extends "res://tests/test_tactical_ai.gd"
## Reuse actual SIDE jobs and the existing goal lifetime/guard regressions.
## Controlled semantic checks only; Root runs native acceptance and runtime FPS.

func adoption_job091() -> Dictionary:
	var arena: Dictionary=_goals_arena051(true)
	var st: Dictionary=arena.state
	var id: String=str(arena.source.id)
	B.update(st,DT);B.pop_events(st)
	var slot: Dictionary=Planner._member_slot051(st.tactical,id)
	check(not slot.is_empty(),"091 obtains an actual owned SIDE job before adoption")
	if slot.is_empty():return {}
	check(not bool(slot.joined) and not T._publish_goal051(st,id,slot),"091 unfinished/unjoined job cannot publish or inspect preparation")
	if not _worker_join051(slot):return {}
	var output: Dictionary=slot.capsule.result
	var source: Dictionary=output.goals051.get(id,{})
	check(not source.is_empty() and not source.get("candidate",{}).is_empty(),"091 actual completed job supplies a routed goal")
	if source.is_empty() or source.get("candidate",{}).is_empty():return {}
	return {"arena":arena,"state":st,"id":id,"slot":slot,"output":output,"source":source}

func adoption_protected091(st: Dictionary) -> PackedByteArray:
	var t: Dictionary=st.tactical
	return var_to_bytes([st.ships,st.rng.state,t.memory,t.intents,t.lastDecision,t.counters])

func prepared_binding091() -> void:
	var job: Dictionary=adoption_job091()
	if job.is_empty():return
	var st: Dictionary=job.state
	var id: String=job.id
	var slot: Dictionary=job.slot
	var output: Dictionary=job.output
	var source: Dictionary=job.source
	var proof=Planner.Goals051._prepared_goal091(output,id,source)
	check(proof!=null and is_same(proof.source,source),"091 preparation binds the exact worker payload by identity")
	check(source.is_read_only() and source.state.is_read_only() and source.state.observations.is_read_only() and source.candidate.is_read_only() and source.candidate.approach.is_read_only() and source.reservation.is_read_only(),"091 payload and nested state/path/reservation freeze before adoption")
	check(Planner.Goals051._prepared_goal091(output,id,source.duplicate(true))==null and Planner.Goals051._prepared_goal091(output,"other-member",source)==null,"091 copied payload and sibling ID cannot borrow preparation")
	var input: Dictionary=source.duplicate(true)
	var before: PackedByteArray=var_to_bytes(input)
	var isolated=Planner.Goals051._PreparedGoal091.new(input)
	check(not isolated.source.is_empty() and var_to_bytes(isolated.source)==before and var_to_bytes(input)==before and not input.is_read_only() and not input.state.is_read_only(),"091 preparation preserves values and leaves retained caller inputs mutable")
	input.state.reason="edited caller memory";input.candidate.approach.clear()
	check(var_to_bytes(isolated.source)==before and var_to_bytes(source)==before,"091 later caller mutations reach neither prepared payload nor actual joined output")
	var protected: PackedByteArray=adoption_protected091(st)
	check(not T._publish_goal051(st,id,slot.duplicate()),"091 copied slot cannot borrow the owned generation")
	var member: int=int(st.tactical.workers051.members051[id])
	st.tactical.workers051.members051[id]=-1
	check(not T._publish_goal051(st,id,slot),"091 wrong member generation cannot reuse exact preparation")
	st.tactical.workers051.members051[id]=member
	var task: int=int(slot.taskId);slot.taskId=0
	check(not T._publish_goal051(st,id,slot),"091 a joined flag without its completed task handle cannot publish")
	slot.taskId=task
	# Keep the real proof while replacing its payload: identity must fail closed
	# into the legacy schema checks, regardless of caller-supplied marker fields.
	var bad: Dictionary=source.duplicate(true)
	bad.state.observations[0].lastHp=NAN
	bad.preparedGoals091=true
	output.goals051[id]=bad
	check(Planner.Goals051._prepared_goal091(output,id,bad)==null and not T._publish_goal051(st,id,slot),"091 replaced nonfinite state cannot reuse a genuine proof or a caller flag")
	check(Planner.Goals051._PreparedGoal091.new(bad).source.is_empty(),"091 preparation itself rejects nonfinite state")
	bad=source.duplicate(true);bad.candidate.approach=[Vector2(INF,0.0)]
	output.goals051[id]=bad
	check(not T._publish_goal051(st,id,slot) and Planner.Goals051._PreparedGoal091.new(bad).source.is_empty(),"091 replaced malformed route fails both legacy and detached candidate checks")
	var preparations: Variant=output.preparedGoals091
	output.preparedGoals091={id:{"source":bad,"valid":true,"frozen":true}}
	check(not T._publish_goal051(st,id,slot),"091 caller dictionary markers cannot impersonate typed preparation")
	output.preparedGoals091=preparations;output.goals051[id]=source
	var now: float=float(st.time)
	st.time=float(source.sampledAt)+Planner.Goals051.SAMPLE_SECONDS+0.000002
	check(not T._publish_goal051(st,id,slot),"091 exact prepared payload cannot renew its original freshness boundary")
	st.time=now
	check(adoption_protected091(st)==protected,"091 all rejected publications preserve live owners, RNG, memory, intents and counters")
	check(T._publish_goal051(st,id,slot),"091 restored exact joined payload publishes through every live guard")
	var held=st.tactical.goals051.get(id)
	check(held!=null and is_same(held.source,source) and is_same(held.record.state,source.state) and not st.ships[0].is_read_only() and not st.tactical.workers051.is_read_only(),"091 publication reuses immutable data without freezing live owner or worker ledger")
	check(not T._publish_goal051(st,id,slot),"091 already observed sample cannot publish twice")
	st.tactical.memory.player.byId[id].reason="edited live memory"
	check(var_to_bytes(source)==before,"091 published mutable memory remains detached from immutable goal data")
	T.retire_planning051(st);T.drain_planning051()

func adoption_outcome091(st: Dictionary,id: String) -> Dictionary:
	var t: Dictionary=st.tactical
	var held=t.goals051[id]
	var record: Dictionary=held.record.duplicate()
	record.erase("owner");record.erase("encounterGeneration051")
	return {"record":record,"source":held.source,"intent":held.intent,"points":held.points,"primary":held.primary,"memory":t.memory,"lastDecision":t.lastDecision,"counters":t.counters,"pending":t.pending,"reasons":t.reasons,"passes":t.passes}.duplicate(true)

func prepared_legacy_equivalence091() -> void:
	var outcomes: Array=[]
	for branch: String in ["prepared","legacy"]:
		var job: Dictionary=adoption_job091()
		if job.is_empty():continue
		var st: Dictionary=job.state
		var id: String=job.id
		if branch=="legacy":
			# No preparation contract: preserve safe pre091 validation/freezing.
			job.output.erase("preparedGoals091")
			job.output.goals051[id]=job.source.duplicate(true)
			check(not job.output.goals051[id].is_read_only(),"091 legacy reference starts from a mutable unprepared payload")
		var before: PackedByteArray=var_to_bytes([st.ships,st.rng.state])
		var accepted: bool=T._publish_goal051(st,id,job.slot)
		check(accepted and var_to_bytes([st.ships,st.rng.state])==before,"091 "+branch+" adoption changes no physical hull, stores or RNG")
		if accepted:
			outcomes.append(adoption_outcome091(st,id))
			check(not T._goal_current051(st,job.arena.source).is_empty(),"091 "+branch+" publication passes the current live goal guard")
		T.retire_planning051(st);T.drain_planning051()
	check(outcomes.size()==2 and outcomes[0]==outcomes[1],"091 prepared and legacy paths preserve deterministic goals, memory, orders, accounting and pass metadata")

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":quit(2);return
	var path: String=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):path=arg.substr(6)
	prepared_binding091();prepared_legacy_equivalence091()
	# Actual post-join and post-publication owner/terrain/capability/target,
	# command, expiry, phase and retirement cases remain the existing authority.
	goals_invalidations051();goals_expiry051();goals_phase_guards051();goals_retirement051()
	for st: Dictionary in worker_states051:T.retire_planning051(st)
	T.drain_planning051()
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(F.encode({"checks":checks,"failures":failures,"observations":observations,"scope":"091 joined goal preparation; no performance evidence"})));file.close()
	print("GOAL ADOPTION091: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
