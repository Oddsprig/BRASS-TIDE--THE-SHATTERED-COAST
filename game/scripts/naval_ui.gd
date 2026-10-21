extends RefCounted
static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	ui.modal_kind="sea_traffic"
	var body=ui.modal("Coastal traffic","OBSERVED FLEETS WITH ACTUAL BUSINESS",1040,800)
	ui.paragraph(body,"Nearby convoys carry paid cargo; patrols intercept or escort; raiders seek prizes. These owners spend stores and wages, suffer damage and buy replacements from real yards. Distant fleets are outside your current watch.",16)
	for p in c.state.patrols:
		if not p.active or c.distance(c.state.position,p)>1800:continue
		var owner: Dictionary=c.fleet_owner(p.id)
		if owner.is_empty():continue
		var order: Dictionary=owner.get("order",{})
		ui.rule(body)
		ui.label(body,"%s · %s"%[owner.name,str(order.get("purpose",owner.kind)).capitalize()],23,ui.GOLD,true)
		ui.paragraph(body,str(order.get("reason","Sailing a coastal route.")),16)
		ui.paragraph(body,"%s · %d visible hulls · %s"%[c.faction(owner.faction).name,owner.boats.filter(func(b):return not b.sunk).size(),"holding in harbor" if p.get("holding",false) else "under way"],14)
		ui.button(body,"Hail this fleet",func():ui.host.show_patrol_encounter(p.id))
	ui.rule(body)
	ui.paragraph(body,"Your captain's log records witnessed outcomes. Full economic ledgers remain available in developer tools.",14)
