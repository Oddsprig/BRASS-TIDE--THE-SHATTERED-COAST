extends RefCounted
## Exported-game CPU probe only. Root supplies the bounded headless/Dummy lane.
const Lab=preload("res://scripts/fleet_lab.gd")
const Battle=preload("res://scripts/battle.gd")
const Damage=preload("res://scripts/damage.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Version=preload("res://scripts/version.gd")
const DT: float=1.0/60.0
var checks: int=0
var failures: Array=[]

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);print("FAIL runtime_performance040: "+message)

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
		if st.result!=null or Time.get_ticks_usec()-started+maxi(3000000,previous*2)>=24000000:break
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

func run(world: Dictionary) -> int:
	var started: int=Time.get_ticks_usec()
	var r: Dictionary={"version":Version.text(),"build":Version.BUILD,"engine":Engine.get_version_info(),"os":OS.get_name(),"features":{"editor":OS.has_feature("editor"),"debug":OS.has_feature("debug"),"release":OS.has_feature("release"),"debugBuild":OS.is_debug_build()},"displayServer":DisplayServer.get_name(),"seed":4040,"dt":DT,"terrain":"Unchanged public Lab default islands/formation","warmupRequested":4,"measuredRequested":12,"warmupCompleted":0,"measuredCompleted":0,"warmupUs":[],"updateUs":[],"aiUs":[],"phaseUs":{},"samples":[],"events":0,"eventKinds":{},"complete":false,"limits":"CPU simulation only under external Test Bridge limits; no rendered FPS or sustained engagement claim. Timings/AI phases cover measured ticks; movement/events include warmup. AI/phase clocks overlap updateUs; planning includes begin and helm."}
	check(DisplayServer.get_name()=="headless","explicit headless display is required")
	if failures.is_empty():sample(world,r,started)
	r.timing=timing(r.updateUs);r.aiTiming=timing(r.aiUs);r.wallUs=Time.get_ticks_usec()-started
	var folder: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	check(not folder.is_empty(),"GAME_TEST_ARTIFACTS supplies the output destination")
	if not folder.is_empty():DirAccess.make_dir_recursive_absolute(folder)
	var file=FileAccess.open(folder.path_join("RUNTIME PERFORMANCE v0.040.json"),FileAccess.WRITE) if not folder.is_empty() else null
	check(file!=null,"runtime performance artifact opens")
	r.checks=checks;r.failures=failures;r.passed=failures.is_empty()
	if file!=null:file.store_string(JSON.stringify(r,"\t"));file.close()
	print("RUNTIME_PERFORMANCE040 %d checks, %d failures"%[checks,failures.size()])
	return 0 if failures.is_empty() else 1
