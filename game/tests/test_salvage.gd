extends SceneTree
const Campaign = preload("res://scripts/campaign.gd")
const Salvage = preload("res://scripts/salvage.gd")
const Damage = preload("res://scripts/damage.gd")
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

func ship(hull_id: String, team: String, sunk: bool, stores: Dictionary) -> Dictionary:
	var s: Dictionary = Damage.create_ship(c.hull(hull_id), stores)
	s.team = team
	s.sunk = sunk
	s.id = "%s-test-%s" % [team, hull_id]
	s.uid = s.id
	s.engine = 0.6
	s.fire = 0.0
	s.x = 700.0
	s.y = 850.0
	return s

func battle_fixture() -> Dictionary:
	var dead_enemy := ship("tin_skiff", "enemy", true, {"fuel": 12.0, "ammo": 125.0, "supplies": 4.0})
	var live_enemy := ship("lantern_skiff", "enemy", false, {"fuel": 50.0, "ammo": 80.0, "supplies": 9.0})
	var dead_friend := ship("harbor_sloop", "player", true, {"fuel": 3.0, "ammo": 0.0, "supplies": 1.0})
	return {"ships": [dead_enemy, live_enemy, dead_friend],
		"wrecks": [{"id": dead_enemy.id, "uid": dead_enemy.uid, "cause": "flooding"}]}

func wreck_by_hull(list: Array, hull_id: String) -> Dictionary:
	for w in list:
		if str(w.get("hull", "")) == hull_id:
			return w
	return {}

func _initialize() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c = Campaign.new(world)
	_test_record_destroyed_only()
	_test_strip_and_capacity_atomicity()
	_test_tow_purse_conservation()
	_test_repeat_claims_and_seeding()
	_test_save_roundtrip()
	print("salvage: %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty():
		quit(0)
	else:
		quit(1)

func _test_record_destroyed_only() -> void:
	reset()
	var battle := battle_fixture()
	var made: Array = Salvage.record_battle(c, battle, "battle:test-1")
	check(made.size() == 2, "Only the two destroyed boats become wrecks (live boat excluded)")
	check(c.state.wrecks.size() == 2, "State persists exactly two wreck records")
	var enemy := wreck_by_hull(made, "tin_skiff")
	var friend := wreck_by_hull(made, "harbor_sloop")
	check(not enemy.is_empty() and not bool(enemy.friendly) and str(enemy.cause) == "flooding", "Enemy wreck keeps identity and battle cause")
	check(not friend.is_empty() and bool(friend.friendly), "Friendly destroyed boat is recorded too")
	check(str(enemy.id) != str(friend.id), "Individual wrecks get distinct stable ids")
	check(is_equal_approx(float(enemy.stores.get("fuel", 0.0)), 12.0), "Wreck preserves that hull's surviving fuel")
	check(is_equal_approx(float(enemy.stores.get("ammo", 0.0)), 2.5), "125 rounds become 2.5 fifty-round cargo cases")
	check(is_equal_approx(float(friend.stores.get("fuel", 0.0)), 3.0), "Friendly wreck keeps its own separate stores")
	check(not (enemy.components as Dictionary).is_empty(), "Wreck carries finite components derived from its hull")
	for good in enemy.components:
		check(float(enemy.components[good]) > 0.0 and is_finite(float(enemy.components[good])), "Finite positive component lot " + str(good))
	# Repeat recording with the same source id is a no-op returning the originals.
	var again: Array = Salvage.record_battle(c, battle, "battle:test-1")
	check(again.size() == 2 and c.state.wrecks.size() == 2, "Repeat recording adds no duplicate wrecks")
	check(str(again[0].id) == str(made[0].id), "Repeat recording returns the original stable ids")
	# A different battle appends with higher monotonic ids.
	var more: Array = Salvage.record_battle(c, {"ships": [ship("tin_skiff", "enemy", true, {})], "wrecks": []}, "battle:test-2")
	check(more.size() == 1 and int(str(more[0].id).trim_prefix("wreck-")) > int(str(made[-1].id).trim_prefix("wreck-")), "Later battles get higher monotonic ids")
	# Nearby finds unclaimed wrecks at the campaign position, nearest first.
	var near: Array = Salvage.nearby(c.state, c.state.position, 180.0)
	check(near.size() == 3, "nearby() lists every unclaimed wreck at the battle position")
	check(Salvage.nearby(c.state, {"x": 0.0, "y": 0.0}, 10.0).is_empty(), "nearby() respects radius")

func _test_strip_and_capacity_atomicity() -> void:
	reset()
	var made: Array = Salvage.record_battle(c, battle_fixture(), "battle:strip")
	var enemy := wreck_by_hull(made, "tin_skiff")
	# Fill the hold completely: stripping must refuse and change nothing.
	c.state.cargo.food = c.capacity()
	var cargo_before: Dictionary = c.state.cargo.duplicate(true)
	var wrecks_before: Array = c.state.wrecks.duplicate(true)
	var refused: Dictionary = Salvage.recover(c, str(enemy.id), "strip")
	check(not bool(refused.ok), "Strip refuses when the hold cannot fit the lots")
	check(c.state.cargo == cargo_before, "Refused strip leaves cargo untouched")
	check(c.state.wrecks == wrecks_before, "Refused strip leaves the wreck untouched")
	# With room, the exact quoted lots move and the wreck empties once.
	c.state.cargo.food = 0.0
	var q: Dictionary = Salvage.quote(c, str(enemy.id), "strip")
	check(bool(q.ok) and int(q.coins) == 0, "Strip quote is ready and never involves coins")
	var coins_before: int = int(c.state.coins)
	var done: Dictionary = Salvage.recover(c, str(enemy.id), "strip")
	check(bool(done.ok), "Strip succeeds with hold room")
	for good in q.items:
		check(is_equal_approx(float(c.state.cargo.get(good, 0.0)), float(cargo_before.get(good, 0.0)) + float(q.items[good])) if good != "food" else float(c.state.cargo.food) >= 0.0, "Cargo gains quoted lot " + str(good))
	check(int(c.state.coins) == coins_before, "Strip moves no coins")
	var stored: Dictionary = Salvage.find_wreck(c.state, str(enemy.id))
	check(str(stored.status) == "stripped" and (stored.stores as Dictionary).is_empty() and (stored.components as Dictionary).is_empty(), "Stripped wreck keeps no second inventory")

func _test_tow_purse_conservation() -> void:
	reset()
	var made: Array = Salvage.record_battle(c, battle_fixture(), "battle:tow")
	var friend := wreck_by_hull(made, "harbor_sloop")
	var q: Dictionary = Salvage.quote(c, str(friend.id), "tow")
	check(bool(q.ok), "Tow quote is ready for a rostered, funded captain")
	check(int(q.expert) == 200, "Tow inspection uses the 200-coin engineer day wage")
	check(int(q.total) == int(q.ordinary) + int(q.expert) + int(q.fee), "Tow total is labor plus expert plus fee")
	var total_before: int = Money.total(c.state)
	var harbor: Dictionary = c.port(c.state.lastPort)
	var household: int = int(harbor.householdPurse)
	var expert_purse: int = int(harbor.expertPurse)
	var business: int = int(harbor.cash)
	var fleet_before: int = c.state.fleet.size()
	var done: Dictionary = Salvage.recover(c, str(friend.id), "tow")
	check(bool(done.ok), "Tow succeeds")
	check(Money.total(c.state) == total_before, "Tow conserves every coin in the economy")
	check(int(harbor.householdPurse) == household + int(q.ordinary), "Tug wages enter the harbor household purse")
	check(int(harbor.expertPurse) == expert_purse + int(q.expert), "Inspection enters the harbor expert purse")
	check(int(harbor.cash) == business + int(q.fee), "Company fee enters the harbor business purse")
	check(c.state.fleet.size() == fleet_before + 1, "Tow returns exactly one physical hull")
	var boat: Dictionary = c.state.fleet[-1]
	check(is_equal_approx(float(boat.hp), float(boat.maxHp) * 0.35), "Towed hull returns at 35% HP")
	check(float(boat.crew) == 0.0 and float(boat.fuel) == 0.0 and float(boat.ammo) == 0.0 and float(boat.supplies) == 0.0, "Towed hull has no crew or working stores")
	check(bool(boat.get("towed", false)) and float(boat.get("towSpeedFactor", 1.0)) < 1.0, "Towed hull carries the tow speed factor for root")
	check(bool(boat.get("mothballed", false)) and bool(boat.get("needsHarborRepair", false)), "Towed hull is mothballed pending harbor repair and crew")
	check(float((boat.repairLiability as Dictionary).get("supplies", 0.0)) > 0.0, "Towed hull records a finite repair liability")
	check(str(Salvage.find_wreck(c.state, str(friend.id)).status) == "towed", "Wreck records its tow settlement")

func _test_repeat_claims_and_seeding() -> void:
	reset()
	var made: Array = Salvage.record_battle(c, battle_fixture(), "battle:once")
	var a := wreck_by_hull(made, "tin_skiff")
	var b := wreck_by_hull(made, "harbor_sloop")
	check(bool(Salvage.recover(c, str(a.id), "strip").ok), "First strip settles wreck A")
	check(not bool(Salvage.recover(c, str(a.id), "strip").ok), "Wreck A cannot be stripped twice")
	check(not bool(Salvage.recover(c, str(a.id), "tow").ok), "Stripped wreck A cannot also be towed")
	check(bool(Salvage.recover(c, str(b.id), "tow").ok), "First tow settles wreck B")
	check(not bool(Salvage.recover(c, str(b.id), "strip").ok), "Towed wreck B cannot also be stripped")
	check(not bool(Salvage.recover(c, str(b.id), "tow").ok), "Wreck B cannot be towed twice")
	check(not bool(Salvage.recover(c, "wreck-9999", "strip").ok), "Unknown wreck id is refused")
	check(not bool(Salvage.quote(c, str(a.id), "burn").ok), "Unknown mode is refused")
	# Broke captains cannot tow, and the refusal pays nobody.
	var made2: Array = Salvage.record_battle(c, {"ships": [ship("tin_skiff", "enemy", true, {})], "wrecks": []}, "battle:broke")
	c.state.coins = 0
	var total_before: int = Money.total(c.state)
	check(not bool(Salvage.recover(c, str(made2[0].id), "tow").ok), "Tow refuses without the labor coins")
	check(Money.total(c.state) == total_before, "Refused tow pays no purse")
	# Survey-site seeding is finite, deterministic and idempotent.
	var site := {"id": "shatter_wreck_field", "x": 8450.0, "y": 4000.0}
	var seeded: Dictionary = Salvage.seed_site_wreck(c, site, "tin_skiff")
	var seeded_again: Dictionary = Salvage.seed_site_wreck(c, site, "lantern_skiff")
	check(not seeded.is_empty() and str(seeded.id) == str(seeded_again.id), "Site wreck seeding never duplicates or rerolls")
	check(str(seeded.hull) == "tin_skiff", "Seeded wreck keeps its first authored hull")
	check(Salvage.seed_site_wreck(c, site, "no_such_hull", "site:other").is_empty(), "Seeding an unknown hull is refused")

func _test_save_roundtrip() -> void:
	reset()
	var made: Array = Salvage.record_battle(c, battle_fixture(), "battle:save")
	Salvage.recover(c, str(wreck_by_hull(made, "tin_skiff").id), "strip")
	var text: String = JSON.stringify(c.state)
	var restored = JSON.parse_string(text)
	check(restored is Dictionary, "State with wrecks survives JSON roundtrip")
	if restored is Dictionary:
		var c2 = Campaign.new(world)
		c2.state = restored
		Salvage.ensure(c2.state)
		check(c2.state.wrecks.size() == c.state.wrecks.size(), "Every wreck survives the roundtrip")
		check(int(c2.state.wreckSeq) == int(c.state.wreckSeq), "Monotonic wreck sequence survives the roundtrip")
		var stripped := wreck_by_hull(c2.state.wrecks, "tin_skiff")
		check(str(stripped.status) == "stripped", "Settled status survives the roundtrip")
		var remaining := wreck_by_hull(c2.state.wrecks, "harbor_sloop")
		check(bool(Salvage.quote(c2, str(remaining.id), "tow").ok), "Restored unclaimed wreck can still be quoted")
		var extra: Array = Salvage.record_battle(c2, {"ships": [ship("tin_skiff", "enemy", true, {})], "wrecks": []}, "battle:after-load")
		check(extra.size() == 1 and int(str(extra[0].id).trim_prefix("wreck-")) > int(c.state.wreckSeq), "Ids keep rising after load")
	# Legacy state without wreck keys gains them without touching other fields.
	var legacy := {"coins": 42, "cargo": {}, "fleet": []}
	Salvage.ensure(legacy)
	check(legacy.wrecks is Array and int(legacy.wreckSeq) == 0 and int(legacy.coins) == 42, "ensure() migrates legacy saves in place")
	# Bound: state never holds more than 128 wrecks.
	var big := {"wrecks": [], "position": {"x": 0.0, "y": 0.0}}
	for i in range(140):
		big.wrecks.append({"id": "wreck-%d" % (i + 1), "status": "unclaimed", "x": 0.0, "y": 0.0})
	Salvage.ensure(big)
	check(big.wrecks.size() == 128, "Wreck list is bounded at 128 records")
