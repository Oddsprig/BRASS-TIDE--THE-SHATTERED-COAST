class_name RegionalGoods
extends RefCounted
const Goods=preload("res://scripts/goods.gd")
const Economy=preload("res://scripts/economy.gd")
const Money=preload("res://scripts/money.gd")

# Goods, Economy and Money refer to the baseline APIs in the inline brief.
# Production/consumption quantities are fractional lots; all transfers are coins.
const IDS := [
	"preserved_fish", "fine_timber", "lacquer", "medicinal_plants"
]
const EXPERT_ROLES := [
	"powder worker", "gunsmith", "mechanic", "foreman", "engineer", "master shipwright"
]
const TEAM := 4.0
const BUFFER_DAYS := 3.0
const NEED_PER_WORKER := 0.02
const MAX_DAILY_NEED := 12.0
const PURSE_SHARE := 0.08
const MAX_PURSE_SHARE := 0.20
const MAX_DAYS := 365.0
const MAX_VALUE := 1000000000000.0
const MAX_COINS := 1000000000000
const EPS := 0.0000001


static func specs() -> Dictionary:
	return {
		"preserved_fish": {
			"inputs": {"food": 1.0},
			"labor": {"fisher": 0.10, "carpenter": 0.04, "foreman": 0.01},
			"weight": 1.0
		},
		"fine_timber": {
			"inputs": {"timber": 0.5},
			"labor": {"carpenter": 0.40,"foreman":0.02},
			"weight": 1.0
		},
		"lacquer": {
			"inputs": {"logs": 0.25, "charcoal": 0.25},
			"labor": {
				"woodcutter": 0.05,
				"refiner": 0.08,
				"carpenter": 0.08, "foreman":0.02
			},
			"weight": 0.5
		},
		"medicinal_plants": {
			"inputs": {},
			"labor": {"farmer": 0.20},
			"weight": 0.25
		}
	}


static func ensure(port: Dictionary) -> void:
	# Metadata only. Never creates stocks, workers or coins.
	if port.has("regionalGoods") and not (port["regionalGoods"] is Dictionary):
		return
	var state: Dictionary = port.get("regionalGoods", {})
	var defaults: Dictionary = {
		"lastProduction": {},
		"lastConsumption": {},
		"lastWages": 0,
		"lastSpent": 0,
		"lastDays": 0.0,
		"lastNeed": 0.0,
		"lastWorkers": 0.0,
		"lastSpecialists": 0.0
	}
	for key: String in defaults:
		if not state.has(key):
			state[key] = defaults[key]
	state["specialty"] = _specialty(port)
	port["regionalGoods"] = state


static func daily(port: Dictionary, days: float = 1.0) -> void:
	# Invalid steps are strict no-ops, including metadata.
	if not is_finite(days) or days <= 0.0 or days > MAX_DAYS:
		return
	if not validate(port).is_empty():
		return
	ensure(port)
	var state: Dictionary = port["regionalGoods"]
	state["lastProduction"] = {}
	state["lastConsumption"] = {}
	state["lastWages"] = 0
	state["lastSpent"] = 0
	state["lastDays"] = days
	state["lastWorkers"] = 0.0
	state["lastSpecialists"] = 0.0
	var need: float = _need_per_day(port)
	state["lastNeed"] = need * days
	var good: String = _specialty(port)
	if not good.is_empty() and need > EPS:
		var target: float = need * BUFFER_DAYS / float(IDS.size())
		_produce(port, state, good, days, target)
	_consume(port, state, days, need)


static func report(port: Dictionary) -> Dictionary:
	# Read-only, with independent nested dictionaries.
	var error: String = validate(port)
	if not error.is_empty():
		return {"error": error}
	var state: Dictionary = port.get("regionalGoods", {})
	var production: Dictionary = state.get("lastProduction", {})
	var consumption: Dictionary = state.get("lastConsumption", {})
	var used: float = 0.0
	for value: Variant in consumption.values():
		used += float(value)
	var need: float = float(state.get("lastNeed", 0.0))
	var good: String = _specialty(port)
	var target: float = 0.0
	var local_stock: float = 0.0
	if not good.is_empty():
		target = _need_per_day(port) * BUFFER_DAYS / float(IDS.size())
		local_stock = float(port["stocks"].get(good, 0.0))
	var stocks: Dictionary = {}
	for item: String in IDS:
		stocks[item] = float(port["stocks"].get(item, 0.0))
	return {
		"specialty": good,
		"lastProduction": production.duplicate(true),
		"lastConsumption": consumption.duplicate(true),
		"lastWages": int(state.get("lastWages", 0)),
		"lastSpent": int(state.get("lastSpent", 0)),
		"days": float(state.get("lastDays", 0.0)),
		"workersUsed": float(state.get("lastWorkers", 0.0)),
		"specialistsUsed": float(state.get("lastSpecialists", 0.0)),
		"needUnits": need,
		"usedUnits": used,
		"unmetUnits": maxf(0.0, need - used),
		"satisfaction": clampf(used / need, 0.0, 1.0) if need > EPS else 1.0,
		"bufferTarget": target,
		"surplusUnits": maxf(0.0, local_stock - target),
		"stocks": stocks
	}


static func validate(port: Dictionary) -> String:
	for key: String in ["workforce", "availableWorkers", "availableSpecialists"]:
		if not _number(port.get(key)):
			return "Regional goods: invalid " + key
	for key: String in ["_yardWorkersUsed", "_yardSpecialistsUsed"]:
		if not _number(port.get(key, 0.0)):
			return "Regional goods: invalid " + key
	if typeof(port.get("industry")) != TYPE_STRING:
		return "Regional goods: invalid industry"
	if float(port["availableWorkers"]) > float(port["workforce"]) + EPS:
		return "Regional goods: available workers exceed workforce"
	if float(port["availableSpecialists"]) > float(port["workforce"]) + EPS:
		return "Regional goods: available specialists exceed workforce"
	for key: String in ["cash", "householdPurse", "expertPurse"]:
		if not _coins(port.get(key)):
			return "Regional goods: invalid " + key
	if port.has("governmentPurse") and not _coins(port["governmentPurse"]):
		return "Regional goods: invalid governmentPurse"
	if not _quantity_map(port.get("stocks")):
		return "Regional goods: invalid stocks"
	if not _quantity_map(port.get("employed")):
		return "Regional goods: invalid employed"
	# Legacy saves may omit the entire regional state.
	if not port.has("regionalGoods"):
		return ""
	if not (port["regionalGoods"] is Dictionary):
		return "Regional goods: invalid regionalGoods"
	var state: Dictionary = port["regionalGoods"]
	var allowed: Array = [
		"specialty", "lastProduction", "lastConsumption", "lastWages",
		"lastSpent", "lastDays", "lastNeed", "lastWorkers",
		"lastSpecialists", "needLimit"
	]
	for key: Variant in state:
		if not allowed.has(key):
			return "Regional goods: unknown state field " + str(key)
	if state.has("specialty"):
		if typeof(state["specialty"]) != TYPE_STRING:
			return "Regional goods: invalid specialty"
		var good: String = state["specialty"]
		if not good.is_empty() and not IDS.has(good):
			return "Regional goods: unknown specialty"
	for key: String in ["lastProduction", "lastConsumption"]:
		if state.has(key) and not _quantity_map(state[key], true):
			return "Regional goods: invalid " + key
	for key: String in ["lastWages", "lastSpent"]:
		if state.has(key) and not _coins(state[key]):
			return "Regional goods: invalid " + key
	for key: String in [
		"lastDays", "lastNeed", "lastWorkers", "lastSpecialists", "needLimit"
	]:
		if state.has(key) and not _number(state[key]):
			return "Regional goods: invalid " + key
	if float(state.get("lastDays", 0.0)) > MAX_DAYS:
		return "Regional goods: invalid lastDays"
	var workers: float = float(state.get("lastWorkers", 0.0))
	if workers > TEAM + EPS:
		return "Regional goods: workshop team exceeds cap"
	if float(state.get("lastSpecialists", 0.0)) > workers + EPS:
		return "Regional goods: specialists exceed workshop workers"
	var consumed: Dictionary = state.get("lastConsumption", {})
	var total: float = 0.0
	for value: Variant in consumed.values():
		total += float(value)
	if total > float(state.get("lastNeed", 0.0)) + EPS:
		return "Regional goods: consumption exceeds recorded need"
	return ""


static func _number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0 and number <= MAX_VALUE


static func _coins(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))


static func _quantity_map(value: Variant, products_only: bool = false) -> bool:
	if not (value is Dictionary):
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			return false
		if products_only and not IDS.has(str(key)):
			return false
		if not _number(value[key]):
			return false
	return true


static func _specialty(port: Dictionary) -> String:
	match str(port.get("industry", "")):
		"fishery":
			return "preserved_fish"
		"timber":
			return "fine_timber"
		"agriculture":
			return "medicinal_plants"
		"refinery", "trade":
			return "lacquer"
	return ""


static func _need_per_day(port: Dictionary) -> float:
	# Conservative workforce proxy; needLimit is an optional whole-port cap.
	var need: float = minf(
		MAX_DAILY_NEED, float(port["workforce"]) * NEED_PER_WORKER
	)
	var state: Dictionary = port.get("regionalGoods", {})
	if state.has("needLimit"):
		need = minf(need, float(state["needLimit"]))
	return need


static func _terms(good: String) -> Dictionary:
	if not Goods.ITEMS.has(good):
		return {}
	var cost_value: Variant = Goods.labor_cost(Goods.ITEMS[good].labor)
	var days_value: Variant = Goods.labor_days(Goods.ITEMS[good].labor)
	if not _number(cost_value) or not _number(days_value):
		return {}
	var cost: float = float(cost_value)
	var workdays: float = float(days_value)
	if cost <= 0.0 or workdays <= 0.0:
		return {}
	var recipe: Dictionary = specs()[good]
	var labor: Dictionary = recipe["labor"]
	var checked_cost: float = 0.0
	var checked_days: float = 0.0
	var expert_cost: float = 0.0
	var expert_days: float = 0.0
	for role: String in labor:
		var wage: Variant = Goods.WAGES.get(role)
		if not _number(wage) or float(wage) <= 0.0:
			return {}
		var role_days: float = float(labor[role])
		var role_cost: float = role_days * float(wage)
		checked_days += role_days
		checked_cost += role_cost
		if EXPERT_ROLES.has(role):
			expert_cost += role_cost
			expert_days += role_days
	# Fail closed if root integration supplied a different labor contract.
	if absf(checked_days - workdays) > EPS:
		return {}
	if absf(checked_cost - cost) > EPS:
		return {}
	return {
		"days": workdays,
		"expertDays": expert_days,
		"household": maxf(0.0, cost - expert_cost),
		"expert": expert_cost
	}


static func _payroll(terms: Dictionary, quantity: float) -> Dictionary:
	# Each paid purse group rounds upward, never granting free fractional work.
	var household: int = ceili(float(terms["household"]) * quantity)
	var expert: int = ceili(float(terms["expert"]) * quantity)
	return {
		"household": household,
		"expert": expert,
		"total": household + expert
	}


static func _fits(port: Dictionary, terms: Dictionary, quantity: float) -> bool:
	var pay: Dictionary = _payroll(terms, quantity)
	return (
		int(pay["total"]) <= int(port["cash"])
		and int(pay["household"]) <= MAX_COINS - int(port["householdPurse"])
		and int(pay["expert"]) <= MAX_COINS - int(port["expertPurse"])
	)


static func _produce(
	port: Dictionary, state: Dictionary, good: String,
	days: float, target: float
) -> void:
	var terms: Dictionary = _terms(good)
	if terms.is_empty():
		return
	var workers: float = minf(
		TEAM,
		maxf(
			0.0,
			float(port["availableWorkers"])
			- float(port.get("_yardWorkersUsed", 0.0))
		)
	)
	var specialists: float = maxf(
		0.0,
		float(port["availableSpecialists"])
		- float(port.get("_yardSpecialistsUsed", 0.0))
	)
	var stocks: Dictionary = port["stocks"]
	var quantity: float = maxf(0.0, target - float(stocks.get(good, 0.0)))
	quantity = minf(quantity, workers * days / float(terms["days"]))
	var expert_days: float = float(terms["expertDays"])
	if expert_days > 0.0:
		quantity = minf(quantity, specialists * days / expert_days)
	var unit_bill: float = float(terms["household"]) + float(terms["expert"])
	quantity = minf(quantity, float(port["cash"]) / unit_bill)
	var recipe: Dictionary = specs()[good]
	var inputs: Dictionary = recipe["inputs"]
	for ingredient: String in inputs:
		quantity = minf(
			quantity,
			float(stocks.get(ingredient, 0.0)) / float(inputs[ingredient])
		)
	if quantity <= EPS:
		return
	# Group rounding may make the raw cash bound too optimistic.
	if not _fits(port, terms, quantity):
		var low: float = 0.0
		var high: float = quantity
		for iteration: int in range(48):
			var middle: float = (low + high) * 0.5
			if _fits(port, terms, middle):
				low = middle
			else:
				high = middle
		quantity = low
	if quantity <= EPS:
		return
	var pay: Dictionary = _payroll(terms, quantity)
	if not _pay(port, pay):
		return
	# Commit material and workforce changes only after successful payroll.
	for ingredient: String in inputs:
		stocks[ingredient] = maxf(
			0.0,
			float(stocks.get(ingredient, 0.0))
			- float(inputs[ingredient]) * quantity
		)
	stocks[good] = float(stocks.get(good, 0.0)) + quantity
	var workers_used: float = quantity * float(terms["days"]) / days
	var specialists_used: float = quantity * expert_days / days
	port["availableWorkers"] = maxf(
		0.0, float(port["availableWorkers"]) - ceilf(workers_used)
	)
	port["availableSpecialists"] = maxf(
		0.0, float(port["availableSpecialists"]) - ceilf(specialists_used)
	)
	var employed: Dictionary = port["employed"]
	var labor: Dictionary = recipe["labor"]
	for role: String in labor:
		employed[role] = (
			float(employed.get(role, 0.0))
			+ float(labor[role]) * quantity / days
		)
	state["lastProduction"] = {good: quantity}
	state["lastWages"] = int(pay["total"])
	state["lastWorkers"] = workers_used
	state["lastSpecialists"] = specialists_used


static func _consume(
	port: Dictionary, state: Dictionary, days: float, need: float
) -> void:
	var share: float = minf(MAX_PURSE_SHARE, PURSE_SHARE * days)
	var budget: int = floori(float(port["householdPurse"]) * share)
	var wanted: float = need * days / float(IDS.size())
	var remaining: int = IDS.size()
	var stocks: Dictionary = port["stocks"]
	var consumption: Dictionary = state["lastConsumption"]
	for good: String in IDS:
		var allowance: int = floori(float(budget) / float(remaining))
		remaining -= 1
		if allowance <= 0 or wanted <= EPS:
			continue
		var stock: float = float(stocks.get(good, 0.0))
		if stock <= EPS:
			continue
		# "buy" means the household is buying from the harbor.
		var quote: Variant = Economy.price(port, good, "buy")
		if not _number(quote) or float(quote) <= 0.0:
			continue
		var price: int = ceili(float(quote))
		var quantity: float = minf(
			minf(wanted, stock), float(allowance) / float(price)
		)
		if quantity <= EPS:
			continue
		var spent: int = mini(allowance, ceili(quantity * float(price)))
		if spent <= 0:
			continue
		quantity = minf(quantity, float(spent) / float(price))
		if not _move(
			port, "householdPurse", "cash", spent,
			"Regional household purchase: " + good
		):
			continue
		stocks[good] = maxf(0.0, stock - quantity)
		consumption[good] = quantity
		state["lastSpent"] = int(state["lastSpent"]) + spent
		budget -= spent


static func _move(
	wallet: Dictionary, source: String, target: String,
	amount: int, reason: String
) -> bool:
	if amount == 0:
		return true
	if amount < 0:
		return false
	var source_before: int = int(wallet[source])
	var target_before: int = int(wallet[target])
	if source_before < amount or target_before > MAX_COINS - amount:
		return false
	# Verify the baseline transfer before publishing balances.
	var shadow: Dictionary = {"source": source_before, "target": target_before}
	Money.move(shadow, "source", shadow, "target", amount, reason)
	if not _coins(shadow.get("source")) or not _coins(shadow.get("target")):
		return false
	if int(shadow["source"]) != source_before - amount:
		return false
	if int(shadow["target"]) != target_before + amount:
		return false
	wallet[source] = int(shadow["source"])
	wallet[target] = int(shadow["target"])
	return true


static func _pay(port: Dictionary, pay: Dictionary) -> bool:
	var wallet: Dictionary = {
		"cash": int(port["cash"]),
		"householdPurse": int(port["householdPurse"]),
		"expertPurse": int(port["expertPurse"])
	}
	if not _move(
		wallet, "cash", "householdPurse", int(pay["household"]),
		"Regional workshop household wages"
	):
		return false
	if not _move(
		wallet, "cash", "expertPurse", int(pay["expert"]),
		"Regional workshop expert wages"
	):
		return false
	for key: String in wallet:
		port[key] = int(wallet[key])
	return true
