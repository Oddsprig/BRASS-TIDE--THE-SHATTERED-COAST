extends RefCounted
## Story evidence only; native battles, boarding, recovery and sailing retain authority.
const ID = "common_passage110"
const RUST = "rust_anchorage"
const WORK = "route_work114"
const A111 = preload("res://scripts/campaign_arc111.gd")
const V = preload("res://scripts/campaign_validation111.gd")
const OPERATING = ["food", "fuel", "ammo", "supplies"]

static func record(c) -> Dictionary:
	return c.state.get("stories", {}).get("chains", {}).get(ID, {})

static func work(c) -> Dictionary:
	var w = record(c).get("work114", {})
	return w if w is Dictionary else {}

static func _new(c, owner: String = "", uids: Array = []) -> Dictionary:
	return {"origin":RUST, "ownerId":owner, "targetUids":uids.duplicate(), "boundDay":float(c.state.day),
		"battleFloor":int(c.state.get("battleSeq", 0)), "encounters":[], "wrecks":[], "captures":[],
		"recoveries":[], "release":{}, "arrival":{}, "reported":false, "resolution":"", "debrief":{}}

static func _stopped(c) -> bool:
	return c.travel_lock064.is_empty() and c.state.get("path", []).is_empty() and not c.current_port().is_empty()

static func _rust(c) -> bool:
	return _stopped(c) and c.current_port().get("id") == RUST

static func _open(c) -> bool:
	return record(c).get("stage") == WORK and not work(c).is_empty() and not work(c).reported and work(c).release.is_empty()

static func _uids(owner: Dictionary) -> Array:
	var out: Array = []
	for boat in owner.get("boats", []):
		if boat.get("sunk", false) or boat.get("captureSecured", false): continue
		var uid = boat.get("uid")
		if not V.text(uid, 120) or out.has(uid): return []
		out.append(uid)
	out.sort()
	return out if out.size() <= 48 else []

static func targets(c) -> Array:
	var out: Array = []
	if record(c).get("stage") != WORK or not _rust(c): return out
	for sight in c.NavalAI.sightings(c.state):
		if not sight.get("current", false) or sight.get("expired", true): continue
		if c.distance(sight, c.current_port()) > c.NavalAI.INTERCEPT_RADIUS: continue
		var patrol: Dictionary=c.NavalAI._find_patrol(c.state,str(sight.get("ownerId","")))
		if patrol.is_empty() or not patrol.get("active",false) or c.distance(c.state.position,patrol)>600.0 or c.distance(patrol,c.current_port())>600.0:continue
		var owner: Dictionary = c.fleet_owner(str(sight.get("ownerId", "")))
		if owner.get("kind") != "raider" or owner.get("homePort") != RUST or not owner.get("active", false): continue
		if not c.Politics.hostile(c, owner) or _uids(owner).is_empty(): continue
		if not out.any(func(row): return row.ownerId == owner.id):
			out.append({"ownerId":str(owner.id), "name":str(owner.name), "boats":_uids(owner).size()})
	out.sort_custom(func(a, b): return a.ownerId < b.ownerId)
	return out

static func bind(c, owner_id: String) -> Dictionary:
	if not work(c).is_empty(): return c.fail("This undertaking already identifies one original fleet.")
	if not record(c).get("flags", []).has("cass_admission114"): return c.fail("Hear Cass's admission before binding an original fleet.")
	if not targets(c).any(func(row): return row.ownerId == owner_id): return c.fail("Identify a currently sighted Rust raider here first.")
	var owner: Dictionary = c.fleet_owner(owner_id)
	record(c).work114 = _new(c, owner_id, _uids(owner))
	return c.ok("Identified %s and %d original boats."%[str(owner.name),_uids(owner).size()])

static func release_quote(c) -> Dictionary:
	if not _open(c): return c.fail("Bind one fleet before requesting its once-only cargo release.")
	var w: Dictionary = work(c)
	if not targets(c).any(func(row): return row.ownerId == w.ownerId): return c.fail("The identified seller must be currently sighted near Rust Anchorage.")
	var owner: Dictionary = c.fleet_owner(str(w.ownerId))
	if not _uids(owner).any(func(uid): return w.targetUids.has(uid)): return c.fail("The identified original hulls are no longer with this seller.")
	var p: Dictionary = c.current_port()
	var permission: Dictionary = c.Politics.permit(c, "service")
	if not permission.get("ok", false): return permission
	var goods: Array = owner.get("cargo", {}).keys()
	goods.sort()
	var why: String = "No releasable cargo is available. The original-hull raid remains an alternative."
	for good in goods:
		if not c.Goods.ITEMS.has(good): continue
		var aboard = owner.cargo[good]
		var proof = owner.get("capturedOperating", {}).get(good, 0) if good in OPERATING else 0
		if not V.number(aboard) or not V.number(proof) or float(proof) > float(aboard): continue
		var available: float = float(proof) if good in OPERATING else float(aboard)
		if available < 1.0: continue
		permission = c.Politics.permit(c, "buy_good", str(good))
		if not permission.get("ok", false): why = str(permission.get("message", "This commodity is restricted.")); continue
		if not c.LawOps.allow_player(c, p, str(good)) or not c.Fleets.allowed_trade(owner, p, str(good), c):
			why = "Existing carrier trade restrictions forbid this release."; continue
		var price: int = c.Economy.price(p, str(good), "buy")
		if price <= 0 or not V.number(owner.get("coins"), 0, 1000000000, true) or not V.number(c.state.get("coins"), 0, 1000000000, true): continue
		var room: int = floori(maxf(0, c.capacity() - c.cargo_weight()) / float(c.Goods.ITEMS[good].weight))
		var qty: int = mini(4, mini(floori(available), mini(room, floori(float(c.state.coins) / price))))
		if qty < 1: why = "Real hold space and coins are required for at least one available unit."; continue
		var held = c.state.cargo.get(good, 0)
		if not V.number(held) or not V.number(float(held) + qty) or not V.number(price, 1, 1000000000, true): continue
		if not V.number(qty * price, 1, 1000000000, true) or not V.number(int(owner.coins) + qty * price, 0, 1000000000, true): continue
		return {"ok":true, "message":"%d %s for %d coins, paid to %s." % [qty, c.Goods.ITEMS[good].name, qty * price, owner.name],
			"ownerId":str(w.ownerId), "good":str(good), "qty":qty, "unitPrice":price, "cost":qty * price,
			"ownerBefore":float(aboard), "cargoBefore":float(held), "capturedBefore":float(proof),
			"sellerBefore":int(owner.coins), "buyerBefore":int(c.state.coins), "day":float(c.state.day)}
	return c.fail(why)

static func release(c, shown: Dictionary) -> Dictionary:
	var q: Dictionary = release_quote(c)
	if not q.get("ok", false): return q
	for key in ["ownerId", "good", "qty", "unitPrice", "cost"]:
		if shown.get(key) != q[key]: return c.fail("The available lot or quoted terms changed. Review the fresh quotation.")
	var owner: Dictionary = c.fleet_owner(str(q.ownerId))
	if not c.Money.move(c.state, "coins", owner, "coins", int(q.cost), "Cass: paid release of actual fleet cargo", c.state.moneyLog):
		return c.fail("The actual seller could not be paid; no goods moved.")
	owner.cargo[q.good] = float(q.ownerBefore) - int(q.qty)
	if owner.get("tradeGood") == q.good: owner.tradeCargo = maxf(0, float(owner.get("tradeCargo", 0)) - int(q.qty))
	c.Fleets.retire_captured_operating(owner, str(q.good), float(q.qty))
	c.Fleets.keep_captured_operating(owner)
	c.state.cargo[q.good] = float(q.cargoBefore) + int(q.qty)
	c.LawOps.reconcile(c)
	c.Manifest.allocate(c.state)
	q.ownerAfter = float(owner.cargo[q.good]); q.cargoAfter = float(c.state.cargo[q.good])
	q.capturedAfter = float(owner.get("capturedOperating", {}).get(q.good, 0))
	q.sellerAfter = int(owner.coins); q.buyerAfter = int(c.state.coins)
	work(c).release = q.duplicate(true)
	return c.ok("Bought %d %s from %s for %d coins."%[int(q.qty),str(c.Goods.ITEMS[q.good].name),str(owner.name),int(q.cost)])

static func capture_snapshot(c, context: Dictionary, battle: Dictionary) -> Array:
	var out: Array = []
	if not _open(c) or context.get("ownerId") != work(c).ownerId: return out
	for boat in battle.get("captured", []):
		if work(c).targetUids.has(str(boat.get("uid", ""))): out.append({"originalUid":str(boat.uid), "boat":boat})
	return out

static func after_battle(c, result: String, context: Dictionary, battle: Dictionary, report: Dictionary, captured: Array) -> void:
	if not _open(c) or context.get("ownerId") != work(c).ownerId: return
	if battle.get("result") != result or float(battle.get("time", 0)) <= 0 or report.get("participants", []).is_empty(): return
	if battle.get("_battleMirror051", false) and not battle.get("simulation051", {}).get("retired", false): return
	var w: Dictionary = work(c)
	var sequence = battle.get("campaignSequence111")
	var source = battle.get("engagementSource060")
	var pos = context.get("position114")
	if not V.number(sequence, float(w.battleFloor) + 1, float(c.state.get("battleSeq", 0)), true) or not V.text(source): return
	if not pos is Dictionary or not V.number(pos.get("x"), -1000000000) or not V.number(pos.get("y"), -1000000000): return
	if not V.number(context.get("day114"), float(w.boundDay), float(c.state.day)): return
	if w.encounters.size() >= 48 or w.encounters.any(func(row): return row.source == source or row.sequence == sequence): return
	w.encounters.append({"source":source, "sequence":int(sequence), "day":float(context.day114), "position":{"x":float(pos.x), "y":float(pos.y)}})
	var parts: int = 0
	for known in w.wrecks: parts += known.itemUids.size()
	for wreck in report.get("wrecks", []):
		if not w.targetUids.has(str(wreck.get("uid", ""))) or wreck.get("sourceId") != source or wreck.get("friendly", false) or wreck.get("team") != "enemy": continue
		if w.wrecks.any(func(row): return row.uid == wreck.uid) or w.captures.any(func(row): return row.originalUid == wreck.uid): continue
		var raw: Dictionary = A111.raw_wreck(c, str(wreck.id))
		if raw.get("uid") != wreck.uid or raw.get("sourceId") != source: continue
		var items: Array = raw.get("sourceModuleCondition", {}).get("items", {}).keys()
		if parts + items.size() > 512: continue
		parts += items.size()
		w.wrecks.append({"id":str(wreck.id), "uid":str(wreck.uid), "source":source, "sequence":int(sequence), "day":float(c.state.day), "itemUids":items})
	for row in captured:
		var boat: Dictionary = row.boat
		if not w.targetUids.has(row.originalUid) or boat.get("sunk", false): continue
		if not (c.state.fleet + c.state.get("boardingPrizes", [])).any(func(owned): return is_same(owned, boat)): continue
		if w.captures.any(func(old): return old.originalUid == row.originalUid) or w.wrecks.any(func(old): return old.uid == row.originalUid): continue
		w.captures.append({"originalUid":row.originalUid, "boatUid":str(boat.uid), "kind":"captured", "source":source, "sequence":int(sequence), "day":float(c.state.day)})

static func after_recovery(c, id: String, result: Dictionary) -> void:
	if not _open(c) or not result.get("ok", false): return
	var w: Dictionary = work(c) # Reacquire after detached native publication.
	if w.recoveries.any(func(row): return row.wreckId == id): return
	for known in w.wrecks:
		if known.id != id: continue
		var raw: Dictionary = A111.raw_wreck(c, id)
		if raw.get("uid") != known.uid or raw.get("sourceId") != known.source or not raw.get("hullStripped", false): return
		if raw.get("claimedMode") != "gear" or raw.get("equipmentCustody") != "retired" or raw.has("sourceModuleCondition"): return
		var ids: Array = []
		for part in result.get("selected", []): ids.append(part.get("itemUid"))
		if not V.ids(ids, 512) or not ids.all(func(uid): return known.itemUids.has(uid)): return
		if not V.text(result.get("carrierUid"), 120) or not V.number(result.get("wagesPaid"), 1, 1000000000, true) or not V.number(result.get("foodConsumed")): return
		w.recoveries.append({"wreckId":id, "source":known.source, "sequence":known.sequence, "day":float(c.state.day), "itemUids":ids,
			"carrierUid":str(result.get("carrierUid", "")), "wagesPaid":int(result.wagesPaid), "foodConsumed":float(result.foodConsumed)})
		return

static func after_tow(c, id: String, result: Dictionary) -> void:
	if not _open(c) or not result.get("ok", false): return
	var w: Dictionary = work(c)
	var raw: Dictionary = A111.raw_wreck(c, id)
	if raw.get("status") != "towed": return
	for known in w.wrecks:
		if known.id != id or raw.get("uid") != known.uid or raw.get("sourceId") != known.source: continue
		var uid: String = str(raw.get("towedBoatUid", ""))
		if c.find_boat(uid).is_empty() or c.find_boat(uid).get("sunk", false) or w.captures.any(func(row): return row.originalUid == known.uid): return
		w.captures.append({"originalUid":known.uid, "boatUid":uid, "kind":"towed", "source":known.source, "sequence":known.sequence, "day":float(c.state.day)})
		return

static func _custody(c, remote: bool = false, expected: Dictionary = {}) -> Dictionary:
	var w: Dictionary = work(c)
	for boat in A111.local_custody(c, remote):
		var proofs: Array = []
		for row in w.get("captures", []):
			if row.boatUid == boat.get("uid"): proofs.append({"kind":"hull", "uid":row.boatUid, "source":row.source, "day":row.day})
		for row in w.get("recoveries", []):
			for uid in row.itemUids:
				if boat.get("moduleCondition", {}).get("items", {}).has(uid): proofs.append({"kind":"fitting", "uid":uid, "source":row.source, "day":row.day})
		for proof in proofs:
			if expected.is_empty() or (proof.kind == expected.get("kind") and proof.uid == expected.get("uid") and proof.source == expected.get("source")): return proof
	return {}

## Root calls ONLY from the native completed harbor-route branch, after positive sailing displacement.
static func arrived(c, port: Dictionary) -> void:
	if not _open(c) or not _stopped(c) or port.get("id") == RUST or c.current_port().get("id") != port.get("id"): return
	if not c.Politics.permit(c, "service").get("ok", false): return
	var proof: Dictionary = _custody(c)
	if proof.is_empty(): return
	for event in work(c).encounters:
		if event.source != proof.source or c.distance(event.position, port) <= 65.0: continue
		work(c).arrival = {"port":str(port.id), "day":float(c.state.day), "kind":proof.kind, "uid":proof.uid,
			"source":proof.source, "nativeArrival":true, "lawful":true}
		return

static func _report_ready(c, choice: String) -> Dictionary:
	if not _stopped(c) or work(c).get("reported", false): return c.fail("Stop at an actual harbor before making this separate report.")
	var w: Dictionary = work(c)
	if choice == "report_unrecovered114":
		if not w.get("release", {}).is_empty() or not _custody(c, true).is_empty(): return c.fail("Original property or a paid release is recorded; report that actual outcome.")
		return c.ok("Close this attempt without recovery or a reward. Unconfirmed property remains unconfirmed.")
	var permission: Dictionary = c.Politics.permit(c, "service")
	if not permission.get("ok", false): return permission
	if not w.get("release", {}).is_empty(): return c.ok("Paid release completed: %d %s for %d coins. Send Cass the account."%[int(w.release.qty),str(c.Goods.ITEMS[w.release.good].name),int(w.release.cost)])
	var arrival: Dictionary = w.get("arrival", {})
	if arrival.is_empty() or arrival.get("port") != c.current_port().get("id") or _custody(c, false, arrival).is_empty():
		return c.fail("Bring an original captured hull or recovered fitting into another lawful harbor, then send Cass the report there.")
	return c.ok("Original property has arrived at %s. You can send Cass the report."%str(c.current_port().name))

static func _choice(value) -> String:
	return str(value.get("id", "")) if value is Dictionary else str(value)

static func choice_gate(c, choice) -> Dictionary:
	var id: String = _choice(choice)
	if id == "investigate_route114":
		return c.ok("") if record(c).get("stage") == "bought_route114" and _rust(c) else c.fail("Meet Cass at Rust Anchorage.")
	if id == "next_witnesses114":
		return c.ok("") if record(c).get("stage") == "route_account114" and work(c).get("reported", false) else c.fail("Make the separate route report first.")
	if id not in ["report_property114", "report_unrecovered114"]: return c.ok("")
	return _report_ready(c, id) if record(c).get("stage") == WORK else c.fail("This chapter is not awaiting that report.")

static func after_choice(c, choice, result: Dictionary) -> void:
	if not result.get("ok", false): return
	var id: String = _choice(choice)
	if id == "investigate_route114":
		if record(c).get("stage") in ["bought_route114", WORK] and _rust(c) and not record(c).flags.has("cass_admission114"):
			record(c).flags.append("cass_admission114")
		return
	if id not in ["report_property114", "report_unrecovered114"] or record(c).get("stage") not in [WORK, "route_account114"]: return
	if not _report_ready(c, id).get("ok", false): return
	var w: Dictionary = work(c)
	if w.is_empty(): w = _new(c)
	w.reported = true
	w.resolution = "unrecovered" if id == "report_unrecovered114" else ("released" if not w.release.is_empty() else "raid")
	w.debrief = {"port":str(c.current_port().id), "day":float(c.state.day), "lawful":bool(c.Politics.permit(c, "service").get("ok", false))}
	record(c).work114 = w

static func gate(c, rule: Dictionary) -> Dictionary:
	if rule.get("mode") == "optional":
		return c.ok("") if record(c).get("flags", []).has("cass_admission114") else c.fail("Hear Cass's admission first.")
	if record(c).get("stage") == "bought_route114": return choice_gate(c, "investigate_route114")
	if record(c).get("stage") == "route_account114": return choice_gate(c, "next_witnesses114")
	return c.ok("")
