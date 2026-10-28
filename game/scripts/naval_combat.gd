extends RefCounted
## Spatial grid indexing, hostile NPC pair detection, and seeded skirmish resolution (v0.013).
## Preloads NavalOrders and core damage/economy/money scripts only (no preload cycles).

const Factions=preload("res://scripts/factions.gd")
const Damage = preload("res://scripts/damage.gd")
const Economy = preload("res://scripts/economy.gd")
const Goods = preload("res://scripts/goods.gd")
const Money = preload("res://scripts/money.gd")
const Fleets = preload("res://scripts/fleet_economy.gd")
const NavalOrders = preload("res://scripts/naval_orders.gd")
const EquipmentOwnerService = preload("res://scripts/equipment_owner_service.gd")

const CELL_SIZE: float = 240.0
const ENCOUNTER_RADIUS: float = 165.0
const INTERCEPT_RADIUS: float = 210.0
const MAX_ENCOUNTERS_PER_DAY: int = 4
const MAX_EVENT_LOG: int = 24


static func spatial_index(state: Dictionary, cell_size: float = CELL_SIZE) -> Dictionary:
	var grid: Dictionary = {}
	var step: float = maxf(32.0, cell_size)
	var patrols: Array = state.get("patrols", []) if state.get("patrols") is Array else []
	for patrol_var in patrols:
		if not (patrol_var is Dictionary):
			continue
		var patrol: Dictionary = patrol_var
		if not bool(patrol.get("active", false)):
			continue
		var pid: String = str(patrol.get("id", ""))
		if pid.is_empty() or pid.begins_with("story-"):
			continue
		var owner: Dictionary = NavalOrders.find_owner(state, pid)
		if owner.is_empty() or NavalOrders.is_story_owner(owner) or not bool(owner.get("active", false)) or NavalOrders.living_boats(owner).is_empty():
			continue
		var cx: int = int(floor(float(patrol.get("x", 0.0)) / step))
		var cy: int = int(floor(float(patrol.get("y", 0.0)) / step))
		var key: String = "%d:%d" % [cx, cy]
		if not grid.has(key):
			grid[key] = []
		var cell_list: Array = grid[key]
		cell_list.append(pid)
	if state.get("navalAi") is Dictionary:
		var nav_ai: Dictionary = state["navalAi"]
		nav_ai["spatialGrid"] = grid
		var owners_arr: Array = state.get("fleetOwners", []) if state.get("fleetOwners") is Array else []
		if not owners_arr.is_empty() and owners_arr[0] is Dictionary:
			var first_owner: Dictionary = owners_arr[0]
			var enc_arr: Array = nav_ai.get("encounters", []) if nav_ai.get("encounters") is Array else []
			var rep_arr: Array = nav_ai.get("replacements", []) if nav_ai.get("replacements") is Array else []
			first_owner["_navalAiCache"] = {
				"tickCount": int(nav_ai.get("tickCount", 0)),
				"lastDay": int(nav_ai.get("lastDay", 1)),
				"encounterDay": int(nav_ai.get("encounterDay", -1)),
				"encounterCount": int(nav_ai.get("encounterCount", 0)),
				"encounterOwners": nav_ai.get("encounterOwners", {}).duplicate(true),
				"encounters": enc_arr.duplicate(true),
				"replacements": rep_arr.duplicate(true)
			}
	return grid


static func are_hostile(state: Dictionary, owner_a: Dictionary, patrol_a: Dictionary, owner_b: Dictionary, patrol_b: Dictionary) -> bool:
	if owner_a.is_empty() or owner_b.is_empty() or str(owner_a.get("id", "")) == str(owner_b.get("id", "")):
		return false
	if NavalOrders.is_story_owner(owner_a) or NavalOrders.is_story_owner(owner_b):
		return false
	var fa: String = str(owner_a.get("faction", ""))
	var fb: String = str(owner_b.get("faction", ""))
	if fa == fb and not fa.is_empty():
		return false
	if state.get("relationships") is Dictionary:
		return Factions.relation(state,fa,fb)<=-20
	return (fa=="raiders")!=(fb=="raiders")


static func _compare_pair_priority(x: Dictionary, y: Dictionary) -> bool:
	return float(x.get("priority", 0.0)) < float(y.get("priority", 0.0))


static func nearby_hostile_pairs(state: Dictionary, radius: float = ENCOUNTER_RADIUS, all_candidates: bool = false) -> Array:
	var grid: Dictionary = spatial_index(state, CELL_SIZE)
	var candidates: Array = []
	var seen_pairs: Dictionary = {}
	var patrols: Array = state.get("patrols", []) if state.get("patrols") is Array else []
	for patrol_a_var in patrols:
		if not (patrol_a_var is Dictionary):
			continue
		var patrol_a: Dictionary = patrol_a_var
		if not bool(patrol_a.get("active", false)):
			continue
		var id_a: String = str(patrol_a.get("id", ""))
		if id_a.is_empty() or id_a.begins_with("story-"):
			continue
		var owner_a: Dictionary = NavalOrders.find_owner(state, id_a)
		if owner_a.is_empty() or NavalOrders.is_story_owner(owner_a) or not bool(owner_a.get("active", false)) or NavalOrders.living_boats(owner_a).is_empty():
			continue
		var pos_a: Vector2 = Vector2(float(patrol_a.get("x", 0.0)), float(patrol_a.get("y", 0.0)))
		var cx: int = int(floor(pos_a.x / CELL_SIZE))
		var cy: int = int(floor(pos_a.y / CELL_SIZE))
		for dx in [-1, 0, 1]:
			var offset_x: int = int(dx)
			for dy in [-1, 0, 1]:
				var offset_y: int = int(dy)
				var cell_key: String = "%d:%d" % [cx + offset_x, cy + offset_y]
				var cell_entries: Array = grid.get(cell_key, []) if grid.get(cell_key) is Array else []
				for id_b_var in cell_entries:
					var id_b: String = str(id_b_var)
					if id_b <= id_a:
						continue
					var pair_id: String = "%s|%s" % [id_a, id_b]
					if seen_pairs.has(pair_id):
						continue
					seen_pairs[pair_id] = true
					var patrol_b: Dictionary = NavalOrders.find_patrol(state, id_b)
					var owner_b: Dictionary = NavalOrders.find_owner(state, id_b)
					if patrol_b.is_empty() or owner_b.is_empty() or not are_hostile(state, owner_a, patrol_a, owner_b, patrol_b):
						continue
					var pos_b: Vector2 = Vector2(float(patrol_b.get("x", 0.0)), float(patrol_b.get("y", 0.0)))
					var dist: float = pos_a.distance_to(pos_b)
					var ord_a: Dictionary = owner_a.get("order", {}) if owner_a.get("order") is Dictionary else {}
					var ord_b: Dictionary = owner_b.get("order", {}) if owner_b.get("order") is Dictionary else {}
					var targeted: bool = (
						str(ord_a.get("targetOwnerId", "")) == id_b
						or str(ord_b.get("targetOwnerId", "")) == id_a
					)
					var eff_radius: float = maxf(radius, INTERCEPT_RADIUS if targeted else radius)
					if dist <= eff_radius:
						var has_patrol: bool = (str(owner_a.get("kind", "")) == "patrol" or str(owner_b.get("kind", "")) == "patrol")
						var prio_base: float = 0.0 if has_patrol else 1000.0
						candidates.append({
							"a": id_a,
							"b": id_b,
							"distance": snappedf(dist, 0.1),
							"priority": prio_base + dist
						})
	candidates.sort_custom(_compare_pair_priority)
	# The persistent scanner reserves owners only after a successful resolution.
	# Keep the original disjoint shortlist for existing callers.
	if all_candidates:
		return candidates
	var chosen: Array = []
	var busy: Dictionary = {}
	for item_var in candidates:
		if not (item_var is Dictionary):
			continue
		var item: Dictionary = item_var
		if chosen.size() >= MAX_ENCOUNTERS_PER_DAY:
			break
		var a_id: String = str(item.get("a", ""))
		var b_id: String = str(item.get("b", ""))
		if busy.has(a_id) or busy.has(b_id):
			continue
		busy[a_id] = true
		busy[b_id] = true
		chosen.append(item)
	return chosen


static func _alive_defenders(defenders: Array) -> Array:
	var out: Array = []
	for d_var in defenders:
		if d_var is Dictionary:
			var d: Dictionary = d_var
			if not bool(d.get("sunk", false)):
				out.append(d)
	return out


static func boat_weapon_power(boat: Dictionary, perf_factor: float = 1.0) -> Dictionary:
	return EquipmentOwnerService.boat_weapon_power(boat, perf_factor)


static func fleet_firepower(owner: Dictionary) -> float:
	return EquipmentOwnerService.fleet_firepower(owner)


static func _fire_salvo_side(rng: RandomNumberGenerator, attackers: Array, defenders: Array, perf_factor: float, dt: float) -> Dictionary:
	var shots_fired: int = 0
	var ammo_used: int = 0
	var hits_landed: int = 0
	var hp_damage: float = 0.0
	var active_defs: Array = _alive_defenders(defenders)
	if active_defs.is_empty():
		return {"shots": 0, "ammoUsed": 0, "hits": 0, "damage": 0.0}

	for s_var in attackers:
		if not (s_var is Dictionary):
			continue
		var s: Dictionary = s_var
		if bool(s.get("sunk", false)) or float(s.get("ammo", 0.0)) <= 0.0:
			continue
		var st: Dictionary = Damage.get_status(s)
		var wf: float = float(st.get("weaponFactor", 0.0)) * perf_factor
		if wf <= 0.02:
			continue
		var mounts: Array = []
		if EquipmentOwnerService.is_canonical_or_foreign_boat(s):
			var wp: Dictionary = boat_weapon_power(s, perf_factor)
			if not bool(wp.get("ok", false)) or float(wp.get("firepower", 0.0)) <= 0.0:
				continue
			mounts = wp.get("activeMounts", [])
		else:
			var spec_d: Dictionary = s.get("spec", {}) if s.get("spec") is Dictionary else {}
			if spec_d.get("weaponMounts") is Array:
				var wm: Array = spec_d["weaponMounts"]
				if not wm.is_empty():
					mounts = wm
			if mounts.is_empty():
				mounts = [{
					"kind": str(spec_d.get("weapon", "gun")),
					"damage": float(spec_d.get("damage", 10.0)),
					"fireRate": float(s.get("economyBaseFireRate", spec_d.get("fireRate", 1.5))),
					"ammoCost": 1
				}]
		for m_var in mounts:
			if not (m_var is Dictionary):
				continue
			var m: Dictionary = m_var
			var mount_wf: float = float(m.get("effectiveWf", wf))
			if not is_finite(mount_wf) or mount_wf <= 0.02:
				continue
			var ammo_cost: int = maxi(1, int(ceil(float(m.get("ammoCost", 1.0)))))
			var avail_shots: int = int(floor(float(s.get("ammo", 0.0)) / float(ammo_cost)))
			if avail_shots <= 0:
				continue
			var fr: float = clampf(float(m.get("fireRate", 1.0)), 0.1, 12.0)
			var salvo_shots: int = mini(avail_shots, maxi(1, int(round(fr * mount_wf * dt * 0.42))))
			var kind_raw: String = str(m.get("kind", "gun"))
			var hit_kind: String = "bullet" if kind_raw == "gun" else ("shell" if kind_raw == "cannon" else kind_raw)
			var dmg_mult: float = 1.8 if hit_kind == "torpedo" else 1.0
			var base_dmg: float = maxf(1.0, float(m.get("damage", 10.0))) * dmg_mult
			var pen: float = 18.0 if hit_kind == "torpedo" else (4.0 if hit_kind == "shell" else 0.0)

			for _shot in range(salvo_shots):
				active_defs = _alive_defenders(active_defs)
				if active_defs.is_empty():
					break
				# Spend a mount's real rounds only when a living target remains.
				s["ammo"] = maxf(0.0, float(s.get("ammo", 0.0)) - float(ammo_cost))
				shots_fired += 1
				ammo_used += ammo_cost
				var target_idx: int = rng.randi_range(0, active_defs.size() - 1)
				var target: Dictionary = active_defs[target_idx]
				var t_spec: Dictionary = target.get("spec", {}) if target.get("spec") is Dictionary else {}
				var t_size: float = clampf(float(t_spec.get("size", 16.0)), 10.0, 40.0)
				var t_status: Dictionary = Damage.get_status(target)
				var t_spd_factor: float = float(t_status.get("speedFactor", 1.0))
				var hit_prob: float = clampf(0.42 + (t_size - 16.0) * 0.012 - t_spd_factor * 0.08, 0.24, 0.74)
				if rng.randf() <= hit_prob:
					hits_landed += 1
					var before_hp: float = float(target.get("hp", 0.0))
					var sec: String = "waterline" if hit_kind == "torpedo" else ("engine" if rng.randf() < 0.22 else "bow")
					Damage.apply_hit(target, {
						"damage": base_dmg,
						"kind": hit_kind,
						"penetration": pen,
						"incendiary": hit_kind == "rocket",
						"section": sec
					}, rng)
					hp_damage += maxf(0.0, before_hp - float(target.get("hp", 0.0)))
	return {"shots": shots_fired, "ammoUsed": ammo_used, "hits": hits_landed, "damage": snappedf(hp_damage, 0.1)}


static func _should_withdraw_side(owner: Dictionary, initial_boats: int, enemy_firepower: float) -> bool:
	var res: Dictionary = NavalOrders.fleet_reserves(owner)
	var perf: Dictionary = NavalOrders.fleet_performance(owner)
	var cur_boats: int = int(res.get("boats", 0))
	if cur_boats <= 0:
		return true
	if cur_boats < initial_boats:
		return true
	if float(res.get("ammo", 0.0)) <= 0.5:
		return true
	var hp_ratio: float = float(res.get("hpRatio", 1.0))
	var min_eng: float = float(res.get("minEngine", 1.0))
	if hp_ratio < 0.56 or min_eng < 0.52:
		return true
	var own_firepower: float = fleet_firepower(owner) if EquipmentOwnerService.has_canonical_or_foreign_boat(owner) else float(perf.get("firepower", 0.0))
	if str(owner.get("kind", "")) == "trader" and hp_ratio < 0.82 and enemy_firepower > own_firepower * 1.1:
		return true
	return false


static func resolve_encounter(state: Dictionary, owner_a: Dictionary, owner_b: Dictionary, patrol_a: Dictionary = {}, patrol_b: Dictionary = {}, seed_val: int = 1) -> Dictionary:
	if NavalOrders.is_story_owner(owner_a) or NavalOrders.is_story_owner(owner_b):
		return {"ok": false, "reason": "story_owner_excluded"}
	var boats_a: Array = NavalOrders.living_boats(owner_a)
	var boats_b: Array = NavalOrders.living_boats(owner_b)
	if boats_a.is_empty() or boats_b.is_empty():
		return {"ok": false, "reason": "no_living_boats"}

	# Retain the canonical owners' original physical boats across salvo and sink
	# handling. Surviving hull counts do not account for actual crew deaths.
	var original_a: Array = owner_a.boats
	var original_b: Array = owner_b.boats
	var crew_before_a: float = 0.0
	var crew_before_b: float = 0.0
	for boat in original_a: crew_before_a += float(boat.crew)
	for boat in original_b: crew_before_b += float(boat.crew)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var pair_str: String = str(owner_a.get("id", "")) + ":" + str(owner_b.get("id", ""))
	var pair_hash: int = absi(int(pair_str.hash()))
	rng.seed = int(seed_val) * 1103515245 + int(state.get("econDay", 1)) * 12345 + pair_hash

	var init_a: int = boats_a.size()
	var init_b: int = boats_b.size()
	var shots_a: int = 0
	var shots_b: int = 0
	var ammo_used_a: int = 0
	var ammo_used_b: int = 0
	var hits_a: int = 0
	var hits_b: int = 0
	var dmg_to_b: float = 0.0
	var dmg_to_a: float = 0.0
	var retreated: String = ""
	var salvos_run: int = 0

	for salvo in range(5):
		boats_a = NavalOrders.living_boats(owner_a)
		boats_b = NavalOrders.living_boats(owner_b)
		if boats_a.is_empty() or boats_b.is_empty():
			break
		var perf_a: Dictionary = NavalOrders.fleet_performance(owner_a)
		var perf_b: Dictionary = NavalOrders.fleet_performance(owner_b)
		var fp_a: float = fleet_firepower(owner_a) if EquipmentOwnerService.has_canonical_or_foreign_boat(owner_a) else float(perf_a.get("firepower", 0.0))
		var fp_b: float = fleet_firepower(owner_b) if EquipmentOwnerService.has_canonical_or_foreign_boat(owner_b) else float(perf_b.get("firepower", 0.0))
		perf_a["firepower"] = fp_a
		perf_b["firepower"] = fp_b
		if salvo >= 1:
			var a_retreat: bool = _should_withdraw_side(owner_a, init_a, fp_b)
			var b_retreat: bool = _should_withdraw_side(owner_b, init_b, fp_a)
			if a_retreat or b_retreat:
				retreated = str(owner_a.get("id", "")) if (a_retreat and not b_retreat) else (str(owner_b.get("id", "")) if (b_retreat and not a_retreat) else "both")
				break
		salvos_run += 1
		var dt_salvo: float = 5.5
		var res_a: Dictionary = _fire_salvo_side(rng, boats_a, boats_b, float(perf_a.get("performanceFactor", 1.0)), dt_salvo)
		var res_b: Dictionary = _fire_salvo_side(rng, boats_b, boats_a, float(perf_b.get("performanceFactor", 1.0)), dt_salvo)
		shots_a += int(res_a.get("shots", 0))
		ammo_used_a += int(res_a.get("ammoUsed", 0))
		hits_a += int(res_a.get("hits", 0))
		dmg_to_b += float(res_a.get("damage", 0.0))
		shots_b += int(res_b.get("shots", 0))
		ammo_used_b += int(res_b.get("ammoUsed", 0))
		hits_b += int(res_b.get("hits", 0))
		dmg_to_a += float(res_b.get("damage", 0.0))

		var all_a: Array = owner_a.get("boats", []) if owner_a.get("boats") is Array else []
		for b_var in all_a:
			if b_var is Dictionary:
				var b: Dictionary = b_var
				if not bool(b.get("sunk", false)):
					Damage.tick_ship(b, dt_salvo, {"inCombat": true})
		var all_b: Array = owner_b.get("boats", []) if owner_b.get("boats") is Array else []
		for b_var in all_b:
			if b_var is Dictionary:
				var b: Dictionary = b_var
				if not bool(b.get("sunk", false)):
					Damage.tick_ship(b, dt_salvo, {"inCombat": true})

	var owners_pair: Array = [owner_a, owner_b]
	for owner_var in owners_pair:
		var owner: Dictionary = owner_var
		var o_boats: Array = owner.get("boats", []) if owner.get("boats") is Array else []
		for b_var in o_boats:
			if not (b_var is Dictionary):
				continue
			var b: Dictionary = b_var
			if bool(b.get("sunk", false)):
				b["hp"] = 0.0
				b["crew"] = 0.0
				b["wounded"] = 0.0
				b["water"] = 0.0
				b["fire"] = 0.0
				b["breaches"] = []
			else:
				var prev_pol: String = str(b.get("policy", "balanced"))
				b["policy"] = "repair"
				Damage.tick_ship(b, 8.0, {"inCombat": false})
				b["policy"] = prev_pol
				if bool(b.get("sunk", false)):
					b["hp"] = 0.0
					b["crew"] = 0.0
					b["wounded"] = 0.0
					b["water"] = 0.0
					b["fire"] = 0.0
					b["breaches"] = []

	var crew_after_a: float = 0.0
	var crew_after_b: float = 0.0
	for boat in original_a: crew_after_a += float(boat.crew)
	for boat in original_b: crew_after_b += float(boat.crew)
	var rem_a: int = NavalOrders.living_boats(owner_a).size()
	var rem_b: int = NavalOrders.living_boats(owner_b).size()
	if rem_a==0:owner_a.defeats=int(owner_a.get("defeats",0))+1
	if rem_b==0:owner_b.defeats=int(owner_b.get("defeats",0))+1
	var sunk_a: int = maxi(0, init_a - rem_a)
	var sunk_b: int = maxi(0, init_b - rem_b)

	var winner: Dictionary = {}
	var loser: Dictionary = {}
	var id_a_str: String = str(owner_a.get("id", ""))
	var id_b_str: String = str(owner_b.get("id", ""))
	if rem_a > 0 and (rem_b == 0 or retreated == id_b_str or (sunk_b > sunk_a and retreated != id_a_str)):
		winner = owner_a
		loser = owner_b
	elif rem_b > 0 and (rem_a == 0 or retreated == id_a_str or (sunk_a > sunk_b and retreated != id_b_str)):
		winner = owner_b
		loser = owner_a
	elif rem_a > 0 and rem_b > 0 and dmg_to_b != dmg_to_a:
		winner = owner_a if dmg_to_b > dmg_to_a else owner_b
		loser = owner_b if dmg_to_b > dmg_to_a else owner_a

	var loot_coins: int = 0
	var captured_good: String = ""
	var captured_qty: int = 0
	if not winner.is_empty() and not loser.is_empty():
		var loser_wiped: bool = NavalOrders.living_boats(loser).is_empty()
		var share: float = 0.25 if loser_wiped else 0.10
		var loser_coins: int = int(loser.get("coins", 0))
		loot_coins = mini(loser_coins, int(floor(float(loser_coins) * share)))
		if loot_coins > 0:
			var m_log: Array = state.get("moneyLog", []) if state.get("moneyLog") is Array else []
			Money.move(loser, "coins", winner, "coins", loot_coins, "NPC skirmish prize coins", m_log)
		var l_good: String = str(loser.get("tradeGood", "timber"))
		var loser_cargo: Dictionary = loser.get("cargo", {}) if loser.get("cargo") is Dictionary else {}
		var winner_cargo: Dictionary = winner.get("cargo", {}) if winner.get("cargo") is Dictionary else {}
		var l_avail: int = mini(int(floor(float(loser_cargo.get(l_good, 0.0)))), int(floor(float(loser.get("tradeCargo", 0.0)))))
		if str(loser.get("kind", "")) != "trader":
			# Raiders have no merchant manifest. A patrol can recover their real
			# prize lots; operating stores remain aboard under the existing rule.
			l_avail = 0
			for good in Goods.ITEMS:
				if good in ["food", "fuel", "supplies", "ammo"]:
					continue
				var held: int = maxi(0, int(floor(float(loser_cargo.get(good, 0.0)))))
				if held > 0:
					l_good = str(good)
					l_avail = held
					break
		if l_avail > 0 and Goods.ITEMS.has(l_good):
			var w_res: Dictionary = NavalOrders.fleet_reserves(winner)
			var w_free: float = maxf(0.0, float(w_res.get("capacity", 0.0)) - float(Economy.cargo_weight(winner_cargo)))
			var item_def: Dictionary = Goods.ITEMS[l_good]
			var g_weight: float = maxf(1.0, float(item_def.get("weight", 1.0)))
			var take: int = mini(l_avail, int(floor(w_free / g_weight)))
			if take > 0:
				loser_cargo[l_good] = maxf(0.0, float(loser_cargo.get(l_good, 0.0)) - float(take))
				if str(loser.get("tradeGood", "")) == l_good:
					loser["tradeCargo"] = maxf(0.0, float(loser.get("tradeCargo", 0.0)) - float(take))
				winner_cargo[l_good] = maxf(0.0, float(winner_cargo.get(l_good, 0.0)) + float(take))
				if str(winner.get("kind", "")) == "trader" and str(winner.get("tradeGood", "")) == l_good:
					winner["tradeCargo"] = maxf(0.0, float(winner.get("tradeCargo", 0.0)) + float(take))
				captured_good = l_good
				captured_qty = take

	var sides: Array = [[owner_a, patrol_a, owner_b], [owner_b, patrol_b, owner_a]]
	for side_var in sides:
		var pair: Array = side_var
		var own: Dictionary = pair[0]
		var pat: Dictionary = pair[1]
		var opp: Dictionary = pair[2]
		var res_now: Dictionary = NavalOrders.fleet_reserves(own)
		var perf_now: Dictionary = NavalOrders.fleet_performance(own)
		var home_id: String = str(own.get("homePort", ""))
		var home_name: String = str(NavalOrders.find_port(state, home_id).get("name", home_id))
		if int(res_now.get("boats", 0)) <= 0:
			own["atPort"] = home_id
			if not pat.is_empty():
				pat["active"] = false
			NavalOrders.build_order(state, own, "replace", home_id, "All hulls lost against %s; seeking replacement at %s." % [str(opp.get("name", "enemy")), home_name])
		elif str(own.get("id", "")) == retreated or retreated == "both" or not NavalOrders.needs_home_recovery(own, res_now, perf_now).is_empty():
			NavalOrders.build_order(state, own, "withdraw", home_id, "Withdrawing to %s for repairs and stores after skirmish with %s." % [home_name, str(opp.get("name", "enemy"))])
			if not pat.is_empty() and str(pat.get("to", "")) != home_id and str(pat.get("from", "")) == home_id:
				var prev_from: String = str(pat.get("from", ""))
				pat["from"] = str(pat.get("to", ""))
				pat["to"] = prev_from
				if pat.get("course") is Array:
					var course_arr: Array = pat["course"]
					course_arr.reverse()
				pat["progress"] = clampf(1.0 - float(pat.get("progress", 0.0)), 0.0, 0.99)
		else:
			var cur_ord: Dictionary = own.get("order", {}) if own.get("order") is Dictionary else {}
			NavalOrders.build_order(state, own, str(cur_ord.get("purpose", own.get("kind", "patrol"))), str(cur_ord.get("destination", home_id)), str(cur_ord.get("reason", "")), str(cur_ord.get("targetOwnerId", "")))

	var kinds: Array = [str(owner_a.get("kind", "")), str(owner_b.get("kind", ""))]
	var encounter_kind: String = "raid" if kinds.has("raider") and kinds.has("trader") else ("patrol" if kinds.has("raider") and kinds.has("patrol") else "faction_clash")
	var label: String = "Raid" if encounter_kind == "raid" else ("Patrol action" if encounter_kind == "patrol" else "Faction clash")
	var summary: String = "%s: %s (%s) engaged %s (%s): %d/%d shots, %d sunk, %s." % [
		label,
		str(owner_a.get("name", id_a_str)),
		id_a_str,
		str(owner_b.get("name", id_b_str)),
		id_b_str,
		shots_a,
		shots_b,
		sunk_a + sunk_b,
		("retreat by " + retreated) if not retreated.is_empty() else ("won by " + str(winner.get("id", "draw")))
	]
	Fleets._log(owner_a, summary)
	Fleets._log(owner_b, summary)

	var ev: Dictionary = {
		"day": int(state.get("econDay", 1)),
		"kind": encounter_kind,
		"a": id_a_str,
		"b": id_b_str,
		"salvos": salvos_run,
		"shotsA": shots_a,
		"shotsB": shots_b,
		"hitsA": hits_a,
		"hitsB": hits_b,
		"damageToA": snappedf(dmg_to_a, 0.1),
		"damageToB": snappedf(dmg_to_b, 0.1),
		"sunkA": sunk_a,
		"sunkB": sunk_b,
		"survivorsA": rem_a,
		"survivorsB": rem_b,
		"crewLostA": crew_before_a - crew_after_a,
		"crewLostB": crew_before_b - crew_after_b,
		"ammoUsedA": ammo_used_a,
		"ammoUsedB": ammo_used_b,
		"retreated": retreated,
		"winner": str(winner.get("id", "")),
		"lootCoins": loot_coins,
		"capturedGood": captured_good,
		"capturedQty": captured_qty,
		"summary": summary
	}
	if state.get("navalAi") is Dictionary:
		var nav_ai: Dictionary = state["navalAi"]
		if nav_ai.get("encounters") is Array:
			var enc_log: Array = nav_ai["encounters"]
			enc_log.push_front(ev)
			if enc_log.size() > MAX_EVENT_LOG:
				enc_log.resize(MAX_EVENT_LOG)
	return {"ok": true, "event": ev, "summary": summary}
