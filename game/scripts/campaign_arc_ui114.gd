# campaign_arc_ui114.gd
extends RefCounted

static func controls(ui, body: Node, entry: Dictionary) -> void:
	if not _live(ui):return
	if str(entry.get("chainId",""))!="common_passage110":return
	if str(entry.get("stage","")) not in ["route_work114","route_account114"]:return
	var c=ui.host.core
	var w: Dictionary=c.Arc114.work(c)
	var owner_id: String=str(w.get("ownerId",""))
	var reported: bool=bool(w.get("reported",false))
	if owner_id.is_empty():
		var targets: Array=c.Arc114.targets(c)
		if targets.is_empty():
			ui.paragraph(body,"Visit Cass at Rust Anchorage for the current contact. Coastal watch shows existing fleets and their last sightings. Refresh after the situation changes.",16)
		for target in targets:
			var count: int=int(target.get("boats",0))
			ui.paragraph(body,"%s: %d %s"%[str(target.get("name","Fleet")),count,"boat" if count==1 else "boats"],17,ui.GOLD)
			ui.button(body,"Choose this fleet",(func(id):_bind.call_deferred(ui,id)).bind(str(target.get("ownerId",""))),true)
	else:
		var owner: Dictionary=c.fleet_owner(owner_id)
		var name: String=str(owner.get("name","")).strip_edges()
		if name.is_empty():name="The identified fleet"
		var count: int=w.get("targetUids",[]).size()
		ui.paragraph(body,"%s: %d original %s identified"%[name,count,"boat" if count==1 else "boats"],17,ui.GOLD)
		if owner.is_empty():ui.paragraph(body,"This fleet is no longer available for contact.",16)
		if not reported:
			_quote(ui,body,c)
			if _can_hail(c,owner_id):
				ui.button(body,"Hail this fleet",(func(id):_hail.call_deferred(ui,id)).bind(owner_id))
			_wrecks(ui,body,c,w)
		else:
			_outcome(ui,body,c,w)
			return
	ui.paragraph(body,"After a raid, secure original property and sail with it to a different harbor where you have lawful access. Arrive and stop there before reporting to Cass.",16)
	ui.paragraph(body,"The battle's 12-second withdrawal ends the encounter. A battle win or bounty payment does not complete the return voyage.",15)
	if not reported:
		var readiness: Dictionary=c.Arc114.choice_gate(c,"report_property114")
		var message: String=str(readiness.get("message","")).strip_edges()
		if not message.is_empty():ui.paragraph(body,message,16,ui.TEAL if readiness.get("ok",false) else ui.GOLD)
	ui.button(body,"Coastal watch and last sightings",func():ui.NavalUI.open(ui))
	var anvil: Dictionary=c.port("anvil_dock")
	if not anvil.is_empty():
		ui.button(body,"Review route to "+str(anvil.get("name","Anvil Dock")),func():ui.HarborRoute104.open(ui,"anvil_dock"))
	ui.button(body,"Refresh",func():_refresh.call_deferred(ui))

static func _outcome(ui,body: Node,c,w: Dictionary) -> void:
	var resolution: String=str(w.get("resolution",""))
	if resolution=="released":
		var release: Dictionary=w.get("release",{})
		ui.label(body,"Cargo release completed",21,ui.GOLD,true)
		ui.paragraph(body,"%.0f %s released for %s coins."%[float(release.get("qty",0)),str(c.Goods.ITEMS.get(str(release.get("good","")),{}).get("name","cargo")),ui.money(release.get("cost",0))],17)
	elif resolution=="raid":
		var arrival: Dictionary=w.get("arrival",{})
		var destination: Dictionary=c.port(str(arrival.get("port","")))
		ui.label(body,"Raid property returned",21,ui.GOLD,true)
		ui.paragraph(body,"An original %s arrived at %s."%["captured hull" if str(arrival.get("kind",""))=="hull" else "recovered fitting",str(destination.get("name","the return harbor"))],17)
	else:
		ui.label(body,"No recovery reported",21,ui.GOLD,true)
		ui.paragraph(body,"This attempt closed without recovered property or a reward.",17)
	var report_port: Dictionary=c.port(str(w.get("debrief",{}).get("port","")))
	ui.paragraph(body,"Cass received your account from %s."%str(report_port.get("name","the reporting harbor")),16)

static func _quote(ui, body: Node, c) -> void:
	var q: Dictionary=c.Arc114.release_quote(c)
	var item: Dictionary=c.Goods.ITEMS.get(str(q.get("good","")),{})
	if not item.is_empty():
		ui.paragraph(body,"Release: %.2f %s"%[float(q.get("qty",0)),str(item.get("name","Cargo"))],17,ui.GOLD)
		ui.paragraph(body,"%s coins each; %s coins total."%[ui.money(q.get("unitPrice",0)),ui.money(q.get("cost",0))],16)
	ui.paragraph(body,"A paid release records the completed cargo transfer. The goods may subsequently be used or sold.",15)
	var message: String=str(q.get("message","")).strip_edges()
	if not message.is_empty():ui.paragraph(body,message,16)
	ui.button(body,"Pay for this release",(func(shown):_release.call_deferred(ui,shown)).bind(q.duplicate(true)),true).disabled=not bool(q.get("ok",false))

static func _wreck_id(row) -> String:
	return str(row.get("id","")) if row is Dictionary else str(row)

static func _wrecks(ui, body: Node, c, w: Dictionary) -> void:
	for known in w.get("wrecks",[]):
		var id: String=_wreck_id(known)
		if id.is_empty():continue
		var wreck: Dictionary=c.Salvage.find_wreck(c.state,id)
		if wreck.is_empty():continue
		var distance: float=c.distance(c.state.position,wreck)
		ui.paragraph(body,"Identified wreck: %s, %.0f water units away."%[str(wreck.get("name","Wreck")),distance],16)
		ui.button(body,"Review wreck recovery",(func(wid):_recover.call_deferred(ui,wid)).bind(id)).disabled=not c.home_local064() or distance>180
		if distance>180:ui.paragraph(body,"Approach within 180 water units to review recovery.",15)

static func _can_hail(c, owner_id: String) -> bool:
	if owner_id.is_empty() or not c.home_local064():return false
	for sight in c.NavalAI.sightings(c.state):
		if str(sight.get("ownerId",""))!=owner_id or not sight.get("current",false):continue
		var patrol: Dictionary=c.NavalAI._find_patrol(c.state,owner_id)
		return not patrol.is_empty() and c.distance(c.state.position,patrol)<=1800
	return false

static func _live(ui) -> bool:
	return ui!=null and is_instance_valid(ui) and ui.host!=null and is_instance_valid(ui.host) and ui.host.mode=="campaign"

static func _bind(ui, owner_id: String) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	_finish(ui,ui.host.core.Arc114.bind(ui.host.core,owner_id))

static func _release(ui, shown: Dictionary) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	var c=ui.host.core
	_finish(ui,c.Arc114.release(c,shown))

static func _hail(ui, owner_id: String) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	var c=ui.host.core
	if str(c.Arc114.work(c).get("ownerId",""))!=owner_id or not _can_hail(c,owner_id):
		_finish(ui,c.fail("This fleet is no longer available to hail. Check Coastal watch."))
		return
	ui.host.show_patrol_encounter(owner_id)

static func _recover(ui, id: String) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	var c=ui.host.core
	var known: bool=false
	for row in c.Arc114.work(c).get("wrecks",[]):
		if _wreck_id(row)==id:
			known=true
			break
	var wreck: Dictionary=c.Salvage.find_wreck(c.state,id)
	if not known or wreck.is_empty() or not c.home_local064() or c.distance(c.state.position,wreck)>180:
		_finish(ui,c.fail("Approach the identified wreck within 180 water units before reviewing recovery."))
		return
	ui.StoryUI._open_recovery(ui,id)

static func _refresh(ui) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	ui.host.save_game(false)
	ui.StoryUI.open(ui)

static func _finish(ui, result: Dictionary) -> void:
	ui.host.respond(result)
	ui.host.save_game(false)
	ui.StoryUI.open(ui)
