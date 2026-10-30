extends RefCounted
## Canonical, detached NEW GAME geography and finite opening provenance.
## Restore validates saved definitions; it never replays generation or endowments.
const World = preload("res://scripts/ocean_world064.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Industry = preload("res://scripts/industry_data.gd")
const TEMPLATE_PATH: String = "res://data/sector_templates069.json"
const REVISION: String = "069.1"
const FACTIONS: Array = ["compact", "forge", "reed", "raiders"]
const SERVICES: Array = ["trade", "supplies", "fuel"]
const HOME_ISLANDS: Dictionary = {"brass_haven":"isl_lantern", "kelp_reach":"isl_kelp",
	"sawtooth_mill":"isl_sawtooth", "silt_hollow":"isl_verdigris", "cinder_quay":"isl_cinder",
	"anvil_dock":"isl_cinder", "reed_floats":"isl_fen", "naphtha_bay":"isl_oilstone",
	"rust_anchorage":"isl_shatter", "shatter_spire":"isl_shatter"}
const SECTOR_FIELDS: Array = ["schema", "generatorRevision", "seed", "atlas", "regionOrder", "bands",
	"islandFacts", "sites", "harbors", "initialOwnership", "openingLedger"]
const SITE_FIELDS: Array = ["id", "name", "regionId", "islandId", "x", "y", "kind", "region",
	"clue", "discovery", "hazard", "resource", "leadId"]
const HARBOR_FIELDS: Array = ["id", "name", "regionId", "islandId", "x", "y", "faction", "industry", "specialty", "services"]


static func generate(seed: int, home: Dictionary, anchors: Dictionary) -> Dictionary:
	var error: String = _inputs_error(home, anchors)
	if not error.is_empty():return _failure(error)
	if not FileAccess.file_exists(TEMPLATE_PATH):return _failure("Missing versioned sector templates.")
	var templates = JSON.parse_string(FileAccess.get_file_as_string(TEMPLATE_PATH))
	if not _templates_valid(templates):return _failure("Missing or invalid versioned sector templates.")
	# Park-Miller state uses integer arithmetic only; retain the supplied seed verbatim.
	# The two remainders also support negative seeds without abs(INT64_MIN) overflow.
	var rng: Array = [((seed % 2147483646) + 2147483646) % 2147483646 + 1]
	var order: Array = World.region_order069()
	var atlas: Dictionary = anchors.duplicate(true)
	atlas.schema = 2
	atlas.ocean.width = 12800.0
	atlas.ocean.height = 8400.0
	var sector: Dictionary = {"schema": 1, "generatorRevision": REVISION, "seed": seed, "atlas": atlas,
		"regionOrder": order, "bands": {}, "islandFacts": {}, "sites": [], "harbors": [],
		"initialOwnership": [], "openingLedger": {}}
	var slots: Array = _slots(anchors)
	if slots.size() < 46:return _failure("The bounded slot layout has insufficient separated charts.")
	slots.resize(46)
	# Permute only within geographic bands; distant groups remain distant.
	for span in [[0, 7], [7, 18], [18, 46]]:
		for index in range(int(span[1]) - 1, int(span[0]), -1):
			var other: int = _draw(rng, int(span[0]), index)
			var swap = slots[index]
			slots[index] = slots[other]
			slots[other] = swap
	var name_offset: int = _draw(rng, 0, 45)
	for index in range(order.size()):
		var id: String = order[index]
		sector.bands[id] = _band(id)
		if index < 2:
			var old_islands: Array = home.ISLANDS if id == World.HOME else anchors.regions[1].islands
			for island in old_islands:
				sector.islandFacts[_island_key(id, island.id)] = _fact(id, island.id, "", "", [])
			continue
		var layout: Dictionary = templates.layouts[_draw(rng, 0, templates.layouts.size() - 1)]
		var name: String = "%s %s" % [templates.names[(index - 2 + name_offset) % 46], layout.label]
		var shapes: Dictionary = _shapes(id, name, layout, templates.profiles, rng)
		var slot: Dictionary = slots[index - 2]
		# Keep the original two RNG draws, so only ocean placement changes.
		var offset_x: int = _draw(rng, -465, 465)
		var offset_y: int = _draw(rng, -345, 345)
		var origin: Dictionary = _offset_origin(slot, anchors, offset_x, offset_y)
		if origin.is_empty():return _failure("No safe bounded offset for a generated chart.")
		var region: Dictionary = {"id": id, "name": name, "layer": "local", "width": 4200.0, "height": 3000.0,
			"oceanOrigin": origin,
			"islands": shapes.islands, "approaches": [
				{"id":"north", "name":name + " North Approach", "position":{"x":2100.0,"y":200.0}, "radius":80.0},
				{"id":"south", "name":name + " South Approach", "position":{"x":2100.0,"y":2800.0}, "radius":80.0}]}
		atlas.regions.append(region)
		var opportunity: Dictionary = templates.opportunities[0 if id == "settled_01" else _draw(rng, 0, templates.opportunities.size() - 1)]
		var landing: Dictionary = shapes.landings[0]
		var site_id: String = id + "_survey"
		sector.sites.append({"id":site_id, "name":name + " Survey Landing", "regionId":id,
			"islandId":region.islands[0].id, "x":landing.x, "y":landing.y, "kind":"sector_survey", "region":name,
			"clue":opportunity.clue, "discovery":opportunity.discovery, "hazard":opportunity.hazard,
			"resource":opportunity.resource, "leadId":""})
		for island_index in range(region.islands.size()):
			var island: Dictionary = region.islands[island_index]
			var facts: Dictionary = templates.opportunities[1] if id == "settled_01" and island_index == 1 else opportunity
			sector.islandFacts[_island_key(id, island.id)] = _fact(id, island.id, facts.resource, facts.hazard, [site_id] if island_index == 0 else [])
		if _band(id) != "remote":
			var faction: String = "compact" if id == "settled_01" else str(FACTIONS[_draw(rng, 0, 2)])
			sector.harbors.append(_harbor(id, name, region.islands[0].id, landing, 1, faction, opportunity))
			if id == "settled_01":
				sector.harbors.append(_harbor(id, name, region.islands[1].id, shapes.landings[1], 2, "reed", templates.opportunities[1]))
	sector.initialOwnership = _ownership(home, atlas, sector.harbors)
	sector.openingLedger = _opening(sector.harbors, sector.bands)
	# Validate the completed detached product, with no economic application or grids.
	error = _sector_error(sector, home, anchors)
	return _failure(error) if not error.is_empty() else _success(sector, atlas, "Seeded sector ready for one new campaign.")


static func prepare(saved: Dictionary, home: Dictionary, anchors: Dictionary) -> Dictionary:
	var error: String = _inputs_error(home, anchors)
	if not error.is_empty():return _failure(error)
	if not saved.has("sector069"):
		return _success({}, anchors, "Legacy two-region voyage retained without additional endowment.")
	if not saved.sector069 is Dictionary:return _failure("Present sector069 must be a canonical dictionary.")
	error = _sector_error(saved.sector069, home, anchors)
	if not error.is_empty():return _failure(error)
	if saved.has("seed") and (not _seed_valid(saved.seed) or int(saved.seed) != int(saved.sector069.seed)):
		return _failure("Campaign seed and canonical sector provenance disagree.")
	var sector: Dictionary = saved.sector069.duplicate(true)
	sector.seed = int(sector.seed)
	return _success(sector, sector.atlas, "Saved canonical sector retained; no regeneration or grants.")


static func _draw(rng: Array, low: int, high: int) -> int:
	rng[0] = (int(rng[0]) * 48271) % 2147483647
	return low + int(rng[0]) % (high - low + 1)


static func _band(id: String) -> String:
	if id == World.HOME or id.begins_with("settled_"):return "settled"
	if id == World.REMOTE or id.begins_with("frontier_"):return "frontier"
	return "remote"


static func _slots(anchors: Dictionary) -> Array:
	var slots: Array = []
	# Safe fallback lattice; assignment still uses its original near/far bands.
	# Offsets of 30% cell spacing leave >=200 horizontal / 160 vertical clear
	# ocean units between 420x300 charts, even with opposing neighbor offsets.
	for row in range(7):
		for column in range(8):
			var candidate: Dictionary = {"x":600 + 1550 * column, "y":500 + 1150 * row}
			if _slot_clear(candidate, anchors):
				candidate["distance2"] = pow(float(candidate.x) + 210.0 - 1220.0, 2.0) + pow(float(candidate.y) + 150.0 - 1460.0, 2.0)
				slots.append(candidate)
	slots.sort_custom(func(a, b): return a.distance2 < b.distance2 if a.distance2 != b.distance2 else (a.y < b.y if a.y != b.y else a.x < b.x))
	return slots


static func _offset_origin(slot: Dictionary, anchors: Dictionary, offset_x: int, offset_y: int) -> Dictionary:
	# A fixed five-candidate search, never a reroll. Reflections retain useful
	# displacement beside anchors; the original safe slot is checked last too.
	for offset in [[offset_x, offset_y], [-offset_x, offset_y], [offset_x, -offset_y], [-offset_x, -offset_y], [0, 0]]:
		var candidate: Dictionary = {"x":float(slot.x) + float(offset[0]), "y":float(slot.y) + float(offset[1])}
		if _slot_clear(candidate, anchors):return candidate
	return {}


static func _slot_clear(candidate: Dictionary, anchors: Dictionary) -> bool:
	if candidate.x < 0.0 or candidate.y < 0.0 or candidate.x + 420.0 > 12800.0 or candidate.y + 300.0 > 8400.0:return false
	# Check the FINAL rectangle, including every fallback, against both unchanged
	# authored charts and their 280-unit ocean buffer.
	for anchor in anchors.regions:
		var w: float = 1040.0 if anchor.id == World.HOME else 420.0
		var h: float = 720.0 if anchor.id == World.HOME else 300.0
		if candidate.x < anchor.oceanOrigin.x + w + 280.0 and candidate.x + 420.0 > anchor.oceanOrigin.x - 280.0 and candidate.y < anchor.oceanOrigin.y + h + 280.0 and candidate.y + 300.0 > anchor.oceanOrigin.y - 280.0:
			return false
	return true


static func _shapes(id: String, name: String, layout: Dictionary, profiles: Dictionary, rng: Array) -> Dictionary:
	var islands: Array = []
	var landings: Array = []
	var mirror: bool = _draw(rng, 0, 1) == 1
	for index in range(layout.islands.size()):
		var source: Dictionary = layout.islands[index]
		var cx: float = float(source.x) + float(_draw(rng, -50, 50))
		if mirror:cx = 4200.0 - cx
		var cy: float = float(source.y) + float(_draw(rng, -35, 35))
		var rx: float = float(source.rx) * float(_draw(rng, 90, 108)) / 100.0
		var ry: float = float(source.ry) * float(_draw(rng, 90, 108)) / 100.0
		var points: Array = []
		for pair in profiles[source.profile]:
			points.append([cx + float(pair[0]) * rx * (-1.0 if mirror else 1.0), cy + float(pair[1]) * ry])
		var shore_name: String = ("Westward" if cx < 2100.0 else "Eastward") + (" Upper" if cy < 1500.0 else " Lower")
		islands.append({"id":"%s_island_%02d" % [id, index + 1], "name":"%s %s" % [name, shore_name],
			"color":["#66877e", "#7a9489", "#5d8077", "#8a9380"][_draw(rng, 0, 3)], "points":points})
		# Every landing faces the continuous, generous central water corridor.
		landings.append({"x":cx + (rx + 110.0) * (1.0 if cx < 2100.0 else -1.0), "y":cy})
	return {"islands":islands, "landings":landings}


static func _harbor(id: String, name: String, island: String, point: Dictionary, ordinal: int, faction: String, opportunity: Dictionary) -> Dictionary:
	return {"id":"%s_harbor_%02d" % [id, ordinal], "name":name + (" Roads" if ordinal == 1 else " Timber Haven"),
		"regionId":id, "islandId":island, "x":float(point.x), "y":float(point.y), "faction":faction,
		"industry":opportunity.industry, "specialty":opportunity.specialty, "services":SERVICES.duplicate()}


static func _island_key(region: String, island: String) -> String:
	return region + "/" + island


static func _fact(region: String, island: String, resource: String, hazard: String, sites: Array) -> Dictionary:
	return {"regionId":region, "islandId":island, "resource":resource, "hazard":hazard, "siteIds":sites}


static func _ownership(home: Dictionary, atlas: Dictionary, harbors: Array) -> Array:
	var owners: Dictionary = {}
	for port in home.PORTS:
		owners[_island_key(World.HOME, HOME_ISLANDS[port.id])] = port.faction
	owners[_island_key(World.REMOTE, "glasswind_west")] = "reed"
	for harbor in harbors:
		owners[_island_key(harbor.regionId, harbor.islandId)] = harbor.faction
	var rows: Array = []
	for region in atlas.regions:
		var islands: Array = home.ISLANDS if region.id == World.HOME else region.islands
		for island in islands:
			rows.append({"regionId":region.id, "islandId":island.id, "faction":owners.get(_island_key(region.id, island.id), "")})
	for port in home.PORTS:
		rows.append({"regionId":World.HOME, "islandId":HOME_ISLANDS[port.id], "portId":port.id, "faction":port.faction})
	rows.append({"regionId":World.REMOTE, "islandId":"glasswind_west", "portId":World.REMOTE_PORT068, "faction":"reed"})
	for harbor in harbors:
		rows.append({"regionId":harbor.regionId, "islandId":harbor.islandId, "portId":harbor.id, "faction":harbor.faction})
	return rows


static func _zero_goods() -> Dictionary:
	var goods: Dictionary = {}
	for good in Industry.GOOD_KEYS:goods[good] = 0
	return goods


static func _opening(harbors: Array, bands: Dictionary) -> Dictionary:
	var entries: Array = []
	var totals: Dictionary = {"workers":0, "coins":0, "stocks":_zero_goods(), "publicStores":_zero_goods()}
	for harbor in harbors:
		var workers: int = 24 if bands[harbor.regionId] == "settled" else 8
		var stocks: Dictionary = _zero_goods()
		stocks.food = 2 * workers
		stocks.fuel = 16
		stocks.supplies = 8
		stocks[harbor.specialty] += 24
		var allocation: Dictionary = {"population":workers, "workforce":workers, "workers":0,
			"employedWorkers":0, "availableWorkers":workers, "publicWorkers":0, "specialists":0,
			"specialistWorkers":0, "availableSpecialists":0, "recruits":0,
			"cash":workers * 20 * 100, "householdPurse":workers * 5 * 100, "governmentPurse":workers * 10 * 100,
			"expertPurse":0, "escrow":0, "stocks":stocks, "publicStores":_zero_goods()}
		entries.append({"portId":harbor.id, "regionId":harbor.regionId,
			"provenance":"new_game_only:069.1:" + harbor.id, "allocation":allocation})
		totals.workers += workers
		totals.coins += allocation.cash + allocation.householdPurse + allocation.governmentPurse
		for good in Industry.GOOD_KEYS:totals.stocks[good] += stocks[good]
	return {"schema":1, "kind":"finite_new_world_endowment", "provenance":"new_game_only:069.1", "harbors":entries, "totals":totals}


static func _inputs_error(home: Dictionary, anchors: Dictionary) -> String:
	if not home.get("WORLD") is Dictionary or home.WORLD.get("width") != World.HOME_WIDTH or home.WORLD.get("height") != World.HOME_HEIGHT or home.get("CAMPAIGN_SCALE") != World.COAST_SCALE:
		return "Supply the accepted home coast dimensions and scale."
	if anchors.get("schema") != 1:return "Supply the unchanged two-region anchor catalog."
	var error: String = World.atlas_error(home, anchors)
	if not error.is_empty():return error
	if not home.get("PORTS") is Array or home.PORTS.size() != HOME_ISLANDS.size():return "The original home ports are required."
	var seen: Dictionary = {}
	for port in home.PORTS:
		if not port is Dictionary or not port.get("id") is String or not HOME_ISLANDS.has(port.id) or seen.has(port.id) or port.get("faction") not in FACTIONS:
			return "The original home port identities and factions are required."
		if not home.ISLANDS.any(func(island): return island.id == HOME_ISLANDS[port.id]):return "Home harbor island association is missing."
		seen[port.id] = true
	return ""


static func _sector_error(sector: Dictionary, home: Dictionary, anchors: Dictionary) -> String:
	if not _plain(sector) or not _keys(sector, SECTOR_FIELDS) or not _number(sector.schema) or sector.schema != 1 or sector.generatorRevision != REVISION or not _seed_valid(sector.seed):
		return "Unsupported or malformed canonical sector header."
	if not sector.atlas is Dictionary or sector.atlas.get("schema") != 2:return "A present sector requires its saved schema-2 atlas."
	var error: String = World.atlas_error(home, sector.atlas)
	if not error.is_empty():return error
	if sector.atlas.regions[0] != anchors.regions[0] or sector.atlas.regions[1] != anchors.regions[1]:return "Saved sector changed an authored anchor."
	var order: Array = World.region_order069()
	if sector.regionOrder != order or not sector.bands is Dictionary or sector.bands.size() != 48:return "Canonical region order or bands are missing."
	if not sector.islandFacts is Dictionary or not sector.sites is Array or sector.sites.size() != 46 or not sector.harbors is Array or sector.harbors.size() != 19:
		return "Canonical island facts, 46 added landings and 19 added harbors are required."
	var regions: Dictionary = {}
	var facts: Dictionary = {}
	var physical: Dictionary = {}
	for region in sector.atlas.regions:
		if sector.bands.get(region.id) != _band(region.id):return "A region has an invalid geographic band."
		regions[region.id] = region
		var islands: Array = home.ISLANDS if region.id == World.HOME else region.islands
		physical[region.id] = Navigation.geometry(islands, 10400.0 if region.id == World.HOME else 4200.0, 7200.0 if region.id == World.HOME else 3000.0)
		for index in range(islands.size()):
			var island: Dictionary = islands[index]
			var key: String = _island_key(region.id, island.id)
			if region.id not in World.REGION_ORDER and island.id != "%s_island_%02d" % [region.id, index + 1]:return "Generated islands require their saved stable identities."
			var fact = sector.islandFacts.get(key)
			if not _keys(fact, ["regionId", "islandId", "resource", "hazard", "siteIds"]) or fact.regionId != region.id or fact.islandId != island.id or not fact.resource is String or not fact.hazard is String or not fact.siteIds is Array:
				return "Invalid island fact or island association."
			if not fact.resource.is_empty() and not fact.resource in Industry.GOOD_KEYS:return "Unknown island resource."
			var expected_sites: Array = [region.id + "_survey"] if region.id not in World.REGION_ORDER and index == 0 else []
			if fact.siteIds != expected_sites:return "Island survey references are not canonical."
			if region.id not in World.REGION_ORDER and (fact.resource.is_empty() or fact.hazard.is_empty()):return "Generated islands require useful resource and hazard findings."
			facts[key] = fact
	if facts.size() != sector.islandFacts.size():return "Orphan island facts are not permitted."
	var site_ids: Dictionary = {}
	for site in sector.sites:
		if not _keys(site, SITE_FIELDS) or not _strings(site, ["id", "name", "regionId", "islandId", "kind", "region", "clue", "discovery", "hazard", "resource", "leadId"]):return "Malformed generated landing."
		if site.regionId in World.REGION_ORDER or not regions.has(site.regionId) or site.id != site.regionId + "_survey" or site_ids.has(site.id) or site.islandId != site.regionId + "_island_01":return "Unknown, repeated or mismatched generated landing."
		if site.kind != "sector_survey" or site.leadId != "" or site.region != regions[site.regionId].name or site.resource not in Industry.GOOD_KEYS or site.clue.is_empty() or site.discovery.is_empty() or site.hazard.is_empty():return "A generated landing needs useful paid-survey findings without reward grants."
		var fact: Dictionary = facts[_island_key(site.regionId, site.islandId)]
		if fact.resource != site.resource or fact.hazard != site.hazard or not _landing_reachable(physical[site.regionId], site):return "A landing disagrees with its island or is unreachable."
		site_ids[site.id] = site
	var harbor_ids: Dictionary = {}
	for harbor in sector.harbors:
		if not _keys(harbor, HARBOR_FIELDS) or not _strings(harbor, ["id", "name", "regionId", "islandId", "faction", "industry", "specialty"]):return "Malformed generated harbor definition."
		if not regions.has(harbor.regionId) or harbor.regionId in World.REGION_ORDER or _band(harbor.regionId) == "remote" or harbor_ids.has(harbor.id):return "Unknown or repeated generated harbor."
		var second: bool = harbor.regionId == "settled_01" and harbor.id == "settled_01_harbor_02"
		if harbor.id != harbor.regionId + ("_harbor_02" if second else "_harbor_01") or harbor.islandId != harbor.regionId + ("_island_02" if second else "_island_01"):return "Harbor identity does not match its canonical island."
		if harbor.faction not in FACTIONS or not Industry.INDUSTRIES.has(harbor.industry) or harbor.specialty not in Industry.GOOD_KEYS or harbor.services != SERVICES:return "Unsupported faction, industry or finite harbor service."
		if not _landing_reachable(physical[harbor.regionId], harbor):return "A harbor berth is unreachable clear water."
		if not second:
			var site: Dictionary = site_ids[harbor.regionId + "_survey"]
			if harbor.x != site.x or harbor.y != site.y:return "Primary harbor and survey landing must share the canonical berth."
		harbor_ids[harbor.id] = harbor
	for id in order:
		if id not in World.REGION_ORDER and _band(id) != "remote" and not harbor_ids.has(id + "_harbor_01"):return "A settled/frontier group has no finite actual services."
	if not harbor_ids.has("settled_01_harbor_02"):return "The mixed-faction starting group needs its second harbor."
	var first: Dictionary = harbor_ids["settled_01_harbor_01"]
	var second: Dictionary = harbor_ids["settled_01_harbor_02"]
	if first.faction != "compact" or first.specialty != "food" or first.industry != "agriculture" or second.faction != "reed" or second.specialty != "logs" or second.industry != "timber":return "The mixed starting group needs complementary food/logs owners."
	if sector.initialOwnership != _ownership(home, sector.atlas, sector.harbors):return "Starting island/harbor ownership provenance is inconsistent."
	if not _opening_matches(sector.openingLedger, _opening(sector.harbors, sector.bands)):return "Opening allocations or finite endowment totals are inconsistent."
	return ""


static func _opening_matches(actual, expected) -> bool:
	# JSON decodes numbers as floats. Compare exact values without changing saved
	# allocations; booleans are never numbers and structure must match completely.
	if actual is int or actual is float or expected is int or expected is float:
		return _number(actual) and _number(expected) and actual == expected
	if expected is Dictionary:
		if not actual is Dictionary or actual.size() != expected.size():return false
		for key in expected:
			if not key is String or not actual.has(key) or not _opening_matches(actual[key], expected[key]):return false
		return true
	if expected is Array:
		if not actual is Array or actual.size() != expected.size():return false
		for index in range(expected.size()):
			if not _opening_matches(actual[index], expected[index]):return false
		return true
	return typeof(actual) == typeof(expected) and actual == expected


static func _landing_reachable(physical: Dictionary, point: Dictionary) -> bool:
	if not _number(point.get("x")) or not _number(point.get("y")):return false
	var landing: Dictionary = {"x":float(point.x), "y":float(point.y)}
	# The authored template corridor admits a 90-unit hull clearance. This check
	# uses the unchanged physical predicates, never a grid or an iterative reroll.
	return Navigation.path_clear(physical, {"x":2100.0,"y":200.0}, [{"x":2100.0,"y":float(point.y)}, landing], 90.0) and Navigation.path_clear(physical, {"x":2100.0,"y":2800.0}, [{"x":2100.0,"y":float(point.y)}, landing], 90.0)


static func _templates_valid(value) -> bool:
	if not _keys(value, ["schema", "generatorRevision", "profiles", "layouts", "names", "opportunities"]) or not _plain(value) or value.schema != 1 or value.generatorRevision != REVISION:return false
	if not value.profiles is Dictionary or value.profiles.size() != 5 or not value.layouts is Array or value.layouts.size() != 6 or not value.names is Array or value.names.size() != 46 or not value.opportunities is Array or value.opportunities.size() != 6:return false
	var names: Dictionary = {}
	for name in value.names:
		if not name is String or name.is_empty() or names.has(name):return false
		names[name] = true
	for profile in value.profiles.values():
		if not profile is Array or profile.size() < 3 or profile.size() > 12:return false
		for pair in profile:
			if not pair is Array or pair.size() != 2 or not _number(pair[0]) or not _number(pair[1]) or absf(float(pair[0])) > 1.0 or absf(float(pair[1])) > 1.0:return false
	for layout in value.layouts:
		if not _keys(layout, ["id", "label", "islands"]) or not _strings(layout, ["id", "label"]) or not layout.islands is Array or layout.islands.size() < 2 or layout.islands.size() > 4:return false
		for island in layout.islands:
			if not _keys(island, ["x", "y", "rx", "ry", "profile"]) or not island.profile is String or not value.profiles.has(island.profile):return false
			for key in ["x", "y", "rx", "ry"]:
				if not _number(island[key]) or island[key] <= 0.0:return false
	for opportunity in value.opportunities:
		if not _keys(opportunity, ["industry", "specialty", "resource", "clue", "discovery", "hazard"]) or not _strings(opportunity, ["industry", "specialty", "resource", "clue", "discovery", "hazard"]):return false
		if not Industry.INDUSTRIES.has(opportunity.industry) or opportunity.specialty not in Industry.GOOD_KEYS or opportunity.resource not in Industry.GOOD_KEYS:return false
	return true


static func _number(value) -> bool:
	return (value is int or value is float) and not value is bool and is_finite(float(value))


static func _seed_valid(value) -> bool:
	# JSON numbers must be exact integers before conversion; native int seeds retain
	# all 64 bits. Ordinary campaign seeds fit the exact JSON integer range.
	return value is int or (value is float and is_finite(value) and absf(value) <= 9007199254740991.0 and floorf(value) == value)


static func _keys(value, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():return false
	for key in expected:
		if not value.has(key):return false
	return true


static func _strings(value: Dictionary, fields: Array) -> bool:
	for field in fields:
		if not value.get(field) is String:return false
	return true


static func _plain(value, depth: int = 0) -> bool:
	if depth > 24:return false
	if value == null or value is String or value is bool or _number(value):return true
	if value is Array:
		if value.size() > 4096:return false
		for child in value:
			if not _plain(child, depth + 1):return false
		return true
	if value is Dictionary:
		if value.size() > 4096:return false
		for key in value:
			if not key is String or not _plain(value[key], depth + 1):return false
		return true
	return false


static func _failure(message: String) -> Dictionary:
	return {"ok":false, "code":"sector069", "message":message, "sector":{}, "atlas":{}}


static func _success(sector: Dictionary, atlas: Dictionary, message: String) -> Dictionary:
	# Return detached definitions: the caller owns publication and economy creation.
	return {"ok":true, "code":"ok", "message":message, "sector":sector.duplicate(true), "atlas":atlas.duplicate(true)}
