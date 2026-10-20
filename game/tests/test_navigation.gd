extends SceneTree

const Navigation = preload("res://scripts/navigation.gd")

const FALLBACK_WORLD := {
	"WORLD": {"width": 2600, "height": 1800},
	"ISLANDS": [
		{"id": "isl_lantern", "points": [[210, 1180], [410, 1160], [445, 1330], [305, 1410], [190, 1300]]},
		{"id": "isl_kelp", "points": [[230, 560], [435, 530], [470, 680], [350, 745], [215, 670]]},
		{"id": "isl_sawtooth", "points": [[520, 150], [770, 135], [810, 275], [660, 330], [500, 265]]},
		{"id": "isl_verdigris", "points": [[860, 1360], [1150, 1335], [1190, 1495], [1010, 1565], [835, 1475]]},
		{"id": "isl_cinder", "points": [[1170, 480], [1420, 465], [1465, 625], [1310, 680], [1145, 600]]},
		{"id": "isl_fen", "points": [[1475, 1145], [1705, 1135], [1745, 1265], [1595, 1320], [1445, 1245]]},
		{"id": "isl_oilstone", "points": [[1790, 195], [2055, 180], [2095, 335], [1930, 390], [1760, 315]]},
		{"id": "isl_shatter", "points": [[2210, 800], [2430, 780], [2470, 980], [2275, 1085], [2185, 955]]}
	],
	"PORTS": [
		{"id": "brass_haven", "x": 495, "y": 1240},
		{"id": "kelp_reach", "x": 530, "y": 630},
		{"id": "sawtooth_mill", "x": 680, "y": 390},
		{"id": "silt_hollow", "x": 1010, "y": 1280},
		{"id": "cinder_quay", "x": 1080, "y": 620},
		{"id": "anvil_dock", "x": 1525, "y": 580},
		{"id": "reed_floats", "x": 1585, "y": 1075},
		{"id": "naphtha_bay", "x": 1920, "y": 455},
		{"id": "rust_anchorage", "x": 2125, "y": 885},
		{"id": "shatter_spire", "x": 2225, "y": 1125}
	],
	"ROUTES": [
		["brass_haven", "kelp_reach"],
		["brass_haven", "silt_hollow"],
		["kelp_reach", "sawtooth_mill"],
		["kelp_reach", "cinder_quay"],
		["kelp_reach", "silt_hollow"],
		["sawtooth_mill", "silt_hollow"],
		["sawtooth_mill", "cinder_quay"],
		["sawtooth_mill", "naphtha_bay"],
		["silt_hollow", "cinder_quay"],
		["silt_hollow", "reed_floats"],
		["cinder_quay", "reed_floats"],
		["anvil_dock", "reed_floats"],
		["anvil_dock", "naphtha_bay"],
		["anvil_dock", "rust_anchorage"],
		["reed_floats", "rust_anchorage"],
		["reed_floats", "shatter_spire"],
		["naphtha_bay", "rust_anchorage"],
		["naphtha_bay", "shatter_spire"],
		["rust_anchorage", "shatter_spire"]
	]
}


func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("test_navigation failed: " + msg)
		assert(false, msg)
		quit(1)


func _box(x: float, y: float, w: float, h: float) -> Dictionary:
	return {
		"points": [
			[x, y],
			[x + w, y],
			[x + w, y + h],
			[x, y + h]
		]
	}


func _same_pt(a: Dictionary, b: Dictionary) -> bool:
	return is_equal_approx(float(a["x"]), float(b["x"])) and is_equal_approx(float(a["y"]), float(b["y"]))


func _safe(nav: Dictionary, path: Array) -> void:
	_check(path.size() >= 2, "path must have at least 2 points")
	for i in range(1, path.size()):
		var a: Dictionary = path[i - 1]
		var b: Dictionary = path[i]
		var ax := float(a["x"])
		var ay := float(a["y"])
		var bx := float(b["x"])
		var by := float(b["y"])
		_check(is_finite(ax) and is_finite(ay) and is_finite(bx) and is_finite(by), "waypoint coordinates must be finite")
		var dist := sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))
		var steps := maxi(1, int(ceil(dist / 2.0)))
		for k in range(steps + 1):
			var t := float(k) / float(steps)
			var sx := ax + (bx - ax) * t
			var sy := ay + (by - ay) * t
			_check(Navigation.is_water(nav, sx, sy), "segment stays clear of land at (%f, %f)" % [sx, sy])


func _load_world_data() -> Dictionary:
	var candidates := [
		"res://data/world.json",
		"C:/Users/bligh/Documents/Codex/2026-10-20/how/outputs/brass-tide/game/data/world.json"
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			var raw := FileAccess.get_file_as_string(path)
			var parsed = JSON.parse_string(raw)
			if parsed is Dictionary:
				return parsed
	return FALLBACK_WORLD


func _initialize() -> void:
	# 1. Direct path in open water
	var nav := Navigation.create([], 600, 400)
	var from := {"x": 30, "y": 200}
	var to := {"x": 570, "y": 200}
	var path := Navigation.find_path(nav, from, to)
	_check(path == [from, to], "direct open-water path equals [from, to]")
	_safe(nav, path)

	# 2. Island detour
	nav = Navigation.create([_box(250, 100, 100, 200)], 600, 400)
	path = Navigation.find_path(nav, from, to)
	_check(path.size() >= 3, "island obstacle forces detour")
	_check(path[0] == from, "detour preserves start endpoint")
	_check(path[path.size() - 1] == to, "detour preserves goal endpoint")
	_safe(nav, path)

	# 3. Blocked targets & non-finite inputs
	_check(Navigation.find_path(nav, from, {"x": 300, "y": 200}).is_empty(), "target inside island returns empty path")
	_check(Navigation.find_path(nav, {"x": NAN, "y": 200}, to).is_empty(), "NaN start coordinate returns empty path")
	_check(Navigation.find_path(nav, {"x": INF, "y": 200}, to).is_empty(), "INF start coordinate returns empty path")
	_check(not Navigation.is_water(nav, NAN, 200), "NaN coordinate is not water")
	_check(not Navigation.is_water(nav, 5, 200, 10), "world border clearance respected")

	# 4. Solid barrier cannot be crossed
	nav = Navigation.create([_box(0, 190, 600, 20)], 600, 400)
	_check(Navigation.find_path(nav, {"x": 100, "y": 100}, {"x": 100, "y": 300}).is_empty(), "solid barrier cannot be crossed")

	# 5. Diagonally touching corners cannot be cut
	nav = Navigation.create([_box(80, 0, 40, 80), _box(0, 80, 80, 40)], 200, 200, 40)
	_check(Navigation.find_path(nav, {"x": 40, "y": 40}, {"x": 160, "y": 160}).is_empty(), "diagonally touching corners cannot be cut")

	# 6. Shore attachment near island boundary
	nav = Navigation.create([_box(120, 70, 100, 160)], 400, 300, 40)
	from = {"x": 108, "y": 150}
	to = {"x": 350, "y": 150}
	path = Navigation.find_path(nav, from, to)
	_check(not path.is_empty(), "shore-adjacent point attaches to navigation graph")
	_check(path[0] == from and path[path.size() - 1] == to, "shore path preserves exact endpoints")
	_safe(nav, path)

	# 7. Bounded finite graph for tiny requested cell size
	nav = Navigation.create([], 2600, 1800, 1)
	_check(nav["nodes"].size() < 5000, "graph stays bounded below 5000 nodes")
	path = Navigation.find_path(nav, {"x": 30, "y": 30}, {"x": 2500, "y": 1700})
	_check(path.size() == 2, "bounded graph finds open path")
	for pt in path:
		_check(is_finite(float(pt["x"])) and is_finite(float(pt["y"])), "bounded graph coordinates are finite")

	# 8. World integration check (8 islands, 10 ports, 19 routes, 45 port pairs)
	var world := _load_world_data()
	var islands: Array = world.get("ISLANDS", [])
	var ports: Array = world.get("PORTS", [])
	var routes: Array = world.get("ROUTES", [])
	var world_dims: Dictionary = world.get("WORLD", {"width": 2600, "height": 1800})
	_check(islands.size() == 8, "world data has 8 islands")
	_check(ports.size() == 10, "world data has 10 ports")
	_check(routes.size() == 19, "world data has 19 routes")
	var world_nav := Navigation.create(islands, world_dims.get("width", 2600), world_dims.get("height", 1800), 40)
	var port_by_id := {}
	for port in ports:
		var pid := String(port["id"])
		port_by_id[pid] = port
		_check(Navigation.is_water(world_nav, port["x"], port["y"]), "port %s is on navigable water" % pid)
	for route in routes:
		var pa: Dictionary = port_by_id[String(route[0])]
		var pb: Dictionary = port_by_id[String(route[1])]
		var p_from := {"x": pa["x"], "y": pa["y"]}
		var p_to := {"x": pb["x"], "y": pb["y"]}
		var rpath := Navigation.find_path(world_nav, p_from, p_to)
		_check(rpath.size() >= 2, "route %s -> %s is navigable" % [route[0], route[1]])
		_check(_same_pt(rpath[0], p_from) and _same_pt(rpath[rpath.size() - 1], p_to), "route %s -> %s preserves exact endpoints" % [route[0], route[1]])
		_safe(world_nav, rpath)
	for i in range(ports.size()):
		for j in range(i + 1, ports.size()):
			var pa: Dictionary = ports[i]
			var pb: Dictionary = ports[j]
			var pair_path := Navigation.find_path(world_nav, {"x": pa["x"], "y": pa["y"]}, {"x": pb["x"], "y": pb["y"]})
			_check(pair_path.size() >= 2, "port pair %s -> %s is reachable" % [pa["id"], pb["id"]])
			_safe(world_nav, pair_path)

	print("navigation: direct, island detour, blocked targets, barriers, diagonal corners, shore connections, bounded finite graph, 10 ports and 19 routes passed")
	quit(0)
