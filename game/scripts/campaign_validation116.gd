extends RefCounted
## Read-only116 preflight. Historical observations are not cargo/people owners.
## Live economy, ship, job and settlement validators keep their own authority.
const Base=preload("res://scripts/campaign_validation111.gd")
const Goods=preload("res://scripts/goods.gd")
const ID: String="common_passage110"
const TERMINAL: Array=["escaped","arrived","sunk","captured"]
const LOSS: Array=["sunk","captured"]

static func number(v,low: float=0,high: float=1000000000,whole: bool=false) -> bool:
	return Base.number(v,low,high,whole)

static func text(v,limit: int=160) -> bool:
	return Base.text(v,limit)

static func valid_load(v) -> bool:
	if not v is Dictionary or v.size()>64:return false
	var seen: Dictionary={}
	for key in v:
		# Native named dictionary assignment may produce StringName keys. JSON
		# restores String keys. Both must retain the same finite commodity rules.
		if not (key is String or key is StringName) or not Goods.ITEMS.has(str(key)) or seen.has(str(key)) or not number(v[key]):return false
		seen[str(key)]=true
	return true

static func totals(manifest: Dictionary) -> Dictionary:
	var out: Dictionary={}
	for aboard in manifest.values():
		if not valid_load(aboard):return {}
		for good in aboard:out[str(good)]=float(out.get(str(good),0))+float(aboard[good])
	return out

static func within(actual: Dictionary,budget: Dictionary) -> bool:
	for good in actual:
		if not number(actual[good]) or not number(budget.get(good)):return false
		if float(actual[good])>float(budget[good])+0.000001:return false
	return true

static func _ids(v,limit: int,empty: bool=false) -> bool:
	return v is Array and ((empty and v.is_empty()) or Base.ids(v,limit))

static func _point(v) -> bool:
	return v is Dictionary and number(v.get("x"),-1000000000) and number(v.get("y"),-1000000000)

static func _fields(v,names: Array,limit: int) -> bool:
	if not v is Dictionary or v.size()>limit:return false
	for key in names:
		if not v.has(key):return false
	return true

static func _manifest(v,ids: Array) -> bool:
	if not v is Dictionary or v.size()!=ids.size():return false
	for uid in ids:
		if not valid_load(v.get(uid)) or v[uid].is_empty():return false
	return true

static func _reports(rows,s: Dictionary) -> bool:
	if not rows is Array or rows.size()>2:return false
	var owners: Dictionary={}
	for r in rows:
		if not _fields(r,["ownerId","name","faction","day","notedDay","targetPort","position","cargoGood","cargoQuantity","currentAtNote"],10):return false
		if not text(r.ownerId) or not text(r.name) or owners.has(r.ownerId) or r.faction!="reed" or not text(r.targetPort):return false
		if not number(r.day,1,float(s.day)) or not number(r.notedDay,float(r.day),float(s.day)) or not _point(r.position) or not r.currentAtNote is bool:return false
		if not r.cargoGood is String or not Goods.ITEMS.has(r.cargoGood) or not number(r.cargoQuantity,0.000001):return false
		owners[r.ownerId]=true
	return true

static func _crew_books(p: Dictionary) -> bool:
	if not p.crewAtAcceptance is Dictionary or p.crewAtAcceptance.size()!=p.carrierUids.size() or not p.capacityAtAcceptance is Dictionary or p.capacityAtAcceptance.size()!=p.carrierUids.size():return false
	for uid in p.carrierUids:
		var crew=p.crewAtAcceptance.get(uid)
		if not crew is Dictionary or not text(crew.get("name")) or not number(crew.get("crew"),1) or not number(crew.get("wounded"),0,float(crew.crew)):return false
		if not number(p.capacityAtAcceptance.get(uid),0.000001):return false
		var weight: float=0.0
		for good in p.carrierCargo[uid]:weight+=float(p.carrierCargo[uid][good])*float(Goods.ITEMS[str(good)].weight)
		if weight>float(p.capacityAtAcceptance[uid])+0.000001:return false
	return true

static func _priority(p,s: Dictionary) -> String:
	if not _fields(p,["jobId","ownerId","fromPort","targetPort","voyageSeq","acceptedDay","battleFloor","carrierUids","carrierCargo","crewAtAcceptance","capacityAtAcceptance","tradeGood","tradeQty","baselineDelivered","routeDistance","reward","policy","status","payment","closure","outcomes","lastSequence","lastSource","arrival"],26):return "Invalid116 priority record."
	for key in ["jobId","ownerId","targetPort"]:
		if not text(p[key]):return "Invalid116 passage identity."
	if p.fromPort!="kelp_reach" or not _ids(p.carrierUids,48):return "Invalid116 original Kelp carriers."
	for key in ["voyageSeq","battleFloor","lastSequence","reward","payment"]:
		if not number(p[key],0,1000000000,true):return "Invalid116 native counter."
	if p.reward<=0 or p.jobId!="escort:%s:%d"%[p.ownerId,int(p.voyageSeq)] or not number(p.acceptedDay,1,float(s.day)):return "Invalid116 accepted native passage."
	if not p.tradeGood is String or not Goods.ITEMS.has(p.tradeGood) or not number(p.tradeQty,0.000001) or not number(p.baselineDelivered) or not number(p.routeDistance,160):return "Invalid116 original trade lot."
	if not _manifest(p.carrierCargo,p.carrierUids) or not _crew_books(p):return "Invalid116 original cargo, crew or hold capacities."
	if float(totals(p.carrierCargo).get(p.tradeGood,0))+0.000001<float(p.tradeQty):return "116 trade lot exceeds its actual original cargo."
	if p.policy not in ["moving","threatened"] or p.status not in ["carried","paid","withdrawn"]:return "Invalid116 priority or native fee status."
	if not p.outcomes is Dictionary or not p.arrival is Dictionary or not p.closure is Dictionary:return "Invalid116 priority evidence books."
	if p.status=="carried":
		if p.payment!=0 or not p.closure.is_empty():return "Carried116 fee already has a closure."
	else:
		var q: Dictionary=p.closure
		if q.get("jobId")!=p.jobId or q.get("ownerId")!=p.ownerId or q.get("status")!=p.status or not number(q.get("day"),float(p.acceptedDay),float(s.day)):return "Invalid116 native fee closure."
		if not number(q.get("payment"),0,1000000000,true) or float(q.payment)!=float(p.payment):return "116 payment differs from native closure."
		if (p.status=="paid" and p.payment!=p.reward) or (p.status=="withdrawn" and p.payment!=0):return "116 fee disagrees with native settlement."
	var job: Dictionary={}
	for entry in s.get("voyageJobs",[]):
		if entry is Dictionary and entry.get("id")==p.jobId:job=entry;break
	if p.status=="carried":
		if job.is_empty() or job.get("kind")!="escort" or job.get("ownerId")!=p.ownerId or job.get("targetPort")!=p.targetPort or not number(job.get("acceptedDay")) or float(job.acceptedDay)!=float(p.acceptedDay) or not number(job.get("reward"),1,1000000000,true) or float(job.reward)!=float(p.reward):return "116 has no matching native carried escort."
		var route: Dictionary=job.get("escort",{})
		if route.get("fromPort")!=p.fromPort or route.get("carrierUids")!=p.carrierUids or route.get("carrierCargo")!=p.carrierCargo or route.get("tradeGood")!=p.tradeGood:return "116 changed its original native carrier binding."
		for key in ["voyageSeq","tradeQty","baselineDelivered","routeDistance"]:
			if not number(route.get(key)) or float(route[key])!=float(p[key]):return "116 changed its original native route/load."
	elif not job.is_empty():return "116 fee is both carried and closed."
	return ""

static func _withdrawal(w: Dictionary,s: Dictionary) -> String:
	var r=w.withdrawal
	var p: Dictionary=w.priority
	if r.is_empty():return ""
	if not _fields(r,["begunDay","battleFloor","policy","carrierUids","carrierCargo","crews","capacity","basis","navalFloor","outcomes","lastSequence","lastSource","arrival"],13):return "Invalid116 withdrawal book."
	if not number(r.begunDay,float(p.acceptedDay),float(s.day)) or not number(r.battleFloor,float(p.lastSequence),float(s.get("battleSeq",0)),true) or r.policy not in ["cover","interdict"]:return "Invalid116 withdrawal start."
	if not _ids(r.carrierUids,48,true) or not _manifest(r.carrierCargo,r.carrierUids) or not r.crews is Dictionary or not r.capacity is Dictionary or r.crews.size()!=r.carrierUids.size() or r.capacity.size()!=r.carrierUids.size():return "Invalid116 surviving carrier snapshot."
	var budget: Dictionary=totals(p.carrierCargo)
	for row in p.outcomes.values():
		if not row is Dictionary or not row.get("cargoAboard") is Dictionary:return "Invalid116 first-operation outcome."
		if str(row.get("fate","")) not in LOSS:continue
		for good in row.cargoAboard:budget[str(good)]=float(budget.get(str(good),0))-float(row.cargoAboard[good])
	if not within(totals(r.carrierCargo),budget):return "116 withdrawal restored original cargo already lost."
	for uid in r.carrierUids:
		if not p.carrierUids.has(uid) or str(p.outcomes.get(uid,{}).get("fate","")) in LOSS:return "116 withdrawal replaced or revived an original hull."
		var crew=r.crews.get(uid)
		if not crew is Dictionary or not number(crew.get("crew"),0,float(p.crewAtAcceptance[uid].crew)) or not number(crew.get("wounded"),0,float(crew.crew)):return "116 withdrawal restored casualties or has invalid crews."
		if not number(r.capacity.get(uid),0.000001,float(p.capacityAtAcceptance[uid])):return "116 withdrawal invented hold capacity."
		var weight: float=0.0
		for good in r.carrierCargo[uid]:weight+=float(r.carrierCargo[uid][good])*float(Goods.ITEMS[str(good)].weight)
		if weight>float(r.capacity[uid])+0.000001:return "116 remaining load exceeds its actual surviving hold."
	if not r.basis is Dictionary or not r.navalFloor is Array or r.navalFloor.size()>24 or not r.outcomes is Dictionary or not r.arrival is Dictionary:return "Invalid116 withdrawal evidence."
	var seen: Dictionary={}
	for id in r.navalFloor:
		if not text(id) or seen.has(id):return "Invalid116 previous NPC event floor."
		seen[id]=true
	var basis: Dictionary=r.basis
	if not _fields(basis,["kind","day","sequence","source","accompaniedDistance","playerDistance"],6) or not number(basis.day,float(p.acceptedDay),float(r.begunDay)) or not number(basis.sequence,0,float(p.lastSequence),true) or not basis.source is String or not number(basis.accompaniedDistance) or not number(basis.playerDistance):return "Invalid116 first-operation evidence."
	match str(basis.kind):
		"encounter":
			if basis.source!=p.lastSource or float(basis.sequence)!=float(p.lastSequence) or float(basis.sequence)<=float(p.battleFloor):return "116 withdrawal has no fresh first encounter."
		"arrival":
			if p.arrival.is_empty() or float(basis.day)!=float(p.arrival.get("day",-1)) or basis.source!=p.arrival.get("source") or basis.sequence!=p.arrival.get("sequence") or not p.outcomes.values().any(func(row):return row is Dictionary and row.get("fate")=="arrived"):return "116 withdrawal has no confirmed first arrival."
		"quiet_leg":
			if basis.sequence!=0 or not basis.source.is_empty() or float(basis.accompaniedDistance)<80 or float(basis.playerDistance)<80:return "116 quiet first leg has no actual accompanied movement."
		_:
			return "Unknown116 first-operation evidence."
	return ""

static func _row(row,p: Dictionary,s: Dictionary) -> bool:
	if not _fields(row,["uid","kind","fate","source","sequence","day","crewAlive","crewWounded","cargoAboard","sourceWreckId"],12):return false
	if not row.uid is String or not p.carrierUids.has(row.uid) or row.kind not in ["encounter","arrival"] or row.fate not in ["escaped","arrived","sunk","captured","afloat","stranded"]:return false
	if not number(row.day,float(p.acceptedDay),float(s.day)) or not number(row.sequence,0,float(s.get("battleSeq",0)),true):return false
	if not row.source is String or row.source.length()>160 or not row.sourceWreckId is String or row.sourceWreckId.length()>160 or not valid_load(row.cargoAboard):return false
	if not number(row.crewAlive,0,float(p.crewAtAcceptance[row.uid].crew)) or not number(row.crewWounded,0,float(row.crewAlive)):return false
	if row.kind=="encounter":return row.fate!="arrived" and text(row.source) and float(row.sequence)>float(p.battleFloor) and (row.fate!="sunk" or float(row.crewAlive)==0)
	return row.fate=="arrived" and row.cargoAboard.is_empty() and row.sourceWreckId.is_empty() and row.get("arrivalMode","") in ["paid","witnessed","harbor_record"]

static func _threat(row,p: Dictionary,s: Dictionary) -> bool:
	if not _fields(row,["ownerId","name","day","position","convoyPosition","origin","orderId"],8):return false
	if not text(row.ownerId) or row.ownerId==p.ownerId or not text(row.name) or not number(row.day,float(p.acceptedDay),float(s.day)) or not _point(row.position) or not _point(row.convoyPosition):return false
	if row.origin not in ["order","encounter"] or not row.orderId is String or row.orderId.length()>160:return false
	if row.origin=="order" and not text(row.orderId):return false
	if row.has("phase") and row.phase not in ["distress","withdrawal"]:return false
	var dx: float=float(row.position.x)-float(row.convoyPosition.x)
	var dy: float=float(row.position.y)-float(row.convoyPosition.y)
	return dx*dx+dy*dy<=1800.0*1800.0+0.000001

static func _encounters(w: Dictionary,s: Dictionary) -> String:
	var p: Dictionary=w.priority
	var seq: int=int(p.battleFloor)
	var sources: Dictionary={}
	var lost: Dictionary={}
	var budget: Dictionary=totals(p.carrierCargo)
	var second_budget: Dictionary=totals(w.withdrawal.get("carrierCargo",{}))
	for e in w.encounters:
		if not _fields(e,["phase","kind","source","sequence","day","enemyId","carriers","proof"],8):return "Invalid116 physical encounter receipt."
		if e.phase not in ["distress","withdrawal"] or e.kind not in ["escort","interdict"] or not text(e.source) or sources.has(e.source) or not number(e.sequence,float(seq)+1,float(s.get("battleSeq",0)),true) or not number(e.day,float(p.acceptedDay),float(s.day)) or not text(e.enemyId) or e.enemyId==p.ownerId:return "Stale, unrelated or duplicate116 encounter."
		if not e.carriers is Array or e.carriers.size()>p.carrierUids.size() or not e.proof is Dictionary:return "Invalid116 encounter projection."
		if e.phase=="withdrawal":
			if w.withdrawal.is_empty() or float(e.sequence)<=float(w.withdrawal.battleFloor) or float(e.day)<float(w.withdrawal.begunDay):return "116 encounter predates its withdrawal binding."
		elif not w.withdrawal.is_empty() and (float(e.sequence)>float(w.withdrawal.battleFloor) or float(e.day)>float(w.withdrawal.begunDay)):return "116 first operation changed after withdrawal began."
		if e.kind=="interdict":
			if e.phase!="withdrawal" or not e.carriers.is_empty() or not _threat(e.proof,p,s) or e.proof.ownerId!=e.enemyId or float(e.proof.day)<float(w.withdrawal.begunDay) or float(e.proof.day)>float(e.day):return "116 interdiction lacks an actual bound pursuer."
			if e.proof.origin=="encounter" and not w.encounters.any(func(prior):return prior is Dictionary and prior.get("kind")=="escort" and prior.get("enemyId")==e.enemyId and number(prior.get("sequence"),float(p.battleFloor)+1,float(e.sequence)-1,true)):return "116 pursued enemy has no earlier matching physical escort."
		else:
			if e.carriers.is_empty() or not e.proof.is_empty():return "116 escort has no original carrier projection."
			var seen: Dictionary={}
			var loads: Dictionary={}
			for row in e.carriers:
				if not _row(row,p,s) or row.kind!="encounter" or row.source!=e.source or float(row.sequence)!=float(e.sequence) or float(row.day)!=float(e.day) or seen.has(row.uid) or lost.has(row.uid):return "116 carrier evidence is duplicated, revived or unrelated."
				if e.phase=="withdrawal" and not w.withdrawal.carrierUids.has(row.uid):return "116 encounter replaced a withdrawal survivor."
				seen[row.uid]=true;loads[row.uid]=row.cargoAboard
			if not within(totals(loads),budget) or (e.phase=="withdrawal" and not within(totals(loads),second_budget)):return "116 encounter invented cargo beyond the remaining original load."
			for row in e.carriers:
				if row.fate not in LOSS:continue
				lost[row.uid]=row
				for good in row.cargoAboard:
					budget[str(good)]=float(budget.get(str(good),0))-float(row.cargoAboard[good])
					if e.phase=="withdrawal":second_budget[str(good)]=float(second_budget.get(str(good),0))-float(row.cargoAboard[good])
		seq=int(e.sequence);sources[e.source]=true
	return ""

static func _arrival(a,p: Dictionary,s: Dictionary) -> String:
	if not a is Dictionary:return "Invalid116 arrival book."
	if a.is_empty():return ""
	if not _fields(a,["ownerId","fromPort","targetPort","voyageSeq","day","carrierUids","crews","witnessed","sequence","source","deliveredQty","paidRoute"],14):return "Invalid116 native arrival."
	if a.ownerId!=p.ownerId or a.fromPort!=p.fromPort or a.targetPort!=p.targetPort or not number(a.voyageSeq,0,1000000000,true) or float(a.voyageSeq)!=float(p.voyageSeq):return "116 arrival belongs to a different passage."
	if not number(a.day,float(p.acceptedDay),float(s.day)) or not _ids(a.carrierUids,48,true) or not a.crews is Dictionary or a.crews.size()!=a.carrierUids.size() or not a.witnessed is bool:return "Invalid116 actual arriving crews."
	if not number(a.sequence,0,float(s.get("battleSeq",0)),true) or not a.source is String or a.source.length()>160 or not number(a.deliveredQty) or not a.paidRoute is Dictionary:return "Invalid116 delivery evidence."
	if (a.sequence==0 and not a.source.is_empty()) or (a.sequence>0 and (not text(a.source) or float(a.sequence)<=float(p.battleFloor))):return "116 arrival has invalid physical provenance."
	for uid in a.carrierUids:
		var crew=a.crews.get(uid)
		if not p.carrierUids.has(uid) or not crew is Dictionary or not number(crew.get("crewAlive"),0,float(p.crewAtAcceptance[uid].crew)) or not number(crew.get("crewWounded"),0,float(crew.crewAlive)):return "116 arrival replaced or restored an original crew."
	if a.has("inspectedAt") or a.has("inspectedDay"):
		if a.get("inspectedAt")!=p.targetPort or not number(a.get("inspectedDay"),float(a.day),float(s.day)):return "116 harbor record was not checked at its actual destination."
	if not a.paidRoute.is_empty():
		var route: Dictionary=a.paidRoute
		for key in ["accompaniedDistance","playerDistance","routeDistance","deliveredQty"]:
			if not number(route.get(key)):return "Invalid116 paid native route observation."
		if p.status!="paid" or a.carrierUids!=p.carrierUids or float(route.routeDistance)!=float(p.routeDistance) or float(route.deliveredQty)+0.000001<float(p.tradeQty) or float(a.deliveredQty)+0.000001<float(p.tradeQty) or float(route.accompaniedDistance)+40<float(p.routeDistance)*0.8 or float(route.playerDistance)+40<float(p.routeDistance)*0.8:return "116 quiet fee did not complete its original loaded route."
	return ""

static func _book(b: Dictionary,p: Dictionary,w: Dictionary,s: Dictionary,phase: String) -> String:
	if b.outcomes.size()>p.carrierUids.size() or not number(b.get("lastSequence"),float(b.battleFloor),float(s.get("battleSeq",0)),true) or not b.get("lastSource") is String or b.lastSource.length()>160:return "Invalid116 phase sequence book."
	var latest: Dictionary={}
	for e in w.encounters:
		if e.phase==phase:latest=e
	if latest.is_empty():
		if float(b.lastSequence)!=float(b.battleFloor) or not b.lastSource.is_empty():return "116 latest encounter has no native receipt."
	elif float(b.lastSequence)!=float(latest.sequence) or b.lastSource!=latest.source:return "116 latest encounter differs from its native receipt."
	var arrival_error: String=_arrival(b.arrival,p,s)
	if not arrival_error.is_empty():return arrival_error
	if not b.arrival.is_empty() and float(b.arrival.sequence)>0:
		if not w.encounters.any(func(e):return e.source==b.arrival.source and float(e.sequence)==float(b.arrival.sequence) and float(e.day)<=float(b.arrival.day)):return "116 arrival claims an unrelated physical source."
	for uid in b.outcomes:
		var row=b.outcomes[uid]
		if not _row(row,p,s) or str(row.uid)!=str(uid):return "Invalid116 original carrier fate."
		if row.kind=="arrival":
			var a: Dictionary=b.arrival
			if a.is_empty() or not a.carrierUids.has(uid) or row.source!=a.source or float(row.sequence)!=float(a.sequence) or float(row.day)!=float(a.day) or float(row.crewAlive)!=float(a.crews[uid].crewAlive) or float(row.crewWounded)!=float(a.crews[uid].crewWounded):return "116 arriving carrier has no matching original docking."
			if row.arrivalMode=="witnessed" and not a.witnessed:return "116 arrival was not witnessed."
			if row.arrivalMode=="harbor_record" and a.get("inspectedAt")!=p.targetPort:return "116 arrival record was not inspected."
			if row.arrivalMode=="paid" and (p.status!="paid" or a.paidRoute.is_empty()):return "116 quiet arrival lacks native paid-route proof."
		else:
			var linked: bool=false
			for e in w.encounters:
				if e.phase==phase and e.kind=="escort" and e.source==row.source and e.carriers.has(row):linked=true;break
			if not linked and phase=="withdrawal":linked=row.fate in LOSS and p.outcomes.get(uid,{})==row
			if not linked:return "116 carrier fate has no matching phase receipt."
	if phase=="withdrawal":
		for uid in p.outcomes:
			if p.outcomes[uid].fate in LOSS and b.outcomes.get(uid,{})!=p.outcomes[uid]:return "116 withdrawal erased a confirmed original loss."
	return ""

static func _aid(w: Dictionary,s: Dictionary) -> String:
	var p: Dictionary=w.priority
	if w.withdrawal.is_empty():return "116 aid predates withdrawal." if not w.aid.is_empty() else ""
	var seen: Dictionary={}
	for row in w.aid:
		if not _fields(row,["id","day","wardenId","wardenUids","pursuerId","threat","event"],7):return "Invalid116 warden receipt."
		if not text(row.id) or seen.has(row.id) or w.withdrawal.navalFloor.has(row.id) or not number(row.day,float(w.withdrawal.begunDay),float(s.day)) or row.wardenId not in ["patrol-2","patrol-8"] or not _ids(row.wardenUids,48) or not text(row.pursuerId):return "116 assistance has no new finite native warden."
		if not _threat(row.threat,p,s) or row.threat.get("phase")!="withdrawal" or row.threat.ownerId!=row.pursuerId or float(row.threat.day)<float(w.withdrawal.begunDay) or float(row.threat.day)>float(row.day) or float(row.day)-float(row.threat.day)>0.25:return "116 warden aid has no matching dated pursuer."
		var e=row.event
		if not e is Dictionary or not e.get("witnessed",false) is bool or e.get("witnessed")!=true or not number(e.get("day"),1,float(s.get("econDay",s.day)),true) or int(e.day)!=int(row.day):return "116 warden event was not newly witnessed."
		if row.id!="naval:%d:%s:%s"%[int(e.day),str(e.get("a","")),str(e.get("b",""))]:return "116 warden event identity disagrees."
		var side: String="A" if e.get("a")==row.wardenId and e.get("b")==row.pursuerId else ("B" if e.get("b")==row.wardenId and e.get("a")==row.pursuerId else "")
		if side.is_empty() or not number(e.get("shots"+side),1,1000000000,true) or (e.get("winner")!=row.wardenId and e.get("retreated")!=row.pursuerId):return "116 wardens supplied no actual matching armed interruption."
		seen[row.id]=true
	return ""

static func validate(s: Dictionary) -> String:
	if not number(s.get("day"),1):return "Invalid116 campaign calendar."
	var stories=s.get("stories",{})
	if not stories is Dictionary or not stories.get("chains",{}) is Dictionary:return "Invalid116 story book."
	var rec=stories.get("chains",{}).get(ID,{})
	if not rec is Dictionary:return "Invalid116 campaign record."
	if not rec.has("work116"):return "Missing116 original passage account." if rec.get("stage","") in ["narrow_withdrawal116","distress_account116"] else ""
	var raw=rec.work116
	if not _fields(raw,["schema","phase","reports","priority","withdrawal","encounters","threats","aid","follow","reported","resolution"],11):return "Invalid116 bounded work record."
	var w: Dictionary=raw
	if not number(w.schema,1,1,true) or w.phase not in ["unfilled","distress","withdrawal","reported"] or not w.follow is bool or not w.reported is bool or not w.resolution is String:return "Invalid116 work state."
	if not _reports(w.reports,s) or not w.priority is Dictionary or not w.withdrawal is Dictionary or not w.encounters is Array or w.encounters.size()>48 or not w.threats is Dictionary or w.threats.size()>16 or not w.aid is Array or w.aid.size()>8:return "Invalid116 bounded evidence books."
	if w.priority.is_empty():
		if w.phase!="unfilled" or not w.withdrawal.is_empty() or not w.encounters.is_empty() or not w.threats.is_empty() or not w.aid.is_empty() or w.follow or w.reported or not w.resolution.is_empty() or rec.get("stage","") in ["narrow_withdrawal116","distress_account116"]:return "Unfilled116 sources cannot prove a mission."
		return ""
	var p: Dictionary=w.priority
	var error: String=_priority(p,s)
	if not error.is_empty():return error
	for uid in p.outcomes:
		if not _row(p.outcomes[uid],p,s) or str(p.outcomes[uid].uid)!=str(uid):return "Invalid116 first-operation carrier outcome."
	if w.reports.size()!=2 or not w.reports.any(func(row):return row.ownerId==p.ownerId):return "116 priority lacks two distinct dated source reports."
	for row in w.reports:
		if float(row.notedDay)>float(p.acceptedDay):return "116 changed its reports after choosing the original passage."
	if w.phase=="unfilled" or (w.phase=="distress" and not w.withdrawal.is_empty()) or (w.phase in ["withdrawal","reported"] and w.withdrawal.is_empty()):return "116 phase disagrees with its original survivor binding."
	error=_withdrawal(w,s)
	if not error.is_empty():return error
	error=_encounters(w,s)
	if not error.is_empty():return error
	error=_book(p,p,w,s,"distress")
	if not error.is_empty():return error
	if not w.withdrawal.is_empty():
		error=_book(w.withdrawal,p,w,s,"withdrawal")
		if not error.is_empty():return error
	for id in w.threats:
		var row=w.threats[id]
		if not _threat(row,p,s) or row.ownerId!=str(id) or not row.has("phase"):return "Invalid116 observed pursuer book."
	error=_aid(w,s)
	if not error.is_empty():return error
	var b: Dictionary=p if w.withdrawal.is_empty() else w.withdrawal
	var clear: int=0
	var unresolved: int=0
	for uid in p.carrierUids:
		var fate: String=str(b.outcomes.get(uid,{}).get("fate",""))
		if fate in ["escaped","arrived"]:clear+=1
		elif fate not in LOSS:unresolved+=1
	if w.reported:
		var expected: String="unconfirmed" if unresolved>0 else ("clear" if clear==p.carrierUids.size() else ("partial" if clear>0 else "lost"))
		if w.phase!="reported" or w.resolution!=expected or p.status=="carried" or w.follow:return "116 report disagrees with physical outcomes or native fee closure."
	elif w.phase=="reported" or not w.resolution.is_empty():return "Unreported116 work claims a completed outcome."
	if rec.get("stage","")=="narrow_withdrawal116" and w.withdrawal.is_empty():return "116 advanced without its real survivor snapshot."
	if rec.get("stage","")=="distress_account116" and not w.reported:return "116 advanced without its explicit honest report."
	return ""
