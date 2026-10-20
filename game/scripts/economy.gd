extends RefCounted
## Brass Tide native bronze cash economy module (v0.001).
## Pure RefCounted simulation: integer bronze cash purses, float physical stocks,
## paid occupation recipes from Goods, and strict atomic coin conservation.

const Goods = preload("res://scripts/goods.gd")
const IndustryData = preload("res://scripts/industry_data.gd")

static var GOODS: Dictionary = Goods.definitions()

const GOOD_KEYS: Array[String] = IndustryData.GOOD_KEYS
const OCCUPATION_KEYS: Array[String] = IndustryData.OCCUPATION_KEYS

const SAILOR_WAGE: int = IndustryData.SAILOR_WAGE
const ORDINARY_WAGE: int = IndustryData.ORDINARY_WAGE
const ROUNDS_PER_CASE: int = IndustryData.ROUNDS_PER_CASE
const WAGES: Dictionary = IndustryData.WAGES

const SEED_BUSINESS_WAGE_DAYS: int = IndustryData.SEED_BUSINESS_WAGE_DAYS
const SEED_HOUSEHOLD_WAGE_DAYS: int = IndustryData.SEED_HOUSEHOLD_WAGE_DAYS
const SEED_EXPERT_WAGE_DAYS: int = IndustryData.SEED_EXPERT_WAGE_DAYS
const SEED_GOVERNMENT_WAGE_DAYS: int = IndustryData.SEED_GOVERNMENT_WAGE_DAYS

const PERSON_DAYS_PER_FOOD_BALE: float = IndustryData.PERSON_DAYS_PER_FOOD_BALE
const DAILY_FOOD_PER_PERSON: float = IndustryData.DAILY_FOOD_PER_PERSON
const WAGE_TAX_RATE: float = IndustryData.WAGE_TAX_RATE
const TRANSACTION_TAX_RATE: float = IndustryData.TRANSACTION_TAX_RATE
const MAX_LEDGER_ENTRIES: int = IndustryData.MAX_LEDGER_ENTRIES
const DEFAULT_RECRUIT_POOL_RATE: float = 0.06
const DAILY_VOLUNTEER_RATE: float = 0.01

const BASE_EQUILIBRIUM: Dictionary = IndustryData.BASE_EQUILIBRIUM
const INDUSTRIES: Dictionary = IndustryData.INDUSTRIES


static func _is_num(val: Variant) -> bool:
	var t := typeof(val)
	return (t == TYPE_INT or t == TYPE_FLOAT) and not is_nan(float(val)) and not is_inf(float(val))


static func _is_int_qty(val: Variant) -> bool:
	if not _is_num(val):
		return false
	var f := float(val)
	return f > 0.0 and floor(f) == f


static func _clean_stock(val: float) -> float:
	if is_nan(val) or is_inf(val) or val <= 1e-6:
		return 0.0
	return round(val * 10000.0) / 10000.0


static func is_expert_occupation(occupation: String) -> bool:
	return int(WAGES.get(occupation, ORDINARY_WAGE)) >= 150


static func _normalize_good(good: Variant) -> String:
	return IndustryData._normalize_good(good)


static func _normalize_industry(industry: Variant) -> String:
	return IndustryData._normalize_industry(industry)


static func _normalize_wealth_factor(wealth: Variant) -> float:
	return IndustryData._normalize_wealth_factor(wealth)


static func _normalize_pop_factor(population: Variant) -> float:
	return IndustryData._normalize_pop_factor(population)


static func _get_workforce_needed(port: Dictionary) -> int:
	return IndustryData._get_workforce_needed(port)


static func default_recruit_pool(workforce: int) -> int:
	return mini(workforce, ceili(float(workforce) * DEFAULT_RECRUIT_POOL_RATE)) if workforce > 0 else 0


static func replenish_volunteers(port: Dictionary, days: float) -> void:
	if not is_finite(days) or days <= 0.0:
		return
	var workforce: int = maxi(0,int(port.get("workforce",0)))
	var avail_w: int = clampi(int(port.get("availableWorkers",0)),0,workforce)
	# Daily volunteer replenishment from remaining idle civilians (willingness pool only; never alters workforce, cash, or goods)
	var recruit_cap := mini(workforce, avail_w)
	var volunteer_target := mini(default_recruit_pool(workforce), recruit_cap)
	var cur_recruits := clampi(int(round(float(port.get("recruits", 0)))), 0, recruit_cap) if _is_num(port.get("recruits", 0)) else 0
	var rec_rem := maxf(0.0, float(port.get("recruitRemainder", 0.0))) if _is_num(port.get("recruitRemainder", 0.0)) else 0.0
	if cur_recruits < volunteer_target and workforce > 0 and avail_w > 0:
		var raw_gain := rec_rem + float(workforce) * DAILY_VOLUNTEER_RATE * days
		var whole_gain := maxi(0, int(floor(raw_gain + 1e-9)))
		var actual_gain := mini(volunteer_target - cur_recruits, whole_gain)
		cur_recruits += actual_gain
		if cur_recruits >= volunteer_target:
			rec_rem = 0.0
		else:
			rec_rem = maxf(0.0, snappedf(raw_gain - float(whole_gain), 0.000001))
	else:
		rec_rem = 0.0
	port["recruits"] = cur_recruits
	port["recruitRemainder"] = rec_rem


static func get_equilibrium_stock(port: Dictionary, good: String) -> int:
	return IndustryData.get_equilibrium_stock(port, good, GOODS)


static func _empty_employed_map() -> Dictionary:
	return IndustryData._empty_employed_map()


static func _make_last_production(prod_map: Dictionary) -> Dictionary:
	return IndustryData._make_last_production(prod_map)


static func _make_shortages(items: Array) -> Array:
	return IndustryData._make_shortages(items)


static func _default_ship_stock(industry: String, wealth_factor: float) -> Dictionary:
	return IndustryData._default_ship_stock(industry, wealth_factor)


static func _default_ship_ids(ship_stock: Dictionary) -> Array:
	return IndustryData._default_ship_ids(ship_stock)


static func _build_recipes(ind: Dictionary, specialty: String) -> Array:
	return IndustryData._build_recipes(ind, specialty, GOODS)


static func _append_ledger(port: Dictionary, entry: Dictionary) -> void:
	if not (port.get("ledger") is Array):
		port["ledger"] = []
	var ledger: Array = port["ledger"]
	ledger.append(entry)
	while ledger.size() > MAX_LEDGER_ENTRIES:
		ledger.pop_front()


static func create_port(def: Dictionary = {}) -> Dictionary:
	var src := def if def != null else {}
	var industry := _normalize_industry(src.get("industry", "trade"))
	var ind_info: Dictionary = INDUSTRIES[industry]

	var pop_raw: Variant = src.get("population", null)
	var population := int(round(float(pop_raw))) if (_is_num(pop_raw) and float(pop_raw) > 0.0) else 1200

	var wealth_raw: Variant = src.get("wealth", null)
	var wealth: Variant = wealth_raw if (_is_num(wealth_raw) and float(wealth_raw) > 0.0) else 1.0

	var spec_raw := _normalize_good(src.get("specialty", ""))
	var specialty := spec_raw if (spec_raw.length() > 0 and GOODS.has(spec_raw)) else str(ind_info.get("defaultSpecialty", "supplies"))

	var wealth_factor := _normalize_wealth_factor(wealth)

	var port: Dictionary = src.duplicate(true)
	port["id"] = str(src.get("id", "port_1")) if str(src.get("id", "")).length() > 0 else "port_1"
	port["name"] = str(src.get("name", "Harbor")) if str(src.get("name", "")).length() > 0 else "Harbor"
	port["faction"] = str(src.get("faction", "compact")) if str(src.get("faction", "")).length() > 0 else "compact"
	port["x"] = src.get("x") if _is_num(src.get("x")) else 400
	port["y"] = src.get("y") if _is_num(src.get("y")) else 400
	port["population"] = population
	port["industry"] = industry
	port["specialty"] = str(src.get("specialty", specialty)) if str(src.get("specialty", "")).length() > 0 else specialty
	port["description"] = str(src.get("description", ""))
	port["wealth"] = wealth

	# Fixed civilian workforce pool (authoritative)
	var default_workforce := _get_workforce_needed(port)
	var wf_raw: Variant = src.get("workforce", src.get("workers", null))
	var workforce := maxi(0, int(round(float(wf_raw)))) if (_is_num(wf_raw) and float(wf_raw) >= 0.0) else default_workforce
	port["workforce"] = workforce

	var emp_workers_raw: Variant = src.get("employedWorkers", null)
	if _is_num(emp_workers_raw) and float(emp_workers_raw) >= 0.0:
		port["workers"] = clampi(int(round(float(emp_workers_raw))), 0, workforce)
	elif src.has("workforce") and src.has("workers") and _is_num(src.get("workers")) and float(src.get("workers")) < float(workforce):
		port["workers"] = clampi(int(round(float(src.get("workers")))), 0, workforce)
	else:
		port["workers"] = int(round(float(workforce) * 0.68))
	port["employedWorkers"] = int(port["workers"])

	var pub_raw: Variant = src.get("publicWorkers", null)
	if _is_num(pub_raw) and float(pub_raw) >= 0.0:
		port["publicWorkers"] = clampi(int(round(float(pub_raw))), 0, maxi(0, workforce - int(port["workers"])))
	else:
		port["publicWorkers"] = clampi(int(round(float(workforce) * 0.06)), 0, maxi(0, workforce - int(port["workers"])))

	# availableWorkers is always the idle remainder of authoritative workforce
	if src.has("availableWorkers") and _is_num(src.get("availableWorkers")) and float(src.get("availableWorkers")) >= 0.0:
		var req_avail := clampi(int(round(float(src.get("availableWorkers")))), 0, maxi(0, workforce - int(port["publicWorkers"])))
		port["workers"] = clampi(workforce - int(port["publicWorkers"]) - req_avail, 0, workforce)
		port["employedWorkers"] = int(port["workers"])
	var avail_workers := maxi(0, workforce - int(port["workers"]) - int(port["publicWorkers"]))
	port["availableWorkers"] = avail_workers

	var default_spec := clampi(maxi(2, int(round(float(workforce) * 0.12))), 0, workforce) if workforce > 0 else 0
	var specialists_raw: Variant = src.get("specialists", src.get("specialistWorkers", null))
	var total_spec := clampi(int(round(float(specialists_raw))), 0, workforce) if (_is_num(specialists_raw) and float(specialists_raw) >= 0.0) else default_spec
	port["specialists"] = total_spec
	port["specialistWorkers"] = total_spec

	var avail_spec_raw: Variant = src.get("availableSpecialists", null)
	var avail_spec := clampi(int(round(float(avail_spec_raw))), 0, mini(total_spec, avail_workers)) if (_is_num(avail_spec_raw) and float(avail_spec_raw) >= 0.0) else mini(total_spec, avail_workers)
	port["availableSpecialists"] = avail_spec

	# Deterministic initial bronze cash purse allocation (only on world creation):
	# business: 20 wage-days/worker, households: 15, specialists: 5, government: 40 (at 100 cash ordinary wage-day)
	var seed_workers := maxi(1, workforce) if (workforce > 0 or not src.has("workers")) else 0
	var default_business_cash := seed_workers * SEED_BUSINESS_WAGE_DAYS * ORDINARY_WAGE
	var default_household_purse := seed_workers * SEED_HOUSEHOLD_WAGE_DAYS * ORDINARY_WAGE
	var default_expert_purse := seed_workers * SEED_EXPERT_WAGE_DAYS * ORDINARY_WAGE
	var default_government_purse := seed_workers * SEED_GOVERNMENT_WAGE_DAYS * ORDINARY_WAGE

	var cash_raw: Variant = src.get("cash", null)
	port["cash"] = maxi(0, int(round(float(cash_raw)))) if (_is_num(cash_raw) and float(cash_raw) >= 0.0) else default_business_cash

	var hh_raw: Variant = src.get("householdPurse", null)
	port["householdPurse"] = maxi(0, int(round(float(hh_raw)))) if (_is_num(hh_raw) and float(hh_raw) >= 0.0) else default_household_purse

	var exp_raw: Variant = src.get("expertPurse", null)
	port["expertPurse"] = maxi(0, int(round(float(exp_raw)))) if (_is_num(exp_raw) and float(exp_raw) >= 0.0) else default_expert_purse

	var gov_raw: Variant = src.get("governmentPurse", null)
	port["governmentPurse"] = maxi(0, int(round(float(gov_raw)))) if (_is_num(gov_raw) and float(gov_raw) >= 0.0) else default_government_purse

	# Scale physical stocks to several days of population demand and sensible minimum industrial stocks
	var src_stocks: Dictionary = src.get("stocks", {}) if src.get("stocks") is Dictionary else {}
	var stocks: Dictionary = {}
	for g in GOOD_KEYS:
		var ov: Variant = src_stocks.get(g, null)
		if ov == null and g == "iron" and src_stocks.has("steel"):
			ov = src_stocks.get("steel", null)
		if _is_num(ov) and float(ov) >= 0.0:
			stocks[g] = _clean_stock(float(ov))
		else:
			stocks[g] = float(get_equilibrium_stock(port, g))
	port["stocks"] = stocks

	var src_pub_stores: Dictionary = src.get("publicStores", {}) if src.get("publicStores") is Dictionary else {}
	var public_stores: Dictionary = {}
	for g in GOOD_KEYS:
		var pv: Variant = src_pub_stores.get(g, null)
		if _is_num(pv) and float(pv) >= 0.0:
			public_stores[g] = _clean_stock(float(pv))
		else:
			public_stores[g] = _clean_stock(float(stocks[g]) * 0.10) if g in ["food", "supplies", "fuel", "ammo"] else 0.0
	port["publicStores"] = public_stores

	var default_prosperity := clampf(round(55.0 + (wealth_factor - 1.0) * 25.0), 25.0, 92.0)
	var prosp_raw: Variant = src.get("prosperity", null)
	port["prosperity"] = clampf(float(prosp_raw), 0.0, 100.0) if _is_num(prosp_raw) else default_prosperity

	var default_recruits := default_recruit_pool(workforce)
	var rec_raw: Variant = src.get("recruits", null)
	port["recruits"] = maxi(0, int(round(float(rec_raw)))) if (_is_num(rec_raw) and float(rec_raw) >= 0.0) else default_recruits
	var rec_rem_raw: Variant = src.get("recruitRemainder", null)
	port["recruitRemainder"] = maxf(0.0, float(rec_rem_raw)) if (_is_num(rec_rem_raw) and float(rec_rem_raw) >= 0.0) else 0.0

	if src.get("shipStock") is Dictionary:
		port["shipStock"] = (src["shipStock"] as Dictionary).duplicate(true)
	else:
		port["shipStock"] = _default_ship_stock(industry, wealth_factor)

	if src.get("shipIds") is Array:
		port["shipIds"] = (src["shipIds"] as Array).duplicate(true)
	else:
		port["shipIds"] = _default_ship_ids(port["shipStock"])

	var emp_map := _empty_employed_map()
	port["employed"] = emp_map
	port["employedByOccupation"] = emp_map.duplicate(true)
	port["lastPayroll"] = {
		"total": 0,
		"business": 0,
		"household": 0,
		"expert": 0,
		"public": 0,
		"tax": 0,
		"byOccupation": _empty_employed_map()
	}
	port["lastProduction"] = _make_last_production({})
	port["projectedProduction"] = _make_last_production({})
	port["shortages"] = []
	port["buildQueue"] = (src["buildQueue"] as Array).duplicate(true) if src.get("buildQueue") is Array else []
	port["ledger"] = src.get("ledger").duplicate(true) if src.get("ledger") is Array else []

	_compute_initial_telemetry(port)
	return port


static func _compute_initial_telemetry(port: Dictionary) -> void:
	IndustryData._compute_initial_telemetry(port, GOODS)


static func clone_port(port: Dictionary) -> Dictionary:
	return port.duplicate(true) if port != null else {}


static func clone_ports(ports: Array) -> Array:
	var copy: Array = []
	for p in ports:
		if p is Dictionary:
			copy.append(p.duplicate(true))
	return copy


static func snapshot_ports(ports: Array) -> Array:
	return clone_ports(ports)


static func _order_seen(orders: Array, order: Dictionary) -> bool:
	for existing in orders:
		if is_same(existing,order):
			return true
	return false


static func port_coins(port: Dictionary) -> int:
	if port == null:
		return 0
	var total := 0
	for k in ["cash", "householdPurse", "expertPurse", "governmentPurse", "escrow"]:
		var v: Variant = port.get(k, 0)
		if _is_num(v):
			total += int(round(float(v)))
	var seen_orders: Array = []
	for ord_key in ["buildQueue", "orders", "constructionOrders"]:
		if port.get(ord_key) is Array:
			for ord in port[ord_key]:
				if ord is Dictionary and not _order_seen(seen_orders,ord):
					seen_orders.append(ord)
					var ev: Variant = ord.get("escrow", 0)
					if _is_num(ev):
						total += int(round(float(ev)))
	return total


static func total_coins(ports: Array, owners: Array = [], orders: Array = [], extra_wallets: Array = []) -> int:
	var sum_coins := 0
	var seen_orders: Array = []

	if ports != null:
		for p in ports:
			if not (p is Dictionary):
				continue
			for k in ["cash", "householdPurse", "expertPurse", "governmentPurse", "escrow"]:
				var pv: Variant = p.get(k, 0)
				if _is_num(pv):
					sum_coins += int(round(float(pv)))
			for ord_key in ["buildQueue", "orders", "constructionOrders"]:
				if p.get(ord_key) is Array:
					for ord in p[ord_key]:
						if ord is Dictionary and not _order_seen(seen_orders,ord):
							seen_orders.append(ord)
							var ev: Variant = ord.get("escrow", 0)
							if _is_num(ev):
								sum_coins += int(round(float(ev)))

	if owners != null:
		for ow in owners:
			if not (ow is Dictionary):
				continue
			for k in ["coins", "crewPurse", "escrow"]:
				var ov: Variant = ow.get(k, 0)
				if _is_num(ov):
					sum_coins += int(round(float(ov)))
			for ord_key in ["buildQueue", "orders", "constructionOrders"]:
				if ow.get(ord_key) is Array:
					for ord in ow[ord_key]:
						if ord is Dictionary and not _order_seen(seen_orders,ord):
							seen_orders.append(ord)
							var ev: Variant = ord.get("escrow", 0)
							if _is_num(ev):
								sum_coins += int(round(float(ev)))

	if orders != null:
		for ord in orders:
			if ord is Dictionary and not _order_seen(seen_orders,ord):
				seen_orders.append(ord)
				var ev: Variant = ord.get("escrow", 0)
				if _is_num(ev):
					sum_coins += int(round(float(ev)))

	if extra_wallets != null:
		for w in extra_wallets:
			if not (w is Dictionary):
				continue
			for k in ["coins", "crewPurse", "escrow"]:
				var wv: Variant = w.get(k, 0)
				if _is_num(wv):
					sum_coins += int(round(float(wv)))

	return sum_coins


static func price(port: Dictionary, good: String, side: String = "buy") -> int:
	var g := _normalize_good(good)
	if not GOODS.has(g):
		return 0
	var trade_side := "sell" if side == "sell" else "buy"
	var base_cost := maxf(1.0, Goods.cost(g))
	var ind_key := _normalize_industry(port.get("industry", "trade") if port != null else "trade")
	var ind: Dictionary = INDUSTRIES[ind_key]
	var stocks: Dictionary = port.get("stocks", {}) if (port != null and port.get("stocks") is Dictionary) else {}
	var raw_stock: Variant = stocks.get(g, stocks.get(good, 0.0))
	var stock := maxf(0.0, float(raw_stock)) if _is_num(raw_stock) else 0.0
	var target := maxf(6.0, float(get_equilibrium_stock(port if port != null else {}, g)))
	var ratio := stock / target

	# Scarcity factor around recursive labor/input cost
	var scarcity_factor := clampf(1.75 / (1.0 + 0.75 * pow(ratio, 0.85)), 0.58, 1.80)
	var price_bias_map: Dictionary = ind.get("priceBias", {})
	var ind_bias := float(price_bias_map.get(g, 1.0))
	var spec := _normalize_good(port.get("specialty", "") if port != null else "")
	var spec_bias := 0.92 if spec == g else 1.0
	var blockade_bias := 1.15 if (port != null and bool(port.get("blockaded", false))) else 1.0

	var mid := base_cost * scarcity_factor * ind_bias * spec_bias * blockade_bias
	var buy_price := maxi(2, int(round(mid * 1.09)))
	if trade_side == "buy":
		return buy_price
	return maxi(1, mini(buy_price - 1, int(round(mid * 0.91))))


static func cargo_weight(cargo_or_wallet: Variant) -> float:
	if not (cargo_or_wallet is Dictionary):
		return 0.0
	var d: Dictionary = cargo_or_wallet
	var cargo: Dictionary = d.get("cargo") if d.get("cargo") is Dictionary else d
	var total_weight := 0.0
	for k in cargo.keys():
		var g := _normalize_good(k)
		if GOODS.has(g):
			var q: Variant = cargo.get(k, 0.0)
			if _is_num(q) and float(q) > 0.0:
				total_weight += float(q) * float(GOODS[g]["weight"])
	return total_weight


static func cargo_space_left(cargo_or_wallet: Variant, capacity: Variant = INF) -> float:
	if capacity == null:
		return INF
	if not (typeof(capacity) in [TYPE_INT, TYPE_FLOAT]) or is_nan(float(capacity)):
		return INF
	if is_inf(float(capacity)):
		return INF
	return maxf(0.0, float(capacity) - cargo_weight(cargo_or_wallet))


static func _add_stock(raw_val: Variant, delta: int) -> Variant:
	if not _is_num(raw_val) or float(raw_val) < 0.0:
		return maxi(0, delta)
	if typeof(raw_val) == TYPE_INT:
		return maxi(0, int(raw_val) + delta)
	var res := maxf(0.0, float(raw_val) + float(delta))
	return round(res * 1000000.0) / 1000000.0


static func _get_wallet_coins(wallet: Dictionary) -> int:
	if wallet == null or not wallet.has("coins") or not _is_num(wallet.get("coins")):
		return -1
	var v := float(wallet.get("coins"))
	if v < 0.0:
		return -1
	return int(round(v))


static func _set_wallet_coins(wallet: Dictionary, amount: int) -> void:
	wallet["coins"] = maxi(0, amount)


static func transact(port: Dictionary, wallet: Dictionary, good: String, qty: Variant, side: String = "buy", capacity: Variant = INF) -> Dictionary:
	var trade_side := "buy" if side == "" else side
	if port == null or not (port.get("stocks") is Dictionary):
		return {"ok": false, "qty": 0, "total": 0, "coins": 0, "message": "Invalid port"}
	if wallet == null:
		return {"ok": false, "qty": 0, "total": 0, "coins": 0, "message": "Invalid wallet"}
	var g := _normalize_good(good)
	if not GOODS.has(g):
		return {"ok": false, "qty": 0, "total": 0, "coins": 0, "message": "Unknown good: " + str(good)}
	if trade_side != "buy" and trade_side != "sell":
		return {"ok": false, "qty": 0, "total": 0, "coins": 0, "message": "Invalid transaction side"}
	if not _is_int_qty(qty):
		return {"ok": false, "qty": 0, "total": 0, "coins": 0, "message": "Quantity must be a positive integer"}

	var wallet_coins := _get_wallet_coins(wallet)
	if wallet_coins < 0:
		return {"ok": false, "qty": 0, "total": 0, "coins": 0, "message": "Invalid wallet coins"}
	if not _is_num(port.get("cash")) or float(port.get("cash")) < 0.0:
		return {"ok": false, "qty": 0, "total": 0, "coins": 0, "message": "Invalid port cash"}

	var q := int(qty)
	var g_info: Dictionary = GOODS[g]
	var stocks: Dictionary = port["stocks"]
	var stock_key := good if (stocks.has(good) and not stocks.has(g)) else g
	var raw_port_val: Variant = stocks.get(stock_key, stocks.get(g, 0))
	var port_stock := maxi(0, int(floor(float(raw_port_val)))) if _is_num(raw_port_val) else 0
	var cur_cargo: Dictionary = wallet.get("cargo") if wallet.get("cargo") is Dictionary else {}
	var cargo_key := good if (cur_cargo.has(good) and not cur_cargo.has(g)) else g
	var raw_player_val: Variant = cur_cargo.get(cargo_key, cur_cargo.get(g, 0))
	var player_stock := maxi(0, int(floor(float(raw_player_val)))) if _is_num(raw_player_val) else 0
	var port_cash := int(round(float(port["cash"])))

	if trade_side == "buy":
		if q > port_stock:
			return {"ok": false, "qty": 0, "total": 0, "coins": 0, "message": "Port lacks sufficient " + str(g_info["name"])}
		if capacity != null:
			var cap_t := typeof(capacity)
			if not (cap_t == TYPE_INT or cap_t == TYPE_FLOAT) or is_nan(float(capacity)) or float(capacity) < 0.0:
				return {"ok": false, "qty": 0, "total": 0, "coins": 0, "message": "Invalid cargo capacity"}
			if not is_inf(float(capacity)):
				var current_weight := cargo_weight(cur_cargo)
				var added_weight := float(q) * float(g_info["weight"])
				if current_weight + added_weight > float(capacity) + 1e-9:
					return {"ok": false, "qty": 0, "total": 0, "coins": 0, "message": "Exceeds cargo hold capacity"}
		var unit_price := price(port, g, "buy")
		var total := unit_price * q
		if wallet_coins < total:
			return {"ok": false, "qty": 0, "total": 0, "coins": 0, "message": "Insufficient coins"}

		if not (wallet.get("cargo") is Dictionary):
			wallet["cargo"] = {}
		_set_wallet_coins(wallet, wallet_coins - total)
		port["cash"] = port_cash + total
		stocks[stock_key] = _add_stock(raw_port_val, -q)
		wallet["cargo"][cargo_key] = _add_stock(raw_player_val, q)
		return {"ok": true, "qty": q, "total": total, "coins": total, "message": "Bought %d %s for %d coins" % [q, str(g_info["name"]), total]}

	if q > player_stock:
		return {"ok": false, "qty": 0, "total": 0, "coins": 0, "message": "Insufficient " + str(g_info["name"]) + " in cargo"}
	var sell_unit := price(port, g, "sell")
	var sell_total := sell_unit * q
	if port_cash < sell_total:
		return {"ok": false, "qty": 0, "total": 0, "coins": 0, "message": "Port lacks cash to buy cargo"}

	if not (wallet.get("cargo") is Dictionary):
		wallet["cargo"] = {}
	_set_wallet_coins(wallet, wallet_coins + sell_total)
	port["cash"] = port_cash - sell_total
	stocks[stock_key] = _add_stock(raw_port_val, q)
	wallet["cargo"][cargo_key] = _add_stock(raw_player_val, -q)
	return {"ok": true, "qty": q, "total": sell_total, "coins": sell_total, "message": "Sold %d %s for %d coins" % [q, str(g_info["name"]), sell_total]}


static func recruit_cost(port: Dictionary, count: int = 1) -> int:
	var n := maxi(1, count)
	var recruits := maxf(0.0, float(port.get("recruits", 0))) if (port != null and _is_num(port.get("recruits", 0))) else 0.0
	var base_advance := SAILOR_WAGE * 10
	# Scarcity premium up to at most 20% above 10 sailor wage-days (1000..1200 coins/hire)
	var scarcity_ratio := clampf((16.0 - recruits) / 16.0, 0.0, 1.0)
	var unit_cost := clampi(
		int(round(float(base_advance) * (1.0 + 0.20 * scarcity_ratio))),
		base_advance,
		int(round(float(base_advance) * 1.20))
	)
	return unit_cost * n


static func recruit(port: Dictionary, wallet: Dictionary, count: Variant, room: Variant = INF) -> Dictionary:
	if port == null:
		return {"ok": false, "count": 0, "cost": 0, "coins": 0, "message": "Invalid port"}
	var wallet_coins := _get_wallet_coins(wallet)
	if wallet == null or wallet_coins < 0:
		return {"ok": false, "count": 0, "cost": 0, "coins": 0, "message": "Invalid wallet"}
	if not _is_int_qty(count):
		return {"ok": false, "count": 0, "cost": 0, "coins": 0, "message": "Recruit count must be a positive integer"}

	var q := int(count)
	var max_room: float = INF
	if room is Dictionary:
		var r_dict: Dictionary = room
		var cap_raw: Variant = r_dict.get("crewMax", r_dict.get("maxCrew", INF))
		var cur_raw: Variant = r_dict.get("crew", wallet.get("crew", 0))
		var cap := float(cap_raw) if (typeof(cap_raw) in [TYPE_INT, TYPE_FLOAT] and not is_nan(float(cap_raw))) else INF
		var cur := float(cur_raw) if _is_num(cur_raw) else 0.0
		max_room = INF if is_inf(cap) else maxf(0.0, floor(cap - cur))
	elif room != null:
		var rt := typeof(room)
		if not (rt == TYPE_INT or rt == TYPE_FLOAT) or is_nan(float(room)) or float(room) < 0.0:
			return {"ok": false, "count": 0, "cost": 0, "coins": 0, "message": "No crew room available"}
		max_room = INF if is_inf(float(room)) else floor(float(room))

	if float(q) > max_room:
		return {"ok": false, "count": 0, "cost": 0, "coins": 0, "message": "Insufficient crew quarters room"}

	var recruits_avail := maxi(0, int(floor(float(port.get("recruits", 0))))) if _is_num(port.get("recruits", 0)) else 0
	var wf_raw: Variant = port["workforce"] if port.has("workforce") else port.get("workers", 0)
	var cur_workforce := maxi(0, int(floor(float(wf_raw)))) if _is_num(wf_raw) else 0
	var available := mini(recruits_avail, cur_workforce)
	if q > available:
		return {"ok": false, "count": 0, "cost": 0, "coins": 0, "message": "Not enough recruits available in port"}

	var cost := recruit_cost(port, q)
	if wallet_coins < cost:
		return {"ok": false, "count": 0, "cost": 0, "coins": 0, "message": "Insufficient coins to recruit crew"}

	_set_wallet_coins(wallet, wallet_coins - cost)
	if wallet.has("crewPurse") and _is_num(wallet.get("crewPurse")):
		wallet["crewPurse"] = maxi(0, int(round(float(wallet["crewPurse"]) + float(cost))))
	else:
		var cur_hh := maxi(0, int(round(float(port.get("householdPurse", 0))))) if _is_num(port.get("householdPurse", 0)) else 0
		port["householdPurse"] = cur_hh + cost

	port["recruits"] = maxi(0, available - q)
	port["workforce"] = maxi(0, cur_workforce - q)
	_sync_port_workforce(port)

	if _is_num(wallet.get("crew")):
		wallet["crew"] = maxi(0, int(round(float(wallet["crew"]) + float(q))))
	else:
		wallet["crew"] = q

	return {"ok": true, "count": q, "cost": cost, "coins": cost, "message": "Recruited %d crew for %d coins" % [q, cost]}


static func _extract_ships(fleet: Variant) -> Array:
	if fleet == null:
		return []
	if fleet is Array:
		return fleet
	if fleet is Dictionary:
		var d: Dictionary = fleet
		if d.get("ships") is Array:
			return d["ships"]
		if d.get("boats") is Array:
			return d["boats"]
		if d.get("fleet") is Array:
			return d["fleet"]
		if d.has("crew") or d.has("size") or d.has("speed") or d.has("spec") or d.has("id") or d.has("hp"):
			return [d]
	return []


static func daily_upkeep(fleet: Variant) -> Dictionary:
	var ships := _extract_ships(fleet)
	if ships.is_empty():
		return {"wages": 0, "food": 0.0, "fuel": 0.0}

	var total_crew := 0.0
	var total_fuel := 0.0

	for item in ships:
		if not (item is Dictionary):
			continue
		var ship: Dictionary = item
		if ship.is_empty() or bool(ship.get("sunk", false)):
			continue
		var crew := maxf(0.0, float(ship.get("crew", 0))) if _is_num(ship.get("crew", 0)) else 0.0
		total_crew += crew

		var spec: Dictionary = ship.get("spec") if ship.get("spec") is Dictionary else ship
		var size_val: Variant = spec.get("size", ship.get("size", 14.0))
		var speed_val: Variant = spec.get("speed", ship.get("speed", 75.0))
		var size := clampf(float(size_val) if _is_num(size_val) else 14.0, 10.0, 48.0)
		var speed := clampf(float(speed_val) if _is_num(speed_val) else 75.0, 40.0, 180.0)
		var ship_fuel := clampf(0.11 + ((size - 10.0) / 38.0) * 0.05 + ((speed - 40.0) / 140.0) * 0.03, 0.1, 0.2)
		total_fuel += ship_fuel

	var wages := int(round(total_crew * float(SAILOR_WAGE))) if total_crew > 0.0 else 0
	var food := snappedf(total_crew * DAILY_FOOD_PER_PERSON, 0.01)
	var fuel := snappedf(total_fuel, 0.01)
	return {
		"wages": wages,
		"food": food,
		"fuel": fuel
	}


static func _is_port_blockaded(port: Dictionary, blockaded_list: Variant) -> bool:
	if port == null or blockaded_list == null:
		return false
	var pid := str(port.get("id", ""))
	var pname := str(port.get("name", ""))
	if blockaded_list is Array:
		for entry in blockaded_list:
			if entry is Dictionary and entry == port:
				return true
			var s := str(entry)
			if s == pid or s == pname:
				return true
	elif blockaded_list is Dictionary:
		var d: Dictionary = blockaded_list
		return bool(d.get(pid, false)) or bool(d.get(pname, false))
	return false


static func _sample_rng(rng_opt: Variant, fallback_rng: RandomNumberGenerator) -> float:
	if rng_opt is RandomNumberGenerator:
		return clampf((rng_opt as RandomNumberGenerator).randf(), 0.0, 1.0)
	if rng_opt is Callable:
		var c: Callable = rng_opt
		if c.is_valid():
			var v: Variant = c.call()
			if _is_num(v):
				return clampf(float(v), 0.0, 1.0)
	return clampf(fallback_rng.randf(), 0.0, 1.0)


static func sync_workforce(port: Dictionary) -> int:
	return _sync_port_workforce(port)


static func decrement_workforce(port: Dictionary, count: int) -> int:
	if port == null:
		return 0
	var n := maxi(0, count)
	var cur_wf := maxi(0, int(round(float(port.get("workforce", port.get("workers", 0)))))) if _is_num(port.get("workforce", port.get("workers", 0))) else 0
	port["workforce"] = maxi(0, cur_wf - n)
	return _sync_port_workforce(port)


static func _sync_port_workforce(port: Dictionary) -> int:
	if port == null:
		return 0
	var wf_raw: Variant = port.get("workforce", port.get("workers", 0))
	var workforce := maxi(0, int(round(float(wf_raw)))) if _is_num(wf_raw) else 0
	port["workforce"] = workforce

	var pub_w := maxi(0, int(round(float(port.get("publicWorkers", 0))))) if _is_num(port.get("publicWorkers", 0)) else 0
	pub_w = mini(workforce, pub_w)
	port["publicWorkers"] = pub_w

	var ind_w := maxi(0, int(round(float(port.get("workers", 0))))) if _is_num(port.get("workers", 0)) else 0
	ind_w = clampi(ind_w, 0, maxi(0, workforce - pub_w))
	port["workers"] = ind_w
	port["employedWorkers"] = ind_w

	var avail_w := maxi(0, workforce - ind_w - pub_w)
	port["availableWorkers"] = avail_w

	if _is_num(port.get("recruits", null)):
		port["recruits"] = clampi(int(round(float(port["recruits"]))), 0, workforce)

	var default_spec := clampi(maxi(2, int(round(float(workforce) * 0.12))), 0, workforce) if workforce > 0 else 0
	var spec_raw: Variant = port.get("specialists", port.get("specialistWorkers", null))
	var total_spec := clampi(int(round(float(spec_raw))), 0, workforce) if (_is_num(spec_raw) and float(spec_raw) >= 0.0) else default_spec
	port["specialists"] = total_spec
	port["specialistWorkers"] = total_spec

	var avail_spec_raw: Variant = port.get("availableSpecialists", null)
	var avail_spec := clampi(int(round(float(avail_spec_raw))), 0, mini(total_spec, avail_w)) if (_is_num(avail_spec_raw) and float(avail_spec_raw) >= 0.0) else mini(total_spec, avail_w)
	port["availableSpecialists"] = avail_spec
	return workforce


static func tick_ports(ports: Array, days: Variant = 1.0, options: Dictionary = {}) -> Array:
	if ports == null or ports.is_empty():
		return []
	if not _is_num(days) or float(days) <= 0.0:
		return []

	var raw_days := float(days)
	var opts := options if options != null else {}
	var rng_opt: Variant = opts.get("rng", null)
	var blockaded_opt: Variant = opts.get("blockaded", [])
	var allow_interport := bool(opts.get("interport_trade", true))
	var fallback_rng := RandomNumberGenerator.new()
	fallback_rng.seed = 133797531

	var events: Array = []
	var remaining := raw_days

	while remaining > 1e-6:
		var dt := minf(1.0, remaining)
		remaining -= dt
		var is_last_step := remaining <= 1e-6

		# 1. Per-port paid recipe production, resident purchases, and government payroll/procurement
		for p_item in ports:
			if not (p_item is Dictionary):
				continue
			var port: Dictionary = p_item
			if not (port.get("stocks") is Dictionary):
				port["stocks"] = {}
			if not (port.get("publicStores") is Dictionary):
				port["publicStores"] = {}
			var stocks: Dictionary = port["stocks"]
			var public_stores: Dictionary = port["publicStores"]

			for g in GOOD_KEYS:
				var sv: Variant = stocks.get(g, 0.0)
				if g == "iron" and not stocks.has("iron") and stocks.has("steel"):
					sv = stocks.get("steel", 0.0)
				stocks[g] = _clean_stock(float(sv)) if _is_num(sv) else 0.0
				var pv: Variant = public_stores.get(g, 0.0)
				public_stores[g] = _clean_stock(float(pv)) if _is_num(pv) else 0.0

			for purse_key in ["cash", "householdPurse", "expertPurse", "governmentPurse"]:
				var pv: Variant = port.get(purse_key, 0)
				port[purse_key] = maxi(0, int(round(float(pv)))) if _is_num(pv) else 0

			var ind_key := _normalize_industry(port.get("industry", "trade"))
			var ind: Dictionary = INDUSTRIES[ind_key]
			var blockaded := _is_port_blockaded(port, blockaded_opt)
			port["blockaded"] = blockaded

			var workforce := _sync_port_workforce(port)
			var expected_workforce := _get_workforce_needed(port)
			var shortage_items: Array = []
			if workforce <= 0 or float(workforce) < float(expected_workforce) * 0.50:
				shortage_items.append("workers")

			var opening_stocks: Dictionary = {}
			var working_stocks: Dictionary = {}
			for g in GOOD_KEYS:
				opening_stocks[g] = float(stocks[g])
				working_stocks[g] = float(stocks[g])

			var produced_rate: Dictionary = {}
			for g in GOOD_KEYS:
				produced_rate[g] = 0.0

			var employed_days_float: Dictionary = {}
			var payroll_by_occ: Dictionary = _empty_employed_map()
			for occ in OCCUPATION_KEYS:
				employed_days_float[occ] = 0.0

			var business_payroll := 0
			var household_wage_in := 0
			var expert_wage_in := 0
			var wage_tax_total := 0

			# Phase A: Paid Industrial Recipe Production (uses opening port.cash and opening_stocks)
			var opening_cash := int(port["cash"])
			if opening_cash <= 0 and workforce > 0:
				shortage_items.append("cash")

			var target_public := clampi(int(round(float(workforce) * 0.06)), 1, maxi(1, workforce / 6)) if workforce >= 10 else 0
			var yard_reserve := int(floor(float(workforce) * 0.14)) if workforce >= 12 else 0
			var max_ind_workers := maxi(0, workforce - target_public - yard_reserve)
			if workforce > 0 and max_ind_workers == 0:
				max_ind_workers = workforce

			var jitter := 0.96 + _sample_rng(rng_opt, fallback_rng) * 0.08
			var specialty := _normalize_good(port.get("specialty", ""))
			var recipes := _build_recipes(ind, specialty)

			# Businesses pace payroll when cash is low; never spend coins they do not have
			var payroll_budget := 0
			if opening_cash > 0:
				if opening_cash < 30000:
					payroll_budget = mini(opening_cash, maxi(ORDINARY_WAGE, int(round(float(opening_cash) * minf(1.0, 0.35 * dt)))))
				else:
					payroll_budget = mini(opening_cash, int(round(float(opening_cash) * minf(1.0, 0.45 * dt))))

			var weighted_recipes: Array = []
			var weight_sum := 0.0
			for r in recipes:
				var rg := str(r.get("good", "food"))
				if not Goods.ITEMS.has(rg):
					continue
				var eq := maxf(4.0, float(get_equilibrium_stock(port, rg)))
				var cur := float(opening_stocks.get(rg, 0.0))
				var sat := cur / eq
				var demand_mult := clampf(1.40 - 0.50 * sat, 0.10, 1.40)
				var spec_mult := 1.32 if specialty == rg else 1.0
				var eff_w := maxf(0.01, float(r.get("share", 0.1)) * demand_mult * spec_mult)
				weighted_recipes.append({"good": rg, "weight": eff_w})
				weight_sum += eff_w

			if max_ind_workers > 0 and payroll_budget > 0 and weight_sum > 0.0:
				for wr in weighted_recipes:
					var rg := str(wr["good"])
					var item_def: Dictionary = Goods.ITEMS[rg]
					var inputs_map: Dictionary = item_def.get("inputs", {})
					var labor_map: Dictionary = item_def.get("labor", {})
					var unit_days := maxf(0.1, Goods.labor_days(labor_map))
					var unit_cost := maxf(1.0, Goods.labor_cost(labor_map))

					var alloc_worker_days := float(max_ind_workers) * dt * (float(wr["weight"]) / weight_sum) * jitter
					var batches := alloc_worker_days / unit_days

					# Constrain by opening physical inputs
					for in_g in inputs_map.keys():
						var in_key := str(in_g)
						var need_per_batch := float(inputs_map[in_key])
						if need_per_batch <= 0.0:
							continue
						var avail_in := maxf(0.0, float(opening_stocks.get(in_key, 0.0)))
						if avail_in <= 1e-6:
							batches = 0.0
							shortage_items.append(in_key)
						elif batches * need_per_batch > avail_in:
							batches = avail_in / need_per_batch
							shortage_items.append(in_key)

					# Constrain by remaining business cash budget
					var rem_cash := mini(int(port["cash"]), payroll_budget - business_payroll)
					if batches > 0.0:
						if rem_cash <= 0:
							batches = 0.0
							shortage_items.append("cash")
						elif batches * unit_cost > float(rem_cash):
							batches = float(rem_cash) / unit_cost
							shortage_items.append("cash")

					if batches <= 1e-5:
						continue

					var occ_pays: Dictionary = {}
					var occ_days_map: Dictionary = {}
					var recipe_gross := 0
					for occ in labor_map.keys():
						var occ_str := str(occ)
						var mapped_occ := "fisher" if (occ_str == "farmer" and ind_key == "fishery") else occ_str
						var w_days := batches * float(labor_map[occ_str])
						var wage_rate := int(WAGES.get(mapped_occ, ORDINARY_WAGE))
						var pay := int(round(w_days * float(wage_rate)))
						occ_pays[mapped_occ] = int(occ_pays.get(mapped_occ, 0)) + pay
						occ_days_map[mapped_occ] = float(occ_days_map.get(mapped_occ, 0.0)) + w_days
						recipe_gross += pay

					if recipe_gross > rem_cash and recipe_gross > 0:
						var scale_down := float(rem_cash) / float(recipe_gross)
						batches *= scale_down
						recipe_gross = 0
						for mapped_occ in occ_pays.keys():
							var p_scaled := int(floor(float(occ_pays[mapped_occ]) * scale_down))
							occ_pays[mapped_occ] = p_scaled
							occ_days_map[mapped_occ] = float(occ_days_map[mapped_occ]) * scale_down
							recipe_gross += p_scaled

					if recipe_gross <= 0 or batches <= 1e-5:
						continue

					# Deplete real inputs and create output
					for in_g in inputs_map.keys():
						var in_key := str(in_g)
						var consumed := batches * float(inputs_map[in_key])
						opening_stocks[in_key] = maxf(0.0, float(opening_stocks.get(in_key, 0.0)) - consumed)
						working_stocks[in_key] = maxf(0.0, float(working_stocks.get(in_key, 0.0)) - consumed)

					working_stocks[rg] = maxf(0.0, float(working_stocks.get(rg, 0.0)) + batches)
					produced_rate[rg] = float(produced_rate.get(rg, 0.0)) + (batches / maxf(0.01, dt))

					# Atomic wage transfer: port.cash -> householdPurse / expertPurse + wage tax -> governmentPurse
					for mapped_occ in occ_pays.keys():
						var gross_pay := int(occ_pays[mapped_occ])
						if gross_pay <= 0:
							continue
						var wage_tax := int(floor(float(gross_pay) * WAGE_TAX_RATE))
						var net_pay := gross_pay - wage_tax
						port["cash"] = int(port["cash"]) - gross_pay
						port["governmentPurse"] = int(port["governmentPurse"]) + wage_tax
						if is_expert_occupation(mapped_occ):
							port["expertPurse"] = int(port["expertPurse"]) + net_pay
							expert_wage_in += net_pay
						else:
							port["householdPurse"] = int(port["householdPurse"]) + net_pay
							household_wage_in += net_pay

						business_payroll += gross_pay
						wage_tax_total += wage_tax
						payroll_by_occ[mapped_occ] = int(payroll_by_occ.get(mapped_occ, 0)) + gross_pay
						employed_days_float[mapped_occ] = float(employed_days_float.get(mapped_occ, 0.0)) + (float(occ_days_map[mapped_occ]) / maxf(0.01, dt))

			if business_payroll > 0:
				_append_ledger(port, {
					"type": "payroll",
					"from": "cash",
					"to": "householdPurse+expertPurse",
					"coins": business_payroll,
					"tax": wage_tax_total
				})

			# Phase B: Resident Purchases (householdPurse & expertPurse buy food and domestic goods from businesses)
			var total_food_need := maxf(0.5, float(maxi(10, workforce)) * DAILY_FOOD_PER_PERSON) * dt
			var food_bought_total := 0.0

			# Release emergency public granary food into market if business food stock is critically low
			if float(working_stocks["food"]) < total_food_need and float(public_stores.get("food", 0.0)) > 0.0:
				var release := minf(float(public_stores["food"]), total_food_need - float(working_stocks["food"]))
				public_stores["food"] = _clean_stock(float(public_stores["food"]) - release)
				working_stocks["food"] = _clean_stock(float(working_stocks["food"]) + release)

			var purse_food_shares := [
				{"key": "householdPurse", "share": 0.78},
				{"key": "expertPurse", "share": 0.22}
			]
			var food_unit_price := float(maxi(1, price(port, "food", "sell")))
			for pf in purse_food_shares:
				var p_key := str(pf["key"])
				var want_food := total_food_need * float(pf["share"])
				var avail_food := maxf(0.0, float(working_stocks.get("food", 0.0)))
				var purse_bal := int(port[p_key])
				if avail_food > 1e-5 and purse_bal > 0 and want_food > 0.0:
					var max_qty := minf(want_food, avail_food)
					var desired_coins := maxi(1, int(ceil(max_qty * food_unit_price)))
					var spend_coins := mini(purse_bal, desired_coins)
					var bought_qty := minf(avail_food, minf(want_food, float(spend_coins) / food_unit_price))
					if spend_coins > 0 and bought_qty > 0.0:
						var tx_tax := int(floor(float(spend_coins) * TRANSACTION_TAX_RATE))
						var net_business := spend_coins - tx_tax
						port[p_key] = int(port[p_key]) - spend_coins
						port["cash"] = int(port["cash"]) + net_business
						port["governmentPurse"] = int(port["governmentPurse"]) + tx_tax
						working_stocks["food"] = maxf(0.0, avail_food - bought_qty)
						food_bought_total += bought_qty
						_append_ledger(port, {
							"type": "resident_food",
							"from": p_key,
							"to": "cash",
							"coins": spend_coins,
							"tax": tx_tax,
							"good": "food",
							"qty": _clean_stock(bought_qty)
						})

			var food_met_ratio := clampf(food_bought_total / maxf(0.01, total_food_need), 0.0, 1.0)
			if food_met_ratio < 0.85:
				shortage_items.append("food")

			# Domestic & specialist workshop consumption of local non-food goods (recycles resident purses into business cash)
			var domestic_goods := ["supplies", "fuel", "timber", "charcoal", "logs", "iron", "ammo"]
			for p_key in ["householdPurse", "expertPurse"]:
				var purse_bal := int(port[p_key])
				var target_sav := maxi(600, workforce * (8 if p_key == "householdPurse" else 3) * ORDINARY_WAGE)
				var spend_rate := 0.14 if purse_bal > target_sav else 0.06
				var dom_budget := int(floor(float(purse_bal) * spend_rate * dt))
				if dom_budget <= 0:
					continue
				for dg in domestic_goods:
					if dom_budget <= 0:
						break
					var avail_dg := maxf(0.0, float(working_stocks.get(dg, 0.0)))
					var eq_dg := float(get_equilibrium_stock(port, dg))
					if avail_dg <= eq_dg * 0.35:
						continue
					var unit_p := float(maxi(1, price(port, dg, "sell")))
					var max_surplus_use := (avail_dg - eq_dg * 0.35) * 0.12 * dt
					var want_coins := int(ceil(max_surplus_use * unit_p))
					var spend := mini(dom_budget, mini(int(port[p_key]), want_coins))
					if spend <= 0:
						continue
					var qty_used := minf(max_surplus_use, float(spend) / unit_p)
					var tx_tax := int(floor(float(spend) * TRANSACTION_TAX_RATE))
					var net_bus := spend - tx_tax
					port[p_key] = int(port[p_key]) - spend
					port["cash"] = int(port["cash"]) + net_bus
					port["governmentPurse"] = int(port["governmentPurse"]) + tx_tax
					working_stocks[dg] = maxf(0.0, avail_dg - qty_used)
					dom_budget -= spend

			# Phase C: Government Public Workers Payroll & Public Stores Procurement
			var employed_ind_workers := 0
			var emp_int_map: Dictionary = _empty_employed_map()
			for occ in OCCUPATION_KEYS:
				var c_occ := maxi(0, int(round(float(employed_days_float.get(occ, 0.0)))))
				if float(employed_days_float.get(occ, 0.0)) > 0.01 and c_occ == 0:
					c_occ = 1
				emp_int_map[occ] = c_occ
				employed_ind_workers += c_occ
			employed_ind_workers = mini(workforce, employed_ind_workers)

			var max_pub_slot := maxi(0, mini(target_public, workforce - employed_ind_workers))
			var gov_bal := int(port["governmentPurse"])
			var pub_wage_budget := int(floor(float(gov_bal) * minf(0.30, 0.10 * dt)))
			var pub_unit_wage := int(round((float(ORDINARY_WAGE) * 0.82 + float(WAGES["foreman"]) * 0.18) * dt))
			pub_unit_wage = maxi(1, pub_unit_wage)
			var paid_public_workers := mini(max_pub_slot, pub_wage_budget / pub_unit_wage) if pub_wage_budget >= pub_unit_wage else 0
			var public_payroll := paid_public_workers * pub_unit_wage
			if public_payroll > 0:
				var pub_expert_pay := int(floor(float(public_payroll) * 0.22))
				var pub_hh_pay := public_payroll - pub_expert_pay
				port["governmentPurse"] = int(port["governmentPurse"]) - public_payroll
				port["householdPurse"] = int(port["householdPurse"]) + pub_hh_pay
				port["expertPurse"] = int(port["expertPurse"]) + pub_expert_pay
				household_wage_in += pub_hh_pay
				expert_wage_in += pub_expert_pay
				_append_ledger(port, {
					"type": "public_payroll",
					"from": "governmentPurse",
					"to": "householdPurse+expertPurse",
					"coins": public_payroll,
					"workers": paid_public_workers
				})

			# Government procurement into publicStores (transfers governmentPurse -> business cash)
			gov_bal = int(port["governmentPurse"])
			var gov_procure_budget := int(floor(float(gov_bal) * 0.08 * dt))
			if gov_procure_budget > 0:
				for pg in ["food", "supplies", "fuel", "ammo", "timber", "iron", "gunpowder"]:
					if gov_procure_budget <= 0:
						break
					var avail_pg := maxf(0.0, float(working_stocks.get(pg, 0.0)))
					var eq_pg := float(get_equilibrium_stock(port, pg))
					if avail_pg <= eq_pg * 0.45:
						continue
					var unit_p := float(maxi(1, price(port, pg, "sell")))
					var max_buy_qty := minf((avail_pg - eq_pg * 0.45) * 0.15 * dt, float(gov_procure_budget) / unit_p)
					var spend := mini(gov_procure_budget, mini(int(port["governmentPurse"]), int(floor(max_buy_qty * unit_p))))
					if spend <= 0:
						continue
					var bought_pg := minf(avail_pg, float(spend) / unit_p)
					port["governmentPurse"] = int(port["governmentPurse"]) - spend
					port["cash"] = int(port["cash"]) + spend
					working_stocks[pg] = maxf(0.0, avail_pg - bought_pg)
					public_stores[pg] = _clean_stock(float(public_stores.get(pg, 0.0)) + bought_pg)
					gov_procure_budget -= spend
					_append_ledger(port, {
						"type": "government_procurement",
						"from": "governmentPurse",
						"to": "cash",
						"coins": spend,
						"good": pg,
						"qty": _clean_stock(bought_pg)
					})

			# Civic upkeep consumption from publicStores
			for pg in GOOD_KEYS:
				var cur_pub := float(public_stores.get(pg, 0.0))
				var cap_pub := float(get_equilibrium_stock(port, pg)) * 0.35
				if cur_pub > cap_pub:
					public_stores[pg] = _clean_stock(cur_pub - (cur_pub - cap_pub) * 0.15 * dt)

			# Commit float physical stocks and check low stock shortages
			for g in GOOD_KEYS:
				var final_s := _clean_stock(maxf(0.0, float(working_stocks.get(g, 0.0))))
				stocks[g] = final_s
				var eq := float(get_equilibrium_stock(port, g))
				if final_s < eq * 0.22:
					shortage_items.append(g)

			# Prosperity update based on food satisfaction, employment, and blockade
			var wealth_factor := _normalize_wealth_factor(port.get("wealth", 1.0))
			var emp_ratio := float(employed_ind_workers + paid_public_workers) / float(maxi(1, workforce)) if workforce > 0 else 0.0
			var target_prosperity := clampf(48.0 + (wealth_factor - 1.0) * 20.0 + emp_ratio * 15.0 - (18.0 if blockaded else 0.0), 18.0, 94.0)
			var next_prosperity := float(port.get("prosperity", target_prosperity)) if _is_num(port.get("prosperity")) else target_prosperity
			if food_met_ratio < 0.75:
				next_prosperity -= 1.2 * dt
			elif blockaded:
				next_prosperity -= 0.4 * dt
			else:
				next_prosperity += (target_prosperity - next_prosperity) * 0.08 * dt
			port["prosperity"] = clampf(snappedf(next_prosperity, 0.1), 0.0, 100.0)

			# Record workforce & employment telemetry (no automatic new workers created)
			port["workforce"] = workforce
			port["workers"] = employed_ind_workers
			port["employedWorkers"] = employed_ind_workers
			port["publicWorkers"] = paid_public_workers
			var avail_w := maxi(0, workforce - employed_ind_workers - paid_public_workers)
			port["availableWorkers"] = avail_w

			replenish_volunteers(port,dt)

			var employed_expert_workers := 0
			for occ in OCCUPATION_KEYS:
				if is_expert_occupation(occ):
					employed_expert_workers += int(emp_int_map.get(occ, 0))
			var total_spec := clampi(int(port.get("specialists", port.get("specialistWorkers", 0))), 0, workforce)
			var yard_spec_reserve := maxi(1, int(round(float(total_spec) * 0.25))) if total_spec > 0 else 0
			var avail_spec := clampi(maxi(yard_spec_reserve, total_spec - employed_expert_workers), 0, mini(total_spec, avail_w))
			port["specialists"] = total_spec
			port["specialistWorkers"] = total_spec
			port["availableSpecialists"] = avail_spec

			port["employed"] = emp_int_map
			port["employedByOccupation"] = emp_int_map.duplicate(true)
			port["lastPayroll"] = {
				"total": business_payroll + public_payroll,
				"business": business_payroll,
				"household": household_wage_in,
				"expert": expert_wage_in,
				"public": public_payroll,
				"tax": wage_tax_total,
				"byOccupation": payroll_by_occ
			}
			port["lastProduction"] = _make_last_production(produced_rate)
			port["projectedProduction"] = _make_last_production(produced_rate)
			port["shortages"] = _make_shortages(shortage_items)

			if is_last_step:
				if blockaded:
					events.append(str(port.get("name", "Port")) + " remains under blockade; harbor trade restricted.")
				elif not (port["shortages"] as Array).is_empty():
					var sh: Array = port["shortages"]
					var top_sh := str(sh[0]) if sh.size() == 1 else "%s, %s" % [str(sh[0]), str(sh[1])]
					events.append("%s reports shortages of %s." % [str(port.get("name", "Port")), top_sh])

		# 2. Inter-port exchange (strictly conserves both physical goods and integer bronze coins)
		if allow_interport:
			var open_ports: Array = []
			for p_item in ports:
				if p_item is Dictionary and p_item.get("stocks") is Dictionary and not _is_port_blockaded(p_item, blockaded_opt):
					open_ports.append(p_item)

			if open_ports.size() >= 2:
				for g in GOOD_KEYS:
					var ranked: Array = []
					for p in open_ports:
						var eq := maxf(6.0, float(get_equilibrium_stock(p, g)))
						var cur := maxf(0.0, float(p["stocks"].get(g, 0.0)))
						ranked.append({"port": p, "eq": eq, "cur": cur, "ratio": cur / eq})
					ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["ratio"]) > float(b["ratio"]))

					var max_pairs := mini(3, ranked.size() / 2)
					for pair_idx in range(max_pairs):
						var exp_entry: Dictionary = ranked[pair_idx]
						var imp_entry: Dictionary = ranked[ranked.size() - 1 - pair_idx]
						if exp_entry["port"] == imp_entry["port"]:
							break
						if float(exp_entry["ratio"]) <= float(imp_entry["ratio"]) + 0.12:
							break

						var exporter: Dictionary = exp_entry["port"]
						var importer: Dictionary = imp_entry["port"]
						var exp_stock := int(floor(float(exporter["stocks"].get(g, 0.0))))
						var imp_cash := int(importer.get("cash", 0))
						if exp_stock < 3 or imp_cash < 400:
							continue

						var exp_avail := maxf(0.0, float(exp_stock) - float(exp_entry["eq"]) * 0.40)
						var imp_need := maxf(1.0, float(imp_entry["eq"]) * 1.05 - float(importer["stocks"].get(g, 0.0)))
						var raw_move := minf(minf(exp_avail * 0.30, imp_need * 0.30), 18.0) * dt
						var unit_trade_price := maxi(1, int(round(float(price(exporter, g, "buy") + price(importer, g, "sell")) * 0.5)))
						var cash_reserve := float(maxi(200, int(importer.get("workforce", 0)) * 40)) if int(importer.get("workforce", 0)) > 0 else 200.0
						var max_spend := maxf(0.0, (float(imp_cash) - cash_reserve) * 0.25)
						var max_affordable := int(floor(max_spend / float(unit_trade_price)))
						var move_qty := mini(int(floor(raw_move)), max_affordable)
						if move_qty == 0 and raw_move >= 0.40 and max_affordable >= 1 and exp_stock >= 4:
							move_qty = 1

						if move_qty >= 1:
							var trade_coins := move_qty * unit_trade_price
							exporter["stocks"][g] = _clean_stock(float(exporter["stocks"][g]) - float(move_qty))
							importer["stocks"][g] = _clean_stock(float(importer["stocks"][g]) + float(move_qty))
							importer["cash"] = int(importer["cash"]) - trade_coins
							exporter["cash"] = int(exporter["cash"]) + trade_coins

							_append_ledger(exporter, {
								"type": "export",
								"from": str(importer.get("id", "importer")),
								"to": "cash",
								"coins": trade_coins,
								"good": g,
								"qty": move_qty
							})
							_append_ledger(importer, {
								"type": "import",
								"from": "cash",
								"to": str(exporter.get("id", "exporter")),
								"coins": trade_coins,
								"good": g,
								"qty": move_qty
							})

							if events.size() < 10:
								events.append(
									"Coaster moved %d %s from %s to %s (%d coins)." % [
										move_qty,
										str(GOODS[g]["name"]),
										str(exporter.get("name", "Exporter")),
										str(importer.get("name", "Importer")),
										trade_coins
									]
								)

	if events.is_empty() and ports[0] is Dictionary:
		events.append(str(ports[0].get("name", "Harbor")) + " harbor markets completed daily production and coastal trade.")

	return events.slice(0, 10)
