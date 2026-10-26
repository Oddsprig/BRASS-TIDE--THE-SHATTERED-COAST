extends RefCounted
## Private step-status cache and exact condition snapshot guard for EquipmentRollout.prefix.
## Preloads only EquipmentCondition. No cyclic preloads of Damage, EquipmentDamage, or EquipmentRecords.

const Core = preload("res://scripts/equipment_condition.gd")

const STATUS_KEYS: Array = [
	"step_status", "step_status_info", "step_status_snap", "step_status_has_policy",
	"step_status_policy_type", "step_status_policy", "step_status_spec", "step_status_spec_rf",
	"step_status_spec_pumps", "step_status_support_rf", "step_status_sunk", "step_status_crew",
	"step_status_wounded", "step_status_shore_crew", "step_status_crew_min", "step_status_crew_opt",
	"step_status_water", "step_status_capacity", "step_status_fire", "step_status_hp",
	"step_status_max_hp", "step_status_armor", "step_status_fuel_pos", "step_status_supplies_pos",
	"step_status_supplies"
]

const COND_KEYS: Array = [
	"step_status_cond_info", "step_status_cond", "step_status_cond_size", "step_status_items",
	"step_status_item_count", "step_status_priority", "step_status_has_sync", "step_status_sync",
	"step_status_seq_type", "step_status_ver_type", "step_status_cond_snap"
]

static func _num(value, fallback: float = 0.0) -> float:
	return float(value) if Core._number(value) else fallback

static func _is_string_value(value) -> bool:
	var value_type: int = typeof(value)
	return value_type == TYPE_STRING or value_type == TYPE_STRING_NAME

static func clear_status(ctx: Dictionary) -> void:
	for key in STATUS_KEYS:
		ctx.erase(key)

static func clear(ctx: Dictionary) -> void:
	for key in STATUS_KEYS:
		ctx.erase(key)
	for key in COND_KEYS:
		ctx.erase(key)
	# A clear is an invalidation. The open tick flag stays so a later compare in
	# the same closed invocation can prove equality again. The proof does not.
	ctx.erase("cond_eq_proof")

static func tick_scope_begin(ctx: Dictionary) -> void:
	if not (ctx is Dictionary):
		return
	ctx["tick_scope_open"] = true
	ctx.erase("cond_eq_proof")

static func tick_scope_end(ctx: Dictionary) -> void:
	if not (ctx is Dictionary):
		return
	ctx["tick_scope_open"] = false
	ctx.erase("cond_eq_proof")

static func _clone_condition_records(cond: Dictionary, ctx: Dictionary) -> Dictionary:
	if is_same(cond, ctx):
		return {}
	var items = cond.get("items")
	if not (items is Dictionary) or is_same(items, ctx) or is_same(items, cond):
		return {}
	var cond_prio = cond.get("repairPriority", "auto")
	if not _is_string_value(cond_prio) or not (String(cond_prio) in Core.PRIORITIES):
		return {}
	if cond.has("legacyEngineSynced") and not Core._unit(cond.get("legacyEngineSynced")):
		return {}
	var snap_items: Dictionary = {}
	for uid in items.keys():
		if not _is_string_value(uid):
			return {}
		var item = items[uid]
		if not (item is Dictionary) or is_same(item, ctx) or is_same(item, cond) or is_same(item, items):
			return {}
		var snap_item: Dictionary = {}
		for ik in item.keys():
			if not _is_string_value(ik):
				return {}
			var iv = item[ik]
			if not (_is_string_value(iv) or Core._number(iv) or iv is bool):
				return {}
			snap_item[ik] = iv
		snap_items[uid] = snap_item
	var cond_snap: Dictionary = {}
	for k in cond.keys():
		if not _is_string_value(k):
			return {}
		if String(k) == "items":
			cond_snap[k] = snap_items
		else:
			var v = cond[k]
			if not (_is_string_value(v) or Core._number(v) or v is bool):
				return {}
			cond_snap[k] = v
	return cond_snap

static func arm_info(boat: Dictionary, info: Dictionary, ctx: Dictionary) -> bool:
	clear(ctx)
	if not (boat is Dictionary) or not (ctx is Dictionary) or not is_same(boat, ctx.get("owner")):
		return false
	if not (info is Dictionary) or is_same(info, ctx):
		return false
	var snap = info.get("snapshot")
	var cond = boat.get("moduleCondition")
	if not (snap is Dictionary) or is_same(snap, ctx) or not bool(snap.get("ok", false)) or not (cond is Dictionary):
		return false
	var cond_snap: Dictionary = _clone_condition_records(cond, ctx)
	if cond_snap.is_empty():
		return false
	var prio_str: String = String(cond_snap.get("repairPriority", "auto"))
	if prio_str != String(snap.get("repairPriority", "auto")):
		return false
	var items: Dictionary = cond.get("items")
	var has_sync: bool = cond.has("legacyEngineSynced")
	ctx["step_status_cond_info"] = info
	ctx["step_status_cond"] = cond
	ctx["step_status_cond_size"] = cond.size()
	ctx["step_status_items"] = items
	ctx["step_status_item_count"] = items.size()
	ctx["step_status_priority"] = prio_str
	ctx["step_status_has_sync"] = has_sync
	ctx["step_status_sync"] = float(cond.get("legacyEngineSynced")) if has_sync else -1.0
	ctx["step_status_seq_type"] = typeof(cond.get("nextItemSeq"))
	ctx["step_status_ver_type"] = typeof(cond.get("version"))
	ctx["step_status_cond_snap"] = cond_snap
	return true

static func cond_valid(boat: Dictionary, ctx: Dictionary) -> bool:
	var equal: bool = _cond_equal(boat, ctx)
	if not equal and ctx is Dictionary:
		ctx.erase("cond_eq_proof")
	return equal

static func _cond_equal(boat: Dictionary, ctx: Dictionary) -> bool:
	if not (boat is Dictionary) or not (ctx is Dictionary) or not ctx.has("step_status_cond_snap"):
		return false
	var info = ctx.get("info")
	if not (info is Dictionary) or not is_same(info, ctx.get("step_status_cond_info")):
		return false
	var cond = boat.get("moduleCondition")
	if not (cond is Dictionary) or not is_same(cond, ctx.get("step_status_cond")) or cond.size() != int(ctx.get("step_status_cond_size", -1)):
		return false
	var items = cond.get("items")
	if not (items is Dictionary) or not is_same(items, ctx.get("step_status_items")) or items.size() != int(ctx.get("step_status_item_count", -1)):
		return false
	var cond_prio = cond.get("repairPriority", "auto")
	if not _is_string_value(cond_prio) or String(cond_prio) != String(ctx.get("step_status_priority", "")):
		return false
	var has_sync: bool = cond.has("legacyEngineSynced")
	if has_sync != bool(ctx.get("step_status_has_sync", false)):
		return false
	if has_sync and (not Core._unit(cond.get("legacyEngineSynced")) or float(cond.get("legacyEngineSynced")) != float(ctx.get("step_status_sync", -1.0))):
		return false
	if typeof(cond.get("nextItemSeq")) != int(ctx.get("step_status_seq_type", -1)) or typeof(cond.get("version")) != int(ctx.get("step_status_ver_type", -1)):
		return false
	# Owner, shape, types, priority, and scalar guards above always run.
	# The deep compare is the only step a live proof may skip, only in its
	# closed private prefix. Other callbacks never open this scope. The local
	# owned condition has no external writer; all internal writers invalidate first.
	if bool(ctx.get("tick_scope_open", false)) and bool(ctx.get("cond_eq_proof", false)):
		return true
	var cond_snap = ctx.get("step_status_cond_snap")
	var same: bool = (cond_snap is Dictionary) and cond == cond_snap
	if same and bool(ctx.get("tick_scope_open", false)):
		ctx["cond_eq_proof"] = true
	return same

static func valid(boat: Dictionary, info: Dictionary, ctx: Dictionary) -> bool:
	if not ctx.has("step_status") or not (info is Dictionary) or not is_same(info, ctx.get("info")) or not is_same(info, ctx.get("step_status_info")):
		return false
	var snap = info.get("snapshot")
	if not (snap is Dictionary) or not is_same(snap, ctx.get("step_status_snap")):
		return false
	var cached = ctx.get("step_status")
	if not (cached is Dictionary) or not bool(cached.get("equipmentOk", false)) or str(cached.get("equipmentMode", "")) != "canonical":
		return false
	var prio_str: String = String(ctx.get("step_status_priority", ""))
	if not (prio_str in Core.PRIORITIES) or prio_str != String(snap.get("repairPriority", "auto")):
		return false
	var has_policy: bool = boat.has("policy")
	if has_policy != bool(ctx.get("step_status_has_policy", false)):
		return false
	if (typeof(boat.get("policy")) if has_policy else TYPE_NIL) != int(ctx.get("step_status_policy_type", -1)):
		return false
	if (String(boat.get("policy", "balanced")) if has_policy else "balanced") != String(ctx.get("step_status_policy", "")):
		return false
	var spec_raw = boat.get("spec")
	if not is_same(spec_raw, ctx.get("step_status_spec")):
		return false
	var spec: Dictionary = spec_raw if spec_raw is Dictionary else {}
	if _num(spec.get("repairFactor", 1.0), 1.0) != float(ctx.get("step_status_spec_rf", 1.0)) or _num(spec.get("pumps")) != float(ctx.get("step_status_spec_pumps", 0.0)):
		return false
	if _num(boat.get("supportRepairFactor", 1.0), 1.0) != float(ctx.get("step_status_support_rf", 1.0)) or bool(boat.get("sunk", false)) != bool(ctx.get("step_status_sunk", false)):
		return false
	if _num(boat.get("crew")) != float(ctx.get("step_status_crew", 0.0)) or _num(boat.get("wounded")) != float(ctx.get("step_status_wounded", 0.0)) or _num(boat.get("shoreCrew", 0)) != float(ctx.get("step_status_shore_crew", 0.0)):
		return false
	if _num(boat.get("crewMin"), 2.0) != float(ctx.get("step_status_crew_min", 2.0)) or _num(boat.get("crewOptimal"), 5.0) != float(ctx.get("step_status_crew_opt", 5.0)):
		return false
	if _num(boat.get("water")) != float(ctx.get("step_status_water", 0.0)) or _num(boat.get("capacity"), 200.0) != float(ctx.get("step_status_capacity", 200.0)):
		return false
	if _num(boat.get("fire")) != float(ctx.get("step_status_fire", 0.0)) or _num(boat.get("hp")) != float(ctx.get("step_status_hp", 0.0)) or _num(boat.get("maxHp"), 100.0) != float(ctx.get("step_status_max_hp", 100.0)) or _num(boat.get("armor")) != float(ctx.get("step_status_armor", 0.0)):
		return false
	if (_num(boat.get("fuel")) > 0.0) != bool(ctx.get("step_status_fuel_pos", false)):
		return false
	var supplies_now: float = _num(boat.get("supplies"))
	return (supplies_now > 0.0) == bool(ctx.get("step_status_supplies_pos", false)) and supplies_now == float(ctx.get("step_status_supplies", 0.0))

static func arm(boat: Dictionary, info: Dictionary, status: Dictionary, ctx: Dictionary) -> void:
	if not (boat is Dictionary) or not (ctx is Dictionary) or not is_same(boat, ctx.get("owner")):
		clear_status(ctx)
		return
	if not (info is Dictionary) or not is_same(info, ctx.get("info")):
		clear_status(ctx)
		return
	if not ctx.has("step_status_cond_snap") or not is_same(info, ctx.get("step_status_cond_info")):
		if not arm_info(boat, info, ctx):
			return
	var snap = info.get("snapshot")
	var spec_raw = boat.get("spec")
	if not (snap is Dictionary) or not bool(snap.get("ok", false)) or not (status is Dictionary) or not bool(status.get("equipmentOk", false)) or str(status.get("equipmentMode", "")) != "canonical":
		clear_status(ctx)
		return
	var prio_str: String = String(ctx.get("step_status_priority", ""))
	if not (prio_str in Core.PRIORITIES) or prio_str != String(snap.get("repairPriority", "auto")) or is_same(status, ctx) or is_same(spec_raw, ctx) or is_same(info, ctx) or is_same(snap, ctx):
		clear_status(ctx)
		return
	if boat.has("policy") and not _is_string_value(boat.get("policy")):
		clear_status(ctx)
		return
	var spec: Dictionary = spec_raw if spec_raw is Dictionary else {}
	var has_policy: bool = boat.has("policy")
	var supplies_now: float = _num(boat.get("supplies"))
	ctx["step_status"] = status
	ctx["step_status_info"] = info
	ctx["step_status_snap"] = snap
	ctx["step_status_has_policy"] = has_policy
	ctx["step_status_policy_type"] = typeof(boat.get("policy")) if has_policy else TYPE_NIL
	ctx["step_status_policy"] = String(boat.get("policy", "balanced")) if has_policy else "balanced"
	ctx["step_status_spec"] = spec_raw
	ctx["step_status_spec_rf"] = _num(spec.get("repairFactor", 1.0), 1.0)
	ctx["step_status_spec_pumps"] = _num(spec.get("pumps"))
	ctx["step_status_support_rf"] = _num(boat.get("supportRepairFactor", 1.0), 1.0)
	ctx["step_status_sunk"] = bool(boat.get("sunk", false))
	ctx["step_status_crew"] = _num(boat.get("crew"))
	ctx["step_status_wounded"] = _num(boat.get("wounded"))
	ctx["step_status_shore_crew"] = _num(boat.get("shoreCrew", 0))
	ctx["step_status_crew_min"] = _num(boat.get("crewMin"), 2.0)
	ctx["step_status_crew_opt"] = _num(boat.get("crewOptimal"), 5.0)
	ctx["step_status_water"] = _num(boat.get("water"))
	ctx["step_status_capacity"] = _num(boat.get("capacity"), 200.0)
	ctx["step_status_fire"] = _num(boat.get("fire"))
	ctx["step_status_hp"] = _num(boat.get("hp"))
	ctx["step_status_max_hp"] = _num(boat.get("maxHp"), 100.0)
	ctx["step_status_armor"] = _num(boat.get("armor"))
	ctx["step_status_fuel_pos"] = _num(boat.get("fuel")) > 0.0
	ctx["step_status_supplies_pos"] = supplies_now > 0.0
	ctx["step_status_supplies"] = supplies_now
