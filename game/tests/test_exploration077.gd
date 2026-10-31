extends SceneTree
## Source implementation only. Root applies, reviews and runs through Test Bridge.
## Story scope: declared finite preparation/berths; real surveys, recovery and return.
const Campaign = preload("res://scripts/campaign.gd")
const Money = preload("res://scripts/money.gd")
const Custody = preload("res://scripts/equipment_campaign.gd")
const Workers = preload("res://scripts/economy_workers.gd")
const StoryOps = preload("res://scripts/story_ops.gd")
const Stories = preload("res://scripts/coastal_stories.gd")
const Offers = preload("res://scripts/story_offers.gd")
const SEED: int = 77077
const BODY_LIMIT_MS: int = 55000
const SELF_STOP_MS: int = 53000
const TIDE: String = "inverted_tide077"
const SOUNDINGS: String = "last_soundings077"
const SOURCE: String = "site:glasswind_keys:abandoned_cache067"
const WITNESS_PATH: String = "C:/Users/bligh/Documents/Codex/2026-10-20/how/work/quality-v077/witness-state077.json"
var c
var workers = Workers.new()
var started: int = 0
var checks: int = 0
var failures: int = 0
var expired: bool = false
var complete: bool = false
var failure_labels: Array = []
var events: Array = []
var artifacts: Array = []
var accountfacts: Array = []
var recovery_facts: Dictionary = {}
var supply: int = 0
var initial_people: float = 0.0
var casualties: float = 0.0
var seen_contacts: Dictionary = {}
var initial_items: Array = []
var initial_boats: Array = []
var geography: String = ""
var home_data: Dictionary = {}
var home_nav
var home_context
var home_anchors
var home_world: Dictionary = {}

func _initialize() -> void:
	started = Time.get_ticks_msec()
	_run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		failure_labels.append(label)
	return value

func bounded() -> bool:
	if Time.get_ticks_msec() - started < SELF_STOP_MS: return true
	if not expired:
		expired = true
		check(false, "Stop new work at fifty-three seconds, reserving cleanup time")
	return false

func note(kind: String, values: Dictionary = {}) -> void:
	var row: Dictionary = {"kind":kind, "elapsed_ms":Time.get_ticks_msec() - started}
	if c != null and not c.state.is_empty(): row["day"] = float(c.state.day)
	row.merge(values, true)
	events.append(row)

func normalized(value) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true)), "", true)

func people(state: Dictionary) -> float:
	var total: float = float(state.get("captives", 0))
	for port in state.get("ports", []):
		total += float(port.get("workforce", 0)) + float(port.get("defenses", {}).get("crew", 0))
	for boat in state.get("fleet", []) + state.get("boardingPrizes", []): total += float(boat.get("crew", 0))
	for owner in state.get("fleetOwners", []):
		for boat in owner.get("boats", []): total += float(boat.get("crew", 0))
	for business in state.get("businesses", []): total += business.get("employees", []).size()
	return total

func fleet_book(state: Dictionary) -> Array:
	var rows: Array = []
	rows.append_array(state.get("fleet", []))
	rows.append_array(state.get("boardingPrizes", []))
	for owner in state.get("fleetOwners", []): rows.append_array(owner.get("boats", []))
	return rows

func assets() -> String:
	return normalized([c.state.coins, c.state.crewPurse, c.state.wageArrears, c.state.coinSupply,
		c.state.cargo, c.state.ports, c.state.fleet, c.state.get("boardingPrizes", []),
		c.state.fleetOwners, c.state.businesses, c.state.tooling, c.state.get("wrecks", []),
		c.state.get("captives", 0), c.state.get("captiveBerths", {})])

func account_contacts() -> void:
	for contact in c.state.get("navalAi", {}).get("encounters", []):
		var key: String = "%d:%s:%s" % [int(contact.get("day", 0)), contact.get("a"), contact.get("b")]
		if seen_contacts.has(key): continue
		seen_contacts[key] = true
		casualties += float(contact.get("crewLostA", 0)) + float(contact.get("crewLostB", 0))
		note("ordinary_npc_consequence", contact.duplicate(true))

func settle_days() -> bool:
	while c.pending_days > 0:
		if not bounded(): return false
		c.pending_days -= 1
		workers.start(c.state.ports, 1, c.TradeFlow.blockades(c), int(c.state.seed) + int(c.state.econDay) * 104729)
		var publication: Dictionary = workers.finish(true)
		c.apply_economy(publication.ports, publication.events, publication.days)
		account_contacts()
	return check(Money.total(c.state) == supply and int(c.state.coinSupply) == supply,
		"Ordinary worker publication conserves the original finite coin supply")

func quiet_events() -> bool:
	for event in c.pop_events():
		if str(event.get("kind", "")) in ["encounter", "ocean_encounter066", "defeat"]:
			note("unexpected_interruption", event)
			return check(false, "An unrelated player encounter interrupted this bounded fixture")
	return true

func advance(seconds: float = 4.0) -> bool:
	if not bounded(): return false
	var before: float = float(c.state.day)
	c.step(seconds)
	if not check(float(c.state.day) > before and float(c.state.day) <= before + seconds / c.DAY_SECONDS + 0.000001,
		"Only ordinary bounded Campaign.step advances the clock"): return false
	if not settle_days(): return false
	account_contacts()
	return quiet_events()

func point(label: String) -> Dictionary:
	if not check(c.pending_days == 0 and workers.group_id < 0, label + ": no unpublished economy work"): return {}
	var saved = JSON.parse_string(JSON.stringify(c.state))
	if not check(saved is Dictionary, label + ": ordinary whole-state JSON decodes"): return {}
	return {"state":saved, "casualties":casualties, "seen":seen_contacts.duplicate(true), "label":label}

func restore_point(saved: Dictionary) -> bool:
	if not bounded() or saved.is_empty(): return false
	if not check(c.pending_days == 0 and workers.group_id < 0, "Restore never discards pending or running economy work"): return false
	var input: Dictionary = saved.state.duplicate(true)
	var expected: String = normalized(input)
	c.data = home_data
	c.nav = home_nav
	c.ocean_context064 = home_context
	c.ocean_anchors064 = home_anchors
	var result: Dictionary = c.restore(input)
	if not check(bool(result.get("ok", false)), str(saved.label) + ": ordinary Campaign.restore: " + str(result.get("message", ""))): return false
	if not check(normalized(input) == expected and normalized(c.state) == expected,
		str(saved.label) + ": ordinary restore preserves the complete canonical save and its input"): return false
	casualties = float(saved.casualties)
	seen_contacts = saved.seen.duplicate(true)
	return check(c.pending_days == 0 and workers.group_id < 0, "Restored clock has no unpublished work")

func record(chain_id: String) -> Dictionary:
	return Stories._record(c.state, chain_id)

func query_purity(label: String) -> bool:
	StoryOps.ensure(c)
	c.Contacts.ensure(c.state, c.data)
	var before: PackedByteArray = var_to_bytes([c.state, c.events, c.pending_days])
	for _repeat in range(3):
		Offers.available(c)
		Stories.available(c)
		Stories.earned_leads(c.state, TIDE)
		Stories.earned_leads(c.state, SOUNDINGS)
		Stories._known_site(c.state, "glasswind_keys:abandoned_cache067")
		Stories._site_level(c.state, "glasswind_south_wreck")
	return check(var_to_bytes([c.state, c.events, c.pending_days]) == before,
		label + ": repeated offer, lead and canonical-cache queries are pure")

func refuse(chain_id: String, choice: String, label: String) -> bool:
	var before: PackedByteArray = var_to_bytes([c.state, c.events, c.pending_days])
	var result: Dictionary = StoryOps.choose(c, chain_id, choice)
	note("refused_choice", {"case":label, "choice":choice, "result":result})
	return check(not bool(result.get("ok", true)) and var_to_bytes([c.state, c.events, c.pending_days]) == before,
		label + ": refusal changes no progress, consequences, assets, events or clock")

func decision(chain_id: String, choice: String, flags: Array, expected: Dictionary = {}) -> bool:
	if not bounded(): return false
	var physical: String = assets()
	var scores: Dictionary = {}
	for key in expected:
		if str(key).begins_with("faction:"):
			var faction: String = str(key).trim_prefix("faction:")
			scores[faction] = int(c.Factions.standing(c.state, faction).score)
	var result: Dictionary = StoryOps.choose(c, chain_id, choice)
	if not check(bool(result.get("ok", false)), "Actual story decision " + choice + ": " + str(result.get("message", ""))): return false
	var rec: Dictionary = record(chain_id)
	for flag in flags: check(rec.get("flags", []).count(flag) == 1, "Actual decision records " + str(flag) + " exactly once")
	for flag in rec.get("flags", []): check(rec.flags.count(flag) == 1, "No duplicated story flag: " + str(flag))
	check(c.state.stories.events.count(str(result.eventId)) == 1, "The actual choice has exactly one story event")
	var applied: Dictionary = {}
	var count: int = 0
	for row in c.state.stories.consequences:
		if not str(row.get("id", "")).begins_with(str(result.eventId) + ":"): continue
		count += 1
		var key: String = str(row.kind) + ":" + str(row.target)
		check(not applied.has(key) and bool(row.get("applied", false)), "Each actual consequence is unique and applied")
		applied[key] = int(row.amount)
	check(count == expected.size() and applied == expected, "The actual consequence ledger has the exact named targets and amounts")
	for faction in scores:
		check(int(c.Factions.standing(c.state, faction).score) == int(scores[faction]) + int(expected["faction:" + faction]),
			"The actual " + faction + " standing changes by the catalog amount")
	check(assets() == physical, "The story decision grants no cash, goods, people, hulls or equipment")
	var replay_before: PackedByteArray = var_to_bytes([c.state, c.events, c.pending_days])
	StoryOps.apply_pending(c)
	check(var_to_bytes([c.state, c.events, c.pending_days]) == replay_before, "Reapplying pending consequences is exactly idempotent")
	note("actual_decision", {"chain":chain_id, "choice":choice, "result":result, "record":rec.duplicate(true), "applied":applied})
	return failures == 0

func trade(good: String, quantity: int) -> bool:
	if quantity <= 0: return true
	var dock: Dictionary = c.current_port()
	var before: Dictionary = {"coins":int(c.state.coins), "cash":int(dock.cash),
		"cargo":float(c.state.cargo.get(good, 0)), "stock":float(dock.stocks.get(good, 0))}
	var bill: Dictionary = c.trade(str(dock.id), good, quantity, "buy")
	if not check(bool(bill.get("ok", false)), "Actual finite provision purchase: " + str(bill.get("message", ""))): return false
	dock = c.current_port()
	check(int(bill.qty) == quantity and int(c.state.coins) == int(before.coins) - int(bill.coins)
		and int(dock.cash) == int(before.cash) + int(bill.coins)
		and is_equal_approx(float(c.state.cargo.get(good, 0)), float(before.cargo) + quantity)
		and is_equal_approx(float(dock.stocks.get(good, 0)), float(before.stock) - quantity),
		"The actual invoice transfers exact existing provisions and cash")
	note("ordinary_paid_provisions", {"good":good, "invoice":bill, "portId":str(dock.id)})
	return check(Money.total(c.state) == supply, "Provision purchases never mint coins")

func provision() -> bool:
	for good in ["food", "supplies", "fuel"]:
		var wanted: int = 20 if good == "food" else (12 if good == "supplies" else 6)
		if not trade(good, ceili(maxf(0.0, wanted - float(c.state.cargo.get(good, 0))))): return false
	return true

func sail(target: Dictionary, port_id: String = "") -> bool:
	if not bounded(): return false
	var route: Dictionary = c.chart_course(target, port_id)
	if not check(bool(route.get("ok", false)), "Ordinary course admission: " + str(route.get("message", ""))): return false
	for _slice in range(80):
		if c.state.path.is_empty(): break
		if not advance(): return false
	return check(c.state.path.is_empty(), "The ordinary admitted course finishes within its bounded progression")

func sail_port(port_id: String) -> bool:
	if str(c.current_port().get("id", "")) == port_id: return true
	var target: Dictionary = c.port(port_id)
	if not check(not target.is_empty(), "The actual current-region harbor exists: " + port_id): return false
	if not sail(target, port_id): return false
	return check(str(c.current_port().get("id", "")) == port_id, "Actual physical arrival at " + port_id)

func survey(site_id: String, required: int = 3) -> bool:
	var site: Dictionary = c.Exploration.catalog_site(c.state, site_id)
	if not check(not site.is_empty(), "The actual survey catalog contains " + site_id): return false
	if site_id.begins_with("glasswind_"):
		var known: Dictionary = Stories._known_site(c.state, site_id)
		if not check(str(known.get("regionId", "")) == "glasswind_keys" and known.get("layer") == "local",
			"The remote survey DTO retains its actual region and layer"): return false
	var spot: Dictionary = {"x":site.x,"y":site.y} if site_id.begins_with("glasswind_") else c.Navigation.harbor_approach(c.nav, site, c.Routes.clearance(c), 170.0)
	if not check(not spot.is_empty() and c.distance(spot, site) <= 180.0, "The actual site has a water-safe survey approach"): return false
	var target: Dictionary = site.duplicate(true)
	target.x = spot.x
	target.y = spot.y
	if not sail(target): return false
	var actions: int = 0
	for action in ["chart", "survey"]:
		var level: int = 2 if action == "chart" else 3
		if level > required or Stories._site_level(c.state, site_id) >= level: continue
		var begun: Dictionary = c.begin_survey(site_id, action)
		if not check(bool(begun.get("ok", false)), "Actual " + action + " at " + site_id + ": " + str(begun.get("message", ""))): return false
		actions += 1
		for _slice in range(52):
			if c.state.exploration.assignment.is_empty(): break
			if not advance(): return false
		if not check(c.state.exploration.assignment.is_empty() and Stories._site_level(c.state, site_id) >= level,
			"Ordinary clock, resources and worker publication complete the actual " + action): return false
		note("actual_survey", {"siteId":site_id, "action":action, "result":begun, "level":Stories._site_level(c.state, site_id)})
	return check(actions > 0 and Stories._site_level(c.state, site_id) >= required, "This fixture actually performs the required site work")

func opening_profile() -> bool:
	var boat_id: String = str(c.state.fleet[0].uid)
	var projected: Array = c.state.fleet.duplicate(true)
	projected[0].crew += 2
	var dock0: Dictionary = c.current_port()
	var budget: int = int(c.Economy.daily_upkeep(projected).wages) * 70 + c.Economy.recruit_cost(dock0, 2)
	for row in [["food",20],["supplies",12],["fuel",6]]:
		budget += int(row[1]) * c.Economy.price(dock0,str(row[0]),"buy")
	var funding: int = maxi(0,budget-int(c.state.coins))
	if not check(Money.move(dock0,"governmentPurse",c.state,"coins",funding,"Declared077 finite seventy-day preparation reserve",c.state.moneyLog),"Declared preparation transfers existing treasury coins and records its source"):return false
	# These story scenarios do not measure unrelated concurrent NPC battles.
	for owner in c.state.fleetOwners:owner.active=false
	for patrol in c.state.get("patrols",[]):patrol.active=false
	var crew: float = float(c.find_boat(boat_id).crew)
	var capital: int = int(c.state.coins)
	var purse: int = int(c.state.crewPurse)
	var recruited: Dictionary = c.recruit_crew(boat_id, 2)
	if not check(bool(recruited.get("ok", false)), "Two actual residents join through ordinary recruitment: " + str(recruited.get("message", ""))): return false
	check(float(c.find_boat(boat_id).crew) == crew + 2 and people(c.state) == initial_people
		and int(c.state.coins) == capital - int(recruited.cost) and int(c.state.crewPurse) == purse + int(recruited.cost),
		"Recruitment transfers the original people and their exact paid advance")
	if not provision(): return false
	var physical: String = assets()
	for index in range(6):
		var old: int = int(c.Factions.standing(c.state, "raiders").score)
		if old==20:break
		c.Factions.adjust(c.state, "raiders", mini(25,20-old), "DECLARED077 initial service-access profile; no earned standing claimed", "declared077-raider-access:%d"%index)
	if not check(int(c.Factions.standing(c.state,"raiders").score)==20,"Declared service profile reaches its disclosed standing through bounded normal adjustments"):return false
	var dock: Dictionary = c.port("reed_floats")
	var berth: Dictionary = c.Navigation.harbor_approach(c.nav, dock, c.Routes.clearance(c), 40.0)
	if not check(not berth.is_empty(), "Declared initial HOME berth is water-safe"): return false
	var location: Dictionary = c.world_location064()
	location.position = berth; location.path = []; location.destination = ""
	var prepared: Dictionary = c.OceanWorld064.prepare_player(location, c.ocean_context064, c.Routes.clearance(c))
	if not check(bool(prepared.get("ok", false)), "Declared initial HOME berth passes the ordinary location gate"): return false
	c._publish_location064(prepared.location)
	check(assets() == physical, "Declared standing and initial berth preserve every finite financial and physical asset")
	note("declared_initial_profile", {"raidersStanding":20, "position":berth, "initialFunding":funding,"budget":budget,"reservedWageDays":70,"npcActorsDormant":true,
		"limit":"Finite treasury-funded reserve; actual paid provisions/recruitment. Standing, dormant NPCs and initial Reedwater/Longglass berths are declared inputs; no outbound-voyage, concurrent-raid or starter-profit proof."})
	return query_purity("Canonical opening")

func longglass_passage(outbound: bool) -> bool:
	if outbound:
		var physical: String=assets()
		var location: Dictionary=c.world_location064()
		location.world064={"schema":1,"layer":"local","regionId":"glasswind_keys"}
		location.position={"x":1360.0,"y":1380.0};location.path=[];location.destination=""
		var prepared: Dictionary=c.OceanWorld064.prepare_player(location,c.ocean_context064,c.Routes.clearance(c))
		if not check(prepared.get("ok",false),"Declared initial Longglass berth passes the existing location validator"):return false
		c._publish_location064(prepared.location)
		c.Exploration.discover_near(c.state,c.state.position,1.0)
		StoryOps.ensure(c)
		note("declared_initial_longglass_berth",{"position":c.state.position.duplicate(),"outwardVoyageProven":false})
		return check(assets()==physical and c.Remote067.local(c.state),"Initial Longglass placement changes no actual assets or story work")
	for region in ["glasswind_keys","shatter_coast"]:
		var course: Dictionary=c.approach_course064(region,"south")
		if not check(course.get("ok",false),"Actual return approach course: "+str(course.get("message",""))):return false
		for _slice in range(120):
			if c.state.path.is_empty():break
			if not advance():return false
		if not check(c.state.path.is_empty(),"Actual return course finishes before the bounded limit"):return false
		var crossed: Dictionary=c.transition064(region,"south")
		if not check(crossed.get("ok",false),"Actual return chart crossing: "+str(crossed.get("message",""))):return false
	return check(c.home_local064(),"The actual same fleet returns through open seas to HOME")

func has_offer(id: String) -> bool:
	return Offers.available(c).any(func(offer): return str(offer.get("id", "")) == id)

func inverted_tide() -> bool:
	var begun: Dictionary = StoryOps.start(c, TIDE)
	if not check(bool(begun.get("ok", false)), "Wren actually starts the Inverted Tide lead at Reedwater"): return false
	if not refuse(TIDE, "copy_salt_staff077", "An uncharted salt staff is not earned progress"): return false
	if not survey("verdigris_salt_pans", 2): return false
	if not decision(TIDE, "copy_salt_staff077", ["read_salt_staff077"]): return false
	if not survey("reed_marsh_landing"): return false
	if not decision(TIDE, "match_marsh_scales077", ["matched_marsh_scales077"]): return false
	if not refuse(TIDE, "publish_tide_book077", "The register requires the actual named harbor"): return false
	if not sail_port("reed_floats"): return false
	var predecision: Dictionary = point("tide-predecision")
	if predecision.is_empty(): return false
	if not decision(TIDE, "publish_tide_book077", ["tide_public077"],
		{"faction:reed":4, "faction:compact":-2, "contact:contact_sister_wren":6}): return false
	if not check(bool(record(TIDE).done) and not record(TIDE).flags.has("tide_bonded077")
		and has_offer("chainfreight-tide-public077") and not has_offer("chainfreight-tide-bonded077"),
		"The public decision unlocks only its actual finite freight offer"): return false
	if not refuse(TIDE, "bond_tide_book077", "The completed public decision cannot also become bonded"): return false
	var offer: Dictionary = {}
	for row in Offers.available(c):
		if str(row.id) == "chainfreight-tide-public077": offer = row.duplicate(true)
	if not check(not offer.is_empty() and str(offer.freight.good) == "supplies" and int(offer.freight.qty) == 4,
		"The new public freight is exactly four real supplies"): return false
	var dock: Dictionary = c.current_port()
	var before: Dictionary = {"cargo":float(c.state.cargo.supplies), "stock":float(dock.stocks.supplies),
		"cash":int(dock.cash), "government":int(dock.governmentPurse), "coins":int(c.state.coins)}
	var accepted: Dictionary = c.accept_voyage_job(str(offer.id))
	if not check(bool(accepted.get("ok", false)), "Ordinary VoyageJob acceptance funds and loads the actual freight"): return false
	var job: Dictionary = c.VoyageJobs._find(c.state, str(offer.id))
	check(int(job.get("escrow", -1)) == int(offer.reward) and int(c.state.coins) == int(before.coins)
		and int(dock.cash) == int(before.cash) + int(offer.materialInvoice)
		and int(dock.governmentPurse) == int(before.government) - int(offer.reward) - int(offer.materialInvoice)
		and is_equal_approx(float(dock.stocks.supplies), float(before.stock) - 4)
		and is_equal_approx(float(c.state.cargo.supplies), float(before.cargo))
		and job.freight.good=="supplies" and is_equal_approx(float(job.freight.qty),4.0),
		"Existing treasury buys four existing kits and escrows the exact actual reward")
	if not sail_port("silt_hollow"): return false
	dock = c.current_port()
	var stock: float = float(dock.stocks.supplies)
	var cargo: float = float(c.state.cargo.supplies)
	var coins: int = int(c.state.coins)
	var invoice: Dictionary = c.settle_voyage_job(str(offer.id))
	if not check(bool(invoice.get("ok", false)), "Ordinary VoyageJob settlement delivers the actual four supplies"): return false
	check(is_equal_approx(float(c.state.cargo.supplies), cargo)
		and is_equal_approx(float(dock.stocks.supplies), stock + 4)
		and int(c.state.coins) == coins + int(invoice.get("reward", 0))
		and int(invoice.get("reward", -1)) == int(offer.reward) and Money.total(c.state) == supply,
		"Actual settlement transfers the freight and existing escrow exactly once")
	var protected: PackedByteArray = var_to_bytes([c.state, c.events, c.pending_days])
	var repeated: Dictionary = c.settle_voyage_job(str(offer.id))
	check(not bool(repeated.get("ok", true)) and var_to_bytes([c.state, c.events, c.pending_days]) == protected,
		"Repeated freight settlement gives no second delivery or reward")
	check(c.state.storyRights.usedOffers.has(str(offer.id)), "The actual issued freight remains permanently recorded as used")
	note("actual_tide_freight", {"offer":offer, "acceptance":accepted, "settlement":invoice})
	var public_end: Dictionary = point("actual-public-freight-complete")
	if not restore_point(predecision): return false
	if not decision(TIDE, "bond_tide_book077", ["tide_bonded077"],
		{"faction:compact":4, "faction:reed":-2, "contact:contact_tobin_hale":6, "contact:contact_sister_wren":-3}): return false
	check(not record(TIDE).flags.has("tide_public077") and not has_offer("chainfreight-tide-public077"),
		"The alternate bonded decision excludes the public register and its offer")
	if not sail_port("brass_haven"): return false
	if not check(has_offer("chainfreight-tide-bonded077") and not has_offer("chainfreight-tide-public077"),
		"The alternate save unlocks only its actual Brass-to-Silt bonded offer"): return false
	if not query_purity("Bonded alternate"): return false
	if not closing_accounts("bonded_alternate"): return false
	return restore_point(public_end)

func source_wreck() -> Dictionary:
	for wreck in c.state.get("wrecks", []):
		if str(wreck.get("sourceId", "")) == SOURCE: return wreck
	return {}

func source_totals(wreck: Dictionary) -> Dictionary:
	var totals: Dictionary = {}
	for good in ["engines", "copper", "supplies", "timber"]:
		totals[good] = float(wreck.get("components", {}).get(good, 0)) + float(wreck.get("stores", {}).get(good, 0))
	return totals

func paid_recovery() -> bool:
	var wreck: Dictionary = source_wreck()
	if not check(not wreck.is_empty() and c.distance(wreck, {"x":1820.0, "y":1640.0}) <= 0.001,
		"The actual canonical south survey resolves the existing Longglass cache and its real wreck ID"): return false
	var known: Dictionary = Stories._known_site(c.state, "glasswind_keys:abandoned_cache067")
	if not check(int(known.get("level", 0)) >= 3, "The real south survey establishes the canonical cache knowledge; no fake fourth survey"): return false
	if not refuse(SOUNDINGS, "take_paid_to_wren077", "Surveying alone is no paid recovery receipt"): return false
	if not refuse(SOUNDINGS, "record_empty_to_wren077", "A stocked source cannot honestly be recorded empty"): return false
	var before: Dictionary = source_totals(wreck)
	for good in {"engines":1, "copper":8, "supplies":12, "timber":16}:
		check(float(before[good]) >= 0 and float(before[good]) <= float({"engines":1, "copper":8, "supplies":12, "timber":16}[good]),
			"The actual finite cache never exceeds its original " + good + " stock")
	if not check(float(before.copper) >= 1, "The positive primary path has one real copper unit available"): return false
	var purse: Dictionary = {"coins":int(c.state.coins), "crew":int(c.state.crewPurse),
		"copper":float(c.state.cargo.get("copper", 0)), "kits":float(c.state.cargo.supplies), "food":float(c.state.cargo.food)}
	var receipt: Dictionary = c.recover_wreck(str(wreck.id), "strip", "copper", 1)
	if not check(bool(receipt.get("ok", false)) and bool(receipt.get("completed", false))
		and float(receipt.get("quantity", 0)) > 0, "The actual synchronous recovery returns a completed positive receipt"): return false
	var after: Dictionary = source_totals(source_wreck())
	check(is_equal_approx(float(receipt.quantity), 1.0) and is_equal_approx(float(after.copper), float(before.copper) - 1)
		and is_equal_approx(float(c.state.cargo.get("copper", 0)), float(purse.copper) + 1),
		"One actual copper unit moves from the original source into player cargo")
	for good in ["engines", "supplies", "timber"]: check(after[good] == before[good], "Recovery does not refill or consume unrelated source " + good)
	check(float(receipt.get("elapsedDays", 0)) > 0 and int(receipt.get("wagesPaid", 0)) > 0
		and float(receipt.get("kitsConsumed", 0)) > 0 and float(receipt.get("foodConsumed", 0)) > 0,
		"The actual positive receipt records elapsed work, real wages, kits and food")
	check(int(c.state.coins) <= int(purse.coins) - int(receipt.wagesPaid)
		and int(c.state.crewPurse) >= int(purse.crew) + int(receipt.wagesPaid)
		and float(c.state.cargo.supplies) <= float(purse.kits) - float(receipt.kitsConsumed) + 0.000001
		and float(c.state.cargo.food) <= float(purse.food) - float(receipt.foodConsumed) + 0.000001,
		"The actual paid recovery debits its real operating resources and transfers wages")
	if not settle_days() or not quiet_events(): return false
	check(record(SOUNDINGS).flags.count("paid_longglass077") == 1 and not record(SOUNDINGS).flags.has("empty_longglass077"),
		"Only Campaign's real successful-recovery hook records the paid flag exactly once")
	recovery_facts = {"wreckId":str(wreck.id), "sourceId":SOURCE, "before":before, "after":after, "receipt":receipt}
	note("actual_synchronous_recovery", recovery_facts)
	return query_purity("Paid canonical cache")

func write_paid_witness() -> bool:
	if not bounded(): return false
	if not check(bool(record(TIDE).get("done", false)) and str(record(SOUNDINGS).get("stage", "")) == "marked_recovery"
		and not bool(record(SOUNDINGS).get("done", false)) and record(SOUNDINGS).flags.count("paid_longglass077") == 1,
		"The canonical witness is the actual first-story-done, paid Longglass pre-choice state"): return false
	if not check(c.pending_days == 0 and workers.group_id < 0 and WITNESS_PATH.is_absolute_path(),
		"The actual witness has joined workers and the exact absolute requested path"): return false
	var serialized: String = JSON.stringify(c.state, "\t")
	var decoded = JSON.parse_string(serialized)
	if not check(decoded is Dictionary and normalized(decoded) == normalized(c.state), "Full actual canonical c.state JSON round-trips"): return false
	var file = FileAccess.open(WITNESS_PATH, FileAccess.WRITE)
	if not check(file != null, "The requested canonical pre-choice witness opens"): return false
	file.store_string(serialized)
	var error: int = file.get_error()
	file.close()
	if not check(error == OK, "The complete actual pre-choice witness is written"): return false
	var digest: String = FileAccess.get_sha256(WITNESS_PATH)
	if not check(digest.length() == 64, "The retained actual witness has its real SHA256"): return false
	artifacts.append({"kind":"witness", "path":WITNESS_PATH, "sha256":digest})
	note("canonical_paid_prechoice_witness", {"path":WITNESS_PATH, "sha256":digest, "injectedProgress":false})
	return true

func turn_in(paid: Dictionary, cass: bool) -> Dictionary:
	if not restore_point(paid): return {}
	var route_choice: String = "take_paid_to_cass077" if cass else "take_paid_to_wren077"
	var route_flag: String = "soundings_to_cass077" if cass else "soundings_to_wren077"
	var registration: String = "register_cass_soundings077" if cass else "register_public_soundings077"
	var port_id: String = "rust_anchorage" if cass else "reed_floats"
	if not decision(SOUNDINGS, route_choice, [route_flag, "paid_longglass077"]): return {}
	if not refuse(SOUNDINGS, registration, "Actual turn-in is refused before reaching " + port_id): return {}
	if not sail_port(port_id): return {}
	var permission: Dictionary = c.Politics.permit(c, "service")
	if not check(bool(permission.get("ok", false)), "Ordinary service permission exists before the actual turn-in reward"): return {}
	var expected: Dictionary = {"faction:raiders":4, "faction:reed":-3, "contact:contact_cass_rye":6} if cass else {"faction:reed":4, "faction:raiders":-3, "contact:contact_sister_wren":6}
	var final_flag: String = "soundings_cass077" if cass else "soundings_public077"
	if not decision(SOUNDINGS, registration, [final_flag, route_flag, "paid_longglass077"], expected): return {}
	if not check(bool(record(SOUNDINGS).done) and not record(SOUNDINGS).flags.has("empty_longglass077")
		and not record(SOUNDINGS).flags.has("soundings_public077" if cass else "soundings_cass077"),
		"The actual permitted paid turn-in finishes only its selected register"): return {}
	if not refuse(SOUNDINGS, registration, "A finished register cannot award its consequences twice"): return {}
	if not query_purity("Completed paid register") or not closing_accounts("paid_cass" if cass else "paid_wren"): return {}
	return point("completed-paid-cass" if cass else "completed-paid-wren")

func legacy_cases(cache_ready: Dictionary) -> bool:
	if not restore_point(cache_ready): return false
	var missing: Dictionary = point("DECLARED legacy missing-source negative input")
	missing.state.wrecks = missing.state.wrecks.filter(func(wreck): return str(wreck.get("sourceId", "")) != SOURCE)
	if not restore_point(missing): return false
	if not check(source_wreck().is_empty(), "The declared missing-source input remains absent; no cache is synthesized"): return false
	if not refuse(SOUNDINGS, "record_empty_to_wren077", "A missing actual source does not establish exhaustion"): return false
	if not restore_point(cache_ready): return false
	var empty: Dictionary = point("DECLARED externally depleted legacy input")
	var removed: Dictionary = {}
	for wreck in empty.state.wrecks:
		if str(wreck.get("sourceId", "")) != SOURCE: continue
		removed = source_totals(wreck)
		for key in ["components", "stores"]:
			for good in wreck.get(key, {}): wreck[key][good] = 0
		wreck.status="stripped"
	if not check(not removed.is_empty() and not record(SOUNDINGS).flags.has("paid_longglass077"),
		"The separate depleted legacy input begins before any player-paid claim"): return false
	if not restore_point(empty): return false
	if not query_purity("Declared depleted legacy source"): return false
	if not check(source_totals(source_wreck()) == {"engines":0.0, "copper":0.0, "supplies":0.0, "timber":0.0},
		"Ordinary restore and queries never refill the declared depleted source"): return false
	if not decision(SOUNDINGS, "record_empty_to_wren077", ["empty_longglass077", "soundings_to_wren077"]): return false
	check(not record(SOUNDINGS).flags.has("paid_longglass077") and not bool(record(SOUNDINGS).done),
		"Honest exhaustion creates neither a player-paid receipt nor a completed harbor turn-in")
	note("declared_legacy_exhaustion", {"externallyRemovedBeforeInput":removed, "playerPaidClaim":false,
		"refilled":false, "record":record(SOUNDINGS).duplicate(true)})
	return closing_accounts("declared_legacy_exhaustion")

func closing_accounts(branch: String) -> bool:
	account_contacts()
	var custody: Dictionary = Custody.check_state(c.state, c.data)
	var items: Array = custody.get("itemUids", []).duplicate()
	items.sort()
	var boats: Array = []
	for boat in fleet_book(c.state): boats.append(str(boat.uid))
	boats.sort()
	check(Money.total(c.state) == supply and int(c.state.coinSupply) == supply, branch + ": original finite world coins reconcile")
	check(absf(initial_people - people(c.state) - casualties) < 0.000001, branch + ": original people reconcile with actual NPC casualties")
	check(bool(custody.get("ok", false)) and bool(custody.get("ready", false)), branch + ": actual equipment custody is canonical")
	check(items == initial_items and boats == initial_boats, branch + ": original hull and equipment UID sets remain exact")
	check(geography == normalized([c.state.sector069, c.state.islandOwnership069]), branch + ": seeded geography and island ownership remain unchanged")
	accountfacts.append({"branch":branch, "coin_supply_baseline":supply, "coin_supply":Money.total(c.state),
		"people_baseline":initial_people, "people":people(c.state), "actual_casualties":casualties,
		"boat_uid_count":boats.size(), "boat_uids_sha256":JSON.stringify(boats).sha256_text(),
		"equipment_uid_count":items.size(), "equipment_uids_sha256":JSON.stringify(items).sha256_text(),
		"cargo":c.state.cargo.duplicate(true), "holders":custody.get("holders", []),
		"tide":record(TIDE).duplicate(true), "soundings":record(SOUNDINGS).duplicate(true)})
	return failures == 0

func finish() -> void:
	if workers.group_id >= 0: workers.finish(true)
	workers = null
	c = null
	var elapsed: int = Time.get_ticks_msec() - started
	check(elapsed < BODY_LIMIT_MS, "Body includes initialization, restores, proof and owned cleanup below fifty-five seconds")
	print(JSON.stringify({"fixture":"exploration077", "checks":checks, "failures":failures,
		"elapsed_ms":elapsed, "complete":complete and failures == 0 and not expired,
		"failure_labels":failure_labels, "events":events, "accountfacts":accountfacts,
		"recovery":recovery_facts, "artifacts":artifacts,
		"limits":"Declared finite treasury-funded seventy-day reserve, initial Reedwater/Longglass berths, Raiders20 service and dormant unrelated NPC profile; no earned outbound voyage, concurrent-raid, starter-profit, rendering, listening or whole-game-quality claim. No minted funding or primary progress injection. Separate externally depleted legacy input claims no player-paid work. Canonical witness is retained through cleanup."}))
	quit(0 if complete and failures == 0 and not expired else 1)

func _run() -> void:
	if not check(DisplayServer.get_name() == "headless", "Root alone runs the private headless fixture"): finish(); return
	var definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	if not check(definitions is Dictionary, "Ordinary world definitions decode"): finish(); return
	c = Campaign.new(definitions)
	var opening: Dictionary = c.new_game(SEED)
	if not check(bool(opening.get("ok", false)), "One ordinary finite new_game initializes this sole Campaign"): finish(); return
	home_data = c.data
	home_nav = c.nav
	home_context = c.ocean_context064
	home_anchors = c.ocean_anchors064
	home_world = c.state.world064.duplicate(true)
	supply = Money.total(c.state)
	initial_people = people(c.state)
	geography = normalized([c.state.sector069, c.state.islandOwnership069])
	var custody: Dictionary = Custody.check_state(c.state, c.data)
	if not check(bool(custody.get("ok", false)) and bool(custody.get("ready", false)), "Original finite equipment custody is canonical"): finish(); return
	initial_items = custody.itemUids.duplicate()
	initial_items.sort()
	for boat in fleet_book(c.state): initial_boats.append(str(boat.uid))
	initial_boats.sort()
	if not opening_profile() or not inverted_tide(): finish(); return
	if not sail_port("brass_haven") or not provision(): finish(); return
	var begun: Dictionary = StoryOps.start(c, SOUNDINGS)
	if not check(bool(begun.get("ok", false)), "Tobin actually starts Last Soundings at HOME Brass"): finish(); return
	if not longglass_passage(true): finish(); return
	for row in [["glasswind_west_marker", "record_west_marker077", "west_soundings077"],
		["glasswind_crown_log", "record_crown_log077", "crown_soundings077"],
		["glasswind_south_wreck", "record_south_wreck077", "south_soundings077"]]:
		if not survey(str(row[0])) or not decision(SOUNDINGS, str(row[1]), [str(row[2])]): finish(); return
	var cache_ready: Dictionary = point("actual-three-surveys-before-player-recovery")
	if cache_ready.is_empty() or not paid_recovery(): finish(); return
	var protected: PackedByteArray = var_to_bytes([c.state, c.events, c.pending_days])
	var unknown: Dictionary = c.recover_wreck("fixture077:missing-source", "strip", "copper", 1)
	if not check(not bool(unknown.get("ok", true)) and var_to_bytes([c.state, c.events, c.pending_days]) == protected,
		"Unknown-source synchronous recovery refuses without progress, receipt or resource changes"): finish(); return
	if not longglass_passage(false) or not sail_port("brass_haven"): finish(); return
	var paid: Dictionary = point("same-actual-paid-Longglass-prechoice")
	if paid.is_empty() or not write_paid_witness(): finish(); return
	if not restore_point(paid): finish(); return
	var wren: Dictionary = turn_in(paid, false)
	if wren.is_empty() or not restore_point(wren): finish(); return
	var cass: Dictionary = turn_in(paid, true)
	if cass.is_empty() or not restore_point(cass): finish(); return
	if not legacy_cases(cache_ready) or not restore_point(cass): finish(); return
	complete = closing_accounts("final-restored-actual-paid-cass")
	finish()
