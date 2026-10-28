extends RefCounted
const Stories=preload("res://scripts/coastal_stories.gd")
static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	c.StoryOps.ensure(c)
	var p: Dictionary=c.current_port()
	if not p.is_empty() and c.Politics.access(c,p).legal:c.Contacts.visit(c.state,p,c.state.day)
	ui.modal_kind="coastal_stories"
	var body=ui.modal("Coastal stories & expedition leads","FOUR ORIGINAL CHAINS · DECISIONS THAT OPEN DIFFERENT WORK",1070,820)
	ui.paragraph(body,"Keep several leads alongside your paid voyage jobs. Surveys, deliveries and actual fleet defeats advance them. Knowledge and relationships are the rewards; any later freight or business still needs a real sponsor, materials and workers.",16)
	for row in Stories.journal(c.state):
		var entry: Dictionary=row
		ui.rule(body)
		ui.label(body,entry.title+" · "+("Complete" if entry.done else entry.approach.capitalize()),26,ui.GOLD,true)
		var stage: Dictionary=Stories._stage_def(Stories._chain_def(c.state,entry.chainId),entry.stage)
		ui.paragraph(body,str(stage.get("body","")),17,ui.TEXT)
		ui.paragraph(body,entry.nextAction,16,ui.TEAL)
		for item in entry.get("earnedLeads",[]):
			var lead: Dictionary=item
			ui.paragraph(body,"Earned lead: "+str(lead.name)+" · "+str(lead.nextAction),15,ui.TEAL)
			ui.button(body,"Inspect & prepare "+str(lead.name),func():ui.CampaignUI.site(ui,str(lead.id)))
		payoff(ui,body,entry)
		if entry.done:continue
		var location: Dictionary=entry.location
		ui.button(body,"Chart "+location.name,func():ui.host.respond(c.chart_course({"x":location.x,"y":location.y},location.id if location.kind=="port" else ""));ui.close_modal())
		var gate: Dictionary=Stories._gate(c,c.state,stage.get("gate",{}))
		if not gate.ok:ui.paragraph(body,gate.message,14,ui.RED)
		for option in entry.choices:
			var choice: Dictionary=option
			ui.paragraph(body,choice.tradeoff,15)
			ui.button(body,choice.text,func():ui.host.respond(c.StoryOps.choose(c,entry.chainId,choice.id));ui.host.save_game(false);open(ui),true).disabled=not gate.ok or (not str(choice.get("requiresFlag","")).is_empty() and not entry.flags.has(choice.requiresFlag))
	ui.rule(body)
	ui.label(body,"Harbor leads",26,ui.GOLD,true)
	var offers: Array=Stories.available(c)
	for item in offers:
		var offer: Dictionary=item
		ui.label(body,offer.title,23,ui.GOLD,true)
		ui.paragraph(body,offer.summary,16)
		ui.button(body,"Hear this contact's lead",func():ui.host.respond(c.StoryOps.start(c,offer.id));ui.host.save_game(false);open(ui))
	if offers.is_empty():ui.paragraph(body,"Visit Tobin at Brass Haven, Wren at Reedwater Floats, Cass at Rust Anchorage, or Mara at Anvil Dock. Their leads stay in this journal once accepted.",16)
	ui.button(body,"Funded voyage jobs & contacts",func():ui.VoyageUI.open(ui))

static func payoff(ui,body: Node,entry: Dictionary) -> void:
	var c=ui.host.core
	var outcome: Dictionary=entry.get("outcome",{})
	if not outcome.is_empty():
		ui.label(body,str(outcome.title),22,ui.GOLD,true)
		ui.paragraph(body,str(outcome.body),16)
		for consequence in outcome.get("consequences",[]):
			var recipient: String=str(consequence.target)
			if str(consequence.kind)=="contact":recipient=str(c.Contacts._find(c.state,recipient).get("name",recipient))
			elif str(consequence.kind)=="faction":recipient=str(c.Factions.standing(c.state,recipient).get("name",recipient))
			ui.paragraph(body,"%s · %+d · %s (%s)"%[recipient,int(consequence.amount),consequence.reason,"recorded" if consequence.applied else "pending"],14,ui.TEAL)
		var charter: Dictionary=outcome.get("charter",{})
		if not charter.is_empty():
			ui.paragraph(body,str(charter.conditions),14)
			var harbors: Array[String]=[]
			for id in charter.portIds:
				var candidate: Dictionary=c.port(str(id))
				if not candidate.is_empty():harbors.append(str(candidate.name))
			ui.paragraph(body,"Candidate charter harbors: "+", ".join(harbors)+". The local paid quote still decides access and availability.",14)
			var port: Dictionary=c.current_port()
			if not port.is_empty() and str(port.id) in charter.portIds:
				var q: Dictionary=ui.HomeUI.Home.quote(c,str(charter.kind),str(port.id))
				ui.paragraph(body,str(q.message),14,ui.TEAL if q.ok and q.get("affordable",false) else ui.GOLD)
				if q.ok and q.get("affordable",false):ui.button(body,"Review paid salvage yard charter",func():ui.HomeUI.open(ui))
	for item in entry.get("recoverySites",[]):
		var site: Dictionary=item
		ui.paragraph(body,"Finite recovery at "+str(site.name)+": "+recovery_stock(site)+". Available after survey; taking rights later does not remove recovered cargo.",14)
		ui.button(body,"Inspect recovery landing: "+str(site.name),func():ui.CampaignUI.site(ui,str(site.id)))
		for id in site.wreckIds:
			var wreck_id: String=str(id)
			var permission: Dictionary=recovery_ready(c,wreck_id)
			if permission.ok:ui.button(body,"Review actual wreck recovery",func():ui.RecoveryUI.open(ui,wreck_id))
			else:ui.paragraph(body,str(permission.message),14,ui.GOLD)

static func recovery_stock(site: Dictionary) -> String:
	var lots: Array[String]=[]
	for stock in [site.remainingComponents,site.remainingStores]:
		for good in stock:
			if float(stock[good])>0:lots.append("%.2f %s"%[float(stock[good]),str(good).replace("_"," ")])
	return ", ".join(lots) if not lots.is_empty() else "no unclaimed stock remaining"

static func recovery_ready(c,wreck_id: String) -> Dictionary:
	var w: Dictionary=c.Salvage.find_wreck(c.state,wreck_id)
	if w.is_empty():return {"ok":false,"message":"This finite wreck is no longer available."}
	if c.distance(c.state.position,w)>180:return {"ok":false,"message":"Approach within 180 water units to review recovery here."}
	var hazard: Dictionary=c.fleet_owner(str(c.state.get("wreckHazards",{}).get(w.sourceId,"")))
	if not hazard.is_empty() and hazard.active and hazard.boats.any(func(b):return not b.sunk):return {"ok":false,"message":"Hostiles control this wreck; leave it marked or fund the extra risk before returning."}
	if not c.state.path.is_empty() or not c.state.exploration.assignment.is_empty():return {"ok":false,"message":"Stop and recall the survey party before recovery."}
	var physical: String=c.Salvage.Recovery.refusal(w)
	if not physical.is_empty():return {"ok":false,"message":physical}
	var strip: Dictionary=c.Salvage.quote(c,wreck_id,"strip")
	if strip.ok and c.Exploration.spare_crew(c.state)>=1:return strip
	var tow: Dictionary=c.Salvage.quote(c,wreck_id,"tow")
	if tow.ok:return tow
	# A smaller finite lot can fit even when the whole wreck cannot.
	if c.Exploration.spare_crew(c.state)>=1 and str(w.status)=="unclaimed":
		for good in c.Salvage._strip_items(w):
			if c.Goods.ITEMS.has(good) and c.capacity()-c.cargo_weight()>=float(c.Goods.ITEMS[good].weight)*0.01:return {"ok":true,"message":"Review a partial finite recovery lot."}
	return {"ok":false,"message":str(strip.message)+" "+str(tow.message)}
