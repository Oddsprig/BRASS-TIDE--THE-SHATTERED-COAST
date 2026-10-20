extends Node2D

const Damage = preload("res://scripts/damage.gd")
const Battle = preload("res://scripts/battle.gd")
const Economy = preload("res://scripts/economy.gd")
const Version = preload("res://scripts/version.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Chart = preload("res://scripts/chart.gd")
const Interface = preload("res://scripts/interface.gd")
const Sound = preload("res://scripts/sound.gd")

var data: Dictionary
var core
var chart
var ui
var audio
var mode = "menu"
var paused = false
var speed = 1
var selected_port = "brass_haven"
var battle: Dictionary = {}
var battle_context: Dictionary = {}
var battle_enemies: Array = []
var quick_mode = false
var fire_held = false
var auto_gunners = false
var result_handled = false
var salvage_claimed = false
var hud_timer = 0.0
var save_timer = 0.0
var economy_task: int = -1
var economy_job: Dictionary = {}
var save_directory = ""
var battle_last_wrecks = 0
var screenshots_requested: Array = []

func _ready():
	Engine.max_fps = 120
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
	add_child(audio)
	ui = Interface.new()
	add_child(ui)
	ui.setup(self)
	save_directory = ProjectSettings.globalize_path("res://saves") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("saves")
	ui.title_screen()
	get_viewport().size_changed.connect(_resize_interface)
	print("BRASS TIDE v", Version.text(), " | ", OS.get_processor_name(), " | ", OS.get_processor_count(), " logical threads | ", RenderingServer.get_video_adapter_name())
	# Development hooks are explicit launch arguments; retail controls do not expose them.
	var args = OS.get_cmdline_user_args()
	if "--qa-campaign" in args:
		new_game()
	if "--qa-battle" in args:
		quick_battle()
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
	chart.step(minf(dt, 0.1))
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
		_finish_economy(true)
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
	elif mode == "battle" and not battle.is_empty() and not result_handled:
		var aim = chart.world_at(get_global_mouse_position())
		var flagship = Battle.get_flagship(battle)
		var firing = fire_held
		if not flagship.is_empty():
			var closest: Dictionary = {}
			var mouse_distance = 45.0
			var best = INF
			for target in battle.ships:
				if target.team != "enemy" or target.sunk:
					continue
				var d = Vector2(target.x - flagship.x, target.y - flagship.y).length()
				var screen_distance = chart.project(Vector2(target.x, target.y)).distance_to(get_global_mouse_position())
				if (auto_gunners and d < best) or (not auto_gunners and screen_distance < mouse_distance):
					closest = target
					best = d
					mouse_distance = screen_distance
			if not closest.is_empty() and (firing or auto_gunners):
				var projectile_speed = 240.0 if flagship.spec.weapon == "torpedo" else 850.0
				var flight = minf(1.7, best / projectile_speed)
				aim = Vector2(closest.x + closest.vx * flight, closest.y + closest.vy * flight)
				if auto_gunners:
					firing = best < flagship.spec.range
		var old_ammo = flagship.get("ammo", 0)
		Battle.update(battle, dt, {"forward": Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP), "backward": Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN), "left": Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT), "right": Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT), "boost": Input.is_key_pressed(KEY_SHIFT), "fire": firing, "aimX": aim.x, "aimY": aim.y})
		if not flagship.is_empty() and flagship.ammo < old_ammo:
			audio.play("shot")
		if battle.wrecks.size() > battle_last_wrecks:
			battle_last_wrecks = battle.wrecks.size()
			audio.play("boom")
		if battle.result != null:
			result_handled = true
			settle_battle.call_deferred()

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
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
			KEY_E: ui.open_port() if mode == "campaign" else null
			KEY_TAB: switch_flagship() if mode == "battle" else null
			KEY_R:
				if mode == "battle":
					auto_gunners = not auto_gunners
					ui.toast("Automatic gunners on. Steer your boat into range." if auto_gunners else "Manual gunnery.")
			KEY_1: Battle.set_order(battle, "engage") if mode == "battle" else null
			KEY_2: Battle.set_order(battle, "escort") if mode == "battle" else null
			KEY_3: Battle.set_order(battle, "hold") if mode == "battle" else null
	elif event is InputEventMouseButton and not ui.modal_open:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			chart.zoom = clampf(chart.zoom * 1.12, 0.7, 1.8)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			chart.zoom = clampf(chart.zoom / 1.12, 0.7, 1.8)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if mode == "battle":
				fire_held = event.pressed
			elif mode == "campaign" and event.pressed:
				click_chart(get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and mode == "campaign":
			core.stop_sailing()
			ui.toast("Engines idle. Course canceled.")

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		fire_held = false

func toggle_pause():
	paused = not paused
	ui.update_hud()

func toggle_fullscreen():
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func new_game():
	sync_economy()
	core.new_game(int(Time.get_unix_time_from_system()))
	mode = "campaign"
	quick_mode = false
	paused = false
	chart.zoom = 1.0
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
	for patrol in core.state.patrols:
		if patrol.active and chart.project(Vector2(patrol.x, patrol.y)).distance_to(position) < 15:
			show_patrol_encounter(patrol.id)
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
	if not patrol.hostile:
		ui.paragraph(body, "A coastal merchant convoy sails this route. It carries goods between the same ports that supply your fleet. Its crews signal a peaceful passage.", 19)
		ui.button(body, "Let them pass", ui.close_modal, true)
		return
	ui.paragraph(body, "Raider engines echo across the water. You can engage their boats or give them a wide berth. Their strength is %d boat(s)." % patrol.strength, 19)
	ui.button(body, "Engage the raiders", func(): engage_patrol(patrol), true)
	ui.button(body, "Avoid contact", func(): core.state.encounterGrace = 90.0; ui.close_modal())

func engage_patrol(patrol: Dictionary):
	var specs: Array = [core.hull("bilge_punt")]
	if patrol.strength >= 2:
		specs.append(core.hull("scab_cutter"))
	if patrol.strength >= 3:
		specs.append(core.hull("barbed_lance"))
	begin_battle(specs, {"kind": "patrol", "id": patrol.id, "ownerId":patrol.id, "name": "Coastal shipping lane"})

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
	sync_economy()
	if core.state.is_empty():
		core.new_game(35)
	var fleet: Array = []
	for id in ["tin_skiff", "harbor_sloop", "reed_stinger"]:
		fleet.append(Damage.create_ship(core.hull(id)))
	battle_enemies = [core.hull("bilge_punt"), core.hull("scab_cutter"), core.hull("ash_corvette")]
	battle_context = {"kind": "skirmish", "name": "The proving shoals"}
	battle = Battle.create({"fleet": fleet, "enemySpecs": battle_enemies, "seed": 25, "location": {"name": "The proving shoals"}})
	quick_mode = true
	_enter_battle()

func _enter_battle():
	# A new encounter replaces any previous result screen without settling it again.
	ui.modal_kind = ""
	mode = "battle"
	paused = true
	auto_gunners = false
	result_handled = false
	salvage_claimed = false
	battle_last_wrecks = 0
	chart.zoom = 1.0
	var flagship = Battle.get_flagship(battle)
	chart.camera = Vector2(flagship.x, flagship.y)
	ui.close_modal()
	ui.build_hud()
	ui.toast("Tactical pause. W/S throttle, A/D steer, hold click to fire. Space starts the battle. R enables auto gunners.")

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
	ui.update_hud()

func set_crew_policy(policy: String):
	var flagship = Battle.get_flagship(battle)
	if not flagship.is_empty():
		Damage.set_policy(flagship, policy)
	ui.update_hud()

func settle_battle():
	fire_held = false
	var report = {"coins": 0, "salvage": {}, "fleetLost": false, "completed": false}
	if not quick_mode:
		report = core.battle_settled(battle.result, battle_enemies, battle_context)
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
	mode = "campaign"
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
	var days = core.pending_days
	core.pending_days = 0
	var blocked: Array = []
	if core.state.missionIndex < 4:
		blocked.append("cinder_quay")
	if core.state.missionIndex < 8:
		blocked.append("shatter_spire")
	var job = {"ports": core.state.ports.duplicate(true), "days": days, "events": [], "blocked": blocked}
	economy_job = job
	economy_task = WorkerThreadPool.add_task(func(): job.events = Economy.tick_ports(job.ports, job.days, {"blockaded": job.blocked,"interport_trade":false}), false, "Brass Tide coastal economy")

func _finish_economy(force: bool):
	if economy_task < 0:
		return
	if not force and not WorkerThreadPool.is_task_completed(economy_task):
		return
	WorkerThreadPool.wait_for_task_completion(economy_task)
	core.apply_economy(economy_job.ports, economy_job.events, economy_job.days)
	economy_task = -1
	economy_job = {}

func sync_economy():
	_finish_economy(true)
	if not core.state.is_empty() and core.pending_days > 0:
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
	if not has_save():
		ui.toast("No saved voyage yet.", true)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(save_directory.path_join("voyage.json")))
	if not parsed is Dictionary:
		ui.toast("Save is unreadable. Your backup is in the saves folder.", true)
		return
	var result = core.restore(parsed)
	if result.ok:
		mode = "campaign"
		quick_mode = false
		paused = false
		chart.zoom = 1.0
		ui.close_modal()
		ui.build_hud()
	respond(result)

func quit_game():
	save_game(false)
	sync_economy()
	get_tree().quit()

func _exit_tree():
	if economy_task >= 0:
		WorkerThreadPool.wait_for_task_completion(economy_task)

func capture_after_start():
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	var path = ProjectSettings.globalize_path("res://../qa")
	DirAccess.make_dir_recursive_absolute(path)
	image.save_png(path.path_join("%s.png" % mode))
	print("QA_CAPTURE ", path.path_join("%s.png" % mode))
