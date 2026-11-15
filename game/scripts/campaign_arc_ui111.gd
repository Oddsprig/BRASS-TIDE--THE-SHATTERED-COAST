extends RefCounted

static func controls(ui,body: Node,entry: Dictionary) -> void:
	if str(entry.get("chainId",""))!="common_passage110" or str(entry.get("stage",""))!="second_signature111":return
	var c=ui.host.core
	var w: Dictionary=c.Arc111.work(c)
	if w.is_empty():
		var offers: Array=c.Arc111.offers(c)
		if offers.is_empty():
			ui.paragraph(body,"Review the current funded bounty at Brass Haven. A target must be an existing hostile raider with living boats; the sponsor must be able to hold the full fee. ",16)
			if str(c.current_port().get("id",""))!="brass_haven":ui.button(body,"Review return to Brass Haven",func():ui.HarborRoute104.open(ui,"brass_haven"))
		for row in offers:
			var terms: Dictionary=row
			var owner: Dictionary=c.fleet_owner(str(terms.ownerId))
			var count: int=owner.get("boats",[]).filter(func(boat):return not boat.get("sunk",false)).size()
			var boat_word: String="boat" if count==1 else "boats"
			ui.paragraph(body,"%s · %d original %s · %s coins held by %s · deadline day %.0f"%[str(terms.title),count,boat_word,ui.money(terms.reward),str(c.port(str(terms.port)).name),float(terms.deadlineDay)],17,ui.GOLD)
			ui.paragraph(body,"Your wages, stores, battle damage and recovery remain your costs. The bounty is paid at its sponsoring harbor after the named fleet's defeat. A fitting is recovered only through the normal paid salvage action.",15)
			ui.button(body,"Accept funded investigation",(func(offer):_accept.call_deferred(ui,offer)).bind(terms.duplicate(true)),true)
		return
	var owner: Dictionary=c.fleet_owner(str(w.ownerId))
	ui.paragraph(body,"Target: %s · original boats: %d · bounty %s"%[str(owner.get("name",w.ownerId)),w.targetUids.size(),str(w.status)],18,ui.GOLD)
	ui.paragraph(body,"Use the coastal watch to reacquire its actual boats. Stay with your repair and return reserves; a retreat leaves this investigation open.",16)
	ui.button(body,"Coastal watch and last sightings",func():ui.NavalUI.open(ui))
	for sight in c.NavalAI.sightings(c.state):
		if str(sight.get("ownerId",""))!=str(w.ownerId) or not sight.get("current",false):continue
		var patrol: Dictionary=c.NavalAI._find_patrol(c.state,str(w.ownerId))
		if c.home_local064() and not patrol.is_empty() and c.distance(c.state.position,patrol)<=1800:ui.button(body,"Hail the original target",func():ui.host.show_patrol_encounter(str(w.ownerId)))
		break
	for known in w.wrecks:
		var wreck: Dictionary=c.Salvage.find_wreck(c.state,str(known.id))
		if wreck.is_empty():continue
		ui.paragraph(body,"Identified wreck: %s · %.0f water units · %s"%[str(wreck.name),c.distance(c.state.position,wreck),str(wreck.status)],16,ui.GOLD)
		if c.home_local064():
			ui.button(body,"Chart this original wreck",(func(point):_course.call_deferred(ui,point)).bind(wreck.duplicate(true)))
			if c.distance(c.state.position,wreck)<=180:ui.button(body,"Review original fitting or hull recovery",(func(id):ui.StoryUI._open_recovery(ui,id)).bind(str(known.id)))
	if str(w.status)=="carried":
		var job: Dictionary=c.VoyageJobs._find(c.state,str(w.jobId))
		ui.paragraph(body,"Bounty report harbor: %s. Claim the fee after the target condition, or withdraw under normal refund rules. Closing it does not invent recovery evidence."%str(c.port(str(w.port)).name),15)
		if str(c.current_port().get("id",""))!=str(w.port):ui.button(body,"Review bounty report route",func():ui.HarborRoute104.open(ui,str(w.port)))
		if not job.is_empty():
			ui.button(body,"Claim the harbor's held bounty",func():_close.call_deferred(ui,false))
			ui.button(body,"Withdraw bounty and refund sponsor",func():_close.call_deferred(ui,true))
	else:
		ui.paragraph(body,"Contract %s · %s coins received. Original property and its current custody decide the separate story report."%[str(w.status),ui.money(w.payment)],16,ui.TEAL)
	var property: Dictionary=c.Arc111.choice_gate(c,"report_property111")
	ui.paragraph(body,str(property.message),15,ui.TEAL if property.ok else ui.GOLD)
	if not property.ok:
		var missing: Dictionary=c.Arc111.choice_gate(c,"report_no_property111")
		ui.paragraph(body,str(missing.message),15,ui.TEAL if missing.ok else ui.GOLD)

static func allowed(ui,entry: Dictionary,choice: String) -> bool:
	if str(entry.get("chainId",""))!="common_passage110":return true
	return bool(ui.host.core.Arc111.choice_gate(ui.host.core,choice).ok)

static func live(ui) -> bool:
	return ui!=null and is_instance_valid(ui) and ui.host!=null and is_instance_valid(ui.host) and ui.host.mode=="campaign"

static func _accept(ui,terms: Dictionary) -> void:
	if not live(ui):return
	ui.host.sync_economy()
	ui.host.respond(ui.host.core.Arc111.accept(ui.host.core,terms))
	ui.host.save_game(false);ui.StoryUI.open(ui)

static func _close(ui,abandon: bool) -> void:
	if not live(ui):return
	ui.host.sync_economy()
	var c=ui.host.core
	var id: String=str(c.Arc111.work(c).get("jobId",""))
	ui.host.respond(c.VoyageJobs.abandon(c,id) if abandon else c.settle_voyage_job(id))
	ui.host.save_game(false);ui.StoryUI.open(ui)

static func _course(ui,point: Dictionary) -> void:
	if not live(ui):return
	ui.host.sync_economy()
	ui.host.respond(ui.host.core.chart_course(point));ui.close_modal()
