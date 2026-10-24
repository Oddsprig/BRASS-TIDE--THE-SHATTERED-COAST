extends RefCounted
## Candidate geometry is a REQUEST. Only B's certificate permits execution.
const Roles = preload("res://scripts/tactical_role_plans.gd")
const MAX_OFFERS: int = 8
const MAX_LEG: int = 8
const MAX_POINTS: int = 24
const MAX_MOUNT_TARGETS: int = 4
const FIELDS: Array = ["candidateId", "shipId", "targetId", "leaderId", "role", "sector", "approach", "pass", "exit", "fireMountIds", "orderRevision", "snapshotRevision"]

static func valid_path(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_LEG:
		return false
	for point: Variant in value:
		if not point is Vector2 or not is_finite(point.x) or not is_finite(point.y):
			return false
	return true

static func valid_candidate(candidate: Dictionary) -> bool:
	var has_mount_targets: bool = candidate.has("fireMountTargets")
	if candidate.size() != FIELDS.size() + (1 if has_mount_targets else 0):
		return false
	for key: String in FIELDS:
		if not candidate.has(key):
			return false
	for key: String in ["candidateId", "shipId", "role"]:
		if not Roles.id_ok(candidate[key]):
			return false
	for key: String in ["targetId", "leaderId"]:
		if not Roles.id_ok(candidate[key], true):
			return false
	if not candidate.sector is int or candidate.sector < -1 or candidate.sector > 7:
		return false
	if not candidate.snapshotRevision is int or not candidate.orderRevision is int:
		return false
	var total: int = 0
	for key: String in ["approach", "pass", "exit"]:
		if not valid_path(candidate[key]):
			return false
		total += candidate[key].size()
	if total == 0 or total > MAX_POINTS or not candidate.fireMountIds is Array or candidate.fireMountIds.size() > Roles.MAX_MOUNTS:
		return false
	var seen: Dictionary = {}
	for mount_id: Variant in candidate.fireMountIds:
		if not Roles.id_ok(mount_id) or seen.has(mount_id):
			return false
		seen[mount_id] = true
	if has_mount_targets:
		if not candidate.fireMountTargets is Dictionary:
			return false
		var map: Dictionary = candidate.fireMountTargets
		if map.is_empty() or map.size() > candidate.fireMountIds.size() or map.size() > Roles.MAX_MOUNTS:
			return false
		if str(candidate.targetId).is_empty() or candidate.fireMountIds.is_empty():
			return false
		var distinct: Dictionary = {str(candidate.targetId): true}
		for mount_id: Variant in map:
			if not Roles.id_ok(mount_id) or not seen.has(mount_id):
				return false
			var target_id: Variant = map[mount_id]
			if not Roles.id_ok(target_id):
				return false
			distinct[str(target_id)] = true
		if distinct.size() > MAX_MOUNT_TARGETS:
			return false
	return true

static func canonical_mount_targets(candidate: Dictionary) -> Array:
	if not candidate.has("fireMountTargets") or not candidate.get("fireMountTargets") is Dictionary:
		return []
	var raw: Dictionary = candidate.fireMountTargets
	var keys: Array = raw.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	var pairs: Array = []
	for key: Variant in keys:
		pairs.append([str(key), str(raw[key])])
	return pairs

static func has_alt_targets(candidate: Dictionary) -> bool:
	return candidate.has("fireMountTargets")

static func mount_target_id(candidate: Dictionary, mount_id: String) -> String:
	var raw: Dictionary = Roles.dictionary(candidate.get("fireMountTargets"))
	if raw.has(mount_id):
		return str(raw[mount_id])
	return str(candidate.get("targetId", ""))

static func fingerprint(candidate: Dictionary) -> String:
	if not valid_candidate(candidate):
		return ""
	# Fixed field order; paths retain every point, not just endpoints. B calls this.
	var canonical: Array = []
	for key: String in FIELDS:
		if key in ["approach", "pass", "exit"]:
			var leg: Array = []
			for point: Vector2 in candidate[key]:
				leg.append([point.x, point.y])
			canonical.append(leg)
		else:
			canonical.append(candidate[key])
	if candidate.has("fireMountTargets"):
		canonical.append(canonical_mount_targets(candidate))
	return JSON.stringify(canonical).sha256_text()

static func same_request(a: Dictionary, b: Dictionary) -> bool:
	for key: String in FIELDS:
		if key not in ["approach", "pass", "exit"] and a.get(key) != b.get(key):
			return false
	if a.has("fireMountTargets") != b.has("fireMountTargets"):
		return false
	if a.has("fireMountTargets") and canonical_mount_targets(a) != canonical_mount_targets(b):
		return false
	return true

static func _point(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2 and is_finite(value.x) and is_finite(value.y):
		return value
	if value is Dictionary:
		return Vector2(Roles.number(value.get("x"), fallback.x), Roles.number(value.get("y"), fallback.y))
	return fallback

static func rally(view: Dictionary, ship: Dictionary, protected: Dictionary, target: Dictionary) -> Vector2:
	var position: Vector2 = Roles.pos(ship)
	var supplied: Variant = Roles.options(view, ship).get("rally")
	if (supplied is Dictionary and supplied.has("x") and supplied.has("y")) or supplied is Vector2:
		return _point(supplied, position)
	if not protected.is_empty():
		var away: Vector2 = (Roles.pos(protected) - Roles.pos(target)).normalized() if not target.is_empty() else -Vector2.from_angle(Roles.number(protected.get("angle")))
		return Roles.pos(protected) + away * (Roles.radius(protected) + Roles.radius(ship) + 90.0)
	var direction: Vector2 = (position - Roles.pos(target)).normalized() if not target.is_empty() else Vector2.LEFT
	if direction.length_squared() < 0.01:
		direction = Vector2.LEFT if str(ship.get("team", "")) == "player" else Vector2.RIGHT
	return position + direction * maxf(180.0, Roles.speed(ship) * 2.0)

static func _incoming_threat(enemy: Dictionary, protected: Dictionary, leash: float, now: float) -> bool:
	# Only an already shortlisted target is inspected. Formation remains useful
	# in transit; real weapon cover or closing into its bounded protection zone
	# makes the screen interpose instead of crossing behind its protected hull.
	if Roles.threat(enemy, protected, now) > 0.0:
		return true
	var delta: Vector2 = Roles.pos(enemy) - Roles.pos(protected)
	var relative: Vector2 = Roles.velocity(enemy) - Roles.velocity(protected)
	if delta.dot(relative) >= 0.0:
		return false
	var reach: float = 0.0
	for mount: Dictionary in Roles.mounts(enemy):
		reach = maxf(reach, Roles.number(mount.get("range")))
	var closest_time: float = clampf(-delta.dot(relative) / maxf(0.00001, relative.length_squared()), 0.0, 2.0)
	return reach > 0.0 and (delta + relative * closest_time).length() <= reach + leash

static func formation_offset(view: Dictionary, ship: Dictionary, protected: Dictionary) -> Vector2:
	var opts: Dictionary = Roles.options(view, ship)
	var groups: Dictionary = Roles.dictionary(view.get("groups"))
	var group_id: int = int(Roles.number(opts.get("group")))
	var members: Array = Roles.array(groups.get(group_id, groups.get(str(group_id)))).duplicate()
	members.sort()
	var index: int = members.find(str(ship.id))
	if index < 0:
		index = maxi(0, int(Roles.number(ship.get("formationIndex"))))
	var spacing: float = Roles.radius(ship) * 2.0 + 30.0
	var side: float = 1.0 if index % 2 == 0 else -1.0
	var row: int = int(floor(float(index) / 2.0))
	var offset: Vector2 = Vector2(-70.0, side * spacing * float(row + 1))
	if str(opts.get("formation", "line")) == "column":
		offset = Vector2(-spacing * float(index + 2), 0.0)
	elif str(opts.get("formation", "line")) == "screen":
		offset = Vector2(60.0, side * spacing * float(row + 1))
	return offset.rotated(Roles.number(protected.get("angle")))

static func _candidate(view: Dictionary, ship: Dictionary, state: Dictionary, target_id: String, sector: int, approach: Array, pass_path: Array, exit_path: Array, fire_mounts: Array, index: int, mount_targets: Dictionary = {}) -> Dictionary:
	var candidate_id: String = "%s:%d:%d:%d" % [str(ship.id).sha256_text().substr(0, 16), int(Roles.number(view.get("snapshotRevision"))), int(Roles.number(ship.get("orderRevision"))), index]
	var out: Dictionary = {"candidateId": candidate_id, "shipId": str(ship.id), "targetId": target_id, "leaderId": str(state.get("leaderId", "")), "role": str(state.role), "sector": sector, "approach": approach, "pass": pass_path, "exit": exit_path, "fireMountIds": fire_mounts.duplicate(), "orderRevision": int(Roles.number(ship.get("orderRevision"))), "snapshotRevision": int(Roles.number(view.get("snapshotRevision")))}
	if not mount_targets.is_empty():
		var sorted_keys: Array = mount_targets.keys()
		sorted_keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var clean_targets: Dictionary = {}
		for key: Variant in sorted_keys:
			clean_targets[str(key)] = str(mount_targets[key])
		out["fireMountTargets"] = clean_targets
	return out

static func _mount_bears_on(ship: Dictionary, pose_pos: Vector2, pose_angle: float, mount: Dictionary, other: Dictionary) -> bool:
	if other.is_empty() or other.get("team") == ship.get("team") or other.get("sunk", false) or other.get("captureSecured", false):
		return false
	var origin: Vector2 = pose_pos + Vector2(Roles.number(mount.get("x")), Roles.number(mount.get("y"))).rotated(pose_angle)
	var delta: Vector2 = Roles.pos(other) - origin
	var velocity: Vector2 = Roles.velocity(other) - Roles.velocity(ship) * 0.2
	var kind: String = str(mount.get("kind", "gun"))
	var default_speed: float = 240.0 if kind == "torpedo" else (730.0 if kind == "rocket" else (620.0 if kind == "cannon" else 850.0))
	var proj_speed: float = maxf(20.0, Roles.number(mount.get("speed"), default_speed))
	var length: float = Roles.number(mount.get("muzzleDistance"))
	if delta.length() < length + 0.000001:
		return false
	var a: float = velocity.length_squared() - proj_speed * proj_speed
	var b: float = 2.0 * (delta.dot(velocity) - length * proj_speed)
	var c: float = delta.length_squared() - length * length
	var time: float = INF
	if absf(a) < 0.000001:
		if absf(b) > 0.000001 and -c / b > 0.0:
			time = -c / b
	else:
		var discriminant: float = b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var root: float = sqrt(discriminant)
			var q: float = -0.5 * (b + (root if b >= 0.0 else -root))
			var one: float = q / a
			var two: float = c / q if absf(q) > 0.000000001 else -b / (2.0 * a)
			if one > 0.0:
				time = one
			if two > 0.0:
				time = minf(time, two)
	var reach: float = maxf(1.0, Roles.number(mount.get("range"), 400.0))
	if not is_finite(time) or time > reach / proj_speed:
		return false
	var aim: Vector2 = Roles.pos(other) + velocity * time
	if (aim - origin).length() > reach:
		return false
	var bearing: float = (aim - origin).angle()
	var m_arc: float = clampf(Roles.number(mount.get("arc"), TAU), 0.01, TAU)
	return absf(angle_difference(pose_angle + Roles.number(mount.get("angle")), bearing)) <= m_arc * 0.5 + 0.00001

static func _station_heading(ship: Dictionary, station: Vector2, target: Dictionary, mounts: Array) -> float:
	var current_angle: float = Roles.number(ship.get("angle"))
	if target.is_empty() or Roles.turn_rate(ship) <= 0.01:
		return current_angle
	var heading: float = current_angle
	var weight: float = -1.0
	var bearing: float = (Roles.pos(target) - station).angle()
	for mount: Dictionary in mounts:
		if Roles.number(ship.get("ammo")) < Roles.number(mount.get("ammoCost"), 1.0):
			continue
		var value: float = Roles.number(mount.get("damage")) * Roles.number(mount.get("fireRate"))
		if value <= weight:
			continue
		weight = value
		var m_arc: float = clampf(Roles.number(mount.get("arc"), TAU), 0.01, TAU)
		heading = bearing - Roles.number(mount.get("angle")) if m_arc < TAU - 0.01 else bearing
	return wrapf(heading, -PI, PI)

static func _select_mount_targets(view: Dictionary, ship: Dictionary, decision: Dictionary, context: Dictionary, target_id: String, station: Vector2) -> Dictionary:
	var order: String = str(ship.get("order", "engage"))
	if order in ["attack", "board"] or target_id.is_empty():
		return {}
	var useful: Array = Roles.useful_mounts(view, ship)
	if useful.size() <= 1:
		return {}
	var primary_target: Dictionary = Roles.dictionary(context.get(target_id))
	if primary_target.is_empty():
		return {}
	var shortlist_ids: Array = Roles.array(decision.get("targets"))
	if shortlist_ids.size() <= 1:
		return {}
	var position: Vector2 = Roles.pos(ship)
	var current_angle: float = Roles.number(ship.get("angle"))
	var current_primary: Array = []
	for mount: Dictionary in useful:
		if _mount_bears_on(ship, position, current_angle, mount, primary_target):
			current_primary.append(mount)
	var anchor_mounts: Array = current_primary if not current_primary.is_empty() else useful
	var station_angle: float = _station_heading(ship, station, primary_target, anchor_mounts)
	var lead_mount_id: String = ""
	var best_weight: float = -1.0
	for mount: Dictionary in anchor_mounts:
		var weight: float = Roles.number(mount.get("damage")) * Roles.number(mount.get("fireRate"))
		if weight > best_weight:
			best_weight = weight
			lead_mount_id = str(mount.id)
	var assignments: Dictionary = {}
	var distinct: Dictionary = {target_id: true}
	var has_secondary: bool = false
	for mount: Dictionary in useful:
		var mount_id: String = str(mount.id)
		var bears_now: bool = _mount_bears_on(ship, position, current_angle, mount, primary_target)
		var bears_station: bool = _mount_bears_on(ship, station, station_angle, mount, primary_target)
		if mount_id == lead_mount_id or bears_now:
			assignments[mount_id] = target_id
			continue
		var chosen_id: String = ""
		var station_fallback: String = ""
		for raw_id: Variant in shortlist_ids:
			var alt_id: String = str(raw_id)
			if alt_id.is_empty() or alt_id == target_id:
				continue
			if not distinct.has(alt_id) and distinct.size() >= MAX_MOUNT_TARGETS:
				continue
			var alt: Dictionary = Roles.dictionary(context.get(alt_id))
			if alt.is_empty() or alt.get("team") == ship.get("team"):
				continue
			# Prefer a real current arc across the same bounded shortlist before
			# committing this tube to a different, future-only station bearing.
			if _mount_bears_on(ship, position, current_angle, mount, alt):
				chosen_id = alt_id
				break
			if station_fallback.is_empty() and not bears_station and _mount_bears_on(ship, station, station_angle, mount, alt):
				station_fallback = alt_id
		if chosen_id.is_empty():
			chosen_id = station_fallback
		if not chosen_id.is_empty():
			assignments[mount_id] = chosen_id
			distinct[chosen_id] = true
			has_secondary = true
		else:
			assignments[mount_id] = target_id
	return assignments if has_secondary else {}

static func _move_detours(ship: Dictionary, position: Vector2, goal: Vector2, context: Dictionary) -> Array:
	var span: Vector2 = goal - position
	var length: float = span.length()
	if length <= 1.0:
		return []
	var forward: Vector2 = span / length
	var lateral: Vector2 = forward.orthogonal()
	var own_radius: float = Roles.radius(ship)
	var blocker: Dictionary = {}
	var best_along: float = INF
	for other: Dictionary in context.values():
		if other.get("team") != ship.get("team") or str(other.get("id", "")) == str(ship.get("id", "")):
			continue
		var rel: Vector2 = Roles.pos(other) - position
		var along: float = rel.dot(forward)
		var across: float = absf(rel.dot(lateral))
		var limit: float = own_radius + Roles.radius(other) + 36.0
		if along >= -own_radius and along <= length + own_radius and across <= limit and along < best_along:
			blocker = other
			best_along = along
	if blocker.is_empty():
		return []
	var center: Vector2 = Roles.pos(blocker)
	var signed_across: float = (center - position).dot(lateral)
	var first_side: float = -1.0 if signed_across > 0.0 else 1.0
	var sides: Array = [first_side, -first_side]
	var base: float = own_radius + Roles.radius(blocker)
	var lead: float = clampf(base + 24.0, 36.0, maxf(36.0, length * 0.35))
	var result: Array = []
	for margin: float in [base + 28.0, base + 56.0]:
		for side: float in sides:
			var wp: Vector2 = center + lateral * (side * margin)
			result.append([position, wp, goal])
	for side: float in sides:
		var offset: Vector2 = lateral * (side * (base + 36.0))
		result.append([position, center - forward * lead + offset, center + forward * lead + offset, goal])
	return result

static func candidates(view: Dictionary, ship: Dictionary, decision: Dictionary, context: Dictionary, reservations: Dictionary = {}) -> Array:
	var state: Dictionary = decision.state
	var protected: Dictionary = Roles.dictionary(context.get(str(state.get("leaderId", ""))))
	var target: Dictionary = Roles.dictionary(context.get(str(state.get("targetId", ""))))
	var position: Vector2 = Roles.pos(ship)
	var phase: String = str(state.phase)
	var order: String = str(ship.get("order", "engage"))
	var opts: Dictionary = Roles.options(view, ship)
	var fire_mounts: Array = []
	var longest_reach: float = 0.0
	var has_gun: bool = false
	for mount: Dictionary in Roles.useful_mounts(view, ship):
		fire_mounts.append(str(mount.id))
		var life: float = Roles.number(mount.get("range")) / maxf(1.0, Roles.number(mount.get("speed"), 300.0))
		var muzzle_reach: float = Vector2(Roles.number(mount.get("x")), Roles.number(mount.get("y"))).length() + Roles.number(mount.get("muzzleDistance"))
		longest_reach = maxf(longest_reach, Roles.number(mount.get("range")) + Roles.velocity(ship).length() * 0.2 * life + muzzle_reach)
		if not Roles.fixed_tube(mount):has_gun = true
	var result: Array = []
	var retreating: bool = phase in ["breakaway", "turn-away", "regroup", "protected"]
	var nonfiring: bool = retreating or phase in ["move", "withdraw", "board"] or target.is_empty()
	if Roles.speed(ship) <= 0.01 and order not in ["move", "board"]:
		if not nonfiring and not target.is_empty() and not fire_mounts.is_empty() and Roles.turn_rate(ship) > 0.01:
			var stationary_targets: Dictionary = _select_mount_targets(view, ship, decision, context, str(target.get("id", "")), position)
			result.append(_candidate(view, ship, state, str(target.get("id", "")), 0, [position], [position], [position], fire_mounts, 0, stationary_targets))
		result.append(_candidate(view, ship, state, "", -1, [position], [position], [position], [], result.size()))
		return result
	if retreating or order in ["move", "hold", "withdraw", "board"] or phase == "hold" or (order == "escort" and protected.is_empty()):
		var goal: Vector2 = rally(view, ship, protected, target) if retreating or order == "withdraw" else _point(ship.get("orderTarget"), position)
		if phase == "hold" and order not in ["move", "hold"]:
			goal = position
		if order == "board" and not retreating and not target.is_empty():
			goal = Roles.pos(target) + (position - Roles.pos(target)).normalized() * (Roles.radius(ship) + Roles.radius(target) + 12.0)
		if phase == "protected" and protected.is_empty() and target.is_empty():
			goal = position
		elif phase == "protected" and not protected.is_empty():
			var away: Vector2 = (Roles.pos(protected) - Roles.pos(target)).normalized() if not target.is_empty() else -Vector2.from_angle(Roles.number(protected.get("angle")))
			goal = Roles.pos(protected) + away * (Roles.radius(protected) + Roles.radius(ship) + 65.0) + formation_offset(view, ship, protected)
		var defend: bool = not nonfiring and order == "hold" and not fire_mounts.is_empty()
		var move_target_id: String = str(target.get("id", "")) if (defend or order == "board") else ""
		var hold_targets: Dictionary = _select_mount_targets(view, ship, decision, context, str(target.get("id", "")), goal) if defend else {}
		result.append(_candidate(view, ship, state, str(target.get("id", "")), -1, [position, goal], [goal], [goal], fire_mounts if defend else [], 0, hold_targets))
		# A blocked shot must not prevent a legal nonfiring hold/move/rally.
		if defend:
			result.append(_candidate(view, ship, state, "", -1, [position, goal], [goal], [goal], [], 1))
		if Roles.speed(ship) > 0.01 and position.distance_to(goal) > 1.0 and (order in ["move", "withdraw", "board"] or retreating):
			for detour: Array in _move_detours(ship, position, goal, context):
				if result.size() >= MAX_OFFERS:
					break
				result.append(_candidate(view, ship, state, move_target_id, -1, detour, [goal], [goal], [], result.size()))
		if retreating:
			var away: Vector2 = goal - position
			for side: float in [-1.0, 1.0]:
				if result.size() >= MAX_OFFERS:
					break
				var alternate: Vector2 = position + away.rotated(side * 0.55)
				result.append(_candidate(view, ship, state, "", -1, [position, alternate], [alternate], [alternate], [], result.size()))
		return result
	if target.is_empty():
		return [_candidate(view, ship, state, "", -1, [position], [position], [position], [], 0)]
	var sectors: Array = [1, 5, 2, 4, 0, 3, 6, 7]
	var sector_seed: Array = [2, 6, 3, 5, 1, 7, 4, 0]
	var seed_sector: int = int(sector_seed[int(Roles.number(ship.get("formationIndex"))) % 8])
	sectors.erase(seed_sector)
	sectors.push_front(seed_sector)
	var old_sector: int = int(Roles.number(state.get("sector"), -1.0))
	if old_sector >= 0 and old_sector < 8 and Roles.number(state.get("commitUntil")) > Roles.number(view.get("time")):
		sectors.erase(old_sector)
		sectors.push_front(old_sector)
	var targets: Array = Roles.array(decision.get("targets"))
	var incoming_by_target: Dictionary = {}
	for i: int in range(MAX_OFFERS):
		var target_index: int = 1 if i >= 6 and targets.size() > 1 and order not in ["attack", "board"] else 0
		var other: Dictionary = Roles.dictionary(context.get(str(targets[target_index])))
		if other.is_empty():
			continue
		var sector: int = int(sectors[i])
		var course: float = Roles.velocity(other).angle() if Roles.velocity(other).length() > 2.0 else Roles.number(other.get("angle"))
		var angle: float = course + float(sector) * TAU / 8.0
		var reach: float = float(decision.range)
		var separation: float = maxf(Roles.radius(ship) + Roles.radius(other) + 45.0, reach * 0.62)
		var radial: Vector2 = Vector2.from_angle(angle)
		var anchor: Vector2 = Roles.pos(other) + radial * separation
		if sector == old_sector and str(other.id) == str(state.get("targetId", "")) and Roles.number(state.get("commitUntil")) > Roles.number(view.get("time")):
			var committed_anchor: Vector2 = _point(state.get("anchor"), anchor)
			if committed_anchor.distance_to(Roles.pos(other)) <= reach * 0.95:
				anchor = committed_anchor
				if anchor.distance_squared_to(Roles.pos(other)) > 1.0:
					radial = (anchor - Roles.pos(other)).normalized()
		var tangent: Vector2 = radial.orthogonal() * (1.0 if sector % 2 == 0 else -1.0)
		var pass_end: Vector2 = Roles.pos(other) + (anchor - Roles.pos(other)).rotated(0.28 if sector % 2 == 0 else -0.28)
		var entry: Vector2 = anchor
		var exit_point: Vector2 = pass_end + radial * 180.0 + tangent * 100.0
		var screen_exit_corner: Variant = null
		if str(state.role) == "striker":
			var launch_heading: float = (Roles.pos(other) - anchor).angle()
			for mount: Dictionary in Roles.useful_mounts(view, ship):
				if Roles.fixed_tube(mount):
					launch_heading -= Roles.number(mount.get("angle"))
					break
			var forward: Vector2 = Vector2.from_angle(launch_heading)
			entry = anchor - forward * maxf(65.0, Roles.speed(ship) * 0.65)
			pass_end = anchor + forward * minf(90.0, separation * 0.3)
			exit_point = pass_end + radial * 180.0 + tangent * 130.0
			if phase == "launch-window" and str(other.id) == str(state.get("targetId", "")):
				# Already aligned: do not first drive backwards to a distant staging point.
				entry = position
				anchor = position
				pass_end = position + Vector2.from_angle(Roles.number(ship.get("angle"))) * 60.0
				exit_point = pass_end + (position - Roles.pos(other)).normalized() * 180.0 + tangent * 130.0
		elif str(state.role) == "screen" and not protected.is_empty():
			var leash: float = maxf(Roles.radius(protected) + Roles.radius(ship) + 35.0, minf(Roles.number(opts.get("leash"), 600.0), maxf(240.0, reach)))
			var threat_direction: Vector2 = (Roles.pos(other) - Roles.pos(protected)).normalized()
			var lateral: Vector2 = threat_direction.orthogonal() * float((sector % 3) - 1) * (Roles.radius(ship) * 2.0 + 18.0)
			anchor = Roles.pos(protected) + (threat_direction * minf(leash * 0.6, separation * 0.6) + lateral).limit_length(leash)
			if not incoming_by_target.has(str(other.id)):
				incoming_by_target[str(other.id)] = _incoming_threat(other, protected, leash, Roles.number(view.get("time")))
			if order == "escort" and str(opts.get("formation", "line")) != "screen" and not bool(incoming_by_target[str(other.id)]):
				anchor = Roles.pos(protected) + formation_offset(view, ship, protected).limit_length(leash)
			entry = anchor
			pass_end = anchor
			exit_point = rally(view, ship, protected, other)
			if (anchor - Roles.pos(protected)).dot(threat_direction) > 0.0:
				# A front screen needs an actual exit AROUND its protected hull.
				# The direct chord to the rear rally crosses that friendly. B still
				# checks both bounded segments, including the moving ally's occupancy.
				var exit_side: float = signf((anchor - Roles.pos(protected)).dot(threat_direction.orthogonal()))
				if exit_side == 0.0:exit_side = 1.0 if sector % 2 == 0 else -1.0
				screen_exit_corner = Roles.pos(protected) + threat_direction.orthogonal() * exit_side * (Roles.radius(protected) + Roles.radius(ship) + 35.0)
		elif str(state.role) == "heavy":
			# Pressure stations stay modest; hull rotation brings working arcs to bear.
			var toward: Vector2 = (Roles.pos(other) - position).normalized()
			var advance: float = clampf(position.distance_to(Roles.pos(other)) - reach * 0.72, -60.0, 150.0)
			anchor = position + toward * advance + toward.orthogonal() * float((sector % 3) - 1) * (Roles.radius(ship) * 2.0 + 24.0)
			entry = anchor
			pass_end = anchor
			exit_point = rally(view, ship, protected, other)
		var approach: Array = [position, entry, anchor]
		var pass_path: Array = [anchor, pass_end]
		var exit_path: Array = []
		if screen_exit_corner is Vector2:exit_path.append(screen_exit_corner)
		exit_path.append(exit_point)
		var pass_targets: Dictionary = _select_mount_targets(view, ship, decision, context, str(other.id), anchor)
		var requested_fire: Array = fire_mounts
		if str(state.role) == "screen":
			var potential_fire: bool = false
			for mount: Dictionary in Roles.useful_mounts(view, ship):
				var bound: Dictionary = Roles.dictionary(context.get(str(pass_targets.get(str(mount.id), other.id))))
				if bound.is_empty():continue
				var reach_with_inheritance: float = Roles.number(mount.get("range")) * (1.0 + Roles.velocity(ship).length() * 0.2 / maxf(1.0, Roles.number(mount.get("speed"), 300.0)))
				if minf(position.distance_to(Roles.pos(bound)), anchor.distance_to(Roles.pos(bound))) <= reach_with_inheritance:
					potential_fire = true
					break
			if not potential_fire:
				# Reaching an intercept station does not require an enemy already
				# inside its firing window. This nonfiring request still needs the
				# exact same physical approach/exit certificate and live safety step.
				requested_fire = []
				pass_targets = {}
		var stage_distance: float = maxf(80.0, Roles.speed(ship) * 2.0)
		if order == "engage" and str(state.role) == "skirmisher" and phase == "approach" and has_gun and position.distance_to(Roles.pos(other)) > longest_reach + Roles.radius(other) + 1.0 and position.distance_to(entry) > stage_distance:
			# This complete NONFIRING local maneuver ends at a stopping station.
			# It certifies no continuation or exit at the remote firing anchor.
			# The chosen sector still supplies the approach direction; B checks
			# all offered geometry, the real physical prefix and every live step.
			var local_station: Vector2 = position.move_toward(entry, stage_distance)
			approach = [position, local_station]
			pass_path = [local_station]
			exit_path = [local_station]
			requested_fire = []
			pass_targets = {}
		result.append(_candidate(view, ship, state, str(other.id), sector, approach, pass_path, exit_path, requested_fire, result.size(), pass_targets))
	# Only invariant observations are hoisted. Each offered station still
	# recomputes its own range/arc exposure, in the original summation order.
	var hostile_descriptors: Array = []
	for target_id: String in Roles.array(decision.get("detailedIds")):
		var observed: Dictionary = Roles.dictionary(context.get(target_id))
		if observed.is_empty():
			continue
		var described_mounts: Array = []
		for mount: Dictionary in Roles.mounts(observed):
			described_mounts.append({"range": Roles.number(mount.get("range")), "heading": Roles.number(observed.get("angle")) + Roles.number(mount.get("angle")), "halfArc": Roles.number(mount.get("arc"), TAU) * 0.5, "weight": minf(2.0, Roles.number(mount.get("damage")) * Roles.number(mount.get("fireRate")) / 50.0)})
		hostile_descriptors.append({"position": Roles.pos(observed), "mounts": described_mounts})
	var ranked: Array = []
	for candidate: Dictionary in result:
		var station: Vector2 = anchor(candidate)
		var rank: float = position.distance_to(station) / maxf(40.0, Roles.speed(ship))
		# Arc exposure uses only the <=16 shortlisted observed opponents. It is a
		# preference, never a terrain/occupancy test or a reachability certificate.
		var exposure: float = 0.0
		for hostile: Dictionary in hostile_descriptors:
			var delta: Vector2 = station - hostile.position
			for mount: Dictionary in hostile.mounts:
				if delta.length() < float(mount.range) and absf(angle_difference(float(mount.heading), delta.angle())) <= float(mount.halfArc):
					exposure += float(mount.weight)
		rank += exposure * 2.0
		if candidate.targetId != str(state.get("targetId", "")):
			rank += 1.0
		if int(candidate.sector) == old_sector and Roles.number(state.get("commitUntil")) > Roles.number(view.get("time")):
			rank -= 100.0
		for other_id: Variant in reservations:
			var occupied: Dictionary = Roles.dictionary(reservations[other_id])
			if str(other_id) != str(ship.id) and Roles.number(occupied.get("until")) > Roles.number(view.get("time")) and occupied.get("targetId") == candidate.targetId and occupied.get("sector") == candidate.sector:
				rank += 100.0
				break
		# A screen must try its chosen protection target before incidental targets.
		# Keep alternatives for genuinely blocked, rejected or occupied offers.
		var primary_screen: bool = str(state.role) == "screen" and phase == "screen" and candidate.targetId == str(state.get("targetId", ""))
		ranked.append({"candidate": candidate, "rank": rank, "primaryScreen": primary_screen})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.primaryScreen) != bool(b.primaryScreen):
			return bool(a.primaryScreen)
		return float(a.rank) < float(b.rank) if not is_equal_approx(float(a.rank), float(b.rank)) else str(a.candidate.candidateId) < str(b.candidate.candidateId)
	)
	result = []
	for entry: Dictionary in ranked:
		result.append(entry.candidate)
	return result

static func anchor(candidate: Dictionary) -> Vector2:
	if candidate.get("anchor") is Vector2:
		return candidate.anchor
	var pass_path: Array = Roles.array(candidate.get("pass"))
	var approach: Array = Roles.array(candidate.get("approach"))
	return pass_path[0] if not pass_path.is_empty() else (approach[-1] if not approach.is_empty() else Vector2.ZERO)

static func reservation_shape(candidate: Dictionary, ship: Dictionary) -> Dictionary:
	# Geometry only. This is neither a certificate nor permission to execute.
	return {"shipId": str(ship.id), "targetId": str(candidate.targetId), "sector": int(candidate.sector), "anchor": anchor(candidate), "radius": Roles.radius(ship) + 8.0, "approach": candidate.approach.duplicate(), "pass": candidate["pass"].duplicate(), "exit": candidate.exit.duplicate()}

static func reservation(candidate: Dictionary, ship: Dictionary, certificate: Dictionary, now: float) -> Dictionary:
	var result: Dictionary = reservation_shape(candidate, ship)
	result["from"] = now
	result["until"] = now + minf(18.0, maxf(Roles.COMMIT_SECONDS, Roles.number(certificate.get("eta")) + 2.0))
	return result

static func _distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var delta: Vector2 = b - a
	return point.distance_to(a + delta * clampf((point - a).dot(delta) / maxf(0.00001, delta.length_squared()), 0.0, 1.0))

static func _capsules(a: Vector2, b: Vector2, c: Vector2, d: Vector2, clearance: float) -> bool:
	var delta: Vector2 = b - a
	var edge: Vector2 = d - c
	var denominator: float = delta.cross(edge)
	if absf(denominator) > 0.000001:
		var along: float = (c - a).cross(edge) / denominator
		var across: float = (c - a).cross(delta) / denominator
		if along >= 0.0 and along <= 1.0 and across >= 0.0 and across <= 1.0:
			return true
	return minf(minf(_distance(a, c, d), _distance(b, c, d)), minf(_distance(c, a, b), _distance(d, a, b))) < clearance

static func conflict(requested: Dictionary, existing: Dictionary, counters: Dictionary, limit: int) -> bool:
	# Count occupancy primitives before execution. Exhaustion is a pending decision.
	if int(counters.clearanceTests) >= limit:
		counters.clearanceExhausted = int(counters.clearanceExhausted) + 1
		return true
	counters.clearanceTests = int(counters.clearanceTests) + 1
	for key: String in ["approach", "pass", "exit"]:
		if not valid_path(existing.get(key)):
			return true
	var clearance: float = Roles.number(requested.get("radius")) + Roles.number(existing.get("radius"))
	if anchor(requested).distance_to(anchor(existing)) < clearance:
		return true
	if str(requested.get("targetId", "")) != "" and requested.targetId == existing.get("targetId") and int(requested.sector) >= 0 and int(requested.sector) == int(Roles.number(existing.get("sector"), -1.0)):
		return true
	# Complete swept path reservations, including the exits, conservatively overlap in time.
	var lane_clearance: float = maxf(0.0, clearance - 9.0)
	var a_path: Array = Roles.array(requested.get("approach")) + Roles.array(requested.get("pass")) + Roles.array(requested.get("exit"))
	var b_path: Array = Roles.array(existing.get("approach")) + Roles.array(existing.get("pass")) + Roles.array(existing.get("exit"))
	for i: int in range(maxi(0, a_path.size() - 1)):
		for j: int in range(maxi(0, b_path.size() - 1)):
			if int(counters.clearanceTests) >= limit:
				counters.clearanceExhausted = int(counters.clearanceExhausted) + 1
				return true
			counters.clearanceTests = int(counters.clearanceTests) + 1
			if _capsules(a_path[i], a_path[i + 1], b_path[j], b_path[j + 1], lane_clearance):
				return true
	return false
