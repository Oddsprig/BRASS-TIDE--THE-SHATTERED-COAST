extends SceneTree
## Declared player references precede measured travel. No NPC, goods or purse setup.
class Preview extends "res://scripts/main.gd":
	const P117=preload("res://scripts/campaign_validation117.gd")
	const V119=preload("res://scripts/campaign_validation119.gd")
	const PRIOR_SHA="bf4c36513bc54f215418e97f236ad4cc2f9e3971f5450a1e3597fc239733a7cf"
	const ALTERNATE_SHA="0ccda1f2bfcbbbd6b95285c9982cf26d3c35beabfb94cbad7aa7b637aeacbc78"
	var began: int=0
	var out: String=""
	var measured: bool=false
	var interrupted: bool=false
	var branch: String="primary-separate"
	var earlier: Dictionary={}
	var fallback: Dictionary={}
	var proof: Dictionary={"checks":[],"declarations":[],"events":[],"choices":[],"restores":[],"legs":[],"images":{},"owner_profile_used":false,"paid_route":false,"primary_admission":false,"scope":"Selected119 only. Exact accepted118 separate C2; validated player-only reference charts/berths before measurement, actual discovery/admission/refund, independent explicit Unsettled account, attempted native crossing/delivery/return and private save/UI. No earned approach voyage, encounter victory, alternate mutual replay, performance/audio/store or later chapter claim."}

	func _ready() -> void:
		qa_ocean066=true
		super._ready()
		set_process(false);set_physics_process(false);set_process_input(false);set_process_unhandled_input(false)
		out=OS.get_environment("GAME_TEST_ARTIFACTS").path_join("campaign119")
		DirAccess.make_dir_recursive_absolute(out);save_directory=out.path_join("saves")
		run.call_deferred()

	func write_json(name: String,value) -> bool:
		var f=FileAccess.open(out.path_join(name),FileAccess.WRITE)
		if f==null:return false
		f.store_string(JSON.stringify(value,"\t"));f.close();return true

	func snapshot() -> Dictionary:
		return JSON.parse_string(JSON.stringify(core.state))

	func conserved() -> bool:
		return core.Money.total(core.state)==int(core.state.coinSupply)

	func check(value: bool,label: String) -> bool:
		value=value and Time.get_ticks_msec()-began<25000
		proof.checks.append({"name":label,"passed":value,"branch":branch})
		print("CAMPAIGN119_CHECK %d %s %s"%[proof.checks.size(),str(value),label])
		write_json("progress.json",{"checks":proof.checks,"elapsed_ms":Time.get_ticks_msec()-began})
		return value

	func clocks() -> Dictionary:
		return {"day":core.state.day,"econDay":core.state.econDay,"pending":core.pending_days,"exploration":core.exploration_timer,"follow":core.arc_follow_timer110,"watch":core.ocean_watch066}

	func mark() -> Dictionary:
		return {"state":snapshot(),"clocks":clocks(),"events":core.events.duplicate(true),"cache":core.route_cache.duplicate(true),"hits":core.route_hits,"misses":core.route_misses}

	func balances() -> Dictionary:
		var source: Dictionary=core.port(core.Arc119.FROM);var target: Dictionary=core.port(core.Arc119.TO)
		return {"sourceGov":int(source.governmentPurse),"targetGov":int(target.governmentPurse),"captain":int(core.state.coins),"supplierCash":int(source.cash),"stock":float(source.stocks.get(core.Arc119.GOOD,0))}

	func chosen(choice: String) -> bool:
		var result: Dictionary=core.StoryOps.choose(core,core.Arc110.ID,choice)
		proof.choices.append({"choice":choice,"result":result,"branch":branch})
		return bool(result.get("ok",false))

	func restore_value(value: Dictionary) -> bool:
		var result: Dictionary=core.restore(JSON.parse_string(JSON.stringify(value)))
		proof.restores.append({"branch":branch,"result":result})
		return bool(result.get("ok",false))

	func reference(region_id: String,point: Dictionary,label: String) -> bool:
		if not check(not measured,"Player reference is prohibited after measured departure: "+label):return false
		var before: Dictionary=snapshot()
		var location: Dictionary={"world064":{"schema":1,"layer":"home" if region_id=="shatter_coast" else "local","regionId":region_id},"position":{"x":float(point.x),"y":float(point.y)},"heading":float(core.state.heading),"path":[],"destination":""}
		var prepared: Dictionary=core.OceanWorld064.prepare_player(location,core.ocean_context064,core.Routes.clearance(core))
		if not check(prepared.get("ok",false),"Original fleet clearance validates declared reference: "+label):return false
		core._publish_location064(prepared.location)
		var after: Dictionary=snapshot()
		for key in ["world064","position","heading","path","destination"]:before.erase(key);after.erase(key)
		proof.declarations.append({"branch":branch,"reference":label,"location":prepared.location,"earned_travel":false})
		return check(P117.same_value(before,after) and conserved(),"Reference changes only player spatial fields: "+label)

	func berth(id: String) -> bool:
		var p: Dictionary=core.port(id)
		if p.is_empty():return check(false,"Existing reference harbor required: "+id)
		var point: Dictionary=core.Routes.endpoint(core,p,core.Routes.clearance(core)) if p.get("regionId","shatter_coast")=="shatter_coast" else p
		return not point.is_empty() and reference(str(p.get("regionId","shatter_coast")),point,id)

	func advance(dt: float) -> bool:
		core.step(dt)
		if core.pending_days>0:sync_economy()
		for event in core.pop_events():
			proof.events.append({"branch":branch,"event":event})
			if str(event.get("kind","")) in ["encounter","ocean_encounter066","defeat"]:
				interrupted=true
				return check(false,"Actual encounter interrupted travel; no victory or clearing supplied")
		return check(conserved(),"Native advance and pending-day synchronization conserve all coins")

	func harbor_course(id: String) -> Dictionary:
		var dock: Dictionary=core.port(id)
		return core.chart_course({"x":float(dock.x),"y":float(dock.y)},id)

	func sail(result: Dictionary,label: String) -> bool:
		proof.get_or_add("courses",[]).append({"name":label,"result":result.duplicate(true)})
		if not check(result.get("ok",false),"Native course accepted: "+label):return false
		var steps: int=0
		while not core.state.path.is_empty() and steps<64 and Time.get_ticks_msec()-began<22500:
			if not advance(4.0):return false
			steps+=1
		proof.legs.append({"name":label,"steps":steps,"location":core.world_location064(),"day":core.state.day})
		return check(core.state.path.is_empty(),"Actual stopped course completion within route budget: "+label)

	func capture(name: String) -> void:
		ui.close_modal();ui.update_hud();ui.StoryUI.open(ui)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var frame=get_viewport().get_texture().get_image()
		var saved: bool=frame!=null and frame.save_png(out.path_join(name))==OK
		proof.images[name]={"saved":saved,"branch":branch,"stage":core.Arc119.record(core).get("stage",""),"done":core.Arc119.record(core).get("done",false),"outcome":core.Arc119.outcome(core.state)}
		check(saved,"Saved actual journal: "+name)

	func save_ending(title: String) -> bool:
		if not check(save_game(false),"Game writes complete private ending save: "+title):return false
		var saved=JSON.parse_string(FileAccess.get_file_as_string(save_directory.path_join("voyage.json")))
		if not saved is Dictionary:return check(false,"Private save is a complete JSON state")
		var book: Dictionary=core.Arc119.work(core).duplicate(true)
		var fleet_ids: Array=core.state.fleet.map(func(b):return str(b.uid))
		if not check(restore_value(saved) and P117.same_value(core.Arc119.work(core),book) and P117.same_value(core.Arc117.work(core),earlier) and core.Arc119.outcome(core.state).get("title","")==title and core.state.fleet.map(func(b):return str(b.uid))==fleet_ids and conserved(),"Full restore retains actual ending, obligations, original fleet and117"):return false
		write_json("ending-"+str(core.Arc119.work(core).report)+".json",snapshot())
		return true

	func unsettled(value: Dictionary) -> bool:
		branch="independent-unsettled";measured=false
		proof.declarations.append("Independent complete private checkpoint reset at stopped Brass, before retry admission; no measured voyage is credited to this branch.")
		if not check(restore_value(value) and core.work_port070().get("id","")=="brass_haven" and core.Arc119.active(core).is_empty(),"Independent Brass checkpoint has no carried passage"):return false
		var due: int=int(core.Arc119.view(core).refundDue);var before: Dictionary=balances()
		if not check(core.Arc119.gate(core,{"mode":"work"}).get("ok",false) and not core.Arc119.choice_gate(core,"report_many119").get("ok",false) and not core.Arc119.choice_gate(core,"report_common119").get("ok",false),"Work union permits explicit unresolved debrief without a false paid account"):return false
		if not check(chosen("close_unsettled119") and chosen("finish_unsettled119") and core.Arc119.record(core).get("done",false) and core.Arc119.outcome(core.state).get("title","")=="Unsettled Coast" and P117.same_value(balances(),before),"Real explicit choices finish Unsettled Coast without awards or invoice refunds"):return false
		if not check(int(core.Arc119.view(core).refundDue)==due and core.Arc119.settle_refund(core).get("ok",false) and int(core.state.coins)==int(before.captain)+due and int(core.port(core.Arc119.FROM).governmentPurse)==int(before.sourceGov)-due and int(core.port(core.Arc119.FROM).cash)==int(before.supplierCash) and conserved(),"Actual observed fee remains repayable after done; spent invoice stays spent"):return false
		before=balances()
		if not check(core.Arc119.settle_refund(core).get("ok",false) and P117.same_value(balances(),before) and not chosen("finish_unsettled119"),"Completed repayment and final choice cannot pay or finish twice"):return false
		if not check(harbor_course("anvil_dock").get("ok",false) and advance(0.5) and core.Arc119.record(core).get("done",false),"Ordinary native chart and step remain usable after the ending"):return false
		return save_ending("Unsettled Coast")

	func funded() -> bool:
		var before: Dictionary=mark();var q: Dictionary=core.Arc119.quote(core)
		proof.current_quote=q.duplicate(true)
		if not check(P117.same_value(before,mark()),"Fresh quote changes no saved state, clocks, events or route cache"):return false
		if not q.get("ok",false):
			var refused: Dictionary=core.Arc119.accept(core,q)
			check(not refused.get("ok",false) and P117.same_value(before,mark()),"Unavailable quote cannot publish deposits, cargo or an attempt")
			return check(false,"Actual funded primary admission unavailable: "+str(q.get("message","No quote")))
		if not check(q.get("model")=="separate" and q.offer.freight.good==core.Arc119.GOOD and int(q.invoice)>0 and int(q.fee)>0,"Actual separate quote identifies current commodity, invoice and own bond"):return false
		if not check(core.Arc119.native_offer(core).is_empty() and not core.accept_voyage_job(str(q.offer.id)).get("ok",false) and P117.same_value(before,mark()),"A successful quote still cannot expose or admit a private order through the ordinary button"):return false
		var stale: Dictionary=q.duplicate(true);stale.invoice=float(stale.invoice)+0.5
		if not check(not core.Arc119.accept(core,stale).get("ok",false) and P117.same_value(before,mark()),"A fractional stale disclosed invoice cannot publish an admission"):return false
		var money: Dictionary=balances();var time_before: Dictionary=clocks()
		if not check(core.Arc119.accept(core,q).get("ok",false),"Actual finite captain deposit and native freight admission succeed"):return false
		proof.primary_admission=true
		var a: Dictionary=core.Arc119.attempt(core);var id: String=str(a.binding.jobId)
		var job: Dictionary=core.VoyageJobs._find(core.state,id);var qty: int=int(a.binding.qty);var fee: int=int(q.fee);var invoice: int=int(q.invoice)
		if not check(V119.matches(job,a.binding) and int(job.escrow)==fee and P117.same_value(V119.allocations(core.state,id),a.allocations) and V119.originals(core.state,a.allocations) and not a.allocations.has("unassigned"),"Canonical native job seals the original player carrier allocations and full escrow"):return false
		if not check(int(core.state.coins)==int(money.captain)-invoice-fee and int(core.port(core.Arc119.FROM).governmentPurse)==int(money.sourceGov) and int(core.port(core.Arc119.TO).governmentPurse)==int(money.targetGov) and int(core.port(core.Arc119.FROM).cash)==int(money.supplierCash)+invoice and is_equal_approx(float(core.port(core.Arc119.FROM).stocks[core.Arc119.GOOD]),float(money.stock)-qty) and P117.same_value(time_before,clocks()) and conserved(),"Admission buys actual stock with captain I+F, no hidden government subsidy or clock reset"):return false
		before=mark()
		if not check(not core.Arc119.accept(core,q).get("ok",false) and P117.same_value(before,mark()),"Duplicate admission cannot buy, debit or allocate twice"):return false
		var bad: Dictionary=snapshot();bad.stories.chains.common_passage110.work119.attempts[-1].binding.fee=float(fee)+0.5
		if not check(not V119.validate(bad).is_empty(),"Raw fractional bound fee is rejected before restore"):return false
		if not check(not core.settle_voyage_job(id,false).get("ok",false) and int(core.state.coins)==int(money.captain)-invoice-fee and core.Arc119.attempt(core).status=="carried","Source harbor cannot pay an undelivered passage"):return false
		if not check(core.settle_voyage_job(id,true).get("ok",false) and core.Arc119.attempt(core).status=="abandoned" and int(core.Arc119.attempt(core).refund)==fee and core.VoyageJobs._find(core.state,id).is_empty() and int(core.port(core.Arc119.FROM).governmentPurse)==int(money.sourceGov)+fee and is_equal_approx(float(core.port(core.Arc119.FROM).stocks[core.Arc119.GOOD]),float(money.stock)) and conserved(),"Actual harbor abandonment unloads original goods and returns only native escrow"):return false
		proof.abandoned=core.Arc119.attempt(core).duplicate(true)
		var retry_base: Dictionary=snapshot()
		if not berth("brass_haven"):return false
		fallback=snapshot()
		if not await unsettled(fallback):return false
		branch="primary-separate";measured=false
		if not check(restore_value(retry_base),"Separate retry resumes its full independent pre-ending checkpoint"):return false
		if not check(core.Arc119.settle_refund(core).get("ok",false) and int(core.state.coins)==int(money.captain)-invoice and int(core.port(core.Arc119.FROM).governmentPurse)==int(money.sourceGov) and int(core.port(core.Arc119.FROM).cash)==int(money.supplierCash)+invoice and int(core.Arc119.view(core).refundDue)==0 and conserved(),"Primary fee repayment restores F once, leaving the real goods invoice spent"):return false
		before=mark()
		if not check(core.Arc119.settle_refund(core).get("ok",false) and P117.same_value(before,mark()),"Repeated primary repayment changes no coin or receipt"):return false
		q=core.Arc119.quote(core);proof.retry_quote=q.duplicate(true)
		if not check(q.get("ok",false) and core.Arc119.accept(core,q).get("ok",false) and core.Arc119.work(core).attempts.size()==2 and conserved(),"Real availability permits one fresh funded retry after closed repayment"):return false
		await capture("passage.png")
		return await paid_route()

	func paid_route() -> bool:
		var pairs: Array=core.VoyageJobs.WorkRegion070._gate_pairs(core.ocean_context064,core.world_location064(),core.port(core.Arc119.TO),core.port(core.Arc119.FROM))
		var pair: Dictionary={}
		for candidate in pairs:
			for gate in core.ocean_context064.regions.shatter_coast.approaches:
				if gate.id!=candidate.depart:continue
				var location: Dictionary={"world064":{"schema":1,"layer":"home","regionId":"shatter_coast"},"position":gate.position,"heading":float(core.state.heading),"path":[],"destination":""}
				if core.OceanWorld064.transition(core.ocean_context064,location,"shatter_coast",str(gate.id),core.Routes.clearance(core),"").get("ok",false):pair=candidate.duplicate(true);pair.point=gate.position;break
			if not pair.is_empty():break
		if not check(not pair.is_empty(),"Closest native gate pair has a clearance-valid exact source transfer"):return false
		if not reference("shatter_coast",pair.point,"declared source approach before measured crossing"):return false
		proof.gates=pair;proof.measured_start=core.world_location064();measured=true
		if not check(core.transition064("shatter_coast",str(pair.depart)).get("ok",false),"Actual departure transition enters Open Seas"):return false
		if not sail(core.approach_course064("glasswind_keys",str(pair.arrive)),"Open Seas outward"):return false
		if not check(core.transition064("glasswind_keys",str(pair.arrive)).get("ok",false),"Actual arrival transition enters Glasswind"):return false
		if not sail(harbor_course(core.Arc119.TO),"actual Westglass berth"):return false
		var a: Dictionary=core.Arc119.attempt(core);var id: String=str(a.binding.jobId);var coins: int=int(core.state.coins)
		var stock: float=float(core.port(core.Arc119.TO).stocks.get(core.Arc119.GOOD,0));var fee: int=int(a.binding.fee);var qty: int=int(a.binding.qty)
		proof.pre_delivery={"nativeJob":core.VoyageJobs._find(core.state,id).duplicate(true),"attempt":a.duplicate(true),"stock":stock,"coins":coins}
		if not check(core.work_port070().get("id","")==core.Arc119.TO and a.travel.outbound.size()==2 and a.travel.outSeconds>0 and a.travel.outDistance>0 and a.travel.arrivalDay>=0 and core.settle_voyage_job(id,false).get("ok",false) and core.Arc119.attempt(core).status=="paid" and int(core.state.coins)==coins+fee and is_equal_approx(float(core.port(core.Arc119.TO).stocks[core.Arc119.GOOD]),stock+qty) and conserved(),"Original native crossing and delivery add actual target stock and return the own bond"):return false
		a=core.Arc119.attempt(core).duplicate(true)
		if not check(not core.settle_voyage_job(id,false).get("ok",false) and P117.same_value(core.Arc119.attempt(core),a) and int(core.state.coins)==coins+fee,"Duplicate delivery cannot pay or rewrite closure twice"):return false
		if not sail(core.approach_course064("glasswind_keys",str(pair.arrive)),"Glasswind return approach"):return false
		if not check(core.transition064("glasswind_keys",str(pair.arrive)).get("ok",false),"Actual return departure enters Open Seas"):return false
		if not sail(core.approach_course064("shatter_coast",str(pair.home)),"Open Seas return"):return false
		if not check(core.transition064("shatter_coast",str(pair.home)).get("ok",false),"Actual return transition enters Shatter Coast"):return false
		if not sail(harbor_course("brass_haven"),"actual Brass return"):return false
		if not check(core.work_port070().get("id","")=="brass_haven" and core.Arc119.attempt(core).travel.returnDay>=0 and chosen("report_many119") and chosen("finish_many119") and core.Arc119.outcome(core.state).get("title","")=="Many Harbors","Actual paid separate passage and physical Brass return admit their real final choices"):return false
		proof.paid_route=true;proof.paid_attempt=core.Arc119.attempt(core).duplicate(true)
		await capture("ending.png")
		return save_ending("Many Harbors")

	func primary() -> bool:
		var path: String=OS.get_environment("CAMPAIGN_PRIOR_SAVE")
		if not check(OS.get_environment("CAMPAIGN_PRIOR_SHA")==PRIOR_SHA and FileAccess.file_exists(path) and FileAccess.get_sha256(path)==PRIOR_SHA,"Exact accepted118 checkpoint is loaded by pinned SHA256"):return false
		if not check(restore_value(JSON.parse_string(FileAccess.get_file_as_string(path))) and core.Arc119.record(core).stage=="common_passage119" and V119.c2(core.state).get("model")=="separate" and core.work_port070().get("id","")=="brass_haven" and core.state.stories.catalog.size()==14 and conserved(),"Accepted118 retains real separate117 C2, Brass and all fourteen chains"):return false
		mode="campaign";paused=true;ui.close_modal();ui.build_hud();earlier=core.Arc117.work(core).duplicate(true)
		if not check(chosen("begin_passage119") and core.Arc119.record(core).stage=="passage_work119" and core.Arc119.work(core).attempts.is_empty(),"Actual Brass opening creates only the new undertaking"):return false
		fallback=snapshot()
		if not check(not core.Arc119.choice_gate(core,"report_many119").get("ok",false) and not core.Arc119.choice_gate(core,"report_common119").get("ok",false),"No shipment or prior117 fee can stand in for paid119 evidence"):return false
		var bad: Dictionary=snapshot();bad.stories.chains.common_passage110.work119.schema=1.5
		if not check(not V119.validate(bad).is_empty(),"Fractional raw119 schema is refused before normalization"):return false
		bad=snapshot();bad.stories.chains.common_passage110.erase("work118")
		if not check(not V119.validate(bad).is_empty(),"119 raw preflight refuses a missing actual118 warrant account"):return false
		if not berth(core.Arc119.FROM):return false
		var west: Dictionary=core.port(core.Arc119.TO)
		if not check(west.get("regionId","")=="glasswind_keys" and not core.VoyageJobs.WorkRegion070.known_port(core,west),"Existing Westglass starts unknown; no installed port is treated as discovered"):return false
		var before: Dictionary=mark();var q: Dictionary=core.Arc119.quote(core)
		proof.unknown_quote=q.duplicate(true)
		if not check(not q.get("ok",false) and P117.same_value(before,mark()),"Unknown Westglass refuses a quote without state or runtime bookkeeping changes"):return false
		var board: Array=core.VoyageJobs.available(core)
		if not check(core.Arc119.native_offer(core).is_empty() and not board.any(func(o):return str(o.get("id","")).begins_with("common119:")),"Ordinary native board exposes no private passage offer"):return false
		before=mark()
		if not check(not core.accept_voyage_job("common119:1").get("ok",false) and P117.same_value(before,mark()),"Direct ordinary-board acceptance cannot bypass private funding"):return false
		if not berth(core.Arc119.TO) or not advance(0.5):return false
		if not check(core.VoyageJobs.WorkRegion070.known_port(core,core.port(core.Arc119.TO)),"Native shipping observer actually discovers Westglass from the validated local reference"):return false
		if not berth(core.Arc119.FROM):return false
		return await funded()

	func run() -> void:
		proof.alternate={"expected_sha":ALTERNATE_SHA,"provided":not OS.get_environment("CAMPAIGN_ALTERNATE_SAVE").is_empty(),"native_verified":false,"reason":"Alternate actual117 mutual replay is outside this primary bounded fixture; no funding history is synthesized."}
		var passed: bool=await primary()
		if not passed and not core.state.is_empty():
			write_json("primary-incomplete-state.json",snapshot())
			if not interrupted and not fallback.is_empty() and not proof.images.has("ending.png") and Time.get_ticks_msec()-began<21000:await unsettled(fallback)
		if not core.state.is_empty():
			if not proof.images.has("passage.png"):await capture("passage.png")
			if not proof.images.has("ending.png"):await capture("ending.png")
			passed=check(P117.same_value(core.Arc117.work(core),earlier) and V119.validate(core.state).is_empty() and conserved(),"Final current branch preserves117, valid119 receipts and real coin conservation") and passed
			write_json("final-state.json",snapshot())
		passed=check(proof.checks.size()>=20 and proof.primary_admission and proof.paid_route,"At least twenty meaningful checks and actual primary admission/paid route are required") and passed
		for row in proof.checks:passed=passed and bool(row.passed)
		proof.passed=passed;proof.elapsed_ms=Time.get_ticks_msec()-began
		write_json("evidence.json",proof)
		print("CAMPAIGN119_DONE" if passed else "CAMPAIGN119_FAIL")
		get_tree().quit(0 if passed else 2)

func _initialize() -> void:
	var preview=Preview.new();preview.began=Time.get_ticks_msec();root.add_child(preview)
