extends RefCounted
const Routes=preload("res://scripts/route_cache.gd")
## Focused campaign windows; main-thread UI only.

static func expedition(ui) -> void:
	ui.host.sync_economy()
	ui.modal_kind="expedition"
	var body=ui.modal("Prepare an expedition","VOYAGE LIMITS · RETURN ALLOWANCE · FLEET GROWTH",980,780)
	body.add_theme_constant_override("separation",9)
	var c=ui.host.core
	var destination: Dictionary=c.port(ui.host.selected_port)
	var route: Array=[]
	var length: float=0.0
	if not destination.is_empty():
		route=Routes.path(c,c.state.position,destination)
		for i in range(1,route.size()):length+=c.distance(route[i-1],route[i])
	var r: Dictionary=c.expedition_report(length)
	ui.paragraph(body,"Limit: "+str(r.bottleneck),23,ui.TEAL if r.readyForAllowance else ui.GOLD)
	if not destination.is_empty():
		ui.paragraph(body,"%s · %.0f water route\n%.2f days outward + %.2f return + %.1f contingency = %.2f days to fund"%[destination.name,length,r.outwardDays,r.returnDays,r.reserveDays,r.tripDays],16,ui.TEXT)
		if route.is_empty():ui.paragraph(body,"No safe water route found. Choose another destination on the chart.",15,ui.RED)
	else:
		ui.paragraph(body,"Select a destination on the chart to include outward and return travel. This preview covers only %.1f contingency days."%r.reserveDays,16,ui.TEXT)
	var gaps: Array[String]=[]
	if r.foodShortfall>0.001:gaps.append("%.1f food"%r.foodShortfall)
	if r.fuelShortfall>0.001:gaps.append("%.1f working fuel"%r.fuelShortfall)
	if r.wageShortfall>0:gaps.append("%s coins"%ui.money(r.wageShortfall))
	if r.allowanceOverload>0.001:gaps.append("%.1f hold space"%r.allowanceOverload)
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
	if not destination.is_empty():
		ui.button(body,"Chart course to "+str(destination.name),func():ui.host.sail_to(destination.id);ui.close_modal(),true).disabled=route.is_empty() or r.overload>0
	ui.rule(body)
	ui.eyebrow(body,"A PARTNER FOR THE NEXT VOYAGE")
	ui.paragraph(body,"%d owned hulls / %d points · %d traveling · %d inactive (%d stored)\nBattle line: %d / %d points · %d traveling boats held in reserve"%[r.ownedCount,r.ownedDP,r.travelingCount,r.inactiveCount,r.storedCount,r.battleDP,r.battleLimit,r.battleReserveCount],15,ui.TEXT)
	ui.paragraph(body,"Ownership can exceed 300 points. Only crewed, seaworthy traveling hulls add hold space. Stored sailors still draw food and wages. Traveling support can stay outside the battle line.",13)
	if not r.supportOptions.is_empty():
		expedition_owned_support(ui,body,r.supportOptions)
	else:
		expedition_yard_support(ui,body)
	ui.paragraph(body,"A cargo partner carries more provisions or freight, but adds crew, food and fuel demand and may slow the flotilla. A tanker carries purchased reserves; each boat still needs its own fuel loaded. A paid workshop fitting helps crew repairs; kits remain finite and the fitting costs hold space and speed.",14)
	ui.rule(body)
	var details=ui.column(body)
	details.visible=false
	for boat: Dictionary in r.boats:
		ui.paragraph(details,"%s · %.1f fuel loaded / %.1f required · %.1f days loaded\nTank %.1f · Burn %.2f/day · Short %.1f fuel · %.1f beyond fitted tank"%[boat.name,boat.loadedFuel,boat.fuelRequired,boat.loadedDays,boat.tankCapacity,boat.fuelPerDay,boat.fuelShortfall,boat.tankShortfall],14)
	for warning in r.warnings:ui.paragraph(details,str(warning),14,ui.RED)
	var toggle=ui.button(body,"Fuel by boat & voyage cautions",func():details.visible=not details.visible)
	body.move_child(toggle,details.get_index())

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
		ui.paragraph(body,"No inactive owned partner to compare. Visit a harbor to see its actual boatyard prices and available support designs.",15,ui.GOLD)
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
	ui.modal_kind="islands"
	var body=ui.modal("Island charts","EXPLORE · SURVEY · FOLLOW A LEAD",1000,790)
	var c=ui.host.core
	var assignment: Dictionary=c.Exploration.assignment(c.state)
	ui.paragraph(body,"Sail near a landmark to sight it. Chart the approaches, then land a deeper survey. Your party needs real spare hands, rations and kits. Wages continue while ashore.",16)
	if not assignment.is_empty():
		ui.label(body,"Party ashore: %s · %.1f / %.1f days"%[assignment.siteId,assignment.daysDone,assignment.daysTotal],20,ui.GOLD)
		ui.button(body,"Advance one survey day",func():survey_day(ui),true)
		ui.button(body,"Recall shore party",func():ui.host.respond(c.recall_survey());islands(ui))
	var known: int=0
	for item in c.Exploration.sites(c.state):
		if item.level==0:continue
		known+=1
		var s: Dictionary=item
		ui.rule(body)
		ui.label(body,str(s.name),23,ui.GOLD,true)
		ui.paragraph(body,"%s · %s · %.0f water units away"%[s.region,str(s.levelName).capitalize(),c.distance(c.state.position,s)],14,ui.TEAL)
		ui.paragraph(body,s.clue if s.level<3 else s.discovery,15)
		ui.button(body,"Inspect landmark / chart approach",func():site(ui,s.id))
	ui.rule(body)
	ui.paragraph(body,"%d known landmarks. Uncharted reaches still hold coves, workshops, resources and wreck fields."%known,15)

static func site(ui,site_id: String) -> void:
	var c=ui.host.core
	var s: Dictionary={}
	for item in c.Exploration.sites(c.state):
		if item.id==site_id:s=item;break
	if s.is_empty() or s.level==0:return
	ui.host.selected_site=site_id
	ui.modal_kind="island_site"
	var body=ui.modal(s.name,"%s · %s"%[s.region,str(s.levelName).to_upper()],950,780)
	ui.paragraph(body,s.clue,18,ui.TEXT)
	ui.paragraph(body,"Approach: "+s.hazard,15,ui.GOLD)
	if s.level>=3:
		ui.label(body,"Survey findings",25,ui.GOLD,true)
		ui.paragraph(body,s.discovery,18,ui.TEXT)
		ui.paragraph(body,"Opportunity: "+str(s.resource)+". Knowledge identifies the site; production and recovery still require actual work and equipment.",15)
		if not str(s.leadId).is_empty():
			var lead: Dictionary=c.Exploration.catalog_site(c.state,s.leadId)
			if not lead.is_empty():ui.button(body,"Follow lead: "+str(lead.name),func():site(ui,lead.id))
	else:
		var action: String="chart" if s.level==1 else "survey"
		var q: Dictionary=c.Exploration.quote(c.state,site_id,action)
		ui.label(body,"Chart the approaches" if action=="chart" else "Land a resource survey",24,ui.GOLD,true)
		ui.paragraph(body,"%d spare crew · %.1f days · %.2f prepaid rations · %.0f kits\nThe payroll continues at %s coins/day for your existing crew."%[q.crewNeeded,q.days,q.food,q.supplies,ui.money(c.Economy.daily_upkeep(c.state.fleet).wages)],16)
		ui.paragraph(body,q.message,15,ui.TEAL if q.ok else ui.RED)
		if c.distance(c.state.position,s)<=180 and not c.state.path.is_empty():ui.button(body,"Idle engines at this landing",func():c.stop_sailing();site(ui,site_id))
		ui.button(body,"Assign shore party",func():ui.host.respond(c.begin_survey(site_id,action));site(ui,site_id),true).disabled=not q.ok or c.distance(c.state.position,s)>180 or not c.state.path.is_empty()
	var assignment: Dictionary=c.Exploration.assignment(c.state)
	if not assignment.is_empty():
		ui.paragraph(body,"Party progress %.1f / %.1f days. Recall the party before sailing."%[assignment.daysDone,assignment.daysTotal],16,ui.GOLD)
		ui.button(body,"Advance one survey day",func():survey_day(ui),true)
		ui.button(body,"Recall party",func():ui.host.respond(c.recall_survey());site(ui,site_id))
	else:
		ui.button(body,"Sail to landing",func():ui.host.respond(c.chart_course(s));ui.close_modal(),true)
	ui.button(body,"Island charts",func():islands(ui))

static func survey_day(ui) -> void:
	ui.host.sync_economy()
	ui.host.core.wait_day()
	ui.host.start_economy()
	ui.host.sync_economy()
	ui.host.save_game(false)
	islands(ui)
