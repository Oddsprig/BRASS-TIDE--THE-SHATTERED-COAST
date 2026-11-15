extends RefCounted
## One finite undertaking. Native cohorts own all people, provisions and money.
const V = preload("res://scripts/campaign_validation115.gd")
const ID = V.ID
const WORK = V.WORK

static func record(c) -> Dictionary:
	var stories = c.state.get("stories", {})
	if not stories is Dictionary: return {}
	var chains = stories.get("chains", {})
	if not chains is Dictionary: return {}
	var rec = chains.get(ID, {})
	return rec if rec is Dictionary else {}

static func _book(c) -> Dictionary:
	var value = record(c).get("work115", {})
	return value if value is Dictionary else {}

## Detached UI view. count is planned/historical, never additional inventory.
static func work(c) -> Dictionary:
	var w: Dictionary = _book(c)
	if w.is_empty(): return {}
	var out: Dictionary = w.duplicate(true)
	var b: Dictionary = w.binding
	out.count = 2
	out.jobId = "" if b.is_empty() else b.job.id
	out.carrierUid = "" if b.is_empty() else b.carrierUid
	out.nativeStage = ""
	out.status = _status(c, w)
	if not b.is_empty() and w.closure.is_empty():
		var j: Dictionary = V.find(c.state, b.job.id)
		out.nativeStage = j.get("stage", "")
		var uid = c.state.get("passengerTransport", {}).get("carriers", {}).get(b.job.id)
		if V.text(uid): out.carrierUid = uid
	return out

static func _status(c, w: Dictionary) -> String:
	if not w.closure.is_empty():
		if not V.closed(w.closure, w.binding, w.destination, float(c.state.day)):
			return "unresolved"
		if w.closure.loss: return "lost"
		return "delivered" if w.closure.destination == w.destination else "returned"
	if w.binding.is_empty(): return "unfilled" if w.reported else "preparing"
	var j: Dictionary = V.find(c.state, w.binding.job.id)
	if j.is_empty() or V.identity(j) != w.binding.job: return "unresolved"
	return "holding" if j.stage == "holding" else "aboard"

static func _service(c, port_id: String = "") -> Dictionary:
	var p: Dictionary = c.current_port()
	if not c.travel_lock064.is_empty() or not c.state.get("path", []).is_empty() or p.is_empty():
		return c.fail("Stop at an actual harbor first.")
	if not port_id.is_empty() and p.get("id") != port_id:
		return c.fail("Visit the agreed harbor for this conversation.")
	return c.Politics.permit(c, "service")

## Called after C1 advances to WORK; optional revisions remain pre-boarding only.
static func select(c, destination: String) -> Dictionary:
	var rec: Dictionary = record(c)
	if rec.get("stage") != WORK or rec.get("done", false):
		return c.fail("Agree the witness undertaking with Wren first.")
	if not V.FLAGS.has(destination) or not rec.get("flags") is Array:
		return c.fail("Choose public testimony or protected testimony.")
	var permission: Dictionary = _service(c)
	if not permission.get("ok", false): return permission
	var w: Dictionary = _book(c)
	if rec.has("work115") and w.is_empty():
		return c.fail("The existing witness record needs inspection.")
	if not w.is_empty() and (not w.binding.is_empty() or not w.closure.is_empty() or w.reported):
		return c.fail("The admitted cohort's destination cannot be changed.")
	var choice_id: String = "choose_public115" if destination == V.REED else "choose_protected115"
	if w.is_empty():
		w = {"origin":V.RUST, "destination":destination, "choiceId":choice_id,
			"selectedDay":float(c.state.day), "binding":{}, "closure":{},
			"reported":false, "reportDay":-1.0}
		rec.work115 = w
	elif w.destination != destination:
		w.destination = destination
		w.choiceId = choice_id
		w.selectedDay = float(c.state.day)
	for flag in V.FLAGS.values(): rec.flags.erase(flag)
	rec.flags.append(V.FLAGS[destination])
	return c.ok("Destination recorded. No one has boarded.")

static func authorized(c, origin, destination, count) -> bool:
	var rec: Dictionary = record(c)
	var w: Dictionary = _book(c)
	return (rec.get("stage") == WORK and not rec.get("done", false)
		and V.selection(w, rec.get("flags"))
		and origin == V.RUST and destination == w.destination
		and V.number(count, 2, 2, true)
		and w.binding.is_empty() and w.closure.is_empty() and not w.reported)

static func quote(c) -> Dictionary:
	var w: Dictionary = _book(c)
	if not authorized(c, V.RUST, w.get("destination"), 2):
		return c.fail("Select a destination before boarding; an admitted cohort cannot be replaced.")
	var q: Dictionary = c.CrisisOps.witness_quote115(c, w.destination)
	if not V.terms(q, w.destination):
		return c.fail(str(q.get("message", "Two funded, provisioned places are not currently available.")))
	var out: Dictionary = q.duplicate(true)
	out.ok = true
	out.message = "Two existing civilians; government funding %d coins, including %d for provisions. Two reception service days follow arrival. Your fleet pays its operating costs." % [q.funded, q.foodCost]
	return out

static func accept(c, shown: Dictionary) -> Dictionary:
	var permission: Dictionary = _service(c, V.RUST)
	if not permission.get("ok", false): return permission
	var current: Dictionary = quote(c)
	if not current.get("ok", false): return current
	if shown != current:
		return c.fail("Current boarding terms changed. Review the new quotation.")
	var result: Dictionary = c.CrisisOps.begin_witness115(c, current.destination)
	if not result.get("ok", false): return result
	var w: Dictionary = _book(c)
	var id = result.get("id")
	var j: Dictionary = V.find(c.state, id)
	var uid = c.state.get("passengerTransport", {}).get("carriers", {}).get(id)
	# Keep a nonempty binding even if a violated native contract is detected.
	# Never retry admission, roll back resources, or discard the native job here.
	w.binding = {"job":V.identity(j), "carrierUid":uid, "acceptedDay":float(c.state.day)}
	if (not V.bound(w.binding, float(c.state.day))
		or not V.snapshot(j, float(c.state.econDay))
		or j.get("id") != id or j.get("destination") != w.destination
		or j.get("created") != c.state.econDay
		or j.get("stage") != "aboard" or j.get("progress") != 0 or j.get("served") != 0):
		return c.fail("Native boarding completed, but its chapter binding needs inspection. Keep the existing cohort.")
	return result

## Subtract commitments before clamping; never add our count to charter_room().
static func _room(c, destination: String, own_id: String) -> int:
	var p: Dictionary = c.port(destination)
	if p.is_empty(): return 0
	var available: int = c.CrisisOps.Transport.room(c, p)
	for j in c.state.get("regionalCrises", {}).get("jobs", []):
		if j.id != own_id and j.destination == destination and j.stage != "returning":
			available -= int(j.n)
	for j in c.state.get("voyageJobs", []):
		if j.get("kind") == "passenger_charter" and j.get("targetPort") == destination:
			available -= int(j.get("passengers", {}).get("n", 0))
	return maxi(0, available)

## Native arrival and successful-finalization preflight only.
## Unrelated regional jobs retain their original reception behavior.
static func reception(c, jobId: String, dest: String, count) -> bool:
	var w: Dictionary = _book(c)
	if w.is_empty() or w.binding.is_empty(): return true
	var b: Dictionary = w.binding
	if b.job.id != jobId: return true
	if w.reported or not w.closure.is_empty() or not V.number(count, 2, 2, true):
		return false
	var j: Dictionary = V.find(c.state, jobId)
	if j.is_empty() or V.identity(j) != b.job: return false
	if dest not in [w.destination, V.RUST]: return false
	return _room(c, dest, jobId) >= 2

## Called only after native _finish has atomically settled and removed the job.
## before.job must be the deep copy taken BEFORE native settlement mutates it.
static func after_closed(c, before: Dictionary, dest: String, loss: bool, earned: int) -> void:
	var w: Dictionary = _book(c)
	if w.is_empty() or w.binding.is_empty() or not w.closure.is_empty(): return
	if not V.shape(before, ["job", "carrierUid"]) or not before.job is Dictionary: return
	if V.identity(before.job) != w.binding.job: return
	if not V.find(c.state, w.binding.job.id).is_empty(): return
	var receipt: Dictionary = {"job":before.job.duplicate(true),
		"carrierUid":before.carrierUid, "destination":dest,
		"loss":loss, "earned":earned, "day":float(c.state.day)}
	if not V.closed(receipt, w.binding, w.destination, float(c.state.day)): return
	w.closure = receipt
	if not loss and dest == w.destination:
		var flags: Array = record(c).flags
		if not flags.has(V.SURVIVED): flags.append(V.SURVIVED)

static func _delivered(c) -> bool:
	var w: Dictionary = _book(c)
	if w.is_empty() or w.binding.is_empty(): return false
	if not V.closed(w.closure, w.binding, w.destination, float(c.state.day)): return false
	return (not w.closure.loss and w.closure.destination == w.destination
		and V.find(c.state, w.binding.job.id).is_empty()
		and record(c).get("flags", []).count(V.SURVIVED) == 1)

static func _report_ready(c) -> Dictionary:
	var permission: Dictionary = _service(c)
	if not permission.get("ok", false): return permission
	var w: Dictionary = _book(c)
	if w.is_empty() or w.reported: return c.fail("This undertaking is not awaiting a report.")
	if not w.binding.is_empty():
		if not V.find(c.state, w.binding.job.id).is_empty():
			return c.fail("The passengers are still travelling or in reception. Complete reception, return or loss settlement before reporting.")
		if not V.closed(w.closure, w.binding, w.destination, float(c.state.day)):
			return c.fail("No completed passage has been recorded. Check the passenger manifest before reporting.")
	return c.ok("Send the passage account. An unfilled passage earns no transport payment.")

static func _choice(value) -> String:
	if value is Dictionary:
		var id = value.get("id")
		return id if id is String else ""
	return value if value is String else ""

static func choice_gate(c, choice) -> Dictionary:
	var id: String = _choice(choice)
	if V.ROUTES.has(id):
		if record(c).get("stage") != V.INTRO or not _book(c).is_empty():
			return c.fail("That destination decision is not available now.")
		return _service(c, V.REED)
	if id == "report_witnesses115":
		return _report_ready(c) if record(c).get("stage") == WORK else c.fail("This chapter is not awaiting that report.")
	if id == "next_distress115":
		return c.ok("") if record(c).get("stage") == V.ACCOUNT and _book(c).get("reported", false) else c.fail("Send the separate witness report first.")
	if id == "finish_wren_witness115":
		var optional = c.state.get("stories", {}).get("chains", {}).get("wren_witness115", {})
		if not optional is Dictionary or optional.get("stage") != "wren_hearing115" or optional.get("done", false):
			return c.fail("Start Wren's separate conversation first.")
		return gate(c, {"mode":"optional"})
	return c.ok("")

static func after_choice(c, choice, result: Dictionary) -> void:
	if not result.get("ok", false): return
	var id: String = _choice(choice)
	if V.ROUTES.has(id) and record(c).get("stage") == WORK:
		var selected: Dictionary = select(c, V.ROUTES[id])
		if not selected.get("ok", false): push_error("115: destination selection did not bind.")
	elif id == "report_witnesses115" and record(c).get("stage") == V.ACCOUNT:
		if not _report_ready(c).get("ok", false): return
		_book(c).reported = true
		_book(c).reportDay = float(c.state.day)

static func gate(c, rule: Dictionary) -> Dictionary:
	if rule.get("mode") == "optional":
		if not _delivered(c): return c.fail("Wren can hear the account after the witnesses complete their reception.")
		return _service(c, V.REED)
	if record(c).get("stage") == V.INTRO: return _service(c, V.REED)
	if record(c).get("stage") == V.ACCOUNT: return choice_gate(c, "next_distress115")
	return c.ok("")
