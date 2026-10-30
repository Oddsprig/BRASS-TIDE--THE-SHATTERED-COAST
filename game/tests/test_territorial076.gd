extends SceneTree
## Source-only bounded fixture; Root alone executes through Test Bridge.
## One ordinary finite opening. Declared staging never claims earned travel.
## No minted cash, cargo, people, machinery, hulls, item IDs or battle results.
const Campaign = preload("res://scripts/campaign.gd")
const Money = preload("res://scripts/money.gd")
const Custody = preload("res://scripts/equipment_campaign.gd")
const Territory = preload("res://scripts/territorial076.gd")
const Home = preload("res://scripts/home_harbor.gd")
const Tools = preload("res://scripts/tooling_ops.gd")
const Workers = preload("res://scripts/economy_workers.gd")
const Battle = preload("res://scripts/battle.gd")
const Coast = preload("res://scripts/coastal_terrain.gd")
const BODY_LIMIT_MS: int = 55000
const SELF_STOP_MS: int = 53000
const EFFICIENCY_GOAL_MS: int = 20000
const SEED: int = 76076
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
var improvement_port: String = "anvil_dock"
var survey_job: String = ""
var control_port: String = "rust_anchorage"
var declared_politics: Dictionary = {}

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
		check(false, "Stop new work at fifty-three seconds with time reserved for body cleanup")
	return false

func note(kind: String, values: Dictionary = {}) -> void:
	var row: Dictionary = {"kind":kind, "elapsed_ms":Time.get_ticks_msec() - started}
	if c != null and not c.state.is_empty(): row["day"] = float(c.state.day)
	row.merge(values, true)
	events.append(row)

func normalized(value) -> String:
	# Main.save_game uses ordinary JSON number precision.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true)), "", true)

func people(state: Dictionary) -> float:
	# Recruits, specialists, boarders, wounds and shoreCrew are subsets, not extras.
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

func account_contacts() -> void:
	for contact in c.state.get("navalAi", {}).get("encounters", []):
		# NavalCombat records whole econDay; JSON may restore its int as a float.
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
	return check(Money.total(c.state) == supply and int(c.state.coinSupply) == supply, "Ordinary payroll and economy publication conserve the original total coins")

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
			return check(false, "An unrelated encounter interrupted this bounded operation; it is not a pass")
	return true

func trade(good: String, quantity: int, buy: bool) -> bool:
	var dock: Dictionary = c.current_port()
	var before: Dictionary = {"coins":int(c.state.coins), "cash":int(dock.cash), "cargo":float(c.state.cargo.get(good, 0)), "stock":float(dock.stocks.get(good, 0))}
	var bill: Dictionary = c.trade(str(dock.id), good, quantity, "buy" if buy else "sell")
	if not check(bool(bill.get("ok", false)), "Actual finite harbor transaction: " + str(bill.get("message", ""))): return false
	dock = c.current_port()
	var sign: int = 1 if buy else -1
	check(int(bill.qty) == quantity and int(c.state.coins) == before.coins - sign * int(bill.coins)
		and int(dock.cash) == before.cash + sign * int(bill.coins)
		and is_equal_approx(float(c.state.cargo[good]), before.cargo + sign * quantity)
		and is_equal_approx(float(dock.stocks[good]), before.stock - sign * quantity), "The actual invoice transfers exact existing cash and goods")
	note("paid_purchase" if buy else "ordinary_opening_sale", {"portId":str(dock.id), "good":good, "invoice":bill})
	return failures == 0

func sail_to(port_id: String) -> bool:
	var target: Dictionary = c.port(port_id)
	var route: Dictionary = c.chart_course({"x":target.x, "y":target.y}, port_id)
	if not check(bool(route.get("ok", false)), "A normal loaded course is admitted to " + port_id + ": " + str(route.get("message", ""))): return false
	for _slice in range(24):
		if c.state.path.is_empty(): break
		if not advance(): return false
	return check(str(c.current_port().get("id", "")) == port_id, "The actual loaded course arrives at " + port_id)

func prepare_and_recover() -> bool:
	var boat_id: String = str(c.state.fleet[0].uid)
	var before_crew: float = float(c.find_boat(boat_id).crew)
	var before_purse: int = int(c.state.crewPurse)
	var before_coins: int = int(c.state.coins)
	var recruited: Dictionary = c.recruit_crew(boat_id, 2)
	if not check(bool(recruited.get("ok", false)), "Two survey hands are normally recruited from actual opening residents: " + str(recruited.get("message", ""))): return false
	check(float(c.find_boat(boat_id).crew) == before_crew + 2 and int(c.state.crewPurse) - before_purse == int(recruited.cost)
		and before_coins - int(c.state.coins) == int(recruited.cost) and people(c.state) == initial_people, "Recruitment transfers people and their real wage advance without minting either")
	# Retain twelve opening food lots for survey/recovery; paid work funds restocking.
	if not trade("food", 18, false): return false
	for good in Home.KINDS.warehouse.materials:
		if not trade(str(good), int(Home.KINDS.warehouse.materials[good]), true): return false
	# Initial chart/survey/recovery kits; later work is restocked after actual payment.
	if not trade("supplies", 3, true): return false
	# The required survey itself earns normal finite payment, with no extra jobs.
	for offer in c.VoyageJobs.available(c):
		if offer.get("kind") == "survey" and offer.get("siteId") == "cinder_workshop_ruin": survey_job = str(offer.id); break
	if not check(not survey_job.is_empty(), "One actual opening Cinder survey offer funds the already-required work"): return false
	var accepted: Dictionary = c.accept_voyage_job(survey_job)
	if not check(bool(accepted.get("ok", false)), "The actual survey sponsor escrows finite payment through ordinary acceptance: " + str(accepted.get("message", ""))): return false
	note("ordinary_paid_survey_accepted", {"job":c.VoyageJobs._find(c.state, survey_job).duplicate(true)})
	var site: Dictionary = c.Exploration.catalog_site(c.state, "cinder_workshop_ruin")
	var spot: Dictionary = c.Navigation.harbor_approach(c.nav, site, c.Routes.clearance(c), 170.0)
	if not check(not spot.is_empty() and c.distance(spot, site) <= 180.0, "The declared source opening has a real water-safe landing"): return false
	var location: Dictionary = c.world_location064()
	location.position = spot; location.path = []; location.destination = ""
	var staged: Dictionary = c.OceanWorld064.prepare_player(location, c.ocean_context064, c.Routes.clearance(c))
	if not check(bool(staged.get("ok", false)), "Only the declared initial location passes the ordinary chart location gate: " + str(staged.get("message", ""))): return false
	c._publish_location064(staged.location)
	note("declared_initial_staging", {"position":spot, "sourceId":site.id, "roster":c.state.fleet.map(func(b): return {"uid":b.uid, "crew":b.crew}), "limit":"Single initial player placement after ordinary paid recruitment/purchases. No earned Brass-to-Cinder voyage; NPCs and every existing asset retain their actual finite opening."})
	if not advance(0.01): return false
	for action in ["chart", "survey"]:
		var begun: Dictionary = c.begin_survey(str(site.id), action)
		if not check(bool(begun.get("ok", false)), "Actual " + action + " reserves existing sailors and consumes ordinary supplies: " + str(begun.get("message", ""))): return false
		var done: bool = false
		for _slice in range(42):
			if c.state.exploration.assignment.is_empty(): done = true; break
			if not advance(): return false
		if not check(done, "Actual " + action + " completes within its small bounded progression"): return false
	if not check(int(c.state.exploration.sites[site.id].level) == 3, "The actual source was charted and surveyed; no progress flags were assigned"): return false
	var recovered: Dictionary = Tools.begin(c, str(site.id), "machine_tools")
	if not check(bool(recovered.get("ok", false)), "The surveyed finite source admits its real two-sailor paid recovery: " + str(recovered.get("message", ""))): return false
	var job: Dictionary = c.state.toolingRecovery.duplicate(true)
	for _slice in range(25):
		if float(c.state.day) + 0.000001 >= float(job.readyAt) and int(c.state.toolingRecovery.get("paid", 0)) >= int(job.workerDays) * 100: break
		if not advance(): return false
	var claimed: Dictionary = Tools.claim(c)
	if not check(bool(claimed.get("ok", false)), "Actual work days and ordinary once-paid wages permit the finite machinery claim: " + str(claimed.get("message", ""))): return false
	for item in c.state.tooling.items:
		if item.kind == "machine_tools" and item.location == "cargo": machine_id = str(item.id)
	if not check(not machine_id.is_empty() and c.state.tooling.extracted.has("site:cinder_workshop_ruin"), "Recovered machinery keeps its finite source and actual identifier"): return false
	note("actual_machine_recovery", {"job":job, "items":c.state.tooling.items.duplicate(true), "coin_supply":Money.total(c.state)})
	if not sail_to("brass_haven"): return false
	var before_payment: int = int(c.state.coins)
	var invoice: Dictionary = c.settle_voyage_job(survey_job)
	if not check(bool(invoice.get("ok", false)), "Actual surveyed source work reports back normally for its escrowed pay: " + str(invoice.get("message", ""))): return false
	check(int(c.state.coins) - before_payment == int(invoice.get("reward", 0)) and Money.total(c.state) == supply, "The actual completed survey fee is an exact existing escrow transfer")
	note("ordinary_paid_survey_settled", {"jobId":survey_job, "invoice":invoice, "limit":"Actual chart/survey/recovery and physical return; the explicitly staged initial outbound placement is not earned travel."})
	# Recovery used the opening kits. Buy only the remaining ordinary work/support
	# needs here, after the actual job paid and before physically carrying them on.
	var payroll: Dictionary = c.Economy.daily_upkeep(c.state.fleet)
	var kit_need: float = Territory.WORK_DAYS * (0.5 + float(Territory.SUPPORT_GOODS.supplies))
	# Four paid operation days plus at most one additional Anvil passage payroll day.
	var ration_need: float = float(payroll.food) * (2 * Territory.WORK_DAYS + 1) \
		+ float(Territory.SUPPORT_GOODS.food) * Territory.WORK_DAYS
	var before_restock: Dictionary = {"coins":int(c.state.coins), "food":float(c.state.cargo.food), "supplies":float(c.state.cargo.supplies)}
	var restock: Dictionary = {"supplies":ceili(maxf(0.0, kit_need - before_restock.supplies)), "food":ceili(maxf(0.0, ration_need - before_restock.food))}
	for good in restock:
		if int(restock[good]) > 0 and not trade(str(good), int(restock[good]), true): return false
	if not check(Money.total(c.state) == supply and int(c.state.coinSupply) == supply
		and float(c.state.cargo.supplies) >= kit_need and float(c.state.cargo.food) >= ration_need,
		"Paid restocking retains exact world coins and carries the remaining real kits, ordinary rations and civilian support food"): return false
	note("ordinary_paid_operation_restock", {"before":before_restock, "required":{"supplies":kit_need, "food":ration_need}, "bought":restock,
		"after":{"coins":int(c.state.coins), "food":float(c.state.cargo.food), "supplies":float(c.state.cargo.supplies)},
		"payrollFoodPerDay":float(payroll.food), "limit":"Two warehouse days and two support days; one additional passage payroll day provisioned. Every shortfall uses actual harbor stock and the exact paid trade invoice."})
	return sail_to(improvement_port)

func machinery() -> Dictionary:
	for item in c.state.tooling.items:
		if str(item.id) == machine_id: return item
	return {}

func local_resources() -> Dictionary:
	# Detached facts at the public boundary; no forecast or resource adjustment.
	var dock: Dictionary = c.current_port()
	var labor: Dictionary = {}
	for key in ["workforce", "availableWorkers", "_yardWorkersUsed", "recruits", "specialists", "specialistWorkers", "availableSpecialists", "_yardSpecialistsUsed", "labor"]:
		labor[key] = dock.get(key)
	var crew: Array = []
	for boat in c.state.fleet:
		crew.append({"uid":str(boat.uid), "crew":boat.crew, "wounded":boat.get("wounded", 0), "crewMin":boat.crewMin, "crewMax":boat.crewMax, "shoreCrew":boat.get("shoreCrew", 0)})
	return {"coins":int(c.state.coins), "crewPurse":int(c.state.crewPurse), "wageArrears":int(c.state.wageArrears),
		"cargo":c.state.cargo.duplicate(true), "portId":str(dock.get("id", "")), "stocks":dock.get("stocks", {}).duplicate(true),
		"harborPurses":{"cash":dock.get("cash"), "householdPurse":dock.get("householdPurse"), "expertPurse":dock.get("expertPurse"), "governmentPurse":dock.get("governmentPurse")},
		"labor":labor.duplicate(true), "fleetCrew":crew, "operation":c.state.territorial076.duplicate(true), "machine":machinery().duplicate(true)}

func unreserved_assets() -> PackedByteArray:
	# Only the actual payer, destination, cargo and physical player hulls can be
	# touched by recall/resume. Avoid copying the complete 48-group atlas here.
	var saved: Dictionary = {"coins":c.state.coins, "crewPurse":c.state.crewPurse, "wageArrears":c.state.wageArrears,
		"cargo":c.state.cargo, "cargoManifest":c.state.cargoManifest, "tooling":c.state.tooling,
		"businesses":c.state.businesses, "port":c.current_port(), "fleet":c.state.fleet,
		"materials":c.state.territorial076.improvement.get("materials", {}),
		"reservedMaterials":c.state.territorial076.improvement.get("reservedMaterials", {}),
		"setupBill":c.state.territorial076.improvement.get("setupBill", {})}.duplicate(true)
	for boat in saved.fleet: boat.erase("shoreCrew")
	return var_to_bytes(saved)

func wait_for_paid(key: String, field: String, days: int) -> bool:
	for _slice in range(26):
		var job: Dictionary = c.state.territorial076[key]
		if int(job.get(field, 0)) >= days: return true
		if not check(str(job.get("status", "")) == "active", "Paid local operation stays admitted: " + str(job.get("reason", ""))): return false
		if not advance(): return false
	return check(false, "Paid local work did not finish within its two-day bounded progression")

func funded_improvement() -> bool:
	if not bounded(): return false
	var untouched: PackedByteArray = var_to_bytes(c.state)
	var quote: Dictionary = Territory.quote_improve(c, improvement_port)
	check(var_to_bytes(c.state) == untouched, "The actual funded improvement quote leaves every asset and purse untouched")
	note("actual_improvement_quote", {"quote":quote, "resources":local_resources()})
	if not check(bool(quote.get("ok", false)), "Actual carried goods, recovered machinery, spare sailors and remaining payroll admit the berth quote: " + str(quote.get("message", ""))): return false
	var cargo: Dictionary = c.state.cargo.duplicate(true)
	var stocks: Dictionary = c.port(improvement_port).stocks.duplicate(true)
	var capital: int = int(c.state.coins)
	var condition: float = float(machinery().condition)
	var begun: Dictionary = Territory.improve(c, improvement_port)
	if not check(bool(begun.get("ok", false)), "Actual funded berth work starts at its real destination: " + str(begun.get("message", ""))): return false
	var held: Dictionary = c.state.territorial076.improvement.get("reservedMaterials", {})
	check(held.size() == quote.materials.size() and int(c.state.coins) == capital,
		"Admission reserves only the actual construction bill and grants no cash or premature material credit")
	for good in quote.materials:
		check(is_equal_approx(float(c.state.cargo[good]), float(cargo[good]) - float(quote.materials[good]))
			and is_equal_approx(float(held.get(good, -1)), float(quote.materials[good]))
			and is_equal_approx(float(c.port(improvement_port).stocks[good]), float(stocks[good])), "Carried " + str(good) + " moves exactly once into the project reservation while public harbor stock stays unchanged")
	var validation: String = Territory.validate(c.state, c.data)
	if not check(validation.is_empty(), "Ordinary validation accepts the actual unfinished project's held goods: " + validation): return false
	note("funded_improvement_started", {"quote":quote, "operation":c.state.territorial076.improvement.duplicate(true), "machine":machinery().duplicate(true), "manifest":c.state.cargoManifest.duplicate(true)})
	if not wait_for_paid("improvement", "paidDays", 1): return false
	var progress: Dictionary = c.state.territorial076.improvement.duplicate(true)
	var actual_assets: PackedByteArray = unreserved_assets()
	var recalled: Dictionary = Territory.withdraw(c)
	note("actual_improvement_withdraw_result", {"result":recalled, "resources":local_resources()})
	if not check(bool(recalled.get("ok", false)), "The actual partially paid improvement can be interrupted by withdrawal: " + str(recalled.get("message", ""))): return false
	var withdrawn: Dictionary = c.state.territorial076.improvement
	check(str(withdrawn.status) == "withdrawn" and withdrawn.crewByBoat.is_empty() and int(withdrawn.paidDays) == 1
		and unreserved_assets() == actual_assets, "Withdrawal recalls only the original crew reservation; all cash, people, cargo, held construction goods, hulls and physical equipment remain exact")
	validation = Territory.validate(c.state, c.data)
	if not check(validation.is_empty(), "Ordinary validation accepts the withdrawn project's retained held goods and paid progress: " + validation): return false
	check(is_equal_approx(float(machinery().condition), condition - 0.01), "The first real paid work day retains its actual machinery wear after interruption")
	note("actual_withdrawal", {"before":progress, "after":withdrawn.duplicate(true), "assets_unchanged":unreserved_assets() == actual_assets, "machine":machinery().duplicate(true)})
	var resume_assets: PackedByteArray = unreserved_assets()
	var resume_quote: Dictionary = Territory.quote_improve(c, improvement_port)
	var resumed: Dictionary = Territory.improve(c, improvement_port)
	note("actual_improvement_resume_result", {"quote":resume_quote, "result":resumed, "resources":local_resources()})
	if not check(bool(resumed.get("ok", false)), "The same paid improvement resumes with its retained actual resources: " + str(resumed.get("message", ""))): return false
	check(int(c.state.territorial076.improvement.paidDays) == 1 and unreserved_assets() == resume_assets, "Resume retains paid progress and the exact held bill without another cargo debit or cash transfer")
	var completion_coins: int = int(c.state.coins)
	var completion_cash: int = int(c.port(improvement_port).cash)
	var completion_day: int = int(c.state.econDay)
	var payroll: int = int(c.Economy.daily_upkeep(c.state.fleet).wages)
	if not wait_for_paid("improvement", "paidDays", 2): return false
	var final: Dictionary = c.state.territorial076.improvement
	var business: Dictionary = Home.business_view(c.state, str(final.businessId))
	if not check(str(final.status) == "complete" and final.crewByBoat.is_empty() and business.get("kind") == "warehouse"
		and business.get("homePort") == improvement_port and business.get("employees", []).size() == 2
		and final.get("reservedMaterials", {}).is_empty(), "Two actual paid days finish one ordinary warehouse with two real resident employees and no unconsumed held construction goods"): return false
	validation = Territory.validate(c.state, c.data)
	if not check(validation.is_empty(), "Ordinary validation accepts the consumed held bill and fresh gross/material-credit/net setup receipt: " + validation): return false
	var bill: Dictionary = final.setupBill
	var fresh: Dictionary = bill.homeQuote
	var priced: int = 0
	for good in fresh.materials:
		priced += ceili(float(fresh.materials[good]) * float(fresh.get("materialPrices", {}).get(good, -1)))
	check(int(bill.grossCost) == int(fresh.cost) and int(bill.materialCredit) == int(fresh.materialCost)
		and int(bill.materialCredit) == priced and int(bill.netCost) == int(bill.grossCost) - priced,
		"The completion receipt uses its actual fresh material prices and exactly one gross-minus-supplied-material credit")
	var credits: Array = c.state.moneyLog.filter(func(row): return str(row.get("reason", "")) == "076 supplied construction materials credit")
	var material_payments: Array = c.state.moneyLog.filter(func(row): return str(row.get("reason", "")) == "Home-harbor setup materials and margin")
	check(credits.size() == 1 and int(credits[0].get("cash", -1)) == priced and credits[0].get("from") == "cash" and credits[0].get("to") == "coins"
		and material_payments.size() == 1 and int(material_payments[0].get("cash", -1)) == priced + int(fresh.margin)
		and material_payments[0].get("from") == "coins" and material_payments[0].get("to") == "cash",
		"The actual harbor receives the normal material-and-margin payment and returns the supplied material value to the captain exactly once")
	var payroll_days: int = int(c.state.econDay) - completion_day
	check(int(c.state.coins) == completion_coins - payroll * payroll_days - int(bill.netCost),
		"The actual captain purse pays ordinary payroll and the net setup bill without a second construction-material charge")
	note("actual_supplied_materials_settlement", {"portId":improvement_port, "setupBill":bill.duplicate(true), "captain_before":completion_coins,
		"captain_after":int(c.state.coins), "payroll_days":payroll_days, "payroll_per_day":payroll,
		"harbor_cash_before":completion_cash, "harbor_cash_after":int(c.port(improvement_port).cash),
		"material_payments":material_payments.duplicate(true), "credits":credits.duplicate(true), "held_after":final.reservedMaterials.duplicate(true)})
	var completed_assets: PackedByteArray = unreserved_assets()
	Territory.daily(c)
	var repeated: Dictionary = Territory.improve(c, improvement_port)
	check(not bool(repeated.get("ok", false)) and str(final.status) == "complete" and unreserved_assets() == completed_assets,
		"The consumed project cannot charge, credit or consume its construction goods a second time: " + str(repeated.get("message", "")))
	check(str(final.machineryId) == machine_id and str(machinery().location) == "cargo"
		and is_equal_approx(float(machinery().condition), condition - 0.02), "The same physically carried machinery remains aboard with exactly two work days of wear")
	check(int(business.get("capitalIn", 0)) == 14 * 2 * 100 + 500, "The warehouse holds its actual fourteen-day staff wage reserve and finite input capital")
	note("funded_improvement_complete", {"operation":final.duplicate(true), "business":business, "machine":machinery().duplicate(true), "coin_supply":Money.total(c.state), "people":people(c.state), "casualties":casualties})
	return failures == 0

func assets(state: Dictionary) -> Dictionary:
	# Compact custody projection used only at the actual transfer/restore boundary.
	var ports: Array = []
	for port in state.ports:
		var row: Dictionary = {}
		for key in ["id", "cash", "householdPurse", "expertPurse", "governmentPurse", "stocks", "publicStores", "workforce", "recruits", "specialists", "shipStock", "buildQueue", "training"]: row[key] = port.get(key)
		var defense: Dictionary = port.get("defenses", {})
		row["defense_assets"] = {}
		for key in ["kind", "units", "crew", "ammo", "supplies", "arrears"]: row.defense_assets[key] = defense.get(key)
		ports.append(row)
	var boats: Array = []
	for boat in fleet_book(state):
		var row: Dictionary = {}
		for key in ["uid", "type", "crew", "wounded", "hp", "water", "fire", "sunk", "fuel", "ammo", "supplies", "boarders", "shoreCrew", "storedPort", "moduleCondition", "equipmentRetiredTo", "refitLocker", "loadout"]: row[key] = boat.get(key)
		boats.append(row)
	var purses: Array = []
	for owner in state.fleetOwners:
		purses.append({"id":owner.id, "homePort":owner.homePort, "coins":owner.coins, "crewPurse":owner.crewPurse, "wageArrears":owner.wageArrears, "cargo":owner.cargo, "tradeCargo":owner.get("tradeCargo"), "boatUids":owner.boats.map(func(b): return str(b.uid))})
	return {"coins":state.coins, "crewPurse":state.crewPurse, "wageArrears":state.wageArrears, "coinSupply":state.coinSupply,
		"cargo":state.cargo, "ports":ports, "boats":boats, "owners":purses,
		"businesses":state.businesses, "tooling":state.tooling, "captives":state.get("captives", 0),
		"wrecks":state.get("wrecks", []), "captiveBerths":state.get("captiveBerths", {}),
		"materials":state.get("territorial076", {}).get("improvement", {}).get("materials", {}),
		"reservedMaterials":state.get("territorial076", {}).get("improvement", {}).get("reservedMaterials", {}),
		"setupBill":state.get("territorial076", {}).get("improvement", {}).get("setupBill", {})}

func control_opening() -> bool:
	if not bounded(): return false
	var physical_before: String = normalized(assets(c.state))
	var before: Dictionary = c.state.relationships.factions.duplicate(true)
	var old_score: int = int(c.Factions.standing(c.state, "forge").score)
	c.Factions.adjust(c.state, "forge", 20 - old_score, "DECLARED076 control opening; no earned standing or completed jobs claimed", "declared076-control-opening")
	var target: Dictionary = c.port(control_port)
	var dock: Dictionary = c.Navigation.harbor_approach(c.nav, target, c.Routes.clearance(c), 40.0)
	if not check(not dock.is_empty(), "The separate control opening uses an actual water-safe harbor berth"): return false
	var moved: Array = []
	# Existing first blockade detachment has exactly the ordinary one-hull roster.
	# Only its initial berth changes. No combat value, purse, store or UID changes.
	var defender: Dictionary = c.fleet_owner("story-0")
	if not check(not defender.is_empty() and defender.boats.size() == 1 and bool(defender.active), "The declared defender is one actual existing finite blockade boat"): return false
	for owner in c.state.fleetOwners:
		if owner.get("faction") != target.faction or str(owner.id) == "story-0" or c.NavalAI.NavalOrders.enrolled066(c.state, str(owner.id)): continue
		var patrol: Dictionary = c.NavalAI._find_patrol(c.state, str(owner.id))
		if str(owner.get("atPort", "")) != control_port and (patrol.is_empty() or c.distance(patrol, target) > 350.0): continue
		var old: Dictionary = {"ownerId":str(owner.id), "atPort":str(owner.get("atPort", "")), "position":{"x":patrol.get("x"), "y":patrol.get("y")}}
		owner.atPort = "shatter_spire"
		if not patrol.is_empty():
			var other: Dictionary = c.Navigation.harbor_approach(c.nav, c.port("shatter_spire"), c.Routes.clearance(c, patrol), 40.0)
			if not check(not other.is_empty(), "Other declared initial defenders retain valid existing harbor poses"): return false
			patrol.x = other.x; patrol.y = other.y
		old["newAtPort"] = "shatter_spire"; moved.append(old)
	moved.append({"ownerId":"story-0", "atPort":str(defender.atPort), "newAtPort":control_port})
	defender.atPort = control_port
	# Separate synthetic one-blockade case, after all live funded progression.
	# Existing inactive-owner semantics retain the complete finite fleet in reserve.
	# Only these two activity flags change; offshore owners are never touched.
	var activity: Array = []
	var active_hostiles: int = 0
	for owner in c.state.fleetOwners:
		var owner_id: String = str(owner.id)
		var enrolled: bool = c.NavalAI.NavalOrders.enrolled066(c.state, owner_id)
		var hostile: bool = c.Politics.hostile(c, owner)
		var patrol: Dictionary = c.NavalAI._find_patrol(c.state, owner_id)
		var prior: Dictionary = {"ownerActive":bool(owner.active), "patrolActive":patrol.get("active")}
		var dormant: bool = hostile and not enrolled and owner_id != str(defender.id)
		if dormant:
			owner.active = false
			if not patrol.is_empty(): patrol.active = false
		if hostile and not enrolled and bool(owner.active): active_hostiles += 1
		activity.append({"ownerId":owner_id, "currentlyHostile":hostile, "oceanEnrolled":enrolled, "declaredDormant":dormant,
			"before":prior, "after":{"ownerActive":bool(owner.active), "patrolActive":patrol.get("active")}})
	note("declared_control_activity", {"selectedDefenderId":str(defender.id), "owners":activity, "limit":"Opening activity flags only; NO concurrent-raid coverage in this separate one-blockade case."})
	if not check(bool(defender.active) and active_hostiles == 1, "The declared control case retains exactly its one selected active coastal hostile defender"): return false
	var location: Dictionary = c.world_location064()
	location.position = dock; location.path = []; location.destination = ""
	var staged: Dictionary = c.OceanWorld064.prepare_player(location, c.ocean_context064, c.Routes.clearance(c))
	if not check(bool(staged.get("ok", false)), "Declared control opening passes the ordinary player-location gate: " + str(staged.get("message", ""))): return false
	c._publish_location064(staged.location)
	declared_politics = {"sponsor":"forge", "before":before, "after":c.state.relationships.factions.duplicate(true), "poses":moved, "playerPosition":dock, "activity":activity,
		"limit":"SEPARATE CONTROL CASE: Root-authorized declared Friendly20, initial berths and one active selected coastal defender. Other currently hostile non-ocean-enrolled owners and matching patrols start inactive in existing reserve semantics; all their actual assets and homeports remain. Ocean-enrolled and nonhostile activity is unchanged. NO concurrent-raid coverage. Standing is unearned; no supporting jobs/history are invented. Earlier actual paid survey/warehouse progression retains all live NPC activity and events. No earned voyage, victory, damage or resource endowment; no subsequent reputation, pose or activity override."}
	check(physical_before == normalized(assets(c.state)), "The declared political/pose opening preserves every actual financial and physical asset from funded progression")
	var saved = JSON.parse_string(JSON.stringify(c.state))
	var restored_core = Campaign.new(c.data, c.nav, false)
	restored_core.ocean_anchors064 = c.ocean_anchors064
	var restored: Dictionary = restored_core.restore(saved)
	if not check(bool(restored.get("ok", false)), "The finite declared control opening passes ordinary Campaign.restore: " + str(restored.get("message", ""))): return false
	c = restored_core
	var before_assets = JSON.parse_string(physical_before)
	var after_assets: Dictionary = assets(c.state)
	var differences: Dictionary = {}
	for key in before_assets:
		if normalized(before_assets[key]) != normalized(after_assets.get(key)):
			differences[key] = {"before":before_assets[key], "after":after_assets.get(key)}
	if not differences.is_empty():note("control_restore_asset_differences", differences)
	check(physical_before == normalized(assets(c.state)) and int(c.Factions.standing(c.state, "forge").score) == 20, "Ordinary restore retains exact physical custody and the disclosed valid political opening")
	for row in activity:
		var restored_owner: Dictionary = c.fleet_owner(str(row.ownerId))
		var restored_patrol: Dictionary = c.NavalAI._find_patrol(c.state, str(row.ownerId))
		check(restored_owner.get("active") == row.after.ownerActive and restored_patrol.get("active") == row.after.patrolActive,
			"Ordinary restore retains the disclosed activity for " + str(row.ownerId) + "; ocean-enrolled and nonhostile flags were not overridden")
	note("declared_control_opening", declared_politics)
	return failures == 0

func actual_contest() -> bool:
	if not bounded(): return false
	var job: Dictionary = c.state.territorial076.control
	var defender: Dictionary = c.fleet_owner(str(job.defenderId))
	var player: Array = c.FleetSupport.combat(c)
	var enemy: Array = defender.boats.filter(func(b): return not b.sunk)
	var original: Array = player + enemy
	var opening_people: float = 0.0
	var rounds: float = 0.0
	for boat in original: opening_people += float(boat.crew); rounds += float(boat.ammo)
	var options: Dictionary = Coast.arena(c.data, c.state.position)
	options.merge({"fleet":player, "enemyFleet":enemy, "seed":SEED}, true)
	var battle: Dictionary = Battle.create(options)
	battle.world064 = c.world_location064().world064
	battle.chartPosition = c.state.position.duplicate(true)
	if not check(str(battle.get("startError", "")).is_empty(), "The actual coast admits the original two physical combat owners: " + str(battle.get("startError", ""))): Battle._close_damage_owned051(battle); return false
	# Ordinary deployment/commands/update own every combat pose and terminal result.
	for _tick in range(1800):
		if battle.result != null: break
		if not bounded(): Battle._close_damage_owned051(battle); return false
		Battle.update(battle, 1.0 / 30.0, {})
	if not check(battle.result != null, "The single original-roster battle reaches a real terminal result within sixty simulation seconds"): Battle._close_damage_owned051(battle); return false
	var context: Dictionary = {"kind":"patrol", "id":str(defender.id), "ownerId":str(defender.id), "aggression":false}
	var report: Dictionary = c.battle_settled(str(battle.result), enemy.map(func(b): return b.spec), context, battle)
	if not check(not report.has("ok") or bool(report.ok), "Actual ordinary Campaign.battle_settled accepts the terminal physical contest: " + str(report.get("message", ""))): return false
	var after_people: float = 0.0
	var after_rounds: float = 0.0
	for boat in original: after_people += float(boat.crew); after_rounds += float(boat.ammo)
	casualties += opening_people - after_people
	note("actual_selected_defender_contest", {"ownerId":str(defender.id), "result":battle.result, "battle_seconds":float(battle.time),
		"initial_crew":opening_people, "settled_crew":after_people, "actual_crew_decrease":opening_people - after_people,
		"actual_rounds_spent":rounds - after_rounds, "report":report, "control":c.state.territorial076.control.duplicate(true), "source":str(battle.get("engagementSource060", ""))})
	check(rounds > after_rounds, "The real selected-defender contest spends original finite ammunition")
	return check(str(battle.result) == "won" and bool(c.state.territorial076.control.battleWon), "Only the actual matching physical victory records the selected defender as defeated")

func contested_control() -> bool:
	if not control_opening(): return false
	var port: Dictionary = c.port(control_port)
	var capital: int = int(c.state.coins)
	var treasury: int = int(port.governmentPurse)
	var begun: Dictionary = Territory.start(c, control_port, "forge")
	if not check(bool(begun.get("ok", false)), "The actual hostile-harbor operation selects its real defending fleet: " + str(begun.get("message", ""))): return false
	check(str(c.state.territorial076.control.defenderId) == "story-0" and int(c.state.coins) == capital - 800
		and int(port.governmentPurse) == treasury + 800, "The selected existing defender and exact 800-coin contribution are real")
	var before_refusal: PackedByteArray = var_to_bytes(c.state)
	var refused: Dictionary = Territory.negotiate(c)
	note("actual_control_early_negotiation", {"result":refused, "resources":local_resources()})
	check(not bool(refused.get("ok", false)) and var_to_bytes(c.state) == before_refusal, "Presence and funding alone cannot change control or consume further assets: " + str(refused.get("message", "")))
	if not wait_for_paid("control", "supportDays", 1): return false
	var retained: Dictionary = c.state.territorial076.control.duplicate(true)
	var before_withdraw: PackedByteArray = unreserved_assets()
	var recalled: Dictionary = Territory.withdraw(c)
	note("actual_control_withdraw_result", {"result":recalled, "resources":local_resources()})
	if not check(bool(recalled.get("ok", false)), "The actual one-day funded support party can withdraw: " + str(recalled.get("message", ""))): return false
	check(unreserved_assets() == before_withdraw and int(c.state.territorial076.control.supportDays) == 1,
		"Control withdrawal preserves exact actual assets and the already-spent support contribution")
	var resumed: Dictionary = Territory.start(c, control_port, "forge")
	note("actual_control_resume_result", {"result":resumed, "resources":local_resources()})
	if not check(bool(resumed.get("ok", false)), "The same actual control operation resumes without new endowment: " + str(resumed.get("message", ""))): return false
	check(unreserved_assets() == before_withdraw and int(c.state.territorial076.control.funded) == 800,
		"Resuming control repeats neither its 800 coins nor the completed first support day")
	note("actual_control_withdraw_resume", {"retained":retained, "resumed":c.state.territorial076.control.duplicate(true)})
	if not wait_for_paid("control", "supportDays", 2): return false
	if not actual_contest(): return false
	var before_transfer: String = normalized(assets(c.state))
	var private_before: String = normalized(c.state.businesses)
	var transferred: Dictionary = Territory.negotiate(c)
	if not check(bool(transferred.get("ok", false)), "Explicit actual negotiation transfers this harbor after its real contest and support: " + str(transferred.get("message", ""))): return false
	check(str(c.port(control_port).faction) == "forge" and str(c.state.territorial076.control.status) == "complete",
		"Only the named harbor changes from its old sovereign after actual funded resolution")
	# The deliberate reservation is released; it is a subset of each original crew.
	var final_assets: Dictionary = assets(c.state)
	for row in final_assets.boats: row.erase("shoreCrew")
	var old_assets = JSON.parse_string(before_transfer)
	for row in old_assets.boats: row.erase("shoreCrew")
	check(normalized(final_assets) == normalized(old_assets) and normalized(c.state.businesses) == private_before,
		"Negotiation preserves exact coins, people, goods, defense equipment, existing damage, hull/item IDs and independent private businesses")
	note("actual_negotiated_control_transfer", {"result":transferred, "operation":c.state.territorial076.control.duplicate(true), "private_businesses_unchanged":normalized(c.state.businesses) == private_before})
	return failures == 0

func save_witness(port_id: String) -> bool:
	if not bounded(): return false
	if not check(c.pending_days == 0 and workers.group_id < 0, "The final witness has no unpublished economy work"): return false
	# UI selection is ordinary saved presentation state, never a pose/account edit.
	c.state.campaignFocus.portId = port_id
	var serialized: String = JSON.stringify(c.state, "\t")
	var saved = JSON.parse_string(serialized)
	if not check(saved is Dictionary, "The ordinary Main.save_game whole-state JSON decodes"): return false
	var expected: String = normalized([assets(saved), saved.territorial076, saved.world064, saved.position, saved.day, saved.econDay, saved.campaignFocus, saved.sector069, saved.islandOwnership069])
	var restored_core = Campaign.new(c.data, c.nav, false)
	restored_core.ocean_anchors064 = c.ocean_anchors064
	var restored: Dictionary = restored_core.restore(saved)
	if not check(bool(restored.get("ok", false)), "The actual final full save uses ordinary Campaign.restore on shared Navigation: " + str(restored.get("message", ""))): return false
	c = restored_core
	check(expected == normalized([assets(c.state), c.state.territorial076, c.state.world064, c.state.position, c.state.day, c.state.econDay, c.state.campaignFocus, c.state.sector069, c.state.islandOwnership069]), "Ordinary JSON save/restore preserves actual title, purses, people, goods, damage, hull/item/machinery IDs, private ownership and clock")
	var law_error: String = c.LawOps.validate(saved, c.data)
	if not check(law_error.is_empty(), "Standalone trade-law validation accepts the actual completed transfer: " + law_error): return false
	var protected_state: PackedByteArray = var_to_bytes([c.state, c.events, c.pending_days])
	for corruption in ["missing_book", "inactive_control", "unrelated_home_title"]:
		if not bounded(): return false
		var malformed: Dictionary = saved.duplicate(true)
		if corruption == "missing_book":
			malformed.erase("territorial076")
		elif corruption == "inactive_control":
			# Withdrawn is otherwise valid with the actual released crew and paid history.
			malformed.territorial076.control.status = "withdrawn"
		else:
			var swapped: bool = false
			for port in malformed.ports:
				if port.id == "brass_haven" and port.id != control_port and port.faction != "forge":
					port.faction = "forge"; swapped = true; break
			if not check(swapped, "The forged unrelated title changes only actual HOME Brass Haven outside the completed operation"): return false
		var input_before: PackedByteArray = var_to_bytes(malformed)
		law_error = c.LawOps.validate(malformed, c.data)
		var refused: Dictionary = c.restore(malformed)
		var input_unchanged: bool = var_to_bytes(malformed) == input_before
		var live_unchanged: bool = var_to_bytes([c.state, c.events, c.pending_days]) == protected_state
		note("malformed_transfer_restore", {"case":corruption, "trade_law_error":law_error, "restore_result":refused,
			"input_unchanged":input_unchanged, "live_unchanged":live_unchanged})
		if not check(not law_error.is_empty(), "Standalone trade-law validation refuses " + corruption + ": " + law_error): return false
		if not check(not bool(refused.get("ok", true)) and str(refused.get("message", "")).contains("Harbor sovereign change has no completed territorial operation."),
			"Ordinary restore refuses " + corruption + " at the sovereign-history guard: " + str(refused.get("message", ""))): return false
		if not check(input_unchanged and live_unchanged, "Refusing " + corruption + " preserves exact input, live assets, territorial history, clock, events and pending work"): return false
	var directory: String = OS.get_environment("GAME_TEST_ARTIFACTS")
	if not check(directory.is_absolute_path(), "Root supplies the private witness directory"): return false
	var path: String = directory.path_join("territorial076-witness.json")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not check(file != null, "One ordinary full witness opens inside Root's private artifact directory"): return false
	file.store_string(serialized); file.close()
	var digest: String = FileAccess.get_sha256(path)
	if not check(digest.length() == 64, "The actual ordinary full witness has a SHA256"): return false
	artifacts.append({"kind":"witness", "path":path, "sha256":digest})
	note("ordinary_save_restore", {"portId":port_id, "faction":str(c.port(port_id).faction), "sha256":digest, "source":"Main.save_game whole core.state JSON; ordinary Campaign.restore; shared immutable Navigation"})
	return failures == 0

func closing_accounts() -> bool:
	var custody: Dictionary = Custody.check_state(c.state, c.data)
	var items: Array = custody.get("itemUids", []).duplicate(); items.sort()
	var boats: Array = []
	for boat in fleet_book(c.state): boats.append(str(boat.uid))
	boats.sort()
	check(Money.total(c.state) == supply and int(c.state.coinSupply) == supply, "All original world coins remain in the exact finite purses after work and control")
	check(absf(initial_people - people(c.state) - casualties) < 0.000001, "All original numerical people reconcile across residents, crews, private staff and actual casualties")
	check(bool(custody.get("ok", false)) and bool(custody.get("ready", false)), "The existing physical preflight accepts unique living/wreck equipment custody: " + str(custody.get("message", "")))
	check(items == initial_items and boats == initial_boats, "The bounded operation retains the exact original hull and equipment UID sets")
	check(geography == normalized([c.state.sector069, c.state.islandOwnership069]), "One harbor's sovereignty leaves seeded geography and every island owner unchanged")
	conservation = {"coin_supply_baseline":supply, "coin_supply":Money.total(c.state), "people_baseline":initial_people,
		"people":people(c.state), "actual_casualties":casualties, "boat_uid_count":boats.size(), "boat_uids_sha256":JSON.stringify(boats).sha256_text(),
		"equipment_uid_count":items.size(), "equipment_uids_sha256":JSON.stringify(items).sha256_text(), "holders":custody.get("holders", []),
		"machine":machinery().duplicate(true), "wage_per_person_day":100, "operation":c.state.territorial076.duplicate(true)}
	return failures == 0

func finish() -> void:
	if workers.group_id >= 0: workers.finish(true)
	if c != null and not complete and workers.group_id < 0:
		# One ordinary whole-state save after join, solely for failure diagnosis.
		# It is never restored here or advertised as a successful UI witness.
		var directory: String = OS.get_environment("GAME_TEST_ARTIFACTS")
		if check(directory.is_absolute_path(), "Root supplies the private failure-state directory"):
			var path: String = directory.path_join("territorial076-failure-state.json")
			var file = FileAccess.open(path, FileAccess.WRITE)
			if check(file != null, "One diagnostic-only ordinary failure state opens in Root's artifact directory"):
				file.store_string(JSON.stringify(c.state, "\t"))
				var write_error: int = file.get_error()
				file.close()
				if check(write_error == OK, "The complete diagnostic-only failure state is written: " + str(write_error)):
					var digest: String = FileAccess.get_sha256(path)
					if check(digest.length() == 64, "The ordinary diagnostic-only failure state has a SHA256"):
						artifacts.append({"kind":"failure_state", "diagnostic_only":true, "pass_witness":false, "path":path, "sha256":digest})
						note("ordinary_failure_state", {"diagnostic_only":true, "pass_witness":false, "path":path, "sha256":digest,
							"worker_joined":workers.group_id < 0, "pending_days":c.pending_days, "source":"Main.save_game whole core.state JSON; no restore or pass acceptance"})
	workers = null
	c = null
	var elapsed: int = Time.get_ticks_msec() - started
	check(elapsed < BODY_LIMIT_MS, "Body includes new_game, ordinary restores, proof and owned cleanup below fifty-five seconds")
	print(JSON.stringify({"fixture":"territorial076", "checks":checks, "failures":failures,
		"elapsed_ms":elapsed, "efficiency_goal_ms":EFFICIENCY_GOAL_MS, "efficiency_goal_met":elapsed <= EFFICIENCY_GOAL_MS,
		"complete":complete and failures == 0 and not expired,
		"failure_labels":failure_labels, "events":events, "accountfacts":conservation,
		"artifacts":artifacts, "limits":"Actual paid survey/recovery/warehouse progression with all live NPC activity; separate declared Friendly20 control opening, initial berths and one active coastal defender. Other currently hostile non-ocean-enrolled owners/patrols start inactive with all actual assets retained; no concurrent-raid coverage, earned-standing/history or outbound-travel claim. Actual subsequent combat/support/control required. No postopening activity override or render/listening/full-game/strict-performance acceptance."}))
	quit(0 if complete and failures == 0 and not expired else 1)

func _run() -> void:
	if not check(DisplayServer.get_name() == "headless", "Root alone runs this native fixture with the private headless backend"): finish(); return
	var definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	if not check(definitions is Dictionary, "Ordinary world definitions decode"): finish(); return
	c = Campaign.new(definitions)
	var opening: Dictionary = c.new_game(SEED)
	if not check(bool(opening.get("ok", false)), "One ordinary finite new_game supplies all opening assets: " + str(opening.get("message", ""))): finish(); return
	supply = Money.total(c.state); initial_people = people(c.state)
	geography = normalized([c.state.sector069, c.state.islandOwnership069])
	var custody: Dictionary = Custody.check_state(c.state, c.data)
	if not check(bool(custody.get("ok", false)) and bool(custody.get("ready", false)), "Opening hull and physical equipment custody is canonical: " + str(custody.get("message", ""))): finish(); return
	initial_items = custody.itemUids.duplicate(); initial_items.sort()
	for boat in fleet_book(c.state): initial_boats.append(str(boat.uid))
	initial_boats.sort()
	if not prepare_and_recover(): finish(); return
	if not funded_improvement(): finish(); return
	if not contested_control(): finish(); return
	if not save_witness(control_port): finish(); return
	complete = closing_accounts()
	finish()
