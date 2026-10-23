extends SceneTree
const Money=preload("res://scripts/money.gd")
const Home=preload("res://scripts/home_harbor.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL crisis voyage: "+text)
func census(c) -> int:
	var n: int=int(c.state.get("captives",0))+int(c.state.regionalCrises.lostPeople)
	for p in c.state.ports:
		n+=int(p.workforce)+int(p.get("defenses",{}).get("crew",0))
		for course in p.training.jobs:n+=int(course.reservedWorkers)
	for b in c.state.fleet+c.state.boardingPrizes:n+=int(b.crew)
	for o in c.state.fleetOwners:
		for b in o.boats:n+=int(b.crew)
	for business in c.state.businesses:n+=business.employees.size()
	for j in c.state.regionalCrises.jobs:n+=int(j.n)
	return n
func _initialize() -> void:
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("crisis-voyage-fixture");scene.new_game();scene.set_process(false);scene.set_physics_process(false)
	var c=scene.core
	for o in c.state.fleetOwners:o.active=false
	for p in c.state.patrols:p.active=false
	Money.move(c.current_port(),"governmentPurse",c.state,"coins",100000,"Finite crisis fixture capital",c.state.moneyLog)
	check(Home.establish(c,"warehouse",str(c.current_port().id)).ok,"Actual staffed warehouse establishes an existing wage obligation")
	var business: Dictionary=c.state.businesses[0]
	Money.move(business,"coins",c.state,"coins",int(business.coins),"Finite insolvency fixture",c.state.moneyLog)
	var supply: int=Money.total(c.state);var people: int=census(c)
	for i in range(2):c.wait_day();scene.sync_economy()
	check(not c.state.regionalCrises.crises["brass_haven:wages"].active,"Two actual unpaid days do not invent a sustained crisis")
	c.wait_day();scene.sync_economy()
	check(c.state.regionalCrises.crises["brass_haven:wages"].active and int(c.state.businesses[0].arrearsHousehold)>0,"Three real unpaid obligations open a dated wage crisis")
	var before: String=JSON.stringify(c.state)
	var offers: Array=c.CrisisOps.api(c).offers(c)
	check(not offers.is_empty() and JSON.stringify(c.state)==before,"Funded passage quotes read actual capacity without moving people or coins")
	var r: Dictionary=c.CrisisOps.begin(c,"kelp_reach",3)
	check(r.ok,"Actual sponsor embarks three existing workers: "+str(r.get("message","")))
	if not r.ok:scene.queue_free();await process_frame;quit(1);return
	var id: String=str(r.id);var uid: String=str(c.state.passengerTransport.carriers[id])
	check(c.CrisisOps.api(c).passenger_count(c.state)==3 and c.CrisisOps.Transport.assigned(c.state,uid)==3,"One actual named boat carries the physical cohort in spare berths")
	check(census(c)==people and Money.total(c.state)==supply,"Embarkation moves workers, savings, provisions and escrow exactly once")
	check(not c.recruit_crew(uid,1).ok and not c.toggle_storage(uid).ok,"Passenger berths cannot be sold again to ordinary hires or stored remotely")
	c.wait_day();scene.sync_economy()
	check(int(c.state.regionalCrises.jobs[0].progress)==0,"Waiting at the origin earns no transport work")
	check(c.chart_course(c.port_position("kelp_reach"),"kelp_reach").ok,"Actual water route can be sailed with the provisioned passenger boat")
	for i in range(1600):
		c.step(0.25)
		if c.pending_days>0:scene.sync_economy()
		if c.state.path.is_empty():break
		if i%100==0:await process_frame
	check(c.current_port().get("id","")=="kelp_reach","Passenger boat physically arrives along the actual navigation route")
	c.wait_day();scene.sync_economy()
	check(int(c.state.regionalCrises.jobs[0].progress)==int(c.state.regionalCrises.jobs[0].days),"Observed actual route distance earns its bounded transport work")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Saved route evidence, carrier, cohort savings and fractional provisions pass full preflight")
	var population: int=int(c.current_port().workforce)
	r=c.CrisisOps.arrive(c,id)
	check(r.ok and int(c.current_port().workforce)==population and c.state.regionalCrises.jobs[0].stage=="holding","Actual arrival creates a separate reception cohort before worker admission: "+str(r.get("message","")))
	c.wait_day();scene.sync_economy()
	check(c.state.regionalCrises.jobs.size()==1 and int(c.state.regionalCrises.jobs[0].served)==1,"First subsequent paid and provisioned reception day does not admit people early")
	var held: String=JSON.stringify(c.state);c.CrisisOps.api(c).daily(c)
	check(JSON.stringify(c.state)==held,"Same-day service cannot repeat wages, food or people admission")
	# The deliberate origin wait consumes some return reserve; optional provisions
	# are purchased with the captain's existing coins rather than minted by a job.
	check(c.CrisisOps.provision(c,id,2).ok,"Actual reception provisions can be replenished at a real local counter")
	c.wait_day();scene.sync_economy()
	check(c.state.regionalCrises.jobs.is_empty() and int(c.current_port().workforce)==population+3,"Second distinct staffed day admits exactly the existing three workers")
	check(int(c.state.campaignFacts.get("resettlersAdmitted",0))==3 and c.state.passengerTransport.carriers.is_empty(),"Completed service leaves dated regional progress and no stale carrier reservation")
	check(census(c)==people and Money.total(c.state)==supply,"Actual voyage, wages, reception, purchases and settlement conserve people and coins")
	check(not c.CrisisOps.arrive(c,id).ok,"Completed passage cannot be paid or admitted twice")
	c.state.position=c.port_position("brass_haven")
	r=c.CrisisOps.begin(c,"kelp_reach",1)
	check(r.ok,"A second real cohort can embark in newly freed actual berths")
	if r.ok:check(c.CrisisOps.home(c,str(r.id)).ok and census(c)==people and Money.total(c.state)==supply,"Physical origin cancellation returns real people and savings, refunds only unearned escrow and stores remaining food")
	r=c.CrisisOps.begin(c,"kelp_reach",1)
	check(r.ok,"Actual carrier-loss fixture has a funded existing cohort")
	if r.ok:
		var recover: Dictionary=JSON.parse_string(JSON.stringify(c.state));var j: Dictionary=c.state.regionalCrises.jobs[0]
		var savings: int=int(j.householdPurse)+int(j.expertPurse)
		c.find_boat(str(c.state.passengerTransport.carriers[str(j.id)])).sunk=true
		c.CrisisOps.losses(c)
		check(c.state.regionalCrises.jobs.is_empty() and int(c.state.regionalCrises.lostPeople)==1 and int(c.state.regionalCrises.lostPurse)==savings,"Actual carrier loss moves its cohort and savings to explicit loss custody once")
		check(Money.total(c.state)==supply,"Loss preserves saved passenger savings and all remaining sponsor coins")
		check(c.restore(recover).ok,"Unmodified pre-loss checkpoint remains valid")
		var bad: Dictionary=JSON.parse_string(JSON.stringify(c.state));bad.passengerTransport.carriers[str(bad.regionalCrises.jobs[0].id)]="imaginary-boat"
		check(not c.restore(bad).ok,"A fabricated passenger carrier is refused before state mutation")
		c.CrisisOps.home(c,str(c.state.regionalCrises.jobs[0].id))
	scene.ui.CrisisUI.open(scene.ui)
	check(scene.ui.modal_kind=="regional_crises","Actual dated crisis, passage, provisions and reception controls render")
	check(Money.total(c.state)==supply and c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Final actual campaign remains coin-conserving and save-valid")
	scene.queue_free();await process_frame
	print("crisis voyage: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
