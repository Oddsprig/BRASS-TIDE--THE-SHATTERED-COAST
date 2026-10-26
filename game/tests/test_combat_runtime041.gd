extends SceneTree
## One bounded source candidate fixture. Root alone runs the native 15s job.
const Damage=preload("res://scripts/damage.gd")
const Core=preload("res://scripts/equipment_condition.gd")
const Records=preload("res://scripts/equipment_records.gd")
const Lab=preload("res://scripts/fleet_lab.gd")
const Battle=preload("res://scripts/battle.gd")
const Certification=preload("res://scripts/tactical_certification.gd")
const Planner=preload("res://scripts/tactical_planner.gd")
const Tactical=preload("res://scripts/tactical_runtime.gd")
const Routes=preload("res://scripts/tactical_routes.gd")
const Benchmark=preload("res://scripts/runtime_benchmark.gd")
const DT: float=1.0/60.0
var checks: int=0
var failures: Array=[]
var started: int=0
var report: Dictionary={}

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);print("FAIL combat_runtime041: "+message)

func uid_at(ship: Dictionary,location: String) -> String:
	for item in ship.moduleCondition.items.values():
		if str(item.location)==location:return str(item.itemUid)
	return ""

func cache_checks(source: Dictionary) -> void:
	var ship: Dictionary=source.duplicate(true)
	ship.vx=12.0;ship.cooldown=0.15
	var cache: Dictionary={}
	Damage.tick_ship(ship,DT,{"inCombat":true},cache)
	var info: Dictionary=Damage.inspect_owner_cached(ship,cache)
	var reference: Dictionary=ship.duplicate(true)
	var same: bool=true
	for tick in range(8):
		Damage.begin_frame_cache(cache,[ship])
		var actual: Dictionary=Damage.tick_ship(ship,DT,{"inCombat":true},cache)
		var expected: Dictionary=Damage.tick_ship(reference,DT,{"inCombat":true})
		same=same and var_to_bytes(ship)==var_to_bytes(reference) and var_to_bytes(actual)==var_to_bytes(expected)
	check(same,"eight cached healthy frames match full public ship state and tick reports")
	check(is_same(Damage.inspect_owner_cached(ship,cache),info),"healthy frames retain the same exact-owner inspection")
	check(Damage.get_status_cached(ship,cache)==Damage.get_status(ship),"instantaneous cached status equals the public projection")
	var public_status: Dictionary=Damage.get_status_cached(ship,cache)
	public_status.speedFactor=0.0;public_status.weaponFactors["mount0"]=0.0
	check(Damage.read_status_cached(ship,cache).speedFactor>0.0 and Damage.read_status_cached(ship,cache).weaponFactors.mount0>0.0,"public status edits cannot poison the immutable runtime projection")
	var clone: Dictionary=ship.duplicate(true)
	clone.wounded=1.0
	var live_before: PackedByteArray=var_to_bytes(ship)
	check(not is_same(Damage.inspect_owner_cached(clone,cache),info) and Damage.get_status_cached(clone,cache)==Damage.get_status(clone),"same-ID wounded copy receives its own inspection and current status")
	clone.moduleCondition={}
	check(not Damage.get_status_cached(clone,cache).equipmentOk,"same-ID corrupt copy fails closed")
	check(var_to_bytes(ship)==live_before and is_same(Damage.inspect_owner_cached(ship,cache),info),"copy and corrupt reads leave the exact live owner and cache untouched")
	ship.fuel=0.0
	check(Damage.get_status_cached(ship,cache)==Damage.get_status(ship) and Damage.read_status_cached(ship,cache).pump==0.0,"fuel crossing zero immediately refreshes pump status")
	ship.fuel=120.0;ship.wounded=1.0
	check(Damage.get_status_cached(ship,cache)==Damage.get_status(ship),"crew scalar edits immediately refresh status")
	ship.wounded=0.0;ship.water=12.0;ship.breaches.append({"area":2.0,"section":"bow"})
	check(Damage.get_status_cached(ship,cache)==Damage.get_status(ship) and Damage.read_status_cached(ship,cache).inflow>0.0,"in-place breach and water edits immediately refresh flood status")
	ship.water=0.0;ship.breaches=[]
	Damage.set_repair_priority(ship,"weapons")
	check(Damage.get_status_cached(ship,cache).repairPriority=="weapons" and Damage._cached_entry(ship,cache).is_empty(),"priority change invalidates the canonical proof")
	Damage.tick_ship(ship,DT,{"inCombat":true},cache)
	var gun_uid: String=uid_at(ship,"mount0")
	check(not gun_uid.is_empty() and Core.apply_component_damage(ship.moduleCondition,{"itemUid":gun_uid,"loss":0.6,"cause":"Runtime fixture"}).ok,"actual installed gun receives component damage")
	check(Damage.get_status_cached(ship,cache)==Damage.get_status(ship) and Damage.read_status_cached(ship,cache).weaponFactors.mount0<1.0,"actual module damage invalidates condition and weapon factors immediately")
	var supplies: float=ship.supplies
	var repaired: Dictionary=Damage.tick_ship(ship,0.2,{"inCombat":true},cache)
	check(repaired.repairedModuleHp>0.0 and repaired.usedSupplies>0.0 and ship.supplies<supplies,"damaged fallback performs real repair with finite crew work and supply debit")
	check(Damage.get_status_cached(ship,cache)==Damage.get_status(ship),"repaired module factors are current after publication")
	ship.engine=0.5
	check(Damage.get_status_cached(ship,cache)==Damage.get_status(ship),"legacy engine scalar change rejects the equipment proof")
	Damage.tick_ship(ship,DT,{"inCombat":true},cache)
	var rng: RandomNumberGenerator=RandomNumberGenerator.new();rng.seed=4101
	Damage.apply_hit(ship,{"damage":8.0,"kind":"bullet","section":"bow"},rng,cache)
	check(Damage._cached_entry(ship,cache).is_empty() and Damage.get_status_cached(ship,cache)==Damage.get_status(ship),"actual hit removes the owned entry and returns current damaged status")
	var fresh: Dictionary=source.duplicate(true)
	cache={};Damage.tick_ship(fresh,DT,{"inCombat":true},cache)
	var old_info: Dictionary=Damage.inspect_owner_cached(fresh,cache)
	fresh.spec.pumps=float(fresh.spec.pumps)+1.0
	check(not is_same(Damage.inspect_owner_cached(fresh,cache),old_info),"in-place specification edits invalidate equipment inspection")
	cache={};fresh=source.duplicate(true);Damage.tick_ship(fresh,DT,{"inCombat":true},cache)
	old_info=Damage.inspect_owner_cached(fresh,cache)
	fresh.loadout.weapons[0]=""
	check(not Damage.get_status_cached(fresh,cache).equipmentOk and not is_same(Damage.inspect_owner_cached(fresh,cache),old_info),"in-place refit mismatch is refused rather than using old gun authority")
	cache={};fresh=source.duplicate(true);Damage.tick_ship(fresh,DT,{"inCombat":true},cache)
	for tick in range(Damage.OWNER_CACHE_FRAMES):Damage.begin_frame_cache(cache,[fresh])
	check(cache.is_empty(),"unchanged proof still expires after twelve live physics frames")

func route_budget() -> Dictionary:
	return {"fullRoutes":0,"cacheHits":0,"rollouts":0,"samples":0,"clearanceTests":0,"clearanceLimit":4096,"exhaustions":0,"rolled":{}}

func route_state(ship: Dictionary,islands: Array,allies: Array=[]) -> Dictionary:
	var st: Dictionary={"time":0.0,"islands":islands}
	var t: Dictionary=Tactical.ensure(st)
	t.ships[str(ship.id)]=ship;t.dt=DT;t.snapshotRevision=1
	t.cells=Routes.grid([ship]+allies);t.geometry=Routes.terrain(st)
	return st

func route_checks(source: Dictionary) -> void:
	var ship: Dictionary=source.duplicate(true)
	ship.x=600.0;ship.y=850.0;ship.vx=0.0;ship.vy=0.0
	ship.status=Damage.get_status(ship);ship.mounts=[]
	var candidate: Dictionary={"candidateId":"route-fixture","shipId":str(ship.id),"targetId":"","leaderId":"","role":"skirmisher","sector":-1,"approach":[Vector2(600,850),Vector2(1400,850)],"pass":[Vector2(1400,850)],"exit":[Vector2(1500,850)],"fireMountIds":[],"orderRevision":int(ship.orderRevision),"snapshotRevision":1}
	var island: Dictionary={"points":[[900,750],[1100,750],[1100,950],[900,950]]}
	var comparisons: Array=[]
	for islands: Array in [[],[island]]:
		var trial_reference: Dictionary=route_state(ship,islands)
		var trial_live: Dictionary=route_state(ship,islands)
		var trial_old_budget: Dictionary=route_budget();var trial_new_budget: Dictionary=route_budget()
		var trial_old_route: Dictionary=Routes.refine(trial_reference,trial_reference.tactical.geometry,ship,candidate,trial_old_budget)
		var trial_new_route: Dictionary=Routes.refine_live(trial_live,trial_live.tactical.geometry,ship,candidate,trial_new_budget)
		check(trial_old_route.status=="valid" and trial_new_route.status=="valid","reference and combined walk find complete clear-water or island-detour routes")
		if trial_old_route.status!="valid" or trial_new_route.status!="valid":continue
		check(trial_old_route.candidate==trial_new_route.candidate and (islands.is_empty() or trial_new_route.candidate.approach.size()>candidate.approach.size()),"combined walk preserves every approach/pass/exit point including a real land detour")
		var view: Dictionary={"snapshotRevision":1,"terrainRevision":trial_reference.tactical.terrainRevision,"time":0.0,"dt":DT,"side":str(ship.team),"dueIds":[str(ship.id)],"ships":[ship]}
		var fingerprint: String=Planner.fingerprint(trial_old_route.candidate)
		var old_cert: Dictionary=Certification.certify_live(trial_reference,view,ship,trial_old_route.candidate,fingerprint,trial_old_budget)
		var new_cert: Dictionary=Certification._certify_refined_live(trial_live,view,ship,trial_new_route,fingerprint,trial_new_budget)
		check(old_cert.status=="valid" and old_cert==new_cert,"same-begin corridor result produces the complete unchanged live certificate")
		check(int(trial_new_budget.clearanceTests)<int(trial_old_budget.clearanceTests),"complete valid route uses fewer bounded clearance operations")
		comparisons.append({"islandDetour":not islands.is_empty(),"referenceClearance":trial_old_budget.clearanceTests,"combinedClearance":trial_new_budget.clearanceTests})
	# The approach crosses an actual ally. Its later pass crosses land and would
	# need a graph search, but no complete maneuver can use that blocked approach.
	var ally: Dictionary=ship.duplicate(true);ally.id="route-blocker";ally.x=675.0
	candidate.approach=[Vector2(600,850),Vector2(750,850)];candidate.pass=[Vector2(750,850),Vector2(1400,850)]
	var reference: Dictionary=route_state(ship,[island],[ally]);var live: Dictionary=route_state(ship,[island],[ally])
	var old_budget: Dictionary=route_budget();var new_budget: Dictionary=route_budget()
	var old_route: Dictionary=Routes.refine(reference,reference.tactical.geometry,ship,candidate,old_budget)
	var new_route: Dictionary=Routes.refine_live(live,live.tactical.geometry,ship,candidate,new_budget)
	check(old_route.status=="valid" and Certification.corridor(reference,ship,old_route.candidate,old_budget).status=="blocked" and new_route.status=="blocked","combined walk rejects the same actual allied approach conflict")
	check(int(old_budget.fullRoutes)>0 and int(new_budget.fullRoutes)==0 and int(new_budget.clearanceTests)<int(old_budget.clearanceTests),"blocked approach stops before the unusable pass/exit graph search")
	var pending_budget: Dictionary=route_budget();pending_budget.clearanceLimit=0
	check(Routes.refine_live(live,live.tactical.geometry,ship,candidate,pending_budget).status=="pending","exhausted route work remains pending and grants no corridor proof")
	report.routeComparisons=comparisons
	report.blockedApproach={"referenceClearance":old_budget.clearanceTests,"combinedClearance":new_budget.clearanceTests,"referenceSearches":old_budget.fullRoutes,"combinedSearches":new_budget.fullRoutes}

func authority_checks(st: Dictionary) -> void:
	var ship: Dictionary=st.ships[0]
	ship.x=600.0;ship.y=850.0
	st.ships[1].x=1700.0;st.ships[1].y=850.0
	check(Battle.issue_order(st,[str(ship.id)],"move",{"x":1000.0,"y":850.0}),"explicit clear-water move is accepted")
	for tick in range(2):Battle.update(st,DT)
	var intent: Dictionary=st.tactical.intents.get(str(ship.id),{})
	var record: Dictionary=st.tactical.predictions.get(str(intent.get("pathFingerprint","")),{})
	check(not record.is_empty(),"public movement obtains real live-step route authority")
	if record.is_empty():return
	check(str(record.certificate.scope)==Planner.LIVE_CERT_SCOPE and int(record.certificate.rolloutSamples)==0 and int(st.tactical.metrics.work.samples)==0,"live runtime does no detached future damage/physics replay or claimed forecast samples")
	check(Certification.current(st,ship,intent).ok and absf(float(st.time)-2.0*DT)<0.000001 and absf(float(ship.vx))>0.0,"actual boat moves at the retained sixty physical updates per second")
	check(not Certification.current(st,ship.duplicate(true),intent).ok,"same-ID ship copy cannot borrow live maneuver authority")
	var hp: float=ship.hp;ship.hp-=1.0
	check(not Certification.current(st,ship,intent).ok,"actual hull loss invalidates live authority immediately")
	ship.hp=hp
	var speed: float=ship.spec.speed;ship.spec.speed+=1.0
	check(not Certification.current(st,ship,intent).ok,"dynamics change invalidates live authority immediately")
	ship.spec.speed=speed
	var now: float=st.time;st.time=float(record.certificate.validUntil)+DT
	check(not Certification.current(st,ship,intent).ok,"expired bounded authority cannot steer or fire")
	st.time=now
	var budget: Dictionary={"clearanceTests":0,"clearanceLimit":4096,"exhaustions":0}
	var edge: Dictionary=ship.duplicate(true);edge.x=2295.0
	check(Certification.safe_step(st,edge,{"angle":0.0,"throttle":1.0},budget).get("blocked",false),"live next-step sweep refuses an actual boundary crossing")
	var ally: Dictionary=ship.duplicate(true);ally.id="fixture-close-ally";ally.x=ship.x+1.0
	st.tactical.cells=Routes.grid([ship,ally])
	budget={"clearanceTests":0,"clearanceLimit":4096,"exhaustions":0}
	check(Certification.safe_step(st,ship,{"angle":0.0,"throttle":1.0},budget).get("blocked",false),"live next-step sweep still refuses allied hull overlap")
	st.tactical.cells=Routes.grid(st.ships)
	check(Battle.issue_order(st,[str(ship.id)],"hold",{"x":ship.x,"y":ship.y}) and not Certification.current(st,ship,intent).ok,"new order revokes the previous maneuver immediately")
	Battle.set_autopilot(st,false)
	Battle.update(st,DT,{"forward":true,"right":true})
	check(str(st.tactical.manualId)==str(ship.id) and absf(float(st.time)-3.0*DT)<0.000001,"manual flagship retains direct per-tick helm authority")

func run() -> void:
	started=Time.get_ticks_usec()
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var created: Dictionary=Lab.create(world,{"player":[Lab.entry(world,"tin_skiff")],"enemy":[Lab.entry(world,"tin_skiff")]},4101)
	check(bool(created.get("ok",false)),"canonical fixture boats use actual public fitting and deployment")
	if bool(created.get("ok",false)):
		cache_checks(created.battle.ships[0])
		route_checks(created.battle.ships[0])
		authority_checks(created.battle)
		var benchmark=Benchmark.new()
		benchmark.action_sample(world,report,started)
		check(benchmark.failures.is_empty(),"shared compact action sample completes, moves both sides and emits/debits real automatic shots")
		report.actionFailures=benchmark.failures
	var folder: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	check(not folder.is_empty(),"Root supplies the focused artifact directory")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		var file=FileAccess.open(folder.path_join("COMBAT RUNTIME v0.041.json"),FileAccess.WRITE)
		check(file!=null,"focused artifact opens")
		if file!=null:
			report.fixture="combat_runtime041";report.complete=failures.is_empty();report.checks=checks;report.failures=failures;report.wallUs=Time.get_ticks_usec()-started
			file.store_string(JSON.stringify(report,"\t"));file.close()
	print("COMBAT_RUNTIME041 %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
