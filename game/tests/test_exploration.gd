extends SceneTree
const Exploration = preload("res://scripts/exploration.gd")
const Navigation = preload("res://scripts/navigation.gd")
var failures: Array = []
var checks: int = 0
var world: Dictionary

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL " + message)

func boat(uid: String, crew: int, crew_min: int, extra: Dictionary = {}) -> Dictionary:
	var b := {"uid": uid, "crew": crew, "crewMin": crew_min, "sunk": false, "mothballed": false}
	b.merge(extra, true)
	return b

func fixture() -> Dictionary:
	# Two traveling boats: spare crew = (8-3) + (5-5) = 5.
	return {
		"fleet": [boat("boat-1", 8, 3), boat("boat-2", 5, 5)],
		"cargo": {"food": 20.0, "supplies": 6.0},
		"coins": 5000,
	}

func site_by_id(list: Array, id: String) -> Dictionary:
	for s in list:
		if s is Dictionary and str(s.get("id", "")) == id:
			return s
	return {}

func _initialize() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	_test_catalog_identity_and_water()
	_test_discovery_and_progression()
	_test_requirements_and_consumption()
	_test_repeat_prevention()
	_test_save_roundtrip()
	print("exploration: %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty():
		quit(0)
	else:
		quit(1)

func _test_catalog_identity_and_water() -> void:
	var a := fixture()
	var b := fixture()
	var sites_a: Array = Exploration.sites(a)
	var sites_b: Array = Exploration.sites(b)
	check(sites_a.size() >= 12, "Catalog has at least 12 sites")
	check(sites_a == sites_b, "Catalog identity is deterministic across fresh states")
	var ids := {}
	var regions := {}
	for s in sites_a:
		check(not ids.has(s.id), "Unique site id " + str(s.id))
		ids[s.id] = true
		regions[str(s.region)] = true
		for field in ["id", "name", "x", "y", "kind", "region", "clue", "discovery", "hazard", "resource", "leadId", "level", "levelName"]:
			check(s.has(field), "Site %s has field %s" % [str(s.id), field])
		check(int(s.level) == 0 and str(s.levelName) == "unknown", "Fresh site starts unknown " + str(s.id))
	check(regions.size() >= 6, "Sites span varied island regions")
	# Every site must sit in navigable water (not inside an island polygon).
	var nav: Dictionary = Navigation.create(world.ISLANDS, float(world.WORLD.width), float(world.WORLD.height), 40.0)
	for s in sites_a:
		check(Navigation.is_water(nav, float(s.x), float(s.y), 10.0), "Site in navigable water " + str(s.id))
	# Returned sites are copies: mutating one must not rewrite persistent state.
	sites_a[0]["level"] = 3
	check(int(site_by_id(Exploration.sites(a), str(sites_a[0].id)).level) == 0, "sites() returns copies, not live state")

func _test_discovery_and_progression() -> void:
	var state := fixture()
	var all_sites: Array = Exploration.sites(state)
	var target: Dictionary = site_by_id(all_sites, "lantern_fresh_cove")
	check(not target.is_empty(), "Lantern cove exists")
	var found: Array = Exploration.discover_near(state, {"x": float(target.x), "y": float(target.y)}, 25.0)
	check(found.size() == 1 and int(found[0].level) == 1, "discover_near sights the site at its coordinates")
	check(Exploration.discover_near(state, {"x": float(target.x), "y": float(target.y)}, 25.0).is_empty(), "Repeated discovery reports nothing new")
	check(Exploration.discover_near(state, {"x": -999.0, "y": -999.0}, 10.0).is_empty(), "Far position discovers nothing")
	check(Exploration.discover_near(state, "nowhere", 10.0).is_empty(), "Invalid position is rejected")
	# Chart: sighted -> charted over 1.0 day.
	var q: Dictionary = Exploration.quote(state, "lantern_fresh_cove", "chart")
	check(bool(q.ok) and int(q.crewNeeded) == 2 and is_equal_approx(float(q.days), 1.0), "Chart quote is ready with crew and days")
	check(is_equal_approx(float(q.food), 0.16), "Chart food uses 0.08 per crew-day (2 crew x 1 day)")
	var begun: Dictionary = Exploration.begin(state, "lantern_fresh_cove", "chart")
	check(bool(begun.ok) and not Exploration.assignment(state).is_empty(), "Chart assignment begins")
	check(Exploration.advance(state, 0.5).is_empty(), "Half-day advance does not complete charting")
	check(int(site_by_id(Exploration.sites(state), "lantern_fresh_cove").level) == 1, "Site stays sighted mid-chart")
	var events: Array = Exploration.advance(state, 0.5)
	check(events.size() == 1 and int(events[0].level) == 2, "Charting completes at one full day")
	check(Exploration.assignment(state).is_empty(), "Assignment clears on completion")
	# Survey: charted -> surveyed over 2.5 days, granting lead + rewarded once.
	check(bool(Exploration.begin(state, "lantern_fresh_cove", "survey").ok), "Survey begins after charting")
	events = Exploration.advance(state, 10.0)
	check(events.size() == 1 and int(events[0].level) == 3, "Survey completes to surveyed level")
	var surveyed: Dictionary = site_by_id(Exploration.sites(state), "lantern_fresh_cove")
	check(bool(surveyed.rewarded), "Surveyed site marks its one-time finding granted")
	var leads: Array = state.exploration.leads
	check(leads.any(func(l): return str(l.get("toSite", "")) == "kelp_shoal_cut"), "Survey records the kelp shortcut lead")

func _test_requirements_and_consumption() -> void:
	var state := fixture()
	check(not Exploration_quote_ok(state, "lantern_fresh_cove", "chart"), "Cannot chart an unknown site")
	check(not Exploration_quote_ok(state, "lantern_fresh_cove", "survey"), "Cannot survey before charting")
	check(not Exploration_quote_ok(state, "no_such_site", "chart"), "Unknown site id is rejected")
	check(not Exploration_quote_ok(state, "lantern_fresh_cove", "dig"), "Unknown action is rejected")
	Exploration.discover_near(state, {"x": 1750.0, "y": 5350.0}, 25.0)
	# No spare crew: every sailor is needed to keep the boats running.
	state.fleet = [boat("boat-1", 3, 3), boat("boat-2", 5, 5),
		boat("boat-3", 9, 3, {"mothballed": true}), boat("boat-4", 9, 3, {"storedPort": "brass_haven"}),
		boat("boat-5", 9, 3, {"sunk": true})]
	check(Exploration.spare_crew(state) == 0, "Mothballed, stored and sunk boats give no spare crew")
	check(not Exploration_quote_ok(state, "lantern_fresh_cove", "chart"), "Chart refused without spare crew")
	state.fleet = [boat("boat-1", 8, 3)]
	# Missing supplies and food are refused without consuming anything.
	state.cargo.supplies = 0.0
	check(not Exploration_quote_ok(state, "lantern_fresh_cove", "chart"), "Chart refused without supply kits")
	state.cargo.supplies = 6.0
	state.cargo.food = 0.0
	var before: Dictionary = state.cargo.duplicate(true)
	check(not bool(Exploration.begin(state, "lantern_fresh_cove", "chart").ok), "Begin refused without food")
	check(state.cargo == before, "Refused begin consumes nothing")
	# Successful begin consumes the quote exactly once.
	state.cargo.food = 20.0
	var q: Dictionary = Exploration.quote(state, "lantern_fresh_cove", "chart")
	check(bool(Exploration.begin(state, "lantern_fresh_cove", "chart").ok), "Begin succeeds when stocked")
	check(is_equal_approx(float(state.cargo.food), 20.0 - float(q.food)), "Food consumed once at begin")
	check(is_equal_approx(float(state.cargo.supplies), 6.0 - float(q.supplies)), "Supply kits consumed once at begin")
	check(int(state.coins) == 5000, "Exploration never moves coins")
	# One assignment at a time.
	check(not Exploration_quote_ok(state, "kelp_shoal_cut", "chart"), "Second assignment refused while one runs")
	check(not bool(Exploration.begin(state, "lantern_fresh_cove", "chart").ok), "Same assignment cannot begin twice")

func Exploration_quote_ok(state: Dictionary, id: String, action: String) -> bool:
	return bool(Exploration.quote(state, id, action).ok)

func _test_repeat_prevention() -> void:
	var state := fixture()
	Exploration.discover_near(state, {"x": 1750.0, "y": 5350.0}, 25.0)
	Exploration.begin(state, "lantern_fresh_cove", "chart")
	Exploration.advance(state, 1.0)
	var cargo_after_chart: Dictionary = state.cargo.duplicate(true)
	check(not Exploration_quote_ok(state, "lantern_fresh_cove", "chart"), "Charted site cannot be charted again")
	Exploration.begin(state, "lantern_fresh_cove", "survey")
	Exploration.advance(state, 2.5)
	check(not Exploration_quote_ok(state, "lantern_fresh_cove", "survey"), "Surveyed site cannot be surveyed again")
	check(Exploration.advance(state, 5.0).is_empty(), "No repeat completion events after settling")
	var leads: Array = state.exploration.leads
	var matching := leads.filter(func(l): return str(l.get("fromSite", "")) == "lantern_fresh_cove")
	check(matching.size() == 1, "Lead granted exactly once across chart and survey")
	check(float(state.cargo.food) < float(cargo_after_chart.food), "Survey still consumed its own food once")

func _test_save_roundtrip() -> void:
	var state := fixture()
	Exploration.discover_near(state, {"x": 1750.0, "y": 5350.0}, 25.0)
	Exploration.begin(state, "lantern_fresh_cove", "chart")
	Exploration.advance(state, 0.25)
	var text: String = JSON.stringify(state)
	var restored = JSON.parse_string(text)
	check(restored is Dictionary, "State survives JSON stringify/parse")
	if restored is Dictionary:
		var restored_state: Dictionary = restored
		check(not Exploration.assignment(restored_state).is_empty(), "Mid-chart assignment persists through save")
		var events: Array = Exploration.advance(restored_state, 0.75)
		check(events.size() == 1 and int(events[0].level) == 2, "Restored assignment completes on schedule")
		check(Exploration.sites(restored_state).size() == Exploration.sites(state).size(), "Restored catalog keeps every site")
	# Legacy state without exploration key gains it without touching other fields.
	var legacy := {"fleet": [], "cargo": {"food": 1.0, "supplies": 1.0}, "coins": 42}
	Exploration.ensure(legacy, world)
	check(legacy.has("exploration") and int(legacy.coins) == 42, "ensure() migrates legacy saves in place")
	check(Exploration.spare_crew(legacy) == 0, "Empty fleet has no spare crew")
