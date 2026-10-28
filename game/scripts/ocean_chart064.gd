extends RefCounted
## Main-thread painter, region/approach picker, and CoastArt050 cache adapter for v0.064.
## Consumes OceanWorld064 view payload V directly (never the outer R0 wrapper).
## Owns Open Ocean and Glasswind Keys local drawing; home campaign drawing stays on Chart.

const CoastArt050 = preload("res://scripts/coast_art050.gd")
const NauticalArt = preload("res://scripts/nautical_art.gd")
const FleetArt054 = preload("res://scripts/campaign_fleet_art054.gd")

const GOLD := Color("dfbd7d")
const FOAM := Color("95cabc")
const VALID_APPROACH_IDS: Array = ["north", "south"]
const HOME_ISLAND_IDS: Array = [
	"isl_lantern", "isl_kelp", "isl_sawtooth", "isl_verdigris",
	"isl_cinder", "isl_fen", "isl_oilstone", "isl_shatter"
]
const CACHE_LIMIT: int = 8

var _local_region_cache: Dictionary = {}
var _ocean_region_cache: Dictionary = {}
var _fallback_font: SystemFont = null


static func _is_finite_number(value) -> bool:
	if value is bool:
		return false
	if value is int or value is float:
		return is_finite(float(value))
	return false


static func _valid_point(value) -> bool:
	if not (value is Dictionary):
		return false
	return _is_finite_number(value.get("x", null)) and _is_finite_number(value.get("y", null))


static func _to_vec2(point: Dictionary) -> Vector2:
	return Vector2(float(point["x"]), float(point["y"]))


static func _valid_layer_pair(layer: String, region_id: String) -> bool:
	if layer == "home":
		return region_id == "shatter_coast"
	if layer == "local":
		return region_id == "glasswind_keys"
	if layer == "ocean":
		return region_id == "open_ocean"
	return false


static func _valid_bounds_dict(bounds) -> bool:
	if not (bounds is Dictionary):
		return false
	if not _is_finite_number(bounds.get("x", null)) or not _is_finite_number(bounds.get("y", null)):
		return false
	if not _is_finite_number(bounds.get("width", null)) or not _is_finite_number(bounds.get("height", null)):
		return false
	return float(bounds["width"]) > 0.0 and float(bounds["height"]) > 0.0


static func _valid_approach(av, expected_region_id: String = "") -> bool:
	if not (av is Dictionary):
		return false
	if not (av.get("regionId", null) is String) or not (av.get("id", null) is String) or not (av.get("name", null) is String):
		return false
	var region_id: String = str(av["regionId"])
	var approach_id: String = str(av["id"])
	if region_id.is_empty() or not (approach_id in VALID_APPROACH_IDS):
		return false
	if not expected_region_id.is_empty() and region_id != expected_region_id:
		return false
	if not _valid_point(av.get("position", null)):
		return false
	if not _is_finite_number(av.get("radius", null)) or float(av["radius"]) <= 0.0:
		return false
	return true


static func _extract_island_pairs(points) -> Array:
	if not (points is Array) or points.size() < 3:
		return []
	var out: Array = []
	for p in points:
		if p is Array and p.size() >= 2 and _is_finite_number(p[0]) and _is_finite_number(p[1]):
			out.append([float(p[0]), float(p[1])])
		elif _valid_point(p):
			out.append([float(p["x"]), float(p["y"])])
		else:
			return []
	return out


static func _extract_silhouette_pairs(ring) -> Array:
	if not (ring is Array) or ring.size() < 3:
		return []
	var out: Array = []
	for p in ring:
		if not _valid_point(p):
			return []
		out.append([float(p["x"]), float(p["y"])])
	return out


static func _valid_island_record(island, disallow_home_ids: bool) -> bool:
	if not (island is Dictionary):
		return false
	if not (island.get("id", null) is String) or not (island.get("name", null) is String):
		return false
	var island_id: String = str(island["id"])
	if island_id.is_empty() or str(island["name"]).is_empty():
		return false
	if disallow_home_ids and island_id in HOME_ISLAND_IDS:
		return false
	var pairs: Array = _extract_island_pairs(island.get("points", null))
	return pairs.size() >= 3


static func _valid_region_view(rv) -> bool:
	if not (rv is Dictionary):
		return false
	if not (rv.get("regionId", null) is String) or not (rv.get("name", null) is String) or not (rv.get("layer", null) is String):
		return false
	var region_id: String = str(rv["regionId"])
	var layer: String = str(rv["layer"])
	if not ((layer == "home" and region_id == "shatter_coast") or (layer == "local" and region_id == "glasswind_keys")):
		return false
	var silhouettes = rv.get("silhouettes", null)
	if not (silhouettes is Array) or silhouettes.is_empty():
		return false
	for ring in silhouettes:
		if _extract_silhouette_pairs(ring).size() < 3:
			return false
	var approaches = rv.get("approaches", null)
	if not (approaches is Array):
		return false
	for av in approaches:
		if not _valid_approach(av, region_id):
			return false
	return true


static func _valid_view(view, require_full_draw_fields: bool = false) -> bool:
	if not (view is Dictionary):
		return false
	if view.has("ok") and view.has("view") and not view.has("layer"):
		return false
	if not (view.get("layer", null) is String) or not (view.get("regionId", null) is String):
		return false
	var layer: String = str(view["layer"])
	var region_id: String = str(view["regionId"])
	if not _valid_layer_pair(layer, region_id):
		return false
	if not _valid_bounds_dict(view.get("bounds", null)):
		return false
	if not require_full_draw_fields:
		return true
	if not (view.get("name", null) is String) or str(view["name"]).is_empty():
		return false
	if not _valid_point(view.get("position", null)):
		return false
	if not _is_finite_number(view.get("heading", null)):
		return false
	if not (view.get("destination", null) is String):
		return false
	var path = view.get("path", null)
	if not (path is Array):
		return false
	for wp in path:
		if not _valid_point(wp):
			return false
	var boats = view.get("boats", null)
	if not (boats is Array):
		return false
	var approaches = view.get("approaches", null)
	if not (approaches is Array):
		return false
	var home_interactions = view.get("homeInteractions", null)
	if not (home_interactions is bool):
		return false
	if bool(home_interactions) != (layer == "home" and region_id == "shatter_coast"):
		return false
	var islands = view.get("islands", null)
	if not (islands is Array):
		return false
	if layer == "local":
		if islands.is_empty():
			return false
		for isl in islands:
			if not _valid_island_record(isl, true):
				return false
		for av in approaches:
			if not _valid_approach(av, region_id):
				return false
	elif layer == "home":
		if islands.is_empty():
			return false
		for isl in islands:
			if not _valid_island_record(isl, false):
				return false
		for av in approaches:
			if not _valid_approach(av, region_id):
				return false
	elif layer == "ocean":
		if not islands.is_empty():
			return false
		var regions = view.get("regions", null)
		if not (regions is Array) or regions.size() != 2:
			return false
		var seen: Dictionary = {}
		for rv in regions:
			if not _valid_region_view(rv):
				return false
			seen[str(rv["regionId"])] = true
		if not seen.has("shatter_coast") or not seen.has("glasswind_keys"):
			return false
		for av in approaches:
			if not _valid_approach(av):
				return false
	return true


func world_bounds(view: Dictionary) -> Rect2:
	if not _valid_view(view, false):
		return Rect2()
	var b: Dictionary = view["bounds"]
	return Rect2(float(b["x"]), float(b["y"]), float(b["width"]), float(b["height"]))


func content_bounds(view: Dictionary) -> Rect2:
	var fallback: Rect2 = world_bounds(view)
	if fallback.size.x <= 0.0 or fallback.size.y <= 0.0:
		return Rect2()
	var layer: String = str(view.get("layer", ""))
	var rect := Rect2()
	var first: bool = true
	if layer == "ocean":
		var regions = view.get("regions", [])
		if regions is Array:
			for rv in regions:
				if not (rv is Dictionary):
					continue
				for ring in rv.get("silhouettes", []):
					for p in _extract_silhouette_pairs(ring):
						var pt := Vector2(float(p[0]), float(p[1]))
						if first:
							rect = Rect2(pt, Vector2.ONE)
							first = false
						else:
							rect = rect.expand(pt)
				for av in rv.get("approaches", []):
					if _valid_approach(av):
						var pt := _to_vec2(av["position"])
						if first:
							rect = Rect2(pt, Vector2.ONE)
							first = false
						else:
							rect = rect.expand(pt)
	else:
		var islands = view.get("islands", [])
		if islands is Array:
			for isl in islands:
				if not (isl is Dictionary):
					continue
				for p in _extract_island_pairs(isl.get("points", [])):
					var pt := Vector2(float(p[0]), float(p[1]))
					if first:
						rect = Rect2(pt, Vector2.ONE)
						first = false
					else:
						rect = rect.expand(pt)
		var approaches = view.get("approaches", [])
		if approaches is Array:
			for av in approaches:
				if _valid_approach(av):
					var pt := _to_vec2(av["position"])
					if first:
						rect = Rect2(pt, Vector2.ONE)
						first = false
					else:
						rect = rect.expand(pt)
	return rect if not first else fallback


static func _local_cache_key(layer: String, region_id: String, bounds_rect: Rect2, islands: Array) -> String:
	var parts: Array = [
		layer,
		region_id,
		"%.1f,%.1f,%.1f,%.1f" % [bounds_rect.position.x, bounds_rect.position.y, bounds_rect.size.x, bounds_rect.size.y],
		str(islands.size())
	]
	for isl in islands:
		var pairs: Array = _extract_island_pairs(isl.get("points", []))
		var first_pt: String = "%.1f:%.1f" % [float(pairs[0][0]), float(pairs[0][1])] if not pairs.is_empty() else ""
		var last_pt: String = "%.1f:%.1f" % [float(pairs[-1][0]), float(pairs[-1][1])] if not pairs.is_empty() else ""
		parts.append("%s#%d#%s#%s" % [str(isl.get("id", "")), pairs.size(), first_pt, last_pt])
	return ":".join(parts)


func prepare_local_region(view: Dictionary) -> Dictionary:
	if not _valid_view(view, false):
		return {}
	var layer: String = str(view["layer"])
	var region_id: String = str(view["regionId"])
	if layer != "local" or region_id != "glasswind_keys":
		return {}
	var islands = view.get("islands", null)
	if not (islands is Array) or islands.is_empty():
		return {}
	for isl in islands:
		if not _valid_island_record(isl, true):
			return {}
	var bounds_rect: Rect2 = world_bounds(view)
	var cache_key: String = _local_cache_key(layer, region_id, bounds_rect, islands)
	if _local_region_cache.has(cache_key):
		return _local_region_cache[cache_key]
	var sheets: Array = []
	for i in range(islands.size()):
		var isl: Dictionary = islands[i]
		var pairs: Array = _extract_island_pairs(isl.get("points", []))
		var normalized: Dictionary = {
			"id": str(isl["id"]),
			"name": str(isl["name"]),
			"color": str(isl.get("color", "")),
			"points": pairs
		}
		var sheet: Dictionary = CoastArt050.prepare_island(normalized)
		sheet["regionId"] = region_id
		sheet["layer"] = layer
		sheets.append(sheet)
	var entry: Dictionary = {
		"cacheKey": cache_key,
		"layer": layer,
		"regionId": region_id,
		"name": str(view.get("name", region_id)),
		"bounds": bounds_rect,
		"sheets": sheets
	}
	if _local_region_cache.size() >= CACHE_LIMIT:
		_local_region_cache.erase(_local_region_cache.keys()[0])
	_local_region_cache[cache_key] = entry
	return entry


static func _ocean_cache_key(rv: Dictionary) -> String:
	var region_id: String = str(rv.get("regionId", ""))
	var layer: String = str(rv.get("layer", ""))
	var silhouettes: Array = rv.get("silhouettes", [])
	var parts: Array = ["ocean", layer, region_id, str(silhouettes.size())]
	for ring in silhouettes:
		var pairs: Array = _extract_silhouette_pairs(ring)
		var first_pt: String = "%.1f:%.1f" % [float(pairs[0][0]), float(pairs[0][1])] if not pairs.is_empty() else ""
		var last_pt: String = "%.1f:%.1f" % [float(pairs[-1][0]), float(pairs[-1][1])] if not pairs.is_empty() else ""
		parts.append("%d#%s#%s" % [pairs.size(), first_pt, last_pt])
	return ":".join(parts)


static func _compact_ocean_reef(land: PackedVector2Array) -> PackedVector2Array:
	var reef := PackedVector2Array()
	var n: int = land.size()
	if n < 3:
		return reef
	for i in range(0, n, 3):
		if reef.size() >= 24:
			break
		var a: Vector2 = land[i]
		var b: Vector2 = land[(i + 1) % n]
		var seg: Vector2 = b - a
		if seg.length_squared() < 4.0:
			continue
		var middle: Vector2 = (a + b) * 0.5
		var along: Vector2 = seg.normalized()
		var outward: Vector2 = -seg.orthogonal().normalized()
		if Geometry2D.is_point_in_polygon(middle + outward * 2.0, land):
			outward = -outward
		var at: Vector2 = middle + outward * (7.5 + float(i % 2) * 2.5)
		reef.append(at - along * 4.5)
		reef.append(at + along * 4.5)
	return reef


func _prepare_ocean_region(rv: Dictionary) -> Dictionary:
	if not _valid_region_view(rv):
		return {}
	var cache_key: String = _ocean_cache_key(rv)
	if _ocean_region_cache.has(cache_key):
		return _ocean_region_cache[cache_key]
	var region_id: String = str(rv["regionId"])
	var region_name: String = str(rv["name"])
	var region_layer: String = str(rv["layer"])
	var silhouettes: Array = rv["silhouettes"]
	var sheets: Array = []
	var polygons: Array = []
	var group_bounds := Rect2()
	var has_bounds: bool = false
	for i in range(silhouettes.size()):
		var pairs: Array = _extract_silhouette_pairs(silhouettes[i])
		if pairs.size() < 3:
			continue
		var profile_id: String = HOME_ISLAND_IDS[i % HOME_ISLAND_IDS.size()] if region_id == "shatter_coast" else "%s_ocean_%d" % [region_id, i]
		var sheet: Dictionary = CoastArt050.prepare_island({
			"id": profile_id,
			"name": region_name,
			"points": pairs
		})
		sheet["id"] = "%s_silhouette_%d" % [region_id, i]
		sheet["regionId"] = region_id
		sheet["layer"] = "ocean"
		sheet["reef"] = _compact_ocean_reef(sheet.get("land", PackedVector2Array()))
		var land_poly: PackedVector2Array = sheet.get("land", PackedVector2Array())
		var poly_bounds: Rect2 = CoastArt050._bounds(land_poly)
		sheet["bounds"] = poly_bounds.grow(14.0)
		sheets.append(sheet)
		polygons.append(land_poly)
		if not has_bounds:
			group_bounds = poly_bounds
			has_bounds = true
		else:
			group_bounds = group_bounds.merge(poly_bounds)
	if sheets.is_empty():
		return {}
	var entry: Dictionary = {
		"cacheKey": cache_key,
		"regionId": region_id,
		"name": region_name,
		"layer": region_layer,
		"sheets": sheets,
		"polygons": polygons,
		"group_bounds": group_bounds,
		"group_center": group_bounds.get_center()
	}
	if _ocean_region_cache.size() >= CACHE_LIMIT:
		_ocean_region_cache.erase(_ocean_region_cache.keys()[0])
	_ocean_region_cache[cache_key] = entry
	return entry


static func _collect_ocean_approaches(view: Dictionary) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var regions = view.get("regions", [])
	if regions is Array:
		for rv in regions:
			if not (rv is Dictionary):
				continue
			var r_id: String = str(rv.get("regionId", ""))
			var r_apps = rv.get("approaches", [])
			if not (r_apps is Array):
				continue
			for av in r_apps:
				if not _valid_approach(av, r_id):
					continue
				var key: String = "%s:%s" % [str(av["regionId"]), str(av["id"])]
				if not seen.has(key):
					seen[key] = true
					out.append(av)
	var top_apps = view.get("approaches", [])
	if top_apps is Array:
		for av in top_apps:
			if not _valid_approach(av):
				continue
			var key: String = "%s:%s" % [str(av["regionId"]), str(av["id"])]
			if not seen.has(key):
				seen[key] = true
				out.append(av)
	return out


func pick_region(view: Dictionary, world_position: Vector2) -> Dictionary:
	if not world_position.is_finite() or not _valid_view(view, false):
		return {}
	var bounds_rect: Rect2 = world_bounds(view)
	if not bounds_rect.grow(120.0).has_point(world_position):
		return {}
	var layer: String = str(view["layer"])
	var active_region_id: String = str(view["regionId"])
	if layer == "local" or layer == "home":
		var approaches = view.get("approaches", null)
		if not (approaches is Array):
			return {}
		var best_av: Dictionary = {}
		var best_dist: float = INF
		for av in approaches:
			if not _valid_approach(av, active_region_id):
				continue
			var center: Vector2 = _to_vec2(av["position"])
			var radius: float = float(av["radius"])
			var dist: float = world_position.distance_to(center)
			if dist <= radius and dist < best_dist:
				best_dist = dist
				best_av = av
		if not best_av.is_empty():
			return {
				"regionId": str(best_av["regionId"]),
				"approachId": str(best_av["id"]),
				"kind": "approach"
			}
		return {}
	if layer != "ocean":
		return {}
	var regions = view.get("regions", null)
	if not (regions is Array) or regions.size() != 2:
		return {}
	for rv in regions:
		if not _valid_region_view(rv):
			return {}
	var ocean_approaches: Array = _collect_ocean_approaches(view)
	# 1. Exact AV.radius hit takes highest priority.
	var best_exact_av: Dictionary = {}
	var best_exact_dist: float = INF
	for av in ocean_approaches:
		var center: Vector2 = _to_vec2(av["position"])
		var radius: float = float(av["radius"])
		var dist: float = world_position.distance_to(center)
		if dist <= radius and dist < best_exact_dist:
			best_exact_dist = dist
			best_exact_av = av
	if not best_exact_av.is_empty():
		return {
			"regionId": str(best_exact_av["regionId"]),
			"approachId": str(best_exact_av["id"]),
			"kind": "approach"
		}
	# 2. Direct interior hit on any RV.silhouettes polygon.
	for rv in regions:
		var reg_plan: Dictionary = _prepare_ocean_region(rv)
		if reg_plan.is_empty():
			continue
		for poly: PackedVector2Array in reg_plan.get("polygons", []):
			if Geometry2D.is_point_in_polygon(world_position, poly):
				return {
					"regionId": str(rv["regionId"]),
					"approachId": "",
					"kind": "region"
				}
	return {}


static func _empty_metrics(layer: String = "", region_id: String = "", delegate_home: bool = false) -> Dictionary:
	return {
		"ok": delegate_home,
		"delegate_home": delegate_home,
		"layer": layer,
		"regionId": region_id,
		"regions_drawn": 0,
		"islands_drawn": 0,
		"vessels_drawn": 0,
		"textured_vessels": 0,
		"approaches_drawn": 0,
		"coast_draw_calls": 0
	}


func _ensure_chart_fonts(chart) -> void:
	if _fallback_font == null:
		_fallback_font = SystemFont.new()
		_fallback_font.font_names = PackedStringArray(["Consolas", "Bahnschrift", "Segoe UI"])
	if chart.get("sans") == null:
		chart.set("sans", _fallback_font)
	if chart.get("mono") == null:
		chart.set("mono", _fallback_font)
	if chart.get("serif") == null:
		chart.set("serif", _fallback_font)


static func _scale_factor(chart) -> float:
	var raw = chart.get("scale_factor") if chart != null else null
	return maxf(0.05, float(raw)) if _is_finite_number(raw) else 0.36


static func _zoom(chart) -> float:
	var raw = chart.get("zoom") if chart != null else null
	return maxf(0.05, float(raw)) if _is_finite_number(raw) else 1.0


static func _project_rect(chart, world_rect: Rect2) -> Rect2:
	var p0: Vector2 = chart.project(world_rect.position)
	var out := Rect2(p0, Vector2.ZERO)
	for corner in [
		Vector2(world_rect.end.x, world_rect.position.y),
		world_rect.end,
		Vector2(world_rect.position.x, world_rect.end.y)
	]:
		out = out.expand(chart.project(corner))
	return out


func _draw_graticule(chart, bounds_rect: Rect2, overview: bool, major_step: int = 1000, minor_step: int = 500) -> void:
	var x0: int = int(bounds_rect.position.x)
	var y0: int = int(bounds_rect.position.y)
	var x1: int = int(bounds_rect.end.x)
	var y1: int = int(bounds_rect.end.y)
	for x in range(x0, x1 + 1, major_step):
		chart.world_line([Vector2(x, y0), Vector2(x, y1)], Color(0.6, 0.8, 0.69, 0.028))
	for y in range(y0, y1 + 1, major_step):
		chart.world_line([Vector2(x0, y), Vector2(x1, y)], Color(0.6, 0.8, 0.69, 0.028))
	if not overview and minor_step > 0:
		for x in range(x0 + minor_step, x1, major_step):
			chart.world_line([Vector2(x, y0), Vector2(x, y1)], Color(0.6, 0.8, 0.69, 0.018))
		for y in range(y0 + minor_step, y1, major_step):
			chart.world_line([Vector2(x0, y), Vector2(x1, y)], Color(0.6, 0.8, 0.69, 0.018))
	chart.world_line([
		bounds_rect.position,
		Vector2(bounds_rect.end.x, bounds_rect.position.y),
		bounds_rect.end,
		Vector2(bounds_rect.position.x, bounds_rect.end.y),
		bounds_rect.position
	], Color(0.69, 0.79, 0.65, 0.16), 1.1)


func _draw_course(chart, position: Vector2, path: Array) -> void:
	if path.is_empty():
		return
	var previous: Vector2 = position
	for step_point in path:
		if not _valid_point(step_point):
			continue
		var point: Vector2 = _to_vec2(step_point)
		chart.draw_dashed_line(chart.project(previous), chart.project(point), Color(GOLD, 0.78), 1.5, 5.0, true)
		previous = point
	var end_screen: Vector2 = chart.project(previous)
	chart.draw_arc(end_screen, 5.5, 0.0, TAU, 20, Color(GOLD, 0.82), 1.2, true)


func _draw_approach_gate(chart, av: Dictionary, destination: String, ocean_layer: bool, labels: Array) -> void:
	var region_id: String = str(av["regionId"])
	var approach_id: String = str(av["id"])
	var pos: Vector2 = _to_vec2(av["position"])
	var radius: float = float(av["radius"])
	var target_key: String = "approach:%s:%s" % [region_id, approach_id]
	var selected: bool = (destination == target_key)
	var color: Color = GOLD if selected else FOAM
	var screen_pos: Vector2 = chart.project(pos)
	var scale_val: float = _scale_factor(chart)
	var screen_radius: float = clampf(radius * scale_val, 9.0 if ocean_layer else 12.0, 42.0)
	chart.world_ring(pos, radius, Color(color, 0.75 if selected else 0.48), 1.4 if selected else 1.1)
	chart.draw_arc(screen_pos, screen_radius, -0.85, 0.85, 14, Color(color, 0.85), 1.5 if selected else 1.2, true)
	chart.draw_arc(screen_pos, screen_radius, PI - 0.85, PI + 0.85, 14, Color(color, 0.85), 1.5 if selected else 1.2, true)
	var dir_y: float = -1.0 if approach_id == "north" else 1.0
	var tip: Vector2 = screen_pos + Vector2(0.0, dir_y * (screen_radius + 5.0))
	chart.draw_colored_polygon(PackedVector2Array([
		tip,
		screen_pos + Vector2(-4.0, dir_y * (screen_radius - 2.0)),
		screen_pos + Vector2(4.0, dir_y * (screen_radius - 2.0))
	]), Color(color, 0.88))
	var gate_title: String = str(av["name"])
	if ocean_layer:
		gate_title = "%s · %s" % [str(av["name"]), "NORTH" if approach_id == "north" else "SOUTH"]
	labels.append({
		"at": screen_pos,
		"art_bounds": Rect2(screen_pos - Vector2(screen_radius, screen_radius), Vector2(screen_radius * 2.0, screen_radius * 2.0)),
		"text": gate_title,
		"subtitle": "COURSE TARGET" if selected else ("COASTAL ENTRY" if ocean_layer else "OCEAN APPROACH"),
		"priority": 100 if selected else (68 if ocean_layer else 74),
		"color": color
	})


func draw_approaches(chart, view: Dictionary, labels: Array = []) -> int:
	if chart == null or not _valid_view(view, false):
		return 0
	var layer: String = str(view["layer"])
	var region_id: String = str(view["regionId"])
	var destination: String = str(view.get("destination", ""))
	var count: int = 0
	if layer == "ocean":
		for av in _collect_ocean_approaches(view):
			_draw_approach_gate(chart, av, destination, true, labels)
			count += 1
	else:
		var approaches = view.get("approaches", [])
		if approaches is Array:
			for av in approaches:
				if not _valid_approach(av, region_id):
					continue
				_draw_approach_gate(chart, av, destination, false, labels)
				count += 1
	return count


func _draw_scale_bar(chart, viewport_size: Vector2, ocean_layer: bool) -> void:
	var scale_val: float = _scale_factor(chart)
	var world_units: float = 400.0 if ocean_layer else 500.0
	var bar_px: float = clampf(world_units * scale_val, 56.0, 160.0)
	var origin := Vector2(viewport_size.x - 230.0, viewport_size.y - 118.0)
	var bar_color := Color(0.69, 0.79, 0.65, 0.55)
	chart.draw_line(origin, origin + Vector2(bar_px, 0.0), bar_color, 1.4, true)
	chart.draw_line(origin - Vector2(0.0, 4.0), origin + Vector2(0.0, 4.0), bar_color, 1.4, true)
	chart.draw_line(origin + Vector2(bar_px * 0.5, -3.0), origin + Vector2(bar_px * 0.5, 3.0), bar_color, 1.1, true)
	chart.draw_line(origin + Vector2(bar_px, -4.0), origin + Vector2(bar_px, 4.0), bar_color, 1.4, true)
	var caption: String = "1 : 10 OCEAN SCALE" if ocean_layer else "LOCAL COASTAL SCALE"
	chart.text_at(caption, origin + Vector2(bar_px * 0.5, -8.0), 9, Color(0.74, 0.84, 0.75, 0.68), chart.get("mono"), true)


func _record_coast_profile(chart, calls: int, started_usec: int) -> void:
	if not bool(chart.get("_profile_drawing")):
		return
	var pf = chart.get("_profile_frame")
	if pf is Dictionary:
		pf["coast_draw_calls"] = int(pf.get("coast_draw_calls", 0)) + calls
		pf["coast_us"] = int(pf.get("coast_us", 0)) + (Time.get_ticks_usec() - started_usec)


func _draw_local_layer(chart, view: Dictionary) -> Dictionary:
	var region_id: String = str(view["regionId"])
	var metrics: Dictionary = _empty_metrics("local", region_id, false)
	var region_plan: Dictionary = prepare_local_region(view)
	if region_plan.is_empty():
		return metrics
	_ensure_chart_fonts(chart)
	var viewport_rect: Rect2 = chart.get_viewport_rect()
	var overview: bool = bool(chart.campaign_overview())
	var projector: Callable = chart._projector()
	var scale_val: float = _scale_factor(chart)
	var zoom_val: float = _zoom(chart)
	var bounds_rect: Rect2 = region_plan["bounds"]
	var labels: Array = []
	_draw_graticule(chart, bounds_rect, overview, 1000, 500)
	var sheets: Array = region_plan["sheets"]
	var islands: Array = view["islands"]
	for i in range(sheets.size()):
		var sheet: Dictionary = sheets[i]
		var started: int = Time.get_ticks_usec() if bool(chart.get("_profile_drawing")) else 0
		var calls: int = NauticalArt.draw(chart, projector, sheet.land, sheet, not overview, scale_val, viewport_rect)
		_record_coast_profile(chart, calls, started)
		metrics["coast_draw_calls"] = int(metrics["coast_draw_calls"]) + calls
		metrics["islands_drawn"] = int(metrics["islands_drawn"]) + 1
		var isl_name: String = str(islands[i].get("name", sheet.get("name", ""))) if i < islands.size() else str(sheet.get("name", ""))
		if not isl_name.is_empty():
			labels.append({
				"at": chart.project(sheet.label),
				"art_bounds": _project_rect(chart, sheet.bounds),
				"text": isl_name,
				"priority": 45,
				"color": Color("c4d2b0")
			})
	metrics["approaches_drawn"] = draw_approaches(chart, view, labels)
	var player_pos: Vector2 = _to_vec2(view["position"])
	_draw_course(chart, player_pos, view["path"])
	var marker: Vector2 = chart.project(player_pos)
	var player_art: Dictionary = FleetArt054.layout(
		view["boats"],
		marker,
		float(view["heading"]),
		scale_val,
		{"viewport": viewport_rect, "overview": zoom_val < 0.7}
	)
	var fleet_stats: Dictionary = FleetArt054.draw(chart, player_art, GOLD, true)
	metrics["vessels_drawn"] = int(fleet_stats.get("drawn_vessels", 0))
	metrics["textured_vessels"] = int(fleet_stats.get("textured_vessels", 0))
	if not player_art.get("vessels", []).is_empty():
		labels.append({
			"at": marker,
			"art_bounds": Rect2(player_art.bounds).grow(5.0),
			"text": "YOUR FLOTILLA",
			"priority": 105,
			"color": GOLD
		})
	chart._draw_chart_labels(labels)
	var size: Vector2 = viewport_rect.size
	var title_text: String = str(view.get("name", "GLASSWIND KEYS")).to_upper()
	chart.text_at(title_text, Vector2(size.x * 0.5, size.y - 175.0), 12, GOLD, chart.get("mono"), true)
	chart.text_at("Local coastal waters  ·  Northern and Southern sea approaches", Vector2(size.x * 0.5, size.y - 144.0), 22, Color("c7d4bd"), chart.get("serif"), true)
	chart.text_at("WASD CAMERA  ·  M TERRITORY  ·  HOME FLEET  ·  CLICK WATER OR APPROACH  ·  SCROLL ZOOM", Vector2(size.x * 0.5, size.y - 118.0), 10, Color( "93b4a8"), chart.get("mono"), true)
	_draw_scale_bar(chart, size, false)
	chart.draw_compass(Vector2(size.x - 70.0, size.y - 133.0))
	metrics["ok"] = true
	metrics["regions_drawn"] = 1
	return metrics


func _draw_ocean_layer(chart, view: Dictionary) -> Dictionary:
	var metrics: Dictionary = _empty_metrics("ocean", "open_ocean", false)
	_ensure_chart_fonts(chart)
	var viewport_rect: Rect2 = chart.get_viewport_rect()
	var overview: bool = bool(chart.campaign_overview())
	var projector: Callable = chart._projector()
	var scale_val: float = _scale_factor(chart)
	var zoom_val: float = _zoom(chart)
	var bounds_rect: Rect2 = world_bounds(view)
	var labels: Array = []
	_draw_graticule(chart, bounds_rect, overview, 800, 400)
	var regions: Array = view["regions"]
	var region_centers: Array = []
	for rv in regions:
		var reg_plan: Dictionary = _prepare_ocean_region(rv)
		if reg_plan.is_empty():
			return _empty_metrics("ocean", "open_ocean", false)
		var group_bounds: Rect2 = reg_plan["group_bounds"].grow(28.0)
		var group_center: Vector2 = reg_plan["group_center"]
		region_centers.append(group_center)
		var ring_radius: float = maxf(group_bounds.size.x, group_bounds.size.y) * 0.52
		chart.world_ring(group_center, ring_radius, Color(0.58, 0.78, 0.70, 0.14), 1.0)
		var sheets: Array = reg_plan["sheets"]
		for sheet: Dictionary in sheets:
			var started: int = Time.get_ticks_usec() if bool(chart.get("_profile_drawing")) else 0
			var calls: int = NauticalArt.draw(
				chart,
				projector,
				sheet.land,
				sheet,
				true,
				maxf(scale_val, 0.30),
				viewport_rect
			)
			_record_coast_profile(chart, calls, started)
			metrics["coast_draw_calls"] = int(metrics["coast_draw_calls"]) + calls
			metrics["islands_drawn"] = int(metrics["islands_drawn"]) + 1
		metrics["regions_drawn"] = int(metrics["regions_drawn"]) + 1
		var is_home_group: bool = str(rv["layer"]) == "home"
		var group_screen: Vector2 = chart.project(group_center)
		var group_screen_bounds: Rect2 = _project_rect(chart, reg_plan["group_bounds"])
		labels.append({
			"at": group_screen,
			"art_bounds": group_screen_bounds,
			"text": str(rv["name"]).to_upper(),
			"subtitle": "HOME WATERS" if is_home_group else "REMOTE KEYS",
			"priority": 92 if is_home_group else 88,
			"color": GOLD if is_home_group else Color("d7e1cc")
		})
	if region_centers.size() == 2:
		chart.draw_dashed_line(
			chart.project(region_centers[0]),
			chart.project(region_centers[1]),
			Color(0.64, 0.80, 0.65, 0.11),
			1.0,
			6.0,
			true
		)
	metrics["approaches_drawn"] = draw_approaches(chart, view, labels)
	var player_pos: Vector2 = _to_vec2(view["position"])
	_draw_course(chart, player_pos, view["path"])
	var marker: Vector2 = chart.project(player_pos)
	var player_art: Dictionary = FleetArt054.layout(
		view["boats"],
		marker,
		float(view["heading"]),
		scale_val,
		{"viewport": viewport_rect, "overview": zoom_val < 0.7}
	)
	var fleet_stats: Dictionary = FleetArt054.draw(chart, player_art, GOLD, true)
	metrics["vessels_drawn"] = int(fleet_stats.get("drawn_vessels", 0))
	metrics["textured_vessels"] = int(fleet_stats.get("textured_vessels", 0))
	if not player_art.get("vessels", []).is_empty():
		labels.append({
			"at": marker,
			"art_bounds": Rect2(player_art.bounds).grow(5.0),
			"text": "YOUR FLOTILLA",
			"priority": 105,
			"color": GOLD
		})
	chart._draw_chart_labels(labels)
	var size: Vector2 = viewport_rect.size
	chart.text_at(str(view.get("name", "OPEN OCEAN")).to_upper(), Vector2(size.x * 0.5, size.y - 175.0), 12, GOLD, chart.get("mono"), true)
	chart.text_at("Shatter Coast  ·  Glasswind Keys", Vector2(size.x * 0.5, size.y - 144.0), 24, Color("c7d4bd"), chart.get("serif"), true)
	chart.text_at("WASD CAMERA  ·  M TERRITORY  ·  HOME FLEET  ·  CLICK APPROACH OR WATER  ·  SCROLL ZOOM", Vector2(size.x * 0.5, size.y - 118.0), 10, Color("93b4a8"), chart.get("mono"), true)
	_draw_scale_bar(chart, size, true)
	chart.draw_compass(Vector2(size.x - 70.0, size.y - 133.0))
	metrics["ok"] = true
	return metrics


func draw(chart, view: Dictionary) -> Dictionary:
	if chart == null or not _valid_view(view, true):
		return _empty_metrics()
	var layer: String = str(view["layer"])
	if layer == "home":
		return _empty_metrics("home", "shatter_coast", true)
	if layer == "local":
		return _draw_local_layer(chart, view)
	if layer == "ocean":
		return _draw_ocean_layer(chart, view)
	return _empty_metrics()
