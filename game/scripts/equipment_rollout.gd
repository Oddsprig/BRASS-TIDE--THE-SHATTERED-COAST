extends RefCounted
## Closed synchronous private prefix. No context is returned, stored or resumed.
## Public math wrappers and this prefix share the same numerical helpers.
const Routes=preload("res://scripts/tactical_routes.gd")
const Damage=preload("res://scripts/damage.gd")
const EquipmentDamage=preload("res://scripts/equipment_damage.gd")
const EquipmentCombat=preload("res://scripts/equipment_combat.gd")
const STEP: float=1.0/30.0
const HULL_CLEARANCE_MARGIN: float=4.0

static func pose(ship: Dictionary) -> Dictionary:
	return {"x":float(ship.x),"y":float(ship.y),"vx":float(ship.vx),"vy":float(ship.vy),"angle":float(ship.angle)}

static func execution(candidate: Dictionary) -> Array:
	# Exit geometry is reserved and checked; the planner must explicitly enter a
	# breakaway/regroup phase before a newly certified exit becomes helm authority.
	var result: Array=candidate.get("approach",[]).duplicate()
	result.append_array(candidate.get("pass",[]))
	return result

static func steering(ship: Dictionary,points: Array,index: int,target: Dictionary={},mounts: Array=[]) -> Dictionary:
	var at: int=index
	var p: Vector2=Routes.point(ship)
	while at<points.size() and p.distance_to(points[at])<14.0:at+=1
	var heading: float=float(ship.angle)
	var throttle: float=0.0
	if at<points.size():
		var delta: Vector2=points[at]-p
		heading=delta.angle()
		var turn: float=absf(angle_difference(float(ship.angle),heading))
		throttle=clampf(delta.length()/140.0,0.2,0.95)*clampf(cos(turn),0.12,1.0)
	else:
		var weight: float=-1.0
		for mount in mounts:
			if target.is_empty() or float(ship.ammo)<float(mount.ammoCost):continue
			var value: float=float(mount.damage)*float(mount.fireRate)
			if value<=weight:continue
			weight=value
			var bearing: float=(Routes.point(target)-p).angle()
			heading=bearing-float(mount.angle) if float(mount.arc)<TAU-0.01 else bearing
	return {"angle":heading,"throttle":throttle,"index":at}

static func mount_target(candidate: Dictionary,mount_id: String) -> String:
	var map: Dictionary=candidate.get("fireMountTargets",{}) if candidate.get("fireMountTargets") is Dictionary else {}
	if map.has(mount_id):return str(map[mount_id])
	return str(candidate.get("targetId",""))

static func primary_mounts(mounts: Array,candidate: Dictionary) -> Array:
	if not candidate.has("fireMountTargets") or not candidate.get("fireMountTargets") is Dictionary:
		return mounts
	var fire_ids: Array=candidate.get("fireMountIds",[]) if candidate.get("fireMountIds") is Array else []
	var primary_id: String=str(candidate.get("targetId",""))
	var filtered: Array=[]
	for mount in mounts:
		var mid: String=str(mount.id)
		if (fire_ids.is_empty() or mid in fire_ids) and mount_target(candidate,mid)==primary_id:
			filtered.append(mount)
	return filtered if not filtered.is_empty() else mounts

static func motion_with_status(ship: Dictionary,dt: float,desired: float,throttle: float,boost: bool,status: Dictionary) -> Dictionary:
	# Shared by the real Battle._move and detached rollouts. Damage/cooldown are
	# advanced by Battle exactly once; a rollout never repairs or spends live stores.
	if not bool(status.get("equipmentOk",true)):
		return {"x":float(ship.x),"y":float(ship.y),"vx":0.0,"vy":0.0,"angle":float(ship.angle),"fuel":float(ship.fuel)}
	var turn_rate: float=maxf(0.0,Damage.number(ship.spec.get("turn"),1.8))*clampf(Damage.number(status.get("turnFactor"),1.0),0.0,1.0)
	var angle: float=wrapf(float(ship.angle)+clampf(angle_difference(float(ship.angle),desired),-turn_rate*dt,turn_rate*dt),-PI,PI)
	var speed: float=maxf(0.0,Damage.number(ship.spec.get("speed"),90.0))*float(status.speedFactor)*(1.0 if float(ship.fuel)>0.0 else 0.2)*throttle*(1.2 if boost else 1.0)
	var velocity: Vector2=Vector2(ship.vx,ship.vy).lerp(Vector2.from_angle(angle)*speed,1.0-exp(-dt*4.0))
	var p: Vector2=Routes.point(ship)+velocity*dt
	var fuel: float=float(ship.fuel)
	if velocity.length()>5.0:fuel=maxf(0.0,fuel-dt*(0.018 if boost else 0.01)*maxf(0.0,Damage.number(ship.spec.get("fuelUse"),1.0)))
	return {"x":p.x,"y":p.y,"vx":velocity.x,"vy":velocity.y,"angle":angle,"fuel":fuel}

static func capability_with_status(ship: Dictionary,status: Dictionary,mask_override: float=NAN) -> Dictionary:
	# Only certify's private copy can reuse the final status from its last tick.
	# Direct scalars and module HP are still read from that copy at this sample.
	return _capability_from_fields(ship,status,EquipmentCombat.capability_fields(ship,status,mask_override))

static func _capability_from_fields(ship: Dictionary,status: Dictionary,fields: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key in ["hp","water","engine","crew","wounded","fire"]:result[key]=float(ship[key])
	result.speedFactor=float(status.speedFactor);result.weaponFactor=float(status.weaponFactor)
	result.merge(fields,true)
	return result

static func prefix(st: Dictionary,ship: Dictionary,candidate: Dictionary,budget: Dictionary,cert: Dictionary,sub_dt: float,parts: int) -> Dictionary:
	var id: String=str(ship.id)
	var live_ship: Dictionary=st.get("tactical",{}).get("ships",{}).get(id,ship)
	var copy: Dictionary=live_ship.duplicate(true)
	copy.mounts=ship.mounts.duplicate(true)
	# Local to this synchronous private rollout. Never store it on a live ship,
	# prediction record or across calls; Damage still validates every real tick.
	var rollout_status: Dictionary=Damage.get_status(copy)
	var is_canonical: bool=str(rollout_status.get("equipmentMode",""))=="canonical"
	var init_mask: float=EquipmentCombat.working_mask(copy,rollout_status) if is_canonical else NAN
	var fixed_inputs: Dictionary=_fixed_inputs(copy) if is_canonical else {}
	var points: Array=execution(candidate)
	var index: int=0
	var predicted: Array=[pose(copy)]
	var capabilities: Array=[(_capability_from_fields(copy,rollout_status,EquipmentCombat._canonical_capability_fields(copy,rollout_status,init_mask)) if is_canonical else capability_with_status(copy,rollout_status,init_mask))]
	var target: Dictionary=st.tactical.observed.get(str(candidate.get("targetId","")),{})
	var primary: Array=primary_mounts(copy.mounts,candidate)
	var chunk: Array=[Routes.point(copy)]
	var start_time: float=0.0
	for step in range(60):
		for _part in range(parts):
			var control: Dictionary=steering(copy,points,index,target,primary)
			index=int(control.index)
			var next: Dictionary=motion_with_status(copy,sub_dt,float(control.angle),float(control.throttle),false,rollout_status)
			copy.merge(next,true)
			budget.samples+=1
			predicted.append(pose(copy));chunk.append(Routes.point(copy))
			# Advance copied condition for the NEXT tick exactly as Battle's shared
			# damage prepass will. No live resources change. Capability tolerance below
			# is numerical error only; actual incoming hits are never predicted away.
			# The returned factors describe the final post-tick state. Its inflow,
			# bailing and repair may be averages; none of these consumers use them.
			rollout_status=Damage._tick_canonical_numeric(copy,sub_dt,{"inCombat":true}) if is_canonical else Damage.tick_ship(copy,sub_dt,{"inCombat":true})
			if is_canonical:
				copy.mounts=EquipmentCombat._condition_mounts_from_status(copy,copy.mounts,rollout_status)
				primary=primary_mounts(copy.mounts,candidate)
			capabilities.append(_capability_from_fields(copy,rollout_status,EquipmentCombat._canonical_capability_fields(copy,rollout_status,init_mask)) if is_canonical else capability_with_status(copy,rollout_status,init_mask))
		cert.rolloutSamples+=1
		# A conservative capsule contains ALL ten integrated positions, including
		# curved turning and braking drift. Six swept envelopes cover the prefix.
		if (step+1)%10==0:
			var a: Vector2=chunk[0]
			var b: Vector2=chunk[-1]
			var radius: float=maxf(10.0,float(ship.spec.get("size",16)))+HULL_CLEARANCE_MARGIN
			var deviation: float=0.0
			for p in chunk:deviation=maxf(deviation,Routes.distance(p,a,b))
			radius+=deviation
			var result: String=Routes.sweep(st.tactical.geometry,a,b,radius,budget)
			if result=="valid":result=Routes.occupied(st.tactical.cells,ship,a,b,radius,start_time,float(step+1)*STEP,budget)
			if result!="valid":cert.status=result;cert.reason="Checking turning clearance" if result=="pending" else "Cannot turn or brake safely on this approach";return {"ok":false}
			chunk=[b];start_time=float(step+1)*STEP
	if is_canonical:
		var final_info: Dictionary=EquipmentDamage.inspect_owner(copy)
		if not final_info.get("ok",false) or str(final_info.get("mode",""))!="canonical" or var_to_bytes(_fixed_inputs(copy))!=var_to_bytes(fixed_inputs):
			cert.status="blocked";cert.reason="Equipment input changed; reassessing"
			return {"ok":false}
	return {"ok":true,"poses":predicted,"capabilities":capabilities,"primary":primary}

static func _fixed_inputs(ship: Dictionary) -> Dictionary:
	var condition: Dictionary=ship.get("moduleCondition",{}).duplicate(true)
	condition.erase("legacyEngineSynced")
	for item in condition.get("items",{}).values():
		for key in ["hp","status","cause"]: item.erase(key)
	var fixed: Dictionary={"condition":condition}
	for key in ["spec","baseSpec","loadout","uid","id","type","team","crewMin","crewOptimal","crewMax","capacity","maxHp","policy","supportRepairFactor","shoreCrew"]:
		if ship.has(key): fixed[key]=ship[key].duplicate(true) if ship[key] is Dictionary or ship[key] is Array else ship[key]
	return fixed
