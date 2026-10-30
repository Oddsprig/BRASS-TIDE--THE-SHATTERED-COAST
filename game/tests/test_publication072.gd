extends "res://tests/test_worker_battle051.gd"
## Controlled publication regression, not earned voyage or performance evidence.
## Reuse the existing worker fixture/checks and its actual canonical Lab factory.
## Root alone runs this bounded native body through the shared test lane.

func publication_arena(world: Dictionary) -> Dictionary:
	var made: Dictionary=Lab.create(world,{"player":[Lab.entry(world,"tin_skiff")],"enemy":[Lab.entry(world,"tin_skiff")],"formation":"closing"},72072)
	check(bool(made.get("ok",false)),"canonical publication fixture is admitted")
	if not bool(made.get("ok",false)):return {}
	var st: Dictionary=made.battle
	st.autoBoard=false
	B.set_autopilot(st,false)
	st.ships[0].hp=float(st.ships[0].maxHp)*0.75
	st.ships[0].water=float(st.ships[0].capacity)*0.25
	st.ships[0].breaches=[{"area":3.0,"section":"waterline"}]
	return st

func hull_pose(ship: Dictionary) -> Dictionary:
	return {"x":ship.x,"y":ship.y,"angle":ship.angle,"turretAngle":ship.turretAngle}

func joined_publication(driver,input: Dictionary,steps: int) -> Dictionary:
	var wanted_jobs: int=int(driver.telemetry().jobsCompleted)+1
	var wanted_steps: int=int(driver.telemetry().completedSteps)+steps
	var view: Dictionary=driver.advance(float(steps)*STEP,input,steps==0)
	var deadline: int=mini(Time.get_ticks_usec()+1000000,began_us+4000000)
	while int(driver.telemetry().jobsCompleted)<wanted_jobs and Time.get_ticks_usec()<deadline:
		await process_frame
		view=driver.advance(0.0,input,true)
	check(int(driver.telemetry().jobsCompleted)==wanted_jobs,"one requested batch produces one joined publication")
	check(int(driver.telemetry().completedSteps)==wanted_steps and int(driver.telemetry().stepsInJob)==steps,"joined batch completes its exact requested physics steps")
	return view

func run() -> void:
	began_us=Time.get_ticks_usec()
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	# Finish the synchronous reference before Driver claims the shared runtime.
	var reference: Dictionary=publication_arena(world)
	if reference.is_empty():quit(1);return
	var input: Dictionary=input_for(reference)
	input.fire=false;input.right=true
	D.set_policy(reference.ships[0],"bail")
	D.set_repair_priority(reference.ships[0],"engine")
	var start_pose: Dictionary=hull_pose(reference.ships[0])
	var one_pose: Dictionary={}
	var last_before: Dictionary={}
	for index in range(4):
		if index==3:last_before=hull_pose(reference.ships[0])
		B.update(reference,STEP,input)
		if index==0:one_pose=hull_pose(reference.ships[0])
	var four_pose: Dictionary=hull_pose(reference.ships[0])
	check(start_pose!=one_pose and one_pose!=last_before and last_before!=four_pose,"independent reference has distinct moving/turning poses at each tested boundary")
	T.retire_planning051(reference);T.drain_planning051();B._close_damage_owned051(reference)
	var initial: Dictionary=publication_arena(world)
	if initial.is_empty():quit(1);return
	var original: Dictionary=initial.ships[0]
	var driver=Driver.new(initial)
	var view: Dictionary=driver.advance(0.0,input,true)
	var id: String=str(view.playerId)
	check(driver.presentation_poses().previous[id]==start_pose and driver.presentation_poses().current[id]==start_pose,"initial display holds the actual pre-step pose")
	# Edit both Main-owned hulls after transfer, never authoritative state.
	original.engine=0.0
	for item: Dictionary in original.moduleCondition.items.values():
		if str(item.location)=="engine":item.hp=0.0;item.status="disabled"
	view.ships[0].engine=0.0;view.ships[0].spec.speed=9999.0
	for item: Dictionary in view.ships[0].moduleCondition.items.values():
		if str(item.location)=="engine":item.hp=0.0;item.status="disabled"
	check(driver.queue_command("crew_policy",{"ids":[id],"policy":"bail"}) and driver.queue_command("repair_priority",{"ids":[id],"priority":"engine"}),"ordinary policy/condition commands queue for the zero-step worker")
	view=await joined_publication(driver,input,0)
	check(int(driver.telemetry().lastCommandSequence)==2 and view.ships[0].policy=="bail" and view.ships[0].moduleCondition.repairPriority=="engine","zero-step publication contains current worker-validated policy and condition priority")
	check(float(view.time)==0.0 and view.ships[0].engine>0.0,"zero-step job neither advances the clock nor borrows edited campaign/display conditions")
	var retained_poses: Dictionary=driver.presentation_poses()
	check(retained_poses.previous[id]==start_pose and retained_poses.current[id]==start_pose,"command-only job publishes unchanged previous/current poses")
	check(not is_same(retained_poses.previous,retained_poses.current) and not is_same(retained_poses.previous[id],retained_poses.current[id]),"equal zero-step poses remain independent mutable display tables")
	var retained_ship: Dictionary=view.ships[0]
	var retained_flow: Dictionary=view.tactical.damageStatusById051[id]
	var retained_status: Dictionary=view.tactical.statusById051[id]
	retained_poses.previous[id].x=-123.0;retained_poses.current[id].y=-456.0
	retained_ship.engine=0.0
	for item: Dictionary in retained_ship.moduleCondition.items.values():
		if str(item.location)=="engine":item.hp=0.0;item.status="disabled"
	retained_flow.weaponFactors["display-only"]=-1.0
	retained_flow.events.append("display-only")
	retained_status.mounts[0].damage=-1.0
	var held_poses: Dictionary=retained_poses.duplicate(true)
	var held_ship: Dictionary=retained_ship.duplicate(true)
	var held_flow: Dictionary=retained_flow.duplicate(true)
	var held_status: Dictionary=retained_status.duplicate(true)
	view=await joined_publication(driver,input,1)
	check(driver.presentation_poses().previous[id]==start_pose and driver.presentation_poses().current[id]==one_pose,"one-step publication spans exactly the independent pre/post physics poses")
	view=await joined_publication(driver,input,3)
	check(driver.presentation_poses().previous[id]==last_before and driver.presentation_poses().current[id]==four_pose,"multistep publication uses the last executed step's pre/post poses")
	check(hull_pose(view.ships[0])==four_pose and is_equal_approx(float(view.time),4.0*STEP),"interpolation and display hull describe the same four completed 30Hz steps")
	check(retained_poses==held_poses and retained_ship==held_ship and retained_flow==held_flow and retained_status==held_status,"later joined jobs leave all edited retained poses/hull/condition/HUD branches unchanged")
	check(not is_same(view.ships[0].moduleCondition,retained_ship.moduleCondition) and not is_same(driver.presentation_poses().current[id],retained_poses.current[id]),"new publication owns detached condition and pose rows")
	var current: Dictionary=view.ships[0]
	var flow: Dictionary=view.tactical.damageStatusById051[id]
	var mounts: Array=B._combat_mounts(view,current)
	check(copied_publication(view) and not view.has("_damageOwned051") and not view.tactical.has("damageCache"),"joined display exposes plain data without live owner/cache handles")
	check(D.EquipmentDamage.Core.inspect_installed(current.moduleCondition).ok and current.engine>0.0 and flow==D.get_status(current),"current canonical condition and HUD flow agree despite edits to old owners")
	check(mounts==B._mounts(current) and view.tactical.statusById051[id].mounts==mounts and mounts[0].damage>0.0,"current physical mounts and HUD mounts remain coherent and unpoisoned")
	check(float(current.supplies)<float(initial.ships[0].supplies) and D.sum_areas(current)<3.0,"controlled damaged fixture still spends actual supplies on repair")
	var final: Dictionary=driver.retire()
	check(is_same(final.ships[0],original) and D.EquipmentDamage.Core.inspect_installed(original.moduleCondition).ok and original.engine>0.0,"joined retirement restores the campaign owner with current valid condition")
	check(driver.presentation_poses().previous[id]==four_pose and driver.presentation_poses().current[id]==four_pose,"zero-step retirement preserves the final pose in independent display tables")
	check(driver.telemetry().retired and not driver.telemetry().inFlight and T.Planner._tasks051.is_empty(),"retirement joins all authoritative and tactical work")
	var elapsed_us: int=Time.get_ticks_usec()-began_us
	check(elapsed_us<5000000,"focused native publication body stays below five seconds")
	print("PUBLICATION072: %d checks, %d failures; bodyUs=%d"%[checks,failures,elapsed_us])
	quit(0 if failures==0 else 1)
