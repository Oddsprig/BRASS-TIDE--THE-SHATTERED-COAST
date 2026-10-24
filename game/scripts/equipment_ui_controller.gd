extends RefCounted
## Main-thread v0.031 fleet equipment condition and harbor service controller.
## Connects real Campaign/Damage/EquipmentCondition/EquipmentRecords/Harbor state to pure EquipmentUI.
## Read-only on open; never initializes legacy hulls from the view and never calls free restoration.

const Core = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const Damage = preload("res://scripts/damage.gd")
const Refit = preload("res://scripts/refit.gd")
const EquipmentUI = preload("res://scripts/equipment_ui.gd")

static func _clean_text(value, fallback: String, max_len: int) -> String:
	var raw: String = str(value) if value != null else ""
	var chars: PackedStringArray = PackedStringArray()
	for i in raw.length():
		var code: int = raw.unicode_at(i)
		if code < 32 or code == 127:
			chars.append(" ")
		else:
			chars.append(raw.substr(i, 1))
	var joined: String = "".join(chars).strip_edges()
	if joined.is_empty():
		joined = fallback
	if joined.length() > max_len:
		joined = joined.substr(0, max_len).strip_edges()
	return joined

static func _module_display_name(family: String, type_id: String) -> String:
	if family == "pumps" or type_id == Records.PUMP_TYPE_ID:
		return "Bilge pumps"
	var catalog: Dictionary = Refit.catalog()
	for group in ["weapons", "engines", "armor"]:
		var group_dict = catalog.get(group, {})
		if group_dict is Dictionary and group_dict.has(type_id):
			var entry = group_dict[type_id]
			if entry is Dictionary:
				return _clean_text(entry.get("name", type_id.capitalize()), "Fitting", EquipmentUI.MAX_TEXT)
	return _clean_text(type_id.capitalize().replace("_", " "), "Fitting", EquipmentUI.MAX_TEXT)

static func _resolve_live_boat(ui, uid: String) -> Dictionary:
	if ui == null or ui.get("host") == null or ui.host.get("core") == null:
		return {}
	var core = ui.host.core
	if not ("state" in core) or not (core.state is Dictionary) or not (core.state.get("fleet") is Array):
		return {}
	if not core.has_method("find_boat"):
		return {}
	var boat: Dictionary = core.find_boat(uid)
	if boat.is_empty() or bool(boat.get("sunk", false)):
		return {}
	for member in core.state.fleet:
		if member is Dictionary and is_same(member, boat):
			return boat
	return {}

static func _part_row(item: Dictionary, spare: bool) -> Dictionary:
	var family: String = str(item.get("family", ""))
	var type_id: String = str(item.get("typeId", ""))
	var status: String = str(item.get("status", "ok"))
	if not status in ["ok", "damaged", "disabled"]:
		status = "damaged"
	var cause: String = _clean_text(item.get("cause", ""), "", EquipmentUI.MAX_TEXT) if status != "ok" else ""
	return {
		"slot": "locker" if spare else str(item.get("location", "")),
		"name": _module_display_name(family, type_id),
		"hp": clampf(EquipmentDamage.number(item.get("hp"), 1.0), 0.0, 1.0),
		"status": status,
		"cause": cause,
		"itemUid": _clean_text(item.get("itemUid", ""), "item", EquipmentUI.MAX_MARK)
	}

static func _needs_any_repair(boat: Dictionary, installed_items: Array) -> bool:
	var max_hp: float = maxf(1.0, EquipmentDamage.number(boat.get("maxHp"), 100.0))
	var hp: float = clampf(EquipmentDamage.number(boat.get("hp"), max_hp), 0.0, max_hp)
	if max_hp - hp > 0.001:
		return true
	if EquipmentDamage._sum_areas(boat) > 0.001:
		return true
	if EquipmentDamage.number(boat.get("water"), 0.0) > 0.001:
		return true
	if EquipmentDamage.number(boat.get("fire"), 0.0) > 0.001:
		return true
	if EquipmentDamage.number(boat.get("wounded"), 0.0) > 0.001:
		return true
	if 1.0 - clampf(EquipmentDamage.number(boat.get("engine"), 1.0), 0.0, 1.0) > 0.001:
		return true
	for item in installed_items:
		if item is Dictionary and str(item.get("location", "")) != "locker":
			if float(item.get("hp", 1.0)) < Core.OK_HP or str(item.get("status", "ok")) != "ok":
				return true
	return false

static func translate_service_quote(core, boat: Dictionary, port: Dictionary, raw_quote: Dictionary, in_port: bool, installed_items: Array = []) -> Dictionary:
	var source: Dictionary = raw_quote.duplicate(true) if raw_quote is Dictionary else {}
	var materials_dict: Dictionary = {}
	if source.get("equipmentMaterials") is Dictionary:
		var eq_mats: Dictionary = source.equipmentMaterials
		var keys: Array = eq_mats.keys()
		keys.sort()
		for raw_key in keys:
			var clean_key: String = _clean_text(raw_key, "", 40)
			var amt: float = EquipmentDamage.number(eq_mats[raw_key], 0.0)
			if not clean_key.is_empty() and amt > 0.0001 and materials_dict.size() < 32:
				materials_dict[clean_key] = clampf(amt, 0.0, EquipmentUI.MAX_NUMBER)
	elif source.get("materials") is Dictionary:
		var given_mats: Dictionary = source.materials
		var keys: Array = given_mats.keys()
		keys.sort()
		for raw_key in keys:
			var clean_key: String = _clean_text(raw_key, "", 40)
			var amt: float = EquipmentDamage.number(given_mats[raw_key], 0.0)
			if not clean_key.is_empty() and amt >= 0.0 and materials_dict.size() < 32:
				materials_dict[clean_key] = clampf(amt, 0.0, EquipmentUI.MAX_NUMBER)
	var purchase_kits: float = EquipmentDamage.number(source.get("purchase"), 0.0)
	var own_kits: float = EquipmentDamage.number(source.get("own"), 0.0)
	if purchase_kits > 0.0001 and not materials_dict.has("supplies") and materials_dict.size() < 32:
		materials_dict["supplies"] = clampf(purchase_kits, 0.0, EquipmentUI.MAX_NUMBER)
	if own_kits > 0.0001 and not materials_dict.has("own kits") and materials_dict.size() < 32:
		materials_dict["own kits"] = clampf(own_kits, 0.0, EquipmentUI.MAX_NUMBER)

	var cost_coins: int = maxi(0, int(roundf(EquipmentDamage.number(source.get("cost"), 0.0))))
	var ordinary_coins: int = maxi(0, int(roundf(EquipmentDamage.number(source.get("ordinary"), 0.0))))
	var expert_coins: int = maxi(0, int(roundf(EquipmentDamage.number(source.get("expert"), 0.0))))
	var fee_coins: int = maxi(0, int(roundf(EquipmentDamage.number(source.get("fee"), 0.0))))
	var mat_coins: int = maxi(0, int(roundf(EquipmentDamage.number(source.get("materials"), 0.0)))) if not (source.get("materials") is Dictionary) else 0

	var quoted_ok: bool = false
	var message: String = _clean_text(source.get("message", source.get("error", "")), "", EquipmentUI.MAX_MESSAGE)
	var needs_work: bool = _needs_any_repair(boat, installed_items)
	var stored_port: String = str(boat.get("storedPort", "")).strip_edges()
	var coins_now: int = int(EquipmentDamage.number(core.state.get("coins"), 0.0)) if (core != null and "state" in core and core.state is Dictionary) else 0
	var port_supplies: float = EquipmentDamage.number(port.get("stocks", {}).get("supplies"), 0.0) if port.get("stocks") is Dictionary else 0.0
	var missing_good: String = ""
	if source.get("equipmentMaterials") is Dictionary and port.get("stocks") is Dictionary:
		for g_key in source.equipmentMaterials.keys():
			var need_amt: float = EquipmentDamage.number(source.equipmentMaterials[g_key], 0.0)
			var have_amt: float = EquipmentDamage.number(port.stocks.get(g_key), 0.0)
			if have_amt + 0.0001 < need_amt:
				missing_good = str(g_key)
				break
	if not in_port or port.is_empty():
		quoted_ok = false
		cost_coins = 0
		ordinary_coins = 0
		expert_coins = 0
		fee_coins = 0
		materials_dict = {}
		if message.is_empty():
			message = "Sail to a harbor for paid yard restoration."
	elif source.has("ok") and typeof(source.get("ok")) == TYPE_BOOL and not bool(source.ok):
		quoted_ok = false
		if message.is_empty():
			message = "Harbor service is unavailable for this hull."
	elif not needs_work:
		quoted_ok = false
		if message.is_empty():
			message = "Hull and installed fittings are already at full condition."
	else:
		quoted_ok = true
		if message.is_empty():
			if not stored_port.is_empty() and stored_port != str(port.get("id", "")):
				message = "This hull is stored at another harbor."
			elif coins_now < cost_coins:
				message = "Drydock needs %d coins; your purse has %d." % [cost_coins, coins_now]
			elif port_supplies + 0.0001 < purchase_kits:
				message = "This harbor lacks the repair kits needed for drydock service."
			elif not missing_good.is_empty():
				message = "This harbor lacks enough %s in stock to restore damaged equipment." % missing_good
			elif mat_coins > 0:
				message = "Materials and repair kits on this bill: %d coins." % mat_coins
			else:
				message = "Ready for paid harbor service."

	return {
		"ok": quoted_ok,
		"message": _clean_text(message, "", EquipmentUI.MAX_MESSAGE),
		"cost": clampf(float(cost_coins), 0.0, EquipmentUI.MAX_NUMBER),
		"ordinary": clampf(float(ordinary_coins), 0.0, EquipmentUI.MAX_NUMBER),
		"expert": clampf(float(expert_coins), 0.0, EquipmentUI.MAX_NUMBER),
		"fee": clampf(float(fee_coins), 0.0, EquipmentUI.MAX_NUMBER),
		"materials": materials_dict,
		"materialsCoinCost": mat_coins
	}

static func build_model(ui, uid: String) -> Dictionary:
	if ui == null or ui.get("host") == null or ui.host.get("core") == null:
		return {"ok": false, "mode": "invalid", "error": "The fleet desk is not ready."}
	var boat: Dictionary = _resolve_live_boat(ui, uid)
	if boat.is_empty():
		return {"ok": false, "mode": "missing", "error": "Choose a living boat in your flotilla."}
	var owner_info: Dictionary = EquipmentDamage.inspect_owner(boat)
	var mode: String = str(owner_info.get("mode", "invalid"))
	if not owner_info.get("ok", false) or mode != "canonical":
		if mode == "legacy":
			return {"ok": false, "mode": "legacy", "error": "This hull has no individual equipment record yet."}
		return {
			"ok": false,
			"mode": mode,
			"error": _clean_text(owner_info.get("error", "These fittings could not be inspected."), "These fittings could not be inspected.", EquipmentUI.MAX_MESSAGE)
		}
	var snap: Dictionary = owner_info.snapshot
	var installed_res: Dictionary = Core.inspect_installed(boat.moduleCondition)
	var locker_res: Dictionary = Core.list_locker(boat.moduleCondition)
	if not installed_res.get("ok", false) or not locker_res.get("ok", false):
		return {"ok": false, "mode": "invalid", "error": "These fittings could not be inspected."}
	var rows: Array = []
	for item in installed_res.get("items", []):
		if item is Dictionary:
			rows.append(_part_row(item, false))
	var spares: Array = []
	for item in locker_res.get("items", []):
		if item is Dictionary:
			spares.append(_part_row(item, true))
	var flow: Dictionary = Damage.get_status(boat)
	var priority: String = str(snap.get("repairPriority", "auto"))
	if not (priority in EquipmentUI.PRIORITY_ORDER):
		priority = "auto"
	var port: Dictionary = ui.host.core.current_port() if ui.host.core.has_method("current_port") else {}
	var in_port: bool = port is Dictionary and not port.is_empty() and (ui.host.core.state.get("path", []).is_empty() if ui.host.core.state.get("path") is Array else true)
	var raw_quote: Dictionary = {}
	if in_port and ui.host.core.has_method("service_quote"):
		raw_quote = ui.host.core.service_quote(boat, port)
	var ui_quote: Dictionary = translate_service_quote(ui.host.core, boat, port, raw_quote, in_port, installed_res.get("items", []))
	var model: Dictionary = {
		"uid": _clean_text(boat.get("uid", uid), "boat", EquipmentUI.MAX_MARK),
		"name": _clean_text(boat.get("name", "Boat"), "Boat", EquipmentUI.MAX_TEXT),
		"priority": priority,
		"rows": rows,
		"spares": spares,
		"supplies": clampf(EquipmentDamage.number(boat.get("supplies"), 0.0), 0.0, EquipmentUI.MAX_NUMBER),
		"repairCrew": clampf(EquipmentDamage.number(flow.get("crewRepair"), 0.0), 0.0, EquipmentUI.MAX_NUMBER),
		"juryCap": clampf(EquipmentDamage.number(snap.get("juryCap"), Core.JURY_CAP), 0.30, 0.75),
		"inPort": in_port,
		"debug": bool(ui.host.get("dev_enabled")),
		"quote": {
			"ok": bool(ui_quote.ok),
			"message": str(ui_quote.message),
			"cost": float(ui_quote.cost),
			"ordinary": float(ui_quote.ordinary),
			"expert": float(ui_quote.expert),
			"fee": float(ui_quote.fee),
			"materials": ui_quote.materials.duplicate(true)
		}
	}
	return {"ok": true, "mode": "canonical", "model": model, "rawQuote": raw_quote.duplicate(true), "translatedQuote": ui_quote}

static func set_priority_action(ui, uid: String, chosen: String) -> Dictionary:
	if ui == null or ui.get("host") == null or ui.host.get("core") == null:
		return {"ok": false, "error": "The fleet desk is not ready."}
	if ui.host.has_method("sync_economy"):
		ui.host.sync_economy()
	var live_boat: Dictionary = _resolve_live_boat(ui, uid)
	if live_boat.is_empty():
		ui.toast("Choose a living boat in your flotilla.", true)
		return {"ok": false, "error": "Choose a living boat in your flotilla."}
	var owner_info: Dictionary = EquipmentDamage.inspect_owner(live_boat)
	if not owner_info.get("ok", false) or str(owner_info.get("mode", "")) != "canonical":
		var err_msg: String = _clean_text(owner_info.get("error", "Equipment condition is not initialized."), "Equipment condition is not initialized.", EquipmentUI.MAX_MESSAGE)
		ui.toast(err_msg, true)
		return {"ok": false, "error": err_msg}
	if not (chosen in Core.PRIORITIES):
		var unknown_msg: String = "Repair priority is unknown."
		ui.toast(unknown_msg, true)
		return {"ok": false, "error": unknown_msg}
	var applied_str: String = Damage.set_repair_priority(live_boat, chosen)
	if ui.host.has_method("save_game") and str(ui.host.get("mode")) == "campaign":
		ui.host.save_game(false)
	open(ui, uid)
	return {"ok": true, "repairPriority": applied_str}

static func repair_action(ui, uid: String) -> Dictionary:
	if ui == null or ui.get("host") == null or ui.host.get("core") == null:
		return {"ok": false, "message": "The fleet desk is not ready."}
	if ui.host.has_method("sync_economy"):
		ui.host.sync_economy()
	var live_boat: Dictionary = _resolve_live_boat(ui, uid)
	if live_boat.is_empty() or not EquipmentDamage.is_canonical_owner(live_boat):
		var msg: String = "Choose a living boat with valid equipment records."
		ui.toast(msg, true)
		return {"ok": false, "message": msg}
	if not ui.host.core.has_method("repair_boat"):
		var unavail_msg: String = "Harbor repair is unavailable."
		ui.toast(unavail_msg, true)
		open(ui, uid)
		return {"ok": false, "message": unavail_msg}
	var raw_res = ui.host.core.repair_boat(uid)
	var res: Dictionary = raw_res if raw_res is Dictionary else {"ok": false, "message": "Harbor repair is unavailable."}
	if ui.host.has_method("respond"):
		ui.host.respond(res)
	else:
		ui.toast(str(res.get("message", res.get("error", ""))), not res.get("ok", false))
	if res.get("ok", false) and ui.host.has_method("save_game") and str(ui.host.get("mode")) == "campaign":
		ui.host.save_game(false)
	open(ui, uid)
	return res

static func workshop_action(ui, uid: String) -> void:
	var live_boat: Dictionary = _resolve_live_boat(ui, uid)
	if live_boat.is_empty():
		ui.toast("Choose a living boat in your flotilla.", true)
		return
	if ui.has_method("open_refit"):
		ui.open_refit(uid)

static func open(ui, uid: String) -> bool:
	if ui == null:
		return false
	var built: Dictionary = build_model(ui, uid)
	if not built.get("ok", false):
		if ui.has_method("toast"):
			ui.toast(str(built.get("error", "These fittings could not be shown.")), true)
		return false
	var actions: Dictionary = {
		"setPriority": func(chosen: String): set_priority_action(ui, uid, chosen),
		"repair": func(): repair_action(ui, uid),
		"workshop": func(): workshop_action(ui, uid),
		"refresh": func(): open(ui, uid)
	}
	EquipmentUI.open(ui, built.model, actions)
	return str(ui.get("modal_kind")) == "equipment"
