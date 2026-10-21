extends RefCounted
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
	for value in ["Work board","Contacts","Market notes"]:
		var selected: String=value
		ui.button(tabs,selected,func():open(ui,selected),selected==tab)
	if tab=="Contacts":contacts(ui,body);return
	if tab=="Market notes":intel(ui,body);return
	ui.paragraph(body,"Carry up to six compatible side jobs alongside your story contract. Freight uses real hold space; rewards are reserved in escrow. Relief cargo is purchased by its sponsoring treasury, then entrusted to your fleet.",16)
	ui.label(body,"%d / 6 commitments · Hold %.1f / %.1f"%[c.state.voyageJobs.size(),c.cargo_weight(),c.capacity()],22,ui.GOLD,true)
	for raw in c.state.voyageJobs:
		var job: Dictionary=raw.duplicate(true)
		ui.rule(body)
		ui.label(body,job.title,24,ui.GOLD,true)
		ui.paragraph(body,"%s · %.1f days remaining · %s coins reserved"%[str(job.state).capitalize(),job.deadlineDay-c.state.day,ui.money(job.escrow)],15,ui.TEAL)
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
		ui.button(body,"Accept funded job",func():ui.host.respond(c.accept_voyage_job(offer.id));ui.host.save_game(false);open(ui),true).disabled=c.state.voyageJobs.size()>=6
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
		ui.rule(body)
		ui.label(body,contact.name,25,ui.GOLD,true)
		ui.paragraph(body,"%s · %s"%[contact.title,c.port(contact.port).name],16,ui.TEXT)
		ui.paragraph(body,"Trust %d · %s"%[contact.trust,"last visited day%.1f"%contact.lastVisitDay if contact.met else "not yet met"],15,ui.TEAL)
		ui.button(body,"Chart this harbor",func():ui.host.sail_to(contact.port);ui.close_modal())
		for entry in contact.log.slice(-3):ui.paragraph(body,"Day%.0f · %s · trust %+d"%[entry.day,entry.event,entry.amount],13)

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
