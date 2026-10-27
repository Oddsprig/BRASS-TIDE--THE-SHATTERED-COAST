extends RefCounted
## Explicit, source-candidate observer of the real Main/Lab/Chart runtime.
## Root supplies the exported binary, private desktop, synthetic APPDATA and lane.
const Lab=preload("res://scripts/fleet_lab.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Damage=preload("res://scripts/damage.gd")
const Tactical=preload("res://scripts/tactical_runtime.gd")
const Preferences=preload("res://scripts/preferences.gd")
const WARMUP_US: int=3000000
const ACTIVE_US: int=12000000
const WALL_LIMIT_US: int=68000000 # One 70s external bound; reserve 2s for final cleanup.
const EVENT_LIMIT: int=20000
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

func prepare(game_host) -> bool:
	host=game_host
	started_us=Time.get_ticks_usec()
	var root: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if root.is_empty() or not root.is_absolute_path():
		push_error("--qa-runtime043 requires an absolute GAME_TEST_ARTIFACTS directory.")
		return false
	if "--fixed-fps" in OS.get_cmdline_args() or Engine.physics_ticks_per_second!=60 or not is_equal_approx(Engine.time_scale,1.0):
		push_error("Runtime043 requires the unchanged real-time 60Hz runtime.")
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
	_optional(host.chart,"profile_enable",[enabled])
	Damage.set_runtime_profile043(enabled)
	Tactical.set_runtime_profile043(enabled)
	if reset:
		Damage.reset_runtime_profile043()
		Tactical.reset_runtime_profile043()
	if reset:_optional(host.chart,"profile_reset")

func start() -> void:
	if stage!="boot":return
	_write_json("runtime043-start.json",{"schema":1,"readyToStartWallUs":Time.get_ticks_usec()-started_us,"hardware":_hardware(),"cases":requested,"limits":_limits()})
	if not rendered:
		_abort("Headless/dummy rendering unavailable; no rendered FPS evidence or verdict.")
		return
	RenderingServer.frame_post_draw.connect(_after_draw)
	_start_case()

func _hardware() -> Dictionary:
	# Damage/Tactical counters are compiled static APIs in Root's instrumented baseline.
	return {"engine":Engine.get_version_info(),"os":OS.get_name(),"cpu":OS.get_processor_name(),"logicalCPUs":OS.get_processor_count(),"pid":OS.get_process_id(),"editor":OS.has_feature("editor"),"template":OS.has_feature("template"),"release":OS.has_feature("release"),"debugBuild":OS.is_debug_build(),"exported":_exported_release(),"templateRelease":_exported_release(),"displayServer":DisplayServer.get_name(),"rendererCandidate":rendered,"renderedAvailable":rendered and render_verified,"windowVisible":host.get_window().visible,"adapter":RenderingServer.get_video_adapter_name(),"adapterVendor":_optional(RenderingServer,"get_video_adapter_vendor"),"apiVersion":_optional(RenderingServer,"get_video_adapter_api_version"),"renderingMethod":_optional(RenderingServer,"get_current_rendering_method"),"renderingDriver":_optional(RenderingServer,"get_current_rendering_driver_name"),"windowPixels":[host.get_tree().root.size.x,host.get_tree().root.size.y],"viewportRect":_viewport_size(),"threadModel":ProjectSettings.get_setting("rendering/driver/threads/thread_model"),"physicsHz":Engine.physics_ticks_per_second,"maxPhysicsStepsPerFrame":Engine.max_physics_steps_per_frame,"timeScale":Engine.time_scale,"frameCap":Engine.max_fps,"processPriority":null,"resourceEnvelope":"Record actual priority/affinity/job CPU and memory limits in Root's external owned-process wrapper.","memory":_memory(),"counterAPIs":{"chart":host.chart.has_method("profile_read"),"damage":true,"tactical":true}}

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
	return {"warmupWallUs":WARMUP_US,"activeWallUs":ACTIVE_US,"cooperativeReadyToFinishUs":WALL_LIMIT_US,"wrapperGlobalLimitUs":70000000,"physics":"Existing Main._physics_process only; no extra updates, skipped actors, altered clocks or thread changes.","frames":"Consecutive frame_post_draw wall intervals, including only complete active intervals; Chart.presentation_us is CPU draw submission, not GPU duration or display scanout. Headless/dummy is rejected without awaiting a draw.","catchUp":"Observed physics calls per draw and wall-minus-sim elapsed deficit; engine internal accumulator/dropped-time counter unavailable. Multiple ticks per draw alone can be normal below 60 render FPS.","observer":"In-memory frame/tick/event rows; observer cost and screenshot/readback/file stalls reported. No image/file writes inside the active interval.","safety":"Root owns TestBridge, private desktop, isolated APPDATA, 70s external global deadline including both case loads/PNGs and cleanup, actual resource envelope and GPU authorization. Probe's 68s cooperative clock includes case loads/writes but cannot interrupt a blocked renderer/readback/filesystem call. Probe has no focus/input/window-control API.","sourceStatus":"Profiling source candidate; no release/version advancement or quality acceptance implied."}

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
	host.start_lab()
	if host.mode!="battle" or not host.lab_active or host.battle.is_empty():
		_abort("Public Main.start_lab did not enter a real Lab battle.")
		return
	# Warm the renderer before combat, so opening missile salvos are measured.
	# This isolated Lab pause ends before the first measured physics tick.
	host.paused=true
	current={"id":id,"seed":host.lab_seed,"config":config,"inspected":checked,"loadUs":Time.get_ticks_usec()-load_started,"createdAtUs":load_started-started_us,"frames":[],"ticks":[],"events":[],"eventKinds":{},"eventFamilies":{},"activeEventKinds":{},"activeFireFamilies":{},"eventsOmitted":0,"screenshots":[],"complete":false}
	var roster: Array=[]
	positions.clear();moved.clear();distance_m=0.0
	# Bounded fixture formation only: three columns, seven possible rows, in the
	# unchanged default islands' open central corridor. AI/physics choose all motion.
	var counts: Dictionary={"player":0,"enemy":0}
	var teams: Dictionary={"player":[],"enemy":[]}
	for ship in host.battle.ships:
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
	current.actual={"actors":host.battle.ships.size(),"playerActors":counts.player,"enemyActors":counts.enemy,"playerDP":Deployment.total(teams.player),"enemyDP":Deployment.total(teams.enemy),"deployment":host.battle.deployment.duplicate(true),"reservePlayer":host.battle.reserves.player.size(),"reserveEnemy":host.battle.reserves.enemy.size()}
	if int(current.actual.playerDP)!=300 or int(current.actual.enemyDP)!=300 or int(current.actual.reservePlayer)!=0 or int(current.actual.reserveEnemy)!=0 or (id=="light" and int(current.actual.actors)!=42):
		_abort("Actual deployment does not match the requested stock 300-vs-300 actors.")
		return
	host.chart.follow_camera=false;host.chart.camera=Vector2(1145,838)
	current.camera={"x":1145,"y":838,"zoom":host.chart.zoom,"follow":false,"note":"Declared fixed normal battle camera; no tactical overview or window manipulation."}
	current.islands=host.battle.islands.duplicate(true)
	current.initialMemory=_memory()
	current.initialState=_state_sample()
	last_state=current.initialState
	current.counterScope="Cumulative since case start, warmup included. Per-tick/per-frame differences attribute work; counters never clear live caches."
	_counters(true,true)
	frame_ticks=0;frame_sim_us=0;last_draw_us=0;last_sample_us=0
	stage="opening";phase_us=Time.get_ticks_usec()

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
	if stage not in ["opening","warmup","active"] or current.is_empty():return
	var observed: int=Time.get_ticks_usec()
	var st: Dictionary=host.battle
	var metrics: Dictionary=st.get("tactical",{}).get("metrics",{})
	var row: Dictionary={"phase":stage,"wallUs":observed-started_us,"simTime":st.time,"dt":dt,"simulationUs":host.simulation_us,"aiUs":metrics.get("aiUs"),"phaseUs":metrics.get("phaseUs",{}).duplicate(true),"planningDetailUs":metrics.get("planningDetailUs",{}).duplicate(true),"work":metrics.get("work",{}).duplicate(true),"damageCounters":Damage.runtime_profile043(),"tacticalCounters":Tactical.runtime_profile043()}
	if not is_equal_approx(dt,1.0/60.0):current["non60HzDtObserved"]=true
	frame_ticks+=1;frame_sim_us+=int(host.simulation_us)
	last_state=_state_sample()
	row.state=last_state
	for event in st.events:
		var kind: String=str(event.kind);var family: String=str(event.family)
		current.eventKinds[kind]=int(current.eventKinds.get(kind,0))+1
		current.eventFamilies[family]=int(current.eventFamilies.get(family,0))+1
		if stage=="active":
			current.activeEventKinds[kind]=int(current.activeEventKinds.get(kind,0))+1
			if kind=="fire":current.activeFireFamilies[family]=int(current.activeFireFamilies.get(family,0))+1
		if current.events.size()<EVENT_LIMIT:
			current.events.append({"phase":stage,"wallUs":observed-started_us,"time":event.time,"seq":event.seq,"kind":kind,"family":family,"projectileKind":event.projectileKind,"source":event.sourceId,"target":event.targetId,"damage":event.damage,"breach":event.breach,"x":event.x,"y":event.y})
		else:current.eventsOmitted+=1
	row.observerUs=Time.get_ticks_usec()-observed
	current.ticks.append(row)

func _state_sample() -> Dictionary:
	var value: Dictionary={"actors":host.battle.ships.size(),"autopilot":host.battle.autopilot,"livePlayer":0,"liveEnemy":0,"moving":0,"flooding":0,"waterLitres":0.0,"fire":0.0,"projectiles":host.battle.projectiles.size(),"missiles":0,"effects":host.battle.effects.size(),"droppedEvents":int(host.battle.get("droppedEvents",0)),"ammo":0.0,"fuel":0.0,"supplies":0.0,"hp":0.0,"result":host.battle.result}
	for ship in host.battle.ships:
		var id: String=str(ship.id);var at: Vector2=Vector2(ship.x,ship.y)
		distance_m+=at.distance_to(positions.get(id,at));positions[id]=at
		if Vector2(ship.vx,ship.vy).length()>0.1:value.moving+=1;moved[id]=true
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
			stage="active";frame_ticks=0;frame_sim_us=0
		elif stage=="active" and (now-active_us>=ACTIVE_US or stopped):
			current.activeWallUs=now-active_us
			current.activeSimSeconds=float(host.battle.time)-active_sim
			current.activeIntervalComplete=now-active_us>=ACTIVE_US and not stopped
			current.intervalEndReason="duration" if not stopped else "battle stopped before the requested active interval completed"
			stage="end";phase_us=now
			_capture("end")
			_end_case()

func _sample_frame(source: String) -> void:
	var now: int=Time.get_ticks_usec()
	var elapsed: int=now-last_draw_us if last_draw_us>0 else 0
	var row: Dictionary={"phase":stage,"source":source,"wallUs":now-started_us,"elapsedUs":elapsed,"physicsTicks":frame_ticks,"simulationTotalUs":frame_sim_us,"lastSimulationUs":host.simulation_us,"chartSubmitUs":host.chart.presentation_us if rendered else null,"chartCounters":_optional(host.chart,"profile_read") if rendered else null,"simTime":host.battle.time,"activeWallMinusSimUs":(now-active_us)-int((float(host.battle.time)-active_sim)*1000000.0) if stage=="active" else null,"physicsInterpolationFraction":_optional(Engine,"get_physics_interpolation_fraction"),"engineProcessSeconds":Performance.get_monitor(Performance.TIME_PROCESS),"rendering":_render_sample(),"state":last_state,"normalRuntimeActive":host.mode=="battle" and host.battle.result==null and not host.result_handled and not host.paused and not host.ui.modal_open}
	if now-last_sample_us>=1000000:
		row.memory=_memory();last_sample_us=now
	row.observerUs=Time.get_ticks_usec()-now
	current.frames.append(row)
	last_draw_us=now;frame_ticks=0;frame_sim_us=0

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
	var frame_us: Array=[];var tick_us: Array=[];var observer_us: Array=[]
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
		tick_us.append(int(tick.simulationUs));observer_us.append(int(tick.observerUs))
		for pair in [["movement","moving"],["missiles","missiles"],["flooding","flooding"],["effects","effects"]]:
			if int(tick.state.get(pair[1],0))>0:coverage[pair[0]]=true
	var frames: Dictionary=_stats(frame_us);var ticks: Dictionary=_stats(tick_us)
	var pngs_valid: bool=current.screenshots.size()==2 and current.screenshots.all(func(shot):return bool(shot.ok) and bool(shot.pixels.nonblank) and bool(shot.rendering.windowVisible))
	render_verified=rendered and not frame_us.is_empty() and pngs_valid and visible_frames==frame_us.size() and float(drawn_frames)/frame_us.size()>=0.95
	var fps=null if not render_verified else 1000000.0/float(frames.meanUs)
	var ratio: float=float(within20)/maxi(1,frame_us.size())
	var deficit_us: int=int(current.activeWallUs)-int(float(current.activeSimSeconds)*1000000.0)
	var target: Dictionary={"fps60":"unavailable" if fps==null else ("met" if fps>=60.0 else "unmet"),"frames95PercentWithin20ms":"unavailable" if not render_verified else ("met" if ratio>=0.95 else "unmet"),"simulationMedian6msP9510ms":"unavailable" if tick_us.is_empty() else ("met" if float(ticks.medianUs)<=6000 and float(ticks.p95Us)<=10000 else "unmet"),"noRecurring50msStutters":"unavailable" if not render_verified else ("met" if stutters<2 else "unmet"),"noRecurringCatchUp":"unavailable" if not render_verified else ("unmet" if catchup_frames>=2 or deficit_us>100000 else "met")}
	var missing: Array=[]
	for key in coverage:
		if key=="missiles" and current.id=="light":continue
		if not bool(coverage[key]):missing.append(key)
	if current.id=="mixed":
		for family in ["gun","cannon","rocket","torpedo"]:
			if int(current.activeFireFamilies.get(family,0))==0:missing.append("active "+family+" fire")
	if not bool(current.get("activeIntervalComplete",false)):missing.append("full 12s active interval")
	if bool(current.get("non60HzDtObserved",false)):missing.append("unchanged 60Hz physics dt")
	if not render_verified:missing.append("verified visible viewport rendering, object/draw counters and two nonblank PNGs")
	current.summary={"frames":frames,"physicsTicks":ticks,"observer":_stats(observer_us),"renderingVerified":render_verified,"visibleActiveFrames":visible_frames,"positiveObjectAndDrawFrames":drawn_frames,"nonblankPNGs":pngs_valid,"renderedFPS":fps,"fractionFramesWithin20ms":ratio if render_verified else null,"framesAbove50ms":stutters,"framesWithMultiplePhysicsTicks":catchup_frames,"wallMinusSimUs":deficit_us,"engineAccumulatorUs":null,"coverage":coverage,"missingActiveCoverage":missing,"targets":target,"targetNote":"Unmet targets are measured performance misses, never fabricated logic-test failures. Coverage and full duration must be complete before this can support active-runtime acceptance. Recurring means at least two occurrences; catch-up also misses if final wall-minus-sim deficit exceeds 100ms.","exportedRenderedEvidence":render_verified and _exported_release() and missing.is_empty() and errors.is_empty()}
	current.endState=_state_sample();current.endMemory=_memory()
	# Preserve the existing bounded developer trace once, AFTER measurement.
	# This explains fleet stalls without new per-tick sampling or a second harness.
	current.endTacticalTrace051=host.battle.get("tactical",{}).get("trace",[]).duplicate(true)
	current.endBoatMotion051=[]
	current.plannerDeadlocks051=[]
	var final_tactical051: Dictionary=host.battle.tactical
	for ship: Dictionary in host.battle.ships:
		current.endBoatMotion051.append({"id":str(ship.id),"x":float(ship.x),"y":float(ship.y),"vx":float(ship.vx),"vy":float(ship.vy),"angle":float(ship.angle)})
		var id051: String=str(ship.id)
		var pending_age051: float=float(host.battle.time)-float(final_tactical051.pending.get(id051,host.battle.time))
		if not ship.sunk and not ship.get("captureSecured",false) and not final_tactical051.intents.has(id051) and Vector2(ship.vx,ship.vy).length_squared()<0.01 and pending_age051>=3.0:
			current.plannerDeadlocks051.append({"id":id051,"pendingSeconds":pending_age051,"reason":str(final_tactical051.reasons.get(id051,""))})
	# An idle, unresolved fleet is not a valid route to a higher frame rate.
	current.summary.targets.noPersistentPlannerDeadlocks="met" if current.plannerDeadlocks051.is_empty() else "unmet"
	current.counterTotals={"damage":Damage.runtime_profile043(),"tactical":Tactical.runtime_profile043(),"chart":_optional(host.chart,"profile_read")}
	current.complete=bool(current.get("activeIntervalComplete",false))
	_write_json("runtime043-%s.json"%current.id,current)
	results.append({"id":current.id,"complete":current.complete,"file":"runtime043-%s.json"%current.id,"actual":current.actual,"summary":current.summary})
	stage="between";_start_case.call_deferred()

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
		current.incompleteReason=reason
		_write_json("runtime043-%s-incomplete.json"%current.id,current)
	_finish()

func _finish() -> void:
	stage="done"
	if RenderingServer.frame_post_draw.is_connected(_after_draw):RenderingServer.frame_post_draw.disconnect(_after_draw)
	_counters(false)
	render_verified=not results.is_empty() and results.all(func(value):return bool(value.summary.renderingVerified))
	var complete: bool=results.size()==requested.size() and results.all(func(value):return bool(value.complete)) and errors.is_empty()
	var saved: bool=_write_json("runtime043-report.json",{"schema":1,"complete":complete,"errors":errors,"readyToFinishWallUs":Time.get_ticks_usec()-started_us,"hardware":_hardware(),"limits":_limits(),"requested":requested,"cases":results})
	complete=complete and saved
	print("RUNTIME043_ARTIFACTS ",output," complete=",complete," rendered=",render_verified)
	host.get_tree().quit(0 if complete else 3)
