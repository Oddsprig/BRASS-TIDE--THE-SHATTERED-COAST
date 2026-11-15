extends RefCounted
## Narrow adapter: the coastal story owns stages; native jobs own boats,
## cargo, movement, wages, loss, escrow and payment. No new account or actor.
const ID: String="common_passage110"
const OPENING: String="overdue_merchant110"
const OPERATIONS: Array=[OPENING]
const Goods=preload("res://scripts/goods.gd")

static func record(c) -> Dictionary:
	return c.state.get("stories",{}).get("chains",{}).get(ID,{})

static func accept_lead(c) -> void:
	var rec: Dictionary=record(c)
	for owner in c.state.get("fleetOwners",[]):
		if str(owner.get("kind",""))!="trader" or str(owner.get("homePort",""))!="kelp_reach" or not owner.get("active",false):continue
		var patrol: Dictionary=c.NavalAI._find_patrol(c.state,str(owner.id))
		if patrol.is_empty() or str(patrol.get("from",""))!="kelp_reach":continue
		rec.lead110={"ownerId":str(owner.id),"name":str(owner.name),"fromPort":"kelp_reach","targetPort":str(patrol.get("to","")),"day":float(c.state.day)}
		return

static func pending(c) -> Dictionary:
	return record(c).get("pending110",{})

static func completed(c,operation: String) -> Dictionary:
	return record(c).get("outcomes110",{}).get(operation,{})

static func gate(c,rule: Dictionary) -> Dictionary:
	if c==null:return {"ok":false,"message":"Return to your voyage to open the campaign."}
	var receipt: Dictionary=completed(c,str(rule.get("operation","")))
	if receipt.get("result","")!="paid":return c.fail("Complete this escort and collect the client’s fee first.")
	var port: String=str(rule.get("port",""))
	if not port.is_empty() and str(c.current_port().get("id",""))!=port:return c.fail("Return to "+str(c.port(port).get("name",port))+" for this conversation.")
	return c.ok("The contact can hear your report.")

# Only currently observed contacts are shown. An old report is not access to
# the client's live load, position, destination or purse.
static func clients(c) -> Array:
	var out: Array=[]
	if str(record(c).get("stage",""))!="escort_work110" or not pending(c).is_empty() or not completed(c,OPENING).is_empty():return out
	for sight in c.NavalAI.sightings(c.state):
		if not bool(sight.get("current",false)):continue
		var id: String=str(sight.get("ownerId",""))
		var offer: Dictionary=c.EscortOps.offer(c,id)
		if not offer.is_empty():out.append(offer.duplicate(true))
	out.sort_custom(func(a,b):return str(a.id)<str(b.id))
	return out

# The escort fee belongs to the client. This quote separately reserves the
# player's entire payroll, food and fuel through the actual delivery and home.
# It is an explicit modal/acceptance calculation, never a per-frame forecast.
static func reserve_quote(c,offer: Dictionary) -> Dictionary:
	var owner: Dictionary=c.fleet_owner(str(offer.get("ownerId","")))
	var destination: Dictionary=c.port(str(offer.get("targetPort","")))
	var home: Dictionary=c.port("brass_haven")
	if owner.is_empty() or destination.is_empty() or home.is_empty():return {}
	var path: Array=c.Routes.path(c,destination,home)
	if path.is_empty():return {}
	var returning: float=0.0
	for i in range(1,path.size()):returning+=c.distance(path[i-1],path[i])
	var own_speed: float=c.travel_speed()
	var client_speed: float=float(c.NavalAI.fleet_performance(owner).speed)*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0))
	var outward: float=float(offer.get("escort",{}).get("routeDistance",0))/maxf(0.01,minf(own_speed,client_speed))/float(c.DAY_SECONDS)
	var return_days: float=returning/maxf(0.01,own_speed)/float(c.DAY_SECONDS)
	var plan: Dictionary={"outwardDays":outward,"returnDays":return_days}
	return c.Expedition.report(c.state,c.data,float(offer.get("escort",{}).get("routeDistance",0))+returning,own_speed,plan)

static func accept_escort(c,quote: Dictionary) -> Dictionary:
	var owner_id: String=str(quote.get("ownerId",""))
	var quoted_fee: int=int(quote.get("reward",-1))
	var rec: Dictionary=record(c)
	if str(rec.get("stage",""))!="escort_work110" or not pending(c).is_empty() or not completed(c,OPENING).is_empty():return c.fail("This campaign operation is not awaiting an escort.")
	var shown: Dictionary={}
	for offer in clients(c):
		if str(offer.ownerId)==owner_id and int(offer.reward)==quoted_fee:shown=offer;break
	if shown.is_empty():return c.fail("Reacquire and hail the actual loaded client; this quote is no longer current.")
	if str(shown.id)!=str(quote.get("id","")) or str(shown.targetPort)!=str(quote.get("targetPort","")) or shown.escort.get("voyageSeq",-1)!=quote.get("escort",{}).get("voyageSeq",-2) or shown.escort.carrierUids!=quote.get("escort",{}).get("carrierUids",[]) or str(shown.escort.tradeGood)!=str(quote.get("escort",{}).get("tradeGood","")) or float(shown.escort.tradeQty)!=float(quote.get("escort",{}).get("tradeQty",-1)):return c.fail("The original voyage, destination or load changed. Review its actual terms again.")
	var allowance: Dictionary=reserve_quote(c,shown)
	if allowance.is_empty() or not bool(allowance.get("readyForAllowance",false)):return c.fail("Prepare payroll, food and loaded fuel for the delivery, return to Brass Haven and two contingency days before taking this campaign escort.")
	var result: Dictionary=c.VoyageJobs.accept_escort(c,owner_id,quoted_fee)
	if not result.get("ok",false):return result
	var job: Dictionary=c.VoyageJobs._find(c.state,str(shown.id))
	if job.is_empty() or str(job.get("ownerId",""))!=owner_id or str(job.get("id",""))!=str(shown.id):return c.fail("The escort was accepted, but its campaign record is unavailable. Review your active voyage jobs; no campaign progress was awarded.")
	# accept_escort's successful job is authoritative, not the displayed copy.
	rec.pending110={"operation":OPENING,"jobId":str(job.id),"kind":"escort","ownerId":str(job.ownerId),"targetPort":str(job.targetPort),"carrierUids":job.escort.carrierUids.duplicate(),"tradeGood":str(job.escort.tradeGood),"tradeQty":float(job.escort.tradeQty),"acceptedDay":float(job.acceptedDay),"voyageSeq":int(job.escort.voyageSeq),"follow":false}
	c.log_entry("Campaign escort accepted: %s, passage %s."%[str(c.fleet_owner(owner_id).name),str(job.id)])
	return result

# Called immediately AFTER the original native payment/refund, before a
# subsequent job can replace lastEscortVoyage. Duplicate settlement is inert.
static func after_job(c,before: Dictionary,result: Dictionary,abandon: bool) -> void:
	var rec: Dictionary=record(c)
	var bound: Dictionary=pending(c)
	if bound.is_empty() or not result.get("ok",false) or str(before.get("id",""))!=str(bound.get("jobId","")):return
	if str(before.get("kind",""))!=str(bound.get("kind","")) or str(before.get("ownerId",""))!=str(bound.get("ownerId","")) or str(before.get("targetPort",""))!=str(bound.get("targetPort","")):return
	if not c.state.get("doneVoyageJobs",[]).has(str(before.id)):return
	if abandon:
		rec.pending110={}
		c.log_entry("Campaign escort withdrawn. The actual client was refunded; the investigation remains open.")
		return
	# Native finish may perform the final arrival tick after the caller's snapshot.
	# Consume its immediate matching paid receipt, never an unrelated later escort.
	var paid_record: Dictionary=c.state.get("lastEscortVoyage",{})
	var settled: Dictionary=paid_record.get("job",{})
	if str(settled.get("id",""))!=str(before.id) or int(paid_record.get("payment",-1))!=int(result.get("reward",-2)):return
	var route: Dictionary=settled.get("escort",{})
	if int(route.get("voyageSeq",-1))!=int(bound.get("voyageSeq",-2)):return
	if not route.get("arrived",false) or route.get("battlePending",false) or route.get("carrierUids",[])!=bound.carrierUids or str(route.get("tradeGood",""))!=str(bound.tradeGood) or float(route.get("tradeQty",0))!=float(bound.tradeQty) or int(result.get("reward",0))!=int(before.get("reward",-1)):return
	if not rec.get("outcomes110") is Dictionary:rec.outcomes110={}
	var operation: String=str(bound.operation)
	if rec.outcomes110.has(operation):return
	rec.outcomes110[operation]={"result":"paid","jobId":str(before.id),"kind":str(before.kind),"ownerId":str(before.ownerId),"targetPort":str(before.targetPort),"carrierUids":bound.carrierUids.duplicate(),"tradeGood":str(bound.tradeGood),"tradeQty":float(bound.tradeQty),"reward":int(result.reward),"day":float(c.state.day),"arrivedDay":float(route.get("arrivedDay",c.state.day)),"voyageSeq":int(bound.voyageSeq)}
	rec.pending110={}
	c.log_entry("Campaign: the original loaded merchant delivered and paid. Return to Tobin at Brass Haven.")

static func follow(c,enabled: bool) -> Dictionary:
	var bound: Dictionary=pending(c)
	var job: Dictionary=c.VoyageJobs._find(c.state,str(bound.get("jobId","")))
	if bound.is_empty() or job.is_empty() or job.get("state","")!="active" or job.get("failed",false):return c.fail("There is no active bound convoy to follow.")
	if not c.home_local064() or job.escort.get("battlePending",false):return c.fail("Resume following after the physical encounter settles.")
	bound.follow=enabled
	c.arc_follow_timer110=0.0
	if not enabled:c.stop_sailing()
	return c.ok("Following the contracted merchant. Another course or Stop cancels following." if enabled else "Convoy follow stopped; the contract still requires protection.")

static func cancel_follow(c) -> void:
	var bound: Dictionary=pending(c)
	if not bound.is_empty():bound.follow=false

# One route update per simulated second, never per render frame. NPC orders,
# cargo and clocks are untouched. Existing navigation checks every player path.
static func follow_step(c,dt: float) -> void:
	var bound: Dictionary=pending(c)
	if not bound.get("follow",false):return
	c.arc_follow_timer110-=dt
	if c.arc_follow_timer110>0:return
	c.arc_follow_timer110=1.0
	var job: Dictionary=c.VoyageJobs._find(c.state,str(bound.jobId))
	if job.is_empty() or job.get("state","")!="active" or job.get("failed",false) or not c.home_local064():c.stop_sailing();return
	if job.escort.get("battlePending",false):return
	if job.escort.get("arrived",false):c.stop_sailing();return
	var p: Dictionary=c.NavalAI._find_patrol(c.state,str(bound.ownerId))
	if p.is_empty() or c.distance(c.state.position,p)>c.EscortOps.CONTRACT_RADIUS:c.stop_sailing();return
	var points: Array=c.remaining_patrol_course(p)
	var target: Dictionary={"x":float(p.x),"y":float(p.y)} if points.is_empty() else points[0]
	var plotted: Dictionary=c.chart_course(target)
	bound.follow=bool(plotted.get("ok",false))
	if not bound.follow:c.stop_sailing()

static func follow_speed(c,ordinary: float) -> float:
	var bound: Dictionary=pending(c)
	if not bound.get("follow",false):return ordinary
	var owner: Dictionary=c.fleet_owner(str(bound.get("ownerId","")))
	var p: Dictionary=c.NavalAI._find_patrol(c.state,str(bound.get("ownerId","")))
	if owner.is_empty() or p.is_empty() or c.distance(c.state.position,p)>220:return ordinary
	var pace: float=float(c.NavalAI.fleet_performance(owner).speed)*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0))
	return minf(ordinary,maxf(0,pace))

static func validate(state: Dictionary) -> String:
	var rec=state.get("stories",{}).get("chains",{}).get(ID,{})
	if not rec is Dictionary:return "Invalid campaign110 progress."
	for key in ["pending110","outcomes110"]:
		if rec.has(key) and not rec[key] is Dictionary:return "Invalid campaign110 operation book."
	if rec.has("lead110"):
		if not rec.lead110 is Dictionary:return "Invalid campaign110 departure report."
		for key in ["ownerId","name","fromPort","targetPort"]:
			if not rec.lead110.get(key) is String or str(rec.lead110[key]).length()>160:return "Invalid campaign110 departure identity."
		var day=rec.lead110.get("day")
		if not (day is int or day is float) or not is_finite(float(day)) or float(day)<1:return "Invalid campaign110 report date."
	var proofs: Dictionary=rec.get("outcomes110",{})
	if proofs.size()>12:return "Campaign110 outcome limit exceeded."
	var p: Dictionary=rec.get("pending110",{})
	var entries: Array=proofs.values()
	if not p.is_empty():
		if p.get("operation","") not in OPERATIONS or not p.get("follow") is bool:return "Invalid pending campaign operation."
		var day=p.get("acceptedDay")
		if not (day is float or day is int) or not is_finite(float(day)) or float(day)<1:return "Invalid campaign110 acceptance date."
		entries.append(p)
	# Validate types BEFORE converting or comparing a pending native identity.
	for item in entries:
		if not item is Dictionary:return "Invalid campaign110 receipt."
		for key in ["jobId","kind","ownerId","targetPort","tradeGood"]:
			if not item.get(key) is String or str(item[key]).is_empty() or str(item[key]).length()>160:return "Invalid campaign110 operation identity."
		var sequence=item.get("voyageSeq")
		if not (sequence is int or sequence is float) or not is_finite(float(sequence)) or float(sequence)<0 or float(sequence)>1000000000 or floorf(float(sequence))!=float(sequence):return "Invalid campaign110 passage sequence."
		if item.kind!="escort" or not Goods.ITEMS.has(str(item.tradeGood)) or not item.get("carrierUids") is Array or item.carrierUids.is_empty() or item.carrierUids.size()>48:return "Invalid campaign110 bound carriers."
		var unique: Dictionary={}
		for uid in item.carrierUids:
			if not uid is String or uid.is_empty() or uid.length()>120 or unique.has(uid):return "Invalid campaign110 carrier identity."
			unique[uid]=true
		var qty=item.get("tradeQty")
		if not (qty is float or qty is int) or not is_finite(float(qty)) or float(qty)<=0 or float(qty)>1000000000:return "Invalid campaign110 cargo quantity."
	if not p.is_empty():
		var native: Dictionary={}
		for job in state.get("voyageJobs",[]):
			if job is Dictionary and str(job.get("id",""))==str(p.jobId):native=job;break
		var route=native.get("escort",{})
		if not route is Dictionary:return "Invalid campaign110 native passage."
		if native.is_empty() or str(native.get("kind",""))!=str(p.kind) or str(native.get("ownerId",""))!=str(p.ownerId) or str(native.get("targetPort",""))!=str(p.targetPort) or route.get("carrierUids",[])!=p.carrierUids or int(route.get("voyageSeq",-1))!=int(p.voyageSeq) or str(route.get("tradeGood",""))!=str(p.tradeGood) or float(route.get("tradeQty",-1))!=float(p.tradeQty):return "Campaign110 binding has no matching native passage and load."
	var used_jobs: Dictionary={}
	for key in proofs:
		if key not in OPERATIONS:return "Unknown campaign110 operation."
		var item: Dictionary=proofs[key]
		var reward=item.get("reward")
		if item.get("result")!="paid" or not (reward is int or reward is float) or not is_finite(float(reward)) or float(reward)<=0 or float(reward)>1000000000 or floorf(float(reward))!=float(reward):return "Invalid campaign110 paid outcome."
		if used_jobs.has(str(item.jobId)):return "A native job cannot complete two campaign operations."
		used_jobs[str(item.jobId)]=true
		for field in ["day","arrivedDay"]:
			if not (item.get(field) is int or item.get(field) is float) or not is_finite(float(item[field])) or float(item[field])<1:return "Invalid campaign110 outcome date."
	return ""
