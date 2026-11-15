extends SceneTree

class Preview extends "res://scripts/main.gd":
	var checks: int=0
	var evidence: Dictionary={"checks":[],"source":"real native campaign APIs","staged_victory":false,"owner_profiles_used":false}
	var began: int=0
	var output: String
	func _ready() -> void:
		qa_ocean066=true # Existing private profile/mute switch; no staged gameplay.
		super._ready()
		set_process(false);set_physics_process(false);set_process_input(false);set_process_unhandled_input(false)
		output=OS.get_environment("GAME_TEST_ARTIFACTS").replace("\\","/").path_join("campaign110")
		DirAccess.make_dir_recursive_absolute(output)
		save_directory=output.path_join("saves")
		DirAccess.make_dir_recursive_absolute(save_directory)
		began=Time.get_ticks_msec()
		run.call_deferred()
	func verify(condition: bool,message: String) -> bool:
		checks+=1;evidence.checks.append({"name":message,"passed":condition})
		if not condition:
			push_error("CAMPAIGN110 "+message)
			write_evidence();get_tree().quit(2)
		return condition
	func same_saved(a,b) -> bool:
		# JSON stores numbers without GDScript's int/float container distinction.
		# Compare all values/keys; do not ignore changed fields or quantities.
		if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
		if a is Dictionary and b is Dictionary:
			if a.size()!=b.size():return false
			for key in a:
				if not b.has(key) or not same_saved(a[key],b[key]):return false
			return true
		if a is Array and b is Array:
			if a.size()!=b.size():return false
			for i in a.size():
				if not same_saved(a[i],b[i]):return false
			return true
		return typeof(a)==typeof(b) and a==b
	func write_evidence() -> void:
		var f=FileAccess.open(output.path_join("evidence.json"),FileAccess.WRITE)
		f.store_string(JSON.stringify(evidence,"\t"));f.close()
	func advance(dt: float) -> bool:
		core.step(dt);sync_economy()
		for event in core.pop_events():
			if str(event.get("kind","")) in ["encounter","ocean_encounter066","defeat"]:
				evidence["interruption"]=event
				return verify(false,"Actual voyage interrupted; no supplied victory")
		if core.Money.total(core.state)!=int(core.state.coinSupply):return verify(false,"Native step lost coin conservation")
		return true
	func picture(name: String) -> void:
		chart.step(0);ui.update_hud()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if not verify(get_viewport().get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Saved actual "+name+" view"):return
	func run() -> void:
		var result: Dictionary=core.new_game(123)
		if not verify(bool(result.get("ok",false)),"Fresh stock career accepted"):return
		mode="campaign";paused=true;ui.close_modal();ui.build_hud();chart.center_camera()
		var start_coins: int=int(core.state.coins)
		if not verify(start_coins==15000 and core.state.fleet.size()==1 and int(core.state.fleet[0].crew)==5,"Actual Tinwake start, five crew and15000 coins"):return
		var old_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/coastal_stories.json"))
		if not verify(old_catalog.chains.size()==9 and core.StoryOps.Stories.catalog(core.state).size()==10,"Nine legacy chains plus one campaign"):return
		var original: Dictionary=old_catalog.chains[0]
		core.state.stories.chains[str(original.id)]={"stage":str(original.stages[0].id),"flags":["retained_fixture"],"leads":[],"done":false,"startedDay":1.0}
		var legacy: Dictionary=core.accept_contract(str(data.MISSIONS[0].id))
		if not verify(bool(legacy.get("ok",false)),"Existing story contract remains independently active"):return
		var legacy_copy: Dictionary=core.state.activeContract.duplicate(true)
		core.Contacts.visit(core.state,core.current_port(),core.state.day)
		if not verify(bool(core.StoryOps.start(core,core.Arc110.ID).get("ok",false)),"Tobin starts the optional campaign through native story API"):return
		ui.StoryUI.open(ui);await picture("opening")
		if not verify(bool(core.StoryOps.choose(core,core.Arc110.ID,"take_short_escort110").get("ok",false)),"Player chooses to investigate"):return
		if not verify(not bool(core.StoryOps.choose(core,core.Arc110.ID,"report_merchant110").get("ok",false)),"No report before native escort proof"):return
		if not verify(not bool(core.StoryOps.Stories._gate(core,core.state,{"type":"misspelled_objective"}).ok),"Unknown objectives fail closed"):return
		var quote: Dictionary=ui.HarborRoute104.quote(core,"kelp_reach")
		if not verify(bool(quote.get("routeAvailable",false)) and bool(quote.endurance.readyForAllowance) and int(quote.endurance.returnWages)<start_coins,"Outward Kelp route and return allowance fit actual starter stores and wages"):return
		evidence.start_reserve=quote.endurance
		if not verify(bool(core.chart_course(core.port("kelp_reach"),"kelp_reach").get("ok",false)),"Native route to Kelp Reach accepted"):return
		ui.close_modal()
		var offer: Dictionary={}
		var hunt_time: float=0.0
		var replot: float=0.0
		while offer.is_empty() and hunt_time<150 and Time.get_ticks_msec()-began<22000:
			if not advance(0.25):return
			hunt_time+=0.25;replot-=0.25
			var current: Array=core.Arc110.clients(core)
			if not current.is_empty():offer=current[0];break
			if replot<=0:
				replot=1.0
				for sight in core.NavalAI.sightings(core.state):
					if sight.get("current",false) and str(sight.get("purpose","")) in ["trade","deliver"] and not core.Politics.hostile(core,core.fleet_owner(str(sight.get("ownerId","")))):
						var patrol: Dictionary=core.NavalAI._find_patrol(core.state,str(sight.get("ownerId","")))
						if not patrol.is_empty():core.chart_course({"x":float(patrol.x),"y":float(patrol.y)})
						break
			if int(hunt_time*4)%12==0:await get_tree().process_frame
		if not verify(not offer.is_empty(),"Actual starting Tinwake reacquired a funded loaded native merchant"):return
		evidence.offer=offer.duplicate(true);evidence.hunt_seconds=hunt_time
		var escort_allowance: Dictionary=core.Arc110.reserve_quote(core,offer)
		evidence.escort_allowance=escort_allowance
		if not verify(not escort_allowance.is_empty() and bool(escort_allowance.get("readyForAllowance",false)) and int(escort_allowance.returnWages)<int(core.state.coins),"Client-specific escort and return reserve covered before any fee"):return
		var stale: Dictionary=offer.duplicate(true);stale.targetPort="brass_haven"
		var before_coins: int=core.Money.total(core.state)
		if not verify(not bool(core.Arc110.accept_escort(core,stale).get("ok",false)) and core.Arc110.pending(core).is_empty() and core.Money.total(core.state)==before_coins,"Stale destination quote refuses without escrow or binding"):return
		if not verify(bool(core.Arc110.accept_escort(core,offer).get("ok",false)),"Original native passage funds and binds campaign escort"):return
		var job_id: String=str(offer.id)
		var roundtrip: Dictionary=JSON.parse_string(JSON.stringify(core.state))
		# Controlled API regression branch; restore the entire detached world
		# before the real voyage. This withdrawal is not an earned outcome.
		var bad: Dictionary=roundtrip.duplicate(true)
		bad.stories.chains[core.Arc110.ID].pending110.voyageSeq={}
		if not verify(not core.Arc110.validate(bad).is_empty(),"Malformed passage sequence is rejected before conversion"):return
		bad=roundtrip.duplicate(true);bad.stories.chains[core.Arc110.ID].pending110.tradeQty+=1
		if not verify(not core.Arc110.validate(bad).is_empty(),"Pending cargo must match the actual native lot"):return
		var held: int=int(core.fleet_owner(str(offer.ownerId)).coins)
		if not verify(bool(core.VoyageJobs.abandon(core,job_id).get("ok",false)) and core.Arc110.pending(core).is_empty() and int(core.fleet_owner(str(offer.ownerId)).coins)==held+int(offer.reward),"Ordinary native withdrawal refunds and releases campaign binding"):return
		if not verify(bool(core.restore(roundtrip).get("ok",false)) and str(core.Arc110.pending(core).jobId)==job_id,"Active original binding survives full native JSON restore"):return
		if not verify(bool(core.Arc110.follow(core,true).get("ok",false)),"Player follow order accepted"):return
		var elapsed: float=0.0
		while elapsed<260 and Time.get_ticks_msec()-began<30000:
			if not advance(0.25):return
			elapsed+=0.25
			var job: Dictionary=core.VoyageJobs._find(core.state,job_id)
			if job.is_empty() or job.get("failed",false) or str(job.state)!="active":evidence.failed_job=job.duplicate(true);break
			if job.escort.get("arrived",false):break
			if int(elapsed*4)%12==0:await get_tree().process_frame
		var paid_job: Dictionary=core.VoyageJobs._find(core.state,job_id)
		evidence.native_arrival=paid_job.duplicate(true);evidence.escort_seconds=elapsed
		if not verify(not paid_job.is_empty() and paid_job.escort.get("arrived",false) and not paid_job.get("failed",false),"Bound original carriers physically sailed and sold their load"):return
		if not verify(bool(core.settle_voyage_job(job_id).get("ok",false)),"Native client escrow paid at actual destination"):return
		var receipt: Dictionary=core.Arc110.completed(core,core.Arc110.OPENING).duplicate(true)
		if not verify(not receipt.is_empty() and str(receipt.jobId)==job_id and receipt.carrierUids==offer.escort.carrierUids,"Durable narrative proof identifies original passage and carriers"):return
		var purse: int=int(core.state.coins)
		if not verify(not bool(core.settle_voyage_job(job_id).get("ok",false)) and int(core.state.coins)==purse and core.Arc110.completed(core,core.Arc110.OPENING)==receipt,"Duplicate settlement cannot pay or progress again"):return
		if not verify(not bool(core.StoryOps.choose(core,core.Arc110.ID,"report_merchant110").get("ok",false)),"Paid delivery still requires physical return to Tobin"):return
		if not verify(bool(core.chart_course(core.port("brass_haven"),"brass_haven").get("ok",false)),"Actual water route home accepted"):return
		var home_time: float=0.0
		while not core.state.path.is_empty() and home_time<160 and Time.get_ticks_msec()-began<33000:
			if not advance(0.25):return
			home_time+=0.25
			if int(home_time*4)%16==0:await get_tree().process_frame
		if not verify(str(core.current_port().get("id",""))=="brass_haven" and int(core.state.coins)>0 and float(core.state.fleet[0].fuel)>0,"Ordinary Tinwake returned with surviving crew, fuel and a positive purse"):return
		if not verify(bool(core.StoryOps.choose(core,core.Arc110.ID,"report_merchant110").get("ok",false)),"Actual return unlocks Tobin and Venn conversation"):return
		ui.StoryUI.open(ui);await picture("return")
		if not verify(bool(core.StoryOps.choose(core,core.Arc110.ID,"question_guarantee110").get("ok",false)),"Player questions claim without accepting a debt or faction agreement"):return
		evidence.legacy_before=legacy_copy
		evidence.legacy_after=core.state.activeContract.duplicate(true)
		evidence.old_chain=core.state.stories.chains.get(str(original.id),{}).duplicate(true)
		if not verify(int(core.state.missionIndex)==0,"Legacy mission index remains unchanged"):return
		if not verify(same_saved(core.state.activeContract,legacy_copy),"Every legacy contract field and quantity survives JSON restore and campaign work"):return
		if not verify(core.state.stories.chains[str(original.id)].flags==["retained_fixture"],"Old chain progress remains intact"):return
		var snapshot: Dictionary=JSON.parse_string(JSON.stringify(core.state))
		if not verify(bool(core.restore(snapshot).get("ok",false)) and str(core.Arc110.record(core).stage)=="second_signature111" and not bool(core.Arc110.record(core).done),"Paid chapter and stable next-version boundary survive native restore"):return
		if not verify(core.Money.total(core.state)==int(core.state.coinSupply),"Final native coin conservation"):return
		evidence.final={"coins":core.state.coins,"crew":core.crew_count(),"day":core.state.day,"receipt":receipt,"legacyMissionIndex":core.state.missionIndex,"actual_return_seconds":home_time,"simulated_seconds":hunt_time+elapsed+home_time,"wall_ms":Time.get_ticks_msec()-began}
		write_evidence();print("CAMPAIGN110_DONE checks=",checks);get_tree().quit(0)

func _initialize() -> void:
	root.add_child(Preview.new())
