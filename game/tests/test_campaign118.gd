extends SceneTree
## Selected transaction/save/UI fixture. Source, destination and contact-harbor
## positions are declared setups. No earned voyage, operating-cost or FPS claim.

class Preview extends "res://scripts/main.gd":
	var began: int = 0
	var out: String = ""
	var finished: bool = false
	var proof: Dictionary = {"checks":[],"declarations":[],"owner_profile_used":false,"scope":"Exact accepted117 checkpoint. Declared reference-harbor positions; actual native legal access, finite paid fuel purchase and published-state receipt, negative transactions, current claimant availability and explicit unresolved Brass report, optional Tobin, private full save and actual UI. No earned full voyage, positive claimant escort or cordon battle when unavailable, invented history, actual repairs, whole-world payroll timing, FPS/audio or store media."}

	func _ready() -> void:
		qa_ocean066 = true
		super._ready()
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		out = OS.get_environment("GAME_TEST_ARTIFACTS").path_join("campaign118")
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
		print("CAMPAIGN118_DONE" if passed else "CAMPAIGN118_FAIL")
		get_tree().quit(0 if passed else 2)

	func check(okay: bool, label: String) -> bool:
		if finished:return false
		var bounded: bool = Time.get_ticks_msec()-began < 25000
		okay = okay and bounded
		proof.checks.append({"name":label,"passed":okay})
		write_json("progress.json",{"checks":proof.checks,"elapsed_ms":Time.get_ticks_msec()-began})
		print("CAMPAIGN118_CHECK %d %s %s"%[proof.checks.size(),str(okay),label])
		if not okay:
			push_error("CAMPAIGN118 "+label)
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
		check(frame != null and frame.save_png(out.path_join(name)) == OK,"Saved actual118 journal image: "+name)

	func restore_value(value: Dictionary) -> bool:
		var result: Dictionary=core.restore(JSON.parse_string(JSON.stringify(value)))
		write_json("reload-result.json",result)
		return bool(result.get("ok",false))


	func chosen(choice: String) -> bool:
		var result: Dictionary=core.StoryOps.choose(core,core.Arc110.ID,choice)
		if not result.get("ok",false):write_json("choice-refusal.json",{"choice":choice,"result":result})
		return bool(result.get("ok",false))

	func run() -> void:
		var validator=preload("res://scripts/campaign_validation118.gd")
		if not check(validator.validate({"day":1}).is_empty(),"An absent optional118 book remains absent for legacy state"):return
		var path: String=OS.get_environment("CAMPAIGN_PRIOR_SAVE")
		if not check(FileAccess.file_exists(path) and FileAccess.get_sha256(path)==OS.get_environment("CAMPAIGN_PRIOR_SHA"),"The exact accepted117 checkpoint is read by SHA256"):return
		if not check(restore_value(JSON.parse_string(FileAccess.get_file_as_string(path))) and core.Arc110.record(core).stage=="fuel_has_owners118" and core.state.stories.catalog.size()==14 and conserved(),"Accepted117 restores with118 and the preserved fourteen-chain catalog"):return
		mode="campaign";paused=true;ui.close_modal();ui.build_hud()
		var earlier: Dictionary=core.Arc117.work(core).duplicate(true)
		locate("naphtha_bay")
		if not check(chosen("begin_fuel118") and core.Arc110.record(core).stage=="fuel_work118","The Naphtha request opens through its real story choice"):return
		if not check(not core.Arc118.choice_gate(core,"report_fuel118").get("ok",false),"Existing working-tank fuel is not a fresh purchase receipt"):return
		var coins: int=int(core.state.coins)
		var total: int=core.Money.total(core.state)
		var entry: Dictionary=core.Arc118.passage_quote(core)
		if not check(entry.get("ok",false) and str(entry.get("port",""))=="naphtha_bay" and entry.get("mode","")=="legal" and int(entry.get("cost",-1))==0 and int(core.state.coins)==coins and core.Money.total(core.state)==total,"Actual ordinary legal Naphtha entry is quoted at zero without moving coins"):return
		if not check(core.Arc118.secure_passage(core).get("ok",false) and int(core.state.coins)==coins and conserved(),"Securing already-legal entry does not invent a paid cordon or charge"):return
		if not check(not core.Arc118.choice_gate(core,"report_fuel118").get("ok",false),"Passage permission alone cannot complete fuel ownership"):return
		locate("brass_haven")
		if not check(not core.Arc118.buy_fuel(core,5).get("ok",false) and int(core.state.coins)==coins and conserved(),"A purchase request at the wrong actual harbor is refused without spending"):return
		locate("naphtha_bay")
		if not check(not core.Arc118.buy_fuel(core,0).get("ok",false) and not core.Arc118.buy_fuel(core,-1).get("ok",false) and int(core.state.coins)==coins,"Zero and negative requested fuel quantities cannot produce a receipt"):return
		var q: Dictionary=core.Arc118.fuel_quote(core,5)
		if not check(q.get("ok",false) and int(q.get("qty",0))==5 and int(q.get("price",0))>0 and int(q.get("cost",0))==5*int(q.get("price",0)) and int(core.state.coins)==coins and conserved(),"A current finite fuel quote discloses quantity, real unit price and whole-coin cost"):return
		var before: Dictionary=core.Arc118.before_trade(core,"naphtha_bay","fuel",5,"buy")
		core.Arc118.after_trade(core,before,{"ok":true,"qty":5,"total":q.cost,"coins":q.cost})
		if not check(not core.Arc118.choice_gate(core,"report_fuel118").get("ok",false) and int(core.state.coins)==coins and conserved(),"A success-shaped callback without actual goods and coin deltas cannot claim a purchase"):return
		var dock: Dictionary=core.port("naphtha_bay")
		var seller: int=int(dock.cash)
		var stock: float=float(dock.stocks.get("fuel",0))
		var owned: float=float(core.state.cargo.get("fuel",0))
		var result: Dictionary=core.Arc118.buy_fuel(core,5)
		dock=core.port("naphtha_bay")
		if not check(result.get("ok",false) and int(core.state.coins)==coins-int(q.cost) and int(dock.cash)==seller+int(q.cost) and is_equal_approx(float(dock.stocks.fuel),stock-5) and is_equal_approx(float(core.state.cargo.fuel),owned+5) and conserved(),"The actual native purchase transfers five fuel and exact coins between the captain and Naphtha seller"):return
		if not check(core.Arc118.choice_gate(core,"report_fuel118").get("ok",false) and not core.Arc118.work(core).get("fuel",{}).is_empty(),"The purchase hook reacquires the published story record and admits the actual fuel report"):return
		var receipt: Dictionary=core.Arc118.work(core).duplicate(true)
		core.Arc118.after_trade(core,before,result)
		if not check(core.Arc117.work(core)==earlier and core.Arc118.work(core)==receipt and conserved(),"Replaying the purchase observer cannot duplicate its record or rewrite117 funding"):return
		proof.fuel={"quantity":5,"price":int(q.price),"cost":int(q.cost),"sellerBefore":seller,"sellerAfter":int(dock.cash),"stockBefore":stock,"stockAfter":float(dock.stocks.fuel),"ownedBefore":owned,"ownedAfter":float(core.state.cargo.fuel),"passage":entry}
		var fractional: Dictionary=snapshot()
		fractional.stories.chains.common_passage110.work118.fuel.cost=float(fractional.stories.chains.common_passage110.work118.fuel.cost)+0.5
		if not check(not validator.validate(fractional).is_empty(),"A fractional coin invoice cannot survive raw fuel receipt preflight"):return
		var foreign: Dictionary=snapshot()
		foreign.stories.chains.common_passage110.work118.fuel.port="brass_haven"
		if not check(not validator.validate(foreign).is_empty(),"Another harbor cannot be substituted into the Naphtha purchase receipt"):return
		if not check(restore_value(snapshot()) and core.Arc118.choice_gate(core,"report_fuel118").get("ok",false) and conserved(),"The actual paid fuel receipt survives full JSON restore"):return
		await capture("fuel.png")
		if finished:return
		if not check(chosen("report_fuel118") and core.Arc110.record(core).stage=="fuel_account118","Only actual fresh paid fuel can be reported"):return
		locate("brass_haven")
		coins=int(core.state.coins)
		var optional_start: Dictionary=core.StoryOps.start(core,"tobin_clause111")
		write_json("optional-start-result.json",optional_start)
		if not check(optional_start.get("ok",false),"Tobin's previously unstarted optional chain begins through its actual harbor contact"):return
		if not check(core.StoryOps.choose(core,"tobin_clause111","read_seizure_clause111").get("ok",false) and core.StoryOps.choose(core,"tobin_clause111","finish_clause111").get("ok",false) and core.state.stories.chains.tobin_clause111.stage=="later_tobin118","The real111 conversation is retained before Tobin's later118 discussion"):return
		var later: Dictionary=snapshot()
		if not check(core.StoryOps.choose(core,"tobin_clause111","leave_tobin118").get("ok",false) and core.state.stories.chains.tobin_clause111.done and int(core.state.coins)==coins and conserved(),"Tobin's later conversation can be left without commissioning or buying anything"):return
		if not check(restore_value(later),"The separate optional-discussion probe restores its complete private pre-choice checkpoint"):return
		if not check(core.StoryOps.choose(core,"tobin_clause111","discuss_funding118").get("ok",false) and core.state.stories.chains.tobin_clause111.stage=="tobin_funding118" and int(core.state.coins)==coins and conserved(),"Tobin discusses the actual117 funding account without a new payment or commission"):return
		if not check(core.StoryOps.choose(core,"tobin_clause111","finish_tobin118").get("ok",false) and core.state.stories.chains.tobin_clause111.done and core.state.stories.chains.tobin_clause111.flags.has("clause_heard111"),"Tobin's later completion preserves his original111 conversation history"):return
		if not check(chosen("next_warrant118") and chosen("begin_warrant118") and core.Arc110.record(core).stage=="warrant_work118","Last Warrant opens at Brass through its actual consecutive choices"):return
		var offers: Array=core.Arc118.warrant_offers(core)
		proof.warrantCoverage={"currentEligibleOffers":offers.size(),"coverage":"Current availability and explicit unresolved account only. Positive original-claimant escort, hostile cordon/interdiction and culpable-crew evidence are not established by this retained checkpoint."}
		if not check(offers.is_empty() and core.Arc118.active(core).is_empty() and not core.Arc118.choice_gate(core,"report_warrant118").get("ok",false) and core.EscortOps.contracted(core).is_empty(),"No eligible current loaded Brass convoy is fabricated or credited as a rescue"):return
		if not check(not core.Arc118.accept_warrant(core,{"ok":true,"offer":{"id":"invented-claimant"}}).get("ok",false) and core.EscortOps.contracted(core).is_empty() and conserved(),"A fabricated claimant offer cannot create a native escort or escrow"):return
		locate("anvil_dock")
		if not check(not core.Arc118.choice_gate(core,"report_unresolved118").get("ok",false),"An unresolved claimant report requires the actual Brass debrief"):return
		locate("brass_haven")
		if not check(core.Arc118.choice_gate(core,"report_unresolved118").get("ok",false) and int(core.state.coins)==coins and conserved(),"Explicit unresolved reporting is available at Brass without fake cargo, people or payment"):return
		await capture("warrant.png")
		if finished:return
		if not check(chosen("report_unresolved118") and core.Arc110.record(core).stage=="warrant_account118" and not core.Arc110.record(core).get("done",false),"The explicit unresolved118 account does not silently end the main campaign"):return
		if not check(chosen("next_passage118") and core.Arc110.record(core).stage=="common_passage119" and core.Arc117.work(core)==earlier and conserved(),"118 ends at the locked119 lead while preserving earlier paid funding"):return
		if not check(save_game(false),"The actual private118 save is written by the game"):return
		var actual=JSON.parse_string(FileAccess.get_file_as_string(save_directory.path_join("voyage.json")))
		if not check(restore_value(actual) and core.state.version=="0.118" and core.state.stories.chains.tobin_clause111.done and core.Arc110.record(core).stage=="common_passage119" and conserved(),"The actual118 save fully restores fuel, unresolved request and optional history"):return
		finish(true)

func _initialize() -> void:
	var preview=Preview.new();preview.began=Time.get_ticks_msec();root.add_child(preview)
