extends RefCounted
const STAGES=["who_pays117","funding_work117","funding_account117"]
const MARA_STAGES=["later_mara117","mara_condition117"]
const CHOICES=["choose_mutual117","choose_separate117","report_funding117","next_fuel117","discuss_owned_hull117","leave_mara117"]

static func _owns(entry: Dictionary) -> bool:
	return (str(entry.get("chainId",""))=="common_passage110" and str(entry.get("stage","")) in STAGES) or (str(entry.get("chainId",""))=="mara_work113" and str(entry.get("stage","")) in MARA_STAGES)

static func body(ui,entry: Dictionary,fallback: String) -> String:
	if not _live(ui) or not _owns(entry) or str(entry.get("stage",""))!="funding_work117":return fallback
	var c=ui.host.core
	if entry.get("done",false) or c.Arc117.work(c).get("reported",false):return fallback
	var a: Dictionary=c.Arc117.attempt(c)
	if a.is_empty():return "Review a current loaded departure under the chosen funding terms. Your operating reserves must be ready before accepting the escort."
	if str(a.get("status",""))=="carried" and (_job(c,a).get("failed",false) or str(_job(c,a).get("state",""))=="expired"):return "The escort remains open for closure. Review its held escrow and any refund already received by the client."
	match str(a.get("status","")):
		"carried":return "Accompany the original boats to delivery. The agreed fee remains separate from your operating reserves."
		"paid":return "The delivery and escort payment are recorded. Mara can now receive the funding account."
		_:return "This escort is closed. Review the client's refund and any harbor contributions still awaiting return before another departure."

static func next_action(ui,entry: Dictionary,fallback: String) -> String:
	if not _live(ui) or not _owns(entry) or str(entry.get("stage",""))!="funding_work117":return fallback
	var c=ui.host.core
	if entry.get("done",false) or c.Arc117.work(c).get("reported",false):return fallback
	var a: Dictionary=c.Arc117.attempt(c)
	if a.is_empty():return "Review the current fee, funding shares and reserves before accepting."
	if str(a.get("status",""))=="paid":return "Send Mara the completed funding account."
	if str(a.get("status",""))=="abandoned":return "Check returned contributions, then refresh the available departures."
	var job: Dictionary=_job(c,a)
	if job.get("failed",false) or str(job.get("state",""))=="expired":return "Close the unsuccessful escort and review the client's actual refund."
	if job.get("escort",{}).get("arrived",false):return "Visit the delivery harbor and collect the held escort fee."
	return "Follow the contracted boats; collect the held fee at their delivery harbor once arrival and sale are complete."

static func controls(ui,body: Node,entry: Dictionary) -> void:
	if not _live(ui) or not _owns(entry):return
	var c=ui.host.core
	var stage: String=str(entry.get("stage",""))
	if stage in MARA_STAGES:
		if not entry.get("done",false):_mara(ui,body,c,entry)
		return
	var a: Dictionary=c.Arc117.attempt(c)
	if not a.is_empty():_account(ui,body,c,a)
	if entry.get("done",false) or (stage=="funding_work117" and c.Arc117.work(c).get("reported",false)):
		if not a.is_empty():_record_details(ui,_details(ui,body,"Funding and original cargo records"),c,a)
		return
	match stage:
		"who_pays117":
			_choice(ui,body,c,entry,"Mutual harbor contributions","choose_mutual117")
			_choice(ui,body,c,entry,"Separate owner bond","choose_separate117")
		"funding_work117":
			if str(a.get("status",""))=="paid":_choice(ui,body,c,entry,"Send Mara the funding account","report_funding117")
			else:
				if not c.Arc117.active(c).is_empty():_carried(ui,body,c,entry,a)
				else:
					if str(a.get("status",""))=="abandoned" and _shares(a)>int(a.get("reimbursed",0)):_button(ui,body,entry,"Return the harbor contributions","reimburse")
					_offers(ui,body,c,entry)
				var actions=ui.row(body)
				_button(ui,actions,entry,"Coastal watch","watch")
				_button(ui,actions,entry,"Refresh","refresh")
		"funding_account117":_choice(ui,body,c,entry,"Hear the next fuel request","next_fuel117")
	if not a.is_empty():_record_details(ui,_details(ui,body,"Funding and original cargo records"),c,a)

static func _offers(ui,body: Node,c,entry: Dictionary) -> void:
	var offers: Array=c.Arc117.offers(c)
	if offers.is_empty():ui.paragraph(body,"No eligible current departure is available. Review any unsettled contributions above, or refresh the coastal watch.",15,ui.GOLD)
	for terms in offers:
		var q: Dictionary=c.Arc117.quote(c,terms)
		if not q.get("ok",false):ui.paragraph(body,str(terms.get("title","Current departure"))+": "+str(q.get("message","Refresh this departure before accepting.")),15,ui.GOLD);continue
		var offer: Dictionary=q.offer
		var escort: Dictionary=offer.get("escort",{})
		var owner: Dictionary=c.fleet_owner(str(offer.get("ownerId","")))
		ui.paragraph(body,"%s: %d original loaded boats, %.2f %s. Fee %s coins after delivery at %s."%[str(offer.get("title","Current departure")),escort.get("carrierUids",[]).size(),float(escort.get("tradeQty",0)),_good(c,str(escort.get("tradeGood",""))),ui.money(offer.get("reward",0)),_port(c,str(offer.get("targetPort","")))],17,ui.GOLD)
		if str(q.get("model",""))=="mutual":
			for share in q.get("contributions",[]):
				var port: Dictionary=c.port(str(share.get("portId","")))
				ui.paragraph(body,"%s government purse: %s coins available; quoted share %s."%[str(port.get("name","Harbor")),ui.money(port.get("governmentPurse",0)),ui.money(share.get("amount",0))],15)
		else:ui.paragraph(body,"Owner bond: %s coins from %s's own %s-coin purse."%[ui.money(offer.get("reward",0)),str(owner.get("name","the convoy owner")),ui.money(owner.get("coins",0))],15)
		var reserve: Dictionary=q.get("reserve",{})
		if not reserve.is_empty():ui.paragraph(body,"Your purse %s coins; keep %s wage coins, %.2f food and %.2f loaded fuel for the passage, return and contingency. These are your operating reserves, separate from the escort fee."%[ui.money(c.state.get("coins",0)),ui.money(reserve.get("returnWages",0)),float(reserve.get("foodRequired",0)),float(reserve.get("fuelRequired",0))],15)
		_button(ui,body,entry,"Accept these funded escort terms","accept",{"quote":q})
		var detail: Node=_details(ui,body,"Passage, reserves and refund terms")
		ui.paragraph(detail,"Deadline day %.2f. Unearned escrow returns to the original client through the escort contract. Harbor contributions are returned only after closure, a recorded client refund and enough actual client funds; any shortfall remains unsettled."%float(offer.get("deadlineDay",0)),15)
		for warning in reserve.get("warnings",[]):ui.paragraph(detail,str(warning),14,ui.GOLD)
		for boat in reserve.get("boats",[]):ui.paragraph(detail,"%s: %.2f fuel loaded / %.2f required."%[str(boat.get("name","Your boat")),float(boat.get("loadedFuel",0)),float(boat.get("fuelRequired",0))],14)

static func _account(ui,body: Node,c,a: Dictionary) -> void:
	var b: Dictionary=a.get("binding",{})
	var status: String=str(a.get("status",""))
	ui.paragraph(body,"%d original loaded boats; %.2f %s accepted on day %.2f. Agreed fee %s coins."%[b.get("carrierUids",[]).size(),float(b.get("tradeQty",0)),_good(c,str(b.get("tradeGood",""))),float(b.get("acceptedDay",0)),ui.money(b.get("reward",0))],16,ui.GOLD)
	if status=="paid":
		ui.paragraph(body,"Delivery and sale recorded; escort fee received %s coins."%ui.money(a.get("closure",{}).get("payment",0)),17,ui.TEAL)
		if _shares(a)>0:
			var sources: Array[String]=[]
			for share in a.get("contributions",[]):sources.append("%s government purse (%s coins)"%[_port(c,str(share.get("portId",""))),ui.money(share.get("amount",0))])
			ui.paragraph(body,"Completed escort funded by %s. No refund or contribution return is due."%"; ".join(sources),15)
		else:
			var owner: Dictionary=c.fleet_owner(str(b.get("ownerId","")))
			ui.paragraph(body,"Completed escort funded by %s's own %s-coin bond. No refund is due."%[str(owner.get("name","the convoy owner")),ui.money(b.get("reward",0))],15)
	elif status=="abandoned":ui.paragraph(body,"Escort closed without an escort fee.",16)
	else:
		var job: Dictionary=_job(c,a)
		ui.paragraph(body,"Escort %s; held client escrow %s coins. No escort fee received."%[str(job.get("state","unavailable")).capitalize(),ui.money(job.get("escrow",0))],16)
	var total: int=_shares(a)
	if status=="abandoned" or int(a.get("refund",0))>0:
		ui.paragraph(body,"Client refund actually received: %s coins%s."%[ui.money(a.get("refund",0))," on day %.2f"%float(a.refundDay) if int(a.get("refund",0))>0 else ""],15)
		if total>0:ui.paragraph(body,"Harbor contributions actually returned: %s / %s coins."%[ui.money(a.get("reimbursed",0)),ui.money(total)],15)
	if status=="abandoned" and total>int(a.get("reimbursed",0)):
		var owner: Dictionary=c.fleet_owner(str(b.get("ownerId","")))
		var shortfall: int=maxi(0,maxi(total-int(a.get("refund",0)),total-int(owner.get("coins",0))))
		ui.paragraph(body,"Unsettled harbor contributions: %s coins; current refund or client-cash shortfall: %s."%[ui.money(total-int(a.get("reimbursed",0))),ui.money(shortfall)],15,ui.GOLD)

static func _carried(ui,body: Node,c,entry: Dictionary,a: Dictionary) -> void:
	var b: Dictionary=a.get("binding",{})
	var job: Dictionary=_job(c,a)
	if job.is_empty():ui.paragraph(body,"Refresh the escort account before taking further action.",15,ui.GOLD);return
	var actions=ui.row(body)
	if str(job.get("state",""))=="active" and not job.get("failed",false) and not job.get("escort",{}).get("arrived",false) and not job.get("escort",{}).get("battlePending",false):_button(ui,actions,entry,"Stop following" if a.get("follow",false) else "Follow original boats","follow",{"enabled":not bool(a.get("follow",false))})
	_button(ui,actions,entry,"Review delivery route","route",{"port":str(b.get("targetPort",""))})
	var here: Dictionary=c.current_port()
	if here.is_empty():return
	var escort: Dictionary=job.get("escort",{})
	if str(here.get("id",""))==str(b.get("targetPort","")) and str(job.get("state",""))=="active" and not job.get("failed",false) and escort.get("arrived",false) and not escort.get("battlePending",false):_button(ui,body,entry,"Collect the held escort fee","collect")
	_button(ui,body,entry,"Close escort and refund the client","refund")

static func _record_details(ui,body: Node,c,a: Dictionary) -> void:
	var b: Dictionary=a.get("binding",{})
	ui.paragraph(body,"Original passage: %s to %s, accepted day %.2f. The following load is the acceptance record."%[_port(c,str(b.get("fromPort",""))),_port(c,str(b.get("targetPort",""))),float(b.get("acceptedDay",0))],15)
	var index: int=0
	for uid in b.get("carrierUids",[]):
		index+=1
		var boat: Dictionary=c.find_boat(str(uid))
		ui.paragraph(body,"%s: %s."%[str(boat.get("name","Original carrier %d"%index)),_cargo(c,b.get("carrierCargo",{}).get(uid,{}))],15)
	for share in a.get("contributions",[]):
		var text: String="%s government purse contributed %s coins."%[_port(c,str(share.get("portId",""))),ui.money(share.get("amount",0))]
		if str(a.get("status",""))=="abandoned" or int(a.get("refund",0))>0:text+=" Actually returned %s coins."%ui.money(share.get("amount",0) if int(a.get("reimbursed",0))==_shares(a) else 0)
		ui.paragraph(body,text,15)

static func _mara(ui,body: Node,c,entry: Dictionary) -> void:
	var selecting: bool=str(entry.get("stage",""))=="later_mara117"
	if selecting:_choice(ui,body,c,entry,"Leave without commissioning repairs","leave_mara117")
	var current: Dictionary=c.Arc117.mara_quote(c)
	if selecting and current.get("ok",false):_choice(ui,body,c,entry,"Discuss the selected owned hull","discuss_owned_hull117")
	var rows: Array=c.Arc117.damaged_hulls(c)
	if rows.is_empty() or (not selecting and not current.get("ok",false)):ui.paragraph(body,"No current service estimate is available for an eligible owned damaged hull here. This conversation requires no repair purchase.",15);return
	var selected: String=str(c.Arc117.work(c).get("mara",{}).get("uid",""))
	for row in rows:
		if not selecting and str(row.get("uid",""))!=selected:continue
		var q: Dictionary=row.get("quote",{})
		var name: String=str(row.get("name","Owned hull"))
		ui.paragraph(body,"%s%s: current yard estimate %s coins. Materials %s; labor %s; yard fee %s."%[name," (selected)" if str(row.get("uid",""))==selected else "",ui.money(q.get("cost",0)),ui.money(q.get("materials",0)),ui.money(int(q.get("ordinary",0))+int(q.get("expert",0))),ui.money(q.get("fee",0))],16,ui.GOLD)
		if selecting:_button(ui,body,entry,"Select "+name+" for discussion","hull",{"uid":str(row.get("uid",""))})
	ui.paragraph(body,"Discussion commissions no work. Any repair remains a separate paid harbor service.",15)

static func _choice(ui,body: Node,c,entry: Dictionary,label: String,id: String) -> void:
	var gate: Dictionary=c.Arc117.choice_gate(c,id)
	for choice in entry.get("choices",[]):
		if str(choice.get("id",""))==id and not str(choice.get("tradeoff","")).is_empty():ui.paragraph(body,str(choice.tradeoff),15)
	if gate.get("ok",false):_button(ui,body,entry,label,id)
	elif not str(gate.get("message","")).is_empty():ui.paragraph(body,str(gate.message),15,ui.GOLD)

static func _button(ui,body: Node,entry: Dictionary,label: String,action: String,args: Dictionary={}) -> void:
	var a: Dictionary=ui.host.core.Arc117.attempt(ui.host.core)
	var context: Dictionary={"chain":str(entry.get("chainId","")),"stage":str(entry.get("stage","")),"job":str(a.get("binding",{}).get("jobId","")),"action":action,"args":args.duplicate(true)}
	ui.button(body,label,(func(data):_act.call_deferred(ui,data)).bind(context.duplicate(true)))

static func _act(ui,context: Dictionary) -> void:
	if not _live(ui) or ui.modal_kind!="coastal_stories":return
	ui.host.sync_economy()
	if not _live(ui) or ui.modal_kind!="coastal_stories":return
	var c=ui.host.core
	var rec: Dictionary=c.state.get("stories",{}).get("chains",{}).get(str(context.chain),{})
	var a: Dictionary=c.Arc117.attempt(c)
	if rec.get("done",false) or str(rec.get("stage",""))!=str(context.stage) or not _owns({"chainId":context.chain,"stage":rec.get("stage","")}):_finish(ui,c.fail("This conversation has changed. Review its current account."));return
	if str(context.chain)=="common_passage110" and str(context.job)!=str(a.get("binding",{}).get("jobId","")):_finish(ui,c.fail("The escort has changed. Refresh its current terms."));return
	var action: String=str(context.action)
	var args: Dictionary=context.args
	var result: Dictionary={}
	if str(context.stage)=="funding_work117" and action in ["accept","refresh"]:c.NavalAI.observe(c.state)
	if action in CHOICES:
		var gate: Dictionary=c.Arc117.choice_gate(c,action)
		result=c.StoryOps.choose(c,str(context.chain),action) if gate.get("ok",false) else gate
	elif str(context.stage)=="later_mara117" and action=="hull":result=c.Arc117.select_hull(c,str(args.uid))
	elif str(context.stage)=="funding_work117" and not c.Arc117.work(c).get("reported",false):
		match action:
			"accept":result=c.Arc117.accept(c,args.quote)
			"reimburse":result=c.Arc117.settle_refund(c)
			"follow":result=c.Arc117.follow(c,bool(args.enabled))
			"collect","refund":
				if c.Arc117.active(c).is_empty() or _job(c,a).is_empty():_finish(ui,c.fail("This escort is no longer carried."));return
				if c.current_port().is_empty():_finish(ui,c.fail("Enter a harbor before closing the escort account."));return
				result=c.settle_voyage_job(str(context.job),action=="refund")
			"route":
				if c.Arc117.active(c).is_empty():_finish(ui,c.fail("This escort is closed."));return
				ui.HarborRoute104.open(ui,str(args.port));return
			"watch":ui.NavalUI.open(ui);return
			"refresh":result=c.ok("Funding account refreshed.")
			_:return
	else:return
	_finish(ui,result,action=="follow" and result.get("ok",false))

static func _finish(ui,result: Dictionary,close: bool=false) -> void:
	ui.host.respond(result)
	if result.get("ok",false):ui.host.save_game(false)
	if not _live(ui):return
	if close:ui.close_modal()
	else:ui.StoryUI.open(ui)

static func _job(c,a: Dictionary) -> Dictionary:
	var b: Dictionary=a.get("binding",{})
	var job: Dictionary=c.VoyageJobs._find(c.state,str(b.get("jobId","")))
	if str(job.get("kind",""))!="escort" or str(job.get("ownerId",""))!=str(b.get("ownerId","")) or str(job.get("targetPort",""))!=str(b.get("targetPort","")) or int(job.get("escort",{}).get("voyageSeq",-1))!=int(b.get("voyageSeq",-2)):return {}
	return job

static func _shares(a: Dictionary) -> int:
	var total: int=0
	for row in a.get("contributions",[]):total+=int(row.get("amount",0))
	return total

static func _details(ui,body: Node,title: String) -> Node:
	var panel=ui.column(body)
	panel.visible=false
	var toggle=ui.button(body,title,(func(target):_toggle.call_deferred(target)).bind(panel),false,false)
	body.move_child(toggle,panel.get_index())
	return panel

static func _toggle(panel) -> void:
	if is_instance_valid(panel):panel.visible=not panel.visible

static func _cargo(c,lots: Dictionary) -> String:
	var parts: Array[String]=[]
	for good in lots:
		if float(lots[good])>0:parts.append("%.2f %s"%[float(lots[good]),_good(c,str(good))])
	return ", ".join(parts) if not parts.is_empty() else "no cargo recorded"

static func _port(c,id: String) -> String:
	return str(c.port(id).get("name","the recorded harbor"))

static func _good(c,id: String) -> String:
	return str(c.Goods.ITEMS.get(id,{}).get("name","cargo"))

static func _live(ui) -> bool:
	return ui!=null and is_instance_valid(ui) and ui.host!=null and is_instance_valid(ui.host) and ui.host.mode=="campaign"
