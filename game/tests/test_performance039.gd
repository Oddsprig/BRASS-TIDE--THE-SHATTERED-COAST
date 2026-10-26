extends SceneTree
## Fixed short simulation baseline. Root alone runs it through Test Bridge.
## No Main, renderer, input, saves, external preloads or production instrumentation.
const Campaign=preload("res://scripts/campaign.gd")
const Battle=preload("res://scripts/battle.gd")
const Damage=preload("res://scripts/damage.gd")
const Refit=preload("res://scripts/refit.gd")
const Records=preload("res://scripts/equipment_records.gd")
const EquipmentCombat=preload("res://scripts/equipment_combat.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Routes=preload("res://scripts/tactical_routes.gd")
const Money=preload("res://scripts/money.gd")
const EconomyWorkers=preload("res://scripts/economy_workers.gd")
const TradeFlow=preload("res://scripts/trade_flow.gd")
const Version=preload("res://scripts/version.gd")
const SEED: int=3901
const CAMPAIGN_DT: float=0.25
const CAMPAIGN_WARMUP: int=2
const CAMPAIGN_TICKS: int=8
const BATTLE_DT: float=1.0/30.0
const BATTLE_WARMUP: int=4
const BATTLE_TICKS: int=24
const ADMISSION_US: int=24000000
const FINISH_MARGIN_US: int=3000000
const CONTACT_SHIFT: float=300.0
# Stock fittings: 75+56+52+44+36+23+14 = 300 per side, fourteen total boats.
const HULL_IDS: Array=["maiden_dreadnought","manta_strike","cinder_monitor","slag_gunboat","gale_cutter","lantern_skiff","bilge_punt"]
var started_us: int=0
var checks: int=0
var failures: Array=[]
var stopped: Array=[]
var report: Dictionary={}
var c

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);print("FAIL performance039: "+message)

func admit(label: String,previous_us: int=0) -> bool:
	# Cooperative admission only: one synchronous public call cannot be preempted.
	# Root retains the external 30s process deadline. Never leave a worker unjoined.
	if Time.get_ticks_usec()-started_us+maxi(FINISH_MARGIN_US,previous_us*2)<ADMISSION_US:return true
	stopped.append(label)
	return false

func distribution(values: Array) -> Dictionary:
	if values.is_empty():return {"count":0,"medianUs":null,"p95Us":null,"maxUs":null,"totalUs":0}
	var sorted: Array=values.duplicate();sorted.sort()
	var count: int=sorted.size();var total: int=0;var middle: int=floori(float(count)/2.0)
	for value in sorted:total+=int(value)
	var median: float=float(sorted[middle]) if count%2 else (float(sorted[middle-1])+float(sorted[middle]))/2.0
	return {"count":count,"medianUs":median,"p95Us":int(sorted[ceili(count*0.95)-1]),"maxUs":int(sorted[-1]),"totalUs":total}

func memory() -> Dictionary:
	return {"engineStaticBytes":OS.get_static_memory_usage(),"engineStaticPeakBytes":OS.get_static_memory_peak_usage(),"note":"Godot static allocations, not process RSS or GPU memory. Process limits are imposed and recorded by Test Bridge."}

func campaign_window() -> void:
	var section: Dictionary={"warmupRequested":CAMPAIGN_WARMUP,"measuredRequested":CAMPAIGN_TICKS,"dtSeconds":CAMPAIGN_DT,"warmupUs":[],"ticksUs":[],"warmupCompleted":0,"measuredCompleted":0}
	report.campaign=section
	var before: int=Time.get_ticks_usec()
	c=Campaign.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json")))
	section.constructorUs=Time.get_ticks_usec()-before
	if not admit("campaign creation",int(section.constructorUs)):return
	before=Time.get_ticks_usec()
	var created: Dictionary=c.new_game(SEED)
	section.newGameUs=Time.get_ticks_usec()-before
	check(created.get("ok",false),"fresh campaign publishes canonical boats")
	if not created.get("ok",false):return
	var independent: Array=[]
	for owner in c.state.fleetOwners:
		if str(owner.id).begins_with("patrol-"):independent.append(str(owner.id))
	section.independentOwnerIds=independent;section.ownerCount=c.state.fleetOwners.size();section.portCount=c.state.ports.size()
	check(independent.size()==9 and c.state.patrols.size()==9,"fresh campaign retains all nine independent physical fleets")
	section.coinsBefore=Money.total(c.state);section.dayBefore=float(c.state.day)
	var previous: int=0
	for index in range(CAMPAIGN_WARMUP+CAMPAIGN_TICKS):
		if not admit("campaign tick %d"%index,previous):break
		before=Time.get_ticks_usec();c.step(CAMPAIGN_DT);previous=Time.get_ticks_usec()-before
		var key: String="warmupUs" if index<CAMPAIGN_WARMUP else "ticksUs"
		section[key].append(previous)
		section["warmupCompleted" if index<CAMPAIGN_WARMUP else "measuredCompleted"]+=1
	section.timing=distribution(section.ticksUs);section.dayAfter=float(c.state.day)
	section.routeCache={"hits":c.route_hits,"misses":c.route_misses,"entries":c.route_cache.size()}
	section.coinsAfter=Money.total(c.state);section.pendingDays=c.pending_days
	section.navalEncounterElapsed=float(c.state.get("navalEncounterElapsed",0.0))
	check(int(section.coinsAfter)==int(section.coinsBefore) and int(section.coinsAfter)==int(c.state.coinSupply),"short real campaign steps conserve all coin custody")
	check(is_finite(float(c.state.day)) and not c.state.fleet.is_empty(),"short campaign time and surviving physical fleet remain finite")

func make_fleet(team: String,known_uids: Array,catalog: Dictionary) -> Array:
	var fleet: Array=[]
	for hull_id in HULL_IDS:
		if not admit("canonical battle roster "+team+"/"+str(hull_id)):break
		var base: Dictionary=c.hull(str(hull_id))
		check(not base.is_empty(),"known benchmark hull "+str(hull_id))
		if base.is_empty():continue
		var ship: Dictionary=Damage.create_ship(base)
		ship.uid="performance039-%s-%d"%[team,fleet.size()]
		ship.loadout=Refit.defaults(base)
		var seeded: Dictionary=Records.initialize(ship,{"base":base,"loadout":ship.loadout,"catalog":catalog,"identity":ship.uid,"knownUids":known_uids})
		check(seeded.get("ok",false),"canonical battle equipment "+str(ship.uid))
		if not seeded.get("ok",false):continue
		known_uids.append_array(seeded.get("itemUids",[]));Refit.ensure(ship,base)
		# Isolated laboratory hulls, optimal numerical crew and full stock ammunition.
		# They are never appended to the paid campaign fleet or awarded to any owner.
		ship.ammo=float(ship.spec.ammoCapacity)
		fleet.append(ship)
	return fleet

func mix(ships: Array,team: String) -> Dictionary:
	var result: Dictionary={"boats":0,"points":0,"hulls":{},"weaponFamilies":{},"crew":0.0,"ammo":0.0}
	for ship in ships:
		if str(ship.team)!=team:continue
		result.boats+=1;result.points+=Deployment.cost(ship);result.crew+=float(ship.crew);result.ammo+=float(ship.ammo)
		result.hulls[str(ship.type)]=int(result.hulls.get(str(ship.type),0))+1
		for mount in ship.spec.weaponMounts:result.weaponFamilies[str(mount.kind)]=true
	return result

func battle_window() -> void:
	var section: Dictionary={"warmupRequested":BATTLE_WARMUP,"measuredRequested":BATTLE_TICKS,"dtSeconds":BATTLE_DT,"warmupUs":[],"ticksUs":[],"aiUs":[],"warmupCompleted":0,"measuredCompleted":0,"samples":[],"peakProjectiles":0,"peakEffects":0,"fireEvents":0,"fireByFamily":{},"peakActiveActors":0}
	report.battle=section
	if c==null or c.state.is_empty() or not admit("battle setup"):return
	var before: int=Time.get_ticks_usec();var known_uids: Array=[];var catalog: Dictionary=Refit.catalog()
	var players: Array=make_fleet("player",known_uids,catalog);var enemies: Array=make_fleet("enemy",known_uids,catalog)
	section.rosterUs=Time.get_ticks_usec()-before
	if players.size()!=HULL_IDS.size() or enemies.size()!=HULL_IDS.size():return
	check(Deployment.total(players)==300 and Deployment.total(enemies)==300,"both canonical mixed input fleets cost exactly 300 DP")
	if not admit("Battle.create"):return
	before=Time.get_ticks_usec()
	var battle: Dictionary=Battle.create({"fleet":players,"enemyFleet":enemies,"seed":SEED,"islands":[],"coastalEncounter":true,"location":{"name":"v0.039 fixed open-water contact baseline"}})
	section.createUs=Time.get_ticks_usec()-before
	check(not battle.has("startError") and battle.ships.size()==HULL_IDS.size()*2,"public Battle.create deploys all fourteen boats")
	if battle.has("startError"):section.startError=str(battle.startError);return
	section.deployment=battle.deployment.duplicate(true)
	check(int(battle.deployment.player)==300 and int(battle.deployment.enemy)==300 and battle.reserves.player.is_empty() and battle.reserves.enemy.is_empty(),"actual deployment is 300 DP per side with no hidden reserves")
	# Keep the public formation's rows and headings in explicit open water; translate
	# each side 300 units toward contact to exercise firing in this short window.
	# Translate its existing retreat home by the identical offset before any tick.
	var geometry: Dictionary=Routes.terrain(battle);var clear: bool=true;var poses: Array=[]
	for ship in battle.ships:
		var offset: float=CONTACT_SHIFT if ship.team=="player" else -CONTACT_SHIFT
		ship.x+=offset;battle.tactical.home[ship.id].x+=offset
		var point: Vector2=Vector2(float(ship.x),float(ship.y))
		clear=clear and Routes.sweep(geometry,point,point,Routes.planning_radius(ship),{"clearanceTests":0,"clearanceLimit":4096,"exhaustions":0})=="valid"
		poses.append({"uid":ship.uid,"x":ship.x,"y":ship.y,"angle":ship.angle})
	check(clear and battle.autopilot,"fixed contact starts retain safe terrain clearance and default autopilot")
	section.initialPoses=poses;section.initial={"player":mix(battle.ships,"player"),"enemy":mix(battle.ships,"enemy")}
	check(int(section.initial.player.points)==300 and int(section.initial.enemy.points)==300,"measured actors independently account for the full DP")
	var previous: int=0
	for index in range(BATTLE_WARMUP+BATTLE_TICKS):
		if not admit("battle tick %d"%index,previous) or battle.result!=null:break
		before=Time.get_ticks_usec();Battle.update(battle,BATTLE_DT,{});previous=Time.get_ticks_usec()-before
		var measured: bool=index>=BATTLE_WARMUP
		section["ticksUs" if measured else "warmupUs"].append(previous)
		section["measuredCompleted" if measured else "warmupCompleted"]+=1
		var metrics: Dictionary=battle.tactical.metrics
		var fires: int=0
		for event in Battle.pop_events(battle):
			if str(event.kind)=="fire":
				fires+=1;section.fireByFamily[str(event.family)]=int(section.fireByFamily.get(str(event.family),0))+1
		section.fireEvents+=fires
		section.peakProjectiles=maxi(int(section.peakProjectiles),battle.projectiles.size());section.peakEffects=maxi(int(section.peakEffects),battle.effects.size())
		section.peakActiveActors=maxi(int(section.peakActiveActors),int(metrics.activeCount))
		if measured:
			section.aiUs.append(int(metrics.aiUs))
			section.samples.append({"tick":index-BATTLE_WARMUP+1,"time":float(battle.time),"updateUs":previous,"aiUs":int(metrics.aiUs),"activeActors":int(metrics.activeCount),"fireEvents":fires,"projectiles":battle.projectiles.size(),"effects":battle.effects.size(),"work":metrics.work.duplicate(true)})
	section.timing=distribution(section.ticksUs);section.aiTiming=distribution(section.aiUs)
	section.simulatedSeconds=float(battle.time);section.result=battle.result
	section.final={"player":mix(battle.ships,"player"),"enemy":mix(battle.ships,"enemy")}
	section.tacticalCounters=battle.tactical.counters.duplicate(true);section.droppedEvents=int(battle.droppedEvents)
	section.memory=memory()
	var finite: bool=true;var canonical: bool=true
	for ship in battle.ships:
		canonical=canonical and EquipmentCombat.is_canonical_owner(ship)
		for key in ["hp","water","engine","crew","ammo","fuel","supplies","x","y"]:finite=finite and is_finite(float(ship[key]))
		for key in ["hp","water","crew","ammo","fuel","supplies"]:finite=finite and float(ship[key])>=0.0
	check(finite and canonical,"measured boats retain finite nonnegative state and canonical equipment")
	check(int(section.fireEvents)>0 and int(section.peakProjectiles)>0,"short fixed contact window includes real AI firing and physical projectiles")
	check(float(section.final.player.ammo)+float(section.final.enemy.ammo)<=float(section.initial.player.ammo)+float(section.initial.enemy.ammo),"battle cannot create stock ammunition")
	check(int(section.peakProjectiles)<=400 and int(section.peakEffects)<=200 and int(section.droppedEvents)==0,"actual projectile/effect bounds and observable event custody hold")

func paid_day() -> void:
	var section: Dictionary={"daysRequested":1,"daysCompleted":0,"note":"Same detached EconomyWorkers and main-thread Campaign.apply_economy path used by Main.sync_economy; one existing wait_day only."}
	report.paidEconomy=section
	if c==null or c.state.is_empty() or not admit("one paid worker day"):return
	var coins: int=Money.total(c.state);var econ_day: int=int(c.state.econDay)
	c.wait_day();c.pending_days-=1
	var workers=EconomyWorkers.new();var before: int=Time.get_ticks_usec()
	workers.start(c.state.ports,1,TradeFlow.blockades(c),int(c.state.seed)+econ_day*104729)
	var completed: Dictionary=workers.finish(true) # Always join our own copied jobs.
	section.workerUs=Time.get_ticks_usec()-before;section.workerReportedUs=int(completed.elapsedUs)
	section.workerLanes=int(completed.workers);section.portCount=completed.ports.size();section.workerEvents=completed.events.size()
	section.payroll={"business":0,"public":0,"household":0,"expert":0,"tax":0,"total":0};section.paidWorkers=0
	for port in completed.ports:
		section.paidWorkers+=int(port.get("lastPaid",0))
		for key in section.payroll:section.payroll[key]+=int(port.get("lastPayroll",{}).get(key,0))
	check(Money.total(c.state)==coins,"detached harbor work leaves live coin custody untouched before publication")
	before=Time.get_ticks_usec();c.apply_economy(completed.ports,completed.events,completed.days)
	section.publicationUs=Time.get_ticks_usec()-before;section.daysCompleted=int(completed.days)
	section.coinsBefore=coins;section.coinsAfter=Money.total(c.state);section.econDayBefore=econ_day;section.econDayAfter=int(c.state.econDay)
	check(int(section.paidWorkers)>0 and int(section.payroll.total)>0,"one actual harbor worker day pays finite existing purses")
	check(int(section.coinsAfter)==coins and int(section.coinsAfter)==int(c.state.coinSupply) and int(c.state.econDay)==econ_day+1 and c.pending_days==0,"paid harbor and fleet publication conserves coins and resolves exactly one day")

func _initialize() -> void:
	started_us=Time.get_ticks_usec()
	if DisplayServer.get_name()!="headless":
		check(false,"requires the Root-owned headless/Dummy Test Bridge invocation")
		print("%d checks, %d failures"%[checks,failures.size()]);quit(1);return
	var workload: Dictionary={"seed":SEED,"hullsPerSide":HULL_IDS,"stockCanonicalEquipment":true,"campaign":{"warmup":CAMPAIGN_WARMUP,"ticks":CAMPAIGN_TICKS,"dt":CAMPAIGN_DT},"battle":{"warmup":BATTLE_WARMUP,"ticks":BATTLE_TICKS,"dt":BATTLE_DT,"contactShift":CONTACT_SHIFT,"terrain":"Explicit open water: islands:[], coastalEncounter:true"},"paidWorkerDays":1}
	report={"schema":1,"fixture":"performance039","workload":workload,"workloadSha256":JSON.stringify(workload).sha256_text(),"fixtureSha256":FileAccess.get_sha256(get_script().resource_path),"worldSha256":FileAccess.get_sha256("res://data/world.json"),"sourceBinding":"Root's exact-source Test Bridge receipt binds all res:// scripts. No measured code is preloaded outside the project.","gameVersion":Version.text(),"engine":Engine.get_version_info(),"logicalProcessorsObserved":OS.get_processor_count(),"envelope":{"headless":true,"audioDriverRequired":"Dummy in external invocation","gpuMeasured":false,"rendered":false,"externallyRequiredGameMiB":512,"externallyRequiredBuilderMiB":1024,"externallyRequiredJobCpuPercent":8,"externallyRequiredLogicalCpuLimit":2,"externalProcessDeadlineSeconds":30,"admissionDeadlineUs":ADMISSION_US,"minimumFinishMarginUs":FINISH_MARGIN_US,"enforcement":"Test Bridge owns job memory/CPU/affinity/deadline and records the actual envelope; this fixture does not change system settings."},"memoryBefore":memory(),"limits":"Short CPU simulation sample, not GPU FPS, long-run throughput, presentation, sound or full-game acceptance. AI aggregate clocks overlap the total update timing; other phases are not separately instrumented. Preload/import/engine startup and queue wait are outside the fixture wall clock; the owning batch records them separately."}
	campaign_window()
	battle_window()
	paid_day()
	var complete: bool=int(report.campaign.warmupCompleted)==CAMPAIGN_WARMUP and int(report.campaign.measuredCompleted)==CAMPAIGN_TICKS and int(report.battle.warmupCompleted)==BATTLE_WARMUP and int(report.battle.measuredCompleted)==BATTLE_TICKS and int(report.paidEconomy.daysCompleted)==1
	check(complete,"all fixed requested windows complete; any guard stop is partial measurement, never a pass")
	check(Time.get_ticks_usec()-started_us<30000000,"cooperative work finishes before the external 30-second process boundary")
	report.complete=complete;report.status="complete" if complete else "partial";report.guardStops=stopped;report.memoryAfter=memory();report.wallUs=Time.get_ticks_usec()-started_us
	var folder: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	check(not folder.is_empty(),"GAME_TEST_ARTIFACTS supplies an explicit evidence destination")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		var file=FileAccess.open(folder.path_join("PERFORMANCE v0.039.json"),FileAccess.WRITE)
		check(file!=null,"performance artifact opens")
		if file!=null:
			report.checks=checks;report.failures=failures;file.store_string(JSON.stringify(report,"\t"));file.close()
	print("PERFORMANCE039 %s: campaign %d/%d, battle %d/%d measured ticks; %dus fixture wall"%[report.status,int(report.campaign.measuredCompleted),CAMPAIGN_TICKS,int(report.battle.measuredCompleted),BATTLE_TICKS,int(report.wallUs)])
	print("%d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
