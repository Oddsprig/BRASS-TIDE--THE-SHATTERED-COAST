extends RefCounted
const Intel=preload("res://scripts/trade_intel.gd")

static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	ui.modal_kind="trade_intel"
	var body=ui.modal("Trade chart & harbor needs","DATED VISITS · FINITE BUYERS · ESTIMATES",1080,820)
	ui.paragraph(body,"Compare a round trip before committing cargo. Remote quotes, needs and buyer purses are visit records; prices, access and available funds can change before arrival.",16)
	var actions=ui.row(body)
	if not c.current_port().is_empty():ui.button(actions,"Return to Market · buy / sell",func():ui.open_port("Market"))
	ui.button(actions,"Cargo & load working stores",ui.open_cargo)
	var offers: Array=Intel.opportunities(c)
	if offers.is_empty():
		ui.paragraph(body,"No cargo estimate available yet",23,ui.GOLD)
		ui.paragraph(body,"Visit another harbor and open its Market to record dated prices, stocks, input needs and buyer funds. Then compare them here with cargo aboard or a purchase at your current harbor. Unvisited markets have no remote quotes.",16)
		ui.paragraph(body,"If you already have quotes, check traveling crew, usable hold, saleable cargo, purchase funds and a navigable route. A missing estimate is not a promise that trade is unprofitable.",14)
	else:
		ui.eyebrow(body,"Top estimates · ranked by nominal round-trip net")
		for i in range(mini(3,offers.size())):_opportunity(ui,body,offers[i])
		if offers.size()>3:
			var more=ui.column(body)
			more.visible=false
			for i in range(3,offers.size()):_opportunity(ui,more,offers[i])
			var more_toggle=ui.button(body,"More observed estimates (%d)"%(offers.size()-3),func():more.visible=not more.visible)
			body.move_child(more_toggle,more.get_index())
	ui.rule(body)
	var quotes=ui.column(body)
	quotes.visible=false
	var seen: int=0
	for p in c.state.ports:
		var report: Dictionary=Intel.report(c,p.id)
		if not report.seen:continue
		seen+=1
		ui.paragraph(quotes,"%s · visit day %d · %d days old · buyer purse %s coins"%[p.name,report.observedDay,report.age,ui.money(report.businessFunds)],17,ui.GOLD)
		ui.paragraph(quotes,report.message,14)
		for good in report.stocks:
			var need: Dictionary=report.get("needs",{}).get(good,{})
			var purpose: String=""
			if float(need.get("observedNeed",0))>0:purpose=" · needs %.1f: %s"%[need.observedNeed,need.needPurpose]
			ui.paragraph(quotes,"%s: %d lots · buy %d / sell %d coins%s"%[c.Goods.ITEMS[good].name,report.stocks[good],report.buy.get(good,0),report.sell.get(good,0),purpose],14)
		ui.rule(quotes)
	if seen>0:
		var quotes_toggle=ui.button(body,"Recorded market quotes & input needs (%d)"%seen,func():quotes.visible=not quotes.visible)
		body.move_child(quotes_toggle,quotes.get_index())
	else:
		ui.paragraph(body,"No observations recorded. Open a harbor Market to start your quote book.",16,ui.GOLD)
	ui.paragraph(body,"Deliveries add real local stock for paid workers and yards; other inputs and wages are still required. Blockades, hostile access and depleted working stores can stop a voyage. Review preparation before explicitly charting a course.",14)

static func market_summary(ui,body: Node,port_id: String) -> void:
	var report: Dictionary=Intel.report(ui.host.core,port_id)
	var details=ui.column(body)
	details.visible=false
	var count: int=0
	for good in report.get("needs",{}):
		var need: Dictionary=report.needs[good]
		if float(need.get("observedNeed",0))<=0:continue
		ui.paragraph(details,"Visit day %d · local stock gap %.1f %s · %s"%[report.observedDay,need.observedNeed,ui.host.core.Goods.ITEMS[good].name,need.needPurpose],14,ui.GOLD)
		count+=1
		if count>=2:break
	ui.paragraph(details,"Selling adds to this harbor's working stock; buying removes it. Production still needs paid labor and its other inputs.",13)
	var toggle=ui.button(body,"Local input needs & supply consequences",func():details.visible=not details.visible)
	body.move_child(toggle,details.get_index())

static func review_destination(ui,port_id: String) -> void:
	if ui.host.core.port(port_id).is_empty():
		ui.toast("This destination is unavailable.",true)
		return
	ui.host.selected_port=port_id
	ui.CampaignUI.expedition(ui)

static func _opportunity(ui,body: Node,r: Dictionary) -> void:
	var c=ui.host.core
	var destination: String=str(r.toPort)
	var name: String=str(c.port(destination).name)
	ui.rule(body)
	ui.paragraph(body,"%s · %d %s → %s"%["Cargo aboard" if r.mode=="carried" else "Local purchase",r.qty,c.Goods.ITEMS[r.good].name,name],22,ui.GOLD)
	ui.paragraph(body,"Gross sale %s · nominal net %s · conservative net %s coins"%[ui.money(r.revenue),ui.money(r.netProfit),ui.money(r.conservativeNetProfit)],18,ui.TEAL if r.conservativeNetProfit>0 and r.preparationReady else ui.GOLD)
	ui.paragraph(body,"Purchase %s + voyage %s coins · price uncertainty margin %s (%.0f%%)."%[ui.money(r.purchaseCost),ui.money(r.tripCost),ui.money(r.uncertaintyMargin),r.uncertainty*100],14)
	ui.paragraph(body,"Visit day %d · %d days old · observed sale quote %d coins/lot · %.2f days round trip"%[r.observedDay,r.quoteAge,r.sellQuote,r.days],14)
	var limits: String="Quantity capped by saleable cargo aboard and recorded buyer funds. Historical cargo purchase cost is excluded from aboard net."
	if r.mode!="carried":limits="Quantity capped by local stock, purchase funds, usable hold and recorded buyer funds. Preparation can reduce safe cargo."
	ui.paragraph(body,limits,14)
	if r.observedNeed>0:
		ui.paragraph(body,"Need at visit: %.1f lots · %s"%[r.observedNeed,r.needPurpose],15,ui.TEXT)
	else:
		ui.paragraph(body,"No specific input need recorded for this cargo. The observed buyer purse limits sales; demand and payment are not guaranteed.",14)
	var risks: PackedStringArray=[]
	var names: Dictionary={"blockade":"blockade reported","stale":"dated price uncertainty","shortFuel":"working fuel short","noPath":"no navigable route","fuelUnpriced":"fuel cost unavailable","hostileWaters":"hostile access","shortFood":"ration allowance short","shortFunding":"departure funds short","preparationHold":"hold allowance exceeded"}
	for key in r.riskFlags:
		if r.riskFlags[key]:risks.append(str(names.get(key,str(key).capitalize())))
	if not r.preparationReady:risks.append("preparation gaps · review before buying")
	if not risks.is_empty():ui.paragraph(body,"Cautions: "+"; ".join(risks),14,ui.RED)
	ui.button(body,"Select %s & review voyage"%name,func():review_destination(ui,destination))
	var next: String="Next: review stores and payroll, explicitly chart the course in preparation, then use the destination Market's Sell control."
	if r.mode!="carried":next="Next: return to Market, choose a quantity and Buy using the existing controls. Recheck this estimate and preparation, then explicitly chart the course. Sell at the destination Market."
	ui.paragraph(body,next,14)
	var details=ui.column(body)
	details.visible=false
	ui.paragraph(details,"Nominal costs: purchase %s + voyage %s (wages %s, fuel %s, food %s) coins. Net excludes contingency, arrears and preparation funding below."%[ui.money(r.purchaseCost),ui.money(r.tripCost),ui.money(r.wageCost),ui.money(r.fuelCost),ui.money(r.foodCost)],14)
	ui.paragraph(details,"Conservative estimate subtracts %s coins for price uncertainty (%.0f%%). %s This is price sensitivity, not a probability or a guaranteed minimum."%[ui.money(r.uncertaintyMargin),r.uncertainty*100,r.uncertaintyBasis],14)
	if r.mode=="carried":
		ui.paragraph(details,"Saleable aboard %d · recorded buyer limit %d lots (%s coins)."%[r.localStockLimit,r.buyerLiquidity,ui.money(r.businessFunds)],14)
	else:
		ui.paragraph(details,"Quantity limits: %s. Local stock %d · affordable %d · hold %d · recorded buyer limit %d lots (%s coins). Buy quote %d coins/lot."%[r.quantityLimitReason,r.localStockLimit,r.affordabilityLimit,r.holdLimit,r.buyerLiquidity,ui.money(r.businessFunds),r.buyQuote],14)
	ui.paragraph(details,"Funding before departure %s · short %s coins. Preparation %s · %.1f contingency days / %s coins · owed wages %s. These are funding requirements, not extra deductions from nominal net."%[ui.money(r.fundingRequired),ui.money(r.fundingShortfall),ui.money(r.preparationCost),r.reserveDays,ui.money(r.contingencyCost),ui.money(r.wageArrears)],14)
	ui.paragraph(details,"Allowance: %.1f food required / %.1f short · %.1f working fuel short · %.1f hold after food / %.1f overload. %.1f loose fuel is cargo; load it into each boat's own tank through Cargo."%[r.foodRequired,r.foodShortfall,r.fuelShortfall,r.payloadAfterFood,r.allowanceOverload,r.looseFuel],14)
	for boat: Dictionary in r.boatFuel:
		if float(boat.fuelShortfall)>0 or float(boat.tankShortfall)>0:
			ui.paragraph(details,"%s: %.1f fuel loaded / %.1f required · %.1f short · %.1f beyond its tank"%[boat.name,boat.loadedFuel,boat.fuelRequired,boat.fuelShortfall,boat.tankShortfall],14,ui.RED)
	for warning in r.preparationWarnings:ui.paragraph(details,str(warning),14,ui.RED)
	var toggle=ui.button(body,"Costs, price uncertainty & quantity limits",func():details.visible=not details.visible)
	body.move_child(toggle,details.get_index())
