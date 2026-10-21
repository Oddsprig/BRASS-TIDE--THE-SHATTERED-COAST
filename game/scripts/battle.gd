extends RefCounted
## Pure fixed-step combat. State and RNG belong exclusively to the caller.
const Objectives=preload("res://scripts/battle_objectives.gd")
const Refit=preload("res://scripts/refit.gd")
const WeaponGeometry=preload("res://scripts/weapon_geometry.gd")
const Damage=preload("res://scripts/damage.gd")
const Deployment=preload("res://scripts/deployment.gd")
const CombatEvents=preload("res://scripts/combat_events.gd")
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
	for island in options.get("islands",[]):
		var points: Array=island.get("points",[]) if island is Dictionary else island
		if points.size()>=3:
			st.islands.append({"points":points.duplicate(true)})
	if st.islands.is_empty():
		st.islands=[{"points":[[850,80],[1130,120],[1210,310],[1030,420],[820,300]]},{"points":[[1040,1320],[1240,1250],[1430,1450],[1320,1640],[1070,1580]]}]
	var fleet: Array=options.get("fleet",[])
	var enemy_fleet: Array=options.get("enemyFleet",[]).duplicate()
	if enemy_fleet.is_empty():
		for spec in options.get("enemySpecs",[]):
			enemy_fleet.append(Damage.create_ship(spec))
	var player_split: Dictionary=Deployment.split(fleet)
	var enemy_split: Dictionary=Deployment.split(enemy_fleet)
	st.reserves.player=player_split.reserve
	st.reserves.enemy=enemy_split.reserve
	st.deployment.player=player_split.points
	st.deployment.enemy=enemy_split.points
	for i in range(player_split.deployed.size()):
		_deploy(st,player_split.deployed[i],i,"player",player_split.deployed.size())
	for i in range(enemy_split.deployed.size()):
		_deploy(st,enemy_split.deployed[i],i,"enemy",enemy_split.deployed.size())
	for ship in st.ships:
		if str(ship.get("uid","")) in st.mission.get("allyUids",[]):
			ship.order="hold";ship.orderTarget={"x":ship.x,"y":ship.y}
	for ship in st.ships:
		if ship.team=="player" and not ship.sunk and not str(ship.get("uid","")) in st.mission.get("allyUids",[]):
			st.playerId=ship.id
			ship.selected=true
			break
	return st

static func _deploy(st: Dictionary,s: Dictionary,index: int,team: String,count: int) -> void:
	if not s.spec.get("weaponMounts") is Array:
		s.spec=Refit.effective_spec(s.spec,Refit.defaults(s.spec))
	s.supportRepairFactor=1.0
	s.localAimAngles={}
	s.team=team
	s.id="%s-%d-%s"%[team,index,s.type]
	s.x=(520.0 if team=="player" else 1600.0)+(index%2)*85.0
	s.y=850.0+(floor(index/2.0)-(ceil(count/2.0)-1.0)/2.0)*85.0
	s.angle=0.0 if team=="player" else PI
	s.turretAngle=s.angle
	s.vx=0.0
	s.vy=0.0
	s.armor=maxf(0.0,Damage.number(s.spec.get("armor"),Damage.number(s.get("armor"))))
	s.cooldown=0.0
	var mounts: Array=_mounts(s)
	s.weaponCooldowns=[]
	for mount in mounts:
		s.weaponCooldowns.append(0.0)
	CombatEvents.register_ship(st,s,mounts)
	s.selected=false
	s.order="engage"
	s.orderTarget={}
	s.formationIndex=index
	s._wreckRecorded=false
	if not _spawn_clear(st,s,_pos(s)):
		for k in range(128):
			var p: Vector2=Vector2((260.0 if team=="player" else 1880.0)+(k%4)*80.0,90.0+floor(k/4.0)*48.0)
			if _spawn_clear(st,s,p):
				s.x=p.x
				s.y=p.y
				break
	st.ships.append(s)

static func _spawn_clear(st: Dictionary,s: Dictionary,p: Vector2) -> bool:
	if _blocked(st,p,_radius(s)):
		return false
	for other in st.ships:
		if not other.sunk and p.distance_to(_pos(other))<_radius(s)+_radius(other)+4.0:
			return false
	return true

static func get_flagship(st: Dictionary) -> Dictionary:
	for s in st.ships:
		if s.id==st.playerId and not s.sunk:
			return s
	return {}

static func select_flagship(st: Dictionary,id) -> bool:
	for s in st.ships:
		if s.id==id and s.team=="player" and not s.sunk:
			st.playerId=id
			for boat in st.ships:
				boat.selected=boat.id==id
			return true
	return false

static func set_autopilot(st: Dictionary,enabled: bool) -> bool:
	st.autopilot=enabled
	return enabled

static func _ship_with_id(st: Dictionary,id: String) -> Dictionary:
	for s in st.ships:
		if str(s.id)==id and not s.sunk:
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
		boat.order=order
		boat.orderTarget=clean.duplicate()
		if order=="hold" and not clean.has("x"):
			boat.orderTarget={"x":float(boat.x),"y":float(boat.y)}
	return true

static func set_order(st: Dictionary,order: String,target: Dictionary={}) -> String:
	var ids: Array=[]
	for s in st.ships:
		if s.team=="player" and not s.sunk:
			ids.append(s.id)
	if issue_order(st,ids,order,target):
		st.order=order
	return st.order

static func retreat(st: Dictionary) -> void:
	if st.result!=null or st.retreatTimer!=null:
		return
	st.retreatTimer=12.0
	set_order(st,"withdraw")
	_log(st,"Fleet withdrawing — 12 seconds to escape")

static func _mounts(s: Dictionary) -> Array:
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

static func _tick_cooldowns(s: Dictionary,dt: float) -> void:
	var mounts: Array=_mounts(s)
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
		if candidate.sunk or candidate.team==s.team:continue
		var delta: Vector2=_lead(s,mount,candidate)-origin
		if delta.length()>mount.range:continue
		if absf(angle_difference(s.angle+mount.angle,delta.angle()))>mount.arc*0.5:continue
		if not _clear_shot(st,origin,_pos(candidate),3.0):continue
		if candidate==preferred:return candidate
		var score: float=delta.length_squared()
		if score<best:best=score;result=candidate
	return result

static func _fire(st: Dictionary,s: Dictionary,target: Vector2,target_ship: Dictionary={}) -> void:
	if s.sunk or st.projectiles.size()>=400:
		return
	var mounts: Array=_mounts(s)
	_sync_cooldowns(s,mounts.size())
	CombatEvents.sync_mount_shots(s,mounts)
	var status: Dictionary=Damage.get_status(s)
	if status.weaponFactor<=0.01:
		return
	for i in range(mounts.size()):
		var mount: Dictionary=mounts[i]
		if s.weaponCooldowns[i]>0.0 or (i==0 and s.cooldown>0.0) or s.ammo<mount.ammoCost or st.projectiles.size()>=400:
			continue
		var mount_target: Dictionary=_target_for_mount(st,s,mount,target_ship) if not target_ship.is_empty() else {}
		if not target_ship.is_empty() and mount_target.is_empty():continue
		var origin: Vector2=_mount_origin(s,mount)
		var aim: Vector2=_lead(s,mount,mount_target) if not mount_target.is_empty() else target
		var delta: Vector2=aim-origin
		if delta.length()>mount.range or delta.length()<0.001:
			continue
		var bearing: float=delta.angle()
		if absf(angle_difference(s.angle+mount.angle,bearing))>mount.arc*0.5+0.00001:
			continue
		var kind: String="bullet" if mount.kind=="gun" else ("shell" if mount.kind=="cannon" else mount.kind)
		var radius: float=5.0 if kind=="torpedo" else (3.0 if kind=="rocket" else 2.0)
		var distance: float=float(mount.muzzleDistance)
		var muzzle: Vector2=origin+Vector2.from_angle(bearing)*distance
		if not _clear_shot(st,origin,aim,radius) or _blocked(st,muzzle,radius):
			continue
		s.turretAngle=bearing
		if not s.get("localAimAngles") is Dictionary:s.localAimAngles={}
		s.localAimAngles[str(mount.id)]=angle_difference(float(s.angle),bearing)
		var angle: float=bearing+(st.rng.randf()-0.5)*(0.025 if kind=="torpedo" else 0.045)
		var velocity: Vector2=Vector2.from_angle(angle)*mount.speed+Vector2(s.vx,s.vy)*0.2
		st.projectiles.append({"x":muzzle.x,"y":muzzle.y,"px":muzzle.x,"py":muzzle.y,"vx":velocity.x,"vy":velocity.y,"team":s.team,"damage":mount.damage*(1.8 if kind=="torpedo" else 1.0),"kind":kind,"family":mount.kind,"variant":CombatEvents.weapon_variant(mount.kind,mount),"moduleId":str(mount.get("moduleId","")),"size":int(mount.get("size",1)),"life":mount.range/mount.speed,"age":0.0,"owner":s.id,"sourceUid":str(s.get("uid",s.id)),"sourceHull":str(s.get("type",s.spec.get("id","boat"))),"mountId":mount.id,"mountIndex":i,"angle":angle,"radius":radius,"penetration":18.0 if kind=="torpedo" else (4.0 if kind=="shell" else 0.0),"blastRadius":36.0 if kind=="rocket" else 0.0,"incendiary":kind=="rocket","height":mount.barrelHeight,"trail":"foam" if kind=="torpedo" else ("smoke" if kind=="rocket" else "tracer")})
		s.ammo=maxf(0.0,s.ammo-mount.ammoCost)
		s.weaponCooldowns[i]=1.0/(mount.fireRate*maxf(0.15,status.weaponFactor))
		if i==0:
			s.cooldown=s.weaponCooldowns[0]
		CombatEvents.emit_fire(st,s,mount,i,muzzle,angle,mount_target)

static func _nearest(st: Dictionary,s: Dictionary) -> Dictionary:
	var best: Dictionary={}
	var best_distance: float=INF
	for target in st.ships:
		if target.team!=s.team and not target.sunk:
			var d: float=_pos(s).distance_to(_pos(target))
			if d<best_distance:
				best_distance=d
				best=target
	return best

static func _move(st: Dictionary,s: Dictionary,dt: float,desired: float,throttle: float,boost: bool) -> void:
	var turn: float=maxf(0.0,Damage.number(s.spec.get("turn"),1.8))
	s.angle=wrapf(s.angle+clampf(angle_difference(s.angle,desired),-turn*dt,turn*dt),-PI,PI)
	var speed: float=maxf(0.0,Damage.number(s.spec.get("speed"),90.0))*Damage.get_status(s).speedFactor*(1.0 if s.fuel>0.0 else 0.2)*throttle*(1.2 if boost else 1.0)
	var velocity: Vector2=Vector2(s.vx,s.vy).lerp(Vector2.from_angle(s.angle)*speed,1.0-exp(-dt*4.0))
	var point: Vector2=_pos(s)+velocity*dt
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
	var target: Dictionary=_nearest(st,s)
	var order: String=str(s.get("order",st.order if s.team=="player" else "engage"))
	var order_target: Dictionary=s.get("orderTarget",{})
	if order=="attack" and order_target.has("shipId"):
		var chosen: Dictionary=_ship_with_id(st,str(order_target.shipId))
		if not chosen.is_empty() and chosen.team!=s.team:
			target=chosen
	var desired: float=s.angle
	var throttle: float=0.0
	var weapon_range: float=_weapon_range(s)
	var engagement_range: float=_engagement_range(s)
	var distance: float=INF
	if not target.is_empty():
		distance=_pos(s).distance_to(_pos(target))
		desired=_combat_heading(s,target)
		throttle=0.9 if distance>engagement_range*0.72 else (-0.25 if distance<engagement_range*0.35 else 0.18)
		if not _clear_shot(st,_pos(s),_pos(target),3.0):
			desired=(_pos(target)-_pos(s)).angle()
			throttle=0.9
	if order=="withdraw":
		desired=PI if s.team=="player" else 0.0
		throttle=1.0
	elif order in ["move","hold"] or (order=="attack" and not order_target.has("shipId") and order_target.has("x") and distance>weapon_range):
		var goal: Vector2=Vector2(order_target.get("x",s.x),order_target.get("y",s.y))
		var gap: float=_pos(s).distance_to(goal)
		throttle=clampf(gap/140.0,0.2,0.95) if gap>12.0 else 0.0
		if gap>12.0:
			desired=(goal-_pos(s)).angle()
	elif order=="escort":
		var leader: Dictionary=_ship_with_id(st,str(order_target.shipId)) if order_target.has("shipId") else get_flagship(st)
		if not leader.is_empty() and leader.id!=s.id:
			var side: float=1.0 if int(s.formationIndex)%2==0 else -1.0
			var goal: Vector2=_pos(leader)+Vector2(-105.0,side*90.0).rotated(leader.angle)
			var gap: float=_pos(s).distance_to(goal)
			throttle=clampf(gap/160.0,0.15,1.0) if gap>40.0 else 0.0
			if gap>75.0:
				desired=(goal-_pos(s)).angle()
	desired=_avoid_land(st,s,desired,throttle)
	_move(st,s,dt,desired,throttle,false)
	if not target.is_empty():
		s.turretAngle=(_pos(target)-_pos(s)).angle()
		if distance<=weapon_range:
			_fire(st,s,_pos(target),target)

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

static func _blast(st: Dictionary,p: Dictionary,point: Vector2,direct_id: String) -> void:
	var radius: float=Damage.number(p.get("blastRadius"))
	if radius<=0.0:
		return
	for s in st.ships:
		if s.sunk or s.team==p.team or str(s.id)==direct_id:
			continue
		var distance: float=point.distance_to(_pos(s))
		if distance<radius+_radius(s) and _clear_shot(st,point,_pos(s),1.0):
			var before_hp: float=Damage.number(s.get("hp"))
			var events: Array=Damage.apply_hit(s,{"damage":p.damage*0.45*clampf(1.0-distance/(radius+_radius(s)),0.0,1.0),"kind":"rocket","incendiary":true,"section":"deck"},st.rng)
			if not events.is_empty():
				CombatEvents.emit_hit(st,p,s,_pos(s),"deck",events,maxf(0.0,before_hp-Damage.number(s.get("hp"))),false)

static func _projectiles(st: Dictionary,dt: float) -> void:
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
			if s.sunk or s.team==p.team:
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
			var section: String="waterline" if p.kind=="torpedo" else ("engine" if st.rng.randf()<0.25 else "bow")
			var before_hp: float=Damage.number(hit.get("hp"))
			var events: Array=Damage.apply_hit(hit,{"damage":p.damage,"kind":p.kind,"penetration":p.get("penetration",0.0),"incendiary":p.get("incendiary",false),"section":section},st.rng)
			CombatEvents.emit_hit(st,p,hit,point,section,events,maxf(0.0,before_hp-Damage.number(hit.get("hp"))),true)
			_blast(st,p,point,str(hit.id))
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
			if s.team=="player" and not s.sunk:
				select_flagship(st,s.id)
				break
	var flagship: Dictionary=get_flagship(st)
	for s in st.ships:
		s.battleTime=st.time
		if s.sunk:
			continue
		# Exactly one decrement of each timer, including the manual flagship.
		Damage.tick_ship(s,dt,{"inCombat":true})
		_tick_cooldowns(s,dt)
		CombatEvents.check_ship_engine(st,s)
		if s.sunk:
			continue
		var manual: bool=input.get("manual",false)==true or not st.get("autopilot",true)
		if manual and not flagship.is_empty() and s.id==flagship.id and s.order!="withdraw":
			var steer: float=(1.0 if input.get("right",false) else 0.0)-(1.0 if input.get("left",false) else 0.0)
			var desired: float=s.angle+steer*float(s.spec.get("turn",1.8))*dt
			var throttle: float=(1.0 if input.get("forward",false) else 0.0)-(0.55 if input.get("backward",false) else 0.0)
			_move(st,s,dt,desired,throttle,input.get("boost",false))
			var aim_x: float=Damage.number(input.get("aimX"),NAN)
			var aim_y: float=Damage.number(input.get("aimY"),NAN)
			if is_finite(aim_x) and is_finite(aim_y):
				var aim: Vector2=Vector2(aim_x,aim_y)
				s.turretAngle=(aim-_pos(s)).angle()
				if input.get("fire",false):
					_fire(st,s,aim)
		else:
			_ai(st,s,dt)
	_collisions(st)
	_projectiles(st,dt)
	_age_effects(st,dt)
	var players: Array=[]
	var enemies: Array=[]
	for s in st.ships:
		if s.sunk:
			if not s._wreckRecorded:
				s._wreckRecorded=true
				var wreck: Dictionary=CombatEvents.record_wreck(st,s,_radius(s))
				CombatEvents.emit_sink(st,s,wreck)
				_log(st,s.name+" sunk")
		elif s.team=="player":
			players.append(s)
		else:
			enemies.append(s)
	if get_flagship(st).is_empty() and not players.is_empty():
		select_flagship(st,players[0].id)
	Objectives.update(st)
	if st.result!=null:return st
	if players.is_empty():
		st.result="lost"
	elif enemies.is_empty():
		st.result="won"
	elif st.retreatTimer!=null:
		st.retreatTimer=maxf(0.0,st.retreatTimer-dt)
		if st.retreatTimer<=0.00000001:
			st.result="retreated"
	return st
