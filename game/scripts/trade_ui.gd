extends RefCounted
const Intel=preload("res://scripts/trade_intel.gd")
static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	ui.modal_kind="trade_intel"
	var body=ui.modal("Trade chart & harbor shortages","DATED QUOTES · REAL INVENTORIES · FINITE BUYERS",1080,820)
	ui.paragraph(body,"Estimates use your own cargo and holds, a navigable round trip, wages, fuel and food. Purchase quantities preserve two payroll days. Prices and buyer funds below are from actual visits; remote quotes age and sales can change before you arrive.",16)
	for r in Intel.opportunities(c):
		var offer: Dictionary=r
		ui.rule(body)
		ui.label(body,"%s: %d %s → %s"%["Cargo aboard" if r.mode=="carried" else "Local purchase",r.qty,c.Goods.ITEMS[r.good].name,c.port(r.toPort).name],22,ui.GOLD,true)
		ui.paragraph(body,"Estimated net %s coins · revenue %s − purchase %s − voyage %s"%[ui.money(r.netProfit),ui.money(r.revenue),ui.money(r.purchaseCost),ui.money(r.tripCost)],16,ui.TEAL if r.netProfit>0 else ui.RED)
		ui.paragraph(body,"Round trip %.2f days · wages %d · fuel %d · food %d · quote %d days old · %.0f%% uncertainty"%[r.days,r.wageCost,r.fuelCost,r.foodCost,r.quoteAge,r.uncertainty*100],14)
		var flags: PackedStringArray=[]
		for key in r.riskFlags:
			if r.riskFlags[key]:flags.append(str(key).capitalize())
		if not flags.is_empty():ui.paragraph(body,"Watch: "+", ".join(flags),14,ui.RED)
		ui.button(body,"Chart this destination",func():ui.host.sail_to(offer.toPort);ui.close_modal())
	ui.rule(body)
	for p in c.state.ports:
		var report: Dictionary=Intel.report(c,p.id)
		if not report.seen:continue
		ui.label(body,"%s · observed day%d · %d days old"%[p.name,report.observedDay,report.age],22,ui.GOLD,true)
		ui.paragraph(body,"Recorded buyer purse %s coins. %s"%[ui.money(report.businessFunds),report.message],14)
		for good in ["food","timber","iron","fuel","supplies","engines"]:
			ui.paragraph(body,"%s: %d lots · %s · buy %d / sell %d coins"%[c.Goods.ITEMS[good].name,report.stocks.get(good,0),report.scarcity.get(good,{}).get("band","unknown"),report.buy.get(good,0),report.sell.get(good,0)],14)
	if c.state.tradeIntel.observations.is_empty():ui.paragraph(body,"Visit a harbor market to record your first quotes. Unvisited prices are unknown.",18)
	ui.rule(body)
	ui.paragraph(body,"Blockades depend on living, crewed and supplied fleets. Defenders can contest them; withdrawing, fuel starvation or defeat lifts them. Every convoy delivery changes the destination stock that workers and yards can use.",15)
