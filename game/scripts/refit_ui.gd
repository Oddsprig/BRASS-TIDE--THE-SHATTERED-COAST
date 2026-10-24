extends RefCounted
const Refit = preload("res://scripts/refit.gd")
const Deployment = preload("res://scripts/deployment.gd")
const Portrait = preload("res://scripts/boat_portrait.gd")
const EquipmentPicker = preload("res://scripts/equipment_picker.gd")

static func module_name(id: String) -> String:
	if id.is_empty() or id == "empty":
		return "Empty mount"
	var catalog: Dictionary = Refit.catalog()
	for category in ["weapons","engines","armor"]:
		if catalog.get(category,{}).has(id):
			return str(catalog[category][id].get("name",id.capitalize()))
	return id.capitalize().replace("_"," ")

static func roster(ui, body: Node):
	ui.paragraph(body,"Fit weapons to compatible hardpoints, then choose your engine and armor. Every installation has a bill for materials and paid work. Your removed fittings stay with their boat.",15)
	for ship in ui.host.core.state.fleet:
		var uid: String = ship.uid
		var line = ui.row(body)
		var portrait = Portrait.new()
		portrait.boat = ship
		portrait.custom_minimum_size = Vector2(230,145)
		line.add_child(portrait)
		var details = ui.column(line)
		ui.label(details,ship.name,25,ui.TEXT,true)
		ui.label(details,"%d DP · %.0f speed · %.0f armor · %d sailors" % [Deployment.cost(ship),ship.spec.speed,ship.armor,ship.crew],14,ui.TEAL)
		var actions = ui.row(details)
		ui.button(actions,"Open fleet workshop ↗",func():ui.open_refit(uid),true)
		if ui.has_method("open_equipment"):
			ui.button(actions,"Equipment & condition",func():ui.open_equipment(uid))
		ui.rule(body)

static func preview(ui, body: Node, ship: Dictionary, select: Callable=Callable()):
	var portrait = Portrait.new()
	portrait.boat = ship
	portrait.custom_minimum_size = Vector2(390,245)
	portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait.show_sockets=true
	if select.is_valid():portrait.mount_selected.connect(select)
	body.add_child(portrait)
	ui.label(body,"%d DP · %.0f SPEED · %.0f ARMOR · %.0f HULL" % [Deployment.cost(ship),ship.spec.speed,ship.armor,ship.maxHp],16,ui.GOLD)

static func open(ui, uid: String):
	ui.host.sync_economy()
	EquipmentPicker.prune_requests(ui)
	var ship: Dictionary = ui.host.core.find_boat(uid)
	if ship.is_empty():
		return
	ui.modal_kind = "refit"
	var body = ui.modal(ship.name,"FITTING BAY · WEAPONS · ENGINE · ARMOR",1100,850)
	preview(ui,body,ship,func(index):choose(ui,uid,"weapon:%d"%index))
	var port: Dictionary = ui.host.core.current_port()
	var docked: bool = not port.is_empty()
	var canonical: bool = EquipmentPicker.is_canonical(ship)
	var show_uid: bool = EquipmentPicker.dev_enabled(ui)
	ui.paragraph(body,"Purse: %s coins · Fleet: %d / 300 deployment points" % [ui.money(ui.host.core.state.coins),ui.host.core.fleet_points()],16,ui.TEAL)
	var fittings: Dictionary = ship.loadout
	var budget: Dictionary = Refit.normalize(ship.baseSpec,fittings)
	ui.label(body,"Fitting points: %d / %d" % [budget.get("usedPoints",0),budget.get("maxPoints",0)],16,ui.GOLD)
	var slots: Array = Refit.hardpoints(ship.baseSpec)
	for i in range(slots.size()):
		var index: int = i
		var slot_key: String = "weapon:%d" % index
		var slot: Dictionary = slots[i]
		var module_id: String = str(fittings.weapons[i]) if i < fittings.weapons.size() else ""
		var line = ui.row(body)
		var text: String = "%d · %s · size %s\n%s" % [i+1,slot.get("label","Mount %d"%(i+1)),str(slot.get("size",1)),module_name(module_id)]
		if canonical:
			var inst: Dictionary = EquipmentPicker.installed_at(ship, slot_key)
			if not inst.is_empty():
				text += " (%s)" % EquipmentPicker.describe_part(inst, show_uid)
		ui.paragraph(line,text,16,ui.TEXT)
		ui.button(line,"Change weapon ↗",func():choose(ui,uid,slot_key)).disabled = not docked
	for pair in [["engine","Propulsion",str(fittings.engine)],["armor","Hull protection",str(fittings.armor)]]:
		var slot_id: String = pair[0]
		var line = ui.row(body)
		var pkg_text: String = "%s\n%s" % [pair[1],module_name(pair[2])]
		if canonical:
			var pkg_inst: Dictionary = EquipmentPicker.installed_at(ship, slot_id)
			if not pkg_inst.is_empty():
				pkg_text += " (%s)" % EquipmentPicker.describe_part(pkg_inst, show_uid)
		ui.paragraph(line,pkg_text,16,ui.TEXT)
		ui.button(line,"Change package ↗",func():choose(ui,uid,slot_id)).disabled = not docked
	ui.rule(body)
	ui.paragraph(body,"Fittings use the hull's available mounting space and fitting points. Faster engines increase fuel use; heavier armor slows the hull. Installing equipment never repairs existing damage.",14)
	if not docked:
		ui.paragraph(body,"Dock at a harbor to hire fitters and install equipment.",15,ui.GOLD)
	var actions = ui.row(body)
	ui.button(actions,"Back to fleet",ui.open_fleet)
	if ui.has_method("open_equipment"):
		ui.button(actions,"Equipment & condition",func():ui.open_equipment(uid))
	ui.button(actions,"Return to voyage",ui.close_modal,true)

static func choose(ui, uid: String, slot: String):
	ui.host.sync_economy()
	EquipmentPicker.prune_requests(ui)
	var ship: Dictionary = ui.host.core.find_boat(uid)
	var port: Dictionary = ui.host.core.current_port()
	if ship.is_empty() or port.is_empty():
		return
	var base: Dictionary = ui.host.core.hull(str(ship.get("type", "")))
	var canonical: bool = EquipmentPicker.is_canonical(ship)
	var show_uid: bool = EquipmentPicker.dev_enabled(ui)
	ui.modal_kind = "refit"
	var body = ui.modal("Choose a fitting","%s · %s" % [ship.name,slot.replace(":"," ").to_upper()],1050,850)
	if canonical:
		var current_part: Dictionary = EquipmentPicker.installed_at(ship, slot)
		ui.paragraph(body,"Currently installed: %s" % (EquipmentPicker.describe_part(current_part, show_uid) if not current_part.is_empty() else "Empty mount"),14,ui.TEAL)
	var category: String = "weapons" if slot.begins_with("weapon:") else "engines" if slot == "engine" else "armor"
	var options: Dictionary = Refit.catalog().get(category,{})
	for id_value in options:
		var id: String = str(id_value)
		var item: Dictionary = options[id]
		ui.label(body,module_name(id),23,ui.GOLD,true)
		ui.paragraph(body,str(item.get("description",item.get("kind",""))),15)
		if category == "weapons" and not id.is_empty():
			var weapon: Dictionary = ship.baseSpec if id == "stock_primary" else item
			ui.paragraph(body,"%s · %.1f shots/s · %.0f impact · range %.0f · %d fitting points" % [str(weapon.get("kind",weapon.get("weapon","gun"))).to_upper(),float(weapon.get("fireRate",1)),float(weapon.get("damage",0)),float(weapon.get("range",0)),int(item.get("op",0))],13,ui.TEAL)
		if not canonical or id.is_empty():
			var quote: Dictionary = EquipmentPicker.quote_single(port,ship,slot,id,{})
			var has_bill: bool = quote.has("newSpec")
			if not quote.get("ok",false): ui.paragraph(body,str(quote.get("message",quote.get("error","Unavailable for this mount"))),14,ui.MUTED)
			var b = ui.button(body,"Review bill · %s coins" % ui.money(quote.get("cost",0)) if has_bill else "Unavailable for this mount",func():review(ui,uid,slot,id,{}))
			b.disabled = not has_bill
		else:
			var new_req: Dictionary = {"new": true}
			var new_quote: Dictionary = EquipmentPicker.quote_single(port,ship,slot,id,new_req)
			var has_new: bool = new_quote.has("newSpec")
			if not new_quote.get("ok",false):
				ui.paragraph(body,str(new_quote.get("message",new_quote.get("error","Unavailable for this mount"))),14,ui.MUTED)
			var b_new = ui.button(body,"Review bill · Buy new (100%%) · %s coins" % ui.money(new_quote.get("cost",0)) if has_new else "Unavailable for this mount",func():review(ui,uid,slot,id,new_req))
			b_new.disabled = not has_new
			var spares: Array = EquipmentPicker.spare_choices(ship,base,slot,id,{})
			for s_idx in range(spares.size()):
				var spare: Dictionary = spares[s_idx]
				var spare_uid: String = str(spare.itemUid)
				var spare_req: Dictionary = {"itemUid": spare_uid}
				var spare_quote: Dictionary = EquipmentPicker.quote_single(port,ship,slot,id,spare_req)
				var has_spare: bool = bool(spare.compatible) and spare_quote.has("newSpec")
				ui.paragraph(body,"Owned spare #%d in locker: %s" % [s_idx+1,EquipmentPicker.describe_part(spare, show_uid)],14,ui.TEAL if has_spare else ui.MUTED)
				if not spare.compatible and not str(spare.reason).is_empty():
					ui.paragraph(body,str(spare.reason),13,ui.GOLD)
				elif not spare_quote.get("ok",false):
					ui.paragraph(body,str(spare_quote.get("message",spare_quote.get("error","Unavailable for this mount"))),13,ui.MUTED)
				var spare_label: String = "Install spare #%d (%s · %s) · %s coins" % [s_idx+1,EquipmentPicker.status_word(str(spare.status)),EquipmentPicker.percent_text(float(spare.hp)),ui.money(spare_quote.get("cost",0))] if has_spare else "Spare #%d unavailable" % (s_idx+1)
				var b_spare = ui.button(body,spare_label,func():review(ui,uid,slot,id,spare_req))
				b_spare.disabled = not has_spare
		ui.rule(body)
	ui.button(body,"Back to fitting bay",func():open(ui,uid))

static func review(ui, uid: String, slot: String, module_id: String, request: Dictionary = {}):
	ui.host.sync_economy()
	EquipmentPicker.prune_requests(ui)
	var ship: Dictionary = ui.host.core.find_boat(uid)
	var port: Dictionary = ui.host.core.current_port()
	if ship.is_empty() or port.is_empty():
		return
	var q: Dictionary = EquipmentPicker.quote_single(port,ship,slot,module_id,request)
	if not q.has("newSpec"):
		ui.toast(str(q.get("message",q.get("error","This fitting is unavailable."))),true)
		return
	ui.modal_kind = "refit"
	var body = ui.modal(module_name(module_id),"REVIEW THE YARD'S FITTING BILL",1050,850)
	var candidate: Dictionary = ship.duplicate(true)
	candidate.loadout = q.newLoadout.duplicate(true)
	Refit.ensure(candidate,ship.baseSpec)
	preview(ui,body,candidate)
	ui.label(body,"%s COINS TOTAL" % ui.money(q.cost),29,ui.GOLD,true)
	if q.get("selection") is Dictionary and not q.selection.is_empty():
		var src_kind: String = "removal" if module_id.is_empty() else ("yard" if bool(q.selection.get("newUnit",false)) else "locker")
		var sel_note: String = EquipmentPicker.change_selection_note(ui,{"source":src_kind,"selection":q.selection})
		if not sel_note.is_empty():
			ui.paragraph(body,sel_note,15,ui.TEAL)
	ui.paragraph(body,"Fitting points: %d / %d\nOrdinary fitting wages: %s coins\nSupervising experts: %s coins\nRegistry duty: %s coins\nYard materials, overhead & margin: %s coins" % [q.get("usedPoints",0),q.get("maxPoints",0),ui.money(q.get("workerWages",0)),ui.money(q.get("expertWages",0)),ui.money(q.get("tax",0)),ui.money(q.get("businessIncome",0))],16)
	var materials: Dictionary = q.get("materials",{})
	if materials.is_empty():
		ui.paragraph(body,"This fitting is already owned. The bill covers installation work.",14,ui.TEAL)
	else:
		ui.eyebrow(body,"PHYSICAL MATERIALS FROM THIS HARBOR")
		for key in materials:
			ui.label(body,"%.2f × %s" % [materials[key],str(key).capitalize()],14,ui.MUTED)
	ui.paragraph(body,"%.2f ordinary worker-days · %.2f expert-days\nExisting damage and working stores carry through the refit." % [q.get("workerDays",0),q.get("expertDays",0)],14)
	var future: int = ui.host.core.fleet_points()-Deployment.cost(ship)+Deployment.cost(q.newSpec)
	var reason: String = "" if q.get("ok",false) else str(q.message)
	if int(q.cost) > int(ui.host.core.state.coins): reason = "Your purse needs %s coins." % ui.money(q.cost)
	if future > 300 and future > ui.host.core.fleet_points(): reason = "This fitting would use %d / 300 fleet deployment points." % future
	if not reason.is_empty(): ui.paragraph(body,reason,15,ui.GOLD)
	ui.button(body,"Install · %s coins"%ui.money(q.cost),func():EquipmentPicker.apply_single_refit(ui,uid,slot,module_id,request),true).disabled = not reason.is_empty()
	ui.button(body,"Back to choices",func():choose(ui,uid,slot))
