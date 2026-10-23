extends SceneTree

const B = preload("res://scripts/boarding.gd")
const Money=preload("res://scripts/money.gd")
var failures := 0
var checks: int=0

class Fixture extends RefCounted:
	var state: Dictionary
	func current_port() -> Dictionary:
		return state.ports.dock
	func port(id) -> Dictionary:
		return state.ports.get(id, {})
	func find_boat(uid) -> Dictionary:
		for b in state.fleet:
			if b.uid == uid:
				return b
		return {}

func check(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures += 1
		print("FAIL boarding: "+message)

func boat(uid: String, team: String, crew: float = 20.0) -> Dictionary:
	return {"uid": uid, "type": "fixture", "team": team,
		"spec": {"size": 20.0, "crewMin": 2, "crewMax": 30},
		"crew": crew, "crewMin": 2, "crewMax": 30, "boarders": 10 if team == "player" else 0,
		"wounded": 0.0, "water": 8.0, "capacity": 100.0, "breaches": [],
		"fire": 0.0, "engine": 1.0 if team == "player" else 0.05,
		"hp": 100.0 if team == "player" else 25.0, "maxHp": 100.0,
		"supplies": 55, "ammo": 33, "fuel": 44, "sunk": false,
		"x": 0.0 if team == "player" else 20.0, "y": 0.0,
		"loadout": [{"mount": "bow", "weapon": "fixture"}]}

func core() -> Fixture:
	var c := Fixture.new()
	c.state = {"fleet": [boat("s", "player")], "coins": 1000000, "crewPurse": 0,
		"day": 1, "econDay": 1, "moneyLog": [], "fleetCap": 2,
		"ports": {"dock": {"id": "dock", "workforce": 100, "availableWorkers": 90,
			"specialists": 10, "availableSpecialists": 10, "recruits": 80,
			"governmentPurse": 20000,"householdPurse":0,"expertPurse":0,
			"training": {"qualified": {"sailor": 60, "boarder": 15, "gunner": 5, "mechanic": 5}},
			"publicStores": {"guns": 1000, "ammo": 1000, "timber": 1000,
				"iron": 1000, "supplies": 1000, "food": 1000}}}}
	B.ensure_state(c)
	return c

func battle(c: Fixture, defenders: float = 12.0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91827
	return {"ships": [c.state.fleet[0], boat("t", "enemy", defenders)],
		"time": 0.0, "rng": rng, "result": "", "events": [], "effects": []}

func cash(c: Fixture) -> int:
	var p := c.current_port()
	return c.state.coins + c.state.crewPurse + p.governmentPurse + p.householdPurse+p.expertPurse

func conserved(b: Dictionary, before: float) -> void:
	var total := 0.0
	for ship in b.ships:
		total += ship.crew + ship.get("captives", 0)
	for j in b.boarding.jobs:
		total += j.alive + j.killed + j.defenderKilled + j.lost
		check(j.initial == j.alive + j.killed + j.returned + j.lost + j.prize,
			"Party partition must conserve its initial people")
	check(total == before, "Battle living people plus recorded losses must be conserved")

func hiring() -> void:
	var c := core()
	var p := c.current_port()
	var s: Dictionary = c.state.fleet[0]
	var money := cash(c)
	check(B.hire_party(c, "s", 3).ok, "Qualified paid hiring")
	check(s.crew == 23 and s.boarders == 13, "Hires occupy real berths")
	check(p.workforce == 97 and p.availableWorkers == 87 and p.recruits == 77,
		"Town people and eligibility leave once")
	check(p.training.qualified.boarder == 12 and p.training.qualified.sailor == 57,
		"Training eligibility consumed")
	check(c.state.coins == 997000 and c.state.crewPurse == 3000 and cash(c) == money,
		"Ten sailor-day advance is a real transfer")
	var snapshot: Dictionary = c.state.duplicate(true)
	check(not B.hire_party(c, "s", 1.5).ok, "Reject fractional hiring")
	check(c.state == snapshot, "Invalid hire has no effect")
	p.training.qualified.erase("boarder")
	check(not B.hire_party(c, "s", 1).ok, "Missing boarder training gives no people")
	p.training.qualified.boarder = 12
	s.crew = 30.0
	check(not B.hire_party(c, "s", 1).ok, "Physical berth limit")
	c.state.service = false
	check(not B.hire_party(c, "s", 1).ok, "Real harbor service gate")

func orders() -> void:
	var c := core()
	var b := battle(c)
	var t: Dictionary = b.ships[1]
	t.team = "player"
	check(not B.launch(b, "s", "t", 4).ok, "Refuse ally")
	t.team = "enemy"
	t.engine = 1.0
	t.hp = 100.0
	check(not B.launch(b, "s", "t", 4).ok, "Refuse healthy target")
	t.engine = 0.05
	t.x = 10000.0
	check(not B.launch(b, "s", "t", 4).ok, "Refuse distant target")
	t.x = 20.0
	for n in [0, -1, 1.5, 129]:
		check(not B.launch(b, "s", "t", n).ok, "Refuse invalid party count")
	check(B.launch(b, "s", "t", 4).ok, "Valid boarding order")
	check(not B.launch(b, "s", "t", 1).ok, "Refuse duplicate party")
	check(b.ships[0].crew == 16 and b.ships[0].boarders == 6,
		"Party is disjoint from source crew")

func captures() -> void:
	var c := core()
	var b := battle(c, 7)
	var t: Dictionary = b.ships[1]
	t.surrendering = true
	var damage: Dictionary = t.duplicate(true)
	var r := B.launch(b, "s", "t", 6)
	check(r.ok, "Launch surrender fixture")
	if not r.ok:
		return
	B.tick(b, 3.0)
	check(b.boarding.jobs[0].status == "active", "Capture requires elapsed time")
	B.tick(b, 1.0)
	check(b.boarding.jobs[0].status == "captured", "Elapsed surrender capture")
	check(is_same(t, b.captured[0]), "Capture preserves hull identity")
	for key in ["hp", "water", "breaches", "fire", "engine", "ammo", "fuel", "supplies", "loadout"]:
		check(t[key] == damage[key], "Preserve captured " + key)
	check(t.crew == 6 and t.boarders == 6 and t.captives == 7, "Real prize crew and captives")
	check(t.supportOnly and t.needsHarborRepair and t.captureSecured, "Prize safety flags")
	conserved(b, 27)
	var reserve := boat("t", "player", 0)
	reserve.boarders = 0
	c.state.fleet.append(reserve)
	c.state.fleetCap = 2
	check(B.settle(c, b).ok, "Settlement accepts held prize")
	check(c.state.boardingPrizes.size() == 1 and c.state.fleet.size() == 2,
		"Full roster retains saved prize")
	check(is_same(c.state.boardingPrizes[0], t) and t.uid != "t",
		"Collision renames only the captured hull")
	var uid = t.uid
	check(c.state.captives == 7 and t.captives == 0, "Captives transfer once")
	c.state.fleetCap = 3
	check(B.settle(c, b).added == 1 and is_same(c.state.fleet[2], t), "Promote same saved hull")
	B.settle(c, b)
	check(c.state.fleet.size() == 3 and c.state.captives == 7 and t.uid == uid,
		"Settlement is idempotent")
	check(c.state.fleet[0].crew + t.crew + c.state.captives == 27,
		"Campaign people conserved")

func recovery() -> void:
	for mode in ["abort", "escape", "sunk", "far_abort"]:
		var c := core()
		var b := battle(c)
		var r := B.launch(b, "s", "t", 4)
		if mode == "escape" or mode == "far_abort":
			b.ships[1].x = 10000.0
		if mode == "sunk":
			b.ships[1].sunk = true
		if mode == "abort" or mode == "far_abort":
			B.abort(b, r.id)
		else:
			B.tick(b, 2.0)
		var j: Dictionary = b.boarding.jobs[0]
		check(j.returned == (4 if mode == "abort" else 0), "Recovery needs real contact")
		check(j.lost == (0 if mode == "abort" else 4), "Unrecoverable party explicitly lost")
		check(not B.abort(b, r.id).ok, "Cannot recover twice")
		conserved(b, 32)
	var c := core()
	var b := battle(c, 20)
	B.launch(b, "s", "t", 8)
	B.tick(b, 2.0)
	check(b.boarding.jobs[0].defenderKilled > 0, "Exchange removes actual defenders")
	conserved(b, 40)
	B.tick(b, 60.0)
	check(b.boarding.jobs[0].status != "active", "Boarding duration is bounded")
	conserved(b, 40)

func timing() -> void:
	var runs: Array = []
	for grouped in [true, false]:
		var c := core()
		var b := battle(c)
		var s2 := boat("s2", "player")
		var t2 := boat("t2", "enemy", 12)
		b.ships.append(s2)
		b.ships.append(t2)
		B.launch(b, "s", "t", 6)
		B.launch(b, "s2", "t2", 6)
		for unused in range(1 if grouped else 60):
			B.tick(b, 60.0 if grouped else 1.0)
		conserved(b, 64)
		runs.append(b)
	for i in range(2):
		check(runs[0].boarding.jobs[i] == runs[1].boarding.jobs[i],
			"Global exchanges are independent of timestep grouping")

func defenses() -> void:
	var c := core()
	var p := c.current_port()
	c.state.friendly = false
	check(not B.defense_quote(c, "battery", 1).ok, "Friendly authority required")
	c.state.friendly = true
	p.availableSpecialists = 0
	check(not B.defense_quote(c, "battery", 1).ok, "Actual oversight required")
	p.availableSpecialists = 10
	var money := cash(c)
	var q := B.defense_quote(c, "battery", 1)
	check(q.ok, "Defense quote")
	if not q.ok:
		return
	var stores: Dictionary = p.publicStores.duplicate(true)
	var household: int = p.householdPurse
	check(B.build_defense(c, "battery", 1).ok, "Paid construction")
	var d: Dictionary = p.defenses
	check(cash(c) == money and p.householdPurse == household + q.ordinary and p.expertPurse==q.expert,
		"Build bill conserves cash and pays labor")
	for good in q.goods:
		check(p.publicStores[good] == stores[good] - q.goods[good], "Physical material " + good)
	check(p.workforce == 94 and d.crew == 6, "Defense crew is separate from workforce")
	check(not B.take_defense_shot(p).ok, "Commissioning cannot fire free shots")
	c.state.econDay += 1
	household = p.householdPurse
	B.daily_defenses(c)
	check(d.active and p.householdPurse == household + 600, "Real daily payroll")
	var paid: int = p.householdPurse
	B.daily_defenses(c)
	check(p.householdPurse == paid, "No duplicate daily payroll")
	var shots := 0
	for unused in range(13):
		var shot := B.take_defense_shot(p)
		if shot.ok:
			shots += 1
			check(shot.damage > 0 and shot.damage <= 20, "Bounded real shot")
	check(shots == 12 and d.ammo == 0 and not d.active, "Real ammo exhaustion")
	Money.move(p, "governmentPurse", c.state, "coins", int(p.governmentPurse),
		"Fixture treasury drain", c.state.moneyLog)
	c.state.econDay += 1
	B.daily_defenses(c)
	check(d.arrears == 600 and not d.active, "Unpaid defenses are inactive")
	Money.move(c.state, "coins", p, "governmentPurse", 5000,
		"Fixture real treasury funding", c.state.moneyLog)
	c.state.econDay += 1
	paid = p.householdPurse
	B.daily_defenses(c)
	check(d.active and d.arrears == 0 and p.householdPurse == paid + 1200,
		"Arrears and current wages must both be paid")
	p.publicStores.food = 0
	c.state.econDay += 1
	B.daily_defenses(c)
	check(not d.active and not B.take_defense_shot(p).ok, "Empty public food disables defense")
	check(cash(c) == money, "Defense operations create no coins")
	check(B.validate(c.state, {"ports": [p]}) == "", "Valid saved defense")
	var bad: Dictionary = c.state.duplicate(true)
	bad.fleet[0].boarders = true
	check(B.validate(bad, {"ports": [p]}) != "", "Reject boolean count")
	bad = c.state.duplicate(true)
	bad.fleet[0].captives = INF
	check(B.validate(bad, {"ports": [p]}) != "", "Reject infinite captive count")
	bad = c.state.duplicate(true)
	bad.ports.dock.defenses.crew = 1.5
	check(B.validate(bad, {"ports": [p]}) != "", "Reject fractional defense people")
	check(B.validate(c.state, {"ports": []}) != "", "Reject unknown defense port reference")

func _initialize() -> void:
	var old := [B.harbor_rules, B.unit_price, B.fleet_capacity, B.household_key]
	B.harbor_rules = func(c, _p):
		return {"here": c.state.get("here", true), "service": c.state.get("service", true),
			"friendly": c.state.get("friendly", true)}
	B.unit_price = func(_c, _p, _good): return 10
	B.fleet_capacity = func(c): return c.state.fleetCap
	B.household_key = "householdPurse"
	hiring()
	orders()
	captures()
	recovery()
	timing()
	defenses()
	B.harbor_rules = old[0]
	B.unit_price = old[1]
	B.fleet_capacity = old[2]
	B.household_key = old[3]
	print("boarding: %d checks, %d failures"%[checks,failures])
	quit(0 if failures == 0 else 1)
