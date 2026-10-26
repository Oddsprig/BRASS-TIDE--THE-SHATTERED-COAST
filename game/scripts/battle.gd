extends RefCounted
## Pure fixed-step combat. State and RNG belong exclusively to the caller.
const BoardingCombat=preload("res://scripts/combat_boarding.gd")
const Objectives=preload("res://scripts/battle_objectives.gd")
const Refit=preload("res://scripts/refit.gd")
const WeaponGeometry=preload("res://scripts/weapon_geometry.gd")
const Damage=preload("res://scripts/damage.gd")
const Deployment=preload("res://scripts/deployment.gd")
const CombatEvents=preload("res://scripts/combat_events.gd")
const Tactical=preload("res://scripts/tactical_runtime.gd")
const Certification=preload("res://scripts/tactical_certification.gd")
const FireControl=preload("res://scripts/tactical_fire_control.gd")
const EquipmentCombat=preload("res://scripts/equipment_combat.gd")
const Routes=preload("res://scripts/tactical_routes.gd")
const WIDTH: float=2300.0
const HEIGHT: float=1700.0
const MAX_MOUNTS: int=16
const MAX_EVENTS: int=CombatEvents.MAX_EVENTS
const MAX_STEP_EVENTS: int=CombatEvents.MAX_STEP_EVENTS
const MAX_EFFECTS: int=CombatEvents.MAX_EFFECTS
const MAX_WRECKS: int=CombatEvents.MAX_WRECKS

static func _pos(s: Dictionary) -> Vector2:
	return Vector2(s.x,s.y)

static func _radius(s: Dictionary) -> float:
	return maxf(10.0,float(s.spec.get("size",16)))

static func _inside(point: Vector2, points: Array) -> bool:
	var yes: bool=false
	var j: int=points.size()-1
	for i in range(points.size()):
		var a: Array=points[i]
		var b: Array=points[j]
		if (a[1]>point.y)!=(b[1]>point.y) and point.x<(b[0]-a[0])*(point.y-a[1])/(b[1]-a[1])+a[0]:
			yes=not yes
		j=i
	return yes

static func _edge_distance(p: Vector2,a: Vector2,b: Vector2) -> float:
	var delta: Vector2=b-a
	var t: float=clampf((p-a).dot(delta)/maxf(0.00001,delta.length_squared()),0.0,1.0)
	return p.distance_to(a+delta*t)

static func _island_blocked(st: Dictionary, p: Vector2, r: float) -> bool:
	for island in st.islands:
		var points: Array=island.points
		if _inside(p,points):
			return true
		for i in range(points.size()):
			var a: Array=points[i]
			var b: Array=points[(i+1)%points.size()]
			if _edge_distance(p,Vector2(a[0],a[1]),Vector2(b[0],b[1]))<r:
				return true
	return false

static func _blocked(st: Dictionary, p: Vector2, r: float) -> bool:
	if p.x<r or p.x>WIDTH-r or p.y<r or p.y>HEIGHT-r:
		return true
	return _island_blocked(st,p,r)

static func _effect(st: Dictionary,p: Vector2,type: String,meta: Dictionary={}) -> void:
	CombatEvents.add_effect(st,p,type,meta)

static func pop_events(st: Dictionary) -> Array:
	return CombatEvents.pop_events(st)

static func mount_shot_time(s: Dictionary,mount_id_or_index) -> float:
	return CombatEvents.mount_shot_time(s,mount_id_or_index)

static func mount_shot_age(s: Dictionary,mount_id_or_index,now: float=NAN) -> float:
	return CombatEvents.mount_shot_age(s,mount_id_or_index,now)

static func hull_material(s: Dictionary) -> String:
	return CombatEvents.hull_material(s)

static func weapon_family(kind) -> String:
	return CombatEvents.weapon_family(kind)

static func _log(st: Dictionary,message: String) -> void:
	st.log.append(message)
	if st.log.size()>12:
		st.log.pop_front()

static func create(options: Dictionary) -> Dictionary:
	var random: RandomNumberGenerator=RandomNumberGenerator.new()
	random.seed=int(options.get("seed",1))
	var st: Dictionary={"ships":[],"projectiles":[],"effects":[],"wrecks":[],"events":[],"eventSeq":0,"droppedEvents":0,"_stepEvents":0,"_engineTracker":{},"_hitTracker":{},"time":0.0,"result":null,"playerId":null,"order":"engage","autopilot":true,"rng":random,"location":options.get("location",{"name":"Open water"}),"islands":[],"log":[],"retreatTimer":null,"reserves":{"player":[],"enemy":[]},"deployment":{"player":0,"enemy":0,"limit":Deployment.LIMIT}}
	st.mission=options.get("mission",{}).duplicate(true)
	Tactical.ensure(st)
	for island in options.get("islands",[]):
		var points: Array=island.get("points",[]) if island is Dictionary else island
		if points.size()>=3:
			var local: Dictionary=island.duplicate(true) if island is Dictionary else {}
			local.points=points.duplicate(true)
			st.islands.append(local)
	if not options.has("islands"):
		st.islands=[{"points":[[850,80],[1130,120],[1210,310],[1030,420],[820,300]]},{"points":[[1040,1320],[1240,1250],[1430,1450],[1320,1640],[1070,1580]]}]
	var fleet: Array=options.get("fleet",[])
	var enemy_fleet: Array=options.get("enemyFleet",[]).duplicate()
	if enemy_fleet.is_empty():
		for spec in options.get("enemySpecs",[]):
			enemy_fleet.append(Damage.create_ship(spec))
	var mission_error: String=Objectives.deployment_error(fleet,enemy_fleet,st.mission)
	if not mission_error.is_empty():
		st.startError=mission_error;st.result="lost";st.objectiveSuccess=false
		return st
	var player_split: Dictionary=Deployment.split(fleet)
	var enemy_split: Dictionary=Deployment.split(enemy_fleet)
	var spawns: Dictionary=_formation_positions(st,player_split.deployed,enemy_split.deployed)
	if spawns.has("error"):
		st.startError=spawns.error;st.result="lost";st.objectiveSuccess=false
		return st
	var reach: Dictionary={"left":64}
	if options.get("coastalEncounter",false) and not spawns.player.is_empty() and not spawns.enemy.is_empty():
		if not _reachable(st,spawns.player[0],spawns.enemy[0],float(spawns.clearance),reach):
			st.startError="No water route connects the opposing coastal formations for these hulls.";st.result="lost";st.objectiveSuccess=false
			return st
	if options.get("coastalEncounter",false) and Objectives.is_convoy(st):
		var exit: Dictionary=_coastal_exit(st,spawns,player_split.deployed,enemy_split.deployed,reach)
		if exit.is_empty():
			st.startError="No reachable water-safe convoy formation and far exit could be established for these hulls.";st.result="lost";st.objectiveSuccess=false
			return st
		st.mission.exit=exit
	st.reserves.player=player_split.reserve
	st.reserves.enemy=enemy_split.reserve
	st.deployment.player=player_split.points
	st.deployment.enemy=enemy_split.points
	for i in range(player_split.deployed.size()):
		_deploy(st,player_split.deployed[i],i,"player",spawns.player[i])
	for i in range(enemy_split.deployed.size()):
		_deploy(st,enemy_split.deployed[i],i,"enemy",spawns.enemy[i])
	Objectives.configure(st)
	for ship in st.ships:
		if ship.team=="player" and not ship.sunk and not str(ship.get("uid","")) in st.mission.get("allyUids",[]):
			st.playerId=ship.id
			ship.selected=true
			break
	return st

static func objective_snapshot(st: Dictionary) -> Dictionary:
	return Objectives.snapshot(st)

static func _deployment_spec(ship: Dictionary) -> Dictionary:
	# Match _deploy's fitting before deciding which actual hull will fit in water.
	if not EquipmentCombat.is_corrupt_owner(ship) and not ship.spec.get("weaponMounts") is Array:
		var loadout: Dictionary=ship.loadout if ship.get("loadout") is Dictionary else Refit.defaults(ship.spec)
		return Refit.effective_spec(ship.spec,loadout)
	return ship.spec

static func _formation_positions(st: Dictionary,players: Array,enemies: Array) -> Dictionary:
	var positions: Dictionary={"player":[],"enemy":[],"largest":10.0,"clearance":10.0}
	for ship in players+enemies:
		positions.clearance=maxf(float(positions.clearance),Routes.planning_radius({"spec":_deployment_spec(ship)}))
	var placed: Dictionary={"islands":st.islands,"ships":[]}
	for team in ["player","enemy"]:
		var fleet: Array=players if team=="player" else enemies
		for i in range(fleet.size()):
			var shape: Dictionary={"spec":_deployment_spec(fleet[i]),"sunk":false}
			var clearance: float=float(positions.clearance)
			var preferred: Vector2=Vector2((520.0 if team=="player" else 1600.0)+(i%2)*85.0,850.0+(floor(i/2.0)-(ceil(fleet.size()/2.0)-1.0)/2.0)*85.0)
			var spawn: Vector2=preferred if _spawn_clear(placed,shape,preferred,clearance) else Vector2(INF,INF)
			var best: float=INF
			if not spawn.is_finite():
				# Fixed, bounded samples in this side's formation area; never change coast.
				for k in range(176):
					var p: Vector2=Vector2((120.0 if team=="player" else 1280.0)+(k%11)*90.0,120.0+floor(k/11.0)*96.0)
					var distance: float=p.distance_squared_to(preferred)
					if distance<best and _spawn_clear(placed,shape,p,clearance):spawn=p;best=distance
			if not spawn.is_finite():return {"error":"No safe water formation for every deployed hull at this coast."}
			positions[team].append(spawn)
			positions.largest=maxf(float(positions.largest),_radius(shape))
			shape.x=spawn.x;shape.y=spawn.y;placed.ships.append(shape)
	return positions

static func _reachable(st: Dictionary,a: Vector2,b: Vector2,r: float,remaining: Dictionary) -> bool:
	# Whole encounter setup has at most 64 bounded queries, each using the existing
	# corner router and its normal 4096-clearance ceiling. Pending never means safe.
	if int(remaining.left)<=0:return false
	remaining.left-=1
	var budget: Dictionary={"fullRoutes":0,"cacheHits":0,"clearanceTests":0,"clearanceLimit":4096,"exhaustions":0}
	return Routes.route(st,Routes.terrain(st),a,b,r,budget).status=="valid"

static func _coastal_exit(st: Dictionary,spawns: Dictionary,players: Array,enemies: Array,reach: Dictionary) -> Dictionary:
	var exit: Dictionary=st.mission.get("exit",{}).duplicate(true)
	var right: bool=str(st.mission.get("carrierTeam","player" if st.mission.kind=="escort" else "enemy"))=="player"
	var fleet: Array=players if right else enemies
	var starts: Array=spawns.player if right else spawns.enemy
	var carriers: Array=Objectives.carrier_uids(st.mission)
	exit.radius=maxf(float(exit.get("radius",70.0)),float(spawns.largest)+24.0)
	if exit.radius>180.0:return {}
	var clearance: float=float(exit.radius)+float(spawns.largest)+4.0
	for column in range(3):
		var inset: float=maxf(120.0,clearance+4.0)+column*140.0
		for row in range(15):
			var offset: float=ceil(row/2.0)*96.0*(-1.0 if row%2 else 1.0)
			var p: Vector2=Vector2(WIDTH-inset if right else inset,float(exit.get("y",850.0))+offset)
			if _blocked(st,p,clearance):continue
			var separated: bool=true
			for i in range(fleet.size()):
				if str(fleet[i].get("uid","")) in carriers and starts[i].distance_to(p)<WIDTH*0.35:separated=false;break
			if not separated:continue
			var reachable: bool=true
			for i in range(fleet.size()):
				if not str(fleet[i].get("uid","")) in carriers:continue
				if not _reachable(st,starts[i],p,Routes.planning_radius({"spec":_deployment_spec(fleet[i])}),reach):reachable=false;break
			if int(reach.left)<=0 and not reachable:return {}
			if not reachable:continue
			exit.x=p.x;exit.y=p.y
			return exit
	return {}

static func _deploy(st: Dictionary,s: Dictionary,index: int,team: String,spawn: Vector2) -> void:
	var corrupt_equip: bool=EquipmentCombat.is_corrupt_owner(s)
	if not corrupt_equip and not s.spec.get("weaponMounts") is Array:
		if EquipmentCombat.is_canonical_owner(s) and not s.get("baseSpec") is Dictionary:
			s.baseSpec=s.spec.duplicate(true)
		if not s.get("loadout") is Dictionary:s.loadout=Refit.defaults(s.spec)
		s.spec=Refit.effective_spec(s.spec,s.loadout)
	s.supportRepairFactor=1.0
	s.localAimAngles={}
	s.team=team
	s.id="%s-%d-%s"%[team,index,s.type]
	s.x=spawn.x
	s.y=spawn.y
	s.angle=0.0 if team=="player" else PI
	s.turretAngle=s.angle
	s.vx=0.0
	s.vy=0.0
	if not corrupt_equip:
		s.armor=maxf(0.0,Damage.number(s.spec.get("armor"),Damage.number(s.get("armor"))))
	s.cooldown=0.0
	var base_mounts: Array=_base_mounts(s)
	var mounts: Array=EquipmentCombat.apply_mount_condition(s,base_mounts)
	s.weaponCooldowns=[]
	for mount in mounts:
		s.weaponCooldowns.append(0.0)
	CombatEvents.register_ship(st,s,mounts)
	s.selected=false
	s.order="engage"
	s.orderTarget={}
	s.orderRevision=0
	s.erase("boardingOrder") # A new arena never inherits an unlaunched approach.
	s.formationIndex=index
	s._wreckRecorded=false
	s.erase("battleEscaped")
	st.ships.append(s)
	Tactical.register(st,s,base_mounts)

static func _spawn_clear(st: Dictionary,s: Dictionary,p: Vector2,clearance: float=0.0) -> bool:
	if _blocked(st,p,maxf(_radius(s),clearance)):
		return false
	for other in st.ships:
		if not other.sunk and p.distance_to(_pos(other))<_radius(s)+_radius(other)+4.0:
			return false
	return true

static func get_flagship(st: Dictionary) -> Dictionary:
	for s in st.ships:
		if s.id==st.playerId and not s.sunk and not s.get("captureSecured",false):
			return s
	return {}

static func select_flagship(st: Dictionary,id) -> bool:
	for s in st.ships:
		if s.id==id and s.team=="player" and not s.sunk and not s.get("captureSecured",false):
			st.playerId=id
			for boat in st.ships:
				boat.selected=boat.id==id
			return true
	return false

static func set_autopilot(st: Dictionary,enabled: bool) -> bool:
	if bool(st.get("autopilot",true))!=enabled:Tactical.control_changed(st)
	st.autopilot=enabled
	return enabled

static func _ship_with_id(st: Dictionary,id: String) -> Dictionary:
	for s in st.ships:
		if str(s.id)==id and not s.sunk and not s.get("captureSecured",false):
			return s
	return {}

static func issue_order(st: Dictionary,ids: Array,order: String,target: Dictionary={}) -> bool:
	if st.result!=null or ids.is_empty() or order not in ["move","attack","escort","hold","engage","withdraw"]:
		return false
	var boats: Array=[]
	var seen: Dictionary={}
	for id in ids:
		if not (id is String or id is StringName):
			return false
		var boat: Dictionary=_ship_with_id(st,str(id))
		if boat.is_empty() or boat.team!="player":
			return false
		if not seen.has(str(id)):
			boats.append(boat)
			seen[str(id)]=true
	var clean: Dictionary={}
	if target.has("x") or target.has("y"):
		var x: float=Damage.number(target.get("x"),NAN)
		var y: float=Damage.number(target.get("y"),NAN)
		if not is_finite(x) or not is_finite(y):
			return false
		for boat in boats:
			if _blocked(st,Vector2(x,y),_radius(boat)):
				return false
		clean={"x":x,"y":y}
	if order=="move" and not clean.has("x"):
		return false
	if target.has("shipId"):
		if not (target.shipId is String or target.shipId is StringName):
			return false
		var target_id: String=str(target.shipId)
		if not target_id.is_empty():
			var other: Dictionary=_ship_with_id(st,target_id)
			if other.is_empty() or (order=="attack" and other.team!="enemy") or (order=="escort" and other.team!="player"):
				return false
			clean.shipId=target_id
	for boat in boats:
		Tactical.accept_command(st,boat,order,clean)
		if order=="hold" and not clean.has("x"):
			boat.orderTarget={"x":float(boat.x),"y":float(boat.y)}
	return true

static func set_tactical_options(st: Dictionary,ids: Array,options: Dictionary) -> bool:
	if options.get("rally") is Dictionary and not options.rally.is_empty():
		var x: float=Damage.number(options.rally.get("x"),NAN)
		var y: float=Damage.number(options.rally.get("y"),NAN)
		if not is_finite(x) or not is_finite(y):return false
		for id in ids:
			var ship: Dictionary=_ship_with_id(st,str(id))
			if ship.is_empty() or _blocked(st,Vector2(x,y),_radius(ship)+4.0):return false
	return Tactical.set_options(st,ids,options)

static func tactical_status(st: Dictionary,id: String) -> Dictionary:
	return Tactical.status(st,id)

static func set_order(st: Dictionary,order: String,target: Dictionary={}) -> String:
	var ids: Array=[]
	for s in st.ships:
		if s.team=="player" and not s.sunk and not s.get("captureSecured",false):
			ids.append(s.id)
	if issue_order(st,ids,order,target):
		st.order=order
	return st.order

static func retreat(st: Dictionary) -> void:
	if st.result!=null or st.retreatTimer!=null:
		return
	st.retreatTimer=12.0
	set_autopilot(st,true)
	set_order(st,"withdraw")
	_log(st,"Fleet withdrawal — 12 seconds")

static func _combat_mounts(st: Dictionary,s: Dictionary,frame_cache=null) -> Array:
	var t: Dictionary=Tactical.ensure(st)
	var id: String=str(s.id)
	var source=s.spec.get("weaponMounts",s.spec)
	if not t.mountCache.has(id) or t.mountCache[id].source!=source:Tactical.register(st,s,_base_mounts(s))
	return Tactical.refresh_mounts(st,s,frame_cache)

static func _mounts(s: Dictionary) -> Array:
	return EquipmentCombat.apply_mount_condition(s,_base_mounts(s))

static func _base_mounts(s: Dictionary) -> Array:
	var raw_mounts: Array=[]
	var legacy: bool=not (s.spec.get("weaponMounts") is Array)
	if legacy:
		raw_mounts=[{"id":"primary","kind":s.spec.get("weapon","gun"),"damage":s.spec.get("damage",10),"fireRate":s.spec.get("fireRate",1.0),"range":s.spec.get("range",400),"arc":TAU}]
	else:
		raw_mounts=s.spec.weaponMounts
	var mounts: Array=[]
	for raw in raw_mounts:
		if mounts.size()>=MAX_MOUNTS:
			break
		if not raw is Dictionary:
			continue
		var kind: String=str(raw.get("kind","gun"))
		if kind not in ["gun","cannon","rocket","torpedo"]:
			continue
		var speed: float=240.0 if kind=="torpedo" else (730.0 if kind=="rocket" else (620.0 if kind=="cannon" else 850.0))
		mounts.append({"id":str(raw.get("id","mount-%d"%mounts.size())),"moduleId":str(raw.get("moduleId","")),"size":int(clampf(Damage.number(raw.get("size"),1.0),1.0,4.0)),"kind":kind,"damage":clampf(Damage.number(raw.get("damage"),10.0),0.0,100000.0),"fireRate":clampf(Damage.number(raw.get("fireRate"),1.0),0.05,60.0),"range":clampf(Damage.number(raw.get("range"),400.0),1.0,5000.0),"speed":clampf(Damage.number(raw.get("speed"),speed),20.0,5000.0),"ammoCost":int(ceil(clampf(Damage.number(raw.get("ammoCost"),1.0),1.0,1000.0))),"x":clampf(Damage.number(raw.get("x")),-150.0,150.0),"y":clampf(Damage.number(raw.get("y")),-150.0,150.0),"arc":clampf(Damage.number(raw.get("arc"),TAU),0.01,TAU),"angle":wrapf(Damage.number(raw.get("angle")),-PI,PI),"legacy":legacy})
		var last: Dictionary=mounts[-1]
		last.muzzleDistance=WeaponGeometry.muzzle(kind,float(s.spec.get("size",16)),int(last.size))
		last.barrelHeight=WeaponGeometry.height(kind,float(s.spec.get("size",16)),int(last.size))
	return mounts

static func _sync_cooldowns(s: Dictionary,count: int) -> void:
	if not (s.get("weaponCooldowns") is Array):
		s.weaponCooldowns=[]
	while s.weaponCooldowns.size()<count:
		s.weaponCooldowns.append(0.0)
	if s.weaponCooldowns.size()>count:
		s.weaponCooldowns.resize(count)

static func _tick_cooldowns(s: Dictionary,dt: float,known_mounts: Array=[]) -> void:
	var mounts: Array=known_mounts if not known_mounts.is_empty() else _mounts(s)
	_sync_cooldowns(s,mounts.size())
	CombatEvents.sync_mount_shots(s,mounts)
	for i in range(s.weaponCooldowns.size()):
		s.weaponCooldowns[i]=maxf(0.0,Damage.number(s.weaponCooldowns[i])-dt)
	if not s.weaponCooldowns.is_empty():
		# Damage.tick_ship already advances this legacy timer once. Keep the
		# primary mount compatible with callers reading or setting cooldown.
		s.weaponCooldowns[0]=maxf(s.weaponCooldowns[0],Damage.number(s.cooldown))
		s.cooldown=s.weaponCooldowns[0]

static func _mount_origin(s: Dictionary,mount: Dictionary) -> Vector2:
	return _pos(s)+Vector2(mount.x,mount.y).rotated(s.angle)

static func _lead(s: Dictionary,mount: Dictionary,target: Dictionary) -> Vector2:
	var delta: Vector2=_pos(target)-_mount_origin(s,mount)
	var velocity: Vector2=Vector2(target.vx,target.vy)-Vector2(s.vx,s.vy)*0.2
	var speed: float=mount.speed
	var a: float=velocity.length_squared()-speed*speed
	var b: float=2.0*delta.dot(velocity)
	var c: float=delta.length_squared()
	var t: float=delta.length()/speed
	if absf(a)<0.00001:
		if absf(b)>0.00001 and -c/b>0.0:
			t=-c/b
	else:
		var discriminant: float=b*b-4.0*a*c
		if discriminant>=0.0:
			var root: float=sqrt(discriminant)
			var t1: float=(-b-root)/(2.0*a)
			var t2: float=(-b+root)/(2.0*a)
			if t1>0.0 and t2>0.0:
				t=minf(t1,t2)
			elif maxf(t1,t2)>0.0:
				t=maxf(t1,t2)
	return _pos(target)+velocity*clampf(t,0.0,mount.range/speed)

static func _clear_shot(st: Dictionary,start: Vector2,end: Vector2,radius: float=2.0) -> bool:
	if minf(start.x,end.x)<radius or maxf(start.x,end.x)>WIDTH-radius or minf(start.y,end.y)<radius or maxf(start.y,end.y)>HEIGHT-radius:
		return false
	for island in st.islands:
		var points: Array=island.points
		if _inside(start,points) or _inside(end,points):
			return false
		for i in range(points.size()):
			var a: Vector2=Vector2(points[i][0],points[i][1])
			var b: Vector2=Vector2(points[(i+1)%points.size()][0],points[(i+1)%points.size()][1])
			var delta: Vector2=end-start
			var edge: Vector2=b-a
			var denominator: float=delta.cross(edge)
			if absf(denominator)>0.000001:
				var along: float=(a-start).cross(edge)/denominator
				var across: float=(a-start).cross(delta)/denominator
				if along>=0.0 and along<=1.0 and across>=0.0 and across<=1.0:
					return false
			if minf(minf(_edge_distance(start,a,b),_edge_distance(end,a,b)),minf(_edge_distance(a,start,end),_edge_distance(b,start,end)))<radius:
				return false
	return true

static func _target_for_mount(st: Dictionary,s: Dictionary,mount: Dictionary,preferred: Dictionary) -> Dictionary:
	var origin: Vector2=_mount_origin(s,mount)
	var result: Dictionary={}
	var best: float=INF
	for candidate in st.ships:
		if candidate.sunk or candidate.team==s.team or candidate.get("captureSecured",false):continue
		var delta: Vector2=_lead(s,mount,candidate)-origin
		if delta.length()>mount.range:continue
		if absf(angle_difference(s.angle+mount.angle,delta.angle()))>mount.arc*0.5:continue
		if not _clear_shot(st,origin,_pos(candidate),3.0):continue
		if candidate==preferred:return candidate
		var score: float=delta.length_squared()
		if score<best:best=score;result=candidate
	return result

static func _fire(st: Dictionary,s: Dictionary,target: Vector2,target_ship: Dictionary={},automatic: bool=false,gates: Dictionary={},frame_cache=null) -> void:
	if s.sunk or s.get("captureSecured",false) or st.projectiles.size()>=400:
		return
	var mounts: Array=_combat_mounts(st,s,frame_cache)
	_sync_cooldowns(s,mounts.size())
	CombatEvents.sync_mount_shots(s,mounts)
	var status: Dictionary=Damage.get_status_cached(s,frame_cache)
	if not bool(status.get("equipmentOk",true)) or status.weaponFactor<=0.01:
		return
	for i in range(mounts.size()):
		var mount: Dictionary=mounts[i]
		var gate: Dictionary=gates.get(str(mount.id),{})
		if automatic and not gate.get("ok",false):continue
		if EquipmentCombat.mount_factor(s,mount,i,status,frame_cache)<=0.01 or float(mount.get("damage",0.0))<=0.0:
			continue
		if s.weaponCooldowns[i]>0.0 or (i==0 and s.cooldown>0.0) or s.ammo<mount.ammoCost or st.projectiles.size()>=400:
			continue
		var mount_target: Dictionary=gate.get("target",{}) if automatic else (_target_for_mount(st,s,mount,target_ship) if not target_ship.is_empty() else {})
		if not target_ship.is_empty() and mount_target.is_empty():continue
		var origin: Vector2=_mount_origin(s,mount)
		var aim: Vector2=gate.aim if automatic else (_lead(s,mount,mount_target) if not mount_target.is_empty() else target)
		var delta: Vector2=aim-origin
		if delta.length()>mount.range or delta.length()<0.001:
			continue
		var bearing: float=delta.angle()
		if absf(angle_difference(s.angle+mount.angle,bearing))>mount.arc*0.5+0.00001:
			continue
		var kind: String="bullet" if mount.kind=="gun" else ("shell" if mount.kind=="cannon" else mount.kind)
		var radius: float=FireControl.shot_radius(mount)
		var distance: float=float(mount.muzzleDistance)
		var muzzle: Vector2=origin+Vector2.from_angle(bearing)*distance
		if not automatic and (not _clear_shot(st,origin,aim,radius) or _blocked(st,muzzle,radius)):
			continue
		# One seeded scatter. This velocity is the segment that must be clear.
		var angle: float=bearing+(st.rng.randf()-0.5)*FireControl.dispersion(mount)
		var velocity: Vector2=Vector2.from_angle(angle)*mount.speed+Vector2(s.vx,s.vy)*0.2
		var lane: Dictionary=FireControl.actual_lane(st,s,mount,muzzle,velocity,radius)
		if not lane.ok:
			continue
		s.turretAngle=bearing
		if not s.get("localAimAngles") is Dictionary:s.localAimAngles={}
		s.localAimAngles[str(mount.id)]=angle_difference(float(s.angle),bearing)
		st.projectiles.append({"x":muzzle.x,"y":muzzle.y,"px":muzzle.x,"py":muzzle.y,"vx":velocity.x,"vy":velocity.y,"team":s.team,"damage":mount.damage*(1.8 if kind=="torpedo" else 1.0),"kind":kind,"family":mount.kind,"variant":CombatEvents.weapon_variant(mount.kind,mount),"moduleId":str(mount.get("moduleId","")),"size":int(mount.get("size",1)),"life":mount.range/mount.speed,"age":0.0,"owner":s.id,"sourceUid":str(s.get("uid",s.id)),"sourceHull":str(s.get("type",s.spec.get("id","boat"))),"mountId":mount.id,"mountIndex":i,"angle":angle,"radius":radius,"penetration":18.0 if kind=="torpedo" else (4.0 if kind=="shell" else 0.0),"blastRadius":36.0 if kind=="rocket" else 0.0,"incendiary":kind=="rocket","height":mount.barrelHeight,"trail":"foam" if kind=="torpedo" else ("smoke" if kind=="rocket" else "tracer")})
		s.ammo=maxf(0.0,s.ammo-mount.ammoCost)
		s.weaponCooldowns[i]=1.0/(mount.fireRate*maxf(0.15,status.weaponFactor))
		if i==0:
			s.cooldown=s.weaponCooldowns[0]
		var before_shot: float=mount_shot_time(s,str(mount.id))
		CombatEvents.emit_fire(st,s,mount,i,muzzle,angle,mount_target)
		if automatic:FireControl.emitted(st,s,mount,st.tactical.intents.get(str(s.id),{}),before_shot,mount_shot_time(s,str(mount.id)))

static func _nearest(st: Dictionary,s: Dictionary) -> Dictionary:
	var best: Dictionary={}
	var best_distance: float=INF
	for target in st.ships:
		if target.team!=s.team and not target.sunk and not target.get("captureSecured",false):
			var d: float=_pos(s).distance_to(_pos(target))
			if d<best_distance:
				best_distance=d
				best=target
	return best

static func _move(st: Dictionary,s: Dictionary,dt: float,desired: float,throttle: float,boost: bool,frame_cache=null) -> void:
	var next: Dictionary=Certification._motion_with_status(s,dt,desired,throttle,boost,Damage.get_status_cached(s,frame_cache))
	s.angle=next.angle
	var velocity: Vector2=Vector2(next.vx,next.vy)
	var point: Vector2=Vector2(next.x,next.y)
	if not _blocked(st,point,_radius(s)):
		s.x=point.x
		s.y=point.y
	else:
		velocity*=0.1
	s.vx=velocity.x
	s.vy=velocity.y
	if velocity.length()>5.0:
		s.fuel=maxf(0.0,s.fuel-dt*(0.018 if boost else 0.01)*maxf(0.0,Damage.number(s.spec.get("fuelUse"),1.0)))

static func _weapon_range(s: Dictionary) -> float:
	var result: float=0.0
	for mount in _mounts(s):
		result=maxf(result,mount.range)
	return maxf(80.0,result)

static func _engagement_range(s: Dictionary) -> float:
	var useful: Array=[]
	var total: float=0.0
	for mount in _mounts(s):
		if s.ammo<mount.ammoCost:
			continue
		var dps: float=mount.damage*mount.fireRate*(1.8 if mount.kind=="torpedo" else 1.0)
		if dps<=0.0:
			continue
		useful.append({"range":mount.range,"dps":dps})
		total+=dps
	# Dry/unarmed boats retain their previous spacing rather than charging in.
	if useful.is_empty():
		return _weapon_range(s)
	useful.sort_custom(func(a,b): return a.range>b.range)
	var cumulative: float=0.0
	for mount in useful:
		cumulative+=mount.dps
		if cumulative>=total*0.8:
			return maxf(80.0,mount.range)
	return _weapon_range(s)

static func _combat_heading(s: Dictionary,target: Dictionary) -> float:
	var desired: float=(_pos(target)-_pos(s)).angle()
	var best: float=-1.0
	for mount in _mounts(s):
		if _pos(s).distance_to(_pos(target))>mount.range*0.95 or s.ammo<mount.ammoCost:
			continue
		var weight: float=mount.damage*mount.fireRate
		if weight>best:
			best=weight
			var bearing: float=(_lead(s,mount,target)-_mount_origin(s,mount)).angle()
			desired=bearing-mount.angle if mount.arc<TAU-0.01 else bearing
	return desired

static func _avoid_land(st: Dictionary,s: Dictionary,desired: float,throttle: float) -> float:
	if throttle<=0.0:
		return desired
	var look: float=_radius(s)+95.0
	if _clear_shot(st,_pos(s),_pos(s)+Vector2.from_angle(desired)*look,_radius(s)+6.0):
		return desired
	var side: float=1.0 if int(s.get("formationIndex",0))%2==0 else -1.0
	for offset in [0.5*side,-0.5*side,0.95*side,-0.95*side,1.5*side,-1.5*side,2.2*side,-2.2*side,PI]:
		var angle: float=desired+offset
		if _clear_shot(st,_pos(s),_pos(s)+Vector2.from_angle(angle)*look,_radius(s)+6.0):
			return angle
	return desired

static func _ai(st: Dictionary,s: Dictionary,dt: float) -> void:
	# Compatibility entry for internal callers. The shared update uses all-helm,
	# all-move, all-fire phases instead of this single-hull convenience wrapper.
	if s.get("sunk",false) or s.get("captureSecured",false):return
	var control: Dictionary=Tactical.helm(st,s)
	_move(st,s,dt,float(control.angle),float(control.throttle),false)
	Tactical.after_motion(st)
	_fire(st,s,Vector2.ZERO,{},true,Tactical.fire_gates(st,s))

static func _collisions(st: Dictionary) -> void:
	for i in range(st.ships.size()):
		for j in range(i+1,st.ships.size()):
			var a: Dictionary=st.ships[i]
			var b: Dictionary=st.ships[j]
			if a.sunk or b.sunk:
				continue
			var delta: Vector2=_pos(b)-_pos(a)
			var d: float=delta.length()
			var minimum: float=_radius(a)+_radius(b)
			if d<minimum:
				var normal: Vector2=delta/d if d>0.0001 else Vector2.RIGHT
				var push: Vector2=normal*(minimum-d)*0.51
				var ap: Vector2=_pos(a)-push
				var bp: Vector2=_pos(b)+push
				if not _blocked(st,ap,_radius(a)):
					a.x=ap.x
					a.y=ap.y
				if not _blocked(st,bp,_radius(b)):
					b.x=bp.x
					b.y=bp.y

static func _blast(st: Dictionary,p: Dictionary,point: Vector2,direct_id: String,frame_cache=null) -> void:
	var radius: float=Damage.number(p.get("blastRadius"))
	if radius<=0.0:
		return
	for s in st.ships:
		if s.get("captureSecured",false) or s.sunk or s.team==p.team or str(s.id)==direct_id:
			continue
		var distance: float=point.distance_to(_pos(s))
		if distance<radius+_radius(s) and _clear_shot(st,point,_pos(s),1.0):
			var before_hp: float=Damage.number(s.get("hp"))
			Damage.invalidate_frame_cache(frame_cache,s)
			var events: Array=Damage.apply_hit(s,{"damage":p.damage*0.45*clampf(1.0-distance/(radius+_radius(s)),0.0,1.0),"kind":"rocket","incendiary":true,"section":"deck"},st.rng,frame_cache)
			if EquipmentCombat.is_canonical_owner(s,frame_cache):_combat_mounts(st,s,frame_cache)
			if not events.is_empty():
				CombatEvents.emit_hit(st,p,s,_pos(s),"deck",events,maxf(0.0,before_hp-Damage.number(s.get("hp"))),false)

static func _projectiles(st: Dictionary,dt: float,frame_cache=null) -> void:
	var survivors: Array=[]
	for p in st.projectiles:
		p.px=p.x
		p.py=p.y
		p.x+=p.vx*dt
		p.y+=p.vy*dt
		p.life-=dt
		p.age=Damage.number(p.get("age"))+dt
		var start: Vector2=Vector2(p.px,p.py)
		var delta: Vector2=_pos(p)-start
		var hit: Dictionary={}
		var first: float=INF
		for s in st.ships:
			if s.sunk or s.team==p.team or s.get("captureSecured",false):
				continue
			var t: float=clampf((_pos(s)-start).dot(delta)/maxf(0.0001,delta.length_squared()),0.0,1.0)
			if _pos(s).distance_to(start+delta*t)<_radius(s)+p.radius and t<first:
				hit=s
				first=t
		var land_t: float=INF
		var hit_land: bool=false
		var steps: int=maxi(1,int(ceil(delta.length()/6.0)))
		for k in range(1,steps+1):
			var t: float=float(k)/steps
			var sample: Vector2=start+delta*t
			if _blocked(st,sample,p.radius):
				land_t=t
				hit_land=_island_blocked(st,sample,p.radius)
				break
		if not hit.is_empty() and first<land_t:
			var point: Vector2=start+delta*first
			var eng_roll: bool=false
			if p.kind!="torpedo":eng_roll=st.rng.randf()<0.25
			var section: String="waterline" if p.kind=="torpedo" else ("engine" if eng_roll else "bow")
			if EquipmentCombat.is_canonical_owner(hit,frame_cache):
				section=str(p.get("section","")) if not str(p.get("section","")).is_empty() else EquipmentCombat.canonical_hit_section(hit,point,str(p.kind),eng_roll,frame_cache)
			var before_hp: float=Damage.number(hit.get("hp"))
			Damage.invalidate_frame_cache(frame_cache,hit)
			var events: Array=Damage.apply_hit(hit,{"damage":p.damage,"kind":p.kind,"penetration":p.get("penetration",0.0),"incendiary":p.get("incendiary",false),"section":section},st.rng,frame_cache)
			if EquipmentCombat.is_canonical_owner(hit,frame_cache):_combat_mounts(st,hit,frame_cache)
			CombatEvents.emit_hit(st,p,hit,point,section,events,maxf(0.0,before_hp-Damage.number(hit.get("hp"))),true)
			_blast(st,p,point,str(hit.id),frame_cache)
			if not events.is_empty():
				_log(st,hit.name+": "+events[0])
		elif land_t!=INF or p.life<=0.0:
			var miss_point: Vector2=start+delta*land_t if land_t!=INF else _pos(p)
			CombatEvents.emit_miss(st,p,miss_point,hit_land and land_t!=INF)
		else:
			survivors.append(p)
	st.projectiles=survivors

static func advance_visuals(st: Dictionary,dt: float) -> void:
	# Cosmetic tail only: ships, projectiles, combat time, RNG and rewards stay fixed.
	if st.get("result")==null:return
	if float(st.get("visualTailTime",0))>=12.0:return
	dt=clampf(Damage.number(dt),0.0,0.1)
	st.visualTailTime=minf(12.0,float(st.get("visualTailTime",0))+dt)
	CombatEvents.tick_wrecks(st,dt)
	_age_effects(st,dt)

static func _age_effects(st: Dictionary,dt: float) -> void:
	var effects: Array=[]
	for effect in st.get("effects",[]):
		effect.age+=dt
		if effect.age<effect.life:effects.append(effect)
	st.effects=effects

static func update(st: Dictionary,dt: float,input: Dictionary = {}) -> Dictionary:
	CombatEvents.ensure_state(st)
	Objectives.configure(st)
	if st.result!=null:
		return st
	dt=clampf(Damage.number(dt),0.0,1.0/30.0)
	if dt<=0.0:
		return st
	CombatEvents.begin_step(st)
	st.time+=dt
	CombatEvents.tick_wrecks(st,dt)
	if get_flagship(st).is_empty():
		for s in st.ships:
			if s.team=="player" and not s.sunk and not s.get("captureSecured",false):
				select_flagship(st,s.id)
				break
	var ai_us: int=0
	var ai_phases: Dictionary={"mounts":0,"planning":0,"lanes":0,"firing":0,"trace":0}
	var frame_cache: Dictionary={}
	# One complete prepass precedes either side's snapshot or helm. In particular
	# the manual flagship never receives a second damage/cooldown decrement.
	for s in st.ships:
		s.battleTime=st.time
		if s.sunk:
			continue
		# Exactly one decrement of each timer, including the manual flagship.
		Damage.tick_ship(s,dt,{"inCombat":true},frame_cache)
		var mount_started: int=Time.get_ticks_usec()
		var cached_mounts: Array=_combat_mounts(st,s,frame_cache)
		var mount_us: int=Time.get_ticks_usec()-mount_started
		ai_us+=mount_us;ai_phases.mounts+=mount_us
		_tick_cooldowns(s,dt,cached_mounts)
		CombatEvents.check_ship_engine(st,s)
	Objectives.retarget(st,input)
	var planning_started: int=Time.get_ticks_usec()
	Tactical.begin(st,dt,input,frame_cache)
	ai_phases.begin=Time.get_ticks_usec()-planning_started
	var controls: Dictionary={}
	var manual_id: String=str(st.tactical.manualId)
	var active_ids: Array=st.tactical.ships.keys()
	active_ids.sort()
	# Every helm observes the same post-damage/pre-movement snapshot. Stable ID
	# order also keeps real emission/RNG order independent of st.ships iteration.
	for id in active_ids:
		var s: Dictionary=st.tactical.ships[id]
		if s.sunk or s.get("captureSecured",false):
			continue
		if id==manual_id:
			var steer: float=(1.0 if input.get("right",false) else 0.0)-(1.0 if input.get("left",false) else 0.0)
			var turn_step: float=float(s.spec.get("turn",1.8))*clampf(Damage.number(Damage.get_status_cached(s,frame_cache).get("turnFactor"),1.0),0.0,1.0)
			var desired: float=s.angle+steer*turn_step*dt
			var throttle: float=(1.0 if input.get("forward",false) else 0.0)-(0.55 if input.get("backward",false) else 0.0)
			controls[id]={"angle":desired,"throttle":throttle,"boost":input.get("boost",false)}
		else:controls[id]=Tactical.helm(st,s,frame_cache)
	ai_phases.planning=Time.get_ticks_usec()-planning_started
	ai_phases.helm=int(ai_phases.planning)-int(ai_phases.begin)
	ai_us+=int(ai_phases.planning)
	for id in active_ids:
		var s: Dictionary=st.tactical.ships[id]
		var control: Dictionary=controls.get(id,{"angle":s.angle,"throttle":0.0})
		_move(st,s,dt,float(control.angle),float(control.throttle),bool(control.get("boost",false)),frame_cache)
	var lanes_started: int=Time.get_ticks_usec()
	Tactical.after_motion(st)
	ai_phases.lanes=Time.get_ticks_usec()-lanes_started
	ai_us+=int(ai_phases.lanes)
	for id in active_ids:
		var s: Dictionary=st.tactical.ships[id]
		if id==manual_id:
			var aim_x: float=Damage.number(input.get("aimX"),NAN)
			var aim_y: float=Damage.number(input.get("aimY"),NAN)
			if is_finite(aim_x) and is_finite(aim_y):
				var aim: Vector2=Vector2(aim_x,aim_y)
				s.turretAngle=(aim-_pos(s)).angle()
				if input.get("fire",false):
					_fire(st,s,aim,{},false,{},frame_cache)
		else:
			var fire_started: int=Time.get_ticks_usec()
			var gates: Dictionary=Tactical.fire_gates(st,s,frame_cache)
			_fire(st,s,Vector2.ZERO,{},true,gates,frame_cache)
			var firing_us: int=Time.get_ticks_usec()-fire_started
			ai_us+=firing_us;ai_phases.firing+=firing_us
	Damage.clear_frame_cache(frame_cache)
	BoardingCombat.tick(st,dt)
	_collisions(st)
	_projectiles(st,dt,frame_cache)
	Damage.clear_frame_cache(frame_cache)
	var finish_started: int=Time.get_ticks_usec()
	Tactical.finish(st,ai_us)
	ai_phases.trace=Time.get_ticks_usec()-finish_started
	st.tactical.metrics.aiUs+=int(ai_phases.trace)
	st.tactical.metrics.phaseUs=ai_phases
	_age_effects(st,dt)
	Objectives.update(st)
	var players: Array=[]
	var enemies: Array=[]
	for s in st.ships:
		if s.sunk:
			if not s._wreckRecorded:
				s._wreckRecorded=true
				var wreck: Dictionary=CombatEvents.record_wreck(st,s,_radius(s))
				CombatEvents.emit_sink(st,s,wreck)
				_log(st,s.name+" sunk")
		elif s.team=="player" and not s.get("captureSecured",false):
			players.append(s)
		elif not s.get("captureSecured",false):
			enemies.append(s)
	if get_flagship(st).is_empty() and not players.is_empty():
		select_flagship(st,players[0].id)
	if st.result!=null:return st
	if players.is_empty():
		st.result="lost"
	elif enemies.is_empty() and not Objectives.is_convoy(st):
		st.result="won"
	elif st.retreatTimer!=null:
		st.retreatTimer=maxf(0.0,st.retreatTimer-dt)
		if st.retreatTimer<=0.00000001:
			st.result="retreated"
	return st
