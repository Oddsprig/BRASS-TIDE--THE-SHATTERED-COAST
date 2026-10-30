extends SceneTree
## Bounded behavior witness. Root alone runs this through the shared test lane.
## Published Battle decisions, real movement/events and existing physical audit.
## No forged certificates, shot acknowledgements, refills or pose writes after setup.
const B=preload("res://scripts/battle.gd")
const D=preload("res://scripts/damage.gd")
const T=preload("res://scripts/tactical_runtime.gd")
const Planner=preload("res://scripts/tactical_planner.gd")
const F=preload("res://tests/tactical_fixture.gd")
const Public=preload("res://tests/tactical_public_battle.gd")
const DT: float=1.0/30.0
const BODY_LIMIT_MS: int=12000
var started: int=0
var checks: int=0
var failures: int=0
var inherited_checks: int=0
var expired: bool=false
var physical_ok: bool=true
var physical_issues: Array=[]
var failure_labels: Array=[]
var observations: Array=[]
var ticks: int=0

func check(ok: bool,label: String,inherited: bool=false) -> void:
	checks+=1
	if inherited:inherited_checks+=1
	if not ok:
		failures+=1;failure_labels.append(label)
		print("FAIL counterplay074: "+label)

func spec(id: String,speed: float=120.0,size: float=16.0,mount_angle: float=0.0,arc: float=TAU) -> Dictionary:
	var result: Dictionary=F.SPEC.duplicate(true)
	result.merge({"id":id,"name":id,"hp":2000.0,"armor":0.0,"speed":speed,"size":size,"turn":2.5,"deploymentPoints":20},true)
	result.weaponMounts=[{"id":"mount0","kind":"gun","damage":1.0,"fireRate":2.0,"range":650.0,"speed":850.0,"ammoCost":1,"x":8.0,"y":0.0,"angle":mount_angle,"arc":arc}]
	return result

func arena(players: Array,enemies: Array) -> Dictionary:
	var st: Dictionary=B.create({"fleet":players,"enemyFleet":enemies,"islands":[],"seed":74074})
	st.autoBoard=false
	return st

func place(ship: Dictionary,point: Vector2,heading: float=0.0) -> void:
	# Declared opening geometry only. All later poses belong to Battle.update.
	ship.x=point.x;ship.y=point.y;ship.angle=heading

func memory(st: Dictionary,ship: Dictionary) -> Dictionary:
	return st.tactical.memory[str(ship.team)].byId.get(str(ship.id),{})

func intent(st: Dictionary,ship: Dictionary) -> Dictionary:
	return st.tactical.intents.get(str(ship.id),{})

func step(st: Dictionary,history: Dictionary) -> Dictionary:
	if Time.get_ticks_msec()-started>=BODY_LIMIT_MS:
		expired=true
		return {"advanced":false,"events":[]}
	if st.result!=null:
		check(false,"fixture remains nonterminal until its observations complete")
		return {"advanced":false,"events":[]}
	var before: float=float(st.time)
	var frame: Dictionary=Public.update(st,{},history)
	physical_ok=physical_ok and bool(frame.ok) and is_equal_approx(float(st.time),before+DT)
	for issue in frame.issues:
		if not issue in physical_issues and physical_issues.size()<6:physical_issues.append(issue)
	ticks+=1;frame.advanced=true
	return frame

func first_request(requests: Array,id: String) -> Dictionary:
	for candidate: Dictionary in requests:
		if str(candidate.shipId)==id:return candidate
	return {}

func complementary_run() -> Dictionary:
	var light: Dictionary=spec("074-light")
	var target_spec: Dictionary=spec("074-station",0.0,32.0)
	var st: Dictionary=arena([D.create_ship(light,{"uid":"074-a"}),D.create_ship(light,{"uid":"074-b"})],[D.create_ship(target_spec,{"uid":"074-target","ammo":0.0})])
	var a: Dictionary=st.ships[0];var b: Dictionary=st.ships[1];var target: Dictionary=st.ships[2]
	place(a,Vector2(500,820));place(b,Vector2(480,950));place(target,Vector2(900,850),PI)
	F.command(st,target,"hold")
	var history: Dictionary={};var published: Dictionary={};var shot_times: Dictionary={}
	var independent_fire: bool=false;var separated: bool=false;var proposal_repeatable: bool=false
	for tick in range(24):
		var frame: Dictionary=step(st,history)
		if not frame.advanced:break
		for ship: Dictionary in [a,b]:
			var chosen: Dictionary=intent(st,ship);var held: Dictionary=memory(st,ship)
			if not chosen.get("waypoints",[]).is_empty() and not str(chosen.get("pathFingerprint","")).is_empty() and str(chosen.get("targetId",""))==str(target.id) and held.get("anchor") is Vector2 and not published.has(str(ship.id)):
				published[str(ship.id)]={"sector":chosen.sector,"anchor":held.anchor,"exit":chosen.exit.duplicate(),"at":float(st.time)}
		if published.size()==2:
			var bearing_a: Vector2=published[str(a.id)].anchor-F.pos(target)
			var bearing_b: Vector2=published[str(b.id)].anchor-F.pos(target)
			separated=absf(bearing_a.angle_to(bearing_b))>=PI/2.0-0.01
		for event: Dictionary in frame.events:
			if str(event.kind)!="fire" or str(event.sourceId) not in [str(a.id),str(b.id)]:continue
			if not shot_times.has(str(event.sourceId)):shot_times[str(event.sourceId)]=float(event.time)
			var partner: Dictionary=b if str(event.sourceId)==str(a.id) else a
			var partner_state: Dictionary=memory(st,partner)
			if partner_state.get("anchor") is Vector2 and F.pos(partner).distance_to(partner_state.anchor)>45.0:independent_fire=true
		if tick==0:
			var view: Dictionary=T.view(st,"player",[str(a.id),str(b.id)])
			var held: Dictionary=st.tactical.memory.player
			var requests: Array=Planner.propose(view,held)
			proposal_repeatable=not first_request(requests,str(a.id)).is_empty() and not first_request(requests,str(b.id)).is_empty() and var_to_bytes(requests)==var_to_bytes(Planner.propose(view,held))
	var exits: bool=published.size()==2
	for record: Dictionary in published.values():exits=exits and not record.exit.is_empty() and record.anchor.distance_to(record.exit[-1])>60.0
	return {"published":published,"shots":shot_times,"separated":separated,"explicit_exits":exits,"independent_fire":independent_fire,"proposal_repeatable":proposal_repeatable,"time":float(st.time)}

func complementary_passes() -> void:
	var first: Dictionary=complementary_run();var second: Dictionary=complementary_run()
	check(first.separated and second.separated,"074: two published approaches pressure complementary bearings")
	check(first.explicit_exits and second.explicit_exits,"074: complementary offers retain explicit finite exits")
	check(first.shots.size()==2 and second.shots.size()==2 and first.independent_fire and second.independent_fire,"074: useful paid fire begins without waiting for a complete ring")
	check(first.proposal_repeatable and second.proposal_repeatable and var_to_bytes(first)==var_to_bytes(second),"074: same seed and public planner inputs repeat the compact opening")
	observations.append({"case":"complementary-opening","first":first,"same_seed_equal":var_to_bytes(first)==var_to_bytes(second),"limit":"Opening coordination only; recovery is witnessed separately below."})

func finite_recovery() -> void:
	var light: Dictionary=spec("074-recovery")
	var st: Dictionary=arena([D.create_ship(light,{"uid":"074-recover"})],[D.create_ship(spec("074-recovery-target",0.0,32.0),{"uid":"074-recovery-target","ammo":0.0})])
	var source: Dictionary=st.ships[0];var target: Dictionary=st.ships[1]
	place(source,Vector2(650,850));place(target,Vector2(1000,850),PI)
	F.command(st,target,"hold")
	var history: Dictionary={};var phases: Array=[];var first_shot: float=-1.0;var recovery_at: float=-1.0;var next_shot: float=-1.0
	var recovery_origin: Vector2=Vector2.ZERO;var recovery_pass: String="";var phase_since: float=-1.0;var stable_recovery: bool=false;var stable_pass: bool=true
	var first_new_pass_at: float=-1.0;var recovered_distance: float=0.0;var paid_shots: int=0;var refreshes: Dictionary={}
	for tick in range(270):
		var frame: Dictionary=step(st,history)
		if not frame.advanced:break
		var held: Dictionary=memory(st,source);var chosen: Dictionary=intent(st,source)
		var phase: String=str(held.get("phase",""));var pass_id: String=str(held.get("firingPassId",""))
		if not phase.is_empty() and (phases.is_empty() or phases[-1].phase!=phase):phases.append({"phase":phase,"at":float(st.time)})
		if recovery_at<0.0 and phase in ["breakaway","turn-away","regroup"]:
			recovery_at=float(st.time);recovery_origin=F.pos(source);recovery_pass=pass_id;phase_since=float(held.get("phaseSince",-1.0))
		if recovery_at>=0.0 and first_new_pass_at<0.0:
			if pass_id==recovery_pass and phase in ["breakaway","turn-away","regroup"]:
				stable_recovery=stable_recovery or (is_equal_approx(float(held.get("phaseSince",-2.0)),phase_since) and float(st.time)-phase_since>=0.3)
				if not chosen.get("waypoints",[]).is_empty() and not str(chosen.get("pathFingerprint","")).is_empty():refreshes[str(chosen.snapshotRevision)]=true
			elif not pass_id.is_empty() and pass_id!=recovery_pass:
				first_new_pass_at=float(st.time);recovered_distance=F.pos(source).distance_to(recovery_origin)
			else:stable_pass=false
		for event: Dictionary in frame.events:
			if str(event.kind)!="fire" or str(event.sourceId)!=str(source.id):continue
			paid_shots+=1
			if first_shot<0.0:first_shot=float(event.time)
			if first_new_pass_at>=0.0:next_shot=float(event.time)
		if next_shot>=0.0:break
	check(first_shot>0.0 and recovery_at>first_shot,"inherited: an observed paid gun burst reaches finite breakaway",true)
	check(stable_recovery and stable_pass and refreshes.size()>=2,"inherited: resampling preserves recovery age and pass identity",true)
	check(first_new_pass_at>recovery_at and recovered_distance>=55.0 and next_shot>=first_new_pass_at,"inherited: real recovery travel precedes another paid pass",true)
	check(paid_shots>=2 and is_equal_approx(80.0-float(source.ammo),float(paid_shots)) and float(source.fuel)<60.0,"inherited: repeated passes use finite actual ammunition and fuel",true)
	observations.append({"case":"finite-pass-recovery","phases":phases,"first_shot":first_shot,"recovery_at":recovery_at,"new_pass_at":first_new_pass_at,"new_pass_shot":next_shot,"recovery_travel":recovered_distance,"recovery_refreshes":refreshes.size(),"paid_shots":paid_shots,"time":float(st.time),"limit":"One close-water gun duel; no claim for every fitting or full public Lab voyage."})

func escort_and_orders() -> void:
	var st: Dictionary=arena([D.create_ship(spec("074-guard",130.0,22.0),{"uid":"074-guard"}),D.create_ship(spec("074-protected",0.0,32.0,0.0,PI/2.0),{"uid":"074-protected","ammo":0.0})],[D.create_ship(spec("074-flanker",120.0,16.0,0.0,PI/3.0),{"uid":"074-flanker","ammo":8.0})])
	var guard: Dictionary=st.ships[0];var leader: Dictionary=st.ships[1];var flanker: Dictionary=st.ships[2]
	# Nonclosing light pressure on the uncovered beam. Default line formation
	# lies on the opposite beam, so an ordinary formation advance is insufficient.
	place(guard,Vector2(750,850));place(leader,Vector2(950,850));place(flanker,Vector2(950,630))
	F.command(st,leader,"hold");F.command(st,flanker,"hold")
	check(B.set_tactical_options(st,[str(guard.id)],{"leash":240.0,"formation":"line"}) and B.issue_order(st,[str(guard.id)],"escort",{"shipId":str(leader.id)}),"inherited: escort command and finite leash are accepted",true)
	var start: Vector2=F.pos(guard);var history: Dictionary={};var interposed: bool=false;var leashed: bool=true;var chosen_target: bool=false;var escort_path: bool=false;var leash_max: float=0.0
	for tick in range(36):
		var frame: Dictionary=step(st,history)
		if not frame.advanced:break
		var chosen: Dictionary=intent(st,guard);var held: Dictionary=memory(st,guard)
		leash_max=maxf(leash_max,F.pos(guard).distance_to(F.pos(leader)))
		leashed=leashed and leash_max<=240.01
		chosen_target=chosen_target or (str(chosen.get("targetId",""))==str(flanker.id) and str(held.get("leaderId",""))==str(leader.id))
		if held.get("anchor") is Vector2 and str(chosen.get("phase",""))=="screen":
			escort_path=escort_path or not chosen.get("waypoints",[]).is_empty()
			leashed=leashed and held.anchor.distance_to(F.pos(leader))<=240.01
		interposed=interposed or (F.point_segment(F.pos(guard),F.pos(leader),F.pos(flanker))+10.0<F.point_segment(start,F.pos(leader),F.pos(flanker)) and (F.pos(guard)-start).dot((F.pos(flanker)-F.pos(leader)).normalized())>10.0)
	check(chosen_target and escort_path and interposed and leashed,"074: escort publishes and moves toward flank interception inside its leash")
	var revision: int=int(guard.orderRevision)
	check(B.issue_order(st,[str(guard.id)],"attack",{"shipId":str(flanker.id)}),"inherited: explicit attack replaces escort",true)
	var attack_seen: bool=false
	for tick in range(9):
		if not step(st,history).advanced:break
		var chosen: Dictionary=intent(st,guard)
		attack_seen=attack_seen or (int(chosen.get("orderRevision",-1))==int(guard.orderRevision) and str(chosen.get("targetId",""))==str(flanker.id))
	check(attack_seen and int(guard.orderRevision)>revision and str(guard.order)=="attack","inherited: published attack honors the selected hostile and new command revision",true)
	check(B.issue_order(st,[str(guard.id)],"hold"),"inherited: defend uses the existing hold command",true)
	var hold_point: Vector2=F.pos(guard);var hold_distance: float=0.0;var hold_seen: bool=false;var defend_shots: int=0
	for tick in range(18):
		var frame: Dictionary=step(st,history)
		if not frame.advanced:break
		hold_distance=maxf(hold_distance,F.pos(guard).distance_to(hold_point))
		hold_seen=hold_seen or str(intent(st,guard).get("phase",""))=="hold"
		for event: Dictionary in frame.events:
			if str(event.kind)=="fire" and str(event.sourceId)==str(guard.id):defend_shots+=1
	check(hold_seen and hold_distance<=45.0 and defend_shots>0,"inherited: defend holds its station and answers with real fire",true)
	var away: Vector2=F.pos(guard)+Vector2(-300,0);var from: Vector2=F.pos(guard);var rounds: float=float(guard.ammo)
	check(B.issue_order(st,[str(guard.id)],"withdraw",{"x":away.x,"y":away.y}),"inherited: explicit local withdrawal is accepted",true)
	var withdrew: bool=false;var forbidden_fire: bool=false
	for tick in range(36):
		var frame: Dictionary=step(st,history)
		if not frame.advanced:break
		withdrew=withdrew or (str(intent(st,guard).get("phase",""))=="withdraw" and F.pos(guard).distance_to(away)+10.0<from.distance_to(away))
		for event: Dictionary in frame.events:
			if str(event.kind)=="fire" and str(event.sourceId)==str(guard.id):forbidden_fire=true
	check(withdrew and not forbidden_fire and is_equal_approx(rounds,float(guard.ammo)),"inherited: withdraw makes actual destination progress and suppresses automatic fire",true)
	observations.append({"case":"escort-and-orders","interception_motion":interposed,"anchors_and_hull_inside_leash":leashed,"maximum_escort_distance":leash_max,"attack_published":attack_seen,"hold_max_drift":hold_distance,"defend_shots":defend_shots,"withdraw_progress":withdrew,"withdraw_fired":forbidden_fire,"time":float(st.time)})

func heavy_fit(mount_angle: float) -> Dictionary:
	var st: Dictionary=arena([D.create_ship(spec("074-heavy",70.0,32.0,mount_angle,PI*0.75),{"uid":"074-heavy"})],[D.create_ship(spec("074-heavy-flank",120.0,16.0,0.0,PI/3.0),{"uid":"074-heavy-flank","ammo":8.0}),D.create_ship(spec("074-decoy",120.0,16.0,0.0,PI/3.0),{"uid":"074-decoy","ammo":8.0})])
	var heavy: Dictionary=st.ships[0];var flanker: Dictionary=st.ships[1]
	place(heavy,Vector2(950,850));place(flanker,Vector2(950,1200));place(st.ships[2],Vector2(1250,850))
	F.command(st,flanker,"hold");F.command(st,st.ships[2],"hold")
	var history: Dictionary={};var published: bool=false;var shots: int=0;var fire_heading: float=0.0
	for tick in range(42):
		var frame: Dictionary=step(st,history)
		if not frame.advanced:break
		var chosen: Dictionary=intent(st,heavy)
		published=published or (str(chosen.get("role",""))=="heavy" and str(chosen.get("targetId",""))==str(flanker.id) and not chosen.get("waypoints",[]).is_empty())
		for event: Dictionary in frame.events:
			if str(event.kind)=="fire" and str(event.sourceId)==str(heavy.id) and str(event.get("targetId",""))==str(flanker.id):
				if shots==0:fire_heading=float(heavy.angle)
				shots+=1
	return {"mount_angle":mount_angle,"heading":float(heavy.angle),"first_flank_shot_heading":fire_heading,"published":published,"paid_shots_at_flanker":shots,"travel":F.pos(heavy).distance_to(Vector2(950,850)),"time":float(st.time)}

func heavy_working_arcs() -> void:
	var bow: Dictionary=heavy_fit(0.0);var beam: Dictionary=heavy_fit(PI/2.0)
	check(bow.published and beam.published and bow.paid_shots_at_flanker>0 and beam.paid_shots_at_flanker>0,"074: heavy answers flank pressure despite a closer frontal decoy")
	check(absf(angle_difference(float(bow.first_flank_shot_heading),float(beam.first_flank_shot_heading)))>0.25 and absf(float(bow.first_flank_shot_heading))>0.25,"074: changing the working gun arc changes the actual heavy response")
	observations.append({"case":"heavy-working-fit","bow":bow,"beam":beam,"limit":"Two declared fitted arcs; canonical mount disable/damage authority remains inherited coverage."})

func _initialize() -> void:
	started=Time.get_ticks_msec()
	if DisplayServer.get_name()!="headless":
		check(false,"headless fixture only")
	else:
		complementary_passes()
		finite_recovery()
		escort_and_orders()
		heavy_working_arcs()
	check(physical_ok,"inherited: existing real event/cooldown/ammunition audit remains strict",true)
	check(not expired and Time.get_ticks_msec()-started<15000,"bounded fixture completes below fifteen seconds; incomplete work fails")
	print(JSON.stringify(F.encode({"fixture":"counterplay074","checks":checks,"failures":failures,"inherited_checks":inherited_checks,"scope074_checks":checks-inherited_checks,"elapsed_ms":Time.get_ticks_msec()-started,"ticks":ticks,"complete":not expired and failures==0,"failure_labels":failure_labels,"physical_issues":physical_issues,"observations":observations,"limits":"Source fixture until Root executes. No rendered motion, listening, whole-game quality, strict FPS, worker scheduling or 073 art claim."})))
	quit(0 if failures==0 else 1)
