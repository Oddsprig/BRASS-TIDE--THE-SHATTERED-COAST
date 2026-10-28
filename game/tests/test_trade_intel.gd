extends SceneTree
## Unrun by the helper. Root runs this headless after integration.
const T = preload("res://scripts/trade_intel.gd")
const Economy = preload("res://scripts/economy.gd")
const Damage = preload("res://scripts/damage.gd")
const Factions = preload("res://scripts/factions.gd")
const Goods = preload("res://scripts/goods.gd")
const Money = preload("res://scripts/money.gd")

var checks: int = 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("FAIL trade intel: " + msg)
		assert(cond, msg)
		quit(1)
		return
	checks += 1


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	_test_dated_observation_hides_live_remote()
	_test_estimates_do_not_move_goods_or_coins()
	_test_freight_limits_local_buy()
	_test_blockade_follows_owner_state()
	_test_player_intervention_and_hostility()
	_test_save_roundtrip_and_bounds()
	_test_meaningful_need_and_margin053()
	_test_quantity_constraints053()
	_test_preparation_is_not_shared_fuel053()
	var elapsed := Time.get_ticks_msec() - started
	_check(elapsed < 60000, "trade intel checks finished under 60s (%d ms)" % elapsed)
	print("ALL TRADE INTEL TESTS PASSED (%d checks in %d ms)" % [checks, elapsed])
	quit(0)


func _spec(cargo: float, speed: float) -> Dictionary:
	return {
		"id": "skiff", "hp": 100.0, "crewMin": 1, "crewOptimal": 5, "crewMax": 6,
		"size": 10.0, "speed": speed, "cargo": cargo, "fuelUse": 1.0,
		"fuelCapacity": 80.0, "kitCapacity": 20.0, "ammoCapacity": 80.0,
	}


func _boat(cargo: float, speed: float, crew: int) -> Dictionary:
	return Damage.create_ship(_spec(cargo, speed), {"crew": crew, "fuel": 30.0, "ammo": 40.0, "supplies": 10.0})


func _port(id: String, x: float, faction: String) -> Dictionary:
	var stocks := {}
	for good in Economy.GOOD_KEYS:
		stocks[good] = 0
	return {
		"id": id, "name": id, "faction": faction, "x": x, "y": 0.0,
		"cash": 4000, "householdPurse": 10, "expertPurse": 10, "governmentPurse": 10,
		"industry": "trade", "specialty": "timber", "population": 1200, "wealth": 1.0,
		"stocks": stocks, "blockaded": false,
	}


func _purse(state: Dictionary) -> int:
	var total := int(state.get("coins", 0)) + int(state.get("crewPurse", 0))
	for port in state.get("ports", []):
		total += int(port.get("cash", 0)) + int(port.get("householdPurse", 0)) + int(port.get("expertPurse", 0)) + int(port.get("governmentPurse", 0))
		for good in port.get("stocks", {}).keys():
			total += int(floor(float(port.stocks[good])))
	for owner in state.get("fleetOwners", []):
		total += int(owner.get("coins", 0)) + int(owner.get("crewPurse", 0))
	for good in state.get("cargo", {}).keys():
		total += int(floor(float(state.cargo[good])))
	return total


func _test_dated_observation_hides_live_remote() -> void:
	var harbor := _port("harbor", 0.0, "compact")
	var mill := _port("mill", 46500.0, "forge")
	mill.stocks.timber = 1
	mill.cash = 90000
	var unseen := _port("cove", 20.0, "reed")
	unseen.cash = 424242
	unseen.stocks.timber = 7777
	var state := {"day": 9, "coins": 1100, "crewPurse": 0, "ports": [harbor, mill, unseen], "fleet": [], "cargo": {}, "position": {"x": 0.0, "y": 0.0}}
	var before := _purse(state)
	var noted: Dictionary = T.observe(state, mill, 4)
	_check(noted.ok and noted.seen and noted.day == 4, "a visit records the day")
	_check(_purse(state) == before, "observe does not mint or move purses")
	var first: Dictionary = T.report(state, "mill")
	_check(first.seen and int(first.age) == 5, "age is today minus the visit day")
	_check(abs(float(first.uncertainty) - 0.30) < 0.001, "uncertainty grows by 0.06 each day")
	_check(first.quote == "stale" and first.estimate and not first.guaranteed, "a stored quote is stale and not a promise")
	_check(int(first.stocks.timber) == 1 and first.scarcity.timber.band == "scarce", "scarcity uses the visited stock")
	_check(int(first.businessFunds) == 90000, "business funds are the visited cash purse")
	var visited_buy := int(first.buy.timber)
	mill.stocks.timber = 9999
	mill.cash = 7
	var again: Dictionary = T.report(state, "mill")
	_check(int(again.stocks.timber) == 1 and int(again.businessFunds) == 90000, "a later report does not read live remote stock or cash")
	_check(int(again.buy.timber) == visited_buy and visited_buy != int(Economy.price(mill, "timber", "buy")), "the stored buy quote is not the live remote price")
	var blind: Dictionary = T.report(state, "cove")
	_check(not blind.seen and blind.uncertainty == "unseen" and not blind.has("buy") and not blind.has("sell"), "an unvisited port has no quote")
	_check(JSON.stringify(blind).find("424242") < 0 and JSON.stringify(blind).find("7777") < 0, "unvisited live cash and stock stay out of the report")
	_check(T.report(state, "cove").source == "none", "unseen source is none")
	_check(_purse(state) == before - 1 + 9999 - 90000 + 7, "only the test fixture changed the mill purse")


func _test_estimates_do_not_move_goods_or_coins() -> void:
	var harbor := _port("harbor", 0.0, "compact")
	var mill := _port("mill", 46500.0, "forge")
	harbor.industry = "refinery"
	harbor.specialty = "fuel"
	for good in Economy.GOOD_KEYS:
		harbor.stocks[good] = 0
		mill.stocks[good] = 0
	mill.stocks.timber = 12
	mill.cash = 500000
	var boat := _boat(40.0, 100.0, 5)
	var state := {
		"day": 4, "coins": 25000, "crewPurse": 40, "ports": [harbor, mill],
		"fleet": [boat], "cargo": {"timber": 3}, "freight": {"good": "timber", "qty": 1},
		"position": {"x": 0.0, "y": 0.0}, "fleetOwners": [],
	}
	T.observe(state, mill, 4)
	var quoted: Dictionary = T.report(state, "mill")
	mill.stocks.timber = 9999
	mill.stocks.fuel = 5000
	mill.cash = 3
	var frozen := JSON.stringify(_without_intel(state))
	var purse := _purse(state)
	var rows: Array = T.opportunities(state)
	_check(JSON.stringify(_without_intel(state)) == frozen, "an estimate does not mutate campaign state")
	_check(_purse(state) == purse and int(state.cargo.timber) == 3 and int(mill.cash) == 3, "no coins, cargo, or remote cash move")
	_check(rows.size() == 1, "one destination with a real carried good")
	var row: Dictionary = rows[0]
	_check(row.mode == "carried" and row.good == "timber" and int(row.qty) == 3, "three owned timber lots are separate from the sealed freight ledger")
	_check(int(row.sellQuote) == int(quoted.sell.timber) and int(row.businessFunds) == 500000, "the sale uses the visit quote and visited funds")
	_check(int(row.sellQuote) != int(Economy.price(mill, "timber", "sell")), "the poisoned live sell price is not used")
	_check(row.estimate and not row.guaranteed and row.risk == "ESTIMATE" and not row.coinsMoved and not row.goodsMoved, "profit is marked as an estimate")
	_check(abs(float(row.distance) - 46500.0) < 0.01, "straight route distance")
	_check(abs(float(row.speed) - 155.0) < 0.01, "travel speed matches the campaign equation")
	_check(abs(float(row.days) - float(row.distance) / float(row.speed) / T.DAY_SECONDS * 2.0) < 0.000001, "days are the out-and-back sail")
	var upkeep: Dictionary = Economy.daily_upkeep(state.fleet)
	_check(int(upkeep.wages) == 500 and int(row.dailyWages) == 500, "five sailors cost 100 coins a day")
	_check(int(row.wageCost) == ceili(float(upkeep.wages) * float(row.days)), "wages use that daily cost for the round trip")
	var rate := (0.011 + 10.0 * 0.0002) * 1.0
	var seconds := float(row.distance) / float(row.speed) * 2.0
	_check(abs(float(row.fuelDrums) - rate * seconds) < 0.000001, "fuel burn uses the sailing equation")
	var local_fuel := int(Economy.price(harbor, "fuel", "buy"))
	_check(local_fuel != int(quoted.buy.fuel), "harbor fuel and the visited fuel quote differ")
	_check(int(row.fuelCost) == ceili(float(row.fuelDrums) * float(local_fuel)), "fuel is priced at the harbor counter")
	_check(int(row.fuelCost) != ceili(float(row.fuelDrums) * float(quoted.buy.fuel)), "fuel is not priced from the remote quote")
	_check(int(row.foodCost) == ceili(float(upkeep.food) * float(row.days) * float(Economy.price(harbor, "food", "buy"))), "rations use daily upkeep and the harbor food quote")
	_check(int(row.purchaseCost) == 0, "carried goods have no second purchase")
	_check(int(row.netProfit) == int(row.revenue) - int(row.purchaseCost) - int(row.wageCost) - int(row.fuelCost) - int(row.foodCost), "net is revenue minus the estimate")
	_check(int(row.spread) == int(row.sellQuote), "carried spread is the visited sell quote")
	_check(not bool(row.riskFlags.shortFuel), "the boat has fuel for this estimate")


func _test_freight_limits_local_buy() -> void:
	var harbor := _port("harbor", 0.0, "compact")
	var mill := _port("mill", 800.0, "forge")
	harbor.stocks.timber = 6
	mill.stocks.timber = 2
	mill.cash = 80000
	var state := {
		"day": 2, "coins": 100000, "ports": [harbor, mill], "fleet": [_boat(4.0, 90.0, 3)],
		"cargo": {}, "freight": {"good": "logs", "qty": 2}, "position": {"x": 0.0, "y": 0.0},
	}
	T.observe(state, mill, 2)
	var blocked: Array = T.opportunities(state)
	_check(blocked.is_empty(), "freight that fills the hold leaves no local purchase")
	state.freight = {}
	var open: Array = T.opportunities(state)
	_check(open.size() == 1 and open[0].mode == "local_buy" and open[0].good == "timber", "with room, the estimate buys local timber")
	_check(int(open[0].qty) == 2, "two timber lots fit the remaining hold")
	_check(int(harbor.stocks.timber) == 6 and int(state.coins) == 100000 and state.cargo.is_empty(), "the local buy is not executed")
	_check(int(open[0].purchaseCost) == int(open[0].buyQuote) * int(open[0].qty), "purchase cost is the local quote times quantity")
	_check(int(open[0].spread) == int(open[0].sellQuote) - int(open[0].buyQuote), "spread is the visited sell quote minus the local buy quote")


func _armed(id: String, hp: float) -> Dictionary:
	return Damage.create_ship({"id": id, "hp": hp, "crewMin": 1, "crewOptimal": 3, "crewMax": 4, "size": 16, "speed": 80, "cargo": 2}, {"crew": 3, "fuel": 8.0, "ammo": 40.0})


func _owner(id: String, faction: String, kind: String, boat: Dictionary) -> Dictionary:
	return {"id": id, "name": id, "faction": faction, "kind": kind, "active": true, "coins": 25, "crewPurse": 0, "boats": [boat], "atPort": "", "cargo": {}}


func _test_blockade_follows_owner_state() -> void:
	var harbor := _port("harbor", 0.0, "compact")
	var cove := _port("cove", 400.0, "reed")
	var raider_boat := _armed("lance", 80.0)
	var raider := _owner("raid-1", "raiders", "raider", raider_boat)
	var convoy := _owner("convoy-1", "compact", "trader", _armed("barge", 80.0))
	var story := _owner("story-2", "raiders", "raider", _armed("flag", 400.0))
	var patrol := {"id": "raid-1", "x": 20.0, "y": 0.0, "from": "cove", "to": "harbor", "progress": 0.5, "active": true, "hostile": true}
	var story_patrol := {"id": "story-2", "x": 400.0, "y": 0.0, "from": "cove", "to": "cove", "progress": 0.5, "active": true, "hostile": true}
	var state := {
		"day": 6, "coins": 500, "ports": [harbor, cove], "fleet": [], "cargo": {},
		"fleetOwners": [raider, story], "patrols": [patrol, story_patrol], "position": {"x": 2000.0, "y": 2000.0},
	}
	var purse := _purse(state)
	_check(T.blockades(state) == ["harbor"], "a supplied raider beside the harbor blockades it")
	_check(not T.blockades(state).has("cove"), "a story- owner does not establish a blockade")
	var opened: Array = T.update(state)
	_check(opened.size() == 1 and opened[0].portId == "harbor" and opened[0].cause == "established" and opened[0].active, "establishment is one event")
	_check(T.update(state).is_empty(), "a second look the same day adds no event")
	_check(harbor.blockaded == false and not harbor.has("ledger"), "update does not write the economy blockade flag or a ledger")
	raider_boat.fuel = 0.0
	var lost: Array = T.update(state)
	_check(lost.size() == 1 and lost[0].cause == "lost" and T.blockades(state).is_empty(), "no remaining fuel lifts the blockade")
	raider_boat.fuel = 8.0
	_check(T.update(state)[0].cause == "established", "refueled and still nearby, the blockade returns")
	patrol.x = 900.0
	var left: Array = T.update(state)
	_check(left.size() == 1 and left[0].cause == "withdrawn" and T.blockades(state).is_empty(), "sailing away lifts the blockade")
	patrol.x = 20.0
	T.update(state)
	state.fleetOwners.append(convoy)
	state.patrols.append({"id": "convoy-1", "x": 30.0, "y": 0.0, "from": "harbor", "to": "cove", "progress": 0.4, "active": true, "hostile": false})
	var with_convoy := _purse(state)
	var held: Array = T.update(state)
	_check(held.size() == 1 and held[0].cause == "contested" and T.blockades(state).is_empty(), "an equal convoy contests the harbor")
	_check(_purse(state) == with_convoy and with_convoy == purse + 25 and int(harbor.cash) == 4000 and int(raider.coins) == 25, "blockade changes move no coins")
	var docked := _port("spit", 0.0, "forge")
	var sitting := _owner("raid-9", "raiders", "raider", _armed("skiff", 80.0))
	sitting.atPort = "spit"
	var dock_state := {"day": 3, "coins": 10, "ports": [docked], "fleetOwners": [sitting], "patrols": [], "fleet": [], "cargo": {}}
	_check(T.blockades(dock_state) == ["spit"], "a supplied hostile owner at the dock blockades it without a patrol coordinate")


func _test_player_intervention_and_hostility() -> void:
	var harbor := _port("harbor", 0.0, "compact")
	var raider := _owner("raid-1", "raiders", "raider", _armed("lance", 80.0))
	var patrol := {"id": "raid-1", "x": 10.0, "y": 0.0, "active": true, "progress": 0.5, "from": "x", "to": "y"}
	var state := {
		"day": 2, "coins": 80, "ports": [harbor], "fleetOwners": [raider], "patrols": [patrol],
		"fleet": [], "cargo": {}, "position": {"x": 0.0, "y": 0.0},
	}
	var world := {"FACTIONS": [{"id": "compact"}, {"id": "raiders"}, {"id": "forge"}, {"id": "reed"}], "PORTS": [{"id": "harbor", "faction": "compact"}]}
	Factions.ensure(state, world)
	_check(T.blockades(state) == ["harbor"], "the raider holds the harbor before anyone intervenes")
	state.fleet = [_boat(10.0, 100.0, 4)]
	_check(T.blockades(state).is_empty(), "a supplied player fleet near the harbor contests it")
	for _i in 3:
		Factions.adjust(state, "compact", -25, "fired on the quay")
	_check(Factions.is_hostile(state, "compact"), "the fixture is now hostile to the harbor faction")
	_check(T.blockades(state) == ["harbor"], "a hostile player is not counted as a defender")
	_check(int(state.coins) == 80, "intervention checks do not mint coins")


func _test_save_roundtrip_and_bounds() -> void:
	var harbor := _port("harbor", 0.0, "compact")
	var mill := _port("mill", 500.0, "forge")
	mill.stocks.iron = 4
	mill.cash = 2222
	var raider := _owner("raid-1", "raiders", "raider", _armed("lance", 80.0))
	var patrol := {"id": "raid-1", "x": 15.0, "y": 0.0, "active": true, "progress": 0.5, "from": "mill", "to": "harbor"}
	var state := {
		"day": 8, "coins": 640, "ports": [harbor, mill], "fleet": [], "cargo": {"iron": 1},
		"fleetOwners": [raider], "patrols": [patrol], "position": {"x": 0.0, "y": 0.0},
	}
	T.observe(state, mill, 8)
	T.update(state)
	var raw := JSON.stringify(state)
	var restored = JSON.parse_string(raw)
	_check(restored is Dictionary, "state survives JSON")
	T.ensure(restored)
	var view: Dictionary = T.report(restored, "mill")
	_check(view.seen and int(view.stocks.iron) == 4 and int(view.businessFunds) == 2222 and int(view.age) == 0, "visited iron, funds, and day survive the round trip")
	_check(T.blockades(restored) == ["harbor"], "the living blockade survives the round trip")
	_check(str(restored.tradeIntel.blockades.harbor.cause) == "established", "the stored cause survives")
	_check(int(restored.coins) == 640, "coins survive untouched")
	var many := {"day": 1, "coins": 5, "ports": [], "fleet": [], "cargo": {}}
	for i in 20:
		var extra := _port("p%02d" % i, float(i) * 1000.0, "compact")
		extra.stocks.food = i + 1
		many.ports.append(extra)
		T.observe(many, extra, i + 1)
	_check(many.tradeIntel.observations.size() == T.MAX_OBSERVATIONS, "observations stay capped")
	_check(not many.tradeIntel.observations.has("p00") and many.tradeIntel.observations.has("p19"), "the oldest visits are dropped")
	var swing := _port("harbor", 0.0, "compact")
	var boat := _armed("lance", 80.0)
	var owner := _owner("raid-1", "raiders", "raider", boat)
	var gate := {"id": "raid-1", "x": 10.0, "y": 0.0, "active": true, "progress": 0.5, "from": "a", "to": "b"}
	var log_state := {"day": 4, "coins": 9, "ports": [swing], "fleetOwners": [owner], "patrols": [gate], "fleet": [], "cargo": {}}
	for i in 50:
		gate.x = 10.0 if i % 2 == 0 else 900.0
		T.update(log_state)
	_check(log_state.tradeIntel.events.size() == T.MAX_EVENTS, "blockade events stay capped at 40")
	_check(str(log_state.tradeIntel.events[0].cause) == "withdrawn", "the newest event is kept at the front")
	_check(int(log_state.coins) == 9 and int(swing.cash) == 4000 and int(owner.coins) == 25, "a long status log mints nothing")


func _without_intel(state: Dictionary) -> Dictionary:
	var copy: Dictionary = state.duplicate(true)
	copy.erase("tradeIntel")
	return copy


func _test_meaningful_need_and_margin053() -> void:
	# Controlled shortage fixture, not evidence of a normal-career profit.
	var harbor := _port("harbor", 0.0, "compact")
	var mill := Economy.create_port({"id": "mill", "industry": "timber", "population": 1200, "wealth": 1.0})
	mill.x = 800.0; mill.y = 0.0; mill.faction = "compact"
	mill.stocks.logs = 0.0; mill.shortages = ["logs"]
	var state := {"day": 7, "coins": 20000, "crewPurse": 0, "ports": [harbor, mill], "fleet": [_boat(40.0, 100.0, 5)], "cargo": {"logs": 3}, "position": {"x": 0.0, "y": 0.0}}
	T.observe(state, mill, 4)
	var saved: Dictionary = T.report(state, "mill")
	_check(saved.needs.has("logs"), "visited recipe input has a dated delivery purpose")
	var need: Dictionary = saved.needs.logs
	_check(float(need.observedNeed) > 0.0 and bool(need.shortageReported), "zero input and the actual reported shortage are recorded")
	_check(Goods.ITEMS.has(need.needOutput) and Goods.ITEMS[need.needOutput].inputs.has("logs") and not str(need.needPurpose).is_empty(), "delivery purpose names an actual output that consumes logs")
	mill.stocks.logs = 9999.0; mill.cash = 1; mill.industry = "refinery"; mill.shortages = []
	var frozen := JSON.stringify(state)
	var total := Money.total(state)
	var again: Dictionary = T.report(state, "mill")
	var rows: Array = T.opportunities(state)
	_check(again.needs == saved.needs and int(again.stocks.logs) == 0, "poisoned remote recipes, shortage, funds and stocks do not refresh the saved need")
	if rows.is_empty():
		_check(false, "carried logs produce a dated opportunity"); return
	var row: Dictionary = rows[0]
	_check(row.good == "logs" and int(row.observedDay) == 4 and int(row.quoteAge) == 3, "the opportunity identifies its carried input and exact observation day")
	_check(row.needOutput == need.needOutput and row.needPurpose == need.needPurpose and is_equal_approx(float(row.observedNeed), float(need.observedNeed)), "opportunity purpose comes from the visit rather than the live remote industry")
	_check(int(row.uncertaintyMargin) == ceili(float(row.revenue) * float(row.uncertainty)), "conservative margin derives from the existing quote-age sensitivity")
	_check(int(row.conservativeNetProfit) == int(row.netProfit) - int(row.uncertaintyMargin) and not str(row.uncertaintyBasis).is_empty(), "conservative estimate discloses its basis and subtracts the margin once")
	_check(int(row.netProfit) == int(row.revenue) - int(row.purchaseCost) - int(row.wageCost) - int(row.fuelCost) - int(row.foodCost), "nominal net still uses only nominal round-trip costs")
	_check(float(row.reserveDays) == 2.0 and int(row.contingencyCost) >= int(row.dailyWages) * 2, "two-day operating allowance remains separate from nominal net")
	_check(row.estimate and not row.guaranteed and not row.coinsMoved and not row.goodsMoved, "useful need and conservative margin still promise no return or transaction")
	_check(JSON.stringify(state) == frozen and Money.total(state) == total, "reports and opportunities preserve every field and actual purse")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(state))
	_check(T.report(restored, "mill").needs == saved.needs, "dated input purpose survives the existing save representation")
	restored.tradeIntel.observations.mill.erase("needs")
	_check(T.report(restored, "mill").needs.is_empty(), "legacy visits without need data do not invent a live remote purpose")


func _test_quantity_constraints053() -> void:
	var harbor := _port("harbor", 0.0, "compact")
	var mill := _port("mill", 800.0, "compact")
	harbor.stocks.timber = 6
	mill.cash = 80000
	var state := {"day": 2, "coins": 100000, "wageArrears": 0, "ports": [harbor, mill], "fleet": [_boat(8.0, 90.0, 3)], "cargo": {}, "position": {"x": 0.0, "y": 0.0}}
	T.observe(state, mill, 2)
	var row: Dictionary = T.opportunities(state)[0]
	_check(int(row.qty) == 4 and int(row.holdLimit) == 4 and int(row.localStockLimit) == 6, "real good weight bounds a local purchase before stock runs out")
	_check(not str(row.quantityLimitReason).is_empty() and int(row.qty) <= int(row.affordabilityLimit), "quantity exposes its limiting reason and captain funding bound")
	state.freight = {"good": "logs", "qty": 2}
	row = T.opportunities(state)[0]
	_check(int(row.qty) == 1 and int(row.holdLimit) == 1, "sealed freight reduces the same physical hold")
	state.freight = {}; harbor.stocks.timber = 1
	row = T.opportunities(state)[0]
	_check(int(row.qty) == 1 and int(row.localStockLimit) == 1, "one finite local lot bounds the advertised purchase")
	harbor.stocks.timber = 6
	mill.cash = int(T.report(state, "mill").sell.timber)
	T.observe(state, mill, 2)
	row = T.opportunities(state)[0]
	_check(int(row.qty) == 1 and int(row.buyerLiquidity) == 1, "one lot of observed buyer funds bounds quantity independently of hold and local stock")
	mill.cash = 0; T.observe(state, mill, 2)
	_check(T.opportunities(state).is_empty(), "an observed empty buyer purse cannot advertise a paid sale")
	mill.cash = 80000; T.observe(state, mill, 2)
	state.coins = 0
	_check(T.opportunities(state).is_empty(), "an empty captain purse cannot advertise an unfunded local purchase")


func _test_preparation_is_not_shared_fuel053() -> void:
	var harbor := _port("harbor", 0.0, "compact")
	var mill := _port("mill", 800.0, "compact")
	mill.cash = 80000
	var dry := _boat(8.0, 90.0, 3); dry.uid = "dry"; dry.fuel = 0.01
	var wet := _boat(8.0, 90.0, 3); wet.uid = "wet"
	var stored := _boat(200.0, 90.0, 3); stored.uid = "stored"; stored.storedPort = "harbor"
	var idle := _boat(200.0, 90.0, 3); idle.uid = "idle"; idle.mothballed = true
	var uncrewed := _boat(200.0, 90.0, 0); uncrewed.uid = "uncrewed"
	var state := {"day": 3, "coins": 0, "crewPurse": 1000, "wageArrears": 150, "ports": [harbor, mill], "fleet": [dry, wet, stored, idle, uncrewed], "cargo": {"timber": 1, "fuel": 0.5}, "position": {"x": 0.0, "y": 0.0}}
	T.observe(state, mill, 2)
	var frozen := JSON.stringify(state)
	var row: Dictionary = T.opportunities(state)[0]
	_check(is_equal_approx(float(row.freeCapacity), 13.5), "stored, mothballed and undercrewed boats lend no active hold")
	_check(row.boatFuel.size() == 2, "preparation exposes only the two traveling boats' tank rows")
	var dry_row: Dictionary = {}
	for boat in row.boatFuel:
		if str(boat.uid) == "dry": dry_row = boat
	_check(not dry_row.is_empty() and float(dry_row.get("fuelShortfall", 0)) > 0.0, "the dry boat keeps its own fuel shortfall despite its supplied companion")
	_check(float(row.looseFuel) == 0.5 and float(row.fuelShortfall) > 0.0 and row.riskFlags.shortFuel, "loose cargo drums and reserve boats do not silently fill a working tank")
	_check(float(row.foodRequired) > 0.0 and float(row.foodShortfall) > 0.0 and int(row.wageArrears) == 150, "real owned crew food and existing unpaid wages remain visible")
	_check(int(row.preparationCost) > 0 and int(row.fundingRequired) > 0 and int(row.fundingShortfall) > 0 and not row.preparationReady, "a carried-cargo estimate exposes missing preparation resources and funds")
	_check(row.riskFlags.shortFood and row.riskFlags.shortFunding and float(row.payloadAfterFood) <= float(row.freeCapacity), "risk fields expose food and funding gaps while preparation reserves real hold space")
	var finite: bool = true
	for key in ["qty", "distance", "days", "netProfit", "conservativeNetProfit", "uncertaintyMargin", "fundingRequired", "fundingShortfall", "foodRequired", "fuelShortfall", "payloadAfterFood", "allowanceOverload"]:
		finite = finite and is_finite(float(row[key]))
	_check(finite, "bounded finite fixture yields finite quantity, risk, cost and preparation observations")
	_check(not row.preparationWarnings.is_empty(), "unsafe preparation explains its actual shortages")
	_check(JSON.stringify(state) == frozen, "fuel, food, crew and purses stay untouched by the full preparation estimate")
