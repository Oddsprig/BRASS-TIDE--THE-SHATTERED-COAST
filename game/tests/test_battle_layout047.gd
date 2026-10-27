extends SceneTree
## SOURCE CANDIDATE, UNRUN. Root alone executes through Test Bridge, after 046.
## One tiny public Lab, two actual viewport layouts, native control signals only.
const Lab=preload("res://scripts/fleet_lab.gd")
var game
var checks: int=0
var failures: int=0

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL battle_layout047: "+message)

func descendants(node: Node) -> Array:
	var result: Array=[node]
	for child in node.get_children():result.append_array(descendants(child))
	return result

func control(name: String):
	return game.ui.root.find_child(name,true,false)

func press(name: String) -> void:
	var button=control(name)
	check(button is Button and button.is_visible_in_tree() and not button.disabled,"reachable control: "+name)
	if button is Button and not button.disabled:button.pressed.emit()

func labels() -> Array:
	return [game.ui.stats_label,game.ui.clock_label,game.ui.voyage_label,game.ui.flagship_label,game.ui.damage_label,game.ui.objective_label,game.ui.battle_points_label,game.ui.battle_control_label,game.ui.tactical_intent_label]

func geometry(viewport: Vector2i) -> void:
	root.content_scale_size=viewport;root.size=viewport
	await process_frame;await process_frame
	game.ui.build_hud()
	await process_frame;await process_frame
	var screen: Rect2=Rect2(Vector2.ZERO,Vector2(viewport))
	var panels: Array=[]
	for name in ["BattleTop","BattleMission","BattleStatus","BattleOrders"]:
		var panel=control(name)
		check(panel is PanelContainer and screen.encloses(panel.get_global_rect().grow(-0.5)),"occupied band stays inside %s: %s"%[viewport,name])
		if panel is PanelContainer:panels.append(panel)
	if panels.size()!=4:return
	var no_overlap: bool=true
	for i in range(panels.size()):
		for j in range(i):no_overlap=no_overlap and not panels[i].get_global_rect().intersects(panels[j].get_global_rect())
	check(no_overlap,"four occupied HUD bands do not overlap at "+str(viewport))
	var visible_fit: bool=true
	var buttons: Array=[]
	for node in descendants(game.ui.chrome):
		if not node is Control or not node.is_visible_in_tree():continue
		if node is Button or node is Label or node is ProgressBar:
			visible_fit=visible_fit and screen.encloses(node.get_global_rect().grow(-0.5))
		if node is Button:buttons.append(node)
	for i in range(buttons.size()):
		for j in range(i):visible_fit=visible_fit and not buttons[i].get_global_rect().intersects(buttons[j].get_global_rect())
	check(visible_fit,"all default text, bars and buttons fit without overlapping controls at "+str(viewport))
	var mission: Rect2=panels[1].get_global_rect()
	var status: Rect2=panels[2].get_global_rect()
	var open_area: float=float(viewport.x)*maxf(0.0,status.position.y-mission.end.y)
	# Inherited 280+300px sidebars plus their margins left at most w-630 centre;
	# using the entire h-166 between old top/bottom bars favors the old layout.
	var previous_centre: float=float(viewport.x-630)*float(viewport.y-166)
	check(open_area>previous_centre*1.30,"actual full-width chart area grows materially at "+str(viewport))
	check(game.ui.chrome.get_child_count()==4,"no empty permanent sidebar frames at "+str(viewport))
	print("battle_layout047 %s: actual clear centre %.0fpx², inherited centre bound %.0fpx²"%[viewport,open_area,previous_centre])

func exercise() -> void:
	var career=game.core
	var saved: Dictionary=career.state.duplicate(true)
	game.open_lab()
	game.lab_config={"player":[Lab.entry(game.data,"iron_bastion"),Lab.entry(game.data,"lantern_skiff")],"enemy":[Lab.entry(game.data,"tin_skiff")]}
	game.lab_seed=47047;game.start_lab();game.paused=true
	var flagship: Dictionary=game.Battle.get_flagship(game.battle)
	var ally: Dictionary=game.battle.ships.filter(func(s):return s.team=="player" and s.id!=flagship.id)[0]
	var stores: Array=[]
	for boat in game.battle.ships:stores.append([boat.crew,boat.wounded,boat.supplies,boat.fuel,boat.ammo])
	for viewport in [Vector2i(1600,1000),Vector2i(1280,800)]:await geometry(viewport)
	var refs: Array=labels()
	game.select_battle_boat(str(ally.id))
	check(game.ui.flagship_label.text==str(ally.name) and is_equal_approx(game.ui.hull_bar.value,100.0*float(ally.hp)/float(ally.maxHp)),"selected condition follows actual selection, independently of flagship")
	game.ui.policy_buttons.repair.pressed.emit()
	check(flagship.policy=="repair" and ally.policy!="repair","compact crew priority acts on actual flagship only")
	game.select_battle_boat(str(flagship.id))
	var status: Dictionary=game.Battle.tactical_status(game.battle,str(flagship.id))
	check(game.ui.tactical_intent_label.text==game.ui.TacticsUI.plain(str(status.reason)) and "Cannon 1:" in game.ui.battle_reload_label.text,"default HUD exposes actual AI reason and physical-mount readiness")
	check("/300 DP" in game.ui.battle_points_label.text and "%d reserve"%game.battle.reserves.player.size() in game.ui.battle_points_label.text,"DP/reserves label follows actual deployment state")
	for command in ["engage","harass","focus","escort","defend","rally","hold","withdraw"]:
		press("BattleCommand_"+command)
		check(str(game.battle_command_ack.get("command",""))==command and not game.ui.battle_control_label.text.is_empty(),"button publishes immediate visible host acknowledgment: "+command)
	press("BattleCommand_focus")
	check(game.battle_command_pending=="focus" and "Right-click" in game.ui.battle_control_label.text,"target order stays visibly pending rather than pretending it executed")
	game.request_battle_command("hold")
	press("BattlePause");check(not game.paused,"native pause button resumes")
	press("BattlePause");check(game.paused,"native pause button pauses")
	for initial in [false,true]:
		game.paused=initial;game.toggle_tactical();game.toggle_tactical()
		check(game.paused==initial,"overview restores prior pause state "+str(initial))
	game.paused=true
	press("BattleAutopilot");check(not game.battle.autopilot,"compact autopilot button yields manual flagship")
	press("BattleAutopilot");check(game.battle.autopilot,"compact autopilot button restores autopilot")
	press("BattleDetails")
	check(game.ui.modal_kind=="battle_details" and "Inflow" in game.ui.battle_details_label.text and "Stores:" in game.ui.battle_details_label.text,"on-demand detail retains finite crew, flows and stores")
	game.ui.close_modal();press("BattleTactics")
	var routes: bool=game.chart.battle_overlays.routes
	press("BattleOverlay_routes");check(game.chart.battle_overlays.routes!=routes,"on-demand routes toggle uses agreed host overlay API")
	game.ui.close_modal()
	check(labels()==refs and refs.all(func(node):return is_instance_valid(node)),"modal round trip preserves every legacy HUD label reference")
	var remaining: Array=[]
	for boat in game.battle.ships:remaining.append([boat.crew,boat.wounded,boat.supplies,boat.fuel,boat.ammo])
	check(remaining==stores and career.state==saved,"UI-only callbacks invent no stores, people or paid career mutations")

func _initialize() -> void:call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()!="headless":check(false,"requires Root background/headless/Dummy Test Bridge batch")
	else:
		game=load("res://main.tscn").instantiate();root.add_child(game)
		game.set_process(false);game.set_physics_process(false)
		game.audio.enabled=false;game.music.enabled=false
		game.save_directory=OS.get_user_data_dir().path_join("layout047-%d"%Time.get_ticks_usec())
		await process_frame
		game.new_game();game.paused=true
		await exercise()
		game.queue_free();await process_frame
	print("battle_layout047: %d checks, %d failures; layout/control signals only, no motion or quality verdict"%[checks,failures])
	quit(0 if failures==0 else 1)
