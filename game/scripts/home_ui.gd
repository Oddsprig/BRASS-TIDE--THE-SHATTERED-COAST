extends RefCounted
const Home=preload("res://scripts/home_harbor.gd")
const HomeOps=preload("res://scripts/home_ops.gd")
const Costs=preload("res://scripts/career_costs.gd")
const Politics=preload("res://scripts/politics.gd")
const Goods=preload("res://scripts/goods.gd")

class ReviewView extends Costs.QuoteView:
	var remote_port_id: String=""
	func _init(c):
		super._init(c)
		if c!=null and c.has_method("work_port070"):
			var wp: Dictionary=c.work_port070()
			if wp.is_empty():
				var imp_port: String=str(c.state.get("territorial076",{}).get("improvement",{}).get("portId",""))
				if not imp_port.is_empty():wp=preload("res://scripts/territorial076.gd")._remote_work_port(c,imp_port)
			remote_port_id=str(wp.get("id",""))
	func work_port070() -> Dictionary:return port(remote_port_id)
	func fail(message: String) -> Dictionary:return {"ok":false,"message":message}

static func review(c) -> Dictionary:
	var v=ReviewView.new(c)
	HomeOps.ensure(v)
	var home_p: Dictionary=v.current_port()
	var p: Dictionary=Home._service_port(v,true)
	var is_remote: bool=home_p.is_empty() and not p.is_empty()
	var quotes: Array=[]
	if not p.is_empty():
		for kind in ["warehouse","salvage_yard","workshop"]:
			var q: Dictionary=Home.quote(v,kind,str(p.id))
			q.kind=kind;quotes.append(q)
	var businesses: Array=[]
	for b in v.state.get("businesses",[]):businesses.append(Home.business_view(v.state,str(b.id)))
	return {"view":v,"port":p,"isRemotePort084":is_remote,"room":HomeOps.room(v,str(home_p.id)) if not home_p.is_empty() else {},"quotes":quotes,"businesses":businesses,"pendingDays":int(c.pending_days),"publishedDay":int(c.state.get("econDay",1))}

## The same pure book summary is used beside the selected regional goal.
static func book(ui,body: Node,b: Dictionary) -> void:
	var summary=ui.column(body)
	summary.name="BusinessSummary"
	summary.add_theme_constant_override("separation",5)
	var values=GridContainer.new()
	values.columns=4
	values.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	values.add_theme_constant_override("h_separation",16)
	summary.add_child(values)
	for metric in [["PURSE",ui.money(int(b.coins))+" coins"],["DAILY PAY",ui.money(int(b.dailyWages))+" coins"],["UNPAID WAGES",ui.money(int(b.arrears))+" coins"],["PAID WORK DAYS",str(int(b.paidWorkDays))]]:
		var cell=ui.column(values)
		cell.add_theme_constant_override("separation",0)
		ui.label(cell,str(metric[0]),14,ui.MUTED)
		ui.paragraph(cell,str(metric[1]),22,ui.RED if str(metric[0])=="UNPAID WAGES" and int(b.arrears)>0 else ui.TEXT)
	if b.working:
		ui.paragraph(summary,"Working · last paid shift day %d"%int(b.lastPaidWorkDay),16,ui.TEAL)
	else:
		ui.paragraph(summary,"Stalled: "+str(b.stallReason),16,ui.RED)
	ui.paragraph(summary,"Next: "+str(b.resumeReason),15,ui.TEXT)
	ui.paragraph(summary,"Next payroll shortfall %d coins · %.1f / %.1f stored · reserve %d"%[int(b.payrollShortfall),float(b.storedWeight),float(b.capacity),int(b.reserve)],15,ui.RED if int(b.payrollShortfall)>0 else ui.MUTED)
	if str(b.kind)!="warehouse":ui.paragraph(summary,str(b.productionReason),15,ui.TEXT)
	ui.paragraph(summary,"Revenue %d − staff pay %d − sold material basis %d − other expenses %d"%[int(b.revenue),int(b.wagesPaid),int(b.get("costOfSales",0)),int(b.get("otherExpenses",0))],15)
	ui.paragraph(summary,"Capital paid in %d is separate from income; stored goods keep their owned basis."%int(b.capitalIn),14)

## Local disclosure only: construct every child now, without joining or saving.
static func _details(ui,body: Node,caption: String,expanded: bool=false) -> VBoxContainer:
	var details=ui.column(body)
	details.add_theme_constant_override("separation",6)
	details.visible=expanded
	var toggle=ui.button(body,caption,func():details.visible=not details.visible,false,false)
	toggle.toggle_mode=true
	toggle.button_pressed=expanded
	body.move_child(toggle,details.get_index())
	return details

static func book_details(ui,body: Node,b: Dictionary) -> void:
	var details=_details(ui,body,"Staff, materials & stored goods")
	ui.paragraph(details,"Labor: "+str(b.laborNotice),15)
	if str(b.kind)=="warehouse":ui.paragraph(details,str(b.productionReason),15)
	for material in b.materials:
		ui.paragraph(details,"%s: %.2f held / %.2f per output lot · short %.2f"%[Goods.ITEMS[str(material.good)].name,float(material.held),float(material.perLot),float(material.shortfall)],15)
	for worker in b.employees:ui.paragraph(details,"%s · %s · %d coins/day"%[worker.name,worker.occupation,worker.wage],15)
	for good in b.inventory:
		if float(b.inventory[good])>0:ui.paragraph(details,"%s · %.2f stored"%[Goods.ITEMS[good].name,b.inventory[good]],15)

static func open(ui) -> void:
	var account: Dictionary=review(ui.host.core)
	var c=account.view
	ui.modal_kind="home_harbor"
	var body=ui.modal("Home harbors & shore businesses","PAID SPACE · REAL STAFF · OPERATING CAPITAL",1090,850)
	body.name="HomeHarborBody"
	body.add_theme_constant_override("separation",10)
	var heading=ui.row(body)
	ui.label(heading,"Captain's purse · %s coins"%ui.money(int(c.state.coins)),20,ui.GOLD).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	ui.button(heading,"Decline / return to chart",ui.close_modal,false,false)
	ui.paragraph(body,"Published day %d · %d calendar days pending · review/close pays nothing; actions refresh and recheck the books."%[int(account.publishedDay),int(account.pendingDays)],14)
	var p: Dictionary=account.port
	var is_remote: bool=bool(account.get("isRemotePort084",false))
	if not p.is_empty():
		if is_remote:
			ui.paragraph(body,"%s: charted remote harbor berth · warehouse development and owned warehouse storage operate here; boat storage berths, salvage yards and workshops remain Shatter Coast home-only."%str(p.get("name",p.get("id",""))),16,ui.GOLD)
		else:
			var space: Dictionary=account.room
			ui.paragraph(body,"%s: private berths %d / %d · public berths %d / %d"%[p.name,space.privateUsed,space.privateCapacity,space.publicUsed,space.publicCapacity],16,ui.GOLD)
	for boat in c.state.fleet:
		if int(boat.get("berthArrears",0))<=0:continue
		var uid: String=boat.uid
		ui.button(body,"Settle %s berth · %d coins"%[boat.name,boat.berthArrears],func():act(ui,"arrears",uid),false,false)
	ui.label(body,"Your shore books",23,ui.GOLD,true)
	if account.businesses.is_empty():ui.paragraph(body,"No owned shore business. Review a local charter below to establish one with paid staff, materials and capital.",16)
	for row in account.businesses:
		var b: Dictionary=row
		var business=ui.column(body)
		business.name="Business_"+str(b.id)
		business.add_theme_constant_override("separation",8)
		ui.rule(business)
		ui.label(business,b.name+" · "+c.port(b.homePort).name,21,ui.GOLD,true)
		book(ui,business,b)
		var local: bool=not p.is_empty() and p.id==b.homePort
		if not local:
			ui.button(business,"Chart home harbor",func():act(ui,"chart",str(b.id)),false,false)
			book_details(ui,business,b)
			continue
		var options=ui.row(business)
		options.name="CargoActions"
		var goods=OptionButton.new()
		for good in Goods.ITEMS:goods.add_item(Goods.ITEMS[good].name);goods.set_item_metadata(goods.item_count-1,good)
		options.add_child(goods)
		var qty=SpinBox.new();qty.min_value=0.01;qty.max_value=400;qty.step=0.01;qty.value=1;options.add_child(qty)
		ui.button(options,"Store owned cargo",func():act(ui,"store",str(b.id),str(goods.get_item_metadata(goods.selected)),float(qty.value)),false,false)
		ui.button(options,"Load aboard",func():act(ui,"load",str(b.id),str(goods.get_item_metadata(goods.selected)),float(qty.value)),false,false)
		var finances=ui.row(business)
		finances.name="FinanceActions"
		ui.button(finances,"Add 1,000 coins",func():act(ui,"capital",str(b.id),"",1000),false,false)
		ui.button(finances,"Draw 100 earned coins",func():act(ui,"dividend",str(b.id),"",100),false,false)
		if b.kind!="warehouse":ui.button(business,"Retain output for fleet" if b.get("autoSell",true) else "Sell output locally",func():act(ui,"autosell",str(b.id)),false,false)
		book_details(ui,business,b)
	ui.paragraph(body,"Public berths cost 28 coins per slot/day: 25 watch and maintenance, 3 registry. Larger hulls use two slots.",14)
	if not p.is_empty():
		var charters=_details(ui,body,"New business charters & setup costs",account.businesses.is_empty())
		charters.name="BusinessCharters"
		ui.paragraph(charters,"A warehouse stores owned cargo and includes eight small berth slots while its two staff are paid. Each business has its own purse; its workers leave the town's available workforce.",15)
		for value in account.quotes:
			var q: Dictionary=value
			var kind: String=str(q.kind)
			ui.rule(charters)
			ui.label(charters,Home.KINDS[kind].name,21,ui.GOLD,true)
			if q.ok:
				ui.paragraph(charters,"Setup %s + opening float %s coins · %d staff · %d coins/day · hold %.0f"%[ui.money(q.setupCost),ui.money(q.workingCapitalDeposit),q.staffTotal,q.dailyWages,q.capacity],17,ui.TEXT)
				ui.paragraph(charters,"Parts %d · ordinary wages %d · expert wages %d · margin %d · duty %d"%[q.materialCost,q.setupOrdinaryWages,q.setupExpertWages,q.margin,q.duty],15)
			else:ui.paragraph(charters,str(q.message),15)
			if is_remote and kind=="warehouse":
				ui.paragraph(charters,"Remote harbor warehouses require two paid berth-development days with carried machinery and materials before setup.",15,ui.TEAL)
				ui.button(charters,"Open Harbor Development",func():load("res://scripts/regional_ui.gd").open(ui,"harbor",str(p.id)),true,false)
			else:
				ui.button(charters,"Establish paid business",func():act(ui,"establish",kind,str(p.id)),true,false).disabled=is_remote or not q.ok or not q.get("affordable",false)

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
				var docked: Dictionary=Home._service_port(c,true)
				var permission: Dictionary=Politics.permit(c,"service","",docked)
				if not permission.ok:result=permission
				elif str(docked.get("id",""))!=str(b.homePort):result=c.fail("Visit this business's actual home harbor to change sales policy.")
				else:b.autoSell=not bool(b.get("autoSell",true));result=c.ok("Local sales policy updated; no goods sold yet.")
		_:return
	ui.host.respond(result)
	if result.get("ok",false):
		c.Manifest.allocate(c.state);ui.host.save_game(false)
	open(ui)
