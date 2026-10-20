extends RefCounted
const Goods = preload("res://scripts/goods.gd")
const Money = preload("res://scripts/money.gd")

static func boat_quote(ui, id: String):
	var h: Dictionary = ui.host.core.hull(id)
	var q: Dictionary = ui.host.core.ship_quote(h)
	ui.modal_kind = "boat_quote"
	var body = ui.modal(h.name,"THE YARD'S BILL OF MATERIALS & PAID WORK")
	ui.paragraph(body,"%.2f m long × %.2f m beam. Every material includes its upstream labor. This yard adds hull assembly, fitting, paid supervision, upkeep, margin and registry duty."%[q.lengthM,q.beamM],16)
	ui.label(body,"Commission %s cash · Ready hull %s cash"%[ui.money(q.commissionPrice),ui.money(q.readyPrice)],25,ui.GOLD,true)
	ui.paragraph(body,"%.1f worker-days in this yard, approximately %.1f calendar days with the quoted team. Material shortages, employment elsewhere or missing supervisors delay the work."%[q.workerDays,q.estimatedDays],15)
	for line in q.lineItems:
		var row = ui.row(body)
		var text = ui.label(row,str(line.label),15,ui.TEXT)
		text.custom_minimum_size.x = 410
		ui.label(row,"%.2f %s × %s"%[line.qty,line.unit,ui.money(line.unitCost)],13,ui.MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ui.label(row,"%s cash"%ui.money(line.cost),16,ui.GOLD)
	ui.rule(body)
	ui.paragraph(body,"Materials %s · Workmanship %s · Supervising experts %s\nYard upkeep %s · Margin %s · Duty %s"%[ui.money(q.materialCost),ui.money(q.laborCost),ui.money(q.supervisionCost),ui.money(q.overhead),ui.money(q.margin),ui.money(q.tax)],16,ui.TEAL)
	ui.paragraph(body,"The ready hull adds %s cash for paid watchkeeping, careening and their margin/duty. Crew advances and working stores are purchased separately. A sailor's standard wage is 100 bronze cash per day."%ui.money(q.readyStorageCost),15)
	ui.button(body,"Back to boatyard",func():ui.open_port("Boatyard"),true)

static func good_recipe(ui, good: String):
	var item: Dictionary = Goods.ITEMS[good]
	ui.modal_kind = "recipe"
	var body = ui.modal(item.name,"INPUTS, OCCUPATIONS & EMBODIED LABOR",850,730)
	ui.paragraph(body,"One %s is an abstract trading lot. Its production cost includes the work in every input; local stock and demand then affect the market price."%item.unit,16)
	ui.label(body,"Base production cost: %s cash"%ui.money(ceili(Goods.cost(good))),30,ui.GOLD,true)
	ui.eyebrow(body,"PURCHASED INPUTS")
	if item.inputs.is_empty():
		ui.paragraph(body,"Local extraction or harvest. Workers must still be hired and paid.")
	for ingredient in item.inputs:
		var row = ui.row(body)
		ui.label(row,"%.2f × %s"%[item.inputs[ingredient],Goods.ITEMS[ingredient].name],17).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ui.label(row,"%s cash embodied"%ui.money(ceili(item.inputs[ingredient]*Goods.cost(ingredient))),15,ui.TEAL)
		var key: String = ingredient
		ui.button(row,"Trace input",func():good_recipe(ui,key))
	ui.eyebrow(body,"DIRECT PAID WORK")
	for occupation in item.labor:
		ui.label(body,"%s · %.2f worker-days × %d cash/day = %s cash"%[str(occupation).capitalize(),item.labor[occupation],Goods.WAGES[occupation],ui.money(ceili(item.labor[occupation]*Goods.WAGES[occupation]))],17,ui.TEXT)
	ui.paragraph(body,"All levels together: %.2f worker-days. Wages move from business funds into workers' and specialists' purses; material purchase money moves to its supplier."%Goods.full_labor_days(good),16)
	ui.button(body,"Back to market",func():ui.open_port("Market"),true)

static func settlement(ui,body,p: Dictionary):
	ui.label(body,"The settlement's purses",25,ui.GOLD,true)
	ui.paragraph(body,"Businesses pay people for real work. Residents spend their wages, taxes go to the treasury, and public purchases pay businesses. A broke employer cannot conjure another payroll.",16)
	for entry in [["Business funds","cash"],["Workers' shared purse","householdPurse"],["Specialists' shared purse","expertPurse"],["Government treasury","governmentPurse"]]:
		var row = ui.row(body)
		ui.label(row,entry[0],17).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ui.label(row,"%s bronze cash"%ui.money(p[entry[1]]),18,ui.GOLD)
	ui.paragraph(body,"Civilian workforce %d · Employed %d · Public workers %d · Idle %d\nLast payroll %s cash · Wages taxed %s cash"%[p.workforce,p.workers,p.publicWorkers,p.availableWorkers,ui.money(p.lastPayroll.total),ui.money(p.lastPayroll.tax)],15,ui.TEAL)
	ui.paragraph(body,"Today's yard commitments: %.1f workers, including %.1f specialists. Free for other service: %.1f workers."%[p.get("_yardWorkersUsed",0),p.get("_yardSpecialistsUsed",0),maxf(0.0,p.availableWorkers-p.get("_yardWorkersUsed",0))],14)
	for occupation in p.get("employedByOccupation",{}):
		var count = p.employedByOccupation[occupation]
		if count > 0:
			ui.label(body,"%s · %d workers · %d cash/day"%[str(occupation).capitalize(),count,Goods.WAGES.get(occupation,100)],14,ui.MUTED)
	ui.rule(body)
	ui.label(body,"Physical stock & production",24,ui.GOLD,true)
	var shortage = ", ".join(p.get("shortages",[]))
	ui.paragraph(body,"Shortages: "+("none" if shortage.is_empty() else shortage),15,ui.RED if not shortage.is_empty() else ui.MUTED)
	for good in Goods.ITEMS:
		var row = ui.row(body)
		ui.label(row,Goods.ITEMS[good].name,15).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ui.label(row,"%.1f in stock · %.1f made last day"%[p.stocks[good],p.lastProduction.get(good,0.0)],14,ui.MUTED)
	ui.rule(body)
	ui.label(body,"Recent transfers",24,ui.GOLD,true)
	for line in p.get("ledger",[]).slice(-12):
		ui.paragraph(body,"%s · %s → %s · %s cash"%[str(line.get("type","Transfer")).capitalize(),line.get("from",""),line.get("to",""),ui.money(line.get("coins",0))],13)
	ui.button(body,"Coastal fleet owners & costs",func():fleet_accounts(ui))
	ui.paragraph(body,"Coast-wide circulating cash: %s · Coin ledger difference: %d"%[ui.money(Money.total(ui.host.core.state)),Money.total(ui.host.core.state)-int(ui.host.core.state.coinSupply)],13,ui.TEAL)

static func fleet_accounts(ui):
	ui.modal_kind = "accounts"
	var body = ui.modal("Coastal fleet accounts","OWNERS · HOME PORTS · OPERATING COSTS")
	for owner in ui.host.core.state.fleetOwners:
		var costs = ui.host.core.Fleets.upkeep(owner)
		var home: Dictionary = ui.host.core.port(owner.homePort)
		var replacement: int = 0
		for boat in owner.boats:
			if not boat.sunk:
				replacement += int(ui.host.core.ship_quote(ui.host.core.hull(boat.type),home).readyPrice)
		var food_cost: int = ceili(costs.food*ui.host.Economy.price(home,"food"))
		var fuel_cost: int = ceili(costs.fuel*ui.host.Economy.price(home,"fuel"))
		ui.label(body,"%s · %s"%[owner.name,ui.host.core.port(owner.homePort).name],22,ui.GOLD,true)
		ui.paragraph(body,"%s · %d boats · Owner %s cash · Sailors %s cash\nDaily wages %s · Owed wages %s · Morale %.0f / 100"%[str(owner.kind).capitalize(),owner.boats.filter(func(b):return not b.sunk).size(),ui.money(owner.coins),ui.money(owner.crewPurse),ui.money(costs.wages),ui.money(owner.wageArrears),owner.morale],15)
		ui.paragraph(body,"Hull replacement value at home: %s cash\nDaily rations %.2f bales (about %s cash from sailors) · Fuel %.2f drums (about %s cash from owner). Actual prices and repair costs depend on local stock and damage."%[ui.money(replacement),costs.food,ui.money(food_cost),costs.fuel,ui.money(fuel_cost)],14,ui.TEAL)
		if not owner.log.is_empty():
			ui.paragraph(body,str(owner.log[0]),13)
		ui.rule(body)
	ui.button(body,"Back to harbor",func():ui.open_port("Economy"),true)
