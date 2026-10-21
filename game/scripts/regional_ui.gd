extends RefCounted
const R=preload("res://scripts/regional_campaigns.gd")
const Rules=preload("res://scripts/regional_rules.gd")
const Factions=preload("res://scripts/factions.gd")

static func port_picker(ui,parent,key: String,caption: String) -> void:
	var c=ui.host.core
	ui.label(parent,caption,15,ui.GOLD)
	var select=OptionButton.new()
	for p in c.state.ports:
		select.add_item(p.name);select.set_item_metadata(select.item_count-1,p.id)
		if str(c.state.campaignFocus.get(key,""))==str(p.id):select.select(select.item_count-1)
	parent.add_child(select)
	select.item_selected.connect(func(index):c.state.campaignFocus[key]=str(select.get_item_metadata(index));ui.host.save_game(false);open(ui))

static func faction_picker(ui,parent,key: String) -> void:
	var c=ui.host.core
	var select=OptionButton.new()
	for id in Factions.CANON:
		select.add_item(Factions.CANON_NAMES[id]);select.set_item_metadata(select.item_count-1,id)
		if c.state.campaignFocus.get(key,"")==id:select.select(select.item_count-1)
	parent.add_child(select)
	select.item_selected.connect(func(index):c.state.campaignFocus[key]=str(select.get_item_metadata(index));ui.host.save_game(false);open(ui))

static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	c.RegionalOps.ensure(c)
	ui.modal_kind="regional"
	var body=ui.modal("Your place on the coast","REGIONAL GOALS · REAL FLEETS · LASTING CONSEQUENCES",1100,850)
	ui.paragraph(body,"Choose a direction for your career. These goals use the coast's existing boats, purses and supplies. You may keep several goals alongside your contracts. Completed routes and harbors are remembered; choosing a new destination never rewrites an active operation.",16)
	var focus=ui.row(body)
	port_picker(ui,focus,"fromPort","Corridor from")
	port_picker(ui,focus,"toPort","To")
	port_picker(ui,focus,"portId","Develop harbor")
	var parties=ui.row(body)
	ui.label(parties,"Ceasefire parties",15,ui.GOLD)
	faction_picker(ui,parties,"peaceA");faction_picker(ui,parties,"peaceB")
	for value in R.available(c):
		var item: Dictionary=value
		var id: String=str(item.id)
		var op: Dictionary=c.state.regionalCampaigns.operations.get(id,{})
		ui.rule(body);ui.label(body,str(R.TITLES[id]),25,ui.GOLD,true)
		match id:
			"corridor":ui.paragraph(body,"Keep both approaches and their sea lane clear for seven consecutive economic days. Prove use through a real merchant passage, a local escort/victory, or two actual endpoint visits by the assigned patrol. Friendly standing can secure up to seven wage-days from the local treasury, preserving two public-payroll days. Recovery and paid resupply take priority.",15)
			"harbor":ui.paragraph(body,"At the selected harbor, contribute or sell at least twelve owned goods lots after starting. A shore business there must then pay three full daily payrolls. A warehouse, salvage yard or workshop qualifies; arrears pause its contribution. See Home harbors for actual construction, materials and operating capital.",15)
			"survey":ui.paragraph(body,"Fully survey three connected sites by following discovered leads. Already completed surveys count as an earned achievement. Charting alone does not qualify, and the goal never grants free survey supplies.",15)
			"ceasefire":ui.paragraph(body,"Carry five food or repair-kit lots to EACH selected faction. Earn Friendly standing with one party and access to both, with no witnessed offenses or claims. After both relief deliveries, allow three economic days for talks. Sign at either party's legal harbor. The truce lasts thirty days; the prior dispute can resume afterward. No forced commission or invented reward.",15)
		if op.get("status","")=="active":
			var place: String=c.port(str(op.get("portId",""))).get("name","the coast")
			if id=="corridor":place="%s ↔ %s"%[c.port(str(op.ends[0])).name,c.port(str(op.ends[1])).name]
			ui.paragraph(body,"Underway since day %d · %s"%[int(op.startedDay),place],16,ui.TEAL)
			if id=="corridor":
				var company: String=c.fleet_owner(str(op.get("ownerId",""))).get("name","your fleet / local commerce")
				ui.paragraph(body,"%d / 7 clear days · %d patrol endpoint visits · %s · %d coins treasury support"%[int(op.get("clearDays",0)),int(op.get("patrolVisits",0)),company,int(op.funded)],15)
			if id=="harbor":ui.paragraph(body,"%.0f / 12 goods lots · %d / 3 paid staff-days · %s"%[float(op.get("harborLots",0)),int(op.get("staffDays",0)),c.port(op.portId).name],15)
			if id=="ceasefire":
				var terms: Dictionary=Rules.peace_conditions(c.state,op,str(op.peaceA),str(op.peaceB))
				ui.paragraph(body,"%s: %d / 5 relief · %s: %d / 5 · talks began day %d"%[Factions.CANON_NAMES[op.peaceA],int(op.relief.get(op.peaceA,0)),Factions.CANON_NAMES[op.peaceB],int(op.relief.get(op.peaceB,0)),int(op.get("talksStartedDay",0))],15)
				ui.paragraph(body,str(terms.reason),15,ui.TEAL)
				ui.button(body,"Sign thirty-day ceasefire",func():act(ui,R.propose_peace(c,str(op.peaceA),str(op.peaceB))),true)
			if id in ["harbor","ceasefire"]:
				var supply=ui.row(body)
				var goods=OptionButton.new()
				for g in R.ACCEPT[id]:goods.add_item(c.Goods.ITEMS[g].name);goods.set_item_metadata(goods.item_count-1,g)
				supply.add_child(goods)
				var qty=SpinBox.new();qty.min_value=1;qty.max_value=100;qty.step=1;qty.value=1;supply.add_child(qty)
				ui.button(supply,"Deliver owned cargo · no payment",func():act(ui,c.RegionalOps.contribute(c,id,str(goods.get_item_metadata(goods.selected)),int(qty.value))))
			ui.button(body,"Withdraw goal · delivered goods and grants stay paid",func():act(ui,R.cancel(c,id)))
		else:
			ui.paragraph(body,str(item.reason),15)
			ui.button(body,"Choose this goal",func():act(ui,c.RegionalOps.start(c,id)),true).disabled=not item.ready
	ui.rule(body);ui.label(body,"Treaties and accomplishments",24,ui.GOLD,true)
	for rec in c.state.regionalCampaigns.peace.values():
		ui.paragraph(body,"%s ↔ %s · %s · expires day %d · new talks after day %d"%[Factions.CANON_NAMES[rec.a],Factions.CANON_NAMES[rec.b],"in force" if rec.get("active",true) else "ended",int(rec.untilDay),int(rec.cooldownUntil)],15)
	for e in R.journal(c.state).slice(0,12):ui.paragraph(body,"Day %d · %s"%[int(e.get("day",0)),event_text(c,e)],14)

static func event_text(c,e: Dictionary) -> String:
	var title: String=str(R.TITLES.get(e.get("goal",""),"Regional activity"))
	match str(e.get("kind","")):
		"complete":return title+" · achieved"
		"withdrawn":return title+" · withdrawn"
		"contribute":return "%d %s delivered to %s"%[int(e.qty),c.Goods.ITEMS[e.good].name,c.port(e.portId).name]
		"mobilize":return "%s assigned %d coins to %s"%[c.port(e.funder).name,int(e.amount),c.fleet_owner(e.target).get("name","its patrol")]
		"treaty-expired":return "Ceasefire ended · "+("previous dispute resumes" if e.cause=="prior-dispute-restored" else "later agreement remains in force")
		"peace":return "Thirty-day ceasefire signed"
	return title+" · "+str(e.get("kind",""))

static func act(ui,result: Dictionary) -> void:
	ui.host.respond(result);ui.host.save_game(false);open(ui)
