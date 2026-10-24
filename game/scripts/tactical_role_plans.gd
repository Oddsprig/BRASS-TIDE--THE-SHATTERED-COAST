extends RefCounted
## Pure observations and role/phase decisions. Never changes a snapshot or real stores.
const MAX_TARGETS: int = 16
const MAX_MOUNTS: int = 16
const COMMIT_SECONDS: float = 1.2
const PURSUIT_SECONDS: float = 18.0
const HP_WINDOW_SECONDS: float = 2.0
const HP_BUCKET_SECONDS: float = 1.0 / 3.0
const MAX_HP_BUCKETS: int = 8
const ROLES: Array = ["auto", "skirmisher", "striker", "screen", "heavy", "support"]

static func number(value: Variant, fallback: float = 0.0) -> float:
	return float(value) if (value is int or value is float) and is_finite(float(value)) else fallback

static func dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

static func array(value: Variant) -> Array:
	return value if value is Array else []

static func id_ok(value: Variant, empty: bool = false) -> bool:
	return value is String and value.length() <= 128 and (empty or not value.is_empty())

static func pos(ship: Dictionary) -> Vector2:
	return Vector2(number(ship.get("x")), number(ship.get("y")))

static func velocity(ship: Dictionary) -> Vector2:
	return Vector2(number(ship.get("vx")), number(ship.get("vy")))

static func active(ship: Dictionary) -> bool:
	return id_ok(ship.get("id")) and not ship.get("sunk", false) and not ship.get("captureSecured", false)

static func ships_by_id(view: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw: Variant in array(view.get("ships")):
		if raw is Dictionary and active(raw):
			result[raw.id] = raw
	return result

static func options(view: Dictionary, ship: Dictionary) -> Dictionary:
	var all_options: Dictionary = dictionary(view.get("options"))
	return dictionary(dictionary(all_options.get("byId")).get(str(ship.get("id", ""))))

static func mounts(ship: Dictionary) -> Array:
	var result: Array = []
	for raw: Variant in array(ship.get("mounts")):
		if result.size() >= MAX_MOUNTS:
			break
		if raw is Dictionary and id_ok(raw.get("id")) and str(raw.get("kind", "")) in ["gun", "cannon", "rocket", "torpedo"]:
			result.append(raw)
	return result

static func fixed_tube(mount: Dictionary) -> bool:
	return str(mount.get("kind", "")) in ["rocket", "torpedo"] and number(mount.get("arc"), TAU) < PI * 0.75

static func speed(ship: Dictionary) -> float:
	var spec: Dictionary = dictionary(ship.get("spec"))
	var status: Dictionary = dictionary(ship.get("status"))
	return maxf(0.0, number(spec.get("speed"))) * clampf(number(status.get("speedFactor"), 1.0), 0.0, 1.0) * (1.0 if number(ship.get("fuel"), 1.0) > 0.0 else 0.2)

static func radius(ship: Dictionary) -> float:
	return maxf(10.0, number(dictionary(ship.get("spec")).get("size"), 16.0))

static func useful_mounts(view: Dictionary, ship: Dictionary) -> Array:
	var result: Array = []
	var opts: Dictionary = options(view, ship)
	var mount_options: Dictionary = dictionary(opts.get("mounts"))
	for mount: Dictionary in working_mounts(ship):
		var settings: Dictionary = dictionary(mount_options.get(str(mount.id)))
		var reserve: float = maxf(0.0, number(settings.get("reserve")))
		if not settings.get("hold", false) and number(ship.get("ammo")) - reserve >= number(mount.get("ammoCost"), 1.0) and number(mount.get("damage"), 1.0) > 0.0:
			result.append(mount)
	return result

static func working_mounts(ship: Dictionary) -> Array:
	var result: Array = []
	if number(dictionary(ship.get("status")).get("weaponFactor"), 1.0) <= 0.01:
		return result
	for mount: Dictionary in mounts(ship):
		if number(ship.get("ammo")) >= number(mount.get("ammoCost"), 1.0) and number(mount.get("damage"), 1.0) > 0.0:
			result.append(mount)
	return result

static func useful_range(view: Dictionary, ship: Dictionary) -> float:
	var choices: Array = useful_mounts(view, ship)
	if choices.is_empty():
		choices = working_mounts(ship)
	var result: float = 80.0
	var best: float = -1.0
	for mount: Dictionary in choices:
		var weight: float = number(mount.get("damage"), 1.0) * number(mount.get("fireRate"), 1.0)
		if weight > best:
			best = weight
			result = maxf(80.0, number(mount.get("range"), 80.0))
	return result

static func leader(view: Dictionary, ship: Dictionary, context: Dictionary) -> Dictionary:
	var opts: Dictionary = options(view, ship)
	var order: String = str(ship.get("order", "engage"))
	var target: Dictionary = dictionary(ship.get("orderTarget"))
	var named: String = str(target.get("shipId", "")) if order == "escort" else str(opts.get("protectedAllyId", ""))
	if not named.is_empty():
		var explicit_leader: Dictionary = dictionary(context.get(named))
		return explicit_leader if explicit_leader.get("team") == ship.get("team") and named != ship.id else {}
	var group_id: int = int(number(opts.get("group")))
	var groups: Dictionary = dictionary(view.get("groups"))
	var group: Array = array(groups.get(group_id, groups.get(str(group_id))))
	var ally_uids: Array = array(dictionary(view.get("mission")).get("allyUids"))
	var best: Dictionary = {}
	var best_score: float = -INF
	for other: Dictionary in context.values():
		if other.get("team") != ship.get("team") or other.id == ship.id:
			continue
		if group_id > 0 and not str(other.id) in group:
			continue
		var score: float = radius(other) * 3.0 - pos(ship).distance_to(pos(other)) * 0.04
		if str(other.get("uid", "")) in ally_uids:
			score += 500.0
		if str(options(view, other).get("role", "")) == "support":
			score += 300.0
		if score > best_score or (is_equal_approx(score, best_score) and str(other.id) < str(best.get("id", "~"))):
			best = other
			best_score = score
	return best

static func infer_role(view: Dictionary, ship: Dictionary) -> String:
	var requested: String = str(options(view, ship).get("role", "auto"))
	if requested in ROLES and requested != "auto":
		return requested
	if str(ship.get("order", "engage")) == "escort":
		return "screen"
	if not str(options(view, ship).get("protectedAllyId", "")).is_empty():
		return "screen"
	if str(ship.get("uid", "")) in array(dictionary(view.get("mission")).get("allyUids")):
		return "support"
	var useful: Array = working_mounts(ship)
	if useful.is_empty():
		return "support"
	for mount: Dictionary in useful:
		if fixed_tube(mount):
			return "striker"
	var spec: Dictionary = dictionary(ship.get("spec"))
	if str(spec.get("role", "")) in ["support", "civilian", "cargo", "tanker", "yacht", "fishing"]:
		return "support"
	return "skirmisher" if radius(ship) <= 24.0 and speed(ship) >= 95.0 else "heavy"

static func threat(enemy: Dictionary, ally: Dictionary, now: float) -> float:
	if ally.is_empty():
		return 0.0
	var delta: Vector2 = pos(ally) - pos(enemy)
	var result: float = 0.0
	for mount: Dictionary in mounts(enemy):
		var reach: float = maxf(1.0, number(mount.get("range"), 80.0))
		var bearing: float = number(enemy.get("angle")) + number(mount.get("angle"))
		if delta.length() <= reach * 1.15 and absf(angle_difference(bearing, delta.angle())) <= number(mount.get("arc"), TAU) * 0.5 + 0.15:
			result = maxf(result, 1.0 - clampf(delta.length() / (reach * 1.6), 0.0, 0.8))
	var recent: float = -1.0
	for stamp: Variant in dictionary(enemy.get("mountShotTimes")).values():
		recent = maxf(recent, number(stamp, -1.0))
	return result * (1.5 if recent >= 0.0 and now - recent <= 2.0 else 1.0)

static func _geometric_insert(entries: Array, id: String, cost: float) -> void:
	var at: int = 0
	while at < entries.size() and (float(entries[at].cost) < cost or (is_equal_approx(float(entries[at].cost), cost) and str(entries[at].id) < id)):
		at += 1
	if at < MAX_TARGETS:
		entries.insert(at, {"id": id, "cost": cost})
		if entries.size() > MAX_TARGETS:
			entries.pop_back()

static func shortlist(view: Dictionary, ship: Dictionary, context: Dictionary, protected: Dictionary) -> Array:
	var target: Dictionary = dictionary(ship.get("orderTarget"))
	var named: String = str(target.get("shipId", "")) if str(ship.get("order", "")) in ["attack", "board"] else ""
	var near_ship: Array = []
	var near_ally: Array = []
	# ALL-context broad phase is positions/velocities only: no arcs, fits, shots,
	# threat(), or role scoring before the sixteen-candidate boundary.
	for other: Dictionary in context.values():
		if other.get("team") == ship.get("team"):
			continue
		if not named.is_empty():
			if str(other.id) == named:
				return [{"id": named, "cost": 0.0}]
			continue
		_geometric_insert(near_ship, str(other.id), pos(ship).distance_squared_to(pos(other)))
		if not protected.is_empty():
			var delta: Vector2 = pos(other) - pos(protected)
			var relative: Vector2 = velocity(other) - velocity(protected)
			var closest_time: float = clampf(-delta.dot(relative) / maxf(0.00001, relative.length_squared()), 0.0, 2.0)
			_geometric_insert(near_ally, str(other.id), (delta + relative * closest_time).length_squared())
	var result: Array = []
	var seen: Dictionary = {}
	# Alternate ally-interception and local-nearest geometric candidates. Close
	# protection threats cannot be crowded out by sixteen nearer distant decoys.
	for i: int in range(MAX_TARGETS):
		for pool: Array in [near_ally, near_ship]:
			if i >= pool.size() or result.size() >= MAX_TARGETS:
				continue
			var entry: Dictionary = pool[i]
			if not seen.has(str(entry.id)):
				result.append(entry)
				seen[str(entry.id)] = true
	return result

static func choose_target(view: Dictionary, ship: Dictionary, previous: Dictionary, context: Dictionary, protected: Dictionary, role: String) -> Dictionary:
	var scored: Array = []
	var reach: float = useful_range(view, ship)
	var now: float = number(view.get("time"))
	var detailed_ids: Array = []
	for entry: Dictionary in shortlist(view, ship, context, protected):
		detailed_ids.append(str(entry.id))
		if str(entry.id) == str(previous.get("failedTargetId", "")) and now < number(previous.get("failedUntil")):
			continue
		var other: Dictionary = context[entry.id]
		var distance: float = pos(ship).distance_to(pos(other))
		if str(ship.get("order", "engage")) == "engage" and str(entry.id) in array(ship.get("failedTargetIds")) and distance > reach * 0.85:
			continue
		var vulnerability: float = 1.0 - clampf(number(other.get("hp"), 1.0) / maxf(1.0, number(other.get("maxHp"), 1.0)), 0.0, 1.0)
		vulnerability += clampf(number(other.get("fire")) / 100.0 + number(other.get("water")) / maxf(1.0, number(other.get("capacity"), 200.0)), 0.0, 1.0)
		var fit: float = 1.0 if (role == "striker" and radius(other) > radius(ship)) or (role == "heavy" and radius(other) < radius(ship)) else 0.0
		var access: float = 1.0 if distance <= reach else 0.0
		var cost: float = distance / maxf(80.0, reach)
		var score: float = 3.0 * threat(other, protected, now) + 2.0 * fit + 2.0 * access + vulnerability - cost
		if str(previous.get("targetId", "")) == entry.id:
			score += 0.6
		scored.append({"id": entry.id, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score) if not is_equal_approx(float(a.score), float(b.score)) else str(a.id) < str(b.id))
	if scored.is_empty():
		return {"targetId": "", "targets": [], "scored": detailed_ids.size(), "detailedIds": detailed_ids}
	var selected: String = str(scored[0].id)
	var old_id: String = str(previous.get("targetId", ""))
	for entry: Dictionary in scored:
		if entry.id != old_id:
			continue
		if now < number(previous.get("commitUntil")) or float(scored[0].score) - float(entry.score) < maxf(0.5, absf(float(entry.score)) * 0.2):
			selected = old_id
		break
	var targets: Array = [selected]
	for entry: Dictionary in scored:
		if entry.id != selected:
			targets.append(entry.id)
	return {"targetId": selected, "targets": targets, "scored": detailed_ids.size(), "detailedIds": detailed_ids}

static func hp_history(now: float, hp: float, previous: Array) -> Dictionary:
	# Eight FIXED TIME buckets cover the two-second window even at duel cadence.
	# Each stored HP and timestamp is an actual observation, never interpolated.
	# At the oldest partial bucket use a still-in-window peak or its last actual
	# sample conservatively; never count an expired peak as recent damage.
	var observations: Array = []
	var cutoff: float = now - HP_WINDOW_SECONDS
	var bucket_id: int = int(floor(now / HP_BUCKET_SECONDS))
	for raw: Variant in previous:
		if not raw is Dictionary:
			continue
		var record: Dictionary = raw.duplicate(true)
		if number(record.get("lastAt"), -INF) >= cutoff and number(record.get("lastAt"), INF) <= now:
			observations.append(record)
	var current: Dictionary = {"bucket": bucket_id, "peakAt": now, "peakHp": hp, "lastAt": now, "lastHp": hp}
	if not observations.is_empty() and int(number(dictionary(observations[-1]).get("bucket"), -1.0)) == bucket_id:
		current = observations.pop_back()
		if hp > number(current.get("peakHp"), hp):
			current.peakHp = hp
			current.peakAt = now
		current.lastAt = now
		current.lastHp = hp
	observations.append(current)
	while observations.size() > MAX_HP_BUCKETS:
		observations.pop_front()
	var baseline: float = hp
	for record: Dictionary in observations:
		if number(record.get("peakAt"), -INF) >= cutoff:
			baseline = maxf(baseline, number(record.get("peakHp"), hp))
		elif number(record.get("lastAt"), -INF) >= cutoff:
			baseline = maxf(baseline, number(record.get("lastHp"), hp))
	return {"observations": observations, "loss": maxf(0.0, baseline - hp)}

static func decide(view: Dictionary, ship: Dictionary, previous: Dictionary, context: Dictionary) -> Dictionary:
	var now: float = number(view.get("time"))
	var opts: Dictionary = options(view, ship)
	var order: String = str(ship.get("order", "engage"))
	var revision: int = int(number(ship.get("orderRevision")))
	var changed_order: bool = not previous.is_empty() and int(number(previous.get("orderRevision"))) != revision
	var state: Dictionary = {}
	# Fixed private record schema. No accumulating proposal/certificate/target cache.
	for key: String in ["role", "phase", "reason", "targetId", "leaderId", "orderRevision", "phaseSince", "passSince", "pursuitSince", "progressAt", "progressPos", "commitUntil", "safeSince", "lastUsefulShot", "failedTargetId", "failedUntil", "passSequence", "firingPassId", "sector", "anchor", "waitSince", "blockedStation", "launchPos", "breakawayFrom"]:
		if previous.has(key):
			state[key] = previous[key]
	var protected: Dictionary = leader(view, ship, context)
	var retained_leader: Dictionary = dictionary(context.get(str(previous.get("leaderId", ""))))
	var group_id: int = int(number(opts.get("group")))
	var group: Array = array(dictionary(view.get("groups")).get(group_id, dictionary(view.get("groups")).get(str(group_id))))
	if not changed_order and order != "escort" and str(opts.get("protectedAllyId", "")).is_empty() and not retained_leader.is_empty() and retained_leader.get("team") == ship.get("team") and (group_id == 0 or str(retained_leader.id) in group):
		protected = retained_leader
	var role: String = infer_role(view, ship)
	var target_choice: Dictionary = choose_target(view, ship, {} if changed_order else previous, context, protected, role)
	var target: Dictionary = dictionary(context.get(str(target_choice.targetId)))
	var doctrine: String = str(opts.get("doctrine", "steady"))
	var hp_limit: float = 0.60 if doctrine == "cautious" else (0.30 if doctrine == "aggressive" else 0.45)
	var flood_limit: float = 0.30 if doctrine == "cautious" else (0.60 if doctrine == "aggressive" else 0.45)
	var hp: float = number(ship.get("hp"), 1.0) / maxf(1.0, number(ship.get("maxHp"), 1.0))
	var flood: float = number(ship.get("water")) / maxf(1.0, number(ship.get("capacity"), 200.0))
	var status: Dictionary = dictionary(ship.get("status"))
	var net_flood: float = number(status.get("inflow")) - number(status.get("bailing"))
	var sinking_soon: bool = net_flood > 0.0 and (number(ship.get("capacity"), 200.0) - number(ship.get("water"))) / net_flood < 8.0
	var history: Dictionary = hp_history(now, number(ship.get("hp")), array(previous.get("observations")))
	var observations: Array = history.observations
	var focused: int = 0
	for enemy_id: String in target_choice.detailedIds:
		var other: Dictionary = context[enemy_id]
		if threat(other, ship, now) > 0.75:
			focused += 1
	var loss: float = float(history.loss)
	var danger: bool = hp <= hp_limit or flood >= flood_limit or sinking_soon or number(ship.get("fire")) >= 25.0 or (focused >= 2 and loss >= number(ship.get("maxHp"), 1.0) * 0.08)
	var dry: bool = working_mounts(ship).is_empty()
	var phase: String = str(previous.get("phase", "stage" if role == "striker" else "approach"))
	var reason: String = "Choose a useful firing lane."
	if changed_order or previous.is_empty() or str(previous.get("role", role)) != role:
		phase = "stage" if role == "striker" else "approach"
		state.phaseSince = now
		state.passSince = now
		state.pursuitSince = now
		state.progressAt = now
		state.progressPos = pos(ship)
		state.commitUntil = 0.0
	var shots: Dictionary = dictionary(ship.get("mountShotTimes"))
	var previous_shots: Dictionary = dictionary(previous.get("shotTimes"))
	var actual_shot: bool = false
	var fixed_shot: bool = false
	var pass_spent: Dictionary = {}
	var observed_shots: Dictionary = {}
	for mount: Dictionary in mounts(ship):
		var stamp: float = number(shots.get(mount.id), -1.0)
		observed_shots[str(mount.id)] = stamp
		if dictionary(previous.get("passSpent")).get(str(mount.id), false):
			pass_spent[str(mount.id)] = true
		if not previous.is_empty() and not changed_order and stamp >= 0.0 and stamp > number(previous_shots.get(mount.id), stamp):
			actual_shot = true
			if fixed_tube(mount):
				fixed_shot = true
				pass_spent[mount.id] = true
				state.launchPos = pos(ship)
	if changed_order and order == "attack":
		pass_spent = {}
		state.erase("launchPos")
		state.breakawayFrom = pos(ship)
	var elapsed: float = now - number(state.get("phaseSince"), now)
	var target_changed: bool = str(previous.get("targetId", "")) != str(target_choice.targetId)
	if actual_shot:
		state.lastUsefulShot = now
		state.pursuitSince = now
	if pos(ship).distance_to(state.get("progressPos", pos(ship))) >= 18.0:
		state.progressPos = pos(ship)
		state.progressAt = now
	var stalled: bool = now - number(state.get("progressAt"), now) >= 3.0
	var failed_pursuit: bool = not target.is_empty() and now - number(state.get("pursuitSince"), now) >= PURSUIT_SECONDS
	var explicit_survival: bool = order == "engage" or bool(opts.get("conditionalWithdrawal", false))
	var survival_trigger: bool = danger or dry or number(ship.get("fuel")) <= 0.0
	var break_origin: Vector2 = state.get("launchPos", state.get("breakawayFrom", pos(ship)))
	var regroup_travelled: bool = pos(ship).distance_to(break_origin) >= maxf(60.0, radius(ship) * 2.0)
	if survival_trigger and explicit_survival:
		phase = "regroup" if dry else "breakaway"
		reason = "Fire or flooding danger; seek a local rally." if danger else ("Ammunition or guns unavailable; seek protection." if dry else "Working fuel exhausted; preserve the boat.")
		state.safeSince = now
	elif phase in ["breakaway", "turn-away", "regroup"]:
		if phase in ["breakaway", "turn-away"] and elapsed >= 2.0:
			phase = "regroup"
			state.safeSince = now
		elif phase == "regroup" and now - number(state.get("safeSince"), now) >= 4.0 and hp > hp_limit + 0.10 and flood < flood_limit - 0.10 and net_flood <= 0.0 and number(ship.get("fire")) < 10.0 and not dry and (role != "striker" or regroup_travelled):
			phase = "stage" if role == "striker" else "approach"
			state.passSequence = int(number(previous.get("passSequence"))) + 1
			pass_spent = {}
			state.pursuitSince = now
			state.passSince = now
			state.progressAt = now
			state.progressPos = pos(ship)
			state.erase("launchPos")
			state.breakawayFrom = pos(ship)
			state.commitUntil = 0.0
		else:
			reason = "Reform behind protection before another pass."
	elif (fixed_shot or not pass_spent.is_empty()) and role == "striker":
		phase = "turn-away"
		reason = "Salvo observed; turn away and reform."
	elif actual_shot and role == "skirmisher" and phase == "fire-pass":
		phase = "breakaway"
		reason = "Firing pass completed; peel away from return fire."
	elif failed_pursuit or (stalled and phase in ["approach", "stage", "align"]):
		phase = "regroup"
		reason = "Pursuit failed; abandon the blocked or faster target."
		state.failedTargetId = str(target_choice.targetId)
		state.failedUntil = now + 4.0
		state.safeSince = now
		state.commitUntil = 0.0
	elif not target.is_empty():
		var range_value: float = useful_range(view, ship)
		var distance: float = pos(ship).distance_to(pos(target))
		if role == "striker":
			phase = "align" if distance <= range_value * 0.85 else "stage"
			for mount: Dictionary in useful_mounts(view, ship):
				if fixed_tube(mount) and distance <= number(mount.get("range")) and absf(angle_difference(number(ship.get("angle")) + number(mount.get("angle")), (pos(target) - pos(ship)).angle())) <= number(mount.get("arc")) * 0.45:
					phase = "launch-window"
					break
			reason = "Align fixed tubes for a certified launch."
		elif role == "skirmisher":
			var anchor: Vector2 = previous.get("anchor", pos(ship))
			phase = "fire-pass" if distance <= range_value * 0.9 and pos(ship).distance_to(anchor) < maxf(45.0, speed(ship) * 0.4) else "approach"
			reason = "Separated approach to pressure an exposed side."
			if speed(ship) <= velocity(target).length() * 1.05 and distance > range_value:
				phase = "regroup"
				reason = "Target is pulling away; no sustainable encirclement."
				state.safeSince = now
		elif role == "screen":
			phase = "screen"
			reason = "Intercept incoming threats within the protected ally's leash."
		elif role == "heavy":
			phase = "pressure"
			reason = "Keep useful gun arcs toward approaching flankers."
		if phase in ["stage", "align", "launch-window", "approach", "fire-pass"] and now - number(state.get("passSince"), now) >= 6.0 and now - number(state.get("lastUsefulShot"), number(state.get("passSince"), now)) >= 6.0:
			phase = "regroup"
			reason = "No useful shot; stop the pass and reassess."
			state.safeSince = now
	if role == "support" and order == "engage" and not danger and number(ship.get("fuel")) > 0.0:
		phase = "protected"
		reason = "Stay behind a real escort and avoid a combat charge."
	if order in ["move", "hold", "withdraw", "board"] and not (survival_trigger and explicit_survival):
		phase = order
		reason = {"move": "Follow the ordered position.", "hold": "Hold the ordered position.", "withdraw": "Follow the ordered local withdrawal.", "board": "Boarding stays under the accepted explicit order."}[order]
	if order == "attack" and target.is_empty():
		phase = "hold"
		reason = "Attack target is gone; await another command."
	if order == "escort" and protected.is_empty():
		phase = "hold"
		reason = "Protected leader is lost; hold for a new escort order."
	elif role == "screen" and protected.is_empty():
		phase = "hold"
		reason = "No protected ally available; hold for a new screen assignment."
	if order == "move" and not (survival_trigger and explicit_survival):
		var destination: Dictionary = dictionary(ship.get("orderTarget"))
		if pos(ship).distance_to(Vector2(number(destination.get("x"), pos(ship).x), number(destination.get("y"), pos(ship).y))) <= 12.0:
			phase = "hold"
			reason = "Move complete; hold at the ordered position."
	if phase != str(previous.get("phase", "")):
		state.phaseSince = now
		if phase in ["breakaway", "turn-away", "regroup"] and str(previous.get("phase", "")) not in ["breakaway", "turn-away", "regroup"]:
			state.breakawayFrom = pos(ship)
	if target_changed or changed_order or danger or stalled:
		state.commitUntil = 0.0
	if changed_order and order == "attack":
		state.passSequence = int(number(previous.get("passSequence"))) + 1
		pass_spent = {}
	state.merge({"role": role, "phase": phase, "reason": reason, "targetId": str(target_choice.targetId), "leaderId": str(protected.get("id", "")), "orderRevision": revision, "observations": observations, "shotTimes": observed_shots, "passSpent": pass_spent}, true)
	state.passSequence = int(number(state.get("passSequence")))
	if not state.has("firingPassId") or int(state.passSequence) != int(number(previous.get("passSequence"))) or (changed_order and order == "attack"):
		state.firingPassId = "%s:pass:%d:%d" % [str(ship.id).sha256_text().substr(0, 16), revision, int(state.passSequence)]
	return {"state": state, "targets": target_choice.targets, "detailedIds": target_choice.detailedIds, "scored": target_choice.scored, "danger": danger, "range": useful_range(view, ship), "riskLimit": 0.35 if doctrine == "cautious" else (0.85 if doctrine == "aggressive" else 0.60)}
