extends RefCounted
const Locality064=preload("res://scripts/expedition.gd")
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
const OBSERVATION_RADIUS: float = 900.0
const PLAYER_OBSERVATION_RADIUS: float = 1800.0
const SIGHTING_MEMORY_DAYS: float = 0.25
const SIGHTING_HISTORY_DAYS: float = 1.0
const MAX_SIGHTINGS: int = 24

## Enrolled physical fleets are owned by the shared travel adapter on every chart.
## Its old patrol is a dormant projection, never a second local participant.
static func enrolled066(state: Dictionary, owner_id: String) -> bool:
	if owner_id.is_empty():return false
	return str(state.get("ocean066",{}).get("contact",{}).get("ownerId",""))==owner_id or str(state.get("shipping068",{}).get("model",{}).get("route",{}).get("ownerId",""))==owner_id


static func home_ports064(state: Dictionary) -> Array:
	return state.get("ports",[]).filter(func(p):return p is Dictionary and str(p.get("regionId","shatter_coast"))=="shatter_coast")


static func home_port064(state: Dictionary, port_id: String) -> Dictionary:
	var port: Dictionary = find_port(state,port_id)
	return port if str(port.get("regionId","shatter_coast"))=="shatter_coast" else {}


static func canonical_location068(state: Dictionary, owner_id: String) -> Dictionary:
	var contact: Dictionary = state.get("ocean066",{}).get("contact",{})
	if contact.get("ownerId")!=owner_id:contact=state.get("shipping068",{}).get("model",{}).get("route",{})
	if contact.get("ownerId")==owner_id:
		return {} if contact.get("phase")=="lost" else contact.get("location",{}).duplicate(true)
	var patrol: Dictionary = find_patrol(state,owner_id)
	if patrol.is_empty() or not patrol.get("active",false) or not patrol.has("x") or not patrol.has("y"):return {}
	return {"world064":{"schema":1,"layer":"home","regionId":"shatter_coast"},"position":{"x":float(patrol.x),"y":float(patrol.y)},"heading":0.0,"path":[],"destination":""}


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
	if enrolled066(state,str(owner.get("id",""))):return Vector2(INF,INF)
	var patrol: Dictionary = find_patrol(state, str(owner.get("id", "")))
	if not patrol.is_empty() and patrol.has("x") and patrol.has("y"):
		return Vector2(float(patrol.get("x", 0.0)), float(patrol.get("y", 0.0)))
	var at_id: String = str(owner.get("atPort", ""))
	if at_id.is_empty():
		at_id = str(owner.get("homePort", ""))
	var p: Dictionary = home_port064(state, at_id)
	if p.is_empty():return Vector2(INF,INF)
	return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))


static func target_destination(state: Dictionary, owner: Dictionary) -> String:
	if enrolled066(state,str(owner.get("id",""))):return ""
	# Raw chart lookup: callers must establish local observation first.
	if owner.is_empty() or is_story_owner(owner) or not bool(owner.get("active", false)) or living_boats(owner).is_empty():
		return ""
	var patrol: Dictionary = find_patrol(state, str(owner.get("id", "")))
	if patrol.is_empty() or not bool(patrol.get("active", false)):
		return ""
	var dest: String = str(patrol.get("to", ""))
	if home_port064(state, dest).is_empty():
		var order: Dictionary = owner.get("order", {}) if owner.get("order") is Dictionary else {}
		dest = str(order.get("destination", ""))
	return dest if not home_port064(state, dest).is_empty() else ""


static func sightings(state: Dictionary, observer_id: String = "player") -> Array:
	if enrolled066(state,observer_id):return []
	var now: float = float(state.get("day", state.get("econDay", 1)))
	var records: Array = state.get("navalAi", {}).get("sightingsByObserver", {}).get(observer_id, [])
	var result: Array = []
	for record in records:
		if not (record is Dictionary):continue
		var age: float = maxf(0.0, now - float(record.get("day", now)))
		if age > SIGHTING_HISTORY_DAYS:continue
		var copy: Dictionary = record.duplicate(true)
		copy.ageDays = age
		copy.expired = now >= float(copy.get("expiresDay", 0.0))
		copy.current = (observer_id!="player" or Locality064.home_local064(state)) and bool(copy.get("current", false)) and not copy.expired and age <= 1.5 / 45.0
		result.append(copy)
	return result.slice(0, MAX_SIGHTINGS)


static func observation_reason(purpose: String) -> String:
	match purpose:
		"withdraw":return "Withdrawing to harbor after damage, depleted stores or local danger."
		"repair":return "Seeking paid hull, machinery or crew recovery at harbor."
		"replace":return "Returning for funded replacement of lost hulls."
		"resupply":return "Returning for paid operating stores or a commercial load."
		"raid":return "Raiding merchant approaches using local sightings."
		"intercept":return "Intercepting a locally sighted hostile fleet."
		"escort":return "Screening a locally sighted loaded convoy."
		"deliver", "trade":return "Carrying a commercial shipment along its observed route."
	return "Watching the coastal sea lanes."


## Sample only while a contact is actually observed. This is an estimate from
## its visible commercial load, never access to a distant purse or live hold.
static func observed_manifest075(owner: Dictionary) -> Dictionary:
	var good: String = str(owner.get("tradeGood", ""))
	var quantity: float = maxf(0.0, minf(float(owner.get("tradeCargo", 0.0)), float(owner.get("cargo", {}).get(good, 0.0))))
	return {"cargoGood":good,"cargoQuantity":quantity,"cargoValue":quantity * Goods.cost(good)}


static func observe(state: Dictionary, observer_id: String = "player") -> Array:
	if enrolled066(state,observer_id):return []
	if observer_id=="player" and not Locality064.home_local064(state):return sightings(state,observer_id)
	var observer: Dictionary = find_owner(state, observer_id)
	if observer_id != "player" and (observer.is_empty() or is_story_owner(observer) or not bool(observer.get("active", false))):return []
	var position: Dictionary = state.get("position", {}) if observer_id == "player" else find_patrol(state, observer_id)
	if not position.has("x") or not position.has("y"):return []
	if not (state.get("navalAi") is Dictionary):state.navalAi = {}
	if not (state.navalAi.get("sightingsByObserver") is Dictionary):state.navalAi.sightingsByObserver = {}
	var now: float = float(state.get("day", state.get("econDay", 1)))
	var radius: float = PLAYER_OBSERVATION_RADIUS if observer_id == "player" else OBSERVATION_RADIUS
	var origin: Vector2 = Vector2(float(position.x), float(position.y))
	var remembered: Array = sightings(state, observer_id)
	for record in remembered:record.current = false
	# Scan cheap chart coordinates first. No distant owner, cargo or destination
	# is queried; selectors subsequently inspect only these bounded snapshots.
	for patrol in state.get("patrols", []):
		var id: String = str(patrol.get("id", ""))
		var enrolled: bool=enrolled066(state,id)
		if id == observer_id or id.begins_with("story-") or (not enrolled and bool(patrol.get("hidden", false))):continue
		var location: Dictionary=canonical_location068(state,id) if enrolled else {}
		if enrolled and location.get("world064",{}).get("layer")!="home":continue
		var position_record: Dictionary=location.position if enrolled else patrol
		var point: Vector2 = Vector2(float(position_record.get("x", 0.0)), float(position_record.get("y", 0.0)))
		if origin.distance_to(point) > radius:continue
		var other: Dictionary = find_owner(state, id)
		var destination: String = str(other.get("homePort","")) if enrolled and other.get("active",false) and not living_boats(other).is_empty() else target_destination(state, other)
		if home_port064(state,destination).is_empty():destination=""
		# A locally observed inactive/empty contact ends pursuit.
		remembered = remembered.filter(func(r):return str(r.get("ownerId", "")) != id)
		if destination.is_empty():continue
		var cargo: Dictionary = other.get("cargo", {})
		var load: float = minf(float(other.get("tradeCargo", 0.0)), float(cargo.get(str(other.get("tradeGood", "")), 0.0)))
		var purpose: String = str(other.get("purpose", "patrol"))
		var record: Dictionary = {"ownerId": id, "name": str(other.get("name", id)), "faction": str(other.get("faction", "")), "kind": str(other.get("kind", "")), "x": point.x, "y": point.y, "day": now, "expiresDay": now + SIGHTING_MEMORY_DAYS, "destination": destination, "purpose": purpose, "reason": str(other.get("reason", observation_reason(purpose))), "loaded": load > 0.0, "threat": float(fleet_performance(other).get("firepower", 0.0)), "current": true}
		record.merge(observed_manifest075(other))
		remembered.push_front(record)
	if remembered.size() > MAX_SIGHTINGS:remembered.resize(MAX_SIGHTINGS)
	state.navalAi.sightingsByObserver[observer_id] = remembered
	return sightings(state, observer_id)


static func target_sighting(state: Dictionary, observer_id: String, target_id: String) -> Dictionary:
	for record in sightings(state, observer_id):
		if str(record.get("ownerId", "")) == target_id and not bool(record.get("expired", true)):return record
	return {}


static func sighting_hostile(state: Dictionary, owner: Dictionary, record: Dictionary) -> bool:
	var a: String = str(owner.get("faction", ""))
	var b: String = str(record.get("faction", ""))
	if a == b:return false
	return Factions.relation(state, a, b) <= -20 if state.get("relationships") is Dictionary else (a == "raiders") != (b == "raiders")


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
		if float(b.get("crew", 0.0)) - float(b.get("wounded", 0.0)) < float(b.get("crewMin", 1.0)):
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
		if float(b.get("crew", 0.0)) - float(b.get("wounded", 0.0)) < float(b.get("crewMin", 1.0)):
			return "%s is under minimum able crew; returning to home harbor." % b_name
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


static func build_order(state: Dictionary, owner: Dictionary, purpose: String = "", destination: String = "", reason: String = "", target_owner_id: String = "", keep_destination: bool = false) -> Dictionary:
	var route075: Dictionary=state.get("shipping068",{}).get("model",{}).get("route",{})
	var generic: bool=route075.get("ownerId")==owner.get("id") and route075.has("corridor075")
	if enrolled066(state,str(owner.get("id",""))) and not generic:return owner.get("order",{})
	# Enrolled targets can be followed only through an actual dated HOME
	# observation below; their dormant patrol coordinates remain excluded.
	var res: Dictionary = fleet_reserves(owner)
	var perf: Dictionary = fleet_performance(owner)
	var ports: Array = home_ports064(state)
	var fallback_port: String = str(owner.get("homePort", ""))
	if fallback_port.is_empty() and not ports.is_empty() and ports[0] is Dictionary:
		var first_port: Dictionary = ports[0]
		fallback_port = str(first_port.get("id", ""))
	var dest: String = destination
	var contact: Dictionary = {}
	if purpose in ["raid", "intercept", "escort"] and not target_owner_id.is_empty() and not keep_destination and not is_story_owner(owner) and not bool(owner.get("playerCompany", false)):
		contact = target_sighting(state, str(owner.get("id", "")), target_owner_id)
		if contact.is_empty():
			target_owner_id = ""
			var kind: String = str(owner.get("kind", "patrol"))
			purpose = "raid" if kind == "raider" else ("deliver" if kind == "trader" else "patrol")
			reason = "%s sea lanes; contact expired or ended locally, pursuit stopped." % ("Raiding merchant" if kind == "raider" else ("Sailing trade" if kind == "trader" else "Patrolling"))
		else:
			dest = str(contact.get("destination", dest))
	var valid_destination: bool=not home_port064(state,dest).is_empty()
	if generic:valid_destination=dest in [route075.corridor075.homeId,route075.corridor075.originId,route075.corridor075.remoteId] and not find_port(state,dest).is_empty()
	if dest.is_empty() or not valid_destination:
		var route: Array = owner.get("route", []) if owner.get("route") is Array else []
		if route.size() >= 2 and not home_port064(state, str(route[1])).is_empty():
			dest = str(route[1])
		elif not route.is_empty() and not home_port064(state, str(route[0])).is_empty():
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
		"day": float(state.get("day", state.get("econDay", 1))),
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
	if not contact.is_empty():
		ord["targetSighting"] = contact.duplicate(true)
		ord["interceptPoint"] = {"x": float(contact.x), "y": float(contact.y)}
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
	var ports: Array = home_ports064(state)
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
	var contacts: Array = observe(state, str(owner.get("id", "")))
	var power: float = maxf(1.0, float(fleet_performance(owner).get("firepower", 0.0)))
	var best_raider: Dictionary = {}
	var best_raider_port: String = ""
	var best_raider_score: float = -INF
	for other in contacts:
		if bool(other.get("expired", true)) or not sighting_hostile(state, owner, other):continue
		var supply: bool = str(other.get("kind", "")) == "trader" and bool(other.get("loaded", false))
		if str(other.get("kind", "")) != "raider" and not supply:continue
		var r_dest: String = str(other.get("destination", ""))
		if r_dest.is_empty() or home_port064(state, r_dest).is_empty():continue
		var r_pos: Vector2 = Vector2(float(other.x), float(other.y))
		var dist: float = my_pos.distance_to(r_pos)
		if float(other.get("threat", 0.0)) > power * 1.6:continue
		var score: float = 2200.0 - dist - float(other.get("ageDays", 0.0)) * 1500.0
		if supply:score += log(1.0 + maxf(0.0, float(other.get("cargoValue", 0.0)))) * 80.0 - 600.0
		if score > best_raider_score:
			best_raider_score = score
			best_raider = other
			best_raider_port = r_dest

	var best_trader: Dictionary = {}
	var best_trader_port: String = ""
	var best_trader_score: float = -INF
	for other in contacts:
		if bool(other.get("expired", true)) or sighting_hostile(state, owner, other):continue
		if str(other.get("kind", "")) != "trader" or not bool(other.get("loaded", false)):continue
		var t_dest: String = str(other.get("destination", ""))
		if t_dest.is_empty() or home_port064(state, t_dest).is_empty():continue
		var dist: float = my_pos.distance_to(Vector2(float(other.x), float(other.y)))
		var score: float = 1600.0 - dist * 0.8 - float(other.get("ageDays", 0.0)) * 1500.0
		if score > best_trader_score:
			best_trader_score = score
			best_trader = other
			best_trader_port = t_dest

	if not best_raider.is_empty() and (best_raider_score >= best_trader_score or best_trader.is_empty()):
		var p_name: String = str(find_port(state, best_raider_port).get("name", best_raider_port))
		return {
			"purpose": "intercept",
			"destination": best_raider_port,
			"targetOwnerId": str(best_raider.get("ownerId", "")),
			"reason": "Intercepting %s%s near %s; local sighting day %.2f%s." % [str(best_raider.get("name", "hostile fleet")), " carrying hostile supplies" if str(best_raider.get("kind", "")) == "trader" else "", p_name, float(best_raider.day), " (last known; contact lost)" if not best_raider.current else ""]
		}
	if not best_trader.is_empty():
		var p_name: String = str(find_port(state, best_trader_port).get("name", best_trader_port))
		return {
			"purpose": "escort",
			"destination": best_trader_port,
			"targetOwnerId": str(best_trader.get("ownerId", "")),
			"reason": "Escorting loaded convoy %s toward %s; local sighting day %.2f%s." % [str(best_trader.get("name", "convoy")), p_name, float(best_trader.day), " (last known; contact lost)" if not best_trader.current else ""]
		}

	var fallback_dest: String = ""
	var route: Array = owner.get("route", []) if owner.get("route") is Array else []
	for r_id_var in route:
		var r_id: String = str(r_id_var)
		if r_id != current_port_id and not home_port064(state, r_id).is_empty():
			fallback_dest = r_id
			break
	if fallback_dest.is_empty():
		var ports: Array = home_ports064(state)
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
	var power: float = maxf(1.0, float(fleet_performance(owner).get("firepower", 0.0)))
	for other in observe(state, str(owner.get("id", ""))):
		if bool(other.get("expired", true)) or not sighting_hostile(state, owner, other):continue
		if str(other.get("kind", "")) != "trader" or not bool(other.get("loaded", false)):continue
		var t_dest: String = str(other.get("destination", ""))
		if t_dest.is_empty() or home_port064(state, t_dest).is_empty():continue
		var threat: float = float(other.get("threat", 0.0))
		if threat > power * 1.3:continue
		var dist: float = my_pos.distance_to(Vector2(float(other.x), float(other.y)))
		var value: float = maxf(0.0, float(other.get("cargoValue", 0.0)))
		var score: float = 900.0 + log(1.0 + value) * 180.0 - dist * 0.55 - threat * 0.5 - float(other.get("ageDays", 0.0)) * 1500.0
		if score > best_score:
			best_score = score
			best_convoy = other
			best_dest = t_dest

	if not best_convoy.is_empty() and not best_dest.is_empty():
		var p_name: String = str(find_port(state, best_dest).get("name", best_dest))
		return {
			"purpose": "raid",
			"destination": best_dest,
			"targetOwnerId": str(best_convoy.get("ownerId", "")),
			"reason": "Seeking loaded convoy %s bound for %s (observed %.1f %s, estimated %.0f coins); local sighting day %.2f%s." % [str(best_convoy.get("name", "convoy")), p_name, float(best_convoy.get("cargoQuantity", 0.0)), str(best_convoy.get("cargoGood", "cargo")), float(best_convoy.get("cargoValue", 0.0)), float(best_convoy.day), " (last known; contact lost)" if not best_convoy.current else ""]
		}

	var raid_port: String = ""
	var route: Array = owner.get("route", []) if owner.get("route") is Array else []
	for r_id_var in route:
		var r_id: String = str(r_id_var)
		if r_id != current_port_id and not home_port064(state, r_id).is_empty():
			raid_port = r_id
			break
	if raid_port.is_empty():
		var ports: Array = home_ports064(state)
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


static func apply_regional_plan(state: Dictionary, owner: Dictionary, plan: Dictionary) -> Dictionary:
	if plan.is_empty() or is_story_owner(owner) or owner.get("playerCompany",false):return {}
	var applied: Dictionary=plan.duplicate(true)
	var res: Dictionary=fleet_reserves(owner)
	var recovery: String=needs_home_recovery(owner,res,fleet_performance(owner))
	var returning: bool=str(owner.get("atPort","")).is_empty() and str(owner.get("purpose","")) in ["withdraw","repair","replace","resupply"]
	if not recovery.is_empty() or returning:
		applied.ready=false
		applied.purpose=str(owner.purpose) if returning else ("replace" if int(res.boats)<int(res.targetBoats) else ("repair" if float(res.hpRatio)<0.65 or float(res.minEngine)<0.68 else "resupply"))
		applied.destination=str(owner.get("destination",owner.homePort)) if returning else str(owner.homePort)
		applied.targetOwnerId=""
		applied.reason=recovery if not recovery.is_empty() else str(owner.get("reason","Returning for paid recovery before the corridor watch."))
		applied.hold=str(owner.get("atPort","")).is_empty() and living_boats(owner).any(func(b):return float(b.get("fuel",0))<=0.0)
		applied.erase("interceptPoint")
	var order: Dictionary=owner.get("order",{})
	if str(order.get("purpose",""))!=str(applied.purpose) or str(order.get("destination",""))!=str(applied.destination) or str(order.get("targetOwnerId",""))!=str(applied.get("targetOwnerId","")):
		build_order(state,owner,str(applied.purpose),str(applied.destination),str(applied.reason),str(applied.get("targetOwnerId","")),true)
	else:
		order.reason=str(applied.reason);owner.reason=str(applied.reason)
	return applied


static func refresh_at_sea(state: Dictionary, owner: Dictionary) -> Dictionary:
	var current: Dictionary = owner.get("order", {})
	if enrolled066(state,str(owner.get("id",""))):return current
	if is_story_owner(owner) or bool(owner.get("playerCompany", false)) or not bool(owner.get("active", false)):return current
	# Authored corridor orders already have a local live adapter and route quote.
	if not RegionalOrders.operation(state, owner).is_empty():return current
	var purpose: String = str(current.get("purpose", ""))
	if purpose in ["withdraw", "repair", "replace", "resupply"]:return current
	var reserves: Dictionary = fleet_reserves(owner)
	var performance: Dictionary = fleet_performance(owner)
	var recovery: String = needs_home_recovery(owner, reserves, performance)
	if recovery.is_empty() and int(reserves.get("crew", 0)) > 0:
		if float(reserves.get("foodDays", 0.0)) < 0.5:recovery = "Crew food reserve below half a day; returning home for paid provisions."
		elif float(reserves.get("wageDays", 0.0)) < 0.5:recovery = "Available purse cannot cover half a day's payroll; returning home before further orders."
	if not recovery.is_empty():
		return build_order(state, owner, "replace" if int(reserves.boats) < int(reserves.targetBoats) else "withdraw", str(owner.get("homePort", "")), recovery)
	var plan: Dictionary = {}
	var kind: String = str(owner.get("kind", "patrol"))
	if kind == "raider":plan = select_raider_order(state, owner, str(owner.get("atPort", "")))
	elif kind == "patrol":plan = select_patrol_order(state, owner, str(owner.get("atPort", "")))
	else:
		# A loaded merchant preserves its commercial leg unless local danger
		# outweighs its actual armed strength. No remote manifest/purse queries.
		var power: float = maxf(1.0, float(performance.get("firepower", 0.0)))
		var pos: Vector2 = owner_position(state, owner)
		for contact in observe(state, str(owner.get("id", ""))):
			if not bool(contact.get("current", false)) or not sighting_hostile(state, owner, contact):continue
			if pos.distance_to(Vector2(float(contact.x), float(contact.y))) > 450.0:continue
			if float(contact.get("threat", 0.0)) > power * 1.3:
				return build_order(state, owner, "withdraw", str(owner.get("homePort", "")), "Withdrawing from locally sighted %s (day %.2f); hostile strength exceeds this convoy's escort." % [str(contact.name), float(contact.day)])
		return current
	owner["lastNavalRetargetDay"] = int(state.get("econDay", 1))
	var target: String = str(plan.get("targetOwnerId", ""))
	# Continue a useful sea leg when there is no local target; do not cycle
	# through fallback ports at every decision slice.
	if target.is_empty():
		plan.destination = str(current.get("destination", owner.get("homePort", "")))
		if not str(current.get("targetOwnerId", "")).is_empty():plan.reason = "Contact expired, ended locally or no longer hostile/viable; resuming the existing sea lane."
	var changed: bool = str(current.get("purpose", "")) != str(plan.get("purpose", "")) or str(current.get("destination", "")) != str(plan.get("destination", "")) or str(current.get("targetOwnerId", "")) != target
	if changed:return build_order(state, owner, str(plan.purpose), str(plan.destination), str(plan.reason), target)
	if not target.is_empty():
		var contact: Dictionary = target_sighting(state, str(owner.get("id", "")), target)
		if not contact.is_empty():
			current.targetSighting = contact.duplicate(true)
			current.interceptPoint = {"x": float(contact.x), "y": float(contact.y)}
			current.reason = str(plan.reason);owner.reason = str(plan.reason)
	return current


static func assign_post_dock_order(state: Dictionary, owner: Dictionary, dock_port: Dictionary = {}, context: Dictionary = {}) -> String:
	if enrolled066(state,str(owner.get("id",""))):return str(owner.get("destination",""))
	Fleets.normalize_owner(owner)
	var home_id: String = str(owner.get("homePort", ""))
	var ports: Array = home_ports064(state)
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
		plan = RegionalOrders.plan(state,owner,dock_id,context)
		if plan.is_empty():plan = select_patrol_order(state, owner, dock_id)

	var next_port: String = str(plan.get("destination", home_id))
	if home_port064(state, next_port).is_empty():
		next_port = home_id
	build_order(
		state,
		owner,
		str(plan.get("purpose", kind)),
		next_port,
		str(plan.get("reason", "")),
		str(plan.get("targetOwnerId", "")),
		not RegionalOrders.operation(state,owner).is_empty()
	)
	var start_port: String = dock_id if not dock_id.is_empty() else home_id
	if not start_port.is_empty() and not next_port.is_empty():
		owner["route"] = [start_port, next_port] if start_port != next_port else [home_id, next_port]
	return next_port
