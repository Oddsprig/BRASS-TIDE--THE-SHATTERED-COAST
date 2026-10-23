extends SceneTree

const Guidance = preload("res://scripts/campaign_guidance.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Expedition = preload("res://scripts/expedition.gd")
const Deployment = preload("res://scripts/deployment.gd")
const Goods = preload("res://scripts/goods.gd")
const Money = preload("res://scripts/money.gd")

const ACTIONS = ["fleet", "hold", "training", "supply", "tooling", "workers",
	"trade", "companies", "law", "boarding", "crises", "exploration",
	"jobs", "regional"]

var checks = 0
var failures = 0
var world: Dictionary

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
	ck(options.size() == 5, "five careers")
	for option in options:
		ck(option.suggestions.size() >= 2 and option.suggestions.size() <= 4,
			"bounded career suggestions")
		var selected = view(c, 0.0, option.id)
		ck(selected.career == option.id, "career selection")
		for suggestion in option.suggestions:
			ck(ACTIONS.has(suggestion.actionId), "career action exists")

	for distance in [NAN, INF, -INF, -1.0, 2000000000.0]:
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

func _initialize() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	ck(parsed is Dictionary, "world JSON loads")
	if parsed is Dictionary:
		world = parsed
		test_pristine_and_inputs()
		test_real_fleet_and_dangers()
	print("campaign guidance: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
