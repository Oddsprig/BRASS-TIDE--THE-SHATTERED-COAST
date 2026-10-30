extends RefCounted
const R=preload("res://scripts/regional_campaigns.gd")
const Rules=preload("res://scripts/regional_rules.gd")
const Factions=preload("res://scripts/factions.gd")
const Orders=preload("res://scripts/naval_orders.gd")
const Ops=preload("res://scripts/regional_ops.gd")
const Costs=preload("res://scripts/career_costs.gd")
const Trade=preload("res://scripts/trade_intel.gd")
const Politics=preload("res://scripts/politics.gd")
const LawOps=preload("res://scripts/law_ops.gd")
const Home=preload("res://scripts/home_harbor.gd")
const HomeUI=preload("res://scripts/home_ui.gd")
const Goods=preload("res://scripts/goods.gd")

class ReviewView extends Costs.QuoteView:
	func fail(message: String) -> Dictionary:return {"ok":false,"message":message}
	func ok(message: String) -> Dictionary:return {"ok":true,"message":message}
	func log_entry(_message: String) -> void:pass

## One copied account and shared immutable nav; no live ensure or publication.
static func review(c,selected_goal: String="corridor") -> Dictionary:
	var v=ReviewView.new(c)
	Ops.ensure(v)
	var territory_port_id: String=str(v.state.get("campaignFocus",{}).get("portId",""))
	var territory_port: Dictionary=v.port(territory_port_id)
	var territory_view: Dictionary=Ops.territory_view(v,territory_port_id)
	var territory_quote: Dictionary=Ops.territory_quote(v,territory_port_id)
	var goal: String=selected_goal if selected_goal in R.GOALS else "corridor"
	var op: Dictionary=Ops.selected_status(v,goal)
	var ids: Array=op.get("ends",[]).duplicate()
	if ids.is_empty():ids=[str(op.get("portId",v.state.campaignFocus.get("portId","")))]
	if goal=="corridor" and op.is_empty():ids=[str(v.state.campaignFocus.fromPort),str(v.state.campaignFocus.toPort)]
	var ports: Array=[]
	for id in ids:
		var p: Dictionary=v.port(str(id))
		if not p.is_empty():ports.append({"id":str(id),"name":str(p.name),"report":Trade.report(v,str(id))})
	var traffic: Array=[]
	var visible: Array=[]
	for contact in Orders.sightings(v.state,"player"):
		var relevant: bool=Rules.near_corridor(v.state,{"ends":ids},Vector2(float(contact.x),float(contact.y))) if ids.size()==2 else (not ports.is_empty() and v.distance(contact,v.port(str(ports[0].id)))<=300.0)
		if not relevant:continue
		traffic.append(contact)
		if bool(contact.current):visible.append(str(contact.ownerId))
	var here: Dictionary=v.current_port()
	var safety: String="Local safety unobserved here; recorded contacts expire. No remote clearance is promised."
	if str(here.get("id","")) in ids and v.state.path.is_empty():
		var observed: Dictionary=v.state.duplicate(false)
		observed.fleetOwners=v.state.fleetOwners.filter(func(owner):return str(owner.id) in visible)
		var blocked: bool=str(here.id) in Trade.blockades(observed)
		safety="Day %.2f local sightings at %s: %s. Unseen fleets and later arrivals can change this."%[float(v.state.day),str(here.name),"supported blockade pressure observed" if blocked else "no supported blockade in current contacts"]
	var sponsor: Dictionary=v.port(str(op.get("portId",ids[0] if not ids.is_empty() else "")))
	var permission: Dictionary=Politics.access(v,sponsor) if not sponsor.is_empty() else {}
	# Limit the existing estimator to the selected goal's dated endpoints.
	var observations: Dictionary=v.state.get("tradeIntel",{}).get("observations",{})
	for id in observations.keys():
		if not str(id) in ids:observations.erase(id)
	var opportunity: Dictionary={}
	var all_owners: Array=v.state.fleetOwners
	v.state.fleetOwners=all_owners.filter(func(owner):return str(owner.id) in visible)
	# Filter the cloned sell quotes BEFORE ranking, so a restricted best cargo
	# cannot hide a legal civilian opportunity at the same visited sponsor.
	var origin_access: Dictionary=Politics.access(v,here) if not here.is_empty() else {}
	for id in observations.keys():
		var destination: Dictionary=v.port(str(id))
		var access: Dictionary=Politics.access(v,destination)
		if destination.get("faction","")!=sponsor.get("faction","") or not access.legal:
			observations.erase(id);continue
		for good in observations[id].get("sell",{}).keys():
			var allowed: bool=not str(good) in access.get("restrictedGoods",[]) and LawOps.allow_player(v,destination,str(good))
			if not here.is_empty():allowed=allowed and origin_access.legal and not str(good) in origin_access.get("restrictedGoods",[]) and LawOps.allow_player(v,here,str(good))
			if not allowed:observations[id].sell[good]=0
	if not sponsor.is_empty():
		for offer in Trade.opportunities(v):
			var destination: Dictionary=v.port(str(offer.toPort))
			if destination.get("faction","")!=sponsor.get("faction",""):continue
			var access: Dictionary=Politics.access(v,destination)
			if not access.legal or str(offer.good) in access.get("restrictedGoods",[]):continue
			if not LawOps.allow_player(v,destination,str(offer.good)):continue
			if not here.is_empty():
				if not origin_access.legal or str(offer.good) in origin_access.get("restrictedGoods",[]) or not LawOps.allow_player(v,here,str(offer.good)):continue
			opportunity=offer.duplicate(true);break
	v.state.fleetOwners=all_owners
	var businesses: Array=[]
	for business in v.state.get("businesses",[]):
		if str(business.get("homePort",""))==str(sponsor.get("id","")):businesses.append(Home.business_view(v.state,str(business.id)))
	return {"view":v,"goal":goal,"operation":op,"harbor":Rules.harbor_view(v.state,op),"available":R.available(v),"ports":ports,"traffic":traffic,"safety":safety,"sponsor":sponsor,"permission":permission,"opportunity":opportunity,"businesses":businesses,"journal":R.journal(v.state),"pendingDays":int(c.pending_days),"publishedDay":int(c.state.get("econDay",1)),"territoryPort":territory_port,"territoryView":territory_view,"territoryQuote":territory_quote}

static func consequences(ui,body: Node,a: Dictionary) -> void:
	var c=a.view
	ui.button(body,"Review home harbor books",func():HomeUI.open(ui),false,false)
	if a.businesses.is_empty():ui.paragraph(body,"No owned shore business at this sponsor. Construction, staff and capital remain optional and paid.",15)
	for business in a.businesses:
		var books=ui.column(body)
		books.name="RegionalBusiness_"+str(business.id)
		books.add_theme_constant_override("separation",8)
		ui.rule(books)
		ui.label(books,str(business.name),20,ui.GOLD,true)
		HomeUI.book(ui,books,business)
		HomeUI.book_details(ui,books,business)
	var observations=_details(ui,body,"Local sightings & visited market quotes")
	observations.name="LocalObservations"
	ui.paragraph(observations,str(a.safety),15)
	if a.traffic.is_empty():ui.paragraph(observations,"Traffic: no local contact on record for this goal. Sail nearby to observe it.",15)
	for contact in a.traffic.slice(0,6):
		ui.paragraph(observations,"%s · %s · %s → %s · sighted day %.2f (%.2f days old, %s)"%[str(contact.name),"loaded merchant" if contact.loaded else str(contact.kind),str(contact.purpose),c.port(str(contact.destination)).get("name","unconfirmed destination"),float(contact.day),float(contact.ageDays),"current" if contact.current else "expired" if contact.expired else "remembered"],15)
	for endpoint in a.ports:
		var report: Dictionary=endpoint.report
		ui.label(observations,str(endpoint.name)+" · visited stock",18,ui.GOLD)
		if not report.seen:
			ui.paragraph(observations,str(report.message),15);continue
		ui.paragraph(observations,str(report.message)+" Buyer purse at visit: %d coins."%int(report.businessFunds),15)
		for good in ["food","timber","fuel","supplies"]:
			var need: Dictionary=report.get("needs",{}).get(good,{})
			ui.paragraph(observations,"%s: %d lots · buy %d / sell %d · recorded need %.1f"%[Goods.ITEMS[good].name,int(report.stocks.get(good,0)),int(report.buy.get(good,0)),int(report.sell.get(good,0)),float(need.get("observedNeed",0))],15)
	var trade=_details(ui,body,"Sponsor access & dated trade estimate")
	trade.name="SponsorTrade"
	if not a.sponsor.is_empty():
		ui.paragraph(trade,"Sponsor: %s · %s"%[str(a.sponsor.name),str(Factions.CANON_NAMES.get(a.sponsor.get("faction",""),"unidentified colors"))],17,ui.GOLD)
		ui.paragraph(trade,str(a.permission.get("reason","No current legal access recorded.")),15)
	var offer: Dictionary=a.opportunity
	if offer.is_empty():
		ui.paragraph(trade,"No legal sponsor trade estimate from these visited endpoints and your current cargo/hold. Visit the sponsor and a second market to record quotes; access and stock are checked again when trading.",15)
	else:
		ui.paragraph(trade,"Existing legal trade estimate: %d %s → %s · nominal round-trip net %d coins · buyer limit %d lots"%[int(offer.qty),Goods.ITEMS[str(offer.good)].name,c.port(str(offer.toPort)).name,int(offer.netProfit),int(offer.buyerLiquidity)],18,ui.GOLD)
		ui.paragraph(trade,"Visit day %d · age %d days · purchase %d + estimated wages/stores/return %d. %s. Unseen blockade pressure is unassessed; quotes reserve nothing and are not realized profit."%[int(offer.observedDay),int(offer.quoteAge),int(offer.purchaseCost),int(offer.tripCost),"Observed preparation allowance covered" if offer.preparationReady else "Preparation or funding still needed"],15)

static func _details(ui,body: Node,caption: String) -> VBoxContainer:
	var details=ui.column(body)
	details.add_theme_constant_override("separation",6)
	details.visible=false
	var toggle=ui.button(body,caption,func():details.visible=not details.visible,false,false)
	toggle.toggle_mode=true
	body.move_child(toggle,details.get_index())
	return details

static func focus_controls(ui,body: Node,c,selected_goal: String) -> void:
	var focus=ui.row(body)
	port_picker(ui,focus,c,"fromPort","Corridor from",selected_goal)
	port_picker(ui,focus,c,"toPort","To",selected_goal)
	port_picker(ui,focus,c,"portId","Develop harbor",selected_goal)
	var parties=ui.row(body)
	ui.label(parties,"Ceasefire parties",15,ui.GOLD)
	faction_picker(ui,parties,c,"peaceA",selected_goal);faction_picker(ui,parties,c,"peaceB",selected_goal)

static func port_picker(ui,parent,c,key: String,caption: String,selected_goal: String) -> void:
	ui.label(parent,caption,15,ui.GOLD)
	var select=OptionButton.new()
	for p in c.state.ports:
		select.add_item(p.name);select.set_item_metadata(select.item_count-1,p.id)
		if str(c.state.campaignFocus.get(key,""))==str(p.id):select.select(select.item_count-1)
	parent.add_child(select)
	select.item_selected.connect(func(index):act(ui,"focus",key,str(select.get_item_metadata(index)),0,selected_goal))

static func faction_picker(ui,parent,c,key: String,selected_goal: String) -> void:
	var select=OptionButton.new()
	for id in Factions.CANON:
		select.add_item(Factions.CANON_NAMES[id]);select.set_item_metadata(select.item_count-1,id)
		if c.state.campaignFocus.get(key,"")==id:select.select(select.item_count-1)
	parent.add_child(select)
	select.item_selected.connect(func(index):act(ui,"focus",key,str(select.get_item_metadata(index)),0,selected_goal))

static func open(ui,selected_goal: String="corridor") -> void:
	var account: Dictionary=review(ui.host.core,selected_goal)
	var c=account.view
	selected_goal=str(account.goal)
	ui.modal_kind="regional"
	var body=ui.modal("Your place on the coast","REGIONAL GOALS · REAL FLEETS · LASTING CONSEQUENCES",1100,850)
	body.name="RegionalBody"
	body.add_theme_constant_override("separation",10)
	var heading=ui.row(body)
	ui.label(heading,"Captain's purse · %s coins"%ui.money(int(c.state.coins)),20,ui.GOLD).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	ui.button(heading,"Decline / return to chart",ui.close_modal,false,false)
	ui.paragraph(body,"Published day %d · %d calendar days pending · review/close pays nothing; actions refresh and recheck the account."%[int(account.publishedDay),int(account.pendingDays)],14)
	var tabs=ui.row(body)
	for value in R.GOALS:
		var goal: String=str(value)
		ui.button(tabs,str(R.TITLES[goal]),func():open(ui,goal),goal==selected_goal,false)
	if selected_goal=="harbor":territory_panel(ui,body,account)
	var primary=ui.column(body)
	primary.name="RegionalPrimary"
	primary.add_theme_constant_override("separation",6)
	for value in account.available:
		var item: Dictionary=value
		var id: String=str(item.id)
		if id!=selected_goal:continue
		var op: Dictionary=account.operation
		ui.label(primary,str(R.TITLES[id]),23,ui.GOLD,true)
		if not op.is_empty():ui.paragraph(primary,"Achievement: %s · recorded progress day %d · completed titles provide no permanent safety or free labor."%["achieved" if op.get("completed",false) else "underway" if op.get("status","")=="active" else "withdrawn",int(op.get("progressDay",op.get("startedDay",0)))],14,ui.TEAL)
		if id=="harbor" and not account.harbor.is_empty():
			var harbor: Dictionary=account.harbor
			ui.paragraph(primary,"%.0f sold/settled + %.0f unpaid donations = %.0f / %d lots · %d / %d actual paid working days"%[float(harbor.deliveredLots),float(harbor.donatedLots),float(harbor.harborLots),int(harbor.lotsRequired),int(harbor.staffDays),int(harbor.staffDaysRequired)],18,ui.TEAL)
			var business: Dictionary=harbor.business
			if not business.is_empty():ui.paragraph(primary,"Business purse %s · daily pay %d · unpaid wages %d coins"%[ui.money(int(business.coins)),int(business.dailyWages),int(business.arrears)],18,ui.TEXT)
			if not str(harbor.stallReason).is_empty():ui.paragraph(primary,"Stalled: "+str(harbor.stallReason),16,ui.RED)
			if not str(harbor.resumeReason).is_empty():ui.paragraph(primary,"Next: "+str(harbor.resumeReason),15,ui.TEXT)
			if not harbor.historyKnown:ui.paragraph(primary,"Earlier work history is unproved; only recorded paid days after the new baseline count.",14)
		if op.get("status","")=="active" or (id=="corridor" and not op.is_empty()):
			var place: String=c.port(str(op.get("portId",""))).get("name","the coast")
			if id=="corridor":place="%s ↔ %s"%[c.port(str(op.ends[0])).name,c.port(str(op.ends[1])).name]
			ui.paragraph(primary,"Started day %d · %s · %s"%[int(op.startedDay),place,"achievement retained" if op.get("completed",false) else str(op.get("status","underway"))],16,ui.TEAL)
			if id=="corridor":
				var company: String=c.fleet_owner(str(op.get("ownerId",""))).get("name","your fleet / local commerce")
				ui.paragraph(primary,"%d / 7 clear days · %d patrol endpoint visits · %s"%[int(op.get("clearDays",0)),int(op.get("patrolVisits",0)),company],18,ui.TEAL)
				var owner: Dictionary=c.fleet_owner(str(op.get("ownerId","")))
				if not owner.is_empty():ui.paragraph(primary,"Patrol purse %s · unpaid wages %d · last crew pay %d coins"%[ui.money(int(owner.get("coins",0))),int(owner.get("wageArrears",0)),int(owner.get("lastPayroll",0))],18,ui.TEXT)
				var status: Array=corridor_status(c,op)
				ui.paragraph(primary,str(status.back()),16,ui.RED if str(status.back()).begins_with("Stalled:") else ui.TEAL)
				ui.paragraph(primary,str(op.get("watchReason","")),15,ui.GOLD)
				var watch=ui.row(primary)
				watch.name="WatchActions"
				ui.button(watch,"Continue paid watch",func():act(ui,"continue_watch","","",0,selected_goal),true,false).disabled=not bool(op.get("canContinue",false))
				ui.button(watch,"Withdraw regional watch",func():act(ui,"withdraw_watch","","",0,selected_goal),false,false).disabled=not bool(op.get("canWithdraw",false))
			if id=="ceasefire":
				var terms: Dictionary=Rules.peace_conditions(c.state,op,str(op.peaceA),str(op.peaceB))
				ui.paragraph(primary,"%s: %d / 5 relief · %s: %d / 5 · talks began day %d"%[Factions.CANON_NAMES[op.peaceA],int(op.relief.get(op.peaceA,0)),Factions.CANON_NAMES[op.peaceB],int(op.relief.get(op.peaceB,0)),int(op.get("talksStartedDay",0))],18,ui.TEAL)
				ui.paragraph(primary,str(terms.reason),16,ui.TEXT)
				ui.button(primary,"Sign thirty-day ceasefire",func():act(ui,"peace",str(op.peaceA),str(op.peaceB),0,selected_goal),true,false)
			if id in ["corridor","harbor","ceasefire"]:
				if id=="corridor":ui.paragraph(primary,"Deliver fuel, ammunition, food or repair kits to %s. Its patrol must still buy supplies and pay its crew and repair workers."%c.port(str(op.portId)).get("name","the sponsoring harbor"),15)
				var supply=ui.row(primary)
				supply.name="ContributionActions"
				var goods=OptionButton.new()
				for g in R.ACCEPT[id]:goods.add_item(Goods.ITEMS[g].name);goods.set_item_metadata(goods.item_count-1,g)
				supply.add_child(goods)
				var qty=SpinBox.new();qty.min_value=1;qty.max_value=100;qty.step=1;qty.value=1;supply.add_child(qty)
				ui.button(supply,"Deliver owned cargo · no payment",func():act(ui,"contribute",id,str(goods.get_item_metadata(goods.selected)),int(qty.value),selected_goal),false,false)
			if id!="corridor":ui.button(primary,"Withdraw goal · delivered goods and grants stay paid",func():act(ui,"cancel",id,"",0,selected_goal),false,false)
		else:
			ui.paragraph(primary,str(item.reason),16,ui.TEXT)
			focus_controls(ui,primary,c,selected_goal)
			ui.button(primary,"Choose this goal",func():act(ui,"start",id,"",0,selected_goal),true,false).disabled=not item.ready
	consequences(ui,body,account)
	var instructions=_details(ui,body,"Goal terms & last published plan")
	instructions.name="GoalTerms"
	ui.paragraph(instructions,"These goals use existing boats, purses and supplies alongside your contracts. Completed routes and harbors are remembered; choosing a new destination never rewrites an active operation.",15)
	match selected_goal:
		"corridor":ui.paragraph(instructions,"Keep both approaches and their sea lane clear for seven consecutive economic days. Prove use through a real merchant passage, a local escort/victory, or two actual endpoint visits by the assigned patrol. Friendly standing can secure up to seven wage-days from the local treasury, preserving two public-payroll days. Recovery and paid resupply take priority.",15)
		"harbor":ui.paragraph(instructions,"At the selected harbor, sell goods and separately donate owned cargo totaling twelve lots after starting. One fully staffed local business must record three paid working days. Rest, stoppage and incomplete payroll add no work days. See Home harbors for construction, materials, labor and operating capital.",15)
		"survey":ui.paragraph(instructions,"Fully survey three connected sites by following discovered leads. Already completed surveys count as an earned achievement. Charting alone does not qualify, and the goal never grants free survey supplies.",15)
		"ceasefire":ui.paragraph(instructions,"Carry five food or repair-kit lots to EACH selected faction. Earn Friendly standing with one party and access to both, with no witnessed offenses or claims. After both relief deliveries, allow three economic days for talks. Sign at either party's legal harbor. The truce lasts thirty days; the prior dispute can resume afterward. No forced commission or invented reward.",15)
	var selected: Dictionary=account.operation
	if selected_goal=="corridor" and not selected.is_empty():
		var plan_lines: Array=corridor_status(c,selected)
		for line in plan_lines.slice(0,plan_lines.size()-1):ui.paragraph(instructions,line,15)
		ui.paragraph(instructions,"Recorded treasury support %d coins; no repeat grant."%int(selected.get("funded",0)),15)
	if selected.get("status","")=="active" or (selected_goal=="corridor" and not selected.is_empty()):
		var destinations=_details(ui,body,"Destinations & ceasefire parties · future goals")
		destinations.name="FutureGoalSelections"
		focus_controls(ui,destinations,c,selected_goal)
	var history=_details(ui,body,"Treaties and accomplishments")
	history.name="RegionalHistory"
	for rec in c.state.regionalCampaigns.peace.values():
		ui.paragraph(history,"%s ↔ %s · %s · expires day %d · new talks after day %d"%[Factions.CANON_NAMES[rec.a],Factions.CANON_NAMES[rec.b],"in force" if rec.get("active",true) else "ended",int(rec.untilDay),int(rec.cooldownUntil)],15)
	for e in R.journal(c.state).slice(0,12):ui.paragraph(history,"Day %d · %s"%[int(e.get("day",0)),event_text(c,e)],15)

static func corridor_status(c,op: Dictionary) -> Array:
	var owner: Dictionary=c.fleet_owner(str(op.get("ownerId","")))
	if owner.is_empty():return ["Stalled: no funded patrol is assigned."]
	var plan: Dictionary=op.get("currentPlan",{})
	var quote: Dictionary=plan.get("readiness",{})
	var order: Dictionary=owner.get("order",{})
	var patrol: Dictionary=Orders.find_patrol(c.state,str(owner.id))
	var convoy: Dictionary=c.fleet_owner(str(plan.get("convoyOwnerId","")))
	var target: Dictionary=c.fleet_owner(str(order.get("targetOwnerId","")))
	var lines: Array=["Last published plan · patrol: %s · convoy: %s · target: %s"%[owner.get("name",owner.id),convoy.get("name","none"),target.get("name","none")]]
	lines.append("Order: %s → %s · %s → %s · route %.0f%%"%[str(order.get("purpose","awaiting orders")),c.port(str(order.get("destination",""))).get("name","no destination"),c.port(str(patrol.get("from",""))).get("name","at sea"),c.port(str(patrol.get("to",""))).get("name","no destination"),float(patrol.get("progress",0))*100.0])
	if not quote.is_empty():
		lines.append("Water route %.0f + return %.0f · %.2f + %.2f days"%[float(quote.get("routeDistance",0)),float(quote.get("returnDistance",0)),maxf(0,float(quote.get("days",0))-float(quote.get("returnDays",0))),float(quote.get("returnDays",0))])
		lines.append("Reserves / route + return: fuel %.1f / %.1f · food %.1f / %.1f · ammo %.0f / %.0f · payroll %d / %d coins"%[float(quote.get("fuel",0)),float(quote.get("fuelNeed",0)),float(quote.get("food",0)),float(quote.get("foodNeed",0)),float(quote.get("ammo",0)),float(quote.get("ammoNeed",0)),int(quote.get("coins",0)),int(quote.get("payrollNeed",0))])
		lines.append("Machinery: %.0f%% engine condition · %s"%[float(quote.get("engineMin",0))*100.0,"modules ready" if quote.get("moduleOk",false) else "equipment service required"])
	lines.append("Treasury grant: %d coins from %s · no repeat grant"%[int(op.get("funded",0)),c.port(str(op.get("portId",""))).get("name","the sponsor")])
	var reason: String=str(owner.get("navigationReason",""))
	if reason.is_empty() and not plan.get("ready",false):reason=str(plan.get("reason","Awaiting a live route and readiness quote."))
	lines.append("Stalled: "+reason if not reason.is_empty() else "Ready: "+str(order.get("reason","Corridor watch underway.")))
	return lines

static func event_text(c,e: Dictionary) -> String:
	var title: String=str(R.TITLES.get(e.get("goal",""),"Regional activity"))
	match str(e.get("kind","")):
		"complete":return title+" · achieved"
		"withdrawn":return title+" · withdrawn"
		"watch-continued":return title+" · paid watch continued"
		"watch-withdrawn":return title+" · regional watch withdrawn; achievement retained"
		"contribute":return "%d %s delivered to %s"%[int(e.qty),Goods.ITEMS[e.good].name,c.port(e.portId).name]
		"mobilize":return "%s assigned %d coins to %s"%[c.port(e.funder).name,int(e.amount),c.fleet_owner(e.target).get("name","its patrol")]
		"operation-order","operation-stalled","operation-resumed":return title+" · "+str(e.get("cause",e.kind))
		"treaty-expired":return "Ceasefire ended · "+("previous dispute resumes" if e.cause=="prior-dispute-restored" else "later agreement remains in force")
		"peace":return "Thirty-day ceasefire signed"
	return title+" · "+str(e.get("kind",""))

static func _home_port(c,id: String) -> bool:
	for row in c.data.get("PORTS",[]):
		if str(row.get("id",""))==id:return true
	return false

static func _island_faction(c,port: Dictionary) -> String:
	var region: String=str(port.get("regionId",""))
	var island: String=str(port.get("islandId",""))
	if island.is_empty():
		for row in c.state.get("sector069",{}).get("initialOwnership",[]):
			if row is Dictionary and str(row.get("portId",""))==str(port.get("id","")):
				region=str(row.get("regionId",region));island=str(row.get("islandId",""));break
	if island.is_empty():return ""
	for row in c.state.get("islandOwnership069",[]):
		if row is Dictionary and not row.has("portId") and str(row.get("regionId",""))==region and str(row.get("islandId",""))==island:
			return str(row.get("faction",""))
	return ""

static func _quote_text(quote: Dictionary) -> String:
	if not quote.get("ok",false):return str(quote.get("message","Dock at a home harbor for a quote."))
	return "Current net warehouse bill: %d coins after a %d-coin credit for your supplied materials. Have %d coins temporarily for the setup transaction. %d paid work days remain; fleet payroll %d coins per day and %.1f work repair kits."%[int(quote.get("netCost",quote.get("cost",0))),int(quote.get("materialCredit",0)),int(quote.get("cashRequired",quote.get("cost",0))),int(quote.get("remainingDays",0)),int(quote.get("payrollPerDay",0)),float(quote.get("workSupplies",0))]

static func _status_text(view: Dictionary,c) -> String:
	var lines: PackedStringArray=[]
	for key in ["improvement","control"]:
		var job: Dictionary=view.get(key,{})
		if job.is_empty():continue
		var days: int=int(job.get("paidDays",0)) if key=="improvement" else int(job.get("supportDays",0))
		var place: String=str(c.port(str(job.get("portId",""))).get("name","the harbor"))
		lines.append("%s at %s: %s, %d of %d paid days. %s"%["Berth work" if key=="improvement" else "Control operation",place,str(job.get("status","awaiting work")),days,int(view.get("workDays",2)),str(job.get("reason",""))])
	var bill: Dictionary=view.get("improvement",{}).get("setupBill",{})
	if not bill.is_empty():lines.append("Paid warehouse bill: %d gross, %d material credit, %d net coins."%[int(bill.get("grossCost",0)),int(bill.get("materialCredit",0)),int(bill.get("netCost",0))])
	return "\n".join(lines) if not lines.is_empty() else "No harbor operation started. Review the requirements before committing goods or coins."

static func territory_panel(ui,body: Node,account: Dictionary) -> void:
	var c=account.view
	var port: Dictionary=account.get("territoryPort",{})
	var view: Dictionary=account.get("territoryView",{})
	var quote: Dictionary=account.get("territoryQuote",{})
	var box=ui.column(body)
	box.name="Territory076";box.add_theme_constant_override("separation",6)
	ui.label(box,"Harbor control",22,ui.GOLD,true)
	var picker=ui.row(box)
	ui.label(picker,"Harbor",15,ui.GOLD)
	var harbors=OptionButton.new()
	var selected: int=0
	for row in c.state.get("ports",[]):
		if not row is Dictionary or not _home_port(c,str(row.get("id",""))):continue
		harbors.add_item(str(row.get("name",row.id)))
		harbors.set_item_metadata(harbors.item_count-1,str(row.id))
		if str(row.id)==str(port.get("id","")):selected=harbors.item_count-1
	if harbors.item_count==0:
		ui.paragraph(box,"No home harbor is available.",15);return
	harbors.select(selected);picker.add_child(harbors)
	harbors.item_selected.connect(func(index):act(ui,"focus","portId",str(harbors.get_item_metadata(index)),0,str(account.goal)))
	var faction: String=str(port.get("faction",""))
	var faction_name: String=str(Factions.CANON_NAMES.get(faction,"Unidentified"))
	ui.paragraph(box,"%s governs %s. A surrender changes this harbor alone; private companies and island jurisdictions remain separate."%[faction_name,str(port.get("name","this harbor"))],16,ui.GOLD)
	ui.paragraph(box,_status_text(view,c),15,ui.TEAL)
	ui.paragraph(box,_quote_text(quote),15)
	var actions=ui.row(box)
	var im: Dictionary=view.get("improvement",{})
	var home: bool=not port.is_empty() and _home_port(c,str(port.get("id","")))
	ui.button(actions,"Resume berth work" if not im.is_empty() and im.get("status")!="complete" else "Improve harbor",func():act(ui,"territory_improve",str(port.get("id","")),"",0,str(account.goal)),true,false).disabled=not home or not bool(quote.get("ok",false))
	ui.button(actions,"Withdraw shore party",func():act(ui,"territory_withdraw","","",0,str(account.goal)),false,false)
	var claim=ui.row(box)
	ui.label(claim,"Sponsor",15,ui.GOLD)
	var factions=OptionButton.new()
	for id in Factions.CANON:
		if id==faction:continue
		factions.add_item(str(Factions.CANON_NAMES[id]));factions.set_item_metadata(factions.item_count-1,id)
	if factions.item_count>0:factions.select(0)
	claim.add_child(factions)
	ui.button(claim,"Fund contest: %d coins"%int(view.get("supportCapital",800)),func():act(ui,"territory_start",str(port.get("id","")),str(factions.get_item_metadata(factions.selected)),0,str(account.goal)),false,false).disabled=not home or factions.item_count==0
	ui.button(claim,"Negotiate surrender",func():act(ui,"territory_negotiate","","",0,str(account.goal)),true,false)
	var terms=_details(ui,box,"Work requirements and cost breakdown")
	var bill: Dictionary=quote.get("homeQuote",{})
	if not bill.is_empty():
		ui.paragraph(terms,"Warehouse setup before the supplied-material credit: material value %d, ordinary workers %d, foremen %d, builder margin %d, duty %d coins. Working capital %d coins enters the business purse; later wages remain payable."%[int(bill.get("materialCost",0)),int(bill.get("setupOrdinaryWages",0)),int(bill.get("setupExpertWages",0)),int(bill.get("margin",0)),int(bill.get("duty",0)),int(bill.get("workingCapitalDeposit",0))],15)
	ui.paragraph(terms,"Bring recovered machine tools, the quoted warehouse materials and two healthy sailors above minimum crew. Materials are reserved for this project when starting, so town production cannot use them. Completion consumes them once and credits their value from the actual setup payment; labor, duty, margin and working capital remain payable. Tools stay aboard and wear by one percent per paid work day. Sailors receive 100 coins each per day through ordinary fleet payroll. Work takes two fully paid local days and half a repair-kit lot each day.",15)
	ui.paragraph(terms,"A contest requires Friendly standing with the sponsor, war between both factions, your hostility to the current governor and an actual defending fleet. The 800 coins enter this harbor's existing treasury. Each of two paid support days also delivers two food and one repair-kit lot from your hold. Win the selected actual contest, then negotiate explicitly. Presence alone takes nothing.",15)
	ui.paragraph(terms,"Leaving, lost crew, unpaid wages, missing supplies or peace interrupts work. Withdraw recalls original sailors; spent goods, wages, support and tool wear remain spent. Resume the same operation to keep its progress.",15)
	var books=_details(ui,box,"Jurisdiction, access and private businesses")
	var island: String=_island_faction(c,port)
	ui.paragraph(books,"Charted island jurisdiction: "+str(Factions.CANON_NAMES.get(island,"unchanged or unrecorded"))+". Harbor authority is recorded separately.",15)
	if not port.is_empty():ui.paragraph(books,str(Politics.access(c,port).get("reason","No access recorded.")),15)
	for b in view.get("businesses",[]):
		ui.paragraph(books,"%s: %s. Its workers, inventory and purse remain with the company."%[str(b.get("name","Owned business")),ui.money(int(b.get("coins",0)))],15)
	ui.rule(box)

static func act(ui,action: String,id: String="",value: String="",qty: int=0,selected_goal: String="corridor") -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	var result: Dictionary={}
	match action:
		"start":result=Ops.start(c,id)
		"contribute":result=Ops.contribute(c,id,value,qty)
		"continue_watch":result=Ops.continue_watch(c)
		"withdraw_watch":result=Ops.withdraw_watch(c)
		"cancel":result=R.cancel(c,id)
		"peace":result=R.propose_peace(c,id,value)
		"territory_improve":result=Ops.territory_improve(c,id)
		"territory_withdraw":result=Ops.territory_withdraw(c)
		"territory_start":
			if not value in Factions.CANON:result=c.fail("Choose a known faction.")
			else:result=Ops.territory_start(c,id,value)
		"territory_negotiate":result=Ops.territory_negotiate(c)
		"focus":
			if id in ["fromPort","toPort","portId"] and not c.port(value).is_empty():
				Ops.ensure(c);c.state.campaignFocus[id]=value;result=c.ok("Regional destination saved; existing operations retain their own endpoints.")
			elif id in ["peaceA","peaceB"] and value in Factions.CANON:
				Ops.ensure(c);c.state.campaignFocus[id]=value;result=c.ok("Proposed parties saved; existing talks retain their terms.")
			else:result=c.fail("That regional selection is no longer available.")
		_:return
	ui.host.respond(result)
	if result.get("ok",false):ui.host.save_game(false)
	open(ui,selected_goal)
