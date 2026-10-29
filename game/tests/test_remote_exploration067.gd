extends SceneTree
## Root-only native model fixture. Synthetic detached data, no campaign voyage,
## payroll, recovery, geometry or delivery claim. No workers/scenes/engine loops.
const Exploration = preload("res://scripts/exploration.gd")
const WEST := "glasswind_west_marker"
const CROWN := "glasswind_crown_log"
const SOUTH := "glasswind_south_wreck"
var checks: int = 0
var failures: int = 0


func check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		print("FAIL remote_exploration067: ", message)
	return value


func fixture(remote: bool = true) -> Dictionary:
	var state := {"position": {"x": 1360.0, "y": 1380.0}, "path": [],
		"fleet": [{"uid": "model067", "crew": 14, "crewMin": 3, "wounded": 1.0,
			"shoreCrew": 0, "sunk": false, "mothballed": false, "storedPort": "", "supplies": 9.0, "spec": {}}],
		"cargo": {"food": 100.0, "supplies": 20.0}, "surveyFoodCredit": 0.0, "coins": 12345}
	if remote:
		state["world064"] = {"schema": 1, "layer": "local", "regionId": "glasswind_keys"}
	return state


func known(state: Dictionary, id: String) -> Dictionary:
	for dto in Exploration.visible_sites(state):
		if dto["id"] == id:
			return dto
	return {}


func visit(state: Dictionary, id: String) -> Array:
	var site: Dictionary = Exploration.catalog_site(state, id)
	state["position"] = {"x": float(site["x"]), "y": float(site["y"])}
	return Exploration.discover_near(state, state["position"], 1.0)


func kits(state: Dictionary) -> float:
	return float(state["cargo"]["supplies"]) + float(state["fleet"][0]["supplies"])


func begin_party(state: Dictionary, id: String, action: String) -> Dictionary:
	var q: Dictionary = Exploration.begin(state, id, action)
	if check(bool(q.get("ok", false)), id + " " + action + " begins"):
		# Emulate Core's reservation/food credit only; the model does not own them.
		state["fleet"][0]["shoreCrew"] = int(q["crewNeeded"])
		state["surveyFoodCredit"] = float(q["food"])
	return q


func complete(state: Dictionary, id: String, action: String) -> Dictionary:
	var before_food: float = state["cargo"]["food"]
	var before_kits: float = kits(state)
	var q := begin_party(state, id, action)
	if not q.get("ok", false):
		return {}
	check(is_equal_approx(before_food - float(state["cargo"]["food"]), float(q["food"])) and is_equal_approx(before_kits - kits(state), float(q["supplies"])), "Quoted rations/kits debit once at begin")
	check(Exploration.advance(state, float(q["days"]) * 0.5).is_empty(), "Half the quoted work cannot complete")
	var events: Array = Exploration.advance(state, float(q["days"]) * 0.5)
	check(events.size() == 1 and Exploration.assignment(state).is_empty(), "Quoted work completes once and clears assignment")
	state["fleet"][0]["shoreCrew"] = 0
	state["surveyFoodCredit"] = 0.0
	check(Exploration.advance(state, 10.0).is_empty(), "Completed work never repeats its event")
	return events[0] if events.size() == 1 else {}


func reject_preserving(state: Dictionary, label: String) -> void:
	var before := state.duplicate(true)
	check(not Exploration.validate_remote067(state).is_empty(), label + " refuses raw save")
	check(state == before, label + " raw refusal leaves input unchanged")


func _initialize() -> void:
	var started: int = Time.get_ticks_msec()
	test_home_append()
	test_region_and_masking()
	test_chain_and_final_gate()
	test_party_restore_and_refusals()
	test_costs_and_shortages()
	check(Time.get_ticks_msec() - started < 30000, "Entire pure-model body stays below 30 seconds")
	print("remote_exploration067: %d checks, %d failures; model only, %dms" % [checks, failures, Time.get_ticks_msec() - started])
	quit(0 if failures == 0 else 1)


func test_home_append() -> void:
	var state := fixture(false)
	check(Exploration.validate_remote067({}).is_empty(), "Missing legacy exploration/world remains safe")
	var untouched := state.duplicate(true)
	check(Exploration.visible_sites(state).is_empty() and state == untouched, "View is pure even before exploration initialization")
	Exploration.discover_near(state, {"x": 1750.0, "y": 5350.0}, 1.0)
	var q: Dictionary = Exploration.quote(state, "lantern_fresh_cove", "chart")
	check(q["ok"] and q["crewNeeded"] == 2 and float(q["days"]) == 1.0 and float(q["supplies"]) == 1.0 and is_equal_approx(float(q["food"]), 0.16), "Legacy home chart costs remain unchanged")
	Exploration.begin(state, "lantern_fresh_cove", "chart")
	Exploration.advance(state, 0.25)
	# Reconstruct a real pre067 frozen catalog with an active home assignment.
	var old_catalog: Array = []
	for site in state["exploration"]["catalog"]:
		if site.get("regionId", "shatter_coast") == "shatter_coast":
			old_catalog.append(site.duplicate(true))
	state["exploration"]["catalog"] = old_catalog.duplicate(true)
	for id in [WEST, CROWN, SOUTH]:
		state["exploration"]["sites"].erase(id)
	var old_progress: Dictionary = state["exploration"]["sites"].duplicate(true)
	var old_assignment: Dictionary = state["exploration"]["assignment"].duplicate(true)
	check(Exploration.validate_remote067(state).is_empty(), "Raw old home catalog and party remain valid")
	Exploration.ensure(state)
	check(state["exploration"]["version"] == 1 and state["exploration"]["catalog"].slice(0, old_catalog.size()) == old_catalog, "v1 migration preserves every frozen home row")
	check(state["exploration"]["catalog"].size() == old_catalog.size() + 3 and state["exploration"]["assignment"] == old_assignment, "Exactly three new rows append without replacing home work")
	for id in old_progress:
		check(state["exploration"]["sites"][id] == old_progress[id], "Migration preserves earned home progress")
	for id in [WEST, CROWN, SOUTH]:
		check(state["exploration"]["sites"][id] == {"level": 0, "rewarded": false}, "Appended remote site starts unknown")
	var migrated := state.duplicate(true)
	Exploration.ensure(state)
	check(state == migrated, "Catalog append is idempotent")
	var events: Array = Exploration.advance(state, 0.75)
	check(events.size() == 1 and events[0]["leadId"] == "kelp_shoal_cut" and not str(events[0]["discovery"]).is_empty(), "Old home party finishes with its original lead behavior")


func test_region_and_masking() -> void:
	var state := fixture()
	Exploration.ensure(state)
	var before := state.duplicate(true)
	check(Exploration.visible_sites(state).is_empty() and state == before, "Unknown remote sites do not leak or mutate through view")
	var refused: Dictionary = Exploration.quote(state, SOUTH, "survey")
	check(not refused["ok"] and not refused.has("siteName") and not refused.has("resource"), "Unknown remote quote has no name or loot")
	check(Exploration.discover_near(state, {"x": 1750.0, "y": 5350.0}, 1.0).is_empty(), "Remote coordinates never discover home sites")
	var home := fixture(false)
	check(Exploration.discover_near(home, state["position"], 1.0).is_empty(), "Identical home coordinates never discover remote sites")
	var found := visit(state, WEST)
	if not check(found.size() == 1, "Physical remote observation discovers one landing"):
		return
	var dto: Dictionary = found[0]
	var true_name: String = Exploration.catalog_site(state, WEST)["name"]
	check(dto.size() == 8 and dto["name"] != true_name and not dto.has("hazard") and not dto.has("discovery") and not dto.has("resource") and not dto.has("leadId"), "Sighted DTO allows only observed clue and generic name")
	check(not JSON.stringify(state["exploration"]["log"]).contains(true_name), "Sighting log does not reveal the uncharted true name")
	before = state.duplicate(true)
	var view: Array = Exploration.visible_sites(state)
	view[0]["name"] = "changed copy"
	view[0]["level"] = 3
	check(state == before, "Visible DTO edits cannot change catalog or progress")
	var q: Dictionary = Exploration.quote(state, WEST, "chart")
	check(q["siteName"] != true_name and q["hazard"] == "" and q["resource"] == "", "Sighted quote cannot reveal chart/survey knowledge")
	var event := complete(state, WEST, "chart")
	check(event.get("discovery", "") == "" and event.get("resource", "") == "" and event.get("leadId", "") == "" and event.get("lead", {}).is_empty(), "Chart completion cannot expose findings or next-site identity")
	dto = known(state, WEST)
	check(dto.get("name") == true_name and dto.has("hazard") and not dto.has("discovery") and not dto.has("resource"), "Chart earns true name/hazard only")
	for identity in [{"schema": true, "layer": "local", "regionId": "glasswind_keys"}, {"schema": 1, "layer": "home", "regionId": "glasswind_keys"}, {"schema": 1, "layer": "local", "regionId": "glasswind_keys", "extra": 0}]:
		var invalid := state.duplicate(true)
		invalid["world064"] = identity
		check(Exploration.current_region(invalid).is_empty() and Exploration.visible_sites(invalid).is_empty() and Exploration.discover_near(invalid, state["position"], 10.0).is_empty(), "Malformed world grants no regional visibility or sighting")
		reject_preserving(invalid, "Malformed world identity")


func test_chain_and_final_gate() -> void:
	var early := fixture()
	visit(early, SOUTH)
	complete(early, SOUTH, "chart")
	var before := early.duplicate(true)
	check(not Exploration.begin(early, SOUTH, "survey")["ok"] and early == before, "Final survey refuses atomically before both earlier surveys")
	var state := fixture()
	visit(state, WEST)
	complete(state, WEST, "chart")
	var event := complete(state, WEST, "survey")
	check(not str(event.get("discovery", "")).is_empty() and event.get("leadId", "") == "" and event.get("lead", {}).is_empty(), "West survey earns bearing while hiding unknown destination ID")
	check(known(state, CROWN).is_empty() and not known(state, WEST).has("leadId"), "Survey never sights the next site automatically")
	visit(state, CROWN)
	check(known(state, WEST).get("leadId") == CROWN, "A previously earned lead ID appears only once destination is sighted")
	complete(state, CROWN, "chart")
	event = complete(state, CROWN, "survey")
	check(not str(event.get("discovery", "")).is_empty() and event.get("leadId", "") == "" and known(state, SOUTH).is_empty(), "Crown survey earns second bearing without revealing South")
	visit(state, SOUTH)
	complete(state, SOUTH, "chart")
	event = complete(state, SOUTH, "survey")
	check(event.get("resource") == "supplies" and Exploration.visible_sites(state).size() == 3, "Third survey identifies only a finite recovery opportunity")
	check(state["coins"] == 12345 and is_equal_approx(float(state["cargo"]["supplies"]), 11.0) and float(state["cargo"]["food"]) < 100.0 and not state["cargo"].has("engines"), "Whole chain spends nine kits and rations without granting money or salvage")
	check(Exploration.validate_remote067(state).is_empty(), "Completed regional chain is a valid raw save")
	before = state.duplicate(true)
	check(not Exploration.begin(state, SOUTH, "survey")["ok"] and state == before, "Completed remote survey cannot debit or reward again")


func test_party_restore_and_refusals() -> void:
	var state := fixture()
	visit(state, WEST)
	var q := begin_party(state, WEST, "chart")
	if not q.get("ok", false):
		return
	Exploration.advance(state, 0.25)
	check(Exploration.validate_remote067(state).is_empty(), "Matching current-region party/reserved sailors/credit validates")
	var parsed = JSON.parse_string(JSON.stringify(state))
	if not check(parsed is Dictionary, "Party serializes to plain JSON"):
		return
	var loaded: Dictionary = parsed
	check(Exploration.validate_remote067(loaded).is_empty() and Exploration.current_region(loaded) == "glasswind_keys", "JSON schema1.0 matches integer schema1 semantically")
	var events: Array = Exploration.advance(loaded, 0.75)
	check(events.size() == 1 and events[0]["level"] == 2, "Restored remote party finishes exactly its remaining work")
	var party_copy: Dictionary = Exploration.assignment(state)
	party_copy["world064"]["regionId"] = "shatter_coast"
	check(Exploration.assignment(state)["world064"]["regionId"] == "glasswind_keys", "Assignment identity is detached on read")
	for identity in [{"schema": 1, "layer": "home", "regionId": "shatter_coast"}, {"schema": 1, "layer": "ocean", "regionId": "open_ocean"}]:
		var away := state.duplicate(true)
		away["world064"] = identity
		var before := away.duplicate(true)
		check(Exploration.advance(away, 10.0).is_empty() and away == before, "Remote work never progresses from another region/ocean")
		reject_preserving(away, "Remote party in another region")
	var moving := state.duplicate(true)
	moving["path"] = [{"x": 1400.0, "y": 1400.0}]
	var snapshot := moving.duplicate(true)
	check(Exploration.advance(moving, 10.0).is_empty() and moving == snapshot, "Moving fleet cannot advance remote shore work")
	reject_preserving(moving, "Moving remote party")
	var far := state.duplicate(true)
	far["position"]["x"] += 181.0
	snapshot = far.duplicate(true)
	check(Exploration.advance(far, 10.0).is_empty() and far == snapshot, "Remote work remains stopped outside landing radius")
	reject_preserving(far, "Distant remote party")
	var missing := state.duplicate(true)
	missing["exploration"]["assignment"].erase("world064")
	reject_preserving(missing, "Missing remote assignment identity")
	var mismatched := state.duplicate(true)
	mismatched["fleet"][0]["shoreCrew"] = 1
	reject_preserving(mismatched, "Mismatched actual reserved sailors")
	var bad_region := state.duplicate(true)
	var region_site: Dictionary = Exploration.catalog_site(bad_region, WEST)
	region_site["regionId"] = true
	reject_preserving(bad_region, "Malformed optional site region")
	var bad_progress := state.duplicate(true)
	bad_progress["exploration"]["sites"][WEST]["level"] = 1.5
	reject_preserving(bad_progress, "Fractional raw progress before ensure")
	var bad_anchor := state.duplicate(true)
	var anchor_site: Dictionary = Exploration.catalog_site(bad_anchor, WEST)
	anchor_site["x"] += 1.0
	reject_preserving(bad_anchor, "Changed remote catalog anchor")


func test_costs_and_shortages() -> void:
	var state := fixture()
	visit(state, WEST)
	for shortage in ["crew", "food", "kits"]:
		var poor := state.duplicate(true)
		if shortage == "crew":
			poor["fleet"][0]["crew"] = 4
		elif shortage == "food":
			poor["cargo"]["food"] = 0.0
		else:
			poor["cargo"]["supplies"] = 0.0
			poor["fleet"][0]["supplies"] = 0.0
		var before := poor.duplicate(true)
		check(not Exploration.begin(poor, WEST, "chart")["ok"] and poor == before, "Missing " + shortage + " refuses before any work/store debit")
	state["fleet"][0]["shoreCrew"] = 3
	check(Exploration.spare_crew(state) == 7, "Spare hands exclude wounded/minimum/already-reserved sailors")
	state["fleet"][0]["shoreCrew"] = 0
	state["fleet"][0]["spec"]["surveyFactor"] = 2.0
	state["cargo"]["supplies"] = 0.25
	var q: Dictionary = Exploration.quote(state, WEST, "chart")
	check(q["ok"] and float(q["days"]) == 0.5 and is_equal_approx(float(q["food"]), 0.08), "Existing survey modifier applies to time and food")
	Exploration.begin(state, WEST, "chart")
	check(is_equal_approx(float(state["cargo"]["supplies"]), 0.0) and is_equal_approx(float(state["fleet"][0]["supplies"]), 8.25), "Exactly one kit debits cargo first, then working racks")
