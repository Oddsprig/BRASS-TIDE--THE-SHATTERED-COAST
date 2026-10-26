extends RefCounted
## Funded NPC hull replacements: ready stock purchases, shipyard slip commissions, and collection (v0.013).
## Preloads NavalOrders and core damage/economy/money/construction scripts only (no preload cycles).

const Economy = preload("res://scripts/economy.gd")
const Goods = preload("res://scripts/goods.gd")
const Money = preload("res://scripts/money.gd")
const Construction = preload("res://scripts/construction.gd")
const Fleets = preload("res://scripts/fleet_economy.gd")
const NavalOrders = preload("res://scripts/naval_orders.gd")
const Lifecycle = preload("res://scripts/equipment_lifecycle.gd")

const MAX_SLIPS_PER_PORT: int = 2
const MAX_EVENT_LOG: int = 24


static func quote_at_port(h: Dictionary, port: Dictionary) -> Dictionary:
	var prices: Dictionary = {}
	if not port.is_empty():
		for good_var in Goods.ITEMS:
			var good: String = str(good_var)
			prices[good] = int(Economy.price(port, good))
	return Construction.quote(h, prices)


static func can_materials(port: Dictionary, materials: Dictionary) -> bool:
	var stocks: Dictionary = port.get("stocks", {}) if port.get("stocks") is Dictionary else {}
	for k_var in materials:
		var k: String = str(k_var)
		if float(stocks.get(k, 0.0)) + 1e-6 < float(materials.get(k, 0.0)):
			return false
	return true


static func consume_materials(port: Dictionary, materials: Dictionary) -> void:
	var stocks: Dictionary = port.get("stocks", {}) if port.get("stocks") is Dictionary else {}
	for k_var in materials:
		var k: String = str(k_var)
		stocks[k] = maxf(0.0, float(stocks.get(k, 0.0)) - float(materials.get(k, 0.0)))


static func owner_has_queued_replacement(state: Dictionary, owner_id: String) -> bool:
	if owner_id.is_empty():
		return false
	var ports: Array = state.get("ports", []) if state.get("ports") is Array else []
	for p_var in ports:
		if not (p_var is Dictionary):
			continue
		var p: Dictionary = p_var
		var queue: Array = p.get("buildQueue", []) if p.get("buildQueue") is Array else []
		for ord_var in queue:
			if ord_var is Dictionary:
				var ord: Dictionary = ord_var
				if str(ord.get("npcOwnerId", "")) == owner_id:
					return true
	return false


static func attach_new_boat(state: Dictionary, owner: Dictionary, port: Dictionary, h: Dictionary, crew_count: int, staged: Dictionary = {}, core = null) -> Dictionary:
	if staged.is_empty() or not bool(staged.get("ok", false)):
		return {}
	var was_empty: bool=NavalOrders.living_boats(owner).is_empty()
	var boats_arr: Array = owner.get("boats", []) if owner.get("boats") is Array else []
	var default_seq: int = boats_arr.size() + 1
	var seq: int = int(owner.get("nextBoatSeq", default_seq))
	var boat: Dictionary = Lifecycle.materialize(h, crew_count, staged, true)
	if core != null and core.has_method("fit_boat"):
		core.fit_boat(boat, true)
	boat.fuel = 0.0
	boat.ammo = 0.0
	boat.supplies = 0.0
	boat.crew = float(crew_count)
	boat["economySpecOwned"] = true
	boat["initialStores"] = {"fuel": 0.0, "ammo": 0.0, "supplies": 0.0}
	for i in range(boats_arr.size()):
		if boats_arr[i] is Dictionary:
			var existing: Dictionary = boats_arr[i]
			if bool(existing.get("sunk", false)):
				boats_arr.remove_at(i)
				break
	boats_arr.append(boat)
	owner["boats"] = boats_arr
	owner["nextBoatSeq"] = seq + 1
	owner["active"] = true
	owner["atPort"] = str(port.get("id", owner.get("homePort", "")))
	Fleets._performance(owner)
	Fleets.dock(owner, port)
	var pat: Dictionary = NavalOrders.find_patrol(state, str(owner.get("id", "")))
	if not pat.is_empty():
		pat["active"] = true
		if was_empty:
			pat.x=port.x;pat.y=port.y;pat.from=port.id;pat.to=port.id;pat.progress=0.0;pat.holding=true
			pat.course=[{"x":port.x,"y":port.y},{"x":port.x,"y":port.y}];pat.courseLength=0.0
	return boat


static func advance_unstepped_npc_orders(state: Dictionary, step_index: int, _total_days: int) -> void:
	if bool(state.get("yardsAdvancedThisDay",false)):return
	var nav_ai: Dictionary = state.get("navalAi", {}) if state.get("navalAi") is Dictionary else {}
	var cur_tick: int = int(nav_ai.get("tickCount", 0))
	var ports: Array = state.get("ports", []) if state.get("ports") is Array else []
	for p_var in ports:
		if not (p_var is Dictionary):
			continue
		var p: Dictionary = p_var
		if not (p.get("buildQueue") is Array):
			continue
		var queue: Array = p["buildQueue"]
		var need_begin: bool = true
		for ord_var in queue:
			if not (ord_var is Dictionary):
				continue
			var ord: Dictionary = ord_var
			if str(ord.get("npcOwnerId", "")).is_empty() or bool(ord.get("ready", false)):
				continue
			var cur_elapsed: float = float(ord.get("elapsedDays", 0.0))
			var last_elapsed: float = float(ord.get("_lastTickElapsed", -1.0))
			var booked_tick: int = int(ord.get("_bookedTick", -1))
			if cur_tick > booked_tick and is_equal_approx(cur_elapsed, last_elapsed):
				if need_begin:
					Construction.begin_day(p)
					need_begin = false
				Construction.advance(p, ord, 1.0)
			ord["_lastTickElapsed"] = float(ord.get("elapsedDays", 0.0))


static func collect_replacements(core, port: Dictionary = {}) -> Array:
	var state: Dictionary = NavalOrders.state_of(core)
	var world: Dictionary = NavalOrders.world_of(core)
	var all_ports: Array = state.get("ports", []) if state.get("ports") is Array else []
	var ports_to_check: Array = [port] if not port.is_empty() else all_ports
	var messages: Array = []
	for p_var in ports_to_check:
		if not (p_var is Dictionary):
			continue
		var p: Dictionary = p_var
		if not (p.get("buildQueue") is Array):
			continue
		var queue: Array = p["buildQueue"]
		var completed_orders: Array = []
		for ord_var in queue:
			if not (ord_var is Dictionary):
				continue
			var ord: Dictionary = ord_var
			var npc_id: String = str(ord.get("npcOwnerId", ""))
			if npc_id.is_empty():
				continue
			if not bool(ord.get("ready", false)) or int(ord.get("escrow", 0)) != 0:
				continue
			var owner: Dictionary = NavalOrders.find_owner(state, npc_id)
			if owner.is_empty() or NavalOrders.is_story_owner(owner):
				continue
			if not NavalOrders.living_boats(owner).is_empty() and str(owner.get("atPort",""))!=str(p.id):continue
			var hid: String = str(ord.get("hull", ord.get("hullId", "bilge_punt")))
			var h: Dictionary = NavalOrders.hull_spec(core, state, world, hid)
			if h.is_empty():continue
			var min_crew: int = maxi(1, int(h.get("crewMin", 2)))
			var opt_crew: int = maxi(min_crew, int(h.get("crewOptimal", min_crew)))
			var max_crew: int = maxi(opt_crew, int(h.get("crewMax", opt_crew + 2)))
			var avail_pool: int = mini(maxi(0, int(p.get("recruits", 0))), maxi(0, int(p.get("workforce", 0))))
			var owner_coins: int = int(owner.get("coins", 0))
			var opt_cost: int = int(Economy.recruit_cost(p, opt_crew))
			var min_cost: int = int(Economy.recruit_cost(p, min_crew))
			var hire_count: int = opt_crew if (avail_pool >= opt_crew and owner_coins >= opt_cost) else min_crew
			if avail_pool < min_crew or owner_coins < min_cost:
				continue
			var boats_now: Array = owner.get("boats", []) if owner.get("boats") is Array else []
			var seq_now: int = int(owner.get("nextBoatSeq", boats_now.size() + 1))
			var birth_uid := "%s-r%d" % [npc_id, seq_now]
			var staged: Dictionary = Lifecycle.stage_birth(state, world, h, birth_uid, {})
			if not staged.ok:
				continue
			if int(owner.get("nextBoatSeq", boats_now.size() + 1)) != seq_now:
				continue
			var wallet: Dictionary = {"coins": owner_coins, "crewPurse": int(owner.get("crewPurse", 0))}
			var hired: Dictionary = Economy.recruit(p, wallet, hire_count, max_crew)
			if not bool(hired.get("ok", false)):
				continue
			owner["coins"] = int(wallet.get("coins", 0))
			owner["crewPurse"] = int(wallet.get("crewPurse", 0))
			var boat: Dictionary = attach_new_boat(state, owner, p, h, int(hired.get("count", hire_count)), staged, core)
			completed_orders.append(ord)
			var msg: String = "%s collected completed %s at %s with %d recruited sailors." % [
				str(owner.get("name", npc_id)),
				str(boat.get("name", hid)),
				str(p.get("name", p.get("id", "harbor"))),
				int(boat.get("crew", 0))
			]
			Fleets._log(owner, msg)
			messages.append(msg)
			if state.get("navalAi") is Dictionary:
				var nav_ai: Dictionary = state["navalAi"]
				if nav_ai.get("replacements") is Array:
					var rep_log: Array = nav_ai["replacements"]
					rep_log.push_front({
						"day": int(state.get("econDay", 1)),
						"ownerId": npc_id,
						"portId": str(p.get("id", "")),
						"hull": hid,
						"mode": "collected",
						"crew": int(boat.get("crew", 0)),
						"crewCost": int(hired.get("cost", 0))
					})
					if rep_log.size() > MAX_EVENT_LOG:
						rep_log.resize(MAX_EVENT_LOG)
			NavalOrders.assign_post_dock_order(state, owner, p)
		for done_var in completed_orders:
			queue.erase(done_var)
	return messages


static func request_replacement(core, owner: Dictionary, port: Dictionary = {}, hull_id: String = "") -> Dictionary:
	if owner.get("playerCompany",false):return {"ok":false,"message":"Company losses need actual owned replacement hulls; no public subsidy or automatic respawn."}
	var state: Dictionary = NavalOrders.state_of(core)
	var world: Dictionary = NavalOrders.world_of(core)
	if owner.is_empty() or NavalOrders.is_story_owner(owner):
		return {"ok": false, "reason": "story_or_empty_owner"}
	Fleets.normalize_owner(owner)
	var owner_id: String = str(owner.get("id", ""))
	if owner_has_queued_replacement(state, owner_id):
		return {"ok": false, "reason": "one_replacement_at_a_time"}

	var p: Dictionary = port
	if p.is_empty():
		var port_id: String = str(owner.get("atPort", ""))
		if port_id.is_empty():
			port_id = str(owner.get("homePort", ""))
		p = NavalOrders.find_port(state, port_id)
	if p.is_empty():
		return {"ok": false, "reason": "no_harbor"}
	if str(p.id)!=str(owner.homePort):return {"ok":false,"reason":"replacement_needs_home_yard"}
	if not NavalOrders.living_boats(owner).is_empty() and str(owner.get("atPort",""))!=str(p.id):return {"ok":false,"reason":"survivors_must_reach_yard"}

	var candidate_ids: Array = []
	if not hull_id.is_empty():
		candidate_ids.append(hull_id)
	else:
		var civilians: Array=Fleets.civilian_hulls(p,str(owner.get("kind","")),world,int(owner_id.trim_prefix("patrol-"))) if owner_id.begins_with("patrol-") else []
		var prefs: Array = owner.get("preferredHulls", []) if owner.get("preferredHulls") is Array else []
		if not civilians.is_empty():prefs=civilians
		for pref_var in prefs:
			var pref_str: String = str(pref_var)
			if not pref_str.is_empty() and not (pref_str in candidate_ids):
				candidate_ids.append(pref_str)
		var sids: Array = p.get("shipIds", []) if civilians.is_empty() and p.get("shipIds") is Array else []
		for sid_var in sids:
			var sid_str: String = str(sid_var)
			if not sid_str.is_empty() and not (sid_str in candidate_ids):
				candidate_ids.append(sid_str)
		if candidate_ids.is_empty():
			candidate_ids.append("bilge_punt")

	var last_reason: String = "insufficient_funds_or_stock"
	var ship_stock: Dictionary = p.get("shipStock", {}) if p.get("shipStock") is Dictionary else {}
	var m_log: Array = state.get("moneyLog", []) if state.get("moneyLog") is Array else []

	# 1. Ready hull purchase from port.shipStock (atomic check of hull price + crew recruitment).
	for cid_var in candidate_ids:
		var cid: String = str(cid_var)
		if int(ship_stock.get(cid, 0)) <= 0:
			continue
		var h: Dictionary = NavalOrders.hull_spec(core, state, world, cid)
		var q: Dictionary = quote_at_port(h, p)
		var price: int = int(q.get("readyPrice", 0))
		if h.is_empty():continue
		var min_crew: int = maxi(1, int(h.get("crewMin", 2)))
		var opt_crew: int = maxi(min_crew, int(h.get("crewOptimal", min_crew)))
		var max_crew: int = maxi(opt_crew, int(h.get("crewMax", opt_crew + 2)))
		var avail_pool: int = mini(maxi(0, int(p.get("recruits", 0))), maxi(0, int(p.get("workforce", 0))))
		if avail_pool < min_crew:
			last_reason = "insufficient_recruits"
			continue
		var owner_coins: int = int(owner.get("coins", 0))
		var opt_cost: int = int(Economy.recruit_cost(p, opt_crew))
		var hire_count: int = opt_crew if (avail_pool >= opt_crew and owner_coins >= price + opt_cost) else min_crew
		var hire_cost: int = int(Economy.recruit_cost(p, hire_count))
		if owner_coins < price + hire_cost:
			last_reason = "insufficient_coins_for_ready_hull_and_crew"
			continue
		var probe_wallet: Dictionary = {"coins": owner_coins - price, "crewPurse": int(owner.get("crewPurse", 0))}
		var probe_hire: Dictionary = Economy.recruit(p.duplicate(true), probe_wallet, hire_count, max_crew)
		if not bool(probe_hire.get("ok", false)):
			last_reason = "recruit_preflight_failed"
			continue
		var boats_now: Array = owner.get("boats", []) if owner.get("boats") is Array else []
		var seq_now: int = int(owner.get("nextBoatSeq", boats_now.size() + 1))
		var birth_uid := "%s-r%d" % [owner_id, seq_now]
		var staged: Dictionary = Lifecycle.stage_birth(state, world, h, birth_uid, {})
		if not staged.ok:
			last_reason = "equipment_birth_refused"
			continue
		if int(owner.get("nextBoatSeq", boats_now.size() + 1)) != seq_now:
			last_reason = "equipment_birth_refused"
			continue

		var tax: int = mini(price, int(q.get("tax", 0)) + int(q.get("readyStorageTax", 0)))
		Money.move(owner, "coins", p, "cash", price - tax, "NPC ready hull purchase", m_log)
		Money.move(owner, "coins", p, "governmentPurse", tax, "NPC hull sales duty", m_log)
		ship_stock[cid] = maxi(0, int(ship_stock.get(cid, 0)) - 1)
		p["shipStock"] = ship_stock

		var wallet: Dictionary = {"coins": int(owner.get("coins", 0)), "crewPurse": int(owner.get("crewPurse", 0))}
		var hired: Dictionary = Economy.recruit(p, wallet, hire_count, max_crew)
		owner["coins"] = int(wallet.get("coins", 0))
		owner["crewPurse"] = int(wallet.get("crewPurse", 0))
		var boat: Dictionary = attach_new_boat(state, owner, p, h, int(hired.get("count", hire_count)), staged, core)
		var msg: String = "%s purchased ready %s at %s (%d coins + %d crew advance)." % [
			str(owner.get("name", owner_id)),
			str(boat.get("name", cid)),
			str(p.get("name", p.get("id", "harbor"))),
			price,
			int(hired.get("cost", hire_cost))
		]
		Fleets._log(owner, msg)
		if state.get("navalAi") is Dictionary:
			var nav_ai: Dictionary = state["navalAi"]
			if nav_ai.get("replacements") is Array:
				var rep_log: Array = nav_ai["replacements"]
				rep_log.push_front({
					"day": int(state.get("econDay", 1)),
					"ownerId": owner_id,
					"portId": str(p.get("id", "")),
					"hull": cid,
					"mode": "stock",
					"price": price,
					"crew": int(boat.get("crew", 0)),
					"crewCost": int(hired.get("cost", hire_cost))
				})
				if rep_log.size() > MAX_EVENT_LOG:
					rep_log.resize(MAX_EVENT_LOG)
		NavalOrders.assign_post_dock_order(state, owner, p)
		return {"ok": true, "mode": "stock", "hull": cid, "boat": boat, "price": price, "crew": int(boat.get("crew", 0)), "message": msg}

	# 2. Funded Construction.make_order on p.buildQueue (max 2 slips).
	if not (p.get("buildQueue") is Array):
		p["buildQueue"] = []
	var queue: Array = p["buildQueue"]
	if queue.size() >= MAX_SLIPS_PER_PORT:
		return {"ok": false, "reason": "slips_full"}

	var port_ship_ids: Array = p.get("shipIds", []) if p.get("shipIds") is Array else []
	# The same faction civilian drawings as Harbor.catalogue, without creating
	# ready stock. All existing material, workforce and purse checks still run.
	port_ship_ids=port_ship_ids.duplicate()
	for h in world.get("HULLS",[]):
		if h.get("civilianRole","") in ["fishing","transport","tanker","yacht"] and h.get("faction","")==p.get("faction","") and not h.id in port_ship_ids:port_ship_ids.append(h.id)
	var nav_ai_d: Dictionary = state.get("navalAi", {}) if state.get("navalAi") is Dictionary else {}
	for cid_var in candidate_ids:
		var cid: String = str(cid_var)
		if not port_ship_ids.is_empty() and not (cid in port_ship_ids):
			last_reason = "hull_not_built_at_port"
			continue
		var h: Dictionary = NavalOrders.hull_spec(core, state, world, cid)
		var q: Dictionary = quote_at_port(h, p)
		var commission_price: int = int(q.get("commissionPrice", q.get("total", 0)))
		var owner_coins: int = int(owner.get("coins", 0))
		if owner_coins < commission_price:
			last_reason = "insufficient_coins_for_commission"
			continue
		var mats: Dictionary = q.get("materials", {}) if q.get("materials") is Dictionary else {}
		if not can_materials(p, mats):
			last_reason = "insufficient_port_materials"
			continue
		var order: Dictionary = Construction.make_order(h, q, "yard")
		order["id"] = "order_%s_%s" % [cid, owner_id]
		order["npcOwnerId"] = owner_id
		order["fundingSource"] = "npc"
		order["_bookedTick"] = int(nav_ai_d.get("tickCount", 0))
		order["_lastTickElapsed"] = 0.0
		var wages: int = int(order.get("escrow", 0))
		var tax: int = int(q.get("tax", 0))
		if wages + tax > commission_price:
			last_reason = "quote_reconciliation_failed"
			continue

		consume_materials(p, mats)
		Money.move(owner, "coins", p, "cash", commission_price - wages - tax, "NPC hull commission materials and yard margin", m_log)
		Money.move(owner, "coins", p, "governmentPurse", tax, "NPC hull commission registry duty", m_log)
		owner["coins"] = int(owner.get("coins", 0)) - wages
		order["escrow"] = wages
		queue.append(order)

		var msg: String = "%s commissioned %s at %s (%d coins, %d wage escrow)." % [
			str(owner.get("name", owner_id)),
			str(h.get("name", cid)),
			str(p.get("name", p.get("id", "harbor"))),
			commission_price,
			wages
		]
		Fleets._log(owner, msg)
		NavalOrders.build_order(state, owner, "replace", str(p.get("id", "")), msg)
		if nav_ai_d.get("replacements") is Array:
			var rep_log: Array = nav_ai_d["replacements"]
			rep_log.push_front({
				"day": int(state.get("econDay", 1)),
				"ownerId": owner_id,
				"portId": str(p.get("id", "")),
				"hull": cid,
				"mode": "commission",
				"price": commission_price,
				"escrow": wages,
				"orderId": str(order.get("id", ""))
			})
			if rep_log.size() > MAX_EVENT_LOG:
				rep_log.resize(MAX_EVENT_LOG)
		return {"ok": true, "mode": "commission", "hull": cid, "order": order, "price": commission_price, "escrow": wages, "message": msg}

	return {"ok": false, "reason": last_reason}
