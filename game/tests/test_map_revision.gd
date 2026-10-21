extends SceneTree
## Headless tests for v0.005 CoastMigration.prepare(saved, world, nav).
## Covers legacy (1)/missing/current (2)/unknown/future/malformed mapRevision values,
## pre-transform legacy validation, deep-copy isolation, Money.total & purse conservation,
## idempotence, docked (<65) vs at-sea (*4 + water/node snap) transforms, and route intent.

const CoastMigration = preload("res://scripts/coast_migration.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Navigation = preload("res://scripts/navigation.gd")
const SaveValidation = preload("res://scripts/save_validation.gd")
const Money = preload("res://scripts/money.gd")

var checks: int = 0
var failures: Array = []


func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL map revision: " + message)
	return ok


func unchanged(a, b) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		if is_nan(float(a)) and is_nan(float(b)):
			return true
		return is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not unchanged(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not unchanged(a[i], b[i]):
				return false
		return true
	return a == b


func copy_json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))


func _island_center(points: Array) -> Vector2:
	var sx: float = 0.0
	var sy: float = 0.0
	for p in points:
		sx += float(p[0])
		sy += float(p[1])
	var count: float = maxf(1.0, float(points.size()))
	return Vector2(sx / count, sy / count)


func _edge_dist(pt: Vector2, a: Array, b: Array) -> float:
	var ax: float = float(a[0])
	var ay: float = float(a[1])
	var bx: float = float(b[0])
	var by: float = float(b[1])
	var dx: float = bx - ax
	var dy: float = by - ay
	var denom: float = maxf(1e-8, dx * dx + dy * dy)
	var t: float = clampf(((pt.x - ax) * dx + (pt.y - ay) * dy) / denom, 0.0, 1.0)
	return pt.distance_to(Vector2(ax + dx * t, ay + dy * t))


func _prepare_world_fixture(raw_world: Dictionary) -> Dictionary:
	# When Root integrates v0.005 world.json, use its actual MAP_REVISION, CAMPAIGN_SCALE, and LEGACY_MAP directly.
	if raw_world.has("LEGACY_MAP") and raw_world.get("LEGACY_MAP") is Dictionary:
		return raw_world.duplicate(true)
	# Fallback only if run before world.json receives LEGACY_MAP: preserve actual world.json in LEGACY_MAP and apply 4x territory geometry.
	var expanded: Dictionary = raw_world.duplicate(true)
	expanded["MAP_REVISION"] = 2
	expanded["CAMPAIGN_SCALE"] = 4.0
	expanded["LEGACY_MAP"] = {
		"WORLD": raw_world["WORLD"].duplicate(true),
		"PORTS": raw_world["PORTS"].duplicate(true),
		"ISLANDS": raw_world["ISLANDS"].duplicate(true)
	}
	expanded["WORLD"] = {"width": 10400, "height": 7200}
	var islands: Array = raw_world["ISLANDS"]
	var ports: Array = raw_world["PORTS"]
	var associations: Array = []
	for p in ports:
		var pt := Vector2(float(p["x"]), float(p["y"]))
		var best_idx: int = 0
		var best_d: float = INF
		for i in range(islands.size()):
			var pts: Array = islands[i]["points"]
			for j in range(pts.size()):
				var d: float = _edge_dist(pt, pts[j], pts[(j + 1) % pts.size()])
				if d < best_d:
					best_d = d
					best_idx = i
		associations.append(best_idx)
	var scales: Dictionary = {}
	for i in range(islands.size()):
		scales[i] = 1.25
	for i in range(islands.size()):
		var attached: Array = []
		for n in range(ports.size()):
			if associations[n] == i:
				attached.append(ports[n])
		for n in range(attached.size()):
			for m in range(n + 1, attached.size()):
				var p1: Dictionary = attached[n]
				var p2: Dictionary = attached[m]
				var sep: float = Vector2(float(p1["x"]), float(p1["y"])).distance_to(Vector2(float(p2["x"]), float(p2["y"])))
				scales[i] = maxf(float(scales[i]), 800.0 / maxf(1.0, sep))
	for i in range(islands.size()):
		var pts: Array = islands[i]["points"]
		var c: Vector2 = _island_center(pts)
		var sc: float = float(scales[i])
		var new_pts: Array = []
		for pt in pts:
			new_pts.append([snappedf(c.x * 4.0 + (float(pt[0]) - c.x) * sc, 0.01), snappedf(c.y * 4.0 + (float(pt[1]) - c.y) * sc, 0.01)])
		expanded["ISLANDS"][i]["points"] = new_pts
	for n in range(ports.size()):
		var p: Dictionary = ports[n]
		var isl_idx: int = int(associations[n])
		var c: Vector2 = _island_center(islands[isl_idx]["points"])
		var sc: float = float(scales[isl_idx])
		expanded["PORTS"][n]["x"] = snappedf(c.x * 4.0 + (float(p["x"]) - c.x) * sc, 0.01)
		expanded["PORTS"][n]["y"] = snappedf(c.y * 4.0 + (float(p["y"]) - c.y) * sc, 0.01)
	return expanded


func _build_legacy_world(world: Dictionary) -> Dictionary:
	var legacy_world: Dictionary = world.duplicate(true)
	var legacy_map: Dictionary = world["LEGACY_MAP"]
	legacy_world["WORLD"] = legacy_map["WORLD"].duplicate(true)
	legacy_world["PORTS"] = legacy_map["PORTS"].duplicate(true)
	legacy_world["ISLANDS"] = legacy_map["ISLANDS"].duplicate(true)
	legacy_world["MAP_REVISION"] = 1
	legacy_world["CAMPAIGN_SCALE"] = 1.0
	legacy_world.erase("LEGACY_MAP")
	return legacy_world


func _ports_map(ports: Array) -> Dictionary:
	var out: Dictionary = {}
	for p in ports:
		out[str(p["id"])] = p
	return out


func _min_port_dist(pt: Vector2, ports_by_id: Dictionary) -> float:
	var best: float = INF
	for pid in ports_by_id:
		var p: Dictionary = ports_by_id[pid]
		var d: float = pt.distance_to(Vector2(float(p["x"]), float(p["y"])))
		if d < best:
			best = d
	return best


func _find_open_water_target(legacy_nav: Dictionary, legacy_start: Dictionary, legacy_ports: Dictionary, nav: Dictionary, new_start: Dictionary, scale: float) -> Dictionary:
	var candidates: Array = [
		{"x": 760.0, "y": 980.0},
		{"x": 820.0, "y": 920.0},
		{"x": 650.0, "y": 950.0},
		{"x": 900.0, "y": 980.0},
		{"x": 1250.0, "y": 920.0},
		{"x": 1400.0, "y": 860.0}
	]
	for cand in candidates:
		var cx: float = float(cand["x"])
		var cy: float = float(cand["y"])
		if _min_port_dist(Vector2(cx, cy), legacy_ports) <= 90.0:
			continue
		if not Navigation.is_water(legacy_nav, cx, cy):
			continue
		if Navigation.find_path(legacy_nav, legacy_start, cand).size() < 2:
			continue
		var sx: float = cx * scale
		var sy: float = cy * scale
		var scaled_cand := {"x": sx, "y": sy}
		if not Navigation.is_water(nav, sx, sy):
			continue
		if Navigation.find_path(nav, new_start, scaled_cand).size() < 2:
			continue
		return cand
	return {"x": 760.0, "y": 980.0}


func _verify_water_segments(nav: Dictionary, start_pt: Dictionary, path: Array, label: String) -> void:
	var prev: Dictionary = start_pt
	for waypoint in path:
		var ax: float = float(prev["x"])
		var ay: float = float(prev["y"])
		var bx: float = float(waypoint["x"])
		var by: float = float(waypoint["y"])
		var dist: float = Vector2(ax, ay).distance_to(Vector2(bx, by))
		var steps: int = maxi(1, int(ceil(dist / 4.0)))
		for i in range(steps + 1):
			var t: float = float(i) / float(steps)
			var sx: float = lerpf(ax, bx, t)
			var sy: float = lerpf(ay, by, t)
			if not Navigation.is_water(nav, sx, sy):
				check(false, "%s segment crosses non-water at (%.1f, %.1f)" % [label, sx, sy])
				return
		prev = waypoint
	check(true, label + " stays on navigable water along every segment")


func _reject_case(saved: Dictionary, world: Dictionary, nav: Dictionary, label: String) -> void:
	var snap_saved: Dictionary = saved.duplicate(true)
	var snap_world: Dictionary = world.duplicate(true)
	var res: Dictionary = CoastMigration.prepare(saved, world, nav)
	check(not res.get("ok", true), label + " is rejected")
	check(res.get("state") is Dictionary and res["state"].is_empty(), label + " returns empty state on refusal")
	check(res.get("message") is String and not str(res["message"]).is_empty(), label + " returns detailed refusal message")
	check(unchanged(saved, snap_saved), label + " does not mutate caller save")
	check(unchanged(world, snap_world), label + " does not mutate caller world")


func _initialize() -> void:
	var started: int = Time.get_ticks_msec()
	var raw_world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var world: Dictionary = _prepare_world_fixture(raw_world)
	var legacy_world: Dictionary = _build_legacy_world(world)

	check(int(world.get("MAP_REVISION", 0)) == 2, "world defines MAP_REVISION = 2")
	check(is_equal_approx(float(world.get("CAMPAIGN_SCALE", 0.0)), 4.0), "world defines CAMPAIGN_SCALE = 4.0")
	check(world.get("LEGACY_MAP") is Dictionary, "world defines LEGACY_MAP dictionary")

	var scale: float = float(world["CAMPAIGN_SCALE"])
	var new_w: float = float(world["WORLD"]["width"])
	var new_h: float = float(world["WORLD"]["height"])
	var nav: Dictionary = Navigation.create(world["ISLANDS"], new_w, new_h)

	var leg_w: float = float(legacy_world["WORLD"]["width"])
	var leg_h: float = float(legacy_world["WORLD"]["height"])
	var legacy_nav: Dictionary = Navigation.create(legacy_world["ISLANDS"], leg_w, leg_h)

	var new_ports_by_id: Dictionary = _ports_map(world["PORTS"])
	var legacy_ports_by_id: Dictionary = _ports_map(legacy_world["PORTS"])
	check(new_ports_by_id.size() == 10 and legacy_ports_by_id.size() == 10, "both legacy and current maps have all 10 stable harbors")

	# Build a real legacy campaign save using actual legacy_world definitions and real Campaign actions (no synthetic gifts).
	var legacy_core = Campaign.new(legacy_world)
	legacy_core.nav = legacy_nav
	legacy_core.new_game(505)
	legacy_core.state.erase("mapRevision")
	var trade_res: Dictionary = legacy_core.trade("brass_haven", "food", 2, "buy")
	check(trade_res.get("ok", false), "real harbor food purchase in legacy campaign")
	var offer: Dictionary = legacy_core.available_contracts()[0]
	var contract_res: Dictionary = legacy_core.accept_contract(offer["id"])
	check(contract_res.get("ok", false), "real funded contract accepted in legacy campaign")

	var legacy_docked: Dictionary = copy_json(legacy_core.state)
	legacy_docked.erase("mapRevision") # Missing save.mapRevision means 1

	# 1. Missing mapRevision (treated as 1) and explicit mapRevision = 1 migration while docked
	var snap_docked: Dictionary = legacy_docked.duplicate(true)
	var snap_world: Dictionary = world.duplicate(true)
	var migrated_res: Dictionary = CoastMigration.prepare(legacy_docked, world, nav)
	check(migrated_res.get("ok", false), "missing mapRevision (legacy=1) docked save migrates: " + str(migrated_res.get("message", "")))
	check(unchanged(legacy_docked, snap_docked), "prepare never mutates caller legacy save")
	check(unchanged(world, snap_world), "prepare never mutates caller world dictionary")

	var migrated: Dictionary = migrated_res["state"]
	check(int(migrated.get("mapRevision", 0)) == 2, "migrated state sets mapRevision = 2")
	check(Money.total(migrated) == Money.total(legacy_docked) and Money.total(migrated) == int(migrated["coinSupply"]), "Money.total and coinSupply strictly conserved")

	var explicit_rev1: Dictionary = legacy_docked.duplicate(true)
	explicit_rev1["mapRevision"] = 1
	var explicit_res: Dictionary = CoastMigration.prepare(explicit_rev1, world, nav)
	check(explicit_res.get("ok", false) and unchanged(explicit_res["state"], migrated), "explicit mapRevision=1 produces identical migrated state")

	# 2. Verify port coordinate mapping by stable ID and preservation of all purses, workforce, stocks, boats, contracts, patrols
	for i in range(migrated["ports"].size()):
		var mp: Dictionary = migrated["ports"][i]
		var op: Dictionary = legacy_docked["ports"][i]
		var pid: String = str(mp["id"])
		var target_def: Dictionary = new_ports_by_id[pid]
		check(is_equal_approx(float(mp["x"]), float(target_def["x"])) and is_equal_approx(float(mp["y"]), float(target_def["y"])), "port %s mapped to new world.PORTS coordinates" % pid)
		check(Navigation.is_water(nav, mp["x"], mp["y"]), "migrated port %s lies on navigable water" % pid)
		for field in ["cash", "householdPurse", "expertPurse", "governmentPurse", "stocks", "population", "workforce", "workers", "publicWorkers", "availableWorkers", "recruits", "prosperity", "buildQueue", "shipStock", "shipIds"]:
			check(unchanged(mp[field], op[field]), "port %s preserves %s untouched" % [pid, field])

	for field in ["coins", "crewPurse", "wageArrears", "debt", "coinSupply", "cargo", "fleet", "fleetOwners", "activeContract", "freight", "recoverable", "doneSide", "log", "moneyLog"]:
		check(unchanged(migrated[field], legacy_docked[field]), "migrated state preserves %s untouched" % field)

	check(migrated["patrols"].size() == legacy_docked["patrols"].size(), "all chart patrols retained")
	for i in range(migrated["patrols"].size()):
		var mp_patrol: Dictionary = migrated["patrols"][i]
		var op_patrol: Dictionary = legacy_docked["patrols"][i]
		check(mp_patrol["id"] == op_patrol["id"] and mp_patrol["from"] == op_patrol["from"] and mp_patrol["to"] == op_patrol["to"] and is_equal_approx(float(mp_patrol["progress"]), float(op_patrol["progress"])), "patrol %s preserves id/from/to/progress" % str(mp_patrol["id"]))

	# Verify docked position moved to new Brass Haven coordinates
	var new_haven: Dictionary = new_ports_by_id["brass_haven"]
	check(is_equal_approx(float(migrated["position"]["x"]), float(new_haven["x"])) and is_equal_approx(float(migrated["position"]["y"]), float(new_haven["y"])), "docked position moves to matching new port")
	check(migrated["path"].is_empty() and str(migrated["destination"]).is_empty(), "stationary docked save keeps empty path and destination")

	# Verify deep-copy isolation by mutating returned state and checking caller save is unaffected
	var retained_result: Dictionary=migrated.duplicate(true)
	var mutated_copy: Dictionary = migrated
	mutated_copy["coins"] = int(mutated_copy["coins"]) + 500
	mutated_copy["ports"][0]["cash"] = int(mutated_copy["ports"][0]["cash"]) - 500
	mutated_copy["fleet"][0]["hp"] = float(mutated_copy["fleet"][0]["hp"]) - 10.0
	check(unchanged(legacy_docked, snap_docked), "mutating returned state never affects original saved dictionary")
	migrated=retained_result

	# 3. Docked offset within 65 units of a legacy port moves to matching new port
	var near_kelp_save: Dictionary = legacy_docked.duplicate(true)
	var old_kelp: Dictionary = legacy_ports_by_id["kelp_reach"]
	near_kelp_save["position"] = {"x": float(old_kelp["x"]) + 36.0, "y": float(old_kelp["y"]) - 42.0} # distance ~55.3 <= 65
	near_kelp_save["lastPort"] = "kelp_reach"
	var near_kelp_res: Dictionary = CoastMigration.prepare(near_kelp_save, world, nav)
	var new_kelp: Dictionary = new_ports_by_id["kelp_reach"]
	check(near_kelp_res.get("ok", false), "position within 65 units of legacy port migrates")
	check(is_equal_approx(float(near_kelp_res["state"]["position"]["x"]), float(new_kelp["x"])) and is_equal_approx(float(near_kelp_res["state"]["position"]["y"]), float(new_kelp["y"])), "offset position within 65 moves to matching new port")

	# 4. Idempotence & current revision (mapRevision = 2) handling
	var migrated_snapshot: Dictionary = migrated.duplicate(true)
	var second_pass: Dictionary = CoastMigration.prepare(migrated, world, nav)
	check(second_pass.get("ok", false), "calling prepare on already-migrated (rev 2) state succeeds")
	check(int(second_pass["state"].get("mapRevision", 0)) == 2, "second pass keeps mapRevision = 2")
	check(unchanged(second_pass["state"], migrated_snapshot), "prepare is idempotent and never applies 4x scaling twice")
	check(unchanged(migrated, migrated_snapshot), "second pass does not mutate caller state")

	var current_core = Campaign.new(world)
	current_core.nav = nav
	current_core.new_game(606)
	var native_rev2: Dictionary = copy_json(current_core.state)
	native_rev2["mapRevision"] = 2
	var native_rev2_snap: Dictionary = native_rev2.duplicate(true)
	var native_rev2_res: Dictionary = CoastMigration.prepare(native_rev2, world, nav)
	check(native_rev2_res.get("ok", false) and unchanged(native_rev2_res["state"], native_rev2_snap), "native mapRevision=2 save validates via current validator without re-scaling")

	# 5. At-sea position scaling (*4) and route intent to destination stable port
	var course_res: Dictionary = legacy_core.chart_course(legacy_core.port_position("kelp_reach"), "kelp_reach")
	check(course_res.get("ok", false), "legacy campaign charts water course from brass_haven to kelp_reach")
	for step_i in range(45):
		legacy_core.step(1.0 / 10.0)
		var point: Dictionary=legacy_core.state.position
		if _min_port_dist(Vector2(point.x,point.y),legacy_ports_by_id)>90.0:break
	var old_sea_pos: Dictionary = legacy_core.state["position"].duplicate(true)
	check(_min_port_dist(Vector2(float(old_sea_pos["x"]), float(old_sea_pos["y"])), legacy_ports_by_id) > 65.0, "stepped legacy fleet is at sea (>65 units from all harbors)")

	var sea_port_route_save: Dictionary = copy_json(legacy_core.state)
	sea_port_route_save.erase("mapRevision")
	var sea_port_res: Dictionary = CoastMigration.prepare(sea_port_route_save, world, nav)
	check(sea_port_res.get("ok", false), "at-sea save with harbor destination migrates: " + str(sea_port_res.get("message", "")))
	var sea_state: Dictionary = {}
	if sea_port_res.get("ok", false):
		sea_state = sea_port_res["state"]
		var expected_sx: float = float(old_sea_pos["x"]) * scale
		var expected_sy: float = float(old_sea_pos["y"]) * scale
		check(Navigation.is_water(nav, sea_state["position"]["x"], sea_state["position"]["y"]), "migrated at-sea position is on actual Navigation water")
		if Navigation.is_water(nav, expected_sx, expected_sy):
			check(is_equal_approx(float(sea_state["position"]["x"]), expected_sx) and is_equal_approx(float(sea_state["position"]["y"]), expected_sy), "open-water at-sea position scales by CAMPAIGN_SCALE (4x)")
		check(str(sea_state.get("destination", "")) == "kelp_reach", "route migration retains destination port ID")
		check(sea_state["path"] is Array and not sea_state["path"].is_empty(), "rebuilt harbor route has waypoints")
		if not sea_state["path"].is_empty():
			var first_wp: Dictionary = sea_state["path"][0]
			var last_wp: Dictionary = sea_state["path"][sea_state["path"].size() - 1]
			check(not (is_equal_approx(float(first_wp["x"]), float(sea_state["position"]["x"])) and is_equal_approx(float(first_wp["y"]), float(sea_state["position"]["y"]))), "start position is removed from rebuilt path")
			check(is_equal_approx(float(last_wp["x"]), float(new_kelp["x"])) and is_equal_approx(float(last_wp["y"]), float(new_kelp["y"])), "rebuilt harbor route terminates at new destination port")
		_verify_water_segments(nav, sea_state["position"], sea_state["path"], "rebuilt harbor route")
		check(Money.total(sea_state) == Money.total(sea_port_route_save), "at-sea harbor route migration conserves Money.total")

	# 6. Open-water route intent (empty destination, final old pathpoint scaled)
	var ref_new_pos: Dictionary = sea_state.get("position", {"x": float(new_haven["x"]), "y": float(new_haven["y"])})
	var open_target_old: Dictionary = _find_open_water_target(legacy_nav, legacy_core.state["position"], legacy_ports_by_id, nav, ref_new_pos, scale)
	var open_course_res: Dictionary = legacy_core.chart_course(open_target_old, "")
	check(open_course_res.get("ok", false), "legacy campaign charts open-water course")
	var open_water_save: Dictionary = copy_json(legacy_core.state)
	open_water_save["mapRevision"] = 1
	var open_res: Dictionary = CoastMigration.prepare(open_water_save, world, nav)
	check(open_res.get("ok", false), "open-water route save migrates: " + str(open_res.get("message", "")))
	if open_res.get("ok", false):
		var open_state: Dictionary = open_res["state"]
		var expected_end_x: float = float(open_target_old["x"]) * scale
		var expected_end_y: float = float(open_target_old["y"]) * scale
		check(str(open_state.get("destination", "")).is_empty(), "open-water route keeps empty destination ID")
		check(not open_state["path"].is_empty(), "open-water route rebuilds non-empty path")
		var end_wp: Dictionary = open_state["path"][open_state["path"].size() - 1]
		check(is_equal_approx(float(end_wp["x"]), expected_end_x) and is_equal_approx(float(end_wp["y"]), expected_end_y), "open-water route targets scaled final old pathpoint")
		_verify_water_segments(nav, open_state["position"], open_state["path"], "rebuilt open-water route")

	# 7. At-sea position snapping to nearest valid nav node when reasonably close vs failing when deep in land
	var valid_node: Dictionary = {}
	for n_entry in nav["nodes"]:
		if not (n_entry is Dictionary):
			continue
		var nx: float = float(n_entry["x"])
		var ny: float = float(n_entry["y"])
		if nx < 1500.0 or nx > new_w - 1500.0 or ny < 1500.0 or ny > new_h - 1500.0:
			continue
		var candidate_old := Vector2((nx + 60.0) / scale, ny / scale)
		if _min_port_dist(candidate_old, legacy_ports_by_id) > 150.0 and _min_port_dist(Vector2(nx + 60.0, ny), new_ports_by_id) > 650.0:
			valid_node = n_entry
			break
	check(not valid_node.is_empty(), "found open-sea reference navigation node away from all harbors")
	if not valid_node.is_empty():
		# Place a small shoal obstacle over (valid_node.x + 60, valid_node.y) so the scaled point is blocked but valid_node is ~60 units away.
		var test_sx: float = float(valid_node["x"]) + 60.0
		var test_sy: float = float(valid_node["y"])
		var shoal_islands: Array = world["ISLANDS"].duplicate(true)
		shoal_islands.append({
			"id": "isl_test_shoal",
			"name": "Test Shoal",
			"points": [
				[test_sx - 25.0, test_sy - 25.0],
				[test_sx + 25.0, test_sy - 25.0],
				[test_sx + 25.0, test_sy + 25.0],
				[test_sx - 25.0, test_sy + 25.0]
			]
		})
		var shoal_nav: Dictionary = Navigation.create(shoal_islands, new_w, new_h)
		var snap_save: Dictionary = legacy_docked.duplicate(true)
		snap_save["position"] = {"x": test_sx / scale, "y": test_sy / scale}
		var snap_res: Dictionary = CoastMigration.prepare(snap_save, world, shoal_nav)
		check(snap_res.get("ok", false), "at-sea point near shore obstacle snaps to nearest valid nav node")
		if snap_res.get("ok", false):
			check(Navigation.is_water(shoal_nav, snap_res["state"]["position"]["x"], snap_res["state"]["position"]["y"]), "snapped at-sea position is on navigable water")

		# Now place a massive landmass covering >700 units around the scaled point (while keeping ports clear) so no valid nav node is reasonably close.
		var huge_land_islands: Array = world["ISLANDS"].duplicate(true)
		huge_land_islands.append({
			"id": "isl_huge_block",
			"name": "Huge Block",
			"points": [
				[test_sx - 420.0, test_sy - 420.0],
				[test_sx + 420.0, test_sy - 420.0],
				[test_sx + 420.0, test_sy + 420.0],
				[test_sx - 420.0, test_sy + 420.0]
			]
		})
		var blocked_nav: Dictionary = Navigation.create(huge_land_islands, new_w, new_h)
		_reject_case(snap_save, world, blocked_nav, "at-sea position buried deep inside land far from any valid nav node")

	# 8. Routing failure returns detailed refusal message without mutating caller
	var blocked_route_save: Dictionary = sea_port_route_save.duplicate(true)
	var isl_center: Vector2 = _island_center(world["ISLANDS"][0]["points"])
	blocked_route_save["destination"] = ""
	blocked_route_save["path"] = [{"x": isl_center.x / scale, "y": isl_center.y / scale}]
	_reject_case(blocked_route_save, world, nav, "open-water route whose scaled final waypoint lands inside an island")

	# Cordon walls around destination port so port itself is on water but unreachable from Brass Haven
	var saw_port: Dictionary = new_ports_by_id["sawtooth_mill"]
	var spx: float = float(saw_port["x"])
	var spy: float = float(saw_port["y"])
	var barrier_islands: Array = world["ISLANDS"].duplicate(true)
	barrier_islands.append({"id": "b_n", "points": [[spx - 180.0, spy - 180.0], [spx + 180.0, spy - 180.0], [spx + 180.0, spy - 120.0], [spx - 180.0, spy - 120.0]]})
	barrier_islands.append({"id": "b_s", "points": [[spx - 180.0, spy + 120.0], [spx + 180.0, spy + 120.0], [spx + 180.0, spy + 180.0], [spx - 180.0, spy + 180.0]]})
	barrier_islands.append({"id": "b_w", "points": [[spx - 180.0, spy - 180.0], [spx - 120.0, spy - 180.0], [spx - 120.0, spy + 180.0], [spx - 180.0, spy + 180.0]]})
	barrier_islands.append({"id": "b_e", "points": [[spx + 120.0, spy - 180.0], [spx + 180.0, spy - 180.0], [spx + 180.0, spy + 180.0], [spx + 120.0, spy + 180.0]]})
	var barrier_nav: Dictionary = Navigation.create(barrier_islands, new_w, new_h)
	var cross_barrier_save: Dictionary = legacy_docked.duplicate(true)
	cross_barrier_save["destination"] = "sawtooth_mill"
	cross_barrier_save["path"] = [{"x": float(legacy_ports_by_id["sawtooth_mill"]["x"]), "y": float(legacy_ports_by_id["sawtooth_mill"]["y"])}]
	_reject_case(cross_barrier_save, world, barrier_nav, "harbor route blocked by impassable cordon around destination")

	# 9. Reject unknown, future, and malformed mapRevision values before changes
	for bad_rev in [0, -1, -99, 3, 4, 999, 1.5, -0.5, NAN, INF, -INF, "1", "2", "two", null, true, false, [], {}]:
		var bad_rev_save: Dictionary = legacy_docked.duplicate(true)
		bad_rev_save["mapRevision"] = bad_rev
		_reject_case(bad_rev_save, world, nav, "malformed or unsupported mapRevision (%s)" % str(bad_rev))

	# 10. Pre-transform legacy validation rejects legacy saves with out-of-legacy-bounds coordinates or tampered coinSupply
	var out_of_legacy_bounds: Dictionary = legacy_docked.duplicate(true)
	out_of_legacy_bounds["mapRevision"] = 1
	out_of_legacy_bounds["position"] = {"x": 3200.0, "y": 1200.0} # > 2600 legacy width
	_reject_case(out_of_legacy_bounds, world, nav, "legacy save with position outside 2600x1800 legacy bounds")

	var tampered_coins: Dictionary = legacy_docked.duplicate(true)
	tampered_coins["coins"] = int(tampered_coins["coins"]) + 250
	_reject_case(tampered_coins, world, nav, "legacy save with inconsistent coinSupply ledger")

	var tampered_rev2_coins: Dictionary = migrated.duplicate(true)
	tampered_rev2_coins["coins"] = int(tampered_rev2_coins["coins"]) + 250
	_reject_case(tampered_rev2_coins, world, nav, "current rev=2 save with inconsistent coinSupply ledger")

	print("map revision: %d checks, %d failures, %dms" % [checks, failures.size(), Time.get_ticks_msec() - started])
	if failures.is_empty():
		quit(0)
	else:
		quit(1)
		assert(failures.is_empty(), "Map revision migration failures above")
