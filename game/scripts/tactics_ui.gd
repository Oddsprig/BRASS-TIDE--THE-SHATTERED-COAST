extends RefCounted
const Deployment = preload("res://scripts/deployment.gd")

static func build(ui, size: Vector2):
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
	ui.button(actions,"Withdraw fleet ↗",func():ui.host.Battle.retreat(ui.host.battle))

static func update(ui):
	var battle: Dictionary = ui.host.battle
	if is_instance_valid(ui.objective_label):ui.objective_label.text=preload("res://scripts/battle_objectives.gd").label(battle)
	var player: Array = battle.ships.filter(func(s):return s.team=="player" and not s.sunk)
	var enemy: Array = battle.ships.filter(func(s):return s.team=="enemy" and not s.sunk)
	ui.battle_points_label.text = "YOUR FLEET  %d / 300 DP\nENEMY FLEET  %d / 300 DP" % [Deployment.total(player),Deployment.total(enemy)]
	ui.autopilot_button.text = "U · AUTOPILOT ON" if battle.get("autopilot",true) else "U · MANUAL FLAGSHIP"
	ui.battle_control_label.text = "WASD  Camera · Shift  Fast pan\nSCROLL  Zoom · HOME  Center\nCLICK / DRAG  Select · SHIFT  Add\nRIGHT-CLICK  Move / attack / escort\nSPACE  Pause · X  Change flagship\n" + ("ARROWS + MOUSE  Manual control" if not battle.get("autopilot",true) else "All boats steer and fire automatically.")
