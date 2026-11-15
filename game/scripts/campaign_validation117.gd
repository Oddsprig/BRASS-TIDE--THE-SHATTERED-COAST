extends RefCounted
## Strict raw117 preflight. Existing validators retain native economy,
## ownership, escort physics and save-schema authority. No normalization.
const ID: String="common_passage110"
const Goods=preload("res://scripts/goods.gd")
const COINS: float=9007199254740991.0
const QUOTE_FIELDS: Array=["cost","material","own","purchase","ordinary","expert","materials","fee","hullKits","equipmentKits","equipmentMaterials","ordinaryDays","expertDays","workerDays"]
const BINDING_FIELDS: Array=["jobId","ownerId","port","targetPort","payerKey","reward","acceptedDay","voyageSeq","fromPort","carrierUids","carrierCargo","tradeGood","tradeQty","baselineDelivered","routeDistance"]

static func number(v,low: float=0,high: float=1000000000,whole: bool=false) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v)>=low and float(v)<=high and (not whole or floorf(float(v))==float(v))

static func text(v) -> bool:
	return v is String and not v.is_empty() and v.length()<=160

static func shape(v,fields: Array) -> bool:
	if not v is Dictionary or v.size()!=fields.size():return false
	for key in fields:
		if not v.has(key):return false
	return true

static func identity(job: Dictionary) -> Dictionary:
	if job.get("kind")!="escort" or not job.get("escort") is Dictionary:return {}
	var route: Dictionary=job.escort
	return {"jobId":job.get("id"),"ownerId":job.get("ownerId"),"port":job.get("port"),"targetPort":job.get("targetPort"),"payerKey":job.get("payerKey"),"reward":job.get("reward"),"acceptedDay":job.get("acceptedDay"),"voyageSeq":route.get("voyageSeq"),"fromPort":route.get("fromPort"),"carrierUids":route.get("carrierUids"),"carrierCargo":route.get("carrierCargo"),"tradeGood":route.get("tradeGood"),"tradeQty":route.get("tradeQty"),"baselineDelivered":route.get("baselineDelivered"),"routeDistance":route.get("routeDistance")}.duplicate(true)

static func terms(job: Dictionary) -> Dictionary:
	var out: Dictionary=identity(job)
	out.erase("acceptedDay")
	return out

static func sale(job: Dictionary) -> Dictionary:
	var route: Dictionary=job.get("escort",{})
	var out: Dictionary={}
	for key in ["arrivedDay","deliveredQty","accompaniedDistance","playerDistance","interceptions","exitSecured","carrierUids"]:
		out[key]=route.get(key,0 if key=="interceptions" else null)
	return out.duplicate(true)

static func sale_valid(q,b: Dictionary,now: float) -> bool:
	if not shape(q,["arrivedDay","deliveredQty","accompaniedDistance","playerDistance","interceptions","exitSecured","carrierUids"]):return false
	if not number(q.arrivedDay,float(b.acceptedDay),now) or not number(q.deliveredQty) or float(q.deliveredQty)+0.000001<float(b.tradeQty):return false
	for key in ["accompaniedDistance","playerDistance"]:
		if not number(q[key]) or float(q[key])+40.0<float(b.routeDistance)*0.8:return false
	return number(q.interceptions,0,1000000000,true) and q.exitSecured is bool and (q.interceptions==0 or q.exitSecured) and q.carrierUids==b.carrierUids

static func quote_valid(q) -> bool:
	if not shape(q,QUOTE_FIELDS) or not q.equipmentMaterials is Dictionary or q.equipmentMaterials.size()>3:return false
	for key in QUOTE_FIELDS:
		if key=="equipmentMaterials":continue
		if not number(q[key],0,COINS,key in ["cost","ordinary","expert","materials","fee"]):return false
	for key in q.equipmentMaterials:
		if not (key is String or key is StringName) or str(key) not in ["iron","copper","timber"] or not number(q.equipmentMaterials[key]):return false
	if q.cost!=q.ordinary+q.expert+q.materials+q.fee or q.own>q.material:return false
	if absf(float(q.material)-float(q.hullKits)-float(q.equipmentKits))>0.000001 or absf(float(q.purchase)-maxf(0,float(q.material)-float(q.own)))>0.000001:return false
	if absf(float(q.workerDays)-float(q.ordinaryDays)-float(q.expertDays))>0.000001:return false
	return float(q.material)>0.0 or float(q.workerDays)>0.0

static func _find(rows: Array,id: String) -> Dictionary:
	for row in rows:
		if row is Dictionary and row.get("id")==id:return row
	return {}

static func _binding(b,s: Dictionary,selected: float) -> bool:
	if not shape(b,BINDING_FIELDS):return false
	for key in ["jobId","ownerId","port","targetPort","fromPort","tradeGood"]:
		if not text(b[key]):return false
	if b.payerKey!="coins" or b.fromPort==b.targetPort or not number(b.reward,1,COINS,true) or not number(b.voyageSeq,0,1000000000,true) or not number(b.acceptedDay,selected,float(s.day)):return false
	if b.jobId!="escort:%s:%d"%[b.ownerId,int(b.voyageSeq)] or not Goods.ITEMS.has(b.tradeGood) or not number(b.tradeQty,0.000001) or not number(b.baselineDelivered) or not number(b.routeDistance,160):return false
	for key in ["port","targetPort","fromPort"]:
		if _find(s.get("ports",[]),str(b[key])).is_empty():return false
	if not b.carrierUids is Array or b.carrierUids.is_empty() or b.carrierUids.size()>48 or not b.carrierCargo is Dictionary or b.carrierCargo.size()!=b.carrierUids.size():return false
	var seen: Dictionary={}
	var total: float=0.0
	for uid in b.carrierUids:
		if not text(uid) or seen.has(uid) or not b.carrierCargo.get(uid) is Dictionary:return false
		seen[uid]=true
		var load: Dictionary=b.carrierCargo[uid]
		if load.is_empty() or load.size()>Goods.ITEMS.size():return false
		for good in load:
			if not (good is String or good is StringName) or not Goods.ITEMS.has(str(good)) or not number(load[good],0.000001):return false
			total+=float(load[good]) if str(good)==str(b.tradeGood) else 0.0
	return total+0.000001>=float(b.tradeQty)

static func _shares(a: Dictionary,model: String) -> int:
	if not a.contributions is Array:return -1
	if model=="separate":return 0 if a.contributions.is_empty() else -1
	if a.contributions.size()!=2:return -1
	var b: Dictionary=a.binding
	var expected: Array=[str(b.fromPort),str(b.targetPort)]
	var first: int=floori(float(b.reward)/2.0)
	var amounts: Array=[first,int(b.reward)-first]
	for i in range(2):
		var row=a.contributions[i]
		if not shape(row,["portId","amount"]) or row.portId!=expected[i] or not number(row.amount,1,COINS,true) or row.amount!=amounts[i]:return -1
	return int(b.reward)

static func _attempt(a,s: Dictionary,model: String,selected: float) -> String:
	if not shape(a,["binding","contributions","refund","refundDay","reimbursed","status","closure","follow","followClock"]):return "117: invalid bounded native attempt."
	if not _binding(a.binding,s,selected):return "117: invalid original native escort identity or cargo."
	var b: Dictionary=a.binding
	var contributed: int=_shares(a,model)
	if contributed<0:return "117: contribution identities or integer shares differ from the chosen terms."
	if a.status not in ["carried","paid","abandoned"] or not a.follow is bool or not number(a.followClock,0,1):return "117: invalid attempt state or follow clock."
	if not number(a.refund,0,float(b.reward),true) or not number(a.reimbursed,0,float(contributed),true) or a.reimbursed not in [0,contributed] or a.reimbursed>a.refund:return "117: unsupported or duplicate contributor return."
	if a.refund==0:
		if not number(a.refundDay,-1,-1):return "117: unobserved refund has a receipt date."
	elif not number(a.refundDay,float(b.acceptedDay),float(s.day)):return "117: refund observation predates admission or is in the future."
	if not a.closure is Dictionary:return "117: invalid native closure record."
	var live: Dictionary=_find(s.get("voyageJobs",[]),str(b.jobId))
	if a.status=="carried":
		if not a.closure.is_empty() or a.reimbursed!=0 or live.is_empty() or identity(live)!=b or s.get("doneVoyageJobs",[]).has(str(b.jobId)):return "117: carried native escort disappeared, changed or already closed."
		if live.get("state") not in ["active","expired"] or not number(live.get("escrow"),0,float(b.reward),true) or int(live.escrow)+int(a.refund)!=int(b.reward):return "117: observed refund disagrees with actual remaining native escrow."
		if live.state=="active" and a.refund!=0:return "117: active fee was already refunded."
		return ""
	if not live.is_empty() or a.follow:return "117: closed escort is still carried or followed."
	var q: Dictionary=a.closure
	if not shape(q,["jobId","ownerId","status","day","payment","sale"]) or q.jobId!=b.jobId or q.ownerId!=b.ownerId or q.status!=a.status or not number(q.day,float(b.acceptedDay),float(s.day)) or not number(q.payment,0,float(b.reward),true):return "117: invalid native once-only closure."
	if a.refund>0 and float(a.refundDay)>float(q.day):return "117: refund was observed after closure."
	if a.status=="paid":
		if q.payment!=b.reward or a.refund!=0 or a.reimbursed!=0 or not sale_valid(q.sale,b,float(q.day)):return "117: paid closure lacks the original actual cargo sale and escort payment."
	else:
		if q.payment!=0 or not q.sale is Dictionary or not q.sale.is_empty():return "117: abandoned fee claims payment or sale."
	# Closed receipts remain historical after native doneVoyageJobs' bounded
	# 128-entry cache evicts an old ID. Runtime capture required that native ID.
	return ""

static func validate(s: Dictionary) -> String:
	if not number(s.get("day"),1):return "117: invalid campaign calendar."
	for key in ["ports","voyageJobs","doneVoyageJobs"]:
		if not s.get(key,[]) is Array:return "117: validate native harbor/job arrays first."
	var stories=s.get("stories",{})
	if not stories is Dictionary or not stories.get("chains",{}) is Dictionary:return "117: invalid raw story structure."
	var rec=stories.chains.get(ID,{})
	if not rec is Dictionary:return "117: invalid campaign record."
	var stage=rec.get("stage","")
	var required: bool=stage in ["funding_work117","funding_account117","fuel_has_owners118"]
	if not rec.has("work117"):return "117: missing chosen funding account." if required else ""
	var w=rec.work117
	if not shape(w,["schema","model","choiceId","selectedDay","attempts","reported","reportDay","mara"]):return "117: invalid bounded funding record."
	if not number(w.schema,1,1,true) or w.model not in ["","mutual","separate"] or not w.choiceId is String or not w.attempts is Array or w.attempts.size()>8 or not w.reported is bool or not w.mara is Dictionary:return "117: invalid raw funding types."
	if w.model=="":
		if required or w.choiceId!="" or not number(w.selectedDay,-1,-1) or not w.attempts.is_empty() or w.reported:return "117: optional unselected work claims a funding commitment."
	else:
		var expected: String="choose_mutual117" if w.model=="mutual" else "choose_separate117"
		if w.choiceId!=expected or not number(w.selectedDay,1,float(s.day)) or stage=="who_pays117":return "117: invalid disclosed pre-admission commitment."
	var ids: Dictionary={}
	var prior: Dictionary={}
	var last: Dictionary={}
	var old=rec.get("work116",{})
	if not old is Dictionary or not old.get("priority",{}) is Dictionary:return "117: validate prior116 identity first."
	for raw in w.attempts:
		var error: String=_attempt(raw,s,str(w.model),float(w.selectedDay))
		if not error.is_empty():return error
		var a: Dictionary=raw
		var b: Dictionary=a.binding
		if ids.has(b.jobId):return "117: duplicate native passage admission."
		ids[b.jobId]=true
		if b.jobId==old.get("priority",{}).get("jobId",""):return "117: an earlier116 native job cannot complete117."
		if not prior.is_empty() and (prior.status!="abandoned" or int(prior.reimbursed)!=_shares(prior,str(w.model)) or float(prior.closure.day)>float(b.acceptedDay)):return "117: retry predates closure or leaves contributors unsettled."
		prior=a;last=a
	if w.reported:
		if last.get("status","")!="paid" or not number(w.reportDay,float(last.get("closure",{}).get("day",-1)),float(s.day)) or stage in ["who_pays117","funding_work117"]:return "117: report lacks the actual completed paid escort."
	elif not number(w.reportDay,-1,-1) or stage in ["funding_account117","fuel_has_owners118"]:return "117: report date or progression precedes actual payment."
	if not w.mara.is_empty():
		var m: Dictionary=w.mara
		if not shape(m,["uid","port","day","quote","discussed"]) or not text(m.uid) or m.port!="anvil_dock" or not number(m.day,1,float(s.day)) or not m.discussed is bool or not quote_valid(m.quote):return "117: invalid actual selected hull estimate."
		if not stories.chains.get("mara_work113") is Dictionary:return "117: Mara estimate lacks its existing optional conversation."
	return ""
