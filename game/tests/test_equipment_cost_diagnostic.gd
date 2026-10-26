extends "res://tests/probe_equipment_capacity.gd"
## SOURCE REVIEW CANDIDATE. Diagnostic data only; no capacity or FPS acceptance.
## Reuses exact f7074c8c create_window/live/condition_summary/diagnostic helpers.
const COST_PROFILE: String="tactical_40"
const COST_SEED: int=83
const MAX_ACTUAL_UPDATES: int=24
const DIAGNOSTIC_WORK_US: int=40000000
var cost_checks: int=0

func _canonical_40(st: Dictionary) -> Dictionary:
	var seen: Dictionary={}
	var invalid: Array=[]
	var canonical: int=0
	for ship in st.ships:
		var uid: String=str(ship.get("uid",""))
		if uid.is_empty() or seen.has(uid):invalid.append({"uid":uid,"reason":"missing_or_duplicate_uid"})
		seen[uid]=true
		if EquipmentDamage.is_canonical_owner(ship):canonical+=1
		else:invalid.append({"uid":uid,"reason":"not_canonical"})
	var population: Dictionary=live(st)
	var ok: bool=st.ships.size()==40 and canonical==40 and invalid.is_empty()
	ok=ok and int(population.player)==20 and int(population.enemy)==20 and int(population.afloat)==40
	ok=ok and st.reserves.player.is_empty() and st.reserves.enemy.is_empty()
	ok=ok and int(st.deployment.player)==300 and int(st.deployment.enemy)==300
	return {"ok":ok,"ship_count":st.ships.size(),"canonical_count":canonical,"live":population,
		"deployment":st.deployment.duplicate(true),"invalid":invalid}

func _resources(st: Dictionary) -> Dictionary:
	var ships: Array=[]
	for ship in st.ships:
		var row: Dictionary={"uid":str(ship.get("uid",""))}
		for key in ["hp","water","fire","engine","crew","wounded","shoreCrew","ammo","fuel","supplies",
			"cooldown","sunk","captureSecured","moduleCondition"]:
			var value=ship.get(key,null)
			row[key]=value.duplicate(true) if value is Dictionary or value is Array else value
		ships.append(row)
	return {"totals":condition_summary(st),"ships":ships}

func _public_status_cost(st: Dictionary) -> Dictionary:
	var live_before: Dictionary=_resources(st)
	var copy_started: int=Time.get_ticks_usec()
	var detached: Dictionary={"ships":st.ships.duplicate(true)}
	var copy_us: int=Time.get_ticks_usec()-copy_started
	var detached_before: Dictionary=_resources(detached)
	var rows: Array=[]
	for ship in detached.ships:
		if Time.get_ticks_usec()-started>=DIAGNOSTIC_WORK_US:break
		var call_started: int=Time.get_ticks_usec()
		var public_status: Dictionary=Damage.get_status(ship)
		var call_us: int=Time.get_ticks_usec()-call_started
		rows.append({"uid":str(ship.get("uid","")),"public_get_status_us":call_us,
			"status":public_status.duplicate(true)})
	var live_after: Dictionary=_resources(st)
	var unchanged: bool=live_before==live_after
	cost_checks+=1
	if not unchanged:failures.append("Detached public-status observation changed live resources")
	return {"scope":"Detached deep-copied ships, after measured Battle loop; one public call per ship",
		"copy_us":copy_us,"calls":rows.size(),"requested_calls":detached.ships.size(),"rows":rows,
		"detached_resources_before":detached_before,"detached_resources_after":_resources(detached),
		"live_resources_unchanged":unchanged,"resource_observation_excluded_from_call_us":true}

func _initialize() -> void:
	started=Time.get_ticks_usec()
	var artifacts: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if artifacts.is_empty() or OS.get_environment("GAME_TEST_JOB_ID").is_empty():
		push_error("Cost diagnostic requires Test Bridge fresh artifacts");quit(1);return
	var public_status_enabled: bool=true
	for argument in OS.get_cmdline_user_args():
		if str(argument)=="--public-status=0":public_status_enabled=false
		elif str(argument)!="--public-status=1":
			push_error("Only --public-status=0 or 1 is accepted");quit(1);return
	var config_value=JSON.parse_string(FileAccess.get_file_as_string("res://tests/tactical_scenarios.json"))
	var world_value=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	if not config_value is Dictionary or not world_value is Dictionary:
		push_error("Exact scenario/world dictionaries required");quit(1);return
	var config: Dictionary=config_value
	var world: Dictionary=world_value
	var world_before: Dictionary=world.duplicate(true)
	var profile: Dictionary=config.load_profiles.get(COST_PROFILE,{})
	if profile.is_empty():push_error("Canonical tactical_40 profile missing");quit(1);return
	var create_started: int=Time.get_ticks_usec()
	var st: Dictionary=create_window(world,profile,COST_SEED)
	var create_us: int=Time.get_ticks_usec()-create_started
	var initial_resources: Dictionary=_resources(st)
	var rows: Array=[]
	var exit_reason: String="MAX_24_ACTUAL_UPDATES"
	for index in range(MAX_ACTUAL_UPDATES):
		if Time.get_ticks_usec()-started>=DIAGNOSTIC_WORK_US:
			exit_reason="DIAGNOSTIC_WORK_BOUND";break
		if st.result!=null:exit_reason="TERMINAL_BEFORE_UPDATE";break
		var observer_started: int=Time.get_ticks_usec()
		var canonical_before: Dictionary=_canonical_40(st)
		var resources_before: Dictionary=_resources(st)
		var pre_observation_us: int=Time.get_ticks_usec()-observer_started
		cost_checks+=1
		if not canonical_before.ok:
			failures.append("Canonical40 pre-update gate failed at tick "+str(index+1))
			exit_reason="CANONICAL_40_REFUSED";break
		var update_started: int=Time.get_ticks_usec()
		Battle.update(st,DT,{})
		var whole_update_us: int=Time.get_ticks_usec()-update_started
		observer_started=Time.get_ticks_usec()
		# Exact frozen API: inherited diagnostic(st), not a nonexistent snapshot API.
		var snapshot: Dictionary=diagnostic(st)
		var ai_us=snapshot.get("ai_us",null)
		var ai_usable: bool=(ai_us is int or ai_us is float) and is_finite(float(ai_us)) and float(ai_us)>=0.0 and float(ai_us)<=float(whole_update_us)
		cost_checks+=1
		if not ai_usable:failures.append("Builtin AI timer unavailable or outside whole-update time at tick "+str(index+1))
		var other_update_us=null if not ai_usable else whole_update_us-int(ai_us)
		var resources_after: Dictionary=_resources(st)
		var post_observation_us: int=Time.get_ticks_usec()-observer_started
		rows.append({"actual_tick":index+1,"sim_time":float(st.time),"canonical_before":canonical_before,
			"whole_update_us":whole_update_us,"ai_us":ai_us,"other_update_us":other_update_us,
			"diagnostic":snapshot,"pre_observation_us":pre_observation_us,
			"post_observation_us":post_observation_us,"resources_before":resources_before,
			"resources_after":resources_after,"live_after":live(st),"terminal_result":st.result})
		if st.result!=null:exit_reason="TERMINAL_AFTER_UPDATE";break
	var public_cost: Dictionary={"enabled":false}
	if public_status_enabled and Time.get_ticks_usec()-started<DIAGNOSTIC_WORK_US:
		public_cost=_public_status_cost(st);public_cost.enabled=true
	elif public_status_enabled:public_cost={"enabled":true,"skipped":"DIAGNOSTIC_WORK_BOUND"}
	cost_checks+=1
	if world!=world_before:failures.append("Canonical world changed")
	cost_checks+=1
	if rows.is_empty():failures.append("No actual update observation recorded")
	var report: Dictionary={"schema":1,"mode":"cost_diagnostic","diagnostic_only":true,
		"capacityAccepted":false,"rendered":false,"audio_auditioned":false,
		"profile":COST_PROFILE,"seed":COST_SEED,"dt":DT,"warmup_updates":0,
		"requested_actual_updates":MAX_ACTUAL_UPDATES,"actual_updates":rows.size(),"checks":cost_checks,
		"create_us":create_us,"exit_reason":exit_reason,"failures":failures.duplicate(true),
		"status":"DIAGNOSTIC_DATA_ONLY" if failures.is_empty() else "DIAGNOSTIC_REFUSED",
		"initial_resources":initial_resources,"final_resources":_resources(st),"samples":rows,
		"public_status_cost":public_cost,"fixture_wall_us":Time.get_ticks_usec()-started,
		"ai_timer_scope":"Existing Battle mount/planning/helm/lanes/automatic-fire/finish slices",
		"other_update_scope":"Whole-update minus builtin AI; aggregate, not isolated damage time",
		"observation_scope":"Resource/canonical/snapshot/copy/serialization work is outside update/call timers",
		"claim_scope":"At most24 cold-start actual updates, no150 warmup, no capacity/FPS/1800 acceptance"}
	var file: FileAccess=FileAccess.open(artifacts.path_join("cost-diagnostic.json"),FileAccess.WRITE)
	if file==null:push_error("Cannot write diagnostic artifacts");quit(1);return
	file.store_string(JSON.stringify(report,"  ")+"\n");file.close()
	print("COST DIAGNOSTIC DATA ONLY: %d actual updates, %s"%[rows.size(),exit_reason])
	print("Cost diagnostic: %d checks, %d failures"%[cost_checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

