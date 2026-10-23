extends RefCounted
const Home=preload("res://scripts/home_harbor.gd")
static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	c.HomeOps.ensure(c)
	ui.modal_kind="home_harbor"
	var body=ui.modal("Home harbors & shore businesses","PAID SPACE · REAL STAFF · OPERATING CAPITAL",1090,820)
	ui.paragraph(body,"A warehouse stores owned cargo and includes eight small berth slots while its two staff are paid. Public berths cost 28 coins per slot/day: 25 watch and maintenance, 3 registry. Larger hulls use two slots. A business has its own purse; its workers leave the town's available workforce.",16)
	var p: Dictionary=c.current_port()
	if not p.is_empty():
		var space: Dictionary=c.HomeOps.room(c,p.id)
		ui.paragraph(body,"%s: private berths %d / %d · public berths %d / %d"%[p.name,space.privateUsed,space.privateCapacity,space.publicUsed,space.publicCapacity],16,ui.GOLD)
		for value in ["warehouse","salvage_yard","workshop"]:
			var kind: String=value
			var q: Dictionary=Home.quote(c,kind,p.id)
			ui.rule(body)
			ui.label(body,Home.KINDS[kind].name,23,ui.GOLD,true)
			ui.paragraph(body,str(q.message),15)
			if q.ok:
				ui.paragraph(body,"Setup %s + opening float %s coins · %d staff · %d coins/day · hold %.0f"%[ui.money(q.setupCost),ui.money(q.workingCapitalDeposit),q.staffTotal,q.dailyWages,q.capacity],15)
				ui.paragraph(body,"Parts %d · ordinary wages %d · expert wages %d · margin %d · duty %d"%[q.materialCost,q.setupOrdinaryWages,q.setupExpertWages,q.margin,q.duty],14)
			ui.button(body,"Establish paid business",func():act(ui,Home.establish(c,kind,p.id)),true).disabled=not q.ok or not q.get("affordable",false)
	ui.rule(body)
	ui.label(body,"Your shore books",26,ui.GOLD,true)
	for row in Home.list_businesses(c.state):
		var b: Dictionary=row
		ui.rule(body)
		ui.label(body,b.name+" · "+c.port(b.homePort).name,23,ui.GOLD,true)
		ui.paragraph(body,"Purse %s · daily pay %d · arrears %d · %.1f / %.1f stored · %s"%[ui.money(b.coins),b.dailyWages,b.arrearsHousehold+b.arrearsExpert,b.storedWeight,b.capacity,"work paused" if b.paused else "staff paid"],16,ui.RED if b.paused else ui.TEAL)
		ui.paragraph(body,"Revenue %d − staff pay %d − sold material basis %d. Coin reserve %d. Deposited goods use standard production-cost valuation; contributed capital is not earned profit."%[b.revenue,b.wagesPaid,b.get("costOfSales",0),b.reserve],14)
		for worker in b.employees:ui.paragraph(body,"%s · %s · %d coins/day"%[worker.name,worker.occupation,worker.wage],13)
		var local: bool=not p.is_empty() and p.id==b.homePort
		if not local:
			ui.button(body,"Chart home harbor",func():ui.host.sail_to(b.homePort);ui.close_modal())
			continue
		var options=ui.row(body)
		var goods=OptionButton.new()
		for good in c.Goods.ITEMS:goods.add_item(c.Goods.ITEMS[good].name);goods.set_item_metadata(goods.item_count-1,good)
		options.add_child(goods)
		var qty=SpinBox.new();qty.min_value=0.01;qty.max_value=400;qty.step=0.01;qty.value=1;options.add_child(qty)
		ui.button(options,"Store owned cargo",func():act(ui,Home.transfer_goods(c,b.id,str(goods.get_item_metadata(goods.selected)),qty.value,"in")))
		ui.button(options,"Load aboard",func():act(ui,Home.transfer_goods(c,b.id,str(goods.get_item_metadata(goods.selected)),qty.value,"out")))
		var finances=ui.row(body)
		ui.button(finances,"Add 1,000 coins",func():act(ui,Home.capital(c,b.id,1000)))
		ui.button(finances,"Draw 100 earned coins",func():act(ui,Home.dividend(c,b.id,100)))
		if b.kind!="warehouse":ui.button(body,"Retain output for fleet" if b.get("autoSell",true) else "Sell output locally",func():var actual: Dictionary=Home._business(c.state,b.id);actual.autoSell=not actual.autoSell;ui.host.save_game(false);open(ui))
		for good in b.inventory:
			if float(b.inventory[good])>0:ui.paragraph(body,"%s · %.2f stored"%[c.Goods.ITEMS[good].name,b.inventory[good]],14)
	for boat in c.state.fleet:
		if int(boat.get("berthArrears",0))<=0:continue
		var uid: String=boat.uid
		ui.button(body,"Settle %s berth · %d coins"%[boat.name,boat.berthArrears],func():act(ui,c.HomeOps.pay_arrears(c,uid)))

static func act(ui,result: Dictionary) -> void:
	ui.host.respond(result)
	ui.host.core.Manifest.allocate(ui.host.core.state)
	ui.host.save_game(false)
	open(ui)
