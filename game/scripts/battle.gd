extends RefCounted
## Pure fixed-step combat. State and RNG belong exclusively to the caller.
const Damage=preload("res://scripts/damage.gd")
const WIDTH: float=2300.0
const HEIGHT: float=1700.0

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

static func _blocked(st: Dictionary, p: Vector2, r: float) -> bool:
	if p.x<r or p.x>WIDTH-r or p.y<r or p.y>HEIGHT-r:
		return true
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

static func _effect(st: Dictionary,p: Vector2,type: String) -> void:
	st.effects.append({"x":p.x,"y":p.y,"type":type,"age":0.0,"life":1.3 if type=="explosion" else (0.16 if type=="muzzle" else 0.45)})
	if st.effects.size()>200:
		st.effects.pop_front()

static func _log(st: Dictionary,message: String) -> void:
	st.log.append(message)
	if st.log.size()>12:
		st.log.pop_front()

static func create(options: Dictionary) -> Dictionary:
	var random: RandomNumberGenerator=RandomNumberGenerator.new()
	random.seed=int(options.get("seed",1))
	var st: Dictionary={"ships":[],"projectiles":[],"effects":[],"wrecks":[],"time":0.0,"result":null,"playerId":null,"order":"engage","rng":random,"location":options.get("location",{"name":"Open water"}),"islands":[],"log":[],"retreatTimer":null}
	for island in options.get("islands",[]):
		var points: Array=island.get("points",[]) if island is Dictionary else island
		if points.size()>=3:
			st.islands.append({"points":points.duplicate(true)})
	if st.islands.is_empty():
		st.islands=[{"points":[[850,80],[1130,120],[1210,310],[1030,420],[820,300]]},{"points":[[1040,1320],[1240,1250],[1430,1450],[1320,1640],[1070,1580]]}]
	var fleet: Array=options.get("fleet",[])
	var enemies: Array=options.get("enemySpecs",[])
	var enemy_fleet: Array=options.get("enemyFleet",[])
	for i in range(fleet.size()):
		_deploy(st,fleet[i],i,"player",fleet.size())
	if not enemy_fleet.is_empty():
		for i in range(enemy_fleet.size()):
			_deploy(st,enemy_fleet[i],i,"enemy",enemy_fleet.size())
	else:
		for i in range(enemies.size()):
			_deploy(st,Damage.create_ship(enemies[i]),i,"enemy",enemies.size())
	for ship in st.ships:
		if ship.team=="player" and not ship.sunk:
			st.playerId=ship.id
			break
	return st

static func _deploy(st: Dictionary,s: Dictionary,index: int,team: String,count: int) -> void:
	s.team=team
	s.id="%s-%d-%s"%[team,index,s.type]
	s.x=(520.0 if team=="player" else 1600.0)+(index%2)*65.0
	s.y=850.0+(floor(index/2.0)-(ceil(count/2.0)-1.0)/2.0)*85.0
	s.angle=0.0 if team=="player" else PI
	s.turretAngle=s.angle
	s.vx=0.0
	s.vy=0.0
	s.cooldown=0.0
	s._wreckRecorded=false
	if _blocked(st,_pos(s),_radius(s)):
		for k in range(40):
			var p: Vector2=Vector2(300.0 if team=="player" else 1950.0,200.0+k*32.0)
			if not _blocked(st,p,_radius(s)):
				s.x=p.x
				s.y=p.y
				break
	st.ships.append(s)

static func get_flagship(st: Dictionary) -> Dictionary:
	for s in st.ships:
		if s.id==st.playerId and not s.sunk:
			return s
	return {}

static func select_flagship(st: Dictionary,id) -> bool:
	for s in st.ships:
		if s.id==id and s.team=="player" and not s.sunk:
			st.playerId=id
			return true
	return false

static func set_order(st: Dictionary,order: String) -> String:
	if order in ["engage","escort","hold","withdraw"]:
		st.order=order
	return st.order

static func retreat(st: Dictionary) -> void:
	if st.result!=null or st.retreatTimer!=null:
		return
	st.retreatTimer=12.0
	set_order(st,"withdraw")
	_log(st,"Fleet withdrawing — 12 seconds to escape")

static func _fire(st: Dictionary,s: Dictionary,target: Vector2) -> void:
	if s.cooldown>0.0 or s.ammo<1.0 or s.sunk or st.projectiles.size()>=400:
		return
	var status: Dictionary=Damage.get_status(s)
	if status.weaponFactor<=0.01:
		return
	var weapon: String=s.spec.get("weapon","gun")
	var kind: String="torpedo" if weapon=="torpedo" else ("bullet" if weapon=="gun" else "shell")
	var speed: float=240.0 if weapon=="torpedo" else (730.0 if weapon=="rocket" else (620.0 if weapon=="cannon" else 850.0))
	var angle: float=(target-_pos(s)).angle()
	s.turretAngle=angle
	angle+=(st.rng.randf()-0.5)*(0.025 if weapon=="torpedo" else 0.045)
	var direction: Vector2=Vector2.from_angle(angle)
	var p: Vector2=_pos(s)+direction*(_radius(s)+6.0)
	var velocity: Vector2=direction*speed+Vector2(s.vx,s.vy)*0.2
	st.projectiles.append({"x":p.x,"y":p.y,"px":p.x,"py":p.y,"vx":velocity.x,"vy":velocity.y,"team":s.team,"damage":float(s.spec.get("damage",10))*(1.8 if weapon=="torpedo" else 1.0),"kind":kind,"life":float(s.spec.get("range",400))/speed,"owner":s.id,"radius":5.0 if kind=="torpedo" else 2.0})
	s.ammo-=1.0
	s.cooldown=1.0/(maxf(0.05,float(s.spec.get("fireRate",1.0)))*maxf(0.15,status.weaponFactor))
	_effect(st,p,"muzzle")

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
	var turn: float=float(s.spec.get("turn",1.8))
	s.angle+=clampf(angle_difference(s.angle,desired),-turn*dt,turn*dt)
	var speed: float=float(s.spec.get("speed",90))*Damage.get_status(s).speedFactor*(1.0 if s.fuel>0.0 else 0.2)*throttle*(1.2 if boost else 1.0)
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
		s.fuel=maxf(0.0,s.fuel-dt*(0.018 if boost else 0.01))

static func _ai(st: Dictionary,s: Dictionary,dt: float) -> void:
	var target: Dictionary=_nearest(st,s)
	if target.is_empty():
		_move(st,s,dt,s.angle,0.0,false)
		return
	var desired: float=(_pos(target)-_pos(s)).angle()
	var d: float=_pos(s).distance_to(_pos(target))
	var weapon_range: float=float(s.spec.get("range",400))
	var throttle: float=0.85 if d>weapon_range*0.72 else (-0.25 if d<weapon_range*0.35 else 0.22)
	if s.team=="player":
		if st.order=="withdraw":
			desired=PI
			throttle=1.0
		elif st.order=="hold":
			throttle=0.0
		elif st.order=="escort":
			var leader: Dictionary=get_flagship(st)
			if not leader.is_empty() and leader.id!=s.id and _pos(s).distance_to(_pos(leader))>140.0:
				desired=(_pos(leader)-_pos(s)).angle()
				throttle=0.9
	var look: float=_radius(s)+75.0
	if throttle>0.0 and _blocked(st,_pos(s)+Vector2.from_angle(desired)*look,_radius(s)+8.0):
		for offset in [0.7,-0.7,1.3,-1.3,PI]:
			var a: float=desired+offset
			if not _blocked(st,_pos(s)+Vector2.from_angle(a)*look,_radius(s)+8.0):
				desired=a
				break
	_move(st,s,dt,desired,throttle,false)
	s.turretAngle=(_pos(target)-_pos(s)).angle()
	if d<weapon_range:
		_fire(st,s,_pos(target))

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

static func _projectiles(st: Dictionary,dt: float) -> void:
	var survivors: Array=[]
	for p in st.projectiles:
		p.px=p.x
		p.py=p.y
		p.x+=p.vx*dt
		p.y+=p.vy*dt
		p.life-=dt
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
		var steps: int=maxi(1,int(ceil(delta.length()/6.0)))
		for k in range(1,steps+1):
			var t: float=float(k)/steps
			if _blocked(st,start+delta*t,p.radius):
				land_t=t
				break
		if not hit.is_empty() and first<land_t:
			var events: Array=Damage.apply_hit(hit,{"damage":p.damage,"kind":p.kind,"section":"engine" if st.rng.randf()<0.25 else "bow"},st.rng)
			_effect(st,start+delta*first,"explosion" if p.kind=="torpedo" else "hit")
			if not events.is_empty():
				_log(st,hit.name+": "+events[0])
		elif land_t!=INF or p.life<=0.0:
			_effect(st,_pos(p),"splash")
		else:
			survivors.append(p)
	st.projectiles=survivors

static func update(st: Dictionary,dt: float,input: Dictionary = {}) -> Dictionary:
	if st.result!=null:
		return st
	dt=clampf(Damage.number(dt),0.0,1.0/30.0)
	if dt<=0.0:
		return st
	st.time+=dt
	if get_flagship(st).is_empty():
		for s in st.ships:
			if s.team=="player" and not s.sunk:
				st.playerId=s.id
				break
	var flagship: Dictionary=get_flagship(st)
	for s in st.ships:
		if s.sunk:
			continue
		# Exactly one cooldown decrement per living ship, including the manual flagship.
		Damage.tick_ship(s,dt,{"inCombat":true})
		if s.sunk:
			continue
		if not flagship.is_empty() and s.id==flagship.id and st.order!="withdraw":
			var steer: float=(1.0 if input.get("right",false) else 0.0)-(1.0 if input.get("left",false) else 0.0)
			var desired: float=s.angle+steer*float(s.spec.get("turn",1.8))*dt
			var throttle: float=(1.0 if input.get("forward",false) else 0.0)-(0.55 if input.get("backward",false) else 0.0)
			_move(st,s,dt,desired,throttle,input.get("boost",false))
			if input.has("aimX") and input.has("aimY") and is_finite(float(input.aimX)) and is_finite(float(input.aimY)):
				var aim: Vector2=Vector2(input.aimX,input.aimY)
				s.turretAngle=(aim-_pos(s)).angle()
				if input.get("fire",false):
					_fire(st,s,aim)
		else:
			_ai(st,s,dt)
	_collisions(st)
	_projectiles(st,dt)
	var effects: Array=[]
	for effect in st.effects:
		effect.age+=dt
		if effect.age<effect.life:
			effects.append(effect)
	st.effects=effects
	var players: Array=[]
	var enemies: Array=[]
	for s in st.ships:
		if s.sunk:
			if not s._wreckRecorded:
				s._wreckRecorded=true
				st.wrecks.append({"x":s.x,"y":s.y,"angle":s.angle,"name":s.name,"team":s.team,"size":_radius(s)})
				_effect(st,_pos(s),"explosion")
				_log(st,s.name+" sunk")
		elif s.team=="player":
			players.append(s)
		else:
			enemies.append(s)
	if get_flagship(st).is_empty() and not players.is_empty():
		st.playerId=players[0].id
	if players.is_empty():
		st.result="lost"
	elif enemies.is_empty():
		st.result="won"
	elif st.retreatTimer!=null:
		st.retreatTimer=maxf(0.0,st.retreatTimer-dt)
		if st.retreatTimer<=0.00000001:
			st.result="retreated"
	return st
