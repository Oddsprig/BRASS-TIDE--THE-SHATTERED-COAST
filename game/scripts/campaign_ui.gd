extends RefCounted
const Routes=preload("res://scripts/route_cache.gd")
const Stories=preload("res://scripts/coastal_stories.gd")
const Panel=preload("res://scripts/voyage_panel070.gd")
## Focused campaign windows; main-thread UI only.

static func _is_local_or_home067(c) -> bool:
	if c.home_local064():return true
	var v: Dictionary=c.world_view064() if c is Object and c.has_method("world_view064") else {}
	return str(v.get("layer",""))=="local"

static func _exploration_view067(c) -> Dictionary:
	if c is Object and c.has_method("exploration_view067"):
		var v=c.exploration_view067()
		if v is Dictionary:return v
	return {}

static func _local_name069(c) -> String:
	if c.home_local064():return "Shatter Coast"
	var view: Dictionary=c.world_view064() if c is Object and c.has_method("world_view064") else {}
	var named: String=str(view.get("name","")).strip_edges()
	return named if not named.is_empty() else "These waters"

static func _visible_sites067(c) -> Array:
	if c.home_local064():
		var home_out: Array=[]
		for item in c.Exploration.sites(c.state):
			if int(item.get("level",0))<=0:continue
			if str(item.get("regionId","shatter_coast"))!="shatter_coast":continue
			home_out.append(item)
		return home_out
	var raw_sites: Array=[]
	var exp067: Dictionary=_exploration_view067(c)
	if exp067.get("sites") is Array:
		raw_sites=exp067.get("sites",[])
	elif c.Exploration is Object and c.Exploration.has_method("visible_sites"):
		raw_sites=c.Exploration.visible_sites(c.state)
	var out: Array=[]
	for item in raw_sites:
		if not (item is Dictionary):continue
		var lvl: int=int(item.get("level",0))
		if lvl<=0:continue
		var copy: Dictionary=item.duplicate(true)
		if not copy.has("region") or str(copy.get("region","")).is_empty():
			copy["region"]=_local_name069(c)
		if lvl<2:
			copy["hazard"]=""
		if lvl<3:
			copy["discovery"]=""
			copy["resource"]=""
			copy["leadId"]=""
		out.append(copy)
	return out

static func _find_visible_site067(c,site_id: String) -> Dictionary:
	if site_id.is_empty():return {}
	for item in _visible_sites067(c):
		if str(item.get("id",""))==site_id:return item
	return {}

static func _local_assignment067(c) -> Dictionary:
	var exp067: Dictionary=_exploration_view067(c)
	if not c.home_local064() and exp067.get("assignment") is Dictionary:
		return exp067.get("assignment",{})
	var a: Dictionary=c.Exploration.assignment(c.state)
	if a.is_empty():return {}
	var active_reg: String="shatter_coast" if c.home_local064() else str(c.world_view064().get("regionId","glasswind_keys"))
	var a_reg: String=str(a.get("world064",{}).get("regionId","shatter_coast")) if a.get("world064") is Dictionary else "shatter_coast"
	return a if a_reg==active_reg else {}

static func _local_wrecks067(c) -> Array:
	var exp067: Dictionary=_exploration_view067(c)
	var out: Array=[]
	if exp067.get("wrecks") is Array:
		for w in exp067.get("wrecks",[]):
			if w is Dictionary and str(w.get("status","unclaimed"))=="unclaimed":out.append(w)
		return out
	var active_reg: String="shatter_coast" if c.home_local064() else str(c.world_view064().get("regionId","glasswind_keys"))
	for w in c.state.get("wrecks",[]):
		if not (w is Dictionary) or str(w.get("status",""))!="unclaimed":continue
		var w_reg: String=str(w.get("world064",{}).get("regionId","shatter_coast")) if w.get("world064") is Dictionary else "shatter_coast"
		if w_reg==active_reg:out.append(w)
	return out

static func expedition(ui,use_site: bool=true) -> void:
	if not ui.host.core.home_local064():ui.open_ocean064();return
	ui.host.sync_economy()
	ui.modal_kind="expedition"
	var body=ui.modal("Prepare an expedition","VOYAGE LIMITS · RETURN ALLOWANCE · FLEET GROWTH",980,780)
	body.add_theme_constant_override("separation",9)
	var c=ui.host.core
	var prep_header: Dictionary=Panel.board_header(c)
	var prep_chart: String=str(prep_header.region) if not str(prep_header.region).is_empty() else "this chart"
	var prep_place: String=str(prep_header.name) if bool(prep_header.docked) else "under way"
	ui.paragraph(body,"Preparing in %s · %s. The route uses the landing or harbor you selected."%[prep_place,prep_chart],15)
	var destination: Dictionary=c.port(ui.host.selected_port)
	var site_id: String=str(ui.host.selected_site) if use_site else ""
	var island: Dictionary=c.Expedition._known_site(c.state,site_id)
	var route: Array=[]
	var length: float=0.0
	if island.is_empty() and not destination.is_empty():
		route=Routes.path(c,c.state.position,destination)
		for i in range(1,route.size()):length+=c.distance(route[i-1],route[i])
	var r: Dictionary=c.expedition_report(length)
	if island.is_empty() and not destination.is_empty() and route.is_empty():r.readyForAllowance=false;r.bottleneck="No safe water route"
	if not island.is_empty():
		var return_port: String=str(destination.get("id",""))
		for job in c.state.get("voyageJobs",[]):
			if job.kind=="survey" and job.state=="active" and str(job.siteId)==site_id:return_port=str(job.port);break
		var detour: String=""
		for lead in Stories.earned_leads(c.state,"middle_sea_chart"):
			if str(lead.id)=="rust_salvage_anchorage" and str(lead.id)!=site_id:detour=str(lead.id)
		r=c.Expedition.preview(c,site_id,return_port,detour)
	ui.paragraph(body,"Limit: "+str(r.bottleneck),23,ui.TEAL if r.readyForAllowance else ui.GOLD)
	if not island.is_empty():
		ui.paragraph(body,"%s → return to %s\n%.2f travel + %.2f shore work + %.1f contingency = %.2f days to fund"%[r.siteName,r.returnPortName,r.travelDays,r.shoreDays,r.reserveDays,r.tripDays],16,ui.TEXT)
		ui.paragraph(body,"Remaining chart %.2f days / full survey %.2f days · %d spare hands needed / %d available\n%.2f shore rations prepaid within normal food use · %.0f kits committed · all owned sailors remain paid."%[r.chartDays,r.surveyDays,r.crewNeeded,r.spareCrew,r.shoreFood,r.shoreKits],14)
		ui.paragraph(body,"Payroll and rations reserve %.0f whole daily charges, including the current partial day."%r.payrollDays,13)
		for work in r.work:ui.paragraph(body,str(work.action).capitalize()+": "+str(work.message),13)
		ui.paragraph(body,r.routeMessage,14,ui.TEAL if r.routeOk else ui.RED)
		expedition_comparison(ui,body,"Return now to "+str(r.returnPortName),r.returnNow)
		if not r.detour.is_empty():
			expedition_comparison(ui,body,"Optional "+str(r.detour.get("siteName","landing"))+" · +%.2f days versus returning now"%r.detour.extraDays,r.detour)
		ui.paragraph(body,"Full level 3 is budgeted for paid surveys; the Chart Rock story clue needs only level 2. Recovery and combat time are additional. Fuel covers travel and contingency, never idle shore days.",13)
		if not destination.is_empty():ui.button(body,"Prepare selected harbor instead: "+str(destination.name),func():expedition(ui,false))
	elif not destination.is_empty():
		ui.paragraph(body,"%s · %.0f water route\n%.2f days outward + %.2f return + %.1f contingency = %.2f days to fund"%[destination.name,length,r.outwardDays,r.returnDays,r.reserveDays,r.tripDays],16,ui.TEXT)
		if route.is_empty():ui.paragraph(body,"No safe water route found. Choose another destination on the chart.",15,ui.RED)
		if not use_site and not str(ui.host.selected_site).is_empty():ui.button(body,"Prepare selected island instead",func():expedition(ui,true))
	else:
		ui.paragraph(body,"Select a destination on the chart to include outward and return travel. This preview covers only %.1f contingency days."%r.reserveDays,16,ui.TEXT)
	var gaps: Array[String]=[]
	if r.foodShortfall>0.001:gaps.append("%.1f food"%r.foodShortfall)
	if r.fuelShortfall>0.001:gaps.append("%.1f working fuel"%r.fuelShortfall)
	if r.wageShortfall>0:gaps.append("%s coins"%ui.money(r.wageShortfall))
	if r.allowanceOverload>0.001:gaps.append("%.1f hold space"%r.allowanceOverload)
	if int(r.get("crewShortfall",0))>0:gaps.append("%d spare sailors"%r.crewShortfall)
	if float(r.get("kitShortfall",0))>0.001:gaps.append("%.1f shore kits"%r.kitShortfall)
	var gap_text: String="Food, loaded fuel, hold and payroll covered."
	var gap_color: Color=ui.TEAL
	if not gaps.is_empty():gap_text=" · ".join(gaps);gap_color=ui.RED
	elif not r.readyForAllowance:gap_text="See the voyage limit above.";gap_color=ui.GOLD
	ui.paragraph(body,"Allowance gaps: "+gap_text,16,gap_color)
	var summary=ui.row(body)
	summary.add_theme_constant_override("separation",24)
	var purse=ui.column(summary)
	ui.eyebrow(purse,"PROTECT THE RETURN")
	ui.paragraph(purse,"Projected return purse: %s coins"%ui.money(maxf(0,float(r.fundsAfterArrears)-float(r.returnWages))),20,ui.GOLD)
	ui.paragraph(purse,"%s payroll allowance + %s old wages\n%s coins/day · %.1f payroll days funded"%[ui.money(r.returnWages),ui.money(r.wageArrears),ui.money(r.dailyWages),r.affordableDays],14)
	var stores=ui.column(summary)
	ui.eyebrow(stores,"USEFUL PAYLOAD")
	ui.paragraph(stores,"%.1f useful hold after food top-up"%r.payloadAfterFood,20,ui.TEAL)
	ui.paragraph(stores,"%.1f / %.1f hold now · %.1f free\nFood %.1f days · %d traveling crew · %.1f repair kits"%[r.cargoWeight,r.usableCapacity,r.freeCapacity,r.foodDays,r.crew,r.repairKits],14)
	var limiter: Dictionary={}
	for boat: Dictionary in r.boats:
		if limiter.is_empty() or float(boat.loadedDays)<float(limiter.loadedDays):limiter=boat
	if not limiter.is_empty():
		ui.paragraph(body,"Fuel limiter: %s · %.1f loaded days · %.1f more fuel needed for this allowance"%[limiter.name,limiter.loadedDays,limiter.fuelShortfall],16,ui.GOLD)
		if limiter.tankShortfall>0.001:ui.paragraph(body,"Its allowance exceeds its fitted tank by %.1f. Plan refueling or a shorter voyage; an empty tanker adds no shared fuel."%limiter.tankShortfall,14,ui.RED)
	ui.paragraph(body,"Payload above is before fuel loading. %.1f loose fuel is cargo, not working fuel. Load reserves through Cargo. Stops, combat, surveys and towing can add time."%r.looseFuel,13)
	var actions=ui.row(body)
	ui.button(actions,"Cargo, stores & accounts",ui.open_cargo)
	ui.button(actions,"Manage traveling boats and stored reserves",ui.open_fleet)
	if r.wageArrears>0 or float(c.state.get("debt",0))>0:
		ui.paragraph(body,"Cargo accounts: settle owed wages and review the %s-coin rescue/harbor loan."%ui.money(c.state.get("debt",0)),14,ui.GOLD)
	if not island.is_empty():
		ui.button(body,"Review landing: "+str(island.name),func():site(ui,site_id))
		ui.button(body,"Prepare route to "+str(island.name),func():ui.host.respond(c.chart_course(island));ui.close_modal(),true).disabled=not r.routeOk or r.overload>0 or not c.state.exploration.assignment.is_empty()
	elif not destination.is_empty():
		ui.button(body,"Prepare route to "+str(destination.name),func():ui.host.sail_to(destination.id);ui.close_modal(),true).disabled=route.is_empty() or r.overload>0
	ui.rule(body)
	ui.eyebrow(body,"A PARTNER FOR THE NEXT VOYAGE")
	ui.paragraph(body,"%d owned hulls / %d points · %d traveling · %d inactive (%d stored)\nBattle line: %d / %d points · %d traveling boats held in reserve"%[r.ownedCount,r.ownedDP,r.travelingCount,r.inactiveCount,r.storedCount,r.battleDP,r.battleLimit,r.battleReserveCount],15,ui.TEXT)
	ui.paragraph(body,"Ownership can exceed 300 points. Only crewed, seaworthy traveling hulls add hold space. Stored sailors still draw food and wages. Traveling support can stay outside the battle line.",13)
	if not r.supportOptions.is_empty():
		expedition_owned_support(ui,body,r.supportOptions)
	else:
		expedition_yard_support(ui,body)
	ui.paragraph(body,"A partner carries more provisions or freight, but adds crew, food and fuel demand and may slow the flotilla. A tanker carries purchased reserves; each boat still needs its own fuel loaded. A paid workshop fitting helps crew repairs; kits remain finite and the fitting costs hold space and speed.",14)
	ui.rule(body)
	var details=ui.column(body)
	details.visible=false
	for boat: Dictionary in r.boats:
		ui.paragraph(details,"%s · %.1f fuel loaded / %.1f required · %.1f days loaded\nTank %.1f · Burn %.2f/day · Short %.1f fuel · %.1f beyond fitted tank"%[boat.name,boat.loadedFuel,boat.fuelRequired,boat.loadedDays,boat.tankCapacity,boat.fuelPerDay,boat.fuelShortfall,boat.tankShortfall],14)
	for warning in r.warnings:ui.paragraph(details,str(warning),14,ui.RED)
	var toggle=ui.button(body,"Fuel by boat & voyage cautions",func():details.visible=not details.visible)
	body.move_child(toggle,details.get_index())

static func expedition_comparison(ui,body: Node,title: String,r: Dictionary) -> void:
	ui.paragraph(body,title+"\n%.2f days · %s payroll coins · %.2f food · %.1f loaded fuel · %.0f shore kits\nMissing %s coins / %.2f food / %.1f loaded fuel / %.0f kits · %s"%[r.tripDays,ui.money(r.returnWages),r.foodRequired,r.fuelRequired,r.get("shoreKits",0),ui.money(r.wageShortfall),r.foodShortfall,r.fuelShortfall,r.get("kitShortfall",0),r.bottleneck],14,ui.TEAL if r.readyForAllowance else ui.GOLD)

static func expedition_owned_support(ui,body: Node,options: Array) -> void:
	ui.paragraph(body,"Compare an owned reserve · preview only",17,ui.GOLD)
	var choice=OptionButton.new()
	choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for option: Dictionary in options:choice.add_item(str(option.name))
	body.add_child(choice)
	var details=ui.paragraph(body,expedition_support_text(ui,options[0]),14,ui.TEXT)
	choice.item_selected.connect(func(index: int):details.text=expedition_support_text(ui,options[index]))
	ui.paragraph(body,"Projection uses today's route speed. Collect, repair, crew and activate through Fleet, then review again if the added boat is slower. Existing sailors are already in the payroll above.",13)

static func expedition_support_text(ui,option: Dictionary) -> String:
	var location: String="With the flotilla" if str(option.storedPort).is_empty() else "Stored at "+str(ui.host.core.port(str(option.storedPort)).get("name",option.storedPort))
	var blockers: Array[String]=[]
	for blocker in option.blockers:blockers.append(str(blocker))
	return "%s · Up to +%.1f hold when ready\nHire %d to minimum · +%s coins/day and +%.2f food/day for new crew\nOwn fuel %.1f loaded / %.1f allowance · %.1f short · %.1f beyond tank\n%s"%[location,option.addedCapacity,option.crewToMinimum,ui.money(option.additionalDailyWages),option.additionalFoodPerDay,option.loadedFuel,option.fuelRequired,option.fuelShortfall,option.tankShortfall,"; ".join(blockers) if not blockers.is_empty() else "Ready to review activation in Fleet."]

static func expedition_yard_support(ui,body: Node) -> void:
	var c=ui.host.core
	var port: Dictionary=c.current_port()
	if port.is_empty():
		var berth: Dictionary=Panel.work_berth(c)
		if not berth.is_empty():ui.paragraph(body,"Docked at %s. Boatyard prices are quoted on the home service harbor, and this list does not buy a hull here."%str(berth.get("name","this berth")),15,ui.GOLD)
		else:ui.paragraph(body,"No inactive owned partner to compare. Visit a harbor to see its actual boatyard prices and available support designs.",15,ui.GOLD)
		return
	var candidates: Array=[]
	var catalogue: Array=c.Harbor.catalogue(c,port)
	for id in catalogue:
		var hull: Dictionary=c.hull(str(id))
		if str(hull.get("civilianRole","")) in ["transport","tanker"]:candidates.append(hull)
		if candidates.size()>=3:break
	if candidates.is_empty() and not catalogue.is_empty():candidates.append(c.hull(str(catalogue[0])))
	if candidates.is_empty():
		ui.paragraph(body,"This harbor has no quoted designs. Compare an owned partner in Fleet or visit another yard.",14)
		return
	ui.paragraph(body,"Local yard: a possible next boat · quoted at "+str(port.name),17,ui.GOLD)
	var choice=OptionButton.new()
	choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for hull: Dictionary in candidates:choice.add_item(str(hull.name))
	body.add_child(choice)
	var details=ui.paragraph(body,expedition_yard_text(ui,port,candidates[0]),14,ui.TEXT)
	choice.item_selected.connect(func(index: int):details.text=expedition_yard_text(ui,port,candidates[index]))
	ui.button(body,"Review local boatyard",func():ui.open_port("Boatyard"))

static func expedition_yard_text(ui,port: Dictionary,hull: Dictionary) -> String:
	var c=ui.host.core
	var quote: Dictionary=c.Harbor.quote(c,hull,port)
	var advance: int=c.Economy.recruit_cost(port,int(hull.crewMin))
	var upkeep: Dictionary=c.Economy.daily_upkeep([{"crew":int(hull.crewMin),"spec":hull}])
	return "%s hull + %s minimum-crew advance = %s coins before stores\n%d completed hulls in stock · Commission %s coins, about %.1f days with a full team\n%d hold · %d minimum crew · +%s wages and +%.2f food/day before specialists · %d hull speed\nCompare here, then confirm in Boatyard, where crew availability, materials and access are checked."%[ui.money(quote.readyPrice),ui.money(advance),ui.money(int(quote.readyPrice)+advance),int(port.get("shipStock",{}).get(hull.id,0)),ui.money(quote.commissionPrice),quote.estimatedDays,hull.cargo,hull.crewMin,ui.money(upkeep.wages),upkeep.food,hull.speed]

static func notes(ui) -> void:
	ui.modal_kind="developer_notes"
	var body=ui.modal("Development notes","BRASS TIDE · v"+ui.host.Version.text(),1000,790)
	var path="res://data/DEVELOPER NOTES.txt"
	ui.paragraph(body,FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "Development notes are being prepared for this build.",15,ui.TEXT)
	ui.rule(body)
	var render_mode: int = int(ProjectSettings.get_setting("rendering/driver/threads/thread_model", 1))
	var render_label: String = "Separate" if render_mode == 2 else ("Safe" if render_mode == 1 else "Single")
	ui.paragraph(body,"Processor: %s · %d logical threads\nHarbor production: up to %d copied-state workers · Rendering mode: %s"%[OS.get_processor_name(),OS.get_processor_count(),clampi(OS.get_processor_count()-2,1,8),render_label],14,ui.TEAL)

static func islands(ui) -> void:
	var c=ui.host.core
	if not _is_local_or_home067(c):ui.open_ocean064();return
	ui.modal_kind="islands"
	var is_home: bool=c.home_local064()
	var body=ui.modal("Island charts" if is_home else _local_name069(c)+" surveys","EXPLORE · SURVEY · FOLLOW A LEAD",1000,790)
	var assignment: Dictionary=_local_assignment067(c)
	ui.paragraph(body,"Sail near a landmark to sight it. Chart the approaches, then land a deeper survey. Your party needs real spare hands, rations and kits. Wages continue while ashore.",16)
	if not assignment.is_empty():
		ui.label(body,"Party ashore: %s · %.1f / %.1f days"%[str(assignment.get("siteId","")),float(assignment.get("daysDone",0.0)),float(assignment.get("daysTotal",0.0))],20,ui.GOLD)
		ui.button(body,"Advance one survey day",func():survey_day(ui),true)
		ui.button(body,"Recall shore party",func():ui.host.respond(c.recall_survey());islands(ui))
	var visible: Array=_visible_sites067(c)
	var known: int=0
	for item in visible:
		if int(item.get("level",0))<=0:continue
		known+=1
		var s: Dictionary=item
		var lvl: int=int(s.get("level",0))
		var reg_lbl: String=str(s.get("region",_local_name069(c)))
		ui.rule(body)
		ui.label(body,str(s.get("name","Landmark")),23,ui.GOLD,true)
		ui.paragraph(body,"%s · %s · %.0f water units away"%[reg_lbl,str(s.get("levelName","")).capitalize(),c.distance(c.state.position,s)],14,ui.TEAL)
		ui.paragraph(body,str(s.get("clue","")) if lvl<3 else str(s.get("discovery",s.get("clue",""))),15)
		ui.button(body,"Inspect landmark / chart approach",func():site(ui,str(s.id)))
	ui.rule(body)
	ui.paragraph(body,"%d known landmarks. Uncharted reaches still hold coves, workshops, resources and wreck fields."%known,15)
	if not is_home:
		var local_wrecks: Array=_local_wrecks067(c)
		var nav_row=ui.row(body)
		if not local_wrecks.is_empty():
			ui.button(nav_row,"Recover stores at "+str(local_wrecks[0].get("name","Collapsed Supply Coaster")),func():ui.RecoveryUI.open(ui,str(local_wrecks[0].get("id",""))),true)
		ui.button(nav_row,"Plan return voyage to Shatter Coast",func():ui.open_voyage_preparation065("shatter_coast"))

static func site(ui,site_id: String) -> void:
	var c=ui.host.core
	if not _is_local_or_home067(c):ui.open_ocean064();return
	var s: Dictionary=_find_visible_site067(c,site_id)
	if s.is_empty() or int(s.get("level",0))<=0:return
	var is_home: bool=c.home_local064()
	var lvl: int=int(s.get("level",0))
	var reg_lbl: String=str(s.get("region",_local_name069(c)))
	ui.host.selected_site=site_id
	ui.modal_kind="island_site"
	var body=ui.modal(str(s.get("name","Landmark")),"%s · %s"%[reg_lbl,str(s.get("levelName","")).to_upper()],950,780)
	ui.paragraph(body,str(s.get("clue","")),18,ui.TEXT)
	if lvl>=2 and not str(s.get("hazard","")).is_empty():
		ui.paragraph(body,"Approach: "+str(s.get("hazard","")),15,ui.GOLD)
	if lvl>=3:
		ui.label(body,"Survey findings",25,ui.GOLD,true)
		ui.paragraph(body,str(s.get("discovery","")),18,ui.TEXT)
		ui.paragraph(body,"Opportunity: "+str(s.get("resource",""))+". Knowledge identifies the site; production and recovery still require actual work and equipment.",15)
		if not is_home:
			var local_wrecks: Array=_local_wrecks067(c)
			if not local_wrecks.is_empty():
				ui.button(body,"Inspect collapsed supply coaster & recover stores",func():ui.RecoveryUI.open(ui,str(local_wrecks[0].get("id",""))),true)
	else:
		var action: String="chart" if lvl==1 else "survey"
		var q: Dictionary=c.Exploration.quote(c.state,site_id,action)
		ui.label(body,"Chart the approaches" if action=="chart" else "Land a resource survey",24,ui.GOLD,true)
		ui.paragraph(body,"%d spare crew · %.1f days · %.2f prepaid rations · %.0f kits\nThe payroll continues at %s coins/day for your existing crew."%[int(q.get("crewNeeded",0)),float(q.get("days",0.0)),float(q.get("food",0.0)),float(q.get("supplies",0.0)),ui.money(c.Economy.daily_upkeep(c.state.fleet).wages)],16)
		ui.paragraph(body,str(q.get("message","")),15,ui.TEAL if bool(q.get("ok",false)) else ui.RED)
		if c.distance(c.state.position,s)<=180 and not c.state.path.is_empty():ui.button(body,"Idle engines at this landing",func():c.stop_sailing();site(ui,site_id))
		ui.button(body,"Assign shore party",func():ui.host.respond(c.begin_survey(site_id,action));site(ui,site_id),true).disabled=not bool(q.get("ok",false)) or c.distance(c.state.position,s)>180 or not c.state.path.is_empty()
	var lead_id: String=str(s.get("leadId",""))
	if lvl>=2 and not lead_id.is_empty():
		var lead: Dictionary=_find_visible_site067(c,lead_id)
		if not lead.is_empty():ui.button(body,"Follow earned lead: "+str(lead.get("name",lead_id)),func():site(ui,str(lead.id)))
	var assignment: Dictionary=_local_assignment067(c)
	if not assignment.is_empty():
		ui.paragraph(body,"Party progress %.1f / %.1f days. Recall the party before sailing."%[float(assignment.get("daysDone",0.0)),float(assignment.get("daysTotal",0.0))],16,ui.GOLD)
		ui.button(body,"Advance one survey day",func():survey_day(ui,site_id),true)
		ui.button(body,"Recall party",func():ui.host.respond(c.recall_survey());site(ui,site_id))
	else:
		ui.button(body,"Prepare route to "+str(s.get("name","this landing")),func():ui.host.respond(c.chart_course(s));ui.close_modal(),true)
	if is_home:
		ui.button(body,"Prepare this island work & named return",func():expedition(ui))
	else:
		ui.button(body,"Plan return voyage to Shatter Coast",func():ui.open_voyage_preparation065("shatter_coast"))
	ui.button(body,"Island charts",func():islands(ui))

static func survey_day(ui,reopen_site_id: String="") -> void:
	ui.host.sync_economy()
	ui.host.core.wait_day()
	ui.host.start_economy()
	ui.host.sync_economy()
	ui.host.save_game(false)
	if not reopen_site_id.is_empty() and not _find_visible_site067(ui.host.core,reopen_site_id).is_empty():
		site(ui,reopen_site_id)
	else:
		islands(ui)
