extends SceneTree
## Source-only bounded fixture for v0.084 remote harbor warehouse development and storage.
## Root alone executes through Test Bridge. Declared staging never claims earned ocean travel.
## No minted cash, cargo, people, machinery, hulls, item IDs or sovereignty changes.
const Campaign = preload("res://scripts/campaign.gd")
const Money = preload("res://scripts/money.gd")
const Custody = preload("res://scripts/equipment_campaign.gd")
const Territory = preload("res://scripts/territorial076.gd")
const Home = preload("res://scripts/home_harbor.gd")
const HomeUI = preload("res://scripts/home_ui.gd")
const RegionalUI = preload("res://scripts/regional_ui.gd")
const Tools = preload("res://scripts/tooling_ops.gd")
const Workers = preload("res://scripts/economy_workers.gd")
const Politics = preload("res://scripts/politics.gd")
const Remote = preload("res://scripts/remote_expedition067.gd")
const BODY_LIMIT_MS: int = 15000
const SELF_STOP_MS: int = 14000
const EFFICIENCY_GOAL_MS: int = 10000
const SEED: int = 84084
const HOME_PORT: String = "anvil_dock"
const REMOTE_REGION: String = "settled_01"
const REMOTE_PORT: String = "settled_01_harbor_01"
const SIBLING_PORT: String = "settled_01_harbor_02"
var c
var started: int = 0
var checks: int = 0
var failures: int = 0
var expired: bool = false
var complete: bool = false
var failure_labels: Array = []
var events: Array = []
var artifacts: Array = []
var conservation: Dictionary = {}
var workers = Workers.new()
var supply: int = 0
var initial_people: float = 0.0
var casualties: float = 0.0
var seen_contacts: Dictionary = {}
var initial_items: Array = []
var initial_boats: Array = []
var geography: String = ""
var machine_id: String = ""
var home_business_id: String = ""
var remote_business_id: String = ""
var home_completed_receipt: Dictionary = {}
var home_data: Dictionary = {}
var home_nav
var home_context
var home_anchors

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
		check(false, "Stop new work at fourteen seconds with time reserved for body cleanup")
	return false

func note(kind: String, values: Dictionary = {}) -> void:
	var row: Dictionary = {"kind":kind, "elapsed_ms":Time.get_ticks_msec() - started}
	if c != null and not c.state.is_empty(): row["day"] = float(c.state.day)
	row.merge(values, true)
	events.append(row)

func normalized(value) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true)), "", true)

func storage_accounts(state: Dictionary) -> String:
	var ports: Array = []
	for port in state.ports:
		var row: Dictionary = {}
		for key in ["id", "faction", "cash", "householdPurse", "expertPurse", "governmentPurse", "stocks", "publicStores", "population", "workforce", "recruits", "specialists"]:
			row[key] = port.get(key)
		ports.append(row)
	return normalized([ports, state.coins, state.crewPurse, state.wageArrears, state.debt,
		state.cargo, state.businesses, state.businessSeq, state.tooling, state.territorial076,
		state.day, state.econDay, state.world064, state.position, state.sector069, state.islandOwnership069])

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
	for boat in state.get("fleet", []) + state.get("boardingPrizes", []): rows.append(boat)
	for owner in state.get("fleetOwners", []): rows.append_array(owner.get("boats", []))
	return rows

func machinery() -> Dictionary:
	for item in c.state.tooling.items:
		if str(item.id) == machine_id: return item
	return {}

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
	return check(Money.total(c.state) == supply and int(c.state.coinSupply) == supply, "Ordinary payroll and economy publication conserve total coins")

func advance(seconds: float = 4.0) -> bool:
	if not bounded(): return false
	var before: float = float(c.state.day)
	c.step(seconds)
	if not check(float(c.state.day) > before and float(c.state.day) <= before + seconds / c.DAY_SECONDS + 0.000001, "Only the ordinary bounded campaign clock advances work"): return false
	if not settle_days(): return false
	account_contacts()
	for event in c.pop_events():
		if str(event.get("kind", "")) in ["encounter", "ocean_encounter066", "defeat"]:
			note("unexpected_interruption", event)
			return check(false, "An unrelated encounter interrupted this bounded fixture")
	return true

func wait_for_paid(key: String, field: String, days: int) -> bool:
	for _slice in range(26):
		var job: Dictionary = c.state.territorial076[key]
		if int(job.get(field, 0)) >= days: return true
		if not check(str(job.get("status", "")) == "active", "Paid local operation stays admitted: " + str(job.get("reason", ""))): return false
		if not advance(): return false
	return check(false, "Paid local work did not finish within its two-day bounded progression")

func stage_location(layer: String, region_id: String, pos: Dictionary) -> bool:
	var location: Dictionary = c.world_location064()
	location.world064 = {"schema": 1, "layer": layer, "regionId": region_id}
	location.position = {"x": float(pos.x), "y": float(pos.y)}
	location.path = []
	location.destination = ""
	var staged: Dictionary = c.OceanWorld064.prepare_player(location, c.ocean_context064, c.Routes.clearance(c))
	if not check(bool(staged.get("ok", false)), "Declared staging passes ordinary location gate (" + region_id + "): " + str(staged.get("message", ""))): return false
	c._publish_location064(staged.location)
	return true

func trade_at_home(good: String, quantity: int, buy: bool) -> bool:
	if quantity <= 0: return true
	var dock: Dictionary = c.current_port()
	var before: Dictionary = {"coins":int(c.state.coins), "cash":int(dock.cash), "cargo":float(c.state.cargo.get(good, 0)), "stock":float(dock.stocks.get(good, 0))}
	var bill: Dictionary = c.trade(str(dock.id), good, quantity, "buy" if buy else "sell")
	if not check(bool(bill.get("ok", false)), "Actual finite harbor trade (" + good + "): " + str(bill.get("message", ""))): return false
	dock = c.current_port()
	var sign: int = 1 if buy else -1
	check(int(bill.qty) == quantity and int(c.state.coins) == before.coins - sign * int(bill.coins)
		and int(dock.cash) == before.cash + sign * int(bill.coins)
		and is_equal_approx(float(c.state.cargo.get(good, 0)), before.cargo + sign * quantity)
		and is_equal_approx(float(dock.stocks.get(good, 0)), before.stock - sign * quantity), "Trade invoice transfers exact existing cash and goods")
	return check(Money.total(c.state) == supply, "Trade conserves world coin supply")

func prepare_and_home_warehouse() -> bool:
	if not bounded(): return false
	# Dormant NPC fleets avoid unrelated raid interruptions during bounded service checks.
	for owner in c.state.fleetOwners: owner.active = false
	for patrol in c.state.get("patrols", []): patrol.active = false
	var dock0: Dictionary = c.current_port()
	var anvil: Dictionary = c.port(HOME_PORT)
	var spire: Dictionary = c.port("shatter_spire")
	var remote: Dictionary = c.port(REMOTE_PORT)
	var sibling: Dictionary = c.port(SIBLING_PORT)
	if not check(not remote.is_empty() and not sibling.is_empty()
		and str(remote.get("regionId", "")) == REMOTE_REGION and str(sibling.get("regionId", "")) == REMOTE_REGION
		and str(remote.get("faction", "")) != str(sibling.get("faction", ""))
		and Home._generated_harbor084(c.state, REMOTE_PORT) and Home._generated_harbor084(c.state, SIBLING_PORT),
		"Seeded sector069 provides the target generated harbor and a differently owned sibling in the same region"): return false
	# Transfer a finite preparation reserve from existing government treasuries without minting coins,
	# and stage operating cash at REMOTE_PORT from shatter_spire's treasury.
	Money.move(spire, "governmentPurse", remote, "cash", 6000, "Declared084 remote harbor operating reserve", c.state.moneyLog)
	for donor in [dock0, anvil, spire, c.port("cinder_quay")]:
		var avail: int = maxi(0, int(donor.get("governmentPurse", 0)) - 1000)
		if avail > 0:
			Money.move(donor, "governmentPurse", c.state, "coins", avail, "Declared084 finite preparation reserve", c.state.moneyLog)
	if not check(Money.total(c.state) == supply and int(c.state.coins) >= 18000, "Declared treasury transfer conserves world coins and funds both warehouse setups"): return false
	# Stage REMOTE_PORT local workforce/specialists by transferring 48 existing residents (including 8 specialists)
	# from shatter_spire so Home.quote's free_workers/free_experts requirements hold across Economy.tick_ports without minting people.
	if not check(int(spire.availableWorkers) >= 48 and int(spire.availableSpecialists) >= 8 and int(spire.specialists) >= 8,
		"Declared resident transfer uses 48 idle residents including 8 existing available specialists"): return false
	var specialists_before: int = int(spire.specialists) + int(remote.specialists)
	spire.population = int(spire.population) - 48
	spire.workforce = int(spire.workforce) - 48
	spire.availableWorkers = maxi(0, int(spire.availableWorkers) - 48)
	spire.specialists = int(spire.specialists) - 8
	spire.specialistWorkers = int(spire.specialists)
	spire.availableSpecialists = mini(int(spire.specialists), int(spire.availableWorkers))
	spire.recruits = maxi(0, int(spire.recruits) - 8)
	c.Economy.sync_workforce(spire)
	remote.population = int(remote.population) + 48
	remote.workforce = int(remote.workforce) + 48
	remote.availableWorkers = int(remote.availableWorkers) + 48
	remote.specialists = int(remote.get("specialists", 0)) + 8
	remote.specialistWorkers = int(remote.specialists)
	remote.availableSpecialists = mini(int(remote.specialists), int(remote.availableWorkers))
	c.Economy.sync_workforce(remote)
	if not check(people(c.state) == initial_people and int(spire.specialists) + int(remote.specialists) == specialists_before
		and c.ShippingFlow068.sector_error069(c.state).is_empty(),
		"Declared resident/specialist transfer to " + REMOTE_PORT + " conserves world population and passes sector_error069"): return false
	var boat_id: String = str(c.state.fleet[0].uid)
	var recruited: Dictionary = c.recruit_crew(boat_id, 2)
	if not check(bool(recruited.get("ok", false)) and people(c.state) == initial_people, "Two spare sailors join from existing residents: " + str(recruited.get("message", ""))): return false
	# 1. Chart, survey and recover the finite machine_tools at cinder_workshop_ruin first while hold is light.
	var site: Dictionary = c.Exploration.catalog_site(c.state, "cinder_workshop_ruin")
	var spot: Dictionary = c.Navigation.harbor_approach(c.nav, site, c.Routes.clearance(c), 170.0)
	if not check(not spot.is_empty() and stage_location("home", "shatter_coast", spot), "Staged water-safe landing at cinder_workshop_ruin"): return false
	# Location publication does not observe; allow the ordinary 0.5-second discovery tick.
	if not advance(0.5): return false
	if not check(int(c.state.exploration.sites[site.id].level) == c.Exploration.LEVEL_SIGHTED,
		"Ordinary campaign observation sights the landing before charting"): return false
	for action in ["chart", "survey"]:
		var begun: Dictionary = c.begin_survey(str(site.id), action)
		if not check(bool(begun.get("ok", false)), "Actual " + action + " starts: " + str(begun.get("message", ""))): return false
		for _slice in range(42):
			if c.state.exploration.assignment.is_empty(): break
			if not advance(): return false
		if not check(c.state.exploration.assignment.is_empty(), "Actual " + action + " completes"): return false
	var rec_start: Dictionary = Tools.begin(c, str(site.id), "machine_tools")
	if not check(bool(rec_start.get("ok", false)), "Machine tools recovery starts: " + str(rec_start.get("message", ""))): return false
	var rec_job: Dictionary = c.state.toolingRecovery.duplicate(true)
	for _slice in range(25):
		if float(c.state.day) + 0.000001 >= float(rec_job.readyAt) and int(c.state.toolingRecovery.get("paid", 0)) >= int(rec_job.workerDays) * 100: break
		if not advance(): return false
	var claimed: Dictionary = Tools.claim(c)
	if not check(bool(claimed.get("ok", false)), "Machine tools claimed: " + str(claimed.get("message", ""))): return false
	for item in c.state.tooling.items:
		if item.kind == "machine_tools" and item.location == "cargo": machine_id = str(item.id)
	if not check(not machine_id.is_empty(), "Recovered machine_tools is in fleet cargo"): return false
	# 2. Stage at HOME_PORT (anvil_dock), move regional timber/logs/iron/supplies/food stock to anvil_dock,
	# buy the FIRST warehouse material lot within hold capacity, and complete the 076 home warehouse.
	anvil = c.port(HOME_PORT)
	var anvil_berth: Dictionary = c.Navigation.harbor_approach(c.nav, anvil, c.Routes.clearance(c), 40.0)
	if not check(not anvil_berth.is_empty() and stage_location("home", "shatter_coast", anvil_berth), "Staged at HOME_PORT berth"): return false
	for donor_port in c.state.ports:
		if str(donor_port.id) in [HOME_PORT, REMOTE_PORT, SIBLING_PORT]: continue
		for good in ["timber", "logs", "iron", "supplies", "food"]:
			var have: float = float(donor_port.stocks.get(good, 0.0))
			if have >= 2.0 and float(anvil.stocks.get(good, 0.0)) < 24.0:
				var moved: float = minf(have - 1.0, 24.0 - float(anvil.stocks.get(good, 0.0)))
				donor_port.stocks[good] = snappedf(have - moved, 0.01)
				anvil.stocks[good] = snappedf(float(anvil.stocks.get(good, 0.0)) + moved, 0.01)
	var excess_food: int = maxi(0, floori(float(c.state.cargo.get("food", 0.0)) - 6.0))
	if excess_food > 0 and not trade_at_home("food", excess_food, false): return false
	for good in Home.KINDS.warehouse.materials:
		var need_first: int = maxi(0, int(Home.KINDS.warehouse.materials[good]) - floori(float(c.state.cargo.get(good, 0.0))))
		if need_first > 0 and not trade_at_home(str(good), need_first, true): return false
	var need_kits_first: int = maxi(0, 2 - floori(float(c.state.cargo.get("supplies", 0.0))))
	if need_kits_first > 0 and not trade_at_home("supplies", need_kits_first, true): return false
	var home_quote: Dictionary = Territory.quote_improve(c, HOME_PORT)
	if not check(bool(home_quote.get("ok", false)), "Home 076 warehouse quote succeeds: " + str(home_quote.get("message", ""))): return false
	var home_start: Dictionary = Territory.improve(c, HOME_PORT)
	if not check(bool(home_start.get("ok", false)), "Home 076 warehouse improvement starts: " + str(home_start.get("message", ""))): return false
	if not wait_for_paid("improvement", "paidDays", 2): return false
	var home_imp: Dictionary = c.state.territorial076.improvement
	home_business_id = str(home_imp.get("businessId", ""))
	home_completed_receipt = home_imp.duplicate(true)
	if not check(str(home_imp.get("status", "")) == "complete" and not home_business_id.is_empty()
		and Home.business_view(c.state, home_business_id).get("homePort") == HOME_PORT,
		"Completed 076 home warehouse is recorded at " + HOME_PORT): return false
	var home_credits: Array = c.state.moneyLog.filter(func(row): return str(row.get("reason", "")) == "076 supplied construction materials credit")
	if not check(home_credits.size() == 1 and int(home_credits[0].get("cash", -1)) == int(home_imp.setupBill.materialCredit)
		and home_credits[0].get("from") == "cash" and home_credits[0].get("to") == "coins",
		"Home completion records its one exact supplied-material credit before later rolling-log truncation"): return false
	# 3. Now that the first warehouse lot was consumed, buy the SECOND warehouse material lot + restock supplies/food at HOME_PORT.
	for good in Home.KINDS.warehouse.materials:
		var need_second: int = maxi(0, int(Home.KINDS.warehouse.materials[good]) - floori(float(c.state.cargo.get(good, 0.0))))
		if need_second > 0 and not trade_at_home(str(good), need_second, true): return false
	var need_kits_second: int = maxi(0, 2 - floori(float(c.state.cargo.get("supplies", 0.0))))
	if need_kits_second > 0 and not trade_at_home("supplies", need_kits_second, true): return false
	var need_food_second: int = maxi(0, 8 - floori(float(c.state.cargo.get("food", 0.0))))
	if need_food_second > 0 and not trade_at_home("food", need_food_second, true): return false
	note("home_076_warehouse_completed", {"portId":HOME_PORT, "businessId":home_business_id, "receipt":home_completed_receipt})
	return failures == 0

func remote_gate_and_rejections() -> bool:
	if not bounded(): return false
	var remote: Dictionary = c.port(REMOTE_PORT)
	var sibling: Dictionary = c.port(SIBLING_PORT)
	# 1. Reject remote improvement while still in Shatter Coast (other region / home layer).
	var before_home: PackedByteArray = var_to_bytes(c.state)
	var from_home_q: Dictionary = Territory.quote_improve(c, REMOTE_PORT)
	var from_home_i: Dictionary = Territory.improve(c, REMOTE_PORT)
	if not check(not bool(from_home_q.get("ok", true)) and not bool(from_home_i.get("ok", true))
		and var_to_bytes(c.state) == before_home, "Remote improvement is rejected from another region without mutating state"): return false
	# 2. Reject on open_ocean layer.
	var approach0: Dictionary = c.ocean_context064.regions[REMOTE_REGION].approaches[0]
	var ocean_pt: Dictionary = c.OceanWorld064._project(c.ocean_context064, c.ocean_context064.regions[REMOTE_REGION], approach0.position)
	if not stage_location("ocean", "open_ocean", ocean_pt): return false
	var before_ocean: PackedByteArray = var_to_bytes(c.state)
	var ocean_q: Dictionary = Territory.quote_improve(c, REMOTE_PORT)
	var ocean_hq: Dictionary = Home.quote(c, "warehouse", REMOTE_PORT)
	if not check(not bool(ocean_q.get("ok", true)) and not bool(ocean_hq.get("ok", true))
		and var_to_bytes(c.state) == before_ocean, "Remote improvement and warehouse quote are rejected on the ocean layer"): return false
	# 3. Reject at sibling berth (settled_01_harbor_02) in the same local region.
	if not stage_location("local", REMOTE_REGION, {"x": float(sibling.x), "y": float(sibling.y)}): return false
	if not check(str(c.work_port070().get("id", "")) == SIBLING_PORT, "work_port070 resolves the sibling harbor when moored at its berth"): return false
	var before_sibling: PackedByteArray = var_to_bytes(c.state)
	var wrong_berth_q: Dictionary = Territory.quote_improve(c, REMOTE_PORT)
	var wrong_berth_i: Dictionary = Territory.improve(c, REMOTE_PORT)
	var wrong_berth_hq: Dictionary = Home.quote(c, "warehouse", REMOTE_PORT)
	if not check(not bool(wrong_berth_q.get("ok", true)) and not bool(wrong_berth_i.get("ok", true))
		and not bool(wrong_berth_hq.get("ok", true)) and var_to_bytes(c.state) == before_sibling,
		"Sibling harbor berth in the same island group cannot authorize " + REMOTE_PORT): return false
	# 4. Stage at target remote harbor (settled_01_harbor_01) and reject while moving (non-empty path).
	if not stage_location("local", REMOTE_REGION, {"x": float(remote.x), "y": float(remote.y)}): return false
	if not check(str(c.work_port070().get("id", "")) == REMOTE_PORT, "work_port070 resolves " + REMOTE_PORT + " when stationary at its berth"): return false
	var plotted: Dictionary = c.chart_course({"x": float(sibling.x), "y": float(sibling.y)}, SIBLING_PORT)
	if not check(bool(plotted.get("ok", false)) and not c.state.path.is_empty(), "Local water course plots between sibling harbors in " + REMOTE_REGION): return false
	var moving_q: Dictionary = Territory.quote_improve(c, REMOTE_PORT)
	var moving_hq: Dictionary = Home.quote(c, "warehouse", REMOTE_PORT)
	if not check(not bool(moving_q.get("ok", true)) and not bool(moving_hq.get("ok", true)), "Moving fleet path rejects remote improvement and service quotes"): return false
	c.state.path = []; c.state.destination = ""
	# 5. Reject when local harbor access is hostile, even if the sibling harbor has safe conduct.
	var target_faction: String = str(remote.get("faction", "compact"))
	var old_score: int = int(c.Factions.standing(c.state, target_faction).score)
	c.Factions.adjust(c.state, target_faction, -35 - old_score, "DECLARED084 temporary hostile standing check", "declared084-hostile-check")
	c.state.relationships.safeConduct[SIBLING_PORT] = float(c.state.day) + 3.0
	var hostile_access: Dictionary = Politics.access(c, remote)
	var hostile_q: Dictionary = Territory.quote_improve(c, REMOTE_PORT)
	var hostile_hq: Dictionary = Home.quote(c, "warehouse", REMOTE_PORT)
	if not check(not bool(hostile_access.get("legal", true)) and not bool(hostile_q.get("ok", true)) and not bool(hostile_hq.get("ok", true)),
		"Hostile local faction standing blocks " + REMOTE_PORT + " even when sibling " + SIBLING_PORT + " holds safe conduct"): return false
	# Grant port-specific safeConduct at REMOTE_PORT and verify access is admitted, then restore standing.
	c.state.relationships.safeConduct[REMOTE_PORT] = float(c.state.day) + 3.0
	if not check(bool(Politics.access(c, remote).get("legal", false)), "Port-specific safeConduct admits legal service access at " + REMOTE_PORT): return false
	c.state.relationships.safeConduct.erase(SIBLING_PORT)
	c.state.relationships.safeConduct.erase(REMOTE_PORT)
	c.Factions.adjust(c.state, target_faction, old_score - int(c.Factions.standing(c.state, target_faction).score), "DECLARED084 restore opening standing", "declared084-restore-standing")
	# 6. Verify control contest remains home-only until 085, and non-warehouse charters or direct establish bypass fail.
	var t_view: Dictionary = Territory.view(c, REMOTE_PORT)
	var before_ctrl: PackedByteArray = var_to_bytes(c.state)
	var ctrl_refused: Dictionary = Territory.start(c, REMOTE_PORT, str(sibling.get("faction", "reed")))
	var salvage_refused: Dictionary = Home.quote(c, "salvage_yard", REMOTE_PORT)
	var workshop_refused: Dictionary = Home.quote(c, "workshop", REMOTE_PORT)
	var bypass_refused: Dictionary = Home.establish(c, "warehouse", REMOTE_PORT)
	if not check(bool(t_view.get("supported", false)) and not bool(t_view.get("controlSupported", true))
		and not bool(ctrl_refused.get("ok", true)) and not bool(salvage_refused.get("ok", true))
		and not bool(workshop_refused.get("ok", true)) and not bool(bypass_refused.get("ok", true))
		and var_to_bytes(c.state) == before_ctrl,
		"Remote harbor rejects control contests before 085, non-warehouse charters, and direct establish bypass without 2 paid work days"): return false
	note("remote_gate_rejections_verified", {"remotePort":REMOTE_PORT, "siblingPort":SIBLING_PORT, "controlRefused":ctrl_refused.get("message", ""), "bypassRefused":bypass_refused.get("message", "")})
	return failures == 0

func remote_improvement_and_service() -> bool:
	if not bounded(): return false
	var remote: Dictionary = c.port(REMOTE_PORT)
	var sibling: Dictionary = c.port(SIBLING_PORT)
	# Verify UI review models at the remote harbor before starting.
	var before_review: PackedByteArray = var_to_bytes(c.state)
	var reg_review: Dictionary = RegionalUI.review(c, "harbor")
	var home_review: Dictionary = HomeUI.review(c)
	for review in [reg_review, home_review]:
		var public_work: Dictionary = c.work_port070()
		if not check(review.view.current_port().get("id", "") == c.current_port().get("id", "")
			and review.view.work_port070().get("id", "") == public_work.get("id", "")
			and var_to_bytes(c.state) == before_review, "Private UI views retain actual core docking IDs without live account writes"): return false
	if not check(str(reg_review.get("territoryPort", {}).get("id", "")) == REMOTE_PORT
		and bool(reg_review.get("territoryView", {}).get("supported", false))
		and not bool(reg_review.get("territoryView", {}).get("controlSupported", true))
		and bool(reg_review.get("territoryQuote", {}).get("ok", false))
		and bool(home_review.get("isRemotePort084", false))
		and str(home_review.get("port", {}).get("id", "")) == REMOTE_PORT,
		"RegionalUI and HomeUI expose honest remote harbor eligibility and quote state"): return false
	var quote: Dictionary = Territory.quote_improve(c, REMOTE_PORT)
	if not check(bool(quote.get("ok", false)), "Remote warehouse development quote succeeds at " + REMOTE_PORT + ": " + str(quote.get("message", ""))): return false
	var cargo_before: Dictionary = c.state.cargo.duplicate(true)
	var stocks_before: Dictionary = remote.stocks.duplicate(true)
	var cond_before: float = float(machinery().condition)
	var begun: Dictionary = Territory.improve(c, REMOTE_PORT)
	if not check(bool(begun.get("ok", false)), "Remote warehouse development starts: " + str(begun.get("message", ""))): return false
	var imp: Dictionary = c.state.territorial076.improvement
	check(str(imp.get("portId", "")) == REMOTE_PORT and str(imp.get("status", "")) == "active"
		and imp.get("reservedMaterials", {}) == quote.materials
		and imp.get("priorCompleted", {}) == home_completed_receipt
		and Territory.view(c, HOME_PORT).get("improvement", {}) == home_completed_receipt
		and not Home.business_view(c.state, home_business_id).is_empty(),
		"Starting remote development reserves carried materials once and preserves the completed 076 home receipt and business")
	for good in quote.materials:
		check(is_equal_approx(float(c.state.cargo.get(good, 0.0)), float(cargo_before.get(good, 0.0)) - float(quote.materials[good]))
			and is_equal_approx(float(remote.stocks.get(good, 0.0)), float(stocks_before.get(good, 0.0))),
			"Carried " + str(good) + " moves into project reservation without inflating harbor market stock")
	var val_active: String = Territory.validate(c.state, c.data)
	if not check(val_active.is_empty(), "Territorial076.validate accepts active remote improvement and priorCompleted receipt: " + val_active): return false
	# Complete paid day 1, then withdraw, depart, save/restore, return, and resume.
	if not wait_for_paid("improvement", "paidDays", 1): return false
	check(is_equal_approx(float(machinery().condition), cond_before - 0.01), "Paid day 1 wears carried machine_tools by 0.01")
	var active_saved: Dictionary = JSON.parse_string(JSON.stringify(c.state))
	if not check(Remote.party_error(active_saved, c.data).is_empty(), "Actual active 084 book explains the exact healthy reserved sailors at its canonical remote berth"): return false
	for corruption in ["uid", "extra_sailor", "berth", "machine", "date", "survey"]:
		var bad: Dictionary = active_saved.duplicate(true)
		match corruption:
			"uid": bad.territorial076.improvement.crewByBoat = {"forged084":2}
			"extra_sailor": bad.fleet[0].shoreCrew = int(bad.fleet[0].shoreCrew) + 1
			"berth": bad.position = {"x":float(sibling.x), "y":float(sibling.y)}
			"machine": bad.territorial076.improvement.machineryId = "missing084"
			"date": bad.territorial076.improvement.lastPaidDay = int(bad.econDay) + 1
			"survey": bad.exploration.assignment = {"siteId":"forged084", "world064":bad.world064.duplicate(true)}
		if not check(not Remote.party_error(bad, c.data).is_empty(), "084 exception rejects corrupt " + str(corruption) + " without waiving survey/book/berth constraints"): return false
		if corruption == "berth":
			var protected: PackedByteArray = var_to_bytes([c.state, c.events, c.pending_days])
			var refused: Dictionary = c.restore(bad)
			if not check(not bool(refused.get("ok", true)) and var_to_bytes([c.state, c.events, c.pending_days]) == protected,
				"Full restore refuses forged " + str(corruption) + " atomically"): return false
	var active_accounts: String = storage_accounts(active_saved)
	var restored_active: Dictionary = c.restore(active_saved)
	if not check(bool(restored_active.get("ok", false)) and storage_accounts(c.state) == active_accounts,
		"Full active-work restore retains exact project/assigned UIDs, paid day, machinery, cargo, purses and prior home completion: " + str(restored_active.get("message", ""))): return false
	var interrupted: Dictionary = active_saved.duplicate(true)
	interrupted.territorial076.improvement.status = "interrupted"
	if not check(Remote.party_error(interrupted, c.data).is_empty(), "An interrupted original healthy warehouse party remains accounted at the same berth"): return false
	var withdrawn_res: Dictionary = Territory.withdraw(c)
	if not check(bool(withdrawn_res.get("ok", false)) and str(c.state.territorial076.improvement.get("status", "")) == "withdrawn"
		and c.state.territorial076.improvement.get("crewByBoat", {}).is_empty()
		and int(c.state.territorial076.improvement.get("paidDays", 0)) == 1,
		"Withdrawing after day 1 releases the shore crew and retains 1 paid day and reserved materials"): return false
	# Depart to sibling harbor, serialize, validate, and restore through Campaign.restore.
	if not stage_location("local", REMOTE_REGION, {"x": float(sibling.x), "y": float(sibling.y)}): return false
	var saved_mid = JSON.parse_string(JSON.stringify(c.state))
	var mid_accounts: String = storage_accounts(saved_mid)
	var val_mid: String = Territory.validate(saved_mid, c.data)
	if not check(val_mid.is_empty(), "Territorial076.validate accepts withdrawn remote operation on save: " + val_mid): return false
	c.data = home_data; c.nav = home_nav; c.ocean_context064 = home_context; c.ocean_anchors064 = home_anchors
	var restored_mid: Dictionary = c.restore(saved_mid)
	if not check(bool(restored_mid.get("ok", false)), "Campaign.restore succeeds while remote improvement is withdrawn away from berth: " + str(restored_mid.get("message", ""))): return false
	if not check(storage_accounts(c.state) == mid_accounts, "Withdrawn save/restore retains exact port purses, people, project, stores, machinery and prior home accounts"): return false
	check(int(c.state.territorial076.improvement.get("paidDays", 0)) == 1
		and c.state.territorial076.improvement.get("reservedMaterials", {}) == quote.materials
		and c.state.territorial076.improvement.get("priorCompleted", {}) == home_completed_receipt,
		"Restored state retains exact paidDays, reservedMaterials, and priorCompleted home receipt")
	# Return to REMOTE_PORT and resume without double-charging materials.
	remote = c.port(REMOTE_PORT)
	if not stage_location("local", REMOTE_REGION, {"x": float(remote.x), "y": float(remote.y)}): return false
	var cargo_resume: Dictionary = c.state.cargo.duplicate(true)
	var resumed: Dictionary = Territory.improve(c, REMOTE_PORT)
	if not check(bool(resumed.get("ok", false)) and c.state.cargo == cargo_resume and int(c.state.territorial076.improvement.get("paidDays", 0)) == 1,
		"Resuming at " + REMOTE_PORT + " keeps paidDays=1 and debits no second material lot"): return false
	var completion_coins: int = int(c.state.coins)
	var completion_day: int = int(c.state.econDay)
	var payroll_per_day: int = int(c.Economy.daily_upkeep(c.state.fleet).wages)
	if not wait_for_paid("improvement", "paidDays", 2): return false
	var final_imp: Dictionary = c.state.territorial076.improvement
	remote_business_id = str(final_imp.get("businessId", ""))
	var remote_biz: Dictionary = Home.business_view(c.state, remote_business_id)
	if not check(str(final_imp.get("status", "")) == "complete" and final_imp.get("crewByBoat", {}).is_empty()
		and final_imp.get("reservedMaterials", {}).is_empty() and not remote_business_id.is_empty()
		and remote_business_id != home_business_id and remote_biz.get("kind") == "warehouse"
		and remote_biz.get("homePort") == REMOTE_PORT and remote_biz.get("employees", []).size() == 2
		and final_imp.get("priorCompleted", {}) == home_completed_receipt
		and not Home.business_view(c.state, home_business_id).is_empty(),
		"Day 2 completes the remote warehouse at " + REMOTE_PORT + " with 2 local employees while preserving the home 076 warehouse"): return false
	var bill: Dictionary = final_imp.get("setupBill", {})
	var fresh: Dictionary = bill.get("homeQuote", {})
	var payroll_days: int = int(c.state.econDay) - completion_day
	check(int(bill.get("grossCost", -1)) == int(fresh.get("cost", -2))
		and int(bill.get("materialCredit", -1)) == int(fresh.get("materialCost", -2))
		and int(bill.get("netCost", -1)) == int(bill.get("grossCost", 0)) - int(bill.get("materialCredit", 0))
		and int(c.state.coins) == completion_coins - payroll_per_day * payroll_days - int(bill.get("netCost", 0)),
		"Remote completion credits supplied materials once and charges exact net setup cost plus ordinary payroll")
	var credits: Array = c.state.moneyLog.filter(func(row): return str(row.get("reason", "")) == "076 supplied construction materials credit")
	var material_payments: Array = c.state.moneyLog.filter(func(row): return str(row.get("reason", "")) == "Home-harbor setup materials and margin")
	if not check(not credits.is_empty() and int(credits[0].get("cash", -1)) == int(bill.get("materialCredit", -2))
		and credits[0].get("from") == "cash" and credits[0].get("to") == "coins"
		and not material_payments.is_empty() and int(material_payments[0].get("cash", -1)) == int(fresh.materialCost) + int(fresh.margin)
		and material_payments[0].get("from") == "coins" and material_payments[0].get("to") == "cash",
		"Newest actual remote setup debit and supplied-material credit match the fresh bill and real purse directions"): return false
	var completed_accounts: String = storage_accounts(c.state)
	Territory.daily(c)
	var repeated: Dictionary = Territory.improve(c, REMOTE_PORT)
	if not check(not bool(repeated.get("ok", true)) and storage_accounts(c.state) == completed_accounts,
		"Completed remote development cannot repeat setup, material credit, staffing or material consumption"): return false
	note("remote_setup_payment", {"portId":REMOTE_PORT, "bill":bill.duplicate(true), "credit":credits[0].duplicate(true), "materialPayment":material_payments[0].duplicate(true)})
	var food_before_store: float = float(c.state.cargo.get("food", 0.0))
	var stored_in: Dictionary = Home.transfer_goods(c, remote_business_id, "food", 2.0, "in")
	if not check(bool(stored_in.get("ok", false))
		and is_equal_approx(float(c.state.cargo.get("food", 0.0)), food_before_store - 2.0)
		and is_equal_approx(float(Home.business_view(c.state, remote_business_id).get("inventory", {}).get("food", 0.0)), 2.0),
		"Actual owned food enters remote warehouse before departure and save/load"): return false
	# Depart to sibling harbor, advance 1 economic day so remote warehouse pays its workforce while player is away, validate save, then return and use storage/capital.
	sibling = c.port(SIBLING_PORT)
	if not stage_location("local", REMOTE_REGION, {"x": float(sibling.x), "y": float(sibling.y)}): return false
	var away_store: Dictionary = Home.transfer_goods(c, remote_business_id, "food", 1.0, "in")
	check(not bool(away_store.get("ok", true)), "Remote warehouse rejects cargo transfers while docked at a different harbor")
	var day_before_away: int = int(c.state.econDay)
	for _slice in range(14):
		if int(c.state.econDay) > day_before_away: break
		if not advance(): return false
	var biz_after_away: Dictionary = Home.business_view(c.state, remote_business_id)
	check(int(biz_after_away.get("wagesPaid", 0)) >= int(biz_after_away.get("dailyWages", 200))
		and int(biz_after_away.get("paidWorkDays", 0)) >= 1,
		"Remote warehouse pays its local workforce and records paid work days while the player is away")
	var saved_done = JSON.parse_string(JSON.stringify(c.state))
	var val_done: String = Territory.validate(saved_done, c.data)
	var val_sec: Dictionary = c.SectorWorld069.prepare(saved_done, c.data, home_anchors)
	var val_acc: String = c.ShippingFlow068.sector_error069(saved_done)
	if not check(val_done.is_empty() and bool(val_sec.get("ok", false)) and val_acc.is_empty()
		and Home.business_view(saved_done, remote_business_id).get("homePort") == REMOTE_PORT
		and Home.business_view(saved_done, home_business_id).get("homePort") == HOME_PORT,
		"Completed remote warehouse state passes Territorial076, SectorWorld069, and ShippingFlow068 validators: " + val_done + str(val_sec.get("message", "")) + val_acc): return false
	var done_accounts: String = storage_accounts(saved_done)
	var business_error: String = c.SaveValidation.CampaignState.validate(saved_done, c.data)
	if not check(business_error.is_empty(), "Completed remote warehouse passes mandatory business validation: " + business_error): return false
	c.data = home_data; c.nav = home_nav; c.ocean_context064 = home_context; c.ocean_anchors064 = home_anchors
	var restored_done: Dictionary = c.restore(saved_done)
	if not check(bool(restored_done.get("ok", false)), "Full Campaign.restore succeeds with completed remote warehouse: " + str(restored_done.get("message", ""))): return false
	if not check(storage_accounts(c.state) == done_accounts, "Completed save/restore retains exact remote and home business accounts, local purses, staff, stores and ownership"): return false
	# Return to REMOTE_PORT and exercise usable warehouse storage and capital transfer.
	remote = c.port(REMOTE_PORT)
	if not stage_location("local", REMOTE_REGION, {"x": float(remote.x), "y": float(remote.y)}): return false
	var food_before: float = float(c.state.cargo.get("food", 0.0))
	if not check(is_equal_approx(float(Home.business_view(c.state, remote_business_id).get("inventory", {}).get("food", 0.0)), 2.0),
		"Returning after actual restore retains the two owned food lots deposited before departure"): return false
	var loaded_out: Dictionary = Home.transfer_goods(c, remote_business_id, "food", 1.0, "out")
	if not check(bool(loaded_out.get("ok", false))
		and is_equal_approx(float(c.state.cargo.get("food", 0.0)), food_before + 1.0)
		and is_equal_approx(float(Home.business_view(c.state, remote_business_id).get("inventory", {}).get("food", 0.0)), 1.0),
		"Docked at " + REMOTE_PORT + ", player loads 1.0 food back from the remote warehouse"): return false
	var purse_before_cap: int = int(Home.business_view(c.state, remote_business_id).get("coins", 0))
	var captain_before_cap: int = int(c.state.coins)
	var cap_res: Dictionary = Home.capital(c, remote_business_id, 200)
	if not check(bool(cap_res.get("ok", false))
		and int(Home.business_view(c.state, remote_business_id).get("coins", 0)) == purse_before_cap + 200
		and int(c.state.coins) == captain_before_cap - 200,
		"Player adds 200 working capital to the remote warehouse while docked at " + REMOTE_PORT): return false
	note("remote_warehouse_service_verified", {"remoteBusiness":Home.business_view(c.state, remote_business_id), "homeBusiness":Home.business_view(c.state, home_business_id)})
	return failures == 0

func closing_accounts() -> bool:
	var custody: Dictionary = Custody.check_state(c.state, c.data)
	var items: Array = custody.get("itemUids", []).duplicate(); items.sort()
	var boats: Array = []
	for boat in fleet_book(c.state): boats.append(str(boat.uid))
	boats.sort()
	check(Money.total(c.state) == supply and int(c.state.coinSupply) == supply, "All original world coins remain in exact finite purses")
	check(absf(initial_people - people(c.state) - casualties) < 0.000001, "All numerical people reconcile across residents, crews, and both warehouses' staff")
	check(bool(custody.get("ok", false)) and bool(custody.get("ready", false)), "Physical preflight accepts unique hull and equipment custody: " + str(custody.get("message", "")))
	check(items == initial_items and boats == initial_boats, "Exact original hull and equipment UID sets are preserved")
	check(geography == normalized([c.state.sector069, c.state.islandOwnership069]), "Seeded geography, harbor factions, and island ownership are completely unchanged")
	conservation = {"coin_supply_baseline":supply, "coin_supply":Money.total(c.state), "people_baseline":initial_people,
		"people":people(c.state), "actual_casualties":casualties, "boat_uid_count":boats.size(), "boat_uids_sha256":JSON.stringify(boats).sha256_text(),
		"equipment_uid_count":items.size(), "equipment_uids_sha256":JSON.stringify(items).sha256_text(),
		"machine":machinery().duplicate(true), "home_business_id":home_business_id, "remote_business_id":remote_business_id,
		"operation":c.state.territorial076.duplicate(true)}
	return failures == 0

func finish() -> void:
	if workers.group_id >= 0: workers.finish(true)
	if c != null and complete and failures == 0 and not expired:
		var directory: String = OS.get_environment("GAME_TEST_ARTIFACTS")
		if check(directory.is_absolute_path(), "Root supplies the private completed-state directory"):
			var path: String = directory.path_join("development084-completed.json")
			var file = FileAccess.open(path, FileAccess.WRITE)
			if check(file != null, "Actual completed development state opens in Root's artifact directory"):
				# Main.save_game writes this whole-state JSON; Campaign has no save_game method.
				file.store_string(JSON.stringify(c.state, "\t"))
				var write_error: int = file.get_error()
				file.close()
				if check(write_error == OK, "Actual completed development state is written: " + str(write_error)):
					artifacts.append({"kind":"completed_state", "path":path, "sha256":FileAccess.get_sha256(path)})
	workers = null
	c = null
	var elapsed: int = Time.get_ticks_msec() - started
	check(elapsed < BODY_LIMIT_MS, "Bounded fixture completes below fifteen seconds")
	print(JSON.stringify({"fixture":"development084", "checks":checks, "failures":failures,
		"elapsed_ms":elapsed, "efficiency_goal_ms":EFFICIENCY_GOAL_MS, "efficiency_goal_met":elapsed <= EFFICIENCY_GOAL_MS,
		"complete":complete and failures == 0 and not expired,
		"failure_labels":failure_labels, "events":events, "accountfacts":conservation,
		"artifacts":artifacts, "limits":"Source-only bounded fixture for v0.084 remote harbor warehouse development and usable storage. Declared finite treasury reserve, resident/specialist staging, dormant NPC fleets, and staged local berths; no earned ocean crossing, remote sovereignty contest (deferred to 085), or full-game acceptance claimed."}))
	quit(0 if complete and failures == 0 and not expired else 1)

func _run() -> void:
	if not check(DisplayServer.get_name() == "headless", "Root alone runs this native fixture with the private headless backend"): finish(); return
	var definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	if not check(definitions is Dictionary, "Ordinary world definitions decode"): finish(); return
	c = Campaign.new(definitions)
	var opening: Dictionary = c.new_game(SEED)
	if not check(bool(opening.get("ok", false)), "One ordinary finite new_game supplies all opening assets: " + str(opening.get("message", ""))): finish(); return
	home_data = c.data; home_nav = c.nav; home_context = c.ocean_context064; home_anchors = c.ocean_anchors064
	supply = Money.total(c.state); initial_people = people(c.state)
	geography = normalized([c.state.sector069, c.state.islandOwnership069])
	var custody: Dictionary = Custody.check_state(c.state, c.data)
	if not check(bool(custody.get("ok", false)) and bool(custody.get("ready", false)), "Opening hull and physical equipment custody is canonical: " + str(custody.get("message", ""))): finish(); return
	initial_items = custody.itemUids.duplicate(); initial_items.sort()
	for boat in fleet_book(c.state): initial_boats.append(str(boat.uid))
	initial_boats.sort()
	if not prepare_and_home_warehouse(): finish(); return
	if not remote_gate_and_rejections(): finish(); return
	if not remote_improvement_and_service(): finish(); return
	complete = closing_accounts()
	finish()
