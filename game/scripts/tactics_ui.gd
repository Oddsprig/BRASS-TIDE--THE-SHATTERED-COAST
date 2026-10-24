extends RefCounted
const Deployment = preload("res://scripts/deployment.gd")

static func build(ui, size: Vector2):
	# Fleet/status controls stay reachable at smaller logical viewport heights.
	var frame: Node=ui.right_body.get_parent()
	frame.remove_child(ui.right_body)
	var body_scroll=ScrollContainer.new()
	body_scroll.custom_minimum_size=Vector2(300,maxf(260.0,size.y-230.0))
	body_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(body_scroll);body_scroll.add_child(ui.right_body)
	ui.right_body.custom_minimum_size=Vector2(260,0)
	ui.right_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	ui.eyebrow(ui.left_body, "FLAGSHIP · DAMAGE CONTROL")
	ui.flagship_label = ui.paragraph(ui.left_body, "", 24, ui.TEXT)
	ui.hull_bar = ui.progress(ui.left_body, ui.TEAL)
	ui.flood_bar = ui.progress(ui.left_body, Color("74b7da"))
	ui.damage_label = ui.label(ui.left_body, "", 12, ui.MUTED)
	ui.rule(ui.left_body)
	ui.eyebrow(ui.left_body, "CREW PRIORITY")
	for pair in [["balanced","Balanced"],["bail","Bail water"],["repair","Patch & repair"],["fight","Guns first"]]:
		var policy: String = pair[0]
		var b = ui.button(ui.left_body, pair[1], func(): ui.host.set_crew_policy(policy))
		b.custom_minimum_size.y = 30
		b.add_theme_font_size_override("font_size", 12)
		ui.policy_buttons[policy] = b
	ui.paragraph(ui.left_body, "Bailing needs hands. Patching needs hands and repair kits.", 12)
	ui.eyebrow(ui.right_body, "FLEET COMMAND")
	ui.objective_label=ui.paragraph(ui.right_body,preload("res://scripts/battle_objectives.gd").label(ui.host.battle),15,ui.GOLD)
	ui.paragraph(ui.right_body, ui.host.battle.location.get("name","Coastal waters"), 22, ui.TEXT)
	ui.battle_points_label = ui.paragraph(ui.right_body, "", 15, ui.GOLD)
	ui.autopilot_button = ui.button(ui.right_body, "", ui.host.toggle_autopilot, true)
	ui.button(ui.right_body, "Tab · Tactical overview", ui.host.toggle_tactical)
	ui.button(ui.right_body, "Select all active boats", ui.host.select_all_boats)
	ui.button(ui.right_body,"Selected tactics & weapon groups",func():options(ui))
	ui.tactical_intent_label=ui.paragraph(ui.right_body,"",13,ui.TEXT)
	ui.button(ui.right_body,"Boarding orders",func():ui.BoardingUI.battle(ui))
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.right_body.add_child(scroll)
	ui.battle_fleet = ui.column(scroll)
	for boat in ui.host.battle.ships:
		if boat.team == "player":
			var id: String = boat.id
			var b = ui.button(ui.battle_fleet, "%s · %d DP" % [boat.name,Deployment.cost(boat)], func():ui.host.select_battle_boat(id,Input.is_key_pressed(KEY_SHIFT)))
			b.add_theme_font_size_override("font_size", 12)
			b.custom_minimum_size.y = 30
	ui.battle_control_label = ui.paragraph(ui.right_body, "", 12)
	var bottom = ui.panel(ui.chrome, Vector2(0,size.y-90), Vector2(size.x,90))
	var actions = ui.row(bottom)
	ui.label(actions, "SELECTED ORDERS", 10, ui.GOLD)
	for pair in [["engage","1 · Engage"],["escort","2 · Escort"],["hold","3 · Hold"]]:
		var order: String = pair[0]
		ui.button(actions,pair[1],func():ui.host.command_selected(order))
	ui.voyage_label = ui.label(actions,"",12,ui.MUTED)
	ui.voyage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.voyage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.button(actions,"Withdraw fleet ↗",ui.host.withdraw_fleet)

static func update(ui):
	var battle: Dictionary = ui.host.battle
	if is_instance_valid(ui.objective_label):ui.objective_label.text=preload("res://scripts/battle_objectives.gd").label(battle)
	var player: Array = battle.ships.filter(func(s):return s.team=="player" and not s.sunk and not s.get("captureSecured",false))
	var enemy: Array = battle.ships.filter(func(s):return s.team=="enemy" and not s.sunk)
	ui.battle_points_label.text = "YOUR FLEET  %d / 300 DP\nENEMY FLEET  %d / 300 DP" % [Deployment.total(player),Deployment.total(enemy)]
	ui.autopilot_button.text = "U · AUTOPILOT ON" if battle.get("autopilot",true) else "U · MANUAL FLAGSHIP"
	ui.battle_control_label.text = "WASD  Camera · Shift  Fast pan\nSCROLL  Zoom · HOME  Center\nCLICK / DRAG  Select · SHIFT  Add\nRIGHT-CLICK  Move / attack / escort\nSPACE  Pause · X  Change flagship\n" + ("ARROWS + MOUSE  Manual control" if not battle.get("autopilot",true) else "All boats steer and fire automatically.")
	if is_instance_valid(ui.tactical_intent_label):
		var lines: Array=[]
		for id in ui.host.selected_battle_ids:
			var status: Dictionary=ui.host.Battle.tactical_status(battle,str(id))
			if status.is_empty():continue
			var name: String="Boat"
			for boat in battle.ships:
				if str(boat.id)==str(id):name=str(boat.name);break
			lines.append(name+" · "+plain(str(status.reason)))
			if not str(status.targetName).is_empty():lines.append("Watching "+str(status.targetName))
			var index: int=0
			for mount in status.mounts:
				index+=1
				var reason: String=str(status.weapons.get(str(mount.id),"Waiting for a firing opportunity"))
				lines.append("%s %d · %s"%[str(mount.kind).capitalize(),index,plain(reason)])
			break # Full selected-group controls live in the scrollable options sheet.
		ui.tactical_intent_label.text="\n".join(lines) if not lines.is_empty() else "Select a boat to see its intent."

static func plain(value: String) -> String:
	return value.replace("certified launch","clear shot").replace("certified","checked").replace("certificate","maneuver check").left(180)

static func selected_choices(ui) -> Dictionary:
	var states: Array=[]
	for id in ui.host.selected_battle_ids:
		var status: Dictionary=ui.host.Battle.tactical_status(ui.host.battle,str(id))
		if not status.is_empty():states.append(status)
	var current: Dictionary=states[0].options if not states.is_empty() else {}
	var mixed: Array=[]
	for state in states:
		for key in current:
			if state.options.get(key)!=current[key] and not key in mixed:mixed.append(key)
	return {"states":states,"current":current,"mixed":mixed}

static func apply_choices(ui,patch: Dictionary) -> void:
	if ui.host.set_selected_tactical_options(patch):options(ui,str(patch.get("mountGroup",{}).get("kind","all")))

static func number_choice(control: SpinBox,mixed: bool) -> Array:
	# An untouched mixed field must not publish the first boat's value to others.
	var edited: Array=[not mixed]
	if mixed:
		control.get_line_edit().text=""
		control.get_line_edit().placeholder_text="Mixed"
	control.value_changed.connect(func(_value):edited[0]=true)
	control.get_line_edit().text_changed.connect(func(_text):edited[0]=true)
	return edited

static func options(ui,weapon_kind: String="all") -> void:
	ui.modal_kind="tactical_options"
	var body=ui.modal("Selected fleet tactics","ORDERS · FORMATIONS · AUTOMATIC FIRE",1040,850)
	ui.paragraph(body,"These choices apply together to the selected living boats. Direct manual helm and fire take priority. Hold and reserve apply to automatic fire. Manual fire uses your aim and available rounds.",16)
	var selection: Dictionary=selected_choices(ui)
	var current: Dictionary=selection.current
	var mixed: Array=selection.mixed
	if not mixed.is_empty():ui.paragraph(body,"Mixed choices across selected boats. Choose a value to change it; untouched mixed fields keep each boat's choices.",14,ui.GOLD)
	ui.label(body,"Courage and survival",21,ui.GOLD,true)
	var profiles=ui.row(body)
	for item in [["cautious","Cautious"],["steady","Steady"],["aggressive","Aggressive"]]:
		var doctrine: String=item[0]
		ui.button(profiles,item[1],func():apply_choices(ui,{"doctrine":doctrine}),not "doctrine" in mixed and current.get("doctrine","")==doctrine)
	ui.paragraph(body,"Cautious boats leave danger sooner. Steady balances pressure and survival. Aggressive stays longer; crew, fuel, damage and weapon performance remain physical.",13)
	var role_ids: Array=["auto","skirmisher","striker","heavy","screen","support"]
	var roles=OptionButton.new();roles.name="TacticalRole"
	for title in ["Choose role automatically","Light skirmisher","Fixed-tube striker","Heavy gunboat","Protecting screen","Support"]:roles.add_item(title)
	roles.selected=maxi(0,role_ids.find(str(current.get("role","auto"))))
	if "role" in mixed:roles.add_item("Mixed roles");roles.selected=role_ids.size()
	var role_row=ui.row(body);role_row.add_child(roles)
	ui.button(role_row,"Assign role",func():
		if roles.selected<role_ids.size():apply_choices(ui,{"role":str(role_ids[roles.selected])}))
	ui.label(body,"Formation and protected ally",21,ui.GOLD,true)
	var formation_row=ui.row(body)
	for kind in ["line","screen","column"]:
		var formation: String=kind
		ui.button(formation_row,formation.capitalize(),func():apply_choices(ui,{"formation":formation}),not "formation" in mixed and current.get("formation","")==formation)
	var allies=OptionButton.new();allies.name="ProtectedAlly"
	var ally_ids: Array=[""]
	allies.add_item("Choose ally automatically")
	for boat in ui.host.battle.ships:
		if boat.team=="player" and not boat.sunk and not boat.get("captureSecured",false):
			ally_ids.append(str(boat.id));allies.add_item(str(boat.name))
	allies.selected=maxi(0,ally_ids.find(str(current.get("protectedAllyId",""))))
	if "protectedAllyId" in mixed:allies.add_item("Mixed protected allies");allies.selected=ally_ids.size()
	var ally_row=ui.row(body);ally_row.add_child(allies)
	ui.button(ally_row,"Protect this ally",func():
		if allies.selected<ally_ids.size():apply_choices(ui,{"protectedAllyId":str(ally_ids[allies.selected])}))
	var leash=SpinBox.new();leash.name="TacticalLeash";leash.min_value=80;leash.max_value=2300;leash.step=20;leash.value=float(current.get("leash",600))
	var leash_row=ui.row(body);ui.label(leash_row,"Stay within",14);leash_row.add_child(leash)
	var leash_edited: Array=number_choice(leash,"leash" in mixed)
	ui.button(leash_row,"Set escort distance",func():
		if leash_edited[0]:apply_choices(ui,{"leash":float(leash.value)}))
	ui.label(body,"Rally and conditional withdrawal",21,ui.GOLD,true)
	var flagship: Dictionary=ui.host.Battle.get_flagship(ui.host.battle)
	var rally: Dictionary=current.get("rally",{})
	var x=SpinBox.new();x.name="RallyX";x.min_value=30;x.max_value=2270;x.value=float(rally.get("x",flagship.get("x",300)))
	var y=SpinBox.new();y.name="RallyY";y.min_value=30;y.max_value=1670;y.value=float(rally.get("y",flagship.get("y",850)))
	var rally_row=ui.row(body);ui.label(rally_row,"Water position",14);rally_row.add_child(x);rally_row.add_child(y)
	var x_edited: Array=number_choice(x,"rally" in mixed)
	var y_edited: Array=number_choice(y,"rally" in mixed)
	ui.button(rally_row,"Set rally",func():
		if x_edited[0] and y_edited[0]:apply_choices(ui,{"rally":{"x":float(x.value),"y":float(y.value)}}))
	ui.button(rally_row,"Withdraw selected to rally",func():ui.host.command_selected("withdraw"))
	var conditional=CheckButton.new();conditional.name="ConditionalWithdrawal";conditional.text="Allow survival withdrawal during explicit orders";conditional.button_pressed=bool(current.get("conditionalWithdrawal",false));body.add_child(conditional)
	if "conditionalWithdrawal" in mixed:conditional.text+=" (Mixed)"
	conditional.toggled.connect(func(value: bool):apply_choices(ui,{"conditionalWithdrawal":value}))
	ui.paragraph(body,"A rally is a local water position. A blocked approach may force a boat to brake and hold. Pale selected route lines show a planned exit. Fleet withdrawal is a separate fleet command.",13)
	ui.label(body,"Automatic weapon groups and working ammunition",21,ui.GOLD,true)
	var groups=OptionButton.new();groups.name="WeaponGroup"
	var kinds: Array=["all","gun","cannon","rocket","torpedo"]
	for title in ["All fitted weapons","Machine guns","Cannons","Rockets","Torpedo tubes"]:groups.add_item(title)
	groups.selected=maxi(0,kinds.find(weapon_kind))
	var weapon_row=ui.row(body);weapon_row.add_child(groups)
	ui.button(weapon_row,"Fire automatically",func():apply_choices(ui,{"mountGroup":{"kind":str(kinds[groups.selected]),"hold":false}}))
	ui.button(weapon_row,"Hold automatic fire",func():apply_choices(ui,{"mountGroup":{"kind":str(kinds[groups.selected]),"hold":true}}))
	var weapon_state=ui.paragraph(body,"",14,ui.GOLD);weapon_state.name="AutomaticWeaponState"
	var reserve=SpinBox.new();reserve.name="WorkingAmmoReserve";reserve.min_value=0;reserve.max_value=1000000;reserve.step=1
	var reserve_edited: Array=number_choice(reserve,false)
	var reserve_row=ui.row(body);ui.label(reserve_row,"Keep aboard after automatic shots",14);reserve_row.add_child(reserve)
	var refresh_weapons=func(_index: int=0):
		var values: Array=[]
		for state in selected_choices(ui).states:
			for mount in state.mounts:
				if kinds[groups.selected]=="all" or str(mount.kind)==str(kinds[groups.selected]):values.append(state.options.mounts.get(str(mount.id),{"hold":false,"reserve":0}))
		var same_reserve: bool=not values.is_empty()
		var same_hold: bool=not values.is_empty()
		for value in values:
			if value.reserve!=values[0].reserve:same_reserve=false
			if value.hold!=values[0].hold:same_hold=false
		reserve.value=float(values[0].reserve) if same_reserve else 0.0
		reserve.get_line_edit().placeholder_text="Mixed" if not values.is_empty() else "No fitted weapons"
		if not same_reserve:reserve.get_line_edit().text=""
		reserve_edited[0]=same_reserve
		weapon_state.text=("Automatic fire: "+("held" if values[0].hold else "active") if same_hold else "Automatic fire: Mixed") if not values.is_empty() else "No fitted weapons in this group."
	groups.item_selected.connect(refresh_weapons)
	refresh_weapons.call()
	ui.button(reserve_row,"Set round reserve",func():
		if reserve_edited[0]:apply_choices(ui,{"mountGroup":{"kind":str(kinds[groups.selected]),"reserve":int(reserve.value)}}))
	ui.label(body,"Four saved selections",21,ui.GOLD,true)
	ui.paragraph(body,"Selections last for this battle. F1–F4 selects a group; Ctrl+F1–F4 saves the current selection. Number keys 1, 2 and 3 keep their existing orders.",13)
	for number in range(1,5):
		var slot: int=number
		var line=ui.row(body)
		ui.button(line,"Save group %d"%slot,func():ui.host.save_selection_group(slot))
		ui.button(line,"Select group %d"%slot,func():
			if ui.host.recall_selection_group(slot):options(ui))
	ui.button(body,"Close",ui.close_modal,true)
