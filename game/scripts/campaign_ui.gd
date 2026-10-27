extends RefCounted
const Routes=preload("res://scripts/route_cache.gd")
## Focused campaign windows; main-thread UI only.

static func expedition(ui) -> void:
	ui.host.sync_economy()
	ui.modal_kind="expedition"
	var body=ui.modal("Prepare an expedition","HOLDS · ENDURANCE · RETURN RESERVES",980,780)
	var c=ui.host.core
	var destination: Dictionary=c.port(ui.host.selected_port)
	var route: Array=[]
	var length: float=0.0
	if not destination.is_empty():
		route=Routes.path(c,c.state.position,destination)
		for i in range(1,route.size()):length+=c.distance(route[i-1],route[i])
	var r: Dictionary=c.expedition_report(length)
	ui.label(body,"%d traveling boats · %d owned · %d crew"%[c.active_fleet().size(),c.state.fleet.size(),r.crew],25,ui.GOLD,true)
	ui.paragraph(body,"Working tanks, magazines and kit racks are separate fitted storage. Loose reserves, goods and sealed freight occupy the traveling holds. Stored or inactive hulls provide no expedition capacity.",15)
	ui.label(body,"Holds %.1f / %.1f · %.1f free"%[r.cargoWeight,r.usableCapacity,maxf(0,r.freeCapacity)],20,ui.TEAL)
	ui.paragraph(body,"Daily payroll: %s coins\nFood: %.1f days · Fuel under way: %.1f days\nCaptain can fund %.1f payroll days · %.1f repair kits aboard"%[ui.money(r.dailyWages),r.foodDays,r.fuelDays,r.affordableDays,r.repairKits],18,ui.TEXT)
	if not destination.is_empty():
		ui.rule(body)
		ui.label(body,"Selected destination: "+str(destination.name),22,ui.GOLD,true)
		ui.paragraph(body,"Water route: %.0f · Round trip estimate: %.2f game days\nReturn payroll allowance: %s coins · Recommended contingency: %.1f days"%[length,r.tripDays,ui.money(r.returnWages),r.reserveDays],16)
		ui.paragraph(body,"Travel estimates use the slowest seaworthy boat and the safe water route. Stops, fighting, surveying and towing add time. Food and wages continue while at sea.",14)
		ui.button(body,"Chart course to "+str(destination.name),func():ui.host.sail_to(destination.id);ui.close_modal(),true).disabled=route.is_empty() or r.overload>0
	for warning in r.warnings:ui.paragraph(body,str(warning),15,ui.RED)
	ui.rule(body)
	ui.button(body,"Cargo, stores & accounts",ui.open_cargo)
	ui.button(body,"Manage traveling boats and stored reserves",ui.open_fleet)

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
