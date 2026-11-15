extends RefCounted
## Raw preflight before normalizers/restore publication.
## Historical snapshots never contribute people, food, housing or money.
const ID = "common_passage110"
const RUST = "rust_anchorage"
const REED = "reed_floats"
const ANVIL = "anvil_dock"
const INTRO = "names_on_paper115"
const WORK = "witness_board115"
const ACCOUNT = "witness_account115"
const NEXT = "two_distress116"
const SURVIVED = "witnesses_discharged115"
const ROUTES = {"choose_public115":REED, "choose_protected115":ANVIL}
const FLAGS = {"reed_floats":"witness_public115", "anvil_dock":"witness_protected115"}
const IMMUTABLE = ["id", "serial", "origin", "destination", "n", "specialists",
	"recruits", "qualified", "created", "days", "wage", "handlers", "foodCost"]
const MUTABLE = ["householdPurse", "expertPurse", "escrow", "food", "stage",
	"arrived", "lastFed", "hungryDays", "progress", "served"]

static func number(v, low: float = 0, high: float = 1000000000000.0, whole: bool = false) -> bool:
	return ((v is int or v is float) and is_finite(float(v))
		and float(v) >= low and float(v) <= high
		and (not whole or floorf(float(v)) == float(v)))

static func text(v) -> bool:
	return v is String and not v.is_empty() and v.length() <= 120

static func shape(v, keys: Array) -> bool:
	if not v is Dictionary or v.size() != keys.size(): return false
	for key in keys:
		if not v.has(key): return false
	return true

static func identity(j) -> Dictionary:
	if not j is Dictionary: return {}
	var copy: Dictionary = j.duplicate(true)
	var out: Dictionary = {}
	for key in IMMUTABLE: out[key] = copy.get(key)
	return out

static func find(state: Dictionary, id) -> Dictionary:
	var regional = state.get("regionalCrises", {})
	if not regional is Dictionary or not regional.get("jobs", []) is Array: return {}
	for j in regional.get("jobs", []):
		if j is Dictionary and j.get("id") == id: return j
	return {}

static func terms(q, destination) -> bool:
	if not q is Dictionary or not FLAGS.has(destination): return false
	if q.get("origin") != RUST or q.get("destination") != destination: return false
	if not number(q.get("count"), 2, 2, true) or not number(q.get("days"), 1, 30, true): return false
	if not number(q.get("handlers"), 1, 1, true): return false
	var gross: float = 200.0 * float(q.days)
	return number(q.get("foodCost"), 0, gross, true) and number(q.get("funded"), gross + 550, gross + 550, true)

static func _basis(j, native_day: float) -> bool:
	if not j is Dictionary or j.get("origin") != RUST or not FLAGS.has(j.get("destination")): return false
	if not number(j.get("serial"), 1, 999999999999.0, true): return false
	if j.get("id") != "rs_%d" % int(j.serial) or not number(j.get("n"), 2, 2, true): return false
	if not number(j.get("created"), 0, native_day, true) or not number(j.get("days"), 1, 30, true): return false
	if not number(j.get("wage"), 100, 100, true) or not number(j.get("handlers"), 1, 1, true): return false
	if not number(j.get("foodCost"), 0, 200.0 * float(j.days), true): return false
	if not number(j.get("specialists"), 0, 2, true) or not number(j.get("recruits"), 0, 2, true): return false
	var q = j.get("qualified")
	if not shape(q, ["sailor", "gunner", "mechanic", "boarder"]): return false
	if not number(q.sailor, 0, 2, true): return false
	for role in ["gunner", "mechanic", "boarder"]:
		if not number(q[role], 0, float(q.sailor), true): return false
	return q.gunner + q.mechanic + q.boarder <= q.sailor

static func bound(b, now: float) -> bool:
	if not shape(b, ["job", "carrierUid", "acceptedDay"]): return false
	if not shape(b.job, IMMUTABLE) or not text(b.carrierUid): return false
	if not number(b.acceptedDay, 0, now): return false
	# Native created is its own econDay integer; it may precede selection.
	return _basis(b.job, floorf(float(b.acceptedDay)))

static func snapshot(j, native_day: float) -> bool:
	if not shape(j, IMMUTABLE + MUTABLE) or not _basis(j, native_day): return false
	for key in ["householdPurse", "expertPurse", "escrow"]:
		if not number(j[key], 0, 1000000000000.0, true): return false
	if not j.food is Dictionary or j.food.size() > 32: return false
	for key in j.food:
		if not (key is String or key is StringName) or not text(str(key)) or not number(j.food[key]): return false
	if j.stage not in ["aboard", "holding", "returning"]: return false
	if not number(j.arrived, -1, native_day, true): return false
	if not number(j.lastFed, float(j.created) - 1, native_day, true): return false
	if not number(j.hungryDays, 0, 999, true): return false
	if not number(j.progress, 0, minf(float(j.days), native_day - float(j.created)), true): return false
	if not number(j.served, 0, 2, true): return false
	if j.stage == "aboard" and (j.arrived != -1 or j.served != 0): return false
	if j.stage == "holding" and j.arrived < j.created: return false
	if j.arrived < 0 and j.served != 0: return false
	if j.arrived >= 0 and (j.progress != j.days or j.served > native_day - j.arrived): return false
	return j.escrow == 200 * j.days + (2 - j.served) * 275 - j.foodCost

static func closed(q, b, destination, now: float) -> bool:
	if not bound(b, now) or not shape(q, ["job", "carrierUid", "destination", "loss", "earned", "day"]): return false
	if not number(q.day, float(b.acceptedDay), now) or not snapshot(q.job, floorf(float(q.day))): return false
	if identity(q.job) != b.job or not text(q.carrierUid) or not q.loss is bool: return false
	# Native recall may physically reload a returning cohort into another boat.
	if q.carrierUid != b.carrierUid and q.job.stage != "returning": return false
	if not number(q.earned, 0, 1000000000000.0, true): return false
	if q.earned != maxi(0, 200 * int(q.job.progress) - int(q.job.foodCost)) or q.earned > q.job.escrow: return false
	if q.loss: return q.destination == ""
	if q.destination == RUST: return q.job.stage != "holding"
	if q.destination != destination or q.job.stage != "holding": return false
	return (q.job.progress == q.job.days and q.job.served == 2
		and q.job.arrived >= q.job.created
		and q.job.lastFed >= q.job.arrived + 2
		and floorf(float(q.day)) >= q.job.arrived + 2)

static func selection(w, flags) -> bool:
	if not w is Dictionary or not flags is Array: return false
	if w.get("origin") != RUST or not FLAGS.has(w.get("destination")): return false
	if not ROUTES.has(w.get("choiceId")) or ROUTES[w.choiceId] != w.destination: return false
	var other: String = ANVIL if w.destination == REED else REED
	return flags.count(FLAGS[w.destination]) == 1 and flags.count(FLAGS[other]) == 0

static func validate(state: Dictionary) -> String:
	var stories = state.get("stories", {})
	if not stories is Dictionary or not stories.get("chains", {}) is Dictionary:
		return "115: validate raw story structure first."
	var chains: Dictionary = stories.get("chains", {})
	var rec = chains.get(ID, {})
	var optional = chains.get("wren_witness115", {})
	if not rec is Dictionary or not optional is Dictionary: return "115: invalid chapter record."
	var flags = rec.get("flags", [])
	if not flags is Array: return "115: flags must remain an array."
	for flag in flags:
		if not flag is String: return "115: invalid raw flag."
	var required: bool = rec.get("stage") in [WORK, ACCOUNT, NEXT]
	if not rec.has("work115"):
		for flag in FLAGS.values() + [SURVIVED]:
			if flags.has(flag): return "115: witness flag lacks its undertaking."
		return "115: missing witness undertaking." if required or not optional.is_empty() else ""
	var w = rec.work115
	if not shape(w, ["origin", "destination", "choiceId", "selectedDay", "binding", "closure", "reported", "reportDay"]):
		return "115: invalid bounded undertaking."
	if not number(state.get("day")) or not number(state.get("econDay"), 0, floorf(float(state.day)), true):
		return "115: invalid campaign/native calendars."
	var now: float = float(state.day)
	var native_day: float = float(state.econDay)
	if not selection(w, flags) or not number(w.selectedDay, 0, now): return "115: invalid disclosed destination."
	if not w.binding is Dictionary or not w.closure is Dictionary or not w.reported is bool:
		return "115: invalid raw undertaking types."
	if rec.get("stage") == INTRO or (rec.get("stage") == WORK and w.reported):
		return "115: destination/report stage mismatch."
	if rec.get("stage") in [ACCOUNT, NEXT] and not w.reported: return "115: chapter advanced without its report."
	var delivered: bool = false
	var earliest_report: float = float(w.selectedDay)
	if w.binding.is_empty():
		if not w.closure.is_empty(): return "115: unadmitted undertaking claims a closure."
	else:
		var b: Dictionary = w.binding
		if not bound(b, now) or b.job.destination != w.destination or float(b.acceptedDay) < float(w.selectedDay):
			return "115: invalid original native binding."
		var regional = state.get("regionalCrises")
		var transport = state.get("passengerTransport")
		if not regional is Dictionary or not regional.get("jobs") is Array or not number(regional.get("nextId"), 1, 1000000000000.0, true):
			return "115: missing native cohort ledger."
		if not transport is Dictionary or not transport.get("carriers") is Dictionary: return "115: missing native carrier ledger."
		if b.job.serial >= regional.nextId or b.job.created > native_day: return "115: replayed or future native identity."
		var live: Dictionary = find(state, b.job.id)
		if w.closure.is_empty():
			if w.reported or live.is_empty() or not snapshot(live, native_day) or identity(live) != b.job:
				return "115: open cohort vanished or changed without native closure."
			var uid = transport.carriers.get(b.job.id)
			if not text(uid) or (live.stage != "returning" and uid != b.carrierUid):
				return "115: original carrier binding changed."
		else:
			if not live.is_empty() or not closed(w.closure, b, w.destination, now):
				return "115: invalid or replayed native closure."
			if not snapshot(w.closure.job, native_day): return "115: closure contains future native work."
			delivered = not w.closure.loss and w.closure.destination == w.destination
			earliest_report = float(w.closure.day)
	if flags.count(SURVIVED) != (1 if delivered else 0): return "115: survivor flag disagrees with actual discharge."
	if w.reported:
		if not number(w.reportDay, earliest_report, now): return "115: report predates the actual outcome."
	elif not number(w.reportDay, -1, -1): return "115: unreported undertaking contains a report date."
	if not optional.is_empty():
		if not delivered: return "115: Wren conversation lacks two discharged survivors."
		if optional.get("stage") != "wren_hearing115" or not optional.get("flags") is Array or not optional.get("done") is bool:
			return "115: invalid optional Wren progress."
	return ""
