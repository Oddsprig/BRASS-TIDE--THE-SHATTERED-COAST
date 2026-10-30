extends RefCounted
## Explicit, source-candidate observer of the real Main/Lab/Chart runtime.
## Root supplies the exported binary, private desktop, synthetic APPDATA and lane.
const Lab=preload("res://scripts/fleet_lab.gd")
const Battle=preload("res://scripts/battle.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Damage=preload("res://scripts/damage.gd")
const Tactical=preload("res://scripts/tactical_runtime.gd")
const Routes=preload("res://scripts/tactical_routes.gd")
const Preferences=preload("res://scripts/preferences.gd")
const WARMUP_US: int=3000000
const ACTIVE_US: int=12000000
const WALL_LIMIT_US: int=68000000 # One 70s external bound; reserve 2s for final cleanup.
const EVENT_LIMIT: int=20000
const WORKER_STEP: float=1.0/30.0
const WORKER_BUDGET_US: float=1000000.0/30.0
const MAIN_PUBLICATION_BUDGET_US: int=6000
const LAG_BUDGET_US: int=100000
const ROSTERS={
	"light":[["bilge_punt",15],["tin_skiff",6]],
	"mixed":[["tin_skiff",1],["ash_corvette",1],["brasswind_motor_galleon",2],["reed_stinger",1],["barbed_lance",1],["slag_gunboat",1],["gale_cutter",1]]
}
var host
var preferences_path: String=""
var save_directory: String=""
var output: String=""
var rendered: bool=false
var render_verified: bool=false
var detailed_counters: bool=true
var stage: String="boot"
var requested: Array=["light","mixed"]
var results: Array=[]
var current: Dictionary={}
var started_us: int=0
var phase_us: int=0
var last_draw_us: int=0
var active_us: int=0
var active_sim: float=0.0
var frame_ticks: int=0
var frame_sim_us: int=0
var last_state: Dictionary={}
var positions: Dictionary={}
var moved: Dictionary={}
var distance_m: float=0.0
var last_sample_us: int=0
var errors: Array=[]
var last_worker_steps: int=0
var last_worker_time: float=0.0
var frame_worker_steps: int=0
var frame_polls: int=0
var last_event_seq: int=0
var published: Dictionary={}
var idle_since051: Dictionary={}
var main_thread_id051: int=0
var hold_probe_issued072: bool=false
var hold_probe_seq_floor072: int=0

func prepare(game_host) -> bool:
	host=game_host
	main_thread_id051=OS.get_thread_caller_id()
	started_us=Time.get_ticks_usec()
	var counter_setting: String=OS.get_environment("BRASS_TIDE_RUNTIME043_COUNTERS")
	if counter_setting not in ["","on","off"]:
		push_error("BRASS_TIDE_RUNTIME043_COUNTERS must be empty, on or off.")
		return false
	detailed_counters=counter_setting!="off"
	var root: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if root.is_empty() or not root.is_absolute_path():
		push_error("--qa-runtime043 requires an absolute GAME_TEST_ARTIFACTS directory.")
		return false
	if "--fixed-fps" in OS.get_cmdline_args() or Engine.physics_ticks_per_second!=60 or not is_equal_approx(Engine.time_scale,1.0):
		push_error("Runtime043 requires real-time Engine 60Hz with worker battle 30Hz; fixed FPS/time scale is unsupported.")
		return false
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--qa-runtime043-case="):
			var selected: String=str(arg).trim_prefix("--qa-runtime043-case=")
			if selected not in ["both","light","mixed"]:
				push_error("Runtime043 case must be light, mixed or both.")
				return false
			if selected!="both":requested=[selected]
		elif str(arg).begins_with("--qa-") and str(arg)!="--qa-runtime043":
			push_error("Runtime043 must run alone; other --qa- hooks are incompatible.")
			return false
	output=root.path_join("runtime043-%d-%d"%[OS.get_process_id(),started_us])
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output.path_join("profile/saves"))!=OK:
		push_error("Cannot create a fresh runtime043 artifact/profile directory.")
		return false
	preferences_path=output.path_join("profile/settings.json")
	save_directory=output.path_join("profile/saves")
	var adapter: String=RenderingServer.get_video_adapter_name()
	var renderer: String=str(_optional(RenderingServer,"get_current_rendering_method"))
	rendered=DisplayServer.get_name()!="headless" and not adapter.is_empty() and not "dummy" in adapter.to_lower() and renderer!="dummy"
	return true

func options() -> Dictionary:
	# Do not read the installed portable preferences or the owner's user profile.
	var result: Dictionary=Preferences.defaults()
	result.audio_enabled=false;result.music_enabled=false;result.fullscreen=false
	result.weapon_volume=0.0;result.ambience_volume=0.0;result.music_volume=0.0
	return result

func _optional(target: Object,method: String,args: Array=[]):
	return target.callv(method,args) if target.has_method(method) else null

func _counters(enabled: bool,reset: bool=false) -> void:
	var detailed_enabled: bool=enabled and detailed_counters
	_optional(host.chart,"profile_enable",[detailed_enabled])
	# Shared numerical sinks cannot be enabled across worker/UI readers. Driver
	# publishes actual job/phase costs independently; on/off still controls Chart.
	Damage.set_runtime_profile043(false)
	Tactical.set_runtime_profile043(false)
	Routes._profile_veto051(false,reset)
	if reset:
		Damage.reset_runtime_profile043()
		Tactical.reset_runtime_profile043()
	if reset:_optional(host.chart,"profile_reset")

func _counter_metadata() -> Dictionary:
	return {"requestedMode":"on" if detailed_counters else "off","detailedEnabledDuringCases":detailed_counters,"actualChartDetail":detailed_counters,"actualWorkerFineSinks":false,"mode":"DETAILED COUNTERS" if detailed_counters else "NORMAL-RUNTIME CONTROL","environment":"BRASS_TIDE_RUNTIME043_COUNTERS","workerFineCounters":"Shared Damage/Records/Tactical/Routes sinks disabled for worker ownership; unavailable, never zero-cost attribution.","scope":"Same CLI on/off controls Main Chart detail. Actual worker job/phase/publication/lag sampling and every acceptance gate remain active in both modes. New worker30Hz cohort; frozen60Hz reports remain historical."}

func start() -> void:
	if stage!="boot":return
	_write_json("runtime043-start.json",{"schema":2,"readyToStartWallUs":Time.get_ticks_usec()-started_us,"hardware":_hardware(),"counterMode":_counter_metadata(),"cases":requested,"limits":_limits()})
	if not rendered:
		_abort("Headless/dummy rendering unavailable; no rendered FPS evidence or verdict.")
		return
	RenderingServer.frame_post_draw.connect(_after_draw)
	host.get_tree().physics_frame.connect(_engine_callback051)
	_start_case()

func _hardware() -> Dictionary:
	# Damage/Tactical counters are compiled static APIs in Root's instrumented baseline.
	return {"engine":Engine.get_version_info(),"os":OS.get_name(),"cpu":OS.get_processor_name(),"logicalCPUs":OS.get_processor_count(),"pid":OS.get_process_id(),"editor":OS.has_feature("editor"),"template":OS.has_feature("template"),"release":OS.has_feature("release"),"debugBuild":OS.is_debug_build(),"exported":_exported_release(),"templateRelease":_exported_release(),"displayServer":DisplayServer.get_name(),"rendererCandidate":rendered,"renderedAvailable":rendered and render_verified,"windowVisible":host.get_window().visible,"adapter":RenderingServer.get_video_adapter_name(),"adapterVendor":_optional(RenderingServer,"get_video_adapter_vendor"),"apiVersion":_optional(RenderingServer,"get_video_adapter_api_version"),"renderingMethod":_optional(RenderingServer,"get_current_rendering_method"),"renderingDriver":_optional(RenderingServer,"get_current_rendering_driver_name"),"windowPixels":[host.get_tree().root.size.x,host.get_tree().root.size.y],"viewportRect":_viewport_size(),"threadModel":ProjectSettings.get_setting("rendering/driver/threads/thread_model"),"physicsHz":Engine.physics_ticks_per_second,"maxPhysicsStepsPerFrame":Engine.max_physics_steps_per_frame,"timeScale":Engine.time_scale,"frameCap":Engine.max_fps,"processPriority":null,"resourceEnvelope":"Record actual priority/affinity/job CPU and memory limits in Root's external owned-process wrapper.","memory":_memory(),"counterMode":_counter_metadata(),"counterAPIs":{"chart":host.chart.has_method("profile_read"),"damage":true,"tactical":true}}

func _exported_release() -> bool:
	return OS.has_feature("template") and OS.has_feature("release") and not OS.has_feature("editor") and not OS.is_debug_build()

func _viewport_size() -> Array:
	var size: Vector2=host.get_viewport().get_visible_rect().size
	return [size.x,size.y]

func _render_sample() -> Dictionary:
	var viewport: RID=host.get_viewport().get_viewport_rid()
	return {"windowVisible":host.get_window().visible,"canvasObjects":RenderingServer.viewport_get_render_info(viewport,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),"canvasDrawCalls":RenderingServer.viewport_get_render_info(viewport,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),"performanceObjects":int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),"performanceDrawCalls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),"serverGlobalObjects":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),"serverGlobalDrawCalls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),"scope":"Per-viewport CANVAS counters prove 2D work. Global/Performance counters are also recorded but may cover only 3D and be zero in this 2D game."}

func _memory() -> Dictionary:
	return {"engineStaticBytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)) if OS.is_debug_build() else null,"engineStaticPeakBytes":int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) if OS.is_debug_build() else null,"engineStaticSupported":OS.is_debug_build(),"renderVideoBytes":int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) if rendered else null,"renderTextureBytes":int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) if rendered else null,"renderBufferBytes":int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) if rendered else null,"scope":"Godot allocation counters; static allocation monitors unsupported in release are null. Zero VRAM may mean unsupported. Not process working set or adapter capacity. Wrapper must sample process working set/CPU and resource limits separately.","adapterCapacityBytes":null}

func _limits() -> Dictionary:
	return {"cohort":"owner-authorized worker30Hz / Engine60Hz / independent interpolated rendering","warmupWallUs":WARMUP_US,"activeWallUs":ACTIVE_US,"cooperativeReadyToFinishUs":WALL_LIMIT_US,"wrapperGlobalLimitUs":70000000,"physics":"Actual Main/Lab driver only. Jobs may batch real fixed1/30 steps; completedSteps and stepsInJob must agree. Engine callbacks are separate. No observer simulation updates.","workerStepBudgetUs":WORKER_BUDGET_US,"mainPublicationP95BudgetUs":MAIN_PUBLICATION_BUDGET_US,"simulationLagBudgetUs":LAG_BUDGET_US,"historicalMainSimulationTarget":"median6ms/P9510ms at60Hz is historical and not an acceptance gate for worker30Hz","frames":"Consecutive frame_post_draw intervals; Chart.presentation_us is CPU submission, not GPU/display duration. Headless/dummy rejected.","catchUp":"Engine callbacks/draw and completed worker steps/draw are separate; acceptance uses worker real-time lag and wall-minus-authoritative-time deficit.","observer":"In-memory rows only during active interval. Snapshot/job/publication costs read from joined published data; no concurrent worker-global reads.","safety":"Root owns shared TestBridge FIFO, private desktop, synthetic APPDATA, muted audio, external70s whole bound including setup/captures/retirement/cleanup. Cooperative68s clock cannot interrupt blocked joins/readback/filesystem.","sourceStatus":"Source candidate; no native/rendered pass, speed claim or version acceptance implied.","orderProbe072":"Once per active case, after about 1s, one public Battle.issue_order Hold on one living player boat through the Main mirror. Records queueMonotonicUs. The exact joined row is sequence priorLastCommandSequence+1 and kind order, and its sequence, kind and ok are kept. observedMonotonicUs is Main's clock at that observation. queueToJoinedObservationUs is the difference and includes scheduling and poll delay. It is not internal execution time or workerJobUs. No exact row leaves it unavailable. Sample durations and strict gates are unchanged."}

func _start_case() -> void:
	if results.size()>=requested.size():
		_finish()
		return
	if Time.get_ticks_usec()-started_us>=WALL_LIMIT_US:
		_abort("No global time remains for another case.")
		return
	current={}
	render_verified=false
	var id: String=str(requested[results.size()])
	var config: Dictionary={"player":[],"enemy":[]}
	for team in ["player","enemy"]:
		for item in ROSTERS[id]:config[team].append(Lab.entry(host.data,str(item[0]),int(item[1])))
	var checked: Dictionary=Lab.inspect(host.data,config)
	if not bool(checked.get("ok",false)) or int(checked.player.points)!=300 or int(checked.enemy.points)!=300:
		_abort("Public Lab.inspect rejected the exact 300-DP stock roster: "+str(checked))
		return
	var load_started: int=Time.get_ticks_usec()
	host.lab_config=config;host.lab_seed=43043 if id=="light" else 43044
	current={"id":id,"seed":host.lab_seed,"config":config,"inspected":checked,"createdAtUs":load_started-started_us,"frames":[],"ticks":[],"mainPolls":[],"engineTicks":[],"events":[],"eventKinds":{},"eventFamilies":{},"activeEventKinds":{},"activeFireFamilies":{},"eventsOmitted":0,"screenshots":[],"complete":false,"workerSequenceErrors":[],"duplicateEventSeqs":[]}
	host.start_lab(configure_battle051)
	if host.mode!="battle" or not host.lab_active or host.battle.is_empty():
		_abort("Public Main.start_lab did not enter a real Lab battle.")
		return
	# Warm the renderer before combat, so opening missile salvos are measured.
	# This isolated Lab pause ends before the first measured physics tick.
	host.paused=true
	current.loadUs=Time.get_ticks_usec()-load_started
	if not current.has("actual") or host.battle_driver051==null:
		_abort("Actual Main entry did not call configure_battle051 before attaching its worker driver.")
		return
	if int(current.actual.playerDP)!=300 or int(current.actual.enemyDP)!=300 or int(current.actual.reservePlayer)!=0 or int(current.actual.reserveEnemy)!=0 or int(current.actual.actors)!=(42 if id=="light" else 16):
		_abort("Actual deployment does not match the requested full stock 300-vs-300 actors.")
		return
	host.chart.follow_camera=false;host.chart.camera=Vector2(1145,838)
	current.camera={"x":1145,"y":838,"zoom":host.chart.zoom,"follow":false,"note":"Declared fixed normal battle camera; no tactical overview or window manipulation."}
	current.islands=host.battle.islands.duplicate(true)
	current.initialMemory=_memory();current.initialState=_state_sample();last_state=current.initialState
	current.counterScope="Main Chart detail is optional. Shared numerical fine sinks are disabled; copied joined job/phase telemetry remains available in both modes. No worker-global counter reads."
	current.counterMode=_counter_metadata()
	current.phaseScope="Published phaseUs/planningDetailUs/work describe the last authoritative step of a joined job; whole workerJobUs includes all actual steps, boot, commands, snapshot and teardown. Batch normalization is capacity, not individually timed steps."
	published=host.battle_driver051.telemetry()
	last_worker_steps=int(published.get("completedSteps",0));last_worker_time=float(published.get("stateTime",0.0));last_event_seq=0
	frame_ticks=0;frame_sim_us=0;frame_worker_steps=0;frame_polls=0;last_draw_us=0;last_sample_us=0
	hold_probe_issued072=false;hold_probe_seq_floor072=0
	stage="opening";phase_us=Time.get_ticks_usec()

func configure_battle051(st: Dictionary) -> void:
	# Main calls once before Driver.new; these are initial conditions, not writes
	# into a live mirror or synthetic movement/fire during the measured interval.
	if current.is_empty() or not current.has("id"):return
	var id: String=str(current.id)
	var roster: Array=[]
	positions.clear();moved.clear();idle_since051.clear();distance_m=0.0
	# Bounded fixture formation only: three columns, seven possible rows, in the
	# unchanged default islands' open central corridor. AI/physics choose all motion.
	var counts: Dictionary={"player":0,"enemy":0}
	var teams: Dictionary={"player":[],"enemy":[]}
	for ship in st.ships:
		var team: String=str(ship.team)
		var index: int=int(counts[team]);counts[team]=index+1
		var row: int=index%7;var column: int=index/7
		ship.x=1000.0-column*76.0 if team=="player" else 1290.0+column*76.0
		ship.y=610.0+row*76.0
		ship.angle=0.0 if team=="player" else PI
		ship.turretAngle=ship.angle
		positions[str(ship.id)]=Vector2(ship.x,ship.y)
		teams[team].append(ship)
		roster.append({"id":ship.id,"hull":ship.spec.id,"team":team,"dp":Deployment.cost(ship),"x":ship.x,"y":ship.y,"angle":ship.angle,"loadout":ship.loadout.duplicate(true),"ammo":ship.ammo,"fuel":ship.fuel,"supplies":ship.supplies,"crew":ship.crew})
	current.roster=roster
	current.preExistingDamage=[]
	if id=="light":
		# Declared damaged-fleet workload: real pumps/patchers must handle water.
		# No synthetic hit/fire events or changed hull/weapon/crew statistics.
		for team in ["player","enemy"]:
			var damaged: Dictionary=teams[team][0]
			damaged.breaches.append({"area":6.0,"section":"waterline"})
			damaged.water=float(damaged.capacity)*0.08
			current.preExistingDamage.append({"id":damaged.id,"breachCm2":6.0,"waterLitres":damaged.water,"source":"Declared initial Lab battle damage"})
	current.actual={"actors":st.ships.size(),"playerActors":counts.player,"enemyActors":counts.enemy,"playerDP":Deployment.total(teams.player),"enemyDP":Deployment.total(teams.enemy),"deployment":st.deployment.duplicate(true),"reservePlayer":st.reserves.player.size(),"reserveEnemy":st.reserves.enemy.size()}
	_counters(true,true)

func _opening() -> void:
	current.firstFrameLoadUs=Time.get_ticks_usec()-started_us-int(current.createdAtUs)
	if rendered:_capture("opening")
	if not errors.is_empty():
		rendered=false
		_abort("Opening actual viewport image is unavailable/blank; rendered FPS unavailable.")
		return
	current.firstFrameAndOpeningPngUs=Time.get_ticks_usec()-started_us-int(current.createdAtUs)
	stage="warmup";phase_us=Time.get_ticks_usec();last_draw_us=0

func after_process(_dt: float) -> void:
	if stage in ["boot","done"]:return
	var now: int=Time.get_ticks_usec()
	if now-started_us>=WALL_LIMIT_US:
		_abort("Global cooperative runtime bound reached; incomplete evidence.")
		return
	if stage in ["opening","end"] and now-phase_us>2000000:
		_abort("No frame_post_draw within the bounded screenshot window.")
		return
	if stage in ["warmup","active"] and last_draw_us>0 and now-last_draw_us>2000000:
		_abort("Renderer stopped producing frame_post_draw; incomplete evidence.")

func after_physics(dt: float) -> void:
	# Retained public hook for historical synchronous callers. Engine coverage in
	# this cohort is connected once to SceneTree.physics_frame, not this hook.
	if not is_equal_approx(dt,1.0/60.0) and not current.is_empty():current["non60HzDtObserved"]=true

func _engine_callback051() -> void:
	if stage not in ["opening","warmup","active"] or current.is_empty():return
	if Engine.physics_ticks_per_second!=60:current["non60HzDtObserved"]=true
	current.engineTicks.append({"phase":stage,"wallUs":Time.get_ticks_usec()-started_us,"dt":1.0/float(Engine.physics_ticks_per_second)})
	frame_ticks+=1

func after_battle_publication051(_dt: float) -> void:
	if stage in ["opening","warmup","active"]:_sample_worker051()

func _sample_worker051() -> void:
	if host.battle_driver051==null:return
	var observed: int=Time.get_ticks_usec()
	published=host.battle_driver051.telemetry()
	_observe_hold_ack072()
	var steps: int=int(published.get("completedSteps",0))
	var state_time: float=float(published.get("stateTime",0.0))
	var added: int=steps-last_worker_steps
	var poll: Dictionary={"phase":stage,"wallUs":observed-started_us,"mainPollUs":published.get("mainPollUs"),"mainPublicationUs":host.simulation_us,"simulationLagSeconds":published.get("simulationLagSeconds"),"completedSteps":steps,"stateTime":state_time}
	current.mainPolls.append(poll);frame_polls+=1
	frame_sim_us+=int(host.simulation_us)
	if added==0:
		poll.observerUs=Time.get_ticks_usec()-observed
		return
	if added!=int(published.get("stepsInJob",0)) or added<0 or not is_equal_approx(state_time-last_worker_time,WORKER_STEP*added):
		current.workerSequenceErrors.append({"from":last_worker_steps,"to":steps,"fromTime":last_worker_time,"toTime":state_time})
	var st: Dictionary=host.battle
	var metrics: Dictionary=st.get("tactical",{}).get("metrics",{})
	var row: Dictionary={"phase":stage,"wallUs":observed-started_us,"simTime":state_time,"dt":WORKER_STEP,"completedSteps":steps,"completedStepDelta":added,"simulationUs":published.get("workerJobUs"),"workerJobUs":published.get("workerJobUs"),"snapshotUs":published.get("snapshotUs"),"workerThreadId":published.get("workerThreadId"),"workerStepHz":published.get("workerStepHz"),"mainPollUs":published.get("mainPollUs"),"simulationLagSeconds":published.get("simulationLagSeconds"),"aiUs":metrics.get("aiUs"),"phaseUs":metrics.get("phaseUs",{}).duplicate(true),"planningDetailUs":metrics.get("planningDetailUs",{}).duplicate(true),"work":metrics.get("work",{}).duplicate(true),"damageCounters":published.get("damageCounters"),"tacticalCounters":published.get("tacticalCounters")}
	last_worker_steps=steps;last_worker_time=state_time;frame_worker_steps+=maxi(0,added)
	last_state=_state_sample()
	row.state=last_state
	row.observerUs=Time.get_ticks_usec()-observed
	poll.observerUs=row.observerUs
	current.ticks.append(row)

func observe_events051(events: Array) -> void:
	if stage not in ["opening","warmup","active","end"] or current.is_empty():return
	var observed: int=Time.get_ticks_usec()
	for event in events:
		var sequence: int=int(event.seq)
		if sequence<=last_event_seq:
			current.duplicateEventSeqs.append(sequence)
			continue
		last_event_seq=sequence
		var kind: String=str(event.kind);var family: String=str(event.family)
		current.eventKinds[kind]=int(current.eventKinds.get(kind,0))+1
		current.eventFamilies[family]=int(current.eventFamilies.get(family,0))+1
		if stage=="active":
			current.activeEventKinds[kind]=int(current.activeEventKinds.get(kind,0))+1
			if kind=="fire":current.activeFireFamilies[family]=int(current.activeFireFamilies.get(family,0))+1
		if current.events.size()<EVENT_LIMIT:
			current.events.append({"phase":stage,"wallUs":observed-started_us,"time":event.time,"seq":event.seq,"kind":kind,"family":family,"projectileKind":event.projectileKind,"source":event.sourceId,"target":event.targetId,"damage":event.damage,"breach":event.breach,"x":event.x,"y":event.y})
		else:current.eventsOmitted+=1

func _state_sample() -> Dictionary:
	var value: Dictionary={"actors":host.battle.ships.size(),"autopilot":host.battle.autopilot,"livePlayer":0,"liveEnemy":0,"moving":0,"flooding":0,"waterLitres":0.0,"fire":0.0,"projectiles":host.battle.projectiles.size(),"missiles":0,"effects":host.battle.effects.size(),"droppedEvents":int(host.battle.get("droppedEvents",0)),"ammo":0.0,"fuel":0.0,"supplies":0.0,"hp":0.0,"result":host.battle.result}
	for ship in host.battle.ships:
		var id: String=str(ship.id);var at: Vector2=Vector2(ship.x,ship.y)
		distance_m+=at.distance_to(positions.get(id,at));positions[id]=at
		if Vector2(ship.vx,ship.vy).length()>0.1:value.moving+=1;moved[id]=true
		var idle: bool=not ship.sunk and not ship.get("captureSecured",false) and not host.battle.get("tactical",{}).get("intents",{}).has(id) and Vector2(ship.vx,ship.vy).length_squared()<0.01
		if idle and not idle_since051.has(id):idle_since051[id]=float(host.battle.time)
		elif not idle:idle_since051.erase(id)
		if not ship.sunk:
			if ship.team=="player":value.livePlayer+=1
			else:value.liveEnemy+=1
		if float(ship.water)>0.0001:value.flooding+=1
		value.waterLitres+=float(ship.water);value.fire+=float(ship.fire)
		for key in ["ammo","fuel","supplies","hp"]:value[key]+=float(ship[key])
	for projectile in host.battle.projectiles:
		if str(projectile.kind) in ["rocket","torpedo"]:value.missiles+=1
	value.movedActors=moved.size();value.distanceMetres=distance_m
	return value

func _after_draw() -> void:
	if stage=="done":return
	if Time.get_ticks_usec()-started_us>=WALL_LIMIT_US:
		_abort("Global bound reached after renderer; incomplete evidence.")
		return
	if stage=="opening":
		_opening()
	elif stage=="end":
		# A real subsequent draw presents the joined final mirror. Read back only
		# after that draw, with physics stopped and every owned task retired.
		_capture("end")
		_end_case()
	elif stage in ["warmup","active"]:
		_sample_frame("frame_post_draw")
		var now: int=last_draw_us
		var stopped: bool=host.battle.result!=null or host.result_handled or (stage=="active" and host.paused) or host.ui.modal_open
		if stage=="warmup" and stopped:
			_abort("Battle stopped during warmup; active interval was not measured.")
			return
		if stage=="warmup" and now-phase_us>=WARMUP_US:
			current.warmupActualWallUs=now-phase_us
			current.warmupScope="Renderer-only warmup; measured combat begins at the first live physics tick."
			host.paused=false
			active_us=now;active_sim=float(host.battle.time)
			current.activeStartSim=active_sim
			current.activeStartWorkerSteps=last_worker_steps
			stage="active";frame_ticks=0;frame_sim_us=0;frame_worker_steps=0;frame_polls=0
		elif stage=="active" and (now-active_us>=ACTIVE_US or stopped):
			current.activeWallUs=now-active_us
			current.activeSimSeconds=float(host.battle.time)-active_sim
			current.activeIntervalComplete=now-active_us>=ACTIVE_US and not stopped
			current.intervalEndReason="duration" if not stopped else "battle stopped before the requested active interval completed"
			stage="end";phase_us=now
			host.paused=true
			# End of measurement is above. Freeze the capture, then explicitly join
			# ownership before reading final canonical data or loading another case.
			_retire_worker051()

func _sample_frame(source: String) -> void:
	var now: int=Time.get_ticks_usec()
	var elapsed: int=now-last_draw_us if last_draw_us>0 else 0
	var row: Dictionary={"phase":stage,"source":source,"wallUs":now-started_us,"elapsedUs":elapsed,"physicsTicks":frame_ticks,"simulationTotalUs":frame_sim_us,"lastSimulationUs":host.simulation_us,"chartSubmitUs":host.chart.presentation_us if rendered else null,"chartCounters":_optional(host.chart,"profile_read") if rendered else null,"simTime":host.battle.time,"activeWallMinusSimUs":(now-active_us)-int((float(host.battle.time)-active_sim)*1000000.0) if stage=="active" else null,"physicsInterpolationFraction":_optional(Engine,"get_physics_interpolation_fraction"),"engineProcessSeconds":Performance.get_monitor(Performance.TIME_PROCESS),"rendering":_render_sample(),"state":last_state,"normalRuntimeActive":host.mode=="battle" and host.battle.result==null and not host.result_handled and not host.paused and not host.ui.modal_open}
	row.workerSteps=frame_worker_steps;row.mainPolls=frame_polls
	row.mainPublicationTotalUs=frame_sim_us
	row.simulationUsScope="Legacy frame simulationTotalUs/lastSimulationUs now mean Main polling/publication only. Worker costs are separate completed-step rows."
	row.workerTelemetry=published.duplicate(true)
	if now-last_sample_us>=1000000:
		row.memory=_memory();last_sample_us=now
	if stage=="active" and not hold_probe_issued072 and now-active_us>=1000000 and host.battle.get("result")==null and not host.paused and not host.result_handled and not host.ui.modal_open:
		_issue_hold_probe072()
	row.observerUs=Time.get_ticks_usec()-now
	current.frames.append(row)
	last_draw_us=now;frame_ticks=0;frame_sim_us=0;frame_worker_steps=0;frame_polls=0

func _retire_worker051() -> void:
	if host.battle_driver051==null:return
	var begun: int=Time.get_ticks_usec()
	var driver=host.battle_driver051
	driver.retire()
	var final_events: Array=driver.take_events()
	observe_events051(final_events)
	# Audio gets exactly the same drained batch; all QA audio is muted.
	host.audio.consume(final_events,host.chart)
	published=driver.telemetry()
	_observe_hold_ack072()
	# Let Main publish/reconcile final state and clear its render-pose ownership.
	# Its retirement is idempotent; no state replacement bypasses Main's setter.
	host._retire_battle_driver051()
	if not current.is_empty():
		current.retirement={"wallUs":Time.get_ticks_usec()-started_us,"joinAndDrainUs":Time.get_ticks_usec()-begun,"outsideActiveInterval":true,"telemetry":published.duplicate(true)}

func _capture(label: String) -> void:
	var now: int=Time.get_ticks_usec()
	var image: Image=host.get_viewport().get_texture().get_image()
	var file: String="%s-%s.png"%[current.id,label]
	var error: int=ERR_UNAVAILABLE
	var pixels: Dictionary={"nonblank":false,"reason":"Viewport image unavailable"}
	if image!=null and not image.is_empty() and not FileAccess.file_exists(output.path_join(file)):
		pixels=_nonblank(image)
		error=image.save_png(output.path_join(file))
	current.screenshots.append({"label":label,"file":file,"ok":error==OK,"error":error,"wallUs":now-started_us,"readbackAndWriteUs":Time.get_ticks_usec()-now,"outsideActiveInterval":true,"pixels":pixels,"rendering":_render_sample()})
	if error!=OK:errors.append("Screenshot unavailable: "+file)
	elif not bool(pixels.nonblank):errors.append("Actual viewport PNG is blank: "+file)

func _nonblank(image: Image) -> Dictionary:
	# Bounded read-only sampling of the actual renderer readback, not a replay.
	var colors: Dictionary={};var opaque: int=0;var away: int=0
	var clear: Color=ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color",Color.BLACK)
	for y in range(20):
		for x in range(32):
			var color: Color=image.get_pixel(mini(image.get_width()-1,int((x+0.5)*image.get_width()/32.0)),mini(image.get_height()-1,int((y+0.5)*image.get_height()/20.0)))
			colors[color.to_rgba32()]=true
			if color.a>0.5:opaque+=1
			if absf(color.r-clear.r)+absf(color.g-clear.g)+absf(color.b-clear.b)>0.03:away+=1
	return {"nonblank":colors.size()>=8 and opaque>=512 and away>=7,"width":image.get_width(),"height":image.get_height(),"gridSamples":640,"uniqueRGBA":colors.size(),"opaqueSamples":opaque,"samplesAwayFromClear":away,"scope":"32x20 actual Image pixel samples; requires >=8 colors, >=80% opaque and >=1% away from project clear color. Not an art-quality or motion verdict."}

func _stats(values: Array) -> Dictionary:
	if values.is_empty():return {"count":0,"medianUs":null,"p95Us":null,"maxUs":null,"meanUs":null}
	var sorted: Array=values.duplicate();sorted.sort()
	var total: float=0.0
	for value in sorted:total+=float(value)
	var n: int=sorted.size();var middle: int=n/2
	return {"count":n,"medianUs":float(sorted[middle]) if n%2 else (float(sorted[middle-1])+float(sorted[middle]))/2.0,"p95Us":sorted[ceili(n*0.95)-1],"maxUs":sorted[-1],"meanUs":total/n}

func _end_case() -> void:
	var frame_us: Array=[];var tick_us: Array=[];var job_us: Array=[];var snapshot_us: Array=[];var poll_us: Array=[];var driver_poll_us: Array=[];var lag_us: Array=[];var observer_us: Array=[]
	var completed: int=0;var worker_threads: Dictionary={};var bad_worker_hz: bool=false;var bad_worker_thread: bool=false;var worker_timing_missing: bool=false
	var stutters: int=0;var catchup_frames: int=0;var within20: int=0
	var visible_frames: int=0;var drawn_frames: int=0
	var coverage: Dictionary={"movement":false,"fire":int(current.activeEventKinds.get("fire",0))>0,"hits":int(current.activeEventKinds.get("hit",0))>0,"missiles":false,"flooding":false,"effects":false}
	for frame in current.frames:
		if frame.phase!="active" or int(frame.elapsedUs)<=0 or not bool(frame.normalRuntimeActive):continue
		frame_us.append(int(frame.elapsedUs));observer_us.append(int(frame.observerUs))
		var rendering: Dictionary=frame.rendering
		if bool(rendering.windowVisible):visible_frames+=1
		if int(rendering.canvasObjects)>0 and int(rendering.canvasDrawCalls)>0:drawn_frames+=1
		if int(frame.elapsedUs)>50000:stutters+=1
		if int(frame.elapsedUs)<=20000:within20+=1
		if int(frame.physicsTicks)>1:catchup_frames+=1
	for tick in current.ticks:
		if tick.phase!="active":continue
		completed+=int(tick.completedStepDelta)
		if tick.workerJobUs==null or tick.snapshotUs==null:worker_timing_missing=true
		else:
			job_us.append(int(tick.workerJobUs));snapshot_us.append(int(tick.snapshotUs))
			# Exact whole-job capacity normalized by its REAL completed step count;
			# includes boot/commands/snapshot, never divides by render callbacks.
			tick_us.append(float(tick.workerJobUs)/maxi(1,int(tick.completedStepDelta)))
		observer_us.append(int(tick.observerUs))
		if int(tick.get("workerStepHz",0))!=30:bad_worker_hz=true
		worker_threads[str(tick.get("workerThreadId",0))]=true
		if int(tick.get("workerThreadId",0))<=0 or int(tick.get("workerThreadId",0))==main_thread_id051:bad_worker_thread=true
		for pair in [["movement","moving"],["missiles","missiles"],["flooding","flooding"],["effects","effects"]]:
			if int(tick.state.get(pair[1],0))>0:coverage[pair[0]]=true
	for poll in current.mainPolls:
		if poll.phase!="active":continue
		if poll.mainPublicationUs!=null:poll_us.append(int(poll.mainPublicationUs))
		if poll.mainPollUs!=null:driver_poll_us.append(int(poll.mainPollUs))
		if poll.simulationLagSeconds!=null:lag_us.append(int(float(poll.simulationLagSeconds)*1000000.0))
	var engine_count: int=0
	for tick in current.engineTicks:
		if tick.phase=="active":engine_count+=1
	var frames: Dictionary=_stats(frame_us);var ticks: Dictionary=_stats(tick_us)
	var polls: Dictionary=_stats(poll_us);var lags: Dictionary=_stats(lag_us)
	var total_worker_us: float=0.0
	for value in job_us:total_worker_us+=float(value)
	var throughput_us=null if completed<=0 else total_worker_us/float(completed)
	var pngs_valid: bool=current.screenshots.size()==2 and current.screenshots.all(func(shot):return bool(shot.ok) and bool(shot.pixels.nonblank) and bool(shot.rendering.windowVisible))
	render_verified=rendered and not frame_us.is_empty() and pngs_valid and visible_frames==frame_us.size() and float(drawn_frames)/frame_us.size()>=0.95
	var fps=null if not render_verified else 1000000.0/float(frames.meanUs)
	var ratio: float=float(within20)/maxi(1,frame_us.size())
	var deficit_us: int=int(current.activeWallUs)-int(float(current.activeSimSeconds)*1000000.0)
	var target: Dictionary={"fps60":"unavailable" if fps==null else ("met" if fps>=60.0 else "unmet"),"frames95PercentWithin20ms":"unavailable" if not render_verified else ("met" if ratio>=0.95 else "unmet"),"workerCapacity33_333ms":"unavailable" if tick_us.is_empty() or worker_timing_missing else ("met" if float(ticks.p95Us)<=WORKER_BUDGET_US and float(ticks.meanUs)<=WORKER_BUDGET_US else "unmet"),"mainPublicationP956ms":"unavailable" if poll_us.is_empty() else ("met" if float(polls.p95Us)<=MAIN_PUBLICATION_BUDGET_US else "unmet"),"workerRealtimeLag100ms":"unavailable" if lag_us.is_empty() else ("met" if float(lags.maxUs)<=LAG_BUDGET_US and deficit_us<=LAG_BUDGET_US else "unmet"),"noRecurring50msStutters":"unavailable" if not render_verified else ("met" if stutters<2 else "unmet"),"noRecurringCatchUp":"unavailable" if lag_us.is_empty() else ("met" if float(lags.maxUs)<=LAG_BUDGET_US and deficit_us<=LAG_BUDGET_US else "unmet")}
	if not tick_us.is_empty() and not worker_timing_missing:
		target.workerCapacity33_333ms="met" if float(ticks.p95Us)<=WORKER_BUDGET_US and throughput_us<=WORKER_BUDGET_US else "unmet"
	var missing: Array=[]
	for key in coverage:
		if key=="missiles" and current.id=="light":continue
		if not bool(coverage[key]):missing.append(key)
	if current.id=="mixed":
		for family in ["gun","cannon","rocket","torpedo"]:
			if int(current.activeFireFamilies.get(family,0))==0:missing.append("active "+family+" fire")
	if not bool(current.get("activeIntervalComplete",false)):missing.append("full 12s active interval")
	if bool(current.get("non60HzDtObserved",false)) or engine_count==0:missing.append("actual Engine60Hz callback coverage")
	if bad_worker_hz or completed==0 or not current.workerSequenceErrors.is_empty():missing.append("real completed worker30Hz steps and exact authoritative time progression")
	if worker_timing_missing or poll_us.is_empty() or lag_us.is_empty():missing.append("published worker/job/snapshot/Main/lag telemetry")
	if worker_threads.is_empty() or bad_worker_thread:missing.append("authoritative work on a non-Main worker thread")
	if not current.duplicateEventSeqs.is_empty():missing.append("single-drain ordered events")
	if not render_verified:missing.append("verified visible viewport rendering, object/draw counters and two nonblank PNGs")
	current.summary={"cohort":_limits().cohort,"frames":frames,"physicsTicks":ticks,"physicsTicksScope":"Historical raw field now contains worker whole-job samples; count is completed jobs, never Main callbacks. Frozen prior reports are unchanged.","engineCallbacks":engine_count,"engineCallbackHz":float(engine_count)*1000000.0/maxi(1,int(current.activeWallUs)),"workerCompletedSteps":completed,"workerCompletedHz":float(completed)*1000000.0/maxi(1,int(current.activeWallUs)),"workerThreads":worker_threads.keys(),"workerJobs":ticks,"workerSnapshots":_stats(snapshot_us),"mainPublication":polls,"simulationLag":lags,"historicalMainSimulationCriterion":"median6ms/P9510ms at60Hz; not evaluated for this new cohort","observer":_stats(observer_us),"renderingVerified":render_verified,"visibleActiveFrames":visible_frames,"positiveObjectAndDrawFrames":drawn_frames,"nonblankPNGs":pngs_valid,"renderedFPS":fps,"fractionFramesWithin20ms":ratio if render_verified else null,"framesAbove50ms":stutters,"framesWithMultiplePhysicsTicks":catchup_frames,"wallMinusSimUs":deficit_us,"engineAccumulatorUs":null,"coverage":coverage,"missingActiveCoverage":missing,"targets":target,"targetNote":"Worker30Hz is intentional owner policy. Job capacity includes snapshot cost; publication has a separate6ms P95 budget and100ms lag cap. Engine callbacks/draw remain raw diagnostics, not worker steps. Render60/95%20ms/no recurring50ms stutter retained. Unmet targets are measured misses; missing coverage never accepts idle FPS.","exportedRenderedEvidence":render_verified and _exported_release() and missing.is_empty() and errors.is_empty()}
	current.summary.workerJobs=_stats(job_us)
	current.summary.workerCapacityPerCompletedStep=ticks
	current.summary.workerThroughputUsPerCompletedStep=throughput_us
	current.summary.workerCapacityScope="P95 of whole-job/actual-step-count plus total-job-cost/total-completed-steps. Individual steps inside a batch are not separately timed. Real-time lag is an independent gate."
	current.summary.driverPolling=_stats(driver_poll_us)
	current.summary.physicsTicks=_stats([])
	current.summary.physicsTicks.count=engine_count
	current.summary.physicsTicksScope="Actual Engine60Hz callbacks, timing unavailable because battle work moved to render-polled worker ownership. Historical60Hz timing reports preserved. See workerJobs/capacity and mainPublication separately."
	current.endState=_state_sample();current.endMemory=_memory()
	# Preserve the existing bounded developer trace once, AFTER measurement.
	# This explains fleet stalls without new per-tick sampling or a second harness.
	current.endTacticalTrace051=host.battle.get("tactical",{}).get("trace",[]).duplicate(true)
	current.endVeto051=published.get("veto051")
	current.endBoatMotion051=[]
	current.plannerDeadlocks051=[]
	var final_tactical051: Dictionary=host.battle.get("tactical",{})
	for ship: Dictionary in host.battle.ships:
		current.endBoatMotion051.append({"id":str(ship.id),"x":float(ship.x),"y":float(ship.y),"vx":float(ship.vx),"vy":float(ship.vy),"angle":float(ship.angle)})
		var id051: String=str(ship.id)
		# The published mirror has no task/goal handles. Track the same observable
		# unresolved + motionless interval on completed steps, before retirement
		# clears goals, rather than probing any worker's mutable slot dictionary.
		var pending_age051: float=last_worker_time-float(idle_since051.get(id051,last_worker_time))
		if idle_since051.has(id051) and pending_age051>=3.0:
			current.plannerDeadlocks051.append({"id":id051,"pendingSeconds":pending_age051,"reason":str(final_tactical051.get("reasons",{}).get(id051,""))})
	# An idle, unresolved fleet is not a valid route to a higher frame rate.
	current.summary.targets.noPersistentPlannerDeadlocks="met" if current.plannerDeadlocks051.is_empty() else "unmet"
	current.counterTotals={"damage":published.get("damageCounters"),"tactical":published.get("tacticalCounters"),"chart":_optional(host.chart,"profile_read"),"workerFineScope":"Unavailable shared global sinks remain null; only published counters are eligible."}
	_finalize_hold_probe072()
	current.summary.orderProbe072=current.orderProbe072.duplicate(true)
	current.complete=bool(current.get("activeIntervalComplete",false))
	_write_json("runtime043-%s.json"%current.id,current)
	results.append({"id":current.id,"complete":current.complete,"file":"runtime043-%s.json"%current.id,"actual":current.actual,"summary":current.summary})
	stage="between";_start_case.call_deferred()

func _living_player_id072() -> String:
	var preferred: String=str(host.battle.get("playerId",""))
	var fallback: String=""
	for ship in host.battle.get("ships",[]):
		if str(ship.get("team",""))!="player" or bool(ship.get("sunk",false)) or bool(ship.get("captureSecured",false)):continue
		var id: String=str(ship.get("id",""))
		if id.is_empty():continue
		if id==preferred:return id
		if fallback.is_empty():fallback=id
	return fallback

func _issue_hold_probe072() -> void:
	# One ordinary public order through the published mirror. The driver queues it;
	# this does not write worker state, clocks, weapons, actors or time scale.
	hold_probe_issued072=true
	var probe: Dictionary={"once":true,"order":"hold","afterActiveUs":1000000,"shipId":"","queued":false,"queueMonotonicUs":null,"observedMonotonicUs":null,"priorLastCommandSequence":null,"acknowledgement":null,"queueToJoinedObservationUs":null,"workload":"One real Hold is part of this active case. Not an isolated comparison to historical063."}
	current.orderProbe072=probe
	if host.battle_driver051==null or not bool(host.battle.get("_battleMirror051",false)):
		probe.reason="Main mirror/driver was not attached. No order was issued. queueToJoinedObservationUs is unavailable."
		return
	var ship_id: String=_living_player_id072()
	probe.shipId=ship_id
	if ship_id.is_empty():
		probe.reason="No living player boat was on the published mirror. No order was issued. queueToJoinedObservationUs is unavailable."
		return
	var prior: Dictionary=host.battle_driver051.telemetry()
	hold_probe_seq_floor072=int(prior.get("lastCommandSequence",0))
	probe.priorLastCommandSequence=hold_probe_seq_floor072
	var queued_at: int=Time.get_ticks_usec()
	var queued: bool=Battle.issue_order(host.battle,[ship_id],"hold",{})
	probe.queued=queued
	if not queued:
		probe.reason="Battle.issue_order did not queue Hold. queueToJoinedObservationUs is unavailable."
		return
	probe.queueMonotonicUs=queued_at
	probe.reason="Queued. Waiting for commandResults sequence priorLastCommandSequence+1 and kind order."

func _observe_hold_ack072() -> void:
	if current.is_empty() or not bool(current.get("orderProbe072",{}).get("queued",false)):return
	var probe: Dictionary=current.orderProbe072
	if probe.acknowledgement!=null:return
	var results=published.get("commandResults",[])
	if not results is Array:return
	# The probe is the only runtime command, so its joined row is the next sequence.
	var expected: int=hold_probe_seq_floor072+1
	for receipt in results:
		if not receipt is Dictionary or not receipt.has("sequence") or not receipt.has("kind"):continue
		if int(receipt.sequence)!=expected or str(receipt.kind)!="order":continue
		var observed_at: int=Time.get_ticks_usec()
		probe.observedMonotonicUs=observed_at
		probe.acknowledgement={"sequence":int(receipt.sequence),"kind":str(receipt.kind),"ok":receipt.get("ok") if receipt.has("ok") else null}
		probe.joinedOutsideActiveInterval=stage!="active"
		var queued_at=probe.get("queueMonotonicUs")
		if queued_at==null:
			probe.queueToJoinedObservationUs=null
			probe.reason="Exact order acknowledgement was observed, but queueMonotonicUs is missing. queueToJoinedObservationUs is unavailable."
			return
		# Main monotonic queue-to-observation span. Scheduling and poll delay are included.
		# This is not worker execution time and not workerJobUs.
		probe.queueToJoinedObservationUs=observed_at-int(queued_at)
		probe.reason="queueToJoinedObservationUs is observedMonotonicUs minus queueMonotonicUs on Main's existing clock. It includes scheduling and poll delay. It is not internal execution time or workerJobUs."
		return

func _finalize_hold_probe072() -> void:
	if current.is_empty():return
	if not current.has("orderProbe072"):
		current.orderProbe072={"once":true,"order":"hold","queued":false,"queueMonotonicUs":null,"observedMonotonicUs":null,"acknowledgement":null,"queueToJoinedObservationUs":null,"reason":"Hold probe was not issued. queueToJoinedObservationUs is unavailable."}
		return
	var probe: Dictionary=current.orderProbe072
	if bool(probe.get("queued",false)) and probe.get("acknowledgement")==null:
		probe.observedMonotonicUs=null
		probe.queueToJoinedObservationUs=null
		probe.reason="No joined command acknowledgement with sequence priorLastCommandSequence+1 and kind order. queueToJoinedObservationUs is unavailable."

func _write_json(name: String,value) -> bool:
	var path: String=output.path_join(name)
	if FileAccess.file_exists(path):
		errors.append("Refused to overwrite artifact "+name)
		return false
	var file=FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		errors.append("Cannot write artifact "+name)
		return false
	file.store_string(JSON.stringify(value));file.close()
	return true

func _abort(reason: String) -> void:
	if stage=="done":return
	errors.append(reason)
	if not current.is_empty():
		_finalize_hold_probe072()
		current.incompleteReason=reason
		_write_json("runtime043-%s-incomplete.json"%current.id,current)
	_finish()

func _finish() -> void:
	_retire_worker051()
	stage="done"
	if RenderingServer.frame_post_draw.is_connected(_after_draw):RenderingServer.frame_post_draw.disconnect(_after_draw)
	if host.get_tree().physics_frame.is_connected(_engine_callback051):host.get_tree().physics_frame.disconnect(_engine_callback051)
	_counters(false)
	render_verified=not results.is_empty() and results.all(func(value):return bool(value.summary.renderingVerified))
	var complete: bool=results.size()==requested.size() and results.all(func(value):return bool(value.complete)) and errors.is_empty()
	var saved: bool=_write_json("runtime043-report.json",{"schema":2,"complete":complete,"errors":errors,"readyToFinishWallUs":Time.get_ticks_usec()-started_us,"hardware":_hardware(),"counterMode":_counter_metadata(),"limits":_limits(),"requested":requested,"cases":results})
	complete=complete and saved
	print("RUNTIME043_ARTIFACTS ",output," complete=",complete," rendered=",render_verified)
	host.get_tree().quit(0 if complete else 3)
