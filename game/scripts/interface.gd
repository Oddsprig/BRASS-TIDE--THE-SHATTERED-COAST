extends CanvasLayer
const TacticsUI = preload("res://scripts/tactics_ui.gd")
const RefitUI = preload("res://scripts/refit_ui.gd")
const WorkshopUI = preload("res://scripts/workshop_ui.gd")
const Portrait = preload("res://scripts/boat_portrait.gd")
const Deployment = preload("res://scripts/deployment.gd")
const Finance = preload("res://scripts/finance_ui.gd")
const CampaignUI=preload("res://scripts/campaign_ui.gd")
const RecoveryUI=preload("res://scripts/recovery_ui.gd")
const HomeUI=preload("res://scripts/home_ui.gd")
const GuidanceUI=preload("res://scripts/guidance_ui.gd")
const CrisisUI=preload("res://scripts/crisis_ui.gd")
const BoardingUIReference051=preload("res://scripts/boarding_ui.gd")
const LawUI=preload("res://scripts/law_ui.gd")
const CompanyUI=preload("res://scripts/company_ui.gd")
const RegionalGoodsUI=preload("res://scripts/regional_goods_ui.gd")
const WorkerUI=preload("res://scripts/worker_ui.gd")
const ToolingUI=preload("res://scripts/tooling_ui.gd")
const SupplyUI=preload("res://scripts/supply_ui.gd")
const EconomicUI=preload("res://scripts/economic_ui.gd")
const RegionalUI=preload("res://scripts/regional_ui.gd")
const StoryUI=preload("res://scripts/story_ui.gd")
const IdentityUI=preload("res://scripts/identity_ui.gd")
const TradeUI=preload("res://scripts/trade_ui.gd")
const NavalUI=preload("res://scripts/naval_ui.gd")
const FactionUI=preload("res://scripts/faction_ui.gd")
const Politics=preload("res://scripts/politics.gd")
const VoyageUI=preload("res://scripts/voyage_ui.gd")
const VoyagePreparation065=preload("res://scripts/voyage_preparation_ui065.gd")
const SectorUI069=preload("res://scripts/sector_ui069.gd")
const OceanContact066=preload("res://scripts/ocean_contact_ui066.gd")
const ShippingUI068=preload("res://scripts/shipping_ui068.gd")
const EquipmentController=preload("res://scripts/equipment_ui_controller.gd")
const EquipmentPicker=preload("res://scripts/equipment_picker.gd")

class BoardingUI extends RefCounted:
	static func open(ui) -> void:
		BoardingUIReference051.open(ui)
	static func battle(ui) -> void:
		if ui.host.battle.get("_battleMirror051",false):ui.open_worker_boarding051()
		else:BoardingUIReference051.battle(ui)

const INK = Color("102731")
const LINE = Color("3b5a60")
const TEXT = Color("e4e1cc")
const MUTED = Color("9cb6af")
const GOLD = Color("dfbd7d")
const TEAL = Color("8ac9b6")
const RED = Color("eb9a7d")
var host
var guidance_career: String="captain"
var root: Control
var chrome: Control
var overlay: Control
var notices: VBoxContainer
var notices_home_position = Vector2(560, 95)
var title_root: Control
var modal_open = false
var modal_kind = ""
var workshop_drafts: Dictionary={}
var workshop_requests: Dictionary={}
var voyage_intent065: Dictionary={}
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
var objective_label: Label
var battle_points_label: Label
var battle_control_label: Label
var autopilot_button: Button
var tactical_intent_label: Label
var battle_reload_label: Label
var battle_crew_label: Label
var battle_details_label: Label

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

func button(parent: Node, text: String, action: Callable, primary: bool = false, sync: bool = true) -> Button:
	var result = Button.new()
	result.text = text
	result.custom_minimum_size.y = 42
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.focus_mode = Control.FOCUS_ALL
	if primary:
		result.add_theme_stylebox_override("normal", box(GOLD, GOLD, 14))
		result.add_theme_stylebox_override("hover", box(Color("efd197"), Color("efd197"), 14))
		result.add_theme_color_override("font_color", INK)
		result.add_theme_color_override("font_focus_color", INK)
		result.add_theme_color_override("font_hover_color", INK)
	# Every harbor/account action publishes a pending copied economy snapshot first.
	# This also covers direct core actions in modal buttons, before they touch purses.
	result.pressed.connect(func():
		if sync:host.sync_economy()
		action.call())
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
	EquipmentPicker.clear_all(self)
	clear(chrome)
	clear(title_root)
	title_root.visible = true
	var size = root.get_viewport_rect().size
	var v = VBoxContainer.new()
	v.position = Vector2(90, 60)
	v.size = Vector2(560, 780)
	v.add_theme_constant_override("separation", 8)
	title_root.add_child(v)
	eyebrow(v, "MOTORBOAT FLEET GAME")
	spacer(v, 20)
	label(v, "BRASS", 88, TEXT, true)
	var title = label(v, "TIDE", 88, GOLD, true)
	title.add_theme_constant_override("line_spacing", -20)
	eyebrow(v, "THE SHATTER COAST")
	spacer(v, 22)
	paragraph(v, "Fleet combat, trading and island exploration.", 21, Color("b5ccc0"))
	spacer(v, 20)
	var actions = column(v)
	actions.custom_minimum_size.x = 345
	actions.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var first: Button
	if host.has_save():
		first=button(actions, "Continue voyage", host.load_game, true)
	var new_voyage: Button=button(actions, "New voyage", open_new_voyage, first==null, false)
	if first==null:first=new_voyage
	add_coastal_clash(actions, false)
	button(actions, "Fleet battle laboratory", host.open_lab)
	button(actions, "Options & music", open_settings)
	button(actions, "Guide & acknowledgements", open_guide, false, false)
	button(actions, "Development notes", func():CampaignUI.notes(self))
	button(actions, "Quit to desktop", host.quit_game)
	for action in actions.get_children():
		if action is Button:action.custom_minimum_size.y=36
	first.grab_focus()
	spacer(v, 25)
	eyebrow(v, "SINGLE PLAYER  ·  KEYBOARD AND MOUSE")
	var footer = Label.new()
	footer.text = "v%s  ·  WINDOWS PC" % host.Version.text()
	footer.position = Vector2(100, size.y - 73)
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", MUTED)
	footer.add_theme_font_override("font", host.chart.mono)
	title_root.add_child(footer)

func open_new_voyage():
	if host.mode != "menu":return
	if not host.new_voyage_needs_confirmation():
		host.new_game()
		return
	modal_kind = "new_voyage"
	var body = modal("Start a new voyage?", "REPLACE CURRENT VOYAGE", 700, 520)
	paragraph(body, "This replaces the current career. Progress since the last save will be discarded.", 18, TEXT)
	paragraph(body, "Your last saved voyage will be kept separately so you can recover it later. Its existing backup will also be kept. Later autosaves leave these copies alone.", 16)
	paragraph(body, "If the saved files cannot be preserved or the new voyage cannot be saved, replacement is cancelled. Recovery help is in Guide > Preserved voyages.", 16)
	button(body, "Cancel", close_modal, true, false).grab_focus()
	button(body, "Replace voyage", host.replace_voyage, false, false)

func open_preserved_voyages():
	modal_kind = "preserved_voyages"
	var body = modal("Preserved voyages", "SAVED FILES", 820, 680)
	paragraph(body, "New voyage keeps the original saved bytes in the files listed below. Autosaves use voyage.json and voyage.backup.json; they do not rotate these preserved copies.", 16)
	paragraph(body, "To recover a copy, close the game. Keep the current voyage.json separately, then COPY the chosen preserved file to voyage.json in the same saves folder. Reopen the game and choose Continue voyage. Keep the preserved original.", 16, TEXT)
	var found: bool = false
	if DirAccess.dir_exists_absolute(host.save_directory):
		for name: String in DirAccess.get_files_at(host.save_directory):
			if not name.begins_with("voyage.before-new.") or not name.ends_with(".json"):continue
			var digest: String = name.trim_prefix("voyage.before-new.").trim_suffix(".json")
			var path: String = host.save_directory.path_join(name)
			if digest.length() != 64 or FileAccess.get_sha256(path) != digest:continue
			found = true
			paragraph(body, path, 14, GOLD)
	if not found:paragraph(body, "No verified preserved copies were found in %s." % host.save_directory, 16)
	button(body, "Back to guide", open_guide, false, false)

func build_hud():
	title_root.visible = false
	clear(chrome)
	policy_buttons.clear()
	EquipmentPicker.prune_requests(self)
	var size = root.get_viewport_rect().size
	if host.mode == "battle":
		notices.position = Vector2(16, 122)
		build_battle_hud(size)
		hud_mode = host.mode
		update_hud()
		return
	notices.position = Vector2(560, 95)
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
	build_campaign_hud(size)
	hud_mode = host.mode
	update_hud()

func build_campaign_hud(size: Vector2):
	# Keep the expanding campaign tools reachable on every supported logical viewport.
	var frame: Control=left_body.get_parent() as Control
	frame.remove_child(left_body)
	var scroll=ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(280,0)
	scroll.custom_maximum_size=Vector2(-1,maxf(1,size.y-230))
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_MAXIMIZE_FIRST
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	frame.add_child(scroll)
	scroll.add_child(left_body)
	left_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.minimum_size_changed.connect(frame.reset_size,CONNECT_DEFERRED)
	frame.reset_size.call_deferred()
	if not host.core.home_local064():
		eyebrow(left_body,"YOUR FLOTILLA")
		flagship_label=label(left_body,"",20,TEXT)
		var view064: Dictionary=host.core.world_view064()
		paragraph(left_body,str(view064.get("name","Chart unavailable")),22,GOLD)
		paragraph(left_body,"Choose a coastal approach to enter local waters or return to the open ocean. Wages, food and working fuel continue on the same voyage.",15)
		button(left_body,"Coastal approaches",open_ocean064,true,false)
		if str(view064.get("layer",""))=="local":
			if str(view064.get("regionId",""))=="glasswind_keys":
				button(left_body,"Westglass anchorage & shipping",func():open_shipping068(),false,false)
			else:
				button(left_body,"Harbor & shipping",_open_local_shipping,false,false)
			button(left_body,"Island surveys (I)",func():CampaignUI.islands(self),false,false)
			button(left_body,"Salvage & cache",func():RecoveryUI.open(self),false,false)
		else:
			button(left_body,"Shipping & remote holdings",func():open_shipping068(),false,false)
		button(left_body,"Fleet & crew",open_fleet,false,false)
		button(left_body,"Hold & reserves",open_cargo,false,false)
		button(left_body,"More charts & business",open_campaign_tools)
		eyebrow(right_body,"VOYAGE")
		var generated_chart: bool=view064.get("regions") is Array and view064.get("regions",[]).size()==48
		if generated_chart:
			paragraph(right_body,"Prepared island groups share this ocean chart. Click a coast to route to an approach or enter it. Known holdings show their factions.",16)
			paragraph(right_body,"Unknown owners stay off the chart. Boatyards, crew hiring, refit, and contracts remain at Shatter Coast.",15,GOLD)
		else:
			paragraph(right_body,"Glasswind Keys and Shatter Coast share one ocean chart. Approach a marked side, stop, then enter its coastal waters.",16)
			paragraph(right_body,"Known remote branch quays trade finite goods and provisions at berth; boatyards, crew hiring, refit, and contracts remain at Shatter Coast.",15,GOLD)
		var footer064=panel(chrome,Vector2(0,size.y-85),Vector2(size.x,85))
		var actions064=row(footer064)
		button(actions064,"Fleet",open_fleet,false,false);button(actions064,"Hold",open_cargo,false,false);button(actions064,"Contracts",open_contracts)
		if str(view064.get("layer",""))=="local":
			if str(view064.get("regionId",""))=="glasswind_keys":
				button(actions064,"Anchorage",func():open_shipping068(),false,false)
			else:
				button(actions064,"Harbor",_open_local_shipping,false,false)
			button(actions064,"Surveys",func():CampaignUI.islands(self),false,false)
			button(actions064,"Salvage",func():RecoveryUI.open(self),false,false)
		voyage_label=label(actions064,"",12,MUTED)
		voyage_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		dock_button=button(actions064,"Coastal approaches",_on_remote_dock_button068,true,false)
		return
	eyebrow(left_body, "YOUR FLOTILLA")
	flagship_label = label(left_body, "", 20, TEXT)
	rule(left_body)
	var active: Dictionary=host.core.state.activeContract
	if not active.is_empty():
		paragraph(left_body,str(active.title),18,GOLD)
	elif not host.core.state.completed and host.core.state.missionIndex<host.data.MISSIONS.size():
		paragraph(left_body,str(host.data.MISSIONS[host.core.state.missionIndex].title),18,GOLD)
	paragraph(left_body,"Review fuel, supplies, crew wages and the return route.",14)
	button(left_body,"Prepare first voyage" if host.core.state.missionIndex==0 and active.is_empty() else "Review voyage",func():GuidanceUI.open_voyage(self),true,false)
	button(left_body,"Open ocean & coastal approaches",open_ocean064,false,false)
	button(left_body,"More charts & business",open_campaign_tools,false,false)
	rule(left_body)
	paragraph(left_body, "Select a harbor to travel or dock.", 13)
	if not host.core.state.activeContract.is_empty():
		var c = host.core.state.activeContract
		eyebrow(right_body, "ACTIVE CONTRACT")
		paragraph(right_body, c.title, 23, TEXT)
		paragraph(right_body, c.description, 14)
		label(right_body, "%s  →  %s" % [host.core.port(c.port).name, host.core.port(c.targetPort).name], 12, GOLD)
		label(right_body, "+%s coins  ·  +%d renown" % [money(c.reward), c.renown], 14, TEAL)
		button(right_body, "View contract  ↗", open_contracts, true)
	else:
		right_body.get_parent().visible = false
	var bottom = panel(chrome, Vector2(0, size.y - 85), Vector2(size.x, 85))
	var actions = row(bottom)
	button(actions, "▱  Fleet", open_fleet, false, false)
	button(actions, "▤  Hold", open_cargo, false, false)
	button(actions, "⚑  Contracts", open_contracts)
	button(actions, "?  Guide", open_guide, false, false)
	voyage_label = label(actions, "", 12, MUTED)
	voyage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voyage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dock_button = button(actions, "Enter harbor  ↗", func(): open_port(), true)

func open_campaign_tools():
	modal_kind="campaign_tools"
	var body=modal("More charts & business")
	button(body,"Open ocean & coastal approaches",open_ocean064,true,false)
	button(body,"Interregional shipping & anchorage",func():open_shipping068(),false,false)
	if not host.core.home_local064():
		if str(host.core.world_view064().get("layer",""))=="local":
			button(body,"Island charts & surveys     I",func():CampaignUI.islands(self),false,false)
			button(body,"Wrecks & recovery",func():RecoveryUI.open(self),false,false)
		button(body,"Fleet & crew",open_fleet,false,false);button(body,"Hold & reserves",open_cargo,false,false)
		button(body,"Existing contracts",open_contracts,false,false);button(body,"Close",close_modal,false,false)
		return
	button(body,"Captain's priorities",func():GuidanceUI.open(self),true,false)
	button(body,"Prepare expedition",func():CampaignUI.expedition(self))
	button(body,"Island charts & surveys     I",func():CampaignUI.islands(self))
	button(body,"Wrecks & recovery",func():RecoveryUI.open(self))
	button(body,"Voyage jobs & contacts     K",func():VoyageUI.open(self))
	button(body,"Coastal stories & leads",func():StoryUI.open(self))
	button(body,"Home harbors & warehouses",func():HomeUI.open(self))
	button(body,"Regional goals                    L",func():RegionalUI.open(self))
	button(body,"Close",close_modal,false,false)

func open_ocean064(region_id: String="",approach_id: String=""):
	if host.mode!="campaign":return
	var view064: Dictionary=host.core.world_view064()
	var current_region: String=str(view064.get("regionId",""))
	if region_id.is_empty() and str(view064.get("layer",""))=="local" and current_region not in ["shatter_coast","glasswind_keys"]:
		open_voyage_preparation065(current_region,approach_id)
		return
	if str(view064.get("layer","")) in ["home","local"] and region_id==current_region and approach_id in ["north","south"]:
		# Authored coasts keep the paired voyage. A generated gate does not retarget to Shatter Coast.
		if region_id=="shatter_coast":
			voyage_intent065["outExit"]=approach_id
			voyage_intent065["targetRegionId"]="glasswind_keys"
			open_voyage_preparation065()
			return
		if region_id=="glasswind_keys":
			voyage_intent065["outExit"]=approach_id
			voyage_intent065["targetRegionId"]="shatter_coast"
			open_voyage_preparation065()
			return
	open_voyage_preparation065(region_id,approach_id)

func open_voyage_preparation065(region_id: String="",approach_id: String="") -> void:
	if host.mode!="campaign":return
	if region_id.is_empty() or region_id=="shatter_coast" or region_id=="glasswind_keys":
		VoyagePreparation065.open(self,region_id,approach_id)
		return
	if SectorUI069.open(self,region_id,approach_id):
		return
	toast("That coast is not on this chart.",true)

func _open_local_shipping() -> void:
	if host.core==null:return
	var view064: Dictionary=host.core.world_view064()
	if str(view064.get("regionId",""))=="glasswind_keys":
		open_shipping068()
		return
	var port_id: String=_known_local_port_id(view064)
	if port_id.is_empty():
		toast("No known harbor on this coast.",true)
		return
	open_shipping068(port_id)

func _known_local_port_id(view064: Dictionary) -> String:
	if str(view064.get("regionId",""))=="glasswind_keys":
		return "westglass_anchorage"
	if host.core!=null and host.core.has_method("sector_view069"):
		var sector=host.core.sector_view069()
		if sector is Dictionary:
			var schema=sector.get("schema",null)
			if schema is bool or not (schema is int or schema is float) or int(schema)!=1:
				return ""
			var ports=sector.get("ports",[])
			if ports is Array:
				for port in ports:
					if port is Dictionary and str(port.get("regionId",""))==str(view064.get("regionId","")):
						if port.has("known") and not bool(port.get("known",false)):
							continue
						if port.has("installed") and not bool(port.get("installed",false)):
							continue
						var port_id: String=str(port.get("id","")).strip_edges()
						if not port_id.is_empty():
							return port_id
	return ""

func open_ocean_contact066(id: String="") -> void:
	if host.mode!="campaign":return
	OceanContact066.open(self,id)

func open_shipping068(port_id: String="") -> void:
	if host.mode!="campaign":return
	ShippingUI068.open(self,port_id)

func open_remote_port068(port_id: String="") -> void:
	open_shipping068(port_id)

func _on_remote_dock_button068() -> void:
	if host.mode!="campaign" or host.core==null:return
	if host.core is Object and host.core.has_method("remote_port068") and not host.core.remote_port068().is_empty():
		var remote_port: Dictionary=host.core.remote_port068()
		var remote_id: String=str(remote_port.get("id","")).strip_edges()
		open_shipping068(remote_id if not remote_id.is_empty() else "westglass_anchorage")
		return
	open_ocean064()

func add_coastal_clash(actions: Node, primary: bool=true) -> Button:
	var clash: Button=button(actions, "Coastal Clash", host.start_coastal_clash, primary)
	clash.name="CoastalClash"
	paragraph(actions, "Escort a cargo packet to the exit.", 14, GOLD)
	return clash

func skirmish_guidance(body: Node = null) -> void:
	if str(host.battle_context.get("kind",""))!="coastal_clash":
		return
	var parent: Node=left_body if body==null else body
	if parent==null:return
	var text: String=str(host.lab_config.get("guidance",""))
	if text.is_empty():
		text="Escort the loaded packet to the exit. WASD camera, Space pause, Tab orders, U manual helm."
	var hint: Label=paragraph(parent, text, 11 if body==null else 14, GOLD)
	hint.name="SkirmishGuidance"
	hint.tooltip_text=text
	if body==null:hint.max_lines_visible=1

func build_battle_hud(size: Vector2):
	TacticsUI.build(self, size)
	skirmish_guidance()

func update_hud():
	if host.mode == "menu" or host.mode != hud_mode or stats_label == null or not is_instance_valid(stats_label) or host.core.state.is_empty():
		return
	if host.mode == "battle":
		clock_label.text = "PAUSED" if host.paused else "%02d:%02d" % [int(host.battle.time) / 60, int(host.battle.time) % 60]
		var cadence: Dictionary=host.battle.get("simulation051",{})
		clock_label.tooltip_text="Authoritative worker: %d Hz · %d completed steps\nPresentation: %.0f FPS · Main poll %.3f ms\nSimulation lag %.3f s"%[int(cadence.get("workerStepHz",30)),int(cadence.get("completedSteps",0)),Engine.get_frames_per_second(),float(cadence.get("mainPollUs",0))/1000.0,float(cadence.get("simulationLagSeconds",0.0))] if not cadence.is_empty() else "Synchronous reference battle"
		TacticsUI.update(self, true)
		return
	var w = host.core.state
	var boats = w.fleet
	var supplies = 0.0
	var ammo = 0.0
	var fuel = 0.0
	var crew = 0
	for s in boats:
		supplies += s.supplies
		ammo += s.ammo
		fuel += s.fuel
		crew += int(s.crew)
	var boat_word: String = "boat" if boats.size() == 1 else "boats"
	stats_label.text = "%s coins     ▱  %d %s owned     ◉  %d crew     ▣  %d kits     ◆  %d fuel     ·  %d ammo" % [money(w.coins), boats.size(), boat_word, crew, supplies, fuel, ammo]
	stats_label.tooltip_text = "Owned boats, their crew and onboard stores. Stored boats are included."
	clock_label.text = "DAY %d  ·  %s" % [int(w.day), "PAUSED" if host.paused else "%d×" % host.speed if host.mode != "battle" else "%02d:%02d" % [int(host.battle.time) / 60, int(host.battle.time) % 60]]
	flagship_label.text = "%d %s owned · %d crew" % [boats.size(), boat_word, crew]
	var p = host.core.current_port()
	dock_button.disabled = p.is_empty() if host.core.home_local064() else false
	if not host.core.home_local064():
		var rp068: Dictionary={}
		var sv068: Dictionary=host.core.shipping_view068() if (host.core is Object and host.core.has_method("shipping_view068")) else {}
		var ports068=sv068.get("ports",[])
		if ports068 is Array:
			for candidate in ports068:
				if candidate is Dictionary and bool(candidate.get("atBerth",false)):
					rp068=candidate
					break
		dock_button.text=("Enter %s  ↗" % str(rp068.get("name","Westglass Anchorage"))) if not rp068.is_empty() else "Coastal approaches"
	else:dock_button.text = "Enter %s  ↗" % p.name if not p.is_empty() else "At sea"
	var region064: String=str(host.core.world_view064().get("name","Shatter Coast"))
	var dest_name068: String=str(host.core.port(w.destination).get("name", "Open water"))
	if dest_name068=="Open water" and str(w.destination)=="westglass_anchorage":dest_name068="Westglass Anchorage"
	voyage_label.text = region064+" / "+("UNDERWAY · %s" % dest_name068 if not w.path.is_empty() else "%d RENOWN   ·   HOLD %.0f / %.0f" % [w.renown, host.core.cargo_weight(), host.core.capacity()])

func modal(title: String, subtitle: String = "CAPTAIN'S DESK", width: float = 1030, height: float = 780) -> VBoxContainer:
	# Detach shared notices before clearing their previous modal.
	if notices.get_parent() == root:
		notices_home_position = notices.position
	else:
		notices.reparent(root, false)
	clear(overlay)
	modal_open = true
	# Poll only completed publications; an open panel never schedules physics.
	if host.has_method("poll_battle051"):host.poll_battle051(0.0,true)
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
	button(head, "×", close_modal, false, modal_kind not in ["guide","captain_priorities","voyage_review","campaign_tools","harbor_services","fleet","fleet_identity","fleet_conversions","economic_workforce","regional","home_harbor","cargo","ocean064","voyage_preparation065","ocean_contact066","shipping068","remote_port068","sector069","new_voyage","preserved_voyages"])
	rule(outer)
	# Reserve a row below the heading, including for action failures.
	notices.reparent(outer, false)
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
	if notices.get_parent() != root:
		notices.reparent(root, false)
		notices.position = notices_home_position
		notices.size = Vector2(480, 0)
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
	if not host.core.home_local064():
		if host.core is Object and host.core.has_method("remote_port068") and not host.core.remote_port068().is_empty():
			var remote_port: Dictionary=host.core.remote_port068()
			var remote_id: String=str(remote_port.get("id","")).strip_edges()
			open_shipping068(remote_id if not remote_id.is_empty() else "westglass_anchorage");return
		var away_view: Dictionary=host.core.world_view064()
		if str(away_view.get("layer",""))=="local" and host.core is Object and host.core.has_method("shipping_view068") and not host.core.shipping_view068().get("ports",[]).is_empty():
			if str(away_view.get("regionId",""))=="glasswind_keys":
				open_shipping068("westglass_anchorage")
			else:
				var known_port: String=_known_local_port_id(away_view)
				if known_port.is_empty():
					toast("No known harbor on this coast.",true)
				else:
					open_shipping068(known_port)
			return
		open_ocean064();return
	host.sync_economy()
	var p = host.core.current_port()
	if p.is_empty():
		toast("Sail to a harbor first.", true)
		return
	var access: Dictionary=Politics.access(host.core,p)
	if not access.legal:
		FactionUI.open(self)
		return
	var inspection: Dictionary=Politics.inspect(host.core)
	if inspection.get("fine",0)>0:toast(str(inspection.message),true)
	p=host.core.current_port()
	access=Politics.access(host.core,p)
	host.core.TradeFlow.observe(host.core)
	if not tab.is_empty():
		port_tab = tab
	modal_kind = "port"
	var body = modal(p.name, "%s · %s" % [host.core.faction(p.faction).name, p.industry.to_upper()])
	paragraph(body, p.description, 16)
	paragraph(body,access.reason,14,TEAL)
	host.core.Contacts.visit(host.core.state,p,host.core.state.day)
	var tabs = row(body)
	for item in ["Market", "Boatyard", "Crew & repairs", "Refit", "Economy", "Contracts"]:
		var value: String = item
		var b = button(tabs, value, func(): open_port(value))
		b.add_theme_color_override("font_color", GOLD if port_tab == value else MUTED)
	button(body,"Advanced harbor services",open_harbor_services)
	match port_tab:
		"Market": market_view(body, p)
		"Boatyard": yard_view(body, p)
		"Crew & repairs": fleet_view(body, true)
		"Refit": RefitUI.roster(self, body)
		"Economy": economy_view(body, p)
		"Contracts": contracts_view(body)
	spacer(body, 10)
	var actions = row(body)
	button(actions, "Wait one day", func(): host.wait_one_day())
	button(actions, "Sail on  ↗", close_modal, true)

func open_harbor_services():
	var p: Dictionary=host.core.current_port()
	if p.is_empty():
		toast("Sail to a harbor first.",true)
		return
	modal_kind="harbor_services"
	var body=modal("Advanced harbor services",str(p.name))
	button(body,"Trade chart · dated quotes & input needs",func():TradeUI.open(self))
	button(body,"Faction standing & safe passage",func():FactionUI.open(self))
	button(body,"Voyage jobs, contacts & intelligence",func():VoyageUI.open(self))
	button(body,"Fishing crews & civilian voyages",func():VoyageUI.open(self,"Fishing"),false,false)
	button(body,"Coastal stories & expedition leads",func():StoryUI.open(self))
	button(body,"Home harbor, storage & business",func():HomeUI.open(self))
	button(body,"Crew training & harbor workforce",func():EconomicUI.open(self),false,false)
	button(body,"Supply coverage & protected stocks",func():SupplyUI.open(self))
	button(body,"Recovered machinery & workshop development",func():ToolingUI.open(self))
	button(body,"People, paid shifts & working conditions",func():WorkerUI.open(self))
	button(body,"Regional goods & coastal trades",func():RegionalGoodsUI.open(self))
	button(body,"Shipping companies & route accounts",func():CompanyUI.open(self))
	button(body,"Cargo declarations, licences & customs",func():LawUI.open(self))
	button(body,"Boarding crews & coastal defense",func():BoardingUI.open(self))
	button(body,"Regional crises & civilian passage",func():CrisisUI.open(self))
	if p.industry=="shipyard":button(body,"Recovered drawings & design licenses",func():RecoveryUI.blueprints(self))
	button(body,"Back to harbor",func():open_port())

func market_view(body: Node, p: Dictionary):
	button(body,"Trade opportunities · compare dated quotes",func():TradeUI.open(self),true)
	TradeUI.market_summary(self,body,str(p.id))
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
		button(line, "Buy %d coins" % host.Economy.price(p, key), func(): host.trade(key, trade_qty, "buy"))
		button(line, "Sell %d coins" % host.Economy.price(p, key, "sell"), func(): host.trade(key, trade_qty, "sell"))
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
	label(head, "%s coins" % money(q.readyPrice), 23, GOLD)
	paragraph(content, h.description, 14)
	label(content, "%d DEPLOYMENT POINTS" % Deployment.cost(h), 13, GOLD)
	label(content, "%d hull  ·  %d armor  ·  %d speed  ·  %d hold  ·  Crew %d / %d / %d" % [h.hp, h.armor, h.speed, h.cargo, h.crewMin, h.crewOptimal, h.crewMax], 13, MUTED)
	label(content, "%s  ·  %.1f shots/s  ·  %d impact  ·  %d m range" % [h.weapon.to_upper(), h.fireRate, h.damage, h.range], 13, TEAL)
	paragraph(content,"Materials %s · Assembly %s · Supervising experts %s · %.1f worker-days"%[money(q.materialCost),money(q.laborCost),money(q.supervisionCost),q.workerDays],13)
	button(content,"Show materials, wages & full price",func():Finance.boat_quote(self,h.id))
	if in_yard:
		var budget: Dictionary=host.core.Harbor.purchase_plan(host.core,h)
		paragraph(content,CampaignUI.purchase_plan_text(self,budget),13)
		var actions = row(content)
		var buy = button(actions, "Buy hull + crew · %s coins"%money(budget.purchaseCoins) if stock > 0 else "Out of stock", func(): host.buy_boat(h.id), true)
		buy.disabled = stock <= 0
		button(actions, "Commission · %s coins" % money(q.commissionPrice), func(): host.commission(h.id))
		paragraph(content,"%.1f calendar days with a full team. Paid supervisors and physical materials are required."%q.estimatedDays,12)

func yard_view(body: Node, p: Dictionary):
	paragraph(body, "Buy a completed boat or commission one for less. Building consumes this town's physical stocks and paid working days. A new hull needs sailors and working stores. You can own more than 300 points; each battle deploys up to 300. Traveling support and stored reserves stay outside that battle line.", 15)
	button(body,"Compare voyage needs before buying",func():CampaignUI.expedition(self))
	button(body,"Compare a fitting or specialist on an owned boat",open_fleet,false,false)
	for i in range(p.buildQueue.size()):
		var index = i
		var order = p.buildQueue[i]
		var line = row(body)
		label(line, "%s · %s · %s" % [host.core.hull(order.hull).name,"YOUR ORDER" if order.owner == "player" else "YARD STOCK","READY" if order.ready else "%.1f worker-days left · %s coins escrow"%[order.remainingWorkerDays,money(order.escrow)]], 15, GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if order.owner == "player":
			button(line, "Collect hull", func(): host.collect_boat(index)).disabled = not order.ready
	for id in host.core.Harbor.catalogue(host.core, p):
		var h = host.core.hull(id)
		hull_card(body, h, true, p.shipStock.get(id, 0))
	button(body, "View all %d boat designs" % host.data.HULLS.size(), open_catalog)

func open_catalog():
	modal_kind = "catalog"
	var body = modal("Fleet register", "%d ORIGINAL HULL DESIGNS" % host.data.HULLS.size())
	paragraph(body, "Prices are for the hull. Buy from a harbor with that design, add crew, and supply it before sailing. Bigger boats have more cargo and armor, but need more hands and are slower to turn.")
	for h in host.data.HULLS:
		hull_card(body, h, false)

func open_fleet():
	EquipmentPicker.prune_requests(self)
	modal_kind = "fleet"
	var body = modal("Your flotilla", "FLEET · CREW · DAMAGE CONTROL")
	fleet_view(body, not host.core.current_port().is_empty())

func fleet_view(body: Node, docked: bool):
	paragraph(body, "Crew counts show minimum / full effectiveness / maximum. Wounded sailors remain aboard but cannot work. An uncrewed hull is towed and stays out of battle. All damage, stores and casualties persist.", 15)
	label(body,"%s · 300 deployable per battle · %d / %d owned hulls"%[count_text(int(host.core.fleet_points()),"owned point","owned points"),host.core.state.fleet.size(),host.core.MAX_FLEET],17,GOLD)
	paragraph(body,"Only seaworthy, crewed traveling boats add expedition hold space. Stored and inactive hulls add none; their sailors still need food and wages. Mark a traveling partner as support through Support conversion to keep it outside battle deployment.",14)
	button(body,"Review expedition limits & support choices",func():CampaignUI.expedition(self))
	button(body,"Long-voyage preparation",open_voyage_preparation065,false,false)
	for boat in host.core.state.fleet:
		var s: Dictionary = boat
		var uid: String = s.uid
		var container = PanelContainer.new()
		container.add_theme_stylebox_override("panel", box(Color("17343d"), LINE, 18))
		body.add_child(container)
		var card = column(container)
		var heading = row(card)
		var portrait = Portrait.new()
		portrait.boat = s
		portrait.custom_minimum_size = Vector2(170, 110)
		heading.add_child(portrait)
		label(heading, s.name, 27, TEXT, true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eyebrow(heading,"STORED AT "+str(host.core.port(s.storedPort).get("name",s.storedPort)) if not str(s.get("storedPort","")).is_empty() else "FLAGSHIP" if host.core.state.flagship==uid else "INACTIVE / TOWED" if s.get("mothballed",false) else "ACTIVE")
		var health = progress(card)
		health.value = s.hp / s.maxHp * 100
		label(card, "Hull %d / %d · Armor %d · Water %d%% · Engine %d%% · Holes %d" % [s.hp, s.maxHp, s.armor, s.water / s.capacity * 100, s.engine * 100, s.breaches.size()], 14, MUTED)
		label(card, "Crew %d aboard (%d wounded) · Required %d / %d / %d" % [s.crew, s.wounded, s.crewMin, s.crewOptimal, s.crewMax], 15, GOLD)
		if not str(s.get("storedPort","")).is_empty():paragraph(card,"Berth: %s · %d coins owed. Public watch costs 28 coins per slot/day; a paid warehouse includes eight slots."%[s.get("storageProvider","Pending harbor watch"),s.get("berthArrears",0)],13)
		label(card, "Ammo %d · Fuel %.1f · Supplies %.1f · Cargo capacity %d" % [s.ammo, s.fuel, s.supplies, s.spec.cargo], 14, MUTED)
		var priorities = row(card)
		for policy_value in ["balanced", "bail", "repair", "fight"]:
			var policy: String = policy_value
			var b = button(priorities, policy.capitalize(), func(): host.Damage.set_policy(s, policy); refresh_fleet())
			b.add_theme_color_override("font_color", GOLD if s.policy == policy else TEXT)
		var actions = row(card)
		label(card, "%s · %s" % [count_text(int(Deployment.cost(s)), "deployment point", "deployment points"), count_text(s.spec.get("weaponMounts", []).size(), "weapon mount", "weapon mounts")], 13, TEAL)
		button(actions, "Equipment & condition", func(): open_equipment(uid)).disabled = s.get("sunk",false)
		button(actions, "Fleet workshop & fitting templates", func(): open_refit(uid)).disabled = s.get("sunk",false)
		button(card,"People, command & service history",func():IdentityUI.open(self,uid),false,false)
		button(actions, "Set flagship", func(): host.core.state.flagship = uid; refresh_fleet()).disabled = s.crew < s.crewMin
		button(actions, "Activate" if s.get("mothballed", false) else "Stand down", func():host.respond(host.core.set_boat_active(uid,s.get("mothballed",false)));refresh_fleet()).disabled = s.crew<s.crewMin or not str(s.get("storedPort","")).is_empty()
		if docked:
			button(actions,"Collect stored boat" if not str(s.get("storedPort","")).is_empty() else "Store at this harbor",func():host.respond(host.core.toggle_storage(uid));refresh_fleet())
		if docked:
			button(actions, "+1 sailor", func(): host.recruit(uid, 1))
			button(actions, "Fill crew", func(): host.recruit(uid, maxi(1, int(s.crewOptimal - s.crew))))
			var quote = host.core.service_quote(s, host.core.current_port())
			var services = row(card)
			button(services, "Drydock · %s coins" % money(quote.cost), func(): host.repair_boat(uid), true)
			button(services, "Voyage stores", func(): host.resupply_boat(uid,"voyage"))
			button(services, "Full stores", func(): host.resupply_boat(uid))
			button(services, "Sell hull", func(): host.sell_boat(uid)).disabled = host.core.state.fleet.size() <= 1
			paragraph(card,"Voyage stores fill the fitted magazine (80 rounds per weapon), 3 fuel and 6 repair kits. Full stores fill the fitted fuel tank and add 20 kits. Every missing round is bought from actual harbor stock.",12)
		else:
			paragraph(card, "At sea: use repair priority to patch breaches and repair hull with supplies. Visit a harbor to recruit, treat wounded, or use drydock.", 13)

func open_refit(uid: String):
	WorkshopUI.open(self, uid)

func open_single_refit(uid: String):
	RefitUI.open(self, uid)

func open_equipment(uid: String):
	if host.mode=="battle" and host.battle.get("_battleMirror051",false):
		open_worker_equipment051(uid)
		return
	EquipmentController.open(self, uid)

func open_worker_equipment051(uid: String) -> void:
	var boat: Dictionary={}
	for candidate: Dictionary in host.battle.get("ships",[]):
		if str(candidate.get("uid",""))==uid or str(candidate.get("id",""))==uid:boat=candidate;break
	if boat.is_empty() or boat.sunk or boat.team!="player":
		toast("Choose a living friendly boat.",true);return
	var condition: Dictionary=boat.get("moduleCondition",{})
	var installed: Dictionary=EquipmentController.Core.inspect_installed(condition)
	var locker: Dictionary=EquipmentController.Core.list_locker(condition)
	if not installed.get("ok",false) or not locker.get("ok",false):
		toast("These fittings could not be inspected.",true);return
	var rows: Array=[];var spares: Array=[]
	for item: Dictionary in installed.get("items",[]):rows.append(EquipmentController._part_row(item,false))
	for item: Dictionary in locker.get("items",[]):spares.append(EquipmentController._part_row(item,true))
	var flow: Dictionary=host.battle.get("tactical",{}).get("damageStatusById051",{}).get(str(boat.id),{})
	var model: Dictionary={"uid":str(boat.get("uid",boat.id)),"name":str(boat.name),"priority":str(condition.get("repairPriority","auto")),"rows":rows,"spares":spares,"supplies":float(boat.supplies),"repairCrew":float(flow.get("crewRepair",0.0)),"juryCap":EquipmentController.Core.JURY_CAP,"inPort":false,"debug":host.dev_enabled,"quote":{"ok":false,"message":"Battle repairs use the crew and kits aboard this boat.","cost":0.0,"ordinary":0.0,"expert":0.0,"fee":0.0,"materials":{}}}
	var id: String=str(boat.id)
	var actions: Dictionary={
		"setPriority":func(chosen: String):
			var queued: bool=host.set_repair_priority(id,chosen)
			toast("Repair priority queued." if queued else "That repair priority could not be queued.",not queued),
		"repair":func():toast("Battle repairs use the crew and kits aboard this boat."),
		"workshop":func():toast("Return to a harbor to change fittings."),
		"refresh":func():open_worker_equipment051(id)}
	EquipmentController.EquipmentUI.open(self,model,actions)

func open_worker_boarding051() -> void:
	modal_kind="boarding_orders"
	var body=modal("Boarding orders","WEAKEN · APPROACH · CAPTURE",1000,760)
	var st: Dictionary=host.battle
	paragraph(body,"Choose spare trained boarders and a weakened enemy. The party leaves only at physical contact; crew, losses and berths remain real.",16)
	var automatic: bool=not bool(st.get("autoBoard",true))
	button(body,"Cautious automatic boarding: "+("ON" if st.get("autoBoard",true) else "OFF"),func():_queue_boarding051("boarding_auto",{"enabled":automatic}),false,false)
	var sources=OptionButton.new();var source_ids: Array=[]
	var targets=OptionButton.new();var target_ids: Array=[]
	for boat: Dictionary in st.ships:
		if boat.sunk:continue
		if boat.team=="player" and not boat.get("captureSecured",false):
			source_ids.append(str(boat.id));sources.add_item("%s · %d boarders"%[str(boat.name),int(boat.get("boarders",0))])
		elif boat.team=="enemy":
			target_ids.append(str(boat.id));targets.add_item("%s · %.0f%% hull"%[str(boat.name),100.0*float(boat.hp)/maxf(1.0,float(boat.maxHp))])
	var controls=row(body);controls.add_child(sources);controls.add_child(targets)
	var count=SpinBox.new();count.min_value=1;count.max_value=128;count.value=3;controls.add_child(count)
	if not source_ids.is_empty() and not target_ids.is_empty():
		button(body,"Approach and board selected target",func():
			if _queue_boarding051("boarding_order",{"sourceId":str(source_ids[sources.selected]),"targetId":str(target_ids[targets.selected]),"count":int(count.value)}):close_modal(),true,false)
	for job: Dictionary in st.get("boarding",{}).get("jobs",[]):
		paragraph(body,"%s · %s · %d aboard target / %d returned / %d lost or killed"%[str(job.id),str(job.status),int(job.alive),int(job.returned),int(job.lost)+int(job.killed)],14)
		if job.status=="active":
			var id: String=str(job.id)
			button(body,"Recall "+id+" if still in contact",func():_queue_boarding051("boarding_abort",{"id":id}),false,false)
	button(body,"Check current orders",open_worker_boarding051,false,false)
	button(body,"Close",close_modal,true,false)

func _queue_boarding051(kind: String,payload: Dictionary) -> bool:
	var queued: bool=host.queue_battle_command051(kind,payload)
	toast("Boarding command queued; the crew will check the current situation." if queued else "That boarding command could not be queued.",not queued)
	return queued

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
	button(body,"Prepare expedition · limits, payroll & support",func():CampaignUI.expedition(self))
	button(body,"Long-voyage preparation",open_voyage_preparation065,false,false)
	for good in host.Economy.GOODS:
		var line = row(body)
		label(line, host.Economy.GOODS[good].name, 17).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label(line, "%.1f  ×  %d space" % [host.core.state.cargo[good], host.Economy.GOODS[good].weight], 16, MUTED)
		var good_id: String=str(good)
		button(line,"Set 1 on a marked float",func():host.respond(host.core.jettison(good_id,1));open_cargo()).disabled=host.core.state.cargo[good]<1
	if not host.core.state.freight.is_empty():
		paragraph(body, "Sealed contract freight: %d %s. Reserved until delivery or abandonment." % [host.core.state.freight.qty, host.core.state.freight.good], 15, GOLD)
	for job in host.core.state.get("voyageJobs",[]):
		if not job.get("freight",{}).is_empty():paragraph(body,"Sealed %s: %.0f %s · %.0f space"%[job.title,job.freight.qty,job.freight.good,job.freight.qty*host.Economy.GOODS[job.freight.good].weight],14,GOLD)
	button(body,"Recovered machinery & shore work",func():ToolingUI.open(self))
	button(body,"Shipping companies & real routes",func():CompanyUI.open(self))
	button(body,"Declarations & customs debts",func():LawUI.open(self))
	button(body,"Boarding crews, captives & prizes",func():BoardingUI.open(self))
	button(body,"Passenger manifests & regional crises",func():CrisisUI.open(self))
	button(body, "Load reserves into working stores", func(): host.core.use_reserves(); open_cargo(), true)
	rule(body)
	var costs = host.Economy.daily_upkeep(host.core.state.fleet)
	paragraph(body,"Daily wages: %s coins · Rations: %.1f bales\nSailors' shared purse: %s coins · Unpaid wages: %s\nHarbor loan: %s coins · Morale: %d / 100"%[money(costs.wages),costs.food,money(host.core.state.crewPurse),money(host.core.state.wageArrears),money(host.core.state.debt),host.core.state.morale],16)
	if host.core.state.wageArrears > 0:
		button(body,"Pay owed crew wages",func():host.respond(host.core.pay_wage_arrears());open_cargo())
	if host.core.state.debt > 0:
		button(body,"Repay up to 5,000 coins to the treasury",func():host.respond(host.core.repay_loan());open_cargo())

func open_contracts():
	modal_kind = "contracts"
	var body = modal("Contracts & logbook", "ACTIVE CONTRACTS · AVAILABLE WORK · RECENT EVENTS")
	if host.core.home_local064():button(body,"Several voyage jobs, contacts & intelligence",func():VoyageUI.open(self))
	contracts_view(body)
	rule(body)
	eyebrow(body, "CAPTAIN'S LOG")
	for entry in host.core.state.log.slice(0, 15):
		paragraph(body, entry, 13)

func contracts_view(body: Node):
	if not host.core.home_local064():
		if str(host.core.world_view064().get("layer",""))=="local":
			button(body,"Island charts & surveys     I",func():CampaignUI.islands(self),false,false)
			button(body,"Wrecks & recovery",func():RecoveryUI.open(self),false,false)
		paragraph(body,"Coastal commitments keep their deadlines. Return to Shatter Coast to accept or settle harbor work.",16,GOLD)
		for commitment064 in host.core.state.get("voyageJobs",[]):
			paragraph(body,str(commitment064.get("title","Voyage commitment"))+" / deadline day "+str(commitment064.get("deadlineDay",0)),15)
		var active064: Dictionary=host.core.state.get("activeContract",{})
		if not active064.is_empty():paragraph(body,str(active064.get("title","Coastal contract")),18,GOLD)
		button(body,"Coastal approaches",open_ocean064)
		return
	var w = host.core.state
	label(body, "Story progress · %d / 8" % w.missionIndex, 24, GOLD, true)
	if not w.activeContract.is_empty():
		var active = w.activeContract
		eyebrow(body, "ACTIVE CONTRACT")
		label(body, active.title, 26, TEXT, true)
		paragraph(body, active.description, 16)
		label(body, "Destination: %s · Reward %s coins" % [host.core.port(active.targetPort).name, money(active.reward)], 16, TEAL)
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
		label(card, "%s → %s · %s coins · %s" % [host.core.port(c.port).name, host.core.port(c.targetPort).name, money(c.reward), count_text(c.enemyHulls.size(), "hostile boat", "hostile boats")], 14, GOLD)
		var p = host.core.current_port()
		if p.is_empty() or p.id != c.port:
			button(card, "Go to %s  ↗" % host.core.port(c.port).name, func(): host.sail_to(c.port); close_modal())
		else:
			var b = button(card, "Accept contract", func(): host.accept_contract(c.id), true)
			b.disabled = not w.activeContract.is_empty()

func open_guide():
	modal_kind = "guide"
	var body = modal("A captain's guide", "BRASS TIDE · v%s" % host.Version.text())
	button(body,"Career goals & first steps",func():GuidanceUI.open(self),true,false)
	button(body, "Preserved voyages", open_preserved_voyages, false, false)
	for section in [
		["Bronze coins and paid work","An ordinary sailor earns 100 bronze coins per day, with rations supplied separately. Wages move into the crew's shared purse. Missed wages become arrears and reduce morale and combat performance. The Hold shows savings and arrears. Each town has business, worker, specialist and government purses; its Economy screen shows employment and actual transfers."],
		["Why a boat costs what it costs","Every design has physical material requirements and paid shipwrights, mechanics, fitters, foremen and supervising experts. Trace the price through logs and planks, ore and iron, powder ingredients, ammunition, guns and engines. Yard quotes list those inputs, wages, overhead, margin and duty. Commissions hold wages in escrow and only pay for work completed."],
		["Your first voyage", "Start at Brass Haven in a cheap Tinwake skiff with five sailors. Enter harbor, open Contracts, and accept Clear the Lantern Narrows. Chart Kelp Reach, sail there, then engage its raider. Earn bronze coins, buy another hull, and recruit enough sailors to use it."],
		["Your camera", "WASD pans the camera in both the chart and battle, even while paused. Shift pans faster. Scroll zooms. M shows the whole coast. Home returns to a regional view around your fleet or flagship. F11 toggles fullscreen. Your flagship begins on autopilot; the fleet fights without manual steering."],
		["Command a flotilla", "Left-click a boat or drag a box to select; Shift adds boats. Right-click open water to move, an enemy to attack, or an ally to escort. Space pauses. Tab opens a paused tactical overview and restores your prior pause state when closed. 1 engages, 2 escorts the flagship, 3 holds. Each side fields up to 300 deployment points. U toggles flagship autopilot; optional manual controls use the arrows and mouse. X cycles flagship."] ,
		["Refit your boat", "Dock at a harbor and open Refit, or use the Fleet refit button. Fit compatible machine guns, cannons, rocket racks and torpedo launchers within each hull’s fitting budget. Engine and armor packages trade speed, fuel use and protection. The bill shows physical materials, paid fitting workers, experts and duty. Removed modules remain in that boat’s locker; stored modules still need paid installation. Refitting does not repair existing damage."],
		["Flooding and hull damage", "Hits can puncture hulls, wound sailors, damage engines, and start fires. Breaches admit water; too much water sinks a boat even if its hull is intact. Powered pumps need fuel and engine power. Crew can bail without supplies. More water slows the boat."],
		["Crew assignments", "Balanced divides hands among guns, bailing and repair. Bail water moves hands off the guns. Patch & repair closes holes using supplies, then slowly repairs hull once holes are closed. Guns first leaves little damage control. Wounded sailors cannot work. Fixed helmsman and gunner details are just part of a boat's art."],
		["Production and trade", "Villages hire woodcutters, carpenters, miners, smelters and other trades. They need both inputs and payroll. Buy abundant goods and sell into shortages. Your cargo can restart a stalled workshop. A commissioned hull needs its full bill of materials, workforce and supervisors."],
		["Buying and repairing boats", "Buy completed hulls at a yard; the price of minimum crew is added. Recruit toward optimal crew for full efficiency. Drydock consumes repair kits and coins. Refill working stores from local stock, or buy reserves into the hold and load them. Victory may offer a battered hull to recover; it needs crew and repairs."],
		["Save your voyage", "Autosaves happen on the campaign chart and after major actions. Manual saves are in the captain's menu. Saves live in a saves folder beside the portable game. Quick battle is separate from the campaign. If every boat is lost, a harbor rescue provides another cheap skiff on a funded harbor loan."],
		["Story contracts", "The eight story contracts lead through the original archipelago to the blockade flagship. Side patrols and sealed-freight jobs provide extra income. The world remains playable after the finale. Use the main menu fleet laboratory to test any hulls and fittings without spending career coins. M shows the expanded coast. Click numbered fittings in the yard preview to select a mount."]
		,["Voyage planning","Prepare expedition shows hold space, wages and return reserves. I opens island surveys, K holds compatible jobs and contacts, and L opens regional goals. Salvage individual wrecks, follow coastal stories, earn faction access and support real convoys. A paid home-harbor business stores cargo and hires shore workers. You own your whole roster while each battle deploys up to 300 points; stored and traveling support boats remain separate."]
	]:
		label(body, section[0], 24, GOLD, true)
		paragraph(body, section[1], 17)
		rule(body)

func open_menu():
	modal_kind = "menu"
	var body = modal("Captain's desk", "BRASS TIDE · v%s" % host.Version.text(), 650, 690)
	button(body, "Resume", close_modal, true).grab_focus()
	if host.lab_active:
		button(body,"Restart same fleets / seed",host.start_lab)
		button(body,"Change laboratory fleets",host.open_lab)
	button(body, "Save voyage", func(): host.save_game(true)).disabled = host.mode != "campaign"
	button(body, "Load saved voyage", func(): host.load_game()).disabled = not host.has_save() or host.lab_active
	if host.mode=="campaign":button(body,"Coastal traffic",func():NavalUI.open(self))
	button(body, "Captain's guide", open_guide, false, false)
	button(body, "Fleet register · all %d hulls" % host.data.HULLS.size(), open_catalog)
	button(body, "Settings & performance", open_settings)
	button(body,"Development notes",func():CampaignUI.notes(self))
	button(body, "Main menu", func(): host.return_to_title())
	button(body, "Quit to desktop", func(): host.quit_game())

func open_settings():
	modal_kind = "settings"
	var body = modal("Settings", "VIDEO · AUDIO · PERFORMANCE", 800, 650)
	button(body, "Toggle fullscreen · F11", host.toggle_fullscreen)
	button(body, "Sound: ON" if host.audio.enabled else "Sound: OFF", func(): host.audio.enabled = not host.audio.enabled; host.save_preferences(); open_settings())
	for pair in [["weapon_volume","Weapons"],["ambience_volume","Engines / ambience"]]:
		label(body,pair[1],14,GOLD)
		var volume_slider=HSlider.new()
		volume_slider.min_value=0;volume_slider.max_value=1;volume_slider.step=0.01;volume_slider.value=host.audio.get(pair[0])
		volume_slider.custom_minimum_size=Vector2(360,24)
		var property: String=pair[0]
		volume_slider.value_changed.connect(func(value):host.audio.set(property,value);host.save_preferences())
		body.add_child(volume_slider)
	button(body,"Music: "+("ON" if host.music.enabled else "OFF"),func():host.music.enabled=not host.music.enabled;host.save_preferences();open_settings())
	paragraph(body,"Now playing: "+host.music.title(),15,GOLD)
	var music_volume=HSlider.new()
	music_volume.min_value=0;music_volume.max_value=1;music_volume.step=0.01;music_volume.value=host.music.volume
	music_volume.custom_minimum_size=Vector2(360,28)
	music_volume.value_changed.connect(func(value):host.music.volume=value;host.save_preferences())
	body.add_child(music_volume)
	var music_actions=row(body)
	button(music_actions,"Next track",func():host.music.next_track();open_settings())
	button(music_actions,"Reload music folder",func():host.music.rescan();host.music.next_track();open_settings())
	paragraph(body,"Add MP3, OGG or WAV files to music beside the game, or your Desktop's Brass Tide Music folder. New tracks are detected automatically.",14)
	button(body, "Frame cap: %d" % Engine.max_fps, func(): Engine.max_fps = 60 if Engine.max_fps == 120 else 120; host.save_preferences(); open_settings())
	button(body,"Development tools: "+("ON · F9 overlay" if host.dev_enabled else "OFF"),func():host.dev_enabled=not host.dev_enabled;host.save_preferences();open_settings())
	paragraph(body, "Options are saved beside the game. Music is optional and can be added while the game is running. A lower frame cap reduces power use.", 16)
	paragraph(body, "CPU: %s\nThreads: %d · Adapter: %s\nCurrent frame rate: %d FPS" % [OS.get_processor_name(), OS.get_processor_count(), RenderingServer.get_video_adapter_name(), Engine.get_frames_per_second()], 15, TEAL)
	button(body, "Back", close_modal if host.mode=="menu" else open_menu)

func outcome(result: String, report: Dictionary, enemies: Array):
	modal_kind = "outcome"
	var body = modal("Waters secured" if result == "won" else "Fleet withdrawn" if result == "retreated" else "Lost at sea", "AFTER ACTION REPORT", 820, 690)
	paragraph(body, "Inspect the damage and load fresh stores before your next engagement." if result == "won" else "Surviving hulls carry their damage, wounded and missing stores back to the campaign. A withdrawal can save a fleet.", 18)
	label(body, "+%s coins" % money(report.get("coins", 0)), 38, GOLD, true)
	var afloat: int = host.battle.ships.filter(func(s): return s.team == "player" and not s.sunk).size()
	paragraph(body, "%s encountered · %s afloat" % [count_text(enemies.size(), "hostile boat", "hostile boats"), count_text(afloat, "friendly boat", "friendly boats")], 17, TEAL)
	for participant in report.get("participants",[]):
		var entry: Dictionary=participant
		rule(body)
		label(body,"%s · %s"%[str(entry.name),str(entry.fate).capitalize()],21,RED if str(entry.fate) in ["sunk","captured"] else GOLD,true)
		paragraph(body,"Crew %.0f → %.0f · Wounded %.0f → %.0f · %.0f fewer aboard"%[float(entry.crewStart),float(entry.crewEnd),float(entry.woundedStart),float(entry.woundedEnd),float(entry.crewDecrease)],15)
		var repair: Dictionary=entry.get("repair",{})
		paragraph(body,"Hull %.0f / %.0f · %.0f damage to repair · Water %.0f · Fire %.0f · Engine %.0f%%"%[float(entry.hpEnd),float(entry.maxHp),float(repair.get("missingHp",0)),float(repair.get("water",0)),float(repair.get("fire",0)),float(repair.get("engine",0))*100.0],14)
		paragraph(body,IdentityUI.service_summary(entry),14,TEAL)
		var history: Array=entry.get("serviceHistory",[])
		if not history.is_empty():paragraph(body,str(history[-1].get("detail","")),14)
		if str(entry.fate)=="sunk":paragraph(body,"Ending crew is the last recorded count aboard, not rescued survivors. History follows the marked wreck. A paid tow returns a damaged, empty hull; recruitment, repairs and stores are separate costs. Lost staff are not returned.",14,RED)
	if report.get("completed", false):
		label(body, "THE SHATTER COAST IS FREE", 26, GOLD, true)
		paragraph(body, "The blockade has ended. You can continue trading, building and sailing.")
	if host.quick_mode:
		button(body, "Fight another skirmish", host.quick_battle, true)
		button(body, "Main menu", host.return_to_title)
		return
	if not report.get("wrecks",[]).is_empty():
		paragraph(body,"%s marked. Recovery choices persist on the coastal chart."%count_text(report.wrecks.size(),"individual wreck","individual wrecks"),16,GOLD)
		button(body,"Inspect wrecks & recovery",func():host.return_to_campaign();RecoveryUI.open(self)).disabled=host.core.active_fleet().is_empty()
	var salvage = report.get("salvage", {})
	if result == "won" and not salvage.is_empty():
		paragraph(body, "Recoverable hull: %s. Tug labor, engineer inspection and company fee: %s coins. It returns at 35%% hull with no crew or stores." % [salvage.name, money(host.core.salvage_quote(salvage.id).total)], 15)
		var recovery_button = button(body, "Recover %s" % salvage.name, func(): host.recover_salvage(salvage.id))
		recovery_button.disabled = not host.core.can_add_boat(salvage)
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
	var in_battle: bool=host!=null and host.mode=="battle"
	text.custom_minimum_size.x = 340 if in_battle else 440
	if in_battle:
		text.max_lines_visible=2
		text.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		text.tooltip_text=message
		text.mouse_filter=Control.MOUSE_FILTER_PASS
	notices.add_child(container)
	while notices.get_child_count() > (1 if in_battle else 4):
		var old = notices.get_child(0)
		notices.remove_child(old)
		old.queue_free()
	var tween = container.create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(container, "modulate:a", 0.0, 0.4)
	tween.tween_callback(container.queue_free)

func money(value) -> String:
	var s = str(int(value))
	var result = ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			result += ","
		result += s[i]
	return result

func count_text(count: int, singular: String, plural: String = "") -> String:
	var word: String = singular if count == 1 else (singular + "s" if plural.is_empty() else plural)
	return "%d %s" % [count, word]
