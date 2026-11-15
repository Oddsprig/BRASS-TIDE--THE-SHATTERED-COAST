extends RefCounted
const CHAIN="common_passage110"
const STAGES=["common_passage119","passage_work119","common_account119","many_account119","unsettled_account119"]
const CHOICES=["begin_passage119","report_common119","report_many119","close_unsettled119","finish_common119","finish_many119","finish_unsettled119"]
const BRASS="brass_haven"
const SOURCE="anvil_dock"

static func owns(entry: Dictionary) -> bool:
	return str(entry.get("chainId",""))==CHAIN and str(entry.get("stage","")) in STAGES

static func body(ui,entry: Dictionary,fallback: String) -> String:
	if not _live(ui) or not owns(entry):return fallback
	if str(entry.get("stage",""))!="passage_work119":return fallback
	return str(ui.host.core.Arc119.view(ui.host.core).get("summary","Review the passage account before deciding what to do."))

static func next_action(ui,entry: Dictionary,fallback: String) -> String:
	if not _live(ui) or not owns(entry):return fallback
	if entry.get("done",false):return "Continue ordinary voyages."
	if str(entry.get("stage",""))!="passage_work119":return fallback
	var c=ui.host.core
	var a: Dictionary=c.Arc119.attempt(c)
	if str(a.get("status",""))=="paid":return "Return to Brass Haven and give Tobin the paid delivery account."
	var job: Dictionary=_job(c,c.Arc119.active(c))
	if not job.is_empty():
		if job.get("failed",false) or job.get("freight",{}).get("lost",false) or str(job.get("state",""))=="expired":return "Stop at a harbor to close this passage and unload any surviving sealed cargo."
		return "Sail with the sealed load to Westglass, deliver at its berth, then return to Brass Haven."
	return "Review the current offer at Anvil Dock, or give Tobin an incomplete account at Brass Haven."

static func controls(ui,body: Node,entry: Dictionary) -> void:
	if not _live(ui) or not owns(entry):return
	var c=ui.host.core
	var v: Dictionary=c.Arc119.view(c)
	var a: Dictionary=c.Arc119.attempt(c)
	if entry.get("done",false):
		_line(ui,body,v,"ending")
		_refund(ui,body,entry,v)
		ui.button(body,"Continue ordinary voyages",ui.close_modal,false,false)
		_facts(ui,body,v)
		_records(ui,body,c,entry,a)
		return
	match str(entry.get("stage","")):
		"common_passage119":
			_choice(ui,body,c,entry,"begin_passage119",true)
			_navigation(ui,body,c,entry,BRASS)
		"passage_work119":
			var reported: bool=false
			for id in ["report_common119","report_many119","close_unsettled119"]:
				if _choice(ui,body,c,entry,id):reported=true
			var active: Dictionary=c.Arc119.active(c)
			if not active.is_empty():_carried(ui,body,c,entry,active)
			elif str(a.get("status",""))=="paid":
				if not reported:
					var gate: Dictionary=c.Arc119.gate(c,{"mode":"paid"})
					if not gate.get("ok",false):ui.paragraph(body,str(gate.get("message","Return to Brass Haven with the delivery account.")),15,ui.GOLD)
				_navigation(ui,body,c,entry,BRASS)
			else:
				_refund(ui,body,entry,v)
				_offer(ui,body,c,entry)
				_navigation(ui,body,c,entry,SOURCE)
		"common_account119":_choice(ui,body,c,entry,"finish_common119",true)
		"many_account119":_choice(ui,body,c,entry,"finish_many119",true)
		"unsettled_account119":
			_choice(ui,body,c,entry,"finish_unsettled119",true)
			_refund(ui,body,entry,v)
	_facts(ui,body,v)
	_records(ui,body,c,entry,a)

static func _offer(ui,body: Node,c,entry: Dictionary) -> void:
	var q: Dictionary=c.Arc119.quote(c)
	if q.get("ok",false):
		var offer: Dictionary=q.get("offer",{})
		var freight: Dictionary=offer.get("freight",{})
		var invoice: int=int(q.get("invoice",0))
		var fee: int=int(q.get("fee",0))
		var mutual: bool=str(q.get("model",""))=="mutual"
		ui.paragraph(body,"%.2f %s: %s to %s. Goods invoice %s coins; held %s %s coins."%[float(freight.get("qty",0)),_good(c,str(freight.get("good",""))),_port(c,str(offer.get("port",""))),_port(c,str(offer.get("targetPort",""))),ui.money(invoice),"service fee" if mutual else "service bond",ui.money(fee)],16,ui.GOLD)
		if str(q.get("model",""))=="mutual":
			var local_fee: int=floori(float(fee)/2.0)
			ui.paragraph(body,"%s government pays %s coins: %s for goods and %s toward the fee. %s government pays the remaining %s fee coins. Your operating costs remain yours."%[_port(c,str(offer.get("port",""))),ui.money(invoice+local_fee),ui.money(invoice),ui.money(local_fee),_port(c,str(offer.get("targetPort",""))),ui.money(fee-local_fee)],15)
		else:
			ui.paragraph(body,"Your purse holds %s coins; this load costs %s: %s for goods and %s as your own service bond. Delivery returns that bond, not a profit. The invoice, wages, fuel and repairs remain your expenses."%[ui.money(c.state.get("coins",0)),ui.money(invoice+fee),ui.money(invoice),ui.money(fee)],15)
		var label: String="Fund and load (%s goods + %s fee coins)"%[ui.money(invoice),ui.money(fee)] if mutual else "Pay %s coins and load sealed cargo"%ui.money(invoice+fee)
		_button(ui,body,entry,label,"accept",{"quote":q})
		var reserve: Dictionary=q.get("reserve",{})
		var allowance: Dictionary=reserve.get("allowance",{})
		var details: Node=_details(ui,body,"Operating allowance and closure terms")
		ui.paragraph(details,"Keep %s wage coins, %.2f food and %.2f loaded fuel for delivery, return and contingency after funding. The held fee is unavailable for operations."%[ui.money(allowance.get("returnWages",0)),float(allowance.get("foodRequired",0)),float(allowance.get("fuelRequired",0))],15)
		ui.paragraph(details,"Closing an unsuccessful passage returns only the fee actually refunded to the sponsor. The receiving harbor's share or your own bond can be repaid only from that recorded return and available funds. Any shortfall remains owed. The goods invoice stays spent.",15)
		for warning in reserve.get("warnings",[]):ui.paragraph(details,str(warning),14,ui.GOLD)
	else:ui.paragraph(body,str(q.get("message","No current funded passage is available.")),15,ui.GOLD)
	_button(ui,body,entry,"Refresh passage terms","refresh")

static func _carried(ui,body: Node,c,entry: Dictionary,a: Dictionary) -> void:
	var job: Dictionary=_job(c,a)
	if job.is_empty():ui.paragraph(body,"The carried passage cannot be matched to its current account. Refresh before taking further action.",15,ui.GOLD);_button(ui,body,entry,"Refresh passage account","refresh");return
	var dock: Dictionary=c.work_port070()
	var freight: Dictionary=job.get("freight",{})
	if str(job.get("state",""))=="active" and not job.get("failed",false) and not freight.get("lost",false) and str(dock.get("id",""))==str(job.get("targetPort","")):
		_button(ui,body,entry,"Deliver sealed cargo; collect %s held coins"%ui.money(job.get("escrow",0)),"collect")
	_navigation(ui,body,c,entry,str(job.get("targetPort","")))
	ui.paragraph(body,"Contracted load: %.2f %s; %s coins still held. Deadline day %.2f."%[float(freight.get("qty",0)),_good(c,str(freight.get("good",""))),ui.money(job.get("escrow",0)),float(job.get("deadlineDay",0))],15)
	if freight.get("lost",false):ui.paragraph(body,"Sealed cargo is recorded as lost. The contracted quantity does not show how much remains aboard.",15,ui.GOLD)
	if not dock.is_empty():
		ui.paragraph(body,"Closing unloads surviving sealed cargo here and requests return of the unearned fee to its sponsor. It does not repay the goods invoice or erase any outstanding contribution.",15)
		_button(ui,body,entry,"Close passage and unload surviving cargo","abandon")
	else:ui.paragraph(body,"Closure requires a stopped harbor berth. Turning back alone leaves this passage open.",15)

static func _navigation(ui,body: Node,c,entry: Dictionary,port_id: String) -> void:
	var p: Dictionary=c.port(port_id)
	if c.home_local064() and str(p.get("regionId","shatter_coast"))=="shatter_coast" and not p.is_empty() and str(c.work_port070().get("id",""))!=port_id:
		_button(ui,body,entry,"Plan route to "+_port(c,port_id),"route",{"port":port_id})
	_button(ui,body,entry,"Open sailing chart","chart")

static func _refund(ui,body: Node,entry: Dictionary,v: Dictionary) -> void:
	if int(v.get("refundDue",0))<=0:return
	ui.paragraph(body,"Fee return still owed: %s coins. The goods invoice remains spent."%ui.money(v.get("refundDue",0)),16,ui.GOLD)
	if not v.get("refundReturnable",false):ui.paragraph(body,"No repayment is currently available from the recorded refund and sponsor's funds. This obligation remains after the debrief.",15)
	_button(ui,body,entry,"Repay from the recorded fee refund","reimburse")

static func _facts(ui,body: Node,v: Dictionary) -> void:
	for key in ["funding","cargo","route","reception"]:_line(ui,body,v,key)

static func _line(ui,body: Node,v: Dictionary,key: String) -> void:
	var value: String=str(v.get(key,""))
	if not value.is_empty():ui.paragraph(body,value,16,ui.GOLD if key=="funding" else ui.TEXT)

static func _records(ui,body: Node,c,entry: Dictionary,a: Dictionary) -> void:
	var is_work: bool=str(entry.get("stage",""))=="passage_work119" and not entry.get("done",false)
	var details: Node=_details(ui,body,"Conversation and passage records" if is_work else "Passage records")
	if is_work:ui.paragraph(details,str(entry.get("body","")),17)
	if a.is_empty():
		if entry.get("done",false):ui.paragraph(details,"No freight acceptance is recorded for this undertaking.",15)
		else:ui.paragraph(details,"A passage needs an existing known Westglass harbor, a lawful route, exportable supplies, hold space and enough real coins and operating reserves. To locate Westglass, sail the Glasswind chart and approach its anchorage. Return to Anvil Dock to review the offer; opening a chart buys and loads nothing.",15)
		return
	var b: Dictionary=a.get("binding",{})
	ui.paragraph(details,"Accepted at %s for %s on day %.2f; deadline day %.2f. Goods invoice %s coins; agreed fee %s coins."%[_port(c,str(b.get("port",""))),_port(c,str(b.get("targetPort",""))),float(b.get("acceptedDay",0)),float(b.get("deadlineDay",0)),ui.money(b.get("materialInvoice",0)),ui.money(b.get("fee",b.get("reward",0)))],15)
	var allocations: Dictionary=a.get("allocations",{})
	var index: int=0
	for uid in allocations:
		index+=1
		var boat: Dictionary=c.find_boat(str(uid))
		ui.paragraph(details,"%s: %.2f accepted %s. This records the original allocation, not a present cargo count."%[str(boat.get("name","Original carrier %d"%index)),float(allocations[uid]),_good(c,str(b.get("good","supplies")))],15)

static func _choice(ui,body: Node,c,entry: Dictionary,id: String,show_refusal: bool=false) -> bool:
	for choice in entry.get("choices",[]):
		if str(choice.get("id",""))!=id:continue
		var gate: Dictionary=c.Arc119.choice_gate(c,id)
		if not gate.get("ok",false):
			if show_refusal and not str(gate.get("message","")).is_empty():ui.paragraph(body,str(gate.message),15,ui.GOLD)
			return false
		if not str(choice.get("tradeoff","")).is_empty():ui.paragraph(body,str(choice.tradeoff),15)
		_button(ui,body,entry,str(choice.get("text","Continue")),id)
		return true
	return false

static func _button(ui,body: Node,entry: Dictionary,label: String,action: String,args: Dictionary={}) -> void:
	var a: Dictionary=ui.host.core.Arc119.attempt(ui.host.core)
	var context: Dictionary={"chain":str(entry.get("chainId","")),"stage":str(entry.get("stage","")),"job":str(a.get("binding",{}).get("jobId","")),"action":action,"args":args.duplicate(true)}
	ui.button(body,label,(func(data):_act.call_deferred(ui,data)).bind(context.duplicate(true)))

static func _act(ui,context: Dictionary) -> void:
	if not _live(ui) or ui.modal_kind!="coastal_stories":return
	ui.host.sync_economy()
	if not _live(ui) or ui.modal_kind!="coastal_stories":return
	var c=ui.host.core
	var rec: Dictionary=c.Arc119.record(c)
	var action: String=str(context.action)
	if str(context.chain)!=CHAIN or str(rec.get("stage",""))!=str(context.stage) or not owns({"chainId":context.chain,"stage":rec.get("stage","")}):_finish(ui,c.fail("This conversation has changed. Review the current account."));return
	if rec.get("done",false) and action!="reimburse":_finish(ui,c.fail("The debrief is complete. Only outstanding fee returns can still be repaid here."));return
	var a: Dictionary=c.Arc119.attempt(c)
	if str(context.job)!=str(a.get("binding",{}).get("jobId","")):_finish(ui,c.fail("The passage has changed. Review its current terms."));return
	var args: Dictionary=context.args
	var result: Dictionary={}
	if action=="reimburse":result=c.Arc119.settle_refund(c)
	elif action in CHOICES:
		var gate: Dictionary=c.Arc119.choice_gate(c,action)
		result=c.StoryOps.choose(c,CHAIN,action) if gate.get("ok",false) else gate
	elif action in ["route","chart"]:
		if action=="chart":ui.close_modal();return
		var port_id: String=str(args.get("port",""))
		var expected: String=BRASS
		if str(rec.get("stage",""))=="passage_work119":
			expected=str(a.get("binding",{}).get("targetPort","")) if not c.Arc119.active(c).is_empty() else (BRASS if str(a.get("status",""))=="paid" else SOURCE)
		if port_id!=expected or not c.home_local064() or str(c.port(port_id).get("regionId",""))!="shatter_coast":_finish(ui,c.fail("Use the sailing chart for this crossing."));return
		ui.HarborRoute104.open(ui,port_id);return
	elif str(rec.get("stage",""))=="passage_work119":
		match action:
			"accept":result=c.Arc119.accept(c,args.get("quote",{}))
			"collect","abandon":
				var job: Dictionary=_job(c,c.Arc119.active(c))
				if job.is_empty():_finish(ui,c.fail("This passage is no longer carried."));return
				if c.work_port070().is_empty():_finish(ui,c.fail("Stop at a harbor berth before closing this passage."));return
				result=c.settle_voyage_job(str(job.get("id","")),action=="abandon")
			"refresh":result=c.ok("Passage terms refreshed.")
			_:return
	else:return
	_finish(ui,result)

static func _job(c,a: Dictionary) -> Dictionary:
	var b: Dictionary=a.get("binding",{})
	if b.is_empty():return {}
	var job: Dictionary=c.VoyageJobs._find(c.state,str(b.get("jobId","")))
	if str(job.get("id",""))!=str(b.get("jobId","")) or str(job.get("kind",""))!="freight" or str(job.get("port",""))!=str(b.get("port","")) or str(job.get("targetPort",""))!=str(b.get("targetPort","")):return {}
	return job

static func _finish(ui,result: Dictionary) -> void:
	ui.host.respond(result)
	if result.get("ok",false):ui.host.save_game(false)
	if _live(ui):ui.StoryUI.open(ui)

static func _details(ui,body: Node,title: String) -> Node:
	var panel=ui.column(body)
	panel.visible=false
	var toggle=ui.button(body,title,(func(target):_toggle.call_deferred(target)).bind(panel),false,false)
	body.move_child(toggle,panel.get_index())
	return panel

static func _toggle(panel) -> void:
	if is_instance_valid(panel):panel.visible=not panel.visible

static func _port(c,id: String) -> String:
	return str(c.port(id).get("name","the recorded harbor"))

static func _good(c,id: String) -> String:
	return str(c.Goods.ITEMS.get(id,{}).get("name","supplies"))

static func _live(ui) -> bool:
	return ui!=null and is_instance_valid(ui) and ui.host!=null and is_instance_valid(ui.host) and ui.host.mode=="campaign"
