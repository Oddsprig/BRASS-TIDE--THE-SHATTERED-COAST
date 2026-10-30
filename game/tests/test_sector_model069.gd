extends SceneTree
## Source fixture only. Root runs this through the shared Test Bridge lane.
const Sector = preload("res://scripts/sector_world069.gd")
const World = preload("res://scripts/ocean_world064.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Travel = preload("res://scripts/ocean_travel066.gd")
var passed: int = 0
var failures: Array = []


func _initialize() -> void:
	var home: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var anchors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ocean_regions064.json"))
	_run(home, anchors)
	print("SECTOR_MODEL069 " + JSON.stringify({"passed":passed, "failed":failures.size(), "failures":failures}))
	print("%d checks, %d failures" % [passed + failures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:passed += 1
	else:failures.append(label)


func _run(home: Dictionary, anchors: Dictionary) -> void:
	var originals: String = JSON.stringify([home, anchors])
	var generated: Dictionary = Sector.generate(69029, home, anchors)
	_check(generated.ok, "generate: " + str(generated.message))
	if not generated.ok:
		var anchor_schema = anchors.get("schema")
		print("SECTOR_MODEL069_ANCHOR_DIAGNOSTICS " + JSON.stringify({
			"message":generated.message, "schemaType":typeof(anchor_schema), "schemaValue":anchor_schema,
			"keys":World._keys(anchors, ["schema", "ocean", "regions"]), "number":World._number(anchor_schema),
			"plain":World._plain(anchors), "schemaMembership":anchor_schema in [1, 2],
			"schemaNumericEquality":anchor_schema == 1 or anchor_schema == 2,
			"atlasError":World.atlas_error(home, anchors)}))
		return
	var sector: Dictionary = generated.sector
	var repeat: Dictionary = Sector.generate(69029, home, anchors)
	var varied: Dictionary = Sector.generate(69030, home, anchors)
	_check(repeat.ok and JSON.stringify(sector) == JSON.stringify(repeat.sector), "same seed is deterministic")
	_check(varied.ok and sector.atlas != varied.atlas, "different seed changes resolved geography")
	_check(JSON.stringify([home, anchors]) == originals, "generation leaves inputs unchanged")
	_check(sector.atlas.regions.size() == 48 and sector.regionOrder.size() == 48, "48 TOTAL regions")
	var bands: Dictionary = {"settled":0, "frontier":0, "remote":0}
	for band in sector.bands.values():bands[band] += 1
	_check(bands == {"settled":8,"frontier":12,"remote":28}, "8/12/28 including old regions")
	_check(sector.atlas.regions[0] == anchors.regions[0] and sector.atlas.regions[1] == anchors.regions[1], "authored geometry retained exactly")
	_check(_separated(sector.atlas), "all projected local charts are nonoverlapping")
	_check(sector.sites.size() == 46 and sector.harbors.size() == 19, "46 added survey landings / 19 finite harbors")
	_check(sector.openingLedger.totals.workers == 280 and sector.openingLedger.totals.coins == 980000, "finite declared opening workers/coins")
	_check(sector.harbors[0].id == "settled_01_harbor_01" and sector.harbors[1].id == "settled_01_harbor_02" and sector.harbors[0].faction == "compact" and sector.harbors[1].faction == "reed" and sector.harbors[0].islandId != sector.harbors[1].islandId and sector.harbors[0].specialty == "food" and sector.harbors[1].specialty == "logs", "mixed group owns separate complementary assets")
	var physical: Dictionary = {}
	for region in sector.atlas.regions:
		var islands: Array = home.ISLANDS if region.id == World.HOME else region.islands
		var geometry: Dictionary = Navigation.geometry(islands, 10400.0 if region.id == World.HOME else 4200.0, 7200.0 if region.id == World.HOME else 3000.0)
		physical[region.id] = geometry
		_check(not geometry.has("nodes") and not geometry.has("edges"), "geometry creates no grid: " + region.id)
		for approach in region.approaches:
			_check(Navigation.is_water(geometry, approach.position.x, approach.position.y, float(approach.radius) + 10.0), "whole approach disk clear: " + region.id + "/" + approach.id)
		if region.id not in World.REGION_ORDER:
			_check(Navigation.path_clear(geometry, {"x":2100.0,"y":200.0}, [{"x":2100.0,"y":2800.0}], 90.0), "two approaches connected: " + region.id)
	for landing in sector.sites + sector.harbors:
		var geometry: Dictionary = physical[landing.regionId]
		var berth: Dictionary = {"x":float(landing.x),"y":float(landing.y)}
		for y in [200.0, 2800.0]:
			_check(Navigation.path_clear(geometry, {"x":2100.0,"y":y}, [{"x":2100.0,"y":berth.y}, berth], 90.0), "landing reachable from both approaches: " + landing.id + "/" + str(y))
	var saved: Dictionary = {"sector069":JSON.parse_string(JSON.stringify(sector))}
	var saved_before: String = JSON.stringify(saved)
	var expected_sector: Dictionary = saved.sector069.duplicate(true)
	expected_sector.seed = int(expected_sector.seed)
	var restored: Dictionary = Sector.prepare(saved, home, anchors)
	_check(restored.ok and restored.sector == expected_sector, "restore retains resolved geography and opening provenance: " + str(restored.message))
	if not restored.ok:return
	restored.sector.harbors[0].name = "detached result"
	_check(JSON.stringify(saved) == saved_before, "restore output detached / saved input unchanged")
	var legacy: Dictionary = Sector.prepare({"coins":17,"ports":[]}, home, anchors)
	_check(legacy.ok and legacy.sector.is_empty() and legacy.atlas == anchors, "absent sector retains legacy two-region world without mint")
	for mutation in ["seed", "missing_region", "overlap", "geometry_resource", "landing", "opening", "ownership", "anchor"]:
		var bad: Dictionary = sector.duplicate(true)
		match mutation:
			"seed":bad.seed = "69029"
			"missing_region":bad.atlas.regions.pop_back()
			"overlap":bad.atlas.regions[3].oceanOrigin = bad.atlas.regions[2].oceanOrigin.duplicate()
			"geometry_resource":bad.atlas.regions[2].islands[0]["resource"] = "food"
			"landing":bad.sites[0].x = -100.0
			"opening":bad.openingLedger.harbors[0].allocation.cash += 1
			"ownership":bad.initialOwnership[0].faction = "fabricated"
			"anchor":bad.atlas.regions[1].islands[0].points[0][0] += 1
		var before: String = JSON.stringify(bad)
		var rejected: Dictionary = Sector.prepare({"sector069":bad}, home, anchors)
		_check(not rejected.ok and rejected.sector.is_empty() and rejected.atlas.is_empty() and before == JSON.stringify(bad), "malformed present sector refused without repair: " + mutation)
	_check(not Sector.prepare({"sector069":{}}, home, anchors).ok, "present empty sector never becomes legacy")
	_check(not Sector.prepare({"seed":69030,"sector069":sector}, home, anchors).ok, "campaign/sector seed mismatch refused")
	_runtime(home, anchors, sector)


func _runtime(home: Dictionary, anchors: Dictionary, sector: Dictionary) -> void:
	# One home grid, one pinned Glasswind grid and at most one generated grid.
	var home_nav: Dictionary = Navigation.create(home.ISLANDS, home.WORLD.width, home.WORLD.height, 160.0)
	var built: Dictionary = World.create(home, sector.atlas, home_nav, sector.harbors)
	_check(built.ok, "generated World context: " + str(built.message))
	if not built.ok:return
	var context: Dictionary = built.context
	var pinned: Dictionary = context.remoteNav
	_check(is_same(context.homeNav, home_nav) and context.activeNav.is_empty(), "create shares home / pins Glasswind / no generated grids")
	var region: Dictionary = context.regions.settled_01
	var origin: Dictionary = region.oceanOrigin
	var ocean: Dictionary = _location("ocean", World.OCEAN, {"x":float(origin.x) + 210.0,"y":float(origin.y) + 20.0})
	var chart: Dictionary = World.view(context, ocean, [])
	_check(chart.ok and chart.view.regions.size() == 48 and context.activeNav.is_empty(), "one geometry view supplies all48 without grid allocation")
	var entered: Dictionary = World.transition_player(context, ocean, "settled_01", "north", 10.0, "")
	_check(entered.ok and context.activeRegionId == "settled_01" and not context.activeNav.is_empty(), "entry prepares active generated grid before publication")
	if not entered.ok:return
	var active: Dictionary = context.activeNav
	var player: Dictionary = World.prepare_player(entered.location, context, 10.0)
	_check(player.ok and is_same(context.activeNav, active), "actual player preparation reuses its generated grid")
	if not player.ok:return
	for iteration in range(3):
		var merchant: Dictionary = World.prepare(_location("local", World.REMOTE, {"x":756.0,"y":732.0}), context, 10.0)
		_check(merchant.ok and is_same(context.remoteNav, pinned) and is_same(context.activeNav, active), "Glasswind merchant does not thrash player grid " + str(iteration))
	var harbor: Dictionary = sector.harbors[0]
	var stale_sighting: Dictionary = World.prepare(_location("local", "settled_02", {"x":2100.0,"y":200.0}), context, 10.0)
	var course: Dictionary = World.plot(context, player.location, {"x":harbor.x,"y":harbor.y}, harbor.id, 10.0)
	_check(stale_sighting.ok and context.activeRegionId == "settled_01" and is_same(context.activeNav, active) and course.ok, "stale generated-region sighting read preserves player grid and plotting")
	_check(course.ok, "canonical generated harbor destination is navigable")
	var merchant_approach: Dictionary = context.regions[World.REMOTE].approaches[0]
	var merchant_departed: Dictionary = World.transition(context, _location("local", World.REMOTE, merchant_approach.position), World.REMOTE, merchant_approach.id, 10.0, "")
	var after_merchant: Dictionary = World.plot(context, player.location, {"x":harbor.x,"y":harbor.y}, harbor.id, 10.0)
	_check(merchant_departed.ok and context.activeRegionId == "settled_01" and is_same(context.activeNav, active) and is_same(context.remoteNav, pinned) and after_merchant.ok, "ordinary merchant transition preserves player grid and subsequent plotting")
	var forged: Dictionary = _location("local", "fabricated_group", {"x":2100.0,"y":200.0})
	_check(not World.prepare(forged, context, 10.0).ok, "fabricated local membership rejected")
	_check(not World.prepare(_location("home", "settled_01", {"x":2100.0,"y":200.0}), context, 10.0).ok, "home identity cannot be generalized")
	_check(Travel.create(context, 69029).ok, "Travel accepts the generated context bounds")
	_check(context.homeNav.nodes.size() < Navigation.MAX_NODES and context.remoteNav.nodes.size() < Navigation.MAX_NODES and context.activeNav.nodes.size() < Navigation.MAX_NODES, "three bounded grids only")
	var left: Dictionary = World.transition_player(context, entered.location, "settled_01", "north", 10.0, "")
	_check(left.ok and context.activeNav.is_empty() and is_same(context.remoteNav, pinned), "exit evicts only generated grid / Glasswind remains pinned")
	var legacy: Dictionary = World.create(home, anchors, home_nav)
	_check(legacy.ok and legacy.context.regions.size() == 2 and legacy.context.ocean.width == 4800.0, "unchanged legacy context remains supported")


func _location(layer: String, region: String, position: Dictionary) -> Dictionary:
	return {"world064":{"schema":1,"layer":layer,"regionId":region}, "position":position, "heading":0.0, "path":[], "destination":""}


func _separated(atlas: Dictionary) -> bool:
	var bounds: Array = []
	for region in atlas.regions:
		var rectangle: Rect2 = Rect2(float(region.oceanOrigin.x), float(region.oceanOrigin.y), 1040.0 if region.id == World.HOME else 420.0, 720.0 if region.id == World.HOME else 300.0)
		for other in bounds:
			if rectangle.intersects(other):return false
		bounds.append(rectangle)
	return true
