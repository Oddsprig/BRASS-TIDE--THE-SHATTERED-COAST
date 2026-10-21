extends RefCounted
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
		route=c.Navigation.find_path(c.nav,c.state.position,destination)
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
	ui.paragraph(body,"Processor: %s · %d logical threads\nHarbor production: up to %d copied-state workers · Separate rendering enabled"%[OS.get_processor_name(),OS.get_processor_count(),clampi(OS.get_processor_count()-2,1,8)],14,ui.TEAL)
