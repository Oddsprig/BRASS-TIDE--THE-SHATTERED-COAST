extends SceneTree
## Real Driver/WorkerThreadPool integration. Root alone executes this fixture.
## Raw B.update reference finishes before driver acquisition; no shared globals
## are inspected while authoritative or tactical work can still own them.
const B=preload("res://scripts/battle.gd")
const D=preload("res://scripts/damage.gd")
const T=preload("res://scripts/tactical_runtime.gd")
const Driver=preload("res://scripts/battle_driver051.gd")
const Main=preload("res://scripts/main.gd")
const Lab=preload("res://scripts/fleet_lab.gd")
const PressureView=preload("res://scripts/combat_pressure_view044.gd")
const STEP: float=1.0/30.0
const SPEC={"id":"worker-proof051","name":"Worker proof","hp":1000.0,"armor":0.0,"crewMin":2,"crewOptimal":12,"crewMax":30,"size":16,"speed":50.0,"turn":2.0,"pumps":1,"weapon":"gun","damage":20.0,"fireRate":2.0,"range":1500.0,"deploymentPoints":20,"weaponMounts":[{"id":"proof-ray","kind":"gun","damage":20.0,"fireRate":2.0,"range":1500.0,"speed":5000.0,"ammoCost":2,"x":8.0,"y":0.0,"arc":6.28318530718,"angle":0.0}]}
var checks: int=0
var failures: int=0
var began_us: int=0
var observations: Array=[]

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("WORKER BATTLE051: "+message)

func _initialize() -> void:call_deferred("run")

func arena(per_side: int=1) -> Dictionary:
	var players: Array=[];var enemies: Array=[]
	for index in range(per_side):
		players.append(D.create_ship(SPEC,{"uid":"worker-player-%d"%index}))
		var target_spec: Dictionary=SPEC.duplicate(true);target_spec.speed=0.0
		enemies.append(D.create_ship(target_spec,{"uid":"worker-enemy-%d"%index,"ammo":0.0}))
	var st: Dictionary=B.create({"fleet":players,"enemyFleet":enemies,"seed":51051,"islands":[]})
	st.autoBoard=false
	for index in range(st.ships.size()):
		var ship: Dictionary=st.ships[index]
		ship.x=500.0 if ship.team=="player" else 800.0
		ship.y=750.0+float(index%per_side)*120.0
		ship.angle=0.0 if ship.team=="player" else PI;ship.turretAngle=ship.angle
		st.tactical.home[str(ship.id)]={"x":ship.x,"y":ship.y}
	st.ships[0].water=100.0;st.ships[0].breaches=[{"area":3.0,"section":"waterline"}]
	B.set_autopilot(st,false if per_side==1 else true)
	return st

func input_for(st: Dictionary) -> Dictionary:
	return {"manual":true,"forward":true,"fire":true,"aimX":st.ships[1].x,"aimY":st.ships[1].y}

func joined_steps(driver,input: Dictionary,count: int,events: Array) -> Dictionary:
	var view: Dictionary=driver.advance(0.0,input,true)
	for index in range(count):
		var wanted: int=int(driver.telemetry().completedSteps)+1
		view=driver.advance(STEP,input,false)
		var deadline: int=Time.get_ticks_usec()+2000000
		while int(driver.telemetry().completedSteps)<wanted and Time.get_ticks_usec()<deadline and Time.get_ticks_usec()-began_us<20000000:
			view=driver.advance(0.0,input,true) # Only polls; cannot add physics debt.
			events.append_array(driver.take_events())
			await process_frame
		check(int(driver.telemetry().completedSteps)==wanted,"one real completed step advances exactly1/30; no callback relabelling")
		if int(driver.telemetry().completedSteps)!=wanted:break
		events.append_array(driver.take_events())
	return view

func copied_publication(value: Variant,depth: int=0) -> bool:
	if depth>40:return false
	if value is Object or value is Callable or value is Signal or typeof(value)==TYPE_RID:return false
	if value is Dictionary:
		for key in value:
			if key in ["_battleDriver051","_battleMirror051"]:continue # Main-only wrapper.
			if not copied_publication(key,depth+1) or not copied_publication(value[key],depth+1):return false
	elif value is Array:
		for item in value:
			if not copied_publication(item,depth+1):return false
	return true

func manual_reference_and_resources() -> void:
	# Complete all synchronous numerical work before any Driver owns the globals.
	var reference: Dictionary=arena()
	var input: Dictionary=input_for(reference)
	var reference_events: Array=[]
	for index in range(30):B.update(reference,STEP,input);reference_events.append_array(B.pop_events(reference))
	T.retire_planning051(reference);T.drain_planning051()
	var initial: Dictionary=arena()
	var original_owner: Dictionary=initial.ships[0]
	var starting_ammo: float=float(original_owner.ammo)
	var starting_supplies: float=float(original_owner.supplies)
	var driver=Driver.new(initial)
	var mirror: Dictionary=driver.advance(0.0,input,true)
	check(copied_publication(mirror),"initial display has plain copied data, no RNG/phase/task/goal objects")
	check(not is_same(mirror.ships[0],original_owner) and not is_same(mirror.ships[0].spec,original_owner.spec),"nested display hull/spec are detached from original campaign owner")
	var old_ship: Dictionary=mirror.ships[0]
	var old_target: Dictionary=mirror.ships[1]
	var original_target_hp: float=float(old_target.hp)
	# Deliberately mutate only Main-owned copies after transfer. Neither change
	# may alter worker accounting; retirement must restore the canonical owner.
	original_owner.ammo=9999.0;old_ship.ammo=-9.0;old_ship.spec.speed=9999.0
	var events: Array=[]
	mirror=await joined_steps(driver,input,30,events)
	var telemetry: Dictionary=driver.telemetry()
	check(int(telemetry.workerThreadId)>0 and int(telemetry.workerThreadId)!=OS.get_thread_caller_id(),"actual authoritative job thread differs from Main")
	check(int(telemetry.workerStepHz)==30 and int(telemetry.completedSteps)==30 and is_equal_approx(float(telemetry.stateTime),1.0),"real30Hz completion count matches authoritative simulation clock")
	check(old_ship.ammo==-9.0 and old_target.hp==original_target_hp,"later publications never mutate a retained nested Main snapshot")
	check(copied_publication(mirror) and not mirror.has("rng") and not mirror.tactical.has("workers051"),"published running state contains no private worker ownership handles")
	var final: Dictionary=driver.retire()
	events.append_array(driver.take_events())
	check(driver.take_events().is_empty(),"published events drain exactly once including retirement")
	check(is_same(final.ships[0],original_owner),"joined final state restores original campaign hull identity")
	for index in range(2):
		for key in ["x","y","angle","vx","vy","hp","crew","water","engine","fuel","ammo","supplies"]:
			check(absf(float(final.ships[index][key])-float(reference.ships[index][key]))<0.00001,"manual1/30 worker agrees with synchronous reference: hull%d/%s"%[index,key])
	var fires: Array=events.filter(func(event):return event.kind=="fire" and str(event.sourceId)==str(final.ships[0].id))
	var hits: Array=events.filter(func(event):return event.kind=="hit" and str(event.targetId)==str(final.ships[1].id))
	check(not fires.is_empty() and not hits.is_empty() and float(final.ships[1].hp)<1000.0,"actual fast emitted rays hit the current hull crossed within one30Hz step")
	check(is_equal_approx(starting_ammo-float(final.ships[0].ammo),2.0*fires.size()),"real emitted shots debit exact whole rounds after display/original-copy mutation")
	check(float(final.ships[0].fuel)<60.0 and float(final.ships[0].supplies)<starting_supplies and D.sum_areas(final.ships[0])<3.0,"worker performs real motion/flood fuel and funded breach repair")
	check(events==reference_events,"seeded actual worker fire/hit stream agrees with pre-acquisition synchronous reference")
	var last_sequence: int=0
	for event in events:
		check(int(event.seq)>last_sequence,"events remain strictly ordered across publications")
		last_sequence=int(event.seq)
	var before_steps: int=int(driver.telemetry().completedSteps)
	var before_time: float=float(final.time)
	for index in range(4):driver.advance(1.0,input,false)
	check(not driver.queue_command("autopilot",{"enabled":true}) and int(driver.telemetry().completedSteps)==before_steps and float(driver.telemetry().stateTime)==before_time,"retired driver rejects commands and never starts another job")
	check(driver.telemetry().retired and not driver.telemetry().inFlight and T.Planner._tasks051.is_empty(),"retirement joins authoritative and tactical child work before releasing state")
	observations.append({"case":"manual-reference","telemetry":telemetry,"retired":driver.telemetry(),"fireEvents":fires.size(),"hitEvents":hits.size(),"ammo":final.ships[0].ammo,"supplies":final.ships[0].supplies})

func commands_pause_and_child_cleanup() -> void:
	# Actual Lab factory supplies canonical installed engine/pumps/repair records.
	# A legacy numerical boat cannot meaningfully accept equipment priority.
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var made: Dictionary=Lab.create(world,{"player":[Lab.entry(world,"tin_skiff",2)],"enemy":[Lab.entry(world,"tin_skiff",2)],"formation":"closing"},51052)
	check(bool(made.get("ok",false)),"public Lab factory admits the canonical command/priority fixture")
	if not bool(made.get("ok",false)):return
	var initial: Dictionary=made.battle
	var driver=Driver.new(initial)
	var mirror: Dictionary=driver.advance(0.0,{},true)
	# Retain and edit only the canonical Main copy, including nested equipment.
	# Later native-copy publications must neither borrow it nor update it in place.
	var retained_ship: Dictionary=mirror.ships[0]
	for item: Dictionary in retained_ship.moduleCondition.items.values():
		if str(item.location)=="engine":item.hp=0.0;item.status="disabled"
	retained_ship.moduleCondition.legacyEngineSynced=0.0
	retained_ship.engine=0.0;retained_ship.hp=-1.0;retained_ship.ammo=-1.0
	var retained_value: Dictionary=retained_ship.duplicate(true)
	var target: Dictionary={"x":650.0,"y":750.0}
	check(B.issue_order(mirror,[mirror.playerId],"move",target),"public Battle command proxy admits detached queued order")
	check(driver.queue_command("player_command",{"ids":[mirror.playerId],"command":"rally","target":target}),"actual compound BattleCommands047 rally is queued for worker validation")
	check(driver.queue_command("crew_policy",{"ids":[mirror.playerId],"policy":"bail"}),"actual crew policy is queued for worker validation")
	check(driver.queue_command("repair_priority",{"ids":[mirror.playerId],"priority":"engine"}),"actual canonical equipment priority is queued for worker validation")
	target.x=2200.0
	check(driver.queue_command("autopilot",{"enabled":true}) and driver.queue_command("autopilot",{"enabled":false}),"opposite commands are admitted in FIFO order")
	var deadline: int=Time.get_ticks_usec()+2000000
	while int(driver.telemetry().get("lastCommandSequence",0))<6 and Time.get_ticks_usec()<deadline:
		mirror=driver.advance(0.0,{},true)
		await process_frame
	check(int(driver.telemetry().lastCommandSequence)==6 and not mirror.autopilot,"worker validates all queued commands in their actual FIFO order")
	var receipts: Array=driver.telemetry().get("commandResults",[])
	check(receipts.size()==6,"actual paused worker returns all six command validation receipts")
	for index in range(receipts.size()):check(int(receipts[index].sequence)==index+1 and bool(receipts[index].ok),"paused command receipt is accepted in exact FIFO order")
	check(mirror.ships[0].order=="move" and is_equal_approx(float(mirror.ships[0].orderTarget.x),650.0),"queued nested target is copied at admission, not borrowed until execution")
	check(is_equal_approx(float(mirror.tactical.options.byId[str(mirror.playerId)].rally.x),650.0),"real BattleCommands047 compound rally applies its tactical options as well as the order")
	check(mirror.ships[0].policy=="bail" and mirror.ships[0].moduleCondition.repairPriority=="engine","paused command publication exposes worker-validated crew policy and canonical repair priority")
	check(float(mirror.time)==0.0 and int(driver.telemetry().completedSteps)==0,"paused command-only publication performs no numerical step")
	var events: Array=[]
	mirror=await joined_steps(driver,{},6,events)
	check(int(mirror.tactical.counters.decisions)>0,"factory-created SIDE jobs actually publish sampled decisions through real joins")
	var current: Dictionary=mirror.ships[0]
	var id: String=str(current.id)
	var flow: Dictionary=mirror.tactical.damageStatusById051[id]
	var status: Dictionary=B.tactical_status(mirror,id)
	var mounts: Array=B._combat_mounts(mirror,current)
	check(current.hp>0.0 and current.ammo>=0.0 and current.engine>0.0 and flow==D.get_status(current),"running canonical hull/HP/ammo/engine and HUD status are coherent after edits to a retained display")
	check(D.EquipmentDamage.Core.inspect_installed(current.moduleCondition).ok and mounts==B._mounts(current) and status.mounts==mounts,"current installed condition, combat mounts and tactical HUD mounts agree without authoritative cache access")
	check(not PressureView.readiness(current,flow).has("Damage control unavailable") and not mounts.is_empty() and PressureView.weapon_state(current,mounts[0],0,flow,"")!="Weapon status unavailable","actual HUD readers accept the running canonical payload")
	check(driver.presentation_poses().current[id]=={"x":current.x,"y":current.y,"angle":current.angle,"turretAngle":current.turretAngle},"interpolation's current pose belongs to the same published hull state")
	check(copied_publication(mirror) and not mirror.has("_damageOwned051") and not mirror.tactical.has("damageCache") and not mirror.tactical.has("goals051") and mirror.tactical.mountCache[id].keys()==["mounts"],"canonical display publishes plain HUD data without private damage/goal/source caches")
	check(retained_ship==retained_value and not is_same(current.moduleCondition,retained_ship.moduleCondition),"later worker jobs leave the entire retained canonical hull and nested condition unchanged")
	var held_time: float=float(mirror.time)
	var held_steps: int=int(driver.telemetry().completedSteps)
	for index in range(8):mirror=driver.advance(0.5,{},true);await process_frame
	check(float(mirror.time)==held_time and int(driver.telemetry().completedSteps)==held_steps,"pause stops new worker physics despite continued presentation polling")
	# Submit another real step then retire immediately, exercising the explicit
	# owned join path whether the scheduler has already finished it or not.
	driver.advance(STEP,{},false)
	var final: Dictionary=driver.retire()
	check(driver.telemetry().retired and not driver.telemetry().inFlight and T.Planner._tasks051.is_empty(),"immediate retirement drains authoritative work and actual sampled tactical children")
	check(not T._battle_worker_owned051,"retirement releases the global tactical owner only after joining")
	check(is_equal_approx(float(final.time),float(driver.telemetry().completedSteps)*STEP),"retirement returns the final joined canonical time")
	check(D.EquipmentDamage.Records.snapshot(final.ships[0]).ok and final.ships[0].has("baseSpec") and final.ships[0].has("loadout"),"retirement retains complete canonical equipment and refit data for campaign accounting")
	observations.append({"case":"commands-pause-children","queuedCommandReceipts":receipts,"telemetry":driver.telemetry(),"finalTime":final.time})

func terminal_result() -> void:
	var initial: Dictionary=arena()
	# The public mount speed limit is5000, or166.7 units per30Hz step.
	# A100-unit gap keeps hulls separate and lets the real shot sweep the target.
	initial.ships[1].x=initial.ships[0].x+100.0
	initial.tactical.home[str(initial.ships[1].id)]={"x":initial.ships[1].x,"y":initial.ships[1].y}
	initial.ships[1].hp=1.0;initial.ships[1].crew=0.0
	var starting_ammo: float=float(initial.ships[0].ammo)
	var driver=Driver.new(initial)
	var events: Array=[]
	var mirror: Dictionary=await joined_steps(driver,input_for(initial),1,events)
	check(mirror.result=="won" and mirror.ships[1].sunk and mirror.wrecks.size()==1,"actual worker final shot publishes victory, sunk hull and cosmetic wreck")
	var final: Dictionary=driver.retire();events.append_array(driver.take_events())
	var fires: Array=events.filter(func(event):return event.kind=="fire" and str(event.sourceId)==str(final.ships[0].id))
	var hits: Array=events.filter(func(event):return event.kind=="hit" and str(event.targetId)==str(final.ships[1].id))
	check(fires.size()==1 and hits.size()==1 and is_equal_approx(starting_ammo-float(final.ships[0].ammo),2.0),"terminal swept shot emits once, hits the separate current target and debits exactly two rounds")
	var snapshot: Dictionary={"ships":final.ships.duplicate(true),"shots":final.projectiles.duplicate(true),"time":final.time,"result":final.result}
	B.advance_visuals(final,0.1)
	check(final.time==snapshot.time and final.result==snapshot.result and final.ships==snapshot.ships and final.projectiles==snapshot.shots,"retired result permits cosmetic tail without numerical motion/crew/stores work")
	check(events.any(func(event):return event.kind=="sink") and T.Planner._tasks051.is_empty(),"final result feedback drains with all tactical children joined")
	check(events.filter(func(event):return event.kind=="sink").size()==1 and driver.take_events().is_empty(),"terminal sink feedback drains exactly once through retirement")
	observations.append({"case":"terminal","telemetry":driver.telemetry(),"result":final.result})

func actual_main_lab_entry() -> void:
	# Same real Main/Lab entry as the rendered observer. Root's synthetic APPDATA,
	# Dummy/muted audio and owned background lane apply to the entire fixture.
	var game=Main.new();root.add_child(game);await process_frame
	game.set_process(false);game.set_physics_process(false)
	game.lab_config={"player":[Lab.entry(game.data,"tin_skiff",2)],"enemy":[Lab.entry(game.data,"tin_skiff",2)]}
	game.start_lab()
	var driver=game.battle_driver051
	check(game.mode=="battle" and game.lab_active and driver!=null and game.battle.get("_battleMirror051",false),"public Main.start_lab attaches the real driver and displays its detached mirror")
	if driver!=null:
		game.poll_battle051(STEP,false)
		var deadline: int=Time.get_ticks_usec()+2000000
		while int(driver.telemetry().completedSteps)<1 and Time.get_ticks_usec()<deadline:
			game.poll_battle051(0.0,true)
			await process_frame
		check(int(driver.telemetry().completedSteps)==1 and int(driver.telemetry().workerThreadId)!=OS.get_thread_caller_id(),"actual Main render-poll path completes worker physics away from Main")
		check(is_equal_approx(float(game.battle.time),STEP),"Main displays authoritative30Hz time without its old60Hz Battle.update path")
		game.return_to_title()
		check(game.battle_driver051==null and driver.telemetry().retired and not driver.telemetry().inFlight and T.Planner._tasks051.is_empty(),"actual Main title transition retires its driver and tactical children")
		observations.append({"case":"actual-main-lab","telemetry":driver.telemetry()})
	else:game.return_to_title()
	game.queue_free();await process_frame

func run() -> void:
	began_us=Time.get_ticks_usec()
	await manual_reference_and_resources()
	await commands_pause_and_child_cleanup()
	await terminal_result()
	await actual_main_lab_entry()
	print("WORKER BATTLE051: %d checks, %d failures; observations=%s"%[checks,failures,JSON.stringify(observations)])
	quit(0 if failures==0 else 1)
