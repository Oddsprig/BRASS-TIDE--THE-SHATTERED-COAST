extends RefCounted
## Run after native/world/story structural validation and before restore publication.
## Receipts are history, never extra inventory, a bounty, or a replacement native owner.
const A = preload("res://scripts/campaign_arc114.gd")
const V = preload("res://scripts/campaign_validation111.gd")
const Goods = preload("res://scripts/goods.gd")

static func _shape(d, fields: Array) -> bool:
	if not d is Dictionary or d.size() != fields.size(): return false
	for field in fields:
		if not d.has(field): return false
	return true

static func _ids(value, limit: int = 512, empty: bool = false) -> bool:
	return value is Array and ((empty and value.is_empty()) or V.ids(value, limit))

static func _yes(value) -> bool:
	return value is bool and value

static func _port(state: Dictionary, id) -> Dictionary:
	if not V.text(id, 120): return {}
	for p in state.get("ports", []):
		if p is Dictionary and p.get("id") == id: return p
	return {}

static func _event(row: Dictionary, events: Dictionary, now: float) -> bool:
	if not V.text(row.get("source")) or not events.has(row.source): return false
	var event: Dictionary = events[row.source]
	return V.number(row.get("sequence"), 0, 1000000000, true) and row.sequence == event.sequence and V.number(row.get("day"), float(event.day), now)

static func _property(receipt: Dictionary, w: Dictionary) -> bool:
	if receipt.kind == "hull":
		return w.captures.any(func(row): return row.boatUid == receipt.uid and row.source == receipt.source and float(receipt.day) >= float(row.day))
	if receipt.kind == "fitting":
		return w.recoveries.any(func(row): return row.itemUids.has(receipt.uid) and row.source == receipt.source and float(receipt.day) >= float(row.day))
	return false

static func _arrival(state: Dictionary, w: Dictionary, events: Dictionary) -> bool:
	var r: Dictionary = w.arrival
	if not _shape(r, ["port", "day", "kind", "uid", "source", "nativeArrival", "lawful"]): return false
	if not _yes(r.nativeArrival) or not _yes(r.lawful) or not V.text(r.uid, 120) or not V.text(r.source) or not events.has(r.source): return false
	if not V.number(r.day, float(w.boundDay), float(state.day)) or not _property(r, w): return false
	var p: Dictionary = _port(state, r.port)
	if p.is_empty() or r.port == A.RUST or not V.number(p.get("x"), -1000000000) or not V.number(p.get("y"), -1000000000): return false
	var pos: Dictionary = events[r.source].position
	return Vector2(float(pos.x), float(pos.y)).distance_to(Vector2(float(p.x), float(p.y))) > 65.0

static func _release(q: Dictionary, w: Dictionary, now: float) -> bool:
	if not _shape(q, ["ok", "message", "ownerId", "good", "qty", "unitPrice", "cost", "ownerBefore", "cargoBefore", "capturedBefore", "sellerBefore", "buyerBefore", "day", "ownerAfter", "cargoAfter", "capturedAfter", "sellerAfter", "buyerAfter"]): return false
	if not _yes(q.ok) or not V.text(q.message, 600) or q.ownerId != w.ownerId or not q.good is String or not Goods.ITEMS.has(q.good): return false
	if not V.number(q.qty, 1, 4, true) or not V.number(q.unitPrice, 1, 1000000000, true) or not V.number(q.cost, 1, 1000000000, true): return false
	if q.cost != q.qty * q.unitPrice or not V.number(q.day, float(w.boundDay), now): return false
	for key in ["ownerBefore", "cargoBefore", "capturedBefore", "ownerAfter", "cargoAfter", "capturedAfter"]:
		if not V.number(q[key]): return false
	for key in ["sellerBefore", "buyerBefore", "sellerAfter", "buyerAfter"]:
		if not V.number(q[key], 0, 1000000000, true): return false
	if q.ownerBefore < q.qty or q.buyerBefore < q.cost or q.capturedBefore > q.ownerBefore: return false
	if absf(float(q.ownerBefore) - float(q.qty) - float(q.ownerAfter)) > 0.000001: return false
	if absf(float(q.cargoBefore) + float(q.qty) - float(q.cargoAfter)) > 0.000001: return false
	if q.sellerAfter != q.sellerBefore + q.cost or q.buyerAfter != q.buyerBefore - q.cost: return false
	if q.good in A.OPERATING:
		if q.capturedBefore < q.qty or absf(float(q.capturedBefore) - float(q.qty) - float(q.capturedAfter)) > 0.000001: return false
	elif q.capturedBefore != 0 or q.capturedAfter != 0: return false
	return true

static func validate(state: Dictionary) -> String:
	var stories = state.get("stories", {})
	if not stories is Dictionary or not stories.get("chains", {}) is Dictionary: return "114: validate native story structure first."
	var rec = stories.get("chains", {}).get(A.ID, {})
	if not rec is Dictionary: return "114: invalid chapter record."
	var required: bool = rec.get("stage") in ["route_account114", "names_on_paper115"]
	if not rec.has("work114"): return "114: missing explicit route report." if required else ""
	var w = rec.work114
	if not _shape(w, ["origin", "ownerId", "targetUids", "boundDay", "battleFloor", "encounters", "wrecks", "captures", "recoveries", "release", "arrival", "reported", "resolution", "debrief"]): return "114: invalid bounded work record."
	if not V.number(state.get("day")) or not V.number(state.get("battleSeq", 0), 0, 1000000000, true): return "114: invalid native clock."
	var now: float = float(state.day)
	if w.origin != A.RUST or not V.number(w.boundDay, 0, now) or not V.number(w.battleFloor, 0, float(state.get("battleSeq", 0)), true): return "114: invalid original binding."
	if not rec.get("flags", []) is Array or not rec.get("flags", []).has("cass_admission114"): return "114: missing Cass admission."
	if not w.reported is bool or w.resolution not in ["", "raid", "released", "unrecovered"] or w.reported != (w.resolution != ""): return "114: invalid explicit resolution."
	if rec.get("stage") == "bought_route114" or (required and not w.reported) or (rec.get("stage") == A.WORK and w.reported): return "114: chapter/report mismatch."
	for key in ["encounters", "wrecks", "captures", "recoveries"]:
		if not w[key] is Array or w[key].size() > 48: return "114: evidence bound exceeded."
	for key in ["release", "arrival", "debrief"]:
		if not w[key] is Dictionary: return "114: invalid receipt type."
	if not w.ownerId is String or not _ids(w.targetUids, 48, w.ownerId.is_empty()): return "114: invalid original target identities."
	if w.reported:
		if not _shape(w.debrief, ["port", "day", "lawful"]) or not w.debrief.lawful is bool: return "114: invalid debrief."
		if _port(state, w.debrief.port).is_empty() or not V.number(w.debrief.day, float(w.boundDay), now): return "114: invalid debrief harbor/day."
	elif not w.debrief.is_empty(): return "114: unreported undertaking contains a debrief."
	if w.ownerId.is_empty():
		if not w.reported or w.resolution != "unrecovered" or not w.targetUids.is_empty(): return "114: unknown source claims property."
		for key in ["encounters", "wrecks", "captures", "recoveries", "release", "arrival"]:
			if not w[key].is_empty(): return "114: unknown source contains invented evidence."
		return ""
	if not V.text(w.ownerId, 120): return "114: invalid original owner."
	var source_owner: Dictionary={}
	for owner in state.get("fleetOwners", []):
		if owner is Dictionary and owner.get("id")==w.ownerId:source_owner=owner;break
	if source_owner.is_empty() or source_owner.get("kind")!="raider" or source_owner.get("homePort")!=A.RUST:return "114: owner is not the original Rust raider source."
	var events: Dictionary = {}
	var sequences: Dictionary = {}
	for row in w.encounters:
		if not _shape(row, ["source", "sequence", "day", "position"]) or not V.text(row.source) or events.has(row.source): return "114: invalid encounter identity."
		if not V.number(row.sequence, float(w.battleFloor) + 1, float(state.get("battleSeq", 0)), true) or sequences.has(row.sequence) or not V.number(row.day, float(w.boundDay), now): return "114: stale encounter."
		if not _shape(row.position, ["x", "y"]) or not V.number(row.position.x, -1000000000) or not V.number(row.position.y, -1000000000): return "114: invalid original encounter position."
		events[row.source] = row; sequences[row.sequence] = true
	var wrecks: Dictionary = {}
	var originals: Dictionary = {}
	var source_parts: Dictionary = {}
	for row in w.wrecks:
		if not _shape(row, ["id", "uid", "source", "sequence", "day", "itemUids"]) or not _event(row, events, now): return "114: invalid native wreck source."
		if not V.text(row.id) or not V.text(row.uid, 120) or not w.targetUids.has(row.uid) or wrecks.has(row.id) or originals.has(row.uid) or not _ids(row.itemUids, 512, true): return "114: invalid original wreck/parts."
		wrecks[row.id] = row; originals[row.uid] = row
		for uid in row.itemUids:
			if source_parts.has(uid): return "114: original fitting occurs in two sources."
			source_parts[uid] = true
		if source_parts.size() > 512: return "114: original fitting bound exceeded."
	var secured: Dictionary = {}
	var hulls: Dictionary = {}
	for row in w.captures:
		if not _shape(row, ["originalUid", "boatUid", "kind", "source", "sequence", "day"]) or not _event(row, events, now): return "114: invalid secured-hull source."
		if not V.text(row.originalUid, 120) or not V.text(row.boatUid, 120) or not w.targetUids.has(row.originalUid) or secured.has(row.originalUid) or hulls.has(row.boatUid): return "114: invalid original secured hull."
		if row.kind == "captured":
			if originals.has(row.originalUid): return "114: captured hull also has a wreck."
		elif row.kind == "towed":
			var original: Dictionary = originals.get(row.originalUid, {})
			if original.is_empty() or original.source != row.source or original.sequence != row.sequence or float(row.day) < float(original.day): return "114: tow lacks its original wreck."
		else: return "114: invalid secured-hull kind."
		secured[row.originalUid] = row; hulls[row.boatUid] = true
	var recovered: Dictionary = {}
	var retained: Dictionary = {}
	for row in w.recoveries:
		if not _shape(row, ["wreckId", "source", "sequence", "day", "itemUids", "carrierUid", "wagesPaid", "foodConsumed"]) or not _event(row, events, now): return "114: invalid paid-recovery source."
		if not V.text(row.wreckId) or not wrecks.has(row.wreckId) or recovered.has(row.wreckId) or not V.text(row.carrierUid, 120) or not _ids(row.itemUids): return "114: invalid paid-recovery identity."
		var original: Dictionary = wrecks[row.wreckId]
		if row.source != original.source or row.sequence != original.sequence or float(row.day) < float(original.day) or secured.has(original.uid): return "114: recovery disagrees with its original wreck."
		if not V.number(row.wagesPaid, 1, 1000000000, true) or not V.number(row.foodConsumed): return "114: invalid actual paid work."
		for uid in row.itemUids:
			if not original.itemUids.has(uid) or retained.has(uid): return "114: fitting is not an original recovered instance."
			retained[uid] = true
		recovered[row.wreckId] = true
	if not w.release.is_empty() and not _release(w.release, w, now): return "114: nonconserving cargo/coin release."
	if not w.arrival.is_empty() and not _arrival(state, w, events): return "114: invalid native withdrawal arrival."
	if not w.reported: return ""
	if w.resolution == "raid":
		if not w.release.is_empty() or w.arrival.is_empty() or not w.debrief.lawful or w.debrief.port != w.arrival.port or float(w.debrief.day) < float(w.arrival.day): return "114: raid report lacks native arrival and debrief."
	elif w.resolution == "released":
		if w.release.is_empty() or not w.debrief.lawful or float(w.debrief.day) < float(w.release.day): return "114: paid-release report lacks actual transfer."
	elif not w.release.is_empty(): return "114: unrecovered report conceals an actual paid release."
	return ""
