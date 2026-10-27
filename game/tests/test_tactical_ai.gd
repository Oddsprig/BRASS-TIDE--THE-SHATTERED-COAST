extends SceneTree
## Actual Battle integration. No direct _fire, fake certificates or RNG retries.
const B=preload("res://scripts/battle.gd")
const D=preload("res://scripts/damage.gd")
const Refit=preload("res://scripts/refit.gd")
const T=preload("res://scripts/tactical_runtime.gd")
const C=preload("res://scripts/tactical_certification.gd")
const Fire=preload("res://scripts/tactical_fire_control.gd")
const Roles=preload("res://scripts/tactical_role_plans.gd")
const Routes=preload("res://scripts/tactical_routes.gd")
const Stations=preload("res://scripts/tactical_stations.gd")
const Planner=preload("res://scripts/tactical_planner.gd")
const Boarding=preload("res://scripts/boarding.gd")
const BoardControl=preload("res://scripts/combat_boarding.gd")
const F=preload("res://tests/tactical_fixture.gd")
const DT: float=1.0/30.0
const SPEC={"id":"ai-probe","name":"AI integration","hp":1000.0,"armor":0,"crewMin":2,"crewOptimal":12,"crewMax":30,"size":16,"speed":100.0,"turn":2.5,"pumps":1,"weapon":"gun","damage":1.0,"fireRate":2.0,"range":900.0,"deploymentPoints":20}
var checks: int=0
var failures: int=0
var observations: Array=[]
var worker_states051: Array=[]

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL tactical_ai: "+message)

func fire_events(st: Dictionary,source: Dictionary) -> Array:
	return B.pop_events(st).filter(func(event):return event.kind=="fire" and str(event.sourceId)==str(source.id))

func ray_case(automatic: bool,kind: String) -> void:
	var spec: Dictionary=SPEC.duplicate(true);spec.speed=0.0
	var far_miss: bool=kind=="miss_ally"
	spec.weaponMounts=[{"id":"ray","kind":"gun","damage":1.0,"fireRate":1.0,"range":1800.0 if far_miss else 900.0,"speed":600.0,"ammoCost":2,"x":8.0,"y":0.0,"arc":TAU,"angle":0.0}]
	var target_spec: Dictionary=spec.duplicate(true);target_spec.size=10 if far_miss else 30
	var ally_spec: Dictionary=spec.duplicate(true);ally_spec.size=10
	var st: Dictionary=B.create({"fleet":[D.create_ship(spec),D.create_ship(ally_spec,{"ammo":0.0})],"enemyFleet":[D.create_ship(target_spec,{"ammo":0.0})],"seed":30011})
	st.islands=[];st.autoBoard=false
	var source: Dictionary=st.ships[0];var ally: Dictionary=st.ships[1];var target: Dictionary=st.ships[2]
	source.x=300.0 if far_miss else 500.0;source.y=850.0;source.angle=0.0;source.vx=100.0;source.vy=25.0
	ally.x=400.0;ally.y=1200.0
	target.x=1800.0 if far_miss else 1000.0;target.y=850.0
	check(B.issue_order(st,[ally.id],"hold"),"ray fixture holds its actual ally")
	# One real no-fire manual frame initializes geometry and exercise mode retake.
	# All blocker placement below is initial measurement setup, never an escape.
	B.update(st,DT,{"manual":true});B.pop_events(st)
	var mount: Dictionary=B._mounts(source)[0]
	var predicted: Dictionary=source.duplicate(true)
	var heading: float=(F.pos(target)-F.pos(source)).angle() if automatic else float(source.angle)
	predicted.merge(C.motion(source,DT,heading,0.0),true)
	var origin: Vector2=F.pos(predicted)+Vector2(mount.x,mount.y).rotated(float(predicted.angle))
	var bearing: float=(F.pos(target)-origin).angle()
	if automatic:
		var intercept: Dictionary=Fire.intercept(predicted,mount,target)
		check(intercept.ok,"actual auto intercept API accepts the ray fixture")
		bearing=float(intercept.get("bearing",bearing))
	var replica: RandomNumberGenerator=RandomNumberGenerator.new();replica.seed=st.rng.seed;replica.state=st.rng.state
	var before_rng: int=st.rng.state
	var scatter: float=(replica.randf()-0.5)*0.045
	var after_one_rng: int=replica.state
	var velocity: Vector2=Vector2.from_angle(bearing+scatter)*float(mount.speed)+Vector2(predicted.vx,predicted.vy)*0.2
	var ideal: Vector2=Vector2.from_angle(bearing)*float(mount.speed)+Vector2(predicted.vx,predicted.vy)*0.2
	var muzzle: Vector2=origin+Vector2.from_angle(bearing)*float(mount.muzzleDistance)
	var life: float=float(mount.range)/float(mount.speed)
	var hostile_time: float=clampf((F.pos(target)-muzzle).dot(velocity)/velocity.length_squared(),0.0,life)
	var hostile_gap: float=F.pos(target).distance_to(muzzle+velocity*hostile_time)
	var normal: Vector2=ideal.normalized().orthogonal()
	if kind=="ally_before":
		var time: float=hostile_time*0.6
		var offset: float=(velocity-ideal).dot(normal)*time
		var point: Vector2=muzzle+ideal*time+normal*signf(offset)*(16.0+absf(offset)*0.5)
		ally.x=point.x;ally.y=point.y
	elif kind in ["ally_after","miss_ally"]:
		var time: float=life-0.2 if far_miss else hostile_time+0.3
		var point: Vector2=muzzle+velocity*time
		ally.x=point.x;ally.y=point.y
	elif kind=="crossing_ally":
		var time: float=hostile_time*0.6
		var point: Vector2=muzzle+velocity*time
		ally.x=point.x;ally.y=point.y-200.0*(time+DT);ally.vy=200.0/exp(-4.0*DT)
	elif kind in ["land_before","land_after"]:
		var time: float=hostile_time*0.7 if kind=="land_before" else hostile_time+0.3
		var point: Vector2=muzzle+velocity*time
		st.islands=[F.rectangle(point.x-0.25,point.y-0.25,point.x+0.25,point.y+0.25)]
	elif kind=="pending":
		# Real geometry work exhausts the unchanged shared cap. No ledger edit.
		for index in range(4100):st.islands.append(F.rectangle(50.0,50.0,51.0,51.0))
	var ammo: float=float(source.ammo)
	B.update(st,DT,{} if automatic else {"manual":true,"fire":true,"aimX":target.x,"aimY":target.y})
	var events: Array=fire_events(st,source)
	var should_fire: bool=kind in ["clear","ally_after","land_after"]
	var label: String=("auto/" if automatic else "manual/")+kind
	check(events.size()==(1 if should_fire else 0),label+": actual emitted ray obeys blocker/hostile horizon")
	check(is_equal_approx(ammo-float(source.ammo),float(events.size())*2.0),label+": exact whole-round debit equals actual events")
	check((float(source.cooldown)>0.0)==should_fire and (B.mount_shot_time(source,"ray")>=0.0)==should_fire,label+": only an actual shot starts cooldown/timestamp")
	check(st.rng.state==before_rng or st.rng.state==after_one_rng,label+": at most one fixed seeded scatter, never reroll until clear")
	if should_fire:
		check(st.rng.state==after_one_rng,label+": emitted shot consumes exactly its single seeded scatter")
		var shots: Array=st.projectiles.filter(func(shot):return str(shot.owner)==str(source.id))
		check(shots.size()==1,label+": emitted projectile remains physically present")
		if shots.size()==1:
			var shot: Dictionary=shots[0]
			check(Vector2(shot.vx,shot.vy).distance_to(velocity)<0.001 and absf(angle_difference(float(shot.angle),bearing+scatter))<0.00001,label+": actual velocity includes the once-scattered direction and inherited ship velocity")
	if far_miss:check(hostile_gap>12.0,label+": seeded ray really misses the hostile, retaining full-life ally protection")
	if kind=="pending":check(int(st.tactical.budget.exhaustions)>0 and int(st.tactical.budget.clearanceTests)<=4096,label+": real budget exhaustion stays pending without emission/debit")
	observations.append({"case":"ray","automatic":automatic,"variant":kind,"time":st.time,"events":events,"ammoBefore":ammo,"ammoAfter":source.ammo,"cooldown":source.cooldown,"rngBefore":before_rng,"rngAfter":st.rng.state,"oneScatterState":after_one_rng,"scatter":scatter,"expectedVelocity":velocity,"predictedHostileGap":hostile_gap,"hostileTime":hostile_time,"life":life,"actualPose":C.pose(source),"budget":st.tactical.budget.duplicate(true)})

func ray_cases() -> void:
	for automatic in [false,true]:
		for kind in ["clear","ally_before","land_before","ally_after","land_after","crossing_ally","miss_ally","pending"]:ray_case(automatic,kind)

func boarding_arena(focused: bool=false) -> Dictionary:
	var source_spec: Dictionary=SPEC.duplicate(true)
	var target_spec: Dictionary=SPEC.duplicate(true);target_spec.speed=0.0;target_spec.crewOptimal=5;target_spec.crewMax=30;target_spec.hp=2000;target_spec.damage=150.0 if focused else 1.0
	var source: Dictionary=D.create_ship(source_spec,{"crew":20.0,"boarders":10})
	var target: Dictionary=D.create_ship(target_spec,{"engine":0.0,"ammo":80.0 if focused else 0.0})
	var enemies: Array=[target]
	if focused:enemies.append(D.create_ship(target_spec,{"engine":1.0}))
	var st: Dictionary=B.create({"fleet":[source],"enemyFleet":enemies,"seed":30029})
	st.islands=[];st.autoBoard=true
	source.x=500.0;source.y=850.0;source.angle=0.0
	target.x=760.0;target.y=850.0;target.angle=PI
	if focused:st.ships[2].x=760.0;st.ships[2].y=930.0;st.ships[2].angle=PI
	return st

func boarding_continuity() -> void:
	for command in ["move","withdraw","manual","stay"]:
		var st: Dictionary=boarding_arena()
		var source: Dictionary=st.ships[0];var target: Dictionary=st.ships[1]
		var start: Vector2=F.pos(source)
		var initial_people: float=float(source.crew)+float(target.crew)
		var launched_at: float=-1.0
		for tick in range(180):
			B.update(st,DT)
			B.pop_events(st)
			if not st.get("boarding",{}).get("jobs",[]).is_empty():launched_at=st.time;break
		check(launched_at>0.0 and F.pos(source).distance_to(start)>50.0,"automatic same-revision "+command+": real approach reaches physical contact and launches")
		if launched_at<0.0:
			observations.append({"case":"boarding-launch-failed","command":command,"time":st.time,"sourcePose":C.pose(source),"targetPose":C.pose(target),"plan":source.get("boardingOrder",{}),"crew":source.crew,"targetCrew":target.crew,"boarders":source.get("boarders",0),"memory":st.tactical.memory.player.byId.get(str(source.id),{}),"log":st.log.duplicate()})
			continue
		var job: Dictionary=st.boarding.jobs[0]
		var crew: float=float(source.crew);var next: float=float(job.next);var alive: int=int(job.alive)
		check(source.order=="engage" and source.get("boardingOrder",{}).get("launched",false) and int(source.orderRevision)==0,"automatic "+command+": unchanged engage revision retains only one launched party")
		if command in ["move","withdraw"]:check(B.issue_order(st,[source.id],command,{"x":300.0,"y":700.0}),"new explicit "+command+" accepted after launch")
		if command=="manual":B.set_autopilot(st,false)
		check(float(source.crew)==crew and float(job.next)==next and int(job.alive)==alive,"new "+command+": command acceptance cannot restore crew or reset the party timer")
		var furthest: float=0.0
		for tick in range(180):
			var input: Dictionary={}
			if command=="manual":
				var turn: float=angle_difference(float(source.angle),PI)
				input={"manual":true,"forward":absf(turn)<0.8,"right":turn>0.04,"left":turn< -0.04}
			B.update(st,DT,input);B.pop_events(st)
			furthest=maxf(furthest,F.pos(source).distance_to(F.pos(target)))
			if job.status!="active":break
		check(st.boarding.jobs.size()==1,"post-launch "+command+": no automatic duplicate party")
		var accounted: float=float(source.crew)+float(target.crew)+float(target.get("captives",0))+float(job.alive)+float(job.killed)+float(job.defenderKilled)+float(job.lost)
		check(is_equal_approx(accounted,initial_people),"post-launch "+command+": actual casualties/custody conserve the initial people")
		if command in ["move","withdraw","manual"]:
			check(job.status=="escaped" and int(job.lost)>0 and float(source.crew)==crew,"post-launch "+command+": actual departure invokes Boarding escape without free crew restore")
		else:check(int(job.round)>0 or job.status=="captured","unchanged automatic contact permits real boarding exchanges")
		observations.append({"case":"boarding-continuity","command":command,"launchTime":launched_at,"time":st.time,"job":job.duplicate(true),"sourceCrew":source.crew,"targetCrew":target.crew,"maximumActualDistance":furthest,"initialPeople":initial_people,"accountedPeople":accounted})

func focused_boarding() -> void:
	var st: Dictionary=boarding_arena(true)
	var source: Dictionary=st.ships[0]
	var first_hp: float=float(source.hp)
	var proof: Dictionary={}
	var trace: Array=[]
	for tick in range(45):
		B.update(st,DT)
		var events: Array=B.pop_events(st)
		var memory: Dictionary=st.tactical.memory.player.byId.get(str(source.id),{})
		if memory.is_empty() or not source.get("boardingOrder",{}).get("automatic",false):continue
		var view: Dictionary=T.view(st,"player",[str(source.id)])
		var own: Dictionary={};var context: Dictionary={}
		for ship in view.ships:
			context[str(ship.id)]=ship
			if str(ship.id)==str(source.id):own=ship
		var projected: Dictionary=Roles.decide(view,own,memory,context)
		if tick%3==0:trace.append({"time":st.time,"hp":source.hp,"order":source.order,"projectedOrder":own.order,"projectedPhase":projected.state.phase,"danger":projected.danger,"plan":source.get("boardingOrder",{}).duplicate(true),"threats":[Roles.threat(context[str(st.ships[1].id)],own,st.time),Roles.threat(context[str(st.ships[2].id)],own,st.time)],"observations":memory.get("observations",[]).duplicate(true),"events":events})
		var live: Dictionary=own.duplicate(true);live.order="engage";live.orderTarget={}
		var real_order: Dictionary=Roles.decide(view,live,memory,context)
		if not real_order.danger or float(source.hp)<float(source.maxHp)*0.6:continue
		proof={"time":st.time,"firstHp":first_hp,"actualHp":source.hp,"actualFire":source.fire,"actualWater":source.water,"actualOrder":source.order,"projectedOrder":own.order,"projectedPhase":projected.state.phase,"engagePhase":real_order.state.phase,"projectedDanger":projected.danger,"engageDanger":real_order.danger,"projectedDetailedIds":projected.detailedIds,"engageDetailedIds":real_order.detailedIds,"runtimeSafety":st.tactical.safety.get(str(source.id),{}),"runtimeMemory":memory.duplicate(true),"eventsOnProofTick":events}
		check(projected.state.phase in ["breakaway","regroup"],"recent actual focused HP loss interrupts automatic boarding while absolute hull/flood/fire remain safe")
		# Real projectile damage lands after begin()'s planner publication. Observe
		# the next scheduled decision, retaining the hit-frame proof above verbatim.
		for next_tick in range(6):
			if str(st.tactical.memory.player.byId[str(source.id)].phase) in ["breakaway","regroup"]:break
			B.update(st,DT);B.pop_events(st)
		proof["publishedAt"]=st.time;proof["publishedMemory"]=st.tactical.memory.player.byId[str(source.id)].duplicate(true)
		check(str(st.tactical.memory.player.byId[str(source.id)].phase) in ["breakaway","regroup"] and float(st.time)-float(proof.time)<=0.2+0.000001,"actual published automatic planner makes the focused-damage survival break within its bounded observation cadence")
		check(source.order=="engage" and not st.tactical.options.byId[str(source.id)].conditionalWithdrawal,"automatic contact cannot change the live command or conditional permission")
		var intent: Dictionary=st.tactical.intents.get(str(source.id),{})
		check(not intent.get("waypoints",[]).is_empty() and (intent.waypoints[-1] as Vector2).distance_to(F.pos(st.ships[1]))>F.pos(source).distance_to(F.pos(st.ships[1])),"published survival path actually leads away from the boarding contact")
		var retreat_start: Vector2=F.pos(source)
		var retreat_range: float=retreat_start.distance_to(F.pos(st.ships[1]))
		var maximum_range: float=retreat_range;var traveled: float=0.0
		var previous: Vector2=retreat_start;var motion: Array=[]
		var fuel: float=float(source.fuel)
		for retreat_tick in range(90):
			B.update(st,DT);B.pop_events(st)
			traveled+=F.pos(source).distance_to(previous);previous=F.pos(source)
			maximum_range=maxf(maximum_range,F.pos(source).distance_to(F.pos(st.ships[1])))
			if retreat_tick%6==0:motion.append({"time":st.time,"pose":C.pose(source),"hp":source.hp,"phase":st.tactical.memory.player.byId.get(str(source.id),{}).get("phase",""),"fuel":source.fuel})
		proof["retreatMotion"]=motion;proof["maximumRadialGain"]=maximum_range-retreat_range;proof["retreatTravel"]=traveled
		check(maximum_range-retreat_range>=30.0 and traveled>=50.0 and float(source.fuel)<fuel and float(source.crew)==20.0 and int(source.boarders)==10 and st.get("boarding",{}).get("jobs",[]).is_empty(),"recent-hit automatic boarding break produces actual fueled escape motion without launching/restoring a crew party")
		break
	check(not proof.is_empty(),"focused boarding fixture proves actual recent-damage danger above the absolute hull threshold")
	observations.append({"case":"focused-boarding","proof":proof,"trace":trace,"finalHp":source.hp,"lastPlan":source.get("boardingOrder",{}),"fireTimes":[st.ships[1].get("mountShotTimes",{}),st.ships[2].get("mountShotTimes",{})]})

func explicit_boarding_authority() -> void:
	for conditional in [false,true]:
		var st: Dictionary=boarding_arena(true)
		var source: Dictionary=st.ships[0];var target: Dictionary=st.ships[1]
		check(BoardControl.order(st,str(source.id),str(target.id),10).ok,"focused explicit board accepted through its native boarding API")
		check(B.set_tactical_options(st,[source.id],{"conditionalWithdrawal":conditional}),"explicit board permission accepted")
		var proof: Dictionary={}
		for tick in range(45):
			B.update(st,DT);B.pop_events(st)
			var memory: Dictionary=st.tactical.memory.player.byId.get(str(source.id),{})
			if memory.is_empty():continue
			var view: Dictionary=T.view(st,"player",[str(source.id)])
			var context: Dictionary=Roles.ships_by_id(view)
			var choice: Dictionary=Roles.decide(view,context[str(source.id)],memory,context)
			if not choice.danger or float(source.hp)<=float(source.maxHp)*0.6:continue
			proof={"time":st.time,"hp":source.hp,"conditional":conditional,"choice":choice.duplicate(true)}
			check(choice.detailedIds.size()==2 and choice.state.targetId==str(target.id) and choice.targets==[str(target.id)],"named board target stays strict while both real threats remain visible")
			for next_tick in range(6):
				var published: Dictionary=st.tactical.memory.player.byId[str(source.id)]
				if float(published.observations[-1].lastAt)>=float(proof.time):break
				B.update(st,DT);B.pop_events(st)
			var phase: String=str(st.tactical.memory.player.byId[str(source.id)].phase)
			check((phase in ["breakaway","regroup"]) if conditional else phase=="board","explicit board obeys its actual false/true withdrawal permission after real hits")
			check(source.order=="board" and source.orderTarget.shipId==target.id and st.tactical.options.byId[str(source.id)].conditionalWithdrawal==conditional,"focused survival cannot rewrite explicit command or live options")
			proof["publishedAt"]=st.time;proof["publishedPhase"]=phase
			break
		check(not proof.is_empty(),"explicit board case observes actual recent HP loss with two real threats")
		observations.append({"case":"explicit-focused-board","proof":proof})

func fire_readiness051() -> void:
	# One real arena throughout: no direct _fire, synthetic certificate, timer
	# reset, ammunition refill or RNG retry. Cooldowns cross only via B.update.
	var dt: float=1.0/60.0
	var spec: Dictionary=SPEC.duplicate(true);spec.speed=0.0
	spec.weaponMounts=[{"id":"slow","kind":"gun","damage":1.0,"fireRate":2.0,"range":900.0,"ammoCost":2,"arc":TAU},{"id":"fast","kind":"gun","damage":1.0,"fireRate":4.0,"range":900.0,"ammoCost":3,"arc":TAU}]
	var st: Dictionary=B.create({"fleet":[D.create_ship(spec)],"enemyFleet":[D.create_ship(spec,{"ammo":0.0}),D.create_ship(spec,{"ammo":0.0})],"seed":30011})
	st.islands=[];st.autoBoard=false
	var source: Dictionary=st.ships[0];var target: Dictionary=st.ships[1];var alternate: Dictionary=st.ships[2]
	var id: String=str(source.id)
	source.x=500.0;source.y=850.0;source.angle=0.0
	target.x=850.0;target.y=850.0;alternate.x=850.0;alternate.y=1150.0
	check(B.issue_order(st,[id],"hold") and B.set_tactical_options(st,[id],{"role":"heavy"}),"readiness uses the actual held heavy-gun arena and public controls")
	var first: Array=[]
	for tick in range(12):
		B.update(st,dt);first=fire_events(st,source)
		if not first.is_empty():break
	check(first.size()==2 and is_equal_approx(80.0-float(source.ammo),5.0),"both initially ready mounts emit real shots with distinct exact ammunition costs")
	if first.size()!=2:return
	var mounts: Array=st.tactical.mountCache[id].mounts
	var intent: Dictionary=st.tactical.intents[id]
	var planned_target: Dictionary=st.tactical.ships[str(intent.fireGate.slow.targetId)]
	var default_gate: Dictionary=Fire.gate(st,source,mounts[0],0,intent,st.tactical.options.byId[id],planned_target,st.tactical.budget)
	check(not default_gate.ok and default_gate.reason=="Reloading","default public Fire.gate retains its existing current reload reason and guard")
	var authority: PackedByteArray=var_to_bytes([st.tactical.intents,st.tactical.predictions,st.tactical.memory,st.tactical.passes,st.tactical.salvoSpent,source.mountShotTimes])
	var budget: Dictionary=st.tactical.budget.duplicate(true)
	var rng_before: int=st.rng.state
	var ammo: float=float(source.ammo)
	check(T._battle_fire_gates051(st,source).is_empty() and st.tactical.fireReasons[id]=={"slow":"Reloading","fast":"Reloading"},"all-reloading current mounts publish fresh holds without a step fire view")
	check(st.rng.state==rng_before and float(source.ammo)==ammo and st.tactical.budget==budget and var_to_bytes([st.tactical.intents,st.tactical.predictions,st.tactical.memory,st.tactical.passes,st.tactical.salvoSpent,source.mountShotTimes])==authority,"impossible-fire probe changes no authority, route ledger, shot history, ammunition or RNG")
	var partial: bool=false
	var crossings: int=0
	var reload_trace: Array=[]
	for tick in range(35):
		var remaining: Array=source.weaponCooldowns.duplicate()
		var primary: float=float(source.cooldown)
		ammo=float(source.ammo);rng_before=st.rng.state
		var replica: RandomNumberGenerator=RandomNumberGenerator.new();replica.seed=st.rng.seed;replica.state=rng_before
		replica.randf()
		B.update(st,dt)
		var events: Array=fire_events(st,source)
		var debit: float=0.0
		for event in events:debit+=2.0 if str(event.mountId)=="slow" else 3.0
		check(is_equal_approx(ammo-float(source.ammo),debit),"every real reload frame pays exactly its emitted mounts")
		for index in range(2):
			var next_reload: float=maxf(0.0,float(remaining[index])-dt)
			if index==0:next_reload=maxf(next_reload,maxf(0.0,primary-dt))
			var mount_id: String="slow" if index==0 else "fast"
			var fired: bool=events.any(func(event):return str(event.mountId)==mount_id)
			if next_reload>0.0:check(not fired,"a reloading mount cannot borrow another ready mount's approval")
			elif float(remaining[index])>0.0:
				crossings+=1
				check(fired,"a real gun fires on its first zero-cooldown tick through the complete current gates: "+mount_id)
				if index==1 and maxf(0.0,primary-dt)>0.0 and not partial:
					partial=true
					check(events.size()==1 and str(events[0].mountId)=="fast" and st.rng.state==replica.state,"ready secondary fires with exactly one scatter while primary still reloads")
		if not events.is_empty():reload_trace.append({"time":st.time,"before":remaining,"events":events,"ammo":source.ammo})
	check(partial and crossings>=3,"real cooldowns exercise both mounts and a partial multimount ready crossing")
	check(B.set_tactical_options(st,[id],{"mountGroup":{"kind":"all","hold":true}}),"current public per-mount hold is accepted")
	ammo=float(source.ammo)
	var held_events: Array=[]
	for tick in range(40):B.update(st,dt);held_events.append_array(fire_events(st,source))
	check(held_events.is_empty() and float(source.ammo)==ammo and source.weaponCooldowns.all(func(value):return float(value)==0.0),"real reloads finish under hold without any free or withheld paid shot")
	check(B.tactical_status(st,id).weapons=={"slow":"Automatic fire held","fast":"Automatic fire held"},"HUD shows current holds after timers have genuinely become ready")
	check(B.set_tactical_options(st,[id],{"mountGroup":{"kind":"all","hold":false,"reserve":int(ammo)}}),"current reserve consumes no ammunition")
	B.update(st,dt)
	check(fire_events(st,source).is_empty() and float(source.ammo)==ammo and B.tactical_status(st,id).weapons=={"slow":"Keeping working ammunition reserve","fast":"Keeping working ammunition reserve"},"ready guns honor each live reserve and replace the old held HUD reasons")
	B.set_autopilot(st,false)
	var manual_rng: RandomNumberGenerator=RandomNumberGenerator.new();manual_rng.seed=st.rng.seed;manual_rng.state=st.rng.state
	manual_rng.randf();manual_rng.randf()
	B.update(st,dt,{"manual":true,"fire":true,"aimX":target.x,"aimY":target.y})
	var manual_events: Array=fire_events(st,source)
	check(manual_events.size()==2 and is_equal_approx(ammo-float(source.ammo),5.0) and st.rng.state==manual_rng.state,"manual trigger keeps its original authority over ready guns, exact ammunition and one scatter per mount despite automatic reserves")
	check(str(st.tactical.manualId)==id and not st.tactical.intents.has(id),"manual fire obtains no automatic gate or retained authority")
	check(B.set_tactical_options(st,[id],{"mountGroup":{"kind":"all","hold":false,"reserve":0}}) and B.issue_order(st,[id],"attack",{"shipId":alternate.id}),"current attack switches the target while the real guns are reloading")
	B.set_autopilot(st,true)
	var changed_events: Array=[]
	var ready_at: float=-1.0
	var first_changed: float=-1.0
	for tick in range(36):
		if ready_at<0.0 and maxf(0.0,float(source.weaponCooldowns[1])-dt)==0.0:ready_at=float(st.time)+dt
		B.update(st,dt)
		var events: Array=fire_events(st,source)
		if not events.is_empty():
			first_changed=float(st.time);changed_events=events;break
	check(not changed_events.is_empty() and first_changed==ready_at and changed_events.all(func(event):return str(event.targetId)==str(alternate.id)),"first ready shot after retake uses the CURRENT attack target, never the earlier target or a cached false readiness")
	# In-place fitting changes must reach the next prepass's current mounts.
	# Make both guns physically unusable without changing stores or real timers.
	source.spec.weaponMounts[0].damage=0.0
	source.spec.weaponMounts[1].ammoCost=int(source.ammo)+1
	ammo=float(source.ammo)
	B.update(st,dt)
	check(fire_events(st,source).is_empty() and float(source.ammo)==ammo and st.tactical.mountCache[id].mounts[1].ammoCost>source.ammo,"readiness reads refreshed mutable fittings rather than a saved cost or mount view")
	check(B.tactical_status(st,id).weapons=={"slow":"Weapon disabled","fast":"Out of ammunition"},"changed fitted damage and ammo cost replace previous ready/reload reasons immediately")
	observations.append({"case":"fire-readiness051","first":first,"reloads":reload_trace,"partial":partial,"crossings":crossings,"manual":manual_events,"changedTarget":changed_events,"readyAt":ready_at,"firstChangedAt":first_changed,"ammo":source.ammo,"weapons":st.tactical.fireReasons[id].duplicate()})

func held_gun() -> void:
	var spec: Dictionary=SPEC.duplicate(true);spec.speed=0.0
	var st: Dictionary=B.create({"fleet":[D.create_ship(spec)],"enemyFleet":[D.create_ship(spec,{"ammo":0.0})],"seed":30011})
	st.islands=[];st.autoBoard=false
	var source: Dictionary=st.ships[0];var target: Dictionary=st.ships[1]
	source.x=500.0;source.y=850.0;target.x=850.0;target.y=850.0
	check(B.issue_order(st,[source.id],"hold") and B.set_tactical_options(st,[source.id],{"role":"heavy"}),"long-held heavy gun uses accepted actual hold/role controls")
	var emitted: Array=[];var costs: float=0.0;var previous_time: float=-1.0
	var maximum: int=0;var last_memory: Dictionary={}
	for tick in range(600):
		var before: float=float(source.ammo)
		B.update(st,DT)
		var events: Array=fire_events(st,source)
		var debit: float=0.0
		for event in events:
			debit+=1.0;emitted.append(event)
			if previous_time>=0.0:check(float(event.time)-previous_time>=0.5-0.000001,"held gun honors each real reload interval")
			previous_time=float(event.time)
		check(is_equal_approx(before-float(source.ammo),debit),"long-held frame debit equals actual emissions")
		costs+=debit
		last_memory=st.tactical.memory.player.byId.get(str(source.id),{})
		maximum=maxi(maximum,int(last_memory.get("passShots",0)));maximum=maxi(maximum,int(last_memory.get("passShortShots",0)))
	check(emitted.size()>=20 and maximum<=4,"long-held gun keeps firing while retained burst counters stay bounded to useful thresholds")
	check(is_equal_approx(80.0-float(source.ammo),costs) and B.mount_shot_time(source,"mount0")==previous_time,"bounded pass counters preserve real whole ammunition and latest actual shot history")
	observations.append({"case":"held-gun","emitted":emitted,"maximumRetainedCount":maximum,"memory":last_memory,"ammo":source.ammo})

func useful_pressure() -> void:
	# Exact original test_battle opening sequence, with per-frame actual evidence.
	var spec: Dictionary=F.SPEC.duplicate(true);spec.hp=130;spec.crewOptimal=5;spec.crewMax=7
	var st: Dictionary=B.create({"fleet":[D.create_ship(spec),D.create_ship(spec)],"enemySpecs":[spec],"seed":42})
	var source: Dictionary=st.ships[0];var target: Dictionary=st.ships[2]
	source.supplies=17.0;B.select_flagship(st,st.ships[1].id);st.ships[1].sunk=true
	B.update(st,DT);B.pop_events(st)
	target.x=source.x+180.0;target.y=source.y;target.spec.speed=0.0
	var events: Array=[];var trace: Array=[];var counts: Dictionary={str(source.id):0,str(target.id):0}
	for tick in range(90):
		var before: float=float(source.ammo)+float(target.ammo)
		B.update(st,DT,{"fire":true,"aimX":target.x,"aimY":target.y})
		var emitted: Array=B.pop_events(st).filter(func(event):return event.kind=="fire")
		check(is_equal_approx(before-float(source.ammo)-float(target.ammo),float(emitted.size())),"original opening pays exactly for real 2 Hz gun events")
		for event in emitted:
			events.append(event);counts[str(event.sourceId)]=int(counts.get(str(event.sourceId),0))+1
		trace.append({"time":st.time,"source":C.pose(source),"hp":source.hp,"targetHp":target.hp,"memory":st.tactical.memory.player.byId.get(str(source.id),{}).duplicate(true),"intent":st.tactical.intents.get(str(source.id),{}).duplicate(true),"reason":st.tactical.reasons.get(str(source.id),""),"withheld":st.tactical.fireReasons.get(str(source.id),{}).duplicate(true)})
	check(int(counts[str(source.id)])>=4 and int(counts[str(target.id)])>=4,"original three-second opening delivers at least four real paid shots on each side")
	observations.append({"case":"useful-pressure","counts":counts,"events":events,"trace":trace,"ammo":[source.ammo,target.ammo]})

func capabilities_and_observations() -> void:
	var results: Dictionary={}
	for variant in ["working","engine-worn","pump-absent","burning"]:
		var spec: Dictionary=SPEC.duplicate(true);spec.pumps=0 if variant=="pump-absent" else 2
		var source: Dictionary=D.create_ship(spec,{"water":80.0,"breaches":[{"area":12.0,"section":"waterline"}],"engine":0.4 if variant=="engine-worn" else 1.0,"fire":20.0 if variant=="burning" else 0.0,"supplies":4.0})
		var target: Dictionary=D.create_ship(SPEC,{"ammo":0.0})
		var st: Dictionary=B.create({"fleet":[source],"enemyFleet":[target],"seed":30011})
		st.islands=[];st.autoBoard=false
		source.x=500.0;source.y=850.0;target.x=1600.0;target.y=1050.0
		# Synthetic privacy markers are data, never real credentials or private user data.
		target.privateLedger={"marker":"enemy-private"};target.paidCargo=71
		st.mission={"kind":"laboratory","duration":30.0,"allyUids":[str(source.get("uid",source.id))],"privateLedger":{"marker":"mission-private"},"paidCargo":71}
		check(B.issue_order(st,[source.id],"move",{"x":1100.0,"y":850.0}),variant+": real numerical-condition movement command accepted")
		F.command(st,target,"move",{"x":1300.0,"y":1050.0})
		var start: Vector2=F.pos(source);var observed_positions: Dictionary={};var samples: Array=[]
		for tick in range(120):
			var before_enemy: Vector2=F.pos(target)
			B.update(st,DT);B.pop_events(st)
			var view: Dictionary=T.view(st,"player",[str(source.id)])
			var context: Dictionary=Roles.ships_by_id(view)
			var seen: Dictionary=context[str(target.id)]
			check(Roles.pos(seen).distance_to(before_enemy)<0.001,variant+": each enemy observation is the current tick's actual pre-motion position")
			check(not seen.has("ammo") and not seen.has("crew") and not seen.has("privateLedger") and not seen.has("paidCargo") and not view.mission.has("privateLedger") and not view.mission.has("paidCargo"),variant+": detached planner sees public motion/mission without private stores or ledgers")
			check(float(source.supplies)<=4.0 and float(source.supplies)>=0.0 and float(source.fuel)<60.0,variant+": actual movement and repair retain finite paid stores")
			observed_positions[str(seen.x)+":"+str(seen.y)]=true
			if tick%15==0:samples.append({"time":st.time,"pose":C.pose(source),"water":source.water,"engine":source.engine,"fire":source.fire,"supplies":source.supplies,"status":D.get_status(source)})
		check(observed_positions.size()>10,variant+": the moving enemy observation is refreshed rather than cached once")
		check(F.pos(source).distance_to(start)>40.0 and float(source.supplies)<4.0 and D.sum_areas(source)<12.0,variant+": actual damaged hull moves, pumps and pays for breach repair")
		results[variant]={"travel":F.pos(source).distance_to(start),"water":source.water,"engine":source.engine,"fire":source.fire,"hp":source.hp,"supplies":source.supplies,"samples":samples}
	check(float(results["engine-worn"].travel)<float(results.working.travel)*0.65,"real worn engine reduces achieved distance under the same accepted movement command")
	check(float(results["pump-absent"].water)>float(results.working.water)+5.0,"absent numerical pumps leave more real floodwater after the same finite crew effort")
	check(float(results.burning.fire)<20.0 and float(results.burning.engine)<1.0 and float(results.burning.hp)<1000.0,"actual firefighting reduces fire while its heat damages hull and engine")
	observations.append({"case":"capabilities-and-fresh-observations","variants":results})
	var spec: Dictionary=SPEC.duplicate(true);spec.speed=0.0
	var source: Dictionary=D.create_ship(spec,{"fire":20.0,"policy":"fight"})
	var st: Dictionary=B.create({"fleet":[source],"enemyFleet":[D.create_ship(spec,{"ammo":0.0})],"seed":30011})
	st.islands=[];st.autoBoard=false;source.x=500.0;source.y=850.0;st.ships[1].x=850.0;st.ships[1].y=850.0
	check(B.issue_order(st,[source.id],"hold"),"burning gun retains accepted explicit hold")
	var emitted: Array=[];var first_cooldown: float=-1.0;var last_cooldown: float=-1.0
	for tick in range(120):
		var before: float=float(source.ammo)
		B.update(st,DT)
		var events: Array=fire_events(st,source)
		check(is_equal_approx(before-float(source.ammo),float(events.size())),"burning gun still pays exactly for actual emitted shots")
		if not events.is_empty():
			if first_cooldown<0.0:first_cooldown=float(source.cooldown)
			last_cooldown=float(source.cooldown);emitted.append_array(events)
	check(emitted.size()>=4 and first_cooldown>0.53 and last_cooldown<first_cooldown,"actual fire-damaged gun reloads more slowly than the healthy 0.5 seconds and improves with real firefighting")
	observations.append({"case":"burning-gun","events":emitted,"firstCooldown":first_cooldown,"lastCooldown":last_cooldown,"fire":source.fire,"engine":source.engine})

func fleet_cadence() -> void:
	# Same native deployment as the independent original40 event fixture. This
	# checks fresh decisions; the separate first120-frame emission failure stays.
	var world: Dictionary=F.world()
	var spec: Dictionary={}
	for hull in world.HULLS:
		if str(hull.id)=="tin_skiff":spec=hull;break
	var players: Array=[];var enemies: Array=[]
	for index in range(21):
		var ship: Dictionary=D.create_ship(spec,{"uid":"p-%d"%index})
		Refit.ensure(ship,spec);ship.ammo=float(ship.spec.ammoCapacity);players.append(ship)
		if index<20:
			ship=D.create_ship(spec,{"uid":"e-%d"%index})
			Refit.ensure(ship,spec);ship.ammo=float(ship.spec.ammoCapacity);enemies.append(ship)
	var st: Dictionary=B.create({"fleet":players,"enemyFleet":enemies,"seed":83})
	check(st.ships.size()==40 and st.deployment.player==300 and st.deployment.enemy==300 and st.reserves.player.size()==1,"cadence uses actual40-hull300-point sides and one untouched reserve")
	var reserve: Array=st.reserves.player.duplicate(true)
	var max_age: float=0.0;var samples: Array=[];var ticks: int=0
	for tick in range(120):
		if st.result!=null:break
		B.update(st,DT);ticks+=1
		var ages: Array=st.tactical.metrics.decisionAges
		for age in ages:max_age=maxf(max_age,float(age))
		check(max_age<=0.2+0.000001,"all real due decisions remain within0.2s despite blocked traffic and finite shared work")
		var work: Dictionary=st.tactical.budget
		check(int(st.tactical.metrics.normalLimit)==7 and ages.size()<=7 and int(work.fullRoutes)<=4 and int(work.rollouts)<=16 and int(work.samples)<=840 and int(work.clearanceTests)<=4096,"cadence retains seven due slots and every frozen shared physical-work cap")
		if tick%15==0:samples.append({"time":st.time,"ages":ages.duplicate(),"work":work.duplicate(true),"late":st.tactical.counters.lateDecisions})
	check(ticks==120 and st.ships.filter(func(ship):return not ship.sunk).size()==40,"all cadence samples are real complete-population ticks,without terminal padding")
	check(int(st.tactical.counters.lateDecisions)==0,"no actual late decision is hidden by successful unrelated physical attempts")
	check(st.reserves.player==reserve,"native cadence leaves the undeployed reserve unchanged")
	observations.append({"case":"native40-decision-cadence","ticks":ticks,"maxDecisionAge":max_age,"lateDecisions":st.tactical.counters.lateDecisions,"eventsWithin120":st.events.size(),"samples":samples})

func local_arena(blocked: bool=false) -> Dictionary:
	var spec: Dictionary=SPEC.duplicate(true);spec.range=300.0
	var source: Dictionary=D.create_ship(spec,{"uid":"local-source"})
	var enemy_spec: Dictionary=spec.duplicate(true);enemy_spec.speed=0.0
	var target: Dictionary=D.create_ship(enemy_spec,{"uid":"local-target","ammo":0.0})
	var alternate: Dictionary=D.create_ship(enemy_spec,{"uid":"local-alternate","ammo":0.0})
	var fleet: Array=[source]
	if blocked:
		var hold_spec: Dictionary=spec.duplicate(true);hold_spec.size=90.0;hold_spec.speed=0.0
		fleet.append(D.create_ship(hold_spec,{"uid":"local-held-ally","ammo":0.0}))
	var st: Dictionary=B.create({"fleet":fleet,"enemyFleet":[target,alternate],"seed":30011})
	st.islands=[];st.autoBoard=false
	source.x=500.0;source.y=850.0;source.angle=0.0
	target.x=1500.0;target.y=850.0;alternate.x=1900.0;alternate.y=1200.0
	F.command(st,target,"hold");F.command(st,alternate,"hold")
	if blocked:
		fleet[1].x=660.0;fleet[1].y=850.0;F.command(st,fleet[1],"hold")
	return {"state":st,"source":source,"target":target,"alternate":alternate}

func local_approach() -> void:
	for dt: float in [1.0/30.0,1.0/60.0]:
		for variant: String in ["paid-fire","blocked","withdraw","manual","actual-hit","target-lost"]:
			var arena: Dictionary=local_arena(variant=="blocked")
			var st: Dictionary=arena.state;var source: Dictionary=arena.source
			var start: Vector2=F.pos(source);var stage: Dictionary={};var first_phase: float=-1.0;var last_age: float=0.0
			for tick in range(roundi(0.6/dt)):
				B.update(st,dt)
				var intent: Dictionary=st.tactical.intents.get(str(source.id),{})
				var record: Dictionary=st.tactical.predictions.get(str(intent.get("pathFingerprint","")),{})
				if not record.is_empty() and record.candidate.fireMountIds.is_empty() and str(intent.phase)=="approach":
					stage=record.duplicate(true)
					var memory: Dictionary=st.tactical.memory.player.byId.get(str(source.id),{})
					if first_phase<0.0:first_phase=float(memory.phaseSince)
					last_age=float(st.time)-float(memory.phaseSince)
				check(st.tactical.budget.clearanceTests<=4096 and st.tactical.budget.samples<=840 and st.tactical.budget.rollouts<=16 and st.tactical.budget.fullRoutes<=4,"local stage retains every actual shared work cap "+variant)
			check(is_equal_approx(float(source.ammo),80.0) and not B.pop_events(st).any(func(event):return event.kind=="fire"),"out-of-range local approach grants no shot or ammunition debit "+variant)
			if variant=="blocked":
				check(stage.is_empty() and F.pos(source).distance_to(start)<1.0,"real held friendly blocks all offered local approaches without unsafe fallback")
				check(F.pos(source).distance_to(F.pos(st.ships[1]))-106.0>=7.0,"blocked local approach retains actual hull separation")
				observations.append({"case":"local-approach-blocked","dt":dt,"travel":F.pos(source).distance_to(start),"reason":st.tactical.reasons.get(str(source.id),"")})
				continue
			check(not stage.is_empty() and F.pos(source).distance_to(start)>15.0 and last_age>0.2 and first_phase>=0.0,"actual nonfiring local stage advances with retained aged phase memory "+variant)
			if stage.is_empty():continue
			check(stage.candidate.approach.size()==2 and stage.candidate["pass"].size()==1 and stage.candidate.exit.size()==1 and stage.candidate.approach[-1]==stage.candidate.exit[-1] and stage.candidate.fireMountIds.is_empty() and stage.certificate.fireWindow.mountIds.is_empty(),"certificate contains the complete offered local stopping maneuver and no remote path/fire window")
			check(stage.certificate.rolloutSamples==60 and stage.poses.size()==(121 if dt<0.02 else 61),"local certificate stores the actual30/60Hz two-second physical prefix")
			var old: Dictionary=st.tactical.intents[str(source.id)].duplicate(true)
			var boundary: Dictionary={"case":"local-approach-"+variant,"dt":dt,"stage":stage,"phaseAge":last_age,"initialTravel":F.pos(source).distance_to(start)}
			match variant:
				"paid-fire":
					var emitted: Array=[]
					for tick in range(roundi(10.0/dt)):
						B.update(st,dt);emitted.append_array(fire_events(st,source))
					check(not emitted.is_empty() and is_equal_approx(80.0-float(source.ammo),float(emitted.size())),"local stage transitions to actual paid gun fire with exact emitted-event debit")
					check(F.pos(source).distance_to(start)>500.0 and float(source.fuel)<60.0 and float(source.fuel)>=0.0,"local stages produce real finite-fuel closing rather than an aged no-progress loop")
					boundary.events=emitted;boundary.travel=F.pos(source).distance_to(start);boundary.ammo=source.ammo
				"withdraw":
					check(B.issue_order(st,[source.id],"withdraw"),"real withdrawal cancels the local stage immediately")
					var at: Vector2=F.pos(source)
					for tick in range(roundi(3.0/dt)):B.update(st,dt);B.pop_events(st)
					check(str(source.order)=="withdraw" and F.pos(source).x<at.x-40.0 and int(source.orderRevision)>int(old.orderRevision),"withdrawal retains actual helm and makes real progress away after finite turning/braking")
				"manual":
					B.set_autopilot(st,false)
					var heading: float=float(source.angle)
					for tick in range(roundi(0.4/dt)):B.update(st,dt,{"manual":true,"left":true});B.pop_events(st)
					check(str(st.tactical.manualId)==str(source.id) and not st.tactical.intents.has(str(source.id)) and absf(angle_difference(heading,float(source.angle)))>0.3,"real manual retake erases stage authority and changes the actual helm")
					B.set_autopilot(st,true)
					for tick in range(roundi(0.4/dt)):B.update(st,dt);B.pop_events(st)
					check(str(st.tactical.manualId).is_empty() and not st.tactical.intents.get(str(source.id),{}).is_empty(),"autopilot return obtains a fresh checked maneuver")
				"actual-hit":
					check(bool(C.current(st,source,old,dt).get("ok",false)),"local stage is current immediately before actual impact")
					var hp: float=float(source.hp)
					st.projectiles.append({"x":float(source.x)-35.0,"y":float(source.y),"px":float(source.x)-35.0,"py":float(source.y),"vx":3000.0,"vy":0.0,"team":"enemy","damage":24.0,"kind":"bullet","life":1.0,"owner":str(arena.target.id),"radius":2.0})
					B.update(st,dt)
					var events: Array=B.pop_events(st)
					check(events.any(func(event):return event.kind=="hit" and str(event.targetId)==str(source.id)) and float(source.hp)<hp-1.0 and not bool(C.current(st,source,old,dt).get("ok",true)),"real projectile damage invalidates the prior local-stage capability certificate")
					boundary.events=events
				"target-lost":
					var target: Dictionary=arena.target
					st.projectiles.append({"x":float(target.x)-35.0,"y":float(target.y),"px":float(target.x)-35.0,"py":float(target.y),"vx":3000.0,"vy":0.0,"team":"player","damage":4000.0,"kind":"shell","life":1.0,"owner":str(source.id),"radius":2.0})
					B.update(st,dt)
					var events: Array=B.pop_events(st)
					for tick in range(roundi(0.2/dt)):B.update(st,dt);B.pop_events(st)
					var fresh: Dictionary=st.tactical.intents.get(str(source.id),{})
					check(events.any(func(event):return event.kind=="hit" and str(event.targetId)==str(target.id)) and target.sunk and st.result==null,"actual impact removes the staged target while another real hostile keeps battle live")
					check(str(fresh.get("targetId",""))!=str(target.id) and str(fresh.get("pathFingerprint",""))!=str(old.pathFingerprint),"fresh observation replaces the dead target's local-stage authority")
					boundary.events=events;boundary.freshIntent=fresh
			observations.append(boundary)

func _admit_retained051(st: Dictionary,source: Dictionary,dt: float,label: String) -> Variant:
	var id: String=str(source.id)
	var started: float=float(st.time)
	var held: Variant=null
	var ticks: int=0
	# Both enemies' explicit hold commands precede the source in the one fair
	# due slot. Wait only through real public ticks, within the .2s admission cap.
	for tick in range(roundi(0.2/dt)):
		B.update(st,dt);B.pop_events(st);ticks+=1
		held=st.tactical.retained051.get(id)
		if held is C._Retained051:break
	var row: Dictionary={"case":"retained-admission051","variant":label,"dt":dt,"ticks":ticks,"elapsed":float(st.time)-started,"admitted":held is C._Retained051}
	if not held is C._Retained051:
		var t: Dictionary=st.tactical
		var intent: Dictionary=t.intents.get(id,{})
		var record: Dictionary=t.predictions.get(str(intent.get("pathFingerprint","")),{})
		row.reason=t.reasons.get(id,"");row.intent=intent.duplicate(true)
		row.predictionKeys=t.predictions.keys();row.recordKeys=record.keys()
		row.certificate=record.get("certificate",{}).duplicate(true)
		row.phase=t.memory[str(source.team)].byId.get(id,{}).get("phase","")
		row.lastDecision=t.lastDecision.duplicate();row.certificationAttempts=t.certificationAttempts.duplicate()
		print("RETAINED_ADMISSION_FAILED "+JSON.stringify(F.encode(row)))
	observations.append(row)
	return held

func retained_role_predicate_parity051(st: Dictionary,source: Dictionary) -> void:
	# Detached READ inputs from a real admitted maneuver. The unchanged eager
	# six-argument decision path is the reference, not a copied danger formula.
	var live_before: PackedByteArray=var_to_bytes([st.ships,st.tactical.memory,st.tactical.options])
	var base: Dictionary=T.view(st,str(source.team),[str(source.id)])
	var hostile_ids: Array=[]
	for other: Dictionary in base.ships:
		if other.team!=source.team:hostile_ids.append(str(other.id))
	check(hostile_ids.size()>=2,"retained predicate parity starts with two actually observed opponents")
	if hostile_ids.size()<2:return
	var preparation_failures051: Array=[]
	for variant: String in ["healthy-focus","below-loss","loss-two","loss-one","impaired-one","impaired-none","stationary","fire","flood","fuel","board","screen","new-protector","changed-order","salvo","burst","missing-target"]:
		var view: Dictionary=base.duplicate(true)
		view.time=3.0
		var context: Dictionary=Roles.ships_by_id(view)
		var own: Dictionary=context[str(source.id)]
		own.hp=own.maxHp;own.fire=0.0;own.water=0.0
		own.status.speedFactor=1.0;own.status.turnFactor=1.0
		own.order="engage";own.orderTarget={}
		view.options.byId[str(own.id)].role="auto"
		var previous: Dictionary=st.tactical.memory[str(source.team)].byId[str(source.id)].duplicate(true)
		previous.targetId=hostile_ids[0];previous.leaderId=""
		previous.observations=Roles.hp_history(2.85,float(own.maxHp),[]).observations
		previous.progressAt=3.0;previous.progressPos=Roles.pos(own)
		for i: int in range(hostile_ids.size()):
			var hostile: Dictionary=context[hostile_ids[i]]
			hostile.x=float(own.x)+180.0+float(i)*40.0;hostile.y=own.y
			hostile.angle=PI
			hostile.mounts=own.mounts.duplicate(true);hostile.mountShotTimes={}
			for mount: Dictionary in hostile.mounts:
				mount.angle=0.0;mount.arc=PI/3.0
				hostile.mountShotTimes[str(mount.id)]=2.99
		match variant:
			"below-loss":own.hp=float(own.maxHp)*0.92001
			"loss-two","loss-one":own.hp=float(own.maxHp)*0.92
			"impaired-one","impaired-none","stationary":own.status.speedFactor=0.2
			"fire":own.fire=25.0
			"flood":own.water=float(own.capacity)*0.5
			"fuel":own.fuel=0.0
			"board":own.order="board";own.orderTarget={"shipId":hostile_ids[0]};own.hp=float(own.maxHp)*0.92
			"screen","new-protector":
				view.options.byId[str(own.id)].role="screen"
				for i: int in range(2):
					var ally: Dictionary=own.duplicate(true)
					ally.id="predicate-protector051-"+str(i);ally.x=float(own.x)-100.0-float(i)*20.0
					if variant=="new-protector" and i==1:ally.hp=float(ally.maxHp)*0.4
					view.ships.append(ally);context[str(ally.id)]=ally
				previous.leaderId="predicate-protector051-0"
			"changed-order":own.orderRevision=int(own.orderRevision)+1;own.order="attack";own.orderTarget={"shipId":hostile_ids[0]}
			"salvo":
				view.options.byId[str(own.id)].role="striker"
				own.mounts[0].kind="rocket";own.mounts[0].arc=0.4
				previous.shotTimes={str(own.mounts[0].id):2.0};own.mountShotTimes[str(own.mounts[0].id)]=2.99
			"burst":
				previous.phase="fire-pass";previous.passShots=4;previous.passShortShots=4
				previous.passFirstShotAt=0.5;previous.passOpportunitySince=0.5
			"missing-target":context.erase(hostile_ids[0])
		if variant in ["loss-one","impaired-one"]:context[hostile_ids[1]].angle=0.0
		if variant=="impaired-none":
			for id: String in hostile_ids:context[id].angle=0.0
		if variant=="stationary":own.spec.speed=0.0
		var before: PackedByteArray=var_to_bytes([view,context,previous])
		var protected: Dictionary=Roles.protected_ally(view,own,previous,context)
		var detailed: Array=[]
		var focused: int=0
		for entry: Dictionary in Roles.shortlist(view,own,context,protected):
			detailed.append(str(entry.id))
			if Roles.threat(context[str(entry.id)],own,float(view.time))>0.75:focused+=1
		var expected: Dictionary={}
		if str(previous.targetId) in detailed:
			expected=Roles._decide(view,own,previous,context,{}, {"targetId":str(previous.targetId),"targets":detailed,"detailedIds":detailed,"scored":0})
		var actual: Dictionary=Roles._observe_retained051(view,own,previous,context)
		check(var_to_bytes(actual)==var_to_bytes(expected),"retained predicate preserves EVERY eager result/memory/detail field: "+variant)
		# Reuse only pure ally/geometry preparation, never a decision. The second
		# read exercises the shared interception pool with all existing policies.
		var prepared_view051: Dictionary=view.duplicate()
		prepared_view051._observation051=Roles._prepare_observation051(prepared_view051,context)
		for read051: int in range(2):
			if var_to_bytes(Roles._observe_retained051(prepared_view051,own,previous,context))!=var_to_bytes(actual):preparation_failures051.append(variant+":"+str(read051))
		if variant=="screen":
			for ally051: Dictionary in context.values():
				if ally051.team!=own.team or ally051.id==own.id:continue
				var row051: Dictionary=prepared_view051._observation051.rows[str(ally051.id)]
				var support_score051: float=Roles._leader_score(view,own,ally051,true)
				for read051: int in range(2):
					if Roles._leader_score(prepared_view051,own,ally051,true,row051)!=support_score051:preparation_failures051.append("support-score:"+str(ally051.id))
			var later051: Dictionary=prepared_view051.duplicate();later051.time=float(view.time)+1.0/60.0
			var revision051: Dictionary=prepared_view051.duplicate();revision051.snapshotRevision=int(view.snapshotRevision)+1
			var options051: Dictionary=prepared_view051.duplicate();options051.options=view.options.duplicate(true)
			check(Roles._observation051(later051,context)==null and Roles._observation051(revision051,context)==null and Roles._observation051(options051,context)==null and Roles._observation051(prepared_view051,context.duplicate())==null,"retained preparation rejects a later tick, revision, replaced options or foreign context")
		var public_choice: Dictionary=Roles.decide(view,own,previous,context)
		var predicate_choice: Dictionary=Roles._decide(view,own,previous,context,{}, {},protected)
		check(var_to_bytes(predicate_choice)==var_to_bytes(public_choice),"same-call predicate preserves complete public choice, scores, memory and result: "+variant)
		check(var_to_bytes([view,context,previous])==before,"retained predicate does not mutate current inputs or previous memory: "+variant)
		if variant in ["healthy-focus","below-loss","stationary"]:check(focused>=2 and not bool(actual.danger),"actual focus can be numerically high without changing danger or outputs: "+variant)
		if variant in ["loss-two","impaired-one"]:check(bool(actual.danger),"current focus still triggers the existing loss/impairment escape predicate: "+variant)
		if variant in ["loss-one","impaired-none"]:check(not bool(actual.danger),"focus still requires the existing live threshold: "+variant)
		if variant=="new-protector":check(str(actual.state.leaderId)=="predicate-protector051-1","same-call protector reflects a newly wounded ally")
		if variant=="salvo":check(bool(actual.state.passSpent.get(str(own.mounts[0].id),false)),"retained observation preserves actual fixed-tube shot accounting")
		if variant=="missing-target":check(actual.is_empty(),"removed current target still forces a full choice")
	check(preparation_failures051.is_empty(),"same-begin prepared/reused observation preserves all existing policy results: "+str(preparation_failures051))
	check(var_to_bytes([st.ships,st.tactical.memory,st.tactical.options])==live_before,"detached retained predicate trials preserve the actual admitted battle")

func _physical_preference_drop051(arena: Dictionary,held: Variant,label: String,retained: bool=true) -> Variant:
	var st: Dictionary=arena.state;var source: Dictionary=arena.source;var id: String=str(source.id)
	var preference: Variant=st.tactical.preferences051.get(id)
	check(preference is C._Preference051 and st.tactical.memory.player.reservations.has(id),"semantic case starts with real authority and its hard reservation: "+label)
	if not preference is C._Preference051:return null
	var others: Dictionary={}
	for side: String in ["player","enemy"]:
		others[side]=st.tactical.memory[side].reservations.duplicate(true);others[side].erase(id)
	var memory: PackedByteArray=var_to_bytes(st.tactical.memory.player.byId[id])
	var blocker: Dictionary=arena.alternate
	var old: Vector2=F.pos(blocker)
	blocker.x=float(source.x)+30.0;blocker.y=source.y
	if not retained:st.tactical.retained051.erase(id) # Leave the real public certificate current.
	T.after_motion(st)
	var physical: PackedByteArray=var_to_bytes([st.ships,st.rng.state])
	var control: Dictionary=T.helm(st,source)
	check(bool(control.get("blocked",false)) and float(control.throttle)==0.0 and (not retained or not held.step_ok) and not st.tactical.intents.has(id) and not st.tactical.retained051.has(id),"actual occupied next step immediately revokes movement/fire authority: "+label)
	check(is_same(st.tactical.preferences051.get(id),preference) and preference.chosen_at==held.chosen_at and not st.tactical.memory.player.reservations.has(id),"physical-only drop preserves original semantic deadline and retires its reservation: "+label)
	check(st.tactical.memory.player.reservations==others.player and st.tactical.memory.enemy.reservations==others.enemy and var_to_bytes(st.tactical.memory.player.byId[id])==memory,"revocation preserves unrelated reservations and role memory: "+label)
	var gates: Dictionary=T.fire_gates(st,source)
	var braked: Dictionary=T.helm(st,source)
	check(gates.is_empty() and float(braked.throttle)==0.0 and bool(braked.get("blocked",false)) and var_to_bytes([st.ships,st.rng.state])==physical,"semantic eligibility cannot waive live contact, fire, integrate motion, spend stores or advance RNG: "+label)
	blocker.x=old.x;blocker.y=old.y;T.after_motion(st)
	return preference

func retained_semantic_preference051() -> void:
	for dt: float in [1.0/30.0,1.0/60.0]:
		var arena: Dictionary=local_arena();var st: Dictionary=arena.state;var source: Dictionary=arena.source;var id: String=str(source.id)
		var held: Variant=_admit_retained051(st,source,dt,"semantic-recertification")
		check(held is C._Retained051,"semantic recertification begins with a real maneuver dt="+str(dt))
		if not held is C._Retained051:continue
		T.enable_planning051(st);worker_states051.append(st)
		check(st.tactical.has("workers051"),"semantic reuse case opts the actual multi-hostile fleet into pooled planning dt="+str(dt))
		var preference: Variant=_physical_preference_drop051(arena,held,"recertification "+str(dt))
		if not preference is C._Preference051:continue
		var original: float=preference.chosen_at
		var memory: PackedByteArray=var_to_bytes(st.tactical.memory.player.byId[id])
		var observed_at: float=float(st.tactical.lastDecision[id])
		var current: Dictionary={}
		var shared: Dictionary=T._retained_observation051(st,id,null,current,true)
		check(not shared.is_empty() and float(st.tactical.lastDecision[id])==observed_at and var_to_bytes(st.tactical.memory.player.byId[id])==memory,"shared fleet observation alone preserves the revoked authority and observation clock dt="+str(dt))
		check(not T._observe_retained051(st,id,null,current) and current.get("freshDecisions051",{}).has(id),"physical-drop observation prepares a fresh decision and still requires new geometry dt="+str(dt))
		if not current.get("freshDecisions051",{}).has(id):continue
		var fresh: Dictionary=current.freshDecisions051[id]
		check(not current.retainedObservation051.has(id) and fresh.decision==shared and not is_same(fresh.decision,shared),"fresh-decision API receives the consumed same-begin observation as its detached complete decision dt="+str(dt))
		var context: Dictionary=current.sides.player.duplicate();context[id]=current.owners[id]
		var read_view: Dictionary={"time":float(st.time),"side":"player","options":st.tactical.options,"groups":st.tactical.groups,"ships":context.values(),"mission":current.mission}
		# Eager canonical decision with the current shortlist is the reference;
		# it recomputes protector/focus instead of calling the optimized observer.
		var previous: Dictionary=st.tactical.memory.player.byId[id]
		var protected: Dictionary=Roles.protected_ally(read_view,context[id],previous,context)
		var detailed: Array=[]
		for entry: Dictionary in Roles.shortlist(read_view,context[id],context,protected):detailed.append(str(entry.id))
		var expected: Dictionary=Roles._decide(read_view,context[id],previous,context,{}, {"targetId":str(previous.targetId),"targets":detailed,"detailedIds":detailed,"scored":0})
		check(var_to_bytes(fresh.decision)==var_to_bytes(expected) and not is_same(fresh.decision.state,expected.state),"prepared decision preserves EVERY current role/result/HP field and owns its memory dt="+str(dt))
		check(is_same(fresh.owner,current.owners[id]) and int(fresh.revision)==int(st.tactical.snapshotRevision) and float(fresh.at)==float(st.time) and float(fresh.originalPreferenceChosenAt)==original,"prepared provenance binds exact owner observation, begin generation/time and original choice dt="+str(dt))
		var view: Dictionary=T._begin_view051(st,"player",[id],null,current)
		var prepared: Dictionary=Planner._prepare_begin(view,st.tactical.memory.player,current.indexes.player,current.freshDecisions051)
		check(var_to_bytes(prepared.decisions[id])==var_to_bytes(fresh.decision) and int(prepared.scored)==0 and not current.freshDecisions051.has(id) and float(prepared.originalPreferenceChosenAt051.get(id,-1.0))==original,"owned planning consumes the complete fresh decision ONCE without target rescoring dt="+str(dt))
		check(not prepared.candidates.is_empty() and not st.tactical.intents.has(id) and not st.tactical.retained051.has(id) and var_to_bytes(st.tactical.memory.player.byId[id])==memory and float(st.tactical.lastDecision[id])==observed_at,"candidate preparation grants no certificate, memory publication or observation clock dt="+str(dt))
		var repeated: Dictionary=Planner._prepare_begin(view,st.tactical.memory.player,current.indexes.player,current.freshDecisions051)
		check(int(repeated.scored)>0 and not repeated.get("originalPreferenceChosenAt051",{}).has(id),"consumed fresh records cannot skip another full choice dt="+str(dt))
		var retry_at051: float=float(st.tactical.physicalRetry051[id].observedAt)
		var attempt051: float=float(st.tactical.certificationAttempts[id])
		var decisions051: int=int(st.tactical.counters.decisions)
		var physical051: PackedByteArray=var_to_bytes([st.ships,st.rng.state,held.record.certificate])
		var retry_current051: Dictionary={}
		check(T._observe_retained051(st,id,null,retry_current051,true) and float(st.tactical.lastDecision[id])==float(st.time) and int(st.tactical.counters.decisions)==decisions051+1 and float(st.tactical.physicalRetry051[id].observedAt)==retry_at051 and float(st.tactical.certificationAttempts[id])==attempt051 and not retry_current051.has("freshDecisions051") and not st.tactical.intents.has(id) and not st.tactical.retained051.has(id) and not st.tactical.memory.player.reservations.has(id) and var_to_bytes([st.ships,st.rng.state,held.record.certificate])==physical051,"stable physical retry publishes a real current observation without rebuilding, moving its retry deadline or restoring authority dt="+str(dt))
		var recertified: Variant=null
		for tick: int in range(ceili(0.2/dt)):
			B.update(st,dt);B.pop_events(st)
			recertified=st.tactical.retained051.get(id)
			if recertified is C._Retained051:break
		check(recertified is C._Retained051,"real battle ticks recertify the restored clear route dt="+str(dt))
		if not recertified is C._Retained051:continue
		check(not is_same(recertified,held) and recertified.chosen_at==original and recertified.record.certificate.checkedAt>held.record.certificate.checkedAt and T._current051(st,source,st.tactical.intents[id]).ok,"new current certificate retains the ORIGINAL semantic cutoff dt="+str(dt))
		for tick: int in range(ceili(0.36/dt)):
			if float(st.time)-original>=0.35-0.000001:break
			B.update(st,dt);B.pop_events(st)
		check(is_same(st.tactical.retained051.get(id),recertified) and float(st.tactical.lastDecision[id])-original>=0.30-0.000001,"fresh stable observations retain the same original preference beyond the intentionally replaced0.30 policy dt="+str(dt))
		for tick: int in range(ceili(0.16/dt)):
			if float(st.time)-original>0.45+0.000001:break
			B.update(st,dt);B.pop_events(st)
		check(not is_same(st.tactical.retained051.get(id),recertified) and not C._retained_current051(st,source,recertified).ok,"recertification and stable observations cannot extend original chosenAt+0.45 dt="+str(dt))
		observations.append({"case":"semantic-preference051","dt":dt,"originalChosenAt":original,"recertifiedAt":recertified.record.certificate.checkedAt,"cutoffObservedAt":st.time})
		T.retire_planning051(st);T.drain_planning051()
	# The same physical revocation must retire a PUBLIC intent's reservation,
	# even when its private retained descriptor has already been removed.
	var public_arena: Dictionary=local_arena()
	var public_held: Variant=_admit_retained051(public_arena.state,public_arena.source,1.0/60.0,"semantic-public-intent")
	check(public_held is C._Retained051,"non-retained helm case obtains its public certificate from real admission")
	if public_held is C._Retained051:
		T.enable_planning051(public_arena.state);worker_states051.append(public_arena.state)
		_physical_preference_drop051(public_arena,public_held,"public-intent",false)
	for variant: String in ["command","options","direct-options","terrain","owner","target","capability","phase","shot","manual","deadline","begin-revision","begin-time","begin-own","begin-observed","begin-memory"]:
		var arena: Dictionary=local_arena();var st: Dictionary=arena.state;var source: Dictionary=arena.source;var id: String=str(source.id)
		var held: Variant=_admit_retained051(st,source,1.0/60.0,"semantic-urgent-"+variant)
		check(held is C._Retained051,"urgent semantic case begins with actual authority: "+variant)
		if not held is C._Retained051:continue
		T.enable_planning051(st);worker_states051.append(st)
		var preference: Variant=_physical_preference_drop051(arena,held,variant)
		if not preference is C._Preference051:continue
		var current: Dictionary={}
		var shared: Dictionary=T._retained_observation051(st,id,null,current,true)
		check(not shared.is_empty() and current.retainedObservation051.has(id),"urgent case starts with a real same-begin semantic observation: "+variant)
		match variant:
			"command":check(B.issue_order(st,[id],"withdraw") and not st.tactical.preferences051.has(id),"command acceptance erases semantic eligibility immediately")
			"options":check(T.set_options(st,[id],{"doctrine":"cautious"}) and not st.tactical.preferences051.has(id),"option transaction erases semantic eligibility immediately")
			"direct-options":st.tactical.options.byId[id].doctrine="cautious"
			"manual":B.set_autopilot(st,false);check(not st.tactical.preferences051.has(id),"manual-control transaction immediately erases semantic eligibility")
			"terrain":st.islands=[F.rectangle(100.0,100.0,140.0,140.0)];st.tactical.geometry=Routes.terrain(st)
			"owner":st.tactical.ships[id]=source.duplicate(true)
			"target":st.tactical.ships[str(preference.target_id)].sunk=true
			"capability":source.engine=0.0
			"phase":st.tactical.memory.player.byId[id].phase="breakaway"
			"shot":source.mountShotTimes[str(st.tactical.mountCache[id].mounts[0].id)]=float(st.time)
			"deadline":st.time=preference.chosen_at+0.45
			"begin-revision":st.tactical.snapshotRevision+=1
			"begin-time":st.time=float(st.time)+1.0/60.0
			"begin-own":current.owners[id]=current.owners[id].duplicate(true)
			"begin-observed":st.tactical.observed[id]=st.tactical.observed[id].duplicate(true)
			"begin-memory":st.tactical.memory.player.byId[id]=st.tactical.memory.player.byId[id].duplicate(true)
		check(not T._observe_retained051(st,id,null,current) and not current.get("freshDecisions051",{}).has(id) and not st.tactical.preferences051.has(id) and not st.tactical.retained051.has(id) and not st.tactical.intents.has(id) and not st.tactical.memory.player.reservations.has(id),"current urgent change/hard deadline cannot lend a semantic decision or authority: "+variant)

func retained_synchronous_policy051() -> void:
	# Actual one-per-side workload policy, both sides, no mission/hull/seed gate.
	# These public ticks isolate reconsideration BEFORE the fleet .45s cutoff.
	var dt: float=1.0/60.0
	for side: String in ["player","enemy"]:
		var spec: Dictionary=SPEC.duplicate(true);spec.range=300.0
		var player: Dictionary=D.create_ship(spec,{"uid":"sync-retained-player"})
		var enemy: Dictionary=D.create_ship(spec,{"uid":"sync-retained-enemy"})
		var st: Dictionary=B.create({"fleet":[player],"enemyFleet":[enemy],"seed":30011,"islands":[]})
		st.islands=[];st.autoBoard=false
		player.x=500.0;player.y=850.0;player.angle=0.0
		enemy.x=1500.0;enemy.y=850.0;enemy.angle=PI
		T.enable_planning051(st)
		check(not st.tactical.has("workers051"),"real ordinary duel retains general synchronous workload policy: "+side)
		var source: Dictionary=player if side=="player" else enemy
		var blocker: Dictionary=enemy if side=="player" else player
		var id: String=str(source.id)
		var held: Variant=_admit_retained051(st,source,dt,"sync-policy-"+side)
		check(held is C._Retained051,"ordinary synchronous side obtains real certified authority: "+side)
		if not held is C._Retained051:continue
		var original: float=held.chosen_at
		for tick: int in range(ceili(0.40/dt)):
			if float(st.time)-original>=0.40-0.000001:break
			B.update(st,dt);B.pop_events(st)
		var reconsidered: Variant=st.tactical.retained051.get(id)
		check(reconsidered is C._Retained051 and not is_same(reconsidered,held) and float(reconsidered.chosen_at)-original>=0.30-0.000001 and float(st.time)-original<0.45,"ordinary sync makes a full choice after .30s, before fleet .45s retention: "+side)
		if not reconsidered is C._Retained051:continue
		check(T._current051(st,source,st.tactical.intents.get(id,{})).ok and reconsidered.record.certificate.checkedAt>held.record.certificate.checkedAt,"ordinary reconsideration obtains a NEW current physical certificate: "+side)
		var old: Vector2=F.pos(blocker)
		blocker.x=float(source.x)+30.0;blocker.y=source.y;T.after_motion(st)
		var control: Dictionary=T.helm(st,source)
		check(bool(control.get("blocked",false)) and float(control.throttle)==0.0 and not reconsidered.step_ok and not st.tactical.intents.has(id) and not st.tactical.retained051.has(id) and not st.tactical.preferences051.has(id),"ordinary physical veto retires authority AND semantic eligibility immediately: "+side)
		check(not st.tactical.memory.player.reservations.has(id) and not st.tactical.memory.enemy.reservations.has(id),"ordinary physical veto clears every side's reservation for this hull: "+side)
		var physical: PackedByteArray=var_to_bytes([st.ships,st.rng.state])
		check(T.fire_gates(st,source).is_empty() and bool(T.helm(st,source).get("blocked",false)) and var_to_bytes([st.ships,st.rng.state])==physical,"ordinary veto cannot fire, move, spend stores or advance RNG: "+side)
		blocker.x=old.x;blocker.y=old.y;T.after_motion(st)
		var current: Dictionary={}
		check(not T._observe_retained051(st,id,null,current) and not current.get("freshDecisions051",{}).has(id),"ordinary physical loss cannot lend a prepared semantic decision: "+side)
		var memory: PackedByteArray=var_to_bytes(st.tactical.memory[side])
		var view: Dictionary=T._begin_view051(st,side,[id],null,current)
		var prepared: Dictionary=Planner._prepare_with_worker051(view,st.tactical.memory[side],{},current.indexes[side],current.get("freshDecisions051",{}))
		var expected: Dictionary=Roles.decide(view,prepared.context[id],st.tactical.memory[side].byId[id],prepared.context,st.tactical.memory[side].reservations)
		check(int(prepared.scored)>0 and var_to_bytes(prepared.decisions[id])==var_to_bytes(expected) and not prepared.originalPreferenceChosenAt051.has(id),"ordinary replan runs the complete current canonical choice without semantic reuse: "+side)
		check(var_to_bytes(st.tactical.memory[side])==memory and not st.tactical.intents.has(id),"ordinary candidate preparation grants no memory or physical authority: "+side)
		var fresh: Variant=null
		for tick: int in range(ceili(0.2/dt)):
			B.update(st,dt);B.pop_events(st)
			fresh=st.tactical.retained051.get(id)
			if fresh is C._Retained051:break
		check(fresh is C._Retained051 and not is_same(fresh,reconsidered) and float(fresh.chosen_at)>float(reconsidered.chosen_at) and T._current051(st,source,st.tactical.intents.get(id,{})).ok,"ordinary physical recovery requires a full choice and NEW live certificate: "+side)
		check(not st.tactical.has("workers051"),"ordinary policy stays synchronous through reconsideration and physical recovery: "+side)
		observations.append({"case":"retained-sync-policy051","side":side,"originalChosenAt":original,"reconsideredAt":reconsidered.chosen_at,"recoveredAt":st.time})

func retained_maneuver051() -> void:
	for dt: float in [1.0/30.0,1.0/60.0]:
		var arena: Dictionary=local_arena()
		var st: Dictionary=arena.state
		var source: Dictionary=arena.source
		var id: String=str(source.id)
		var held=_admit_retained051(st,source,dt,"lease")
		check(held is C._Retained051,"real accepted engage maneuver admits one typed descriptor dt="+str(dt))
		if not held is C._Retained051:continue
		retained_role_predicate_parity051(st,source)
		var current: Dictionary={}
		var last: float=float(st.tactical.lastDecision[id])
		var prior: PackedByteArray=var_to_bytes(st.tactical.memory.player.byId[id])
		var semantic: Dictionary=T._retained_observation051(st,id,null,current,true)
		check(not semantic.is_empty() and is_same(current.retainedObservation051[id].decision,semantic) and float(st.tactical.lastDecision[id])==last and var_to_bytes(st.tactical.memory.player.byId[id])==prior and is_same(st.tactical.retained051.get(id),held),"sharing a real pure observation grants no memory/clock/authority dt="+str(dt))
		check(T._observe_retained051(st,id,null,current) and not current.retainedObservation051.has(id) and is_same(st.tactical.memory.player.byId[id],semantic.state) and held.chosen_at==last,"normal retained observation consumes the EXACT same semantic result once and preserves original choice dt="+str(dt))
		var certificate_bytes: PackedByteArray=var_to_bytes(held.record.certificate)
		var old_intent: Dictionary=held.intent.duplicate(true)
		var start: Vector2=F.pos(source)
		for tick in range(ceili(0.26/dt)):
			B.update(st,dt);B.pop_events(st)
			if float(st.time)-held.chosen_at>0.2+0.000001:break
		check(is_same(st.tactical.retained051.get(id),held) and held.step_ok and held.step_at==float(st.time),"retained route crosses the old lease with fresh actual-step clearance dt="+str(dt))
		check(not C.current(st,source,old_intent,dt).ok and var_to_bytes(held.record.certificate)==certificate_bytes,"original public corridor certificate expires unchanged dt="+str(dt))
		check(F.pos(source).distance_to(start)>0.0 and float(source.fuel)<60.0,"retained execution moves the real hull with finite fuel dt="+str(dt))
		check(T._current051(st,source,st.tactical.intents.get(id,{}),dt).ok,"private execution observes current capability after movement dt="+str(dt))
		# Move a real hostile into this actual next step; no synthetic permission.
		arena.target.x=float(source.x)+30.0;arena.target.y=float(source.y)
		B.update(st,dt);B.pop_events(st)
		check(not held.step_ok and not st.tactical.retained051.has(id),"fresh hostile clearance brakes and discards retained authority dt="+str(dt))
		observations.append({"case":"retained-maneuver051","dt":dt,"expiredPublicCertificateUnchanged":var_to_bytes(held.record.certificate)==certificate_bytes,"blockedStep":not held.step_ok})
	for action: String in ["deadline","terrain","withdraw","manual","hit"]:
		var arena: Dictionary=local_arena()
		var st: Dictionary=arena.state
		var source: Dictionary=arena.source
		var id: String=str(source.id)
		var dt: float=1.0/60.0
		var held=_admit_retained051(st,source,dt,action)
		check(held is C._Retained051,"retained invalidation case starts from actual authority "+action)
		if not held is C._Retained051:continue
		match action:
			"deadline":
				for tick in range(28):B.update(st,dt);B.pop_events(st)
				check(not is_same(st.tactical.retained051.get(id),held),"ordinary full choice replaces the descriptor within0.45s including slots")
			"terrain":
				st.islands=[F.rectangle(float(source.x)-40.0,float(source.y)-40.0,float(source.x)+40.0,float(source.y)+40.0)]
				B.update(st,dt);B.pop_events(st)
				check(int(st.tactical.terrainRevision)!=held.terrain_revision and not is_same(st.tactical.retained051.get(id),held),"terrain transaction invalidates the static path proof on the next real tick")
			"withdraw":
				check(B.issue_order(st,[id],"withdraw") and not st.tactical.retained051.has(id),"explicit withdrawal cancels retained authority at command acceptance")
			"manual":
				B.set_autopilot(st,false);B.update(st,dt,{"manual":true,"left":true});B.pop_events(st)
				check(str(st.tactical.manualId)==id and not st.tactical.retained051.has(id) and not st.tactical.intents.has(id),"manual retake removes autonomous authority immediately")
			"hit":
				var hp: float=float(source.hp)
				st.projectiles.append({"x":float(source.x)-35.0,"y":float(source.y),"px":float(source.x)-35.0,"py":float(source.y),"vx":3000.0,"vy":0.0,"team":"enemy","damage":24.0,"kind":"bullet","life":1.0,"owner":str(arena.target.id),"radius":2.0})
				B.update(st,dt)
				var events: Array=B.pop_events(st)
				check(events.any(func(event):return event.kind=="hit" and str(event.targetId)==id) and float(source.hp)<hp-1.0 and not T._current051(st,source,held.intent,dt).ok,"actual impact immediately invalidates retained capability authority")

	retained_semantic_preference051()
	retained_synchronous_policy051()

func traffic_budget051(limit: int=4096) -> Dictionary:
	return {"fullRoutes":0,"cacheHits":0,"rollouts":0,"samples":0,"clearanceTests":0,"exhaustions":0,"rolled":{},"clearanceLimit":limit}

func traffic_route051(geometry: Dictionary,owner: Dictionary,candidate: Dictionary,others: Array,seconds: float,closed: bool=false) -> Dictionary:
	var st: Dictionary={"tactical":{"routeCache":{},"cells":Routes.grid([owner]+others,true)}}
	var budget: Dictionary=traffic_budget051()
	var proofs: Routes._BeginProofs051=Routes._begin_proofs051(geometry,st.tactical.cells,{str(owner.id):owner})
	if closed:Routes._close_begin_proofs051(proofs)
	var result: Dictionary=Routes.refine_live(st,geometry,owner,candidate,budget) if seconds<0.0 else Routes._refine_begin051(st,geometry,owner,candidate,budget,proofs,seconds)
	if not closed:Routes._close_begin_proofs051(proofs)
	return {"result":result,"budget":budget}

func traffic_prefix051() -> void:
	# Detached requests exercise planning policy only, never create live authority.
	var seconds: float=Stations.LIVE_TRAFFIC_SECONDS051
	var geometry: Dictionary={"key":"traffic-prefix051","revision":51,"obstacles":[]}
	var owner: Dictionary={"id":"traffic-own051","team":"player","x":400.0,"y":800.0,"vx":0.0,"vy":0.0,"spec":{"size":16.0,"speed":100.0,"turn":2.5},"status":{"speedFactor":1.0},"fuel":60.0,"order":"move","orderTarget":{}}
	var request: Dictionary={"shipId":str(owner.id),"targetId":"shared-target051","sector":2,"approach":[Vector2(400,800),Vector2(1100,800)],"pass":[Vector2(1100,800),Vector2(1100,1000)],"exit":[Vector2(1200,1000)]}
	var before: PackedByteArray=var_to_bytes([geometry,owner,request])
	for row: Dictionary in [{"name":"late","x":900.0,"status":"valid"},{"name":"near","x":510.0,"status":"blocked"},{"name":"boundary-capsule","x":590.0,"status":"blocked"}]:
		var other: Dictionary=owner.duplicate(true);other.id="traffic-other051";other.x=row.x
		var full: Dictionary=traffic_route051(geometry,owner,request,[other],-1.0)
		var live: Dictionary=traffic_route051(geometry,owner,request,[other],seconds)
		check(full.result.status=="blocked" and live.result.status==row.status,"traffic prefix "+row.name+": full reference and private crossing policy")
		check(int(live.budget.clearanceTests)<=4096 and int(live.budget.rollouts)==0,"traffic prefix "+row.name+": original finite work limits")
		if row.name=="late":
			check(live.result.candidate==request and is_equal_approx(float(live.result.eta),12.5),"traffic prefix keeps every static waypoint and the complete ETA")
			check(traffic_route051(geometry,owner,request,[other],seconds,true).result==live.result,"closed proof fallback preserves the explicitly supplied private horizon")
		observations.append({"case":"traffic-prefix","variant":row.name,"full":full,"live":live})
	var default_st: Dictionary={"tactical":{"routeCache":{},"cells":Routes.grid([owner],true)}}
	var proofs: Routes._BeginProofs051=Routes._begin_proofs051(geometry,default_st.tactical.cells,{str(owner.id):owner})
	var default_budget: Dictionary=traffic_budget051()
	var default_result: Dictionary=Routes._refine_begin051(default_st,geometry,owner,request,default_budget,proofs)
	var full_open: Dictionary=traffic_route051(geometry,owner,request,[],-1.0)
	check(default_result==full_open.result and default_budget==full_open.budget,"omitting the private float keeps full public refinement and debit order")
	Routes._close_begin_proofs051(proofs)
	var land: Dictionary={"key":"traffic-prefix-land051","revision":52,"obstacles":[{"points":[[1000,700],[1200,700],[1200,900],[1000,900]],"lo":Vector2(1000,700),"hi":Vector2(1200,900)}]}
	check(traffic_route051(land,owner,request,[],seconds).result.status=="blocked","land beyond two seconds still rejects an unreachable full-route endpoint")
	var split: Dictionary=request.duplicate(true)
	split.approach=[Vector2(400,800),Vector2(480,800)];split["pass"]=[Vector2(480,800),Vector2(640,800)];split.exit=[Vector2(1200,800)]
	var prefix: Dictionary=Stations._reservation_begin051(split,owner,10.0,seconds)
	check(prefix.approach==split.approach and prefix["pass"]==[Vector2(480,800),Vector2(560,800)] and prefix.exit.is_empty(),"reservation boundary clips the exact fraction across approach/pass/exit")
	check(prefix["from"]==10.0 and prefix.until==12.0 and prefix.anchor==Stations.anchor(split) and prefix.targetId==split.targetId and prefix.sector==split.sector,"prefix lifetime and soft station metadata retain their distinct meanings")
	var impaired: Dictionary=owner.duplicate(true);impaired.status.speedFactor=0.5;impaired.fuel=0.0
	check(Stations._reservation_begin051(request,impaired,10.0,seconds).approach[-1]==Vector2(416,800),"reservation prefix uses the same actual speed-factor and dry-fuel nominal clock")
	var peer: Dictionary=owner.duplicate(true);peer.id="traffic-peer051";peer.x=900.0;peer.y=600.0
	var peer_request: Dictionary=request.duplicate(true);peer_request.shipId=peer.id;peer_request.approach=[Vector2(900,600),Vector2(900,1100)]
	var own_prefix: Dictionary=Stations._reservation_begin051(request,owner,10.0,seconds)
	var peer_prefix: Dictionary=Stations._reservation_begin051(peer_request,peer,10.0,seconds)
	var counter: Dictionary={"clearanceTests":0,"clearanceExhausted":0}
	check(Stations.conflict(Stations.reservation(request,owner,{"eta":12.5},10.0),Stations.reservation(peer_request,peer,{"eta":12.5},10.0),counter,4096),"public reservations still hard-veto their complete crossing and shared station")
	counter={"clearanceTests":0,"clearanceExhausted":0}
	check(not Stations._conflict_begin051(own_prefix,peer_prefix,counter,4096),"distant crossing/shared anchor/sector cannot veto two disjoint private prefixes")
	var public_shape: Dictionary=Stations.reservation(request,owner,{"eta":12.5},10.0)
	check(public_shape.approach==request.approach and public_shape["pass"]==request["pass"] and public_shape.exit==request.exit and public_shape.until==24.5 and not public_shape.has("origin051"),"public reservation arrays, ETA lifetime and schema stay unchanged")
	var st: Dictionary={"time":10.0,"tactical":{"memory":{"player":{"reservations":{str(peer.id):peer_prefix}}},"budget":traffic_budget051()}}
	check(T._reserved_path(st,"player",owner,request)=="valid","Runtime early hard-reservation gate uses the same prefix policy")
	var main_seconds: float=Planner.CERT_PREFIX_SECONDS
	peer.x=480.0;peer.y=700.0;peer_request.approach=[Vector2(480,700),Vector2(480,1100)]
	var later_peer: Dictionary=Stations._reservation_begin051(peer_request,peer,10.0,seconds)
	counter={"clearanceTests":0,"clearanceExhausted":0}
	check(Stations._conflict_begin051(own_prefix,later_peer,counter,4096),"old later crossing still blocks an explicitly requested two-second reservation")
	st.tactical.memory.player.reservations[str(peer.id)]=Stations._reservation_begin051(peer_request,peer,10.0,main_seconds)
	st.tactical.budget=traffic_budget051()
	check(T._reserved_path(st,"player",owner,request)=="valid","old later crossing lies beyond both renewable main prefixes and can proceed now")
	# Nominal speed80 gives 24 units in .3s. Old x480 crossing is 56 units
	# beyond the owner's clipped endpoint, outside the 39-unit lane clearance.
	# Imminent starts are 56.569 apart (>39 padding, >32 physical); endpoints
	# (424,800)/(440,784) are 22.627 apart. Separation reaches39 at .1553s
	# and32 at .2172s, both INSIDE .3s; the current starts never overlap.
	peer.x=440.0;peer.y=760.0;peer_request.approach=[Vector2(440,760),Vector2(440,1100)]
	var imminent_peer: Dictionary=Stations._reservation_begin051(peer_request,peer,10.0,main_seconds)
	var imminent_owner: Dictionary=Stations._reservation_begin051(request,owner,10.0,main_seconds)
	var physical: float=Roles.radius(owner)+Roles.radius(peer)
	var lane_clearance: float=float(imminent_owner.radius)+float(imminent_peer.radius)-9.0
	check(is_equal_approx(main_seconds,0.3) and imminent_owner.approach[-1]==Vector2(424,800) and imminent_peer.approach[-1]==Vector2(440,784) and Roles.pos(owner).distance_to(Roles.pos(peer))>lane_clearance and lane_clearance>physical and imminent_owner.approach[-1].distance_to(imminent_peer.approach[-1])<physical,"imminent crossing starts physically separate and enters physical clearance inside the actual .3s prefix")
	st.tactical.memory.player.reservations[str(peer.id)]=imminent_peer
	st.tactical.budget=traffic_budget051()
	check(T._reserved_path(st,"player",owner,request)=="blocked","within-prefix crossing still blocks the Runtime early gate")
	var no_origin: Dictionary=request.duplicate(true);no_origin.approach=[Vector2(1100,800)]
	st.tactical.budget=traffic_budget051()
	check(T._reserved_path(st,"player",owner,no_origin)=="blocked","first current-position-to-waypoint edge is included without enlarging leg caps")
	st.tactical.budget=traffic_budget051(0)
	check(T._reserved_path(st,"player",owner,request)=="pending" and st.tactical.budget.clearanceTests==0 and st.tactical.budget.exhaustions==1,"prefix reservation exhaustion remains pending and respects the unchanged ledger")
	# Retain the existing explicit two-second expiry coverage as well.
	st.tactical.memory.player.reservations[str(peer.id)]=Stations._reservation_begin051(peer_request,peer,10.0,seconds)
	st.time=12.0;st.tactical.budget=traffic_budget051()
	check(T._reserved_path(st,"player",owner,request)=="valid" and st.tactical.budget.clearanceTests==0,"expired private reservations stop vetoing at their two-second lifetime")
	check(var_to_bytes([geometry,owner,request])==before,"traffic and reservation policy cannot mutate original observations or full requests")
	traffic_resolve051()
	for dt: float in [1.0/30.0,1.0/60.0]:
		var arena: Dictionary=local_arena()
		var battle: Dictionary=arena.state;var source: Dictionary=arena.source;var id: String=str(source.id)
		var held: Variant=_admit_retained051(battle,source,dt,"traffic-prefix-braking")
		check(held is C._Retained051,"private prefix braking starts with real accepted authority dt="+str(dt))
		if not held is C._Retained051:continue
		B.update(battle,dt);B.pop_events(battle)
		var speed: float=Vector2(source.vx,source.vy).length()
		arena.target.x=float(source.x)+90.0;arena.target.y=float(source.y)
		B.update(battle,dt);B.pop_events(battle)
		var helm: Dictionary=T.helm(battle,source)
		check(speed>0.0 and Vector2(source.vx,source.vy).length()<speed and float(helm.throttle)==0.0 and not held.step_ok and not battle.tactical.retained051.has(id),"later real hostile immediately brakes/discards the retained maneuver dt="+str(dt))
		observations.append({"case":"traffic-prefix-braking","dt":dt,"speedBefore":speed,"speedAfter":Vector2(source.vx,source.vy).length(),"helm":helm,"budget":battle.tactical.budget.duplicate(true)})

func traffic_resolve051() -> void:
	# Mint the offer through actual route/certificate code; no fabricated grant.
	var arena: Dictionary=local_arena();var st: Dictionary=arena.state;var source: Dictionary=arena.source
	check(B.issue_order(st,[source.id],"move",{"x":1100.0,"y":850.0}),"prefix resolve accepts an ordinary explicit movement request")
	B.update(st,DT);B.pop_events(st)
	var view: Dictionary=T.view(st,"player",[str(source.id)])
	var own: Dictionary=Roles.ships_by_id(view)[str(source.id)]
	var memory: Dictionary={"byId":{},"reservations":{}}
	var planning: Dictionary=Planner._prepare_begin(view,memory)
	check(not planning.candidates.is_empty(),"prefix resolve obtains its bounded ordinary public candidates")
	if planning.candidates.is_empty():return
	var raw: Dictionary=planning.candidates[0]
	var budget: Dictionary=traffic_budget051()
	var proofs: Routes._BeginProofs051=Routes._begin_proofs051(st.tactical.geometry,st.tactical.cells,{str(own.id):own})
	var refined: Dictionary=Routes._refine_begin051(st,st.tactical.geometry,own,raw,budget,proofs,Stations.LIVE_TRAFFIC_SECONDS051)
	Routes._close_begin_proofs051(proofs)
	check(refined.status=="valid","prefix resolve retains complete static geometry")
	if refined.status!="valid":return
	var certificate: Dictionary=C._certify_refined_live(st,view,own,refined,Planner.fingerprint(refined.candidate),budget)
	check(certificate.status=="valid","prefix resolve offer has a real current route certificate")
	if certificate.status!="valid":return
	var peer: Dictionary=own.duplicate(true);peer.id="resolve-peer051";peer.x=200.0;peer.y=300.0
	var other: Dictionary=refined.candidate.duplicate(true);other.shipId=peer.id;other.approach=[Vector2(200,300),other.approach[-1]]
	memory.reservations[str(peer.id)]=Stations._reservation_begin051(other,peer,float(view.time),Stations.LIVE_TRAFFIC_SECONDS051)
	planning=Planner._prepare_begin(view,memory)
	var offers: Array=[{"candidate":refined.candidate,"certificate":certificate}]
	var before: PackedByteArray=var_to_bytes([view,memory,offers])
	var public_result: Dictionary=Planner.resolve(view,memory,offers)
	var default_result: Dictionary=Planner._resolve_planned(view,memory,offers,planning)
	var live: Dictionary=Planner._resolve_planned(view,memory,offers,Planner._prepare_begin(view,memory),Stations.LIVE_TRAFFIC_SECONDS051)
	check(public_result==default_result and int(public_result.counters.accepted)==0,"public resolve and omitted private float retain the full hard station veto")
	check(int(live.counters.accepted)==1 and live.memory.reservations[str(own.id)].until==float(view.time)+Stations.LIVE_TRAFFIC_SECONDS051,"private resolve publishes the accepted two-second hard prefix")
	check(var_to_bytes([view,memory,offers])==before,"public/private resolution preserves source view, memory and actual offer")
	# Same real route/certificate, admitted once by the closed begin. The fast
	# path must produce the exact same result and lend no proof to copies.
	var admitted_plan: Dictionary=Planner._prepare_begin(view,memory)
	var admitted: Dictionary=T._seal_begin_offer051(admitted_plan.sources[str(refined.candidate.candidateId)],refined.candidate,certificate,Planner.fingerprint(refined.candidate))
	check(not admitted.is_empty() and admitted.is_read_only() and admitted.candidate.is_read_only() and admitted.candidate.approach.is_read_only() and admitted.certificate.fireWindow.is_read_only(),"same-begin actual offer seals its request paths and physical certificate")
	admitted_plan.beginView051=view;admitted_plan.beginOffers051={str(refined.candidate.candidateId):admitted}
	var admitted_result: Dictionary=Planner._resolve_planned(view,memory,[admitted],admitted_plan,Stations.LIVE_TRAFFIC_SECONDS051)
	check(admitted_result==live,"same-begin admission preserves exact current certificate, choices, memory and reservation debits")
	check(Planner._admitted_begin_offer051(view,admitted_plan,admitted) and not Planner._admitted_begin_offer051(view.duplicate(true),admitted_plan,admitted) and not Planner._admitted_begin_offer051(view,admitted_plan,admitted.duplicate(true)),"same-begin proof requires both exact view and exact immutable offer identity")
	var counterfeit: Dictionary=admitted.duplicate(true)
	counterfeit.candidate.approach=[Vector2(1234,4321)]
	var counterfeit_result: Dictionary=Planner._resolve_planned(view,memory,[counterfeit],admitted_plan,Stations.LIVE_TRAFFIC_SECONDS051)
	check(int(counterfeit_result.counters.accepted)==0,"copied offer with changed path must revalidate and cannot borrow a sealed fingerprint")
	check(Planner.resolve(view,memory,[admitted])==public_result,"public resolve ignores private admission and preserves full default checks")
	var denied_certificate: Dictionary=certificate.duplicate(true)
	denied_certificate.status="pending";denied_certificate.pathFingerprint=""
	var denied: Dictionary=T._seal_begin_offer051(admitted_plan.sources[str(refined.candidate.candidateId)],refined.candidate,denied_certificate,"")
	var denied_plan: Dictionary=Planner._prepare_begin(view,memory)
	denied_plan.beginView051=view;denied_plan.beginOffers051={str(refined.candidate.candidateId):denied}
	var denied_result: Dictionary=Planner._resolve_planned(view,memory,[denied],denied_plan,Stations.LIVE_TRAFFIC_SECONDS051)
	check(int(denied_result.counters.accepted)==0 and int(denied_result.counters.pending)==1,"unhashed pending offer remains pending and grants no maneuver or reservation")
	view.options.clearanceRemaining=0
	var pending: Dictionary=Planner._resolve_planned(view,memory,offers,Planner._prepare_begin(view,memory),Stations.LIVE_TRAFFIC_SECONDS051)
	check(int(pending.counters.accepted)==0 and int(pending.counters.clearanceExhausted)>0 and int(pending.counters.clearanceTests)==0,"private resolve cannot accept through exhausted reservation work")
	observations.append({"case":"traffic-prefix-resolve","certificateStatus":certificate.status,"public":public_result.counters,"private":live.counters,"pending":pending.counters})

func _worker_slot051(arena: Dictionary, expiry051: bool=true) -> Dictionary:
	var st: Dictionary=arena.state
	var id: String=str(arena.source.id)
	T.enable_planning051(st);worker_states051.append(st)
	# Obtain a REAL side-batch sample before the ORIGINAL .45s preference expiry.
	# No fabricated task, descriptor, completion flag or physical certificate.
	var batch_times: Dictionary={}
	var spaced: bool=true
	for tick: int in range(60):
		B.update(st,1.0/60.0);B.pop_events(st)
		var slots: Dictionary=st.tactical.workers051.slots
		for cohort: Dictionary in slots.values():
			for member: String in cohort.guards:
				if batch_times.has(member) and int(cohort.generation051)!=int(batch_times[member].generation):spaced=spaced and float(cohort.periodAt051)>=float(batch_times[member].period)+0.15-0.000001
				batch_times[member]={"generation":int(cohort.generation051),"period":float(cohort.periodAt051)}
		var held: Variant=st.tactical.retained051.get(id)
		var slot: Dictionary=Planner._member_slot051(st.tactical,id)
		# The expiry case asserts BOTH original semantic age and useful age from
		# this batch's guard. A newer observation after dispatch cannot make an
		# ineligible old generation satisfy that unchanged same-age contract.
		var expiry_sample051: bool=true
		if expiry051 and not slot.is_empty() and held is C._Retained051:
			expiry_sample051=held.chosen_at+0.45<=minf(float(slot.createdAt)+Planner.WORKER_DEADLINE051,float(slot.guards[id].decisionAt)+Planner.CERT_SECONDS)+0.000001
		if not slot.is_empty() and held is C._Retained051 and float(slot.createdAt)==float(st.time) and float(st.time)-held.chosen_at>=(0.30 if expiry051 else 0.10)-0.000001 and expiry_sample051:
			check(int(slot.taskId)>=0 and float(slot.guards[id].decisionAt)>=0.0 and float(st.time)-held.chosen_at<0.45+0.000001 and spaced,"actor samples debit distinct150ms side periods before original preference expiry")
			check(float(st.tactical.lastDecision[id])==float(slot.guards[id].decisionAt) and float(slot.createdAt)==float(st.time) and is_same(st.tactical.intents.get(id),held.intent),"batch dispatch preserves real observation clocks and grants no new helm authority")
			var complete: bool=true
			var side_periods: Dictionary={}
			for batch: Dictionary in slots.values():
				var key: String=str(batch.side)+":"+str(batch.periodAt051)
				complete=complete and not side_periods.has(key)
				side_periods[key]=true
			for ship: Dictionary in st.tactical.ships.values():
				if str(ship.id)!=str(st.tactical.manualId):complete=complete and st.tactical.workers051.periods051[str(ship.team)].slices.has(str(ship.id))
			check(complete and Planner._tasks051.size()<=2 and int(st.tactical.budget.fullRoutes)<=4 and int(st.tactical.budget.clearanceTests)<=4096,"one batch per side period covers every automated hull while main fair/global caps remain unchanged")
			return {"slot":slot,"held":held}
		OS.delay_usec(500) # Fixture scheduling only, outside public physics.
	check(false,"worker case obtains a real side-batch expiry sample within60 public ticks")
	observations.append({"case":"workers-start-failed","time":st.time,"intent":st.tactical.intents.get(id,{}),"memory":st.tactical.memory.player.byId.get(id,{}),"reason":st.tactical.reasons.get(id,""),"slots":st.tactical.workers051.slots.keys()})
	return {}

func _worker_join051(slot: Dictionary) -> bool:
	# Test-owner scheduling OUTSIDE Battle.update/physics, not a runtime await.
	var until: int=Time.get_ticks_usec()+2000000
	while not bool(slot.joined) and Time.get_ticks_usec()<until:
		T.poll_planning051()
		if not bool(slot.joined):OS.delay_usec(500)
	check(bool(slot.joined) and int(slot.taskId)==-1,"real WorkerThreadPool task completes and is joined before any output inspection")
	return bool(slot.joined)

func duel_policy051() -> void:
	for variant: String in ["duel","player-fleet","enemy-fleet","sunk-extra","captured-extra","manual-extra","manual-enemy-fleet"]:
		var spec: Dictionary=SPEC.duplicate(true);spec.range=300.0
		var source: Dictionary=D.create_ship(spec,{"uid":"policy-source"})
		var target_spec: Dictionary=spec.duplicate(true);target_spec.speed=0.0
		var target: Dictionary=D.create_ship(target_spec,{"uid":"policy-target","ammo":0.0})
		var players: Array=[source]
		var enemies: Array=[target]
		if variant in ["player-fleet","sunk-extra","captured-extra","manual-extra"]:players.append(D.create_ship(spec,{"uid":"policy-ally"}))
		if variant in ["enemy-fleet","manual-enemy-fleet"]:enemies.append(D.create_ship(target_spec,{"uid":"policy-enemy","ammo":0.0}))
		var st: Dictionary=B.create({"fleet":players,"enemyFleet":enemies,"seed":30011,"islands":[]})
		st.autoBoard=false
		if variant=="sunk-extra":players[1].sunk=true
		if variant=="captured-extra":players[1].captureSecured=true
		if variant in ["manual-extra","manual-enemy-fleet"]:B.set_autopilot(st,false)
		T.enable_planning051(st);worker_states051.append(st)
		var pooled: bool=variant in ["player-fleet","enemy-fleet","manual-enemy-fleet"]
		check(st.tactical.has("workers051")==pooled,"encounter policy batches only a side with multiple live automated boats: "+variant)
		if variant=="duel":
			source.x=500.0;source.y=850.0;source.angle=0.0
			target.x=700.0;target.y=850.0;F.command(st,target,"hold")
			var ammo: float=float(source.ammo)
			B.update(st,1.0/60.0)
			var emitted: Array=fire_events(st,source)
			# The existing global cap is one due hull per tick in a duel; the
			# enemy sorts first. Neither slot should wait for a pooled batch.
			var enemy_memory: Dictionary=st.tactical.memory.enemy.byId.get(str(target.id),{})
			var enemy_history: Array=enemy_memory.get("observations",[])
			check(not enemy_history.is_empty() and float(enemy_history[-1].lastAt)==float(st.time),"ordinary duel observes the first fair hull on the first60Hz tick")
			B.update(st,1.0/60.0);emitted.append_array(fire_events(st,source))
			var memory: Dictionary=st.tactical.memory.player.byId.get(str(source.id),{})
			var history: Array=memory.get("observations",[])
			check(not memory.is_empty() and not history.is_empty() and float(history[-1].lastAt)==float(st.time) and int(st.tactical.counters.decisions)>=2,"ordinary duel publishes both full role observations in the first two fair60Hz slots")
			for tick: int in range(60):
				B.update(st,1.0/60.0);emitted.append_array(fire_events(st,source))
			check(not emitted.is_empty() and is_equal_approx(ammo-float(source.ammo),float(emitted.size())),"ordinary synchronous duel emits real certified fire with exact ammunition debit")
			check(B.issue_order(st,[source.id],"move",{"x":450.0,"y":600.0}),"ordinary duel accepts a current manual command")
			B.update(st,1.0/60.0);B.pop_events(st)
			memory=st.tactical.memory.player.byId.get(str(source.id),{});history=memory.get("observations",[])
			check(source.order=="move" and int(memory.get("orderRevision",-1))==int(source.orderRevision) and not history.is_empty() and float(history[-1].lastAt)==float(st.time),"duel command receives fresh synchronous observations on the next60Hz tick")
			B.set_autopilot(st,false)
			B.update(st,1.0/60.0,{"manual":true,"left":true});B.pop_events(st)
			check(str(st.tactical.manualId)==str(source.id) and not st.tactical.intents.has(str(source.id)),"ordinary duel manual helm immediately retains sole control")
			var profile: Dictionary=T.runtime_profile043()
			check(not st.tactical.has("workers051") and int(profile.workerDispatches)==0 and int(profile.workerAdoptions)==0,"actual duel never dispatches or adopts a pooled side batch")
			observations.append({"case":"duel-policy","time":st.time,"events":emitted,"ammoBefore":ammo,"ammoAfter":source.ammo,"memory":memory,"profile":profile})
		T.retire_planning051(st);T.drain_planning051()

func current_begin051() -> void:
	var arena: Dictionary=local_arena()
	var st: Dictionary=arena.state
	B.update(st,1.0/60.0);B.pop_events(st)
	var before: PackedByteArray=var_to_bytes([st.ships,st.tactical.memory,st.tactical.options,st.tactical.observed])
	var current: Dictionary={}
	for side: String in ["player","enemy"]:
		var due: Array=[]
		for ship: Dictionary in st.ships:
			if ship.team==side and not ship.sunk:
				due.append(str(ship.id));break
		var view: Dictionary=T._begin_view051(st,side,due,null,current)
		var detached: Dictionary=T._worker_view051(st,side,due)
		var memory: Dictionary=st.tactical.memory[side]
		var planned: Dictionary=Planner._prepare_begin(view,memory,current.indexes[side])
		var reference: Dictionary=Planner._prepare_begin(detached,memory)
		check(view==detached and planned==reference,"current begin preserves exact detached observations, options, decisions and ordered offers: "+side)
		check(is_same(planned.context,current.indexes[side]) and current.owners.size()<=current.indexes[side].size(),"private planning reuses the exact current index without rebuilding all hulls: "+side)
		var owner: Dictionary=planned.context[due[0]]
		var live: Dictionary=st.tactical.ships[due[0]]
		check(is_same(owner.mounts,st.tactical.mountCache[due[0]].mounts) and is_same(owner.weaponCooldowns,live.weaponCooldowns) and is_same(owner.orderTarget,live.orderTarget) and not is_same(owner.mountShotTimes,live.mountShotTimes),"closed begin borrows current inputs but preserves separately sampled actual shot times: "+side)
		var detached_owner: Dictionary=Roles.ships_by_id(detached)[due[0]]
		check(not is_same(detached_owner.mounts,owner.mounts) and not is_same(detached_owner.weaponCooldowns,live.weaponCooldowns) and not is_same(detached_owner.orderTarget,live.orderTarget),"worker boundary still exclusively owns every nested planning input: "+side)
		check(not live.orderTarget.is_read_only() and not live.weaponCooldowns.is_read_only() and not owner.mounts.is_read_only(),"borrowed begin does not freeze live command, cooldown or mount containers: "+side)
		var public_view: Dictionary=T.view(st,side,due)
		var public_owner: Dictionary=Roles.ships_by_id(public_view)[due[0]]
		var real_range: float=float(owner.mounts[0].range)
		public_owner.mounts[0].range=real_range+9.0
		detached_owner.mounts[0].range=real_range+17.0
		check(float(owner.mounts[0].range)==real_range and not is_same(public_owner.orderTarget,live.orderTarget),"public and worker edits cannot change the current or live view: "+side)
	check(var_to_bytes([st.ships,st.tactical.memory,st.tactical.options,st.tactical.observed])==before,"both current-side planning passes leave all live ships, observations and prior memory byte-identical")
	# No scope crosses a physics tick: real commands and current motion must be
	# projected again, while the previous current bundle remains just old data.
	var id: String=str(arena.source.id)
	var old: Dictionary=current.owners[id]
	var old_revision: int=int(old.orderRevision)
	check(B.issue_order(st,[id],"move",{"x":1100.0,"y":850.0}),"current-begin freshness case accepts a real new command")
	B.update(st,1.0/60.0);B.pop_events(st)
	var next: Dictionary={}
	var next_view: Dictionary=T._begin_view051(st,"player",[id],null,next)
	var next_plan: Dictionary=Planner._prepare_begin(next_view,st.tactical.memory.player,next.indexes.player)
	check(not is_same(next.owners[id],old) and int(old.orderRevision)==old_revision and int(next.owners[id].orderRevision)==int(arena.source.orderRevision) and int(next_plan.decisions[id].state.orderRevision)==int(arena.source.orderRevision),"a fresh begin observes the actual command revision without lending old scope authority")
	observations.append({"case":"current-begin-ownership","sides":current.indexes.size(),"fullOwners":current.owners.size(),"oldRevision":old_revision,"currentRevision":arena.source.orderRevision})

func worker_handoff051() -> void:
	for variant: String in ["late", "deadline", "command", "physical"]:
		var arena: Dictionary=local_arena()
		var st: Dictionary=arena.state
		var source: Dictionary=arena.source
		var id: String=str(source.id)
		var lease: Dictionary=_worker_slot051(arena,false)
		if lease.is_empty():T.retire_planning051(st);T.drain_planning051();continue
		var slot: Dictionary=lease.slot
		if not _worker_join051(slot):T.retire_planning051(st);T.drain_planning051();continue
		# Hold REAL worker output behind a REAL owned completion fence. Poll/join
		# still use WorkerThreadPool; no fabricated output/certificate or timer.
		var release: Semaphore=Semaphore.new()
		slot.joined=false
		slot.taskId=WorkerThreadPool.add_task(release.wait,false,"AI fixture bounded handoff fence")
		Planner._tasks051.append(slot)
		var last: float=float(st.tactical.lastDecision[id])
		var intent: Dictionary=st.tactical.intents.get(id,{})
		var guard_memory: Dictionary=slot.guards[id].memory
		var baseline: Dictionary=guard_memory.duplicate(true)
		var previous: Dictionary=st.tactical.memory.player.byId[id]
		var memory_before: Dictionary=previous.duplicate(true)
		check(not is_same(slot.guards[id].memory,previous) and not is_same(slot.guards[id].memory.get("shotTimes",{}),previous.get("shotTimes",{})),"dispatch semantic baseline independently owns nested main memory: "+variant)
		var current051: Dictionary={}
		var pending: Dictionary=Planner._take_worker051(st,"player",[id],T._worker_capability051,null,T._worker_wait_guard051,current051)
		var repeated: bool=Planner._waiting_worker051(st,id,T._worker_capability051,T._worker_wait_guard051,null,current051)
		check(pending.get("pending051",[])==[id] and repeated and int(current051.workerWaitChecks051)==1 and id in slot.remaining and id not in slot.discarded,"unfinished member remains pending and reuses one exact-begin guard: "+variant)
		var shared: Dictionary=current051.get("retainedObservation051",{}).get(id,{})
		check(not shared.is_empty() and is_same(shared.owner,source) and is_same(shared.own,current051.owners[id]) and is_same(shared.observed,st.tactical.observed[id]) and is_same(shared.previous,previous) and int(shared.revision)==int(st.tactical.snapshotRevision) and float(shared.at)==float(st.time),"real wait guard shares only its exact current owner/observation/memory/begin proof: "+variant)
		check(float(st.tactical.lastDecision[id])==last and is_same(st.tactical.intents.get(id),intent) and st.tactical.memory.player.byId[id]==memory_before,"pending handoff grants no observation or authority: "+variant)
		var deadline: float=Planner._worker_wait_until051(st,id,slot)
		check(is_equal_approx(deadline,minf(float(slot.createdAt)+0.15,last+0.2-1.0/60.0)),"pending deadline is the earlier real sample/observation limit: "+variant)
		if variant=="late":
			for tick: int in range(2):B.update(st,1.0/60.0);B.pop_events(st)
			check(float(st.time)-float(slot.createdAt)>=1.0/30.0-0.000001 and float(st.time)<deadline-0.000001 and id in slot.remaining and id not in slot.discarded and float(st.tactical.lastDecision[id])==last,"real pending result survives the former33ms consumption point")
		elif variant=="deadline":
			for tick: int in range(12):
				if float(st.time)+1.0/60.0>=deadline-0.000001:break
				B.update(st,1.0/60.0);B.pop_events(st)
			check(id in slot.remaining and not bool(slot.joined) and float(st.tactical.lastDecision[id])==last,"unfinished result retains its member immediately before the exact deadline")
			B.update(st,1.0/60.0);B.pop_events(st)
			var history: Array=st.tactical.memory.player.byId.get(id,{}).get("observations",[])
			check(is_equal_approx(float(st.time),deadline) and id in slot.discarded and id not in slot.adopted and not history.is_empty() and float(history[-1].lastAt)==float(st.time) and float(st.time)-last<=0.2+0.000001,"exact deadline consumes unfinished member and publishes real synchronous fallback")
			check(id not in slot.remaining and Planner._member_slot051(st.tactical,id).is_empty() and float(st.tactical.lastDecision.get(id,-1.0))==float(st.time) and not history.is_empty() and float(history[-1].lastHp)==float(source.hp) and is_same(st.tactical.intents.get(id),intent),"deadline consumption preserves the live maneuver while a real current retained observation publishes HP and clock")
		else:
			if variant=="command":check(B.issue_order(st,[id],"move",{"x":450.0,"y":600.0}),"command accepted during unfinished handoff")
			else:source.engine=0.0
			var event_at: float=float(st.time)
			B.update(st,1.0/60.0);B.pop_events(st)
			check(id in slot.discarded and id not in slot.adopted and float(st.time)<deadline-0.000001 and guard_memory==baseline,"current invalidation bypasses waiting before deadline without rewriting dispatch memory: "+variant)
			check(variant!="command" or (str(source.order)=="move" and int(source.orderRevision)>int(lease.held.revision)),"unfinished worker cannot restore a superseded command")
			check(variant!="physical" or (float(source.engine)==0.0 and not is_same(st.tactical.intents.get(id),intent) and float(T.helm(st,source).throttle)==0.0),"current physical invalidation revokes the old maneuver while worker is unfinished")
			observations.append({"case":"workers-handoff-invalidation","variant":variant,"eventAt":event_at,"fallbackAt":st.time,"deadline":deadline})
		# Always release our fence before teardown; no runtime wait or leaked task.
		release.post()
		if _worker_join051(slot) and variant=="late":
			var joined: Dictionary=Planner._take_worker051(st,"player",[id],T._worker_capability051,null,T._worker_wait_guard051,{})
			var view: Dictionary=T.view(st,"player",[id])
			var prepared: Dictionary=Planner._prepare_with_worker051(view,st.tactical.memory.player,joined)
			check(id in slot.adopted and id not in slot.discarded and float(st.time)-last<=0.2+0.000001,"late real worker result adopts before unchanged observation expiry")
			check(id in prepared.workerIds051 and float(st.tactical.lastDecision[id])==last and is_same(st.tactical.intents.get(id),intent),"late preference transfer itself cannot grant a clock or overwrite current authority")
		elif variant=="deadline":
			var fallback_at: float=float(st.tactical.lastDecision.get(id,-1.0))
			var late: Dictionary=Planner._take_worker051(st,"player",[id],T._worker_capability051,null,T._worker_wait_guard051,{})
			check(id not in late.get("allowed",[]) and slot.adopted.is_empty() and slot.discarded.count(id)==1 and float(st.tactical.lastDecision.get(id,-1.0))==fallback_at,"late completion cannot restore a consumed deadline generation or renew its clock")
		observations.append({"case":"workers-handoff","variant":variant,"createdAt":slot.createdAt,"deadline":deadline,"time":st.time,"adopted":slot.adopted.duplicate(),"discarded":slot.discarded.duplicate()})
		T.retire_planning051(st);T.drain_planning051()
		check(bool(slot.joined) and slot.capsule==null and Planner._tasks051.is_empty(),"bounded handoff case joins every owned task: "+variant)

func worker_side_batches051() -> void:
	var spec: Dictionary=SPEC.duplicate(true);spec.range=300.0
	var fleet: Array=[]
	for index: int in range(12):fleet.append(D.create_ship(spec,{"uid":"cohort-"+str(index)}))
	var enemy_spec: Dictionary=spec.duplicate(true);enemy_spec.speed=0.0
	var st: Dictionary=B.create({"fleet":fleet,"enemyFleet":[D.create_ship(enemy_spec,{"uid":"cohort-target","ammo":0.0})],"seed":30011,"islands":[]})
	st.islands=[];st.autoBoard=false
	for index: int in range(12):
		var ship: Dictionary=st.ships[index]
		ship.x=400.0+float(index%3)*180.0;ship.y=300.0+floorf(float(index)/3.0)*250.0
	st.ships[-1].x=1900.0;st.ships[-1].y=850.0
	T.enable_planning051(st);worker_states051.append(st)
	B.update(st,1.0/60.0);B.pop_events(st)
	var initial: Array=st.tactical.workers051.slots.values()
	check(initial.size()==2 and int(st.tactical.metrics.normalLimit)==2,"real13-hull frame dispatches one whole batch per side without changing the cap-two main selection")
	if initial.size()!=2:T.retire_planning051(st);T.drain_planning051();return
	var slow: Dictionary=initial[0] if str(initial[0].side)=="enemy" else initial[1]
	var ready: Dictionary=initial[0] if str(initial[0].side)=="player" else initial[1]
	check(slow.remaining.size()==1 and ready.remaining.size()==12,"only cohort-size policy rolls back: every automated hull belongs to its one deadline-ordered side batch")
	var ordered: bool=true
	for batch: Dictionary in initial:
		for index: int in range(1,batch.remaining.size()):
			ordered=ordered and float(batch.guards[batch.remaining[index-1]].decisionAt)<=float(batch.guards[batch.remaining[index]].decisionAt)
	check(ordered,"whole side batches retain useful-observation deadline order")
	if not _worker_join051(slow) or not _worker_join051(ready):T.retire_planning051(st);T.drain_planning051();return
	var outputs: Array=[slow.capsule.result,ready.capsule.result] # Both REAL results already joined; retain their costs before the fence.
	var release: Semaphore=Semaphore.new()
	slow.joined=false;slow.taskId=WorkerThreadPool.add_task(release.wait,false,"AI fixture independent cohort fence")
	Planner._tasks051.append(slow)
	var clocks: Dictionary=st.tactical.lastDecision.duplicate(true)
	var invalid: String=str(ready.remaining[0])
	var neighbors: Array=ready.remaining.duplicate();neighbors.erase(invalid)
	var neighbor: String=str(neighbors[0])
	check(B.issue_order(st,[invalid],"move",{"x":300.0,"y":1450.0}),"one joined side-batch member receives a real superseding command")
	var offered: Dictionary=Planner._take_worker051(st,str(ready.side),ready.remaining.duplicate(),T._worker_capability051,null,T._worker_wait_guard051,{})
	check(offered.allowed==neighbors and invalid in ready.discarded and neighbors.all(func(id):return id not in ready.discarded) and not bool(slow.joined) and not slow.remaining.is_empty(),"completed side is usable independently; invalidating one member preserves every neighbor and the unfinished side")
	check(Planner._take_worker051(st,str(ready.side),[neighbor],T._worker_capability051,null,T._worker_wait_guard051,{}).get("allowed",[]).is_empty(),"a joined member generation transfers at most once")
	var order: Array=st.tactical.ships.keys()
	for round051: int in range(10):
		Planner._poll_tasks051()
		var refill: Dictionary=Planner._dispatch_batch051(st,order,T._worker_view051,T._worker_capability051,null)
		check(int(refill.dispatches)==0 and Planner._tasks051.size()<=2,"joining/consuming a side never eagerly refills its period or exceeds the global unfinished task cap")
		var complete: bool=true
		for period: Dictionary in st.tactical.workers051.periods051.values():
			complete=complete and period.sent.size()==period.slices.size()
		for slot: Dictionary in st.tactical.workers051.slots.values():
			if is_same(slot,slow):continue
			if _worker_join051(slot):
				outputs.append(slot.capsule.result)
				Planner._take_worker051(st,str(slot.side),slot.remaining.duplicate(),T._worker_capability051,null,T._worker_wait_guard051,{})
		if complete:break
	var issued: int=0
	var totals: Dictionary={}
	for output: Dictionary in outputs:
		var side: String=str(output.planning.context[str(output.budgets.keys()[0])].team)
		if not totals.has(side):totals[side]={"clearance":0,"proof":0,"routes":0}
		totals[side].proof+=int(output.proofBudget051.clearanceTests)
		for id: String in output.budgets:
			var budget: Dictionary=output.budgets[id]
			totals[side].clearance+=int(budget.clearanceTests)
			totals[side].routes+=int(budget.fullRoutes)-4+int(budget.routeAllowance051)
			check(int(budget.clearanceTests)<=int(budget.clearanceLimit) and output.requests.get(id,[]).size()<=8,"every side-batch member preserves all bounded candidate generation and its owned slice")
	for period: Dictionary in st.tactical.workers051.periods051.values():
		issued+=period.sent.size()
		check(int(period.clearanceAllocated)==2900 and int(period.proofAllocated)==128 and int(period.routesAllocated)==4 and period.sent.size()==period.slices.size() and bool(period.dispatched051),"each side batch allocates original2900traffic PLUS128proof/four-route allowances once per150ms period")
	for spent: Dictionary in totals.values():check(int(spent.clearance)<=2900 and int(spent.proof)<=128 and int(spent.routes)<=4,"actual completed side-batch traffic/proof work stays inside separate aggregate side bounds")
	check(issued==13 and float(st.time)==1.0/60.0 and st.tactical.lastDecision.get(neighbor)==clocks.get(neighbor),"dispatch/join covers every actor without advancing simulation or useful-observation clocks")
	var old_generation: int=int(slow.generation051)
	var slow_ids: Array=slow.remaining.duplicate()
	Planner._release_slot051(st.tactical,slow)
	check(bool(slow.retired) and Planner._tasks051.has(slow) and not bool(slow.joined),"retired unfinished side batch retains its global task seat until real completion")
	var retired_dispatch: Dictionary=Planner._dispatch_batch051(st,order,T._worker_view051,T._worker_capability051,null)
	check(int(retired_dispatch.dispatches)==0 and Planner._tasks051.size()==1,"retiring a side batch cannot refill already spent side-period actor slices")
	var before_boundary: Dictionary=st.tactical.lastDecision.duplicate(true)
	var period_at: float=float(st.tactical.workers051.periods051.player.at)
	st.time=period_at+0.15-0.000002
	check(int(Planner._dispatch_batch051(st,order,T._worker_view051,T._worker_capability051,null).dispatches)==0,"side cadence remains closed immediately before its existing150ms boundary")
	st.time=period_at+0.15
	var next_period: Dictionary=Planner._dispatch_batch051(st,order,T._worker_view051,T._worker_capability051,null)
	check(int(next_period.dispatches)==1 and Planner._tasks051.size()==2 and Planner._tasks051.has(slow) and bool(slow.retired),"next side period can use only the free task seat while retired unfinished work still owns the other")
	check(int(Planner._dispatch_batch051(st,order,T._worker_view051,T._worker_capability051,null).dispatches)==0 and st.tactical.lastDecision==before_boundary,"two tasks including retired work prevent another dispatch and all cadence checks grant no observation clocks")
	release.post();_worker_join051(slow)
	check(slow.capsule==null and not st.tactical.workers051.slots.has(old_generation) and slow_ids.all(func(id):return Planner._member_slot051(st.tactical,str(id)).is_empty()),"late retired completion cannot restore any consumed generation")
	T.retire_planning051(st);T.drain_planning051()
	check(Planner._tasks051.is_empty(),"independent side-batch case joins every owned task")

func worker_revoked_ready051() -> void:
	for variant: String in ["stable","phase"]:
		var arena: Dictionary=local_arena()
		var st: Dictionary=arena.state
		var source: Dictionary=arena.source
		var id: String=str(source.id)
		var lease: Dictionary=_worker_slot051(arena,false)
		if lease.is_empty():T.retire_planning051(st);T.drain_planning051();continue
		var slot: Dictionary=lease.slot
		if not _worker_join051(slot):T.retire_planning051(st);T.drain_planning051();continue
		var preference: Variant=_physical_preference_drop051(arena,lease.held,"ready-worker-"+variant)
		if not preference is C._Preference051:T.retire_planning051(st);T.drain_planning051();continue
		var before: PackedByteArray=var_to_bytes([st.ships,st.tactical.memory,st.tactical.lastDecision,st.rng.state])
		check(Planner._ready_worker051(st,id) and var_to_bytes([st.ships,st.tactical.memory,st.tactical.lastDecision,st.rng.state])==before and not st.tactical.intents.has(id),"joined routing eligibility grants no memory, clock, physical authority or RNG work: "+variant)
		if variant=="phase":
			arena.target.x=float(source.x)+40.0;arena.target.y=source.y
		for tick: int in range(8):
			B.update(st,1.0/60.0);B.pop_events(st)
			if id in slot.adopted or id in slot.discarded:break
		var fresh: Dictionary=st.tactical.memory.player.byId.get(id,{})
		var history: Array=fresh.get("observations",[])
		var observed_at: float=float(history[-1].get("lastAt",-1.0)) if not history.is_empty() else -1.0
		# B.update also runs live helm/fire checks after the handoff. They may
		# revoke authority and reset lastDecision; current memory proves publication.
		if variant=="stable":
			check(id in slot.adopted and id not in slot.discarded,"ready stable suggestion survives physical-only revocation and is consumed by main planning")
			check(observed_at==float(st.time),"ready handoff publishes current decision observations without promising physical authority")
		else:
			check(id in slot.discarded and id not in slot.adopted and str(fresh.get("phase",""))=="breakaway" and observed_at==float(st.time),"changed current hostile phase rejects ready offers and publishes current escape observations while allowing a later physical veto")
		var held: Variant=st.tactical.retained051.get(id)
		var certificate: Dictionary=held.record.certificate if held is C._Retained051 else {}
		observations.append({"case":"workers-revoked-ready","variant":variant,"createdAt":slot.createdAt,"time":st.time,"adopted":slot.adopted.duplicate(),"discarded":slot.discarded.duplicate(),
			"memoryAt":observed_at,"phase":fresh.get("phase",""),"lastDecision":st.tactical.lastDecision.get(id,-1.0),"reason":st.tactical.reasons.get(id,""),
			"heldChosenAt":held.chosen_at if held is C._Retained051 else -1.0,"certCheckedAt":certificate.get("checkedAt",-1.0),"certRevision":certificate.get("snapshotRevision",-1)})
		T.retire_planning051(st);T.drain_planning051()
		check(not Planner._ready_worker051(st,id) and Planner._tasks051.is_empty(),"retirement removes joined routing eligibility and drains every owned task: "+variant)

func worker_prepared051() -> void:
	var arena: Dictionary=local_arena()
	var st: Dictionary=arena.state
	B.update(st,1.0/60.0);B.pop_events(st)
	var id: String=str(arena.source.id)
	var view: Dictionary=T.view(st,"player",[id])
	var context: Dictionary=Roles.ships_by_id(view)
	var memory: Dictionary=st.tactical.memory.player
	var base: Dictionary=Planner._prepare_begin(view,memory,context)
	# Pure detached dispatch inputs: the old choice is valid now at0.40s,
	# but cannot cover this answer's unchanged150ms handoff window.
	var sample: Dictionary=view.duplicate();sample.time=0.40
	var borrowed: Dictionary=base.duplicate();borrowed.originalPreferenceChosenAt051={id:0.0}
	check(Planner._worker_seed051(sample,context,borrowed,id).is_empty(),"worker recomputes a borrowed role whose original expiry falls inside its handoff window")
	sample.time=0.20
	var seed: Dictionary=Planner._worker_seed051(sample,context,borrowed,id)
	check(not seed.is_empty() and is_same(seed.owner,context[id]) and float(seed.originalPreferenceChosenAt)==0.0 and float(seed.at)==0.20,"worker seed preserves an eligible original semantic clock and the actual detached owner")
	# Membership is scheduling only: a detached fixture never enters Battle or
	# constructs physical authority. Keep bootstrap/all old handoff cases intact.
	var held: C._Retained051=C._Retained051.new()
	held.owner=st.tactical.ships[id];held.intent={};held.chosen_at=0.0
	var schedule: Dictionary={"time":0.20,"tactical":{"ships":{id:held.owner},"intents":{id:held.intent},"retained051":{id:held},"pending":{},"lastDecision":{id:0.20}}}
	check(not Planner._worker_needed051(schedule,id,false) and Planner._worker_needed051(schedule,id,true),"stable later-expiry hull skips speculative work while bootstrap retains every owner")
	schedule.time=0.30
	check(Planner._worker_needed051(schedule,id,false) and held.chosen_at==0.0,"original semantic expiry inside150ms includes the owner without renewing its clock")
	schedule.time=0.20;schedule.tactical.pending[id]=0.20
	check(Planner._worker_needed051(schedule,id,false),"pending physical work remains in the next side cohort despite a later semantic deadline")
	schedule.tactical.pending.clear();schedule.tactical.intents.erase(id)
	check(Planner._worker_needed051(schedule,id,false),"lost retained authority remains eligible for worker preparation")
	var fresh: Dictionary=base.decisions[id].duplicate(true)
	var record: Dictionary={"owner":context[id],"revision":int(view.snapshotRevision),"at":float(view.time),"decision":fresh,"originalPreferenceChosenAt":0.0}
	var records: Dictionary={id:record}
	var before: Dictionary=memory.duplicate(true)
	# The first global fair slot may observe an enemy instead of this hull.
	var clock_present: bool=st.tactical.lastDecision.has(id)
	var clock: float=float(st.tactical.lastDecision.get(id,-1.0))
	var prepared: Dictionary=Planner._prepare_with_worker051(view,memory,{},context,records)
	check(records.is_empty() and is_same(prepared.decisions[id],fresh) and float(prepared.originalPreferenceChosenAt051[id])==0.0 and prepared.candidates.size()==base.candidates.size(),"same-begin semantic decision is consumed once with its original choice time and all candidates regenerated")
	check(memory==before and st.tactical.lastDecision.has(id)==clock_present and float(st.tactical.lastDecision.get(id,-1.0))==clock,"consuming a prepared decision alone publishes no memory or useful-observation clock")
	for changed: String in ["owner","revision","at"]:
		var stale: Dictionary=record.duplicate()
		if changed=="owner":stale.owner=context[id].duplicate(true)
		elif changed=="revision":stale.revision=int(view.snapshotRevision)-1
		else:stale.at=float(view.time)-1.0/60.0
		var rejected: Dictionary={id:stale}
		var fallback: Dictionary=Planner._prepare_begin(view,memory,context,rejected)
		check(rejected.has(id) and not is_same(fallback.decisions[id],fresh) and fallback.originalPreferenceChosenAt051.is_empty(),"prepared decision cannot cross its exact begin guard: "+changed)

func workers051() -> void:
	var profiling: bool=bool(T.runtime_profile043().enabled)
	T.set_runtime_profile043(true);T.reset_runtime_profile043()
	current_begin051()
	duel_policy051()
	worker_side_batches051()
	worker_prepared051()
	worker_revoked_ready051()
	worker_handoff051()
	var arena: Dictionary=local_arena()
	var st: Dictionary=arena.state
	var source: Dictionary=arena.source
	var id: String=str(source.id)
	var lease: Dictionary=_worker_slot051(arena)
	if not lease.is_empty() and _worker_join051(lease.slot):
		var slot: Dictionary=lease.slot
		var output: Dictionary=slot.capsule.result
		var worker_view: Dictionary=output.planning.context[id]
		check(output.planning.dueIds.all(func(member):return output.planning.originalPreferenceChosenAt051.has(member) and float(output.planning.originalPreferenceChosenAt051[member])<=float(slot.createdAt) and float(slot.createdAt)+Planner.WORKER_DEADLINE051<=float(output.planning.originalPreferenceChosenAt051[member])+0.45+0.000001),"real worker decisions retain original/sample semantic ages through the entire bounded handoff")
		var observed_at: float=float(slot.guards[id].decisionAt)
		check(not is_same(worker_view,st.tactical.ships[id]) and not is_same(worker_view.mounts,st.tactical.observed[id].mounts) and not is_same(worker_view.mountShotTimes,source.mountShotTimes) and not is_same(worker_view.orderTarget,source.orderTarget),"single-build worker view exclusively owns its nested inputs")
		var origin: Vector2=F.pos(source)
		var before: Dictionary={}
		for tick: int in range(12):
			before=C.pose(source)
			B.update(st,1.0/60.0);B.pop_events(st)
			if id in slot.adopted:break
		check(id in slot.adopted and float(st.time)-lease.held.chosen_at>=0.45-0.000001 and float(st.time)-observed_at<=0.2+0.000001,"cohort preference ADOPTS at original0.45s expiry within the unchanged useful-observation bound")
		check(not is_same(st.tactical.retained051.get(id),lease.held) and F.pos(source).distance_to(origin)>0.0,"adopted suggestion publishes a new real maneuver and moves the actual boat")
		var intent: Dictionary=st.tactical.intents.get(id,{})
		var record: Dictionary=st.tactical.predictions.get(str(intent.get("pathFingerprint","")),{})
		check(not record.is_empty() and record.certificate.checkedPose==before and record.certificate.checkedAt==float(st.time) and record.certificate.snapshotRevision==int(st.tactical.snapshotRevision),"main creates a fresh pose/clock/revision certificate, never the worker's old observation")
		check(F.pos(worker_view).distance_to(F.pos(source))>0.0 and not output.has("certificate") and output.planning.candidates.size()<=8,"worker output is detached, bounded station/path preference data only")
		var clearance_limit: int=0
		var route_limit: int=0
		var routes_used: int=0
		for budget: Dictionary in output.budgets.values():
			clearance_limit+=int(budget.clearanceLimit)
			route_limit+=int(budget.routeAllowance051)
			routes_used+=int(budget.fullRoutes)-4+int(budget.routeAllowance051)
			check(int(budget.clearanceTests)<=int(budget.clearanceLimit) and int(budget.fullRoutes)<=4,"pure worker stayed inside its preassigned work slice")
		check(clearance_limit<=2900 and int(output.proofBudget051.clearanceTests)<=128 and route_limit<=4 and routes_used<=4,"cohort pure work retains separate bounded2900traffic/128proof/four-route side allowances")
		var sampled_history: Array=output.planning.decisions[id].state.observations
		var joined_history: Array=st.tactical.memory.player.byId[id].observations
		check(float(sampled_history[-1].lastAt)==float(slot.createdAt) and float(joined_history[-1].lastAt)==float(st.time) and float(joined_history[-1].lastHp)==float(source.hp),"normal join preserves worker sample times and appends actual current HP without a role redecision")
		var now_view: Dictionary=T.view(st,"player",[id])
		var now_owner: Dictionary=Roles.ships_by_id(now_view)[id]
		var checked_membership: Dictionary=C._begin_inputs(now_view,now_owner,[str(arena.target.id),"absent",id,str(arena.target.id)],true)
		check(checked_membership.detailed==[str(arena.target.id)] and C._begin_inputs(now_view,now_owner,[],true).detailed.is_empty(),"private prepared membership checks current live hostile IDs, deduplicates and preserves an empty selection")
		observations.append({"case":"workers-retained-expiry","createdAt":slot.createdAt,"chosenAt":lease.held.chosen_at,"adoptedAt":st.time,"adopted":slot.adopted.duplicate(),"discarded":slot.discarded.duplicate(),"workerPose":C.pose(worker_view),"mainCheckedPose":record.get("certificate",{}).get("checkedPose",{}),"budgets":output.budgets,
			"generation":slot.generation051,"guardDecisionAt":observed_at,"workerChosenAt":output.planning.originalPreferenceChosenAt051.get(id,-1.0),"lastDecision":st.tactical.lastDecision.get(id,-1.0),"memoryAt":joined_history[-1].lastAt,"certCheckedAt":record.get("certificate",{}).get("checkedAt",-1.0),"certRevision":record.get("certificate",{}).get("snapshotRevision",-1),"reason":st.tactical.reasons.get(id,"")})
	T.retire_planning051(st);T.drain_planning051()
	# A REAL batch contains only nonfiring distant stations. Moving the hostile
	# inside gun range must not seal that old fire hold into a new retained plan.
	arena=local_arena();st=arena.state;source=arena.source;id=str(source.id)
	lease=_worker_slot051(arena)
	if not lease.is_empty() and _worker_join051(lease.slot):
		var slot: Dictionary=lease.slot
		var requests: Array=slot.capsule.result.requests.get(id,[])
		check(not requests.is_empty() and requests.all(func(candidate):return candidate.fireMountIds.is_empty()),"range fixture starts with actual nonfiring worker requests")
		var event_at: float=float(st.time)
		var observed_at: float=-1.0
		var recovery_at: float=-1.0
		var reengaged: bool=false
		var requested_fire: bool=false
		var emitted: Array=[]
		var ammo: float=float(source.ammo)
		var pass_sequence: int=int(st.tactical.memory.player.byId[id].get("passSequence",0))
		arena.target.x=float(source.x)+200.0;arena.target.y=float(source.y)
		for tick: int in range(600): # Bounded real10s, unchanged60Hz physics/fire.
			B.update(st,1.0/60.0)
			var shots: Array=fire_events(st,source)
			emitted.append_array(shots)
			var memory: Dictionary=st.tactical.memory.player.byId.get(id,{})
			var history: Array=memory.get("observations",[])
			if observed_at<0.0 and not history.is_empty() and float(history[-1].lastAt)>event_at:observed_at=float(history[-1].lastAt)
			var intent: Dictionary=st.tactical.intents.get(id,{})
			var record: Dictionary=st.tactical.predictions.get(str(intent.get("pathFingerprint","")),{})
			requested_fire=requested_fire or not record.get("candidate",{}).get("fireMountIds",[]).is_empty()
			if recovery_at<0.0 and str(memory.get("phase","")) in ["breakaway","turn-away","regroup"]:recovery_at=float(st.time)
			if recovery_at>=0.0 and int(memory.get("passSequence",0))>pass_sequence and not shots.is_empty():reengaged=true
			if id in slot.discarded and reengaged:break
			OS.delay_usec(100) # Fixture scheduling only; never a runtime wait.
		check(id in slot.discarded and id not in slot.adopted and observed_at>event_at and observed_at-event_at<=0.2+0.000001,"range crossing discards the obsolete fire request and observes current range within0.2s")
		check(requested_fire and not emitted.is_empty() and is_equal_approx(ammo-float(source.ammo),float(emitted.size())),"worker range fallback obtains actual certified gun requests and exactly paid emitted fire")
		check(recovery_at>=0.0 and reengaged,"real worker-driven gun pass recovers and emits again on a new finite pass")
		observations.append({"case":"workers-range-fire","createdAt":slot.createdAt,"eventAt":event_at,"observedAt":observed_at,"time":st.time,"recoveryAt":recovery_at,"reengaged":reengaged,"events":emitted,"ammoBefore":ammo,"ammoAfter":source.ammo,"memory":st.tactical.memory.player.byId.get(id,{}),"adopted":slot.adopted.duplicate(),"discarded":slot.discarded.duplicate()})
	T.retire_planning051(st);T.drain_planning051()
	# A real joined land route on the right remains geometrically valid there.
	# Move its owner across the SAME wall: only a fresh main connector can reject
	# adoption from that new pose. No terrain/revision invalidation can do it.
	arena=local_arena();st=arena.state;source=arena.source;id=str(source.id)
	st.islands=[F.rectangle(200.0,20.0,250.0,1680.0)]
	lease=_worker_slot051(arena)
	if not lease.is_empty() and _worker_join051(lease.slot):
		var slot: Dictionary=lease.slot
		var observed_at: float=float(slot.guards[id].decisionAt)
		var worker_chosen_at: float=float(slot.capsule.result.planning.originalPreferenceChosenAt051.get(id,-1.0))
		source.x=100.0;source.y=850.0
		for tick: int in range(12):
			B.update(st,1.0/60.0);B.pop_events(st)
			if id in slot.adopted:break
		check(id in slot.adopted and not st.tactical.intents.has(id),"real worker suggestion grants no authority across a blocked fresh land connector")
		check(float(T.helm(st,source).throttle)==0.0,"fresh connector rejection brakes the actual hull")
		observations.append({"case":"workers-blocked-connector","generation":slot.generation051,"createdAt":slot.createdAt,"chosenAt":lease.held.chosen_at,"guardDecisionAt":observed_at,"workerChosenAt":worker_chosen_at,"time":st.time,"lastDecision":st.tactical.lastDecision.get(id,-1.0),"adopted":slot.adopted.duplicate(),"discarded":slot.discarded.duplicate(),"hasIntent":st.tactical.intents.has(id),"reason":st.tactical.reasons.get(id,"")})
	T.retire_planning051(st);T.drain_planning051()
	# The worker chose an ordinary approach. A newly close hostile requires a
	# CURRENT escape decision even though command/capability/terrain still match.
	arena=local_arena();st=arena.state;source=arena.source;id=str(source.id)
	lease=_worker_slot051(arena)
	if not lease.is_empty() and _worker_join051(lease.slot):
		var slot: Dictionary=lease.slot
		var old_phase: String=str(slot.capsule.result.planning.decisions[id].state.phase)
		var event_at: float=float(st.time)
		var event_revision: int=int(st.tactical.snapshotRevision)
		var decisions_before: int=int(st.tactical.counters.decisions)
		arena.target.x=float(source.x)+45.0;arena.target.y=float(source.y)
		for tick: int in range(12):
			B.update(st,1.0/60.0);B.pop_events(st)
			if id in slot.discarded:break
		var fresh: Dictionary=st.tactical.memory.player.byId.get(id,{})
		var history: Array=fresh.get("observations",[])
		check(old_phase=="approach" and id in slot.discarded and id not in slot.adopted and str(fresh.get("phase",""))=="breakaway","changed live phase rejects worker offers and rebuilds from the fresh main escape decision")
		var last_decision: float=float(st.tactical.lastDecision.get(id,-1.0))
		var safe_clock: bool=last_decision==float(st.time) or (last_decision<0.0 and not st.tactical.intents.has(id))
		# A current observation can be followed by a same-step physical veto.
		# That veto must retain its right to revoke the helm/decision timestamp.
		check(safe_clock and not history.is_empty() and float(history[-1].lastAt)==float(st.time) and int(st.tactical.snapshotRevision)>event_revision and int(st.tactical.counters.decisions)>decisions_before and float(st.time)-event_at<=0.2+0.000001,"phase fallback publishes current observations within0.2s while preserving a later physical veto")
		observations.append({"case":"workers-fresh-phase","eventAt":event_at,"time":st.time,"workerPhase":old_phase,"mainPhase":fresh.get("phase",""),"lastDecision":last_decision,"memoryAt":history[-1].get("lastAt",-1.0) if not history.is_empty() else -1.0,"hasIntent":st.tactical.intents.has(id),"decisionsBefore":decisions_before,"decisionsAfter":st.tactical.counters.decisions,"adopted":slot.adopted.duplicate(),"discarded":slot.discarded.duplicate()})
	T.retire_planning051(st);T.drain_planning051()
	for action: String in ["command","options","terrain","capability","manual","abandon"]:
		arena=local_arena();st=arena.state;source=arena.source;id=str(source.id)
		lease=_worker_slot051(arena)
		if lease.is_empty():T.retire_planning051(st);T.drain_planning051();continue
		var slot: Dictionary=lease.slot
		if action!="abandon" and not _worker_join051(slot):T.retire_planning051(st);T.drain_planning051();continue
		var event_at: float=float(st.time)
		var event_revision: int=int(st.tactical.snapshotRevision)
		var fresh: Dictionary={}
		var age_samples: Array=[]
		match action:
			"command":check(B.issue_order(st,[id],"move",{"x":450.0,"y":600.0}),"new command accepted while a real suggestion is in flight")
			"options":check(B.set_tactical_options(st,[id],{"doctrine":"cautious"}),"new options accepted while a real suggestion is in flight")
			"terrain":st.islands=[F.rectangle(850.0,100.0,900.0,200.0)]
			"capability":source.engine=0.0
			"manual":B.set_autopilot(st,false)
			"abandon":T.retire_planning051(st)
		if action!="abandon":
			for tick: int in range(15):
				B.update(st,1.0/60.0,{"manual":action=="manual"});B.pop_events(st)
				age_samples.append({"time":st.time,"decisionAges":st.tactical.metrics.decisionAges.duplicate(),"lastDecision":st.tactical.lastDecision.get(id,-1.0),"orderTime":st.tactical.orderTimes.get(id,0.0)})
				if action!="manual" and fresh.is_empty():
					var memory: Dictionary=st.tactical.memory.player.byId.get(id,{})
					var history: Array=memory.get("observations",[])
					var observed_at: float=float(history[-1].get("lastAt",-1.0)) if not history.is_empty() else -1.0
					if float(st.tactical.lastDecision.get(id,-1.0))==float(st.time) and observed_at==float(st.time):
						fresh={"time":st.time,"snapshotRevision":st.tactical.snapshotRevision,"lastDecision":st.tactical.lastDecision[id],"memoryAt":observed_at,"orderRevision":memory.get("orderRevision",-1)}
				if id in slot.discarded and (action=="manual" or not fresh.is_empty()):break
		check(id in slot.discarded and id not in slot.adopted,"real pending suggestion is discarded for "+action)
		if action=="command":check(source.order=="move" and int(source.orderRevision)>int(lease.held.revision),"worker never restores the superseded command")
		if action=="manual":check(st.tactical.manualId==id and not st.tactical.intents.has(id),"manual helm never receives worker authority")
		# decisionAges is this tick's fleet data, not event-response latency:
		# invalidation's -1 can make it measure from the original orderTime.
		# Require this hull's actual main publication after the CURRENT event.
		if action not in ["abandon","manual"]:
			check(not fresh.is_empty() and float(fresh.time)>event_at and float(fresh.time)-event_at<=0.2+0.000001 and int(fresh.snapshotRevision)>event_revision and float(fresh.lastDecision)==float(fresh.time) and float(fresh.memoryAt)==float(fresh.time) and int(fresh.orderRevision)==int(source.orderRevision),"worker rejection publishes current main observations within0.2s: "+action)
		T.retire_planning051(st);T.drain_planning051()
		check(bool(slot.joined) and int(slot.taskId)==-1 and slot.capsule==null and Planner._tasks051.is_empty() and not st.tactical.has("workers051"),"standalone/abandoned encounter joins every owned task: "+action)
		observations.append({"case":"workers-discard","variant":action,"createdAt":slot.createdAt,"eventAt":event_at,"eventSnapshotRevision":event_revision,"time":st.time,"freshObservation":fresh,"decisionAgeSamples":age_samples,"adopted":slot.adopted.duplicate(),"discarded":slot.discarded.duplicate(),"joined":slot.joined})
	var profile: Dictionary=T.runtime_profile043()
	check(int(profile.workerDispatches)>0 and int(profile.workerAdoptions)>0 and int(profile.workerDrops)>0 and int(profile.workerSyncFallbacks)>0,"existing Runtime profile observes real dispatch/adoption/drop/synchronous fallback")
	observations.append({"case":"workers-counters","profile":profile})
	T.set_runtime_profile043(profiling)

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":quit(2);return
	var selected: String="all"
	var path: String=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):selected=arg.substr(7)
		if arg.begins_with("--out="):path=arg.substr(6)
	match selected:
		"all":
			ray_cases();boarding_continuity();focused_boarding();explicit_boarding_authority();held_gun();useful_pressure();capabilities_and_observations();fleet_cadence();local_approach();retained_maneuver051();traffic_prefix051();workers051();fire_readiness051()
		"rays":ray_cases()
		"boarding":boarding_continuity()
		"focused-boarding":focused_boarding()
		"board-authority":explicit_boarding_authority()
		"held-gun":held_gun()
		"fire-readiness":fire_readiness051()
		"useful-pressure":useful_pressure()
		"capabilities":capabilities_and_observations()
		"fleet-cadence":fleet_cadence()
		"local-approach":local_approach()
		"retained":retained_maneuver051()
		"traffic-prefix":traffic_prefix051()
		"workers":workers051()
		_:quit(2);return
	for st: Dictionary in worker_states051:T.retire_planning051(st)
	T.drain_planning051()
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(F.encode({"checks":checks,"failures":failures,"observations":observations})));file.close()
	print("Tactical AI %s: %d checks, %d failures"%[selected,checks,failures])
	quit(0 if failures==0 else 1)
