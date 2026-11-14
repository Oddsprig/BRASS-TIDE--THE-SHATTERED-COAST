extends RefCounted
const Routes=preload("res://scripts/route_cache.gd")
const Guidance=preload("res://scripts/campaign_guidance.gd")
const Costs=preload("res://scripts/career_costs.gd")
const VoyagePanel=preload("res://scripts/voyage_panel070.gd")

static func _actions(parent: Node) -> HFlowContainer:
	var flow=HFlowContainer.new()
	flow.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation",8)
	flow.add_theme_constant_override("v_separation",8)
	parent.add_child(flow)
	return flow

static func _switch_caption(candidate: Dictionary) -> String:
	if candidate.get("kind","")=="delivery":
		return "Review sealed dispatch"
	if candidate.get("story",false):
		return "Review story contract"
	var title: String=str(candidate.get("title","contract"))
	if title.to_lower().contains("patrol"):
		return "Review coastal patrol"
	return "Review "+title

static func _choice_summary(ui,c,candidate: Dictionary,q: Dictionary,selected: bool) -> String:
	var prefix: String="▶ " if selected else "• "
	var target_name: String=str(c.port(str(candidate.get("targetPort",""))).get("name",candidate.get("targetPort","")))
	var choice_title: String=str(candidate.get("title","Contract"))
	var destination: String="" if target_name in choice_title else " → "+target_name
	var hostiles: String=ui.count_text(candidate.get("enemyHulls",[]).size(),"hostile boat","hostile boats")
	var status: String="ready" if q.get("canAccept",false) and q.get("ready",false) else ("unfunded" if not q.get("funded",false) else ("no route" if not q.get("routeAvailable",false) else "check reserves"))
	if q.get("routeAvailable",false) and q.get("estimatedSurplusCoins",null)!=null:
		return "%s%s%s · %s · %d coins gross (%d estimated surplus) · %s"%[prefix,choice_title,destination,hostiles,int(q.grossRewardCoins),int(q.estimatedSurplusCoins),status]
	return "%s%s%s · %s · %d coins gross · %s"%[prefix,choice_title,destination,hostiles,int(q.grossRewardCoins),status]

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
	var body=ui.modal("Voyage review","CHOICES · RESERVES · NEXT UPGRADE",980,820)
	if offer.is_empty():
		ui.paragraph(body,"No local contract offer. Open Contracts & logbook or the funded work board at a harbor.")
		VoyagePanel.connect_views(ui,body,true,true)
		var empty_actions=_actions(body)
		ui.button(empty_actions,"Open contracts & logbook",ui.open_contracts)
		ui.button(empty_actions,"Close",ui.close_modal,false,false)
		return
	var q: Dictionary=Costs.contract_quote(c,offer)
	offer=q.offer
	var budget: Dictionary=q.operatingCosts;var e: Dictionary=q.endurance
	if not q.active and offers.size()>1:
		ui.label(body,"Local contract choices",18,ui.TEAL,true)
		var switch_row=_actions(body)
		for candidate in offers:
			var is_current: bool=str(candidate.id)==str(offer.id)
			var cq: Dictionary=q if is_current else Costs.contract_quote(c,candidate)
			ui.paragraph(body,_choice_summary(ui,c,candidate,cq,is_current),14,ui.GOLD if is_current else ui.TEXT)
			if not is_current:
				var next_id: String=str(candidate.id)
				ui.button(switch_row,_switch_caption(candidate),func():open_voyage(ui,next_id),false,false)
		ui.rule(body)
	ui.label(body,str(offer.title),24,ui.GOLD,true)
	_primary_contract_action(ui,body,c,offer,q)
	var escrow_state: String=("escrow held" if q.active else "escrow funded on acceptance") if q.funded else "FUNDING UNAVAILABLE"
	var net_clause: String=" · Est. net after full allowance: %d coins"%int(q.estimatedSurplusCoins) if q.routeAvailable and q.estimatedSurplusCoins!=null else ""
	ui.paragraph(body,"%s → %s · %s · Gross reward: %d coins (%s)%s"%[
		str(c.port(str(offer.port)).get("name",offer.port)),
		str(c.port(str(offer.targetPort)).get("name",offer.targetPort)),
		ui.count_text(offer.get("enemyHulls",[]).size(),"hostile boat","hostile boats"),
		int(q.grossRewardCoins),
		escrow_state,
		net_clause],16,ui.TEAL if q.funded else ui.RED)
	var reserve_days: int=roundi(float(budget.reserveDays))
	var route_note: String="Safe route: %s · %.2f days (round trip + %s)."%[
		ui.count_text(roundi(float(q.routeDistance)),"chart unit","chart units"),
		float(budget.days),
		ui.count_text(reserve_days,"contingency day","contingency days")
	] if q.routeAvailable else "No safe sailing route. Sailing quote unavailable; %s only, excluding travel."%ui.count_text(reserve_days,"reserve day","reserve days")
	ui.paragraph(body,"%s Payroll: %d coins/day (%d coins voyage reserve · purse %d coins)."%[
		route_note,int(budget.dailyWages),int(budget.wageCoins),int(c.state.get("coins",0))],15)
	var repair_text: String="%d coins"%int(budget.repairQuoteCoins) if budget.repairQuoteAvailable else "dock quote unavailable"
	var loose_note: String=" (%.1f loose fuel in Hold)"%float(budget.looseFuel) if float(budget.looseFuel)>0.0 else ""
	ui.paragraph(body,"Reserves aboard: %.1f food days · %.1f tank-fuel days · %.1f repair kits%s. Store shortfalls to buy: %.1f food (%d coins), %.1f fuel (%d coins) · Repairs: %s · Full voyage allowance: %d coins (cash needed now: %d coins)."%[
		float(e.foodDays),float(e.fuelDays),float(e.repairKits),loose_note,
		float(budget.foodPurchase),int(budget.foodPurchaseCoins),
		float(budget.fuelPurchase),int(budget.fuelPurchaseCoins),
		repair_text,int(budget.allowanceCoins),int(budget.additionalCashCoins)],14)
	ui.paragraph(body,"The full allowance values used stores at replacement cost; stores already aboard are not purchased again. Later combat damage and ammunition are extra.",13)
	for blocker in q.blockers:ui.paragraph(body,str(blocker),14,ui.RED)
	for step_note in Guidance.recovery_notes(c,offers,q):ui.paragraph(body,str(step_note),14,ui.GOLD)
	var projected_coins: int=-1
	if q.routeAvailable and q.funded and q.estimatedSurplusCoins!=null:
		projected_coins=maxi(0,int(c.state.get("coins",0))-int(c.state.get("wageArrears",0))+int(q.estimatedSurplusCoins))
	var upgrades: Array=Guidance.upgrade_quotes(c,projected_coins)
	var hull: Dictionary=q.secondHull
	if not upgrades.is_empty() or not hull.is_empty():
		ui.rule(body)
		ui.label(body,"Next upgrade & fleet growth",19,ui.TEAL,true)
		for up in upgrades:
			var status_text: String="affordable now (keeps 2-day payroll reserve)" if bool(up.get("safeReserveNow",false)) else ("affordable now" if bool(up.get("affordableNow",false)) else ("within budget after completion (%d coins short now)"%int(up.get("shortCoins",0)) if bool(up.get("affordableAfterContract",false)) else "short %d coins"%int(up.get("shortCoins",0))))
			var where_text: String="Refit" if str(up.get("action",""))=="refit" else "Fleet"
			ui.paragraph(body,"• %s (%s · %s): %d coins · %s — %s."%[
				str(up.get("name","Upgrade")),str(up.get("slotLabel","")),where_text,
				int(up.get("cost",0)),str(up.get("effect","")),status_text],14,
				ui.GOLD if bool(up.get("affordableNow",false)) else ui.TEXT)
		if not hull.is_empty():
			var gap_clause: String=" · Estimated shortfall if funded and completed: %d coins"%int(hull.gapCoins) if q.routeAvailable and q.funded else ""
			ui.paragraph(body,"Towards a second hull: %s — %d coins ready + %d coins (%s, %d in stock; commission hull %d coins, materials and paid construction required)%s."%[
				str(hull.name),int(hull.readyCoins),int(hull.crewAdvanceCoins),
				ui.count_text(int(hull.minimumCrew),"sailor's advance","sailors' advance"),
				int(hull.stock),int(hull.commissionCoins),gap_clause],14,ui.MUTED)
	ui.rule(body)
	VoyagePanel.connect_views(ui,body,true,false)
	if not VoyagePanel.service_berth(c).is_empty():
		var services=_actions(body)
		ui.button(services,"Paid repairs & crew",func():ui.open_port("Crew & repairs"))
		ui.button(services,"Paid fitting",func():ui.open_port("Refit"))
		ui.button(services,"Open fleet",ui.open_fleet)
		ui.button(services,"Local boatyard quotes",func():ui.open_port("Boatyard"))
	var footer=_actions(body)
	ui.button(footer,"Refresh voyage quote",func():open_voyage(ui,str(offer.id)),false,false)
	ui.button(footer,"Close",ui.close_modal,false,false)

static func _primary_contract_action(ui,body,c,offer: Dictionary,q: Dictionary) -> void:
	var row=_actions(body)
	if q.active:
		if c.contract_ready():
			ui.button(row,"Deliver & collect reward" if offer.get("cleared",false) else "Engage hostile flotilla",ui.host.resolve_contract,true).disabled=not q.funded
		elif c.home_local064():
			ui.button(row,"Chart destination",func():ui.host.sail_to(str(offer.targetPort));ui.close_modal(),true).disabled=not q.routeAvailable
		else:
			ui.paragraph(body,"Contract harbor is on Shatter Coast; return there to set this course.",15,ui.GOLD)
	elif q.atSponsor:
		ui.button(row,"Accept contract",func():ui.host.accept_contract(str(offer.id));open_voyage(ui),true).disabled=not q.canAccept
	elif c.home_local064():
		ui.button(row,"Go to sponsor",func():ui.host.sail_to(str(offer.port));ui.close_modal(),true)
	else:
		ui.paragraph(body,"Sponsor harbor is on Shatter Coast; return there to set this course.",15,ui.GOLD)
	var budget: Dictionary=q.get("operatingCosts",{})
	var e: Dictionary=q.get("endurance",{})
	if float(e.get("fuelDays",0.0))<float(budget.get("days",0.0)) and float(budget.get("looseFuel",0.0))>0.0:
		ui.button(row,"Load hold reserves",func():
			var loaded: Dictionary=c.use_reserves()
			ui.host.respond(loaded)
			if loaded.get("ok",false):ui.host.save_game(false)
			open_voyage(ui,str(offer.id)))

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
	ui.label(body,str(plan.get("name","Career"))+" · first goal",24,ui.GOLD,true)
	ui.paragraph(body,str(plan.get("firstGoal","")),16,ui.TEXT)
	ui.label(body,"Requirements & entry",19,ui.TEAL,true)
	for requirement in plan.get("requirements",[]):ui.paragraph(body,str(requirement),15)
	if not plan.get("ready",false):
		for blocker in plan.get("blockers",[]):ui.paragraph(body,str(blocker),14,ui.GOLD)
	ui.label(body,"Operating costs",19,ui.TEAL,true)
	ui.paragraph(body,str(plan.get("operatingCosts",{}).get("summary","Inspect expedition preparation for current payroll and stores.")),14)
	ui.label(body,"Reward source",19,ui.TEAL,true)
	ui.paragraph(body,str(plan.get("rewardSource","")),15)
	var plan_actions=_actions(body)
	var first_action: String=str(plan.get("actionId",""))
	if not first_action.is_empty():ui.button(plan_actions,action_label(first_action),func():action(ui,first_action),true)
	ui.label(body,"Next step",19,ui.TEAL,true)
	ui.paragraph(body,str(plan.get("nextStep","")),15)
	var next_action: String=str(plan.get("nextActionId",""))
	if not next_action.is_empty() and next_action!=first_action:
		var next_row=_actions(body)
		ui.button(next_row,action_label(next_action),func():action(ui,next_action))
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
	var body=ui.modal("Captain's priorities","CAREER · FLEET · RESERVES",1120,880)
	ui.paragraph(body,"Select a career to inspect entry requirements, voyage reserves, payout sources and next actions.",15)
	var career=OptionButton.new();var choices: Array=Guidance.careers();var selected: int=0
	for i in range(choices.size()):
		career.add_item(str(choices[i].name))
		if choices[i].id==report.career:selected=i
	career.select(selected);body.add_child(career)
	career.item_selected.connect(func(i):ui.guidance_career=str(choices[i].id);open(ui))
	# Career entry stays visible even when all warning-card slots are occupied.
	career_plan(ui,body,report.get("careerPlan",{}))
	var fleet: Dictionary=report.fleet
	ui.rule(body)
	ui.label(body,"%s · %d in company fleets · %d stored · %d support"%[ui.count_text(int(fleet.owned),"owned boat","owned boats"),int(fleet.company),int(fleet.stored),int(fleet.support)],20,ui.GOLD,true)
	ui.paragraph(body,"Battle line: %s (%d / %d deployment points, %d in reserve). Support hulls stay out of combat; captured prizes need harbor repair first."%[ui.count_text(int(fleet.deployed),"deployed boat","deployed boats"),int(fleet.points),int(fleet.limit),int(fleet.reserve)],15)
	var budget: Dictionary=report.route_trip_returnbudget
	ui.label(body,"Return allowance" if sailing_quote else "Reserve-only budget",21,ui.TEAL,true)
	var journey: String="No harbor selected. Sailing quote unavailable; reserve-only budget, excluding travel."
	if not target.is_empty():
		journey="Selected harbor: %s. "%str(target.name)
		journey+="The estimate is a round trip from your current position plus %s."%ui.count_text(roundi(float(budget.reserveDays)),"reserve day","reserve days") if sailing_quote else "No safe sailing route. Sailing quote unavailable; reserve-only budget, excluding travel."
	var loose_fuel: float=float(c.state.get("cargo",{}).get("fuel",0.0)) if c!=null and c.get("state") is Dictionary else 0.0
	var hold_fuel_note: String=" (%.1f loose fuel in Hold)"%loose_fuel if loose_fuel>0.0 else ""
	ui.paragraph(body,journey+"\n%.1f %s days · %s coins/day payroll (%s coins %s) · %.1f food days · %.1f tank-fuel days%s · %.1f repair kits · Holds %.1f / %.1f."%[float(budget.tripDays),"planned" if sailing_quote else "reserve",str(budget.dailyWages),str(budget.returnWages),"return" if sailing_quote else "reserve",float(budget.foodDays),float(budget.fuelDays),hold_fuel_note,float(budget.repairKits),float(budget.cargoWeight),float(budget.usableCapacity)],15)
	VoyagePanel.connect_views(ui,body,false,true)
	var dock: Dictionary=VoyagePanel.board_header(c)
	var dock_chart: String=str(dock.region) if not str(dock.region).is_empty() else "this chart"
	if bool(dock.docked):
		var dock_kind: String="Service harbor" if str(dock.kind)=="home" else "Work berth"
		ui.paragraph(body,"%s: %s · %s. Inspect individual freight, survey, bounty and charter quotes on the funded work board."%[dock_kind,str(dock.name),dock_chart],14)
		ui.button(body,"Open funded work at this berth",func():ui.VoyageUI.open(ui),true,false)
	elif not bool(dock.get("berthKnown",false)):
		ui.paragraph(body,"Funded work board lists published gross fees and per-voyage cost quotes.",14)
		ui.button(body,"Open funded work board",func():ui.VoyageUI.open(ui),false,false)
	else:
		ui.paragraph(body,"Dock at a harbor to view local offers on the funded work board.",14)
		ui.button(body,"Open funded work board",func():ui.VoyageUI.open(ui),false,false)
	for card in report.cards:
		ui.rule(body)
		ui.label(body,str(card.title),20,ui.RED if card.urgent else ui.GOLD,true)
		ui.paragraph(body,str(card.reason),15)
		var id: String=str(card.actionId)
		ui.button(body,action_label(id),func():action(ui,id))
	for note in report.notes:ui.paragraph(body,str(note),13,ui.MUTED)
	ui.button(body,"Close",ui.close_modal,true,false)
