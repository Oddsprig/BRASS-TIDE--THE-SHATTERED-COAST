extends SceneTree
const Campaign=preload("res://scripts/campaign.gd")
const Economy=preload("res://scripts/economy.gd")
const Navigation=preload("res://scripts/navigation.gd")
const Battle=preload("res://scripts/battle.gd")
const Money=preload("res://scripts/money.gd")
const Goods=preload("res://scripts/goods.gd")
var failures: Array=[]
var checks: int=0
var c
var world: Dictionary
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:
		var stack: Array=get_stack()
		var where: String="test_campaign.gd:%s"%stack[1].line if stack.size()>1 else "test_campaign.gd"
		failures.append(where+" — "+message)
		print("FAIL "+failures[-1])
func reset() -> void:
	var result: Dictionary=c.new_game(123)
	check(result.get("ok",false),"Fresh current career publishes")
func at_port(id: String) -> void:
	c.state.position=c.port_position(id)
func wallet_snapshot() -> Dictionary:
	return {"coins":c.state.coins,"crewPurse":c.state.crewPurse,"totalCoins":Money.total(c.state),"cargo":c.state.cargo.duplicate(true),"fleet":c.state.fleet.duplicate(true),"ports":c.state.ports.duplicate(true)}
func same_data(a,b) -> bool:
	# JSON changes integer-valued numbers to floats; compare every nested value semantically.
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():
			return false
		for key in a:
			if not b.has(key) or not same_data(a[key],b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():
			return false
		for i in range(a.size()):
			if not same_data(a[i],b[i]):
				return false
		return true
	return a==b
func _initialize() -> void:
	world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c=Campaign.new(world)
	_test_start_buy_recruit()
	_test_commission()
	_test_repair_resupply()
	_test_trade_freight()
	_test_actual_first_battle()
	_test_story_protocol()
	_test_salvage_rescue_save()
	_test_uncrewed_recovery()
	_test_ten_days()
	print("campaign: %d checks, %d failures"%[checks,failures.size()])
	if not failures.is_empty():
		quit(1)
		assert(failures.is_empty(),"Campaign integration failures above")
	else:
		quit(0)
func _test_start_buy_recruit() -> void:
	reset()
	var starter: Dictionary=c.state.fleet[0]
	check(c.state.fleet.size()==1 and starter.type==world.START.hull and starter.spec.price==c.hull(world.START.hull).price,"Exactly one configured inherited hull at its published fitted price")
	check(starter.crew==world.START.crew and c.state.coins==world.START.coins,"Exact configured crew and starting coins")
	check(c.current_port().id==world.START.port,"Start in real home harbor")
	var p: Dictionary=c.current_port()
	var h: Dictionary=c.hull(world.START.hull)
	var q: Dictionary=c.ship_quote(h,p)
	fund_wallet(int(q.readyPrice))
	var insufficient: Dictionary=wallet_snapshot()
	check(not c.buy_boat(h.id).ok and wallet_snapshot()==insufficient,"Hull-only funds cannot bypass minimum crew cost")
	fund_wallet(int(q.readyPrice)+Economy.recruit_cost(p,int(h.crewMin))+10000)
	var stock: float=p.shipStock[h.id]
	var pool: float=p.recruits
	var available: int=mini(int(pool),mini(int(p.workforce),int(p.training.qualified.sailor)))
	var coins: float=c.state.coins
	var hire_cost: int=Economy.recruit_cost(p,int(h.crewMin))
	var people: int=int(p.workforce)+c.crew_count()
	var total: int=Money.total(c.state)
	var crew_purse: int=int(c.state.crewPurse)
	var result: Dictionary=c.buy_boat(h.id)
	check(Money.total(c.state)==total and int(p.workforce)+c.crew_count()==people,"Purchase conserves coins and actual shore/ship people")
	check(int(c.state.crewPurse)==crew_purse+hire_cost,"Minimum crew advance belongs to the recruited sailors")
	check(result.ok,"Second hull affordable from its published quote and funded finite wallet")
	check(c.state.fleet.size()==2,"Second hull added")
	if c.state.fleet.size()>1:
		var second: Dictionary=c.state.fleet[1]
		check(second.crew==h.crewMin and not second.mothballed,"Minimum crew included and deployed")
		check(c.state.coins==coins-int(q.readyPrice)-hire_cost,"Hull and exact recruitment paid")
		check(p.recruits==available-h.crewMin and p.shipStock[h.id]==stock-1,"Recruit and hull pools consumed")
		coins=c.state.coins
		pool=p.recruits
		check(not c.recruit_crew(second.uid,999).ok,"Recruitment respects bunks")
		check(c.state.coins==coins and p.recruits==pool,"Rejected recruitment unchanged")
		fund_wallet(10000)
		var room: int=int(second.crewMax-second.crew)
		check(int(p.recruits)>=room and int(p.workforce)>=room and int(p.training.qualified.sailor)>=room,"Existing port workforce can fill the tested bunks")
		check(c.recruit_crew(second.uid,room).ok and second.crew==second.crewMax,"Recruit exactly to capacity")
		check(not c.recruit_crew(second.uid,1).ok,"No extra sailor past max")
		check(starter.crew<starter.crewMax,"Starter has a real vacant berth for the empty-pool rejection")
		p.recruits=0
		check(not c.recruit_crew(starter.uid,1).ok,"No recruitment from empty pool")
func _test_commission() -> void:
	reset()
	fund_wallet(100000)
	var p: Dictionary=c.current_port()
	var h: Dictionary=c.hull(world.START.hull)
	var materials: Dictionary=c.ship_materials(h)
	for good in materials:
		top_stock(p,str(good),float(materials[good])+20.0)
	var q: Dictionary=c.ship_quote(h,p)
	fund_wallet(maxi(100000,int(q.commissionPrice)+12*c.crew_count()*Goods.SAILOR_WAGE))
	var before: Dictionary=p.stocks.duplicate()
	var coins: float=c.state.coins
	p.stocks.engines=0
	var snap: Dictionary=wallet_snapshot()
	check(not c.commission(h.id).ok and wallet_snapshot()==snap and p.buildQueue.is_empty(),"Commission rejects missing materials unchanged")
	p.stocks=before.duplicate()
	var total: int=Money.total(c.state)
	var people: int=int(p.workforce)+c.crew_count()
	check(c.commission(h.id).ok,"Commission accepted with materials")
	check(c.state.coins==coins-int(q.commissionPrice),"Exact published materials/labor/supervision/overhead/margin/tax commission price paid")
	check(Money.total(c.state)==total and int(p.workforce)+c.crew_count()==people,"Commission escrows labor and conserves coins and people")
	for good in materials:
		check(p.stocks[good]==before[good]-materials[good],"Commission consumes "+good)
	check(p.buildQueue.size()==1 and p.buildQueue[0].remainingWorkerDays>0 and is_equal_approx(float(p.buildQueue[0].estimatedDays),float(q.estimatedDays)),"Quoted worker/expert time recorded")
	var order: Dictionary=p.buildQueue[0]
	check(int(order.escrow)==int(q.laborCost)+int(q.supervisionCost),"All promised construction wages start in finite escrow")
	check(not c.collect_boat(0).ok,"Cannot collect unfinished hull")
	for day in range(12):
		c.apply_economy(c.state.ports,[],1)
	check(order.ready and order.remainingWorkerDays==0 and order.escrow==0,"Original twelve paid days finish commissioned hull")
	check(int(order.laborPaid)==int(q.laborCost) and int(order.supervisionPaid)==int(q.supervisionCost) and Money.total(c.state)==total,"Completion pays exactly the quoted worker/expert wages without minting coins")
	check(c.collect_boat(0).ok,"Completed commission collectible")
	var boat: Dictionary=c.state.fleet[-1]
	check(boat.crew==0 and boat.mothballed,"Collected hull requires recruitment")
	check(p.buildQueue.is_empty() and not c.collect_boat(0).ok,"Commission only collected once")
func _test_repair_resupply() -> void:
	reset()
	fund_wallet(10000)
	var boat: Dictionary=c.state.fleet[0]
	var p: Dictionary=c.current_port()
	boat.hp-=30
	boat.supplies=2.0
	boat.engine=0.7
	boat.wounded=1
	boat.water=100
	boat.fire=10
	boat.breaches=[{"area":40.0,"section":"bow"}]
	var quote: Dictionary=c.service_quote(boat,p)
	check(quote.get("ok",false),"Current canonical service quote accepts the original damage setup")
	fund_wallet(maxi(10000,int(quote.cost)))
	var stocks: float=p.stocks.supplies
	var coins: float=c.state.coins
	check(quote.own==2 and quote.purchase>0 and quote.cost>0,"Repair quote consumes existing kits first")
	var total: int=Money.total(c.state)
	var worker_purse: int=int(p.householdPurse)
	var expert_purse: int=int(p.expertPurse)
	var equipment_materials: Dictionary=p.stocks.duplicate(true)
	check(c.repair_boat(boat.uid).ok,"Drydock succeeds")
	check(Money.total(c.state)==total and int(p.householdPurse)==worker_purse+int(quote.ordinary) and int(p.expertPurse)==expert_purse+int(quote.expert),"Repair transfers the exact quoted paid labor and expert wages")
	for good in quote.equipmentMaterials:
		check(is_equal_approx(float(p.stocks[good]),float(equipment_materials[good])-float(quote.equipmentMaterials[good])),"Repair consumes quoted canonical equipment material "+str(good))
	check(boat.supplies==0 and is_equal_approx(p.stocks.supplies,stocks-quote.purchase),"Repair consumes own and purchased supplies")
	check(c.state.coins==coins-quote.cost,"Repair charged exact quote")
	check(boat.hp==boat.maxHp and boat.breaches.is_empty() and boat.water==0 and boat.engine==1 and boat.wounded==0 and boat.fire==0,"Repair resolves all damage")
	boat.hp-=20
	boat.supplies=0
	p.stocks.supplies=0
	var snap: Dictionary=wallet_snapshot()
	check(not c.repair_boat(boat.uid).ok and wallet_snapshot()==snap,"No supply means atomic repair rejection")
	boat.fuel=0
	boat.ammo=0
	boat.supplies=0
	fund_wallet(100)
	p.stocks.fuel=3.0
	p.stocks.ammo=2.0
	p.stocks.supplies=1.0
	coins=c.state.coins
	var stock_before: Dictionary=p.stocks.duplicate()
	check(c.resupply_boat(boat.uid).ok,"Partial resupply works with finite money")
	check(c.state.coins>=0 and c.state.coins<coins,"Resupply spends finite coins")
	for good in ["fuel","ammo","supplies"]:
		check(p.stocks[good]>=0 and is_equal_approx(float(boat[good])/(Goods.ROUNDS_PER_CASE if good=="ammo" else 1.0)+float(p.stocks[good]),float(stock_before[good])),"Resupply stock conservation "+good)
	fund_wallet(0)
	snap=wallet_snapshot()
	check(not c.resupply_boat(boat.uid).ok and snap==wallet_snapshot(),"No free supplies with empty wallet")
func _test_trade_freight() -> void:
	reset()
	fund_wallet(10000)
	var p: Dictionary=c.current_port()
	c.state.cargo.food=c.capacity()
	var before: Dictionary=wallet_snapshot()
	check(not c.trade(p.id,"food",1,"buy").ok and before==wallet_snapshot(),"Hold capacity rejects buy unchanged")
	c.state.cargo.food=10.6
	p.stocks.food=100.25
	check(c.trade(p.id,"food",1,"buy").ok,"Whole-unit trade with fractional remainder")
	check(is_equal_approx(c.state.cargo.food,11.6) and is_equal_approx(p.stocks.food,99.25),"Trade preserves upkeep food and port fractional stock")
	check(c.trade(p.id,"food",1,"sell").ok,"Sell one unit")
	check(is_equal_approx(c.state.cargo.food,10.6) and is_equal_approx(p.stocks.food,100.25),"Roundtrip conserves fractional stock")
	var delivery: Dictionary={}
	for contract in c.available_contracts():
		if not contract.story and contract.kind=="delivery":
			delivery=contract
	check(not delivery.is_empty(),"Side freight available")
	c.state.cargo.food=c.capacity()
	check(not c.accept_contract(delivery.id).ok and c.state.freight.is_empty(),"Freight respects existing cargo")
	c.state.cargo.food=0
	check(c.accept_contract(delivery.id).ok,"Accept sealed freight")
	check(c.freight_weight()>0 and c.cargo_weight()==c.freight_weight(),"Freight contributes occupied hold")
	check(not c.trade(p.id,"supplies",1,"sell").ok,"Sealed freight cannot be sold as owned cargo")
	c.state.cargo.food=c.capacity()-c.freight_weight()
	check(not c.trade(p.id,"food",1,"buy").ok,"Trade reserves sealed freight capacity")
	check(c.abandon_contract().ok and c.state.freight.is_empty() and c.state.activeContract.is_empty(),"Abandon returns sealed freight")
func _test_actual_first_battle() -> void:
	reset()
	var first: Dictionary=world.MISSIONS[0]
	check(c.accept_contract(first.id).ok,"First story accepted")
	var target: Dictionary=c.port_position(first.targetPort)
	check(c.chart_course(target,first.targetPort).ok,"Real first-story water route exists")
	for frame in range(12000):
		if c.state.path.is_empty():
			break
		c.step(1.0/30.0)
		check(Navigation.is_water(c.nav,c.state.position.x,c.state.position.y),"Route step remains water")
	check(c.distance(c.state.position,target)<1 and c.contract_ready(),"First story destination reached")
	var enemies: Array=[]
	for id in first.enemyHulls:
		enemies.append(c.hull(id))
	var boat: Dictionary=c.state.fleet[0]
	var owner: Dictionary=c.fleet_owner(str(c.state.activeContract.ownerId))
	check(not owner.is_empty(),"First contract names a real finite shipowner")
	var st: Dictionary=Battle.create({"fleet":c.active_fleet(),"enemyFleet":owner.boats,"seed":123})
	Battle.set_autopilot(st,false) # Preserve this fixture's original manual helm policy.
	for frame in range(5400):
		if st.result!=null:
			break
		var player: Dictionary=Battle.get_flagship(st)
		if player.is_empty():
			break
		var enemy: Dictionary={}
		for s in st.ships:
			if s.team=="enemy" and not s.sunk:
				enemy=s
				break
		if enemy.is_empty():
			Battle.update(st,1.0/30.0)
			continue
		var delta: Vector2=Vector2(enemy.x-player.x,enemy.y-player.y)
		var turn: float=angle_difference(player.angle,delta.angle())
		var input: Dictionary={"manual":true,"forward":delta.length()>player.spec.range*0.7,"left":turn< -0.05,"right":turn>0.05,"fire":delta.length()<player.spec.range,"aimX":enemy.x,"aimY":enemy.y}
		Battle.update(st,1.0/30.0,input)
	check(st.result=="won","Actual first story fight winnable with inherited single skiff")
	print("first fight outcome=%s time=%.2f hp=%.2f ammo=%.2f supplies=%.2f"%[st.result,st.time,boat.hp,boat.ammo,boat.supplies])
	check(boat.ammo<world.START.ammo,"Actual battle spends persistent ammunition")
	check(boat.hp<boat.maxHp or boat.water>0 or boat.supplies<world.START.supplies,"Actual first fight leaves persistent damage/stores")
	var post: Dictionary=boat.duplicate(true)
	var settled: Dictionary=c.battle_settled(str(st.result),enemies,{"kind":"contract","ownerId":owner.id},st)
	check(not settled.fleetLost and c.state.fleet[0].ammo==post.ammo and c.state.fleet[0].hp==post.hp and c.state.fleet[0].supplies==post.supplies,"Settlement preserves actual boat stores and damage")
	check(c.state.missionIndex==1,"Actual first victory advances story")
func _test_story_protocol() -> void:
	reset()
	c.state.cargo.food=0
	for i in range(world.MISSIONS.size()):
		var mission: Dictionary=world.MISSIONS[i]
		at_port(mission.port)
		check(c.accept_contract(mission.id).ok,"Accept sequential story %d"%(i+1))
		at_port(mission.targetPort)
		var unpaid: float=c.state.coins
		check(not c.finish_contract().ok and c.state.coins==unpaid,"Story enemies must be cleared before payment %d"%(i+1))
		var specs: Array=[]
		for id in mission.enemyHulls:
			specs.append(c.hull(id))
		var coins: float=c.state.coins
		var renown: float=c.state.renown
		var owner: Dictionary=c.fleet_owner(str(c.state.activeContract.ownerId))
		var reward: int=int(c.state.activeContract.escrow)
		var loot: int=floori(float(owner.coins)*0.30)
		var total: int=Money.total(c.state)
		c.battle_settled("won",specs,{"kind":"contract","ownerId":owner.id})
		check(Money.total(c.state)==total,"Story loot and funded escrow only transfer existing coins %d"%(i+1))
		check(c.state.missionIndex==i+1,"Story advances exactly once %d"%(i+1))
		check(c.state.coins==coins+loot+reward and c.state.renown==renown+3*specs.size()+mission.renown,"Story reward exact %d"%(i+1))
		coins=c.state.coins
		check(not c.finish_contract().ok and c.state.coins==coins,"No double claim %d"%(i+1))
	check(c.state.completed and c.state.missionIndex==world.MISSIONS.size(),"Eight-story completion")
func _test_salvage_rescue_save() -> void:
	reset()
	fund_wallet(10000)
	var coins: float=c.state.coins
	var h: Dictionary=c.hull("bilge_punt")
	check(not c.salvage_boat(h.id).ok,"An arbitrary hull ID is not an earned recoverable wreck")
	record_recoverable(h)
	var q: Dictionary=c.salvage_quote(h.id)
	var total: int=Money.total(c.state)
	var worker_purse: int=int(c.port(c.state.lastPort).householdPurse)
	var expert_purse: int=int(c.port(c.state.lastPort).expertPurse)
	check(c.salvage_boat(h.id).ok,"Recover towed hull")
	check(Money.total(c.state)==total and int(c.port(c.state.lastPort).householdPurse)==worker_purse+int(q.ordinary) and int(c.port(c.state.lastPort).expertPurse)==expert_purse+int(q.expert),"Tug recovery conserves coins and pays quoted crew and inspection labor")
	var tow: Dictionary=c.state.fleet[-1]
	check(tow.hp==tow.maxHp*0.35 and tow.crew==0 and tow.fuel==0 and tow.ammo==0 and tow.supplies==0 and tow.mothballed,"Salvage requires repair crew and stores")
	check(c.state.coins==coins-int(q.total) and c.active_fleet().size()==1,"Salvage payment and inactive tow")
	c.state.fleet[0].hp-=7
	c.state.fleet[0].wounded=1
	c.state.fleet[0].water=8
	c.state.fleet[0].breaches=[{"area":3.0,"section":"stern"}]
	c.state.ports[0].stocks.iron=123.25
	var saved: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	var before: Dictionary=c.state.duplicate(true)
	check(c.restore(saved).ok,"JSON campaign restored")
	for key in ["fleet","ports","cargo","position","coins","missionIndex","seed","renown","day"]:
		check(same_data(c.state[key],before[key]),"JSON preserves "+key)
	c.state.fleet=[]
	coins=c.state.debt
	var home: Dictionary=c.port(world.START.port)
	var people: int=int(home.workforce)+c.crew_count()
	total=Money.total(c.state)
	check(c.rescue().ok,"Rescue replacement funded by actual harbor treasury")
	check(c.state.fleet.size()==1 and c.state.fleet[0].crew==rescue_crew(c.state.fleet[0]) and int(c.state.debt)==int(coins)+latest_loan(),"Rescue replacement and exact booked harbor debt")
	check(Money.total(c.state)==total and int(home.workforce)+c.crew_count()==people,"Replacement rescue conserves coins and actual sailors")
	check(c.current_port().id==world.START.port and c.state.coins>=rescue_crew(c.state.fleet[0])*Goods.SAILOR_WAGE*5 and c.state.cargo.food>=8,"Rescue harbor essentials and five-day wage reserve")
func _test_ten_days() -> void:
	reset()
	var total: int=Money.total(c.state)
	var coins: float=c.state.coins
	var food: float=c.state.cargo.food
	var costs: Dictionary=Economy.daily_upkeep(c.state.fleet)
	for day in range(10):
		c.wait_day()
		var ports: Array=c.state.ports.duplicate(true)
		var events: Array=Economy.tick_ports(ports,1.0)
		c.apply_economy(ports,events,1)
	check(c.state.coins==coins-10*ceili(costs.wages),"Ten days wages exact")
	check(is_equal_approx(c.state.cargo.food,food-10*float(costs.food)),"Ten days rations exact")
	check(c.state.day==11 and c.state.econDay==11,"Ten days clock and economy advance")
	check(Money.total(c.state)==total and total==int(c.state.coinSupply),"Ten days payroll and shore spending conserve the exact finite coin supply")
	for p in c.state.ports:
		check(is_finite(float(p.cash)) and p.cash>=0,"Port cash finite "+p.id)
		for good in Economy.GOODS:
			check(is_finite(float(p.stocks[good])) and p.stocks[good]>=0,"Port stocks finite "+p.id+" "+good)

func _test_uncrewed_recovery() -> void:
	reset()
	fund_wallet(10000)
	record_recoverable(c.hull("bilge_punt"))
	check(c.salvage_boat("bilge_punt").ok,"Recovery fixture creates real uncrewed salvage")
	var tow_uid: String=str(c.state.fleet[-1].uid)
	c.state.fleet[0].sunk=true
	var result: Dictionary=c.battle_settled("lost",[],{"kind":"patrol"})
	check(c.state.fleet.size()==1 and c.active_fleet().is_empty(),"Only uncrewed towed hull remains after loss")
	check(result.fleetLost,"Uncrewed-only fleet triggers rescue outcome")
	var total: int=Money.total(c.state)
	var people: int=int(c.port(world.START.port).workforce)+c.crew_count()
	var debt_before: int=int(c.state.debt)
	check(c.rescue().ok,"Owned-tow rescue succeeds")
	check(c.state.fleet.size()==1 and str(c.state.fleet[0].uid)==tow_uid and c.active_fleet().size()==1,"Rescue preserves and re-crews the owned tow before buying another hull")
	check(Money.total(c.state)==total and int(c.port(world.START.port).workforce)+c.crew_count()==people and int(c.state.debt)==debt_before+latest_loan(),"Owned-tow rescue conserves coins and people and books exact loan")
	check(not c.find_boat(c.state.flagship).mothballed,"Rescue selects active flagship")
	reset()
	c.state.fleet=[]
	for i in range(8):
		var tow: Dictionary=c.add_boat(c.hull("bilge_punt"),0)
		tow.hp=tow.maxHp*0.35
		tow.water=100
		tow.breaches=[{"area":20.0,"section":"bow"}]
		tow.fuel=0
		tow.ammo=0
		tow.supplies=0
	check(c.active_fleet().is_empty() and c.state.fleet.size()==8,"Full eight-tow fixture has no usable boat")
	result=c.battle_settled("lost",[],{"kind":"patrol"})
	check(result.fleetLost,"Eight-uncrewed result triggers rescue")
	var debt: float=c.state.debt
	total=Money.total(c.state)
	people=int(c.port(world.START.port).workforce)+c.crew_count()
	check(c.rescue().ok,"Eight-tow rescue succeeds without a new hull")
	check(c.state.fleet.size()==8,"Rescue never expands the owned eight-tow roster")
	check(c.active_fleet().size()>=1,"Full-fleet rescue crews an owned hull")
	var flagship: Dictionary=c.find_boat(c.state.flagship)
	check(flagship.crew>=flagship.crewMin and flagship.wounded==0 and not flagship.sunk and not flagship.mothballed,"Recovered flagship has able minimum crew")
	check(flagship.water==0 and flagship.breaches.is_empty() and flagship.engine==1 and flagship.hp>0 and flagship.fuel>0 and flagship.ammo>0,"Full-fleet rescue yields seaworthy supplied boat")
	check(int(c.state.debt)==int(debt)+latest_loan() and c.current_port().id==world.START.port and Money.total(c.state)==total and int(c.port(world.START.port).workforce)+c.crew_count()==people,"Full-fleet rescue charged once and returned home")

# Test setup transfers existing purses/stock. No runtime or owner save writes.
func fund_wallet(target: int) -> void:
	var total: int=Money.total(c.state)
	if int(c.state.coins)>target:
		check(Money.move(c.state,"coins",c.port(world.START.port),"governmentPurse",int(c.state.coins)-target),"Fixture returns excess coins to an existing treasury")
	for p in c.state.ports:
		var need: int=maxi(0,target-int(c.state.coins))
		if need==0:break
		check(Money.move(p,"governmentPurse",c.state,"coins",mini(need,int(p.governmentPurse))),"Fixture borrows only existing treasury coins")
	check(int(c.state.coins)==target and Money.total(c.state)==total and total==int(c.state.coinSupply),"Fixture wallet setup conserves the original finite coin supply")

func top_stock(port: Dictionary,good: String,target: float) -> void:
	var before: float=0.0
	for p in c.state.ports:before+=float(p.stocks.get(good,0.0))
	for p in c.state.ports:
		if is_same(p,port):continue
		var amount: float=minf(maxf(0.0,target-float(port.stocks.get(good,0.0))),float(p.stocks.get(good,0.0)))
		p.stocks[good]=float(p.stocks.get(good,0.0))-amount
		port.stocks[good]=float(port.stocks.get(good,0.0))+amount
	var after: float=0.0
	for p in c.state.ports:after+=float(p.stocks.get(good,0.0))
	check(float(port.stocks[good])>=target and is_equal_approx(before,after),"Commission setup transfers finite existing material "+good)

func record_recoverable(h: Dictionary) -> void:
	# Existing legacy settlement adapter contract; not physical wreck/provenance proof.
	var total: int=Money.total(c.state)
	c.battle_settled("won",[h],{"kind":"patrol"})
	check(c.state.recoverable.get("hull","")==h.id and not c.state.recoverable.get("claimed",true) and Money.total(c.state)==total,"Published victory adapter produces one unpaid unclaimed recovery record")

func latest_loan() -> int:
	for row in c.state.moneyLog:
		if row.get("reason","")=="Harbor rescue loan":
			check(row.get("from","")=="governmentPurse" and row.get("to","")=="coins" and int(row.cash)>0,"Rescue loan is an actual positive treasury-to-captain transfer")
			return int(row.cash)
	check(false,"Rescue loan must appear in the actual money ledger")
	return -1

func rescue_crew(boat: Dictionary) -> int:
	var base: Dictionary=c.hull(str(boat.type))
	return maxi(int(base.crewMin),mini(int(base.crewOptimal),int(world.START.crew)))
