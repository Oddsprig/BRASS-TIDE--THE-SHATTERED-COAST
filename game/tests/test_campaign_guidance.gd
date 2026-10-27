extends SceneTree

const Guidance = preload("res://scripts/campaign_guidance.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Expedition = preload("res://scripts/expedition.gd")
const Deployment = preload("res://scripts/deployment.gd")
const Goods = preload("res://scripts/goods.gd")
const Money = preload("res://scripts/money.gd")
const Battle = preload("res://scripts/battle.gd")
const CoastalTerrain = preload("res://scripts/coastal_terrain.gd")

const FILE_WALL_US: int = 18000000
const CAMPAIGN_STEPS: int = 900 # 30 simulated seconds shared by both legs.
const COMBAT_STEPS: int = 5400 # 90 simulated seconds at production 60 Hz.

const ACTIONS = ["fleet", "hold", "training", "supply", "tooling", "workers",
	"trade", "companies", "law", "boarding", "crises", "exploration",
	"jobs", "regional", "fishing", "traffic", "contracts", "market", "yard", "catalog"]
const CAREER_IDS = ["captain", "explorer", "merchant", "privateer", "escort",
	"fisher", "passenger", "harbormaster"]

var checks = 0
var failures = 0
var world: Dictionary
var file_started_us: int = 0
var file_phase: String = "startup"
var file_timed_out: bool = false
var voyage_complete: bool = false

func in_time(phase: String) -> bool:
	file_phase = phase
	if not file_timed_out and Time.get_ticks_usec() - file_started_us < FILE_WALL_US:
		return true
	if not file_timed_out:
		file_timed_out = true
		ck(false, "entire file exceeded 18s wall guard in " + phase)
	return false

func voyage_ck(value: bool, label: String) -> bool:
	ck(value, "first voyage [" + file_phase + "]: " + label)
	if not value:
		print("first voyage INCOMPLETE phase=" + file_phase)
	return value

func ck(value, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL guidance: "+label)

func snapshot(c) -> String:
	return JSON.stringify({"state":c.state, "data":c.data})

func finite_tree(v) -> bool:
	if v is float or v is int:
		return is_finite(float(v)) and absf(float(v)) <= 1000000000.0
	if v is Array:
		for item in v:
			if not finite_tree(item):
				return false
	if v is Dictionary:
		for item in v.values():
			if not finite_tree(item):
				return false
	return true

func view(c, distance: float = 0.0, career: String = "captain") -> Dictionary:
	var before = snapshot(c)
	var r = Guidance.report(c, distance, career)
	ck(snapshot(c) == before, "report preserves state and world")
	ck(r.ok, "valid Campaign accepted")
	ck(r.cards.size() <= 8 and r.warnings.size() <= 8, "bounded output")
	ck(finite_tree(r), "finite capped numerical display")
	ck(r.day == c.state.day, "campaign day timestamp")
	for card in r.cards:
		ck(ACTIONS.has(card.actionId), "supported action ID")
		ck(card.title != "" and card.reason != "", "readable card")
	return r

func card_with(r: Dictionary, id: String) -> Dictionary:
	for card in r.cards:
		if card.id == id:
			return card
	return {}

func boat(seed: Dictionary, uid: String) -> Dictionary:
	var b = seed.duplicate(true)
	b["uid"] = uid
	b["name"] = uid
	b["crew"] = 4
	b["crewMin"] = 1
	b["crewMax"] = 8
	b["shoreCrew"] = 0
	b["hp"] = 100.0
	b["maxHp"] = 100.0
	b["water"] = 0.0
	b["waterCapacity"] = 50.0
	b["fire"] = 0.0
	b["fuel"] = 20.0
	b["supplies"] = 20.0
	b["storedPort"] = ""
	b["mothballed"] = false
	b["sunk"] = false
	b["supportOnly"] = false
	b["needsHarborRepair"] = false
	b["spec"] = seed.spec.duplicate(true)
	b.spec["cargo"] = 20.0
	return b

func test_pristine_and_inputs() -> void:
	var c = Campaign.new(world.duplicate(true));c.new_game(281)
	if not in_time("pristine career"):
		return
	var before = snapshot(c)
	var cash = Money.total(c.state)
	ck(snapshot(c) == before, "pristine total is read-only")
	var r = view(c)
	ck(Money.total(c.state) == cash and snapshot(c) == before,
		"pristine canonical purses conserved")
	ck(Goods.SAILOR_WAGE == 100, "100 coins per sailor-day")
	ck(r.route_trip_returnbudget.sailorDayCoins == 100, "wage anchor exposed")
	ck(not r.has("hullPrice") and not r.route_trip_returnbudget.has("hullPrice"),
		"no invented hull price")

	var options = Guidance.careers()
	ck(options.size() == 8, "eight careers")
	ck(options.map(func(option):return str(option.id)) == CAREER_IDS,
		"exact current career IDs and order")
	for option in options:
		if not in_time("prior career guidance"):
			return
		ck(option.suggestions.size() >= 2 and option.suggestions.size() <= 4,
			"bounded career suggestions")
		var selected = view(c, 0.0, option.id)
		ck(selected.career == option.id, "career selection")
		for suggestion in option.suggestions:
			ck(ACTIONS.has(suggestion.actionId), "career action exists")

	for distance in [NAN, INF, -INF, -1.0, 2000000000.0]:
		if not in_time("prior invalid route guidance"):
			return
		var invalid = view(c, distance, "missing_career")
		ck(invalid.routeDistance == 0.0 and not invalid.routeValid,
			"invalid route explicitly normalized")
		ck(invalid.career == "captain" and not invalid.notes.is_empty(),
			"invalid career explained")
	ck(snapshot(c) == before, "successful and invalid reports preserve snapshot")

	r.route_trip_returnbudget.dailyWages = 999
	r.fleet.owned = 999
	r.warnings.append("edited")
	r.notes.append("edited")
	if not r.cards.is_empty():
		r.cards[0].reason = "edited"
	options[0].suggestions[0].reason = "edited"
	ck(snapshot(c) == before, "returned nested edits cannot change campaign")
	ck(Guidance.careers()[0].suggestions[0].reason != "edited",
		"career copies are independent")
	var absent = Guidance.report(null)
	ck(not absent.ok and absent.cards.is_empty(), "missing Campaign handled")

func test_real_fleet_and_dangers() -> void:
	var c = Campaign.new(world.duplicate(true));c.new_game(281)
	if not in_time("prior fleet career"):
		return
	ck(not c.state.fleet.is_empty(), "real starter hull exists")
	if c.state.fleet.is_empty():
		return
	var seed: Dictionary = c.state.fleet[0].duplicate(true)
	var home = c.current_port().get("id", "")
	ck(home != "", "real starting harbor exists")
	if home == "":
		return
	var flag = boat(seed, "guidance_flag")
	var support = boat(seed, "guidance_support")
	support.supportOnly = true
	var stored = boat(seed, "guidance_stored")
	stored.storedPort = home
	c.state.fleet = [flag, support, stored]
	c.state.flagship = flag.uid
	c.state.specialists = []
	c.state["wageArrears"] = 0
	for good in c.state.cargo:
		c.state.cargo[good] = 0.0

	ck(Deployment.cost(flag) > 0, "real hull has deployment cost")
	for i in range(Deployment.LIMIT + 1):
		if not in_time("prior deployment fixture"):
			return
		c.state.fleet.append(boat(seed, "guidance_%d" % i))
		var active = c.active_fleet()
		var split = Deployment.split(active.duplicate(true))
		if Deployment.total(active) > Deployment.LIMIT and split.reserve.size() > 1:
			break
	var active = c.active_fleet()
	var split = Deployment.split(active.duplicate(true))
	ck(Deployment.total(active) > Deployment.LIMIT, "fixture exceeds battle limit")
	ck(split.reserve.size() > 1, "battle reserve beyond support hull")

	# Read-only fixtures below do not perform transfers or claim global balance.
	# Money.total is deliberately restricted to the pristine test above.
	var company_hull = boat(seed, "guidance_company")
	c.state.fleetOwners.append({"id":"guidance_co", "playerCompany":true,
		"name":"Fixture Lines", "boats":[company_hull], "route":[home],
		"coins":900, "crewPurse":50, "wageArrears":0})
	c.state["shippingCompanies"] = {"guidance_co":{
		"ownerId":"guidance_co", "status":"active", "recall":true,
		"netProfit":-17, "invested":500, "withdrawn":0}}

	var r = view(c, 0.0, "merchant")
	if not in_time("prior fleet guidance"):
		return
	var e = Expedition.report(c.state, c.data, 0.0)
	var points = 0
	for b in split.deployed:
		points += Deployment.cost(b)
		ck(b.uid != support.uid, "support excluded from battle line")
	ck(r.fleet.limit == 300 and r.fleet.points == points, "actual deployed costs")
	ck(r.fleet.points == split.points and r.fleet.reserve == split.reserve.size(),
		"actual battle split")
	ck(r.fleet.totalPoints == Deployment.total(active), "actual total points")
	ck(r.fleet.owned == c.state.fleet.size() + 1 and r.fleet.company == 1,
		"owned and company hulls counted once")
	ck(r.fleet.stored == 1 and r.fleet.support == 1, "stored and support records")
	ck(r.route_trip_returnbudget.usableCapacity == e.usableCapacity,
		"reserve is not added as new capacity")
	var account = card_with(r, "companies")
	ck(not account.is_empty(), "recorded company opportunity")
	if not account.is_empty():
		var text = account.reason.to_lower()
		ck(text.contains("-17") and text.contains("900") and text.contains("recall"),
			"real profit, operating cash and recall")
		ck(text.contains("capital") and text.contains("profit"), "capital distinction")
		var before = snapshot(c)
		account.reason = "edited"
		ck(snapshot(c) == before, "company card has no book alias")

	var capacity = e.usableCapacity
	flag.spec.cargo = 1.0
	r = view(c)
	if not in_time("prior fitted capacity"):
		return
	e = Expedition.report(c.state, c.data, 0.0)
	ck(r.route_trip_returnbudget.usableCapacity == e.usableCapacity
		and e.usableCapacity < capacity, "actual fitted spec.cargo")

	flag.crew = 1
	flag.crewMin = 4
	flag.water = 5.0
	flag.fire = 1.0
	flag.hp = 20.0
	flag.needsHarborRepair = true
	for b in c.state.fleet:
		b.fuel = 0.0
		b.supplies = 0.0
	c.state.coins = 0
	c.state.crewPurse = 0
	c.state.wageArrears = 200
	r = view(c, 1000.0, "explorer")
	if not in_time("prior danger guidance"):
		return
	e = Expedition.report(c.state, c.data, 1000.0)
	ck(r.cards[0].id == "hulls", "urgent hull readiness first")
	for id in ["crew", "pay", "stores", "return_pay"]:
		ck(not card_with(r, id).is_empty(), "actual danger: " + id)
	ck(r.route_trip_returnbudget.dailyWages == int(ceil(float(e.dailyWages)))
		and e.dailyWages == c.state.fleet.filter(func(b):return not b.sunk).reduce(func(sum,b):return sum+int(b.crew)*Goods.SAILOR_WAGE,0), "actual numerical crew wages")
	ck(r.route_trip_returnbudget.returnWages == int(ceil(float(e.returnWages))),
		"actual rounded return payroll")
	ck(r.route_trip_returnbudget.tripDays == e.tripDays
		and r.route_trip_returnbudget.foodDays == e.foodDays
		and r.route_trip_returnbudget.fuelDays == e.fuelDays, "actual trip and stores")
	c.state.cargo["food"] = 1000000.0
	r = view(c, 1000.0, "harbormaster")
	ck(not card_with(r, "overload").is_empty(), "actual overloaded hold")

func test_first_voyage_public_loop() -> void:
	if not in_time("voyage career creation"):
		return
	var c = Campaign.new(world.duplicate(true))
	var born: Dictionary = c.new_game(123)
	if not in_time("voyage start") or not voyage_ck(born.get("ok", false), str(born.get("message", "career refused"))):
		return
	if not voyage_ck(c.current_port().get("id", "") == "brass_haven" and c.state.fleet.size() == 1, "actual single-hull Brass Haven start"):
		return
	var ship: Dictionary = c.state.fleet[0]
	var uid: String = str(ship.uid)
	var initial_cash: int = int(c.state.coins)
	var initial_crew_purse: int = int(c.state.crewPurse)
	var initial_food: float = float(c.state.cargo.food)
	var initial_day: float = float(c.state.day)
	var initial_econ_day: int = int(c.state.econDay)
	var total_coins: int = Money.total(c.state)
	var initial_budget: Dictionary = c.expedition_report(0.0)
	var initial_wages: int = int(initial_budget.dailyWages)
	var reward: int = 0
	var captured: int = 0
	var repair_cost: int = 0
	var refill_cost: int = 0
	var campaign_steps: int = 0
	var route_distance: float = 0.0
	var combat_time: float = 0.0
	if not voyage_ck(ship.type == "tin_skiff" and initial_cash == 15000 and initial_wages == 500, "real Tin start and 500/day payroll"):
		return
	var offer: Dictionary = {}
	for candidate in c.available_contracts():
		if candidate.id == "mission_1_lantern_sweep":
			offer = candidate
	if not voyage_ck(not offer.is_empty(), "opening contract available"):
		return
	reward = int(offer.reward)
	if not voyage_ck(reward == 34545 and offer.targetPort == "kelp_reach", "calculated 34,545-coin Kelp combat job"):
		return
	var sponsor: Dictionary = c.current_port()
	var sponsor_before: int = int(sponsor.governmentPurse)
	var accepted: Dictionary = c.accept_contract(str(offer.id))
	if not voyage_ck(accepted.get("ok", false), str(accepted.get("message", "acceptance refused"))):
		return
	if not voyage_ck(c.state.coins == initial_cash and sponsor.governmentPurse == sponsor_before - reward and c.state.activeContract.escrow == reward and Money.total(c.state) == total_coins, "sponsor funds conserved escrow without paying captain"):
		return
	var early: Dictionary = c.finish_contract()
	if not voyage_ck(not early.get("ok", false) and c.state.coins == initial_cash and c.state.activeContract.escrow == reward, "no early payment"):
		return

	for destination in ["kelp_reach", "brass_haven"]:
		if not in_time("sailing to " + destination):
			return
		var course: Dictionary = c.chart_course(c.port_position(destination), destination)
		if not voyage_ck(course.get("ok", false), str(course.get("message", "course refused"))):
			return
		var arrived: bool = false
		while not c.state.path.is_empty() and campaign_steps < CAMPAIGN_STEPS:
			if not in_time("sailing to " + destination):
				return
			var prior_position: Dictionary = c.state.position.duplicate()
			c.step(1.0 / 30.0)
			campaign_steps += 1
			route_distance += c.distance(prior_position, c.state.position)
			for event in c.pop_events():
				if event.get("kind", "") == "arrival" and event.get("port", "") == destination:
					arrived = true
				elif event.get("kind", "") in ["defeat", "encounter"]:
					voyage_ck(false, "additional journey event: " + JSON.stringify(event))
					return
			if not voyage_ck(not c.state.fleet.is_empty(), "physical starter survives sailing"):
				return
		if not voyage_ck(arrived and c.state.path.is_empty() and c.current_port().get("id", "") == destination, "actual arrival within shared 30s campaign horizon: " + destination):
			return
		c.StoryOps.refresh(c) # Same arrival publication as main._physics_process.
		if destination == "brass_haven":
			continue
		if not in_time("physical Kelp battle") or not voyage_ck(c.contract_ready(), "contract destination reached by sailing"):
			return
		var owner: Dictionary = c.fleet_owner(str(c.state.activeContract.ownerId))
		if not voyage_ck(not owner.is_empty(), "real opponent owner exists"):
			return
		var enemies: Array = []
		for id in c.state.activeContract.enemyHulls:
			enemies.append(c.hull(str(id)))
		var context: Dictionary = {"kind":"contract", "id":offer.id, "ownerId":owner.id, "name":"%s approaches" % str(c.port(str(offer.targetPort)).name)}
		context = c.EscortOps.prepare_intercept(c, context)
		if not voyage_ck(str(context.get("startError", "")).is_empty(), "production encounter preparation: " + str(context.get("startError", ""))):
			return
		c.use_reserves()
		c.stop_sailing()
		var combat_fleet: Array = c.FleetSupport.combat(c)
		for combat_ship in combat_fleet:
			combat_ship.supportRepairFactor = 1.0 # main.begin_battle's combat setup.
		var arena: Dictionary = CoastalTerrain.arena(c.data, c.state.position)
		arena.merge({"fleet":combat_fleet, "mission":context.get("mission", {}), "enemyFleet":owner.boats.filter(func(b):return not b.sunk), "enemySpecs":enemies, "seed":int(c.state.seed)+int(c.state.wins)*17+int(c.state.losses)*5})
		var battle: Dictionary = Battle.create(arena)
		if not voyage_ck(str(battle.get("startError", "")).is_empty() and battle.autopilot, "real coastal arena/default autopilot: " + str(battle.get("startError", ""))):
			return
		context.mission = battle.mission.duplicate(true)
		battle.captureSlots = maxi(0, 64-c.state.get("boardingPrizes", []).size())
		c.BoardingOps.coastal(c, battle)
		for _frame in range(COMBAT_STEPS):
			if battle.result != null:
				break
			if not in_time("physical Kelp battle at %.3fs" % float(battle.time)):
				return
			Battle.update(battle, 1.0 / 60.0, {})
		combat_time = float(battle.time)
		print("first voyage fight result=%s sim=%.3fs hp=%.3f ammo=%.3f kits=%.3f" % [str(battle.result), combat_time, float(ship.hp), float(ship.ammo), float(ship.supplies)])
		if not voyage_ck(battle.result == "won", "actual 60Hz win within 90s; outcome=" + str(battle.result)):
			return
		if not in_time("physical battle settlement"):
			return
		var battle_stores: Array = [ship.hp, ship.ammo, ship.supplies, ship.fuel]
		var cash_before_settlement: int = int(c.state.coins)
		var owner_before_settlement: int = int(owner.coins)
		captured = floori(float(owner_before_settlement) * 0.30)
		context.objectiveOnly = bool(battle.get("objectiveOnly", false))
		var settled: Dictionary = c.battle_settled(str(battle.result), enemies, context, battle)
		if not voyage_ck(settled.get("ok", true) and not settled.get("fleetLost", true), str(settled.get("message", "physical settlement retains fleet"))):
			return
		var payout_count: int = 0
		for entry in c.state.moneyLog:
			if entry.get("reason", "") == "Contract payment from escrow":
				payout_count += 1
				if not voyage_ck(int(entry.cash) == reward, "actual escrow receipt"):
					return
		if not voyage_ck(c.state.coins == cash_before_settlement + reward + captured and owner.coins == owner_before_settlement - captured and int(settled.get("coins", -1)) == reward + captured and payout_count == 1, "exactly one funded payout, separate real owner loot"):
			return
		if not voyage_ck(c.state.missionIndex == 1 and c.state.wins == 1 and c.state.activeContract.is_empty() and Money.total(c.state) == total_coins, "one physical story victory conserves all coins"):
			return
		if not voyage_ck([ship.hp, ship.ammo, ship.supplies, ship.fuel] == battle_stores and is_same(c.find_boat(uid), ship), "settlement preserves physical starter damage and stores"):
			return
		print("first voyage paid at Kelp reward=%d captured=%d captain=%d" % [reward, captured, int(c.state.coins)])

	if not in_time("Brass service and refill"):
		return
	var cash_before_duplicate: int = int(c.state.coins)
	var duplicate_payment: Dictionary = c.finish_contract()
	if not voyage_ck(not duplicate_payment.get("ok", false) and c.state.coins == cash_before_duplicate, "return cannot collect the completed contract again"):
		return
	var service: Dictionary = c.service_quote(ship, c.current_port())
	if not voyage_ck(service.get("ok", false), str(service.get("error", "service quote refused"))):
		return
	if int(service.cost) > 0 or float(service.material) > 0.0 or int(service.get("equipmentCount", 0)) > 0:
		if not in_time("paid harbor repair"):
			return
		var cash_before_repair: int = int(c.state.coins)
		var fixed: Dictionary = c.repair_boat(uid)
		if not voyage_ck(fixed.get("ok", false), str(fixed.get("message", "service refused"))):
			return
		repair_cost = cash_before_repair - int(c.state.coins)
		if not voyage_ck(repair_cost == int(service.cost) and is_equal_approx(float(ship.hp), float(ship.maxHp)) and ship.breaches.is_empty() and float(ship.water) == 0.0 and float(ship.fire) == 0.0, "paid quoted physical harbor repair"):
			return
	else:
		print("first voyage repair NOT EXERCISED: actual starter has no service deficit")
	if not in_time("replacement working stores"):
		return
	var targets: Dictionary = {"fuel":float(ship.spec.get("fuelCapacity", 60)), "ammo":maxf(80.0, float(ship.spec.get("ammoCapacity", 80))), "supplies":20.0}
	var needs_refill: bool = false
	for good in targets:
		if float(ship[good]) + 0.00001 < float(targets[good]):
			needs_refill = true
	if needs_refill:
		var cash_before_refill: int = int(c.state.coins)
		var refilled: Dictionary = c.resupply_boat(uid, "full")
		if not voyage_ck(refilled.get("ok", false), str(refilled.get("message", "refill refused"))):
			return
		refill_cost = cash_before_refill - int(c.state.coins)
	for good in targets:
		if not voyage_ck(float(ship[good]) + 0.00001 >= float(targets[good]), "paid %s replacement %.5f/%.5f; stock or cash short if incomplete" % [str(good), float(ship[good]), float(targets[good])]):
			return
	var booked_wages: int = 0
	for entry in c.state.moneyLog:
		if entry.get("reason", "") == "Captain pays sailors":
			booked_wages += int(entry.cash)
	if not voyage_ck(int(c.state.day) == int(initial_day) and c.state.econDay == initial_econ_day and c.pending_days == 0 and booked_wages == 0 and c.state.crewPurse == initial_crew_purse and is_equal_approx(float(c.state.cargo.food), initial_food), "day-1 journey has zero booked payroll/food; no economy day skipped"):
		return
	var campaign_days: float = float(c.state.day) - initial_day
	var wage_allowance: float = float(initial_wages) * campaign_days
	var profit: int = reward + captured - booked_wages - repair_cost - refill_cost
	if not voyage_ck(c.state.coins == initial_cash + profit and profit > 0 and Money.total(c.state) == total_coins, "positive measured operating cash profit after repair and replacement stores"):
		return
	print("first voyage economy " + JSON.stringify({"reward":reward, "captured":captured, "repair":repair_cost, "refill":refill_cost, "cashProfitBeforeFitting":profit, "bookedDay1Wages":booked_wages, "initialCrewWageAllowanceNotBooked":wage_allowance, "profitLessWageAllowance":float(profit)-wage_allowance, "campaignDays":campaign_days}))

	if not in_time("paid racing-engine fitting"):
		return
	var engine_uid: String = ""
	for item in ship.get("moduleCondition", {}).get("items", {}).values():
		if item.get("location", "") == "engine":
			engine_uid = str(item.itemUid)
	if not voyage_ck(not engine_uid.is_empty(), "existing physical engine identity retained"):
		return
	var draft: Dictionary = ship.loadout.duplicate(true)
	draft.engine = "boost_drive"
	var request: Dictionary = {"slots":{"engine":{"new":true}}}
	var quote: Dictionary = c.workshop_preview(uid, draft, request)
	var reserve: int = maxi(initial_wages * 2, int(c.expedition_report(0.0).returnWages))
	print("first voyage fitting " + JSON.stringify({"cost":quote.get("cost", 0), "captainCoins":c.state.coins, "requiredPayrollReserve":reserve, "cashGap":maxi(0, int(quote.get("cost", 0))+reserve-int(c.state.coins)), "reasons":quote.get("reasons", [])}))
	if not voyage_ck(quote.get("ok", false), str(quote.get("message", "fitting refused"))):
		return
	if not voyage_ck(int(quote.cost) > initial_cash and c.state.coins >= int(quote.cost) + reserve, "job unlocks a paid fitting while retaining two-day payroll reserve"):
		return
	if not in_time("apply paid racing engine"):
		return
	var cash_before_fitting: int = int(c.state.coins)
	var materials_before: Dictionary = c.current_port().stocks.duplicate(true)
	var fitted: Dictionary = c.workshop_apply(uid, draft, quote, request)
	if not voyage_ck(fitted.get("ok", false) and fitted.get("changed", false), str(fitted.get("message", "fitting refused"))):
		return
	if not voyage_ck(c.state.coins == cash_before_fitting - int(quote.cost) and c.state.coins >= reserve and ship.loadout.engine == "boost_drive", "actual fitting debit, installed racing engine and retained reserve"):
		return
	for good in quote.materials:
		if not voyage_ck(is_equal_approx(float(materials_before[good])-float(c.current_port().stocks[good]), float(quote.materials[good])), "physical fitting materials: " + str(good)):
			return
	var old_engine: Dictionary = ship.moduleCondition.items.get(engine_uid, {})
	if not voyage_ck(old_engine.get("location", "") == "locker" and old_engine.get("typeId", "") == "stock_engine" and int(ship.refitLocker.get("stock_engine", 0)) == 1, "same old engine retained once in the physical locker"):
		return
	if not voyage_ck(float(ship.spec.speed) > float(quote.beforeSpec.speed) and float(ship.spec.turn) > float(quote.beforeSpec.turn) and float(ship.spec.fuelUse) > float(quote.beforeSpec.fuelUse), "meaningful paid speed/turn benefit with higher fuel use"):
		return
	if not voyage_ck(Money.total(c.state) == total_coins and int(c.state.coins) == initial_cash + profit - int(quote.cost), "capital spend separated from operating profit; total coins conserved"):
		return
	var guidance_failures_before: int = failures
	view(c)
	if not voyage_ck(failures == guidance_failures_before, "resulting fitted-fleet guidance stays read-only and valid"):
		return
	if not in_time("voyage final guidance"):
		return
	voyage_complete = true
	print("first voyage metrics " + JSON.stringify({"campaignSteps":campaign_steps, "routeDistance":route_distance, "combatSeconds60Hz":combat_time, "fittingCapitalSpent":quote.cost, "captainCoins":c.state.coins, "payrollReserve":reserve, "wallSecondsEntireFile":float(Time.get_ticks_usec()-file_started_us)/1000000.0}))

func _initialize() -> void:
	file_started_us = Time.get_ticks_usec()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	ck(parsed is Dictionary, "world JSON loads")
	if parsed is Dictionary:
		world = parsed
		if in_time("prior pristine checks"):
			test_pristine_and_inputs()
		if in_time("prior fleet checks"):
			test_real_fleet_and_dangers()
		if in_time("first voyage"):
			test_first_voyage_public_loop()
	if not in_time(file_phase):
		voyage_complete = false
	print("first voyage status=%s phase=%s entire_file_wall=%.3fs" % ["complete" if voyage_complete else "INCOMPLETE", file_phase, float(Time.get_ticks_usec()-file_started_us)/1000000.0])
	print("campaign guidance: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
