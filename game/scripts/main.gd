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

func _ready():
	if "--qa-runtime043" in OS.get_cmdline_user_args():
		runtime_profile043=RuntimeProfile043.new()
		if not runtime_profile043.prepare(self):
			get_tree().quit(2)
			return
		preferences_path=runtime_profile043.preferences_path
	else:
		preferences_path=ProjectSettings.globalize_path("res://../settings.json") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("settings.json")
		if DisplayServer.get_name()=="headless":preferences_path=OS.get_user_data_dir().path_join("qa-settings.json")
	var options: Dictionary=Preferences.load_options(preferences_path) if runtime_profile043==null else runtime_profile043.options()
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
			if FleetLab.presets().has(preset):
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
		screenshots_requested = ["title051", "home051", "voyage051", "harbor051"]
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
	var running: bool=mode=="battle" and not result_handled and not paused and not ui.modal_open
	if mode=="campaign" and not core.state.is_empty():running=not core.state.path.is_empty() and not paused and not ui.modal_open
	audio.set_engine(running,0.65)
	music.set_context(music_context())
	hud_timer += dt
	if hud_timer >= 0.15:
		hud_timer = 0.0
		ui.update_hud()
	if mode == "campaign":
		save_timer += dt
		if save_timer > 20 and not ui.modal_open:
			save_timer = 0
			save_game(false)
	if runtime_profile043!=null:runtime_profile043.after_process(dt)

func _physics_process(dt: float):
	if paused or ui == null or ui.modal_open:
		return
	if mode == "campaign":
		# Publish the worker's port snapshot before NPC arrivals can trade with these purses.
		_finish_economy(false)
		if economy_task>=0:return # Await copied port jobs without stalling a frame or trading stale purses.
		core.step(dt * speed)
		for event in core.pop_events():
			match event.kind:
				"arrival":
					core.StoryOps.refresh(core)
					selected_port = event.port
					ui.toast("Arrived at %s. Enter harbor to trade, recruit, and refit." % core.port(event.port).name)
					audio.play("bell")
				"defeat":
					paused = true
					var body = ui.modal("A skiff, a second chance", "HARBOR RESCUE", 700, 500)
					ui.paragraph(body, "Brass Haven can fund a replacement and crew from its treasury. The actual cost becomes a loan owed to the harbor.", 19)
					ui.button(body, "Accept harbor rescue", accept_rescue, true)
				"encounter":
					show_patrol_encounter(event.patrol)
				"survey_complete":ui.toast("%s: %s"%[event.siteName,event.levelName])
	# Battle numerical work belongs to the driver; rendering polls it in _process.

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
				if ui.modal_kind == "outcome":
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
			KEY_K: ui.VoyageUI.open(ui) if mode=="campaign" else null
			KEY_L: ui.RegionalUI.open(ui) if mode=="campaign" else null
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

func new_game():
	_retire_battle_driver051()
	_leave_lab()
	sync_economy()
	var begun: Dictionary = core.new_game(int(Time.get_unix_time_from_system()))
	if not begun.get("ok", false):
		ui.toast(str(begun.get("message", "New career was refused. The previous voyage is unchanged.")), true)
		return
	ui.workshop_drafts.clear()
	mode = "campaign"
	quick_mode = false
	paused = false
	chart.zoom = 1.0
	chart.center_camera()
	selected_port = data.START.port
	ui.close_modal()
	ui.build_hud()
	ui.toast("Welcome to Brass Haven. Enter harbor and accept your first contract.")
	save_game(false)

func click_chart(position: Vector2):
	var nearest: Dictionary = {}
	var nearest_distance = 45.0
	for p in core.state.ports:
		var d = chart.project(Vector2(p.x, p.y)).distance_to(position)
		if d < nearest_distance:
			nearest = p
			nearest_distance = d
	if not nearest.is_empty():
		selected_port = nearest.id
		var current = core.current_port()
		if not current.is_empty() and current.id == nearest.id:
			ui.open_port()
		else:
			sail_to(nearest.id)
		return
	for site in core.Exploration.sites(core.state):
		if site.level>0 and chart.project(Vector2(site.x,site.y)).distance_to(position)<22:
			selected_site=site.id
			ui.CampaignUI.site(ui,site.id)
			return
	for patrol in core.state.patrols:
		if patrol.active and chart.project(Vector2(patrol.x, patrol.y)).distance_to(position) < 15:
			show_patrol_encounter(patrol.id)
			return
	for w in core.state.get("wrecks",[]):
		if w.get("status","")=="unclaimed" and chart.project(Vector2(w.x,w.y)).distance_to(position)<16:
			ui.RecoveryUI.open(ui,w.id)
			return
	var world = chart.world_at(position)
	respond(core.chart_course({"x": world.x, "y": world.y}))

func sail_to(id: String):
	var p = core.port(id)
	if p.is_empty():
		return
	core.use_reserves()
	respond(core.chart_course({"x": p.x, "y": p.y}, id))
	selected_port = id

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
		respond(core.finish_contract())
		ui.close_modal()
		ui.build_hud()
		save_game(false)
	else:
		var specs: Array = []
		for id in contract.enemyHulls:
			specs.append(core.hull(id))
		begin_battle(specs, {"kind": "contract", "id": contract.id, "ownerId":contract.get("ownerId",""), "name": "%s approaches" % core.port(contract.targetPort).name})

func show_patrol_encounter(id: String):
	var patrol: Dictionary = {}
	for p in core.state.patrols:
		if p.id == id:
			patrol = p
	if patrol.is_empty():
		return
	var body = ui.modal(patrol.name, "CONTACT ON THE COAST", 700, 550)
	ui.modal_kind = "encounter"
	var observed: Dictionary=core.fleet_owner(id)
	if not observed.is_empty():ui.paragraph(body,str(observed.get("reason","")),15,ui.GOLD)
	var owner: Dictionary=core.fleet_owner(id)
	patrol.hostile=core.Politics.hostile(core,owner)
	if not owner.is_empty() and core.distance(core.state.position,patrol)<=1800.0 and owner.boats.any(func(b):return not b.sunk):
		core.Contacts.record_captain(core.state,id,"hail:%s:%d"%[id,int(core.state.day)],"Exchanged signals on the coastal route.")
		var captain: Dictionary=core.Contacts._find(core.state,"captain:"+id)
		if not captain.is_empty():
			ui.label(body,str(captain.name),21,ui.GOLD,true)
			for memory in captain.log.slice(-2):ui.paragraph(body,str(memory.get("detail",memory.event)),14)
	var loaded: bool=owner.get("kind","")=="trader" and float(owner.get("tradeCargo",0))>0
	if not patrol.hostile:
		ui.paragraph(body, "A coastal merchant convoy sails this route. It carries goods between the same ports that supply your fleet. Its crews signal a peaceful passage.", 19)
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
	ui.paragraph(body, "Raider engines echo across the water. You can engage their boats or give them a wide berth. Their strength is %d boat(s)." % patrol.strength, 19)
	ui.button(body, "Engage the raiders", func(): engage_patrol(patrol), true)
	ui.button(body, "Avoid contact", func(): core.state.encounterGrace = 90.0; ui.close_modal())

func engage_patrol(patrol: Dictionary):
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
	if context.get("encounterPosition") is Dictionary and context.encounterPosition.has("x") and context.encounterPosition.has("y"):
		return context.encounterPosition.duplicate(true)
	var contact_id: String=str(context.get("allyOwnerId","") if context.get("kind","")=="escort" else context.get("ownerId","") if context.get("kind","")=="patrol" else "")
	for patrol in core.state.patrols:
		if str(patrol.id)==contact_id:return {"x":float(patrol.x),"y":float(patrol.y)}
	return core.state.position.duplicate(true)

func begin_battle(specs: Array, context: Dictionary):
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
	var player_fleet: Array=core.FleetSupport.combat(core)
	if context.get("kind","")=="escort":
		var ally_owner: Dictionary=core.fleet_owner(str(context.get("allyOwnerId","")))
		player_fleet=ally_owner.get("boats",[]).filter(func(b):return not b.sunk and b.crew>=b.crewMin)+player_fleet
	for boat in player_fleet:boat.supportRepairFactor=1.0
	var options: Dictionary=CoastalTerrain.arena(data,encounter_position(context))
	options.merge({"fleet":player_fleet,"mission":context.get("mission",{}),"enemySpecs":specs,"enemyFleet":enemy_fleet,"seed":int(core.state.seed)+core.state.wins*17+core.state.losses*5})
	battle = Battle.create(options)
	if not str(battle.get("startError","")).is_empty():
		ui.toast(str(battle.startError),true)
		battle={}
		return
	battle_context.mission=battle.mission.duplicate(true)
	battle.captureSlots=maxi(0,64-core.state.get("boardingPrizes",[]).size())
	core.BoardingOps.coastal(core,battle)
	_enter_battle()

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

func start_lab(prepare051: Callable=Callable()):
	sync_economy()
	if lab_config.is_empty():lab_config=FleetLab.preset(data,"mixed")
	var built: Dictionary=FleetLab.create(data,lab_config,lab_seed)
	if not built.ok:
		ui.toast(built.error,true)
		return
	if career_core==null:career_core=core
	core=Campaign.new(data)
	# HUD-only laboratory state: never initialize a career economy or read a save.
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
	paused = false
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
	chart.zoom = 1.4 if battle.ships.size() <= 8 else 1.0
	chart.set_tactical(false)
	chart.center_camera()
	ui.close_modal()
	ui.build_hud()
	ui.toast("Autopilot engaged. WASD camera · Space pause · select boats, right-click orders · Tab tactical view.")
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
		var nearest = ""
		var distance = 42.0
		for boat in battle.ships:
			if boat.team == "player" and not boat.sunk and not boat.get("captureSecured",false):
				var d = chart.project(chart.battle_boat_position051(boat)).distance_to(position)
				if d < distance:
					distance = d
					nearest = str(boat.id)
		if not nearest.is_empty():
			select_battle_boat(nearest, additive)
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
	var target: Dictionary = {}
	var closest = 42.0
	for boat in battle.ships:
		if boat.sunk or boat.get("captureSecured",false):
			continue
		var distance = chart.project(chart.battle_boat_position051(boat)).distance_to(position)
		if distance < closest:
			closest = distance
			target = boat
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
	var result: Dictionary=core.workshop_apply(uid,loadout,expected_quote,request)
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
		battle_context.objectiveOnly=bool(battle.get("objectiveOnly",false))
		report = core.battle_settled(battle.result,battle_enemies,battle_context,battle)
		if not report.get("ok",true):
			paused=true;result_handled=false;ui.toast(str(report.message),true);return
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

func recover_wreck(id: String,choice: String,good: String="",qty: float=0.0) -> Dictionary:
	return RecoveryFlow.recover(self,id,choice,good,qty)

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

func accept_rescue():
	sync_economy()
	var result = core.rescue()
	if not result.ok:
		respond(result)
		return_to_title()
		return
	return_to_campaign()
	respond(result)

func return_to_title():
	_retire_battle_driver051()
	if mode == "campaign":
		save_game(false)
	_leave_lab()
	mode = "menu"
	paused = false
	quick_mode = false
	battle = {}
	ui.title_screen()

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

func save_game(show_notice: bool = true,allow_settled_battle: bool = false):
	var settled_battle: bool=allow_settled_battle and mode=="battle" and not lab_active and result_handled and battle.get("result")!=null and not battle_report.is_empty() and bool(battle_report.get("ok",true))
	if (mode != "campaign" and not settled_battle) or core.state.is_empty() or quick_mode:
		if show_notice:
			ui.toast("Return to the campaign chart before saving.", true)
		return
	sync_economy()
	var error = DirAccess.make_dir_recursive_absolute(save_directory)
	if error != OK:
		if show_notice:
			ui.toast("Cannot save here. Move the portable folder to a writable location.", true)
		return
	var path = save_directory.path_join("voyage.json")
	if FileAccess.file_exists(path):
		var backup = FileAccess.open(save_directory.path_join("voyage.backup.json"), FileAccess.WRITE)
		if backup:
			backup.store_string(FileAccess.get_file_as_string(path))
			backup.close()
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		core.state.version = Version.text()
		file.store_string(JSON.stringify(core.state, "\t"))
		file.close()
		if show_notice:
			ui.toast("Voyage saved beside the portable game.")
	elif show_notice:
		ui.toast("The save file could not be written.", true)

func load_game():
	_retire_battle_driver051()
	sync_economy()
	_leave_lab()
	if not has_save():
		ui.toast("No saved voyage yet.", true)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(save_directory.path_join("voyage.json")))
	if not parsed is Dictionary:
		ui.toast("Save is unreadable. Your backup is in the saves folder.", true)
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
		ui.workshop_drafts.clear()
		mode = "campaign"
		quick_mode = false
		paused = false
		chart.zoom = 1.0
		chart.center_camera()
		ui.close_modal()
		ui.build_hud()
	respond(result)

func quit_game():
	_retire_battle_driver051()
	save_preferences()
	save_game(false)
	sync_economy()
	get_tree().quit()

func _exit_tree():
	_retire_battle_driver051()
	Tactical.retire_planning051(battle)
	Tactical.drain_planning051()
	if economy_task >= 0:
		economy_workers.finish(true)

func capture_after_start():
	await get_tree().create_timer(2.0).timeout
	var path: String = OS.get_environment("GAME_TEST_ARTIFACTS")
	if not path.is_absolute_path():
		path = ProjectSettings.globalize_path("res://../qa")
	DirAccess.make_dir_recursive_absolute(path)
	var views: Array = screenshots_requested.duplicate()
	if views.is_empty():views = [mode]
	for raw in views:
		var name: String = str(raw)
		if name.ends_with("051") and not screenshots_requested.is_empty():
			if name == "home051":
				new_game();paused = true;chart.center_camera()
			elif name == "voyage051":Interface.GuidanceUI.open_voyage(ui)
			elif name == "harbor051":ui.open_port()
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
