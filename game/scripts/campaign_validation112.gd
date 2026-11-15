extends RefCounted
const V=preload("res://scripts/campaign_validation111.gd")
const Goods=preload("res://scripts/goods.gd")
const TERMINAL: Array=["escaped","arrived","sunk","captured"]

static func validate(s: Dictionary) -> String:
	var rec: Dictionary=s.get("stories",{}).get("chains",{}).get("common_passage110",{})
	if not rec.has("work112"):
		return "Missing Exit Channel report." if str(rec.get("stage","")) in ["wren_account112","useful_enemy113"] else ""
	if not rec.work112 is Dictionary or rec.work112.is_empty() or rec.work112.size()>28:return "Invalid Exit Channel record."
	var w: Dictionary=rec.work112
	for key in ["jobId","ownerId","targetPort"]:
		if not V.text(w.get(key)):return "Invalid Exit Channel passage identity."
	if w.get("fromPort","")!="kelp_reach" or not V.ids(w.get("carrierUids"),48):return "Invalid original Kelp carriers."
	for key in ["voyageSeq","battleFloor","lastSequence","payment","reward"]:
		if not V.number(w.get(key),0,1000000000,true):return "Invalid Exit Channel counter."
	if w.reward<=0 or w.jobId!="escort:%s:%d"%[w.ownerId,int(w.voyageSeq)] or not V.number(w.get("acceptedDay"),1,float(s.get("day",0))):return "Invalid funded passage."
	if float(w.battleFloor)>float(w.lastSequence) or float(w.lastSequence)>float(s.get("battleSeq",0)):return "Invalid encounter freshness."
	if not w.get("lastSource") is String or w.lastSource.length()>160 or ((w.lastSequence==w.battleFloor)!=w.lastSource.is_empty()):return "Invalid latest physical source."
	if not w.get("tradeGood") is String or not Goods.ITEMS.has(w.tradeGood) or not V.number(w.get("tradeQty"),0.000001) or not V.number(w.get("baselineDelivered")) or not V.number(w.get("routeDistance"),160):return "Invalid original passage load."
	for key in ["carrierCargo","crewAtAcceptance","outcomes","closure","arrival"]:
		if not w.get(key) is Dictionary:return "Invalid Exit Channel evidence book."
	if w.carrierCargo.size()!=w.carrierUids.size() or w.crewAtAcceptance.size()!=w.carrierUids.size() or w.outcomes.size()>w.carrierUids.size():return "Carrier books disagree."
	if not w.get("follow") is bool or not w.get("reported") is bool or w.get("status","") not in ["carried","paid","withdrawn"] or w.get("resolution","") not in ["","clear","partial","lost"]:return "Invalid Exit Channel state."
	if (w.status=="paid" and w.payment!=w.reward) or (w.status!="paid" and w.payment!=0):return "Fee disagrees with native closure."
	if w.status=="carried" and not w.closure.is_empty():return "Carried fee already has closure."
	if w.status!="carried":
		var closed: Dictionary=w.closure
		if closed.get("jobId","")!=w.jobId or closed.get("ownerId","")!=w.ownerId or closed.get("status","")!=w.status or not V.number(closed.get("payment"),0,1000000000,true) or float(closed.payment)!=float(w.payment) or not V.number(closed.get("day"),float(w.acceptedDay),float(s.get("day",0))):return "Invalid native fee closure."
	var original: Dictionary={}
	for uid in w.carrierUids:
		var crew=w.crewAtAcceptance.get(uid)
		if not crew is Dictionary or not V.text(crew.get("name")) or not V.number(crew.get("crew"),1) or not V.number(crew.get("wounded"),0,float(crew.crew)):return "Invalid original crew."
		var load=w.carrierCargo.get(uid)
		if not _load(load) or load.is_empty():return "Invalid original loaded carrier."
		for good in load:original[good]=float(original.get(good,0))+float(load[good])
	var arrival_error: String=_arrival(w,s)
	if not arrival_error.is_empty():return arrival_error
	var escaped: int=0
	var arrived: int=0
	var unresolved: int=0
	var sources: Dictionary={}
	var groups: Dictionary={}
	for uid in w.carrierUids:
		if not w.outcomes.has(uid):unresolved+=1;continue
		var row=w.outcomes[uid]
		if not row is Dictionary or row.get("uid","")!=uid or row.get("fate","") not in ["escaped","arrived","sunk","captured","afloat","stranded"]:return "Invalid original carrier fate."
		if row.get("kind","") not in ["encounter","arrival"] or not V.number(row.get("day"),float(w.acceptedDay),float(s.get("day",0))):return "Invalid carrier receipt."
		if not V.number(row.get("crewAlive")) or not V.number(row.get("crewWounded"),0,float(row.crewAlive)) or not row.get("sourceWreckId") is String or row.sourceWreckId.length()>160 or not _load(row.get("cargoAboard")):return "Invalid native crew/cargo observation."
		if row.kind=="arrival":
			var a: Dictionary=w.arrival
			if row.fate!="arrived" or a.is_empty() or not a.carrierUids.has(uid) or not row.cargoAboard.is_empty() or not row.sourceWreckId.is_empty():return "Arrival has no original docking receipt."
			if row.get("source")!=a.source or row.get("sequence")!=a.sequence or float(row.day)!=float(a.day) or float(row.crewAlive)!=float(a.crews[uid].crewAlive) or float(row.crewWounded)!=float(a.crews[uid].crewWounded):return "Arrival differs from its native docking observation."
			if row.get("arrivalMode","")=="paid":
				if w.status!="paid" or a.paidRoute.is_empty() or a.sequence!=0:return "Quiet arrival lacks native paid-route proof."
			elif row.get("arrivalMode","")=="witnessed":
				if not a.witnessed:return "Unwitnessed arrival cannot close a withdrawal."
			elif row.get("arrivalMode","")=="harbor_record":
				if a.get("inspectedAt","")!=w.targetPort or not V.number(a.get("inspectedDay"),float(a.day),float(s.get("day",0))):return "Arrival record was not checked at its destination harbor."
			else:return "Unknown arrival evidence."
			arrived+=1
		else:
			if row.fate=="arrived" or not V.text(row.get("source")) or not V.number(row.get("sequence"),float(w.battleFloor)+1,float(w.lastSequence),true):return "Invalid or stale physical encounter."
			if not groups.has(row.source):groups[row.source]={}
			for good in row.cargoAboard:
				groups[row.source][good]=float(groups[row.source].get(good,0))+float(row.cargoAboard[good])
			if row.fate=="escaped":escaped+=1
			elif row.fate not in TERMINAL:unresolved+=1
		if float(row.sequence)>0:
			if sources.has(row.source) and float(sources[row.source])!=float(row.sequence):return "One physical source has two sequences."
			sources[row.source]=row.sequence
	for uid in w.outcomes:
		if not w.carrierUids.has(uid):return "Outcome belongs to an unrelated hull."
	for source in groups:
		for good in groups[source]:
			var remaining: float=float(original.get(good,0))
			for loss in w.outcomes.values():
				if str(loss.fate) in ["sunk","captured"] and float(loss.sequence)<float(sources[source]):
					remaining-=float(loss.cargoAboard.get(good,0))
			if float(groups[source][good])>remaining+0.000001:return "Physical outcome invented cargo beyond the remaining original load."
	if w.lastSequence>w.battleFloor and (not sources.has(w.lastSource) or float(sources[w.lastSource])!=float(w.lastSequence)):return "Latest source has no carrier evidence."
	if w.reported:
		var expected: String="clear" if escaped+arrived==w.carrierUids.size() else ("partial" if escaped+arrived>0 else "lost")
		if unresolved>0 or w.status=="carried" or w.resolution!=expected or w.follow:return "Reported withdrawal has unresolved boats or fee."
	elif w.resolution!="":return "Unreported withdrawal has a completed resolution."
	if str(rec.get("stage","")) in ["wren_account112","useful_enemy113"] and not w.reported:return "Exit Channel advanced without its explicit report."
	var job: Dictionary={}
	for entry in s.get("voyageJobs",[]):
		if entry is Dictionary and str(entry.get("id",""))==str(w.jobId):job=entry;break
	if w.status=="carried":
		if job.is_empty() or job.get("kind","")!="escort" or job.get("ownerId","")!=w.ownerId or job.get("targetPort","")!=w.targetPort or float(job.get("acceptedDay",-1))!=float(w.acceptedDay) or int(job.get("reward",-1))!=int(w.reward):return "No matching native carried contract."
		var route: Dictionary=job.get("escort",{})
		if route.get("fromPort","")!=w.fromPort or float(route.get("voyageSeq",-1))!=float(w.voyageSeq) or route.get("carrierUids",[])!=w.carrierUids or route.get("carrierCargo",{})!=w.carrierCargo or route.get("tradeGood","")!=w.tradeGood or float(route.get("tradeQty",-1))!=float(w.tradeQty) or float(route.get("baselineDelivered",-1))!=float(w.baselineDelivered) or float(route.get("routeDistance",-1))!=float(w.routeDistance):return "Original route/load disagrees with its native contract."
	elif not job.is_empty():return "Fee is both carried and closed."
	return ""

static func _arrival(w: Dictionary,s: Dictionary) -> String:
	var a: Dictionary=w.arrival
	if a.is_empty():return ""
	if a.get("ownerId","")!=w.ownerId or a.get("fromPort","")!="kelp_reach" or a.get("targetPort","")!=w.targetPort or not V.number(a.get("voyageSeq"),0,1000000000,true) or float(a.voyageSeq)!=float(w.voyageSeq):return "Arrival belongs to another passage."
	if not V.number(a.get("day"),float(w.acceptedDay),float(s.get("day",0))) or not a.get("witnessed") is bool or not a.get("carrierUids") is Array or a.carrierUids.size()>w.carrierUids.size() or not a.get("crews") is Dictionary or a.crews.size()!=a.carrierUids.size():return "Invalid native docking record."
	if a.has("inspectedAt") or a.has("inspectedDay"):
		if a.get("inspectedAt","")!=w.targetPort or not V.number(a.get("inspectedDay"),float(a.day),float(s.get("day",0))):return "Invalid inspected harbor arrival."
	if not V.number(a.get("sequence"),0,float(w.lastSequence),true) or not a.get("source") is String or a.source.length()>160 or not V.number(a.get("deliveredQty")) or not a.get("paidRoute") is Dictionary:return "Invalid arrival evidence."
	if a.sequence==0:
		if not a.source.is_empty():return "Quiet arrival claims a battle source."
	elif float(a.sequence)<=float(w.battleFloor) or a.source.is_empty():return "Arrival refers to a stale encounter."
	var seen: Dictionary={}
	for uid in a.carrierUids:
		if not uid is String or not w.carrierUids.has(uid) or seen.has(uid):return "Invalid original arrival hull."
		seen[uid]=true
		var crew=a.crews.get(uid)
		if not crew is Dictionary or not V.number(crew.get("crewAlive")) or not V.number(crew.get("crewWounded"),0,float(crew.crewAlive)):return "Invalid crew at native docking."
	if not a.paidRoute.is_empty():
		var p: Dictionary=a.paidRoute
		for key in ["accompaniedDistance","playerDistance","routeDistance","deliveredQty"]:
			if not V.number(p.get(key)):return "Invalid native paid-route observation."
		if a.carrierUids!=w.carrierUids or float(p.routeDistance)!=float(w.routeDistance) or float(p.deliveredQty)+0.000001<float(w.tradeQty) or float(p.accompaniedDistance)+40<float(w.routeDistance)*0.8 or float(p.playerDistance)+40<float(w.routeDistance)*0.8:return "Quiet arrival did not complete its native loaded route."
	return ""

static func _load(value) -> bool:
	if not value is Dictionary or value.size()>64:return false
	for good in value:
		if not good is String or not Goods.ITEMS.has(good) or not V.number(value[good]):return false
	return true
