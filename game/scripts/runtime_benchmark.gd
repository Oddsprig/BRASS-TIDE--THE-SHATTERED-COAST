extends RefCounted
## Exported-game CPU probe only. Root supplies the bounded headless/Dummy lane.
const Lab=preload("res://scripts/fleet_lab.gd")
const Battle=preload("res://scripts/battle.gd")
const Damage=preload("res://scripts/damage.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Version=preload("res://scripts/version.gd")
const DT: float=1.0/60.0
const PROBE_BUDGET_US: int=12000000
const ACTION_TICKS: int=96
var checks: int=0
var failures: Array=[]

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);print("FAIL runtime_performance041: "+message)

func valid(st: Dictionary) -> bool:
	for ship in st.ships:
		var info: Dictionary=Damage.inspect_owner_cached(ship)
		if not bool(info.get("ok",false)) or str(info.get("mode",""))!="canonical":return false
		for key in ["x","y","vx","vy","angle","hp","water","fire","engine","crew","ammo","fuel","supplies"]:
			if not is_finite(float(ship.get(key,NAN))):return false
		if float(ship.ammo)<0.0 or float(ship.fuel)<0.0 or float(ship.supplies)<0.0:return false
	return true

func timing(values: Array) -> Dictionary:
	if values.is_empty():return {"count":0,"medianUs":null,"p95Us":null,"maxUs":null,"totalUs":0}
	var sorted: Array=values.duplicate();sorted.sort()
	var count: int=sorted.size();var middle: int=floori(count/2.0);var total: int=0
	for value in sorted:total+=int(value)
	return {"count":count,"medianUs":float(sorted[middle]) if count%2 else (float(sorted[middle-1])+float(sorted[middle]))/2.0,"p95Us":int(sorted[ceili(count*0.95)-1]),"maxUs":int(sorted[-1]),"totalUs":total}

func sample(world: Dictionary,r: Dictionary,started: int) -> void:
	var created: Dictionary=Lab.create(world,{"player":[Lab.entry(world,"bilge_punt",21)],"enemy":[Lab.entry(world,"bilge_punt",21)]},4040)
	check(bool(created.get("ok",false)),"public Lab.create succeeds")
	if not bool(created.get("ok",false)):r.startError=str(created.get("error",""));return
	var st: Dictionary=created.battle
	check(not st.has("startError"),"public battle deployment fits in default terrain")
	if st.has("startError"):r.startError=str(st.startError);return
	var players: Array=st.ships.filter(func(ship):return ship.team=="player")
	var enemies: Array=st.ships.filter(func(ship):return ship.team=="enemy")
	r.actual={"hull":"bilge_punt","totalBoats":st.ships.size(),"playerBoats":players.size(),"enemyBoats":enemies.size(),"playerDP":Deployment.total(players),"enemyDP":Deployment.total(enemies),"deployment":st.deployment.duplicate(true)}
	check(players.size()==21 and enemies.size()==21 and st.ships.all(func(ship):return str(ship.spec.id)=="bilge_punt") and int(r.actual.playerDP)==294 and int(r.actual.enemyDP)==294 and int(st.deployment.player)==294 and int(st.deployment.enemy)==294 and st.reserves.player.is_empty() and st.reserves.enemy.is_empty(),"actual 42 bilge punts deploy at 294 DP per side without reserves")
	check(valid(st),"initial states are finite with valid canonical equipment")
	var movement: Dictionary={};var previous: int=0
	for ship in st.ships:movement[str(ship.id)]={"team":str(ship.team),"last":Vector2(ship.x,ship.y),"distance":0.0}
	for tick in range(16):
		if st.result!=null or Time.get_ticks_usec()-started+maxi(3000000,previous*2)>=PROBE_BUDGET_US:break
		var before: int=Time.get_ticks_usec();Battle.update(st,DT);previous=Time.get_ticks_usec()-before
		r["warmupCompleted" if tick<4 else "measuredCompleted"]+=1
		if tick<4:r.warmupUs.append(previous)
		else:
			var metrics: Dictionary=st.tactical.metrics
			r.updateUs.append(previous);r.aiUs.append(int(metrics.aiUs))
			r.samples.append({"tick":tick-3,"updateUs":previous,"aiUs":int(metrics.aiUs),"phaseUs":metrics.get("phaseUs",{}).duplicate(true),"planningDetailUs":metrics.get("planningDetailUs",{}).duplicate(true)})
			for key in metrics.get("phaseUs",{}):r.phaseUs[key]=int(r.phaseUs.get(key,0))+int(metrics.phaseUs[key])
		for event in Battle.pop_events(st):r.events+=1;r.eventKinds[str(event.kind)]=int(r.eventKinds.get(str(event.kind),0))+1
		for ship in st.ships:
			var row: Dictionary=movement[str(ship.id)];var position: Vector2=Vector2(ship.x,ship.y)
			row.distance+=position.distance_to(row.last);row.last=position
	r.movedBoats=0;r.movement=[]
	for id in movement:
		var row: Dictionary=movement[id]
		if float(row.distance)>0.0001:r.movedBoats+=1
		r.movement.append({"id":id,"team":row.team,"distance":row.distance})
	r.simSeconds=float(st.time);r.droppedEvents=int(st.droppedEvents);r.result=st.result
	r.complete=int(r.warmupCompleted)==4 and int(r.measuredCompleted)==12 and is_equal_approx(float(st.time),16*DT)
	check(valid(st),"final states remain finite with valid canonical equipment")
	check(bool(r.complete),"all four warmup and twelve measured ticks complete at 1/60")

func action_sample(world: Dictionary,r: Dictionary,started: int) -> Dictionary:
	# Separate from the unchanged 42/294 opening workload. Compact real birth
	# poses put four stock gunboats in range; all movement, AI, shots, hit tests,
	# damage and stores then advance through public Battle.update at 60Hz.
	var action: Dictionary={"seed":4101,"terrain":"Unchanged default islands; paired boats at x1000/1200, y650/1050","dt":DT,"ticksRequested":ACTION_TICKS,"ticksCompleted":0,"updateUs":[],"events":{},"fireEvents":0,"hitEvents":0,"firstFireTick":-1,"firstHitTick":-1,"timeline":[],"complete":false}
	r.action=action
	if Time.get_ticks_usec()-started+3000000>=PROBE_BUDGET_US:
		check(false,"action sample has time remaining inside the shared probe budget");return {}
	var created: Dictionary=Lab.create(world,{"player":[Lab.entry(world,"tin_skiff",2)],"enemy":[Lab.entry(world,"tin_skiff",2)]},4101)
	check(bool(created.get("ok",false)),"compact action sample uses public canonical Lab birth")
	if not bool(created.get("ok",false)):action.startError=str(created.get("error",""));return {}
	var st: Dictionary=created.battle
	var movement: Dictionary={}
	var before: Dictionary={"ammo":0.0,"fuel":0.0,"crew":0.0,"supplies":0.0}
	for index in range(st.ships.size()):
		var ship: Dictionary=st.ships[index]
		ship.x=1000.0 if ship.team=="player" else 1200.0
		ship.y=650.0+400.0*(index%2)
		ship.angle=0.0 if ship.team=="player" else PI
		st.tactical.home[str(ship.id)]={"x":ship.x+(-240.0 if ship.team=="player" else 240.0),"y":ship.y}
		movement[str(ship.id)]={"team":str(ship.team),"last":Vector2(ship.x,ship.y),"distance":0.0}
		for key in before:before[key]+=float(ship[key])
	action.actual={"boats":st.ships.size(),"playerDP":st.deployment.player,"enemyDP":st.deployment.enemy,"autopilot":st.autopilot}
	check(st.ships.size()==4 and not st.has("startError") and st.autopilot,"four boats start the compact action sample under default autopilot")
	var previous_us: int=0
	for tick in range(ACTION_TICKS):
		if st.result!=null or Time.get_ticks_usec()-started+maxi(3000000,previous_us*2)>=PROBE_BUDGET_US:break
		var tick_started: int=Time.get_ticks_usec()
		Battle.update(st,DT)
		previous_us=Time.get_ticks_usec()-tick_started
		action.updateUs.append(previous_us);action.ticksCompleted+=1
		var events: Array=Battle.pop_events(st)
		for event in events:
			var kind: String=str(event.kind)
			action.events[kind]=int(action.events.get(kind,0))+1
			if kind=="fire":
				action.fireEvents+=1
				if int(action.firstFireTick)<0:action.firstFireTick=tick+1
			if kind=="hit":
				action.hitEvents+=1
				if int(action.firstHitTick)<0:action.firstHitTick=tick+1
		var poses: Array=[]
		for ship in st.ships:
			var row: Dictionary=movement[str(ship.id)]
			var position: Vector2=Vector2(ship.x,ship.y)
			row.distance+=position.distance_to(row.last);row.last=position
			if tick%12==0 or tick==ACTION_TICKS-1:poses.append({"id":ship.id,"x":ship.x,"y":ship.y,"hp":ship.hp,"ammo":ship.ammo,"fuel":ship.fuel})
		if not poses.is_empty():action.timeline.append({"tick":tick+1,"time":st.time,"fireEvents":action.fireEvents,"hitEvents":action.hitEvents,"poses":poses})
	var after: Dictionary={"ammo":0.0,"fuel":0.0,"crew":0.0,"supplies":0.0}
	for ship in st.ships:
		for key in after:after[key]+=float(ship[key])
	action.movement=[];action.movedByTeam={"player":0,"enemy":0}
	for id in movement:
		var row: Dictionary=movement[id]
		action.movement.append({"id":id,"team":row.team,"distance":row.distance})
		if float(row.distance)>1.0:action.movedByTeam[row.team]+=1
	action.storesBefore=before;action.storesAfter=after
	action.simSeconds=st.time;action.result=st.result;action.timing=timing(action.updateUs)
	action.complete=int(action.ticksCompleted)==ACTION_TICKS and is_equal_approx(float(st.time),ACTION_TICKS*DT)
	check(bool(action.complete),"compact action completes all 96 physical ticks at 1/60")
	check(int(action.fireEvents)>0 and float(after.ammo)<float(before.ammo),"default AI emits real weapon events and debits finite ammunition")
	check(int(action.movedByTeam.player)>0 and int(action.movedByTeam.enemy)>0 and float(after.fuel)<float(before.fuel),"both sides actually move and burn real fuel during the action window")
	check(valid(st),"compact action finishes with finite canonical states and nonnegative stores")
	return st

func run(world: Dictionary) -> int:
	var started: int=Time.get_ticks_usec()
	var r: Dictionary={"version":Version.text(),"build":Version.BUILD,"engine":Engine.get_version_info(),"os":OS.get_name(),"features":{"editor":OS.has_feature("editor"),"debug":OS.has_feature("debug"),"release":OS.has_feature("release"),"debugBuild":OS.is_debug_build()},"displayServer":DisplayServer.get_name(),"seed":4040,"dt":DT,"terrain":"Unchanged public Lab default islands/formation","warmupRequested":4,"measuredRequested":12,"warmupCompleted":0,"measuredCompleted":0,"warmupUs":[],"updateUs":[],"aiUs":[],"phaseUs":{},"samples":[],"events":0,"eventKinds":{},"complete":false,"limits":"Opening42/294 workload unchanged; compact four-boat action is reported separately. CPU simulation only under external Test Bridge limits; no rendered FPS or sustained engagement claim. Timings/AI phases cover measured ticks; movement/events include warmup. AI/phase clocks overlap updateUs; planning includes begin and helm."}
	check(DisplayServer.get_name()=="headless","explicit headless display is required")
	check(not OS.has_feature("editor") and OS.has_feature("release") and not OS.is_debug_build(),"probe requires an exported release executable outside the editor")
	if failures.is_empty():
		sample(world,r,started)
		if bool(r.complete):action_sample(world,r,started)
	r.openingComplete=bool(r.complete)
	r.complete=bool(r.complete) and bool(r.get("action",{}).get("complete",false))
	r.targetUpdateUs=12000
	r.probeBudgetUs=PROBE_BUDGET_US
	r.timing=timing(r.updateUs);r.aiTiming=timing(r.aiUs);r.wallUs=Time.get_ticks_usec()-started
	r.targetMet=r.timing.medianUs!=null and float(r.timing.medianUs)<12000.0
	var folder: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	check(not folder.is_empty(),"GAME_TEST_ARTIFACTS supplies the output destination")
	if not folder.is_empty():DirAccess.make_dir_recursive_absolute(folder)
	var file=FileAccess.open(folder.path_join("RUNTIME PERFORMANCE v0.041.json"),FileAccess.WRITE) if not folder.is_empty() else null
	check(file!=null,"runtime performance artifact opens")
	r.checks=checks;r.failures=failures;r.passed=failures.is_empty()
	if file!=null:file.store_string(JSON.stringify(r,"\t"));file.close()
	print("RUNTIME_PERFORMANCE041 %d checks, %d failures"%[checks,failures.size()])
	return 0 if failures.is_empty() else 1
