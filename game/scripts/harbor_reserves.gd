extends RefCounted

const GoodsData = preload("res://scripts/goods.gd")
const IndustryDataSource = preload("res://scripts/industry_data.gd")

const SCHEMA: int = 1
const ESSENTIALS: Array[String] = ["food", "supplies", "fuel", "ammo"]
const POLICIES: Array[String] = ["security", "commercial"]
const PRIORITY: Dictionary = {
	"food": 4.0, "supplies": 3.0, "fuel": 2.0, "ammo": 1.0
}
const DEFAULT_RESUPPLY_DAYS: float = 4.0
const MIN_RESUPPLY_DAYS: float = 1.0
const MAX_RESUPPLY_DAYS: float = 14.0
const MAX_AMOUNT: float = 1.0e12
const EPSILON: float = 0.000001


# Only this method and set_policy modify port.reserves.
# No method modifies stocks, publicStores, purses or live production.
static func ensure(port: Dictionary) -> void:
	port["reserves"] = _settings(port)


static func report(port: Dictionary) -> Dictionary:
	var settings: Dictionary = _settings(port)
	var stocks: Dictionary = _dictionary(port.get("stocks", {}))
	var public_stores: Dictionary = _dictionary(port.get("publicStores", {}))
	var observed: Dictionary = _dictionary(settings.get("observedDemand", {}))
	var incoming: Dictionary = _dictionary(settings.get("incoming", {}))
	var contracted: Dictionary = _dictionary(settings.get("contractedLots", {}))
	var days: float = float(settings["resupplyDays"])
	var security: bool = str(settings["policy"]) == "security"
	var operating_days: float = minf(1.5, maxf(0.5, days * 0.25))
	if not security:
		operating_days = minf(0.75, maxf(0.25, days * 0.125))

	var workforce: float = _amount(port.get("workforce", 10.0), 10.0)
	var household_food: float = maxf(
		0.5,
		maxf(10.0, workforce)
		* float(IndustryDataSource.DAILY_FOOD_PER_PERSON)
	)
	var rows: Dictionary = {}

	for key: Variant in GoodsData.ITEMS.keys():
		var good: String = str(key)
		var stock: float = _amount(stocks.get(good, 0.0))
		var public_stock: float = _amount(public_stores.get(good, 0.0))
		var arriving: float = _amount(incoming.get(good, 0.0))
		var committed: float = minf(stock, _amount(contracted.get(good, 0.0)))
		var demand: float = _amount(observed.get(good, 0.0))
		if good == "food":
			demand += household_food
		if demand <= EPSILON:
			demand = 0.0

		var essential: bool = ESSENTIALS.has(good)
		if not essential and stock + public_stock + arriving + committed + demand == 0.0:
			continue

		var free_stock: float = maxf(0.0, stock - committed)
		var operating_target: float = 0.0
		var public_target: float = 0.0
		if essential:
			operating_target = demand * operating_days
			public_target = demand * days * (1.0 if security else 0.5)

		# Public inventory cannot silently substitute for commercial operating stock.
		var operating_protected: float = minf(free_stock, operating_target)
		var protected: float = committed + operating_protected
		var available: float = maxf(0.0, stock - protected)
		var reason: String = "No daily use; only actual contracted lots are protected."
		if demand > 0.0:
			if essential:
				reason = "Operating buffer protected; public targets are advisory."
			else:
				reason = "Observed use reported; no essential operating holdback."
		if committed > 0.0:
			reason += " Contracted lots are excluded from new sale quotes."

		rows[good] = {
			"dailyDemand": demand,
			"noDemand": demand == 0.0,
			"commercialStock": stock,
			"publicStock": public_stock,
			"incoming": arriving,
			"contracted": committed,
			"commercialCoverageDays": _coverage(free_stock, demand),
			"publicCoverageDays": _coverage(public_stock, demand),
			"operatingTarget": operating_target,
			"publicTarget": public_target,
			"operatingProtected": operating_protected,
			"protected": protected,
			"exportable": available,
			"reason": reason,
		}

	return {
		"schema": SCHEMA,
		"policy": settings["policy"],
		"resupplyDays": days,
		"operatingDays": operating_days,
		"householdFoodPerDay": household_food,
		"goods": rows,
		"reason": "Public release requires an actual transfer; incoming is not coverage.",
	}


# Quote for NEW, uncommitted exports. Existing named contracts use root's
# actual-lot fulfillment path, not an unrestricted bypass of this quote.
static func exportable(port: Dictionary, good: String) -> float:
	var snapshot: Dictionary = report(port)
	var rows: Dictionary = _dictionary(snapshot["goods"])
	var row: Dictionary = _dictionary(rows.get(good, {}))
	return _amount(row.get("exportable", 0.0))


# Fractional workers mean worker-days per day, matching recipe labor_days.
# paid_workers is the feasible shared pool AFTER public/yard commitments.
# Root allocates the remaining workforce after these floors, not on top of it.
static func allocation_floors(port: Dictionary, paid_workers: float) -> Dictionary:
	var budget: float = _amount(paid_workers) * 0.25
	var floors: Dictionary = {}
	if budget <= EPSILON:
		return floors

	var settings: Dictionary = _settings(port)
	var recipes: Array[Dictionary] = _recipe_list(
		settings.get("availableRecipes", [])
	)
	var available: Dictionary = {}
	for recipe: Dictionary in recipes:
		available[str(recipe["good"])] = true
	if available.is_empty():
		return floors

	var snapshot: Dictionary = report(port)
	var rows: Dictionary = _dictionary(snapshot["goods"])
	var days: float = float(snapshot["resupplyDays"])
	var candidates: Array[Dictionary] = []
	var total_weight: float = 0.0

	for good: String in ESSENTIALS:
		if not available.has(good):
			continue
		var row: Dictionary = _dictionary(rows.get(good, {}))
		var demand: float = _amount(row.get("dailyDemand", 0.0))
		if demand <= EPSILON:
			continue

		var free_stock: float = maxf(
			0.0,
			_amount(row.get("commercialStock", 0.0))
			- _amount(row.get("contracted", 0.0))
		)
		var operating_target: float = _amount(row.get("operatingTarget", 0.0))
		var public_target: float = _amount(row.get("publicTarget", 0.0))
		var public_stock: float = _amount(row.get("publicStock", 0.0))
		var shortage: float = maxf(
			maxf(0.0, operating_target - free_stock),
			maxf(0.0, operating_target + public_target - free_stock - public_stock)
		)
		if shortage <= EPSILON:
			continue

		var definition: Dictionary = _dictionary(GoodsData.ITEMS.get(good, {}))
		var raw_inputs: Variant = definition.get("inputs", {})
		var raw_labor: Variant = definition.get("labor", {})
		if _amounts_error(raw_inputs, "inputs") != "":
			continue
		if _amounts_error(raw_labor, "labor", false) != "":
			continue
		var inputs: Dictionary = _dictionary(raw_inputs)
		var labor: Dictionary = _dictionary(raw_labor)
		var labor_days: float = float(GoodsData.labor_days(labor))
		if not is_finite(labor_days) or labor_days <= EPSILON:
			continue

		var weight: float = float(PRIORITY[good])
		var requested_output: float = demand + shortage / days
		candidates.append({
			"good": good,
			"inputs": inputs,
			"laborDays": labor_days,
			"needWorkers": minf(budget, requested_output * labor_days),
			"weight": weight,
		})
		total_weight += weight

	# Reserve only opening commercial ingredients. Public/incoming goods and
	# outputs of other candidate recipes never become fictional opening inputs.
	var stocks: Dictionary = _dictionary(port.get("stocks", {}))
	var contracted: Dictionary = _dictionary(settings.get("contractedLots", {}))
	var remaining_inputs: Dictionary = {}
	for key: Variant in GoodsData.ITEMS.keys():
		var good: String = str(key)
		remaining_inputs[good] = maxf(
			0.0,
			_amount(stocks.get(good, 0.0))
			- _amount(contracted.get(good, 0.0))
		)

	var remaining_budget: float = budget
	var remaining_weight: float = total_weight
	for candidate: Dictionary in candidates:
		if remaining_budget <= EPSILON or remaining_weight <= EPSILON:
			break
		var weight: float = float(candidate["weight"])
		var quota: float = remaining_budget * weight / remaining_weight
		remaining_weight = maxf(0.0, remaining_weight - weight)
		var workers: float = minf(quota, float(candidate["needWorkers"]))
		var labor_days: float = float(candidate["laborDays"])
		var inputs: Dictionary = _dictionary(candidate["inputs"])

		for ingredient_key: Variant in inputs.keys():
			var ingredient: String = str(ingredient_key)
			var quantity: float = float(inputs[ingredient_key])
			if quantity > 0.0:
				workers = minf(
					workers,
					_amount(remaining_inputs.get(ingredient, 0.0))
					* labor_days / quantity
				)
		if workers <= EPSILON:
			continue

		floors[str(candidate["good"])] = workers
		remaining_budget = maxf(0.0, remaining_budget - workers)
		for ingredient_key: Variant in inputs.keys():
			var ingredient: String = str(ingredient_key)
			var used: float = workers / labor_days * float(inputs[ingredient_key])
			remaining_inputs[ingredient] = maxf(
				0.0, _amount(remaining_inputs.get(ingredient, 0.0)) - used
			)

	return floors


# Local configuration only. Root must check authority before calling.
static func set_policy(port: Dictionary, policy: String) -> Dictionary:
	var normalized: String = policy.strip_edges().to_lower()
	if not POLICIES.has(normalized):
		var settings: Dictionary = _settings(port)
		return {
			"ok": false,
			"message": "Unknown reserve policy.",
			"policy": settings["policy"],
		}
	ensure(port)
	var reserves: Dictionary = _dictionary(port["reserves"])
	reserves["policy"] = normalized
	return {
		"ok": true,
		"message": "Reserve policy: " + normalized,
		"policy": normalized,
	}


# Empty string means valid. This diagnostic does not repair or mutate inputs.
static func validate(port: Dictionary) -> String:
	var raw_value: Variant = port.get("reserves", {})
	if not (raw_value is Dictionary):
		return "reserves must be a Dictionary."
	var raw: Dictionary = _dictionary(raw_value)
	if raw.has("schema"):
		var schema: Variant = raw["schema"]
		if not _valid_amount(schema) or float(schema) != float(SCHEMA):
			return "Unsupported reserves schema."
	if raw.has("policy") and not POLICIES.has(str(raw["policy"])):
		return "Unknown reserve policy."
	if raw.has("resupplyDays"):
		var days: Variant = raw["resupplyDays"]
		if not _valid_amount(days):
			return "resupplyDays must be finite and nonnegative."
		if float(days) < MIN_RESUPPLY_DAYS or float(days) > MAX_RESUPPLY_DAYS:
			return "resupplyDays is outside 1..14."
	if port.has("workforce") and not _valid_amount(port["workforce"]):
		return "workforce must be a finite nonnegative scalar."

	for field: String in ["stocks", "publicStores"]:
		if port.has(field):
			var error: String = _amounts_error(port[field], field)
			if error != "":
				return error
	for field: String in ["observedDemand", "incoming", "contractedLots"]:
		if raw.has(field):
			var error: String = _amounts_error(raw[field], field)
			if error != "":
				return error

	if raw.has("availableRecipes"):
		if not (raw["availableRecipes"] is Array):
			return "availableRecipes must be an Array."
		var records: Array = raw["availableRecipes"]
		for value: Variant in records:
			if not (value is Dictionary):
				return "availableRecipes contains a malformed record."
			var record: Dictionary = _dictionary(value)
			if not GoodsData.ITEMS.has(str(record.get("good", ""))):
				return "availableRecipes contains an unknown good."
			var share: Variant = record.get("share", null)
			if not _valid_amount(share) or float(share) <= 0.0:
				return "Recipe share must be finite and positive."

	var committed: Dictionary = _dictionary(raw.get("contractedLots", {}))
	var stocks: Dictionary = _dictionary(port.get("stocks", {}))
	for key: Variant in committed.keys():
		if _amount(committed[key]) > _amount(stocks.get(key, 0.0)) + EPSILON:
			return "Contracted lots exceed actual commercial stock: " + str(key)
	return ""


static func _settings(port: Dictionary) -> Dictionary:
	var raw: Dictionary = _dictionary(port.get("reserves", {}))
	var policy: String = str(raw.get("policy", "security"))
	if not POLICIES.has(policy):
		policy = "security"
	var result: Dictionary = {
		"schema": SCHEMA,
		"policy": policy,
		"resupplyDays": clampf(
			_amount(raw.get("resupplyDays", DEFAULT_RESUPPLY_DAYS), DEFAULT_RESUPPLY_DAYS),
			MIN_RESUPPLY_DAYS,
			MAX_RESUPPLY_DAYS
		),
	}
	for field: String in ["observedDemand", "incoming", "contractedLots"]:
		if raw.has(field):
			result[field] = _amounts(raw[field])
	if raw.has("availableRecipes"):
		result["availableRecipes"] = _recipe_list(raw["availableRecipes"])
	return result


static func _recipe_list(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	var values: Array = value
	var shares: Dictionary = {}
	for entry_value: Variant in values:
		var entry: Dictionary = _dictionary(entry_value)
		var good: String = str(entry.get("good", ""))
		var share: float = _amount(entry.get("share", 0.0))
		if GoodsData.ITEMS.has(good) and share > 0.0:
			shares[good] = minf(MAX_AMOUNT, _amount(shares.get(good, 0.0)) + share)
	for key: Variant in shares.keys():
		result.append({"good": str(key), "share": float(shares[key])})
	return result


static func _amounts(value: Variant) -> Dictionary:
	var source: Dictionary = _dictionary(value)
	var result: Dictionary = {}
	for key: Variant in source.keys():
		var good: String = str(key)
		var quantity: float = _amount(source[key])
		if GoodsData.ITEMS.has(good) and quantity > 0.0:
			result[good] = quantity
	return result


static func _amounts_error(
	value: Variant, field: String, goods_only: bool = true
) -> String:
	if not (value is Dictionary):
		return field + " must be a Dictionary."
	var quantities: Dictionary = _dictionary(value)
	for key: Variant in quantities.keys():
		if goods_only and not GoodsData.ITEMS.has(str(key)):
			return field + " contains an unknown good: " + str(key)
		if not _valid_amount(quantities[key]):
			return field + " contains a malformed amount: " + str(key)
	return ""


static func _valid_amount(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0 and number <= MAX_AMOUNT


static func _amount(value: Variant, fallback: float = 0.0) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return fallback
	var number: float = float(value)
	if not is_finite(number):
		return fallback
	return clampf(number, 0.0, MAX_AMOUNT)


static func _coverage(quantity: float, daily_demand: float) -> float:
	return quantity / daily_demand if daily_demand > EPSILON else 0.0


static func _dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}
