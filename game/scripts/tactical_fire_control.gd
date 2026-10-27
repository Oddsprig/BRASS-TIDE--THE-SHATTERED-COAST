extends RefCounted
## Current physical solutions and battle-local, persistent salvo spending.
const Routes=preload("res://scripts/tactical_routes.gd")
const Damage=preload("res://scripts/damage.gd")
const EquipmentCombat=preload("res://scripts/equipment_combat.gd")

static func fixed(mount: Dictionary) -> bool:
	return str(mount.kind) in ["rocket","torpedo"] and float(mount.arc)<PI*0.75

static func shot_radius(mount: Dictionary) -> float:
	return 5.0 if str(mount.kind)=="torpedo" else (3.0 if str(mount.kind)=="rocket" else 2.0)

static func dispersion(mount: Dictionary) -> float:
	return 0.025 if str(mount.kind)=="torpedo" else 0.045

static func ally_clearance(radius: float,ally: Dictionary) -> float:
	return radius+maxf(10.0,float(ally.spec.get("size",16)))+4.0

static func intercept(ship: Dictionary,mount: Dictionary,target: Dictionary) -> Dictionary:
	return _intercept051(ship,mount,target,null)

static func _intercept051(ship: Dictionary,mount: Dictionary,target: Dictionary,numeric: Routes._Numeric051) -> Dictionary:
	var own_body=Routes._numeric_body051(numeric,ship)
	var target_body=Routes._numeric_body051(numeric,target)
	var own_point: Vector2=own_body[1] if own_body!=null else Routes.point(ship)
	var target_point: Vector2=target_body[1] if target_body!=null else Routes.point(target)
	var own_velocity: Vector2=own_body[2] if own_body!=null else Vector2(ship.vx,ship.vy)
	var target_velocity: Vector2=target_body[2] if target_body!=null else Vector2(target.vx,target.vy)
	var origin: Vector2=own_point+Vector2(mount.x,mount.y).rotated(float(ship.angle))
	var delta: Vector2=target_point-origin
	var velocity: Vector2=target_velocity-own_velocity*0.2
	var speed: float=float(mount.speed)
	var length: float=float(mount.muzzleDistance)
	var a: float=velocity.length_squared()-speed*speed
	var b: float=2.0*(delta.dot(velocity)-length*speed)
	var c: float=delta.length_squared()-length*length
	var time: float=INF
	if delta.length()<length+0.000001:return {"ok":false,"reason":"Target is inside the muzzle clearance"}
	if absf(a)<0.000001:
		if absf(b)>0.000001 and -c/b>0.0:time=-c/b
	else:
		var discriminant: float=b*b-4.0*a*c
		if discriminant>=0.0:
			var root: float=sqrt(discriminant)
			# Stable quadratic roots avoid cancellation near equal projectile and
			# target speed. A degenerate repeated root is handled without division0.
			var q: float=-0.5*(b+(root if b>=0.0 else -root))
			var one: float=q/a
			var two: float=c/q if absf(q)>0.000000001 else -b/(2.0*a)
			if one>0.0:time=one
			if two>0.0:time=minf(time,two)
	if not is_finite(time) or time>float(mount.range)/speed:return {"ok":false,"reason":"Target cannot be intercepted in range"}
	var aim: Vector2=target_point+velocity*time
	if (aim-origin).length()>float(mount.range):return {"ok":false,"reason":"Target is outside fitted range"}
	var bearing: float=(aim-origin).angle()
	if absf(angle_difference(float(ship.angle)+float(mount.angle),bearing))>float(mount.arc)*0.5+0.00001:return {"ok":false,"reason":"Aligning weapon"}
	var radius: float=shot_radius(mount)
	return {"ok":true,"reason":"Firing lane ready","aim":aim,"origin":origin,"muzzle":origin+Vector2.from_angle(bearing)*float(mount.muzzleDistance),"bearing":bearing,"time":time,"radius":radius}

static func solution(st: Dictionary,ship: Dictionary,mount: Dictionary,target: Dictionary,budget: Dictionary,geometry: Dictionary,cells: Dictionary,check_stores: bool=true,ignore_projectile_cap: bool=false,frame_cache=null,ship_status: Dictionary={}) -> Dictionary:
	if target.is_empty() or target.get("sunk",false) or target.get("captureSecured",false) or target.team==ship.team:return {"ok":false,"reason":"Target unavailable"}
	if check_stores:
		if not ignore_projectile_cap and st.get("projectiles",[]).size()>=400:return {"ok":false,"reason":"Waiting for a clear firing cycle"}
		if float(ship.ammo)<float(mount.ammoCost):return {"ok":false,"reason":"Out of ammunition"}
		var status: Dictionary=EquipmentCombat.status_of(ship,ship_status,frame_cache)
		if not bool(status.get("equipmentOk",true)) or EquipmentCombat.mount_factor(ship,mount,int(mount.get("mountIndex",0)),status,frame_cache)<=0.01 or float(mount.get("damage",1.0))<=0.0:return {"ok":false,"reason":"Weapon disabled"}
		if status.weaponFactor<=0.01:return {"ok":false,"reason":"Guns need working crew"}
	var numeric051: Routes._Numeric051=Routes._numeric_for051(cells,ship)
	var shot: Dictionary=_intercept051(ship,mount,target,numeric051)
	if not shot.ok:return shot
	var clear: String=Routes.sweep(geometry,shot.origin,shot.muzzle,float(shot.radius),budget)
	if clear!="valid":return {"ok":false,"status":clear,"reason":"Checking firing lane" if clear=="pending" else "Land blocks the shot"}
	clear=Routes.sweep(geometry,shot.muzzle,shot.muzzle,float(shot.radius),budget)
	if clear!="valid":return {"ok":false,"status":clear,"reason":"Checking muzzle clearance" if clear=="pending" else "Muzzle obstructed"}
	# Account for inherited shooter velocity and each ally's observed motion.
	var finish: Vector2=shot.muzzle+(Vector2.from_angle(float(shot.bearing))*float(mount.speed)+Vector2(ship.vx,ship.vy)*0.2)*float(shot.time)
	clear=Routes.sweep(geometry,shot.muzzle,finish,float(shot.radius),budget)
	if clear!="valid":return {"ok":false,"status":clear,"reason":"Checking projectile travel" if clear=="pending" else "Land blocks projectile travel"}
	var extra: float=maxf(0.0,float(shot.time)-2.0)*float(cells.get("_maxSpeed",0.0))+90.0
	for ally in Routes.neighbours(cells,shot.muzzle,finish,extra):
		if ally.team!=ship.team or str(ally.id)==str(ship.id):continue
		if not Routes.spend(budget):return {"ok":false,"status":"pending","reason":"Checking allied firing lane"}
		var body051=Routes._numeric_body051(numeric051,ally)
		var ally_point: Vector2=body051[1] if body051!=null else Routes.point(ally)
		var ally_velocity: Vector2=body051[2] if body051!=null else Vector2(ally.vx,ally.vy)
		var ally_radius: float=float(body051[3]) if body051!=null else _hull_radius(ally)
		var relative: Vector2=shot.muzzle-ally_point
		var travel: Vector2=(finish-shot.muzzle)-ally_velocity*float(shot.time)
		var t: float=clampf(-relative.dot(travel)/maxf(0.000001,travel.length_squared()),0.0,1.0)
		if (relative+travel*t).length()<float(shot.radius)+ally_radius+4.0:return {"ok":false,"reason":"Ally in firing lane"}
	return shot

static func pass_key(ship_id: String,mount_id: String,revision: int,pass_id: String) -> String:
	return JSON.stringify([ship_id,mount_id,revision,pass_id]).sha256_text()

static func gate(st: Dictionary,ship: Dictionary,mount: Dictionary,index: int,intent: Dictionary,options: Dictionary,target: Dictionary,budget: Dictionary,frame_cache=null,ship_status: Dictionary={}) -> Dictionary:
	var t: Dictionary=st.tactical
	var id: String=str(ship.id)
	var mount_id: String=str(mount.id)
	if EquipmentCombat.mount_factor(ship,mount,index,ship_status,frame_cache)<=0.01 or float(mount.get("damage",1.0))<=0.0:return {"ok":false,"reason":"Weapon disabled"}
	var plan: Dictionary=intent.get("fireGate",{}).get(mount_id,{})
	var reason: String=str(plan.get("reason","Waiting for a firing opportunity"))
	if plan.is_empty() or not plan.get("permit",false) or float(intent.get("validUntil",-1.0))<float(st.time):return {"ok":false,"reason":reason}
	var record: Dictionary=t.predictions.get(str(intent.get("pathFingerprint","")),{})
	var candidate: Dictionary=record.get("candidate",{})
	var window: Dictionary=record.get("certificate",{}).get("fireWindow",{})
	if not mount_id in candidate.get("fireMountIds",[]) or not mount_id in window.get("mountIds",[]) or float(st.time)<float(window.get("from",INF)) or float(st.time)>float(window.get("until",-INF)):return {"ok":false,"reason":"Waiting for a firing opportunity"}
	var req_targets: Dictionary=candidate.get("fireMountTargets",{}) if candidate.get("fireMountTargets") is Dictionary else {}
	var expected_target: String=str(req_targets.get(mount_id,candidate.get("targetId","")))
	if candidate.has("fireMountTargets") or window.has("mountTargets"):
		var w_targets: Dictionary=window.get("mountTargets",{}) if window.get("mountTargets") is Dictionary else {}
		if not w_targets.has(mount_id) or str(w_targets.get(mount_id,""))!=expected_target:return {"ok":false,"reason":"Waiting for a firing opportunity"}
	var order: String=str(ship.get("order","engage"))
	if order in ["move","withdraw","board"]:return {"ok":false,"reason":"Holding fire during maneuver"}
	if order=="attack":
		var ordered_id: String=str(ship.get("orderTarget",{}).get("shipId",""))
		if (not ordered_id.is_empty() and expected_target!=ordered_id) or candidate.has("fireMountTargets"):return {"ok":false,"reason":"Aligning with ordered target"}
	var choice: Dictionary=options.get("mounts",{}).get(mount_id,{})
	if bool(choice.get("hold",false)):return {"ok":false,"reason":"Automatic fire held"}
	if float(ship.ammo)-float(mount.ammoCost)<float(choice.get("reserve",0)):return {"ok":false,"reason":"Keeping working ammunition reserve"}
	if index<ship.weaponCooldowns.size() and float(ship.weaponCooldowns[index])>0.0:return {"ok":false,"reason":"Reloading"}
	if index==0 and float(ship.cooldown)>0.0:return {"ok":false,"reason":"Reloading"}
	if fixed(mount):
		if str(plan.get("leaseKind",""))!="salvo":return {"ok":false,"reason":"Waiting for a launch pass"}
		var pass_id: String=str(plan.get("firingPassId",""))
		var pass_state: Dictionary=t.passes.get(id,{})
		# A new candidate/fingerprint cannot reset real tube spending. Only an
		# observed breakaway/regroup transition or an explicit attack may do that.
		if pass_id.is_empty() or pass_id!=str(pass_state.get("id","")):return {"ok":false,"reason":"Waiting for a new launch pass"}
		var key: String=pass_key(id,mount_id,int(ship.get("orderRevision",0)),pass_id)
		if int(t.salvoSpent.get(key,0))>=mini(1,int(plan.get("shotLimit",0))):return {"ok":false,"reason":"Salvo spent; turning away"}
	else:
		if str(plan.get("leaseKind",""))!="continuous" or int(plan.get("shotLimit",0))<=0:return {"ok":false,"reason":"Automatic fire held"}
	if str(plan.get("targetId",""))!=expected_target or expected_target!=str(target.get("id","")):return {"ok":false,"reason":"Target unavailable"}
	return solution(st,ship,mount,target,budget,t.geometry,t.cells,true,false,frame_cache,ship_status)

static func _hull_radius(ship: Dictionary) -> float:
	return maxf(10.0,float(ship.spec.get("size",16)))

static func _crossing_time(origin: Vector2,velocity: Vector2,other: Dictionary,life: float,reach: float,body051=null) -> float:
	# Closest approach of the scattered shot and one hull, both at the velocities
	# observed now. Battle._projectiles uses this parameter, not circle entry, and
	# removes the shot there when it falls inside boat radius + shot radius.
	var other_point: Vector2=body051[1] if body051!=null else Routes.point(other)
	var other_velocity: Vector2=body051[2] if body051!=null else Vector2(float(other.vx),float(other.vy))
	var relative: Vector2=origin-other_point
	var closing: Vector2=velocity-other_velocity
	var speed2: float=closing.length_squared()
	if speed2<=0.000001:return 0.0 if relative.length()<reach else INF
	var time: float=clampf(-relative.dot(closing)/speed2,0.0,life)
	if (relative+closing*time).length()<reach:return time
	return INF

static func actual_lane(st: Dictionary,ship: Dictionary,mount: Dictionary,muzzle: Vector2,velocity: Vector2,radius: float) -> Dictionary:
	# One already-scattered velocity. Inherited shooter velocity is already inside
	# velocity. Horizon is projectile life, clipped to the earliest hostile approach
	# the live ray actually meets. A miss of every hostile keeps the full life.
	# Land or an ally past that hit is not swept. Pending does not fire.
	var t: Dictionary=st.get("tactical",{})
	var geometry: Dictionary=t.get("geometry",{})
	var cells: Dictionary=t.get("cells",{})
	var budget: Dictionary=t.get("budget",{})
	if not geometry.get("obstacles") is Array or budget.is_empty():return {"ok":false,"status":"pending","reason":"Checking projectile travel"}
	var life: float=float(mount.range)/maxf(0.001,float(mount.speed))
	var far: Vector2=muzzle+velocity*life
	var extra: float=maxf(0.0,life-2.0)*float(cells.get("_maxSpeed",0.0))+90.0
	var horizon: float=life
	var allies: Array=[]
	var numeric051: Routes._Numeric051=Routes._numeric_for051(cells,ship)
	for other in Routes.neighbours(cells,muzzle,far,extra):
		if str(other.id)==str(ship.id):continue
		if not Routes.spend(budget):return {"ok":false,"status":"pending","reason":"Checking projectile travel"}
		if other.team!=ship.team:
			var body051=Routes._numeric_body051(numeric051,other)
			var other_radius: float=float(body051[3]) if body051!=null else _hull_radius(other)
			horizon=minf(horizon,_crossing_time(muzzle,velocity,other,life,other_radius+radius,body051))
		else:allies.append(other)
	var finish: Vector2=muzzle+velocity*horizon
	var clear: String=Routes.sweep(geometry,muzzle,finish,radius,budget)
	if clear!="valid":return {"ok":false,"status":clear,"reason":"Checking projectile travel" if clear=="pending" else "Land blocks projectile travel"}
	for ally in allies:
		var body051=Routes._numeric_body051(numeric051,ally)
		var ally_radius: float=float(body051[3]) if body051!=null else _hull_radius(ally)
		if _crossing_time(muzzle,velocity,ally,horizon,radius+ally_radius+4.0,body051)<INF:return {"ok":false,"reason":"Ally in firing lane"}
	return {"ok":true,"reason":"Firing lane ready"}

static func emitted(st: Dictionary,ship: Dictionary,mount: Dictionary,intent: Dictionary,before: float,after: float) -> void:
	if after<=before or not fixed(mount):return
	var plan: Dictionary=intent.get("fireGate",{}).get(str(mount.id),{})
	var key: String=pass_key(str(ship.id),str(mount.id),int(ship.get("orderRevision",0)),str(plan.get("firingPassId","")))
	st.tactical.salvoSpent[key]=int(st.tactical.salvoSpent.get(key,0))+1
	var pass_state: Dictionary=st.tactical.passes.get(str(ship.id),{})
	pass_state.launchedAt=float(st.time);pass_state.launchPose=Routes.point(ship)
	st.tactical.passes[str(ship.id)]=pass_state

static func carry_revision(st: Dictionary,ship: Dictionary,old_revision: int) -> void:
	var id: String=str(ship.id)
	var current: Dictionary=st.tactical.passes.get(id,{})
	if current.is_empty():return
	for mount in st.tactical.mountCache.get(id,{}).get("mounts",[]):
		var old_key: String=pass_key(id,str(mount.id),old_revision,str(current.id))
		var new_key: String=pass_key(id,str(mount.id),int(ship.orderRevision),str(current.id))
		if st.tactical.salvoSpent.has(old_key):
			st.tactical.salvoSpent[new_key]=int(st.tactical.salvoSpent[old_key])
			st.tactical.salvoSpent.erase(old_key)
	current.revision=int(ship.orderRevision)
	st.tactical.passes[id]=current

static func accept_pass(st: Dictionary,ship: Dictionary,intent: Dictionary) -> void:
	var id: String=str(ship.id)
	var current: Dictionary=st.tactical.passes.get(id,{"id":"","phase":"","released":true,"revision":int(ship.get("orderRevision",0))})
	var phase: String=str(intent.get("phase",""))
	if phase in ["breakaway","turn-away","regroup","rally"]:
		if not current.has("breakPose"):
			current.breakPose=Routes.point(ship);current.breakAt=float(st.time)
		var origin: Vector2=current.get("launchPose",current.get("breakPose",Routes.point(ship)))
		if float(st.time)-float(current.get("breakAt",st.time))>=0.5 and Routes.point(ship).distance_to(origin)>=maxf(60.0,float(ship.spec.get("size",16))*2.0):current.released=true
	for value in intent.get("fireGate",{}).values():
		if str(value.get("leaseKind",""))!="salvo":continue
		var incoming: String=str(value.get("firingPassId",""))
		if not incoming.is_empty() and (str(current.get("id","")).is_empty() or (incoming!=str(current.id) and bool(current.get("released",false)))):
			current.id=incoming;current.released=false;current.revision=int(ship.get("orderRevision",0))
			current.erase("breakPose");current.erase("breakAt");current.erase("launchPose");current.erase("launchedAt")
		break
	current.phase=phase
	st.tactical.passes[id]=current
