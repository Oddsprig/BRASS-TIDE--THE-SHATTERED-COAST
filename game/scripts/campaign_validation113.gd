# campaign_validation113.gd
extends RefCounted
const Arc = preload("res://scripts/campaign_arc113.gd")
const V111 = preload("res://scripts/campaign_validation111.gd")

static func validate(state: Dictionary) -> String:
	var closed=state.get("doneVoyageJobs",[])
	if not closed is Array:return "113: invalid native closed-job book."
	var native_closed: bool=closed.has(Arc.JOB)
	var rec: Dictionary = Arc.record(state)
	var jobs = state.get("voyageJobs", [])
	if not jobs is Array: return "113: validate native voyage jobs first."
	var native: Dictionary = {}
	for item in jobs:
		if not item is Dictionary: return "113: invalid native job."
		if item.get("id") == Arc.JOB:
			if not native.is_empty(): return "113: duplicate reserve order."
			native = item
	var stage: String = str(rec.get("stage", ""))
	var required: bool = stage in ["material_account113", "bought_route114"]
	if not rec.has("work113"):
		return "113: missing reserve-order account." if required or native_closed or not native.is_empty() else ""
	var w = rec.work113
	if not w is Dictionary or w.is_empty() or w.size() > 16: return "113: invalid work record."
	if not (w.get("reported") is bool): return "113: invalid report flag."
	if not V111.number(w.get("payment"), 0, 1000000000, true): return "113: invalid payment."
	if not V111.number(w.get("deliveredQty"), 0, 8, true): return "113: invalid delivered quantity."
	if w.get("status") not in ["carried", "delivered", "withdrawn", "unfilled"]: return "113: invalid status."
	if not (w.get("closure") is Dictionary): return "113: invalid closure."
	if required and not w.reported: return "113: explicit material report required."
	if w.reported:
		if w.status == "carried" or stage == Arc.WORK: return "113: report/stage mismatch."
		if not V111.text(w.get("reportPort"), 120): return "113: missing report harbor."
		if not V111.number(w.get("reportDay")): return "113: invalid report day."
		if float(w.reportDay) > float(state.day): return "113: future report."
	elif w.has("reportPort") or w.has("reportDay"):
		return "113: unreported work contains a report."
	if w.status == "unfilled":
		if w.size() != 7 or not w.reported or native_closed or not native.is_empty():
			return "113: unfilled account conflicts with native work."
		if not w.closure.is_empty() or w.payment != 0 or w.deliveredQty != 0:
			return "113: unfilled account claims settlement."
		for key in w:
			if key not in ["status", "payment", "deliveredQty", "reported", "closure", "reportPort", "reportDay"]:
				return "113: unfilled account contains accepted terms."
		return ""
	if w.size() != (16 if w.reported else 14): return "113: unexpected accepted-work fields."
	for pair in [["jobId", Arc.JOB], ["origin", Arc.FROM], ["target", Arc.TO], ["good", Arc.GOOD]]:
		if w.get(pair[0]) != pair[1]: return "113: changed order identity."
	if not V111.number(w.get("qty"), 1, 8, true): return "113: invalid accepted quantity."
	if not V111.number(w.get("reward"), 1, 1000000000, true): return "113: invalid native fee."
	if not V111.number(w.get("materialInvoice"), 0, 1000000000, true): return "113: invalid invoice."
	if not V111.number(w.get("acceptedDay")): return "113: invalid acceptance day."
	if not V111.number(w.get("deadlineDay"), float(w.acceptedDay)): return "113: invalid deadline."
	if float(w.acceptedDay) > float(state.day): return "113: future acceptance."
	if w.status == "carried":
		if native_closed or not Arc.same(w, native): return "113: carried native order mismatch."
		if not w.closure.is_empty() or w.payment != 0 or w.deliveredQty != 0 or w.reported:
			return "113: carried order claims settlement."
		return ""
	if not native.is_empty(): return "113: closed account still carries native freight."
	var closure: Dictionary = w.closure
	if closure.size() != 8 or closure.get("jobId") != Arc.JOB: return "113: invalid historical closure."
	if not (closure.get("nativeClosed") is bool) or closure.nativeClosed != true:
		return "113: missing native closure evidence."
	var freight = closure.get("freight")
	if not freight is Dictionary or freight.get("good") != Arc.GOOD or freight.get("qty") != w.qty:
		return "113: original freight mismatch."
	if not V111.text(closure.get("unloadPort"), 120): return "113: invalid unloading harbor."
	if not V111.number(closure.get("closedDay"), float(w.acceptedDay)): return "113: invalid closure day."
	if float(closure.closedDay) > float(state.day): return "113: future closure."
	if not V111.number(closure.get("stockBefore")) or not V111.number(closure.get("stockAfter")):
		return "113: invalid native stock observations."
	var lost: bool=bool(freight.get("lost",false))
	var unloaded: float=0.0 if lost else float(w.qty)
	if float(closure.stockAfter)-float(closure.stockBefore)+0.000001 < unloaded:
		return "113: missing original-lot unloading evidence."
	if closure.get("payment") != w.payment: return "113: closure payment mismatch."
	if w.status == "delivered":
		if lost or closure.unloadPort != Arc.TO or w.payment != w.reward or w.deliveredQty != w.qty:
			return "113: incomplete delivery or native payment."
	elif w.payment != 0 or w.deliveredQty != 0:
		return "113: withdrawn order claims payment or delivery."
	if w.reported and float(w.reportDay) < float(closure.closedDay): return "113: report predates settlement."
	return ""
