extends SceneTree
const Campaign = preload("res://scripts/campaign.gd")
const Identity = preload("res://scripts/fleet_identity.gd")
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

func reset() -> void:
	c.new_game(123)
	Identity.ensure(c.state)
	stock_yard()

func yard() -> Dictionary:
	return c.current_port()

func stock_yard() -> void:
	var p: Dictionary = yard()
	for good in ["timber", "logs", "iron", "copper", "supplies", "engines"]:
		p.stocks[good] = 50.0
	p.availableWorkers = 50
	p.availableSpecialists = 10
	p.specialistWorkers = 10
	p.recruits = 20
	p.workforce = 100

# Root assumption under test locally: Money.total plus specialist purses.
func total_with_specialists() -> int:
	return Money.total(c.state)

func boat() -> Dictionary:
	return c.state.fleet[0]

func _initialize() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c = Campaign.new(world)
	_test_paid_conversion()
	_test_atomic_refusals()
	_test_effective_no_stacking_no_healing()
	_test_specialist_hiring_and_pay()
	_test_save_roundtrip_and_service()
	print("fleet_identity: %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty():
		quit(0)
	else:
		quit(1)

func _test_paid_conversion() -> void:
	reset()
	c.state.coins = 100000
	var supply_before: int = Money.total(c.state)
	var p := yard()
	var cash_before: int = int(p.cash)
	var timber_before: float = float(p.stocks.timber)
	var base_speed: float = float(c.fitted_spec(boat()).speed)
	var base_cargo: float = float(c.fitted_spec(boat()).cargo)
	var mounts_before = str(c.fitted_spec(boat()).get("weaponMounts", []))
	var loadout_before: Dictionary = (boat().get("loadout", {}) as Dictionary).duplicate(true)
	var q: Dictionary = Identity.quote_conversion(c, boat().uid, "cargo_rig")
	check(bool(q.ok) and int(q.cost) > 0, "Cargo rig quotes at local prices")
	check(bool(Identity.install_conversion(c, boat().uid, "cargo_rig").ok), "Cargo rig installs")
	check(Money.total(c.state) == supply_before, "Conversion conserves every coin")
	check(int(p.cash) > cash_before, "Material and margin coins reach the harbor business purse")
	check(is_equal_approx(float(p.stocks.timber), timber_before - 3.0), "Conversion consumes real timber stock")
	var spec: Dictionary = Identity.effective(boat(), c.fitted_spec(boat()))
	check(int(spec.cargo) > int(base_cargo), "Cargo rig enlarges the hold")
	check(float(spec.speed) < base_speed, "Cargo rig pays for space with speed")
	check(str(boat().conversion) == "cargo_rig", "Boat records its interior conversion")
	check(not bool(Identity.install_conversion(c, boat().uid, "cargo_rig").ok), "The same conversion cannot be bought twice")
	check(str(spec.get("weaponMounts", [])) == mounts_before, "Interior conversion leaves physical weapon mounts untouched")
	check((boat().get("loadout", {}) as Dictionary) == loadout_before, "Interior conversion leaves the original loadout stable")
	check(Identity.conversions().size() == 5, "Five interior conversions are catalogued")

func _test_atomic_refusals() -> void:
	reset()
	var snapshot_coins: int = int(c.state.coins)
	c.state.coins = 1
	check(not bool(Identity.install_conversion(c, boat().uid, "workshop_rig").ok), "Conversion refuses when the captain cannot pay")
	check(str(boat().get("conversion", "")) == "" and int(c.state.coins) == 1, "Broke refusal changes neither boat nor purse")
	c.state.coins = snapshot_coins + 100000
	yard().stocks.iron = 0.0
	var stock_before: Dictionary = (yard().stocks as Dictionary).duplicate(true)
	check(not bool(Identity.quote_conversion(c, boat().uid, "workshop_rig").ok), "Conversion refuses without physical iron")
	check((yard().stocks as Dictionary)==stock_before,"Missing-material quote is atomic before the fixture restores its iron")
	yard().stocks.iron = 50.0
	stock_before=(yard().stocks as Dictionary).duplicate(true)
	yard().availableWorkers = 0
	check(not bool(Identity.quote_conversion(c, boat().uid, "workshop_rig").ok), "Conversion refuses without yard workers")
	yard().availableWorkers = 50
	yard().availableSpecialists = 0
	check(not bool(Identity.quote_conversion(c, boat().uid, "workshop_rig").ok), "Conversion refuses without yard specialists")
	yard().availableSpecialists = 10
	check((yard().stocks as Dictionary) == stock_before, "Every refused quote left stocks untouched")

func _test_effective_no_stacking_no_healing() -> void:
	reset()
	c.state.coins = 100000
	boat().hp = float(boat().maxHp) * 0.5
	boat().fuel = 7.0
	boat().ammo = 11.0
	boat().supplies = 2.0
	boat().water = 40.0
	check(bool(Identity.install_conversion(c, boat().uid, "survey_rig").ok), "Survey rig installs on a damaged boat")
	check(is_equal_approx(float(boat().hp), float(boat().maxHp) * 0.5), "Conversion never heals damage")
	check(float(boat().fuel) == 7.0 and float(boat().ammo) == 11.0 and float(boat().supplies) == 2.0, "Conversion never refills stores")
	check(float(boat().water) == 40.0, "Conversion never pumps flooding")
	var once: Dictionary = Identity.effective(boat(), c.fitted_spec(boat()))
	var repeat_fitted: Dictionary = Identity.effective(boat(), c.fitted_spec(boat()))
	check(once == repeat_fitted, "Effective spec is canonical across calls")
	var twice: Dictionary = Identity.effective(boat(), once)
	check(int(twice.cargo) == int(once.cargo) and is_equal_approx(float(twice.surveyFactor), float(once.surveyFactor)), "Effective-on-effective never stacks")
	check(float(once.surveyFactor) > 1.0 and float(once.cargo) < float(c.fitted_spec(boat()).cargo), "Survey advantage is paid for with hold space")

func _test_specialist_hiring_and_pay() -> void:
	reset()
	c.state.coins = 100000
	var total_before: int = total_with_specialists()
	var crew_before: float = float(boat().crew)
	var recruits_before: int = int(yard().recruits)
	var hired: Dictionary = Identity.hire_specialist(c, boat().uid, "surveyor")
	check(bool(hired.ok), "Surveyor hires at a stocked harbor")
	check(float(boat().crew) == crew_before + 1.0, "Specialist occupies one real crew berth")
	check(int(yard().recruits) == recruits_before - 1, "Specialist leaves the port recruit pool")
	check(total_with_specialists() == total_before, "Hiring advance conserves coins")
	check(not bool(Identity.hire_specialist(c, boat().uid, "surveyor").ok), "One surveyor per boat")
	var with_surveyor: Dictionary = Identity.effective(boat(), c.fitted_spec(boat()))
	check(float(with_surveyor.surveyFactor) > 1.0, "Paid surveyor benefit is active")
	var coins_before_tick: int = int(c.state.coins)
	Identity.tick(c, 2.0)
	var rec: Dictionary = c.state.specialists[0]
	check(int(rec.coins) == 150, "Two days of 75-coin premium reach the specialist purse")
	check(int(c.state.coins) == coins_before_tick - 150, "Premium leaves the captain purse exactly")
	check(total_with_specialists() == total_before, "Premium payments conserve coins")
	# Wage shortfall: arrears accrue and the premium benefit switches off.
	c.state.coins = 10
	var total_short: int = total_with_specialists()
	var messages: Array = Identity.tick(c, 2.0)
	check(not messages.is_empty(), "Shortfall is reported, not silent")
	check(int(rec.arrears) == 140 and not bool(rec.active), "Unpaid premium accrues arrears and deactivates")
	check(not bool((boat().specialistActive as Dictionary).get("surveyor", true)), "Boat loses the surveyor benefit flag")
	var suspended: Dictionary = Identity.effective(boat(), c.fitted_spec(boat()))
	check(float(suspended.surveyFactor) < float(with_surveyor.surveyFactor), "Suspended benefit leaves the effective spec")
	check(total_with_specialists() == total_short, "Shortfall mints and destroys nothing")
	c.state.coins = 1000
	Identity.tick(c, 1.0)
	check(int(rec.arrears) == 0 and bool(rec.active), "Fresh coins settle arrears before new premium")
	# Hiring refusals: no berth, no specialists ashore, no advance coins.
	boat().crew = float(boat().crewMax)
	check(not bool(Identity.hire_specialist(c, boat().uid, "pilot").ok), "No berth, no specialist")
	boat().crew = crew_before
	yard().availableSpecialists = 0
	check(not bool(Identity.hire_specialist(c, boat().uid, "pilot").ok), "No free port specialist, no hire")
	yard().availableSpecialists = 10
	c.state.coins = 0
	check(not bool(Identity.hire_specialist(c, boat().uid, "pilot").ok), "No advance coins, no hire")
	check(c.state.specialists.size() == 1, "Refused hires create no phantom specialists")

func _test_save_roundtrip_and_service() -> void:
	reset()
	c.state.coins = 100000
	Identity.install_conversion(c, boat().uid, "tug_rig")
	Identity.hire_specialist(c, boat().uid, "chief_engineer")
	Identity.record_service(c, [boat().uid], "won")
	Identity.record_service(c, [boat().uid], "survey")
	Identity.record_service(c, [boat().uid], "won")
	check(int(boat().service.get("battles", 0)) == 2 and int(boat().service.get("wins", 0)) == 2, "Service counters record battles and wins")
	check(int(boat().service.get("surveys", 0)) == 1, "Service counters record surveys")
	var spec_before: Dictionary = Identity.effective(boat(), c.fitted_spec(boat()))
	for i in range(20):
		Identity.record_service(c, [boat().uid], "trade")
	check((boat().serviceHistory as Array).size() <= 12, "Service history is bounded")
	check(Identity.effective(boat(), c.fitted_spec(boat())) == spec_before, "Long service never escalates any stat")
	var text: String = JSON.stringify(c.state)
	var restored = JSON.parse_string(text)
	check(restored is Dictionary, "State with identity data survives JSON roundtrip")
	if restored is Dictionary:
		var c2 = Campaign.new(world)
		c2.state = restored
		Identity.ensure(c2.state)
		check(str(c2.state.fleet[0].conversion) == "tug_rig", "Conversion survives the roundtrip")
		check(c2.state.specialists.size() == 1 and int(c2.state.specialists[0].premiumPerDay) == 100, "Chief engineer and premium survive")
		check(int(c2.state.fleet[0].service.get("trades", 0)) == 20, "Service counters survive the roundtrip")
		var spec2: Dictionary = Identity.effective(c2.state.fleet[0], c2.fitted_spec(c2.state.fleet[0]))
		check(is_equal_approx(float(spec2.get("towSpeedFactor", 0.0)), 0.75), "Tug advantage rebuilds canonically after load")
	var legacy := {"fleet": [{"uid": "boat-9"}], "coins": 5}
	Identity.ensure(legacy)
	check(legacy.specialists is Array and str(legacy.fleet[0].conversion) == "" and int(legacy.coins) == 5, "ensure() migrates legacy saves in place")
