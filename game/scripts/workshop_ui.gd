extends RefCounted
## Main-thread fitting workspace. Drafts live in Interface, never in campaign stock.
const Workshop=preload("res://scripts/fleet_workshop.gd")
const Refits=preload("res://scripts/refit.gd")
const RefitUI=preload("res://scripts/refit_ui.gd")
const Portrait=preload("res://scripts/boat_portrait.gd")
const Deployment=preload("res://scripts/deployment.gd")
const EquipmentPicker=preload("res://scripts/equipment_picker.gd")
const Comparison=preload("res://scripts/workshop_comparison048.gd")
const Builds=preload("res://scripts/workshop_builds048.gd")

static func _actions(parent: Node) -> HFlowContainer:
	var flow=HFlowContainer.new()
	flow.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(flow)
	return flow

static func _table(ui,parent: Node,rows: Array,node_name: String):
	var grid=GridContainer.new()
	grid.name=node_name;grid.columns=4
	grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",16)
	grid.add_theme_constant_override("v_separation",8)
	parent.add_child(grid)
	for title in ["FIT VALUE","CURRENT","DRAFT","CHANGE"]:
		ui.paragraph(grid,title,11,ui.GOLD)
	for entry in rows:
		for key in ["label","before","after","delta"]:
			var cell=ui.paragraph(grid,str(entry[key]),14,ui.GOLD if key=="delta" and entry.changed else ui.TEXT)
			if key=="label":cell.size_flags_stretch_ratio=1.6

static func _try_draft(ui,uid: String,draft: Dictionary):
	# Capture the LOCAL draft, including unapplied edits. Never pass installed fit instead.
	if ui.host.has_method("workshop_try_draft"):ui.host.workshop_try_draft(uid,draft.duplicate(true))

static func _draft_actions(ui,parent: Node,uid: String,draft: Dictionary,q: Dictionary):
	var actions=_actions(parent)
	ui.button(actions,"Review whole-fit quote · %s coins"%ui.money(q.cost),func():review(ui,uid,draft),true).disabled=not q.validDraft or q.changes.is_empty()
	var trial=ui.button(actions,"Try current draft in Lab",func():_try_draft(ui,uid,draft),false,false)
	trial.name="WorkshopTryDraft"
	trial.disabled=not q.validDraft or not ui.host.has_method("workshop_try_draft")
	trial.tooltip_text="Isolated practice with this draft; no campaign equipment, condition, coins or stores are transferred."
	ui.button(actions,"Reference fittings",func():examples(ui,uid,draft),false,false).name="WorkshopExamples"

static func _selected(ui,parent: Node,base: Dictionary,ship: Dictionary,draft: Dictionary,q: Dictionary,selected: int):
	var sockets: Array=Refits.hardpoints(base)
	if sockets.is_empty():return
	var socket: Dictionary=sockets[clampi(selected,0,sockets.size()-1)]
	ui.eyebrow(parent,"SELECTED SOCKET %d · %s · SIZE %d"%[selected+1,str(socket.label),int(socket.size)])
	ui.paragraph(parent,"Select this numbered position on either boat to change its weapon draft. The highlighted sector uses this socket's actual bearing and firing arc.",12)
	var weapons: Array=draft.get("weapons",[])
	var module_id: String=str(weapons[selected]) if selected<weapons.size() else ""
	ui.paragraph(parent,Comparison.compatibility(base,socket,module_id),13,ui.TEAL)
	if q.validDraft:
		_table(ui,parent,Comparison.mount_rows(q.beforeSpec,q.afterSpec,str(socket.id),float(ship.get("ammo",0))),"WorkshopMountComparison")
	else:ui.paragraph(parent,"Correct the draft before comparing firing values. "+str(q.message),13,ui.RED)

static func _prune_drafts(ui) -> Dictionary:
	return EquipmentPicker.prune_requests(ui)

static func _draft(ui,uid: String,provided: Dictionary={}) -> Dictionary:
	if not _prune_drafts(ui).has(uid):return {}
	EquipmentPicker.bind_boat(ui,uid)
	if not provided.is_empty():ui.workshop_drafts[uid]=provided.duplicate(true)
	if not ui.workshop_drafts.has(uid):
		var boat: Dictionary=ui.host.core.find_boat(uid)
		ui.workshop_drafts[uid]=boat.get("loadout",Refits.defaults(ui.host.core.hull(str(boat.get("type",""))))).duplicate(true)
		EquipmentPicker.bind_boat(ui,uid)
	EquipmentPicker.prune_requests(ui)
	return ui.workshop_drafts[uid].duplicate(true)

static func _portrait(ui,parent: Node,ship: Dictionary,spec: Dictionary,selected: int=0,action: Callable=Callable()):
	var view=Portrait.new()
	var candidate: Dictionary=ship.duplicate(true)
	candidate.spec=spec.duplicate(true)
	view.boat=candidate;view.show_sockets=true;view.show_arcs=true;view.selected_socket=selected
	view.custom_minimum_size=Vector2(290,220)
	view.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if action.is_valid():view.mount_selected.connect(action)
	parent.add_child(view)
	return view

static func _spec_text(spec: Dictionary,points: int,maximum: int) -> String:
	return "Fitting capacity  %d / %d\nBattle deployment  %d DP\nHold  %.0f space · Berths  %d\nCrew  %d minimum / %d working\nSpeed  %.1f · Turn  %.2f\nArmor  %.0f · Fuel use  %.2f×\nFull working crew pay  %d coins/day"%[points,maximum,Deployment.cost(spec),float(spec.get("cargo",0)),int(spec.get("crewMax",0)),int(spec.get("crewMin",0)),int(spec.get("crewOptimal",0)),float(spec.get("speed",0)),float(spec.get("turn",0)),float(spec.get("armor",0)),float(spec.get("fuelUse",1)),int(spec.get("crewOptimal",0))*100]

static func _arc_text(spec: Dictionary,socket: Dictionary) -> String:
	return Comparison.mount_summary(spec,socket)

static func _picker(ui,parent: Node,uid: String,draft: Dictionary):
	var row=ui.row(parent)
	ui.eyebrow(row,"OWNED BOAT")
	var choice=OptionButton.new()
	choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for ship in ui.host.core.state.fleet:
		if ship.get("sunk",false):continue
		choice.add_item(str(ship.name));choice.set_item_metadata(choice.item_count-1,str(ship.uid))
		if ship.uid==uid:choice.select(choice.item_count-1)
	choice.item_selected.connect(func(index):ui.host.sync_economy();open(ui,str(choice.get_item_metadata(index))))
	row.add_child(choice)
	ui.button(row,"Compare known hulls",func():compare(ui,uid,draft,str(ui.host.core.find_boat(uid).type)))
	ui.button(row,"Fitting templates",func():templates(ui,uid,draft))

static func open(ui,uid: String,draft: Dictionary={},selected: int=0):
	ui.host.sync_economy()
	_prune_drafts(ui)
	var ship: Dictionary=ui.host.core.find_boat(uid)
	if ship.is_empty() or ship.get("sunk",false):return
	draft=_draft(ui,uid,draft)
	var q: Dictionary=EquipmentPicker.preview_workshop(ui,uid,draft)
	var canonical: bool=EquipmentPicker.is_canonical(ship)
	ui.modal_kind="refit"
	var body=ui.modal(ship.name,"FITTING BAY · FLEET WORKSHOP · CURRENT FIT & DRAFT",1160,890)
	_picker(ui,body,uid,draft)
	var quote_status: String="Draft only · %d changed slots · %s coins quoted · %.2f ordinary + %.2f expert worker-days\nPurse covers bill: %s · Yard can apply now: %s"%[q.changes.size(),ui.money(q.cost),float(q.workerDays),float(q.expertDays),"yes" if q.affordable else "no","yes" if q.applicable else "no"]
	if not q.validDraft:quote_status="Invalid draft · correct its compatibility or fitting budget before a bill can be reviewed."
	ui.paragraph(body,quote_status,14,ui.TEAL if q.applicable else ui.GOLD).name="WorkshopQuoteStatus"
	if q.validDraft:ui.paragraph(body,Comparison.headline(q),14,ui.TEXT).name="WorkshopHeadline"
	_draft_actions(ui,body,uid,draft,q)
	if not q.get("reasons",[]).is_empty():ui.paragraph(body,str(q.reasons[0]),13,ui.GOLD)
	var columns=ui.row(body)
	var current=ui.column(columns)
	var planned=ui.column(columns)
	ui.eyebrow(current,"CURRENT FITTING")
	ui.eyebrow(planned,"DRAFT FITTING" if q.validDraft else "DRAFT NEEDS ADJUSTMENT")
	var base: Dictionary=ui.host.core.hull(str(ship.type))
	var before: Dictionary=Refits.normalize(base,ship.get("loadout",{}))
	var before_loadout: Dictionary=before.get("loadout",Refits.defaults(base))
	selected=clampi(selected,0,maxi(0,Refits.hardpoints(base).size()-1))
	var current_spec: Dictionary=q.beforeSpec if not q.beforeSpec.is_empty() else ship.spec
	var draft_spec: Dictionary=q.afterSpec if not q.afterSpec.is_empty() else current_spec
	var select=func(index):choose(ui,uid,draft,"weapon:%d"%index)
	_portrait(ui,current,ship,current_spec,selected,select)
	_portrait(ui,planned,ship,draft_spec,selected,select)
	ui.paragraph(current,"%s · %s"%[RefitUI.module_name(str(before_loadout.engine)),RefitUI.module_name(str(before_loadout.armor))],13)
	ui.paragraph(planned,"%s · %s"%[RefitUI.module_name(str(draft.engine)),RefitUI.module_name(str(draft.armor))],13)
	if not q.validDraft:ui.paragraph(planned,"Draft geometry is shown as the current fit until all modules fit. "+str(q.message),13,ui.RED)
	ui.paragraph(body,"The highlighted firing sector shows the selected mount's bearings. Its radius is schematic; range is listed below. Empty mounts do not fire.",12)
	_selected(ui,body,base,ship,draft,q,selected)
	ui.eyebrow(body,"BEFORE → DRAFT · HANDLING, STORES & COST OF SERVICE")
	_table(ui,body,Comparison.stat_rows(base,q),"WorkshopFitComparison")
	ui.paragraph(body,Comparison.basis(),12)
	ui.paragraph(body,Comparison.stores_text(ship),12)
	ui.paragraph(body,"Crew: %d minimum / %d working. Full working-crew pay: %d coins/day at 100 coins per sailor-day. Existing integral pumps and repair-kit stock are unchanged by a weapon, engine or armor draft."%[int(draft_spec.get("crewMin",0)),int(draft_spec.get("crewOptimal",0)),int(draft_spec.get("crewOptimal",0))*100],13)
	var sockets: Array=Refits.hardpoints(base)
	ui.eyebrow(body,"PHYSICAL SOCKETS")
	for i in range(sockets.size()):
		var index: int=i
		var slot_key: String="weapon:%d"%index
		var slot: Dictionary=sockets[i]
		var id: String=str(draft.get("weapons",[])[i]) if i<draft.get("weapons",[]).size() else ""
		var line=ui.row(body)
		var details=ui.column(line)
		ui.paragraph(details,"%d · %s · size %d · %s → %s"%[i+1,slot.label,slot.size,RefitUI.module_name(str(before_loadout.weapons[i])),RefitUI.module_name(id)],16,ui.GOLD)
		ui.paragraph(details,_arc_text(draft_spec,slot),12)
		if canonical:
			var sum_text: String=EquipmentPicker.slot_summary_text(ui,ship,draft,slot_key,q)
			if not sum_text.is_empty():ui.paragraph(details,sum_text,13,ui.TEAL)
		ui.button(line,"Change weapon draft %d"%(i+1),func():choose(ui,uid,draft,slot_key)).name="WorkshopSocket%d"%i
	for pair in [["engine","Propulsion"],["armor","Hull protection"]]:
		var slot: String=pair[0]
		var line=_actions(body)
		var details=ui.column(line)
		ui.paragraph(details,"%s · %s"%[pair[1],RefitUI.module_name(str(draft.get(slot,"")))],16,ui.TEXT)
		if canonical:
			var pkg_sum: String=EquipmentPicker.slot_summary_text(ui,ship,draft,slot,q)
			if not pkg_sum.is_empty():ui.paragraph(details,pkg_sum,13,ui.TEAL)
		ui.button(line,"Change package draft · "+slot,func():choose(ui,uid,draft,slot))
	ui.rule(body)
	ui.paragraph(body,"Purse: %s coins · Living owned fleet: %d DP · Battle deployment limit: 300 DP per side. Ownership is separate from battle deployment."%[ui.money(ui.host.core.state.coins),ui.host.core.fleet_points()],14,ui.TEAL)
	_reserve(ui,body,q)
	if not q.get("reasons",[]).is_empty():
		for reason in q.reasons:ui.paragraph(body,str(reason),13,ui.GOLD)
	ui.eyebrow(body,"AUTOMATIC WEAPON CONTROL & DAMAGE CONTROL")
	ui.paragraph(body,Comparison.control_limit(),13)
	var actions=_actions(body)
	ui.button(actions,"Reset draft to current",func():EquipmentPicker.clear_workshop_state(ui,uid);open(ui,uid))
	ui.button(actions,"Single-slot refit",func():ui.open_single_refit(uid))
	if ui.has_method("open_equipment"):
		ui.button(actions,"Equipment & condition",func():ui.open_equipment(uid))
	ui.button(body,"Back to fleet",ui.open_fleet)

static func draft_set(ui,uid: String,draft: Dictionary,slot: String,module_id: String,choice: Dictionary={}):
	if not _prune_drafts(ui).has(uid):return
	var next: Dictionary=draft.duplicate(true)
	var position: Dictionary=Refits._slot(next,slot)
	if not position.ok:ui.toast(str(position.message),true);return
	if position.index>=0:next.weapons[position.index]=module_id
	else:next[position.key]=module_id
	ui.workshop_drafts[uid]=next.duplicate(true)
	EquipmentPicker.set_workshop_slot_choice(ui,uid,slot,module_id,choice)
	open(ui,uid,next,maxi(0,int(position.index)))

static func choose(ui,uid: String,draft: Dictionary,slot: String):
	ui.host.sync_economy()
	draft=_draft(ui,uid,draft)
	var ship: Dictionary=ui.host.core.find_boat(uid)
	if ship.is_empty():return
	var base: Dictionary=ui.host.core.hull(str(ship.type))
	var position: Dictionary=Refits._slot(draft,slot)
	if not position.ok:ui.toast(str(position.message),true);return
	var selected: int=maxi(0,int(position.index))
	var q: Dictionary=EquipmentPicker.preview_workshop(ui,uid,draft)
	var canonical: bool=EquipmentPicker.is_canonical(ship)
	var show_uid: bool=EquipmentPicker.dev_enabled(ui)
	var slot_requests: Dictionary=EquipmentPicker.workshop_slot_map(ui,uid,draft)
	var current_slot_req: Dictionary=slot_requests.get(slot,{}) if slot_requests.get(slot,{}) is Dictionary else {}
	var installed_item: Dictionary=EquipmentPicker.installed_at(ship,slot)
	ui.modal_kind="refit"
	var slot_label: String="Propulsion" if slot=="engine" else "Hull protection"
	if position.index>=0:slot_label="Socket %d · %s"%[position.index+1,Refits.hardpoints(base)[position.index].label]
	var body=ui.modal("Draft a fitting","%s · %s"%[ship.name,slot_label],1100,850)
	_portrait(ui,body,ship,q.afterSpec if not q.afterSpec.is_empty() else ship.spec,selected,func(index):choose(ui,uid,draft,"weapon:%d"%index))
	if position.index>=0:
		_selected(ui,body,base,ship,draft,q,selected)
		ui.paragraph(body,Comparison.basis(),12)
	if canonical:
		ui.paragraph(body,EquipmentPicker.slot_summary_text(ui,ship,draft,slot,q),14,ui.TEAL)
	ui.paragraph(body,"This changes the draft only. The final bill pools removed modules and locker stock before buying any yard inputs. Installation always pays ordinary and expert workers.",14)
	var options: Dictionary=Refits.catalog()[position.group]
	for key in options:
		var id: String=str(key)
		var item: Dictionary=options[id]
		var compatible: bool=true
		if position.index>=0:
			compatible=int(item.size)<=int(Refits.hardpoints(base)[position.index].size) and (id!="stock_primary" or position.index==0)
		else:compatible=int(item.size)<=Refits._size(base)
		ui.label(body,RefitUI.module_name(id),22,ui.GOLD,true)
		ui.paragraph(body,str(item.get("description","")),14)
		if position.index>=0 and not id.is_empty():
			var weapon: Dictionary=Refits.weapon_for_socket(base,item,Refits.hardpoints(base)[0 if id=="stock_primary" else position.index],id=="stock_primary")
			ui.paragraph(body,"%.0f impact · %.2f shots/s · %.2f s base reload · range %.0f · %.0f° arc · %d fitting points"%[float(weapon.damage),float(weapon.fireRate),1.0/maxf(0.000001,float(weapon.fireRate)),float(weapon.range),rad_to_deg(float(weapon.arc)),int(item.op)],13,ui.TEAL)
		else:ui.paragraph(body,"%d fitting points"%int(item.op),13,ui.TEAL)
		var next: Dictionary=draft.duplicate(true)
		if position.index>=0:next.weapons[position.index]=id
		else:next[position.key]=id
		var fit: Dictionary=Refits.normalize(base,next)
		if compatible and not fit.ok:ui.paragraph(body,"Draft adjustment needed: "+str(fit.message),13,ui.GOLD)
		if not canonical or id.is_empty():
			var button=ui.button(body,"Already in draft" if str(position.old)==id else "Use in draft" if compatible else "Too large or incompatible with this socket",func():draft_set(ui,uid,draft,slot,id,{}))
			button.disabled=not compatible or str(position.old)==id
		else:
			var same_draft_mod: bool=(str(position.old)==id)
			var default_kept: bool=same_draft_mod and current_slot_req.is_empty()
			var b_default=ui.button(body,"Already in draft" if default_kept else "Use in draft" if compatible else "Too large or incompatible with this socket",func():draft_set(ui,uid,draft,slot,id,{}))
			b_default.disabled=not compatible or default_kept
			var new_selected: bool=same_draft_mod and bool(current_slot_req.get("new",false))
			var b_new=ui.button(body,"New yard unit in draft" if new_selected else ("Buy new in draft (100%)" if compatible else "Too large or incompatible with this socket"),func():draft_set(ui,uid,draft,slot,id,{"new":true}))
			b_new.disabled=not compatible or new_selected
			var spares: Array=EquipmentPicker.spare_choices(ship,base,slot,id,slot_requests,q)
			for s_idx in range(spares.size()):
				var spare: Dictionary=spares[s_idx]
				var spare_uid: String=str(spare.itemUid)
				var spare_selected: bool=same_draft_mod and str(current_slot_req.get("itemUid",""))==spare_uid
				ui.paragraph(body,"Owned spare #%d in locker: %s"%[s_idx+1,EquipmentPicker.describe_part(spare,show_uid)],13,ui.TEAL if spare.compatible else ui.MUTED)
				if not spare.compatible and not str(spare.reason).is_empty():
					ui.paragraph(body,str(spare.reason),12,ui.GOLD)
				var spare_label: String="Spare #%d selected in draft"%(s_idx+1) if spare_selected else ("Draft spare #%d (%s · %s)"%[s_idx+1,EquipmentPicker.status_word(str(spare.status)),EquipmentPicker.percent_text(float(spare.hp))] if spare.compatible else "Spare #%d unavailable"%(s_idx+1))
				var b_spare=ui.button(body,spare_label,func():draft_set(ui,uid,draft,slot,id,{"itemUid":spare_uid}))
				b_spare.disabled=not compatible or not bool(spare.compatible) or spare_selected
		ui.rule(body)
	ui.button(body,"Back to whole fitting",func():open(ui,uid,draft,selected))

static func _reserve(ui,parent: Node,q: Dictionary):
	if q.get("reserve",{}).is_empty():return
	var reserve: Dictionary=q.reserve
	var after: Dictionary=reserve.after
	ui.eyebrow(parent,"DAILY & RETURN OBLIGATIONS")
	ui.paragraph(parent,"Current fleet payroll: %s coins/day · After fitting: %s coins/day\nPurse after bill: %s coins · Existing wage arrears: %s · Debt: %s\nTwo-day payroll reserve: %s coins · Shortfall after bill and arrears: %s\nTraveling hold: %.1f / %.1f used · %.1f free · %.1f overloaded\nWorking fuel: %.1f days minimum · Food: %.1f days"%[ui.money(reserve.before.dailyWages),ui.money(after.dailyWages),ui.money(reserve.afterCoins),ui.money(reserve.arrears),ui.money(reserve.debt),ui.money(reserve.returnWages),ui.money(reserve.shortfall),float(after.cargoWeight),float(after.usableCapacity),float(after.freeCapacity),float(after.overload),float(after.fuelDays),float(after.foodDays)],14,ui.GOLD if int(reserve.shortfall)>0 else ui.TEAL)
	ui.paragraph(parent,str(reserve.basis)+" The bill buys no fuel, food, ammunition or crew.",12)
	for warning in after.warnings:ui.paragraph(parent,str(warning),12,ui.GOLD)

static func review(ui,uid: String,draft: Dictionary):
	ui.host.sync_economy()
	draft=_draft(ui,uid,draft)
	var ship: Dictionary=ui.host.core.find_boat(uid)
	if ship.is_empty():return
	var q: Dictionary=EquipmentPicker.preview_workshop(ui,uid,draft)
	ui.modal_kind="refit"
	var body=ui.modal("Review the complete fitting","EXACT PREVIEW · STOCK · WORKERS · COINS",1120,880)
	if not q.afterSpec.is_empty():_portrait(ui,body,ship,q.afterSpec)
	ui.label(body,"%s COINS TOTAL"%ui.money(q.cost),29,ui.GOLD,true)
	ui.paragraph(body,"Draft: %s · Purse covers bill: %s · Yard can apply now: %s"%["valid" if q.validDraft else "invalid","yes" if q.affordable else "no","yes" if q.applicable else "no"],15,ui.TEAL if q.applicable else ui.GOLD)
	for change in q.changes:
		ui.label(body,str(change.label),17,ui.GOLD)
		ui.paragraph(body,"%s → %s\nSource: %s · %s coins · %.2f ordinary + %.2f expert days"%[RefitUI.module_name(str(change.oldModule)),RefitUI.module_name(str(change.moduleId)),{"yard":"physical yard materials","locker":"boat locker","moved":"removed module reused in this fit","removal":"returned to boat locker"}.get(change.source,change.source),ui.money(change.bill.cost),float(change.bill.workerDays),float(change.bill.expertDays)],14)
		var sel_note: String=EquipmentPicker.change_selection_note(ui,change)
		if not sel_note.is_empty():
			ui.paragraph(body,sel_note,13,ui.TEAL)
	ui.rule(body)
	ui.paragraph(body,"Physical materials: %s coins\nOrdinary fitter wages: %s coins\nExpert wages: %s coins\nYard overhead & margin: %s coins\nRegistry duty: %s coins\nTotal ordinary worker-days: %.2f · Expert-days: %.2f"%[ui.money(q.materialCost),ui.money(q.workerWages),ui.money(q.expertWages),ui.money(q.margin),ui.money(q.tax),float(q.workerDays),float(q.expertDays)],16,ui.TEXT)
	if q.materials.is_empty():ui.paragraph(body,"No new materials: this draft uses already owned modules or removals. Fitting labor is still paid.",14,ui.TEAL)
	for good in q.materials:
		ui.paragraph(body,"%.2f × %s at %s coins/unit · %.2f available"%[float(q.materials[good]),str(good).capitalize(),ui.money(q.materialPrices[good]),maxf(0,float(q.get("materialAvailability",{}).get(good,0)))],14)
	ui.eyebrow(body,"BOAT LOCKER AFTER THE FIT")
	if q.lockerAfter.is_empty():ui.paragraph(body,"No spare modules remain.",13)
	for id in q.lockerAfter:ui.paragraph(body,"%d × %s"%[q.lockerAfter[id],RefitUI.module_name(str(id))],14)
	ui.paragraph(body,"Refits retain existing damage, crew and stores. Hull damage, engine damage, wounds, breaches and fire still need care after fitting.",13)
	_reserve(ui,body,q)
	for reason in q.reasons:ui.paragraph(body,str(reason),14,ui.GOLD)
	ui.paragraph(body,"The apply button authorizes this complete bill once. If the hull, stock, workforce, permission or purse changes, the yard requires a fresh review.",13)
	ui.button(body,"Apply reviewed fitting · %s coins"%ui.money(q.cost),func():EquipmentPicker.apply_workshop(ui,uid,draft,q),true).disabled=not q.applicable or q.changes.is_empty()
	ui.button(body,"Back to draft",func():open(ui,uid,draft))

static func examples(ui,uid: String,draft: Dictionary,hull_id: String=""):
	draft=_draft(ui,uid,draft)
	var ship: Dictionary=ui.host.core.find_boat(uid)
	if ship.is_empty():return
	if hull_id not in Builds.HULL_IDS:
		hull_id=str(ship.type) if str(ship.type) in Builds.HULL_IDS else Builds.HULL_ID
	var base: Dictionary=ui.host.core.hull(hull_id)
	if base.is_empty():return
	var library: Array=Builds.examples(base)
	ui.modal_kind="refit"
	var body=ui.modal("Reference fittings","KNOWN FITS · "+str(base.get("name",hull_id)).to_upper(),1100,850)
	ui.eyebrow(body,"REFERENCE HULL")
	var choice=OptionButton.new()
	choice.name="WorkshopReferenceHull";choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for reference_id in Builds.HULL_IDS:
		var reference: Dictionary=ui.host.core.hull(str(reference_id))
		choice.add_item(str(reference.name));choice.set_item_metadata(choice.item_count-1,str(reference_id))
		if str(reference_id)==hull_id:choice.select(choice.item_count-1)
	choice.item_selected.connect(func(index):examples(ui,uid,draft,str(choice.get_item_metadata(index))))
	body.add_child(choice)
	ui.paragraph(body,"Compare fittings on the same hull. Each trades fuel use, handling, reach, protection or shared ammunition. Loading one changes only the draft; the yard still needs actual parts, stock, labor and coins.",14)
	for entry in library:
		var example: Dictionary=entry
		ui.label(body,str(example.name),23,ui.GOLD,true)
		ui.paragraph(body,str(example.summary)+"\nTradeoff: "+str(example.tradeoff),14)
		ui.paragraph(body,"Suggested role: %s. Choosing a fitting does not issue a role or fire order; set those in the battle's selected tactics."%str(example.role),12)
		if str(ship.type)==str(base.id):
			var quote: Dictionary=EquipmentPicker.preview_workshop(ui,uid,example.loadout,{})
			ui.paragraph(body,"This boat's whole-fit quote: %s coins · %.2f ordinary + %.2f expert days · yard ready: %s"%[ui.money(quote.cost),float(quote.workerDays),float(quote.expertDays),"yes" if quote.applicable else "no"],13,ui.TEAL if quote.applicable else ui.GOLD)
			if not quote.reasons.is_empty():ui.paragraph(body,str(quote.reasons[0]),12,ui.GOLD)
		var actions=_actions(body)
		ui.button(actions,"Compare known build",func():compare(ui,uid,draft,str(base.id),example.loadout),false,false)
		var load_button=ui.button(actions,"Load example into owned draft",func():EquipmentPicker.clear_workshop_state(ui,uid);open(ui,uid,example.loadout),false,false)
		load_button.name="WorkshopExample_"+str(example.id)
		load_button.disabled=str(ship.type)!=str(base.id)
		if load_button.disabled:load_button.tooltip_text="This template fits "+str(base.name)+". Compare it without buying a hull; load only onto a hull you own of this design."
		ui.rule(body)
	ui.paragraph(body,"To try a build, load it into the owned draft and use Try current draft in Lab. The Lab creates isolated practice equipment and finite practice stores; your paid fleet stays in its career.",13)
	ui.button(body,"Back to owned draft",func():open(ui,uid,draft),false,false)

static func templates(ui,uid: String,draft: Dictionary):
	ui.host.sync_economy()
	draft=_draft(ui,uid,draft)
	var ship: Dictionary=ui.host.core.find_boat(uid)
	if ship.is_empty():return
	ui.modal_kind="refit"
	var body=ui.modal("Named fitting templates","KNOWLEDGE ONLY · AT MOST 24 TEMPLATES",1060,820)
	ui.paragraph(body,"A template remembers a fitting for its hull design. Loading one only changes this draft. Applying it still consumes actual owned modules or yard inputs and pays the full installation bill.",15)
	var name_box=LineEdit.new()
	name_box.max_length=48;name_box.placeholder_text="Name this fitting (1–48 characters)"
	name_box.custom_minimum_size.y=42
	body.add_child(name_box)
	ui.button(body,"Save draft template",func():
		var result: Dictionary=ui.host.workshop_save_template(uid,name_box.text,draft)
		if result.ok:templates(ui,uid,draft))
	var library: Array=Workshop.template_list(ui.host.core.state,str(ship.type))
	ui.paragraph(body,"%d / 24 library entries · %d for this hull"%[Workshop.template_list(ui.host.core.state).size(),library.size()],14,ui.TEAL)
	for entry in library:
		var saved: Dictionary=entry
		ui.label(body,str(saved.name),23,ui.GOLD,true)
		var row=ui.row(body)
		ui.button(row,"Load into draft",func():EquipmentPicker.clear_workshop_state(ui,uid);open(ui,uid,saved.loadout))
		ui.button(row,"Forget template",func():
			var result: Dictionary=ui.host.workshop_delete_template(str(saved.id))
			if result.ok:templates(ui,uid,draft))
		ui.rule(body)
	ui.button(body,"Browse all hulls & templates",func():compare(ui,uid,draft,str(ship.type)))
	ui.button(body,"Back to draft",func():open(ui,uid,draft))

static func compare(ui,uid: String,draft: Dictionary,hull_id: String,known_fit: Dictionary={}):
	ui.host.sync_economy()
	draft=_draft(ui,uid,draft)
	var ship: Dictionary=ui.host.core.find_boat(uid)
	var base: Dictionary=ui.host.core.hull(hull_id)
	if ship.is_empty() or base.is_empty():return
	var q: Dictionary=EquipmentPicker.preview_workshop(ui,uid,draft)
	var normalized: Dictionary=Refits.normalize(base,known_fit)
	if not normalized.ok:return
	var spec: Dictionary=Refits.effective_spec(base,normalized.loadout)
	ui.modal_kind="refit"
	var body=ui.modal("Compare hulls and fits","KNOWN DESIGNS · OWNERSHIP IS UNCHANGED",1160,850)
	var choice=OptionButton.new()
	choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for hull in ui.host.data.HULLS:
		choice.add_item(str(hull.name));choice.set_item_metadata(choice.item_count-1,str(hull.id))
		if hull.id==hull_id:choice.select(choice.item_count-1)
	choice.item_selected.connect(func(index):compare(ui,uid,draft,str(choice.get_item_metadata(index))))
	body.add_child(choice)
	var columns=ui.row(body)
	var own=ui.column(columns)
	var other=ui.column(columns)
	ui.eyebrow(own,"YOUR DRAFT · "+str(ship.name))
	ui.eyebrow(other,str(base.name)+" · KNOWN FIT")
	var own_spec: Dictionary=q.afterSpec if not q.afterSpec.is_empty() else ship.spec
	_portrait(ui,own,ship,own_spec)
	_portrait(ui,other,ship,spec)
	ui.paragraph(own,_spec_text(own_spec,int(q.usedPoints),int(q.maxPoints)),14,ui.TEAL)
	ui.paragraph(other,_spec_text(spec,int(normalized.usedPoints),int(normalized.maxPoints)),14)
	for pair in [[own,own_spec],[other,spec]]:
		for socket in Refits.hardpoints(pair[1]):
			var weapon: Dictionary=Comparison.mount(pair[1],str(socket.id))
			if weapon.is_empty():continue
			ui.paragraph(pair[0],str(socket.label)+" · "+RefitUI.module_name(str(weapon.moduleId))+"\n"+Comparison.mount_summary(pair[1],socket),13)
	ui.paragraph(body,"Known designs show design performance and optimal-crew payroll. Your draft includes its existing support conversion, specialists and morale. Buying no hull is required to use the workshop.",13)
	ui.paragraph(body,Comparison.basis(),12)
	ui.button(body,"Compare original design fit",func():compare(ui,uid,draft,hull_id))
	for entry in Workshop.template_list(ui.host.core.state,hull_id):
		var saved: Dictionary=entry
		ui.button(body,"Compare template · "+str(saved.name),func():compare(ui,uid,draft,hull_id,saved.loadout))
	ui.button(body,"Back to owned draft",func():open(ui,uid,draft))
