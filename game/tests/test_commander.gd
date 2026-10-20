extends SceneTree
const Main = preload("res://scripts/main.gd")
const RefitUI = preload("res://scripts/refit_ui.gd")
var game
var checks = 0
var failures = 0

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("COMMANDER TEST: " + message)

func _initialize():
	call_deferred("run")

func key(code: Key):
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_input(event)

func labels(node: Node) -> Array:
	var result: Array = []
	if node is Label or node is Button:
		result.append(str(node.text))
	for child in node.get_children():
		result.append_array(labels(child))
	return result

func run():
	game = Main.new()
	root.add_child(game)
	await process_frame
	game.audio.enabled = false
	game.save_directory = ProjectSettings.globalize_path("res://../qa/commander-saves")
	game.new_game()
	game.paused = true
	var before: Vector2 = game.chart.camera
	game.chart.pan_camera(Vector2.RIGHT,0.1)
	game.chart.step(0.1)
	check(game.chart.camera != before,"campaign camera pans and persists while paused")
	game.quick_battle()
	check(game.battle.autopilot and not game.paused,"battle starts running with flagship autopilot")
	game.paused = true
	before = game.chart.camera
	game.chart.pan_camera(Vector2.UP,0.1)
	game.chart.step(0.1)
	check(game.chart.camera != before,"battle camera moves while paused")
	key(KEY_TAB)
	check(game.tactical_mode and game.paused,"Tab opens a paused tactical view")
	key(KEY_TAB)
	check(not game.tactical_mode and game.paused,"Tab restores previously paused state")
	game.paused = false
	key(KEY_TAB)
	key(KEY_TAB)
	check(not game.paused,"Tab restores previously running state")
	game.paused = true
	key(KEY_U)
	check(not game.battle.autopilot,"U enables explicit manual flagship")
	key(KEY_U)
	check(game.battle.autopilot,"U returns flagship to autopilot")
	var flagship: String = game.battle.playerId
	key(KEY_X)
	check(game.battle.playerId != flagship,"X cycles flagship")
	game.select_all_boats()
	var players: Array = game.battle.ships.filter(func(s):return s.team=="player" and not s.sunk)
	check(game.selected_battle_ids.size()==players.size(),"select all includes all living player boats")
	game.command_selected("hold")
	for boat in players:
		check(boat.get("order","")=="hold" or boat.get("command",{}).get("order","")=="hold","hold order reaches selected boat")
	var selected: Dictionary = players[0]
	game.select_battle_boat(selected.id)
	check(game.selected_battle_ids == [selected.id],"single selection replaces group")
	var screen: Vector2 = game.chart.project(Vector2(selected.x,selected.y))
	game.selection_start = screen
	game.selection_dragging = true
	game.finish_battle_selection(screen)
	check(selected.id in game.selected_battle_ids,"click selection uses isometric projection")
	game.selection_start = Vector2(-10000,-10000)
	game.finish_battle_selection(Vector2(10000,10000))
	check(game.selected_battle_ids.size() == players.size(),"box selects all boats in rectangle")
	game.ui.update_hud()
	var visible: String = "\n".join(labels(game.ui.chrome))
	check("coins" in visible and not "cash" in visible.to_lower(),"HUD consistently calls currency coins")
	check("300" in visible and "AUTOPILOT" in visible,"HUD shows per-side deployment limit and control mode")
	game.return_to_campaign()
	game.paused = true
	var uid: String = game.core.state.fleet[0].uid
	game.ui.open_refit(uid)
	await process_frame
	visible = "\n".join(labels(game.ui.overlay))
	check(game.ui.modal_kind == "refit" and "FITTING BAY" in visible,"real fitting screen opens for inherited hull")
	check("Change weapon" in visible and "Change package" in visible,"fitting UI exposes weapons engine and armor")
	game.core.current_port().stocks.guns = 0.0
	RefitUI.choose(game.ui,uid,"weapon:1")
	visible = "\n".join(labels(game.ui.overlay))
	check("Review bill" in visible and "Needle machine gun" in visible,"missing-stock fitting still allows inspection of its real bill")
	RefitUI.review(game.ui,uid,"weapon:1","rapid_gun")
	visible = "\n".join(labels(game.ui.overlay))
	check("PHYSICAL MATERIALS" in visible and "COINS TOTAL" in visible,"unavailable fitting review explains parts and total cost")
	var install_disabled: bool = false
	var pending: Array = [game.ui.overlay]
	while not pending.is_empty():
		var node = pending.pop_back()
		if node is Button and str(node.text).begins_with("Install"):
			install_disabled = node.disabled
		pending.append_array(node.get_children())
	check(install_disabled,"a missing-stock fitting bill cannot install")
	game.ui.close_modal()
	game.queue_free()
	await process_frame
	print("commander: %d checks, %d failures; background only" % [checks,failures])
	quit(0 if failures==0 else 1)
