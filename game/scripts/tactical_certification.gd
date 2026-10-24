extends RefCounted
## Full corridor geometry, two-second physical prefix, 0.2-second authority.
const Routes=preload("res://scripts/tactical_routes.gd")
const Fire=preload("res://scripts/tactical_fire_control.gd")
const Damage=preload("res://scripts/damage.gd")
const STEP: float=1.0/30.0

static func pose(ship: Dictionary) -> Dictionary:
	return {"x":float(ship.x),"y":float(ship.y),"vx":float(ship.vx),"vy":float(ship.vy),"angle":float(ship.angle)}

static func dynamics_key(ship: Dictionary) -> String:
	# Gradual bailing/repair is predicted, not byte-hashed into immutable inputs.
	return JSON.stringify([ship.spec.get("size",16),ship.spec.get("speed",90),ship.spec.get("turn",1.8),ship.spec.get("fuelUse",1),ship.spec.get("pumps",0),ship.spec.get("repairFactor",1),ship.get("supportRepairFactor",1),ship.crewMin,ship.crewOptimal,ship.capacity,ship.policy,ship.get("shoreCrew",0),float(ship.fuel)>0.0,float(ship.engine)>0.0,float(ship.crew)-float(ship.wounded)>=float(ship.crewMin)]).sha256_text()

static func capability(ship: Dictionary) -> Dictionary:
	var result: Dictionary={}
	var status: Dictionary=Damage.get_status(ship)
	for key in ["hp","water","engine","crew","wounded","fire"]:result[key]=float(ship[key])
	result.speedFactor=float(status.speedFactor);result.weaponFactor=float(status.weaponFactor)
	return result

static func motion(ship: Dictionary,dt: float,desired: float,throttle: float,boost: bool=false) -> Dictionary:
	# Shared by the real Battle._move and detached rollouts. Damage/cooldown are
	# advanced by Battle exactly once; a rollout never repairs or spends live stores.
	var angle: float=wrapf(float(ship.angle)+clampf(angle_difference(float(ship.angle),desired),-maxf(0.0,Damage.number(ship.spec.get("turn"),1.8))*dt,maxf(0.0,Damage.number(ship.spec.get("turn"),1.8))*dt),-PI,PI)
	var speed: float=maxf(0.0,Damage.number(ship.spec.get("speed"),90.0))*Damage.get_status(ship).speedFactor*(1.0 if float(ship.fuel)>0.0 else 0.2)*throttle*(1.2 if boost else 1.0)
	var velocity: Vector2=Vector2(ship.vx,ship.vy).lerp(Vector2.from_angle(angle)*speed,1.0-exp(-dt*4.0))
	var p: Vector2=Routes.point(ship)+velocity*dt
	var fuel: float=float(ship.fuel)
	if velocity.length()>5.0:fuel=maxf(0.0,fuel-dt*(0.018 if boost else 0.01)*maxf(0.0,Damage.number(ship.spec.get("fuelUse"),1.0)))
	return {"x":p.x,"y":p.y,"vx":velocity.x,"vy":velocity.y,"angle":angle,"fuel":fuel}

static func paths(candidate: Dictionary) -> Array:
	var result: Array=[]
	for leg in ["approach","pass","exit"]:result.append_array(candidate.get(leg,[]))
	return result

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

static func candidate_valid(candidate: Dictionary,view: Dictionary,ship: Dictionary) -> bool:
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
	if total>24 or not candidate.get("fireMountIds",[]) is Array:return false
	var ids: Dictionary={}
	for mount in ship.mounts:ids[str(mount.id)]=true
	for id in candidate.get("fireMountIds",[]):
		if not id is String or not ids.has(id):return false
	return true

static func base_certificate(view: Dictionary,ship: Dictionary,candidate: Dictionary,fingerprint: String) -> Dictionary:
	return {"status":"pending","reachable":false,"exitReachable":false,"eta":0.0,"fireWindow":{"from":float(view.time),"until":float(view.time),"mountIds":[]},"risk":1.0,"checkedAt":float(view.time),"validUntil":float(view.time),"snapshotRevision":int(view.snapshotRevision),"orderRevision":int(ship.get("orderRevision",0)),"pathFingerprint":fingerprint,"terrainRevision":view.terrainRevision,"geometryKey":JSON.stringify([view.terrainRevision,maxf(10.0,float(ship.spec.get("size",16)))]).sha256_text(),"checkedPose":pose(ship),"dynamicsKey":dynamics_key(ship),"physicalHorizonEnd":float(view.time),"rolloutSamples":0,"scope":"complete-geometry+prefix-physical","reason":"Checking a safe route"}

static func corridor(st: Dictionary,ship: Dictionary,candidate: Dictionary,budget: Dictionary) -> Dictionary:
	var points: Array=paths(candidate)
	var previous: Vector2=Routes.point(ship)
	var elapsed: float=0.0
	var speed: float=maxf(1.0,float(ship.spec.get("speed",90))*float(ship.status.speedFactor)*(1.0 if float(ship.fuel)>0.0 else 0.2)*0.8)
	var radius: float=maxf(10.0,float(ship.spec.get("size",16)))+4.0
	for goal in points:
		var result: String=Routes.sweep(st.tactical.geometry,previous,goal,radius,budget)
		if result!="valid":return {"status":result,"eta":elapsed,"reason":"Checking a safe route" if result=="pending" else "Land blocks this route"}
		var until: float=elapsed+previous.distance_to(goal)/speed
		result=Routes.occupied(st.tactical.cells,ship,previous,goal,radius,elapsed,until,budget)
		if result!="valid":return {"status":result,"eta":elapsed,"reason":"Checking allied traffic" if result=="pending" else "Ally occupies this approach"}
		elapsed=until;previous=goal
	return {"status":"valid","eta":elapsed,"reason":"Route clear"}

static func certify(st: Dictionary,view: Dictionary,ship: Dictionary,candidate: Dictionary,fingerprint: String,budget: Dictionary) -> Dictionary:
	var cert: Dictionary=base_certificate(view,ship,candidate,fingerprint)
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
	var copy: Dictionary=ship.duplicate(true)
	var points: Array=execution(candidate)
	var index: int=0
	var predicted: Array=[pose(copy)]
	var capabilities: Array=[capability(copy)]
	var target: Dictionary=st.tactical.observed.get(str(candidate.get("targetId","")),{})
	var chunk: Array=[Routes.point(copy)]
	var start_time: float=0.0
	for step in range(60):
		for _part in range(parts):
			var control: Dictionary=steering(copy,points,index,target,ship.mounts)
			index=int(control.index)
			var next: Dictionary=motion(copy,sub_dt,float(control.angle),float(control.throttle))
			copy.merge(next,true)
			budget.samples+=1
			predicted.append(pose(copy));chunk.append(Routes.point(copy))
			# Advance copied condition for the NEXT tick exactly as Battle's shared
			# damage prepass will. No live resources change. Capability tolerance below
			# is numerical error only; actual incoming hits are never predicted away.
			Damage.tick_ship(copy,sub_dt,{"inCombat":true})
			capabilities.append(capability(copy))
		cert.rolloutSamples+=1
		# A conservative capsule contains ALL ten integrated positions, including
		# curved turning and braking drift. Six swept envelopes cover the prefix.
		if (step+1)%10==0:
			var a: Vector2=chunk[0]
			var b: Vector2=chunk[-1]
			var radius: float=maxf(10.0,float(ship.spec.get("size",16)))+2.0
			var deviation: float=0.0
			for p in chunk:deviation=maxf(deviation,Routes.distance(p,a,b))
			radius+=deviation
			var result: String=Routes.sweep(st.tactical.geometry,a,b,radius,budget)
			if result=="valid":result=Routes.occupied(st.tactical.cells,ship,a,b,radius,start_time,float(step+1)*STEP,budget)
			if result!="valid":cert.status=result;cert.reason="Checking turning clearance" if result=="pending" else "Cannot turn or brake safely on this approach";return cert
			chunk=[b];start_time=float(step+1)*STEP
	# Firing access at the proposed station is geometric/observed prediction;
	# current live fire gates still require a fresh physical intercept every tick.
	var firing: Array=[]
	var arrival: float=0.0
	var current_window: bool=false
	# Route checks carry pending provenance from the active planning limit; a
	# failed budget debit is not evidence that a firing lane is obstructed.
	var fire_pending: bool=false
	if not candidate.get("fireMountIds",[]).is_empty() and not target.is_empty():
		var station: Vector2=Routes.point(ship)
		if not candidate.get("approach",[]).is_empty():station=candidate.approach[-1]
		arrival=Routes.point(ship).distance_to(station)/maxf(1.0,float(ship.spec.get("speed",90))*float(ship.status.speedFactor))
		var at_station: Dictionary=ship.duplicate(true)
		at_station.x=station.x;at_station.y=station.y
		for mount in ship.mounts:
			if not str(mount.id) in candidate.fireMountIds:continue
			var now_shot: Dictionary=Fire.solution(st,ship,mount,target,budget,st.tactical.geometry,st.tactical.cells,true,true)
			if now_shot.ok:current_window=true
			elif str(now_shot.get("status",""))=="pending":fire_pending=true
			at_station.angle=(Routes.point(target)-station).angle()-float(mount.angle)
			var shot: Dictionary=Fire.solution(st,at_station,mount,target,budget,st.tactical.geometry,st.tactical.cells,true,true)
			if shot.ok:firing.append(str(mount.id))
			elif str(shot.get("status",""))=="pending":fire_pending=true
		if firing.is_empty():
			cert.status="pending" if fire_pending else "blocked"
			cert.reason="Checking firing lanes" if cert.status=="pending" else "No usable firing lane at this station"
			return cert
	cert.status="valid";cert.reachable=true;cert.exitReachable=true
	cert.validUntil=float(view.time)+0.2;cert.physicalHorizonEnd=float(view.time)+2.0
	cert.fireWindow={"from":float(view.time)+arrival,"until":float(view.time)+arrival+1.2 if not firing.is_empty() else float(view.time)+arrival,"mountIds":firing}
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
	var r: float=maxf(10.0,float(ship.spec.get("size",16)))+2.0
	var clear: String=Routes.sweep(st.tactical.geometry,Routes.point(ship),Routes.point(next),r,budget)
	if clear=="valid":clear=Routes.occupied(st.tactical.cells,ship,Routes.point(ship),Routes.point(next),r,0.0,float(st.tactical.dt),budget)
	if clear=="valid":return control
	return {"angle":float(ship.angle),"throttle":0.0,"reason":"Braking; checking clearance" if clear=="pending" else "Braking for land or allied traffic","blocked":true}

static func brake(st: Dictionary,ship: Dictionary,budget: Dictionary,reason: String) -> Dictionary:
	var control: Dictionary={"angle":float(ship.angle),"throttle":0.0,"reason":reason}
	var checked: Dictionary=safe_step(st,ship,control,budget)
	if checked.get("blocked",false):checked.reason=reason+"; braking drift is obstructed"
	return checked
