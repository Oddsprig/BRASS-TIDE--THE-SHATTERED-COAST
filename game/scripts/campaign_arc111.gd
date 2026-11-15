extends RefCounted
## Second Signature: original bounty, physical property and honest loss.
## Native jobs/battles/recovery own every financial and physical mutation.
const ID: String="common_passage110"
const STAGE: String="second_signature111"
const OPTIONAL: String="tobin_clause111"

static func record(c) -> Dictionary:
	return c.state.get("stories",{}).get("chains",{}).get(ID,{})

static func work(c) -> Dictionary:
	return record(c).get("work111",{})

static func found(message: String,resolution: String) -> Dictionary:
	return {"ok":true,"message":message,"resolution":resolution}

static func offers(c) -> Array:
	var out: Array=[]
	if str(record(c).get("stage",""))!=STAGE or not work(c).is_empty():return out
	if str(c.current_port().get("id",""))!="brass_haven":return out
	for offer in c.VoyageJobs.available(c):
		if str(offer.get("kind",""))!="bounty":continue
		var owner: Dictionary=c.fleet_owner(str(offer.get("ownerId","")))
		if not owner.is_empty() and c.Politics.hostile(c,owner):out.append(offer.duplicate(true))
	return out

static func accept(c,terms: Dictionary) -> Dictionary:
	if str(record(c).get("stage",""))!=STAGE or not work(c).is_empty():return c.fail("This investigation already has a target, or is not at this chapter.")
	var shown: Dictionary={}
	for offer in offers(c):
		if str(offer.id)==str(terms.get("id","")) and str(offer.ownerId)==str(terms.get("ownerId","")) and int(offer.reward)==int(terms.get("reward",-1)):shown=offer;break
	if shown.is_empty():return c.fail("The funded target or terms changed. Review the harbor's current bounty again.")
	var owner: Dictionary=c.fleet_owner(str(shown.ownerId))
	var originals: Array=[]
	for boat in owner.get("boats",[]):
		if not boat.get("sunk",false):originals.append(str(boat.uid))
	if originals.is_empty() or originals.size()>48:return c.fail("There are no bounded original target hulls to identify.")
	var result: Dictionary=c.VoyageJobs.accept(c,str(shown.id))
	if not result.get("ok",false):return result
	var job: Dictionary=c.VoyageJobs._find(c.state,str(shown.id))
	if job.is_empty():return c.fail("The contract was accepted but its investigation binding is unavailable. Review carried jobs; no story progress was awarded.")
	record(c).work111={"jobId":str(job.id),"ownerId":str(job.ownerId),"port":str(job.port),"targetUids":originals,"acceptedDay":float(job.acceptedDay),"battleFloor":int(c.state.get("battleSeq",0)),"baselineDefeats":int(job.baselineDefeats),"reward":int(job.reward),"status":"carried","payment":0,"closure":{},"wrecks":[],"captures":[],"recoveries":[],"reported":false,"resolution":""}
	c.log_entry("Second Signature: identified the original boats under "+str(owner.name)+"; the harbor holds the bounty escrow.")
	return result

static func after_job(c,before: Dictionary,result: Dictionary,abandon: bool) -> void:
	var w: Dictionary=work(c)
	if w.is_empty() or not result.get("ok",false) or str(w.jobId)!=str(before.get("id","")) or str(before.get("kind",""))!="bounty" or str(before.get("ownerId",""))!=str(w.ownerId):return
	if not c.state.get("doneVoyageJobs",[]).has(str(w.jobId)):return
	if str(w.status)!="carried":return
	if abandon:
		w.status="abandoned"
		c.log_entry("The bounty was withdrawn under its contract refund terms. The original target and unfinished investigation remain recorded.")
	elif int(result.get("reward",-1))==int(w.reward):
		w.status="paid";w.payment=int(result.reward)
		c.log_entry("The harbor paid its bounty. Payment alone does not prove a witnessed encounter or recovered property.")
	if str(w.status)!="carried":w.closure={"jobId":str(w.jobId),"ownerId":str(w.ownerId),"status":str(w.status),"day":float(c.state.day),"payment":int(w.payment),"defeats":int(c.state.get("defeatedOwners",{}).get(str(w.ownerId),0))}

# Capture settlement can rename a conflicting hull UID. Preserve the original
# target identity and the SAME native dictionary across that normal transfer.
static func capture_snapshot(c,context: Dictionary,battle: Dictionary) -> Array:
	var out: Array=[]
	var w: Dictionary=work(c)
	if w.is_empty() or str(context.get("ownerId",""))!=str(w.ownerId) or w.reported:return out
	for boat in battle.get("captured",[]):
		if w.targetUids.has(str(boat.get("uid",""))):out.append({"originalUid":str(boat.uid),"boat":boat})
	return out

static func after_battle(c,result: String,context: Dictionary,battle: Dictionary,report: Dictionary,captured: Array) -> void:
	var w: Dictionary=work(c)
	if w.is_empty() or w.reported or battle.is_empty() or str(context.get("ownerId",""))!=str(w.ownerId):return
	if str(battle.get("result",""))!=result or float(battle.get("time",0))<=0 or report.get("participants",[]).is_empty():return
	if battle.get("_battleMirror051",false) and not battle.get("simulation051",{}).get("retired",false):return
	var sequence: int=int(battle.get("campaignSequence111",-1))
	var source: String=str(battle.get("engagementSource060",""))
	if sequence<=int(w.battleFloor) or sequence>int(c.state.get("battleSeq",0)) or source.is_empty():return
	for wreck in report.get("wrecks",[]):
		var uid: String=str(wreck.get("uid",""))
		if not w.targetUids.has(uid) or str(wreck.get("sourceId",""))!=source or wreck.get("friendly",false) or str(wreck.get("team",""))!="enemy":continue
		if w.captures.any(func(row):return str(row.originalUid)==uid):continue
		if w.wrecks.any(func(row):return str(row.uid)==uid):continue
		w.wrecks.append({"id":str(wreck.id),"uid":uid,"source":source,"sequence":sequence,"day":float(c.state.day),"terminal":{}})
	for row in captured:
		var boat: Dictionary=row.boat
		if boat.get("sunk",false) or not (c.state.fleet+c.state.get("boardingPrizes",[])).any(func(owned):return is_same(owned,boat)):continue
		if w.captures.any(func(old):return str(old.originalUid)==str(row.originalUid)):continue
		w.captures.append({"originalUid":str(row.originalUid),"boatUid":str(boat.uid),"kind":"captured","source":source,"sequence":sequence,"day":float(c.state.day)})
	if not w.wrecks.is_empty() or not w.captures.is_empty():c.log_entry("Second Signature: original target property located in a physical encounter. Recovery and custody still decide what you can report.")

static func after_recovery(c,id: String,result: Dictionary) -> void:
	var w: Dictionary=work(c) # Reacquired AFTER detached recovery publication.
	if w.is_empty() or w.reported or not result.get("ok",false) or w.recoveries.size()>=48:return
	var original: Dictionary={}
	for wreck in w.wrecks:
		if str(wreck.id)==id:original=wreck;break
	if original.is_empty():return
	# Native selected recovery dismantles the WHOLE hull and forfeits every
	# unselected fitting. Verify that published result instead of assuming it.
	var source: Dictionary=raw_wreck(c,id)
	if str(source.get("sourceId",""))!=str(original.source) or str(source.get("uid",""))!=str(original.uid) or not source.get("hullStripped",false) or str(source.get("claimedMode",""))!="gear" or str(source.get("equipmentCustody",""))!="retired" or source.has("sourceModuleCondition"):return
	var parts: Array=[]
	for part in result.get("selected",[]):parts.append(str(part.itemUid))
	if parts.is_empty():return
	if w.recoveries.any(func(row):return str(row.wreckId)==id):return
	w.recoveries.append({"wreckId":id,"source":str(original.source),"itemUids":parts,"carrierUid":str(result.carrierUid),"day":float(c.state.day),"wagesPaid":int(result.get("wagesPaid",0)),"foodConsumed":float(result.get("foodConsumed",0))})
	original.terminal={"mode":"gear","day":float(c.state.day)}
	c.log_entry("Second Signature: paid recovery retained original fittings. Keep that property in your current custody until reporting.")

static func after_tow(c,id: String,result: Dictionary) -> void:
	var w: Dictionary=work(c)
	if w.is_empty() or w.reported or not result.get("ok",false):return
	var wreck: Dictionary=c.Salvage.find_wreck(c.state,id)
	if str(wreck.get("status",""))!="towed":return
	for known in w.wrecks:
		if str(known.id)!=id or str(known.uid)!=str(wreck.get("uid","")) or str(known.source)!=str(wreck.get("sourceId","")):continue
		var boat_uid: String=str(wreck.get("towedBoatUid",""))
		if c.find_boat(boat_uid).is_empty() or w.captures.any(func(row):return str(row.originalUid)==str(known.uid)):return
		known.terminal={"mode":"tow","day":float(c.state.day)}
		w.captures.append({"originalUid":str(known.uid),"boatUid":boat_uid,"kind":"towed","source":str(known.source),"sequence":int(known.sequence),"day":float(c.state.day)})
		return

static func after_strip(c,id: String,result: Dictionary) -> void:
	var w: Dictionary=work(c)
	if w.is_empty() or w.reported or not result.get("ok",false):return
	for known in w.wrecks:
		if str(known.id)!=id:continue
		var raw: Dictionary=raw_wreck(c,id)
		if str(raw.get("uid",""))==str(known.uid) and str(raw.get("sourceId",""))==str(known.source) and raw.get("hullStripped",false) and str(raw.get("equipmentCustody",""))=="retired":known.terminal={"mode":"strip","day":float(c.state.day)}
		return

static func raw_wreck(c,id: String) -> Dictionary:
	for row in c.state.get("wrecks",[]):
		if row is Dictionary and str(row.get("id",""))==id:return row
	return {}

static func local_custody(c,include_remote: bool=false) -> Array:
	var out: Array=[]
	var here: String=str(c.current_port().get("id",""))
	for boat in c.state.get("fleet",[])+c.state.get("boardingPrizes",[]):
		if boat.get("sunk",false):continue
		var stored: String=str(boat.get("storedPort",""))
		if include_remote or stored.is_empty() or (not here.is_empty() and stored==here):out.append(boat)
	return out

static func secured(c,include_remote: bool=false) -> Dictionary:
	var w: Dictionary=work(c)
	if w.is_empty():return c.fail("Accept this chapter's funded contract first.")
	for boat in local_custody(c,include_remote):
		for capture in w.captures:
			if str(capture.boatUid)==str(boat.uid):return found("The original secured hull remains in your custody.","recovered" if capture.kind=="towed" else "captured")
		var items: Dictionary=boat.get("moduleCondition",{}).get("items",{})
		for receipt in w.recoveries:
			for uid in receipt.itemUids:
				if items.has(str(uid)):return found("An original paid-recovery fitting is in your local custody.","recovered")
	return c.fail("Keep an original recovered fitting or captured target hull with this fleet or at this harbor. A matching design or an old receipt is insufficient.")

static func loss(c) -> Dictionary:
	var w: Dictionary=work(c)
	if w.is_empty():return c.fail("No original target is bound to this investigation.")
	if secured(c,true).ok:return c.fail("Original property remains in your custody. Bring it with your fleet or report at its storage harbor; do not declare it lost.")
	if str(w.status)=="carried":return c.fail("Close the bounty at its sponsoring harbor before confirming the outcome.")
	var owner: Dictionary=c.fleet_owner(str(w.ownerId))
	if not owner.is_empty() and owner.boats.any(func(boat):return w.targetUids.has(str(boat.get("uid",""))) and not boat.get("sunk",false)):return c.fail("An original target boat remains afloat. Its unresolved property is not a confirmed loss.")
	# A witnessed wreck with recoverable original gear is unfinished, not lost.
	for known in w.wrecks:
		var wreck: Dictionary=raw_wreck(c,str(known.id))
		var terminal: Dictionary=known.get("terminal",{})
		if wreck.is_empty():
			if not terminal.is_empty():continue
			return c.fail("The identified wreck record is unavailable. That does not establish exhaustion; the investigation remains open.")
		if str(wreck.get("uid",""))!=str(known.uid) or str(wreck.get("sourceId",""))!=str(known.source) or str(wreck.get("status","")) not in ["unclaimed","stripped","towed"]:return c.fail("The identified wreck's status cannot be confirmed. Do not report an unknown source as lost.")
		var equipment= wreck.get("sourceModuleCondition",{})
		if not equipment is Dictionary or str(wreck.get("equipmentCustody",""))=="refused":return c.fail("The identified wreck's equipment cannot be read. Unreadable property is not a confirmed loss.")
		if equipment.get("items",{}).size()>0:return c.fail("An identified wreck still has original equipment. Recover it, secure its hull, or make an explicit confirmed forfeiture before reporting no retained property.")
		if not terminal.is_empty():continue
		return c.fail("There is no recorded stripping, dismantling or towing outcome for this original wreck. An empty or unknown record is not a confirmed loss.")
	# A paid bounty is public confirmation of a defeat, not our witness.
	if w.wrecks.is_empty() and str(w.status)!="paid" and (w.captures.is_empty() or int(w.closure.get("defeats",0))<=int(w.baselineDefeats)):return c.fail("There is no witnessed loss or paid harbor confirmation. An unseen or escaped target remains unresolved.")
	return found("Report that no original property is retained. Do not claim an unwitnessed battle or award a prize.","no_property")

static func choice_gate(c,choice: String) -> Dictionary:
	if choice not in ["report_property111","report_no_property111"]:return c.ok("")
	var w: Dictionary=work(c)
	if str(record(c).get("stage",""))!=STAGE or w.is_empty() or w.reported:return c.fail("This chapter is not awaiting that report.")
	if str(w.status)=="carried":return c.fail("Claim or withdraw the actual bounty at its sponsoring harbor first; the investigation does not discard held escrow.")
	if c.current_port().is_empty():return c.fail("Send this report while berthed at an actual harbor.")
	var permission: Dictionary=c.Politics.permit(c,"service")
	if not permission.ok:return permission
	return secured(c) if choice=="report_property111" else loss(c)

static func after_choice(c,choice: String,result: Dictionary) -> void:
	if not result.get("ok",false) or choice not in ["report_property111","report_no_property111"]:return
	var w: Dictionary=work(c)
	if w.is_empty() or w.reported:return
	w.resolution="no_property" if choice=="report_no_property111" else str(secured(c).get("resolution","recovered"))
	w.reported=true

static func gate(c,rule: Dictionary) -> Dictionary:
	if rule.get("mode","")=="optional":
		return c.ok("") if record(c).get("flags",[]).has("venn_claim_seen110") else c.fail("Hear Tobin's connection to Venn's guarantee first.")
	var property: Dictionary=choice_gate(c,"report_property111")
	if property.ok:return property
	var missing: Dictionary=choice_gate(c,"report_no_property111")
	return missing if missing.ok else property
