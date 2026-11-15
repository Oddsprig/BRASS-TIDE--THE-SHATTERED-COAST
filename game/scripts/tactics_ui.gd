extends RefCounted
const Deployment = preload("res://scripts/deployment.gd")
const PressureView = preload("res://scripts/combat_pressure_view044.gd")

class MiniMap103 extends Control:
	var host
	func _process(_dt: float) -> void:queue_redraw()
	func _draw() -> void:
		if host!=null and not host.battle.is_empty():
			host.chart.paint_battle_minimap103(self,Rect2(Vector2.ZERO,size))

static func build(ui, size: Vector2):
	# Four shallow occupied bands, with no invisible sidebar frames over the chart.
	# Main rebuilds on resize; labels/buttons never set an unbounded minimum width.
	ui.battle_details_label=null
	ui.battle_fleet=null
	var top=compact_panel(ui,"BattleTop",Rect2(0,0,size.x,52))
	var nav=ui.row(top);nav.add_theme_constant_override("separation",6)
	compact_button(ui,nav,"BRASS TIDE",ui.open_menu)
	ui.stats_label=ui.label(nav,"",13,ui.TEXT)
	ui.stats_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	ui.stats_label.clip_text=true
	ui.stats_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	ui.clock_label=ui.label(nav,"",12,ui.GOLD)
	var pause=compact_button(ui,nav,"Pause",ui.host.toggle_pause)
	pause.name="BattlePause";pause.tooltip_text="Space pauses; WASD still moves the camera."
	compact_button(ui,nav,"1× / 4×",func():ui.host.speed=4 if ui.host.speed==1 else 1)
	compact_button(ui,nav,"Tab · Overview",ui.host.toggle_tactical)
	compact_button(ui,nav,"Roster & crew",func():details(ui)).name="BattleDetails"
	compact_button(ui,nav,"Selected tactics & weapon groups",func():options(ui)).name="BattleTactics"
	ui.autopilot_button=compact_button(ui,nav,"",ui.host.toggle_autopilot,true)
	ui.autopilot_button.name="BattleAutopilot"
	var mission=compact_panel(ui,"BattleMission",Rect2(12,60,size.x-24,52))
	var mission_row=ui.row(mission)
	ui.left_body=ui.column(mission_row);ui.left_body.add_theme_constant_override("separation",2)
	ui.objective_label=limited_label(ui,ui.left_body,14,ui.GOLD,2)
	ui.battle_points_label=ui.label(mission_row,"",12,ui.GOLD)
	ui.battle_points_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var status=compact_panel(ui,"BattleStatus",Rect2(12,size.y-192,size.x-24,132))
	var status_row=ui.row(status);status_row.add_theme_constant_override("separation",16)
	var selected=ui.column(status_row)
	selected.custom_minimum_size.x=300
	selected.size_flags_horizontal=Control.SIZE_FILL
	selected.add_theme_constant_override("separation",3)
	ui.flagship_label=ui.label(selected,"",18,ui.TEXT)
	ui.flagship_label.clip_text=true
	ui.flagship_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	ui.hull_bar=ui.progress(selected,ui.TEAL)
	ui.flood_bar=ui.progress(selected,Color("74b7da"))
	ui.damage_label=limited_label(ui,selected,12,ui.MUTED,2)
	var crew=ui.row(selected);crew.add_theme_constant_override("separation",4)
	ui.battle_crew_label=ui.label(crew,"FLAGSHIP CREW",10,ui.GOLD)
	for pair in [["balanced","Balanced"],["bail","Bail"],["repair","Repair"],["fight","Guns"]]:
		var policy: String=pair[0]
		var choice=compact_button(ui,crew,pair[1],func():ui.host.set_crew_policy(policy))
		choice.custom_minimum_size.y=26
		choice.add_theme_font_size_override("font_size",11)
		choice.tooltip_text="Flagship crew priority: "+str({"balanced":"balanced work","bail":"bail water","repair":"patch and repair using actual kits","fight":"guns first"}[policy])
		ui.policy_buttons[policy]=choice
	ui.right_body=ui.column(status_row);ui.right_body.add_theme_constant_override("separation",4)
	ui.voyage_label=limited_label(ui,ui.right_body,12,ui.GOLD,1)
	ui.tactical_intent_label=limited_label(ui,ui.right_body,13,ui.TEXT,2)
	ui.battle_reload_label=limited_label(ui,ui.right_body,12,ui.MUTED,2)
	ui.battle_reload_label.name="BattleReload"
	ui.battle_control_label=limited_label(ui,ui.right_body,12,ui.MUTED,2)
	ui.battle_control_label.name="BattleAcknowledgment"
	var minimap=MiniMap103.new()
	minimap.name="BattleMinimap"
	minimap.host=ui.host
	minimap.custom_minimum_size=Vector2(190,100)
	minimap.size_flags_vertical=Control.SIZE_EXPAND_FILL
	minimap.mouse_filter=Control.MOUSE_FILTER_IGNORE
	status_row.add_child(minimap)
	var orders=compact_panel(ui,"BattleOrders",Rect2(12,size.y-52,size.x-24,44))
	var actions=ui.row(orders);actions.add_theme_constant_override("separation",6)
	ui.label(actions,"SELECTED",10,ui.GOLD)
	for pair in [["engage","Engage"],["harass","Harass"],["focus","Focus attack"],["escort","Escort"],["defend","Defend"],["rally","Rally"],["hold","Hold"],["withdraw","Withdraw"]]:
		var command: String=pair[0]
		var action=compact_button(ui,actions,pair[1],func():ui.host.request_battle_command(command))
		action.name="BattleCommand_"+command
		action.tooltip_text=str({"engage":"Steady automatic engagement.","harass":"Cautious skirmishing pressure, without a locked target.","focus":"Right-click an enemy for a focused attack.","escort":"Right-click the allied boat to protect.","defend":"Right-click water to defend that position and fire within range.","rally":"Right-click water to regroup there, then hold.","hold":"Hold each selected boat at its present position.","withdraw":"Selected boats withdraw toward their rally or home side; this does not end the battle."}[command])
		# Share any spare width without forcing the row beyond a 1280px viewport.
		action.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	compact_button(ui,actions,"Select all",ui.host.select_all_boats).name="BattleSelectAll"

static func compact_panel(ui, title: String, rectangle: Rect2) -> VBoxContainer:
	var frame=PanelContainer.new();frame.name=title
	frame.position=rectangle.position;frame.size=rectangle.size
	frame.add_theme_stylebox_override("panel",ui.box(Color(0.045,0.12,0.16,0.95),ui.LINE,8))
	ui.chrome.add_child(frame)
	var body=ui.column(frame);body.add_theme_constant_override("separation",4)
	return body

static func compact_button(ui, parent: Node, text: String, action: Callable, primary: bool=false) -> Button:
	var result: Button=ui.button(parent,text,action,primary,false)
	result.custom_minimum_size.y=32
	result.add_theme_font_size_override("font_size",12)
	# World command keys, especially Space, must not activate the last clicked button.
	result.focus_mode=Control.FOCUS_NONE
	for state in ["normal","hover","pressed","disabled"]:
		var style: StyleBox=result.get_theme_stylebox(state).duplicate()
		style.content_margin_left=8;style.content_margin_right=8
		style.content_margin_top=4;style.content_margin_bottom=4
		result.add_theme_stylebox_override(state,style)
	return result

static func limited_label(ui, parent: Node, font_size: int, color: Color, lines: int) -> Label:
	var result: Label=ui.paragraph(parent,"",font_size,color)
	result.max_lines_visible=lines
	result.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	return result

static func update(ui, compact: bool=false):
	var battle: Dictionary = ui.host.battle
	if is_instance_valid(ui.objective_label):
		ui.objective_label.text=preload("res://scripts/battle_objectives.gd").label(battle)
		ui.objective_label.tooltip_text=ui.objective_label.text
	var player: Array = battle.ships.filter(func(s):return s.team=="player" and not s.sunk and not s.get("captureSecured",false))
	var enemy: Array = battle.ships.filter(func(s):return s.team=="enemy" and not s.sunk)
	var reserves: Array=battle.get("reserves",{}).get("player",[])
	var limit: int=int(battle.get("deployment",{}).get("limit",Deployment.LIMIT))
	ui.battle_points_label.text = "YOU %d/%d DP · ENEMY %d/%d DP · %d reserve" % [Deployment.total(player),limit,Deployment.total(enemy),limit,reserves.size()]
	ui.battle_points_label.tooltip_text="Active boats only. Deployment has a %d DP limit per side; ownership is separate. Reserved boats remain outside this engagement."%limit
	ui.autopilot_button.text = "U · AUTOPILOT ON" if battle.get("autopilot",true) else "U · MANUAL FLAGSHIP"
	if not compact:ui.battle_control_label.text = "WASD  Camera · Shift  Fast pan\nSCROLL  Zoom · HOME  Center\nCLICK / DRAG  Select · SHIFT  Add\nRIGHT-CLICK  Move / attack / escort\nSPACE  Pause · X  Change flagship\n" + ("ARROWS + MOUSE  Manual control" if not battle.get("autopilot",true) else "All boats steer and fire automatically.")
	if is_instance_valid(ui.tactical_intent_label):
		var lines: Array=[]
		var selection: Dictionary=PressureView.selection(battle,ui.host.selected_battle_ids)
		var boat: Dictionary=selection.boat
		var status: Dictionary=ui.host.Battle.tactical_status(battle,str(boat.id)) if not boat.is_empty() else {}
		var flow: Dictionary={}
		var weapons: Array=[]
		if not status.is_empty():
			flow=ui.host.Damage.get_status_cached(boat,battle.get("tactical",{}).get("damageCache"))
			lines.append("SELECTED · "+str(boat.name)+(" (1 of %d)"%selection.count if int(selection.count)>1 else ""))
			lines.append(plain(str(status.reason)))
			lines.append_array(PressureView.readiness(boat,flow))
			if not str(status.targetName).is_empty():lines.append("Watching "+str(status.targetName))
			var index: int=0
			for mount in status.mounts:
				var reason: String=str(status.weapons.get(str(mount.id),"Waiting for a firing opportunity"))
				var state: String=PressureView.weapon_state(boat,mount,index,flow,plain(reason))
				lines.append("%s %d · %s"%[str(mount.kind).capitalize(),index+1,state])
				weapons.append("%s %d · %s"%[str(mount.kind).capitalize(),index+1,compact_weapon_status106(state)])
				index+=1
		var expanded: String="\n".join(lines) if not lines.is_empty() else "Select a boat to see its intent."
		if compact:update_compact(ui,selection,status,flow,weapons,expanded,player.size(),enemy.size())
		else:ui.tactical_intent_label.text=expanded

static func update_compact(ui, selection: Dictionary, status: Dictionary, flow: Dictionary, weapons: Array, expanded: String, friendly_count: int, enemy_count: int) -> void:
	var battle: Dictionary=ui.host.battle
	var boat: Dictionary=selection.boat
	var crew: int=0
	for member in battle.ships:
		if member.team=="player" and not member.sunk and not member.get("captureSecured",false):crew+=int(member.crew)
	var active_boat_word109: String="boat" if friendly_count==1 else "boats"
	ui.stats_label.text="%d active %s · %d crew"%[friendly_count,active_boat_word109,crew]
	ui.voyage_label.text="%d SELECTED · %d HOSTILE · %s"%[int(selection.count),enemy_count,"AUTOPILOT" if battle.get("autopilot",true) else "MANUAL FLAGSHIP"]
	if not status.is_empty():ui.voyage_label.text="%d SELECTED · %d HOSTILE · %s · %s%s"%[int(selection.count),enemy_count,str(status.role).capitalize(),str(status.order).capitalize()," → "+str(status.targetName) if not str(status.targetName).is_empty() else ""]
	if battle.get("retreatTimer")!=null:ui.voyage_label.text="Fleet withdrawal · %.0f seconds"%float(battle.retreatTimer)
	ui.flagship_label.text=str(boat.name) if not boat.is_empty() else "No boat selected"
	ui.flagship_label.tooltip_text="Condition of the first living selected boat. Select with click/drag; Shift adds boats. Crew priority buttons always act on the flagship."
	ui.hull_bar.value=100.0*float(boat.hp)/maxf(1.0,float(boat.maxHp)) if not boat.is_empty() else 0.0
	ui.flood_bar.value=100.0*float(boat.water)/maxf(1.0,float(boat.capacity)) if not boat.is_empty() else 0.0
	var engine: String="%.0f%%"%(100.0*float(flow.get("engineHp",0.0))) if flow.get("equipmentOk",false) else "unavailable"
	ui.damage_label.text="Hull %d/%d · Water %.0f%%\nCrew %d (%d hurt) · Fire %.0f%% · Engine %s"%[boat.hp,boat.maxHp,ui.flood_bar.value,boat.crew,boat.wounded,boat.fire,engine] if not boat.is_empty() else "Click or drag to select your boats."
	ui.tactical_intent_label.text=plain(str(status.reason)) if not status.is_empty() else "Select a boat to see its intent."
	ui.tactical_intent_label.tooltip_text=expanded
	ui.battle_reload_label.text="  |  ".join(weapons) if not weapons.is_empty() else ("Weapon status unavailable" if status.is_empty() else "No fitted weapons") if not boat.is_empty() else "Reload and weapon limits appear for the selected boat."
	ui.battle_reload_label.tooltip_text=expanded
	var flagship: Dictionary=ui.host.Battle.get_flagship(battle)
	ui.battle_crew_label.tooltip_text="Flagship: "+str(flagship.get("name","none"))+". These four priorities act on its finite crew and kits."
	for policy in ui.policy_buttons:
		var choice: Button=ui.policy_buttons[policy]
		choice.disabled=flagship.is_empty()
		choice.add_theme_color_override("font_color",ui.GOLD if flagship.get("policy","")==policy else ui.TEXT)
	var pending: String=str(ui.host.battle_command_pending)
	var ack: Dictionary=ui.host.battle_command_ack
	ui.battle_control_label.text=str(ack.get("message","WASD camera · Space pause · right-click orders · F1–F4 groups · X flagship"))
	if not ack.is_empty():ui.battle_control_label.text="Last command: "+ui.battle_control_label.text
	if not pending.is_empty():ui.battle_control_label.text+=" · Right-click target; Esc cancels."
	ui.battle_control_label.tooltip_text=ui.battle_control_label.text
	ui.battle_control_label.add_theme_color_override("font_color",ui.GOLD if not pending.is_empty() else (ui.TEAL if ack.get("ok",true) else ui.RED))
	if is_instance_valid(ui.battle_details_label):
		ui.battle_details_label.text=expanded+("\n\n"+damage_detail(boat,flow) if not boat.is_empty() else "")

static func damage_detail(boat: Dictionary, flow: Dictionary) -> String:
	if not flow.get("equipmentOk",false):return "Damage-control status unavailable. Stores: %.1f kits · %.1f fuel · %.1f ammunition"%[boat.supplies,boat.fuel,boat.ammo]
	return "Hull %d/%d · Water %.0f%% · Holes %d · Fire %.0f%%\nInflow %.1f L/s · Bailing %.1f L/s · Patch %.1f cm²/s\nCrew %.1f guns / %.1f bail / %.1f repair · %d wounded\nStores: %.1f kits · %.1f fuel · %.1f ammunition"%[boat.hp,boat.maxHp,100.0*float(boat.water)/maxf(1.0,float(boat.capacity)),boat.breaches.size(),boat.fire,flow.get("inflow",0.0),flow.get("bailing",0.0),flow.get("repair",0.0),flow.get("crewGuns",0.0),flow.get("crewBail",0.0),flow.get("crewRepair",0.0),boat.wounded,boat.supplies,boat.fuel,boat.ammo]

static func details(ui) -> void:
	ui.modal_kind="battle_details"
	var body=ui.modal("Fleet, reserves & damage control","BATTLE DETAIL",1040,800)
	ui.battle_details_label=null
	ui.skirmish_guidance(body)
	var actions=ui.row(body)
	ui.button(actions,"Selected tactics & weapon groups",func():options(ui),false,false)
	ui.button(actions,"Boarding orders",func():ui.BoardingUI.battle(ui),false,false)
	ui.button(actions,"Select all active boats",func():ui.host.select_all_boats();details(ui),false,false)
	ui.label(body,"Selected boat · intent, reload and readiness",21,ui.GOLD,true)
	ui.battle_details_label=ui.paragraph(body,"",14,ui.TEXT)
	var flagship: Dictionary=ui.host.Battle.get_flagship(ui.host.battle)
	ui.label(body,"Flagship crew priority · "+str(flagship.get("name","no flagship")),19,ui.GOLD,true)
	var priorities=ui.row(body)
	for pair in [["balanced","Balanced"],["bail","Bail water"],["repair","Patch & repair"],["fight","Guns first"]]:
		var policy: String=pair[0]
		ui.button(priorities,pair[1],func():ui.host.set_crew_policy(policy);details(ui),flagship.get("policy","")==policy,false).disabled=flagship.is_empty()
	ui.paragraph(body,"These priorities act on the named flagship, even when another boat is selected. Repair consumes actual kits; bailing, repairs and guns share its available crew. Use X in battle to change flagship.",13)
	ui.rule(body)
	ui.paragraph(body,"300 DP limits deployment per side, not fleet ownership. Reserved boats remain outside this engagement; this roster cannot spawn reinforcements. Click a living friendly boat to select it; Shift adds to selection.",14)
	ui.battle_fleet=ui.column(body)
	for team in ["player","enemy"]:
		var active: Array=ui.host.battle.ships.filter(func(s):return s.team==team and not s.sunk and not s.get("captureSecured",false))
		var reserves: Array=ui.host.battle.get("reserves",{}).get(team,[])
		ui.label(ui.battle_fleet,("YOUR FLEET" if team=="player" else "OPPOSITION")+" · %d active / %d DP · %d reserve / %d DP"%[active.size(),Deployment.total(active),reserves.size(),Deployment.total(reserves)],17,ui.GOLD)
		for boat in active:
			var text: String="%s · %d DP · %.0f%% hull%s"%[boat.name,Deployment.cost(boat),100.0*float(boat.hp)/maxf(1.0,float(boat.maxHp))," · FLAGSHIP" if str(boat.id)==str(ui.host.battle.playerId) else ""]
			if team=="player":
				var id: String=str(boat.id)
				compact_button(ui,ui.battle_fleet,text,func():ui.host.select_battle_boat(id,Input.is_key_pressed(KEY_SHIFT));details(ui),id in ui.host.selected_battle_ids)
			else:ui.paragraph(ui.battle_fleet,text,13)
		for boat in reserves:ui.paragraph(ui.battle_fleet,"RESERVE · %s · %d DP · outside the arena"%[boat.get("name",boat.get("spec",{}).get("name","Boat")),Deployment.cost(boat)],13)
	ui.paragraph(body,"WASD camera · Shift fast pan · Scroll zoom · Home center · Space pause · Tab overview · Click/drag select · Shift add · Right-click order · 1 engage / 2 escort flagship / 3 hold · F1–F4 recall / Ctrl+F1–F4 save · U autopilot · X flagship. Manual helm uses arrows and mouse.",13)
	var footer=ui.row(body)
	ui.button(footer,"Retreat fleet ↗",func():ui.close_modal();ui.host.withdraw_fleet(),false,false)
	ui.button(footer,"Return to battle",ui.close_modal,true,false)
	ui.update_hud()

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
	ui.label(body,"Chart information on demand",21,ui.GOLD,true)
	var overlays=ui.row(body)
	for pair in [["arcs","Weapon arcs & range"],["threat","Threat range"],["routes","Targets & routes"]]:
		var kind: String=pair[0]
		var enabled: bool=bool(ui.host.chart.battle_overlays.get(kind,false))
		var toggle=func():
			if ui.host.set_battle_overlay(kind,not enabled):options(ui,weapon_kind)
		ui.button(overlays,str(pair[1])+": "+("ON" if enabled else "OFF"),toggle,enabled,false).name="BattleOverlay_"+kind
	ui.paragraph(body,"Range and arcs show fitted weapons; a loaded weapon still needs aim, ammunition and a clear firing lane. Targets and routes describe the current plan and can change when danger intervenes.",13)
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
		var assign=func():
			if ui.host.set_selected_formation(formation):options(ui,weapon_kind)
		ui.button(formation_row,formation.capitalize(),assign,not "formation" in mixed and current.get("formation","")==formation,false)
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
	ui.button(rally_row,"Fall back selected",func():ui.host.command_selected("withdraw"))
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

static func compact_weapon_status106(full_status: String) -> String:
	var text: String=full_status.strip_edges()
	var normalized: String=text.replace("·"," ").replace("—"," ")
	normalized=normalized.replace("\n"," ").strip_edges()
	while normalized.contains("  "):
		normalized=normalized.replace("  "," ")
	normalized=normalized.trim_suffix(".").to_lower()

	if normalized in ["loaded","loaded waiting for firing opportunity","loaded waiting for a firing opportunity","loaded waiting for shot"]:
		return "Loaded"
	if normalized in ["hold","hold fire","holding fire"]:
		return "Hold"

	if text.begins_with("Loaded "):
		text=text.trim_prefix("Loaded ").lstrip(" :·—")
	elif text.begins_with("Loaded:"):
		text=text.trim_prefix("Loaded:").lstrip(" :·—")

	if text.begins_with("Reloading "):
		text="Reload "+text.trim_prefix("Reloading ")

	return text if text.length()<=24 else text.left(23)+"…"
