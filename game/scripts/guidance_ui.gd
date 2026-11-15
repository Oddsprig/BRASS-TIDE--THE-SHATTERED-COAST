extends RefCounted
const Routes=preload("res://scripts/route_cache.gd")
const Guidance=preload("res://scripts/campaign_guidance.gd")
const Costs=preload("res://scripts/career_costs.gd")
const VoyagePanel=preload("res://scripts/voyage_panel070.gd")

## HUD hooks: build once with the HUD; refresh changes text only. No quoting
## or pathfinding is performed on the 150 ms HUD update.
static func render_next120(ui, parent: Node) -> void:
	var card = ui.column(parent)
	card.name = "CaptainNext120"
	ui.label(card, "NEXT ACTION", 12, ui.TEAL).name = "Caption"
	var title = ui.paragraph(card, "", 18, ui.GOLD)
	title.name = "Title"
	var reason = ui.paragraph(card, "", 13)
	reason.name = "Reason"
	var open_button = ui.button(card, "Next voyage", func(): _open_next120(ui), true, false)
	open_button.name = "Open"
	ui.button(card, "Guidance and other work", func(): open_first120(ui), false, false).name = "Manage"
	refresh_next120(ui)

static func _open_next120(ui) -> void:
	if ui.host.first_voyage120.enabled: _next120(ui, ui.host.first_voyage120.status(ui.host))
	else: open_first120(ui)

static func refresh_next120(ui) -> void:
	var card = ui.chrome.find_child("CaptainNext120", true, false)
	if card == null: return
	var guide = ui.host.first_voyage120
	var step: Dictionary = guide.status(ui.host)
	var visible: bool = guide.enabled and not step.is_empty()
	for part in ["Caption", "Title", "Reason"]: card.get_node(part).visible = visible
	card.get_node("Manage").visible = visible
	card.get_node("Open").text = str(step.get("caption", "Next voyage")) if visible else "Show voyage guidance"
	card.get_node("Title").text = str(step.get("title", ""))
	card.get_node("Reason").text = str(step.get("reason", ""))

static func open_first120(ui) -> void:
	if ui.host.mode == "battle":
		open_battle120(ui)
		return
	if ui.host.mode != "campaign": return
	ui.host.first_voyage120.enabled = true
	var step: Dictionary = ui.host.first_voyage120.status(ui.host)
	ui.modal_kind = "first_voyage120"
	var body = ui.modal("Next voyage", "PAID WORK - FITTING - NEXT DEPARTURE", 900, 650)
	ui.label(body, str(step.get("title", "Choose your work")), 24, ui.GOLD, true)
	ui.paragraph(body, str(step.get("reason", "Choose work to compare its requirements.")), 17)
	if ui.host.first_voyage120.last_payment > 0:
		ui.paragraph(body, "Last completed job released %d coins." % ui.host.first_voyage120.last_payment, 15, ui.TEAL)
	if ui.host.first_voyage120.last_fit_cost > 0:
		ui.paragraph(body, "Last fitting was installed for %d coins." % ui.host.first_voyage120.last_fit_cost, 15, ui.TEAL)
	ui.button(body, str(step.get("caption", "Choose work")), func(): _next120(ui, step), true, false)
	if not ui.host.first_voyage120.earned:
		ui.paragraph(body, "First: accept local work, sail, fight and collect. Then compare a paid fitting and choose a different job. Manual steering is optional.", 15)
	var row = _actions(body)
	ui.button(row, "Choose other work", func(): choose_work120(ui), false, false)
	ui.button(row, "Common Passage", func(): ui.StoryUI.open(ui), false, false)
	ui.button(row, "Continue sailing", ui.close_modal, false, false)
	ui.button(row, "Hide guidance for this session", func(): ui.host.set_guidance120(false); ui.close_modal(), false, false)

static func _next120(ui, step: Dictionary) -> void:
	var c = ui.host.core
	match str(step.get("action", "choose")):
		"contract": open_voyage(ui, str(step.get("id", "")))
		"fit": open_first_fit120(ui)
		"collect_job":
			ui.host.settle_voyage_job(str(step.get("id", "")), false)
			open_first120(ui)
		"job":
			var job: Dictionary = c.VoyageJobs._find(c.state, str(step.get("id", ""))).duplicate(true)
			if job.is_empty(): open_first120(ui)
			elif str(job.get("kind", "")) == "escort": c.EscortOps.review(ui, str(job.get("ownerId", "")))
			elif str(job.get("kind", "")) == "survey":
				var site: Dictionary = c.Exploration.catalog_site(c.state, str(job.get("siteId", "")))
				var level: int = int(c.state.get("exploration", {}).get("sites", {}).get(str(job.get("siteId", "")), {}).get("level", 0))
				if level < 3 and not site.is_empty() and str(site.get("regionId", "shatter_coast")) == c.Exploration.current_region(c.state): ui.CampaignUI.site(ui, str(job.get("siteId", "")))
				else: ui.VoyageUI.review_estimate(ui, job)
			elif str(job.get("kind", "")) in ui.VoyageUI.Choices.CIVILIAN_KINDS: ui.VoyageUI.review_job(ui, job)
			else: ui.VoyageUI.review_estimate(ui, job)
		"repairs":
			if not c.current_port().is_empty(): ui.open_port("Crew & repairs")
			else: ui.open_fleet()
		"escort", "freight", "survey": open_career120(ui, str(step.action))
		"campaign": ui.StoryUI.open(ui)
		"remote_work": ui.VoyageUI.open(ui)
		"ocean": ui.open_ocean064()
		_: choose_work120(ui)

static func open_first_fit120(ui, focus: String = "economy") -> void:
	if ui.host.mode != "campaign": return
	# Viewing a yard never joins a pending economy job or buys anything.
	var c = ui.host.core
	var plan: Dictionary = Guidance.first_fit120(c, focus)
	ui.modal_kind = "first_fit120"
	var body = ui.modal("Reinvest in your boat", "PAID FITTING - MONEY KEPT FOR CREW AND STORES", 960, 700)
	body.add_theme_constant_override("separation", 7)
	ui.label(body, str(plan.get("title", "Harbor fitting")), 24, ui.GOLD, true)
	ui.paragraph(body, str(plan.get("purpose", "Return to a Shatter Coast harbor to inspect a fitting.")), 16)
	if plan.has("quote"):
		ui.paragraph(body, "%s: %s" % [str(plan.get("boatName", "Flagship")), str(plan.get("effect", "Choose a different fitting."))], 16, ui.TEAL)
	if plan.has("reserveCoins"):
		ui.paragraph(body, "Bill %d coins. Purse afterward %d; keep %d for two days of crew pay, store shortfalls and current dock repairs." % [int(plan.get("cost", 0)), int(plan.get("remainingCoins", c.state.get("coins", 0))), int(plan.get("reserveCoins", 0))], 16, ui.GOLD)
	ui.paragraph(body, str(plan.get("message", "")), 15, ui.TEAL if plan.get("safe", false) else ui.GOLD)
	var actions = _actions(body)
	var held: Dictionary = plan.duplicate(true)
	ui.button(actions, "Pay %d coins and install" % int(plan.get("cost", 0)), func(): ui.host.apply_guided_fit120(held), true, false).disabled = not plan.get("safe", false) or ui.host.economy_task >= 0 or c.pending_days > 0
	ui.button(actions, "Fuel economy", func(): open_first_fit120(ui, "economy"), false, false)
	ui.button(actions, "Hull protection", func(): open_first_fit120(ui, "armor"), false, false)
	ui.button(actions, "Refresh bill", func(): open_first_fit120(ui, focus), false, false)
	if ui.host.economy_task >= 0 or c.pending_days > 0:
		ui.paragraph(body, "Harbor accounts are still being settled. Close this screen, then review a fresh bill.", 14, ui.GOLD)
	var more = _actions(body)
	ui.button(more, "All fittings", func(): ui.open_refit(str(c.state.get("flagship", ""))) if not c.current_port().is_empty() else ui.open_fleet(), false, false)
	ui.button(more, "Paid repairs and supplies", func(): ui.open_port("Crew & repairs") if not c.current_port().is_empty() else ui.open_cargo(), false, false)
	ui.button(more, "Choose next work", func(): choose_work120(ui), false, false)
	ui.button(more, "Close", ui.close_modal, false, false)
	if plan.has("quote"):
		var details = _details120(ui, body, "Materials, wages and reserve details")
		var q: Dictionary = plan.quote
		ui.paragraph(details, "Parts and yard income %d; shipwright pay %d; engineer pay %d; duty %d coins." % [int(q.get("businessIncome", 0)), int(q.get("workerWages", 0)), int(q.get("expertWages", 0)), int(q.get("tax", 0))], 14)
		for reason in q.get("reasons", []): ui.paragraph(details, str(reason), 14, ui.RED)
		ui.paragraph(details, str(plan.get("budget", {}).get("summary", "")), 14)
		ui.paragraph(details, "This is a harbor reserve. Price the next route before departure; longer trips, combat, ammunition and new damage cost more. Removed equipment stays in the boat's locker.", 14)

static func choose_work120(ui) -> void:
	if ui.host.mode != "campaign": return
	ui.modal_kind = "next_work120"
	var body = ui.modal("Choose the next voyage", "FREIGHT · CONVOYS · SURVEYS · CAMPAIGN", 940, 700)
	body.add_theme_constant_override("separation", 7)
	if ui.host.first_voyage120.last_fit_cost > 0:
		ui.paragraph(body, "Fitting installed for %d coins. Choose the work for its next departure." % ui.host.first_voyage120.last_fit_cost, 15, ui.TEAL)
	var choices: Array = [
		["escort", "Protect a loaded convoy", "Hail a nearby friendly client. Stay with its loaded carriers; protect their escape during an attack."],
		["freight", "Deliver sealed freight", "Compare the actual cargo, fee and return costs. Deliver the lot to change the destination's stock."],
		["survey", "Complete an island survey", "Fund spare crew, kits and time ashore. Report the finished survey for the sponsor's fee."],
		["campaign", "Follow Common Passage", "Follow the campaign's conversations and voyages. Local contracts remain separate paid work."]]
	for choice in choices:
		var id: String = str(choice[0])
		ui.button(body, str(choice[1]), func(): ui.host.first_voyage120.objective = id; open_career120(ui, id), false, false)
		ui.paragraph(body, str(choice[2]), 14)
	ui.button(body, "Continue sailing", ui.close_modal, false, false)

static func open_career120(ui, objective: String) -> void:
	if objective == "campaign": ui.StoryUI.open(ui); return
	if ui.host.mode != "campaign": return
	var c = ui.host.core
	ui.host.first_voyage120.objective = objective
	ui.modal_kind = "career_departure120"
	var body = ui.modal("Next paid voyage", "REQUIREMENTS - PAYMENT - DEPARTURE", 960, 720)
	if not c.home_local064():
		ui.paragraph(body,"Island harbors can fund freight and survey work. Review the actual fee, cargo and return costs before accepting. Shipyards and advanced fitting remain at Shatter Coast.",16)
		if not c.work_port070().is_empty():
			ui.button(body,"Review funded island work",func():ui.VoyageUI.open(ui),true,false)
		ui.button(body, "Plan the return", ui.open_ocean064, true, false)
		ui.button(body, "Island surveys", func(): ui.CampaignUI.islands(ui), false, false).disabled = str(c.world_view064().get("layer", "")) != "local"
		ui.button(body, "Close", ui.close_modal, false, false)
		return
	if objective == "escort":
		ui.label(body, "Protect a loaded convoy", 24, ui.GOLD, true)
		ui.paragraph(body, "Hail a nearby friendly loaded convoy for a client-funded fee. Sail with its original carriers; report at their destination after delivery.", 16)
		var report: Dictionary = ui.NavalUI.report(c.state)
		var found: bool = false
		for raw in report.get("contacts", []):
			var contact: Dictionary = raw.duplicate(true)
			var faction: String = str(contact.get("faction", ""))
			if not contact.get("current", false) or not contact.get("loaded", false) or not c.Factions.CANON_NAMES.has(faction) or c.Factions.is_hostile(c.state, faction): continue
			found = true
			ui.button(body, "Hail " + str(contact.get("name", "Convoy")), func(): ui.NavalUI.hail(ui, contact), true, false)
		if not found: ui.paragraph(body, "No friendly loaded convoy is currently in hailing range. Sail along a trading lane and watch Coastal traffic, or choose another job.", 15, ui.GOLD)
		ui.button(body, "Open coastal traffic", func(): ui.NavalUI.open(ui), false, false)
		ui.paragraph(body, "During an interception, the cargo boats must actually reach their exit. Destroying an attacker alone does not deliver the load.", 14)
	else:
		var career: String = "explorer" if objective == "survey" else "merchant"
		var plan: Dictionary = Costs.plan(c, career)
		ui.label(body, "Survey an island" if objective == "survey" else "Carry a paid freight lot", 24, ui.GOLD, true)
		var quoted: Dictionary = plan.get("quote", {})
		ui.paragraph(body, str(plan.get("firstGoal", "Review current work at a harbor.")), 16)
		if int(quoted.get("rewardCoins", 0)) > 0: ui.paragraph(body, "Completion fee %d coins; held by the sponsor until the job is complete." % int(quoted.rewardCoins), 16, ui.GOLD)
		var budget: Dictionary = plan.get("operatingCosts", {})
		ui.paragraph(body, "Keep %d coins for payroll, missing stores and current repairs. Estimated full cost, including stores used: %d coins." % [int(budget.get("additionalCashCoins", 0)) + int(c.state.get("wageArrears", 0)), int(budget.get("allowanceCoins", 0))], 15)
		for blocker in plan.get("blockers", []).slice(0, 2): ui.paragraph(body, str(blocker), 14, ui.GOLD)
		var offer_id: String = str(quoted.get("id", ""))
		if not offer_id.is_empty(): ui.button(body, "Review this job and accept", func(): _review_offer120(ui, offer_id), true, false)
		ui.button(body, "Compare all funded jobs", func(): ui.VoyageUI.open(ui), false, false)
		if objective == "survey": ui.button(body, "Island charts and shore work", func(): ui.CampaignUI.islands(ui), false, false)
		else: ui.button(body, "Compare a trade route", func(): ui.TradeUI.open(ui), false, false)
		var details = _details120(ui, body, "Crew, stores and return costs")
		for requirement in plan.get("requirements", []): ui.paragraph(details, str(requirement), 14)
		ui.paragraph(details, str(budget.get("summary", "")), 14)
	ui.button(body, "Choose different work", func(): choose_work120(ui), false, false)
	ui.button(body, "Continue sailing", ui.close_modal, false, false)

static func _review_offer120(ui, id: String) -> void:
	# Read only from a detached domain quote. The ordinary job reviewer and
	# Native acceptance still own cargo, purses, carriers and admission guards.
	var view = Costs.QuoteView.new(ui.host.core)
	for raw in view.VoyageJobs.available(view):
		if str(raw.get("id", "")) != id: continue
		var offer: Dictionary = raw.duplicate(true)
		if str(offer.get("kind", "")) in ui.VoyageUI.Choices.CIVILIAN_KINDS: ui.VoyageUI.review_job(ui, offer)
		else: ui.VoyageUI.review_estimate(ui, offer)
		return
	ui.toast("That offer changed. Review the current work board.", true)
	ui.VoyageUI.open(ui)

static func open_battle120(ui) -> void:
	if ui.host.mode != "battle" or ui.host.result_handled: return
	ui.host.first_voyage120.enabled = true
	# Opening a reference panel pauses; both exits deliberately release its modal.
	ui.host.paused = true
	ui.host.poll_battle051(0.0, true)
	ui.modal_kind = "battle_guide120"
	var body = ui.modal("Give a battle order", "PAUSED - AUTOPILOT IS OPTIONAL", 820, 560)
	ui.paragraph(body, "Close this panel to give orders while paused. Select your boat, choose Focus attack and right-click an enemy. Turn on firing arcs to see which weapons can bear.", 17)
	ui.paragraph(body, "Space resumes or pauses. Autopilot steers and fires; U switches to optional manual helm. Watch hull and water. Open Fleet & crew for the named flagship's Bail or Repair priority. X cycles flagship; selected condition can show a different boat.", 16)
	ui.paragraph(body, "Fall back changes position. Retreat fleet starts the real withdrawal; it can lose cargo and the contract may remain unfinished.", 15)
	ui.button(body, "Close and give orders", func(): ui.host.close_battle_guidance120(false), true, false)
	ui.button(body, "Resume battle", func(): ui.host.close_battle_guidance120(true), false, false)
	ui.button(body, "Hide guidance and resume", func(): ui.host.set_guidance120(false); ui.host.close_battle_guidance120(true), false, false)

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
		return "Review local contract"
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
	if not q.get("active",false) and not q.get("atSponsor",false):
		status="accept at "+str(c.port(str(candidate.get("port",""))).get("name",candidate.get("port","")))
	if q.get("routeAvailable",false) and q.get("estimatedSurplusCoins",null)!=null:
		return "%s%s%s · %s · %d coins gross (%d estimated surplus) · %s"%[prefix,choice_title,destination,hostiles,int(q.grossRewardCoins),int(q.estimatedSurplusCoins),status]
	return "%s%s%s · %s · %d coins gross · %s"%[prefix,choice_title,destination,hostiles,int(q.grossRewardCoins),status]

static func _details120(ui, parent: Node, caption: String) -> VBoxContainer:
	var details = ui.column(parent)
	details.visible = false
	var toggle = ui.button(parent, caption, func(): details.visible = not details.visible, false, false)
	parent.move_child(toggle, details.get_index())
	return details

static func open_voyage(ui, offer_id: String = "") -> void:
	var c = ui.host.core
	var offers: Array = Costs.contract_offers(c)
	var offer: Dictionary = c.state.get("activeContract", {}).duplicate(true)
	if offer.is_empty():
		for candidate in offers:
			if str(candidate.id) == offer_id or (offer_id.is_empty() and candidate.get("story", false)):
				offer = candidate; break
		if offer.is_empty() and not offers.is_empty(): offer = offers[0]
	ui.modal_kind = "voyage_review"
	var body = ui.modal("Local contract", "DESTINATION - PAYMENT - RETURN RESERVE", 980, 720)
	if offer.is_empty():
		ui.paragraph(body, "No local contract is offered here. Look for funded freight, convoy passage or survey work.", 16)
		ui.button(body, "Open the work board", func(): ui.VoyageUI.open(ui), true, false)
		ui.button(body, "Choose another career", func(): choose_work120(ui), false, false)
		ui.button(body, "Close", ui.close_modal, false, false)
		return
	var q: Dictionary = Costs.contract_quote(c, offer)
	offer = q.offer
	var budget: Dictionary = q.operatingCosts
	var e: Dictionary = q.endurance
	ui.label(body, str(offer.title), 24, ui.GOLD, true)
	ui.paragraph(body, "%s to %s" % [str(c.port(str(offer.port)).get("name", "Sponsor")), str(c.port(str(offer.targetPort)).get("name", "Destination"))], 17, ui.TEAL)
	var job_type: String = "Deliver the sealed dispatch" if offer.get("enemyHulls", []).is_empty() else "Clear %s, then collect at the destination" % ui.count_text(offer.get("enemyHulls", []).size(), "hostile boat", "hostile boats")
	ui.paragraph(body, job_type + ".", 15)
	var money_state: String = "held in escrow" if q.active else ("funded by the sponsor on acceptance" if q.funded else "sponsor cannot fund it")
	ui.paragraph(body, "Payment: %d coins, %s." % [int(q.grossRewardCoins), money_state], 17, ui.GOLD if q.funded else ui.RED)
	var available: int = int(c.state.get("coins", 0))
	var needed: int = int(budget.additionalCashCoins) + int(c.state.get("wageArrears", 0))
	ui.paragraph(body, "Purse %d coins. Keep %d for this trip, the return and %.0f spare days: %d left outside that allowance." % [available, needed, float(budget.reserveDays), available - needed], 15)
	var missing: String = "Buy %.1f food and %.1f fuel; current repair quote %d coins." % [float(budget.foodPurchase), float(budget.fuelPurchase), int(budget.repairQuoteCoins)]
	ui.paragraph(body, missing + " Load loose fuel from Hold before departure.", 14)
	if not q.blockers.is_empty(): ui.paragraph(body, str(q.blockers[0]), 15, ui.RED)
	_primary_contract_action(ui, body, c, offer, q)
	var tools = _actions(body)
	ui.button(tools, "Stores and repairs", func(): ui.open_port("Crew & repairs") if not c.current_port().is_empty() else ui.open_cargo(), false, false)
	ui.button(tools, "Choose other work", func(): choose_work120(ui), false, false)
	ui.button(tools, "Close", ui.close_modal, false, false)
	var details = _details120(ui, body, "Trip costs and other local contracts")
	ui.paragraph(details, "Estimated full voyage cost %d coins including the replacement value of stores used. Payment is %d; estimated surplus %s. Damage and ammunition can cost more." % [int(budget.allowanceCoins), int(q.grossRewardCoins), str(q.estimatedSurplusCoins) + " coins" if q.estimatedSurplusCoins != null else "unavailable"], 14)
	ui.paragraph(details, "Payroll %d coins/day; %.2f days allowed. Food aboard covers %.1f days, loaded fuel %.1f days. Existing stores are not bought again." % [int(budget.dailyWages), float(budget.days), float(e.foodDays), float(e.fuelDays)], 14)
	for blocker in q.blockers: ui.paragraph(details, str(blocker), 14, ui.RED)
	for note in Guidance.recovery_notes(c, offers, q): ui.paragraph(details, str(note), 14, ui.GOLD)
	if not q.active:
		for candidate in offers:
			if str(candidate.id) == str(offer.id): continue
			var other: Dictionary = candidate.duplicate(true)
			ui.button(details, "Review " + str(other.title), func(): open_voyage(ui, str(other.id)), false, false)
	ui.paragraph(details, "Local contracts are separate from the Common Passage campaign. Both remain available in the journal.", 13, ui.MUTED)
	VoyagePanel.connect_views(ui, details, true, false)

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
		ui.button(row,"Accept contract",func():ui.host.accept_guided_contract120(offer.duplicate(true));open_voyage(ui),true).disabled=not q.canAccept
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
	return "Open "+str({"fleet":"fleet","hold":"hold","training":"academy","supply":"expedition preparation","tooling":"machinery","workers":"workplace accounts","trade":"trade intelligence","companies":"shipping companies","law":"customs","boarding":"boarding and defenses","crises":"regional crises","exploration":"island charts","jobs":"funded work board","regional":"regional goals","fishing":"fishing crews · K board","traffic":"coastal traffic & convoy contacts","contracts":"local contracts & logbook","market":"harbor market","yard":"harbor boatyard","catalog":"boat designs"}.get(id,id))

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
	ui.button(body,"Current voyage and next action",func():open_first120(ui),true,false)
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
