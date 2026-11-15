extends SceneTree
## Selected transaction/save/UI fixture. Source, destination and contact-harbor
## positions are declared setups. No earned voyage, operating-cost or FPS claim.

class Preview extends "res://scripts/main.gd":
	var began: int = 0
	var out: String = ""
	var finished: bool = false
	var proof: Dictionary = {"checks":[],"declarations":[],"owner_profile_used":false,"scope":"Accepted116 checkpoint. Declared harbor/observation/late-leg and negative-funding reference positions; actual native finite harbor contributions, client escrow, expiry refund, abandonment/reimbursement, two independent paid escort branches, optional Mara eligibility, private save/UI. No earned whole voyage, general-world payroll timing, actual repair work, battle/FPS/audio or store-media certification."}

	func _ready() -> void:
		qa_ocean066 = true
		super._ready()
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		out = OS.get_environment("GAME_TEST_ARTIFACTS").path_join("campaign117")
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
		print("CAMPAIGN117_DONE" if passed else "CAMPAIGN117_FAIL")
		get_tree().quit(0 if passed else 2)

	func check(okay: bool, label: String) -> bool:
		if finished:return false
		var bounded: bool = Time.get_ticks_msec()-began < 25000
		okay = okay and bounded
		proof.checks.append({"name":label,"passed":okay})
		write_json("progress.json",{"checks":proof.checks,"elapsed_ms":Time.get_ticks_msec()-began})
		print("CAMPAIGN117_CHECK %d %s %s"%[proof.checks.size(),str(okay),label])
		if not okay:
			push_error("CAMPAIGN117 "+label)
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
		check(frame != null and frame.save_png(out.path_join(name)) == OK,"Saved actual117 journal image: "+name)

	func native_job() -> Dictionary:
		return core.VoyageJobs._find(core.state,str(core.Arc117.attempt(core).get("binding",{}).get("jobId","")))

	func restore_value(value: Dictionary) -> bool:
		var result: Dictionary=core.restore(JSON.parse_string(JSON.stringify(value)))
		write_json("reload-result.json",result)
		return bool(result.get("ok",false))

	func prepare_model(model: String) -> bool:
		locate("anvil_dock")
		var choice: String="choose_mutual117" if model=="mutual" else "choose_separate117"
		return check(core.StoryOps.choose(core,core.Arc110.ID,choice).get("ok",false) and core.Arc117.work(core).model==model,"Funding commitment selected before accepting: "+model)

	func prepare_quote() -> Dictionary:
		var p: Dictionary=core.NavalAI._find_patrol(core.state,"patrol-7")
		var client: Dictionary=core.fleet_owner("patrol-7")
		if p.is_empty() or client.is_empty() or float(p.get("courseLength",0))<=200:return {}
		p.progress=1.0-200.0/float(p.courseLength);core.place_patrol(p);client.progress=p.progress
		core.state.position={"x":float(p.x),"y":float(p.y)};core.state.path=[];core.state.destination=""
		core.NavalAI.observe(core.state)
		proof.declarations.append("Existing loaded patrol-7 begins on the final200 units of its existing route; reference player observation position is declared. Subsequent short movement/sale is native; no whole-voyage claim.")
		for offer in core.Arc117.offers(core):
			if str(offer.ownerId)=="patrol-7":return core.Arc117.quote(core,offer)
		write_json("offer-refusal-state.json",snapshot())
		return {}

	func short_delivery() -> bool:
		var followed: Dictionary=core.Arc117.follow(core,true)
		if not followed.get("ok",false):write_json("follow-refusal.json",followed);return false
		for i in range(120):
			if Time.get_ticks_msec()-began>22500:return false
			core.step(0.25);core.VoyageJobs.tick(core,0.25/float(core.DAY_SECONDS))
			var job: Dictionary=native_job()
			if job.is_empty() or job.get("failed",false):write_json("trip-diagnostic.json",job);return false
			if job.escort.get("arrived",false):return true
		write_json("trip-diagnostic.json",native_job())
		return false

	func paid_branch(model: String,image_name: String) -> bool:
		if not prepare_model(model):return false
		var q: Dictionary=prepare_quote()
		if not check(q.get("ok",false) and q.model==model,"Current finite native funding quote exists for "+model):return false
		var fee: int=int(q.offer.reward)
		var before_owner: int=int(core.fleet_owner("patrol-7").coins)
		var before_player: int=int(core.state.coins)
		var before_purses: Dictionary={}
		for share in q.contributions:before_purses[share.portId]=int(core.port(share.portId).governmentPurse)
		if not check(core.Arc117.accept(core,q).get("ok",false) and int(native_job().escrow)==fee and int(core.state.coins)==before_player and conserved(),"Real native escrow holds the finite fee without advancing coins to the captain: "+model):return false
		var a: Dictionary=core.Arc117.attempt(core)
		var right_payers: bool=a.contributions.size()==(2 if model=="mutual" else 0)
		for share in a.contributions:right_payers=right_payers and int(core.port(share.portId).governmentPurse)==int(before_purses[share.portId])-int(share.amount)
		right_payers=right_payers and int(core.fleet_owner("patrol-7").coins)==before_owner-(fee if model=="separate" else 0)
		if not check(right_payers,"The disclosed government shares or owner bond fund the actual native fee: "+model):return false
		var active: Dictionary=snapshot()
		if not check(restore_value(active) and core.Arc117.attempt(core).binding==active.stories.chains.common_passage110.work117.attempts[-1].binding and conserved(),"Active native funding binding and real purses survive full restore: "+model):return false
		if not check(short_delivery(),"Actual native following, arrival and cargo sale complete the short reference passage: "+model):return false
		var job: Dictionary=native_job();var id: String=str(job.id)
		proof[model]={"nativeJobBeforePayment":job.duplicate(true),"contributions":core.Arc117.attempt(core).contributions.duplicate(true)}
		locate(str(job.targetPort))
		var coins: int=int(core.state.coins)
		var result: Dictionary=core.settle_voyage_job(id)
		a=core.Arc117.attempt(core)
		if not check(result.get("ok",false) and a.status=="paid" and int(a.closure.payment)==fee and int(core.state.coins)==coins+fee and int(a.refund)==0 and native_job().is_empty() and conserved(),"Native cargo sale releases the original fee once under "+model+" terms"):return false
		var kept: Dictionary=a.duplicate(true);coins=int(core.state.coins)
		if not check(not core.settle_voyage_job(id).get("ok",false) and core.Arc117.attempt(core)==kept and int(core.state.coins)==coins and conserved(),"A repeated closed-job settlement cannot pay the captain twice: "+model):return false
		await capture(image_name)
		if finished:return false
		if not check(core.StoryOps.choose(core,core.Arc110.ID,"report_funding117").get("ok",false) and core.Arc117.work(core).reported,"The funding report requires the actual paid escort: "+model):return false
		write_json(model+"-state.json",snapshot())
		return true

	func run() -> void:
		if not check(preload("res://scripts/campaign_validation117.gd").validate({"day":1}).is_empty(),"Legacy absence of this optional chapter book is handled without dictionary-key access errors"):return
		var path: String=OS.get_environment("CAMPAIGN_PRIOR_SAVE")
		if not check(FileAccess.file_exists(path) and FileAccess.get_sha256(path)==OS.get_environment("CAMPAIGN_PRIOR_SHA"),"Exact accepted116 checkpoint is used by SHA256"):return
		var loaded: bool=restore_value(JSON.parse_string(FileAccess.get_file_as_string(path)))
		mode="campaign";paused=true;ui.close_modal();ui.build_hud()
		if not check(loaded and core.Arc110.record(core).stage=="who_pays117" and core.state.stories.catalog.size()==14 and conserved(),"Accepted116 restores with117 and the preserved fourteen-chain catalog"):return
		var earlier: Dictionary=core.Arc116.work(core).duplicate(true)
		locate("anvil_dock")
		var coins: int=int(core.state.coins)
		if not check(core.Arc117.active(core).is_empty() and not core.Arc117.select_hull(core,"not-owned").get("ok",false),"Optional Mara cannot select a foreign hull or take over convoy following"):return
		var eligible: Array=core.Arc117.damaged_hulls(core)
		if not eligible.is_empty():
			var row: Dictionary=eligible[0]
			if not check(core.Arc117.select_hull(core,str(row.uid)).get("ok",false) and core.Arc117.mara_quote(core).get("ok",false) and int(core.state.coins)==coins,"An actually owned damaged hull has a native estimate with no commissioned repair"):return
			if not check(core.StoryOps.choose(core,"mara_work113","discuss_owned_hull117").get("ok",false) and core.Arc117.work(core).mara.discussed and core.Arc117.active(core).is_empty(),"Optional estimate discussion changes no active convoy or payer"):return
			if not check(core.StoryOps.choose(core,"mara_work113","finish_mara117").get("ok",false) and int(core.state.coins)==coins and conserved(),"Mara's optional discussion finishes without a repair payment"):return
			proof.mara={"coverage":"actual owned damaged hull estimate and discussion; no repair commissioned","uid":row.uid,"quote":row.quote}
		else:
			if not check(not core.Arc117.choice_gate(core,"discuss_owned_hull117").get("ok",false) and core.StoryOps.choose(core,"mara_work113","leave_mara117").get("ok",false) and int(core.state.coins)==coins and conserved(),"With no eligible damaged hull Mara can still be left without selecting or buying anything"):return
			proof.mara={"coverage":"no eligible damaged hull; unconditional leave exercised; positive estimate not native-covered"}
		var starting: Dictionary=snapshot()
		if not prepare_model("mutual"):return
		if not check(not core.StoryOps.choose(core,core.Arc110.ID,"choose_separate117").get("ok",false),"C2 commitment cannot switch after the funding terms are selected"):return
		var q: Dictionary=prepare_quote()
		if not check(q.get("ok",false) and q.contributions.size()==2 and q.contributions[0].portId!=q.contributions[1].portId and int(q.contributions[0].amount)+int(q.contributions[1].amount)==int(q.offer.reward),"Mutual quotation names two distinct real government purses and exact whole-coin shares"):return
		var sponsor_id: String=str(q.contributions[0].portId)
		var sponsor: Dictionary=core.port(sponsor_id)
		var government: int=int(sponsor.governmentPurse)
		if not check(core.Money.move(sponsor,"governmentPurse",sponsor,"householdPurse",government,"Declared117 unavailable government budget",core.state.moneyLog),"Negative budget setup moves existing coins into another existing purse"):return
		if not check(not core.Arc117.quote(core,q.offer).get("ok",false) and native_job().is_empty() and conserved(),"An unfunded harbor share cannot be quoted into a new escrow"):return
		if not check(core.Money.move(sponsor,"householdPurse",sponsor,"governmentPurse",government,"Restore declared117 budget reference",core.state.moneyLog),"The isolated budget probe returns exactly its original real coins"):return
		var bad: Dictionary=q.duplicate(true);bad.contributions[0].amount=int(bad.contributions[0].amount)+1
		if not check(not core.Arc117.accept(core,bad).get("ok",false) and native_job().is_empty() and conserved(),"Changed displayed contribution shares reject before any money moves"):return
		var purse_before: Dictionary={}
		for share in q.contributions:purse_before[share.portId]=int(core.port(share.portId).governmentPurse)
		var owner_before: int=int(core.fleet_owner("patrol-7").coins)
		if not check(core.Arc117.accept(core,q).get("ok",false) and int(core.fleet_owner("patrol-7").coins)==owner_before and conserved(),"Actual mutual contributions fund native escrow while retaining the client's original operating coins"):return
		var active: Dictionary=snapshot()
		var fractional: Dictionary=JSON.parse_string(JSON.stringify(active))
		fractional.stories.chains.common_passage110.work117.attempts[-1].reimbursed=0.5
		if not check(not preload("res://scripts/campaign_validation117.gd").validate(fractional).is_empty(),"Fractional coin reimbursements still fail raw preflight before conversion"):return
		if not check(restore_value(active) and core.Arc117.active(core).binding.jobId==native_job().id and conserved(),"The funded refund-probe checkpoint fully restores with its original native identity"):return
		if not check(not core.Arc117.accept(core,q).get("ok",false) and core.Arc117.work(core).attempts.size()==1,"A carried original funding attempt cannot be admitted twice"):return
		core.VoyageJobs.ensure(core)
		var validator=preload("res://scripts/campaign_validation117.gd")
		var restored_binding: Dictionary=core.Arc117.attempt(core).binding
		if not check(validator.same_value(validator.identity(native_job()),restored_binding) and validator.validate(core.state).is_empty(),"Native normalization after restore retains the exact original numeric identity"):return
		var changed_identity: Dictionary=restored_binding.duplicate(true)
		changed_identity.reward=float(changed_identity.reward)+0.5
		if not check(not validator.same_value(changed_identity,restored_binding) and not validator.same_value({"amount":false},{"amount":0}) and validator.same_value({"amount":941},{"amount":941.0}),"Exact value comparison accepts JSON numeric representations and rejects changed or boolean amounts"):return
		var job: Dictionary=native_job();var id: String=str(job.id);var fee: int=int(job.reward)
		var p: Dictionary=core.NavalAI._find_patrol(core.state,"patrol-7")
		var away: Dictionary={}
		for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			var point: Dictionary={"x":float(p.x)+direction.x*1200.0,"y":float(p.y)+direction.y*1200.0}
			if core.Navigation.is_water(core.nav,float(point.x),float(point.y),24.0):away=point;break
		if not check(not away.is_empty(),"A water-safe outside-escort-radius reference exists for the refund probe"):return
		core.state.position=away;core.state.path=[];core.state.destination=""
		proof.declarations.append("Declared player reference outside600 protection radius solely to exercise actual native contract failure/refund, not an earned withdrawal.")
		core.EscortOps.advance_contract(core,job)
		var a: Dictionary=core.Arc117.attempt(core)
		if not check(job.get("failed",false) and job.state=="expired" and int(job.escrow)==0 and int(a.refund)==fee and int(a.reimbursed)==0 and conserved(),"Native radius failure refunds the actual client before abandonment and records the amount once"):return
		var owner_coins: int=int(core.fleet_owner("patrol-7").coins)
		core.VoyageJobs.tick(core,0)
		if not check(int(core.Arc117.attempt(core).refund)==fee and int(core.fleet_owner("patrol-7").coins)==owner_coins and conserved(),"Repeated expiry cannot duplicate the native refund"):return
		var failed: Dictionary=snapshot()
		var client: Dictionary=core.fleet_owner("patrol-7")
		if not check(core.Money.move(client,"coins",client,"crewPurse",int(client.coins),"Declared117 client refund temporarily unavailable in crew purse",core.state.moneyLog),"Shortfall probe conserves existing client coins in an existing crew purse"):return
		locate(str(job.targetPort))
		if not check(core.settle_voyage_job(id,true).get("ok",false) and core.Arc117.attempt(core).status=="abandoned" and int(core.Arc117.attempt(core).reimbursed)==0 and not core.Arc117.settle_refund(core).get("ok",false) and core.Arc117.offers(core).is_empty() and conserved(),"A closed escort with unavailable client funds retains its contribution debt and cannot fabricate reimbursement or another attempt"):return
		var unsettled: Dictionary=snapshot()
		if not check(restore_value(unsettled) and core.Arc117.attempt(core).status=="abandoned" and int(core.Arc117.attempt(core).reimbursed)==0 and not core.Arc117.settle_refund(core).get("ok",false) and conserved(),"An actual unsettled contribution account fully restores without fabricating a return"):return
		if not check(restore_value(failed) and int(core.Arc117.attempt(core).refund)==fee and conserved(),"The isolated shortfall probe restores only its complete private pre-close checkpoint"):return
		job=native_job();locate(str(job.targetPort))
		if not check(core.settle_voyage_job(id,true).get("ok",false) and core.Arc117.attempt(core).status=="abandoned" and int(core.Arc117.attempt(core).reimbursed)==fee and int(core.fleet_owner("patrol-7").coins)==owner_before and conserved(),"Native abandonment returns both actual harbor contributions from the client's received refund"):return
		var repaid: bool=true
		for port_id in purse_before:repaid=repaid and int(core.port(str(port_id)).governmentPurse)==int(purse_before[port_id])
		var before_repeat: int=core.Money.total(core.state)
		core.Arc117.settle_refund(core)
		if not check(repaid and int(core.Arc117.attempt(core).reimbursed)==fee and core.Money.total(core.state)==before_repeat and not core.Arc117.choice_gate(core,"report_funding117").get("ok",false),"Returned shares stay with their original harbors once; a refund is not a completed funded escort"):return
		proof.refund={"amount":fee,"reimbursed":core.Arc117.attempt(core).reimbursed,"closure":core.Arc117.attempt(core).closure}
		if not check(restore_value(starting),"The independent paid mutual branch starts from the original declared117 pre-commit checkpoint"):return
		if not await paid_branch("mutual","mutual.png"):return
		if not check(restore_value(starting),"The independent separate-owner branch starts from the same pre-commit checkpoint"):return
		if not await paid_branch("separate","separate.png"):return
		if not check(core.StoryOps.choose(core,core.Arc110.ID,"next_fuel117").get("ok",false) and core.Arc110.record(core).stage=="fuel_has_owners118" and core.Arc116.work(core)==earlier,"117 ends at the locked118 lead and preserves the original116 convoy account"):return
		if not check(save_game(false),"Actual private117 save is written by the game"):return
		var actual = JSON.parse_string(FileAccess.get_file_as_string(save_directory.path_join("voyage.json")))
		if not check(restore_value(actual) and core.state.version=="0.117" and core.Arc117.work(core).reported and conserved(),"Actual117 save fully restores paid funding, original native identities and optional Mara history"):return
		finish(true)

func _initialize() -> void:
	var preview=Preview.new();preview.began=Time.get_ticks_msec();root.add_child(preview)
