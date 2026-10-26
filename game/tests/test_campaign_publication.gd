extends "res://tests/test_campaign.gd"
## Focused regression; the separate unchanged parent still runs all nine scenarios.
const IdentityDefaults = preload("res://scripts/fleet_identity.gd")
const HomeDefaults = preload("res://scripts/home_ops.gd")
const BoardingDefaults = preload("res://scripts/boarding_ops.gd")
const Births = preload("res://scripts/equipment_lifecycle.gd")

func _initialize() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c = Campaign.new(world)
	_test_fresh_publication()
	_test_paid_low_morale_publication()
	_test_legacy_shell_publication()
	_test_existing_publication_fields()
	print("campaign_publication: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _published(boat: Dictionary, label: String) -> void:
	for key in ["berthArrears", "boarders", "conversion", "economyFactor", "service", "serviceHistory", "specialistActive"]:
		check(boat.has(key), label + " publishes " + key + " before save")
	var factor: float = clampf(float(c.state.morale) / 85.0, 0.35, 1.0)
	var base: Dictionary = IdentityDefaults.effective(boat, c.fitted_spec(boat))
	check(is_equal_approx(float(boat.get("economyFactor", -1.0)), factor), label + " has current morale factor")
	check(is_equal_approx(float(boat.spec.speed), float(base.speed) * factor), label + " scales canonical speed once")
	check(is_equal_approx(float(boat.spec.fireRate), float(base.fireRate) * factor), label + " scales canonical fire rate once")
	var expected: Array = base.get("weaponMounts", [])
	var actual: Array = boat.spec.get("weaponMounts", [])
	check(actual.size() == expected.size(), label + " preserves mount count")
	for i in range(mini(actual.size(), expected.size())):
		check(is_equal_approx(float(actual[i].fireRate), float(expected[i].fireRate) * factor), label + " scales mount fire rate once")

func _round_trip(label: String) -> void:
	var before: Dictionary = c.state.duplicate(true)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(c.state))
	check(c.restore(saved).ok, label + " restores actual campaign JSON")
	for key in ["fleet", "ports", "cargo", "position", "coins", "missionIndex", "seed", "renown", "day", "morale", "coinSupply", "crewPurse", "specialists"]:
		check(same_data(c.state[key], before[key]), label + " preserves complete " + key)
	check(Money.total(c.state) == int(before.coinSupply), label + " preserves the finite coin supply")

func _test_fresh_publication() -> void:
	reset()
	_published(c.state.fleet[0], "Fresh career starter")
	_round_trip("Immediate fresh career")

func _test_paid_low_morale_publication() -> void:
	for morale in [42.5, 10.0]:
		reset()
		c.state.morale = morale
		c.apply_morale()
		var p: Dictionary = c.current_port()
		var h: Dictionary = c.hull(world.START.hull)
		var q: Dictionary = c.ship_quote(h, p)
		var hiring: int = Economy.recruit_cost(p, int(h.crewMin))
		fund_wallet(int(q.readyPrice) + hiring + 1000)
		var coins: int = int(c.state.coins)
		var purse: int = int(c.state.crewPurse)
		var total: int = Money.total(c.state)
		var people: int = int(p.workforce) + c.crew_count()
		var count: int = c.state.fleet.size()
		check(c.buy_boat(h.id).ok, "Low-morale hull bought through the published paid contract")
		check(c.state.fleet.size() == count + 1, "Paid hull publishes exactly once")
		if c.state.fleet.size() != count + 1:
			continue
		var boat: Dictionary = c.state.fleet[-1]
		check(int(c.state.coins) == coins - int(q.readyPrice) - hiring and int(c.state.crewPurse) == purse + hiring, "Paid hull retains exact price and sailor advance")
		check(Money.total(c.state) == total and int(p.workforce) + c.crew_count() == people, "Publication conserves existing coins and people")
		_published(boat, "Paid low-morale hull")
		boat.hp -= 7.0
		var damaged: Dictionary = boat.duplicate(true)
		c._initialize_published_boat(boat)
		check(same_data(boat, damaged), "Repeated publication keeps UID, fitted spec, module records, damage, crew and stores")
		_round_trip("Paid hull at morale %.1f" % morale)

func _test_legacy_shell_publication() -> void:
	reset()
	c.state.morale = 42.5
	c.apply_morale()
	var total: int = Money.total(c.state)
	var people: int = c.crew_count()
	var ports: Array = c.state.ports.duplicate(true)
	var starter: Dictionary = c.state.fleet[0].duplicate(true)
	var uid: String = "boat-%d" % int(c.state.nextUid)
	var boat: Dictionary = c.add_boat(c.hull("bilge_punt"), 0)
	_published(boat, "Legacy tow shell")
	check(boat.uid == uid and boat.crew == 0 and boat.fuel == 0 and boat.ammo == 0 and boat.supplies == 0 and boat.mothballed, "Legacy shell retains its UID and empty inactive delivery contract")
	check(Money.total(c.state) == total and c.crew_count() == people and same_data(c.state.ports, ports) and same_data(c.state.fleet[0], starter), "Legacy initialization leaves existing people, purses, harbor stocks and hull untouched")
	# This deliberately unseeded legacy shell exercises the domain-default seam.
	# Physical-equipment migration is a separate contract from these seven fields.
	var restored: Dictionary = JSON.parse_string(JSON.stringify(boat))
	IdentityDefaults.ensure_boat(restored)
	HomeDefaults.ensure_boat(restored)
	BoardingDefaults.ensure_boat(restored)
	c._apply_boat_morale(restored, 0.5)
	check(same_data(restored, boat), "Legacy shell JSON already contains exactly the restore-time domain defaults and morale spec")

func _test_existing_publication_fields() -> void:
	reset()
	var source: Dictionary = c.state.fleet[0].duplicate(true)
	var staged: Dictionary = {"boat": source, "hullHp": float(source.hp) - 7.0}
	var boat: Dictionary = Births.materialize(c.hull(source.type), int(source.crew), staged, false)
	c._initialize_published_boat(boat)
	boat.berthArrears = 37
	boat.boarders = 1
	boat.service = {"battles": 2, "wins": 1}
	boat.serviceHistory = [{"day": 1.0, "event": "battle", "detail": "retained publication record"}]
	var before: Dictionary = boat.duplicate(true)
	var state_before: Dictionary = c.state.duplicate(true)
	c._initialize_published_boat(boat)
	check(same_data(boat, before), "Existing valid per-hull fields and preserved-stage physical state are not reset")
	check(boat.uid == source.uid and same_data(boat.moduleCondition, source.moduleCondition) and boat.hp == staged.hullHp and boat.fuel == 0 and boat.ammo == 0 and boat.supplies == 0 and boat.crew == source.crew, "Preserved materialization retains equipment UIDs, HP, crew and its zero-store delivery contract")
	check(same_data(c.state, state_before), "Per-hull defaults never change live campaign people, purses or inventory")
