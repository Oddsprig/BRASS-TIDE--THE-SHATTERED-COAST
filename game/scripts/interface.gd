extends CanvasLayer
const Finance = preload("res://scripts/finance_ui.gd")

const INK = Color("102731")
const LINE = Color("3b5a60")
const TEXT = Color("e4e1cc")
const MUTED = Color("9cb6af")
const GOLD = Color("dfbd7d")
const TEAL = Color("8ac9b6")
const RED = Color("eb9a7d")
var host
var root: Control
var chrome: Control
var overlay: Control
var notices: VBoxContainer
var title_root: Control
var modal_open = false
var modal_kind = ""
var hud_mode = ""
var port_tab = "Market"
var trade_qty = 5
var stats_label: Label
var clock_label: Label
var voyage_label: Label
var left_body: VBoxContainer
var right_body: VBoxContainer
var dock_button: Button
var flagship_label: Label
var hull_bar: ProgressBar
var flood_bar: ProgressBar
var damage_label: Label
var battle_fleet: VBoxContainer
var policy_buttons: Dictionary = {}

func setup(game_host):
	host = game_host
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.theme = create_theme()
	chrome = Control.new()
	chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chrome)
	title_root = Control.new()
	title_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_root)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)
	notices = VBoxContainer.new()
	notices.position = Vector2(560, 95)
	notices.size = Vector2(480, 0)
	notices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notices)

func create_theme() -> Theme:
	var theme = Theme.new()
	theme.default_font = host.chart.sans
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color("fff0cb"))
	theme.set_color("font_disabled_color", "Button", Color("607e7b"))
	theme.set_stylebox("normal", "Button", box(Color("1a3942"), LINE, 12))
	theme.set_stylebox("hover", "Button", box(Color("2a4a50"), Color("8ea99a"), 12))
	theme.set_stylebox("pressed", "Button", box(Color("4c5144"), GOLD, 12))
	theme.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), GOLD, 12))
	theme.set_stylebox("disabled", "Button", box(Color("142e37"), Color("2b4549"), 12))
	theme.set_constant("separation", "VBoxContainer", 10)
	theme.set_constant("separation", "HBoxContainer", 10)
	theme.set_stylebox("panel", "PanelContainer", box(Color(0.045, 0.12, 0.16, 0.95), LINE, 20))
	theme.set_stylebox("background", "ProgressBar", box(Color("23454c"), Color(0, 0, 0, 0), 0))
	theme.set_stylebox("fill", "ProgressBar", box(TEAL, Color(0, 0, 0, 0), 0))
	return theme

func box(color: Color, border: Color, padding: int = 16) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding * 0.75
	style.content_margin_bottom = padding * 0.75
	return style

func clear(node: Node):
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func label(parent: Node, text: String, font_size: int = 16, color: Color = TEXT, serif: bool = false) -> Label:
	var result = Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	if serif:
		result.add_theme_font_override("font", host.chart.serif)
	parent.add_child(result)
	return result

func paragraph(parent: Node, text: String, font_size: int = 16, color: Color = MUTED) -> Label:
	var result = label(parent, text, font_size, color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result

func eyebrow(parent: Node, text: String) -> Label:
	var result = label(parent, text.to_upper(), 11, GOLD)
	result.add_theme_font_override("font", host.chart.mono)
	return result

func button(parent: Node, text: String, action: Callable, primary: bool = false) -> Button:
	var result = Button.new()
	result.text = text
	result.custom_minimum_size.y = 42
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.focus_mode = Control.FOCUS_NONE
	if primary:
		result.add_theme_stylebox_override("normal", box(GOLD, GOLD, 14))
		result.add_theme_stylebox_override("hover", box(Color("efd197"), Color("efd197"), 14))
		result.add_theme_color_override("font_color", INK)
		result.add_theme_color_override("font_hover_color", INK)
	# Every harbor/account action publishes a pending copied economy snapshot first.
	# This also covers direct core actions in modal buttons, before they touch purses.
	result.pressed.connect(func(): host.sync_economy(); action.call())
	parent.add_child(result)
	return result

func row(parent: Node) -> HBoxContainer:
	var result = HBoxContainer.new()
	parent.add_child(result)
	return result

func column(parent: Node) -> VBoxContainer:
	var result = VBoxContainer.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(result)
	return result

func spacer(parent: Node, height: float = 10):
	var space = Control.new()
	space.custom_minimum_size.y = height
	parent.add_child(space)

func rule(parent: Node):
	var separator = HSeparator.new()
	separator.modulate = Color(LINE, 0.8)
	parent.add_child(separator)

func panel(parent: Node, position: Vector2, size_value: Vector2) -> VBoxContainer:
	var container = PanelContainer.new()
	container.position = position
	container.size = size_value
	parent.add_child(container)
	return column(container)

func progress(parent: Node, color: Color = TEAL) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.custom_minimum_size.y = 6
	bar.show_percentage = false
	bar.add_theme_stylebox_override("fill", box(color, color, 0))
	parent.add_child(bar)
	return bar

func title_screen():
	close_modal()
	clear(chrome)
	clear(title_root)
	title_root.visible = true
	var size = root.get_viewport_rect().size
	var v = VBoxContainer.new()
	v.position = Vector2(100, 110)
	v.size = Vector2(560, 780)
	v.add_theme_constant_override("separation", 8)
	title_root.add_child(v)
	eyebrow(v, "—  A COAST WORTH FIGHTING FOR")
	spacer(v, 20)
	label(v, "BRASS", 120, TEXT, true)
	var title = label(v, "TIDE", 120, GOLD, true)
	title.add_theme_constant_override("line_spacing", -20)
	eyebrow(v, "THE SHATTER COAST")
	spacer(v, 22)
	paragraph(v, "One worn-out skiff. An ocean of trouble.\nBuild your fleet. Keep it afloat. Break the blockade.", 21, Color("b5ccc0"))
	spacer(v, 20)
	var actions = column(v)
	actions.custom_minimum_size.x = 345
	actions.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button(actions, "TAKE THE HELM                         ↗", host.new_game, true)
	if host.has_save():
		button(actions, "Continue voyage                         →", host.load_game)
	button(actions, "Quick battle                                 ⚑", host.quick_battle)
	button(actions, "Captain's guide                            ?", open_guide)
	spacer(v, 25)
	eyebrow(v, "FLEET COMBAT  ·  LIVING PORTS  ·  YOUR OWN FLOTILLA")
	var footer = Label.new()
	footer.text = "CAPTAIN'S EDITION  v%s\nORIGINAL WORLD  ·  NATIVE WINDOWS  ·  PORTABLE SAVES" % host.Version.text()
	footer.position = Vector2(100, size.y - 73)
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", MUTED)
	footer.add_theme_font_override("font", host.chart.mono)
	title_root.add_child(footer)

func build_hud():
	title_root.visible = false
	clear(chrome)
	policy_buttons.clear()
	var size = root.get_viewport_rect().size
	var top = panel(chrome, Vector2.ZERO, Vector2(size.x, 76))
	var top_row = row(top)
	button(top_row, "◈  BRASS TIDE", open_menu)
	stats_label = label(top_row, "", 16, TEXT)
	stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_label = label(top_row, "", 12, MUTED)
	button(top_row, "Ⅱ", func(): host.toggle_pause())
	button(top_row, "1× / 4×", func(): host.speed = 4 if host.speed == 1 else 1)
	button(top_row, "♫", func(): host.audio.enabled = not host.audio.enabled; toast("Sound on" if host.audio.enabled else "Sound off"))
	button(top_row, "☰", open_menu)
	left_body = panel(chrome, Vector2(25, 100), Vector2(280, 0))
	right_body = panel(chrome, Vector2(size.x - 325, 100), Vector2(300, 0))
	if host.mode == "battle":
		build_battle_hud(size)
	else:
		build_campaign_hud(size)
	hud_mode = host.mode
	update_hud()

func build_campaign_hud(size: Vector2):
	eyebrow(left_body, "YOUR FLOTILLA")
	flagship_label = label(left_body, "", 26, TEXT, true)
	paragraph(left_body, "A captain is only as strong as the boats and sailors that come home.", 14)
	rule(left_body)
	button(left_body, "Fleet & damage control     F", open_fleet)
	button(left_body, "Cargo & supplies               C", open_cargo)
	button(left_body, "Contracts & logbook          J", open_contracts)
	rule(left_body)
	paragraph(left_body, "Choose a harbor on the chart. Coastal villages build hulls from workers, timber, steel, and engines.", 13)
	if not host.core.state.activeContract.is_empty():
		var c = host.core.state.activeContract
		eyebrow(right_body, "ACTIVE CONTRACT")
		paragraph(right_body, c.title, 23, TEXT)
		paragraph(right_body, c.description, 14)
		label(right_body, "%s  →  %s" % [host.core.port(c.port).name, host.core.port(c.targetPort).name], 12, GOLD)
		label(right_body, "+%s coins  ·  +%d renown" % [money(c.reward), c.renown], 14, TEAL)
		button(right_body, "View contract  ↗", open_contracts, true)
	else:
		eyebrow(right_body, "CAPTAIN'S ORDERS")
		label(right_body, "Start small.\nThink like a fleet.", 27, TEXT, true)
		paragraph(right_body, "Your skiff is cheap. Your crew isn't expendable. Take harbor contracts, trade between ports, and buy or recover boats to grow your flotilla.", 15)
		var next = host.data.MISSIONS[mini(host.core.state.missionIndex, host.data.MISSIONS.size() - 1)]
		if not host.core.state.completed:
			paragraph(right_body, "Next story contract: %s" % host.core.port(next.port).name, 14, GOLD)
		button(right_body, "Find a contract  ↗", open_contracts, true)
	var bottom = panel(chrome, Vector2(0, size.y - 85), Vector2(size.x, 85))
	var actions = row(bottom)
	button(actions, "▱  Fleet", open_fleet)
	button(actions, "▤  Hold", open_cargo)
	button(actions, "⚑  Contracts", open_contracts)
	button(actions, "?  Guide", open_guide)
	voyage_label = label(actions, "", 12, MUTED)
	voyage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voyage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dock_button = button(actions, "Enter harbor  ↗", func(): open_port(), true)

func build_battle_hud(size: Vector2):
	eyebrow(left_body, "FLAGSHIP · DAMAGE CONTROL")
	flagship_label = label(left_body, "", 25, TEXT, true)
	hull_bar = progress(left_body, TEAL)
	flood_bar = progress(left_body, Color("74b7da"))
	damage_label = label(left_body, "", 13, MUTED)
	rule(left_body)
	eyebrow(left_body, "CREW PRIORITY")
	for pair in [["balanced", "Balanced"], ["bail", "Bail water"], ["repair", "Patch & repair"], ["fight", "Guns first"]]:
		var policy: String = pair[0]
		var b = button(left_body, pair[1], func(): host.set_crew_policy(policy))
		b.custom_minimum_size.y = 33
		b.add_theme_font_size_override("font_size", 13)
		policy_buttons[policy] = b
	rule(left_body)
	paragraph(left_body, "More hands bailing and repairing means fewer on the guns. Patching consumes supplies. Bailing does not.", 13)
	eyebrow(right_body, "BATTLE GROUP")
	label(right_body, host.battle.location.get("name", "Coastal waters"), 24, TEXT, true)
	battle_fleet = column(right_body)
	for boat in host.battle.ships:
		if boat.team == "player":
			var id = boat.id
			button(battle_fleet, boat.name, func(): host.Battle.select_flagship(host.battle, id))
	rule(right_body)
	paragraph(right_body, "W / S   Throttle\nA / D   Steer\nSHIFT   Boost\nMOUSE   Aim · hold click to fire\nR   Toggle auto gunners\nTAB   Switch flagship\nSPACE   Tactical pause", 14)
	var bottom = panel(chrome, Vector2(0, size.y - 90), Vector2(size.x, 90))
	var actions = row(bottom)
	label(actions, "FLEET ORDERS", 11, MUTED)
	for pair in [["engage", "1 · Engage"], ["escort", "2 · Escort"], ["hold", "3 · Hold"]]:
		var order: String = pair[0]
		button(actions, pair[1], func(): host.Battle.set_order(host.battle, order))
	voyage_label = label(actions, "", 13, MUTED)
	voyage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voyage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	button(actions, "Withdraw  ↗", func(): host.Battle.retreat(host.battle))

func update_hud():
	if host.mode == "menu" or host.mode != hud_mode or stats_label == null or not is_instance_valid(stats_label) or host.core.state.is_empty():
		return
	var w = host.core.state
	var boats = w.fleet if host.mode != "battle" else host.battle.ships.filter(func(s): return s.team == "player" and not s.sunk)
	var supplies = 0.0
	var ammo = 0.0
	var fuel = 0.0
	var crew = 0
	for s in boats:
		supplies += s.supplies
		ammo += s.ammo
		fuel += s.fuel
		crew += int(s.crew)
	stats_label.text = "%s cash     ▱  %d boats     ◉  %d crew     ▣  %d kits     ◆  %d fuel     ·  %d ammo" % [money(w.coins), boats.size(), crew, supplies, fuel, ammo]
	clock_label.text = "DAY %d  ·  %s" % [int(w.day), "PAUSED" if host.paused else "%d×" % host.speed if host.mode != "battle" else "%02d:%02d" % [int(host.battle.time) / 60, int(host.battle.time) % 60]]
	if host.mode == "battle":
		var s = host.Battle.get_flagship(host.battle)
		if s.is_empty():
			return
		var flow = host.Damage.get_status(s)
		flagship_label.text = s.name
		hull_bar.value = s.hp / s.maxHp * 100
		flood_bar.value = s.water / s.capacity * 100
		damage_label.text = "HULL  %d / %d     FLOOD  %d%%\n\nInflow       %.1f L/s\nBailing      %.1f L/s\nPatch rate   %.1f cm²/s\n\nCREW  %.1f guns · %.1f bail · %.1f repair\nHoles %d · Fire %d%% · Engine %d%%\nWounded %d · Supplies %.1f" % [s.hp, s.maxHp, s.water / s.capacity * 100, flow.inflow, flow.bailing, flow.repair, flow.crewGuns, flow.crewBail, flow.crewRepair, s.breaches.size(), s.fire, s.engine * 100, s.wounded, s.supplies]
		for policy in policy_buttons:
			policy_buttons[policy].add_theme_color_override("font_color", GOLD if s.policy == policy else TEXT)
		var enemies = host.battle.ships.filter(func(t): return t.team == "enemy" and not t.sunk).size()
		voyage_label.text = "%d HOSTILE  ·  %s  ·  %s" % [enemies, host.battle.order.to_upper(), "AUTO GUNNERS ON" if host.auto_gunners else "MANUAL GUNNERY"]
		if host.battle.retreatTimer != null:
			voyage_label.text = "WITHDRAWING · %.0f seconds" % host.battle.retreatTimer
	else:
		flagship_label.text = "%d %s. One captain." % [w.fleet.size(),"boat" if w.fleet.size() == 1 else "boats"]
		var p = host.core.current_port()
		dock_button.disabled = p.is_empty()
		dock_button.text = "Enter %s  ↗" % p.name if not p.is_empty() else "At sea"
		voyage_label.text = "UNDERWAY · %s" % host.core.port(w.destination).get("name", "Open water") if not w.path.is_empty() else "%d RENOWN   ·   HOLD %.0f / %.0f" % [w.renown, host.core.cargo_weight(), host.core.capacity()]

func modal(title: String, subtitle: String = "CAPTAIN'S DESK", width: float = 1030, height: float = 780) -> VBoxContainer:
	clear(overlay)
	modal_open = true
	var size = root.get_viewport_rect().size
	var shade = ColorRect.new()
	shade.color = Color(0.012, 0.04, 0.065, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(shade)
	var panel_root = PanelContainer.new()
	width = minf(width, size.x - 80)
	height = minf(height, size.y - 100)
	panel_root.position = (size - Vector2(width, height)) * 0.5
	panel_root.size = Vector2(width, height)
	panel_root.add_theme_stylebox_override("panel", box(Color("102a34"), Color("628477"), 28))
	overlay.add_child(panel_root)
	var outer = column(panel_root)
	var head = row(outer)
	var heading = column(head)
	eyebrow(heading, subtitle)
	label(heading, title, 36, TEXT, true)
	button(head, "×", close_modal)
	rule(outer)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var body = column(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	return body

func close_modal():
	var previous = modal_kind
	modal_open = false
	modal_kind = ""
	clear(overlay)
	host.fire_held = false
	if previous == "outcome" and host.mode == "battle":
		if host.quick_mode:
			host.return_to_title()
		elif host.core.active_fleet().is_empty():
			host.accept_rescue()
		else:
			host.return_to_campaign()
		return
	if host.mode != "menu":
		update_hud()

func open_port(tab: String = ""):
	host.sync_economy()
	var p = host.core.current_port()
	if p.is_empty():
		toast("Sail to a harbor first.", true)
		return
	if not tab.is_empty():
		port_tab = tab
	modal_kind = "port"
	var body = modal(p.name, "%s · %s" % [host.core.faction(p.faction).name, p.industry.to_upper()])
	paragraph(body, p.description, 16)
	var tabs = row(body)
	for item in ["Market", "Boatyard", "Crew & repairs", "Economy", "Contracts"]:
		var value: String = item
		var b = button(tabs, value, func(): open_port(value))
		b.add_theme_color_override("font_color", GOLD if port_tab == value else MUTED)
	match port_tab:
		"Market": market_view(body, p)
		"Boatyard": yard_view(body, p)
		"Crew & repairs": fleet_view(body, true)
		"Economy": economy_view(body, p)
		"Contracts": contracts_view(body)
	spacer(body, 10)
	var actions = row(body)
	button(actions, "Wait one day", func(): host.wait_one_day())
	button(actions, "Sail on  ↗", close_modal, true)

func market_view(body: Node, p: Dictionary):
	paragraph(body, "Prices follow local stocks, labor and trade. Working stores aboard boats are separate from cargo. Buy reserves here, then load them through the Hold screen.", 14)
	var options = row(body)
	label(options, "TRADE QUANTITY", 11, MUTED)
	var qty = SpinBox.new()
	qty.min_value = 1
	qty.max_value = 100
	qty.value = trade_qty
	qty.custom_minimum_size = Vector2(110, 38)
	qty.value_changed.connect(func(value): trade_qty = int(value))
	options.add_child(qty)
	label(options, "Hold %.0f / %.0f" % [host.core.cargo_weight(), host.core.capacity()], 14, GOLD)
	for good in host.Economy.GOODS:
		var key: String = good
		var definition = host.Economy.GOODS[key]
		var line = row(body)
		var name_label = label(line, definition.name, 17, Color(definition.color).lightened(0.35))
		name_label.custom_minimum_size.x = 220
		label(line, "%4d stock" % p.stocks[key], 13, MUTED).custom_minimum_size.x = 110
		label(line, "%4d hold" % host.core.state.cargo[key], 13, MUTED).custom_minimum_size.x = 100
		button(line, "Buy %d cash" % host.Economy.price(p, key), func(): host.trade(key, trade_qty, "buy"))
		button(line, "Sell %d cash" % host.Economy.price(p, key, "sell"), func(): host.trade(key, trade_qty, "sell"))
		button(line,"Cost",func():Finance.good_recipe(self,key))
		rule(body)

func hull_card(body: Node, h: Dictionary, in_yard: bool, stock: int = 0):
	var q = host.core.ship_quote(h)
	var container = PanelContainer.new()
	container.add_theme_stylebox_override("panel", box(Color("17343d"), LINE, 17))
	body.add_child(container)
	var content = column(container)
	var head = row(content)
	var details = column(head)
	eyebrow(details, "%s · %s · TIER %d" % [host.core.faction(h.faction).name, h.role, h.tier])
	label(details, h.name, 25, TEXT, true)
	label(head, "%s cash" % money(q.readyPrice), 23, GOLD)
	paragraph(content, h.description, 14)
	label(content, "%d hull  ·  %d armor  ·  %d speed  ·  %d hold  ·  Crew %d / %d / %d" % [h.hp, h.armor, h.speed, h.cargo, h.crewMin, h.crewOptimal, h.crewMax], 13, MUTED)
	label(content, "%s  ·  %.1f shots/s  ·  %d impact  ·  %d m range" % [h.weapon.to_upper(), h.fireRate, h.damage, h.range], 13, TEAL)
	paragraph(content,"Materials %s · Assembly %s · Supervising experts %s · %.1f worker-days"%[money(q.materialCost),money(q.laborCost),money(q.supervisionCost),q.workerDays],13)
	button(content,"Show materials, wages & full price",func():Finance.boat_quote(self,h.id))
	if in_yard:
		var actions = row(content)
		var buy = button(actions, "Buy hull + minimum crew" if stock > 0 else "Out of stock", func(): host.buy_boat(h.id), true)
		buy.disabled = stock <= 0
		button(actions, "Commission · %s cash" % money(q.commissionPrice), func(): host.commission(h.id))
		paragraph(content,"%.1f calendar days with a full team. Paid supervisors and physical materials are required."%q.estimatedDays,12)

func yard_view(body: Node, p: Dictionary):
	paragraph(body, "Buy a completed boat or commission one for less. Building consumes this town's physical stocks and takes working days. Newly launched hulls need sailors and stores. Your flotilla can contain eight boats.", 15)
	for i in range(p.buildQueue.size()):
		var index = i
		var order = p.buildQueue[i]
		var line = row(body)
		label(line, "%s · %s · %s" % [host.core.hull(order.hull).name,"YOUR ORDER" if order.owner == "player" else "YARD STOCK","READY" if order.ready else "%.1f worker-days left · %s cash escrow"%[order.remainingWorkerDays,money(order.escrow)]], 15, GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if order.owner == "player":
			button(line, "Collect hull", func(): host.collect_boat(index)).disabled = not order.ready
	for id in p.get("shipIds", []):
		var h = host.core.hull(id)
		hull_card(body, h, true, p.shipStock.get(id, 0))
	button(body, "View all 24 boat designs", open_catalog)

func open_catalog():
	modal_kind = "catalog"
	var body = modal("Fleet register", "24 ORIGINAL HULL DESIGNS")
	paragraph(body, "Prices are for the hull. Buy from a harbor with that design, add crew, and supply it before sailing. Bigger boats have more cargo and armor, but need more hands and are slower to turn.")
	for h in host.data.HULLS:
		hull_card(body, h, false)

func open_fleet():
	host.sync_economy()
	modal_kind = "fleet"
	var body = modal("Your flotilla", "FLEET · CREW · DAMAGE CONTROL")
	fleet_view(body, not host.core.current_port().is_empty())

func fleet_view(body: Node, docked: bool):
	paragraph(body, "Crew counts show minimum / full effectiveness / maximum. Wounded sailors remain aboard but cannot work. An uncrewed hull is towed and stays out of battle. All damage, stores and casualties persist.", 15)
	for boat in host.core.state.fleet:
		var s: Dictionary = boat
		var uid: String = s.uid
		var container = PanelContainer.new()
		container.add_theme_stylebox_override("panel", box(Color("17343d"), LINE, 18))
		body.add_child(container)
		var card = column(container)
		var heading = row(card)
		label(heading, s.name, 27, TEXT, true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eyebrow(heading, "FLAGSHIP" if host.core.state.flagship == uid else "TOWED / RESERVE" if s.get("mothballed", false) else "ACTIVE")
		var health = progress(card)
		health.value = s.hp / s.maxHp * 100
		label(card, "Hull %d / %d · Armor %d · Water %d%% · Engine %d%% · Holes %d" % [s.hp, s.maxHp, s.armor, s.water / s.capacity * 100, s.engine * 100, s.breaches.size()], 14, MUTED)
		label(card, "Crew %d aboard (%d wounded) · Required %d / %d / %d" % [s.crew, s.wounded, s.crewMin, s.crewOptimal, s.crewMax], 15, GOLD)
		label(card, "Ammo %d · Fuel %.1f · Supplies %.1f · Cargo capacity %d" % [s.ammo, s.fuel, s.supplies, s.spec.cargo], 14, MUTED)
		var priorities = row(card)
		for policy_value in ["balanced", "bail", "repair", "fight"]:
			var policy: String = policy_value
			var b = button(priorities, policy.capitalize(), func(): host.Damage.set_policy(s, policy); refresh_fleet())
			b.add_theme_color_override("font_color", GOLD if s.policy == policy else TEXT)
		var actions = row(card)
		button(actions, "Set flagship", func(): host.core.state.flagship = uid; refresh_fleet()).disabled = s.crew < s.crewMin
		button(actions, "Activate" if s.get("mothballed", false) else "Reserve", func(): s.mothballed = not s.get("mothballed", false); refresh_fleet()).disabled = s.crew < s.crewMin
		if docked:
			button(actions, "+1 sailor", func(): host.recruit(uid, 1))
			button(actions, "Fill crew", func(): host.recruit(uid, maxi(1, int(s.crewOptimal - s.crew))))
			var quote = host.core.service_quote(s, host.core.current_port())
			var services = row(card)
			button(services, "Drydock · %s cash" % money(quote.cost), func(): host.repair_boat(uid), true)
			button(services, "Voyage stores", func(): host.resupply_boat(uid,"voyage"))
			button(services, "Full stores", func(): host.resupply_boat(uid))
			button(services, "Sell hull", func(): host.sell_boat(uid)).disabled = host.core.state.fleet.size() <= 1
			paragraph(card,"Voyage stores target 80 rounds, 3 fuel and 6 repair kits; full stores target 80 rounds, 60 fuel and 20 kits. Pay only for missing stock.",12)
		else:
			paragraph(card, "At sea: use repair priority to patch breaches and repair hull with supplies. Visit a harbor to recruit, treat wounded, or use drydock.", 13)

func refresh_fleet():
	if modal_kind == "port":
		open_port("Crew & repairs")
	else:
		open_fleet()

func economy_view(body: Node, p: Dictionary):
	Finance.settlement(self,body,p)

func open_cargo():
	modal_kind = "cargo"
	var body = modal("The hold", "CARGO · RESERVES · ACCOUNTS", 850, 700)
	paragraph(body, "Trade cargo uses fleet hold space. Ready-use ammunition, fuel and repair supplies stay aboard each boat. Load reserves to transfer cargo into those working stores.")
	label(body, "%.0f / %.0f cargo space" % [host.core.cargo_weight(), host.core.capacity()], 26, GOLD, true)
	for good in host.Economy.GOODS:
		var line = row(body)
		label(line, host.Economy.GOODS[good].name, 17).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label(line, "%.1f  ×  %d space" % [host.core.state.cargo[good], host.Economy.GOODS[good].weight], 16, MUTED)
	if not host.core.state.freight.is_empty():
		paragraph(body, "Sealed contract freight: %d %s. Reserved until delivery or abandonment." % [host.core.state.freight.qty, host.core.state.freight.good], 15, GOLD)
	button(body, "Load reserves into working stores", func(): host.core.use_reserves(); open_cargo(), true)
	rule(body)
	var costs = host.Economy.daily_upkeep(host.core.state.fleet)
	paragraph(body,"Daily wages: %s cash · Rations: %.1f bales\nSailors' shared purse: %s cash · Unpaid wages: %s\nHarbor loan: %s cash · Morale: %d / 100"%[money(costs.wages),costs.food,money(host.core.state.crewPurse),money(host.core.state.wageArrears),money(host.core.state.debt),host.core.state.morale],16)
	if host.core.state.wageArrears > 0:
		button(body,"Pay owed crew wages",func():host.respond(host.core.pay_wage_arrears());open_cargo())
	if host.core.state.debt > 0:
		button(body,"Repay up to 5,000 cash to the treasury",func():host.respond(host.core.repay_loan());open_cargo())

func open_contracts():
	modal_kind = "contracts"
	var body = modal("Contracts & logbook", "THE COAST REMEMBERS WHAT YOU DO")
	contracts_view(body)
	rule(body)
	eyebrow(body, "CAPTAIN'S LOG")
	for entry in host.core.state.log.slice(0, 15):
		paragraph(body, entry, 13)

func contracts_view(body: Node):
	var w = host.core.state
	label(body, "Story progress · %d / 8" % w.missionIndex, 24, GOLD, true)
	if not w.activeContract.is_empty():
		var active = w.activeContract
		eyebrow(body, "ACTIVE CONTRACT")
		label(body, active.title, 26, TEXT, true)
		paragraph(body, active.description, 16)
		label(body, "Destination: %s · Reward %s cash" % [host.core.port(active.targetPort).name, money(active.reward)], 16, TEAL)
		var actions = row(body)
		if host.core.contract_ready():
			button(actions, "Deliver & collect reward" if active.cleared else "Engage hostile flotilla", host.resolve_contract, true)
		else:
			button(actions, "Chart destination  ↗", func(): host.sail_to(active.targetPort); close_modal(), true)
		button(actions, "Abandon contract", func(): host.respond(host.core.abandon_contract()); open_contracts())
		rule(body)
	for contract in host.core.available_contracts():
		var c: Dictionary = contract
		var container = PanelContainer.new()
		container.add_theme_stylebox_override("panel", box(Color("17343d"), LINE, 18))
		body.add_child(container)
		var card = column(container)
		eyebrow(card, "STORY CONTRACT" if c.get("story", false) else "HARBOR WORK")
		label(card, c.title, 23, TEXT, true)
		paragraph(card, c.description, 14)
		label(card, "%s → %s · %s cash · %d hostile boats" % [host.core.port(c.port).name, host.core.port(c.targetPort).name, money(c.reward), c.enemyHulls.size()], 14, GOLD)
		var p = host.core.current_port()
		if p.is_empty() or p.id != c.port:
			button(card, "Go to %s  ↗" % host.core.port(c.port).name, func(): host.sail_to(c.port); close_modal())
		else:
			var b = button(card, "Accept contract", func(): host.accept_contract(c.id), true)
			b.disabled = not w.activeContract.is_empty()

func open_guide():
	modal_kind = "guide"
	var body = modal("A captain's guide", "BRASS TIDE · v%s" % host.Version.text())
	for section in [
		["Bronze cash and paid work","An ordinary sailor earns 100 bronze cash per day, with rations supplied separately. Wages move into the crew's shared purse. Missed wages become arrears and reduce morale and combat performance. The Hold shows savings and arrears. Each town has business, worker, specialist and government purses; its Economy screen shows employment and actual transfers."],
		["Why a boat costs what it costs","Every design has physical material requirements and paid shipwrights, mechanics, fitters, foremen and supervising experts. Trace the price through logs and planks, ore and iron, powder ingredients, ammunition, guns and engines. Yard quotes list those inputs, wages, overhead, margin and duty. Commissions hold wages in escrow and only pay for work completed."],
		["Your first voyage", "Start at Brass Haven in a cheap Tinwake skiff with five sailors. Enter harbor, open Contracts, and accept Clear the Lantern Narrows. Chart Kelp Reach, sail there, then engage its raider. Earn bronze cash, buy another hull, and recruit enough sailors to use it."],
		["At the helm", "W / S adjusts throttle; A / D steers. Hold left mouse to fire at your cursor; aim near a boat for gentle aim assistance. Shift boosts. R toggles automatic gunners. Tab switches your flagship. Space pauses. F11 toggles fullscreen. Mouse wheel changes zoom."],
		["Command a flotilla", "You directly steer one boat. Your other active boats steer and fire on their own. 1 engages, 2 escorts your flagship, and 3 holds position. Withdraw orders a 12-second escape. Hulls with too few sailors are towed and do not deploy. You can field up to eight boats."],
		["Keep the water outside", "Hits can puncture hulls, wound sailors, damage engines, and start fires. Breaches admit water; too much water sinks a boat even if its hull is intact. Powered pumps need fuel and engine power. Crew can bail without supplies. More water slows the boat."],
		["Choose what the crew does", "Balanced divides hands among guns, bailing and repair. Bail water moves hands off the guns. Patch & repair closes holes using supplies, then slowly repairs hull once holes are closed. Guns first leaves little damage control. Wounded sailors cannot work. Fixed helmsman and gunner details are just part of a boat's art."],
		["Make the coast work for you", "Villages hire woodcutters, carpenters, miners, smelters and other trades. They need both inputs and payroll. Buy abundant goods and sell into shortages. Your cargo can restart a stalled workshop. A commissioned hull needs its full bill of materials, workforce and supervisors."],
		["Build your fleet", "Buy completed hulls at a yard; the price of minimum crew is added. Recruit toward optimal crew for full efficiency. Drydock consumes repair kits and cash. Refill working stores from local stock, or buy reserves into the hold and load them. Victory may offer a battered hull to recover; it needs crew and repairs."],
		["Save your voyage", "Autosaves happen on the campaign chart and after major actions. Manual saves are in the captain's menu. Saves live in a saves folder beside the portable game. Quick battle is separate from the campaign. If every boat is lost, a harbor rescue provides another cheap skiff on a funded harbor loan."],
		["Free the Shatter Coast", "The eight story contracts lead through the original archipelago to the blockade flagship. Side patrols and sealed-freight jobs provide extra income. The world remains playable after the finale. v0.001 is the first complete playable step; later versions advance by 0.001."]
	]:
		label(body, section[0], 24, GOLD, true)
		paragraph(body, section[1], 17)
		rule(body)

func open_menu():
	modal_kind = "menu"
	var body = modal("Captain's desk", "BRASS TIDE · v%s" % host.Version.text(), 650, 690)
	button(body, "Return to voyage", close_modal, true)
	button(body, "Save voyage", func(): host.save_game(true)).disabled = host.mode == "battle"
	button(body, "Load saved voyage", func(): host.load_game()).disabled = not host.has_save()
	button(body, "Captain's guide", open_guide)
	button(body, "Fleet register · all 24 hulls", open_catalog)
	button(body, "Settings & performance", open_settings)
	button(body, "Main menu", func(): host.return_to_title())
	button(body, "Quit to desktop", func(): host.quit_game())

func open_settings():
	modal_kind = "settings"
	var body = modal("Settings", "VIDEO · AUDIO · PERFORMANCE", 800, 650)
	button(body, "Toggle fullscreen · F11", host.toggle_fullscreen)
	button(body, "Sound: ON" if host.audio.enabled else "Sound: OFF", func(): host.audio.enabled = not host.audio.enabled; open_settings())
	button(body, "Frame cap: %d" % Engine.max_fps, func(): Engine.max_fps = 60 if Engine.max_fps == 120 else 120; open_settings())
	paragraph(body,"If changing text flickers or disappears, close the game and use Stable Rendering.vbs in the portable folder. The normal launcher keeps separate rendering enabled.",14)
	paragraph(body, "Godot 4.7.2 · 2D Mobile renderer\nSeparate rendering thread configured from the first build. Economy days run on worker snapshots; interface and rendering commands are submitted on the main thread. Water is a flat gradient with a small set of decorative highlights and wakes.", 16)
	paragraph(body, "CPU: %s\nThreads: %d · Adapter: %s\nCurrent frame rate: %d FPS" % [OS.get_processor_name(), OS.get_processor_count(), RenderingServer.get_video_adapter_name(), Engine.get_frames_per_second()], 15, TEAL)
	button(body, "Back to captain's desk", open_menu)

func outcome(result: String, report: Dictionary, enemies: Array):
	modal_kind = "outcome"
	var body = modal("Waters secured" if result == "won" else "Fleet withdrawn" if result == "retreated" else "Lost at sea", "AFTER ACTION REPORT", 820, 690)
	paragraph(body, "Your crew can breathe again. Inspect the damage and load fresh stores before your next engagement." if result == "won" else "Surviving hulls carry their damage, wounded and missing stores back to the campaign. A withdrawal can save a fleet.", 18)
	label(body, "+%s coins" % money(report.get("coins", 0)), 38, GOLD, true)
	paragraph(body, "%d hostile boats encountered · %d friendly boats afloat" % [enemies.size(), host.battle.ships.filter(func(s): return s.team == "player" and not s.sunk).size()], 17, TEAL)
	if report.get("completed", false):
		label(body, "THE SHATTER COAST IS FREE", 26, GOLD, true)
		paragraph(body, "The Admiral's blockade is broken. Harbors reopen their routes. Your flotilla has earned its place in the coast's history. You can keep trading, building and sailing.")
	if host.quick_mode:
		button(body, "Fight another skirmish", host.quick_battle, true)
		button(body, "Main menu", host.return_to_title)
		return
	var salvage = report.get("salvage", {})
	if result == "won" and not salvage.is_empty():
		paragraph(body, "Recoverable hull: %s. Tug labor, engineer inspection and company fee: %s cash. It returns at 35%% hull with no crew or stores." % [salvage.name, money(host.core.salvage_quote(salvage.id).total)], 15)
		var recovery_button = button(body, "Recover %s" % salvage.name, func(): host.recover_salvage(salvage.id))
		recovery_button.disabled = host.core.state.fleet.size() >= host.core.MAX_FLEET
	if report.get("fleetLost", false):
		paragraph(body,"Brass Haven may lend enough from its real treasury to buy an available hull, hire sailors and purchase stores. The itemized cost becomes a harbor loan.",16,GOLD)
		button(body, "Accept harbor rescue", host.accept_rescue, true)
	else:
		button(body, "Return to the coast  ↗", host.return_to_campaign, true)

func toast(message: String, bad: bool = false):
	if message.is_empty():
		return
	var container = PanelContainer.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_theme_stylebox_override("panel", box(Color("173d43"), RED if bad else GOLD, 14))
	var text = paragraph(container, message, 15, TEXT)
	text.custom_minimum_size.x = 440
	notices.add_child(container)
	if notices.get_child_count() > 4:
		var old = notices.get_child(0)
		notices.remove_child(old)
		old.queue_free()
	var tween = create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(container, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func():
		if is_instance_valid(container):
			container.queue_free()
	)

func money(value) -> String:
	var s = str(int(value))
	var result = ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			result += ","
		result += s[i]
	return result
