extends SceneTree

const Goods = preload("res://scripts/goods.gd")
const Construction = preload("res://scripts/construction.gd")

var _checks: int = 0


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		push_error("FAIL: " + msg)
		assert(false, msg)
		quit(1)


func _load_world() -> Dictionary:
	var file: FileAccess = FileAccess.open("res://data/world.json", FileAccess.READ)
	_check(file != null, "world.json must open")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_check(typeof(parsed) == TYPE_DICTIONARY, "world.json must parse as Dictionary")
	return parsed as Dictionary


func _initialize() -> void:
	var t0: int = Time.get_ticks_msec()
	var world: Dictionary = _load_world()
	var hulls: Array = world.get("HULLS", [])
	_check(hulls.size() == 24, "Expected 24 hulls in world.json")

	var starter_spec: Dictionary = {}
	for h_var in hulls:
		var spec: Dictionary = h_var
		if str(spec.get("id", "")) == "tin_skiff":
			starter_spec = spec.duplicate(true)

		var bp: Dictionary = Construction.blueprint(spec)
		var q: Dictionary = Construction.quote(spec)

		_check(is_finite(float(bp["lengthM"])) and float(bp["lengthM"]) > 0.0, "%s lengthM finite/positive" % spec["id"])
		_check(is_finite(float(bp["beamM"])) and float(bp["beamM"]) > 0.0, "%s beamM finite/positive" % spec["id"])
		_check(is_finite(float(q["ordinaryDays"])) and float(q["ordinaryDays"]) > 0.0, "%s ordinaryDays > 0" % spec["id"])
		_check(is_finite(float(q["expertDays"])) and float(q["expertDays"]) > 0.0, "%s expertDays > 0" % spec["id"])
		_check(absf(float(q["workerDays"]) - (float(q["ordinaryDays"]) + float(q["expertDays"]))) < 0.05, "%s workerDays == ordinaryDays + expertDays" % spec["id"])
		_check(is_finite(float(q["estimatedDays"])) and float(q["estimatedDays"]) > 0.0, "%s estimatedDays > 0" % spec["id"])

		var mats: Dictionary = q["materials"]
		_check(not mats.is_empty(), "%s materials non-empty" % spec["id"])
		for m_key in mats:
			_check(Goods.ITEMS.has(m_key), "%s material %s in Goods.ITEMS" % [spec["id"], m_key])
			_check(is_finite(float(mats[m_key])) and float(mats[m_key]) > 0.0, "%s material %s > 0" % [spec["id"], m_key])
		_check(int(mats["engines"]) >= 1 and absf(float(mats["engines"]) - roundf(float(mats["engines"]))) < 1e-6, "%s engines is whole integer >= 1" % spec["id"])
		_check(int(mats["guns"]) >= 1 and absf(float(mats["guns"]) - roundf(float(mats["guns"]))) < 1e-6, "%s guns is whole integer >= 1" % spec["id"])

		var lab: Dictionary = q["labor"]
		_check(not lab.is_empty(), "%s labor non-empty" % spec["id"])
		_check(lab.has("laborer") and float(lab["laborer"]) > 0.0, "%s labor uses laborer occupation" % spec["id"])
		_check(not lab.has("woodcutter"), "%s yard labor does not name laborers woodcutter" % spec["id"])
		for occ in lab:
			_check(Goods.WAGES.has(occ), "%s occupation %s in Goods.WAGES" % [spec["id"], occ])
			_check(is_finite(float(lab[occ])) and float(lab[occ]) > 0.0, "%s occupation %s > 0" % [spec["id"], occ])

		_check(int(q["materialCost"]) > 0, "%s materialCost > 0" % spec["id"])
		_check(int(q["laborCost"]) > 0, "%s laborCost > 0" % spec["id"])
		_check(int(q["supervisionCost"]) > 0, "%s supervisionCost > 0" % spec["id"])
		_check(int(q["overhead"]) > 0, "%s overhead > 0" % spec["id"])
		_check(int(q["margin"]) > 0, "%s margin > 0" % spec["id"])
		_check(int(q["tax"]) > 0, "%s tax > 0" % spec["id"])
		_check(int(q["total"]) > 0, "%s total > 0" % spec["id"])
		_check(int(q["commissionPrice"]) == int(q["total"]), "%s commissionPrice == total" % spec["id"])
		_check(int(q["readyPrice"]) > int(q["commissionPrice"]), "%s readyPrice > commissionPrice" % spec["id"])

		var component_sum: int = int(q["materialCost"]) + int(q["laborCost"]) + int(q["supervisionCost"]) + int(q["overhead"]) + int(q["margin"]) + int(q["tax"])
		_check(component_sum == int(q["total"]), "%s component sum == total" % spec["id"])

		var line_sum: int = 0
		var line_items: Array = q["lineItems"]
		_check(line_items.size() >= 10, "%s has itemized lineItems" % spec["id"])
		for item in line_items:
			_check(int(item["cost"]) > 0, "%s line item %s > 0" % [spec["id"], item["key"]])
			line_sum += int(item["cost"])
		_check(line_sum == int(q["total"]), "%s itemized lineItems sum == total" % spec["id"])

		# Scale checks: ~6m starter; 11-25m combat craft
		if str(spec["id"]) == "tin_skiff":
			_check(float(q["lengthM"]) >= 5.5 and float(q["lengthM"]) <= 6.8, "starter tin_skiff ~6m scale")
		elif int(spec.get("size", 14)) >= 17:
			_check(float(q["lengthM"]) >= 11.0 and float(q["lengthM"]) <= 25.5, "%s combat craft 11-25m scale" % spec["id"])

		# Full fractional-step build and exact wage conservation for every one of the 24 hulls
		var hull_order: Dictionary = Construction.make_order(spec, q, "player")
		var hull_port: Dictionary = {
			"workforce": 60,
			"workers": 20,
			"publicWorkers": 10,
			"specialists": 8,
			"householdPurse": 10000,
			"expertPurse": 5000
		}
		var hull_coins_start: int = int(hull_port["householdPurse"]) + int(hull_port["expertPurse"]) + int(hull_order["escrow"])
		var guard: int = 0
		while not bool(hull_order["ready"]) and guard < 200:
			guard += 1
			Construction.begin_day(hull_port)
			Construction.advance(hull_port, hull_order, 0.75)
			_check(not hull_port.has("_yardStepOrders"), "%s port stores no order references" % spec["id"])
			var hull_coins_now: int = int(hull_port["householdPurse"]) + int(hull_port["expertPurse"]) + int(hull_order["escrow"])
			_check(hull_coins_now == hull_coins_start, "%s tick %d conserves coins" % [spec["id"], guard])
		_check(bool(hull_order["ready"]), "%s completes build" % spec["id"])
		_check(int(hull_order["escrow"]) == 0, "%s final escrow == 0" % spec["id"])
		_check(int(hull_order["laborPaid"]) == int(q["laborCost"]), "%s final laborPaid == laborCost" % spec["id"])
		_check(int(hull_order["supervisionPaid"]) == int(q["supervisionCost"]), "%s final supervisionPaid == supervisionCost" % spec["id"])
		_check(int(hull_port["householdPurse"]) == 10000 + int(q["laborCost"]), "%s householdPurse exact" % spec["id"])
		_check(int(hull_port["expertPurse"]) == 5000 + int(q["supervisionCost"]), "%s expertPurse exact" % spec["id"])

	# No forced starter price or reliance on legacy spec.price
	_check(not starter_spec.is_empty(), "starter tin_skiff found")
	var starter_q: Dictionary = Construction.quote(starter_spec)
	var mutated_price_spec: Dictionary = starter_spec.duplicate(true)
	mutated_price_spec["price"] = 999999
	var starter_q_mutated_price: Dictionary = Construction.quote(mutated_price_spec)
	_check(int(starter_q["total"]) == int(starter_q_mutated_price["total"]), "quote ignores legacy spec.price")
	_check(int(starter_q["total"]) != 40000 and int(starter_q["total"]) != int(starter_spec.get("price",-1)), "no forced 40k or legacy price")

	# Total changes with wages, materials, armor, and weapons
	var q_high_wages: Dictionary = Construction.quote(starter_spec, {"shipwright": 200, "mechanic": 240, "foreman": 260})
	_check(int(q_high_wages["laborCost"]) > int(starter_q["laborCost"]), "laborCost increases with higher wages")
	_check(int(q_high_wages["supervisionCost"]) > int(starter_q["supervisionCost"]), "supervisionCost increases with higher foreman wage")
	_check(int(q_high_wages["total"]) > int(starter_q["total"]), "total increases with higher wages")

	var q_high_materials: Dictionary = Construction.quote(starter_spec, {"timber": 700.0, "iron": 1400.0, "engines": 24000.0})
	_check(int(q_high_materials["materialCost"]) > int(starter_q["materialCost"]), "materialCost increases with higher material prices")
	_check(int(q_high_materials["total"]) > int(starter_q["total"]), "total increases with higher material prices")

	var heavy_armor_spec: Dictionary = starter_spec.duplicate(true)
	heavy_armor_spec["armor"] = 12
	var q_heavy_armor: Dictionary = Construction.quote(heavy_armor_spec)
	_check(float(q_heavy_armor["materials"]["iron"]) > float(starter_q["materials"]["iron"]), "armor increases iron material requirement")
	_check(int(q_heavy_armor["total"]) > int(starter_q["total"]), "total increases with armor")

	var heavy_weapon_spec: Dictionary = starter_spec.duplicate(true)
	heavy_weapon_spec["weapon"] = "torpedo"
	heavy_weapon_spec["damage"] = 36
	heavy_weapon_spec["weaponCount"] = 2
	var q_heavy_weapon: Dictionary = Construction.quote(heavy_weapon_spec)
	_check(float(q_heavy_weapon["materials"]["guns"]) > float(starter_q["materials"]["guns"]), "heavier weapon increases gun assembly lots")
	_check(int(q_heavy_weapon["total"]) > int(starter_q["total"]), "total increases with weapons")

	# Zero workers / zero supervisors -> no progress and no cash spent
	var order_zero: Dictionary = Construction.make_order(starter_spec, starter_q, "player")
	var port_no_workers: Dictionary = {
		"workforce": 30,
		"workers": 22,
		"publicWorkers": 8,
		"specialists": 4,
		"householdPurse": 1000,
		"expertPurse": 500
	}
	var res_no_workers: Dictionary = Construction.advance(port_no_workers, order_zero, 3.0)
	_check(int(res_no_workers["spent"]) == 0, "zero available workers spends 0 cash")
	_check(float(res_no_workers["workedDays"]) == 0.0, "zero available workers does 0 work")
	_check(not bool(order_zero["ready"]), "order not ready with zero workers")

	var port_no_supervisors: Dictionary = {
		"workforce": 30,
		"workers": 10,
		"publicWorkers": 5,
		"specialists": 0,
		"householdPurse": 1000,
		"expertPurse": 500
	}
	var res_no_sup: Dictionary = Construction.advance(port_no_supervisors, order_zero, 3.0)
	_check(int(res_no_sup["spent"]) == 0, "zero supervisors spends 0 cash")
	_check(float(res_no_sup["workedDays"]) == 0.0, "zero supervisors does 0 work")
	_check(int(port_no_supervisors["householdPurse"]) == 1000 and int(port_no_supervisors["expertPurse"]) == 500, "purses unchanged on blocked advance")

	# Finite escrow cap: partial escrow cannot advance beyond affordable work or create coins
	var order_capped_escrow: Dictionary = Construction.make_order(starter_spec, starter_q, "player")
	order_capped_escrow["escrow"] = 800
	var port_partial: Dictionary = {
		"workforce": 40,
		"workers": 10,
		"publicWorkers": 5,
		"specialists": 5,
		"householdPurse": 2000,
		"expertPurse": 1000
	}
	var global_before_partial: int = int(port_partial["householdPurse"]) + int(port_partial["expertPurse"]) + int(order_capped_escrow["escrow"])
	var res_partial: Dictionary = Construction.advance(port_partial, order_capped_escrow, 20.0)
	var global_after_partial: int = int(port_partial["householdPurse"]) + int(port_partial["expertPurse"]) + int(order_capped_escrow["escrow"])
	_check(global_before_partial == global_after_partial, "partial escrow conserves exact coins")
	_check(int(order_capped_escrow["escrow"]) == 0, "partial escrow exhausted cleanly")
	_check(int(res_partial["spent"]) == 800, "partial escrow spent equals available 800 coins")
	_check(not bool(order_capped_escrow["ready"]), "underfunded escrow order cannot finish")

	# Full build progression, exact wage distribution, coin conservation, and idempotency after completion
	var order_full: Dictionary = Construction.make_order(starter_spec, starter_q, "yard")
	_check(str(order_full["owner"]) == "yard", "yard owner preserved")
	_check(int(order_full["escrow"]) == int(starter_q["laborCost"]) + int(starter_q["supervisionCost"]), "initial escrow == laborCost + supervisionCost")

	var port_build: Dictionary = {
		"workforce": 35,
		"workers": 18,
		"publicWorkers": 5,
		"specialists": 3,
		"householdPurse": 5000,
		"expertPurse": 2500
	}
	var initial_total_coins: int = int(port_build["householdPurse"]) + int(port_build["expertPurse"]) + int(order_full["escrow"])
	var steps: int = 0
	while not bool(order_full["ready"]) and steps < 60:
		steps += 1
		Construction.begin_day(port_build)
		var step_res: Dictionary = Construction.advance(port_build, order_full, 1.0)
		var running_coins: int = int(port_build["householdPurse"]) + int(port_build["expertPurse"]) + int(order_full["escrow"])
		_check(running_coins == initial_total_coins, "step %d conserves exact coins" % steps)
		_check(int(step_res["spent"]) >= 0, "step %d non-negative spend" % steps)

	_check(bool(order_full["ready"]), "order completed within bounded steps")
	_check(int(order_full["escrow"]) == 0, "completed order escrow is 0")
	_check(int(order_full["laborPaid"]) == int(starter_q["laborCost"]), "exact laborCost paid to householdPurse")
	_check(int(order_full["supervisionPaid"]) == int(starter_q["supervisionCost"]), "exact supervisionCost paid to expertPurse")
	_check(int(port_build["householdPurse"]) == 5000 + int(starter_q["laborCost"]), "householdPurse received exact laborCost")
	_check(int(port_build["expertPurse"]) == 2500 + int(starter_q["supervisionCost"]), "expertPurse received exact supervisionCost")
	_check(float(order_full["remainingWorkerDays"]) == 0.0, "remainingWorkerDays == 0 on completion")

	# Completed advance idempotency
	var res_after_done: Dictionary = Construction.advance(port_build, order_full, 5.0)
	_check(bool(res_after_done["finished"]) and bool(res_after_done["ready"]), "completed advance remains finished")
	_check(int(res_after_done["spent"]) == 0, "completed advance spends 0 extra coins")
	_check(int(port_build["householdPurse"]) == 5000 + int(starter_q["laborCost"]), "idempotent householdPurse")
	_check(int(port_build["expertPurse"]) == 2500 + int(starter_q["supervisionCost"]), "idempotent expertPurse")

	# Bounded yard team cap & workforce-workers-publicWorkers total civilian bottleneck (including experts)
	var order_cap_a: Dictionary = Construction.make_order(starter_spec, starter_q, "player")
	var order_cap_b: Dictionary = Construction.make_order(starter_spec, starter_q, "player")
	var port_normal_pool: Dictionary = {"workforce": 50, "workers": 10, "publicWorkers": 5, "specialists": 10, "householdPurse": 0, "expertPurse": 0}
	var port_huge_pool: Dictionary = {"workforce": 5000, "workers": 10, "publicWorkers": 5, "specialists": 1000, "householdPurse": 0, "expertPurse": 0}
	Construction.begin_day(port_normal_pool)
	Construction.begin_day(port_huge_pool)
	var res_cap_a: Dictionary = Construction.advance(port_normal_pool, order_cap_a, 1.0)
	var res_cap_b: Dictionary = Construction.advance(port_huge_pool, order_cap_b, 1.0)
	_check(absf(float(res_cap_a["workedDays"]) - float(res_cap_b["workedDays"])) < 1e-4, "bounded yard team cap prevents infinite parallel speedup")

	var order_tight: Dictionary = Construction.make_order(starter_spec, starter_q, "player")
	var port_tight: Dictionary = {"workforce": 20, "workers": 14, "publicWorkers": 5, "specialists": 4, "householdPurse": 0, "expertPurse": 0}
	Construction.begin_day(port_tight)
	var res_tight: Dictionary = Construction.advance(port_tight, order_tight, 1.0)
	var tight_combined: float = float(res_tight["ordinaryWorked"]) + float(res_tight["expertWorked"])
	_check(tight_combined <= 1.01 and tight_combined > 0.0, "combined ordinary + expert respects total idle workforce == 1")
	_check(absf(float(res_tight["workedDays"]) - 1.0) < 0.05, "workedDays bounded by free_TOTAL * dt == 1.0")

	# Invalid / non-positive / NaN days do not mutate
	var order_nan: Dictionary = Construction.make_order(starter_spec, starter_q, "player")
	var res_neg: Dictionary = Construction.advance(port_normal_pool, order_nan, -2.0)
	var res_nan: Dictionary = Construction.advance(port_normal_pool, order_nan, NAN)
	_check(int(res_neg["spent"]) == 0 and int(res_nan["spent"]) == 0, "negative/NaN days spend 0")
	_check(float(order_nan["workedDays"]) == 0.0, "negative/NaN days do 0 work")

	# Whole assembly scaling: starter has 1 engine & 1 gun; larger hulls have more whole engines & guns
	_check(int(starter_q["materials"]["engines"]) == 1, "starter tin_skiff has 1 whole engine assembly")
	_check(int(starter_q["materials"]["guns"]) == 1, "starter tin_skiff has 1 whole gun assembly")
	var dread_spec: Dictionary = {}
	for h_var in hulls:
		var h_dict: Dictionary = h_var
		if str(h_dict.get("id", "")) == "maiden_dreadnought":
			dread_spec = h_dict
	var dread_q: Dictionary = Construction.quote(dread_spec)
	_check(int(dread_q["materials"]["engines"]) > int(starter_q["materials"]["engines"]), "larger hull has more whole engines")
	_check(int(dread_q["materials"]["guns"]) > int(starter_q["materials"]["guns"]), "larger hull has more whole guns")

	# Simultaneous orders & combined workforce pool (availableWorkers is TOTAL idle civilians; experts are a SUBSET)
	# 1) Tight total workforce (3 free total workers < 1 full team, abundant 10 specialists):
	#    order_1 is bounded by free_TOTAL*dt/(ordinaryDays+expertDays) -> uses all 3.0 total workers (ordinary+expert == 3.0), order_2 gets 0
	var sim_ord_1a: Dictionary = Construction.make_order(starter_spec, starter_q, "player")
	var sim_ord_1b: Dictionary = Construction.make_order(starter_spec, starter_q, "yard")
	var port_sim_ord_tight: Dictionary = {
		"workforce": 20,
		"workers": 13,
		"publicWorkers": 4,
		"specialists": 10,
		"householdPurse": 0,
		"expertPurse": 0
	}
	Construction.begin_day(port_sim_ord_tight)
	var r_ord_1a: Dictionary = Construction.advance(port_sim_ord_tight, sim_ord_1a, 1.0)
	var r_ord_1b: Dictionary = Construction.advance(port_sim_ord_tight, sim_ord_1b, 1.0)
	var comb_1a: float = float(r_ord_1a["ordinaryWorked"]) + float(r_ord_1a["expertWorked"])
	var comb_1b: float = float(r_ord_1b["ordinaryWorked"]) + float(r_ord_1b["expertWorked"])
	_check(absf(comb_1a - 3.0) < 0.05, "first simultaneous order uses all 3.0 total available workers (ordinary + expert)")
	_check(comb_1b == 0.0 and float(r_ord_1b["workedDays"]) == 0.0 and int(r_ord_1b["spent"]) == 0, "second simultaneous order blocked when total workers exhausted")

	# 2) Combined pool <= availableWorkers across two orders with abundant experts (6 total idle workers, 10 specialists):
	#    order_1 takes its full team (~5.10 combined: ~4.00 ordinary + ~1.10 expert), order_2 gets remaining ~0.90 combined
	var sim_ord_2a: Dictionary = Construction.make_order(starter_spec, starter_q, "player")
	var sim_ord_2b: Dictionary = Construction.make_order(starter_spec, starter_q, "yard")
	var port_sim_ord_share: Dictionary = {
		"workforce": 20,
		"workers": 10,
		"publicWorkers": 4,
		"availableWorkers": 6,
		"specialists": 10,
		"availableSpecialists": 10,
		"householdPurse": 0,
		"expertPurse": 0
	}
	Construction.begin_day(port_sim_ord_share)
	var r_ord_2a: Dictionary = Construction.advance(port_sim_ord_share, sim_ord_2a, 1.0)
	var r_ord_2b: Dictionary = Construction.advance(port_sim_ord_share, sim_ord_2b, 1.0)
	var comb_2a: float = float(r_ord_2a["ordinaryWorked"]) + float(r_ord_2a["expertWorked"])
	var comb_2b: float = float(r_ord_2b["ordinaryWorked"]) + float(r_ord_2b["expertWorked"])
	_check(comb_2a > 0.0 and comb_2b > 0.0, "both simultaneous orders work when total pool (6.0) exceeds one team (~5.10)")
	_check(comb_2b < comb_2a, "second order gets reduced remainder of total workforce")
	_check(comb_2a + comb_2b <= 6.05 and absf((comb_2a + comb_2b) - 6.0) < 0.05, "combined (ordinary + expert) across two orders with abundant experts == 6.0 <= availableWorkers")

	# 3) Prioritize availableSpecialists over total specialists:
	#    port has specialists=10 but availableSpecialists=0 -> 0 work; availableSpecialists=1 -> order_1 takes 1.0, order_2 gets 0
	var sim_avail_spec_0: Dictionary = Construction.make_order(starter_spec, starter_q, "player")
	var port_avail_spec_zero: Dictionary = {
		"workforce": 50,
		"workers": 10,
		"publicWorkers": 5,
		"specialists": 10,
		"availableSpecialists": 0,
		"householdPurse": 0,
		"expertPurse": 0
	}
	Construction.begin_day(port_avail_spec_zero)
	var r_avail_0: Dictionary = Construction.advance(port_avail_spec_zero, sim_avail_spec_0, 1.0)
	_check(float(r_avail_0["workedDays"]) == 0.0 and int(r_avail_0["spent"]) == 0, "availableSpecialists=0 overrides specialists=10 and blocks work")

	var sim_spec_1a: Dictionary = Construction.make_order(starter_spec, starter_q, "player")
	var sim_spec_1b: Dictionary = Construction.make_order(starter_spec, starter_q, "yard")
	var port_sim_spec_tight: Dictionary = {
		"workforce": 50,
		"workers": 10,
		"publicWorkers": 5,
		"specialists": 10,
		"availableSpecialists": 1,
		"householdPurse": 0,
		"expertPurse": 0
	}
	Construction.begin_day(port_sim_spec_tight)
	var r_spec_1a: Dictionary = Construction.advance(port_sim_spec_tight, sim_spec_1a, 1.0)
	var r_spec_1b: Dictionary = Construction.advance(port_sim_spec_tight, sim_spec_1b, 1.0)
	_check(absf(float(r_spec_1a["expertWorked"]) - 1.0) < 0.05, "first simultaneous order uses full 1.0 availableSpecialists (ignoring specialists=10)")
	_check(float(r_spec_1b["expertWorked"]) == 0.0 and float(r_spec_1b["workedDays"]) == 0.0 and int(r_spec_1b["spent"]) == 0, "second simultaneous order blocked when availableSpecialists exhausted")

	# 4) Partial specialist pool sharing (2 free specialists: order_1 takes ~1.10, order_2 gets remaining ~0.90)
	var sim_spec_2a: Dictionary = Construction.make_order(starter_spec, starter_q, "player")
	var sim_spec_2b: Dictionary = Construction.make_order(starter_spec, starter_q, "yard")
	var port_sim_spec_share: Dictionary = {
		"workforce": 50,
		"workers": 10,
		"publicWorkers": 5,
		"specialists": 10,
		"availableSpecialists": 2,
		"householdPurse": 0,
		"expertPurse": 0
	}
	Construction.begin_day(port_sim_spec_share)
	var r_spec_2a: Dictionary = Construction.advance(port_sim_spec_share, sim_spec_2a, 1.0)
	var r_spec_2b: Dictionary = Construction.advance(port_sim_spec_share, sim_spec_2b, 1.0)
	_check(float(r_spec_2a["expertWorked"]) > 0.0 and float(r_spec_2b["expertWorked"]) > 0.0, "both orders work when 2 availableSpecialists present")
	_check(float(r_spec_2b["expertWorked"]) < float(r_spec_2a["expertWorked"]), "second order gets reduced remainder of availableSpecialists")
	_check(absf((float(r_spec_2a["expertWorked"]) + float(r_spec_2b["expertWorked"])) - 2.0) < 0.05, "simultaneous orders sum to exact availableSpecialists (2.0)")

	# 5) Explicit begin_day(port) reset API & no whole order references in port
	var day_test_order: Dictionary = Construction.make_order(starter_spec, starter_q, "player")
	var port_day_reset: Dictionary = {
		"workforce": 20,
		"workers": 15,
		"publicWorkers": 2,
		"specialists": 5,
		"householdPurse": 0,
		"expertPurse": 0
	}
	Construction.begin_day(port_day_reset)
	var r_same_day_1: Dictionary = Construction.advance(port_day_reset, day_test_order, 1.0)
	var r_same_day_2: Dictionary = Construction.advance(port_day_reset, day_test_order, 1.0)
	_check(absf(float(r_same_day_1["workedDays"]) - 3.0) < 0.05, "day 1 first call uses all 3.0 available workers")
	_check(float(r_same_day_2["workedDays"]) == 0.0, "same-day second call without begin_day gets 0 remaining workers")
	Construction.begin_day(port_day_reset)
	var r_next_day: Dictionary = Construction.advance(port_day_reset, day_test_order, 1.0)
	_check(absf(float(r_next_day["workedDays"]) - 3.0) < 0.05, "begin_day(port) resets daily reservation pool for next day")
	_check(not port_day_reset.has("_yardStepOrders") and not port_day_reset.has("_yardStepSig"), "port has no _yardStepOrders or _yardStepSig")
	for pk in port_day_reset:
		var pv: Variant = port_day_reset[pk]
		_check(typeof(pv) != TYPE_DICTIONARY and typeof(pv) != TYPE_ARRAY, "port key %s stores scalar only (no order references)" % str(pk))

	# 6) Multi-day simultaneous build of two orders to completion with daily begin_day, combined capacity & coin conservation
	var multi_a: Dictionary = Construction.make_order(starter_spec, starter_q, "player")
	var multi_b: Dictionary = Construction.make_order(starter_spec, starter_q, "yard")
	var port_multi: Dictionary = {
		"workforce": 20,
		"workers": 10,
		"publicWorkers": 4,
		"specialists": 2,
		"householdPurse": 1000,
		"expertPurse": 500
	}
	var multi_coins_start: int = int(port_multi["householdPurse"]) + int(port_multi["expertPurse"]) + int(multi_a["escrow"]) + int(multi_b["escrow"])
	var multi_days: int = 0
	while (not bool(multi_a["ready"]) or not bool(multi_b["ready"])) and multi_days < 60:
		multi_days += 1
		Construction.begin_day(port_multi)
		var ra: Dictionary = Construction.advance(port_multi, multi_a, 1.0)
		var rb: Dictionary = Construction.advance(port_multi, multi_b, 1.0)
		var day_combined_workers: float = float(ra["ordinaryWorked"]) + float(ra["expertWorked"]) + float(rb["ordinaryWorked"]) + float(rb["expertWorked"])
		_check(day_combined_workers <= 6.05, "day %d combined (ordinary + expert) work <= 6" % multi_days)
		_check(float(ra["expertWorked"]) + float(rb["expertWorked"]) <= 2.05, "day %d combined specialist work <= 2" % multi_days)
		var multi_coins_now: int = int(port_multi["householdPurse"]) + int(port_multi["expertPurse"]) + int(multi_a["escrow"]) + int(multi_b["escrow"])
		_check(multi_coins_now == multi_coins_start, "day %d simultaneous build conserves coins" % multi_days)
	_check(bool(multi_a["ready"]) and bool(multi_b["ready"]), "both simultaneous orders complete")
	_check(int(multi_a["escrow"]) == 0 and int(multi_b["escrow"]) == 0, "both simultaneous orders exhaust escrow")
	_check(int(port_multi["householdPurse"]) == 1000 + 2 * int(starter_q["laborCost"]), "householdPurse receives exact laborCost from both orders")
	_check(int(port_multi["expertPurse"]) == 500 + 2 * int(starter_q["supervisionCost"]), "expertPurse receives exact supervisionCost from both orders")

	var elapsed_ms: int = Time.get_ticks_msec() - t0
	print("STARTER QUOTE (tin_skiff): length=%.2fm beam=%.2fm area=%.2fm2 ordinaryDays=%.2f expertDays=%.2f workerDays=%.2f estDays=%.2f" % [
		starter_q["lengthM"], starter_q["beamM"], starter_q["hullAreaM2"],
		starter_q["ordinaryDays"], starter_q["expertDays"], starter_q["workerDays"], starter_q["estimatedDays"]
	])
	print("STARTER COSTS: materialCost=%d laborCost=%d supervisionCost=%d overhead=%d margin=%d tax=%d commissionPrice/total=%d readyPrice=%d escrow=%d" % [
		starter_q["materialCost"], starter_q["laborCost"], starter_q["supervisionCost"],
		starter_q["overhead"], starter_q["margin"], starter_q["tax"],
		starter_q["total"], starter_q["readyPrice"], starter_q["escrow"]
	])
	print("STARTER MATERIALS: ", JSON.stringify(starter_q["materials"]))
	print("STARTER MATERIAL COSTS: ", JSON.stringify(starter_q["materialCosts"]))
	print("STARTER LABOR DAYS: ", JSON.stringify(starter_q["labor"]))
	print("STARTER LABOR COSTS: ", JSON.stringify(starter_q["laborCosts"]))
	print("CONSTRUCTION PASS: %d checks in %d ms" % [_checks, elapsed_ms])
	quit(0)
