extends RefCounted
const Home=preload("res://scripts/home_harbor.gd")
const HomeOps=preload("res://scripts/home_ops.gd")
const Costs=preload("res://scripts/career_costs.gd")
const Politics=preload("res://scripts/politics.gd")
const Goods=preload("res://scripts/goods.gd")

class ReviewView extends Costs.QuoteView:
	func fail(message: String) -> Dictionary:return {"ok":false,"message":message}

static func review(c) -> Dictionary:
	var v=ReviewView.new(c)
	HomeOps.ensure(v)
	var p: Dictionary=v.current_port()
	var quotes: Array=[]
	if not p.is_empty():
		for kind in ["warehouse","salvage_yard","workshop"]:
			var q: Dictionary=Home.quote(v,kind,str(p.id))
			q.kind=kind;quotes.append(q)
	var businesses: Array=[]
	for b in v.state.get("businesses",[]):businesses.append(Home.business_view(v.state,str(b.id)))
	return {"view":v,"port":p,"room":HomeOps.room(v,str(p.id)) if not p.is_empty() else {},"quotes":quotes,"businesses":businesses,"pendingDays":int(c.pending_days),"publishedDay":int(c.state.get("econDay",1))}

## The same pure book summary is used beside the selected regional goal.
static func book(ui,body: Node,b: Dictionary) -> void:
	ui.paragraph(body,"Purse %s · daily pay %d · wages paid %d · %d paid working days · arrears %d · %s"%[ui.money(int(b.coins)),int(b.dailyWages),int(b.wagesPaid),int(b.paidWorkDays),int(b.arrears),"working" if b.working else "work stalled"],15,ui.TEAL if b.working else ui.RED)
	ui.paragraph(body,"Labor: %s. %s %s"%[str(b.laborNotice),str(b.stallReason),str(b.resumeReason)],14)
	ui.paragraph(body,"Next payroll shortfall %d coins · %.1f / %.1f stored · reserve %d. %s"%[int(b.payrollShortfall),float(b.storedWeight),float(b.capacity),int(b.reserve),str(b.productionReason)],14)
	for material in b.materials:
		ui.paragraph(body,"%s: %.2f held / %.2f per output lot · short %.2f"%[Goods.ITEMS[str(material.good)].name,float(material.held),float(material.perLot),float(material.shortfall)],13)
	ui.paragraph(body,"Revenue %d − staff pay %d − sold material basis %d − other expenses %d. Capital paid in %d is separate from income; stored goods keep their owned basis."%[int(b.revenue),int(b.wagesPaid),int(b.get("costOfSales",0)),int(b.get("otherExpenses",0)),int(b.capitalIn)],14)

static func open(ui) -> void:
	var account: Dictionary=review(ui.host.core)
	var c=account.view
	ui.modal_kind="home_harbor"
	var body=ui.modal("Home harbors & shore businesses","PAID SPACE · REAL STAFF · OPERATING CAPITAL",1090,820)
	ui.paragraph(body,"A warehouse stores owned cargo and includes eight small berth slots while its two staff are paid. Public berths cost 28 coins per slot/day: 25 watch and maintenance, 3 registry. Larger hulls use two slots. A business has its own purse; its workers leave the town's available workforce.",16)
	ui.paragraph(body,"Published day %d · %d calendar days pending. Reviewing or closing pays nothing; an explicit action refreshes and checks the current books."%[int(account.publishedDay),int(account.pendingDays)],14)
	ui.button(body,"Decline / return to chart",ui.close_modal,false,false)
	var p: Dictionary=account.port
	if not p.is_empty():
		var space: Dictionary=account.room
		ui.paragraph(body,"%s: private berths %d / %d · public berths %d / %d"%[p.name,space.privateUsed,space.privateCapacity,space.publicUsed,space.publicCapacity],16,ui.GOLD)
		for value in account.quotes:
			var q: Dictionary=value
			var kind: String=str(q.kind)
			ui.rule(body)
			ui.label(body,Home.KINDS[kind].name,23,ui.GOLD,true)
			ui.paragraph(body,str(q.message),15)
			if q.ok:
				ui.paragraph(body,"Setup %s + opening float %s coins · %d staff · %d coins/day · hold %.0f"%[ui.money(q.setupCost),ui.money(q.workingCapitalDeposit),q.staffTotal,q.dailyWages,q.capacity],15)
				ui.paragraph(body,"Parts %d · ordinary wages %d · expert wages %d · margin %d · duty %d"%[q.materialCost,q.setupOrdinaryWages,q.setupExpertWages,q.margin,q.duty],14)
			ui.button(body,"Establish paid business",func():act(ui,"establish",kind,str(p.id)),true,false).disabled=not q.ok or not q.get("affordable",false)
	ui.rule(body)
	ui.label(body,"Your shore books",26,ui.GOLD,true)
	for row in account.businesses:
		var b: Dictionary=row
		ui.rule(body)
		ui.label(body,b.name+" · "+c.port(b.homePort).name,23,ui.GOLD,true)
		book(ui,body,b)
		for worker in b.employees:ui.paragraph(body,"%s · %s · %d coins/day"%[worker.name,worker.occupation,worker.wage],13)
		var local: bool=not p.is_empty() and p.id==b.homePort
		if not local:
			ui.button(body,"Chart home harbor",func():act(ui,"chart",str(b.id)),false,false)
			continue
		var options=ui.row(body)
		var goods=OptionButton.new()
		for good in Goods.ITEMS:goods.add_item(Goods.ITEMS[good].name);goods.set_item_metadata(goods.item_count-1,good)
		options.add_child(goods)
		var qty=SpinBox.new();qty.min_value=0.01;qty.max_value=400;qty.step=0.01;qty.value=1;options.add_child(qty)
		ui.button(options,"Store owned cargo",func():act(ui,"store",str(b.id),str(goods.get_item_metadata(goods.selected)),float(qty.value)),false,false)
		ui.button(options,"Load aboard",func():act(ui,"load",str(b.id),str(goods.get_item_metadata(goods.selected)),float(qty.value)),false,false)
		var finances=ui.row(body)
		ui.button(finances,"Add 1,000 coins",func():act(ui,"capital",str(b.id),"",1000),false,false)
		ui.button(finances,"Draw 100 earned coins",func():act(ui,"dividend",str(b.id),"",100),false,false)
		if b.kind!="warehouse":ui.button(body,"Retain output for fleet" if b.get("autoSell",true) else "Sell output locally",func():act(ui,"autosell",str(b.id)),false,false)
		for good in b.inventory:
			if float(b.inventory[good])>0:ui.paragraph(body,"%s · %.2f stored"%[Goods.ITEMS[good].name,b.inventory[good]],14)
	for boat in c.state.fleet:
		if int(boat.get("berthArrears",0))<=0:continue
		var uid: String=boat.uid
		ui.button(body,"Settle %s berth · %d coins"%[boat.name,boat.berthArrears],func():act(ui,"arrears",uid),false,false)

static func act(ui,action: String,id: String="",value: String="",amount: float=0.0) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	var result: Dictionary={}
	match action:
		"establish":result=Home.establish(c,id,value)
		"store","load":result=Home.transfer_goods(c,id,value,amount,"in" if action=="store" else "out")
		"capital":result=Home.capital(c,id,int(amount))
		"dividend":result=Home.dividend(c,id,int(amount))
		"arrears":result=HomeOps.pay_arrears(c,id)
		"autosell","chart":
			var b: Dictionary=Home._business(c.state,id)
			if b.is_empty():result=c.fail("That business is no longer in your books.")
			elif action=="chart":
				ui.host.sail_to(str(b.homePort));ui.close_modal();return
			else:
				var permission: Dictionary=Politics.permit(c,"service")
				if not permission.ok:result=permission
				elif str(c.current_port().get("id",""))!=str(b.homePort):result=c.fail("Visit this business's actual home harbor to change sales policy.")
				else:b.autoSell=not bool(b.get("autoSell",true));result=c.ok("Local sales policy updated; no goods sold yet.")
		_:return
	ui.host.respond(result)
	if result.get("ok",false):
		c.Manifest.allocate(c.state);ui.host.save_game(false)
	open(ui)
