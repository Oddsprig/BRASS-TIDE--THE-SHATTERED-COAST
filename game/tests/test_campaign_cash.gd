extends SceneTree
const Campaign=preload("res://scripts/campaign.gd")
const E=preload("res://scripts/economy.gd")
const M=preload("res://scripts/money.gd")
const B=preload("res://scripts/construction.gd")
var failures: Array=[]
var checks: int=0
var c
var world: Dictionary
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures.append("line%d: %s"%[get_stack()[1].line,message])
		print("FAIL "+failures[-1])
func reset() -> void:
	c.new_game(123)
func home() -> Dictionary:
	return c.port(world.START.port)
func at(id: String) -> void:
	c.state.position=c.port_position(id)
func fund(amount: int) -> void:
	# Fixture funding moves existing treasury/business coins; never edits coinSupply.
	var needed: int=maxi(0,amount-int(c.state.coins))
	for p in c.state.ports:
		for purse in ["governmentPurse","cash"]:
			var moved: int=mini(needed,int(p[purse]))
			M.move(p,purse,c.state,"coins",moved)
			needed-=moved
	check(needed==0,"Fixture is funded from existing port purses")
func conservation(label: String) -> void:
	check(M.total(c.state)==int(c.state.coinSupply),label+" exact global bronze-cash conservation")
func same(a,b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in range(a.size()):
			if not same(a[i],b[i]): return false
		return true
	return a==b
func _initialize() -> void:
	var start: int=Time.get_ticks_msec()
	world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c=Campaign.new(world)
	_test_start_purchase_sell()
	_test_commission()
	_test_salary()
	_test_contracts()
	_test_capture_salvage()
	_test_rescue()
	_test_save()
	_test_hundred_days()
	_test_shared_workforce()
	print("campaign cash: %d checks, %d failures, %d ms"%[checks,failures.size(),Time.get_ticks_msec()-start])
	if failures.is_empty(): quit(0)
	else:
		quit(1)
		assert(failures.is_empty(),"Cash campaign integration failures above")
func _test_start_purchase_sell() -> void:
	reset()
	check(c.state.fleet.size()==1 and c.state.fleet[0].crew==5 and c.state.fleet[0].type==world.START.hull,"One inherited starter with five sailors")
	check(c.state.coins==15000 and c.state.crewPurse==5000,"Exact15000 captain and5000 crew cash endowment")
	var p: Dictionary=home()
	var h: Dictionary=c.hull(world.START.hull)
	var q: Dictionary=c.ship_quote(h,p)
	var advance: int=E.recruit_cost(p,h.crewMin)
	fund(q.readyPrice+advance+5000)
	var coins: int=c.state.coins
	var crew_purse: int=c.state.crewPurse
	var workforce: int=p.workforce
	var pool: int=p.recruits
	var stock: int=p.shipStock[h.id]
	var bought: Dictionary=c.buy_boat(h.id)
	check(bought.ok,"Real hull plus minimum crew affordable after explicit transfer fixture")
	if bought.ok:
		var boat: Dictionary=c.state.fleet[-1]
		check(c.state.coins==coins-q.readyPrice-advance and c.state.crewPurse==crew_purse+advance,"Hull price paid; advance transferred to sailors")
		check(p.workforce==workforce-h.crewMin and p.recruits==pool-h.crewMin and p.shipStock[h.id]==stock-1,"Purchase consumes physical hull and civilian hires")
		check(boat.fuel==0 and boat.ammo==0 and boat.supplies==0,"Purchased hull has no free working stores")
		conservation("Hull purchase")
		# Physical stock fixture isolates conversion: exactly one50-round case available.
		p.stocks.ammo=1.0
		p.stocks.fuel=0.0
		p.stocks.supplies=0.0
		coins=c.state.coins
		var unit: int=E.price(p,"ammo")
		check(c.resupply_boat(boat.uid).ok,"Ready rounds can be purchased")
		check(boat.ammo==50 and p.stocks.ammo==0 and c.state.coins==coins-unit,"One physical case converts to50 rounds at one case price")
		conservation("Case conversion")
		var business_cash: int=p.cash
		M.move(p,"cash",p,"governmentPurse",business_cash)
		var before: Dictionary=c.state.duplicate(true)
		check(not c.sell_boat(boat.uid).ok and same(before,c.state),"Empty business purse cannot buy used hull")
		M.move(p,"governmentPurse",p,"cash",business_cash)
		workforce=p.workforce
		pool=p.recruits
		var household: int=p.householdPurse
		var total_crew: int=c.crew_count()
		var savings: int=floori(float(c.state.crewPurse)*boat.crew/total_crew)
		check(c.sell_boat(boat.uid).ok,"Funded business purchases used hull")
		check(p.workforce==workforce+boat.crew and p.recruits==pool+boat.crew and p.householdPurse==household+savings,"Discharged sailors return workforce and actual shared savings")
		conservation("Used-hull sale")
func _test_commission() -> void:
	reset()
	var p: Dictionary=home()
	var h: Dictionary=c.hull(world.START.hull)
	var q: Dictionary=c.ship_quote(h,p)
	fund(q.commissionPrice+10000)
	for good in q.materials:
		p.stocks[good]=q.materials[good]+100.0
	q=c.ship_quote(h,p)
	fund(q.commissionPrice+10000)
	var coins: int=c.state.coins
	var before: Dictionary=p.stocks.duplicate()
	var result: Dictionary=c.commission(h.id)
	check(result.ok,"Material-funded commission books atomically")
	if not result.ok: return
	var order: Dictionary=p.buildQueue[-1]
	check(order.escrow>0 and c.state.coins==coins-q.commissionPrice,"Quote paid with real construction wage escrow")
	for good in q.materials:
		check(is_equal_approx(p.stocks[good],before[good]-q.materials[good]),"Commission consumes quoted "+good)
	check(not c.collect_boat(p.buildQueue.size()-1).ok,"Unworked hull cannot be collected")
	conservation("Commission booking")
	var paid_before: int=p.householdPurse+p.expertPurse
	for day in range(200):
		if order.get("ready",false): break
		# A new day releases yesterday's jobs; fixed workforce is never enlarged.
		p.workers=0
		p.publicWorkers=0
		p.availableWorkers=p.workforce
		p.availableSpecialists=p.get("specialistWorkers",20)
		if p.has("_lastWorkersField"): p._lastWorkersField=0
		B.begin_day(p)
		B.advance(p,order,1.0)
		conservation("Construction day%d"%day)
	check(order.get("ready",false),"Paid actual worker-days finish commissioned hull")
	check(order.escrow==0 and p.householdPurse+p.expertPurse>paid_before,"Completed labor escrow reaches wage recipients without residue")
	var index: int=p.buildQueue.find(order)
	var count: int=c.state.fleet.size()
	check(c.collect_boat(index).ok and c.state.fleet.size()==count+1,"Worked hull collectible once")
	check(not c.collect_boat(index).ok,"No duplicate construction collection")
	conservation("Commission collection")
func _test_salary() -> void:
	reset()
	c.state.position={"x":1300.0,"y":850.0}
	var coins: int=c.state.coins
	var crew: int=c.state.crewPurse
	c.apply_economy(c.state.ports,[],1)
	check(c.state.coins==coins-500 and c.state.crewPurse==crew+500,"Five sailors receive100cash each per day into shared purse")
	conservation("Salary")
	M.move(c.state,"coins",home(),"governmentPurse",int(c.state.coins))
	var morale: float=c.state.morale
	var speed: float=c.state.fleet[0].spec.speed
	c.apply_economy(c.state.ports,[],1)
	check(c.state.wageArrears==500 and c.state.morale<morale and c.state.fleet[0].spec.speed<speed,"Missed pay creates liability and real morale/performance loss")
	fund(500)
	crew=c.state.crewPurse
	check(c.pay_wage_arrears().ok and c.state.wageArrears==0 and c.state.crewPurse==crew+500,"Actual cash repayment clears liability into crew purse")
	conservation("Arrears repayment")
func _test_contracts() -> void:
	reset()
	var delivery: Dictionary={}
	for offer in c.available_contracts():
		if not offer.story and offer.kind=="delivery": delivery=offer
	var sponsor: Dictionary=home()
	var business: int=sponsor.cash
	var supplies: float=sponsor.stocks.supplies
	var accepted: Dictionary=c.accept_contract(delivery.id)
	check(accepted.ok,"Business-funded sealed freight contract accepted")
	if accepted.ok:
		check(c.state.activeContract.escrow==delivery.reward and sponsor.cash==business-delivery.reward and sponsor.stocks.supplies==supplies-delivery.cargo.qty,"Sponsor cash and physical freight move into escrow/hold")
		conservation("Contract escrow")
		check(c.abandon_contract().ok and sponsor.cash==business and sponsor.stocks.supplies==supplies,"Abandon refunds actual sponsor cash and docked freight")
		conservation("Contract refund")
	c.state.cargo.food=0
	for i in range(8):
		var mission: Dictionary=world.MISSIONS[i]
		at(mission.port)
		var chosen: Dictionary={}
		for offer in c.available_contracts():
			if offer.id==mission.id: chosen=offer
		var p: Dictionary=c.port(mission.port)
		# Sponsors may need a lawful inter-treasury transfer for final expensive blockade jobs.
		if not chosen.is_empty() and p.governmentPurse<chosen.reward:
			for other in c.state.ports:
				if other.id!=p.id:
					M.move(other,"governmentPurse",p,"governmentPurse",mini(int(other.governmentPurse),maxi(0,int(chosen.reward-p.governmentPurse))))
		var result: Dictionary=c.accept_contract(mission.id)
		check(result.ok,"Story%d fully funded"%(i+1))
		if not result.ok: continue
		conservation("Story%d escrow"%(i+1))
		at(mission.targetPort)
		check(not c.finish_contract().ok,"Story%d requires enemy clearance"%(i+1))
		var owner: Dictionary=c.fleet_owner("story-%d"%i)
		var owner_coins: int=owner.coins
		var coins: int=c.state.coins
		var specs: Array=[]
		for id in mission.enemyHulls: specs.append(c.hull(id))
		c.battle_settled("won",specs,{"kind":"contract","ownerId":owner.id})
		check(c.state.missionIndex==i+1 and c.state.coins==coins+int(chosen.reward)+floori(owner_coins*0.3),"Story%d reward is escrow plus captured real purse"%(i+1))
		coins=c.state.coins
		check(not c.finish_contract().ok and c.state.coins==coins,"Story%d no second reward claim"%(i+1))
		conservation("Story%d settlement"%(i+1))
	check(c.state.completed and c.state.missionIndex==8,"All eight funded story protocols complete")
func _test_capture_salvage() -> void:
	reset()
	check(not c.salvage_boat("bilge_punt").ok,"Salvage requires a pending actual wreck")
	var owner: Dictionary=c.fleet_owner("patrol-0")
	var value: int=owner.coins
	var coins: int=c.state.coins
	c.battle_settled("won",[c.hull("bilge_punt")],{"kind":"patrol","id":owner.id,"ownerId":owner.id})
	check(c.state.coins==coins+floori(value*0.3) and owner.coins==value-floori(value*0.3),"Capture transfers real owner purse rather than minting bounty")
	check(c.salvage_boat("bilge_punt").ok,"Funded pending wreck can be recovered")
	var before: Dictionary=c.state.duplicate(true)
	check(not c.salvage_boat("bilge_punt").ok and same(before,c.state),"Recovered wreck cannot be claimed twice")
	check(c.state.fleet[-1].crew==0 and c.state.fleet[-1].fuel==0 and c.state.fleet[-1].hp==c.state.fleet[-1].maxHp*0.35,"Salvage is damaged uncrewed unstored physical hull")
	conservation("Capture and salvage")
func _test_rescue() -> void:
	reset()
	c.state.fleet=[]
	var p: Dictionary=home()
	var inventory: int=0
	for amount in p.shipStock.values(): inventory+=amount
	var workers: int=p.workforce
	var pool: int=p.recruits
	var debt: int=c.state.debt
	var result: Dictionary=c.rescue()
	check(result.ok,"Funded stocked harbor rescues lost captain")
	if result.ok:
		var after: int=0
		for amount in p.shipStock.values(): after+=amount
		var boat: Dictionary=c.state.fleet[0]
		check(after==inventory-1 and p.workforce==workers-boat.crew and p.recruits==pool-boat.crew,"Rescue consumes real hull stock and civilian sailors")
		check(c.state.debt>debt and c.active_fleet().size()==1,"Treasury loan creates usable active boat and liability")
		conservation("Rescue loan and purchases")
		fund(1000)
		var treasury: int=p.governmentPurse
		var captain: int=c.state.coins
		debt=c.state.debt
		check(c.repay_loan(500).ok and c.state.coins==captain-500 and p.governmentPurse==treasury+500 and c.state.debt==debt-500,"Loan repayment moves actual cash to lending treasury and reduces liability")
		conservation("Loan repayment")
	reset()
	c.state.fleet=[]
	for id in home().shipStock: home().shipStock[id]=0
	var before: Dictionary=c.state.duplicate(true)
	check(not c.rescue().ok and same(before,c.state),"Empty yard cannot fabricate a rescue hull")
	reset()
	c.state.fleet=[]
	for i in range(8):
		var tow: Dictionary=c.add_boat(c.hull(world.START.hull),0)
		tow.hp=tow.maxHp*0.35
	p=home()
	p.workers=0
	p.publicWorkers=0
	p.availableWorkers=p.workforce
	p.availableSpecialists=p.get("specialistWorkers",20)
	if p.has("_lastWorkersField"): p._lastWorkersField=0
	check(c.rescue().ok and c.state.fleet.size()==8 and not c.active_fleet().is_empty(),"Eight-tow rescue refits existing hull without exceeding cap")
	conservation("Eight-hull rescue")
func _test_save() -> void:
	reset()
	c.state.fleet[0].hp-=17
	c.state.fleet[0].wounded=1
	c.state.fleet[0].water=7.5
	c.state.fleet[0].breaches=[{"area":4.0,"section":"engine"}]
	c.state.fleet[0].ammo=31
	c.state.fleet[0].supplies=2.75
	c.state.ports[0].stocks.iron=42.25
	var snapshot: Dictionary=c.state.duplicate(true)
	var bad: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	bad.coins+=1
	check(not c.restore(bad).ok and same(snapshot,c.state),"Corrupt ledger refusal leaves current voyage unchanged")
	bad=JSON.parse_string(JSON.stringify(snapshot))
	bad.ports[0]=null
	check(not c.restore(bad).ok and same(snapshot,c.state),"Malformed harbor is rejected before counting money or replacing live voyage")
	bad=JSON.parse_string(JSON.stringify(snapshot))
	bad.coins=-10
	check(not c.restore(bad).ok and same(snapshot,c.state),"Negative purse is rejected without clamping a replacement voyage into existence")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(snapshot))
	check(c.restore(saved).ok,"Valid bronze-cash save restores")
	for key in ["ports","cargo","position","coins","crewPurse","wageArrears","fleetOwners","activeContract","debt","recoverable"]:
		check(same(c.state[key],snapshot[key]),"JSON preserves cash campaign "+key)
	for key in ["hp","wounded","water","breaches","ammo","supplies","crew","uid"]:
		check(same(c.state.fleet[0][key],snapshot.fleet[0][key]),"JSON preserves damaged boat "+key)
	conservation("Save restore")
func _test_hundred_days() -> void:
	reset()
	var yard: Dictionary=home()
	var design: Dictionary=c.hull(world.START.hull)
	var quote: Dictionary=c.ship_quote(design,yard)
	for good in quote.materials:
		yard.stocks[good]=quote.materials[good]+100.0
	quote=c.ship_quote(design,yard)
	fund(quote.commissionPrice+10000)
	check(c.commission(design.id).ok,"Hundred-day core fixture includes a real funded construction job")
	var max_work: float=0.0
	for day in range(100):
		c.wait_day()
		var ports: Array=c.state.ports.duplicate(true)
		var messages: Array=E.tick_ports(ports,1.0)
		c.apply_economy(ports,messages,1)
		for order in home().buildQueue:
			max_work=maxf(max_work,float(order.get("workedDays",0)))
		conservation("Fullcore NPC yards day%d"%day)
	check(max_work>0.0,"Full-core run actually pays/advances yard labor alongside NPC economy")
	for p in c.state.ports:
		check(p.cash>=0 and p.householdPurse>=0 and p.expertPurse>=0 and p.governmentPurse>=0,"Finite settlement purses "+p.id)
		for good in E.GOODS:
			check(is_finite(float(p.stocks[good])) and p.stocks[good]>=0,"Finite physical "+p.id+" "+good)

func _test_shared_workforce() -> void:
	reset()
	var p: Dictionary=home()
	var h: Dictionary=c.hull(world.START.hull)
	var quote: Dictionary=c.ship_quote(h,p)
	fund(quote.commissionPrice+10000)
	check(c.commission(h.id).ok,"Shared-worker fixture funds a physical commission")
	p.workers=p.workforce-5
	p.publicWorkers=0
	p.availableWorkers=5
	p.availableSpecialists=5
	B.begin_day(p)
	B.advance(p,p.buildQueue[0],1.0)
	check(is_equal_approx(float(p.get("_yardWorkersUsed",0)),5.0),"Construction actually reserves all five idle civilians including experts")
	c.state.fleet[0].hp-=10
	var before: Dictionary=c.state.duplicate(true)
	check(not c.repair_boat(c.state.fleet[0].uid).ok and same(before,c.state),"Drydock cannot reuse civilians already paid to build a hull today")
	conservation("Shared construction and service workforce")
