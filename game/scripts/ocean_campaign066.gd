extends RefCounted
## One physical raider's spatial adapter. Campaign retains every account and boat.
const Travel=preload("res://scripts/ocean_travel066.gd")
const World=preload("res://scripts/ocean_world064.gd")
const Orders=preload("res://scripts/naval_orders.gd")
const Routes=preload("res://scripts/route_cache.gd")
const Fleets=preload("res://scripts/fleet_economy.gd")
const Money=preload("res://scripts/money.gd")
const Flow=preload("res://scripts/shipping_flow068.gd")
const OWNER="patrol-0"
const PHASES=["supply","outbound","patrol","return","lost"]

static func empty_book() -> Dictionary:
	return {"schema":1,"contact":{},"memory":Travel.empty_memory()}

static func _fail(message: String) -> Dictionary:
	return {"ok":false,"message":message}

static func _keys(value,keys: Array) -> bool:
	if not value is Dictionary or value.size()!=keys.size():return false
	for key in keys:
		if not value.has(key):return false
	return true

static func _finite(value,minimum: float=-INF) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum

static func _point(value) -> bool:
	return _keys(value,["x","y"]) and _finite(value.x) and _finite(value.y)

static func _owner(state: Dictionary,id: String="") -> Dictionary:
	if id.is_empty():id=str(state.get("ocean066",{}).get("contact",{}).get("ownerId",OWNER))
	return Orders.find_owner(state,id)

static func _patrol(state: Dictionary,id: String="") -> Dictionary:
	if id.is_empty():id=str(state.get("ocean066",{}).get("contact",{}).get("ownerId",OWNER))
	return Orders.find_patrol(state,id)

static func clearance(owner: Dictionary) -> float:
	var result: float=10.0
	for boat in owner.get("boats",[]):
		if not boat.get("sunk",false):result=maxf(result,float(boat.get("spec",{}).get("size",10.0)))
	return result

static func prepare(saved: Dictionary,context064: Dictionary) -> Dictionary:
	if not saved.has("ocean066"):return {"ok":true,"book":empty_book()}
	var book=saved.get("ocean066")
	if not _keys(book,["schema","contact","memory"]) or book.schema!=1 or not book.contact is Dictionary:return _fail("Invalid ocean066 book.")
	if not _finite(saved.get("day"),1.0):return _fail("Invalid ocean066 clock.")
	if not _finite(saved.get("seed"),0.0) or not saved.get("fleetOwners") is Array or not saved.get("patrols") is Array or not saved.get("fleet") is Array or not saved.get("boardingPrizes",[]) is Array:return _fail("Ocean066 requires valid campaign collections.")
	var made: Dictionary=Travel.create(context064,int(saved.get("seed",0)),book.memory,admitted_owner_ids(saved),float(saved.day)*45.0)
	if not made.get("ok",false):return _fail(str(made.get("message","Invalid ocean066 memory.")))
	var contact: Dictionary=book.contact
	if not contact.is_empty():
		if not _keys(contact,["ownerId","phase","location","gate","waypoint"]) or not contact.ownerId is String or str(contact.ownerId).is_empty() or contact.phase not in PHASES:return _fail("Invalid ocean066 admission or phase.")
		var id: String=str(contact.ownerId)
		var corridor: Dictionary=_published_corridor(saved)
		if (corridor.is_empty() and id!=OWNER) or id==str(corridor.get("ownerId","")):return _fail("Invalid ocean066 raider enrollment.")
		var owners: Array=saved.get("fleetOwners",[]).filter(func(o):return o is Dictionary and str(o.get("id",""))==id)
		var patrols: Array=saved.get("patrols",[]).filter(func(p):return p is Dictionary and str(p.get("id",""))==id)
		if owners.size()!=1 or patrols.size()!=1:return _fail("Ocean contact needs one existing owner and home projection.")
		var owner: Dictionary=owners[0]
		var patrol: Dictionary=patrols[0]
		if not owner.get("boats") is Array or not patrol.get("course",[]) is Array:return _fail("Invalid ocean066 physical fleet or projection route.")
		for boat in owner.boats:
			if not boat is Dictionary or not boat.get("spec") is Dictionary:return _fail("Invalid ocean boat or specification.")
			if not _finite(boat.spec.get("size",10.0),0.0):return _fail("Invalid ocean boat clearance.")
		if owner.get("kind","")!="raider" or Orders.is_story_owner(owner) or owner.get("playerCompany",false) or not Orders.RegionalOrders.operation(saved,owner).is_empty():return _fail("Only an unassigned existing nonstory raider may enroll.")
		if patrol.get("active",true) or not patrol.get("hidden",false) or not patrol.get("holding",false) or not patrol.get("course",[]).is_empty():return _fail("Enrolled home projection must be dormant.")
		if not _keys(contact.gate,["regionId","approachId"]) or contact.gate.regionId!="shatter_coast" or contact.gate.approachId not in ["north","south"] or not _point(contact.waypoint):return _fail("Invalid ocean066 gate or waypoint.")
		if not contact.location is Dictionary:return _fail("Invalid canonical ocean066 location.")
		var located: Dictionary=World.prepare(contact.location,context064,clearance(owner))
		if not located.get("ok",false):return _fail("Ocean contact: "+str(located.get("message","Invalid location.")))
		var waypoint: Dictionary={"world064":{"schema":1,"layer":"ocean","regionId":"open_ocean"},"position":contact.waypoint,"heading":0.0,"path":[],"destination":""}
		if not World.prepare(waypoint,context064,clearance(owner)).get("ok",false):return _fail("Ocean patrol waypoint is unsafe.")
		if located.location.world064.layer not in ["home","ocean"]:return _fail("The bounded raider patrol cannot enter a remote region.")
		if (contact.phase=="outbound" and located.location.world064.layer!="home") or (contact.phase=="patrol" and located.location.world064.layer!="ocean"):return _fail("Ocean patrol phase and chart disagree.")
		var region: Dictionary=context064.regions["shatter_coast"]
		var ocean_gate: Dictionary={}
		for approach in region.approaches:
			if str(approach.id)==str(contact.gate.approachId):ocean_gate={"x":float(region.oceanOrigin.x)+float(approach.position.x)/10.0,"y":float(region.oceanOrigin.y)+float(approach.position.y)/10.0}
		var points: Dictionary=_corridor_points(saved,context064)
		var remote: Dictionary=points.get("remoteOcean",{})
		var on_corridor: bool=not remote.is_empty() and str(contact.gate.regionId)=="shatter_coast" and World._distance(contact.waypoint,remote)<=0.001
		if ocean_gate.is_empty() or (World._distance(contact.waypoint,ocean_gate)>80.000001 and not on_corridor):return _fail("The one raider's patrol must remain a short gate-local loop.")
		var living: Array=Orders.living_boats(owner)
		if contact.phase=="lost":
			if not living.is_empty() or owner.get("active",true) or not str(owner.get("atPort","")).is_empty():return _fail("Lost offshore owner cannot retain living hulls or a home berth.")
			if not located.location.path.is_empty() or not str(located.location.destination).is_empty():return _fail("A lost ocean fleet cannot keep a moving course.")
		elif living.is_empty() or not owner.get("active",false):return _fail("An active ocean contact needs its original physical fleet.")
		var at: String=str(owner.get("atPort",""))
		if contact.phase=="supply":
			var home: Dictionary=Orders.find_port(saved,str(owner.get("homePort","")))
			if located.location.world064.layer!="home" or at!=str(home.get("id","")) or home.is_empty() or World._distance(located.location.position,home)>=40.0:return _fail("Ocean departure needs an actual home harbor visit.")
			if located.location.position!={"x":patrol.get("x"),"y":patrol.get("y")} or not located.location.path.is_empty():return _fail("Supply location must match the actual dormant home projection.")
			if not _finite(owner.get("harborServiceUntilDay"),maxf(1.0,float(saved.day)-4.0/45.0)) or float(owner.harborServiceUntilDay)>float(saved.day)+0.25+0.000001:return _fail("Invalid paid ocean departure service deadline.")
		elif not at.is_empty() or owner.has("harborServiceUntilDay"):return _fail("An ocean passage cannot receive remote harbor service.")
		for boat in owner.get("boats",[]):
			if not boat is Dictionary:return _fail("Invalid ocean boat record.")
			if str(boat.get("uid","")).is_empty():return _fail("Ocean boats require their existing UIDs.")
			var count: int=0
			for b in saved.get("fleet",[])+saved.get("boardingPrizes",[]):
				if not b is Dictionary:return _fail("Invalid player boat custody.")
				if str(b.get("uid",""))==str(boat.uid):count+=1
			for other in saved.get("fleetOwners",[]):
				if not other is Dictionary or not other.get("boats") is Array:return _fail("Invalid owner boat custody.")
				for b in other.get("boats",[]):
					if not b is Dictionary:return _fail("Invalid owner boat record.")
					if str(b.get("uid",""))==str(boat.uid):count+=1
			if count!=1:return _fail("Ocean boat custody must remain unique.")
	var prepared: Dictionary=book.duplicate(true)
	prepared["memory"]=made.memory
	return {"ok":true,"book":prepared}

static func render_boats(boats: Array) -> Array:
	var output: Array=[]
	for boat in boats:
		if boat.get("sunk",false):continue
		# The locked render DTO is bounded; physical roster/accounting uses all boats.
		if output.size()>=36:break
		var spec: Dictionary={"id":str(boat.get("type",boat.get("spec",{}).get("id","")))}
		for key in ["role","size","tier","faction","weapon","fuelUse"]:
			if boat.get("spec",{}).has(key):spec[key]=boat.spec[key]
		var mounts: Array=[]
		for mount in boat.get("spec",{}).get("weaponMounts",[]):
			var item: Dictionary={}
			for key in ["id","moduleId","kind","size","x","y","angle"]:
				if mount.has(key):item[key]=mount[key]
			mounts.append(item)
		if not mounts.is_empty():spec["weaponMounts"]=mounts
		var row: Dictionary={"uid":str(boat.get("uid","")),"spec":spec}
		var engine=boat.get("loadout",{}).get("engine","")
		if engine is String and not engine.is_empty():row["engineModule"]=engine
		output.append(row)
	return output

static func powered(boats: Array) -> bool:
	for boat in boats:
		if boat.get("sunk",false) or boat.get("mothballed",false) or boat.get("needsHarborRepair",false) or boat.get("towed",false) or not str(boat.get("storedPort","")).is_empty():continue
		if float(boat.get("crew",0))-float(boat.get("wounded",0))<float(boat.get("crewMin",1)):continue
		var fuel=boat.get("fuel")
		if _finite(fuel,0.0) and float(fuel)>0.0:return true
	return false

static func actors(c,book: Dictionary) -> Array:
	var player_power: bool=powered(c.active_fleet())
	# Coastal grace stays with HOME encounters; offshore capability follows physical readiness.
	var player: Dictionary={"ownerId":"player","location":c.world_location064(),"baseSpeed":c.travel_speed() if player_power else 0.0,"clearance":Routes.clearance(c),"canMove":not c.home_local064() and player_power,"canIntercept":player_power and not c.home_local064() and not c.FleetSupport.combat(c).is_empty(),"detectionRange":1800.0,"interceptRange":75.0,"boats":render_boats(c.active_fleet())}
	var result: Array=[player]
	var contact: Dictionary=book.get("contact",{})
	if contact.is_empty() or contact.phase=="lost":return _with_shipping(c,result)
	var owner: Dictionary=_owner(c.state,str(contact.ownerId))
	# Performance queries normalize; use a detached physical snapshot here.
	var snapshot: Dictionary=owner.duplicate(true)
	var performance: Dictionary=Orders.fleet_performance(snapshot)
	var npc_power: bool=powered(snapshot.get("boats",[]))
	var armed: bool=Orders.living_boats(snapshot).any(func(b):return float(b.get("ammo",0))>0.0 and float(b.get("crew",0))-float(b.get("wounded",0))>=float(b.get("crewMin",1)))
	result.append({"ownerId":str(contact.ownerId),"location":contact.location.duplicate(true),"baseSpeed":float(performance.speed)*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0)) if npc_power else 0.0,"clearance":clearance(snapshot),"canMove":npc_power and contact.phase!="supply","canIntercept":npc_power and armed and contact.phase=="patrol","detectionRange":900.0,"interceptRange":75.0,"boats":render_boats(owner.get("boats",[]))})
	return _with_shipping(c,result)

static func _with_shipping(c,participants: Array) -> Array:
	var merchant: Dictionary=c.ShippingFlow068.actor(c)
	if not merchant.is_empty():participants.append(merchant)
	return participants

static func relations(c,participants: Array) -> Array:
	var result: Array=[]
	for observer in participants:
		var ranked: Array=[]
		var index: int=0
		for target in participants:
			if observer.ownerId==target.ownerId:continue
			var hostile: bool
			if observer.ownerId=="player" or target.ownerId=="player":
				var npc: String=str(target.ownerId) if observer.ownerId=="player" else str(observer.ownerId)
				hostile=bool(c.Politics.hostile(c,_owner(c.state,npc)))
			else:
				var a: Dictionary=_owner(c.state,str(observer.ownerId))
				var b: Dictionary=_owner(c.state,str(target.ownerId))
				hostile=str(a.get("faction",""))!=str(b.get("faction","")) and c.Factions.relation(c.state,str(a.get("faction","")),str(b.get("faction","")))<=-20
				# The real NPC resolver permits one participation per owner/day and
				# a shared daily cap. A spent slot must not clip every later tick to0.
				var ledger: Dictionary=c.state.get("navalAi",{})
				if int(ledger.get("encounterDay",-1))==int(c.state.get("econDay",1)):
					var busy: Dictionary=ledger.get("encounterOwners",{})
					if int(ledger.get("encounterCount",0))>=c.NavalAI.MAX_ENCOUNTERS_PER_DAY or busy.has(str(observer.ownerId)) or busy.has(str(target.ownerId)):hostile=false
			var seen_load: float=-1.0
			if hostile and str(observer.ownerId)!="player":seen_load=_observed_load(c,observer,target)
			ranked.append({"observerId":str(observer.ownerId),"targetId":str(target.ownerId),"hostile":hostile,"_load":seen_load,"_i":index})
			index+=1
		if str(observer.ownerId)!="player":
			ranked.sort_custom(func(left,right):
				if float(left._load)!=float(right._load):return float(left._load)>float(right._load)
				return int(left._i)<int(right._i))
		for row in ranked:
			row.erase("_load");row.erase("_i")
			result.append(row)
	return result

static func _observed_load(c,observer: Dictionary,target: Dictionary) -> float:
	# Prefer cargo only from a sighting sampled while the target was visible.
	var sight=c.state.get("ocean066",{}).get("memory",{}).get("sightings",{}).get(str(observer.ownerId),{}).get(str(target.ownerId),{})
	if not sight is Dictionary or sight.is_empty():return -1.0
	var now: float=float(c.state.day)*45.0
	if float(sight.get("expiresSecond",0.0))<=now:return -1.0
	if not Travel.same_world(sight.get("world064"),target.location.world064):return -1.0
	var manifest=sight.get("manifest075",{})
	if not manifest is Dictionary or not manifest.has("cargoValue"):return -1.0
	return maxf(0.0,float(manifest.cargoValue))

static func _exact_corridor(corridor) -> Dictionary:
	if not corridor is Dictionary:return {}
	if not _keys(corridor,["ownerId","homeId","originId","remoteId","homeGate","originGate","remoteGate"]):return {}
	for key in ["ownerId","homeId","originId","remoteId"]:
		if not corridor[key] is String or str(corridor[key]).is_empty():return {}
	for key in ["homeGate","originGate","remoteGate"]:
		var gate=corridor[key]
		if not gate is Dictionary or not _keys(gate,["regionId","approachId"]):return {}
		if not gate.regionId is String or not gate.approachId is String or str(gate.regionId).is_empty() or str(gate.approachId).is_empty():return {}
	return corridor

static func _published_corridor(state: Dictionary) -> Dictionary:
	return _exact_corridor(Flow.corridor075(state))

static func _route_corridor(route: Dictionary) -> Dictionary:
	if not route is Dictionary:return {}
	return _exact_corridor(route.get("corridor075",{}))

## Player, the enrolled raider, and the selected trader. Legacy ids apply only
## while the shipping book has no exact corridor075 record.
static func admitted_owner_ids(state: Dictionary,staged_route: Dictionary={}) -> Array:
	var corridor: Dictionary=_route_corridor(staged_route)
	if corridor.is_empty():corridor=_published_corridor(state)
	if corridor.is_empty():
		var legacy: String=str(Flow.owner_id075(state))
		if legacy.is_empty() or legacy=="player":legacy="patrol-7"
		var legacy_ids: Array=["player",OWNER]
		if not legacy_ids.has(legacy):legacy_ids.append(legacy)
		return legacy_ids
	var trader: String=str(corridor.ownerId)
	var contact=state.get("ocean066",{}).get("contact",{})
	var raider: String=OWNER
	if contact is Dictionary and not str(contact.get("ownerId","")).is_empty():raider=str(contact.ownerId)
	var ids: Array=["player"]
	if raider!="player" and not ids.has(raider):ids.append(raider)
	if trader!="player" and not ids.has(trader):ids.append(trader)
	return ids

static func _ocean_gate(context064: Dictionary,gate: Dictionary) -> Dictionary:
	if not context064.get("ocean") is Dictionary or not context064.get("regions") is Dictionary:return {}
	var region: Dictionary=context064.regions.get(str(gate.get("regionId","")),{})
	if region.is_empty() or not region.get("oceanOrigin") is Dictionary:return {}
	var approach: Dictionary=World._approach(region,str(gate.get("approachId","")))
	if approach.is_empty() or not approach.get("position") is Dictionary:return {}
	return World._project(context064,region,approach.position)

static func _corridor_points(state: Dictionary,context064: Dictionary,staged_route: Dictionary={}) -> Dictionary:
	var corridor: Dictionary=_route_corridor(staged_route)
	if corridor.is_empty():corridor=_published_corridor(state)
	if corridor.is_empty():return {}
	var origin: Dictionary=_ocean_gate(context064,corridor.originGate)
	var remote: Dictionary=_ocean_gate(context064,corridor.remoteGate)
	if origin.is_empty() or remote.is_empty():return {}
	return {"originOcean":origin,"remoteOcean":remote,"corridor":corridor}

static func _port_label(state: Dictionary,id: String) -> String:
	for port in state.get("ports",[]):
		if port is Dictionary and str(port.get("id",""))==id:
			var name: String=str(port.get("name",""))
			return name if not name.is_empty() else id
	return id

static func _release_unadmitted(memory: Dictionary,ids: Array) -> void:
	for group in ["intents","sightings","pursuits"]:
		if not memory.get(group) is Dictionary:continue
		for key in memory[group].keys():
			if not ids.has(str(key)):memory[group].erase(key)
	if memory.get("intents") is Dictionary:
		for owner_id in memory.intents.keys():
			var target: String=str(memory.intents[owner_id].get("targetId",""))
			if not target.is_empty() and not ids.has(target):memory.intents.erase(owner_id)
	if memory.get("sightings") is Dictionary:
		for observer_id in memory.sightings.keys():
			var sights: Dictionary=memory.sightings[observer_id]
			if not sights is Dictionary:
				memory.sightings.erase(observer_id)
				continue
			for target_id in sights.keys():
				if not ids.has(str(target_id)):sights.erase(target_id)
			if sights.is_empty():memory.sightings.erase(observer_id)
	if memory.get("pursuits") is Dictionary:
		for owner_id in memory.pursuits.keys():
			if not ids.has(str(memory.pursuits[owner_id].get("targetId",""))):memory.pursuits.erase(owner_id)

static func _bind_admitted(c,book: Dictionary,ids: Array) -> void:
	if c.ocean_context066.is_empty():return
	c.ocean_context066["ownerIds"]=ids.duplicate()
	_release_unadmitted(book.memory,ids)

static func _observation075(c,owner: Dictionary) -> Dictionary:
	var order=owner.get("order",{})
	if not order is Dictionary:order={}
	var purpose: String=str(order.get("purpose","")).left(128)
	var destination: String=str(order.get("destination","")).left(128)
	var reason: String=str(order.get("reason",""))
	if reason.is_empty() and not purpose.is_empty():reason=Orders.observation_reason(purpose)
	var manifest: Dictionary=Orders.observed_manifest075(owner)
	if not manifest is Dictionary:manifest={}
	return {"intention075":{"purpose":purpose,"destination":destination,"reason":reason.left(240),"day":float(c.state.day)},"manifest075":{"cargoGood":str(manifest.get("cargoGood","")).left(128),"cargoQuantity":maxf(0.0,float(manifest.get("cargoQuantity",0.0))),"cargoValue":maxf(0.0,float(manifest.get("cargoValue",0.0)))}}

static func _attach_observations(c,participants: Array) -> void:
	for actor in participants:
		if str(actor.get("ownerId",""))=="player":continue
		var owner: Dictionary=_owner(c.state,str(actor.get("ownerId","")))
		if owner.is_empty():continue
		actor["observation075"]=_observation075(c,owner)

static func _physical_contact(c,id: String) -> Dictionary:
	var contact=c.state.get("ocean066",empty_book()).get("contact",{})
	if contact is Dictionary and str(contact.get("ownerId",""))==id:return contact
	var route=c.state.get("shipping068",{}).get("model",{}).get("route",{})
	if route is Dictionary and not route.is_empty() and str(route.get("ownerId",""))==id:return route
	return {}

static func _gate(c,gate: Dictionary,ocean: bool) -> Dictionary:
	var region: Dictionary=c.ocean_context064.regions[gate.regionId]
	for approach in region.approaches:
		if str(approach.id)!=str(gate.approachId):continue
		return {"x":float(region.oceanOrigin.x)+float(approach.position.x)/10.0,"y":float(region.oceanOrigin.y)+float(approach.position.y)/10.0} if ocean else approach.position.duplicate(true)
	return {}

static func _plan(c,book: Dictionary,target: Dictionary,destination: String="") -> bool:
	var contact: Dictionary=book.contact
	var owner: Dictionary=_owner(c.state,str(contact.ownerId))
	var result: Dictionary=World.plot(c.ocean_context064,contact.location,target,destination,clearance(owner))
	if not result.get("ok",false):return false
	if result.location.world064.layer=="home" and destination==str(owner.get("homePort","")):
		var path: Array=Routes.path(c,{"id":str(contact.ownerId),"x":float(contact.location.position.x),"y":float(contact.location.position.y)},target,clearance(owner))
		if path.is_empty():return false
		path=path.duplicate(true);path.pop_front();result.location["path"]=path
	contact["location"]=result.location
	book.memory.intents[str(contact.ownerId)]={"kind":"route","targetId":"","goal":{"world064":result.location.world064.duplicate(true),"target":target.duplicate(true),"destination":destination},"returnGoal":{},"lastPlanSecond":float(c.state.day)*45.0}
	return true

static func _ocean_seconds075(c,start: Dictionary,points: Array,speed: float) -> float:
	if speed<=0.0:return INF
	var legs: Array=[]
	var previous: Dictionary=start
	for point in points:
		var distance: float=c.distance(previous,point)*Travel.SCALE
		legs.append({"kind":"sail","layer":"ocean","from":previous,"to":point,"path":[point],"physicalDistance":distance,"seconds":distance/speed})
		previous=point
	var forecast: Dictionary=Travel.forecast(c.ocean_context066,legs,speed,float(c.state.day)*45.0)
	return float(forecast.conservativeSeconds) if forecast.get("ok",false) else INF

static func _return_days(c,contact: Dictionary,speed: float) -> float:
	var gate: Dictionary=_gate(c,contact.gate,false)
	var owner: Dictionary=_owner(c.state,str(contact.ownerId))
	var home: Dictionary=c.port(str(owner.homePort))
	var local_path: Array=Routes.path(c,{"id":str(contact.ownerId),"x":gate.x,"y":gate.y},home,clearance(owner))
	if local_path.is_empty():return INF
	var length: float=0.0
	for i in range(1,local_path.size()):length+=c.distance(local_path[i-1],local_path[i])
	var ocean_seconds: float=0.0
	if contact.location.world064.layer=="ocean":
		var ocean_gate: Dictionary=_gate(c,contact.gate,true)
		if not _published_corridor(c.state).is_empty():ocean_seconds=_ocean_seconds075(c,contact.location.position,[ocean_gate],speed)
		else:ocean_seconds=c.distance(contact.location.position,ocean_gate)*10.0/0.25/maxf(0.001,speed)
	else:length=maxf(length,c.distance(contact.location.position,home))
	return (length/maxf(0.001,speed)+ocean_seconds)/45.0+0.5

static func _control(c,book: Dictionary) -> void:
	var contact: Dictionary=book.contact
	if contact.is_empty() or contact.phase=="lost":return
	var owner: Dictionary=_owner(c.state,str(contact.ownerId))
	var copy: Dictionary=owner.duplicate(true)
	var reserves: Dictionary=Orders.fleet_reserves(copy)
	var performance: Dictionary=Orders.fleet_performance(copy)
	var speed: float=float(performance.speed)*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0))
	if contact.phase=="supply":
		if float(c.state.day)<float(owner.get("harborServiceUntilDay",INF)):return
		contact["phase"]="outbound"
		# Like Core.approach_course064, HOME targets the gate with no destination label.
		_plan(c,book,_gate(c,contact.gate,false))
	var return_days: float=_return_days(c,contact,speed)
	if contact.phase in ["outbound","patrol"] and (not Orders.needs_home_recovery(copy,reserves,performance).is_empty() or float(reserves.get("foodDays",0))<=return_days or float(reserves.get("wageDays",0))<=return_days):
		contact["phase"]="return"
		book.memory.pursuits.erase(str(contact.ownerId))
		contact.location["path"]=[];contact.location["destination"]=""
		_plan(c,book,_gate(c,contact.gate,true) if contact.location.world064.layer=="ocean" else c.port(str(owner.homePort)),"approach:shatter_coast:"+str(contact.gate.approachId) if contact.location.world064.layer=="ocean" else str(owner.homePort))
	if not contact.location.path.is_empty():return
	if contact.phase=="outbound" or (contact.phase=="return" and contact.location.world064.layer=="ocean"):
		if not book.memory.pursuits.is_empty():return
		var crossed: Dictionary=World.transition(c.ocean_context064,contact.location,"shatter_coast",str(contact.gate.approachId),clearance(owner),"")
		if not crossed.get("ok",false):return
		contact["location"]=crossed.location
		if contact.phase=="outbound":
			contact["phase"]="patrol"
			var points: Dictionary=_corridor_points(c.state,c.ocean_context064)
			if not points.is_empty() and c.distance(contact.waypoint,points.remoteOcean)<=0.001:_plan(c,book,points.originOcean)
			else:_plan(c,book,contact.waypoint)
		else:_plan(c,book,c.port(str(owner.homePort)),str(owner.homePort))
	elif contact.phase=="patrol" and book.memory.pursuits.is_empty():
		var gate: Dictionary=_gate(c,contact.gate,true)
		var points: Dictionary=_corridor_points(c.state,c.ocean_context064)
		if not points.is_empty() and c.distance(contact.waypoint,points.remoteOcean)<=0.001:
			var origin: Dictionary=points.originOcean
			var at_origin: bool=c.distance(contact.location.position,origin)<0.001
			# Enter at generated A, then sail to generated B. Home return stays on contact.gate.
			_plan(c,book,contact.waypoint if at_origin else origin)
		else:_plan(c,book,gate if c.distance(contact.location.position,contact.waypoint)<0.001 else contact.waypoint)

static func stage(c,dt: float) -> Dictionary:
	# One call moves the player and at most two admitted owners. It does not step the world.
	if c.ocean_context066.is_empty():
		if not c.home_local064():return _fail("Ocean travel definitions are unavailable.")
		return {"ok":true,"acceptedSeconds":dt,"locations":[],"book":c.state.get("ocean066",empty_book()).duplicate(true),"encounter":{},"conditions":[],"watchDue":false}
	var book: Dictionary=c.state.get("ocean066",empty_book()).duplicate(true)
	if c.ocean_watch066>=1.0 or (not book.contact.is_empty() and book.contact.location.path.is_empty()):_control(c,book)
	var shipping: Dictionary=c.ShippingFlow068.stage(c,dt)
	if not shipping.get("ok",false):return shipping
	var staged_route: Dictionary={}
	if shipping.get("model") is Dictionary and shipping.model.get("route") is Dictionary:staged_route=shipping.model.route
	var ids: Array=admitted_owner_ids(c.state,staged_route)
	_bind_admitted(c,book,ids)
	var trader: String=str(Flow.owner_id075(c.state))
	if not _route_corridor(staged_route).is_empty():trader=str(_route_corridor(staged_route).ownerId)
	elif not staged_route.is_empty() and staged_route.get("ownerId") is String:trader=str(staged_route.ownerId)
	elif not _published_corridor(c.state).is_empty():trader=str(_published_corridor(c.state).ownerId)
	if trader.is_empty() or trader=="player":trader="patrol-7"
	var participants: Array=[]
	for actor in actors(c,book):
		var id: String=str(actor.get("ownerId",""))
		if id==trader or not ids.has(id):continue
		participants.append(actor)
	if not shipping.actor.is_empty():
		var merchant_id: String=str(shipping.actor.get("ownerId",""))
		if ids.has(merchant_id) and not participants.any(func(a):return str(a.ownerId)==merchant_id):participants.append(shipping.actor)
	_attach_observations(c,participants)
	var watch: bool=c.ocean_watch066>=1.0
	var raider: String=str(book.contact.get("ownerId",""))
	var decisions: Array=[raider] if watch and not book.contact.is_empty() and book.contact.phase=="patrol" and participants.any(func(a):return str(a.ownerId)==raider) else []
	var stepped: Dictionary=Travel.step(c.ocean_context066,participants,relations(c,participants),book.memory,{"startSecond":float(c.state.day)*45.0,"dt":dt,"watchDue":watch,"decisionOwnerIds":decisions})
	if not stepped.get("ok",false):return stepped
	var accepted=stepped.get("acceptedSeconds")
	if not _finite(accepted,0.0) or float(accepted)>dt:return _fail("Ocean travel refused an invalid accepted interval.")
	for move in stepped.locations:
		if not book.contact.is_empty() and str(move.ownerId)==str(book.contact.ownerId):book.contact["location"]=move.location.duplicate(true)
		elif not staged_route.is_empty() and str(move.ownerId)==str(staged_route.get("ownerId","")):shipping.model.route["location"]=move.location.duplicate(true)
	book["memory"]=stepped.memory
	stepped["book"]=book
	stepped["shipping068"]=shipping
	stepped["watchDue"]=watch
	return stepped

static func commit(c,staged: Dictionary) -> void:
	c.state["ocean066"]=staged.book
	if staged.has("shipping068"):c.ShippingFlow068.commit(c,staged.shipping068)
	for move in staged.locations:
		if str(move.ownerId)=="player" and not c.home_local064():c._publish_location064(move.location)
	var contact: Dictionary=staged.book.contact
	if not contact.is_empty() and contact.phase!="supply":
		var owner: Dictionary=_owner(c.state)
		owner["atPort"]="";owner.erase("harborServiceUntilDay")
	c.ocean_watch066=(0.0 if staged.watchDue else c.ocean_watch066)+float(staged.acceptedSeconds)
	c.ocean_conditions066=staged.conditions.duplicate(true)

static func _admit(c) -> void:
	if _published_corridor(c.state).is_empty():
		_try_admit(c,_owner(c.state,OWNER))
		return
	var candidates: Array=c.state.get("fleetOwners",[]).filter(func(o):return o is Dictionary and str(o.get("kind",""))=="raider" and not Orders.is_story_owner(o))
	candidates.sort_custom(func(a,b):
		var left: int=maxi(0,int(a.get("coins",0))-int(a.get("wageArrears",0)))
		var right: int=maxi(0,int(b.get("coins",0))-int(b.get("wageArrears",0)))
		return left>right if left!=right else str(a.get("id",""))<str(b.get("id","")))
	for owner in candidates:
		if _try_admit(c,owner):return

static func _try_admit(c,owner: Dictionary) -> bool:
	if not c.state.get("ocean066",{}).get("contact",{}).is_empty():return false
	var id: String=str(owner.get("id",""))
	var patrol: Dictionary=_patrol(c.state,id)
	if owner.is_empty() or id.is_empty() or patrol.is_empty() or not owner.get("active",false) or owner.get("kind","")!="raider" or Orders.is_story_owner(owner) or owner.get("playerCompany",false) or Orders.enrolled066(c.state,id) or not Orders.RegionalOrders.operation(c.state,owner).is_empty():return false
	var home: Dictionary=c.port(str(owner.get("homePort","")))
	if home.is_empty() or str(home.get("regionId","shatter_coast"))!="shatter_coast" or str(owner.get("atPort",""))!=str(home.id) or not patrol.get("active",false) or patrol.get("hidden",false) or not patrol.get("holding",false) or patrol.has("interceptPoint") or c.distance(patrol,home)>=40.0:return false
	# Reject damaged or undercrewed fleets before provisioning can spend anything.
	var snapshot: Dictionary=owner.duplicate(true)
	var performance: Dictionary=Orders.fleet_performance(snapshot)
	if not performance.get("seaworthy",false) or not Orders.needs_home_recovery(snapshot,Orders.fleet_reserves(snapshot),performance).is_empty():return false
	# Do not detach hulls from a funded yard collection that is already underway.
	for port in c.state.ports:
		for order in port.get("buildQueue",[]):
			if str(order.get("npcOwnerId",""))==id:return false
	var speed: float=float(performance.speed)*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0))
	if speed<=0.0:return false
	var best: Dictionary={}
	var best_days: float=INF
	for approach_id in ["north","south"]:
		var gate: Dictionary={"regionId":"shatter_coast","approachId":approach_id}
		var location: Dictionary={"world064":{"schema":1,"layer":"home","regionId":"shatter_coast"},"position":{"x":float(patrol.x),"y":float(patrol.y)},"heading":0.0,"path":[],"destination":""}
		# Validate HOME context/water; its immutable nav is shared with Campaign.
		var prepared: Dictionary=World.prepare(location,c.ocean_context064,clearance(owner))
		if not prepared.get("ok",false):continue
		var path: Array=c.cached_path(location.position,_gate(c,gate,false),clearance(owner))
		if path.size()<2:continue
		path.pop_front()
		var length: float=0.0
		var previous: Dictionary=location.position
		for point in path:length+=c.distance(previous,point);previous=point
		var ocean_seconds: float=1600.0/0.25/speed
		var points: Dictionary=_corridor_points(c.state,c.ocean_context064)
		if not points.is_empty():
			var entered: Dictionary=_gate(c,gate,true)
			ocean_seconds=_ocean_seconds075(c,entered,[points.originOcean,points.remoteOcean,points.originOcean,entered],speed)
		var days: float=(2.0*length/speed+ocean_seconds)/45.0+1.0
		if days<best_days:best_days=days;best={"gate":gate,"location":location}
	if best.is_empty():return false
	var costs: Dictionary=Fleets.upkeep(owner)
	var food: int=maxi(0,ceili(float(costs.food)*best_days-float(owner.cargo.get("food",0))))
	var bill: int=food*c.Economy.price(home,"food","buy")
	var advance: int=maxi(0,bill-int(owner.get("crewPurse",0)))
	if float(owner.get("coins",0))<ceilf(float(costs.wages)*best_days)+advance:return false
	if float(owner.get("cargo",{}).get("food",0))+food>Fleets._capacity(owner):return false
	if advance>0 and not Money.move(owner,"coins",owner,"crewPurse",advance,"Ocean patrol ration advance",c.state.moneyLog):return false
	if food>0:Fleets._purchase(owner,home,"food",food,true,false,c)
	var reserve: Dictionary=Orders.fleet_reserves(owner.duplicate(true))
	if float(reserve.get("foodDays",0))<best_days or float(reserve.get("wageDays",0))<best_days:return false
	if float(reserve.get("fuel",0))<float(costs.fuel)*best_days:return false
	if not Orders.fleet_performance(owner.duplicate(true)).get("seaworthy",false):return false
	var gate_point: Dictionary=_gate(c,best.gate,true)
	var corridor_now: Dictionary=_corridor_points(c.state,c.ocean_context064)
	var waypoint: Dictionary=corridor_now.remoteOcean.duplicate(true) if not corridor_now.is_empty() else {"x":gate_point.x+80.0,"y":gate_point.y}
	owner["harborServiceUntilDay"]=maxf(float(c.state.day)+0.25,float(owner.get("harborServiceUntilDay",0)))
	c.state.ocean066["contact"]={"ownerId":id,"phase":"supply","location":best.location,"gate":best.gate,"waypoint":waypoint}
	patrol["active"]=false;patrol["hidden"]=true;patrol["holding"]=true;patrol["course"]=[];patrol["courseLength"]=0.0;patrol["progress"]=0.0
	patrol.erase("interceptPoint")
	if corridor_now.is_empty():c.log_entry("Reef raiders are provisioning a short ocean patrol from %s using their existing boats, purse and purchased rations."%str(home.name))
	else:c.log_entry("Reef raiders are provisioning a funded run from %s toward %s and %s on their existing boats, purse and purchased rations."%[str(home.name),_port_label(c.state,str(corridor_now.corridor.originId)),_port_label(c.state,str(corridor_now.corridor.remoteId))])
	return true

static func record_losses(c) -> void:
	var contact: Dictionary=c.state.get("ocean066",{}).get("contact",{})
	if contact.is_empty():return
	var owner: Dictionary=_owner(c.state)
	var pending: Array=owner.get("boats",[]).filter(func(b):return b.get("sunk",false) and not b.get("wreckRecorded",false))
	var remaining: int=pending.size()
	var living: int=Orders.living_boats(owner).size()
	for boat in pending:
		var records: Array=c.Salvage.record_battle(c,{"ships":[boat],"chartPosition":contact.location.position,"world064":contact.location.world064},"ocean-npc:"+str(boat.uid))
		if records.is_empty():continue
		var wreck: Dictionary=c.Salvage.find_wreck(c.state,str(records[0].id))
		for good in owner.cargo:
			var lost: float=float(owner.cargo[good])/maxi(1,living+remaining)
			owner.cargo[good]=maxf(0.0,float(owner.cargo[good])-lost)
			wreck.stores[good]=float(wreck.stores.get(good,0))+lost*0.5
			if str(owner.get("tradeGood",""))==str(good):owner["tradeCargo"]=maxf(0.0,float(owner.get("tradeCargo",0))-lost)
		boat["wreckRecorded"]=true;remaining-=1
	if Orders.living_boats(owner).is_empty():
		contact["phase"]="lost";contact.location["path"]=[];contact.location["destination"]=""
		owner["active"]=false;owner["atPort"]="";owner.erase("harborServiceUntilDay")
		_resolve_memory(c.state.ocean066.memory,str(contact.ownerId))

static func _resolve_memory(memory: Dictionary,owner_id: String) -> void:
	for id in memory.pursuits.keys():
		if str(id)==owner_id or str(memory.pursuits[id].get("targetId",""))==owner_id:memory.pursuits.erase(id)

static func after_step(c,watch_due: bool=false) -> void:
	record_losses(c)
	var contact: Dictionary=c.state.ocean066.contact
	if contact.is_empty():
		if watch_due:_admit(c)
		return
	if contact.phase!="return" or contact.location.world064.layer!="home" or not contact.location.path.is_empty():return
	var owner: Dictionary=_owner(c.state)
	var home: Dictionary=c.port(str(owner.homePort))
	if c.distance(contact.location.position,home)>=40.0:return
	var patrol: Dictionary=_patrol(c.state)
	patrol["x"]=float(contact.location.position.x);patrol["y"]=float(contact.location.position.y)
	patrol["from"]=str(home.id);patrol["to"]=str(home.id);patrol["active"]=bool(owner.active);patrol["holding"]=true;patrol["progress"]=0.0;patrol["course"]=[];patrol["courseLength"]=0.0
	patrol.erase("hidden");patrol.erase("interceptPoint")
	_resolve_memory(c.state.ocean066.memory,str(contact.ownerId))
	c.state.ocean066.memory.intents.erase(str(contact.ownerId))
	c.state.ocean066["contact"]={}
	owner["atPort"]=str(home.id);owner["progress"]=0.0
	Fleets.dock(owner,home,c);c.NavalLifecycle.hire(c,owner,home)
	owner["harborServiceUntilDay"]=float(c.state.day)+0.25
	c.NavalLifecycle.route(c,patrol,c.NavalAI.arrived(c,owner,home))
	c.log_entry("The same raider fleet returned through its home approach for paid harbor service.")

static func action(c,id: String,kind: String) -> Dictionary:
	if kind not in ["investigate","avoid","resume"]:return _fail("Choose a physical ocean travel action.")
	if not c.travel_lock064.is_empty():return _fail(c.travel_lock064)
	var participants: Array=actors(c,c.state.get("ocean066",empty_book()))
	if kind!="resume" and (id=="player" or not participants.any(func(a):return str(a.ownerId)==id)):return _fail("This contact is no longer present on the ocean chart.")
	var requested: Dictionary={"kind":kind}
	if kind!="resume":requested["targetId"]=id
	var result: Dictionary=Travel.command(c.ocean_context066,participants[0],c.state.ocean066.memory,requested,float(c.state.day)*45.0)
	if not result.get("ok",false):return result
	c._publish_location064(result.location)
	c.state.ocean066["memory"]=result.memory
	return {"ok":true,"message":"Course resumed." if kind=="resume" else "Physical avoidance course set." if kind=="avoid" else "Course set for the dated sighting."}

static func diverted(c,target: Dictionary,destination: String) -> Dictionary:
	var player: Dictionary=actors(c,c.state.get("ocean066",empty_book()))[0]
	var memory: Dictionary=c.state.ocean066.memory.duplicate(true)
	var prior: Dictionary=memory.intents.get("player",{})
	# A new chart has no active prior course. Preserve dated intel/pursuit, not a
	# stale completed course as the original goal of every later ocean diversion.
	if not prior.is_empty() and not Travel.same_world(prior.get("goal",{}).get("world064"),player.location.world064):memory.intents.erase("player")
	var result: Dictionary=Travel.command(c.ocean_context066,player,memory,{"kind":"divert","target":target,"destination":destination},float(c.state.day)*45.0)
	if result.get("ok",false) and player.location.path.is_empty() and memory.intents.get("player",{}).get("returnGoal",{}).is_empty():result.memory.intents.player["kind"]="route"
	return result

static func blocker(c) -> String:
	if c.ocean_context066.is_empty():return ""
	var participants: Array=actors(c,c.state.get("ocean066",empty_book()))
	var pending: bool=c.events.any(func(e):return str(e.get("kind","")) in ["encounter","ocean_encounter066","defeat"])
	return Travel.transition_blocker(participants,relations(c,participants),c.state.get("ocean066",empty_book()).memory,pending)

static func encounter(c,id: String,settlement: Dictionary={}) -> Dictionary:
	var book: Dictionary=c.state.get("ocean066",empty_book())
	var contact: Dictionary=_physical_contact(c,id)
	if c.home_local064() or contact.is_empty() or str(contact.ownerId)!=id or contact.phase=="lost":return _fail("This is not an enrolled offshore contact.")
	if not c.state.get("world064",{}).is_empty() and not Travel.same_world(c.state.world064,contact.location.world064):return _fail("This contact belongs to another chart.")
	var owner: Dictionary=_owner(c.state,id)
	if not owner.get("active",false) or Orders.living_boats(owner).is_empty():return _fail("This contact has no surviving physical fleet.")
	var scale: float=10.0 if c.state.world064.layer=="ocean" else 1.0
	if c.distance(c.state.position,contact.location.position)*scale>75.0001:return _fail("Approach within actual interception range first.")
	var seen: Dictionary=book.memory.sightings.get("player",{}).get(id,{})
	if seen.is_empty() or not Travel.same_world(seen.world064,c.state.world064) or float(c.state.day)*45.0-float(seen.seenSecond)>1.5:return _fail("A fresh physical sighting is needed to engage.")
	if not settlement.is_empty():
		if not Travel.same_world(settlement.get("world064"),c.state.world064) or settlement.get("encounterPosition")!=c.state.position:return _fail("The offshore encounter provenance changed.")
	return {"ok":true,"message":"Physical offshore contact validated.","context":{"kind":"ocean066","id":id,"ownerId":id,"world064":c.state.world064.duplicate(true),"encounterPosition":c.state.position.duplicate(true),"name":"Offshore interception"}}

static func settlement_error(c,context: Dictionary,battle: Dictionary) -> String:
	var id: String=str(context.get("ownerId",""))
	var contact: Dictionary=_physical_contact(c,id)
	if battle.is_empty() or contact.is_empty() or str(contact.ownerId)!=id:return "Offshore settlement needs the enrolled physical owner."
	if not Travel.same_world(context.get("world064"),c.state.get("world064")) or not Travel.same_world(battle.get("world064"),context.get("world064")) or context.get("encounterPosition")!=c.state.position or battle.get("chartPosition")!=context.get("encounterPosition"):return "Offshore battle position or world provenance changed."
	if not context.get("ownerUids066") is Array or context.ownerUids066.is_empty():return "Offshore settlement needs its original boat UIDs."
	var seen: Dictionary={}
	for uid in context.ownerUids066:
		if not uid is String or uid.is_empty() or seen.has(uid):return "Offshore battle has invalid original boat UIDs."
		if not _owner(c.state,id).get("boats",[]).any(func(b):return str(b.get("uid",""))==uid):return "Offshore battle lost its original owner custody before reconciliation."
		seen[uid]=true
	return ""

static func settled(c,battle: Dictionary,context: Dictionary,wrecks: Array) -> void:
	if str(context.get("kind",""))!="ocean066" or battle.get("oceanCargoSettled066",false):return
	var id: String=str(context.get("ownerId",""))
	var owner: Dictionary=_owner(c.state,id)
	var lost: Array=[]
	var prizes: Array=[]
	for wreck in wrecks:
		if str(wreck.get("uid","")) in context.get("ownerUids066",[]):lost.append(wreck)
	for prize in c.state.get("fleet",[])+c.state.get("boardingPrizes",[]):
		if str(prize.get("uid","")) in context.get("ownerUids066",[]) and prize.get("captureSecured",false) and not prize.get("sunk",false):prizes.append(prize)
	var total: int=maxi(1,context.get("ownerUids066",[]).size())
	for good in owner.get("cargo",{}):
		var per_hull: float=float(owner.cargo[good])/total
		var quantity: float=per_hull*float(lost.size()+prizes.size())
		owner.cargo[good]=maxf(0.0,float(owner.cargo[good])-quantity)
		if str(owner.get("tradeGood",""))==str(good):owner["tradeCargo"]=maxf(0.0,float(owner.get("tradeCargo",0))-quantity)
		for wreck in lost:
			var live: Dictionary=c.Salvage.find_wreck(c.state,str(wreck.id))
			live.stores[good]=float(live.stores.get(good,0))+per_hull*0.5
		for prize in prizes:
			if not prize.get("convoyCargo") is Dictionary:prize["convoyCargo"]={}
			prize.convoyCargo[good]=float(prize.convoyCargo.get(good,0))+per_hull
	battle["oceanCargoSettled066"]=true
	if id==str(c.state.ocean066.contact.get("ownerId","")):
		_resolve_memory(c.state.ocean066.memory,id)
		if not c.state.ocean066.contact.is_empty():c.state.ocean066.contact["phase"]="return"
		record_losses(c)
	else:
		c.ShippingFlow068._forget_pursuits(c,id)
		c.ShippingFlow068.record_losses(c)

static func view(c) -> Dictionary:
	var output: Dictionary={"zones":[],"conditions":c.ocean_conditions066.duplicate(true),"forecast":{},"contacts":[],"travel066":{"mode":"route","contactId":"","resumeDestination":"","resumePath":[],"activeZoneSummary":"Clear water"}}
	if c.state.is_empty() or c.ocean_context066.is_empty():return output
	var now: float=float(c.state.day)*45.0
	output["zones"]=Travel.zone_view(c.ocean_context066,now)
	var condition: Dictionary=Travel.conditions(c.ocean_context066,c.world_location064(),now)
	if condition.get("ok",false):
		output.travel066["activeZoneSummary"]=str(condition.condition.label)
		output["forecast"]={"conditions":[condition.condition.duplicate(true)],"validUntilSecond":float(condition.condition.validUntilSecond),"assumptions":["Weather phases may change after this forecast; route preparation keeps a separate conservative allowance."]}
	var memory: Dictionary=c.state.get("ocean066",empty_book()).memory
	var intent: Dictionary=memory.intents.get("player",{})
	output.travel066["mode"]=str(intent.get("kind","route"));output.travel066["contactId"]=str(intent.get("targetId",""))
	var original: Dictionary=intent.get("returnGoal",{})
	if not original.is_empty():
		output.travel066["resumeDestination"]=str(original.get("destination",""))
		if Travel.same_world(original.get("world064"),c.state.get("world064")):output.travel066["resumePath"]=[original.target.duplicate(true)]
	var contact: Dictionary=c.state.get("ocean066",empty_book()).contact
	if contact.is_empty() or contact.phase=="lost":return output
	var id: String=str(contact.ownerId)
	var seen: Dictionary=memory.sightings.get("player",{}).get(id,{})
	if seen.is_empty() or float(seen.expiresSecond)<=now or not Travel.same_world(seen.world064,c.state.get("world064")):return output
	var owner: Dictionary=_owner(c.state)
	var age: float=maxf(0.0,now-float(seen.seenSecond))
	var current: bool=age<=1.5
	var observed=seen.get("intention075",{})
	var label: String="Dated sighting; investigate or avoid"
	if observed is Dictionary and not str(observed.get("reason","")).is_empty():label=str(observed.reason)
	output.contacts.append({"id":id,"ownerId":id,"name":str(owner.get("name","Reef raiders")),"faction":str(owner.get("faction","raiders")),"role":str(owner.get("kind","raider")),"hostile":bool(c.Politics.hostile(c,owner)),"visibility":"visible" if current else "last_known","world064":seen.world064.duplicate(true),"position":seen.position.duplicate(true),"heading":float(seen.heading),"uncertaintyRadius":0.0 if current else minf(1800.0,age*120.0),"ageSeconds":age,"sightedDay":float(seen.seenSecond)/45.0,"intentLabel":label,"provenance":"Existing fleet %s; paid departure from %s"%[id,str(owner.get("homePort",""))],"boats":seen.boats.duplicate(true)})
	return output
