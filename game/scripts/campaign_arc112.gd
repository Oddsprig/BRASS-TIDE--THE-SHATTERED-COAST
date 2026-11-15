extends RefCounted
## Exit Channel observes one existing funded passage. Native sailing, battle,
## cargo, crews, escrow and refunds remain the only physical/economic owners.
const ID: String="common_passage110"
const STAGE: String="withdrawal_work112"
const TERMINAL: Array=["escaped","arrived","sunk","captured"]

static func record(c) -> Dictionary:
	return c.state.get("stories",{}).get("chains",{}).get(ID,{})

static func work(c) -> Dictionary:
	return record(c).get("work112",{})

static func offers(c) -> Array:
	var out: Array=[]
	if str(record(c).get("stage",""))!=STAGE or not work(c).is_empty():return out
	for sight in c.NavalAI.sightings(c.state):
		if not sight.get("current",false):continue
		var owner_id: String=str(sight.get("ownerId",""))
		var offer: Dictionary=c.EscortOps.offer(c,owner_id)
		if not offer.is_empty() and str(offer.escort.get("fromPort",""))=="kelp_reach":out.append(offer.duplicate(true))
	out.sort_custom(func(a,b):return str(a.id)<str(b.id))
	return out

static func accept(c,terms: Dictionary) -> Dictionary:
	var shown: Dictionary={}
	for offer in offers(c):
		if str(offer.id)==str(terms.get("id","")) and str(offer.ownerId)==str(terms.get("ownerId","")) and int(offer.reward)==int(terms.get("reward",-1)) and str(offer.targetPort)==str(terms.get("targetPort","")) and offer.escort==terms.get("escort",{}):shown=offer;break
	if shown.is_empty():return c.fail("Reacquire the loaded Kelp departure and review its current funded terms.")
	var owner: Dictionary=c.fleet_owner(str(shown.ownerId))
	var crew: Dictionary={}
	for uid in shown.escort.carrierUids:
		for boat in owner.boats:
			if str(boat.uid)==str(uid):crew[uid]={"name":str(boat.name),"crew":float(boat.crew),"wounded":float(boat.wounded)};break
	if crew.size()!=shown.escort.carrierUids.size():return c.fail("The original loaded boats are unavailable.")
	var result: Dictionary=c.VoyageJobs.accept_escort(c,str(shown.ownerId),int(shown.reward))
	if not result.get("ok",false):return result
	var job: Dictionary=c.VoyageJobs._find(c.state,str(shown.id))
	if job.is_empty():return c.fail("Review the accepted native escort; its chapter binding is unavailable.")
	# The accepted native job, rather than the displayed copy, binds the risk.
	record(c).work112={"jobId":str(job.id),"ownerId":str(job.ownerId),"fromPort":"kelp_reach","targetPort":str(job.targetPort),"voyageSeq":int(job.escort.voyageSeq),"acceptedDay":float(job.acceptedDay),"battleFloor":int(c.state.get("battleSeq",0)),"carrierUids":job.escort.carrierUids.duplicate(),"carrierCargo":job.escort.carrierCargo.duplicate(true),"crewAtAcceptance":crew,"reward":int(job.reward),"status":"carried","payment":0,"closure":{},"outcomes":{},"lastSequence":int(c.state.get("battleSeq",0)),"lastSource":"","follow":false,"reported":false,"resolution":""}
	var bound: Dictionary=work(c)
	bound.tradeGood=str(job.escort.tradeGood)
	bound.tradeQty=float(job.escort.tradeQty)
	bound.baselineDelivered=float(job.escort.baselineDelivered)
	bound.routeDistance=float(job.escort.routeDistance)
	bound.arrival={}
	c.log_entry("Exit Channel: bound the original loaded boats leaving Kelp. Each physical escape or loss will be reported separately from the native fee.")
	return result

static func same_passage(c) -> bool:
	var w: Dictionary=work(c)
	if w.is_empty() or not c.home_local064():return false
	var p: Dictionary=c.NavalAI._find_patrol(c.state,str(w.ownerId))
	return not p.is_empty() and p.get("active",false) and int(p.get("voyageSeq",-1))==int(w.voyageSeq) and str(p.get("from",""))=="kelp_reach" and str(p.get("to",""))==str(w.targetPort)

static func after_job(c,before: Dictionary,result: Dictionary,abandon: bool) -> void:
	var w: Dictionary=work(c)
	if w.is_empty() or str(w.status)!="carried" or not result.get("ok",false):return
	if str(before.get("kind",""))!="escort" or str(before.get("id",""))!=str(w.jobId) or str(before.get("ownerId",""))!=str(w.ownerId) or str(before.get("targetPort",""))!=str(w.targetPort):return
	if not c.state.get("doneVoyageJobs",[]).has(str(w.jobId)):return
	if not abandon:
		var receipt: Dictionary=c.state.get("lastEscortVoyage",{})
		if str(receipt.get("job",{}).get("id",""))!=str(w.jobId) or int(receipt.get("payment",-1))!=int(w.reward) or int(result.get("reward",-1))!=int(w.reward):return
		_paid_arrival(c,w,receipt.job)
	w.status="withdrawn" if abandon else "paid"
	w.payment=0 if abandon else int(result.reward)
	w.closure={"jobId":str(w.jobId),"ownerId":str(w.ownerId),"status":str(w.status),"payment":int(w.payment),"day":float(c.state.day)}
	# Closing the native fee never clears the original physical binding.

static func before_arrival(c,owner: Dictionary,p: Dictionary) -> Dictionary:
	var w: Dictionary=work(c)
	if w.is_empty() or w.reported or str(owner.get("id",""))!=str(w.ownerId):return {}
	if str(p.get("from",""))!="kelp_reach" or str(p.get("to",""))!=str(w.targetPort) or int(p.get("voyageSeq",-1))!=int(w.voyageSeq):return {}
	return {"ownerId":str(owner.id),"fromPort":str(p.from),"targetPort":str(p.to),"voyageSeq":int(p.voyageSeq)}

static func after_arrival(c,owner: Dictionary,p: Dictionary,dock: Dictionary,prior: Dictionary) -> void:
	var w: Dictionary=work(c)
	if prior.is_empty() or w.is_empty() or w.reported:return
	if str(prior.get("ownerId",""))!=str(w.ownerId) or str(prior.get("fromPort",""))!="kelp_reach" or int(prior.get("voyageSeq",-1))!=int(w.voyageSeq):return
	if str(prior.get("targetPort",""))!=str(w.targetPort) or str(dock.get("id",""))!=str(w.targetPort) or str(owner.get("atPort",""))!=str(w.targetPort):return
	if not p.get("holding",false) or c.distance(p,dock)>=40:return
	var ids: Array=[]
	var crews: Dictionary={}
	for uid in w.carrierUids:
		for boat in owner.boats:
			if str(boat.uid)!=str(uid) or boat.get("sunk",false) or boat.get("captureSecured",false):continue
			ids.append(str(uid))
			crews[uid]={"crewAlive":float(boat.crew),"crewWounded":float(boat.wounded)}
			break
	var encountered: bool=int(w.lastSequence)>int(w.battleFloor)
	w.arrival={
		"ownerId":str(w.ownerId),
		"fromPort":"kelp_reach",
		"targetPort":str(w.targetPort),
		"voyageSeq":int(w.voyageSeq),
		"day":float(c.state.day),
		"carrierUids":ids,
		"crews":crews,
		"witnessed":c.home_local064() and c.distance(c.state.position,p)<=c.EscortOps.CONTRACT_RADIUS,
		"sequence":int(w.lastSequence) if encountered else 0,
		"source":str(w.lastSource) if encountered else "",
		"deliveredQty":maxf(0,float(owner.get("tradeDelivered",0))-float(w.baselineDelivered)),
		"paidRoute":{}
	}
	refresh_arrivals(c)

static func _paid_arrival(c,w: Dictionary,job: Dictionary) -> void:
	var a: Dictionary=w.arrival
	var route: Dictionary=job.get("escort",{})
	if a.is_empty() or job.get("failed",true):return
	if str(job.get("ownerId",""))!=str(w.ownerId) or str(job.get("targetPort",""))!=str(w.targetPort):return
	if not route.get("arrived",false) or route.get("battlePending",true) or int(route.get("interceptions",0))!=0:return
	if int(route.get("voyageSeq",-1))!=int(w.voyageSeq) or route.get("carrierUids",[])!=w.carrierUids or route.get("carrierCargo",{})!=w.carrierCargo:return
	if str(route.get("tradeGood",""))!=str(w.tradeGood) or float(route.get("tradeQty",-1))!=float(w.tradeQty) or float(route.get("baselineDelivered",-1))!=float(w.baselineDelivered) or float(route.get("routeDistance",-1))!=float(w.routeDistance):return
	if a.carrierUids!=w.carrierUids or float(route.get("deliveredQty",0))+0.000001<float(w.tradeQty):return
	if float(route.get("accompaniedDistance",0))+40<float(w.routeDistance)*0.8 or float(route.get("playerDistance",0))+40<float(w.routeDistance)*0.8:return
	if float(a.deliveredQty)+0.000001<float(w.tradeQty):return
	a.paidRoute={
		"accompaniedDistance":float(route.accompaniedDistance),
		"playerDistance":float(route.playerDistance),
		"routeDistance":float(route.routeDistance),
		"deliveredQty":float(route.deliveredQty)
	}
	_apply_arrivals(w,"paid")

static func refresh_arrivals(c) -> void:
	var w: Dictionary=work(c)
	if w.is_empty() or w.reported or w.arrival.is_empty():return
	var a: Dictionary=w.arrival
	if not a.witnessed:return
	_apply_arrivals(w,"witnessed")

static func check_arrival_record(c) -> Dictionary:
	var w: Dictionary=work(c)
	if w.is_empty() or w.reported:return c.fail("There is no open Kelp withdrawal to check.")
	if str(c.current_port().get("id",""))!=str(w.targetPort):return c.fail("Check the arrivals at the convoy's destination harbor.")
	var permission: Dictionary=c.Politics.permit(c,"service")
	if not permission.ok:return permission
	if w.arrival.is_empty():return c.fail("No arrival of the original boats has been recorded here yet.")
	w.arrival.inspectedAt=str(w.targetPort)
	w.arrival.inspectedDay=float(c.state.day)
	_apply_arrivals(w,"harbor_record")
	return c.ok("The harbor's record confirms which original boats arrived. The escort fee keeps its normal conditions.")

static func _apply_arrivals(w: Dictionary,mode: String) -> void:
	var a: Dictionary=w.arrival
	for uid in a.carrierUids:
		var old: Dictionary=w.outcomes.get(uid,{})
		if str(old.get("fate","")) in TERMINAL:continue
		if int(old.get("sequence",0))>int(a.sequence) or float(old.get("day",0))>float(a.day):continue
		var crew: Dictionary=a.crews[uid]
		w.outcomes[uid]={
			"uid":str(uid),
			"kind":"arrival",
			"arrivalMode":mode,
			"fate":"arrived",
			"source":str(a.source),
			"sequence":int(a.sequence),
			"day":float(a.day),
			"crewAlive":float(crew.crewAlive),
			"crewWounded":float(crew.crewWounded),
			"cargoAboard":{},
			"sourceWreckId":""
		}

static func after_battle(c,result: String,context: Dictionary,battle: Dictionary,report: Dictionary) -> void:
	# Called ONLY after successful canonical NEW settlement, beside Arc111,
	# before settlementReport is written. Cached settlements never call us.
	var w: Dictionary=work(c)
	if w.is_empty() or w.reported or battle.is_empty() or battle.has("settlementReport"):return
	if str(context.get("kind",""))!="escort" or str(context.get("allyOwnerId",""))!=str(w.ownerId) or str(context.get("escortEvent",""))!=str(w.jobId):return
	if str(context.get("escortJobId","")) not in ["",str(w.jobId)] or str(context.get("ownerId",""))==str(w.ownerId):return
	if str(battle.get("result",""))!=result or float(battle.get("time",0))<=0 or report.get("participants",[]).is_empty():return
	if battle.get("_battleMirror051",false) and not battle.get("simulation051",{}).get("retired",false):return
	var sequence: int=int(battle.get("campaignSequence111",-1))
	var source: String=str(battle.get("engagementSource060",""))
	if source.is_empty() or sequence<=int(w.battleFloor) or sequence<=int(w.lastSequence) or sequence>int(c.state.get("battleSeq",0)) or source==str(w.lastSource):return
	var mission: Dictionary=battle.get("mission",{})
	var native: Dictionary=report.get("convoy",{})
	if str(mission.get("kind",""))!="escort" or str(mission.get("carrierTeam",""))!="player" or str(mission.get("carrierOwnerId",""))!=str(w.ownerId):return
	if str(native.get("kind",""))!="escort" or str(native.get("exit",{}).get("portId",""))!=str(w.targetPort) or native!=battle.get("convoySettlement",{}):return
	var uids: Array=mission.get("carrierUids",[])
	if uids.is_empty() or uids.size()>w.carrierUids.size() or native.get("carriers",[]).size()!=uids.size():return
	var updates: Dictionary={}
	var totals: Dictionary={}
	var budget: Dictionary=cargo_budget(w)
	for row in native.carriers:
		var uid: String=str(row.get("uid",""))
		if not w.carrierUids.has(uid) or not uids.has(uid) or updates.has(uid) or str(row.get("fate","")) not in ["escaped","sunk","captured","afloat","stranded"]:return
		var load: Dictionary=row.get("cargoAboard",{})
		if load!=mission.get("carrierCargo",{}).get(uid,{}):return
		if str(w.outcomes.get(uid,{}).get("fate","")) in ["sunk","captured"]:return
		for good in load:
			if not budget.has(good) or float(load[good])<0:return
			totals[good]=float(totals.get(good,0))+float(load[good])
		if str(row.fate)=="escaped":
			var actor: Dictionary=battle.get("convoy",{}).get("actors",{}).get(uid,{})
			if not actor.get("battleEscaped",false) or not battle.get("escapedShips",[]).any(func(boat):return is_same(boat,actor)):return
		updates[uid]={"uid":uid,"kind":"encounter","fate":str(row.fate),"source":source,"sequence":sequence,"day":float(c.state.day),"crewAlive":float(row.get("crewAlive",0)),"crewWounded":float(row.get("crewWounded",0)),"cargoAboard":load.duplicate(true),"sourceWreckId":str(row.get("sourceWreckId",""))}
	for good in totals:
		if float(totals[good])>float(budget[good])+0.000001:return
	# Validate the whole native projection before writing any chapter evidence.
	for uid in updates:w.outcomes[uid]=updates[uid]
	w.lastSequence=sequence;w.lastSource=source
	w.follow=false
	c.log_entry("Exit Channel: recorded each original boat's physical outcome. Unresolved boats remain unfinished; the ordinary escort fee keeps its own rules.")

static func counts(c) -> Dictionary:
	var out: Dictionary={"escaped":0,"arrived":0,"sunk":0,"captured":0,"unresolved":0}
	var w: Dictionary=work(c)
	for uid in w.get("carrierUids",[]):
		var fate: String=str(w.get("outcomes",{}).get(uid,{}).get("fate","unknown"))
		var key: String=fate if fate in TERMINAL else "unresolved"
		out[key]=int(out[key])+1
	return out

static func gate(c,rule: Dictionary={}) -> Dictionary:
	return choice_gate(c,"report_withdrawal112")

static func choice_gate(c,choice: String) -> Dictionary:
	if choice!="report_withdrawal112":return c.ok("")
	var w: Dictionary=work(c)
	if str(record(c).get("stage",""))!=STAGE or w.is_empty() or w.reported:return c.fail("Accept and account for this original Kelp passage first.")
	if counts(c).unresolved>0:return c.fail("Some original boats have no confirmed exit or loss. Their withdrawal remains open.")
	if str(w.status)=="carried":return c.fail("Claim or withdraw the native escort contract before sending Wren the separate report.")
	if not c.travel_lock064.is_empty() or c.current_port().is_empty():return c.fail("Send Wren the report from an actual harbor after the encounter settles.")
	return c.Politics.permit(c,"service")

static func after_choice(c,choice: String,result: Dictionary) -> void:
	if choice!="report_withdrawal112" or not result.get("ok",false):return
	var w: Dictionary=work(c)
	if w.is_empty() or w.reported:return
	var n: Dictionary=counts(c)
	w.reported=true;w.follow=false
	w.resolution="clear" if n.escaped+n.arrived==w.carrierUids.size() else ("partial" if n.escaped+n.arrived>0 else "lost")

static func follow(c,enabled: bool) -> Dictionary:
	var w: Dictionary=work(c)
	if w.is_empty() or w.reported or not same_passage(c) or not c.travel_lock064.is_empty():return c.fail("Following needs the same surviving passage on this chart after battle settlement.")
	w.follow=enabled;c.arc_follow_timer110=0.0
	if not enabled:c.stop_sailing()
	return c.ok("Following the original working boats. A new course or Stop cancels following." if enabled else "Following stopped; the withdrawal remains open.")

static func cancel_follow(c) -> void:
	var w: Dictionary=work(c)
	if not w.is_empty():w.follow=false

static func follow_step(c,dt: float) -> void:
	var w: Dictionary=work(c)
	if not w.get("follow",false):return
	c.arc_follow_timer110-=dt
	if c.arc_follow_timer110>0:return
	c.arc_follow_timer110=1.0
	if not same_passage(c) or not c.travel_lock064.is_empty():c.stop_sailing();return
	var p: Dictionary=c.NavalAI._find_patrol(c.state,str(w.ownerId))
	if p.get("holding",false) or c.distance(c.state.position,p)>c.EscortOps.CONTRACT_RADIUS:c.stop_sailing();return
	var points: Array=c.remaining_patrol_course(p)
	var target: Dictionary={"x":float(p.x),"y":float(p.y)} if points.is_empty() else points[0]
	var result: Dictionary=c.chart_course(target)
	w.follow=bool(result.get("ok",false))
	if not w.follow:c.stop_sailing()

static func follow_speed(c,ordinary: float) -> float:
	var w: Dictionary=work(c)
	if not w.get("follow",false):return ordinary
	var owner: Dictionary=c.fleet_owner(str(w.ownerId))
	var p: Dictionary=c.NavalAI._find_patrol(c.state,str(w.ownerId))
	if owner.is_empty() or p.is_empty() or c.distance(c.state.position,p)>220:return ordinary
	return minf(ordinary,maxf(0,float(c.NavalAI.fleet_performance(owner).speed)*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0))))

static func cargo_budget(w: Dictionary) -> Dictionary:
	var budget: Dictionary={}
	for load in w.carrierCargo.values():
		for good in load:budget[good]=float(budget.get(good,0))+float(load[good])
	for row in w.outcomes.values():
		if str(row.get("fate","")) not in ["sunk","captured"]:continue
		for good in row.cargoAboard:
			budget[good]=float(budget.get(good,0))-float(row.cargoAboard[good])
	return budget

static func protection_gate(c) -> Dictionary:
	var w: Dictionary=work(c)
	if w.is_empty() or w.reported or counts(c).unresolved==0 or not same_passage(c):
		return c.fail("No unresolved original boats are available on this same passage.")
	var plan: Dictionary=c.EscortOps._load_plan(c,c.fleet_owner(str(w.ownerId)))
	if not plan.get("ok",false):
		return c.fail("This protection action needs a loaded carrier. Unloaded survivors can be accounted for at their actual arrival harbor.")
	var totals: Dictionary={}
	var budget: Dictionary=cargo_budget(w)
	for uid in plan.carrierUids:
		if not w.carrierUids.has(str(uid)):
			return c.fail("The current loaded passage includes a different boat; it cannot replace the original withdrawal.")
		for good in plan.carrierCargo[uid]:
			totals[good]=float(totals.get(good,0))+float(plan.carrierCargo[uid][good])
	for good in totals:
		if not budget.has(good) or float(totals[good])>float(budget[good])+0.000001:
			return c.fail("The current load no longer matches the remaining original passage.")
	return c.ok("")
