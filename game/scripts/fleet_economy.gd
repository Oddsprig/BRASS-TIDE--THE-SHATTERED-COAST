extends RefCounted
## Fleet-owned circulating bronze cash. All coins enter through explicit purse transfers.
const TradeRules=preload("res://scripts/trade_rules.gd")
const Damage=preload("res://scripts/damage.gd")
const Economy=preload("res://scripts/economy.gd")
const Goods=preload("res://scripts/goods.gd")
const SAILOR_WAGE: int=100

static func _log(owner: Dictionary,message: String) -> void:
	owner.log.push_front(message)
	if owner.log.size()>16:
		owner.log.resize(16)

static func _find(items: Array,id: String) -> Dictionary:
	for item in items:
		if item.id==id:
			return item
	return {}

static func _integer(value) -> int:
	if (value is float or value is int) and is_finite(float(value)):
		return maxi(0,int(floor(value)))
	return 0

static func normalize_owner(owner: Dictionary) -> Dictionary:
	# Mutate the supplied owner in place: no purse creation or boat replacement.
	var defaults: Dictionary={"id":"","name":"Fleet owner","homePort":"","faction":"raiders","kind":"patrol","coins":0,"crewPurse":0,"wageArrears":0,"morale":85.0,"cargo":{},"boats":[],"route":[],"progress":0.0,"atPort":"","active":true,"log":[],"tradeGood":"timber","tradeCargo":0.0,"wageRemainder":0.0,"daysOperated":0.0,"performanceFactor":1.0,"lastPayroll":0,"lastFoodConsumed":0.0,"lastFuelConsumed":0.0}
	for key in defaults:
		if not owner.has(key):
			owner[key]=defaults[key].duplicate(true) if defaults[key] is Dictionary or defaults[key] is Array else defaults[key]
	if not owner.cargo is Dictionary:
		owner.cargo={}
	for good in Goods.ITEMS:
		if not owner.cargo.has(good):
			owner.cargo[good]=0.0
	if not owner.tradeCargo is float and not owner.tradeCargo is int:
		owner.tradeCargo=0.0
	if not Goods.ITEMS.has(owner.tradeGood):
		owner.tradeGood="timber"
	for boat in owner.boats:
		if not boat.get("economySpecOwned",false):
			boat.spec=boat.spec.duplicate(true)
			boat.economySpecOwned=true
	return owner

static func upkeep(owner: Dictionary) -> Dictionary:
	var crew: float=0.0
	var fuel: float=0.0
	for boat in owner.boats:
		if boat.sunk:
			continue
		crew+=maxf(0.0,float(boat.crew))
		fuel+=clampf(0.11+(float(boat.spec.get("size",14))-10.0)/38.0*0.05+(float(boat.spec.get("speed",75))-40.0)/140.0*0.03,0.1,0.2)*maxf(0.2,float(boat.spec.get("fuelUse",1)))
	return {"wages":crew*SAILOR_WAGE+(75 if owner.get("playerCompany",false) and crew>0 else 0),"food":crew*0.08,"fuel":fuel}

static func total_coins(owners: Array) -> int:
	var total: int=0
	for owner in owners:
		total+=_integer(owner.coins)+_integer(owner.crewPurse)
	return total

static func create_owners(ports: Array,world: Dictionary) -> Array:
	var owners: Array=[]
	var routes: Array=world.get("ROUTES",[])
	if routes.is_empty():
		return owners
	for i in range(9):
		var route: Array=routes[(i*3+1)%routes.size()]
		var home: Dictionary=_find(ports,str(route[0]))
		if home.is_empty():
			continue
		var kind: String="raider" if i%3==0 else ("trader" if i%3==1 else "patrol")
		if kind=="raider":
			var refuge: Dictionary=_find(ports,"rust_anchorage" if i%2==0 else "shatter_spire")
			if not refuge.is_empty():
				home=refuge
				route=[home.id,str(route[1]) if str(route[1])!=str(home.id) else "brass_haven"]
		var strength: int=1+i%3
		var ids: Array=["bilge_punt"]
		if strength>=2:
			ids.append("scab_cutter")
		if strength>=3:
			ids.append("barbed_lance")
		var boats: Array=[]
		for id in ids:
			var spec: Dictionary=_find(world.get("HULLS",[]),id)
			if not spec.is_empty():
				var boat: Dictionary=Damage.create_ship(spec,{"fuel":0.0,"ammo":0.0,"supplies":0.0})
				boat.uid="npc-%d-%d"%[i,boats.size()]
				boats.append(boat)
		# Existing naval crews are allocated out of the same fixed civilian population.
		# Never leave those sailors simultaneously available for industrial jobs/recruitment.
		var workforce: int=_integer(home.get("workforce",0))
		var idle: int=_integer(home.get("availableWorkers",maxi(0,workforce-_integer(home.get("workers",0))-_integer(home.get("publicWorkers",0)))))
		var civilians: int=mini(workforce,mini(idle,_integer(home.get("recruits",0))))
		var assigned: int=0
		for boat in boats:
			boat.crew=minf(boat.crew,maxi(0,civilians-assigned))
			assigned+=int(boat.crew)
		home.workforce=workforce-assigned
		home.availableWorkers=maxi(0,idle-assigned)
		home.recruits=maxi(0,_integer(home.get("recruits",0))-assigned)
		var cargo: Dictionary={}
		for good in Goods.ITEMS:
			cargo[good]=0.0
		var owner: Dictionary={"id":"patrol-%d"%i,"name":"Reef raiders" if i%3==0 else "Coastal convoy","homePort":home.id,"faction":"raiders" if kind=="raider" else home.get("faction","compact"),"kind":kind,"coins":0,"crewPurse":0,"wageArrears":0,"morale":85.0,"cargo":cargo,"boats":boats,"route":route.duplicate(),"progress":float(i%5)/5.0,"atPort":home.id if i%5==0 else "","active":true,"log":[],"wageRemainder":0.0,"performanceFactor":1.0,"daysOperated":0.0,"lastPayroll":0,"lastFoodConsumed":0.0,"lastFuelConsumed":0.0,"tradeGood":_trade_good(home),"tradeCargo":0}
		# Fourteen wage-days plus three days' rations/fuel: an explicit capital transfer,
		# capped by the existing sponsoring purse. Hulls are the initial physical fleet.
		var costs: Dictionary=upkeep(owner)
		var requested: int=ceili(costs.wages*14.0+costs.food*3.0*Goods.cost("food")+costs.fuel*3.0*Goods.cost("fuel"))
		var purse: String="cash" if kind=="trader" else "governmentPurse"
		var capital: int=mini(requested,_integer(home.get(purse,0)))
		home[purse]=_integer(home.get(purse,0))-capital
		owner.coins=capital
		_log(owner,"Capital: %d bronze coins transferred from %s."%[capital,home.name])
		owners.append(owner)
	return owners

static func _trade_good(port: Dictionary) -> String:
	match port.get("industry","trade"):
		"timber": return "timber"
		"foundry": return "iron"
		"refinery": return "fuel"
		"shipyard": return "supplies"
		"fishery","agriculture": return "food"
	return "timber"

static func subsidize(owner: Dictionary,port: Dictionary,amount: int) -> int:
	if amount<=0 or owner.get("playerCompany",false):
		return 0
	var transfer: int=mini(amount,_integer(port.get("governmentPurse",0)))
	port.governmentPurse=_integer(port.get("governmentPurse",0))-transfer
	owner.coins+=transfer
	if transfer>0:
		_log(owner,"Public subsidy: %d coins."%transfer)
	return transfer

static func _capacity(owner: Dictionary) -> float:
	var result: float=0.0
	for boat in owner.boats:
		if not boat.sunk:
			result+=float(boat.spec.get("cargo",0))
	return result

static func allowed_trade(owner: Dictionary,port: Dictionary,good: String,core=null) -> bool:
	var bans: Array=owner.get("tradeBans",port.get("tradeBans",[])) if core==null else core.state.get("tradeLaw",{}).get("bans",[])
	var day: float=float(owner.get("tradeLawDay",port.get("tradeLawDay",0))) if core==null else float(core.state.day)
	return TradeRules.allowed(bans,str(owner.get("faction","")),str(port.get("faction","")),good,day)

static func _purchase(owner: Dictionary,port: Dictionary,good: String,quantity: int,crew_paid: bool=false,working: bool=false,core=null,commercial: bool=false) -> int:
	if quantity<=0 or not allowed_trade(owner,port,good,core):
		return 0
	var purse: String="crewPurse" if crew_paid else "coins"
	var wallet: Dictionary={"coins":owner[purse],"cargo":owner.cargo}
	var price: int=Economy.price(port,good,"buy")
	var room: float=maxf(0.0,_capacity(owner)-Economy.cargo_weight(owner.cargo))
	if working:room=maxf(room,quantity*float(Goods.ITEMS[good].weight))
	var count: int=mini(quantity,mini(_integer(port.stocks.get(good,0)),mini(int(owner[purse])/maxi(1,price),int(floor(room/float(Goods.ITEMS[good].weight))))))
	if port.get("reserves") is Dictionary:
		var reserve_api: Script=load("res://scripts/harbor_reserves.gd")
		count=mini(count,floori(float(reserve_api.exportable(port,good))))
	if owner.get("playerCompany",false) and commercial:
		count=mini(count,core.CompanyOps.market_limit(core,owner,port,true,good,price) if core!=null else 0)
	if count<=0:
		return 0
	var result: Dictionary=Economy.transact(port,wallet,good,count,"buy",maxf(_capacity(owner),Economy.cargo_weight(owner.cargo)+count*float(Goods.ITEMS[good].weight)) if working else _capacity(owner))
	if not result.ok:
		return 0
	var paid: int=int(owner[purse])-int(wallet.coins)
	owner[purse]=wallet.coins
	if core!=null and owner.get("playerCompany",false):
		if commercial:core.CompanyOps.record(core,owner,"purchase",paid,good,float(result.qty))
		elif not crew_paid and working:core.CompanyOps.add_working(core,owner,good,float(result.qty),paid)
	return int(result.qty)

static func dock(owner: Dictionary,port: Dictionary,core=null) -> Array:
	normalize_owner(owner)
	if owner.get("playerCompany",false) and core==null:return []
	var messages: Array=[]
	owner.atPort=port.id
	if not owner.active:
		return messages
	var costs: Dictionary=upkeep(owner)
	if owner.kind=="trader":
		var good: String=owner.tradeGood
		if port.id!=owner.homePort or (owner.get("playerCompany",false) and core.CompanyOps.book(core,owner.id).recall):
			var sale: int=mini(_integer(owner.cargo.get(good,0)),_integer(owner.tradeCargo))
			if owner.get("playerCompany",false):
				sale=mini(sale,mini(core.CompanyOps.market_limit(core,owner,port,false,good,Economy.price(port,good,"sell")),int(port.cash)/maxi(1,Economy.price(port,good,"sell"))))
			if not allowed_trade(owner,port,good,core):sale=0
			if sale>0:
				var wallet: Dictionary={"coins":owner.coins,"cargo":owner.cargo}
				var result: Dictionary=Economy.transact(port,wallet,good,sale,"sell",_capacity(owner))
				if result.ok:
					var earned: int=int(wallet.coins)-int(owner.coins)
					owner.coins=wallet.coins
					if owner.get("playerCompany",false):core.CompanyOps.record(core,owner,"sale",earned,good,float(result.qty))
					owner.tradeCargo-=int(result.qty)
					owner.tradeDelivered=float(owner.get("tradeDelivered",0))+float(result.qty)
					messages.append("%s sold %d %s at %s."%[owner.name,sale,good,port.name])
	var personal_food: float=float(owner.cargo.food)
	if owner.get("playerCompany",false) and owner.tradeGood=="food":personal_food=maxf(0,personal_food-float(owner.tradeCargo))
	_purchase(owner,port,"food",maxi(0,ceili(costs.food*3.0-personal_food)),true,false,core)
	for boat in owner.boats:
		if boat.sunk:
			continue
		for good in ["fuel","supplies","ammo"]:
			var target: float=3.0 if good=="fuel" else (2.0 if good=="supplies" else 50.0)
			var conversion: float=50.0 if good=="ammo" else 1.0
			var need: int=maxi(0,ceili((target-float(boat[good]))/conversion))
			var have: int=mini(need,_integer(owner.cargo.get(good,0)))
			if have<need:
				_purchase(owner,port,good,need-have,false,true,core)
			var moved: int=mini(need,_integer(owner.cargo.get(good,0)))
			owner.cargo[good]-=moved
			if good==owner.tradeGood:
				owner.tradeCargo=maxi(0,owner.tradeCargo-moved)
			boat[good]+=moved*conversion
		_repair(owner,port,boat,core)
	if owner.kind=="trader" and port.id==owner.homePort:
		var reserve: int=ceili(costs.wages*3.0)
		var budget: int=maxi(0,owner.coins-reserve)
		var qty: int=int(budget/maxi(1,Economy.price(port,owner.tradeGood,"buy")))
		var bought: int=_purchase(owner,port,owner.tradeGood,qty,false,false,core,true)
		owner.tradeCargo+=bought
		if bought>0:
			messages.append("%s loaded %d %s at %s."%[owner.name,bought,owner.tradeGood,port.name])
	if core!=null and owner.get("playerCompany",false):core.CompanyOps.reconcile(core,owner)
	for message in messages:
		_log(owner,message)
	return messages

static func _repair(owner: Dictionary,port: Dictionary,boat: Dictionary,core=null) -> void:
	# One dock visit buys at most one worker-day, paid into residents' purse.
	# No idle civilian worker, kits or affordable pay means no repair.
	var idle: float=maxf(0.0,float(port.get("availableWorkers",0))-float(port.get("_yardWorkersUsed",0)))
	if owner.coins<100 or boat.supplies<=0 or idle<1.0:
		return
	var area: float=Damage.sum_areas(boat)
	var kits: float=0.0
	var wage: int=100
	var key: String=""
	var amount: float=0.0
	if boat.fire>0:
		key="fire"
		amount=minf(boat.fire,minf(20.0,boat.supplies/0.01))
		kits=amount*0.01
	elif area>0:
		key="breaches"
		amount=minf(area,minf(100.0,boat.supplies/0.018))
		kits=amount*0.018
	elif boat.engine<1 and owner.coins>=150 and float(port.get("availableSpecialists",0))>=1:
		key="engine"
		amount=minf(1.0-boat.engine,minf(0.25,boat.supplies/4.0))
		kits=amount*4.0
		wage=150
	elif boat.wounded>0:
		key="wounded"
		amount=minf(boat.wounded,minf(1.0,boat.supplies/0.25))
		kits=amount*0.25
	elif boat.hp<boat.maxHp:
		key="hp"
		amount=minf(boat.maxHp-boat.hp,minf(20.0,boat.supplies/0.2))
		kits=amount*0.2
	if amount<=0.0:
		return
	if wage==150:
		var experts: float=maxf(0.0,float(port.get("availableSpecialists",port.get("specialistWorkers",0)))-float(port.get("_yardSpecialistsUsed",0)))
		if experts<1.0:
			return
		port.availableSpecialists=maxf(0.0,float(port.get("availableSpecialists",port.get("specialistWorkers",0)))-1.0)
	owner.coins-=wage
	if core!=null and owner.get("playerCompany",false):core.CompanyOps.record(core,owner,"repairs",wage)
	port.workers=float(port.get("workers",0))+1.0
	port.availableWorkers=maxf(0.0,float(port.get("availableWorkers",0))-1.0)
	if port.has("_lastWorkersField"):
		port._lastWorkersField=int(port.workers)
	var purse: String="expertPurse" if wage==150 else "householdPurse"
	port[purse]=_integer(port.get(purse,0))+wage
	boat.supplies=maxf(0.0,boat.supplies-kits)
	if key=="breaches":
		for breach in boat.breaches:
			var part: float=minf(amount,breach.area)
			breach.area-=part
			amount-=part
		boat.breaches=boat.breaches.filter(func(b): return b.area>0.001)
	elif key in ["hp","engine"]:
		boat[key]+=amount
	else:
		boat[key]-=amount

static func _performance(owner: Dictionary) -> void:
	owner.performanceFactor=clampf(float(owner.morale)/85.0,0.35,1.0)
	for boat in owner.boats:
		if not boat.has("economyBaseSpeed"):
			boat.economyBaseSpeed=float(boat.spec.get("speed",90))
			boat.economyBaseFireRate=float(boat.spec.get("fireRate",1.0))
		boat.economyFactor=owner.performanceFactor
		boat.spec.speed=boat.economyBaseSpeed*owner.performanceFactor
		boat.spec.fireRate=boat.economyBaseFireRate*owner.performanceFactor

static func tick(owners: Array,ports: Array,days: float,core=null) -> Array:
	var messages: Array=[]
	if not is_finite(days) or days<=0:
		return messages
	# Aggregate crews, bounded daily slices; no individual NPC/person loops.
	var left: float=days
	while left>0.00000001:
		var h: float=minf(1.0,left)
		for owner in owners:
			normalize_owner(owner)
			if not owner.active:
				continue
			var costs: Dictionary=upkeep(owner)
			var wage_float: float=costs.wages*h+owner.wageRemainder
			var due: int=int(floor(wage_float+0.00000001))
			owner.wageRemainder=maxf(0.0,wage_float-due)
			owner.wageArrears+=due
			var paid: int=mini(_integer(owner.coins),_integer(owner.wageArrears))
			owner.coins-=paid
			owner.crewPurse+=paid
			owner.wageArrears-=paid
			owner.lastPayroll=paid
			if core!=null and owner.get("playerCompany",false):core.CompanyOps.record(core,owner,"wages",paid)
			owner.daysOperated+=h
			var port: Dictionary=_find(ports,str(owner.atPort))
			if not port.is_empty():
				messages.append_array(dock(owner,port,core))
			var needed: float=costs.food*h
			var owned_food: float=maxf(0.0,float(owner.cargo.food)-(float(owner.tradeCargo) if owner.tradeGood=="food" else 0.0))
			var food: float=minf(needed,maxf(0.0,float(owner.cargo.food)))
			if owner.tradeGood=="food":
				owner.tradeCargo=maxf(0.0,owner.tradeCargo-maxf(0.0,food-owned_food))
			owner.cargo.food=maxf(0.0,owner.cargo.food-food)
			owner.lastFoodConsumed=food
			owner.lastFuelConsumed=0.0
			for boat in owner.boats:
				if boat.sunk:
					continue
				if boat.water>0 or Damage.sum_areas(boat)>0 or boat.fire>0:
					Damage.tick_ship(boat,45.0*h,{"inCombat":false})
				var fuel_need: float=costs.fuel*h/maxi(1,owner.boats.size())
				var used: float=minf(boat.fuel,fuel_need)
				boat.fuel=maxf(0.0,boat.fuel-used)
				owner.lastFuelConsumed+=used
			var unpaid: bool=owner.wageArrears>0
			var hungry: bool=food+0.000001<needed
			owner.morale=clampf(owner.morale+(-8.0 if unpaid else 1.0)*h-(5.0*h if hungry else 0.0),10.0,100.0)
			if core!=null and owner.get("playerCompany",false):core.CompanyOps.reconcile(core,owner)
			_performance(owner)
			if unpaid and due>0:
				var message: String="%s: %d coins wage arrears; morale %.0f."%[owner.name,owner.wageArrears,owner.morale]
				_log(owner,message)
				if messages.size()<24:
					messages.append(message)
		left-=h
	return messages.slice(0,24)
