extends Node2D

const Damage = preload("res://scripts/damage.gd")
const Battle = preload("res://scripts/battle.gd")
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
var battle: Dictionary = {}
var battle_context: Dictionary = {}
var battle_enemies: Array = []
var quick_mode = false
var fire_held = false
var auto_gunners = true
var tactical_mode = false
var pre_tactical_paused = false
var selected_battle_ids: Array = []
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

func _ready():
	preferences_path=ProjectSettings.globalize_path("res://../settings.json") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("settings.json")
	if DisplayServer.get_name()=="headless":preferences_path=OS.get_user_data_dir().path_join("qa-settings.json")
	var options: Dictionary=Preferences.load_options(preferences_path)
	Engine.max_fps = options.frame_cap
	dev_enabled=options.dev_enabled
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	if data.is_empty():
		push_error("World data missing.")
		get_tree().quit(1)
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
	add_child(music)
	ui = Interface.new()
	add_child(ui)
	ui.setup(self)
	dev_tools=DevTools.new()
	add_child(dev_tools)
	dev_tools.setup(self)
	save_directory = ProjectSettings.globalize_path("res://saves") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("saves")
	ui.title_screen()
	get_viewport().size_changed.connect(_resize_interface)
	print("BRASS TIDE v", Version.text(), " | ", OS.get_processor_name(), " | ", OS.get_processor_count(), " logical threads | ", RenderingServer.get_video_adapter_name())
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
	if chart == null:
		return
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
	elif mode == "battle" and not battle.is_empty() and not result_handled:
		var started: int=Time.get_ticks_usec()
		var aim = chart.world_at(get_global_mouse_position())
		var flagship = Battle.get_flagship(battle)
		var manual = not bool(battle.get("autopilot", true)) and not tactical_mode
		Battle.update(battle, dt, {"manual":manual,"forward":Input.is_key_pressed(KEY_UP),"backward":Input.is_key_pressed(KEY_DOWN),"left":Input.is_key_pressed(KEY_LEFT),"right":Input.is_key_pressed(KEY_RIGHT),"boost":Input.is_key_pressed(KEY_CTRL),"fire":manual and fire_held,"aimX":aim.x,"aimY":aim.y})
		simulation_us=Time.get_ticks_usec()-started
		audio.consume(Battle.pop_events(battle),chart)
		if battle.result != null:
			result_handled = true
			settle_battle.call_deferred()

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if dev_enabled:
			if event.keycode==KEY_F9: dev_tools.shown=not dev_tools.shown;return
			if event.keycode==KEY_F6: dev_tools.refill();return
			if event.keycode==KEY_F8: dev_tools.snapshot();return
			if event.keycode==KEY_PERIOD and lab_active and paused and not ui.modal_open:
				Battle.update(battle,1.0/30.0,{})
				if battle.result!=null and not result_handled: result_handled=true;settle_battle()
				return
		if event.keycode == KEY_F11:
			toggle_fullscreen()
			return
		if event.keycode == KEY_ESCAPE:
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
	_leave_lab()
	sync_economy()
	core.new_game(int(Time.get_unix_time_from_system()))
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
	if not patrol.hostile:
		ui.paragraph(body, "A coastal merchant convoy sails this route. It carries goods between the same ports that supply your fleet. Its crews signal a peaceful passage.", 19)
		ui.button(body, "Let them pass", ui.close_modal, true)
		ui.paragraph(body,"Opening fire damages public standing, creates a witnessed offense and a harbor claim.",15,ui.RED)
		ui.button(body,"Attack this convoy",func():engage_patrol(patrol))
		return
	ui.paragraph(body, "Raider engines echo across the water. You can engage their boats or give them a wide berth. Their strength is %d boat(s)." % patrol.strength, 19)
	ui.button(body, "Engage the raiders", func(): engage_patrol(patrol), true)
	ui.button(body, "Avoid contact", func(): core.state.encounterGrace = 90.0; ui.close_modal())

func engage_patrol(patrol: Dictionary):
	var owner: Dictionary=core.fleet_owner(patrol.id)
	var aggression: bool=not core.Politics.hostile(core,owner)
	if aggression:core.Politics.declare_attack(core,owner)
	var specs: Array = [core.hull("bilge_punt")]
	if patrol.strength >= 2:
		specs.append(core.hull("scab_cutter"))
	if patrol.strength >= 3:
		specs.append(core.hull("barbed_lance"))
	begin_battle(specs, {"kind": "patrol", "id": patrol.id, "ownerId":patrol.id,"aggression":aggression, "name": "Coastal shipping lane"})

func begin_battle(specs: Array, context: Dictionary):
	if core.active_fleet().is_empty():
		ui.toast("You need a crewed, active boat before fighting.", true)
		return
	sync_economy()
	core.use_reserves()
	save_game(false)
	quick_mode = false
	core.stop_sailing()
	battle_enemies = specs
	battle_context = context
	var owner = core.fleet_owner(str(context.get("ownerId","")))
	var enemy_fleet = owner.get("boats",[]).filter(func(b):return not b.sunk) if not owner.is_empty() else []
	battle = Battle.create({"fleet": core.active_fleet(), "enemySpecs": specs, "enemyFleet":enemy_fleet, "seed": int(core.state.seed) + core.state.wins * 17 + core.state.losses * 5, "location": {"name": context.name}})
	_enter_battle()

func quick_battle():
	lab_config=FleetLab.preset(data,"mixed")
	start_lab()

func _leave_lab():
	if career_core!=null:
		core=career_core
		career_core=null
	lab_active=false
	quick_mode=false

func open_lab():
	if mode=="campaign": save_game(false)
	_leave_lab()
	mode="menu"
	battle={}
	ui.modal_kind=""
	ui.title_screen()
	LabUI.open(ui)

func start_lab():
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
	battle_enemies=battle.ships.filter(func(s):return s.team=="enemy").map(func(s):return s.spec)
	battle_context={"kind":"laboratory","name":"Fleet battle laboratory"}
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
	salvage_claimed = false
	battle_last_wrecks = 0
	selection_dragging = false
	selected_battle_ids = [battle.playerId] if battle.playerId != null else []
	chart.zoom = 1.0
	chart.set_tactical(false)
	chart.center_camera()
	ui.close_modal()
	ui.build_hud()
	ui.toast("Autopilot engaged. WASD camera · Space pause · select boats, right-click orders · Tab tactical view.")

func switch_flagship():
	var fleet = battle.ships.filter(func(s): return s.team == "player" and not s.sunk)
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
	Battle.set_autopilot(battle, not bool(battle.get("autopilot", true)))
	fire_held = false
	ui.toast("Flagship autopilot engaged." if battle.autopilot else "Manual flagship: arrow keys steer, mouse aims/fires. WASD still moves the camera.")
	ui.update_hud()

func toggle_tactical():
	if mode != "battle":
		return
	tactical_mode = not tactical_mode
	if tactical_mode:
		pre_tactical_paused = paused
		paused = true
		Battle.set_autopilot(battle, true)
	else:
		paused = pre_tactical_paused
	chart.set_tactical(tactical_mode)
	fire_held = false
	ui.update_hud()

func select_battle_boat(id: String, additive: bool = false):
	if not battle.ships.any(func(boat):return str(boat.id)==id and boat.team=="player" and not boat.sunk):
		return
	if not additive:
		selected_battle_ids.clear()
	if not id in selected_battle_ids:
		selected_battle_ids.append(id)
	ui.update_hud()

func select_all_boats():
	selected_battle_ids.clear()
	for boat in battle.get("ships", []):
		if boat.team == "player" and not boat.sunk:
			selected_battle_ids.append(boat.id)
	ui.update_hud()

func finish_battle_selection(position: Vector2, additive: bool = false):
	selection_dragging = false
	var rectangle = Rect2(selection_start, position - selection_start).abs()
	if rectangle.size.length() < 8:
		var nearest = ""
		var distance = 42.0
		for boat in battle.ships:
			if boat.team == "player" and not boat.sunk:
				var d = chart.project(Vector2(boat.x, boat.y)).distance_to(position)
				if d < distance:
					distance = d
					nearest = str(boat.id)
		if not nearest.is_empty():
			select_battle_boat(nearest, additive)
	else:
		if not additive:
			selected_battle_ids.clear()
		for boat in battle.ships:
			if boat.team == "player" and not boat.sunk and rectangle.has_point(chart.project(Vector2(boat.x, boat.y))) and not boat.id in selected_battle_ids:
				selected_battle_ids.append(boat.id)
	selection_box = Rect2()
	ui.update_hud()

func command_selected(order: String, target: Dictionary = {}):
	if battle.is_empty():
		return
	if order == "escort" and target.is_empty():
		target = {"shipId":str(battle.playerId)}
	selected_battle_ids = selected_battle_ids.filter(func(id):return battle.ships.any(func(boat):return boat.id==id and boat.team=="player" and not boat.sunk))
	if selected_battle_ids.is_empty():
		select_all_boats()
	if not Battle.issue_order(battle, selected_battle_ids, order, target):
		ui.toast("Choose navigable water or a living target for that order.", true)
	ui.update_hud()

func order_at(position: Vector2):
	if battle.is_empty():
		return
	var target: Dictionary = {}
	var closest = 42.0
	for boat in battle.ships:
		if boat.sunk:
			continue
		var distance = chart.project(Vector2(boat.x, boat.y)).distance_to(position)
		if distance < closest:
			closest = distance
			target = boat
	if not target.is_empty():
		command_selected("attack" if target.team == "enemy" else "escort", {"shipId":str(target.id)})
	else:
		var point = chart.world_at(position)
		command_selected("move", {"x":point.x,"y":point.y})

func refit_boat(uid: String, slot: String, module_id: String):
	sync_economy()
	var result = core.refit_boat(uid, slot, module_id)
	respond(result)
	if result.ok:
		save_game(false)
	ui.open_refit(uid)

func set_crew_policy(policy: String):
	var flagship = Battle.get_flagship(battle)
	if not flagship.is_empty():
		Damage.set_policy(flagship, policy)
	ui.update_hud()

func settle_battle():
	fire_held = false
	if lab_active:
		LabUI.results(ui)
		return
	var report = {"coins": 0, "salvage": {}, "fleetLost": false, "completed": false}
	if not quick_mode:
		report = core.battle_settled(battle.result,battle_enemies,battle_context,battle)
	ui.outcome(battle.result, report, battle_enemies)

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

func save_game(show_notice: bool = true):
	if mode != "campaign" or core.state.is_empty() or quick_mode:
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
		mode = "campaign"
		quick_mode = false
		paused = false
		chart.zoom = 1.0
		chart.center_camera()
		ui.close_modal()
		ui.build_hud()
	respond(result)

func quit_game():
	save_preferences()
	save_game(false)
	sync_economy()
	get_tree().quit()

func _exit_tree():
	if economy_task >= 0:
		economy_workers.finish(true)

func capture_after_start():
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	var path = ProjectSettings.globalize_path("res://../qa")
	DirAccess.make_dir_recursive_absolute(path)
	image.save_png(path.path_join("%s.png" % mode))
	print("QA_CAPTURE ", path.path_join("%s.png" % mode))
