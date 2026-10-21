extends SceneTree
## Native headless test suite for v0.013 NavalAI coordinator and sub-modules
## (naval_ai.gd, naval_orders.gd, naval_combat.gd, naval_replacements.gd).

const Campaign = preload("res://scripts/campaign.gd")
const NavalAI = preload("res://scripts/naval_ai.gd")
const NavalOrders = preload("res://scripts/naval_orders.gd")
const NavalCombat = preload("res://scripts/naval_combat.gd")
const NavalReplacements = preload("res://scripts/naval_replacements.gd")
const Economy = preload("res://scripts/economy.gd")
const Fleets = preload("res://scripts/fleet_economy.gd")
const Construction = preload("res://scripts/construction.gd")
const Money = preload("res://scripts/money.gd")
const Goods = preload("res://scripts/goods.gd")
const SaveValidation = preload("res://scripts/save_validation.gd")

var failures: Array = []
var checks: int = 0
var world: Dictionary = {}
var c


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		var stack: Array = get_stack()
		var line_num: String = "0"
		if stack.size() > 1 and stack[1] is Dictionary:
			var frame: Dictionary = stack[1]
			line_num = str(frame.get("line", 0))
		var where: String = "test_naval_ai.gd:%s" % line_num if stack.size() > 1 else "test_naval_ai.gd"
		var line: String = where + " — " + message
		failures.append(line)
		print("FAIL " + line)


func reset_campaign(seed_val: int = 42) -> void:
	c = Campaign.new(world)
	c.new_game(seed_val)
	var st: Dictionary = c.state
	NavalAI.ensure(st, world)


func same_data(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for k in da:
			if not db.has(k) or not same_data(da[k], db[k]):
				return false
		return true
	if a is Array and b is Array:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return false
		for i in range(aa.size()):
			if not same_data(aa[i], ab[i]):
				return false
		return true
	return a == b


func _initialize() -> void:
	var started_ms: int = Time.get_ticks_msec()
	var parsed_world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	world = parsed_world if parsed_world is Dictionary else {}
	_test_ensure_and_orders()
	_test_absent_player_skirmish_and_story_exclusion()
	_test_unfunded_replacement_refuses_atomically()
	_test_funded_stock_and_build_replacement()
	_test_json_roundtrip_and_bounded_work()
	var elapsed_ms: int = Time.get_ticks_msec() - started_ms
	print("naval_ai: %d checks, %d failures, %d ms" % [checks, failures.size(), elapsed_ms])
	if not failures.is_empty():
		quit(1)
		assert(failures.is_empty(), "NavalAI unit test failures above")
	else:
		quit(0)


func _test_ensure_and_orders() -> void:
	reset_campaign(101)
	var st: Dictionary = c.state
	check(st.get("navalAi") is Dictionary, "NavalAI.ensure initializes state.navalAi")
	var patrol_count: int = 0
	var trader_count: int = 0
	var raider_count: int = 0
	var story_count: int = 0

	var owners: Array = st.get("fleetOwners", []) if st.get("fleetOwners") is Array else []
	for owner_var in owners:
		var owner: Dictionary = owner_var
		var owner_id: String = str(owner.get("id", ""))
		var ord: Dictionary = owner.get("order", {}) if owner.get("order") is Dictionary else {}
		check(not ord.is_empty(), "Owner %s has active order dictionary" % owner_id)
		check(not str(ord.get("purpose", "")).is_empty(), "Order for %s has purpose" % owner_id)
		check(not c.port(str(ord.get("destination", ""))).is_empty(), "Order for %s has valid destination port" % owner_id)
		check(not str(ord.get("reason", "")).is_empty(), "Order for %s has human-readable reason" % owner_id)
		var res: Dictionary = ord.get("reserves", {}) if ord.get("reserves") is Dictionary else {}
		var perf: Dictionary = ord.get("performance", {}) if ord.get("performance") is Dictionary else {}
		check(not res.is_empty() and not perf.is_empty(), "Order for %s carries reserves and performance" % owner_id)
		check(is_finite(float(res.get("fuel", NAN))) and float(res.get("fuel", -1.0)) >= 0.0, "Order reserves fuel finite for %s" % owner_id)
		check(is_finite(float(res.get("ammo", NAN))) and float(res.get("ammo", -1.0)) >= 0.0, "Order reserves ammo finite for %s" % owner_id)
		check(is_finite(float(perf.get("speed", NAN))) and float(perf.get("speed", -1.0)) > 0.0, "Order performance speed positive for %s" % owner_id)
		var kind_str: String = str(owner.get("kind", ""))
		if NavalOrders.is_story_owner(owner):
			story_count += 1
			check(str(ord.get("purpose", "")) == "blockade", "Story owner %s keeps blockade purpose" % owner_id)
		elif kind_str == "patrol":
			patrol_count += 1
		elif kind_str == "trader":
			trader_count += 1
		elif kind_str == "raider":
			raider_count += 1

	check(patrol_count == 3 and trader_count == 3 and raider_count == 3 and story_count == 8, "Existing patrol/trader/raider/story owners classified")

	# Trader picks real stock/demand destination; raider seeks loaded convoy; patrol intercepts or escorts.
	var trader: Dictionary = c.fleet_owner("patrol-1")
	var trader_home: Dictionary = c.port(str(trader.get("homePort", "")))
	var trader_home_id: String = str(trader_home.get("id", ""))
	trader["tradeGood"] = "timber"
	var trader_cargo: Dictionary = trader.get("cargo", {}) if trader.get("cargo") is Dictionary else {}
	trader_cargo["timber"] = 18.0
	trader["tradeCargo"] = 18.0

	var hungry_port: Dictionary = {}
	var ports: Array = st.get("ports", []) if st.get("ports") is Array else []
	for p_var in ports:
		var p: Dictionary = p_var
		if str(p.get("id", "")) != trader_home_id and str(p.get("faction", "")) != "raiders":
			var p_stocks: Dictionary = p.get("stocks", {}) if p.get("stocks") is Dictionary else {}
			p_stocks["timber"] = 500.0
			if hungry_port.is_empty():
				hungry_port = p
	var hungry_stocks: Dictionary = hungry_port.get("stocks", {}) if hungry_port.get("stocks") is Dictionary else {}
	hungry_stocks["timber"] = 0.0
	Money.move(hungry_port,"governmentPurse",hungry_port,"cash",mini(500000,int(hungry_port.governmentPurse)),"Fixture buyer liquidity transfer",st.moneyLog)
	var next_trader_port: String = NavalAI.arrived(c, trader, trader_home)
	var trader_ord: Dictionary = trader.get("order", {}) if trader.get("order") is Dictionary else {}
	check(next_trader_port == str(hungry_port.get("id", "")) and str(trader_ord.get("purpose", "")) == "deliver", "Loaded trader selects scarce high-demand port for delivery")

	var raider: Dictionary = c.fleet_owner("patrol-0")
	var raider_home: Dictionary = c.port(str(raider.get("homePort", "")))
	for other in st.fleetOwners:
		if other.kind=="trader" and other.id!=trader.id:
			other.active=false # isolate the one convoy this unit scenario is about
			other.cargo[other.tradeGood]=maxf(0,float(other.cargo.get(other.tradeGood,0))-float(other.tradeCargo))
			other.tradeCargo=0
	var next_raider_port: String = NavalAI.arrived(c, raider, raider_home)
	var raider_ord: Dictionary = raider.get("order", {}) if raider.get("order") is Dictionary else {}
	check(str(raider_ord.get("purpose", "")) == "raid" and not next_raider_port.is_empty(), "Raider selects raid order seeking loaded convoys")
	print("raider selection: ",raider_ord.get("targetOwnerId","")," wanted ",trader.id," reason ",raider_ord.get("reason",""))
	check(str(raider_ord.get("targetOwnerId", "")) == str(trader.get("id", "")), "Raider targets the loaded trader convoy")

	var pat_owner: Dictionary = c.fleet_owner("patrol-2")
	var pat_home: Dictionary = c.port(str(pat_owner.get("homePort", "")))
	var next_pat_port: String = NavalAI.arrived(c, pat_owner, pat_home)
	var pat_ord: Dictionary = pat_owner.get("order", {}) if pat_owner.get("order") is Dictionary else {}
	check(str(pat_ord.get("purpose", "")) in ["intercept", "escort"] and not next_pat_port.is_empty(), "Patrol selects intercept or escort order")

	# Damaged crew at a foreign port returns home.
	var foreign_port: Dictionary = hungry_port
	pat_owner["atPort"] = str(foreign_port.get("id", ""))
	var pat_boats: Array = pat_owner.get("boats", []) if pat_owner.get("boats") is Array else []
	var b0: Dictionary = pat_boats[0]
	b0["hp"] = float(b0.get("maxHp", 100.0)) * 0.35
	b0["engine"] = 0.45
	var retreat_dest: String = NavalAI.arrived(c, pat_owner, foreign_port)
	var pat_ret_ord: Dictionary = pat_owner.get("order", {}) if pat_owner.get("order") is Dictionary else {}
	check(retreat_dest == str(pat_owner.get("homePort", "")) and str(pat_ret_ord.get("purpose", "")) in ["repair", "withdraw"], "Damaged fleet at foreign port orders return to homePort")
	check(int(Money.total(st)) == int(st.get("coinSupply", 0)), "Order selection conserves global coins")


func _test_absent_player_skirmish_and_story_exclusion() -> void:
	reset_campaign(202)
	var st: Dictionary = c.state
	var start_d: Dictionary = world.get("START", {}) if world.get("START") is Dictionary else {}
	st["position"] = c.port_position(str(start_d.get("port", "")))
	st["path"] = []

	var raider_owner: Dictionary = c.fleet_owner("patrol-3")
	var patrol_owner: Dictionary = c.fleet_owner("patrol-5")
	var story_owner: Dictionary = c.fleet_owner("story-0")
	var pat_raider: Dictionary = NavalOrders.find_patrol(st, "patrol-3")
	var pat_guard: Dictionary = NavalOrders.find_patrol(st, "patrol-5")

	var patrols: Array = st.get("patrols", []) if st.get("patrols") is Array else []
	for p_var in patrols:
		var p: Dictionary = p_var
		p["x"] = 500.0+float(patrols.find(p))*700.0
		p["y"] = 250.0
	pat_raider["x"] = 4200.0
	pat_raider["y"] = 3100.0
	pat_guard["x"] = 4230.0
	pat_guard["y"] = 3110.0

	var combatants: Array = [raider_owner, patrol_owner]
	for own_var in combatants:
		var own: Dictionary = own_var
		var own_boats: Array = own.get("boats", []) if own.get("boats") is Array else []
		for b_var in own_boats:
			var b: Dictionary = b_var
			b["ammo"] = 80.0
			b["supplies"] = 6.0
			b["fuel"] = 20.0
			b["hp"] = float(b.get("maxHp", 100.0))
			b["engine"] = 1.0

	var story_before: Dictionary = story_owner.duplicate(true)
	var ammo_before: float = 0.0
	var hp_before: float = 0.0
	for own_var in combatants:
		var own: Dictionary = own_var
		var own_boats: Array = own.get("boats", []) if own.get("boats") is Array else []
		for b_var in own_boats:
			var b: Dictionary = b_var
			ammo_before += float(b.get("ammo", 0.0))
			hp_before += float(b.get("hp", 0.0))

	var msgs: Array = NavalAI.tick(c, 1)
	check(not msgs.is_empty(), "Absent-player NPC skirmish produces event message")
	var nav_ai: Dictionary = st.get("navalAi", {}) if st.get("navalAi") is Dictionary else {}
	var enc_list: Array = nav_ai.get("encounters", []) if nav_ai.get("encounters") is Array else []
	check(enc_list.size() == 1, "Exactly one bounded encounter recorded")

	var ev: Dictionary = enc_list[0] if not enc_list.is_empty() else {}
	check(int(ev.get("shotsA", 0)) + int(ev.get("shotsB", 0)) > 0, "Encounter fires actual shots")

	var ammo_after: float = 0.0
	var hp_after: float = 0.0
	for own_var in combatants:
		var own: Dictionary = own_var
		var own_boats: Array = own.get("boats", []) if own.get("boats") is Array else []
		for b_var in own_boats:
			var b: Dictionary = b_var
			ammo_after += float(b.get("ammo", 0.0))
			hp_after += float(b.get("hp", 0.0))

	check(ammo_after < ammo_before, "Skirmish spends persistent NPC boat ammunition")
	check(hp_after < hp_before, "Skirmish inflicts persistent hull damage or sinking")
	var r_ord: Dictionary = raider_owner.get("order", {}) if raider_owner.get("order") is Dictionary else {}
	var p_ord: Dictionary = patrol_owner.get("order", {}) if patrol_owner.get("order") is Dictionary else {}
	check(
		str(r_ord.get("purpose", "")) in ["withdraw", "repair", "replace", "raid"]
		and str(p_ord.get("purpose", "")) in ["withdraw", "repair", "replace", "patrol", "intercept", "escort"],
		"Post-skirmish orders reflect outcome or withdrawal"
	)
	check(same_data(story_owner.get("boats", []), story_before.get("boats", [])) and bool(story_owner.get("active", false)) == true, "Story blockade owner excluded from automatic fights")
	check(int(Money.total(st)) == int(st.get("coinSupply", 0)), "Skirmish and prize capture conserve global coins")


func _test_unfunded_replacement_refuses_atomically() -> void:
	reset_campaign(303)
	var st: Dictionary = c.state
	var m_log: Array = st.get("moneyLog", []) if st.get("moneyLog") is Array else []
	var owner: Dictionary = c.fleet_owner("patrol-0")
	var home: Dictionary = c.port(str(owner.get("homePort", "")))
	owner["atPort"] = str(home.get("id", ""))
	var o_boats: Array = owner.get("boats", []) if owner.get("boats") is Array else []
	var ob0: Dictionary = o_boats[0]
	ob0["sunk"] = true
	ob0["hp"] = 0.0
	ob0["crew"] = 0.0

	# 1. Ready stock available, but owner has 0 coins.
	Money.move(owner, "coins", home, "governmentPurse", int(owner.get("coins", 0)), "Drain owner purse for unfunded test", m_log)
	var ship_stock: Dictionary = home.get("shipStock", {}) if home.get("shipStock") is Dictionary else {}
	ship_stock["bilge_punt"] = 1
	var snap_owner: Dictionary = owner.duplicate(true)
	var snap_port: Dictionary = home.duplicate(true)
	var res_unfunded_stock: Dictionary = NavalReplacements.request_replacement(c, owner, home, "bilge_punt")
	check(not bool(res_unfunded_stock.get("ok", false)), "Unfunded ready stock replacement refused")
	check(same_data(owner.get("coins", 0), snap_owner.get("coins", 0)) and same_data(home.get("shipStock", {}), snap_port.get("shipStock", {})) and same_data(home.get("recruits", 0), snap_port.get("recruits", 0)), "Unfunded ready stock refusal is atomic")
	check(int(Money.total(st)) == int(st.get("coinSupply", 0)), "Unfunded ready stock check conserves coins")

	# 2. No ready stock; commission requested without sufficient coins.
	ship_stock["bilge_punt"] = 0
	home["buildQueue"] = []
	if not "bilge_punt" in home.shipIds:home.shipIds.append("bilge_punt")
	var h: Dictionary = c.hull("bilge_punt")
	var q: Dictionary = NavalReplacements.quote_at_port(h, home)
	var q_mats: Dictionary = q.get("materials", {}) if q.get("materials") is Dictionary else {}
	var h_stocks: Dictionary = home.get("stocks", {}) if home.get("stocks") is Dictionary else {}
	for mat_var in q_mats:
		var mat: String = str(mat_var)
		h_stocks[mat] = float(q_mats.get(mat, 0.0)) + 10.0
	q=NavalReplacements.quote_at_port(h,home)
	var comm_price: int = int(q.get("commissionPrice", 0))
	Money.move(home, "governmentPurse", owner, "coins", comm_price - 10, "Partial coins below commission price", m_log)
	snap_owner = owner.duplicate(true)
	snap_port = home.duplicate(true)
	var res_unfunded_comm: Dictionary = NavalReplacements.request_replacement(c, owner, home, "bilge_punt")
	check(not bool(res_unfunded_comm.get("ok", false)), "Underfunded commission replacement refused")
	var h_queue: Array = home.get("buildQueue", []) if home.get("buildQueue") is Array else []
	check(h_queue.is_empty() and same_data(home.get("stocks", {}), snap_port.get("stocks", {})) and int(owner.get("coins", 0)) == int(snap_owner.get("coins", 0)), "Underfunded commission leaves stocks, slip, and purse untouched")

	# 3. Funded owner, but port lacks physical materials.
	Money.move(home, "governmentPurse", owner, "coins", 25000, "Fund owner for material shortage test", m_log)
	h_stocks["engines"] = 0.0
	snap_owner = owner.duplicate(true)
	snap_port = home.duplicate(true)
	var res_no_mat: Dictionary = NavalReplacements.request_replacement(c, owner, home, "bilge_punt")
	check(not bool(res_no_mat.get("ok", false)) and str(res_no_mat.get("reason", "")) == "insufficient_port_materials", "Missing yard materials refuses commission")
	h_queue = home.get("buildQueue", []) if home.get("buildQueue") is Array else []
	check(h_queue.is_empty() and int(owner.get("coins", 0)) == int(snap_owner.get("coins", 0)) and same_data(home.get("stocks", {}), snap_port.get("stocks", {})), "Missing materials refusal is atomic")

	# 4. Funded owner and materials present, but both building slips (max 2) are occupied.
	for mat_var in q_mats:
		var mat: String = str(mat_var)
		h_stocks[mat] = float(q_mats.get(mat, 0.0)) + 10.0
	var dummy_a: Dictionary = Construction.make_order(h, q, "yard")
	var dummy_b: Dictionary = Construction.make_order(h, q, "yard")
	dummy_a["escrow"] = 0
	dummy_b["escrow"] = 0
	home["buildQueue"] = [dummy_a, dummy_b]
	snap_owner = owner.duplicate(true)
	var res_full_slips: Dictionary = NavalReplacements.request_replacement(c, owner, home, "bilge_punt")
	check(not bool(res_full_slips.get("ok", false)) and str(res_full_slips.get("reason", "")) == "slips_full", "Port buildQueue max 2 enforced")
	h_queue = home.get("buildQueue", []) if home.get("buildQueue") is Array else []
	check(h_queue.size() == 2 and int(owner.get("coins", 0)) == int(snap_owner.get("coins", 0)), "Full slip refusal is atomic")
	home["buildQueue"] = []
	check(int(Money.total(st)) == int(st.get("coinSupply", 0)), "All refusal paths conserve global coins")


func _test_funded_stock_and_build_replacement() -> void:
	reset_campaign(404)
	var st: Dictionary = c.state
	var m_log: Array = st.get("moneyLog", []) if st.get("moneyLog") is Array else []
	# Part A: Ready stock replacement purchase + crew recruitment + Fleets.dock store purchases.
	var owner: Dictionary = c.fleet_owner("patrol-0")
	var home: Dictionary = c.port(str(owner.get("homePort", "")))
	owner["atPort"] = str(home.get("id", ""))
	var o_boats: Array = owner.get("boats", []) if owner.get("boats") is Array else []
	var ob0: Dictionary = o_boats[0]
	ob0["sunk"] = true
	ob0["hp"] = 0.0
	ob0["crew"] = 0.0

	var sids: Array = home.get("shipIds", []) if home.get("shipIds") is Array else []
	if not ("bilge_punt" in sids):
		sids.append("bilge_punt")
	var ship_stock: Dictionary = home.get("shipStock", {}) if home.get("shipStock") is Dictionary else {}
	ship_stock["bilge_punt"] = 1
	home["recruits"] = maxi(12, int(home.get("recruits", 0)))
	home["workforce"] = maxi(40, int(home.get("workforce", 0)))
	Economy.sync_workforce(home)
	var h_stocks: Dictionary = home.get("stocks", {}) if home.get("stocks") is Dictionary else {}
	h_stocks["fuel"] = 50.0
	h_stocks["supplies"] = 50.0
	h_stocks["ammo"] = 50.0
	h_stocks["food"] = 50.0
	Money.move(home, "governmentPurse", owner, "coins", 60000, "Fund NPC ready stock replacement", m_log)

	var recruits_before: int = int(home.get("recruits", 0))
	var wf_before: int = int(home.get("workforce", 0))
	var fuel_stock_before: float = float(h_stocks.get("fuel", 0.0))
	var ammo_stock_before: float = float(h_stocks.get("ammo", 0.0))
	var sup_stock_before: float = float(h_stocks.get("supplies", 0.0))

	var stock_rep: Dictionary = NavalAI.request_replacement(c, owner, home, "bilge_punt")
	check(bool(stock_rep.get("ok", false)) and str(stock_rep.get("mode", "")) == "stock", "Funded ready stock replacement succeeds")
	check(int(ship_stock.get("bilge_punt", 0)) == 0, "Ready hull removed from port shipStock")
	var new_boat: Dictionary = stock_rep.get("boat", {}) if stock_rep.get("boat") is Dictionary else {}
	var hired_crew: int = int(new_boat.get("crew", 0))
	check(hired_crew >= int(new_boat.get("crewMin", 2)), "New replacement hull has valid recruited crew")
	check(int(home.get("recruits", 0)) == recruits_before - hired_crew and int(home.get("workforce", 0)) == wf_before - hired_crew, "Recruited sailors removed from port recruits and workforce")
	check(same_data(new_boat.get("initialStores", {}), {"fuel": 0.0, "ammo": 0.0, "supplies": 0.0}), "New hull created with zero initial stores before dock purchase")
	check(float(new_boat.get("fuel", 0.0)) > 0.0 and float(new_boat.get("ammo", 0.0)) >= 50.0 and float(new_boat.get("supplies", 0.0)) > 0.0, "Fleets.dock buys working stores for replacement hull")
	check(float(h_stocks.get("fuel", 0.0)) < fuel_stock_before and float(h_stocks.get("ammo", 0.0)) < ammo_stock_before and float(h_stocks.get("supplies", 0.0)) < sup_stock_before, "Working stores deducted from port stocks")
	check(int(Money.total(st)) == int(st.get("coinSupply", 0)), "Ready stock replacement + crew + stores conserves global coins")

	# Part B: Funded Construction.make_order with order.npcOwnerId, slip progression, and collection.
	o_boats = owner.get("boats", []) if owner.get("boats") is Array else []
	var cur_b0: Dictionary = o_boats[0]
	cur_b0["sunk"] = true
	cur_b0["hp"] = 0.0
	cur_b0["crew"] = 0.0
	ship_stock["bilge_punt"] = 0
	home["buildQueue"] = []
	var h: Dictionary = c.hull("bilge_punt")
	var q: Dictionary = NavalReplacements.quote_at_port(h, home)
	var q_mats: Dictionary = q.get("materials", {}) if q.get("materials") is Dictionary else {}
	for mat_var in q_mats:
		var mat: String = str(mat_var)
		h_stocks[mat] = float(q_mats.get(mat, 0.0)) + 25.0
	var mat_before: Dictionary = h_stocks.duplicate(true)
	var comm_price: int = int(q.get("commissionPrice", 0))
	Money.move(home, "governmentPurse", owner, "coins", comm_price + 25000, "Fund NPC slip construction", m_log)

	var comm_rep: Dictionary = NavalAI.request_replacement(c, owner, home, "bilge_punt")
	check(bool(comm_rep.get("ok", false)) and str(comm_rep.get("mode", "")) == "commission", "Funded NPC commission books order on slip")
	var h_queue: Array = home.get("buildQueue", []) if home.get("buildQueue") is Array else []
	check(h_queue.size() == 1, "Order placed in port.buildQueue")
	var ord: Dictionary = h_queue[0] if not h_queue.is_empty() else {}
	check(str(ord.get("npcOwnerId", "")) == str(owner.get("id", "")) and int(ord.get("escrow", 0)) == int(q.get("escrow", 0)), "Order carries npcOwnerId and full ordinary+expert wage escrow")
	for mat_var in q_mats:
		var mat: String = str(mat_var)
		check(is_equal_approx(float(h_stocks.get(mat, 0.0)), float(mat_before.get(mat, 0.0)) - float(q_mats.get(mat, 0.0))), "Commission consumes port material " + mat)
	check(int(Money.total(st)) == int(st.get("coinSupply", 0)), "Commission escrow counted by Money.total")

	# One replacement per owner at a time guard.
	var dup_rep: Dictionary = NavalAI.request_replacement(c, owner, home, "bilge_punt")
	check(not bool(dup_rep.get("ok", false)) and str(dup_rep.get("reason", "")) == "one_replacement_at_a_time", "Owner cannot book a second replacement while one is queued")

	# Advance days until the slip order completes and NavalAI.tick collects it.
	var hh_before: int = int(home.get("householdPurse", 0))
	var exp_before: int = int(home.get("expertPurse", 0))
	var rec_before_collect: int = int(home.get("recruits", 0))
	var collected: bool = false
	for _day in range(18):
		NavalAI.tick(c, 1)
		check(int(Money.total(st)) == int(st.get("coinSupply", 0)), "Daily slip advance and collection conserve global coins")
		var q_now: Array = home.get("buildQueue", []) if home.get("buildQueue") is Array else []
		if q_now.is_empty() and NavalOrders.living_boats(owner).size() == 1:
			collected = true
			break

	check(collected, "Completed NPC order on slip is collected by NavalAI.tick")
	check(int(home.get("householdPurse", 0)) > hh_before and int(home.get("expertPurse", 0)) > exp_before, "Ordinary and expert slip wages paid from escrow into port purses")
	check(int(home.get("recruits", 0)) < rec_before_collect, "Collecting completed hull recruits finite sailors from port")
	var alive_boats: Array = NavalOrders.living_boats(owner)
	var built_boat: Dictionary = alive_boats[0] if not alive_boats.is_empty() else {}
	check(float(built_boat.get("fuel", 0.0)) > 0.0 and float(built_boat.get("ammo", 0.0)) >= 50.0, "Collected hull stocked via Fleets.dock")


func _test_json_roundtrip_and_bounded_work() -> void:
	reset_campaign(505)
	var st: Dictionary = c.state
	var m_log: Array = st.get("moneyLog", []) if st.get("moneyLog") is Array else []
	var owner: Dictionary = c.fleet_owner("patrol-6")
	var home: Dictionary = c.port(str(owner.get("homePort", "")))
	owner["atPort"] = str(home.get("id", ""))
	var o_boats: Array = owner.get("boats", []) if owner.get("boats") is Array else []
	var ob0: Dictionary = o_boats[0]
	ob0["sunk"] = true
	ob0["hp"] = 0.0
	ob0["crew"] = 0.0
	var sids: Array = home.get("shipIds", []) if home.get("shipIds") is Array else []
	if not ("bilge_punt" in sids):
		sids.append("bilge_punt")
	var ship_stock: Dictionary = home.get("shipStock", {}) if home.get("shipStock") is Dictionary else {}
	ship_stock["bilge_punt"] = 0
	var h: Dictionary = c.hull("bilge_punt")
	var q: Dictionary = NavalReplacements.quote_at_port(h, home)
	var q_mats: Dictionary = q.get("materials", {}) if q.get("materials") is Dictionary else {}
	var h_stocks: Dictionary = home.get("stocks", {}) if home.get("stocks") is Dictionary else {}
	for mat_var in q_mats:
		var mat: String = str(mat_var)
		h_stocks[mat] = float(q_mats.get(mat, 0.0)) + 20.0
	var comm_price: int = int(q.get("commissionPrice", 0))
	Money.move(home, "governmentPurse", owner, "coins", comm_price + 20000, "Fund JSON roundtrip commission", m_log)
	check(bool(NavalAI.request_replacement(c, owner, home, "bilge_punt").get("ok", false)), "Book slip order before JSON roundtrip")
	NavalAI.tick(c, 1)

	var raw_json: String = JSON.stringify(st)
	var parsed_val = JSON.parse_string(raw_json)
	var parsed: Dictionary = parsed_val if parsed_val is Dictionary else {}
	var val: Dictionary = SaveValidation.validate(parsed, world)
	check(bool(val.get("ok", false)), "SaveValidation accepts state with NavalAI orders and npcOwnerId buildQueue: " + str(val.get("message", "")))

	var pat1: Dictionary = c.fleet_owner("patrol-1")
	var pat1_ord: Dictionary = pat1.get("order", {}) if pat1.get("order") is Dictionary else {}
	var order_before: Dictionary = pat1_ord.duplicate(true)
	var h_queue: Array = home.get("buildQueue", []) if home.get("buildQueue") is Array else []
	var slip0: Dictionary = h_queue[0] if not h_queue.is_empty() else {}
	var slip_before: Dictionary = slip0.duplicate(true)
	var restored_campaign = Campaign.new(world)
	var res_restore: Dictionary = restored_campaign.restore(parsed)
	check(bool(res_restore.get("ok", false)), "Campaign.restore succeeds after NavalAI JSON roundtrip: " + str(res_restore.get("message", "")))
	var rest_state: Dictionary = restored_campaign.state
	NavalAI.ensure(rest_state, world)
	var rest_pat1: Dictionary = restored_campaign.fleet_owner("patrol-1")
	var rest_pat1_ord: Dictionary = rest_pat1.get("order", {}) if rest_pat1.get("order") is Dictionary else {}
	check(same_data(rest_pat1_ord.get("destination", ""), order_before.get("destination", "")), "Restored owner retains order destination")
	var restored_home: Dictionary = restored_campaign.port(str(home.get("id", "")))
	var rest_queue: Array = restored_home.get("buildQueue", []) if restored_home.get("buildQueue") is Array else []
	var rest_slip0: Dictionary = rest_queue[0] if not rest_queue.is_empty() else {}
	check(rest_queue.size() == 1 and str(rest_slip0.get("npcOwnerId", "")) == str(owner.get("id", "")) and int(rest_slip0.get("escrow", -1)) == int(slip_before.get("escrow", -2)), "Restored buildQueue retains npcOwnerId and exact escrow")
	check(int(Money.total(rest_state)) == int(rest_state.get("coinSupply", 0)), "Restored campaign conserves global coins")

	# Bounded work benchmark over 30 simulated days.
	var bench_start: int = Time.get_ticks_msec()
	var rest_owners: Array = rest_state.get("fleetOwners", []) if rest_state.get("fleetOwners") is Array else []
	var rest_ports: Array = rest_state.get("ports", []) if rest_state.get("ports") is Array else []
	for _d in range(30):
		Fleets.tick(rest_owners, rest_ports, 1.0)
		NavalAI.tick(restored_campaign, 1)
	var bench_ms: int = Time.get_ticks_msec() - bench_start
	check(bench_ms < 2500, "Thirty days of NavalAI.tick + Fleets.tick stays bounded (%d ms)" % bench_ms)
	var rest_nav_ai: Dictionary = rest_state.get("navalAi", {}) if rest_state.get("navalAi") is Dictionary else {}
	var rest_enc: Array = rest_nav_ai.get("encounters", []) if rest_nav_ai.get("encounters") is Array else []
	var rest_rep: Array = rest_nav_ai.get("replacements", []) if rest_nav_ai.get("replacements") is Array else []
	check(rest_enc.size() <= 24 and rest_rep.size() <= 24, "Encounter and replacement logs stay bounded")
	for own_var in rest_owners:
		var own: Dictionary = own_var
		var own_orders: Array = own.get("orders", []) if own.get("orders") is Array else []
		var own_log: Array = own.get("log", []) if own.get("log") is Array else []
		check(own_orders.size() <= 8 and own_log.size() <= 16, "Owner order and event logs stay bounded for " + str(own.get("id", "")))
	check(int(Money.total(rest_state)) == int(rest_state.get("coinSupply", 0)), "Thirty-day simulation conserves exact global coin supply")
