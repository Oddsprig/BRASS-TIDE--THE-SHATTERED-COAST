extends SceneTree
## Paired real-Battle correctness only. No timing/capacity/GPU claim.
## Original seeds/conditions; assert the actual live-step or full-prefix contract.
const B=preload("res://scripts/battle.gd")
const D=preload("res://scripts/damage.gd")
const C=preload("res://scripts/tactical_certification.gd")
const P=preload("res://scripts/tactical_planner.gd")
const T=preload("res://scripts/tactical_runtime.gd")
const SPEC={"id":"skiff","name":"Skiff","hp":150,"armor":1,"crewMin":2,"crewOptimal":5,"crewMax":7,"size":16,"speed":100,"turn":2,"pumps":1,"weapon":"gun","damage":12,"fireRate":2,"range":550}
var checks: int=0
var failures: int=0
var results: Array=[]

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL certification_dt: "+message)

func prediction(st: Dictionary,ship: Dictionary) -> Dictionary:
	var intent: Dictionary=st.tactical.intents.get(str(ship.id),{})
	return st.tactical.predictions.get(str(intent.get("pathFingerprint","")),{})

func live_motion_ok(before: Dictionary,ship: Dictionary,dt: float) -> bool:
	var expected: Vector2=Vector2(before.x,before.y)+Vector2(ship.vx,ship.vy)*dt
	var turn_limit: float=float(ship.spec.turn)*float(D.get_status(ship).turnFactor)*dt
	return Vector2(ship.x,ship.y).distance_to(expected)<=0.0001 and absf(angle_difference(float(before.angle),float(ship.angle)))<=turn_limit+0.0001

func real_fire_and_progress(dt: float) -> void:
	var enemy_spec: Dictionary=SPEC.duplicate(true)
	enemy_spec.speed=0.0
	var st: Dictionary=B.create({"fleet":[D.create_ship(SPEC)],"enemySpecs":[enemy_spec],"seed":42})
	var ship: Dictionary=st.ships[0]
	ship.x=500.0;ship.y=850.0;ship.angle=0.0
	st.ships[1].x=900.0;st.ships[1].y=850.0;st.ships[1].ammo=0.0
	var shots: int=0
	var valid_frames: int=0
	var first_full: Dictionary={}
	var first_live: Dictionary={}
	var motion_ok: bool=true
	var max_samples: int=0
	var expected_steps: int=P.CERT_PREFIX_STEPS*(2 if dt<0.02 else 1)
	for tick in range(roundi(3.0/dt)):
		var before: Dictionary=C.pose(ship)
		B.update(st,dt)
		motion_ok=live_motion_ok(before,ship,dt) and motion_ok
		for event in B.pop_events(st):
			if str(event.get("kind",""))=="fire" and str(event.get("sourceId",""))==str(ship.id):shots+=1
		var intent: Dictionary=st.tactical.intents.get(str(ship.id),{})
		if bool(C.current(st,ship,intent,dt).get("ok",false)):valid_frames+=1
		max_samples=maxi(max_samples,int(st.tactical.budget.get("samples",0)))
		var record: Dictionary=prediction(st,ship)
		if not record.is_empty() and is_equal_approx(float(record.certificate.checkedAt),float(st.time)):
			if str(record.certificate.scope)==P.LIVE_CERT_SCOPE and first_live.is_empty():
				first_live={"chargedSteps":int(st.tactical.budget.samples),"rollouts":int(st.tactical.budget.rollouts),"coarseSamples":int(record.certificate.rolloutSamples),"ownerSame":is_same(record.get("owner"),ship),"guardCurrent":record.get("capabilityInputs")==C._live_capability(ship,D.get_status(ship)),"motionCurrent":record.get("motionInputs")==C._motion_inputs(ship),"checkedPoseMatches":record.certificate.checkedPose==before,"hasForecast":record.has("poses") or record.has("capabilities"),"dt":float(st.tactical.dt),"validSeconds":float(record.certificate.validUntil)-float(record.certificate.checkedAt),"physicalSeconds":float(record.certificate.physicalHorizonEnd)-float(record.certificate.checkedAt)}
			elif str(record.certificate.scope)==P.CERT_SCOPE and first_full.is_empty():
				check(record.get("poses") is Array and record.get("capabilities") is Array,"full physical prefix publishes its actual arrays dt="+str(dt))
				if record.get("poses") is Array and record.get("capabilities") is Array:
					first_full={"chargedSteps":int(st.tactical.budget.samples),"rollouts":int(st.tactical.budget.rollouts),"coarseSamples":int(record.certificate.rolloutSamples),"poses":record.poses.size(),"capabilities":record.capabilities.size(),"sampleDt":record.get("sampleDt",1.0/30.0),"physicalSeconds":float(record.certificate.physicalHorizonEnd)-float(record.certificate.checkedAt)}
	var distance: float=Vector2(ship.x-500.0,ship.y-850.0).length()
	check(is_equal_approx(float(st.time),3.0) and st.result==null,"nonterminal three-second real duel dt="+str(dt))
	check(shots>0 and float(ship.ammo)<80.0,"actual automatic firing spends ammunition dt="+str(dt))
	check(distance>20.0 and float(ship.fuel)<60.0,"actual hull progresses and spends fuel dt="+str(dt))
	check(motion_ok,"every actual step integrates velocity at caller dt and respects live turning dt="+str(dt))
	check(valid_frames>10,"physical certificates stay usable through real motion dt="+str(dt))
	check(not first_live.is_empty() or not first_full.is_empty(),"real Battle publishes a supported physical authority scope dt="+str(dt))
	if not first_live.is_empty():
		check(first_live.ownerSame and first_live.guardCurrent and first_live.motionCurrent and first_live.checkedPoseMatches,"live-step record belongs to the actual hull, checked pose and current capability dt="+str(dt))
		check(not first_live.hasForecast and int(first_live.chargedSteps)==0 and int(first_live.rollouts)==0 and int(first_live.coarseSamples)==0,"live-step authority claims no future poses, capabilities or rollout work dt="+str(dt))
		check(is_equal_approx(float(first_live.dt),dt) and is_equal_approx(float(first_live.validSeconds),P.CERT_SECONDS) and is_equal_approx(float(first_live.physicalSeconds),P.CERT_SECONDS),"live-step lease keeps the actual caller dt and bounded public expiry dt="+str(dt))
	if not first_full.is_empty():
		check(int(first_full.chargedSteps)==expected_steps and int(first_full.rollouts)==1,"every physical integration is charged exactly dt="+str(dt))
		check(int(first_full.coarseSamples)==P.CERT_PREFIX_STEPS and int(first_full.poses)==expected_steps+1 and int(first_full.capabilities)==expected_steps+1,"configured coarse prefix retains every actual step dt="+str(dt))
		check(is_equal_approx(float(first_full.sampleDt),dt) and is_equal_approx(float(first_full.physicalSeconds),P.CERT_PREFIX_SECONDS),"stored step and public prefix horizon match real caller dt="+str(dt))
	check(max_samples<=840,"observed sample ledger stays within the unchanged 840 cap dt="+str(dt))
	results.append({"case":"real-fire-and-progress","dt":dt,"time":st.time,"shots":shots,"ammo":ship.ammo,"fuel":ship.fuel,"distance":distance,"validPostMotionFrames":valid_frames,"actualMotionOk":motion_ok,"firstLiveStep":first_live,"firstFullPrefix":first_full,"maxChargedStepsInObservedTick":max_samples})

func condition_and_hit(dt: float) -> void:
	var enemy_spec: Dictionary=SPEC.duplicate(true)
	enemy_spec.speed=0.0
	var owned: Dictionary=D.create_ship(SPEC,{"hp":115.0,"water":30.0,"fire":5.0,"engine":0.65,"policy":"repair"})
	var st: Dictionary=B.create({"fleet":[owned],"enemySpecs":[enemy_spec],"seed":42})
	var ship: Dictionary=st.ships[0]
	ship.x=500.0;ship.y=850.0;ship.angle=0.0
	st.ships[1].x=1600.0;st.ships[1].y=1100.0;st.ships[1].ammo=0.0
	check(B.issue_order(st,[str(ship.id)],"move",{"x":1000.0,"y":850.0}),"condition fixture accepts a real clear-water order dt="+str(dt))
	var valid_frames: int=0
	var max_error: float=0.0
	var compared: int=0
	var full_compared: int=0
	var live_compared: int=0
	var live_guards_ok: bool=true
	var motion_ok: bool=true
	for tick in range(roundi(0.4/dt)):
		var before: Dictionary=C.pose(ship)
		B.update(st,dt)
		motion_ok=live_motion_ok(before,ship,dt) and motion_ok
		B.pop_events(st)
		var intent: Dictionary=st.tactical.intents.get(str(ship.id),{})
		if bool(C.current(st,ship,intent,dt).get("ok",false)):valid_frames+=1
		var record: Dictionary=prediction(st,ship)
		if not record.is_empty():
			if str(record.certificate.scope)==P.LIVE_CERT_SCOPE:
				live_guards_ok=(record.get("capabilityInputs")==C._live_capability(ship,D.get_status(ship))) and live_guards_ok
				live_compared+=1
			elif str(record.certificate.scope)==P.CERT_SCOPE:
				check(record.get("capabilities") is Array and not record.get("capabilities",[]).is_empty(),"full physical prefix publishes actual condition samples dt="+str(dt))
				if not record.get("capabilities") is Array or record.capabilities.is_empty():continue
				var sample_dt: float=float(record.get("sampleDt",1.0/30.0))
				var index: int=clampi(roundi((float(st.time)-float(record.certificate.checkedAt))/sample_dt),0,record.capabilities.size()-1)
				var expected: Dictionary=record.capabilities[index]
				var actual: Dictionary=C.capability(ship)
				for key in expected:max_error=maxf(max_error,absf(float(actual[key])-float(expected[key])))
				full_compared+=1
			else:check(false,"condition record has a supported physical scope dt="+str(dt));continue
			compared+=1
	check(float(ship.hp)>115.0 and float(ship.supplies)<20.0,"actual hull repair spends finite supplies dt="+str(dt))
	check(float(ship.water)<30.0 and float(ship.fire)<5.0,"actual bailing and firefighting evolve condition dt="+str(dt))
	check(compared>0 and motion_ok,"real evolving condition has checked authority and exact live-step motion dt="+str(dt))
	if live_compared>0:check(live_guards_ok,"real gradual condition advances the current live capability guard dt="+str(dt))
	if full_compared>0:check(max_error<=0.0001,"real condition matches expected prefix capability without tolerance change dt="+str(dt))
	check(valid_frames>=roundi(0.2/dt),"gradual condition evolution preserves current certificate dt="+str(dt))
	var old_intent: Dictionary=st.tactical.intents.get(str(ship.id),{}).duplicate(true)
	var before_hit: Dictionary=C.current(st,ship,old_intent,dt)
	var hp_before: float=float(ship.hp)
	check(bool(before_hit.get("ok",false)),"current certificate is valid immediately before real impact dt="+str(dt))
	# A real swept projectile applies the sudden hit through Battle, not an HP edit.
	st.projectiles.append({"x":float(ship.x)-35.0,"y":float(ship.y),"px":float(ship.x)-35.0,"py":float(ship.y),"vx":3000.0,"vy":0.0,"team":"enemy","damage":24.0,"kind":"bullet","life":1.0,"owner":str(st.ships[1].id),"radius":2.0})
	B.update(st,dt)
	var events: Array=B.pop_events(st)
	var hit: bool=false
	for event in events:
		if str(event.get("kind",""))=="hit" and str(event.get("targetId",""))==str(ship.id):hit=true
	var after_hit: Dictionary=C.current(st,ship,old_intent,dt)
	check(hit and float(ship.hp)<hp_before-1.0,"real projectile impacts the damaged hull dt="+str(dt))
	check(not bool(after_hit.get("ok",true)) and str(after_hit.get("reason",""))=="Damage or capability changed; reassessing","sudden actual hit invalidates the prior certificate dt="+str(dt))
	var braking: Dictionary=T.helm(st,ship)
	check(float(braking.throttle)==0.0,"actual helm brakes immediately after real capability loss dt="+str(dt))
	results.append({"case":"condition-and-real-hit","dt":dt,"comparedFrames":compared,"liveComparedFrames":live_compared,"fullComparedFrames":full_compared,"liveCapabilityGuardOk":live_guards_ok,"actualMotionOk":motion_ok,"validPostMotionFrames":valid_frames,"maxCapabilityError":max_error if full_compared>0 else null,"water":ship.water,"fire":ship.fire,"engine":ship.engine,"supplies":ship.supplies,"hpBeforeHit":hp_before,"hpAfterHit":ship.hp,"actualHitEvent":hit,"beforeHitOk":before_hit.get("ok"),"afterHitOk":after_hit.get("ok"),"afterHitReason":after_hit.get("reason"),"brakeThrottle":braking.throttle})

func legacy_repeated_fire_observation() -> void:
	var spec: Dictionary=SPEC.duplicate(true)
	spec.hp=130
	var ship: Dictionary=D.create_ship(spec)
	var st: Dictionary=B.create({"fleet":[ship,D.create_ship(spec)],"enemySpecs":[spec],"seed":42})
	st.ships[0].supplies=17.0
	B.select_flagship(st,str(st.ships[1].id))
	st.ships[1].sunk=true
	B.update(st,1.0/30.0)
	var enemy: Dictionary=st.ships[2]
	enemy.x=float(ship.x)+180.0;enemy.y=ship.y;enemy.spec.speed=0.0
	B.pop_events(st)
	var phases: Array=[]
	var shots: int=0
	for tick in range(90):
		B.update(st,1.0/30.0,{"fire":true,"aimX":enemy.x,"aimY":enemy.y})
		for event in B.pop_events(st):
			if str(event.get("kind",""))=="fire" and str(event.get("sourceId",""))==str(ship.id):shots+=1
		var state: Dictionary=st.tactical.memory.player.byId.get(str(ship.id),{})
		var phase: String=str(state.get("phase",""))
		if phases.is_empty() or str(phases[-1].phase)!=phase:phases.append({"time":st.time,"phase":phase,"lastUsefulShot":state.get("lastUsefulShot"),"reason":state.get("reason")})
	results.append({"case":"unchanged-legacy-battle-first-90","dt":1.0/30.0,"autopilot":st.autopilot,"ammo":ship.ammo,"enemyAmmo":enemy.ammo,"enemyHp":enemy.hp,"playerShotsIn90":shots,"phases":phases,"oldThreshold":"test_battle.gd:39 ship.ammo<=76 after90 real ticks"})

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":quit(2);return
	for dt: float in [1.0/30.0,1.0/60.0]:
		real_fire_and_progress(dt)
		condition_and_hit(dt)
	legacy_repeated_fire_observation()
	var path: String=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):path=arg.substr(6)
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Paired 30/60 Hz real-Battle correctness; no capacity/performance/full-budget or scattered-ray legality claim","results":results}))
	file.close()
	for row in results:print("OBS certification_dt "+JSON.stringify(row))
	print("Certification dt: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
