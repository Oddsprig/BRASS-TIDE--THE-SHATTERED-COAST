extends RefCounted
## Read-only local harbor preview; sailing rechecks the real navigation rules.
const Routes=preload("res://scripts/route_cache.gd")
const Expedition=preload("res://scripts/expedition.gd")

static func quote(c,port_id: String) -> Dictionary:
	if not c.home_local064():return {}
	var destination: Dictionary=c.port(port_id)
	if destination.is_empty() or str(destination.get("regionId","shatter_coast"))!="shatter_coast":return {}
	var path: Array=Routes.path(c,c.state.position,destination)
	var distance: float=0.0
	for i in range(1,path.size()):distance+=c.distance(path[i-1],path[i])
	var endurance: Dictionary=Expedition.report(c.state,c.data,distance)
	return {"destination":destination.duplicate(true),"routeAvailable":not path.is_empty(),
		"distance":distance,"endurance":endurance}

static func open(ui,port_id: String) -> void:
	var c=ui.host.core
	var q: Dictionary=quote(c,port_id)
	if q.is_empty():ui.toast("Choose a harbor on this local chart.",true);return
	ui.modal_kind="harbor_route104"
	var body=ui.modal(str(q.destination.name),"HARBOR ROUTE",780,620)
	var e: Dictionary=q.endurance
	if q.routeAvailable:
		ui.label(body,"%.2f sailing days Â· %.0f chart units"%[float(e.outwardDays),float(q.distance)],23,ui.TEXT,true)
		ui.paragraph(body,"Return allowance: %.2f days, including %.0f contingency days."%[float(e.tripDays),float(e.reserveDays)],16)
		ui.paragraph(body,"Reserve %s coins for crew wages. Food aboard: %.1f days. Loaded fuel: %.1f days."%[ui.money(e.returnWages),float(e.foodDays),float(e.fuelDays)],16)
		for warning in e.warnings:ui.paragraph(body,str(warning),14,ui.GOLD)
		ui.button(body,"Set course",func():ui.host.sail_to(port_id);ui.close_modal(),true,false).disabled=int(e.travelingCount)==0
	else:
		ui.paragraph(body,"No safe water route for this fleet's hull clearance.",17,ui.RED)
	ui.button(body,"Hold & boat reserves",ui.open_cargo,false,false)
	ui.button(body,"Cancel",ui.close_modal,false,false)
