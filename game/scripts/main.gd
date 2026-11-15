extends Node2D

const DamageReference051 = preload("res://scripts/damage.gd")
const Battle = preload("res://scripts/battle.gd")
const BattleDriver051 = preload("res://scripts/battle_driver051.gd")
const Tactical = preload("res://scripts/tactical_runtime.gd")
const Economy = preload("res://scripts/economy.gd")
const Version = preload("res://scripts/version.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Chart = preload("res://scripts/chart.gd")
const Interface = preload("res://scripts/interface.gd")
const Refit = preload("res://scripts/refit.gd")
const Deployment = preload("res://scripts/deployment.gd")
const Sound = preload("res://scripts/sound.gd")
const FleetLab = preload("res://scripts/fleet_lab.gd")
const LabUI = preload("res://scripts/lab_ui.gd")
const DevTools = preload("res://scripts/dev_tools.gd")
const Music = preload("res://scripts/music.gd")
const Preferences=preload("res://scripts/preferences.gd")
const EconomyWorkers=preload("res://scripts/economy_workers.gd")
const RecoveryFlow=preload("res://scripts/recovery_flow.gd")
const CoastalTerrain=preload("res://scripts/coastal_terrain.gd")
const RuntimeBenchmark=preload("res://scripts/runtime_benchmark.gd")
const RuntimeProfile043=preload("res://scripts/runtime_profile043.gd")
const BattleCommands047=preload("res://scripts/battle_commands047.gd")
const WorkshopBuilds060=preload("res://scripts/workshop_builds048.gd")
const ShippingUI068=preload("res://scripts/shipping_ui068.gd")
const FirstVoyage120=preload("res://scripts/first_voyage120.gd")
const Guidance120=preload("res://scripts/campaign_guidance.gd")
const GuidanceUI120=preload("res://scripts/guidance_ui.gd")
const CareerCosts120=preload("res://scripts/career_costs.gd")

class _DamageView051 extends RefCounted:
	var owner: WeakRef
	func _init(main):owner=weakref(main)
	func _published(ship: Dictionary) -> Dictionary:
		var main=owner.get_ref()
		if main==null or main.battle_driver051==null:return {}
		for boat: Dictionary in main.battle.get("ships",[]):
			if str(boat.get("id",""))==str(ship.get("id","")) or (not str(ship.get("uid","")).is_empty() and str(boat.get("uid",""))==str(ship.uid)):
				return boat
		return {}
	func get_status(ship: Dictionary) -> Dictionary:
		return get_status_cached(ship)
	func get_status_cached(ship: Dictionary,cache=null) -> Dictionary:
		var boat: Dictionary=_published(ship)
		if not boat.is_empty():
			var main=owner.get_ref()
			return main.battle.get("tactical",{}).get("damageStatusById051",{}).get(str(boat.id),{}).duplicate(true)
		return DamageReference051.get_status_cached(ship,cache)
	func set_policy(ship: Dictionary,policy: String) -> String:
		var boat: Dictionary=_published(ship)
		if not boat.is_empty():
			var main=owner.get_ref()
			return policy if main.Battle.set_crew_policy(main.battle,[str(boat.id)],policy) else str(boat.get("policy","balanced"))
		return DamageReference051.set_policy(ship,policy)
	func apply_hit(ship: Dictionary,hit: Dictionary,rng: RandomNumberGenerator=null,cache=null) -> Array:
		# Synchronous test fixtures retain their old API; active player commands
		# never manufacture damage or mutate the published display dictionary.
		if not _published(ship).is_empty():return []
		return DamageReference051.apply_hit(ship,hit,rng,cache)

# Existing host.Damage UI callers get published data during worker ownership.
# Raw component scripts still preload damage.gd and keep their synchronous APIs.
var Damage=_DamageView051.new(self)

var data: Dictionary
var core
var chart
var ui
var audio
var music
var mode = "menu"
var paused = false
var speed = 1
var selected_port = "brass_haven"
var selected_site: String=""
var battle: Dictionary = {}:
	set(value):
		if not _publishing_battle051:
			_retire_battle_driver051()
			Tactical.retire_planning051(battle)
		battle = value
var battle_driver051=null
var battle_publication_us051: int=0
var _publishing_battle051: bool=false
var _battle_ports051: Dictionary={}
var _battle_ack_sequence051: int=0
var battle_context: Dictionary = {}
var battle_report: Dictionary = {}
var battle_enemies: Array = []
var quick_mode = false
var fire_held = false
var auto_gunners = true
var tactical_mode = false
var pre_tactical_paused = false
var pre_tactical_autopilot = true
var battle_selection_groups: Dictionary={1:[],2:[],3:[],4:[]}
var selected_battle_ids: Array = []
var battle_command_pending: String = ""
var battle_command_ack: Dictionary = {}
var selection_start = Vector2.ZERO
var selection_box = Rect2()
var selection_dragging = false
var result_handled = false
var salvage_claimed = false
var hud_timer = 0.0
var save_timer = 0.0
var economy_task: int = -1
var economy_job: Dictionary = {}
var economy_workers=EconomyWorkers.new()
var save_directory = ""
var battle_last_wrecks = 0
var screenshots_requested: Array = []
var lab_active=false
var lab_config: Dictionary={}
var lab_seed: int=83
var career_core=null
var dev_enabled=false
var dev_tools
var simulation_us: int=0
var preferences_path=""
var runtime_profile043=null
var qa_ocean066: bool=false
var first_voyage120=FirstVoyage120.new()
var _campaign_motion120: float=0.0
var _engine_load120: float=0.0

func _ready():
	if qa_ocean066 and not OS.get_environment("GAME_TEST_ARTIFACTS").is_absolute_path():
		push_error("Ocean066 fixture requires an isolated GAME_TEST_ARTIFACTS directory.");get_tree().quit(2);return
	if "--qa-runtime043" in OS.get_cmdline_user_args():
		runtime_profile043=RuntimeProfile043.new()
		if not runtime_profile043.prepare(self):
			get_tree().quit(2)
			return
		preferences_path=runtime_profile043.preferences_path
	else:
		preferences_path=ProjectSettings.globalize_path("res://../settings.json") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("settings.json")
		if DisplayServer.get_name()=="headless":preferences_path=OS.get_user_data_dir().path_join("qa-settings.json")
	var options: Dictionary=Preferences.defaults() if qa_ocean066 else (Preferences.load_options(preferences_path) if runtime_profile043==null else runtime_profile043.options())
	if qa_ocean066:
		options=Preferences.defaults();options.audio_enabled=false;options.music_enabled=false;options.fullscreen=false
		preferences_path=OS.get_environment("GAME_TEST_ARTIFACTS").path_join("ocean066-profile/settings.json")
	Engine.max_fps = options.frame_cap
	dev_enabled=options.dev_enabled
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	if data.is_empty():
		push_error("World data missing.")
		get_tree().quit(1)
		return
	if "--qa-performance" in OS.get_cmdline_user_args():
		print("QA synchronous 60Hz component reference; not the worker30Hz/rendered acceptance cohort.")
		get_tree().quit(RuntimeBenchmark.new().run(data))
		return
	core = Campaign.new(data)
	chart = Chart.new()
	add_child(chart)
	chart.setup(self)
	audio = Sound.new()
	audio.enabled=options.audio_enabled;audio.weapon_volume=options.weapon_volume;audio.ambience_volume=options.ambience_volume
	add_child(audio)
	music=Music.new()
	if qa_ocean066:music.include_desktop=false
	music.enabled=options.music_enabled;music.volume=options.music_volume
	if runtime_profile043!=null:music.include_desktop=false
	add_child(music)
	ui = Interface.new()
	add_child(ui)
	ui.setup(self)
	dev_tools=DevTools.new()
	add_child(dev_tools)
	dev_tools.setup(self)
	save_directory = ProjectSettings.globalize_path("res://saves") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("saves")
	if runtime_profile043!=null:save_directory=runtime_profile043.save_directory
	if qa_ocean066:save_directory=OS.get_environment("GAME_TEST_ARTIFACTS").path_join("ocean066-profile/saves")
	ui.title_screen()
	get_viewport().size_changed.connect(_resize_interface)
	print("BRASS TIDE v", Version.text(), " | ", OS.get_processor_name(), " | ", OS.get_processor_count(), " logical threads | ", RenderingServer.get_video_adapter_name())
	if runtime_profile043!=null:
		runtime_profile043.start.call_deferred()
		return
	# Development hooks are explicit launch arguments; retail controls do not expose them.
	var args = OS.get_cmdline_user_args()
	dev_enabled=dev_enabled or "--dev" in args
	if options.fullscreen and DisplayServer.get_name()!="headless":DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if "--qa-campaign" in args:
		new_game()
	if "--qa-battle" in args:
		quick_battle()
	for argument in args:
		if str(argument).begins_with("--qa-lab="):
			var preset: String=str(argument).trim_prefix("--qa-lab=")
			if preset == "attachment060" and OS.get_environment("GAME_TEST_ARTIFACTS").is_absolute_path():
				_start_attachment_lab060()
			elif FleetLab.presets().has(preset):
				lab_config=FleetLab.preset(data,preset);start_lab()
	if "--qa-workshop048" in args and OS.get_environment("GAME_TEST_ARTIFACTS").is_absolute_path():
		# Existing capture harness supplies an isolated portable copy and profile.
		new_game();paused = true
		if not core.state.fleet.is_empty():ui.open_refit(str(core.state.fleet[0].uid))
	if "--qa-coast050" in args and OS.get_environment("GAME_TEST_ARTIFACTS").is_absolute_path():
		new_game();paused = true
		screenshots_requested = ["home", "overview"]
		for port in data.PORTS:screenshots_requested.append(str(port.id))
	if "--qa-opening051" in args and OS.get_environment("GAME_TEST_ARTIFACTS").is_absolute_path():
		screenshots_requested = ["title051", "home051", "regional061051", "watch061051", "homebook061051", "harbor061051", "ocean064051", "glasswind064051", "home-return064051", "preparation065051", "transfer065051", "ocean-travel066051"]
	if "--qa-capture" in args:
		capture_after_start.call_deferred()

func _resize_interface():
	if ui == null:
		return
	if mode == "menu":
		ui.title_screen()
	else:
		ui.close_modal()
		ui.build_hud()

func _process(dt: float):
	Tactical.poll_planning051() # Also joins abandoned encounters while in menus.
	if chart == null:
		return
	if mode=="battle" and battle_driver051!=null:
		poll_battle051(dt,paused or ui.modal_open or result_handled)
	_finish_economy(false)
	if not core.state.is_empty() and core.pending_days > 0 and economy_task < 0:
		start_economy()
	if mode != "menu" and not ui.modal_open:
		var axis = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		if axis.length_squared() > 0:
			chart.pan_camera(axis.normalized(), minf(dt, 0.1), Input.is_physical_key_pressed(KEY_SHIFT))
	# Results settle immediately, while the last wreck and blast finish behind the panel.
	if mode=="battle" and result_handled and not paused and not battle.is_empty() and (not ui.modal_open or ui.modal_kind=="outcome"):
		Battle.advance_visuals(battle,minf(dt,0.1))
	chart.step(minf(dt, 0.1))
	_update_propulsion120(dt)
	music.set_context(music_context())
	hud_timer += dt
	if hud_timer >= 0.15:
		hud_timer = 0.0
		ui.update_hud()
		GuidanceUI120.refresh_next120(ui)
	if mode == "campaign":
		save_timer += dt
		# Keep autosave due until copied harbor days have settled on Main.
		# Explicit saves still join and verify their complete state.
		if save_timer > 20 and not ui.modal_open and economy_task < 0 and core.pending_days == 0:
			save_timer = 0
			save_game(false)
	if runtime_profile043!=null:runtime_profile043.after_process(dt)

## This cue reads the published flagship. It never writes a worker-owned boat.
func _update_propulsion120(dt: float) -> void:
	var boat: Dictionary={}
	var moving: float=0.0
	var engine_factor: float=0.0
	if not paused and not ui.modal_open:
		if mode=="battle" and not result_handled:
			boat=Battle.get_flagship(battle)
			moving=Vector2(float(boat.get("vx",0.0)),float(boat.get("vy",0.0))).length()
			var status: Dictionary=battle.get("tactical",{}).get("damageStatusById051",{}).get(str(boat.get("id","")),{})
			engine_factor=float(status.get("engineFactor",boat.get("engine",0.0)))
		elif mode=="campaign" and not core.state.is_empty():
			boat=core.find_boat(str(core.state.get("flagship","")))
			moving=_campaign_motion120
			engine_factor=float(boat.get("engine",0.0))
	var live: bool=not boat.is_empty() and not boat.get("sunk",false) and not boat.get("captureSecured",false) and float(boat.get("hp",0.0))>0.0 and float(boat.get("fuel",0.0))>0.0 and engine_factor>0.001 and float(boat.get("crew",0.0))-float(boat.get("wounded",0.0))>0.0
	var running: bool=live and is_finite(moving) and moving>1.0
	if not running:
		_engine_load120=0.0
		audio.set_engine(false,0.0)
		return
	var nominal: float=maxf(1.0,float(boat.get("spec",{}).get("speed",100.0)))
	var load: float=clampf(moving/nominal,0.0,1.0)*clampf(engine_factor,0.0,1.0)
	_engine_load120=move_toward(_engine_load120,load,minf(dt,0.1)*2.5)
	audio.set_engine(true,_engine_load120)

func set_guidance120(enabled: bool) -> void:
	first_voyage120.enabled=enabled
	GuidanceUI120.refresh_next120(ui)

func accept_guided_contract120(shown: Dictionary) -> Dictionary:
	if mode!="campaign":return core.fail("Return to the chart before accepting work.")
	sync_economy()
	var quote: Dictionary=CareerCosts120.contract_quote(core,shown)
	var actual: Dictionary=quote.get("offer",{})
	for key in ["id","port","targetPort","reward","enemyHulls","cargo"]:
		if actual.get(key)!=shown.get(key):
			var stale: Dictionary=core.fail("The contract changed. Review its current terms before accepting.")
			respond(stale)
			return stale
	if not quote.get("canAccept",false):
		var blockers120: Array=quote.get("blockers",[])
		var refused: Dictionary=core.fail(str(blockers120[0]) if not blockers120.is_empty() else "This contract is already active or unavailable.")
		respond(refused)
		return refused
	var result: Dictionary=core.accept_contract(str(actual.get("id","")))
	respond(result)
	if result.get("ok",false):
		save_game(false)
		ui.build_hud()
	return result

func apply_guided_fit120(shown: Dictionary) -> Dictionary:
	if mode!="campaign":return core.fail("Return to the chart before paying for a fitting.")
	sync_economy()
	var focus: String=str(shown.get("focus","armor"))
	var current: Dictionary=Guidance120.first_fit120(core,focus)
	var quoted: Dictionary=shown.get("quote",{})
	var fresh: Dictionary=current.get("quote",{})
	var same_bill: bool=not str(quoted.get("quoteId","")).is_empty() and str(quoted.quoteId)==str(fresh.get("quoteId","")) and shown.get("uid")==current.get("uid") and shown.get("loadout")==current.get("loadout")
	if not same_bill or not current.get("safe",false):
		var refused: Dictionary=core.fail("The bill or reserve changed. Review a fresh fitting quote." if not same_bill else str(current.get("message","Keep the crew and store reserve before fitting.")))
		GuidanceUI120.open_first_fit120(ui,focus)
		respond(refused)
		return refused
	var before: int=int(core.state.get("coins",0))
	var result: Dictionary=core.workshop_apply(str(current.uid),current.loadout,fresh)
	first_voyage120.observe_fit(result,before,int(core.state.get("coins",0)))
	respond(result)
	if result.get("ok",false) and result.get("changed",false):
		ui.workshop_drafts.erase(str(current.uid))
		save_game(false)
		ui.build_hud()
		GuidanceUI120.choose_work120(ui)
	else:GuidanceUI120.open_first_fit120(ui,focus)
	return result

func close_battle_guidance120(resume: bool) -> void:
	ui.close_modal()
	if mode!="battle" or result_handled:return
	if resume and tactical_mode:toggle_tactical()
	paused=not resume
	ui.update_hud()

func _physics_process(dt: float):
	_campaign_motion120=0.0
	if paused or ui == null or ui.modal_open:
		return
	if mode == "campaign":
		# Publish the worker's port snapshot before NPC arrivals can trade with these purses.
		_finish_economy(false)
		if economy_task>=0:return # Await copied port jobs without stalling a frame or trading stale purses.
		if core.pending_days>0:start_economy();return
		var before120: Dictionary=core.state.get("position",{}).duplicate()
		core.step(dt * speed)
		var after120: Dictionary=core.state.get("position",{})
		if dt>0.0 and before120.has("x") and after120.has("x"):
			_campaign_motion120=Vector2(float(after120.x)-float(before120.x),float(after120.y)-float(before120.y)).length()/maxf(0.001,dt*speed)
		handle_campaign_events067()
	# Battle numerical work belongs to the driver; rendering polls it in _process.

## Paid remote work can reach the same event boundary while a modal is open.
func handle_campaign_events067() -> void:
	for event in core.pop_events():
		match event.kind:
			"arrival":
				core.StoryOps.refresh(core)
				selected_port = event.port
				ui.toast("Arrived at %s. Enter harbor to trade, recruit, and refit." % core.port(event.port).name)
				audio.play("bell")
			"defeat":
				paused = true
				var body = ui.modal("Harbor rescue", "REPLACEMENT BOAT AND CREW", 700, 500)
				ui.paragraph(body, "Brass Haven can fund a replacement and crew from its treasury. The actual cost becomes a loan owed to the harbor.", 19)
				ui.button(body, "Accept harbor rescue", accept_rescue, true)
			"encounter":show_patrol_encounter(event.patrol)
			"ocean_encounter066":contact_action066(str(event.ownerId),"engage")
			"survey_complete":ui.toast("%s: %s"%[event.siteName,event.levelName])

func _publish_battle051(display: Dictionary) -> void:
	_publishing_battle051=true
	battle=display
	_publishing_battle051=false

func _battle_input051() -> Dictionary:
	var aim: Vector2=chart.world_at(get_global_mouse_position())
	var manual: bool=not bool(battle.get("autopilot",true)) and not tactical_mode
	return {"manual":manual,"forward":Input.is_key_pressed(KEY_UP),"backward":Input.is_key_pressed(KEY_DOWN),"left":Input.is_key_pressed(KEY_LEFT),"right":Input.is_key_pressed(KEY_RIGHT),"boost":Input.is_key_pressed(KEY_CTRL),"fire":manual and fire_held,"aimX":aim.x,"aimY":aim.y}

func poll_battle051(dt: float, stopped: bool) -> void:
	if battle_driver051==null:return
	var started: int=Time.get_ticks_usec()
	_publish_battle051(battle_driver051.advance(dt,_battle_input051(),stopped))
	battle_publication_us051=Time.get_ticks_usec()-started
	# Historical name retained for consumers; this is Main cost, NOT worker time.
	simulation_us=battle_publication_us051
	if runtime_profile043!=null and runtime_profile043.has_method("after_battle_publication051"):
		runtime_profile043.after_battle_publication051(dt)
	for receipt: Dictionary in battle_driver051.telemetry().get("commandResults",[]):
		var sequence: int=int(receipt.get("sequence",0))
		if sequence<=_battle_ack_sequence051:continue
		_battle_ack_sequence051=sequence
		if not receipt.get("ok",false):
			battle_command_ack=BattleCommands047.reply(str(receipt.get("kind","")),false,str(receipt.get("message","Command declined after checking the current battle state.")))
			ui.toast(str(battle_command_ack.message),true)
		elif str(receipt.get("kind",""))=="player_command":
			battle_command_ack=BattleCommands047.reply("player_command",true,str(receipt.get("message","Fleet command applied.")))
			first_voyage120.command_seen=true
	var events: Array=battle_driver051.take_events()
	if runtime_profile043!=null and runtime_profile043.has_method("observe_events051"):
		runtime_profile043.observe_events051(events)
	audio.consume(events,chart)
	if battle.get("result")!=null and not result_handled:
		_retire_battle_driver051()
		result_handled=true
		settle_battle.call_deferred()

func _start_battle_driver051() -> void:
	_battle_ports051.clear()
	# Keep campaign identities on Main, outside every worker input/publication.
	if not lab_active and not quick_mode:
		for fort: Dictionary in battle.get("coastalDefenses",[]):
			var port: Dictionary=fort.get("port",{})
			if not port.is_empty():_battle_ports051[str(port.id)]=port
	battle._labCommands051=lab_active
	battle_driver051=BattleDriver051.new(battle)
	_publish_battle051(battle_driver051.advance(0.0,{},true))
	battle_publication_us051=0;simulation_us=0
	_battle_ack_sequence051=0
	chart.reset_battle_presentation051()

func _reconcile_coastal_ports051(final: Dictionary) -> void:
	# Driver restores original boat identities; Main also publishes spent coastal
	# ammunition into the original campaign ports after worker ownership ends.
	for fort: Dictionary in final.get("coastalDefenses",[]):
		var port: Dictionary=fort.get("port",{})
		var target: Dictionary=_battle_ports051.get(str(port.get("id","")),{})
		if target.is_empty():continue
		if not is_same(target,port) and port.get("defenses") is Dictionary:
			var defenses: Dictionary=target.get("defenses",{})
			defenses.clear();defenses.merge(port.defenses.duplicate(true),true)
			target.defenses=defenses
		fort.port=target

func _retire_battle_driver051() -> void:
	if battle_driver051==null:return
	var final: Dictionary=battle_driver051.retire()
	battle_driver051=null
	if not _battle_ports051.is_empty():_reconcile_coastal_ports051(final)
	_publish_battle051(final)
	_battle_ports051.clear()
	if chart!=null:chart.clear_battle_poses051()

func queue_battle_command051(kind: String,payload: Dictionary={}) -> bool:
	if mode!="battle" or result_handled or battle_driver051==null:return false
	return battle_driver051.queue_command(kind,payload)

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if dev_enabled:
			if event.keycode==KEY_F9: dev_tools.shown=not dev_tools.shown;return
			if event.keycode==KEY_F6:
				if lab_active and battle_driver051!=null:
					queue_battle_command051("lab_refill",{})
				else:dev_tools.refill()
				return
			if event.keycode==KEY_F8: dev_tools.snapshot();return
			if event.keycode==KEY_PERIOD and lab_active and paused and not ui.modal_open:
				# One asynchronous owned step; the paused render loop polls completion.
				poll_battle051(1.0/30.0,false)
				return
		if event.keycode == KEY_F11:
			toggle_fullscreen()
			return
		if event.keycode == KEY_ESCAPE:
			if mode == "battle" and not ui.modal_open and not battle_command_pending.is_empty():
				battle_command_ack = BattleCommands047.reply(battle_command_pending, false, "Command canceled.")
				battle_command_pending = ""
				ui.toast("Command canceled.");ui.update_hud()
				return
			if ui.modal_open:
				if ui.modal_kind == "settings":
					ui.leave_settings()
				elif ui.modal_kind == "outcome":
					if quick_mode:
						return_to_title()
					elif core.active_fleet().is_empty():
						accept_rescue()
					else:
						return_to_campaign()
				else:
					ui.close_modal()
			elif mode != "menu":
				ui.open_menu()
			return
		if ui.modal_open or mode == "menu":
			return
		match event.keycode:
			KEY_SPACE: toggle_pause()
			KEY_F: ui.open_fleet() if mode == "campaign" else null
			KEY_C: ui.open_cargo() if mode == "campaign" else null
			KEY_J: ui.open_contracts() if mode == "campaign" else null
			KEY_H: ui.open_guide()
			KEY_I: ui.CampaignUI.islands(ui) if mode=="campaign" else null
			KEY_K: (ui.VoyageUI.open(ui) if core.home_local064() else ui.open_ocean064()) if mode=="campaign" else null
			KEY_L: (ui.RegionalUI.open(ui) if core.home_local064() else ui.open_ocean064()) if mode=="campaign" else null
			KEY_E: ui.open_port() if mode == "campaign" else null
			KEY_TAB: toggle_tactical() if mode == "battle" else null
			KEY_HOME: chart.center_camera()
			KEY_M: chart.territory_view() if mode=="campaign" else null
			KEY_U: toggle_autopilot() if mode == "battle" else null
			KEY_X: switch_flagship() if mode == "battle" else null
			KEY_R:
				if mode == "battle":
					auto_gunners = not auto_gunners
					ui.toast("Fleet gunnery is automatic while autopilot is on. U toggles flagship control.")
			KEY_1: command_selected("engage") if mode == "battle" else null
			KEY_2: command_selected("escort") if mode == "battle" else null
			KEY_3: command_selected("hold") if mode == "battle" else null
			KEY_F1, KEY_F2, KEY_F3, KEY_F4:
				if mode=="battle":
					var group: int=int(event.keycode)-int(KEY_F1)+1
					if event.ctrl_pressed:save_selection_group(group)
					else:recall_selection_group(group)
	elif event is InputEventMouseButton and not ui.modal_open:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			chart.zoom = clampf(chart.zoom * 1.12, 0.10 if mode=="campaign" else 0.45, 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			chart.zoom = clampf(chart.zoom / 1.12, 0.10 if mode=="campaign" else 0.45, 3.0)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if mode == "battle":
				if bool(battle.get("autopilot", true)) or tactical_mode:
					if event.pressed:
						selection_start = get_global_mouse_position()
						selection_dragging = true
					elif selection_dragging:
						finish_battle_selection(get_global_mouse_position(), Input.is_key_pressed(KEY_SHIFT))
				else:
					fire_held = event.pressed
			elif mode == "campaign" and event.pressed:
				click_chart(get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and mode == "battle":
			order_at(get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and mode == "campaign":
			core.stop_sailing()
			ui.toast("Engines idle. Course canceled.")

func _input(event):
	if event is InputEventMouseMotion and selection_dragging:
		selection_box = Rect2(selection_start, get_global_mouse_position() - selection_start).abs()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		fire_held = false
		if selection_dragging and mode == "battle" and not ui.modal_open:
			finish_battle_selection(get_global_mouse_position(), Input.is_key_pressed(KEY_SHIFT))

func toggle_pause():
	paused = not paused
	if mode=="battle":poll_battle051(0.0,true)
	ui.update_hud()

func toggle_fullscreen():
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
	save_preferences()

func save_preferences():
	Preferences.save_options(preferences_path,{"audio_enabled":audio.enabled,"weapon_volume":audio.weapon_volume,"ambience_volume":audio.ambience_volume,"music_enabled":music.enabled,"music_volume":music.volume,"frame_cap":Engine.max_fps,"fullscreen":DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN,"dev_enabled":dev_enabled})

func music_context() -> String:
	if mode=="menu":return "title"
	if mode=="battle":
		if battle.get("result")!=null:return "victory" if battle.result=="won" else "loss"
		if not quick_mode and not lab_active and battle_context.get("kind","")=="contract" and core.state.get("activeContract",{}).get("story",false) and int(core.state.get("missionIndex",0))==data.MISSIONS.size()-1:return "finale"
		return "combat"
	if ui.modal_open:
		return "contact" if ui.modal_kind=="encounter" else "harbor"
	return "travel"

func new_game(seed_override: int = 0):
	_retire_battle_driver051()
	_leave_lab()
	sync_economy()
	var begun: Dictionary = core.new_game(seed_override if seed_override != 0 else int(Time.get_unix_time_from_system()))
	if not begun.get("ok", false):
		ui.toast(str(begun.get("message", "New career was refused. The previous voyage is unchanged.")), true)
		return
	_present_new_voyage()
	save_game(false)

func _present_new_voyage():
	ui.workshop_drafts.clear()
	ui.voyage_intent065.clear()
	mode = "campaign"
	quick_mode = false
	paused = false
	chart.zoom = 1.0
	chart.center_camera()
	selected_port = data.START.port
	first_voyage120.begin(core,true)
	ui.close_modal()
	ui.build_hud()
	GuidanceUI120.open_first120(ui)

func new_voyage_needs_confirmation() -> bool:
	return has_save() or FileAccess.file_exists(save_directory.path_join("voyage.backup.json")) or not core.state.is_empty() or career_core != null

func _save_file_matches(path: String, bytes: PackedByteArray) -> bool:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:return false
	var matches: bool = file.get_length() == bytes.size()
	if matches:
		var read: PackedByteArray = file.get_buffer(bytes.size())
		matches = read == bytes and file.get_error() in [OK, ERR_FILE_EOF]
	file.close()
	return matches

func _store_save_copy(path: String, bytes: PackedByteArray) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:return false
	file.store_buffer(bytes)
	file.flush()
	var error: int = file.get_error()
	file.close()
	return error == OK

func _commit_save_file(staged: String, path: String) -> int:
	return DirAccess.rename_absolute(staged, path)

func _write_verified_save_copy(path: String, bytes: PackedByteArray) -> bool:
	# Only verified content receives a stable name. A failed temporary write
	# cannot block the next attempt, and existing stable files are never truncated.
	if FileAccess.file_exists(path):return _save_file_matches(path, bytes)
	if DirAccess.dir_exists_absolute(path):return false
	var temporary: String = ""
	for attempt: int in range(100):
		var proposed: String = "%s.writing.%d.%d" % [path, Time.get_ticks_usec(), attempt]
		if not FileAccess.file_exists(proposed) and not DirAccess.dir_exists_absolute(proposed):
			temporary = proposed
			break
	if temporary.is_empty():return false
	if not _store_save_copy(temporary, bytes) or not _save_file_matches(temporary, bytes):return false
	if FileAccess.file_exists(path):return _save_file_matches(path, bytes)
	if DirAccess.dir_exists_absolute(path) or _commit_save_file(temporary, path) != OK:return false
	return _save_file_matches(path, bytes)

func replace_voyage(seed_override: int = 0) -> bool:
	# Only the ordinary title-screen confirmation reaches this transaction.
	# Direct new_game calls retain the existing first-start, QA and lab contract.
	if mode != "menu" or lab_active or not ui.modal_open or ui.modal_kind != "new_voyage":return false
	if save_directory.is_empty() or DirAccess.make_dir_recursive_absolute(save_directory) != OK:
		ui.toast("Cannot prepare a saved replacement here. The previous voyage is unchanged.", true)
		return false
	var originals: Dictionary = {}
	var archives: PackedStringArray = []
	# Preserve the fallback too: a damaged primary must not cost the last good save.
	for name: String in ["voyage.json", "voyage.backup.json"]:
		var path: String = save_directory.path_join(name)
		if not FileAccess.file_exists(path):
			if DirAccess.dir_exists_absolute(path):
				ui.toast("A save path is a folder. The previous voyage is unchanged.", true)
				return false
			continue
		var original = FileAccess.open(path, FileAccess.READ)
		if original == null:
			ui.toast("Cannot read the saved voyage. Replacement was cancelled.", true)
			return false
		var length: int = original.get_length()
		var bytes: PackedByteArray = original.get_buffer(length)
		var error: int = original.get_error()
		original.close()
		if bytes.is_empty() or bytes.size() != length or error not in [OK, ERR_FILE_EOF]:
			ui.toast("Cannot read the complete saved voyage. Replacement was cancelled.", true)
			return false
		var digest: String = FileAccess.get_sha256(path)
		var archive: String = save_directory.path_join("voyage.before-new.%s.json" % digest)
		if digest.length() != 64 or not _write_verified_save_copy(archive, bytes) or FileAccess.get_sha256(archive) != digest:
			ui.toast("Cannot write and verify a preserved save. The previous voyage is unchanged.", true)
			return false
		originals[path] = {"bytes":bytes, "archive":archive}
		if not archives.has(archive):archives.append(archive)
	# Build and write off to the side; no old core, worker or UI state is retired yet.
	var candidate = Campaign.new(data.duplicate(true), core.nav, false)
	candidate.ocean_anchors064 = core.ocean_anchors064.duplicate(true)
	var begun: Dictionary = candidate.new_game(seed_override if seed_override != 0 else int(Time.get_unix_time_from_system()))
	if not begun.get("ok", false):
		ui.toast(str(begun.get("message", "New voyage was refused. The previous voyage is unchanged.")), true)
		return false
	candidate.state.version = Version.text()
	var text: String = JSON.stringify(candidate.state, "\t")
	var staged: String = save_directory.path_join("voyage.new.%s.pending" % text.sha256_text())
	if not _write_verified_save_copy(staged, text.to_utf8_buffer()):
		ui.toast("Cannot write and verify the new save. The previous voyage is unchanged.", true)
		return false
	# A changed source or archive aborts before the only replacement operation.
	for name: String in ["voyage.json", "voyage.backup.json"]:
		var path: String = save_directory.path_join(name)
		if FileAccess.file_exists(path) != originals.has(path):
			ui.toast("Saved files changed during preparation. Replacement was cancelled.", true)
			return false
		if originals.has(path) and (not _save_file_matches(path, originals[path].bytes) or not _save_file_matches(originals[path].archive, originals[path].bytes)):
			ui.toast("Saved files could not be verified again. Replacement was cancelled.", true)
			return false
	# Both files are in the same directory. A failed rename leaves the old save in place.
	if _commit_save_file(staged, save_directory.path_join("voyage.json")) != OK:
		ui.toast("Cannot replace the save file. The previous voyage is unchanged.", true)
		return false
	_retire_battle_driver051()
	_leave_lab()
	sync_economy()
	core = candidate
	_present_new_voyage()
	# The committed file is already verified; do not rotate it through save_game.
	if not archives.is_empty():
		ui.toast("Previous saves preserved at:\n%s\nRecovery: Guide > Preserved voyages." % "\n".join(archives))
	return true

func click_chart(position: Vector2):
	var view064: Dictionary=core.world_view064()
	if not core.home_local064():
		var contact066: Dictionary=chart.pick_contact066(position)
		if not contact066.is_empty():ui.open_ocean_contact066(str(contact066.get("contactId",contact066.get("ownerId",contact066.get("id","")))));return
		var pick064: Dictionary=chart.pick_ocean064(position)
		if not pick064.is_empty():
			if str(pick064.get("kind",""))=="contact":ui.open_ocean_contact066(str(pick064.get("contactId",pick064.get("ownerId",pick064.get("id","")))));return
			if str(pick064.get("kind",""))=="site":
				selected_site=str(pick064.get("siteId",""))
				ui.CampaignUI.site(ui,selected_site);return
			if str(pick064.get("kind",""))=="wreck":ui.RecoveryUI.open(ui,str(pick064.get("wreckId","")));return
			if str(pick064.get("kind",""))=="port":ShippingUI068.open(ui,str(pick064.get("portId","")));return
			var region064: String=str(pick064.get("regionId",""))
			var approach064: String=str(pick064.get("approachId",""))
			if str(view064.get("layer",""))=="ocean":
				ui.open_voyage_preparation065(region064,approach064)
			else:
				ui.open_ocean064(region064,approach064)
			return
		var point064: Vector2=chart.world_at(position)
		respond(core.chart_course({"x":point064.x,"y":point064.y}));return
	for gate064 in view064.get("approaches",[]):
		if chart.project(Vector2(gate064.position.x,gate064.position.y)).distance_to(position)<18:
			ui.open_ocean064(str(gate064.regionId),str(gate064.id));return
	var nearest: Dictionary = {}
	var nearest_distance: float=INF
	for p in core.state.ports:
		if str(p.get("regionId","shatter_coast"))!="shatter_coast":continue
		var d = chart.project(Vector2(p.x, p.y)).distance_to(position)
		if chart.campaign_harbor_hit054(p,position) and d < nearest_distance:
			nearest = p
			nearest_distance = d
	if not nearest.is_empty():
		selected_port = nearest.id
		var current = core.current_port()
		if not current.is_empty() and current.id == nearest.id:
			ui.open_port()
		else:
			ui.HarborRoute104.open(ui,str(nearest.id))
		return
	for site in core.Exploration.sites(core.state):
		if site.level>0 and (chart.project(Vector2(site.x,site.y)).distance_to(position)<22 or Rect2(chart.campaign_site_art054(site,int(site.level)).bounds).grow(3).has_point(position)):
			selected_site=site.id
			ui.CampaignUI.site(ui,site.id)
			return
	for patrol in core.state.patrols:
		if not patrol.active or bool(patrol.get("hidden",false)):continue
		var art: Dictionary=chart.campaign_patrol_art054(patrol)
		if not art.vessels.is_empty() and (chart.project(Vector2(patrol.x, patrol.y)).distance_to(position) < 15 or Rect2(art.bounds).grow(3).has_point(position)):
			show_patrol_encounter(patrol.id)
			return
	for w in core.state.get("wrecks",[]):
		if core.Expedition.home_local064(w) and w.get("status","")=="unclaimed" and (chart.project(Vector2(w.x,w.y)).distance_to(position)<16 or Rect2(chart.campaign_wreck_art054(w).bounds).grow(3).has_point(position)):
			ui.RecoveryUI.open(ui,w.id)
			return
	var world = chart.world_at(position)
	respond(core.chart_course({"x": world.x, "y": world.y}))

func sail_to(id: String):
	if not core.home_local064():ui.toast("Return through a Shatter Coast approach before charting a harbor.",true);return
	var p = core.port(id)
	if p.is_empty():
		return
	core.use_reserves()
	respond(core.chart_course({"x": p.x, "y": p.y}, id))
	selected_port = id

func sail_approach064(region_id: String,approach_id: String):
	if mode!="campaign":return
	sync_economy()
	var result: Dictionary=core.approach_course064(region_id,approach_id)
	ui.close_modal();respond(result)

func enter_approach064(region_id: String,approach_id: String):
	if mode!="campaign" or (ui.modal_open and ui.modal_kind!="ocean064"):return
	sync_economy()
	var result: Dictionary=core.transition064(region_id,approach_id)
	if result.get("ok",false):
		selected_port="";selected_site=""
		ui.close_modal();chart.center_camera();ui.build_hud();save_game(false)
	respond(result)

## One explicit action from a fresh quote; no saved itinerary executor.
## Reserve shortages are advice. Core retains the real course/crossing guards.
func voyage_action065(intent: Dictionary) -> Dictionary:
	if mode!="campaign":return core.fail("Return to the campaign chart before preparing a course.")
	sync_economy()
	var quote: Dictionary=core.voyage_quote065(intent)
	var result: Dictionary
	var action: Dictionary=quote.get("nextAction",{})
	var kind: String=str(action.get("kind","none"))
	if not quote.get("routeOk",false):result=core.fail(str(quote.get("message","Choose a reachable voyage route.")))
	elif kind=="course":result=core.chart_course(action.get("target",{}),str(action.get("destination","")))
	elif kind=="transition":result=core.transition064(str(action.get("regionId","")),str(action.get("approachId","")))
	else:result=core.fail("The selected destination is reached. Choose a home destination to plan your return.")
	if result.get("ok",false):
		selected_port=str(action.get("destination","")) if kind=="course" and not str(action.get("destination","")).begins_with("approach:") else ""
		selected_site=""
		ui.close_modal()
		if kind=="transition":chart.center_camera();ui.build_hud()
		save_game(false)
	else:ui.open_voyage_preparation065()
	respond(result)
	return result

func accept_voyage_job(id: String,carrier_uid: String="") -> Dictionary:
	if mode!="campaign":return core.fail("Return to the campaign chart before accepting harbor work.")
	sync_economy()
	var result: Dictionary=core.accept_voyage_job(id,carrier_uid)
	if result.get("ok",false):save_game(false)
	respond(result)
	return result

func prepare_voyage_job070(id: String) -> Dictionary:
	if mode!="campaign":return core.fail("Return to the campaign chart before preparing harbor work.")
	sync_economy()
	var job: Dictionary=core.VoyageJobs._find(core.state,id)
	if job.is_empty():
		for offer in core.VoyageJobs.available(core):
			if str(offer.get("id",""))==id:job=offer;break
	if job.is_empty():
		var missing: Dictionary=core.fail("That work offer is no longer available. Review the current board.")
		respond(missing)
		return missing
	var quote: Dictionary=core.VoyageJobs.offer_view070(core,job)
	var action: Dictionary=quote.get("nextAction",{})
	var kind: String=str(action.get("kind","none"))
	var result: Dictionary
	if not quote.get("routeOk",false):result=core.fail(str(quote.get("message","No reachable work route is available.")))
	elif kind=="course":result=core.chart_course(action.get("target",{}),str(action.get("destination","")))
	elif kind=="transition":result=core.transition064(str(action.get("regionId","")),str(action.get("approachId","")))
	else:result=core.fail("This leg is reached. Review the job's completion requirements.")
	if result.get("ok",false):
		selected_port=str(action.get("destination","")) if kind=="course" and not str(action.get("destination","")).begins_with("approach:") else ""
		selected_site=""
		ui.close_modal()
		if kind=="transition":chart.center_camera();ui.build_hud()
		save_game(false)
	respond(result)
	return result

func settle_voyage_job(id: String,abandon: bool=false) -> Dictionary:
	if mode!="campaign":return core.fail("Return to the campaign chart before settling harbor work.")
	sync_economy()
	var before120: int=int(core.state.get("coins",0))
	var result: Dictionary=core.settle_voyage_job(id,abandon)
	if not abandon:first_voyage120.observe_payment(result,before120,int(core.state.get("coins",0)))
	if result.get("ok",false):save_game(false)
	respond(result)
	return result

func transfer_fuel065(source_uid: String,target_uid: String,quantity: float) -> Dictionary:
	if mode!="campaign":return core.fail("Return to the campaign chart before transferring fuel.")
	sync_economy()
	var result: Dictionary=core.transfer_fuel065(source_uid,target_uid,quantity)
	if result.get("ok",false):save_game(false)
	ui.open_voyage_preparation065()
	respond(result)
	return result

func load_reserves065() -> Dictionary:
	if mode!="campaign":return core.fail("Return to the campaign chart before loading reserves.")
	sync_economy()
	if not core.travel_lock064.is_empty():return core.fail(core.travel_lock064)
	for event in core.events:
		if event.get("kind","") in ["encounter","defeat"]:return core.fail("Resolve the pending encounter before loading reserves.")
	core.use_reserves()
	save_game(false)
	ui.open_voyage_preparation065()
	var result: Dictionary=core.ok("Loaded available hold reserves into working ammunition, fuel and repair kits. Food stays in the hold.")
	respond(result)
	return result

func respond(result: Dictionary):
	ui.toast(str(result.get("message", "Done.")), not result.get("ok", false))
	ui.update_hud()
	if result.get("ok", false):
		audio.play("bell")

func trade(good: String, amount: int, side: String):
	sync_economy()
	var p = core.current_port()
	if p.is_empty():
		return
	respond(core.trade(p.id, good, amount, side))
	ui.open_port("Market")
	save_game(false)

func remote_trade068(good: String,qty: int,side: String,port_id: String="") -> Dictionary:
	if mode!="campaign":return core.fail("Return to the campaign chart before trading at the anchorage.")
	sync_economy()
	var result: Dictionary=core.remote_trade068(good,qty,side,port_id)
	respond(result)
	if result.get("ok",false):save_game(false)
	if ui.modal_open and ui.modal_kind=="shipping068":
		var shown: String=str(result.get("receipt",{}).get("portId",port_id))
		if shown.is_empty():shown=str(core.remote_port068().get("id",core.ShippingFlow068.PORT))
		ShippingUI068.open(ui,shown)
	return result

func buy_boat(id: String):
	sync_economy()
	respond(core.buy_boat(id))
	ui.open_port("Boatyard")
	save_game(false)

func commission(id: String):
	sync_economy()
	respond(core.commission(id))
	ui.open_port("Boatyard")
	save_game(false)

func collect_boat(index: int):
	sync_economy()
	respond(core.collect_boat(index))
	ui.open_port("Crew & repairs")
	save_game(false)

func recruit(uid: String, amount: int):
	sync_economy()
	respond(core.recruit_crew(uid, amount))
	ui.refresh_fleet()
	save_game(false)

func repair_boat(uid: String):
	sync_economy()
	respond(core.repair_boat(uid))
	ui.refresh_fleet()
	save_game(false)

func resupply_boat(uid: String, profile: String = "full"):
	sync_economy()
	respond(core.resupply_boat(uid,profile))
	ui.refresh_fleet()
	save_game(false)

func sell_boat(uid: String):
	sync_economy()
	respond(core.sell_boat(uid))
	ui.refresh_fleet()
	save_game(false)

func accept_contract(id: String):
	sync_economy()
	respond(core.accept_contract(id))
	ui.close_modal()
	ui.build_hud()
	ui.open_contracts()
	save_game(false)

func resolve_contract():
	sync_economy()
	if not core.contract_ready():
		respond(core.fail("Reach your contract's destination first."))
		return
	var contract = core.state.activeContract
	if contract.cleared:
		var first_payment120: bool=not first_voyage120.earned
		var before120: int=int(core.state.get("coins",0))
		var result120: Dictionary=core.finish_contract()
		first_voyage120.observe_payment(result120,before120,int(core.state.get("coins",0)))
		respond(result120)
		ui.close_modal()
		ui.build_hud()
		save_game(false)
		if result120.get("ok",false) and first_payment120 and first_voyage120.earned and first_voyage120.enabled:
			first_voyage120.offer_reinvestment=false
			GuidanceUI120.open_first_fit120(ui)
	else:
		var specs: Array = []
		for id in contract.enemyHulls:
			specs.append(core.hull(id))
		begin_battle(specs, {"kind": "contract", "id": contract.id, "ownerId":contract.get("ownerId",""), "name": "%s approaches" % core.port(contract.targetPort).name})

func show_patrol_encounter(id: String):
	if core.NavalAI.NavalOrders.enrolled066(core.state,id):
		if not core.home_local064():ui.open_ocean_contact066(id)
		return
	if not core.home_local064():return
	var patrol: Dictionary = {}
	for p in core.state.patrols:
		if p.id == id:
			patrol = p
	if patrol.is_empty():
		return
	var owner: Dictionary=core.fleet_owner(id)
	var contact: Dictionary=core.Politics.encounter(core.state,owner)
	var contact_name: String=str(patrol.name)
	if contact_name=="Coastal convoy" and contact.kind=="patrol":contact_name="%s patrol"%str(contact.factionName)
	var body = ui.modal(contact_name, "CONTACT ON THE COAST", 700, 550)
	ui.modal_kind = "encounter"
	if not owner.is_empty():ui.paragraph(body,str(owner.get("reason","")),15,ui.GOLD)
	patrol.hostile=core.Politics.hostile(core,owner)
	ui.paragraph(body,"%s · %s"%[str(contact.factionName),str(contact.role).capitalize()],19)
	ui.paragraph(body,str(contact.reason),15,ui.RED if patrol.hostile else ui.GOLD)
	if not owner.is_empty() and core.distance(core.state.position,patrol)<=1800.0 and owner.boats.any(func(b):return not b.sunk):
		core.Contacts.record_captain(core.state,id,"hail:%s:%d"%[id,int(core.state.day)],"Exchanged signals on the coastal route.")
		var captain: Dictionary=core.Contacts._find(core.state,"captain:"+id)
		if not captain.is_empty():
			ui.label(body,str(captain.name),21,ui.GOLD,true)
			for memory in captain.log.slice(-2):ui.paragraph(body,str(memory.get("detail",memory.event)),14)
	var loaded: bool=owner.get("kind","")=="trader" and float(owner.get("tradeCargo",0))>0
	if not patrol.hostile:
		var passage: String="This %s signals peaceful passage. Its current coastal purpose is shown above."%str(contact.role)
		if contact.kind=="trader":
			passage="This merchant convoy carries goods between coastal ports. Its crews signal peaceful passage." if loaded else "This merchant convoy is sailing without a trade load. Its crews signal peaceful passage."
		ui.paragraph(body,passage,19)
		ui.button(body, "Let them pass", ui.close_modal, true)
		if loaded and not core.EscortOps.threat(core,owner).is_empty():
			ui.paragraph(body,"Protect the loaded boats until they physically reach the far exit zone. Elapsed time alone cannot secure their passage; surviving boats keep their cargo for the onward voyage.",16,ui.GOLD)
			ui.button(body,"Protect convoy to its exit",func():core.EscortOps.start(self,id))
		ui.paragraph(body,"Opening fire damages public standing, creates a witnessed offense and a harbor claim.",15,ui.RED)
		ui.paragraph(body,"Interception: stop the loaded boats before they reach the far exit. Escaped boats keep their goods. Recover only the cargo and damaged hulls left under your control." if loaded else "No loaded trade convoy is present. An attack promises no cargo prize.",16)
		ui.button(body,"Intercept this convoy" if loaded else "Attack this fleet",func():engage_patrol(patrol))
		return
	if not owner.is_empty() and owner.kind=="trader":
		ui.paragraph(body,"A hostile convoy is carrying actual goods along this route. Stop its loaded boats before they physically reach the far exit zone. Boats that escape keep their cargo for the onward voyage." if loaded else "This hostile convoy has no trade load aboard. Engaging it promises no cargo prize.",19)
		ui.button(body,"Intercept this convoy" if loaded else "Engage this fleet",func():engage_patrol(patrol),true)
		ui.button(body,"Avoid contact",func():core.state.encounterGrace=90.0;ui.close_modal())
		return
	ui.paragraph(body,"This hostile %s can be engaged or given a wide berth. Its strength is %d boat(s)."%[str(contact.role),int(patrol.strength)],19)
	ui.button(body,"Engage the raiders" if contact.kind=="raider" else "Engage this fleet",func():engage_patrol(patrol),true)
	ui.button(body, "Avoid contact", func(): core.state.encounterGrace = 90.0; ui.close_modal())

func engage_patrol(patrol: Dictionary):
	if core.NavalAI.NavalOrders.enrolled066(core.state,str(patrol.get("id",""))):contact_action066(str(patrol.id),"engage");return
	if not core.home_local064() or core.distance(core.state.position,patrol)>1800.0:
		ui.toast("Approach this fleet in Shatter Coast waters before engaging.",true);return
	var owner: Dictionary=core.fleet_owner(patrol.id)
	if owner.is_empty() or not owner.get("active",false) or not owner.get("boats",[]).any(func(b):return not b.sunk):
		ui.toast("This contact has no surviving fleet to engage.",true)
		return
	var aggression: bool=not core.Politics.hostile(core,owner)
	if aggression:core.Politics.declare_attack(core,owner)
	var specs: Array = [core.hull("bilge_punt")]
	if patrol.strength >= 2:
		specs.append(core.hull("scab_cutter"))
	if patrol.strength >= 3:
		specs.append(core.hull("barbed_lance"))
	begin_battle(specs, {"kind": "patrol", "id": patrol.id, "ownerId":patrol.id,"aggression":aggression, "name": "Coastal shipping lane"})

func encounter_position(context: Dictionary) -> Dictionary:
	if str(context.get("kind",""))=="ocean066":return context.encounterPosition.duplicate(true)
	if not core.home_local064():return core.state.position.duplicate(true)
	if context.get("encounterPosition") is Dictionary and context.encounterPosition.has("x") and context.encounterPosition.has("y"):
		return context.encounterPosition.duplicate(true)
	var contact_id: String=str(context.get("allyOwnerId","") if context.get("kind","")=="escort" else context.get("ownerId","") if context.get("kind","")=="patrol" else "")
	for patrol in core.state.patrols:
		if str(patrol.id)==contact_id:return {"x":float(patrol.x),"y":float(patrol.y)}
	return core.state.position.duplicate(true)

func begin_battle(specs: Array, context: Dictionary):
	if str(context.get("kind",""))=="ocean066":
		sync_economy()
		var checked066: Dictionary=core.encounter_context066(str(context.get("ownerId","")))
		if not checked066.get("ok",false):ui.toast(str(checked066.message),true);return
		context=checked066.context
		var physical066: Array=core.fleet_owner(str(context.ownerId)).get("boats",[]).filter(func(b):return not b.get("sunk",false))
		if physical066.is_empty():ui.toast("This contact has no surviving physical fleet.",true);return
		context["ownerUids066"]=physical066.map(func(b):return str(b.uid))
		specs=physical066.map(func(b):return b.spec.duplicate(true))
	if not core.home_local064() and context.get("kind","") in ["patrol","escort","contract"]:
		ui.toast("This coastal contact belongs to Shatter Coast waters.",true);return
	if core.FleetSupport.combat(core).is_empty():
		ui.toast("You need a crewed boat marked for battle deployment.", true)
		return
	sync_economy()
	context=core.EscortOps.prepare_intercept(core,context)
	if not str(context.get("startError","")).is_empty():
		ui.toast(str(context.startError),true)
		return
	core.use_reserves()
	save_game(false)
	quick_mode = false
	core.stop_sailing()
	battle_enemies = specs
	battle_context = context.duplicate(true)
	var owner = core.fleet_owner(str(context.get("ownerId","")))
	var enemy_fleet = owner.get("boats",[]).filter(func(b):return not b.sunk) if not owner.is_empty() else []
	if str(context.get("kind",""))=="ocean066" and enemy_fleet.is_empty():ui.toast("Offshore contact lost its physical boats.",true);return
	var player_fleet: Array=core.FleetSupport.combat(core)
	if context.get("kind","")=="escort":
		var ally_owner: Dictionary=core.fleet_owner(str(context.get("allyOwnerId","")))
		player_fleet=ally_owner.get("boats",[]).filter(func(b):return not b.sunk and b.crew>=b.crewMin)+player_fleet
	for boat in player_fleet:boat.supportRepairFactor=1.0
	var geography064: Dictionary=data if core.home_local064() else {"ISLANDS":core.world_view064().get("islands",[])}
	var options: Dictionary=CoastalTerrain.arena(geography064,encounter_position(context))
	options.merge({"fleet":player_fleet,"mission":context.get("mission",{}),"enemySpecs":specs,"enemyFleet":enemy_fleet,"seed":int(core.state.seed)+core.state.wins*17+core.state.losses*5})
	battle = Battle.create(options)
	if not str(battle.get("startError","")).is_empty():
		ui.toast(str(battle.startError),true)
		battle={}
		return
	core.travel_lock064="Resolve the current battle before changing charts."
	battle.world064=core.world_location064().world064
	battle.chartPosition=encounter_position(context)
	battle_context.mission=battle.mission.duplicate(true)
	battle.captureSlots=maxi(0,64-core.state.get("boardingPrizes",[]).size())
	core.BoardingOps.coastal(core,battle)
	_enter_battle()

func contact_action066(id: String,action: String) -> Dictionary:
	if mode!="campaign":return core.fail("Return to the chart before choosing a contact action.")
	sync_economy()
	if action=="engage":
		var checked: Dictionary=core.encounter_context066(id)
		if not checked.get("ok",false):respond(checked);return checked
		begin_battle([],checked.context)
		return {"ok":mode=="battle","message":"Offshore engagement started." if mode=="battle" else "Offshore engagement could not start."}
	var result: Dictionary=core.contact_action066(id,action)
	if result.get("ok",false):ui.close_modal();save_game(false)
	respond(result)
	return result

func resume_voyage066() -> Dictionary:
	if mode!="campaign":return core.fail("Return to the chart before resuming a voyage.")
	sync_economy()
	var result: Dictionary=core.resume_voyage066()
	if result.get("ok",false):ui.close_modal();save_game(false)
	respond(result)
	return result

func quick_battle():
	lab_config=FleetLab.preset(data,"mixed")
	start_lab()

func start_coastal_clash():
	lab_config=FleetLab.preset(data,"coastal_clash")
	lab_seed=41041
	start_lab()
	if mode=="battle" and str(battle_context.get("kind",""))=="coastal_clash" and ui!=null:
		ui.toast("Raiders are in range. Screen the packet and put guns and torpedoes on them.")

func _leave_lab():
	if career_core!=null:
		core=career_core
		career_core=null
	lab_active=false
	quick_mode=false

func workshop_try_draft(uid: String, loadout: Dictionary) -> bool:
	if mode != "campaign" or lab_active or career_core != null:
		ui.toast("Return to your voyage before trying an owned boat draft.", true)
		return false
	sync_economy()
	var owned: Dictionary = core.find_boat(uid)
	if owned.is_empty() or owned.get("sunk", false):
		ui.toast("Choose a living owned boat to try.", true)
		return false
	var base: Dictionary = core.hull(str(owned.type))
	var checked: Dictionary = Refit.normalize(base, loadout)
	if not checked.ok:
		ui.toast(str(checked.message), true)
		return false
	var candidate: Dictionary = FleetLab.preset(data, "duel")
	candidate.player = [{"hull": str(base.id), "count": 1, "loadout": checked.loadout.duplicate(true)}]
	candidate.enemy = [FleetLab.entry(data, "ash_corvette")]
	candidate.formation = "closing"
	candidate.label = "Workshop draft trial"
	candidate.guidance = "Repeatable draft trial. No fittings purchased and no voyage rewards. Use Selected tactics for this battle's automatic-fire settings."
	var inspected: Dictionary = FleetLab.inspect(data, candidate)
	if not inspected.ok:
		ui.toast(str(inspected.error), true)
		return false
	lab_config = candidate
	lab_seed = 48048
	start_lab()
	return lab_active and mode == "battle"

func open_lab():
	if mode=="campaign": save_game(false)
	_leave_lab()
	mode="menu"
	battle={}
	ui.modal_kind=""
	ui.title_screen()
	LabUI.open(ui)

func _start_attachment_lab060() -> void:
	# Declared laboratory motion fixture. The independent native060 career
	# proof pays for these fits and hires; this arena grants no career assets.
	var examples060: Array = WorkshopBuilds060.examples(FleetLab.hull(data, "iron_bastion"))
	if examples060.size() < 2:push_error("Attachment060 laboratory fits missing");return
	lab_config = FleetLab.preset(data, "duel")
	lab_config.player = [];lab_config.enemy = [FleetLab.entry(data, "iron_bastion", 2)]
	lab_config.formation = "";lab_config.label = "Crew and command comparison"
	for index060 in range(2):
		var entry060: Dictionary = FleetLab.entry(data, "iron_bastion")
		entry060.loadout = examples060[index060].loadout.duplicate(true)
		lab_config.player.append(entry060)
	start_lab(func(arena060: Dictionary):
		var allies060: Array = arena060.ships.filter(func(ship060):return ship060.team == "player")
		var foes060: Array = arena060.ships.filter(func(ship060):return ship060.team == "enemy")
		for index060 in range(2):
			var ship060: Dictionary = allies060[index060]
			ship060.name = "Pilot · gun pressure" if index060 == 0 else "Gunner · cannon anchor"
			ship060.specialistActive = {"pilot":true} if index060 == 0 else {"gunner":true}
			ship060.spec = Campaign.FleetIdentity.effective(ship060, ship060.spec)
			Tactical.register(arena060, ship060, Battle._base_mounts(ship060))
			if not Battle.set_tactical_options(arena060, [ship060.id], {"doctrine":"cautious" if index060 == 0 else "aggressive", "role":str(examples060[index060].role)}):
				push_error("Attachment060 laboratory command refused")
			for pair060 in [ship060, foes060[index060]]:
				pair060.x = 600.0 if pair060.team == "player" else 1000.0
				pair060.y = 650.0 + 400.0 * index060
				pair060.angle = 0.0 if pair060.team == "player" else PI
				pair060.turretAngle = pair060.angle
				arena060.tactical.home[str(pair060.id)] = {"x":380.0 if pair060.team == "player" else 1220.0, "y":float(pair060.y)}
	)
	chart.zoom = 1.0;chart.camera = Vector2(800.0, 850.0);chart.follow_camera = false

func start_lab(prepare051: Callable=Callable()):
	sync_economy()
	if lab_config.is_empty():lab_config=FleetLab.preset(data,"mixed")
	var built: Dictionary=FleetLab.create(data,lab_config,lab_seed)
	if not built.ok:
		ui.toast(built.error,true)
		return
	if career_core==null:career_core=core
	# HUD-only Lab reuses immutable navigation; skip career/ocean initialization and saves.
	core=Campaign.new(data,core.nav,false)
	core.state={"coins":0,"day":0.0,"fleet":[]}
	lab_active=true
	quick_mode=true
	battle=built.battle
	# Observer formation/damage setup is Main-only and precedes ownership transfer.
	if prepare051.is_valid():prepare051.call(battle)
	battle_enemies=battle.ships.filter(func(s):return s.team=="enemy").map(func(s):return s.spec)
	var skirmish: bool=str(lab_config.get("context",""))=="coastal_clash"
	battle_context={"kind":"coastal_clash" if skirmish else "laboratory","name":str(lab_config.get("label","Coastal Clash")) if skirmish else "Fleet battle laboratory"}
	_enter_battle()

func _enter_battle():
	audio.reset_battle()
	ui.modal_kind = ""
	mode = "battle"
	var first_orders120: bool=not quick_mode and not lab_active and first_voyage120.enabled and not first_voyage120.earned and not first_voyage120.battle_introduced and str(battle_context.get("kind",""))=="contract"
	paused = first_orders120
	if first_orders120:first_voyage120.battle_introduced=true
	first_voyage120.command_seen=false
	tactical_mode = false
	auto_gunners = true
	Battle.set_autopilot(battle, true)
	result_handled = false
	battle_report = {}
	salvage_claimed = false
	battle_last_wrecks = 0
	selection_dragging = false
	selected_battle_ids = [battle.playerId] if battle.playerId != null else []
	battle_command_pending = "";battle_command_ack = {}
	battle_selection_groups={1:[],2:[],3:[],4:[]}
	_start_battle_driver051()
	chart.battle_overlays={"arcs":false,"threat":false,"routes":false}
	chart.zoom = 2.0 if battle.ships.size() <= 8 else 1.4
	chart.set_tactical(false)
	chart.center_camera()
	ui.close_modal()
	ui.build_hud()
	if first_orders120:ui.toast("Paused for your first order. Select your boat, choose Focus attack and right-click an enemy. Space resumes; autopilot handles the helm.")
	else:ui.toast("Autopilot engaged. Space pauses; select boats and right-click to give orders. Tab opens the tactical view.")
	if RecoveryFlow.is_convoy(battle):ui.toast(RecoveryFlow.objective_label(battle))

func switch_flagship():
	var fleet = battle.ships.filter(func(s): return s.team == "player" and not s.sunk and not s.get("captureSecured",false))
	if fleet.is_empty():
		return
	var index = 0
	for i in range(fleet.size()):
		if fleet[i].id == battle.playerId:
			index = (i + 1) % fleet.size()
			break
	Battle.select_flagship(battle, fleet[index].id)
	select_battle_boat(str(fleet[index].id))
	ui.update_hud()

func toggle_autopilot():
	if mode != "battle" or battle.is_empty():
		return
	var enabled: bool=not bool(battle.get("autopilot",true))
	Battle.set_autopilot(battle, enabled)
	if tactical_mode:pre_tactical_autopilot=enabled
	fire_held = false
	ui.toast("Flagship autopilot engaged." if enabled else "Manual flagship: arrow keys steer, mouse aims/fires. WASD still moves the camera.")
	ui.update_hud()

func toggle_tactical():
	if mode != "battle":
		return
	tactical_mode = not tactical_mode
	if tactical_mode:
		pre_tactical_paused = paused
		pre_tactical_autopilot=bool(battle.get("autopilot",true))
		paused = true
		Battle.set_autopilot(battle, true)
	else:
		paused = pre_tactical_paused
		Battle.set_autopilot(battle,pre_tactical_autopilot)
	chart.set_tactical(tactical_mode)
	fire_held = false
	ui.update_hud()

func select_battle_boat(id: String, additive: bool = false):
	if not battle.ships.any(func(boat):return str(boat.id)==id and boat.team=="player" and not boat.sunk and not boat.get("captureSecured",false)):
		return
	if not additive:
		selected_battle_ids.clear()
	if not id in selected_battle_ids:
		selected_battle_ids.append(id)
	ui.update_hud()

func set_selected_tactical_options(options: Dictionary) -> bool:
	if mode!="battle" or battle.is_empty():return false
	var ok: bool=Battle.set_tactical_options(battle,selected_battle_ids.duplicate(),options)
	if not ok:ui.toast("Choose living owned boats and valid tactical choices.",true)
	else:ui.toast("Selected boats' tactical choices updated.")
	ui.update_hud()
	return ok

func set_selected_formation(formation: String) -> bool:
	return set_selected_tactical_options({"formation":formation})

func set_battle_overlay(kind: String, enabled: bool) -> bool:
	if mode != "battle" or chart == null or not chart.battle_overlays.has(kind):return false
	chart.battle_overlays[kind] = enabled
	chart.queue_redraw()
	return true

func save_selection_group(group: int) -> bool:
	if mode!="battle" or group<1 or group>4 or selected_battle_ids.is_empty():return false
	var ids: Array=[]
	for id in selected_battle_ids:
		if battle.ships.any(func(boat):return str(boat.id)==str(id) and boat.team=="player" and not boat.sunk and not boat.get("captureSecured",false)):ids.append(str(id))
	if ids.is_empty():return false
	var previous: Array = battle.get("tactical",{}).get("groups",{}).get(group,[]).duplicate()
	if not Battle.set_tactical_options(battle,ids,{"group":group}):return false
	var released: Array = previous.filter(func(id):return id not in ids and battle.ships.any(func(boat):return str(boat.id)==str(id) and boat.team=="player" and not boat.sunk and not boat.get("captureSecured",false)))
	if not released.is_empty():Battle.set_tactical_options(battle,released,{"group":0})
	for other in battle_selection_groups:
		battle_selection_groups[other] = battle_selection_groups[other].filter(func(id):return id not in ids)
	battle_selection_groups[group]=ids.duplicate()
	ui.toast("Group %d saved. Formation choices apply when escorting."%group)
	ui.update_hud()
	return true

func recall_selection_group(group: int) -> bool:
	if mode!="battle" or group<1 or group>4:return false
	var ids: Array=[]
	for id in battle.get("tactical",{}).get("groups",{}).get(group,battle_selection_groups.get(group,[])):
		if battle.ships.any(func(boat):return str(boat.id)==str(id) and boat.team=="player" and not boat.sunk and not boat.get("captureSecured",false)):ids.append(str(id))
	if ids.is_empty():ui.toast("Group %d has no living boats saved."%group);return false
	selected_battle_ids=ids
	ui.update_hud()
	return true

func withdraw_fleet():
	if mode!="battle" or battle.is_empty():return
	Battle.retreat(battle)
	if tactical_mode:pre_tactical_autopilot=true
	fire_held=false
	ui.toast("Fleet withdrawal ordered; autopilot engaged. U retakes manual control.")
	ui.update_hud()

func select_all_boats():
	selected_battle_ids.clear()
	for boat in battle.get("ships", []):
		if boat.team == "player" and not boat.sunk and not boat.get("captureSecured",false):
			selected_battle_ids.append(boat.id)
	ui.update_hud()

func finish_battle_selection(position: Vector2, additive: bool = false):
	selection_dragging = false
	var rectangle = Rect2(selection_start, position - selection_start).abs()
	if rectangle.size.length() < 8:
		var hit120: Dictionary=chart.pick_battle_boat120(position,"player")
		if not hit120.is_empty():select_battle_boat(str(hit120.id),additive)
	else:
		if not additive:
			selected_battle_ids.clear()
		for boat in battle.ships:
			if boat.team == "player" and not boat.sunk and not boat.get("captureSecured",false) and rectangle.has_point(chart.project(chart.battle_boat_position051(boat))) and not boat.id in selected_battle_ids:
				selected_battle_ids.append(boat.id)
	selection_box = Rect2()
	ui.update_hud()

func command_selected(order: String, target: Dictionary = {}):
	if battle.is_empty():
		return
	if order == "escort" and target.is_empty():
		target = {"shipId":str(battle.playerId)}
	selected_battle_ids = selected_battle_ids.filter(func(id):return battle.ships.any(func(boat):return boat.id==id and boat.team=="player" and not boat.sunk and not boat.get("captureSecured",false)))
	if selected_battle_ids.is_empty():
		select_all_boats()
	# Existing keys/context/options callers retain their chosen role and doctrine.
	battle_command_pending = ""
	var ok: bool = Battle.issue_order(battle, selected_battle_ids, order, target)
	battle_command_ack = BattleCommands047.reply(order, ok, "Order received: " + order.capitalize() + "." if ok else "Choose navigable water or a living target for that order.", selected_battle_ids.size() if ok else 0)
	if ok and battle.playerId in selected_battle_ids and not bool(battle.get("autopilot", true)):battle_command_ack.message += " Flagship order waits for autopilot (U)."
	ui.toast(str(battle_command_ack.message), not ok)
	ui.update_hud()

func request_battle_command(command: String, target: Dictionary = {}) -> bool:
	if mode != "battle" or battle.is_empty():return false
	selected_battle_ids = selected_battle_ids.filter(func(id):return battle.ships.any(func(boat):return str(boat.id)==str(id) and boat.team=="player" and not boat.sunk and not boat.get("captureSecured",false)))
	if command not in BattleCommands047.COMMANDS or selected_battle_ids.is_empty():
		battle_command_ack = BattleCommands047.reply(command, false, "Select living friendly boats to command.")
	elif BattleCommands047.needs_target(command) and target.is_empty():
		battle_command_pending = command
		var prompt: String = {"focus":"Right-click an enemy to focus attack.","escort":"Right-click a friendly boat to protect.","defend":"Right-click open water to defend.","rally":"Right-click open water to rally."}[command]
		battle_command_ack = BattleCommands047.reply(command, true, prompt, selected_battle_ids.size())
	else:
		battle_command_pending = command if BattleCommands047.needs_target(command) else ""
		if battle_driver051!=null:
			var queued: bool=queue_battle_command051("player_command",{"ids":selected_battle_ids.duplicate(),"command":command,"target":target})
			battle_command_ack=BattleCommands047.reply(command,queued,"Command queued for the fleet." if queued else "That command could not be queued.",selected_battle_ids.size() if queued else 0)
		else:
			battle_command_ack = BattleCommands047.apply(battle, selected_battle_ids.duplicate(), command, target)
		if battle_command_ack.ok:battle_command_pending = ""
	ui.toast(str(battle_command_ack.message), not bool(battle_command_ack.ok))
	ui.update_hud()
	return bool(battle_command_ack.ok)

func order_at(position: Vector2):
	if battle.is_empty():
		return
	var target: Dictionary=chart.pick_battle_boat120(position)
	if not battle_command_pending.is_empty():
		if battle_command_pending in ["focus", "escort"]:
			request_battle_command(battle_command_pending, {"shipId":str(target.get("id", ""))})
		else:
			var destination: Vector2 = chart.world_at(position)
			request_battle_command(battle_command_pending, {"x":destination.x,"y":destination.y})
		return
	if not target.is_empty():
		command_selected("attack" if target.team == "enemy" else "escort", {"shipId":str(target.id)})
	else:
		var point = chart.world_at(position)
		command_selected("move", {"x":point.x,"y":point.y})

func refit_boat(uid: String, slot: String, module_id: String, request: Dictionary = {}):
	sync_economy()
	var result = core.refit_boat(uid, slot, module_id, request)
	respond(result)
	if result.ok:
		ui.workshop_drafts.erase(uid)
		save_game(false)
	ui.open_refit(uid)

func workshop_preview(uid: String, loadout: Dictionary, request: Dictionary = {}) -> Dictionary:
	return core.workshop_preview(uid, loadout, request)

func workshop_apply(uid: String,loadout: Dictionary,expected_quote: Dictionary={},request: Dictionary={}):
	sync_economy()
	var before120: int=int(core.state.get("coins",0))
	var result: Dictionary=core.workshop_apply(uid,loadout,expected_quote,request)
	first_voyage120.observe_fit(result,before120,int(core.state.get("coins",0)))
	respond(result)
	if result.ok:
		ui.workshop_drafts.erase(uid)
		if result.get("changed",false):save_game(false)
	ui.open_refit(uid)

func workshop_save_template(uid: String,name: String,loadout: Dictionary) -> Dictionary:
	sync_economy()
	var result: Dictionary=core.workshop_save_template(uid,name,loadout)
	respond(result)
	if result.ok:save_game(false)
	return result

func workshop_delete_template(id: String) -> Dictionary:
	sync_economy()
	var result: Dictionary=core.workshop_delete_template(id)
	respond(result)
	if result.ok:save_game(false)
	return result

func set_crew_policy(policy: String):
	var flagship = Battle.get_flagship(battle)
	if not flagship.is_empty():
		Battle.set_crew_policy(battle,[str(flagship.id)],policy)
	ui.update_hud()

func set_repair_priority(id: String,priority: String) -> bool:
	if mode!="battle" or battle.is_empty():return false
	return Battle.set_repair_priority(battle,[id],priority)

func settle_battle():
	if mode!="battle" or battle.get("result")==null:return
	_retire_battle_driver051()
	fire_held = false
	result_handled=true
	if lab_active:
		LabUI.results(ui)
		return
	if not battle_report.is_empty():
		show_battle_report()
		return
	var report = {"coins": 0, "salvage": {}, "fleetLost": false, "completed": false}
	if not quick_mode:
		var contract120: Dictionary=core.state.get("activeContract",{}).duplicate(true) if str(battle_context.get("kind",""))=="contract" else {}
		var purse120: int=int(core.state.get("coins",0))
		battle_context.objectiveOnly=bool(battle.get("objectiveOnly",false))
		report = core.battle_settled(battle.result,battle_enemies,battle_context,battle)
		if not report.get("ok",true):
			paused=true;result_handled=false;ui.toast(str(report.message),true);return
		first_voyage120.observe_battle_payment(core,contract120,purse120)
	battle_report=report.duplicate(true)
	save_game(false,true)
	show_battle_report()

func show_battle_report():
	if not quick_mode and RecoveryFlow.is_convoy(battle):
		ui.RecoveryUI.outcome(ui,str(battle.result),battle_report)
	else:
		ui.outcome(battle.result,battle_report,battle_enemies)

func open_battle_recovery():
	var ids: Array=RecoveryFlow.wreck_ids(battle_report)
	return_to_campaign()
	ui.RecoveryUI.open(ui,"",ids)

func recover_wreck(id: String,choice: String,good: String="",qty: float=0.0,request: Dictionary={}) -> Dictionary:
	return RecoveryFlow.recover(self,id,choice,good,qty,request)

func take_prize_cargo(uid: String,good: String,qty: float) -> Dictionary:
	if mode!="campaign":return core.fail("Return to the coast before transferring prize cargo.")
	sync_economy()
	var result: Dictionary=core.EscortOps.take_prize_cargo(core,uid,good,qty)
	respond(result)
	if result.get("ok",false):save_game(false)
	return result

func recover_salvage(id: String):
	sync_economy()
	if salvage_claimed:
		ui.toast("This wreck has already been recovered.", true)
		return
	var result = core.salvage_boat(id)
	if result.ok:
		salvage_claimed = true
	respond(result)

func return_to_campaign():
	if mode=="battle" and not quick_mode and not lab_active and battle.get("result")==null:
		ui.toast("Resolve or withdraw from the current battle before returning to the chart.",true);return
	if mode=="battle" and str(battle_context.get("kind",""))=="ocean066" and battle_report.is_empty():ui.toast("Complete physical settlement before returning to the chart.",true);return
	core.travel_lock064=""
	_retire_battle_driver051()
	Tactical.retire_planning051(battle)
	_leave_lab()
	if core.state.is_empty():
		return_to_title()
		return
	tactical_mode = false
	chart.set_tactical(false)
	mode = "campaign"
	chart.center_camera()
	paused = false
	quick_mode = false
	chart.zoom = 1.0
	ui.close_modal()
	ui.build_hud()
	save_game(false)
	if first_voyage120.offer_reinvestment and first_voyage120.enabled:
		first_voyage120.offer_reinvestment=false
		GuidanceUI120.open_first_fit120(ui)

func accept_rescue():
	sync_economy()
	var result = core.rescue()
	if not result.ok:
		respond(result)
		return_to_title()
		return
	return_to_campaign()
	respond(result)

func return_to_title() -> bool:
	var must_save: bool = mode == "campaign" and not core.state.is_empty() and not quick_mode and not lab_active
	if must_save and not save_game(true):
		return false
	_retire_battle_driver051()
	_leave_lab()
	mode = "menu"
	paused = false
	quick_mode = false
	battle = {}
	ui.title_screen()
	return true

func wait_one_day():
	sync_economy()
	core.wait_day()
	start_economy()
	sync_economy()
	ui.open_port()
	save_game(false)

func start_economy():
	if economy_task >= 0 or core.pending_days <= 0:
		return
	var days: int=1
	core.pending_days-=days
	var blocked: Array=core.TradeFlow.blockades(core)
	economy_workers.start(core.state.ports,days,blocked,int(core.state.seed)+int(core.state.econDay)*104729)
	economy_task=0

func _finish_economy(force: bool):
	if economy_task < 0:
		return
	if not force and not economy_workers.ready():
		return
	var completed: Dictionary=economy_workers.finish(force)
	core.apply_economy(completed.ports, completed.events, completed.days)
	economy_task = -1
	economy_job = {}

func sync_economy():
	_finish_economy(true)
	while not core.state.is_empty() and core.pending_days > 0:
		start_economy()
		_finish_economy(true)

func has_save() -> bool:
	return not save_directory.is_empty() and FileAccess.file_exists(save_directory.path_join("voyage.json"))

func save_game(show_notice: bool = true,allow_settled_battle: bool = false) -> bool:
	var settled_battle: bool=allow_settled_battle and mode=="battle" and not lab_active and result_handled and battle.get("result")!=null and not battle_report.is_empty() and bool(battle_report.get("ok",true))
	if (mode != "campaign" and not settled_battle) or core.state.is_empty() or quick_mode:
		if show_notice:
			ui.toast("Return to the campaign chart before saving.", true)
		return false
	sync_economy()
	var error = DirAccess.make_dir_recursive_absolute(save_directory)
	if error != OK:
		if show_notice:
			ui.toast("Cannot save here. Move the portable folder to a writable location.", true)
		return false
	var path = save_directory.path_join("voyage.json")
	var backup_path: String = save_directory.path_join("voyage.backup.json")
	var backup_staged: String = ""
	core.state.version = Version.text()
	var text: String = JSON.stringify(core.state, "\t")
	var staged: String = save_directory.path_join("voyage.save.%s.pending" % text.sha256_text())
	# Verify the complete candidate before touching either existing save file.
	if not _write_verified_save_copy(staged, text.to_utf8_buffer()):
		if show_notice:ui.toast("The new save could not be written and verified. The previous save is unchanged.", true)
		return false
	if FileAccess.file_exists(path):
		var previous = FileAccess.open(path, FileAccess.READ)
		if previous == null:
			if show_notice:ui.toast("Cannot read the previous save. It has not been replaced.", true)
			return false
		var length: int = previous.get_length()
		var bytes: PackedByteArray = previous.get_buffer(length)
		var read_error: int = previous.get_error()
		previous.close()
		if bytes.size() != length or read_error not in [OK, ERR_FILE_EOF]:
			if show_notice:ui.toast("Cannot read the complete previous save. It has not been replaced.", true)
			return false
		backup_staged = save_directory.path_join("voyage.backup.%s.pending" % FileAccess.get_sha256(path))
		if not _write_verified_save_copy(backup_staged, bytes) or not _save_file_matches(path, bytes):
			if show_notice:ui.toast("Cannot write and verify the backup. The previous save is unchanged.", true)
			return false
		if DirAccess.dir_exists_absolute(backup_path):
			if show_notice:ui.toast("Cannot replace the backup. The previous save is unchanged.", true)
			return false
	# Preserve the pre-call fallback until the primary has committed successfully.
	if DirAccess.dir_exists_absolute(path) or _commit_save_file(staged, path) != OK:
		if show_notice:ui.toast("The save file could not be replaced. The previous save is unchanged.", true)
		return false
	if not backup_staged.is_empty() and _commit_save_file(backup_staged, backup_path) != OK:
		if show_notice:ui.toast("Voyage was saved, but its backup could not be updated. Previous saved bytes remain at %s." % backup_staged, true)
		return false
	if show_notice:ui.toast("Voyage saved beside the portable game.")
	return true

func load_game():
	_retire_battle_driver051()
	sync_economy()
	_leave_lab()
	if not has_save():
		ui.toast("No saved voyage yet.", true)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(save_directory.path_join("voyage.json")))
	if not parsed is Dictionary:
		ui.toast("Save is unreadable. Check voyage.backup.json and Guide > Preserved voyages for recovery options.", true)
		return
	if int(data.get("MAP_REVISION",1))>int(parsed.get("mapRevision",1)):
		var source_text=FileAccess.get_file_as_string(save_directory.path_join("voyage.json"))
		var backup_path=save_directory.path_join("voyage.pre-map2.%s.json"%source_text.sha256_text().left(12))
		if not FileAccess.file_exists(backup_path):
			var original=FileAccess.open(backup_path,FileAccess.WRITE)
			if original==null:
				ui.toast("Cannot preserve the original save here. Move the portable folder to a writable location.",true)
				return
			original.store_string(source_text);original.close()
	var result = core.restore(parsed)
	if result.ok:
		first_voyage120.begin(core)
		ui.workshop_drafts.clear()
		ui.voyage_intent065.clear()
		mode = "campaign"
		quick_mode = false
		paused = false
		chart.zoom = 1.0
		chart.center_camera()
		selected_port="";selected_site=""
		ui.close_modal()
		ui.build_hud()
	respond(result)

func quit_game() -> bool:
	var must_save: bool = mode == "campaign" and not core.state.is_empty() and not quick_mode and not lab_active
	if must_save and not save_game(true):
		return false
	_retire_battle_driver051()
	save_preferences()
	sync_economy()
	get_tree().quit()
	return true

func _exit_tree():
	_retire_battle_driver051()
	Tactical.retire_planning051(battle)
	Tactical.drain_planning051()
	if economy_task >= 0:
		economy_workers.finish(true)

func _civilian_capture059(baseline: Dictionary, hull_id: String) -> String:
	# Private layout fixture: finite opening yard shell and capital are declared,
	# then the normal hull, trained crew and stores transactions are fully paid.
	# The independent native fixture proves voyages; these paused views claim no
	# earned income, shipbuilding or paid expedition outcome.
	ui.close_modal()
	core.state = baseline.duplicate(true);core.pending_days = 0;core.events = []
	var dock059: Dictionary = core.current_port()
	dock059.shipStock[hull_id] = int(dock059.shipStock.get(hull_id, 0)) + 1
	if not core.Money.move(core.port("shatter_spire"), "governmentPurse", core.state, "coins", 200000, "Declared civilian059 layout capital", core.state.moneyLog):
		push_error("Civilian059 layout capital refused");return ""
	var uid059: String = "boat-%d" % int(core.state.nextUid)
	if not core.buy_boat(hull_id).ok:
		push_error("Civilian059 layout paid acquisition refused");return ""
	var surplus059: int = maxi(0, floori(float(core.state.cargo.food)) - 3)
	if surplus059 > 0 and not core.trade(str(dock059.id), "food", surplus059, "sell").ok:
		push_error("Civilian059 layout finite food sale refused");return ""
	if not core.sell_boat("boat-1").ok or not core.resupply_boat(uid059, "voyage").ok:
		push_error("Civilian059 layout paid preparation refused");return ""
	core.TradeFlow.observe(core)
	return uid059

func _regional_capture061() -> bool:
	# Private layout fixture only: declared finite capital, actual paid local
	# construction and donations. The native voyage proves earned consequences.
	var port061: Dictionary = core.current_port()
	if not core.Money.move(core.port("shatter_spire"), "governmentPurse", core.state, "coins", 40000, "Declared regional061 layout capital", core.state.moneyLog):
		push_error("Regional061 layout finite capital refused");return false
	var home061: Script = load("res://scripts/home_harbor.gd")
	var established061: Dictionary = home061.establish(core, "warehouse", str(port061.id))
	if not established061.ok:push_error("Regional061 paid layout business refused: " + str(established061.message));return false
	core.state.campaignFocus.fromPort = str(port061.id)
	core.state.campaignFocus.toPort = "kelp_reach"
	core.state.campaignFocus.portId = str(port061.id)
	var begun061: Dictionary = core.RegionalOps.start(core, "corridor")
	if not begun061.ok:push_error("Regional061 layout goal refused: " + str(begun061.message));return false
	core.TradeFlow.observe(core)
	return true

## Existing private capture sequence only. Sail the real Core with its normal
## economy publication; no injected location, cargo, grace or cleared threats.
func _capture_sail064(region_id: String,approach_id: String) -> bool:
	var plotted: Dictionary=core.approach_course064(region_id,approach_id)
	if not plotted.get("ok",false):push_error("Ocean064 capture course: "+str(plotted.message));return false
	for _piece064 in range(160):
		if core.state.path.is_empty():return true
		var length064: float=0.0
		var previous064: Dictionary=core.state.position
		for point064 in core.state.path:length064+=core.distance(previous064,point064);previous064=point064
		var physical_scale064: float=10.0 if core.state.world064.layer=="ocean" else 1.0
		core.step(minf(4.0,maxf(0.001,length064*physical_scale064/maxf(0.01,core.travel_speed()))))
		sync_economy()
		for event064 in core.pop_events():
			if event064.get("kind","") in ["encounter","defeat"]:push_error("Ocean064 capture interrupted by a real encounter/loss");return false
	push_error("Ocean064 capture route did not complete inside the bounded sequence")
	return false

func _capture_cross064(region_id: String,approach_id: String) -> bool:
	var crossed: Dictionary=core.transition064(region_id,approach_id)
	if not crossed.get("ok",false):push_error("Ocean064 capture transfer: "+str(crossed.message));return false
	selected_port="";selected_site="";ui.close_modal();ui.build_hud();chart.center_camera();chart.territory_view()
	return true

func _voyage_capture065() -> bool:
	# Controlled paused layout only: one seeded career and declared capital
	# moved from an existing treasury, then real hull/crew/conversion/store bills.
	# This composition is not an earned voyage or a successful transfer claim.
	new_game(65065);paused=true
	# Same INITIAL budget as the actual fixture:15000+80000 covers setup48389,
	# stores<=30000 and ten925-coin payroll boundaries, with7361 left over.
	var fixture_capital: int=80000
	var treasury: Dictionary=core.port("shatter_spire")
	var treasury_before: int=int(treasury.get("governmentPurse",0))
	var captain_before: int=int(core.state.coins)
	var capital_total: int=core.Money.total(core.state)
	if treasury_before<fixture_capital:
		push_error("Voyage065 layout treasury cannot fund the declared initial80000 transfer");return false
	if not core.Money.move(treasury,"governmentPurse",core.state,"coins",fixture_capital,"Declared voyage065 layout capital",core.state.moneyLog):
		push_error("Voyage065 layout capital refused");return false
	if treasury_before-int(treasury.governmentPurse)!=fixture_capital or int(core.state.coins)-captain_before!=fixture_capital or core.Money.total(core.state)!=capital_total:
		push_error("Voyage065 initial layout capital did not conserve treasury/captain/world coins");return false
	var source_uid: String=str(core.state.fleet[0].uid)
	var target_uid: String="boat-%d"%int(core.state.nextUid)
	var bought: Dictionary=core.buy_boat("tin_skiff")
	if not bought.get("ok",false):push_error("Voyage065 paid layout hull: "+str(bought.get("message","")));return false
	var converted: Dictionary=core.FleetIdentity.install_conversion(core,source_uid,"auxiliary_tanks")
	if not converted.get("ok",false):push_error("Voyage065 paid layout conversion: "+str(converted.get("message","")));return false
	var store_results: Array=[]
	var stores_ok: bool=true
	for loadout in [{"uid":source_uid,"profile":"full"},{"uid":target_uid,"profile":"voyage"}]:
		var boat: Dictionary=core.find_boat(loadout.uid)
		var harbor: Dictionary=core.current_port()
		var prior_boat: Dictionary=boat.duplicate(true)
		var prior_harbor: Dictionary=harbor.duplicate(true)
		var prior_coins: int=int(core.state.coins)
		var prior_total: int=core.Money.total(core.state)
		var targets: Dictionary={"ammo":maxf(80.0,float(boat.spec.get("ammoCapacity",80*maxi(1,boat.spec.get("weaponMounts",[]).size())))),"fuel":3.0 if loadout.profile=="voyage" else float(boat.spec.get("fuelCapacity",60)),"supplies":6.0 if loadout.profile=="voyage" else 20.0}
		var result: Dictionary=core.resupply_boat(loadout.uid,loadout.profile)
		var ready_before: bool=true
		var ready_after: bool=true
		var conserved: bool=true
		var invoice: int=0
		for good in targets:
			var conversion: float=float(core.Goods.ROUNDS_PER_CASE) if good=="ammo" else 1.0
			var loaded: float=float(boat[good])-float(prior_boat[good])
			var used: float=float(prior_harbor.stocks[good])-float(harbor.stocks[good])
			ready_before=ready_before and float(prior_boat[good])>=float(targets[good])-0.000000001
			ready_after=ready_after and float(boat[good])>=float(targets[good])-0.000000001
			conserved=conserved and loaded>=0.0 and used>=0.0 and float(harbor.stocks[good])>=0.0 and absf(loaded-used*conversion)<0.000000001 and loaded<=maxf(0.0,float(targets[good])-float(prior_boat[good]))+0.000000001
			invoice+=ceili(used*Economy.price(prior_harbor,good)-0.000001)
		var paid: bool=prior_coins-int(core.state.coins)==invoice and int(harbor.cash)-int(prior_harbor.cash)==invoice and core.Money.total(core.state)==prior_total
		store_results.append({"uid":loadout.uid,"profile":loadout.profile,"result":result,"targets":targets,"readyBefore":ready_before,"readyAfter":ready_after,"stockConserved":conserved,"invoicePaid":paid,"beforeStores":{"ammo":prior_boat.ammo,"fuel":prior_boat.fuel,"supplies":prior_boat.supplies},"afterStores":{"ammo":boat.ammo,"fuel":boat.fuel,"supplies":boat.supplies},"beforeStock":prior_harbor.stocks,"afterStock":harbor.stocks.duplicate(true),"beforeCoins":prior_coins,"afterCoins":core.state.coins,"invoice":invoice})
		stores_ok=ready_after and conserved and paid and (result.get("ok",false) or (ready_before and invoice==0)) and stores_ok
	if not stores_ok:push_error("Voyage065 paid layout stores: "+JSON.stringify(store_results));return false
	ui.voyage_intent065={"targetRegionId":"glasswind_keys","targetApproachId":"south","outExit":"north","backExit":"south","homeEntry":"north","returnPortId":"brass_haven","idleDays":0.25}
	ui.open_voyage_preparation065()
	print("QA voyage065 controlled paused preparation/transfer layout; paid travel and conservation are separate native checks")
	return true

func capture_after_start():
	await get_tree().create_timer(2.0).timeout
	var path: String = OS.get_environment("GAME_TEST_ARTIFACTS")
	if not path.is_absolute_path():
		path = ProjectSettings.globalize_path("res://../qa")
	DirAccess.make_dir_recursive_absolute(path)
	var views: Array = screenshots_requested.duplicate()
	var traffic_origin055: Dictionary = {}
	var recovery_wreck058: String = ""
	var recovery_carrier058: String = ""
	var recovery_parts058: Array = []
	var civilian_baseline059: Dictionary = {}
	var crew_carrier060: String = ""
	if views.is_empty():views = [mode]
	for raw in views:
		var name: String = str(raw)
		if name.ends_with("051") and not screenshots_requested.is_empty():
			if name == "ocean064051":
				new_game(64064);paused=true
				if not _capture_sail064("shatter_coast","north") or not _capture_cross064("shatter_coast","north"):return
			elif name == "glasswind064051":
				if not _capture_sail064("glasswind_keys","south") or not _capture_cross064("glasswind_keys","south"):return
			elif name == "home-return064051":
				if not _capture_cross064("glasswind_keys","south"):return
				if not _capture_sail064("shatter_coast","north") or not _capture_cross064("shatter_coast","north"):return
			elif name == "preparation065051":
				if not _voyage_capture065():return
				await get_tree().process_frame
				for scroll065 in ui.overlay.find_children("*","ScrollContainer",true,false):scroll065.scroll_vertical=0
			elif name == "transfer065051":
				ui.open_voyage_preparation065()
				await get_tree().process_frame
				for scroll065 in ui.overlay.find_children("*","ScrollContainer",true,false):scroll065.scroll_vertical=100000
			elif name == "ocean-travel066051":
				# Declared paused layout, not an earned voyage/contact or battle.
				# Same existing owner/boats/accounts; only chart positions are staged.
				new_game(66066);paused=true;ui.close_modal()
				var loc066: Dictionary={"world064":{"schema":1,"layer":"ocean","regionId":"open_ocean"},"position":{"x":1300.0,"y":1130.0},"heading":0.0,"path":[{"x":1600.0,"y":1130.0}],"destination":""}
				core._publish_location064(loc066)
				var foe066: Dictionary=core.fleet_owner("patrol-0")
				var npc066: Dictionary=loc066.duplicate(true);npc066["position"]={"x":1340.0,"y":1130.0};npc066["path"]=[]
				core.state.ocean066["contact"]={"ownerId":"patrol-0","phase":"patrol","location":npc066,"gate":{"regionId":"shatter_coast","approachId":"north"},"waypoint":{"x":1300.0,"y":1130.0}}
				foe066["atPort"]="";foe066.erase("harborServiceUntilDay")
				var projection066: Dictionary=core.NavalAI._find_patrol(core.state,"patrol-0")
				projection066["active"]=false;projection066["hidden"]=true;projection066["holding"]=true;projection066["course"]=[];projection066["courseLength"]=0.0;projection066["progress"]=0.0
				var staged066: Dictionary=core.OceanCampaign066.stage(core,0.0)
				if not staged066.get("ok",false):push_error(str(staged066.message));return
				core.OceanCampaign066.commit(core,staged066)
				chart.center_camera();ui.build_hud()
				ui.toast("Declared chart layout: weather, a dated existing-fleet sighting and voyage controls; no earned voyage claimed.")
			elif name == "home051":
				new_game(59059);paused = true;chart.center_camera()
				civilian_baseline059 = core.state.duplicate(true)
			elif name == "regional061051":
				if not _regional_capture061():return
				ui.RegionalUI.open(ui, "corridor")
			elif name == "watch061051":
				# Explicitly controlled completed-watch layout, not earned clear
				# days or a real patrol reassignment. No funding or actor is created.
				var watch061: Dictionary = core.state.regionalCampaigns.operations.corridor
				watch061.status = "complete";watch061.watchState = "awaiting"
				watch061.ownerId = "patrol-2"
				ui.RegionalUI.open(ui, "corridor")
				await get_tree().process_frame
				for scroll061 in ui.overlay.find_children("*", "ScrollContainer", true, false):scroll061.scroll_vertical = 0
			elif name == "homebook061051":
				ui.HomeUI.open(ui)
				await get_tree().process_frame
				for scroll061 in ui.overlay.find_children("*", "ScrollContainer", true, false):scroll061.scroll_vertical = 0
			elif name == "harbor061051":
				var harbor061: Dictionary = core.RegionalOps.start(core, "harbor")
				if not harbor061.ok or not core.trade(str(core.current_port().id), "timber", 6, "buy").ok or not core.RegionalOps.contribute(core, "harbor", "timber", 6).ok:
					push_error("Regional061 paid layout donation refused");return
				ui.RegionalUI.open(ui, "harbor")
			elif name == "crew060051":
				# Real affordable starter hires, with ordinary finite port labor,
				# advances and berths. No opening capital or specialist is granted.
				crew_carrier060 = str(core.state.fleet[0].uid)
				for role060 in ["pilot", "gunner"]:
					var hired060: Dictionary = core.FleetIdentity.hire_specialist(core, crew_carrier060, role060)
					if not hired060.ok:push_error("Crew060 paid layout hire refused: " + str(hired060.message));return
				if not core.FleetIdentity.set_command_preference(core, crew_carrier060, "cautious", "skirmisher").ok:
					push_error("Crew060 layout intent refused");return
				core.apply_morale();core.Manifest.allocate(core.state)
				ui.IdentityUI.open(ui, crew_carrier060)
			elif name == "crewcare060051":
				ui.IdentityUI.open(ui, crew_carrier060)
				await get_tree().process_frame
				for scroll060 in ui.overlay.find_children("*", "ScrollContainer", true, false):scroll060.scroll_vertical = 100000
			elif name == "training060051":
				ui.EconomicUI.open(ui)
			elif name == "loss060051":
				# Declared controlled UI loss, not an earned combat outcome. Real
				# canonical owners enter the public physical settlement path; native
				# proof and motion review establish behavior separately.
				var foe060: Dictionary = core.fleet_owner("patrol-0")
				battle = Battle.create({"fleet":core.active_fleet(), "enemyFleet":foe060.boats, "seed":60060, "islands":[]})
				var lost060: Dictionary = core.find_boat(crew_carrier060)
				lost060.hp = 0.0;lost060.sunk = true;lost060.crew = 0.0;lost060.wounded = 0.0
				battle.result = "lost"
				var enemies060: Array = foe060.boats.map(func(boat060):return boat060.spec)
				battle_report = core.battle_settled("lost", enemies060, {"kind":"patrol", "ownerId":"patrol-0"}, battle)
				if not battle_report.has("participants"):push_error("Crew060 controlled layout settlement refused");return
				ui.outcome("lost", battle_report, enemies060)
			elif name in ["freight059051", "fishing059051", "charter059051"]:
				var role059: String = "kelpnet_dory" if name == "fishing059051" else ("gullwing_daysailer" if name == "charter059051" else "fenhopper_lighter")
				var carrier059: String = _civilian_capture059(civilian_baseline059, role059)
				if carrier059.is_empty():return
				if name == "fishing059051":
					# Only the layout's position is staged at real nearby water. No
					# catch, survey knowledge, buyer demand or elapsed work is granted.
					var home059: Dictionary = core.current_port()
					var water059: bool = false
					for delta059 in [Vector2(220, 0), Vector2(-220, 0), Vector2(0, 220), Vector2(0, -220)]:
						var point059: Dictionary = {"x":float(home059.x) + delta059.x, "y":float(home059.y) + delta059.y}
						if core.Navigation.is_water(core.nav, point059.x, point059.y, maxf(10, float(core.find_boat(carrier059).spec.size))):
							core.state.position = point059;water059 = true;break
					if not water059:push_error("Civilian059 layout water missing");return
					ui.VoyageUI.review_fishing(ui, carrier059, 0.5, int(core.find_boat(carrier059).crew), "brass_haven")
				else:
					var offer059: Dictionary = {}
					var kind059: String = core.VoyageJobs.KIND_CHARTER if name == "charter059051" else core.VoyageJobs.KIND_FREIGHT
					for job059: Dictionary in core.VoyageJobs.available(core):
						if str(job059.kind) == kind059:offer059 = job059;break
					if offer059.is_empty():push_error("Civilian059 layout funded offer missing");return
					ui.VoyageUI.review_job(ui, offer059, carrier059)
			elif name == "recovery058051":
				# Declared isolated UI fixture, not earned combat: damage and retire
				# one existing NPC, using the real condition and wreck custody APIs.
				core.stop_sailing();recovery_carrier058 = str(core.state.fleet[0].uid)
				var source058: Dictionary = {}
				for actor058: Dictionary in core.fleet_owner("patrol-2").get("boats", []):
					if str(actor058.get("type", "")) == "bilge_punt" and not actor058.get("sunk", false):source058 = actor058;break
				if source058.is_empty():push_error("Recovery058 layout source missing");return
				for item058: Dictionary in source058.get("moduleCondition", {}).get("items", {}).values():
					if str(item058.get("location", "")) in ["mount0", "engine"]:
						var damaged058: Dictionary = core.Preflight.Core.apply_component_damage(source058.moduleCondition, {"itemUid":str(item058.itemUid), "loss":0.375 if str(item058.location) == "mount0" else 0.125, "cause":"Declared recovery058 UI fixture"})
						if not damaged058.ok:push_error("Recovery058 fixture damage refused");return
						recovery_parts058.append(str(item058.itemUid))
				if not core.Preflight.Records.publish(source058).ok:push_error("Recovery058 fixture projection refused");return
				source058.team = "enemy";source058.sunk = true;source058.hp = 0.0
				var wrecks058: Array = core.Salvage.record_battle(core, {"ships":[source058], "chartPosition":core.state.position}, "recovery058-declared-layout")
				if wrecks058.size() != 1:push_error("Recovery058 layout custody refused");return
				recovery_wreck058 = str(wrecks058[0].id)
				ui.RecoveryUI.open(ui, recovery_wreck058)
			elif name == "gear058051":
				ui.RecoveryUI.gear(ui, recovery_wreck058, recovery_parts058, recovery_carrier058)
				await get_tree().process_frame
				# Inspect the actual disclosed losses, carrying and final action;
				# local scroll only, with no input/focus/computer control.
				for scroll058 in ui.overlay.find_children("*", "ScrollContainer", true, false):scroll058.scroll_vertical = 100000
			elif name == "prize058051":
				# Re-label the existing owned starter for this empty-prize panel;
				# no free hull, boarding victory or earned capture is claimed.
				var owned058: Dictionary = core.find_boat(recovery_carrier058)
				owned058.captureSecured = true;owned058.convoyCargo = {};owned058.supportOnly = true
				ui.RecoveryUI.owned_prize(ui, recovery_carrier058)
			elif name in ["convoy051", "hostile051", "civilian051"]:
				ui.close_modal()
				var chosen054: Dictionary = {}
				for patrol054: Dictionary in core.state.patrols:
					if not patrol054.get("active", false):continue
					var owner054: Dictionary = core.fleet_owner(str(patrol054.id))
					var match054: bool = bool(patrol054.get("hostile", false)) if name == "hostile051" else str(owner054.get("kind", "")) == "trader"
					if name == "civilian051":
						match054 = owner054.get("boats", []).any(func(b):return str(b.get("spec", {}).get("civilianRole", "")) in ["fishing", "transport", "tanker", "yacht"])
					if match054:chosen054 = patrol054;break
				if chosen054.is_empty():
					for patrol054: Dictionary in core.state.patrols:
						if patrol054.get("active", false):chosen054 = patrol054;break
				if not chosen054.is_empty():
					chart.follow_camera = false;chart._campaign_follow = false
					chart.camera = Vector2(float(chosen054.x), float(chosen054.y))
					chart.scale_factor = chart.regional_scale()
			elif name == "trafficcurrent051":
				# Isolated layout fixture: use an existing distant carrier's water
				# position to sample a genuine local contact, without creating boats.
				traffic_origin055 = core.state.position.duplicate(true)
				var contact055: Dictionary = {}
				var farthest055: float = 1800.0
				for patrol055: Dictionary in core.state.patrols:
					if not patrol055.get("active", false) or patrol055.get("hidden", false):continue
					var owner055: Dictionary = core.fleet_owner(str(patrol055.id))
					var distance055: float = core.distance(core.state.position, patrol055)
					if str(owner055.get("kind", "")) == "trader" and distance055 > farthest055:
						contact055 = patrol055;farthest055 = distance055
				if not contact055.is_empty():core.state.position = {"x":float(contact055.x),"y":float(contact055.y)}
				ui.NavalUI.open(ui)
			elif name == "trafficold051":
				if not traffic_origin055.is_empty():core.state.position = traffic_origin055
				core.step(0.5)
				ui.NavalUI.open(ui)
			elif name == "discovery051":
				var knowledge054: Dictionary = core.state.get("exploration", {})
				for site054: Dictionary in knowledge054.get("catalog", []):
					if int(knowledge054.get("sites", {}).get(site054.id, {}).get("level", 0)) <= 0:continue
					selected_site = str(site054.id)
					chart.follow_camera = false;chart._campaign_follow = false
					chart.camera = Vector2(float(site054.x), float(site054.y))
					chart.scale_factor = chart.regional_scale()
					break
			elif name == "overview051":chart.territory_view()
			elif name == "factions051":ui.FactionUI.open(ui)
			elif name == "commission051":
				# Isolated terms-layout fixture; native cases verify earned standing
				# and explicit consent separately. No commission is signed here.
				core.Factions.adjust(core.state, "compact", 20, "QA terms layout: friendly standing")
				ui.FactionUI.terms(ui, "compact")
			elif name == "contactwork051":
				# Exercise actual escrow and settlement; only the completed survey
				# condition is staged for this isolated UI capture, not a long voyage.
				for offer056: Dictionary in core.VoyageJobs.available(core):
					if str(offer056.kind) != "survey":continue
					if core.accept_voyage_job(str(offer056.id)).ok:
						core.state.exploration.sites[str(offer056.siteId)].level = 3
						core.settle_voyage_job(str(offer056.id))
					break
				ui.VoyageUI.open(ui)
			elif name == "encounter051":
				var patrol056: Dictionary = core.NavalAI._find_patrol(core.state, "patrol-2")
				if not patrol056.is_empty():
					core.state.position = {"x":float(patrol056.x), "y":float(patrol056.y)}
					show_patrol_encounter("patrol-2")
			elif name == "storylead051":
				core.stop_sailing()
				core.state.position = core.port_position("reed_floats")
				core.state.lastPort = "reed_floats"
				core.Contacts.visit(core.state, core.current_port(), core.state.day)
				core.StoryOps.start(core, "middle_sea_chart")
				ui.StoryUI.open(ui)
			elif name == "islandprep051":
				selected_site = "middle_chart_rock";selected_port = ""
				Interface.CampaignUI.expedition(ui)
			elif name == "storypayoff051":
				# Isolated layout fixture only: actual native057 voyage proof uses
				# paid shore assignments. Here survey levels are explicitly staged
				# before the real choices/finite wreck/rights UI are exercised.
				core.state.exploration.sites["middle_chart_rock"].level = 2
				core.StoryOps.choose(core, "middle_sea_chart", "share_chart")
				core.state.exploration.sites["shatter_wreck_field"].level = 3
				core.Salvage.seed_site_wreck(core, core.Exploration.catalog_site(core.state, "shatter_wreck_field"), "harbor_sloop")
				core.StoryOps.choose(core, "middle_sea_chart", "mark_field")
				core.StoryOps.choose(core, "middle_sea_chart", "open_field")
				ui.StoryUI.open(ui)
			elif name == "voyage051":Interface.GuidanceUI.open_voyage(ui)
			elif name == "harbor051":ui.open_port()
			elif name == "preparation051":
				for destination052 in data.PORTS:
					if str(destination052.id)!=str(core.current_port().get("id","")):
						selected_port=str(destination052.id)
						break
				Interface.CampaignUI.expedition(ui)
			elif name == "market051":ui.open_port("Market")
			elif name == "tradeempty051":Interface.TradeUI.open(ui)
			elif name == "trade051":
				# Isolated capture profile: record one real destination's visit quote.
				# Restore the paused captain before opening the normal trade screen.
				var origin053: Dictionary = core.state.position.duplicate(true)
				core.state.position = core.port_position(selected_port)
				core.TradeFlow.observe(core)
				core.state.position = origin053
				Interface.TradeUI.open(ui)
			elif name == "tradedetails051":
				for button053 in ui.overlay.find_children("*", "Button", true, false):
					if button053 is Button and str(button053.text).begins_with("Costs, price uncertainty & quantity limits"):
						button053.pressed.emit()
						break
			# Private layout branches can replace their paused state directly;
			# publish the current HUD before the same frame is captured.
			ui.update_hud()
			await get_tree().process_frame
			name = "opening051-" + name.trim_suffix("051")
		elif not screenshots_requested.is_empty():
			if name == "home":chart.center_camera()
			elif name == "overview":chart.territory_view()
			else:
				var port: Dictionary = core.port(name)
				if port.is_empty():push_error("Unknown requested coastal view");return
				selected_port = name
				chart.follow_camera = false;chart._campaign_follow = false
				chart.camera = Vector2(port.x,port.y);chart.zoom = 1.7
			chart.step(0.0);ui.update_hud()
			await get_tree().process_frame
			name = "coast050-" + name
		await RenderingServer.frame_post_draw
		var image = get_viewport().get_texture().get_image()
		image.save_png(path.path_join(name + ".png"))
		print("QA_CAPTURE ", path.path_join(name + ".png"))
	screenshots_requested.clear()
