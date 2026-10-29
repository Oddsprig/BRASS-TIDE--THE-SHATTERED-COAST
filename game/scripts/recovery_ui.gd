extends RefCounted
## Finite recovery choices; every action stays in Main/RecoveryFlow/Campaign.
const Flow=preload("res://scripts/recovery_flow.gd")
const Decisions=preload("res://scripts/recovery_decisions.gd")
const EquipmentRecovery=preload("res://scripts/equipment_recovery.gd")

static func _is_local_or_home067(c) -> bool:
	if c.home_local064():return true
	var v: Dictionary=c.world_view064() if c is Object and c.has_method("world_view064") else {}
	return str(v.get("layer",""))=="local"

static func _wreck_in_current_region067(c,w: Dictionary) -> bool:
	if c.home_local064():
		return c.Expedition.home_local064(w)
	var v: Dictionary=c.world_view064() if c is Object and c.has_method("world_view064") else {}
	var active_reg: String=str(v.get("regionId","glasswind_keys"))
	var ww: Dictionary=w.get("world064",{}) if w.get("world064") is Dictionary else {}
	return str(ww.get("layer",""))=="local" and str(ww.get("regionId",""))==active_reg

static func _is_cargo_only067(c,w: Dictionary) -> bool:
	return not c.home_local064() or bool(w.get("cargoOnly",false)) or str(w.get("sourceId",""))=="site:glasswind_keys:abandoned_cache067"

static func _board(ui,title: String,subtitle: String,width: float=1020,height: float=800):
	# Interface captures its close-button sync policy while constructing a modal.
	# Reuse its existing read-only voyage-review policy, then expose recovery's
	# public identity. Even the header X must not settle unrelated pending wages.
	ui.modal_kind="voyage_review"
	var body=ui.modal(title,subtitle,width,height)
	ui.modal_kind="recovery"
	return body

static func open(ui,focus_id: String="",encounter_ids: Array=[]) -> void:
	if ui.host.mode!="campaign":return
	var c=ui.host.core
	if not _is_local_or_home067(c):ui.open_ocean064();return
	var is_home: bool=c.home_local064()
	var body=_board(ui,"Wrecks & recovery" if is_home else "Expedition salvage & cache recovery","KEEP A HULL · TAKE STORES · RECOVER REAL PARTS" if is_home else "FINITE SURVIVING STORES · PAID CREW WORK · HOLD CAPACITY")
	ui.paragraph(body,"Keep a damaged hull with a paid tow, take finite stores, or dismantle it for explicitly selected parts. Work takes crew time; normal wages and food continue." if is_home else "Recover finite surviving cargo lots from the surveyed wreck site. Remote recovery requires real spare hands, 1 repair kit per working day, and funded payroll and provisions.",16)
	ui.label(body,"Traveling hold %.1f / %.1f"%[c.cargo_weight(),c.capacity()],22,ui.GOLD,true)
	var top_row=ui.row(body)
	ui.button(top_row,"Leave wrecks marked · return to chart",func():leave(ui),false,false)
	if not is_home:
		ui.button(top_row,"Glasswind Keys surveys",func():ui.CampaignUI.islands(ui),false,false)
		ui.button(top_row,"Plan return voyage to Shatter Coast",func():ui.open_voyage_preparation065("shatter_coast"),false,false)
	ui.paragraph(body,"Closing takes nothing and does no recovery work. Captured boats are already yours and remain in your roster.",14)
	var prizes: Array=captured_prizes(c) if is_home else []
	if not prizes.is_empty():
		ui.rule(body)
		ui.label(body,"Already-owned prizes",23,ui.GOLD,true)
	for boat in prizes:
		var uid: String=str(boat.uid)
		var row=ui.row(body)
		ui.paragraph(row,"%s · %s"%[str(boat.get("name","Captured boat")),_boat_summary(boat)],15,ui.TEAL)
		ui.button(row,"Inspect prize",func():owned_prize(ui,uid,focus_id,encounter_ids),false,false)
	var wrecks: Array=[]
	var focused: Dictionary={}
	for raw in c.state.get("wrecks",[]):
		if not (raw is Dictionary) or not _wreck_in_current_region067(c,raw) or str(raw.get("status",""))!="unclaimed":continue
		if not encounter_ids.is_empty() and str(raw.get("id","")) not in encounter_ids:continue
		wrecks.append(raw)
		if str(raw.get("id",""))==focus_id:focused=raw
	if focused.is_empty() and focus_id.is_empty():
		for w in wrecks:
			if c.distance(c.state.position,w)<=180:focused=w;break
		if focused.is_empty() and not is_home and wrecks.size()==1:
			focused=wrecks[0]
	if not encounter_ids.is_empty():ui.paragraph(body,"Only this encounter's wrecks are listed. Escaped boats keep their cargo.",14,ui.TEAL)
	# Only this single focused wreck can stage custody, route or service quotes.
	if not focused.is_empty():_focused(ui,body,focused,encounter_ids)
	ui.rule(body)
	ui.label(body,"Marked wrecks · %d"%wrecks.size(),23,ui.GOLD,true)
	for w in wrecks:
		var id: String=str(w.id)
		var row=ui.row(body)
		var status_lbl: String="cargo-only supply cache" if _is_cargo_only067(c,w) else ("hull forfeited; finite lots remain" if w.get("hullStripped",false) else "unclaimed")
		ui.paragraph(row,"%s · %.0f water units · %s"%[str(w.get("name","Wreck")),c.distance(c.state.position,w),status_lbl],15)
		ui.button(row,"Inspected" if id==str(focused.get("id","")) else "Inspect",func():open(ui,id,encounter_ids),false,false)
	if wrecks.is_empty():ui.paragraph(body,"No unclaimed wrecks in this view. Battles and surveyed salvage sites can reveal individual hulls and stores.",16)
	if not focus_id.is_empty() or not encounter_ids.is_empty():ui.button(body,"All marked wrecks",func():open(ui),false,false)
	if is_home:
		ui.button(body,"Recovered drawings",func():blueprints(ui),false,false)

static func _boat_summary(boat: Dictionary) -> String:
	var role: String="support / reserve boat" if boat.get("supportOnly",false) else "crewed roster hull"
	if boat.get("needsHarborRepair",false):role+="; paid harbor repair needed"
	return "hull %.0f / %.0f · crew %d / %d minimum · %s"%[float(boat.get("hp",0)),float(boat.get("maxHp",0)),int(boat.get("crew",0)),int(boat.get("crewMin",0)),role]

static func _lots(c,lots: Dictionary) -> String:
	var parts: Array=[]
	for good in lots:
		if float(lots[good])>0:parts.append("%.2f %s"%[float(lots[good]),str(c.Goods.ITEMS.get(good,{"name":good}).name)])
	return ", ".join(parts) if not parts.is_empty() else "none"

static func _place(item: Dictionary) -> String:
	var location: String=str(item.get("location",""))
	if location.begins_with("mount"):return "weapon mount %d"%(location.trim_prefix("mount").to_int()+1)
	return "locker" if location=="locker" else location.capitalize()

static func _part_text(item: Dictionary) -> String:
	return "%s · %s · %.0f%% condition%s"%[Decisions.part_name(item),_place(item),float(item.get("hp",0))*100," · disabled" if str(item.get("status",""))=="disabled" else ""]

static func _parts(ui,body,items: Array,empty_text: String="No readable physical equipment snapshot is recorded.") -> void:
	for item in items:
		var line=ui.paragraph(body,_part_text(item),14,ui.TEAL)
		line.tooltip_text="Physical part: %s\nOrigin: %s\nCause: %s"%[str(item.get("itemUid","")),str(ui.host.core.hull(str(item.get("originHullType",""))).get("name",item.get("originHullType",""))),str(item.get("cause",""))]
	if items.is_empty():ui.paragraph(body,empty_text,14)

static func _allowance(ui,body,r: Dictionary,before: Dictionary={}) -> void:
	if r.is_empty():return
	if not r.get("routeOk",false):
		ui.paragraph(body,"No navigable, legal return harbor is quoted for this choice. No safe return is promised.",15,ui.RED)
		return
	var speed: String="%.1f"%float(r.get("routeSpeed",0))
	if not before.is_empty():speed="%.1f → %.1f"%[float(before.get("routeSpeed",0)),float(r.get("routeSpeed",0))]
	ui.paragraph(body,"Return to %s · %.2f sailing days after %.2f work days · speed %s water units/s."%[str(r.returnPortName),float(r.returnDays),float(r.get("workDays",0)),speed],15,ui.GOLD)
	ui.paragraph(body,"Work + return + 2 reserve days: %d payroll days / %s coins, plus %s existing arrears. Food %.2f bales (short %.2f); loaded fuel %.2f drums (short %.2f)."%[int(r.payrollDays),ui.money(r.returnWages),ui.money(r.wageArrears),float(r.foodRequired),float(r.foodShortfall),float(r.fuelRequired),float(r.fuelShortfall)],14)
	if int(r.get("pendingPayrollDays",0))>0:ui.paragraph(body,"This includes %d unsettled earlier payroll days; they do not add more sailing time."%int(r.pendingPayrollDays),14)
	ui.paragraph(body,"Hold after choice %.1f / %.1f; allowance overfill %.1f. %s These conservative allowances are not extra fees; encounters and later purchases can change them."%[float(r.cargoWeight),float(r.usableCapacity),float(r.allowanceOverload),"Reserves covered." if r.readyForAllowance else "Limit: "+str(r.bottleneck)+"."],14,ui.TEAL if r.readyForAllowance else ui.RED)

static func _service(ui,body,model: Dictionary) -> void:
	if model.is_empty():return
	var q: Dictionary=model.get("quote",{})
	if q.get("ok",false):
		ui.paragraph(body,"%s · today's installed hull/equipment service quote: %s coins (%.2f worker-days)."%[str(model.get("portName","Harbor")),ui.money(q.cost),float(q.workerDays)],15,ui.GOLD)
	for message in model.get("blockers",[]):ui.paragraph(body,str(message),14,ui.RED)
	ui.paragraph(body,"Service stock, workers and prices can change before arrival. Hire crew and buy operating stores separately. Locker spares retain their damage; fitting, compatibility and paid repair still apply.",14)

static func _focused(ui,body,w: Dictionary,encounter_ids: Array) -> void:
	var c=ui.host.core
	var id: String=str(w.id)
	var cargo_only: bool=_is_cargo_only067(c,w)
	ui.rule(body)
	ui.label(body,str(w.get("name","Wreck")),27,ui.GOLD,true)
	ui.paragraph(body,"%s · recorded day %.1f · %.0f water units away"%["Friendly loss" if w.get("friendly",false) else ("Surveyed expedition cache" if cargo_only else "Marked find"),float(w.get("day",0)),c.distance(c.state.position,w)],14,ui.TEAL)
	var nav_row=ui.row(body)
	ui.button(nav_row,"Chart wreck location",func():ui.host.respond(c.chart_course(w));ui.close_modal()).disabled=not c.state.get("exploration",{}).get("assignment",{}).is_empty()
	if c.distance(c.state.position,w)<=180 and not c.state.path.is_empty():
		ui.button(nav_row,"Idle engines for recovery",func():c.stop_sailing();open(ui,id,encounter_ids))
	if cargo_only:
		var base_q: Dictionary=c.recovery_quote(id,"strip")
		var lots: Dictionary=base_q.get("items",{}) if base_q.get("items") is Dictionary and not base_q.get("items",{}).is_empty() else c.Salvage._strip_items(w)
		var free_hold: float=maxf(0,c.capacity()-c.cargo_weight())
		var total_wt: float=0.0
		for gk in lots:
			var g_str: String=str(gk)
			total_wt+=float(lots[gk])*float(c.Goods.ITEMS.get(g_str,{"weight":1.0}).weight)
		ui.paragraph(body,"Collapsed supply coaster · finite cargo-only salvage. The hull frame is broken on the reef and has no towable hull or canonical fittings. Select explicit cargo lots that fit your traveling hold.",15,ui.GOLD)
		ui.paragraph(body,"Remaining cache weight: %.1f hold units · Free traveling hold: %.1f units · Spare able hands: %d\nRemote recovery consumes 1 repair kit per working day (cargo first, then boat racks) plus normal payroll and rations."%[total_wt,free_hold,c.Exploration.spare_crew(c.state)],14,ui.TEXT)
		ui.label(body,"Surviving cargo lots",21,ui.GOLD,true)
		for good_key in lots:
			var good: String=str(good_key)
			var qty: float=float(lots[good])
			if qty<=0.0 or not c.Goods.ITEMS.has(good):continue
			var unit_wt: float=float(c.Goods.ITEMS[good].weight)
			var row=ui.row(body)
			ui.paragraph(row,"%s · %.0f available (%.1f wt each · %.1f total wt)"%[str(c.Goods.ITEMS[good].name),qty,unit_wt,qty*unit_wt],14)
			var fits_whole: float=minf(qty,floorf((free_hold+0.00001)/maxf(0.01,unit_wt)))
			var fits: float=fits_whole if fits_whole>=1.0 else minf(qty,free_hold/maxf(0.01,unit_wt))
			ui.button(row,"Review 1",func():store_choice(ui,id,good,minf(1.0,qty),encounter_ids),false,false)
			if qty>=4.0:
				ui.button(row,"Review 4",func():store_choice(ui,id,good,minf(4.0,qty),encounter_ids),false,false)
			ui.button(row,"Review what fits (%.0f)"%fits,func():store_choice(ui,id,good,fits,encounter_ids),false,false).disabled=fits<=0.0
		if lots.is_empty():
			ui.paragraph(body,"No surviving cargo lots remain on this wreck.",14)
		return
	var model: Dictionary=Decisions.compare(c,id,"tow")
	var q: Dictionary=model.get("quote",{})
	ui.paragraph(body,"Real fitted parts · towing preserves their recorded damage.",15,ui.GOLD)
	_parts(ui,body,model.get("equipment",Decisions.equipment(w)))
	ui.button(body,"Choose real parts and destination locker",func():gear(ui,id,[],"",encounter_ids),false,false).disabled=not EquipmentRecovery.is_active(w) or bool(w.get("hullStripped",false))
	ui.label(body,"Finite stores and material",21,ui.GOLD,true)
	var lots: Dictionary=c.Salvage._strip_items(w)
	var free_hold: float=maxf(0,c.capacity()-c.cargo_weight())
	for good_key in lots:
		var good: String=str(good_key)
		var qty: float=float(lots[good])
		var row=ui.row(body)
		ui.paragraph(row,"%s · %.2f available (%.2f loose)"%[str(c.Goods.ITEMS[good].name),qty,float(w.get("stores",{}).get(good,0))],14)
		var fits: float=minf(qty,free_hold/float(c.Goods.ITEMS[good].weight))
		ui.button(row,"Review 1",func():store_choice(ui,id,good,minf(1,qty),encounter_ids),false,false)
		ui.button(row,"Review what fits",func():store_choice(ui,id,good,fits,encounter_ids),false,false).disabled=fits<=0
	if lots.is_empty():ui.paragraph(body,"No loose stores or component lots remain.",14)
	ui.label(body,"Preserve the damaged hull",21,ui.GOLD,true)
	ui.paragraph(body,str(q.get("message",model.get("message","Tow quote unavailable."))),15,ui.TEAL if q.get("ok",false) else ui.RED)
	if q.has("recoveredHp"):
		ui.paragraph(body,"Hull %.0f / %.0f after recovery · tug/inspection fee %s coins · %.2f crew work days."%[float(q.recoveredHp),float(q.fittedMaxHp),ui.money(q.get("total",0)),float(q.get("workDays",maxf(1,float(q.get("ordinary",100))/200.0)))],15,ui.GOLD)
	ui.paragraph(body,"A tow leaves it uncrewed, empty and needing paid harbor service. Take wanted stores first; ALL remaining loose stores are forfeited by the tow. The hull-only repair liability is an estimate, not the equipment restoration bill.",14)
	if q.get("repairLiability",{}) is Dictionary and not q.get("repairLiability",{}).is_empty():ui.paragraph(body,"Hull-only estimate: %.1f missing HP / %.2f repair kits. Actual installed-equipment service is priced separately below."%[float(q.repairLiability.get("missingHp",0)),float(q.repairLiability.get("supplies",0))],14)
	_allowance(ui,body,model.get("after",{}),model.get("before",{}))
	_service(ui,body,model.get("service",{}))
	ui.button(body,"Pay %s coins · tow damaged hull"%ui.money(q.get("total",0)),func():recover(ui,id,"tow","",0,encounter_ids),true,false).disabled=not model.get("ok",false)

static func store_choice(ui,id: String,good: String,qty: float,encounter_ids: Array=[]) -> void:
	if ui.host.mode!="campaign":return
	var body=_board(ui,"Take a finite lot","SELECTED STORES · CREW WORK · HOLD SPACE",1000,780)
	var c=ui.host.core
	var w: Dictionary=c.Salvage.find_wreck(c.state,id)
	if _is_cargo_only067(c,w):
		var q: Dictionary=c.recovery_quote(id,"strip",good,qty)
		var amount: float=float(q.get("quantity",qty))
		var good_name: String=str(c.Goods.ITEMS.get(good,{"name":good}).name)
		var unit_wt: float=float(c.Goods.ITEMS.get(good,{"weight":1.0}).weight)
		var avail: float=float(w.get("stores",{}).get(good,0.0))
		var free_hold: float=maxf(0.0,c.capacity()-c.cargo_weight())
		ui.label(body,"%.2f %s"%[amount,good_name],26,ui.GOLD,true)
		ui.paragraph(body,"Explicit cargo lot from %s · %.0f available on wreck · %.1f hold weight (%.1f free hold)."%[str(w.get("name","Collapsed Supply Coaster")),avail,float(q.get("weight",amount*unit_wt)),free_hold],16,ui.TEAL)
		var work_days: float=float(q.get("workDays",1.0))
		var kits_req: float=float(q.get("kitsRequired",q.get("supplies",work_days)))
		var payroll_days: int=int(q.get("payrollDays",int(work_days)))
		var wages: int=int(q.get("wages",0))
		var arrears: int=int(q.get("arrears",0))
		var food_req: float=float(q.get("food",0.0))
		ui.paragraph(body,"Work & preflight: %.0f working days · %.0f repair kits required (cargo first, then boat racks)\nPayroll: %d days · %s wages + %s existing arrears · %.2f food bales required."%[work_days,kits_req,payroll_days,ui.money(wages),ui.money(arrears),food_req],15,ui.GOLD)
		ui.paragraph(body,str(q.get("message","Quote unavailable.")),15,ui.TEAL if bool(q.get("ok",false)) else ui.RED)
		var preset_row=ui.row(body)
		for preset in [1.0,2.0,4.0,8.0]:
			if preset<=avail:
				ui.button(preset_row,"Lot %.0f"%preset,func():store_choice(ui,id,good,preset,encounter_ids),false,false)
		var fits_whole: float=minf(avail,floorf((free_hold+0.00001)/maxf(0.01,unit_wt)))
		if fits_whole>=1.0:
			ui.button(preset_row,"What fits (%.0f)"%fits_whole,func():store_choice(ui,id,good,fits_whole,encounter_ids),false,false)
		if avail>0.0:
			ui.button(preset_row,"All (%.0f)"%avail,func():store_choice(ui,id,good,avail,encounter_ids),false,false)
		ui.button(body,"Recover %.2f %s"%[amount,good_name],func():recover(ui,id,"strip",good,amount,encounter_ids),true,false).disabled=not bool(q.get("ok",false))
		ui.button(body,"Decline · return to wreck manifest",func():open(ui,id,encounter_ids),false,false)
		return
	var model: Dictionary=Decisions.compare(c,id,"strip",good,qty)
	w=model.get("wreck",w)
	var q: Dictionary=model.get("quote",{})
	var amount: float=float(q.get("quantity",qty))
	ui.label(body,"%.2f %s"%[amount,str(c.Goods.ITEMS.get(good,{"name":good}).name)],26,ui.GOLD,true)
	var structural: bool=amount>float(w.get("stores",{}).get(good,0))+0.000001
	ui.paragraph(body,"This takes structural material: the hull and all its physical equipment become permanently unrecoverable. Remaining finite component lots can still be stripped." if structural else "Only loose stores are selected. Hull and physical equipment stay aboard the marked wreck.",16,ui.RED if structural else ui.TEAL)
	if structural:_parts(ui,body,model.get("equipment",[]))
	ui.paragraph(body,str(q.get("message",model.get("message","Quote unavailable."))),15,ui.TEAL if q.get("ok",false) else ui.RED)
	_allowance(ui,body,model.get("after",{}),model.get("before",{}))
	ui.button(body,"Recover %.2f %s%s"%[amount,str(c.Goods.ITEMS.get(good,{"name":good}).name)," · forfeit hull and equipment" if structural else ""],func():recover(ui,id,"strip",good,amount,encounter_ids),true,false).disabled=not model.get("ok",false)
	ui.button(body,"Decline · take nothing",func():open(ui,id,encounter_ids),false,false)

## No part or destination is selected by default. Only the final button accepts
## the explicitly listed irreversible loss, then Main revalidates everything.
static func gear(ui,id: String,selected: Array=[],carrier_uid: String="",encounter_ids: Array=[]) -> void:
	if ui.host.mode!="campaign":return
	var body=_board(ui,"Recover selected real parts","IRREVERSIBLE DISMANTLING · EXISTING BOAT LOCKER")
	var c=ui.host.core
	var w: Dictionary={}
	for candidate in c.state.get("wrecks",[]):
		if str(candidate.get("id",""))==id:w=candidate;break
	if _is_cargo_only067(c,w):
		open(ui,id,encounter_ids)
		return
	var items: Array=Decisions.equipment(w)
	ui.paragraph(body,"Choose each physical part and an existing working boat. Nothing is selected automatically. Integral pumps stay with the lost hull.",16)
	for item in items:
		var uid: String=str(item.get("itemUid",""))
		var next: Array=selected.duplicate()
		if uid in next:next.erase(uid)
		else:next.append(uid)
		var control=ui.button(body,_part_text(item),func():gear(ui,id,next,carrier_uid,encounter_ids),false,false)
		control.toggle_mode=true
		control.button_pressed=uid in selected
		control.disabled=str(item.get("family",""))=="pumps"
		control.tooltip_text="Physical part: %s\nOrigin: %s"%[uid,str(c.hull(str(item.get("originHullType",""))).get("name",item.get("originHullType","")))]
	ui.label(body,"Destination · existing working hull",20,ui.GOLD,true)
	var destination=OptionButton.new()
	destination.custom_minimum_size.y=42
	destination.add_item("Choose destination boat…")
	destination.set_item_metadata(0,"")
	var chosen: int=0
	for boat in Decisions.carriers(c.state):
		var index: int=destination.item_count
		destination.add_item("%s · %.1f hold capacity"%[str(boat.get("name","Boat")),float(boat.get("spec",{}).get("cargo",0))])
		destination.set_item_metadata(index,str(boat.uid))
		if str(boat.uid)==carrier_uid:chosen=index
	destination.select(chosen)
	body.add_child(destination)
	destination.item_selected.connect(func(index):gear(ui,id,selected,str(destination.get_item_metadata(index)),encounter_ids))
	var request: Dictionary={"itemUids":selected.duplicate(),"carrierUid":carrier_uid}
	var model: Dictionary={}
	if not selected.is_empty() and not carrier_uid.is_empty():model=Decisions.compare(c,id,"gear","",0,request)
	var q: Dictionary=model.get("quote",{})
	ui.rule(body)
	ui.label(body,"Irreversible loss · review before dismantling",22,ui.GOLD,true)
	ui.paragraph(body,"Forfeit %s: the whole hull, EVERY unselected part including integral pumps, and ALL remaining structural component lots. No credit and no later tow or second equipment recovery. Loose stores stay finite on the marked wreck for separate collection."%str(w.get("name","this wreck")),16,ui.RED)
	var kept: Array=[]
	var lost: Array=[]
	for item in items:
		if str(item.get("itemUid","")) in selected:kept.append(item)
		else:lost.append(item)
	ui.paragraph(body,"Selected for the locker:",15,ui.GOLD)
	_parts(ui,body,q.get("selected",kept),"None selected.")
	ui.paragraph(body,"Lost equipment:",15,ui.RED)
	_parts(ui,body,q.get("forfeitedItems",lost),"No unselected parts.")
	ui.paragraph(body,"Component lots lost without credit: "+_lots(c,q.get("forfeitedComponents",w.get("components",{}))),14,ui.RED)
	ui.paragraph(body,"Loose stores left for separate collection: "+_lots(c,q.get("retainedStores",w.get("stores",{}))),14,ui.TEAL)
	if q.has("weight"):
		ui.paragraph(body,"Selected parts %.1f hold space · destination locker after %.1f / %.1f hull hold · fleet space before %.1f."%[float(q.weight),float(q.get("lockerWeight",0)),float(q.get("carrierCapacity",0)),float(q.get("freeCapacity",0))],15,ui.GOLD)
	if q.has("workDays"):
		ui.paragraph(body,"Actual work %.2f days · %d payroll boundaries · %s wages + %s arrears · %.2f food bales. No recovery fee; this is real crew work."%[float(q.workDays),int(q.get("payrollDays",0)),ui.money(q.get("wages",0)),ui.money(q.get("arrears",0)),float(q.get("food",0))],15)
	ui.paragraph(body,str(q.get("message","Choose at least one part and a destination to obtain the real quote.")),15,ui.TEAL if q.get("ok",false) else ui.RED)
	_allowance(ui,body,model.get("after",{}),model.get("before",{}))
	ui.paragraph(body,"Recovery preserves each selected part's identity, damage and origin. It goes into the chosen locker, not a working mount. Foreign original fittings may refuse installation; ordinary paid refit and service remain required.",14)
	ui.button(body,"Forfeit hull and listed parts · recover selection",func():_recover_gear(ui,id,selected,carrier_uid,encounter_ids),true,false).disabled=not model.get("ok",false)
	ui.button(body,"Decline · keep wreck marked",func():open(ui,id,encounter_ids),false,false)

static func _recover_gear(ui,id: String,selected: Array,carrier_uid: String,encounter_ids: Array) -> void:
	var request: Dictionary={"itemUids":selected.duplicate(),"carrierUid":carrier_uid,"acceptForfeiture":true}
	recover(ui,id,"gear","",0,encounter_ids,request)

static func owned_prize(ui,uid: String,focus_id: String="",encounter_ids: Array=[]) -> void:
	if ui.host.mode!="campaign":return
	var body=_board(ui,"Already-owned prize","YOUR ROSTER · ACTUAL CONDITION · LATER PAID SERVICE")
	var c=ui.host.core
	var model: Dictionary=Decisions.prize(c,uid)
	if not model.get("ok",false):
		ui.paragraph(body,str(model.get("message","Prize unavailable.")),16,ui.RED)
		ui.button(body,"Return to recovery",func():open(ui,focus_id,encounter_ids),false,false)
		return
	var boat: Dictionary=model.boat
	ui.label(body,str(boat.get("name","Captured boat")),26,ui.GOLD,true)
	ui.paragraph(body,"Already owned · "+_boat_summary(boat),16,ui.TEAL)
	ui.paragraph(body,"An empty cargo hold does not remove this boat from your roster. Closing or leaving wrecks marked keeps this prize and all its fittings.",15)
	_parts(ui,body,model.equipment)
	ui.label(body,"Actual prize cargo",21,ui.GOLD,true)
	ui.paragraph(body,_lots(c,boat.get("convoyCargo",{})),15)
	var free_hold: float=maxf(0,c.capacity()-c.cargo_weight())
	for good_key in boat.get("convoyCargo",{}):
		var good: String=str(good_key)
		var qty: float=float(boat.convoyCargo[good])
		if qty<=0 or not c.Goods.ITEMS.has(good):continue
		var fits: float=minf(qty,free_hold/float(c.Goods.ITEMS[good].weight))
		ui.button(body,"Take what fits · %.2f %s"%[fits,str(c.Goods.ITEMS[good].name)],func():ui.host.take_prize_cargo(uid,good,fits);owned_prize(ui,uid,focus_id,encounter_ids)).disabled=fits<=0
	_allowance(ui,body,model.get("return",{}))
	_service(ui,body,model.get("service",{}))
	ui.button(body,"Inspect normal equipment and service",func():ui.open_equipment(uid),false,false)
	ui.button(body,"Keep prize · return to recovery",func():open(ui,focus_id,encounter_ids),false,false)

static func captured_prizes(c) -> Array:
	return Decisions.captured_prizes(c.state)

static func take_cargo(ui,uid: String,good: String,qty: float,focus_id: String="",encounter_ids: Array=[]) -> void:
	ui.host.take_prize_cargo(uid,good,qty)
	open(ui,focus_id,encounter_ids)

static func leave(ui) -> void:
	ui.close_modal()

static func recover(ui,id: String,mode: String,good: String="",qty: float=0.0,encounter_ids: Array=[],request: Dictionary={}) -> void:
	ui.host.recover_wreck(id,mode,good,qty,request)
	open(ui,id,encounter_ids)

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
		ui.button(body,"Review already-owned prizes",ui.host.open_battle_recovery,ids.is_empty()).disabled=ui.host.core.active_fleet().is_empty()
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
