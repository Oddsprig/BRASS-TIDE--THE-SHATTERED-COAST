extends SceneTree
const Goods=preload("res://scripts/goods.gd")

const RG = preload("res://scripts/regional_goods.gd")
const TOL := 0.00001
var failures: int = 0


func _initialize() -> void:
	_test_contract()
	if failures > 0:
		quit(1)
		return
	_test_schema()
	_test_industries()
	_test_denied_production()
	_test_cash_and_fractional_days()
	_test_household_demand()
	_test_invalid_steps()
	if failures == 0:
		print("REGIONAL_GOODS_TESTS_PASS")
	else:
		push_error("Regional goods failures: " + str(failures))
	quit(0 if failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= TOL


func _port(industry: String) -> Dictionary:
	return {
		"id": "regional_fixture",
		"name": "Regional fixture",
		"industry": industry,
		"specialty": "baseline specialty",
		"workforce": 100.0,
		"availableWorkers": 10.0,
		"availableSpecialists": 10.0,
		"_yardWorkersUsed": 0.0,
		"_yardSpecialistsUsed": 0.0,
		"stocks": {"food": 100.0, "logs": 100.0, "timber":100.0, "charcoal": 100.0},
		"cash": 20000,
		"householdPurse": 0,
		"expertPurse": 0,
		"governmentPurse": 5000,
		"employed": {"laborer": 5.0},
		"lastProduction": {"food": 1.0},
		"lastPayroll": 500,
		"unrest": 0.0,
		"starvation": 0.0
	}


func _money(port: Dictionary) -> int:
	return (
		int(port["cash"]) + int(port["householdPurse"])
		+ int(port["expertPurse"]) + int(port["governmentPurse"])
	)


func _employed(port: Dictionary) -> float:
	var total: float = 0.0
	for value: Variant in port["employed"].values():
		total += float(value)
	return total


func _audit(before: Dictionary, after: Dictionary) -> void:
	var error: String = RG.validate(after)
	_expect(error.is_empty(), "Post-step validation: " + error)
	if not error.is_empty():
		return
	var r: Dictionary = RG.report(after)
	var produced: Dictionary = r["lastProduction"]
	var consumed: Dictionary = r["lastConsumption"]
	var wages: int = int(r["lastWages"])
	var spent: int = int(r["lastSpent"])
	var expert_pay: int = int(after["expertPurse"]) - int(before["expertPurse"])
	var household_pay: int = (
		int(after["householdPurse"]) - int(before["householdPurse"]) + spent
	)
	_expect(_money(before) == _money(after), "Coins must be conserved")
	_expect(expert_pay >= 0 and household_pay >= 0, "No negative payroll")
	_expect(expert_pay + household_pay == wages, "Purses receive reported wages")
	_expect(
		int(after["cash"]) == int(before["cash"]) - wages + spent,
		"Harbor cash matches payroll and actual sales"
	)
	var days: float = float(r["days"])
	var purchase_purse: int = int(before["householdPurse"]) + household_pay
	var cap: int = floori(
		float(purchase_purse) * minf(RG.MAX_PURSE_SHARE, RG.PURSE_SHARE * days)
	)
	_expect(spent <= cap, "Household purchases respect remaining-purse budget")
	var billed: float = 0.0
	var worker_days: float = 0.0
	var expert_days: float = 0.0
	var definitions: Dictionary = RG.specs()
	for good: String in RG.IDS:
		var quantity: float = float(produced.get(good, 0.0))
		var used: float = float(consumed.get(good, 0.0))
		_expect(
			_near(
				float(after["stocks"].get(good, 0.0)),
				float(before["stocks"].get(good, 0.0)) + quantity - used
			),
			"Real stock conservation: " + good
		)
		billed += float(Goods.labor_cost(Goods.ITEMS[good].labor)) * quantity
		worker_days += float(Goods.labor_days(Goods.ITEMS[good].labor)) * quantity
		var labor: Dictionary = definitions[good]["labor"]
		for role: String in labor:
			if RG.EXPERT_ROLES.has(role):
				expert_days += float(labor[role]) * quantity
		if used > TOL:
			_expect(spent > 0, "Consumed goods require actual household coins")
	_expect(wages >= ceili(billed), "No unpaid fractional production")
	for ingredient: String in ["food", "logs", "timber", "charcoal"]:
		var required: float = 0.0
		for good: String in RG.IDS:
			required += (
				float(produced.get(good, 0.0))
				* float(definitions[good]["inputs"].get(ingredient, 0.0))
			)
		_expect(
			_near(
				float(after["stocks"].get(ingredient, 0.0)),
				float(before["stocks"].get(ingredient, 0.0)) - required
			),
			"Actual ingredient conservation: " + ingredient
		)
	var workers: float = float(r["workersUsed"])
	var specialists: float = float(r["specialistsUsed"])
	_expect(
		_near(float(before["availableWorkers"]) - float(after["availableWorkers"]), minf(float(before["availableWorkers"]),ceilf(workers))),
		"Workers reserved exactly once"
	)
	_expect(
		_near(
			float(before["availableSpecialists"]) - float(after["availableSpecialists"]),
			minf(float(before["availableSpecialists"]),ceilf(specialists))
		),
		"Specialists reserved exactly once"
	)
	_expect(_near(workers * days, worker_days), "Real labor-days constrain output")
	_expect(_near(specialists * days, expert_days), "Real specialist-days constrain output")
	_expect(_near(_employed(after) - _employed(before), workers), "Employment bookkeeping")
	_expect(workers <= RG.TEAM + TOL, "Modest workshop team cap")
	_expect(
		workers <= maxf(
			0.0,
			float(before["availableWorkers"]) - float(before["_yardWorkersUsed"])
		) + TOL,
		"Yard workers remain reserved"
	)
	_expect(
		specialists <= maxf(
			0.0,
			float(before["availableSpecialists"]) - float(before["_yardSpecialistsUsed"])
		) + TOL,
		"Yard specialists remain reserved"
	)
	_expect(float(r["usedUnits"]) <= float(r["needUnits"]) + TOL, "No excess consumption")
	for key: String in [
		"workforce", "specialty", "governmentPurse", "lastProduction",
		"lastPayroll", "unrest", "starvation"
	]:
		_expect(after[key] == before[key], "Preserve base field: " + key)


func _test_contract() -> void:
	var definitions: Dictionary = RG.specs()
	_expect(definitions.size() == 4, "Exactly four regional products")
	for good: String in RG.IDS:
		_expect(Goods.ITEMS.has(good), "Root must install Goods spec: " + good)
		if not Goods.ITEMS.has(good):
			continue
		var definition: Dictionary = definitions[good]
		_expect(
			Goods.ITEMS[good].get("inputs", {}) == definition["inputs"],
			"Installed material bill: " + good
		)
		_expect(
			Goods.ITEMS[good].get("labor", {}) == definition["labor"],
			"Installed labor bill: " + good
		)
		_expect(
			_near(float(Goods.ITEMS[good].get("weight", 0.0)), float(definition["weight"])),
			"Installed cargo weight: " + good
		)
		var cost: float = 0.0
		var days: float = 0.0
		var labor: Dictionary = definition["labor"]
		for role: String in labor:
			_expect(Goods.WAGES.has(role), "Existing wage role: " + role)
			cost += float(labor[role]) * float(Goods.WAGES.get(role, 0))
			days += float(labor[role])
		_expect(_near(float(Goods.labor_cost(Goods.ITEMS[good].labor)), cost), "Goods labor cost: " + good)
		_expect(_near(float(Goods.labor_days(Goods.ITEMS[good].labor)), days), "Goods labor days: " + good)


func _test_schema() -> void:
	var p: Dictionary = _port("fishery")
	var before: Dictionary = p.duplicate(true)
	_expect(RG.validate(p).is_empty(), "Legacy port without regional state is valid")
	RG.ensure(p)
	for key: String in before:
		_expect(p[key] == before[key], "Ensure creates metadata only: " + key)
	for good: String in RG.IDS:
		_expect(not p["stocks"].has(good), "Ensure must not seed " + good)
	var once: Dictionary = p.duplicate(true)
	RG.ensure(p)
	_expect(p == once, "Ensure is idempotent")
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(p))
	_expect(RG.validate(loaded).is_empty(), "JSON-shaped save is valid")
	var snapshot: Dictionary = p.duplicate(true)
	RG.report(p)
	RG.validate(p)
	_expect(p == snapshot, "Report and validation are read-only")
	p["industry"] = "timber"
	RG.ensure(p)
	_expect(p["regionalGoods"]["specialty"] == "fine_timber", "Actual industry wins")
	for bad: float in [NAN, INF, -1.0]:
		var broken: Dictionary = _port("fishery")
		broken["stocks"]["food"] = bad
		_expect(not RG.validate(broken).is_empty(), "Reject invalid stock quantity")
	var broken: Dictionary = _port("fishery")
	broken["cash"] = 0.5
	_expect(not RG.validate(broken).is_empty(), "Reject fractional coin balances")
	broken = _port("fishery")
	broken["availableWorkers"] = NAN
	_expect(not RG.validate(broken).is_empty(), "Reject nonfinite workforce")
	broken = _port("fishery")
	RG.ensure(broken)
	broken["regionalGoods"]["needLimit"] = INF
	_expect(not RG.validate(broken).is_empty(), "Reject nonfinite need limit")
	broken["regionalGoods"]["needLimit"] = 1.0
	broken["regionalGoods"]["lastConsumption"] = {"unknown_product": 1.0}
	_expect(not RG.validate(broken).is_empty(), "Reject unknown regional usage")
	broken["regionalGoods"]["lastConsumption"] = {"fine_timber": NAN}
	_expect(not RG.validate(broken).is_empty(), "Reject nonfinite recorded usage")


func _test_industries() -> void:
	var mapping: Dictionary = {
		"fishery": "preserved_fish",
		"timber": "fine_timber",
		"agriculture": "medicinal_plants",
		"refinery": "lacquer",
		"trade": "lacquer",
		"foundry": "",
		"shipyard": ""
	}
	for industry: String in mapping:
		var p: Dictionary = _port(industry)
		var before: Dictionary = p.duplicate(true)
		RG.daily(p)
		_audit(before, p)
		var r: Dictionary = RG.report(p)
		var expected: String = mapping[industry]
		_expect(r["specialty"] == expected, "Geographic specialty: " + industry)
		var production: Dictionary = r["lastProduction"]
		if expected.is_empty():
			_expect(production.is_empty(), "No generic harvest: " + industry)
		else:
			_expect(production.size() == 1, "One local production chain")
			_expect(float(production.get(expected, 0.0)) > 0.0, "Local output: " + industry)


func _test_denied_production() -> void:
	for reason: String in ["workers", "cash", "inputs", "specialists", "yard", "buffer"]:
		var p: Dictionary = _port("fishery")
		match reason:
			"workers":
				p["availableWorkers"] = 0.0
			"cash":
				p["cash"] = 0
			"inputs":
				p["stocks"]["food"] = 0.0
			"specialists":
				p["availableSpecialists"] = 0.0
			"yard":
				p["_yardWorkersUsed"] = p["availableWorkers"]
			"buffer":
				p["stocks"]["preserved_fish"] = 1000.0
		var before: Dictionary = p.duplicate(true)
		RG.daily(p)
		_audit(before, p)
		_expect(RG.report(p)["lastProduction"].is_empty(), "Blocked production: " + reason)
	var lacquer: Dictionary = _port("refinery")
	lacquer["stocks"]["charcoal"] = 0.0
	var before: Dictionary = lacquer.duplicate(true)
	RG.daily(lacquer)
	_audit(before, lacquer)
	_expect(RG.report(lacquer)["lastProduction"].is_empty(), "No imagined charcoal")
	var capped: Dictionary = _port("agriculture")
	RG.ensure(capped)
	capped["regionalGoods"]["needLimit"] = 0.0
	before = capped.duplicate(true)
	RG.daily(capped)
	_audit(before, capped)
	_expect(RG.report(capped)["lastProduction"].is_empty(), "Zero need stops workshop")


func _test_cash_and_fractional_days() -> void:
	var p: Dictionary = _port("fishery")
	p["cash"] = 1
	var before: Dictionary = p.duplicate(true)
	RG.daily(p)
	_audit(before, p)
	_expect(RG.report(p)["lastProduction"].is_empty(), "Cannot afford both purse groups")
	p = _port("fishery")
	p["cash"] = 2
	before = p.duplicate(true)
	RG.daily(p)
	_audit(before, p)
	_expect(
		float(RG.report(p)["lastProduction"].get("preserved_fish", 0.0)) > 0.0,
		"Affordable fractional batch"
	)
	var full: Dictionary = _port("agriculture")
	full["availableWorkers"] = 0.2
	full["availableSpecialists"] = 0.0
	var half: Dictionary = full.duplicate(true)
	var full_before: Dictionary = full.duplicate(true)
	var half_before: Dictionary = half.duplicate(true)
	RG.daily(full, 1.0)
	RG.daily(half, 0.5)
	_audit(full_before, full)
	_audit(half_before, half)
	var full_output: float = float(RG.report(full)["lastProduction"].get("medicinal_plants", 0.0))
	var half_output: float = float(RG.report(half)["lastProduction"].get("medicinal_plants", 0.0))
	_expect(_near(full_output, 1.0), "One fifth worker supplies one farmer lot per day")
	_expect(_near(half_output, full_output * 0.5), "Fractional days scale real labor")
	var team: Dictionary = _port("fishery")
	team["workforce"] = 1000.0
	team["availableWorkers"] = 20.0
	team["availableSpecialists"] = 20.0
	before = team.duplicate(true)
	RG.daily(team, 0.1)
	_audit(before, team)
	_expect(_near(float(RG.report(team)["workersUsed"]), RG.TEAM), "Team cap binds")


func _stock_civilian_goods(port: Dictionary, quantity: float) -> void:
	for good: String in RG.IDS:
		port["stocks"][good] = quantity


func _test_household_demand() -> void:
	for purse: int in [0, 9]:
		var poor: Dictionary = _port("foundry")
		poor["householdPurse"] = purse
		_stock_civilian_goods(poor, 100.0)
		var before: Dictionary = poor.duplicate(true)
		RG.daily(poor)
		_audit(before, poor)
		_expect(RG.report(poor)["lastConsumption"].is_empty(), "Poor purse is protected")
		_expect(int(poor["householdPurse"]) == purse, "No debt or forced luxury bill")
	var empty: Dictionary = _port("shipyard")
	empty["householdPurse"] = 1000000
	var before: Dictionary = empty.duplicate(true)
	RG.daily(empty)
	_audit(before, empty)
	_expect(_near(float(RG.report(empty)["satisfaction"]), 0.0), "Missing optional goods")
	var satisfied: Dictionary = _port("foundry")
	satisfied["householdPurse"] = 1000000
	_stock_civilian_goods(satisfied, 10.0)
	var oversupplied: Dictionary = satisfied.duplicate(true)
	_stock_civilian_goods(oversupplied, 1000.0)
	var satisfied_before: Dictionary = satisfied.duplicate(true)
	var oversupplied_before: Dictionary = oversupplied.duplicate(true)
	RG.daily(satisfied)
	RG.daily(oversupplied)
	_audit(satisfied_before, satisfied)
	_audit(oversupplied_before, oversupplied)
	var normal: Dictionary = RG.report(satisfied)
	var excess: Dictionary = RG.report(oversupplied)
	_expect(_near(float(normal["satisfaction"]), 1.0), "Affordable households satisfy need")
	_expect(
		normal["lastConsumption"] == excess["lastConsumption"],
		"Oversupply never creates extra household need"
	)
	_expect(float(excess["usedUnits"]) <= 2.0 + TOL, "Finite daily civilian use")
	_expect(int(excess["lastSpent"]) > 0, "Actual coins paid to harbor")
	var copy: Dictionary = RG.report(satisfied)
	copy["lastConsumption"]["fine_timber"] = 999.0
	_expect(
		float(RG.report(satisfied)["lastConsumption"].get("fine_timber", 0.0)) < 999.0,
		"Report cannot mutate recorded wellbeing use"
	)


func _test_invalid_steps() -> void:
	for days: float in [0.0, -1.0, INF, NAN, 366.0]:
		var p: Dictionary = _port("agriculture")
		var before: Dictionary = p.duplicate(true)
		RG.daily(p, days)
		_expect(p == before, "Invalid time step must not mutate port")
