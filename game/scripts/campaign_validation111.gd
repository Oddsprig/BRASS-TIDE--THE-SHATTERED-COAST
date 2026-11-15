extends RefCounted
## Validate only111's separate progress. Native equipment/job validators retain
## ownership of the world ledger; completed historical receipts are not owners.
const ID: String="common_passage110"

static func number(v,low: float=0,high: float=1000000000,whole: bool=false) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v)>=low and float(v)<=high and (not whole or floorf(float(v))==float(v))

static func text(v,limit: int=160) -> bool:
	return v is String and not v.is_empty() and v.length()<=limit

static func ids(v,limit: int) -> bool:
	if not v is Array or v.is_empty() or v.size()>limit:return false
	var seen: Dictionary={}
	for uid in v:
		if not text(uid,120) or seen.has(uid):return false
		seen[uid]=true
	return true

static func validate(state: Dictionary) -> String:
	var rec: Dictionary=state.get("stories",{}).get("chains",{}).get(ID,{})
	if not rec.has("work111"):
		return "Missing Second Signature report." if str(rec.get("stage","")) in ["tobin_admission111","exit_channel112"] else ""
	var raw=rec.work111
	if not raw is Dictionary or raw.is_empty() or raw.size()>16:return "Invalid Second Signature record."
	var w: Dictionary=raw
	for key in ["jobId","ownerId","port"]:
		if not text(w.get(key)):return "Invalid Second Signature contract identity."
	if not ids(w.get("targetUids"),48):return "Invalid original bounty hull identities."
	for key in ["battleFloor","baselineDefeats","payment"]:
		if not number(w.get(key),0,1000000000,true):return "Invalid Second Signature counter."
	if not number(w.get("acceptedDay"),1,float(state.get("day",0))) or float(w.battleFloor)>float(state.get("battleSeq",0)) or not number(w.get("reward"),1,1000000000,true):return "Invalid funded investigation terms."
	if w.get("status","") not in ["carried","paid","abandoned"] or not w.get("reported") is bool or w.get("resolution","") not in ["","recovered","captured","no_property"]:return "Invalid investigation closure."
	if (w.status=="paid" and w.payment!=w.reward) or (w.status!="paid" and w.payment!=0):return "Investigation fee disagrees with native closure."
	if not w.get("closure") is Dictionary:return "Invalid bounty closure receipt."
	var closure: Dictionary=w.closure
	if w.status=="carried" and not closure.is_empty():return "Carried bounty already has a closed receipt."
	if w.status!="carried":
		if closure.get("jobId","")!=w.jobId or closure.get("ownerId","")!=w.ownerId or closure.get("status","")!=w.status or not number(closure.get("payment"),0,1000000000,true) or float(closure.payment)!=float(w.payment) or not number(closure.get("day"),float(w.acceptedDay),float(state.get("day",0))) or not number(closure.get("defeats"),0,1000000000,true):return "Bounty closure receipt disagrees with investigation."
		if w.status=="paid" and float(closure.defeats)<=float(w.baselineDefeats):return "Paid bounty has no newer defeat confirmation."
	if (w.reported and (w.status=="carried" or str(w.resolution).is_empty())) or (not w.reported and not str(w.resolution).is_empty()):return "Investigation report and resolution disagree."
	if str(rec.get("stage","")) in ["tobin_admission111","exit_channel112"] and not w.reported:return "Second Signature advanced without a report."
	for key in ["wrecks","captures","recoveries"]:
		if not w.get(key) is Array or w[key].size()>48:return "Invalid bounded investigation evidence."
	if w.reported and ((w.resolution=="captured" and w.captures.is_empty()) or (w.resolution=="recovered" and w.wrecks.is_empty())):return "Reported property has no original physical source."
	if w.reported and w.resolution=="captured" and not w.captures.any(func(row):return row is Dictionary and row.get("kind","")=="captured"):return "Captured report has no captured-kind receipt."
	if w.reported and w.resolution=="recovered" and w.recoveries.is_empty() and not w.captures.any(func(row):return row is Dictionary and row.get("kind","")=="towed"):return "Recovered report has no paid fitting or towed-hull receipt."
	var seen_uid: Dictionary={}
	var wrecks: Dictionary={}
	var floor: float=float(w.battleFloor)
	var latest: float=float(state.get("battleSeq",0))
	for row in w.wrecks+w.captures:
		if not row is Dictionary:return "Invalid physical encounter evidence."
		if not text(row.get("source")) or not number(row.get("sequence"),floor+1,latest,true) or not number(row.get("day"),float(w.acceptedDay),float(state.get("day",0))):return "Invalid or stale physical encounter source."
	for row in w.wrecks:
		if not text(row.get("id")) or not text(row.get("uid"),120) or not w.targetUids.has(row.uid) or seen_uid.has(row.uid) or wrecks.has(row.id):return "Invalid original wreck identity."
		var terminal=row.get("terminal",{})
		if not terminal is Dictionary:return "Invalid original wreck terminal receipt."
		if not terminal.is_empty() and (terminal.get("mode","") not in ["gear","strip","tow"] or not number(terminal.get("day"),float(row.day),float(state.get("day",0)))):return "Invalid original wreck terminal outcome."
		seen_uid[row.uid]=true;wrecks[row.id]=row
	for row in w.captures:
		if not text(row.get("originalUid"),120) or not text(row.get("boatUid"),120) or row.get("kind","") not in ["captured","towed"] or not w.targetUids.has(row.originalUid):return "Invalid original secured hull identity."
		if row.kind=="captured" and seen_uid.has(row.originalUid):return "A captured original hull also has a wreck."
		if row.kind=="towed" and not w.wrecks.any(func(wreck):return str(wreck.uid)==str(row.originalUid) and str(wreck.source)==str(row.source)):return "Towed property has no original witnessed wreck."
		var key: String="secured:"+str(row.originalUid)
		if seen_uid.has(key):return "An original secured hull is repeated."
		seen_uid[key]=true
	var recovered: Dictionary={}
	var parts: Dictionary={}
	for row in w.recoveries:
		if not row is Dictionary or not text(row.get("wreckId")) or not wrecks.has(row.wreckId) or recovered.has(row.wreckId):return "Recovery has no original witnessed wreck."
		if not text(row.get("source")) or row.source!=wrecks[row.wreckId].source or not text(row.get("carrierUid"),120) or not ids(row.get("itemUids"),512):return "Invalid original recovered part identities."
		if not number(row.get("day"),float(w.acceptedDay),float(state.get("day",0))) or not number(row.get("wagesPaid"),1,1000000000,true) or not number(row.get("foodConsumed")):return "Invalid actual recovery work receipt."
		recovered[row.wreckId]=true
		for uid in row.itemUids:
			if parts.has(uid):return "An original fitting is repeated in recovery evidence."
			parts[uid]=true
		if parts.size()>512:return "Investigation recovered-part limit exceeded."
	for row in w.wrecks:
		var mode: String=str(row.get("terminal",{}).get("mode",""))
		if mode=="gear" and not w.recoveries.any(func(receipt):return str(receipt.wreckId)==str(row.id) and str(receipt.source)==str(row.source) and float(receipt.day)==float(row.terminal.day)):return "Gear terminal has no matching paid dismantling receipt."
		if mode=="tow" and not w.captures.any(func(receipt):return receipt.kind=="towed" and str(receipt.originalUid)==str(row.uid) and str(receipt.source)==str(row.source) and float(receipt.day)==float(row.terminal.day)):return "Tow terminal has no matching towed-hull receipt."
	if w.reported and w.resolution=="no_property":
		if w.wrecks.is_empty() and w.status!="paid" and (w.captures.is_empty() or float(closure.get("defeats",0))<=float(w.baselineDefeats)):return "No-property report has no terminal or defeat evidence."
		for row in w.wrecks:
			if row.get("terminal",{}).is_empty():return "No-property report has an unresolved original wreck."
	if w.status=="carried":
		var job: Dictionary={}
		for entry in state.get("voyageJobs",[]):
			if entry is Dictionary and str(entry.get("id",""))==str(w.jobId):job=entry;break
		if job.is_empty() or job.get("kind","")!="bounty" or job.get("ownerId","")!=w.ownerId or job.get("port","")!=w.port or int(job.get("reward",-1))!=int(w.reward) or int(job.get("baselineDefeats",-1))!=int(w.baselineDefeats) or float(job.get("acceptedDay",-1))!=float(w.acceptedDay):return "Investigation has no matching native carried bounty."
	else:
		for job in state.get("voyageJobs",[]):
			if job is Dictionary and str(job.get("id",""))==str(w.jobId):return "Investigation bounty is both carried and closed."
	return ""
