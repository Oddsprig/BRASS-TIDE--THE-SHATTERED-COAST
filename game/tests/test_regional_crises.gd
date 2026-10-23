extends SceneTree

var script_resource
var failures = 0
var checks = 0

class FakeCore extends RefCounted:
	var state: Dictionary
	var data: Dictionary
	var dock = "a"
	var travelling = false
	var berth_limit = 32
	var site_limit = 100
	var blocked = ""
	var staff = {}
	var lost_food = 0

	func _init():
		state = {"econDay": 0, "day": 0, "cash": 500, "position": {"x": 0, "y": 0},
			"path": [], "fleet": [], "ports": [make_port("a", 80, 20), make_port("b", 20, 4)]}
		state.ports[0].lastFoodMet = 0.25
		data = {"PORTS": [{"id": "a"}, {"id": "b"}]}

	func make_port(id, people, specialists):
		return {"id": id, "workforce": people, "specialists": specialists,
			"specialistWorkers": specialists, "availableWorkers": people,
			"availableSpecialists": specialists, "recruits": int(people / 5),
			"training": {"qualified": {"sailor": int(people / 2),
				"gunner": int(people / 4), "mechanic": int(people / 8), "boarder": 0},
				"jobs": [{"held": 3}]},
			"householdPurse": people * 1000, "expertPurse": specialists * 1000,
			"governmentPurse": 500000, "cash": 1000, "householdSavings": 999,
			"stocks": {"food": 100000}, "publicStores": {"food": 0},
			"lastFoodMet": 1.0, "lastWagesDue": 100, "lastWagesPaid": 100,
			"conditions": {"health": 100, "fatigue": 0, "unrest": 10, "foodSecurity": 100}}

	func port(id):
		for p in state.ports:
			if p.id == id: return p
		return null

	func current_port(): return port(dock)
	func ok(message): return {"ok": true, "message": message}
	func fail(message): return {"ok": false, "message": message}
	func log_entry(_message): pass
	func capacity(): return 100000
	func cargo_weight(): return 0
	func berths(_core): return berth_limit
	func room(_core, p): return maxi(0, site_limit - int(p.workforce))
	func route(_core, _origin, _destination): return 2
	func service(_core, _port, _kind): return true
	func travel(_core, _job, _day): return travelling and dock == ""
	func account(_core): return [state, "cash"]

	func quote(_core, origin, count, days):
		var units = count * days
		return units * 2 if port(origin).stocks.food >= units else -1

	func callbacks():
		return {"wage": 100, "berths": Callable(self, "berths"),
			"site_room": Callable(self, "room"), "route_days": Callable(self, "route"),
			"service": Callable(self, "service"), "food_quote": Callable(self, "quote"),
			"atomic": Callable(self, "atomic"), "travel_day": Callable(self, "travel"),
			"fleet_account": Callable(self, "account")}

	func undo(journal):
		journal.reverse()
		for row in journal:
			if row[3]: row[0][row[1]] = row[2]
			else: row[0].erase(row[1])

	func write(journal, holder, key, value):
		journal.append([holder, key, holder.get(key, 0), holder.has(key)])
		holder[key] = value

	func atomic(_core, moves, event):
		var action = event.action
		var j = event.job
		if blocked == action: return false
		var p = port(event.get("port", ""))
		var units = int(j.n) * int(event.get("days", 0))
		if action == "buy":
			if p == null or p.stocks.food < units or j.foodCost != units * 2: return false
		if action == "eat" and int(j.food.get("food", 0)) < int(j.n): return false
		var staff_key = "%d:%s" % [int(state.econDay), event.get("port", "")]
		var used = staff.get(staff_key, [0, 0])
		if action == "handle":
			if p.availableWorkers - used[0] < j.handlers + 1: return false
			if p.availableSpecialists - used[1] < 1: return false
		var journal = []
		for m in moves:
			var amount = int(m[4])
			var balance = int(m[0].get(m[1], 0))
			var target = int(m[2].get(m[3], 0))
			if amount < 0 or balance < amount or target + amount > 1000000000000:
				undo(journal)
				return false
			write(journal, m[0], m[1], balance - amount)
			write(journal, m[2], m[3], target + amount)
		if action == "buy":
			if blocked == "latebuy" or j.escrow < j.foodCost:
				undo(journal)
				return false
			j.escrow -= j.foodCost
			p.cash += j.foodCost
			p.stocks.food -= units
			j.food["food"] = units
		elif action == "eat":
			j.food.food -= j.n
		elif action == "handle":
			staff[staff_key] = [used[0] + j.handlers + 1, used[1] + 1]
		elif action == "release":
			p.publicStores.food += int(j.food.get("food", 0))
			j.food.clear()
		elif action == "lose":
			lost_food += int(j.food.get("food", 0))
			j.food.clear()
		return true

func check(value, label):
	checks += 1
	if not value:
		failures += 1
		print("FAIL regional crises: "+str(label))

func fixture(crisis = true) -> Array:
	var f = FakeCore.new()
	var c = script_resource.new()
	c.configure(f.callbacks())
	check(c.ensure(f), "fixture validates")
	if crisis:
		for day in range(3):
			f.state.econDay = day
			c.daily(f)
	return [f, c]

func money(f, c) -> int:
	var total = int(f.state.cash)
	for p in f.state.ports:
		for key in ["householdPurse", "expertPurse", "governmentPurse", "cash"]:
			total += int(p[key])
	var s = f.state[c.KEY]
	total += int(s.lostPurse) + c.escrow_total(f.state)
	for j in s.jobs: total += int(j.householdPurse) + int(j.expertPurse)
	return total

func census(f, c) -> Array:
	var s = f.state[c.KEY]
	var out = [int(s.lostPeople), int(s.lostSpecialists), int(s.lostRecruits), 0, 0, 0, 0]
	for i in range(4): out[i + 3] = int(s.lostQualified[c.ROLES[i]])
	var pools = f.state.ports.duplicate()
	pools.append_array(s.jobs)
	for p in pools:
		out[0] += int(p.get("workforce", p.get("n", 0)))
		out[1] += int(p.specialists)
		out[2] += int(p.recruits)
		var q = p.qualified if p.has("qualified") else p.training.qualified
		for i in range(4): out[i + 3] += int(q[c.ROLES[i]])
	return out

func tick(f, c, dock = "", travel = true):
	f.state.econDay += 1
	f.dock = dock
	f.travelling = travel
	c.daily(f)
	check(c.validate(f.state, f.data.PORTS).is_empty(), "tick validates")

func embark(f, c, n = 8):
	var result = c.begin_resettlement(f, "a", "b", n)
	check(result.ok, "embark succeeds")
	return result.get("id", "")

func sail(f, c, id):
	tick(f, c)
	tick(f, c)
	f.dock = "b"
	f.travelling = false
	check(c.arrive(f, id).ok, "physical arrival succeeds")

func test_observations():
	var pair = fixture(false)
	var f = pair[0]
	var c = pair[1]
	f.port("a").erase("lastFoodMet")
	f.port("a").erase("conditions")
	f.port("a").erase("lastWagesPaid")
	for day in range(4):
		f.state.econDay = day
		c.daily(f)
	check(c.offers(f).is_empty(), "missing facts cannot generate offers")
	f.port("a").lastFoodMet = 0.2
	f.state.econDay = 20
	c.daily(f)
	check(c.offers(f).is_empty(), "gap is not fabricated sustained shortage")
	tick(f, c, "a", false)
	tick(f, c, "a", false)
	check(not c.offers(f).is_empty(), "three consecutive observed bad days")
	var before = JSON.stringify(f.state)
	c.daily(f)
	c.offers(f)
	c.report(f)
	check(JSON.stringify(f.state) == before, "daily/read idempotence")
	f.port("a").lastFoodMet = 1.0
	for i in range(3): tick(f, c, "a", false)
	check(not f.state[c.KEY].crises["a:food"].active, "dated recovery closes crisis")
	f.port("a").lastWagesDue = 100
	f.port("a").lastWagesPaid = 20
	for i in range(3): tick(f, c, "a", false)
	check(f.state[c.KEY].crises["a:wages"].active, "actual unpaid wages sustain crisis")

func test_gates():
	var pair = fixture()
	var f = pair[0]
	var c = pair[1]
	var before = JSON.stringify(f.state)
	f.dock = "b"
	check(not c.begin_resettlement(f, "a", "b", 8).ok, "origin dock required")
	f.dock = "a"
	for n in [0, 33, 1.5]:
		check(not c.begin_resettlement(f, "a", "b", n).ok, "bounded whole count")
	f.blocked = "latebuy"
	check(not c.begin_resettlement(f, "a", "b", 8).ok, "atomic purchase failure")
	check(JSON.stringify(f.state) == before, "failed purchase restores every balance/pool")
	f.blocked = ""
	f.berth_limit = 0
	check(c.offers(f).is_empty(), "numerical passenger berths required")
	f.berth_limit = 32
	f.site_limit = 20
	check(c.offers(f).is_empty(), "real destination room required")
	f.site_limit = 100
	f.port("a").governmentPurse = 0
	check(c.offers(f).is_empty(), "insolvent sponsor cannot offer")
	f.port("a").governmentPurse = 500000
	f.port("a").stocks.food = 0
	check(c.offers(f).is_empty(), "actual provisions required")
	f.port("a").stocks.food = 100000
	c.configure({})
	check(c.offers(f).is_empty(), "missing hooks fail closed")

func test_delivery():
	var pair = fixture()
	var f = pair[0]
	var c = pair[1]
	var coins = money(f, c)
	var people = census(f, c)
	var id = embark(f, c)
	check(c.passenger_count(f.state) == 8 and f.port("a").workforce == 72, "people leave origin once")
	check(f.port("a").training.jobs[0].held == 3, "committed training untouched")
	check(f.port("a").householdSavings == 999, "informational savings never treated as purse")
	check(f.port("a").stocks.food == 99952, "actual provision stock purchased")
	check(money(f, c) == coins and census(f, c) == people, "embark conservation")
	check(not c.arrive(f, id).ok, "no instant acceptance")
	sail(f, c, id)
	check(c.passenger_count(f.state) == 0 and c.held_people(f.state) == 8, "ashore holding distinct from crew")
	check(f.port("b").workforce == 20, "no same-day workforce refill")
	check(not c.arrive(f, id).ok, "arrival replay rejected")
	tick(f, c, "b", false)
	check(f.state[c.KEY].jobs[0].served == 1, "first actual reception day")
	check(f.port("b").workforce == 20, "first day cannot admit")
	var saved = f.state.duplicate(true)
	var same = JSON.stringify(f.state)
	c.daily(f)
	check(JSON.stringify(f.state) == same, "same-day service cannot repeat")
	f.state = saved.duplicate(true)
	c.daily(f)
	check(JSON.stringify(f.state) == same, "save replay cannot repeat service")
	tick(f, c, "b", false)
	check(f.port("b").workforce == 28 and c.held_people(f.state) == 0, "second day admits exactly once")
	check(money(f, c) == coins and census(f, c) == people, "delivery conservation")
	check(not c.arrive(f, id).ok and not c.return_to_origin(f, id).ok, "terminal replay rejected")
	check(f.port("b").publicStores.food == 16, "unused real provisions enter local custody")

func test_holding_and_return():
	var pair = fixture()
	var f = pair[0]
	var c = pair[1]
	var coins = money(f, c)
	var people = census(f, c)
	var id = embark(f, c)
	sail(f, c, id)
	f.blocked = "handle"
	tick(f, c, "b", false)
	check(f.state[c.KEY].jobs[0].served == 0, "unavailable actual handlers cannot be paid")
	f.blocked = ""
	f.state.econDay += 7
	c.daily(f)
	check(f.state[c.KEY].jobs[0].served == 1, "catch-up pays one actual reception day")
	f.dock = "a"
	check(not c.recall(f, id).ok, "cannot teleport holding cohort aboard")
	check(not c.return_to_origin(f, id).ok, "holding cohort cannot teleport to origin")
	f.dock = "b"
	f.berth_limit = 0
	check(not c.recall(f, id).ok, "recall needs usable berths")
	f.berth_limit = 32
	check(c.recall(f, id).ok, "holding cohort physically reloaded")
	check(not c.return_to_origin(f, id).ok, "return requires origin dock")
	f.dock = "a"
	check(c.return_to_origin(f, id).ok, "actual return settles")
	check(money(f, c) == coins and census(f, c) == people, "return conservation")
	check(f.port("a").workforce == 80, "no duplicate returning people")

func test_cancel_and_loss():
	var pair = fixture()
	var f = pair[0]
	var c = pair[1]
	var coins = money(f, c)
	var people = census(f, c)
	var id = embark(f, c)
	check(c.return_to_origin(f, id).ok, "pre-departure cancellation")
	check(f.state.cash == 500, "no unearned fare")
	check(f.port("a").publicStores.food == 48, "cancelled supplies return to sponsor custody")
	check(money(f, c) == coins and census(f, c) == people, "cancel conservation")
	id = embark(f, c)
	var savings = f.state[c.KEY].jobs[0].householdPurse + f.state[c.KEY].jobs[0].expertPurse
	tick(f, c)
	check(c.recall(f, id).ok, "at-sea recall changes intent only")
	check(not c.return_to_origin(f, id).ok, "at-sea discharge forbidden")
	check(c.lose(f, id).ok, "explicit loss settles")
	check(f.state[c.KEY].lostPurse == savings and f.state[c.KEY].lostPeople == 8, "loss custody ledger")
	check(f.lost_food == 40, "actual remaining provisions explicitly lost")
	check(money(f, c) == coins and census(f, c) == people, "loss money/person/qualification accounting")
	var before = JSON.stringify(f.state)
	check(not c.lose(f, id).ok, "loss replay rejected")
	check(JSON.stringify(f.state) == before, "loss replay cannot drain twice")

func test_limits_and_validation():
	var pair = fixture()
	var f = pair[0]
	var c = pair[1]
	for i in range(8): embark(f, c, 1)
	check(not c.begin_resettlement(f, "a", "b", 1).ok, "eight-job limit")
	var valid = f.state.duplicate(true)
	var j = f.state[c.KEY].jobs[0]
	j.escrow += 1
	check(not c.validate(f.state, f.data.PORTS).is_empty(), "escrow drift rejected")
	f.state = valid.duplicate(true)
	f.state[c.KEY].jobs[0].qualified.gunner = 33
	check(not c.ensure(f), "invalid qualification subset rejected")
	f.state = valid.duplicate(true)
	f.state[c.KEY].jobs[1].id = f.state[c.KEY].jobs[0].id
	check(not c.ensure(f), "duplicate stable ID rejected")
	f.state = valid.duplicate(true)
	f.state[c.KEY].jobs[0].food.food = NAN
	check(not c.ensure(f), "nonfinite JSON rejected")
	f.state = valid.duplicate(true)
	f.state[c.KEY].schema = 99
	var before = JSON.stringify(f.state)
	check(not c.ensure(f), "unknown schema rejected")
	check(JSON.stringify(f.state) == before, "unknown schema preserved")
	f.state = valid.duplicate(true)
	f.state.ports[1].id = "a"
	check(not c.ensure(f), "duplicate canonical port rejected")
	pair = fixture()
	f = pair[0]
	c = pair[1]
	embark(f, c, 32)
	check(not c.begin_resettlement(f, "a", "b", 1).ok, "total live cohort cap")

func _initialize():
	script_resource = load("res://scripts/regional_crises.gd")
	if script_resource == null:
		push_error("Place regional_crises.gd beside this test.")
		quit(1)
		return
	test_observations()
	test_gates()
	test_delivery()
	test_holding_and_return()
	test_cancel_and_loss()
	test_limits_and_validation()
	print("regional_crises: %d checks; %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
