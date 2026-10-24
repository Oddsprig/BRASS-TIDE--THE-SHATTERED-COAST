extends RefCounted
## Physical custody for one Refit slot and one FleetWorkshop bill.
## Count lockers stay on boats with no moduleCondition. This module does not
## preload Refit, Campaign, Harbor, or Money, and it never treats a caller flag
## as proof of payment. Spare hold weight is not applied here.
const Core = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "message": message}

static func _forward(result: Dictionary) -> Dictionary:
	if result.get("ok", false) == true:
		return result
	var message: String = str(result.get("message", result.get("error", "The fitting could not be completed.")))
	return _fail(message)

static func _legacy_opaque(ship: Dictionary) -> bool:
	for key in ship.keys():
		if str(key) == "moduleCondition":
			continue
		var text: String = str(key).to_lower()
		var noun: bool = text.contains("module") or text.contains("fitting") or text.contains("equipment") or text.contains("weapon") or text.contains("engine") or text.contains("armor") or text.contains("pump")
		var state: bool = text.contains("condition") or text.contains("state")
		if noun and state:
			return true
	var spec = ship.get("spec", {})
	if spec is Dictionary and spec.get("weaponMounts", []) is Array:
		for mount in spec.get("weaponMounts", []):
			if not mount is Dictionary:
				continue
			for key in mount.keys():
				var field: String = str(key).to_lower()
				if field.contains("condition") or field.contains("state") or field in ["disabled", "serial", "health", "hp"]:
					return true
	return false

## legacy: no schema. physical: one valid moduleCondition.
## corrupt: present but not a known condition record. foreign: any other condition-shaped field.
static func classify(ship: Dictionary) -> String:
	if not ship is Dictionary:
		return "corrupt"
	if _legacy_opaque(ship):
		return "foreign"
	if not ship.has("moduleCondition"):
		return "legacy"
	if not ship.moduleCondition is Dictionary:
		return "corrupt"
	if not Core._records(ship.moduleCondition).ok:
		return "corrupt"
	return "physical"

static func fingerprint(ship: Dictionary) -> Dictionary:
	var kind: String = classify(ship)
	if kind != "physical":
		return {"mode": kind}
	var condition: Dictionary = ship.moduleCondition
	var rows: Array = []
	for key in condition.items.keys():
		var item: Dictionary = condition.items[key]
		rows.append([item.itemUid, item.typeId, item.originHullType, item.location, item.lockerOrder, item.hp, item.status, item.cause])
	rows.sort_custom(func(a, b): return str(a[0]) < str(b[0]))
	var printed: Dictionary = {"mode": "physical", "birth": condition.birthNamespace, "serial": condition.nextItemSeq, "priority": condition.repairPriority, "version": condition.version, "items": rows}
	if condition.has("legacyEngineSynced"):
		printed.watermark = condition.legacyEngineSynced
	return printed

## Publish locker counts from the items. Copy the raw engine hp downward onto
## the scalar. A lower scalar stays put so ensure does not erase damage that
## the next paid fit still has to absorb. Items are not created or rewritten.
static func write_projection(ship: Dictionary) -> void:
	if classify(ship) != "physical":
		return
	var projected: Dictionary = Core.project(ship.moduleCondition)
	if not projected.ok:
		return
	ship.refitLocker = projected.refitLocker.duplicate(true)
	if not projected.hasEngine:
		return
	var canonical: float = float(projected.engineHp)
	var scalar = ship.get("engine", null)
	if (scalar is int or scalar is float) and is_finite(float(scalar)) and float(scalar) < canonical - 0.0001:
		return
	ship.engine = canonical

static func matches(ship: Dictionary, hull_type: String, mount_count: int, loadout: Dictionary) -> bool:
	if classify(ship) != "physical":
		return false
	var ctx: Dictionary = {"mountCount": mount_count, "hullType": hull_type, "knownUids": [], "loadout": loadout}
	return Core.validate(ship.moduleCondition, ctx).ok

static func _bool_error(value, label: String) -> String:
	if value is bool:
		return ""
	return label

## True only for a real bool. Numeric 0/1 and other truthy values are not flags.
static func wants_initialize(request: Dictionary) -> bool:
	return request.has("initialize") and request.initialize is bool and request.initialize

static func wants_new(ask: Dictionary) -> bool:
	return ask.has("new") and ask.new is bool and ask.new

static func request_error(request: Dictionary, whole: bool) -> String:
	if not request is Dictionary:
		return "Fitting request is malformed."
	var allowed: Array = ["initialize", "knownUids", "slots"] if whole else ["initialize", "knownUids", "itemUid", "new"]
	for key in request.keys():
		if not (key in allowed):
			return "Fitting request has an unknown field."
	if request.has("initialize"):
		var init_flag: String = _bool_error(request.initialize, "Fitting initialization flag is malformed.")
		if not init_flag.is_empty():
			return init_flag
	if request.has("new"):
		var new_flag: String = _bool_error(request.new, "Fitting replacement flag is malformed.")
		if not new_flag.is_empty():
			return new_flag
	if request.has("itemUid") and not Core._uid(request.itemUid):
		return "Fitting request item id is malformed."
	if request.has("itemUid") and wants_new(request):
		return "Choose either an existing part or a newly built part."
	if request.has("knownUids"):
		var known: Dictionary = Core._known_set(request.knownUids)
		if not known.ok:
			return str(known.error)
	if not whole:
		return ""
	if not request.has("slots"):
		return ""
	if not request.slots is Dictionary:
		return "Slot requests are malformed."
	for slot in request.slots.keys():
		if not slot is String:
			return "Slot requests are malformed."
		var ask = request.slots[slot]
		if not ask is Dictionary:
			return "Slot requests are malformed."
		for key in ask.keys():
			if key not in ["itemUid", "new"]:
				return "Slot request has an unknown field."
		if ask.has("itemUid") and not Core._uid(ask.itemUid):
			return "Fitting request item id is malformed."
		if ask.has("new"):
			var slot_flag: String = _bool_error(ask.new, "Fitting replacement flag is malformed.")
			if not slot_flag.is_empty():
				return slot_flag
		if ask.has("itemUid") and wants_new(ask):
			return "Choose either an existing part or a newly built part."
	return ""

## Canonical names only: engine, armor, and weapon:<index> for this hull's mounts.
static func _socket_name(slot: String, weapon_count: int) -> bool:
	if slot == "engine" or slot == "armor":
		return true
	var prefix: String = "weapon:"
	if not slot.begins_with(prefix):
		return false
	var suffix: String = slot.substr(prefix.length())
	if suffix.is_empty() or not suffix.is_valid_int() or str(int(suffix)) != suffix:
		return false
	var index: int = int(suffix)
	return index >= 0 and index < weapon_count

static func socket_error(request: Dictionary, weapon_count: int) -> String:
	if not request.has("slots"):
		return ""
	if not request.slots is Dictionary:
		return "Slot requests are malformed."
	for slot in request.slots.keys():
		if not slot is String or not _socket_name(str(slot), weapon_count):
			return "That socket is not on this hull."
	return ""

static func asks_exact(request: Dictionary) -> bool:
	if request.has("itemUid") or wants_new(request):
		return true
	var slots = request.get("slots", {})
	return slots is Dictionary and not slots.is_empty()

static func _location(slot: String) -> String:
	if slot == "engine" or slot == "armor":
		return slot
	return "mount" + slot.split(":")[1]

static func _group(slot: String) -> String:
	if slot == "engine":
		return "engines"
	if slot == "armor":
		return "armor"
	return "weapons"

static func _module_at(loadout: Dictionary, slot: String) -> String:
	if slot == "engine" or slot == "armor":
		return str(loadout[slot])
	return str(loadout.weapons[int(slot.split(":")[1])])

static func _ask_for(request: Dictionary, slot: String, whole: bool) -> Dictionary:
	if whole:
		var slots = request.get("slots", {})
		if slots is Dictionary and slots.has(slot) and slots[slot] is Dictionary:
			return slots[slot]
		return {}
	var ask: Dictionary = {}
	if request.has("itemUid"):
		ask.itemUid = request.itemUid
	if request.has("new"):
		ask.new = request.new
	return ask

static func _origin_block(item: Dictionary, hull_type: String) -> String:
	if str(item.family) == "pumps":
		return "Integral pumps stay in their bay."
	if str(item.typeId) in Core.STOCK_TYPES and str(item.originHullType) != hull_type:
		return "A factory part cannot be installed on a different hull design."
	return ""

static func _fits(catalog: Dictionary, item: Dictionary, location: String, sockets: Array, tier: int) -> bool:
	var type_id: String = str(item.typeId)
	var family: String = str(item.family)
	if location.begins_with("mount"):
		if family != "weapons" or not catalog.weapons.has(type_id):
			return false
		var index: int = int(location.substr(5, 1))
		if index >= sockets.size():
			return false
		if type_id == "stock_primary" and index != 0:
			return false
		return int(catalog.weapons[type_id].size) <= int(sockets[index].size)
	if location == "engine":
		return family == "engines" and catalog.engines.has(type_id) and int(catalog.engines[type_id].size) <= tier
	if location == "armor":
		return family == "armor" and catalog.armor.has(type_id) and int(catalog.armor[type_id].size) <= tier
	return false

static func _candidate_sort(a: Dictionary, b: Dictionary) -> bool:
	if int(a.lockerOrder) == int(b.lockerOrder):
		return str(a.itemUid) < str(b.itemUid)
	return int(a.lockerOrder) < int(b.lockerOrder)

static func _known_array(request: Dictionary) -> Array:
	var known = request.get("knownUids", [])
	return known.duplicate(true) if known is Array else []

static func plan_slot(ship: Dictionary, base: Dictionary, old_loadout: Dictionary, new_loadout: Dictionary, slot: String, module_id: String, old_type: String, request: Dictionary, sockets: Array, tier: int, catalog: Dictionary) -> Dictionary:
	var shape: String = request_error(request, false)
	if not shape.is_empty():
		return _fail(shape)
	if module_id.is_empty() and (request.has("itemUid") or wants_new(request)):
		return _fail("A removal does not select a replacement part.")
	var change: Dictionary = {"slot": slot, "location": _location(slot), "module_id": module_id, "group": _group(slot), "old_type": old_type, "ask": _ask_for(request, slot, false)}
	return _assign(ship, [change], request, false, base, old_loadout, new_loadout, sockets, tier, catalog)

static func plan_whole(ship: Dictionary, base: Dictionary, old_loadout: Dictionary, new_loadout: Dictionary, request: Dictionary, sockets: Array, tier: int, catalog: Dictionary) -> Dictionary:
	var shape: String = request_error(request, true)
	if not shape.is_empty():
		return _fail(shape)
	var named: String = socket_error(request, old_loadout.weapons.size())
	if not named.is_empty():
		return _fail(named)
	var slots: Array = []
	for i in range(old_loadout.weapons.size()):
		slots.append("weapon:%d" % i)
	slots.append("engine")
	slots.append("armor")
	var changes: Array = []
	for slot in slots:
		var old_id: String = _module_at(old_loadout, slot)
		var new_id: String = _module_at(new_loadout, slot)
		var ask: Dictionary = _ask_for(request, slot, true)
		var explicit: bool = ask.has("itemUid") or wants_new(ask)
		if old_id == new_id and not explicit:
			continue
		if new_id.is_empty() and explicit:
			return _fail("A removal does not select a replacement part.")
		changes.append({"slot": slot, "location": _location(slot), "module_id": new_id, "group": _group(slot), "old_type": old_id, "ask": ask})
	if changes.is_empty():
		var untouched: Dictionary = {}
		if classify(ship) == "physical":
			var projected: Dictionary = Core.project(ship.moduleCondition)
			if projected.ok:
				untouched = projected.refitLocker.duplicate(true)
		return {"ok": true, "changes": [], "lockerAfter": untouched, "plan": {}}
	return _assign(ship, changes, request, true, base, old_loadout, new_loadout, sockets, tier, catalog)

static func _assign(ship: Dictionary, changes: Array, request: Dictionary, whole: bool, base: Dictionary, old_loadout: Dictionary, new_loadout: Dictionary, sockets: Array, tier: int, catalog: Dictionary) -> Dictionary:
	var hull_type: String = str(base.get("id", ""))
	var mount_count: int = sockets.size()
	var known: Array = _known_array(request)
	var working: Dictionary = ship.duplicate(true)
	var must_initialize: bool = not working.has("moduleCondition")
	if must_initialize:
		if not wants_initialize(request):
			return _fail("This boat has no physical equipment record.")
		var seeded: Dictionary = Records.initialize(working, {"base": base, "loadout": old_loadout, "catalog": catalog, "identity": str(ship.get("uid", "")), "knownUids": known})
		if not seeded.ok:
			return _forward(seeded)
	elif wants_initialize(request):
		# Already physical. initialize is idempotent and must not reseed.
		must_initialize = false
	var current: Dictionary = Core.validate(working.moduleCondition, {"mountCount": mount_count, "hullType": hull_type, "knownUids": known, "loadout": old_loadout})
	if not current.ok:
		return _forward(current)
	var scratch: Dictionary = {"moduleCondition": working.moduleCondition.duplicate(true), "engine": working.get("engine", 1.0)}
	var absorbed: Dictionary = Records.absorb_legacy_damage(scratch)
	if not absorbed.ok:
		return _forward(absorbed)
	var condition: Dictionary = scratch.moduleCondition
	var changing: Dictionary = {}
	for change in changes:
		changing[str(change.location)] = true
	var assigned: Dictionary = {}
	var taken: Dictionary = {}
	for key in condition.items.keys():
		var item: Dictionary = condition.items[key]
		var place: String = str(item.location)
		if place != "locker" and not changing.has(place):
			assigned[str(key)] = place
			taken[place] = str(key)
	var staged: Array = []
	for change in changes:
		var ask: Dictionary = change.ask
		var location: String = str(change.location)
		var module_id: String = str(change.module_id)
		var row: Dictionary = {"slot": change.slot, "group": change.group, "oldModule": change.old_type, "moduleId": module_id, "owned": false, "source": "yard", "selection": {}}
		if module_id.is_empty():
			row.source = "removal"
			row.selection = {"newUnit": false, "itemUid": "", "hp": 0.0, "status": "", "cause": "", "originHullType": "", "typeId": ""}
			staged.append(row)
			continue
		if wants_new(ask):
			row.owned = false
			row.source = "yard"
			row.selection = {"newUnit": true, "itemUid": "", "previewUid": "", "hp": 1.0, "status": "ok", "cause": "", "originHullType": hull_type, "typeId": module_id, "location": location}
			staged.append(row)
			continue
		var chosen: Dictionary = {}
		if ask.has("itemUid"):
			var uid: String = str(ask.itemUid)
			if not condition.items.has(uid):
				return _fail("That exact part is not on this hull.")
			chosen = condition.items[uid]
			if str(chosen.typeId) != module_id or str(chosen.family) != _family_for(location):
				return _fail("That spare is a different part.")
			if not _fits(catalog, chosen, location, sockets, tier):
				return _fail("That part does not fit this socket.")
			var blocked: String = _origin_block(chosen, hull_type)
			if not blocked.is_empty():
				return _fail(blocked)
			if assigned.has(uid) and str(assigned[uid]) != location:
				return _fail("That part is already filling another socket.")
			if str(chosen.location) != "locker" and not changing.has(str(chosen.location)) and str(chosen.location) != location:
				return _fail("That part is installed in another socket.")
		else:
			var pool: Array = []
			var blocked_reason: String = ""
			for key in condition.items.keys():
				var item: Dictionary = condition.items[key]
				if assigned.has(str(key)) and str(assigned[str(key)]) != "locker":
					continue
				if str(item.family) == "pumps" or str(item.typeId) != module_id:
					continue
				if str(item.location) != "locker" and not changing.has(str(item.location)):
					continue
				var unfit: bool = not _fits(catalog, item, location, sockets, tier)
				var origin: String = _origin_block(item, hull_type)
				if unfit or not origin.is_empty():
					if blocked_reason.is_empty():
						blocked_reason = origin if not origin.is_empty() else "That part does not fit this socket."
					continue
				pool.append(item)
			pool.sort_custom(func(a, b): return _candidate_sort(a, b))
			if pool.is_empty() and not blocked_reason.is_empty():
				return _fail(blocked_reason)
			if not pool.is_empty():
				chosen = pool[0]
		if chosen.is_empty():
			row.owned = false
			row.source = "yard"
			row.selection = {"newUnit": true, "itemUid": "", "previewUid": "", "hp": 1.0, "status": "ok", "cause": "", "originHullType": hull_type, "typeId": module_id, "location": location}
			staged.append(row)
			continue
		var chosen_uid: String = str(chosen.itemUid)
		if taken.has(location) and str(taken[location]) != chosen_uid:
			return _fail("That socket was already given a part.")
		assigned[chosen_uid] = location
		taken[location] = chosen_uid
		row.owned = true
		row.source = "locker" if str(chosen.location) == "locker" else "moved"
		row.selection = {"newUnit": false, "itemUid": chosen_uid, "hp": chosen.hp, "status": str(chosen.status), "cause": str(chosen.cause), "originHullType": str(chosen.originHullType), "typeId": str(chosen.typeId), "location": location}
		staged.append(row)
	var goals: Dictionary = {}
	for key in condition.items.keys():
		var item: Dictionary = condition.items[key]
		if str(item.family) == "pumps":
			continue
		goals[str(key)] = str(assigned[str(key)]) if assigned.has(str(key)) else "locker"
	var locker_count: int = 0
	var counts: Dictionary = {}
	for uid in goals.keys():
		if str(goals[uid]) != "locker":
			continue
		locker_count += 1
		var type_id: String = str(condition.items[uid].typeId)
		counts[type_id] = int(counts.get(type_id, 0)) + 1
	var acquires: Array = []
	for row in staged:
		if row.selection.get("newUnit", false) == true:
			acquires.append({"family": _family_for(str(row.selection.location)), "typeId": str(row.selection.typeId), "location": str(row.selection.location), "originHullType": hull_type})
	if locker_count > Core.MAX_LOCKER:
		return _fail("The locker exceeds the existing 256-part bound.")
	if condition.items.size() + acquires.size() > Core.MAX_ITEMS:
		return _fail("Equipment record exceeds the existing part bound.")
	var serial: int = int(condition.nextItemSeq)
	var birth: String = str(condition.birthNamespace)
	var preview_index: int = 0
	for row in staged:
		if row.selection.get("newUnit", false) != true:
			continue
		row.selection.previewUid = Core.mint_uid(birth, serial + preview_index)
		preview_index += 1
	for location in taken.keys():
		var uid: String = str(taken[location])
		if goals.has(uid) and str(goals[uid]) != str(location):
			return _fail("One physical part was assigned to two sockets.")
	var seen: Dictionary = {}
	for uid in goals.keys():
		var place: String = str(goals[uid])
		if place == "locker":
			continue
		if seen.has(place):
			return _fail("One socket was assigned two physical parts.")
		seen[place] = uid
	return {
		"ok": true,
		"changes": staged,
		"lockerAfter": counts,
		"plan": {
			"initialize": must_initialize,
			"identity": str(ship.get("uid", "")),
			"knownUids": known,
			"mountCount": mount_count,
			"hullType": hull_type,
			"oldLoadout": old_loadout.duplicate(true),
			"newLoadout": new_loadout.duplicate(true),
			"goals": goals.duplicate(true),
			"acquires": acquires.duplicate(true)
		}
	}

static func _family_for(location: String) -> String:
	if location.begins_with("mount"):
		return "weapons"
	if location == "engine":
		return "engines"
	if location == "armor":
		return "armor"
	return ""

static func _restore(dest: Dictionary, snap: Dictionary) -> void:
	for key in dest.keys():
		dest.erase(key)
	for key in snap.keys():
		var value = snap[key]
		dest[key] = value.duplicate(true) if (value is Dictionary or value is Array) else value

## Payment has already been staged by the caller. Accept new parts only here.
static func commit(probe: Dictionary, plan: Dictionary, catalog: Dictionary, base: Dictionary) -> Dictionary:
	if not plan is Dictionary or not plan.get("goals") is Dictionary or not plan.get("acquires") is Array:
		return _fail("The fitting plan is malformed.")
	if plan.get("initialize") == true:
		var seeded: Dictionary = Records.initialize(probe, {"base": base, "loadout": plan.oldLoadout, "catalog": catalog, "identity": str(plan.identity), "knownUids": plan.knownUids})
		if not seeded.ok:
			return _forward(seeded)
	var absorbed: Dictionary = Records.absorb_legacy_damage(probe)
	if not absorbed.ok:
		return _forward(absorbed)
	var condition: Dictionary = probe.moduleCondition
	var snap: Dictionary = condition.duplicate(true)
	var entering: Array = []
	var stayed: Dictionary = {}
	for key in condition.items.keys():
		if str(condition.items[key].family) == "pumps":
			continue
		if not plan.goals.has(str(key)):
			_restore(condition, snap)
			return _fail("The fitting plan dropped a physical part.")
	for uid in plan.goals.keys():
		if not condition.items.has(str(uid)):
			_restore(condition, snap)
			return _fail("That exact part is not on this hull.")
		var dest: String = str(plan.goals[uid])
		var prior: String = str(snap.items[uid].location)
		condition.items[uid].location = dest
		if dest == "locker":
			if prior == "locker":
				stayed[str(uid)] = int(snap.items[uid].lockerOrder)
			else:
				entering.append(str(uid))
		else:
			condition.items[uid].lockerOrder = 0
	entering.sort()
	var next_order: int = 0
	for uid in stayed.keys():
		condition.items[uid].lockerOrder = int(stayed[uid])
		next_order = maxi(next_order, int(stayed[uid]))
	for uid in entering:
		next_order += 1
		condition.items[uid].lockerOrder = next_order
	var found_engine: bool = false
	for key in condition.items.keys():
		if str(condition.items[key].location) == "engine":
			condition.legacyEngineSynced = float(condition.items[key].hp)
			found_engine = true
			break
	if not found_engine and condition.has("legacyEngineSynced"):
		condition.erase("legacyEngineSynced")
	var ctx: Dictionary = {"mountCount": plan.mountCount, "hullType": plan.hullType, "knownUids": plan.knownUids}
	var moved: Dictionary = Core.validate(condition, ctx)
	if not moved.ok:
		_restore(condition, snap)
		return _forward(moved)
	for acquire in plan.acquires:
		var accepted: Dictionary = Core.accept_acquired_item(condition, {
			"acquired": true,
			"family": str(acquire.family),
			"typeId": str(acquire.typeId),
			"originHullType": str(acquire.originHullType),
			"location": str(acquire.location),
			"hp": 1.0,
			"mountCount": plan.mountCount,
			"hullType": plan.hullType,
			"knownUids": plan.knownUids
		})
		if not accepted.ok:
			_restore(condition, snap)
			return _forward(accepted)
	ctx.loadout = plan.newLoadout
	var matched: Dictionary = Core.validate(condition, ctx)
	if not matched.ok:
		_restore(condition, snap)
		return _forward(matched)
	var published: Dictionary = Records.publish(probe)
	if not published.ok:
		_restore(condition, snap)
		return _forward(published)
	return {"ok": true, "engine": probe.engine, "refitLocker": probe.refitLocker.duplicate(true)}
