extends RefCounted
## Prospective r4 observer. Frozen r3 remains byte-for-byte separate.
const F=preload("res://tests/tactical_fixture.gd")
const B=preload("res://scripts/battle.gd")
const D=preload("res://scripts/damage.gd")
const C=preload("res://scripts/tactical_certification.gd")
const DT: float=1.0/30.0

static func config() -> Dictionary:
	var path: String=ProjectSettings.globalize_path("res://").path_join("../tools/tactical_scenarios.r4.json").simplify_path()
	return JSON.parse_string(FileAccess.get_file_as_string(path))

static func create_case(definitions: Dictionary,scenario_id: String,variant_id: String,seed: int,orientation: String) -> Dictionary:
	# Variant damage is a declared INITIAL condition, never an observation edit.
	var detached: Dictionary=definitions.duplicate(true)
	for row in detached.scenarios:
		if str(row.id)!=scenario_id:continue
		for variant in row.variants:
			if str(variant.id)==variant_id and variant.has("actor_damage"):row.actor_damage=variant.actor_damage.duplicate(true)
	return F.create_case(detached,scenario_id,variant_id,seed,orientation)

static func condition(ship: Dictionary) -> Dictionary:
	var status: Dictionary=D.get_status(ship)
	return {"time":float(ship.get("battleTime",0.0)),"pose":C.pose(ship),"hp":float(ship.hp),"max_hp":float(ship.maxHp),"water":float(ship.water),"capacity":float(ship.capacity),"fire":float(ship.fire),"breach_area":D.sum_areas(ship),"crew":float(ship.crew),"wounded":float(ship.wounded),"engine":float(ship.engine),"ammo":float(ship.ammo),"fuel":float(ship.fuel),"supplies":float(ship.supplies),"status":status.duplicate(true)}

static func danger_observer(case: Dictionary) -> Dictionary:
	var observation: Dictionary={"enabled":str(case.definition.id)=="A4","onset":{},"escape":{},"witness":{},"samples":[],"actual_hit_events":[],"travel":0.0,"max_goal_progress":0.0,"max_away_velocity":0.0,"previous":F.pos(case.actors[0]),"success":false}
	observe_danger(case,observation,[])
	return observation

static func observe_danger(case: Dictionary,observation: Dictionary,events: Array) -> void:
	if not observation.enabled:return
	var st: Dictionary=case.state;var actor: Dictionary=case.actors[0]
	var now: float=float(st.time);var actual: Dictionary=condition(actor)
	for event in events:
		if str(event.kind)=="hit" and str(event.get("targetId",""))==str(actor.id):observation.actual_hit_events.append(event.duplicate(true))
	observation.samples.append({"time":now,"hp":float(actor.hp)})
	while observation.samples.size()>0 and float(observation.samples[0].time)<now-2.0-0.000001:observation.samples.pop_front()
	var peak: float=float(actor.hp)
	for sample in observation.samples:peak=maxf(peak,float(sample.hp))
	var focused: int=0;var threats: Array=[]
	# Independent actual geometry/shot observations; no planner annotation or
	# production threat()/decide() call. The scenario has at most three hostiles.
	for enemy in case.opponents:
		if not F.live(enemy):continue
		var delta: Vector2=F.pos(actor)-F.pos(enemy)
		var pressure: float=0.0;var within: Array=[]
		for mount in B._mounts(enemy):
			var distance: float=delta.length();var reach: float=float(mount.range)
			if distance<=reach*1.15 and absf(angle_difference(float(enemy.angle)+float(mount.angle),delta.angle()))<=float(mount.arc)*0.5+0.15:
				pressure=maxf(pressure,1.0-clampf(distance/maxf(1.0,reach*1.6),0.0,0.8));within.append(str(mount.id))
		var shot: float=-1.0
		for stamp in enemy.get("mountShotTimes",{}).values():shot=maxf(shot,float(stamp))
		if shot>=0.0 and now-shot<=2.0:pressure*=1.5
		if pressure>0.75:focused+=1
		threats.append({"id":str(enemy.id),"pose":C.pose(enemy),"distance":delta.length(),"covering_mounts":within,"latest_real_shot":shot,"pressure":pressure})
	var net: float=float(actual.status.inflow)-float(actual.status.bailing)
	var evidence: Array=[]
	if float(actor.hp)/float(actor.maxHp)<=0.45:evidence.append("actual_hp_fraction_at_or_below_0.45")
	if float(actor.water)/float(actor.capacity)>=0.45:evidence.append("actual_water_fraction_at_or_above_0.45")
	if float(actor.fire)>=25.0:evidence.append("actual_fire_at_or_above_25")
	if net>0.0 and (float(actor.capacity)-float(actor.water))/net<8.0:evidence.append("actual_net_flooding_less_than_8s_to_capacity")
	if focused>=2 and peak-float(actor.hp)>=0.08*float(actor.maxHp):evidence.append("two_actual_covering_recent_threats_and_8pct_recent_hp_loss")
	if observation.onset.is_empty() and not evidence.is_empty():
		observation.onset={"time":now,"condition":actual,"pose":C.pose(actor),"evidence":evidence,"recent_hp_loss":peak-float(actor.hp),"threats":threats,"actual_hits":observation.actual_hit_events.duplicate(true)}
		observation.previous=F.pos(actor)
	if observation.onset.is_empty():observation.previous=F.pos(actor);return
	observation.travel+=F.pos(actor).distance_to(observation.previous);observation.previous=F.pos(actor)
	if observation.escape.is_empty():
		var intent: Dictionary=st.tactical.intents.get(str(actor.id),{})
		var current: Dictionary=C.current(st,actor,intent,DT)
		if current.get("ok",false):
			var candidate: Dictionary=current.record.candidate
			var exit_path: Array=candidate.get("exit",[])
			var origin: Vector2=Vector2(observation.onset.pose.x,observation.onset.pose.y)
			if candidate.get("fireMountIds",[]).is_empty() and not exit_path.is_empty():
				var goal: Vector2=exit_path[-1];var away: Vector2=origin-F.pos(case.opponents[0])
				if origin.distance_to(goal)>=80.0 and (goal-origin).dot(away)>0.0:
					observation.escape={"observed_at":now,"checked_at":float(current.record.certificate.checkedAt),"onset_pose":observation.onset.pose.duplicate(true),"capture_pose":C.pose(actor),"goal":goal,"candidate":candidate.duplicate(true),"certificate":current.record.certificate.duplicate(true),"post_motion_current_valid":true}
	if observation.escape.is_empty() or not F.live(actor) or not F.live(case.opponents[0]):return
	var origin: Vector2=Vector2(observation.onset.pose.x,observation.onset.pose.y)
	var goal: Vector2=observation.escape.goal
	var progress: float=origin.distance_to(goal)-F.pos(actor).distance_to(goal)
	var away_speed: float=Vector2(actor.vx,actor.vy).dot((F.pos(actor)-F.pos(case.opponents[0])).normalized())
	observation.max_goal_progress=maxf(float(observation.max_goal_progress),progress)
	observation.max_away_velocity=maxf(float(observation.max_away_velocity),away_speed)
	if observation.travel>=80.0 and progress>=64.0 and away_speed>5.0 and not observation.success:
		observation.success=true
		observation.witness={"time":now,"condition":actual,"pose":C.pose(actor),"hostile_pose":C.pose(case.opponents[0]),"travel_since_danger":observation.travel,"progress_toward_captured_escape":progress,"actual_velocity_away":away_speed,"relative_range":F.pos(actor).distance_to(F.pos(case.opponents[0]))}

static func recovery_observer(case: Dictionary) -> Dictionary:
	var initial: Dictionary=condition(case.actors[0])
	return {"enabled":bool(case.variant.get("requires_recovery",false)),"initial":initial,"final":initial.duplicate(true),"paid_hp_gain":0.0,"supplies_spent":0.0,"breach_area_repaired":0.0,"minimum_water":float(initial.water),"minimum_fire":float(initial.fire),"repair_crew_observed":false,"bailing_crew_observed":false,"first_paid_repair":{},"actual_incoming_hits":[]}

static func observe_recovery(case: Dictionary,observation: Dictionary,before: Dictionary,events: Array,issues: Dictionary) -> void:
	if not observation.enabled:return
	var ship: Dictionary=case.actors[0];var after: Dictionary=condition(ship)
	var hp_gain: float=maxf(0.0,float(after.hp)-float(before.hp))
	var patch: float=maxf(0.0,float(before.breach_area)-float(after.breach_area))
	var debit: float=float(before.supplies)-float(after.supplies)
	# Independently account material consumed by visible patch/hull improvements.
	# Concurrent fire/impact can hide some paid repair, never create a free gain.
	if hp_gain*0.35+patch*0.018>debit+0.00001:issues["Actual repair improvement exceeds finite material debit"]=true
	if hp_gain>0.0 and (float(before.status.crewRepair)<=0.0 or debit<=0.0):issues["Hull recovery occurred without actual repair people and supplies"]=true
	observation.paid_hp_gain+=hp_gain;observation.supplies_spent+=maxf(0.0,debit);observation.breach_area_repaired+=patch
	observation.minimum_water=minf(float(observation.minimum_water),float(after.water))
	observation.minimum_fire=minf(float(observation.minimum_fire),float(after.fire))
	if float(before.status.crewRepair)>0.0:observation.repair_crew_observed=true
	if float(before.status.crewBail)>0.0:observation.bailing_crew_observed=true
	if hp_gain>0.0 and observation.first_paid_repair.is_empty():observation.first_paid_repair={"time":float(case.state.time),"before":before,"after":after,"actual_hp_gain":hp_gain,"actual_supplies_debit":debit}
	for event in events:
		if str(event.kind)=="hit" and str(event.get("targetId",""))==str(ship.id):observation.actual_incoming_hits.append(event.duplicate(true))
	observation.final=after

static func recovery_failures(case: Dictionary,observation: Dictionary,definitions: Dictionary) -> Array:
	var failures: Array=[]
	if not F.live(case.actors[0]):failures.append("Protected recovery hull did not remain alive and in its owner's custody")
	if float(observation.paid_hp_gain)<float(definitions.physical_metrics.recovery_minimum_hp_gain) or observation.first_paid_repair.is_empty():failures.append("No meaningful actual HP recovery funded by finite supplies")
	if float(observation.initial.water)-float(observation.minimum_water)<float(definitions.physical_metrics.recovery_minimum_water_reduction):failures.append("Actual protected hull water did not improve")
	if float(observation.initial.fire)-float(observation.minimum_fire)<float(definitions.physical_metrics.recovery_minimum_fire_reduction):failures.append("Actual protected hull fire did not improve")
	if not observation.repair_crew_observed or not observation.bailing_crew_observed or float(observation.supplies_spent)<=0.0:failures.append("Recovery lacks real crew work or material payment")
	return failures

static func observe_protection(case: Dictionary,traveled: Dictionary,definitions: Dictionary) -> Dictionary:
	var groups: Array=[]
	if case.definition.has("protect_opponent_index"):groups.append({"members":case.opponents,"leader":int(case.definition.protect_opponent_index),"threats":case.actors})
	if case.definition.has("protect_actor_index") or case.variant.has("protect_actor_index"):groups.append({"members":case.actors,"leader":int(case.variant.get("protect_actor_index",case.definition.get("protect_actor_index",0))),"threats":case.opponents})
	for group in groups:
		var leader: Dictionary=group.members[group.leader]
		if not F.live(leader):continue
		for index in range(group.members.size()):
			if index==int(group.leader):continue
			var screen: Dictionary=group.members[index]
			for threat in group.threats:
				if not F.live(screen) or not F.live(threat):continue
				var a: Vector2=F.pos(leader);var b: Vector2=F.pos(threat)
				var fraction: float=(F.pos(screen)-a).dot(b-a)/maxf(1.0,(b-a).length_squared())
				var distance: float=F.point_segment(F.pos(screen),a,b)
				if fraction>0.0 and fraction<1.0 and distance<=float(definitions.physical_metrics.screen_intercept_max_distance_to_threat_ally_segment) and float(traveled[str(screen.id)])>=40.0:
					return {"time":float(case.state.time),"screen_id":str(screen.id),"leader_id":str(leader.id),"threat_id":str(threat.id),"screen_pose":C.pose(screen),"protected_condition":condition(leader),"threat_pose":C.pose(threat),"actual_screen_travel":float(traveled[str(screen.id)]),"segment_fraction":fraction,"distance_to_threat_protected_segment":distance}
	return {}

static func run_case(definitions: Dictionary,scenario_id: String,variant_id: String,seed: int,orientation: String,ticks: int,process_started: int=0) -> Dictionary:
	var started: int=Time.get_ticks_usec() if process_started==0 else process_started
	var case: Dictionary=create_case(definitions,scenario_id,variant_id,seed,orientation)
	if case.has("error"):return {"status":"INVALID_FIXTURE","failures":[case.error]}
	var st: Dictionary=case.state
	var traces: Array=[F.snapshot(st)]
	var events: Array=[]
	var scripted_events: Array=[]
	var starts: Dictionary={};var previous: Dictionary={};var traveled: Dictionary={}
	var first_shot_pos: Dictionary={};var minimum_range: Dictionary={}
	var useful_actor_shots: int=0
	var enemy_shots: int=0
	var separated: bool=false
	var breakaway: bool=false
	var protective_motion: bool=false
	var survival_retreat: bool=false
	var physical_issues: Dictionary={}
	var minimum_ally_gap: float=INF
	var missing_memory: int=0
	var aged_memory: bool=false
	var last_phase: Dictionary={};var last_since: Dictionary={}
	var last_role: Dictionary={};var last_revision: Dictionary={};var stores: Dictionary={}
	var exited: Dictionary={};var second_pass: bool=false
	var actual_hits: int=0
	var status: String="COMPLETE_OBSERVATION_WINDOW"
	var frames: int=0
	var survival: Dictionary=danger_observer(case)
	var recovery: Dictionary=recovery_observer(case)
	var protection_witness: Dictionary={}
	var closest_allied_sweep: Dictionary={}
	for ship in st.ships:
		starts[str(ship.id)]=F.pos(ship);previous[str(ship.id)]=F.pos(ship);traveled[str(ship.id)]=0.0
		stores[str(ship.id)]={"ammo":float(ship.ammo),"fuel":float(ship.fuel),"supplies":float(ship.supplies)}
	for tick in range(ticks):
		if st.result!=null:status="TERMINAL_OUTCOME";break
		if Time.get_ticks_usec()-started>int(definitions.behavior_protocol.process_work_bound_seconds)*1000000:status="WORK_BOUND_INCOMPLETE";break
		var injected: Dictionary=F.event_at(case,tick)
		if not injected.is_empty():scripted_events.append(injected)
		var ammo_before: float=0.0
		for ship in st.ships:ammo_before+=float(ship.ammo)
		var pre_condition: Dictionary=condition(case.actors[0])
		B.update(st,DT,{})
		frames+=1
		var work: Dictionary=st.tactical.budget
		for key in ["fullRoutes","rollouts","samples","clearanceTests"]:
			if int(work.get(key,0))>int(definitions.exact_work_limits[key]):physical_issues["Actual shared "+key+" work cap exceeded"]=true
		if st.tactical.routeCache.size()>int(definitions.exact_work_limits.cacheEntries) or st.tactical.trace.size()>int(definitions.exact_work_limits.traceRecords):physical_issues["Actual bounded runtime cache or trace exceeded"]=true
		var raw_events: Array=B.pop_events(st)
		observe_danger(case,survival,raw_events)
		observe_recovery(case,recovery,pre_condition,raw_events,physical_issues)
		var prior_positions: Dictionary=previous.duplicate()
		var spent: float=0.0
		for event in raw_events:
			if str(event.kind)=="hit":
				var hit_source: Dictionary=F.find(st,str(event.sourceId));var hit_target: Dictionary=F.find(st,str(event.targetId))
				if hit_source in case.actors and not hit_target.is_empty() and hit_source.team!=hit_target.team:actual_hits+=1
			if str(event.kind)!="fire":continue
			var shooter: Dictionary=F.find(st,str(event.sourceId))
			var target: Dictionary=F.find(st,str(event.targetId))
			var mount: Dictionary={}
			if shooter.is_empty():physical_issues["Unknown emitting hull"]=true;continue
			for fitted in B._mounts(shooter):
				if str(fitted.id)==str(event.mountId):mount=fitted;break
			if shooter.is_empty() or mount.is_empty():physical_issues["Unknown emitted mount"]=true;continue
			spent+=float(mount.ammoCost)
			if target.is_empty() or target.team==shooter.team:physical_issues["Automatic shot has no real hostile target"]=true
			if absf(angle_difference(float(shooter.angle)+float(mount.angle),float(event.angle)))>float(mount.arc)*0.5+0.10:physical_issues["Emitted shot outside actual mount arc"]=true
			var muzzle: Vector2=Vector2(event.x,event.y)
			if F.ray_land(st,muzzle,muzzle,float(5 if mount.kind=="torpedo" else 3)):physical_issues["Actual emitted muzzle intersects land"]=true
			events.append({"event":event.duplicate(true),"shooter_pose":{"x":float(shooter.x),"y":float(shooter.y),"vx":float(shooter.vx),"vy":float(shooter.vy),"heading":float(shooter.angle)},"target_pose":{} if target.is_empty() else {"x":float(target.x),"y":float(target.y),"vx":float(target.vx),"vy":float(target.vy)},"mount":mount.duplicate(true),"ammo_after":float(shooter.ammo)})
			if shooter in case.actors:
				useful_actor_shots+=1
				if not first_shot_pos.has(str(shooter.id)):first_shot_pos[str(shooter.id)]=F.pos(shooter)
			else:enemy_shots+=1
		var ammo_after: float=0.0
		for ship in st.ships:
			ammo_after+=float(ship.ammo)
			var id: String=str(ship.id)
			var old_position: Vector2=prior_positions[id]
			for other in st.ships:
				if other.team!=ship.team or str(other.id)<=id or not F.live(ship) or not F.live(other):continue
				var relative: Vector2=old_position-(prior_positions[str(other.id)] as Vector2)
				var travel: Vector2=(F.pos(ship)-old_position)-(F.pos(other)-(prior_positions[str(other.id)] as Vector2))
				var fraction: float=clampf(-relative.dot(travel)/maxf(0.000001,travel.length_squared()),0.0,1.0)
				var gap: float=(relative+travel*fraction).length()-maxf(10.0,float(ship.spec.size))-maxf(10.0,float(other.spec.size))
				if gap<minimum_ally_gap:closest_allied_sweep={"time":float(st.time),"gap":gap,"first":str(ship.id),"second":str(other.id),"first_before":old_position,"first_after":C.pose(ship),"second_before":prior_positions[str(other.id)],"second_after":C.pose(other),"work":work.duplicate(true)}
				minimum_ally_gap=minf(minimum_ally_gap,gap)
				if gap<6.8:physical_issues["Actual allied swept hull gap below B's 7-unit clearance"]=true
			var memory: Dictionary=st.tactical.memory[str(ship.team)].byId.get(id,{})
			if F.live(ship) and tick>=6 and memory.is_empty():missing_memory+=1
			if not memory.is_empty():
				var phase: String=str(memory.get("phase",""))
				var since: float=float(memory.get("phaseSince",st.time))
				if phase==str(last_phase.get(id,"")) and str(memory.get("role",""))==str(last_role.get(id,"")) and int(memory.get("orderRevision",-1))==int(last_revision.get(id,-2)) and since!=float(last_since.get(id,since)):physical_issues["Stable memory phase age was reset without a phase, role or order change"]=true
				if float(st.time)-since>=0.5:aged_memory=true
				last_phase[id]=phase;last_since[id]=since
				last_role[id]=str(memory.get("role",""));last_revision[id]=int(memory.get("orderRevision",-1))
			for key in ["ammo","fuel","supplies"]:
				if float(ship[key])>float(stores[id][key])+0.000001:physical_issues["Unfunded working store increase"]=true
				stores[id][key]=float(ship[key])
			traveled[id]+=F.pos(ship).distance_to(previous[id]);previous[id]=F.pos(ship)
			if F.live(ship) and F.ray_land(st,F.pos(ship),F.pos(ship),maxf(10.0,float(ship.spec.size))-0.2):physical_issues["Actual hull penetrates land"]=true
			for key in ["hp","water","ammo","fuel","supplies","crew","x","y","vx","vy"]:
				if not is_finite(float(ship[key])):physical_issues["Nonfinite physical state"]=true
			if float(ship.ammo)<0.0 or float(ship.fuel)<0.0 or float(ship.supplies)<0.0:physical_issues["Negative working store"]=true
		if absf((ammo_before-ammo_after)-spent)>0.00001:physical_issues["Finite actual emissions do not match spent working rounds"]=true
		if case.actors.size()>=3 and F.live(case.opponents[0]):
			var bearings: Array=[]
			var spread: float=0.0
			for actor in case.actors:
				if F.live(actor) and float(traveled[str(actor.id)])>=float(definitions.physical_metrics.separated_approach_min_travel_world_units):bearings.append((F.pos(actor)-F.pos(case.opponents[0])).angle())
			for a in bearings:
				for b in bearings:spread=maxf(spread,absf(angle_difference(float(a),float(b))))
			if bearings.size()>=3 and spread>=deg_to_rad(float(definitions.physical_metrics.separated_approach_min_bearing_spread_degrees)):separated=true
		for actor in case.actors:
			var id: String=str(actor.id)
			if not F.live(actor) or not F.live(case.opponents[0]):continue
			var delta: Vector2=F.pos(actor)-F.pos(case.opponents[0])
			if scenario_id=="A4" and actor==case.actors[0]:survival_retreat=bool(survival.success)
			if first_shot_pos.has(id):
				minimum_range[id]=minf(float(minimum_range.get(id,delta.length())),delta.length())
				var exiting: bool=delta.length()-float(minimum_range[id])>=float(definitions.physical_metrics.exit_radial_gain_world_units) and Vector2(actor.vx,actor.vy).dot(delta.normalized())>5.0 and F.pos(actor).distance_to(first_shot_pos[id])>=float(definitions.physical_metrics.exit_radial_gain_world_units)
				if exiting:breakaway=true
				if exiting and not exited.has(id):exited[id]={"time":float(st.time),"distance":delta.length()}
				if exited.has(id) and float(actor.get("lastShotTime",-1.0))>float(exited[id].time) and delta.length()<float(exited[id].distance)-32.0:second_pass=true
		if protection_witness.is_empty():protection_witness=observe_protection(case,traveled,definitions)
		if not protection_witness.is_empty():protective_motion=true
		if tick%int(definitions.behavior_protocol.trace_every_ticks)==0 or not raw_events.is_empty():traces.append(F.snapshot(st))
	if st.result!=null:status="TERMINAL_OUTCOME"
	traces.append(F.snapshot(st))
	var failures: Array=physical_issues.keys()
	if missing_memory>0:failures.append("Actual live hull frames lost persistent planner memory")
	if not aged_memory:failures.append("No persistent phase age progressed for half a second")
	var actor_losses: int=0
	for actor in case.actors:
		if not F.live(actor):actor_losses+=1
	var counter_defeat: bool=actor_losses>0 and enemy_shots>0
	if status=="WORK_BOUND_INCOMPLETE":failures.append("Work bound reached; behavior case incomplete")
	if case.variant.get("requires_separated_approach",false) and not separated:failures.append("No observed separated reachable approach from native starting positions")
	if case.variant.get("requires_useful_fire",false) and useful_actor_shots<int(definitions.physical_metrics.minimum_useful_firing_events_favorable_case):failures.append("No actual useful actor firing pass")
	if case.variant.get("requires_useful_fire",false) and useful_actor_shots>0 and actual_hits==0 and not counter_defeat:failures.append("Favorable emitted shots produced no actual hostile hit or real counter defeat")
	if scenario_id in ["A1","A3"] and case.variant.get("requires_useful_fire",false) and not second_pass and not counter_defeat:failures.append("No actual second firing pass after separated exit/re-entry")
	if scenario_id in ["A1","A3"] and useful_actor_shots>0 and not breakaway and not counter_defeat:failures.append("Firing did not lead to an observed physical breakaway or real counter defeat")
	if case.variant.get("requires_no_actor_fire",false) and useful_actor_shots>0:failures.append("Empty tubes emitted free rounds")
	if case.variant.get("requires_protective_motion",false) and not protective_motion:failures.append("No actual screen movement between threat and protected ally")
	if scenario_id=="A4" and (case.variant.get("requires_survival_retreat",false) or not survival.onset.is_empty()) and not survival_retreat and not (case.variant.get("counter_outcome_allowed",false) and counter_defeat):failures.append("Observed actual danger did not produce required checked local survival motion")
	if case.variant.get("requires_physical_breakaway",false) and (not breakaway or float(traveled[str(case.actors[0].id)])<80.0) and not counter_defeat:failures.append("Original open damaged case lacks actual physical travel and firing breakaway")
	if case.variant.get("requires_recovery",false):
		for issue in recovery_failures(case,recovery,definitions):failures.append(issue)
	if scenario_id in ["A2","A5"]:
		var motion: bool=false
		for actor in case.actors:
			if float(traveled[str(actor.id)])>=float(definitions.physical_metrics.movement_min_world_units):motion=true
		if not motion and not counter_defeat:failures.append("No observed adaptation/movement from initial separated positions")
	if scenario_id=="A5" and variant_id=="leader_destroyed":
		var leader_id: String=str(case.actors[int(case.definition.protect_actor_index)].id)
		for actor in case.actors:
			if F.live(actor) and actor.order=="escort" and str(actor.orderTarget.get("shipId",""))==leader_id:failures.append("Actual live escort retains destroyed leader order")
	return F.encode({"protocol":"prospective-r4","mode":"behavior","status":status,"scenario":scenario_id,"variant":variant_id,"orientation":orientation,"seed":seed,"ticks_requested":ticks,"ticks_observed":frames,"simulated_seconds":float(st.time),"terminal_result":st.result,"failures":failures,"metrics":{"traveled":traveled,"actor_shots":useful_actor_shots,"opponent_shots":enemy_shots,"actual_actor_hits":actual_hits,"minimum_allied_swept_hull_gap":minimum_ally_gap if is_finite(minimum_ally_gap) else null,"missing_memory_frames":missing_memory,"aged_memory":aged_memory,"actual_second_pass":second_pass,"separated_approach":separated,"physical_breakaway":breakaway,"protective_motion":protective_motion,"survival_retreat":survival_retreat,"actual_danger_exercised":not survival.onset.is_empty(),"danger_observation":survival,"protected_recovery":recovery,"protection_witness":protection_witness,"closest_allied_sweep":closest_allied_sweep,"actor_losses":actor_losses,"counter_defeat":counter_defeat},"scripted_events":scripted_events,"fire_events":events,"trace":traces,"scope":"Actual position/heading/shot/mount/store observations; no GPU, audio or guaranteed-light-win claim"})
