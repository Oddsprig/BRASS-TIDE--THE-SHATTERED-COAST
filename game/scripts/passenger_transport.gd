extends RefCounted
const Routes=preload("res://scripts/route_cache.gd")
## Main-thread physical passenger/provision transaction adapter.
const Goods=preload("res://scripts/goods.gd")
const Money=preload("res://scripts/money.gd")
const Economy=preload("res://scripts/economy.gd")
const Expedition=preload("res://scripts/expedition.gd")
const Manifest=preload("res://scripts/hold_manifest.gd")
const Reserves=preload("res://scripts/harbor_reserves.gd")
const Politics=preload("res://scripts/politics.gd")
const Reads=preload("res://scripts/passenger_manifest.gd")
const Cohorts=preload("res://scripts/regional_crises.gd")
static func actual(c):return c.core if c.get("core")!=null else c
static func jobs(s: Dictionary) -> Array:return s.get("regionalCrises",{}).get("jobs",[])
static func assigned(s: Dictionary,uid: String) -> int:
	return Reads.assigned(s,uid)
static func food_weight(s: Dictionary,uid: String="") -> float:
	return Reads.food_weight(s,uid)
static func spare(c,b: Dictionary) -> int:
	return maxi(0,floori(float(b.crewMax)-float(b.crew))-int(c.state.get("captiveBerths",{}).get(str(b.uid),0))-assigned(c.state,str(b.uid)))
static func available_hold(c,b: Dictionary,known: Dictionary={}) -> float:
	var probe: Dictionary=c.state.duplicate()
	if known.is_empty():Manifest.allocate(probe)
	else:probe.cargoManifest=known
	var used: float=Expedition.store_overflow(b)+food_weight(c.state,str(b.uid))
	for good in probe.get("cargoManifest",{}).get(str(b.uid),{}):
		var qty: float=float(probe.cargoManifest[str(b.uid)][good])
		if Goods.ITEMS.has(good):used+=qty*float(Goods.ITEMS[good].weight)
		elif str(good).begins_with("@tool:"):
			for item in c.state.get("tooling",{}).get("items",[]):
				if item.id==str(good).trim_prefix("@tool:"):used+=float(c.ToolingOps.Tooling.KINDS[item.kind].weight)
		else:used+=qty*3.0 # conservative sealed-freight reservation
	return maxf(0,float(b.spec.cargo)-used)
static func choose(c,count: int,food: float) -> String:
	var probe: Dictionary=c.state.duplicate();Manifest.allocate(probe)
	for b in c.active_fleet():
		if spare(c,b)>=count and available_hold(c,b,probe.cargoManifest)+0.000001>=food:return str(b.uid)
	return ""
static func berths(view) -> int:
	var c=actual(view);var largest: int=0
	for b in c.active_fleet():largest=maxi(largest,spare(c,b))
	var carried: int=0
	for j in jobs(c.state):
		if j.stage!="holding":carried+=int(j.n)
	# Each cohort travels in one real boat; the module subtracts its existing passengers.
	return carried+largest
static func room(view,p: Dictionary) -> int:
	var c=actual(view)
	var capacity: int=int(c.state.passengerTransport.housing.get(str(p.id),int(p.workforce)))
	var committed: int=int(p.workforce)
	for course in p.get("training",{}).get("jobs",[]):committed+=int(course.reservedWorkers)
	for business in c.state.get("businesses",[]):
		if business.homePort==p.id and not business.get("closed",false):committed+=business.employees.size()
	committed+=int(p.get("defenses",{}).get("crew",0))
	return maxi(0,capacity-committed)
static func route_days(view,origin: String,destination: String) -> int:
	var c=actual(view);var path: Array=Routes.path(c,c.port_position(origin),c.port_position(destination))
	if path.size()<2 or c.travel_speed()<=0:return -1
	var distance: float=0.0
	for i in range(1,path.size()):distance+=c.distance(path[i-1],path[i])
	return clampi(ceili(distance/maxf(1,c.travel_speed())/c.DAY_SECONDS),1,30)
static func service(view,id: String,_kind: String) -> bool:
	var c=actual(view)
	return c.current_port().get("id","")==id and bool(Politics.permit(c,"service").ok)
static func quantity(count: int,days: int) -> float:return snappedf(float(count)*0.08*float(days),0.01)
static func quote(view,origin: String,count: int,days: int) -> int:
	var c=actual(view);var p: Dictionary=c.port(origin);var food: float=quantity(count,days)
	if p.is_empty() or food<=0 or Reserves.exportable(p,"food")+0.000001<food or choose(c,count,food).is_empty():return -1
	return ceili(food*Economy.price(p,"food","buy"))
static func travel(view,j: Dictionary,_day: int) -> bool:
	var c=actual(view);var work: Dictionary=c.state.passengerTransport.work.get(str(j.id),{})
	return float(work.get("distance",0))+0.05>=float(work.get("unit",1e9))
static func account(view) -> Array:return [actual(view).state,"coins"]
static func numeric(v) -> bool:return (v is int or v is float) and is_finite(float(v)) and float(v)>=0 and floorf(float(v))==float(v) and float(v)<=1e12
static func atomic(view,moves: Array,event: Dictionary) -> bool:
	var c=actual(view);var j: Dictionary=event.job;var action: String=str(event.action)
	var p: Dictionary=c.port(str(event.get("port","")));var extra: Array=[]
	var food: float=0.0;var carrier: String=""
	if action=="buy":
		if not service(c,str(p.get("id","")),""):return false
		food=quantity(int(j.n),int(event.days));carrier=choose(c,int(j.n),food)
		if carrier.is_empty() or quote(c,str(p.id),int(j.n),int(event.days))!=int(j.foodCost):return false
		extra.append([j,"escrow",p,"cash",int(j.foodCost)])
	elif action=="eat":
		food=quantity(int(j.n),1)
		if float(j.food.get("food",0))+0.000001<food:return false
	elif action=="handle":
		if p.is_empty() or float(p.get("_yardWorkersUsed",0))+int(j.handlers)+1>float(p.availableWorkers) or float(p.get("_yardSpecialistsUsed",0))+1>float(p.availableSpecialists):return false
	elif action=="reload":
		carrier=choose(c,int(j.n),float(j.food.get("food",0)))
		if carrier.is_empty() or not service(c,str(p.get("id","")),""):return false
	elif action=="release":
		if p.is_empty():return false
	elif action!="lose":return false
	# Preflight the complete ordered purse ledger, including newly funded escrow.
	var holders: Array=[];var balances: Dictionary={}
	for move in moves+extra:
		if not move is Array or move.size()!=5 or not move[0] is Dictionary or not move[2] is Dictionary or not numeric(move[4]):return false
		var keys: Array=[]
		for side in [[move[0],move[1]],[move[2],move[3]]]:
			if not side[1] is String or not numeric(side[0].get(side[1])):return false
			var index: int=-1
			for i in range(holders.size()):
				if is_same(holders[i],side[0]):index=i;break
			if index<0:index=holders.size();holders.append(side[0])
			var key: String=str(index)+":"+str(side[1]);keys.append(key)
			if not balances.has(key):balances[key]=int(side[0][side[1]])
		var amount: int=int(move[4])
		if int(balances[keys[0]])<amount or int(balances[keys[1]])+amount>1000000000000:return false
		balances[keys[0]]-=amount;balances[keys[1]]+=amount
	for move in moves+extra:Money.move(move[0],str(move[1]),move[2],str(move[3]),int(move[4]),"Passenger service "+action,c.state.moneyLog)
	match action:
		"buy":
			p.stocks.food-=food;j.food.food=food
			c.state.passengerTransport.carriers[str(j.id)]=carrier
			var path: Array=Routes.path(c,c.port_position(j.origin),c.port_position(j.destination));var distance: float=0
			for i in range(1,path.size()):distance+=c.distance(path[i-1],path[i])
			c.state.passengerTransport.work[str(j.id)]={"distance":0.0,"unit":distance/maxi(1,int(j.days))}
		"eat":j.food.food=maxf(0,float(j.food.food)-food)
		"handle":p._yardWorkersUsed=float(p.get("_yardWorkersUsed",0))+int(j.handlers)+1;p._yardSpecialistsUsed=float(p.get("_yardSpecialistsUsed",0))+1
		"reload":c.state.passengerTransport.carriers[str(j.id)]=carrier
		"release":
			p.publicStores.food=float(p.publicStores.get("food",0))+float(j.food.get("food",0));j.food.clear()
			if str(j.destination)==str(p.id) and str(j.origin)!=str(p.id):c.state.campaignFacts.resettlersAdmitted=int(c.state.campaignFacts.get("resettlersAdmitted",0))+int(j.n)
		"lose":c.state.passengerTransport.foodLost=float(c.state.passengerTransport.foodLost)+float(j.food.get("food",0));j.food.clear()
	return true

## Charters share the actual regional cohort arithmetic, berths and provisions.
## Their fee AND carried household savings occupy the already-counted voyage
## escrow; there is no second purse or invented passenger population.
static func choose_charter(c,count: int,food: float,uid: String="") -> String:
	for b in c.active_fleet():
		if not uid.is_empty() and str(b.uid)!=uid:continue
		if str(c.hull(str(b.type)).get("civilianRole","")) not in ["transport","yacht"]:continue
		if spare(c,b)>=count and available_hold(c,b)+0.000001>=food and c.capacity()-c.cargo_weight()+0.000001>=food:return str(b.uid)
	return ""

static func charter_room(c,p: Dictionary,excluding: String="") -> int:
	var value: int=room(c,p)
	for j in jobs(c.state):
		if str(j.destination)==str(p.id) and j.stage!="returning":value-=int(j.n)
	for j in c.state.get("voyageJobs",[]):
		if j.get("kind","")=="passenger_charter" and str(j.id)!=excluding and str(j.targetPort)==str(p.id):value-=int(j.get("passengers",{}).get("n",0))
	return maxi(0,value)

static func charter_quote(c,origin: String,destination: String,count: int,uid: String="") -> Dictionary:
	var p: Dictionary=c.port(origin);var target: Dictionary=c.port(destination)
	if p.is_empty() or target.is_empty() or origin==destination or count<1 or count>32 or charter_room(c,target)<count:return {}
	var module=Cohorts.new()
	var cohort: Dictionary=module._cohort(p,count)
	if cohort.is_empty():return {}
	var days: int=route_days(c,origin,destination)
	if days<1:return {}
	var food: float=quantity(count,days+2)
	var carrier: String=choose_charter(c,count,food,uid)
	if carrier.is_empty() or Reserves.exportable(p,"food")+0.000001<food:return {}
	var path: Array=Routes.path(c,c.state.position,target)
	var distance: float=0.0
	for i in range(1,path.size()):distance+=c.distance(path[i-1],path[i])
	if path.size()<2 or distance<=0:return {}
	return {"passengers":cohort,"carrierUid":carrier,"charterFood":{"food":food},"materialInvoice":ceili(food*Economy.price(p,"food","buy")),"routeDistance":distance,"routeDays":days,
		"savingsHousehold":module._share(int(p.householdPurse),count,int(p.workforce)),"savingsExpert":module._share(int(p.expertPurse),int(cohort.specialists),int(p.specialists))}

static func board_charter(c,j: Dictionary,uid: String="") -> bool:
	var p: Dictionary=c.current_port()
	if str(p.get("id",""))!=str(j.port) or not service(c,str(j.port),""):return false
	var q: Dictionary=charter_quote(c,str(j.port),str(j.targetPort),int(j.passengers.n),uid)
	if q.is_empty() or int(p.get(str(j.payerKey),0))<int(j.reward)+int(q.materialInvoice):return false
	# Complete preflight precedes the four finite purse transfers and the stock debit.
	if int(p.householdPurse)<int(q.savingsHousehold) or int(p.expertPurse)<int(q.savingsExpert):return false
	j.merge(q,true);j.escrow=0
	Money.move(p,str(j.payerKey),j,"escrow",int(j.reward),"Sponsor funds passenger charter",c.state.moneyLog)
	Money.move(p,str(j.payerKey),p,"cash",int(j.materialInvoice),"Sponsor buys actual charter provisions",c.state.moneyLog)
	Money.move(p,"householdPurse",j,"escrow",int(j.savingsHousehold),"Passengers carry existing household savings",c.state.moneyLog)
	Money.move(p,"expertPurse",j,"escrow",int(j.savingsExpert),"Passengers carry existing expert savings",c.state.moneyLog)
	p.stocks.food=maxf(0,float(p.stocks.food)-float(j.charterFood.food))
	Cohorts.new()._people(p,j.passengers,-1)
	Economy.sync_workforce(p)
	j.lastPosition=c.state.position.duplicate();j.lastTickDay=float(c.state.day);j.elapsedDays=0.0;j.voyageDistance=0.0;j.foodConsumed=0.0
	return true

static func discharge_charter(c,j: Dictionary,p: Dictionary) -> bool:
	var n: int=int(j.get("passengers",{}).get("n",0))
	var savings: int=int(j.get("savingsHousehold",0))+int(j.get("savingsExpert",0))
	if n<=0 or p.is_empty() or charter_room(c,p,str(j.id))<n or int(j.escrow)<savings:return false
	Money.move(j,"escrow",p,"householdPurse",int(j.savingsHousehold),"Passenger household savings discharged",c.state.moneyLog)
	Money.move(j,"escrow",p,"expertPurse",int(j.savingsExpert),"Passenger expert savings discharged",c.state.moneyLog)
	Cohorts.new()._people(p,j.passengers,1);Economy.sync_workforce(p)
	p.publicStores.food=float(p.publicStores.get("food",0))+float(j.charterFood.get("food",0))
	j.passengers={};j.charterFood={};j.savingsHousehold=0;j.savingsExpert=0
	return true

static func lose_charter(c,j: Dictionary) -> void:
	var cohort: Dictionary=j.get("passengers",{})
	if cohort.is_empty():return
	var losses: Dictionary=c.state.regionalCrises
	var savings: int=int(j.savingsHousehold)+int(j.savingsExpert)
	Money.move(j,"escrow",losses,"lostPurse",savings,"Lost charter savings retained in existing loss custody",c.state.moneyLog)
	losses.lostPeople=int(losses.lostPeople)+int(cohort.n)
	losses.lostSpecialists=int(losses.lostSpecialists)+int(cohort.specialists)
	losses.lostRecruits=int(losses.lostRecruits)+int(cohort.recruits)
	for role in Cohorts.ROLES:losses.lostQualified[role]=int(losses.lostQualified[role])+int(cohort.qualified[role])
	c.state.passengerTransport.foodLost=float(c.state.passengerTransport.foodLost)+float(j.charterFood.get("food",0))
	j.passengers={};j.charterFood={};j.savingsHousehold=0;j.savingsExpert=0;j.failed=true

static func tick_charter(c,j: Dictionary,dt_days: float) -> void:
	if j.get("passengers",{}).is_empty():return
	var b: Dictionary=c.find_boat(str(j.carrierUid))
	if b.is_empty() or b.sunk:lose_charter(c,j);return
	var now: float=float(c.state.day)
	var elapsed: float=maxf(0,minf(dt_days,now-float(j.lastTickDay)))
	if elapsed<=0:return
	j.lastTickDay=now
	if not c.active_fleet().has(b):j.failed=true
	var need: float=float(j.passengers.n)*0.08*elapsed
	var eaten: float=minf(need,float(j.charterFood.get("food",0)))
	j.charterFood.food=maxf(0,float(j.charterFood.get("food",0))-eaten)
	j.foodConsumed=float(j.foodConsumed)+eaten
	if eaten+0.000001<need:j.failed=true
	j.elapsedDays=float(j.elapsedDays)+elapsed
	j.voyageDistance=minf(1e9,float(j.voyageDistance)+c.distance(j.lastPosition,c.state.position))
	j.lastPosition=c.state.position.duplicate()
