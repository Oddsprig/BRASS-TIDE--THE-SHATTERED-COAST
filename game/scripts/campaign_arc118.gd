extends RefCounted
## Chapter receipts only. Native policy, trade, original boats and escort escrow
## retain authority; a current claimant application proves no historical claim.
const V=preload("res://scripts/campaign_validation118.gd")
const P=preload("res://scripts/campaign_validation117.gd")
const Economy=preload("res://scripts/economy.gd")
const Reserves=preload("res://scripts/harbor_reserves.gd")
const Goods=preload("res://scripts/goods.gd")
const ID: String="common_passage110"
const OPTIONAL: String="tobin_clause111"
const PORT: String="naphtha_bay"
const BRASS: String="brass_haven"
const STEPS: Dictionary={"begin_fuel118":["fuel_has_owners118","fuel_work118"],"report_fuel118":["fuel_work118","fuel_account118"],"next_warrant118":["fuel_account118","last_warrant118"],"begin_warrant118":["last_warrant118","warrant_work118"],"report_warrant118":["warrant_work118","warrant_account118"],"report_unresolved118":["warrant_work118","warrant_account118"],"next_passage118":["warrant_account118","common_passage119"]}

static func record(c) -> Dictionary:
	return c.state.get("stories",{}).get("chains",{}).get(ID,{})

static func work(c) -> Dictionary:
	return record(c).get("work118",{})

static func active(c) -> Dictionary:
	var a: Dictionary=work(c).get("attempt",{})
	return a if a.get("status","")=="carried" and not work(c).get("warrantReported",false) else {}

static func _ensure(c) -> Dictionary:
	var rec: Dictionary=record(c)
	if rec.is_empty():return {}
	if not rec.has("work118"):
		rec.work118={"schema":1,"startedDay":-1.0,"passage":{},"fuel":{},"fuelReported":false,"fuelReportDay":-1.0,"warrantDay":-1.0,"attempt":{},"warrantReported":false,"warrantReportDay":-1.0,"warrantPort":"","resolution":"","tobin":{}}
	return rec.work118

static func _access(c,p: Dictionary) -> Dictionary:
	# Politics.access ensures its input: give it detached policy, never live state.
	var policy: Dictionary={"day":c.state.day,"relationships":c.state.get("relationships",{}).duplicate(true)}
	return c.Politics.access({"state":policy,"data":c.data},p)

static func passage_quote(c) -> Dictionary:
	var q: Dictionary={"ok":false,"message":"Begin Fuel Has Owners, then stop at Naphtha Bay.","cost":0,"mode":"","port":PORT}
	if record(c).get("stage","")!="fuel_work118":return q
	var p: Dictionary=c.current_port()
	if str(p.get("id",""))!=PORT or not c.state.get("path",[]).is_empty():return q
	var a: Dictionary=_access(c,p)
	if a.get("legal",false):
		q.ok=true;q.mode="legal";q.message="Ordinary current harbor permission costs nothing. It conveys no fuel ownership or protection from fleets at sea."
		return q
	if not P.number(a.get("claim"),0,1000000,true):q.message="The actual harbor claim cannot be quoted.";return q
	q.mode="parley";q.cost=1000+100*int(a.claim)
	q.message="Three-day Naphtha-only civilian safe conduct costs %d coins; fleets at sea remain independent."%int(q.cost)
	if not P.number(c.state.get("coins"),float(q.cost),P.COINS,true):q.message="The actual player purse cannot afford this local parley.";return q
	for key in ["householdPurse","expertPurse","governmentPurse"]:
		var share: int=750 if key=="householdPurse" else (200 if key=="expertPurse" else 50+100*int(a.claim))
		if not P.number(p.get(key),0,P.COINS-float(share),true):q.message="A harbor purse cannot receive this whole-coin bill.";return q
	q.ok=true
	return q

static func secure_passage(c) -> Dictionary:
	var q: Dictionary=passage_quote(c)
	if not q.ok:return q
	if not work(c).get("fuel",{}).is_empty():return c.fail("The first fuel purchase is already recorded; its access receipt stays historical.")
	var p: Dictionary=c.current_port()
	var a: Dictionary=_access(c,p)
	if q.mode=="legal":
		if work(c).get("passage",{}).is_empty():work(c).passage={"port":PORT,"mode":"legal","day":float(c.state.day),"cost":0,"claim":int(a.claim),"until":0.0}
		return c.ok(str(q.message))
	var coins=c.state.coins
	var purses: Array=[p.householdPurse,p.expertPurse,p.governmentPurse]
	var result: Dictionary=c.Politics.parley(c)
	if not result.get("ok",false):return result
	# Record only the successful native transfer, not a permission flag alone.
	p=c.current_port()
	if not P.number(c.state.get("coins"),0,P.COINS,true) or not P.same_value(coins-int(q.cost),c.state.coins):return c.fail("The parley payment did not match its bill; review the harbor account.")
	var paid: Array=[750,200,50+100*int(a.claim)]
	var keys: Array=["householdPurse","expertPurse","governmentPurse"]
	for i in range(3):
		if not P.same_value(purses[i]+paid[i],p.get(keys[i])):return c.fail("The harbor's received payments did not match its bill; no access receipt was recorded.")
	var until=c.state.get("relationships",{}).get("safeConduct",{}).get(PORT)
	if not P.number(until) or not P.same_value(until,float(c.state.day)+3.0):return c.fail("No actual three-day Naphtha pass was published.")
	work(c).passage={"port":PORT,"mode":"parley","day":float(c.state.day),"cost":int(q.cost),"claim":int(a.claim),"until":until}
	return result

static func fuel_quote(c,qty: int=5) -> Dictionary:
	var q: Dictionary={"ok":false,"message":"Buy fresh Naphtha fuel during Fuel Has Owners; old tank fuel does not count.","qty":qty,"price":0,"cost":0}
	if record(c).get("stage","")!="fuel_work118" or not work(c).get("fuel",{}).is_empty() or qty<=0 or qty>1000000:return q
	var access: Dictionary=passage_quote(c)
	if not access.ok or access.mode!="legal":q.message="Obtain actual legal entry at Naphtha before purchasing its fuel.";return q
	var p: Dictionary=c.current_port()
	q.price=Economy.price(p,"fuel","buy");q.cost=int(q.price)*qty
	if not P.number(q.price,1,1000000000,true) or not P.number(q.cost,1,P.COINS,true):return q
	if not c.LawOps.allow_player(c,p,"fuel"):q.message="Current trading terms do not permit this fuel purchase.";return q
	for value in [c.state.get("coins"),p.get("cash")]:
		if not P.number(value,0,P.COINS,true):q.message="Both actual trade purses must hold finite whole coins.";return q
	if int(c.state.coins)<int(q.cost) or float(p.cash)>P.COINS-float(q.cost):q.message="Actual buyer funds or seller purse room cannot cover this purchase.";return q
	if not P.number(p.get("stocks",{}).get("fuel",0)) or not P.number(c.state.get("cargo",{}).get("fuel",0)):return q
	if floori(Reserves.exportable(p,"fuel"))<qty:q.message="Naphtha has insufficient fuel for sale beyond its operating reserves.";return q
	if float(c.cargo_weight())+float(Goods.ITEMS.fuel.weight)*qty>float(c.capacity()):q.message="The actual traveling holds lack room for that fuel.";return q
	q.ok=true;q.message="Buy %d actual fuel for %d coins into your holds; passage alone owns none."%[qty,int(q.cost)]
	return q

static func buy_fuel(c,qty: int) -> Dictionary:
	var q: Dictionary=fuel_quote(c,qty)
	return c.trade(PORT,"fuel",qty,"buy") if q.ok else q

static func before_trade(c,id: String,good: String,qty: int,side: String) -> Dictionary:
	if id!=PORT or good!="fuel" or side!="buy":return {}
	var q: Dictionary=fuel_quote(c,qty)
	if not q.ok:return {}
	var p: Dictionary=c.current_port()
	return {"port":PORT,"day":float(c.state.day),"qty":qty,"price":q.price,"cost":q.cost,"buyerBefore":c.state.coins,"sellerBefore":p.cash,"stockBefore":p.stocks.get("fuel",0),"holdBefore":c.state.cargo.get("fuel",0)}

static func after_trade(c,before: Dictionary,result: Dictionary) -> void:
	# LawOps trades on a copy and publishes nested containers: reacquire now.
	var w: Dictionary=work(c)
	if before.is_empty() or not result.get("ok",false) or record(c).get("stage","")!="fuel_work118" or w.is_empty() or not w.fuel.is_empty():return
	if not P.shape(before,V.BEFORE_FIELDS) or not P.same_value(before.get("day"),c.state.get("day")):return
	if not P.number(result.get("qty"),1,1000000,true) or not P.number(result.get("total"),1,P.COINS,true) or not P.number(result.get("coins"),1,P.COINS,true):return
	if not P.same_value(result.qty,before.qty) or not P.same_value(result.total,before.cost) or not P.same_value(result.coins,before.cost):return
	var p: Dictionary=c.current_port()
	if str(p.get("id",""))!=PORT or not c.state.get("path",[]).is_empty() or not _access(c,p).get("legal",false):return
	var receipt: Dictionary=before.duplicate(true)
	receipt.buyerAfter=c.state.get("coins");receipt.sellerAfter=p.get("cash");receipt.stockAfter=p.get("stocks",{}).get("fuel");receipt.holdAfter=c.state.get("cargo",{}).get("fuel")
	if not V.fuel_valid(receipt,float(w.startedDay),float(c.state.day)):return
	if w.passage.is_empty():w.passage={"port":PORT,"mode":"legal","day":float(c.state.day),"cost":0,"claim":int(_access(c,p).get("claim",0)),"until":0.0}
	w.fuel=receipt
	c.log_entry("Fuel Has Owners: bought %d Naphtha fuel; %d actual coins reached the seller."%[int(receipt.qty),int(receipt.cost)])

static func _admission(c) -> bool:
	return record(c).get("stage","")=="warrant_work118" and work(c).get("fuelReported",false) and work(c).get("attempt",{}).is_empty() and not work(c).get("warrantReported",false) and c.state.get("voyageJobs",[]).size()<c.VoyageJobs.MAX_ACTIVE and c.EscortOps.contracted(c).is_empty()

static func warrant_offers(c) -> Array:
	var rows: Array=[]
	if not _admission(c):return rows
	var brass: Dictionary=c.port(BRASS)
	if brass.is_empty():return rows
	for sight in c.NavalAI.sightings(c.state):
		if not sight.get("current",false):continue
		var owner: String=str(sight.get("ownerId",""))
		var patrol: Dictionary=c.NavalAI._find_patrol(c.state,owner)
		if patrol.is_empty() or c.distance(patrol,brass)>1800.0 or c.distance(patrol,c.state.position)>600.0:continue
		var offer: Dictionary=c.EscortOps.offer(c,owner)
		if offer.is_empty() or V.earlier_job(record(c),str(offer.id)) or rows.any(func(row):return row.id==offer.id):continue
		rows.append(offer.duplicate(true))
	rows.sort_custom(func(a,b):return str(a.id)<str(b.id))
	return rows

static func warrant_quote(c,offer: Dictionary) -> Dictionary:
	var q: Dictionary={"ok":false,"message":"No matching loaded passage can presently be contracted near Brass. Continue ordinary sailing, or return to Brass to report the work unresolved.","offer":{},"reserve":{}}
	for row in warrant_offers(c):
		if P.same_value(P.terms(row),P.terms(offer)):q.offer=row;break
	if q.offer.is_empty():return q
	if not P._binding(P.identity(q.offer),c.state,0.0):return q
	var client: Dictionary=c.fleet_owner(str(q.offer.ownerId))
	if not P.number(client.get("coins"),float(q.offer.reward),P.COINS,true):q.message="The actual owner cannot fund an exact whole-coin escort fee.";return q
	q.reserve=c.Arc110.reserve_quote(c,q.offer)
	if not q.reserve.get("readyForAllowance",false):q.message="Fund actual payroll, food, loaded fuel, return and contingency reserves before accepting the held fee.";return q
	q.ok=true;q.message="Record this owner's current claimant request and hold its escort fee. The request establishes neither a past guarantee payment nor guilt."
	return q

static func accept_warrant(c,quoted: Dictionary) -> Dictionary:
	if not quoted.get("ok",false) or not quoted.get("offer") is Dictionary:return c.fail("Review a fresh warrant quote first.")
	var q: Dictionary=warrant_quote(c,quoted.offer)
	if not q.ok:return q
	var owner: Dictionary=c.fleet_owner(str(q.offer.ownerId))
	var crew: Array=[]
	for uid in q.offer.escort.carrierUids:
		var boat: Dictionary={}
		for row in owner.get("boats",[]):
			if row.get("uid")==uid:boat=row;break
		if boat.is_empty() or not P.number(boat.get("crew"),0,1000000,true):return c.fail("An original carrier's actual crew observation is unavailable.")
		crew.append({"uid":uid,"crew":boat.crew})
	var patrol: Dictionary=c.NavalAI._find_patrol(c.state,str(q.offer.ownerId))
	var origin: Dictionary={"x":patrol.x,"y":patrol.y,"playerX":c.state.position.x,"playerY":c.state.position.y}
	var result: Dictionary=c.VoyageJobs.accept_escort(c,str(q.offer.ownerId),int(q.offer.reward))
	if not result.get("ok",false):return result
	var job: Dictionary=c.VoyageJobs._find(c.state,str(q.offer.id))
	work(c).attempt={"binding":P.identity(job),"claimDay":float(c.state.day),"claimStatus":"unverified","origin":origin,"crew":crew,"status":"carried","closure":{},"follow":false,"followClock":0.0}
	c.log_entry("%s: claimant request recorded; held escort fee %d coins. The claim is unverified."%[str(owner.get("name","The convoy owner")),int(job.reward)])
	return result

static func _observations(c,b: Dictionary) -> Array:
	var rows: Array=[]
	var owner: Dictionary=c.fleet_owner(str(b.ownerId))
	var patrol: Dictionary=c.NavalAI._find_patrol(c.state,str(b.ownerId))
	var seen: bool=false
	if not patrol.is_empty() and c.distance(patrol,c.state.position)<=c.EscortOps.CONTRACT_RADIUS:
		for sight in c.NavalAI.sightings(c.state):
			if sight.get("current",false) and str(sight.get("ownerId",""))==str(b.ownerId):seen=true;break
		var here: Dictionary=c.current_port()
		if not here.is_empty() and str(owner.get("atPort",""))==str(here.id) and patrol.get("holding",false) and c.distance(patrol,here)<40.0:seen=true
	for uid in b.carrierUids:
		var observation: Dictionary={"uid":uid,"state":"unobserved","crew":-1}
		if not seen:rows.append(observation);continue
		for boat in owner.get("boats",[]):
			if boat.get("uid")!=uid:continue
			observation.state="sunk" if boat.get("sunk",false) else ("captured" if boat.get("captureSecured",false) else "afloat")
			if P.number(boat.get("crew"),0,1000000,true):observation.crew=boat.crew
			break
		rows.append(observation)
	return rows

static func after_job(c,before: Dictionary,result: Dictionary,abandon: bool) -> void:
	var a: Dictionary=active(c)
	if a.is_empty() or not result.get("ok",false) or not P.same_value(P.identity(before),a.binding):return
	var b: Dictionary=a.binding
	if not c.state.get("doneVoyageJobs",[]).has(str(b.jobId)) or not c.VoyageJobs._find(c.state,str(b.jobId)).is_empty():return
	var sale: Dictionary={}
	var payment: int=0
	if not abandon:
		var receipt: Dictionary=c.state.get("lastEscortVoyage",{})
		var settled: Dictionary=receipt.get("job",{})
		if not P.same_value(P.identity(settled),b) or not P.number(result.get("reward"),1,P.COINS,true) or not P.number(receipt.get("payment"),1,P.COINS,true):return
		if not P.same_value(result.reward,b.reward) or not P.same_value(receipt.payment,b.reward) or receipt.get("deliveryPort")!=b.targetPort or not P.same_value(receipt.get("paidDay"),c.state.day):return
		sale=P.sale(settled)
		if not P.sale_valid(sale,b,float(c.state.day)) or settled.get("failed",false) or not settled.get("escort",{}).get("arrived",false) or settled.escort.get("battlePending",false):return
		payment=int(b.reward)
	a.status="abandoned" if abandon else "paid";a.follow=false
	a.closure={"jobId":str(b.jobId),"ownerId":str(b.ownerId),"status":str(a.status),"day":float(c.state.day),"payment":payment,"sale":sale,"observations":_observations(c,b)}
	var owner_name: String=str(c.fleet_owner(str(b.ownerId)).get("name","The convoy owner"))
	c.log_entry("%s paid you %d coins after delivery."%[owner_name,payment] if not abandon else "%s's escort was abandoned. No delivery fee was earned; the recorded boat and crew observations remain."%owner_name)

static func follow(c,enabled: bool) -> Dictionary:
	var a: Dictionary=active(c)
	var job: Dictionary=c.VoyageJobs._find(c.state,str(a.get("binding",{}).get("jobId","")))
	if a.is_empty() or job.is_empty() or job.get("state")!="active" or job.get("failed",false):return c.fail("There is no active original warrant convoy to follow.")
	if not c.home_local064() or job.escort.get("battlePending",false):return c.fail("Resume following after the actual encounter settles.")
	a.follow=enabled;a.followClock=0.0
	if not enabled:c.stop_sailing()
	return c.ok("Following the original warrant convoy." if enabled else "Warrant following stopped; the escort contract remains open.")

static func cancel_follow(c) -> void:
	var a: Dictionary=active(c)
	if not a.is_empty():a.follow=false

static func follow_step(c,dt: float) -> void:
	var a: Dictionary=active(c)
	if not a.get("follow",false) or not is_finite(dt) or dt<0:return
	a.followClock=maxf(0.0,float(a.followClock)-dt)
	if a.followClock>0:return
	a.followClock=1.0
	var job: Dictionary=c.VoyageJobs._find(c.state,str(a.binding.jobId))
	if job.is_empty() or job.get("state")!="active" or job.get("failed",false) or not c.home_local064():c.stop_sailing();return
	if job.escort.get("battlePending",false):return
	if job.escort.get("arrived",false):c.stop_sailing();return
	var p: Dictionary=c.NavalAI._find_patrol(c.state,str(a.binding.ownerId))
	if p.is_empty() or c.distance(c.state.position,p)>c.EscortOps.CONTRACT_RADIUS:c.stop_sailing();return
	var points: Array=c.remaining_patrol_course(p)
	var target: Dictionary={"x":float(p.x),"y":float(p.y)} if points.is_empty() else points[0]
	var plotted: Dictionary=c.chart_course(target)
	a.follow=bool(plotted.get("ok",false))
	if not a.follow:c.stop_sailing()

static func follow_speed(c,ordinary: float) -> float:
	var a: Dictionary=active(c)
	if not a.get("follow",false):return ordinary
	var job: Dictionary=c.VoyageJobs._find(c.state,str(a.binding.jobId))
	var owner: Dictionary=c.fleet_owner(str(a.binding.ownerId))
	var p: Dictionary=c.NavalAI._find_patrol(c.state,str(a.binding.ownerId))
	if job.get("state")!="active" or job.get("failed",false) or owner.is_empty() or p.is_empty() or c.distance(c.state.position,p)>220:return ordinary
	var pace: float=float(c.NavalAI.fleet_performance(owner).speed)*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0))
	return minf(ordinary,maxf(0,pace))

static func gate(c,rule: Dictionary={}) -> Dictionary:
	match str(rule.get("mode","")):
		"fuel":return choice_gate(c,"report_fuel118")
		"fuel_reported":return choice_gate(c,"next_warrant118")
		"warrant":
			var paid: Dictionary=choice_gate(c,"report_warrant118")
			return paid if paid.ok else choice_gate(c,"report_unresolved118")
		"warrant_reported":return choice_gate(c,"next_passage118")
		"optional":return c.ok("Tobin's optional discussion commissions nothing; leaving remains available.")
	return c.fail("This chapter condition is unavailable.")

static func choice_gate(c,choice: String) -> Dictionary:
	if choice in ["leave_tobin118","finish_tobin118"]:return c.ok("You may leave without paying or commissioning help.")
	if choice=="discuss_funding118":
		var optional: Dictionary=c.state.get("stories",{}).get("chains",{}).get(OPTIONAL,{})
		var funding: Dictionary=record(c).get("work117",{})
		if not funding.get("reported",false) or funding.get("model") not in ["mutual","separate"]:return c.fail("Record the chosen harbor funding account before discussing its results with Tobin. You may still leave.")
		return c.ok("Discuss the actual current funding facts; no help is commissioned.") if optional.get("stage")=="later_tobin118" and not optional.get("done",false) and str(c.current_port().get("id",""))==BRASS and work(c).get("tobin",{}).is_empty() else c.fail("Meet Tobin at Brass when his existing later conversation is open.")
	if not STEPS.has(choice):return c.ok("")
	if record(c).get("stage")!=STEPS[choice][0]:return c.fail("That chapter decision is not currently open.")
	var w: Dictionary=work(c)
	match choice:
		"begin_fuel118":
			if not record(c).get("work117",{}).get("reported",false):return c.fail("Record the harbor funding account first.")
		"report_fuel118":
			if w.get("fuelReported",false) or not V.fuel_valid(w.get("fuel",{}),float(w.get("startedDay",-1)),float(c.state.day)):return c.fail("Make the first actual paid Naphtha fuel purchase before reporting ownership.")
		"next_warrant118","begin_warrant118":
			if not w.get("fuelReported",false) or w.get("warrantReported",false):return c.fail("Record the fuel ownership account first.")
		"report_warrant118","report_unresolved118":
			if str(c.current_port().get("id",""))!=BRASS or not c.state.get("path",[]).is_empty() or w.get("warrantReported",false):return c.fail("Stop at Brass to record the warrant account once.")
			var a: Dictionary=w.get("attempt",{})
			if choice=="report_unresolved118":
				if not c.EscortOps.contracted(c).is_empty() or (not a.is_empty() and (a.get("status")!="abandoned" or a.get("closure",{}).get("status")!="abandoned")):return c.fail("Close any carried escort before reporting the work unresolved. A completed paid passage has its own account.")
			elif a.get("status")!="paid" or a.get("closure",{}).get("status")!="paid":return c.fail("Deliver the original cargo and receive the held escort fee before reporting a paid passage.")
		"next_passage118":
			if not w.get("warrantReported",false):return c.fail("Record the honest warrant account first.")
	return c.ok("Record this decision.")

static func after_choice(c,choice: String,result: Dictionary) -> void:
	if not result.get("ok",false):return
	if choice=="discuss_funding118":
		var funding: Dictionary=record(c).get("work117",{})
		if funding.get("reported",false) and funding.get("model") in ["mutual","separate"] and c.state.get("stories",{}).get("chains",{}).get(OPTIONAL,{}).get("stage")=="tobin_funding118":
			var optional_work: Dictionary=_ensure(c)
			if not optional_work.is_empty() and optional_work.tobin.is_empty():optional_work.tobin={"day":float(c.state.day)}
		return
	if not STEPS.has(choice) or record(c).get("stage")!=STEPS[choice][1]:return
	var w: Dictionary=_ensure(c)
	if w.is_empty():return
	match choice:
		"begin_fuel118":
			if float(w.startedDay)<0:w.startedDay=float(c.state.day)
		"report_fuel118":
			if not w.fuelReported and V.fuel_valid(w.fuel,float(w.startedDay),float(c.state.day)):w.fuelReported=true;w.fuelReportDay=float(c.state.day)
		"begin_warrant118":
			if w.fuelReported and float(w.warrantDay)<0:w.warrantDay=float(c.state.day)
		"report_warrant118","report_unresolved118":
			if w.warrantReported:return
			var a: Dictionary=w.attempt
			if str(c.current_port().get("id",""))!=BRASS or not c.state.get("path",[]).is_empty():return
			if choice=="report_warrant118" and (a.get("status")!="paid" or a.get("closure",{}).get("status")!="paid"):return
			if choice=="report_unresolved118" and (not c.EscortOps.contracted(c).is_empty() or (not a.is_empty() and (a.get("status")!="abandoned" or a.get("closure",{}).get("status")!="abandoned"))):return
			w.warrantReported=true;w.warrantReportDay=float(c.state.day);w.warrantPort=str(c.current_port().get("id",""));w.resolution="unresolved" if a.is_empty() else str(a.status)

static func view(c) -> Dictionary:
	var w: Dictionary=work(c)
	var q: Dictionary=passage_quote(c)
	var access: String=str(q.message)
	if not w.get("passage",{}).is_empty():access="Naphtha access was recorded for %s coins. Current harbor permissions still apply; the pass owns no fuel and protects against no fleets."%str(w.passage.cost)
	var fuel: String="No fresh paid Naphtha fuel purchase recorded. Existing working tank fuel is not a purchase."
	if not w.get("fuel",{}).is_empty():fuel="Bought %s Naphtha fuel for %s actual coins on day %.2f; the seller received the money and your holds received the fuel."%[str(w.fuel.qty),str(w.fuel.cost),float(w.fuel.day)]
	var warrant: String="No claimant passage has been contracted. A nearby loaded convoy must be sighted and able to pay its fee; any current claim remains unverified."
	var a: Dictionary=w.get("attempt",{})
	if not a.is_empty():
		var convoy_name: String=str(c.fleet_owner(str(a.binding.ownerId)).get("name","The convoy owner"))
		var destination: String=str(c.port(str(a.binding.targetPort)).get("name","the delivery harbor"))
		warrant="%s's current claimant request remains unverified. Escort the original cargo to %s; %d owner-paid coins are held for delivery."%[convoy_name,destination,int(a.binding.reward)]
		if a.status=="paid":warrant="%s paid you %d coins after its original cargo sold at %s. This proves the delivery, not a past guarantee payment, crew guilt or a rescue."%[convoy_name,int(a.closure.payment),destination]
		elif a.status=="abandoned":warrant="%s's escort was abandoned. No delivery fee was earned. Its recorded losses and crew observations remain; no rescue is claimed."%convoy_name
		var job: Dictionary=c.VoyageJobs._find(c.state,str(a.binding.jobId))
		if job.get("state")=="expired" or job.get("failed",false):warrant="%s's escort has ended without delivery. Close the carried contract before reporting it unresolved; no rescue is claimed."%convoy_name
	elif w.get("resolution","")=="unresolved":warrant="Unresolved at Brass: no warrant escort was undertaken, no fee was earned and no rescue or culpability was proved."
	var prior: Dictionary=record(c).get("work117",{})
	var attempts: Array=prior.get("attempts",[])
	var last: Dictionary={} if attempts.is_empty() else attempts[-1]
	var payment=last.get("closure",{}).get("payment",0) if last.get("status")=="paid" else 0
	var terms: String="mutual harbor contributions" if prior.get("model")=="mutual" else ("separate owner bonds" if prior.get("model")=="separate" else "no chosen funding terms")
	var funding_owner: String=str(c.fleet_owner(str(last.get("binding",{}).get("ownerId",""))).get("name","The convoy owner"))
	var tobin: String="Funding terms: %s. "%terms
	tobin+="%s paid you %s coins after delivery. "%[funding_owner,str(payment)] if float(payment)>0 else "No escort fee has been received. "
	tobin+="%s received %s coins in refunds; %s coins were returned to harbor contributors."%[funding_owner,str(last.get("refund",0)),str(last.get("reimbursed",0))]
	tobin+=" The funding account is recorded." if prior.get("reported",false) else " The funding account has not been reported."
	for row in last.get("contributions",[]):
		var port: Dictionary=c.port(str(row.portId))
		tobin+=" %s contributed %s coins; its government purse now holds %s coins."%[str(port.get("name","The contributing harbor")),str(row.amount),str(port.get("governmentPurse","an unconfirmed amount of"))]
	tobin+=" Discussion commissions and pays for no help; you may leave."
	return {"passageLabel":access,"fuelLabel":fuel,"warrantLabel":warrant,"tobinLabel":tobin}
