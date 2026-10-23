extends RefCounted
const Routes=preload("res://scripts/route_cache.gd")
const Guidance=preload("res://scripts/campaign_guidance.gd")
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
static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	var target: Dictionary=c.port(str(ui.host.selected_port))
	var route: float=0
	if not target.is_empty():
		var path: Array=Routes.path(c,c.state.position,c.port_position(str(target.id)))
		for i in range(1,path.size()):route+=c.distance(path[i-1],path[i])
	var report: Dictionary=Guidance.report(c,route,str(ui.guidance_career))
	ui.modal_kind="captain_priorities"
	var body=ui.modal("Captain's priorities","YOUR FLEET · THE VOYAGE · WHAT NEEDS ATTENTION",1120,880)
	ui.paragraph(body,"Choose a way to read the coast. This view suggests existing opportunities and explains current problems; it does not spend coins, issue orders or change your career.",16)
	var career=OptionButton.new();var choices: Array=Guidance.careers();var selected: int=0
	for i in range(choices.size()):
		career.add_item(str(choices[i].name))
		if choices[i].id==ui.guidance_career:selected=i
	career.select(selected);body.add_child(career)
	career.item_selected.connect(func(i):ui.guidance_career=str(choices[i].id);open(ui))
	var fleet: Dictionary=report.fleet
	ui.label(body,"%d owned boats · %d in your company fleets · %d stored · %d supporting"%[int(fleet.owned),int(fleet.company),int(fleet.stored),int(fleet.support)],21,ui.GOLD,true)
	ui.paragraph(body,"Next battle: %d deployed boats at %d / %d points, %d held in reserve. Ownership, traveling support and battle deployment are separate. Secured prizes need harbor repair before combat."%[int(fleet.deployed),int(fleet.points),int(fleet.limit),int(fleet.reserve)],15)
	var budget: Dictionary=report.route_trip_returnbudget
	ui.label(body,"Return allowance",22,ui.TEAL,true)
	ui.paragraph(body,"Selected harbor: %s. The estimate is a round trip from your current position plus %.0f reserve days.
%.1f days planned · %s coins daily payroll · %s coins return payroll · %.1f food days · %.1f working-fuel days · %.1f repair kits.
Holds: %.1f / %.1f space. Loose fuel still needs loading into boat tanks."%[str(target.get("name","No harbor selected")),float(budget.reserveDays),float(budget.tripDays),str(budget.dailyWages),str(budget.returnWages),float(budget.foodDays),float(budget.fuelDays),float(budget.repairKits),float(budget.cargoWeight),float(budget.usableCapacity)],15)
	for card in report.cards:
		ui.rule(body)
		ui.label(body,str(card.title),21,ui.RED if card.urgent else ui.GOLD,true)
		ui.paragraph(body,str(card.reason),15)
		var id: String=str(card.actionId)
		ui.button(body,"Open "+str({"fleet":"fleet","hold":"hold","training":"academy","supply":"expedition preparation","tooling":"machinery","workers":"workplace accounts","trade":"trade intelligence","companies":"shipping companies","law":"customs","boarding":"boarding and defenses","crises":"regional crises","exploration":"island charts","jobs":"contacts and jobs","regional":"regional goals"}.get(id,id)),func():action(ui,id))
	for note in report.notes:ui.paragraph(body,str(note),13,ui.MUTED)
	ui.button(body,"Close",ui.close_modal,true)
