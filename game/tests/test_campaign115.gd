extends SceneTree
## Selected transaction/save/UI fixture. Source, destination and contact-harbor
## positions are declared setups. No earned voyage, operating-cost or FPS claim.

class Preview extends "res://scripts/main.gd":
	var began: int = 0
	var out: String = ""
	var finished: bool = false
	var proof: Dictionary = {"checks":[],"declarations":[],"owner_profile_used":false,"scope":"Actual114 checkpoint; declared harbor positions; finite witness admission, native provisions/savings/reception/return/loss, optional Wren contact; declared harbor positions, route-work and calendar, persistence and actual UI. Not an earned full voyage or store media."}

	func _ready() -> void:
		qa_ocean066 = true
		super._ready()
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		out = OS.get_environment("GAME_TEST_ARTIFACTS").path_join("campaign115")
		DirAccess.make_dir_recursive_absolute(out)
		save_directory = out.path_join("saves")
		run.call_deferred()

	func write_json(name: String, value) -> bool:
		var f = FileAccess.open(out.path_join(name),FileAccess.WRITE)
		if f == null:return false
		f.store_string(JSON.stringify(value,"\t"));f.close()
		return true

	func snapshot() -> Dictionary:
		return JSON.parse_string(JSON.stringify(core.state))

	func conserved() -> bool:
		return core.Money.total(core.state) == int(core.state.coinSupply)

	func finish(passed: bool) -> void:
		if finished:return
		finished = true
		proof.passed = passed
		proof.elapsed_ms = Time.get_ticks_msec()-began
		if not core.state.is_empty():write_json("final-state.json",snapshot())
		write_json("evidence.json",proof)
		print("CAMPAIGN115_DONE" if passed else "CAMPAIGN115_FAIL")
		get_tree().quit(0 if passed else 2)

	func check(okay: bool, label: String) -> bool:
		if finished:return false
		var bounded: bool = Time.get_ticks_msec()-began < 25000
		okay = okay and bounded
		proof.checks.append({"name":label,"passed":okay})
		write_json("progress.json",{"checks":proof.checks,"elapsed_ms":Time.get_ticks_msec()-began})
		print("CAMPAIGN115_CHECK %d %s %s"%[proof.checks.size(),str(okay),label])
		if not okay:
			push_error("CAMPAIGN115 "+label)
			finish(false)
		return okay

	func locate(port_id: String) -> void:
		var p: Dictionary = core.port(port_id)
		core.state.position = {"x":float(p.x),"y":float(p.y)}
		core.state.path = []
		core.state.destination = ""
		proof.declarations.append("Declared reference-harbor position: "+port_id+"; no traveled-distance claim.")

	func capture(name: String, find_mara: bool=false) -> void:
		ui.close_modal();ui.update_hud();ui.StoryUI.open(ui)
		await get_tree().process_frame
		if find_mara:
			var labels: Array = ui.find_children("*","Label",true,false)
			for label in labels:
				if not str(label.text).begins_with("Mara"):continue
				var ancestor: Node = label.get_parent()
				while ancestor != null and not ancestor is ScrollContainer:ancestor=ancestor.get_parent()
				if ancestor is ScrollContainer:
					var scrolling: ScrollContainer=ancestor as ScrollContainer
					scrolling.scroll_vertical += maxi(0,roundi(label.global_position.y-scrolling.global_position.y)-12)
					break
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var frame = get_viewport().get_texture().get_image()
		check(frame != null and frame.save_png(out.path_join(name)) == OK,"Saved actual115 journal image: "+name)

	func cohort_job() -> Dictionary:
		var id: String=str(core.Arc115.work(core).get("jobId",""))
		for j in core.state.regionalCrises.jobs:
			if str(j.id)==id:return j
		return {}

	func cohort_day(duplicate_probe: bool=false) -> bool:
		var next: int=int(core.state.econDay)+1
		core.state.day=maxf(float(core.state.day),float(next)+0.01)
		core.CrisisOps.daily(core)
		if duplicate_probe:
			var first: Dictionary=cohort_job().duplicate(true)
			var balance: int=int(core.state.coins)
			core.CrisisOps.daily(core)
			if not check(cohort_job()==first and int(core.state.coins)==balance,"The same native reception service day cannot run twice"):return false
		core.state.econDay=next
		return conserved()

	func complete_route_and_reception(destination: String) -> bool:
		var j: Dictionary=cohort_job()
		var id: String=str(j.id)
		var days: int=int(j.days)
		var work: Dictionary=core.state.passengerTransport.work[id]
		# Unchanged route-distance subsystem is a declared precondition here.
		# The fixture exercises its real day consumption and native reception;
		# it does not claim an earned full sailing voyage or world-day payroll.
		work.distance=float(work.unit)*float(days)+0.1
		proof.declarations.append("Declared full native route-work credit and reference calendar for "+destination+"; no earned voyage or general-world daily cost claim.")
		for i in range(days):
			if not cohort_day():return false
		j=cohort_job()
		if not check(not j.is_empty() and int(j.progress)==days and int(j.served)==0 and not core.Arc115.choice_gate(core,"report_witnesses115").get("ok",false),"Completed transport work alone grants no witness discharge report"):return false
		locate(destination)
		var arrived: Dictionary=core.CrisisOps.arrive(core,id)
		if not check(arrived.get("ok",false) and cohort_job().stage=="holding" and not core.Arc115.choice_gate(core,"report_witnesses115").get("ok",false),"Actual native arrival enters reception and still requires two service days"):return false
		if not cohort_day(true):return false
		if not check(not cohort_job().is_empty() and int(cohort_job().served)==1,"The first paid reception day retains the actual cohort"):return false
		if not cohort_day():return false
		return check(cohort_job().is_empty() and core.Arc115.work(core).status=="delivered" and conserved(),"The second distinct native service day discharges the original two people and closes their purses once")

	func run() -> void:
		var path: String=OS.get_environment("CAMPAIGN_PRIOR_SAVE")
		if not check(FileAccess.file_exists(path) and FileAccess.get_sha256(path)==OS.get_environment("CAMPAIGN_PRIOR_SHA"),"Uses the exact accepted114 checkpoint by SHA256"):return
		var restored: Dictionary=core.restore(JSON.parse_string(FileAccess.get_file_as_string(path)))
		mode="campaign";paused=true;ui.close_modal();ui.build_hud()
		if not check(restored.get("ok",false) and core.Arc110.record(core).stage=="names_on_paper115" and core.state.stories.catalog.size()==14 and conserved(),"Accepted114 restores with its original property account and the new115 catalog"):return
		var earlier: Dictionary=core.Arc114.work(core).duplicate(true)
		var starting: Dictionary=snapshot()
		locate("reed_floats")
		if not check(core.StoryOps.choose(core,core.Arc110.ID,"choose_public115").get("ok",false) and core.Arc115.work(core).destination=="reed_floats","Public reception is disclosed and selected before boarding"):return
		if not check(not core.Arc115.gate(core,{"mode":"optional"}).get("ok",false),"A destination choice alone does not open Wren's survivor conversation"):return
		locate("rust_anchorage")
		if not core.Politics.permit(core,"service").get("ok",false):
			if not check(core.Politics.parley(core).get("ok",false),"Native Rust access is actually paid when required"):return
		var p: Dictionary=core.current_port()
		var government: int=int(p.governmentPurse)
		if not check(core.Money.move(p,"governmentPurse",p,"householdPurse",government,"Declared115 sponsor unavailable elsewhere",core.state.moneyLog),"Negative funding precondition transfers existing coins without changing supply"):return
		if not check(not core.Arc115.quote(core).get("ok",false) and cohort_job().is_empty() and conserved(),"An unfunded source cannot board witnesses or create an allocation"):return
		if not check(core.Money.move(p,"householdPurse",p,"governmentPurse",government,"Restore private115 funding precondition",core.state.moneyLog),"The isolated funding probe returns the same actual coins"):return
		var q: Dictionary=core.Arc115.quote(core)
		if not check(q.get("ok",false) and int(q.count)==2 and q.destination=="reed_floats" and q.funded==2*100*int(q.days)+550,"The two-person offer uses the native finite wage/reception allocation"):return
		var wrong: Dictionary=q.duplicate(true);wrong.funded=int(q.funded)+1
		var old_workers: int=int(p.workforce);var old_government: int=int(p.governmentPurse);var old_food: float=float(p.stocks.food)
		if not check(not core.Arc115.accept(core,wrong).get("ok",false) and int(p.workforce)==old_workers and int(p.governmentPurse)==old_government,"Changed quotation refuses before moving people or money"):return
		if not check(core.Arc115.accept(core,q).get("ok",false),"Native two-person admission boards from the existing Rust workforce"):return
		var j: Dictionary=cohort_job()
		var public_id: String=str(j.id)
		var carrier: String=str(core.state.passengerTransport.carriers[public_id])
		if not check(int(j.n)==2 and old_workers-int(core.port("rust_anchorage").workforce)==2 and old_government-int(core.port("rust_anchorage").governmentPurse)==int(q.funded) and old_food>float(core.port("rust_anchorage").stocks.food) and not carrier.is_empty() and conserved(),"Actual workforce, food, sponsor allocation and carrier are conserved through native boarding"):return
		if not check(not core.Arc115.accept(core,q).get("ok",false) and not core.Arc115.select(core,"anvil_dock").get("ok",false),"The cohort cannot embark twice or change destination after boarding"):return
		var target_before: int=int(core.port("reed_floats").workforce)
		if not complete_route_and_reception("reed_floats"):return
		if not check(int(core.port("reed_floats").workforce)-target_before==2 and core.Arc115.choice_gate(core,"report_witnesses115").get("ok",false),"Only the real public discharge admits exactly two destination workers"):return
		if not check(core.StoryOps.choose(core,core.Arc110.ID,"report_witnesses115").get("ok",false) and core.Arc115.work(core).reported and write_json("public-state.json",snapshot()),"Explicit public report retains the actual completed cohort account"):return
		await capture("public.png")
		if finished:return
		if not check(core.StoryOps.start(core,"wren_witness115").get("ok",false) and core.StoryOps.choose(core,"wren_witness115","finish_wren_witness115").get("ok",false),"Actual discharged survivors open Wren's optional conversation"):return
		if not check(core.restore(starting).get("ok",false) and conserved(),"The separate protected branch starts from the original accepted114 checkpoint"):return
		locate("reed_floats")
		if not check(core.StoryOps.choose(core,core.Arc110.ID,"choose_protected115").get("ok",false) and core.Arc115.work(core).destination=="anvil_dock","Protected Anvil reception is selected before any passenger boards"):return
		locate("rust_anchorage")
		q=core.Arc115.quote(core)
		if not check(q.get("ok",false) and core.Arc115.accept(core,q).get("ok",false),"The protected branch uses its own real native terms and two-person admission"):return
		var active: Dictionary=snapshot()
		j=cohort_job();var protected_id: String=str(j.id)
		var returned: Dictionary=core.CrisisOps.home(core,protected_id)
		if not check(returned.get("ok",false) and core.Arc115.work(core).status=="returned" and cohort_job().is_empty() and conserved(),"Actual return restores the cohort and its savings to Rust without claiming testimony delivery"):return
		if not check(not core.Arc115.gate(core,{"mode":"optional"}).get("ok",false) and core.restore(active).get("ok",false),"A returned cohort does not grant survivor testimony; the active checkpoint restores"):return
		carrier=str(core.state.passengerTransport.carriers[protected_id])
		var boat: Dictionary=core.find_boat(carrier)
		boat.sunk=true
		proof.declarations.append("Declared carrier-loss marker to exercise native people/savings loss settlement; not physical battle casualty evidence.")
		var lost_before: int=int(core.state.regionalCrises.lostPeople)
		core.CrisisOps.losses(core)
		if not check(core.Arc115.work(core).status=="lost" and int(core.state.regionalCrises.lostPeople)-lost_before==2 and cohort_job().is_empty() and conserved(),"Native loss settlement records exactly the original two people and counted savings once"):return
		core.CrisisOps.losses(core)
		if not check(int(core.state.regionalCrises.lostPeople)-lost_before==2 and not core.Arc115.gate(core,{"mode":"optional"}).get("ok",false),"Repeated loss neither duplicates people nor grants a survivor conversation"):return
		if not check(core.restore(active).get("ok",false) and conserved(),"The loss probe rolls back only its complete private checkpoint"):return
		target_before=int(core.port("anvil_dock").workforce)
		if not complete_route_and_reception("anvil_dock"):return
		if not check(int(core.port("anvil_dock").workforce)-target_before==2 and core.StoryOps.choose(core,core.Arc110.ID,"report_witnesses115").get("ok",false) and write_json("protected-state.json",snapshot()),"The protected report uses actual Anvil discharge rather than the public destination"):return
		await capture("protected.png")
		if finished:return
		locate("reed_floats")
		if not check(core.StoryOps.start(core,"wren_witness115").get("ok",false) and core.StoryOps.choose(core,"wren_witness115","finish_wren_witness115").get("ok",false),"Wren can receive the protected cost account without exposing witness identities"):return
		if not check(core.StoryOps.choose(core,core.Arc110.ID,"next_distress115").get("ok",false) and core.Arc110.record(core).stage=="two_distress116" and core.Arc114.work(core)==earlier,"115 ends at the locked116 lead and preserves the accepted114 property report"):return
		if not check(save_game(false),"Native private115 portable save is written"):return
		var actual = JSON.parse_string(FileAccess.get_file_as_string(save_directory.path_join("voyage.json")))
		if not check(core.restore(actual).get("ok",false) and core.state.version=="0.115" and core.Arc115.work(core).reported and conserved(),"Actual115 save reloads with destination, discharged people and historical native account intact"):return
		finish(true)

func _initialize() -> void:
	var preview=Preview.new()
	preview.began=Time.get_ticks_msec()
	root.add_child(preview)
