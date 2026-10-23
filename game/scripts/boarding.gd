class_name Boarding
extends RefCounted
const Money=preload("res://scripts/money.gd")
const Goods=preload("res://scripts/goods.gd")

const PEOPLE := 1000000
const CASH := 1000000000000
const JOBS := 32
const PRIZES := 64
const RULES := {
	"battery": {"crew": 6, "hands": 4, "experts": 2, "ammo": 12,
		"timber": 16, "iron": 6, "supplies": 4, "labor": 2150},
	"garrison": {"crew": 4, "hands": 3, "experts": 1, "ammo": 8,
		"timber": 8, "iron": 2, "supplies": 4, "labor": 975}
}

# Required root adapters; missing bindings fail closed.
static var harbor_rules: Callable # (core, port) -> {here, service, friendly}
static var unit_price: Callable # (core, port, good) -> positive integer
static var fleet_capacity: Callable # (core) -> actual roster limit
static var household_key := "householdPurse" # Must name an EXISTING purse.

static func _n(v, cap = PEOPLE) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) \
		and is_finite(float(v)) and v >= 0 and v <= cap

static func _w(v, cap = PEOPLE) -> bool:
	return _n(v, cap) and float(v) == floor(float(v))

static func _yes(v) -> bool:
	return typeof(v) == TYPE_BOOL and v

static func _id(v) -> bool:
	return (typeof(v) == TYPE_STRING and v.length() > 0 and v.length() <= 128) \
		or (typeof(v) == TYPE_INT and v >= 0 and v <= CASH)

static func _bad(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _rows(v) -> Array:
	if v is Dictionary:
		return v.values()
	return v if v is Array else []

static func _has(rows: Array, boat: Dictionary) -> bool:
	for row in rows:
		if is_same(row, boat):
			return true
	return false

static func _cap(b):
	return b.get("crewMax", b.get("spec", {}).get("crewMax", -1))

static func _minimum(b):
	return b.get("crewMin", b.get("spec", {}).get("crewMin", -1))

static func _crew(b) -> bool:
	if not b is Dictionary or not b.get("spec") is Dictionary:
		return false
	return _n(b.get("crew")) and _n(b.get("wounded")) \
		and _n(_cap(b)) and b.crew <= _cap(b) and b.wounded <= b.crew \
		and _w(b.get("boarders", 0)) and b.get("boarders", 0) <= floor(b.crew) \
		and _n(b.get("captives", 0))

static func _live(b) -> bool:
	return _crew(b) and _n(b.get("hp")) and b.hp > 0 \
		and typeof(b.get("sunk", false)) == TYPE_BOOL and not b.get("sunk", false)

static func _near(a: Dictionary, b: Dictionary) -> bool:
	for boat in [a, b]:
		if not _n(boat.spec.get("size"), 1000) or boat.spec.size <= 0:
			return false
		for key in ["x", "y"]:
			var v = boat.get(key)
			if not (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT):
				return false
			if not is_finite(float(v)) or abs(float(v)) > 1000000000:
				return false
	var reach: float = 80.0 + 0.5 * (a.spec.size + b.spec.size)
	var dx: float = a.x - b.x
	var dy: float = a.y - b.y
	return dx * dx + dy * dy <= reach * reach

static func _vulnerable(b: Dictionary) -> bool:
	if _yes(b.get("suppressed")) or _yes(b.get("surrendering")):
		return true
	if _n(b.get("engine"), 1) and b.engine <= 0.2:
		return true
	if _n(b.get("maxHp")) and b.maxHp > 0 and b.hp <= b.maxHp * 0.35:
		return true
	if _n(_minimum(b)) and b.crew - b.wounded <= maxf(1, _minimum(b) * 0.5):
		return true
	return _n(b.get("water")) and _n(b.get("capacity")) \
		and b.capacity > 0 and b.water >= b.capacity * 0.7

static func _pay(core, src: Dictionary, key: String, dst: Dictionary,
		dest: String, amount: int, reason: String) -> bool:
	if not _w(amount, CASH) or not _w(src.get(key), CASH) \
		or not _w(dst.get(dest), CASH) or src[key] < amount \
		or dst[dest] + amount > CASH or not core.state.get("moneyLog") is Array:
		return false
	var before: int = int(src[key])
	var after: int = int(dst[dest])
	if amount > 0:
		Money.move(src, key, dst, dest, amount, reason, core.state.moneyLog)
	return src[key] == before - amount and dst[dest] == after + amount

static func _port(core, friendly: bool) -> Dictionary:
	var p = core.current_port()
	if not p is Dictionary or not _id(p.get("id")) or not harbor_rules.is_valid():
		return {}
	if not is_same(core.port(p.id), p):
		return {}
	var access = harbor_rules.call(core, p)
	if not access is Dictionary or not _yes(access.get("here")) \
		or not _yes(access.get("service")):
		return {}
	if friendly and not _yes(access.get("friendly")):
		return {}
	return p

static func _people(p: Dictionary, count: int, boarders: bool) -> bool:
	var training = p.get("training", {})
	if not training is Dictionary or not training.get("qualified") is Dictionary:
		return false
	var q: Dictionary = training.qualified
	for key in ["workforce", "availableWorkers", "recruits", "specialists", "availableSpecialists"]:
		if not _n(p.get(key)):
			return false
	for key in ["sailor", "boarder", "gunner", "mechanic"]:
		if not _w(q.get(key, 0)):
			return false
	if q.get("sailor", 0) > floor(p.workforce) or p.specialists > p.workforce \
		or p.availableSpecialists > p.specialists \
		or p.availableWorkers > p.workforce \
		or p.recruits > p.workforce:
		return false
	for key in ["boarder", "gunner", "mechanic"]:
		if q.get(key, 0) > q.get("sailor", 0):
			return false
	if p.availableWorkers < count or p.recruits < count \
		or p.workforce - p.specialists < count or q.get("sailor", 0) < count:
		return false
	if boarders:
		return q.get("boarder", 0) >= count
	# Guaranteed general sailors, even when specialty subsets overlap.
	return q.sailor - q.get("boarder", 0) - q.get("gunner", 0) \
		- q.get("mechanic", 0) >= count

static func _take_people(p: Dictionary, count: int, boarders: bool) -> void:
	p.workforce -= count
	p.availableWorkers -= count
	p.recruits -= count
	var q: Dictionary = p.training.qualified
	q.sailor -= count
	if boarders:
		q.boarder -= count
		# Root academy specialties are disjoint subsets; other skilled residents remain.

static func _day(core) -> int:
	var day = core.state.get("econDay")
	return int(day) if _w(day) else -1

static func ensure_state(core) -> void:
	var s: Dictionary = core.state
	for pair in [["captives", 0], ["boardingSerial", 0], ["boardingPrizes", []]]:
		if not s.has(pair[0]):
			s[pair[0]] = pair[1]
	for b in _rows(s.get("fleet", [])):
		if b is Dictionary and not b.has("boarders"):
			b["boarders"] = 0

static func hire_party(core, boat_uid, count) -> Dictionary:
	ensure_state(core)
	if not _w(count, 1000) or count < 1:
		return _bad("Invalid hiring count")
	var p := _port(core, false)
	var b = core.find_boat(boat_uid)
	if p.is_empty() or not _live(b) or not _has(core.state.fleet, b):
		return _bad("A living fleet boat at an accessible harbor is required")
	var n := int(count)
	if not _people(p, n, true):
		return _bad("Not enough qualified, available boarder recruits")
	if b.crew + n > _cap(b):
		return _bad("Not enough physical berths")
	var cost: int = n * Goods.SAILOR_WAGE * 10
	if not _pay(core, core.state, "coins", core.state, "crewPurse",
			cost, "Boarder hiring advance"):
		return _bad("Hiring advance unavailable")
	_take_people(p, n, true)
	b.crew += n
	b["boarders"] = int(b.get("boarders", 0)) + n
	return {"ok": true, "count": n, "cost": cost}

static func _ship(battle: Dictionary, uid) -> Dictionary:
	var found: Dictionary = {}
	for b in battle.get("ships", []):
		if b is Dictionary and _id(b.get("id",b.get("uid"))) and str(b.get("id",b.get("uid"))) == str(uid):
			if not found.is_empty():
				return {}
			found = b
	return found

static func _setup(battle: Dictionary) -> bool:
	if not battle.get("ships") is Array or not battle.get("rng") is RandomNumberGenerator:
		return false
	if not battle.has("boarding"):
		battle["boarding"] = {"clock": 0.0, "next": 1, "jobs": []}
	if not battle.has("captured"):
		battle["captured"] = []
	var s = battle.boarding
	return s is Dictionary and s.get("jobs") is Array \
		and s.jobs.size() <= JOBS and _w(s.get("next")) and s.next >= 1 \
		and _n(s.get("clock"), 1000000000) and battle.captured is Array

static func launch(battle: Dictionary, source_id, target_id, count) -> Dictionary:
	if not _w(count, 128) or count < 1 or not _id(source_id) or not _id(target_id):
		return _bad("Invalid boarding order")
	var source := _ship(battle, source_id)
	var target := _ship(battle, target_id)
	if not _live(source) or not _live(target) or source.get("team") != "player" \
		or target.get("team") != "enemy" or str(source_id) == str(target_id):
		return _bad("A living player source and enemy target are required")
	if _yes(source.get("supportOnly")) or _yes(target.get("captureSecured")) \
		or not _near(source, target) or not _vulnerable(target):
		return _bad("Target cannot be boarded here")
	var n := int(count)
	if n>_cap(target) or n+target.crew>_cap(target)+floorf(float(target.spec.get("cargo",0))):return _bad("Party and defenders need physical prize berths or empty deck space")
	if not _n(_minimum(source)) or n > source.get("boarders", 0) - ceili(source.wounded) \
		or source.crew - source.wounded - n < _minimum(source):
		return _bad("Not enough healthy boarders above minimum crew")
	if not _setup(battle) or battle.boarding.jobs.size() >= JOBS \
		or battle.boarding.next >= PEOPLE:
		return _bad("Boarding job limit or invalid battle")
	for j in battle.boarding.jobs:
		if j.status == "active" and (str(j.source) == str(source_id) \
				or str(j.target) == str(target_id)):
			return _bad("Source or target already has a boarding job")
	var id := "boarding-%d" % int(battle.boarding.next)
	battle.boarding.next += 1
	source.crew -= n
	source["boarders"] = int(source.get("boarders", 0)) - n
	battle.boarding.jobs.append({"id": id, "source": source_id, "target": target_id,
		"initial": n, "alive": n, "killed": 0, "defenderKilled": 0,
		"returned": 0, "lost": 0, "prize": 0, "captives": 0.0,
		"round": 0, "next": battle.boarding.clock + 2.0, "status": "active",
		"recovery": "pending"})
	return {"ok": true, "id": id}

static func _finish(battle: Dictionary, j: Dictionary, why: String, recover: bool) -> void:
	var returned := 0
	var source := _ship(battle, j.source)
	var target := _ship(battle, j.target)
	if recover and _live(source) and _live(target) and _near(source, target):
		returned = mini(int(j.alive), maxi(0, floori(_cap(source) - source.crew)))
		source.crew += returned
		source["boarders"] = int(source.get("boarders", 0)) + returned
	j.returned += returned
	j.lost += j.alive - returned
	j.alive = 0
	j.status = why
	j.recovery = "returned" if j.lost == 0 else ("partial" if returned > 0 else "lost")

static func abort(battle: Dictionary, job_id) -> Dictionary:
	if _setup(battle):
		for j in battle.boarding.jobs:
			if j.id == job_id and j.status == "active":
				_finish(battle, j, "aborted", true)
				return {"ok": true, "returned": j.returned, "lost": j.lost,
					"recovery": j.recovery}
	return _bad("No active boarding job")

static func _capture(battle: Dictionary, j: Dictionary, target: Dictionary) -> void:
	if target.get("captives", 0) + target.crew > PEOPLE:
		_finish(battle, j, "captive_limit", true)
		return
	j.captives = target.crew
	target["captives"] = target.get("captives", 0) + target.crew
	target.crew = float(j.alive)
	target.wounded = 0.0
	target["boarders"] = int(j.alive)
	target.team = "player"
	for key in ["captureSecured", "needsHarborRepair", "supportOnly"]:
		target[key] = true
	target["boardingSettled"] = false
	j.prize = j.alive
	j.alive = 0
	j.status = "captured"
	j.recovery = "prize_crew"
	if not _has(battle.captured, target):
		battle.captured.append(target)

static func _exchange(battle: Dictionary, j: Dictionary) -> void:
	var source := _ship(battle, j.source)
	var target := _ship(battle, j.target)
	if not _live(source) or not _live(target):
		_finish(battle, j, "hull_lost", false)
		return
	if not _near(source, target):
		_finish(battle, j, "escaped", false)
		return
	j.round += 1
	j.next += 2.0
	var defenders := maxi(0, floori(target.crew - target.wounded))
	if defenders > 0 and not _yes(target.get("surrendering")):
		var party_loss := mini(int(j.alive), battle.rng.randi_range(
			0, mini(8, maxi(1, ceili(defenders / 6.0)))))
		var defender_loss := mini(defenders, battle.rng.randi_range(
			1, maxi(1, ceili(j.alive / 2.0))))
		j.alive -= party_loss
		j.killed += party_loss
		j.defenderKilled += defender_loss
		target.crew -= defender_loss
		target["boarders"] = maxi(0, int(target.get("boarders", 0)) - defender_loss)
	if j.alive == 0:
		j.status = "defeated"
		j.recovery = "none_survived"
	elif j.round >= 2 and (_yes(target.get("surrendering")) \
			or floori(target.crew - target.wounded) <= floori(j.alive * 0.5)):
		_capture(battle, j, target)
	elif j.round >= 30:
		_finish(battle, j, "stalled", true)

static func tick(battle: Dictionary, dt) -> void:
	if not battle.has("boarding") or not _n(dt, 3600) or dt <= 0 or not _setup(battle):
		return
	var stop: float = battle.boarding.clock + dt
	if stop > 1000000000:
		return
	# Global chronological ordering keeps RNG consumption independent of tick grouping.
	for unused in range(JOBS * 30):
		var due: Dictionary = {}
		for j in battle.boarding.jobs:
			if j.status == "active" and j.next <= stop \
				and (due.is_empty() or j.next < due.next):
				due = j
		if due.is_empty():
			break
		_exchange(battle, due)
	battle.boarding.clock = stop

static func _uid_used(s: Dictionary, uid, boat: Dictionary) -> bool:
	if not _id(uid):
		return true
	for b in s.fleet + s.boardingPrizes:
		if not is_same(b, boat) and str(b.get("uid")) == str(uid):
			return true
	return false

static func settle(core, battle: Dictionary) -> Dictionary:
	ensure_state(core)
	var s: Dictionary = core.state
	if not fleet_capacity.is_valid() or not s.get("fleet") is Array \
		or not s.boardingPrizes is Array or not _w(s.boardingSerial) \
		or not _n(s.captives) or not _setup(battle):
		return _bad("Invalid settlement state or missing capacity adapter")
	var limit = fleet_capacity.call(core)
	if not _w(limit, 256) or limit < 1:
		return _bad("Invalid roster capacity")
	for j in battle.boarding.jobs:
		if j.status == "active":
			_finish(battle, j, "settled", true)
	var incoming: Array = []
	var extra := 0
	var prisoners: float = 0
	for b in battle.captured:
		if not _live(b) or not _yes(b.get("captureSecured")) \
			or not _yes(b.get("supportOnly")) or not _yes(b.get("needsHarborRepair")):
			return _bad("Captured hull requires root reconciliation")
		if _has(incoming, b):
			continue
		incoming.append(b)
		if not _has(s.fleet, b) and not _has(s.boardingPrizes, b):
			extra += 1
		if not _yes(b.get("boardingSettled")):
			prisoners += b.get("captives", 0)
	if s.boardingPrizes.size() + extra > PRIZES or s.captives + prisoners > PEOPLE:
		return _bad("Prize or captive holding capacity reached; retain battle")
	for b in incoming:
		if _uid_used(s, b.get("uid"), b):
			var uid := ""
			while s.boardingSerial < PEOPLE:
				s.boardingSerial += 1
				var candidate := "prize-%d" % int(s.boardingSerial)
				if not _uid_used(s, candidate, b):
					uid = candidate
					break
			if uid.is_empty():
				return _bad("Prize UID space exhausted; retain unresolved battle")
			b["uid"] = uid
		if not _has(s.fleet, b) and not _has(s.boardingPrizes, b):
			s.boardingPrizes.append(b)
		if not _yes(b.get("boardingSettled")):
			s.captives += b.get("captives", 0)
			b["captives"] = 0.0
			b["boardingSettled"] = true
	var added := 0
	while s.fleet.size() < limit and not s.boardingPrizes.is_empty():
		s.fleet.append(s.boardingPrizes.pop_front())
		added += 1
	return {"ok": true, "added": added, "pending": s.boardingPrizes.size(),
		"captivesMoved": prisoners}

static func _defense_ok(d) -> bool:
	if not d is Dictionary or not RULES.has(d.get("kind")) \
		or not _w(d.get("units"), 4) or d.units < 1:
		return false
	var r: Dictionary = RULES[d.kind]
	if not _w(d.get("crew"), r.crew * d.units) or d.get("guns") != d.units \
		or not _w(d.get("guns"), 4) or not _w(d.get("ammo"), r.ammo * d.units) \
		or not _w(d.get("arrears"), CASH) or not _w(d.get("lastDay")) \
		or typeof(d.get("active")) != TYPE_BOOL or not _n(d.get("strength"), 4) \
		or not d.get("reason") is String or d.reason.length() > 128:
		return false
	var strength: float = d.crew / float(r.crew) if d.active else 0.0
	return abs(d.strength - strength) < 0.000001 and (not d.active \
		or (d.crew >= ceili(r.crew * d.units * 0.5) and d.ammo > 0 and d.arrears == 0))

static func _disable(d: Dictionary, reason: String) -> void:
	d.active = false
	d.strength = 0.0
	d.reason = reason

static func defense_quote(core, kind: String, count) -> Dictionary:
	if not RULES.has(kind) or not _w(count, 4) or count < 1 or _day(core) < 0:
		return _bad("Invalid defense request")
	var p := _port(core, true)
	if p.is_empty() or not unit_price.is_valid():
		return _bad("Friendly harbor authority and economy pricing are required")
	var r: Dictionary = RULES[kind]
	var n := int(count)
	if p.has("defenses") and (not _defense_ok(p.defenses) \
		or p.defenses.kind != kind or p.defenses.units + n > 4 \
		or p.defenses.lastDay != _day(core)):
		return _bad("Defense type, capacity or daily accounting blocks construction")
	if not _people(p, r.crew * n, false) \
		or p.availableWorkers < (r.crew + r.hands) * n \
		or p.availableSpecialists < r.experts * n:
		return _bad("Real trained recruits, labor and oversight are required")
	var stores = p.get("publicStores")
	var purses: Dictionary = p
	if not stores is Dictionary or not purses is Dictionary \
		or not _w(p.get("governmentPurse"), CASH) \
		or not _w(purses.get(household_key), CASH):
		return _bad("Missing public stores or existing household accounts")
	var goods := {"guns": n, "ammo": r.ammo * n, "timber": r.timber * n,
		"iron": r.iron * n, "supplies": r.supplies * n}
	var ordinary: int = (1200 if kind=="battery" else 800)*n
	var expert: int = (950 if kind=="battery" else 175)*n
	var days: float = (18.0 if kind=="battery" else 9.0)*n
	var expert_days: float = (6.0 if kind=="battery" else 1.0)*n
	if float(p.get("_yardWorkersUsed",0))+days+float(r.crew*n)>float(p.availableWorkers) or float(p.get("_yardSpecialistsUsed",0))+expert_days>float(p.availableSpecialists):return _bad("Construction needs its complete paid labor and oversight days")
	var labor: int = ordinary+expert
	var cost := labor
	for good in goods:
		var price = unit_price.call(core, p, good)
		if not _w(price) or price < 1 or not _n(stores.get(good)) or stores[good] < goods[good]:
			return _bad("Missing priced public materials")
		cost += int(price) * int(goods[good])
	if not _w(core.state.get("coins"), CASH) or core.state.coins < cost \
		or p.governmentPurse + cost > CASH or purses[household_key] + labor > CASH or not _w(p.get("expertPurse"),CASH) or p.expertPurse+labor>CASH \
		or not core.state.get("moneyLog") is Array:
		return _bad("Captain contribution or account capacity is insufficient")
	return {"ok": true, "kind": kind, "count": n, "crew": r.crew * n,
		"goods": goods, "labor": labor,"ordinary":ordinary,"expert":expert,"days":days,"expertDays":expert_days, "cost": cost, "day": _day(core)}

static func build_defense(core, kind: String, count) -> Dictionary:
	var quote := defense_quote(core, kind, count)
	if not quote.ok:
		return quote
	var p: Dictionary = core.current_port()
	if not _pay(core, core.state, "coins", p, "governmentPurse",
			quote.cost, "Harbor defense contribution"):
		return _bad("Contribution transfer failed")
	_pay(core,p,"governmentPurse",p,household_key,quote.ordinary,"Defense construction labor")
	_pay(core,p,"governmentPurse",p,"expertPurse",quote.expert,"Defense gunsmiths and foremen")
	p._yardWorkersUsed=float(p.get("_yardWorkersUsed",0))+quote.days
	p._yardSpecialistsUsed=float(p.get("_yardSpecialistsUsed",0))+quote.expertDays
	_take_people(p, quote.crew, false)
	for good in quote.goods:
		p.publicStores[good] -= quote.goods[good]
	var d: Dictionary = p.get("defenses", {"kind": kind, "units": 0, "crew": 0,
		"guns": 0, "ammo": 0, "arrears": 0, "lastDay": quote.day})
	d.units += quote.count
	d.crew += quote.crew
	d.guns += quote.count
	d.ammo += quote.goods.ammo
	_disable(d, "Commissioning; awaiting next daily payroll")
	p["defenses"] = d
	return quote

static func daily_defenses(core) -> void:
	var today := _day(core)
	if today < 0:
		return
	for p in _rows(core.state.get("ports", [])):
		if not p is Dictionary or not p.get("defenses") is Dictionary:
			continue
		var d: Dictionary = p.defenses
		if not _defense_ok(d):
			_disable(d, "Invalid defense state")
			continue
		if d.lastDay >= today:
			continue
		var days: int = today - int(d.lastDay)
		var due: int = int(d.arrears) + int(d.crew) * Goods.SAILOR_WAGE * days
		d.lastDay = today
		var purses: Dictionary = p
		if not purses is Dictionary or not _pay(core, p, "governmentPurse",
				purses, household_key, due, "Coastal defense wages"):
			d.arrears = due
			_disable(d, "Unpaid defense wages")
			continue
		d.arrears = 0
		var stores = p.get("publicStores")
		var food := ceili(d.crew / 4.0) * days
		var kits: int = int(d.units) * days
		if not stores is Dictionary or not _n(stores.get("food")) or stores.food < food:
			_disable(d, "Public food unavailable")
			continue
		if not _n(stores.get("supplies")) or stores.supplies < kits \
			or not _n(stores.get("ammo", 0)):
			_disable(d, "Public support or ammunition inventory unavailable")
			continue
		stores.food -= food
		stores.supplies -= kits
		var refill := mini(int(RULES[d.kind].ammo * d.units - d.ammo),
			int(stores.get("ammo", 0)))
		d.ammo += refill
		stores["ammo"] = int(stores.get("ammo", 0)) - refill
		if d.ammo <= 0 or d.crew < ceili(RULES[d.kind].crew * d.units * 0.5):
			_disable(d, "Insufficient ammunition or defense crew")
		else:
			d.active = true
			d.strength = d.crew / float(RULES[d.kind].crew)
			d.reason = "Ready"

static func take_defense_shot(p: Dictionary) -> Dictionary:
	var d = p.get("defenses")
	if not _defense_ok(d) or not d.active:
		return _bad("Defense is inactive")
	var strength: float = d.strength
	d.ammo -= 1
	if d.ammo == 0:
		_disable(d, "Ammunition exhausted")
	var battery: bool = d.kind == "battery"
	return {"ok": true, "ammoSpent": 1, "strength": strength,
		"damage": minf(20, 12 + strength * 2) if battery else minf(10, 6 + strength),
		"range": 600.0 if battery else 180.0,
		"speed": 260.0, "cooldown": 4.0 if battery else 6.0}

static func validate(state, world) -> String:
	if not state is Dictionary or not state.get("fleet") is Array \
		or not state.get("boardingPrizes", []) is Array:
		return "Invalid fleet or prize arrays"
	if state.fleet.size() > 256 or state.get("boardingPrizes", []).size() > PRIZES \
		or not _n(state.get("captives", 0)) or not _w(state.get("boardingSerial", 0)):
		return "Invalid boarding capacity, captives or UID counter"
	var seen := {}
	for b in state.fleet + state.get("boardingPrizes", []):
		if not _crew(b) or not _id(b.get("uid")) or seen.has(str(b.uid)):
			return "Invalid boat people, berths or unique UID"
		seen[str(b.uid)] = true
		for key in ["captureSecured", "needsHarborRepair", "supportOnly", "boardingSettled"]:
			if b.has(key) and typeof(b[key]) != TYPE_BOOL:
				return "Invalid capture flag"
		if _yes(b.get("needsHarborRepair")) and not _yes(b.get("supportOnly")):
			return "Unrepaired capture must remain support only"
	for b in state.get("boardingPrizes", []):
		if not _yes(b.get("captureSecured")) or not _yes(b.get("supportOnly")) \
			or not _yes(b.get("needsHarborRepair")) or not _yes(b.get("boardingSettled")):
			return "Invalid saved prize custody"
	var ports = state.get("ports", [])
	if not (ports is Array or ports is Dictionary):
		return "Invalid ports"
	var known := {}
	if world is Dictionary:
		for p in _rows(world.get("ports", [])):
			if p is Dictionary and _id(p.get("id")):
				known[str(p.id)] = true
	for p in _rows(ports):
		if not p is Dictionary:
			return "Invalid port record"
		if not p.has("defenses"):
			continue
		if not _id(p.get("id")) or not known.has(str(p.id)):
			return "Defense references an unknown world port"
		if not _defense_ok(p.defenses) or not _people(p, 0, true) \
			or not _w(p.get("governmentPurse"), CASH) or not p is Dictionary \
			or not _w(p.get(household_key), CASH):
			return "Invalid defense cohort or public accounts"
		if not _w(state.get("econDay")) or p.defenses.lastDay > state.econDay:
			return "Invalid defense accounting day"
	return ""
