extends RefCounted
class_name RegionalCrises

const KEY = "regionalCrises"
const LIMIT = 1000000000000
const PEOPLE = 1000000
const ROLES = ["sailor", "gunner", "mechanic", "boarder"]
const KINDS = ["food", "unrest", "wages"]
const World068=preload("res://scripts/ocean_world064.gd")
var hooks: Dictionary = {}

func configure(callbacks: Dictionary) -> void:
	hooks = callbacks.duplicate()

func _q() -> Dictionary:
	return {"sailor": 0, "gunner": 0, "mechanic": 0, "boarder": 0}

func _whole(v, low = 0, high = LIMIT) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) \
		and is_finite(float(v)) and float(v) == floor(float(v)) \
		and v >= low and v <= high

func _json(v, depth = 0) -> bool:
	if depth > 8: return false
	match typeof(v):
		TYPE_NIL, TYPE_BOOL: return true
		TYPE_INT: return _whole(v, -1)
		TYPE_FLOAT: return is_finite(float(v)) and float(v)>=-1 and float(v)<=LIMIT
		TYPE_STRING, TYPE_STRING_NAME: return v.length() <= 512
		TYPE_ARRAY:
			if v.size() > 128: return false
			for x in v:
				if not _json(x, depth + 1): return false
			return true
		TYPE_DICTIONARY:
			if v.size() > 128: return false
			for k in v:
				if not (k is String or k is StringName) or not _json(k, depth + 1): return false
				if not _json(v[k], depth + 1): return false
			return true
	return false

func _shape(v, names: String) -> bool:
	if not (v is Dictionary): return false
	var keys = names.split(" ")
	if v.size() != keys.size(): return false
	for k in keys:
		if not v.has(k): return false
	return true

func _catalog(world) -> Dictionary:
	var out = {}
	var defs = world.values() if world is Dictionary else world
	if not (defs is Array): return {}
	for p in defs:
		if not (p is Dictionary): return {}
		var id = p.get("id")
		if not (id is String) or id.is_empty() or id.length() > 80: return {}
		if out.has(id): return {}
		out[id] = p
	return out

func _day(state) -> int:
	var value = state.get("econDay", state.get("day", -2))
	return int(value) if _whole(value) else -2

func _spec(p) -> int:
	return int(p.get("specialists", p.get("specialistWorkers", 0)))

func _qualified(p):
	var training = p.get("training", {})
	return training.get("qualified", {}) if training is Dictionary else null

func _subsets(n, specialists, recruits, qualified) -> bool:
	if not _whole(n) or not _whole(specialists, 0, n): return false
	if not _whole(recruits, 0, n) or not (qualified is Dictionary): return false
	if not _whole(qualified.get("sailor", 0), 0, n): return false
	for role in ROLES:
		var maximum = n if role == "sailor" else qualified.get("sailor", 0)
		if not _whole(qualified.get(role, 0), 0, maximum): return false
	return int(qualified.get("gunner",0))+int(qualified.get("mechanic",0))+int(qualified.get("boarder",0))<=int(qualified.get("sailor",0))

func _port_ok(p) -> bool:
	if not (p is Dictionary) or not _whole(p.get("workforce"), 0, PEOPLE): return false
	var specialists = p.get("specialists", p.get("specialistWorkers", 0))
	if not _subsets(p.workforce, specialists, p.get("recruits", 0), _qualified(p)): return false
	if p.has("specialistWorkers") and p.specialistWorkers != specialists: return false
	var available = p.get("availableWorkers", 0)
	if not _whole(available, 0, p.workforce): return false
	if not _whole(p.get("availableSpecialists", 0), 0, min(specialists, available)): return false
	for key in ["householdPurse", "expertPurse", "governmentPurse", "cash"]:
		if not _whole(p.get(key, 0)): return false
	return true

func _stock(v) -> bool:
	if not (v is Dictionary) or v.size() > 32: return false
	for key in v:
		if not (key is String or key is StringName) or not (v[key] is int or v[key] is float) or not is_finite(float(v[key])) or float(v[key])<0 or float(v[key])>LIMIT: return false
	return true

func ensure(core) -> bool:
	if not core.state.has(KEY):
		core.state[KEY] = {
			"schema": 1, "lastDay": -1, "nextId": 1, "crises": {}, "jobs": [],
			"lostPurse": 0, "lostPeople": 0, "lostSpecialists": 0,
			"lostRecruits": 0, "lostQualified": _q()
		}
	return validate(core.state, core.data.PORTS).is_empty()

func validate(state: Dictionary, world) -> Array:
	var catalog = _catalog(world)
	# Optional installed record extends validation only; HOME job offers stay HOME.
	var shipping068=state.get("shipping068",{})
	if shipping068 is Dictionary and shipping068.get("schema")==1 and shipping068.get("installation") is Dictionary and shipping068.installation.get("status")=="installed":
		catalog[World068.REMOTE_PORT068]=World068.remote_port068()
	var day = _day(state)
	if catalog.is_empty() or day < 0: return ["Invalid world/day."]
	var ports = state.get("ports")
	if not (ports is Array) or ports.size() != catalog.size(): return ["Invalid port set."]
	var seen = {}
	for p in ports:
		if not _port_ok(p): return ["Invalid civilian pools/purses."]
		var id = p.get("id")
		if not catalog.has(id) or seen.has(id): return ["Unknown/duplicate port."]
		if id==World068.REMOTE_PORT068:
			for key in World068.remote_port068():
				if p.get(key)!=World068.remote_port068()[key]:return ["Invalid canonical Westglass harbor definition."]
		seen[id] = true
	if not state.has(KEY): return []
	var s = state[KEY]
	if not _shape(s, "schema lastDay nextId crises jobs lostPurse lostPeople lostSpecialists lostRecruits lostQualified"):
		return ["Invalid regional schema; preserved."]
	if not _json(s) or s.schema != 1: return ["Invalid regional JSON/schema."]
	if not _whole(s.lastDay, -1, day) or not _whole(s.nextId, 1): return ["Invalid regional clock/ID."]
	if not _whole(s.lostPurse) or not _subsets(s.lostPeople, s.lostSpecialists, s.lostRecruits, s.lostQualified):
		return ["Invalid loss ledger."]
	if not _shape(s.lostQualified, "sailor gunner mechanic boarder"): return ["Invalid lost roles."]
	if not (s.crises is Dictionary) or s.crises.size() > 96: return ["Too many crises."]
	for key in s.crises:
		var r = s.crises[key]
		if not _shape(r, "port kind bad good active seen started recovered evidence advice"):
			return ["Invalid crisis record."]
		if not catalog.has(r.port) or r.port==World068.REMOTE_PORT068 or not (r.kind in KINDS): return ["Invalid home crisis identity."]
		if key != "%s:%s" % [r.port, r.kind]: return ["Unstable crisis ID."]
		if not _whole(r.bad, 0, 999) or not _whole(r.good, 0, 999): return ["Invalid streak."]
		if r.bad > 0 and r.good > 0: return ["Contradictory streaks."]
		for k in ["seen", "started", "recovered"]:
			if not _whole(r[k], -1, s.lastDay): return ["Invalid evidence date."]
		if typeof(r.active) != TYPE_BOOL or not (r.evidence is String) or not (r.advice is String):
			return ["Invalid crisis evidence."]
		if r.active and (r.started < 0 or r.good >= 3): return ["Invalid active crisis."]
		if r.bad >= 3 and not r.active: return ["Invalid crisis progress."]
	if not (s.jobs is Array) or s.jobs.size() > 8: return ["Too many voyages."]
	seen.clear()
	for j in s.jobs:
		if not _shape(j, "id serial origin destination n specialists recruits qualified householdPurse expertPurse escrow food stage created arrived lastFed hungryDays days wage handlers progress served foodCost"):
			return ["Invalid voyage record."]
		if not _whole(j.serial, 1, s.nextId - 1): return ["Invalid voyage serial."]
		if j.id != "rs_%d" % int(j.serial) or seen.has(j.id): return ["Duplicate/unstable voyage ID."]
		seen[j.id] = true
		if not catalog.has(j.origin) or not catalog.has(j.destination) or j.origin == j.destination or j.origin==World068.REMOTE_PORT068 or j.destination==World068.REMOTE_PORT068:
			return ["Invalid voyage endpoints."]
		if not _whole(j.n, 1, 32) or not _subsets(j.n, j.specialists, j.recruits, j.qualified):
			return ["Invalid passenger subsets."]
		if not _shape(j.qualified, "sailor gunner mechanic boarder") or not _stock(j.food):
			return ["Invalid roles/provisions."]
		for k in ["householdPurse", "expertPurse", "escrow", "foodCost"]:
			if not _whole(j[k]): return ["Invalid passenger money."]
		if j.wage != 100 or not _whole(j.days, 1, 30): return ["Invalid fare basis."]
		if j.handlers != int(ceil(float(j.n) / 8.0)): return ["Invalid handling obligation."]
		if not _whole(j.created, 0, day) or not _whole(j.arrived, -1, day): return ["Invalid voyage dates."]
		if not _whole(j.lastFed, j.created - 1, day) or not _whole(j.hungryDays, 0, 999):
			return ["Invalid food progress."]
		if not _whole(j.progress, 0, min(j.days, day - j.created)): return ["Unearned route work."]
		if not _whole(j.served, 0, 2) or not (j.stage in ["aboard", "holding", "returning"]):
			return ["Invalid reception progress."]
		if j.stage == "aboard" and (j.arrived != -1 or j.served != 0): return ["Invalid aboard state."]
		if j.stage == "holding" and j.arrived < j.created: return ["Undated reception."]
		if j.arrived < 0 and j.served != 0: return ["Unarrived handling payment."]
		if j.arrived >= 0 and (j.progress != j.days or j.served > day - j.arrived):
			return ["Unearned reception."]
		var gross = int(j.n) * 100 * int(j.days)
		var handling = int(j.handlers)*100+175
		if j.foodCost > gross or j.escrow != gross + (2 - int(j.served)) * handling - int(j.foodCost):
			return ["Noncanonical escrow/payment relationship."]
	if held_people(state) > 32: return ["Too many held passengers."]
	return []

func _ready() -> bool:
	if not _whole(hooks.get("wage"), 100, 100): return false
	for key in ["berths", "site_room", "route_days", "service", "food_quote", "atomic", "travel_day", "fleet_account"]:
		if not (hooks.get(key) is Callable) or not hooks[key].is_valid(): return false
	return true

func _dock(core, id: String) -> bool:
	var p = core.current_port()
	var actual = p.get("id", "") if p is Dictionary else p
	return actual == id and hooks.service.call(core, id, "resettlement") == true

func _atomic(core, moves: Array, event: Dictionary) -> bool:
	var paid = []
	for move in moves:
		if move[4] > 0: paid.append(move)
	return hooks.atomic.call(core, paid, event) == true

@warning_ignore("integer_division")
func _share(value: int, count: int, total: int) -> int:
	return value * count / maxi(1, total)

func _cohort(p, n: int) -> Dictionary:
	var w = int(p.workforce)
	var idle = int(p.get("availableWorkers", 0))
	if n < 1 or n > idle: return {}
	var available = int(p.get("availableSpecialists", 0))
	var low = maxi(0, maxi(_spec(p) - (w - n), available - (idle - n)))
	var high = mini(n, available)
	if low > high: return {}
	var specialists = clampi(_share(_spec(p), n, w), low, high)
	var qualified = _q()
	for role in ROLES:
		qualified[role] = _share(int(_qualified(p).get(role, 0)), n, w)
	return {"n": n, "specialists": specialists,
		"recruits": _share(int(p.get("recruits", 0)), n, w), "qualified": qualified}

func _people(p, j, sign: int) -> void:
	p.workforce = int(p.workforce) + sign * int(j.n)
	p.recruits = int(p.get("recruits", 0)) + sign * int(j.recruits)
	p.availableWorkers = int(p.get("availableWorkers", 0)) + sign * int(j.n)
	p.specialists = _spec(p) + sign * int(j.specialists)
	if p.has("specialistWorkers"): p.specialistWorkers = p.specialists
	p.availableSpecialists = int(p.get("availableSpecialists", 0)) + sign * int(j.specialists)
	if not p.has("training"): p.training = {}
	if not p.training.has("qualified"): p.training.qualified = {}
	for role in ROLES:
		p.training.qualified[role] = int(p.training.qualified.get(role, 0)) + sign * int(j.qualified[role])

func _room(core, id: String, excluding = "") -> int:
	var p = core.port(id)
	var value = hooks.site_room.call(core, p)
	if not _whole(value, 0, PEOPLE): return 0
	var room = int(value)
	for j in core.state[KEY].jobs:
		if j.id != excluding and j.destination == id and j.stage != "returning":
			room -= int(j.n)
	return maxi(0, mini(room, PEOPLE - int(p.workforce)))

func _bad(s, id: String) -> bool:
	for r in s.crises.values():
		if r.port == id and r.active and r.bad >= 3: return true
	return false

func _fact(p, kind: String) -> Array:
	if kind == "food":
		var met = p.get("lastFoodMet")
		if (typeof(met) == TYPE_INT or typeof(met) == TYPE_FLOAT) \
			and is_finite(float(met)) and met >= 0 and met <= 1:
			return [1 if met < 0.85 else 0, "Actual food purchased/need: %.3f." % met]
	if kind == "unrest":
		var conditions = p.get("conditions", {})
		var unrest = conditions.get("unrest") if conditions is Dictionary else null
		if (unrest is int or unrest is float) and is_finite(float(unrest)) and float(unrest)>=0 and float(unrest)<=100:
			return [1 if unrest >= 70 else 0, "Observed unrest: %d/100." % int(unrest)]
	if kind == "wages":
		var due = p.get("lastWagesDue")
		var paid = p.get("lastWagesPaid")
		if _whole(due, 1) and _whole(paid):
			return [1 if paid < due else 0, "Actual wages paid/due: %d/%d." % [int(paid), int(due)]]
	return [-1, "No verified current fact; crisis effects suspended."]

func _observe(s, p, day: int) -> void:
	for kind in KINDS:
		var key = "%s:%s" % [p.id, kind]
		if not s.crises.has(key):
			if s.crises.size() >= 96: continue
			s.crises[key] = {"port": p.id, "kind": kind, "bad": 0, "good": 0,
				"active": false, "seen": -1, "started": -1, "recovered": -1,
				"evidence": "", "advice": ""}
		var r = s.crises[key]
		var fact = _fact(p, kind)
		if r.seen != day - 1:
			r.bad = 0
			r.good = 0
			r.active = false
		r.seen = day
		r.evidence = fact[1]
		if fact[0] < 0:
			r.bad = 0
			r.good = 0
			r.active = false
		elif fact[0] == 1:
			r.bad = mini(999, int(r.bad) + 1)
			r.good = 0
			if r.bad >= 3 and not r.active:
				r.active = true
				r.started = day - 2
				r.recovered = -1
		else:
			r.bad = 0
			r.good = mini(999, int(r.good) + 1)
			if r.active and r.good >= 3:
				r.active = false
				r.recovered = day
		var advice = {
			"food": "Fund actual food purchases; verify three consecutive adequate days.",
			"unrest": "Resolve observed local grievances; verify three days below 70 unrest.",
			"wages": "Pay real outstanding wages; verify three consecutive fully paid days."
		}
		r.advice = "Day %d: %s" % [day, advice[kind]]
		if fact[0] < 0: r.advice = "Day %d: Restore verified observations before intervention." % day

func _quote(core, origin: String, destination: String, maximum: int) -> Dictionary:
	if origin==World068.REMOTE_PORT068 or destination==World068.REMOTE_PORT068:return {}
	var s = core.state[KEY]
	if s.jobs.size() >= 8 or origin == destination or not _bad(s, origin) or _bad(s, destination): return {}
	var p = core.port(origin)
	var berths = hooks.berths.call(core)
	var days = hooks.route_days.call(core, origin, destination)
	if not _whole(berths, 0, PEOPLE) or not _whole(days, 1, 30): return {}
	var n = mini(maximum, mini(32 - held_people(core.state),
		mini(int(p.get("availableWorkers", 0)), mini(_room(core, destination), int(berths) - passenger_count(core.state)))))
	while n > 0:
		var handlers = int(ceil(float(n) / 8.0))
		var funded = n * 100 * int(days) + 2 * (handlers*100+175)
		if int(p.get("governmentPurse", 0)) >= funded and not _cohort(p, n).is_empty():
			var cost = hooks.food_quote.call(core, origin, n, 2 * int(days) + 2)
			if _whole(cost, 0, n * 100 * int(days)):
				return {"origin": origin, "destination": destination, "count": n,
					"days": int(days), "handlers": handlers, "foodCost": int(cost), "funded": funded}
		n -= 1
	return {}

func offers(core) -> Array:
	var out = []
	if not ensure(core) or not _ready(): return out
	for p in core.state.ports:
		if not _bad(core.state[KEY], p.id): continue
		for destination in core.state.ports:
			var offer = _quote(core, p.id, destination.id, 32)
			if not offer.is_empty(): out.append(offer)
			if out.size() >= 16: return out
	return out

func begin_resettlement(core, origin: String, destination: String, count):
	if not ensure(core) or not _ready(): return core.fail("Regional service unavailable.")
	if not _whole(count, 1, 32) or not _dock(core, origin): return core.fail("Visit the origin service with a whole passenger count.")
	if core.port(origin) == null or core.port(destination) == null: return core.fail("Unknown endpoint.")
	if not _catalog(core.data.PORTS).has(destination): return core.fail("Unknown destination.")
	var offer = _quote(core, origin, destination, int(count))
	if offer.is_empty() or offer.count != count: return core.fail("No funded, provisioned capacity for that cohort.")
	var s = core.state[KEY]
	if s.nextId >= LIMIT: return core.fail("Voyage ID limit reached.")
	var p = core.port(origin)
	var j = _cohort(p, int(count))
	var household = _share(int(p.get("householdPurse", 0)), int(count), int(p.workforce))
	var expert = _share(int(p.get("expertPurse", 0)), int(j.specialists), _spec(p))
	j.merge({"id": "rs_%d" % int(s.nextId), "serial": int(s.nextId),
		"origin": origin, "destination": destination, "householdPurse": 0, "expertPurse": 0,
		"escrow": 0, "food": {}, "stage": "aboard", "created": _day(core.state), "arrived": -1,
		"lastFed": _day(core.state) - 1, "hungryDays": 0, "days": offer.days, "wage": 100,
		"handlers": offer.handlers, "progress": 0, "served": 0, "foodCost": offer.foodCost})
	var moves = [[p, "governmentPurse", j, "escrow", offer.funded],
		[p, "householdPurse", j, "householdPurse", household],
		[p, "expertPurse", j, "expertPurse", expert]]
	var event = {"action": "buy", "job": j, "port": origin, "days": 2 * j.days + 2}
	if not _atomic(core, moves, event): return core.fail("Funding/provisions changed; nothing reserved.")
	_people(p, j, -1)
	s.jobs.append(j)
	s.nextId = int(s.nextId) + 1
	core.log_entry("Resettlement %s embarked %d existing civilians." % [j.id, j.n])
	var result = core.ok("Cohort embarked.")
	if result is Dictionary: result["id"] = j.id
	return result

func _job(core, id: String):
	for j in core.state[KEY].jobs:
		if j.id == id: return j
	return null

func arrive(core, id: String):
	if not ensure(core) or not _ready(): return core.fail("Regional service unavailable.")
	var j = _job(core, id)
	if j == null: return core.fail("Unknown/completed voyage.")
	if j.stage != "aboard" or not _dock(core, j.destination): return core.fail("Dock at the destination with this cohort.")
	if j.progress != j.days or _room(core, j.destination, id) < j.n: return core.fail("Route work or reception capacity incomplete.")
	j.stage = "holding"
	j.arrived = _day(core.state)
	return core.ok("Cohort ashore in reception; two distinct service days remain.")

func recall(core, id: String):
	if not ensure(core) or not _ready(): return core.fail("Regional service unavailable.")
	var j = _job(core, id)
	if j == null or j.stage == "returning": return core.fail("Unknown/completed/already returning voyage.")
	if j.stage == "holding":
		var berths = hooks.berths.call(core)
		if not _dock(core, j.destination) or not _whole(berths, 0, PEOPLE): return core.fail("Visit the holding cohort.")
		if int(berths) - passenger_count(core.state) < j.n: return core.fail("Insufficient passenger berths.")
		if not _atomic(core, [], {"action": "reload", "job": j, "port": j.destination}):
			return core.fail("Cannot physically reload cohort/provisions.")
	j.stage = "returning"
	return core.ok("Return to the origin to discharge this cohort.")

func _finish(core, j, destination: String, loss = false) -> bool:
	var s = core.state[KEY]
	var target = null if loss else core.port(destination)
	if not loss and (target == null or _room(core, destination, j.id) < j.n): return false
	if loss and (s.lostPeople + j.n > LIMIT or s.lostPurse + j.householdPurse + j.expertPurse > LIMIT): return false
	var account = hooks.fleet_account.call(core)
	if not (account is Array) or account.size() != 2: return false
	if not (account[0] is Dictionary) or not (account[1] is String): return false
	if not _whole(account[0].get(account[1])): return false
	var earned = maxi(0, int(j.n) * 100 * int(j.progress) - int(j.foodCost))
	var sponsor = core.port(j.origin)
	var receiver = s if loss else target
	var hkey = "lostPurse" if loss else "householdPurse"
	var ekey = "lostPurse" if loss else "expertPurse"
	var moves = [[j, "householdPurse", receiver, hkey, int(j.householdPurse)],
		[j, "expertPurse", receiver, ekey, int(j.expertPurse)],
		[j, "escrow", account[0], account[1], earned],
		[j, "escrow", sponsor, "governmentPurse", int(j.escrow) - earned]]
	var event = {"action": "lose" if loss else "release", "job": j, "port": destination}
	if not _atomic(core, moves, event): return false
	if loss:
		s.lostPeople = int(s.lostPeople) + int(j.n)
		s.lostSpecialists = int(s.lostSpecialists) + int(j.specialists)
		s.lostRecruits = int(s.lostRecruits) + int(j.recruits)
		for role in ROLES: s.lostQualified[role] = int(s.lostQualified[role]) + int(j.qualified[role])
	else:
		_people(target, j, 1)
	s.jobs.erase(j)
	core.log_entry("Resettlement %s settled: %s." % [j.id, "recorded loss" if loss else destination])
	return true

func return_to_origin(core, id: String):
	if not ensure(core) or not _ready(): return core.fail("Regional service unavailable.")
	var j = _job(core, id)
	if j == null or j.stage == "holding": return core.fail("Cohort is absent or still ashore.")
	if not _dock(core, j.origin): return core.fail("Physically return to the origin.")
	if not _finish(core, j, j.origin): return core.fail("Origin capacity or settlement unavailable.")
	return core.ok("Existing people/savings returned; only unearned escrow refunded.")

func lose(core, id: String):
	if not ensure(core) or not _ready(): return core.fail("Regional service unavailable.")
	var j = _job(core, id)
	if j == null: return core.fail("Unknown/completed voyage.")
	if not _finish(core, j, "", true): return core.fail("Loss settlement unavailable.")
	return core.ok("Loss recorded once; savings retained in the counted lost purse.")

func daily(core):
	if not ensure(core) or not _ready(): return core.fail("Regional service unavailable.")
	var s = core.state[KEY]
	var day = _day(core.state)
	if day <= s.lastDay: return core.ok("Regional day already processed.")
	s.lastDay = day
	for p in core.state.ports:
		if p.get("id")!=World068.REMOTE_PORT068:_observe(s, p, day)
	for j in s.jobs.duplicate():
		if j.lastFed < day:
			if _atomic(core, [], {"action": "eat", "job": j, "day": day}):
				j.lastFed = day
				j.hungryDays = 0
			else:
				j.hungryDays = mini(999, int(j.hungryDays) + 1)
		if j.stage != "holding":
			if day > j.created and hooks.travel_day.call(core, j, day) == true:
				j.progress = mini(int(j.days), int(j.progress) + 1)
			continue
		if j.served == 2:
			_finish(core, j, j.destination)
			continue
		if day <= j.arrived or j.lastFed != day or _room(core, j.destination, j.id) < j.n: continue
		var p = core.port(j.destination)
		var moves = [[j, "escrow", p, "householdPurse", int(j.handlers) * 100],
			[j, "escrow", p, "expertPurse", 175]]
		if _atomic(core, moves, {"action": "handle", "job": j, "port": j.destination, "day": day}):
			j.served = int(j.served) + 1
			if j.served == 2: _finish(core, j, j.destination)
	return core.ok("Regional day processed without synthetic catch-up days.")

func passenger_count(state: Dictionary) -> int:
	var total = 0
	for j in state.get(KEY, {}).get("jobs", []):
		if j.stage != "holding": total += int(j.n)
	return total

func held_people(state: Dictionary) -> int:
	var total = 0
	for j in state.get(KEY, {}).get("jobs", []): total += int(j.n)
	return total

func escrow_total(state: Dictionary) -> int:
	var total = 0
	for j in state.get(KEY, {}).get("jobs", []): total += int(j.escrow)
	return total

func report(core) -> Dictionary:
	if not ensure(core): return {"error": "Invalid regional state; preserved."}
	var s = core.state[KEY]
	return {"crises": s.crises.duplicate(true), "jobs": s.jobs.duplicate(true),
		"passengers": passenger_count(core.state), "heldPeople": held_people(core.state),
		"escrow": escrow_total(core.state), "lostPeople": s.lostPeople, "lostPurse": s.lostPurse}
