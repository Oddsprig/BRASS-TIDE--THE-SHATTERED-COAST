extends SceneTree
const C=preload("res://scripts/campaign.gd")
const T=preload("res://scripts/crew_training.gd")
const M=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL training: "+message)
func _initialize() -> void:
	var w: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var c=C.new(w);c.new_game(919)
	var p: Dictionary=c.current_port()
	M.move(p,"governmentPurse",c.state,"coins",30000,"Finite test training capital",c.state.moneyLog)
	var total: int=M.total(c.state)
	var q: Dictionary=T.quote(p,3,"sailor")
	check(q.ok and int(q.cost)==int(q.materialCost)+int(q.traineeWages)+int(q.instructorWages)+int(q.oversight)+int(q.margin)+int(q.duty),"Quote reconciles actual materials, trainee/instructor wages, oversight, facility and duty")
	var poor: Dictionary={"coins":0};var snap: String=JSON.stringify(p)
	check(not T.enroll(p,poor,3).ok and JSON.stringify(p)==snap,"Unaffordable enrollment is atomic")
	var people: int=int(p.workforce);var eligible: int=int(p.training.qualified.sailor)
	check(T.enroll(p,c.state,3).ok and int(p.workforce)==people-4,"Three trainees and one instructor leave ordinary labor")
	var id: String=p.training.jobs[0].id
	check(T.validate(p).is_empty() and M.total(c.state)==total,"Live course schema and escrow total reconcile")
	T.daily(p,1)
	check(int(p.training.jobs[0].traineePaid)==300 and int(p.training.jobs[0].instructorPaid)==150,"One day pays actual trainee and instructor wages")
	var after_paid: int=int(c.state.coins);var held: int=int(p.training.jobs[0].escrow)
	check(T.cancel(p,c.state,id).ok and int(c.state.coins)==after_paid+held,"Cancellation refunds only the remaining wage escrow")
	check(int(p.workforce)==people and int(p.training.qualified.sailor)==eligible and M.total(c.state)==total,"Cancelled course returns people without qualification or new coins")
	check(not T.cancel(p,c.state,id).ok,"Repeated cancellation cannot refund twice")
	check(T.enroll(p,c.state,2,"mechanic").ok,"Existing workers can train as mechanics")
	T.daily(p,2.5)
	check(T.validate(p).is_empty() and M.total(c.state)==total,"Fractional elapsed time preserves cumulative integer wages")
	T.daily(p,20)
	check(p.training.jobs.is_empty() and int(p.training.qualified.sailor)==eligible+2 and int(p.training.qualified.mechanic)==2,"Completion returns real people with a qualification subset")
	check(int(p.workforce)==people and M.total(c.state)==total,"Completed training conserves people and coins")
	var bad: Dictionary=p.duplicate(true);bad.training.qualified.sailor=100000000
	check(not T.validate(bad).is_empty(),"Qualifications cannot exceed actual workers")
	check(not T.quote(p,-1).ok and not T.quote(p,101).ok and not T.quote(p,1,"wizard").ok,"Invalid counts and unknown course are refused")
	check(T.enroll(p,c.state,1,"mechanic").ok,"A fractional-time regression course can begin")
	var malformed: Dictionary=p.duplicate(true)
	malformed.training.nextId=0
	check(not T.validate(malformed).is_empty(),"Stale course sequence cannot create duplicate future identities")
	malformed=p.duplicate(true)
	malformed.training.jobs[0].progress=1.0
	check(not T.validate(malformed).is_empty(),"Unpaid elapsed course progress cannot be forged")
	var partitioned: Dictionary=p.duplicate(true)
	var partition_money: int=M.port_total(partitioned)
	for i in range(80):T.daily(partitioned,0.1)
	check(partitioned.training.jobs.is_empty() and M.port_total(partitioned)==partition_money,"Eighty fractional slices finish once with every escrow coin settled")
	T.daily(p,8)
	check(T.validate(p).is_empty() and M.total(c.state)==total,"Whole and fractional training both keep canonical wages and people")
	p.stocks.supplies=0
	check(not T.enroll(p,c.state,1).ok,"Material shortage prevents funded but impossible training")
	print("crew training: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
