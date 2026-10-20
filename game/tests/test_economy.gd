extends SceneTree

const Economy = preload("res://scripts/economy.gd")
const Goods = preload("res://scripts/goods.gd")

var _checks_passed: int = 0


func _check(cond: bool, msg: String) -> void:
	assert(cond, msg)
	if not cond:
		push_error("TEST FAILED: " + msg)
		quit(1)
	_checks_passed += 1


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	_test_16_goods_and_recursive_costs()
	_test_create_port_and_coin_seeding()
	_test_price_spread_and_scarcity()
	_test_transact_fractional_and_invalid_calls()
	_test_recruit_scarcity_and_purses()
	_test_daily_upkeep()
	_test_wage_recipients_zero_cash_and_missing_inputs()
	_test_worker_isolation_and_thread_snapshot()
	_test_365_day_coin_conservation_and_stability()
	var elapsed_ms := Time.get_ticks_msec() - t0
	_check(elapsed_ms < 60000, "test suite completed under 60s (%d ms)" % elapsed_ms)
	print("ALL NATIVE ECONOMY TESTS PASSED (%d checks in %d ms)" % [_checks_passed, elapsed_ms])
	quit(0)


func _test_16_goods_and_recursive_costs() -> void:
	var expected := [
		"food", "logs", "timber", "ore", "charcoal", "iron", "copper", "saltpeter",
		"sulfur", "gunpowder", "ammo", "crude", "fuel", "supplies", "engines", "guns"
	]
	_check(Economy.GOODS.size() == 16, "GOODS has 16 entries")
	_check(Economy.GOOD_KEYS.size() == 16, "GOOD_KEYS has 16 entries")
	for k in expected:
		_check(Economy.GOODS.has(k), "GOODS has key " + k)
		var g: Dictionary = Economy.GOODS[k]
		_check(typeof(g.get("name")) == TYPE_STRING and str(g["name"]).length() > 0, k + " name valid")
		_check(int(g.get("base", 0)) == ceili(Goods.cost(k)), k + " base matches ceili(Goods.cost)")
		_check(float(g.get("weight", 0.0)) > 0.0, k + " weight > 0")
		_check(typeof(g.get("color")) == TYPE_STRING and str(g["color"]).begins_with("#"), k + " color hex")
		_check(typeof(g.get("unit")) == TYPE_STRING and str(g["unit"]).length() > 0, k + " unit valid")
		_check(g.get("inputs") is Dictionary and g.get("labor") is Dictionary, k + " inputs and labor dictionaries")

	# Verify specific recursive labor/input cost anchors from Goods
	_check(int(Economy.GOODS["food"]["base"]) == 200, "food base cost is 200 cash (2 farmer-days)")
	_check(int(Economy.GOODS["logs"]["base"]) == 200, "logs base cost is 200 cash (2 woodcutter-days)")
	_check(int(Economy.GOODS["timber"]["base"]) == 388, "timber base cost is ceili(387.5) = 388 cash")
	_check(int(Economy.GOODS["iron"]["base"]) == 800, "iron base cost is 800 cash")
	_check(int(Economy.GOODS["gunpowder"]["base"]) == 1400, "gunpowder base cost is 1400 cash")
	_check(int(Economy.GOODS["ammo"]["base"]) == 355, "ammo base cost is 355 cash")
	_check(int(Economy.GOODS["engines"]["base"]) == 17265, "engines recursive base cost is 17265 cash")
	_check(int(Economy.GOODS["guns"]["base"]) == 7809, "guns recursive base cost is ceili(7808.75) = 7809 cash")


func _test_create_port_and_coin_seeding() -> void:
	var def := {
		"id": "iron_bay",
		"name": "Iron Bay",
		"faction": "forge",
		"x": 640,
		"y": 520,
		"population": 1800,
		"industry": "foundry",
		"specialty": "iron",
		"description": "Smelters and gun foundries along basalt cliffs.",
		"wealth": 1.3
	}
	var port := Economy.create_port(def)
	for k in def.keys():
		_check(port[k] == def[k], "port preserves def." + str(k))

	var wf := int(port["workforce"])
	_check(wf == int(round(1800.0 * 0.35)), "civilian workforce is 35% of 1800 = 630")
	_check(int(port["cash"]) == wf * 20 * 100, "business purse seeded at 20 wage-days per worker")
	_check(int(port["householdPurse"]) == wf * 15 * 100, "household purse seeded at 15 wage-days per worker")
	_check(int(port["expertPurse"]) == wf * 5 * 100, "expert purse seeded at 5 wage-days per worker")
	_check(int(port["governmentPurse"]) == wf * 40 * 100, "government purse seeded at 40 wage-days per worker")
	_check(Economy.port_coins(port) == wf * 80 * 100, "total port coins equals 80 wage-days per worker")

	_check(port.get("stocks") is Dictionary, "stocks is Dictionary")
	for g in Economy.GOOD_KEYS:
		_check(float(port["stocks"][g]) > 0.0, "positive initial stock for " + g)
	# Food stock scaled to several days of population demand (1 bale per 12.5 person-days = 144/day for 1800 pop)
	var daily_pop_food := 1800.0 / 12.5
	_check(float(port["stocks"]["food"]) >= daily_pop_food * 1.5, "initial food stock covers multiple days of population demand")

	_check(int(port.get("workers", 0)) > 0, "positive employed workers")
	_check(int(port.get("publicWorkers", 0)) > 0, "positive publicWorkers")
	_check(int(port.get("availableWorkers", -1)) > 0, "positive idle availableWorkers")
	_check(int(port.get("availableWorkers", -1)) == wf - int(port["workers"]) - int(port["publicWorkers"]), "availableWorkers matches idle remainder workforce - workers - publicWorkers")
	_check(int(port["recruits"]) == mini(wf, ceili(float(wf) * 0.06)), "initial default recruit pool is min(workforce, ceili(workforce * 0.06))")
	var kelp_port := Economy.create_port({"id": "kelp_reach", "workforce": 1050, "industry": "fishery"})
	_check(int(kelp_port["recruits"]) == mini(1050, ceili(1050.0 * 0.06)) and int(kelp_port["recruits"]) == 63, "large workforce (>1000) default recruit pool scales with 6% instead of capping at 42")
	var fixture_port := Economy.create_port({"id": "fix_p", "workforce": 200, "recruits": 19})
	_check(int(fixture_port["recruits"]) == 19, "create_port preserves explicit recruits fixture")
	var zero_rec_fixture := Economy.create_port({"id": "fix_zero", "workforce": 200, "recruits": 0})
	_check(int(zero_rec_fixture["recruits"]) == 0, "create_port preserves explicit zero recruits fixture")
	_check(int(port.get("specialists", 0)) > 0 and int(port.get("specialists", 0)) == int(port.get("specialistWorkers", -1)), "specialists and specialistWorkers aliases match and > 0")
	# Equal-valued but physically distinct commissions each own separate coin escrow.
	var first_order: Dictionary = {"escrow":500}
	var second_order: Dictionary = first_order.duplicate(true)
	var order_port: Dictionary = {"buildQueue":[first_order,second_order]}
	_check(Economy.port_coins(order_port)==1000,"two identical separate orders both count their physical escrow")
	_check(Economy.total_coins([order_port],[],[first_order,second_order])==1000,"aliasing an already counted order does not count it twice")
	_check(int(port.get("availableSpecialists", 0)) > 0 and int(port.get("availableSpecialists", 0)) <= int(port.get("specialists", 0)), "availableSpecialists alias positive and bounded by specialists")
	_check(port.get("employed") is Dictionary and port.get("employedByOccupation") is Dictionary, "employed by occupation exposed")
	_check(port.get("lastPayroll") is Dictionary, "lastPayroll exposed")
	_check(port.get("publicStores") is Dictionary, "publicStores exposed")
	_check(port.get("shipStock") is Dictionary and port.get("shipIds") is Array, "shipStock and shipIds exposed")
	_check(port.get("lastProduction") is Dictionary and port.get("projectedProduction") is Dictionary and port.get("shortages") is Array and port.get("ledger") is Array, "telemetry, projectedProduction, and ledger exposed")
	for g in Economy.GOOD_KEYS:
		_check(float(port["lastProduction"][g]) == 0.0, "create_port lastProduction is zero before paid tick for " + g)
	_check(float(port["projectedProduction"]["iron"]) > 0.0, "projectedProduction shows projected specialty output separately")

	# Verify legacy world.json port def with only 'workers' treats it as authoritative workforce with positive idle availableWorkers
	var legacy_port := Economy.create_port({"id": "legacy_p", "workers": 420, "industry": "shipyard"})
	_check(int(legacy_port["workforce"]) == 420, "legacy workers field seeds authoritative workforce")
	_check(int(legacy_port["availableWorkers"]) == 420 - int(legacy_port["workers"]) - int(legacy_port["publicWorkers"]) and int(legacy_port["availableWorkers"]) > 0, "legacy port has positive idle availableWorkers")

	# Verify buildQueue escrow is included in port_coins and total_coins without double-counting
	var base_port_coins := Economy.port_coins(port)
	var bq_order := {"id": "bq-1", "escrow": 12500}
	port["cash"] = int(port["cash"]) - 12500
	port["buildQueue"] = [bq_order]
	_check(Economy.port_coins(port) == base_port_coins, "port_coins includes buildQueue escrow")
	_check(Economy.total_coins([port]) == base_port_coins, "total_coins includes port.buildQueue escrow")
	_check(Economy.total_coins([port], [], [bq_order]) == base_port_coins, "total_coins deduplicates buildQueue order when also passed in orders")


func _test_price_spread_and_scarcity() -> void:
	var port := Economy.create_port({
		"id": "reed_haven",
		"name": "Reed Haven",
		"faction": "reed",
		"x": 300,
		"y": 300,
		"population": 1200,
		"industry": "fishery",
		"wealth": 1.0
	})
	for g in Economy.GOOD_KEYS:
		for stock_level in [0, 3, 25, 90, 220, 450]:
			port["stocks"][g] = float(stock_level)
			var buy := Economy.price(port, g, "buy")
			var sell := Economy.price(port, g, "sell")
			_check(buy > 0 and sell > 0, "positive integer prices for " + g)
			_check(buy > sell, "buy > sell spread for " + g)

		port["stocks"][g] = 2.0
		var scarce_buy := Economy.price(port, g, "buy")
		var scarce_sell := Economy.price(port, g, "sell")
		port["stocks"][g] = 350.0
		var abundant_buy := Economy.price(port, g, "buy")
		var abundant_sell := Economy.price(port, g, "sell")
		_check(scarce_buy > abundant_buy, "scarce buy > abundant buy for " + g)
		_check(scarce_sell > abundant_sell, "scarce sell > abundant sell for " + g)


func _test_transact_fractional_and_invalid_calls() -> void:
	var port := Economy.create_port({
		"id": "market_port",
		"name": "Market Port",
		"faction": "compact",
		"population": 1400,
		"industry": "trade",
		"cash": 20000
	})
	port["stocks"]["iron"] = 20.0
	port["stocks"]["food"] = 50.0

	var wallet := {
		"coins": 15000,
		"cargo": {"food": 10.0}
	}
	var capacity := 40 # 10 food * 1 = 10 used, 30 left (iron weight 3 -> max 10 iron)
	var coins_before := Economy.total_coins([port], [], [], [wallet])

	var unit_buy := Economy.price(port, "iron", "buy")
	var buy_res := Economy.transact(port, wallet, "iron", 5, "buy", capacity)
	_check(bool(buy_res["ok"]) == true, "valid iron buy succeeds")
	_check(int(buy_res["qty"]) == 5, "bought qty 5")
	_check(int(buy_res["total"]) == unit_buy * 5 and int(buy_res["coins"]) == unit_buy * 5, "buy total/coins matches unit * 5")
	_check(int(wallet["coins"]) == 15000 - unit_buy * 5, "wallet coins deducted")
	_check(float(wallet["cargo"]["iron"]) == 5.0, "wallet cargo iron increased")
	_check(float(port["stocks"]["iron"]) == 15.0, "port iron stock decreased")
	_check(int(port["cash"]) == 20000 + unit_buy * 5, "port business cash increased")
	_check(Economy.total_coins([port], [], [], [wallet]) == coins_before, "buy conserves exact total coins")

	# Reject exceeding capacity without mutation
	var snap_port := port.duplicate(true)
	var snap_wallet := wallet.duplicate(true)
	var over_cap := Economy.transact(port, wallet, "iron", 6, "buy", capacity)
	_check(bool(over_cap["ok"]) == false, "exceeding capacity rejected")
	_check(port == snap_port and wallet == snap_wallet, "no mutation on capacity rejection")

	# Reject exceeding port stock
	var over_stock := Economy.transact(port, wallet, "iron", 99, "buy", 1000)
	_check(bool(over_stock["ok"]) == false, "exceeding port stock rejected")
	_check(port == snap_port and wallet == snap_wallet, "no mutation on over-stock buy")

	# Reject invalid quantities, unknown goods, and deprecated credits-only wallets
	for bad_qty in [-3, 0, 1.5, NAN, INF]:
		var r := Economy.transact(port, wallet, "food", bad_qty, "buy", 100)
		_check(bool(r["ok"]) == false, "bad qty rejected")
	var bad_good := Economy.transact(port, wallet, "unobtainium", 1, "buy", 100)
	_check(bool(bad_good["ok"]) == false, "unknown good rejected")
	var credits_only_wallet := {"credits": 50000, "cargo": {}}
	var credits_tx := Economy.transact(port, credits_only_wallet, "food", 1, "buy", 100)
	_check(bool(credits_tx["ok"]) == false, "deprecated credits-only wallet rejected by transact")
	_check(Economy.total_coins([], [], [], [credits_only_wallet]) == 0, "deprecated credits key ignored by total_coins")
	_check(port == snap_port and wallet == snap_wallet, "no mutation after invalid calls")

	# Reject insufficient wallet coins
	wallet["coins"] = 50
	var broke_buy := Economy.transact(port, wallet, "iron", 1, "buy", 100)
	_check(bool(broke_buy["ok"]) == false, "insufficient coins rejected")
	_check(int(wallet["coins"]) == 50, "wallet coins unchanged")

	# Valid sell transfers port.cash -> wallet.coins
	var coins_mid := Economy.total_coins([port], [], [], [wallet])
	var unit_sell := Economy.price(port, "iron", "sell")
	var cash_before := int(port["cash"])
	var sell_res := Economy.transact(port, wallet, "iron", 3, "sell", capacity)
	_check(bool(sell_res["ok"]) == true, "valid iron sell succeeds")
	_check(int(sell_res["qty"]) == 3 and int(sell_res["coins"]) == unit_sell * 3, "sell qty and coins match")
	_check(int(wallet["coins"]) == 50 + unit_sell * 3, "wallet coins increased")
	_check(float(wallet["cargo"]["iron"]) == 2.0, "wallet cargo iron decreased")
	_check(int(port["cash"]) == cash_before - unit_sell * 3, "port cash decreased")
	_check(float(port["stocks"]["iron"]) == 18.0, "port iron stock increased")
	_check(Economy.total_coins([port], [], [], [wallet]) == coins_mid, "sell conserves exact total coins")

	# Reject selling when port lacks cash
	port["cash"] = 10
	var snap_port_sell := port.duplicate(true)
	var snap_wallet_sell := wallet.duplicate(true)
	var poor_sell := Economy.transact(port, wallet, "iron", 2, "sell", capacity)
	_check(bool(poor_sell["ok"]) == false, "poor port sell rejected")
	_check(port == snap_port_sell and wallet == snap_wallet_sell, "no mutation on failed sell")

	# Preserve fractional existing balances on buy/sell and conserve total stock + coins
	var frac_port := Economy.create_port({
		"id": "frac_port",
		"name": "Fractional Port",
		"industry": "fishery",
		"population": 1200,
		"cash": 10000
	})
	frac_port["stocks"]["food"] = 150.25
	var frac_wallet := {
		"coins": 5000,
		"cargo": {"food": 9.6}
	}
	var total_food_before := float(frac_port["stocks"]["food"]) + float(frac_wallet["cargo"]["food"])
	var total_coins_frac := Economy.total_coins([frac_port], [], [], [frac_wallet])

	var frac_buy := Economy.transact(frac_port, frac_wallet, "food", 2, "buy", 100)
	_check(bool(frac_buy["ok"]) == true, "fractional balance buy 2 succeeds")
	_check(is_equal_approx(float(frac_wallet["cargo"]["food"]), 11.6), "buy 2 preserves .6 fractional cargo balance (11.6)")
	_check(is_equal_approx(float(frac_port["stocks"]["food"]), 148.25), "buy 2 preserves .25 fractional port balance (148.25)")
	_check(is_equal_approx(float(frac_port["stocks"]["food"]) + float(frac_wallet["cargo"]["food"]), total_food_before), "buy 2 conserves total food")
	_check(Economy.total_coins([frac_port], [], [], [frac_wallet]) == total_coins_frac, "buy 2 conserves total coins")

	var frac_sell := Economy.transact(frac_port, frac_wallet, "food", 4, "sell", 100)
	_check(bool(frac_sell["ok"]) == true, "fractional balance sell 4 succeeds")
	_check(is_equal_approx(float(frac_wallet["cargo"]["food"]), 7.6), "sell 4 preserves .6 fractional cargo balance (7.6)")
	_check(is_equal_approx(float(frac_port["stocks"]["food"]), 152.25), "sell 4 preserves .25 fractional port balance (152.25)")
	_check(is_equal_approx(float(frac_port["stocks"]["food"]) + float(frac_wallet["cargo"]["food"]), total_food_before), "sell 4 conserves total food")
	_check(Economy.total_coins([frac_port], [], [], [frac_wallet]) == total_coins_frac, "sell 4 conserves total coins")


func _test_recruit_scarcity_and_purses() -> void:
	var port := Economy.create_port({
		"id": "harbor_a",
		"name": "Harbor A",
		"population": 1000,
		"industry": "fishery",
		"workers": 100,
		"workforce": 100,
		"recruits": 20
	})
	# Abundant recruits (>= 16): ordinary cash advance = 10 sailor wage-days = 1000 coins
	var abundant_cost := Economy.recruit_cost(port, 1)
	_check(abundant_cost == 1000, "abundant recruit cost is 10 sailor wage-days (1000 coins)")

	port["recruits"] = 2
	var scarce_cost := Economy.recruit_cost(port, 1)
	_check(scarce_cost > abundant_cost and scarce_cost <= 1200, "scarce recruit cost has >0% and <=20% scarcity premium: " + str(scarce_cost))

	port["recruits"] = 6
	# Case 1: wallet has crewPurse -> payer.coins transfers into payer.crewPurse
	var wallet_with_purse := {"coins": 5000, "crewPurse": 200, "crew": 5}
	var coins_before_1 := Economy.total_coins([port], [], [], [wallet_with_purse])
	var hh_before_1 := int(port["householdPurse"])
	var r1 := Economy.recruit(port, wallet_with_purse, 2, 4)
	_check(bool(r1["ok"]) == true, "recruit with crewPurse succeeds")
	_check(int(wallet_with_purse["coins"]) == 5000 - int(r1["cost"]), "payer coins deducted")
	_check(int(wallet_with_purse["crewPurse"]) == 200 + int(r1["cost"]), "advance transferred to payer.crewPurse")
	_check(int(port["householdPurse"]) == hh_before_1, "port householdPurse untouched when payer has crewPurse")
	_check(int(port["recruits"]) == 4 and int(port["workforce"]) == 98, "recruits and authoritative workforce reduced by 2")
	_check(int(port["availableWorkers"]) == int(port["workforce"]) - int(port["workers"]) - int(port["publicWorkers"]), "availableWorkers equals idle remainder after recruit")
	_check(Economy.total_coins([port], [], [], [wallet_with_purse]) == coins_before_1, "recruit with crewPurse conserves total coins")

	# Case 2: wallet has no crewPurse -> payer.coins transfers into port.householdPurse
	var wallet_no_purse := {"coins": 5000, "crew": 5}
	var coins_before_2 := Economy.total_coins([port], [], [], [wallet_no_purse])
	var hh_before_2 := int(port["householdPurse"])
	var r2 := Economy.recruit(port, wallet_no_purse, 2, 4)
	_check(bool(r2["ok"]) == true, "recruit without crewPurse succeeds")
	_check(int(wallet_no_purse["coins"]) == 5000 - int(r2["cost"]), "payer coins deducted")
	_check(int(port["householdPurse"]) == hh_before_2 + int(r2["cost"]), "advance transferred to port.householdPurse")
	_check(int(port["recruits"]) == 2 and int(port["workforce"]) == 96, "recruits and workforce reduced to 2 and 96")
	_check(Economy.total_coins([port], [], [], [wallet_no_purse]) == coins_before_2, "recruit without crewPurse conserves total coins")

	# Reject over room, over pool, insufficient coins, credits-only wallet, and invalid counts without mutation
	var snap_port := port.duplicate(true)
	var snap_wallet := wallet_no_purse.duplicate(true)
	_check(not bool(Economy.recruit(port, wallet_no_purse, 2, 1)["ok"]), "over room rejected")
	_check(not bool(Economy.recruit(port, wallet_no_purse, 5, 10)["ok"]), "over recruit pool rejected")
	_check(not bool(Economy.recruit(port, {"credits": 9000}, 1, 10)["ok"]), "credits-only wallet rejected by recruit")
	for bad_cnt in [0, -1, 1.5, NAN, INF]:
		_check(not bool(Economy.recruit(port, wallet_no_purse, bad_cnt, 10)["ok"]), "invalid count rejected")
	_check(port == snap_port and wallet_no_purse == snap_wallet, "no mutation on failed recruit calls")

	# NPC starter sailor workforce decrement persists across ticks (authoritative workforce)
	Economy.decrement_workforce(port, 6)
	_check(int(port["workforce"]) == 90, "NPC starter sailor decrement reduces workforce to 90")
	Economy.tick_ports([port], 5.0)
	_check(int(port["workforce"]) == 90, "civilian workforce stays fixed at 90 after sailors leave (no automatic refill)")

	# Malformed/external recruit pool with recruits > workforce: require q <= min(recruits, workforce) before mutation
	port["workforce"] = 2
	port["workers"] = 2
	port["recruits"] = 8
	var snap_malformed_port := port.duplicate(true)
	var phantom_wallet := {"coins": 20000, "crew": 5}
	var snap_phantom_wallet := phantom_wallet.duplicate(true)
	var phantom_hire := Economy.recruit(port, phantom_wallet, 3, 10)
	_check(not bool(phantom_hire["ok"]), "recruit rejects q > min(recruits, workforce) when recruits > workforce")
	_check(port == snap_malformed_port and phantom_wallet == snap_phantom_wallet, "no mutation when recruits > workforce hire is rejected")

	# Valid hire within min(recruits, workforce) succeeds and reduces authoritative workforce by exact hire count q
	var wf_before_hire := int(port["workforce"])
	var coins_before_3 := Economy.total_coins([port], [], [], [phantom_wallet])
	var valid_capped_hire := Economy.recruit(port, phantom_wallet, 2, 10)
	_check(bool(valid_capped_hire["ok"]) == true, "recruit succeeds when q <= min(recruits, workforce)")
	_check(int(valid_capped_hire["count"]) == 2, "hired count is 2")
	_check(wf_before_hire - int(port["workforce"]) == int(valid_capped_hire["count"]), "authoritative workforce delta equals exact hired count (2 -> 0)")
	_check(int(port["workforce"]) == 0 and int(port["recruits"]) == 0 and int(port["workers"]) == 0, "workforce, recruits, and workers clamped at 0 after hiring remaining 2 workforce")
	_check(Economy.total_coins([port], [], [], [phantom_wallet]) == coins_before_3, "capped workforce hire conserves total coins")

	# External recruits > 0 when workforce == 0 cannot hire phantom crew
	port["recruits"] = 5
	var snap_zero_wf_port := port.duplicate(true)
	var snap_zero_wf_wallet := phantom_wallet.duplicate(true)
	var zero_wf_hire := Economy.recruit(port, phantom_wallet, 1, 10)
	_check(not bool(zero_wf_hire["ok"]), "recruit rejects hire when workforce == 0 even if recruits > 0")
	_check(port == snap_zero_wf_port and phantom_wallet == snap_zero_wf_wallet, "no mutation when workforce == 0 hire is rejected")

	# Volunteer pool recovery from zero, fractional remainder accumulation, workforce constancy, idle/workforce bounds, and coin invariance
	var vol_port := Economy.create_port({
		"id": "kelp_volunteer",
		"name": "Kelp Volunteer Reach",
		"industry": "fishery",
		"workforce": 150,
		"recruits": 0
	})
	var vol_target := mini(150, ceili(150.0 * 0.06)) # 9
	var vol_coins_init := Economy.port_coins(vol_port)
	_check(int(vol_port["recruits"]) == 0, "volunteer test port starts with 0 recruits")

	# Day 1: 150 * 0.01 = 1.5 -> 1 volunteer, 0.5 remainder
	Economy.tick_ports([vol_port], 1.0, {"interport_trade": false})
	_check(int(vol_port["recruits"]) == 1, "day 1 volunteer pool gains 1 from 1.5 rate")
	_check(is_equal_approx(float(vol_port["recruitRemainder"]), 0.5), "day 1 accumulates 0.5 fractional volunteer remainder")
	_check(int(vol_port["workforce"]) == 150, "day 1 volunteering keeps authoritative workforce constant at 150")
	_check(Economy.port_coins(vol_port) == vol_coins_init, "day 1 volunteering conserves exact port coins")

	# Day 2: 0.5 + 1.5 = 2.0 -> +2 volunteers (total 3), 0.0 remainder
	Economy.tick_ports([vol_port], 1.0, {"interport_trade": false})
	_check(int(vol_port["recruits"]) == 3, "day 2 volunteer pool reaches 3 using accumulated fractional remainder")
	_check(is_equal_approx(float(vol_port["recruitRemainder"]), 0.0), "day 2 fractional remainder consumed cleanly")
	_check(int(vol_port["workforce"]) == 150, "day 2 authoritative workforce remains 150")
	_check(Economy.port_coins(vol_port) == vol_coins_init, "day 2 volunteering conserves exact port coins")

	# Days 3..8: recovers up to target 9 and caps at target
	Economy.tick_ports([vol_port], 6.0, {"interport_trade": false})
	_check(int(vol_port["recruits"]) == vol_target, "volunteer pool recovers from zero to target ceili(150 * 0.06) = 9 and caps there")
	_check(is_equal_approx(float(vol_port["recruitRemainder"]), 0.0), "volunteer remainder resets at target cap")
	_check(int(vol_port["workforce"]) == 150, "workforce remains constant at 150 after full volunteer recovery")
	_check(Economy.port_coins(vol_port) == vol_coins_init, "full volunteer recovery conserves exact port coins")

	# Bound when no idle workers (availableWorkers == 0)
	var no_idle_port := Economy.create_port({
		"id": "no_idle_harbor",
		"industry": "foundry",
		"workforce": 120,
		"availableWorkers": 0,
		"recruits": 0
	})
	var no_idle_coins := Economy.port_coins(no_idle_port)
	Economy.replenish_volunteers(no_idle_port, 5.0)
	_check(int(no_idle_port["availableWorkers"]) == 0, "no-idle port keeps 0 availableWorkers")
	_check(int(no_idle_port["recruits"]) == 0, "volunteer pool remains 0 when no idle workers exist")
	_check(int(no_idle_port["workforce"]) == 120, "no-idle port workforce stays constant at 120")
	_check(Economy.port_coins(no_idle_port) == no_idle_coins, "no-idle port conserves exact coins")

	# Bound when partial idle workers < target (e.g. 4 idle workers < ceili(200 * 0.06) = 12)
	var low_idle_port := Economy.create_port({
		"id": "low_idle_harbor",
		"industry": "foundry",
		"workforce": 200,
		"availableWorkers": 4,
		"recruits": 0
	})
	var low_idle_coins := Economy.port_coins(low_idle_port)
	Economy.replenish_volunteers(low_idle_port, 6.0)
	_check(int(low_idle_port["availableWorkers"]) == 4, "low-idle port keeps 4 availableWorkers")
	_check(int(low_idle_port["recruits"]) == 4, "volunteer pool is bounded by idle availableWorkers (4 < 12)")
	_check(int(low_idle_port["workforce"]) == 200, "low-idle port workforce stays constant at 200")
	_check(Economy.port_coins(low_idle_port) == low_idle_coins, "low-idle port conserves exact coins")

	# Bound when zero workforce (workforce == 0)
	var zero_wf_vol := Economy.create_port({
		"id": "zero_wf_harbor",
		"industry": "timber",
		"workforce": 0,
		"workers": 0,
		"recruits": 0
	})
	var zero_wf_coins := Economy.port_coins(zero_wf_vol)
	Economy.tick_ports([zero_wf_vol], 5.0, {"interport_trade": false})
	_check(int(zero_wf_vol["workforce"]) == 0 and int(zero_wf_vol["availableWorkers"]) == 0 and int(zero_wf_vol["recruits"]) == 0, "zero-workforce port keeps 0 recruits and 0 workforce across ticks")
	_check(Economy.port_coins(zero_wf_vol) == zero_wf_coins, "zero-workforce port conserves exact coins")


func _test_daily_upkeep() -> void:
	var ship := {
		"id": "skiff_1",
		"name": "Midge Skiff",
		"crew": 5,
		"size": 14,
		"speed": 95
	}
	var snap_ship := ship.duplicate(true)
	var upkeep := Economy.daily_upkeep([ship])
	_check(ship == snap_ship, "daily_upkeep does not mutate ship")
	_check(int(upkeep["wages"]) == 500, "daily_upkeep wages = 100 cash per living crew/day (5 * 100 = 500)")
	_check(is_equal_approx(float(upkeep["food"]), 0.40), "daily_upkeep food = 0.08 per crew/day (5 * 0.08 = 0.40)")
	_check(float(upkeep["fuel"]) >= 0.1 and float(upkeep["fuel"]) <= 0.2, "daily_upkeep fuel in 0.1..0.2 per hull/day")


func _test_wage_recipients_zero_cash_and_missing_inputs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	# 1. Actual wage recipients and purse flows in a well-supplied shipyard
	var yard := Economy.create_port({
		"id": "yard_fed",
		"name": "Fed Yard",
		"industry": "shipyard",
		"population": 1600
	})
	for g in Economy.GOOD_KEYS:
		yard["stocks"][g] = 120.0
	var yard_coins_before := Economy.port_coins(yard)
	Economy.tick_ports([yard], 1.0, {"rng": rng, "interport_trade": false})
	_check(Economy.port_coins(yard) == yard_coins_before, "single-port tick conserves exact total coins")
	var payroll: Dictionary = yard["lastPayroll"]
	_check(int(payroll["business"]) > 0, "businesses paid positive recipe payroll")
	_check(int(payroll["household"]) > 0, "ordinary workers received wages into householdPurse")
	_check(int(payroll["expert"]) > 0, "specialists received wages into expertPurse")
	_check(int(payroll["public"]) > 0, "government paid publicWorkers")
	_check(int(payroll["tax"]) > 0, "government collected wage taxes")
	var emp: Dictionary = yard["employed"]
	_check(int(emp["mechanic"]) > 0 and int(emp["engineer"]) > 0 and int(emp["gunsmith"]) > 0 and int(emp["carpenter"]) > 0, "shipyard employed mechanics, engineers, gunsmiths, and carpenters")
	_check(float(yard["lastProduction"]["engines"]) > 0.0 and float(yard["lastProduction"]["guns"]) > 0.0 and float(yard["lastProduction"]["supplies"]) > 0.0, "fed shipyard produced engines, guns, and supplies")
	_check(float(yard["stocks"]["iron"]) < 120.0 and float(yard["stocks"]["copper"]) < 120.0, "fed shipyard depleted real iron and copper inputs")

	# Verify paid occupations across timber, foundry, refinery, and fishery ports
	var timber_p := Economy.create_port({"id": "t_p", "industry": "timber", "population": 1200})
	var foundry_p := Economy.create_port({"id": "f_p", "industry": "foundry", "population": 1400})
	var refinery_p := Economy.create_port({"id": "r_p", "industry": "refinery", "population": 1400})
	var fishery_p := Economy.create_port({"id": "fi_p", "industry": "fishery", "population": 1200})
	var ind_ports := [timber_p, foundry_p, refinery_p, fishery_p]
	var ind_coins_before := Economy.total_coins(ind_ports)
	Economy.tick_ports(ind_ports, 1.0, {"rng": rng, "interport_trade": false})
	_check(Economy.total_coins(ind_ports) == ind_coins_before, "industry occupation test ports conserve coins")
	_check(int(timber_p["employed"]["woodcutter"]) > 0 and int(timber_p["employed"]["carpenter"]) > 0 and int(timber_p["employed"]["charcoal burner"]) > 0, "timber port pays woodcutters, carpenters, and charcoal burners")
	_check(int(foundry_p["employed"]["miner"]) > 0 and int(foundry_p["employed"]["smelter"]) > 0 and int(foundry_p["employed"]["gunsmith"]) > 0, "foundry port pays miners, smelters, and gunsmiths")
	_check(int(refinery_p["employed"]["miner"]) > 0 and int(refinery_p["employed"]["refiner"]) > 0 and int(refinery_p["employed"]["powder worker"]) > 0, "refinery port pays miners, refiners, and powder workers")
	_check(int(fishery_p["employed"]["fisher"]) > 0, "fishery port pays fishers")

	# 2. Missing inputs prevent production and report shortages
	var starved_yard := Economy.create_port({
		"id": "yard_starved",
		"name": "Starved Yard",
		"industry": "shipyard",
		"population": 1600
	})
	starved_yard["stocks"]["iron"] = 0.0
	starved_yard["stocks"]["copper"] = 0.0
	starved_yard["stocks"]["timber"] = 0.0
	var starved_coins_before := Economy.port_coins(starved_yard)
	Economy.tick_ports([starved_yard], 1.0, {"rng": rng, "interport_trade": false})
	_check(Economy.port_coins(starved_yard) == starved_coins_before, "starved yard conserves exact total coins")
	_check(float(starved_yard["lastProduction"]["engines"]) == 0.0, "starved yard produces 0 engines without iron/copper")
	_check(float(starved_yard["lastProduction"]["guns"]) == 0.0, "starved yard produces 0 guns without iron/copper/timber")
	_check(float(starved_yard["lastProduction"]["supplies"]) == 0.0, "starved yard produces 0 supplies without iron/timber")
	var sh: Array = starved_yard["shortages"]
	_check(sh.has("iron") and sh.has("timber"), "starved yard reports missing iron and timber in shortages")

	# 3. Zero-cash production limitation (no bailout cash invented, zero industrial production when cash == 0)
	var broke_port := Economy.create_port({
		"id": "broke_foundry",
		"name": "Broke Foundry",
		"industry": "foundry",
		"population": 1400,
		"cash": 0,
		"householdPurse": 0,
		"expertPurse": 0,
		"governmentPurse": 0
	})
	Economy.tick_ports([broke_port], 1.0, {"rng": rng, "interport_trade": false})
	_check(Economy.port_coins(broke_port) == 0, "broke port invents zero bailout coins")
	_check(int(broke_port["lastPayroll"]["business"]) == 0, "broke port pays 0 business wages")
	_check(int(broke_port["workers"]) == 0, "broke port employs 0 industrial workers")
	for g in Economy.GOOD_KEYS:
		_check(float(broke_port["lastProduction"][g]) == 0.0, "broke port produces 0 " + g)
	_check((broke_port["shortages"] as Array).has("cash"), "broke port reports cash shortage")


func _test_worker_isolation_and_thread_snapshot() -> void:
	var zero_worker_port := Economy.create_port({
		"id": "ghost_harbor",
		"name": "Ghost Harbor",
		"industry": "timber",
		"population": 1200,
		"workers": 0,
		"workforce": 0
	})
	var ghost_coins := Economy.port_coins(zero_worker_port)
	Economy.tick_ports([zero_worker_port], 1.0)
	_check(Economy.port_coins(zero_worker_port) == ghost_coins, "zero-worker port conserves coins")
	for g in Economy.GOOD_KEYS:
		_check(float(zero_worker_port["lastProduction"][g]) == 0.0, "zero-worker port produces 0 " + g)
	_check((zero_worker_port["shortages"] as Array).has("workers"), "zero-worker port flags workers shortage")

	# WorkerThreadPool snapshot isolation
	var orig_ports := [
		Economy.create_port({"id": "p1", "name": "Harbor One", "industry": "fishery", "population": 1200}),
		Economy.create_port({"id": "p2", "name": "Harbor Two", "industry": "foundry", "population": 1500})
	]
	var orig_before := Economy.clone_ports(orig_ports)
	var worker_snapshot := Economy.snapshot_ports(orig_ports)
	var snap_coins_before := Economy.total_coins(worker_snapshot)

	var task_id := WorkerThreadPool.add_task(func() -> void:
		var local_rng := RandomNumberGenerator.new()
		local_rng.seed = 777
		for _step in range(4):
			Economy.tick_ports(worker_snapshot, 0.25, {"rng": local_rng})
	)
	WorkerThreadPool.wait_for_task_completion(task_id)

	_check(orig_ports == orig_before, "main-thread ports untouched while background task ticked snapshot")
	_check(worker_snapshot != orig_before, "background worker snapshot advanced over fractional days")
	_check(Economy.total_coins(worker_snapshot) == snap_coins_before, "background fractional-day ticks conserved exact total coins")


func _test_365_day_coin_conservation_and_stability() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261020
	var port_defs := [
		{"id": "p_fish", "name": "Gull Spit", "faction": "reed", "x": 260, "y": 340, "population": 1100, "industry": "fishery", "wealth": 0.9},
		{"id": "p_agri", "name": "Silt Terrace", "faction": "reed", "x": 520, "y": 420, "population": 1600, "industry": "agriculture", "wealth": 1.1},
		{"id": "p_timb", "name": "Cedar Reach", "faction": "compact", "x": 780, "y": 300, "population": 1300, "industry": "timber", "wealth": 1.0},
		{"id": "p_foun", "name": "Cinder Quay", "faction": "forge", "x": 1180, "y": 600, "population": 1900, "industry": "foundry", "wealth": 1.3},
		{"id": "p_refi", "name": "Shale Point", "faction": "forge", "x": 1460, "y": 780, "population": 1500, "industry": "refinery", "wealth": 1.2},
		{"id": "p_yard", "name": "Brass Slipway", "faction": "compact", "x": 1750, "y": 540, "population": 2100, "industry": "shipyard", "wealth": 1.4},
		{"id": "p_trad", "name": "Lantern Bight", "faction": "compact", "x": 980, "y": 920, "population": 2200, "industry": "trade", "wealth": 1.5},
		{"id": "p_raid", "name": "Wreckers Cove", "faction": "raiders", "x": 2100, "y": 1200, "population": 950, "industry": "fishery", "specialty": "ammo", "wealth": 0.85},
		{"id": "p_iron", "name": "Anvil Narrows", "faction": "forge", "x": 1620, "y": 1120, "population": 1700, "industry": "foundry", "specialty": "engines", "wealth": 1.25}
	]
	var ports: Array = []
	for d in port_defs:
		ports.append(Economy.create_port(d))

	# Carve player wallet, NPC owner purse, and buildQueue construction escrow out of existing port purses so global coin stock is seeded from world creation only
	var player_wallet := {"coins": 25000, "crewPurse": 5000, "crew": 5, "cargo": {}}
	ports[6]["cash"] = int(ports[6]["cash"]) - 30000
	Economy.decrement_workforce(ports[6], 5)

	var npc_owners := [
		{"id": "patrol-1", "coins": 40000, "crewPurse": 10000}
	]
	ports[5]["governmentPurse"] = int(ports[5]["governmentPurse"]) - 50000
	Economy.decrement_workforce(ports[5], 8)

	var construction_orders := [
		{"id": "order-1", "escrow": 35000}
	]
	ports[5]["cash"] = int(ports[5]["cash"]) - 35000
	ports[5]["buildQueue"] = construction_orders

	var initial_global_coins := Economy.total_coins(ports, npc_owners, [], [player_wallet])
	var initial_workforces: Dictionary = {}
	for p in ports:
		initial_workforces[p["id"]] = int(p["workforce"])

	for day in range(1, 366):
		var blockaded := ["p_raid"] if (day >= 100 and day <= 140) else []
		var ev := Economy.tick_ports(ports, 1.0, {"blockaded": blockaded, "rng": rng})
		_check(ev.size() > 0, "day %d returned events" % day)

		if day == 50:
			var buy_r := Economy.transact(ports[1], player_wallet, "food", 5, "buy", 100)
			_check(bool(buy_r["ok"]), "day 50 player food buy succeeded")
		elif day == 120:
			var sell_r := Economy.transact(ports[3], player_wallet, "food", 5, "sell", 100)
			_check(bool(sell_r["ok"]), "day 120 player food sell succeeded")
		elif day == 200:
			var rec_r := Economy.recruit(ports[6], player_wallet, 2, 10)
			_check(bool(rec_r["ok"]), "day 200 player recruit succeeded")
			initial_workforces["p_trad"] -= 2

		var day_coins := Economy.total_coins(ports, npc_owners, construction_orders, [player_wallet])
		_check(day_coins == initial_global_coins, "day %d exact global coin conservation (%d == %d)" % [day, day_coins, initial_global_coins])

		for p in ports:
			_check(int(p["cash"]) > 0, "day %d %s business cash > 0" % [day, str(p["id"])])
			_check(int(p["householdPurse"]) > 0, "day %d %s householdPurse > 0" % [day, str(p["id"])])
			_check(int(p["expertPurse"]) > 0, "day %d %s expertPurse > 0" % [day, str(p["id"])])
			_check(int(p["governmentPurse"]) > 0, "day %d %s governmentPurse > 0" % [day, str(p["id"])])
			_check(int(p["workforce"]) == int(initial_workforces[p["id"]]), "day %d %s fixed civilian workforce conserved" % [day, str(p["id"])])
			_check((p["ledger"] as Array).size() <= Economy.MAX_LEDGER_ENTRIES, "day %d %s ledger bounded" % [day, str(p["id"])])
			for g in Economy.GOOD_KEYS:
				var s := float(p["stocks"][g])
				_check(s >= 0.0 and not is_nan(s) and not is_inf(s), "day %d %s %s stock valid" % [day, str(p["id"]), g])

	# Verify regional specialization pricing after 365 days
	_check(Economy.price(ports[1], "food", "buy") < Economy.price(ports[3], "food", "buy"), "agriculture food cheaper than foundry after 365d")
	_check(Economy.price(ports[2], "timber", "buy") < Economy.price(ports[4], "timber", "buy"), "timber cheaper at timber port than refinery after 365d")
	_check(Economy.price(ports[3], "iron", "buy") < Economy.price(ports[1], "iron", "buy"), "iron cheaper at foundry than agriculture after 365d")
	_check(Economy.price(ports[4], "fuel", "buy") < Economy.price(ports[1], "fuel", "buy"), "fuel cheaper at refinery than agriculture after 365d")
	_check(Economy.price(ports[5], "engines", "buy") < Economy.price(ports[1], "engines", "buy"), "engines cheaper at shipyard than agriculture after 365d")
