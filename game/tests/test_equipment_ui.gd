extends SceneTree
## Headless fixture for the detached equipment panel.
## Not registered in tools/check_game.py. This workspace does not launch Godot.
## Sol runs it later with the engine lease. Pose and dictionary inputs are not boat motion.
const Core = preload("res://scripts/equipment_condition.gd")
const Refit = preload("res://scripts/refit.gd")
const EquipmentPanel = preload("res://scripts/equipment_ui.gd")
var game
var checks: int = 0
var failures: int = 0
var calls: Dictionary = {"priority": [], "repair": 0, "workshop": 0, "refresh": 0}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL equipment UI: " + message)

func descendants(node: Node) -> Array:
	var result: Array = [node]
	for child in node.get_children():
		result.append_array(descendants(child))
	return result

func visible_text() -> String:
	var text: Array[String] = []
	for node in descendants(game.ui.overlay):
		if node is Label or node is Button:
			text.append(str(node.text))
	return "\n".join(text)

func find_button(prefix: String):
	for node in descendants(game.ui.overlay):
		if node is Button and str(node.text).begins_with(prefix):
			return node
	return null

func press(prefix: String) -> bool:
	var button = find_button(prefix)
	check(button != null and not button.disabled, "real control is available: " + prefix)
	if button == null or button.disabled:
		return false
	button.pressed.emit()
	return true

func part_name(type_id: String) -> String:
	var catalog: Dictionary = Refit.catalog()
	for category in ["weapons", "engines", "armor"]:
		if catalog.get(category, {}).has(type_id):
			return str(catalog[category][type_id].get("name", type_id))
	return ""

func located(condition: Dictionary, location: String) -> Dictionary:
	for key in condition.items.keys():
		if str(condition.items[key].location) == location:
			return condition.items[key]
	return {}

func view_row(item: Dictionary) -> Dictionary:
	return {
		"slot": str(item.location),
		"name": part_name(str(item.typeId)),
		"hp": float(item.hp),
		"status": str(item.status),
		"cause": str(item.cause),
		"itemUid": str(item.itemUid),
	}

func actions() -> Dictionary:
	return {
		"setPriority": func(value): calls.priority.append(str(value)),
		"repair": func(): calls.repair += 1,
		"workshop": func(): calls.workshop += 1,
		"refresh": func(): calls.refresh += 1,
	}

func quote(ok: bool, message: String) -> Dictionary:
	return {
		"ok": ok,
		"message": message,
		"cost": 40,
		"materials": {"iron": 2},
		"ordinary": 12,
		"expert": 7,
		"fee": 3,
	}

func build_model(boat: Dictionary) -> Dictionary:
	var fixture: Dictionary = {"id": "launch", "type": "launch", "uid": "spawn-pending", "engine": 1.0}
	var installed: Array = [
		{"family": "weapons", "typeId": "stock_primary", "originHullType": "launch", "location": "mount0"},
		{"family": "engines", "typeId": "stock_engine", "originHullType": "launch", "location": "engine"},
		{"family": "armor", "typeId": "stock_armor", "originHullType": "launch", "location": "armor"},
	]
	var locker: Array = [
		{"family": "weapons", "typeId": "rapid_gun", "originHullType": "launch", "location": "locker", "hp": 0.4, "cause": "Salvaged"},
	]
	var seeded: Dictionary = Core.legacy_seed(fixture, {
		"identity": "phys-ui-panel",
		"hullType": "launch",
		"mountCount": 2,
		"installed": installed,
		"locker": locker,
		"engineScalar": 1.0,
	})
	check(seeded.ok, "detached core seed supplies the panel rows")
	if not seeded.ok:
		return {}
	var engine: Dictionary = located(fixture.moduleCondition, "engine")
	var hurt: Dictionary = Core.apply_component_damage(fixture.moduleCondition, {"itemUid": engine.itemUid, "loss": 0.8, "cause": "Shell splinter"})
	check(hurt.ok and str(hurt.status) == "disabled", "core disables the engine before the partial repair")
	var lifted: Dictionary = Core.repair_installed(fixture.moduleCondition, {
		"work": 0.05,
		"supplies": 1.0,
		"hpPerWork": 1.0,
		"suppliesPerHp": {"engines": 1.0},
		"priority": "engine",
		"juryCap": 0.75,
	})
	engine = located(fixture.moduleCondition, "engine")
	check(lifted.ok and is_equal_approx(float(engine.hp), 0.25) and str(engine.status) == "disabled", "core leaves that engine disabled at 0.25")
	var installed_rows: Dictionary = Core.inspect_installed(fixture.moduleCondition)
	var spare_rows: Dictionary = Core.list_locker(fixture.moduleCondition)
	check(installed_rows.ok and spare_rows.ok and installed_rows.items.size() == 3 and spare_rows.items.size() == 1, "core lists the installed parts and the one spare")
	if not installed_rows.ok or not spare_rows.ok:
		return {}
	var rows: Array = []
	for item in installed_rows.items:
		rows.append(view_row(item))
	var spares: Array = []
	for item in spare_rows.items:
		spares.append(view_row(item))
	for row in rows + spares:
		check(str(row.name) != "", "catalog supplies the displayed part name for " + str(row.slot))
	return {
		"uid": str(boat.uid),
		"name": str(boat.name),
		"priority": "auto",
		"rows": rows,
		"spares": spares,
		"supplies": 6,
		"repairCrew": 2,
		"juryCap": 0.75,
		"inPort": true,
		"quote": quote(false, "The harbor has no iron for this repair."),
		"debug": false,
	}

func career_file() -> String:
	return FileAccess.get_file_as_string(game.save_directory.path_join("voyage.json"))

func exercise(model: Dictionary, spy: Dictionary, before_state: Dictionary, before_file: String) -> void:
	var held: Dictionary = model.duplicate(true)
	EquipmentPanel.open(game.ui, model, spy)
	var text: String = visible_text()
	check(game.ui.modal_open and game.ui.modal_kind == "equipment", "panel uses the live modal")
	check(str(game.core.state.fleet[0].name) in text, "panel titles the career boat")
	check("Disabled" in text and "Condition 25%" in text and "Shell splinter" in text, "disabled 0.25 engine is shown with its cause")
	check("Original engine" in text and "Needle machine gun" in text and "Condition 40%" in text and "Salvaged" in text, "installed and spare conditions both come from the core rows")
	check("not available" in text and "Damaged" in text and "Operational" in text, "disabled, damaged, and operational states are distinct")
	check("Repair kits 6" in text and "current repair effort 2" in text and "jury repairs stop at 75%" in text, "kits, effort, and jury cap are the supplied figures")
	check("No mechanical pump is aboard" in text and "Armor and loose spares need the yard" in text, "missing pumps stay missing and the yard note is explicit")
	check("crew duty" in text and not ("Balanced" in text or "Bail" in text), "machinery order does not replace crew duty")
	check("40 COINS" in text and "2 × Iron" in text and "Shipwright wages: 12 coins" in text and "Mechanic wages: 7 coins" in text and "Fee: 3 coins" in text, "harbor bill shows the supplied coins, materials, wages, and fee")
	check("The harbor has no iron for this repair." in text, "unavailable quote message is shown unchanged")
	var blocked = find_button("Repair installed parts")
	check(blocked != null and blocked.disabled and blocked.text == "Repair installed parts", "failed quote disables repair and does not offer a coin button")
	var engine_mark: String = ""
	for row in model.rows:
		if str(row.slot) == "engine":
			engine_mark = str(row.itemUid)
	check(engine_mark != "" and not engine_mark in text, "physical part ids stay hidden when debug is off")
	check(model == held, "reading the failed quote does not rewrite the model")
	check(game.core.state == before_state and career_file() == before_file, "reading the failed quote does not rewrite the saved career")
	var closer = find_button("×")
	check(closer != null, "the modal supplies its own close control")
	if closer != null:
		closer.pressed.emit()
	check(not game.ui.modal_open and game.ui.modal_kind == "", "close goes through the existing modal")

	model.quote = quote(true, "The yard can do this repair.")
	held = model.duplicate(true)
	var repair_before: int = int(calls.repair)
	EquipmentPanel.open(game.ui, model, spy)
	check(press("Repair installed parts · 40 coins"), "successful quote enables the coin repair control")
	check(int(calls.repair) == repair_before + 1 and int(calls.workshop) == 0, "the repair control calls only the repair action")
	check(press("Open the fitting bay"), "workshop control is present")
	check(int(calls.workshop) == 1 and int(calls.repair) == repair_before + 1, "workshop calls only its own action")
	check(press("Check this boat again"), "refresh control is present")
	check(int(calls.refresh) == 1, "refresh calls only its own action")
	check(press("Pumps first"), "machinery priority control is present")
	check(calls.priority == ["pumps"], "priority calls the supplied action once with the canonical value")
	check(model == held, "callbacks do not rewrite the model")
	if find_button("×") != null:
		find_button("×").pressed.emit()

	model.debug = true
	held = model.duplicate(true)
	EquipmentPanel.open(game.ui, model, spy)
	check(engine_mark in visible_text(), "debug shows the physical part id")
	if find_button("×") != null:
		find_button("×").pressed.emit()
	check(model == held, "debug display does not rewrite the model")

	model.debug = false
	model.inPort = false
	model.quote = quote(true, "Crew can spend the kits already aboard.")
	held = model.duplicate(true)
	EquipmentPanel.open(game.ui, model, spy)
	var sea: String = visible_text()
	var sea_repair = find_button("Repair installed parts")
	check("YARD BILL" not in sea and "COINS" not in sea and "Dock at a harbor" in sea, "at sea the yard bill is not invented")
	check(sea_repair != null and not sea_repair.disabled and sea_repair.text == "Repair installed parts", "at sea a ready quote repairs without a coin price")
	var sea_before: int = int(calls.repair)
	if sea_repair != null and not sea_repair.disabled:
		sea_repair.pressed.emit()
	check(int(calls.repair) == sea_before + 1, "the sea repair control calls the repair action once")
	if find_button("×") != null:
		find_button("×").pressed.emit()
	check(model == held, "the sea panel leaves the model unchanged")

	var refused: Dictionary = held.duplicate(true)
	refused.supplies = INF
	EquipmentPanel.open(game.ui, refused, spy)
	check(not game.ui.modal_open and find_button("Repair installed parts") == null, "a non-finite kit count does not open a working panel")
	check(is_inf(float(refused.supplies)), "refusal does not replace the rejected number")
	EquipmentPanel.open(game.ui, held, {})
	check(not game.ui.modal_open, "missing actions do not open a working panel")
	check(game.core.state == before_state and career_file() == before_file, "the whole fixture leaves the paid career and its save unchanged")
	check(int(game.core.state.coins) == int(before_state.coins), "no control debits coins")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() != "headless":
		check(false, "this suite requires the root's hidden headless/silent engine lease")
	else:
		game = load("res://main.tscn").instantiate()
		root.add_child(game)
		game.set_process(false)
		game.set_physics_process(false)
		game.audio.enabled = false
		game.music.enabled = false
		game.save_directory = OS.get_user_data_dir().path_join("equipment-ui-%d" % Time.get_ticks_usec())
		await process_frame
		game.new_game()
		game.paused = true
		game.audio.enabled = false
		game.music.enabled = false
		var boat: Dictionary = game.core.state.fleet[0]
		var before_state: Dictionary = game.core.state.duplicate(true)
		var before_file: String = career_file()
		check(not before_file.is_empty() and game.save_directory != "" and "equipment-ui-" in game.save_directory, "the career save is an isolated non-empty file")
		var model: Dictionary = build_model(boat)
		if not model.is_empty():
			exercise(model, actions(), before_state, before_file)
		game.queue_free()
		await process_frame
	print("equipment UI: %d checks, %d failures; native controls only, background/headless/silent" % [checks, failures])
	quit(0 if failures == 0 else 1)
