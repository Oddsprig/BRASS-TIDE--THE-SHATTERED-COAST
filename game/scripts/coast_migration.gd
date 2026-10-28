extends RefCounted
## Copy-first save revision preflight and legacy (v0.001/v0.002 -> v0.005) coast migration.
## Pure static module: no Campaign, SceneTree, filesystem, or live-state dependency.

const SaveValidation = preload("res://scripts/save_validation.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Money = preload("res://scripts/money.gd")

const LEGACY_MAP_REVISION: int = 1
const CURRENT_MAP_REVISION: int = 2
const DEFAULT_CAMPAIGN_SCALE: float = 4.0
const DOCK_RADIUS: float = 65.0
const MIN_SNAP_RADIUS: float = 180.0
const MAX_SNAP_RADIUS: float = 360.0
const SNAP_CELL_FACTOR: float = 2.25

const FALLBACK_LEGACY_MAP: Dictionary = {
	"WORLD": {"width": 2600, "height": 1800},
	"PORTS": [
		{"id": "brass_haven", "name": "Brass Haven", "faction": "compact", "x": 495, "y": 1240, "population": 6800, "industry": "trade", "wealth": 78, "shipIds": ["tin_skiff", "lantern_skiff", "harbor_sloop", "mercantile_clipper", "aegis_corvette"]},
		{"id": "kelp_reach", "name": "Kelp Reach", "faction": "reed", "x": 530, "y": 630, "population": 4400, "industry": "fishery", "wealth": 56, "shipIds": ["tin_skiff", "marsh_dart", "silt_lugger", "gale_cutter"]},
		{"id": "sawtooth_mill", "name": "Sawtooth Mill", "faction": "compact", "x": 680, "y": 390, "population": 5100, "industry": "timber", "wealth": 64, "shipIds": ["tin_skiff", "harbor_sloop", "lantern_skiff", "cobalt_frigate"]},
		{"id": "silt_hollow", "name": "Silt Hollow", "faction": "reed", "x": 1010, "y": 1280, "population": 5900, "industry": "agriculture", "wealth": 60, "shipIds": ["marsh_dart", "silt_lugger", "reed_stinger", "manta_strike"]},
		{"id": "cinder_quay", "name": "Cinder Quay", "faction": "forge", "x": 1080, "y": 620, "population": 8200, "industry": "foundry", "wealth": 84, "shipIds": ["ash_corvette", "slag_gunboat", "cinder_monitor", "bellows_gunboat"]},
		{"id": "anvil_dock", "name": "Anvil Dock", "faction": "forge", "x": 1525, "y": 580, "population": 7600, "industry": "shipyard", "wealth": 88, "shipIds": ["ash_corvette", "bellows_gunboat", "furnace_turret", "iron_bastion", "maiden_dreadnought"]},
		{"id": "reed_floats", "name": "Reedwater Floats", "faction": "reed", "x": 1585, "y": 1075, "population": 6300, "industry": "trade", "wealth": 70, "shipIds": ["marsh_dart", "reed_stinger", "gale_cutter", "mercantile_clipper", "manta_strike"]},
		{"id": "naphtha_bay", "name": "Naphtha Bay", "faction": "forge", "x": 1920, "y": 455, "population": 6900, "industry": "refinery", "wealth": 82, "shipIds": ["slag_gunboat", "cinder_monitor", "cobalt_frigate", "furnace_turret"]},
		{"id": "rust_anchorage", "name": "Rust Anchorage", "faction": "raiders", "x": 2125, "y": 885, "population": 4800, "industry": "fishery", "wealth": 58, "shipIds": ["bilge_punt", "scab_cutter", "hook_raider", "barbed_lance", "krill_torpedo"]},
		{"id": "shatter_spire", "name": "Shatter Spire", "faction": "raiders", "x": 2225, "y": 1125, "population": 7400, "industry": "shipyard", "wealth": 86, "shipIds": ["scab_cutter", "krill_torpedo", "wraith_rocket", "iron_bastion", "maiden_dreadnought"]}
	],
	"ISLANDS": [
		{"id": "isl_lantern", "name": "Lantern Cay", "color": "#4b5563", "points": [[210, 1180], [410, 1160], [445, 1330], [305, 1410], [190, 1300]]},
		{"id": "isl_kelp", "name": "Kelpback Shoal", "color": "#3f6212", "points": [[230, 560], [435, 530], [470, 680], [350, 745], [215, 670]]},
		{"id": "isl_sawtooth", "name": "Sawtooth Crag", "color": "#57534e", "points": [[520, 150], [770, 135], [810, 275], [660, 330], [500, 265]]},
		{"id": "isl_verdigris", "name": "Verdigris Atoll", "color": "#365314", "points": [[860, 1360], [1150, 1335], [1190, 1495], [1010, 1565], [835, 1475]]},
		{"id": "isl_cinder", "name": "Cinder Crown", "color": "#78350f", "points": [[1170, 480], [1420, 465], [1465, 625], [1310, 680], [1145, 600]]},
		{"id": "isl_fen", "name": "Kettle Fen Isle", "color": "#14532d", "points": [[1475, 1145], [1705, 1135], [1745, 1265], [1595, 1320], [1445, 1245]]},
		{"id": "isl_oilstone", "name": "Oilstone Bluff", "color": "#44403c", "points": [[1790, 195], [2055, 180], [2095, 335], [1930, 390], [1760, 315]]},
		{"id": "isl_shatter", "name": "Shatter Bastion", "color": "#7f1d1d", "points": [[2210, 800], [2430, 780], [2470, 980], [2275, 1085], [2185, 955]]}
	]
}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "state": {}, "message": message}


static func _ok(state: Dictionary, message: String) -> Dictionary:
	return {"ok": true, "state": state, "message": message}


static func _is_finite_number(v) -> bool:
	if v is bool or not (v is int or v is float):
		return false
	return is_finite(float(v))


static func _is_finite_int(v) -> bool:
	if not _is_finite_number(v):
		return false
	var n: float = float(v)
	return floor(n) == n


static func _parse_save_revision(saved: Dictionary) -> Dictionary:
	if not saved.has("mapRevision"):
		return {"ok": true, "revision": LEGACY_MAP_REVISION}
	var raw = saved.get("mapRevision")
	if not _is_finite_int(raw):
		return {"ok": false, "revision": -1, "message": "Save refused: save.mapRevision must be a finite integer."}
	return {"ok": true, "revision": int(float(raw))}


static func _parse_world_revision(world: Dictionary) -> Dictionary:
	if not world.has("MAP_REVISION"):
		return {"ok": true, "revision": CURRENT_MAP_REVISION}
	var raw = world.get("MAP_REVISION")
	if not _is_finite_int(raw):
		return {"ok": false, "revision": -1, "message": "Save refused: world.MAP_REVISION must be a finite integer."}
	var rev: int = int(float(raw))
	if rev != CURRENT_MAP_REVISION:
		return {"ok": false, "revision": rev, "message": "Save refused: unsupported world.MAP_REVISION %d (expected %d)." % [rev, CURRENT_MAP_REVISION]}
	return {"ok": true, "revision": rev}


static func _parse_campaign_scale(world: Dictionary) -> Dictionary:
	if not world.has("CAMPAIGN_SCALE"):
		return {"ok": true, "scale": DEFAULT_CAMPAIGN_SCALE}
	var raw = world.get("CAMPAIGN_SCALE")
	if not _is_finite_number(raw) or float(raw) <= 0.0:
		return {"ok": false, "scale": 0.0, "message": "Save refused: world.CAMPAIGN_SCALE must be a positive finite number."}
	return {"ok": true, "scale": float(raw)}


static func _build_legacy_world(world: Dictionary) -> Dictionary:
	var legacy_map: Dictionary = {}
	if world.has("LEGACY_MAP"):
		if not (world.get("LEGACY_MAP") is Dictionary):
			return {"ok": false, "world": {}, "message": "Save refused: world.LEGACY_MAP must be a dictionary."}
		legacy_map = world["LEGACY_MAP"]
	else:
		legacy_map = FALLBACK_LEGACY_MAP
	var legacy_dims = legacy_map.get("WORLD")
	var legacy_ports = legacy_map.get("PORTS")
	var legacy_islands = legacy_map.get("ISLANDS")
	if not (legacy_dims is Dictionary) or not _is_finite_number(legacy_dims.get("width")) or not _is_finite_number(legacy_dims.get("height")) or float(legacy_dims["width"]) <= 0.0 or float(legacy_dims["height"]) <= 0.0:
		return {"ok": false, "world": {}, "message": "Save refused: world.LEGACY_MAP.WORLD dimensions are missing or invalid."}
	if not (legacy_ports is Array) or legacy_ports.is_empty():
		return {"ok": false, "world": {}, "message": "Save refused: world.LEGACY_MAP.PORTS must be a non-empty array."}
	if not (legacy_islands is Array):
		return {"ok": false, "world": {}, "message": "Save refused: world.LEGACY_MAP.ISLANDS must be an array."}
	var copied_world: Dictionary = world.duplicate(true)
	copied_world["WORLD"] = legacy_dims.duplicate(true)
	copied_world["PORTS"] = legacy_ports.duplicate(true)
	copied_world["ISLANDS"] = legacy_islands.duplicate(true)
	return {"ok": true, "world": copied_world}


static func _ports_by_id(ports_array: Array) -> Dictionary:
	var table: Dictionary = {}
	for entry in ports_array:
		if not (entry is Dictionary):
			return {}
		var pid = entry.get("id")
		if not (pid is String) or pid.is_empty():
			return {}
		if not _is_finite_number(entry.get("x")) or not _is_finite_number(entry.get("y")):
			return {}
		if table.has(pid):
			return {}
		table[pid] = entry
	return table


static func _find_docked_port_id(pos: Dictionary, legacy_ports: Dictionary, preferred_id: String = "") -> String:
	var px: float = float(pos["x"])
	var py: float = float(pos["y"])
	var pvec := Vector2(px, py)
	var best_id: String = ""
	var best_dist: float = DOCK_RADIUS
	for pid in legacy_ports:
		var port_def: Dictionary = legacy_ports[pid]
		var d: float = pvec.distance_to(Vector2(float(port_def["x"]), float(port_def["y"])))
		if d <= DOCK_RADIUS:
			if best_id.is_empty() or d < best_dist - 0.001 or (is_equal_approx(d, best_dist) and pid == preferred_id):
				best_dist = d
				best_id = str(pid)
	return best_id


static func _has_nav_connectors(nav: Dictionary, pt: Dictionary) -> bool:
	if not (nav is Dictionary) or nav.is_empty():
		return false
	var connectors: Array = Navigation._connectors(nav, pt)
	return not connectors.is_empty()


static func _nearest_valid_nav_node(nav: Dictionary, x: float, y: float) -> Dictionary:
	if not (nav is Dictionary) or nav.is_empty() or not (nav.get("nodes") is Array):
		return {"ok": false, "point": {}, "distance": INF, "maxDistance": 0.0}
	var cell: float = DEFAULT_CAMPAIGN_SCALE * 40.0
	if _is_finite_number(nav.get("cell")) and float(nav["cell"]) > 0.0:
		cell = float(nav["cell"])
	var max_dist: float = clampf(cell * SNAP_CELL_FACTOR, MIN_SNAP_RADIUS, MAX_SNAP_RADIUS)
	var nodes: Array = nav["nodes"]
	var edges = nav.get("edges")
	var has_edges: bool = edges is Array and edges.size() == nodes.size()
	var target := Vector2(x, y)
	var best_pt: Dictionary = {}
	var best_dist: float = INF
	for i in range(nodes.size()):
		var node = nodes[i]
		if not (node is Dictionary):
			continue
		if not _is_finite_number(node.get("x")) or not _is_finite_number(node.get("y")):
			continue
		if has_edges and (not (edges[i] is Array) or edges[i].is_empty()):
			continue
		var nx: float = float(node["x"])
		var ny: float = float(node["y"])
		if not Navigation.is_water(nav, nx, ny):
			continue
		var d: float = target.distance_to(Vector2(nx, ny))
		if d < best_dist:
			best_dist = d
			best_pt = {"x": nx, "y": ny}
	if best_pt.is_empty() or best_dist > max_dist:
		return {"ok": false, "point": {}, "distance": best_dist, "maxDistance": max_dist}
	return {"ok": true, "point": best_pt, "distance": best_dist, "maxDistance": max_dist}


static func place_on_water(nav: Dictionary, point: Dictionary) -> Dictionary:
	# Nearest connected chart water. Already-safe positions are returned unchanged.
	if not (point is Dictionary) or not _is_finite_number(point.get("x")) or not _is_finite_number(point.get("y")):
		return {"ok": false, "point": {}, "moved": false}
	var current := {"x": float(point["x"]), "y": float(point["y"])}
	if Navigation.is_water(nav, current["x"], current["y"]) and _has_nav_connectors(nav, current):
		return {"ok": true, "point": current, "moved": false}
	if not (nav is Dictionary) or not (nav.get("nodes") is Array):
		return {"ok": false, "point": {}, "moved": false}
	var nodes: Array = nav["nodes"]
	var edges = nav.get("edges")
	var has_edges: bool = edges is Array and edges.size() == nodes.size()
	var target := Vector2(float(current["x"]), float(current["y"]))
	var best: Dictionary = {}
	var best_dist := INF
	for i in range(nodes.size()):
		var node = nodes[i]
		if not (node is Dictionary) or not _is_finite_number(node.get("x")) or not _is_finite_number(node.get("y")):
			continue
		if has_edges and (not (edges[i] is Array) or (edges[i] as Array).is_empty()):
			continue
		if not Navigation.is_water(nav, node["x"], node["y"]):
			continue
		var d := target.distance_to(Vector2(float(node["x"]), float(node["y"])))
		if d < best_dist:
			best_dist = d
			best = {"x": float(node["x"]), "y": float(node["y"])}
	if best.is_empty():
		return {"ok": false, "point": {}, "moved": false}
	return {"ok": true, "point": best, "moved": true}


static func _correct_current_chart(state: Dictionary, world: Dictionary, nav: Dictionary) -> String:
	# Rev 2 careers stay byte-for-byte when they are already in safe water.
	# Land added inland of a harbor only relocates a stranded position or patrol,
	# then rebuilds the same destination. Coins, crew and harbor stores are untouched.
	if nav == null or nav.is_empty() or not (nav.get("nodes") is Array):
		return ""
	if not (state.get("position") is Dictionary):
		return ""
	if not state.has("world064"):
		var placed := place_on_water(nav, state["position"])
		if not placed.get("ok", false):
			return "Save refused: chart position is inland and no safe water could be found."
		var moved: bool = bool(placed.get("moved", false))
		if moved:
			state["position"] = placed["point"]
		var path: Array = state.get("path", []) if state.get("path") is Array else []
		var blocked := moved or (not path.is_empty() and not Navigation.path_clear(nav, state["position"], path))
		if blocked:
			var destination := str(state.get("destination", ""))
			var target: Dictionary = {}
			if not destination.is_empty() and world.get("PORTS") is Array:
				for port in world["PORTS"]:
					if port is Dictionary and str(port.get("id", "")) == destination:
						target = {"x": float(port["x"]), "y": float(port["y"])}
						break
			elif not path.is_empty() and path[path.size() - 1] is Dictionary:
				var last: Dictionary = path[path.size() - 1]
				var end := place_on_water(nav, last)
				if end.get("ok", false):
					target = end["point"]
			if target.is_empty():
				state["path"] = []
			else:
				var route: Array = Navigation.find_path(nav, state["position"], target)
				if route.size() >= 2:
					route.pop_front()
					state["path"] = route
				else:
					state["path"] = []
	if state.get("patrols") is Array:
		for patrol in state["patrols"]:
			if not (patrol is Dictionary) or not _is_finite_number(patrol.get("x")) or not _is_finite_number(patrol.get("y")):
				continue
			var patrol_point := place_on_water(nav, {"x": patrol["x"], "y": patrol["y"]})
			if patrol_point.get("ok", false) and bool(patrol_point.get("moved", false)):
				patrol["x"] = float(patrol_point["point"]["x"])
				patrol["y"] = float(patrol_point["point"]["y"])
	return ""


static func _resolve_at_sea_position(old_pos: Dictionary, scale: float, nav: Dictionary) -> Dictionary:
	var sx: float = float(old_pos["x"]) * scale
	var sy: float = float(old_pos["y"]) * scale
	var candidate := {"x": sx, "y": sy}
	if Navigation.is_water(nav, sx, sy) and _has_nav_connectors(nav, candidate):
		return {"ok": true, "position": candidate, "snapped": false}
	var snap: Dictionary = _nearest_valid_nav_node(nav, sx, sy)
	if snap.get("ok", false):
		return {"ok": true, "position": snap["point"], "snapped": true}
	return {
		"ok": false,
		"position": {},
		"message": "Save refused: scaled at-sea position (%.1f, %.1f) is not on navigable water and nearest valid nav node is %.1f units away (max %.1f)." % [sx, sy, float(snap.get("distance", INF)), float(snap.get("maxDistance", 0.0))]
	}


static func prepare(saved: Dictionary, world: Dictionary, nav: Dictionary,context064: Dictionary={}) -> Dictionary:
	if saved == null or not (saved is Dictionary) or saved.is_empty():
		return _fail("Save refused: save data must be a non-empty dictionary.")
	if world == null or not (world is Dictionary) or world.is_empty():
		return _fail("Save refused: world definitions must be a non-empty dictionary.")
	var world_rev_check: Dictionary = _parse_world_revision(world)
	if not world_rev_check.get("ok", false):
		return _fail(str(world_rev_check.get("message", "Invalid world map revision.")))
	var target_rev: int = int(world_rev_check["revision"])

	var save_rev_check: Dictionary = _parse_save_revision(saved)
	if not save_rev_check.get("ok", false):
		return _fail(str(save_rev_check.get("message", "Invalid save map revision.")))
	var rev: int = int(save_rev_check["revision"])

	if rev > target_rev:
		return _fail("Save refused: unsupported future mapRevision %d (current world is %d)." % [rev, target_rev])
	if rev != LEGACY_MAP_REVISION and rev != target_rev:
		return _fail("Save refused: unknown mapRevision %d (expected %d or %d)." % [rev, LEGACY_MAP_REVISION, target_rev])

	# Current revision path: validate against current world, verify coin conservation, return deep copy without re-scaling.
	if rev == target_rev:
		var current_validation: Dictionary = SaveValidation.validate(saved, world,context064)
		if not current_validation.get("ok", false):
			return _fail("Save refused: " + str(current_validation.get("message", "invalid current save schema")))
		var current_coins: int = Money.total(saved)
		if current_coins != int(saved.get("coinSupply", -1)):
			return _fail("Save refused: coin ledger mismatch (%d != %d)." % [current_coins, int(saved.get("coinSupply", -1))])
		var current_state: Dictionary = saved.duplicate(true)
		current_state["mapRevision"] = target_rev
		var chart_error := _correct_current_chart(current_state, world, nav)
		if not chart_error.is_empty():
			return _fail(chart_error)
		if Money.total(current_state) != current_coins:
			return _fail("Save refused: coin total changed during state preparation.")
		return _ok(current_state, "Save verified at map revision %d." % target_rev)

	if saved.has("world064"):return _fail("Save refused: world064 requires the current home map revision.")

	# Legacy revision (1 -> 2) path: validate against copied legacy world before any coordinate transform.
	var scale_check: Dictionary = _parse_campaign_scale(world)
	if not scale_check.get("ok", false):
		return _fail(str(scale_check.get("message", "Invalid campaign scale.")))
	var scale: float = float(scale_check["scale"])

	var legacy_world_res: Dictionary = _build_legacy_world(world)
	if not legacy_world_res.get("ok", false):
		return _fail(str(legacy_world_res.get("message", "Invalid legacy map definitions.")))
	var legacy_world: Dictionary = legacy_world_res["world"]

	var legacy_validation: Dictionary = SaveValidation.validate(saved, legacy_world)
	if not legacy_validation.get("ok", false):
		return _fail("Save refused: " + str(legacy_validation.get("message", "invalid legacy save schema")))

	var initial_money: int = Money.total(saved)
	if initial_money != int(saved.get("coinSupply", -1)):
		return _fail("Save refused: coin ledger mismatch (%d != %d)." % [initial_money, int(saved.get("coinSupply", -1))])

	if nav == null or not (nav is Dictionary) or nav.is_empty():
		return _fail("Save refused: navigation graph is unavailable for coast migration.")

	var new_ports_list = world.get("PORTS")
	var legacy_ports_list = legacy_world.get("PORTS")
	if not (new_ports_list is Array) or not (legacy_ports_list is Array) or new_ports_list.size() != legacy_ports_list.size():
		return _fail("Save refused: world port definitions do not match legacy harbor count.")

	var new_ports_by_id: Dictionary = _ports_by_id(new_ports_list)
	var legacy_ports_by_id: Dictionary = _ports_by_id(legacy_ports_list)
	if new_ports_by_id.size() != new_ports_list.size() or legacy_ports_by_id.size() != legacy_ports_list.size():
		return _fail("Save refused: world or legacy port definitions contain duplicate or invalid harbor IDs.")
	for pid in legacy_ports_by_id:
		if not new_ports_by_id.has(pid):
			return _fail("Save refused: legacy harbor '%s' is missing from current world definitions." % str(pid))

	# Work strictly on a deep copy of saved; caller state is never mutated.
	var state: Dictionary = saved.duplicate(true)
	var old_pos: Dictionary = {"x": float(state["position"]["x"]), "y": float(state["position"]["y"])}
	var old_path: Array = state.get("path", []).duplicate(true)
	var dest_id: String = str(state.get("destination", ""))
	var last_port_id: String = str(state.get("lastPort", ""))

	# Also allow docking detection against saved port coordinates prior to mapping, if within legacy bounds.
	var saved_legacy_ports: Dictionary = {}
	for saved_p in state.get("ports", []):
		if saved_p is Dictionary and saved_p.get("id") is String and _is_finite_number(saved_p.get("x")) and _is_finite_number(saved_p.get("y")):
			var sid: String = str(saved_p["id"])
			saved_legacy_ports[sid] = {"id": sid, "x": float(saved_p["x"]), "y": float(saved_p["y"])}

	# 1. Map saved ports x/y by stable ID to world.PORTS while leaving purses, stocks, workforce, and queues untouched.
	for port_entry in state["ports"]:
		var pid: String = str(port_entry["id"])
		if not new_ports_by_id.has(pid):
			return _fail("Save refused: unknown saved harbor ID '%s'." % pid)
		var target_port_def: Dictionary = new_ports_by_id[pid]
		var px: float = float(target_port_def["x"])
		var py: float = float(target_port_def["y"])
		if not Navigation.is_water(nav, px, py):
			return _fail("Save refused: migrated harbor '%s' at (%.1f, %.1f) is not on navigable water." % [pid, px, py])
		port_entry["x"] = px
		port_entry["y"] = py

	# 2. Migrate fleet position: docked within 65 moves to matching new port; at-sea scales by CAMPAIGN_SCALE and verifies water.
	var docked_id: String = _find_docked_port_id(old_pos, legacy_ports_by_id, last_port_id)
	if docked_id.is_empty():
		docked_id = _find_docked_port_id(old_pos, saved_legacy_ports, last_port_id)

	if not docked_id.is_empty():
		var docked_new_port: Dictionary = new_ports_by_id[docked_id]
		var dpx: float = float(docked_new_port["x"])
		var dpy: float = float(docked_new_port["y"])
		if not Navigation.is_water(nav, dpx, dpy):
			return _fail("Save refused: docked harbor '%s' at (%.1f, %.1f) is not on navigable water." % [docked_id, dpx, dpy])
		state["position"] = {"x": dpx, "y": dpy}
	else:
		var sea_res: Dictionary = _resolve_at_sea_position(old_pos, scale, nav)
		if not sea_res.get("ok", false):
			return _fail(str(sea_res.get("message", "Save refused: at-sea position could not be placed on navigable water.")))
		state["position"] = sea_res["position"]

	# 3. Rebuild existing route intent: to destination stable port, or final old pathpoint scaled, via Navigation.find_path with start removed.
	if not dest_id.is_empty():
		if not new_ports_by_id.has(dest_id):
			return _fail("Save refused: unknown route destination harbor '%s'." % dest_id)
		var dest_port: Dictionary = new_ports_by_id[dest_id]
		var target_pt: Dictionary = {"x": float(dest_port["x"]), "y": float(dest_port["y"])}
		var route_path: Array = Navigation.find_path(nav, state["position"], target_pt)
		if route_path.size() < 2:
			return _fail("Save refused: could not rebuild water route from (%.1f, %.1f) to destination harbor '%s' at (%.1f, %.1f)." % [
				float(state["position"]["x"]),
				float(state["position"]["y"]),
				dest_id,
				target_pt["x"],
				target_pt["y"]
			])
		route_path.pop_front()
		state["path"] = route_path
		state["destination"] = dest_id
	elif not old_path.is_empty():
		var final_old: Dictionary = old_path[old_path.size() - 1]
		var scaled_target: Dictionary = {
			"x": float(final_old["x"]) * scale,
			"y": float(final_old["y"]) * scale
		}
		var open_route: Array = Navigation.find_path(nav, state["position"], scaled_target)
		if open_route.size() < 2:
			return _fail("Save refused: could not rebuild open-water route from (%.1f, %.1f) to scaled waypoint (%.1f, %.1f)." % [
				float(state["position"]["x"]),
				float(state["position"]["y"]),
				scaled_target["x"],
				scaled_target["y"]
			])
		open_route.pop_front()
		state["path"] = open_route
		state["destination"] = ""
	else:
		state["path"] = []
		state["destination"] = ""

	# 4. Patrols preserve progress/from/to; Campaign.restore recomputes patrol courses.
	# Ensure patrol x/y remain valid finite world coordinates for post-migration schema check.
	state["mapRevision"] = target_rev

	# 5. Post-transform validation against current world and strict Money.total conservation.
	var post_validation: Dictionary = SaveValidation.validate(state, world)
	if not post_validation.get("ok", false):
		return _fail("Save refused after migration: " + str(post_validation.get("message", "invalid migrated state")))

	var final_money: int = Money.total(state)
	if final_money != initial_money or final_money != int(state.get("coinSupply", -1)):
		return _fail("Save refused: coin conservation failed during migration (%d != %d)." % [final_money, initial_money])

	return _ok(state, "Migrated save from map revision %d to %d." % [LEGACY_MAP_REVISION, target_rev])
