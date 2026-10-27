extends RefCounted
## Detached v0.031 catalog/layout adapter for EquipmentCondition.
## Pure dictionary adapter; preloads only EquipmentCondition and MountLayout.
## No Refit, Damage, Battle, Harbor, or Campaign preloads.

const Core = preload("res://scripts/equipment_condition.gd")
const Layout = preload("res://scripts/mount_layout.gd")

const CONTEXT_KEYS: Array = ["base", "loadout", "catalog", "identity", "knownUids"]
const LOADOUT_KEYS: Array = ["weapons", "engine", "armor"]
const CATALOG_FAMILIES: Array = ["weapons", "engines", "armor"]
const MOUNT_LOCATIONS: Array = ["mount0", "mount1", "mount2", "mount3"]
const PUMP_TYPE_ID: String = "hull_pumps"

# Canonical public snapshot projection/construction only; numeric rollouts stay out.
static var _runtime_profile043_enabled: bool = false
static var _runtime_profile043_counts: Dictionary = {"fullSnapshotCalls":0,"fullSnapshotRefreshes":0,"fullSnapshotRefusals":0,"fullSnapshotUs":0}

static func set_runtime_profile043(enabled: bool) -> void:
	_runtime_profile043_enabled = enabled

static func reset_runtime_profile043() -> void:
	for key in _runtime_profile043_counts: _runtime_profile043_counts[key] = 0

static func runtime_profile043() -> Dictionary:
	var result: Dictionary = _runtime_profile043_counts.duplicate(true)
	result.enabled = _runtime_profile043_enabled
	return result

static func _runtime_profile043_snapshot_finished(started: int, refreshed: bool) -> void:
	var elapsed: int = Time.get_ticks_usec() - started
	_runtime_profile043_counts.fullSnapshotCalls += 1
	_runtime_profile043_counts.fullSnapshotUs += elapsed
	if refreshed: _runtime_profile043_counts.fullSnapshotRefreshes += 1
	else: _runtime_profile043_counts.fullSnapshotRefusals += 1

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func _validate_catalog(catalog) -> Dictionary:
	if not catalog is Dictionary or not Core._keys_only(catalog, CATALOG_FAMILIES):
		return _fail("Equipment catalog is malformed.")
	for family in CATALOG_FAMILIES:
		if not catalog.has(family) or not catalog[family] is Dictionary or catalog[family].is_empty():
			return _fail("Equipment catalog is missing " + str(family) + ".")
	if not catalog.weapons.has("stock_primary") or not catalog.engines.has("stock_engine") or not catalog.armor.has("stock_armor"):
		return _fail("Equipment catalog is missing required stock types.")
	var family_by_type: Dictionary = {}
	for family in CATALOG_FAMILIES:
		var group: Dictionary = catalog[family]
		for raw_id in group.keys():
			if not raw_id is String:
				return _fail("Equipment catalog has a non-string type id.")
			var type_id: String = str(raw_id)
			var entry = group[raw_id]
			if not entry is Dictionary:
				return _fail("Equipment catalog entry must be a dictionary.")
			if type_id.is_empty():
				if family != "weapons":
					return _fail("Only weapons may define an empty slot entry.")
				continue
			if not Core._token(type_id) or type_id == PUMP_TYPE_ID:
				return _fail("Equipment catalog has an invalid type id.")
			if family_by_type.has(type_id):
				return _fail("Equipment catalog has a duplicate type id across families.")
			if not Core._whole_in(entry.get("size"), 1.0, 3.0) or not Core._whole_in(entry.get("op", entry.get("points", 0)), 0.0, 36.0):
				return _fail("Equipment catalog entry has invalid size or fitting points.")
			family_by_type[type_id] = family
	return {"ok": true, "familyByType": family_by_type}

static func _validate_base(base, boat: Dictionary) -> Dictionary:
	if not base is Dictionary:
		return _fail("Base hull specification must be a dictionary.")
	if not Core._token(base.get("id")):
		return _fail("Base hull id is malformed.")
	var hull_type: String = str(base.id)
	if not Core._number(base.get("size")) or float(base.size) < 8.0 or float(base.size) > 48.0:
		return _fail("Base hull size is outside valid bounds.")
	if base.has("tier") and not Core._whole_in(base.tier, 1.0, 4.0):
		return _fail("Base hull tier is invalid.")
	var has_pumps: bool = false
	if base.has("pumps"):
		if not Core._number(base.pumps) or float(base.pumps) < 0.0:
			return _fail("Base hull pump rating must be a finite nonnegative number.")
		has_pumps = float(base.pumps) > 0.0
	if base.has("hardpoints") and (not base.hardpoints is Array or base.hardpoints.size() > Core.MAX_MOUNTS):
		return _fail("Base hull exceeds the hardpoint bound.")
	var points: Array = Layout.hardpoints(base)
	if points.is_empty() or points.size() > Core.MAX_MOUNTS:
		return _fail("Hull hardpoints are outside the 1..4 bound.")
	if boat.has("type") and (not boat.type is String or (not str(boat.type).is_empty() and str(boat.type) != hull_type)):
		return _fail("Boat hull type does not match the base hull.")
	if boat.has("baseSpec"):
		if not boat.baseSpec is Dictionary:
			return _fail("Boat baseSpec is malformed.")
		if boat.baseSpec.has("id") and str(boat.baseSpec.id) != hull_type:
			return _fail("Boat baseSpec id does not match the base hull.")
	if boat.has("spec") and not boat.spec is Dictionary:
		return _fail("Boat spec is malformed.")
	return {
		"ok": true,
		"hullType": hull_type,
		"points": points,
		"mountCount": points.size(),
		"hullTier": Layout.mount_tier(base),
		"fittingBudget": Layout.fitting_budget(base),
		"hasPumps": has_pumps
	}

static func _validate_identity(identity, hull_type: String, boat: Dictionary) -> Dictionary:
	if not Core._identity(identity):
		return _fail("Caller must supply a valid stable hull identity.")
	var id_str: String = str(identity)
	if id_str == hull_type or id_str == "boat":
		return _fail("Item identity cannot default to a generic hull type id.")
	if boat.has("type") and id_str == str(boat.type):
		return _fail("Item identity cannot default to the boat type.")
	if boat.get("spec") is Dictionary and id_str == str(boat.spec.get("id", "")):
		return _fail("Item identity cannot default to spec.id.")
	if boat.get("baseSpec") is Dictionary and id_str == str(boat.baseSpec.get("id", "")):
		return _fail("Item identity cannot default to baseSpec.id.")
	if boat.has("id") and id_str == str(boat.id) and (str(boat.get("type", boat.id)) == str(boat.id) or str(boat.id) == hull_type):
		return _fail("Item identity cannot default to a generic boat id.")
	return {"ok": true, "identity": id_str}

static func _same_loadout(a, b: Dictionary) -> bool:
	if not a is Dictionary or not Core._keys_only(a, LOADOUT_KEYS):
		return false
	for key in LOADOUT_KEYS:
		if not a.has(key):
			return false
	if not a.weapons is Array or a.weapons.size() != b.weapons.size():
		return false
	for i in range(b.weapons.size()):
		if not a.weapons[i] is String or str(a.weapons[i]) != str(b.weapons[i]):
			return false
	return a.engine is String and a.armor is String and str(a.engine) == str(b.engine) and str(a.armor) == str(b.armor)

static func _validate_loadout(loadout, catalog: Dictionary, hull_info: Dictionary, boat: Dictionary) -> Dictionary:
	if not loadout is Dictionary or not Core._keys_only(loadout, LOADOUT_KEYS):
		return _fail("Loadout must be a normalized dictionary with weapons, engine, and armor.")
	for key in LOADOUT_KEYS:
		if not loadout.has(key):
			return _fail("Loadout is missing " + str(key) + ".")
	var weapons = loadout.get("weapons")
	var engine_id = loadout.get("engine")
	var armor_id = loadout.get("armor")
	if not weapons is Array or not engine_id is String or not armor_id is String:
		return _fail("Loadout requires a weapons array, engine string, and armor string.")
	var points: Array = hull_info.points
	if weapons.size() != points.size():
		return _fail("Loadout weapon slots do not match this hull's hardpoints.")
	var clean_weapons: Array = []
	var used_op: int = 0
	for i in range(points.size()):
		var raw_weapon = weapons[i]
		if not raw_weapon is String or not catalog.weapons.has(raw_weapon):
			return _fail("Loadout references an unknown weapon module.")
		var weapon_id: String = str(raw_weapon)
		if not weapon_id.is_empty():
			var mod: Dictionary = catalog.weapons[weapon_id]
			if (weapon_id == "stock_primary" and i != 0) or int(mod.size) > int(points[i].size):
				return _fail("Loadout weapon does not fit hardpoint mount%d." % i)
			used_op += int(mod.get("op", mod.get("points", 0)))
		clean_weapons.append(weapon_id)
	if not catalog.engines.has(engine_id):
		return _fail("Loadout references an unknown engine module.")
	var engine_mod: Dictionary = catalog.engines[engine_id]
	if int(engine_mod.size) > int(hull_info.hullTier):
		return _fail("Loadout engine is too large for this hull.")
	used_op += int(engine_mod.get("op", engine_mod.get("points", 0)))
	if not catalog.armor.has(armor_id):
		return _fail("Loadout references an unknown armor module.")
	var armor_mod: Dictionary = catalog.armor[armor_id]
	if int(armor_mod.size) > int(hull_info.hullTier):
		return _fail("Loadout armor is too large for this hull.")
	used_op += int(armor_mod.get("op", armor_mod.get("points", 0)))
	if used_op > int(hull_info.fittingBudget):
		return _fail("Loadout exceeds this hull's fitting point budget.")
	var clean: Dictionary = {"weapons": clean_weapons, "engine": str(engine_id), "armor": str(armor_id)}
	if boat.has("loadout") and not _same_loadout(boat.loadout, clean):
		return _fail("Boat loadout does not match the supplied normalized loadout.")
	return {"ok": true, "loadout": clean, "usedPoints": used_op}

static func _parse_legacy_locker(boat: Dictionary, family_by_type: Dictionary, hull_type: String) -> Dictionary:
	if not boat.has("refitLocker"):
		return {"ok": true, "descriptors": [], "counts": {}}
	var value = boat.get("refitLocker")
	if not (value is Dictionary or value is Array):
		return _fail("Refit locker must be a dictionary or array of module counts.")
	var descriptors: Array = []
	var counts: Dictionary = {}
	var total: int = 0
	if value is Dictionary:
		if value.size() > Core.MAX_LOCKER:
			return _fail("Refit locker exceeds the 256-part bound.")
		var keys: Array = value.keys()
		for raw_key in keys:
			if not raw_key is String or not family_by_type.has(str(raw_key)):
				return _fail("Refit locker contains an unknown module id.")
		keys.sort()
		for key in keys:
			var type_id: String = str(key)
			var raw_count = value[key]
			if not Core._whole_in(raw_count, 0.0, float(Core.MAX_LOCKER)):
				return _fail("Refit locker has an invalid module count.")
			var count: int = int(raw_count)
			total += count
			if total > Core.MAX_LOCKER:
				return _fail("Refit locker exceeds the 256-part bound.")
			if count > 0:
				counts[type_id] = int(counts.get(type_id, 0)) + count
				var family: String = str(family_by_type[type_id])
				for _i in range(count):
					descriptors.append({
						"family": family,
						"typeId": type_id,
						"originHullType": hull_type,
						"location": "locker",
						"hp": 1.0
					})
	else:
		var arr: Array = value
		if arr.size() > Core.MAX_LOCKER:
			return _fail("Refit locker exceeds the 256-part bound.")
		for entry in arr:
			var type_id = entry
			var raw_count = 1
			if entry is Dictionary:
				if not Core._keys_only(entry, ["id", "count"]) or not entry.has("id"):
					return _fail("Refit locker entry has an unknown or missing field.")
				type_id = entry.get("id")
				raw_count = entry.get("count", 1)
			if not type_id is String or not family_by_type.has(str(type_id)):
				return _fail("Refit locker contains an unknown module id.")
			if not Core._whole_in(raw_count, 0.0, float(Core.MAX_LOCKER)):
				return _fail("Refit locker has an invalid module count.")
			var count: int = int(raw_count)
			total += count
			if total > Core.MAX_LOCKER:
				return _fail("Refit locker exceeds the 256-part bound.")
			if count > 0:
				var clean_id: String = str(type_id)
				counts[clean_id] = int(counts.get(clean_id, 0)) + count
				var family: String = str(family_by_type[clean_id])
				for _i in range(count):
					descriptors.append({
						"family": family,
						"typeId": clean_id,
						"originHullType": hull_type,
						"location": "locker",
						"hp": 1.0
					})
	return {"ok": true, "descriptors": descriptors, "counts": counts}

static func _validate_condition_catalog(condition: Dictionary, catalog: Dictionary, family_by_type: Dictionary, hull_info: Dictionary) -> Dictionary:
	var pump_count: int = 0
	for uid in condition.items.keys():
		var item: Dictionary = condition.items[uid]
		var family: String = str(item.family)
		var type_id: String = str(item.typeId)
		var location: String = str(item.location)
		if family == "pumps":
			if not bool(hull_info.hasPumps):
				return _fail("Pump-free hull cannot carry integral pumps.")
			if type_id != PUMP_TYPE_ID or location != "pumps" or str(item.originHullType) != str(hull_info.hullType):
				return _fail("Integral pumps record does not match this hull.")
			pump_count += 1
		else:
			if not family_by_type.has(type_id) or str(family_by_type[type_id]) != family:
				return _fail("Equipment item type does not match the catalog family.")
			if location.begins_with("mount"):
				var mount_idx: int = int(location.substr(5, 1))
				if mount_idx < 0 or mount_idx >= hull_info.points.size():
					return _fail("Installed weapon is on a nonexistent hardpoint.")
				var w_mod: Dictionary = catalog.weapons[type_id]
				if (type_id == "stock_primary" and mount_idx != 0) or int(w_mod.size) > int(hull_info.points[mount_idx].size):
					return _fail("Installed weapon does not fit hardpoint " + location + ".")
			elif location == "engine":
				var e_mod: Dictionary = catalog.engines[type_id]
				if int(e_mod.size) > int(hull_info.hullTier):
					return _fail("Installed engine is too large for this hull.")
			elif location == "armor":
				var a_mod: Dictionary = catalog.armor[type_id]
				if int(a_mod.size) > int(hull_info.hullTier):
					return _fail("Installed armor is too large for this hull.")
	if bool(hull_info.hasPumps) and pump_count != 1:
		return _fail("Integral pumps record is missing and cannot regenerate.")
	if not bool(hull_info.hasPumps) and pump_count != 0:
		return _fail("Pump-free hull cannot carry integral pumps.")
	return {"ok": true}

static func initialize(boat: Dictionary, context: Dictionary) -> Dictionary:
	if not boat is Dictionary or not context is Dictionary:
		return _fail("Initialize requires a boat dictionary and a context dictionary.")
	if not Core._keys_only(context, CONTEXT_KEYS):
		return _fail("Initialize context has an unknown field.")
	for req in ["base", "loadout", "catalog", "identity"]:
		if not context.has(req):
			return _fail("Initialize context is missing " + str(req) + ".")
	if Core._foreign(boat):
		return _fail("Unrecognized condition metadata was left untouched.")
	var cat_check: Dictionary = _validate_catalog(context.get("catalog"))
	if not cat_check.ok:
		return cat_check
	var hull_info: Dictionary = _validate_base(context.get("base"), boat)
	if not hull_info.ok:
		return hull_info
	var hull_type: String = str(hull_info.hullType)
	var id_check: Dictionary = _validate_identity(context.get("identity"), hull_type, boat)
	if not id_check.ok:
		return id_check
	var birth_identity: String = str(id_check.identity)
	var fit_check: Dictionary = _validate_loadout(context.get("loadout"), context.catalog, hull_info, boat)
	if not fit_check.ok:
		return fit_check
	var clean_loadout: Dictionary = fit_check.loadout
	var locker_check: Dictionary = _parse_legacy_locker(boat, cat_check.familyByType, hull_type)
	if not locker_check.ok:
		return locker_check
	var known_uids = context.get("knownUids", [])
	var known_check: Dictionary = Core._known_set(known_uids)
	if not known_check.ok:
		return known_check
	if boat.has("moduleCondition"):
		var probe_existing: Dictionary = boat.duplicate(true)
		var validate_req: Dictionary = {
			"identity": birth_identity,
			"hullType": hull_type,
			"mountCount": int(hull_info.mountCount),
			"knownUids": known_uids,
			"installed": [],
			"locker": [],
			"engineScalar": 1.0,
			"loadout": clean_loadout
		}
		var checked_existing: Dictionary = Core.legacy_seed(probe_existing, validate_req)
		if not checked_existing.ok:
			return checked_existing
		var cat_existing: Dictionary = _validate_condition_catalog(probe_existing.moduleCondition, context.catalog, cat_check.familyByType, hull_info)
		if not cat_existing.ok:
			return cat_existing
		return checked_existing
	if boat.has("engine") and not Core._unit(boat.get("engine")):
		return _fail("The legacy engine scalar is not a finite condition.")
	var installed: Array = []
	for i in range(int(hull_info.mountCount)):
		var weapon_id: String = str(clean_loadout.weapons[i])
		if not weapon_id.is_empty():
			installed.append({
				"family": "weapons",
				"typeId": weapon_id,
				"originHullType": hull_type,
				"location": "mount%d" % i,
				"hp": 1.0
			})
	if not str(clean_loadout.engine).is_empty():
		installed.append({
			"family": "engines",
			"typeId": str(clean_loadout.engine),
			"originHullType": hull_type,
			"location": "engine"
		})
	if not str(clean_loadout.armor).is_empty():
		installed.append({
			"family": "armor",
			"typeId": str(clean_loadout.armor),
			"originHullType": hull_type,
			"location": "armor",
			"hp": 1.0
		})
	if bool(hull_info.hasPumps):
		installed.append({
			"family": "pumps",
			"typeId": PUMP_TYPE_ID,
			"originHullType": hull_type,
			"location": "pumps",
			"hp": 1.0
		})
	var probe: Dictionary = boat.duplicate(true)
	var seed_req: Dictionary = {
		"identity": birth_identity,
		"hullType": hull_type,
		"mountCount": int(hull_info.mountCount),
		"knownUids": known_uids,
		"installed": installed,
		"locker": locker_check.descriptors,
		"engineScalar": float(boat.get("engine", 1.0)) if boat.has("engine") else 1.0,
		"loadout": clean_loadout
	}
	var seeded: Dictionary = Core.legacy_seed(probe, seed_req)
	if not seeded.ok:
		return seeded
	var cat_seeded: Dictionary = _validate_condition_catalog(probe.moduleCondition, context.catalog, cat_check.familyByType, hull_info)
	if not cat_seeded.ok:
		return cat_seeded
	var published: Dictionary = publish(probe)
	if not published.ok:
		return published
	boat.moduleCondition = probe.moduleCondition
	boat.engine = probe.engine
	boat.refitLocker = probe.refitLocker
	return seeded

static func _tick_records_exact(condition: Dictionary, proof: Dictionary) -> Dictionary:
	# Private to one synchronous Damage.tick_ship call. Native equality is an
	# early-out only: bytes also distinguish StringName/String and int/float.
	# Never retain a refusal or admit a changed condition without Core._records.
	if is_same(proof.get("condition"), condition) and condition == proof.get("value"):
		if var_to_bytes(condition) == proof.get("bytes"):
			return proof.records
	var records: Dictionary = Core._records(condition)
	proof.clear()
	if records.ok:
		proof.condition = condition
		proof.value = condition.duplicate(true)
		proof.bytes = var_to_bytes(condition)
		records.locations.make_read_only()
		records.make_read_only()
		proof.records = records
	return records

static func absorb_legacy_damage(boat: Dictionary) -> Dictionary:
	return _absorb_legacy_damage_with(boat, Core._records)

static func _absorb_legacy_damage_with(boat: Dictionary, validate: Callable) -> Dictionary:
	if not boat is Dictionary:
		return _fail("Boat must be a dictionary.")
	if Core._foreign(boat):
		return _fail("Unrecognized condition metadata was left untouched.")
	if not boat.has("moduleCondition") or not boat.moduleCondition is Dictionary:
		return _fail("Equipment condition is not initialized.")
	if not boat.has("engine"):
		return _fail("The legacy engine scalar is missing.")
	return Core._note_engine_scalar_with(boat.moduleCondition, boat.get("engine"), validate)

static func publish(boat: Dictionary) -> Dictionary:
	return _publish_with(boat, Core._records)

static func _publish_with(boat: Dictionary, validate: Callable) -> Dictionary:
	if not boat is Dictionary:
		return _fail("Boat must be a dictionary.")
	if Core._foreign(boat):
		return _fail("Unrecognized condition metadata was left untouched.")
	if not boat.has("moduleCondition") or not boat.moduleCondition is Dictionary:
		return _fail("Equipment condition is not initialized.")
	var records: Dictionary = validate.call(boat.moduleCondition)
	if not records.ok:
		return records
	var projected: Dictionary = Core._publish_fields_from_records(boat.moduleCondition, records)
	return _publish_projection(boat, projected)

static func _publish_numeric(boat: Dictionary) -> Dictionary:
	var projected: Dictionary = Core._project_publish_fields_numeric(boat.moduleCondition)
	if not projected.ok:
		return projected
	return _publish_projection(boat, projected)

static func _publish_projection(boat: Dictionary, projected: Dictionary) -> Dictionary:
	var raw_engine_hp: float = float(projected.engineHp) if bool(projected.hasEngine) else 0.0
	var locker_counts: Dictionary = projected.refitLocker.duplicate(true)
	boat.engine = raw_engine_hp
	boat.refitLocker = locker_counts
	return {
		"ok": true,
		"hasEngine": bool(projected.hasEngine),
		"engine": raw_engine_hp,
		"engineHp": raw_engine_hp,
		"refitLocker": locker_counts.duplicate(true)
	}

static func _factor_for(item: Dictionary) -> float:
	if item.is_empty() or str(item.get("status", "disabled")) == "disabled":
		return 0.0
	return clampf(float(item.get("hp", 0.0)), 0.0, 1.0)

static func snapshot(boat: Dictionary) -> Dictionary:
	if not boat is Dictionary:
		return _fail("Boat must be a dictionary.")
	if Core._foreign(boat):
		return _fail("Unrecognized condition metadata was left untouched.")
	if not boat.has("moduleCondition"):
		if boat.has("engine") and not Core._unit(boat.get("engine")):
			return _fail("The legacy engine scalar is not a finite condition.")
		var empty_weapons: Dictionary = {}
		var empty_factors: Dictionary = {
			"engineHp": 0.0,
			"engineFactor": 0.0,
			"pumpFactor": 0.0,
			"armorFactor": 0.0,
			"weaponFactors": empty_weapons
		}
		return {
			"ok": true,
			"needsInitialize": true,
			"installed": {},
			"installedItems": [],
			"factors": empty_factors,
			"engineHp": 0.0,
			"engineFactor": 0.0,
			"pumpFactor": 0.0,
			"armorFactor": 0.0,
			"weaponFactors": {},
			"repairPriority": "auto",
			"juryCap": Core.JURY_CAP
		}
	if not boat.moduleCondition is Dictionary:
		return _fail("Existing equipment condition is corrupt and was left untouched.")
	var profile_started: int = Time.get_ticks_usec() if _runtime_profile043_enabled else 0
	var projected: Dictionary = Core.project(boat.moduleCondition)
	if not projected.ok:
		if _runtime_profile043_enabled: _runtime_profile043_snapshot_finished(profile_started,false)
		return projected
	var result: Dictionary = _snapshot_from_projection(boat, projected)
	if _runtime_profile043_enabled: _runtime_profile043_snapshot_finished(profile_started,true)
	return result

static func _snapshot_numeric(boat: Dictionary) -> Dictionary:
	var projected: Dictionary = Core._project_numeric(boat.moduleCondition)
	if not projected.ok:
		return projected
	return _snapshot_from_projection(boat, projected)

static func _snapshot_from_projection(boat: Dictionary, projected: Dictionary) -> Dictionary:
	var by_location: Dictionary = {}
	var items_list: Array = []
	for item in projected.installed:
		var loc: String = str(item.location)
		by_location[loc] = item.duplicate(true)
		items_list.append(item.duplicate(true))
	var engine_item: Dictionary = by_location.get("engine", {})
	var pump_item: Dictionary = by_location.get("pumps", {})
	var armor_item: Dictionary = by_location.get("armor", {})
	var engine_hp: float = float(engine_item.hp) if not engine_item.is_empty() else 0.0
	var engine_factor: float = _factor_for(engine_item)
	var pump_factor: float = _factor_for(pump_item)
	var armor_factor: float = _factor_for(armor_item)
	var weapon_factors: Dictionary = {}
	for loc in MOUNT_LOCATIONS:
		if by_location.has(loc):
			weapon_factors[loc] = _factor_for(by_location[loc])
	var factors: Dictionary = {
		"engineHp": engine_hp,
		"engineFactor": engine_factor,
		"pumpFactor": pump_factor,
		"armorFactor": armor_factor,
		"weaponFactors": weapon_factors.duplicate(true)
	}
	return {
		"ok": true,
		"needsInitialize": false,
		"birthNamespace": str(boat.moduleCondition.birthNamespace),
		"nextItemSeq": int(boat.moduleCondition.nextItemSeq),
		"repairPriority": str(boat.moduleCondition.repairPriority),
		"juryCap": Core.JURY_CAP,
		"installed": by_location,
		"installedItems": items_list,
		"factors": factors,
		"engineHp": engine_hp,
		"engineFactor": engine_factor,
		"pumpFactor": pump_factor,
		"armorFactor": armor_factor,
		"weaponFactors": weapon_factors.duplicate(true)
	}

static func _rollout_status_fields(boat: Dictionary) -> Dictionary:
	# Private readout for the owned numeric rollout. Same refusal object as _snapshot_numeric.
	# Installed values are new dictionaries. Factor calls use the live winner, which does not leave.
	var records: Dictionary = Core._records_numeric(boat.moduleCondition)
	if not records.ok:
		return records
	var _birth_namespace: String = str(boat.moduleCondition.birthNamespace)
	var _next_item_seq: int = int(boat.moduleCondition.nextItemSeq)
	var priority: String = str(boat.moduleCondition.repairPriority)
	var rows: Array = []
	for key in Core._uid_list(boat.moduleCondition):
		var item: Dictionary = boat.moduleCondition.items[key]
		if str(item.location) == "locker":
			continue
		rows.append(item)
	rows.sort_custom(func(a, b): return Core._location_rank(str(a.location)) < Core._location_rank(str(b.location)))
	var installed: Dictionary = {}
	var live: Dictionary = {}
	for item in rows:
		var loc: String = str(item.location)
		installed[loc] = {"family": str(item.get("family", "")), "hp": float(item.get("hp", 1.0))}
		live[loc] = item
	var engine_item: Dictionary = live.get("engine", {})
	var pump_item: Dictionary = live.get("pumps", {})
	var armor_item: Dictionary = live.get("armor", {})
	var engine_hp: float = float(engine_item.hp) if not engine_item.is_empty() else 0.0
	var weapon_factors: Dictionary = {}
	for loc in MOUNT_LOCATIONS:
		if live.has(loc):
			weapon_factors[loc] = _factor_for(live[loc])
	return {
		"ok": true,
		"needsInitialize": false,
		"repairPriority": priority,
		"installed": installed,
		"engineHp": engine_hp,
		"engineFactor": _factor_for(engine_item),
		"pumpFactor": _factor_for(pump_item),
		"armorFactor": _factor_for(armor_item),
		"weaponFactors": weapon_factors
	}

static func _absorb_legacy_numeric(boat: Dictionary) -> Dictionary:
	return Core._note_engine_scalar_numeric(boat.moduleCondition, boat.get("engine"))
