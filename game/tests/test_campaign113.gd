extends SceneTree
## Selected transaction/save/UI fixture. Source, destination and contact-harbor
## positions are declared setups. No earned voyage, operating-cost or FPS claim.

class Preview extends "res://scripts/main.gd":
	var began: int = 0
	var out: String = ""
	var finished: bool = false
	var proof: Dictionary = {"checks":[],"declarations":[],"owner_profile_used":false,"scope":"Actual112 checkpoint; declared harbor positions; native funded material order, inventory/fee/refund, optional contact, persistence and actual UI. Not an earned full voyage or store media."}

	func _ready() -> void:
		qa_ocean066 = true
		super._ready()
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		out = OS.get_environment("GAME_TEST_ARTIFACTS").path_join("campaign113")
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
		print("CAMPAIGN113_DONE" if passed else "CAMPAIGN113_FAIL")
		get_tree().quit(0 if passed else 2)

	func check(okay: bool, label: String) -> bool:
		if finished:return false
		var bounded: bool = Time.get_ticks_msec()-began < 25000
		okay = okay and bounded
		proof.checks.append({"name":label,"passed":okay})
		write_json("progress.json",{"checks":proof.checks,"elapsed_ms":Time.get_ticks_msec()-began})
		print("CAMPAIGN113_CHECK %d %s %s"%[proof.checks.size(),str(okay),label])
		if not okay:
			push_error("CAMPAIGN113 "+label)
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
		check(frame != null and frame.save_png(out.path_join(name)) == OK,"Saved actual113 journal image: "+name)

	func run() -> void:
		var prior_path: String = OS.get_environment("CAMPAIGN_PRIOR_SAVE")
		var expected_sha: String = OS.get_environment("CAMPAIGN_PRIOR_SHA")
		if not check(not prior_path.is_empty() and FileAccess.file_exists(prior_path) and FileAccess.get_sha256(prior_path)==expected_sha,"Uses the exact accepted112 native checkpoint by SHA256"):return
		var prior = JSON.parse_string(FileAccess.get_file_as_string(prior_path))
		var restored: Dictionary = core.restore(prior)
		mode="campaign";paused=true;ui.close_modal();ui.build_hud()
		if not check(restored.get("ok",false) and conserved() and core.Arc110.record(core).stage=="useful_enemy113" and core.state.stories.catalog.size()==12,"Actual112 state restores with its report and the appended Mara catalog"):return
		var earlier: Dictionary = core.Arc112.work(core).duplicate(true)
		locate("cinder_quay")
		var begun: Dictionary = core.StoryOps.choose(core,core.Arc110.ID,"accept_material_request113")
		if not check(begun.get("ok",false) and core.Arc110.record(core).stage=="materials_work113" and core.Arc112.work(core)==earlier,"Native story choice starts113 without altering the accepted112 carrier report"):return
		locate("anvil_dock")
		core.Contacts.visit(core.state,core.current_port(),core.state.day)
		var request: Dictionary = snapshot()
		var before_unfilled: int = int(core.state.coins)
		var unfilled: Dictionary = core.StoryOps.choose(core,core.Arc110.ID,"report_materials113")
		if not check(unfilled.get("ok",false) and core.Arc113.work(core).status=="unfilled" and core.Arc113.work(core).reported and int(core.state.coins)==before_unfilled and conserved(),"Explicit unfilled report grants no cargo, fee or aid credit"):return
		if not check(core.restore(request).get("ok",false) and conserved(),"Private unfilled branch returns through a full native checkpoint restore"):return
		var offer: Dictionary = core.Arc113.offer(core)
		if not check(not offer.is_empty() and offer.kind=="freight" and offer.targetPort=="cinder_quay" and offer.freight.good=="supplies" and offer.freight.qty>0 and offer.freight.qty<=8,"Current finite kit order is a real native-priced funded freight quote"):return
		var origin: Dictionary = core.port("anvil_dock")
		var target: Dictionary = core.port("cinder_quay")
		var initial_stock: float = float(origin.stocks.supplies)
		var initial_government: int = int(origin.governmentPurse)
		var initial_business: int = int(origin.cash)
		var initial_player: int = int(core.state.coins)
		var changed: Dictionary = offer.duplicate(true)
		changed.reward = int(changed.reward)+1
		var refused: Dictionary = core.Arc113.accept(core,changed)
		if not check(not refused.get("ok",false) and core.Arc113.work(core).is_empty() and float(origin.stocks.supplies)==initial_stock and int(origin.governmentPurse)==initial_government and conserved(),"Changed quote refuses without consuming stock or funding a job"):return
		var accepted: Dictionary = core.Arc113.accept(core,offer)
		var w: Dictionary = core.Arc113.work(core)
		var id: String = str(w.get("jobId",""))
		var job: Dictionary = core.VoyageJobs._find(core.state,id)
		var qty: float = float(w.get("qty",0))
		if not check(accepted.get("ok",false) and not job.is_empty() and w.status=="carried" and qty>0 and absf(initial_stock-float(origin.stocks.supplies)-qty)<0.000001 and int(core.state.coins)==initial_player and conserved(),"Native acceptance removes actual source kits and seals the load without charging the player for public stock"):return
		if not check(initial_government-int(origin.governmentPurse)==int(job.reward)+int(job.materialInvoice) and int(origin.cash)-initial_business==int(job.materialInvoice) and int(job.escrow)==int(job.reward),"Actual government pays material invoice and escrow; the existing business receives the invoice"):return
		var active: Dictionary = snapshot()
		var too_early: Dictionary = core.StoryOps.choose(core,core.Arc110.ID,"report_materials113")
		if not check(not too_early.get("ok",false) and not w.reported,"Carried public freight cannot become a completed narrative report"):return
		var withdrawn: Dictionary = core.settle_voyage_job(id,true)
		if not check(withdrawn.get("ok",false) and core.Arc113.work(core).status=="withdrawn" and core.VoyageJobs._find(core.state,id).is_empty() and conserved(),"Native abandonment refunds/unloads the real consignment and records withdrawal without delivery credit"):return
		if not check(core.restore(active).get("ok",false) and core.Arc113.work(core).status=="carried" and conserved(),"Active funded consignment and chapter binding survive native restore"):return
		# Declared loss marker is a negative transaction branch, not evidence of
		# an earned encounter. Native abandonment must never recreate lost kits.
		var lost_job: Dictionary = core.VoyageJobs._find(core.state,id)
		lost_job.freight.lost = true
		lost_job.failed = true
		proof.declarations.append("Private lost-consignment guard branch declares the existing native freight.lost marker; no physical battle-loss claim.")
		var before_lost_stock: float = float(core.port("anvil_dock").stocks.supplies)
		var lost_closed: Dictionary = core.settle_voyage_job(id,true)
		if not check(lost_closed.get("ok",false) and core.Arc113.work(core).status=="withdrawn" and float(core.port("anvil_dock").stocks.supplies)==before_lost_stock and conserved(),"Lost sealed freight can close and refund without resurrecting its kits in harbor stocks"):return
		if not check(core.restore(active).get("ok",false) and conserved(),"Negative loss branch restores the actual accepted pre-loss checkpoint"):return
		locate("cinder_quay")
		var stock_before_delivery: float = float(core.port("cinder_quay").stocks.supplies)
		var coins_before_delivery: int = int(core.state.coins)
		var delivered: Dictionary = core.settle_voyage_job(id)
		w=core.Arc113.work(core)
		if not check(delivered.get("ok",false) and w.status=="delivered" and absf(float(core.port("cinder_quay").stocks.supplies)-stock_before_delivery-qty)<0.000001 and int(core.state.coins)-coins_before_delivery==int(w.payment) and int(w.payment)==int(w.reward) and conserved(),"Native completion transfers the original kits into Cinder and pays only the funded escrow"):return
		var delivered_coins: int = int(core.state.coins)
		var repeated: Dictionary = core.settle_voyage_job(id)
		if not check(not repeated.get("ok",false) and int(core.state.coins)==delivered_coins and core.Arc113.offer(core).is_empty() and conserved(),"Closed one-time order cannot pay or issue its stock again"):return
		var reported: Dictionary = core.StoryOps.choose(core,core.Arc110.ID,"report_materials113")
		if not check(reported.get("ok",false) and core.Arc113.work(core).reported and core.Arc110.record(core).stage=="material_account113" and conserved(),"Explicit native report advances to Mara's factual material account"):return
		await capture("materials.png")
		if finished:return
		locate("anvil_dock")
		core.Contacts.visit(core.state,core.current_port(),core.state.day)
		var optional: Dictionary = core.StoryOps.start(core,"mara_work113")
		if not check(optional.get("ok",false),"Mara's optional paid-work conversation starts at her actual contact harbor"):return
		await capture("mara.png",true)
		if finished:return
		var optional_first: Dictionary = core.StoryOps.choose(core,"mara_work113","ask_paid_work113")
		var optional_end: Dictionary = core.StoryOps.choose(core,"mara_work113","finish_mara_work113")
		if not check(optional_first.get("ok",false) and optional_end.get("ok",false) and core.state.stories.chains.mara_work113.stage=="later_mara117" and conserved(),"Optional conversation retains its future117 boundary without requiring a repair purchase"):return
		locate("cinder_quay")
		var next: Dictionary = core.StoryOps.choose(core,core.Arc110.ID,"ask_cass113")
		if not check(next.get("ok",false) and core.Arc110.record(core).stage=="bought_route114" and core.Arc112.work(core)==earlier,"113 reaches only the unreleased114 boundary and preserves112's native report"):return
		if not check(save_game(false),"Actual native portable-save operation writes the current113 version in a private profile"):return
		var actual_save = JSON.parse_string(FileAccess.get_file_as_string(save_directory.path_join("voyage.json")))
		var reload: Dictionary = core.restore(actual_save)
		if not check(reload.get("ok",false) and core.state.version=="0.113" and core.Arc113.work(core).reported and core.Arc113.work(core).status=="delivered" and core.Arc110.record(core).stage=="bought_route114" and conserved(),"Actual113 save reloads with delivered materials, optional work and ending boundary intact"):return
		proof.final={"work":core.Arc113.work(core).duplicate(true),"stage":core.Arc110.record(core).stage,"coinTotal":core.Money.total(core.state),"coinSupply":core.state.coinSupply,"prior_sha256":expected_sha}
		finish(true)

func _initialize() -> void:
	var start: int = Time.get_ticks_msec()
	var preview = Preview.new()
	preview.began = start
	root.add_child(preview)
