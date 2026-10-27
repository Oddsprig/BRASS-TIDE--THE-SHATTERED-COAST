extends RefCounted
## Detached tactical intent. B alone certifies paths and applies physical helm/fire.
const Roles = preload("res://scripts/tactical_role_plans.gd")
const Stations = preload("res://scripts/tactical_stations.gd")
const Routes = preload("res://scripts/tactical_routes.gd")
const MAX_OFFERS: int = 8
const MAX_CLEARANCE: int = 4096
const CERT_SECONDS: float = 0.2
const CERT_PREFIX_STEPS: int = 9
const CERT_PREFIX_SECONDS: float = float(CERT_PREFIX_STEPS) / 30.0
const CERT_SCOPE: String = "complete-geometry+prefix-physical"
const LIVE_CERT_SCOPE: String = "complete-geometry+live-step"
const CERT_FIELDS: Array = ["status", "reachable", "exitReachable", "eta", "fireWindow", "risk", "checkedAt", "validUntil", "snapshotRevision", "orderRevision", "pathFingerprint", "terrainRevision", "geometryKey", "checkedPose", "dynamicsKey", "physicalHorizonEnd", "rolloutSamples", "scope", "reason"]

# Main alone owns the bounded handle list and the slot metadata. The worker
# receives ONLY its capsule: no live ships, callbacks, SceneTree or globals.
static var _tasks051: Array = []
const WORKER_DEADLINE051: float = 0.15
const WORKER_BATCH_SECONDS051: float = 0.15
const WORKER_WAIT051: float = 1.0 / 30.0
const OBSERVATION_SECONDS051: float = 0.15
const MAX_TASKS051: int = 2

class _Detached051 extends RefCounted:
	var input: Dictionary = {}
	var result: Dictionary = {}

static func _work051(job: _Detached051) -> void:
	var data: Dictionary = job.input
	var prepared: Dictionary = _prepare_begin(data.view, data.memory)
	var routes: Dictionary = {}
	var requests: Dictionary = {}
	for candidate: Dictionary in prepared.candidates:
		var id: String = str(candidate.shipId)
		if not requests.has(id): requests[id] = []
		requests[id].append(candidate)
	var private_state: Dictionary = {"time": data.view.time, "tactical": {"routeCache": data.cache, "cells": Routes.grid(data.view.ships, true)}}
	for id: String in data.order:
		var budget: Dictionary = data.budgets[id]
		var ship: Dictionary = prepared.context[id]
		for candidate: Dictionary in requests.get(id, []):
			var path: Dictionary = Routes._prepare_detached051(private_state, data.geometry, ship, candidate, budget)
			routes[str(candidate.candidateId)] = path
	job.result = {"planning": prepared, "requests": requests, "routes": routes, "cache": data.cache, "budgets": data.budgets}
	job.input = {} # All remaining output stays exclusively owned until joined.

static func _poll_tasks051(drain: bool = false) -> void:
	# Called on main; never waits for an unfinished task during physics.
	for index: int in range(_tasks051.size() - 1, -1, -1):
		var slot: Dictionary = _tasks051[index]
		if not drain and not WorkerThreadPool.is_task_completed(int(slot.taskId)):
			continue
		WorkerThreadPool.wait_for_task_completion(int(slot.taskId))
		slot.taskId = -1
		slot.joined = true
		if bool(slot.retired):
			slot.capsule = null
		_tasks051.remove_at(index)

static func _retire_slot051(slot: Dictionary) -> void:
	slot.retired = true
	slot.guards = {}
	slot.owners = {}
	slot.discarded.append_array(slot.remaining)
	slot.remaining = []
	if bool(slot.joined):
		slot.capsule = null

static func _enable_workers051(t: Dictionary) -> void:
	if not t.has("workers051"):
		t.workers051 = {"slots": {}, "cache": {"player": {}, "enemy": {}}, "nextAt": {"player": 0.0, "enemy": 0.0}}

static func _retire_workers051(t: Dictionary) -> void:
	if not t.has("workers051"):
		return
	for slot: Dictionary in t.workers051.slots.values():
		_retire_slot051(slot)
	t.erase("workers051")
	_poll_tasks051()

static func _release_slot051(t: Dictionary, side: String) -> void:
	var slot: Dictionary = t.workers051.slots[side]
	if bool(slot.joined) and slot.capsule != null and str(slot.terrainKey) == str(t.geometry.key):
		# Transfer, never share, the worker's private route cache to its successor.
		t.workers051.cache[side] = slot.capsule.result.cache
	_retire_slot051(slot)
	t.workers051.slots.erase(side)

static func _take_worker051(st: Dictionary, side: String, due: Array, capability: Callable, frame_cache) -> Dictionary:
	var t: Dictionary = st.tactical
	if not t.has("workers051") or not t.workers051.slots.has(side):
		return {}
	var slot: Dictionary = t.workers051.slots[side]
	var allowed: Array = []
	var dropped: int = 0
	for id: String in due:
		if id not in slot.remaining:
			continue
		slot.remaining.erase(id)
		var guard: Dictionary = slot.guards[id]
		var ship: Dictionary = t.ships[id]
		var current: bool = bool(slot.joined) and float(st.time) - float(slot.createdAt) <= WORKER_DEADLINE051 + 0.000001
		current = current and str(t.geometry.key) == str(slot.terrainKey) and int(t.geometry.revision) == int(slot.terrainRevision)
		current = current and is_same(ship, guard.owner) and is_same(ship.spec, guard.spec) and is_same(t.mountCache[id].baseMounts, guard.mounts)
		current = current and id != str(t.manualId) and int(ship.orderRevision) == int(guard.revision) and t.options.byId[id] == guard.options
		# Normal retained observations may replace memory after the batch sample.
		# Semantic phase/pass changes are checked at adoption, not record identity.
		current = current and str(ship.order) == str(guard.order)
		if current:
			var state: Dictionary = slot.capsule.result.planning.decisions[id].state
			for key: String in ["targetId", "leaderId"]:
				var target_id: String = str(state.get(key, ""))
				if not target_id.is_empty() and not is_same(t.ships.get(target_id), slot.owners.get(target_id)):
					current = false; break
		if current:
			current = not (capability.call(st, id, guard.capability, frame_cache) as Array).is_empty()
		if current:
			allowed.append(id)
		else:
			slot.discarded.append(id)
			dropped += 1
	var result: Dictionary = {}
	if not allowed.is_empty():
		result = {"planning": slot.capsule.result.planning, "requests": slot.capsule.result.requests, "routes": slot.capsule.result.routes, "allowed": allowed, "slot": slot, "guards": slot.guards}
	# These joined output dictionaries remain owned by result after slot release.
	if slot.remaining.is_empty():
		_release_slot051(t, side)
	result.dropped051 = dropped
	return result

static func _waiting_worker051(st: Dictionary, id: String) -> bool:
	var t: Dictionary = st.tactical
	if not t.has("workers051"): return false
	var side: String = str(t.ships[id].team)
	if not t.workers051.slots.has(side): return false
	var slot: Dictionary = t.workers051.slots[side]
	if id not in slot.remaining or bool(slot.joined): return false
	var guard: Dictionary = slot.guards[id]
	var last: float = float(t.lastDecision.get(id, -1.0))
	# Only a dispatched batch member may wait. No observation clock is
	# advanced by dispatch, and one physics step remains for the main fallback.
	return last >= 0.0 and int(t.ships[id].orderRevision) == int(guard.revision) and str(t.geometry.key) == str(slot.terrainKey) and float(st.time) - float(slot.createdAt) < WORKER_WAIT051 - 0.000001 and float(st.time) - last + float(t.dt) < CERT_SECONDS - 0.000001

static func _dispatch_batch051(st: Dictionary, order: Array, build_view: Callable, capability: Callable, frame_cache) -> Dictionary:
	var t: Dictionary = st.tactical
	var tally: Dictionary = {"dispatches": 0, "drops": 0}
	if not t.has("workers051"):
		return tally
	for side: String in t.workers051.slots.keys():
		var slot: Dictionary = t.workers051.slots[side]
		if float(st.time) - float(slot.createdAt) >= WORKER_BATCH_SECONDS051 - 0.000001 or str(slot.terrainKey) != str(t.geometry.key):
			tally.drops += slot.remaining.size()
			_release_slot051(t, side)
	if _tasks051.size() >= MAX_TASKS051:
		return tally
	var busy_sides: Array = []
	for active: Dictionary in _tasks051: busy_sides.append(str(active.side))
	var sides: Array = []
	for id: String in order:
		var side: String = str(t.ships[id].team)
		if id == str(t.manualId) or t.workers051.slots.has(side) or side in busy_sides: continue
		if float(st.time) < float(t.workers051.nextAt[side]) - 0.000001: continue
		if side not in sides and _tasks051.size() + sides.size() >= MAX_TASKS051: continue
		if side not in sides: sides.append(side)
	for side: String in sides:
		var ids: Array = []
		var slices: Dictionary = {}
		var guards: Dictionary = {}
		var memory_copy: Dictionary = {"byId": {}, "reservations": t.memory[side].reservations.duplicate(true)}
		for id: String in order:
			var ship: Dictionary = t.ships[id]
			if str(ship.team) != side or id == str(t.manualId): continue
			ids.append(id)
			var memory: Dictionary = t.memory[side].byId.get(id, {})
			if not memory.is_empty(): memory_copy.byId[id] = memory.duplicate(true)
			guards[id] = {"owner": ship, "spec": ship.spec, "mounts": t.mountCache[id].baseMounts, "revision": int(ship.orderRevision), "order": str(ship.order), "options": t.options.byId[id].duplicate(true), "decisionAt": t.lastDecision.get(id, -1.0), "memory": memory, "capability": capability.call(st, id, [], frame_cache)}
		# Independent PURE work, not a second debit of main's current budget.
		# All hulls get eight offers; finite route work is sliced in global age order.
		var clearance: int = 2900
		var route_slots: int = 4
		for index: int in range(ids.size()):
			var count: int = ids.size() - index
			var tests: int = ceili(float(clearance) / float(count))
			var routes: int = ceili(float(route_slots) / float(count))
			clearance -= tests; route_slots -= routes
			slices[ids[index]] = {"clearanceTests": 0, "clearanceLimit": tests, "exhaustions": 0, "fullRoutes": 4 - routes, "routeAllowance051": routes, "cacheHits": 0}
		var capsule: _Detached051 = _Detached051.new()
		var snapshot: Dictionary = build_view.call(st, side, ids, frame_cache)
		# The builder creates the worker-owned view directly. Neither a borrowed
		# begin view nor a second deep copy crosses this ownership boundary.
		capsule.input = {"view": snapshot, "memory": memory_copy, "geometry": t.geometry.duplicate(true), "cache": t.workers051.cache[side], "order": ids.duplicate(), "budgets": slices}
		t.workers051.cache[side] = {} # Ownership transferred; main has no alias.
		var slot: Dictionary = {"side": side, "capsule": capsule, "guards": guards, "owners": t.ships.duplicate(), "remaining": ids, "createdAt": float(st.time), "terrainKey": str(t.geometry.key), "terrainRevision": int(t.geometry.revision), "joined": false, "retired": false, "adopted": [], "discarded": [], "taskId": -1}
		slot.taskId = WorkerThreadPool.add_task(_work051.bind(capsule), false, "Brass Tide detached station/land suggestions")
		t.workers051.slots[side] = slot
		t.workers051.nextAt[side] = float(st.time) + WORKER_BATCH_SECONDS051
		_tasks051.append(slot)
		tally.dispatches += 1
	return tally

static func _phase_due051(view: Dictionary, ship: Dictionary, state: Dictionary, target: Dictionary, range_value: float) -> bool:
	# Only actual phase boundaries need main's full decision. A batch period is
	# not a new burst/recovery/pursuit clock, nor permission to miss its deadline.
	var now: float = float(view.time)
	var phase: String = str(state.phase)
	var elapsed: float = now - float(state.get("phaseSince", now))
	if phase in ["breakaway", "turn-away", "regroup"]:
		if bool(state.get("localRecovery", false)):
			var recovery: float = clampf(PI / maxf(0.01, Roles.turn_rate(ship)), 0.75, 2.0)
			if elapsed >= recovery and Roles.pos(ship).distance_to(state.get("breakawayFrom", Roles.pos(ship))) >= maxf(60.0, Roles.radius(ship) * 2.0):
				var recovery_guns: Array = Roles.solo_recovery_guns(view, ship, state)
				for mount: Dictionary in Roles.mounts(ship):
					if str(mount.id) in recovery_guns and (Roles.mount_reload(ship, mount) <= 0.000001 or float(ship.get("mountShotTimes", {}).get(mount.id, -1.0)) > float(state.get("phaseSince", now))): return true
		else:
			return (phase in ["breakaway", "turn-away"] and elapsed >= 2.0) or (phase == "regroup" and now - float(state.get("safeSince", now)) >= 4.0)
		return false
	if Roles.speed(ship) <= 0.01: return false
	var distance: float = Roles.pos(ship).distance_to(Roles.pos(target)) if not target.is_empty() else INF
	var role: String = str(state.role)
	if role in ["skirmisher", "striker"] and not target.is_empty():
		if now - float(state.get("pursuitSince", now)) >= Roles.PURSUIT_SECONDS: return true
		var opportunity: float = float(state.get("passOpportunitySince", -1.0))
		var launcher: Dictionary = Roles.launch_mount(view, ship) if role == "striker" else {}
		var reloading: bool = not launcher.is_empty() and Roles.mount_reload(ship, launcher) > 0.000001
		if phase in ["stage", "align", "launch-window", "approach", "fire-pass"] and not (phase == "stage" and reloading) and opportunity >= 0.0 and now - maxf(opportunity, float(state.get("lastUsefulShot", opportunity))) >= 6.0: return true
		if phase in ["approach", "stage", "align"] and now - float(state.get("progressAt", now)) >= 3.0 and not (reloading and distance <= range_value * 1.2): return true
		if role == "skirmisher" and phase in ["approach", "fire-pass"]:
			var near_anchor: bool = Roles.pos(ship).distance_to(state.get("anchor", Roles.pos(ship))) < maxf(45.0, Roles.speed(ship) * 0.4)
			var keep_pass: bool = (phase == "fire-pass" or int(state.get("passShortShots", 0)) > 0) and distance <= range_value * 1.05
			if ((distance <= range_value * 0.9 and near_anchor) or keep_pass) != (phase == "fire-pass"): return true
			if Roles.speed(ship) <= Roles.velocity(target).length() * 1.05 and distance > range_value: return true
	return false

static func _join_preference051(view: Dictionary, ship: Dictionary, previous: Dictionary, context: Dictionary, old: Dictionary, sampled_context: Dictionary, baseline: Dictionary) -> Dictionary:
	# Preferences are bounded-age suggestions. Only meaningful changes demand a
	# full role search; this guard neither certifies a path nor permits a shot.
	var sampled: Dictionary = sampled_context[str(ship.id)]
	if ship.get("order") != sampled.get("order") or ship.get("orderTarget") != sampled.get("orderTarget"): return {}
	for key: String in ["role", "phase", "targetId", "leaderId", "firingPassId", "passSequence", "passShots", "passShortShots", "passSpent", "localRecovery", "phaseSince", "passSince", "passFirstShotAt", "passOpportunitySince", "shotTimes", "lastUsefulShot", "safeSince"]:
		if previous.get(key) != baseline.get(key): return {}
	if ship.get("mountShotTimes", {}) != sampled.get("mountShotTimes", {}): return {}
	var target_id: String = str(old.state.targetId)
	var leader_id: String = str(old.state.leaderId)
	if not target_id.is_empty() and (not context.has(target_id) or context[target_id].team == ship.team): return {}
	if not leader_id.is_empty() and (not context.has(leader_id) or context[leader_id].team != ship.team): return {}
	var target: Dictionary = context.get(target_id, {})
	var sampled_target: Dictionary = sampled_context.get(target_id, {})
	var distance: float = Roles.pos(ship).distance_to(Roles.pos(target)) if not target.is_empty() else INF
	var sampled_distance: float = Roles.pos(sampled).distance_to(Roles.pos(sampled_target)) if not sampled_target.is_empty() else INF
	var timers: Array = Roles.array(ship.get("weaponCooldowns"))
	var old_timers: Array = Roles.array(sampled.get("weaponCooldowns"))
	for index: int in range(mini(Roles.MAX_MOUNTS, ship.mounts.size())):
		var mount: Dictionary = ship.mounts[index]
		var reload: float = float(timers[index]) if index < timers.size() else 0.0
		var old_reload: float = float(old_timers[index]) if index < old_timers.size() else 0.0
		if index == 0:
			reload = maxf(reload, float(ship.get("cooldown", 0.0)))
			old_reload = maxf(old_reload, float(sampled.get("cooldown", 0.0)))
		if (reload <= 0.000001) != (old_reload <= 0.000001): return {}
		# Match the retained range event BEFORE sealing a new maneuver. Otherwise
		# an old nonfiring stage silently inherits the new in-range event baseline.
		if (distance <= float(mount.range) + Roles.radius(target) + 1.0) != (sampled_distance <= float(mount.range) + Roles.radius(sampled_target) + 1.0): return {}
		if Roles.fixed_tube(mount) and not target.is_empty() and reload <= 0.000001:
			var aligned: bool = distance <= float(mount.range) and absf(angle_difference(float(ship.angle) + float(mount.angle), (Roles.pos(target) - Roles.pos(ship)).angle())) <= float(mount.arc) * 0.45
			var sampled_aligned: bool = sampled_distance <= float(mount.range) and absf(angle_difference(float(sampled.angle) + float(mount.angle), (Roles.pos(sampled_target) - Roles.pos(sampled)).angle())) <= float(mount.arc) * 0.45
			if aligned != sampled_aligned: return {}
	var opts: Dictionary = Roles.options(view, ship)
	var doctrine: String = str(opts.get("doctrine", "steady"))
	var hp_limit: float = 0.60 if doctrine == "cautious" else (0.30 if doctrine == "aggressive" else 0.45)
	var flood_limit: float = 0.30 if doctrine == "cautious" else (0.60 if doctrine == "aggressive" else 0.45)
	var status: Dictionary = ship.status
	var net: float = float(status.get("inflow", 0.0)) - float(status.get("bailing", 0.0))
	if float(ship.hp) / maxf(1.0, float(ship.maxHp)) <= hp_limit or float(ship.water) / maxf(1.0, float(ship.capacity)) >= flood_limit or float(ship.fire) >= 25.0 or (net > 0.0 and (float(ship.capacity) - float(ship.water)) / net < 8.0): return {}
	if float(ship.fuel) <= 0.0 or (str(old.state.role) != "support" and Roles.working_mounts(ship).is_empty()): return {}
	# A newly close hostile needs a current escape decision even if it was not
	# selected by the old preference. This is positions only, never a shortlist.
	if str(ship.order) != "board":
		for other: Dictionary in context.values():
			if other.team != ship.team and Roles.pos(ship).distance_to(Roles.pos(other)) < Routes.navigation_radius(ship) + Routes.navigation_radius(other) + 24.0: return {}
	var history: Array = Roles.array(previous.get("observations"))
	var sampled_history: Array = Roles.array(old.state.get("observations"))
	if history.is_empty() or (not sampled_history.is_empty() and float(sampled_history[-1].lastAt) > float(history[-1].lastAt)): history = sampled_history
	# Preserve the worker sample's REAL timestamps; append a REAL current HP
	# observation, rather than relabeling old HP as if sampled on this join.
	var hp: Dictionary = Roles.hp_history(float(view.time), float(ship.hp), history)
	var impaired: bool = float(ship.spec.get("speed", 0.0)) > 0.0 and (float(status.get("speedFactor", 1.0)) < 0.45 or float(status.get("turnFactor", 1.0)) < 0.45)
	if impaired or float(hp.loss) >= float(ship.maxHp) * 0.08:
		var focused: int = 0
		for enemy_id: String in old.get("detailedIds", []):
			if context.has(enemy_id) and context[enemy_id].team != ship.team and Roles.threat(context[enemy_id], ship, float(view.time)) > 0.75: focused += 1
		if (impaired and focused > 0) or focused >= 2: return {}
	if str(old.state.role) == "skirmisher" and str(old.state.phase) == "fire-pass" and Roles._skirmisher_burst_done(view, ship, old.state, float(view.time), float(old.range)): return {}
	var decision: Dictionary = old.duplicate()
	decision.state = old.state.duplicate()
	# Keep newer observed travel, and observe REAL current progress before
	# testing a stall. Joining a preference must not rewind these clocks/poses.
	if float(previous.get("progressAt", -1.0)) > float(decision.state.get("progressAt", -1.0)):
		decision.state.progressAt = previous.progressAt
		decision.state.progressPos = previous.progressPos
	if Roles.pos(ship).distance_to(decision.state.get("progressPos", Roles.pos(ship))) >= 18.0:
		decision.state.progressAt = float(view.time)
		decision.state.progressPos = Roles.pos(ship)
	if _phase_due051(view, ship, decision.state, target, float(old.range)): return {}
	decision.state.observations = hp.observations
	var detailed: Array = []
	if old.get("detailedIds", []).size() > Roles.MAX_TARGETS: return {}
	for raw: Variant in old.get("detailedIds", []):
		if not raw is String or detailed.size() >= Roles.MAX_TARGETS or raw in detailed: return {}
		if context.has(raw) and context[raw].team != ship.team: detailed.append(raw)
	if not target_id.is_empty() and target_id not in detailed: return {}
	decision.detailedIds = detailed
	var targets: Array = []
	for raw: Variant in old.get("targets", []):
		if raw in detailed: targets.append(raw)
	decision.targets = targets
	return decision

static func _prepare_with_worker051(view: Dictionary, memory: Dictionary, suggestion: Dictionary) -> Dictionary:
	# Normal joins keep the worker preference with actual current HP memory.
	# Authority still requires new main pose/traffic/certificate/resolution work.
	if suggestion.get("allowed", []).is_empty(): return _prepare_begin(view, memory)
	var context: Dictionary = Roles.ships_by_id(view)
	var reservations: Dictionary = Roles.dictionary(memory.get("reservations")).duplicate(true)
	var prepared: Dictionary = {"context": context, "dueIds": _due(view, context), "decisions": {}, "sources": {}, "candidates": [], "scored": 0, "routes051": {}, "workerIds051": []}
	for id: String in prepared.dueIds:
		var ship: Dictionary = context[id]
		var previous: Dictionary = Roles.dictionary(Roles.dictionary(memory.get("byId")).get(id))
		var decision: Dictionary = {}
		var requests: Array = []
		if id in suggestion.allowed:
			var old: Dictionary = suggestion.planning.decisions[id]
			decision = _join_preference051(view, ship, previous, context, old, suggestion.planning.context, suggestion.guards[id].memory)
			if not decision.is_empty():
				for raw: Dictionary in suggestion.requests.get(id, []):
					# Joined output is transferred once to main, not copied eight
					# times. Save the old route key before minting fresh request IDs.
					var route: Dictionary = suggestion.routes.get(str(raw.candidateId), {})
					var candidate: Dictionary = raw
					candidate.candidateId = "%s:%d:%d:%d" % [id.sha256_text().substr(0, 16), int(view.snapshotRevision), int(ship.orderRevision), requests.size()]
					candidate.snapshotRevision = int(view.snapshotRevision)
					candidate.orderRevision = int(ship.orderRevision)
					requests.append(candidate)
					prepared.routes051[str(candidate.candidateId)] = route
				prepared.workerIds051.append(id)
				suggestion.slot.adopted.append(id)
			else:
				suggestion.slot.discarded.append(id)
		if decision.is_empty():
			decision = Roles.decide(view, ship, previous, context, reservations)
		if id not in prepared.workerIds051:
			# A changed phase already has a CURRENT observation above. Generate
			# its new offers without repeating the whole role/HP/phase decision.
			requests = Stations.candidates(view, ship, decision, context, reservations)
		prepared.decisions[id] = decision
		prepared.scored += int(decision.scored)
		prepared.candidates.append_array(requests)
		for candidate: Dictionary in requests: prepared.sources[candidate.candidateId] = candidate
		if not requests.is_empty() and int(requests[0].sector) >= 0:
			reservations[id] = {"targetId": requests[0].targetId, "sector": requests[0].sector, "until": float(view.time) + CERT_SECONDS}
	return prepared

static func fingerprint(candidate: Dictionary) -> String:
	return Stations.fingerprint(candidate)

static func _view_ok(view: Dictionary) -> bool:
	return view.get("snapshotRevision") is int and view.get("terrainRevision") is int and Roles.id_ok(view.get("side")) and view.get("dueIds") is Array and view.get("ships") is Array and _finite(view.get("time")) and Roles.number(view.get("time")) >= 0.0 and _finite(view.get("dt")) and Roles.number(view.get("dt")) >= 0.0

static func _finite(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _due(view: Dictionary, context: Dictionary) -> Array:
	var ids: Array = []
	var seen: Dictionary = {}
	for raw: Variant in Roles.array(view.get("dueIds")):
		if not Roles.id_ok(raw) or seen.has(raw):
			continue
		seen[raw] = true
		var ship: Dictionary = Roles.dictionary(context.get(raw))
		if ship.is_empty() or ship.get("team") != view.get("side"):
			continue
		ids.append(raw)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var aa: Dictionary = context[a]
		var bb: Dictionary = context[b]
		var a_danger: float = Roles.number(aa.get("water")) / maxf(1.0, Roles.number(aa.get("capacity"), 200.0)) + Roles.number(aa.get("fire")) / 100.0 + 1.0 - Roles.number(aa.get("hp"), 1.0) / maxf(1.0, Roles.number(aa.get("maxHp"), 1.0))
		var b_danger: float = Roles.number(bb.get("water")) / maxf(1.0, Roles.number(bb.get("capacity"), 200.0)) + Roles.number(bb.get("fire")) / 100.0 + 1.0 - Roles.number(bb.get("hp"), 1.0) / maxf(1.0, Roles.number(bb.get("maxHp"), 1.0))
		return a_danger > b_danger if not is_equal_approx(a_danger, b_danger) else a < b
	)
	return ids

static func propose(view: Dictionary, memory: Dictionary) -> Array:
	if not _view_ok(view):
		return []
	return _planning(view, memory).candidates

static func _prepare_begin(view: Dictionary, memory: Dictionary) -> Dictionary:
	# Keep propose's validation before any same-begin planning work.
	return _planning(view, memory) if _view_ok(view) else {}

static func _observe_retained051(view: Dictionary, ship: Dictionary, previous: Dictionary, context: Dictionary) -> Dictionary:
	# Private authoritative inputs, already admitted by Runtime. No proposal,
	# scored preference, source reconstruction or public certificate is produced.
	return Roles._observe_retained051(view, ship, previous, context)

static func _planning(view: Dictionary, memory: Dictionary) -> Dictionary:
	var context: Dictionary = Roles.ships_by_id(view)
	var by_id: Dictionary = Roles.dictionary(memory.get("byId"))
	var result: Array = []
	var decisions: Dictionary = {}
	var sources: Dictionary = {}
	var reservations: Dictionary = Roles.dictionary(memory.get("reservations")).duplicate(true)
	var due_ids: Array = _due(view, context)
	var scored: int = 0
	for ship_id: String in due_ids:
		var ship: Dictionary = context[ship_id]
		var decision: Dictionary = Roles.decide(view, ship, Roles.dictionary(by_id.get(ship_id)), context, reservations)
		decisions[ship_id] = decision
		scored += int(decision.scored)
		var requests: Array = Stations.candidates(view, ship, decision, context, reservations)
		result.append_array(requests)
		for candidate: Dictionary in requests:
			sources[candidate.candidateId] = candidate
		if not requests.is_empty() and int(requests[0].sector) >= 0:
			# Tentative preference only, used to offer distinct sectors in this batch.
			# It is never a published station or a manufactured physical certificate.
			reservations[ship_id] = {"targetId": requests[0].targetId, "sector": requests[0].sector, "until": float(view.time) + CERT_SECONDS}
	return {"context": context, "dueIds": due_ids, "decisions": decisions, "sources": sources, "candidates": result, "scored": scored}

static func _hex_key(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for i: int in range(value.length()):
		if not value.substr(i, 1) in "0123456789abcdef":
			return false
	return true

static func _certificate_reason(view: Dictionary, ship: Dictionary, candidate: Dictionary, certificate: Dictionary, shortlisted_targets: Array = []) -> String:
	for key: String in CERT_FIELDS:
		if not certificate.has(key):
			return "Waiting for a fully checked maneuver."
	if certificate.status != "valid":
		return "Route check pending." if certificate.status == "pending" else "Route or exit blocked."
	if not certificate.reachable is bool or not certificate.exitReachable is bool or certificate.reachable != true or certificate.exitReachable != true:
		return "No checked approach and exit."
	for key: String in ["eta", "risk", "checkedAt", "validUntil", "physicalHorizonEnd"]:
		if not _finite(certificate[key]):
			return "Maneuver check unavailable; wait."
	if float(certificate.eta) < 0.0 or float(certificate.risk) < 0.0 or float(certificate.risk) > 1.0:
		return "Maneuver check unavailable; wait."
	if not Roles.id_ok(certificate.reason, true) or not certificate.scope in [CERT_SCOPE,LIVE_CERT_SCOPE]:
		return "Waiting for a complete route and turning check."
	var now: float = float(view.time)
	if float(certificate.checkedAt) > now + 0.000001 or float(certificate.validUntil) <= now or float(certificate.validUntil) > float(certificate.checkedAt) + CERT_SECONDS + 0.000001:
		return "Checking the next safe maneuver."
	if not certificate.snapshotRevision is int or not certificate.orderRevision is int or not certificate.terrainRevision is int or certificate.snapshotRevision != view.snapshotRevision or certificate.snapshotRevision != candidate.snapshotRevision or certificate.orderRevision != ship.get("orderRevision", 0) or certificate.orderRevision != candidate.orderRevision or certificate.terrainRevision != view.terrainRevision:
		return "Order or terrain changed; checking a new maneuver."
	if not _hex_key(certificate.pathFingerprint) or certificate.pathFingerprint != fingerprint(candidate) or not _hex_key(certificate.geometryKey) or not _hex_key(certificate.dynamicsKey):
		return "Maneuver changed; checking it again."
	var live_step: bool = certificate.scope == LIVE_CERT_SCOPE
	var expected_samples: int = 0 if live_step else CERT_PREFIX_STEPS
	var expected_horizon: float = CERT_SECONDS if live_step else CERT_PREFIX_SECONDS
	if not certificate.rolloutSamples is int or int(certificate.rolloutSamples) != expected_samples or absf(float(certificate.physicalHorizonEnd) - float(certificate.checkedAt) - expected_horizon) > 0.00001:
		return "Turning and braking still need checking."
	var pose: Dictionary = Roles.dictionary(certificate.checkedPose)
	for key: String in ["x", "y", "vx", "vy", "angle"]:
		if not _finite(pose.get(key)) or absf(float(pose[key]) - Roles.number(ship.get(key))) > 0.000001:
			return "Boat moved; checking the maneuver again."
	var window: Dictionary = Roles.dictionary(certificate.fireWindow)
	if not _finite(window.get("from")) or not _finite(window.get("until")) or not window.get("mountIds") is Array:
		return "Waiting for a usable firing window."
	if float(window.until) < float(window.from) or float(window.from) < float(certificate.checkedAt) - 0.000001:
		return "Waiting for a usable firing window."
	var installed: Dictionary = {}
	for mount: Dictionary in Roles.mounts(ship):
		installed[str(mount.id)] = true
	var seen: Dictionary = {}
	if window.mountIds.size() > Roles.MAX_MOUNTS:
		return "Weapon assignment needs checking."
	for mount_id: Variant in window.mountIds:
		if not Roles.id_ok(mount_id) or not installed.has(mount_id) or mount_id not in candidate.fireMountIds or seen.has(mount_id):
			return "Weapon assignment changed; checking fire."
		seen[mount_id] = true
	if not candidate.fireMountIds.is_empty() and (candidate.targetId.is_empty() or window.mountIds.is_empty() or float(window.until) <= float(window.from) or candidate.exit.is_empty()):
		return "Attack has no checked firing opportunity and exit."
	if candidate.fireMountIds.is_empty() and (not window.mountIds.is_empty() or not is_equal_approx(float(window.from), float(window.until))):
		return "Checking fire holds for this maneuver."
	var context: Dictionary = Roles.ships_by_id(view)
	var order: String = str(ship.get("order", "engage"))
	var order_target_id: String = str(Roles.dictionary(ship.get("orderTarget")).get("shipId", ""))
	var has_alt: bool = Stations.has_alt_targets(candidate)
	if order in ["attack", "board"] and has_alt:
		return "Explicit attack stays on the ordered target."
	for mount_id: String in candidate.fireMountIds:
		if not installed.has(mount_id):
			return "Weapon fitting changed; checking fire."
		var req_tid: String = Stations.mount_target_id(candidate, mount_id)
		var req_target: Dictionary = Roles.dictionary(context.get(req_tid))
		if req_target.is_empty() or req_target.get("team") == ship.get("team"):
			return "Weapon target unavailable; checking fire."
		if not shortlisted_targets.is_empty() and req_tid not in shortlisted_targets:
			return "Weapon target assignment needs checking."
		if order in ["attack", "board"] and not order_target_id.is_empty() and req_tid != order_target_id:
			return "Explicit attack stays on the ordered target."
	if has_alt and not window.has("mountTargets"):
		return "Weapon target assignment needs checking."
	if window.has("mountTargets"):
		if not window.get("mountTargets") is Dictionary:
			return "Weapon target assignment needs checking."
		var w_targets: Dictionary = window.mountTargets
		if candidate.fireMountIds.is_empty() and not w_targets.is_empty():
			return "Checking fire holds for this maneuver."
		if w_targets.size() != window.mountIds.size() or w_targets.size() > Roles.MAX_MOUNTS:
			return "Weapon target assignment needs checking."
		var distinct: Dictionary = {}
		if not str(candidate.get("targetId", "")).is_empty():
			distinct[str(candidate.targetId)] = true
		for mount_id: Variant in window.mountIds:
			if not w_targets.has(mount_id) or not Roles.id_ok(w_targets[mount_id]):
				return "Weapon target assignment changed; checking fire."
			var certified_tid: String = str(w_targets[mount_id])
			if certified_tid != Stations.mount_target_id(candidate, str(mount_id)):
				return "Weapon target assignment changed; checking fire."
			var target_ship: Dictionary = Roles.dictionary(context.get(certified_tid))
			if target_ship.is_empty() or target_ship.get("team") == ship.get("team"):
				return "Weapon target unavailable; checking fire."
			if not shortlisted_targets.is_empty() and certified_tid not in shortlisted_targets:
				return "Weapon target assignment needs checking."
			distinct[certified_tid] = true
		if distinct.size() > Stations.MAX_MOUNT_TARGETS:
			return "Weapon target assignment needs checking."
	return ""

static func _fire_gates(view: Dictionary, ship: Dictionary, state: Dictionary, candidate: Dictionary, certificate: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var useful: Dictionary = {}
	for mount: Dictionary in Roles.useful_mounts(view, ship):
		useful[str(mount.id)] = true
	var window: Dictionary = Roles.dictionary(certificate.get("fireWindow"))
	var window_ids: Array = Roles.array(window.get("mountIds"))
	var has_window_targets: bool = window.has("mountTargets") and window.get("mountTargets") is Dictionary
	var window_targets: Dictionary = Roles.dictionary(window.get("mountTargets"))
	var alt_requested: bool = Stations.has_alt_targets(candidate)
	var now: float = Roles.number(view.get("time"))
	var time_ok: bool = not certificate.is_empty() and now >= Roles.number(window.get("from"), INF) and now <= Roles.number(window.get("until"), -INF)
	var pass_spent: Dictionary = Roles.dictionary(state.get("passSpent"))
	for mount: Dictionary in Roles.mounts(ship):
		var mount_id: String = str(mount.id)
		var fixed: bool = Roles.fixed_tube(mount)
		var expected_target: String = Stations.mount_target_id(candidate, mount_id) if not certificate.is_empty() else str(candidate.get("targetId", ""))
		var target_verified: bool = (not alt_requested and not has_window_targets) or (has_window_targets and window_targets.has(mount_id) and str(window_targets.get(mount_id, "")) == expected_target)
		var permit: bool = time_ok and mount_id in Roles.array(candidate.get("fireMountIds")) and mount_id in window_ids and useful.has(mount_id) and target_verified
		# The primary phase aligns the hull, not an already-bearing secondary
		# tube. Its distinct target/window is physically certified; the live Fire
		# gate still rechecks the actual ray, and the same one-shot pass lease holds.
		var secondary_window: bool = alt_requested and target_verified and expected_target != str(candidate.get("targetId", "")) and mount_id in window_ids
		var reason: String = "Waiting for a usable firing window."
		if not useful.has(mount_id):
			reason = "Automatic fire held or ammunition reserved/unavailable."
		if fixed and (bool(pass_spent.get(mount_id, false)) or (str(state.get("phase", "")) != "launch-window" and not secondary_window)):
			permit = false
			reason = "Salvo spent; turn away." if pass_spent.get(mount_id, false) else "Aligning fixed tubes."
		if permit:
			reason = "Firing at the assigned target."
		result[mount_id] = {"targetId": expected_target, "permit": permit, "shotLimit": 1 if fixed else 2147483647, "reason": reason, "leaseKind": "salvo" if fixed else "continuous", "firingPassId": str(state.get("firingPassId", "")) if fixed else ""}
	return result

static func _intent(view: Dictionary, ship: Dictionary, state: Dictionary, candidate: Dictionary, certificate: Dictionary, reason: String = "") -> Dictionary:
	var accepted: bool = not certificate.is_empty()
	return {"candidateId": str(candidate.get("candidateId", "")), "pathFingerprint": str(certificate.get("pathFingerprint", "")), "snapshotRevision": int(view.snapshotRevision), "orderRevision": int(Roles.number(ship.get("orderRevision"))), "role": str(state.role), "targetId": str(candidate.get("targetId", "")), "leaderId": str(candidate.get("leaderId", state.get("leaderId", ""))), "sector": int(Roles.number(candidate.get("sector"), -1.0)), "phase": str(state.phase) if accepted else "pending", "waypoints": (Roles.array(candidate.get("approach")) + Roles.array(candidate.get("pass"))).duplicate() if accepted else [], "exit": Roles.array(candidate.get("exit")).duplicate() if accepted else [], "fireGate": _fire_gates(view, ship, state, candidate, certificate), "reason": (str(state.reason) if reason.is_empty() else reason).substr(0, 128), "validUntil": minf(float(certificate.validUntil), float(view.time) + CERT_SECONDS) if accepted else float(view.time)}

static func resolve(view: Dictionary, memory: Dictionary, offers: Array) -> Dictionary:
	# Public r2 calls always plan afresh; only Runtime.begin owns the local seam.
	return _resolve_planned(view, memory, offers, {})

static func _resolve_planned(view: Dictionary, memory: Dictionary, offers: Array, prepared: Dictionary, live_traffic_seconds051: float = -1.0) -> Dictionary:
	# Runtime alone opts into renewable hard prefixes. Public/default calls
	# retain complete reservations, including their station/sector vetoes.
	if not is_finite(live_traffic_seconds051):live_traffic_seconds051 = -1.0
	var counters: Dictionary = {"due": 0, "proposed": 0, "scoredTargets": 0, "offers": 0, "accepted": 0, "rejected": 0, "pending": 0, "blocked": 0, "offerOverflow": 0, "reservationConflicts": 0, "clearanceTests": 0, "clearanceExhausted": 0}
	# The private synchronous begin never writes a previous per-hull record.
	# Copy its two containers only; public/default results remain fully detached.
	var private_begin051: bool = not prepared.is_empty() and live_traffic_seconds051 >= 0.0
	var next_memory: Dictionary = memory.duplicate() if private_begin051 else memory.duplicate(true)
	if private_begin051:
		next_memory.byId = Roles.dictionary(memory.get("byId")).duplicate()
		next_memory.reservations = Roles.dictionary(memory.get("reservations")).duplicate()
	var by_id: Dictionary = {}
	if not _view_ok(view):
		return {"memory": next_memory, "byId": by_id, "counters": counters}
	if not next_memory.get("byId") is Dictionary:
		next_memory["byId"] = {}
	if not next_memory.get("reservations") is Dictionary:
		next_memory["reservations"] = {}
	var planning: Dictionary = _planning(view, memory) if prepared.is_empty() else prepared
	var context: Dictionary = planning.context
	var due_ids: Array = planning.dueIds
	var decisions: Dictionary = planning.decisions
	var sources: Dictionary = planning.sources
	var grouped: Dictionary = {}
	for ship_id: String in due_ids:
		grouped[ship_id] = []
	counters.scoredTargets = int(planning.scored)
	counters.proposed = planning.candidates.size()
	counters.due = due_ids.size()
	var max_input: int = due_ids.size() * MAX_OFFERS
	var offered_per_hull: Dictionary = {}
	var seen_candidates: Dictionary = {}
	counters.offerOverflow = maxi(0, offers.size() - max_input)
	for index: int in range(mini(offers.size(), max_input)):
		counters.offers = int(counters.offers) + 1
		var raw: Variant = offers[index]
		if not raw is Dictionary:
			counters.rejected = int(counters.rejected) + 1
			continue
		var candidate: Dictionary = Roles.dictionary(raw.get("candidate"))
		var certificate: Dictionary = Roles.dictionary(raw.get("certificate"))
		var source: Dictionary = Roles.dictionary(sources.get(candidate.get("candidateId")))
		var ship_id: String = str(candidate.get("shipId", ""))
		offered_per_hull[ship_id] = int(offered_per_hull.get(ship_id, 0)) + 1
		if int(offered_per_hull[ship_id]) > MAX_OFFERS:
			counters.offerOverflow = int(counters.offerOverflow) + 1
			continue
		if source.is_empty() or not grouped.has(ship_id) or not Stations.valid_candidate(candidate) or not Stations.same_request(source, candidate):
			counters.rejected = int(counters.rejected) + 1
			continue
		if seen_candidates.has(str(candidate.candidateId)):
			counters.rejected = int(counters.rejected) + 1
			continue
		seen_candidates[str(candidate.candidateId)] = true
		if grouped[ship_id].size() >= MAX_OFFERS:
			counters.offerOverflow = int(counters.offerOverflow) + 1
			continue
		var rejection: String = _certificate_reason(view, context[ship_id], candidate, certificate, Roles.array(decisions[ship_id].get("targets")))
		if not rejection.is_empty():
			counters.rejected = int(counters.rejected) + 1
			if certificate.get("status") == "pending":
				counters.pending = int(counters.pending) + 1
			elif certificate.get("status") == "blocked":
				counters.blocked = int(counters.blocked) + 1
			decisions[ship_id].rejection = rejection
			continue
		var state: Dictionary = decisions[ship_id].state
		var explicit: bool = str(context[ship_id].get("order", "engage")) != "engage"
		if not explicit and float(certificate.risk) > float(decisions[ship_id].riskLimit):
			counters.rejected = int(counters.rejected) + 1
			decisions[ship_id].rejection = "Exposed firing lane; seek another station or protection."
			continue
		var score: float = -float(certificate.risk) * 3.0 - float(certificate.eta) * 0.04
		if candidate.targetId == state.get("targetId"):
			score += 1.0
		if candidate.sector == state.get("sector") and Roles.number(state.get("commitUntil")) > float(view.time):
			score += 2.0
		var primary_screen: bool = str(state.role) == "screen" and str(state.phase) == "screen" and candidate.targetId == state.get("targetId")
		grouped[ship_id].append({"candidate": candidate, "certificate": certificate, "score": score, "primaryScreen": primary_screen})
	var remaining: int = clampi(int(Roles.number(Roles.dictionary(view.get("options")).get("clearanceRemaining"), MAX_CLEARANCE)), 0, MAX_CLEARANCE)
	for ship_id: String in due_ids:
		var ship: Dictionary = context[ship_id]
		var decision: Dictionary = decisions[ship_id]
		var state: Dictionary = decision.state
		var candidates: Array = grouped[ship_id]
		# Preserve the screen's chosen protection target after B certifies offers.
		# Risk/certificate gates above and swept conflicts below still reject it.
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if bool(a.primaryScreen) != bool(b.primaryScreen):
				return bool(a.primaryScreen)
			return float(a.score) > float(b.score) if not is_equal_approx(float(a.score), float(b.score)) else str(a.candidate.candidateId) < str(b.candidate.candidateId)
		)
		var chosen: Dictionary = {}
		for offer: Dictionary in candidates:
			var reservation: Dictionary = Stations.reservation(offer.candidate, ship, offer.certificate, float(view.time)) if live_traffic_seconds051 < 0.0 else Stations._reservation_begin051(offer.candidate, ship, float(view.time), live_traffic_seconds051)
			var conflict: bool = false
			for other_id: Variant in next_memory.reservations:
				if str(other_id) == ship_id:
					continue
				var other: Dictionary = Roles.dictionary(next_memory.reservations[other_id])
				if other.is_empty() or Roles.number(other.get("until")) <= float(view.time):
					continue
				var occupied: bool = Stations.conflict(reservation, other, counters, remaining) if live_traffic_seconds051 < 0.0 else Stations._conflict_begin051(reservation, other, counters, remaining)
				if occupied:
					conflict = true
					counters.reservationConflicts = int(counters.reservationConflicts) + 1
					break
			if not conflict:
				chosen = offer
				break
		if not chosen.is_empty():
			var candidate: Dictionary = chosen.candidate
			var certificate: Dictionary = chosen.certificate
			var anchor: Vector2 = Stations.anchor(candidate)
			if state.get("targetId") != candidate.targetId or state.get("sector") != candidate.sector or Roles.number(state.get("commitUntil")) <= float(view.time):
				state["commitUntil"] = float(view.time) + Roles.COMMIT_SECONDS
			state["targetId"] = str(candidate.targetId)
			state["sector"] = int(candidate.sector)
			state["anchor"] = anchor
			state["waitSince"] = -1.0
			state["blockedStation"] = false
			by_id[ship_id] = _intent(view, ship, state, candidate, certificate)
			next_memory["reservations"][ship_id] = Stations.reservation(candidate, ship, certificate, float(view.time)) if live_traffic_seconds051 < 0.0 else Stations._reservation_begin051(candidate, ship, float(view.time), live_traffic_seconds051)
			counters.accepted = int(counters.accepted) + 1
		else:
			var reason: String = str(decision.get("rejection", "Waiting for a safe route and exit."))
			if not candidates.is_empty():
				reason = "Station or swept lane is occupied; wait or choose another approach."
			if int(counters.clearanceExhausted) > 0:
				reason = "Planning clearance budget pending; wait for a checked maneuver."
			state["blockedStation"] = true
			state["commitUntil"] = 0.0
			if Roles.number(state.get("waitSince"), -1.0) < 0.0:
				state["waitSince"] = float(view.time)
			if float(view.time) - Roles.number(state.get("waitSince")) >= 3.0:
				var prior: Dictionary = Roles.dictionary(Roles.dictionary(memory.get("byId")).get(ship_id))
				# A rejected restart never became a published new phase. Age the
				# actual retained regroup rather than resetting it on every offer.
				if str(prior.get("phase", "")) == "regroup" and str(prior.get("role", "")) == str(state.role) and prior.get("orderRevision") == state.get("orderRevision"):
					state["phaseSince"] = prior.get("phaseSince", float(view.time))
					state["safeSince"] = prior.get("safeSince", float(view.time))
				else:
					state["phaseSince"] = float(view.time)
					state["safeSince"] = float(view.time)
				state["phase"] = "regroup"
				state["reason"] = "No checked approach or exit; abandon this maneuver."
				state["failedTargetId"] = str(state.get("targetId", ""))
				state["failedUntil"] = float(view.time) + 4.0
				reason = str(state["reason"])
			by_id[ship_id] = _intent(view, ship, state, {}, {}, reason)
			next_memory["reservations"].erase(ship_id)
		next_memory["byId"][ship_id] = state
	# No target/path caches or append-only histories. One record and reservation per hull.
	return {"memory": next_memory, "byId": by_id, "counters": counters}
