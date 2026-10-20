extends RefCounted
## Brass Tide static industry, equilibrium, occupation, and seeding definitions (v0.001).
## Extracted from economy.gd to keep module files comfortably below size limits.

const Goods = preload("res://scripts/goods.gd")

const GOOD_KEYS: Array[String] = [
	"food", "logs", "timber", "ore", "charcoal", "iron", "copper", "saltpeter",
	"sulfur", "gunpowder", "ammo", "crude", "fuel", "supplies", "engines", "guns"
]

const OCCUPATION_KEYS: Array[String] = [
	"farmer", "fisher", "woodcutter", "miner", "charcoal burner",
	"carpenter", "smelter", "refiner", "shipwright",
	"powder worker", "gunsmith", "mechanic",
	"foreman", "engineer", "master shipwright"
]

const SAILOR_WAGE: int = Goods.SAILOR_WAGE
const ORDINARY_WAGE: int = Goods.SAILOR_WAGE
const ROUNDS_PER_CASE: int = Goods.ROUNDS_PER_CASE
const WAGES: Dictionary = Goods.WAGES

const SEED_BUSINESS_WAGE_DAYS: int = 20
const SEED_HOUSEHOLD_WAGE_DAYS: int = 15
const SEED_EXPERT_WAGE_DAYS: int = 5
const SEED_GOVERNMENT_WAGE_DAYS: int = 40

const PERSON_DAYS_PER_FOOD_BALE: float = 12.5
const DAILY_FOOD_PER_PERSON: float = 1.0 / PERSON_DAYS_PER_FOOD_BALE
const WAGE_TAX_RATE: float = 0.05
const TRANSACTION_TAX_RATE: float = 0.08
const MAX_LEDGER_ENTRIES: int = 32

const BASE_EQUILIBRIUM: Dictionary = {
	"food": 120.0,
	"logs": 85.0,
	"timber": 75.0,
	"ore": 80.0,
	"charcoal": 65.0,
	"iron": 55.0,
	"copper": 36.0,
	"saltpeter": 36.0,
	"sulfur": 36.0,
	"gunpowder": 28.0,
	"ammo": 55.0,
	"crude": 70.0,
	"fuel": 75.0,
	"supplies": 65.0,
	"engines": 10.0,
	"guns": 14.0
}

const INDUSTRIES: Dictionary = {
	"fishery": {
		"name": "Fishery",
		"defaultSpecialty": "food",
		"stockMultipliers": {
			"food": 1.85, "logs": 1.0, "timber": 0.95, "supplies": 1.15, "fuel": 0.95,
			"iron": 0.65, "ammo": 0.75, "engines": 0.5, "guns": 0.5
		},
		"priceBias": {
			"food": 0.82, "supplies": 0.95, "iron": 1.08, "engines": 1.10, "guns": 1.08
		},
		"recipes": [
			{"good": "food", "share": 0.58},
			{"good": "logs", "share": 0.12},
			{"good": "timber", "share": 0.10},
			{"good": "supplies", "share": 0.12},
			{"good": "fuel", "share": 0.08}
		]
	},
	"agriculture": {
		"name": "Agriculture",
		"defaultSpecialty": "food",
		"stockMultipliers": {
			"food": 1.95, "logs": 1.25, "timber": 1.15, "charcoal": 1.1, "supplies": 1.15,
			"iron": 0.65, "ammo": 0.75, "engines": 0.5, "guns": 0.5
		},
		"priceBias": {
			"food": 0.80, "logs": 0.92, "timber": 0.94, "supplies": 0.94, "iron": 1.08, "engines": 1.10
		},
		"recipes": [
			{"good": "food", "share": 0.56},
			{"good": "logs", "share": 0.16},
			{"good": "timber", "share": 0.12},
			{"good": "charcoal", "share": 0.08},
			{"good": "supplies", "share": 0.08}
		]
	},
	"timber": {
		"name": "Timber",
		"defaultSpecialty": "timber",
		"stockMultipliers": {
			"food": 1.0, "logs": 1.95, "timber": 1.9, "charcoal": 1.5, "supplies": 1.35,
			"iron": 0.75, "engines": 0.55, "guns": 0.55
		},
		"priceBias": {
			"logs": 0.78, "timber": 0.78, "charcoal": 0.84, "supplies": 0.88, "iron": 1.06, "engines": 1.08
		},
		"recipes": [
			{"good": "logs", "share": 0.34},
			{"good": "timber", "share": 0.28},
			{"good": "charcoal", "share": 0.12},
			{"good": "supplies", "share": 0.10},
			{"good": "food", "share": 0.16}
		]
	},
	"foundry": {
		"name": "Foundry",
		"defaultSpecialty": "iron",
		"stockMultipliers": {
			"food": 0.85, "logs": 0.95, "timber": 0.9, "ore": 1.9, "charcoal": 1.5,
			"iron": 1.9, "copper": 1.75, "gunpowder": 1.15, "ammo": 1.55, "guns": 1.65, "engines": 1.15
		},
		"priceBias": {
			"ore": 0.82, "iron": 0.80, "copper": 0.84, "ammo": 0.86, "guns": 0.84,
			"engines": 0.94, "food": 1.12, "timber": 1.08
		},
		"recipes": [
			{"good": "ore", "share": 0.22},
			{"good": "logs", "share": 0.07},
			{"good": "charcoal", "share": 0.08},
			{"good": "iron", "share": 0.17},
			{"good": "copper", "share": 0.11},
			{"good": "guns", "share": 0.15},
			{"good": "ammo", "share": 0.08},
			{"good": "food", "share": 0.12}
		]
	},
	"refinery": {
		"name": "Refinery",
		"defaultSpecialty": "fuel",
		"stockMultipliers": {
			"food": 0.85, "logs": 0.9, "charcoal": 1.4, "saltpeter": 1.85, "sulfur": 1.85,
			"gunpowder": 1.85, "crude": 1.9, "fuel": 1.95, "ammo": 1.35, "iron": 0.9, "copper": 0.9
		},
		"priceBias": {
			"crude": 0.80, "fuel": 0.78, "saltpeter": 0.82, "sulfur": 0.82,
			"gunpowder": 0.82, "ammo": 0.90, "food": 1.12, "timber": 1.06
		},
		"recipes": [
			{"good": "crude", "share": 0.19},
			{"good": "fuel", "share": 0.15},
			{"good": "saltpeter", "share": 0.15},
			{"good": "sulfur", "share": 0.13},
			{"good": "logs", "share": 0.05},
			{"good": "charcoal", "share": 0.06},
			{"good": "gunpowder", "share": 0.11},
			{"good": "ammo", "share": 0.04},
			{"good": "food", "share": 0.12}
		]
	},
	"shipyard": {
		"name": "Shipyard",
		"defaultSpecialty": "engines",
		"stockMultipliers": {
			"food": 0.9, "logs": 1.15, "timber": 1.4, "iron": 1.5, "copper": 1.35,
			"fuel": 1.25, "supplies": 1.65, "ammo": 1.15, "engines": 1.95, "guns": 1.75
		},
		"priceBias": {
			"engines": 0.80, "guns": 0.84, "supplies": 0.85, "timber": 0.96, "food": 1.10
		},
		"recipes": [
			{"good": "engines", "share": 0.34},
			{"good": "guns", "share": 0.22},
			{"good": "supplies", "share": 0.10},
			{"good": "timber", "share": 0.10},
			{"good": "logs", "share": 0.08},
			{"good": "ammo", "share": 0.04},
			{"good": "food", "share": 0.12}
		]
	},
	"trade": {
		"name": "Trade Hub",
		"defaultSpecialty": "supplies",
		"stockMultipliers": {
			"food": 1.25, "logs": 1.15, "timber": 1.2, "ore": 1.05, "charcoal": 1.1,
			"iron": 1.2, "copper": 1.15, "saltpeter": 1.1, "sulfur": 1.1, "gunpowder": 1.15,
			"ammo": 1.2, "crude": 1.1, "fuel": 1.25, "supplies": 1.4, "engines": 1.15, "guns": 1.15
		},
		"priceBias": {
			"food": 0.96, "timber": 0.96, "iron": 0.96, "fuel": 0.96,
			"supplies": 0.90, "ammo": 0.96, "engines": 0.95, "guns": 0.95
		},
		"recipes": [
			{"good": "food", "share": 0.20},
			{"good": "logs", "share": 0.08},
			{"good": "timber", "share": 0.10},
			{"good": "charcoal", "share": 0.05},
			{"good": "ore", "share": 0.06},
			{"good": "iron", "share": 0.07},
			{"good": "crude", "share": 0.06},
			{"good": "fuel", "share": 0.08},
			{"good": "supplies", "share": 0.10},
			{"good": "ammo", "share": 0.05},
			{"good": "engines", "share": 0.08},
			{"good": "guns", "share": 0.07}
		]
	}
}


static func _is_num(val: Variant) -> bool:
	var t := typeof(val)
	return (t == TYPE_INT or t == TYPE_FLOAT) and not is_nan(float(val)) and not is_inf(float(val))


static func _clean_stock(val: float) -> float:
	if is_nan(val) or is_inf(val) or val <= 1e-6:
		return 0.0
	return round(val * 10000.0) / 10000.0


static func _normalize_good(good: Variant) -> String:
	var g := str(good) if good != null else ""
	if g == "steel":
		return "iron"
	return g


static func _normalize_industry(industry: Variant) -> String:
	var key := str(industry) if industry != null else "trade"
	return key if INDUSTRIES.has(key) else "trade"


static func _normalize_wealth_factor(wealth: Variant) -> float:
	if not _is_num(wealth) or float(wealth) <= 0.0:
		return 1.0
	var w := float(wealth)
	if w <= 3.0:
		return clampf(w, 0.55, 2.2)
	if w <= 10.0:
		return clampf(0.65 + (w / 5.0) * 0.6, 0.65, 2.0)
	if w <= 150.0:
		return clampf(w / 60.0, 0.55, 2.0)
	return clampf(w / 4000.0, 0.6, 2.2)


static func _normalize_pop_factor(population: Variant) -> float:
	if not _is_num(population) or float(population) <= 0.0:
		return 1.0
	var pop := float(population)
	if pop < 150.0:
		return clampf(pop / 60.0, 0.6, 2.0)
	return clampf(sqrt(pop / 1200.0), 0.6, 2.2)


static func _get_workforce_needed(port: Dictionary) -> int:
	var pop_val: Variant = port.get("population", 0)
	if not _is_num(pop_val) or float(pop_val) <= 0.0:
		return 420
	var pop := float(pop_val)
	if pop < 200.0:
		return maxi(12, int(round(pop * 0.6)))
	return clampi(int(round(pop * 0.35)), 40, 2500)


static func get_equilibrium_stock(port: Dictionary, good: String, goods_dict: Dictionary) -> int:
	var g := _normalize_good(good)
	if not goods_dict.has(g):
		return 40
	var ind_key := _normalize_industry(port.get("industry", "trade") if port != null else "trade")
	var ind: Dictionary = INDUSTRIES[ind_key]
	var pop_val := float(port.get("population", 1200)) if (port != null and _is_num(port.get("population", 1200))) else 1200.0
	var pop_factor := _normalize_pop_factor(pop_val)
	var wealth_factor := _normalize_wealth_factor(port.get("wealth", 1.0) if port != null else 1.0)
	var mults: Dictionary = ind.get("stockMultipliers", {})
	var ind_mult := float(mults.get(g, 1.0))
	var spec := _normalize_good(port.get("specialty", "") if port != null else "")
	var spec_mult := 1.25 if spec == g else 1.0

	if g == "food":
		# Several days of population food demand at 1 bale per 12.5 person-days
		var daily_pop_food := maxf(8.0, pop_val * DAILY_FOOD_PER_PERSON)
		return maxi(24, int(round(daily_pop_food * 2.5 * ind_mult * spec_mult)))

	var base_eq := float(BASE_EQUILIBRIUM.get(g, 45.0))
	var scale := clampf(0.55 + 0.30 * pop_factor + 0.15 * wealth_factor, 0.6, 1.85)
	return maxi(6, int(round(base_eq * ind_mult * spec_mult * scale)))


static func _default_ship_stock(industry: String, wealth_factor: float) -> Dictionary:
	var rich := 1 if wealth_factor >= 1.15 else 0
	if industry == "shipyard":
		return {"skiff": 3, "cutter": 2, "gunboat": 2, "corvette": 1 + rich}
	if industry == "trade" or industry == "foundry":
		return {"skiff": 2, "cutter": 2, "gunboat": 1 + rich}
	return {"skiff": 2, "cutter": 1}


static func _default_ship_ids(ship_stock: Dictionary) -> Array:
	var ids: Array = []
	for k in ship_stock.keys():
		if _is_num(ship_stock[k]) and int(ship_stock[k]) > 0:
			ids.append(str(k))
	return ids


static func _build_recipes(ind: Dictionary, specialty: String, goods_dict: Dictionary) -> Array:
	var base_recipes: Array = ind.get("recipes", [])
	var recipes: Array = []
	var has_spec := false
	for r in base_recipes:
		if r is Dictionary:
			var copy := (r as Dictionary).duplicate(true)
			recipes.append(copy)
			if str(copy.get("good", "")) == specialty:
				has_spec = true
	if specialty != "" and goods_dict.has(specialty) and not has_spec:
		var item_def: Dictionary = Goods.ITEMS.get(specialty, {})
		var inputs: Dictionary = item_def.get("inputs", {})
		for in_g in inputs.keys():
			var has_in := false
			for r in recipes:
				if str(r.get("good", "")) == str(in_g):
					has_in = true
					break
			if not has_in and goods_dict.has(str(in_g)):
				recipes.append({"good": str(in_g), "share": 0.08})
		recipes.append({"good": specialty, "share": 0.18})
	return recipes


static func _empty_employed_map() -> Dictionary:
	var out: Dictionary = {}
	for occ in OCCUPATION_KEYS:
		out[occ] = 0
	return out


static func _make_last_production(prod_map: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for g in GOOD_KEYS:
		var v := maxf(0.0, float(prod_map.get(g, 0.0))) if _is_num(prod_map.get(g, 0.0)) else 0.0
		out[g] = _clean_stock(v)
	return out


static func _make_shortages(items: Array) -> Array:
	var unique: Array = []
	var seen: Dictionary = {}
	for item in items:
		var k := str(item)
		if k.length() > 0 and not seen.has(k):
			seen[k] = true
			unique.append(k)
	return unique


static func _compute_initial_telemetry(port: Dictionary, goods_dict: Dictionary) -> void:
	var ind_key := _normalize_industry(port.get("industry", "trade"))
	var ind: Dictionary = INDUSTRIES[ind_key]
	var workforce := maxi(0, int(port.get("workforce", 0)))
	var cash := maxi(0, int(port.get("cash", 0)))
	var specialty := _normalize_good(port.get("specialty", ""))
	var recipes := _build_recipes(ind, specialty, goods_dict)
	var stocks: Dictionary = port.get("stocks", {})

	var prod: Dictionary = {}
	for g in GOOD_KEYS:
		prod[g] = 0.0
	var shortages: Array = []
	if workforce <= 0:
		shortages.append("workers")
	if cash <= 0:
		shortages.append("cash")

	var usable_workers := float(maxi(0, int(round(float(workforce) * 0.68))))
	if workforce > 0 and cash > 0:
		var total_share := 0.0
		for r in recipes:
			var rg := str(r.get("good", "food"))
			var sh := float(r.get("share", 0.1)) * (1.3 if rg == specialty else 1.0)
			total_share += sh
		total_share = maxf(0.01, total_share)

		for r in recipes:
			var rg := str(r.get("good", "food"))
			if not Goods.ITEMS.has(rg):
				continue
			var item_def: Dictionary = Goods.ITEMS[rg]
			var unit_days := maxf(0.1, Goods.labor_days(item_def["labor"]))
			var sh := float(r.get("share", 0.1)) * (1.3 if rg == specialty else 1.0) / total_share
			var batches := (usable_workers * sh) / unit_days
			var inputs: Dictionary = item_def.get("inputs", {})
			for in_g in inputs.keys():
				var need := batches * float(inputs[in_g])
				var have := maxf(0.0, float(stocks.get(in_g, 0.0)))
				if need > 0.0 and have < need:
					batches = have / float(inputs[in_g]) if float(inputs[in_g]) > 0.0 else 0.0
					shortages.append(str(in_g))
			prod[rg] = float(prod.get(rg, 0.0)) + maxf(0.0, batches)

	for g in GOOD_KEYS:
		var eq := float(get_equilibrium_stock(port, g, goods_dict))
		var cur := maxf(0.0, float(stocks.get(g, 0.0)))
		if cur < eq * 0.20:
			shortages.append(g)

	# lastProduction remains zero until paid work occurs in tick_ports; projectedProduction exposes capacity
	port["lastProduction"] = _make_last_production({})
	port["projectedProduction"] = _make_last_production(prod)
	port["shortages"] = _make_shortages(shortages)
