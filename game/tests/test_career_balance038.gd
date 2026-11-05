extends SceneTree
## One bounded current career, six public quotes and one real escrow transaction.
## Empty canonical fixture shells hire actual paid crew; no clock/playthrough.
const Campaign=preload("res://scripts/campaign.gd")
const Guidance=preload("res://scripts/campaign_guidance.gd")
const Expedition=preload("res://scripts/expedition.gd")
const Exploration=preload("res://scripts/exploration.gd")
const Jobs=preload("res://scripts/voyage_jobs.gd")
const Money=preload("res://scripts/money.gd")
const Births=preload("res://scripts/equipment_lifecycle.gd")
const Work=preload("res://scripts/civilian_work.gd")
const Transport=preload("res://scripts/passenger_transport.gd")
const Economy=preload("res://scripts/economy.gd")
const Goods=preload("res://scripts/goods.gd")
const Reserves=preload("res://scripts/harbor_reserves.gd")
const Navigation=preload("res://scripts/navigation.gd")
var c
var checks: int=0
var failures: int=0
var records: Array=[]

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL career balance038: "+message)

func close(a: float,b: float) -> bool:return absf(a-b)<0.0001

func read_plan(id: String) -> Dictionary:
	var before: Dictionary=c.state.duplicate(true);var world: Dictionary=c.data.duplicate(true)
	var cache: Dictionary=c.route_cache.duplicate(true);var events: Array=c.events.duplicate(true);var pending: int=c.pending_days
	var report: Dictionary=Guidance.report(c,0.0,id)
	var p: Dictionary=report.get("careerPlan",{})
	check(report.ok and p.get("id","")==id and not str(p.get("firstGoal","")).is_empty() and not p.get("requirements",[]).is_empty(),id+": actual first goal and entry requirements")
	check(c.state==before and c.data==world and c.route_cache==cache and c.events==events and c.pending_days==pending,id+": report preserves full state, world, route cache and pending work")
	if p.is_empty():return p
	check(int(p.operatingCosts.dailyWages)==int(Expedition.report(c.state,c.data).dailyWages) and close(float(p.operatingCosts.wageCoins),ceilf(float(p.operatingCosts.days)*float(p.operatingCosts.dailyWages))),id+": actual full-fleet 100-coin payroll and return allowance")
	check(not str(p.rewardSource).is_empty() and not str(p.nextStep).is_empty() and not str(p.operatingCosts.summary).is_empty() and not str(p.limits).is_empty(),id+": concrete reward source, cost quote, next step and limits")
	records.append(p.duplicate(true))
	return p

func offered(id: String) -> Dictionary:
	for j in Jobs.available(c):
		if str(j.id)==id:return j
	return {}

func add_empty_shell(id: String,count: int) -> String:
	var h: Dictionary=c.hull(id)
	var staged: Dictionary=Births.stage_birth(c.state,c.data,h,"boat-%d"%int(c.state.nextUid),{})
	check(staged.ok,"canonical empty fixture shell: "+id)
	if not staged.ok:return ""
	var b: Dictionary=c.add_boat(h,0,staged)
	check(c.recruit_crew(str(b.uid),count).ok and c.resupply_boat(str(b.uid),"voyage").ok,"existing paid sailors and actual purchased stores: "+id)
	return str(b.uid)

func _initialize() -> void:
	c=Campaign.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json")))
	check(c.new_game(3801).ok,"current campaign publishes")
	if c.state.is_empty():finish();return
	var merchant_only095: bool=OS.get_cmdline_user_args().has("--merchant-only095")
	if not merchant_only095:
		var explorer: Dictionary=read_plan("explorer")
		var survey: Dictionary=offered(str(explorer.get("quote",{}).get("id","")))
		check(not survey.is_empty() and int(explorer.quote.rewardCoins)==int(survey.reward),"explorer uses the actual finite treasury survey offer")
		if not survey.is_empty():
			var chart: Dictionary=Exploration.quote(c.state,str(survey.siteId),"chart")
			var landed: Dictionary=Exploration.quote(c.state,str(survey.siteId),"survey")
			check(close(float(explorer.operatingCosts.workDays),float(chart.days)+float(landed.days)) and close(float(explorer.operatingCosts.workKits),float(chart.supplies)+float(landed.supplies)),"survey allowance includes real chart+landed work, provisions and three kits")
	print("COST095_PHASE merchant_quote_begin")
	var merchant: Dictionary=read_plan("merchant")
	print("COST095_PHASE merchant_quote_complete")
	var freight: Dictionary=offered(str(merchant.get("quote",{}).get("id","")))
	check(not freight.is_empty() and int(merchant.quote.rewardCoins)==int(freight.reward) and merchant.quote.freight==freight.freight,"merchant quotes the actual funded lot and fee")
	var quote: Dictionary=merchant.marketQuote
	var origin: Dictionary=c.port(str(quote.get("originPort","")))
	var destination: Dictionary=c.port(str(quote.get("destinationPort","")))
	var linked: bool=false
	var farm: String=""
	for edge in c.data.ROUTES:
		var other: String=""
		if str(edge[0])==str(origin.get("id","")):other=str(edge[1])
		elif str(edge[1])==str(origin.get("id","")):other=str(edge[0])
		if other==str(destination.get("id","")):linked=true
		if other!="" and str(c.port(other).get("industry",""))=="agriculture":farm=other
	check(quote.get("ok",false) and str(quote.good)!="preserved_fish" and str(origin.get("id",""))!=str(destination.get("id","")) and linked and quote.get("sailed",true)==false,"merchant quotes an authored cross-port good and does not claim a sailed result")
	if farm!="":check(str(destination.id)==farm,"an agriculture neighbor is the quoted route")
	check(int(quote.exportableLots)==floori(Reserves.exportable(origin,str(quote.good))) and int(quote.exportableLots)>=1 and int(quote.buyCoins)==Economy.price(origin,str(quote.good)) and int(quote.sellCoins)==Economy.price(destination,str(quote.good),"sell") and int(quote.buyerCash)==int(destination.cash) and is_equal_approx(float(quote.stock),float(origin.stocks[str(quote.good)])),"source buy, destination sell, exportable stock and buyer purse are the live book")
	var weight: float=float(Goods.ITEMS[str(quote.good)].weight)
	var hold_lots: int=floori(float(merchant.operatingCosts.freeHold)/weight)
	var buyer_lots: int=floori(float(int(destination.cash))/float(int(quote.sellCoins)))
	check(int(quote.holdLots)==hold_lots and int(quote.buyerLots)==buyer_lots and int(quote.capLots)==mini(int(quote.exportableLots),mini(hold_lots,buyer_lots)),"integer lots cannot pass exportable stock, free hold or destination cash")
	var shown: bool=false
	for line in merchant.requirements:
		if str(line)==str(quote.guidance):shown=true
	check(shown and "Not a sailed profit" in str(quote.guidance) and int(quote.unitMarginCoins)==int(quote.sellCoins)-int(quote.buyCoins),"the visible plan states the live unit margin and does not call it a sailed profit")
	if str(quote.contrastPort)!="":
		var other_port: Dictionary=c.port(str(quote.contrastPort))
		check(str(other_port.id)!=str(origin.id) and int(quote.contrastSellCoins)==Economy.price(other_port,str(quote.good),"sell"),"the other authored neighbor is a second live sell quote")
	var costs: Dictionary=merchant.operatingCosts
	var days: float=float(costs.days)
	var food_needed: float=float(Economy.daily_upkeep(c.state.fleet).food)*days
	var food_aboard: float=float(c.state.cargo.food)
	var food_buy: float=maxf(0.0,food_needed-food_aboard)
	var burn: float=0.0
	var fuel_aboard: float=0.0
	for b in c.active_fleet():
		burn+=Work.fuel_rate(b)
		fuel_aboard+=float(b.fuel)
	var loose: float=float(c.state.cargo.get("fuel",0.0))
	var fuel_needed: float=burn*days
	var fuel_buy: float=maxf(0.0,fuel_needed-fuel_aboard-loose)
	var gross: int=int(costs.wageCoins)+ceili(food_needed*float(costs.prices.food))+ceili(fuel_needed*float(costs.prices.fuel))+int(costs.workKitCoins)+int(costs.repairQuoteCoins)
	check(close(float(costs.foodRequired),food_needed) and close(float(costs.foodAboard),food_aboard) and close(float(costs.foodPurchase),food_buy) and int(costs.foodPurchaseCoins)==ceili(food_buy*float(costs.prices.food)) and int(costs.foodCoins)==ceili(food_needed*float(costs.prices.food)),"food allowance buys only the shortfall against rations already aboard")
	check(close(float(costs.fuelRequired),fuel_needed) and close(float(costs.fuelAboard),fuel_aboard) and close(float(costs.looseFuel),loose) and close(float(costs.fuelPurchase),fuel_buy) and int(costs.fuelPurchaseCoins)==ceili(fuel_buy*float(costs.prices.fuel)) and int(costs.fuelCoins)==ceili(fuel_needed*float(costs.prices.fuel)),"fuel allowance buys only the shortfall against tanks and loose drums")
	check(float(costs.reserveDays)==2.0 and int(costs.wageCoins)==ceili(days*float(costs.dailyWages)) and days>=float(costs.reserveDays) and int(costs.allowanceCoins)==int(costs.wageCoins)+int(costs.foodCoins)+int(costs.fuelCoins)+int(costs.workKitCoins)+int(costs.repairQuoteCoins),"full replacement allowance retains reserve-day payroll and consumed store value")
	check(food_aboard>0.0 and food_buy<food_needed and fuel_aboard+loose>0.0 and fuel_buy<fuel_needed and int(costs.additionalCashCoins)<gross and int(costs.allowanceCoins)==gross and int(costs.replacementAllowanceCoins)==gross,"owned food and fuel reduce new cash needed without inflating replacement-valued surplus")
	check(int(costs.additionalCashCoins)==int(costs.wageCoins)+int(costs.foodPurchaseCoins)+int(costs.fuelPurchaseCoins)+int(costs.workKitCoins)+int(costs.repairQuoteCoins) and int(costs.rewardLessAllowanceCoins)==int(freight.reward)-gross,"additional purchases and replacement-valued reward projection have separate exact bases")
	if merchant_only095:
		finish();return
	var privateer: Dictionary=read_plan("privateer")
	var bounty: Dictionary=offered(str(privateer.get("quote",{}).get("id","")))
	check(not bounty.is_empty() and int(privateer.quote.rewardCoins)==int(bounty.reward) and int(privateer.operatingCosts.boardingAdvanceCoins)==2000,"privateer uses funded named-raider bounty and actual optional boarder advance")
	# Reposition two existing actors only to quote the actual observed escort path.
	var convoy: Dictionary={};var raider: Dictionary={};var home: Dictionary=c.current_port()
	for owner in c.state.fleetOwners:
		if owner.kind=="trader" and convoy.is_empty():convoy=owner
		if owner.kind=="raider" and str(owner.id).begins_with("patrol-") and raider.is_empty():raider=owner
	for p in c.state.patrols:
		if p.id==convoy.get("id","") or p.id==raider.get("id",""):p.x=float(home.x)+200;p.y=float(home.y)
	var escort: Dictionary=read_plan("escort")
	check(escort.quote.get("ownerId","")==convoy.get("id","missing") and not escort.quote.get("carrierUids",[]).is_empty() and int(escort.quote.rewardCoins)==0 and int(escort.quote.standing)==5,"real loaded escort offers standing and service, never invented coins")
	if not freight.is_empty():
		var total: int=Money.total(c.state);var treasury: int=int(home.governmentPurse);var business: int=int(home.cash)
		check(c.accept_voyage_job(str(freight.id)).ok,"actual public freight acceptance reserves finite reward and physical lot")
		var held: Dictionary=Jobs._find(c.state,str(freight.id))
		check(int(held.get("escrow",0))==int(freight.reward) and int(home.governmentPurse)==treasury-int(freight.reward)-int(freight.materialInvoice) and int(home.cash)==business+int(freight.materialInvoice) and Money.total(c.state)==total,"quoted reward and invoice reconcile real sponsor, business and escrow purses")
		check(not c.settle_voyage_job(str(freight.id)).ok and c.settle_voyage_job(str(freight.id),true).ok and Money.total(c.state)==total,"no origin payout; ordinary abandonment refunds and preserves coins")
	var fisher_entry: Dictionary=Guidance.report(c,0.0,"fisher").careerPlan
	check(not fisher_entry.ready and fisher_entry.has("entryHull") and int(fisher_entry.entryHull.commissionCoins)>0 and int(fisher_entry.entryHull.crewAdvanceCoins)>0,"missing fishing hull shows actual local paid entry rather than hiding career")
	Money.move(home,"governmentPurse",c.state,"coins",200000,"Finite career fixture capital for paid civilian crew/stores",c.state.moneyLog)
	var supply: int=Money.total(c.state)
	var fish_uid: String=add_empty_shell("brinehook_longliner",8)
	var transport_uid: String=add_empty_shell("fenhopper_lighter",4)
	check(Money.total(c.state)==supply,"fixture crew advances and working-store purchases conserve circulating coins")
	if fish_uid.is_empty() or transport_uid.is_empty():finish();return
	var fisher: Dictionary=read_plan("fisher")
	check(close(float(fisher.quote.catchPerCrewDay),Work.catch_rate()) and float(fisher.quote.catchCeiling)<=Work.SITE_QUOTA and float(fisher.quote.catchCeiling)<=float(fisher.quote.freeBoatHold) and close(float(fisher.quote.fuelPerWorkDay),Work.fuel_rate(c.find_boat(fish_uid))),"one fishing day uses actual labor, site quota, fuel and physical hold limits")
	check(int(fisher.quote.saleCeilingCoins)<=int(home.cash) and int(fisher.quote.sellUnitCoins)==Economy.price(home,"preserved_fish","sell") and not fisher.ready,"catch sale uses a real buyer and dockside gear remains unavailable")
	var passenger: Dictionary=read_plan("passenger")
	var charter: Dictionary=offered(str(passenger.get("quote",{}).get("id","")))
	check(not charter.is_empty() and int(passenger.quote.rewardCoins)==int(charter.reward),"passenger uses one actual funded charter quote")
	if not charter.is_empty():
		var q: Dictionary=Transport.charter_quote(c,str(charter.port),str(charter.targetPort),int(charter.passengers.n),str(charter.carrierUid))
		check(not q.is_empty() and passenger.quote.carrierUid==q.carrierUid and close(float(passenger.quote.passengerFood),float(q.charterFood.food)) and int(passenger.quote.passengers)<=Transport.spare(c,c.find_boat(str(q.carrierUid))),"actual single carrier, paid provisions and real spare berths agree")
		check(int(passenger.quote.passengerSavingsCoins)==int(q.savingsHousehold)+int(q.savingsExpert) and "not captain revenue" in str(passenger.rewardSource),"passenger savings are distinct from the earning fee")
	check(Money.total(c.state)==supply and c.state.voyageJobs.is_empty() and float(c.state.day)==1.0,"all quote work leaves jobs, purses and campaign time unchanged")
	finish()

func finish() -> void:
	var folder: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		var file=FileAccess.open(folder.path_join("CAREER BASIS v0.038.json"),FileAccess.WRITE)
		check(file!=null,"selected career-quote artifact opens")
		if file!=null:file.store_string(JSON.stringify({"basis":"Focused current095 merchant quotation only; otherfivecareers notselected." if OS.get_cmdline_user_args().has("--merchant-only095") else "Actual starter fleet for explorer/merchant/escort/privateer; paid crews on explicit empty canonical fixture shells for fisher/passenger. No career clock advance. All allowances name the actual full traveling fleet and paid inactive crew. No numerical economy change justified by these single-action quotes.","careers":records},"\t"));file.close()
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
