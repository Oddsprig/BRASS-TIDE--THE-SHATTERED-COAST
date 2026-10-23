extends RefCounted
const Ops=preload("res://scripts/company_ops.gd")
const Goods=preload("res://scripts/goods.gd")
static func result(ui,r: Dictionary) -> void:
	ui.host.respond(r)
	if r.ok:ui.host.save_game(false)
	open(ui)
static func number(body,value: float,maximum: float,width: float=150):
	var control=SpinBox.new();control.min_value=0;control.max_value=maximum;control.step=1;control.value=value;control.custom_minimum_size=Vector2(width,42);body.add_child(control);return control
static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	Ops.ensure(c)
	ui.modal_kind="shipping_companies"
	var body=ui.modal("Your shipping companies","REAL BOATS · CAPITAL · ROUTES · ACCOUNTS",1160,880)
	ui.paragraph(body,"Charter spare boats and their existing crews. Keep one seaworthy flagship and enough hold space for your actual cargo. A company sails the real coast, pays its crew and master, buys shared inventory and bears real damage or losses. Capital, carried stock and earned profit have separate accounts.",16)
	for b in Ops.api(c).list(c):
		var id: String=b.ownerId
		var o: Dictionary=c.fleet_owner(id)
		ui.label(body,str(o.name)+" · "+str(b.status).capitalize(),22,ui.GOLD,true)
		ui.paragraph(body,"%s ↔ %s · %s · %d afloat / %d hull records · %s coins operating purse · %s coins wage arrears"%[str(c.port(b.home).name),str(c.port(b.destination).name),str(Goods.ITEMS[b.good].name),o.boats.filter(func(boat):return not boat.sunk).size(),o.boats.size(),ui.money(int(o.coins)),ui.money(int(o.wageArrears))],16)
		ui.paragraph(body,"Sales %s − material cost %s − operation/loss costs %s = %s coins net result. Capital deposited %s; %s lots of commercial inventory remain at %s coins basis. Working stores are expensed as consumed; transferred hull losses use their stated standard production value."%[ui.money(int(b.revenue)),ui.money(int(b.cogs)),ui.money(int(b.operating)),ui.money(int(b.netProfit)),ui.money(int(b.invested)),str(snappedf(float(b.basisQty),0.01)),ui.money(int(b.basisCost))],15)
		if b.status=="collected":continue
		ui.paragraph(body,str(o.get("reason","Awaiting route decision.")),14,ui.MUTED)
		var row=ui.row(body)
		ui.button(row,"Recall physically",func():result(ui,Ops.recall(c,id)))
		ui.button(row,"Meet fleet: add1,000 coins",func():result(ui,Ops.capital(c,id,1000)))
		ui.button(row,"Meet fleet: pay arrears",func():result(ui,Ops.pay_arrears(c,id)))
		ui.button(body,"Collect boats, cargo and purses at home",func():result(ui,Ops.collect(c,id)))
	ui.rule(body)
	var home: Dictionary=c.current_port()
	if home.is_empty():
		ui.paragraph(body,"Visit a legal harbor to charter a company.",16)
	else:
		ui.label(body,"Charter a fleet from this harbor",23,ui.TEAL,true)
		var selected: Dictionary={}
		var quote_label=ui.paragraph(body,"Choose boats to preview voyage costs.",15,ui.MUTED)
		var destinations=OptionButton.new();destinations.custom_minimum_size=Vector2(300,44)
		var port_ids: Array=[]
		for p in c.state.ports:
			if p.id==home.id:continue
			port_ids.append(str(p.id));destinations.add_item(str(p.name))
		var goods=OptionButton.new();goods.custom_minimum_size=Vector2(300,44)
		var good_ids: Array=Goods.ITEMS.keys()
		for good in good_ids:goods.add_item(str(Goods.ITEMS[good].name))
		var route_row=ui.row(body);route_row.add_child(destinations);route_row.add_child(goods)
		var refresh=func():
			var ids: Array=selected.keys().filter(func(uid):return bool(selected[uid]))
			quote_label.text=str(Ops.quote(c,ids,str(port_ids[destinations.selected]),str(good_ids[goods.selected])).message)
		for boat in c.state.fleet:
			var uid: String=boat.uid
			var check=CheckBox.new();check.text="%s · %.0f crew · %.0f hold space"%[str(boat.name),float(boat.crew),float(boat.spec.cargo)];body.add_child(check)
			check.toggled.connect(func(on):selected[uid]=on;refresh.call())
		destinations.item_selected.connect(func(_index):refresh.call());goods.item_selected.connect(func(_index):refresh.call())
		ui.paragraph(body,"Operating capital / maximum buy price / minimum sell price",14)
		var price_row=ui.row(body)
		var capital=number(price_row,minf(12000,float(c.state.coins)),float(c.state.coins))
		var buy=number(price_row,Economy_price(c,home,good_ids[0],"buy"),1000000)
		var sell=number(price_row,0,1000000)
		goods.item_selected.connect(func(_index):buy.value=Economy_price(c,home,str(good_ids[goods.selected]),"buy"))
		ui.paragraph(body,"Maximum commercial lots / protected operating reserve / route risk allowance",14)
		var limits_row=ui.row(body)
		var quantity=number(limits_row,20,100000)
		var reserve=number(limits_row,3000,100000000)
		var risk=OptionButton.new();risk.add_item("Avoid observed blockades");risk.add_item("Accept blockade risk");limits_row.add_child(risk)
		ui.button(body,"Charter selected actual boats",func():
			var ids: Array=selected.keys().filter(func(uid):return bool(selected[uid]))
			var limits: Dictionary={"buyMax":int(buy.value),"sellMin":int(sell.value),"maxCargo":float(quantity.value),"reserve":int(reserve.value),"risk":0.9 if risk.selected==1 else 0.4}
			result(ui,Ops.create(c,ids,str(port_ids[destinations.selected]),str(good_ids[goods.selected]),int(capital.value),limits)))
		refresh.call()
	ui.button(body,"Close",ui.close_modal,true)
static func Economy_price(c,p: Dictionary,good: String,side: String) -> int:
	return c.Economy.price(p,good,side)
