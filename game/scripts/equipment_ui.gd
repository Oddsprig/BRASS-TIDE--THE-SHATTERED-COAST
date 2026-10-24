extends RefCounted
## Detached v0.031 equipment condition panel.
## Renders a caller-supplied model and calls caller-supplied actions.
## No preload. Does not mutate hulls, money, the model, or the action dictionary.

const MAX_INSTALLED: int = 7
const MAX_SPARES: int = 256
const MAX_TEXT: int = 80
const MAX_MESSAGE: int = 240
const MAX_MARK: int = 96
const MAX_NUMBER: float = 1000000000000.0
const PRIORITY_ORDER: Array = ["auto", "hull", "pumps", "engine", "weapons"]
const INSTALLED_SLOTS: Array = ["mount0", "mount1", "mount2", "mount3", "engine", "armor", "pumps"]

static func open(ui, model: Dictionary, actions: Dictionary) -> void:
	if not _surface(ui):
		return
	if not _accepted(model, actions):
		ui.toast("These fittings could not be shown.", true)
		return
	var priority: String = str(model.priority)
	var quote: Dictionary = model.quote
	var in_port: bool = bool(model.inPort)
	var show_marks: bool = bool(model.debug)
	var set_priority: Callable = actions.setPriority
	var repair_action: Callable = actions.repair
	var workshop_action: Callable = actions.workshop
	var refresh_action: Callable = actions.refresh
	var quoted_ok: bool = bool(quote.ok)
	var pumps_listed: bool = false
	for entry in model.rows:
		if str(entry.slot) == "pumps":
			pumps_listed = true
	ui.modal_kind = "equipment"
	var body: VBoxContainer = ui.modal(str(model.name), "FITTINGS · CONDITION · REPAIR", 1100, 850)
	ui.paragraph(body, "Check this boat's mounted guns, machinery, armor, and spare parts.", 15)
	ui.paragraph(body, "Repair kits %s · current repair effort %s · jury repairs stop at %s." % [_amount(float(model.supplies)), _amount(float(model.repairCrew)), _percent(float(model.juryCap))], 16, ui.TEAL)
	ui.paragraph(body, "Armor and loose spares need the yard for full restoration.", 14)
	ui.paragraph(body, "Choose which damaged machinery your repair hands tend first; crew duty for guns, bailing, and patching stays on the fleet card.", 14)
	var priorities: HBoxContainer = ui.row(body)
	for value in PRIORITY_ORDER:
		var chosen: String = str(value)
		var control: Button = ui.button(priorities, _priority_label(chosen), _bind_priority(set_priority, chosen))
		if chosen == priority:
			control.add_theme_color_override("font_color", ui.GOLD)
	ui.rule(body)
	ui.eyebrow(body, "Installed")
	_list_parts(ui, body, model.rows, show_marks, false)
	if not pumps_listed:
		ui.paragraph(body, "No mechanical pump is aboard. Hand bailing is unchanged.", 14)
	ui.rule(body)
	ui.eyebrow(body, "Loose spares")
	_list_parts(ui, body, model.spares, show_marks, true)
	ui.rule(body)
	if in_port:
		ui.eyebrow(body, "Yard bill")
		ui.label(body, "%s COINS" % ui.money(quote.cost), 29, ui.GOLD, true)
		_materials(ui, body, quote.materials)
		ui.paragraph(body, "Shipwright wages: %s coins\nMechanic wages: %s coins\nFee: %s coins" % [ui.money(quote.ordinary), ui.money(quote.expert), ui.money(quote.fee)], 16)
	else:
		ui.paragraph(body, "Dock at a harbor to see the yard's repair bill.", 15, ui.GOLD)
	if not str(quote.message).is_empty():
		ui.paragraph(body, str(quote.message), 15, ui.GOLD if not quoted_ok else ui.TEAL)
	var commands: HBoxContainer = ui.row(body)
	var repair_text: String = "Repair installed parts"
	if in_port and quoted_ok:
		repair_text = "Repair installed parts · %s coins" % ui.money(quote.cost)
	var repair_button: Button = ui.button(commands, repair_text, _bind_repair(repair_action, quoted_ok), quoted_ok)
	repair_button.disabled = not quoted_ok
	ui.button(commands, "Open the fitting bay", _bind_plain(workshop_action))
	ui.button(commands, "Check this boat again", _bind_plain(refresh_action))
	ui.button(body, "Return to voyage", ui.close_modal, true)

static func _surface(ui) -> bool:
	if ui == null:
		return false
	for method_name in ["modal", "button", "label", "paragraph", "row", "column", "eyebrow", "rule", "close_modal", "money", "toast"]:
		if not ui.has_method(method_name):
			return false
	return true

static func _accepted(model: Dictionary, actions: Dictionary) -> bool:
	if not _text(model.get("uid"), 1, MAX_MARK) or not _text(model.get("name"), 1, MAX_TEXT):
		return false
	if typeof(model.get("priority")) != TYPE_STRING or not str(model.priority) in PRIORITY_ORDER:
		return false
	if not model.get("rows") is Array or not model.get("spares") is Array:
		return false
	var rows: Array = model.rows
	var spares: Array = model.spares
	if rows.size() > MAX_INSTALLED or spares.size() > MAX_SPARES:
		return false
	if not _num(model.get("supplies"), 0.0, MAX_NUMBER) or not _num(model.get("repairCrew"), 0.0, MAX_NUMBER):
		return false
	if not _num(model.get("juryCap"), 0.30, 0.75):
		return false
	if typeof(model.get("inPort")) != TYPE_BOOL or typeof(model.get("debug")) != TYPE_BOOL:
		return false
	if not model.get("quote") is Dictionary or not _quote(model.quote):
		return false
	var seen: Dictionary = {}
	var slots: Dictionary = {}
	for entry in rows:
		if not _part(entry, false, seen, slots):
			return false
	for entry in spares:
		if not _part(entry, true, seen, slots):
			return false
	for key in ["setPriority", "repair", "workshop", "refresh"]:
		var action = actions.get(key, null)
		if typeof(action) != TYPE_CALLABLE or not (action as Callable).is_valid():
			return false
	return true

static func _quote(quote: Dictionary) -> bool:
	if typeof(quote.get("ok")) != TYPE_BOOL or not _text(quote.get("message"), 0, MAX_MESSAGE):
		return false
	if not _num(quote.get("cost"), 0.0, MAX_NUMBER) or not _num(quote.get("ordinary"), 0.0, MAX_NUMBER):
		return false
	if not _num(quote.get("expert"), 0.0, MAX_NUMBER) or not _num(quote.get("fee"), 0.0, MAX_NUMBER):
		return false
	if not quote.get("materials") is Dictionary or quote.materials.size() > 32:
		return false
	for key in quote.materials.keys():
		if not _text(key, 1, 40) or not _num(quote.materials[key], 0.0, MAX_NUMBER):
			return false
	return true

static func _part(entry, spare: bool, seen: Dictionary, slots: Dictionary) -> bool:
	if not entry is Dictionary:
		return false
	var slot = entry.get("slot")
	if typeof(slot) != TYPE_STRING:
		return false
	if spare:
		if slot != "locker":
			return false
	elif not (slot in INSTALLED_SLOTS) or slots.has(slot):
		return false
	else:
		slots[slot] = true
	if not _text(entry.get("name"), 1, MAX_TEXT) or not _num(entry.get("hp"), 0.0, 1.0):
		return false
	if typeof(entry.get("status")) != TYPE_STRING or not str(entry.status) in ["ok", "damaged", "disabled"]:
		return false
	if not _text(entry.get("cause"), 0, MAX_TEXT) or not _text(entry.get("itemUid"), 1, MAX_MARK):
		return false
	var mark: String = str(entry.itemUid)
	if seen.has(mark):
		return false
	seen[mark] = true
	return true

static func _num(value, low: float, high: float) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= low and number <= high

static func _text(value, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = value
	if text.length() < minimum or text.length() > maximum:
		return false
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code < 32 or code == 127:
			return false
	return true

static func _list_parts(ui, body: Node, rows: Array, show_marks: bool, spares: bool) -> void:
	if rows.is_empty():
		ui.paragraph(body, "No loose spares are aboard." if spares else "No installed parts are listed.", 15)
		return
	for entry in rows:
		var block: VBoxContainer = ui.column(ui.row(body))
		ui.label(block, "%s · %s" % [_slot_label(str(entry.slot)), str(entry.name)], 20, ui.TEXT, true)
		ui.paragraph(block, "%s · Condition %s · %s" % [_status_word(str(entry.status)), _percent(float(entry.hp)), _availability(str(entry.status))], 15, ui.TEAL)
		if not str(entry.cause).is_empty():
			ui.paragraph(block, "Last damage: %s" % str(entry.cause), 14)
		if show_marks:
			ui.label(block, str(entry.itemUid), 12, ui.MUTED)

static func _materials(ui, body: Node, materials: Dictionary) -> void:
	if materials.is_empty():
		ui.paragraph(body, "No materials are on this bill.", 14, ui.TEAL)
		return
	ui.eyebrow(body, "Materials")
	var names: Array = materials.keys()
	names.sort()
	for key in names:
		ui.label(body, "%s × %s" % [_amount(float(materials[key])), str(key).capitalize()], 14, ui.MUTED)

static func _bind_priority(action: Callable, chosen: String) -> Callable:
	return func(): action.call(chosen)

static func _bind_repair(action: Callable, allowed: bool) -> Callable:
	return func():
		if allowed:
			action.call()

static func _bind_plain(action: Callable) -> Callable:
	return func(): action.call()

static func _priority_label(priority: String) -> String:
	match priority:
		"auto": return "As needed"
		"hull": return "Hull first"
		"pumps": return "Pumps first"
		"engine": return "Engine first"
		"weapons": return "Guns first"
		_: return "As needed"

static func _slot_label(slot: String) -> String:
	match slot:
		"mount0": return "Mount 1"
		"mount1": return "Mount 2"
		"mount2": return "Mount 3"
		"mount3": return "Mount 4"
		"engine": return "Engine"
		"armor": return "Armor"
		"pumps": return "Pumps"
		"locker": return "Spare"
		_: return "Fitting"

static func _status_word(status: String) -> String:
	match status:
		"ok": return "Operational"
		"damaged": return "Damaged"
		"disabled": return "Disabled"
		_: return "Unavailable"

static func _availability(status: String) -> String:
	match status:
		"ok": return "available"
		"damaged": return "limited"
		"disabled": return "not available"
		_: return "not available"

static func _percent(value: float) -> String:
	var points: float = clampf(value, 0.0, 1.0) * 100.0
	if absf(points - roundf(points)) < 0.05:
		return "%d%%" % int(roundf(points))
	return "%.1f%%" % points

static func _amount(value: float) -> String:
	if not is_finite(value):
		return "0"
	var nearest: float = roundf(value)
	if absf(value - nearest) <= 0.000001 and absf(nearest) <= 9007199254740991.0:
		return str(int(nearest))
	return "%.2f" % value
