extends RefCounted
const Regional=preload("res://scripts/regional_goods.gd")
const Goods=preload("res://scripts/goods.gd")
static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	ui.modal_kind="regional_goods"
	var body=ui.modal("Coastal goods & civilian trade","REAL TRADES · MATERIAL BILLS · HOUSEHOLD BUYERS",1120,850)
	ui.paragraph(body,"Useful civilian goods give harbors different trades. Production uses the actual workers and materials remaining after essential work. Households buy food first, then optional goods using a capped share of their savings. A missing luxury is a trading opportunity, with no extra hunger penalty.",16)
	for good in Regional.IDS:
		var recipe: Dictionary=Goods.ITEMS[good]
		var ingredients: Array=[]
		for key in recipe.inputs:ingredients.append("%.2f %s"%[float(recipe.inputs[key]),str(Goods.ITEMS[key].name)])
		var trades: Array=[]
		for key in recipe.labor:trades.append("%.2f %s-days"%[float(recipe.labor[key]),str(key)])
		ui.label(body,str(recipe.name),22,ui.GOLD,true)
		ui.paragraph(body,"%s · %s · %.2f coins direct labor · %.2f coins full material-and-labor basis per %s"%[", ".join(ingredients) if not ingredients.is_empty() else "Paid local harvest",", ".join(trades),Goods.labor_cost(recipe.labor),Goods.cost(good),str(recipe.unit)],14)
	ui.rule(body)
	for p in c.state.ports:
		var r: Dictionary=Regional.report(p)
		if r.has("error"):continue
		ui.label(body,str(p.name),21,ui.TEAL,true)
		var name: String=str(Goods.ITEMS[r.specialty].name) if not str(r.specialty).is_empty() else "Imports civilian goods"
		ui.paragraph(body,"%s · %s coins paid in regional wages · %s coins actually spent by households"%[name,ui.money(int(r.lastWages)),ui.money(int(r.lastSpent))],15)
		for good in Regional.IDS:
			ui.paragraph(body,"%s: %.2f on hand · %.2f made · %.2f consumed"%[str(Goods.ITEMS[good].name),float(r.stocks[good]),float(r.lastProduction.get(good,0)),float(r.lastConsumption.get(good,0))],14,ui.MUTED)
	ui.button(body,"Close",ui.close_modal,true)
