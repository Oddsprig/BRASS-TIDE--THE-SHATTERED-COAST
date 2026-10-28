extends SceneTree
## Root-only proof candidate. SOURCE lane C never executes this script.
## One Main/world/nav, declared finite opening fixture, then ordinary paid flow.
const Money=preload("res://scripts/money.gd")
const Home=preload("res://scripts/home_harbor.gd")
const Ops=preload("res://scripts/regional_ops.gd")
const Rules=preload("res://scripts/regional_rules.gd")
const Orders=preload("res://scripts/naval_orders.gd")
const Fleets=preload("res://scripts/fleet_economy.gd")
const Navigation=preload("res://scripts/navigation.gd")
const Economy=preload("res://scripts/economy.gd")
const Goods=preload("res://scripts/goods.gd")
const RegionalUI=preload("res://scripts/regional_ui.gd")
const HomeUI=preload("res://scripts/home_ui.gd")
const BUDGET_SECONDS: float=40.0
const ORIGIN: String="brass_haven"
const DESTINATION: String="kelp_reach"
const WATCH: String="patrol-2"
const TRADER: String="patrol-1"
const THREAT: String="patrol-0"
var scene
var c
var checks: int=0
var failures: int=0
var began_us: int=0
var supply: int=0
var census: float=0.0
var steps: int=0
var joined_days: int=0
var encounters: Dictionary={}
var receipt: Dictionary={"status":"UNFINISHED","phases":[],"distance":0.0,"returnDistance":0.0,"grossSales":0,"steps":0,"stall":{},"resumed":{}}

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL regional voyage: "+message)

func elapsed() -> float:return float(Time.get_ticks_usec()-began_us)/1000000.0

func within_budget() -> bool:
	if elapsed()<BUDGET_SECONDS-2.0:return true
	check(false,"40-second internal fixture budget exhausted; remaining voyage is unproved")
	receipt.status="BLOCKED_BUDGET";return false

func phase(label: String) -> void:
	var item: Dictionary={"name":label,"seconds":elapsed(),"day":float(c.state.day),"econDay":int(c.state.econDay),"steps":steps,"joinedDays":joined_days}
	receipt.phases.append(item);print("regional061 phase ",JSON.stringify(item))

func people() -> float:
	# Numerical custody census only; encounter receipts supply actual deaths.
	var n: float=float(c.state.get("regionalCrises",{}).get("lostPeople",0))+float(c.state.get("boardingLostPeople",0))+float(c.state.get("captives",0))
	for p in c.state.ports:
		n+=float(p.workforce)+float(p.get("defenses",{}).get("crew",0))
		for job in p.get("training",{}).get("jobs",[]):n+=float(job.reservedWorkers)
	for b in c.state.fleet+c.state.get("boardingPrizes",[]):n+=float(b.crew)
	for owner in c.state.fleetOwners:
		for b in owner.boats:n+=float(b.crew)
	for b in c.state.get("businesses",[]):n+=float(b.employees.size())
	for job in c.state.get("yardProjects",[]):n+=float(job.get("workers",0))
	for job in c.state.get("regionalCrises",{}).get("jobs",[]):n+=float(job.n)
	for job in c.state.get("voyageJobs",[]):n+=float(job.get("passengers",{}).get("n",0))
	return n

func collect_encounters() -> void:
	var retained: Array=c.state.get("navalAi",{}).get("encounters",[])
	check(retained.size()<24,"bounded actual encounter history has not pruned loss evidence")
	for event in retained:
		var key: String=JSON.stringify([event.day,event.a,event.b])
		if encounters.has(key):continue
		var valid: bool=true
		for field in ["crewLostA","crewLostB"]:
			var value=event.get(field)
			valid=valid and (value is int or value is float) and is_finite(float(value)) and float(value)>=0.0
		check(valid,"actual NPC encounter records finite nonnegative crewLostA/B")
		if valid:encounters[key]=event.duplicate(true)

func join_calendar() -> void:
	var pending: int=int(c.pending_days)
	scene.sync_economy();joined_days+=pending;collect_encounters()
	check(c.pending_days==0 and scene.economy_task<0 and Money.total(c.state)==supply,"ordinary calendar publication joins its workers and conserves every purse")

func observe_recovery() -> void:
	var op: Dictionary=Ops.selected_status(c)
	var plan: Dictionary=op.get("currentPlan",{})
	if not plan.is_empty() and not plan.get("ready",true) and not encounters.is_empty() and receipt.stall.is_empty():
		receipt.stall={"day":float(c.state.day),"plan":plan.duplicate(true),"patrol":owner_book(WATCH)}
	if not receipt.stall.is_empty() and plan.get("ready",false) and receipt.resumed.is_empty():
		receipt.resumed={"day":float(c.state.day),"plan":plan.duplicate(true),"patrol":owner_book(WATCH)}

func advance(seconds: float,join: bool=true,returning: bool=false) -> bool:
	if not within_budget():return false
	var before: Dictionary=c.state.position.duplicate()
	c.step(seconds);steps+=1;collect_encounters();observe_recovery()
	var distance: float=c.distance(before,c.state.position)
	receipt.distance=float(receipt.distance)+distance
	if returning:receipt.returnDistance=float(receipt.returnDistance)+distance
	if join and c.pending_days>0:join_calendar();observe_recovery()
	if c.events.any(func(event):return str(event.get("kind","")) in ["encounter","defeat"]):
		var interrupted: Array=c.events.filter(func(event):return str(event.get("kind","")) in ["encounter","defeat"])
		receipt.interruption={"day":float(c.state.day),"position":c.state.position.duplicate(),"events":interrupted.duplicate(true)}
		receipt.status="BLOCKED_PLAYER_ENCOUNTER";check(false,"a live player encounter/defeat interrupts this proof; no completed voyage claim: "+JSON.stringify(receipt.interruption));return false
	return true

func sail(destination: String,returning: bool=false) -> bool:
	var route: Dictionary=c.chart_course(c.port_position(destination),destination)
	check(route.ok,"actual water course to "+destination+": "+str(route.get("message","")))
	if not route.ok:return false
	for index in range(120):
		if c.state.path.is_empty():break
		if not advance(1.0,true,returning):return false
	var arrived: bool=c.state.path.is_empty() and str(c.current_port().get("id",""))==destination
	check(arrived,"actual sailing reaches "+destination+" without position/arrival edits")
	if arrived:c.TradeFlow.observe(c)
	return arrived

func gear_uids(boat: Dictionary) -> Array:
	var ids: Array=[]
	for item in boat.get("moduleCondition",{}).get("items",{}).values():ids.append(str(item.itemUid))
	ids.sort()
	return ids

func owner_book(id: String) -> Dictionary:
	var owner: Dictionary=c.fleet_owner(id)
	return {"id":id,"coins":int(owner.get("coins",0)),"crewPurse":int(owner.get("crewPurse",0)),"arrears":int(owner.get("wageArrears",0)),"delivered":float(owner.get("tradeDelivered",0)),"cargo":owner.get("cargo",{}).duplicate(true),"boats":owner.get("boats",[]).map(func(b):return {"uid":str(b.uid),"crew":float(b.crew),"fuel":float(b.fuel),"ammo":float(b.ammo),"supplies":float(b.supplies),"hp":float(b.hp),"items":gear_uids(b)})}

func snapshot() -> String:
	return JSON.stringify({"state":c.state,"data":c.data,"events":c.events,"pending":c.pending_days,"economyTask":scene.economy_task})

func button_in(node: Node,caption: String) -> Button:
	if node is Button and str(node.text)==caption:return node
	for child in node.get_children():
		var found: Button=button_in(child,caption)
		if found!=null:return found
	return null

func pending_reviews() -> void:
	check(c.pending_days>0 and scene.economy_task<0,"review begins with a genuine unjoined calendar payroll")
	var before: String=snapshot()
	for panel in ["regional","home_harbor"]:
		if panel=="regional":RegionalUI.open(scene.ui)
		else:HomeUI.open(scene.ui)
		check(snapshot()==before and scene.ui.modal_kind==panel,"opening "+panel+" is pure with pending payroll")
		var close: Button=button_in(scene.ui.overlay,"×")
		check(close!=null,"actual shared header X exists for "+panel)
		if close!=null:close.pressed.emit()
		check(snapshot()==before and not scene.ui.modal_open,"actual "+panel+" header X declines without joining payroll")
		if panel=="regional":RegionalUI.open(scene.ui)
		else:HomeUI.open(scene.ui)
		var decline: Button=button_in(scene.ui.overlay,"Decline / return to chart")
		check(decline!=null,"explicit pure decline exists for "+panel)
		if decline!=null:decline.pressed.emit()
		check(snapshot()==before and not scene.ui.modal_open,"reopen/decline "+panel+" changes no time, book, purse or pending day")

func point_on(path: Array,distance: float) -> Dictionary:
	var left: float=distance
	for index in range(1,path.size()):
		var length: float=c.distance(path[index-1],path[index])
		if left<=length:
			var t: float=left/maxf(0.0001,length)
			return {"x":lerpf(float(path[index-1].x),float(path[index].x),t),"y":lerpf(float(path[index-1].y),float(path[index].y),t)}
		left-=length
	return path[-1].duplicate()

func ammo_rounds() -> float:
	var n: float=0.0
	for p in c.state.ports:n+=(float(p.stocks.get("ammo",0))+float(p.get("publicStores",{}).get("ammo",0)))*Goods.ROUNDS_PER_CASE
	n+=float(c.state.cargo.get("ammo",0))*Goods.ROUNDS_PER_CASE
	for b in c.state.fleet:n+=float(b.ammo)
	for owner in c.state.fleetOwners:
		n+=float(owner.cargo.get("ammo",0))*Goods.ROUNDS_PER_CASE
		for b in owner.boats:n+=float(b.ammo)
	return n

func opening_fixture() -> bool:
	# Root approved e9f33410/098ad60e: controlled INITIAL locality, not naturally
	# seeded world progression. This is the ONLY fixture position/store editing.
	# No crew, hull, physical item, cargo or coin is born here.
	var watch: Dictionary=c.fleet_owner(WATCH)
	var merchant: Dictionary=c.fleet_owner(TRADER)
	var threat: Dictionary=c.fleet_owner(THREAT)
	check(not watch.is_empty() and not merchant.is_empty() and not threat.is_empty(),"three existing canonical owners are present")
	if watch.is_empty() or merchant.is_empty() or threat.is_empty():return false
	var provenance: Dictionary={"merchant":owner_book(TRADER),"originalHome":str(merchant.homePort),"tradeGood":str(merchant.tradeGood),"paidLoadedQty":float(merchant.tradeCargo)}
	check(float(merchant.tradeCargo)>0 and float(merchant.cargo.get(str(merchant.tradeGood),0))>=float(merchant.tradeCargo),"merchant carries its physically purchased opening load; no cargo fixture creates it")
	if float(merchant.tradeCargo)<=0:return false
	var original_watch_home: String=str(watch.homePort)
	var ammunition: float=ammo_rounds()
	var redistribution: Array=[]
	for b in watch.boats:
		var surplus: float=float(b.ammo)-18.0
		check(surplus>=0,"existing patrol magazine contains the declared18-round opening reserve")
		if surplus<0:return false
		var source: Dictionary=c.port(original_watch_home)
		var before: float=float(source.stocks.ammo)
		source.stocks.ammo=before+surplus/float(Goods.ROUNDS_PER_CASE)
		b.ammo=18.0
		redistribution.append({"boatUid":str(b.uid),"sourcePort":original_watch_home,"originalRounds":18.0+surplus,"remainingRounds":18.0,"returnedCases":surplus/float(Goods.ROUNDS_PER_CASE),"stockBefore":before,"stockAfter":float(source.stocks.ammo)})
	check(absf(ammo_rounds()-ammunition)<0.0000001,"opening exact rounds/cases redistribution conserves every ammunition unit without rounding")
	check(Money.move(c.port("shatter_spire"),"governmentPurse",c.state,"coins",50000,"Declared finite regional061 opening capital",c.state.moneyLog),"opening capital transfers from an existing counted purse")
	var crew_savings: int=ceili(float(Fleets.upkeep(watch).food)*3.0)*Economy.price(c.port(ORIGIN),"food","buy")+1000
	check(Money.move(watch,"coins",watch,"crewPurse",crew_savings,"Declared existing patrol crew savings allocation",c.state.moneyLog),"initial patrol savings allocate existing coins, not earned wages")
	c.Factions.adjust(c.state,"compact",25,"Declared controlled opening Friendly legal standing, not earned progression")
	c.state.campaignFocus={"fromPort":ORIGIN,"toPort":DESTINATION,"portId":ORIGIN,"peaceA":"compact","peaceB":"raiders"}
	watch.homePort=ORIGIN;watch.route=[ORIGIN,DESTINATION]
	merchant.homePort=ORIGIN;merchant.route=[ORIGIN,DESTINATION]
	var clearance: float=10.0
	for owner in [watch,merchant,threat]:
		for b in owner.boats:clearance=maxf(clearance,Navigation.hull_clearance(float(b.spec.size)))
	var start: Dictionary=Navigation.harbor_approach(c.nav,c.port(ORIGIN),clearance,40.0)
	var end: Dictionary=Navigation.harbor_approach(c.nav,c.port(DESTINATION),clearance,40.0)
	check(not start.is_empty() and not end.is_empty(),"declared staged actors have real water approaches at their actual hull clearance")
	if start.is_empty() or end.is_empty():return false
	var path: Array=c.cached_path(start,end,clearance)
	check(path.size()>=2,"one existing navigation supplies the controlled coastal staging path")
	if path.size()<2:return false
	for row in [[watch,0.0],[threat,140.0],[merchant,450.0]]:
		var owner: Dictionary=row[0]
		var actor: Dictionary=Orders.find_patrol(c.state,str(owner.id))
		var point: Dictionary=point_on(path,float(row[1]))
		actor.x=point.x;actor.y=point.y;actor.from=ORIGIN;actor.to=DESTINATION;actor.progress=0.0;actor.holding=false
		owner.progress=0.0;owner.atPort=ORIGIN if float(row[1])==0.0 else ""
		c.set_patrol_course(actor,point,c.port(DESTINATION))
		Orders.build_order(c.state,owner,"deliver" if owner.kind=="trader" else "raid" if owner.kind=="raider" else "patrol",DESTINATION,"Declared controlled opening local route; later travel is earned.")
	c.NavalAI.observe(c.state)
	var before: Dictionary=provenance.merchant
	check(owner_book(TRADER).cargo==before.cargo and float(merchant.tradeCargo)==float(provenance.paidLoadedQty) and owner_book(TRADER).boats==before.boats,"staging preserves the merchant's purchased load, stores, crew, hull and part UIDs")
	check(Money.total(c.state)==supply and people()==census,"opening staging preserves all coins and numerical people")
	var validated: Dictionary=c.SaveValidation.validate(JSON.parse_string(JSON.stringify(c.state)),c.data)
	check(validated.ok,"declared opening state passes parsed save validation: "+str(validated.get("message","")))
	if not validated.ok:return false
	receipt.opening={"scenario":"Controlled initial local composition; not naturally seeded world progression or traffic balance","capitalTransfer":50000,"merchantProvenance":provenance,"ammunitionRedistribution":redistribution,"watch":owner_book(WATCH),"threat":owner_book(THREAT),"playerCoins":int(c.state.coins),"playerFuel":float(c.state.fleet[0].fuel),"playerFood":float(c.state.cargo.food),"playerItems":gear_uids(c.state.fleet[0]),"econDay":int(c.state.econDay),"crew":int(c.crew_count()),"originStocks":c.port(ORIGIN).stocks.duplicate(true),"destinationStocks":c.port(DESTINATION).stocks.duplicate(true),"standing":c.Factions.standing(c.state,"compact")}
	return true

func paid_voyage() -> void:
	var watch: Dictionary=c.fleet_owner(WATCH)
	var food: int=ceili(float(Fleets.upkeep(watch).food)*3.0)
	var food_stock: float=float(c.port(ORIGIN).stocks.food)
	var savings: int=int(watch.crewPurse)
	check(Fleets._purchase(watch,c.port(ORIGIN),"food",food,true,false,c)==food and int(watch.crewPurse)<savings and float(c.port(ORIGIN).stocks.food)==food_stock-food,"existing docked patrol savings buy real crew provisions before departure")
	var position: Dictionary=Orders.find_patrol(c.state,WATCH).duplicate(true)
	var treasury: int=int(c.port(ORIGIN).governmentPurse)
	var purse: int=int(watch.coins)
	var begun: Dictionary=Ops.start(c,"corridor")
	check(begun.ok and int(begun.funded)>0 and str(begun.ownerId)==WATCH,"Friendly actual sponsor funds its existing patrol against a live local threat")
	if not begun.ok or str(begun.ownerId)!=WATCH:return
	receipt.funding=c.state.regionalCampaigns.fundedRoutes.duplicate(true)
	receipt.completionId=str(begun.completionId)
	check(int(c.port(ORIGIN).governmentPurse)==treasury-int(begun.funded) and int(watch.coins)==purse+int(begun.funded) and Money.total(c.state)==supply,"once-only grant is the exact sponsor debit and original owner credit")
	check(c.distance(position,Orders.find_patrol(c.state,WATCH))<0.000001,"operation planning redirects without relocating the actual patrol")
	var op: Dictionary=Ops.selected_status(c)
	check(str(op.currentPlan.get("targetOwnerId",""))==THREAT and str(op.currentPlan.get("convoyOwnerId",""))==TRADER and op.currentPlan.ready,"actual loaded trader and live hostile enter a paid route-and-return-ready watch plan")
	check(not Ops.start(c,"corridor").ok and c.state.regionalCampaigns.fundedRoutes==receipt.funding,"repeated start cannot grant twice")
	var construction: Dictionary=Home.establish(c,"warehouse",ORIGIN)
	check(construction.ok,"actual materials/setup labor and staff deposit establish the local warehouse")
	if not construction.ok:return
	receipt.businessId=str(construction.business.id);receipt.setupBill=int(construction.cost)
	check(Ops.start(c,"harbor").ok,"harbor goal snapshots this real business before paid working days")
	check(c.trade(ORIGIN,"timber",12,"buy").ok,"captain pays for twelve actual local timber lots within the real hold")
	var sold_open: int=int(c.state.coins)
	var sold: Dictionary=c.trade(ORIGIN,"timber",6,"sell")
	check(sold.ok,"six actual owned lots sell into the local buyer's stock")
	receipt.grossSales=int(c.state.coins)-sold_open
	var unpaid: int=int(c.state.coins)
	var delivered: float=float(c.state.regionalFacts.deliveries.get(ORIGIN,0))
	var stock: float=float(c.port(ORIGIN).stocks.timber)
	check(Ops.contribute(c,"harbor","timber",6).ok and int(c.state.coins)==unpaid and float(c.port(ORIGIN).stocks.timber)==stock+6 and float(c.state.regionalFacts.deliveries.get(ORIGIN,0))==delivered,"six separate donations move real goods once, are unpaid and add no sold-delivery fact")
	var harbor: Dictionary=Rules.harbor_view(c.state,c.state.regionalCampaigns.operations.harbor)
	check(float(harbor.deliveredLots)==6 and float(harbor.donatedLots)==6 and float(harbor.harborLots)==12 and int(harbor.staffDays)==0,"6 sold +6 separately donated =12, with no fabricated working days")
	var protected: String=JSON.stringify(c.state.regionalFacts)
	check(not c.trade(ORIGIN,"timber",1,"sell").ok and not Ops.contribute(c,"harbor","timber",1).ok and JSON.stringify(c.state.regionalFacts)==protected,"repeated exhausted cargo cannot duplicate sales, donation or delivery credit")
	check(c.trade(ORIGIN,"timber",1,"buy").ok,"one distinct paid cargo lot is loaded for the actual coastal voyage")
	protected=JSON.stringify(c.state.regionalFacts)
	check(not c.trade(DESTINATION,"timber",1,"sell").ok and JSON.stringify(c.state.regionalFacts)==protected,"unvisited destination cannot receive a false remote sale/passage")
	receipt.initialView=selected_evidence()
	phase("funded watch, paid warehouse, distinct sold/donated lots")
	if not advance(1.0):return
	check(encounters.values().any(func(e):return WATCH in [str(e.a),str(e.b)] and THREAT in [str(e.a),str(e.b)]),"real local NPC combat resolves the staged live patrol/threat pair")
	check(not receipt.stall.is_empty() and receipt.stall.patrol.boats.any(func(b):return float(b.ammo)<18.0),"actual combat ammunition use causes genuine readiness/recovery shortage")
	if not advance(maxf(0.001,(floorf(float(c.state.day))+1.0-float(c.state.day))*c.DAY_SECONDS+0.001),false):return
	pending_reviews()
	var business: Dictionary=Home.business_view(c.state,str(receipt.businessId))
	var capital: int=int(business.capitalIn)
	var wages: int=int(business.wagesPaid)
	HomeUI.open(scene.ui)
	var fund: Button=button_in(scene.ui.overlay,"Add 1,000 coins")
	check(fund!=null,"real explicit capital action exists on local books")
	if fund==null:return
	var pending: int=int(c.pending_days)
	fund.pressed.emit();joined_days+=pending;collect_encounters();observe_recovery()
	business=Home.business_view(c.state,str(receipt.businessId))
	check(pending==1 and c.pending_days==0 and scene.economy_task<0 and int(business.capitalIn)==capital+1000 and int(business.wagesPaid)==wages+int(business.dailyWages) and int(business.paidWorkDays)==1,"explicit action joins real payroll first, then revalidates and transfers capital once")
	scene.ui.close_modal()
	phase("actual combat, pending-day pure panels and paid resume")
	if not sail(DESTINATION):return
	var before_quote: Dictionary=c.TradeIntel.report(c,DESTINATION)
	var buyer: int=int(c.port(DESTINATION).cash)
	stock=float(c.port(DESTINATION).stocks.timber);sold_open=int(c.state.coins)
	sold=c.trade(DESTINATION,"timber",1,"sell")
	var gross: int=int(c.state.coins)-sold_open
	check(sold.ok and gross>0 and int(c.port(DESTINATION).cash)==buyer-gross and float(c.port(DESTINATION).stocks.timber)==stock+1,"physical destination sale debits the real buyer, credits captain and adds the same local stock")
	receipt.grossSales=int(receipt.grossSales)+gross
	var pair: String=Rules.route_key([ORIGIN,DESTINATION])
	check(int(c.state.regionalFacts.passages.get(pair,0))>0,"actual delivered voyage earns a real corridor passage")
	var after_quote: Dictionary=c.TradeIntel.report(c,DESTINATION)
	check(before_quote.seen and after_quote.seen and int(after_quote.stocks.timber)==int(before_quote.stocks.timber)+1,"real revisited stock quote records the actual delivered lot")
	receipt.destination={"before":before_quote,"after":after_quote,"grossSale":gross,"view":selected_evidence()}
	check(not receipt.destination.view.opportunity.is_empty(),"selected UI exposes an existing legal sponsor trade estimate from actual visited quotes")
	# Remain at the reached destination while the real watch clears the route;
	# an early return met a live hostile near home before the watch completed.
	# No encounter is suppressed and no actor/store/progress is edited here.
	phase("actual loaded coastal sale; destination wait under the paid watch")
	for index in range(100):
		op=Ops.selected_status(c)
		if op.get("completed",false) and not receipt.resumed.is_empty():break
		if float(c.state.day)>11.0:break
		if not advance(minf(5.0,(floorf(float(c.state.day))+1.0-float(c.state.day))*c.DAY_SECONDS+0.001)):return
	op=Ops.selected_status(c)
	check(op.get("completed",false) and int(op.get("clearDays",0))>=7 and str(op.get("watchState",""))=="awaiting" and not Rules.threatened(c.state,op),"seven earned consecutive clear published days plus real passage complete the achievement and await choice")
	check(float(c.fleet_owner(TRADER).get("tradeDelivered",0))>float(receipt.opening.merchantProvenance.merchant.delivered),"the same physically loaded merchant earns its actual destination sale")
	check(not receipt.resumed.is_empty() and receipt.resumed.plan.ready and int(receipt.resumed.patrol.coins)<int(receipt.stall.patrol.coins),"paid dock purchase/repair/payroll resumes the original watch from real resources")
	harbor=Rules.harbor_view(c.state,c.state.regionalCampaigns.operations.harbor)
	check(harbor.ready and int(harbor.staffDays)>=3 and c.state.regionalCampaigns.operations.harbor.status=="complete","actual fully paid staffed working days complete the twelve-lot harbor goal")
	if not op.get("completed",false):receipt.status="BLOCKED_SUSTAINED_WATCH";return
	if not sail(ORIGIN,true):return
	phase("physical return after the earned clear watch")
	if not watch_choices():return
	if not within_budget():return
	var facts: String=JSON.stringify(c.state.regionalFacts)
	var fuel: float=float(c.state.fleet[0].fuel)
	var fuel_stock: float=float(c.port(ORIGIN).stocks.fuel)
	var before_stores: int=int(c.state.coins)
	check(c.resupply_boat(str(c.state.fleet[0].uid)).ok and float(c.state.fleet[0].fuel)>fuel,"actual paid return visit reloads consumed working tank fuel")
	check(absf((fuel_stock-float(c.port(ORIGIN).stocks.fuel))-(float(c.state.fleet[0].fuel)-fuel))<0.000001 and int(c.state.coins)<before_stores and JSON.stringify(c.state.regionalFacts)==facts,"paid own-tank loading conserves exact fuel and coins without any merchant sale or passage credit")
	receipt.returnStoresPaid=before_stores-int(c.state.coins)
	receipt.finalView=selected_evidence()
	parsed_save()
	receipt.closingCoins=int(c.state.coins);receipt.closingWatch=owner_book(WATCH);receipt.closingMerchant=owner_book(TRADER)
	receipt.playerPayrollDays=int(c.state.econDay)-int(receipt.opening.econDay)
	receipt.playerBaseWages=int(receipt.playerPayrollDays)*int(receipt.opening.crew)*Goods.SAILOR_WAGE
	receipt.actualCaptainCashOutflow=int(receipt.opening.playerCoins)+int(receipt.grossSales)-int(c.state.coins)
	receipt.separateCapitalPaid=int(receipt.setupBill)+1000
	receipt.operatingCashPaid=int(receipt.actualCaptainCashOutflow)-int(receipt.separateCapitalPaid)
	receipt.foodConsumed=maxf(0,float(receipt.opening.playerFood)-float(c.state.cargo.food))
	receipt.foodReplacementValue=ceili(float(receipt.foodConsumed)*Economy.price(c.port(ORIGIN),"food","buy"))
	receipt.operatingNet=int(receipt.grossSales)-int(receipt.operatingCashPaid)-int(receipt.foodReplacementValue)
	receipt.costBasis="Actual captain outflow after declared opening capital; paid business setup/deposit/additional capital separate; wages, purchased/donated goods and paid return stores included; consumed opening rations valued separately. No positive-profit or complete progression claim."
	check(float(receipt.returnDistance)>0 and int(receipt.operatingCashPaid)>=int(receipt.playerBaseWages) and int(c.state.wageArrears)==0,"receipt includes actual return, full100-coin sailor-day payroll and spent stores, with no waived arrears")
	check(gear_uids(c.state.fleet[0])==receipt.opening.playerItems,"same player hull retains its original physical equipment UIDs")
	for row in [[receipt.opening.watch,receipt.closingWatch],[receipt.opening.merchantProvenance.merchant,receipt.closingMerchant]]:
		check(row[0].boats.map(func(b):return {"uid":b.uid,"items":b.items})==row[1].boats.map(func(b):return {"uid":b.uid,"items":b.items}),"same original patrol/merchant boat UIDs retain their actual physical itemUid values through paid recovery and return")
	receipt.status="COMPLETED" if failures==0 else "FAILED"
	phase("continued/withdrawn watch, paid return stores and parsed save")

func selected_evidence() -> Dictionary:
	var view: Dictionary=RegionalUI.review(c)
	return {"operation":view.operation,"ports":view.ports,"traffic":view.traffic,"safety":view.safety,"opportunity":view.opportunity,"businesses":view.businesses,"publishedDay":view.publishedDay}

func watch_choices() -> bool:
	var op: Dictionary=Ops.selected_status(c)
	var owners: int=c.state.fleetOwners.size()
	var hulls: Array=c.fleet_owner(WATCH).boats.map(func(b):return str(b.uid))
	var items: Array=c.fleet_owner(WATCH).boats.map(func(b):return gear_uids(b))
	var coins: int=Money.total(c.state)
	RegionalUI.open(scene.ui)
	var keep: Button=button_in(scene.ui.overlay,"Continue paid watch")
	check(keep!=null and not keep.disabled,"actual completed-watch UI offers explicit continuation")
	if keep==null:return false
	keep.pressed.emit()
	var kept: Dictionary=Ops.selected_status(c)
	check(kept.watchAssigned and kept.completed and str(kept.completionId)==str(op.completionId) and str(kept.ownerId)==WATCH and c.state.regionalCampaigns.fundedRoutes==receipt.funding,"continue keeps achievement, owner, completion and once-only funding identity")
	var repeated: Dictionary=Ops.continue_watch(c)
	check(repeated.ok and not repeated.changed and int(repeated.granted)==0,"repeated explicit continuation is idempotent and grants zero")
	var before: Dictionary=Orders.find_patrol(c.state,WATCH).duplicate(true)
	var withdraw: Button=button_in(scene.ui.overlay,"Withdraw regional watch")
	check(withdraw!=null and not withdraw.disabled,"actual watch UI offers explicit withdrawal")
	if withdraw==null:return false
	withdraw.pressed.emit()
	var withdrawn: Dictionary=Ops.selected_status(c)
	check(withdrawn.completed and not withdrawn.watchAssigned and withdrawn.watchState=="withdrawn" and c.distance(before,Orders.find_patrol(c.state,WATCH))<0.000001,"withdraw retains achievement and changes assignment without teleporting the fleet")
	check(Ops.withdraw_watch(c).ok and not Ops.start(c,"corridor").ok and c.state.regionalCampaigns.fundedRoutes==receipt.funding,"withdraw/repeat/restart cannot duplicate completion or treasury support")
	check(Money.total(c.state)==coins and c.state.fleetOwners.size()==owners and c.fleet_owner(WATCH).boats.map(func(b):return str(b.uid))==hulls and c.fleet_owner(WATCH).boats.map(func(b):return gear_uids(b))==items,"watch choices preserve all coins, owners, hull UIDs and actual fitting UIDs")
	scene.ui.close_modal()
	for index in range(45):
		var actor: Dictionary=Orders.find_patrol(c.state,WATCH)
		if str(c.fleet_owner(WATCH).get("atPort",""))==ORIGIN and c.distance(actor,c.port(ORIGIN))<40.0:break
		if not advance(5.0):return false
	var home: bool=str(c.fleet_owner(WATCH).get("atPort",""))==ORIGIN and c.distance(Orders.find_patrol(c.state,WATCH),c.port(ORIGIN))<40.0
	check(home,"withdrawn original patrol physically returns through its ordinary paid route/recovery")
	return home

func parsed_save() -> void:
	join_calendar()
	var saved: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	var funds: String=JSON.stringify(saved.regionalCampaigns.fundedRoutes)
	var business: Dictionary=Home.business_view(c.state,str(receipt.businessId))
	var accounts: Array=JSON.parse_string(JSON.stringify([owner_book(WATCH),owner_book(TRADER)]))
	var combat_log: Array=JSON.parse_string(JSON.stringify(c.state.get("navalAi",{}).get("encounters",[])))
	check(c.restore(saved).ok,"actual JSON-parsed voyage restores paid work, stock, identity, watch and funding books")
	check(JSON.stringify(c.state.regionalCampaigns.fundedRoutes)==funds and Home.business_view(c.state,str(receipt.businessId)).paidWorkDays==business.paidWorkDays and Ops.selected_status(c).watchState=="withdrawn","parsed restore preserves actual work receipts and original once-only watch choice")
	check(JSON.parse_string(JSON.stringify([owner_book(WATCH),owner_book(TRADER)]))==accounts and JSON.parse_string(JSON.stringify(c.state.get("navalAi",{}).get("encounters",[])))==combat_log,"parsed restore preserves both actual owners' purses, cargo, hull/part identities and exact encounter loss receipts")
	check(not Ops.start(c,"harbor").ok and not Ops.start(c,"corridor").ok,"restored completed goals cannot fund or finish a second time")
	var protected: String=JSON.stringify(c.state)
	var bad: Dictionary=saved.duplicate(true);bad.regionalCampaigns.operations.corridor.clearDays=-1
	check(not c.restore(bad).ok and JSON.stringify(c.state)==protected,"negative regional progress is refused before live mutation")
	bad=saved.duplicate(true);bad.campaignFocus.portId="invented-harbor"
	check(not c.restore(bad).ok and JSON.stringify(c.state)==protected,"unknown selected harbor is refused without changing the voyage")

func _initialize() -> void:
	began_us=Time.get_ticks_usec()
	scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.set_process(false);scene.set_physics_process(false)
	scene.audio.enabled=false;scene.music.enabled=false
	scene.save_directory=OS.get_user_data_dir().path_join("regional061-%d"%began_us)
	c=scene.core
	check(c.new_game(61061).ok,"one seeded campaign uses Main's existing world/navigation")
	scene.mode="campaign";scene.paused=true
	if c.state.is_empty():await finish();return
	supply=Money.total(c.state);census=people()
	check(c.state.regionalCampaigns.operations.is_empty(),"optional regional book starts empty")
	# Exact opening staging and paid flow are below; no other worlds or new_game.
	if not opening_fixture():await finish();return
	phase("declared opening fixture and physical identity")
	if within_budget():paid_voyage()
	await finish()

func finish() -> void:
	if c!=null and not c.state.is_empty():
		join_calendar()
		var deaths: float=0.0
		for event in encounters.values():deaths+=float(event.crewLostA)+float(event.crewLostB)
		receipt.encounters=encounters;receipt.joinedDays=joined_days;receipt.steps=steps
		receipt.conservation={"coins":Money.total(c.state),"supply":supply,"people":people(),"openingPeople":census,"recordedNpcDeaths":deaths}
		check(Money.total(c.state)==supply and int(c.state.coinSupply)==supply and people()+deaths==census,"global coins and numerical custody plus actual recorded deaths equal the declared opening supply")
	scene.queue_free();await process_frame
	check(elapsed()<BUDGET_SECONDS,"whole internal proof stays below40s including setup, joins and cleanup")
	receipt.elapsedSeconds=elapsed()
	if receipt.status=="COMPLETED" and failures>0:receipt.status="FAILED"
	print("regional061 receipt ",JSON.stringify(receipt))
	print("regional voyage: %d checks, %d failures; %.3fs"%[checks,failures,elapsed()]);quit(0 if failures==0 and receipt.status=="COMPLETED" else 1)
