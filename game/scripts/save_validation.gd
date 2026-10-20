extends RefCounted
## Read-only schema preflight. No filesystem, SceneTree, singleton, or live-state access.
const GOODS: Array=["food","logs","timber","ore","charcoal","iron","copper","saltpeter","sulfur","gunpowder","ammo","crude","fuel","supplies","engines","guns"]
const MAX_COINS: float=9007199254740991.0

static func _number(v,minimum: float=0.0,maximum: float=INF,whole: bool=false) -> bool:
	if not (v is int or v is float):
		return false
	var n: float=float(v)
	return is_finite(n) and n>=minimum and n<=maximum and (not whole or floor(n)==n)

static func _text(v,allow_empty: bool=false) -> bool:
	return v is String and (allow_empty or not v.is_empty())

static func _numbers(d: Dictionary,keys: Array,path: String,whole: bool=false,maximum: float=INF) -> String:
	for key in keys:
		if not _number(d.get(key),0.0,maximum,whole):
			return "%s.%s must be a finite nonnegative%s number."%[path,key," whole" if whole else ""]
	return ""

static func _cargo(value,path: String,all_goods: bool) -> String:
	if not value is Dictionary:
		return path+" must be a goods dictionary."
	if all_goods:
		var missing: String=_numbers(value,GOODS,path)
		if not missing.is_empty(): return missing
	for key in value:
		if not key is String or not GOODS.has(key) or not _number(value[key]):
			return path+" contains an unknown good or invalid quantity."
	return ""

static func _point(value,path: String,width: float,height: float) -> String:
	if not value is Dictionary or not _number(value.get("x"),0.0,width) or not _number(value.get("y"),0.0,height):
		return path+" must contain finite world coordinates."
	return ""

static func _boat(value,hulls: Dictionary,path: String,player: bool) -> String:
	if not value is Dictionary:
		return path+" must be a boat dictionary."
	if not _text(value.get("type")) or not hulls.has(value.type):
		return path+" contains an unknown hull type."
	var spec: Dictionary=hulls[value.type]
	if player and not _text(value.get("uid")):
		return path+" requires a unique boat uid."
	if value.has("uid") and not _text(value.uid): return path+" has an invalid uid."
	for key in ["id","name","policy"]:
		if not _text(value.get(key)): return path+" requires a string "+key+"."
	if not value.policy in ["balanced","bail","repair","fight"]: return path+" has an unknown crew policy."
	if not value.get("sunk") is bool: return path+" requires a sinking flag."
	if value.has("mothballed") and not value.mothballed is bool: return path+" has invalid mothballed flag."
	var error: String=_numbers(value,["maxHp","hp","armor","crew","crewMin","crewOptimal","crewMax","wounded","water","capacity","fire","engine","supplies","ammo","fuel","cooldown"],path)
	if not error.is_empty(): return error
	if value.maxHp<=0 or not is_equal_approx(float(value.maxHp),float(spec.hp)) or value.hp>value.maxHp:
		return path+" has invalid hull HP bounds."
	if value.crew>float(spec.crewMax) or value.crew>value.crewMax or value.wounded>value.crew or value.crewMin>value.crewOptimal or value.crewOptimal>value.crewMax or value.crewMax>float(spec.crewMax):
		return path+" has invalid crew bounds."
	if value.capacity<=0 or value.water>value.capacity or value.fire>100 or value.engine>1:
		return path+" has invalid flooding/fire/engine bounds."
	for key in ["x","y","angle","vx","vy"]:
		if not _number(value.get(key),-INF): return path+" has invalid finite geometry: "+key+"."
	if value.has("turretAngle") and not _number(value.turretAngle,-INF): return path+" has invalid turret geometry."
	for key in ["economyBaseSpeed","economyBaseFireRate","economyFactor"]:
		if value.has(key) and not _number(value[key]): return path+" has invalid "+key+"."
	if not value.get("spec") is Dictionary: return path+" requires a spec dictionary."
	for key in ["speed","fireRate","size","damage","range"]:
		if not _number(value.spec.get(key)): return path+" has invalid stored spec "+key+"."
	for key in ["turn","pumps","cargo","hp","armor","crewMin","crewOptimal","crewMax","price"]:
		if value.spec.has(key) and not _number(value.spec[key]): return path+" has invalid stored spec "+key+"."
	if not value.get("breaches") is Array: return path+" requires a breach array."
	for breach in value.breaches:
		if not breach is Dictionary or not _number(breach.get("area")) or not _text(breach.get("section")):
			return path+" contains an invalid breach."
	return ""

static func _order(value,hulls: Dictionary,path: String) -> String:
	if not value is Dictionary: return path+" must be a construction order."
	if not _text(value.get("hull")) or not hulls.has(value.hull): return path+" has an unknown hull."
	if not _text(value.get("id")) or not value.get("owner") in ["player","yard"] or not value.get("ready") is bool:
		return path+" has invalid order identity/owner/ready fields."
	var error: String=_numbers(value,["escrow"],path,true,MAX_COINS)
	if not error.is_empty(): return error
	for key in ["ordinaryDays","expertDays","workerDays","remainingOrdinaryDays","remainingExpertDays","remainingWorkerDays","workedDays","elapsedDays","estimatedDays","initialEstimatedDays","ordinaryTeamCap","expertTeamCap","teamSize","progress"]:
		if value.has(key) and not _number(value[key]): return path+" has invalid "+key+"."
	for key in ["initialEscrow","laborTarget","supervisionTarget","laborPaid","supervisionPaid","materialCost","laborCost","supervisionCost","overhead","margin","tax","total"]:
		if value.has(key) and not _number(value[key],0.0,MAX_COINS,true): return path+" has invalid "+key+"."
	if value.has("materials"):
		error=_cargo(value.materials,path+".materials",false)
		if not error.is_empty(): return error
	if value.has("labor"):
		if not value.labor is Dictionary: return path+".labor must be a dictionary."
		for occupation in value.labor:
			if not _number(value.labor[occupation]): return path+" has invalid worker-days."
	return ""

static func validate(saved: Dictionary,world: Dictionary) -> Dictionary:
	var error: String=_validate(saved,world)
	return {"ok":error.is_empty(),"message":"Save schema is valid." if error.is_empty() else error}

static func _validate(s: Dictionary,world: Dictionary) -> String:
	if not world.get("PORTS") is Array or not world.get("HULLS") is Array: return "World definitions are unavailable."
	var ports: Dictionary={}
	var hulls: Dictionary={}
	for p in world.PORTS:
		if not p is Dictionary or not _text(p.get("id")): return "Invalid world port definition."
		ports[p.id]=true
	for h in world.HULLS:
		if not h is Dictionary or not _text(h.get("id")) or not _number(h.get("hp"),1) or not _number(h.get("crewMax")): return "Invalid world hull definition."
		hulls[h.id]=h
	if s.get("format")!=2: return "Save format must be2."
	var error: String=_numbers(s,["coins","crewPurse","wageArrears","debt","coinSupply"],"save",true,MAX_COINS)
	if not error.is_empty(): return error
	for key in ["seed","nextUid","econDay","renown","missionIndex","wins","losses","kills"]:
		if not _number(s.get(key),0.0,MAX_COINS,true): return "save."+key+" must be a nonnegative integer."
	if not _number(s.get("day"),1.0) or not _number(s.get("morale"),0.0,100.0) or not _number(s.get("heading"),-INF) or not _number(s.get("encounterGrace")):
		return "Invalid campaign clock, morale or heading."
	if not s.get("completed") is bool: return "Missing campaign completion flag."
	for key in ["version","destination","lastPort","flagship"]:
		if not _text(s.get(key),true): return "save."+key+" must be a string."
	if not ports.has(s.lastPort) or (not s.destination.is_empty() and not ports.has(s.destination)): return "Unknown campaign harbor reference."
	var world_size=world.get("WORLD",{})
	var width: float=2600.0
	var height: float=1800.0
	if world_size is Dictionary:
		if _number(world_size.get("width"),1): width=float(world_size.width)
		if _number(world_size.get("height"),1): height=float(world_size.height)
	error=_point(s.get("position"),"save.position",width,height)
	if not error.is_empty(): return error
	error=_cargo(s.get("cargo"),"save.cargo",true)
	if not error.is_empty(): return error
	if not s.get("ports") is Array or s.ports.size()!=ports.size(): return "Save must contain every original harbor exactly once."
	var seen_ports: Dictionary={}
	for p in s.ports:
		if not p is Dictionary or not _text(p.get("id")) or not ports.has(p.id) or seen_ports.has(p.id): return "Unknown, duplicate or malformed saved harbor."
		seen_ports[p.id]=true
		error=_numbers(p,["cash","householdPurse","expertPurse","governmentPurse"],p.id,true,MAX_COINS)
		if not error.is_empty(): return error
		error=_cargo(p.get("stocks"),p.id+".stocks",true)
		if not error.is_empty(): return error
		error=_point(p,p.id,width,height)
		if not error.is_empty(): return error
		for key in ["name","industry","faction"]:
			if not _text(p.get(key)): return p.id+" has invalid "+key+"."
		for key in ["population","workforce","workers","publicWorkers","availableWorkers","recruits","prosperity"]:
			if not _number(p.get(key)): return p.id+" has invalid "+key+"."
		if not p.get("buildQueue") is Array or not p.get("shipStock") is Dictionary or not p.get("shipIds") is Array: return p.id+" has invalid yard collections."
		for id in p.shipStock:
			if not hulls.has(id) or not _number(p.shipStock[id],0.0,MAX_COINS,true): return p.id+" has invalid hull stock."
		for id in p.shipIds:
			if not _text(id) or not hulls.has(id): return p.id+" has an unknown yard design."
		for order in p.buildQueue:
			error=_order(order,hulls,p.id+".buildQueue")
			if not error.is_empty(): return error
	if not s.get("fleet") is Array or s.fleet.size()>8: return "Player fleet must be an array of at most eight hulls."
	var uids: Dictionary={}
	for boat in s.fleet:
		error=_boat(boat,hulls,"save.fleet",true)
		if not error.is_empty(): return error
		if uids.has(boat.uid): return "Duplicate player boat uid."
		uids[boat.uid]=true
	if not s.get("fleetOwners") is Array: return "NPC fleet owners must be an array."
	var owner_ids: Dictionary={}
	for owner in s.fleetOwners:
		if not owner is Dictionary or not _text(owner.get("id")) or owner_ids.has(owner.id): return "Malformed or duplicate NPC fleet owner."
		owner_ids[owner.id]=true
		error=_numbers(owner,["coins","crewPurse","wageArrears"],owner.id,true,MAX_COINS)
		if not error.is_empty(): return error
		if not _text(owner.get("homePort")) or not ports.has(owner.homePort) or not owner.get("active") is bool or not owner.get("boats") is Array:
			return owner.id+" has invalid home, active flag or boats."
		if not owner.get("kind") in ["trader","patrol","raider"] or not _text(owner.get("name")) or not _number(owner.get("morale"),0.0,100.0): return owner.id+" has invalid fleet identity/morale."
		if not _text(owner.get("faction")): return owner.id+" has invalid faction."
		if owner.has("tradeGood") and (not _text(owner.tradeGood) or not GOODS.has(owner.tradeGood)): return owner.id+" has invalid traded good."
		error=_cargo(owner.get("cargo"),owner.id+".cargo",false)
		if not error.is_empty(): return error
		if not owner.get("route") is Array or not owner.get("log") is Array: return owner.id+" has invalid route/log."
		for id in owner.route:
			if not _text(id) or not ports.has(id): return owner.id+" has unknown route harbor."
		if not _text(owner.get("atPort"),true) or (not owner.atPort.is_empty() and not ports.has(owner.atPort)): return owner.id+" has invalid dock."
		for boat in owner.boats:
			error=_boat(boat,hulls,owner.id+".boats",false)
			if not error.is_empty(): return error
		for key in ["tradeCargo","wageRemainder","daysOperated","performanceFactor","progress","lastPayroll","lastFoodConsumed","lastFuelConsumed"]:
			if owner.has(key) and not _number(owner[key]): return owner.id+" has invalid "+key+"."
	if not s.get("activeContract") is Dictionary: return "Active contract must be a dictionary."
	var contract: Dictionary=s.activeContract
	if not contract.is_empty():
		for key in ["id","title","port","targetPort","payerKey"]:
			if not _text(contract.get(key)): return "Active contract requires "+key+"."
		if not ports.has(contract.port) or not ports.has(contract.targetPort) or not contract.payerKey in ["cash","governmentPurse"]: return "Active contract has unknown sponsor/escrow purse."
		error=_numbers(contract,["escrow","reward","renown"],"activeContract",true,MAX_COINS)
		if not error.is_empty(): return error
		if not contract.get("cleared") is bool or not contract.get("enemyHulls") is Array: return "Invalid contract enemy clearance fields."
		for id in contract.enemyHulls:
			if not _text(id) or not hulls.has(id): return "Unknown contract enemy hull."
	if not s.get("freight") is Dictionary or not s.get("recoverable") is Dictionary: return "Invalid freight or wreck record."
	if not s.freight.is_empty():
		if not _text(s.freight.get("good")) or not GOODS.has(s.freight.good) or not _number(s.freight.get("qty"),0.0,MAX_COINS,true): return "Invalid sealed freight."
	if not s.recoverable.is_empty():
		if not _text(s.recoverable.get("hull")) or not hulls.has(s.recoverable.hull) or not s.recoverable.get("claimed") is bool: return "Invalid salvage claim."
	for key in ["path","patrols","doneSide","log","moneyLog"]:
		if not s.get(key) is Array: return "save."+key+" must be an array."
	for point in s.path:
		error=_point(point,"save.path",width,height)
		if not error.is_empty(): return error
	for patrol in s.patrols:
		if not patrol is Dictionary or not _text(patrol.get("id")) or not _text(patrol.get("from")) or not ports.has(patrol.from) or not _text(patrol.get("to")) or not ports.has(patrol.to): return "Invalid chart patrol route."
		if not patrol.get("active") is bool or not patrol.get("hostile") is bool or not _number(patrol.get("progress"),0.0,1.0): return "Invalid chart patrol state."
		error=_point(patrol,"save.patrols",width,height)
		if not error.is_empty(): return error
	for entry in s.log:
		if not entry is String: return "Campaign log must contain strings."
	for entry in s.doneSide:
		if not entry is String: return "Completed contract ids must be strings."
	for entry in s.moneyLog:
		if not entry is Dictionary: return "Money log must contain records."
	return ""
