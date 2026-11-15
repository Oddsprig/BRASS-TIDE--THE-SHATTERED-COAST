extends SceneTree
## Controlled post110 chapter-boundary fixture over an ACTUAL110 retail new-
## career save. No earned full-campaign, sailing reachability or FPS claim.
## Positive bounty/combat/recovery use original finite native owners and purses.
class Preview extends "res://scripts/main.gd":
	const Check111=preload("res://scripts/campaign_validation111.gd")
	var count111: int=0
	var output111: String
	var began111: int=0
	var proof111: Dictionary={"checks":[],"fixture":"Declared post110 story boundary and isolated reference encounter; not an earned campaign playthrough or store media","supplied_boats_or_coins":false,"owner_profile_used":false}
	func _ready() -> void:
		qa_ocean066=true;super._ready()
		set_process(false);set_physics_process(false);set_process_input(false);set_process_unhandled_input(false)
		output111=OS.get_environment("GAME_TEST_ARTIFACTS").path_join("campaign111")
		DirAccess.make_dir_recursive_absolute(output111)
		began111=Time.get_ticks_msec();run111.call_deferred()
	func verify111(ok: bool,message: String) -> bool:
		count111+=1;proof111.checks.append({"name":message,"passed":ok})
		if not ok:
			push_error("CAMPAIGN111 "+message);write111();get_tree().quit(2)
		return ok
	func write111() -> void:
		var file=FileAccess.open(output111.path_join("evidence.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(proof111,"\t"));file.close()
	func snapshot111() -> Dictionary:
		return JSON.parse_string(JSON.stringify(core.state))
	func restore111(snapshot: Dictionary) -> bool:
		return bool(core.restore(snapshot).get("ok",false))
	func same111(a,b) -> bool:
		if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
		if a is Dictionary and b is Dictionary:
			if a.size()!=b.size():return false
			for key in a:
				if not b.has(key) or not same111(a[key],b[key]):return false
			return true
		if a is Array and b is Array:
			if a.size()!=b.size():return false
			for i in a.size():
				if not same111(a[i],b[i]):return false
			return true
		return typeof(a)==typeof(b) and a==b
	func picture111(name: String) -> void:
		chart.step(0);ui.update_hud()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		verify111(get_viewport().get_texture().get_image().save_png(output111.path_join(name+".png"))==OK,"Saved controlled "+name+" view")
	func run111() -> void:
		var old_path: String=OS.get_environment("CAMPAIGN111_PRIOR_SAVE")
		if not verify111(FileAccess.get_sha256(old_path)==OS.get_environment("CAMPAIGN111_PRIOR_SHA"),"Actual110 private retail starter save hash matches"):return
		var older: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(old_path))
		if not verify111(restore111(older),"Actual110 retail save restores under111 without new progress"):return
		mode="campaign";paused=true;ui.close_modal();ui.build_hud();chart.center_camera()
		if not verify111(int(core.state.coins)==15000 and core.state.fleet.size()==1 and int(core.crew_count())==5,"Unmodified original starter boat, five sailors and15000coins"):return
		if not verify111(core.StoryOps.Stories.catalog(core.state).size()==11,"Nine old chains, main campaign and one optional contact arc"):return
		core.Contacts.visit(core.state,core.current_port(),core.state.day)
		if not verify111(not core.StoryOps.start(core,core.Arc111.OPTIONAL).ok,"Optional clause conversation does not disclose the guarantee early"):return
		if not verify111(core.accept_contract(str(data.MISSIONS[0].id)).ok,"Ordinary legacy contract stays active alongside this chapter"):return
		var legacy: Dictionary=core.state.activeContract.duplicate(true)
		if not verify111(core.StoryOps.start(core,core.Arc110.ID).ok,"Main campaign starts through the normal contact API"):return
		# Explicit declared precondition. Do not pretend this fixture earned110.
		core.Arc110.record(core).stage="second_signature111"
		core.Arc110.record(core).flags=["venn_claim_seen110"]
		if not verify111(core.StoryOps.start(core,core.Arc111.OPTIONAL).ok and core.StoryOps.choose(core,core.Arc111.OPTIONAL,"read_seizure_clause111").ok and core.StoryOps.choose(core,core.Arc111.OPTIONAL,"finish_clause111").ok,"Optional Tobin conversation completes without gating the main operation"):return
		var offers: Array=core.Arc111.offers(core)
		if not verify111(not offers.is_empty(),"Actual sponsor can fund an existing hostile raider bounty"):return
		var terms: Dictionary=offers[0].duplicate(true)
		var wrong: Dictionary=terms.duplicate(true);wrong.reward=int(wrong.reward)+1
		var before_jobs: int=core.state.voyageJobs.size()
		if not verify111(not core.Arc111.accept(core,wrong).ok and core.state.voyageJobs.size()==before_jobs and core.Arc111.work(core).is_empty(),"Changed quotation refuses without native job or story mutation"):return
		if not verify111(core.Arc111.accept(core,terms).ok,"Actual native bounty escrow and original target binding accepted"):return
		var active: Dictionary=snapshot111()
		var w: Dictionary=core.Arc111.work(core)
		var job_id: String=str(w.jobId);var owner_id: String=str(w.ownerId)
		if not verify111(core.VoyageJobs.abandon(core,job_id).ok and str(core.Arc111.work(core).status)=="abandoned" and not core.Arc111.choice_gate(core,"report_no_property111").ok,"Stock native withdrawal records refund but no invented loss"):return
		var invalid: Dictionary=snapshot111()
		invalid.stories.chains[core.Arc110.ID].work111.reported=true
		invalid.stories.chains[core.Arc110.ID].work111.resolution="no_property"
		invalid.stories.chains[core.Arc110.ID].stage="tobin_admission111"
		if not verify111(not Check111.validate(invalid).is_empty() and not core.restore(invalid).ok,"Empty abandoned loss report is rejected by validator and full restore"):return
		if not verify111(restore111(active) and str(core.Arc111.work(core).status)=="carried","Carried bounty and closure state restore after withdrawal branch"):return
		var context: Dictionary={"kind":"patrol","id":owner_id,"ownerId":owner_id,"name":"Controlled native111 encounter"}
		core.battle_settled("won",[core.hull("bilge_punt")],context)
		if not verify111(core.Arc111.work(core).wrecks.is_empty() and not core.Arc111.secured(core).ok,"Empty legacy won result grants no physical property evidence"):return
		if not verify111(restore111(active),"Negative legacy-result case rolls back only its private fixture"):return
		var owner: Dictionary=core.fleet_owner(owner_id)
		var original_boat: Dictionary=owner.boats[0]
		var original_uid: String=str(original_boat.uid)
		var captured: Array=core.Arc111.capture_snapshot(core,context,{"captured":[original_boat]})
		original_boat.uid="renamed-prize-fixture111"
		var identity_ok: bool=captured.size()==1 and str(captured[0].originalUid)==original_uid and str(captured[0].boat.uid)=="renamed-prize-fixture111"
		original_boat.uid=original_uid
		if not verify111(identity_ok and core.Arc111.work(core).captures.is_empty(),"Capture snapshot retains original identity through a controlled rename without granting a prize"):return
		# Isolated reference arena, native original hulls/ammo/crew, no supplied win.
		var physical: Dictionary=Battle.create({"fleet":core.active_fleet(),"enemyFleet":owner.boats.filter(func(boat):return not boat.sunk),"seed":111,"islands":[]})
		physical.chartPosition=core.state.position.duplicate(true);physical.world064=core.world_location064().world064
		while physical.result==null and float(physical.time)<180 and Time.get_ticks_msec()-began111<25000:
			Battle.update(physical,1.0/30.0)
		Battle.update(physical,0) # End actual equipment/cache borrows before settlement.
		proof111.reference_combat={"result":physical.result,"simulatedSeconds":physical.time,"not_rendered_fps_or_reachability":true}
		if not verify111(physical.result=="won","Actual two-boat native reference combat reaches a win without supplied damage or victory"):return
		var report: Dictionary=core.battle_settled(str(physical.result),[core.hull("bilge_punt")],context,physical)
		w=core.Arc111.work(core)
		if not verify111(not report.get("wrecks",[]).is_empty() and w.wrecks.size()==1 and str(w.wrecks[0].uid)==original_uid,"Native settlement binds the original physical target wreck and immutable engagement sequence"):return
		var paid_before: int=int(core.state.coins)
		core.battle_settled(str(physical.result),[core.hull("bilge_punt")],context,physical)
		if not verify111(int(core.state.coins)==paid_before and w.wrecks.size()==1,"Cached battle settlement neither pays twice nor repeats physical evidence"):return
		var after_combat: Dictionary=snapshot111()
		w.battleFloor=int(physical.campaignSequence111);w.wrecks=[];w.captures=[]
		core.state.battleSeq=int(core.state.battleSeq)+1
		core.Arc111.after_battle(core,str(physical.result),context,physical,report,[])
		if not verify111(w.wrecks.is_empty(),"Advancing the global counter cannot freshen an archived battle"):return
		if not verify111(restore111(after_combat),"Actual native post-combat state restores"):return
		if not verify111(core.settle_voyage_job(job_id).ok and str(core.Arc111.work(core).status)=="paid" and not core.Arc111.secured(core).ok,"Real bounty payment closes its receipt but does not fabricate recovered property"):return
		var no_recovery: Dictionary=snapshot111()
		w=core.Arc111.work(core)
		var wreck_id: String=str(w.wrecks[0].id)
		var impossible: Dictionary=snapshot111()
		impossible.stories.chains[core.Arc110.ID].work111.reported=true
		impossible.stories.chains[core.Arc110.ID].work111.resolution="recovered"
		impossible.stories.chains[core.Arc110.ID].stage="tobin_admission111"
		if not verify111(not Check111.validate(impossible).is_empty(),"Witnessed wreck alone cannot restore as completed recovered property"):return
		impossible=snapshot111()
		impossible.stories.chains[core.Arc110.ID].work111.wrecks[0].terminal={"mode":"gear","day":float(core.state.day)}
		if not verify111(not Check111.validate(impossible).is_empty(),"Gear terminal without a matching paid recovery receipt is rejected"):return
		w.wrecks[0].terminal={"mode":"gear","day":float(core.state.day)}
		if not verify111(not core.Arc111.loss(core).ok,"Recoverable live equipment still blocks loss despite a stale terminal claim"):return
		if not verify111(restore111(no_recovery),"Actual original wreck restores after terminal-claim probe"):return
		core.state.wrecks=core.state.wrecks.filter(func(row):return str(row.id)!=wreck_id)
		if not verify111(not core.Arc111.loss(core).ok,"Missing original wreck is unresolved rather than a confirmed loss"):return
		if not verify111(restore111(no_recovery),"Missing-record negative fixture rolls back"):return
		var raw: Dictionary=core.Arc111.raw_wreck(core,wreck_id);raw.status="unknown-fixture"
		if not verify111(not core.Arc111.loss(core).ok,"Unknown native wreck status cannot close the investigation"):return
		if not verify111(restore111(no_recovery),"Unknown-status fixture rolls back"):return
		var boat: Dictionary=core.state.fleet[0]
		while core.Exploration.spare_crew(core.state)<1 and float(boat.crew)<float(boat.crewMax):
			if not core.Harbor.recruit(core,str(boat.uid),1).ok:break
		if not verify111(core.Exploration.spare_crew(core.state)>=1,"An actual able spare sailor is available for paid recovery"):return
		var wreck: Dictionary=core.Arc111.raw_wreck(core,wreck_id)
		var part_uid: String=""
		for uid in wreck.get("sourceModuleCondition",{}).get("items",{}):
			if str(wreck.sourceModuleCondition.items[uid].family)!="pumps":part_uid=str(uid);break
		if not verify111(not part_uid.is_empty(),"Original physical wreck contains an identifiable non-integral fitting"):return
		var request: Dictionary={"itemUids":[part_uid],"carrierUid":str(boat.uid),"acceptForfeiture":false}
		var coins_before: int=int(core.state.coins)
		if not verify111(not core.recover_wreck(wreck_id,"gear","",0,request).ok and int(core.state.coins)==coins_before and core.Arc111.work(core).recoveries.is_empty(),"Refused forfeiture consent performs no recovery or story progress"):return
		request.acceptForfeiture=true
		var recovered: Dictionary=core.recover_wreck(wreck_id,"gear","",0,request)
		if not verify111(recovered.ok and int(recovered.get("wagesPaid",0))>0 and core.Arc111.work(core).recoveries.size()==1 and core.Arc111.secured(core).ok,"Actual paid recovery publishes original fitting custody and story receipt after state replacement"):return
		var terminal_wreck: Dictionary=core.Arc111.raw_wreck(core,wreck_id)
		if not verify111(terminal_wreck.get("hullStripped",false) and terminal_wreck.get("claimedMode","")=="gear" and terminal_wreck.get("equipmentCustody","")=="retired" and not terminal_wreck.has("sourceModuleCondition"),"Actual selected recovery forfeits the whole source snapshot and remaining fittings"):return
		var after_recovery_coins: int=int(core.state.coins)
		if not verify111(not core.recover_wreck(wreck_id,"gear","",0,request).ok and int(core.state.coins)==after_recovery_coins and core.Arc111.work(core).recoveries.size()==1,"Repeated native fitting recovery is refused without new charge or story receipt"):return
		proof111.paid_recovery={"partUid":part_uid,"wagesPaid":recovered.wagesPaid,"foodConsumed":recovered.foodConsumed,"workDays":recovered.workDays}
		var retained: Dictionary=snapshot111()
		boat=core.state.fleet[0]
		var real_part: Dictionary=boat.moduleCondition.items[part_uid]
		boat.moduleCondition.items.erase(part_uid)
		if not verify111(not core.Arc111.secured(core).ok,"Cached recovery receipt cannot replace a missing original fitting"):return
		boat.moduleCondition.items[part_uid]=real_part
		boat.storedPort="anvil_dock"
		if not verify111(not core.Arc111.secured(core).ok and not core.Arc111.loss(core).ok,"Property stored at a different harbor is neither local report evidence nor a loss"):return
		if not verify111(restore111(retained),"Actual retained property restores after custody probes"):return
		ui.StoryUI.open(ui);await picture111("property-fixture")
		if not verify111(core.StoryOps.choose(core,core.Arc110.ID,"report_property111").ok and core.Arc111.work(core).reported,"Explicit report requires original current property and reaches Tobin's admission"):return
		if not verify111(not core.StoryOps.choose(core,core.Arc110.ID,"report_property111").ok,"Repeated report is refused"):return
		if not verify111(core.StoryOps.choose(core,core.Arc110.ID,"hear_exit_channel111").ok and str(core.Arc110.record(core).stage)=="exit_channel112" and not core.Arc110.record(core).done,"Stable next-version boundary is saved without claiming full campaign completion"):return
		if not verify111(restore111(snapshot111()) and core.Arc111.work(core).reported and core.Money.total(core.state)==int(core.state.coinSupply),"Final native restore retains actual equipment, bounded evidence and world coin conservation"):return
		if not verify111(int(core.state.missionIndex)==0 and same111(core.state.activeContract,legacy),"Every legacy contract field and unchanged mission index survive111"):return
		proof111.final={"coins":core.state.coins,"crew":core.crew_count(),"day":core.state.day,"stage":core.Arc110.record(core).stage,"native_bounty_payment":core.Arc111.work(core).payment,"wall_ms":Time.get_ticks_msec()-began111}
		write111();print("CAMPAIGN111_DONE checks=",count111);get_tree().quit(0)

func _initialize() -> void:
	root.add_child(Preview.new())
