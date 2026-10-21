extends RefCounted
const Identity=preload("res://scripts/fleet_identity.gd")
static func open(ui,uid: String) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	Identity.ensure(c.state)
	var boat: Dictionary=c.find_boat(uid)
	if boat.is_empty():return
	ui.modal_kind="fleet_identity"
	var body=ui.modal(boat.name+" · role & crew","A WORKING BOAT WITH ITS OWN HISTORY",1050,820)
	ui.paragraph(body,"Interior conversions trade hold space or handling for useful fleet roles. They keep your physical weapon sockets and fitted weapons. Specialists occupy real crew berths; base pay stays 100 coins per day, with the stated professional premium paid into their own purses.",16)
	ui.label(body,"Role: "+str(Identity.conversions().get(boat.get("conversion",""),{}).get("name","Original interior")),23,ui.GOLD,true)
	ui.button(body,"Support reserve" if not boat.get("supportOnly",false) else "Include in battle deployment",func():ui.host.respond(c.FleetSupport.reserve(c,uid));ui.host.save_game(false);open(ui,uid))
	for id in Identity.conversions():
		var key: String=id
		var q: Dictionary=Identity.quote_conversion(c,uid,key)
		ui.rule(body)
		ui.label(body,Identity.conversions()[key].name,22,ui.GOLD,true)
		ui.paragraph(body,Identity.conversions()[key].trade,15)
		ui.paragraph(body,str(q.get("message","")),14)
		ui.button(body,"Install conversion",func():ui.host.respond(Identity.install_conversion(c,uid,key));c.fit_boat(c.find_boat(uid));c.apply_morale();c.Manifest.allocate(c.state);ui.host.save_game(false);open(ui,uid),true).disabled=not q.ok
	ui.rule(body)
	for role in Identity.roles():
		var value: String=role
		var info: Dictionary=Identity.roles()[value]
		ui.button(body,"Hire %s · +%d coins/day"%[info.name,info.premium],func():ui.host.respond(Identity.hire_specialist(c,uid,value));c.apply_morale();c.Manifest.allocate(c.state);ui.host.save_game(false);open(ui,uid))
	for rec in c.FleetSupport.aboard(c,uid):
		var id: String=rec.id
		ui.paragraph(body,"%s · %s · purse %d · arrears %d · %s"%[rec.name,rec.role,rec.coins,rec.arrears,"working" if rec.active else "premium unpaid"],15,ui.TEAL)
		ui.button(body,"Discharge with savings",func():ui.host.respond(c.FleetSupport.dismiss(c,id));ui.host.save_game(false);open(ui,uid))
	ui.rule(body)
	ui.label(body,"Service history",23,ui.GOLD,true)
	for entry in boat.get("serviceHistory",[]):ui.paragraph(body,"Day%.1f · %s · %s"%[entry.day,entry.event,entry.get("detail","")],14)
