extends SceneTree
const Money=preload("res://scripts/money.gd")
const Training=preload("res://scripts/crew_training.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL training voyage: "+message)
func _initialize() -> void:
	var scene=load("res://main.tscn").instantiate()
	root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("training-voyage-fixture")
	scene.new_game();scene.set_process(false);scene.set_physics_process(false)
	var c=scene.core
	var p: Dictionary=c.current_port()
	Money.move(p,"governmentPurse",c.state,"coins",20000,"Fixture finite training funds",c.state.moneyLog)
	var total: int=Money.total(c.state)
	var q: Dictionary=Training.quote(p,3,"sailor")
	check(q.ok,"Actual harbor can quote a three-person course")
	var workforce: int=int(p.workforce)
	check(c.TrainingOps.enroll(c,3,"sailor").ok,"Actual local transaction commissions training")
	check(Money.total(c.state)==total and int(p.workforce)==workforce-int(q.get("reservedWorkers",4)),"Training escrows existing coins and reserves existing workers")
	var id: String=str(p.training.jobs[0].id)
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Queued training roundtrips through actual restore preflight")
	p=c.current_port()
	check(c.TrainingOps.cancel(c,id).ok and not c.TrainingOps.cancel(c,id).ok,"Cancellation returns people and unspent wages once")
	check(int(p.workforce)==workforce and Money.total(c.state)==total,"Cancellation preserves people and total money")
	check(c.TrainingOps.enroll(c,1,"sailor").ok,"Second real course can begin")
	for day in range(ceili(float(q.get("days",4)))+2):
		c.wait_day();scene.sync_economy()
	check(Money.total(c.state)==total,"Actual copied-port economy days conserve training money")
	p=c.current_port()
	check(p.training.jobs.is_empty(),"Funded training finishes under the real worker publication loop")
	var before: int=int(p.workforce)
	var eligible: int=int(p.training.qualified.sailor)
	var boat: Dictionary=c.add_boat(c.hull("bilge_punt"),0)
	check(c.recruit_crew(boat.uid,1).ok,"Newly available qualification supports actual recruitment")
	check(int(p.workforce)==before-1 and int(p.training.qualified.sailor)==eligible-1,"Hiring consumes a person and eligibility together")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Finished training and hired crew survive actual save/load")
	var bad: Dictionary=c.state.duplicate(true)
	bad.ports[0].training.jobs="broken"
	var held: String=JSON.stringify(c.state)
	check(not c.restore(bad).ok and JSON.stringify(c.state)==held,"Malformed training refuses before changing live state")
	scene.ui.EconomicUI.open(scene.ui)
	check(scene.ui.modal_kind=="economic_workforce","Actual harbor training screen renders")
	scene.queue_free();await process_frame
	print("training voyage: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
