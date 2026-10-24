extends SceneTree
## Actual Battle integration. No direct _fire, fake certificates or RNG retries.
const B=preload("res://scripts/battle.gd")
const D=preload("res://scripts/damage.gd")
const Refit=preload("res://scripts/refit.gd")
const T=preload("res://scripts/tactical_runtime.gd")
const C=preload("res://scripts/tactical_certification.gd")
const Fire=preload("res://scripts/tactical_fire_control.gd")
const Roles=preload("res://scripts/tactical_role_plans.gd")
const Boarding=preload("res://scripts/boarding.gd")
const BoardControl=preload("res://scripts/combat_boarding.gd")
const F=preload("res://tests/tactical_fixture.gd")
const DT: float=1.0/30.0
const SPEC={"id":"ai-probe","name":"AI integration","hp":1000.0,"armor":0,"crewMin":2,"crewOptimal":12,"crewMax":30,"size":16,"speed":100.0,"turn":2.5,"pumps":1,"weapon":"gun","damage":1.0,"fireRate":2.0,"range":900.0,"deploymentPoints":20}
var checks: int=0
var failures: int=0
var observations: Array=[]

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

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":quit(2);return
	var selected: String="all"
	var path: String=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):selected=arg.substr(7)
		if arg.begins_with("--out="):path=arg.substr(6)
	match selected:
		"all":
			ray_cases();boarding_continuity();focused_boarding();explicit_boarding_authority();held_gun();useful_pressure();capabilities_and_observations();fleet_cadence();local_approach()
		"rays":ray_cases()
		"boarding":boarding_continuity()
		"focused-boarding":focused_boarding()
		"board-authority":explicit_boarding_authority()
		"held-gun":held_gun()
		"useful-pressure":useful_pressure()
		"capabilities":capabilities_and_observations()
		"fleet-cadence":fleet_cadence()
		"local-approach":local_approach()
		_:quit(2);return
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(F.encode({"checks":checks,"failures":failures,"observations":observations})));file.close()
	print("Tactical AI %s: %d checks, %d failures"%[selected,checks,failures])
	quit(0 if failures==0 else 1)
