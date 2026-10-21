extends SceneTree
## A short wall-clock run advances 180 economic days with real copied-port workers.
const Money=preload("res://scripts/money.gd")
const Home=preload("res://scripts/home_harbor.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,text: String):
	checks+=1
	if not ok:failures+=1;print("FAIL endurance: "+text)
func _initialize():
	var started: int=Time.get_ticks_msec()
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("endurance-fixture")
	scene.new_game();scene.set_process(false);scene.set_physics_process(false)
	var c=scene.core
	var p: Dictionary=c.current_port()
	Money.move(p,"governmentPurse",c.state,"coins",30000,"Fixture finite warehouse startup capital",c.state.moneyLog)
	check(Home.establish(c,"warehouse",p.id).ok and c.RegionalOps.start(c,"harbor").ok,"Endurance starts an actual funded business and optional goal")
	var supply: int=Money.total(c.state)
	var workers: int=0
	for day in range(180):
		c.wait_day();scene.sync_economy()
		workers=maxi(workers,scene.economy_workers.last_workers)
		check(Money.total(c.state)==supply,"Coins conserved on day %d"%(day+2))
		check(scene.economy_workers.group_id<0 and scene.economy_task<0,"Workers joined before next day")
		for town in c.state.ports:
			var valid: bool=true
			for value in town.stocks.values():
				if not is_finite(float(value)) or float(value)<-0.00001:valid=false
			check(valid,"Finite nonnegative physical stocks at "+str(town.id))
		if day in [29,89,179]:
			check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Actual save roundtrip at economic day %d"%int(c.state.day))
	check(int(c.state.econDay)==181 and workers>=1 and workers<=8,"All 180 days publish once with a bounded hardware worker group")
	check(c.state.businesses[0].paused and c.state.businesses[0].arrearsHousehold>0,"An unfunded business eventually pauses with explicit wage arrears")
	check(c.state.regionalCampaigns.journal.size()<=40 and c.state.log.size()<=45,"Long campaign histories remain bounded")
	check(Time.get_ticks_msec()-started<45000,"180 economic days remain a short background check")
	print("campaign endurance: %d checks, %d failures, %d ms, %d worker lanes"%[checks,failures,Time.get_ticks_msec()-started,workers])
	scene.queue_free();await process_frame
	quit(0 if failures==0 else 1)
