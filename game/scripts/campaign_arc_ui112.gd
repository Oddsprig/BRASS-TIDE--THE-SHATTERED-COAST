extends RefCounted

static func controls(ui,body: Node,entry: Dictionary) -> void:
	if str(entry.get("chainId",""))!="common_passage110" or str(entry.get("stage","")) not in ["withdrawal_work112","wren_account112"]:return
	var c=ui.host.core
	var w: Dictionary=c.Arc112.work(c)
	if w.is_empty():
		var offers: Array=c.Arc112.offers(c)
		if offers.is_empty():
			ui.paragraph(body,"Approach a loaded convoy leaving Kelp Reach. Its captain must have crewed boats, a current water route and enough coins to fund the escort.",16)
			ui.button(body,"Review route to Kelp Reach",func():ui.HarborRoute104.open(ui,"kelp_reach"))
		for item in offers.slice(0,3):
			var offer: Dictionary=item
			var allowance: Dictionary=c.Arc110.reserve_quote(c,offer)
			ui.paragraph(body,"%s · %d loaded boats · %s coins held until delivery"%[str(offer.title),offer.escort.carrierUids.size(),ui.money(offer.reward)],17,ui.GOLD)
			if not allowance.is_empty():
				ui.paragraph(body,"Your reserves: %s coins for payroll, %.1f food and %.1f loaded fuel. Includes the escort, return to Brass Haven and two contingency days."%[ui.money(allowance.returnWages),float(allowance.foodRequired),float(allowance.fuelRequired)],15)
				for warning in allowance.get("warnings",[]):ui.paragraph(body,str(warning),14,ui.GOLD)
			ui.button(body,"Accept this Kelp departure",(func(terms):_accept.call_deferred(ui,terms)).bind(offer.duplicate(true)),true).disabled=allowance.is_empty() or not bool(allowance.get("readyForAllowance",false))
		ui.button(body,"Coastal traffic and observed routes",func():ui.NavalUI.open(ui))
		ui.button(body,"Refresh coastal watch",func():_refresh.call_deferred(ui))
		return
	var tally: Dictionary=c.Arc112.counts(c)
	ui.paragraph(body,"Escaped: %d · Arrived at harbor: %d · Sunk: %d · Captured: %d · Unconfirmed: %d"%[int(tally.get("escaped",0)),int(tally.get("arrived",0)),int(tally.get("sunk",0)),int(tally.get("captured",0)),int(tally.get("unresolved",0))],17,ui.GOLD)
	var names: Dictionary={"escaped":"escaped through the battle exit","arrived":"arrived at harbor","sunk":"sunk","captured":"captured","afloat":"still exposed","stranded":"withdrawal unconfirmed","unknown":"withdrawal unconfirmed"}
	for uid in w.get("carrierUids",[]):
		var original: Dictionary=w.get("crewAtAcceptance",{}).get(uid,{})
		var outcome: Dictionary=w.get("outcomes",{}).get(uid,{})
		var fate: String=str(outcome.get("fate","unknown"))
		ui.paragraph(body,"%s — %s"%[str(original.get("name","Working boat")),str(names.get(fate,"withdrawal unconfirmed"))],15)
	var job: Dictionary=c.VoyageJobs._find(c.state,str(w.get("jobId","")))
	var status: String=str(w.get("status","carried"))
	if status=="paid":ui.paragraph(body,"Escort fee received: %s coins."%ui.money(w.get("payment",0)),16,ui.TEAL)
	elif status=="withdrawn":ui.paragraph(body,"Escort contract closed. No fee received.",16)
	elif not job.is_empty() and (str(job.get("state",""))!="active" or job.get("failed",false)):
		ui.paragraph(body,"Escort contract expired. Close it before sending Wren the report.",16,ui.GOLD)
	else:ui.paragraph(body,"Escort fee: %s coins held by the client. Collect at %s after the contracted delivery."%[ui.money(w.get("reward",0)),str(c.port(str(w.get("targetPort",""))).get("name","the delivery harbor"))],16)
	if w.get("reported",false) or str(entry.get("stage",""))=="wren_account112":return
	if status=="carried" and not job.is_empty():
		if str(job.get("state",""))=="active" and not job.get("failed",false) and job.get("escort",{}).get("arrived",false):ui.button(body,"Collect the held escort fee",func():_close.call_deferred(ui,false),true)
		ui.button(body,"Withdraw escort and refund client",func():_close.call_deferred(ui,true))
	if int(tally.get("unresolved",0))>0 or c.Arc112.delivery_pending(c):
		if str(c.current_port().get("id",""))==str(w.targetPort):ui.button(body,"Check this harbor's recorded arrivals",func():_check_record.call_deferred(ui))
		else:ui.button(body,"Review route to the arrival-record harbor",(func(port_id):ui.HarborRoute104.open(ui,port_id)).bind(str(w.targetPort)))
		if c.Arc112.same_passage(c):
			ui.button(body,"Stop following" if w.get("follow",false) else "Follow the original working boats",(func(enabled):_follow.call_deferred(ui,enabled)).bind(not bool(w.get("follow",false))),true)
			var threat: Dictionary=c.EscortOps.threat(c,c.fleet_owner(str(w.ownerId)))
			var protection: Dictionary=c.Arc112.protection_gate(c)
			if not protection.ok:ui.paragraph(body,str(protection.message),15,ui.GOLD)
			if not threat.is_empty():ui.button(body,"Cover the boats through the interception",(func(owner_id):_protect.call_deferred(ui,owner_id)).bind(str(w.ownerId))).disabled=not protection.ok
		else:ui.paragraph(body,"The original passage is no longer visible on this route. The remaining boats' withdrawal is still unconfirmed.",15,ui.GOLD)
		ui.button(body,"Review observed coastal traffic",func():ui.NavalUI.open(ui))
	var report: Dictionary=c.Arc112.choice_gate(c,"report_withdrawal112")
	if not report.ok:ui.paragraph(body,str(report.message),15,ui.GOLD)

static func _live(ui) -> bool:
	return ui!=null and is_instance_valid(ui) and ui.host!=null and is_instance_valid(ui.host) and ui.host.mode=="campaign"

static func _accept(ui,terms: Dictionary) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	var allowance: Dictionary=ui.host.core.Arc110.reserve_quote(ui.host.core,terms)
	if allowance.is_empty() or not allowance.get("readyForAllowance",false):
		ui.host.respond(ui.host.core.fail("Prepare the displayed payroll, food and loaded fuel reserves before accepting."));ui.StoryUI.open(ui);return
	ui.host.respond(ui.host.core.Arc112.accept(ui.host.core,terms))
	ui.host.save_game(false);ui.StoryUI.open(ui)

static func _close(ui,withdraw: bool) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	var c=ui.host.core
	var id: String=str(c.Arc112.work(c).get("jobId",""))
	ui.host.respond(c.VoyageJobs.abandon(c,id) if withdraw else c.settle_voyage_job(id))
	ui.host.save_game(false);ui.StoryUI.open(ui)

static func _follow(ui,enabled: bool) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	var result: Dictionary=ui.host.core.Arc112.follow(ui.host.core,enabled)
	ui.host.respond(result)
	if result.get("ok",false):ui.close_modal()

static func _protect(ui,owner_id: String) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	var permission: Dictionary=ui.host.core.Arc112.protection_gate(ui.host.core)
	if permission.ok:ui.host.core.EscortOps.start(ui.host,owner_id)
	else:ui.host.respond(permission)

static func _refresh(ui) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	ui.host.core.NavalAI.observe(ui.host.core.state)
	ui.StoryUI.open(ui)

static func _check_record(ui) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	ui.host.respond(ui.host.core.Arc112.check_arrival_record(ui.host.core))
	ui.host.save_game(false);ui.StoryUI.open(ui)
