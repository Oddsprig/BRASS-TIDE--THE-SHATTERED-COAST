extends RefCounted
## Autonomous NPC fleet coordinator (v0.013): thin entry point over NavalOrders, NavalCombat, and NavalReplacements.
## Pure-data module: no global RNG, no scene/UI access, strict bronze coin and workforce conservation.

const Fleets = preload("res://scripts/fleet_economy.gd")
const NavalOrders = preload("res://scripts/naval_orders.gd")
const NavalCombat = preload("res://scripts/naval_combat.gd")
const NavalReplacements = preload("res://scripts/naval_replacements.gd")
const World068 = preload("res://scripts/ocean_world064.gd")
const Travel068 = preload("res://scripts/ocean_travel066.gd")

const CELL_SIZE: float = NavalCombat.CELL_SIZE
const ENCOUNTER_RADIUS: float = NavalCombat.ENCOUNTER_RADIUS
const INTERCEPT_RADIUS: float = NavalCombat.INTERCEPT_RADIUS
const MAX_ENCOUNTERS_PER_DAY: int = NavalCombat.MAX_ENCOUNTERS_PER_DAY
const MAX_ORDER_LOG: int = NavalOrders.MAX_ORDER_LOG
const MAX_EVENT_LOG: int = NavalOrders.MAX_EVENT_LOG
const MAX_SLIPS_PER_PORT: int = NavalReplacements.MAX_SLIPS_PER_PORT
const MAX_ORDER_DECISIONS: int = 2


static func observe(state: Dictionary, observer_id: String = "player") -> Array:
	return NavalOrders.observe(state, observer_id)


static func sightings(state: Dictionary, observer_id: String = "player") -> Array:
	return NavalOrders.sightings(state, observer_id)


static func _reconcile_losses(core) -> bool:
	# Runtime dependency: Lifecycle preloads this coordinator. Reuse its single
	# recorder before public replacement entry points can relaunch a wiped fleet.
	if core is Object and core.has_method("port") and core.has_method("hull"):
		var lifecycle_api: Script = load("res://scripts/naval_lifecycle.gd")
		return lifecycle_api.reconcile_losses(core)
	return true # Legacy data-only callers have no campaign wreck recorder.


static func order_slice(state: Dictionary) -> Array:
	var owners: Array = state.get("fleetOwners", [])
	if owners.is_empty() or not (state.get("navalAi") is Dictionary):return []
	var nav_ai: Dictionary = state.navalAi
	var cursor: int = posmod(int(nav_ai.get("orderCursor", 0)), owners.size())
	var visited: int = 0
	var decided: Array = []
	while visited < owners.size() and decided.size() < MAX_ORDER_DECISIONS:
		var owner: Dictionary = owners[cursor]
		cursor = (cursor + 1) % owners.size();visited += 1
		if NavalOrders.enrolled066(state,str(owner.get("id",""))):continue
		if NavalOrders.is_story_owner(owner) or bool(owner.get("playerCompany", false)) or not bool(owner.get("active", false)):continue
		var patrol: Dictionary = NavalOrders.find_patrol(state, str(owner.get("id", "")))
		if patrol.is_empty() or not bool(patrol.get("active", false)) or not str(owner.get("atPort", "")).is_empty():continue
		if not NavalOrders.RegionalOrders.operation(state, owner).is_empty():continue
		NavalOrders.refresh_at_sea(state, owner)
		decided.append(str(owner.get("id", "")))
	nav_ai.orderCursor = cursor
	return decided


static func is_story_owner(owner: Dictionary) -> bool:
	return NavalOrders.is_story_owner(owner)


static func _state_of(core_or_state) -> Dictionary:
	return NavalOrders.state_of(core_or_state)


static func _world_of(core_or_state) -> Dictionary:
	return NavalOrders.world_of(core_or_state)


static func _find_port(state: Dictionary, port_id: String) -> Dictionary:
	return NavalOrders.find_port(state, port_id)


static func _find_owner(state: Dictionary, owner_id: String) -> Dictionary:
	return NavalOrders.find_owner(state, owner_id)


static func _find_patrol(state: Dictionary, patrol_id: String) -> Dictionary:
	return NavalOrders.find_patrol(state, patrol_id)


static func _living_boats(owner: Dictionary) -> Array:
	return NavalOrders.living_boats(owner)


static func _quote_at_port(h: Dictionary, port: Dictionary) -> Dictionary:
	return NavalReplacements.quote_at_port(h, port)


static func fleet_reserves(owner: Dictionary) -> Dictionary:
	return NavalOrders.fleet_reserves(owner)


static func fleet_performance(owner: Dictionary) -> Dictionary:
	return NavalOrders.fleet_performance(owner)


static func build_order(state: Dictionary, owner: Dictionary, purpose: String = "", destination: String = "", reason: String = "", target_owner_id: String = "") -> Dictionary:
	return NavalOrders.build_order(state, owner, purpose, destination, reason, target_owner_id)


static func spatial_index(state: Dictionary, cell_size: float = CELL_SIZE) -> Dictionary:
	return NavalCombat.spatial_index(state, cell_size)


static func nearby_hostile_pairs(state: Dictionary, radius: float = ENCOUNTER_RADIUS) -> Array:
	return NavalCombat.nearby_hostile_pairs(state, radius)


static func resolve_encounter(state: Dictionary, owner_a: Dictionary, owner_b: Dictionary, patrol_a: Dictionary = {}, patrol_b: Dictionary = {}, seed_val: int = 1) -> Dictionary:
	if NavalOrders.enrolled066(state,str(owner_a.get("id",""))) or NavalOrders.enrolled066(state,str(owner_b.get("id",""))):return {"ok":false,"reason":"ocean_owner_excluded"}
	var nav_ai: Dictionary = ensure(state)
	if nav_ai.is_empty():
		return {"ok": false, "reason": "no_campaign"}
	var busy: Dictionary = nav_ai["encounterOwners"]
	var id_a: String = str(owner_a.get("id", ""))
	var id_b: String = str(owner_b.get("id", ""))
	if int(nav_ai.get("encounterCount", 0)) >= MAX_ENCOUNTERS_PER_DAY:
		return {"ok": false, "reason": "daily_encounter_limit"}
	if busy.has(id_a) or busy.has(id_b):
		return {"ok": false, "reason": "owner_already_engaged"}
	if not NavalCombat.are_hostile(state, owner_a, patrol_a, owner_b, patrol_b):
		return {"ok": false, "reason": "not_hostile"}
	var outcome: Dictionary = NavalCombat.resolve_encounter(state, owner_a, owner_b, patrol_a, patrol_b, seed_val)
	if bool(outcome.get("ok", false)):
		for side in [[owner_a, patrol_a], [owner_b, patrol_b]]:
			var owner: Dictionary = side[0]
			var patrol: Dictionary = side[1]
			if patrol.is_empty():patrol = NavalOrders.find_patrol(state, str(owner.get("id", "")))
			for boat in owner.get("boats", []):
				if patrol.has("x") and patrol.has("y") and bool(boat.get("sunk", false)) and not bool(boat.get("wreckRecorded", false)) and not boat.has("navalLossPosition"):
					boat.navalLossPosition = {"x": float(patrol.get("x", 0.0)), "y": float(patrol.get("y", 0.0))}
					boat.navalLossDay = float(state.get("day", state.get("econDay", 1)))
		# Refusals spend neither a daily slot nor either owner's participation.
		nav_ai["encounterCount"] = int(nav_ai.get("encounterCount", 0)) + 1
		busy[id_a] = true
		busy[id_b] = true
		var witnessed: bool = false
		var position: Dictionary = state.get("position", {}) if state.get("position") is Dictionary else {}
		if NavalOrders.Locality064.home_local064(state) and position.has("x") and position.has("y"):
			var player_pos: Vector2 = Vector2(float(position.x), float(position.y))
			for patrol in [patrol_a, patrol_b]:
				if patrol.has("x") and patrol.has("y") and player_pos.distance_to(Vector2(float(patrol.x), float(patrol.y))) <= 1800.0:
					witnessed = true # Same chart watch as NavalUI; no distant intel or rewards.
		outcome.event["witnessed"] = witnessed
		NavalCombat.spatial_index(state)
	return outcome


## Same physical salvo/prize resolver as coastal NPCs, reached only with exact
## canonical chart positions. Refusals occur before ensure()/daily bookkeeping.
static func resolve_at068(core, aId: String, bId: String, locationA: Dictionary, locationB: Dictionary) -> Dictionary:
	if not core is Object or not core.has_method("world_location064"):return {"ok":false,"reason":"physical_campaign_required"}
	var state: Dictionary=core.state
	if aId==bId or aId=="player" or bId=="player" or not (NavalOrders.enrolled066(state,aId) or NavalOrders.enrolled066(state,bId)):return {"ok":false,"reason":"invalid_npc_pair"}
	for id in [aId,bId]:
		if state.get("fleetOwners",[]).filter(func(o):return o is Dictionary and o.get("id")==id).size()!=1 or state.get("patrols",[]).filter(func(p):return p is Dictionary and p.get("id")==id).size()!=1:return {"ok":false,"reason":"ambiguous_physical_owners"}
	var owner_a: Dictionary=NavalOrders.find_owner(state,aId)
	var owner_b: Dictionary=NavalOrders.find_owner(state,bId)
	if owner_a.is_empty() or owner_b.is_empty() or NavalOrders.is_story_owner(owner_a) or NavalOrders.is_story_owner(owner_b) or owner_a.get("playerCompany",false) or owner_b.get("playerCompany",false):return {"ok":false,"reason":"invalid_physical_owners"}
	if not owner_a.get("active",false) or not owner_b.get("active",false) or NavalOrders.living_boats(owner_a).is_empty() or NavalOrders.living_boats(owner_b).is_empty():return {"ok":false,"reason":"no_living_boats"}
	if not NavalCombat.faction_hostile068(state,owner_a,owner_b):return {"ok":false,"reason":"not_hostile"}
	for side in [[aId,owner_a,locationA],[bId,owner_b,locationB]]:
		var actual: Dictionary=NavalOrders.canonical_location068(state,str(side[0]))
		var claimed: Dictionary=side[2]
		if actual.is_empty() or actual.get("world064")!=claimed.get("world064") or actual.get("position")!=claimed.get("position"):return {"ok":false,"reason":"canonical_location_changed"}
		var clearance: float=10.0
		for boat in side[1].get("boats",[]):
			if not boat.get("sunk",false):clearance=maxf(clearance,float(boat.get("spec",{}).get("size",10.0)))
		if not World068.prepare(claimed,core.ocean_context064,clearance).get("ok",false):return {"ok":false,"reason":"unsafe_actual_location"}
	if not Travel068.same_world(locationA.world064,locationB.world064):return {"ok":false,"reason":"different_charts"}
	var scale: float=10.0 if locationA.world064.layer=="ocean" else 1.0
	if World068._distance(locationA.position,locationB.position)*scale>ENCOUNTER_RADIUS:return {"ok":false,"reason":"outside_physical_range"}
	if not _custody_valid068(state,[owner_a,owner_b]):return {"ok":false,"reason":"ambiguous_physical_custody"}
	# Check the shared budget on a detached ledger before ensure can normalize it.
	var ledger: Dictionary=state.get("navalAi",{}).duplicate(true)
	_encounter_day(state,ledger)
	if int(ledger.get("encounterCount",0))>=MAX_ENCOUNTERS_PER_DAY:return {"ok":false,"reason":"daily_encounter_limit"}
	if ledger.encounterOwners.has(aId) or ledger.encounterOwners.has(bId):return {"ok":false,"reason":"owner_already_engaged"}
	var nav_ai: Dictionary=ensure(state)
	var outcome: Dictionary=NavalCombat._resolve_physical068(state,owner_a,owner_b,NavalOrders.find_patrol(state,aId),NavalOrders.find_patrol(state,bId),int(state.get("seed",1)))
	if not outcome.get("ok",false):return outcome
	nav_ai.encounterCount=int(nav_ai.encounterCount)+1
	nav_ai.encounterOwners[aId]=true;nav_ai.encounterOwners[bId]=true
	var witnessed: bool=false
	if Travel068.same_world(state.get("world064"),locationA.world064):
		witnessed=minf(World068._distance(state.position,locationA.position),World068._distance(state.position,locationB.position))*scale<=1800.0
	outcome.event["witnessed"]=witnessed
	for side in [[owner_a,locationA],[owner_b,locationB]]:
		_record_losses068(core,side[0],side[1])
	NavalCombat.spatial_index(state)
	return outcome


static func _custody_valid068(state: Dictionary, owners: Array) -> bool:
	var counts: Dictionary={}
	var all_boats: Array=state.get("fleet",[])+state.get("boardingPrizes",[])
	for owner in state.get("fleetOwners",[]):
		if not owner is Dictionary or not owner.get("boats") is Array:return false
		all_boats+=owner.boats
	for boat in all_boats:
		if not boat is Dictionary:return false
		var uid: String=str(boat.get("uid",""))
		if not uid.is_empty():counts[uid]=int(counts.get(uid,0))+1
	for owner in owners:
		for boat in owner.get("boats",[]):
			if int(counts.get(str(boat.get("uid","")),0))!=1:return false
	return true


static func _record_losses068(core, owner: Dictionary, location: Dictionary) -> void:
	var state: Dictionary=core.state
	if not NavalOrders.enrolled066(state,str(owner.id)):return # Existing HOME recorder owns ordinary coastal losses.
	var shipping_route: Dictionary=state.get("shipping068",{}).get("model",{}).get("route",{})
	var ocean_contact: Dictionary=state.get("ocean066",{}).get("contact",{})
	var is_shipping: bool=not shipping_route.is_empty() and str(shipping_route.get("ownerId",""))==str(owner.id)
	var salvage: Script=load("res://scripts/salvage.gd")
	var pending: Array=owner.boats.filter(func(b):return b.get("sunk",false) and not b.get("wreckRecorded",false))
	var remaining: int=pending.size()
	var living: int=NavalOrders.living_boats(owner).size()
	for boat in pending:
		var prefix: String="shipping-npc:" if is_shipping else "ocean-npc:"
		var records: Array=salvage.record_battle(core,{"ships":[boat],"chartPosition":location.position,"world064":location.world064},prefix+str(boat.uid))
		if records.is_empty():continue # Keep original pending hull/equipment for existing retry.
		var wreck: Dictionary=salvage.find_wreck(state,str(records[0].id))
		for good in owner.cargo:
			var lost: float=maxf(0.0,float(owner.cargo[good]))/maxi(1,living+remaining)
			owner.cargo[good]=maxf(0.0,float(owner.cargo[good])-lost)
			wreck.stores[good]=float(wreck.stores.get(good,0.0))+lost*0.5
			if good==owner.get("tradeGood",""):owner.tradeCargo=maxf(0.0,float(owner.tradeCargo)-lost)
		boat.wreckRecorded=true;remaining-=1
	if living>0:return
	owner.active=false;owner.atPort="";owner.erase("harborServiceUntilDay")
	var route: Dictionary=shipping_route if is_shipping else (ocean_contact if str(ocean_contact.get("ownerId",""))==str(owner.id) else {})
	if not route.is_empty():route.phase="lost";route.location.path=[];route.location.destination=""
	var memory: Dictionary=state.get("ocean066",{}).get("memory",{})
	for id in memory.get("pursuits",{}).keys():
		if id==owner.id or memory.pursuits[id].get("targetId")==owner.id:memory.pursuits.erase(id)
	memory.get("intents",{}).erase(str(owner.id))


static func _encounter_day(state: Dictionary, nav_ai: Dictionary) -> void:
	var day: int = int(state.get("econDay", 1))
	if int(nav_ai.get("encounterDay", -1)) == day and nav_ai.get("encounterOwners") is Dictionary and nav_ai.has("encounterCount"):
		return
	nav_ai["encounterDay"] = day
	nav_ai["encounterCount"] = 0
	nav_ai["encounterOwners"] = {}
	# Older saves have the bounded event log but no shared daily ledger.
	for event in nav_ai.get("encounters", []):
		if not (event is Dictionary) or int(event.get("day", -1)) != day:
			continue
		nav_ai["encounterCount"] = int(nav_ai["encounterCount"]) + 1
		nav_ai["encounterOwners"][str(event.get("a", ""))] = true
		nav_ai["encounterOwners"][str(event.get("b", ""))] = true


static func scan_encounters(core) -> Array:
	var state: Dictionary = NavalOrders.state_of(core)
	var nav_ai: Dictionary = ensure(state, NavalOrders.world_of(core))
	if nav_ai.is_empty() or int(nav_ai.get("encounterCount", 0)) >= MAX_ENCOUNTERS_PER_DAY:
		return []
	var messages: Array = []
	var busy: Dictionary = nav_ai["encounterOwners"]
	for pair in NavalCombat.nearby_hostile_pairs(state, ENCOUNTER_RADIUS, true):
		if int(nav_ai.get("encounterCount", 0)) >= MAX_ENCOUNTERS_PER_DAY:
			break
		var id_a: String = str(pair.get("a", ""))
		var id_b: String = str(pair.get("b", ""))
		if busy.has(id_a) or busy.has(id_b):
			continue
		var outcome: Dictionary = resolve_encounter(state, NavalOrders.find_owner(state, id_a), NavalOrders.find_owner(state, id_b), NavalOrders.find_patrol(state, id_a), NavalOrders.find_patrol(state, id_b), int(state.get("seed", 1)))
		if outcome.get("ok",false) and core is Object and core.has_method("campaign_naval_new116"):core.campaign_naval_new116(outcome.event)
		if bool(outcome.get("ok", false)) and bool(outcome.event.get("witnessed", false)):
			messages.append(str(outcome.get("summary", "")))
	# HOME patrols can respond to a physically present shared-travel fleet.
	# Their old dormant projection never enters the coastal grid or resolver.
	if core is Object and core.has_method("world_location064"):
		for id in ["patrol-0","patrol-7"]:
			if not NavalOrders.enrolled066(state,id) or busy.has(id):continue
			var actual: Dictionary=NavalOrders.canonical_location068(state,id)
			if actual.get("world064",{}).get("layer")!="home":continue
			for patrol in state.get("patrols",[]):
				if int(nav_ai.encounterCount)>=MAX_ENCOUNTERS_PER_DAY or busy.has(id):break
				var other_id: String=str(patrol.get("id",""))
				if not patrol.get("active",false) or NavalOrders.enrolled066(state,other_id) or busy.has(other_id):continue
				var other: Dictionary=NavalOrders.canonical_location068(state,other_id)
				if other.is_empty() or World068._distance(actual.position,other.position)>ENCOUNTER_RADIUS:continue
				var outcome: Dictionary=resolve_at068(core,id,other_id,actual,other)
				if outcome.get("ok",false) and core.has_method("campaign_naval_new116"):core.campaign_naval_new116(outcome.event)
				if outcome.get("ok",false) and outcome.event.get("witnessed",false):messages.append(str(outcome.get("summary","")))
	return messages


static func collect_replacements(core, port: Dictionary = {}) -> Array:
	var state: Dictionary = NavalOrders.state_of(core)
	var world: Dictionary = NavalOrders.world_of(core)
	ensure(state, world)
	if not _reconcile_losses(core):return []
	return NavalReplacements.collect_replacements(core, port)


static func request_replacement(core, owner: Dictionary, port: Dictionary = {}, hull_id: String = "") -> Dictionary:
	var state: Dictionary = NavalOrders.state_of(core)
	var world: Dictionary = NavalOrders.world_of(core)
	ensure(state, world)
	if not _reconcile_losses(core):return {"ok": false, "reason": "pending_wreck_transfer"}
	return NavalReplacements.request_replacement(core, owner, port, hull_id)


static func refresh_order_stats(owner: Dictionary, cur: Dictionary) -> void:
	# Derived observations only. Preserve order intent, route, logs and purses.
	var res: Dictionary = NavalOrders.fleet_reserves(owner)
	var perf: Dictionary = NavalOrders.fleet_performance(owner)
	cur["reserves"] = res
	cur["performance"] = perf
	cur["coins"] = int(res.get("coins", 0))
	cur["crew"] = int(res.get("crew", 0))
	cur["boats"] = int(res.get("boats", 0))
	cur["hpRatio"] = float(res.get("hpRatio", 0.0))
	cur["fuel"] = float(res.get("fuel", 0.0))
	cur["food"] = float(res.get("food", 0.0))
	cur["ammo"] = float(res.get("ammo", 0.0))
	cur["supplies"] = float(res.get("supplies", 0.0))
	cur["speed"] = float(perf.get("speed", 0.0))
	cur["firepower"] = float(perf.get("firepower", 0.0))
	cur["performanceFactor"] = float(perf.get("performanceFactor", 1.0))
	cur["morale"] = float(perf.get("morale", 85.0))


static func ensure(state: Dictionary, _world: Dictionary = {}) -> Dictionary:
	if state.is_empty():
		return {}
	if not (state.get("navalAi") is Dictionary):
		var cached: Dictionary = {}
		var owners_arr: Array = state.get("fleetOwners", []) if state.get("fleetOwners") is Array else []
		if not owners_arr.is_empty() and owners_arr[0] is Dictionary:
			var first_owner: Dictionary = owners_arr[0]
			if first_owner.get("_navalAiCache") is Dictionary:
				var cache_d: Dictionary = first_owner["_navalAiCache"]
				cached = cache_d.duplicate(true)
		state["navalAi"] = {
			"version": 1,
			"tickCount": int(cached.get("tickCount", 0)),
			"lastDay": int(cached.get("lastDay", state.get("econDay", 1))),
			"encounterDay": int(cached.get("encounterDay", -1)),
			"encounterCount": int(cached.get("encounterCount", 0)),
			"encounterOwners": cached.get("encounterOwners", {}),
			"encounters": cached.get("encounters", []),
			"replacements": cached.get("replacements", []),
			"spatialGrid": {},
			"ordersByOwner": {}
		}
	var nav_ai: Dictionary = state["navalAi"]
	var arr_keys: Array = ["encounters", "replacements"]
	for key_var in arr_keys:
		var k: String = str(key_var)
		if not (nav_ai.get(k) is Array):
			nav_ai[k] = []
	var dict_keys: Array = ["spatialGrid", "ordersByOwner", "sightingsByObserver"]
	for key_var in dict_keys:
		var k: String = str(key_var)
		if not (nav_ai.get(k) is Dictionary):
			nav_ai[k] = {}
	var by_owner: Dictionary = nav_ai["ordersByOwner"]

	var owners: Array = state.get("fleetOwners", []) if state.get("fleetOwners") is Array else []
	for owner_var in owners:
		if not (owner_var is Dictionary):
			continue
		var owner: Dictionary = owner_var
		Fleets.normalize_owner(owner)
		if NavalOrders.enrolled066(state,str(owner.get("id",""))):continue
		var boats: Array = owner.get("boats", []) if owner.get("boats") is Array else []
		if not owner.has("targetBoats"):
			owner["targetBoats"] = maxi(1, boats.size())
		var pref_existing: Array = owner.get("preferredHulls", []) if owner.get("preferredHulls") is Array else []
		if pref_existing.is_empty():
			var prefs: Array = []
			for b_var in boats:
				if b_var is Dictionary:
					var b: Dictionary = b_var
					var b_type: String = str(b.get("type", ""))
					if not b_type.is_empty():
						prefs.append(b_type)
			if prefs.is_empty():
				prefs.append("bilge_punt")
			owner["preferredHulls"] = prefs
		if not owner.has("nextBoatSeq"):
			owner["nextBoatSeq"] = boats.size() + 1

		var patrol: Dictionary = NavalOrders.find_patrol(state, str(owner.get("id", "")))
		var default_dest: String = str(patrol.get("to", ""))
		if default_dest.is_empty():
			var r: Array = owner.get("route", []) if owner.get("route") is Array else []
			default_dest = str(r[r.size() - 1]) if not r.is_empty() else str(owner.get("homePort", ""))

		var cur_ord_check: Dictionary = owner.get("order", {}) if owner.get("order") is Dictionary else {}
		if cur_ord_check.is_empty():
			if NavalOrders.is_story_owner(owner):
				var p_name: String = str(NavalOrders.find_port(state, default_dest).get("name", default_dest))
				NavalOrders.build_order(state, owner, "blockade", default_dest, "Maintaining story blockade station at %s." % p_name)
			else:
				var dock_port: Dictionary = NavalOrders.find_port(state, str(owner.get("atPort", "")))
				NavalOrders.assign_post_dock_order(state, owner, dock_port)
		else:
			var cur: Dictionary = cur_ord_check
			refresh_order_stats(owner, cur)
			if not cur.has("purpose") or str(cur.get("purpose", "")).is_empty():
				cur["purpose"] = "blockade" if NavalOrders.is_story_owner(owner) else str(owner.get("kind", "patrol"))
			if not cur.has("destination") or NavalOrders.find_port(state, str(cur.get("destination", ""))).is_empty():
				cur["destination"] = default_dest
			if not cur.has("reason") or str(cur.get("reason", "")).is_empty():
				cur["reason"] = "%s order toward %s." % [str(cur.get("purpose", "")).capitalize(), str(cur.get("destination", ""))]
			owner["purpose"] = str(cur.get("purpose", ""))
			owner["destination"] = str(cur.get("destination", ""))
			owner["reason"] = str(cur.get("reason", ""))
			by_owner[str(owner.get("id", ""))] = cur
	_encounter_day(state, nav_ai)
	NavalCombat.spatial_index(state)
	return nav_ai


static func arrived(core, owner: Dictionary, dock: Dictionary = {}) -> String:
	var state: Dictionary = NavalOrders.state_of(core)
	if NavalOrders.enrolled066(state,str(owner.get("id",""))):return str(owner.get("destination",""))
	ensure(state, NavalOrders.world_of(core))
	var losses_ready: bool = _reconcile_losses(core)
	Fleets.normalize_owner(owner)
	var home_id: String = str(owner.get("homePort", ""))
	var ports: Array = state.get("ports", []) if state.get("ports") is Array else []
	if home_id.is_empty() and not ports.is_empty() and ports[0] is Dictionary:
		var first_p: Dictionary = ports[0]
		home_id = str(first_p.get("id", ""))
	var dock_id: String = str(dock.get("id", owner.get("atPort", "")))
	var dock_port: Dictionary = dock if not dock.is_empty() else NavalOrders.find_port(state, dock_id)
	if not dock_port.is_empty():
		dock_id = str(dock_port.get("id", ""))
		owner["atPort"] = dock_id

	if not NavalOrders.is_story_owner(owner) and not owner.get("playerCompany",false):
		var res: Dictionary = NavalOrders.fleet_reserves(owner)
		var perf: Dictionary = NavalOrders.fleet_performance(owner)
		var recovery_reason: String = NavalOrders.needs_home_recovery(owner, res, perf)
		if losses_ready and not recovery_reason.is_empty() and dock_id == home_id and not dock_port.is_empty():
			if int(res.get("boats", 0)) < int(res.get("targetBoats", 1)):
				NavalReplacements.request_replacement(core, owner, dock_port)

	return NavalOrders.assign_post_dock_order(state, owner, dock_port)


static func tick(core, days = 1) -> Array:
	var state: Dictionary = NavalOrders.state_of(core)
	var world: Dictionary = NavalOrders.world_of(core)
	if state.is_empty():
		return []
	ensure(state, world)
	var day_steps: int = 0
	if (days is int or days is float) and is_finite(float(days)):
		day_steps = maxi(0, int(floor(float(days))))
	if day_steps <= 0:
		return []

	var nav_ai: Dictionary = state["navalAi"]
	var messages: Array = []
	for step_i in range(day_steps):
		var step_idx: int = int(step_i)
		# Share actual fleets, ports, logs and ledger; date only this bounded step.
		var day_state: Dictionary = state.duplicate(false)
		day_state["econDay"] = int(state.get("econDay", 1)) + step_idx
		nav_ai["tickCount"] = int(nav_ai.get("tickCount", 0)) + 1
		nav_ai["lastDay"] = int(day_state["econDay"])

		# 1. Advance any unstepped NPC slip orders, then collect ready hulls.
		var losses_ready: bool = _reconcile_losses(core)
		NavalReplacements.advance_unstepped_npc_orders(state, step_idx, day_steps)
		if losses_ready:messages.append_array(NavalReplacements.collect_replacements(core))

		# 2. Request funded replacement purchase or commission for under-strength non-story owners at harbor.
		var owners: Array = state.get("fleetOwners", []) if state.get("fleetOwners") is Array else []
		for owner_var in owners:
			if not (owner_var is Dictionary):
				continue
			var owner: Dictionary = owner_var
			if NavalOrders.enrolled066(state,str(owner.get("id",""))) or NavalOrders.is_story_owner(owner) or owner.get("playerCompany",false):
				continue
			var res: Dictionary = NavalOrders.fleet_reserves(owner)
			var living: int = int(res.get("boats", 0))
			var target: int = int(res.get("targetBoats", 1))
			if losses_ready and living < target and not NavalReplacements.owner_has_queued_replacement(state, str(owner.get("id", ""))):
				var at_id: String = str(owner.get("atPort", ""))
				if living == 0 and at_id.is_empty():
					at_id = str(owner.get("homePort", ""))
					owner["atPort"] = at_id
				if not at_id.is_empty():
					var p: Dictionary = NavalOrders.find_port(state, at_id)
					if not p.is_empty():
						var rep: Dictionary = NavalReplacements.request_replacement(core, owner, p)
						if bool(rep.get("ok", false)) and rep.has("message"):
							messages.append(str(rep.get("message", "")))

		# 3. Daily and mid-day calls share one persistent encounter budget.
		messages.append_array(scan_encounters(day_state))

		# 4. Refresh orders, reserves, and performance metrics for all owners.
		for owner_var in owners:
			if not (owner_var is Dictionary):
				continue
			var owner: Dictionary = owner_var
			if NavalOrders.enrolled066(state,str(owner.get("id",""))) or NavalOrders.is_story_owner(owner) or bool(owner.get("playerCompany", false)):
				# ensure() refreshes derived stats without replacing authored/player intent.
				continue
			NavalOrders.refresh_at_sea(day_state, owner)
			var pat: Dictionary = NavalOrders.find_patrol(state, str(owner.get("id", "")))
			if not pat.is_empty():
				pat["active"] = bool(owner.get("active", false)) and not NavalOrders.living_boats(owner).is_empty()
		NavalCombat.spatial_index(state, CELL_SIZE)
	return messages.slice(0, 24)
