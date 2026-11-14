extends RefCounted
const Routes=preload("res://scripts/route_cache.gd")
const Guidance=preload("res://scripts/campaign_guidance.gd")
const Costs=preload("res://scripts/career_costs.gd")
const VoyagePanel=preload("res://scripts/voyage_panel070.gd")

static func open_voyage(ui,offer_id: String="") -> void:
	# Quotes are prepared only on opening/refresh, never by the campaign HUD tick.
	var c=ui.host.core
	var offers: Array=Costs.contract_offers(c)
	var offer: Dictionary=c.state.get("activeContract",{}).duplicate(true)
	if offer.is_empty():
		for candidate in offers:
			if str(candidate.id)==offer_id or (offer_id.is_empty() and candidate.get("story",false)):
				offer=candidate;break
		if offer.is_empty() and not offers.is_empty():offer=offers[0]
	ui.modal_kind="voyage_review"
	var body=ui.modal("Voyage review","ROUTE · PAYROLL · RETURN RESERVES",980,820)
	if offer.is_empty():
		ui.paragraph(body,"No current contract offer. Inspect the contracts or funded work board at a harbor.")
		VoyagePanel.connect_views(ui,body,true,true)
		ui.button(body,"Open contracts & logbook",ui.open_contracts)
		ui.button(body,"Close",ui.close_modal,false,false)
		return
	var q: Dictionary=Costs.contract_quote(c,offer)
	offer=q.offer
	var budget: Dictionary=q.operatingCosts;var e: Dictionary=q.endurance
	ui.label(body,str(offer.title),25,ui.GOLD,true)
	_primary_contract_action(ui,body,c,offer,q)
	ui.paragraph(body,"%s → %s · %s"%[str(c.port(str(offer.port)).get("name",offer.port)),str(c.port(str(offer.targetPort)).get("name",offer.targetPort)),ui.count_text(offer.get("enemyHulls",[]).size(),"hostile boat","hostile boats")],17,ui.TEXT)
	ui.paragraph(body,"Gross reward: %d coins · %s"%[int(q.grossRewardCoins),("held in contract escrow" if q.active else "sponsor can fund escrow on acceptance") if q.funded else "FUNDING UNAVAILABLE"],16,ui.TEAL)
	var reserve_days: int=roundi(float(budget.reserveDays))
	var route_note: String="Safe route: %s. %.2f days including return and %s."%[ui.count_text(roundi(float(q.routeDistance)),"chart unit","chart units"),float(budget.days),ui.count_text(reserve_days,"contingency day","contingency days")] if q.routeAvailable else "No safe sailing route. Sailing quote unavailable; %s only, excluding travel."%ui.count_text(reserve_days,"reserve day","reserve days")
	ui.paragraph(body,route_note+" Payroll %d coins/day; %d coins over this allowance."%[int(budget.dailyWages),int(budget.wageCoins)],15)
	ui.paragraph(body,"Coverage: %.1f food days · %.1f working-fuel days · %.1f repair kits. Full replacement values still to buy: %.2f food / %d coins, %.2f fuel / %d coins. Stores already aboard are not purchased again; loose fuel must be loaded through Hold."%[float(e.foodDays),float(e.fuelDays),float(e.repairKits),float(budget.foodPurchase),int(budget.foodPurchaseCoins),float(budget.fuelPurchase),int(budget.fuelPurchaseCoins)],15)
	ui.paragraph(body,"Current paid repairs: %s. Full payroll, stores replacement and repair value: %d coins."%[str(int(budget.repairQuoteCoins))+" coins" if budget.repairQuoteAvailable else "dock quote unavailable",int(budget.allowanceCoins)],15)
	ui.paragraph(body,"Additional cash allowance: %d coins. Only shortfalls in food and fuel need new purchases; full replacement value remains in the surplus projection."%int(budget.additionalCashCoins),14)
	if q.routeAvailable:
		ui.paragraph(body,"Estimated reward less full allowance, if funded and completed: %d coins. This values wages, reserve days and all food and fuel at replacement cost, including stores already aboard."%int(q.estimatedSurplusCoins),15,ui.GOLD)
	ui.paragraph(body,"Future damage, ammunition, paid fitting and time spent fighting are extra. Quotes refresh when this review opens; final actions recheck the live contract.",13)
	for blocker in q.blockers:ui.paragraph(body,str(blocker),14,ui.RED)
	VoyagePanel.connect_views(ui,body,true,false)
	if not q.active:
		for candidate in offers:
			if candidate.get("kind","")=="delivery" and str(candidate.id)!=str(offer.id):
				var dispatch_id: String=str(candidate.id)
				ui.button(body,"Review sealed dispatch",func():open_voyage(ui,dispatch_id),false,false)
				break
	var hull: Dictionary=q.secondHull
	if not hull.is_empty():
		ui.label(body,"Towards a second hull",20,ui.TEAL,true)
		ui.paragraph(body,"Lowest local ready-hull entry: %s, %d coins + %d coins for %s; %d in stock. Commission hull alone: %d coins, with materials and paid construction required."%[str(hull.name),int(hull.readyCoins),int(hull.crewAdvanceCoins),ui.count_text(int(hull.minimumCrew),"sailor's advance","sailors' advance"),int(hull.stock),int(hull.commissionCoins)],14)
		if q.routeAvailable:ui.paragraph(body,"Estimated shortfall if this contract pays, after protecting the full voyage allowance: %d coins. New-boat stores, fitting and ongoing payroll are extra."%int(hull.gapCoins),14)
	if not VoyagePanel.service_berth(c).is_empty():
		var services=ui.row(body)
		ui.button(services,"Paid repairs & crew",func():ui.open_port("Crew & repairs"))
		ui.button(services,"Paid fitting",func():ui.open_port("Refit"))
		ui.button(services,"Local boatyard quotes",func():ui.open_port("Boatyard"))
	ui.button(body,"Refresh voyage quote",func():open_voyage(ui,str(offer.id)),false,false)
	ui.button(body,"Close",ui.close_modal,false,false)

static func _primary_contract_action(ui,body,c,offer: Dictionary,q: Dictionary) -> void:
	if q.active:
		if c.contract_ready():
			ui.button(body,"Deliver & collect reward" if offer.get("cleared",false) else "Engage hostile flotilla",ui.host.resolve_contract,true).disabled=not q.funded
		elif c.home_local064():
			ui.button(body,"Chart destination",func():ui.host.sail_to(str(offer.targetPort));ui.close_modal(),true).disabled=not q.routeAvailable
		else:
			ui.paragraph(body,"The contract harbor is on Shatter Coast. This chart cannot set that harbor course.",15,ui.GOLD)
	elif q.atSponsor:
		ui.button(body,"Accept contract",func():ui.host.accept_contract(str(offer.id));open_voyage(ui),true).disabled=not q.canAccept
	elif c.home_local064():
		ui.button(body,"Go to sponsor",func():ui.host.sail_to(str(offer.port));ui.close_modal(),true)
	else:
		ui.paragraph(body,"The sponsor harbor is on Shatter Coast. This chart cannot set that harbor course.",15,ui.GOLD)

static func action_label(id: String) -> String:
	return "Open "+str({"fleet":"fleet","hold":"hold","training":"academy","supply":"expedition preparation","tooling":"machinery","workers":"workplace accounts","trade":"trade intelligence","companies":"shipping companies","law":"customs","boarding":"boarding and defenses","crises":"regional crises","exploration":"island charts","jobs":"funded work board","regional":"regional goals","fishing":"fishing crews · K board","traffic":"coastal traffic & convoy contacts","contracts":"contracts & logbook","market":"harbor market","yard":"harbor boatyard","catalog":"boat designs"}.get(id,id))

static func action(ui,id: String) -> void:
	match id:
		"fleet":ui.open_fleet()
		"hold":ui.open_cargo()
		"training":ui.EconomicUI.open(ui)
		"supply":ui.CampaignUI.expedition(ui)
		"tooling":ui.ToolingUI.open(ui)
		"workers":ui.WorkerUI.open(ui)
		"trade":ui.TradeUI.open(ui)
		"companies":ui.CompanyUI.open(ui)
		"law":ui.LawUI.open(ui)
		"boarding":ui.BoardingUI.open(ui)
		"crises":ui.CrisisUI.open(ui)
		"exploration":ui.CampaignUI.islands(ui)
		"jobs":ui.VoyageUI.open(ui)
		"regional":ui.RegionalUI.open(ui)
		"fishing":ui.VoyageUI.open(ui,"Fishing")
		"traffic":ui.NavalUI.open(ui)
		"contracts":ui.open_contracts()
		"market":ui.open_port("Market")
		"yard":ui.open_port("Boatyard")
		"catalog":ui.open_catalog()

static func career_plan(ui,body,plan: Dictionary) -> void:
	if plan.is_empty():return
	ui.rule(body)
	ui.label(body,str(plan.get("name","Career"))+" · first goal",25,ui.GOLD,true)
	ui.paragraph(body,str(plan.get("firstGoal","")),17,ui.TEXT)
	ui.label(body,"Requirements & entry",20,ui.TEAL,true)
	for requirement in plan.get("requirements",[]):ui.paragraph(body,str(requirement),15)
	if not plan.get("ready",false):
		for blocker in plan.get("blockers",[]):ui.paragraph(body,str(blocker),15,ui.GOLD)
	ui.label(body,"Operating costs",20,ui.TEAL,true)
	ui.paragraph(body,str(plan.get("operatingCosts",{}).get("summary","Inspect expedition preparation for current payroll and stores.")),15)
	ui.label(body,"Reward source",20,ui.TEAL,true)
	ui.paragraph(body,str(plan.get("rewardSource","")),15)
	var first_action: String=str(plan.get("actionId",""))
	if not first_action.is_empty():ui.button(body,action_label(first_action),func():action(ui,first_action),true)
	ui.label(body,"Next step",20,ui.TEAL,true)
	ui.paragraph(body,str(plan.get("nextStep","")),15)
	var next_action: String=str(plan.get("nextActionId",""))
	if not next_action.is_empty() and next_action!=first_action:ui.button(body,action_label(next_action),func():action(ui,next_action))
	for extra_key in ["alternativesSummary","reinvestmentSummary"]:
		var extra_note: String=str(plan.get(extra_key,""))
		if not extra_note.is_empty():ui.paragraph(body,extra_note,14,ui.TEAL)
	for key in ["basis","limits"]:
		var note: String=str(plan.get(key,""))
		if not note.is_empty():ui.paragraph(body,note,13,ui.MUTED)

static func open(ui) -> void:
	var c=ui.host.core
	var target: Dictionary=c.port(str(ui.host.selected_port))
	var route: float=0
	var sailing_quote: bool=false
	if not target.is_empty():
		var path: Array=Routes.path(c,c.state.position,c.port_position(str(target.id)))
		sailing_quote=not path.is_empty()
		for i in range(1,path.size()):route+=c.distance(path[i-1],path[i])
	var report: Dictionary=Guidance.report(c,route,str(ui.guidance_career))
	ui.modal_kind="captain_priorities"
	var body=ui.modal("Captain's priorities","YOUR FLEET · THE VOYAGE · WHAT NEEDS ATTENTION",1120,880)
	ui.paragraph(body,"Choose a career to see a practical first goal, its entry requirements, paid running costs and real reward source. Reading this view spends nothing and changes no orders or jobs.",16)
	var career=OptionButton.new();var choices: Array=Guidance.careers();var selected: int=0
	for i in range(choices.size()):
		career.add_item(str(choices[i].name))
		if choices[i].id==report.career:selected=i
	career.select(selected);body.add_child(career)
	career.item_selected.connect(func(i):ui.guidance_career=str(choices[i].id);open(ui))
	# Career entry stays visible even when all warning-card slots are occupied.
	career_plan(ui,body,report.get("careerPlan",{}))
	var fleet: Dictionary=report.fleet
	ui.label(body,"%s · %d in your company fleets · %d stored · %d supporting"%[ui.count_text(int(fleet.owned),"owned boat","owned boats"),int(fleet.company),int(fleet.stored),int(fleet.support)],21,ui.GOLD,true)
	ui.paragraph(body,"Next battle: %s at %d / %d points, %d held in reserve. Ownership, traveling support and battle deployment are separate. Secured prizes need harbor repair before combat."%[ui.count_text(int(fleet.deployed),"deployed boat","deployed boats"),int(fleet.points),int(fleet.limit),int(fleet.reserve)],15)
	var budget: Dictionary=report.route_trip_returnbudget
	ui.label(body,"Return allowance" if sailing_quote else "Reserve-only budget",22,ui.TEAL,true)
	var journey: String="No harbor selected. Sailing quote unavailable; reserve-only budget, excluding travel."
	if not target.is_empty():
		journey="Selected harbor: %s. "%str(target.name)
		journey+="The estimate is a round trip from your current position plus %s."%ui.count_text(roundi(float(budget.reserveDays)),"reserve day","reserve days") if sailing_quote else "No safe sailing route. Sailing quote unavailable; reserve-only budget, excluding travel."
	ui.paragraph(body,journey+"\n%.1f %s days · %s coins daily payroll · %s coins %s payroll · %.1f food days · %.1f working-fuel days · %.1f repair kits.
Holds: %.1f / %.1f space. Loose fuel still needs loading into boat tanks. Estimate for the current fleet."%[float(budget.tripDays),"planned" if sailing_quote else "reserve",str(budget.dailyWages),str(budget.returnWages),"return" if sailing_quote else "reserve",float(budget.foodDays),float(budget.fuelDays),float(budget.repairKits),float(budget.cargoWeight),float(budget.usableCapacity)],15)
	VoyagePanel.connect_views(ui,body,false,true)
	var dock: Dictionary=VoyagePanel.board_header(c)
	var dock_chart: String=str(dock.region) if not str(dock.region).is_empty() else "this chart"
	if bool(dock.docked):
		var dock_kind: String="Service harbor" if str(dock.kind)=="home" else "Work berth"
		ui.paragraph(body,"%s: %s · %s. The funded board lists gross fees. Review one job there for its voyage estimate. The allowance above is this career screen's own figure. Opening the board buys nothing."%[dock_kind,str(dock.name),dock_chart],15)
		ui.button(body,"Open funded work at this berth",func():ui.VoyageUI.open(ui),true,false)
	elif not bool(dock.get("berthKnown",false)):
		ui.paragraph(body,"The funded board lists published gross fees. Review one job for its voyage estimate. This career allowance is separate. Opening the board buys nothing.",15)
		ui.button(body,"Open funded work board",func():ui.VoyageUI.open(ui),false,false)
	else:
		ui.paragraph(body,"The funded board lists work only at a known harbor you are docked at. Opening it buys nothing.",15)
		ui.button(body,"Open funded work board",func():ui.VoyageUI.open(ui),false,false)
	for card in report.cards:
		ui.rule(body)
		ui.label(body,str(card.title),21,ui.RED if card.urgent else ui.GOLD,true)
		ui.paragraph(body,str(card.reason),15)
		var id: String=str(card.actionId)
		ui.button(body,action_label(id),func():action(ui,id))
	for note in report.notes:ui.paragraph(body,str(note),13,ui.MUTED)
	ui.button(body,"Close",ui.close_modal,true,false)
