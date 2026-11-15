extends RefCounted
const STAGES=["fuel_has_owners118","fuel_work118","fuel_account118","last_warrant118","warrant_work118","warrant_account118"]
const TOBIN_STAGES=["later_tobin118","tobin_funding118"]
const CHOICES=["begin_fuel118","report_fuel118","next_warrant118","begin_warrant118","report_warrant118","report_unresolved118","next_passage118","discuss_funding118","leave_tobin118","finish_tobin118"]

static func owns(entry: Dictionary) -> bool:
	return (str(entry.get("chainId",""))=="common_passage110" and str(entry.get("stage","")) in STAGES) or (str(entry.get("chainId",""))=="tobin_clause111" and str(entry.get("stage","")) in TOBIN_STAGES)

static func body(_ui,_entry: Dictionary,fallback: String) -> String:
	return fallback

static func next_action(_ui,_entry: Dictionary,fallback: String) -> String:
	return fallback

static func controls(ui,body: Node,entry: Dictionary) -> void:
	if not _live(ui) or not owns(entry):return
	var c=ui.host.core
	var stage: String=str(entry.get("stage",""))
	var view: Dictionary=c.Arc118.view(c)
	if stage in TOBIN_STAGES:
		_summary(ui,body,view,"tobinLabel")
		if entry.get("done",false):return
		if stage=="later_tobin118":
			_choice(ui,body,c,entry,"leave_tobin118")
			_choice(ui,body,c,entry,"discuss_funding118")
		else:_choice(ui,body,c,entry,"finish_tobin118")
		return
	if stage in ["fuel_has_owners118","fuel_work118","fuel_account118"]:
		_summary(ui,body,view,"passageLabel")
		_summary(ui,body,view,"fuelLabel")
	else:_summary(ui,body,view,"warrantLabel")
	if entry.get("done",false):return
	match stage:
		"fuel_has_owners118":_choice(ui,body,c,entry,"begin_fuel118")
		"fuel_work118":
			_choice(ui,body,c,entry,"report_fuel118")
			if not c.Arc118.choice_gate(c,"report_fuel118").get("ok",false):_fuel(ui,body,c,entry)
		"fuel_account118":_choice(ui,body,c,entry,"next_warrant118")
		"last_warrant118":_choice(ui,body,c,entry,"begin_warrant118")
		"warrant_work118":
			var active: Dictionary=c.Arc118.active(c)
			if not active.is_empty():_carried(ui,body,c,entry,active)
			elif c.Arc118.choice_gate(c,"report_warrant118").get("ok",false):_choice(ui,body,c,entry,"report_warrant118")
			else:
				_choice(ui,body,c,entry,"report_warrant118",false)
				_choice(ui,body,c,entry,"report_unresolved118")
				var actions=ui.row(body)
				_button(ui,actions,entry,"Coastal watch","watch")
				_button(ui,actions,entry,"Refresh current offers","refresh")
				_offers(ui,body,c,entry)
		"warrant_account118":_choice(ui,body,c,entry,"next_passage118")

static func _fuel(ui,body: Node,c,entry: Dictionary) -> void:
	var q: Dictionary=c.Arc118.passage_quote(c)
	var port: String=_port(c,"naphtha_bay")
	if str(q.get("mode","")) in ["legal","parley"]:
		if str(q.get("mode",""))=="legal":ui.paragraph(body,"%s: lawful entry, 0 permission coins. Fuel is a separate purchase."%port,16,ui.GOLD)
		else:ui.paragraph(body,"%s: %s coins for three days of port-specific safe conduct. This buys no fuel or protection at sea."%[port,ui.money(q.get("cost",0))],16,ui.GOLD)
	ui.paragraph(body,str(q.get("message","Entry terms are unavailable.")),15,ui.GOLD)
	if q.get("ok",false):
		_button(ui,body,entry,"Confirm lawful entry (0 coins)" if str(q.get("mode",""))=="legal" else "Buy three-day permission (%s coins)"%ui.money(q.get("cost",0)),"permission",{"quote":q})
	for qty in [1,5]:
		var fuel: Dictionary=c.Arc118.fuel_quote(c,qty)
		if fuel.get("ok",false) or (fuel.has("price") and fuel.has("cost") and float(fuel.price)>0):
			ui.paragraph(body,"%d fuel: %s coins at %s coins each. This purchases cargo from the seller's stock."%[int(fuel.get("qty",qty)),ui.money(fuel.get("cost",0)),ui.money(fuel.get("price",0))],16)
		if fuel.get("ok",false):
			_button(ui,body,entry,"Buy %d fuel (%s coins)"%[qty,ui.money(fuel.get("cost",0))],"buy",{"qty":qty,"quote":fuel})
		else:ui.paragraph(body,"%d fuel: %s"%[qty,str(fuel.get("message","No current purchase is available."))],15,ui.GOLD)
	_button(ui,body,entry,"Refresh entry and fuel prices","refresh")

static func _offers(ui,body: Node,c,entry: Dictionary) -> void:
	var offers: Array=c.Arc118.warrant_offers(c)
	if offers.is_empty():
		ui.paragraph(body,"No current funded passage is available near Brass Haven. Review the account above; you may keep watching instead of reporting an unresolved request.",15,ui.GOLD)
		return
	for offered in offers:
		var q: Dictionary=c.Arc118.warrant_quote(c,offered)
		var offer: Dictionary=q.get("offer",offered)
		var owner: Dictionary=c.fleet_owner(str(offer.get("ownerId","")))
		_passage(ui,body,c,offer)
		ui.paragraph(body,"%s's own purse: %s coins available; proposed held fee %s coins."%[str(owner.get("name","The convoy owner")),ui.money(owner.get("coins",0)),ui.money(offer.get("reward",0))],15)
		ui.paragraph(body,"Any application dated on acceptance is an unverified claim. This offer establishes no earlier guarantee payment or guilt.",15)
		var reserve: Dictionary=q.get("reserve",{})
		if not reserve.is_empty():ui.paragraph(body,"Your purse: %s coins. Operating allowance: %s wage coins, %.2f food and %.2f loaded fuel for the delivery, return and contingency. These reserves are separate from the client's fee."%[ui.money(c.state.get("coins",0)),ui.money(reserve.get("returnWages",0)),float(reserve.get("foodRequired",0)),float(reserve.get("fuelRequired",0))],15)
		if q.get("ok",false):_button(ui,body,entry,"Accept funded escort (%s held coins)"%ui.money(offer.get("reward",0)),"accept",{"quote":q})
		else:ui.paragraph(body,str(q.get("message","Review this passage again before accepting.")),15,ui.GOLD)
		var detail: Node=_details(ui,body,"Original load, route and operating allowance")
		_manifest(ui,detail,c,offer)
		ui.paragraph(detail,"Deadline day %.2f. Unearned escrow returns to its original client; your incurred voyage costs remain."%float(offer.get("deadlineDay",0)),15)
		for warning in reserve.get("warnings",[]):ui.paragraph(detail,str(warning),14,ui.GOLD)
		for boat in reserve.get("boats",[]):ui.paragraph(detail,"%s: %.2f loaded fuel / %.2f required."%[str(boat.get("name","Your boat")),float(boat.get("loadedFuel",0)),float(boat.get("fuelRequired",0))],14)

static func _carried(ui,body: Node,c,entry: Dictionary,a: Dictionary) -> void:
	var job: Dictionary=_job(c,a)
	if job.is_empty():ui.paragraph(body,"Refresh the passage record before taking further action.",15,ui.GOLD);_button(ui,body,entry,"Refresh passage record","refresh");return
	var route: Dictionary=job.get("escort",{})
	_passage(ui,body,c,job)
	ui.paragraph(body,"%s; client escrow held %s coins. %s"%[str(job.get("state","Open")).capitalize(),ui.money(job.get("escrow",0)),str(route.get("failure",""))],15)
	var actions=ui.row(body)
	if str(job.get("state",""))=="active" and not job.get("failed",false) and not route.get("arrived",false) and not route.get("battlePending",false):_button(ui,actions,entry,"Stop following" if a.get("follow",false) else "Follow the original boats","follow",{"enabled":not bool(a.get("follow",false))})
	_button(ui,actions,entry,"Review delivery route","route")
	_button(ui,actions,entry,"Coastal watch","watch")
	var here: Dictionary=c.current_port()
	if not here.is_empty():
		if str(here.get("id",""))==str(job.get("targetPort","")) and str(job.get("state",""))=="active" and not job.get("failed",false) and route.get("arrived",false) and not route.get("battlePending",false):_button(ui,body,entry,"Collect the held escort fee","collect")
		_button(ui,body,entry,"Close escort; refund unearned escrow","refund")
	else:ui.paragraph(body,"Close the account at a harbor. The earned fee is collected at %s after delivery and sale."%_port(c,str(job.get("targetPort",""))),15)
	_manifest(ui,_details(ui,body,"Original boats and accepted cargo"),c,job)

static func _passage(ui,body: Node,c,offer: Dictionary) -> void:
	var owner: Dictionary=c.fleet_owner(str(offer.get("ownerId","")))
	var e: Dictionary=offer.get("escort",{})
	ui.paragraph(body,"%s: %d original loaded boats, %.2f %s, bound for %s. Agreed fee %s coins."%[str(owner.get("name","Convoy owner")),e.get("carrierUids",[]).size(),float(e.get("tradeQty",0)),_good(c,str(e.get("tradeGood",""))),_port(c,str(offer.get("targetPort",""))),ui.money(offer.get("reward",0))],16,ui.GOLD)

static func _manifest(ui,body: Node,c,offer: Dictionary) -> void:
	var e: Dictionary=offer.get("escort",{})
	ui.paragraph(body,"%s to %s."%[_port(c,str(e.get("fromPort",""))),_port(c,str(offer.get("targetPort","")))],15)
	var index: int=0
	for uid in e.get("carrierUids",[]):
		index+=1
		var boat: Dictionary=c.find_boat(str(uid))
		var lots: Array[String]=[]
		for good in e.get("carrierCargo",{}).get(uid,{}):
			var qty: float=float(e.carrierCargo[uid][good])
			if qty>0:lots.append("%.2f %s"%[qty,_good(c,str(good))])
		ui.paragraph(body,"%s: %s."%[str(boat.get("name","Original carrier %d"%index)),", ".join(lots) if not lots.is_empty() else "no cargo recorded"],15)

static func _summary(ui,body: Node,view: Dictionary,key: String) -> void:
	if not str(view.get(key,"")).is_empty():ui.paragraph(body,str(view[key]),16,ui.GOLD)

static func _choice(ui,body: Node,c,entry: Dictionary,id: String,show_refusal: bool=true) -> void:
	var gate: Dictionary=c.Arc118.choice_gate(c,id)
	for choice in entry.get("choices",[]):
		if str(choice.get("id",""))!=id:continue
		if not gate.get("ok",false):
			if show_refusal and not str(gate.get("message","")).is_empty():ui.paragraph(body,str(gate.message),15,ui.GOLD)
			return
		if not str(choice.get("tradeoff","")).is_empty():ui.paragraph(body,str(choice.tradeoff),15)
		_button(ui,body,entry,str(choice.get("text","Continue")),id)
		return

static func _button(ui,body: Node,entry: Dictionary,label: String,action: String,args: Dictionary={}) -> void:
	var a: Dictionary=ui.host.core.Arc118.active(ui.host.core)
	var context: Dictionary={"chain":str(entry.get("chainId","")),"stage":str(entry.get("stage","")),"job":str(a.get("binding",{}).get("jobId","")),"action":action,"args":args.duplicate(true)}
	ui.button(body,label,(func(data):_act.call_deferred(ui,data)).bind(context.duplicate(true)))

static func _act(ui,context: Dictionary) -> void:
	if not _live(ui) or ui.modal_kind!="coastal_stories":return
	ui.host.sync_economy()
	if not _live(ui) or ui.modal_kind!="coastal_stories":return
	var c=ui.host.core
	var rec: Dictionary=c.state.get("stories",{}).get("chains",{}).get(str(context.chain),{})
	var a: Dictionary=c.Arc118.active(c)
	if rec.get("done",false) or str(rec.get("stage",""))!=str(context.stage) or not owns({"chainId":context.chain,"stage":rec.get("stage","")}):_finish(ui,c.fail("This conversation has changed. Review its current account."));return
	if str(context.chain)=="common_passage110" and str(context.job)!=str(a.get("binding",{}).get("jobId","")):_finish(ui,c.fail("The carried escort has changed. Review its current account."));return
	var action: String=str(context.action)
	var args: Dictionary=context.args
	var result: Dictionary={}
	if action in CHOICES:
		var gate: Dictionary=c.Arc118.choice_gate(c,action)
		result=c.StoryOps.choose(c,str(context.chain),action) if gate.get("ok",false) else gate
	elif str(context.stage)=="fuel_work118":
		match action:
			"permission":
				var q: Dictionary=c.Arc118.passage_quote(c)
				result=c.Arc118.secure_passage(c) if _priced(args.quote,q,["cost","mode","port"]) else c.fail(str(q.get("message",""))+" Entry terms changed; review the current price.")
			"buy":
				if c.Arc118.choice_gate(c,"report_fuel118").get("ok",false):_finish(ui,c.fail("The fuel purchase is already recorded. Review its account before ordering more."));return
				var q: Dictionary=c.Arc118.fuel_quote(c,int(args.qty))
				result=c.Arc118.buy_fuel(c,int(args.qty)) if _priced(args.quote,q,["qty","price","cost"]) else c.fail(str(q.get("message",""))+" Fuel terms changed; review the current price.")
			"refresh":result=c.ok("Entry and fuel quotes refreshed.")
			_:return
	elif str(context.stage)=="warrant_work118":
		match action:
			"accept":result=c.Arc118.accept_warrant(c,args.quote)
			"follow":result=c.Arc118.follow(c,bool(args.enabled))
			"collect","refund","route":
				var job: Dictionary=_job(c,a)
				if a.is_empty() or job.is_empty():_finish(ui,c.fail("This escort is no longer carried."));return
				if action=="route":ui.HarborRoute104.open(ui,str(job.get("targetPort","")));return
				if c.current_port().is_empty():_finish(ui,c.fail("Enter a harbor before closing this account."));return
				result=c.settle_voyage_job(str(job.get("id","")),action=="refund")
			"watch":ui.NavalUI.open(ui);return
			"refresh":c.NavalAI.observe(c.state);result=c.ok("Current coastal offers refreshed.")
			_:return
	else:return
	_finish(ui,result,action=="follow" and result.get("ok",false))

static func _priced(shown: Dictionary,current: Dictionary,keys: Array) -> bool:
	if not shown.get("ok",false) or not current.get("ok",false):return false
	for key in keys:
		if not shown.has(key) or not current.has(key):return false
		var old=shown[key]
		var now=current[key]
		if typeof(old) in [TYPE_INT,TYPE_FLOAT] and typeof(now) in [TYPE_INT,TYPE_FLOAT]:
			if float(old)!=float(now):return false
		elif old!=now:return false
	return true

static func _job(c,a: Dictionary) -> Dictionary:
	var b: Dictionary=a.get("binding",{})
	if b.is_empty():return {}
	var job: Dictionary=c.EscortOps.contracted(c,str(b.get("ownerId","")))
	if str(job.get("kind",""))!="escort" or str(job.get("id",""))!=str(b.get("jobId","")) or str(job.get("ownerId",""))!=str(b.get("ownerId","")) or str(job.get("targetPort",""))!=str(b.get("targetPort","")) or int(job.get("escort",{}).get("voyageSeq",-1))!=int(b.get("voyageSeq",-2)):return {}
	return job

static func _finish(ui,result: Dictionary,close: bool=false) -> void:
	ui.host.respond(result)
	if result.get("ok",false):ui.host.save_game(false)
	if not _live(ui):return
	if close:ui.close_modal()
	else:ui.StoryUI.open(ui)

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
	return str(c.Goods.ITEMS.get(id,{}).get("name","cargo"))

static func _live(ui) -> bool:
	return ui!=null and is_instance_valid(ui) and ui.host!=null and is_instance_valid(ui.host) and ui.host.mode=="campaign"
