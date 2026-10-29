extends RefCounted
## One scheduled physical trader. No clock, inventory, payroll or ocean memory.
const World = preload("res://scripts/ocean_world064.gd")
const Economy = preload("res://scripts/economy.gd")
const Goods = preload("res://scripts/goods.gd")
const Harbor = preload("res://scripts/harbor_reserves.gd")
const Fleets = preload("res://scripts/fleet_economy.gd")
const OWNER: String = "patrol-7"
const ORIGIN: String = "kelp_reach"
const REMOTE_PORT: String = "westglass_anchorage"
const BERTH: Dictionary = {"x":756.0,"y":732.0}
const PHASES: Array = ["home_service","outbound","remote_service","return","lost"]
const DAY_SECONDS: float = 45.0
const SERVICE_SECONDS: float = 11.25
const EPS: float = 0.000001


static func empty_book() -> Dictionary:
	return {"schema":1,"route":{}}


static func prepare(saved: Dictionary, context064: Dictionary) -> Dictionary:
	if not saved.has("shipping068"):return _result(empty_book(),{},"Legacy voyage has no shipping enrollment.")
	var outer = saved.get("shipping068")
	if not outer is Dictionary or not outer.has("model"):return _fail("Present shipping068 requires its explicit model book.")
	var book = outer.get("model")
	if not _book_valid(book):return _fail("Invalid shipping068 model schema or fields.")
	if book.route.is_empty():return _result(book.duplicate(true),{},"No merchant is enrolled.")
	if not _number(saved.get("day"),1.0):return _fail("Shipping needs the existing finite campaign clock.")
	var error: String = _route_error(context064,book.route,float(saved.day)*DAY_SECONDS)
	if not error.is_empty():return _fail(error)
	for collection in ["fleetOwners","patrols","fleet","boardingPrizes"]:
		if not saved.get(collection,[] if collection=="boardingPrizes" else null) is Array:return _fail("Shipping physical custody collections are invalid.")
	var owners: Array = saved.fleetOwners.filter(func(o):return o is Dictionary and o.get("id")==OWNER)
	var patrols: Array = saved.patrols.filter(func(p):return p is Dictionary and p.get("id")==OWNER)
	if owners.size()!=1 or patrols.size()!=1:return _fail("Shipping needs one original trader and one dormant home projection.")
	var owner: Dictionary = owners[0]
	var patrol: Dictionary = patrols[0]
	error = _owner_error(owner)
	if not error.is_empty():return _fail(error)
	var clearance: float=10.0
	for boat in owner.boats:
		if not boat.sunk:clearance=maxf(clearance,float(boat.spec.size))
	var physical_location: Dictionary=World.prepare(book.route.location,context064,clearance)
	if not physical_location.get("ok",false):return _fail(str(physical_location.get("message","Unsafe physical shipping route.")))
	if patrol.get("active")!=false or patrol.get("hidden")!=true or patrol.get("holding")!=true or not patrol.get("course") is Array or not patrol.course.is_empty() or patrol.has("interceptPoint"):
		return _fail("Enrolled merchant's home projection must stay dormant.")
	var route: Dictionary = book.route
	var living: int = owner.boats.filter(func(b):return not b.sunk).size()
	if route.phase=="lost":
		if living!=0 or owner.active or owner.get("atPort")!="" or owner.has("harborServiceUntilDay") or not route.location.path.is_empty() or route.location.destination!="":return _fail("Lost shipping cannot retain living hulls, a berth or a moving course.")
	elif living==0 or not owner.active:return _fail("Active shipping requires its original living fleet.")
	if route.phase in ["home_service","remote_service"]:
		var port_id: String = ORIGIN if route.phase=="home_service" else REMOTE_PORT
		if not saved.get("ports") is Array:return _fail("Shipping service requires actual ports.")
		var matches: Array = saved.ports.filter(func(p):return p is Dictionary and p.get("id")==port_id)
		if matches.size()!=1 or not _at_berth(route.location,matches[0]) or owner.get("atPort")!=port_id:return _fail("Shipping service needs its actual stopped canonical berth.")
		if owner.has("harborServiceUntilDay") and (not _number(owner.harborServiceUntilDay,1.0) or float(owner.harborServiceUntilDay)>float(saved.day)+0.25+EPS):return _fail("Shipping paid service deadline is invalid.")
		if int(route.sequence)%6 in [1,4] and not owner.has("harborServiceUntilDay"):return _fail("Serviced shipping must retain its actual service deadline.")
	elif route.phase!="lost" and (owner.get("atPort")!="" or owner.has("harborServiceUntilDay")):
		return _fail("A shipping passage cannot receive remote harbor service.")
	# Check raw UID custody without invoking any boat/owner normalizer.
	var custody: Dictionary = {}
	var all_boats: Array = saved.fleet+saved.get("boardingPrizes",[])
	for other in saved.fleetOwners:
		if not other is Dictionary or not other.get("boats") is Array:return _fail("Invalid raw owner custody.")
		all_boats += other.boats
	for boat in all_boats:
		if not boat is Dictionary:return _fail("Invalid raw physical boat.")
		var uid = boat.get("uid")
		if uid is String and not uid.is_empty():custody[uid]=int(custody.get(uid,0))+1
	for boat in owner.boats:
		if int(custody.get(boat.uid,0))!=1:return _fail("Shipping must preserve unique original hull custody.")
	return _result(book.duplicate(true),{},"Shipping model validated without changing raw state.")


static func requirements(context064: Dictionary, snapshot: Dictionary) -> Dictionary:
	var error: String = _snapshot_error(snapshot)
	if not error.is_empty():return _fail(error)
	var speed: float = float(snapshot.performance.get("speed",0.0))*0.38*float(snapshot.campaignScale)
	if speed<=0.0:return _fail("Merchant has no powered voyage speed.")
	var home_gate: Dictionary = _gate(context064,World.HOME,false)
	var remote_gate: Dictionary = _gate(context064,World.REMOTE,false)
	var ocean_home: Dictionary = _gate(context064,World.HOME,true)
	var ocean_remote: Dictionary = _gate(context064,World.REMOTE,true)
	if home_gate.is_empty() or remote_gate.is_empty() or ocean_home.is_empty() or ocean_remote.is_empty():return _fail("The two existing northern approaches are required.")
	var home_loc: Dictionary = _location("home",World.HOME,_point(snapshot.originPort))
	var safe_home: Dictionary = World.Navigation.harbor_approach(context064.homeNav,snapshot.originPort,float(snapshot.clearance))
	if safe_home.is_empty():return _fail("The existing home berth has no safe fleet approach.")
	home_loc.position=safe_home
	var north_home: Dictionary = _location("home",World.HOME,home_gate)
	var north_remote: Dictionary = _location("local",World.REMOTE,remote_gate)
	var outward: Dictionary = World.plot(context064,home_loc,home_gate,"",float(snapshot.clearance))
	var homeward: Dictionary = World.plot(context064,north_home,_point(snapshot.originPort),ORIGIN,float(snapshot.clearance))
	var remote: Dictionary = World.plot(context064,north_remote,BERTH,"",float(snapshot.clearance))
	if not outward.get("ok",false) or not homeward.get("ok",false) or not remote.get("ok",false):return _fail("A real northern shipping leg is not navigable at this fleet clearance.")
	var local_distance: float = maxf(_length(home_loc.position,outward.location.path),_length(north_home.position,homeward.location.path))+_length(north_remote.position,remote.location.path)
	var physical_ocean: float = World._distance(ocean_home,ocean_remote)*float(context064.ocean.localUnitsPerUnit)
	# Both physical legs at slowest ocean speed, two quarter-day calls and half
	# a day of maneuver/weather contingency. No simulated time is spent here.
	var days: float = 2.0*(local_distance+physical_ocean/0.25)/speed/DAY_SECONDS+1.0
	var costs: Dictionary = Fleets.upkeep(snapshot.owner)
	if not is_finite(days) or days<=0.0:return _fail("Shipping reserve duration is invalid.")
	return {"ok":true,"days":days,"wageCoins":ceili(float(costs.wages)*days)+int(snapshot.owner.get("wageArrears",0)),"food":ceilf(float(costs.food)*days),"fuel":ceilf(float(costs.fuel)*days),"repairCoins":ceili(float(snapshot.reserves.boats)*Economy.ORDINARY_WAGE),"message":"Conservative round-trip reserve; no guaranteed profit or refill."}


static func plan(context064: Dictionary, modelBook: Dictionary, snapshot: Dictionary, nowSecond: float) -> Dictionary:
	if not _book_valid(modelBook) or not _number(nowSecond,0.0):return _fail("Invalid shipping book or existing campaign time.")
	var error: String = _snapshot_error(snapshot)
	if not error.is_empty():return _fail(error)
	var book: Dictionary = modelBook.duplicate(true)
	var owner: Dictionary = snapshot.owner
	if book.route.is_empty():
		if not owner.active or not snapshot.patrol.get("holding",false) or owner.get("atPort")!=ORIGIN or not _point_valid(snapshot.patrol):return _result(book,{},"Waiting for the same merchant's actual Kelp return and service.")
		var location: Dictionary = _location("home",World.HOME,_point(snapshot.patrol))
		if not _at_berth(location,snapshot.originPort):return _result(book,{},"Merchant has not reached the real Kelp berth.")
		if not _number(owner.get("harborServiceUntilDay"),1.0):return _result(book,{},"Waiting for an actual paid home service visit.")
		if owner.boats.filter(func(b):return not b.sunk).is_empty():return _result(book,{},"The merchant has no surviving physical carrier.")
		book.route={"ownerId":OWNER,"phase":"home_service","location":location,"nextDueSecond":maxf(nowSecond,float(owner.harborServiceUntilDay)*DAY_SECONDS),"sequence":0}
		return _result(book,{},"Original trader admitted at its actual paid home service; no invoice executed by admission.")
	else:
		error=_route_error(context064,book.route,nowSecond)
		if not error.is_empty():return _fail(error)
	var route: Dictionary = book.route
	if route.phase=="lost":return _result(book,{},"This carrier was lost; no cargo can be delivered.")
	if owner.boats.filter(func(b):return not b.sunk).is_empty():
		route.phase="lost";route.location.path=[];route.location.destination=""
		return _result(book,{},"The same physical carrier was lost.")
	if nowSecond+EPS<float(route.nextDueSecond):return _result(book,{},"Scheduled watch or paid harbor service is not yet due.")
	route.nextDueSecond=nowSecond+1.0
	if route.phase=="outbound" and (not snapshot.performance.get("seaworthy",false) or int(owner.wageArrears)>0):
		# An interrupted voyage may reverse without inventing a remote delivery
		# invoice. Its next real home arrival advances the existing sequence.
		route.phase="return";route.location.path=[];route.location.destination=""
	if route.phase in ["home_service","remote_service"]:
		var home: bool = route.phase=="home_service"
		var port: Dictionary = snapshot.originPort if home else snapshot.remotePort
		if not _at_berth(route.location,port):return _fail("Shipping service is not at its actual stopped berth.")
		var slot: int = int(route.sequence)%6
		if slot in [0,3]:
			route.sequence=int(route.sequence)+1;route.nextDueSecond=nowSecond+SERVICE_SECONDS
			return _result(book,_command("service",port,"",0,route.sequence),"Finite paid provisioning and quay service requested once.")
		if not _number(owner.get("harborServiceUntilDay"),1.0) or nowSecond+EPS<float(owner.harborServiceUntilDay)*DAY_SECONDS:return _result(book,{},"Physical paid service has not finished.")
		var required: Dictionary = requirements(context064,snapshot)
		if not required.get("ok",false):
			route.nextDueSecond=nowSecond+3.0
			return _result(book,{},str(required.message))
		var fraction: float = 1.0 if home else 0.5
		if not _ready(snapshot,required,fraction):
			route.nextDueSecond=nowSecond+3.0
			return _result(book,{},"Holding for actual crew, food, fuel, wages and repair reserve; no repeat remittance.")
		var held: float = float(owner.tradeCargo)
		var good: String = "food" if home else "logs"
		var qty: int = 0
		if held>EPS:
			good=str(owner.tradeGood)
			if home and (good!="food" or held>64.0):return _result(book,{},"Unsold prior cargo remains aboard; a bounded food manifest is required before departure.")
		elif Fleets.allowed_trade(owner,port,good):
			var reserve: int = ceili(float(required.wageCoins)*fraction)+int(required.repairCoins)
			var affordable: int = maxi(0,int(owner.coins)-reserve)/maxi(1,Economy.price(port,good,"buy"))
			var capacity: float = maxf(0.0,float(snapshot.reserves.capacity)-Economy.cargo_weight(owner.cargo))
			qty=mini(64,mini(affordable,mini(floori(Harbor.exportable(port,good)),floori(capacity/float(Goods.ITEMS[good].weight)))))
		if home and held+float(qty)<1.0:
			route.nextDueSecond=nowSecond+3.0
			return _result(book,{},"Holding for a funded exportable food lot after all voyage reserves.")
		route.phase="outbound" if home else "return"
		route.sequence=int(route.sequence)+1
		var target: Dictionary = _gate(context064,World.HOME if home else World.REMOTE,false)
		var plotted: Dictionary = World.plot(context064,route.location,target,"" if home else "approach:glasswind_keys:north",float(snapshot.clearance))
		if not plotted.get("ok",false):return _fail(str(plotted.get("message","No safe departure route.")))
		route.location=plotted.location
		return _result(book,_command("load",port,good,qty,route.sequence),"Load only the real affordable lot and depart after paid service.")
	if not route.location.path.is_empty():return _result(book,{},"The physical carrier is underway.")
	var outbound: bool = route.phase=="outbound"
	var destination: Dictionary = snapshot.remotePort if outbound else snapshot.originPort
	if _at_berth(route.location,destination):
		var good: String = str(owner.tradeGood)
		var qty: int = mini(floori(float(owner.cargo.get(good,0.0))),floori(float(owner.tradeCargo)))
		qty=mini(qty,int(destination.get("cash",0))/maxi(1,Economy.price(destination,good,"sell")))
		qty=mini(qty,maxi(0,ceili(Economy.get_equilibrium_stock(destination,good)-float(destination.get("stocks",{}).get(good,0.0)))))
		if not Fleets.allowed_trade(owner,destination,good):qty=0
		route.phase="remote_service" if outbound else "home_service"
		route.sequence=int(route.sequence)+1
		return _result(book,_command("deliver",destination,good,maxi(0,qty),route.sequence),"Real berth reached; unpaid or unwanted cargo stays aboard.")
	return _next_leg(context064,book,snapshot,outbound)


static func actor(modelBook: Dictionary, snapshot: Dictionary) -> Dictionary:
	if not _book_valid(modelBook) or modelBook.route.is_empty() or modelBook.route.get("phase")=="lost" or not _snapshot_error(snapshot).is_empty():return {}
	var route: Dictionary = modelBook.route
	if not _keys(route,["ownerId","phase","location","nextDueSecond","sequence"]) or route.ownerId!=OWNER or route.phase not in PHASES or not _keys(route.location,["world064","position","heading","path","destination"]):return {}
	var powered: bool = snapshot.owner.boats.any(func(b):return not b.sunk and not b.get("mothballed",false) and not b.get("towed",false) and not b.get("needsHarborRepair",false) and str(b.get("storedPort","")).is_empty() and float(b.get("fuel",0.0))>0.0 and float(b.get("crew",0.0))-float(b.get("wounded",0.0))>=float(b.get("crewMin",1.0)))
	return {"ownerId":OWNER,"location":route.location.duplicate(true),"baseSpeed":float(snapshot.performance.get("speed",0.0))*0.38*float(snapshot.campaignScale) if powered else 0.0,
		"clearance":float(snapshot.clearance),"canMove":powered and route.phase in ["outbound","return"],"canIntercept":false,"detectionRange":900.0,"interceptRange":75.0,"boats":_render_boats(snapshot.owner.boats)}


static func _next_leg(context: Dictionary, book: Dictionary, snapshot: Dictionary, outbound: bool) -> Dictionary:
	var route: Dictionary = book.route
	var layer: String = str(route.location.world064.layer)
	var target: Dictionary
	var destination: String = ""
	if layer=="ocean":
		var region_id: String = World.REMOTE if outbound else World.HOME
		target=_gate(context,region_id,true)
		if World._distance(route.location.position,target)<=EPS:
			var crossed: Dictionary = World.transition(context,route.location,region_id,"north",float(snapshot.clearance),"")
			if not crossed.get("ok",false):return _fail(str(crossed.get("message","The northern approach refused crossing.")))
			route.location=crossed.location
			var port: Dictionary = snapshot.remotePort if outbound else snapshot.originPort
			target=_point(port);destination="" if outbound else ORIGIN
		else:destination="approach:%s:north"%region_id
	elif (outbound and layer=="home") or (not outbound and layer=="local"):
		var region_id: String = World.HOME if outbound else World.REMOTE
		target=_gate(context,region_id,false)
		if World._distance(route.location.position,target)<=EPS:
			var crossed: Dictionary = World.transition(context,route.location,region_id,"north",float(snapshot.clearance),"")
			if not crossed.get("ok",false):return _fail(str(crossed.get("message","The northern approach refused crossing.")))
			route.location=crossed.location
			region_id=World.REMOTE if outbound else World.HOME
			target=_gate(context,region_id,true);destination="approach:%s:north"%region_id
		elif layer=="local":destination="approach:glasswind_keys:north"
	else:
		var port: Dictionary = snapshot.remotePort if outbound else snapshot.originPort
		target=_point(port);destination="" if outbound else ORIGIN
	var plotted: Dictionary = World.plot(context,route.location,target,destination,float(snapshot.clearance))
	if not plotted.get("ok",false):return _fail(str(plotted.get("message","Shipping route could not be plotted.")))
	route.location=plotted.location
	return _result(book,{},"One physical northern shipping leg staged.")


static func _ready(snapshot: Dictionary, required: Dictionary, fraction: float) -> bool:
	var reserve: Dictionary = snapshot.reserves
	return snapshot.performance.get("seaworthy",false) and Economy.cargo_weight(snapshot.owner.cargo)<=float(reserve.capacity)+EPS and float(reserve.get("food",0.0))+EPS>=float(required.food)*fraction and float(reserve.get("fuel",0.0))+EPS>=float(required.fuel)*fraction and int(snapshot.owner.coins)>=ceili(float(required.wageCoins)*fraction)+int(required.repairCoins)


static func _book_valid(book) -> bool:
	return _keys(book,["schema","route"]) and _number(book.schema) and book.schema==1 and book.route is Dictionary


static func _route_error(context: Dictionary, route: Dictionary, now: float) -> String:
	if not _keys(route,["ownerId","phase","location","nextDueSecond","sequence"]) or route.ownerId!=OWNER or route.phase not in PHASES:return "Invalid shipping route owner, phase or fields."
	if not _number(route.sequence,0.0) or float(route.sequence)!=floorf(float(route.sequence)) or float(route.sequence)>1000000000.0:return "Shipping sequence must be a bounded integer."
	var slot: int = int(route.sequence)%6
	if route.phase!="lost" and not ((route.phase in ["home_service","remote_service"] and slot in [0,1,3,4]) or (route.phase in ["outbound","return"] and slot in [2,5])):return "Shipping phase and once-only invoice sequence disagree."
	if not _number(route.nextDueSecond,0.0) or float(route.nextDueSecond)>now+SERVICE_SECONDS+3.0+EPS:return "Invalid scheduled shipping deadline."
	if not _keys(route.location,["world064","position","heading","path","destination"]) or not route.location.path is Array or route.location.path.size()>128:return "Shipping location needs only bounded canonical spatial fields."
	var located: Dictionary = World.prepare(route.location,context,0.0)
	return "" if located.get("ok",false) else str(located.get("message","Invalid shipping location."))


static func _snapshot_error(snapshot: Dictionary) -> String:
	if not _keys(snapshot,["owner","patrol","originPort","remotePort","reserves","performance","clearance","campaignScale"]):return "Shipping snapshot requires exactly the agreed physical queries."
	for key in ["owner","patrol","originPort","remotePort","reserves","performance"]:
		if not snapshot[key] is Dictionary:return "Shipping physical queries must be dictionaries."
	var error: String = _owner_error(snapshot.owner)
	if not error.is_empty():return error
	if snapshot.patrol.get("id")!=OWNER:return "Shipping snapshot must use the same original patrol."
	if snapshot.originPort.get("id")!=ORIGIN or snapshot.remotePort.get("id")!=REMOTE_PORT or snapshot.remotePort.get("regionId")!=World.REMOTE or snapshot.remotePort.get("faction")!="reed" or not _point_valid(snapshot.originPort) or not _point_valid(snapshot.remotePort) or _point(snapshot.remotePort)!=BERTH:return "Shipping needs the actual funded Kelp/Westglass endpoints and final berth."
	if not _number(snapshot.clearance,0.0) or not _number(snapshot.campaignScale,EPS):return "Shipping clearance and scale must be finite."
	if not _number(snapshot.performance.get("speed"),0.0):return "Shipping performance must contain finite actual speed."
	for key in ["capacity","boats","food","fuel"]:
		if not _number(snapshot.reserves.get(key),0.0):return "Shipping reserves must contain actual finite physical quantities."
	return ""


static func _owner_error(owner: Dictionary) -> String:
	if owner.get("id")!=OWNER or owner.get("kind")!="trader" or owner.get("homePort")!=ORIGIN or owner.get("playerCompany",false) or not owner.get("active") is bool:return "Only the original non-company Kelp trader may use this route."
	if not owner.get("boats") is Array or owner.boats.size()>36 or not owner.get("cargo") is Dictionary:return "Shipping needs the actual bounded physical boats and hold."
	for key in ["coins","crewPurse","wageArrears","tradeCargo"]:
		if not _number(owner.get(key),0.0):return "Shipping accounts and manifest must be finite and nonnegative."
	if not owner.get("tradeGood") is String or not Goods.ITEMS.has(owner.tradeGood):return "Shipping manifest good is invalid."
	for good in owner.cargo:
		if not good is String or not Goods.ITEMS.has(good) or not _number(owner.cargo[good],0.0):return "Shipping hold contains invalid raw goods."
	if float(owner.tradeCargo)>float(owner.cargo.get(owner.tradeGood,0.0))+EPS:return "Shipping manifest exceeds the surviving physical cargo."
	var ids: Dictionary = {}
	for boat in owner.boats:
		if not boat is Dictionary or not boat.get("spec") is Dictionary or not boat.get("uid") is String or str(boat.uid).is_empty() or ids.has(boat.uid) or not boat.get("sunk") is bool:return "Shipping hull identity or physical specification is invalid."
		ids[boat.uid]=true
		for key in ["size","cargo","speed"]:
			if not _number(boat.spec.get(key),0.0):return "Shipping physical hull dimensions must be finite."
		for key in ["fuel","crew","wounded"]:
			if not _number(boat.get(key),0.0):return "Shipping hull stores and crew must be finite."
	return ""


static func _at_berth(location: Dictionary, port: Dictionary) -> bool:
	if not location.get("world064") is Dictionary or not location.get("path") is Array or not location.path.is_empty() or not _point_valid(location.get("position")) or not _point_valid(port):return false
	var remote: bool = port.get("id")==REMOTE_PORT
	return location.world064.get("layer")==("local" if remote else "home") and location.world064.get("regionId")== (World.REMOTE if remote else World.HOME) and World._distance(location.position,port)<40.0


static func _gate(context: Dictionary, region_id: String, ocean: bool) -> Dictionary:
	var region = context.get("regions",{}).get(region_id)
	if not region is Dictionary or not region.get("approaches") is Array:return {}
	for approach in region.approaches:
		if approach.get("id")=="north":return World._project(context,region,approach.position) if ocean else _point(approach.position)
	return {}


static func _render_boats(boats: Array) -> Array:
	var result: Array = []
	for boat in boats:
		if boat.sunk:continue
		var spec: Dictionary = {"id":str(boat.get("type",boat.spec.get("id","")))}
		for key in ["role","size","tier","faction","weapon","fuelUse"]:
			if boat.spec.has(key):spec[key]=boat.spec[key]
		var mounts: Array = []
		for mount in boat.spec.get("weaponMounts",[]):
			var item: Dictionary = {}
			for key in ["id","moduleId","kind","size","x","y","angle"]:
				if mount.has(key):item[key]=mount[key]
			mounts.append(item)
		if not mounts.is_empty():spec["weaponMounts"]=mounts
		result.append({"uid":str(boat.uid),"spec":spec,"engineModule":str(boat.get("engineModule","stock_engine"))})
	return result


static func _command(kind: String, port: Dictionary, good: String, qty: int, sequence: int) -> Dictionary:
	return {"kind":kind,"ownerId":OWNER,"portId":str(port.id),"good":good,"qty":qty,"sequence":sequence}


static func _result(book: Dictionary, command: Dictionary, message: String) -> Dictionary:
	return {"ok":true,"book":book,"command":command,"message":message}


static func _fail(message: String) -> Dictionary:
	return {"ok":false,"message":message}


static func _location(layer: String, region: String, position: Dictionary) -> Dictionary:
	return {"world064":{"schema":1,"layer":layer,"regionId":region},"position":position.duplicate(),"heading":0.0,"path":[],"destination":""}


static func _length(start: Dictionary, path: Array) -> float:
	var distance: float = 0.0
	var previous: Dictionary = start
	for point in path:distance+=World._distance(previous,point);previous=point
	return distance


static func _number(value, minimum: float = -INF) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum


static func _keys(value, keys: Array) -> bool:
	if not value is Dictionary or value.size()!=keys.size():return false
	for key in keys:
		if not value.has(key):return false
	return true


static func _point_valid(value) -> bool:
	return value is Dictionary and _number(value.get("x")) and _number(value.get("y"))


static func _point(value: Dictionary) -> Dictionary:
	return {"x":float(value.x),"y":float(value.y)}
