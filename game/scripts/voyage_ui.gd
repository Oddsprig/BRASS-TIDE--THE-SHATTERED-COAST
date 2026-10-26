extends RefCounted
const Transport=preload("res://scripts/passenger_transport.gd")
## Several funded commitments, original contacts and honest dated reports.
static func open(ui,tab: String="Work board") -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	c.VoyageJobs.ensure(c)
	c.VoyageJobs._expire_overdue(c,c.state)
	ui.modal_kind="voyage_jobs"
	var body=ui.modal("Voyage jobs & contacts","PLAN A ROUTE WITH SEVERAL REASONS TO SAIL",1040,820)
	ui.button(body,"Coastal stories & leads",func():ui.StoryUI.open(ui))
	ui.button(body,"Trade chart & observed prices",func():ui.TradeUI.open(ui))
	ui.button(body,"Coastal traffic",func():ui.NavalUI.open(ui))
	ui.button(body,"Factions & safe passage",func():ui.FactionUI.open(ui))
	var tabs=ui.row(body)
	for value in ["Work board","Fishing","Contacts","Market notes"]:
		var selected: String=value
		ui.button(tabs,selected,func():open(ui,selected),selected==tab)
	if tab=="Contacts":contacts(ui,body);return
	if tab=="Fishing":fishing(ui,body);return
	if tab=="Market notes":intel(ui,body);return
	ui.paragraph(body,"Carry up to six compatible side jobs alongside your story contract. Freight uses real hold space; rewards are reserved in escrow. Relief cargo is purchased by its sponsoring treasury, then entrusted to your fleet.",16)
	ui.label(body,"%d / 6 commitments · Hold %.1f / %.1f"%[c.state.voyageJobs.size(),c.cargo_weight(),c.capacity()],22,ui.GOLD,true)
	for raw in c.state.voyageJobs:
		var job: Dictionary=raw.duplicate(true)
		ui.rule(body)
		ui.label(body,job.title,24,ui.GOLD,true)
		ui.paragraph(body,"%s · %.1f days remaining · %s coins reserved"%[str(job.state).capitalize(),job.deadlineDay-c.state.day,ui.money(job.escrow)],15,ui.TEAL)
		if not str(job.get("carrierUid","")).is_empty():
			var boat: Dictionary=c.find_boat(str(job.carrierUid))
			ui.paragraph(body,"Carrier: %s · %s"%[str(boat.get("name","Carrier unavailable")),str(job.carrierUid)],15,ui.GOLD)
		if not job.get("freight",{}).is_empty():ui.paragraph(body,"Sealed cargo: %.0f %s"%[float(job.freight.qty),str(c.Goods.ITEMS.get(job.freight.good,{}).get("name",job.freight.good))],15)
		if job.kind=="passenger_charter":ui.paragraph(body,"%d passengers aboard · %.2f ration bales reserved"%[int(job.get("passengers",{}).get("n",0)),float(job.get("charterFood",{}).get("food",0))],15)
		if job.get("failed",false):ui.paragraph(body,"Freight lost: this job needs to be closed at a harbor.",15,ui.RED)
		var target: Dictionary=c.port(job.targetPort)
		if job.kind=="survey":
			var s: Dictionary=c.Exploration.catalog_site(c.state,job.siteId)
			var progress: int=int(c.state.exploration.sites.get(job.siteId,{}).get("level",0))
			if progress<3:target=s
		ui.button(body,"Chart next destination",func():ui.host.respond(c.chart_course(target,str(target.get("id","")) if c.port(str(target.get("id",""))).size()>0 else ""));ui.close_modal())
		ui.button(body,"Complete & release escrow",func():settle(ui,job.id,false),true)
		ui.button(body,"Abandon / unload remaining freight",func():settle(ui,job.id,true))
	ui.rule(body)
	ui.label(body,"Available at this harbor",25,ui.GOLD,true)
	var offers: Array=c.VoyageJobs.available(c)
	if offers.is_empty():ui.paragraph(body,"Enter a harbor for funded work. Offers need an actual sponsor purse and physical cargo; completed jobs do not reroll.",16)
	for item in offers:
		var offer: Dictionary=item.duplicate(true)
		ui.label(body,offer.title,23,ui.TEXT,true)
		ui.paragraph(body,offer.description,15)
		ui.paragraph(body,"%s coins · deadline day%.0f"%[ui.money(offer.reward),offer.deadlineDay],15,ui.GOLD)
		var picker: OptionButton=null
		if offer.kind in ["fuel_delivery","passenger_charter"]:picker=carrier_picker(ui,body,str(offer.kind))
		ui.button(body,"Accept funded job",func():ui.host.respond(c.accept_voyage_job(offer.id,str(picker.get_selected_metadata()) if picker!=null and picker.item_count>0 else ""));ui.host.save_game(false);open(ui),true).disabled=c.state.voyageJobs.size()>=6 or (picker!=null and picker.item_count==0)
		ui.rule(body)
	ui.button(body,"Story contracts & captain's log",ui.open_contracts)

static func settle(ui,id: String,abandon: bool) -> void:
	ui.host.respond(ui.host.core.settle_voyage_job(id,abandon))
	ui.host.save_game(false)
	open(ui)

static func contacts(ui,body) -> void:
	var c=ui.host.core
	ui.paragraph(body,"Personal trust belongs to the person you helped. Visits, fulfilled promises and failures are remembered. Faction standing is a separate relationship.",16)
	for person in c.Contacts.list_contacts(c.state):
		var contact: Dictionary=person
		if contact.has("ownerId") and not contact.met:continue
		ui.rule(body)
		ui.label(body,contact.name,25,ui.GOLD,true)
		ui.paragraph(body,"%s · %s"%[contact.title,c.port(contact.port).name],16,ui.TEXT)
		ui.paragraph(body,"Trust %d · %s"%[contact.trust,"last visited day%.1f"%contact.lastVisitDay if contact.met else "not yet met"],15,ui.TEAL)
		ui.button(body,"Chart this harbor",func():ui.host.sail_to(contact.port);ui.close_modal())
		for entry in contact.log.slice(-3):ui.paragraph(body,"Day%.0f · %s · trust %+d"%[entry.day,entry.get("detail",entry.event),entry.amount],13)

static func carrier_picker(ui,body,kind: String) -> OptionButton:
	var c=ui.host.core
	ui.paragraph(body,"Choose the actual carrier. Existing crew, captives, passengers, working stores and sealed cargo occupy its space.",14)
	var picker=OptionButton.new()
	picker.custom_minimum_size=Vector2(0,42)
	for b in c.active_fleet():
		if kind=="fuel_delivery" and str(b.spec.get("civilianRole","")) not in ["transport","tanker"]:continue
		if kind=="passenger_charter" and str(b.spec.get("civilianRole","")) not in ["transport","yacht"]:continue
		if kind=="fishing" and str(b.spec.get("civilianRole",""))!="fishing":continue
		picker.add_item("%s · %s · %s"%[b.name,str(b.spec.get("civilianRole",b.spec.role)),str(b.uid)])
		picker.set_item_metadata(picker.item_count-1,str(b.uid))
	body.add_child(picker)
	var details=ui.paragraph(body,"",14,ui.TEAL)
	var describe: Callable=func(_index: int):
		if picker.item_count==0:return
		var b: Dictionary=c.find_boat(str(picker.get_selected_metadata()))
		details.text="Crew %.0f / %.0f · %.1f free hold · %d spare berths · %.1f working fuel"%[float(b.crew),float(b.crewOptimal),Transport.available_hold(c,b),Transport.spare(c,b),float(b.fuel)]
	picker.item_selected.connect(describe)
	describe.call(0)
	if picker.item_count==0:ui.paragraph(body,"No eligible active, crewed carrier. Prepare a suitable boat through Fleet and the harbor yard.",15,ui.GOLD)
	return picker

static func fishing(ui,body) -> void:
	var c=ui.host.core
	ui.paragraph(body,"Fishing boats catch and preserve fish aboard while campaign time runs at sea. Assign real sailors and carry fuel, rations and free hold space. Dockside waiting earns no catch. Sell the catch through the harbor market for coins from its actual buyers.",16)
	for work in c.CivilianWork.fishing_status(c):
		var uid: String=str(work.boatUid)
		var boat: Dictionary=c.find_boat(uid)
		ui.label(body,str(boat.get("name",uid))+" · fishing",22,ui.GOLD,true)
		ui.paragraph(body,"%d assigned sailors · %.2f / %.2f working days · %.2f fish lots caught"%[int(work.crew),float(work.daysDone),float(work.daysTotal),float(work.catch)],15)
		ui.button(body,"Recall this fishing crew",func():ui.host.respond(c.cancel_fishing(uid));ui.host.save_game(false);open(ui,"Fishing"))
	ui.rule(body)
	var picker: OptionButton=carrier_picker(ui,body,"fishing")
	var options=ui.row(body)
	ui.label(options,"Working days",14)
	var days=SpinBox.new();days.min_value=0.25;days.max_value=3.0;days.step=0.25;days.value=1.0;options.add_child(days)
	ui.label(options,"Assigned sailors",14)
	var crew=SpinBox.new();crew.min_value=1;crew.max_value=1;crew.value=1;options.add_child(crew)
	var update: Callable=func(_index: int):
		if picker.item_count==0:return
		var boat: Dictionary=c.find_boat(str(picker.get_selected_metadata()))
		crew.max_value=maxi(1,floori(float(boat.get("crew",0))-float(boat.get("wounded",0))))
		crew.value=crew.max_value
	picker.item_selected.connect(update)
	update.call(0)
	var launch: Callable=func():
		var result: Dictionary=c.start_fishing(str(picker.get_selected_metadata()),float(days.value),int(crew.value))
		ui.host.respond(result)
		if result.ok:ui.host.save_game(false);ui.close_modal()
		else:open(ui,"Fishing")
	ui.button(body,"Begin fishing and return to sea",launch,true).disabled=picker.item_count==0
	ui.button(body,"Return to the chart",ui.close_modal)

static func intel(ui,body) -> void:
	var c=ui.host.core
	ui.paragraph(body,"These are observations from your actual harbor visits. Remote reports age; they do not guarantee current stock, prices or a buyer's funds.",16)
	for id in c.state.get("marketSnapshots",{}):
		var snap: Dictionary=c.state.marketSnapshots[id]
		ui.rule(body)
		ui.label(body,"%s · %.1f days old"%[c.port(id).name,maxf(0,c.state.day-snap.day)],23,ui.GOLD,true)
		ui.paragraph(body,"Observed business purse: %s coins"%ui.money(snap.cash),15)
		for good in ["food","timber","iron","fuel","supplies"]:ui.paragraph(body,"%s · %.1f observed lots"%[c.Goods.ITEMS[good].name,snap.stocks.get(good,0)],14)
	if c.state.get("marketSnapshots",{}).is_empty():ui.paragraph(body,"Visit a harbor and enter its market to record your first observations.",17)
