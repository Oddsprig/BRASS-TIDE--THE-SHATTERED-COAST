extends RefCounted
## Plans only: existing actors, real water routes and owned operating reserves.
## This leaf must not preload NavalOrders/RegionalRules (both depend on it).
const Factions=preload("res://scripts/factions.gd")
const Fleets=preload("res://scripts/fleet_economy.gd")
const Damage=preload("res://scripts/damage.gd")
const Navigation=preload("res://scripts/navigation.gd")
const LOCAL_RANGE: float=1800.0
const CORRIDOR_RANGE: float=300.0

static func watch_state(op: Dictionary) -> String:
	var saved: String=str(op.get("watchState",""))
	if saved in ["active","awaiting","withdrawn"]:return saved
	match str(op.get("status","")):
		"active":return "active"
		"complete":return "awaiting"
	return "withdrawn"

static func assigned(op: Dictionary) -> bool:
	return str(op.get("status","")) in ["active","complete"] and watch_state(op)=="active"

static func operation(s: Dictionary,owner: Dictionary) -> Dictionary:
	var op: Dictionary=s.get("regionalCampaigns",{}).get("operations",{}).get("corridor",{})
	return op if assigned(op) and op.get("ownerId","")==owner.get("id","") and op.get("ends",[]).size()==2 else {}

static func arrival(s: Dictionary,owner: Dictionary,p: Dictionary) -> void:
	var op: Dictionary=operation(s,owner)
	if op.is_empty() or not str(p.get("id","")) in op.ends:return
	if str(p.id)!=str(op.get("patrolLastPort","")):
		op.patrolVisits=int(op.get("patrolVisits",0))+1
		op.patrolLastPort=str(p.id)

static func plan(s: Dictionary,owner: Dictionary,current: String,context: Dictionary={}) -> Dictionary:
	var op: Dictionary=operation(s,owner)
	if op.is_empty() or owner.get("kind","")!="patrol" or _protected(owner):return {}
	# Legacy AI calls have no navigation object. The live adapter requotes before
	# movement; never substitute a straight-line distance for a missing sea route.
	if context.is_empty():
		if op.get("currentPlan") is Dictionary and not op.currentPlan.is_empty():return op.currentPlan.duplicate(true)
		return {"ownerId":str(owner.id),"completionId":str(op.completionId),"purpose":"resupply","destination":current if current!="" else str(owner.homePort),"targetOwnerId":"","convoyOwnerId":"","ready":false,"hold":true,"reason":"Corridor watch awaits its live route and return-reserve quote.","readiness":{}}
	var from: String=current if current!="" else str(op.get("patrolLastPort",owner.get("homePort","")))
	var dest: String=str(op.ends[1]) if from==str(op.ends[0]) else str(op.ends[0])
	var convoy: Dictionary=_convoy(s,owner,op)
	var hostile: Dictionary=_hostile(s,owner,op,convoy)
	var purpose: String="patrol"
	var target: Dictionary={}
	var intercept_point: Dictionary={}
	var objective: String="Patrol the actual corridor endpoints."
	if not hostile.is_empty():
		purpose="intercept";target=hostile
		var sighting: Dictionary=_patrol(s,str(hostile.id))
		intercept_point={"x":float(sighting.x),"y":float(sighting.y)}
		objective="Intercept nearby hostile %s%s."%[str(hostile.get("name",hostile.id))," threatening "+str(convoy.get("name",convoy.id)) if not convoy.is_empty() else " on the corridor"]
	elif not convoy.is_empty():
		purpose="escort";target=convoy
		objective="Screen loaded friendly convoy %s (%.1f %s)."%[str(convoy.get("name",convoy.id)),_load(convoy),str(convoy.get("tradeGood","cargo"))]
	if purpose=="escort":dest=str(_patrol(s,str(target.id)).get("to",dest))
	var route_context: Dictionary=context.duplicate(false)
	if not intercept_point.is_empty():route_context.interceptPoint=intercept_point
	var quote: Dictionary=readiness(s,owner,dest,route_context)
	var target_id: String=str(target.get("id",""))
	var reason: String="Regional corridor watch: "+objective
	if not bool(quote.ready):
		purpose="resupply";target_id=""
		intercept_point={}
		dest=current if current!="" else str(owner.get("homePort",""))
		reason+=" Stalled: "+str(quote.reason)
	else:
		reason+=" Route and return reserves ready (%.2f days)."%float(quote.days)
	return {"ownerId":str(owner.id),"completionId":str(op.completionId),"purpose":purpose,"destination":dest,"targetOwnerId":target_id,"convoyOwnerId":str(convoy.get("id","")),"interceptPoint":intercept_point,"ready":bool(quote.ready),"hold":not bool(quote.ready) and (current!="" or not bool(quote.get("canReturn",false))),"objective":objective,"reason":reason,"readiness":quote}

static func readiness(s: Dictionary,owner: Dictionary,destination: String,context: Dictionary={}) -> Dictionary:
	var r: Dictionary={"ready":false,"reason":"","shortage":"","routeDistance":0.0,"returnDistance":0.0,"days":0.0,"returnDays":0.0,"speed":0.0,"clearance":10.0,"fuelNeed":0.0,"fuel":0.0,"foodNeed":0.0,"food":0.0,"payrollNeed":0,"coins":maxi(0,int(owner.get("coins",0))),"ammoNeed":0.0,"ammo":0.0,"engineMin":1.0,"moduleOk":true,"canReturn":false}
	var boats: Array=[]
	var first: String=""
	var shortage: String=""
	var morale: float=clampf(float(owner.get("performanceFactor",float(owner.get("morale",85.0))/85.0)),0.35,1.0)
	var speed: float=170.0
	for b in owner.get("boats",[]):
		if bool(b.get("sunk",false)):continue
		boats.append(b)
		r.clearance=maxf(float(r.clearance),Navigation.hull_clearance(b.get("spec",{}).get("size",10.0)))
		r.fuel+=maxf(0.0,float(b.get("fuel",0.0)))
		r.ammo+=maxf(0.0,float(b.get("ammo",0.0)))
		var status: Dictionary=Damage.get_status(b)
		var engine: float=minf(float(b.get("engine",1.0)),float(status.get("engineFactor",0.0)))
		r.engineMin=minf(float(r.engineMin),engine)
		var modules: bool=bool(status.get("equipmentOk",false)) and engine>=0.68
		if str(status.get("equipmentMode",""))=="canonical":
			var armed: bool=false
			for factor in status.get("weaponFactors",{}).values():
				if float(factor)>0.0:armed=true
			modules=modules and armed and (float(b.get("spec",{}).get("pumps",0.0))<=0.0 or float(status.get("pumpFactor",0.0))>0.0)
		r.moduleOk=bool(r.moduleOk) and modules
		var base: float=float(b.get("economyBaseSpeed",b.get("spec",{}).get("speed",90.0)))
		speed=minf(speed,base*morale*maxf(0.25,float(status.get("speedFactor",1.0))))
		if first!="":continue
		var name: String=str(b.get("name","Hull"))
		if float(b.get("crew",0.0))-float(b.get("wounded",0.0))<float(b.get("crewMin",1.0)):
			first=name+" needs its real minimum able crew; paid recruitment or treatment is required.";shortage="crew"
		elif not modules:
			first=name+" needs paid engine or installed-module service.";shortage="machinery"
		elif float(b.get("hp",0.0))<float(b.get("maxHp",1.0))*0.65 or Damage.sum_areas(b)>0.1 or float(b.get("fire",0.0))>1.0 or float(b.get("water",0.0))>float(b.get("capacity",200.0))*0.2:
			first=name+" needs paid hull repair or flooding control.";shortage="repair"
	if first=="" and boats.size()<maxi(1,int(owner.get("targetBoats",1))):
		first="Patrol below its existing hull strength; a funded purchase or commission is required.";shortage="replacement"
	if boats.is_empty():r.engineMin=0.0;r.moduleOk=false
	r.speed=speed if not boats.is_empty() else 0.0
	var costs: Dictionary=Fleets.upkeep(owner)
	var cargo: Dictionary=owner.get("cargo",{})
	r.food=maxf(0.0,float(cargo.get("food",0.0))-(float(owner.get("tradeCargo",0.0)) if owner.get("tradeGood","")=="food" else 0.0))
	r.ammoNeed=boats.size()*18.0 # Existing NavalOrders recovery threshold, in working guns.
	var nav: Dictionary=context.get("nav",{})
	if nav.is_empty():return _short(r,"route","No live water route is available for a route-and-return quote.")
	var actor: Dictionary=_patrol(s,str(owner.get("id","")))
	var end: Dictionary=_port(s,destination)
	var home: Dictionary=_port(s,str(owner.get("homePort","")))
	if actor.is_empty() or end.is_empty() or home.is_empty():return _short(r,"route","Patrol, destination or return harbor is no longer present.")
	var intercept: Dictionary=context.get("interceptPoint",{})
	if (intercept.is_empty() and _enemy(s,owner,end)) or _enemy(s,owner,home):return _short(r,"route","The outbound or return harbor is hostile; no legal resupply approach.")
	# An interception ends at the live hostile's current sea position. It is
	# neither an enemy-port service visit nor a patrol endpoint arrival.
	var end_point: Dictionary=Navigation.harbor_approach(nav,end,float(r.clearance),40.0) if intercept.is_empty() else intercept
	var home_point: Dictionary=Navigation.harbor_approach(nav,home,float(r.clearance),40.0)
	if end_point.is_empty() or home_point.is_empty():return _short(r,"route","No safe outbound or return harbor approach for the patrol's actual hull clearance.")
	var outbound: Array=Navigation.find_path(nav,actor,end_point,float(r.clearance))
	if outbound.is_empty():return _short(r,"route","No safe outbound water route for the patrol's actual hull clearance.")
	var returning: Array=Navigation.find_path(nav,end_point,home_point,float(r.clearance))
	var direct_home: Array=Navigation.find_path(nav,actor,home_point,float(r.clearance))
	if returning.is_empty():return _short(r,"route","No safe water route back to the home harbor.")
	r.routeDistance=_length(outbound);r.returnDistance=_length(returning)
	var per_day: float=maxf(0.01,float(r.speed)*0.38*float(context.get("scale",1.0))*float(context.get("daySeconds",45.0)))
	r.returnDays=float(r.returnDistance)/per_day
	r.days=(float(r.routeDistance)+float(r.returnDistance))/per_day
	# The existing NPC economy charges complete economic-day slices. Reserve
	# the next whole payroll/consumption slice even for a short coastal leg.
	r.reserveDays=maxi(1,ceili(float(r.days)))
	r.foodNeed=float(costs.food)*float(r.reserveDays)
	r.fuelNeed=0.0
	r.payrollNeed=maxi(0,int(owner.get("wageArrears",0)))+ceili(float(costs.wages)*float(r.reserveDays)+float(owner.get("wageRemainder",0.0)))
	# Loose fuel/ammo cannot power boats at sea. Existing paid dock transfers
	# them into working tanks/magazines; readiness never performs that transfer.
	var fuel_short: bool=false
	var ammo_short: bool=false
	var home_days: float=maxf(1.0,ceilf(_length(direct_home)/per_day)) if not direct_home.is_empty() else INF
	var can_return: bool=not direct_home.is_empty() and first==""
	for b in boats:
		var per_boat_day: float=float(Fleets.upkeep({"boats":[b]}).fuel)
		var need: float=per_boat_day*float(r.reserveDays)+0.6
		r.fuelNeed+=need
		if float(b.get("fuel",0.0))+0.000001<need:fuel_short=true
		if float(b.get("ammo",0.0))<18.0:ammo_short=true
		if float(b.get("fuel",0.0))+0.000001<per_boat_day*home_days:can_return=false
	r.canReturn=can_return
	if first!="":return _short(r,shortage,first)
	if fuel_short:return _short(r,"fuel","Working fuel %.2f / %.2f drums for the actual route, return and existing recovery reserve; buy fuel at dock."%[float(r.fuel),float(r.fuelNeed)])
	if float(r.food)+0.000001<float(r.foodNeed):return _short(r,"food","Crew food %.2f / %.2f lots for the route and return; sailors must buy provisions."%[float(r.food),float(r.foodNeed)])
	if int(r.coins)<int(r.payrollNeed):return _short(r,"payroll","Payroll reserve %d / %d coins including arrears for the route and return."%[int(r.coins),int(r.payrollNeed)])
	if ammo_short:return _short(r,"ammo","Working ammunition %.0f / %.0f rounds, with at least 18 per hull; buy cases at dock."%[float(r.ammo),float(r.ammoNeed)])
	r.ready=true;r.reason="Actual route, return, crew, machinery and paid operating reserves are ready."
	return r

static func _short(r: Dictionary,shortage: String,reason: String) -> Dictionary:
	r.ready=false;r.shortage=shortage;r.reason=reason
	return r

static func _length(path: Array) -> float:
	var distance: float=0.0
	for i in range(1,path.size()):distance+=_position(path[i-1]).distance_to(_position(path[i]))
	return distance

static func _position(p: Dictionary) -> Vector2:return Vector2(float(p.get("x",0.0)),float(p.get("y",0.0)))

static func _port(s: Dictionary,id: String) -> Dictionary:
	for p in s.get("ports",[]):
		if p.get("id","")==id:return p
	return {}

static func _patrol(s: Dictionary,id: String) -> Dictionary:
	for p in s.get("patrols",[]):
		if p.get("id","")==id:return p
	return {}

static func _protected(owner: Dictionary) -> bool:
	return str(owner.get("id","")).begins_with("story-") or bool(owner.get("playerCompany",false))

static func _live(s: Dictionary,owner: Dictionary) -> bool:
	if _protected(owner) or not bool(owner.get("active",false)):return false
	var living: bool=false
	for b in owner.get("boats",[]):
		if not bool(b.get("sunk",false)):living=true
	var p: Dictionary=_patrol(s,str(owner.get("id","")))
	return living and not p.is_empty() and bool(p.get("active",false)) and not _port(s,str(p.get("to",""))).is_empty()

static func _enemy(s: Dictionary,a: Dictionary,b: Dictionary) -> bool:
	var af: String=str(a.get("faction",""));var bf: String=str(b.get("faction",""))
	return af!="" and bf!="" and af!=bf and Factions.relation(s,af,bf)<=Factions.ENEMY_AT

static func _near(s: Dictionary,op: Dictionary,point: Dictionary) -> bool:
	var a: Dictionary=_port(s,str(op.ends[0]));var b: Dictionary=_port(s,str(op.ends[1]))
	if a.is_empty() or b.is_empty():return false
	var pos: Vector2=_position(point)
	return pos.distance_to(Geometry2D.get_closest_point_to_segment(pos,_position(a),_position(b)))<=CORRIDOR_RANGE

static func _load(owner: Dictionary) -> float:
	return maxf(0.0,minf(float(owner.get("tradeCargo",0.0)),float(owner.get("cargo",{}).get(str(owner.get("tradeGood","")),0.0))))

static func _convoy(s: Dictionary,owner: Dictionary,op: Dictionary) -> Dictionary:
	var best: Dictionary={}
	var distance: float=LOCAL_RANGE
	var own: Dictionary=_patrol(s,str(owner.id))
	for other in s.get("fleetOwners",[]):
		if other.get("kind","")!="trader" or not _live(s,other) or _enemy(s,owner,other) or _load(other)<=0.0:continue
		if other.get("faction","")!=owner.get("faction","") and Factions.relation(s,str(owner.get("faction","")),str(other.get("faction","")))<=0:continue
		var actor: Dictionary=_patrol(s,str(other.id))
		if bool(actor.get("holding",false)) or not _near(s,op,actor):continue
		if not str(actor.get("from","")) in op.ends or not str(actor.to) in op.ends or actor.get("from","")==actor.to:continue
		var d: float=_position(own).distance_to(_position(actor))
		if d<distance:best=other;distance=d
	return best

static func _hostile(s: Dictionary,owner: Dictionary,op: Dictionary,convoy: Dictionary) -> Dictionary:
	var best: Dictionary={}
	var distance: float=LOCAL_RANGE
	var own: Dictionary=_patrol(s,str(owner.id))
	for other in s.get("fleetOwners",[]):
		if not _live(s,other) or not _enemy(s,owner,other):continue
		var actor: Dictionary=_patrol(s,str(other.id))
		if not _near(s,op,actor):continue
		var d: float=_position(own).distance_to(_position(actor))
		if d>=distance:continue
		if not convoy.is_empty():
			var threatens: bool=str(other.get("order",{}).get("targetOwnerId",""))==str(convoy.id) or _position(actor).distance_to(_position(_patrol(s,str(convoy.id))))<=LOCAL_RANGE
			if not threatens:continue
		best=other;distance=d
	return best
