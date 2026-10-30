extends RefCounted
const Stories=preload("res://scripts/coastal_stories.gd")
static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	c.StoryOps.ensure(c)
	var p: Dictionary=c.current_port()
	if not p.is_empty() and c.Politics.access(c,p).legal:c.Contacts.visit(c.state,p,c.state.day)
	ui.modal_kind="coastal_stories"
	var body=ui.modal("Coastal stories & expedition leads","DECISIONS THAT OPEN DIFFERENT WORK",1070,800)
	ui.paragraph(body,"Keep several leads alongside your paid voyage jobs. Surveys, deliveries and actual fleet defeats advance them. Knowledge and relationships are the rewards; any later freight or business still needs a real sponsor, materials and workers.",16)
	for row in Stories.journal(c.state):
		var entry: Dictionary=row
		ui.rule(body)
		ui.label(body,entry.title+" · "+("Complete" if entry.done else entry.approach.capitalize()),26,ui.GOLD,true)
		var stage: Dictionary=Stories._stage_def(Stories._chain_def(c.state,entry.chainId),entry.stage)
		ui.paragraph(body,str(entry.get("body",stage.get("body",""))),17,ui.TEXT)
		ui.paragraph(body,entry.nextAction,16,ui.TEAL)
		for item in entry.get("earnedLeads",[]):
			var lead: Dictionary=item
			var lead_id: String=str(lead.get("id",""))
			var lead_region: String=str(lead.get("regionId",""))
			var lead_layer: String=str(lead.get("layer",""))
			var on_chart: bool=ui.CampaignUI._is_local_or_home067(c) and _same_chart(c,lead_region,lead_layer)
			var visible: Dictionary=ui.CampaignUI._find_visible_site067(c,lead_id) if on_chart else {}
			var line: String="Earned lead: "+str(lead.get("name",lead_id))+" · "+str(lead.get("nextAction",""))
			if not visible.is_empty():
				var here: String=str(visible.get("region","")).strip_edges()
				if here.is_empty():here=_region_label(c,lead_region)
				line+=" · "+here+" · %.0f water units away"%c.distance(c.state.position,visible)
			else:
				var away: String=_region_label(c,lead_region)
				if not away.is_empty():line+=" · "+away
			ui.paragraph(body,line,15,ui.TEAL)
			var lead_label: String="Inspect & prepare "+str(lead.get("name",lead_id))
			if visible.is_empty() and not lead_region.is_empty() and not c.Exploration.region_record069(c.state,lead_region).is_empty():lead_label="Open regional navigation"
			ui.button(body,lead_label,(func(id,region,layer):_open_known.call_deferred(ui,id,region,layer)).bind(lead_id,lead_region,lead_layer))
		payoff(ui,body,entry)
		if entry.done:continue
		var location: Dictionary=entry.location
		var chart_port: String=str(location.get("id","")) if str(location.get("kind",""))=="port" else ""
		ui.button(body,"Chart "+str(location.get("name","")),(func(x,y,port):_chart.call_deferred(ui,x,y,port)).bind(float(location.get("x",0.0)),float(location.get("y",0.0)),chart_port))
		var gate: Dictionary=Stories._gate(c,c.state,stage.get("gate",{}))
		if not gate.ok:ui.paragraph(body,gate.message,14,ui.RED)
		for option in entry.choices:
			var choice: Dictionary=option
			ui.paragraph(body,str(choice.get("tradeoff","")),15)
			ui.button(body,str(choice.get("text","")),(func(chain_id,choice_id):_commit.call_deferred(ui,chain_id,choice_id)).bind(str(entry.get("chainId","")),str(choice.get("id",""))),true).disabled=not gate.ok or (not str(choice.get("requiresFlag","")).is_empty() and not entry.flags.has(choice.requiresFlag))
	ui.rule(body)
	ui.label(body,"Harbor leads",26,ui.GOLD,true)
	var offers: Array=Stories.available(c)
	for item in offers:
		var offer: Dictionary=item
		ui.label(body,offer.title,23,ui.GOLD,true)
		ui.paragraph(body,offer.summary,16)
		ui.button(body,"Hear this contact's lead",(func(id):_start.call_deferred(ui,id)).bind(str(offer.get("id",""))))
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
		var landing_id: String=str(site.get("id",""))
		ui.button(body,"Inspect recovery landing: "+str(site.get("name","")),(func(id,region,layer):_open_known.call_deferred(ui,id,region,layer)).bind(landing_id,str(site.get("regionId","")),str(site.get("layer",""))))
		for id in site.wreckIds:
			var wreck_id: String=str(id)
			var permission: Dictionary=recovery_ready(c,wreck_id)
			if permission.ok and bool(permission.get("cargoOnly",false)):ui.button(body,"Review explicit cargo lot",(func(wid):_open_recovery.call_deferred(ui,wid)).bind(wreck_id))
			elif permission.ok:ui.button(body,"Review actual wreck recovery",(func(wid):_open_recovery.call_deferred(ui,wid)).bind(wreck_id))
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
	if c.Remote067.cargo_only(w):
		if c.Exploration.spare_crew(c.state)<1:return {"ok":false,"cargoOnly":true,"message":"Cargo recovery needs an able spare sailor above the working boat minimums."}
		if c.Salvage._strip_items(w).is_empty():return {"ok":false,"cargoOnly":true,"message":"No unclaimed stock remaining."}
		return {"ok":true,"cargoOnly":true,"message":"Review one explicit finite cargo lot. Whole-cache strip is not offered."}
	var strip: Dictionary=c.Salvage.quote(c,wreck_id,"strip")
	if strip.ok and c.Exploration.spare_crew(c.state)>=1:return strip
	var tow: Dictionary=c.Salvage.quote(c,wreck_id,"tow")
	if tow.ok:return tow
	# A smaller finite lot can fit even when the whole wreck cannot.
	if c.Exploration.spare_crew(c.state)>=1 and str(w.status)=="unclaimed":
		for good in c.Salvage._strip_items(w):
			if c.Goods.ITEMS.has(good) and c.capacity()-c.cargo_weight()>=float(c.Goods.ITEMS[good].weight)*0.01:return {"ok":true,"message":"Review a partial finite recovery lot."}
	return {"ok":false,"message":str(strip.message)+" "+str(tow.message)}

static func _alive(ui) -> bool:
	return ui!=null and is_instance_valid(ui) and ui.host!=null and ui.host.mode=="campaign"

static func _same_chart(c, region_id: String, layer: String) -> bool:
	if region_id.is_empty() and layer.is_empty():return true
	var here_region: String="shatter_coast"
	var here_layer: String="home"
	if not c.home_local064():
		var view: Dictionary=c.world_view064() if c.has_method("world_view064") else {}
		here_region=str(view.get("regionId",""))
		here_layer=str(view.get("layer",""))
	if not region_id.is_empty() and region_id!=here_region:return false
	if not layer.is_empty() and layer!=here_layer:return false
	return true

static func _region_label(c, region_id: String) -> String:
	if region_id.is_empty() or c.Exploration.region_record069(c.state,region_id).is_empty():return ""
	if c.has_method("world_view064"):
		var view: Dictionary=c.world_view064()
		if str(view.get("regionId",""))==region_id and not str(view.get("name","")).strip_edges().is_empty():return str(view.get("name","")).strip_edges()
	if region_id=="shatter_coast":return "Shatter Coast"
	if region_id=="glasswind_keys":return "Glasswind Keys"
	return str(c.Exploration.region_record069(c.state,region_id).get("name","")).strip_edges()

static func _open_known(ui, site_id: String, region_id: String, layer: String) -> void:
	if not _alive(ui):return
	var c=ui.host.core
	if ui.CampaignUI._is_local_or_home067(c) and _same_chart(c,region_id,layer) and not ui.CampaignUI._find_visible_site067(c,site_id).is_empty():
		ui.CampaignUI.site(ui,site_id)
		return
	if not region_id.is_empty() and not c.Exploration.region_record069(c.state,region_id).is_empty():
		ui.open_voyage_preparation065(region_id)
		return
	ui.CampaignUI.site(ui,site_id)

static func _open_recovery(ui, wreck_id: String) -> void:
	if not _alive(ui):return
	ui.RecoveryUI.open(ui,wreck_id)

static func _chart(ui, x: float, y: float, port_id: String) -> void:
	if not _alive(ui):return
	ui.host.respond(ui.host.core.chart_course({"x":x,"y":y},port_id))
	if _alive(ui):ui.close_modal()

static func _commit(ui, chain_id: String, choice_id: String) -> void:
	if not _alive(ui):return
	var c=ui.host.core
	ui.host.respond(c.StoryOps.choose(c,chain_id,choice_id))
	ui.host.save_game(false)
	if _alive(ui):open(ui)

static func _start(ui, offer_id: String) -> void:
	if not _alive(ui):return
	var c=ui.host.core
	ui.host.respond(c.StoryOps.start(c,offer_id))
	ui.host.save_game(false)
	if _alive(ui):open(ui)
