extends RefCounted
## Shared NPC fleet state lookups, reserves/performance evaluation, and order selection (v0.013).
## Leaf NavalAI sub-module: preloads only core economy/damage/goods scripts (no preload cycles).

const Factions=preload("res://scripts/factions.gd")
const RegionalOrders=preload("res://scripts/regional_orders.gd")
const Damage = preload("res://scripts/damage.gd")
const Economy = preload("res://scripts/economy.gd")
const Goods = preload("res://scripts/goods.gd")
const Fleets = preload("res://scripts/fleet_economy.gd")

const CELL_SIZE: float = 240.0
const MAX_ORDER_LOG: int = 8
const MAX_EVENT_LOG: int = 24


static func is_story_owner(owner: Dictionary) -> bool:
	return str(owner.get("id", "")).begins_with("story-")


static func state_of(core_or_state) -> Dictionary:
	if core_or_state is Dictionary:
		var d: Dictionary = core_or_state
		if d.has("state") and d.get("state") is Dictionary:
			var sub: Dictionary = d["state"]
			return sub
		return d
	if core_or_state != null and ("state" in core_or_state) and core_or_state.state is Dictionary:
		var st: Dictionary = core_or_state.state
		return st
	return {}


static func world_of(core_or_state) -> Dictionary:
	if core_or_state is Dictionary:
		var d: Dictionary = core_or_state
		if d.has("data") and d.get("data") is Dictionary:
			var sub_data: Dictionary = d["data"]
			return sub_data
		if d.has("world") and d.get("world") is Dictionary:
			var sub_world: Dictionary = d["world"]
			return sub_world
		return {}
	if core_or_state != null and ("data" in core_or_state) and core_or_state.data is Dictionary:
		var wd: Dictionary = core_or_state.data
		return wd
	return {}


static func find_port(state: Dictionary, port_id: String) -> Dictionary:
	if port_id.is_empty():
		return {}
	var ports: Array = state.get("ports", []) if state.get("ports") is Array else []
	for p_var in ports:
		if p_var is Dictionary:
			var p: Dictionary = p_var
			if str(p.get("id", "")) == port_id:
				return p
	return {}


static func find_owner(state: Dictionary, owner_id: String) -> Dictionary:
	if owner_id.is_empty():
		return {}
	var owners: Array = state.get("fleetOwners", []) if state.get("fleetOwners") is Array else []
	for o_var in owners:
		if o_var is Dictionary:
			var o: Dictionary = o_var
			if str(o.get("id", "")) == owner_id:
				return o
	return {}


static func find_patrol(state: Dictionary, patrol_id: String) -> Dictionary:
	if patrol_id.is_empty():
		return {}
	var patrols: Array = state.get("patrols", []) if state.get("patrols") is Array else []
	for p_var in patrols:
		if p_var is Dictionary:
			var p: Dictionary = p_var
			if str(p.get("id", "")) == patrol_id:
				return p
	return {}


static func hull_spec(core_or_state, state: Dictionary, world: Dictionary, hull_id: String) -> Dictionary:
	if hull_id.is_empty():
		return {}
	if not (core_or_state is Dictionary) and core_or_state != null and core_or_state.has_method("hull"):
		var h_call: Dictionary = core_or_state.hull(hull_id)
		if not h_call.is_empty():
			return h_call
	var hulls: Array = world.get("HULLS", []) if world.get("HULLS") is Array else []
	for h_var in hulls:
		if h_var is Dictionary:
			var h: Dictionary = h_var
			if str(h.get("id", "")) == hull_id:
				return h
	var owners: Array = state.get("fleetOwners", []) if state.get("fleetOwners") is Array else []
	for o_var in owners:
		if not (o_var is Dictionary):
			continue
		var o: Dictionary = o_var
		var o_boats: Array = o.get("boats", []) if o.get("boats") is Array else []
		for b_var in o_boats:
			if b_var is Dictionary:
				var b: Dictionary = b_var
				if str(b.get("type", "")) == hull_id and b.get("spec") is Dictionary:
					var spec_d: Dictionary = b["spec"]
					return spec_d.duplicate(true)
	var p_fleet: Array = state.get("fleet", []) if state.get("fleet") is Array else []
	for b_var in p_fleet:
		if b_var is Dictionary:
			var b: Dictionary = b_var
			if str(b.get("type", "")) == hull_id and b.get("spec") is Dictionary:
				var spec_d: Dictionary = b["spec"]
				return spec_d.duplicate(true)
	return {
		"id": hull_id,
		"name": hull_id.capitalize(),
		"role": "skiff",
		"tier": 1,
		"size": 14.0,
		"hp": 115.0,
		"armor": 2.0,
		"speed": 108.0,
		"turn": 2.2,
		"cargo": 45.0,
		"pumps": 2.1,
		"crewMin": 2,
		"crewOptimal": 4,
		"crewMax": 6,
		"weapon": "gun",
		"damage": 9.0,
		"fireRate": 2.2,
		"range": 330.0
	}


static func living_boats(owner: Dictionary) -> Array:
	var out: Array = []
	var boats: Array = owner.get("boats", []) if owner.get("boats") is Array else []
	for b_var in boats:
		if b_var is Dictionary:
			var b: Dictionary = b_var
			if not bool(b.get("sunk", false)):
				out.append(b)
	return out


static func owner_position(state: Dictionary, owner: Dictionary) -> Vector2:
	var patrol: Dictionary = find_patrol(state, str(owner.get("id", "")))
	if not patrol.is_empty() and patrol.has("x") and patrol.has("y"):
		return Vector2(float(patrol.get("x", 0.0)), float(patrol.get("y", 0.0)))
	var at_id: String = str(owner.get("atPort", ""))
	if at_id.is_empty():
		at_id = str(owner.get("homePort", ""))
	var p: Dictionary = find_port(state, at_id)
	return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))


static func port_dist(a: Dictionary, b: Dictionary) -> float:
	if a.is_empty() or b.is_empty():
		return 1000.0
	var pos_a: Vector2 = Vector2(float(a.get("x", 0.0)), float(a.get("y", 0.0)))
	var pos_b: Vector2 = Vector2(float(b.get("x", 0.0)), float(b.get("y", 0.0)))
	return pos_a.distance_to(pos_b)


static func fleet_reserves(owner: Dictionary) -> Dictionary:
	Fleets.normalize_owner(owner)
	var costs: Dictionary = Fleets.upkeep(owner)
	var crew_total: int = 0
	var able_total: float = 0.0
	var min_crew_total: int = 0
	var hp_sum: float = 0.0
	var max_hp_sum: float = 0.0
	var min_engine: float = 1.0
	var boat_fuel: float = 0.0
	var boat_ammo: float = 0.0
	var boat_supplies: float = 0.0
	var cap_total: float = 0.0
	var living: int = 0
	var boats: Array = owner.get("boats", []) if owner.get("boats") is Array else []
	for b_var in boats:
		if not (b_var is Dictionary):
			continue
		var b: Dictionary = b_var
		if bool(b.get("sunk", false)):
			continue
		living += 1
		var c: float = maxf(0.0, float(b.get("crew", 0.0)))
		var w: float = clampf(float(b.get("wounded", 0.0)), 0.0, c)
		crew_total += int(round(c))
		able_total += maxf(0.0, c - w)
		min_crew_total += maxi(1, int(round(float(b.get("crewMin", 2.0)))))
		hp_sum += maxf(0.0, float(b.get("hp", 0.0)))
		max_hp_sum += maxf(1.0, float(b.get("maxHp", 100.0)))
		min_engine = minf(min_engine, clampf(float(b.get("engine", 1.0)), 0.0, 1.0))
		boat_fuel += maxf(0.0, float(b.get("fuel", 0.0)))
		boat_ammo += maxf(0.0, float(b.get("ammo", 0.0)))
		boat_supplies += maxf(0.0, float(b.get("supplies", 0.0)))
		var spec_d: Dictionary = b.get("spec", {}) if b.get("spec") is Dictionary else {}
		cap_total += maxf(0.0, float(spec_d.get("cargo", 0.0)))
	if living == 0:
		min_engine = 0.0
	var cargo: Dictionary = owner.get("cargo", {}) if owner.get("cargo") is Dictionary else {}
	var trade_good: String = str(owner.get("tradeGood", ""))
	var trade_qty: float = maxf(0.0, float(owner.get("tradeCargo", 0.0)))
	var hold_fuel: float = maxf(0.0, float(cargo.get("fuel", 0.0)) - (trade_qty if trade_good == "fuel" else 0.0))
	var hold_food: float = maxf(0.0, float(cargo.get("food", 0.0)) - (trade_qty if trade_good == "food" else 0.0))
	var hold_ammo: float = maxf(0.0, float(cargo.get("ammo", 0.0)) - (trade_qty if trade_good == "ammo" else 0.0)) * float(Goods.ROUNDS_PER_CASE)
	var hold_supplies: float = maxf(0.0, float(cargo.get("supplies", 0.0)) - (trade_qty if trade_good == "supplies" else 0.0))
	var total_fuel: float = snappedf(boat_fuel + hold_fuel, 0.01)
	var total_food: float = snappedf(hold_food, 0.01)
	var total_ammo: float = snappedf(boat_ammo + hold_ammo, 0.1)
	var total_supplies: float = snappedf(boat_supplies + hold_supplies, 0.01)
	var daily_fuel: float = float(costs.get("fuel", 0.0))
	var daily_food: float = float(costs.get("food", 0.0))
	var daily_wages: float = float(costs.get("wages", 0.0))
	var owner_coins: int = maxi(0, int(owner.get("coins", 0)))
	var wage_arrears: int = maxi(0, int(owner.get("wageArrears", 0)))
	var net_coins: int = maxi(0, owner_coins - wage_arrears)
	var default_target: int = maxi(1, boats.size())
	return {
		"coins": owner_coins,
		"crewPurse": maxi(0, int(owner.get("crewPurse", 0))),
		"wageArrears": wage_arrears,
		"crew": crew_total,
		"ableCrew": snappedf(able_total, 0.1),
		"minCrew": min_crew_total,
		"boats": living,
		"targetBoats": maxi(1, int(owner.get("targetBoats", default_target))),
		"hpRatio": snappedf(hp_sum / maxf(1.0, max_hp_sum), 0.001) if living > 0 else 0.0,
		"minEngine": snappedf(min_engine, 0.001),
		"fuel": total_fuel,
		"fuelDays": snappedf(total_fuel / maxf(0.01, daily_fuel), 0.01) if daily_fuel > 0.0 else 0.0,
		"food": total_food,
		"foodDays": snappedf(total_food / maxf(0.01, daily_food), 0.01) if daily_food > 0.0 else 0.0,
		"ammo": total_ammo,
		"supplies": total_supplies,
		"wageDays": snappedf(float(net_coins) / maxf(1.0, daily_wages), 0.01) if daily_wages > 0.0 else 0.0,
		"tradeCargo": trade_qty,
		"capacity": cap_total
	}


static func fleet_performance(owner: Dictionary) -> Dictionary:
	Fleets.normalize_owner(owner)
	var morale: float = clampf(float(owner.get("morale", 85.0)), 10.0, 100.0)
	var perf_factor: float = clampf(float(owner.get("performanceFactor", morale / 85.0)), 0.35, 1.0)
	var min_speed: float = 170.0
	var firepower: float = 0.0
	var living: int = 0
	var has_undercrewed: bool = false
	var boats: Array = owner.get("boats", []) if owner.get("boats") is Array else []
	for b_var in boats:
		if not (b_var is Dictionary):
			continue
		var b: Dictionary = b_var
		if bool(b.get("sunk", false)):
			continue
		living += 1
		var status: Dictionary = Damage.get_status(b)
		var spec_d: Dictionary = b.get("spec", {}) if b.get("spec") is Dictionary else {}
		var base_spd: float = float(b.get("economyBaseSpeed", spec_d.get("speed", 90.0)))
		var fuel_mult: float = 1.0 if float(b.get("fuel", 0.0)) > 0.0 else 0.2
		var b_spd: float = base_spd * perf_factor * maxf(0.25, float(status.get("speedFactor", 1.0))) * fuel_mult
		min_speed = minf(min_speed, b_spd)
		if float(b.get("crew", 0.0)) < float(b.get("crewMin", 1.0)):
			has_undercrewed = true
		var wf: float = float(status.get("weaponFactor", 0.0)) * perf_factor
		if float(b.get("ammo", 0.0)) > 0.0 and wf > 0.0:
			var mounts: Array = spec_d.get("weaponMounts", []) if spec_d.get("weaponMounts") is Array else []
			if not mounts.is_empty():
				for m_var in mounts:
					if m_var is Dictionary:
						var m: Dictionary = m_var
						var dmg: float = maxf(1.0, float(m.get("damage", 10.0)))
						var fr: float = maxf(0.1, float(m.get("fireRate", 1.0)))
						var mult: float = 1.8 if str(m.get("kind", "")) == "torpedo" else 1.0
						firepower += dmg * fr * mult * wf
			else:
				var dmg: float = maxf(1.0, float(spec_d.get("damage", 10.0)))
				var fr: float = maxf(0.1, float(b.get("economyBaseFireRate", spec_d.get("fireRate", 1.0))))
				firepower += dmg * fr * wf
	if living == 0:
		min_speed = 0.0
	var res: Dictionary = fleet_reserves(owner)
	var seaworthy: bool = (
		living > 0
		and not has_undercrewed
		and float(res.get("hpRatio", 0.0)) >= 0.62
		and float(res.get("minEngine", 0.0)) >= 0.68
		and float(res.get("ammo", 0.0)) >= float(living) * 18.0
		and float(res.get("fuel", 0.0)) >= float(living) * 0.6
	)
	return {
		"performanceFactor": snappedf(perf_factor, 0.001),
		"morale": snappedf(morale, 0.1),
		"speed": snappedf(min_speed, 0.1),
		"firepower": snappedf(firepower, 0.1),
		"seaworthy": seaworthy
	}


static func needs_home_recovery(owner: Dictionary, res: Dictionary, perf: Dictionary) -> String:
	var living: int = int(res.get("boats", 0))
	var target_boats: int = int(res.get("targetBoats", 1))
	if living <= 0:
		return "All hulls lost; returning to home shipyard for replacement."
	if living < target_boats:
		return "Fleet below strength (%d/%d hulls); returning home for replacement." % [living, target_boats]
	var boats: Array = owner.get("boats", []) if owner.get("boats") is Array else []
	for b_var in boats:
		if not (b_var is Dictionary):
			continue
		var b: Dictionary = b_var
		if bool(b.get("sunk", false)):
			continue
		var b_name: String = str(b.get("name", "Hull"))
		if float(b.get("crew", 0.0)) < float(b.get("crewMin", 1.0)):
			return "%s is under minimum crew; returning to home harbor." % b_name
		var breach_area: float = float(Damage.sum_areas(b))
		if float(b.get("fire", 0.0)) > 1.0 or breach_area > 0.1 or float(b.get("water", 0.0)) > float(b.get("capacity", 200.0)) * 0.2:
			return "%s has active hull breaches or flooding; returning home for drydock." % b_name
		if float(b.get("hp", 0.0)) < float(b.get("maxHp", 100.0)) * 0.58 or float(b.get("engine", 1.0)) < 0.68:
			return "%s suffered hull or engine damage; returning home for repair." % b_name
	var hp_ratio: float = float(res.get("hpRatio", 1.0))
	var min_eng: float = float(res.get("minEngine", 1.0))
	if hp_ratio < 0.65 or min_eng < 0.68:
		return "Fleet damaged (HP %.0f%%, engine %.0f%%); returning home for repair." % [hp_ratio * 100.0, min_eng * 100.0]
	var ammo_val: float = float(res.get("ammo", 0.0))
	if ammo_val < float(living) * 18.0:
		return "Ammunition depleted (%.0f rounds); returning home to resupply." % ammo_val
	var fuel_val: float = float(res.get("fuel", 0.0))
	if fuel_val < float(living) * 0.6:
		return "Working fuel low (%.1f drums); returning home to refuel." % fuel_val
	if not bool(perf.get("seaworthy", true)):
		return "Fleet requires harbor refit and resupply."
	return ""


static func build_order(state: Dictionary, owner: Dictionary, purpose: String = "", destination: String = "", reason: String = "", target_owner_id: String = "") -> Dictionary:
	var res: Dictionary = fleet_reserves(owner)
	var perf: Dictionary = fleet_performance(owner)
	var ports: Array = state.get("ports", []) if state.get("ports") is Array else []
	var fallback_port: String = str(owner.get("homePort", ""))
	if fallback_port.is_empty() and not ports.is_empty() and ports[0] is Dictionary:
		var first_port: Dictionary = ports[0]
		fallback_port = str(first_port.get("id", ""))
	var dest: String = destination
	if dest.is_empty() or find_port(state, dest).is_empty():
		var route: Array = owner.get("route", []) if owner.get("route") is Array else []
		if route.size() >= 2 and not find_port(state, str(route[1])).is_empty():
			dest = str(route[1])
		elif not route.is_empty() and not find_port(state, str(route[0])).is_empty():
			dest = str(route[0])
		else:
			dest = fallback_port
	var purp: String = purpose
	if purp.is_empty():
		var owner_kind: String = str(owner.get("kind", "patrol"))
		if is_story_owner(owner):
			purp = "blockade"
		elif owner_kind == "trader":
			purp = "deliver"
		elif owner_kind == "raider":
			purp = "raid"
		else:
			purp = "patrol"
	var why: String = reason
	if why.is_empty():
		var p_name: String = str(find_port(state, dest).get("name", dest))
		why = "%s order toward %s." % [purp.capitalize(), p_name]
	var seq: int = int(owner.get("orderSeq", 0)) + 1
	owner["orderSeq"] = seq
	var at_port: String = str(owner.get("atPort", ""))
	var origin_id: String = at_port if not at_port.is_empty() else str(owner.get("homePort", fallback_port))
	var ord: Dictionary = {
		"id": "ord-%s-%d" % [str(owner.get("id", "npc")), seq],
		"ownerId": str(owner.get("id", "")),
		"kind": str(owner.get("kind", "patrol")),
		"purpose": purp,
		"origin": origin_id,
		"destination": dest,
		"targetOwnerId": target_owner_id,
		"tradeGood": str(owner.get("tradeGood", "timber")),
		"reason": why,
		"day": int(state.get("econDay", 1)),
		"reserves": res,
		"performance": perf,
		"coins": int(res.get("coins", 0)),
		"crew": int(res.get("crew", 0)),
		"boats": int(res.get("boats", 0)),
		"hpRatio": float(res.get("hpRatio", 0.0)),
		"fuel": float(res.get("fuel", 0.0)),
		"food": float(res.get("food", 0.0)),
		"ammo": float(res.get("ammo", 0.0)),
		"supplies": float(res.get("supplies", 0.0)),
		"speed": float(perf.get("speed", 0.0)),
		"firepower": float(perf.get("firepower", 0.0)),
		"performanceFactor": float(perf.get("performanceFactor", 1.0)),
		"morale": float(perf.get("morale", 85.0))
	}
	owner["order"] = ord
	owner["purpose"] = purp
	owner["destination"] = dest
	owner["reason"] = why
	if not (owner.get("orders") is Array):
		owner["orders"] = []
	var orders_log: Array = owner["orders"]
	orders_log.push_front(ord.duplicate(true))
	if orders_log.size() > MAX_ORDER_LOG:
		orders_log.resize(MAX_ORDER_LOG)
	if state.get("navalAi") is Dictionary:
		var nav_ai: Dictionary = state["navalAi"]
		if nav_ai.get("ordersByOwner") is Dictionary:
			var by_owner: Dictionary = nav_ai["ordersByOwner"]
			by_owner[str(owner.get("id", ""))] = ord
	return ord


static func pick_export_good(home: Dictionary, current_good: String) -> String:
	var best_good: String = current_good if Goods.ITEMS.has(current_good) else "timber"
	if home.is_empty() or not (home.get("stocks") is Dictionary):
		return best_good
	var stocks: Dictionary = home["stocks"]
	if float(stocks.get(best_good, 0.0)) >= 4.0:
		return best_good
	var best_score: float = -INF
	var candidates: Array = ["timber", "iron", "fuel", "supplies", "food", "copper", "logs", "ore"]
	for g_var in candidates:
		var g: String = str(g_var)
		if not Goods.ITEMS.has(g):
			continue
		var avail: float = float(stocks.get(g, 0.0))
		if avail < 2.0:
			continue
		var eq: float = maxf(6.0, float(Economy.get_equilibrium_stock(home, g)))
		var spec_bonus: float = 0.35 if str(home.get("specialty", "")) == g else 0.0
		var score: float = avail / eq + spec_bonus
		if score > best_score:
			best_score = score
			best_good = g
	return best_good


static func select_trader_order(state: Dictionary, owner: Dictionary, current_port_id: String) -> Dictionary:
	var home_id: String = str(owner.get("homePort", ""))
	var home: Dictionary = find_port(state, home_id)
	var cur_port: Dictionary = find_port(state, current_port_id)
	var trade_cargo: float = maxf(0.0, float(owner.get("tradeCargo", 0.0)))
	if trade_cargo <= 0.5 and not current_port_id.is_empty() and current_port_id != home_id and not home.is_empty():
		var export_good: String = pick_export_good(home, str(owner.get("tradeGood", "timber")))
		owner["tradeGood"] = export_good
		return {
			"purpose": "resupply",
			"destination": home_id,
			"targetOwnerId": "",
			"reason": "Returning to %s to load %s stock for export." % [str(home.get("name", home_id)), export_good]
		}
	var origin_port: Dictionary = cur_port if not cur_port.is_empty() else home
	var export_src: Dictionary = home if not home.is_empty() else origin_port
	var good: String = str(owner.get("tradeGood","timber")) if trade_cargo>0 else pick_export_good(export_src,str(owner.get("tradeGood","timber")))
	owner["tradeGood"] = good
	var buy_port: Dictionary = origin_port if not origin_port.is_empty() else home
	var buy_price: int = int(Economy.price(buy_port, good, "buy"))
	var best_id: String = ""
	var best_score: float = -INF
	var best_reason: String = ""
	var ports: Array = state.get("ports", []) if state.get("ports") is Array else []
	for p_var in ports:
		if not (p_var is Dictionary):
			continue
		var p: Dictionary = p_var
		var pid: String = str(p.get("id", ""))
		if pid.is_empty() or pid == current_port_id:
			continue
		if state.has("relationships") and str(p.get("faction",""))!=str(owner.get("faction","")) and Factions.relation(state,str(owner.get("faction","")),str(p.get("faction","")))<=-20:
			continue
		var sell_price: int = int(Economy.price(p, good, "sell"))
		var eq: float = maxf(6.0, float(Economy.get_equilibrium_stock(p, good)))
		var p_stocks: Dictionary = p.get("stocks", {}) if p.get("stocks") is Dictionary else {}
		var stock: float = maxf(0.0, float(p_stocks.get(good, 0.0)))
		var demand_gap: float = clampf((eq - stock) / eq, -0.5, 1.0)
		var liquidity: float = clampf(float(p.get("cash", 0)) / maxf(200.0, float(sell_price) * maxf(4.0, trade_cargo)), 0.1, 1.0)
		var dist: float = port_dist(origin_port, p)
		var margin: float = float(sell_price - buy_price)
		var score: float = float(sell_price) * (1.0 + 0.65 * maxf(0.0, demand_gap)) * liquidity + margin * 0.45 - dist * 0.012
		if score > best_score:
			best_score = score
			best_id = pid
			best_reason = "Delivering %s to %s (sell %d coins, local stock %.0f/%d)." % [good, str(p.get("name", pid)), sell_price, stock, int(round(eq))]
	if best_id.is_empty():
		for p_var in ports:
			if p_var is Dictionary:
				var p: Dictionary = p_var
				var pid: String = str(p.get("id", ""))
				if pid != current_port_id:
					best_id = pid
					best_reason = "Sailing trade route to %s." % str(p.get("name", best_id))
					break
	return {
		"purpose": "deliver",
		"destination": best_id if not best_id.is_empty() else home_id,
		"targetOwnerId": "",
		"reason": best_reason
	}


static func select_patrol_order(state: Dictionary, owner: Dictionary, current_port_id: String) -> Dictionary:
	var home_id: String = str(owner.get("homePort", ""))
	var origin_port: Dictionary = find_port(state, current_port_id if not current_port_id.is_empty() else home_id)
	var my_pos: Vector2 = owner_position(state, owner)
	var owners: Array = state.get("fleetOwners", []) if state.get("fleetOwners") is Array else []

	var best_raider: Dictionary = {}
	var best_raider_port: String = ""
	var best_raider_score: float = -INF
	for other_var in owners:
		if not (other_var is Dictionary):
			continue
		var other: Dictionary = other_var
		if is_story_owner(other) or not bool(other.get("active", false)):
			continue
		if state.has("relationships") and Factions.relation(state,str(owner.get("faction","")),str(other.get("faction","")))>-20:continue
		if str(other.get("kind", "")) != "raider" or living_boats(other).is_empty():
			continue
		var r_patrol: Dictionary = find_patrol(state, str(other.get("id", "")))
		var r_ord: Dictionary = other.get("order", {}) if other.get("order") is Dictionary else {}
		var r_dest: String = str(r_ord.get("destination", r_patrol.get("to", "")))
		if r_dest.is_empty() or r_dest == current_port_id:
			var r_from: String = str(r_patrol.get("from", other.get("homePort", "")))
			r_dest = r_from if r_from != current_port_id else r_dest
		if r_dest.is_empty() or r_dest == current_port_id or find_port(state, r_dest).is_empty():
			continue
		var r_pos: Vector2 = owner_position(state, other)
		var dist: float = my_pos.distance_to(r_pos)
		var hunt_bonus: float = 350.0 if not str(r_ord.get("targetOwnerId", "")).is_empty() else 0.0
		var score: float = 2200.0 - dist + hunt_bonus
		if score > best_raider_score:
			best_raider_score = score
			best_raider = other
			best_raider_port = r_dest

	var best_trader: Dictionary = {}
	var best_trader_port: String = ""
	var best_trader_score: float = -INF
	for other_var in owners:
		if not (other_var is Dictionary):
			continue
		var other: Dictionary = other_var
		if is_story_owner(other) or not bool(other.get("active", false)):
			continue
		if str(other.get("kind", "")) != "trader" or living_boats(other).is_empty():
			continue
		var t_patrol: Dictionary = find_patrol(state, str(other.get("id", "")))
		var t_ord: Dictionary = other.get("order", {}) if other.get("order") is Dictionary else {}
		var t_dest: String = str(t_ord.get("destination", t_patrol.get("to", "")))
		if t_dest.is_empty() or t_dest == current_port_id:
			var t_from: String = str(t_patrol.get("from", other.get("homePort", "")))
			t_dest = t_from if t_from != current_port_id else t_dest
		if t_dest.is_empty() or t_dest == current_port_id or find_port(state, t_dest).is_empty():
			continue
		var cargo_val: float = maxf(0.0, float(other.get("tradeCargo", 0.0))) * maxf(10.0, float(Goods.cost(str(other.get("tradeGood", "timber")))))
		var dist: float = my_pos.distance_to(owner_position(state, other))
		var score: float = 1600.0 + cargo_val * 0.25 - dist * 0.8
		if score > best_trader_score:
			best_trader_score = score
			best_trader = other
			best_trader_port = t_dest

	if not best_raider.is_empty() and (best_raider_score >= best_trader_score or best_trader.is_empty()):
		var p_name: String = str(find_port(state, best_raider_port).get("name", best_raider_port))
		return {
			"purpose": "intercept",
			"destination": best_raider_port,
			"targetOwnerId": str(best_raider.get("id", "")),
			"reason": "Intercepting %s (%s) near %s." % [str(best_raider.get("name", "raiders")), str(best_raider.get("id", "")), p_name]
		}
	if not best_trader.is_empty():
		var p_name: String = str(find_port(state, best_trader_port).get("name", best_trader_port))
		return {
			"purpose": "escort",
			"destination": best_trader_port,
			"targetOwnerId": str(best_trader.get("id", "")),
			"reason": "Escorting convoy %s carrying %.0f %s toward %s." % [str(best_trader.get("name", "convoy")), maxf(0.0, float(best_trader.get("tradeCargo", 0.0))), str(best_trader.get("tradeGood", "cargo")), p_name]
		}

	var fallback_dest: String = ""
	var route: Array = owner.get("route", []) if owner.get("route") is Array else []
	for r_id_var in route:
		var r_id: String = str(r_id_var)
		if r_id != current_port_id and not find_port(state, r_id).is_empty():
			fallback_dest = r_id
			break
	if fallback_dest.is_empty():
		var ports: Array = state.get("ports", []) if state.get("ports") is Array else []
		for p_var in ports:
			if p_var is Dictionary:
				var p: Dictionary = p_var
				var pid: String = str(p.get("id", ""))
				if pid != current_port_id and str(p.get("faction", "")) != "raiders":
					fallback_dest = pid
					break
	if fallback_dest.is_empty():
		fallback_dest = home_id
	var dest_name: String = str(find_port(state, fallback_dest).get("name", fallback_dest))
	return {
		"purpose": "patrol",
		"destination": fallback_dest,
		"targetOwnerId": "",
		"reason": "Patrolling sea lane between %s and %s." % [str(origin_port.get("name", home_id)), dest_name]
	}


static func select_raider_order(state: Dictionary, owner: Dictionary, current_port_id: String) -> Dictionary:
	var home_id: String = str(owner.get("homePort", ""))
	var my_pos: Vector2 = owner_position(state, owner)
	var best_convoy: Dictionary = {}
	var best_dest: String = ""
	var best_score: float = -INF
	var owners: Array = state.get("fleetOwners", []) if state.get("fleetOwners") is Array else []
	for other_var in owners:
		if not (other_var is Dictionary):
			continue
		var other: Dictionary = other_var
		if is_story_owner(other) or not bool(other.get("active", false)):
			continue
		if state.has("relationships") and Factions.relation(state,str(owner.get("faction","")),str(other.get("faction","")))>-20:continue
		if str(other.get("kind", "")) != "trader" or living_boats(other).is_empty():
			continue
		var t_patrol: Dictionary = find_patrol(state, str(other.get("id", "")))
		var t_ord: Dictionary = other.get("order", {}) if other.get("order") is Dictionary else {}
		var t_dest: String = str(t_ord.get("destination", t_patrol.get("to", "")))
		if t_dest.is_empty() or t_dest == current_port_id:
			var t_from: String = str(t_patrol.get("from", other.get("homePort", "")))
			t_dest = t_from if t_from != current_port_id else t_dest
		if t_dest.is_empty() or t_dest == current_port_id or find_port(state, t_dest).is_empty():
			continue
		var loaded_qty: float = maxf(0.0, float(other.get("tradeCargo", 0.0)))
		var good_val: float = maxf(10.0, float(Goods.cost(str(other.get("tradeGood", "timber")))))
		var load_bonus: float = 900.0 if loaded_qty > 0.0 else 100.0
		var prize_score: float = loaded_qty * good_val + float(other.get("coins", 0)) * 0.15 + load_bonus
		var dist: float = my_pos.distance_to(owner_position(state, other))
		var score: float = prize_score - dist * 0.55
		if score > best_score:
			best_score = score
			best_convoy = other
			best_dest = t_dest

	if not best_convoy.is_empty() and not best_dest.is_empty():
		var p_name: String = str(find_port(state, best_dest).get("name", best_dest))
		return {
			"purpose": "raid",
			"destination": best_dest,
			"targetOwnerId": str(best_convoy.get("id", "")),
			"reason": "Seeking loaded convoy %s (%.0f %s) bound for %s." % [str(best_convoy.get("name", "convoy")), maxf(0.0, float(best_convoy.get("tradeCargo", 0.0))), str(best_convoy.get("tradeGood", "cargo")), p_name]
		}

	var raid_port: String = ""
	var route: Array = owner.get("route", []) if owner.get("route") is Array else []
	for r_id_var in route:
		var r_id: String = str(r_id_var)
		if r_id != current_port_id and not find_port(state, r_id).is_empty():
			raid_port = r_id
			break
	if raid_port.is_empty():
		var ports: Array = state.get("ports", []) if state.get("ports") is Array else []
		for p_var in ports:
			if p_var is Dictionary:
				var p: Dictionary = p_var
				var pid: String = str(p.get("id", ""))
				if pid != current_port_id and str(p.get("faction", "")) != "raiders":
					raid_port = pid
					break
	if raid_port.is_empty():
		raid_port = home_id
	var rp_name: String = str(find_port(state, raid_port).get("name", raid_port))
	return {
		"purpose": "raid",
		"destination": raid_port,
		"targetOwnerId": "",
		"reason": "Raiding merchant approaches off %s." % rp_name
	}


static func assign_post_dock_order(state: Dictionary, owner: Dictionary, dock_port: Dictionary = {}) -> String:
	Fleets.normalize_owner(owner)
	var home_id: String = str(owner.get("homePort", ""))
	var ports: Array = state.get("ports", []) if state.get("ports") is Array else []
	if home_id.is_empty() and not ports.is_empty() and ports[0] is Dictionary:
		var first_p: Dictionary = ports[0]
		home_id = str(first_p.get("id", ""))
	var dock_id: String = str(dock_port.get("id", owner.get("atPort", "")))
	var port_ref: Dictionary = dock_port if not dock_port.is_empty() else find_port(state, dock_id)
	if not port_ref.is_empty():
		dock_id = str(port_ref.get("id", ""))
		owner["atPort"] = dock_id
		RegionalOrders.arrival(state,owner,port_ref)

	if owner.get("playerCompany",false):
		var company_api: Script=load("res://scripts/company_ops.gd")
		var recovery: String=needs_home_recovery(owner,fleet_reserves(owner),fleet_performance(owner))
		var company_plan: Dictionary=company_api.plan(state,owner,port_ref,recovery)
		var next: String=str(company_plan.get("destination",home_id))
		build_order(state,owner,"resupply" if not recovery.is_empty() else "trade",next,str(company_plan.get("reason","Chartered route.")))
		return next

	if is_story_owner(owner):
		var story_route: Array = owner.get("route", []) if owner.get("route") is Array else []
		var story_dest: String = str(story_route[story_route.size() - 1]) if not story_route.is_empty() else home_id
		var sp_name: String = str(find_port(state, story_dest).get("name", story_dest))
		build_order(state, owner, "blockade", story_dest, "Maintaining story blockade station at %s." % sp_name)
		return story_dest

	var res: Dictionary = fleet_reserves(owner)
	var perf: Dictionary = fleet_performance(owner)
	var recovery_reason: String = needs_home_recovery(owner, res, perf)

	if not recovery_reason.is_empty():
		var living_cnt: int = int(res.get("boats", 0))
		var target_cnt: int = int(res.get("targetBoats", 1))
		if dock_id != home_id and not find_port(state, home_id).is_empty():
			var hp_bad: bool = float(res.get("hpRatio", 1.0)) < 0.65 or float(res.get("minEngine", 1.0)) < 0.68
			var purpose_home: String = "replace" if living_cnt < target_cnt else ("repair" if hp_bad else "resupply")
			build_order(state, owner, purpose_home, home_id, recovery_reason)
			if not dock_id.is_empty():
				owner["route"] = [dock_id, home_id]
			return home_id
		var cur_purpose: String="replace" if living_cnt<target_cnt else "repair"
		build_order(state,owner,cur_purpose,home_id,recovery_reason)
		owner["route"]=[home_id,home_id]
		return home_id

	var kind: String = str(owner.get("kind", "patrol"))
	var plan: Dictionary = {}
	if kind == "trader":
		if dock_id == home_id and not port_ref.is_empty() and float(owner.get("tradeCargo", 0.0)) <= 0.0:
			owner["tradeGood"] = pick_export_good(port_ref, str(owner.get("tradeGood", "timber")))
			Fleets.dock(owner, port_ref)
		plan = select_trader_order(state, owner, dock_id)
	elif kind == "raider":
		plan = select_raider_order(state, owner, dock_id)
	else:
		plan = RegionalOrders.plan(state,owner,dock_id)
		if plan.is_empty():plan = select_patrol_order(state, owner, dock_id)

	var next_port: String = str(plan.get("destination", home_id))
	if find_port(state, next_port).is_empty():
		next_port = home_id
	build_order(
		state,
		owner,
		str(plan.get("purpose", kind)),
		next_port,
		str(plan.get("reason", "")),
		str(plan.get("targetOwnerId", ""))
	)
	var start_port: String = dock_id if not dock_id.is_empty() else home_id
	if not start_port.is_empty() and not next_port.is_empty():
		owner["route"] = [start_port, next_port] if start_port != next_port else [home_id, next_port]
	return next_port
