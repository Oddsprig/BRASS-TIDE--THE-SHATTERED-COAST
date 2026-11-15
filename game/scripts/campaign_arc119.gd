extends RefCounted
## A single chapter's receipts. Native jobs, manifests, travel and purses own reality.
## Do not preload VoyageJobs here: CoastalStories also reads this ending.
const V=preload("res://scripts/campaign_validation119.gd")
const P=preload("res://scripts/campaign_validation117.gd")
const Goods=preload("res://scripts/goods.gd")
const Reserves=preload("res://scripts/harbor_reserves.gd")
const ID: String="common_passage110"
const FROM: String="anvil_dock"
const TO: String="westglass_anchorage"
const GOOD: String="food"
const INTRO: String="common_passage119"
const WORK: String="passage_work119"
const ACCOUNTS: Dictionary={"common":"common_account119","many":"many_account119","unsettled":"unsettled_account119"}
const REPORTS: Dictionary={"report_common119":"common","report_many119":"many","close_unsettled119":"unsettled"}
const FINISH: Dictionary={"finish_common119":"common","finish_many119":"many","finish_unsettled119":"unsettled"}

static func record(c) -> Dictionary:
	return c.state.get("stories",{}).get("chains",{}).get(ID,{})

static func work(c) -> Dictionary:
	return record(c).get("work119",{})

static func attempt(c) -> Dictionary:
	var rows: Array=work(c).get("attempts",[])
	return {} if rows.is_empty() else rows[-1]

static func active(c) -> Dictionary:
	var a: Dictionary=attempt(c)
	return a if a.get("status","")=="carried" else {}

static func _detach(c):
	# No restore(), new game, clock reset, live normalization or partial publication.
	var staged=c.get_script().new(c.data,c.nav,false)
	for field in ["state","events","pending_days","route_cache","route_hits","route_misses","exploration_timer","arc_follow_timer110","sailing_clearance","ocean_context064","ocean_error064","travel_lock064","ocean_context066","ocean_watch066","ocean_conditions066","ocean_anchors064","shipping","crises","trace_steps075","step_costs075"]:
		var value=c.get(field)
		staged.set(field,value.duplicate(true) if value is Dictionary or value is Array else value)
	return staged

static func _stock(p: Dictionary) -> float:
	var value=p.get("stocks",{}).get(GOOD)
	return float(value) if P.number(value) else -1.0

static func _balances(c) -> Dictionary:
	var source: Dictionary=c.port(FROM)
	var target: Dictionary=c.port(TO)
	return {"sourceGov":source.get("governmentPurse"),"targetGov":target.get("governmentPurse"),"captain":c.state.get("coins"),"supplierCash":source.get("cash"),"stock":_stock(source)}

static func _admission(c) -> Dictionary:
	if record(c).get("stage","")!=WORK or record(c).get("done",false) or work(c).is_empty() or work(c).get("report","")!="":return c.fail("Open the final passage with Tobin at Brass Haven first.")
	if V.c2(c.state).is_empty():return c.fail("The chosen funding arrangement needs its actual reported paid escort account.")
	if work(c).attempts.size()>=4:return c.fail("The four recorded passage attempts are closed to new admissions. Their accounts remain available.")
	var previous: Dictionary=attempt(c)
	if not previous.is_empty() and (previous.status!="abandoned" or V.refund_due(previous)>0):return c.fail("Close the previous passage at a harbor and settle its actual fee-return obligation before another admission.")
	if c.state.get("voyageJobs",[]).size()>=c.VoyageJobs.MAX_ACTIVE:return c.fail("Finish or abandon a carried job first.")
	if c.pending_days!=0 or int(c.state.get("econDay",0))<floori(float(c.state.day)):return c.fail("Wait for the harbor accounts to finish their pending day before quoting.")
	return c._work_permission070()

static func _prepare(c) -> Dictionary:
	# The caller owns a detached Core. Even native policy/cache reads stay detached.
	var allowed: Dictionary=_admission(c)
	if not allowed.get("ok",false):return allowed
	var source: Dictionary=c.work_port070()
	var target: Dictionary=c.port(TO)
	if source.get("id","")!=FROM:return c.fail("Stop at Anvil Dock to price and load this real freight.")
	if target.get("regionId","")!="glasswind_keys" or not c.VoyageJobs.WorkRegion070.known_port(c,target):return c.fail("Westglass must already exist and be discovered on its Glasswind chart. Explore it through ordinary travel first.")
	if is_same(source,target) or not c.VoyageJobs._work_access(c,source,GOOD,source) or not c.VoyageJobs._work_access(c,target,GOOD,source):return c.fail("Current harbor permissions or the food trade ban block this passage.")
	var route: Dictionary=c.VoyageJobs.WorkRegion070.route(c,target,source)
	if not route.get("ok",false):return c.fail(str(route.get("message","No outward and return water route is available.")))
	var need: float=maxf(0,float(c.VoyageJobs._freight_needs(target).get(GOOD,{}).get("observedNeed",0))-float(c.VoyageJobs._promised_freight(c.state,TO,GOOD)))
	var weight: float=float(Goods.ITEMS[GOOD].weight)
	var room: float=minf(float(c.VoyageJobs._freight_room(c)),float(c.VoyageJobs._effective_free(c,c.state)))
	var stock: float=minf(_stock(source),float(Reserves.exportable(source,GOOD)))
	var qty: int=mini(8,floori(minf(need,minf(stock,room/weight))))
	if qty<1:return c.fail("There is no current exportable Anvil food load, unmet Westglass need or free physical hold for this passage.")
	var tariff: Dictionary=c.VoyageJobs._work_fee(c,source,float(route.referenceDays),c.VoyageJobs.KIND_FREIGHT,qty,qty*weight)
	if tariff.is_empty() or not P.number(tariff.get("reward"),1,P.COINS,true):return c.fail("The carrier tariff is unavailable.")
	var price=c.Economy.price(source,GOOD)
	if not P.number(price,1,P.COINS,true):return c.fail("The actual supply invoice cannot be quoted.")
	var invoice: int=qty*int(price)
	var fee: int=int(tariff.reward)
	if invoice>int(P.COINS)-fee:return c.fail("Invoice and fee exceed the exact whole-coin range.")
	var basis: Dictionary=V.c2(c.state)
	var model: String=str(basis.model)
	var left: int=floori(float(fee)/2.0)
	var right: int=fee-left
	var shares: Array=[{"payer":"anvil_government","amount":invoice+left},{"payer":"westglass_government","amount":right}] if model=="mutual" else [{"payer":"captain","amount":invoice+fee}]
	var before: Dictionary=_balances(c)
	if not V.balances(before) or int(before.supplierCash)>int(P.COINS)-invoice:return c.fail("The actual supplier cash account cannot receive this invoice.")
	var deposit: int=right if model=="mutual" else invoice+fee
	if int(before.sourceGov)>int(P.COINS)-deposit:return c.fail("The existing Anvil sponsor cannot receive the declared deposit.")
	if model=="mutual" and (int(before.sourceGov)<invoice+left or int(before.targetGov)<right):return c.fail("Both named governments need their disclosed actual invoice and fee shares.")
	if model=="separate" and int(before.captain)<deposit:return c.fail("Your own coins must cover both the material invoice and the service bond, before operating reserves.")
	if not c.Money.move(target if model=="mutual" else c.state,"governmentPurse" if model=="mutual" else "coins",source,"governmentPurse",deposit,"Common Passage disclosed sponsor deposit",c.state.moneyLog):return c.fail("The declared real deposit could not be made.")
	# Native accept ignores invoice move's bool: preflight BOTH debits and its receiver.
	if not P.number(source.get("governmentPurse"),float(invoice+fee),P.COINS,true):return c.fail("The deposited sponsor cannot fund invoice plus escrow.")
	var offer: Dictionary={"id":"common119:%d"%(work(c).attempts.size()+1),"title":"Common Passage: Anvil food to Westglass","description":"An actual purchased, sealed relief load. The disclosed funding model remains binding; the fee is not operating cash.","port":FROM,"targetPort":TO,"kind":"freight","regionId":"shatter_coast","targetRegionId":"glasswind_keys","reward":fee,"escrow":0,"payerKey":"governmentPurse","materialInvoice":invoice,"failed":false,"deadlineDay":floorf(float(c.state.day))+maxf(20,ceilf(maxf(float(route.referenceDays),float(tariff.days))*3+6)),"acceptedDay":0.0,"freight":{"good":GOOD,"qty":qty},"state":"offered","siteId":"","ownerId":"","routeDays":maxi(1,ceili(float(tariff.days))),"routeDistance":float(route.outwardDistance),"demandNeed":need,"demandPurpose":"Current Westglass household food deficit after other promised freight.","loadTier":"small","quotedDay":float(c.state.day),"feeBasis":str(tariff.feeBasis)}
	if not c.VoyageJobs._find(c.state,str(offer.id)).is_empty() or c.VoyageJobs._is_closed(c.state,str(offer.id)):return c.fail("This passage has already been accepted or closed.")
	var reserve: Dictionary=c.VoyageJobs.WorkRegion070.offer_view(c,offer)
	if not reserve.get("readyForAllowance",false):return c.fail("After the actual deposit, payroll, arrears, provisions, loaded fuel, return and contingency must still be funded. "+" ".join(reserve.get("blockers",[])))
	var message: String="Anvil buys %d food bales for %d coins and pays %d of the %d-coin fee; Westglass deposits the remaining %d. Your fleet pays its actual operating costs."%[qty,invoice,left,fee,right] if model=="mutual" else "Your own purse deposits %d coins: %d buys %d food bales and %d is your service bond. Paid completion returns that bond; it is not profit. Cargo, wages, fuel and repairs remain your expenses."%[invoice+fee,invoice,qty,fee]
	return {"ok":true,"message":message,"offer":offer,"model":model,"invoice":invoice,"fee":fee,"contributions":shares,"reserve":reserve,"_before":before,"_basis":basis}

static func _public_quote(prepared: Dictionary) -> Dictionary:
	var q: Dictionary=prepared.duplicate(true)
	q.erase("_before");q.erase("_basis")
	if not q.get("ok",false):q.merge({"offer":{},"model":"","invoice":0,"fee":0,"contributions":[],"reserve":{}},false)
	return q

static func quote(c) -> Dictionary:
	return _public_quote(_prepare(_detach(c)))

static func native_offer(c) -> Dictionary:
	# This metadata exists only on the private transaction Core, never in saved state.
	if not c.get_meta("passage119_admitting",false):return {}
	var pending=c.get_meta("passage119_offer",{})
	return pending.duplicate(true) if pending is Dictionary and record(c).get("stage","")==WORK else {}

static func accept(c,shownQuote: Dictionary) -> Dictionary:
	if not shownQuote.get("ok",false):return c.fail("Review the current complete passage quote first.")
	var staged=_detach(c)
	var prepared: Dictionary=_prepare(staged)
	if not prepared.get("ok",false):return _public_quote(prepared)
	if not P.same_value(_public_quote(prepared),shownQuote):return c.fail("The load, route, funding or operating reserves changed. Review the fresh quote.")
	var old117: Dictionary=record(staged).work117.duplicate(true)
	staged.set_meta("passage119_offer",prepared.offer.duplicate(true))
	staged.set_meta("passage119_admitting",true)
	var admitted: Dictionary=staged.accept_voyage_job(str(prepared.offer.id))
	staged.remove_meta("passage119_admitting");staged.remove_meta("passage119_offer")
	if not admitted.get("ok",false):return c.fail(str(admitted.get("message","admission refused; the staged transaction was discarded.")))
	# Core.accept_voyage_job has now run Manifest.allocate. Bind its canonical job.
	var job: Dictionary=staged.VoyageJobs._find(staged.state,str(prepared.offer.id))
	var binding: Dictionary=V.identity(job)
	var allocations: Dictionary=V.allocations(staged.state,str(prepared.offer.id))
	var funding: Dictionary={"model":prepared.model,"choiceId":prepared._basis.choiceId,"reportDay":prepared._basis.reportDay,"contributions":prepared.contributions.duplicate(true),"before":prepared._before.duplicate(true),"after":_balances(staged)}
	if not V.binding(binding,float(staged.state.day)) or not V.allocation(allocations,float(binding.get("qty",0)),false) or not V.originals(staged.state,allocations) or not V.funding(funding,binding,staged.state):return c.fail("load, invoice or original manifest did not match the declared funding. The passage was not accepted; no funds were spent.")
	if job.get("state")!="active" or not P.number(job.get("escrow"),float(binding.fee),float(binding.fee),true) or not P.same_value(old117,record(staged).work117):return c.fail("The admission or earlier funding book changed unexpectedly. The passage was not accepted; no funds were spent.")
	work(staged).attempts.append({"binding":binding,"allocations":allocations,"funding":funding,"travel":{"outbound":[],"returning":[],"outSeconds":0.0,"backSeconds":0.0,"outDistance":0.0,"backDistance":0.0,"arrivalDay":-1.0,"returnDay":-1.0,"originalIntact":true,"exitProof":true,"battleFloor":int(staged.state.get("battleSeq",0)),"battles":[]},"status":"carried","refund":0,"refundDay":-1.0,"repaid":0,"repayDay":-1.0,"closure":{}})
	var problem: String=V.validate(staged.state)
	if not problem.is_empty():return c.fail("The staged passage record was refused: "+problem)
	c._publish_runtime069(staged)
	return {"ok":true,"message":"Purchased and loaded the original sealed freight under the disclosed funding. Follow the actual outward and return routes.","job":job.duplicate(true)}

static func _originals(c,a: Dictionary) -> bool:
	return P.same_value(V.allocations(c.state,str(a.binding.jobId)),a.allocations) and V.originals(c.state,a.allocations)

static func _berth(c,a: Dictionary) -> void:
	var dock: Dictionary=c.work_port070()
	if a.status=="carried" and a.travel.arrivalDay<0 and dock.get("id","")==TO and a.travel.outbound.size()==2 and a.travel.originalIntact and a.travel.exitProof and _originals(c,a):a.travel.arrivalDay=float(c.state.day)
	if a.status=="paid" and a.travel.returnDay<0 and dock.get("id","")=="brass_haven" and a.travel.returning.size()==2 and float(c.state.day)>float(a.closure.day):a.travel.returnDay=float(c.state.day)

static func after_transition(c,priorLocation: Dictionary,regionId: String,approachId: String,result: Dictionary) -> void:
	var a: Dictionary=attempt(c)
	if a.is_empty() or a.status not in ["carried","paid"] or not result.get("ok",false) or a.travel.returnDay>=0:return
	var old: Dictionary=priorLocation.get("world064",{})
	var current: Dictionary=c.world_location064().get("world064",{})
	var row: Dictionary={"fromLayer":str(old.get("layer","")),"fromRegion":str(old.get("regionId","")),"toLayer":str(current.get("layer","")),"toRegion":str(current.get("regionId","")),"region":regionId,"approach":approachId,"day":float(c.state.day)}
	var outbound: bool=a.status=="carried"
	var departing: String="shatter_coast" if outbound else "glasswind_keys"
	var arriving: String="glasswind_keys" if outbound else "shatter_coast"
	var rows: Array=a.travel.outbound if outbound else a.travel.returning
	if old.get("regionId")==departing and old.get("layer") in ["home","local"] and current.get("layer")=="ocean" and regionId==departing:
		rows.clear();rows.append(row)
		if outbound:a.travel.outSeconds=0.0;a.travel.outDistance=0.0;a.travel.arrivalDay=-1.0
		else:a.travel.backSeconds=0.0;a.travel.backDistance=0.0
	elif old.get("layer")=="ocean" and current.get("regionId")==departing and current.get("layer") in ["home","local"] and rows.size()==1:
		rows.clear()
		if outbound:a.travel.outSeconds=0.0;a.travel.outDistance=0.0
		else:a.travel.backSeconds=0.0;a.travel.backDistance=0.0
	elif old.get("layer")=="ocean" and current.get("regionId")==arriving and current.get("layer") in ["home","local"] and regionId==arriving and rows.size()==1:
		var seconds: float=float(a.travel.outSeconds if outbound else a.travel.backSeconds)
		var distance: float=float(a.travel.outDistance if outbound else a.travel.backDistance)
		if seconds>0 and distance>0 and float(row.day)>float(rows[0].day):rows.append(row)
	_berth(c,a)

static func after_step(c,priorLocation: Dictionary,priorDay: float,dt: float) -> void:
	# Root passes only the committed, clipped _step066 acceptedSeconds.
	var a: Dictionary=attempt(c)
	if a.is_empty() or a.status not in ["carried","paid"] or not is_finite(dt) or dt<=0 or float(c.state.day)<=priorDay:return
	if a.status=="carried" and not _originals(c,a):a.travel.originalIntact=false
	var old: Dictionary=priorLocation.get("world064",{})
	var current: Dictionary=c.world_location064()
	if old.get("layer")=="ocean" and current.get("world064",{}).get("layer")=="ocean":
		var moved: float=c.distance(priorLocation.get("position",{}),current.get("position",{}))
		if moved>0:
			if a.status=="carried" and a.travel.outbound.size()==1:a.travel.outSeconds+=dt;a.travel.outDistance+=moved
			elif a.status=="paid" and a.travel.returning.size()==1:a.travel.backSeconds+=dt;a.travel.backDistance+=moved
	_berth(c,a)

static func after_battle(c,result: String,context: Dictionary,battle: Dictionary,report: Dictionary) -> void:
	var a: Dictionary=active(c)
	if a.is_empty() or float(c.state.day)<float(a.binding.acceptedDay):return
	if battle.has("settlementReport"):return
	if battle.is_empty() or result!=battle.get("result") or not P.number(battle.get("time")) or float(battle.time)<=0 or report.get("participants",[]).is_empty():
		a.travel.exitProof=false
		return
	if battle.get("_battleMirror051",false) and not battle.get("simulation051",{}).get("retired",false):a.travel.exitProof=false;return
	var source: String=str(battle.get("engagementSource060",""))
	var sequence=battle.get("campaignSequence111")
	if source.is_empty() or not P.text(context.get("ownerId")) or not P.number(sequence,float(a.travel.battleFloor)+1,float(c.state.get("battleSeq",0)),true):a.travel.exitProof=false;return
	for prior in a.travel.battles:
		if prior.source==source or prior.sequence==sequence:return
	if a.travel.battles.size()>=8:a.travel.exitProof=false;return
	var exits: Array=[]
	var afloat: Array=[]
	var reserve: Array=[]
	for boat in battle.get("escapedShips",[]):
		var uid: String=str(boat.get("uid",""))
		if a.allocations.has(uid) and is_same(c.find_boat(uid),boat) and boat.get("team","")=="player" and boat.get("battleEscaped",false) and not boat.get("sunk",false) and report.get("participants",[]).any(func(p):return p.get("uid")==uid and p.get("fate")=="escaped") and not exits.has(uid):exits.append(uid)
	for actor in battle.get("ships",[]):
		var actor_uid: String=str(actor.get("uid",""))
		if a.allocations.has(actor_uid) and is_same(c.find_boat(actor_uid),actor) and actor.get("team","")=="player" and not actor.get("sunk",false) and report.get("participants",[]).any(func(p):return p.get("uid")==actor_uid and p.get("fate")=="afloat") and not exits.has(actor_uid) and not afloat.has(actor_uid):afloat.append(actor_uid)
	for support in battle.get("reserves",{}).get("player",[]):
		var support_uid: String=str(support.get("uid",""))
		if a.allocations.has(support_uid) and is_same(c.find_boat(support_uid),support) and not support.get("sunk",false) and not exits.has(support_uid) and not afloat.has(support_uid) and not reserve.has(support_uid):reserve.append(support_uid)
	# Native battle.gd declares ordinary victory when no hostile arena hull remains.
	# Undeployed reserves are not service participants and gain no invented exit.
	var clear_victory: bool=result=="won" and not battle.get("ships",[]).any(func(enemy):return enemy.get("team","")=="enemy" and not enemy.get("sunk",false) and not enemy.get("captureSecured",false))
	exits.sort();afloat.sort();reserve.sort()
	a.travel.battles.append({"source":source,"sequence":int(sequence),"ownerId":str(context.get("ownerId","")),"day":float(c.state.day),"result":result,"clearVictory":clear_victory,"exits":exits,"afloat":afloat,"reserve":reserve})
	if exits.size()!=a.allocations.size() and (not clear_victory or exits.size()+afloat.size()+reserve.size()!=a.allocations.size()):a.travel.exitProof=false
	if not _originals(c,a):a.travel.originalIntact=false

static func before_job(c,job: Dictionary) -> Dictionary:
	var a: Dictionary=active(c)
	if a.is_empty() or job.get("id")!=a.binding.jobId:return {}
	var dock: Dictionary=c.work_port070()
	var good: bool=V.matches(job,a.binding) and is_same(c.VoyageJobs._find(c.state,str(job.id)),job) and not c.VoyageJobs._is_closed(c.state,str(job.id))
	var ready: bool=good and job.get("state")=="active" and not job.get("failed",false) and not job.get("freight",{}).get("lost",false) and a.travel.originalIntact and a.travel.exitProof and int(c.state.get("battleSeq",0))==int(a.travel.battleFloor)+a.travel.battles.size() and _originals(c,a) and a.travel.outbound.size()==2 and a.travel.arrivalDay>=a.binding.acceptedDay and dock.get("id","")==TO and c.travel_lock064.is_empty() and c.transition_blocker064().is_empty()
	return {"ok":ready,"message":"The original freight needs a measured crossing, safe original carriers after any battle, proved exits on retreat, and a stopped Westglass berth before payment.","terms":V.terms(job),"freight":job.get("freight",{}).duplicate(true),"allocations":V.allocations(c.state,str(job.id)),"day":float(c.state.day),"berth":str(dock.get("id","")),"stock":_stock(dock),"coins":c.state.coins,"escrow":job.get("escrow",0)}

static func after_job(c,before: Dictionary,result: Dictionary,abandon: bool) -> void:
	var a: Dictionary=active(c)
	if a.is_empty() or not result.get("ok",false) or not V.matches(before,a.binding):return
	var saved=before.get("delivery119",{})
	if not saved is Dictionary or saved.is_empty() or not P.same_value(saved.get("terms"),V.terms(before)):return
	var id: String=str(a.binding.jobId)
	if not c.VoyageJobs._is_closed(c.state,id) or not c.VoyageJobs._find(c.state,id).is_empty():return
	var dock: Dictionary=c.work_port070()
	if dock.get("id","")!=saved.get("berth","") or not P.same_value(saved.get("freight"),before.get("freight",{})):return
	var receipt: Dictionary={"jobId":id,"day":float(c.state.day),"berth":str(dock.get("id","")),"stockBefore":saved.stock,"stockAfter":_stock(dock),"coinsBefore":saved.coins,"coinsAfter":c.state.coins,"escrowBefore":saved.escrow,"freight":saved.freight.duplicate(true),"allocations":saved.allocations.duplicate(true),"payment":0 if abandon else result.get("reward",-1),"refundAtClose":a.refund,"failed":before.get("failed",false),"battleSequence":int(c.state.get("battleSeq",0))}
	if not abandon and not saved.get("ok",false):return
	var status: String="abandoned" if abandon else "paid"
	if not V.closure(receipt,a,status,float(c.state.day)):return
	a.status=status;a.closure=receipt

static func observe_refund(c,job: Dictionary,amount: int) -> void:
	var a: Dictionary=active(c)
	if a.is_empty() or amount<=0 or not V.matches(job,a.binding):return
	if not is_same(c.VoyageJobs._find(c.state,str(a.binding.jobId)),job) or not P.number(job.get("escrow"),0,float(a.binding.fee),true):return
	if int(a.refund)+amount>int(a.binding.fee) or int(a.refund)+amount!=int(a.binding.fee)-int(job.escrow):return
	a.refund=int(a.refund)+amount;a.refundDay=float(c.state.day)

static func _returnable(c,a: Dictionary) -> bool:
	var due: int=V.refund_due(a)
	if due<=0 or int(a.refund)<due or not c.VoyageJobs._find(c.state,str(a.binding.jobId)).is_empty():return false
	var source: Dictionary=c.port(FROM)
	var recipient: Dictionary=c.port(TO) if a.funding.model=="mutual" else c.state
	var key: String="governmentPurse" if a.funding.model=="mutual" else "coins"
	return not source.is_empty() and not recipient.is_empty() and not is_same(source,recipient) and P.number(source.get("governmentPurse"),float(due),P.COINS,true) and P.number(recipient.get(key),0,P.COINS-float(due),true)

static func settle_refund(c) -> Dictionary:
	for a in work(c).get("attempts",[]):
		var due: int=V.refund_due(a)
		if due<=0:continue
		if not _returnable(c,a):return {"ok":false,"message":"The observed abandoned fee return remains owed. Anvil needs the real coins and the original recipient needs receiving room; the ending does not cancel this obligation.","shortfall":due}
		var recipient: Dictionary=c.port(TO) if a.funding.model=="mutual" else c.state
		if not c.Money.move(c.port(FROM),"governmentPurse",recipient,"governmentPurse" if a.funding.model=="mutual" else "coins",due,"Returned actual abandoned Common Passage fee share",c.state.moneyLog):return c.fail("The real return could not be paid. Its obligation remains recorded.")
		a.repaid=due;a.repayDay=float(c.state.day)
		return c.ok("Returned the recorded fee share once. The spent material invoice is not refunded.")
	return c.ok("No closed abandoned fee-return obligation remains.")

static func _brass(c) -> bool:
	return c.work_port070().get("id","")=="brass_haven" and c.travel_lock064.is_empty() and c._work_permission070().get("ok",false)

static func choice_gate(c,choice: String) -> Dictionary:
	if choice!="begin_passage119" and not REPORTS.has(choice) and not FINISH.has(choice):return c.ok("")
	if record(c).get("done",false) or not _brass(c):return c.fail("Make this explicit campaign choice while stopped at Brass Haven with Tobin.")
	var stage: String=str(record(c).get("stage",""))
	if choice=="begin_passage119":return c.ok("Begin the actual freight undertaking; its availability remains conditional.") if stage==INTRO and work(c).is_empty() and not V.c2(c.state).is_empty() and V.prior_ready(c.state,float(c.state.day)) else c.fail("The final passage is not awaiting its opening conversation.")
	var w: Dictionary=work(c)
	var a: Dictionary=attempt(c)
	if REPORTS.has(choice):
		if stage!=WORK or w.get("report","")!="" or not active(c).is_empty():return c.fail("Finish or abandon the carried undertaking before choosing its debrief.")
		if choice=="close_unsettled119":return c.ok("Explicitly close the incomplete account; unpaid refund obligations remain usable.") if a.is_empty() or a.status=="abandoned" or (a.status=="paid" and a.travel.returnDay<0) else c.fail("This completed returned passage has a paid account to report.")
		var model: String="mutual" if choice=="report_common119" else "separate"
		return c.ok("Report the actually funded delivery and real return.") if a.get("status","")=="paid" and a.get("funding",{}).get("model")==model and a.travel.returnDay>=a.closure.day else c.fail("The chosen model needs an actually paid original delivery and an observed return to Brass.")
	var ending: String=str(FINISH[choice])
	return c.ok("Close this campaign account and continue sailing.") if stage==ACCOUNTS[ending] and w.get("report","")==ending and w.get("finishedDay",-1)==-1 else c.fail("Read this ending's actual debrief account first.")

static func gate(c,rule: Dictionary={}) -> Dictionary:
	if rule.has("choice"):return choice_gate(c,str(rule.choice)) if rule.choice in ["begin_passage119","report_common119","report_many119","close_unsettled119","finish_common119","finish_many119","finish_unsettled119"] else c.fail("Unknown final-passage gate.")
	match str(rule.get("mode","")):
		"begin":return choice_gate(c,"begin_passage119")
		"work":
			var paid: Dictionary=choice_gate(c,"report_common119" if V.c2(c.state).get("model")=="mutual" else "report_many119")
			if paid.get("ok",false):return paid
			var unsettled: Dictionary=choice_gate(c,"close_unsettled119")
			return unsettled if unsettled.get("ok",false) else c.fail(str(paid.message)+" "+str(unsettled.message))
		"paid":return choice_gate(c,"report_common119" if V.c2(c.state).get("model")=="mutual" else "report_many119")
		"unsettled":return choice_gate(c,"close_unsettled119")
		"finish":
			for key in FINISH:
				if FINISH[key]==work(c).get("report",""):return choice_gate(c,str(key))
	return c.fail("Unknown final-passage gate.")

static func after_choice(c,choice: String,result: Dictionary) -> void:
	if not result.get("ok",false):return
	if choice=="begin_passage119" and record(c).get("stage","")==WORK and work(c).is_empty():
		record(c).work119={"schema":1,"startedDay":float(c.state.day),"attempts":[],"report":"","reportDay":-1.0,"finishedDay":-1.0}
	elif REPORTS.has(choice) and record(c).get("stage","")==ACCOUNTS[REPORTS[choice]] and not work(c).is_empty() and work(c).report=="":
		work(c).report=str(REPORTS[choice]);work(c).reportDay=float(c.state.day)
	elif FINISH.has(choice) and record(c).get("done",false) and record(c).get("stage","")==ACCOUNTS[FINISH[choice]] and work(c).get("report","")==FINISH[choice] and work(c).get("finishedDay",-1)==-1:
		work(c).finishedDay=float(c.state.day)

static func outcome(state: Dictionary) -> Dictionary:
	var rec=state.get("stories",{}).get("chains",{}).get(ID,{})
	if not rec is Dictionary or rec.get("done")!=true:return {}
	var w=rec.get("work119",{})
	if not w is Dictionary or not ACCOUNTS.has(w.get("report","")) or rec.get("stage")!=ACCOUNTS[w.report] or not P.number(w.get("finishedDay"),float(w.get("reportDay",-1)),float(state.get("day",0))):return {}
	var title: String={"common":"Common Passage","many":"Many Harbors","unsettled":"Unsettled Coast"}[w.report]
	var body: String={"common":"The two harbors actually funded the purchased relief cargo and service fee. The original sealed load reached Westglass, its held fee was paid, and you returned to Brass.","many":"Your own purse bought the relief cargo and posted its service bond. The original sealed load reached Westglass and the paid bond returned to you. The invoice and operating costs remain your expense; this does not promise protection for every harbor.","unsettled":"At Brass you explicitly closed an incomplete undertaking. The record keeps its actual deliveries, losses, spending and unpaid obligations; retreat alone did not choose this ending."}[w.report]
	var due: int=0
	for a in w.get("attempts",[]):due+=V.refund_due(a)
	body+=" "+V.reception(state)
	return {"title":title,"body":body,"nextAction":"Return the %d coins still owed from the abandoned fee when the actual sponsor can pay. You can continue sailing."%due if due>0 else "Continue sailing, trading and working with harbor contacts. Existing costs and obligations remain."}

static func view(c) -> Dictionary:
	var a: Dictionary=attempt(c)
	var basis: Dictionary=V.c2(c.state)
	var out: Dictionary={"summary":"Discuss the final passage with Tobin at Brass Haven.","funding":"No completed funding commitment is available." if basis.is_empty() else ("Mutual harbor contributions remain the chosen terms." if basis.model=="mutual" else "Your own purse must buy the cargo and post the separate service bond."),"cargo":"Only a fresh paid Anvil food load can complete this passage.","route":"Discover Westglass on its existing Glasswind chart, then use the actual Open Seas route and return to Brass.","ending":"The campaign remains open until your explicit Brass debrief.","reception":V.reception(c.state),"refundDue":0,"refundReturnable":false}
	if c.VoyageJobs.WorkRegion070.known_port(c,c.port(TO)):out.route="Use the sailing charts to reach Westglass, deliver at its berth and return to Brass."
	if not work(c).is_empty():out.summary="The undertaking is open; inspect current availability at Anvil Dock."
	if not a.is_empty():
		out.summary="The original sealed freight is still carried; a retreat leaves the undertaking open." if a.status=="carried" else ("The original cargo delivery was paid; sail back to Brass." if a.status=="paid" else "The undertaking was abandoned. Its actual cargo and fee account remain recorded.")
		var held: int=int(c.VoyageJobs._find(c.state,str(a.binding.jobId)).get("escrow",0))
		out.cargo="%d purchased food bales, invoice %d coins; %d coins currently held."%[int(a.binding.qty),int(a.binding.materialInvoice),held]
		if a.status=="paid":out.cargo="%d food bales delivered; invoice %d coins spent, %d held coins paid."%[int(a.binding.qty),int(a.binding.materialInvoice),int(a.binding.fee)]
		elif a.status=="abandoned":out.cargo="Passage closed; invoice %d coins stays spent. Fee refund recorded: %d coins; returned contribution: %d coins; still owed: %d coins."%[int(a.binding.materialInvoice),int(a.refund),int(a.repaid),V.refund_due(a)]
		out.funding="Anvil government paid %d for materials and %d of the fee; Westglass paid %d. Your fleet pays its operating costs."%[int(a.binding.materialInvoice),floori(float(a.binding.fee)/2),int(a.binding.fee)-floori(float(a.binding.fee)/2)] if a.funding.model=="mutual" else "Your own purse paid %d for materials and posted %d as a service bond. Completion returns your bond; it does not repay materials or operating expenses."%[int(a.binding.materialInvoice),int(a.binding.fee)]
		if a.funding.model=="separate" and a.status=="paid":out.funding="Your purse bought the goods for %d coins and posted %d as a bond. That bond returned to you; the goods and operating costs remain spent."%[int(a.binding.materialInvoice),int(a.binding.fee)]
		elif a.funding.model=="separate" and a.status=="abandoned":out.funding="Your purse spent %d coins on goods and posted %d as a bond. Only the actual fee refund can repay that bond; the goods invoice remains a cost."%[int(a.binding.materialInvoice),int(a.binding.fee)]
		if a.status=="abandoned":out.route="This passage is closed. A fresh attempt needs its own available stock, funds and route."
		if a.status!="abandoned" and a.travel.returnDay>=0:out.route="The outward crossing, delivery and later Brass return are recorded."
		elif a.status!="abandoned" and a.travel.arrivalDay>=0:out.route="Arrival at Westglass is recorded. Payment and the later Brass return remain separate." if a.status!="paid" else "Westglass received the cargo and paid the held fee. The return to Brass remains open."
	for row in work(c).get("attempts",[]):
		out.refundDue+=V.refund_due(row)
		if _returnable(c,row):out.refundReturnable=true
	if out.refundDue>0:out.funding+=" %d coins remain owed from an abandoned fee. The spent material invoice is excluded."%int(out.refundDue)
	var final: Dictionary=outcome(c.state)
	if not final.is_empty():
		out.ending=str(final.title)+": "+str(final.body);out.summary=str(final.nextAction)
		if work(c).report=="unsettled":out.route="This relief undertaking is closed. Ordinary voyages remain available."
	return out
