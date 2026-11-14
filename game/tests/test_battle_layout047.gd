extends SceneTree
## Actual Driver-publication fixture. Root executes through the shared Test Bridge lane.
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

func press(name: String) -> bool:
	var button=control(name)
	var reachable: bool=(
		button is Button
		and button.is_visible_in_tree()
		and not button.disabled
	)
	check(reachable,"reachable control: "+name)
	if not reachable:
		return false
	button.pressed.emit()
	return true

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
	var map_control=control("BattleMinimap")
	check(map_control is Control and panels[2].get_global_rect().encloses(map_control.get_global_rect()),"minimap occupies its reserved status-band column at "+str(viewport))
	if map_control is Control:
		check(labels().all(func(item):return not item.get_global_rect().intersects(map_control.get_global_rect())),"minimap does not cover status text or actionable state")
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

func boat106(id: String) -> Dictionary:
	for boat: Dictionary in game.battle.ships:
		if str(boat.id)==id:
			return boat
	return {}

func stores106() -> Dictionary:
	var result: Dictionary={}
	for boat: Dictionary in game.battle.ships:
		result[str(boat.id)]=[
			boat.crew,boat.wounded,boat.supplies,boat.fuel,boat.ammo
		]
	return result

func receipt106(after: int, kind: String="") -> Dictionary:
	var result: Dictionary={}
	for row: Dictionary in game.battle_driver051.telemetry().get("commandResults",[]):
		if int(row.get("sequence",0))<=after:
			continue
		if not kind.is_empty() and str(row.get("kind",""))!=kind:
			continue
		if result.is_empty() or int(row.sequence)>int(result.sequence):
			result=row.duplicate(true)
	return result

func publish106(done: Callable, message: String) -> bool:
	if game.battle_driver051==null:
		check(false,"native Driver exists: "+message)
		return false

	var before_stores: Dictionary=stores106()
	var before_career: Dictionary=game.core.state.duplicate(true)
	var deadline: int=Time.get_ticks_msec()+2000

	for attempt in range(120):
		# Always stopped, including while testing the pause button.
		game.poll_battle051(0.0,true)
		game.ui.update_hud()

		if stores106()!=before_stores or game.core.state!=before_career:
			check(false,"zero-time publication preserves stores/career: "+message)
			return false

		if bool(done.call()):
			check(true,message)
			return true
		if Time.get_ticks_msec()>=deadline:
			break
		await process_frame

	check(false,"publication deadline: "+message)
	return false

func command106(command: String) -> bool:
	var sequence: int=int(game._battle_ack_sequence051)
	if not press("BattleCommand_"+command):
		return false

	if game.battle_command_pending==command:
		check("Right-click" in game.ui.battle_control_label.text,
			"target command visibly awaits its target: "+command)
		return true

	if not (await publish106(func():
		return not receipt106(sequence,"player_command").is_empty()
	,"native command receipt: "+command)):
		return false

	var receipt: Dictionary=receipt106(sequence,"player_command")
	var accepted: bool=bool(receipt.get("ok",false))
	check(accepted,"native command accepted: "+command)
	check(
		str(game.battle_command_ack.get("command",""))=="player_command"
		and not game.ui.battle_control_label.text.is_empty(),
		"published command acknowledgment is visible: "+command
	)
	return accepted

func exercise() -> void:
	var career=game.core
	var saved: Dictionary=career.state.duplicate(true)
	game.open_lab()
	game.lab_config={"player":[Lab.entry(game.data,"iron_bastion"),Lab.entry(game.data,"lantern_skiff")],"enemy":[Lab.entry(game.data,"tin_skiff")]}
	game.lab_seed=47047;game.start_lab();game.paused=true
	check(game.Battle.set_autopilot(game.battle,true),"initial zero-time public command queues the worker boot")
	if not (await publish106(func():
		var boat: Dictionary=game.Battle.get_flagship(game.battle)
		return not boat.is_empty() and game.Battle.tactical_status(game.battle,str(boat.id)).has("reason")
	,"initial native status publication")):return
	var flagship_id: String=str(game.Battle.get_flagship(game.battle).id)
	var ally_id: String="";var enemy_id: String=""
	for boat in game.battle.ships:
		if boat.team=="player" and str(boat.id)!=flagship_id:ally_id=str(boat.id)
		if boat.team=="enemy":enemy_id=str(boat.id)
	check(not ally_id.is_empty() and not enemy_id.is_empty(),"actual friendly and enemy targets exist")
	if ally_id.is_empty() or enemy_id.is_empty():return
	var stores: Dictionary=stores106()
	var clock: float=float(game.battle.time)
	var steps: int=int(game.battle_driver051.telemetry().completedSteps)
	check(clock==0.0 and float(game.battle_driver051.telemetry().stateTime)==0.0 and steps==0,"boot publishes without any priming physics step")
	for viewport in [Vector2i(1600,1000),Vector2i(1280,800)]:await geometry(viewport)
	game.ui.toast("first battle notice");game.ui.toast("second battle notice")
	check(game.ui.notices.get_child_count()==1,"battle feedback has one notice rather than a stack")
	if "--layout-only" in OS.get_cmdline_user_args():return
	var refs: Array=labels()
	game.select_battle_boat(ally_id)
	check(game.ui.flagship_label.text==str(boat106(ally_id).name),"condition follows actual selected ally")
	var ally_policy: String=str(boat106(ally_id).policy)
	var sequence: int=int(game._battle_ack_sequence051)
	game.ui.policy_buttons.repair.pressed.emit()
	if not (await publish106(func():return not receipt106(sequence).is_empty() and boat106(flagship_id).get("policy")=="repair","flagship crew priority reaches worker publication")):return
	check(bool(receipt106(sequence).get("ok",false)) and str(boat106(ally_id).policy)==ally_policy,"crew priority changes flagship only")
	game.select_battle_boat(flagship_id)
	var status: Dictionary=game.Battle.tactical_status(game.battle,flagship_id)
	check(game.ui.tactical_intent_label.text==game.ui.TacticsUI.plain(str(status.reason)),"actual selected AI reason remains visible")
	check("Cannon 1 · " in game.ui.battle_reload_label.text,"compact label names the actual physical mount")
	var full_reason: String=str(status.weapons.get(str(status.mounts[0].id),"")) if not status.mounts.is_empty() else ""
	check(not full_reason.is_empty() and "Cannon 1 · " in game.ui.battle_reload_label.tooltip_text and full_reason in game.ui.battle_reload_label.tooltip_text,"tooltip retains the complete current weapon reason")
	check("/300 DP" in game.ui.battle_points_label.text,"deployment remains distinct from ownership")
	for command in ["engage","harass","focus","escort","defend","rally","hold","withdraw"]:
		if not (await command106(command)):return
	# Exercise actual native target submission, without OS input or simulation.
	for command in ["focus","escort","defend","rally"]:
		press("BattleCommand_"+command)
		check(game.battle_command_pending==command,"target selection is visibly pending: "+command)
		var target_id: String=enemy_id if command=="focus" else ally_id
		var at: Vector2=Vector2(boat106(target_id).x,boat106(target_id).y) if command in ["focus","escort"] else Vector2(boat106(flagship_id).x,boat106(flagship_id).y)
		var target_sequence: int=int(game._battle_ack_sequence051)
		game.order_at(game.chart.project(at))
		if not (await publish106(func():return not receipt106(target_sequence,"player_command").is_empty(),"target command published: "+command)):return
		check(bool(receipt106(target_sequence,"player_command").get("ok",false)),"native target command accepted: "+command)
		check(str(boat106(flagship_id).order)==str({"focus":"attack","escort":"escort","defend":"hold","rally":"move"}[command]),"actual boat receives mapped target order: "+command)
		if command in ["focus","escort"]:check(str(boat106(flagship_id).orderTarget.get("shipId",""))==target_id,"order retains actual target identity: "+command)
	if not (await command106("hold")):return
	check(game.battle_command_pending.is_empty(),"hold clears pending target order")
	press("BattlePause");check(not game.paused,"pause control resumes")
	press("BattlePause");check(game.paused,"pause control pauses")
	for initial in [false,true]:
		game.paused=initial
		var manual_sequence: int=int(game._battle_ack_sequence051)
		check(game.queue_battle_command051("autopilot",{"enabled":false}),"manual baseline command queues")
		if not (await publish106(func():return not receipt106(manual_sequence,"autopilot").is_empty() and not bool(game.battle.autopilot),"manual baseline publishes")):return
		var previous_autopilot: bool=bool(game.battle.autopilot)
		var overview_sequence: int=int(game._battle_ack_sequence051)
		game.toggle_tactical()
		if not (await publish106(func():return not receipt106(overview_sequence,"autopilot").is_empty() and bool(game.battle.autopilot),"overview autopilot publishes")):return
		var restore_sequence: int=int(game._battle_ack_sequence051)
		game.toggle_tactical()
		if not (await publish106(func():return not receipt106(restore_sequence,"autopilot").is_empty() and bool(game.battle.autopilot)==previous_autopilot,"overview restores autopilot")):return
		check(game.paused==initial,"overview restores prior pause state")
	game.paused=true
	check(game.Battle.set_autopilot(game.battle,true),"autopilot baseline queues")
	if not (await publish106(func():return bool(game.battle.autopilot),"autopilot baseline publishes")):return
	var manual_button_sequence: int=int(game._battle_ack_sequence051)
	press("BattleAutopilot")
	if not (await publish106(func():return not receipt106(manual_button_sequence,"autopilot").is_empty() and not bool(game.battle.autopilot),"manual flagship publishes")):return
	var autopilot_button_sequence: int=int(game._battle_ack_sequence051)
	press("BattleAutopilot")
	if not (await publish106(func():return not receipt106(autopilot_button_sequence,"autopilot").is_empty() and bool(game.battle.autopilot),"autopilot restores")):return
	press("BattleDetails")
	check(game.ui.modal_kind=="battle_details" and "Inflow" in game.ui.battle_details_label.text and "Stores:" in game.ui.battle_details_label.text,"expanded detail keeps finite damage control and stores")
	game.ui.close_modal();press("BattleTactics")
	var routes: bool=game.chart.battle_overlays.routes
	press("BattleOverlay_routes");check(game.chart.battle_overlays.routes!=routes,"optional route overlay changes")
	game.ui.close_modal()
	check(labels()==refs and refs.all(func(node):return is_instance_valid(node)),"modal round trip preserves HUD controls")
	check(stores106()==stores and career.state==saved,"all UI-only commands preserve finite stores and the actual career")
	check(float(game.battle.time)==clock and float(game.battle_driver051.telemetry().stateTime)==clock and int(game.battle_driver051.telemetry().completedSteps)==steps,"command-only publication advances no simulation clock or steps")

func _initialize() -> void:call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()!="headless":check(false,"requires Root background/headless/Dummy Test Bridge batch")
	else:
		game=load("res://main.tscn").instantiate();game.qa_ocean066=true;root.add_child(game)
		game.set_process(false);game.set_physics_process(false)
		game.audio.enabled=false;game.music.enabled=false
		game.save_directory=OS.get_user_data_dir().path_join("layout047-%d"%Time.get_ticks_usec())
		await process_frame
		game.new_game(47047);game.paused=true
		await exercise()
		game.queue_free();await process_frame
	if has_method("after_controls106"):await call("after_controls106")
	print("battle_layout047: %d checks, %d failures; layout/control signals only, no motion or quality verdict"%[checks,failures])
	quit(0 if failures==0 else 1)
