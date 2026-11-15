extends RefCounted
## Raw119 preflight: no normalization, purse writes or representation equality.
const P=preload("res://scripts/campaign_validation117.gd")
const W=preload("res://scripts/campaign_validation115.gd")
const ID: String="common_passage110"
const TERMS: Array=["jobId","port","targetPort","regionId","targetRegionId","payerKey","reward","fee","materialInvoice","acceptedDay","deadlineDay","routeDays","routeDistance"]
const ACCOUNTS: Dictionary={"common":"common_account119","many":"many_account119","unsettled":"unsettled_account119"}

static func _find(rows: Array,id: String,key: String="id") -> Dictionary:
	for row in rows:
		if row is Dictionary and row.get(key)==id:return row
	return {}

static func c2(s: Dictionary) -> Dictionary:
	var prior=s.get("stories",{}).get("chains",{}).get(ID,{}).get("work117",{})
	if not prior is Dictionary or not prior.get("reported") is bool or not prior.reported or prior.get("model") not in ["mutual","separate"] or not prior.get("attempts") is Array or prior.attempts.is_empty():return {}
	var last=prior.attempts[-1]
	if not last is Dictionary or last.get("status")!="paid" or not last.get("binding") is Dictionary or not last.get("closure") is Dictionary:return {}
	var closed: Dictionary=last.closure
	var expected: String="choose_mutual117" if prior.model=="mutual" else "choose_separate117"
	if prior.get("choiceId")!=expected or closed.get("status")!="paid" or not P.number(closed.get("day"),1,float(s.get("day",0))) or not P.number(prior.get("reportDay"),float(closed.day),float(s.get("day",0))):return {}
	if not P.number(last.binding.get("reward"),1,P.COINS,true) or not P.number(closed.get("payment"),float(last.binding.reward),float(last.binding.reward),true):return {}
	return {"model":prior.model,"choiceId":prior.choiceId,"reportDay":prior.reportDay}

static func prior_ready(s: Dictionary,before: float) -> bool:
	var prior=s.get("stories",{}).get("chains",{}).get(ID,{}).get("work118",{})
	return prior is Dictionary and prior.get("warrantReported") is bool and prior.warrantReported and P.number(prior.get("warrantReportDay"),1,before)

static func terms(job: Dictionary) -> Dictionary:
	if job.get("kind")!="freight":return {}
	var out: Dictionary={}
	for key in TERMS:
		out[key]=job.get("id") if key=="jobId" else job.get("reward") if key=="fee" else job.get(key)
	return out.duplicate(true)

static func identity(job: Dictionary) -> Dictionary:
	var out: Dictionary=terms(job)
	if out.is_empty():return out
	var lot=job.get("freight",{})
	out.good=lot.get("good") if lot is Dictionary else null
	out.qty=lot.get("qty") if lot is Dictionary else null
	return out

static func binding(b,now: float) -> bool:
	if not P.shape(b,TERMS+["good","qty"]):return false
	if not P.text(b.jobId) or not b.jobId.begins_with("common119:") or b.port!="anvil_dock" or b.targetPort!="westglass_anchorage" or b.regionId!="shatter_coast" or b.targetRegionId!="glasswind_keys" or b.payerKey!="governmentPurse" or b.good!="food":return false
	for key in ["reward","fee","materialInvoice"]:
		if not P.number(b[key],1,P.COINS,true):return false
	if b.reward!=b.fee or float(b.fee)+float(b.materialInvoice)>P.COINS or not P.number(b.qty,1,8,true) or int(b.materialInvoice)%int(b.qty)!=0:return false
	return P.number(b.acceptedDay,1,now) and P.number(b.deadlineDay,float(b.acceptedDay),1000000000) and P.number(b.routeDays,1,1000000000,true) and P.number(b.routeDistance,0.000001)

static func freight(f,b: Dictionary,failed: bool) -> bool:
	if not f is Dictionary:return false
	if f.is_empty():return failed
	if not P.shape(f,["good","qty","lost"]) or f.good!=b.good or not f.lost is bool or not P.number(f.qty,0,float(b.qty),true):return false
	return (f.qty==b.qty and not f.lost) or (failed and f.lost)

static func matches(job: Dictionary,b: Dictionary) -> bool:
	var saved: Dictionary={}
	for key in TERMS:saved[key]=b.get(key)
	return job.get("kind")=="freight" and job.get("ownerId","")=="" and job.get("carrierUid","")=="" and job.get("failed") is bool and P.same_value(terms(job),saved) and freight(job.get("freight"),b,job.failed)

static func allocations(s: Dictionary,id: String) -> Dictionary:
	var out: Dictionary={}
	var manifest=s.get("cargoManifest",{})
	if not manifest is Dictionary:return out
	for uid in manifest:
		var row=manifest[uid]
		if row is Dictionary and row.has("@job:"+id):out[uid]=row["@job:"+id]
	return out.duplicate(true)

static func allocation(m,qty: float,partial: bool) -> bool:
	if not m is Dictionary or m.size()>48 or (not partial and (m.is_empty() or m.has("unassigned"))):return false
	var total: int=0
	for uid in m:
		if not P.text(uid) or not P.number(m[uid],1,qty,true):return false
		total+=int(m[uid])
	return total<=qty if partial else total==qty

static func originals(s: Dictionary,m: Dictionary) -> bool:
	for uid in m:
		var boat: Dictionary=_find(s.get("fleet",[]),str(uid),"uid")
		if boat.is_empty() or boat.get("sunk",false) or boat.get("mothballed",false) or boat.get("needsHarborRepair",false) or boat.get("storedPort","")!="":return false
		if not P.number(boat.get("crew")) or not P.number(boat.get("crewMin"),1) or boat.crew<boat.crewMin:return false
	return not m.is_empty() and not m.has("unassigned")

static func balances(q) -> bool:
	if not P.shape(q,["sourceGov","targetGov","captain","supplierCash","stock"]):return false
	for key in ["sourceGov","targetGov","captain","supplierCash"]:
		if not P.number(q[key],0,P.COINS,true):return false
	return P.number(q.stock)

static func funding(f,b: Dictionary,s: Dictionary) -> bool:
	if not P.shape(f,["model","choiceId","reportDay","contributions","before","after"]) or not balances(f.before) or not balances(f.after):return false
	var chosen: Dictionary=c2(s)
	if chosen.is_empty() or f.model!=chosen.model or f.choiceId!=chosen.choiceId or not P.number(f.reportDay,1,float(b.acceptedDay)) or not P.same_value(f.reportDay,chosen.reportDay):return false
	var invoice: int=int(b.materialInvoice)
	var fee: int=int(b.fee)
	var left: int=floori(float(fee)/2.0)
	var right: int=fee-left
	var deposit: int=right if f.model=="mutual" else invoice+fee
	var expected: Array=[{"payer":"anvil_government","amount":invoice+left},{"payer":"westglass_government","amount":right}] if f.model=="mutual" else [{"payer":"captain","amount":invoice+fee}]
	if not P.same_value(f.contributions,expected) or int(f.before.sourceGov)>int(P.COINS)-deposit or int(f.before.supplierCash)>int(P.COINS)-invoice:return false
	if f.after.supplierCash!=f.before.supplierCash+invoice or absf(float(f.before.stock)-float(f.after.stock)-float(b.qty))>0.000001:return false
	if f.model=="mutual":return f.before.sourceGov>=invoice+left and f.before.targetGov>=right and f.after.sourceGov==f.before.sourceGov-invoice-left and f.after.targetGov==f.before.targetGov-right and f.after.captain==f.before.captain
	return f.before.captain>=invoice+fee and f.after.sourceGov==f.before.sourceGov and f.after.targetGov==f.before.targetGov and f.after.captain==f.before.captain-invoice-fee

static func refund_limit(a: Dictionary) -> int:
	var b=a.get("binding",{})
	if not b is Dictionary or not P.number(b.get("fee"),1,P.COINS,true):return 0
	return int(b.fee)-floori(float(b.fee)/2.0) if a.get("funding",{}).get("model")=="mutual" else int(b.fee)

static func refund_due(a: Dictionary) -> int:
	if a.get("status")!="abandoned" or not a.get("closure") is Dictionary or a.closure.is_empty():return 0
	var limit: int=refund_limit(a)
	return limit-int(a.repaid) if P.number(a.get("repaid"),0,float(limit),true) else 0

static func _crossing(rows,from: String,to: String,first: float,now: float) -> bool:
	if not rows is Array or rows.size()>2:return false
	for i in range(rows.size()):
		var r=rows[i]
		if not P.shape(r,["fromLayer","fromRegion","toLayer","toRegion","region","approach","day"]) or not P.text(r.approach) or not P.number(r.day,first,now):return false
		if i==0:
			if r.fromLayer not in ["home","local"] or r.fromRegion!=from or r.toLayer!="ocean" or r.toRegion!="open_ocean" or r.region!=from:return false
		else:
			if r.fromLayer!="ocean" or r.fromRegion!="open_ocean" or r.toLayer not in ["home","local"] or r.toRegion!=to or r.region!=to or float(r.day)<=float(rows[0].day):return false
	return true

static func travel(t,b: Dictionary,m: Dictionary,s: Dictionary) -> bool:
	if not P.shape(t,["outbound","returning","outSeconds","backSeconds","outDistance","backDistance","arrivalDay","returnDay","originalIntact","exitProof","battleFloor","battles"]):return false
	if not t.originalIntact is bool or not t.exitProof is bool or not P.number(t.battleFloor,0,float(s.get("battleSeq",0)),true) or not t.battles is Array or t.battles.size()>8:return false
	var now: float=float(s.day)
	if not _crossing(t.outbound,"shatter_coast","glasswind_keys",float(b.acceptedDay),now) or not _crossing(t.returning,"glasswind_keys","shatter_coast",float(b.acceptedDay),now):return false
	for key in ["outSeconds","backSeconds","outDistance","backDistance"]:
		if not P.number(t[key]):return false
	if t.outbound.is_empty() and (t.outSeconds!=0 or t.outDistance!=0):return false
	if t.returning.is_empty() and (t.backSeconds!=0 or t.backDistance!=0):return false
	if t.outbound.size()==2 and (t.outSeconds<=0 or t.outDistance<=0):return false
	if t.returning.size()==2 and (t.backSeconds<=0 or t.backDistance<=0):return false
	for key in ["arrivalDay","returnDay"]:
		if not P.number(t[key],-1,now) or (t[key]<0 and t[key]!=-1):return false
	if t.arrivalDay>=0 and (t.outbound.size()!=2 or float(t.arrivalDay)<float(t.outbound[-1].day)):return false
	if not t.returning.is_empty() and (t.arrivalDay<0 or float(t.returning[0].day)<float(t.arrivalDay)):return false
	if t.returnDay>=0 and (t.returning.size()!=2 or float(t.returnDay)<float(t.returning[-1].day)):return false
	var sequence: int=int(t.battleFloor)
	var sources: Dictionary={}
	for i in range(t.battles.size()):
		var r=t.battles[i]
		if not P.shape(r,["source","sequence","ownerId","day","result","clearVictory","exits","afloat","reserve"]) or not P.text(r.source) or sources.has(r.source) or not P.text(r.ownerId) or not P.number(r.sequence,float(sequence)+1,float(s.get("battleSeq",0)),true) or not P.number(r.day,float(b.acceptedDay),now):return false
		if r.result not in ["won","lost","retreated"] or not r.clearVictory is bool or (r.clearVictory and r.result!="won"):return false
		sources[r.source]=true;sequence=int(r.sequence)
		var seen: Dictionary={}
		for group in ["exits","afloat","reserve"]:
			if not r[group] is Array or r[group].size()>m.size():return false
			for uid in r[group]:
				if not P.text(uid) or not m.has(uid) or seen.has(uid):return false
				seen[uid]=true
		if t.exitProof and (r.sequence!=int(t.battleFloor)+i+1 or (r.exits.size()!=m.size() and (not r.clearVictory or seen.size()!=m.size()))):return false
	return true

static func closure(q,a: Dictionary,status: String,now: float) -> bool:
	if not P.shape(q,["jobId","day","berth","stockBefore","stockAfter","coinsBefore","coinsAfter","escrowBefore","freight","allocations","payment","refundAtClose","failed","battleSequence"]):return false
	var b: Dictionary=a.binding
	if q.jobId!=b.jobId or not P.number(q.day,float(b.acceptedDay),now) or not q.berth is String or not q.failed is bool or not freight(q.freight,b,q.failed) or not allocation(q.allocations,float(b.qty),true):return false
	for key in ["coinsBefore","coinsAfter","payment","refundAtClose","escrowBefore"]:
		if not P.number(q[key],0,P.COINS,true):return false
	if q.escrowBefore>b.fee or not P.number(q.battleSequence,float(a.travel.battleFloor),1000000000,true):return false
	if not P.number(q.stockBefore,-1) or not P.number(q.stockAfter,-1):return false
	if q.berth=="":
		if status!="abandoned" or not q.freight.is_empty() or q.stockBefore!=-1 or q.stockAfter!=-1:return false
	elif not P.text(q.berth) or q.stockBefore<0 or q.stockAfter<0:return false
	if status=="paid":
		if q.berth!=b.targetPort or q.failed or q.freight.get("lost",true) or not P.same_value(q.freight.get("qty"),b.qty) or not P.same_value(q.allocations,a.allocations):return false
		if q.payment!=b.fee or q.escrowBefore!=b.fee or q.refundAtClose!=0 or a.refund!=0 or q.coinsAfter!=q.coinsBefore+b.fee:return false
		if not a.travel.originalIntact or not a.travel.exitProof or a.travel.outbound.size()!=2 or a.travel.arrivalDay<0 or float(q.day)<float(a.travel.arrivalDay) or q.battleSequence!=int(a.travel.battleFloor)+a.travel.battles.size():return false
		return absf(float(q.stockAfter)-float(q.stockBefore)-float(b.qty))<=0.000001
	var unloaded: float=0.0 if q.freight.get("lost",true) else float(q.freight.get("qty",0))
	return status=="abandoned" and q.payment==0 and q.coinsAfter==q.coinsBefore and q.refundAtClose==a.refund and a.refund==b.fee and absf(float(q.stockAfter)-float(q.stockBefore)-unloaded)<=0.000001

static func _attempt(a,s: Dictionary,first: float) -> String:
	if not P.shape(a,["binding","allocations","funding","travel","status","refund","refundDay","repaid","repayDay","closure"]):return "119: invalid bounded attempt shape."
	if not binding(a.binding,float(s.day)) or float(a.binding.acceptedDay)<first or not allocation(a.allocations,float(a.binding.qty),false):return "119: invalid original freight identity or manifest allocation."
	if _find(s.get("ports",[]),str(a.binding.port)).is_empty() or _find(s.get("ports",[]),str(a.binding.targetPort)).get("regionId")!="glasswind_keys":return "119: original source or Westglass destination disappeared."
	if not funding(a.funding,a.binding,s) or not travel(a.travel,a.binding,a.allocations,s):return "119: funding, integer balances, original exits or travel chronology differ from the bound terms."
	if a.status not in ["carried","paid","abandoned"] or not a.closure is Dictionary:return "119: invalid carried or closed state."
	if not P.number(a.refund,0,float(a.binding.fee),true) or not P.number(a.repaid,0,float(refund_limit(a)),true) or (a.repaid!=0 and a.repaid!=refund_limit(a)) or a.repaid>a.refund:return "119: invalid, fractional or duplicate fee return."
	if a.refund==0:
		if not P.number(a.refundDay,-1,-1):return "119: unobserved refund has a date."
	elif not P.number(a.refundDay,float(a.binding.acceptedDay),float(s.day)):return "119: refund predates admission or is in the future."
	if a.repaid==0:
		if not P.number(a.repayDay,-1,-1):return "119: unpaid fee obligation has a repayment date."
	elif a.status!="abandoned" or a.closure.is_empty() or not P.number(a.closure.get("day"),float(a.binding.acceptedDay),float(s.day)) or not P.number(a.repayDay,float(a.closure.day),float(s.day)):return "119: repayment precedes native abandoned closure."
	var live: Dictionary=_find(s.get("voyageJobs",[]),str(a.binding.jobId))
	if a.status=="carried":
		if not a.closure.is_empty() or a.repaid!=0 or live.is_empty() or not matches(live,a.binding) or s.get("doneVoyageJobs",[]).has(a.binding.jobId):return "119: original carried job changed, vanished or already closed."
		if live.get("state") not in ["active","expired"] or not P.number(live.get("escrow"),0,float(a.binding.fee),true) or live.escrow+a.refund!=a.binding.fee or (live.state=="active" and a.refund!=0):return "119: observed refund disagrees with the actual native escrow."
		if a.travel.originalIntact and (not P.same_value(allocations(s,str(a.binding.jobId)),a.allocations) or not originals(s,a.allocations)):return "119: claimed original manifest was lost or substituted."
		if not a.travel.returning.is_empty() or a.travel.returnDay!=-1:return "119: unpaid freight claims a post-payment return."
		return ""
	if not live.is_empty() or not closure(a.closure,a,str(a.status),float(s.day)):return "119: missing or inconsistent once-only native closure."
	if a.refund>0 and float(a.refundDay)>float(a.closure.day):return "119: refund was recorded after closure."
	if a.status=="paid":
		if a.refund!=0 or a.repaid!=0:return "119: paid delivery also claims a refunded fee."
		if not a.travel.returning.is_empty() and float(a.travel.returning[0].day)<float(a.closure.day):return "119: return crossing predates actual paid settlement."
		if a.travel.returnDay>=0 and float(a.travel.returnDay)<=float(a.closure.day):return "119: Brass return predates the paid destination settlement."
	elif not a.travel.returning.is_empty() or a.travel.returnDay!=-1:return "119: abandoned delivery claims a paid return."
	return ""

static func validate(s: Dictionary) -> String:
	if not P.number(s.get("day"),1) or not P.number(s.get("battleSeq",0),0,1000000000,true):return "119: invalid raw calendar or battle sequence."
	for key in ["ports","fleet","voyageJobs","doneVoyageJobs"]:
		if not s.get(key,[]) is Array:return "119: validate native arrays first."
	var stories=s.get("stories",{})
	if not stories is Dictionary or not stories.get("chains",{}) is Dictionary:return "119: invalid raw story book."
	var rec=stories.get("chains",{}).get(ID,{})
	if not rec is Dictionary:return "119: invalid main-chain record."
	var stage=rec.get("stage","")
	var required: bool=stage=="passage_work119" or stage in ACCOUNTS.values()
	if not rec.has("work119"):
		for j in s.get("voyageJobs",[]):
			if j is Dictionary and str(j.get("id","")).begins_with("common119:"):return "119: native passage bypassed its disclosed funding admission."
		return "119: missing final undertaking." if required else ""
	var w=rec.work119
	if not P.shape(w,["schema","startedDay","attempts","report","reportDay","finishedDay"]) or not P.number(w.schema,1,1,true) or not P.number(w.startedDay,1,float(s.day)) or not w.attempts is Array or w.attempts.size()>4 or not w.report is String or not rec.get("done") is bool:return "119: invalid raw undertaking types."
	if not prior_ready(s,float(w.startedDay)):return "119: final undertaking predates or lacks the actual completed118 account."
	var chosen: Dictionary=c2(s)
	if chosen.is_empty() or not required or float(w.startedDay)<float(chosen.reportDay):return "119: undertaking lacks the earlier reported funding commitment or its actual opening."
	var ids: Dictionary={}
	var previous: Dictionary={}
	var last: Dictionary={}
	for i in range(w.attempts.size()):
		var a=w.attempts[i]
		var problem: String=_attempt(a,s,float(w.startedDay))
		if not problem.is_empty():return problem
		if a.binding.jobId!="common119:%d"%(i+1) or ids.has(a.binding.jobId):return "119: duplicate or unbound native passage ID."
		ids[a.binding.jobId]=true
		if not previous.is_empty() and (previous.status!="abandoned" or refund_due(previous)!=0 or float(previous.closure.day)>float(a.binding.acceptedDay) or float(previous.repayDay)>float(a.binding.acceptedDay)):return "119: next attempt precedes actual closure and settlement of the earlier fee shares."
		previous=a;last=a
	for j in s.get("voyageJobs",[]):
		if j is Dictionary and str(j.get("id","")).begins_with("common119:") and not ids.has(j.id):return "119: undisclosed native passage admission."
	if w.report=="":
		if stage!="passage_work119" or rec.done or not P.number(w.reportDay,-1,-1) or not P.number(w.finishedDay,-1,-1):return "119: unreported undertaking claims an account or ending."
		return ""
	if not ACCOUNTS.has(w.report) or stage!=ACCOUNTS[w.report] or last.get("status")=="carried":return "119: report disagrees with the account or still-carried job."
	var earliest: float=float(w.startedDay) if last.is_empty() else float(last.closure.day)
	if w.report in ["common","many"]:
		if last.get("status")!="paid" or last.funding.model!=("mutual" if w.report=="common" else "separate") or last.travel.returnDay<0:return "119: paid ending lacks original delivery, model or actual Brass return."
		earliest=float(last.travel.returnDay)
	elif not last.is_empty() and last.status=="paid" and last.travel.returnDay>=0:return "119: incomplete debrief mislabels a completed returned delivery."
	if not P.number(w.reportDay,earliest,float(s.day)):return "119: debrief predates its actual passage outcome."
	if rec.done:
		if not P.number(w.finishedDay,float(w.reportDay),float(s.day)):return "119: finished campaign lacks its explicit final choice date."
	elif not P.number(w.finishedDay,-1,-1):return "119: unfinished account claims an ending date."
	return ""

static func reception(s: Dictionary) -> String:
	var w=s.get("stories",{}).get("chains",{}).get(ID,{}).get("work115",{})
	if w is Dictionary and w.get("binding") is Dictionary and w.get("closure") is Dictionary and W.closed(w.closure,w.binding,w.get("destination"),float(s.get("day",0))) and not w.closure.loss and w.closure.destination==w.destination:
		return "The protected cohort completed reception at Anvil Dock. Their identities remain protected in this account." if w.destination=="anvil_dock" else "The public-testimony cohort completed reception at Reedwater Floats. Their received account remains part of this record."
	return "No completed witness reception is claimed by this account. The earlier cohort record keeps its actual outcome."
