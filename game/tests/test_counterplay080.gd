extends SceneTree
## One stock encounter through the exported game's sampled worker driver.
## Root alone runs this. Static opening/observation APIs also serve its capture.
## No pose/HP/crew/store/phase writes after Driver acquisition; no refill/forced win.
const B=preload("res://scripts/battle.gd")
const T=preload("res://scripts/tactical_runtime.gd")
const Driver=preload("res://scripts/battle_driver051.gd")
const Lab=preload("res://scripts/fleet_lab.gd")
const F=preload("res://tests/tactical_fixture.gd")
const DT: float=1.0/30.0
const BODY_LIMIT_US: int=12000000
const SEED080: int=80080
var checks: int=0
var failures: int=0
var began: int=0
var incomplete: bool=false
var physical_issues: Array=[]
var shot_times: Dictionary={}
var event_seq: int=0
var observations: Array=[]

static func initial_config080(data: Dictionary) -> Dictionary:
	return {"player":[Lab.entry(data,"brasswind_motor_galleon"),Lab.entry(data,"tideledger_coaster"),Lab.entry(data,"fourport_packet")],"enemy":[Lab.entry(data,"gale_cutter")],"formation":"closing"}

static func by_type080(st: Dictionary,type_id: String) -> Dictionary:
	for ship: Dictionary in st.ships:
		if str(ship.type)==type_id:return ship
	return {}

static func apply_opening080(st: Dictionary) -> void:
	# Declared off-beam practice opening, before ownership transfer only.
	var positions: Dictionary={"brasswind_motor_galleon":Vector2(1010,850),"tideledger_coaster":Vector2(1210,1010),"fourport_packet":Vector2(1210,850),"gale_cutter":Vector2(1210,590)}
	for ship: Dictionary in st.ships:
		var p: Vector2=positions[str(ship.type)]
		ship.x=p.x;ship.y=p.y;ship.angle=PI/2.0 if ship.team=="enemy" else 0.0
		ship.turretAngle=ship.angle
		st.tactical.home[str(ship.id)]={"x":p.x,"y":p.y}
	st.autoBoard=false
	var guard: Dictionary=by_type080(st,"tideledger_coaster")
	var protected: Dictionary=by_type080(st,"fourport_packet")
	B.issue_order(st,[str(protected.id)],"hold")
	B.set_tactical_options(st,[str(guard.id)],{"leash":320.0,"formation":"line"})
	B.issue_order(st,[str(guard.id)],"escort",{"shipId":str(protected.id)})

static func witness080(st: Dictionary) -> Dictionary:
	var guard: Dictionary=by_type080(st,"tideledger_coaster")
	var heavy: Dictionary=by_type080(st,"brasswind_motor_galleon")
	var protected: Dictionary=by_type080(st,"fourport_packet")
	var light: Dictionary=by_type080(st,"gale_cutter")
	return {"stage":0,"since":0.0,"guard":str(guard.id),"heavy":str(heavy.id),"protected":str(protected.id),"light":str(light.id),"guard_start":F.pos(guard),"heavy_heading":float(heavy.angle),"sampled":{},"first_shot":-1.0,"break_at":-1.0,"break_origin":Vector2.ZERO,"break_travel":0.0,"renewed_shot":-1.0,"intercept":false,"leashed":true,"heavy_hit":false,"light_hit":false,"hold_shots":0,"hold_drift":0.0,"hold_seen":false,"move_seen":false,"move_arrived":false,"maneuver_fire":false,"withdraw_seen":false,"withdraw_progress":0.0,"queued":true,"idle":{},"max_idle":0.0,"phases":[],"commands":[]}

static func observe080(st: Dictionary,events: Array,w: Dictionary) -> void:
	var light: Dictionary=F.find(st,w.light);var guard: Dictionary=F.find(st,w.guard)
	var heavy: Dictionary=F.find(st,w.heavy);var protected: Dictionary=F.find(st,w.protected)
	var chosen: Dictionary=st.tactical.intents.get(w.light,{})
	var phase: String=str(chosen.get("phase",""))
	if not phase.is_empty() and (w.phases.is_empty() or str(w.phases[-1].phase)!=phase):w.phases.append({"phase":phase,"at":float(st.time)})
	if w.stage==0:
		w.leashed=bool(w.leashed) and F.pos(guard).distance_to(F.pos(protected))<=320.01
		var toward: Vector2=(F.pos(light)-F.pos(protected)).normalized()
		w.intercept=bool(w.intercept) or (str(st.tactical.intents.get(w.guard,{}).get("targetId",""))==w.light and (F.pos(guard)-F.pos(protected)).dot(toward)>20.0 and F.point_segment(F.pos(guard),F.pos(protected),F.pos(light))+15.0<F.point_segment(w.guard_start,F.pos(protected),F.pos(light)))
	if float(w.first_shot)>=0.0 and float(w.break_at)<0.0 and phase in ["breakaway","turn-away","regroup"]:
		w.break_at=float(st.time);w.break_origin=F.pos(light)
	if float(w.break_at)>=0.0 and float(w.renewed_shot)<0.0:w.break_travel=maxf(float(w.break_travel),F.pos(light).distance_to(w.break_origin))
	for event: Dictionary in events:
		if str(event.kind)=="hit":
			if str(event.sourceId)==w.heavy and str(event.targetId)==w.light:w.heavy_hit=true
			if str(event.sourceId)==w.light and str(event.targetId) in [w.heavy,w.guard,w.protected]:w.light_hit=true
		if str(event.kind)!="fire":continue
		if str(event.sourceId)==w.light:
			if float(w.first_shot)<0.0:w.first_shot=float(event.time)
			elif float(w.break_at)>=0.0 and float(w.break_travel)>=60.0 and phase not in ["breakaway","turn-away","regroup"]:w.renewed_shot=float(event.time)
		if str(event.sourceId)==w.guard:
			if w.stage==1 and str(guard.order)=="hold":w.hold_shots+=1
			if w.stage>=2:w.maneuver_fire=true
	if w.stage==1:
		w.hold_drift=maxf(float(w.hold_drift),F.pos(guard).distance_to(w.hold_point))
		w.hold_seen=bool(w.hold_seen) or (str(guard.order)=="hold" and str(st.tactical.intents.get(w.guard,{}).get("phase",""))=="hold" and int(guard.orderRevision)>int(w.prior_revision))
	if w.stage==2:
		w.move_seen=bool(w.move_seen) or (str(guard.order)=="move" and int(st.tactical.intents.get(w.guard,{}).get("orderRevision",-1))==int(guard.orderRevision))
		w.move_arrived=bool(w.move_arrived) or (bool(w.move_seen) and F.pos(guard).distance_to(w.move_point)<=12.0)
	if w.stage==3:
		w.withdraw_seen=bool(w.withdraw_seen) or str(st.tactical.intents.get(w.guard,{}).get("phase",""))=="withdraw"
		w.withdraw_progress=maxf(float(w.withdraw_progress),F.pos(guard).distance_to(w.withdraw_origin))
	for ship: Dictionary in st.ships:
		var id: String=str(ship.id);var offer: Dictionary=st.tactical.intents.get(id,{})
		if str(offer.get("scope",""))=="sampled-fleet-goal":w.sampled[id]=true
		var reasons: String=str(st.tactical.reasons.get(id,""))
		for reason: Variant in st.tactical.fireReasons.get(id,{}).values():reasons+=" "+str(reason)
		var at_hold: bool=str(ship.order)=="hold" and F.pos(ship).distance_to(Vector2(float(ship.orderTarget.get("x",ship.x)),float(ship.orderTarget.get("y",ship.y))))<=12.0
		var unresolved: bool=offer.is_empty() or "Waiting for current helm clearance" in reasons or "Waiting for a route" in reasons or "Braking for land" in reasons
		if F.live(ship) and not at_hold and unresolved and Vector2(ship.vx,ship.vy).length()<2.0:
			if not w.idle.has(id):w.idle[id]=float(st.time)
			w.max_idle=maxf(float(w.max_idle),float(st.time)-float(w.idle[id]))
		else:w.idle.erase(id)

static func command_milestones080(st: Dictionary,w: Dictionary) -> void:
	# Ordinary commands change the outcome after the observed autonomous cycle.
	var guard: Dictionary=F.find(st,w.guard)
	if st.result!=null:return
	if w.stage==0 and float(w.renewed_shot)>=0.0 and w.intercept and w.heavy_hit and w.light_hit:
		w.hold_point=F.pos(guard);w.prior_revision=int(guard.orderRevision)
		w.queued=bool(w.queued) and B.issue_order(st,[w.guard],"hold")
		w.stage=1;w.since=float(st.time);w.commands.append({"order":"hold","at":float(st.time)})
	elif w.stage==1 and float(st.time)-float(w.since)>=1.2 and w.hold_seen and int(w.hold_shots)>0:
		w.move_point=F.pos(guard)+Vector2(-110,-40)
		w.queued=bool(w.queued) and B.issue_order(st,[w.guard],"move",{"x":w.move_point.x,"y":w.move_point.y})
		w.stage=2;w.since=float(st.time);w.commands.append({"order":"move","at":float(st.time),"point":w.move_point})
	elif w.stage==2 and w.move_arrived:
		w.withdraw_origin=F.pos(guard);B.retreat(st)
		w.stage=3;w.since=float(st.time);w.commands.append({"order":"fleet withdraw","at":float(st.time)})

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL counterplay080: "+label)

func issue080(label: String) -> void:
	if not label in physical_issues and physical_issues.size()<8:physical_issues.append(label)

func audit080(before: Dictionary,after: Dictionary,events: Array) -> void:
	var costs: Dictionary={};var emitted: Dictionary={}
	for event: Dictionary in events:
		if int(event.seq)<=event_seq:issue080("event sequence duplicated or reordered")
		event_seq=int(event.seq)
		if str(event.kind)!="fire":continue
		var ship: Dictionary=F.find(after,str(event.sourceId));var target: Dictionary=F.find(after,str(event.targetId))
		var mounts: Array=after.tactical.mountsById051.get(str(event.sourceId),[])
		var index: int=int(event.mountIndex)
		if ship.is_empty() or target.is_empty() or index<0 or index>=mounts.size():issue080("unresolved emitting mount or hostile");continue
		var mount: Dictionary=mounts[index];var key: String=str(ship.id)+"/"+str(mount.id)
		if target.team==ship.team or str(event.mountId)!=str(mount.id) or emitted.has(key):issue080("invalid hostile/mount identity or duplicate shot")
		if shot_times.has(key) and float(event.time)-float(shot_times[key])+0.000001<1.0/float(mount.fireRate):issue080("shot repeated before nominal reload")
		if not is_equal_approx(B.mount_shot_time(ship,str(mount.id)),float(event.time)) or float(ship.weaponCooldowns[index])+0.000001<1.0/float(mount.fireRate):issue080("shot has no matching actual timestamp/reload")
		shot_times[key]=float(event.time);emitted[key]=true
		costs[str(ship.id)]=float(costs.get(str(ship.id),0.0))+float(mount.ammoCost)
	for ship: Dictionary in after.ships:
		var prior: Dictionary=F.find(before,str(ship.id))
		if float(ship.ammo)<0.0 or not is_equal_approx(float(prior.ammo)-float(ship.ammo),float(costs.get(str(ship.id),0.0))):issue080("whole ammunition debit differs from actual emitted mount costs")

func joined_step080(driver,before: Dictionary) -> Dictionary:
	var wanted: int=int(driver.telemetry().completedSteps)+1
	var events: Array=[];var view: Dictionary=driver.advance(DT,{},false)
	while int(driver.telemetry().completedSteps)<wanted and view.get("result")==null and Time.get_ticks_usec()-began<BODY_LIMIT_US:
		events.append_array(driver.take_events())
		await process_frame
		view=driver.advance(0.0,{},false) # Poll debt/commands; never add another step.
	events.append_array(driver.take_events())
	if int(driver.telemetry().completedSteps)!=wanted or not is_equal_approx(float(view.time),float(before.time)+DT):incomplete=true
	if not incomplete:audit080(before,view,events)
	return {"state":view,"events":events}

func complete_encounter080(data: Dictionary) -> void:
	var made: Dictionary=Lab.create(data,initial_config080(data),SEED080)
	check(bool(made.get("ok",false)),"canonical Lab factory accepts all stock fittings and physical crew")
	if not bool(made.get("ok",false)):return
	apply_opening080(made.battle)
	var owners: Array=made.battle.ships.duplicate()
	var w: Dictionary=witness080(made.battle)
	var driver=Driver.new(made.battle)
	var view: Dictionary=driver.advance(0.0,{},true)
	while view.result==null and float(view.time)<30.0 and not incomplete:
		var frame: Dictionary=await joined_step080(driver,view)
		view=frame.state
		if incomplete:break
		observe080(view,frame.events,w);command_milestones080(view,w)
	var telemetry: Dictionary=driver.telemetry()
	var final: Dictionary=driver.retire()
	check(w.sampled.size()==4 and int(telemetry.workerThreadId)>0 and int(telemetry.workerThreadId)!=OS.get_thread_caller_id(),"actual detached authoritative worker publishes sampled-fleet-goal intents for all four boats")
	check(float(w.first_shot)>0.0 and float(w.break_at)>float(w.first_shot) and float(w.break_travel)>=60.0 and float(w.renewed_shot)>float(w.break_at),"real paid flank pass completes physical recovery before another paid pass")
	check(w.intercept and w.leashed,"escort actually interposes toward the light threat inside its finite leash")
	check(w.heavy_hit and w.light_hit,"heavy punishes the flanker and the flanker inflicts actual opposing damage")
	check(w.queued and w.hold_seen and int(w.hold_shots)>0 and float(w.hold_drift)<=45.0,"accepted Hold revision brakes at its station and still fires legally")
	check(w.move_seen and w.move_arrived and not w.maneuver_fire,"Move overrides screening, reaches its actual destination and suppresses fire")
	check(w.withdraw_seen and float(w.withdraw_progress)>60.0 and str(final.result)=="retreated","ordinary fleet withdrawal travels and reaches its real terminal outcome")
	check(float(w.max_idle)<3.0,"no unresolved stationary Engage/helm wait reaches the unchanged three-second stall boundary")
	var identities: bool=true
	for owner: Dictionary in owners:identities=identities and is_same(F.find(final,str(owner.id)),owner)
	check(identities and driver.telemetry().retired and not driver.telemetry().inFlight and T.Planner._tasks051.is_empty() and not T._battle_worker_owned051,"joined retirement preserves physical owners and releases all tracked tactical children")
	observations.append({"case":"complete-stock-encounter","witness":w,"time":final.time,"result":final.result,"telemetry":telemetry})

func blocked_and_hold080(data: Dictionary) -> void:
	if incomplete:return
	var made: Dictionary=Lab.create(data,{"player":[Lab.entry(data,"bilge_punt",2)],"enemy":[Lab.entry(data,"bilge_punt")],"formation":"closing"},SEED080+1)
	check(bool(made.get("ok",false)),"tiny blocked-route/Hold contrast uses canonical hulls")
	if not bool(made.get("ok",false)):return
	var st: Dictionary=made.battle
	# Declared enclosed water pocket; no point, pose or store changes once active.
	st.islands=[F.rectangle(700,740,720,960),F.rectangle(880,740,900,960),F.rectangle(700,740,900,760),F.rectangle(700,940,900,960)]
	var trap: Dictionary=st.ships[0];var holder: Dictionary=st.ships[1];var target: Dictionary=st.ships[2]
	for pair: Array in [[trap,Vector2(800,850)],[holder,Vector2(1100,850)],[target,Vector2(1390,850)]]:
		pair[0].x=pair[1].x;pair[0].y=pair[1].y;pair[0].angle=0.0
		st.tactical.home[str(pair[0].id)]={"x":pair[1].x,"y":pair[1].y}
	holder.ammo=2.0;target.ammo=0.0;st.autoBoard=false
	B.issue_order(st,[str(trap.id)],"move",{"x":1030.0,"y":850.0})
	B.issue_order(st,[str(holder.id)],"hold");F.command(st,target,"hold")
	var trap_id: String=str(trap.id);var hold_id: String=str(holder.id)
	var driver=Driver.new(st);var view: Dictionary=driver.advance(0.0,{},true)
	var shots: int=0;var trap_shots: int=0;var stayed: bool=true;var drift: float=0.0;var sampled: bool=false;var dry_at: float=-1.0
	for tick in range(120):
		if incomplete or view.result!=null:break
		var frame: Dictionary=await joined_step080(driver,view);view=frame.state
		trap=F.find(view,trap_id);holder=F.find(view,hold_id)
		stayed=stayed and float(trap.x)>720.0 and float(trap.x)<880.0 and float(trap.y)>760.0 and float(trap.y)<940.0
		drift=maxf(drift,F.pos(holder).distance_to(Vector2(1100,850)))
		sampled=sampled or str(view.tactical.intents.get(hold_id,{}).get("scope",""))=="sampled-fleet-goal"
		for event: Dictionary in frame.events:
			if str(event.kind)=="fire" and str(event.sourceId)==hold_id:shots+=1
			if str(event.kind)=="fire" and str(event.sourceId)==trap_id:trap_shots+=1
		if float(holder.ammo)==0.0 and dry_at<0.0:dry_at=float(view.time)
	var final: Dictionary=driver.retire();holder=F.find(final,hold_id)
	check(stayed and trap_shots==0 and F.pos(F.find(final,trap_id)).distance_to(Vector2(1030,850))>100.0,"a genuinely enclosed route cannot grant wall-crossing or illegal fire")
	check(sampled and drift<=12.0 and shots==2 and float(holder.ammo)==0.0 and dry_at>0.0 and float(final.time)-dry_at>=1.0,"legitimate stationary Hold fires exactly its two carried rounds then remains dry")
	check(not driver.telemetry().inFlight and T.Planner._tasks051.is_empty() and not T._battle_worker_owned051,"contrast retires its own worker and children before completion")
	observations.append({"case":"blocked-route-versus-legal-hold","trapped":stayed,"hold_drift":drift,"hold_shots":shots,"dry_at":dry_at,"time":final.time})

func _initialize() -> void:call_deferred("run080")

func run080() -> void:
	# Process-local headless scheduling only; authoritative combat remains 30 Hz.
	if DisplayServer.get_name()=="headless":Engine.max_fps=0
	began=Time.get_ticks_usec()
	if DisplayServer.get_name()!="headless":check(false,"headless native fixture only; capture uses static APIs")
	else:
		var data: Dictionary=F.world()
		await complete_encounter080(data)
		shot_times.clear();event_seq=0
		await blocked_and_hold080(data)
	check(physical_issues.is_empty(),"actual ordered fire events retain mount/reload/finite ammunition accounting")
	check(not incomplete and Time.get_ticks_usec()-began<BODY_LIMIT_US,"one bounded native body completes below twelve seconds; an incomplete cycle fails")
	print(JSON.stringify(F.encode({"fixture":"counterplay080","checks":checks,"failures":failures,"complete":not incomplete and failures==0,"elapsed_us":Time.get_ticks_usec()-began,"physical_issues":physical_issues,"observations":observations,"limits":"Source until Root executes. One declared canonical stock encounter and one contrast; no campaign/FPS/rendered motion/listening/whole-game quality acceptance."})))
	print("Counterplay080: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
