extends RefCounted
## Persistent wrecks and finite selectable material lots.
const Flow=preload("res://scripts/recovery_flow.gd")
const EquipmentRecovery=preload("res://scripts/equipment_recovery.gd")

static func open(ui,focus_id: String="",encounter_ids: Array=[]) -> void:
	if ui.host.mode!="campaign":return
	ui.host.sync_economy()
	ui.modal_kind="recovery"
	var body=ui.modal("Wrecks & recovery","SALVAGE · TOWS · MARKED CARGO",1020,800)
	var c=ui.host.core
	ui.paragraph(body,"Tow a damaged hull, strip finite material into your hold, or abandon recovery for now and leave the wreck marked. Stripping structural parts permanently rules out towing that hull. Taking only loose stores leaves its equipment aboard. Recovery work advances time; wages and provisions continue.",15)
	ui.label(body,"Traveling hold %.1f / %.1f"%[c.cargo_weight(),c.capacity()],22,ui.GOLD,true)
	if not encounter_ids.is_empty():ui.paragraph(body,"Wrecks from this engagement. Escaped boats keep their goods and are not recovery prizes.",15,ui.TEAL)
	ui.button(body,"Abandon for now — leave wrecks marked",func():leave(ui))
	ui.paragraph(body,"Leaving this board takes no cargo, pays no coins and does no recovery work. You may return to any unclaimed wreck later.",14)
	var prizes: Array=captured_prizes(c)
	if not prizes.is_empty():
		ui.rule(body)
		ui.label(body,"Captured prize cargo",24,ui.GOLD,true)
		ui.paragraph(body,"These goods remain aboard your actual captured boats. Transfer only what your traveling holds can carry; any remainder stays on the prize. Moving cargo does not repair its hull or equipment.",15)
	for prize in prizes:
		var uid: String=str(prize.uid)
		ui.label(body,str(prize.get("name",prize.get("spec",{}).get("name","Captured boat"))),20,ui.TEAL)
		for key in prize.convoyCargo:
			var good: String=str(key)
			var qty: float=float(prize.convoyCargo[good])
			if qty<=0 or not c.Goods.ITEMS.has(good):continue
			var line=ui.row(body)
			ui.label(line,"%s · %.2f aboard prize"%[c.Goods.ITEMS[good].name,qty],15).size_flags_horizontal=Control.SIZE_EXPAND_FILL
			var fits: float=minf(qty,maxf(0,c.capacity()-c.cargo_weight())/float(c.Goods.ITEMS[good].weight))
			ui.button(line,"Take 1",func():take_cargo(ui,uid,good,minf(1,qty),focus_id,encounter_ids)).disabled=fits+0.000001<minf(1,qty)
			ui.button(line,"Take what fits",func():take_cargo(ui,uid,good,fits,focus_id,encounter_ids)).disabled=fits<=0
	var count: int=0
	for raw in c.state.get("wrecks",[]):
		if raw.status!="unclaimed":continue
		if not focus_id.is_empty() and raw.id!=focus_id:continue
		if not encounter_ids.is_empty() and not str(raw.id) in encounter_ids:continue
		var w: Dictionary=raw.duplicate(true)
		count+=1
		ui.rule(body)
		ui.label(body,w.name,24,ui.GOLD,true)
		ui.paragraph(body,"%s · %.0f water units away · recorded day%.1f"%["Friendly loss" if w.get("friendly",false) else "Marked find",c.distance(c.state.position,w),float(w.get("day",0))],14,ui.TEAL)
		var here: bool=c.distance(c.state.position,w)<=180
		var idle: bool=c.state.path.is_empty() and c.state.exploration.assignment.is_empty()
		var hazard: Dictionary=c.fleet_owner(str(c.state.get("wreckHazards",{}).get(w.sourceId,"")))
		var controlled: bool=hazard.is_empty() or not hazard.active or not hazard.boats.any(func(b):return not b.sunk)
		if not controlled:ui.paragraph(body,"Hostiles still control these waters. The wreck stays marked; secure the field before recovering it.",15,ui.RED)
		if here and not c.state.path.is_empty():ui.button(body,"Idle engines for recovery",func():c.stop_sailing();open(ui,w.id,encounter_ids))
		if not c.state.exploration.assignment.is_empty():ui.paragraph(body,"Recall the shore party before starting recovery work.",14,ui.RED)
		ui.button(body,"Chart the wreck location",func():ui.host.respond(c.chart_course(w));ui.close_modal()).disabled=not c.state.exploration.assignment.is_empty()
		var ready: bool=here and idle and controlled
		var strip_ready: bool=ready and c.Exploration.spare_crew(c.state)>=1
		if ready and not strip_ready:ui.paragraph(body,"Stripping needs one spare able sailor above the boat minimums.",14,ui.RED)
		if w.has("sourceModuleCondition") and w.sourceModuleCondition is Dictionary:
			var parts: Array=[]
			for item in w.sourceModuleCondition.get("items",{}).values():
				parts.append("%s %.0f%%"%[str(item.get("typeId","Part")).replace("_"," "),float(item.get("hp",0))*100])
			ui.paragraph(body,"Recorded equipment: "+", ".join(parts)+". A tow preserves this condition; it does not repair modules.",14,ui.GOLD)
		var items: Dictionary=c.Salvage._strip_items(w)
		for key in items:
			var good: String=str(key)
			var qty: float=float(items[good])
			var line=ui.row(body)
			ui.label(line,"%s · %.2f"%[c.Goods.ITEMS[good].name,qty],15).size_flags_horizontal=Control.SIZE_EXPAND_FILL
			if not EquipmentRecovery.is_store_good(good) and float(w.components.get(good,0))>0:
				ui.paragraph(body,"%s: first %.2f is loose cargo; taking more strips structural material and forfeits the tow."%[c.Goods.ITEMS[good].name,float(w.stores.get(good,0))],13,ui.RED)
			ui.button(line,"Recover 1",func():recover(ui,w.id,"strip",good,minf(1,qty),encounter_ids)).disabled=not strip_ready
			var fits: float=minf(qty,maxf(0,c.capacity()-c.cargo_weight())/float(c.Goods.ITEMS[good].weight))
			ui.button(line,"Take what fits",func():recover(ui,w.id,"strip",good,fits,encounter_ids)).disabled=not strip_ready or fits<=0
		var q: Dictionary=c.Salvage.quote(c,w.id,"strip")
		ui.paragraph(body,str(q.message),14)
		ui.button(body,"Strip all · %.1f space · hull permanently forfeited"%float(q.get("weight",0)),func():recover(ui,w.id,"strip","",0,encounter_ids)).disabled=not strip_ready or not q.ok
		q=c.Salvage.quote(c,w.id,"tow")
		ui.paragraph(body,q.message,14)
		ui.paragraph(body,"A tow pays tug labor and inspection. The hull returns damaged, uncrewed and empty; loose lots remaining aboard are forfeited. Take any wanted stores first. Paid harbor repair, crew and fresh working stores are still needed.",14)
		ui.button(body,"Tow hull · %s coins + later repairs"%ui.money(q.get("total",0)),func():recover(ui,w.id,"tow","",0,encounter_ids),true).disabled=not ready or not q.ok
	if count==0:ui.paragraph(body,"No unclaimed wrecks charted. Battles and surveyed salvage sites can reveal individual hulls and stores.",17)
	ui.rule(body)
	if not focus_id.is_empty() or not encounter_ids.is_empty():ui.button(body,"All marked wrecks",func():open(ui))
	ui.button(body,"Recovered drawings",func():blueprints(ui))

static func captured_prizes(c) -> Array:
	var prizes: Array=[]
	for boat in c.state.get("fleet",[])+c.state.get("boardingPrizes",[]):
		if boat.get("sunk",false):continue
		for good in boat.get("convoyCargo",{}):
			if c.Goods.ITEMS.has(good) and float(boat.convoyCargo[good])>0:
				prizes.append(boat)
				break
	return prizes

static func take_cargo(ui,uid: String,good: String,qty: float,focus_id: String="",encounter_ids: Array=[]) -> void:
	ui.host.take_prize_cargo(uid,good,qty)
	open(ui,focus_id,encounter_ids)

static func leave(ui) -> void:
	ui.close_modal()

static func recover(ui,id: String,mode: String,good: String="",qty: float=0.0,encounter_ids: Array=[]) -> void:
	ui.host.recover_wreck(id,mode,good,qty)
	open(ui,"",encounter_ids)

static func outcome(ui,result: String,report: Dictionary) -> void:
	ui.modal_kind="outcome"
	var escort: bool=ui.host.battle.get("mission",{}).get("kind","")=="escort"
	var title: String="Convoy passage secured" if escort and result=="won" else "Convoy stopped" if result=="won" else "Convoy engagement ended"
	if report.get("convoy",{}).get("partial",false):title="Partial convoy outcome"
	var body=ui.modal(title,"CONVOY · VOYAGE OUTCOME",860,740)
	ui.paragraph(body,Flow.objective_label(ui.host.battle),18,ui.GOLD)
	ui.paragraph(body,"Boats that crossed the exit remain on their voyage with their goods. Crossing the battle exit is not delivery to a harbor. Captured survivors keep their actual custody and equipment; damaged prizes still need paid harbor service.",16)
	var convoy: Dictionary=report.get("convoy",{})
	if not convoy.is_empty():
		ui.paragraph(body,"%d escaped · %d sunk · %d captured"%[int(convoy.get("escaped",0)),int(convoy.get("sunk",0)),int(convoy.get("captured",0))],18,ui.TEAL)
		for carrier in convoy.get("carriers",[]):
			var lots: Array=[]
			for good in carrier.get("cargoAboard",{}):
				lots.append("%.2f %s"%[float(carrier.cargoAboard[good]),str(ui.host.core.Goods.ITEMS.get(good,{"name":good}).name)])
			ui.paragraph(body,"%s · %s · manifest before losses: %s"%[str(carrier.get("name","Carrier")),str(carrier.get("fate","afloat")),", ".join(lots) if not lots.is_empty() else "none"],15,ui.TEAL)
		ui.paragraph(body,"A lost carrier leaves only its surviving wreck lots. The recovery board shows the amounts actually available.",14)
	ui.label(body,"%s coins transferred"%ui.money(report.get("coins",0)),25,ui.GOLD,true)
	var ids: Array=Flow.wreck_ids(report)
	if not ids.is_empty():
		ui.paragraph(body,"%d wrecks marked at this encounter. Tow preserves recorded module condition; stripping takes finite material and gives up the hull. Leave wrecks marked if you want to return later."%ids.size(),16)
		ui.button(body,"Return and choose recovery · %d marked wrecks"%ids.size(),ui.host.open_battle_recovery,true).disabled=ui.host.core.active_fleet().is_empty()
	var prizes: Array=captured_prizes(ui.host.core)
	if not prizes.is_empty():
		ui.button(body,"Review captured cargo",ui.host.open_battle_recovery,ids.is_empty()).disabled=ui.host.core.active_fleet().is_empty()
	if report.get("fleetLost",false):
		ui.paragraph(body,"No crewed fleet remains. Harbor rescue uses an actual treasury loan. Marked wrecks remain for a later return.",16,ui.RED)
		ui.button(body,"Accept harbor rescue",ui.host.accept_rescue,true)
	else:
		ui.button(body,"Return to coast — leave wrecks marked",ui.host.return_to_campaign,ids.is_empty() and prizes.is_empty())

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
