extends RefCounted
## Source relay only. Native jobs, owners, movement and settlement own all
## people, goods, damage and money. Existing112 is never changed or borrowed
## as mutable storage. See relay/API.json for the integration boundary.
const V=preload("res://scripts/campaign_validation116.gd")
const ID: String="common_passage110"
const DISTRESS: String="two_distress116"
const WITHDRAWAL: String="narrow_withdrawal116"
const ACCOUNT: String="distress_account116"
const TERMINAL: Array=["escaped","arrived","sunk","captured"]
const LOSS: Array=["sunk","captured"]

static func record(c) -> Dictionary:
	return c.state.get("stories",{}).get("chains",{}).get(ID,{})

static func work(c) -> Dictionary:
	return record(c).get("work116",{})

static func _open(c) -> bool:
	return str(record(c).get("stage","")) in [DISTRESS,WITHDRAWAL] and not work(c).get("reported",false)

static func _ensure(c) -> Dictionary:
	var rec: Dictionary=record(c)
	if rec.is_empty():return {}
	if not rec.has("work116"):
		rec.work116={"schema":1,"phase":"unfilled","reports":[],"priority":{},"withdrawal":{},"encounters":[],"threats":{},"aid":[],"follow":false,"reported":false,"resolution":""}
	return rec.work116

static func _priority(c) -> Dictionary:
	return work(c).get("priority",{})

static func _book(c) -> Dictionary:
	var w: Dictionary=work(c)
	return w.get("withdrawal",{}) if not w.get("withdrawal",{}).is_empty() else w.get("priority",{})

static func reports(c) -> Array:
	var out: Array=[]
	if not _open(c):return out
	# These are the lookout's dated payloads. Do not refresh an unseen owner's
	# route, manifest, hulls or purse by consulting its present world record.
	for sight in c.NavalAI.sightings(c.state):
		if str(sight.get("kind",""))!="trader" or str(sight.get("faction",""))!="reed" or not sight.get("loaded",false):continue
		if not V.text(sight.get("ownerId")) or not V.text(sight.get("destination")) or not V.number(sight.get("day"),1,float(c.state.day)):continue
		if not V.text(sight.get("cargoGood")) or not V.number(sight.get("cargoQuantity"),0.000001):continue
		out.append({"ownerId":str(sight.ownerId),"name":str(sight.get("name",sight.ownerId)),"faction":"reed","day":float(sight.day),"notedDay":float(c.state.day),"targetPort":str(sight.destination),"position":{"x":float(sight.x),"y":float(sight.y)},"cargoGood":str(sight.cargoGood),"cargoQuantity":float(sight.cargoQuantity),"currentAtNote":bool(sight.get("current",false))})
	out.sort_custom(func(a,b):return str(a.ownerId)<str(b.ownerId))
	return out

static func note_report(c,owner_id: String) -> Dictionary:
	if str(record(c).get("stage",""))!=DISTRESS or not _priority(c).is_empty():return c.fail("The two reports are fixed after choosing the priority passage.")
	var selected: Dictionary={}
	for row in reports(c):
		if row.ownerId==owner_id:selected=row;break
	if selected.is_empty():return c.fail("No dated loaded Reed convoy report is available. Refresh Coastal watch when a real convoy is sighted.")
	var w: Dictionary=_ensure(c)
	if w.is_empty():return c.fail("The campaign record is unavailable.")
	for i in range(w.reports.size()):
		if str(w.reports[i].ownerId)==owner_id:w.reports[i]=selected.duplicate(true);return c.ok("Updated this dated convoy report; its unseen outcome is still unknown.")
	if w.reports.size()>=2:return c.fail("Two distinct reports are already noted. Approach one of those owners to choose its actual passage.")
	w.reports.append(selected.duplicate(true))
	return c.ok("Noted the dated convoy report. This records a sighting, not an escape, delivery or loss.")

static func offers(c) -> Array:
	var out: Array=[]
	if str(record(c).get("stage",""))!=DISTRESS or not _priority(c).is_empty():return out
	for sight in c.NavalAI.sightings(c.state):
		if not sight.get("current",false) or str(sight.get("faction",""))!="reed":continue
		var offer: Dictionary=c.EscortOps.offer(c,str(sight.get("ownerId","")))
		if not offer.is_empty() and str(offer.escort.get("fromPort",""))=="kelp_reach":out.append(offer.duplicate(true))
	out.sort_custom(func(a,b):return str(a.id)<str(b.id))
	return out

static func accept_priority(c,terms: Dictionary,policy: String="moving") -> Dictionary:
	if policy not in ["moving","threatened"]:return c.fail("Choose the moving boats or the currently threatened passage.")
	var w: Dictionary=work(c)
	if w.is_empty() or w.reports.size()!=2 or not w.priority.is_empty():return c.fail("Note two distinct native convoy reports before choosing one actual priority passage.")
	var shown: Dictionary={}
	for offer in offers(c):
		if str(offer.id)==str(terms.get("id","")) and str(offer.ownerId)==str(terms.get("ownerId","")) and int(offer.reward)==int(terms.get("reward",-1)) and str(offer.targetPort)==str(terms.get("targetPort","")) and offer.escort==terms.get("escort",{}):shown=offer;break
	if shown.is_empty():return c.fail("Approach the chosen owner within 600, hail it and review its fresh loaded passage and fee.")
	if not w.reports.any(func(row):return str(row.ownerId)==str(shown.ownerId)):return c.fail("Choose an owner from the two noted reports.")
	var fresh_report: Dictionary={}
	for row in reports(c):
		if row.ownerId==str(shown.ownerId) and row.targetPort==str(shown.targetPort) and row.cargoGood==str(shown.escort.tradeGood):fresh_report=row;break
	if fresh_report.is_empty():return c.fail("Refresh this chosen owner's native sighting before accepting its changed passage.")
	var owner: Dictionary=c.fleet_owner(str(shown.ownerId))
	if policy=="threatened" and c.EscortOps.threat(c,owner).is_empty():return c.fail("No actual armed threat to this passage is currently observed. The moving-boats priority remains available.")
	var crews: Dictionary={}
	var capacity: Dictionary={}
	for uid in shown.escort.carrierUids:
		for boat in owner.boats:
			if str(boat.uid)==str(uid):
				crews[str(uid)]={"name":str(boat.name),"crew":float(boat.crew),"wounded":float(boat.wounded)}
				capacity[str(uid)]=float(boat.spec.get("cargo",0))
				break
	if crews.size()!=shown.escort.carrierUids.size():return c.fail("The original loaded carriers are unavailable.")
	var result: Dictionary=c.VoyageJobs.accept_escort(c,str(shown.ownerId),int(shown.reward))
	if not result.get("ok",false):return result
	# accept_escort appends this exact native job before returning success.
	var job: Dictionary=c.VoyageJobs._find(c.state,str(shown.id))
	w.priority={"jobId":str(job.id),"ownerId":str(job.ownerId),"fromPort":str(job.escort.fromPort),"targetPort":str(job.targetPort),"voyageSeq":int(job.escort.voyageSeq),"acceptedDay":float(job.acceptedDay),"battleFloor":int(c.state.get("battleSeq",0)),"carrierUids":job.escort.carrierUids.duplicate(),"carrierCargo":job.escort.carrierCargo.duplicate(true),"crewAtAcceptance":crews,"capacityAtAcceptance":capacity,"tradeGood":str(job.escort.tradeGood),"tradeQty":float(job.escort.tradeQty),"baselineDelivered":float(job.escort.baselineDelivered),"routeDistance":float(job.escort.routeDistance),"reward":int(job.reward),"policy":policy,"status":"carried","payment":0,"closure":{},"outcomes":{},"lastSequence":int(c.state.get("battleSeq",0)),"lastSource":"","arrival":{}}
	w.phase="distress"
	# Refresh only the selected report from the actual hailed native sighting.
	for row in reports(c):
		if row.ownerId!=str(job.ownerId):continue
		for i in range(w.reports.size()):
			if w.reports[i].ownerId==row.ownerId:w.reports[i]=row.duplicate(true)
	c.log_entry("Two Distress Flags: chose one actual loaded passage. The other convoy remains a dated report, with no claimed rescue or loss.")
	return result

static func same_passage(c) -> bool:
	var p: Dictionary=_priority(c)
	if p.is_empty() or not c.home_local064() or c.NavalAI.NavalOrders.enrolled066(c.state,str(p.ownerId)):return false
	var patrol: Dictionary=c.NavalAI._find_patrol(c.state,str(p.ownerId))
	var owner: Dictionary=c.fleet_owner(str(p.ownerId))
	return not owner.is_empty() and owner.get("active",false) and not patrol.is_empty() and patrol.get("active",false) and not patrol.get("holding",false) and int(patrol.get("voyageSeq",0))==int(p.voyageSeq) and str(patrol.get("from",""))==str(p.fromPort) and str(patrol.get("to",""))==str(p.targetPort)

static func delivery_pending(c) -> bool:
	var p: Dictionary=_priority(c)
	if p.is_empty() or p.status!="carried":return false
	var job: Dictionary=c.VoyageJobs._find(c.state,str(p.jobId))
	return not job.is_empty() and job.get("state","")=="active" and not job.get("failed",false) and not job.get("escort",{}).get("arrived",false)

static func _budget(c) -> Dictionary:
	var p: Dictionary=_priority(c)
	var b: Dictionary=_book(c)
	var loads: Dictionary=p.get("carrierCargo",{}) if work(c).get("withdrawal",{}).is_empty() else b.get("carrierCargo",{})
	var budget: Dictionary=V.totals(loads)
	for row in b.get("outcomes",{}).values():
		if str(row.get("fate","")) not in LOSS or not loads.has(str(row.uid)):continue
		for good in row.cargoAboard:budget[good]=float(budget.get(good,0))-float(row.cargoAboard[good])
	return budget

static func _load(c) -> Dictionary:
	var p: Dictionary=_priority(c)
	if p.is_empty() or not same_passage(c):return {"ok":false,"message":"The original passage is not continuing on this coastal route."}
	var plan: Dictionary=c.EscortOps._load_plan(c,c.fleet_owner(str(p.ownerId)))
	if not plan.get("ok",false):return plan
	var b: Dictionary=_book(c)
	var allowed: Array=p.carrierUids if work(c).withdrawal.is_empty() else b.carrierUids
	var loads: Dictionary={}
	for uid in plan.carrierUids:
		if not allowed.has(str(uid)) or str(b.outcomes.get(str(uid),{}).get("fate","")) in LOSS:return {"ok":false,"message":"A replacement or previously lost hull cannot join the original load."}
		loads[str(uid)]=plan.carrierCargo[uid]
	if not V.within(V.totals(loads),_budget(c)):return {"ok":false,"message":"This load exceeds the remaining original cargo; no replenished or delivered lot may replace it."}
	return plan

static func counts(c) -> Dictionary:
	var out: Dictionary={"escaped":0,"arrived":0,"sunk":0,"captured":0,"unresolved":0}
	var p: Dictionary=_priority(c)
	var b: Dictionary=_book(c)
	for uid in p.get("carrierUids",[]):
		var fate: String=str(b.get("outcomes",{}).get(uid,{}).get("fate",""))
		var key: String=fate if fate in TERMINAL else "unresolved"
		out[key]=int(out[key])+1
	return out

static func _basis(c) -> Dictionary:
	var p: Dictionary=_priority(c)
	if p.is_empty():return {}
	if int(p.lastSequence)>int(p.battleFloor):return {"kind":"encounter","day":float(c.state.day),"sequence":int(p.lastSequence),"source":str(p.lastSource),"accompaniedDistance":0.0,"playerDistance":0.0}
	if not p.arrival.is_empty() and p.outcomes.values().any(func(row):return str(row.get("fate",""))=="arrived"):
		return {"kind":"arrival","day":float(p.arrival.day),"sequence":int(p.arrival.sequence),"source":str(p.arrival.source),"accompaniedDistance":0.0,"playerDistance":0.0}
	var job: Dictionary=c.VoyageJobs._find(c.state,str(p.jobId))
	if not same_passage(c) or job.is_empty() or job.get("failed",false) or job.get("state","")!="active":return {}
	var route: Dictionary=job.get("escort",{})
	var owner: Dictionary=c.fleet_owner(str(p.ownerId))
	if not c.EscortOps.threat(c,owner).is_empty() or float(route.get("accompaniedDistance",0))<80 or float(route.get("playerDistance",0))<80:return {}
	if int(route.get("interceptions",0))!=0:return {}
	return {"kind":"quiet_leg","day":float(c.state.day),"sequence":0,"source":"","accompaniedDistance":float(route.accompaniedDistance),"playerDistance":float(route.playerDistance)}

static func _withdraw_ready(c) -> Dictionary:
	var w: Dictionary=work(c)
	if w.is_empty() or w.priority.is_empty() or w.reported:return c.fail("Choose and accompany an actual loaded priority passage first.")
	if not w.withdrawal.is_empty():return c.ok("")
	if _basis(c).is_empty():return c.fail("The first operation needs an actual settled encounter, confirmed native arrival, or a quiet accompanied leg. A priority choice alone proves no rescue.")
	if not c.travel_lock064.is_empty():return c.fail("Settle the physical encounter before planning the withdrawal.")
	if same_passage(c):
		var patrol: Dictionary=c.NavalAI._find_patrol(c.state,str(w.priority.ownerId))
		if c.distance(c.state.position,patrol)>c.EscortOps.CONTRACT_RADIUS:return c.fail("Approach the original surviving boats within 600 before recording the remaining load.")
		var plan: Dictionary=_load(c)
		if not plan.get("ok",false):return c.fail(str(plan.message))
		var p: Dictionary=w.priority
		var owner: Dictionary=c.fleet_owner(str(p.ownerId))
		for uid in plan.carrierUids:
			for boat in owner.boats:
				if str(boat.uid)!=str(uid):continue
				if not V.number(boat.crew,0,float(p.crewAtAcceptance[str(uid)].crew)) or not V.number(boat.wounded,0,float(boat.crew)) or not V.number(boat.spec.get("cargo"),0.000001,float(p.capacityAtAcceptance[str(uid)])):return c.fail("The remaining original crew or hold no longer matches this bound passage. No casualty or capacity reset will be recorded.")
	elif counts(c).unresolved>0:
		return c.fail("The original voyage is unavailable and some boats remain unconfirmed. Reacquire it or inspect its actual destination arrival record; no replacement passage will be created.")
	return c.ok("")

static func begin_withdrawal(c,policy: String="cover") -> Dictionary:
	if policy not in ["cover","interdict"]:return c.fail("Choose withdrawal cover or actual-pursuer interdiction.")
	if str(record(c).get("stage","")) not in [DISTRESS,WITHDRAWAL]:return c.fail("This campaign is not planning the withdrawal.")
	var ready: Dictionary=_withdraw_ready(c)
	if not ready.ok:return ready
	var w: Dictionary=work(c)
	if not w.withdrawal.is_empty():return c.ok("The original withdrawal is already bound; no load or crew was reset.")
	var p: Dictionary=w.priority
	var uids: Array=[]
	var cargo: Dictionary={}
	var crews: Dictionary={}
	var capacity: Dictionary={}
	if same_passage(c):
		var plan: Dictionary=_load(c)
		var owner: Dictionary=c.fleet_owner(str(p.ownerId))
		for uid in plan.carrierUids:
			uids.append(str(uid));cargo[str(uid)]=plan.carrierCargo[uid].duplicate(true)
			for boat in owner.boats:
				if str(boat.uid)==str(uid):
					crews[str(uid)]={"crew":float(boat.crew),"wounded":float(boat.wounded)}
					capacity[str(uid)]=float(boat.spec.get("cargo",0))
					break
	var outcomes: Dictionary={}
	for uid in p.outcomes:
		if str(p.outcomes[uid].fate) in LOSS or str(p.outcomes[uid].fate)=="arrived":outcomes[uid]=p.outcomes[uid].duplicate(true)
	var floor_events: Array=[]
	for event in c.state.get("navalAi",{}).get("encounters",[]):floor_events.append(_naval_id(event))
	w.withdrawal={"begunDay":float(c.state.day),"battleFloor":int(c.state.get("battleSeq",0)),"policy":policy,"carrierUids":uids,"carrierCargo":cargo,"crews":crews,"capacity":capacity,"basis":_basis(c),"navalFloor":floor_events,"outcomes":outcomes,"lastSequence":int(c.state.get("battleSeq",0)),"lastSource":"","arrival":{}}
	# A confirmed prior arrival is evidence of arrival, never a new cargo load.
	if not p.arrival.is_empty() and outcomes.values().any(func(row):return row.fate=="arrived"):w.withdrawal.arrival=p.arrival.duplicate(true)
	w.phase="withdrawal";w.follow=false
	_remember(c,pursuers(c))
	c.log_entry("Narrow Withdrawal: retained only the actual original survivors and remaining load. Earlier losses remain lost; an earlier battle exit does not prove this next withdrawal.")
	return c.ok("The withdrawal is bound to the original remaining boats and cargo. No new fee, crew, hull or load was supplied.")

static func protection_gate(c) -> Dictionary:
	if not _open(c) or _priority(c).is_empty() or not c.travel_lock064.is_empty():return c.fail("No settled original passage is available to cover.")
	if counts(c).unresolved==0 and not delivery_pending(c):return c.fail("No remaining loaded delivery or unresolved original boat needs cover.")
	var plan: Dictionary=_load(c)
	if not plan.get("ok",false):return c.fail(str(plan.message))
	var p: Dictionary=_priority(c)
	var patrol: Dictionary=c.NavalAI._find_patrol(c.state,str(p.ownerId))
	if not _current(c,str(p.ownerId)) or c.distance(c.state.position,patrol)>c.EscortOps.CONTRACT_RADIUS:return c.fail("Hail the chosen original passage within 600 before covering it.")
	if c.state.get("escortEvents",{}).has(str(p.jobId)):return c.fail("This voyage already has native rescue credit. Keep following its actual delivery or interdict a reachable actual pursuer; rescue credit cannot be replayed.")
	var owner: Dictionary=c.fleet_owner(str(p.ownerId))
	if c.EscortOps.threat(c,owner).is_empty():return c.fail("No actual nearby armed threat is available. Continue the quiet withdrawal to its actual arrival.")
	var job: Dictionary=c.VoyageJobs._find(c.state,str(p.jobId))
	if not job.is_empty() and job.get("state","")=="active" and (job.get("failed",false) or plan.carrierUids!=job.escort.carrierUids):return c.fail("Close the failed native fee before a voluntary rescue of its surviving original boats.")
	return c.ok("")

static func cover(host) -> Dictionary:
	host.sync_economy()
	var c=host.core
	var permission: Dictionary=protection_gate(c)
	if not permission.ok:return permission
	_remember(c,pursuers(c))
	c.EscortOps.start(host,str(_priority(c).ownerId))
	if host.mode!="battle" or host.battle_context.get("allyOwnerId")!=_priority(c).ownerId:return c.fail("The native escort could not begin; no chapter result was recorded.")
	if not work(c).withdrawal.is_empty():work(c).withdrawal.policy="cover"
	return c.ok("Covering the actual original loaded carriers through the native physical encounter.")

static func _current(c,owner_id: String) -> bool:
	if not c.home_local064():return false
	for sight in c.NavalAI.sightings(c.state):
		if str(sight.get("ownerId",""))==owner_id and sight.get("current",false):return true
	return false

static func pursuers(c) -> Array:
	var out: Array=[]
	var p: Dictionary=_priority(c)
	if not _open(c) or p.is_empty() or not same_passage(c):return out
	var convoy: Dictionary=c.NavalAI._find_patrol(c.state,str(p.ownerId))
	if c.distance(c.state.position,convoy)>1800:return out
	var own: Dictionary=c.fleet_owner(str(p.ownerId))
	for sight in c.NavalAI.sightings(c.state):
		if not sight.get("current",false):continue
		var id: String=str(sight.get("ownerId",""))
		var enemy: Dictionary=c.fleet_owner(id)
		var patrol: Dictionary=c.NavalAI._find_patrol(c.state,id)
		if enemy.is_empty() or patrol.is_empty() or not enemy.get("active",false) or not patrol.get("active",false) or patrol.get("hidden",false) or c.NavalAI.NavalOrders.enrolled066(c.state,id):continue
		if not c.Politics.hostile(c,enemy) or c.Factions.relation(c.state,str(own.faction),str(enemy.faction))>-20:continue
		if not enemy.boats.any(func(b):return not b.get("sunk",false) and not b.get("captureSecured",false) and float(b.get("ammo",0))>0 and float(b.crew)>=float(b.crewMin)):continue
		if c.distance(patrol,convoy)>1800 or c.distance(c.state.position,patrol)>1800:continue
		var order: Dictionary=enemy.get("order",{})
		var targeted: bool=str(order.get("targetOwnerId",""))==str(p.ownerId) and str(order.get("purpose","")) in ["raid","intercept"]
		var encountered: bool=work(c).encounters.any(func(row):return row.kind=="escort" and row.enemyId==id)
		if not targeted and not encountered:continue
		out.append({"ownerId":id,"name":str(enemy.name),"day":float(c.state.day),"position":{"x":float(patrol.x),"y":float(patrol.y)},"convoyPosition":{"x":float(convoy.x),"y":float(convoy.y)},"origin":"order" if targeted else "encounter","orderId":str(order.get("id",""))})
	out.sort_custom(func(a,b):return str(a.ownerId)<str(b.ownerId))
	return out

static func _remember(c,rows: Array) -> void:
	var w: Dictionary=work(c)
	for row in rows:
		if not w.threats.has(row.ownerId) and w.threats.size()>=16:continue
		var saved: Dictionary=row.duplicate(true);saved.phase=str(w.phase)
		w.threats[row.ownerId]=saved

static func interdict(host,owner_id: String) -> Dictionary:
	host.sync_economy()
	var c=host.core
	if not _open(c) or work(c).get("withdrawal",{}).is_empty() or not c.travel_lock064.is_empty():return c.fail("Begin and settle the original withdrawal before interdicting a pursuer.")
	var proof: Dictionary={}
	for row in pursuers(c):
		if row.ownerId==owner_id:proof=row;break
	if proof.is_empty():return c.fail("No reachable actual pursuer of the original boats is currently observed. An unrelated Rust fleet proves nothing about their withdrawal.")
	_remember(c,[proof])
	var p: Dictionary=_priority(c)
	var enemy: Dictionary=c.fleet_owner(owner_id)
	var context: Dictionary={"kind":"patrol","id":owner_id,"ownerId":owner_id,"aggression":false,"name":"Hold the observed pursuer","_arc116":{"jobId":str(p.jobId),"ownerId":str(p.ownerId),"voyageSeq":int(p.voyageSeq),"proof":proof.duplicate(true)}}
	host.begin_battle(enemy.boats.filter(func(b):return not b.get("sunk",false)).map(func(b):return b.spec),context)
	if host.mode!="battle" or str(host.battle_context.get("ownerId",""))!=owner_id:return c.fail("The actual pursuer engagement did not begin; no outcome was recorded.")
	work(c).withdrawal.policy="interdict"
	return c.ok("Engaging the actual observed pursuer. The original boats still need their own confirmed withdrawal or arrival.")

static func after_battle(c,result: String,context: Dictionary,battle: Dictionary,report: Dictionary) -> void:
	var w: Dictionary=work(c)
	var p: Dictionary=_priority(c)
	if not _open(c) or p.is_empty() or battle.is_empty() or battle.has("settlementReport"):return
	if battle.get("result")!=result or float(battle.get("time",0))<=0 or report.get("participants",[]).is_empty():return
	if battle.get("_battleMirror051",false) and not battle.get("simulation051",{}).get("retired",false):return
	var sequence: int=int(battle.get("campaignSequence111",-1))
	var source: String=str(battle.get("engagementSource060",""))
	var b: Dictionary=_book(c)
	if source.is_empty() or sequence<=int(b.battleFloor) or sequence<=int(b.lastSequence) or sequence>int(c.state.get("battleSeq",0)) or w.encounters.size()>=48:return
	if w.encounters.any(func(row):return row.sequence==sequence or row.source==source):return
	var kind: String=str(context.get("kind",""))
	var enemy_id: String=str(context.get("ownerId",""))
	var rows: Array=[]
	var proof: Dictionary={}
	if kind=="escort":
		if context.get("allyOwnerId")!=p.ownerId or context.get("escortEvent")!=p.jobId or str(context.get("escortJobId","")) not in ["",str(p.jobId)] or enemy_id==p.ownerId:return
		var mission: Dictionary=battle.get("mission",{})
		var native: Dictionary=report.get("convoy",{})
		if mission.get("kind")!="escort" or mission.get("carrierTeam")!="player" or mission.get("carrierOwnerId")!=p.ownerId:return
		if native.get("kind")!="escort" or native.get("exit",{}).get("portId")!=p.targetPort or native!=battle.get("convoySettlement",{}):return
		var ids: Array=mission.get("carrierUids",[])
		if ids.is_empty() or ids.size()>p.carrierUids.size() or native.get("carriers",[]).size()!=ids.size():return
		var seen: Dictionary={}
		var loads: Dictionary={}
		for row in native.carriers:
			var uid: String=str(row.get("uid",""))
			if not ids.has(uid) or not p.carrierUids.has(uid) or seen.has(uid) or str(row.get("fate","")) not in ["escaped","sunk","captured","afloat","stranded"]:return
			if not w.withdrawal.is_empty() and not w.withdrawal.carrierUids.has(uid):return
			if str(b.outcomes.get(uid,{}).get("fate","")) in LOSS or row.get("cargoAboard",{})!=mission.get("carrierCargo",{}).get(uid,{}):return
			if not V.valid_load(row.get("cargoAboard")) or not V.number(row.get("crewAlive")) or not V.number(row.get("crewWounded"),0,float(row.crewAlive)):return
			if str(row.fate)=="escaped":
				var actor: Dictionary=battle.get("convoy",{}).get("actors",{}).get(uid,{})
				if not actor.get("battleEscaped",false) or not battle.get("escapedShips",[]).any(func(boat):return is_same(boat,actor)):return
			seen[uid]=true;loads[uid]=row.cargoAboard
			rows.append({"uid":uid,"kind":"encounter","fate":str(row.fate),"source":source,"sequence":sequence,"day":float(c.state.day),"crewAlive":float(row.crewAlive),"crewWounded":float(row.crewWounded),"cargoAboard":row.cargoAboard.duplicate(true),"sourceWreckId":str(row.get("sourceWreckId",""))})
		if not V.within(V.totals(loads),_budget(c)):return
	else:
		var bound: Dictionary=context.get("_arc116",{})
		if kind!="patrol" or w.withdrawal.is_empty() or bound.get("jobId")!=p.jobId or bound.get("ownerId")!=p.ownerId or int(bound.get("voyageSeq",-1))!=int(p.voyageSeq):return
		proof=bound.get("proof",{})
		if proof.get("ownerId")!=enemy_id or not w.threats.has(enemy_id) or proof!=_without_phase(w.threats[enemy_id]):return
		if not V.number(proof.get("day"),float(w.withdrawal.begunDay),float(c.state.day)):return
		kind="interdict"
	# Whole projection checked before evidence is committed. Settlement already
	# moved real losses/cargo to the native wreck/prize owners; never move again.
	w.encounters.append({"phase":str(w.phase),"kind":kind,"source":source,"sequence":sequence,"day":float(c.state.day),"enemyId":enemy_id,"carriers":rows.duplicate(true),"proof":proof.duplicate(true)})
	for row in rows:b.outcomes[row.uid]=row
	b.lastSequence=sequence;b.lastSource=source;w.follow=false
	if kind=="escort":
		var at: Dictionary=battle.get("chartPosition",c.state.position)
		_remember(c,[{"ownerId":enemy_id,"name":str(c.fleet_owner(enemy_id).get("name",enemy_id)),"day":float(c.state.day),"position":{"x":float(at.x),"y":float(at.y)},"convoyPosition":{"x":float(at.x),"y":float(at.y)},"origin":"encounter","orderId":""}])

static func _without_phase(row: Dictionary) -> Dictionary:
	var out: Dictionary=row.duplicate(true);out.erase("phase");return out

static func before_arrival(c,owner: Dictionary,patrol: Dictionary) -> Dictionary:
	var p: Dictionary=_priority(c)
	if not _open(c) or p.is_empty() or str(owner.get("id",""))!=str(p.ownerId):return {}
	if str(patrol.get("from",""))!=str(p.fromPort) or str(patrol.get("to",""))!=str(p.targetPort) or int(patrol.get("voyageSeq",0))!=int(p.voyageSeq):return {}
	return {"ownerId":str(p.ownerId),"fromPort":str(p.fromPort),"targetPort":str(p.targetPort),"voyageSeq":int(p.voyageSeq)}

static func after_arrival(c,owner: Dictionary,patrol: Dictionary,dock: Dictionary,prior: Dictionary) -> void:
	var p: Dictionary=_priority(c)
	if not _open(c) or p.is_empty() or prior.is_empty():return
	if prior.get("ownerId")!=p.ownerId or prior.get("fromPort")!=p.fromPort or prior.get("targetPort")!=p.targetPort or int(prior.get("voyageSeq",-1))!=int(p.voyageSeq):return
	if owner.get("id")!=p.ownerId or dock.get("id")!=p.targetPort or owner.get("atPort")!=p.targetPort or not patrol.get("holding",false) or c.distance(patrol,dock)>=40:return
	var b: Dictionary=_book(c)
	var ids: Array=[]
	var crews: Dictionary={}
	for uid in p.carrierUids:
		if str(b.outcomes.get(uid,{}).get("fate","")) in LOSS:continue
		for boat in owner.boats:
			if str(boat.uid)==str(uid) and not boat.get("sunk",false) and not boat.get("captureSecured",false):
				ids.append(str(uid));crews[str(uid)]={"crewAlive":float(boat.crew),"crewWounded":float(boat.wounded)};break
	var encountered: bool=int(b.lastSequence)>int(b.battleFloor)
	b.arrival={"ownerId":str(p.ownerId),"fromPort":str(p.fromPort),"targetPort":str(p.targetPort),"voyageSeq":int(p.voyageSeq),"day":float(c.state.day),"carrierUids":ids,"crews":crews,"witnessed":c.home_local064() and c.distance(c.state.position,patrol)<=c.EscortOps.CONTRACT_RADIUS,"sequence":int(b.lastSequence) if encountered else 0,"source":str(b.lastSource) if encountered else "","deliveredQty":maxf(0,float(owner.get("tradeDelivered",0))-float(p.baselineDelivered)),"paidRoute":{}}
	if b.arrival.witnessed:_apply_arrivals(b,"witnessed")

static func _apply_arrivals(b: Dictionary,mode: String) -> void:
	var a: Dictionary=b.arrival
	for uid in a.carrierUids:
		var old: Dictionary=b.outcomes.get(uid,{})
		if str(old.get("fate","")) in LOSS or str(old.get("fate",""))=="arrived":continue
		if float(old.get("day",0))>float(a.day) or int(old.get("sequence",0))>int(a.sequence) and int(a.sequence)>0:continue
		var crew: Dictionary=a.crews[uid]
		b.outcomes[uid]={"uid":str(uid),"kind":"arrival","arrivalMode":mode,"fate":"arrived","source":str(a.source),"sequence":int(a.sequence),"day":float(a.day),"crewAlive":float(crew.crewAlive),"crewWounded":float(crew.crewWounded),"cargoAboard":{},"sourceWreckId":""}

static func check_arrival_record(c) -> Dictionary:
	if not _open(c) or _priority(c).is_empty():return c.fail("There is no original 116 passage to inspect.")
	var p: Dictionary=_priority(c)
	if str(c.current_port().get("id",""))!=str(p.targetPort):return c.fail("Inspect the original boats' actual delivery harbor.")
	var permission: Dictionary=c.Politics.permit(c,"service")
	if not permission.ok:return permission
	var b: Dictionary=_book(c)
	if b.arrival.is_empty():return c.fail("No native docking of the original boats is recorded here yet.")
	b.arrival.inspectedAt=str(p.targetPort);b.arrival.inspectedDay=float(c.state.day)
	_apply_arrivals(b,"harbor_record")
	return c.ok("The native harbor record identifies the original arrivals. It supplies no cargo or escort fee.")

static func after_job(c,before: Dictionary,result: Dictionary,abandon: bool) -> void:
	var p: Dictionary=_priority(c)
	if p.is_empty() or p.status!="carried" or not result.get("ok",false):return
	if before.get("kind")!="escort" or before.get("id")!=p.jobId or before.get("ownerId")!=p.ownerId or before.get("targetPort")!=p.targetPort:return
	if not c.state.get("doneVoyageJobs",[]).has(str(p.jobId)):return
	if not abandon:
		var receipt: Dictionary=c.state.get("lastEscortVoyage",{})
		if receipt.get("job",{}).get("id")!=p.jobId or int(receipt.get("payment",-1))!=int(p.reward) or int(result.get("reward",-1))!=int(p.reward):return
		var b: Dictionary=_book(c)
		var route: Dictionary=receipt.job.get("escort",{})
		if not b.arrival.is_empty() and int(route.get("interceptions",0))==0 and route.get("arrived",false) and route.get("carrierUids",[])==p.carrierUids and route.get("carrierCargo",{})==p.carrierCargo and float(route.get("deliveredQty",0))+0.000001>=float(p.tradeQty) and float(route.get("accompaniedDistance",0))+40>=float(p.routeDistance)*0.8 and float(route.get("playerDistance",0))+40>=float(p.routeDistance)*0.8 and float(b.arrival.deliveredQty)+0.000001>=float(p.tradeQty):
			b.arrival.paidRoute={"accompaniedDistance":float(route.accompaniedDistance),"playerDistance":float(route.playerDistance),"routeDistance":float(route.routeDistance),"deliveredQty":float(route.deliveredQty)}
			_apply_arrivals(b,"paid")
	p.status="withdrawn" if abandon else "paid";p.payment=0 if abandon else int(result.reward)
	p.closure={"jobId":str(p.jobId),"ownerId":str(p.ownerId),"status":str(p.status),"payment":int(p.payment),"day":float(c.state.day)}

static func _naval_id(event: Dictionary) -> String:
	return "naval:%d:%s:%s"%[int(event.get("day",0)),str(event.get("a","")),str(event.get("b",""))]

static func after_naval_encounter(c,event: Dictionary) -> void:
	var w: Dictionary=work(c)
	if not _open(c) or w.get("withdrawal",{}).is_empty() or w.aid.size()>=8 or not event.get("witnessed",false):return
	if not same_passage(c) or (counts(c).unresolved==0 and not delivery_pending(c)):return
	if not c.state.get("navalAi",{}).get("encounters",[]).any(func(row):return is_same(row,event)):return
	var id: String=_naval_id(event)
	if w.withdrawal.navalFloor.has(id) or w.aid.any(func(row):return row.id==id):return
	for pair in [[str(event.get("a","")),str(event.get("b","")),"A"],[str(event.get("b","")),str(event.get("a","")),"B"]]:
		var warden: Dictionary=c.fleet_owner(pair[0])
		var threat: Dictionary=w.threats.get(pair[1],{})
		if pair[0] not in ["patrol-2","patrol-8"] or warden.is_empty() or warden.get("faction")!="compact" or warden.get("kind")!="patrol" or threat.get("phase")!="withdrawal":continue
		if not V.number(threat.get("day"),float(w.withdrawal.begunDay),float(c.state.day)) or float(c.state.day)-float(threat.day)>0.25:continue
		if int(event.get("day",0))!=int(c.state.econDay) or int(event.get("shots"+pair[2],0))<=0:continue
		if str(event.get("winner",""))!=pair[0] and str(event.get("retreated",""))!=pair[1]:continue
		var patrol: Dictionary=c.NavalAI._find_patrol(c.state,pair[0])
		var convoy: Dictionary=c.NavalAI._find_patrol(c.state,str(_priority(c).ownerId))
		if patrol.is_empty() or convoy.is_empty() or not c.home_local064() or c.distance(patrol,convoy)>1800:continue
		var ids: Array=warden.boats.map(func(boat):return str(boat.uid))
		if ids.is_empty():continue
		w.aid.append({"id":id,"day":float(c.state.day),"economyDay":int(c.state.econDay),"wardenId":pair[0],"wardenUids":ids,"pursuerId":pair[1],"threat":threat.duplicate(true),"event":event.duplicate(true)})
		return

static func follow(c,enabled: bool) -> Dictionary:
	if not _open(c) or not same_passage(c) or not c.travel_lock064.is_empty():return c.fail("Following needs the same surviving original passage after battle settlement.")
	work(c).follow=enabled;c.arc_follow_timer110=0.0
	if not enabled:c.stop_sailing()
	return c.ok("Following the original surviving boats; a new course or Stop cancels following." if enabled else "Following stopped. The original withdrawal remains open.")

static func cancel_follow(c) -> void:
	if not work(c).is_empty():work(c).follow=false

static func follow_step(c,dt: float) -> void:
	if not work(c).get("follow",false):return
	c.arc_follow_timer110-=dt
	if c.arc_follow_timer110>0:return
	c.arc_follow_timer110=1.0
	if not same_passage(c) or not c.travel_lock064.is_empty():c.stop_sailing();return
	var patrol: Dictionary=c.NavalAI._find_patrol(c.state,str(_priority(c).ownerId))
	if c.distance(c.state.position,patrol)>c.EscortOps.CONTRACT_RADIUS:c.stop_sailing();return
	var points: Array=c.remaining_patrol_course(patrol)
	var target: Dictionary={"x":float(patrol.x),"y":float(patrol.y)} if points.is_empty() else points[0]
	var result: Dictionary=c.chart_course(target)
	work(c).follow=bool(result.get("ok",false))
	if not work(c).follow:c.stop_sailing()

static func follow_speed(c,ordinary: float) -> float:
	if not work(c).get("follow",false) or _priority(c).is_empty():return ordinary
	var owner: Dictionary=c.fleet_owner(str(_priority(c).ownerId))
	var patrol: Dictionary=c.NavalAI._find_patrol(c.state,str(_priority(c).ownerId))
	if owner.is_empty() or patrol.is_empty() or c.distance(c.state.position,patrol)>220:return ordinary
	return minf(ordinary,maxf(0,float(c.NavalAI.fleet_performance(owner).speed)*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0))))

static func _report_ready(c) -> Dictionary:
	var w: Dictionary=work(c)
	if w.is_empty() or w.withdrawal.is_empty() or w.reported:return c.fail("The original second operation has not been bound or is already reported.")
	if w.priority.status=="carried":return c.fail("Claim or withdraw the native escort fee before sending the separate physical report.")
	if counts(c).unresolved>0 and same_passage(c):return c.fail("Original boats remain unconfirmed on their active passage. Follow them, cover a supported threat or inspect their actual arrival record.")
	if not c.travel_lock064.is_empty() or c.current_port().is_empty():return c.fail("Send the report from an actual harbor after settlement.")
	return c.Politics.permit(c,"service")

static func gate(c,rule: Dictionary={}) -> Dictionary:
	match str(rule.get("mode","priority")):
		"priority":return choice_gate(c,"begin_withdrawal116")
		"report":return choice_gate(c,"report_distress116")
	return c.fail("Unknown 116 campaign gate.")

static func choice_gate(c,choice: String) -> Dictionary:
	if choice=="begin_withdrawal116":return _withdraw_ready(c) if str(record(c).get("stage",""))==DISTRESS else c.fail("This chapter is not choosing its original withdrawal.")
	if choice=="report_distress116":return _report_ready(c) if str(record(c).get("stage",""))==WITHDRAWAL else c.fail("This chapter is not awaiting its withdrawal report.")
	if choice=="next_funding116":return c.ok("") if str(record(c).get("stage",""))==ACCOUNT and work(c).get("reported",false) else c.fail("Send the honest 116 account first.")
	return c.ok("")

static func after_choice(c,choice: String,result: Dictionary) -> void:
	if not result.get("ok",false):return
	if choice=="begin_withdrawal116":begin_withdrawal(c);return
	if choice!="report_distress116" or not _report_ready(c).get("ok",false):return
	var w: Dictionary=work(c)
	var n: Dictionary=counts(c)
	w.reported=true;w.phase="reported";w.follow=false
	w.resolution="unconfirmed" if n.unresolved>0 else ("clear" if int(n.escaped)+int(n.arrived)==w.priority.carrierUids.size() else ("partial" if int(n.escaped)+int(n.arrived)>0 else "lost"))
