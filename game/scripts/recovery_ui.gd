extends RefCounted
## Persistent wrecks and finite selectable material lots.
static func open(ui,focus_id: String="") -> void:
	ui.host.sync_economy()
	ui.modal_kind="recovery"
	var body=ui.modal("Wrecks & recovery","SALVAGE · TOWS · MARKED CARGO",1020,800)
	var c=ui.host.core
	ui.paragraph(body,"Recover selected lots or strip the remaining wreck. Removing structural parts rules out towing that hull. A tow needs paid tug labor and inspection, then repairs and a real crew. Recovery advances working time; wages and provisions continue.",15)
	ui.label(body,"Traveling hold %.1f / %.1f"%[c.cargo_weight(),c.capacity()],22,ui.GOLD,true)
	var count: int=0
	for raw in c.state.get("wrecks",[]):
		if raw.status!="unclaimed":continue
		if not focus_id.is_empty() and raw.id!=focus_id:continue
		var w: Dictionary=raw.duplicate(true)
		count+=1
		ui.rule(body)
		ui.label(body,w.name,24,ui.GOLD,true)
		ui.paragraph(body,"%s · %.0f water units away · recorded day%.1f"%["Friendly loss" if w.get("friendly",false) else "Marked find",c.distance(c.state.position,w),float(w.get("day",0))],14,ui.TEAL)
		var here: bool=c.distance(c.state.position,w)<=180
		if here and not c.state.path.is_empty():ui.button(body,"Idle engines for recovery",func():c.stop_sailing();open(ui,w.id))
		ui.button(body,"Chart the wreck location",func():ui.host.respond(c.chart_course(w));ui.close_modal()).disabled=not c.state.exploration.assignment.is_empty()
		var items: Dictionary=c.Salvage._strip_items(w)
		for key in items:
			var good: String=str(key)
			var qty: float=float(items[good])
			var line=ui.row(body)
			ui.label(line,"%s · %.2f"%[c.Goods.ITEMS[good].name,qty],15).size_flags_horizontal=Control.SIZE_EXPAND_FILL
			ui.button(line,"Recover 1",func():recover(ui,w.id,"strip",good,minf(1,qty))).disabled=not here
			var fits: float=minf(qty,maxf(0,c.capacity()-c.cargo_weight())/float(c.Goods.ITEMS[good].weight))
			ui.button(line,"Take what fits",func():recover(ui,w.id,"strip",good,fits)).disabled=not here or fits<=0
		var q: Dictionary=c.Salvage.quote(c,w.id,"strip")
		ui.button(body,"Strip all remaining lots · %.1f space"%float(q.get("weight",0)),func():recover(ui,w.id,"strip"),true).disabled=not here or not q.ok
		q=c.Salvage.quote(c,w.id,"tow")
		ui.paragraph(body,q.message,14)
		ui.button(body,"Tow hull · %s coins + repairs"%ui.money(q.get("total",0)),func():recover(ui,w.id,"tow")).disabled=not here or not q.ok
	if count==0:ui.paragraph(body,"No unclaimed wrecks charted. Battles and surveyed salvage sites can reveal individual hulls and stores.",17)
	ui.rule(body)
	if not focus_id.is_empty():ui.button(body,"All marked wrecks",func():open(ui))
	ui.button(body,"Recovered drawings",func():blueprints(ui))

static func recover(ui,id: String,mode: String,good: String="",qty: float=0.0) -> void:
	ui.host.respond(ui.host.core.recover_wreck(id,mode,good,qty))
	ui.host.start_economy()
	ui.host.sync_economy()
	ui.host.save_game(false)
	open(ui)

static func blueprints(ui) -> void:
	ui.modal_kind="blueprints"
	var body=ui.modal("Recovered drawings","KNOWLEDGE UNLOCKS PAID CONSTRUCTION",900,700)
	var c=ui.host.core
	ui.paragraph(body,"License a recovered design at the shipyard you choose. It adds a construction option there; the yard still needs actual materials, workers, expert supervision and payment.",17)
	for id_value in c.state.get("blueprints",{}):
		var id: String=str(id_value)
		ui.label(body,str(c.hull(id).get("name",id)),25,ui.GOLD,true)
		ui.button(body,"License at this shipyard",func():ui.host.respond(c.license_blueprint(id));blueprints(ui),true).disabled=c.current_port().is_empty() or c.current_port().get("industry","")!="shipyard"
	if c.state.get("blueprints",{}).is_empty():ui.paragraph(body,"Survey abandoned workshops to look for original hull drawings.",16)
