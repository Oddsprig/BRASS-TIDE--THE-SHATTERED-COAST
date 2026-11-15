# campaign_arc113.gd
extends RefCounted
const Reserves = preload("res://scripts/harbor_reserves.gd")
const Goods = preload("res://scripts/goods.gd")
const ID: String = "common_passage110"
const WORK: String = "materials_work113"
const JOB: String = "material113:anvil_dock:cinder_quay"
const FROM: String = "anvil_dock"
const TO: String = "cinder_quay"
const GOOD: String = "supplies"

static func record(state: Dictionary) -> Dictionary:
	var stories = state.get("stories", {})
	if not stories is Dictionary: return {}
	var chains = stories.get("chains", {})
	if not chains is Dictionary: return {}
	var rec = chains.get(ID, {})
	return rec if rec is Dictionary else {}

static func work(c) -> Dictionary:
	var value = record(c.state).get("work113", {})
	return value.duplicate(true) if value is Dictionary else {}

static func _stage(c) -> String:
	return str(record(c.state).get("stage", ""))

static func _stock(port: Dictionary) -> float:
	var stocks = port.get("stocks", {})
	return float(stocks.get(GOOD, 0.0)) if stocks is Dictionary else -1.0

static func same(w: Dictionary, job: Dictionary) -> bool:
	var freight = job.get("freight", {})
	if not freight is Dictionary: return false
	return (w.get("jobId") == JOB and job.get("id") == JOB
		and job.get("port") == FROM and job.get("targetPort") == TO
		and job.get("kind") == "freight" and job.get("payerKey") == "governmentPurse"
		and freight.get("good") == GOOD and freight.get("qty") == w.get("qty")
		and job.get("reward") == w.get("reward")
		and job.get("materialInvoice", 0) == w.get("materialInvoice")
		and job.get("acceptedDay") == w.get("acceptedDay")
		and job.get("deadlineDay") == w.get("deadlineDay"))

static func offer(c) -> Dictionary:
	var rec: Dictionary = record(c.state)
	if _stage(c) != WORK or rec.is_empty() or rec.has("work113"): return {}
	if not c.VoyageJobs._find(c.state, JOB).is_empty(): return {}
	if c.VoyageJobs._is_closed(c.state, JOB): return {}
	var origin: Dictionary = c.work_port070()
	var target: Dictionary = c.port(TO)
	if origin.get("id") != FROM or target.get("id") != TO: return {}
	if not c.VoyageJobs._work_access(c, origin): return {}
	if not c.VoyageJobs._work_access(c, target, GOOD, origin): return {}
	var route: Dictionary = c.VoyageJobs.WorkRegion070.route(c, target, origin)
	if not route.get("ok",false) or float(route.get("referenceDays", 0)) <= 0: return {}
	var weight: float = float(Goods.ITEMS[GOOD].weight)
	if weight <= 0: return {}
	var room: float = minf(float(c.VoyageJobs._freight_room(c)),
		float(c.VoyageJobs._effective_free(c, c.state)))
	var stock: float = minf(float(Reserves.exportable(origin, GOOD)), _stock(origin))
	var limit: int = mini(8, mini(floori(stock), floori(room / weight)))
	if limit < 1: return {}
	var quote: Dictionary = c.VoyageJobs._funded_load(c, origin,
		float(route.referenceDays), c.VoyageJobs.KIND_FREIGHT, limit, GOOD)
	if quote.is_empty(): return {}
	return {
		"id": JOB, "title": "Reserve repair kits: Anvil Dock to Cinder Quay",
		"description": "Anvil's treasury buys this reserve load of existing drydock kits and funds the delivery fee when you accept. Your fleet pays its own operating costs.",
		"port": FROM, "targetPort": TO, "kind": c.VoyageJobs.KIND_FREIGHT,
		"regionId": c.VoyageJobs.WorkRegion070.region(origin),
		"targetRegionId": c.VoyageJobs.WorkRegion070.region(target),
		"routeDays": float(quote.days), "routeDistance": float(route.get("outwardDistance", 0)),
		"deadlineDay": float(int(c.state.day)) + maxf(20, ceilf(float(quote.days) * 3)),
		"reward": int(quote.reward), "materialInvoice": int(quote.invoice),
		"feeBasis": str(quote.feeBasis), "payerKey": "governmentPurse",
		"escrow": 0, "acceptedDay": 0.0, "state": c.VoyageJobs.STATE_OFFERED,
		"freight": {"good": GOOD, "qty": int(quote.qty)}, "siteId": "", "ownerId": ""}

static func bind(c) -> bool:
	var rec: Dictionary = record(c.state)
	var job: Dictionary = c.VoyageJobs._find(c.state, JOB)
	if rec.has("work113"): return same(work(c), job)
	if rec.is_empty() or job.is_empty() or _stage(c) != WORK: return false
	var freight: Dictionary = job.get("freight", {})
	var w: Dictionary = {
		"jobId": job.get("id"), "origin": job.get("port"),
		"target": job.get("targetPort"), "good": freight.get("good"),
		"qty": int(freight.get("qty", 0)), "reward": int(job.get("reward", 0)),
		"materialInvoice": int(job.get("materialInvoice", 0)),
		"acceptedDay": float(job.get("acceptedDay", 0)),
		"deadlineDay": float(job.get("deadlineDay", 0)),
		"status": "carried", "payment": 0, "deliveredQty": 0,
		"reported": false, "closure": {}}
	if not same(w, job) or w.qty < 1 or w.qty > 8: return false
	if job.get("state") != c.VoyageJobs.STATE_ACTIVE: return false
	rec.work113 = w
	return true

static func accept(c, shown: Dictionary) -> Dictionary:
	var current: Dictionary = offer(c)
	if current.is_empty() or shown != current:
		return c.VoyageJobs._fail(c, "The reserve order changed. Review its current terms.")
	var result: Dictionary = c.accept_voyage_job(JOB)
	if result.get("ok") == true and not bind(c):
		return c.VoyageJobs._fail(c, "Native order accepted, but its chapter binding needs inspection.")
	return result

static func before_job(c, job: Dictionary) -> Dictionary:
	var w: Dictionary = work(c)
	if w.get("status") != "carried" or not same(w, job): return {}
	if c.VoyageJobs._is_closed(c.state, JOB): return {}
	if not same(w, c.VoyageJobs._find(c.state, JOB)): return {}
	var dock: Dictionary = c.work_port070()
	return {"jobId": JOB, "freight": job.freight.duplicate(true),
		"targetBefore": _stock(c.port(TO)), "unloadPort": str(dock.get("id", "")),
		"unloadBefore": _stock(dock)}

static func after_job(c, before: Dictionary, result: Dictionary, abandon: bool) -> void:
	var w: Dictionary = work(c)
	if result.get("ok") != true or w.get("status") != "carried": return
	if not same(w, before) or not c.VoyageJobs._is_closed(c.state, JOB): return
	if not c.VoyageJobs._find(c.state, JOB).is_empty(): return
	var observation = before.get("_delivery113", {})
	if not observation is Dictionary: return
	if observation.get("jobId") != JOB or observation.get("freight") != before.get("freight"): return
	var port_id: String = str(observation.get("unloadPort", "")) if abandon else TO
	var dock: Dictionary = c.work_port070()
	if port_id.is_empty() or dock.get("id") != port_id: return
	var low: float = float(observation.get("unloadBefore", -1)) if abandon else float(observation.get("targetBefore", -1))
	var high: float = _stock(c.port(port_id))
	var lost: bool=bool(before.get("freight",{}).get("lost",false))
	var unloaded: float=0.0 if lost else float(w.qty)
	if not is_finite(low) or not is_finite(high) or low < 0 or high-low+0.000001 < unloaded: return
	if not abandon and lost:return
	if not abandon and result.get("reward") != w.reward: return
	w.status = "withdrawn" if abandon else "delivered"
	w.payment = 0 if abandon else int(w.reward)
	w.deliveredQty = 0 if abandon else int(w.qty)
	w.closure = {"jobId": JOB, "nativeClosed": true,
		"freight": before.freight.duplicate(true), "closedDay": float(c.state.day),
		"unloadPort": port_id, "stockBefore": low, "stockAfter": high, "payment": w.payment}
	record(c.state).work113 = w

static func _reportable(c) -> bool:
	if not c.travel_lock064.is_empty():return false
	var dock: Dictionary = c.work_port070()
	if dock.is_empty(): return false
	var permit = c.Politics.permit(c, "service")
	if permit is Dictionary:
		if permit.get("ok") != true: return false
	elif not (permit is bool) or not permit: return false
	if not c.VoyageJobs._find(c.state, JOB).is_empty(): return false
	var w: Dictionary = work(c)
	if w.is_empty():
		return not record(c.state).has("work113") and not c.VoyageJobs._is_closed(c.state, JOB)
	var closure = w.get("closure", {})
	return (closure is Dictionary and closure.get("nativeClosed") == true
		and w.get("reported") == false and w.get("status") in ["delivered", "withdrawn"])

static func _choice(choice) -> String:
	return str(choice.get("id", "")) if choice is Dictionary else str(choice)

static func choice_gate(c, choice) -> Dictionary:
	if _choice(choice)!="report_materials113":return c.ok("")
	if _stage(c)!=WORK or not _reportable(c):return c.fail("Complete or close the freight order, then report from a harbor.")
	return c.ok("")

static func after_choice(c, choice, result: Dictionary) -> void:
	if not result.get("ok",false):return
	if _choice(choice) != "report_materials113": return
	if _stage(c) not in [WORK, "material_account113"] or not _reportable(c): return
	var w: Dictionary = work(c)
	if w.is_empty():
		w = {"status": "unfilled", "payment": 0, "deliveredQty": 0, "reported": false, "closure": {}}
	w.reported = true
	w.reportPort = str(c.work_port070().id)
	w.reportDay = float(c.state.day)
	record(c.state).work113 = w

static func optional_gate(c) -> Dictionary:
	return c.ok("") if record(c.state).get("flags",[]).has("wren_accounted112") else c.fail("Read Wren's repair-material lead first.")

static func gate(c, source: Dictionary) -> Dictionary:
	return optional_gate(c) if source.get("mode")=="optional" else choice_gate(c,"report_materials113")
