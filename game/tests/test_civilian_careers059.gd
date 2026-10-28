extends SceneTree
## Root-only bounded native proof. One Main, one world/nav, detached baseline forks.
## The declared finite yard shells/capital are starting fixtures, never earnings.
const Work=preload("res://scripts/civilian_work.gd")
const Jobs=preload("res://scripts/voyage_jobs.gd")
const Money=preload("res://scripts/money.gd")
const Economy=preload("res://scripts/economy.gd")
const Goods=preload("res://scripts/goods.gd")
const Expedition=preload("res://scripts/expedition.gd")
const Transport=preload("res://scripts/passenger_transport.gd")
const Navigation=preload("res://scripts/navigation.gd")
const Harbor=preload("res://scripts/harbor.gd")
const Support=preload("res://scripts/fleet_support.gd")
const Costs=preload("res://scripts/career_costs.gd")
const Choices=preload("res://scripts/civilian_choices059.gd")
const VoyageUI=preload("res://scripts/voyage_ui.gd")
const FIXTURE_HULLS=["kelpnet_dory","fenhopper_lighter","seepoil_tanker","gullwing_daysailer"]
const NEXT_HULLS={"fishing":"brinehook_longliner","freight":"tideledger_coaster","fuel_delivery":"blackwater_fleet_tanker","passenger_charter":"osprey_cabin_cruiser"}
const BUDGET_SECONDS: float=40.0
var scene
var c
var baseline: Dictionary={}
var baseline_cache: Dictionary={}
var supply: int=0
var census: int=0
var checks: int=0
var failures: int=0
var began_us: int=0
var phase_us: int=0
var phases: Array=[]
var receipts: Array=[]
var steps: int=0
var payroll_days: int=0

# This existing detached quote view supplies the actual domain reads. Only the
# local carrying refusal/elapsed-work regression uses these mutation callbacks;
# its synthetic capacities never enter a paid voyage or a claimed margin.
class CarryView extends Costs.QuoteView:
	func fail(message: String) -> Dictionary:return {"ok":false,"message":message}
	func ok(message: String) -> Dictionary:return {"ok":true,"message":message}
	func log_entry(_message: String) -> void:pass

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL civilian059: "+message)

func close(a: float,b: float) -> bool:return absf(a-b)<0.0001

func elapsed() -> float:return float(Time.get_ticks_usec()-began_us)/1000000.0

func phase(label: String) -> void:
	var now: int=Time.get_ticks_usec()
	phases.append({"phase":label,"seconds":float(now-phase_us)/1000000.0,"checks":checks,"steps":steps,"payrollDays":payroll_days})
	print("civilian059 phase ",JSON.stringify(phases[-1]))
	phase_us=now

func within_budget(label: String) -> bool:
	if elapsed()<BUDGET_SECONDS-2.0:return true
	check(false,"40-second fixture budget reached before "+label+"; unfinished branches are NOT passes")
	return false

func people(s: Dictionary) -> int:
	var total: int=int(s.get("regionalCrises",{}).get("lostPeople",0))
	for p in s.ports:
		total+=int(p.workforce)+int(p.get("defenses",{}).get("crew",0))
		for job in p.get("training",{}).get("jobs",[]):total+=int(job.reservedWorkers)
	for b in s.fleet+s.get("boardingPrizes",[]):total+=int(b.crew)
	for owner in s.fleetOwners:
		for b in owner.boats:total+=int(b.crew)
	for business in s.get("businesses",[]):total+=business.employees.size()
	for job in s.get("regionalCrises",{}).get("jobs",[]):total+=int(job.n)
	for job in s.get("voyageJobs",[]):total+=int(job.get("passengers",{}).get("n",0))
	return total

func snapshot() -> String:
	return JSON.stringify({"state":c.state,"world":c.data,"events":c.events,"pending":c.pending_days,"economyTask":scene.economy_task})

func button_in(node: Node,caption: String,contains: bool=false) -> Button:
	if node is Button and ((caption in str(node.text)) if contains else str(node.text)==caption):return node
	for child in node.get_children():
		var found: Button=button_in(child,caption,contains)
		if found!=null:return found
	return null

func _initialize() -> void:
	began_us=Time.get_ticks_usec();phase_us=began_us
	scene=load("res://main.tscn").instantiate();root.add_child(scene)
	await process_frame
	scene.set_process(false);scene.set_physics_process(false)
	scene.audio.enabled=false;scene.music.enabled=false
	scene.save_directory=OS.get_user_data_dir().path_join("civilian-careers059-%d"%began_us)
	c=scene.core
	check(c.new_game(59059).ok,"one seeded Campaign on Main's existing world/navigation publishes")
	scene.mode="campaign";scene.paused=true
	if c.state.is_empty():finish();return
	supply=Money.total(c.state);census=people(c.state)
	# Declared synthetic OPENING capital stock: one ready empty shell per named
	# design at this fixture yard, before any branch or work begins. Every branch
	# must still pay Harbor's full ready price, trained minimum crew and stores.
	# These are not claimed to have been built/earned by the fixture captain.
	for id in FIXTURE_HULLS:c.current_port().shipStock[id]=int(c.current_port().shipStock.get(id,0))+1
	var donor: Dictionary=c.port("shatter_spire")
	check(Money.move(donor,"governmentPurse",c.state,"coins",200000,"Declared finite opening civilian fixture capital",c.state.moneyLog),"opening capital is transferred from an existing counted purse")
	check(Money.total(c.state)==supply and people(c.state)==census,"opening fixture mints no coins, people, goods or working stores")
	var restored: Dictionary=c.SaveValidation.validate(JSON.parse_string(JSON.stringify(c.state)),c.data)
	check(restored.ok,"declared seeded baseline passes actual parsed save validation: "+str(restored.get("message","")))
	if not restored.ok:finish();return
	baseline=c.state.duplicate(true);baseline_cache=c.route_cache.duplicate(true)
	phase("one Main/world/nav and validated declared baseline")
	if within_budget("fishing"):fishing_cycle()
	phase("fishing, pure quote, UI and physical carrying")
	if within_budget("freight"):job_cycle(Jobs.KIND_FREIGHT,"fenhopper_lighter")
	phase("actual freight round trip")
	if within_budget("charter"):job_cycle(Jobs.KIND_CHARTER,"gullwing_daysailer")
	phase("actual charter round trip")
	if within_budget("fuel"):job_cycle(Jobs.KIND_FUEL,"seepoil_tanker")
	phase("actual fuel recipient round trip or explicit blocker")
	finish()

func begin_branch(kind: String,hull_id: String) -> Dictionary:
	scene.sync_economy()
	# Independent fork of the validated baseline, before this branch's start.
	# Immutable navigation and already-known paths are reused; no world rebuild.
	c.state=baseline.duplicate(true);c.route_cache=baseline_cache.duplicate(true)
	c.pending_days=0;c.events=[];c.exploration_timer=0.0;c.sailing_clearance=0.0
	var dock: Dictionary=c.current_port()
	var acquisition_open: int=int(c.state.coins)
	var ready: Dictionary=Harbor.quote(c,c.hull(hull_id),dock)
	var crew_before: int=c.crew_count()
	var people_before: int=int(dock.workforce)
	var eligible_before: int=int(dock.training.qualified.sailor)
	var advance_quote: int=Economy.recruit_cost(dock,int(c.hull(hull_id).crewMin))
	var source_stock: int=int(dock.shipStock.get(hull_id,0))
	var born_uid: String="boat-%d"%int(c.state.nextUid)
	var bought: Dictionary=c.buy_boat(hull_id)
	check(bought.ok,kind+": actual fully paid hull/trained minimum-crew acquisition: "+str(bought.get("message","")))
	if not bought.ok:return {}
	var boat: Dictionary=c.find_boat(born_uid)
	check(not boat.is_empty() and int(dock.shipStock[hull_id])==source_stock-1 and c.crew_count()>crew_before,kind+": finite opening yard stock becomes one canonical owned UID with actual hired sailors")
	if boat.is_empty():return {}
	var acquisition_spent: int=acquisition_open-int(c.state.coins)
	check(acquisition_spent==int(ready.readyPrice)+advance_quote and int(dock.workforce)==people_before-int(boat.crew) and int(dock.training.qualified.sailor)==eligible_before-int(boat.crew),kind+": paid hire debits exactly the actual trained eligibility subset and population")
	check(acquisition_spent>=int(ready.readyPrice) and Money.total(c.state)==supply and people(c.state)==census,kind+": ready hull capital and crew advances paid without duplicating people/coins")
	# Return surplus inherited rations through the real buyer before replacing
	# the inherited skiff. A yacht must not be given a waived 30-lot overload.
	var food_to_sell: int=maxi(0,floori(float(c.state.cargo.food))-3)
	if food_to_sell>0:check(c.trade(str(dock.id),"food",food_to_sell,"sell").ok,kind+": inherited surplus rations sold through the actual finite market")
	var sale_open: int=int(c.state.coins)
	check(c.sell_boat("boat-1").ok,kind+": inherited skiff sold with crew/savings/stores returned through the ordinary API")
	var capital_recovered: int=int(c.state.coins)-sale_open
	var stores_open: int=int(c.state.coins)
	check(c.resupply_boat(born_uid,"voyage").ok,kind+": actual stock/coins buy engine fuel, kits and magazine")
	var stores_paid: int=stores_open-int(c.state.coins)
	check(c.state.fleet.size()==1 and c.active_fleet().size()==1 and int(boat.crew)>=int(boat.crewMin),kind+": receipt prices one real working boat, with no hidden unpaid/stored sailors")
	check(c.cargo_weight()<=c.capacity()+0.0001 and Money.total(c.state)==supply and people(c.state)==census,kind+": acquisition and paid stores retain carrying/coin/person conservation")
	var prices: Dictionary={}
	for good in ["food","fuel","supplies","ammo"]:prices[good]=Economy.price(dock,good,"buy")
	return {"kind":kind,"boatUid":born_uid,"hull":hull_id,"origin":str(dock.id),"status":"STARTED","openingCapitalTransfer":200000,
		"hullCapitalPaid":int(ready.readyPrice),"crewAdvancePaid":acquisition_spent-int(ready.readyPrice),"inheritedHullCapitalRecovered":capital_recovered,"openingStoresPaid":stores_paid,
		"openingCoins":int(c.state.coins),"openingArrears":int(c.state.wageArrears),"openingDay":float(c.state.day),"openingEconDay":int(c.state.econDay),
		"openingCrewPurse":int(c.state.crewPurse),"physicalItemUids":boat.moduleCondition.items.keys(),"crew":int(boat.crew),"dailyWages":int(Economy.daily_upkeep(c.state.fleet).wages),"specialistPremiumPerDay":Support.premium(c.state),
		"openingFuel":float(boat.fuel),"openingFood":float(c.state.cargo.food),"openingKits":float(boat.supplies),"openingAmmo":float(boat.ammo),
		"prices":prices,"grossIncome":0,"passengerSavingsCustody":0,"sailingDistance":0.0,"sailingDays":0.0,"returnDays":0.0,"steps":0}

func advance(seconds: float,r: Dictionary) -> bool:
	if seconds<=0:return true
	if not within_budget(str(r.kind)+" clock"):return false
	var before: Dictionary=c.state.position.duplicate()
	c.step(seconds);steps+=1;r.steps=int(r.steps)+1
	r.sailingDistance=float(r.sailingDistance)+c.distance(before,c.state.position)
	# Work earns only Campaign.step time. Real calendar settlement occurs at
	# the ordinary boundary, with Main's copied economy workers joined.
	if c.pending_days>0:
		var days: int=c.pending_days;scene.sync_economy();payroll_days+=days
	if c.events.any(func(event):return str(event.get("kind",""))=="encounter"):
		r.status="BLOCKED_ENCOUNTER";r.blocker="An actual hostile encounter interrupted this route; no completed-voyage claim."
		return false
	return true

func sail(r: Dictionary,target: Dictionary,destination: String="",returning: bool=false) -> bool:
	var route: Dictionary=c.chart_course(target,destination)
	check(route.ok,str(r.kind)+": actual chart route accepted: "+str(route.get("message","")))
	if not route.ok:r.status="BLOCKED_ROUTE";r.blocker=route.get("message","");return false
	var departure: float=float(c.state.day)
	for index in range(120):
		if c.state.path.is_empty():break
		if not advance(1.0,r):return false
	var duration: float=float(c.state.day)-departure
	r.sailingDays=float(r.sailingDays)+duration
	if returning:r.returnDays=float(r.returnDays)+duration
	var arrived: bool=c.state.path.is_empty() and (destination.is_empty() or str(c.current_port().get("id",""))==destination)
	check(arrived,str(r.kind)+": bounded physical sailing reaches its actual destination")
	return arrived

func settle_calendar(r: Dictionary) -> void:
	# Include at least one actual ordinary payroll day in each short work cycle;
	# a same-day dash does not become a wage-free positive career claim.
	if int(c.state.econDay)==int(r.openingEconDay):
		advance(maxf(0.01,(float(floori(float(c.state.day))+1)-float(c.state.day))*c.DAY_SECONDS+0.001),r)
	scene.sync_economy()
	check(c.pending_days==0 and scene.economy_task<0 and int(c.state.econDay)>int(r.openingEconDay),str(r.kind)+": actual ordinary economy/payroll fully joined")

func reload_check(r: Dictionary) -> void:
	scene.sync_economy()
	var state: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	var coin: int=int(c.state.coins);var day: float=float(c.state.day)
	var fish: float=float(c.state.cargo.get("preserved_fish",0))
	var jobs: String=JSON.stringify(c.state.voyageJobs)
	var result: Dictionary=c.restore(state)
	check(result.ok and int(c.state.coins)==coin and close(float(c.state.day),day) and close(float(c.state.cargo.get("preserved_fish",0)),fish) and JSON.stringify(c.state.voyageJobs)==jobs,str(r.kind)+": parsed actual save/reload preserves coins, date, physical catch and exact accepted terms: "+str(result.get("message","")))

func finish_receipt(r: Dictionary,paid: bool) -> void:
	settle_calendar(r)
	var boat: Dictionary=c.find_boat(str(r.boatUid))
	if boat.is_empty():check(false,str(r.kind)+": actual working boat survives receipt");receipts.append(r);return
	var fuel_used: float=maxf(0,float(r.openingFuel)-float(boat.fuel))
	var food_used: float=maxf(0,float(r.openingFood)-float(c.state.cargo.food))
	var kits_used: float=maxf(0,float(r.openingKits)-float(boat.supplies))
	var ammo_used: float=maxf(0,float(r.openingAmmo)-float(boat.ammo))/Goods.ROUNDS_PER_CASE
	var dock: Dictionary=c.current_port()
	var prices: Dictionary=r.prices.duplicate(true)
	if not dock.is_empty():
		for good in prices:prices[good]=maxi(int(prices[good]),Economy.price(dock,good,"buy"))
	var store_value: int=ceili(fuel_used*int(prices.fuel))+ceili(food_used*int(prices.food))+ceili(kits_used*int(prices.supplies))+ceili(ammo_used*int(prices.ammo))
	var operating_cash: int=int(r.openingCoins)+int(r.grossIncome)-int(c.state.coins)
	var days: int=int(c.state.econDay)-int(r.openingEconDay)
	var wages: int=days*(int(r.dailyWages)+int(r.specialistPremiumPerDay))
	check(operating_cash>=wages and int(r.dailyWages)==int(r.crew)*Goods.SAILOR_WAGE,str(r.kind)+": actual full 100-coin sailor payroll and any specialist premium included")
	r.closingCoins=int(c.state.coins);r.closingArrears=int(c.state.wageArrears);r.closingDay=float(c.state.day);r.paidCrewDays=days*int(r.crew)
	r.payrollDays=days;r.wagesAndPremiums=wages;r.actualOperatingCashPaid=operating_cash
	r.fuelConsumed=fuel_used;r.foodConsumed=food_used;r.kitsConsumed=kits_used;r.ammoCasesConsumed=ammo_used;r.replacementPrices=prices;r.consumedStoresReplacementCoins=store_value
	r.operatingNet=int(r.grossIncome)-operating_cash-store_value
	r.closingCrewPurse=int(c.state.crewPurse);r.closingFuel=float(boat.fuel);r.closingFood=float(c.state.cargo.food)
	r.costBasis="Actual captain cash outflow after declared acquisition plus actual store consumption at the higher real origin/return buy price. Sponsor cargo/provisions invoice and passenger savings remain separate. No contingency charge is deducted as spent."
	r.reservedContingency=ceili(2.0*(int(r.dailyWages)+int(r.specialistPremiumPerDay)+float(Economy.daily_upkeep(c.state.fleet).food)*int(prices.food)+Work.fuel_rate(boat)*int(prices.fuel)))
	r.reserveWasSpent=false;r.returnIncluded=float(r.returnDays)>0
	r.coinSupply=Money.total(c.state);r.people=people(c.state)
	check(Money.total(c.state)==supply and people(c.state)==census,str(r.kind)+": actual global coins and people conserved, including all custody/escrows")
	check(int(c.state.wageArrears)==int(r.openingArrears) and c.cargo_weight()<=c.capacity()+0.0001,str(r.kind)+": no waived payroll arrears or physical overload behind the margin")
	check(boat.moduleCondition.items.keys()==r.physicalItemUids,str(r.kind)+": same acquired physical fitting UIDs remain in actual boat custody")
	var next_id: String=str(NEXT_HULLS[r.kind])
	var next_quote: Dictionary=Harbor.quote(c,c.hull(next_id),dock if not dock.is_empty() else c.port(str(r.origin)))
	r.nextHull={"id":next_id,"name":c.hull(next_id).name,"quotedReadyCoins":int(next_quote.readyPrice),"quotedCommissionCoins":int(next_quote.commissionPrice),"surplusCoins":maxi(0,int(r.operatingNet))}
	if paid:
		r.status="PAID_POSITIVE" if int(r.operatingNet)>0 else "PAID_UNDER_COST"
		check(float(r.sailingDistance)>0 and r.returnIncluded,str(r.kind)+": earning receipt includes real outward AND return work")
		check(int(r.operatingNet)>0,str(r.kind)+": actual fee/sale covers payroll, all consumed stores at replacement prices and return; net="+str(r.operatingNet))
		check(int(next_quote.readyPrice)>0 and int(r.operatingNet)>0,str(r.kind)+": measured surplus contributes toward a real useful next-hull quote; opening capital/savings excluded")
	else:
		check(false,str(r.kind)+": four-career earning gate remains blocked: "+str(r.get("blocker","no actual paid completion")))
	reload_check(r)
	receipts.append(r.duplicate(true));print("civilian059 receipt ",JSON.stringify(r))

func fishing_cycle() -> void:
	var r: Dictionary=begin_branch("fishing","kelpnet_dory")
	if r.is_empty():return
	var uid: String=str(r.boatUid)
	var offers: Array=Jobs.available(c)
	var review_offer: Dictionary={}
	for job in offers:
		if job.kind==Jobs.KIND_FREIGHT:review_offer=job.duplicate(true);break
	check(not c.start_fishing(uid,1.0,3).ok,"dockside fishing cannot grant catch")
	var home: Dictionary=c.current_port();var point: Dictionary={}
	for delta in [Vector2(220,0),Vector2(-220,0),Vector2(0,220),Vector2(0,-220)]:
		var candidate: Dictionary={"x":float(home.x)+delta.x,"y":float(home.y)+delta.y}
		if Navigation.is_water(c.nav,candidate.x,candidate.y,maxf(10,float(c.find_boat(uid).spec.size))):point=candidate;break
	check(not point.is_empty(),"one reachable current-ground fishing candidate exists")
	if point.is_empty() or not sail(r,point):r.blocker="No actual safe fishing route";finish_receipt(r,false);return
	pure_fishing_checks(uid)
	# Produce an ordinary pending day with actual Campaign time. Review and
	# dismissal must leave it pending; they cannot secretly join/debit payroll.
	c.step((float(floori(float(c.state.day))+1)-float(c.state.day))*c.DAY_SECONDS+0.001);steps+=1
	check(c.pending_days>0,"UI refusal/decline fixture has an actual pending calendar day")
	pure_ui_checks(uid,review_offer)
	var pending: int=c.pending_days;scene.sync_economy();payroll_days+=pending
	var quote: Dictionary=Work.fishing_quote(c,uid,1.0,3)
	check(quote.ok and float(quote.catchMax)>0,"selected actual boat has a bounded feasible one-day catch")
	var before: float=float(c.state.cargo.preserved_fish)
	var fuel: float=float(c.find_boat(uid).fuel);var food: float=float(c.state.cargo.food)
	var day: float=float(c.state.day)
	check(c.start_fishing(uid,1.0,3).ok and close(float(c.state.cargo.preserved_fish),before),"setting actual gear grants no instant catch")
	for index in range(4):
		if not advance(c.DAY_SECONDS*0.25,r):break
	var catch_amount: float=float(c.state.cargo.preserved_fish)-before
	check(close(float(c.state.day)-day,1.0) and catch_amount>0 and catch_amount<=float(quote.catchMax)+0.0001,"actual calendar time earns only the quoted crew/ground/hold bound")
	check(close(fuel-float(c.find_boat(uid).fuel),float(quote.fuelNeeded)) and food>float(c.state.cargo.food),"anchored work consumes exactly the quoted real engine fuel and finite rations")
	r.fishingQuote=quote.duplicate(true);r.fishingFuelConsumed=fuel-float(c.find_boat(uid).fuel)
	r.fishingAndCalendarFoodConsumed=food-float(c.state.cargo.food)
	var book: Dictionary=c.state.get("civilianWork",{})
	check(close(float(book.get("wildFishCreated",0)),catch_amount),"actual physical catch equals explicit finite wild production")
	for amount in book.get("sites",{}).values():check(float(amount)<=Work.SITE_QUOTA+0.0001,"no crew multiplies one cell's calendar quota")
	if not Work.fishing_status(c).is_empty():check(c.cancel_fishing(uid).ok,"real recall keeps already earned catch")
	if not sail(r,c.port_position(str(r.origin)),str(r.origin),true):r.blocker="Actual fishing return failed";finish_receipt(r,false);return
	var buyer: Dictionary=c.current_port();var cash: int=int(buyer.cash);var stock: float=float(buyer.stocks.preserved_fish)
	var wallet: int=int(c.state.coins);var lots: int=floori(catch_amount)
	var sold: Dictionary=c.trade(str(buyer.id),"preserved_fish",lots,"sell")
	r.grossIncome=int(c.state.coins)-wallet;r.catchLots=catch_amount;r.soldLots=lots
	r.buyer={"port":buyer.id,"day":float(c.state.day),"cashBefore":cash,"cashAfter":int(buyer.cash),"unitSellCoins":Economy.price(buyer,"preserved_fish","sell")}
	check(sold.ok and int(buyer.cash)==cash-int(r.grossIncome) and close(float(buyer.stocks.preserved_fish),stock+lots),"ordinary fish sale debits a real buyer and transfers the same integer caught lots")
	finish_receipt(r,bool(sold.ok))

func pure_fishing_checks(uid: String) -> void:
	var before: String=snapshot()
	var small: Dictionary=Work.fishing_quote(c,uid,0.25,1)
	var normal: Dictionary=Work.fishing_quote(c,uid,0.25,3)
	check(small.ok and normal.ok and float(normal.catchMax)>float(small.catchMax) and close(float(normal.catchRate),3.0*Work.catch_rate()),"actual selected hands/time change the bounded fishing estimate")
	check(not Work.fishing_quote(c,uid,0,3).ok and not Work.fishing_quote(c,uid,1,99).ok and not Work.fishing_quote(c,"absent",1,3).ok,"pure estimate refuses zero time, invented hands and absent physical carrier")
	check(snapshot()==before,"quote/refusal preserves full state/world, purses, catch, date, events and pending calendar")
	var view=CarryView.new(c)
	var boat: Dictionary=view.active_fleet()[0]
	boat.spec.cargo=1000.0;view.state.cargo.food=10.0;boat.fuel=10.0
	var q: Dictionary=Work.fishing_quote(view,uid,1.0,3)
	view.state.civilianWork={"schema":36,"fishing":[],"resourceDay":floori(float(view.state.day)),"sites":{Work.site_id(view.state.position):39.0},"wildFishCreated":39.0}
	q=Work.fishing_quote(view,uid,minf(0.2,1.0-fposmod(float(view.state.day),1.0)),3)
	check(q.ok and float(q.catchMax)<=1.00001 and "quota" in q.limits,"actual remaining cell quota limits extra hands/time")
	view.state.day=float(floori(float(view.state.day)))+0.9
	q=Work.fishing_quote(view,uid,0.2,3)
	check(q.ok and close(float(q.catchMax),3.0) and close(float(q.quotaInHorizon),41.0),"forecast splits the current finite quota and next calendar's ground at midnight")
	view.state.civilianWork.sites[Work.site_id(view.state.position)]=40.0
	check(not Work.fishing_quote(view,uid,1,3).ok,"exhausted same-date ground is an explicit refusal")
	view.state.civilianWork.resourceDay=floori(float(view.state.day))-1
	check(close(float(Work.fishing_quote(view,uid,0.1,3).quotaRemaining),40),"old-date site use never consumes the new calendar's quota")
	view.state.erase("civilianWork")
	boat.fuel=0.001
	q=Work.fishing_quote(view,uid,0.5,3)
	check("fuel" in q.limits and float(q.fuelNeeded)<=float(boat.fuel)+0.000001,"forecast respects loaded individual tank and anchored burn")
	boat.fuel=10.0;view.state.cargo.food=0.001
	q=Work.fishing_quote(view,uid,0.5,3)
	check("food" in q.limits and float(q.foodNeeded)<=0.001001,"forecast respects finite loaded rations")
	# Existing physical installed engine is placed in a detached test locker;
	# no new UID or parallel count is created. Both production seams must agree.
	view=CarryView.new(c);boat=view.active_fleet()[0]
	var item: Dictionary={}
	for entry in boat.moduleCondition.items.values():
		if entry.location=="engine":item=entry;break
	check(not item.is_empty(),"detached carrying regression uses an existing exact physical engine UID")
	if not item.is_empty():
		item.location="locker";item.lockerOrder=0
		# Transfer one EXISTING eligible NPC carrier only inside this detached
		# carrying case, so spare fleet room cannot hide the selected-hull bug.
		var extra: Dictionary={}
		for owner in view.state.fleetOwners:
			for candidate in owner.boats:
				if not candidate.sunk and float(candidate.crew)>=float(candidate.crewMin) and float(candidate.spec.cargo)>5:
					extra=candidate;owner.boats.erase(candidate);view.state.fleet.append(candidate);break
			if not extra.is_empty():break
		check(not extra.is_empty(),"detached hull-limit case transfers an existing crewed physical carrier rather than inventing fleet room")
		var locker: float=Expedition.locker_weight(boat)
		var used: float=float(boat.spec.cargo)-Transport.available_hold(view,boat)
		boat.spec.cargo=used+locker
		check(view.capacity()-view.cargo_weight()>0 and Work.fishing_quote(view,uid,0.25,3).limitingCause=="hold" and not Work.start_fishing(view,uid,0.25,3).ok,"quote and actual start refuse a locker-filled selected hold even while another real carrier has space")
		boat.spec.cargo+=0.4
		check(Work.start_fishing(view,uid,0.25,3).ok,"detached actual gear accepts only the remaining physical hold")
		var fish: float=float(view.state.cargo.preserved_fish)
		var food: float=float(view.state.cargo.food)
		view.state.day=float(view.state.day)+0.25
		Work.tick(view,0.25)
		check(float(view.state.cargo.preserved_fish)-fish>0 and float(view.state.cargo.preserved_fish)-fish<=0.40001+food-float(view.state.cargo.food) and view.cargo_weight()<=view.capacity()+0.00001,"actual elapsed tick respects this boat's locker; only real eaten rations free more room")
	check(snapshot()==before,"all synthetic carrying/quota/store variants remain detached from the paid voyage")

func pure_ui_checks(uid: String,offer: Dictionary) -> void:
	var before: String=snapshot()
	var review: Dictionary=Choices.fishing_review(c,uid,1.0,3,str(c.state.lastPort))
	check(review.has("quote") and snapshot()==before,"B detached selected fishing review preserves the pending real day")
	VoyageUI.review_fishing(scene.ui,uid,1.0,3,str(c.state.lastPort))
	check(snapshot()==before and scene.ui.modal_open,"actual selected fishing review opens without time/payment/offer mutation")
	var decline: Button=button_in(scene.ui.overlay,"Decline",true)
	if decline==null:decline=button_in(scene.ui.overlay,"Return to chart",true)
	check(decline!=null,"fishing review exposes an explicit nontransactional dismissal")
	if decline!=null:decline.pressed.emit()
	check(snapshot()==before,"actual fishing decline does not settle unrelated pending payroll")
	if not offer.is_empty():
		var job: Dictionary=Choices.job_review(c,offer,uid)
		check(job.has("budget") and snapshot()==before,"B detached selected job budget preserves exact pending state")
		VoyageUI.review_job(scene.ui,offer,uid)
		decline=button_in(scene.ui.overlay,"Decline",true)
		check(decline!=null,"selected unaccepted real job exposes a nontransactional Decline")
		if decline!=null:decline.pressed.emit()
		check(snapshot()==before,"actual job decline neither accepts work nor joins pending payroll")
		VoyageUI.review_job(scene.ui,offer,uid)
		var header: Button=button_in(scene.ui.overlay,String.chr(215))
		check(header!=null,"actual work review retains its ordinary header close")
		if header!=null:header.pressed.emit()
		check(snapshot()==before,"actual header-X refuses Interface's automatic economy sync on pure review")
	else:check(false,"real funded freight exists for selected review/header-X proof")

func job_cycle(kind: String,hull_id: String) -> void:
	var r: Dictionary=begin_branch(kind,hull_id)
	if r.is_empty():return
	var uid: String=str(r.boatUid)
	var offers: Array=Jobs.available(c)
	var chosen: Dictionary={}
	if kind==Jobs.KIND_FREIGHT:
		for job in offers:
			if str(job.kind)==kind and str(job.get("freight",{}).get("good","")) in ["preserved_fish","fine_timber","lacquer","medicinal_plants"]:chosen=job.duplicate(true);break
	for job in offers:
		if not chosen.is_empty():break
		if str(job.kind)==kind and (kind!=Jobs.KIND_CHARTER or int(job.passengers.n)<=Transport.spare(c,c.find_boat(uid))):chosen=job.duplicate(true);break
	if chosen.is_empty() and kind==Jobs.KIND_FUEL:
		# Bounded live opportunity observation. No tank edits, NPC freeze, forged
		# atPort, demand injection or custom reward. A owns the published policy.
		for index in range(3):
			if not advance(c.DAY_SECONDS*0.05,r):break
			for job in Jobs.available(c):
				if str(job.kind)==kind:chosen=job.duplicate(true);break
			if not chosen.is_empty():break
	if chosen.is_empty():
		r.status="BLOCKED_NO_FUNDED_OFFER";r.blocker="No actual eligible funded "+kind+" offer at "+str(c.current_port().get("name","sea"))+" day "+str(c.state.day)
		r.available=offers.map(func(job):return {"id":job.id,"kind":job.kind,"reward":job.reward,"target":job.targetPort})
		if kind==Jobs.KIND_FUEL:
			r.recipients=[]
			for owner in c.state.fleetOwners:
				if not str(owner.id).begins_with("story-"):r.recipients.append({"ownerId":owner.id,"active":owner.active,"atPort":owner.atPort,"threeDrumNeed":Jobs.fuel_demand(owner),"operatingTankNeed":Jobs.fuel_demand(owner,true),"coins":owner.coins})
		print("civilian059 EARLY BLOCKER ",JSON.stringify(r))
		finish_receipt(r,false);return
	var id: String=str(chosen.id)
	r.offer=chosen.duplicate(true)
	var selected: Dictionary=Choices.job_review(c,chosen,uid)
	check(selected.get("ok",false) and selected.get("carrierFits",false),kind+": selected real offer has the actual physical carrier fit")
	if kind==Jobs.KIND_FREIGHT:
		var larger: Array=offers.filter(func(job):return job.kind==kind and str(job.get("loadTier",""))=="larger")
		r.largerRealOptions=larger.map(func(job):return {"id":job.id,"qty":job.freight.qty,"good":job.freight.good,"reward":job.reward,"target":job.targetPort})
		check(larger.any(func(job):return float(job.freight.qty)*float(Goods.ITEMS[str(job.freight.good)].weight)>float(c.hull("gullwing_daysailer").cargo)),"at least one actually funded larger freight load exceeds the real daysailer's entire hold, making a cargo carrier useful")
	var dock: Dictionary=c.current_port();var payer: String=str(chosen.payerKey)
	var treasury: int=int(dock[payer]);var business: int=int(dock.cash)
	var freight: Dictionary=chosen.get("freight",{})
	var source_stock: float=float(dock.stocks.get(str(freight.get("good","food")),0))
	var population: int=int(dock.workforce)
	var household: int=int(dock.householdPurse);var expert: int=int(dock.expertPurse)
	var accepted: Dictionary=c.accept_voyage_job(id,uid)
	check(accepted.ok,kind+": Campaign accepts actual exact funded terms: "+str(accepted.get("message","")))
	if not accepted.ok:r.blocker=accepted.get("message","");finish_receipt(r,false);return
	var active: Dictionary=Jobs._find(c.state,id)
	var savings: int=int(active.get("savingsHousehold",0))+int(active.get("savingsExpert",0))
	r.passengerSavingsCustody=savings
	r.sponsorMaterialInvoicePaid=int(active.materialInvoice)
	r.acceptedEscrow=int(active.escrow);r.sponsorPurseBefore=treasury;r.sponsorPurseAfter=int(dock[payer])
	check(int(active.escrow)==int(chosen.reward)+savings and int(dock[payer])==treasury-int(chosen.reward)-int(active.materialInvoice),kind+": exact real sponsor fee plus invoice debit and conserved escrow")
	if not freight.is_empty():
		check(close(float(dock.stocks[str(freight.good)]),source_stock-float(freight.qty)),kind+": accepted sealed load removes the exact source stock")
		check(int(dock.cash)==business+int(active.materialInvoice),kind+": cargo invoice reaches the actual source business purse")
	if kind==Jobs.KIND_CHARTER:
		r.charterProvisionsLoaded=float(active.charterFood.food)
		check(int(dock.workforce)==population-int(active.passengers.n) and Transport.assigned(c.state,uid)==int(active.passengers.n),"actual counted charter cohort occupies this yacht's spare berths")
		check(int(dock.householdPurse)==household-int(active.savingsHousehold) and int(dock.expertPurse)==expert-int(active.savingsExpert),"passenger savings leave the actual source purses and stay custody, never captain income")
		check(not c.recruit_crew(uid,Transport.spare(c,c.find_boat(uid))+1).ok,"charter occupied berths cannot hire a second set of people")
	if kind==Jobs.KIND_FUEL:
		check(close(float(c.state.cargoManifest.get(uid,{}).get("@job:"+id,0)),float(freight.qty)),"fuel lot is sealed on its selected physical hull, distinct from engine tanks")
	var wallet: int=int(c.state.coins)
	check(not c.settle_voyage_job(id).ok and int(c.state.coins)==wallet,kind+": origin refusal cannot earn destination escrow")
	check(Money.total(c.state)==supply and people(c.state)==census,kind+": acceptance/refusal conserves all global purses and people")
	var parsed: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	var validated: Dictionary=c.SaveValidation.validate(parsed,c.data)
	check(validated.ok and JSON.stringify(Jobs._find(parsed,id))==JSON.stringify(JSON.parse_string(JSON.stringify(Jobs._find(c.state,id)))),kind+": exact active fee, load, custody, recipient policy and physical carrier survive parsed save validation")
	if kind==Jobs.KIND_FREIGHT:
		var saved_job: Dictionary=Jobs._find(parsed,id).duplicate(true)
		var saved_manifest: Dictionary=parsed.cargoManifest.duplicate(true)
		var saved_parts: Dictionary=JSON.parse_string(JSON.stringify(c.find_boat(uid).moduleCondition))
		var restored: Dictionary=c.restore(parsed)
		check(restored.ok and JSON.parse_string(JSON.stringify(Jobs._find(c.state,id)))==saved_job and JSON.parse_string(JSON.stringify(c.state.cargoManifest))==saved_manifest and JSON.parse_string(JSON.stringify(c.find_boat(uid).moduleCondition))==saved_parts,"ACTIVE actual sealed freight reload preserves exact parsed cargo/escrow/carrier/fitting UIDs before delivery: "+str(restored.get("message","")))
		if not restored.ok:r.blocker=str(restored.get("message",""));finish_receipt(r,false);return
	var destination: String=str(chosen.targetPort)
	if not sail(r,c.port_position(destination),destination):r.blocker="Actual outward route interrupted";finish_receipt(r,false);return
	active=Jobs._find(c.state,id)
	if kind==Jobs.KIND_CHARTER:
		r.charterFoodConsumed=float(active.foodConsumed);r.charterFoodToPublicStores=float(active.charterFood.food)
		check(float(active.voyageDistance)>0 and float(active.elapsedDays)>0 and float(active.foodConsumed)>0 and close(float(active.charterFood.food)+float(active.foodConsumed),float(r.charterProvisionsLoaded)),"charter actual sailing earns observed route/time and conserves its own bought provisions")
	var target: Dictionary=c.current_port()
	var target_stock: float=float(target.stocks.get(str(freight.get("good","food")),0))
	var target_workers: int=int(target.workforce)
	var target_household: int=int(target.householdPurse);var target_expert: int=int(target.expertPurse)
	var saved_household: int=int(active.get("savingsHousehold",0));var saved_expert: int=int(active.get("savingsExpert",0))
	var passenger_n: int=int(active.get("passengers",{}).get("n",0))
	var owner: Dictionary=c.fleet_owner(str(active.get("ownerId","")))
	var recipient_fuel: float=0.0
	if not owner.is_empty():
		for boat in owner.boats:recipient_fuel+=float(boat.fuel)
		if kind==Jobs.KIND_FUEL:
			r.recipientBefore=Jobs.recipient_status(c,active);r.recipientTankFuelBefore=recipient_fuel
			r.recipientCargoFuelBefore=float(owner.cargo.get("fuel",0))
	wallet=int(c.state.coins)
	var settled: Dictionary=c.settle_voyage_job(id)
	var paid: bool=bool(settled.ok)
	if paid:
		r.grossIncome=int(c.state.coins)-wallet
		check(int(r.grossIncome)==int(chosen.reward),kind+": actual settlement pays exactly the fee, excluding all passenger savings")
		if kind==Jobs.KIND_FREIGHT:check(close(float(target.stocks[str(freight.good)]),target_stock+float(freight.qty)),"destination receives the same physical source freight lot")
		if kind==Jobs.KIND_CHARTER:check(int(target.workforce)==target_workers+passenger_n and int(target.householdPurse)==target_household+saved_household and int(target.expertPurse)==target_expert+saved_expert,"actual destination receives each charter person and household/expert savings exactly once")
		if kind==Jobs.KIND_FUEL:
			var received: float=0.0
			for boat in owner.boats:received+=float(boat.fuel)
			r.recipientTankFuelAfter=received;r.recipientCargoFuelAfter=float(owner.cargo.get("fuel",0))
			check(close(received-recipient_fuel,float(freight.qty)) and close(float(owner.cargo.get("fuel",0)),float(r.recipientCargoFuelBefore)),"finite recipient tanks receive exactly the actual sealed fuel lot without duplicating cargo fuel")
		wallet=int(c.state.coins)
		check(not c.settle_voyage_job(id).ok and int(c.state.coins)==wallet,kind+": duplicate receipt never pays twice")
	else:
		r.status="BLOCKED_AT_RECIPIENT";r.blocker=str(settled.get("message",""))
		check(int(c.state.coins)==wallet and not Jobs._find(c.state,id).is_empty(),kind+": actual unavailable recipient remains unpaid with its load/escrow in custody")
		print("civilian059 EARLY BLOCKER ",JSON.stringify(r))
	if not sail(r,c.port_position(str(r.origin)),str(r.origin),true):r.blocker="Actual return interrupted after "+str(r.get("blocker","receipt"));finish_receipt(r,false);return
	if not paid:
		var origin: Dictionary=c.current_port();var refund_before: int=int(origin[payer])
		var owed: int=int(Jobs._find(c.state,id).get("escrow",0))-savings
		check(c.settle_voyage_job(id,true).ok and int(origin[payer])==refund_before+owed,kind+": actual safe return refunds the remaining sponsor fee once")
		check(not c.settle_voyage_job(id,true).ok,kind+": safe refund cannot duplicate")
	finish_receipt(r,paid)

func finish() -> void:
	if scene!=null:
		scene.sync_economy();scene.free()
	var whole: float=elapsed()
	check(whole<BUDGET_SECONDS,"entire one-baseline fixture including setup/cleanup stays below 40 seconds; actual="+str(whole))
	check(receipts.size()==4,"four career receipts exist; queued/blocked/unfinished work is not a paid pass")
	var artifact: Dictionary={"sourceOnlyAuthor":"C; only Root executes this fixture","seed":59059,"checks":checks,"failures":failures,"wholeSeconds":whole,"steps":steps,"payrollDays":payroll_days,"phases":phases,"receipts":receipts,
		"startingFixture":"One finite ready shell per named career at the synthetic opening yard; 200000 coins transferred from Shatter Spire treasury; Campaign fully paid hull/crew/stores acquisition. No captain-earned capital/progression claim.",
		"limits":"Independent baseline branches, live NPCs, no post-start goods/demand/cash/people grants or waived costs. Reserved contingency is funding, not spent costs; household/expert savings are custody. One positive cycle contributes toward a quoted next hull, not a proven full career. Broad coast art/strict051/whole quality remain OPEN062."}
	var folder: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if not folder.is_empty():
		var file=FileAccess.open(folder.path_join("civilian-careers059.json"),FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify(artifact,"\t"));file.close()
	print("civilian059 ",checks," checks, ",failures," failures; ",whole,"s; ",steps," actual steps; ",payroll_days," joined payroll days")
	quit(0 if failures==0 else 1)
