extends SceneTree
## Real Main scene and native control signals, never desktop input or owner files.
const Lab=preload("res://scripts/fleet_lab.gd")
const TacticsUI=preload("res://scripts/tactics_ui.gd")
var game
var checks: int=0
var failures: int=0
var observations: Array=[]

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL tactical UI: "+message)

func nodes(node: Node) -> Array:
	var result: Array=[node]
	for child in node.get_children():result.append_array(nodes(child))
	return result

func button(prefix: String):
	for node in nodes(game.ui):
		if node is Button and str(node.text).begins_with(prefix):return node
	return null

func press(prefix: String) -> bool:
	var control=button(prefix)
	check(control!=null and not control.disabled,"actual available button: "+prefix)
	if control==null or control.disabled:return false
	control.pressed.emit()
	return true

func field(name: String):
	for node in nodes(game.ui):
		if str(node.name)==name:return node
	return null

func labels() -> String:
	var lines: Array[String]=[]
	for node in nodes(game.ui):
		if node is Label or node is Button:lines.append(str(node.text))
	return "\n".join(lines)

func key(code: Key,ctrl: bool=false,pressed: bool=true,echo: bool=false) -> void:
	var event: InputEventKey=InputEventKey.new()
	event.keycode=code;event.pressed=pressed;event.ctrl_pressed=ctrl;event.echo=echo
	game._unhandled_input(event)

func options(id: String) -> Dictionary:
	return game.Battle.tactical_status(game.battle,id).get("options",{})

func reopen_options() -> bool:
	game.ui.close_modal()
	return press("Selected tactics & weapon groups")

func groups(source: Dictionary,ally: Dictionary,enemy: Dictionary) -> void:
	var sets: Array=[[source.id],[ally.id],[source.id,ally.id],[source.id]]
	for group in range(1,5):
		game.select_battle_boat(str(sets[group-1][0]))
		if sets[group-1].size()==2:game.select_battle_boat(str(ally.id),true)
		key(KEY_F1+group-1,true)
		check(game.battle_selection_groups[group]==sets[group-1],"Ctrl+F%d stores exact living selection"%group)
		game.select_battle_boat(str(ally.id) if sets[group-1]==[source.id] else str(source.id))
		key(KEY_F1+group-1)
		check(game.selected_battle_ids==sets[group-1],"F%d recalls exact saved selection"%group)
	var saved: Array=game.selected_battle_ids.duplicate()
	key(KEY_F2,false,false);key(KEY_F2,false,true,true)
	check(game.selected_battle_ids==saved,"released and echoed function keys cannot change selection")
	game.select_battle_boat(str(enemy.id))
	check(game.selected_battle_ids==saved,"enemy cannot enter owned selection")
	game.selection_start=game.chart.project(Vector2(source.x,source.y))
	game.finish_battle_selection(game.selection_start)
	check(game.selected_battle_ids==[source.id],"projected native click-selection callback selects the actual boat")
	game.selection_start=game.chart.project(Vector2(ally.x,ally.y))
	game.finish_battle_selection(game.selection_start,true)
	check(game.selected_battle_ids==[source.id,ally.id],"projected additive selection preserves the first boat")

func exercise() -> void:
	var career=game.core
	var saved: Dictionary=career.state.duplicate(true)
	game.open_lab()
	var battery: Dictionary=Lab.entry(game.data,"iron_bastion")
	battery.loadout.weapons[1]="rapid_gun"
	game.lab_config={"player":[battery,Lab.entry(game.data,"lantern_skiff")],"enemy":[Lab.entry(game.data,"iron_bastion")]}
	game.lab_seed=30011
	game.start_lab();game.paused=true
	check(game.mode=="battle" and game.lab_active and game.career_core==career,"actual laboratory enters Main battle with separate career custody")
	var players: Array=game.battle.ships.filter(func(ship):return ship.team=="player")
	var enemy: Dictionary=game.battle.ships.filter(func(ship):return ship.team=="enemy")[0]
	check(players.size()==2,"real configured player fleet is available")
	if players.size()!=2:return
	var source: Dictionary=players[0]
	var ally: Dictionary=players[1]
	check(game.battle.autopilot and game.selected_battle_ids==[source.id],"Main enters with default automatic flagship and current selection")
	groups(source,ally,enemy)
	game.select_battle_boat(str(source.id))
	check(game.selected_battle_ids==[source.id],"native boat selection is exact")
	game.select_battle_boat(str(ally.id),true)
	check(game.selected_battle_ids==[source.id,ally.id],"native additive selection retains both")
	if not press("Selected tactics & weapon groups"):return
	check(game.ui.modal_kind=="tactical_options","actual tactics button opens current sheet")
	if not press("Cautious"):return
	for ship in players:check(options(str(ship.id)).get("doctrine")=="cautious","native courage choice reaches selected hull")
	var role=field("TacticalRole")
	check(role is OptionButton,"real role selector exists")
	if role==null:return
	role.select(4)
	if not press("Assign role"):return
	for ship in players:check(options(str(ship.id)).get("role")=="screen","native role choice reaches every selected hull")
	if not press("Column"):return
	for ship in players:check(options(str(ship.id)).get("formation")=="column","real formation choice applies atomically")
	var protected_ally=field("ProtectedAlly")
	check(protected_ally is OptionButton,"real protected ally selector exists")
	if protected_ally==null:return
	# Both selected boats cannot protect themselves. Select only the first boat.
	game.select_battle_boat(str(source.id))
	protected_ally.select(2)
	if not press("Protect this ally"):return
	check(options(str(source.id)).get("protectedAllyId")==str(ally.id),"native protection names the actual allied hull")
	var leash=field("TacticalLeash")
	leash.value=400
	if not press("Set escort distance"):return
	check(is_equal_approx(float(options(str(source.id)).get("leash",0)),400.0),"native escort distance applies")
	var x=field("RallyX");var y=field("RallyY")
	x.value=300;y.value=850
	if not press("Set rally"):return
	check(options(str(source.id)).get("rally",{})=={"x":300.0,"y":850.0},"real local rally water position")
	var conditional=field("ConditionalWithdrawal")
	conditional.button_pressed=true
	check(options(str(source.id)).get("conditionalWithdrawal",false),"native survival permission applies")
	if not press("Hold automatic fire"):return
	for settings in options(str(source.id)).get("mounts",{}).values():check(settings.hold,"actual fitted mount is held")
	var reserve=field("WorkingAmmoReserve")
	reserve.value=7
	if not press("Set round reserve"):return
	for settings in options(str(source.id)).get("mounts",{}).values():check(int(settings.reserve)==7,"actual mount reserve is finite working rounds")
	var before_options: Dictionary=options(str(source.id)).duplicate(true)
	if not reopen_options():return
	check(field("TacticalRole").selected==4 and field("ProtectedAlly").selected==2,"reopened panel reads this selected boat's current role and protected ally")
	check(field("TacticalLeash").value==400 and field("RallyX").value==300 and field("RallyY").value==850 and field("ConditionalWithdrawal").button_pressed,"reopened panel reads current leash, rally and survival choices")
	check(field("WorkingAmmoReserve").value==7,"reopened panel displays current working reserve instead of a zero default")
	if not press("Set round reserve"):return
	check(options(str(source.id))==before_options,"applying displayed unchanged reserve cannot reset stored rounds or unrelated options")
	var weapon_group=field("WeaponGroup")
	weapon_group.select(1);weapon_group.item_selected.emit(1)
	check(field("WorkingAmmoReserve").value==7,"selecting a weapon family reads that family's actual mount reserve")
	field("WorkingAmmoReserve").value=3
	if not press("Set round reserve"):return
	var mounts: Array=game.Battle.tactical_status(game.battle,str(source.id)).mounts
	for mount in mounts:check(int(options(str(source.id)).mounts[str(mount.id)].reserve)==(3 if str(mount.kind)=="gun" else 7),"family reserve changes only the actual matching mount ID: "+str(mount.id))
	weapon_group=field("WeaponGroup");weapon_group.select(2);weapon_group.item_selected.emit(2)
	if not press("Fire automatically"):return
	check(field("WeaponGroup").selected==2 and field("WorkingAmmoReserve").value==7,"applying a family choice retains its picker and current reserve")
	for mount in mounts:check(bool(options(str(source.id)).mounts[str(mount.id)].hold)==(str(mount.kind)!="cannon"),"family hold changes only the actual matching mount ID: "+str(mount.id))
	weapon_group=field("WeaponGroup");weapon_group.select(0);weapon_group.item_selected.emit(0)
	check(field("WorkingAmmoReserve").get_line_edit().text.is_empty() and "Mixed" in field("AutomaticWeaponState").text,"different per-mount hold/reserve choices display their actual mixed state")
	var distinct: Dictionary=options(str(source.id)).duplicate(true)
	if not press("Set round reserve"):return
	check(options(str(source.id))==distinct,"untouched mixed family reserve does not homogenize mounted stores")
	# Different roles and reserves must be represented without silently choosing one.
	game.select_battle_boat(str(ally.id))
	field("TacticalRole").select(5)
	if not press("Assign role"):return
	game.select_battle_boat(str(source.id));game.select_battle_boat(str(ally.id),true)
	if not reopen_options():return
	await process_frame
	var mixed_role=field("TacticalRole")
	check("Mixed" in mixed_role.get_item_text(mixed_role.selected),"mixed selection is represented in the actual role selector")
	check("Mixed" in labels(),"actual mixed-selection explanation is visible in the native sheet")
	var protected_mixed=field("ProtectedAlly")
	check("Mixed" in protected_mixed.get_item_text(protected_mixed.selected),"mixed protected allies are explicit in the actual picker")
	for name in ["TacticalLeash","RallyX","RallyY","WorkingAmmoReserve"]:
		check(field(name).get_line_edit().text.is_empty() and field(name).get_line_edit().placeholder_text=="Mixed","mixed numeric choice remains visibly unassigned after a native frame: "+name)
	check("Mixed" in field("ConditionalWithdrawal").text,"mixed survival permission is explicit")
	var mixed_before: Array=[options(str(source.id)).duplicate(true),options(str(ally.id)).duplicate(true)]
	if not press("Assign role"):return
	if not press("Set round reserve"):return
	if not press("Protect this ally"):return
	if not press("Set escort distance"):return
	if not press("Set rally"):return
	check(options(str(source.id))==mixed_before[0] and options(str(ally.id))==mixed_before[1],"untouched mixed controls preserve each boat's distinct options")
	game.select_battle_boat(str(source.id))
	if not reopen_options():return
	if not press("Save group 1"):return
	game.select_battle_boat(str(ally.id))
	if not press("Select group 1"):return
	check(game.selected_battle_ids==[source.id],"actual save/recall restores current living selection")
	if not press("Withdraw selected to rally"):return
	check(source.order=="withdraw" and game.battle.retreatTimer==null,"selected rally order is distinct from fleet withdrawal")
	if not press("Close"):return
	key(KEY_U)
	check(not game.battle.autopilot,"real U input takes manual authority after queued withdraw")
	for pause_before in [false,true]:
		game.paused=pause_before
		key(KEY_TAB)
		check(game.tactical_mode and game.paused and game.battle.autopilot,"actual Tab pauses tactical overview temporarily")
		key(KEY_TAB)
		check(not game.tactical_mode and game.paused==pause_before and not game.battle.autopilot,"Tab restores prior pause and manual authority")
	game.paused=true
	# Real projected right-click routing without sending any OS mouse input.
	game.select_battle_boat(str(source.id))
	# Keep this open-water click outside the actual 42px boat-picking radius.
	game.order_at(game.chart.project(Vector2(1100,850)))
	check(source.order=="move" and absf(float(source.orderTarget.get("x",0))-1100.0)<0.01,"Main water order routes to canonical move")
	game.order_at(game.chart.project(Vector2(enemy.x,enemy.y)))
	check(source.order=="attack" and source.orderTarget.get("shipId")==enemy.id,"Main enemy order routes to explicit target")
	game.order_at(game.chart.project(Vector2(ally.x,ally.y)))
	check(source.order=="escort" and source.orderTarget.get("shipId")==ally.id,"Main ally order routes to named escort")
	if not press("3 · Hold"):return
	check(source.order=="hold","real hold button cancels prior approach")
	if not press("1 · Engage"):return
	check(source.order=="engage","real engage button returns group autonomy")
	if not press("Withdraw fleet"):return
	check(game.battle.autopilot and game.battle.retreatTimer!=null,"actual fleet withdrawal button engages automatic helm")
	key(KEY_U)
	check(not game.battle.autopilot,"real U retakes manual after fleet withdrawal")
	game.ui.update_hud()
	check("Fleet withdrawal" in labels() and "12" in labels(),"current UI names the finite fleet timer plainly")
	for tick in range(12):game.Battle.update(game.battle,1.0/30.0,{"manual":true,"forward":true})
	game.ui.update_hud()
	check(not str(game.ui.tactical_intent_label.text).is_empty(),"actual selected HUD exposes intent/blocked reason")
	check(career.state==saved,"tactical controls, options, orders and actual lab movement leave the paid career EXACT")
	observations.append({"case":"main-controls","time":game.battle.time,"selected":game.selected_battle_ids.duplicate(),"options":options(str(source.id)),"fleetTimer":game.battle.retreatTimer})
	game.Damage.apply_hit(ally,{"damage":1000000.0,"kind":"shell"},game.battle.rng)
	key(KEY_F3)
	check(ally.sunk and game.selected_battle_ids==[source.id],"group recall drops an actually destroyed hull and preserves its living member")
	game.return_to_campaign();game.paused=true
	check(game.core==career and career.state==saved,"leaving battle restores untouched career identity and property")
	finite_outcomes(career,saved)

func finite_outcomes(career,saved: Dictionary) -> void:
	game.open_lab()
	game.lab_config={"player":[Lab.entry(game.data,"tin_skiff")],"enemy":[Lab.entry(game.data,"iron_bastion")]}
	game.lab_seed=30012;game.start_lab()
	var source: Dictionary=game.Battle.get_flagship(game.battle)
	var enemy: Dictionary=game.battle.ships.filter(func(ship):return ship.team=="enemy")[0]
	# Initial synthetic condition only; no later refills, timer edits or forced fire.
	source.x=500.0;source.y=850.0;source.angle=0.0;source.ammo=12.0
	source.hp-=5.0;source.water=30.0;source.fire=5.0
	enemy.x=760.0;enemy.y=850.0;enemy.spec.speed=0.0;enemy.ammo=0.0
	game.battle.islands=[];game.battle.autoBoard=false
	if not press("Patch & repair"):return
	check(source.policy=="repair","real crew-priority button changes the actual flagship duty allocation")
	if not press("Selected tactics & weapon groups"):return
	if not press("Hold automatic fire"):return
	var ammo: float=float(source.ammo);var water: float=float(source.water);var hp: float=float(source.hp);var kits: float=float(source.supplies);var fire: float=float(source.fire)
	game.paused=false
	game._physics_process(1.0/30.0)
	check(game.battle.time==0.0,"Main physics callback respects the actual open modal gate")
	game.ui.close_modal()
	game.paused=true;game._physics_process(1.0/30.0)
	check(game.battle.time==0.0,"Main physics callback respects the actual pause gate")
	game.paused=false
	for tick in range(15):game._physics_process(1.0/30.0)
	check(game.battle.time>0.49 and float(source.ammo)==ammo and game.Battle.mount_shot_time(source,0)<0.0,"real Main updates advance time while UI-held automatic gun emits and spends nothing")
	check(game.Damage.get_status(source).get("equipmentMode","")=="canonical" and float(source.fire)>0.0 and float(source.fire)<fire and float(source.water)<water and float(source.hp)<=hp and float(source.supplies)==kits,"canonical crew-priority callback allocates finite crew work fire-first while bailing without spending kits")
	for tick in range(75):game._physics_process(1.0/30.0)
	check(game.battle.time>2.99 and float(source.fire)==0.0,"canonical fire-first crew work extinguishes active fire before paid hull repair")
	check(float(source.water)<water and float(source.hp)>hp and float(source.supplies)<kits,"actual crew-priority callback produces bailing and paid finite-kit repair")
	game.paused=true
	if not press("Selected tactics & weapon groups"):return
	field("WorkingAmmoReserve").value=12
	if not press("Set round reserve"):return
	if not press("Fire automatically"):return
	game.ui.close_modal();game.paused=false
	for tick in range(15):game._physics_process(1.0/30.0)
	check(float(source.ammo)==ammo and game.Battle.mount_shot_time(source,0)<0.0,"UI reserve independently blocks a now-unheld reachable automatic gun")
	game.paused=true
	if not press("Selected tactics & weapon groups"):return
	field("WorkingAmmoReserve").value=11
	if not press("Set round reserve"):return
	game.ui.close_modal()
	var automatic: Array=[]
	for tick in range(15):
		game.Battle.update(game.battle,1.0/30.0)
		for event in game.Battle.pop_events(game.battle):
			if event.kind=="fire" and str(event.sourceId)==str(source.id):automatic.append(event.duplicate(true))
	check(automatic.size()==1 and is_equal_approx(ammo-float(source.ammo),float(automatic.size())) and source.ammo==11.0,"lowering reserve through UI permits one real automatic shot with its exact event debit")
	ammo=float(source.ammo)
	game.paused=true
	if not press("Selected tactics & weapon groups"):return
	if not press("Hold automatic fire"):return
	game.ui.close_modal();key(KEY_U)
	var click: InputEventMouseButton=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	game._unhandled_input(click)
	check(not game.battle.autopilot and game.fire_held,"actual manual mouse callback arms the flagship trigger after U")
	var start: Vector2=Vector2(source.x,source.y)
	var events: Array=[]
	var cooldown_before: float=float(source.cooldown)
	var manual_trace: Array=[]
	# Repair duty reduces gun crew, so observe its real cooldown without editing it.
	for tick in range(45):
		var turn: float=angle_difference(float(source.angle),Vector2(enemy.x-source.x,enemy.y-source.y).angle())
		game.Battle.update(game.battle,1.0/30.0,{"manual":not game.battle.autopilot,"forward":absf(turn)<0.8,"right":turn>0.04,"left":turn< -0.04,"fire":game.fire_held,"aimX":enemy.x,"aimY":enemy.y})
		if tick in [0,31,32,44]:manual_trace.append({"tick":tick,"time":game.battle.time,"cooldown":source.cooldown,"mountCooldowns":source.weaponCooldowns.duplicate(),"weaponFactor":game.Damage.get_status(source).weaponFactor,"fireHeld":game.fire_held,"manualId":game.battle.tactical.manualId,"sourceId":source.id,"distance":Vector2(source.x-enemy.x,source.y-enemy.y).length(),"angle":source.angle,"shipPos":Vector2(source.x,source.y),"enemyPos":Vector2(enemy.x,enemy.y),"ammo":source.ammo})
		for event in game.Battle.pop_events(game.battle):
			if event.kind=="fire" and str(event.sourceId)==str(source.id):events.append(event.duplicate(true))
	check(not events.is_empty() and is_equal_approx(ammo-float(source.ammo),float(events.size())),"real manual firing overrides UI auto-hold/reserve and debits exactly actual whole-round events")
	check(Vector2(source.x,source.y).distance_to(start)>10.0 and float(source.fuel)<120.0,"manual retake has real finite-fuel helm motion")
	click.pressed=false;game._input(click)
	check(not game.fire_held,"Main release callback clears the manual trigger")
	key(KEY_TAB);key(KEY_U);key(KEY_TAB)
	check(not game.battle.autopilot and not game.tactical_mode,"explicit manual U choice inside tactical overview survives Tab restoration")
	key(KEY_TAB);key(KEY_U);key(KEY_U);key(KEY_TAB)
	check(game.battle.autopilot and not game.tactical_mode,"explicit automatic U choice inside tactical overview survives Tab restoration")
	check(game.career_core==career and career.state==saved,"UI-driven shots, repair and motion conserve the separate paid career exactly")
	observations.append({"case":"native-outcomes","time":game.battle.time,"ammo":source.ammo,"actualAutomaticFireEvents":automatic,"actualManualFireEvents":events,"cooldownBeforeManual":cooldown_before,"manualTrace":manual_trace,"waterBefore":water,"waterAfter":source.water,"hpBefore":hp,"hpAfter":source.hp,"kitsBefore":kits,"kitsAfter":source.supplies,"manualDistance":Vector2(source.x,source.y).distance_to(start)})
	game.return_to_campaign();game.paused=true

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()!="headless":check(false,"requires background/headless/Dummy lease")
	else:
		game=load("res://main.tscn").instantiate();root.add_child(game)
		game.set_process(false);game.set_physics_process(false)
		game.audio.enabled=false;game.music.enabled=false
		game.save_directory=OS.get_user_data_dir().path_join("tactical-ui-%d"%Time.get_ticks_usec())
		await process_frame
		game.new_game();game.paused=true
		await exercise()
		game.queue_free();await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file: FileAccess=FileAccess.open(arg.substr(6),FileAccess.WRITE)
			if file!=null:file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations}));file.close()
	print("tactical UI: %d checks, %d failures; real Main controls, no desktop input"%[checks,failures])
	quit(0 if failures==0 else 1)
