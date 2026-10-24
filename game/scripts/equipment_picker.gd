extends RefCounted
## Shared v0.031 physical part-choice and draft request helper for RefitUI and WorkshopUI.
## Keeps draft request state in Interface outside campaign saves, bounded to living fleet hulls,
## and invalidated on career replacement, draft reset, template load, or hull removal.
## Preloads only Core, Records, EquipmentDamage, Refit, FleetWorkshop, and MountLayout.

const Core = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const Refits = preload("res://scripts/refit.gd")
const Workshop = preload("res://scripts/fleet_workshop.gd")
const Layout = preload("res://scripts/mount_layout.gd")

## Roster draft/request cap matches SaveValidation.MAX_ROSTER and Campaign.MAX_FLEET (96 owned hulls:
## 300 DP of 8-DP hulls is 37 active boats plus harbor reserve margin).
const MAX_ROSTER_REQUESTS: int = 96

static func inspect_boat(boat: Dictionary) -> Dictionary:
	return EquipmentDamage.inspect_owner(boat)

static func is_canonical(boat: Dictionary) -> bool:
	return str(inspect_boat(boat).get("mode", "")) == "canonical"

static func dev_enabled(ui) -> bool:
	return bool(ui != null and ui.get("host") != null and bool(ui.host.get("dev_enabled")))

static func slot_to_location(slot: String) -> String:
	if slot == "engine" or slot == "armor":
		return slot
	if slot.begins_with("weapon:"):
		var suffix: String = slot.substr(7)
		if not suffix.is_empty() and suffix.is_valid_int() and str(int(suffix)) == suffix:
			var idx: int = int(suffix)
			if idx >= 0 and idx < Core.MAX_MOUNTS:
				return "mount%d" % idx
	return ""

static func location_to_slot(location: String) -> String:
	if location == "engine" or location == "armor":
		return location
	if location.begins_with("mount") and location.length() == 6 and location.substr(5, 1).is_valid_int():
		return "weapon:%d" % int(location.substr(5, 1))
	return ""

static func slot_family(slot: String) -> String:
	if slot == "engine":
		return "engines"
	if slot == "armor":
		return "armor"
	if slot.begins_with("weapon:"):
		return "weapons"
	return ""

static func slot_title(slot: String) -> String:
	if slot == "engine":
		return "Engine"
	if slot == "armor":
		return "Armor"
	if slot.begins_with("weapon:"):
		var suffix: String = slot.substr(7)
		if suffix.is_valid_int():
			return "Mount %d" % (int(suffix) + 1)
	return slot.capitalize()

static func status_word(status: String) -> String:
	match status:
		"ok": return "Operational"
		"damaged": return "Damaged"
		"disabled": return "Disabled"
		_: return "Unavailable"

static func percent_text(value: float) -> String:
	var points: float = clampf(value, 0.0, 1.0) * 100.0
	if absf(points - roundf(points)) < 0.05:
		return "%d%%" % int(roundf(points))
	return "%.1f%%" % points

static func describe_part(item: Dictionary, show_uid: bool = false) -> String:
	if item.is_empty():
		return "Empty"
	var text: String = "%s · %s condition" % [status_word(str(item.get("status", "ok"))), percent_text(float(item.get("hp", 1.0)))]
	var cause: String = str(item.get("cause", "")).strip_edges()
	if str(item.get("status", "ok")) != "ok" and not cause.is_empty():
		text += " · " + cause
	if show_uid and not str(item.get("itemUid", "")).is_empty():
		text += " · " + str(item.itemUid)
	return text

static func installed_at(boat: Dictionary, slot: String) -> Dictionary:
	if not is_canonical(boat):
		return {}
	var loc: String = slot_to_location(slot)
	if loc.is_empty():
		return {}
	var snap: Dictionary = Records.snapshot(boat)
	if not snap.get("ok", false):
		return {}
	var installed: Dictionary = snap.get("installed", {})
	if installed.has(loc) and installed[loc] is Dictionary:
		return installed[loc].duplicate(true)
	return {}

static func item_by_uid(boat: Dictionary, item_uid: String) -> Dictionary:
	if not is_canonical(boat) or item_uid.is_empty():
		return {}
	var items: Dictionary = boat.moduleCondition.get("items", {})
	if items.has(item_uid) and items[item_uid] is Dictionary:
		return items[item_uid].duplicate(true)
	return {}

static func _module_at_loadout(loadout: Dictionary, slot: String) -> String:
	if slot == "engine" or slot == "armor":
		return str(loadout.get(slot, ""))
	if slot.begins_with("weapon:"):
		var suffix: String = slot.substr(7)
		if suffix.is_valid_int():
			var idx: int = int(suffix)
			var weapons = loadout.get("weapons", [])
			if weapons is Array and idx >= 0 and idx < weapons.size():
				return str(weapons[idx])
	return ""

static func _fits_socket(catalog: Dictionary, base: Dictionary, item: Dictionary, slot: String) -> Dictionary:
	var hull_type: String = str(base.get("id", ""))
	var loc: String = slot_to_location(slot)
	var family: String = str(item.get("family", ""))
	var type_id: String = str(item.get("typeId", ""))
	if family == "pumps":
		return {"ok": false, "reason": "Integral pumps stay in their bay."}
	if type_id in Core.STOCK_TYPES and str(item.get("originHullType", "")) != hull_type:
		return {"ok": false, "reason": "A factory part cannot be installed on a different hull design."}
	var sockets: Array = Refits.hardpoints(base)
	var tier: int = Refits._size(base)
	if loc.begins_with("mount"):
		if family != "weapons" or not catalog.get("weapons", {}).has(type_id):
			return {"ok": false, "reason": "That part does not fit this socket."}
		var idx: int = int(loc.substr(5, 1))
		if idx < 0 or idx >= sockets.size():
			return {"ok": false, "reason": "That socket is not on this hull."}
		if type_id == "stock_primary" and idx != 0:
			return {"ok": false, "reason": "The factory primary fits only the main hardpoint."}
		if int(catalog.weapons[type_id].size) > int(sockets[idx].size):
			return {"ok": false, "reason": "That part is too large for this socket."}
		return {"ok": true, "reason": ""}
	if loc == "engine":
		if family == "engines" and catalog.get("engines", {}).has(type_id) and int(catalog.engines[type_id].size) <= tier:
			return {"ok": true, "reason": ""}
		return {"ok": false, "reason": "That engine is too large for this hull."}
	if loc == "armor":
		if family == "armor" and catalog.get("armor", {}).has(type_id) and int(catalog.armor[type_id].size) <= tier:
			return {"ok": true, "reason": ""}
		return {"ok": false, "reason": "That armor is too large for this hull."}
	return {"ok": false, "reason": "That part does not fit this socket."}

static func spare_choices(boat: Dictionary, base: Dictionary, slot: String, module_id: String, draft_slots: Dictionary = {}, preview_quote: Dictionary = {}) -> Array:
	if module_id.is_empty() or not is_canonical(boat) or base.is_empty():
		return []
	var locker_res: Dictionary = Core.list_locker(boat.moduleCondition)
	if not locker_res.get("ok", false):
		return []
	var family: String = slot_family(slot)
	var catalog: Dictionary = Refits.catalog()
	var assigned_by_uid: Dictionary = {}
	for other_slot in draft_slots.keys():
		var ask = draft_slots[other_slot]
		if ask is Dictionary and ask.has("itemUid"):
			assigned_by_uid[str(ask.itemUid)] = str(other_slot)
	for change in preview_quote.get("changes", []):
		if change is Dictionary:
			var ch_slot: String = str(change.get("slot", ""))
			var sel = change.get("selection", {})
			if not ch_slot.is_empty() and sel is Dictionary and not bool(sel.get("newUnit", false)):
				var sel_uid: String = str(sel.get("itemUid", ""))
				if not sel_uid.is_empty() and not assigned_by_uid.has(sel_uid):
					assigned_by_uid[sel_uid] = ch_slot
	var rows: Array = []
	for item in locker_res.get("items", []):
		if str(item.get("family", "")) != family or str(item.get("typeId", "")) != module_id:
			continue
		var uid: String = str(item.get("itemUid", ""))
		var fit_check: Dictionary = _fits_socket(catalog, base, item, slot)
		var assigned_to: String = str(assigned_by_uid.get(uid, ""))
		var taken_elsewhere: bool = not assigned_to.is_empty() and assigned_to != slot
		var compatible: bool = bool(fit_check.get("ok", false)) and not taken_elsewhere
		var reason: String = str(fit_check.get("reason", ""))
		if taken_elsewhere:
			reason = "Already assigned to %s in this draft." % slot_title(assigned_to)
		rows.append({
			"itemUid": uid,
			"typeId": module_id,
			"family": family,
			"hp": float(item.get("hp", 1.0)),
			"status": str(item.get("status", "ok")),
			"cause": str(item.get("cause", "")),
			"originHullType": str(item.get("originHullType", "")),
			"lockerOrder": int(item.get("lockerOrder", 0)),
			"assignedSlot": assigned_to,
			"compatible": compatible,
			"reason": reason
		})
	return rows

static func normalize_slot_request(slot: String, request: Dictionary, module_id: String = "__keep__") -> Dictionary:
	if not request is Dictionary or request.is_empty():
		return {}
	if module_id == "":
		return {}
	var ask: Dictionary = request
	if request.get("slots") is Dictionary:
		ask = request.slots.get(slot, {}) if request.slots.get(slot) is Dictionary else {}
	if ask.get("new") is bool and bool(ask.new):
		return {"new": true}
	if ask.has("itemUid") and Core._uid(ask.get("itemUid")):
		return {"itemUid": str(ask.itemUid)}
	return {}

static func _ensure_request_map(ui) -> Dictionary:
	if ui == null:
		return {}
	if not ("workshop_requests" in ui) or not (ui.workshop_requests is Dictionary):
		return {}
	return ui.workshop_requests

static func clear_all(ui) -> void:
	if ui == null:
		return
	if "workshop_drafts" in ui and ui.workshop_drafts is Dictionary:
		ui.workshop_drafts.clear()
	if "workshop_requests" in ui and ui.workshop_requests is Dictionary:
		ui.workshop_requests.clear()

static func clear_workshop_state(ui, uid: String) -> void:
	if ui == null:
		return
	if "workshop_drafts" in ui and ui.workshop_drafts is Dictionary:
		ui.workshop_drafts.erase(uid)
	if "workshop_requests" in ui and ui.workshop_requests is Dictionary:
		ui.workshop_requests.erase(uid)

static func prune_ui_state(ui) -> Dictionary:
	return prune_requests(ui)

static func prune_requests(ui, keep_uid: String = "") -> Dictionary:
	if ui == null or ui.get("host") == null or ui.host.get("core") == null:
		clear_all(ui)
		return {}
	var state = ui.host.core.get("state")
	if not (state is Dictionary) or not (state.get("fleet") is Array):
		clear_all(ui)
		return {}
	var living: Dictionary = {}
	for boat in state.fleet:
		if boat is Dictionary and not boat.get("sunk", false):
			var b_uid: String = str(boat.get("uid", ""))
			if not b_uid.is_empty():
				living[b_uid] = boat
	if "workshop_drafts" in ui and ui.workshop_drafts is Dictionary:
		for uid in ui.workshop_drafts.keys():
			if not living.has(str(uid)):
				ui.workshop_drafts.erase(uid)
	var req_map: Dictionary = _ensure_request_map(ui)
	var state_seed: int = int(state.get("seed", 0))
	for uid in req_map.keys():
		var uid_str: String = str(uid)
		if not living.has(uid_str):
			req_map.erase(uid)
			continue
		var live_boat: Dictionary = living[uid_str]
		var entry = req_map[uid]
		var birth_now: String = str(live_boat.moduleCondition.get("birthNamespace", "")) if live_boat.get("moduleCondition") is Dictionary else ""
		if not (entry is Dictionary) or not is_same(entry.get("boatRef"), live_boat) or int(entry.get("seed", -1)) != state_seed or str(entry.get("birth", "")) != birth_now:
			req_map.erase(uid)
			if "workshop_drafts" in ui and ui.workshop_drafts is Dictionary:
				ui.workshop_drafts.erase(uid_str)
			continue
		if "workshop_drafts" in ui and ui.workshop_drafts is Dictionary and not ui.workshop_drafts.has(uid_str):
			req_map.erase(uid)
			continue
		if not is_canonical(live_boat):
			entry["slots"] = {}
			continue
		var draft: Dictionary = ui.workshop_drafts.get(uid_str, {}) if ("workshop_drafts" in ui and ui.workshop_drafts is Dictionary) else {}
		var base: Dictionary = ui.host.core.hull(str(live_boat.get("type", "")))
		var weapon_count: int = Refits.hardpoints(base).size() if not base.is_empty() else 0
		var raw_slots = entry.get("slots", {})
		if not (raw_slots is Dictionary):
			entry["slots"] = {}
			continue
		var clean_slots: Dictionary = {}
		var used_uids: Dictionary = {}
		var slot_names: Array = []
		for i in range(weapon_count):
			slot_names.append("weapon:%d" % i)
		slot_names.append("engine")
		slot_names.append("armor")
		for slot in slot_names:
			if not raw_slots.has(slot):
				continue
			var drafted_mod: String = _module_at_loadout(draft, slot) if not draft.is_empty() else ""
			if drafted_mod.is_empty():
				continue
			var ask: Dictionary = normalize_slot_request(slot, raw_slots[slot] if raw_slots[slot] is Dictionary else {}, drafted_mod)
			if ask.is_empty():
				continue
			if ask.has("itemUid"):
				var item_uid: String = str(ask.itemUid)
				if used_uids.has(item_uid):
					continue
				var item: Dictionary = item_by_uid(live_boat, item_uid)
				if item.is_empty() or str(item.get("location", "")) != "locker":
					continue
				if str(item.get("typeId", "")) != drafted_mod or str(item.get("family", "")) != slot_family(slot):
					continue
				if not _fits_socket(Refits.catalog(), base, item, slot).get("ok", false):
					continue
				used_uids[item_uid] = slot
				clean_slots[slot] = {"itemUid": item_uid}
			elif ask.get("new") == true:
				clean_slots[slot] = {"new": true}
		entry["slots"] = clean_slots
	if "workshop_drafts" in ui and ui.workshop_drafts is Dictionary:
		for uid in ui.workshop_drafts.keys():
			if ui.workshop_drafts.size() <= MAX_ROSTER_REQUESTS:
				break
			var uid_str: String = str(uid)
			if uid_str == keep_uid:
				continue
			ui.workshop_drafts.erase(uid)
			req_map.erase(uid_str)
	for uid in req_map.keys():
		if req_map.size() <= MAX_ROSTER_REQUESTS:
			break
		var uid_str: String = str(uid)
		if uid_str == keep_uid:
			continue
		req_map.erase(uid)
	return living

static func bind_boat(ui, uid: String) -> void:
	var living: Dictionary = prune_requests(ui, uid)
	if not living.has(uid):
		return
	var req_map: Dictionary = _ensure_request_map(ui)
	var live_boat: Dictionary = living[uid]
	var state_seed: int = int(ui.host.core.state.get("seed", 0))
	var birth_now: String = str(live_boat.moduleCondition.get("birthNamespace", "")) if live_boat.get("moduleCondition") is Dictionary else ""
	if not req_map.has(uid) or not (req_map[uid] is Dictionary) or not is_same(req_map[uid].get("boatRef"), live_boat):
		req_map[uid] = {
			"seed": state_seed,
			"birth": birth_now,
			"boatRef": live_boat,
			"slots": {}
		}
	elif not is_canonical(live_boat):
		req_map[uid]["slots"] = {}

static func workshop_slot_map(ui, uid: String, draft: Dictionary = {}) -> Dictionary:
	var living: Dictionary = prune_requests(ui)
	if not living.has(uid):
		return {}
	var req_map: Dictionary = _ensure_request_map(ui)
	if not req_map.has(uid) or not (req_map[uid] is Dictionary):
		return {}
	var slots: Dictionary = req_map[uid].get("slots", {})
	if not (slots is Dictionary) or slots.is_empty():
		return {}
	if draft.is_empty():
		return slots.duplicate(true)
	var filtered: Dictionary = {}
	for slot in slots.keys():
		var mod_id: String = _module_at_loadout(draft, str(slot))
		if mod_id.is_empty():
			continue
		var ask: Dictionary = normalize_slot_request(str(slot), slots[slot], mod_id)
		if not ask.is_empty():
			filtered[str(slot)] = ask
	return filtered

static func workshop_request(ui, uid: String, draft: Dictionary = {}) -> Dictionary:
	var slots: Dictionary = workshop_slot_map(ui, uid, draft)
	if slots.is_empty():
		return {}
	return {"slots": slots}

static func set_workshop_slot_choice(ui, uid: String, slot: String, module_id: String, choice: Dictionary = {}) -> void:
	bind_boat(ui, uid)
	var req_map: Dictionary = _ensure_request_map(ui)
	if not req_map.has(uid) or not (req_map[uid] is Dictionary):
		return
	var slots: Dictionary = req_map[uid].get("slots", {}).duplicate(true)
	var ask: Dictionary = normalize_slot_request(slot, choice, module_id)
	if ask.is_empty() or module_id.is_empty():
		slots.erase(slot)
	else:
		if ask.has("itemUid"):
			var chosen_uid: String = str(ask.itemUid)
			for other_slot in slots.keys():
				if str(other_slot) != slot and slots[other_slot] is Dictionary and str(slots[other_slot].get("itemUid", "")) == chosen_uid:
					slots.erase(other_slot)
		slots[slot] = ask
	req_map[uid]["slots"] = slots

static func slot_summary_text(ui, boat: Dictionary, draft: Dictionary, slot: String, quote: Dictionary = {}) -> String:
	if not is_canonical(boat):
		return ""
	var show_uid: bool = dev_enabled(ui)
	for change in quote.get("changes", []):
		if change is Dictionary and str(change.get("slot", "")) == slot:
			var sel: Dictionary = change.get("selection", {}) if change.get("selection") is Dictionary else {}
			var src: String = str(change.get("source", ""))
			if src == "removal":
				var old_item: Dictionary = installed_at(boat, slot)
				if not old_item.is_empty():
					return "Draft removal → locker (%s)" % describe_part(old_item, show_uid)
				return "Draft removal → locker"
			if bool(sel.get("newUnit", false)) or src == "yard":
				return "Draft: Buy new from yard (Operational · 100% condition)"
			if not str(sel.get("itemUid", "")).is_empty():
				var prefix: String = "Draft spare from locker" if src == "locker" else "Draft moved fitting"
				return "%s (%s)" % [prefix, describe_part(sel, show_uid)]
	var current_item: Dictionary = installed_at(boat, slot)
	if not current_item.is_empty():
		return "Installed: %s" % describe_part(current_item, show_uid)
	return "Empty mount"

static func change_selection_note(ui, change: Dictionary) -> String:
	if not (change is Dictionary):
		return ""
	var sel: Dictionary = change.get("selection", {}) if change.get("selection") is Dictionary else {}
	if sel.is_empty():
		return ""
	var show_uid: bool = dev_enabled(ui)
	var src: String = str(change.get("source", ""))
	if src == "removal":
		return "Removed part returns to this boat's locker with its existing condition."
	if bool(sel.get("newUnit", false)):
		var text: String = "Selected part: New yard unit · Operational · 100% condition"
		if show_uid and not str(sel.get("previewUid", "")).is_empty():
			text += " · " + str(sel.previewUid)
		return text
	if not str(sel.get("itemUid", "")).is_empty():
		var note: String = "Selected part: %s" % describe_part(sel, show_uid)
		if float(sel.get("hp", 1.0)) < Core.OK_HP or str(sel.get("status", "ok")) != "ok":
			note += " (damaged spare stays at %s condition after installation until harbor repair)" % percent_text(float(sel.get("hp", 1.0)))
		return note
	return ""

static func _script_method_arg_count(script_ref, method_name: String) -> int:
	if script_ref == null or not script_ref.has_method("get_script_method_list"):
		return 0
	var best: int = 0
	for entry in script_ref.get_script_method_list():
		if entry is Dictionary and str(entry.get("name", "")) == method_name:
			var args = entry.get("args", [])
			if args is Array:
				best = maxi(best, args.size())
	return best

static func _object_method_arg_count(target, method_name: String) -> int:
	if target == null:
		return 0
	var best: int = 0
	if target.has_method("get_script"):
		var scr = target.get_script()
		if scr != null:
			best = maxi(best, _script_method_arg_count(scr, method_name))
	if target.has_method("get_method_list"):
		for entry in target.get_method_list():
			if entry is Dictionary and str(entry.get("name", "")) == method_name:
				var args = entry.get("args", [])
				if args is Array:
					best = maxi(best, args.size())
	return best

static func _refit_boat_uses_workshop_slots(core) -> bool:
	if core == null:
		return false
	if core.has_method("get_script"):
		var scr = core.get_script()
		if scr != null and typeof(scr.get("source_code")) == TYPE_STRING:
			var src: String = str(scr.source_code)
			if not src.is_empty():
				if src.contains("Refits.install") or src.contains("Refit.install"):
					return false
				if src.contains("workshop_apply"):
					return true
	return core.has_method("workshop_apply")

static func quote_single(port: Dictionary, ship: Dictionary, slot: String, module_id: String, request: Dictionary = {}) -> Dictionary:
	var slot_req: Dictionary = normalize_slot_request(slot, request, module_id)
	if not is_canonical(ship):
		slot_req = {}
	if _script_method_arg_count(Refits, "quote") >= 5:
		return Refits.quote(port, ship, slot, module_id, slot_req)
	return Refits.quote(port, ship, slot, module_id)

static func preview_workshop(ui, uid: String, draft: Dictionary, explicit_request = null) -> Dictionary:
	var req: Dictionary = explicit_request.duplicate(true) if explicit_request is Dictionary else workshop_request(ui, uid, draft)
	if ui != null and ui.get("host") != null:
		if _object_method_arg_count(ui.host, "workshop_preview") >= 3:
			return ui.host.workshop_preview(uid, draft, req)
		if ui.host.get("core") != null and _object_method_arg_count(ui.host.core, "workshop_preview") >= 3:
			return ui.host.core.workshop_preview(uid, draft, req)
	if _script_method_arg_count(Workshop, "preview") >= 4:
		return Workshop.preview(ui.host.core, uid, draft, req)
	return Workshop.preview(ui.host.core, uid, draft)

static func apply_single_refit(ui, uid: String, slot: String, module_id: String, request: Dictionary = {}):
	if ui == null or ui.get("host") == null or ui.host.get("core") == null:
		return {"ok": false, "message": "The fitting bay is not ready."}
	if ui.host.has_method("sync_economy"):
		ui.host.sync_economy()
	var ship: Dictionary = ui.host.core.find_boat(uid)
	if ship.is_empty() or ship.get("sunk", false):
		ui.toast("Choose a living boat in your flotilla.", true)
		return {"ok": false, "message": "Choose a living boat in your flotilla."}
	var slot_req: Dictionary = normalize_slot_request(slot, request, module_id)
	if not is_canonical(ship):
		slot_req = {}
	var whole_req: Dictionary = {"slots": {slot: slot_req}} if not slot_req.is_empty() else {}
	if _object_method_arg_count(ui.host, "refit_boat") >= 4:
		var pass_req: Dictionary = whole_req if _refit_boat_uses_workshop_slots(ui.host.core) else slot_req
		var res = ui.host.refit_boat(uid, slot, module_id, pass_req)
		if not ("workshop_drafts" in ui and ui.workshop_drafts.has(uid)):
			clear_workshop_state(ui, uid)
		return res
	if not slot_req.is_empty() and _script_method_arg_count(Workshop, "apply") >= 5:
		var base: Dictionary = ui.host.core.hull(str(ship.get("type", "")))
		var fit: Dictionary = Refits.normalize(base, ship.get("loadout", {}))
		if not fit.ok:
			if ui.host.has_method("respond"):
				ui.host.respond(fit)
			return fit
		var position: Dictionary = Refits._slot(fit.loadout, slot)
		if not position.ok:
			if ui.host.has_method("respond"):
				ui.host.respond(position)
			return position
		var next: Dictionary = fit.loadout.duplicate(true)
		if position.index >= 0:
			next.weapons[position.index] = module_id
		else:
			next[position.key] = module_id
		return apply_workshop(ui, uid, next, {}, whole_req)
	var fallback_res = ui.host.refit_boat(uid, slot, module_id)
	if not ("workshop_drafts" in ui and ui.workshop_drafts.has(uid)):
		clear_workshop_state(ui, uid)
	return fallback_res

static func apply_workshop(ui, uid: String, draft: Dictionary, expected_quote: Dictionary = {}, explicit_request = null):
	if ui == null or ui.get("host") == null or ui.host.get("core") == null:
		return {"ok": false, "message": "The fitting bay is not ready."}
	if ui.host.has_method("sync_economy"):
		ui.host.sync_economy()
	var ship: Dictionary = ui.host.core.find_boat(uid)
	if ship.is_empty() or ship.get("sunk", false):
		ui.toast("Choose a living boat in your flotilla.", true)
		return {"ok": false, "message": "Choose a living boat in your flotilla."}
	var req: Dictionary = explicit_request.duplicate(true) if explicit_request is Dictionary else workshop_request(ui, uid, draft)
	if _object_method_arg_count(ui.host, "workshop_apply") >= 4:
		var res = ui.host.workshop_apply(uid, draft, expected_quote, req)
		if not ("workshop_drafts" in ui and ui.workshop_drafts.has(uid)):
			clear_workshop_state(ui, uid)
		return res
	if req.is_empty() and ui.host.has_method("workshop_apply"):
		var plain_res = ui.host.workshop_apply(uid, draft, expected_quote)
		if not ("workshop_drafts" in ui and ui.workshop_drafts.has(uid)):
			clear_workshop_state(ui, uid)
		return plain_res
	if _object_method_arg_count(ui.host.core, "workshop_apply") >= 4:
		var core_res: Dictionary = ui.host.core.workshop_apply(uid, draft, expected_quote, req)
		if ui.host.has_method("respond"):
			ui.host.respond(core_res)
		if core_res.get("ok", false):
			clear_workshop_state(ui, uid)
			if core_res.get("changed", false) and ui.host.has_method("save_game"):
				ui.host.save_game(false)
		if ui.has_method("open_refit"):
			ui.open_refit(uid)
		return core_res
	if _script_method_arg_count(Workshop, "apply") >= 5:
		var result: Dictionary = Workshop.apply(ui.host.core, uid, draft, expected_quote, req)
		if result.get("ok", false) and result.get("changed", false) and ui.host.core.has_method("log_entry"):
			ui.host.core.log_entry(str(result.message))
		if ui.host.has_method("respond"):
			ui.host.respond(result)
		if result.get("ok", false):
			clear_workshop_state(ui, uid)
			if result.get("changed", false) and ui.host.has_method("save_game"):
				ui.host.save_game(false)
		if ui.has_method("open_refit"):
			ui.open_refit(uid)
		return result
	var fallback_res = ui.host.workshop_apply(uid, draft, expected_quote)
	if not ("workshop_drafts" in ui and ui.workshop_drafts.has(uid)):
		clear_workshop_state(ui, uid)
	return fallback_res
