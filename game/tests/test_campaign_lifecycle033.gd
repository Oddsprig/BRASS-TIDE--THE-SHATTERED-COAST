extends SceneTree
## Focused v0.033 lifecycle fixture. Root owns the bounded native run.
const Campaign=preload("res://scripts/campaign.gd")
const Lifecycle=preload("res://scripts/naval_lifecycle.gd")
const AI=preload("res://scripts/naval_ai.gd")
const Orders=preload("res://scripts/naval_orders.gd")
const Fleets=preload("res://scripts/fleet_economy.gd")
const Economy=preload("res://scripts/economy.gd")
const Service=preload("res://scripts/equipment_service.gd")
const Money=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0
var c

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL campaign lifecycle033: ",message)

func reset(seed_value: int) -> void:
	c.new_game(seed_value)
	c.state.day=5.25;c.state.econDay=5;c.state.encounterGrace=60.0
	for p in c.state.patrols:p.active=false

func _initialize() -> void:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c=Campaign.new(world)
	_test_midday()
	_test_recovery_route()
	_test_prize_sale_and_repair()
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func _test_midday() -> void:
	reset(3301)
	var raider: Dictionary=c.fleet_owner("patrol-3")
	var guard: Dictionary=c.fleet_owner("patrol-5")
	var a: Dictionary=Orders.find_patrol(c.state,str(raider.id))
	var b: Dictionary=Orders.find_patrol(c.state,str(guard.id))
	var speed_sum: float=(float(AI.fleet_performance(raider).speed)+float(AI.fleet_performance(guard).speed))*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0))
	var gap: float=AI.ENCOUNTER_RADIUS+speed_sum*0.25
	var segment: Array=[]
	var length: float=0.0
	for i in range(1,a.course.size()):
		if c.distance(a.course[i-1],a.course[i])>length:
			segment=[a.course[i-1],a.course[i]];length=c.distance(segment[0],segment[1])
	check(length>gap+speed_sum,"existing water route has room for a short crossing scenario")
	if length<=gap+speed_sum:return
	var direction: Vector2=Vector2(float(segment[1].x)-float(segment[0].x),float(segment[1].y)-float(segment[0].y)).normalized()
	var middle: Vector2=(Vector2(segment[0].x,segment[0].y)+Vector2(segment[1].x,segment[1].y))*0.5
	c.state.position={"x":middle.x,"y":middle.y}
	for pair in [[raider,a,1.0],[guard,b,-1.0]]:
		var owner: Dictionary=pair[0]
		var p: Dictionary=pair[1]
		var start: Vector2=middle-direction*gap*0.5*float(pair[2])
		p.active=true;p.holding=false;p.x=start.x;p.y=start.y;p.progress=0.0
		p.course=[{"x":p.x,"y":p.y},segment[1] if float(pair[2])>0 else segment[0]];p.courseLength=c.distance(p.course[0],p.course[1])
		owner.atPort=""
		AI.build_order(c.state,owner,"raid" if owner.kind=="raider" else "patrol",str(p.to),"Fixture existing crossing course")
	var ammo_before: float=0.0
	for owner in [raider,guard]:
		for boat in owner.boats:ammo_before+=float(boat.ammo)
	var story_before: Dictionary=c.fleet_owner("story-0").duplicate(true)
	var ticks_before: int=int(c.state.navalAi.tickCount)
	c.step(0.5)
	check(c.state.navalAi.encounters.is_empty(),"subsecond movement does not scan every frame")
	check(c.distance(a,b)<AI.ENCOUNTER_RADIUS,"real chart movement brings previously separated fleets within encounter range")
	c.step(0.5)
	var encounters: Array=c.state.navalAi.encounters
	check(encounters.size()==1,"campaign step resolves the crossing during the day")
	if encounters.size()!=1:print("MIDDAY: ",{"distance":c.distance(a,b),"speedSum":speed_sum,"navalAi":c.state.navalAi.get("encounterCount",-1)})
	var event: Dictionary=encounters[0] if not encounters.is_empty() else {}
	check(int(event.get("shotsA",0))+int(event.get("shotsB",0))>0,"midday encounter fires real boats' weapons")
	var ammo_after: float=0.0
	for owner in [raider,guard]:
		for boat in owner.boats:ammo_after+=float(boat.ammo)
		if owner.get("purpose","") in ["withdraw","repair","replace","resupply"] and Orders.living_boats(owner).size()>0:
			check(str(Orders.find_patrol(c.state,str(owner.id)).to)==str(owner.destination),"combat survivor follows its recovery destination immediately")
	check(ammo_after<ammo_before,"midday encounter consumes actual persistent ammunition")
	check(int(c.state.econDay)==5 and int(c.state.navalAi.tickCount)==ticks_before,"fight occurs without a daily AI tick")
	check(c.state.log.any(func(line):return str(event.get("summary","missing encounter summary")) in str(line)),"nearby successful encounter summary reaches the campaign log")
	check(c.fleet_owner("story-0")==story_before,"story hulls, cargo, people and purses remain unchanged")
	check(Money.total(c.state)==int(c.state.coinSupply),"midday fight conserves all campaign coins")
	c.step(2.0)
	check(c.state.navalAi.encounters.size()==1,"later lifecycle scan cannot repeat an owner's fight that day")
	check(float(c.state.navalEncounterElapsed)==0.0,"long step drops missed scan intervals instead of accumulating catch-up work")

	reset(3302)
	raider=c.fleet_owner("patrol-3");guard=c.fleet_owner("patrol-5")
	guard.faction=raider.faction
	for owner in [raider,guard]:
		var p: Dictionary=Orders.find_patrol(c.state,str(owner.id))
		p.active=true;p.holding=true;p.x=4200.0;p.y=3100.0
	c.step(1.0)
	check(c.state.navalAi.encounters.is_empty(),"nearby nonhostile fleets do not fight")

func _test_recovery_route() -> void:
	reset(3303)
	var owner: Dictionary=c.fleet_owner("patrol-3")
	var p: Dictionary=Orders.find_patrol(c.state,str(owner.id))
	var away: String=str(p.to)
	p.active=true
	for purpose in ["withdraw","repair","replace","resupply"]:
		Lifecycle.route(c,p,away)
		# Exercise the formerly missed case: this leg did not originate at home.
		p.from=away
		var before: Dictionary={"x":p.x,"y":p.y}
		AI.build_order(c.state,owner,purpose,str(owner.homePort),"Fixture recovery from the current sea position")
		Lifecycle.step(c,0.01)
		check(str(p.to)==str(owner.destination),"%s changes the active destination before further movement"%purpose)
		check(not p.course.is_empty() and c.distance(p.course[0],before)<0.001,"%s route starts at the survivor's current coordinate"%purpose)
		var limit: float=float(AI.fleet_performance(owner).speed)*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0))*0.01+0.01
		check(c.distance(p,before)<=limit,"%s neither teleports nor advances along the obsolete course"%purpose)

func _test_prize_sale_and_repair() -> void:
	reset(3304)
	var owner: Dictionary=c.fleet_owner("patrol-3")
	var trader: Dictionary=c.fleet_owner("patrol-1")
	var market: Dictionary=c.port(str(trader.homePort))
	# Clear real commercial lots to make room, then buy the test shipment.
	var wallet: Dictionary={"coins":trader.coins,"cargo":trader.cargo}
	var sold: Dictionary=Economy.transact(market,wallet,str(trader.tradeGood),mini(8,floori(float(trader.tradeCargo))),"sell",Fleets._capacity(trader))
	if sold.ok:
		trader.coins=wallet.coins;trader.tradeCargo=maxf(0.0,float(trader.tradeCargo)-float(sold.qty))
	var loaded: int=Fleets._purchase(trader,market,"timber",4,false,false,c,true)
	check(loaded>0,"shipment comes from paid finite port stock")
	if loaded<=0:return
	trader.tradeGood="timber";trader.tradeCargo=loaded
	# An exhausted merchant withdraws after the first salvo; no invented prize.
	for boat in trader.boats:boat.ammo=0.0
	var timber_before: float=float(owner.cargo.timber)+float(trader.cargo.timber)
	var outcome: Dictionary=AI.resolve_encounter(c.state,owner,trader,Orders.find_patrol(c.state,str(owner.id)),Orders.find_patrol(c.state,str(trader.id)),3304)
	var event: Dictionary=outcome.get("event",{})
	check(outcome.get("ok",false) and event.get("winner","")==owner.id and int(event.get("capturedQty",0))>0 and event.get("capturedGood","")=="timber","real hostile encounter transfers a merchant shipment to the raider's hold")
	if int(event.get("capturedQty",0))<=0:
		print("PRIZE: ",outcome)
		return
	check(is_equal_approx(float(owner.cargo.timber)+float(trader.cargo.timber),timber_before),"captured goods are debited from the defeated owner's real hold")
	var home: Dictionary=c.port(str(owner.homePort))
	var p: Dictionary=Orders.find_patrol(c.state,str(owner.id))
	p.holding=true;p.x=home.x;p.y=home.y;p.from=home.id;p.to=home.id
	owner.atPort=home.id
	# Purchase any missing operating cases before measuring the separate prize sale.
	for good in ["fuel","supplies","ammo"]:
		var target: float=3.0 if good=="fuel" else (2.0 if good=="supplies" else 50.0)
		var conversion: float=50.0 if good=="ammo" else 1.0
		var need: int=0
		for vessel in owner.boats:need+=maxi(0,ceili((target-float(vessel[good]))/conversion))
		if need>floori(float(owner.cargo[good])):Fleets._purchase(owner,home,good,need-floori(float(owner.cargo[good])),false,true,c)
	var boat: Dictionary=owner.boats[0]
	boat.hp=float(boat.maxHp)-5.0
	var q: Dictionary=Service.service_quote(c,boat,home)
	check(q.get("ok",false) and int(q.get("cost",0))>0 and float(q.get("workerDays",0))>0,"existing equipment service quotes a paid worker and real kits for hull repair")
	if not q.get("ok",false):return
	_test_repair_guards(owner,home,boat)
	var owner_snapshot: Dictionary=owner.duplicate(true)
	var home_snapshot: Dictionary=home.duplicate(true)
	var coins_before: int=int(owner.coins)
	var cash_before: int=int(home.cash)
	var household_before: int=int(home.householdPurse)
	var workers_before: float=float(home.get("_yardWorkersUsed",0.0))
	var kits_before: float=float(boat.supplies)
	var timber_stock: float=float(home.stocks.timber)
	var held: float=float(owner.cargo.timber)
	var price: int=Economy.price(home,"timber","sell")
	var quantity: int=mini(floori(held),cash_before/maxi(1,price))
	var boat_uid: String=str(boat.uid)
	var birth: String=str(boat.moduleCondition.birthNamespace)
	var crew: float=float(boat.crew)
	var messages: Array=Fleets.dock(owner,home,c)
	check(quantity>0 and is_equal_approx(float(owner.cargo.timber),held-quantity) and is_equal_approx(float(home.stocks.timber),timber_stock+quantity),"home sale moves only held prize lots into actual market stocks")
	check(int(owner.coins)==coins_before+quantity*price-int(q.cost),"prize receipts fund the existing repair bill without extra credit")
	check(int(home.cash)==cash_before-quantity*price+int(q.materials)+int(q.fee),"market cash pays the sale and receives only the quoted repair materials and fee")
	check(int(home.householdPurse)==household_before+int(q.ordinary) and is_equal_approx(float(home.get("_yardWorkersUsed",0.0)),workers_before+float(q.workerDays)),"actual paid shipwright wages and worker reservations are published")
	check(is_equal_approx(float(boat.hp),float(boat.maxHp)) and is_equal_approx(float(boat.supplies),kits_before-float(q.own)),"hull restoration consumes the quoted onboard repair supplies")
	check(str(boat.uid)==boat_uid and str(boat.moduleCondition.birthNamespace)==birth and float(boat.crew)==crew,"paid repair preserves the physical boat, equipment birth and actual crew")
	check(messages.any(func(line):return "captured timber" in str(line)),"home prize sale appears in the existing owner messages")
	check(Money.total(c.state)==int(c.state.coinSupply),"capture, operating purchases, home sale and paid repair conserve global coins")
	_test_sale_guards(owner_snapshot,home_snapshot)
	# A second visit cannot sell the already transferred shipment again.
	var remaining: float=float(owner.cargo.timber)
	Fleets.dock(owner,home,c)
	check(float(owner.cargo.timber)==remaining,"repeated home docking cannot duplicate sold cargo")
	check(Money.total(c.state)==int(c.state.coinSupply),"repeated docking preserves campaign coin supply")

func _test_sale_guards(prize: Dictionary,port: Dictionary) -> void:
	# Detached copies isolate guard cases from the live canonical campaign.
	for guard in ["cash","stock","away","embargo","company","story"]:
		var owner: Dictionary=prize.duplicate(true)
		var dock: Dictionary=port.duplicate(true)
		match guard:
			"cash":dock.cash=0
			"stock":owner.cargo.timber=0.0
			"away":dock.id="other-harbor"
			"embargo":owner.tradeBans=[{"issuer":owner.faction,"target":dock.faction,"good":"timber","expires":99.0}]
			"company":owner.playerCompany=true
			"story":owner.id="story-fixture033"
		var before: float=float(owner.cargo.timber)
		var coins: int=int(owner.coins)
		Fleets.dock(owner,dock)
		check(float(owner.cargo.timber)==before and int(owner.coins)==coins,"%s guard grants no prize sale or free credit"%guard)
	var owner: Dictionary=prize.duplicate(true)
	var dock: Dictionary=port.duplicate(true)
	owner.cargo.timber=0.0
	var before: Dictionary={}
	for good in ["food","fuel","supplies","ammo"]:
		before[good]=float(owner.cargo[good])
		if good!="food":
			for boat in owner.boats:before[good]+=float(boat[good])/(50.0 if good=="ammo" else 1.0)
	Fleets.dock(owner,dock)
	for good in ["food","fuel","supplies","ammo"]:
		var after: float=float(owner.cargo[good])
		if good!="food":
			for boat in owner.boats:after+=float(boat[good])/(50.0 if good=="ammo" else 1.0)
		check(is_equal_approx(after,float(before[good])),"protected %s stores remain aboard the owner rather than being sold for cash"%good)
	check(int(dock.cash)==int(port.cash),"operating stores create no market sale receipts")

func _test_repair_guards(owner: Dictionary,port: Dictionary,boat: Dictionary) -> void:
	# Use the registered hull and live core, so each refusal exercises service preflight.
	var hp: float=float(boat.hp)
	var coins: int=int(owner.coins)
	Money.move(owner,"coins",port,"governmentPurse",coins,"Fixture reserve purse",c.state.moneyLog)
	Fleets._repair(owner,port,boat,c)
	check(float(boat.hp)==hp and int(owner.coins)==0,"empty owner purse cannot grant free hull restoration")
	Money.move(port,"governmentPurse",owner,"coins",coins,"Fixture restore purse",c.state.moneyLog)
	var kits: float=float(boat.supplies)
	var stock: float=float(port.stocks.supplies)
	boat.supplies=0.0;port.stocks.supplies=0.0
	Fleets._repair(owner,port,boat,c)
	check(float(boat.hp)==hp and int(owner.coins)==coins,"missing boat and market supplies cannot grant free hull restoration")
	boat.supplies=kits;port.stocks.supplies=stock
	var workers: float=float(port.availableWorkers)
	port.availableWorkers=0.0
	Fleets._repair(owner,port,boat,c)
	check(float(boat.hp)==hp and int(owner.coins)==coins,"unavailable harbor workers cannot grant free hull restoration")
	port.availableWorkers=workers
