extends RefCounted
## Prospective replacements for three implementation-bound legacy observations.
## Every shot/motion sample comes from real Battle.update, never private _fire.
const B=preload("res://scripts/battle.gd")
const D=preload("res://scripts/damage.gd")
const C=preload("res://scripts/tactical_certification.gd")
const F=preload("res://tests/tactical_fixture.gd")
const DT: float=1.0/30.0

static func update(st: Dictionary,input: Dictionary={},history: Dictionary={}) -> Dictionary:
	var before: Dictionary={};var cooldowns: Dictionary={}
	for ship in st.ships:
		before[str(ship.id)]=float(ship.ammo);cooldowns[str(ship.id)]=ship.weaponCooldowns.duplicate()
	B.update(st,DT,input)
	var events: Array=B.pop_events(st);var debit: Dictionary={};var emitted: Dictionary={};var issues: Array=[]
	for event in events:
		if str(event.kind)!="fire":continue
		var ship: Dictionary=F.find(st,str(event.sourceId));var mounts: Array=B._mounts(ship)
		var index: int=int(event.mountIndex);var id: String=str(event.sourceId)
		if ship.is_empty() or index<0 or index>=mounts.size():issues.append("unknown real emitting mount");continue
		var mount: Dictionary=mounts[index];var key: String=id+"/"+str(mount.id)
		if emitted.has(key) or str(event.mountId)!=str(mount.id):issues.append("duplicate or mismatched mount event")
		if history.has(key) and float(event.time)-float(history[key])<1.0/float(mount.fireRate)-0.000001:issues.append("real shot repeated before its reload")
		if not is_equal_approx(B.mount_shot_time(ship,str(mount.id)),float(event.time)) or not is_equal_approx(B.mount_shot_time(ship,index),float(event.time)):issues.append("shot timestamp differs from real event")
		if float(ship.weaponCooldowns[index])<1.0/float(mount.fireRate)-0.000001:issues.append("emission has no real reload cooldown")
		history[key]=float(event.time);emitted[key]=true
		debit[id]=float(debit.get(id,0.0))+float(mount.ammoCost)
	for ship in st.ships:
		var id: String=str(ship.id)
		if not is_equal_approx(float(before[id])-float(ship.ammo),float(debit.get(id,0.0))):issues.append("actual whole rounds do not equal emitted mount costs")
		for index in range(ship.weaponCooldowns.size()):
			var key: String=id+"/"+str(B._mounts(ship)[index].id)
			if not emitted.has(key) and not is_equal_approx(float(ship.weaponCooldowns[index]),maxf(0.0,float(cooldowns[id][index])-DT)):issues.append("non-emitting mount timer changed beyond natural decrement")
	return {"ok":issues.is_empty(),"issues":issues,"events":events}

static func moving_intercept(spec: Dictionary) -> Dictionary:
	var leading: Dictionary=spec.duplicate(true);leading.speed=0.0
	leading.weaponMounts=[{"id":"lead","kind":"gun","range":800.0,"speed":300.0,"x":10.0,"y":4.0}]
	var st: Dictionary=B.create({"fleet":[D.create_ship(spec,{"uid":"moving-target"})],"enemyFleet":[D.create_ship(leading,{"uid":"interceptor"})],"seed":42})
	var target: Dictionary=st.ships[0];var shooter: Dictionary=st.ships[1]
	# Declared initial steady straight motion; no pose/velocity writes after start.
	target.x=900.0;target.y=850.0;target.angle=PI/2.0;target.vx=0.0;target.vy=100.0
	shooter.x=500.0;shooter.y=850.0;shooter.angle=0.0
	B.set_autopilot(st,false)
	var first: Dictionary={};var history: Dictionary={};var audited: bool=true;var actual_hit: bool=false
	var total_cost: float=0.0;var events: Array=[]
	for tick in range(75):
		var frame: Dictionary=update(st,{"forward":true},history);audited=audited and bool(frame.ok)
		for event in frame.events:
			events.append(event.duplicate(true))
			if str(event.kind)=="hit" and str(event.sourceId)==str(shooter.id) and str(event.targetId)==str(target.id):actual_hit=true
			if str(event.kind)!="fire" or str(event.sourceId)!=str(shooter.id):continue
			var mount: Dictionary=B._mounts(shooter)[int(event.mountIndex)];total_cost+=float(mount.ammoCost)
			if not first.is_empty():continue
			var projectile: Dictionary={}
			for raw in st.projectiles:
				if str(raw.owner)==str(shooter.id) and str(raw.mountId)==str(event.mountId):projectile=raw.duplicate(true);break
			var origin: Vector2=F.pos(shooter)+Vector2(mount.x,mount.y).rotated(float(shooter.angle))
			var muzzle: Vector2=Vector2(event.x,event.y)
			var velocity: Vector2=Vector2(projectile.get("vx",0.0),projectile.get("vy",0.0))
			var relative: Vector2=Vector2(target.vx,target.vy)-velocity
			var gap: Vector2=F.pos(target)-muzzle
			var closest_time: float=clampf(-gap.dot(relative)/maxf(0.00001,relative.length_squared()),0.0,float(mount.range)/float(mount.speed))
			var closest: float=(gap+relative*closest_time).length()
			var straight_miss: float=absf((F.pos(target)-origin).cross(Vector2(target.vx,target.vy)))/maxf(1.0,velocity.length())
			first={"event":event.duplicate(true),"projectile":projectile,"muzzle":muzzle,"mount_origin":origin,"mount":mount.duplicate(true),"shooter_pose":C.pose(shooter),"target_pose":C.pose(target),"closest_constant_velocity_gap":closest,"flight_time":closest_time,"unled_motion_scale":straight_miss,"certificate":st.tactical.predictions.get(str(st.tactical.intents.get(str(shooter.id),{}).get("pathFingerprint","")),{}).get("certificate",{}).duplicate(true)}
	return F.encode({"checks":{"real_public_emission_within_point2":not first.is_empty() and float(first.event.time)<=0.2+0.000001,"real_moving_target":not first.is_empty() and float(first.target_pose.vy)>90.0,"emitted_intercept_ray":not first.is_empty() and float(first.projectile.vy)>50.0 and float(first.closest_constant_velocity_gap)<=float(target.spec.size)+3.0,"real_mount_muzzle_origin":not first.is_empty() and absf((first.muzzle as Vector2).distance_to(first.mount_origin)-float(first.mount.muzzleDistance))<0.001,"actual_projectile_hit":actual_hit,"finite_exact_paid_events":audited and total_cost>0.0 and is_equal_approx(80.0-float(shooter.ammo),total_cost),"actual_geometry_initialized":not st.tactical.geometry.is_empty() and not first.get("certificate",{}).is_empty()},"first_emission":first,"events":events,"ammo":float(shooter.ammo),"total_emitted_cost":total_cost,"target_hp":float(target.hp),"target_pose":C.pose(target)})

static func fair_motion(spec: Dictionary,swapped: bool) -> Dictionary:
	var left: Dictionary=D.create_ship(spec,{"uid":"left"});var right: Dictionary=D.create_ship(spec,{"uid":"right"})
	var st: Dictionary=B.create({"fleet":[right if swapped else left],"enemyFleet":[left if swapped else right],"seed":19})
	left.x=500.0;left.y=850.0;left.angle=0.0
	right.x=900.0;right.y=850.0;right.angle=PI
	var motion: Dictionary={"left":[],"right":[]};var first_moving: Dictionary={};var history: Dictionary={};var audited: bool=true
	var frames: Array=[]
	for tick in range(6):
		var frame: Dictionary=update(st,{},history);audited=audited and bool(frame.ok)
		for ship in [left,right]:
			var forward: float=Vector2(ship.vx,ship.vy).dot(Vector2.RIGHT if str(ship.uid)=="left" else Vector2.LEFT)
			if forward>8.0 and not first_moving.has(str(ship.uid)):first_moving[str(ship.uid)]=float(st.time)
			var intent: Dictionary=st.tactical.intents.get(str(ship.id),{})
			var current: Dictionary=C.current(st,ship,intent,DT)
			if current.get("ok",false):motion[str(ship.uid)].append({"time":float(st.time),"tick":tick+1,"checked_at":float(current.record.certificate.checkedAt),"forward_velocity":forward,"pose":C.pose(ship)})
		frames.append(F.snapshot(st))
	return F.encode({"swapped":swapped,"motion":motion,"first_forward_motion":first_moving,"accounting_valid":audited,"frames":frames,"time":float(st.time)})

static func single_approach(spec: Dictionary) -> Dictionary:
	var stationary: Dictionary=spec.duplicate(true);stationary.speed=0.0
	var st: Dictionary=B.create({"fleet":[D.create_ship(spec,{"uid":"approaching-gun"})],"enemyFleet":[D.create_ship(stationary,{"uid":"approach-target","ammo":0.0})],"seed":42})
	var ship: Dictionary=st.ships[0];var enemy: Dictionary=st.ships[1]
	ship.x=500.0;ship.y=850.0;ship.angle=0.0;enemy.x=1200.0;enemy.y=850.0
	var history: Dictionary={};var audited: bool=true;var attainable: bool=true;var first: Dictionary={};var shots: int=0
	var closest: float=700.0;var trace: Array=[];var cost: float=0.0
	for tick in range(90):
		var before: Vector2=F.pos(ship);var previous_velocity: Vector2=Vector2(ship.vx,ship.vy)
		var frame: Dictionary=update(st,{},history);audited=audited and bool(frame.ok)
		var velocity: Vector2=Vector2(ship.vx,ship.vy)
		if velocity.length()>100.0001 or F.pos(ship).distance_to(before)>100.0*DT+0.0001 or velocity.distance_to(previous_velocity)>200.0*(1.0-exp(-4.0*DT))+0.0001:attainable=false
		closest=minf(closest,F.pos(ship).distance_to(F.pos(enemy)))
		for event in frame.events:
			if str(event.kind)=="fire" and str(event.sourceId)==str(ship.id):
				shots+=1;cost+=float(B._mounts(ship)[int(event.mountIndex)].ammoCost)
				if first.is_empty():
					var mount: Dictionary=B._mounts(ship)[int(event.mountIndex)];var projectile: Dictionary={}
					for raw in st.projectiles:
						if str(raw.owner)==str(ship.id) and str(raw.mountId)==str(event.mountId):projectile=raw.duplicate(true);break
					var gap: Vector2=F.pos(enemy)-Vector2(event.x,event.y)
					var relative: Vector2=Vector2(enemy.vx,enemy.vy)-Vector2(projectile.get("vx",0.0),projectile.get("vy",0.0))
					var flight: float=-gap.dot(relative)/maxf(0.00001,relative.length_squared())
					first={"event":event.duplicate(true),"projectile":projectile,"mount":mount.duplicate(true),"ship_pose":C.pose(ship),"target_pose":C.pose(enemy),"muzzle_distance_to_target":gap.length(),"actual_ray_closest_time":flight,"actual_ray_closest_gap":(gap+relative*flight).length(),"configured_full_life":float(mount.range)/float(mount.speed)}
		if tick%3==0:trace.append(F.snapshot(st))
	var before_hold_speed: float=Vector2(ship.vx,ship.vy).length();var hold_time: float=float(st.time)
	var command_ok: bool=B.issue_order(st,[ship.id],"hold")
	var minimum_hold_speed: float=before_hold_speed;var hold_distance: float=0.0;var previous: Vector2=F.pos(ship)
	for tick in range(30):
		var previous_velocity: Vector2=Vector2(ship.vx,ship.vy)
		var frame: Dictionary=update(st,{},history);audited=audited and bool(frame.ok)
		var velocity: Vector2=Vector2(ship.vx,ship.vy)
		hold_distance+=F.pos(ship).distance_to(previous);previous=F.pos(ship)
		minimum_hold_speed=minf(minimum_hold_speed,velocity.length())
		if velocity.length()>100.0001 or velocity.distance_to(previous_velocity)>200.0*(1.0-exp(-4.0*DT))+0.0001:attainable=false
		for event in frame.events:
			if str(event.kind)=="fire" and str(event.sourceId)==str(ship.id):cost+=float(B._mounts(ship)[int(event.mountIndex)].ammoCost)
	return F.encode({"checks":{"original_weapon_reach":is_equal_approx(B._weapon_range(ship),550.0),"useful_timely_advance":700.0-closest>=80.0,"real_paid_fire_by_three_seconds":shots>0 and not first.is_empty() and float(first.event.time)<=3.0+0.000001,"correct_actual_shot_reach":not first.is_empty() and float(first.actual_ray_closest_time)>0.0 and float(first.actual_ray_closest_time)<=float(first.configured_full_life) and float(first.actual_ray_closest_gap)<=float(enemy.spec.size)+float(first.projectile.radius) and is_equal_approx(float(first.projectile.life)+DT,550.0/float(first.mount.speed)),"attainable_speed_and_acceleration":attainable,"actual_hold_braking":command_ok and before_hold_speed>10.0 and minimum_hold_speed<before_hold_speed*0.5,"finite_fuel_spent":float(ship.fuel)<60.0 and float(ship.fuel)>0.0,"finite_exact_paid_events":audited and cost>0.0 and is_equal_approx(80.0-float(ship.ammo),cost)},"first_emission":first,"closest_range_in_three_seconds":closest,"hold_at":hold_time,"before_hold_speed":before_hold_speed,"minimum_hold_speed":minimum_hold_speed,"actual_hold_travel":hold_distance,"fuel":float(ship.fuel),"ammo":float(ship.ammo),"trace":trace})
