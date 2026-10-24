extends SceneTree
## Canonical commands, physical manual priority and launched crew custody.
const B=preload("res://scripts/battle.gd")
const D=preload("res://scripts/damage.gd")
const Boarding=preload("res://scripts/boarding.gd")
const CombatBoarding=preload("res://scripts/combat_boarding.gd")
const T=preload("res://scripts/tactical_runtime.gd")
const SPEC: Dictionary={"id":"orders-skiff","name":"Order fixture","role":"skiff","hp":180,"armor":1,"size":16,"speed":105,"turn":2.5,"crewMin":2,"crewOptimal":12,"crewMax":24,"pumps":1,"weapon":"gun","damage":10,"fireRate":2,"range":550,"deploymentPoints":15}
var checks: int=0
var failures: int=0
var observations: Array=[]

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL tactical orders: "+message)

func arena(close: bool=false) -> Dictionary:
	var st: Dictionary=B.create({"fleet":[D.create_ship(SPEC,{"uid":"order-source"}),D.create_ship(SPEC,{"uid":"order-ally"})],"enemyFleet":[D.create_ship(SPEC,{"uid":"order-target"})],"seed":30011})
	st.islands=[];st.autoBoard=false
	if close:
		st.ships[0].x=500.0;st.ships[0].y=850.0
		st.ships[1].x=400.0;st.ships[1].y=1100.0
		st.ships[2].x=900.0;st.ships[2].y=850.0
	return st

func step(st: Dictionary,ticks: int,input: Dictionary={}) -> void:
	for tick in range(ticks):
		if st.result!=null:break
		B.update(st,1.0/30.0,input)

func commands() -> void:
	var st: Dictionary=arena()
	var source: Dictionary=st.ships[0]
	var ally: Dictionary=st.ships[1]
	var enemy: Dictionary=st.ships[2]
	step(st,12)
	for order in ["move","attack","hold","escort","engage","withdraw"]:
		var target: Dictionary={"x":740.0,"y":850.0} if order in ["move","withdraw"] else {"shipId":str(enemy.id)} if order=="attack" else {"shipId":str(ally.id)} if order=="escort" else {}
		var revision: int=int(source.orderRevision)
		check(B.issue_order(st,[source.id],order,target),"native accepts selected "+order)
		check(source.order==order and int(source.orderRevision)>revision,"order replaces the prior command immediately: "+order)
		check(not st.tactical.intents.has(str(source.id)),"old physical intent is invalidated immediately: "+order)
		var issued: float=float(st.time)
		step(st,1)
		check(float(st.time)-issued<=1.0/30.0+0.000001,"command applies by next simulation tick: "+order)
		check(int(st.tactical.appliedRevisions.get(str(source.id),-1))==int(source.orderRevision) and not st.tactical.metrics.orderApplyAges.is_empty(),"real helm acknowledges this exact revision: "+order)
		for age in st.tactical.metrics.get("orderApplyAges",[]):check(float(age)<=1.0/30.0+0.000001,"actual helm acknowledged current order revision")
		check(not str(B.tactical_status(st,str(source.id)).get("reason","")).is_empty(),"native selected status explains command/physical wait: "+order)
	var before: Dictionary=st.duplicate(true)
	check(not B.issue_order(st,[source.id,enemy.id],"hold"),"mixed-owner recipient set refuses")
	check(st==before,"recipient refusal is atomic, preserving all state")
	check(not B.issue_order(st,[source.id],"move",{"x":NAN,"y":850}),"nonfinite destination refuses")
	check(st==before,"bad coordinates leave canonical state exact")
	check(not B.issue_order(st,[source.id],"attack",{"shipId":str(ally.id)}),"cannot attack allied hull")
	check(st==before,"bad target leaves canonical state exact")

func physical_manual_priority() -> void:
	var st: Dictionary=arena()
	var source: Dictionary=st.ships[0]
	check(B.issue_order(st,[source.id],"withdraw",{"x":200.0,"y":850.0}),"queue real per-boat withdrawal")
	B.set_autopilot(st,false)
	var initial: Vector2=Vector2(source.x,source.y)
	step(st,45,{"manual":true,"forward":true,"right":true})
	check(not st.autopilot and source.order=="withdraw","manual control owns helm while queued order remains")
	check(Vector2(source.x,source.y).distance_to(initial)>40.0 and absf(float(source.angle))>0.2,"actual arrow helm moves and turns under queued withdrawal")
	var before_angle: float=float(source.angle)
	B.retreat(st)
	check(st.autopilot and is_equal_approx(float(st.retreatTimer),12.0),"fleet withdrawal uses its once-only legacy timer and engages autopilot")
	step(st,1)
	var remaining: float=float(st.retreatTimer)
	B.retreat(st)
	check(is_equal_approx(float(st.retreatTimer),remaining),"repeated fleet command cannot refresh timer")
	B.set_autopilot(st,false)
	initial=Vector2(source.x,source.y)
	step(st,30,{"manual":true,"forward":true,"left":true})
	check(not st.autopilot and Vector2(source.x,source.y).distance_to(initial)>20.0 and absf(angle_difference(before_angle,float(source.angle)))>0.1,"manual retake after fleet retreat has actual motion/heading authority")
	observations.append({"case":"manual-retake","time":st.time,"distanceAfterRetake":Vector2(source.x,source.y).distance_to(initial),"angle":source.angle,"fuel":source.fuel,"remainingFleetTimer":st.retreatTimer})

func per_mount_automatic_budget() -> void:
	var spec: Dictionary=SPEC.duplicate(true)
	spec.weaponMounts=[{"id":"orders-gun","kind":"gun","damage":10.0,"fireRate":2.0,"range":550.0,"speed":850.0,"ammoCost":1,"x":8.0,"y":-5.0,"angle":0.0,"arc":TAU},{"id":"orders-cannon","kind":"cannon","damage":12.0,"fireRate":1.0,"range":550.0,"speed":700.0,"ammoCost":2,"x":8.0,"y":5.0,"angle":0.0,"arc":TAU}]
	var enemy_spec: Dictionary=SPEC.duplicate(true);enemy_spec.speed=0.0
	var st: Dictionary=B.create({"fleet":[D.create_ship(spec,{"ammo":3.0})],"enemySpecs":[enemy_spec],"seed":30011})
	st.autoBoard=false;st.islands=[]
	var source: Dictionary=st.ships[0];var enemy: Dictionary=st.ships[1]
	source.x=500.0;source.y=850.0;source.angle=0.0;enemy.x=900.0;enemy.y=850.0;enemy.ammo=0.0
	var cannon_time: float=B.mount_shot_time(source,"orders-cannon")
	check(B.set_tactical_options(st,[source.id],{"mounts":{"orders-gun":{"hold":false,"reserve":2},"orders-cannon":{"hold":true,"reserve":0}}}),"independent installed mount hold and working reserve accepted")
	var events: Array=[]
	for tick in range(30):
		B.update(st,1.0/30.0)
		for event in B.pop_events(st):
			if event.kind=="fire" and str(event.sourceId)==str(source.id):events.append(event.duplicate(true))
	check(events.size()==1 and str(events[0].mountId)=="orders-gun","reachable unheld gun emits once; held cannon never emits")
	check(is_equal_approx(float(source.ammo),2.0),"actual single-round event debit leaves exact per-mount reserve")
	check(float(source.ammo)>=0.0 and B.mount_shot_time(source,"orders-cannon")==cannon_time,"held cannon retains its native never-fired timestamp and has no hidden debit")
	observations.append({"case":"per-mount-reserve","events":events,"ammo":source.ammo,"time":st.time,"options":B.tactical_status(st,str(source.id)).options})

func automatic_hold_and_manual_rounds() -> void:
	var st: Dictionary=arena(true)
	var source: Dictionary=st.ships[0]
	var target: Dictionary=st.ships[2]
	for ship in st.ships:ship.ammo=0.0
	source.ammo=12.0
	var shot_times: Dictionary=source.get("mountShotTimes",{}).duplicate(true)
	check(B.set_tactical_options(st,[source.id],{"mountGroup":{"kind":"all","hold":true,"reserve":12}}),"real per-mount automatic hold/reserve")
	step(st,30)
	check(is_equal_approx(float(source.ammo),12.0) and source.get("mountShotTimes",{})==shot_times,"automatic held mounts spend no rounds in a reachable engagement")
	B.set_autopilot(st,false)
	step(st,1,{"manual":true,"fire":true,"aimX":float(target.x),"aimY":float(target.y)})
	var fired: Array=B.pop_events(st).filter(func(event):return event.kind=="fire" and str(event.sourceId)==str(source.id))
	check(not fired.is_empty() and float(source.ammo)<12.0,"actual manual emission overrides automatic hold/reserve using finite available rounds")
	var rounds: float=float(source.ammo)
	step(st,1,{"manual":true,"fire":true,"aimX":float(target.x),"aimY":float(target.y)})
	check(is_equal_approx(float(source.ammo),rounds),"same physical mount cannot shoot again while real cooldown remains")
	check(source.cooldown>0.0,"Damage and battle did not double-advance the legacy timer")

func boarding_custody() -> void:
	var st: Dictionary=arena(true)
	var source: Dictionary=st.ships[0]
	var target: Dictionary=st.ships[2]
	for ship in st.ships:ship.ammo=0.0
	source.boarders=6;source.crew=12.0
	target.engine=0.0;target.crew=2.0;target.wounded=0.0
	st.autoBoard=true
	check(CombatBoarding.order(st,str(source.id),str(target.id),4).ok,"real unlaunched physical boarding approach")
	var crew: float=float(source.crew)
	check(B.issue_order(st,[source.id],"hold"),"a new command cancels an unlaunched approach")
	step(st,3)
	check(not source.has("boardingOrder") and float(source.crew)==crew and st.get("boarding",{}).get("jobs",[]).is_empty(),"hold prevents auto-boarding recreation and keeps all people aboard")
	B.set_autopilot(st,false)
	step(st,3,{"manual":true})
	check(not source.has("boardingOrder") and st.get("boarding",{}).get("jobs",[]).is_empty(),"manual flagship has no hidden automatic boarding approach")
	# Dedicated physical contact setup, separate from role-motion starting poses.
	target.x=float(source.x)+40.0;target.y=float(source.y)
	var launch: Dictionary=Boarding.launch(st,str(source.id),str(target.id),4)
	check(launch.ok,"actual finite party launches on physical contact")
	if not launch.ok:return
	var job: Dictionary=st.boarding.jobs[0]
	var next_exchange: float=float(job.next)
	check(float(source.crew)==crew-4 and int(job.alive)==4,"launched crew moves once into canonical party custody")
	check(B.issue_order(st,[source.id],"move",{"x":700.0,"y":1000.0}),"new command while party is launched")
	check(is_same(st.boarding.jobs[0],job) and float(job.next)==next_exchange and float(source.crew)==crew-4,"accepting a new command leaves the launched job and timer exact")
	step(st,1,{"manual":true})
	check(is_same(st.boarding.jobs[0],job) and job.status=="active" and int(job.alive)==4 and float(source.crew)==crew-4,"new helm command cannot recall or duplicate launched people")
	check(is_equal_approx(float(job.next),next_exchange),"new command cannot reset launched boarding exchange timer")
	var pose: Vector2=Vector2(source.x,source.y)
	step(st,12,{"manual":true,"forward":true,"right":true})
	check(job.status=="active" and float(job.next)==next_exchange and int(job.alive)==4 and float(source.crew)==crew-4,"real launched party keeps people and exchange deadline during manual helm")
	check(Vector2(source.x,source.y).distance_to(pose)>1.0 and absf(float(source.angle))>0.1,"launched boarding job cannot force or lock the manual helm")
	observations.append({"case":"launched-custody","sourceCrew":source.crew,"party":job.duplicate(true),"boardingClock":st.boarding.clock,"manualDistance":Vector2(source.x,source.y).distance_to(pose)})
	target.captureSecured=true
	var before: Dictionary=st.duplicate(true)
	check(not B.select_flagship(st,target.id) and not B.issue_order(st,[target.id],"engage"),"secured prize excluded from selection and orders")
	check(st==before,"prize exclusion cannot alter existing crew/job custody")

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":check(false,"requires hidden/headless engine lease")
	else:
		commands();physical_manual_priority();automatic_hold_and_manual_rounds();per_mount_automatic_budget();boarding_custody()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file: FileAccess=FileAccess.open(arg.substr(6),FileAccess.WRITE)
			if file!=null:file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations}));file.close()
	print("tactical orders: %d checks, %d failures; actual commands, helm, stores and launched custody"%[checks,failures])
	quit(0 if failures==0 else 1)
