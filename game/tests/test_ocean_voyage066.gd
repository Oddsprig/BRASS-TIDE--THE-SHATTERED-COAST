extends SceneTree
## SOURCE CANDIDATE, NOT RUN. Root owns the shared native lane and55s process cap.
## One Main/Core, real finite treasury advance/purchases, physical patrol/course/
## pursuit, save/refusal and worker battle withdrawal. The final flooding branch
## is DECLARED controlled damage to an existing boat, not an earned combat win.
const Main=preload("res://scripts/main.gd")
const DIAGNOSTIC_LIMIT: int=48
var main
var c
var started: int=0
var checks: int=0
var failures: int=0
var finished: bool=false
var contact_ready: bool=false
var invoices: Array=[]
var phase: String="initialize"
var diagnostics: Array=[]
var diagnostic_count: int=0

func _initialize() -> void:
	started=Time.get_ticks_msec()
	create_timer(53.5).timeout.connect(_timeout)
	_run.call_deferred()

func check(value: bool,message: String) -> bool:
	checks+=1
	if not value:
		failures+=1
		diagnose({"kind":"assertion","message":message})
		print("FAIL ocean066: ",message," ",JSON.stringify(diagnostics[-1]))
	return value

func diagnose(event: Dictionary={}) -> void:
	var snapshot: Dictionary={"phase":phase,"elapsedMs":Time.get_ticks_msec()-started}
	if c!=null and not c.state.is_empty():
		snapshot["day"]=float(c.state.day)
		snapshot["world"]=c.state.get("world064",{}).duplicate(true)
		snapshot["position"]=c.state.position.duplicate(true)
		snapshot["pathPoints"]=c.state.path.size()
		snapshot["graceSeconds"]=float(c.state.encounterGrace)
		var contact: Dictionary=c.state.get("ocean066",{}).get("contact",{})
		var location: Dictionary=contact.get("location",{})
		var owner: Dictionary=c.fleet_owner("patrol-0")
		var projection: Dictionary=c.NavalAI._find_patrol(c.state,"patrol-0")
		snapshot["raider"]={"phase":str(contact.get("phase","unadmitted")),"gate":contact.get("gate",{}).duplicate(true),"world":location.get("world064",{}).duplicate(true),"position":location.get("position",{}).duplicate(true),"atPort":str(owner.get("atPort","")),"homePort":str(owner.get("homePort","")),"homePosition":{"x":projection.get("x",0.0),"y":projection.get("y",0.0)},"holding":bool(projection.get("holding",false))}
	if not event.is_empty():
		var detail: Dictionary={}
		for key in ["kind","patrol","ownerId","port","message"]:
			if event.has(key):detail[key]=str(event[key]).left(400)
		snapshot["event"]=detail
	if diagnostics.size()>=DIAGNOSTIC_LIMIT:diagnostics.pop_front()
	diagnostics.append(snapshot)
	if diagnostic_count<DIAGNOSTIC_LIMIT:print("OCEAN066_DIAG ",JSON.stringify(snapshot))
	diagnostic_count+=1

func enter_phase(label: String) -> void:
	phase=label
	diagnose()

func bounded() -> bool:
	return not finished and Time.get_ticks_msec()-started<52000

func _timeout() -> void:
	if finished:return
	check(false,"Whole fixture watchdog expired; queued/interrupted/timed-out work is not a pass")
	_finish.call_deferred()

func advance(dt: float,allow_contact: bool=false) -> bool:
	if not bounded():return check(false,"Whole fixture exceeded its bounded body")
	var before: float=float(c.state.day)
	c.step(dt)
	main.sync_economy()
	check(float(c.state.day)>=before and float(c.state.day)<=before+dt/45.0+0.000001,"One clipped campaign clock")
	check(c.Money.total(c.state)==int(c.state.coinSupply),"Finite global coins after normal daily publication")
	for event in c.pop_events():
		diagnose(event)
		if str(event.get("kind",""))=="ocean_encounter066":
			contact_ready=true
			if not allow_contact:return check(false,"Unexpected real offshore interception; not counted as arrival")
		elif str(event.get("kind","")) in ["encounter","defeat"]:return check(false,"Actual home encounter/loss interrupted this fixture")
	return true

func finish_course() -> bool:
	for _piece in range(240):
		if c.state.path.is_empty():return true
		if not advance(4.0):return false
	return check(false,"Real course did not finish within the bounded route loop")

func _run() -> void:
	if not check(OS.get_environment("GAME_TEST_ARTIFACTS").is_absolute_path(),"Root provides an isolated artifact/profile directory"):await _finish();return
	main=Main.new();main.qa_ocean066=true
	root.add_child.call_deferred(main)
	await main.ready # Includes the actual Main/Core/UI/nav constructor chain.
	main.set_process(false);main.set_physics_process(false);main.paused=true
	main.new_game(66066)
	c=main.core
	if not check(not c.state.is_empty(),"Actual Main new_game completed after ready"):await _finish();return
	enter_phase("finite_preparation")
	var legacy: Dictionary=JSON.parse_string(JSON.stringify(c.state));legacy.erase("ocean066")
	var dock: Dictionary=c.current_port()
	var upkeep: Dictionary=c.Economy.daily_upkeep(c.state.fleet)
	var food_units: int=maxi(0,ceili(float(upkeep.food)*18.0-float(c.state.cargo.food)))
	var fuel_units: int=8
	var budget: int=ceili(float(upkeep.wages)*18.0)+food_units*c.Economy.price(dock,"food","buy")+fuel_units*c.Economy.price(dock,"fuel","buy")
	var service: Dictionary=c.service_quote(c.state.fleet[0],dock)
	budget+=maxi(0,int(service.get("total",0)))
	var transfer: int=maxi(0,budget-int(c.state.coins))
	if not check(int(dock.governmentPurse)>=transfer,"Existing harbor treasury covers calculated fixture budget"):await _finish();return
	if transfer>0 and not check(c.Money.move(dock,"governmentPurse",c.state,"coins",transfer,"Declared066 integration budget advance",c.state.moneyLog),"Actual treasury transfer, unchanged coinSupply"):await _finish();return
	invoices.append({"budget":budget,"treasuryTransfer":transfer,"wageDays":18,"foodUnits":food_units,"fuelUnits":fuel_units})
	if food_units>0:
		var food: Dictionary=c.trade(str(dock.id),"food",food_units,"buy");invoices.append(food)
		if not check(food.get("ok",false),"Food purchased from actual stock"):await _finish();return
	var fuel: Dictionary=c.trade(str(dock.id),"fuel",fuel_units,"buy");invoices.append(fuel)
	if not check(fuel.get("ok",false),"Fuel purchased from actual stock"):await _finish();return
	var supplied: Dictionary=c.resupply_boat(str(c.state.fleet[0].uid),"full");invoices.append(supplied)
	c.use_reserves()
	if not check(float(c.state.fleet[0].fuel)>0 and float(c.state.cargo.food)>0,"Inspect actual readiness; full profile is not assumed to fill tanks"):await _finish();return
	# Leave the starting harbor immediately through its nearer ordinary approach.
	# Waiting there for another owner's next visit exposes an unrelated home contact.
	enter_phase("leave_home")
	var departure_gate: Dictionary={"regionId":"shatter_coast","approachId":"south"}
	if not check(c.approach_course064(str(departure_gate.regionId),str(departure_gate.approachId)).get("ok",false),"Ordinary player course out of home before waiting") or not finish_course():await _finish();return
	var departed: Dictionary=c.transition064(str(departure_gate.regionId),str(departure_gate.approachId))
	if not check(departed.get("ok",false),"Real player gate transfer before waiting: "+str(departed.get("message",""))):await _finish();return
	var ocean_gate: Dictionary=c.state.position.duplicate(true)
	enter_phase("clear_departure_gate")
	if not check(c.chart_course({"x":ocean_gate.x+160.0,"y":ocean_gate.y}).get("ok",false),"Sail clear offshore before waiting for actual NPC admission") or not finish_course():await _finish();return
	enter_phase("wait_npc_admission_offshore")
	for _piece in range(180):
		if not c.state.ocean066.contact.is_empty():break
		if not advance(4.0):await _finish();return
		if (_piece+1)%60==0:diagnose()
	if not check(not c.state.ocean066.contact.is_empty(),"One existing raider physically reached home and paid departure preparation"):await _finish();return
	var owned_uid: String=str(c.fleet_owner("patrol-0").boats[0].uid)
	var gate: Dictionary=c.state.ocean066.contact.gate.duplicate(true)
	if gate!=departure_gate:
		enter_phase("sail_ocean_to_admitted_gate")
		if not check(c.approach_course064(str(gate.regionId),str(gate.approachId)).get("ok",false),"Actual ocean course to the differently admitted gate") or not finish_course():await _finish();return
		ocean_gate=c.state.position.duplicate(true)
		enter_phase("clear_admitted_gate")
		if not check(c.chart_course({"x":ocean_gate.x+160.0,"y":ocean_gate.y}).get("ok",false),"Sail clear of admitted gate before waiting for a sighting") or not finish_course():await _finish();return
	enter_phase("wait_actual_offshore_sighting")
	# The player is already offshore: allow the NPC's full paid coastal departure,
	# rather than counting a former player home leg toward its travel time.
	for _piece in range(180):
		if not c.ocean_view066().contacts.is_empty():break
		# Once offshore, sample before a four-second sweep can pass first sighting.
		var offshore: bool=str(c.state.ocean066.contact.get("location",{}).get("world064",{}).get("layer",""))=="ocean"
		if not advance(0.1 if offshore else 4.0):await _finish();return
		if (_piece+1)%60==0:diagnose()
	if not check(not c.ocean_view066().contacts.is_empty(),"Actual offshore sighting of existing UID, no synthetic contact"):await _finish();return
	check(c.NavalAI.spatial_index(c.state).values().all(func(cell):return "patrol-0" not in cell),"Enrolled raider excluded from all HOME spatial cells")
	check(c.NavalAI.NavalOrders.observe(c.state,"patrol-0").is_empty(),"Dormant projection cannot observe HOME fleets")
	check(not c.LawOps.eligible(c,c.NavalAI._find_patrol(c.state,"patrol-0"),c.fleet_owner("patrol-0")),"No coastal service/customs contact for enrolled owner")
	enter_phase("investigate_actual_pursuit")
	var baseline_goal: Dictionary={"x":ocean_gate.x+400.0,"y":ocean_gate.y}
	if not check(c.chart_course(baseline_goal).get("ok",false),"Set one real onward voyage before investigating"):await _finish();return
	if not check(main.contact_action066("patrol-0","investigate").get("ok",false),"Investigate dated position through Main"):await _finish();return
	for _piece in range(120):
		if c.state.ocean066.memory.pursuits.has("patrol-0"):break
		if not advance(0.1):await _finish();return
	if not check(c.state.ocean066.memory.pursuits.has("patrol-0"),"Actual capable NPC pursuit, scheduled from detection"):await _finish();return
	enter_phase("avoid_and_save")
	var grace: float=float(c.state.encounterGrace)
	if not check(main.contact_action066("patrol-0","avoid").get("ok",false),"Avoid plots a physical course"):await _finish();return
	check(float(c.state.encounterGrace)==grace and c.state.ocean066.memory.pursuits.has("patrol-0"),"Avoid grants no grace and retains pursuit")
	check(not c.transition_blocker064().is_empty(),"Unsafe crossing remains blocked during actual pursuit")
	check(c.chart_course({"x":ocean_gate.x+350.0,"y":ocean_gate.y+50.0}).get("ok",false),"Ordinary course fleeing remains legal during pursuit")
	main.save_game(false)
	var saved: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	var memory_before: String=JSON.stringify(saved.ocean066)
	var loaded: Dictionary=c.restore(saved)
	if not check(loaded.get("ok",false),"Same Core restores actual ocean voyage: "+str(loaded.get("message",""))):await _finish();return
	check(JSON.stringify(c.state.ocean066)==memory_before,"Canonical raider location and dated A memory survive save/load")
	# Controlled valid empty-tank save variant, then reload the original voyage;
	# no production refuel command or extra fleet/account is introduced.
	enter_phase("empty_tank_restore")
	var no_fuel: Dictionary=saved.duplicate(true)
	for boat in no_fuel.fleet:boat["fuel"]=0.0
	for owner in no_fuel.fleetOwners:
		if str(owner.id)=="patrol-0":
			for boat in owner.boats:boat["fuel"]=0.0
	if not check(c.restore(no_fuel).get("ok",false),"Actual Core accepts finite empty tanks"):await _finish();return
	var stopped_player: Dictionary=c.state.position.duplicate(true)
	var stopped_npc: Dictionary=c.state.ocean066.contact.location.position.duplicate(true)
	var no_fuel_day: float=float(c.state.day)
	var capabilities: Array=c.OceanCampaign066.actors(c,c.state.ocean066)
	check(capabilities.all(func(a):return not a.canMove and float(a.baseSpeed)==0.0),"Both 066 actors refuse powered motion with all eligible tanks empty")
	if not advance(0.25):await _finish();return
	check(c.state.position==stopped_player and c.state.ocean066.contact.location.position==stopped_npc,"Actual Core step gives no empty-tank offshore drift")
	check(is_equal_approx(float(c.state.day)-no_fuel_day,0.25/45.0),"Empty tanks still advance the single clock exactly once")
	if not check(c.restore(saved).get("ok",false),"Reload original finite fixture after empty-tank branch"):await _finish();return
	enter_phase("copy_first_and_legacy_restore")
	var before: String=JSON.stringify(c.state)
	var malformed: Dictionary=saved.duplicate(true);malformed.ocean066.contact.ownerId="invented-owner"
	var rejected: Dictionary=c.restore(malformed)
	check(not rejected.get("ok",false) and JSON.stringify(c.state)==before and malformed.ocean066.contact.ownerId=="invented-owner","Malformed copy-first refusal leaves input and live state unchanged")
	check(c.restore(legacy).get("ok",false) and c.state.ocean066.contact.is_empty(),"Genuine old absent book defaults without creating a fleet")
	if not check(c.restore(saved).get("ok",false),"Restore active voyage into same Core after compatibility branch"):await _finish();return
	enter_phase("resume_and_actual_interception")
	if not check(main.resume_voyage066().get("ok",false),"Resume replots original same-chart voyage from current point"):await _finish();return
	if not check(main.contact_action066("patrol-0","investigate").get("ok",false),"Investigate again for actual interception"):await _finish();return
	for _piece in range(300):
		if contact_ready:break
		if not advance(0.25,true):await _finish();return
	if not check(contact_ready,"Swept physical interception reached before timeout"):await _finish();return
	var original_boat: Dictionary=c.fleet_owner("patrol-0").boats[0]
	enter_phase("physical_battle_withdrawal")
	var begun: Dictionary=main.contact_action066("patrol-0","engage")
	if not check(begun.get("ok",false) and main.mode=="battle","Actual Main battle started with physical owned boats"):await _finish();return
	check(main.battle.chartPosition==c.state.position and main.battle.world064==c.state.world064,"Actual encounter coordinate and region stamped on battle")
	main.withdraw_fleet()
	for _piece in range(600):
		if not bounded():break
		main.poll_battle051(0.1,false)
		await process_frame
		if main.battle.get("result")!=null:break
	if not check(main.battle.get("result")!=null,"Bounded existing battle completes actual withdrawal/result, never fabricated"):await _finish();return
	enter_phase("physical_settlement")
	main.settle_battle()
	if not check(not main.battle_report.is_empty() and main.battle_driver051==null,"Physical worker retired and settlement completed"):await _finish();return
	var coins: int=int(c.state.coins)
	var settled: Dictionary=c.battle_settled(str(main.battle.result),main.battle_enemies,main.battle_context,main.battle)
	check(settled==main.battle_report and int(c.state.coins)==coins,"Repeated physical settlement grants no second loot/account transfer")
	check(c.fleet_owner("patrol-0").boats.any(func(b):return str(b.uid)==owned_uid and is_same(b,original_boat)) or main.battle.get("captured",[]).any(func(b):return str(b.uid)==owned_uid),"Worker returns the original physical UID/object or exact captured prize")
	main.return_to_campaign()
	# Controlled voyage-loss custody branch: same retired physical boat, no new
	# fleet/spec/resource and no assigned victory. This is not earned combat proof.
	enter_phase("controlled_wreck_custody")
	var foe: Dictionary=c.fleet_owner("patrol-0")
	var living: Array=foe.boats.filter(func(b):return not b.get("sunk",false))
	if not living.is_empty():
		var damaged: Dictionary=living[0]
		damaged.water=float(damaged.capacity)
		c.Damage.tick_ship(damaged,0.1,{"inCombat":false})
		c.OceanCampaign066.record_losses(c)
	var wrecks: Array=c.state.wrecks.filter(func(w):return str(w.get("uid",""))==owned_uid and c.OceanCampaign066.Travel.same_world(w.get("world064",{}),main.battle.world064))
	check(not wrecks.is_empty(),"Actual physical UID/equipment becomes a wreck in its offshore region")
	check(c.Money.total(c.state)==int(c.state.coinSupply),"Battle/controlled wreck custody preserves original global coin supply")
	enter_phase("read_only_contact_ui")
	var live_before: String=JSON.stringify(c.state)
	var pending_before: int=c.pending_days
	main.ui.open_ocean_contact066();main.ui.close_modal()
	check(JSON.stringify(c.state)==live_before and c.pending_days==pending_before,"Contact display/open/close is read-only")
	await _finish()

func _finish() -> void:
	if finished:return
	enter_phase("cleanup")
	finished=true
	if main!=null:
		main._retire_battle_driver051();main.sync_economy()
		main.queue_free()
		await process_frame
	var elapsed: int=Time.get_ticks_msec()-started
	check(elapsed<55000,"Whole body including ready/startup and cleanup stays below55 seconds")
	var receipt: Dictionary={"fixture":"ocean_voyage066","sourceCandidate":true,"checks":checks,"failures":failures,"elapsedMs":elapsed,"invoices":invoices,"diagnostics":diagnostics,"diagnosticCount":diagnostic_count,"controlledLoss":"Existing retired boat flooded for regional wreck custody; no earned combat win asserted."}
	var directory: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if directory.is_absolute_path():
		var file=FileAccess.open(directory.path_join("ocean-voyage066-result.json"),FileAccess.WRITE)
		if file:file.store_string(JSON.stringify(receipt,"\t"));file.close()
	print("OCEAN066_RESULT ",JSON.stringify(receipt))
	quit(0 if failures==0 else 1)
