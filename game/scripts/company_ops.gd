extends RefCounted
const Routes=preload("res://scripts/route_cache.gd")
## Main-thread physical fleet-company binding. Accounting metadata holds no purse.
const Companies=preload("res://scripts/shipping_companies.gd")
const TradeRules=preload("res://scripts/trade_rules.gd")
const Goods=preload("res://scripts/goods.gd")
const Economy=preload("res://scripts/economy.gd")
const Money=preload("res://scripts/money.gd")
const Politics=preload("res://scripts/politics.gd")
const Factions=preload("res://scripts/factions.gd")
const Expedition=preload("res://scripts/expedition.gd")

static func api(c):
	if c.shipping==null:c.shipping=Companies.new(Goods.ITEMS,Money,Politics,func(core,b):return float(core.fitted_spec(b).get("cargo",0)))
	return c.shipping

static func ensure(c) -> void:
	api(c).ensure(c)
	var used: Dictionary={}
	for b in api(c)._boats(c.state):
		if b.get("uid") is String and not str(b.uid).is_empty():used[b.uid]=true
	for o in c.state.fleetOwners:
		for i in range(o.boats.size()):
			var boat: Dictionary=o.boats[i]
			if boat.get("uid") is String and not str(boat.uid).is_empty():continue
			var id: String="legacy-%s-%d"%[str(o.id),i]
			while used.has(id):id+="-next"
			boat.uid=id;used[id]=true
	for b in c.state.fleet:
		if not b.has("storedPort"):b.storedPort=""
		if not b.has("mothballed"):b.mothballed=false

static func create(c,uids: Array,destination: String,good: String,capital: int,limits: Dictionary) -> Dictionary:
	for uid in uids:
		if c.CrisisOps.Transport.assigned(c.state,str(uid))>0:return c.fail("Discharge passengers before assigning their carrier to a company.")
		if int(c.state.get("captiveBerths",{}).get(str(uid),0))>0:return c.fail("Release captives before assigning their carrier to a company.")
	ensure(c)
	var probe: Dictionary=c.state.duplicate(true)
	probe.fleet=probe.fleet.filter(func(b):return b.uid not in uids)
	c.Manifest.allocate(probe)
	if not probe.cargoManifest.get("unassigned",{}).is_empty():return c.fail("Unload or store cargo first: the retained traveling fleet must carry its actual manifest.")
	var result: Dictionary=api(c).create(c,uids,destination,good,capital,limits)
	if not result.ok:return result
	var owner: Dictionary=c.fleet_owner(str(result.id))
	owner.commandPremium=75
	owner.commandName="Master of "+str(owner.boats[0].name)
	owner.workingBasis={}
	for basis_good in ["fuel","supplies","ammo"]:
		var quantity: float=0
		for boat in owner.boats:quantity+=float(boat[basis_good])
		var cost: int=ceili(quantity*Goods.cost(basis_good)/(50.0 if basis_good=="ammo" else 1.0))
		owner.workingBasis[basis_good]={"qty":quantity,"cost":cost}
	owner.workingCapitalIn=owner.workingBasis.values().reduce(func(total,row):return total+int(row.cost),0)
	owner.hullBasis={}
	for boat in owner.boats:owner.hullBasis[boat.uid]={"value":ceili(float(c.fitted_spec(boat).get("price",0))),"charged":false}
	for boat in owner.boats:
		c.fit_boat(boat)
		boat.economyBaseSpeed=float(boat.spec.speed)
		boat.economyBaseFireRate=float(boat.spec.fireRate)
	c.NavalAI.ensure(c.state,c.data)
	c.Fleets.dock(owner,c.current_port(),c)
	var patrol: Dictionary=api(c)._patrol(c.state,owner.id)
	c.NavalLifecycle.route(c,patrol,c.NavalAI.arrived(c,owner,c.current_port()))
	c.Manifest.allocate(c.state)
	result.message="Company chartered with the same actual boats and crews. Its master is one of those sailors and earns75 extra coins/day; all route costs use its real purse."
	return result

static func owner(c,id: String) -> Dictionary:
	return c.fleet_owner(id)

static func book(c,id: String) -> Dictionary:
	return c.state.get("shippingCompanies",{}).get(id,{})

static func met(c,o: Dictionary) -> bool:
	var p: Dictionary=c.current_port()
	return not p.is_empty() and api(c)._docked(c,o,str(p.id)) and Politics.permit(c,"service").ok

static func capital(c,id: String,amount: int) -> Dictionary:
	var o: Dictionary=owner(c,id)
	if o.is_empty() or not met(c,o):return c.fail("Meet this company at the same actual harbor to hand over coins.")
	var result: Dictionary=api(c).capital(c,id,amount)
	return c.ok("Transferred actual operating coins; capital is not profit.") if result.ok else result

static func pay_arrears(c,id: String) -> Dictionary:
	var o: Dictionary=owner(c,id)
	if o.is_empty() or not met(c,o):return c.fail("Meet this company in harbor to settle its crew account.")
	var amount: int=mini(int(o.coins),int(o.wageArrears))
	if amount<=0:return c.fail("No affordable company wage arrears.")
	Money.move(o,"coins",o,"crewPurse",amount,"Company crew arrears",c.state.moneyLog)
	o.wageArrears-=amount;record(c,o,"wages",amount)
	return c.ok("Paid %d coins of company crew arrears."%amount)

static func recall(c,id: String) -> Dictionary:
	var result: Dictionary=api(c).recall(c,id)
	if not result.ok:return result
	var o: Dictionary=owner(c,id)
	var p: Dictionary=api(c)._patrol(c.state,id)
	if o.active:c.NavalLifecycle.route(c,p,str(book(c,id).home))
	return c.ok("Recall sent. The actual fleet must sail home; its position has not changed.")

static func collect(c,id: String) -> Dictionary:
	var result: Dictionary=api(c).collect(c,id)
	if not result.ok:return result
	for boat in c.state.fleet:
		c.fit_boat(boat)
		boat.erase("economyBaseSpeed");boat.erase("economyBaseFireRate")
	c.Manifest.allocate(c.state)
	return c.ok("The same hulls, fittings, stores, crew savings, capital and remaining cargo are back aboard your fleet.")

static func record(c,o: Dictionary,event: String,coins: int,good: String="",qty: float=0) -> void:
	if c==null or not o.get("playerCompany",false):return
	api(c).record(c,o,event,coins,good,qty)

static func reconcile(c,o: Dictionary) -> void:
	if c==null or not o.get("playerCompany",false):return
	var b: Dictionary=book(c,str(o.id))
	if b.is_empty() or b.status=="collected":return
	var missing: float=maxf(0,float(b.basisQty)-float(o.cargo.get(b.good,0)))
	if missing>0.000001:record(c,o,"loss",0,str(b.good),missing)
	o.tradeCargo=float(b.basisQty)

static func daily(c) -> void:
	for o in c.state.fleetOwners:
		reconcile(c,o);reconcile_working(c,o)
		if o.get("playerCompany",false):
			if not o.boats.any(func(boat):return not boat.sunk):
				o.active=false
				api(c)._patrol(c.state,str(o.id)).active=false
			for boat in o.boats:
				var basis: Dictionary=o.get("hullBasis",{}).get(boat.uid,{})
				if boat.sunk and not basis.is_empty() and not basis.charged:
					record(c,o,"capital_loss",int(basis.value));basis.charged=true
	api(c).daily(c)

static func market_limit(c,o: Dictionary,p: Dictionary,buying: bool,good: String,price: int) -> int:
	if c==null:return 0
	if not TradeRules.allowed(c.state.get("tradeLaw",{}).get("bans",[]),str(o.faction),str(p.faction),good,float(c.state.day)):return 0
	if Factions.relation(c.state,str(o.faction),str(p.faction))<=-20:return 0
	if buying and good in Politics.access(c,p).restrictedGoods:return 0
	return maxi(0,floori(float(api(c).trade_limit(c,o,buying,good,price))))

static func hold(c,o: Dictionary) -> bool:
	var b: Dictionary=book(c,str(o.id))
	if b.is_empty():return true
	if b.recall:return str(o.atPort)==str(b.home)
	if str(o.atPort)==str(b.home):return float(b.basisQty)<=0
	if str(o.atPort)==str(b.destination):return floori(float(b.basisQty))>0
	return false

static func plan(state: Dictionary,o: Dictionary,dock: Dictionary,recovery: String) -> Dictionary:
	var b: Dictionary=state.get("shippingCompanies",{}).get(o.id,{})
	if b.is_empty():return {}
	o.route=[b.home,b.destination]
	var at: String=str(o.get("atPort",""))
	var dest: String=str(o.get("destination",b.destination))
	var reason: String="Following the chartered two-harbor company route."
	if not recovery.is_empty():dest=b.home;reason=recovery+" Company replacements require actual owned hulls."
	elif b.recall:dest=b.home;reason="Physical recall to home harbor."
	elif at==b.home:
		dest=b.destination if float(b.basisQty)>0 else b.home
		reason="Chartered cargo aboard." if float(b.basisQty)>0 else "Waiting for actual affordable stock within the charter's price and reserve limits."
	elif at==b.destination:
		dest=b.destination if floori(float(b.basisQty))>0 else b.home
		reason="Waiting for an actual buyer within the charter's selling floor." if float(b.basisQty)>0 else "Sale complete; returning for another actual cargo."
	var target: Dictionary={}
	for p in state.ports:
		if p.id==dest:target=p
	var blockade: Dictionary=state.get("tradeIntel",{}).get("blockades",{}).get(dest,{})
	if not b.recall and not target.is_empty() and (Factions.relation(state,str(o.faction),str(target.faction))<=-20 or (float(b.limits.risk)<0.75 and bool(blockade.get("blocked",false)))):
		dest=b.home;reason="Route held: hostile customs or observed blockade exceeds the charter's risk allowance."
	return {"destination":dest,"reason":reason}

static func validate(state: Dictionary,world: Dictionary) -> String:
	if not state.has("shippingCompanies"):return ""
	if state.shippingCompanies is Dictionary and state.shippingCompanies.is_empty() and not state.fleetOwners.any(func(o):return o.get("playerCompany",false)):return ""
	var check_api=Companies.new(Goods.ITEMS,Money,Politics,Callable())
	var error: String=check_api.validate(state,{"ports":world.PORTS,"hulls":world.HULLS})
	if not error.is_empty():return error
	for o in state.fleetOwners:
		if not o.get("playerCompany",false):continue
		if o.get("commandPremium",0)!=75:return "Noncanonical company master wage."
		if not o.get("commandName") is String or o.commandName.length()>160:return "Invalid company master identity."
		if not o.get("workingBasis") is Dictionary or o.workingBasis.size()!=3 or not o.get("hullBasis") is Dictionary or o.hullBasis.size()>96:return "Invalid company working/hull basis."
		for good in ["fuel","supplies","ammo"]:
			var row=o.workingBasis.get(good)
			if not row is Dictionary or not check_api._num(row.get("qty")) or row.qty<0 or row.qty>1000000000 or not check_api._whole(row.get("cost")) or (row.qty==0 and row.cost!=0):return "Invalid company working stock basis."
		if state.shippingCompanies[o.id].status!="collected":
			var hull_ids: Array=o.boats.map(func(boat):return str(boat.uid))
			if o.hullBasis.size()!=hull_ids.size():return "Missing company hull capital identity."
			for uid in o.hullBasis:
				if uid not in hull_ids:return "Unknown company hull capital identity."
		for row in o.hullBasis.values():
			if not row is Dictionary or not check_api._whole(row.get("value")) or not row.get("charged") is bool:return "Invalid company hull capital basis."
	return ""

static func consume_working(c,o: Dictionary,good: String,quantity: float) -> void:
	if c==null or not o.get("playerCompany",false) or quantity<=0:return
	var basis: Dictionary=o.get("workingBasis",{}).get(good,{})
	if basis.is_empty() or float(basis.qty)<=0:return
	var used: float=minf(quantity,float(basis.qty))
	var cost: int=int(basis.cost) if used+0.000001>=float(basis.qty) else floori(float(basis.cost)*used/float(basis.qty))
	basis.qty=maxf(0,float(basis.qty)-used);basis.cost-=cost
	record(c,o,"stores",cost)

static func reconcile_working(c,o: Dictionary) -> void:
	if not o.get("playerCompany",false):return
	for good in ["fuel","supplies","ammo"]:
		var held: float=0
		for boat in o.boats:
			if not boat.sunk:held+=float(boat[good])
		var commercial: Dictionary=book(c,str(o.id))
		held+=maxf(0,float(o.cargo.get(good,0))-(float(commercial.get("basisQty",0)) if commercial.get("good","")==good else 0))*(50.0 if good=="ammo" else 1.0)
		var based: float=float(o.get("workingBasis",{}).get(good,{}).get("qty",0))
		if based>held+0.000001:consume_working(c,o,good,based-held)

static func add_working(c,o: Dictionary,good: String,quantity: float,cost: int) -> void:
	if good not in ["fuel","supplies","ammo"]:return
	var row: Dictionary=o.workingBasis[good]
	row.qty+=quantity*(50.0 if good=="ammo" else 1.0)
	row.cost+=cost

static func quote(c,uids: Array,destination: String,good: String) -> Dictionary:
	var home: Dictionary=c.current_port();var target: Dictionary=c.port(destination)
	if home.is_empty() or target.is_empty() or good not in Goods.ITEMS:return {"message":"Choose an actual harbor route and good."}
	var crew: float=0;var hold_space: float=0;var speed: float=100000;var boats: int=0
	for boat in c.state.fleet:
		if boat.uid not in uids:continue
		crew+=float(boat.crew);hold_space+=float(c.fitted_spec(boat).cargo);speed=minf(speed,float(c.fitted_spec(boat).speed));boats+=1
	var path: Array=Routes.path(c,home,target)
	var distance: float=0
	for i in range(1,path.size()):distance+=c.distance(path[i-1],path[i])
	var days: float=2*distance/maxf(1,speed*0.38*float(c.data.get("CAMPAIGN_SCALE",1)))/45.0+0.25
	var wages: int=ceili(crew*100+(75 if boats>0 else 0))
	var buy: int=Economy.price(home,good,"buy");var sell: int=Economy.price(target,good,"sell")
	return {"days":days,"wages":wages,"hold":hold_space,"buy":buy,"sell":sell,"message":"Current quotes: buy %d / sell %d coins per lot; %.2f days projected round trip; %d coins/day payroll, including the master; %.1f physical hold space. Price spread must cover payroll, consumed fuel, repairs and losses. Crew food is bought from their earned savings. Quotes may change before arrival."%[buy,sell,days,wages,hold_space]}
