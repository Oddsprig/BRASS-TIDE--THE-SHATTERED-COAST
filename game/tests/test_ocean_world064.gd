extends SceneTree
## Pure world fixture only. Root runs this through the shared Test Bridge lane.
## No Campaign, economy, save migration, pursuit or rendered-quality acceptance.
const World = preload("res://scripts/ocean_world064.gd")
const Navigation = preload("res://scripts/navigation.gd")
var checks: int = 0
var failures: int = 0
var home: Dictionary = {}
var atlas: Dictionary = {}
var context: Dictionary = {}
var home_nav: Dictionary = {}
var home_before: Dictionary = {}
var atlas_before: Dictionary = {}
var context_before: Dictionary = {}
var fleet_clearance: float = 10.0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL ocean world064: ", message)


func refused(result: Dictionary, field: String = "location", code: String = "") -> void:
	check(not result.ok and result.get(field) == {}, "refusal returns an empty " + field)
	check(result.code == code if not code.is_empty() else result.code != "ok", "refusal has the expected failure code")
	check(not str(result.message).is_empty(), "refusal explains the failure")


func location(layer: String, region_id: String, x: float, y: float) -> Dictionary:
	return {"world064": {"schema": 1, "layer": layer, "regionId": region_id},
		"position": {"x": x, "y": y}, "heading": 0.37, "path": [], "destination": ""}


func same_point(a: Dictionary, b: Dictionary) -> bool:
	return absf(float(a.x) - float(b.x)) < 0.000001 and absf(float(a.y) - float(b.y)) < 0.000001


func distance(a: Dictionary, b: Dictionary) -> float:
	var dx: float = float(a.x) - float(b.x)
	var dy: float = float(a.y) - float(b.y)
	return sqrt(dx * dx + dy * dy)


func _initialize() -> void:
	var home_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var atlas_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/ocean_regions064.json"))
	check(home_data is Dictionary and atlas_data is Dictionary, "actual home and two-region catalog load")
	if not home_data is Dictionary or not atlas_data is Dictionary:
		finish()
		return
	home = home_data
	atlas = atlas_data
	home_before = home.duplicate(true)
	atlas_before = atlas.duplicate(true)
	for hull in home.HULLS:
		fleet_clearance = maxf(fleet_clearance, float(hull.size))
	# One home graph and one remote graph for this entire fixture.
	home_nav = Navigation.create(home.ISLANDS, home.WORLD.width, home.WORLD.height, 40.0 * float(home.CAMPAIGN_SCALE))
	var made: Dictionary = World.create(home, atlas, home_nav)
	check(made.ok and made.code == "ok", "create accepts the actual definitions")
	if not made.ok:
		print(made.message)
		finish()
		return
	context = made.context
	context_before = context.duplicate(true)
	check(is_same(context.homeNav, home_nav), "context retains the original shared home navigation")
	check(context.remoteNav.nodes.size() < Navigation.MAX_NODES, "one remote coarse graph stays bounded")
	check(context.regions.size() == 2 and context.regions.glasswind_keys.islands.size() == 3, "only the existing coast and three-island prototype exist")
	check(context.regions.shatter_coast.islands == home.ISLANDS, "home island points are unchanged")
	check(context.ports.size() == home.PORTS.size(), "only original home port coordinates are retained")
	for port in home.PORTS:
		check(context.ports[port.id] == {"x": float(port.x), "y": float(port.y)}, "home port %s retains its original coordinates" % port.id)
	_test_definitions()
	_test_prepare()
	_test_transfers()
	_test_plot_and_advance()
	_test_views()
	check(home == home_before and atlas == atlas_before, "all pure operations preserve both original source dictionaries")
	check(context == context_before, "all pure operations preserve geometry, caches and shared home navigation")
	finish()


func finish() -> void:
	print("%d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_definitions() -> void:
	refused(World.create({}, atlas, home_nav), "context", "definitions")
	refused(World.create(home, atlas, {}), "context", "definitions")
	var bad: Dictionary = atlas.duplicate(true)
	bad.ocean.width = INF
	refused(World.create(home, bad, home_nav), "context", "definitions")
	bad = atlas.duplicate(true)
	bad.regions.append(bad.regions[1].duplicate(true))
	refused(World.create(home, bad, home_nav), "context", "definitions")
	bad = atlas.duplicate(true)
	bad.regions[1].ports = []
	refused(World.create(home, bad, home_nav), "context", "definitions")
	bad = atlas.duplicate(true)
	bad.regions[1].islands[0].points[0][0] = true
	refused(World.create(home, bad, home_nav), "context", "definitions")
	bad = atlas.duplicate(true)
	bad.regions[1].approaches[0].position.y = 0.0
	refused(World.create(home, bad, home_nav), "context", "definitions")
	check(atlas == atlas_before, "refused catalog inputs do not change the original atlas")


func _test_prepare() -> void:
	var old: Dictionary = {"mapRevision": 2, "position": {"x": home.PORTS[0].x, "y": home.PORTS[0].y},
		"heading": 0, "path": [], "destination": "", "coins": 123, "day": 7.25,
		"fleet": [{"uid": "fixture-owned-1", "fuel": 17.0}], "ports": [{"id": "retained-account", "coins": 99}]}
	var before: Dictionary = old.duplicate(true)
	var result: Dictionary = World.prepare(old, context, fleet_clearance)
	check(result.ok and result.location.world064 == {"schema": 1, "layer": "home", "regionId": "shatter_coast"}, "already migrated save with absent metadata defaults home")
	check(old == before and not old.has("world064"), "legacy default is copy-first and never writes accounts or the input save")
	if result.ok:
		check(result.location.size() == 5 and not result.location.has("fleet") and not result.location.has("day"), "prepare returns spatial fields only")
		result.location.position.x = 99.0
		check(old == before, "prepared location is detached from the saved player point")
	old.mapRevision = 1
	refused(World.prepare(old, context, fleet_clearance), "location", "location")
	var base: Dictionary = location("local", "glasswind_keys", 2100.0, 200.0)
	for identity in [null, {}, "home", {"schema": true, "layer": "home", "regionId": "shatter_coast"},
		{"schema": 2, "layer": "home", "regionId": "shatter_coast"},
		{"schema": 1, "layer": "home", "regionId": "glasswind_keys"},
		{"schema": 1, "layer": "local", "regionId": "missing"}]:
		var bad: Dictionary = base.duplicate(true)
		bad.world064 = identity
		var bad_before: Dictionary = bad.duplicate(true)
		refused(World.prepare(bad, context, fleet_clearance), "location", "location")
		check(bad == bad_before, "invalid present identity is refused without default or mutation")
	for value in [true, "2100", INF, NAN, -1.0, 5000.0]:
		var bad: Dictionary = base.duplicate(true)
		bad.position.x = value
		refused(World.prepare(bad, context, fleet_clearance), "location", "location")
	var land: Dictionary = location("local", "glasswind_keys", 1000.0, 1100.0)
	refused(World.prepare(land, context, fleet_clearance), "location", "location")
	var crossing: Dictionary = location("local", "glasswind_keys", 300.0, 1100.0)
	crossing.path = [{"x": 1700.0, "y": 1100.0}]
	refused(World.prepare(crossing, context, fleet_clearance), "location", "route")
	var bad_path: Dictionary = base.duplicate(true)
	bad_path.path = [{"x": true, "y": 300.0}]
	refused(World.prepare(bad_path, context, fleet_clearance), "location", "route")
	bad_path = base.duplicate(true)
	bad_path.path = [base.position.duplicate()]
	refused(World.prepare(bad_path, context, fleet_clearance), "location", "route")
	for destination in ["brass_haven", "approach:shatter_coast:north", "approach:glasswind_keys:missing"]:
		var bad: Dictionary = base.duplicate(true)
		bad.destination = destination
		refused(World.prepare(bad, context, fleet_clearance), "location", "location")
	var wrong_end: Dictionary = base.duplicate(true)
	wrong_end.destination = "approach:glasswind_keys:south"
	refused(World.prepare(wrong_end, context, fleet_clearance), "location", "route")
	var idle_home: Dictionary = location("home", "shatter_coast", 5200.0, 12.0)
	check(World.prepare(idle_home, context, fleet_clearance).ok, "idle home positions keep base-clearance dock semantics")
	refused(World.plot(context, idle_home, {"x": 5200.0, "y": 300.0}, "", fleet_clearance), "location", "route")
	refused(World.prepare(base, {}, fleet_clearance), "location", "definitions")
	refused(World.prepare(base, context, INF), "location", "location")
	var ocean_edge: Dictionary = location("ocean", "open_ocean", fleet_clearance / 10.0 - 0.1, 300.0)
	refused(World.prepare(ocean_edge, context, fleet_clearance), "location", "location")
	ocean_edge.position.x = fleet_clearance / 10.0
	check(World.prepare(ocean_edge, context, fleet_clearance).ok, "ocean border clearance uses the physical ten-to-one scale")


func _test_transfers() -> void:
	for region_id in ["shatter_coast", "glasswind_keys"]:
		var region: Dictionary = context.regions[region_id]
		var nav: Dictionary = home_nav if region.layer == "home" else context.remoteNav
		for approach in region.approaches:
			check(Navigation.is_water(nav, approach.position.x, approach.position.y, fleet_clearance + approach.radius), "%s/%s entire approach disk clears the largest real catalog hull" % [region_id, approach.id])
			var original: Dictionary = location(region.layer, region_id, approach.position.x + 20.0, approach.position.y + 30.0)
			original.coins = 127
			original.day = 9.5
			original.encounterGrace = 0.0
			original.fleet = [{"uid": "fixture-owned-1", "hp": 42.0, "fuel": 12.0}]
			var before: Dictionary = original.duplicate(true)
			var departed: Dictionary = World.transition(context, original, region_id, approach.id, fleet_clearance, "")
			check(departed.ok, "%s/%s departs from an off-center point" % [region_id, approach.id])
			if not departed.ok:
				continue
			var expected: Dictionary = {"x": float(region.oceanOrigin.x) + float(original.position.x) / 10.0, "y": float(region.oceanOrigin.y) + float(original.position.y) / 10.0}
			check(same_point(departed.location.position, expected), "departure projects the actual point without center snapping")
			check(departed.location.world064 == {"schema": 1, "layer": "ocean", "regionId": "open_ocean"}, "departure uses the canonical ocean identity")
			var returned: Dictionary = World.transition(context, departed.location, region_id, approach.id, fleet_clearance, "")
			check(returned.ok and same_point(returned.location.position, original.position), "paired inverse returns to the original off-center local point")
			if returned.ok:
				check(returned.location.heading == original.heading and returned.location.path.is_empty() and returned.location.destination.is_empty(), "transfer preserves heading and returns a stopped spatial location")
			check(original == before and not departed.location.has("coins") and not departed.location.has("fleet"), "transfer never changes accounts, time, grace, hull damage or supplies")
	var base: Dictionary = location("home", "shatter_coast", 5200.0, 300.0)
	refused(World.transition(context, base, "shatter_coast", "north", fleet_clearance, "Live pursuit blocks departure."), "location", "blocked")
	refused(World.transition(context, base, "glasswind_keys", "north", fleet_clearance, ""), "location", "approach")
	refused(World.transition(context, base, "shatter_coast", "south", fleet_clearance, ""), "location", "approach")
	refused(World.transition(context, base, "shatter_coast", "missing", fleet_clearance, ""), "location", "approach")
	refused(World.transition(context, base, "shatter_coast", "north", 400.0, ""), "location", "approach")
	base.path = [{"x": 5200.0, "y": 400.0}]
	refused(World.transition(context, base, "shatter_coast", "north", fleet_clearance, ""), "location", "approach")
	var far_ocean: Dictionary = location("ocean", "open_ocean", 2400.0, 1400.0)
	refused(World.transition(context, far_ocean, "glasswind_keys", "north", fleet_clearance, ""), "location", "approach")


func _test_plot_and_advance() -> void:
	var start: Dictionary = location("ocean", "open_ocean", 1220.0, 1130.0)
	var start_before: Dictionary = start.duplicate(true)
	var target: Dictionary = {"x": 3510.0, "y": 620.0}
	var plotted: Dictionary = World.plot(context, start, target, "approach:glasswind_keys:north", fleet_clearance)
	check(plotted.ok and plotted.location.path == [target], "ocean plotting produces one bounded straight segment")
	check(start == start_before and plotted.location.position == start.position and plotted.location.heading == start.heading, "plot preserves and detaches the original location")
	if plotted.ok:
		var stationary: Dictionary = World.advance(context, plotted.location, 0.0, 2000.0, fleet_clearance)
		check(stationary.ok and not stationary.moving and not stationary.arrived and stationary.distance == 0.0 and stationary.location == plotted.location, "zero-time advance preserves the route without movement or arrival")
		var moved: Dictionary = World.advance(context, plotted.location, 0.25, 2000.0, fleet_clearance)
		check(moved.ok and moved.moving and not moved.arrived and absf(float(moved.distance) - 500.0) < 0.000001, "ocean advance reports home-unit physical distance")
		if moved.ok:
			check(absf(distance(start.position, moved.location.position) - 50.0) < 0.000001, "physical five-hundred-unit movement covers fifty ocean units")
			check(moved.location.destination == "approach:glasswind_keys:north", "movement retains approach intent")
		var arrived: Dictionary = World.advance(context, plotted.location, 100.0, 1000.0, fleet_clearance)
		check(arrived.ok and arrived.arrived and arrived.location.path.is_empty() and arrived.location.destination == plotted.location.destination, "arrival completes the path without consuming Core's destination")
		if arrived.ok:
			check(absf(float(arrived.distance) - distance(start.position, target) * 10.0) < 0.000001, "arrival charges traversed distance only, without unused step budget")
			var entered: Dictionary = World.transition(context, arrived.location, "glasswind_keys", "north", fleet_clearance, "")
			check(entered.ok and same_point(entered.location.position, {"x": 2100.0, "y": 200.0}), "actual ocean course arrives at the paired remote entry")
	refused(World.plot(context, start, {"x": 3509.0, "y": 620.0}, "approach:glasswind_keys:north", fleet_clearance), "location", "target")
	refused(World.plot(context, start, {"x": INF, "y": 620.0}, "", fleet_clearance), "location", "target")
	refused(World.plot(context, start, {"x": 4900.0, "y": 620.0}, "", fleet_clearance), "location", "target")
	# A projected island is presentation only on the abstract ocean chart.
	var silhouette: Dictionary = context.regionViews[1].silhouettes[0][0]
	check(World.plot(context, start, silhouette, "", fleet_clearance).ok, "ocean silhouettes do not become coarse land collision")
	var remote: Dictionary = location("local", "glasswind_keys", 2100.0, 200.0)
	var local_route: Dictionary = World.plot(context, remote, {"x": 2100.0, "y": 2800.0}, "approach:glasswind_keys:south", fleet_clearance)
	check(local_route.ok, "remote navigation connects north and south around the three actual islands")
	if local_route.ok:
		check(local_route.location.path.size() > 1 and Navigation.path_clear(context.remoteNav, remote.position, local_route.location.path, fleet_clearance), "remote route detours with actual fleet clearance and excludes its start")
		var expected_distance: float = 0.0
		var previous: Dictionary = remote.position
		for point in local_route.location.path:
			expected_distance += distance(previous, point)
			previous = point
		var moved: Dictionary = World.advance(context, local_route.location, 100.0, 1000.0, fleet_clearance)
		check(moved.ok and moved.arrived and absf(float(moved.distance) - expected_distance) < 0.000001, "local movement uses the unchanged home distance scale")
	refused(World.plot(context, remote, {"x": 1000.0, "y": 1100.0}, "", fleet_clearance), "location", "target")
	var unsafe: Dictionary = location("local", "glasswind_keys", 300.0, 1100.0)
	unsafe.path = [{"x": 1700.0, "y": 1100.0}]
	var unsafe_before: Dictionary = unsafe.duplicate(true)
	var failure: Dictionary = World.advance(context, unsafe, 1.0, 2000.0, fleet_clearance)
	refused(failure, "location", "route")
	check(failure.distance == 0.0 and not failure.moving and not failure.arrived and unsafe == unsafe_before, "unsafe movement refuses atomically with zero reported travel")
	for pair in [[-1.0, 100.0], [1.0, -1.0], [NAN, 100.0], [1.0, INF]]:
		failure = World.advance(context, start, pair[0], pair[1], fleet_clearance)
		refused(failure, "location", "step")
		check(failure.distance == 0.0 and not failure.moving and not failure.arrived, "invalid step returns the canonical stopped result")
	var corner: Dictionary = location("ocean", "open_ocean", 2000.0, 1000.0)
	corner.path = [{"x": 2010.0, "y": 1000.0}, {"x": 2010.0, "y": 1020.0}]
	var whole: Dictionary = World.advance(context, corner, 1.0, 500.0, fleet_clearance)
	var part: Dictionary = World.advance(context, corner, 0.5, 500.0, fleet_clearance)
	if part.ok:
		var rest: Dictionary = World.advance(context, part.location, 0.5, 500.0, fleet_clearance)
		check(whole.ok and rest.ok and whole.location == rest.location and absf(float(whole.distance) - 300.0) < 0.000001 and absf(float(part.distance) + float(rest.distance) - float(whole.distance)) < 0.000001, "split steps consume each corner leg once and preserve physical distance")
	var idle: Dictionary = World.advance(context, start, 1.0, 500.0, fleet_clearance)
	check(idle.ok and not idle.moving and not idle.arrived and idle.distance == 0.0, "idle advance does not invent movement or an arrival")
	var coast: Dictionary = location("home", "shatter_coast", 5200.0, 300.0)
	var port: Dictionary = home.PORTS[0]
	var home_route: Dictionary = World.plot(context, coast, {"x": port.x, "y": port.y}, str(port.id), fleet_clearance)
	check(home_route.ok, "home course keeps its original port ID")
	if home_route.ok:
		var endpoint: Dictionary = Navigation.harbor_approach(home_nav, port, fleet_clearance)
		check(same_point(home_route.location.path[-1], endpoint) and Navigation.path_clear(home_nav, coast.position, home_route.location.path, fleet_clearance), "home harbor course uses the existing safe harbor approach")


func _test_views() -> void:
	var boats: Array = [{"uid": "fixture-owned-1", "spec": {"id": "tin_skiff", "size": 14.0}, "fuel": 12.0}]
	var boats_before: Array = boats.duplicate(true)
	# Kelp Reach's unchanged point also lies in remote water. Layer identity,
	# rather than numeric coincidence or lastPort, controls interaction permission.
	var overlap: Dictionary = location("local", "glasswind_keys", float(home.PORTS[1].x), float(home.PORTS[1].y))
	var overlap_before: Dictionary = overlap.duplicate(true)
	var local_view: Dictionary = World.view(context, overlap, boats)
	check(local_view.ok and not local_view.view.homeInteractions and local_view.view.regionId == "glasswind_keys", "overlapping home coordinates never grant remote home interaction permission")
	if local_view.ok:
		check(local_view.view.islands.size() == 3 and local_view.view.regions.size() == 2 and local_view.view.approaches.size() == 2, "local view exposes exact three-island geometry and both projected regions")
		check(local_view.view.bounds == {"x": 0.0, "y": 0.0, "width": 4200.0, "height": 3000.0}, "local view supplies finite zero-origin chart bounds")
		check(local_view.view.boats == boats and local_view.view.boats[0].uid == "fixture-owned-1", "view retains supplied active boats and UIDs")
		check(not local_view.view.has("ports") and not local_view.view.has("markets"), "remote view fabricates no home account facade")
		local_view.view.position.x = 0.0
		local_view.view.islands[0].points[0][0] = 0.0
		local_view.view.regions[0].silhouettes[0][0].x = 0.0
		local_view.view.approaches[0].position.x = 0.0
		local_view.view.boats[0].spec.size = 999.0
		check(overlap == overlap_before and boats == boats_before and context == context_before, "editing every nested view container cannot change live location, boats or geometry")
	var routed: Dictionary = location("ocean", "open_ocean", 1220.0, 1130.0)
	routed.path = [{"x": 1300.0, "y": 1200.0}]
	var routed_view: Dictionary = World.view(context, routed, boats)
	if routed_view.ok:
		routed_view.view.path[0].x = 0.0
		check(routed.path[0].x == 1300.0, "view route waypoints are detached")
	else:
		check(false, "a valid routed view is available")
	var ocean: Dictionary = location("ocean", "open_ocean", 1220.0, 1130.0)
	var ocean_view: Dictionary = World.view(context, ocean, boats)
	check(ocean_view.ok and ocean_view.view.islands.is_empty() and ocean_view.view.approaches.size() == 4 and not ocean_view.view.homeInteractions, "ocean view has four scaled approaches and no local collision islands")
	if ocean_view.ok:
		for region in ocean_view.view.regions:
			for approach in region.approaches:
				check(approach.radius == 8.0 and approach.position.has("x") and approach.position.has("y"), "ocean approaches use canonical points and eight-unit radii")
	var coast: Dictionary = location("home", "shatter_coast", 5200.0, 300.0)
	var home_view: Dictionary = World.view(context, coast, [])
	check(home_view.ok and home_view.view.homeInteractions and home_view.view.islands == home.ISLANDS and home_view.view.boats.is_empty(), "home view retains original geometry and never infers an active fleet")
	refused(World.view({}, coast, boats), "view", "definitions")
	refused(World.view(context, coast, [null]), "view", "location")
	refused(World.view(context, coast, [boats[0], boats[0]]), "view", "location")
