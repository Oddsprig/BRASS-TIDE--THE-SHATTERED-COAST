extends RefCounted
## Pure player spatial operations. Campaign alone owns boats, accounts and time.
## Context is runtime geometry; the supplied home navigation is shared read-only.
const Navigation = preload("res://scripts/navigation.gd")
const CoastShape121 = preload("res://scripts/coast_shape121.gd")
const HOME: String = "shatter_coast"
const REMOTE: String = "glasswind_keys"
const OCEAN: String = "open_ocean"
const REGION_ORDER: Array = [HOME, REMOTE]
const HOME_PORTS: Array = ["brass_haven", "kelp_reach", "sawtooth_mill", "silt_hollow", "cinder_quay", "anvil_dock", "reed_floats", "naphtha_bay", "rust_anchorage", "shatter_spire"]
const HOME_WIDTH: float = 10400.0
const HOME_HEIGHT: float = 7200.0
const COAST_SCALE: float = 4.0
const APPROACH_RADIUS: float = 80.0
const POINT_EPSILON: float = 0.000001
const REMOTE_PORT068: String = "westglass_anchorage"

static func remote_port068() -> Dictionary:
	# Geometry only. Campaign installation/knowledge controls whether this harbor exists.
	return {"id":REMOTE_PORT068,"name":"Westglass Anchorage","regionId":REMOTE,
		"islandId":"glasswind_west","faction":"reed","industry":"timber","specialty":"logs",
		"x":756.0,"y":732.0}


static func create(home: Dictionary, atlas: Dictionary, home_nav: Dictionary, harbors: Array = []) -> Dictionary:
	var error: String = _definitions_error(home, atlas, home_nav)
	if not error.is_empty():
		return _failure("definitions", error, "context")
	var regions: Dictionary = {}
	for definition in atlas.regions:
		regions[definition.id] = definition.duplicate(true)
	var coast: Dictionary = regions[HOME]
	coast.width = float(home.WORLD.width)
	coast.height = float(home.WORLD.height)
	coast.islands = home.ISLANDS.duplicate(true)
	var ports: Dictionary = {}
	for port in home.PORTS:
		ports[port.id] = _point(port)
	var geometry: Dictionary = {HOME: home_nav}
	for region_id in regions:
		if region_id != HOME:
			var local_region: Dictionary = regions[region_id]
			# v0.121 runtime-only shaping of this duplicated region. The
			# saved sector/atlas bytes are never mutated: validation above
			# ran on them, shaping re-derives from them every launch, and
			# shaped runtime copies carry a coast121 marker against repeats.
			local_region.islands = CoastShape121.natural_islands(local_region.islands)
			geometry[region_id] = Navigation.geometry(local_region.islands, local_region.width, local_region.height)
	var remote: Dictionary = regions[REMOTE]
	# Keep Glasswind pinned: its existing merchant stays physical while the player
	# visits generated charts. Only ONE additional generated grid may be active.
	var remote_nav: Dictionary = Navigation.create(remote.islands, remote.width, remote.height, Navigation.DEFAULT_CELL * COAST_SCALE)
	var context: Dictionary = {"schema": 1, "ocean": atlas.ocean.duplicate(true), "regions": regions,
		"atlasSchema": int(atlas.schema), "ports": ports, "homeNav": home_nav, "remoteNav": remote_nav,
		"regionGeometry": geometry, "activeRegionId": "", "activeNav": {}, "harbors": {}, "regionViews": []}
	for harbor in harbors:
		if not harbor is Dictionary or not _plain(harbor) or not _text(harbor.get("id")) or not _text(harbor.get("regionId")):
			return _failure("definitions", "Harbor berths require canonical string identities.", "context")
		if context.harbors.has(harbor.id) or ports.has(harbor.id) or harbor.id == REMOTE_PORT068 or not regions.has(harbor.regionId) or harbor.regionId in REGION_ORDER:
			return _failure("definitions", "Repeated harbor or unknown generated harbor region.", "context")
		if not _number(harbor.get("x")) or not _number(harbor.get("y")) or not _text(harbor.get("islandId")):
			return _failure("definitions", "Harbor berths require finite coordinates and an island.", "context")
		var harbor_region: Dictionary = regions[harbor.regionId]
		if not harbor_region.islands.any(func(island): return island.id == harbor.islandId) or not Navigation.is_water(geometry[harbor.regionId], harbor.x, harbor.y):
			return _failure("definitions", "Harbor berth is not clear water beside a canonical island.", "context")
		# No faction, service, stock, purse or knowledge enters the spatial context.
		context.harbors[harbor.id] = {"id": harbor.id, "regionId": harbor.regionId, "islandId": harbor.islandId, "x": float(harbor.x), "y": float(harbor.y)}
	for definition in atlas.regions:
		var region_id: String = definition.id
		var region: Dictionary = regions[region_id]
		for approach in region.approaches:
			if not _approach_safe(context, region, approach, Navigation.DEFAULT_CLEARANCE):
				return _failure("definitions", "A coastal approach or its paired ocean endpoint is not clear water.", "context")
		context.regionViews.append(_region_view(context, region))
	return _success("context", context, "World geometry ready.")


static func prepare(saved: Dictionary, context: Dictionary, clearance: float) -> Dictionary:
	# Copy only spatial fields before validation; no account is copied or published.
	# Caller must finish legacy CoastMigration first. A revision-1 save is refused.
	# Actor, intent and sighting reads must never replace the player's active grid.
	return _read_location(saved, context, clearance, true)


static func prepare_player(saved: Dictionary, context: Dictionary, clearance: float) -> Dictionary:
	# Actual player restore only, before publishing this runtime context to workers.
	var result: Dictionary = prepare(saved, context, clearance)
	if result.ok:
		_activate(context, result.location.world064, true)
	return result


static func plot(context: Dictionary, location: Dictionary, target: Dictionary, destination: String, clearance: float) -> Dictionary:
	var prepared: Dictionary = _read_location(location, context, clearance, false)
	if not prepared.ok:
		return prepared
	var loc: Dictionary = prepared.location
	if not _is_point(target):
		return _failure("target", "A course needs finite x/y coordinates.")
	var endpoint: Dictionary = _point(target)
	var intent: Dictionary = _destination(context, loc.world064, destination)
	if not intent.ok:
		return _failure("target", intent.message)
	if intent.has("approach") and not _same_point(endpoint, intent.approach.position):
		return _failure("target", "An approach course must target its matching center.")
	if loc.world064.layer == "local" and intent.has("port") and not _same_point(endpoint,intent.port):
		return _failure("target", "A remote harbor course must target its actual water berth.")
	var actual: float = Navigation.hull_clearance(clearance)
	var ocean: bool = loc.world064.layer == "ocean"
	if not ocean and loc.world064.layer == "home":
		var harbor: Dictionary = intent.get("port", {})
		if not harbor.is_empty() and not _same_point(endpoint, harbor):
			return _failure("target", "A harbor course must target the original harbor coordinate.")
		if harbor.is_empty():
			for port_id in HOME_PORTS:
				if _same_point(endpoint, context.ports[port_id]):
					harbor = context.ports[port_id]
					break
		if not harbor.is_empty():
			endpoint = Navigation.harbor_approach(context.homeNav, harbor, actual)
			if endpoint.is_empty():
				return _failure("target", "No safe harbor approach for this fleet clearance.")
	if not _water(context, loc.world064, endpoint, actual):
		return _failure("target", "The course endpoint is outside safe navigable water.")
	var path: Array = []
	if not _same_point(loc.position, endpoint):
		if ocean:
			path.append(endpoint)
		else:
			var navigation: Dictionary = _nav(context, loc.world064)
			if navigation.is_empty():
				return _failure("definitions", "Prepare this local chart before publishing its runtime context.")
			path = Navigation.find_path(navigation, loc.position, endpoint, actual)
			if path.size() < 2:
				return _failure("route", "No safe water route for this fleet clearance.")
			path.pop_front()
	loc.path = path
	loc.destination = destination
	return _success("location", loc, "Course plotted.")


static func advance(context: Dictionary, location: Dictionary, dt: float, speed: float, clearance: float) -> Dictionary:
	if not is_finite(dt) or not is_finite(speed) or dt < 0.0 or speed < 0.0 or not is_finite(dt * speed):
		return _step_failure(_failure("step", "Movement needs finite nonnegative time and speed."))
	var prepared: Dictionary = _read_location(location, context, clearance, false)
	if not prepared.ok:
		return _step_failure(prepared)
	var loc: Dictionary = prepared.location
	var was_routed: bool = not loc.path.is_empty()
	var unit_scale: float = float(context.ocean.localUnitsPerUnit) if loc.world064.layer == "ocean" else 1.0
	var remaining: float = dt * speed / unit_scale
	var traversed: float = 0.0
	var actual: float = Navigation.hull_clearance(clearance)
	while remaining > 0.0 and not loc.path.is_empty():
		var target: Dictionary = loc.path[0]
		var dx: float = float(target.x) - float(loc.position.x)
		var dy: float = float(target.y) - float(loc.position.y)
		var length: float = sqrt(dx * dx + dy * dy)
		if length == 0.0:
			loc.path.pop_front()
			continue
		var moved: float = minf(remaining, length)
		var endpoint: Dictionary = target.duplicate() if moved == length else {
			"x": float(loc.position.x) + dx * moved / length, "y": float(loc.position.y) + dy * moved / length}
		# Check the consumed segment at the current fleet clearance. Full remaining
		# routes are checked by prepare; no resampling of the whole route each frame.
		if not _segment_safe(context, loc.world064, loc.position, endpoint, actual):
			return _step_failure(_failure("route", "The movement segment is unsafe for this fleet clearance."))
		loc.heading = atan2(dy, dx)
		loc.position = endpoint
		traversed += moved
		remaining -= moved
		if moved == length:
			loc.path.pop_front()
	var result: Dictionary = _success("location", loc, "Movement advanced.")
	result.distance = traversed * unit_scale
	result.moving = traversed > 0.0
	result.arrived = was_routed and loc.path.is_empty()
	return result


static func transition(context: Dictionary, location: Dictionary, region_id: String, approach_id: String, clearance: float, blocked_reason: String) -> Dictionary:
	# Actor transfers validate/copy location only; they never own the player's grid.
	if not blocked_reason.is_empty():
		return _failure("blocked", blocked_reason)
	var prepared: Dictionary = _read_location(location, context, clearance, false)
	if not prepared.ok:
		return prepared
	var loc: Dictionary = prepared.location
	if not loc.path.is_empty():
		return _failure("approach", "Finish or stop the current course before changing charts.")
	if not context.regions.has(region_id):
		return _failure("approach", "Unknown coastal region.")
	var ocean: bool = loc.world064.layer == "ocean"
	if not ocean and loc.world064.regionId != region_id:
		return _failure("approach", "Depart through an approach belonging to the current region.")
	var region: Dictionary = context.regions[region_id]
	var approach: Dictionary = _approach(region, approach_id)
	if approach.is_empty():
		return _failure("approach", "Unknown coastal approach.")
	var center: Dictionary = _project(context, region, approach.position) if ocean else _point(approach.position)
	var radius: float = float(approach.radius) / float(context.ocean.localUnitsPerUnit) if ocean else float(approach.radius)
	if _distance(loc.position, center) > radius:
		return _failure("approach", "Sail within the matching coastal approach before changing charts.")
	var actual: float = Navigation.hull_clearance(clearance)
	if not _approach_safe(context, region, approach, actual) or not _water(context, loc.world064, loc.position, actual):
		return _failure("approach", "The paired approach is unsafe for this fleet clearance.")
	var identity: Dictionary = {"schema": 1, "layer": region.layer if ocean else "ocean", "regionId": region_id if ocean else OCEAN}
	var endpoint: Dictionary = _unproject(context, region, loc.position) if ocean else _project(context, region, loc.position)
	if not _water(context, identity, endpoint, actual):
		return _failure("approach", "The exact transfer endpoint is not safe navigable water.")
	loc.world064 = identity
	loc.position = endpoint
	loc.path = []
	loc.destination = ""
	return _success("location", loc, "Coastal chart changed.")


static func transition_player(context: Dictionary, location: Dictionary, region_id: String, approach_id: String, clearance: float, blocked_reason: String) -> Dictionary:
	# Actual player transfer only, before publishing this runtime context to workers.
	var result: Dictionary = transition(context, location, region_id, approach_id, clearance, blocked_reason)
	if result.ok:
		_activate(context, result.location.world064, true)
	return result


static func view(context: Dictionary, location: Dictionary, active_boats: Array) -> Dictionary:
	var prepared: Dictionary = _read_location(location, context, Navigation.DEFAULT_CLEARANCE, false)
	if not prepared.ok:
		return _failure(prepared.code, prepared.message, "view")
	var loc: Dictionary = prepared.location
	var seen: Dictionary = {}
	for boat in active_boats:
		if not boat is Dictionary or not _plain(boat) or not _text(boat.get("uid")):
			return _failure("location", "Chart boats must be plain data with their existing UIDs.", "view")
		if seen.has(boat.uid):
			return _failure("location", "Chart boat UIDs must be unique.", "view")
		seen[boat.uid] = true
	var ocean: bool = loc.world064.layer == "ocean"
	var region: Dictionary = context.ocean if ocean else context.regions[loc.world064.regionId]
	var approaches: Array = []
	if ocean:
		for projected_region in context.regionViews:
			approaches.append_array(projected_region.approaches.duplicate(true))
	else:
		for approach in region.approaches:
			approaches.append(_approach_view(region.id, approach, approach.position, float(approach.radius)))
	var chart: Dictionary = {"layer": loc.world064.layer, "regionId": loc.world064.regionId, "name": region.name,
		"bounds": {"x": 0.0, "y": 0.0, "width": float(region.width), "height": float(region.height)},
		"position": loc.position, "heading": loc.heading, "path": loc.path, "destination": loc.destination,
		"islands": [] if ocean else region.islands.duplicate(true), "regions": context.regionViews.duplicate(true),
		"approaches": approaches, "boats": active_boats.duplicate(true), "homeInteractions": loc.world064.layer == "home"}
	return _success("view", chart, "Chart view ready.")


static func _number(value) -> bool:
	return (value is int or value is float) and not value is bool and is_finite(float(value))


static func _text(value) -> bool:
	return value is String and not value.is_empty()


static func _keys(value, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true


static func _is_point(value) -> bool:
	return _keys(value, ["x", "y"]) and _number(value.x) and _number(value.y)


static func _point(value: Dictionary) -> Dictionary:
	return {"x": float(value.x), "y": float(value.y)}


static func _same_point(a: Dictionary, b: Dictionary) -> bool:
	return float(a.x) == float(b.x) and float(a.y) == float(b.y)


static func _distance(a: Dictionary, b: Dictionary) -> float:
	var dx: float = float(b.x) - float(a.x)
	var dy: float = float(b.y) - float(a.y)
	return sqrt(dx * dx + dy * dy)


static func _failure(code: String, message: String, field: String = "location") -> Dictionary:
	return {"ok": false, "code": code, "message": message, field: {}}


static func _success(field: String, value: Dictionary, message: String) -> Dictionary:
	return {"ok": true, "code": "ok", "message": message, field: value}


static func _step_failure(result: Dictionary) -> Dictionary:
	result.distance = 0.0
	result.moving = false
	result.arrived = false
	return result


static func _inside_bounds(point: Dictionary, width: float, height: float, margin: float = 0.0) -> bool:
	return float(point.x) >= margin and float(point.y) >= margin and float(point.x) <= width - margin and float(point.y) <= height - margin


static func _islands_valid(value, width: float, height: float, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	var ids: Dictionary = {}
	for island in value:
		if not _keys(island, ["id", "name", "color", "points"]) or not _text(island.id) or not _text(island.name) or not _text(island.color):
			return false
		if ids.has(island.id) or not island.points is Array or island.points.size() < 3:
			return false
		ids[island.id] = true
		var points: Array = island.points
		for pair in points:
			if not pair is Array or pair.size() != 2 or not _number(pair[0]) or not _number(pair[1]):
				return false
			if not _inside_bounds({"x": pair[0], "y": pair[1]}, width, height):
				return false
		var twice_area: float = 0.0
		for i in range(points.size()):
			var a: Array = points[i]
			var b: Array = points[(i + 1) % points.size()]
			if a == b:
				return false
			twice_area += float(a[0]) * float(b[1]) - float(b[0]) * float(a[1])
		if not is_finite(twice_area) or absf(twice_area) < POINT_EPSILON:
			return false
	return true


static func _nav_valid(nav: Dictionary, width: float, height: float) -> bool:
	if not _number(nav.get("width")) or not _number(nav.get("height")) or nav.width != width or nav.height != height:
		return false
	if not _number(nav.get("cell")) or nav.cell <= 0.0 or not _number(nav.get("cols")) or not _number(nav.get("rows")):
		return false
	if nav.cols < 1 or nav.rows < 1 or nav.cols != int(nav.cols) or nav.rows != int(nav.rows):
		return false
	if not nav.get("nodes") is Array or not nav.get("edges") is Array or not nav.get("islands") is Array:
		return false
	return nav.nodes.size() == int(nav.cols) * int(nav.rows) and nav.edges.size() == nav.nodes.size() and nav.nodes.size() < Navigation.MAX_NODES


static func _definitions_error(home: Dictionary, atlas: Dictionary, home_nav: Dictionary) -> String:
	if not home.get("WORLD") is Dictionary or not _number(home.WORLD.get("width")) or not _number(home.WORLD.get("height")):
		return "Missing finite home world bounds."
	if home.WORLD.width != HOME_WIDTH or home.WORLD.height != HOME_HEIGHT or not _number(home.get("CAMPAIGN_SCALE")) or home.CAMPAIGN_SCALE != COAST_SCALE:
		return "This catalog requires the unchanged Shatter Coast dimensions and campaign scale."
	if not _islands_valid(home.get("ISLANDS"), HOME_WIDTH, HOME_HEIGHT, 8) or not _nav_valid(home_nav, HOME_WIDTH, HOME_HEIGHT):
		return "Missing or invalid home island geometry or shared navigation."
	if home_nav.islands.size() != home.ISLANDS.size():
		return "Shared home navigation does not match home islands."
	for i in range(home.ISLANDS.size()):
		if not home_nav.islands[i] is Dictionary or home_nav.islands[i].get("points") != home.ISLANDS[i].points:
			return "Shared home navigation does not match home island points."
	if not home.get("PORTS") is Array or home.PORTS.size() != HOME_PORTS.size():
		return "The original home ports are required."
	var seen_ports: Dictionary = {}
	for port in home.PORTS:
		if not port is Dictionary or not _text(port.get("id")) or port.id not in HOME_PORTS or seen_ports.has(port.id):
			return "Unknown or repeated home port."
		if not _number(port.get("x")) or not _number(port.get("y")) or not Navigation.is_water(home_nav, port.x, port.y):
			return "A home port has invalid navigable coordinates."
		seen_ports[port.id] = true
	return atlas_error(home, atlas)


static func region_order069() -> Array:
	var order: Array = REGION_ORDER.duplicate()
	for band in [{"id": "settled", "count": 7}, {"id": "frontier", "count": 11}, {"id": "remote", "count": 28}]:
		for index in range(1, int(band.count) + 1):
			order.append("%s_%02d" % [band.id, index])
	return order


static func local_id_valid(value) -> bool:
	if not _text(value) or value.length() > 64 or value in [HOME, OCEAN]:
		return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return false
	return true


static func atlas_error(home: Dictionary, atlas: Dictionary) -> String:
	# Geometry-only validation is also used before publishing canonical saved sectors.
	# This function never allocates a grid or reads campaign ownership/accounts.
	if not _keys(atlas, ["schema", "ocean", "regions"]) or not _number(atlas.schema) or (atlas.schema != 1 and atlas.schema != 2) or not _plain(atlas):
		return "Unsupported world catalog schema."
	var generated: bool = atlas.schema == 2
	var ocean = atlas.ocean
	if not _keys(ocean, ["id", "name", "width", "height", "localUnitsPerUnit"]):
		return "Missing ocean definitions."
	if ocean.id != OCEAN or ocean.name != "Open Ocean" or not _number(ocean.width) or not _number(ocean.height) or not _number(ocean.localUnitsPerUnit):
		return "Invalid ocean identity or numeric definitions."
	if ocean.width != (12800.0 if generated else 4800.0) or ocean.height != (8400.0 if generated else 2800.0) or ocean.localUnitsPerUnit != 10.0:
		return "Unexpected ocean dimensions or distance scale."
	var order: Array = region_order069() if generated else REGION_ORDER
	if not atlas.regions is Array or atlas.regions.size() != order.size():
		return "The catalog requires exactly two legacy regions or 48 canonical sector regions."
	if not _islands_valid(home.get("ISLANDS"), HOME_WIDTH, HOME_HEIGHT, 8):
		return "The unchanged home island geometry is required."
	var seen_regions: Dictionary = {}
	var projected_bounds: Array = []
	for region_index in range(atlas.regions.size()):
		var region = atlas.regions[region_index]
		if not region is Dictionary or not _text(region.get("id")) or region.id != order[region_index] or seen_regions.has(region.id):
			return "Unknown or repeated region."
		seen_regions[region.id] = true
		var home_region: bool = region.id == HOME
		var fields: Array = ["id", "name", "layer", "oceanOrigin", "approaches", "source"] if home_region else ["id", "name", "layer", "oceanOrigin", "approaches", "width", "height", "islands"]
		if not _keys(region, fields) or not _is_point(region.oceanOrigin):
			return "Invalid regional definition fields or projection origin."
		if home_region:
			if region.layer != "home" or region.name != "Shatter Coast" or region.source != "home" or region.oceanOrigin != {"x": 700.0, "y": 1100.0}:
				return "Invalid Shatter Coast regional identity."
		else:
			if region.layer != "local" or not local_id_valid(region.id) or not _text(region.name):
				return "Invalid local regional identity."
			if region.id == REMOTE and (region.name != "Glasswind Keys" or region.oceanOrigin != {"x": 3300.0, "y": 600.0}):
				return "Invalid Glasswind Keys regional identity."
			if not _number(region.width) or not _number(region.height) or region.width != 4200.0 or region.height != 3000.0:
				return "Local charts require their finite canonical bounds."
			if not region.islands is Array or region.islands.size() < 2 or region.islands.size() > 4 or (region.id == REMOTE and region.islands.size() != 3):
				return "A local chart needs its bounded island set."
			if not _islands_valid(region.islands, 4200.0, 3000.0, region.islands.size()):
				return "Invalid local island geometry."
		var width: float = HOME_WIDTH if home_region else float(region.width)
		var height: float = HOME_HEIGHT if home_region else float(region.height)
		var rectangle: Dictionary = {"x": float(region.oceanOrigin.x), "y": float(region.oceanOrigin.y), "width": width / 10.0, "height": height / 10.0}
		if rectangle.x < 0.0 or rectangle.y < 0.0 or rectangle.x + rectangle.width > ocean.width or rectangle.y + rectangle.height > ocean.height:
			return "A projected local chart lies outside the ocean."
		for other in projected_bounds:
			if maxf(rectangle.x, other.x) < minf(rectangle.x + rectangle.width, other.x + other.width) and maxf(rectangle.y, other.y) < minf(rectangle.y + rectangle.height, other.y + other.height):
				return "Projected local charts must not overlap."
		projected_bounds.append(rectangle)
		var physical: Dictionary = Navigation.geometry(home.ISLANDS if home_region else region.islands, width, height)
		if not region.approaches is Array or region.approaches.size() != 2:
			return "Each region needs north and south approaches."
		var seen_approaches: Dictionary = {}
		for approach in region.approaches:
			if not _keys(approach, ["id", "name", "position", "radius"]) or approach.id not in ["north", "south"] or seen_approaches.has(approach.id):
				return "Unknown or repeated coastal approach."
			if not _text(approach.name) or not _is_point(approach.position) or not _number(approach.radius) or approach.radius != APPROACH_RADIUS:
				return "Invalid coastal approach geometry."
			var expected: Dictionary = {"x": 5200.0, "y": 300.0 if approach.id == "north" else 6900.0} if home_region else {"x": 2100.0, "y": 200.0 if approach.id == "north" else 2800.0}
			if approach.position != expected:
				return "Unexpected coastal approach position."
			var disk: float = float(approach.radius) + Navigation.DEFAULT_CLEARANCE
			if not Navigation.is_water(physical, approach.position.x, approach.position.y, disk):
				return "A coastal approach disk is not safe water."
			seen_approaches[approach.id] = true
	return ""


static func _context_valid(context: Dictionary) -> bool:
	if not _number(context.get("schema")) or context.schema != 1 or not context.get("ocean") is Dictionary or not context.get("regions") is Dictionary:
		return false
	for key in ["width", "height", "localUnitsPerUnit"]:
		if not _number(context.ocean.get(key)) or float(context.ocean[key]) <= 0.0:
			return false
	if not _number(context.get("atlasSchema")) or (context.atlasSchema != 1 and context.atlasSchema != 2) or not context.get("ports") is Dictionary or not context.get("regionViews") is Array:
		return false
	var count: int = 48 if context.atlasSchema == 2 else 2
	if context.regions.size() != count or context.regionViews.size() != count or not context.get("regionGeometry") is Dictionary or context.regionGeometry.size() != count:
		return false
	for region_id in context.regions:
		if not context.regions.get(region_id) is Dictionary:
			return false
		var region: Dictionary = context.regions[region_id]
		if not _number(region.get("width")) or not _number(region.get("height")) or region.width <= 0.0 or region.height <= 0.0:
			return false
		if not region.get("islands") is Array or not region.get("approaches") is Array or not _is_point(region.get("oceanOrigin")):
			return false
		if not context.regionGeometry.get(region_id) is Dictionary:
			return false
	if not context.get("homeNav") is Dictionary or not context.get("remoteNav") is Dictionary:
		return false
	if not context.regions.has(HOME) or not context.regions.has(REMOTE) or not context.get("harbors") is Dictionary or not context.get("activeNav") is Dictionary or not context.get("activeRegionId") is String:
		return false
	if context.activeRegionId.is_empty():
		if not context.activeNav.is_empty():return false
	elif context.activeRegionId in REGION_ORDER or not context.regions.has(context.activeRegionId) or not _nav_valid(context.activeNav, 4200.0, 3000.0):
		return false
	return _nav_valid(context.homeNav, HOME_WIDTH, HOME_HEIGHT) and _nav_valid(context.remoteNav, 4200.0, 3000.0)


static func _read_location(saved: Dictionary, context: Dictionary, clearance: float, check_route: bool) -> Dictionary:
	var raw: Dictionary = {}
	for key in ["world064", "position", "heading", "path", "destination"]:
		var value = saved.get(key)
		raw[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	if not _context_valid(context):
		return _failure("definitions", "Missing or invalid world context.")
	if not is_finite(clearance) or clearance < 0.0:
		return _failure("location", "Fleet clearance must be finite and nonnegative.")
	if not saved.has("world064"):
		if not _number(saved.get("mapRevision")) or saved.mapRevision != 2:
			return _failure("location", "Migrate the legacy home coast before preparing a world location.")
		raw.world064 = {"schema": 1, "layer": "home", "regionId": HOME}
	var identity = raw.world064
	if not _keys(identity, ["schema", "layer", "regionId"]) or not _number(identity.schema) or identity.schema != 1:
		return _failure("location", "Invalid world064 spatial identity.")
	if not identity.layer is String or not identity.regionId is String:
		return _failure("location", "World layer and region must be strings.")
	if not ((identity.layer == "home" and identity.regionId == HOME) or (identity.layer == "local" and local_id_valid(identity.regionId) and context.regions.has(identity.regionId)) or (identity.layer == "ocean" and identity.regionId == OCEAN)):
		return _failure("location", "World layer and region do not form a supported pair.")
	if not _is_point(raw.position) or not _number(raw.heading) or not raw.path is Array or not raw.destination is String:
		return _failure("location", "Missing or invalid position, heading, path or destination.")
	var loc: Dictionary = {"world064": {"schema": 1, "layer": identity.layer, "regionId": identity.regionId},
		"position": _point(raw.position), "heading": float(raw.heading), "path": [], "destination": raw.destination}
	var actual: float = Navigation.hull_clearance(clearance)
	# Home idle/docked positions keep existing ten-unit semantics. Sailing and
	# every transfer still require actual clearance, with no relocation.
	var position_clearance: float = Navigation.DEFAULT_CLEARANCE if identity.layer == "home" else actual
	if not _water(context, identity, loc.position, position_clearance):
		return _failure("location", "The active player position is outside safe navigable water.")
	for point in raw.path:
		if not _is_point(point):
			return _failure("route", "Route waypoints need finite x/y coordinates.")
		var waypoint: Dictionary = _point(point)
		if loc.path.is_empty() and _same_point(waypoint, loc.position):
			return _failure("route", "Route waypoints must exclude the current starting point.")
		if not _bounded(context, identity, waypoint, actual):
			return _failure("route", "A route waypoint is outside this chart's fleet bounds.")
		loc.path.append(waypoint)
	var intent: Dictionary = _destination(context, identity, loc.destination)
	if not intent.ok:
		return _failure("location", intent.message)
	var route_end: Dictionary = loc.position if loc.path.is_empty() else loc.path[-1]
	if intent.has("approach") and not _same_point(route_end, intent.approach.position):
		return _failure("route", "The approach destination does not match the route endpoint.")
	if intent.has("port") and _distance(route_end, intent.port) >= 65.0:
		return _failure("route", "The harbor destination does not match the route endpoint.")
	if check_route and not loc.path.is_empty():
		if identity.layer == "ocean":
			if not _water(context, identity, loc.position, actual):
				return _failure("route", "The ocean route start is outside fleet bounds.")
		elif not Navigation.path_clear(_geometry(context, identity), loc.position, loc.path, actual):
			return _failure("route", "The saved route is unsafe for this fleet clearance.")
	return _success("location", loc, "Location prepared.")


static func _nav(context: Dictionary, identity: Dictionary) -> Dictionary:
	if identity.layer == "home":return context.homeNav
	if identity.regionId == REMOTE:return context.remoteNav
	return context.activeNav if context.activeRegionId == identity.regionId else {}


static func _geometry(context: Dictionary, identity: Dictionary) -> Dictionary:
	return context.regionGeometry[identity.regionId]


static func _activate(context: Dictionary, identity: Dictionary, evict: bool = false) -> void:
	# Call only from explicit player restore/transition before worker publication.
	if identity.layer == "local" and identity.regionId != REMOTE:
		if context.activeRegionId != identity.regionId:
			var region: Dictionary = context.regions[identity.regionId]
			var navigation: Dictionary = Navigation.create(region.islands, region.width, region.height, Navigation.DEFAULT_CELL * COAST_SCALE)
			context.activeNav = navigation
			context.activeRegionId = identity.regionId
	elif evict:
		context.activeNav = {}
		context.activeRegionId = ""


static func _bounded(context: Dictionary, identity: Dictionary, point: Dictionary, clearance: float) -> bool:
	var chart: Dictionary = context.ocean if identity.layer == "ocean" else context.regions[identity.regionId]
	var margin: float = clearance / float(context.ocean.localUnitsPerUnit) if identity.layer == "ocean" else clearance
	return _inside_bounds(point, float(chart.width), float(chart.height), margin)


static func _water(context: Dictionary, identity: Dictionary, point: Dictionary, clearance: float) -> bool:
	if not _bounded(context, identity, point, clearance):
		return false
	return identity.layer == "ocean" or Navigation.is_water(_geometry(context, identity), point.x, point.y, clearance)


static func _segment_safe(context: Dictionary, identity: Dictionary, from: Dictionary, to: Dictionary, clearance: float) -> bool:
	if identity.layer == "ocean":
		return _water(context, identity, from, clearance) and _water(context, identity, to, clearance)
	return Navigation.path_clear(_geometry(context, identity), from, [to], clearance)


static func _approach(region: Dictionary, approach_id: String) -> Dictionary:
	for approach in region.approaches:
		if approach.id == approach_id:
			return approach
	return {}


static func _project(context: Dictionary, region: Dictionary, point: Dictionary) -> Dictionary:
	var scale: float = float(context.ocean.localUnitsPerUnit)
	return {"x": float(region.oceanOrigin.x) + float(point.x) / scale, "y": float(region.oceanOrigin.y) + float(point.y) / scale}


static func _unproject(context: Dictionary, region: Dictionary, point: Dictionary) -> Dictionary:
	var scale: float = float(context.ocean.localUnitsPerUnit)
	return {"x": (float(point.x) - float(region.oceanOrigin.x)) * scale, "y": (float(point.y) - float(region.oceanOrigin.y)) * scale}


static func _approach_safe(context: Dictionary, region: Dictionary, approach: Dictionary, clearance: float) -> bool:
	var identity: Dictionary = {"layer": region.layer, "regionId": region.id}
	var ocean_identity: Dictionary = {"layer": "ocean", "regionId": OCEAN}
	# Checking radius + hull clearance at the center protects the whole transfer
	# disk, including off-center exact-coordinate entry/departure endpoints.
	var disk_clearance: float = float(approach.radius) + clearance
	return _water(context, identity, approach.position, disk_clearance) and _water(context, ocean_identity, _project(context, region, approach.position), disk_clearance)


static func _destination(context: Dictionary, identity: Dictionary, destination: String) -> Dictionary:
	if destination.is_empty():
		return {"ok": true}
	if identity.layer == "home":
		if context.ports.has(destination):
			return {"ok": true, "port": context.ports[destination]}
		return {"ok": false, "message": "Home destinations must be original home port IDs or empty."}
	if identity.layer == "local" and identity.regionId == REMOTE and destination == REMOTE_PORT068:
		return {"ok":true,"port":_point(remote_port068())}
	if identity.layer == "local" and context.harbors.has(destination):
		var harbor: Dictionary = context.harbors[destination]
		if harbor.regionId != identity.regionId:
			return {"ok": false, "message": "A local course cannot target another region's harbor."}
		return {"ok": true, "port": _point(harbor)}
	var parts: PackedStringArray = destination.split(":", true)
	if parts.size() != 3 or parts[0] != "approach" or not context.regions.has(parts[1]):
		return {"ok": false, "message": "Unknown regional approach destination."}
	if identity.layer == "local" and identity.regionId != parts[1]:
		return {"ok": false, "message": "A local course cannot target another region's approach."}
	var region: Dictionary = context.regions[parts[1]]
	var approach: Dictionary = _approach(region, parts[2])
	if approach.is_empty():
		return {"ok": false, "message": "Unknown coastal approach destination."}
	var ocean: bool = identity.layer == "ocean"
	var point: Dictionary = _project(context, region, approach.position) if ocean else _point(approach.position)
	var radius: float = float(approach.radius) / float(context.ocean.localUnitsPerUnit) if ocean else float(approach.radius)
	return {"ok": true, "approach": _approach_view(region.id, approach, point, radius)}


static func _approach_view(region_id: String, approach: Dictionary, point: Dictionary, radius: float) -> Dictionary:
	return {"regionId": region_id, "id": approach.id, "name": approach.name, "position": _point(point), "radius": radius}


static func _region_view(context: Dictionary, region: Dictionary) -> Dictionary:
	var silhouettes: Array = []
	for island in region.islands:
		var outline: Array = []
		for pair in island.points:
			outline.append(_project(context, region, {"x": pair[0], "y": pair[1]}))
		silhouettes.append(outline)
	var approaches: Array = []
	for approach in region.approaches:
		approaches.append(_approach_view(region.id, approach, _project(context, region, approach.position), float(approach.radius) / float(context.ocean.localUnitsPerUnit)))
	return {"regionId": region.id, "name": region.name, "layer": region.layer, "silhouettes": silhouettes, "approaches": approaches,
		"bounds": {"x": float(region.oceanOrigin.x), "y": float(region.oceanOrigin.y), "width": float(region.width) / float(context.ocean.localUnitsPerUnit), "height": float(region.height) / float(context.ocean.localUnitsPerUnit)}}


static func _plain(value, depth: int = 0) -> bool:
	if depth > 32:
		return false
	if value == null or value is bool or value is String or _number(value):
		return true
	if value is Array:
		for child in value:
			if not _plain(child, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not _plain(value[key], depth + 1):
				return false
		return true
	return false
