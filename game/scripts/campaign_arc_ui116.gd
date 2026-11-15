extends RefCounted
const Costs=preload("res://scripts/civilian_choices059.gd")
const STAGES=["two_distress116","narrow_withdrawal116","distress_account116"]

static func _owns(entry: Dictionary) -> bool:
	return str(entry.get("chainId",""))=="common_passage110" and str(entry.get("stage","")) in STAGES

static func body(ui,entry: Dictionary,fallback: String) -> String:
	if not _live(ui) or not _owns(entry):return fallback
	var w: Dictionary=ui.host.core.Arc116.work(ui.host.core)
	if w.get("reported",false) or str(entry.stage)=="distress_account116":return fallback
	if w.get("priority",{}).is_empty():return fallback
	if str(w.priority.get("status","carried"))!="carried":return "The escort contract is closed. Review the original boats’ confirmed outcomes and any remaining unknowns before sending the convoy account."
	if w.get("withdrawal",{}).is_empty() and ui.host.core.Arc116.choice_gate(ui.host.core,"begin_withdrawal116").get("ok",false):return "Review the original boats and their remaining load before planning the withdrawal."
	if not w.get("withdrawal",{}).is_empty():return "Keep track of the surviving original boats, their remaining load and crew. A battle escape leaves the contracted delivery and its fee to be settled separately."
	return "The priority is accepted. Accompany its original boats and respond to the actual situation before beginning the withdrawal. No outcome is known for the other convoy."

static func next_action(ui,entry: Dictionary,fallback: String) -> String:
	if not _live(ui) or not _owns(entry):return fallback
	var c=ui.host.core
	var w: Dictionary=c.Arc116.work(c)
	if w.get("reported",false) or str(entry.stage)=="distress_account116":return fallback
	if w.get("priority",{}).is_empty():return fallback
	if w.get("withdrawal",{}).is_empty():
		var first: Dictionary=c.Arc116.choice_gate(c,"begin_withdrawal116")
		return "Review the withdrawal." if first.get("ok",false) else str(first.get("message","Accompany the original boats before reviewing the withdrawal."))
	if str(w.priority.get("status","carried"))!="carried":
		var report: Dictionary=c.Arc116.choice_gate(c,"report_distress116")
		return "Send the convoy account." if report.get("ok",false) else str(report.get("message","Review the carrier records at a harbor."))
	if c.Arc116.delivery_pending(c):return "Accompany the original boats to their delivery harbor; escape alone does not release the fee."
	return "Check the remaining boats and close the escort contract before sending the withdrawal account."

static func controls(ui,body: Node,entry: Dictionary) -> void:
	if not _live(ui) or not _owns(entry):return
	var c=ui.host.core
	var w: Dictionary=c.Arc116.work(c)
	var p: Dictionary=w.get("priority",{})
	var closed: bool=bool(entry.get("done",false)) or bool(w.get("reported",false)) or str(entry.stage)=="distress_account116"
	if not closed:c.NavalAI.observe(c.state)
	if not p.is_empty():
		_summary(ui,body,c,w,p,not closed)
		_fee(ui,body,c,p,not closed)
	if closed:
		ui.paragraph(body,"Account: "+str({"clear":"all original carriers accounted for","partial":"partial withdrawal","lost":"confirmed carrier losses","unconfirmed":"withdrawal unconfirmed"}.get(str(w.get("resolution","")),"no completed withdrawal recorded"))+".",17,ui.GOLD)
		var details: Node=_details(ui,body,"Carrier records and dated sightings")
		if not p.is_empty():_carrier_details(ui,details,c,w,p)
		_reports(ui,details,c,w,false)
		return
	if p.is_empty():
		_reports(ui,body,c,w,str(entry.stage)=="two_distress116")
		if str(entry.stage)=="two_distress116":_offers(ui,body,c,w)
	else:
		var tally: Dictionary=c.Arc116.counts(c)
		if int(tally.get("unresolved",0))>0 or c.Arc116.delivery_pending(c) or w.get("withdrawal",{}).is_empty():_navigation(ui,body,c,w,p)
		var gate: Dictionary=c.Arc116.choice_gate(c,"begin_withdrawal116" if str(entry.stage)=="two_distress116" else "report_distress116")
		if not str(gate.get("message","")).is_empty():ui.paragraph(body,str(gate.message),15,ui.TEAL if gate.get("ok",false) else ui.GOLD)
		var details: Node=_details(ui,body,"Carrier records and dated sightings")
		_carrier_details(ui,details,c,w,p)
		_reports(ui,details,c,w,false)
	var actions=ui.row(body)
	_button(ui,actions,"Coastal watch","watch")
	_button(ui,actions,"Refresh","refresh")

static func _reports(ui,body: Node,c,w: Dictionary,editable: bool) -> void:
	var noted: Array=[]
	for row in w.get("reports",[]):
		var id: String=str(row.get("ownerId",""))
		noted.append(id)
		_report_row(ui,body,c,row,"Priority sighting" if id==str(w.get("priority",{}).get("ownerId","")) else "Noted sighting")
		if editable:_button(ui,body,"Refresh this dated report","note",{"owner":id})
		elif not w.get("priority",{}).is_empty() and id!=str(w.priority.ownerId):ui.paragraph(body,"Other convoy: this dated sighting records no later arrival, loss or rescue.",15)
	if not editable:return
	ui.paragraph(body,"%d / 2 distinct reports noted. A second dated report needs no return to the first convoy."%noted.size(),15)
	if noted.size()>=2:return
	for row in c.Arc116.reports(c):
		var id: String=str(row.get("ownerId",""))
		if noted.has(id):continue
		_report_row(ui,body,c,row,"Available sighting")
		_button(ui,body,"Note this convoy report","note",{"owner":id})
	if c.Arc116.reports(c).is_empty():ui.paragraph(body,"No loaded convoy sighting is available. Review coastal traffic and return when a report is available.",16,ui.GOLD)

static func _report_row(ui,body: Node,c,row: Dictionary,prefix: String) -> void:
	ui.paragraph(body,"%s: %s, day %.2f (%.2f days ago). %.2f %s toward %s."%[prefix,str(row.get("name","Observed trader")),float(row.get("day",0)),maxf(0,float(c.state.day)-float(row.get("day",0))),float(row.get("cargoQuantity",0)),_good(c,str(row.get("cargoGood",""))),_port(c,str(row.get("targetPort","")))],16,ui.GOLD)

static func _offers(ui,body: Node,c,w: Dictionary) -> void:
	var noted: Array=[]
	for row in w.get("reports",[]):noted.append(str(row.get("ownerId","")))
	var offers: Array=c.Arc116.offers(c)
	if offers.is_empty():ui.paragraph(body,"No current funded Kelp departure is within hailing range. Reacquire a noted loaded convoy within 600 water units; its captain keeps sailing.",16,ui.GOLD)
	for q in offers.slice(0,3):
		var reserve: Dictionary=c.Arc110.reserve_quote(c,q)
		ui.paragraph(body,"%s: %.2f %s in %d original loaded boats; %s coins payable after delivery. Deadline day %.2f."%[str(q.get("title","Current escort offer")),float(q.escort.tradeQty),_good(c,str(q.escort.tradeGood)),q.escort.carrierUids.size(),ui.money(q.reward),float(q.deadlineDay)],17,ui.GOLD)
		if not reserve.is_empty():
			var budget: Dictionary=_budget(c,reserve)
			ui.paragraph(body,"Your purse %s coins; payroll %s/day. Required reserves: %s payroll coins, %.2f food, %.2f loaded fuel for delivery, return to Brass Haven and two contingency days."%[ui.money(c.state.get("coins",0)),ui.money(budget.dailyWages),ui.money(reserve.returnWages),float(reserve.foodRequired),float(reserve.fuelRequired)],15)
			if budget.priced:ui.paragraph(body,"Estimated operating cost %s coins; separate contingency reserve %s. Repairs, combat losses and delays are extra."%[ui.money(budget.operatingCost),ui.money(budget.reserveFunding)],15)
			else:ui.paragraph(body,"Scheduled travel payroll %s coins. Food or fuel replacement prices are missing; total operating margin is unavailable."%ui.money(budget.wages),15,ui.GOLD)
			_offer_details(ui,_details(ui,body,"Cost, stores and contract details"),c,reserve,budget)
		var ready: bool=noted.size()==2 and noted.has(str(q.ownerId)) and bool(reserve.get("readyForAllowance",false))
		var policies=ui.row(body)
		_button(ui,policies,"Moving escort: %s coins after delivery"%ui.money(q.reward),"accept",{"terms":q,"policy":"moving"},ready)
		if not c.EscortOps.threat(c,c.fleet_owner(str(q.ownerId))).is_empty():
			_button(ui,policies,"Threatened escort: %s coins after delivery"%ui.money(q.reward),"accept",{"terms":q,"policy":"threatened"},ready)
	_button(ui,body,"Review route to Kelp Reach","route",{"port":"kelp_reach"})

static func _offer_details(ui,body: Node,_c,reserve: Dictionary,budget: Dictionary) -> void:
	ui.paragraph(body,"Delivery %.2f days; return %.2f days. Operating payroll %s coins; food replacement %s; fuel replacement %s. Replacement prices: %s, day %.2f."%[float(reserve.outwardDays),float(reserve.returnDays),ui.money(budget.wages),ui.money(budget.foodCost) if budget.priced else "unpriced",ui.money(budget.fuelCost) if budget.priced else "unpriced",str(budget.pricePort),float(budget.priceDay)],15)
	ui.paragraph(body,"Loaded food %.2f / %.2f required; loaded fuel short %.2f; wage arrears %s coins. The fee is client-funded escrow, paid after delivery. Loss, withdrawal, route change or leaving the convoy returns unearned escrow to its client. Both policies have the same fee and reserve requirements; threatened escort requires an actual threat and adds combat risk."%[float(reserve.foodAvailable),float(reserve.foodRequired),float(reserve.fuelShortfall),ui.money(budget.arrears)],15)
	for boat in reserve.get("boats",[]):ui.paragraph(body,"%s: %.2f fuel loaded / %.2f allowance; %.2f beyond its own tank."%[str(boat.get("name","Your boat")),float(boat.loadedFuel),float(boat.fuelRequired),float(boat.tankShortfall)],14)
	for warning in reserve.get("warnings",[]):ui.paragraph(body,str(warning),14,ui.GOLD)

static func _budget(c,reserve: Dictionary) -> Dictionary:
	var here: Dictionary=c.current_port()
	var prices: Dictionary={}
	if here.is_empty():
		var previous: Dictionary=c.port(str(c.state.get("lastPort","")))
		var report: Dictionary=Costs._report(c,previous) if not previous.is_empty() else {}
		if report.get("seen",false):prices={"food":int(report.get("buy",{}).get("food",0)),"fuel":int(report.get("buy",{}).get("fuel",0)),"name":str(previous.get("name","Visited harbor")),"day":float(report.get("observedDay",0))}
	return Costs._budget(c,float(reserve.outwardDays),float(reserve.returnDays),0,here,0,0,"",prices)

static func _summary(ui,body: Node,c,w: Dictionary,p: Dictionary,active: bool) -> void:
	var tally: Dictionary=c.Arc116.counts(c)
	var name: String="Chosen convoy"
	for report in w.get("reports",[]):
		if str(report.get("ownerId",""))==str(p.ownerId):name=str(report.get("name","Chosen convoy"));break
	ui.paragraph(body,"%s: %d original boats escaped, %d arrived, %d sunk, %d captured, %d unconfirmed."%[name,int(tally.get("escaped",0)),int(tally.get("arrived",0)),int(tally.get("sunk",0)),int(tally.get("captured",0)),int(tally.get("unresolved",0))],17,ui.GOLD)
	var book: Dictionary=w.get("withdrawal",{})
	if book.is_empty():book=p
	var current: bool=false
	if active and c.Arc116.same_passage(c):
		for sight in c.NavalAI.sightings(c.state):
			if str(sight.get("ownerId",""))==str(p.ownerId) and sight.get("current",false):current=true;break
	if current:
		var owner: Dictionary=c.fleet_owner(str(p.ownerId))
		var load: Dictionary=c.EscortOps._load_plan(c,owner)
		var count: int=0
		var crew: float=0;var wounded: float=0;var hold: float=0
		var lots: Dictionary={}
		for boat in owner.get("boats",[]):
			if not book.get("carrierUids",[]).has(str(boat.get("uid",""))) or boat.get("sunk",false) or boat.get("captureSecured",false):continue
			count+=1;crew+=float(boat.get("crew",0));wounded+=float(boat.get("wounded",0))
			hold+=maxf(0,float(boat.get("spec",{}).get("cargo",0))-c.Expedition.store_overflow(boat))
			for good in load.get("carrierCargo",{}).get(str(boat.uid),{}):lots[good]=float(lots.get(good,0))+float(load.carrierCargo[str(boat.uid)][good])
		ui.paragraph(body,"Currently observed: %d original boats afloat; crew %.0f, wounded %.0f; usable hold %.2f. Load: %s."%[count,crew,wounded,hold,_cargo(c,lots) if load.get("ok",false) else "cannot be reconciled to the surviving holds"],16)
	elif int(tally.get("arrived",0))>0:
		var arrival: Dictionary=book.get("arrival",{})
		ui.paragraph(body,"Confirmed arrival: %d original boats at %s%s. Their recorded outcomes remain in the account."%[int(tally.arrived),_port(c,str(p.targetPort))," on day %.2f"%float(arrival.day) if arrival.has("day") else ""],16)
	elif active:ui.paragraph(body,"Latest confirmed carrier records are in Details; no current load is shown without sight of the original passage.",15,ui.GOLD)

static func _carrier_details(ui,body: Node,c,w: Dictionary,p: Dictionary) -> void:
	var book: Dictionary=w.get("withdrawal",{})
	if book.is_empty():book=p
	else:ui.paragraph(body,"Withdrawal began day %.2f with %d surviving original loaded boats. Earlier escapes do not establish their later withdrawal."%[float(book.get("begunDay",0)),book.get("carrierUids",[]).size()],15)
	var lots: Dictionary={}
	var crew: float=0;var wounded: float=0;var hold: float=0
	var crews: Dictionary=book.get("crews",p.get("crewAtAcceptance",{}))
	var capacities: Dictionary=book.get("capacity",p.get("capacityAtAcceptance",{}))
	for uid in book.get("carrierUids",[]):
		crew+=float(crews.get(uid,{}).get("crew",0));wounded+=float(crews.get(uid,{}).get("wounded",0))
		hold+=float(capacities.get(uid,0))
		for good in book.get("carrierCargo",{}).get(uid,{}):lots[good]=float(lots.get(good,0))+float(book.carrierCargo[uid][good])
	ui.paragraph(body,"Snapshot day %.2f: crew %.0f, wounded %.0f; original hull hold %.2f; load %s. This dated inventory is not a current load report."%[float(book.get("begunDay",p.get("acceptedDay",0))),crew,wounded,hold,_cargo(c,lots)],15)
	var fates: Dictionary={"escaped":"escaped the encounter","arrived":"arrived at harbor","sunk":"sunk","captured":"captured","afloat":"afloat; withdrawal unconfirmed","stranded":"stranded; withdrawal unconfirmed"}
	var index: int=0
	for uid in p.get("carrierUids",[]):
		index+=1
		var outcome: Dictionary=book.get("outcomes",{}).get(uid,{})
		var name: String=str(p.get("crewAtAcceptance",{}).get(uid,{}).get("name","Original boat %d"%index))
		ui.paragraph(body,"%s: %s%s."%[name,str(fates.get(str(outcome.get("fate","")),"unconfirmed")),"; recorded day %.2f"%float(outcome.day) if outcome.has("day") else ""],15)

static func _fee(ui,body: Node,c,p: Dictionary,active: bool) -> void:
	var status: String=str(p.get("status","carried"))
	if status=="paid":ui.paragraph(body,"Escort fee received: %s coins."%ui.money(p.get("payment",0)),16,ui.TEAL);return
	if status=="withdrawn":ui.paragraph(body,"Escort contract closed through its refund arrangements. No escort fee received.",16);return
	if not active:ui.paragraph(body,"No closed escort fee receipt is recorded.",16,ui.GOLD);return
	var job: Dictionary=_job(c,p)
	if job.is_empty():ui.paragraph(body,"No matching open escort job is available. No fee receipt is recorded.",16,ui.GOLD);return
	ui.paragraph(body,"Escort: %s%s. Client escrow %s coins; agreed fee %s. No fee received yet."%[str(job.get("state","pending")).capitalize(),"; failed" if job.get("failed",false) else "",ui.money(job.get("escrow",0)),ui.money(job.get("reward",0))],16)
	if c.current_port().is_empty():return
	var docked: bool=str(c.current_port().get("id",""))==str(p.targetPort)
	var delivered: bool=str(job.get("state",""))=="active" and not job.get("failed",false) and job.get("escort",{}).get("arrived",false) and not job.get("escort",{}).get("battlePending",false)
	var actions=ui.row(body)
	_button(ui,actions,"Collect held fee","collect",{"job":str(p.jobId)},docked and delivered)
	_button(ui,actions,"Close escort and refund client","refund",{"job":str(p.jobId)},not c.current_port().is_empty())

static func _navigation(ui,body: Node,c,w: Dictionary,p: Dictionary) -> void:
	var args: Dictionary={"job":str(p.jobId)}
	var actions=ui.row(body)
	if c.Arc116.same_passage(c) or w.get("follow",false):_button(ui,actions,"Stop following" if w.get("follow",false) else "Follow original boats","follow",{"job":str(p.jobId),"enabled":not bool(w.get("follow",false))})
	var protection: Dictionary=c.Arc116.protection_gate(c)
	if not protection.get("ok",false) and not str(protection.get("message","")).is_empty():ui.paragraph(body,str(protection.message),15,ui.GOLD)
	if not c.EscortOps.threat(c,c.fleet_owner(str(p.ownerId))).is_empty():_button(ui,actions,"Cover through interception","cover",args,bool(protection.get("ok",false)))
	for pursuer in c.Arc116.pursuers(c):
		ui.paragraph(body,"Observed pursuer: %s, day %.2f."%[str(pursuer.get("name","Hostile fleet")),float(pursuer.get("day",0))],15,ui.GOLD)
		_button(ui,body,"Interdict this pursuer","interdict",{"job":str(p.jobId),"owner":str(pursuer.get("ownerId",""))})
	var harbor=ui.row(body)
	if str(c.current_port().get("id",""))==str(p.targetPort):_button(ui,harbor,"Check harbor arrivals","arrival",args)
	_button(ui,harbor,"Review delivery route","route",{"port":str(p.targetPort),"job":str(p.jobId)})

static func _job(c,p: Dictionary) -> Dictionary:
	var job: Dictionary=c.VoyageJobs._find(c.state,str(p.get("jobId","")))
	if str(job.get("kind",""))!="escort" or str(job.get("ownerId",""))!=str(p.get("ownerId","")) or str(job.get("targetPort",""))!=str(p.get("targetPort","")) or int(job.get("escort",{}).get("voyageSeq",-1))!=int(p.get("voyageSeq",-2)):return {}
	return job

static func _button(ui,body: Node,label: String,action: String,args: Dictionary={},enabled: bool=true) -> void:
	ui.button(body,label,(func(kind,data):_act.call_deferred(ui,kind,data)).bind(action,args.duplicate(true))).disabled=not enabled

static func _details(ui,body: Node,title: String) -> Node:
	var panel=ui.column(body)
	panel.visible=false
	var toggle=ui.button(body,title,(func(target):_toggle.call_deferred(target)).bind(panel),false,false)
	body.move_child(toggle,panel.get_index())
	return panel

static func _toggle(panel) -> void:
	if is_instance_valid(panel):panel.visible=not panel.visible

static func _act(ui,action: String,args: Dictionary) -> void:
	if not _live(ui) or ui.modal_kind!="coastal_stories":return
	ui.host.sync_economy()
	if not _live(ui) or ui.modal_kind!="coastal_stories":return
	var c=ui.host.core
	var record: Dictionary=c.Arc116.record(c)
	var w: Dictionary=c.Arc116.work(c)
	var p: Dictionary=w.get("priority",{})
	if record.get("done",false) or str(record.get("stage","")) not in STAGES.slice(0,2) or w.get("reported",false):_finish(ui,c.fail("This account is no longer open."));return
	if args.has("job") and (str(args.job)!=str(p.get("jobId","")) or p.is_empty()):_finish(ui,c.fail("The selected escort has changed. Refresh its account."));return
	c.NavalAI.observe(c.state)
	var result: Dictionary
	match action:
		"note","accept":
			if str(record.stage)!="two_distress116" or not p.is_empty():_finish(ui,c.fail("The priority has already been selected."));return
			if action=="note":result=c.Arc116.note_report(c,str(args.owner))
			else:
				var reserve: Dictionary=c.Arc110.reserve_quote(c,args.terms)
				if not reserve.get("readyForAllowance",false):_finish(ui,c.fail("Prepare the displayed payroll, food and loaded fuel reserves before accepting."));return
				if str(args.policy)=="threatened" and c.EscortOps.threat(c,c.fleet_owner(str(args.terms.ownerId))).is_empty():_finish(ui,c.fail("That convoy has no current threat. Review its moving escort terms."));return
				result=c.Arc116.accept_priority(c,args.terms,str(args.policy))
		"follow":result=c.Arc116.follow(c,bool(args.enabled))
		"cover":result=c.Arc116.cover(ui.host)
		"interdict":result=c.Arc116.interdict(ui.host,str(args.owner))
		"arrival":result=c.Arc116.check_arrival_record(c)
		"collect","refund":
			if _job(c,p).is_empty() or str(p.get("status",""))!="carried":_finish(ui,c.fail("This escort has no matching open fee account."));return
			result=c.settle_voyage_job(str(args.job),action=="refund")
		"route":ui.HarborRoute104.open(ui,str(args.port));return
		"watch":ui.NavalUI.open(ui);return
		"refresh":result=c.ok("Coastal watch refreshed.")
		_:return
	_finish(ui,result,action=="follow" and result.get("ok",false))

static func _finish(ui,result: Dictionary,close: bool=false) -> void:
	ui.host.respond(result)
	if result.get("ok",false):ui.host.save_game(false)
	if ui.host.mode!="campaign":return
	if close:ui.close_modal()
	else:ui.StoryUI.open(ui)

static func _cargo(c,lots: Dictionary) -> String:
	var parts: Array[String]=[]
	for good in lots:
		if float(lots[good])>0:parts.append("%.2f %s"%[float(lots[good]),_good(c,str(good))])
	return ", ".join(parts) if not parts.is_empty() else "none aboard"

static func _good(c,id: String) -> String:
	return str(c.Goods.ITEMS.get(id,{}).get("name","cargo"))

static func _port(c,id: String) -> String:
	return str(c.port(id).get("name","the reported harbor"))

static func _live(ui) -> bool:
	return ui!=null and is_instance_valid(ui) and ui.host!=null and is_instance_valid(ui.host) and ui.host.mode=="campaign"
