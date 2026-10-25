extends RefCounted
## Full corridor geometry, two-second physical prefix, 0.2-second authority.
const Routes=preload("res://scripts/tactical_routes.gd")
const Fire=preload("res://scripts/tactical_fire_control.gd")
const Damage=preload("res://scripts/damage.gd")
const Roles=preload("res://scripts/tactical_role_plans.gd")
const EquipmentCombat=preload("res://scripts/equipment_combat.gd")
const EquipmentRollout=preload("res://scripts/equipment_rollout.gd")
const STEP: float=1.0/30.0
# Routes.occupied adds the other hull's radius+3. Match the full corridor's
# seven-unit allied margin in actual curved prefixes and the final live step.
const HULL_CLEARANCE_MARGIN: float=4.0

static func pose(ship: Dictionary) -> Dictionary:
	return EquipmentRollout.pose(ship)

static func dynamics_key(ship: Dictionary) -> String:
	# Gradual bailing/repair is predicted, not byte-hashed into immutable inputs.
	return JSON.stringify([ship.spec.get("size",16),ship.spec.get("speed",90),ship.spec.get("turn",1.8),ship.spec.get("fuelUse",1),ship.spec.get("pumps",0),ship.spec.get("repairFactor",1),ship.get("supportRepairFactor",1),ship.crewMin,ship.crewOptimal,ship.capacity,ship.policy,ship.get("shoreCrew",0),float(ship.fuel)>0.0,float(ship.engine)>0.0,float(ship.crew)-float(ship.wounded)>=float(ship.crewMin)]).sha256_text()

static func capability(ship: Dictionary,mask_override: float=NAN) -> Dictionary:
	return _capability_with_status(ship,Damage.get_status(ship),mask_override)

static func _capability_with_status(ship: Dictionary,status: Dictionary,mask_override: float=NAN) -> Dictionary:
	return EquipmentRollout.capability_with_status(ship,status,mask_override)

static func motion(ship: Dictionary,dt: float,desired: float,throttle: float,boost: bool=false) -> Dictionary:
	return _motion_with_status(ship,dt,desired,throttle,boost,Damage.get_status(ship))

static func _motion_with_status(ship: Dictionary,dt: float,desired: float,throttle: float,boost: bool,status: Dictionary) -> Dictionary:
	return EquipmentRollout.motion_with_status(ship,dt,desired,throttle,boost,status)

static func paths(candidate: Dictionary) -> Array:
	var result: Array=[]
	for leg in ["approach","pass","exit"]:result.append_array(candidate.get(leg,[]))
	return result

static func execution(candidate: Dictionary) -> Array:
	return EquipmentRollout.execution(candidate)

static func steering(ship: Dictionary,points: Array,index: int,target: Dictionary={},mounts: Array=[]) -> Dictionary:
	return EquipmentRollout.steering(ship,points,index,target,mounts)

static func mount_target(candidate: Dictionary,mount_id: String) -> String:
	return EquipmentRollout.mount_target(candidate,mount_id)

static func primary_mounts(mounts: Array,candidate: Dictionary) -> Array:
	return EquipmentRollout.primary_mounts(mounts,candidate)

static func detailed_targets(view: Dictionary,ship: Dictionary,previous: Dictionary={}) -> Array:
	var context: Dictionary=Roles.ships_by_id(view)
	var protected: Dictionary=Roles.protected_ally(view,ship,previous,context)
	var ids: Array=[]
	for entry in Roles.shortlist(view,ship,context,protected):ids.append(str(entry.id))
	return ids

static func candidate_valid(candidate: Dictionary,view: Dictionary,ship: Dictionary,membership: Array=[]) -> bool:
	for field in ["candidateId","shipId","targetId","leaderId","role"]:
		if not candidate.get(field,"") is String or str(candidate.get(field,"")).length()>128:return false
	if str(candidate.get("candidateId","")).is_empty() or str(candidate.get("shipId",""))!=str(ship.id) or not str(ship.id) in view.dueIds:return false
	if int(candidate.get("orderRevision",-1))!=int(ship.get("orderRevision",0)) or int(candidate.get("snapshotRevision",-1))!=int(view.snapshotRevision):return false
	var total: int=0
	for leg in ["approach","pass","exit"]:
		if not candidate.get(leg) is Array or candidate[leg].size()>8:return false
		for p in candidate[leg]:
			if not p is Vector2 or not p.is_finite():return false
		total+=candidate[leg].size()
	if total>24 or not candidate.get("fireMountIds",[]) is Array or candidate.fireMountIds.size()>16:return false
	var ids: Dictionary={}
	for mount in ship.mounts:ids[str(mount.id)]=true
	var fire_set: Dictionary={}
	for id in candidate.get("fireMountIds",[]):
		if not id is String or not ids.has(id) or fire_set.has(id):return false
		fire_set[id]=true
	var hostiles: Dictionary={}
	for raw in view.get("ships",[]):
		if raw is Dictionary and str(raw.get("team",""))!=str(ship.get("team","")) and not raw.get("sunk",false) and not raw.get("captureSecured",false):
			hostiles[str(raw.get("id",""))]=true
	# Runtime independently builds this position-only set once per due hull,
	# before any candidate can spend route, rollout or ballistic work.
	var detailed: Array=membership if not membership.is_empty() else detailed_targets(view,ship)
	if detailed.size()>16:return false
	if not candidate.fireMountIds.is_empty() and (not hostiles.has(str(candidate.get("targetId",""))) or not str(candidate.targetId) in detailed):
		return false
	if candidate.has("fireMountTargets"):
		if not candidate.get("fireMountTargets") is Dictionary:return false
		var map: Dictionary=candidate.fireMountTargets
		if map.is_empty() or map.size()>candidate.fireMountIds.size() or map.size()>16 or candidate.fireMountIds.is_empty() or str(candidate.get("targetId","")).is_empty():
			return false
		var distinct: Dictionary={str(candidate.get("targetId","")):true}
		for mount_id in map:
			if not mount_id is String or mount_id.length()>128 or not fire_set.has(mount_id):return false
			var tid=map[mount_id]
			if not tid is String or tid.is_empty() or tid.length()>128 or not hostiles.has(tid) or not tid in detailed:return false
			distinct[tid]=true
		if distinct.size()>4:return false
	return true

static func base_certificate(view: Dictionary,ship: Dictionary,candidate: Dictionary,fingerprint: String) -> Dictionary:
	return {"status":"pending","reachable":false,"exitReachable":false,"eta":0.0,"fireWindow":{"from":float(view.time),"until":float(view.time),"mountIds":[],"mountTargets":{}},"risk":1.0,"checkedAt":float(view.time),"validUntil":float(view.time),"snapshotRevision":int(view.snapshotRevision),"orderRevision":int(ship.get("orderRevision",0)),"pathFingerprint":fingerprint,"terrainRevision":view.terrainRevision,"geometryKey":JSON.stringify([view.terrainRevision,maxf(10.0,float(ship.spec.get("size",16)))]).sha256_text(),"checkedPose":pose(ship),"dynamicsKey":dynamics_key(ship),"physicalHorizonEnd":float(view.time),"rolloutSamples":0,"scope":"complete-geometry+prefix-physical","reason":"Checking a safe route"}

static func corridor(st: Dictionary,ship: Dictionary,candidate: Dictionary,budget: Dictionary) -> Dictionary:
	var points: Array=paths(candidate)
	var previous: Vector2=Routes.point(ship)
	var elapsed: float=0.0
	var speed: float=maxf(1.0,float(ship.spec.get("speed",90))*float(ship.status.speedFactor)*(1.0 if float(ship.fuel)>0.0 else 0.2)*0.8)
	var radius: float=maxf(10.0,float(ship.spec.get("size",16)))+HULL_CLEARANCE_MARGIN
	for goal in points:
		var result: String=Routes.sweep(st.tactical.geometry,previous,goal,radius,budget)
		if result!="valid":return {"status":result,"eta":elapsed,"reason":"Checking a safe route" if result=="pending" else "Land blocks this route"}
		var until: float=elapsed+previous.distance_to(goal)/speed
		result=Routes.occupied(st.tactical.cells,ship,previous,goal,radius,elapsed,until,budget)
		if result!="valid":return {"status":result,"eta":elapsed,"reason":"Checking allied traffic" if result=="pending" else "Ally occupies this approach"}
		elapsed=until;previous=goal
	return {"status":"valid","eta":elapsed,"reason":"Route clear"}

static func certify(st: Dictionary,view: Dictionary,ship: Dictionary,candidate: Dictionary,fingerprint: String,budget: Dictionary,membership: Array=[]) -> Dictionary:
	var cert: Dictionary=base_certificate(view,ship,candidate,fingerprint)
	if not candidate_valid(candidate,view,ship,membership):
		cert.status="blocked";cert.reason="Weapon assignment outside bounded observed targets";return cert
	var full: Dictionary=corridor(st,ship,candidate,budget)
	cert.eta=full.eta
	if full.status!="valid":cert.status=full.status;cert.reason=full.reason;return cert
	var id: String=str(ship.id)
	# Physics is 60Hz and Battle.update keeps that dt. A 30Hz sample rounded to
	# the nearest pose is already a full step ahead after one 1/60 tick, so the
	# velocity check fails and helm brakes. Two closed-loop half-steps still
	# publish exactly 60 samples across the required 2s prefix. Any other dt
	# keeps the single 1/30 sample, which matches a 1/30 caller exactly.
	var sub_dt: float=float(st.tactical.get("dt",STEP))
	var parts: int=1
	if absf(sub_dt*2.0-STEP)<0.0000001:
		parts=2
	else:
		sub_dt=STEP
	if budget.rolled.has(id) or int(budget.rollouts)>=16 or int(budget.samples)+60*parts>840:
		budget.exhaustions+=1;cert.reason="Checking the next safe maneuver";return cert
	budget.rolled[id]=true;budget.rollouts+=1
	var live_ship: Dictionary=st.get("tactical",{}).get("ships",{}).get(id,ship)
	var prefix: Dictionary=EquipmentRollout.prefix(st,ship,candidate,budget,cert,sub_dt,parts)
	if not prefix.ok:return cert
	var predicted: Array=prefix.poses
	var capabilities: Array=prefix.capabilities
	var primary: Array=prefix.primary
	var target: Dictionary=st.tactical.observed.get(str(candidate.get("targetId","")),{})
	# Firing access at the proposed station is geometric/observed prediction;
	# current live fire gates still require a fresh physical intercept every tick.
	var firing: Array=[]
	var certified_targets: Dictionary={}
	var arrival: float=0.0
	var current_window: bool=false
	var station_window: bool=false
	# Route checks carry pending provenance from the active planning limit; a
	# failed budget debit is not evidence that a firing lane is obstructed.
	var fire_pending: bool=false
	if not candidate.get("fireMountIds",[]).is_empty() and not target.is_empty():
		var station: Vector2=Routes.point(ship)
		if not candidate.get("approach",[]).is_empty():station=candidate.approach[-1]
		arrival=Routes.point(ship).distance_to(station)/maxf(1.0,float(ship.spec.get("speed",90))*float(ship.status.speedFactor))
		var at_station: Dictionary=live_ship.duplicate(true)
		at_station.mounts=ship.mounts.duplicate(true)
		at_station.x=station.x;at_station.y=station.y
		if Routes.point(ship).distance_to(station)<14.0:
			at_station.angle=float(predicted[-1].angle)
		else:
			at_station.angle=wrapf(float(steering(at_station,[],0,target,primary).angle),-PI,PI)
		for mount in ship.mounts:
			var mount_id: String=str(mount.id)
			if not mount_id in candidate.fireMountIds:continue
			var mount_target_id: String=mount_target(candidate,mount_id)
			var mount_target_ship: Dictionary=st.tactical.observed.get(mount_target_id,{})
			var now_shot: Dictionary=Fire.solution(st,live_ship,mount,mount_target_ship,budget,st.tactical.geometry,st.tactical.cells,true,true)
			if now_shot.ok:current_window=true
			elif str(now_shot.get("status",""))=="pending":fire_pending=true
			var shot: Dictionary=Fire.solution(st,at_station,mount,mount_target_ship,budget,st.tactical.geometry,st.tactical.cells,true,true)
			if shot.ok:station_window=true
			elif str(shot.get("status",""))=="pending":fire_pending=true
			if now_shot.ok or shot.ok:
				firing.append(mount_id)
				certified_targets[mount_id]=mount_target_id
		if firing.is_empty():
			cert.status="pending" if fire_pending else "blocked"
			cert.reason="Checking firing lanes" if cert.status=="pending" else "No usable firing lane at this station"
			return cert
	cert.status="valid";cert.reachable=true;cert.exitReachable=true
	cert.validUntil=float(view.time)+0.2;cert.physicalHorizonEnd=float(view.time)+2.0
	cert.fireWindow={"from":float(view.time)+arrival,"until":float(view.time)+arrival+(1.2 if station_window else 0.0),"mountIds":firing,"mountTargets":certified_targets}
	cert.risk=clampf(float(ship.water)/maxf(1.0,float(ship.capacity)),0.0,1.0)
	cert.reason="Route and immediate maneuver checked"
	if current_window:cert.fireWindow["from"]=float(view.time);cert.fireWindow.until=maxf(float(view.time)+0.2,float(cert.fireWindow.until))
	var motion_key: String=dynamics_key(ship)
	cert.dynamicsKey=JSON.stringify([motion_key,capabilities]).sha256_text()
	st.tactical.predictions[fingerprint]={"poses":predicted,"capabilities":capabilities,"motionKey":motion_key,"sampleDt":sub_dt,"candidate":candidate.duplicate(true),"certificate":cert.duplicate(true)}
	return cert

static func current(st: Dictionary,ship: Dictionary,intent: Dictionary,pose_offset: float=0.0) -> Dictionary:
	if intent.is_empty():return {"ok":false,"reason":"Choosing a safe maneuver"}
	var record: Dictionary=st.tactical.predictions.get(str(intent.get("pathFingerprint","")),{})
	if record.is_empty():return {"ok":false,"reason":"Checking the next safe maneuver"}
	var cert: Dictionary=record.certificate
	if str(cert.status)!="valid" or float(st.time)>minf(float(cert.validUntil),float(intent.get("validUntil",-1)))+0.0000001:return {"ok":false,"reason":"Checking the next safe maneuver"}
	if str(intent.get("candidateId",""))!=str(record.candidate.candidateId) or int(intent.get("snapshotRevision",-1))!=int(cert.snapshotRevision) or int(intent.get("orderRevision",-1))!=int(ship.get("orderRevision",0)):return {"ok":false,"reason":"Following the new order"}
	if st.tactical.terrainRevision!=cert.terrainRevision or dynamics_key(ship)!=str(record.motionKey):return {"ok":false,"reason":"Conditions changed; checking maneuver"}
	var age: float=maxf(0.0,float(st.time)-float(cert.checkedAt))
	var sample_dt: float=float(record.get("sampleDt",STEP))
	if sample_dt<=0.0:sample_dt=STEP
	var at: int=clampi(roundi((age+pose_offset)/sample_dt),0,record.poses.size()-1)
	var predicted: Dictionary=record.poses[at]
	if Routes.point(ship).distance_to(Routes.point(predicted))>2.0 or Vector2(ship.vx,ship.vy).distance_to(Vector2(predicted.vx,predicted.vy))>2.0 or absf(angle_difference(float(ship.angle),float(predicted.angle)))>deg_to_rad(1.0):return {"ok":false,"reason":"Traffic changed; checking approach"}
	# Fire follows this tick's movement before the next damage prepass. Its
	# capability belongs to age, while its position belongs to age+dt.
	var condition_at: int=clampi(roundi(age/sample_dt),0,record.capabilities.size()-1)
	var actual: Dictionary=capability(ship)
	var expected: Dictionary=record.capabilities[condition_at]
	for key in expected:
		if absf(float(actual[key])-float(expected[key]))>0.0001:return {"ok":false,"reason":"Damage or capability changed; reassessing"}
	return {"ok":true,"reason":str(intent.get("reason","Following maneuver")),"record":record}

static func safe_step(st: Dictionary,ship: Dictionary,control: Dictionary,budget: Dictionary) -> Dictionary:
	var next: Dictionary=motion(ship,float(st.tactical.dt),float(control.angle),float(control.throttle))
	var r: float=maxf(10.0,float(ship.spec.get("size",16)))+HULL_CLEARANCE_MARGIN
	var clear: String=Routes.sweep(st.tactical.geometry,Routes.point(ship),Routes.point(next),r,budget)
	if clear=="valid":clear=Routes.occupied(st.tactical.cells,ship,Routes.point(ship),Routes.point(next),r,0.0,float(st.tactical.dt),budget)
	if clear=="valid":return control
	return {"angle":float(ship.angle),"throttle":0.0,"reason":"Braking; checking clearance" if clear=="pending" else "Braking for land or allied traffic","blocked":true}

static func brake(st: Dictionary,ship: Dictionary,budget: Dictionary,reason: String) -> Dictionary:
	var control: Dictionary={"angle":float(ship.angle),"throttle":0.0,"reason":reason}
	var checked: Dictionary=safe_step(st,ship,control,budget)
	if checked.get("blocked",false):checked.reason=reason+"; braking drift is obstructed"
	return checked
