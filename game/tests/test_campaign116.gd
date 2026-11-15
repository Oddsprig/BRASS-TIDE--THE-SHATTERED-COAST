extends SceneTree
## Selected transaction/save/UI fixture. Source, destination and contact-harbor
## positions are declared setups. No earned voyage, operating-cost or FPS claim.

class Preview extends "res://scripts/main.gd":
	var began: int = 0
	var out: String = ""
	var finished: bool = false
	var proof: Dictionary = {"checks":[],"declarations":[],"owner_profile_used":false,"scope":"Accepted115 checkpoint. Declared observation/harbor/late-route and enemy reference positions; actual native short coastal movement, client escrow, original carriers, authored short water-safe battle exit, settlement and private save/UI. Not an earned complete voyage, stock arena balance, FPS/audio or store media."}

	func _ready() -> void:
		qa_ocean066 = true
		super._ready()
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		out = OS.get_environment("GAME_TEST_ARTIFACTS").path_join("campaign116")
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
		print("CAMPAIGN116_DONE" if passed else "CAMPAIGN116_FAIL")
		get_tree().quit(0 if passed else 2)

	func check(okay: bool, label: String) -> bool:
		if finished:return false
		var bounded: bool = Time.get_ticks_msec()-began < 25000
		okay = okay and bounded
		proof.checks.append({"name":label,"passed":okay})
		write_json("progress.json",{"checks":proof.checks,"elapsed_ms":Time.get_ticks_msec()-began})
		print("CAMPAIGN116_CHECK %d %s %s"%[proof.checks.size(),str(okay),label])
		if not okay:
			push_error("CAMPAIGN116 "+label)
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
		check(frame != null and frame.save_png(out.path_join(name)) == OK,"Saved actual116 journal image: "+name)

	func same_load(left: Dictionary,right: Dictionary) -> bool:
		if left.size()!=right.size():return false
		for uid in left:
			if not right.has(uid) or not left[uid] is Dictionary or not right[uid] is Dictionary or left[uid].size()!=right[uid].size():return false
			for good in left[uid]:
				if not right[uid].has(good):return false
				var a: float=float(left[uid][good]);var b: float=float(right[uid][good])
				if not is_finite(a) or not is_finite(b) or absf(a-b)>0.000001:return false
		return true

	func native_job() -> Dictionary:
		return core.VoyageJobs._find(core.state,str(core.Arc116.work(core).get("priority",{}).get("jobId","")))

	func restore_value(value: Dictionary) -> bool:
		var result: Dictionary=core.restore(JSON.parse_string(JSON.stringify(value)))
		write_json("reload-result.json",result)
		return bool(result.get("ok",false))

	func stage() -> String:
		return str(core.Arc116.record(core).get("stage",""))

	func place_player(point: Dictionary) -> void:
		core.state.position={"x":float(point.x),"y":float(point.y)}
		core.state.path=[];core.state.destination=""
		core.NavalAI.observe(core.state)

	func quiet_leg(minimum: float) -> bool:
		var followed: Dictionary=core.Arc116.follow(core,true)
		if not followed.get("ok",false):write_json("follow-refusal.json",followed);return false
		var previous_player: Dictionary=core.state.position.duplicate(true)
		var previous_convoy: Dictionary=core.NavalAI._find_patrol(core.state,"patrol-1").duplicate(true)
		var actual_player: float=0.0
		var actual_convoy: float=0.0
		for i in range(80):
			if Time.get_ticks_msec()-began>21000:return false
			core.step(0.25)
			core.VoyageJobs.tick(core,0.25/float(core.DAY_SECONDS))
			var j: Dictionary=native_job()
			if j.is_empty() or j.get("failed",false):return false
			var convoy: Dictionary=core.NavalAI._find_patrol(core.state,"patrol-1")
			actual_player+=core.distance(core.state.position,previous_player)
			actual_convoy+=core.distance(convoy,previous_convoy)
			previous_player=core.state.position.duplicate(true)
			previous_convoy={"x":float(convoy.x),"y":float(convoy.y)}
			proof.actual_short_movement={"player":actual_player,"convoy":actual_convoy}
			if actual_player>=minimum and actual_convoy>=minimum and float(j.escort.accompaniedDistance)>=minimum and float(j.escort.playerDistance)>=minimum:return true
		return false

	func run() -> void:
		var path: String=OS.get_environment("CAMPAIGN_PRIOR_SAVE")
		if not check(FileAccess.file_exists(path) and FileAccess.get_sha256(path)==OS.get_environment("CAMPAIGN_PRIOR_SHA"),"Exact accepted115 checkpoint is used by SHA256"):return
		var restored: bool=restore_value(JSON.parse_string(FileAccess.get_file_as_string(path)))
		mode="campaign";paused=true;ui.close_modal();ui.build_hud()
		if not check(restored and stage()=="two_distress116" and core.state.stories.catalog.size()==14 and conserved(),"Accepted115 loads with the116 chapter and all fourteen chains"):return
		var previous: Dictionary=core.Arc115.record(core).work115.duplicate(true)
		var before_money: int=int(core.state.coins)
		if not check(not core.StoryOps.choose(core,core.Arc110.ID,"begin_withdrawal116").get("ok",false) and int(core.state.coins)==before_money,"An unfilled priority cannot fabricate the first operation or pay a reward"):return
		var client: Dictionary=core.fleet_owner("patrol-1")
		var p: Dictionary=core.NavalAI._find_patrol(core.state,"patrol-1")
		var second: Dictionary=core.NavalAI._find_patrol(core.state,"patrol-7")
		if not check(not client.is_empty() and float(client.tradeCargo)>0 and not p.is_empty() and not second.is_empty() and float(p.courseLength)>200,"Two original Reed cargo passages exist; no boats or load are seeded"):return
		# A declared late leg bounds world movement, retaining the actual water course.
		p.progress=1.0-200.0/float(p.courseLength);core.place_patrol(p);client.progress=p.progress
		proof.declarations.append("Existing patrol-1 begins on its final200 units of its existing water route. Player observation/reference positions are declared; no full-voyage claim.")
		place_player(second)
		if not check(core.Arc116.note_report(core,"patrol-7").get("ok",false),"The second original convoy can be noted independently at its observed position"):return
		place_player(p)
		if not check(core.Arc116.note_report(core,"patrol-1").get("ok",false) and core.Arc116.work(core).reports.size()==2,"Two distinct dated reports coexist without requiring both within the hail radius"):return
		var terms: Dictionary={}
		for q in core.Arc116.offers(core):
			if str(q.ownerId)=="patrol-1":terms=q.duplicate(true);break
		if not check(not terms.is_empty() and float(terms.escort.tradeQty)>0,"The chosen current loaded owner has a real affordable native offer"):return
		var bad: Dictionary=terms.duplicate(true);bad.reward=int(bad.reward)+1
		if not check(not core.Arc116.accept_priority(core,bad).get("ok",false) and native_job().is_empty() and conserved(),"Changed displayed terms refuse before any job or escrow is created"):return
		var client_coins: int=int(client.coins)
		var accepted: Dictionary=core.Arc116.accept_priority(core,terms,"moving")
		var w: Dictionary=core.Arc116.work(core)
		var job: Dictionary=native_job()
		if not check(accepted.get("ok",false) and not job.is_empty() and int(client.coins)==client_coins-int(job.escrow) and int(job.escrow)==int(terms.reward) and conserved(),"Native acceptance holds the chosen client's own coins exactly once"):return
		var ids: Array=w.priority.carrierUids.duplicate()
		if not check(ids==job.escort.carrierUids and w.priority.carrierCargo==job.escort.carrierCargo and w.reports.size()==2,"Priority binds original carrier identities and cargo; the other report is not a second contract"):return
		if not check(not core.Arc116.accept_priority(core,terms).get("ok",false) and core.state.voyageJobs.filter(func(j):return str(j.kind)=="escort").size()==1 and conserved(),"A repeated acceptance creates neither another escort nor a second fee"):return
		var active: Dictionary=snapshot()
		if not check(restore_value(active) and core.Arc116.work(core)==active.stories.chains.common_passage110.work116 and conserved(),"The actual active priority and native escrow survive full detached restore"):return
		client=core.fleet_owner("patrol-1") # Full restore publishes a new native owner dictionary.
		if not check(not core.Arc116.begin_withdrawal(core).get("ok",false) and core.Arc116.work(core).withdrawal.is_empty(),"Acceptance alone cannot establish withdrawal experience"):return
		core.Arc116.after_battle(core,"won",{}, {}, {})
		if not check(core.Arc116.work(core).encounters.is_empty() and conserved(),"An empty won result grants no physical evidence or assistance"):return
		if not check(quiet_leg(82.0),"Native following and coastal movement produce an actual accompanied quiet leg"):return
		job=native_job()
		proof.quiet_leg={"accompaniedDistance":job.escort.accompaniedDistance,"playerDistance":job.escort.playerDistance,"routeDistance":job.escort.routeDistance}
		await capture("priority.png")
		if finished:return
		if not check(core.StoryOps.choose(core,core.Arc110.ID,"begin_withdrawal116").get("ok",false) and stage()=="narrow_withdrawal116","The explicit choice opens the second operation after real first-leg work"):return
		w=core.Arc116.work(core)
		write_json("withdrawal-binding.json",{"uidsExact":w.withdrawal.carrierUids==ids,"originalCargo":w.priority.carrierCargo,"remainingCargo":w.withdrawal.carrierCargo,"basis":w.withdrawal.basis,"maximumQuantityTolerance":0.000001})
		if not check(w.withdrawal.carrierUids==ids and same_load(w.withdrawal.carrierCargo,w.priority.carrierCargo) and w.withdrawal.capacity==w.priority.capacityAtAcceptance and w.withdrawal.basis.kind=="quiet_leg","Withdrawal retains exact original IDs and hold capacity, with unchanged fractional cargo to one millionth of a lot"):return
		var corrupt: Dictionary=snapshot()
		corrupt.stories.chains.common_passage110.work116.priority.reward="free"
		if not check(not preload("res://scripts/campaign_validation116.gd").validate(corrupt).is_empty(),"Raw malformed priority accounting refuses before restore publication"):return
		if not check(not core.StoryOps.choose(core,core.Arc110.ID,"report_distress116").get("ok",false),"An active native escort cannot be discarded by the campaign report"):return
		if not check(core.Arc116.pursuers(core).is_empty(),"An unrelated distant Rust fleet is not reported as an actual pursuer"):return
		# Existing armed raider, reference chart placement only; no supplied HP/damage/result.
		var enemy: Dictionary=core.fleet_owner("patrol-3")
		var ep: Dictionary=core.NavalAI._find_patrol(core.state,"patrol-3")
		p=core.NavalAI._find_patrol(core.state,"patrol-1")
		var reference: Dictionary={}
		for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			var point: Dictionary={"x":float(p.x)+direction.x*1200.0,"y":float(p.y)+direction.y*1200.0}
			if core.Navigation.is_water(core.nav,float(point.x),float(point.y),24.0):reference=point;break
		if not check(not enemy.is_empty() and enemy.get("active",false) and not reference.is_empty(),"An existing crewed armed raider and water-safe encounter reference are available"):return
		ep.x=reference.x;ep.y=reference.y;core.NavalAI.observe(core.state)
		proof.declarations.append({"kind":"declared_existing_enemy_chart_position","ownerId":str(enemy.id),"position":reference,"distanceFromCarrier":core.distance(ep,p),"no_new_actor_or_pursuit_order":true})
		var allies: Array=client.boats.filter(func(b):return not b.sunk)
		var enemies: Array=enemy.boats.filter(func(b):return not b.sunk)
		var specs: Array=enemies.map(func(b):return b.spec.duplicate(true))
		var mission: Dictionary=core.EscortOps._mission(core,client,"escort")
		mission.allyUids=allies.map(func(b):return str(b.uid))
		mission.exit.x=740.0;mission.exit.y=850.0;mission.exit.radius=140.0
		job=native_job();job.escort.battlePending=true;job.escort.interceptions=int(job.escort.get("interceptions",0))+1
		var context: Dictionary={"kind":"escort","ownerId":str(enemy.id),"allyOwnerId":str(client.id),"escortEvent":str(job.id),"escortJobId":str(job.id)}
		proof.declarations.append("Native post-start battlePending/interception flags and authored short water-safe exit; no threaded UI-start, stock arena or supplied outcome claim.")
		var physical: Dictionary=Battle.create({"fleet":core.active_fleet()+allies,"enemyFleet":enemies,"mission":mission,"seed":116,"islands":[]})
		physical.chartPosition=core.state.position.duplicate(true);physical.world064=core.world_location064().world064
		if not check(str(physical.get("startError","")).is_empty() and physical.get("result")==null and physical.convoy.uids==ids,"Native battle deploys the same original loaded boats and actual enemy"):return
		var starts: Dictionary={}
		for uid in ids:
			var actor: Dictionary=physical.convoy.actors[uid]
			starts[uid]={"x":float(actor.x),"y":float(actor.y)}
		while physical.result==null and float(physical.time)<180.0 and Time.get_ticks_msec()-began<23000:
			Battle.update(physical,1.0/30.0)
		Battle.update(physical,0)
		var moved: bool=true
		for uid in ids:
			var actor: Dictionary=physical.convoy.actors[uid]
			moved=moved and actor.get("battleEscaped",false) and core.distance(actor,starts[uid])>0.01
		if not check(physical.result=="won" and moved,"Native simulation physically moves the original carriers through their exit"):return
		var cargo_before: Dictionary=client.cargo.duplicate(true)
		var report: Dictionary=core.battle_settled(str(physical.result),specs,context,physical)
		w=core.Arc116.work(core)
		proof.physical={"source":physical.get("engagementSource060",""),"sequence":physical.get("campaignSequence111",0),"simulatedSeconds":physical.time,"nativeConvoy":report.get("convoy",{}),"supplied_positive_outcome":false}
		if not check(core.Arc116.counts(core).escaped==ids.size() and w.withdrawal.lastSequence>w.withdrawal.battleFloor and client.cargo==cargo_before and conserved(),"Canonical new settlement credits only phase-two physical exits and retains actual cargo"):return
		var settled: Dictionary=w.duplicate(true)
		var settled_money: int=int(core.state.coins)
		core.battle_settled(str(physical.result),specs,context,physical)
		if not check(core.Arc116.work(core)==settled and int(core.state.coins)==settled_money and conserved(),"Cached settlement repeats neither fee, battle evidence nor carrier outcomes"):return
		if not check(core.Arc116.delivery_pending(core) and not core.Arc116.protection_gate(core).get("ok",false),"The first credited exit retains delivery work while the native duplicate-credit guard stays active"):return
		# Continue actual remaining short route; native docking sells the real load.
		var continuing: Dictionary=core.Arc116.follow(core,true)
		if not check(continuing.get("ok",false),"Native following remains available for the still-carried original delivery"):return
		for i in range(80):
			if Time.get_ticks_msec()-began>23500:break
			core.step(0.25);core.VoyageJobs.tick(core,0.25/float(core.DAY_SECONDS))
			job=native_job()
			if job.is_empty() or job.get("failed",false) or job.escort.get("arrived",false):break
		job=native_job();write_json("arrival-state.json",snapshot())
		if not check(not job.is_empty() and not job.get("failed",false) and job.escort.get("arrived",false) and conserved(),"Actual remaining native movement, docking and sale complete the protected delivery"):return
		var target: String=str(job.targetPort)
		locate(target)
		var coins: int=int(core.state.coins);var fee: int=int(job.reward)
		var closure: Dictionary=core.settle_voyage_job(str(job.id))
		w=core.Arc116.work(core)
		if not check(closure.get("ok",false) and w.priority.status=="paid" and int(core.state.coins)==coins+fee and native_job().is_empty() and conserved(),"Native delivery settlement releases the original held fee exactly once"):return
		if not check(core.Arc116.counts(core).arrived==ids.size() and w.aid.is_empty(),"Actual original arrivals are distinct from physical exits and no unobserved warden aid is claimed"):return
		await capture("withdrawal.png")
		if finished:return
		if not check(core.StoryOps.choose(core,core.Arc110.ID,"report_distress116").get("ok",false) and w.reported and stage()=="distress_account116","Explicit report retains the physical and financial account after native closure"):return
		if not check(core.StoryOps.choose(core,core.Arc110.ID,"next_funding116").get("ok",false) and stage()=="who_pays117" and core.Arc115.record(core).work115==previous,"The locked117 lead preserves the accepted witness people and account"):return
		if not check(save_game(false),"Actual private116 save is written by the game"):return
		var actual = JSON.parse_string(FileAccess.get_file_as_string(save_directory.path_join("voyage.json")))
		if not check(restore_value(actual) and core.state.version=="0.116" and core.Arc116.work(core).reported and conserved(),"Actual116 save fully restores the report, original carriers and once-paid fee"):return
		finish(true)

func _initialize() -> void:
	var preview=Preview.new();preview.began=Time.get_ticks_msec();root.add_child(preview)
