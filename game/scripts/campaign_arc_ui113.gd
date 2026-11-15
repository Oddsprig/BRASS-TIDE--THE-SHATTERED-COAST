# campaign_arc_ui113.gd
extends RefCounted

static func controls(ui, body: Node, entry: Dictionary) -> void:
	if not _live(ui):return
	var chain: String=str(entry.get("chainId",""))
	var stage: String=str(entry.get("stage",""))
	if chain=="mara_work113":
		if stage in ["mara_quote113","mara_account113"]:_mara(ui,body)
		return
	if chain!="common_passage110" or stage not in ["useful_enemy113","materials_work113","material_account113"]:return
	var c=ui.host.core
	var w: Dictionary=c.Arc113.work(c)
	var here: String=str(c.current_port().get("id",""))
	var id: String=str(w.get("jobId",""))
	var status: String=str(w.get("status",""))
	var native: Dictionary=c.VoyageJobs._find(c.state,id) if not id.is_empty() else {}
	if w.is_empty():
		ui.paragraph(body,"No reserve order has been accepted.",16)
		if stage=="material_account113":ui.paragraph(body,"No materials delivered. No fee received.",16)
	else:
		var qty: float=float(w.get("qty",0))
		var payment=w.get("payment",0)
		if not id.is_empty():_route(ui,body,c,str(w.get("origin","")),str(w.get("target","")),str(w.get("good","")))
		ui.paragraph(body,"Accepted: %.1f kits · Contract delivery completed: %.1f kits"%[qty,qty if status=="delivered" else 0.0],17,ui.GOLD)
		if status=="carried":
			if native.get("failed",false) or native.get("freight",{}).get("lost",false):ui.paragraph(body,"The consignment cannot complete delivery. Close the order at a harbor.",16,ui.GOLD)
			elif str(native.get("state",""))=="expired":ui.paragraph(body,"The order expired. Close it at a harbor to return any remaining freight.",16,ui.GOLD)
			else:ui.paragraph(body,"The freight is aboard. Delivery is pending.",16)
		elif status=="delivered":ui.paragraph(body,"The harbor has received the freight.",16)
		elif status=="withdrawn":ui.paragraph(body,"The freight order closed without delivery.",16)
		elif status=="unfilled":ui.paragraph(body,"The request remains unfilled.",16)
		ui.paragraph(body,"Agreed delivery fee: %s coins. Fee received: %s coins."%[ui.money(w.get("reward",0)),ui.money(payment)],16)
		var invoice=w.get("materialInvoice",null)
		if invoice is int or invoice is float:
			ui.paragraph(body,"Public materials invoice: %s coins."%ui.money(invoice),16)
		if status=="withdrawn":
			var closure: Dictionary=w.get("closure",{})
			var actual_unloaded: float=maxf(0,float(closure.get("stockAfter",0))-float(closure.get("stockBefore",0)))
			var unloading: Dictionary=c.port(str(closure.get("unloadPort","")))
			if actual_unloaded>0:ui.paragraph(body,"%.1f kits unloaded at %s. No delivery fee received."%[minf(qty,actual_unloaded),str(unloading.get("name","the closing harbor"))],16)
			else:ui.paragraph(body,"No kits unloaded. No delivery fee received.",16)
		if status=="unfilled" and float(payment)==0.0:
			ui.paragraph(body,"No materials delivered. No fee received.",16)
	if id.is_empty() and stage=="materials_work113":
		var q: Dictionary=c.Arc113.offer(c)
		if q.is_empty():
			ui.paragraph(body,"No public order is available to accept here now. You can report the request unfilled.",16)
			ui.paragraph(body,"The order needs exportable kits, public funds, free cargo space and a reachable Cinder Quay route.",15)
		else:
			var freight: Dictionary=q.get("freight",{})
			_route(ui,body,c,"anvil_dock","cinder_quay",str(freight.get("good","")))
			ui.paragraph(body,"Requested: 8 kits. Funded offer: %.1f kits."%float(freight.get("qty",0)),17,ui.GOLD)
			ui.paragraph(body,"Public materials invoice: %s coins. Delivery fee on completion: %s coins."%[ui.money(q.materialInvoice),ui.money(q.reward)],16)
			ui.paragraph(body,"No funds are held until acceptance. Your crew, fuel and other operating costs are separate.",16)
			ui.button(body,"Accept this reserve order",(func(shown):_accept.call_deferred(ui,shown)).bind(q.duplicate(true)),true).disabled=float(freight.get("qty",0))<=0.0
		if here!="anvil_dock":_route_button(ui,body,c,"anvil_dock")
	if status=="carried":
		var valid: bool=_valid_job(c,w) and not native.is_empty()
		var target: String=str(w.get("target",""))
		ui.button(body,"Deliver the freight",func():_settle.call_deferred(ui,id,false),true).disabled=not valid or here!=target or native.get("failed",false) or str(native.get("state",""))!="active"
		ui.button(body,"Withdraw this freight order",func():_settle.call_deferred(ui,id,true)).disabled=not valid or here.is_empty()
		if valid and here!=target:_route_button(ui,body,c,target)
	elif stage=="useful_enemy113" and here!="cinder_quay":
		_route_button(ui,body,c,"cinder_quay")
	ui.button(body,"Refresh",func():_refresh.call_deferred(ui))

static func _route(ui, body: Node, c, origin_id: String, target_id: String, good: String) -> void:
	var origin: Dictionary=c.port(origin_id)
	var target: Dictionary=c.port(target_id)
	var item: Dictionary=c.Goods.ITEMS.get(good,{})
	ui.paragraph(body,"%s to %s · %s"%[str(origin.get("name","Origin harbor")),str(target.get("name","Destination harbor")),str(item.get("name","Repair kits"))],17,ui.GOLD)

static func _route_button(ui, body: Node, c, target: String) -> void:
	var p: Dictionary=c.port(target)
	ui.button(body,"Review route to "+str(p.get("name","the harbor")),func():ui.HarborRoute104.open(ui,target))

static func _mara(ui, body: Node) -> void:
	var c=ui.host.core
	var p: Dictionary=c.current_port()
	if str(p.get("id",""))!="anvil_dock":
		ui.paragraph(body,"Mara can discuss the local repair estimate at Anvil Dock.",16)
		_route_button(ui,body,c,"anvil_dock")
		return
	var ships: Array=c.state.fleet.filter(func(b):return not b.get("sunk",false) and str(b.get("storedPort","")) in ["","anvil_dock"])
	if ships.is_empty():
		ui.paragraph(body,"No owned boat is available for an estimate at Anvil Dock.",16)
		return
	var boat: Dictionary=ships[0]
	var q: Dictionary=c.service_quote(boat,p)
	if q.is_empty() or not bool(q.get("ok",false)):
		ui.paragraph(body,"No repair estimate is available for this boat.",16)
		return
	ui.paragraph(body,"%s: repair estimate"%str(boat.get("name","Active boat")),17,ui.GOLD)
	ui.paragraph(body,"Quoted cost: %s coins. Additional kits from the harbor: %.1f."%[ui.money(q.cost),float(q.purchase)],16)
	if q.has("materials"):ui.paragraph(body,"Materials quoted: %s coins."%ui.money(q.materials),15)
	if q.has("ordinary"):ui.paragraph(body,"General labor quoted: %s coins."%ui.money(q.ordinary),15)
	if q.has("expert"):ui.paragraph(body,"Skilled labor quoted: %s coins."%ui.money(q.expert),15)
	if q.has("fee"):ui.paragraph(body,"Service fee quoted: %s coins."%ui.money(q.fee),15)
	if float(q.cost)==0.0 and float(q.purchase)==0.0:
		ui.paragraph(body,"No repair needed.",16)
	ui.paragraph(body,"This estimate does not commission the work.",16)
	ui.button(body,"Refresh repair estimate",func():_refresh.call_deferred(ui))

static func _valid_job(c, w: Dictionary) -> bool:
	return str(w.get("status",""))=="carried" and not str(w.get("jobId","")).is_empty() and float(w.get("qty",0))>0.0 and c.Goods.ITEMS.has(str(w.get("good",""))) and not c.port(str(w.get("target",""))).is_empty()

static func _live(ui) -> bool:
	return ui!=null and is_instance_valid(ui) and ui.host!=null and is_instance_valid(ui.host) and ui.host.mode=="campaign"

static func _accept(ui, shown: Dictionary) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	_finish(ui,ui.host.core.Arc113.accept(ui.host.core,shown))

static func _settle(ui, id: String, abandon: bool) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	var c=ui.host.core
	var w: Dictionary=c.Arc113.work(c)
	if not _valid_job(c,w) or str(w.get("jobId",""))!=id:
		_finish(ui,c.fail("The freight order has changed. Review it again."))
		return
	if not abandon and str(c.current_port().get("id",""))!=str(w.get("target","")):
		_finish(ui,c.fail("Enter the destination harbor to deliver this freight."))
		return
	_finish(ui,c.settle_voyage_job(id,abandon))

static func _refresh(ui) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	ui.host.save_game(false)
	ui.StoryUI.open(ui)

static func _finish(ui, result: Dictionary) -> void:
	ui.host.respond(result)
	ui.host.save_game(false)
	ui.StoryUI.open(ui)
