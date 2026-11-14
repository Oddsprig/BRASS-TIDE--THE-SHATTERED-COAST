extends SceneTree
## Root executes through Test Bridge. No engine subprocess or nested lane lease.
## Factory contract: zero arguments; returns the existing ready light42 battle
## Dictionary, preserving its normal Lab.create/Battle.create construction.

const Baseline = preload("res://tests/baseline_tactical_runtime101.gd")
const Candidate = preload("res://scripts/tactical_runtime.gd")
const Deployment = preload("res://scripts/deployment.gd")
const Routes = preload("res://scripts/tactical_routes.gd")

const BODY_CAP_US: int = 12000000
const WARMUP: int = 4
const CASE_SEED: int = 101051

static var checks: int = 0
static var failures: int = 0
static var began_us: int = 0
static var cap_reported: bool = false


func _initialize() -> void:
	call_deferred("_entry101")


func _entry101() -> void:
	quit(run_light101(_make_light101,12))

static func _make_light101() -> Dictionary:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var lab: Script=preload("res://scripts/fleet_lab.gd")
	var made: Dictionary=lab.create(world,{"player":[lab.entry(world,"bilge_punt",21)],"enemy":[lab.entry(world,"bilge_punt",21)]},4040)
	if not bool(made.get("ok",false)):
		push_error("V101 factory: "+str(made.get("error","")))
		return {}
	return made.battle


static func _check101(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error("V101: " + message)
	return ok


static func _budget101() -> bool:
	if Time.get_ticks_usec() - began_us <= BODY_CAP_US:
		return true
	if not cap_reported:
		cap_reported = true
		_check101(false, "12-second body budget exceeded; incomplete run.")
	return false


static func _same101(a: Variant, b: Variant, flags: bool = false) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		var ad: Dictionary = a
		var bd: Dictionary = b
		if ad.size() != bd.size():
			return false
		if flags and ad.is_read_only() != bd.is_read_only():
			return false
		for key in ad:
			if not bd.has(key) or not _same101(ad[key], bd[key], flags):
				return false
		return true
	if a is Array:
		var aa: Array = a
		var ba: Array = b
		if aa.size() != ba.size():
			return false
		if flags and aa.is_read_only() != ba.is_read_only():
			return false
		for index in range(aa.size()):
			if not _same101(aa[index], ba[index], flags):
				return false
		return true
	return a == b


static func _ids101(st: Dictionary, side: String) -> Array:
	var result: Array = []
	for id in st.tactical.ships:
		if str(st.tactical.ships[id].team) == side:
			result.append(str(id))
	return result


static func _due101(ids: Array) -> Array:
	var result: Array = []
	for index in range(ids.size()):
		if index % 2 == 0:
			result.append(ids[index])
	return result


static func _row101(payload: Dictionary, id: String) -> Dictionary:
	for row in payload.get("ships", []):
		if str(row.get("id", "")) == id:
			return row
	_check101(false, "missing payload row " + id)
	return {}


static func _prepare101(st: Dictionary) -> bool:
	if not _check101(st.get("tactical") is Dictionary,
			"factory returns an initialized battle state"):
		return false
	var t: Dictionary = st.tactical
	if not _check101(t.get("ships") is Dictionary,
			"ready tactical ship index exists"):
		return false

	st.autoBoard = false
	for side in ["player", "enemy"]:
		var ids: Array = _ids101(st, side)
		var points: int = 0
		var spec_ids: Dictionary = {}
		for id in ids:
			var ship: Dictionary = t.ships[id]
			points += int(Deployment.cost(ship.spec))
			spec_ids[str(ship.spec.id)] = true

		if not _check101(ids.size() == 21 and points == 294,
				"%s has exactly 21 boats and 294 DP" % side):
			return false
		print("V101_FLEET ", JSON.stringify({
			"side": side,
			"boats": ids.size(),
			"points": points,
			"specIds": spec_ids.keys()
		}))

		# One due and one non-due owner exercise targetless attack resolution.
		# Give both real live nested options so ownership probes are meaningful.
		for index in [0, 1]:
			var id: String = str(ids[index])
			var ship: Dictionary = t.ships[id]
			ship.order = "attack"
			ship.orderTarget = {}
			var choice: Dictionary = t.options.byId.get(
				id, Baseline.defaults()).duplicate(true)
			choice.rally = {
				"x": float(ship.x) + 60.0,
				"y": float(ship.y) + 40.0
			}
			t.options.byId[id] = choice
	return true


static func _pair101(factory: Callable) -> Array:
	var result: Array = []
	for index in range(2):
		if not _budget101():
			return []
		seed(CASE_SEED)
		var made: Variant = factory.call()
		if not _check101(made is Dictionary, "factory returns Dictionary"):
			return []
		var st: Dictionary = made
		if not _prepare101(st):
			return []
		result.append(st)

	var a: Dictionary = result[0]
	var b: Dictionary = result[1]
	_check101(_same101(a.tactical.ships, b.tactical.ships),
		"baseline/candidate start with identical live hull values")
	_check101(_same101(a.tactical.options, b.tactical.options),
		"baseline/candidate start with identical options")
	_check101(_same101(a.get("mission", {}), b.get("mission", {})),
		"baseline/candidate start with identical mission")
	_check101(float(a.time) == float(b.time), "identical initial time")
	_check101(bool(Baseline._fleet_goals051(a.tactical)),
		"baseline exercises sampled fleet worker path")
	_check101(bool(Candidate._fleet_goals051(b.tactical)),
		"candidate exercises sampled fleet worker path")
	return result


static func _view101(runtime: Script, mode: String, st: Dictionary,
		side: String, due: Array) -> Dictionary:
	var baseline: bool=runtime==Baseline
	if mode == "public":
		return Baseline.view(st,side,due,null) if baseline else Candidate.view(st,side,due,null)
	if mode == "main":
		return Baseline._begin_view051(st,side,due,null,{}) if baseline else Candidate._begin_view051(st,side,due,null,{})
	if mode == "main_cached":
		var current: Dictionary = {}
		if baseline:Baseline._begin_context051(st,side,null,current)
		else:Candidate._begin_context051(st,side,null,current)
		return Baseline._begin_view051(st,side,due,null,current) if baseline else Candidate._begin_view051(st,side,due,null,current)
	if mode == "legacy":
		return Baseline._begin_view051(st,side,due,null) if baseline else Candidate._begin_view051(st,side,due,null)
	return Baseline._worker_view051(st,side,due,null) if baseline else Candidate._worker_view051(st,side,due,null)


static func _aliases101(st: Dictionary, payload: Dictionary,
		label: String) -> void:
	var t: Dictionary = st.tactical
	for row in payload.ships:
		var id: String = str(row.id)
		var observed: Dictionary = t.observed[id]
		_check101(is_same(observed.mounts, t.mountCache[id].mounts),
			label + ": main observation retains mount-generation alias " + id)
		_check101(not is_same(row, observed),
			label + ": worker row detached " + id)
		for key in ["mounts", "mountShotTimes", "spec"]:
			_check101(not is_same(row[key], observed[key]),
				label + ": worker " + key + " detached " + id)


static func _probe101(value: Variant, marker: int, depth: int = 0) -> void:
	if depth > 24:
		_check101(false, "unexpected probe nesting depth")
		return
	if value is Dictionary:
		var dictionary: Dictionary = value
		if not _check101(not dictionary.is_read_only(),
				"worker nested Dictionary remains mutable"):
			return
		for key in dictionary.keys():
			_probe101(dictionary[key], marker, depth + 1)
		dictionary["__v101_probe"] = marker
	elif value is Array:
		var array: Array = value
		if not _check101(not array.is_read_only(),
				"worker nested Array remains mutable"):
			return
		for child in array:
			_probe101(child, marker, depth + 1)
		# resize changes even an empty typed Array without guessing element type.
		array.resize(array.size() + 1)


static func _targets101(st: Dictionary, payload: Dictionary,
		side: String, ids: Array) -> void:
	for index in [0, 1]:
		var id: String = str(ids[index])
		var owner: Dictionary = _row101(payload, id)
		if owner.is_empty():
			continue
		_check101(str(owner.get("order", "")) == "attack",
			"targetless attack exercised for due/non-due " + id)
		var nearest: String = ""
		var best: float = INF
		for enemy_id in st.tactical.observed:
			var enemy: Dictionary = st.tactical.observed[enemy_id]
			if str(enemy.team) == side:
				continue
			var distance: float = Routes.point(
				st.tactical.ships[id]).distance_squared_to(Routes.point(enemy))
			if distance < best:
				best = distance
				nearest = str(enemy_id)
		_check101(str(owner.get("orderTarget", {}).get("shipId", "")) == nearest,
			"target uses this request's observation generation " + id)


static func _functional101(a: Dictionary, b: Dictionary, side: String) -> void:
	var ids: Array = _ids101(b, side)
	var due: Array = _due101(ids)
	var enemy_side: String = "enemy" if side == "player" else "player"
	var enemy_ids: Array = _ids101(b, enemy_side)

	var left: Dictionary = _view101(Baseline, "worker", a, side, due)
	var capsule: Dictionary = _view101(Candidate, "worker", b, side, due)
	_check101(_same101(left, capsule, true), side + ": worker payload parity")
	_check101(_same101(a.tactical.observed, b.tactical.observed, true),
		side + ": main observation parity")
	_aliases101(a, left, side + " baseline")
	_aliases101(b, capsule, side + " candidate")
	_targets101(b, capsule, side, ids)

	var first_observed: Dictionary = b.tactical.observed
	var first_observed_before: Dictionary = first_observed.duplicate(true)
	var second: Dictionary = _view101(Candidate, "worker", b, side, due)
	_check101(_same101(capsule, second, true),
		side + ": repeated unchanged request has identical values")
	_check101(not is_same(first_observed, b.tactical.observed),
		side + ": each request replaces the observation root")
	_aliases101(b, second, side + " second candidate")

	var live_before: Dictionary = b.duplicate(true)
	var second_before: Dictionary = second.duplicate(true)
	var probe_ids: Array = [ids[0], ids[1], enemy_ids[0]]
	for index in range(probe_ids.size()):
		var row: Dictionary = _row101(capsule, str(probe_ids[index]))
		if row.is_empty():
			continue
		for key in ["mounts", "mountShotTimes", "spec"]:
			_probe101(row[key], 101 + index)
		row.x = float(row.x) + 0.5
		if index < 2:
			_probe101(row.get("orderTarget"), 201 + index)
			_probe101(row.get("status"), 301 + index)
			row.order = "hold"
			_probe101(capsule.options.byId[str(probe_ids[index])], 401 + index)
	_probe101(capsule.dueIds, 501)
	_probe101(capsule.groups, 502)

	_check101(_same101(b, live_before),
		side + ": nested capsule mutations leave live state/current observations unchanged")
	_check101(_same101(second, second_before),
		side + ": successive worker capsules are independent")
	_check101(_same101(first_observed, first_observed_before),
		side + ": retained main observation generation remains unchanged")

	var moved_id: String = ""
	for id in enemy_ids:
		var ship: Dictionary = b.tactical.ships[id]
		if not bool(ship.get("sunk", false)) and float(ship.get("hp", 0.0)) > 0.0:
			moved_id = str(id)
			break
	if not _check101(not moved_id.is_empty(), "live enemy exists for freshness probe"):
		return

	var previous_observed: Dictionary = b.tactical.observed
	var old_x: float = float(b.tactical.ships[moved_id].x)
	var new_x: float = old_x + 4096.25
	a.tactical.ships[moved_id].x = new_x
	b.tactical.ships[moved_id].x = new_x
	_check101(_same101(second, second_before),
		side + ": live enemy mutation cannot change an existing capsule")
	_check101(float(previous_observed[moved_id].x) == old_x,
		side + ": published observation scalar remains its sampled value")

	var fresh_left: Dictionary = _view101(Baseline, "worker", a, side, due)
	var fresh: Dictionary = _view101(Candidate, "worker", b, side, due)
	_check101(_same101(fresh_left, fresh, true),
		side + ": parity after live enemy movement")
	_check101(float(_row101(fresh, moved_id).get("x", INF)) == new_x,
		side + ": next worker request observes live enemy position")
	_check101(not is_same(previous_observed, b.tactical.observed),
		side + ": freshness does not reuse the preceding observation root")
	_check101(_same101(second, second_before),
		side + ": next request leaves old capsule unchanged")
	_targets101(b, fresh, side, ids)

	for mode in ["public", "main", "main_cached", "legacy"]:
		if not _budget101():
			return
		var control_a: Dictionary = _view101(Baseline, mode, a, side, due)
		var control_b: Dictionary = _view101(Candidate, mode, b, side, due)
		_check101(_same101(control_a, control_b, true),
			side + ": " + mode + " values and read-only flags unchanged")


static func _timed101(runtime: Script, st: Dictionary,
		side: String, due: Array) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var payload: Dictionary = Baseline._worker_view051(st,side,due,null) if runtime==Baseline else Candidate._worker_view051(st,side,due,null)
	var elapsed: int = Time.get_ticks_usec() - started
	return {"us": elapsed, "payload": payload}


static func _median101(values: Array) -> float:
	var ordered: Array = values.duplicate()
	ordered.sort()
	var middle: int = ordered.size() >> 1
	if ordered.size() % 2 == 0:
		return (float(ordered[middle - 1]) + float(ordered[middle])) * 0.5
	return float(ordered[middle])


static func _benchmark101(a: Dictionary, b: Dictionary,
		side: String, pairs: int) -> void:
	var due: Array = _due101(_ids101(b, side))
	for index in range(WARMUP):
		if not _budget101():
			return
		_view101(Baseline, "worker", a, side, due)
		if not _budget101():
			return
		_view101(Candidate, "worker", b, side, due)

	var raw: Array = []
	var baseline_us: Array = []
	var candidate_us: Array = []
	for index in range(pairs):
		if not _budget101():
			return
		var left: Dictionary
		var right: Dictionary
		if index % 2 == 0:
			left = _timed101(Baseline, a, side, due)
			if not _budget101():
				return
			right = _timed101(Candidate, b, side, due)
		else:
			right = _timed101(Candidate, b, side, due)
			if not _budget101():
				return
			left = _timed101(Baseline, a, side, due)
		if not _budget101():
			return

		# Validation, bookkeeping and output are outside construction timers.
		_check101(_same101(left.payload, right.payload, true),
			"%s timed pair %d payload parity" % [side, index])
		baseline_us.append(int(left.us))
		candidate_us.append(int(right.us))
		raw.append({
			"pair": index,
			"first": "baseline" if index % 2 == 0 else "candidate",
			"baselineUs": int(left.us),
			"candidateUs": int(right.us)
		})

	print("V101_TIMING ", JSON.stringify({
		"side": side,
		"warmup": WARMUP,
		"pairs": pairs,
		"due": due.size(),
		"nonDue": 21 - due.size(),
		"raw": raw,
		"baselineMedianUs": _median101(baseline_us),
		"candidateMedianUs": _median101(candidate_us),
		"performanceConclusion": "UNASSESSED",
		"scope": "synchronous worker-view construction only"
	}))


static func _finish101() -> int:
	_budget101()
	print("V101_DONE ", JSON.stringify({
		"status": "PASS" if failures == 0 else "FAIL",
		"checks": checks,
		"failures": failures,
		"bodyUs": Time.get_ticks_usec() - began_us,
		"bodyBudgetUs": BODY_CAP_US,
		"performanceConclusion": "UNASSESSED"
	}))
	return 0 if failures == 0 else 1


static func run_light101(make_light42: Callable, pairs: int = 12) -> int:
	checks = 0
	failures = 0
	cap_reported = false
	began_us = Time.get_ticks_usec()

	if not _check101(make_light42.is_valid(), "valid existing light42 factory"):
		return _finish101()
	if not _check101(pairs == 12 or pairs == 24, "pairs must be 12 or 24"):
		return _finish101()

	Baseline.set_runtime_profile043(false)
	Candidate.set_runtime_profile043(false)

	var states: Array = _pair101(make_light42)
	if states.size() != 2 or failures > 0:
		return _finish101()
	for side in ["player", "enemy"]:
		if not _budget101():
			return _finish101()
		_functional101(states[0], states[1], side)
		if failures > 0:
			return _finish101()

	# Fresh original placements for timing; ownership probes never enter them.
	states = _pair101(make_light42)
	if states.size() != 2 or failures > 0:
		return _finish101()
	for side in ["player", "enemy"]:
		_benchmark101(states[0], states[1], side, pairs)
		if failures > 0:
			return _finish101()
	return _finish101()
