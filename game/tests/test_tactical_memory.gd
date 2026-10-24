extends SceneTree
## Narrow connector regression: real Battle only, physical certs/gates untouched.
## No direct _publish/_fire, synthetic certificates, store refills or timer edits.
const B=preload("res://scripts/battle.gd")
const D=preload("res://scripts/damage.gd")
const T=preload("res://scripts/tactical_runtime.gd")
const DT: float=1.0/30.0
const SPEC={"id":"memory_skiff","name":"Memory Skiff","role":"skiff","tier":1,"hp":150,"armor":1,"crewMin":2,"crewOptimal":5,"crewMax":7,"size":16,"speed":100,"turn":2,"pumps":1,"weapon":"gun","damage":12,"fireRate":2,"range":550,"deploymentPoints":20}
var checks: int=0
var failures: int=0

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL tactical_memory: "+message)

func bounded(value: Variant) -> bool:
	return T.bounded_value(value,{"nodes":0})

func test_bounds() -> void:
	check(bounded({&"phaseSince":1.0,"progressPos":Vector2(3,4),"nested":{&"lastHp":150.0}}),"native textual keys retain finite typed values and nested records")
	check(not bounded({7:1}),"numeric dictionary keys still rejected")
	check(not bounded({"x".repeat(129):1}),"String key length limit preserved")
	check(not bounded({StringName("x".repeat(129)):1}),"StringName key length limit preserved")
	check(not bounded({"x":"x".repeat(257)}),"string value length limit preserved")
	check(not bounded({"x":&"unexpected_symbol_value"}),"non-schema StringName values still rejected")
	check(not bounded({"x":INF}) and not bounded({"x":Vector2(NAN,0)}),"nonfinite scalar/vector values still rejected")
	check(not bounded({"x":RefCounted.new()}),"object values still rejected")
	var wide: Array=[]
	wide.resize(65)
	check(not bounded(wide),"array size limit preserved")
	var dictionary: Dictionary={}
	for i in range(65):dictionary[str(i)]=i
	check(not bounded(dictionary),"dictionary size limit preserved")
	var deep: Variant=0
	for i in range(9):deep=[deep]
	check(not bounded(deep),"depth limit preserved")
	var nodes: Array=[]
	for i in range(64):
		var branch: Array=[]
		for j in range(64):branch.append(j)
		nodes.append(branch)
	check(not bounded(nodes),"total node budget preserved within legal per-container sizes")

func memory(st: Dictionary,ship: Dictionary) -> Dictionary:
	return st.tactical.memory[str(ship.team)].byId.get(str(ship.id),{})

func test_real_salvo_memory() -> void:
	var spec: Dictionary=SPEC.duplicate(true)
	spec.weaponMounts=[{"id":"tube","kind":"rocket","damage":12.0,"fireRate":1.0,"range":800.0,"speed":730.0,"ammoCost":1,"x":8.0,"y":0.0,"angle":0.0,"arc":0.4}]
	var st: Dictionary=B.create({"fleet":[D.create_ship(spec)],"enemySpecs":[spec],"seed":42})
	var starts: Dictionary={}
	var ammo: Dictionary={}
	var fuel: Dictionary={}
	var phases: Dictionary={}
	var shots: Dictionary={}
	var phase_entries: Dictionary={}
	var stable_ages: Dictionary={}
	var last_phase: Dictionary={}
	var last_since: Dictionary={}
	var first_pass: Dictionary={}
	var missing: Dictionary={}
	var observed_shot: Dictionary={}
	for i in range(st.ships.size()):
		var ship: Dictionary=st.ships[i]
		ship.x=500.0+float(i)*400.0;ship.y=850.0;ship.angle=float(i)*PI
		var id: String=str(ship.id)
		starts[id]=Vector2(ship.x,ship.y);ammo[id]=float(ship.ammo);fuel[id]=float(ship.fuel)
		phases[id]=[];shots[id]=0;phase_entries[id]={};stable_ages[id]=false;missing[id]=0;observed_shot[id]=false
	for tick in range(150):
		B.update(st,DT)
		for event in B.pop_events(st):
			if str(event.get("kind",""))=="fire":
				var source: String=str(event.get("sourceId",""))
				if shots.has(source):shots[source]=int(shots[source])+1
		for ship in st.ships:
			var id: String=str(ship.id)
			var state: Dictionary=memory(st,ship)
			if state.is_empty():
				if tick>=5:missing[id]=int(missing[id])+1
				continue
			var phase: String=str(state.get("phase",""))
			var since: float=float(state.get("phaseSince",st.time))
			if not phase in phases[id]:
				phases[id].append(phase)
				phase_entries[id][phase]=float(st.time)
			if phase==str(last_phase.get(id,"")) and is_equal_approx(since,float(last_since.get(id,-1.0))) and float(st.time)-since>0.3:stable_ages[id]=true
			last_phase[id]=phase;last_since[id]=since
			if not first_pass.has(id):first_pass[id]=str(state.get("firingPassId",""))
			if float(state.get("lastUsefulShot",-1.0))>0.0 and bool(state.get("passSpent",{}).get("tube",false)):observed_shot[id]=true
	check(is_equal_approx(float(st.time),5.0) and st.result==null,"150 real nonterminal updates advance five seconds")
	for ship in st.ships:
		var id: String=str(ship.id)
		var state: Dictionary=memory(st,ship)
		var distance: float=Vector2(ship.x,ship.y).distance_to(starts[id])
		check(not state.is_empty() and int(missing[id])==0,id+" retains memory on due and non-due ticks")
		check(bool(stable_ages[id]),id+" phaseSince persists while actual phase time ages")
		check("launch-window" in phases[id] and "turn-away" in phases[id] and "regroup" in phases[id],id+" real launch is observed then progresses through turn-away to regroup")
		check(bool(observed_shot[id]),id+" retained state observes the actual fixed-tube shot and spending")
		check(int(shots[id])==1 and is_equal_approx(float(ship.ammo),float(ammo[id])-1.0),id+" emits one paid salvo across routine plan/certificate refreshes")
		check(not str(state.get("firingPassId","")).is_empty() and str(state.get("firingPassId",""))==str(first_pass.get(id,"")),id+" same pass identity survives launch and regroup")
		check(distance>10.0 and float(ship.fuel)<float(fuel[id]),id+" actual hull moves and spends fuel during the maneuver")
		print("OBS tactical_memory "+JSON.stringify({"id":id,"phases":phases[id],"phaseEntries":phase_entries[id],"retainedFramesMissingAfterTick6":missing[id],"shots":shots[id],"ammoStart":ammo[id],"ammoEnd":ship.ammo,"fuelStart":fuel[id],"fuelEnd":ship.fuel,"distance":distance,"phaseSince":state.get("phaseSince"),"lastUsefulShot":state.get("lastUsefulShot"),"passSpent":state.get("passSpent"),"firingPassId":state.get("firingPassId")}))

func test_real_order_progress() -> void:
	var target_spec: Dictionary=SPEC.duplicate(true)
	target_spec.speed=0.0
	var st: Dictionary=B.create({"fleet":[D.create_ship(SPEC)],"enemySpecs":[target_spec],"seed":42})
	var ship: Dictionary=st.ships[0]
	ship.x=500.0;ship.y=850.0;ship.angle=0.0
	st.ships[1].x=1500.0;st.ships[1].y=1150.0
	var start: Vector2=Vector2(ship.x,ship.y)
	var goal: Vector2=Vector2(650,850)
	var initial_ammo: float=float(ship.ammo)
	var initial_fuel: float=float(ship.fuel)
	check(B.issue_order(st,[str(ship.id)],"move",{"x":goal.x,"y":goal.y}),"real move order accepted")
	var progress_times: Array=[]
	for tick in range(150):
		B.update(st,DT)
		B.pop_events(st)
		var state: Dictionary=memory(st,ship)
		if state.has("progressAt") and not float(state.progressAt) in progress_times:progress_times.append(float(state.progressAt))
	var state: Dictionary=memory(st,ship)
	var position: Vector2=Vector2(ship.x,ship.y)
	check(position.distance_to(start)>100.0 and position.distance_to(goal)<30.0,"real clear-water move advances to the ordered destination")
	check(progress_times.size()>1 and not state.is_empty(),"retained progress observations update from real traveled distance")
	check(is_equal_approx(float(ship.ammo),initial_ammo) and float(ship.fuel)<initial_fuel,"nonfiring move spends fuel without inventing or spending ammunition")
	print("OBS tactical_memory "+JSON.stringify({"case":"clear-water-move","order":ship.order,"x":ship.x,"y":ship.y,"distance":position.distance_to(start),"goalDistance":position.distance_to(goal),"progressTimes":progress_times,"memoryPhase":state.get("phase"),"ammoStart":initial_ammo,"ammoEnd":ship.ammo,"fuelStart":initial_fuel,"fuelEnd":ship.fuel}))

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":quit(2);return
	test_bounds()
	test_real_salvo_memory()
	test_real_order_progress()
	print("Tactical memory: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
