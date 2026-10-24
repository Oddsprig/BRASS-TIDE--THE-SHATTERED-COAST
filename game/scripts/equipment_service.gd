extends RefCounted
## v0.031 paid harbor service quotes and atomic installed equipment restoration.
## Restores canonical installed equipment in place via EquipmentCondition.restore_installed_paid
## and projects compatibility fields via EquipmentRecords.publish only inside accepted paid transactions.

const Core = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Refit = preload("res://scripts/refit.gd")
const Construction = preload("res://scripts/construction.gd")
const Goods = preload("res://scripts/goods.gd")
const Economy = preload("res://scripts/economy.gd")
const Money = preload("res://scripts/money.gd")
const Damage = preload("res://scripts/damage.gd")
const Politics = preload("res://scripts/politics.gd")

const EPS: float = 0.0001
const MAX_COINS: int = 9007199254740991
const REPAIR_MAT_RATE: float = 0.35
const REPAIR_KIT_RATE: float = 0.65
const REPAIR_LABOR_RATE: float = 0.55
const DISABLED_SURCHARGE: float = 0.15
const SERVICE_GOODS: Array = ["iron", "copper", "timber"]
const PORT_PURSES: Array = ["cash", "householdPurse", "expertPurse", "governmentPurse"]

class DetachedCampaignView extends RefCounted:
	var state: Dictionary = {}
	var data: Dictionary = {}
	var _port: Dictionary = {}

	func _init(state_copy: Dictionary, data_copy: Dictionary, port_copy: Dictionary) -> void:
		state = state_copy
		data = data_copy
		_port = port_copy

	func current_port() -> Dictionary:
		return _port

	func fail(message: String) -> Dictionary:
		return {"ok": false, "message": message}

	func ok(message: String) -> Dictionary:
		return {"ok": true, "message": message}

static func _fail_quote(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"message": message,
		"cost": 0,
		"material": 0.0,
		"own": 0.0,
		"purchase": 0.0,
		"ordinary": 0,
		"expert": 0,
		"materials": 0,
		"fee": 0,
		"hullKits": 0.0,
		"equipmentKits": 0.0,
		"kitPurchaseCost": 0,
		"equipmentMaterials": {},
		"equipmentMaterialPrices": {},
		"equipmentMaterialCost": 0,
		"hullOrdinaryDays": 0.0,
		"hullExpertDays": 0.0,
		"equipmentOrdinaryDays": 0.0,
		"equipmentExpertDays": 0.0,
		"ordinaryDays": 0.0,
		"expertDays": 0.0,
		"workerDays": 0.0,
		"equipmentDeficits": {},
		"equipmentCount": 0,
		"disabledCount": 0
	}

static func _fail_action(core, message: String) -> Dictionary:
	if core != null and core.has_method("fail"):
		var res: Dictionary = core.fail(message)
		if not res.has("error"):
			res["error"] = message
		return res
	return {"ok": false, "message": message, "error": message}

static func _ok_action(core, message: String, extra: Dictionary = {}) -> Dictionary:
	var res: Dictionary = {"ok": true, "message": message}
	if core != null and core.has_method("ok"):
		res = core.ok(message)
	for k in extra.keys():
		res[k] = extra[k]
	return res

static func _is_finite_number(value) -> bool:
	return (value is float or value is int) and not (value is bool) and is_finite(float(value))

static func _is_whole_coin(value) -> bool:
	if value is bool:
		return false
	if value is int:
		return value >= 0 and value <= MAX_COINS
	if value is float:
		return is_finite(value) and value >= 0.0 and value <= float(MAX_COINS) and floor(value) == value
	return false

static func _has_same_dict(items: Array, candidate: Dictionary) -> bool:
	for existing in items:
		if is_same(existing, candidate):
			return true
	return false

static func _stored_harbor_label(core, port_id: String) -> String:
	var clean_id: String = port_id.strip_edges()
	if core != null and core.has_method("port"):
		var resolved: Dictionary = core.port(clean_id)
		if resolved is Dictionary and not str(resolved.get("name", "")).strip_edges().is_empty():
			return str(resolved.get("name", ""))
	if core != null and ("state" in core) and (core.state is Dictionary) and (core.state.get("ports") is Array):
		for candidate in core.state.ports:
			if candidate is Dictionary and str(candidate.get("id", "")) == clean_id:
				var candidate_name: String = str(candidate.get("name", "")).strip_edges()
				if not candidate_name.is_empty():
					return candidate_name
	return clean_id if not clean_id.is_empty() else "another harbor"

static func _resolve_hull(core, hull_id: String, fallback: Dictionary = {}) -> Dictionary:
	var clean_id: String = hull_id.strip_edges()
	if clean_id.is_empty():
		return {}
	if core != null and core.has_method("hull"):
		var found: Dictionary = core.hull(clean_id)
		if found is Dictionary and not found.is_empty() and str(found.get("id", "")) == clean_id:
			return found
	if fallback is Dictionary and not fallback.is_empty() and str(fallback.get("id", "")) == clean_id:
		return fallback
	return {}

static func _resolve_base_spec(core, boat: Dictionary) -> Dictionary:
	var base_spec: Dictionary = {}
	if boat.get("baseSpec") is Dictionary and not boat.baseSpec.is_empty():
		base_spec = boat.baseSpec
	var hull_type: String = str(boat.get("type", base_spec.get("id", ""))).strip_edges()
	var resolved: Dictionary = _resolve_hull(core, hull_type, base_spec)
	if not resolved.is_empty():
		return resolved
	if not base_spec.is_empty() and not str(base_spec.get("id", "")).strip_edges().is_empty():
		if hull_type.is_empty() or hull_type == str(base_spec.get("id", "")).strip_edges():
			return base_spec
	return {}

static func _collect_other_fleet_uids(core, target_boat: Dictionary) -> Dictionary:
	var distinct_owners: Array = []
	var other_conditions: Array = []
	var seen_boat_uids: Dictionary = {}
	var seen_birth_namespaces: Dictionary = {}
	var target_uid: String = str(target_boat.get("uid", "")).strip_edges() if (target_boat.get("uid") is String) else ""
	if not target_uid.is_empty():
		seen_boat_uids[target_uid] = true
	if target_boat.get("moduleCondition") is Dictionary and (target_boat.moduleCondition.get("birthNamespace") is String):
		var target_ns: String = str(target_boat.moduleCondition.get("birthNamespace", "")).strip_edges()
		if not target_ns.is_empty():
			seen_birth_namespaces[target_ns] = true
	if core == null or not ("state" in core) or not (core.state is Dictionary):
		return {"ok": true, "knownUids": []}
	var state: Dictionary = core.state
	var lists: Array = []
	if state.has("fleet"):
		if not (state.get("fleet") is Array):
			return {"ok": false, "error": "Campaign fleet must be an array."}
		lists.append(state.fleet)
	if state.has("boardingPrizes"):
		if not (state.get("boardingPrizes") is Array):
			return {"ok": false, "error": "Campaign boardingPrizes must be an array."}
		lists.append(state.boardingPrizes)
	if state.has("fleetOwners"):
		if not (state.get("fleetOwners") is Array):
			return {"ok": false, "error": "Campaign fleetOwners must be an array."}
		for owner in state.fleetOwners:
			if not (owner is Dictionary):
				return {"ok": false, "error": "Each campaign fleetOwner must be a dictionary."}
			if owner.has("boats"):
				if not (owner.get("boats") is Array):
					return {"ok": false, "error": "Fleet owner boats must be an array."}
				lists.append(owner.boats)
	for group in lists:
		for other in group:
			if not (other is Dictionary):
				return {"ok": false, "error": "Another hull in campaign state is not a dictionary."}
			# Keep target excluded and count an aliased same hull once across roster lists.
			if is_same(other, target_boat) or _has_same_dict(distinct_owners, other):
				continue
			distinct_owners.append(other)
			if other.has("uid") and not (other.get("uid") is String):
				return {"ok": false, "error": "Another hull in campaign state has a non-string uid."}
			var other_uid: String = str(other.get("uid", "")).strip_edges()
			if not other_uid.is_empty():
				if seen_boat_uids.has(other_uid):
					return {"ok": false, "error": "Two distinct hulls share the same boat uid."}
				seen_boat_uids[other_uid] = true
			if Core._foreign(other):
				return {"ok": false, "error": "Another hull in campaign state carries foreign condition metadata."}
			if not other.has("moduleCondition"):
				continue
			if not (other.get("moduleCondition") is Dictionary):
				return {"ok": false, "error": "Another hull in campaign state has a corrupt equipment condition record."}
			if (target_boat.get("moduleCondition") is Dictionary and is_same(other.moduleCondition, target_boat.moduleCondition)) or _has_same_dict(other_conditions, other.moduleCondition):
				return {"ok": false, "error": "Two distinct hulls share the same equipment condition dictionary."}
			var other_ns_raw = other.moduleCondition.get("birthNamespace")
			if not (other_ns_raw is String) or str(other_ns_raw).strip_edges().is_empty():
				return {"ok": false, "error": "Another hull in campaign state has a malformed birthNamespace."}
			var other_ns: String = str(other_ns_raw).strip_edges()
			if seen_birth_namespaces.has(other_ns):
				return {"ok": false, "error": "Two distinct hulls share the same birthNamespace."}
			seen_birth_namespaces[other_ns] = true
			other_conditions.append(other.moduleCondition)
	var collected: Dictionary = Core.collect_item_uids(other_conditions)
	if not collected.get("ok", false):
		return {"ok": false, "error": str(collected.get("error", "Duplicate equipment itemUid across campaign hulls."))}
	return {"ok": true, "knownUids": collected.get("uids", [])}

static func _validate_hull_scalars(boat: Dictionary) -> String:
	if not _is_finite_number(boat.get("maxHp")) or float(boat.get("maxHp", 0.0)) <= 0.0:
		return "Boat maxHp must be a finite positive number."
	if not _is_finite_number(boat.get("hp")) or float(boat.get("hp", -1.0)) < 0.0 or float(boat.get("hp", 0.0)) > float(boat.get("maxHp", 0.0)) + EPS:
		return "Boat hp must be a finite nonnegative number within maxHp."
	for field in ["water", "fire", "wounded", "supplies"]:
		if boat.has(field):
			if not _is_finite_number(boat.get(field)) or float(boat.get(field, 0.0)) < 0.0:
				return "Boat %s must be a finite nonnegative number." % field
	if boat.has("engine"):
		if not Core._unit(boat.get("engine")):
			return "The legacy engine scalar is not a finite condition."
	if boat.has("breaches"):
		if not (boat.get("breaches") is Array):
			return "Boat breaches must be an array."
		for b in boat.breaches:
			if not (b is Dictionary) or not _is_finite_number(b.get("area")) or float(b.get("area", -1.0)) < 0.0:
				return "Each hull breach must have a finite nonnegative area."
	return ""

static func inspect_service_owner(core, boat: Dictionary) -> Dictionary:
	if not (boat is Dictionary) or boat.is_empty():
		return {"ok": false, "error": "Boat must be a non-empty dictionary."}
	if Core._foreign(boat):
		return {"ok": false, "error": "Unrecognized condition metadata was left untouched."}
	var scalar_err: String = _validate_hull_scalars(boat)
	if not scalar_err.is_empty():
		return {"ok": false, "error": scalar_err}
	var base: Dictionary = _resolve_base_spec(core, boat)
	if base.is_empty() or str(base.get("id", "")).strip_edges().is_empty():
		return {"ok": false, "error": "Base hull specification is unknown."}
	if base.has("pumps") and (not _is_finite_number(base.get("pumps")) or float(base.get("pumps", 0.0)) < 0.0):
		return {"ok": false, "error": "Base hull pump rating must be a finite nonnegative number."}
	if boat.has("loadout") and not (boat.get("loadout") is Dictionary):
		return {"ok": false, "error": "Boat loadout must be a dictionary."}
	var raw_loadout: Dictionary = boat.get("loadout", Refit.defaults(base))
	var normalized: Dictionary = Refit.normalize(base, raw_loadout)
	if not normalized.get("ok", false):
		return {"ok": false, "error": str(normalized.get("message", "Boat loadout is invalid for this hull."))}
	var loadout: Dictionary = normalized.loadout
	var catalog: Dictionary = Refit.catalog()
	var uid_scan: Dictionary = _collect_other_fleet_uids(core, boat)
	if not uid_scan.ok:
		return uid_scan
	var known_uids: Array = uid_scan.knownUids

	var probe: Dictionary = boat.duplicate(true)
	probe["loadout"] = loadout
	var had_canonical: bool = probe.has("moduleCondition")
	var identity: String = ""
	if had_canonical:
		if not (probe.get("moduleCondition") is Dictionary):
			return {"ok": false, "error": "Existing equipment condition is corrupt and was left untouched."}
		if not (probe.moduleCondition.get("birthNamespace") is String):
			return {"ok": false, "error": "Existing equipment birthNamespace is malformed."}
		# Existing canonical owners validate against their immutable birthNamespace even after capture reassigns boat.uid.
		identity = str(probe.moduleCondition.get("birthNamespace", "")).strip_edges()
	else:
		# Missing-legacy owners initialize only from a real stable boat.uid, never from hull type or generic fallbacks.
		if not (probe.get("uid") is String):
			return {"ok": false, "error": "A stable boat uid is required."}
		identity = str(probe.get("uid", "")).strip_edges()
	if identity.is_empty():
		return {"ok": false, "error": "A stable boat uid or birthNamespace is required."}

	var init_res: Dictionary = Records.initialize(probe, {
		"identity": identity,
		"base": base,
		"catalog": catalog,
		"loadout": loadout,
		"knownUids": known_uids.duplicate(true)
	})
	if not init_res.get("ok", false):
		return {"ok": false, "error": str(init_res.get("error", "Equipment condition failed validation."))}

	# Verify every item's originHullType resolves to an actual hull specification.
	var items: Dictionary = probe.moduleCondition.get("items", {})
	for item_uid in items.keys():
		var item: Dictionary = items[item_uid]
		var origin_type: String = str(item.get("originHullType", "")).strip_edges()
		var origin_spec: Dictionary = _resolve_hull(core, origin_type, base)
		if origin_spec.is_empty():
			return {"ok": false, "error": "Equipment item %s references unknown originHullType %s." % [str(item_uid), origin_type]}

	# Absorb only downward legacy scalar engine damage before quoting or servicing.
	var absorb_res: Dictionary = Records.absorb_legacy_damage(probe)
	if not absorb_res.get("ok", false):
		return {"ok": false, "error": str(absorb_res.get("error", "Failed to synchronize legacy engine condition."))}
	var pub_res: Dictionary = Records.publish(probe)
	if not pub_res.get("ok", false):
		return {"ok": false, "error": str(pub_res.get("error", "Failed to project canonical equipment condition."))}
	var snap: Dictionary = Records.snapshot(probe)
	if not snap.get("ok", false):
		return {"ok": false, "error": str(snap.get("error", "Equipment snapshot failed validation."))}

	return {
		"ok": true,
		"hadCanonical": had_canonical,
		"identity": identity,
		"base": base,
		"catalog": catalog,
		"loadout": loadout,
		"knownUids": known_uids,
		"probe": probe,
		"snapshot": snap
	}

static func item_restoration_bill(core, p: Dictionary, base: Dictionary, catalog: Dictionary, item: Dictionary) -> Dictionary:
	var family: String = str(item.get("family", ""))
	var type_id: String = str(item.get("typeId", ""))
	var location: String = str(item.get("location", ""))
	var origin_type: String = str(item.get("originHullType", base.get("id", "")))
	var origin_spec: Dictionary = _resolve_hull(core, origin_type, base)
	if origin_spec.is_empty():
		origin_spec = base
	var origin_bp: Dictionary = Construction.blueprint(origin_spec)
	var hp: float = clampf(float(item.get("hp", 1.0)), 0.0, 1.0)
	var status: String = str(item.get("status", "ok"))
	var deficit: float = maxf(0.0, 1.0 - hp)
	var is_disabled: bool = (status == "disabled") or (hp <= Core.DISABLE_HP + Core.EPS)
	if location == "locker" or (deficit <= Core.EPS and status == "ok"):
		return {
			"needsService": false,
			"itemUid": str(item.get("itemUid", "")),
			"location": location,
			"family": family,
			"typeId": type_id,
			"originHullType": origin_type,
			"hp": hp,
			"deficit": 0.0,
			"status": status,
			"disabled": false,
			"effort": 0.0,
			"kits": 0.0,
			"materials": {},
			"ordinaryDays": 0.0,
			"expertDays": 0.0
		}

	var base_effort: float = maxf(deficit, 0.05 if status != "ok" else 0.0)
	var effort: float = clampf(base_effort + (DISABLED_SURCHARGE if is_disabled else 0.0), 0.0, 1.0 + DISABLED_SURCHARGE)

	var gun_spec: Dictionary = Goods.ITEMS.get("guns", {})
	var gun_inputs: Dictionary = gun_spec.get("inputs", {})
	var eng_spec: Dictionary = Goods.ITEMS.get("engines", {})
	var eng_inputs: Dictionary = eng_spec.get("inputs", {})
	var eng_labor: Dictionary = eng_spec.get("labor", {})

	var new_iron: float = 0.0
	var new_copper: float = 0.0
	var new_timber: float = 0.0
	var new_kits: float = 0.0
	var new_ord_days: float = 0.0
	var new_exp_days: float = 0.0

	if family == "weapons":
		var cat_mod: Dictionary = catalog.get("weapons", {}).get(type_id, {})
		var mod_mats: Dictionary = cat_mod.get("materials", {})
		var f_bill: Dictionary = Refit.fitting_bill(p, origin_spec, "weapons", "", type_id, false)
		var gun_units: float = maxf(0.5, float(f_bill.get("materials", {}).get("guns", mod_mats.get("guns", 1.0))))
		new_iron = float(mod_mats.get("iron", 0.0)) + gun_units * (float(gun_inputs.get("iron", 4.0)) + (0.25 if type_id == "stock_primary" else 0.0))
		new_copper = float(mod_mats.get("copper", 0.0)) + gun_units * (float(gun_inputs.get("copper", 0.4)) + (0.12 if type_id == "stock_primary" else 0.0))
		new_timber = float(mod_mats.get("timber", 0.0)) + gun_units * (float(gun_inputs.get("timber", 0.1)) + (0.15 if type_id == "stock_primary" else 0.0))
		new_kits = maxf(0.5, float(mod_mats.get("supplies", 1.0)))
		new_ord_days = float(cat_mod.get("workerDays", 1.0)) + 1.80 * gun_units
		new_exp_days = float(cat_mod.get("expertDays", 0.0)) + 0.70 * gun_units
	elif family == "engines":
		var cat_mod: Dictionary = catalog.get("engines", {}).get(type_id, {})
		var mod_mats: Dictionary = cat_mod.get("materials", {})
		var f_bill: Dictionary = Refit.fitting_bill(p, origin_spec, "engines", "", type_id, false)
		var eng_units: float = maxf(0.5, float(f_bill.get("materials", {}).get("engines", mod_mats.get("engines", 1.0))))
		new_iron = float(mod_mats.get("iron", 0.0)) + eng_units * (float(eng_inputs.get("iron", 10.0)) + (0.35 if type_id == "stock_engine" else 0.0))
		new_copper = float(mod_mats.get("copper", 0.0)) + eng_units * (float(eng_inputs.get("copper", 2.0)) + (0.20 if type_id == "stock_engine" else 0.0))
		new_timber = float(mod_mats.get("timber", 0.0))
		new_kits = float(mod_mats.get("supplies", 1.0)) + eng_units * float(eng_inputs.get("supplies", 2.0))
		new_ord_days = float(cat_mod.get("workerDays", 1.0)) + 2.50 * eng_units
		new_exp_days = float(cat_mod.get("expertDays", 1.0)) + 1.10 * eng_units
	elif family == "armor":
		var cat_mod: Dictionary = catalog.get("armor", {}).get(type_id, {})
		var mod_mats: Dictionary = cat_mod.get("materials", {})
		var armor_val: float = maxf(0.0, float(origin_spec.get("armor", 2.0)))
		var area_m2: float = maxf(10.0, float(origin_bp.get("hullAreaM2", 55.0)))
		if type_id == "stock_armor":
			new_iron = maxf(float(mod_mats.get("iron", 2.0)), 0.014 * armor_val * pow(area_m2, 0.72))
			new_copper = float(mod_mats.get("copper", 0.0))
			new_timber = maxf(float(mod_mats.get("timber", 0.0)), 0.08 * armor_val)
			new_kits = float(mod_mats.get("supplies", 1.0)) + 0.08 * armor_val
			new_ord_days = float(cat_mod.get("workerDays", 1.0)) + 0.75 * armor_val
			new_exp_days = float(cat_mod.get("expertDays", 0.0)) + 0.26 * armor_val
		else:
			new_iron = float(mod_mats.get("iron", 0.0))
			new_copper = float(mod_mats.get("copper", 0.0))
			new_timber = float(mod_mats.get("timber", 0.0))
			new_kits = maxf(0.5, float(mod_mats.get("supplies", 1.0)))
			new_ord_days = float(cat_mod.get("workerDays", 1.0))
			new_exp_days = float(cat_mod.get("expertDays", 0.0))
	elif family == "pumps":
		# Grounded in Construction.blueprint integral pump machinery share (construction.gd:122,146,159,160,190) and Goods.ITEMS["engines"].
		var pumps_val: float = maxf(0.5, float(origin_spec.get("pumps", 2.4)))
		var pump_mach_units: float = 0.08 * (pumps_val / 2.4)
		new_iron = float(eng_inputs.get("iron", 10.0)) * pump_mach_units + 0.15 * pumps_val
		new_copper = 0.06 * pumps_val + float(eng_inputs.get("copper", 2.0)) * pump_mach_units
		new_timber = 0.0
		new_kits = 0.18 * pumps_val + float(eng_inputs.get("supplies", 2.0)) * pump_mach_units
		new_ord_days = 0.45 * pumps_val + 0.25 * float(eng_labor.get("mechanic", 2.2)) * pump_mach_units
		new_exp_days = maxf(0.25, 0.12 * pumps_val + float(eng_labor.get("engineer", 1.0)) * pump_mach_units)

	var item_mats: Dictionary = {}
	var iron_need: float = new_iron * REPAIR_MAT_RATE * effort
	var copper_need: float = new_copper * REPAIR_MAT_RATE * effort
	var timber_need: float = new_timber * REPAIR_MAT_RATE * effort
	if iron_need > EPS:
		item_mats["iron"] = iron_need
	if copper_need > EPS:
		item_mats["copper"] = copper_need
	if timber_need > EPS:
		item_mats["timber"] = timber_need

	var item_kits: float = new_kits * REPAIR_KIT_RATE * effort
	var item_ord_days: float = new_ord_days * REPAIR_LABOR_RATE * effort
	var item_exp_days: float = new_exp_days * REPAIR_LABOR_RATE * effort

	return {
		"needsService": true,
		"itemUid": str(item.get("itemUid", "")),
		"location": location,
		"family": family,
		"typeId": type_id,
		"originHullType": origin_type,
		"hp": hp,
		"deficit": deficit,
		"status": status,
		"disabled": is_disabled,
		"effort": effort,
		"kits": item_kits,
		"materials": item_mats,
		"ordinaryDays": item_ord_days,
		"expertDays": item_exp_days
	}

static func workforce_status(p: Dictionary) -> Dictionary:
	if not (p is Dictionary):
		return {"ok": false, "error": "Harbor dictionary is invalid."}
	var raw_workers = p.get("availableWorkers", p.get("workers", 0))
	var raw_specialists = p.get("availableSpecialists", p.get("specialistWorkers", p.get("specialists", 0)))
	if not _is_finite_number(raw_workers) or float(raw_workers) < 0.0:
		return {"ok": false, "error": "Harbor worker count is invalid."}
	if not _is_finite_number(raw_specialists) or float(raw_specialists) < 0.0:
		return {"ok": false, "error": "Harbor specialist count is invalid."}
	var dock_view: Dictionary = p.duplicate(true)
	if not dock_view.has("availableSpecialists") and dock_view.has("specialistWorkers"):
		dock_view["availableSpecialists"] = int(dock_view.get("specialistWorkers", 0))
	var wf: Dictionary = Refit._workforce(dock_view)
	wf["ok"] = true
	return wf

static func service_quote(core, boat: Dictionary, p: Dictionary) -> Dictionary:
	if not (p is Dictionary) or p.is_empty() or not (p.get("stocks") is Dictionary):
		return _fail_quote("Harbor service requires a valid port with commercial stocks.")
	var inspected: Dictionary = inspect_service_owner(core, boat)
	if not inspected.get("ok", false):
		return _fail_quote(str(inspected.get("error", "Boat equipment state is invalid.")))

	var probe: Dictionary = inspected.probe
	var base: Dictionary = inspected.base
	var catalog: Dictionary = inspected.catalog
	var snap: Dictionary = inspected.snapshot

	# Non-equipment hull service: hull HP, breaches, water, wounded, and fire.
	# Engine kits and engine specialist labor are NOT charged here; they come from the canonical installed engine record.
	var damage: float = maxf(0.0, float(probe.get("maxHp", 0.0)) - float(probe.get("hp", 0.0)))
	var area: float = Damage.sum_areas(probe)
	var hull_kits: float = damage * 0.20 + area * 0.018
	var hull_ordinary_days: float = damage * 0.08 + area * 0.002 + maxf(0.0, float(probe.get("water", 0.0))) * 0.0001
	var hull_expert_days: float = maxf(0.0, float(probe.get("wounded", 0.0))) + maxf(0.0, float(probe.get("fire", 0.0))) * 0.002

	var equipment_kits: float = 0.0
	var equipment_ordinary_days: float = 0.0
	var equipment_expert_days: float = 0.0
	var equipment_materials: Dictionary = {}
	var equipment_deficits: Dictionary = {}
	var equipment_count: int = 0
	var disabled_count: int = 0

	var installed_items: Array = snap.get("installedItems", [])
	for item in installed_items:
		if not (item is Dictionary):
			continue
		var loc: String = str(item.get("location", ""))
		if loc.is_empty() or loc == "locker":
			continue
		var bill: Dictionary = item_restoration_bill(core, p, base, catalog, item)
		if not bill.get("needsService", false):
			continue
		equipment_count += 1
		if bill.get("disabled", false):
			disabled_count += 1
		equipment_kits += float(bill.get("kits", 0.0))
		equipment_ordinary_days += float(bill.get("ordinaryDays", 0.0))
		equipment_expert_days += float(bill.get("expertDays", 0.0))
		var item_mats: Dictionary = bill.get("materials", {})
		for good in SERVICE_GOODS:
			var amount: float = float(item_mats.get(good, 0.0))
			if amount > EPS:
				equipment_materials[good] = float(equipment_materials.get(good, 0.0)) + amount
		equipment_deficits[loc] = {
			"itemUid": str(bill.get("itemUid", "")),
			"family": str(bill.get("family", "")),
			"typeId": str(bill.get("typeId", "")),
			"originHullType": str(bill.get("originHullType", "")),
			"hp": float(bill.get("hp", 1.0)),
			"deficit": float(bill.get("deficit", 0.0)),
			"status": str(bill.get("status", "ok")),
			"disabled": bool(bill.get("disabled", false)),
			"effort": float(bill.get("effort", 0.0)),
			"kits": float(bill.get("kits", 0.0)),
			"materials": item_mats.duplicate(true),
			"ordinaryDays": float(bill.get("ordinaryDays", 0.0)),
			"expertDays": float(bill.get("expertDays", 0.0))
		}

	var material: float = hull_kits + equipment_kits
	var own: float = minf(maxf(0.0, float(probe.get("supplies", 0.0))), material)
	var purchase: float = maxf(0.0, material - own)
	var kit_purchase_cost: int = ceili(purchase * float(Economy.price(p, "supplies")))

	var equipment_material_prices: Dictionary = {}
	var equipment_material_cost: int = 0
	for good in SERVICE_GOODS:
		if not equipment_materials.has(good):
			continue
		var unit_price: int = Economy.price(p, good)
		equipment_material_prices[good] = unit_price
		equipment_material_cost += ceili(float(equipment_materials[good]) * float(unit_price))

	var materials_coin_cost: int = kit_purchase_cost + equipment_material_cost
	var ordinary_days: float = hull_ordinary_days + equipment_ordinary_days
	var expert_days: float = hull_expert_days + equipment_expert_days
	var worker_days: float = ordinary_days + expert_days

	var ordinary_wage: int = ceili(ordinary_days * float(Goods.WAGES.shipwright))
	var expert_wage: int = ceili(hull_expert_days * float(Goods.WAGES.mechanic) + equipment_expert_days * float(Goods.WAGES.engineer))
	var fee: int = ceili(float(ordinary_wage + expert_wage) * 0.10)
	var total_cost: int = materials_coin_cost + ordinary_wage + expert_wage + fee

	return {
		"ok": true,
		"cost": total_cost,
		"material": material,
		"own": own,
		"purchase": purchase,
		"ordinary": ordinary_wage,
		"expert": expert_wage,
		"materials": materials_coin_cost,
		"fee": fee,
		"hullKits": hull_kits,
		"equipmentKits": equipment_kits,
		"kitPurchaseCost": kit_purchase_cost,
		"equipmentMaterials": equipment_materials,
		"equipmentMaterialPrices": equipment_material_prices,
		"equipmentMaterialCost": equipment_material_cost,
		"hullOrdinaryDays": hull_ordinary_days,
		"hullExpertDays": hull_expert_days,
		"equipmentOrdinaryDays": equipment_ordinary_days,
		"equipmentExpertDays": equipment_expert_days,
		"ordinaryDays": ordinary_days,
		"expertDays": expert_days,
		"workerDays": worker_days,
		"equipmentDeficits": equipment_deficits,
		"equipmentCount": equipment_count,
		"disabledCount": disabled_count
	}

static func _check_policy_detached(core, service_name: String) -> Dictionary:
	if core == null or not ("state" in core) or not (core.state is Dictionary):
		return {"ok": false, "message": "Campaign state is required for harbor service."}
	var p: Dictionary = core.current_port() if core.has_method("current_port") else {}
	if not (p is Dictionary) or p.is_empty():
		return {"ok": false, "message": "Stop at a harbor for this service."}
	if core.state.has("path") and not (core.state.get("path") is Array):
		return {"ok": false, "message": "Stop at a harbor for this service."}
	var state_copy: Dictionary = core.state.duplicate(true)
	if not (state_copy.get("path") is Array):
		state_copy["path"] = []
	var data_copy: Dictionary = {}
	if ("data" in core) and (core.data is Dictionary):
		data_copy = core.data.duplicate(true)
	var view := DetachedCampaignView.new(state_copy, data_copy, p.duplicate(true))
	return Politics.permit(view, service_name)

static func journal_error(state: Dictionary) -> String:
	var journal = state.get("moneyLog")
	if not journal is Array or journal.size() > 4096:
		return "Payment journal is unreadable; no payment was made."
	for entry in journal:
		if not entry is Dictionary or not entry.get("reason") is String or str(entry.reason).strip_edges().is_empty() or not _is_whole_coin(entry.get("cash")) or int(entry.cash) <= 0:
			return "Payment journal row is unreadable; no payment was made."
		# Exact historical summary from the original commission producer. This
		# is metadata only; no balance, receipt or transaction is rewritten.
		if entry.size() == 2 and entry.reason == "Commission: materials, wages in escrow, yard income and duty":
			continue
		if not entry.get("from") is String or str(entry.from).strip_edges().is_empty() or not entry.get("to") is String or str(entry.to).strip_edges().is_empty():
			return "Payment journal endpoints are unreadable; no payment was made."
	return ""

static func _validate_ledger_and_overflow(state: Dictionary, p: Dictionary, q: Dictionary) -> String:
	if not state.has("coinSupply"):
		return "World coinSupply is required before harbor service."
	var journal_problem: String = journal_error(state)
	if not journal_problem.is_empty():
		return journal_problem
	if not _is_whole_coin(state.get("coins")):
		return "Captain coin balance is not a valid finite integer."
	if state.has("crewPurse") and not _is_whole_coin(state.get("crewPurse")):
		return "Crew purse balance is not a valid finite integer."
	for purse in PORT_PURSES:
		if not _is_whole_coin(p.get(purse)):
			return "Harbor %s is not a valid finite integer." % purse
	if state.has("coinSupply"):
		if not _is_whole_coin(state.get("coinSupply")):
			return "World coinSupply is not a valid finite integer."
		if Money.total(state) != int(state.get("coinSupply", 0)):
			return "World coin ledger is out of balance before harbor service."
	for q_key in ["cost", "materials", "fee", "ordinary", "expert"]:
		if not _is_whole_coin(q.get(q_key)):
			return "Harbor quote %s is not a valid finite integer." % q_key
	var cost: int = int(q.get("cost", 0))
	var mat_receipt: int = int(q.get("materials", 0))
	var fee_receipt: int = int(q.get("fee", 0))
	if mat_receipt > MAX_COINS - fee_receipt:
		return "Harbor yard receipt would overflow maximum coin supply."
	var yard_receipt: int = mat_receipt + fee_receipt
	var ordinary_receipt: int = int(q.get("ordinary", 0))
	var expert_receipt: int = int(q.get("expert", 0))
	if cost < 0 or yard_receipt < 0 or ordinary_receipt < 0 or expert_receipt < 0:
		return "Negative harbor service charges are invalid."
	if yard_receipt + ordinary_receipt + expert_receipt != cost:
		return "Harbor service quote components do not sum to total coin cost."
	if int(p.get("cash", 0)) > MAX_COINS - yard_receipt:
		return "Harbor cash purse would overflow maximum coin supply."
	if int(p.get("householdPurse", 0)) > MAX_COINS - ordinary_receipt:
		return "Harbor householdPurse would overflow maximum coin supply."
	if int(p.get("expertPurse", 0)) > MAX_COINS - expert_receipt:
		return "Harbor expertPurse would overflow maximum coin supply."
	return ""

static func repair(core, uid: String) -> Dictionary:
	if core == null or not ("state" in core) or not (core.state is Dictionary):
		return _fail_action(core, "Campaign state is required for harbor repair.")
	var allowed: Dictionary = _check_policy_detached(core, "repair")
	if not allowed.get("ok", false):
		return _fail_action(core, str(allowed.get("message", "Harbor authorities refused drydock service.")))

	var boat: Dictionary = core.find_boat(uid) if core.has_method("find_boat") else {}
	var p: Dictionary = core.current_port() if core.has_method("current_port") else {}
	if boat.is_empty() or bool(boat.get("sunk", false)) or p.is_empty():
		return _fail_action(core, "Dock with an active boat to repair it.")
	if not (p.get("stocks") is Dictionary):
		return _fail_action(core, "Harbor commercial stocks are unavailable.")
	if boat.has("storedPort") and not (boat.get("storedPort") is String):
		return _fail_action(core, "Boat storedPort field is invalid.")
	var stored_port: String = str(boat.get("storedPort", "")).strip_edges()
	if not stored_port.is_empty() and stored_port != str(p.get("id", "")):
		return _fail_action(core, "%s is laid up at %s." % [str(boat.get("name", "Boat")), _stored_harbor_label(core, stored_port)])

	var inspected: Dictionary = inspect_service_owner(core, boat)
	if not inspected.get("ok", false):
		return _fail_action(core, str(inspected.get("error", "Equipment condition is invalid and cannot be serviced.")))

	var q: Dictionary = service_quote(core, boat, p)
	if not q.get("ok", false):
		return _fail_action(core, str(q.get("error", "Harbor could not prepare a valid service quote.")))

	var wf: Dictionary = workforce_status(p)
	if not wf.get("ok", false):
		return _fail_action(core, str(wf.get("error", "Harbor workforce records are invalid.")))
	var total_work: float = float(q.get("workerDays", 0.0))
	var ordinary_work: float = float(q.get("ordinaryDays", 0.0))
	var expert_work: float = float(q.get("expertDays", 0.0))
	var workers_total: float = float(wf.get("total", 0.0))
	var experts_total: float = float(wf.get("specialists", 0.0))
	if (total_work > EPS and int(floor(workers_total + EPS)) < 1) or float(wf.get("free", 0.0)) + EPS < total_work:
		return _fail_action(core, "This harbor doesn't have enough available shipwrights for drydock today.")
	if (expert_work > EPS and int(floor(experts_total + EPS)) < 1) or float(wf.get("freeExperts", 0.0)) + EPS < expert_work:
		return _fail_action(core, "This harbor lacks available mechanics and engineering specialists today.")

	var raw_supplies = p.stocks.get("supplies", -1.0)
	if not _is_finite_number(raw_supplies) or float(raw_supplies) < 0.0:
		return _fail_action(core, "Harbor repair kit stock is invalid.")
	if float(raw_supplies) + EPS < float(q.get("purchase", 0.0)):
		return _fail_action(core, "This harbor doesn't have enough repair kits in stock.")

	var eq_mats: Dictionary = q.get("equipmentMaterials", {})
	for good in SERVICE_GOODS:
		if not eq_mats.has(good):
			continue
		var need: float = float(eq_mats[good])
		var have_raw = p.stocks.get(good, -1.0)
		if not _is_finite_number(have_raw) or float(have_raw) < 0.0:
			return _fail_action(core, "Harbor %s stock is invalid." % good)
		if float(have_raw) + EPS < need:
			return _fail_action(core, "This harbor lacks enough %s in stock to restore damaged equipment." % good)

	var ledger_err: String = _validate_ledger_and_overflow(core.state, p, q)
	if not ledger_err.is_empty():
		return _fail_action(core, ledger_err)
	if int(core.state.get("coins", 0)) < int(q.get("cost", 0)):
		return _fail_action(core, "You don't have enough coins for drydock service.")

	# Stage transaction on detached copies before any live publication.
	var staged_boat: Dictionary = inspected.probe
	var restore_res: Dictionary = Core.restore_installed_paid(staged_boat.moduleCondition, {"confirmPaid": true})
	if not restore_res.get("ok", false):
		return _fail_action(core, str(restore_res.get("error", "Failed to restore installed equipment records.")))

	staged_boat["supplies"] = maxf(0.0, float(staged_boat.get("supplies", 0.0)) - float(q.get("own", 0.0)))
	staged_boat["hp"] = float(staged_boat.get("maxHp", staged_boat.get("hp", 0.0)))
	staged_boat["breaches"] = []
	staged_boat["water"] = 0.0
	staged_boat["fire"] = 0.0
	staged_boat["wounded"] = 0.0
	if bool(staged_boat.get("captureSecured", false)):
		staged_boat["supportOnly"] = false
		staged_boat["captureSecured"] = false
	staged_boat["needsHarborRepair"] = false
	staged_boat["towed"] = false
	staged_boat["towSpeedFactor"] = 1.0

	# Project canonical condition onto staged_boat.engine and staged_boat.refitLocker.
	# Do NOT call absorb_legacy_damage after paid restoration so old scalar values never re-damage the restored engine.
	var pub_res: Dictionary = Records.publish(staged_boat)
	if not pub_res.get("ok", false):
		return _fail_action(core, str(pub_res.get("error", "Failed to publish restored equipment state.")))
	var post_snap: Dictionary = Records.snapshot(staged_boat)
	if not post_snap.get("ok", false):
		return _fail_action(core, str(post_snap.get("error", "Restored equipment state failed post-service validation.")))

	var dock: Dictionary = p.duplicate(true)
	var wallet: Dictionary = {"coins": int(core.state.get("coins", 0))}
	var staged_log: Array = []
	if core.state.get("moneyLog") is Array:
		staged_log = core.state.moneyLog.duplicate(true)

	var before_pair_coins: int = int(wallet.coins) + Money.port_total(dock)
	var boat_label: String = str(boat.get("name", uid))
	if not Money.move(wallet, "coins", dock, "cash", int(q.get("materials", 0)) + int(q.get("fee", 0)), "Repair materials and yard fee", staged_log):
		return _fail_action(core, "Drydock material and fee transfer failed.")
	if not Money.move(wallet, "coins", dock, "householdPurse", int(q.get("ordinary", 0)), "Drydock shipwright wages", staged_log):
		return _fail_action(core, "Shipwright wage transfer failed.")
	if not Money.move(wallet, "coins", dock, "expertPurse", int(q.get("expert", 0)), "Mechanics and treatment specialists", staged_log):
		return _fail_action(core, "Specialist wage transfer failed.")
	if int(wallet.coins) + Money.port_total(dock) != before_pair_coins:
		return _fail_action(core, "Drydock coin conservation check failed.")

	dock.stocks["supplies"] = maxf(0.0, float(dock.stocks.get("supplies", 0.0)) - float(q.get("purchase", 0.0)))
	for good in SERVICE_GOODS:
		if not eq_mats.has(good):
			continue
		dock.stocks[good] = maxf(0.0, float(dock.stocks.get(good, 0.0)) - float(eq_mats[good]))

	dock["_yardWorkersUsed"] = float(wf.get("used", 0.0))
	dock["_yardSpecialistsUsed"] = float(wf.get("expertsUsed", 0.0))
	var ord_used_a: float = float(p.get("_yardOrdinaryUsed", 0.0)) if _is_finite_number(p.get("_yardOrdinaryUsed")) else 0.0
	var ord_used_b: float = float(p.get("yardOrdinaryReserved", 0.0)) if _is_finite_number(p.get("yardOrdinaryReserved")) else 0.0
	dock["_yardOrdinaryUsed"] = maxf(ord_used_a, ord_used_b)
	Construction._record_yard_reservation(dock, workers_total, experts_total, total_work, ordinary_work, expert_work)

	# Commit staged mutations in place while preserving live dictionary references.
	var live_stocks: Dictionary = p.stocks
	for stock_key in dock.stocks.keys():
		live_stocks[stock_key] = dock.stocks[stock_key]
	for dock_key in dock.keys():
		if dock_key == "stocks":
			continue
		p[dock_key] = dock[dock_key]

	var boat_commit_keys: Array = ["supplies", "hp", "breaches", "water", "fire", "wounded", "engine", "captureSecured", "supportOnly", "needsHarborRepair", "towed", "towSpeedFactor"]
	if bool(inspected.get("hadCanonical", false)):
		boat_commit_keys.append_array(["loadout", "moduleCondition", "refitLocker"])
	for boat_key in boat_commit_keys:
		if staged_boat.has(boat_key):
			boat[boat_key] = staged_boat[boat_key]

	core.state["coins"] = int(wallet.coins)
	if core.state.get("moneyLog") is Array:
		core.state.moneyLog.clear()
		core.state.moneyLog.append_array(staged_log)

	var restored_ids: Array = []
	var change_list: Array = restore_res.get("changes", [])
	for ch in change_list:
		if ch is Dictionary and ch.has("itemUid"):
			restored_ids.append(str(ch.itemUid))

	return _ok_action(core, "%s repaired for %d coins, paid to suppliers, shipwrights and specialists." % [boat_label, int(q.get("cost", 0))], {
		"cost": int(q.get("cost", 0)),
		"changes": change_list,
		"restoredIds": restored_ids,
		"quote": q
	})
