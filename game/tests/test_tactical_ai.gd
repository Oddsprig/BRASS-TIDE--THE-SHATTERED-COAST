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

func retained_maneuver051() -> void:
	for dt: float in [1.0/30.0,1.0/60.0]:
		var arena: Dictionary=local_arena()
		var st: Dictionary=arena.state
		var source: Dictionary=arena.source
		var id: String=str(source.id)
		var held=_admit_retained051(st,source,dt,"lease")
		check(held is C._Retained051,"real accepted engage maneuver admits one typed descriptor dt="+str(dt))
		if not held is C._Retained051:continue
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
	peer.x=480.0;peer.y=700.0;peer_request.approach=[Vector2(480,700),Vector2(480,1100)]
	st.tactical.memory.player.reservations[str(peer.id)]=Stations._reservation_begin051(peer_request,peer,10.0,seconds)
	st.tactical.budget=traffic_budget051()
	check(T._reserved_path(st,"player",owner,request)=="blocked","within-prefix crossing still blocks the Runtime early gate")
	var no_origin: Dictionary=request.duplicate(true);no_origin.approach=[Vector2(1100,800)]
	st.tactical.budget=traffic_budget051()
	check(T._reserved_path(st,"player",owner,no_origin)=="blocked","first current-position-to-waypoint edge is included without enlarging leg caps")
	st.tactical.budget=traffic_budget051(0)
	check(T._reserved_path(st,"player",owner,request)=="pending" and st.tactical.budget.clearanceTests==0 and st.tactical.budget.exhaustions==1,"prefix reservation exhaustion remains pending and respects the unchanged ledger")
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
	view.options.clearanceRemaining=0
	var pending: Dictionary=Planner._resolve_planned(view,memory,offers,Planner._prepare_begin(view,memory),Stations.LIVE_TRAFFIC_SECONDS051)
	check(int(pending.counters.accepted)==0 and int(pending.counters.clearanceExhausted)>0 and int(pending.counters.clearanceTests)==0,"private resolve cannot accept through exhausted reservation work")
	observations.append({"case":"traffic-prefix-resolve","certificateStatus":certificate.status,"public":public_result.counters,"private":live.counters,"pending":pending.counters})

func _worker_slot051(arena: Dictionary) -> Dictionary:
	var st: Dictionary=arena.state
	var id: String=str(arena.source.id)
	T.enable_planning051(st);worker_states051.append(st)
	# Obtain a REAL retained maneuver and its actual due job. No fabricated
	# task, retained descriptor, completion flag or physical certificate.
	for tick: int in range(60):
		var held: Variant=st.tactical.retained051.get(id)
		B.update(st,1.0/60.0);B.pop_events(st)
		var slots: Dictionary=st.tactical.workers051.slots
		if slots.has("player") and id in slots.player.remaining and held is C._Retained051:
			var slot: Dictionary=slots.player
			check(int(slot.taskId)>=0 and float(slot.guards[id].decisionAt)>=0.0 and float(st.time)-held.chosen_at>=0.30-0.000001,"worker case really dispatches only when its retained preference is due")
			check(not st.tactical.retained051.has(id) and float(st.tactical.lastDecision[id])==float(slot.guards[id].decisionAt) and float(slot.createdAt)==float(st.time) and Planner._waiting_worker051(st,id),"due dispatch preserves the last real observation and waits without publishing worker authority")
			check(Planner._tasks051.size()<=2 and int(st.tactical.budget.fullRoutes)<=4 and int(st.tactical.budget.clearanceTests)<=4096,"real dispatch reserves within the existing global work/task caps")
			return {"slot":slot,"held":held}
	check(false,"worker case obtains a real retained due job within60 public ticks")
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

func workers051() -> void:
	var profiling: bool=bool(T.runtime_profile043().enabled)
	T.set_runtime_profile043(true);T.reset_runtime_profile043()
	var arena: Dictionary=local_arena()
	var st: Dictionary=arena.state
	var source: Dictionary=arena.source
	var id: String=str(source.id)
	var lease: Dictionary=_worker_slot051(arena)
	if not lease.is_empty() and _worker_join051(lease.slot):
		var slot: Dictionary=lease.slot
		var output: Dictionary=slot.capsule.result
		var worker_view: Dictionary=output.planning.context[id]
		var observed_at: float=float(slot.guards[id].decisionAt)
		check(not is_same(worker_view,st.tactical.ships[id]) and not is_same(worker_view.mounts,st.tactical.observed[id].mounts) and not is_same(worker_view.mountShotTimes,source.mountShotTimes) and not is_same(worker_view.orderTarget,source.orderTarget),"single-build worker view exclusively owns its nested inputs")
		var origin: Vector2=F.pos(source)
		var before: Dictionary={}
		for tick: int in range(12):
			before=C.pose(source)
			B.update(st,1.0/60.0);B.pop_events(st)
			if id in slot.adopted:break
		check(id in slot.adopted and float(st.time)-lease.held.chosen_at>=0.30-0.000001 and float(st.time)-observed_at<=0.2+0.000001,"actual due job ADOPTS after normal0.30s expiry within the unchanged useful-observation bound")
		check(not is_same(st.tactical.retained051.get(id),lease.held) and F.pos(source).distance_to(origin)>0.0,"adopted suggestion publishes a new real maneuver and moves the actual boat")
		var intent: Dictionary=st.tactical.intents.get(id,{})
		var record: Dictionary=st.tactical.predictions.get(str(intent.get("pathFingerprint","")),{})
		check(not record.is_empty() and record.certificate.checkedPose==before and record.certificate.checkedAt==float(st.time) and record.certificate.snapshotRevision==int(st.tactical.snapshotRevision),"main creates a fresh pose/clock/revision certificate, never the worker's old observation")
		check(F.pos(worker_view).distance_to(F.pos(source))>0.0 and not output.has("certificate") and output.planning.candidates.size()<=8,"worker output is detached, bounded station/path preference data only")
		for budget: Dictionary in output.budgets.values():check(int(budget.clearanceTests)<=int(budget.clearanceLimit) and int(budget.fullRoutes)<=4,"pure worker stayed inside its preassigned work slice")
		observations.append({"case":"workers-retained-expiry","createdAt":slot.createdAt,"chosenAt":lease.held.chosen_at,"adoptedAt":st.time,"adopted":slot.adopted.duplicate(),"discarded":slot.discarded.duplicate(),"workerPose":C.pose(worker_view),"mainCheckedPose":record.get("certificate",{}).get("checkedPose",{}),"budgets":output.budgets})
	T.retire_planning051(st);T.drain_planning051()
	# A real joined land route on the right remains geometrically valid there.
	# Move its owner across the SAME wall: only a fresh main connector can reject
	# adoption from that new pose. No terrain/revision invalidation can do it.
	arena=local_arena();st=arena.state;source=arena.source;id=str(source.id)
	st.islands=[F.rectangle(200.0,20.0,250.0,1680.0)]
	lease=_worker_slot051(arena)
	if not lease.is_empty() and _worker_join051(lease.slot):
		var slot: Dictionary=lease.slot
		source.x=100.0;source.y=850.0
		for tick: int in range(12):
			B.update(st,1.0/60.0);B.pop_events(st)
			if id in slot.adopted:break
		check(id in slot.adopted and not st.tactical.intents.has(id),"real worker suggestion grants no authority across a blocked fresh land connector")
		check(float(T.helm(st,source).throttle)==0.0,"fresh connector rejection brakes the actual hull")
	T.retire_planning051(st);T.drain_planning051()
	# The worker chose an ordinary approach. A newly close hostile requires a
	# CURRENT escape decision even though command/capability/terrain still match.
	arena=local_arena();st=arena.state;source=arena.source;id=str(source.id)
	lease=_worker_slot051(arena)
	if not lease.is_empty() and _worker_join051(lease.slot):
		var slot: Dictionary=lease.slot
		var old_phase: String=str(slot.capsule.result.planning.decisions[id].state.phase)
		var event_at: float=float(st.time)
		arena.target.x=float(source.x)+45.0;arena.target.y=float(source.y)
		B.update(st,1.0/60.0);B.pop_events(st)
		var fresh: Dictionary=st.tactical.memory.player.byId.get(id,{})
		var history: Array=fresh.get("observations",[])
		check(old_phase=="approach" and id in slot.discarded and id not in slot.adopted and str(fresh.get("phase",""))=="breakaway","changed live phase rejects worker offers and rebuilds from the fresh main escape decision")
		check(float(st.tactical.lastDecision.get(id,-1.0))==float(st.time) and not history.is_empty() and float(history[-1].lastAt)==float(st.time) and float(st.time)-event_at<=0.2+0.000001,"phase fallback publishes actual current observations within the unchanged deadline")
		observations.append({"case":"workers-fresh-phase","eventAt":event_at,"time":st.time,"workerPhase":old_phase,"mainPhase":fresh.get("phase",""),"adopted":slot.adopted.duplicate(),"discarded":slot.discarded.duplicate()})
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
			ray_cases();boarding_continuity();focused_boarding();explicit_boarding_authority();held_gun();useful_pressure();capabilities_and_observations();fleet_cadence();local_approach();retained_maneuver051();traffic_prefix051();workers051()
		"rays":ray_cases()
		"boarding":boarding_continuity()
		"focused-boarding":focused_boarding()
		"board-authority":explicit_boarding_authority()
		"held-gun":held_gun()
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
