extends RefCounted
## Autonomous NPC fleet coordinator (v0.013): thin entry point over NavalOrders, NavalCombat, and NavalReplacements.
## Pure-data module: no global RNG, no scene/UI access, strict bronze coin and workforce conservation.

const Fleets = preload("res://scripts/fleet_economy.gd")
const NavalOrders = preload("res://scripts/naval_orders.gd")
const NavalCombat = preload("res://scripts/naval_combat.gd")
const NavalReplacements = preload("res://scripts/naval_replacements.gd")

const CELL_SIZE: float = NavalCombat.CELL_SIZE
const ENCOUNTER_RADIUS: float = NavalCombat.ENCOUNTER_RADIUS
const INTERCEPT_RADIUS: float = NavalCombat.INTERCEPT_RADIUS
const MAX_ENCOUNTERS_PER_DAY: int = NavalCombat.MAX_ENCOUNTERS_PER_DAY
const MAX_ORDER_LOG: int = NavalOrders.MAX_ORDER_LOG
const MAX_EVENT_LOG: int = NavalOrders.MAX_EVENT_LOG
const MAX_SLIPS_PER_PORT: int = NavalReplacements.MAX_SLIPS_PER_PORT


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
	ensure(state)
	return NavalCombat.resolve_encounter(state, owner_a, owner_b, patrol_a, patrol_b, seed_val)


static func collect_replacements(core, port: Dictionary = {}) -> Array:
	var state: Dictionary = NavalOrders.state_of(core)
	var world: Dictionary = NavalOrders.world_of(core)
	ensure(state, world)
	return NavalReplacements.collect_replacements(core, port)


static func request_replacement(core, owner: Dictionary, port: Dictionary = {}, hull_id: String = "") -> Dictionary:
	var state: Dictionary = NavalOrders.state_of(core)
	var world: Dictionary = NavalOrders.world_of(core)
	ensure(state, world)
	return NavalReplacements.request_replacement(core, owner, port, hull_id)


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
	var dict_keys: Array = ["spatialGrid", "ordersByOwner"]
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
	NavalCombat.spatial_index(state)
	return nav_ai


static func arrived(core, owner: Dictionary, dock: Dictionary = {}) -> String:
	var state: Dictionary = NavalOrders.state_of(core)
	ensure(state, NavalOrders.world_of(core))
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

	if not NavalOrders.is_story_owner(owner):
		var res: Dictionary = NavalOrders.fleet_reserves(owner)
		var perf: Dictionary = NavalOrders.fleet_performance(owner)
		var recovery_reason: String = NavalOrders.needs_home_recovery(owner, res, perf)
		if not recovery_reason.is_empty() and dock_id == home_id and not dock_port.is_empty():
			Fleets.dock(owner, dock_port)
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
		nav_ai["tickCount"] = int(nav_ai.get("tickCount", 0)) + 1
		nav_ai["lastDay"] = int(state.get("econDay", 1)) + step_idx

		# 1. Advance any unstepped NPC slip orders, then collect ready hulls.
		NavalReplacements.advance_unstepped_npc_orders(state, step_idx, day_steps)
		messages.append_array(NavalReplacements.collect_replacements(core))

		# 2. Request funded replacement purchase or commission for under-strength non-story owners at harbor.
		var owners: Array = state.get("fleetOwners", []) if state.get("fleetOwners") is Array else []
		for owner_var in owners:
			if not (owner_var is Dictionary):
				continue
			var owner: Dictionary = owner_var
			if NavalOrders.is_story_owner(owner):
				continue
			var res: Dictionary = NavalOrders.fleet_reserves(owner)
			var living: int = int(res.get("boats", 0))
			var target: int = int(res.get("targetBoats", 1))
			if living < target and not NavalReplacements.owner_has_queued_replacement(state, str(owner.get("id", ""))):
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

		# 3. Resolve bounded daily pair encounters for spatially nearby hostile NPC chart patrols.
		var pairs: Array = NavalCombat.nearby_hostile_pairs(state, ENCOUNTER_RADIUS)
		for pair_var in pairs:
			if not (pair_var is Dictionary):
				continue
			var pair: Dictionary = pair_var
			var id_a: String = str(pair.get("a", ""))
			var id_b: String = str(pair.get("b", ""))
			var pat_a: Dictionary = NavalOrders.find_patrol(state, id_a)
			var pat_b: Dictionary = NavalOrders.find_patrol(state, id_b)
			var own_a: Dictionary = NavalOrders.find_owner(state, id_a)
			var own_b: Dictionary = NavalOrders.find_owner(state, id_b)
			if own_a.is_empty() or own_b.is_empty():
				continue
			var outcome: Dictionary = NavalCombat.resolve_encounter(
				state,
				own_a,
				own_b,
				pat_a,
				pat_b,
				int(state.get("seed", 1)) + step_idx * 97
			)
			if bool(outcome.get("ok", false)) and outcome.has("summary"):
				messages.append(str(outcome.get("summary", "")))

		# 4. Refresh orders, reserves, and performance metrics for all owners.
		for owner_var in owners:
			if not (owner_var is Dictionary):
				continue
			var owner: Dictionary = owner_var
			var cur_ord: Dictionary = owner.get("order", {}) if owner.get("order") is Dictionary else {}
			if NavalOrders.is_story_owner(owner):
				var s_route: Array = owner.get("route", []) if owner.get("route") is Array else []
				var s_dest: String = str(s_route[s_route.size() - 1]) if not s_route.is_empty() else str(owner.get("homePort", ""))
				NavalOrders.build_order(state, owner, "blockade", s_dest, str(cur_ord.get("reason", "Maintaining story blockade station.")))
				continue
			var res_now: Dictionary = NavalOrders.fleet_reserves(owner)
			var perf_now: Dictionary = NavalOrders.fleet_performance(owner)
			var rec_why: String = NavalOrders.needs_home_recovery(owner, res_now, perf_now)
			var cur_purpose: String = str(cur_ord.get("purpose", ""))
			if not rec_why.is_empty() and not (cur_purpose in ["withdraw", "repair", "resupply", "replace"]):
				var h_id: String = str(owner.get("homePort", ""))
				var purp: String = "replace" if int(res_now.get("boats", 0)) < int(res_now.get("targetBoats", 1)) else "withdraw"
				NavalOrders.build_order(state, owner, purp, h_id, rec_why)
			else:
				NavalOrders.build_order(
					state,
					owner,
					str(cur_ord.get("purpose", owner.get("kind", "patrol"))),
					str(cur_ord.get("destination", owner.get("homePort", ""))),
					str(cur_ord.get("reason", "")),
					str(cur_ord.get("targetOwnerId", ""))
				)
			var pat: Dictionary = NavalOrders.find_patrol(state, str(owner.get("id", "")))
			if not pat.is_empty():
				pat["active"] = bool(owner.get("active", false)) and not NavalOrders.living_boats(owner).is_empty()
		NavalCombat.spatial_index(state, CELL_SIZE)
	return messages.slice(0, 24)
