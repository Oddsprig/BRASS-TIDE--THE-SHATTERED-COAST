extends SceneTree
## Selected transaction/save/UI fixture. Source, destination and contact-harbor
## positions are declared setups. No earned voyage, operating-cost or FPS claim.

class Preview extends "res://scripts/main.gd":
	var began: int = 0
	var out: String = ""
	var finished: bool = false
	var proof: Dictionary = {"checks":[],"declarations":[],"owner_profile_used":false,"scope":"Actual113 checkpoint; declared harbor positions; finite property release, original native raid/recovery, short controlled harbor arrival, optional Cass contact, persistence and actual UI. Not an earned full voyage or store media."}

	func _ready() -> void:
		qa_ocean066 = true
		super._ready()
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		out = OS.get_environment("GAME_TEST_ARTIFACTS").path_join("campaign114")
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
		print("CAMPAIGN114_DONE" if passed else "CAMPAIGN114_FAIL")
		get_tree().quit(0 if passed else 2)

	func check(okay: bool, label: String) -> bool:
		if finished:return false
		var bounded: bool = Time.get_ticks_msec()-began < 25000
		okay = okay and bounded
		proof.checks.append({"name":label,"passed":okay})
		write_json("progress.json",{"checks":proof.checks,"elapsed_ms":Time.get_ticks_msec()-began})
		print("CAMPAIGN114_CHECK %d %s %s"%[proof.checks.size(),str(okay),label])
		if not okay:
			push_error("CAMPAIGN114 "+label)
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
		check(frame != null and frame.save_png(out.path_join(name)) == OK,"Saved actual114 journal image: "+name)

	func run() -> void:
		var prior_path: String = OS.get_environment("CAMPAIGN_PRIOR_SAVE")
		if not check(FileAccess.file_exists(prior_path) and FileAccess.get_sha256(prior_path)==OS.get_environment("CAMPAIGN_PRIOR_SHA"),"Uses the exact accepted113 checkpoint by SHA256"):return
		var prior = JSON.parse_string(FileAccess.get_file_as_string(prior_path))
		var loaded: Dictionary = core.restore(prior)
		mode="campaign";paused=true;ui.close_modal();ui.build_hud()
		if not check(loaded.get("ok",false) and conserved() and core.Arc110.record(core).stage=="bought_route114" and core.state.stories.catalog.size()==13,"Actual113 chapter and earlier history restore into the appended114 catalog"):return
		var earlier: Dictionary = core.Arc113.work(core).duplicate(true)
		locate("rust_anchorage")
		var permit: Dictionary = core.Politics.permit(core,"service")
		if not permit.get("ok",false):permit=core.Politics.parley(core)
		if not check(permit.get("ok",false) and conserved(),"Actual native access terms are paid when Rust requires them"):return
		var begun: Dictionary = core.StoryOps.choose(core,core.Arc110.ID,"investigate_route114")
		if not check(begun.get("ok",false) and core.Arc110.record(core).stage=="route_work114" and core.Arc113.work(core)==earlier,"Cass's admission begins114 without rewriting the accepted material delivery"):return
		if not check(core.StoryOps.start(core,"cass_price114").get("ok",false) and core.StoryOps.choose(core,"cass_price114","ask_cass_knowledge114").get("ok",false) and core.StoryOps.choose(core,"cass_price114","finish_cass_price114").get("ok",false) and core.state.stories.chains.cass_price114.done,"Optional Cass conversation records knowledge without a payment or main-story gate"):return
		var empty: Dictionary = snapshot()
		var coins: int = int(core.state.coins)
		if not check(core.StoryOps.choose(core,core.Arc110.ID,"report_unrecovered114").get("ok",false) and int(core.state.coins)==coins and conserved(),"Explicit unrecovered closure invents no property, aid or reward"):return
		if not check(core.restore(empty).get("ok",false),"The open114 undertaking restores after the explicit no-recovery branch"):return
		var owner: Dictionary = core.fleet_owner("patrol-6")
		var patrol: Dictionary = core.NavalAI._find_patrol(core.state,"patrol-6")
		if not check(not owner.is_empty() and not patrol.is_empty() and owner.active and owner.homePort=="rust_anchorage" and owner.boats.any(func(b):return not b.get("sunk",false)),"Reference encounter uses an existing surviving Rust raider and original hulls"):return
		# Declare an observed reference approach, not earned pursuit or NPC route AI.
		patrol.x=core.state.position.x;patrol.y=core.state.position.y
		core.NavalAI.observe(core.state)
		proof.declarations.append("Existing patrol-6 positioned at the Rust reference approach for a current sighting; no earned pursuit or NPC-route claim.")
		if not check(core.Arc114.bind(core,"patrol-6").get("ok",false) and core.Arc114.work(core).ownerId=="patrol-6","A current original Rust owner is bound once, without a new actor or commission"):return
		var bound: Dictionary = snapshot()
		var stock: Dictionary = core.port("rust_anchorage")
		# Finite paid lot precondition: existing harbor timber is purchased using
		# this owner's existing coins. This is not a claim of an earned NPC seizure.
		var amount: float = minf(4,float(stock.stocks.timber))
		var invoice: int = ceili(amount*core.Economy.price(stock,"timber","buy"))
		if not check(amount>0 and int(owner.coins)>=invoice and core.Money.move(owner,"coins",stock,"cash",invoice,"Declared114 reference lot purchase",core.state.moneyLog),"Declared lot precondition purchases existing timber with the existing owner's purse"):return
		stock.stocks.timber-=amount;owner.cargo.timber=float(owner.cargo.get("timber",0))+amount
		proof.declarations.append("Paid finite harbor timber allocated to the existing raider for release-transaction coverage; not NPC theft provenance.")
		var q: Dictionary = core.Arc114.release_quote(core)
		if not check(q.get("ok",false) and q.good=="timber" and q.qty>0 and q.cost==ceili(float(q.qty)*float(q.unitPrice)),"Release terms quote actual held property, its current native price and finite quantity"):return
		var bad: Dictionary = q.duplicate(true);bad.cost=int(bad.cost)+1
		var before_coins: int = int(core.state.coins);var before_owner: int=int(owner.coins)
		var before_cargo: float = float(core.state.cargo.get(str(q.good),0));var before_lot: float=float(owner.cargo.get(str(q.good),0))
		if not check(not core.Arc114.release(core,bad).get("ok",false) and int(core.state.coins)==before_coins and float(owner.cargo.get(str(q.good),0))==before_lot,"A changed release quotation refuses without moving goods or coins"):return
		var release: Dictionary = core.Arc114.release(core,q)
		if not check(release.get("ok",false) and before_coins-int(core.state.coins)==int(q.cost) and int(owner.coins)-before_owner==int(q.cost) and absf(float(core.state.cargo.get(str(q.good),0))-before_cargo-float(q.qty))<0.000001 and absf(before_lot-float(owner.cargo.get(str(q.good),0))-float(q.qty))<0.000001 and conserved(),"Actual release transfers the finite original lot and its full payment between the real purses"):return
		if not check(not core.Arc114.release(core,q).get("ok",false),"The same release cannot be bought again"):return
		if not check(core.StoryOps.choose(core,core.Arc110.ID,"report_property114").get("ok",false) and write_json("released-state.json",snapshot()),"The actual completed release supports its explicit report without a claimed raid"):return
		await capture("release.png")
		if finished:return
		if not check(core.restore(bound).get("ok",false) and conserved(),"Original bound owner restores after the separate paid-release branch"):return
		owner=core.fleet_owner("patrol-6")
		var context: Dictionary={"kind":"patrol","id":str(owner.id),"ownerId":str(owner.id),"name":"Declared114 native reference encounter"}
		if not check(not core.Arc114.choice_gate(core,"report_property114").get("ok",false),"A bound target alone does not establish a recovery"):return
		# Real native reference fight; no supplied damage, death or result.
		var physical: Dictionary = Battle.create({"fleet":core.active_fleet(),"enemyFleet":owner.boats.filter(func(b):return not b.get("sunk",false)),"seed":111,"islands":[]})
		physical.chartPosition=core.state.position.duplicate(true);physical.world064=core.world_location064().world064
		while physical.result==null and float(physical.time)<180 and Time.get_ticks_msec()-began<25000:Battle.update(physical,1.0/30.0)
		Battle.update(physical,0)
		proof.reference_combat={"result":physical.result,"simulatedSeconds":physical.time,"not_rendered_fps_or_reachability":true}
		if not check(physical.result=="won","Actual original native reference combat reaches its own result"):return
		var result: Dictionary = core.battle_settled(str(physical.result),owner.boats.map(func(b):return b.spec),context,physical)
		var w: Dictionary = core.Arc114.work(core)
		if not check(result.get("wrecks",[]).size()>0 and w.wrecks.size()>0 and not core.Arc114.choice_gate(core,"report_property114").get("ok",false),"Native settlement binds an original wreck; victory alone supplies no returned property"):return
		var id: String = str(w.wrecks[0].id)
		var wreck: Dictionary = core.Salvage.find_wreck(core.state,id)
		var part: String = ""
		for uid in wreck.get("sourceModuleCondition",{}).get("items",{}):
			if str(wreck.sourceModuleCondition.items[uid].family)!="pumps":part=str(uid);break
		if not check(not part.is_empty() and core.Exploration.spare_crew(core.state)>=1,"Original wreck contains a fitting and an actual spare sailor can recover it"):return
		var request: Dictionary={"itemUids":[part],"carrierUid":str(core.state.fleet[0].uid),"acceptForfeiture":true}
		var recovery: Dictionary = core.recover_wreck(id,"gear","",0,request)
		if not check(recovery.get("ok",false) and int(recovery.get("wagesPaid",0))>0 and core.Arc114.work(core).recoveries.size()==1 and conserved(),"Native paid recovery transfers an original fitting; its crew time and wages remain real costs"):return
		if not check(not core.Arc114.choice_gate(core,"report_property114").get("ok",false),"Original property at Rust still needs physical withdrawal to a different lawful harbor"):return
		# Declare only the start of a short real final approach, not the full voyage.
		var harbor: Dictionary = core.port("anvil_dock")
		var clearance: float = core.Routes.clearance(core)
		var endpoint: Dictionary = core.Routes.endpoint(core,harbor,clearance)
		var route: Array = core.cached_path(core.state.position,endpoint,clearance)
		if not check(route.size()>1,"Anvil has a real navigable native return approach"):return
		var end: Vector2=Vector2(float(endpoint.x),float(endpoint.y));var previous: Dictionary=route[route.size()-2]
		var direction: Vector2=Vector2(float(previous.x),float(previous.y))-end
		var reference_start: Vector2=end+direction.normalized()*minf(20,direction.length()*0.5)
		core.state.position={"x":reference_start.x,"y":reference_start.y};core.state.path=[];core.state.destination=""
		proof.declarations.append("Declared final Anvil approach, followed by native chart_course and actual movement/arrival. No full Rust-to-Anvil voyage claim.")
		if not check(not core.Arc114.choice_gate(core,"report_property114").get("ok",false),"Harbor proximity without a later native arrival cannot complete raid withdrawal"):return
		var plotted: Dictionary = core.chart_course(harbor,"anvil_dock")
		if not check(plotted.get("ok",false) and not core.state.path.is_empty(),"Native course starts the short physical harbor return"):return
		core.step(minf(4.0,20.0/maxf(1,core.travel_speed())+0.08))
		if not check(core.state.path.is_empty() and str(core.current_port().get("id",""))=="anvil_dock" and core.Arc114.choice_gate(core,"report_property114").get("ok",false) and write_json("raid-arrival-state.json",snapshot()),"Actual native arrival and retained original fitting allow the separate raid return report"):return
		var invalid: Dictionary = snapshot();invalid.stories.chains[core.Arc110.ID].work114.ownerId="missing-owner114"
		if not check(not preload("res://scripts/campaign_validation114.gd").validate(invalid).is_empty(),"Unknown original ownership is rejected before restore publication"):return
		if not check(core.StoryOps.choose(core,core.Arc110.ID,"report_property114").get("ok",false) and core.Arc114.work(core).reported and conserved(),"Explicit returned-property report records the actual native raid/recovery/arrival"):return
		await capture("recovery.png")
		if finished:return
		if not check(core.StoryOps.choose(core,core.Arc110.ID,"next_witnesses114").get("ok",false) and core.Arc110.record(core).stage=="names_on_paper115" and core.Arc113.work(core)==earlier,"The campaign reaches the locked115 witness lead while earlier delivered material history remains unchanged"):return
		if not check(save_game(false),"Native private114 portable save is written"):return
		var saved_path: String=save_directory.path_join("voyage.json")
		var saved = JSON.parse_string(FileAccess.get_file_as_string(saved_path))
		if not check(saved is Dictionary and str(saved.get("version",""))=="0.114" and core.restore(saved).get("ok",false) and core.Arc114.work(core).reported and conserved(),"Actual private114 portable save restores the retained native property account"):return
		finish(true)

func _initialize() -> void:
	var preview=Preview.new()
	preview.began=Time.get_ticks_msec()
	root.add_child(preview)
