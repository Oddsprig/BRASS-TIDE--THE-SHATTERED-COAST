extends RefCounted

static func controls(ui,body: Node,entry: Dictionary) -> void:
	if str(entry.get("chainId",""))!="common_passage110":return
	var c=ui.host.core
	var arc=c.Arc110
	var lead: Dictionary=arc.record(c).get("lead110",{})
	if not lead.is_empty():ui.paragraph(body,"Tobin's departure entry, day %.2f: %s, Kelp Reach to %s. This is a dated route report; current position and load must be reacquired at sea."%[float(lead.day),str(lead.name),str(c.port(str(lead.targetPort)).get("name",lead.targetPort))],15,ui.GOLD)
	if str(entry.get("stage",""))!="escort_work110":return
	var bound: Dictionary=arc.pending(c)
	var receipt: Dictionary=arc.completed(c,arc.OPENING)
	if not receipt.is_empty():
		ui.paragraph(body,"Delivered %.1f %s. The client released %s coins. Tobin is waiting at Brass Haven."%[float(receipt.tradeQty),str(receipt.tradeGood),ui.money(receipt.reward)],16,ui.TEAL)
		ui.button(body,"Chart return to Brass Haven",func():ui.host.sail_to("brass_haven");ui.close_modal())
		return
	if bound.is_empty():
		var clients: Array=arc.clients(c)
		if clients.is_empty():
			ui.paragraph(body,"No funded loaded merchant is currently within hailing range. Tobin's departure report points to the Kelp Reach routes. Approach a peaceful moving convoy within 600 units, then refresh this journal. The merchant keeps sailing while you look for it.",16)
			ui.button(body,"Review route to Kelp Reach",func():ui.HarborRoute104.open(ui,"kelp_reach"))
			ui.button(body,"Coastal traffic and observed routes",func():ui.NavalUI.open(ui))
		else:
			for item in clients.slice(0,3):
				var offer: Dictionary=item
				ui.paragraph(body,"%s · %.1f %s in %d loaded boat(s) · %s client coins held until delivery"%[str(offer.title),float(offer.escort.tradeQty),str(offer.escort.tradeGood),offer.escort.carrierUids.size(),ui.money(offer.reward)],16,ui.GOLD)
				var reserve: Dictionary=arc.reserve_quote(c,offer)
				if not reserve.is_empty():
					ui.paragraph(body,"Your allowance: %.2f escort days, %.2f days home and two contingency days. Reserve %s coins for payroll; %.1f food and %.1f loaded fuel. The client fee is paid after delivery."%[float(reserve.outwardDays),float(reserve.returnDays),ui.money(reserve.returnWages),float(reserve.foodRequired),float(reserve.fuelRequired)],15)
					for warning in reserve.warnings:ui.paragraph(body,str(warning),14,ui.GOLD)
				ui.button(body,"Accept this campaign escort",(func(terms):_accept.call_deferred(ui,terms)).bind(offer.duplicate(true)),true).disabled=reserve.is_empty() or not bool(reserve.get("readyForAllowance",false))
		ui.button(body,"Refresh current local watch",func():c.NavalAI.observe(c.state);ui.StoryUI.open(ui))
		return
	var job: Dictionary=c.VoyageJobs._find(c.state,str(bound.jobId))
	if job.is_empty():
		ui.paragraph(body,"This convoy contract is unavailable. Close it before seeking another client.",16,ui.RED)
		return
	ui.paragraph(body,"%s · %.0f / %.0f route units accompanied · report at %s · deadline day %.2f"%[str(job.title),float(job.escort.accompaniedDistance),float(job.escort.routeDistance),str(c.port(str(job.targetPort)).name),float(job.deadlineDay)],16,ui.GOLD)
	if job.get("failed",false) or str(job.state)!="active":
		ui.paragraph(body,str(job.escort.get("failure","The passage expired; the client’s held fee is refunded under the contract terms.")),16,ui.RED)
	elif job.escort.get("arrived",false):
		ui.button(body,"Collect the client's held escort fee",func():_settle.call_deferred(ui,str(job.id)),true)
	else:
		ui.button(body,"Stop following" if bound.get("follow",false) else "Follow contracted merchant",func():_follow.call_deferred(ui,not bool(bound.get("follow",false))),true)
		var threat: Dictionary=c.EscortOps.threat(c,c.fleet_owner(str(bound.ownerId)))
		if not threat.is_empty():ui.button(body,"Protect merchant through the interception",func():c.EscortOps.start(ui.host,str(bound.ownerId)))
	ui.button(body,"Withdraw escort and refund client",func():_withdraw.call_deferred(ui))

static func _live(ui) -> bool:
	return ui!=null and is_instance_valid(ui) and ui.host!=null and is_instance_valid(ui.host) and ui.host.mode=="campaign"

static func _accept(ui,quote: Dictionary) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	ui.host.respond(ui.host.core.Arc110.accept_escort(ui.host.core,quote))
	ui.host.save_game(false)
	ui.StoryUI.open(ui)

static func _settle(ui,id: String) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	ui.host.respond(ui.host.core.settle_voyage_job(id))
	ui.host.save_game(false)
	ui.StoryUI.open(ui)

static func _follow(ui,enabled: bool) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	var result: Dictionary=ui.host.core.Arc110.follow(ui.host.core,enabled)
	ui.host.respond(result)
	if result.get("ok",false):ui.close_modal()

static func _withdraw(ui) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	var c=ui.host.core
	var job: Dictionary=c.VoyageJobs._find(c.state,str(c.Arc110.pending(c).get("jobId",""))).duplicate(true)
	var result: Dictionary=c.VoyageJobs.abandon(c,str(job.get("id","")))
	c.Arc110.after_job(c,job,result,true)
	ui.host.respond(result)
	ui.host.save_game(false)
	ui.StoryUI.open(ui)
