extends RefCounted
## Candidate geometry is a REQUEST. Only B's certificate permits execution.
const Roles = preload("res://scripts/tactical_role_plans.gd")
const MAX_OFFERS: int = 8
const MAX_LEG: int = 8
const MAX_POINTS: int = 24
const FIELDS: Array = ["candidateId", "shipId", "targetId", "leaderId", "role", "sector", "approach", "pass", "exit", "fireMountIds", "orderRevision", "snapshotRevision"]

static func valid_path(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_LEG:
		return false
	for point: Variant in value:
		if not point is Vector2 or not is_finite(point.x) or not is_finite(point.y):
			return false
	return true

static func valid_candidate(candidate: Dictionary) -> bool:
	if candidate.size() != FIELDS.size():
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
	return true

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
	return JSON.stringify(canonical).sha256_text()

static func same_request(a: Dictionary, b: Dictionary) -> bool:
	for key: String in FIELDS:
		if key not in ["approach", "pass", "exit"] and a.get(key) != b.get(key):
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

static func _candidate(view: Dictionary, ship: Dictionary, state: Dictionary, target_id: String, sector: int, approach: Array, pass_path: Array, exit_path: Array, fire_mounts: Array, index: int) -> Dictionary:
	var candidate_id: String = "%s:%d:%d:%d" % [str(ship.id).sha256_text().substr(0, 16), int(Roles.number(view.get("snapshotRevision"))), int(Roles.number(ship.get("orderRevision"))), index]
	return {"candidateId": candidate_id, "shipId": str(ship.id), "targetId": target_id, "leaderId": str(state.get("leaderId", "")), "role": str(state.role), "sector": sector, "approach": approach, "pass": pass_path, "exit": exit_path, "fireMountIds": fire_mounts.duplicate(), "orderRevision": int(Roles.number(ship.get("orderRevision"))), "snapshotRevision": int(Roles.number(view.get("snapshotRevision")))}

static func candidates(view: Dictionary, ship: Dictionary, decision: Dictionary, context: Dictionary, reservations: Dictionary = {}) -> Array:
	var state: Dictionary = decision.state
	var protected: Dictionary = Roles.dictionary(context.get(str(state.get("leaderId", ""))))
	var target: Dictionary = Roles.dictionary(context.get(str(state.get("targetId", ""))))
	var position: Vector2 = Roles.pos(ship)
	var phase: String = str(state.phase)
	var order: String = str(ship.get("order", "engage"))
	var opts: Dictionary = Roles.options(view, ship)
	var fire_mounts: Array = []
	for mount: Dictionary in Roles.useful_mounts(view, ship):
		fire_mounts.append(str(mount.id))
	var result: Array = []
	var retreating: bool = phase in ["breakaway", "turn-away", "regroup", "protected"]
	var nonfiring: bool = retreating or phase in ["move", "withdraw", "board"] or target.is_empty()
	if retreating or order in ["move", "hold", "withdraw", "board"] or phase == "hold" or (order == "escort" and protected.is_empty()):
		var goal: Vector2 = rally(view, ship, protected, target) if retreating or order == "withdraw" else _point(ship.get("orderTarget"), position)
		if phase == "hold" and order not in ["move", "hold"]:
			goal = position
		if order == "board" and not target.is_empty():
			goal = Roles.pos(target) + (position - Roles.pos(target)).normalized() * (Roles.radius(ship) + Roles.radius(target) + 12.0)
		if phase == "protected" and protected.is_empty() and target.is_empty():
			goal = position
		elif phase == "protected" and not protected.is_empty():
			var away: Vector2 = (Roles.pos(protected) - Roles.pos(target)).normalized() if not target.is_empty() else -Vector2.from_angle(Roles.number(protected.get("angle")))
			goal = Roles.pos(protected) + away * (Roles.radius(protected) + Roles.radius(ship) + 65.0) + formation_offset(view, ship, protected)
		var defend: bool = not nonfiring and order == "hold" and not fire_mounts.is_empty()
		result.append(_candidate(view, ship, state, str(target.get("id", "")), -1, [position, goal], [goal], [goal], fire_mounts if defend else [], 0))
		# A blocked shot must not prevent a legal nonfiring hold/move/rally.
		if defend:
			result.append(_candidate(view, ship, state, "", -1, [position, goal], [goal], [goal], [], 1))
		elif retreating:
			var away: Vector2 = goal - position
			for side: float in [-1.0, 1.0]:
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
			anchor = _point(state.get("anchor"), anchor)
		var tangent: Vector2 = radial.orthogonal() * (1.0 if sector % 2 == 0 else -1.0)
		var pass_end: Vector2 = Roles.pos(other) + (anchor - Roles.pos(other)).rotated(0.28 if sector % 2 == 0 else -0.28)
		var entry: Vector2 = anchor + radial * 65.0 - tangent * 45.0
		var exit_point: Vector2 = pass_end + radial * 180.0 + tangent * 100.0
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
			if order == "escort" and str(opts.get("formation", "line")) != "screen":
				anchor = Roles.pos(protected) + formation_offset(view, ship, protected).limit_length(leash)
			entry = anchor
			pass_end = anchor
			exit_point = rally(view, ship, protected, other)
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
		var exit_path: Array = [exit_point]
		result.append(_candidate(view, ship, state, str(other.id), sector, approach, pass_path, exit_path, fire_mounts, result.size()))
	var ranked: Array = []
	for candidate: Dictionary in result:
		var station: Vector2 = anchor(candidate)
		var rank: float = position.distance_to(station) / maxf(40.0, Roles.speed(ship))
		# Arc exposure uses only the <=16 shortlisted observed opponents. It is a
		# preference, never a terrain/occupancy test or a reachability certificate.
		var exposure: float = 0.0
		for target_id: String in Roles.array(decision.get("detailedIds")):
			var observed: Dictionary = Roles.dictionary(context.get(target_id))
			if observed.is_empty():
				continue
			for mount: Dictionary in Roles.mounts(observed):
				var delta: Vector2 = station - Roles.pos(observed)
				if delta.length() < Roles.number(mount.get("range")) and absf(angle_difference(Roles.number(observed.get("angle")) + Roles.number(mount.get("angle")), delta.angle())) <= Roles.number(mount.get("arc"), TAU) * 0.5:
					exposure += minf(2.0, Roles.number(mount.get("damage")) * Roles.number(mount.get("fireRate")) / 50.0)
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

static func reservation(candidate: Dictionary, ship: Dictionary, certificate: Dictionary, now: float) -> Dictionary:
	return {"shipId": str(ship.id), "targetId": str(candidate.targetId), "sector": int(candidate.sector), "anchor": anchor(candidate), "radius": Roles.radius(ship) + 8.0, "from": now, "until": now + minf(18.0, maxf(Roles.COMMIT_SECONDS, Roles.number(certificate.get("eta")) + 2.0)), "approach": candidate.approach.duplicate(), "pass": candidate["pass"].duplicate(), "exit": candidate.exit.duplicate()}

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
	var a_path: Array = Roles.array(requested.get("approach")) + Roles.array(requested.get("pass")) + Roles.array(requested.get("exit"))
	var b_path: Array = Roles.array(existing.get("approach")) + Roles.array(existing.get("pass")) + Roles.array(existing.get("exit"))
	for i: int in range(maxi(0, a_path.size() - 1)):
		for j: int in range(maxi(0, b_path.size() - 1)):
			if int(counters.clearanceTests) >= limit:
				counters.clearanceExhausted = int(counters.clearanceExhausted) + 1
				return true
			counters.clearanceTests = int(counters.clearanceTests) + 1
			if _capsules(a_path[i], a_path[i + 1], b_path[j], b_path[j + 1], clearance):
				return true
	return false
