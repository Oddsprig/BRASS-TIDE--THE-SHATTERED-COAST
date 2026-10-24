extends RefCounted
## Current physical solutions and battle-local, persistent salvo spending.
const Routes=preload("res://scripts/tactical_routes.gd")
const Damage=preload("res://scripts/damage.gd")

static func fixed(mount: Dictionary) -> bool:
	return str(mount.kind) in ["rocket","torpedo"] and float(mount.arc)<PI*0.75

static func intercept(ship: Dictionary,mount: Dictionary,target: Dictionary) -> Dictionary:
	var origin: Vector2=Routes.point(ship)+Vector2(mount.x,mount.y).rotated(float(ship.angle))
	var delta: Vector2=Routes.point(target)-origin
	var velocity: Vector2=Vector2(target.vx,target.vy)-Vector2(ship.vx,ship.vy)*0.2
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
	var aim: Vector2=Routes.point(target)+velocity*time
	if (aim-origin).length()>float(mount.range):return {"ok":false,"reason":"Target is outside fitted range"}
	var bearing: float=(aim-origin).angle()
	if absf(angle_difference(float(ship.angle)+float(mount.angle),bearing))>float(mount.arc)*0.5+0.00001:return {"ok":false,"reason":"Aligning weapon"}
	var radius: float=5.0 if mount.kind=="torpedo" else (3.0 if mount.kind=="rocket" else 2.0)
	return {"ok":true,"reason":"Firing lane ready","aim":aim,"origin":origin,"muzzle":origin+Vector2.from_angle(bearing)*float(mount.muzzleDistance),"bearing":bearing,"time":time,"radius":radius}

static func solution(st: Dictionary,ship: Dictionary,mount: Dictionary,target: Dictionary,budget: Dictionary,geometry: Dictionary,cells: Dictionary,check_stores: bool=true,ignore_projectile_cap: bool=false) -> Dictionary:
	if target.is_empty() or target.get("sunk",false) or target.get("captureSecured",false) or target.team==ship.team:return {"ok":false,"reason":"Target unavailable"}
	if check_stores:
		if not ignore_projectile_cap and st.get("projectiles",[]).size()>=400:return {"ok":false,"reason":"Waiting for a clear firing cycle"}
		if float(ship.ammo)<float(mount.ammoCost):return {"ok":false,"reason":"Out of ammunition"}
		if Damage.get_status(ship).weaponFactor<=0.01:return {"ok":false,"reason":"Guns need working crew"}
	var shot: Dictionary=intercept(ship,mount,target)
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
		var relative: Vector2=shot.muzzle-Routes.point(ally)
		var travel: Vector2=(finish-shot.muzzle)-Vector2(ally.vx,ally.vy)*float(shot.time)
		var t: float=clampf(-relative.dot(travel)/maxf(0.000001,travel.length_squared()),0.0,1.0)
		if (relative+travel*t).length()<float(shot.radius)+maxf(10.0,float(ally.spec.get("size",16)))+4.0:return {"ok":false,"reason":"Ally in firing lane"}
	return shot

static func pass_key(ship_id: String,mount_id: String,revision: int,pass_id: String) -> String:
	return JSON.stringify([ship_id,mount_id,revision,pass_id]).sha256_text()

static func gate(st: Dictionary,ship: Dictionary,mount: Dictionary,index: int,intent: Dictionary,options: Dictionary,target: Dictionary,budget: Dictionary) -> Dictionary:
	var t: Dictionary=st.tactical
	var id: String=str(ship.id)
	var mount_id: String=str(mount.id)
	var plan: Dictionary=intent.get("fireGate",{}).get(mount_id,{})
	var reason: String=str(plan.get("reason","Waiting for a firing opportunity"))
	if plan.is_empty() or not plan.get("permit",false) or float(intent.get("validUntil",-1.0))<float(st.time):return {"ok":false,"reason":reason}
	var window: Dictionary=t.predictions.get(str(intent.get("pathFingerprint","")),{}).get("certificate",{}).get("fireWindow",{})
	if not mount_id in window.get("mountIds",[]) or float(st.time)<float(window.get("from",INF)) or float(st.time)>float(window.get("until",-INF)):return {"ok":false,"reason":"Waiting for a firing opportunity"}
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
	if str(plan.get("targetId",""))!=str(target.get("id","")):return {"ok":false,"reason":"Target unavailable"}
	return solution(st,ship,mount,target,budget,t.geometry,t.cells)

static func manual_lane(st: Dictionary,ship: Dictionary,mount: Dictionary,muzzle: Vector2,bearing: float) -> bool:
	# Direct aim is authoritative; crew/arc/terrain checks live in Battle._fire.
	# Its complete real projectile travel must still keep allies out of the lane.
	var life: float=float(mount.range)/float(mount.speed)
	var travel: Vector2=(Vector2.from_angle(bearing)*float(mount.speed)+Vector2(ship.vx,ship.vy)*0.2)*life
	for ally in st.get("ships",[]):
		if ally.get("sunk",false) or ally.get("captureSecured",false) or ally.team!=ship.team or str(ally.id)==str(ship.id):continue
		var relative: Vector2=muzzle-Routes.point(ally)
		var delta: Vector2=travel-Vector2(ally.vx,ally.vy)*life
		var at: float=clampf(-relative.dot(delta)/maxf(0.000001,delta.length_squared()),0.0,1.0)
		if (relative+delta*at).length()<maxf(10.0,float(ally.spec.get("size",16)))+float(5 if mount.kind=="torpedo" else 3):return false
	return true

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
