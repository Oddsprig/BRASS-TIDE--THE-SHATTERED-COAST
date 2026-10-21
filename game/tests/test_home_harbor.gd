extends SceneTree
const Campaign = preload("res://scripts/campaign.gd")
const HomeHarbor = preload("res://scripts/home_harbor.gd")
const Money = preload("res://scripts/money.gd")
var failures: Array = []
var checks: int = 0
var world: Dictionary
var c

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL " + message)

func home() -> Dictionary:
	return c.current_port()

func home_id() -> String:
	return str(home().id)

func stock_home() -> void:
	var p: Dictionary = home()
	for good in ["timber", "logs", "iron", "copper", "supplies"]:
		p.stocks[good] = 50.0
	p.workforce = 200
	p.workers = 100
	p.publicWorkers = 10
	p.availableWorkers = 90
	p.recruits = 50
	p.specialists = 20
	p.specialistWorkers = 20
	p.availableSpecialists = 10
	p.cash = 100000

func reset() -> void:
	c.new_game(123)
	HomeHarbor.ensure(c.state)
	stock_home()
	c.state.coins = 200000

func survey(site_id: String) -> void:
	c.state.exploration.sites[site_id]={"level":3,"rewarded":false}
	if site_id=="cinder_workshop_ruin":c.state.storyRights.workshopCharter=true
	else:c.state.storyRights.openField=true

# Root assumption under test locally: Money.total plus business purses.
func total_with_businesses() -> int:
	return Money.total(c.state)

func business() -> Dictionary:
	return c.state.businesses[0]

func _initialize() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c = Campaign.new(world)
	_test_warehouse_setup_and_transfers()
	_test_atomic_refusals_and_charters()
	_test_workshop_production_sales_dividend()
	_test_salvage_yard_and_starvation()
	_test_save_roundtrip()
	print("home_harbor: %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty():
		quit(0)
	else:
		quit(1)

func _test_warehouse_setup_and_transfers() -> void:
	reset()
	var p := home()
	var workforce_before: int = int(p.workforce)
	var recruits_before: int = int(p.recruits)
	var specialists_before: int = int(p.specialists)
	var timber_before: float = float(p.stocks.timber)
	var supply_before: int = total_with_businesses()
	var q: Dictionary = HomeHarbor.quote(c, "warehouse", home_id())
	check(bool(q.ok), "Warehouse quotes at the docked home harbor")
	check(int(q.workingCapitalDeposit) == 14 * 200 + 500, "Deposit is 14 wage-days plus input capital")
	var r: Dictionary = HomeHarbor.establish(c, "warehouse", home_id())
	check(bool(r.ok), "Warehouse establishes")
	check(total_with_businesses() == supply_before, "Setup and deposit conserve every coin")
	check(is_equal_approx(float(p.stocks.timber), timber_before - 4.0), "Setup consumes real timber stock")
	check(int(p.workforce) == workforce_before - 2 and int(p.recruits) == recruits_before - 2, "Two staff leave the port workforce and recruit pools")
	check(int(p.specialists) == specialists_before, "Warehouse staff are ordinary workers, not specialists")
	check(int(business().coins) == int(q.workingCapitalDeposit) and int(business().capitalIn) == int(q.workingCapitalDeposit), "Opening float is exactly the captain deposit")
	check((business().employees as Array).size() == 2, "Employees are stored on the business")
	check(str(business().homePort) == home_id(), "Business records its existing home port")
	check(not bool(HomeHarbor.establish(c, "warehouse", home_id()).ok), "The same kind cannot be established twice at one harbor")
	c.state.cargo.timber = 10.0
	var weight_before: float = c.cargo_weight()
	check(bool(HomeHarbor.transfer_goods(c, str(business().id), "timber", 4.0, "in").ok), "Real cargo stores ashore")
	check(is_equal_approx(float(c.state.cargo.timber), 6.0) and is_equal_approx(float(business().inventory.timber), 4.0), "Stored goods move out of the fleet hold")
	check(is_equal_approx(c.cargo_weight(), weight_before - 8.0), "Warehouse stock never counts as traveling hold weight")
	check(not bool(HomeHarbor.transfer_goods(c, str(business().id), "timber", 99.0, "in").ok), "Cannot store goods the fleet does not carry")
	c.state.cargo.logs = 300.0
	check(not bool(HomeHarbor.transfer_goods(c, str(business().id), "logs", 300.0, "in").ok), "Store capacity refuses 900 weight of logs")
	c.state.cargo.logs = 0.0
	var at_port: Dictionary = (c.state.position as Dictionary).duplicate(true)
	c.state.position = {"x": -5000.0, "y": -5000.0}
	check(not bool(HomeHarbor.transfer_goods(c, str(business().id), "timber", 1.0, "out").ok), "No shore transfers away from the home harbor")
	c.state.position = at_port
	check(bool(HomeHarbor.transfer_goods(c, str(business().id), "timber", 1.0, "out").ok), "Stored goods load back aboard at the dock")
	check(is_equal_approx(float(business().inventory.timber), 3.0), "Loading out drains the shore store")
	check(HomeHarbor.list_businesses(c.state).size() == 1, "list_businesses reports the warehouse")

func _test_atomic_refusals_and_charters() -> void:
	reset()
	var p := home()
	var stocks_before: Dictionary = (p.stocks as Dictionary).duplicate(true)
	var workforce_before: int = int(p.workforce)
	c.state.coins = 1
	check(not bool(HomeHarbor.establish(c, "warehouse", home_id()).ok), "Establishment refuses when the captain cannot pay setup plus deposit")
	check((c.state.businesses as Array).is_empty() and int(c.state.coins) == 1, "Broke refusal creates nothing")
	check((p.stocks as Dictionary) == stocks_before and int(p.workforce) == workforce_before, "Broke refusal leaves stocks and people untouched")
	c.state.coins = 200000
	p.stocks.timber = 0.0
	check(not bool(HomeHarbor.quote(c, "warehouse", home_id()).ok), "Setup refuses without physical timber")
	p.stocks.timber = 50.0
	p.availableWorkers = 0
	check(not bool(HomeHarbor.quote(c, "warehouse", home_id()).ok), "Setup refuses without available workers")
	p.availableWorkers = 90
	check(not bool(HomeHarbor.quote(c, "workshop", home_id()).ok), "Workshop charter refuses before its site is surveyed")
	check(not bool(HomeHarbor.quote(c, "salvage_yard", home_id()).ok), "Salvage charter refuses before a salvage site is surveyed")
	survey("cinder_workshop_ruin")
	check(bool(HomeHarbor.quote(c, "workshop", home_id()).ok), "Surveyed workshop ruin unlocks the workshop charter")
	check(not bool(HomeHarbor.quote(c, "salvage_yard", home_id()).ok), "Workshop survey does not unlock the salvage charter")
	check(not bool(HomeHarbor.quote(c, "warehouse", "nowhere_port").ok), "No businesses at ports that do not exist")
	check(not bool(HomeHarbor.quote(c, "warehouse", _other_port_id()).ok), "No establishment without real dock access")

func _other_port_id() -> String:
	for p in c.state.ports:
		if str(p.id) != home_id():
			return str(p.id)
	return ""

func _test_workshop_production_sales_dividend() -> void:
	reset()
	survey("cinder_workshop_ruin")
	var p := home()
	check(bool(HomeHarbor.establish(c, "workshop", home_id()).ok), "Workshop establishes under charter")
	var b := business()
	check(int(b.coins) == 14 * 525 + 1500, "Workshop float is 14 wage-days plus input capital")
	check(int(p.specialists) == 19, "The mechanic leaves the town specialist pool")
	c.state.cargo.timber = 1.6
	c.state.cargo.iron = 5.0
	check(bool(HomeHarbor.transfer_goods(c, str(b.id), "timber", 1.6, "in").ok), "Workshop takes in real timber")
	check(bool(HomeHarbor.transfer_goods(c, str(b.id), "iron", 5.0, "in").ok), "Workshop takes in real iron")
	p.stocks.supplies = 0.0
	var household_before: int = int(p.householdPurse)
	var expert_before: int = int(p.expertPurse)
	var cash_before: int = int(p.cash)
	var supply_before: int = total_with_businesses()
	HomeHarbor.tick(c, 1)
	check(is_equal_approx(float(b.inventory.get("timber", 0.0)), 0.0), "Production is limited by stored timber: exactly four kits of inputs")
	check(is_equal_approx(float(b.inventory.get("iron", 0.0)), 4.8), "Four kits consume 0.2 iron per the Goods recipe")
	check(is_equal_approx(float(p.stocks.supplies), 4.0), "The needing home port buys all four kits into its stocks")
	check(int(p.cash) < cash_before and int(b.revenue) == cash_before - int(p.cash), "Sale coins move port cash to the business, none minted")
	check(int(p.householdPurse) - household_before == 375 and int(p.expertPurse) - expert_before == 150, "Daily wages pay carpenters to household and the mechanic to expert purse")
	check(total_with_businesses() == supply_before, "Wages, production and sale conserve every coin")
	check(not bool(HomeHarbor.dividend(c, str(b.id), 999999).ok), "Dividend refuses beyond earned surplus above the reserve")
	var coins_before_dividend: int = int(c.state.coins)
	check(bool(HomeHarbor.dividend(c, str(b.id), 50).ok), "A modest earned dividend pays out")
	check(int(c.state.coins) == coins_before_dividend + 50 and total_with_businesses() == supply_before, "Dividend is a transfer, not a faucet")
	check(int(b.coins) >= 14 * 525 + 1500, "Business still holds its 14-day wage and input reserve")
	check(not bool(HomeHarbor.capital(c, str(b.id), 0).ok), "Zero capital is refused")
	check(bool(HomeHarbor.capital(c, str(b.id), 1000).ok), "Captain can add working capital")
	check(not bool(HomeHarbor.dividend(c, str(b.id), 100000).ok), "Fresh captain capital cannot be withdrawn as a dividend")
	c.state.cargo.timber = 4.0
	check(bool(HomeHarbor.transfer_goods(c, str(b.id), "timber", 4.0, "in").ok), "More timber stores for the liquidity check")
	p.cash = 0
	var revenue_before: int = int(b.revenue)
	var supply_liquidity: int = total_with_businesses()
	HomeHarbor.tick(c, 1)
	check(int(b.revenue) == revenue_before, "A port with no cash buys nothing")
	check(float(b.inventory.get("supplies", 0.0)) > 0.0, "Unsold kits stay in the workshop store")
	check(total_with_businesses() == supply_liquidity, "Liquidity-blocked tick still conserves coins")
	p.cash = 100000
	p.stocks.supplies = 1000.0
	revenue_before = int(b.revenue)
	HomeHarbor.tick(c, 1)
	check(int(b.revenue) == revenue_before, "A port at or above equilibrium needs no kits and buys none")

func _test_salvage_yard_and_starvation() -> void:
	reset()
	survey("rust_salvage_anchorage")
	var p := home()
	check(bool(HomeHarbor.establish(c, "salvage_yard", home_id()).ok), "Salvage yard establishes under charter")
	var b := business()
	c.state.cargo.iron = 3.0
	check(bool(HomeHarbor.transfer_goods(c, str(b.id), "iron", 3.0, "in").ok), "Stripped salvage iron from the hold stores in the yard")
	p.stocks.iron = 0.0
	var household_before: int = int(p.householdPurse)
	var expert_before: int = int(p.expertPurse)
	var supply_before: int = total_with_businesses()
	HomeHarbor.tick(c, 1)
	check(is_equal_approx(float(p.stocks.iron), 3.0) and is_equal_approx(float(b.inventory.get("iron", 0.0)), 0.0), "Yard sells stored salvage iron to the needing port")
	check(int(b.revenue) > 0 and total_with_businesses() == supply_before, "Salvage sale moves coins, never mints")
	check(int(p.householdPurse) - household_before == 300 and int(p.expertPurse) - expert_before == 150, "Yard wages split laborers and mechanic by tier")
	check((c.state.get("wrecks", []) as Array).is_empty(), "The yard never spawns free wrecks")
	b.coins = 10
	c.state.cargo.iron = 2.0
	check(bool(HomeHarbor.transfer_goods(c, str(b.id), "iron", 2.0, "in").ok), "More salvage stores before the starvation check")
	supply_before = total_with_businesses()
	HomeHarbor.tick(c, 1)
	check(bool(b.paused), "Unpaid wages pause the yard")
	check(int(b.arrearsHousehold) + int(b.arrearsExpert) == 450 - 10, "Wage shortfall is recorded as arrears, not forgiven")
	check(is_equal_approx(float(b.inventory.get("iron", 0.0)), 2.0), "Paused staff sell nothing")
	check(total_with_businesses() == supply_before, "Starved tick conserves coins")
	check(bool(HomeHarbor.capital(c, str(b.id), 5000).ok), "Captain capital can rescue the purse")
	p.stocks.iron = 0.0
	HomeHarbor.tick(c, 1)
	check(not bool(b.paused) and int(b.arrearsHousehold) == 0 and int(b.arrearsExpert) == 0, "Next paid tick clears arrears first and resumes work")

func _test_save_roundtrip() -> void:
	reset()
	survey("cinder_workshop_ruin")
	HomeHarbor.establish(c, "workshop", home_id())
	var b := business()
	b.inventory["timber"] = 2.5
	HomeHarbor.capital(c, str(b.id), 250)
	var text: String = JSON.stringify(c.state)
	var restored = JSON.parse_string(text)
	check(restored is Dictionary, "State with businesses survives JSON roundtrip")
	if restored is Dictionary:
		var c2 = Campaign.new(world)
		c2.state = restored
		var rows: Array = HomeHarbor.list_businesses(c2.state)
		check(rows.size() == 1 and str(rows[0].kind) == "workshop", "Business survives the roundtrip")
		check(str(rows[0].homePort) == home_id() and str(rows[0].charterSite) == "cinder_workshop_ruin", "Home port and charter site survive")
		check(int(rows[0].coins) == int(b.coins) and int(rows[0].capitalIn) == int(b.capitalIn), "Purse and contributed capital survive")
		check((rows[0].employees as Array).size() == 4, "Employees survive the roundtrip")
		check(is_equal_approx(float(rows[0].inventory.get("timber", 0.0)), 2.5), "Stored inventory survives the roundtrip")
		check(int(rows[0].reserve) == 14 * 525 + 1500, "Reserve recomputes after load")
