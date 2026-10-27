extends RefCounted
## NEW v0.031 equipment-condition prototype. Not called by Battle, Refit, Damage,
## Harbor, or the campaign. No preload of those modules. Pure dictionaries.
##
## Bounds, matching current refit/save limits rather than a tighter cap:
##   MAX_LOCKER 256 (Refit.MAX_LOCKER / SaveValidation.MAX_LOCKER). A larger
##   legacy list is refused whole; items are not dropped.
##   MAX_MOUNTS 4 (MountLayout mount0..mount3). mountCount is caller-supplied.
##   MAX_ITEMS 263 = 256 locker + 4 mounts + engine + armor + pumps.
##   typeId / originHullType: 1..64 of [A-Za-z0-9_].
##   birth identity: 1..128 of [A-Za-z0-9_.:@-], and it must not equal the hull
##   type id. Item UIDs: 1..96 of [A-Za-z0-9_-]. Cause: 0..80 printable ASCII.
##   nextItemSeq, version, lockerOrder, mountCount: finite whole numbers
##   (int or float) inside their bounds. Strings, bools, fractions, NaN, and
##   infinity are refused and are not rounded into range. hp: finite 0..1.
##   Godot JSON.parse_string restores whole counters as floats; that form is valid.
## Stock type ids are only stock_primary, stock_engine, stock_armor.
## Jury defaults: disable 0.20, re-enable 0.30, cap 0.75, ok at 0.999.
## Rates and coin prices are not defined here.

const MAX_LOCKER: int = 256
const MAX_MOUNTS: int = 4
const MAX_ITEMS: int = 263
const MAX_TOKEN: int = 64
const MAX_IDENTITY: int = 128
const MAX_UID: int = 96
const MAX_CAUSE: int = 80
const MAX_SERIAL: int = 1000000
const VERSION: int = 1
const DISABLE_HP: float = 0.20
const REENABLE_HP: float = 0.30
const JURY_CAP: float = 0.75
const OK_HP: float = 0.999
const EPS: float = 0.0000001

const OWNER_KEYS: Array = ["version", "birthNamespace", "nextItemSeq", "repairPriority", "legacyEngineSynced", "items"]
const ITEM_KEYS: Array = ["itemUid", "family", "typeId", "originHullType", "location", "lockerOrder", "hp", "cause", "status"]
const FAMILIES: Array = ["weapons", "engines", "armor", "pumps"]
const PRIORITIES: Array = ["auto", "hull", "pumps", "engine", "weapons"]
const STOCK_TYPES: Array = ["stock_primary", "stock_engine", "stock_armor"]
const LOCATIONS: Array = ["mount0", "mount1", "mount2", "mount3", "engine", "armor", "pumps", "locker"]

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func _keys_only(value: Dictionary, allowed: Array) -> bool:
	for key in value.keys():
		if not (key in allowed):
			return false
	return true

static func _number(value) -> bool:
	if value is bool or not (value is int or value is float):
		return false
	return is_finite(float(value))

static func _unit(value) -> bool:
	if not _number(value):
		return false
	var n: float = float(value)
	return n >= 0.0 and n <= 1.0

static func _whole_in(value, minimum: float, maximum: float) -> bool:
	if not _number(value):
		return false
	var n: float = float(value)
	return n >= minimum and n <= maximum and floor(n) == n

static func _chars(text: String, minimum: int, maximum: int, extra: String) -> bool:
	if text.length() < minimum or text.length() > maximum:
		return false
	for i in text.length():
		var code: int = text.unicode_at(i)
		var letter: bool = (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		if letter or code == 95 or extra.contains(char(code)):
			continue
		return false
	return true

static func _token(value) -> bool:
	return value is String and _chars(value, 1, MAX_TOKEN, "")

static func _identity(value) -> bool:
	return value is String and _chars(value, 1, MAX_IDENTITY, "-.:@")

static func _uid(value) -> bool:
	return value is String and _chars(value, 1, MAX_UID, "-")

static func _cause(value) -> bool:
	if not value is String or value.length() > MAX_CAUSE:
		return false
	for i in value.length():
		var code: int = value.unicode_at(i)
		if code < 32 or code > 126:
			return false
	return true

static func _whole(value, maximum: int) -> bool:
	return _whole_in(value, 0.0, float(maximum))

static func _fnv(text: String, offset: int) -> int:
	var hash: int = offset & 0xFFFFFFFF
	var prime: int = 16777619
	for i in text.length():
		hash = (hash ^ text.unicode_at(i)) & 0xFFFFFFFF
		hash = (hash * prime) & 0xFFFFFFFF
	return hash

static func mint_uid(birth_namespace: String, serial: int) -> String:
	var high: int = _fnv(birth_namespace, 2166136261)
	var low: int = _fnv(birth_namespace + "|", 2166136261)
	return "it-%08x%08x-%d" % [high, low, serial]

static func _status_for(hp: float, previous: String) -> String:
	if hp >= OK_HP:
		return "ok"
	if hp <= DISABLE_HP + EPS:
		return "disabled"
	if previous == "disabled" and hp < REENABLE_HP - EPS:
		return "disabled"
	return "damaged"

static func _set_hp(item: Dictionary, hp: float, cause: String, replace_cause: bool) -> void:
	var previous: String = str(item.get("status", "ok"))
	item.hp = clampf(hp, 0.0, 1.0)
	item.status = _status_for(float(item.hp), previous)
	if item.status == "ok":
		item.cause = ""
	elif replace_cause and _cause(cause):
		item.cause = cause

static func _mount_index(location: String) -> int:
	if location.begins_with("mount") and location.length() == 6 and location.substr(5, 1).is_valid_int():
		return int(location.substr(5, 1))
	return 0

static func _family_for_location(location: String) -> String:
	if location.begins_with("mount"):
		return "weapons"
	if location == "engine":
		return "engines"
	if location == "armor":
		return "armor"
	if location == "pumps":
		return "pumps"
	return ""

static func _priority_family(priority: String) -> String:
	if priority == "engine":
		return "engines"
	if priority == "weapons":
		return "weapons"
	if priority == "pumps":
		return "pumps"
	return ""

static func _family_index(family: String, priority: String) -> int:
	var order: Array = ["pumps", "engines", "weapons"]
	var base: int = order.find(family)
	if base < 0:
		return 9
	if priority == "auto" or priority == "hull":
		return base
	if family == _priority_family(priority):
		return 0
	return 1 + base

static func _repair_key(item: Dictionary, priority: String) -> String:
	var family: String = str(item.family)
	var preferred: bool = family == _priority_family(priority)
	var group: int = 0 if priority == "auto" or preferred else 1
	var phase: int = 0 if str(item.status) == "disabled" else 1
	var mount_index: int = _mount_index(str(item.location))
	if priority == "auto":
		return "%d-%d-%02d-%s" % [phase, _family_index(family, priority), mount_index, str(item.itemUid)]
	return "%d-%d-%d-%02d-%s" % [group, phase, _family_index(family, priority), mount_index, str(item.itemUid)]

static func _rollback(dest: Dictionary, snap: Dictionary) -> void:
	for key in dest.keys():
		dest.erase(key)
	for key in snap.keys():
		var value = snap[key]
		if value is Dictionary or value is Array:
			dest[key] = value.duplicate(true)
		else:
			dest[key] = value

static func _foreign(ship: Dictionary) -> bool:
	for key in ship.keys():
		if str(key) == "moduleCondition":
			continue
		var text: String = str(key).to_lower()
		var noun: bool = text.contains("module") or text.contains("fitting") or text.contains("equipment") or text.contains("weapon") or text.contains("engine") or text.contains("armor") or text.contains("pump")
		var state: bool = text.contains("condition") or text.contains("state")
		if noun and state:
			return true
	var spec = ship.get("spec", {})
	if not spec is Dictionary:
		return false
	var mounts = spec.get("weaponMounts", [])
	if not mounts is Array:
		return false
	for mount in mounts:
		if not mount is Dictionary:
			continue
		for key in mount.keys():
			var field: String = str(key).to_lower()
			if field.contains("condition") or field.contains("state") or field in ["disabled", "serial", "health", "hp", "status", "cause", "itemuid"]:
				return true
	return false

static func _known_set(value) -> Dictionary:
	var found: Dictionary = {}
	if value == null:
		return {"ok": true, "uids": found}
	if not value is Array:
		return _fail("Known item UIDs must be an array.")
	for uid in value:
		if not _uid(uid):
			return _fail("A known item UID is malformed.")
		found[str(uid)] = true
	return {"ok": true, "uids": found}

static func _structural(item: Dictionary) -> String:
	var family: String = str(item.family)
	var location: String = str(item.location)
	var expected: String = _family_for_location(location)
	if location == "locker":
		if family == "pumps":
			return "Integral pumps cannot enter the locker."
		if int(item.lockerOrder) < 0:
			return "Locker order is invalid."
	else:
		if expected.is_empty() or family != expected:
			return "That part does not belong in that slot."
		if int(item.lockerOrder) != 0:
			return "An installed part has locker order."
		if location.begins_with("mount") and (_mount_index(location) < 0 or _mount_index(location) >= MAX_MOUNTS):
			return "That hardpoint is not a real mount."
	if str(item.typeId) == "stock_primary" and location != "locker" and location != "mount0":
		return "The factory primary fits only the main hardpoint."
	if family == "pumps" and location != "pumps":
		return "Integral pumps cannot leave their bay."
	return ""

static func _placement(item: Dictionary, mount_count: int, hull_type: String) -> String:
	var family: String = str(item.family)
	var location: String = str(item.location)
	var expected: String = _family_for_location(location)
	if location == "locker":
		if family == "pumps":
			return "Integral pumps cannot enter the locker."
		if int(item.lockerOrder) < 0:
			return "Locker order is invalid."
	else:
		if expected.is_empty() or family != expected:
			return "That part does not belong in that slot."
		if int(item.lockerOrder) != 0:
			return "An installed part has locker order."
		if location.begins_with("mount") and _mount_index(location) >= mount_count:
			return "That hardpoint is not on this hull."
	if str(item.typeId) == "stock_primary" and location != "locker" and location != "mount0":
		return "The factory primary fits only the main hardpoint."
	if str(item.typeId) in STOCK_TYPES and location != "locker" and str(item.originHullType) != hull_type:
		return "A factory part cannot be installed on a different hull design."
	if family == "pumps" and str(item.originHullType) != hull_type:
		return "Integral pumps belong to their hull design."
	return ""

static func _records(condition: Dictionary) -> Dictionary:
	if not condition is Dictionary:
		return _fail("Equipment condition must be a dictionary.")
	if not _keys_only(condition, OWNER_KEYS):
		return _fail("Equipment condition has an unknown field.")
	for key in ["version", "birthNamespace", "nextItemSeq", "repairPriority", "items"]:
		if not condition.has(key):
			return _fail("Equipment condition is missing " + str(key) + ".")
	if not _whole_in(condition.version, float(VERSION), float(VERSION)):
		return _fail("Equipment condition version is not supported.")
	if not _identity(condition.birthNamespace):
		return _fail("Birth namespace is malformed.")
	if not _whole_in(condition.nextItemSeq, 1.0, float(MAX_SERIAL)):
		return _fail("Item serial is outside its bounds.")
	if not condition.repairPriority in PRIORITIES:
		return _fail("Repair priority is unknown.")
	if not condition.items is Dictionary:
		return _fail("Equipment items must be a dictionary.")
	if condition.items.size() > MAX_ITEMS:
		return _fail("Equipment record exceeds the existing part bound.")
	var seen_location: Dictionary = {}
	var seen_order: Dictionary = {}
	var locker: int = 0
	var engine_hp: float = -1.0
	var has_engine: bool = false
	for key in condition.items.keys():
		if not _uid(key):
			return _fail("An item key is malformed.")
		var item = condition.items[key]
		if not item is Dictionary or not _keys_only(item, ITEM_KEYS):
			return _fail("An equipment item has an unknown field.")
		for required in ITEM_KEYS:
			if not item.has(required):
				return _fail("An equipment item is incomplete.")
		if str(item.itemUid) != str(key) or not _uid(item.itemUid):
			return _fail("An item UID does not match its record.")
		if not str(item.family) in FAMILIES or not _token(item.typeId) or not _token(item.originHullType):
			return _fail("An equipment item has an unknown family or type.")
		if not str(item.location) in LOCATIONS:
			return _fail("An equipment item is in an unknown place.")
		if not _whole_in(item.lockerOrder, 0.0, float(MAX_SERIAL)):
			return _fail("Locker order is invalid.")
		if not _unit(item.hp) or not _cause(item.cause) or not str(item.status) in ["ok", "damaged", "disabled"]:
			return _fail("An equipment item has an invalid condition.")
		if str(item.status) != _status_for(float(item.hp), str(item.status)):
			return _fail("Stored status does not match condition.")
		if str(item.status) == "ok" and not str(item.cause).is_empty():
			return _fail("A sound part is carrying a damage cause.")
		if str(item.location) == "locker":
			locker += 1
			if seen_order.has(int(item.lockerOrder)):
				return _fail("Two locker parts share an order.")
			seen_order[int(item.lockerOrder)] = true
		else:
			if seen_location.has(str(item.location)):
				return _fail("Two parts occupy one slot.")
			seen_location[str(item.location)] = str(key)
		if str(item.location) == "engine":
			has_engine = true
			engine_hp = float(item.hp)
		var placed: String = _structural(item)
		if not placed.is_empty():
			return _fail(placed)
	if locker > MAX_LOCKER:
		return _fail("The locker exceeds the existing 256-part bound.")
	var preview: String = mint_uid(str(condition.birthNamespace), int(condition.nextItemSeq))
	if condition.items.has(preview):
		return _fail("The next item serial is already used.")
	if has_engine:
		if not condition.has("legacyEngineSynced") or not _unit(condition.legacyEngineSynced):
			return _fail("Engine projection watermark is missing.")
		if absf(float(condition.legacyEngineSynced) - engine_hp) > 0.0001:
			return _fail("Engine projection watermark does not match the engine part.")
	elif condition.has("legacyEngineSynced"):
		return _fail("Engine watermark exists without an engine part.")
	return {"ok": true, "hasEngine": has_engine, "engineHp": engine_hp, "locations": seen_location, "locker": locker}

static func _records_numeric(condition: Dictionary) -> Dictionary:
	# Internal to EquipmentRollout.prefix's strictly validated private copy.
	# Only hp/status/cause/watermark can change in its shared numeric kernels.
	# Full immutable schema is checked at entry and again before publication.
	if not condition.get("items") is Dictionary or not condition.get("repairPriority") in PRIORITIES:
		return _fail("Equipment numerical context is malformed.")
	var has_engine: bool = false
	var engine_hp: float = -1.0
	var locations: Dictionary = {}
	var locker: int = 0
	for key in condition.items.keys():
		var item = condition.items[key]
		if not item is Dictionary:
			return _fail("An equipment item is incomplete.")
		if not _unit(item.get("hp")) or not _cause(item.get("cause")) or not str(item.get("status", "")) in ["ok", "damaged", "disabled"]:
			return _fail("An equipment item has an invalid condition.")
		if str(item.status) != _status_for(float(item.hp), str(item.status)):
			return _fail("Stored status does not match condition.")
		if str(item.status) == "ok" and not str(item.cause).is_empty():
			return _fail("A sound part is carrying a damage cause.")
		if str(item.location) == "locker": locker += 1
		else: locations[str(item.location)] = str(key)
		if str(item.location) == "engine":
			has_engine = true
			engine_hp = float(item.hp)
	if has_engine:
		if not _unit(condition.get("legacyEngineSynced")):
			return _fail("Engine projection watermark is missing.")
		if absf(float(condition.legacyEngineSynced) - engine_hp) > 0.0001:
			return _fail("Engine projection watermark does not match the engine part.")
	elif condition.has("legacyEngineSynced"):
		return _fail("Engine watermark exists without an engine part.")
	return {"ok": true, "hasEngine": has_engine, "engineHp": engine_hp, "locations": locations, "locker": locker}

static func validate(condition: Dictionary, context: Dictionary) -> Dictionary:
	if not context is Dictionary or not _keys_only(context, ["mountCount", "hullType", "knownUids", "loadout"]):
		return _fail("Condition context is malformed.")
	if not _whole(context.get("mountCount"), MAX_MOUNTS) or not _token(context.get("hullType")):
		return _fail("Hull mount count or hull type is malformed.")
	var records: Dictionary = _records(condition)
	if not records.ok:
		return records
	var known: Dictionary = _known_set(context.get("knownUids", []))
	if not known.ok:
		return known
	var hull_type: String = str(context.hullType)
	var mount_count: int = int(context.mountCount)
	for key in condition.items.keys():
		var item: Dictionary = condition.items[key]
		if known.uids.has(str(key)):
			return _fail("That physical part is already registered to another hull.")
		var placed: String = _placement(item, mount_count, hull_type)
		if not placed.is_empty():
			return _fail(placed)
	if context.has("loadout"):
		var matched: String = _matches_loadout(condition, context.loadout, mount_count)
		if not matched.is_empty():
			return _fail(matched)
	return {"ok": true, "hasEngine": records.hasEngine, "engineHp": records.engineHp}

static func _matches_loadout(condition: Dictionary, loadout, mount_count: int) -> String:
	if not loadout is Dictionary or not _keys_only(loadout, ["weapons", "engine", "armor"]):
		return "Loadout context is malformed."
	if not loadout.get("weapons") is Array or loadout.weapons.size() != mount_count:
		return "Loadout hardpoints do not match this hull."
	if not loadout.get("engine") is String or not loadout.get("armor") is String:
		return "Loadout engine or armor is malformed."
	var expect: Dictionary = {}
	for i in range(mount_count):
		var type_id = loadout.weapons[i]
		if not type_id is String or (not type_id.is_empty() and not _token(type_id)):
			return "A loadout weapon id is malformed."
		if not str(type_id).is_empty():
			expect["mount%d" % i] = str(type_id)
	if not str(loadout.engine).is_empty():
		if not _token(loadout.engine):
			return "Loadout engine id is malformed."
		expect.engine = str(loadout.engine)
	if not str(loadout.armor).is_empty():
		if not _token(loadout.armor):
			return "Loadout armor id is malformed."
		expect.armor = str(loadout.armor)
	var found: Dictionary = {}
	for key in condition.items.keys():
		var item: Dictionary = condition.items[key]
		if str(item.location) == "locker" or str(item.location) == "pumps":
			continue
		found[str(item.location)] = str(item.typeId)
	if found.size() != expect.size():
		return "Installed parts do not match the declared loadout."
	for location in expect.keys():
		if str(found.get(location, "")) != str(expect[location]):
			return "Installed parts do not match the declared loadout."
	return ""

static func _descriptor(raw, forced_location: String) -> Dictionary:
	if not raw is Dictionary or not _keys_only(raw, ["family", "typeId", "originHullType", "location", "hp", "cause", "itemUid"]):
		return _fail("An equipment descriptor has an unknown field.")
	for key in ["family", "typeId", "originHullType", "location"]:
		if not raw.has(key):
			return _fail("An equipment descriptor is incomplete.")
	if not str(raw.family) in FAMILIES or not _token(raw.typeId) or not _token(raw.originHullType):
		return _fail("An equipment descriptor has an unknown family or type.")
	var location: String = str(raw.location)
	if not forced_location.is_empty() and location != forced_location:
		return _fail("A locker descriptor must stay in the locker.")
	if not location in LOCATIONS:
		return _fail("An equipment descriptor has an unknown place.")
	if raw.has("hp") and not _unit(raw.hp):
		return _fail("An equipment descriptor has an invalid condition.")
	if raw.has("cause") and not _cause(raw.cause):
		return _fail("An equipment descriptor has an invalid cause.")
	if raw.has("itemUid") and not _uid(raw.itemUid):
		return _fail("An equipment descriptor has a malformed item UID.")
	return {"ok": true}

static func _engine_birth_hp(ship: Dictionary, request: Dictionary, raw: Dictionary) -> Dictionary:
	var samples: Array = []
	if ship.has("engine"):
		if not _unit(ship.engine):
			return _fail("The legacy engine scalar is not a finite condition.")
		samples.append(float(ship.engine))
	if request.has("engineScalar"):
		if not _unit(request.engineScalar):
			return _fail("The supplied engine scalar is not a finite condition.")
		samples.append(float(request.engineScalar))
	if raw.has("hp"):
		samples.append(float(raw.hp))
	if samples.is_empty():
		return _fail("Seeding an engine requires the legacy engine scalar.")
	var hp: float = float(samples[0])
	for sample in samples:
		hp = minf(hp, float(sample))
	return {"ok": true, "hp": hp}

static func legacy_seed(ship: Dictionary, request: Dictionary) -> Dictionary:
	if not ship is Dictionary or not request is Dictionary:
		return _fail("Seed requires a hull dictionary and an explicit request.")
	if not _keys_only(request, ["identity", "hullType", "mountCount", "knownUids", "installed", "locker", "engineScalar", "loadout"]):
		return _fail("Seed request has an unknown field.")
	if not _identity(request.get("identity")) or not _token(request.get("hullType")) or not _whole(request.get("mountCount"), MAX_MOUNTS):
		return _fail("Seed requires a stable hull identity, hull type, and mount count.")
	var identity: String = str(request.identity)
	var hull_type: String = str(request.hullType)
	if identity == hull_type or identity == str(ship.get("type", "")) or identity == "boat":
		return _fail("Item identity cannot be minted from the hull type id.")
	if ship.has("id") and identity == str(ship.id) and str(ship.get("type", ship.id)) == str(ship.id):
		return _fail("Item identity cannot be minted from a generic spec id.")
	if _foreign(ship):
		return _fail("Unrecognized condition metadata was left untouched.")
	var mount_count: int = int(request.mountCount)
	if ship.has("moduleCondition"):
		if not ship.moduleCondition is Dictionary:
			return _fail("Existing equipment condition is corrupt and was left untouched.")
		var structural: Dictionary = _records(ship.moduleCondition)
		if not structural.ok:
			return _fail("Existing equipment condition is corrupt and was left untouched.")
		var existing_context: Dictionary = {"mountCount": mount_count, "hullType": hull_type, "knownUids": request.get("knownUids", [])}
		if request.has("loadout"):
			existing_context.loadout = request.loadout
		var existing: Dictionary = validate(ship.moduleCondition, existing_context)
		if not existing.ok:
			return existing
		if str(ship.moduleCondition.birthNamespace) != identity:
			return _fail("Existing parts keep their birth namespace.")
		var again: Dictionary = {"ok": true, "idempotent": true, "changed": false, "itemUids": _uid_list(ship.moduleCondition), "nextItemSeq": int(ship.moduleCondition.nextItemSeq), "hasEngine": existing.hasEngine}
		if existing.hasEngine:
			again.engineHp = existing.engineHp
		return again
	var known: Dictionary = _known_set(request.get("knownUids", []))
	if not known.ok:
		return known
	var installed = request.get("installed", [])
	var locker = request.get("locker", [])
	if not installed is Array or not locker is Array:
		return _fail("Seed descriptors must be arrays.")
	if locker.size() > MAX_LOCKER or installed.size() + locker.size() > MAX_ITEMS:
		return _fail("Seed descriptors exceed the existing part bound.")
	var built: Dictionary = {"version": VERSION, "birthNamespace": identity, "nextItemSeq": 1, "repairPriority": "auto", "items": {}}
	var serial: int = 1
	var occupied: Dictionary = {}
	var orders: Dictionary = {}
	var next_order: int = 1
	for entry in installed:
		var made: Dictionary = _take_descriptor(entry, "", built, known, occupied, orders, identity, hull_type, mount_count, serial, next_order, ship, request)
		if not made.ok:
			return made
		serial = int(made.serial)
		next_order = int(made.nextOrder)
	for entry in locker:
		var stored: Dictionary = _take_descriptor(entry, "locker", built, known, occupied, orders, identity, hull_type, mount_count, serial, next_order, ship, request)
		if not stored.ok:
			return stored
		serial = int(stored.serial)
		next_order = int(stored.nextOrder)
	built.nextItemSeq = serial
	var context: Dictionary = {"mountCount": mount_count, "hullType": hull_type, "knownUids": request.get("knownUids", [])}
	if request.has("loadout"):
		context.loadout = request.loadout
	var checked: Dictionary = validate(built, context)
	if not checked.ok:
		return checked
	ship.moduleCondition = built
	return {"ok": true, "idempotent": false, "changed": true, "itemUids": _uid_list(built), "nextItemSeq": serial, "hasEngine": checked.hasEngine, "engineHp": checked.engineHp}

static func _take_descriptor(entry, forced: String, built: Dictionary, known: Dictionary, occupied: Dictionary, orders: Dictionary, identity: String, hull_type: String, mount_count: int, serial: int, next_order: int, ship: Dictionary, request: Dictionary) -> Dictionary:
	var described: Dictionary = _descriptor(entry, forced)
	if not described.ok:
		return described
	if forced.is_empty() and str(entry.location) == "locker":
		return _fail("Installed descriptors cannot start in the locker.")
	var family: String = str(entry.family)
	var location: String = str(entry.location)
	var type_id: String = str(entry.typeId)
	var origin: String = str(entry.originHullType)
	if family == "pumps" and (location != "pumps" or origin != hull_type):
		return _fail("Integral pumps are hull-bound and are not invented.")
	if type_id in STOCK_TYPES and origin != hull_type and location != "locker":
		return _fail("A factory part cannot be seeded onto a different hull design.")
	if occupied.has(location):
		return _fail("Two descriptors occupy one slot.")
	if location != "locker":
		occupied[location] = true
	var hp: float = 1.0
	if location == "engine":
		var born: Dictionary = _engine_birth_hp(ship, request, entry)
		if not born.ok:
			return born
		hp = float(born.hp)
	elif entry.has("hp"):
		hp = float(entry.hp)
	var uid: String = ""
	if entry.has("itemUid"):
		uid = str(entry.itemUid)
		if built.items.has(uid) or known.uids.has(uid):
			return _fail("A seeded item UID is already registered.")
	else:
		if serial > MAX_SERIAL:
			return _fail("Item serial is outside its bounds.")
		uid = mint_uid(identity, serial)
		if built.items.has(uid) or known.uids.has(uid):
			return _fail("A minted item UID is already registered.")
		serial += 1
	var order: int = 0
	if location == "locker":
		order = next_order
		next_order += 1
		if orders.has(order):
			return _fail("Two locker parts share an order.")
		orders[order] = true
	var item: Dictionary = {"itemUid": uid, "family": family, "typeId": type_id, "originHullType": origin, "location": location, "lockerOrder": order, "hp": 1.0, "cause": str(entry.get("cause", "")) if entry.has("cause") else "", "status": "ok"}
	if not _cause(item.cause):
		return _fail("An equipment descriptor has an invalid cause.")
	_set_hp(item, hp, str(item.cause), not str(item.cause).is_empty())
	var placed: String = _placement(item, mount_count, hull_type)
	if not placed.is_empty():
		return _fail(placed)
	built.items[uid] = item
	if location == "engine":
		built.legacyEngineSynced = float(item.hp)
	return {"ok": true, "serial": serial, "nextOrder": next_order}

static func _uid_list(condition: Dictionary) -> Array:
	var uids: Array = condition.items.keys()
	uids.sort()
	return uids

static func inspect_installed(condition: Dictionary) -> Dictionary:
	var records: Dictionary = _records(condition)
	if not records.ok:
		return records
	return _installed_rows(condition)

static func _installed_rows(condition: Dictionary) -> Dictionary:
	var rows: Array = []
	for key in _uid_list(condition):
		var item: Dictionary = condition.items[key]
		if str(item.location) == "locker":
			continue
		rows.append(item.duplicate(true))
	rows.sort_custom(func(a, b): return _location_rank(str(a.location)) < _location_rank(str(b.location)))
	return {"ok": true, "items": rows}

static func _location_rank(location: String) -> int:
	var rank: int = LOCATIONS.find(location)
	return rank if rank >= 0 else 99

static func list_locker(condition: Dictionary) -> Dictionary:
	var records: Dictionary = _records(condition)
	if not records.ok:
		return records
	var rows: Array = []
	for key in _uid_list(condition):
		var item: Dictionary = condition.items[key]
		if str(item.location) != "locker":
			continue
		rows.append(item.duplicate(true))
	rows.sort_custom(func(a, b):
		if int(a.lockerOrder) == int(b.lockerOrder):
			return str(a.itemUid) < str(b.itemUid)
		return int(a.lockerOrder) < int(b.lockerOrder)
	)
	return {"ok": true, "items": rows, "counts": _locker_counts(condition)}

static func _locker_counts(condition: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for key in condition.items.keys():
		var item: Dictionary = condition.items[key]
		if str(item.location) != "locker":
			continue
		var type_id: String = str(item.typeId)
		counts[type_id] = int(counts.get(type_id, 0)) + 1
	return counts

static func project(condition: Dictionary) -> Dictionary:
	var records: Dictionary = _records(condition)
	if not records.ok:
		return records
	return _project_from_records(condition, records)

static func _project_numeric(condition: Dictionary) -> Dictionary:
	var records: Dictionary = _records_numeric(condition)
	if not records.ok:
		return records
	return _project_from_records(condition, records)

static func _project_from_records(condition: Dictionary, records: Dictionary) -> Dictionary:
	var installed: Dictionary = _installed_rows(condition)
	var projected: Dictionary = {"ok": true, "refitLocker": _locker_counts(condition), "hasEngine": records.hasEngine, "installed": installed.items}
	if records.hasEngine:
		projected.engineHp = records.engineHp
		projected.legacyEngineSynced = float(condition.legacyEngineSynced)
	return projected

static func _project_publish_fields(condition: Dictionary) -> Dictionary:
	var records: Dictionary = _records(condition)
	if not records.ok:
		return records
	return _publish_fields_from_records(condition, records)

static func _project_publish_fields_numeric(condition: Dictionary) -> Dictionary:
	var records: Dictionary = _records_numeric(condition)
	if not records.ok:
		return records
	return _publish_fields_from_records(condition, records)

static func _publish_fields_from_records(condition: Dictionary, records: Dictionary) -> Dictionary:
	# Publish stores engine and locker counts only. Installed rows are not built.
	var projected: Dictionary = {"ok": true, "refitLocker": _locker_counts(condition), "hasEngine": records.hasEngine}
	if records.hasEngine:
		projected.engineHp = records.engineHp
		projected.legacyEngineSynced = float(condition.legacyEngineSynced)
	return projected

static func _context_of(request: Dictionary) -> Dictionary:
	if not request.has("mountCount") or not request.has("hullType"):
		return _fail("The hull mount count and hull type are required.")
	var context: Dictionary = {"mountCount": request.mountCount, "hullType": request.hullType, "knownUids": request.get("knownUids", [])}
	return {"ok": true, "context": context}

static func move_exact(condition: Dictionary, request: Dictionary) -> Dictionary:
	if not request is Dictionary or not _keys_only(request, ["itemUid", "location", "mountCount", "hullType", "knownUids"]):
		return _fail("Move request is malformed.")
	if not _uid(request.get("itemUid")) or not str(request.get("location")) in LOCATIONS:
		return _fail("Move requires an exact item and a known place.")
	var wrapped: Dictionary = _context_of(request)
	if not wrapped.ok:
		return wrapped
	var before: Dictionary = validate(condition, wrapped.context)
	if not before.ok:
		return before
	var snap: Dictionary = condition.duplicate(true)
	var uid: String = str(request.itemUid)
	if not condition.items.has(uid):
		return _fail("That exact part is not on this hull.")
	var item: Dictionary = condition.items[uid]
	var destination: String = str(request.location)
	if str(item.family) == "pumps" or destination == "pumps" or str(item.location) == "pumps":
		return _fail("Integral pumps stay in their bay.")
	if str(item.location) == destination:
		return {"ok": true, "changed": false, "itemUid": uid, "location": destination, "hp": float(item.hp)}
	for other in condition.items.keys():
		if destination != "locker" and str(other) != uid and str(condition.items[other].location) == destination:
			return _fail("That slot is already occupied.")
	item.location = destination
	if destination == "locker":
		item.lockerOrder = _next_order(condition, uid)
	else:
		item.lockerOrder = 0
	_sync_watermark(condition)
	var after: Dictionary = validate(condition, wrapped.context)
	if not after.ok:
		_rollback(condition, snap)
		return after
	return {"ok": true, "changed": true, "itemUid": uid, "location": destination, "hp": float(item.hp), "status": str(item.status)}

static func _sync_watermark(condition: Dictionary) -> void:
	var found: bool = false
	var hp: float = 0.0
	for key in condition.items.keys():
		if str(condition.items[key].location) == "engine":
			found = true
			hp = float(condition.items[key].hp)
			break
	if found:
		condition.legacyEngineSynced = hp
	else:
		condition.erase("legacyEngineSynced")

static func _next_order(condition: Dictionary, except_uid: String) -> int:
	var highest: int = 0
	for key in condition.items.keys():
		if str(key) == except_uid:
			continue
		if str(condition.items[key].location) == "locker":
			highest = maxi(highest, int(condition.items[key].lockerOrder))
	return highest + 1

static func swap_exact(condition: Dictionary, request: Dictionary) -> Dictionary:
	if not request is Dictionary or not _keys_only(request, ["firstUid", "secondUid", "mountCount", "hullType", "knownUids"]):
		return _fail("Swap request is malformed.")
	if not _uid(request.get("firstUid")) or not _uid(request.get("secondUid")) or str(request.firstUid) == str(request.secondUid):
		return _fail("Swap requires two different exact parts.")
	var wrapped: Dictionary = _context_of(request)
	if not wrapped.ok:
		return wrapped
	var before: Dictionary = validate(condition, wrapped.context)
	if not before.ok:
		return before
	var snap: Dictionary = condition.duplicate(true)
	var first: Dictionary = condition.items.get(str(request.firstUid), {})
	var second: Dictionary = condition.items.get(str(request.secondUid), {})
	if first.is_empty() or second.is_empty():
		return _fail("That exact part is not on this hull.")
	if str(first.family) == "pumps" or str(second.family) == "pumps":
		return _fail("Integral pumps stay in their bay.")
	var first_location: String = str(first.location)
	var second_location: String = str(second.location)
	var first_order: int = int(first.lockerOrder)
	var second_order: int = int(second.lockerOrder)
	first.location = second_location
	second.location = first_location
	first.lockerOrder = second_order
	second.lockerOrder = first_order
	if str(first.location) != "locker":
		first.lockerOrder = 0
	if str(second.location) != "locker":
		second.lockerOrder = 0
	_sync_watermark(condition)
	var after: Dictionary = validate(condition, wrapped.context)
	if not after.ok:
		_rollback(condition, snap)
		return after
	return {"ok": true, "changed": true, "firstUid": str(first.itemUid), "secondUid": str(second.itemUid), "firstHp": float(first.hp), "secondHp": float(second.hp)}

static func transfer_exact(source: Dictionary, dest: Dictionary, request: Dictionary) -> Dictionary:
	if not request is Dictionary or not _keys_only(request, ["itemUid", "location", "mountCount", "hullType", "sourceMountCount", "sourceHullType", "knownUids"]):
		return _fail("Transfer request is malformed.")
	if is_same(source, dest) or not _uid(request.get("itemUid")) or not str(request.get("location")) in LOCATIONS:
		return _fail("Transfer requires two hulls, an exact item, and a known place.")
	if not _whole(request.get("sourceMountCount"), MAX_MOUNTS) or not _token(request.get("sourceHullType")):
		return _fail("Transfer requires the source hull type and mount count.")
	var dest_context: Dictionary = _context_of(request)
	if not dest_context.ok:
		return dest_context
	var source_context: Dictionary = {"mountCount": request.sourceMountCount, "hullType": request.sourceHullType, "knownUids": request.get("knownUids", [])}
	var source_ok: Dictionary = validate(source, source_context)
	var dest_ok: Dictionary = validate(dest, dest_context.context)
	if not source_ok.ok:
		return source_ok
	if not dest_ok.ok:
		return dest_ok
	var custody: Dictionary = collect_item_uids([source, dest])
	if not custody.ok:
		return custody
	var uid: String = str(request.itemUid)
	if not source.items.has(uid):
		return _fail("That exact part is not on the source hull.")
	if dest.items.has(uid):
		return _fail("The destination already holds that physical part.")
	var known: Dictionary = _known_set(request.get("knownUids", []))
	if not known.ok:
		return known
	if known.uids.has(uid):
		return _fail("That physical part is already registered to another hull.")
	var source_snap: Dictionary = source.duplicate(true)
	var dest_snap: Dictionary = dest.duplicate(true)
	var moving: Dictionary = source.items[uid].duplicate(true)
	if str(moving.family) == "pumps" or str(request.location) == "pumps":
		return _fail("Integral pumps are not transferred.")
	source.items.erase(uid)
	moving.location = str(request.location)
	moving.lockerOrder = _next_order(dest, "") if moving.location == "locker" else 0
	dest.items[uid] = moving
	_sync_watermark(source)
	_sync_watermark(dest)
	var source_after: Dictionary = validate(source, source_context)
	var dest_after: Dictionary = validate(dest, dest_context.context)
	if not source_after.ok or not dest_after.ok:
		_rollback(source, source_snap)
		_rollback(dest, dest_snap)
		return dest_after if source_after.ok else source_after
	return {"ok": true, "changed": true, "itemUid": uid, "hp": float(moving.hp), "status": str(moving.status), "location": str(moving.location)}

static func note_engine_scalar(condition: Dictionary, scalar) -> Dictionary:
	return _note_engine_scalar_with(condition, scalar, _records)

static func _note_engine_scalar_numeric(condition: Dictionary, scalar) -> Dictionary:
	return _note_engine_scalar_with(condition, scalar, _records_numeric)

static func _note_engine_scalar_with(condition: Dictionary, scalar, validate: Callable) -> Dictionary:
	var records: Dictionary = validate.call(condition)
	if not records.ok:
		return records
	if not _unit(scalar):
		return _fail("The legacy engine scalar is not a finite condition.")
	if not records.hasEngine:
		return _fail("There is no engine part to project.")
	var observed: float = float(scalar)
	if observed >= float(records.engineHp) - 0.0001:
		return {"ok": true, "changed": false, "engineHp": float(records.engineHp)}
	var snap: Dictionary = condition.duplicate(true)
	var engine: Dictionary = {}
	for key in condition.items.keys():
		if str(condition.items[key].location) == "engine":
			engine = condition.items[key]
			break
	var cause: String = str(engine.cause) if not str(engine.cause).is_empty() else "Legacy engine scalar"
	_set_hp(engine, observed, cause, str(engine.cause).is_empty())
	condition.legacyEngineSynced = float(engine.hp)
	var after: Dictionary = validate.call(condition)
	if not after.ok:
		_rollback(condition, snap)
		return after
	return {"ok": true, "changed": true, "engineHp": float(engine.hp), "status": str(engine.status)}

static func apply_component_damage(condition: Dictionary, request: Dictionary) -> Dictionary:
	return _apply_component_damage_with(condition, request, _records)

static func _apply_component_damage_numeric(condition: Dictionary, request: Dictionary) -> Dictionary:
	return _apply_component_damage_with(condition, request, _records_numeric)

static func _apply_component_damage_with(condition: Dictionary, request: Dictionary, validate: Callable) -> Dictionary:
	if not request is Dictionary or not _keys_only(request, ["itemUid", "loss", "cause"]):
		return _fail("Damage request is malformed.")
	if not _uid(request.get("itemUid")) or not _number(request.get("loss")) or float(request.loss) < 0.0:
		return _fail("Damage requires an exact part and a finite loss.")
	if request.has("cause") and not _cause(request.cause):
		return _fail("Damage cause is invalid.")
	var records: Dictionary = validate.call(condition)
	if not records.ok:
		return records
	var uid: String = str(request.itemUid)
	if not condition.items.has(uid):
		return _fail("That exact part is not on this hull.")
	if float(request.loss) <= EPS:
		var untouched: Dictionary = condition.items[uid]
		return {"ok": true, "changed": false, "itemUid": uid, "hp": float(untouched.hp)}
	var snap: Dictionary = condition.duplicate(true)
	var item: Dictionary = condition.items[uid]
	var cause: String = str(request.cause) if request.has("cause") else str(item.cause)
	_set_hp(item, float(item.hp) - float(request.loss), cause, request.has("cause"))
	if str(item.location) == "engine":
		condition.legacyEngineSynced = float(item.hp)
	var after: Dictionary = validate.call(condition)
	if not after.ok:
		_rollback(condition, snap)
		return after
	return {"ok": true, "changed": true, "itemUid": uid, "hp": float(item.hp), "status": str(item.status)}

static func _affordable_hp(budget: float, factor: float, limit: float, budget_times_factor: bool) -> float:
	if not is_finite(budget) or not is_finite(factor) or not is_finite(limit):
		return -1.0
	if factor <= 0.0 or budget < 0.0 or limit < 0.0:
		return -1.0
	if budget <= EPS or limit <= EPS:
		return 0.0
	var span: float = budget * factor if budget_times_factor else budget / factor
	if not is_finite(span):
		return limit
	if span < 0.0:
		return -1.0
	return span

static func repair_installed(condition: Dictionary, request: Dictionary) -> Dictionary:
	return _repair_installed_with(condition, request, _records)

static func _repair_installed_numeric(condition: Dictionary, request: Dictionary) -> Dictionary:
	return _repair_installed_with(condition, request, _records_numeric)

static func _repair_installed_with(condition: Dictionary, request: Dictionary, validate: Callable, want_receipt051: bool = true) -> Dictionary:
	if not request is Dictionary or not _keys_only(request, ["work", "supplies", "hpPerWork", "suppliesPerHp", "priority", "juryCap"]):
		return _fail("Repair request is malformed.")
	for key in ["work", "supplies", "hpPerWork"]:
		if not _number(request.get(key)):
			return _fail("Repair work and supplies must be finite.")
	if float(request.work) < 0.0 or float(request.supplies) < 0.0 or float(request.hpPerWork) <= 0.0:
		return _fail("Repair budgets cannot be negative.")
	if not request.get("suppliesPerHp") is Dictionary:
		return _fail("Repair supply rates must be supplied by the caller.")
	var rates: Dictionary = {}
	for family in request.suppliesPerHp.keys():
		if not str(family) in FAMILIES:
			return _fail("Repair supply rates name an unknown family.")
		var rate = request.suppliesPerHp[family]
		if not _number(rate) or float(rate) <= 0.0:
			return _fail("A repair supply rate must be a finite amount above zero.")
		rates[str(family)] = float(rate)
	var records: Dictionary = validate.call(condition)
	if not records.ok:
		return records
	var priority: String = str(request.get("priority", condition.repairPriority))
	if not priority in PRIORITIES:
		return _fail("Repair priority is unknown.")
	var jury_cap: float = JURY_CAP
	if request.has("juryCap"):
		if not _unit(request.juryCap) or float(request.juryCap) > JURY_CAP + EPS or float(request.juryCap) < REENABLE_HP:
			return _fail("Jury repair cannot exceed the 0.75 cap.")
		jury_cap = float(request.juryCap)
	if priority == "hull":
		return {"ok": true, "changed": false, "usedWork": 0.0, "usedSupplies": 0.0, "changes": []}
	var snap = null
	var armed: bool = false
	var work_left: float = float(request.work)
	var supplies_left: float = float(request.supplies)
	var used_work: float = 0.0
	var used_supplies: float = 0.0
	var skipped: Dictionary = {}
	var guard: int = 0
	while guard < MAX_ITEMS:
		guard += 1
		if work_left <= EPS:
			break
		var found: bool = false
		var best_key: String = ""
		var best_uid: String = ""
		for key in condition.items.keys():
			if skipped.has(str(key)):
				continue
			var item: Dictionary = condition.items[key]
			if str(item.location) == "locker" or str(item.family) == "armor":
				continue
			if not rates.has(str(item.family)):
				continue
			if float(item.hp) >= jury_cap - EPS:
				continue
			if supplies_left <= EPS:
				continue
			var rank: String = _repair_key(item, priority)
			if not found or rank < best_key:
				found = true
				best_key = rank
				best_uid = str(key)
		if not found:
			break
		var target: Dictionary = condition.items[best_uid]
		var hp0: float = float(target.hp)
		var limit: float = jury_cap - hp0
		if str(target.status) == "disabled" and hp0 < REENABLE_HP:
			limit = minf(limit, REENABLE_HP - hp0)
		var rate: float = float(rates[str(target.family)])
		var hp_per: float = float(request.hpPerWork)
		var by_work: float = _affordable_hp(work_left, hp_per, limit, true)
		var by_supply: float = _affordable_hp(supplies_left, rate, limit, false)
		if by_work < 0.0 or by_supply < 0.0:
			if armed:
				_rollback(condition, snap)
			return _fail("Repair debit is not a finite nonnegative amount.")
		var gain: float = minf(limit, minf(by_work, by_supply))
		if not is_finite(gain) or gain < 0.0:
			if armed:
				_rollback(condition, snap)
			return _fail("Repair debit is not a finite nonnegative amount.")
		if gain <= EPS:
			skipped[best_uid] = true
			continue
		var spent_work: float = gain / hp_per
		var spent_supplies: float = gain * rate
		if not is_finite(spent_work) or not is_finite(spent_supplies) or spent_work < 0.0 or spent_supplies < 0.0:
			if armed:
				_rollback(condition, snap)
			return _fail("Repair debit is not a finite nonnegative amount.")
		if spent_work > work_left + 0.000001 or spent_supplies > supplies_left + 0.000001:
			if armed:
				_rollback(condition, snap)
			return _fail("Repair debit is not a finite nonnegative amount.")
		if not armed:
			snap = condition.duplicate(true)
			armed = true
		_set_hp(target, hp0 + gain, str(target.cause), false)
		if str(target.location) == "engine":
			condition.legacyEngineSynced = float(target.hp)
		work_left = maxf(0.0, work_left - spent_work)
		supplies_left = maxf(0.0, supplies_left - spent_supplies)
		used_work += spent_work
		used_supplies += spent_supplies
		if not is_finite(used_work) or not is_finite(used_supplies) or used_work < 0.0 or used_supplies < 0.0:
			_rollback(condition, snap)
			return _fail("Repair debit is not a finite nonnegative amount.")
	if guard >= MAX_ITEMS and work_left > EPS:
		if armed:
			_rollback(condition, snap)
		return _fail("Repair stopped on its part bound.")
	var after: Dictionary = validate.call(condition)
	if not after.ok:
		if armed:
			_rollback(condition, snap)
		return after
	if not is_finite(used_work) or not is_finite(used_supplies) or used_work < 0.0 or used_supplies < 0.0:
		if armed:
			_rollback(condition, snap)
		return _fail("Repair debit is not a finite nonnegative amount.")
	# Only the admitted owned writer opts out. Keep the original final finite
	# checks and rollback, but omit sorted UID allocation and the unused diff.
	if not want_receipt051:
		for key in condition.items:
			if not is_finite(float(condition.items[key].hp)) or (armed and not is_finite(float(snap.items[key].hp))):
				if armed: _rollback(condition,snap)
				return _fail("Repair debit is not a finite nonnegative amount.")
		return {"ok":true,"usedWork":used_work,"usedSupplies":used_supplies}
	var changes: Array = []
	for key in _uid_list(condition):
		var now: Dictionary = condition.items[key]
		var was: Dictionary = now
		if armed:
			was = snap.items[key]
		if not is_finite(float(now.hp)) or not is_finite(float(was.hp)):
			if armed:
				_rollback(condition, snap)
			return _fail("Repair debit is not a finite nonnegative amount.")
		if absf(float(now.hp) - float(was.hp)) <= EPS and str(now.status) == str(was.status):
			continue
		changes.append({"itemUid": str(key), "beforeHp": float(was.hp), "afterHp": float(now.hp), "beforeStatus": str(was.status), "afterStatus": str(now.status)})
	return {"ok": true, "changed": not changes.is_empty(), "usedWork": used_work, "usedSupplies": used_supplies, "changes": changes}

static func restore_installed_paid(condition: Dictionary, request: Dictionary) -> Dictionary:
	if not request is Dictionary or not _keys_only(request, ["confirmPaid"]) or request.get("confirmPaid") != true:
		return _fail("Paid restoration requires an explicit paid confirmation.")
	var records: Dictionary = _records(condition)
	if not records.ok:
		return records
	var snap: Dictionary = condition.duplicate(true)
	var changes: Array = []
	for key in condition.items.keys():
		var item: Dictionary = condition.items[key]
		if str(item.location) == "locker":
			continue
		var before_hp: float = float(item.hp)
		var before_status: String = str(item.status)
		_set_hp(item, 1.0, "", true)
		if str(item.location) == "engine":
			condition.legacyEngineSynced = float(item.hp)
		if absf(float(item.hp) - before_hp) > EPS or str(item.status) != before_status:
			changes.append({"itemUid": str(key), "beforeHp": before_hp, "afterHp": float(item.hp), "beforeStatus": before_status, "afterStatus": str(item.status)})
	var after: Dictionary = _records(condition)
	if not after.ok:
		_rollback(condition, snap)
		return after
	return {"ok": true, "changed": not changes.is_empty(), "usedWork": 0.0, "usedSupplies": 0.0, "changes": changes}

static func preview_next_item(condition: Dictionary) -> Dictionary:
	var records: Dictionary = _records(condition)
	if not records.ok:
		return records
	var serial: int = int(condition.nextItemSeq)
	return {"ok": true, "changed": false, "serial": serial, "itemUid": mint_uid(str(condition.birthNamespace), serial), "nextItemSeq": serial}

static func accept_acquired_item(condition: Dictionary, request: Dictionary) -> Dictionary:
	if not request is Dictionary or not _keys_only(request, ["acquired", "family", "typeId", "originHullType", "location", "hp", "cause", "mountCount", "hullType", "knownUids"]):
		return _fail("Acquisition request is malformed.")
	if request.get("acquired") != true:
		return _fail("A new part is accepted only after the adapter's own transaction.")
	var descriptor: Dictionary = request.duplicate(true)
	for context_key in ["acquired", "mountCount", "hullType", "knownUids"]:
		descriptor.erase(context_key)
	var described: Dictionary = _descriptor(descriptor, "")
	if not described.ok:
		return described
	var wrapped: Dictionary = _context_of(request)
	if not wrapped.ok:
		return wrapped
	var before: Dictionary = validate(condition, wrapped.context)
	if not before.ok:
		return before
	var snap: Dictionary = condition.duplicate(true)
	var serial: int = int(condition.nextItemSeq)
	var uid: String = mint_uid(str(condition.birthNamespace), serial)
	var known: Dictionary = _known_set(request.get("knownUids", []))
	if not known.ok:
		return known
	if condition.items.has(uid) or known.uids.has(uid):
		return _fail("A minted item UID is already registered.")
	if condition.items.size() + 1 > MAX_ITEMS:
		return _fail("Equipment record exceeds the existing part bound.")
	if str(request.location) == "locker" and _locker_size(condition) + 1 > MAX_LOCKER:
		return _fail("The locker exceeds the existing 256-part bound.")
	for key in condition.items.keys():
		if str(condition.items[key].location) == str(request.location) and str(request.location) != "locker":
			return _fail("That slot is already occupied.")
	var hp: float = float(request.hp) if request.has("hp") else 1.0
	var item: Dictionary = {"itemUid": uid, "family": str(request.family), "typeId": str(request.typeId), "originHullType": str(request.originHullType), "location": str(request.location), "lockerOrder": _next_order(condition, "") if str(request.location) == "locker" else 0, "hp": 1.0, "cause": str(request.get("cause", "")) if request.has("cause") else "", "status": "ok"}
	_set_hp(item, hp, str(item.cause), not str(item.cause).is_empty())
	condition.items[uid] = item
	condition.nextItemSeq = serial + 1
	if str(item.location) == "engine":
		condition.legacyEngineSynced = float(item.hp)
	var after: Dictionary = validate(condition, wrapped.context)
	if not after.ok:
		_rollback(condition, snap)
		return after
	return {"ok": true, "changed": true, "itemUid": uid, "nextItemSeq": int(condition.nextItemSeq), "hp": float(item.hp), "status": str(item.status)}

static func _locker_size(condition: Dictionary) -> int:
	var count: int = 0
	for key in condition.items.keys():
		if str(condition.items[key].location) == "locker":
			count += 1
	return count

static func acknowledge_hull_uid(condition: Dictionary, hull_uid: String) -> Dictionary:
	var records: Dictionary = _records(condition)
	if not records.ok:
		return records
	if not hull_uid is String:
		return _fail("Capture identity must be a string.")
	return {"ok": true, "changed": false, "birthNamespace": str(condition.birthNamespace), "itemUids": _uid_list(condition), "nextItemSeq": int(condition.nextItemSeq), "hullUid": hull_uid}

static func collect_item_uids(conditions: Array) -> Dictionary:
	if conditions.size() > 512:
		return _fail("Too many hull records to compare at once.")
	var seen: Dictionary = {}
	var ordered: Array = []
	for condition in conditions:
		var records: Dictionary = _records(condition)
		if not records.ok:
			return records
		for uid in _uid_list(condition):
			if seen.has(str(uid)):
				return _fail("Two hulls share one physical part.")
			seen[str(uid)] = true
			ordered.append(str(uid))
	return {"ok": true, "uids": ordered}
