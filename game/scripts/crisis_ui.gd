extends RefCounted
const Ops=preload("res://scripts/crisis_ops.gd")
static func result(ui,r: Dictionary) -> void:
	ui.host.respond(r)
	if r.ok:ui.host.save_game(false)
	open(ui)
static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core;Ops.ensure(c)
	var report: Dictionary=Ops.api(c).report(c)
	ui.modal_kind="regional_crises"
	var body=ui.modal("Regional crises & civilian passage","DATED EVIDENCE · EXISTING PEOPLE · FUNDED WORK",1160,880)
	ui.paragraph(body,"Three consecutive observed days of inadequate food, high unrest or unpaid recorded wages open a local crisis. Three adequate days close it. Relief uses existing goods and real pay. Optional civilian passage moves existing idle workers and their savings; it creates no people or boats.",16)
	var active: int=0
	for crisis in report.crises.values():
		if not crisis.active:continue
		active+=1
		ui.label(body,str(c.port(crisis.port).name)+" · "+str(crisis.kind).capitalize(),21,ui.GOLD,true)
		ui.paragraph(body,"Day %d · %s %s"%[int(crisis.seen),str(crisis.evidence),str(crisis.advice)],15)
	if active==0:ui.paragraph(body,"No sustained crisis is currently evidenced. Normal production, relief deliveries and paid work can prevent one.",16,ui.TEAL)
	ui.paragraph(body,"Live cohorts: %d people · %d aboard · %d coins reserved for work · %d people recorded lost"%[int(report.heldPeople),int(report.passengers),int(report.escrow),int(report.lostPeople)],16)
	for j in report.jobs:
		var id: String=str(j.id)
		var boat: Dictionary=c.find_boat(str(c.state.passengerTransport.carriers.get(id,"")))
		ui.label(body,"%s · %d people · %s"%[id,int(j.n),str(j.stage).capitalize()],21,ui.GOLD,true)
		ui.paragraph(body,"%s → %s · %s · %.2f ration bales · %d/%d observed transport days · %d/2 reception days. Household and specialist savings: %d coins."%[str(c.port(j.origin).name),str(c.port(j.destination).name),"Ashore in reception" if j.stage=="holding" else str(boat.get("name","Carrier unavailable")),float(j.food.get("food",0)),int(j.progress),int(j.days),int(j.served),int(j.householdPurse)+int(j.expertPurse)],15)
		var row=ui.row(body)
		ui.button(row,"Report arrival",func():result(ui,Ops.arrive(c,id)))
		ui.button(row,"Buy two days of provisions",func():result(ui,Ops.provision(c,id)))
		ui.button(row,"Recall physically",func():result(ui,Ops.recall(c,id)))
		ui.button(body,"Discharge at the actual origin",func():result(ui,Ops.home(c,id)))
	var p: Dictionary=c.current_port()
	if not p.is_empty():
		ui.rule(body)
		ui.label(body,str(p.name)+" reception capacity",22,ui.TEAL,true)
		ui.paragraph(body,"%d worker places available before incoming reservations. Town, academy, private staff and coastal watch commitments already occupy places. The standing ceiling uses the original settlement workforce plus one vacant worker place per 200 authored residents; it never grows on loading a save."%Ops.Transport.room(c,p),14)
		var offers: Array=Ops.api(c).offers(c).filter(func(offer):return offer.origin==p.id)
		if offers.is_empty():ui.paragraph(body,"No sponsored passage currently has verified need, solvent funding, provisions, a legal route, receiving places and usable boat berths.",15)
		for offer in offers:
			var destination: String=str(offer.destination)
			ui.paragraph(body,"To %s · up to %d existing workers · %d estimated transport days · sponsor reserves %d coins, including two paid reception days. Current provision bill %.0f coins."%[str(c.port(destination).name),int(offer.count),int(offer.days),int(offer.funded),float(offer.foodCost)],15)
			var row=ui.row(body);var number=SpinBox.new();number.min_value=1;number.max_value=int(offer.count);number.value=int(offer.count);row.add_child(number)
			ui.button(row,"Embark this real cohort",func():result(ui,Ops.begin(c,destination,int(number.value))))
	ui.paragraph(body,"Each cohort occupies one named boat's spare crew berths and carries its own purchased food. Actual sailing distance earns transport work; waiting or moving the map camera earns none. Two later, provisioned and staffed reception days precede workforce admission. Unused provisions enter public stores and unearned escrow returns to the sponsor. Carrier loss records people and goods once; their savings stay in a counted estate purse.",15,ui.MUTED)
	ui.button(body,"Close",ui.close_modal,true)
