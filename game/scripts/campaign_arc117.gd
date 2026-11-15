extends RefCounted
## Chapter records are receipts, never purses. Native escort admission,
## movement, original cargo sale, escrow and closure keep their authority.
const V=preload("res://scripts/campaign_validation117.gd")
const ID: String="common_passage110"
const INTRO: String="who_pays117"
const WORK: String="funding_work117"
const ACCOUNT: String="funding_account117"
const NEXT: String="fuel_has_owners118"
const MODELS: Dictionary={"choose_mutual117":"mutual","choose_separate117":"separate"}

static func record(c) -> Dictionary:
	return c.state.get("stories",{}).get("chains",{}).get(ID,{})

static func work(c) -> Dictionary:
	return record(c).get("work117",{})

static func attempt(c) -> Dictionary:
	var rows: Array=work(c).get("attempts",[])
	return {} if rows.is_empty() else rows[-1]

static func active(c) -> Dictionary:
	var a: Dictionary=attempt(c)
	return a if a.get("status","")=="carried" and not work(c).get("reported",false) else {}

static func _ensure(c) -> Dictionary:
	var rec: Dictionary=record(c)
	if rec.is_empty():return {}
	if not rec.has("work117"):
		rec.work117={"schema":1,"model":"","choiceId":"","selectedDay":-1.0,"attempts":[],"reported":false,"reportDay":-1.0,"mara":{}}
	return rec.work117

static func _admission(c) -> Dictionary:
	var w: Dictionary=work(c)
	if record(c).get("stage","")!=WORK or w.get("model","") not in ["mutual","separate"] or w.get("reported",false):return c.fail("Choose the harbor funding terms at Anvil Dock first.")
	if w.get("attempts",[]).size()>=8:return c.fail("The eight recorded funding attempts are exhausted; their accounts remain available.")
	var a: Dictionary=attempt(c)
	if not a.is_empty() and (a.status!="abandoned" or int(a.reimbursed)!=_contributed(a)):return c.fail("Close the previous escort and return its actual harbor contributions before another attempt.")
	if c.state.get("voyageJobs",[]).size()>=c.VoyageJobs.MAX_ACTIVE:return c.fail("Finish or abandon a carried voyage job first.")
	if not c.EscortOps.contracted(c).is_empty():return c.fail("Finish or abandon the existing escort first.")
	return c.ok("A fresh funded passage may be considered.")

static func offers(c) -> Array:
	var rows: Array=[]
	if not _admission(c).ok:return rows
	for sight in c.NavalAI.sightings(c.state):
		if not sight.get("current",false):continue
		var q: Dictionary=c.EscortOps.offer(c,str(sight.get("ownerId","")))
		if not q.is_empty() and not rows.any(func(row):return row.id==q.id):rows.append(q.duplicate(true))
	rows.sort_custom(func(a,b):return str(a.id)<str(b.id))
	return rows

static func quote(c,terms: Dictionary) -> Dictionary:
	var admission: Dictionary=_admission(c)
	if not admission.ok:return admission
	var live: Dictionary={}
	for row in offers(c):
		if V.same_value(V.terms(row),V.terms(terms)):live=row;break
	if live.is_empty():return c.fail("No matching fresh loaded offer is available. Reacquire the actual trader and review its terms.")
	if str(live.id)==str(record(c).get("work116",{}).get("priority",{}).get("jobId","")):return c.fail("The previous convoy operation cannot be reused for this funding account.")
	var reserve: Dictionary=c.Arc110.reserve_quote(c,live)
	if not reserve.get("readyForAllowance",false):return c.fail("Fund your payroll, food, loaded fuel, return and contingency reserves before accepting an escort fee.")
	var fee: int=int(live.reward)
	var shares: Array=[]
	if work(c).model=="mutual":
		var departure: String=str(live.escort.fromPort)
		var target: String=str(live.targetPort)
		if departure==target or fee<2:return c.fail("Mutual terms need two distinct actual harbors and two positive coin shares.")
		shares=[{"portId":departure,"amount":floori(float(fee)/2.0)},{"portId":target,"amount":fee-floori(float(fee)/2.0)}]
		for share in shares:
			var p: Dictionary=c.port(share.portId)
			if p.is_empty() or not V.number(p.get("governmentPurse"),float(share.amount),V.COINS,true):return c.fail("The named harbor government cannot fund its quoted share from its actual purse.")
	return {"ok":true,"message":"Current escort terms; reviewing this quote moves no coins.","offer":live.duplicate(true),"model":str(work(c).model),"contributions":shares,"reserve":reserve}

static func _contributed(a: Dictionary) -> int:
	var amount: int=0
	for row in a.get("contributions",[]):amount+=int(row.amount)
	return amount

static func _transfer(c,client: Dictionary,shares: Array,to_client: bool) -> bool:
	# Distinct real purses, fully preflighted before the first synchronous move.
	var total: int=0
	var ports: Array=[]
	for row in shares:
		var p: Dictionary=c.port(str(row.portId))
		if p.is_empty() or is_same(p,client) or ports.any(func(prior):return is_same(prior,p)):return false
		if not V.number(p.get("governmentPurse"),0,V.COINS,true) or not V.number(row.amount,1,V.COINS,true):return false
		if to_client and int(p.governmentPurse)<int(row.amount):return false
		if not to_client and int(p.governmentPurse)>int(V.COINS)-int(row.amount):return false
		ports.append(p);total+=int(row.amount)
	if not V.number(client.get("coins"),0,V.COINS,true):return false
	if (to_client and int(client.coins)>int(V.COINS)-total) or (not to_client and int(client.coins)<total):return false
	var moved: int=0
	for i in range(shares.size()):
		var ok: bool=c.Money.move(ports[i],"governmentPurse",client,"coins",int(shares[i].amount),"Harbor contribution to convoy escort",c.state.moneyLog) if to_client else c.Money.move(client,"coins",ports[i],"governmentPurse",int(shares[i].amount),"Returned actual abandoned escort contribution",c.state.moneyLog)
		if not ok:
			for j in range(moved-1,-1,-1):
				if to_client:c.Money.move(client,"coins",ports[j],"governmentPurse",int(shares[j].amount),"Reversed unadmitted harbor contribution",c.state.moneyLog)
				else:c.Money.move(ports[j],"governmentPurse",client,"coins",int(shares[j].amount),"Reversed incomplete contribution return",c.state.moneyLog)
			return false
		moved+=1
	return true

static func accept(c,quoted: Dictionary) -> Dictionary:
	if not quoted.get("ok",false) or not quoted.get("offer") is Dictionary:return c.fail("Review a current funding quote first.")
	var q: Dictionary=quote(c,quoted.offer)
	if not q.ok:return q
	if quoted.get("model")!=q.model or not V.same_value(quoted.get("contributions"),q.contributions):return c.fail("The selected funding terms changed; review them again.")
	var shown: Dictionary=q.offer
	if c.VoyageJobs._is_closed(c.state,str(shown.id)) or not c.VoyageJobs._find(c.state,str(shown.id)).is_empty():return c.fail("This passage has already been accepted or closed.")
	var client: Dictionary=c.fleet_owner(str(shown.ownerId))
	if client.is_empty() or not _transfer(c,client,q.contributions,true):return c.fail("The actual contribution purses changed. No escort was admitted.")
	var result: Dictionary=c.VoyageJobs.accept_escort(c,str(shown.ownerId),int(shown.reward))
	if not result.get("ok",false):
		# Native admission has no failing branch after its client->escrow move.
		_transfer(c,client,q.contributions,false)
		return result
	var job: Dictionary=c.VoyageJobs._find(c.state,str(shown.id))
	# The synchronous native success appended this authoritative original job.
	var binding: Dictionary=V.identity(job)
	work(c).attempts.append({"binding":binding,"contributions":q.contributions.duplicate(true),"refund":0,"refundDay":-1.0,"reimbursed":0,"status":"carried","closure":{},"follow":false,"followClock":0.0})
	var funding_name: String="Mutual harbor funding" if str(work(c).model)=="mutual" else "Owner bond"
	c.log_entry("%s: %d coins held for %s. Payment follows the contracted delivery."%[funding_name,int(binding.reward),str(client.get("name","the convoy"))])
	return result

static func observe_refund(c,job: Dictionary,amount: int) -> void:
	var a: Dictionary=active(c)
	if a.is_empty() or amount<=0 or not V.same_value(V.identity(job),a.binding):return
	var live: Dictionary=c.VoyageJobs._find(c.state,str(a.binding.jobId))
	if live.is_empty() or not is_same(live,job) or int(a.refund)+amount>int(a.binding.reward):return
	if int(a.refund)+amount!=int(a.binding.reward)-int(job.get("escrow",-1)):return
	a.refund=int(a.refund)+amount;a.refundDay=float(c.state.day)

static func after_job(c,before: Dictionary,result: Dictionary,abandon: bool) -> void:
	var a: Dictionary=active(c)
	if a.is_empty() or not result.get("ok",false) or not V.same_value(V.identity(before),a.binding):return
	var b: Dictionary=a.binding
	if not c.state.get("doneVoyageJobs",[]).has(str(b.jobId)) or not c.VoyageJobs._find(c.state,str(b.jobId)).is_empty():return
	if abandon:
		a.status="abandoned";a.follow=false
		a.closure={"jobId":str(b.jobId),"ownerId":str(b.ownerId),"status":"abandoned","day":float(c.state.day),"payment":0,"sale":{}}
		settle_refund(c)
		return
	var receipt: Dictionary=c.state.get("lastEscortVoyage",{})
	var settled: Dictionary=receipt.get("job",{})
	if not V.same_value(V.identity(settled),b) or int(result.get("reward",-1))!=int(b.reward) or int(receipt.get("payment",-1))!=int(b.reward) or str(receipt.get("deliveryPort",""))!=str(b.targetPort) or float(receipt.get("paidDay",-1))!=float(c.state.day):return
	var sale: Dictionary=V.sale(settled)
	if int(a.refund)!=0 or not V.sale_valid(sale,b,float(c.state.day)) or settled.get("failed",false) or not settled.get("escort",{}).get("arrived",false) or settled.get("escort",{}).get("battlePending",false):return
	a.status="paid";a.follow=false
	a.closure={"jobId":str(b.jobId),"ownerId":str(b.ownerId),"status":"paid","day":float(c.state.day),"payment":int(b.reward),"sale":sale}
	c.log_entry("Funding account: the original cargo sold and the actual held escort fee was paid once.")

static func settle_refund(c) -> Dictionary:
	var a: Dictionary=attempt(c)
	if a.is_empty() or a.get("status","")!="abandoned" or a.get("closure",{}).get("status","")!="abandoned":return c.fail("Only a closed abandoned escort can return harbor contributions.")
	var due: int=_contributed(a)
	if int(a.reimbursed)==due:return c.ok("No harbor contribution remains to return.")
	var b: Dictionary=a.binding
	if not c.VoyageJobs._find(c.state,str(b.jobId)).is_empty():return c.fail("The escort contract has not closed.")
	var client: Dictionary=c.fleet_owner(str(b.ownerId))
	var funds: int=int(client.get("coins",0))
	var shortfall: int=maxi(0,maxi(due-int(a.refund),due-funds))
	if client.is_empty() or shortfall>0:return {"ok":false,"message":"The abandoned contribution remains unsettled: recorded refund and actual client funds must cover both shares.","shortfall":shortfall,"needed":due,"refund":int(a.refund)}
	if not _transfer(c,client,a.contributions,false):return c.fail("The original contributor purses cannot receive an atomic return yet; the obligation remains unsettled.")
	a.reimbursed=due
	return c.ok("Returned both harbor contributions from the client's received refund.")

static func follow(c,enabled: bool) -> Dictionary:
	var a: Dictionary=active(c)
	var job: Dictionary=c.VoyageJobs._find(c.state,str(a.get("binding",{}).get("jobId","")))
	if a.is_empty() or job.is_empty() or job.get("state","")!="active" or job.get("failed",false):return c.fail("There is no active contracted convoy to follow.")
	if not c.home_local064() or job.escort.get("battlePending",false):return c.fail("Resume following after the physical encounter settles.")
	a.follow=enabled;a.followClock=0.0
	if not enabled:c.stop_sailing()
	return c.ok("Following the contracted original convoy." if enabled else "Convoy following stopped; its contract remains open.")

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
	if job.is_empty() or job.get("state","")!="active" or job.get("failed",false) or not c.home_local064():c.stop_sailing();return
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
	var owner: Dictionary=c.fleet_owner(str(a.binding.ownerId))
	var p: Dictionary=c.NavalAI._find_patrol(c.state,str(a.binding.ownerId))
	if owner.is_empty() or p.is_empty() or c.distance(c.state.position,p)>220:return ordinary
	var pace: float=float(c.NavalAI.fleet_performance(owner).speed)*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0))
	return minf(ordinary,maxf(0,pace))

static func _summary(q: Dictionary) -> Dictionary:
	var out: Dictionary={}
	for key in V.QUOTE_FIELDS:out[key]=q.get(key)
	return out.duplicate(true)

static func damaged_hulls(c) -> Array:
	var rows: Array=[]
	var p: Dictionary=c.current_port()
	if str(p.get("id",""))!="anvil_dock":return rows
	for boat in c.state.get("fleet",[]):
		if boat.get("sunk",false) or str(boat.get("storedPort","")) not in ["","anvil_dock"]:continue
		var q: Dictionary=c.service_quote(boat,p)
		var summary: Dictionary=_summary(q)
		if q.get("ok",false) and V.quote_valid(summary):rows.append({"uid":str(boat.uid),"name":str(boat.get("name",boat.uid)),"quote":summary})
	return rows

static func select_hull(c,uid: String) -> Dictionary:
	var optional: Dictionary=c.state.get("stories",{}).get("chains",{}).get("mara_work113",{})
	if optional.get("stage","")!="later_mara117" or optional.get("done",false):return c.fail("Mara's later conversation is not open.")
	if work(c).get("mara",{}).get("discussed",false):return c.fail("Mara's recorded estimate discussion is already complete.")
	for row in damaged_hulls(c):
		if row.uid!=uid:continue
		var w: Dictionary=_ensure(c)
		if w.is_empty():return c.fail("The campaign record is unavailable.")
		w.mara={"uid":uid,"port":"anvil_dock","day":float(c.state.day),"quote":row.quote.duplicate(true),"discussed":false}
		return c.ok("Selected the actual owned damaged hull and its current paid-service estimate.")
	return c.fail("That owned damaged hull is not locally available for an estimate.")

static func mara_quote(c) -> Dictionary:
	var m: Dictionary=work(c).get("mara",{})
	for row in damaged_hulls(c):
		if row.uid==str(m.get("uid","")):return {"ok":true,"message":"Actual service quote; no repair commissioned.","uid":row.uid,"quote":row.quote.duplicate(true)}
	return c.fail("Select an actually owned, locally available damaged hull; leaving remains available without one.")

static func gate(c,rule: Dictionary={}) -> Dictionary:
	match str(rule.get("mode","")):
		"funding":return choice_gate(c,"report_funding117")
		"reported":return choice_gate(c,"next_fuel117")
		"optional":return c.ok("Mara's discussion and leaving do not require a repair.")
	return c.fail("Unknown117 campaign gate.")

static func choice_gate(c,choice: String) -> Dictionary:
	if choice=="leave_mara117":return c.ok("You may leave without selecting or repairing a hull.")
	if choice=="discuss_owned_hull117":
		var optional: Dictionary=c.state.get("stories",{}).get("chains",{}).get("mara_work113",{})
		if optional.get("stage","")!="later_mara117" or optional.get("done",false) or work(c).get("mara",{}).get("discussed",false):return c.fail("This optional discussion is not open.")
		var q: Dictionary=mara_quote(c)
		if not q.ok:return q
		return c.ok("Discuss this actual paid-service estimate.") if V.same_value(q.quote,work(c).mara.quote) else c.fail("The hull or service quote changed. Select its current estimate again.")
	if MODELS.has(choice):
		if record(c).get("stage","")!=INTRO or not str(work(c).get("model","")).is_empty():return c.fail("The funding commitment is already chosen or is not yet open.")
		return c.ok("Choose the disclosed funding terms before boarding.") if str(c.current_port().get("id",""))=="anvil_dock" else c.fail("Meet Mara at Anvil Dock to commit the funding terms.")
	if choice=="report_funding117":
		var a: Dictionary=attempt(c)
		if record(c).get("stage","")!=WORK or work(c).get("reported",false) or a.get("status","")!="paid":return c.fail("Complete the loaded escort and collect its held fee before reporting.")
		return c.ok("Report the real escort payment under the chosen funding terms.")
	if choice=="next_fuel117":return c.ok("The funding account is recorded.") if record(c).get("stage","")==ACCOUNT and work(c).get("reported",false) else c.fail("Record the paid funding account first.")
	return c.ok("")

static func after_choice(c,choice: String,result: Dictionary) -> void:
	if not result.get("ok",false):return
	if MODELS.has(choice) and record(c).get("stage","")==WORK:
		var w: Dictionary=_ensure(c)
		if w.is_empty() or not str(w.model).is_empty():return
		w.model=str(MODELS[choice]);w.choiceId=choice;w.selectedDay=float(c.state.day)
	elif choice=="report_funding117" and record(c).get("stage","")==ACCOUNT and attempt(c).get("status","")=="paid" and not work(c).get("reported",false):
		work(c).reported=true;work(c).reportDay=float(c.state.day)
	elif choice=="discuss_owned_hull117":
		var q: Dictionary=mara_quote(c)
		if q.ok and V.same_value(q.quote,work(c).get("mara",{}).get("quote",{})):work(c).mara.discussed=true
