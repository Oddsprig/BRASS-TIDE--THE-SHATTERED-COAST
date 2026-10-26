extends SceneTree
## Bounded r3 capacity prefixes and independent finite behavior cases. No owner IO.
const Battle=preload("res://scripts/battle.gd")
const Damage=preload("res://scripts/damage.gd")
const Refit=preload("res://scripts/refit.gd")
const Records=preload("res://scripts/equipment_records.gd")
const EquipmentDamage=preload("res://scripts/equipment_damage.gd")
const Version=preload("res://scripts/version.gd")
const DT: float=1.0/30.0
const SPEC: Dictionary={"id":"skiff","name":"Skiff","role":"skiff","tier":1,"hp":150,"armor":1,"crewMin":2,"crewOptimal":5,"crewMax":7,"size":16,"speed":100,"turn":2,"pumps":1,"weapon":"gun","damage":12,"fireRate":2,"range":550}
var started: int=0
var failures: Array=[]

static func live(st: Dictionary) -> Dictionary:
	var result: Dictionary={"player":0,"enemy":0,"total":0,"afloat":0}
	for ship in st.ships:
		if ship.sunk:continue
		result.afloat+=1
		if ship.get("captureSecured",false):continue
		result[str(ship.team)]+=1;result.total+=1
	return result

static func quantiles(values: Array) -> Dictionary:
	if values.is_empty():return {"n":0}
	var sorted: Array=values.duplicate();sorted.sort()
	var total: float=0.0
	for value in values:total+=float(value)
	var result: Dictionary={"n":values.size(),"min":sorted[0],"mean":total/values.size(),"max":sorted[-1]}
	for pair in [["p50",0.5],["p90",0.9],["p95",0.95],["p99",0.99]]:result[pair[0]]=sorted[mini(sorted.size()-1,int(floor(sorted.size()*float(pair[1]))))]
	return result

func roster(world: Dictionary,profile: Dictionary,team: String,extra: int=0) -> Array:
	var result: Array=[]
	for index in range(int(profile.per_side)+extra):
		var base: Dictionary={}
		if profile.has("synthetic_deployment_points"):
			base=SPEC.duplicate(true);base.deploymentPoints=int(profile.synthetic_deployment_points)
		else:
			for spec in world.HULLS:
				if str(spec.id)==str(profile.hull):base=spec.duplicate(true);break
		if base.is_empty():failures.append("Unknown profile hull");return []
		var ship: Dictionary=Damage.create_ship(base,{"uid":"bench-%s-%d"%[team,index]})
		if not profile.has("synthetic_deployment_points"):
			var fit: Dictionary=Refit.defaults(base)
			if not Refit.normalize(base,fit).get("ok",false):failures.append("Invalid stock profile fit")
			ship.loadout=fit;Refit.ensure(ship,base)
			ship.ammo=float(ship.spec.ammoCapacity)
		result.append(ship)
	return result

func seed_fleet(ships: Array,known: Array) -> bool:
	var catalog: Dictionary=Refit.catalog()
	for ship in ships:
		var base: Dictionary=ship.get("baseSpec",ship.get("spec",{}))
		var fit: Dictionary=ship.loadout if ship.get("loadout") is Dictionary else Refit.defaults(base)
		var seeded: Dictionary=Records.initialize(ship,{"base":base,"loadout":fit,"catalog":catalog,"identity":str(ship.get("uid","")),"knownUids":known.duplicate()})
		if not seeded.get("ok",false):failures.append(str(seeded.get("error","Canonical seed refused")));return false
		for uid in seeded.get("itemUids",[]):known.append(str(uid))
	return true

func create_window(world: Dictionary,profile: Dictionary,seed: int) -> Dictionary:
	var known: Array=[]
	var fleet: Array=roster(world,profile,"player")
	var enemy: Array=roster(world,profile,"enemy")
	if not seed_fleet(fleet,known) or not seed_fleet(enemy,known):return {"ships":[],"projectiles":[],"effects":[],"reserves":{"player":[],"enemy":[]},"deployment":{"player":0,"enemy":0},"islands":[],"time":0.0,"result":"canonical_refused"}
	var st: Dictionary=Battle.create({"fleet":fleet,"enemyFleet":enemy,"seed":seed})
	if st.deployment.player!=int(profile.points_per_side) or st.deployment.enemy!=int(profile.points_per_side):failures.append("Profile DP mismatch")
	if st.ships.size()!=int(profile.per_side)*2 or not st.reserves.player.is_empty() or not st.reserves.enemy.is_empty():failures.append("Profile admission mismatch")
	for group in [st.ships,st.reserves.player,st.reserves.enemy]:
		for ship in group:
			if EquipmentDamage.is_canonical_owner(ship):continue
			failures.append("Hull is not canonical: "+str(ship.get("uid","")));st.result="canonical_refused";return st
	return st

func condition_summary(st: Dictionary) -> Dictionary:
	var result: Dictionary={"hp":0.0,"water":0.0,"fire":0.0,"ammo":0.0,"fuel":0.0,"supplies":0.0,"crew":0.0,"sunk":0,"secured":0}
	for ship in st.ships:
		for key in ["hp","water","fire","ammo","fuel","supplies","crew"]:result[key]+=float(ship[key])
		if ship.sunk:result.sunk+=1
		if ship.get("captureSecured",false):result.secured+=1
	return result

func diagnostic(st: Dictionary) -> Dictionary:
	if not st.get("tactical") is Dictionary:return {"ai_us":null,"scope":"OLD .029 has no complete new-AI timer"}
	var t: Dictionary=st.tactical
	var metrics: Dictionary=t.get("metrics",{}).duplicate(true)
	var result: Dictionary={"ai_us":metrics.get("aiUs",null),"metrics":metrics,"counters":t.get("counters",{}).duplicate(true),"memory":{"route_cache_entries":t.get("routeCache",{}).size(),"trace_records":t.get("trace",[]).size(),"pending_records":t.get("pending",{}).size(),"prediction_records":t.get("predictions",{}).size()}}
	return result

func capacity(args: Dictionary,config: Dictionary,world: Dictionary) -> Dictionary:
	var protocol: Dictionary=config.capacity_protocol
	var profile: Dictionary=config.load_profiles.get(str(args.profile),{})
	if profile.is_empty():failures.append("Unknown capacity profile");return {}
	var offset: int=int(args.window)
	var remaining: int=int(args.remaining)
	var window_limit: int=mini(int(args.windows),int(protocol.windows_per_process_max))
	if offset<0 or offset>=int(protocol.windows_per_profile_max) or remaining<=0 or window_limit<1:failures.append("Invalid capacity allocation");return {}
	var create_started: int=Time.get_ticks_usec()
	var warm: Dictionary=create_window(world,profile,83)
	var warm_create_us: int=Time.get_ticks_usec()-create_started
	var warm_started: int=Time.get_ticks_usec()
	var warm_ticks: int=0
	for tick in range(int(protocol.warmup_ticks_per_process)):
		if warm.result!=null or Time.get_ticks_usec()-started>int(protocol.work_bound_seconds)*1000000:break
		Battle.update(warm,DT,{});warm_ticks+=1
	var warmup: Dictionary={"requested_ticks":int(protocol.warmup_ticks_per_process),"actual_ticks":warm_ticks,"seed":83,"sim_seconds":warm.time,"terminal_result":warm.result,"final_live":live(warm),"create_us":warm_create_us,"update_wall_us":Time.get_ticks_usec()-warm_started}
	var windows: Array=[]
	var total_samples: int=0
	var wall_limited: bool=false
	for local in range(window_limit):
		if total_samples>=remaining or offset+local>=int(protocol.windows_per_profile_max):break
		if Time.get_ticks_usec()-started>int(protocol.work_bound_seconds)*1000000:wall_limited=true;break
		var number: int=offset+local
		var seed: int=int(protocol.seed_schedule_cyclic[number%protocol.seed_schedule_cyclic.size()])
		create_started=Time.get_ticks_usec()
		var st: Dictionary=create_window(world,profile,seed)
		var create_us: int=Time.get_ticks_usec()-create_started
		var initial: Dictionary=live(st)
		var samples: Array=[]
		var battle_us: Array=[]
		var ai_us: Array=[]
		var reason: String="WINDOW_TICK_LIMIT"
		var measured_started: int=Time.get_ticks_usec()
		var peak_projectiles: int=0
		var peak_effects: int=0
		for tick in range(mini(int(protocol.window_ticks_max),remaining-total_samples)):
			if Time.get_ticks_usec()-started>int(protocol.work_bound_seconds)*1000000:reason="WORK_BOUND_INCOMPLETE";wall_limited=true;break
			var before: Dictionary=live(st)
			if st.result!=null:reason="TERMINAL";break
			if int(before.total)!=int(initial.total):reason="FIRST_LOSS";break
			var tick_started: int=Time.get_ticks_usec()
			Battle.update(st,DT,{})
			var elapsed: int=Time.get_ticks_usec()-tick_started
			var after: Dictionary=live(st)
			var diag: Dictionary=diagnostic(st)
			battle_us.append(elapsed)
			if diag.ai_us!=null:ai_us.append(int(diag.ai_us))
			samples.append({"tick":tick+1,"window":number,"seed":seed,"sim_time":float(st.time),"battle_us":elapsed,"before_live":before,"after_live":after,"projectiles":st.projectiles.size(),"effects":st.effects.size(),"condition_stores":condition_summary(st),"diagnostic":diag})
			total_samples+=1
			peak_projectiles=maxi(peak_projectiles,st.projectiles.size());peak_effects=maxi(peak_effects,st.effects.size())
			if st.result!=null:reason="TERMINAL";break
			if int(after.total)!=int(initial.total):reason="FIRST_LOSS";break
			if total_samples>=remaining:reason="REMAINING_ALLOCATION";break
		windows.append({"window":number,"seed":seed,"initial_live":initial,"final_live":live(st),"deployment":st.deployment,"reserve_uids":{"player":st.reserves.player.map(func(s):return str(s.uid)),"enemy":st.reserves.enemy.map(func(s):return str(s.uid))},"default_islands":st.islands,"create_us":create_us,"update_and_observation_wall_us":Time.get_ticks_usec()-measured_started,"measured_ticks":samples.size(),"sim_seconds":float(st.time),"terminal_result":st.result,"exit_reason":reason,"peak_projectiles":peak_projectiles,"peak_effects":peak_effects,"final_condition_stores":condition_summary(st),"samples":samples,"battle_timing_us":quantiles(battle_us),"ai_timing_us":quantiles(ai_us),"diagnostic_json_bytes":JSON.stringify(st.get("tactical",{})).to_utf8_buffer().size(),"process_static_memory_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"memory_scope":"Diagnostic serialization is measured; process static allocation includes legacy state and does not establish isolated additional AI live bytes"})
		if wall_limited:break
	return {"mode":"capacity","protocol":protocol.id,"profile":str(args.profile),"window_offset":offset,"sample_allocation":remaining,"samples_recorded":total_samples,"warmup":warmup,"windows":windows,"status":"WORK_BOUND_INCOMPLETE" if wall_limited else "BATCH_RECORDED","scope":"Cumulative full-pre-tick capacity prefixes, not continuous battle or outcome acceptance"}

func behavior(args: Dictionary,config: Dictionary) -> Dictionary:
	failures.append("Behavior mode is refused; %s is capacity-only"%str(config.get("capacity_protocol",{}).get("id","capacity")))
	return {"status":"REFUSED","scenario":str(args.get("scenario",""))}

func _initialize() -> void:
	started=Time.get_ticks_usec()
	var args: Dictionary={"mode":"capacity","profile":"tactical_40","window":"0","windows":"2","remaining":"1800","scenario":"A1","variant":"stationary_heavy","seed":"30011","orientation":"authored","config":"","out":""}
	for value in OS.get_cmdline_user_args():
		var pair: PackedStringArray=str(value).trim_prefix("--").split("=",true,1)
		if pair.size()!=2 or not args.has(pair[0]):push_error("Unknown tactical bench argument");quit(1);return
		args[pair[0]]=pair[1]
	if str(args.config).is_empty() or str(args.out).is_empty():push_error("Tactical bench requires explicit config and output");quit(1);return
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(args.config)))
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var source_world: Dictionary=world.duplicate(true)
	var result: Dictionary=capacity(args,config,world) if str(args.mode)=="capacity" else behavior(args,config)
	if world!=source_world:failures.append("Canonical world changed")
	result.schema=1;result.version=Version.text();result.failures=failures+result.get("failures",[])
	result.fixture_wall_us=Time.get_ticks_usec()-started
	result.rendered=false;result.audio_auditioned=false
	var file: FileAccess=FileAccess.open(str(args.out),FileAccess.WRITE)
	if file==null:push_error("Cannot write tactical result");quit(1);return
	file.store_string(JSON.stringify(result,"  ")+"\n");file.close()
	print("TACTICAL BENCH COMPLETE %s %s: %s, %d failures"%[str(args.mode),str(args.profile) if str(args.mode)=="capacity" else str(args.scenario)+"/"+str(args.variant),str(result.get("status","UNKNOWN")),result.failures.size()])
	quit(0 if result.failures.is_empty() else 1)
