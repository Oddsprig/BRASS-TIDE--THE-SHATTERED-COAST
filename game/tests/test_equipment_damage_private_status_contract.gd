extends SceneTree
## Supplemental derivative. Not original174.
## Does not replace tests/test_equipment_damage.gd and does not add to its checks.
## Source contract only until Root reviews and Sol runs it. No mirror formulas.
##
## Compares Damage._status_for_info of EquipmentDamage._numeric_info with
## EquipmentDamage._numeric_rollout_info, by var_to_bytes (float64 and key order).
## Each status call must leave the whole owned boat byte-identical.
## Repair compares Damage._tick_canonical_numeric, the switched callable, with
## _tick_canonical_with still bound to _numeric_info and the same numeric
## repair, publish, and absorb. The compared value is var_to_bytes of the full
## owned boat, so hp, water, fire, breaches, cooldown, supplies, condition,
## and key insertion order all count, plus var_to_bytes of the returned status.
## One eligible case must gain module hp and spend supplies on both paths.
## Those amounts are observed, not hardcoded.
## Raw snapshots are allowed to differ: the private readout omits installedItems,
## factors, uids, type ids, causes, and locker counts. The consumer status is the contract.
## var_to_bytes is called only after a walk finds no Object, Callable, Signal, or RID.

const Damage = preload("res://scripts/damage.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Core = preload("res://scripts/equipment_condition.gd")
const Refit = preload("res://scripts/refit.gd")

const FIT: Dictionary = {
	"weapons": ["stock_primary", "rapid_gun", "light_cannon", "fire_rocket"],
	"engine": "stock_engine",
	"armor": "stock_armor"
}
const LOCKER: Dictionary = {"rapid_gun": 2, "stock_engine": 1, "scout_plating": 1}
const REPAIR_DT: float = 0.5
const LIVE_CHANNELS: Array = ["hp", "water", "fire", "breaches", "cooldown", "supplies"]

var world: Dictionary = {}
var catalog: Dictionary = {}
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("private_status_contract: " + message)

func _context(base: Dictionary, loadout: Dictionary, identity: String) -> Dictionary:
	return {"base": base, "loadout": loadout, "catalog": catalog, "identity": identity, "knownUids": []}

func _item_at(condition: Dictionary, location: String) -> Dictionary:
	for uid in condition.items.keys():
		var item: Dictionary = condition.items[uid]
		if str(item.location) == location:
			return item
	return {}

func _bad_encoded(value, path: String) -> String:
	var kind: int = typeof(value)
	if kind == TYPE_OBJECT or kind == TYPE_CALLABLE or kind == TYPE_SIGNAL or kind == TYPE_RID:
		return path + " " + type_string(kind)
	if kind == TYPE_DICTIONARY:
		for key in value.keys():
			var key_bad: String = _bad_encoded(key, path + ".key")
			if not key_bad.is_empty():
				return key_bad
			var found: String = _bad_encoded(value[key], path + "." + str(key))
			if not found.is_empty():
				return found
	elif kind == TYPE_ARRAY:
		for i in value.size():
			var found: String = _bad_encoded(value[i], path + "[" + str(i) + "]")
			if not found.is_empty():
				return found
	return ""

func _bytes(label: String, value) -> Dictionary:
	var bad: String = _bad_encoded(value, label)
	if not bad.is_empty():
		check(false, label + " refused before var_to_bytes (" + bad + ")")
		return {"ok": false, "bytes": PackedByteArray()}
	return {"ok": true, "bytes": var_to_bytes(value)}

func _same_bytes(label: String, left, right) -> void:
	var a: Dictionary = _bytes(label + " A", left)
	var b: Dictionary = _bytes(label + " B", right)
	if a.ok and b.ok:
		check(a.bytes == b.bytes, label)

func _differ_bytes(label: String, left, right) -> void:
	var a: Dictionary = _bytes(label + " A", left)
	var b: Dictionary = _bytes(label + " B", right)
	if a.ok and b.ok:
		check(a.bytes != b.bytes, label)

func _fitted(identity: String, with_locker: bool) -> Dictionary:
	if not world.get("HULLS") is Array or world.HULLS.size() <= 23:
		check(false, identity + " world hull 23 is missing")
		return {}
	var base: Dictionary = world.HULLS[23].duplicate(true)
	var overrides: Dictionary = {}
	if with_locker:
		overrides.refitLocker = LOCKER.duplicate(true)
	var boat: Dictionary = Damage.create_ship(base, overrides)
	var norm: Dictionary = Refit.normalize(base, FIT)
	check(norm.ok, identity + " loadout normalizes")
	if not norm.ok:
		return {}
	boat.loadout = norm.loadout
	Refit.ensure(boat, base)
	boat.uid = identity
	var init_res: Dictionary = Records.initialize(boat, _context(base, boat.loadout, identity))
	check(init_res.ok, identity + " Records.initialize (" + str(init_res.get("error", "ok")) + ")")
	if not init_res.ok:
		return {}
	var numeric: Dictionary = Core._records_numeric(boat.moduleCondition)
	var full: Dictionary = Core._records(boat.moduleCondition)
	check(numeric.ok, identity + " reachable factory copy passes _records_numeric")
	check(full.ok, identity + " reachable factory copy passes _records")
	if not numeric.ok or not full.ok:
		return {}
	return boat

func _strike(boat: Dictionary, location: String, loss: float, cause: String) -> bool:
	var item: Dictionary = _item_at(boat.moduleCondition, location)
	if item.is_empty():
		check(false, location + " missing before " + cause)
		return false
	var struck: Dictionary = Core.apply_component_damage(boat.moduleCondition, {
		"itemUid": str(item.itemUid),
		"loss": loss,
		"cause": cause
	})
	check(struck.ok, cause + " (" + str(struck.get("error", "ok")) + ")")
	return struck.ok

func _status_from(boat: Dictionary, original: bool) -> Dictionary:
	var owned: Dictionary = boat.duplicate(true)
	var info: Dictionary = EquipmentDamage._numeric_info(owned) if original else EquipmentDamage._numeric_rollout_info(owned)
	return Damage._status_for_info(owned, info)

func _compare_status(label: String, boat: Dictionary) -> void:
	var left: Dictionary = boat.duplicate(true)
	var right: Dictionary = boat.duplicate(true)
	var left_before: Dictionary = _bytes(label + " original boat before status", left)
	var right_before: Dictionary = _bytes(label + " rollout boat before status", right)
	var original: Dictionary = Damage._status_for_info(left, EquipmentDamage._numeric_info(left))
	var rollout: Dictionary = Damage._status_for_info(right, EquipmentDamage._numeric_rollout_info(right))
	_same_bytes(label + " whole consumer status var_to_bytes", original, rollout)
	var left_after: Dictionary = _bytes(label + " original boat after status", left)
	var right_after: Dictionary = _bytes(label + " rollout boat after status", right)
	if left_before.ok and left_after.ok:
		check(left_before.bytes == left_after.bytes, label + " original status call leaves the whole boat unchanged")
	if right_before.ok and right_after.ok:
		check(right_before.bytes == right_after.bytes, label + " rollout status call leaves the whole boat unchanged")

func _tick(boat: Dictionary, wired: bool) -> Dictionary:
	var owned: Dictionary = boat.duplicate(true)
	var status: Dictionary = {}
	if wired:
		status = Damage._tick_canonical_numeric(owned, REPAIR_DT, {})
	else:
		status = Damage._tick_canonical_with(
			owned,
			REPAIR_DT,
			{},
			EquipmentDamage._numeric_info,
			EquipmentDamage._tick_repair_numeric_from_info,
			Records._publish_numeric,
			Records._absorb_legacy_numeric
		)
	return {"status": status, "boat": owned}

func _compare_repair(label: String, boat: Dictionary) -> Dictionary:
	for channel in LIVE_CHANNELS:
		check(boat.has(channel), label + " owned boat carries " + str(channel))
	var before_keys: Array = boat.keys()
	var wired: Dictionary = _tick(boat, true)
	var original: Dictionary = _tick(boat, false)
	_same_bytes(label + " full owned boat var_to_bytes", wired.boat, original.boat)
	_same_bytes(label + " post-repair status var_to_bytes", wired.status, original.status)
	check(wired.boat.keys() == original.boat.keys(), label + " both repairs keep the same key insertion order")
	check(wired.boat.keys() == before_keys and original.boat.keys() == before_keys, label + " repair inserts no boat key")
	return {"wired": wired, "original": original}

func _detached(label: String, boat: Dictionary) -> void:
	var owned: Dictionary = boat.duplicate(true)
	var info: Dictionary = EquipmentDamage._numeric_rollout_info(owned)
	check(bool(info.get("ok", false)) and str(info.get("mode", "")) == "canonical" and info.has("snapshot"), label + " rollout info is canonical")
	if not bool(info.get("ok", false)) or not info.get("snapshot") is Dictionary:
		return
	var snap: Dictionary = info.snapshot
	var installed: Dictionary = snap.get("installed", {})
	check(not installed.has("locker"), label + " installed readout has no locker row")
	var live_enc: Dictionary = _bytes(label + " live condition", owned.moduleCondition)
	for loc in installed.keys():
		var slim = installed[loc]
		check(slim is Dictionary, label + " " + str(loc) + " slim row is a new dictionary shape")
		if slim is Dictionary:
			for uid in owned.moduleCondition.items.keys():
				check(not is_same(slim, owned.moduleCondition.items[uid]), label + " " + str(loc) + " slim row is not a live item")
			slim.hp = -99.0
	if live_enc.ok:
		var after_live: Dictionary = _bytes(label + " live condition after slim edit", owned.moduleCondition)
		if after_live.ok:
			check(after_live.bytes == live_enc.bytes, label + " mutating slim rows leaves live items")
	var factors: Dictionary = snap.get("weaponFactors", {})
	for loc in factors.keys():
		check(typeof(factors[loc]) == TYPE_FLOAT, label + " " + str(loc) + " weapon factor is a float, not an item")
	var full: Dictionary = EquipmentDamage._numeric_info(boat.duplicate(true))
	check(bool(full.get("ok", false)) and full.get("snapshot") is Dictionary and full.snapshot.has("installedItems") and full.snapshot.has("factors"), label + " original _numeric_info still returns the full snapshot")
	check(snap.has("installed") and snap.has("repairPriority") and snap.has("engineHp") and snap.has("engineFactor") and snap.has("pumpFactor") and snap.has("armorFactor") and snap.has("weaponFactors"), label + " readout keeps the fields _status_from_info consumes")
	check(not snap.has("installedItems") and not snap.has("factors") and not snap.has("birthNamespace") and not snap.has("nextItemSeq"), label + " private readout drops the copies status does not consume")

func _public_entry(boat: Dictionary) -> void:
	var owned: Dictionary = boat.duplicate(true)
	var before: Dictionary = _bytes("public entry before", owned)
	var status: Dictionary = Damage.get_status(owned)
	var snap: Dictionary = Records.snapshot(owned)
	check(str(status.get("equipmentMode", "")) == "canonical" and bool(status.get("equipmentOk", false)), "public get_status stays canonical on a factory boat")
	check(bool(snap.get("ok", false)) and snap.has("installedItems"), "public Records.snapshot still carries installedItems")
	var after: Dictionary = _bytes("public entry after", owned)
	if before.ok and after.ok:
		check(before.bytes == after.bytes, "public status and snapshot leave the whole boat unchanged")
	var ticked: Dictionary = owned.duplicate(true)
	var public_tick: Dictionary = Damage.tick_ship(ticked, REPAIR_DT, {})
	check(str(public_tick.get("equipmentMode", "")) == "canonical", "public tick_ship stays on inspect_owner")

func _reachable() -> void:
	var normal: Dictionary = _fitted("psc-normal", false)
	if normal.is_empty():
		return
	_compare_status("reachable normal", normal)
	_compare_repair("reachable normal", normal)
	_detached("reachable normal", normal)
	_public_entry(normal)
	var normal_status: Dictionary = _status_from(normal, true)

	var engine: Dictionary = _fitted("psc-engine", false)
	if not engine.is_empty() and _strike(engine, "engine", 0.85, "Disabled engine"):
		_compare_status("reachable disabled engine", engine)
		_compare_repair("reachable disabled engine", engine)
		_detached("reachable disabled engine", engine)
		_differ_bytes("disabled engine changes the original consumer status", _status_from(engine, true), normal_status)

	var pumps: Dictionary = _fitted("psc-pumps", false)
	if not pumps.is_empty() and _strike(pumps, "pumps", 0.85, "Disabled pumps"):
		_compare_status("reachable pumps", pumps)
		_compare_repair("reachable pumps", pumps)
		_detached("reachable pumps", pumps)

	var armor: Dictionary = _fitted("psc-armor", false)
	if not armor.is_empty() and _strike(armor, "armor", 0.50, "Damaged armor"):
		_compare_status("reachable armor", armor)
		_compare_repair("reachable armor", armor)
		_detached("reachable armor", armor)

	var mount: Dictionary = _fitted("psc-mount", false)
	if not mount.is_empty() and _strike(mount, "mount0", 0.85, "Disabled mount0") and _strike(mount, "mount1", 0.40, "Damaged mount1"):
		_compare_status("reachable mounts", mount)
		_compare_repair("reachable mounts", mount)
		_detached("reachable mounts", mount)

	var at_cap: Dictionary = _fitted("psc-jury-cap", false)
	var below: Dictionary = _fitted("psc-jury-below", false)
	if not at_cap.is_empty() and not below.is_empty() and _strike(at_cap, "engine", 0.25, "Engine at jury cap") and _strike(below, "engine", 0.26, "Engine below jury cap"):
		_compare_status("reachable jury cap", at_cap)
		_compare_repair("reachable jury cap", at_cap)
		_compare_status("reachable jury below", below)
		_compare_repair("reachable jury below", below)
		_detached("reachable jury below", below)
		_differ_bytes("jury cap and below-cap engines differ through the original consumer", _status_from(at_cap, true), _status_from(below, true))

	var sunk: Dictionary = _fitted("psc-sunk", false)
	if not sunk.is_empty() and _strike(sunk, "engine", 0.85, "Engine before sunk"):
		sunk.sunk = true
		sunk.water = 30.0
		_compare_status("reachable sunk", sunk)
		_compare_repair("reachable sunk", sunk)
		_detached("reachable sunk", sunk)

	var locker: Dictionary = _fitted("psc-locker", true)
	if not locker.is_empty():
		var locker_item: Dictionary = {}
		for uid in locker.moduleCondition.items.keys():
			var item: Dictionary = locker.moduleCondition.items[uid]
			if str(item.location) == "locker":
				locker_item = item
				break
		check(not locker_item.is_empty(), "reachable locker factory stores a locker part")
		_compare_status("reachable locker", locker)
		_compare_repair("reachable locker", locker)
		_detached("reachable locker", locker)

func _eligible_module_repair() -> void:
	# Factory hull, real priority API, damage input only. No expected hp or supply total.
	var boat: Dictionary = _fitted("psc-eligible-engine", false)
	if boat.is_empty():
		return
	if not _strike(boat, "engine", 0.60, "Eligible engine"):
		return
	var priority: String = Damage.set_repair_priority(boat, "engine")
	check(priority == "engine" and str(boat.moduleCondition.repairPriority) == "engine", "eligible repair priority comes from Damage.set_repair_priority")
	var engine: Dictionary = _item_at(boat.moduleCondition, "engine")
	check(not engine.is_empty(), "eligible engine is installed")
	if engine.is_empty():
		return
	check(float(engine.hp) < Core.JURY_CAP and float(engine.hp) > Core.DISABLE_HP, "eligible engine is inside the damaged band below the jury cap")
	var able: float = maxf(0.0, float(boat.crew) - float(boat.wounded) - maxf(0.0, float(boat.get("shoreCrew", 0.0))))
	check(able > 0.0 and float(boat.supplies) > 0.0, "eligible factory boat has able crew and supplies")
	# Inputs so the full-boat compare covers channels the old store pick skipped.
	boat.water = 12.0
	boat.fire = 1.0
	boat.cooldown = 0.5
	boat.breaches.append({"area": 2.0})
	var before_hp: float = float(_item_at(boat.moduleCondition, "engine").hp)
	var before_supplies: float = float(boat.supplies)
	_compare_status("eligible engine priority", boat)
	var pair: Dictionary = _compare_repair("eligible engine priority", boat)
	_detached("eligible engine priority", boat)
	var wired_pack: Dictionary = pair.wired
	var original_pack: Dictionary = pair.original
	var wired_boat: Dictionary = wired_pack.boat
	var original_boat: Dictionary = original_pack.boat
	var wired_status: Dictionary = wired_pack.status
	var original_status: Dictionary = original_pack.status
	check(float(_item_at(wired_boat.moduleCondition, "engine").hp) > before_hp and float(_item_at(original_boat.moduleCondition, "engine").hp) > before_hp, "eligible engine priority gains module hp on both paths")
	check(float(wired_boat.supplies) < before_supplies and float(original_boat.supplies) < before_supplies, "eligible engine priority spends supplies on both paths")
	check(float(wired_status.get("repairedModuleHp", 0.0)) > 0.0 and float(original_status.get("repairedModuleHp", 0.0)) > 0.0, "eligible engine priority reports repaired module hp on both paths")
	check(float(wired_status.get("usedSupplies", 0.0)) > 0.0 and float(original_status.get("usedSupplies", 0.0)) > 0.0, "eligible engine priority reports used supplies on both paths")

func _guard_domain_duplicate() -> void:
	var boat: Dictionary = _fitted("psc-duplicate", false)
	if boat.is_empty():
		return
	var owned: Dictionary = boat.duplicate(true)
	var engine: Dictionary = _item_at(owned.moduleCondition, "engine")
	if engine.is_empty():
		check(false, "duplicate edge has no engine")
		return
	var twin: Dictionary = engine.duplicate(true)
	# Sorts before a minted it- uid, and is inserted last. Dict-order engineHp is the twin.
	# The UID-then-rank walk can keep the factory engine when equal ranks stay in order.
	# Pass condition is path equality, not a hard-coded winner. sort_custom stability is native.
	var twin_uid: String = "aaa-twin"
	twin.itemUid = twin_uid
	twin.hp = 0.40
	twin.status = Core._status_for(0.40, "ok")
	twin.cause = "" if twin.status == "ok" else "Second engine"
	owned.moduleCondition.items[twin_uid] = twin
	owned.moduleCondition.legacyEngineSynced = float(twin.hp)
	var numeric: Dictionary = Core._records_numeric(owned.moduleCondition)
	var full: Dictionary = Core._records(owned.moduleCondition)
	check(numeric.ok, "private guard-domain duplicate passes _records_numeric")
	check(not full.ok and str(full.get("error", "")) == "Two parts occupy one slot.", "private guard-domain duplicate is refused by full _records")
	if not numeric.ok:
		return
	_compare_status("private duplicate location", owned)
	_compare_repair("private duplicate location", owned)
	_detached("private duplicate location", owned)

func _numeric_refusal() -> void:
	var boat: Dictionary = _fitted("psc-refusal", false)
	if boat.is_empty():
		return
	var owned: Dictionary = boat.duplicate(true)
	var engine: Dictionary = _item_at(owned.moduleCondition, "engine")
	if engine.is_empty():
		check(false, "refusal edge has no engine")
		return
	engine.status = "disabled"
	owned.moduleCondition.nextItemSeq = "not-a-whole-number"
	var direct: Dictionary = Core._records_numeric(owned.moduleCondition)
	var readout: Dictionary = Records._rollout_status_fields(owned.duplicate(true))
	var original_info: Dictionary = EquipmentDamage._numeric_info(owned.duplicate(true))
	var rollout_info: Dictionary = EquipmentDamage._numeric_rollout_info(owned.duplicate(true))
	check(not direct.ok, "private refusal is _records_numeric, before nextItemSeq is read")
	_same_bytes("refusal readout returns that records object contents", direct, readout)
	check(not readout.has("installed") and not readout.has("engineHp") and not readout.has("weaponFactors"), "refusal readout has no status fields")
	check(not original_info.has("snapshot") and not rollout_info.has("snapshot"), "both invalid wrappers omit snapshot")
	check(str(original_info.get("mode", "")) == "invalid" and str(rollout_info.get("mode", "")) == "invalid", "both wrappers are invalid")
	_compare_status("private numeric refusal", owned)
	var untouched: Dictionary = _bytes("refusal setup", owned)
	_compare_repair("private numeric refusal", owned)
	var after: Dictionary = _bytes("refusal setup after", owned)
	if untouched.ok and after.ok:
		check(untouched.bytes == after.bytes, "refusal setup boat is not written by the later copies")

func _initialize() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	if not parsed is Dictionary:
		check(false, "world.json did not parse")
		_finish()
		return
	world = parsed
	catalog = Refit.catalog()
	_reachable()
	_eligible_module_repair()
	_guard_domain_duplicate()
	_numeric_refusal()
	_prefix_step_status_contract()
	_finish()

func _tick_prefix_pair(label: String, boat: Dictionary, dt: float = 0.1, options: Dictionary = {}) -> Dictionary:
	var wired_boat: Dictionary = boat.duplicate(true)
	var ref_boat: Dictionary = boat.duplicate(true)
	var ctx: Dictionary = {"owner": wired_boat, "valid": false}
	var prefix_info: Callable = func(b: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_info(b, ctx)
	var prefix_repair: Callable = func(b: Dictionary, h: float, cr: float, opts: Dictionary, inf: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_repair(b, h, cr, opts, inf, ctx)
	var prefix_publish: Callable = func(b: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_publish(b, ctx)
	var prefix_absorb: Callable = func(b: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_absorb(b, ctx)
	var prefix_step_status: Callable = func(b: Dictionary, inf: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_step_status(b, inf, ctx, Damage._status_for_info)
	var wired_status: Dictionary = Damage._tick_canonical_with(wired_boat, dt, options.duplicate(true), prefix_info, prefix_repair, prefix_publish, prefix_absorb, null, prefix_step_status)
	var ref_status: Dictionary = Damage._tick_canonical_with(ref_boat, dt, options.duplicate(true), EquipmentDamage._numeric_rollout_info, EquipmentDamage._tick_repair_rollout_from_info, Records._publish_numeric, Records._absorb_legacy_numeric)
	_same_bytes(label + " full owned boat var_to_bytes", wired_boat, ref_boat)
	_same_bytes(label + " post-tick status var_to_bytes", wired_status, ref_status)
	check(wired_boat.keys() == ref_boat.keys() and wired_boat.keys() == boat.keys(), label + " preserves exact boat key insertion order")
	check(_bad_encoded(ctx, label + " ctx").is_empty(), label + " ctx stores no Callables/Objects/Signals/RIDs")
	return {"wiredBoat": wired_boat, "refBoat": ref_boat, "wiredStatus": wired_status, "refStatus": ref_status, "ctx": ctx}

func _tick_armed_prefix_pair(label: String, boat: Dictionary, mutate_fn: Callable, expect_info_invalidated: bool, dt: float = 0.1, options: Dictionary = {}) -> Dictionary:
	var wired_boat: Dictionary = boat.duplicate(true)
	var ref_boat: Dictionary = boat.duplicate(true)
	var ctx: Dictionary = {"owner": wired_boat, "valid": false}
	var pre_info: Dictionary = EquipmentDamage._prefix_ctx_info(wired_boat, ctx)
	var pre_st: Dictionary = EquipmentDamage._prefix_ctx_step_status(wired_boat, pre_info, ctx, Damage._status_for_info)
	check(bool(ctx.get("valid", false)) and is_same(ctx.get("step_status"), pre_st) and ctx.has("step_status_cond_snap") and not ctx.has("step_status_cond_hash"), label + " pre-arms ctx with collision-free cond_snap")
	var pre_cond_snap: Dictionary = ctx.get("step_status_cond_snap", {})
	var pre_cond_bytes: Dictionary = _bytes(label + " pre-mutation cond_snap", pre_cond_snap)
	mutate_fn.call(wired_boat)
	mutate_fn.call(ref_boat)
	if pre_cond_bytes.ok:
		check(_bytes(label + " cond_snap after live mutation", pre_cond_snap).bytes == pre_cond_bytes.bytes, label + " cond_snap stays isolated from live mutation")
	if expect_info_invalidated:
		check(not EquipmentDamage._prefix_ctx_reuse_info(wired_boat, ctx), label + " invalidates cached info before reuse")
	check(not EquipmentDamage._prefix_ctx_step_status_valid(wired_boat, pre_info, ctx), label + " invalidates cached step_status before tick")
	var prefix_info: Callable = func(b: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_info(b, ctx)
	var prefix_repair: Callable = func(b: Dictionary, h: float, cr: float, opts: Dictionary, inf: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_repair(b, h, cr, opts, inf, ctx)
	var prefix_publish: Callable = func(b: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_publish(b, ctx)
	var prefix_absorb: Callable = func(b: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_absorb(b, ctx)
	var prefix_step_status: Callable = func(b: Dictionary, inf: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_step_status(b, inf, ctx, Damage._status_for_info)
	var wired_status: Dictionary = Damage._tick_canonical_with(wired_boat, dt, options.duplicate(true), prefix_info, prefix_repair, prefix_publish, prefix_absorb, null, prefix_step_status)
	var ref_status: Dictionary = Damage._tick_canonical_with(ref_boat, dt, options.duplicate(true), EquipmentDamage._numeric_rollout_info, EquipmentDamage._tick_repair_rollout_from_info, Records._publish_numeric, Records._absorb_legacy_numeric)
	_same_bytes(label + " full owned boat var_to_bytes", wired_boat, ref_boat)
	_same_bytes(label + " post-tick status var_to_bytes", wired_status, ref_status)
	check(wired_boat.keys() == ref_boat.keys(), label + " preserves exact boat key insertion order")
	check(_bad_encoded(ctx, label + " ctx").is_empty(), label + " ctx stores no Callables/Objects/Signals/RIDs")
	return {"wiredBoat": wired_boat, "refBoat": ref_boat, "wiredStatus": wired_status, "refStatus": ref_status, "ctx": ctx}

func _prefix_step_status_contract() -> void:
	var boat: Dictionary = _fitted("psc-step-status", true)
	if boat.is_empty():
		return
	boat.water = 18.0
	boat.fuel = 40.0
	boat.supplies = 12.0
	boat.vx = 14.0
	var ctx: Dictionary = {"owner": boat, "valid": false}
	var info1: Dictionary = EquipmentDamage._prefix_ctx_info(boat, ctx)
	var st1: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, info1, ctx, Damage._status_for_info)
	var st1_snap: Dictionary = _bytes("st1 initial snapshot", st1)
	check(bool(ctx.get("valid", false)) and ctx.has("step_status") and is_same(ctx.get("step_status"), st1), "step_status arms on valid canonical prefix_ctx")
	check(ctx.has("step_status_cond_snap") and not ctx.has("step_status_cond_hash"), "armed prefix_ctx stores collision-free cond_snap without hash key")
	var cond_snap1: Dictionary = ctx.get("step_status_cond_snap", {})
	check(not is_same(cond_snap1, boat.moduleCondition) and not is_same(cond_snap1.get("items"), boat.moduleCondition.get("items")), "cond_snap clones top-level condition and items dictionaries")
	for uid in boat.moduleCondition.items.keys():
		check(cond_snap1.get("items", {}).has(uid) and not is_same(cond_snap1.items[uid], boat.moduleCondition.items[uid]), "cond_snap clones item record " + str(uid))
	_same_bytes("armed cond_snap matches live moduleCondition", cond_snap1, boat.moduleCondition)
	check(_bad_encoded(ctx, "armed prefix_ctx").is_empty(), "armed prefix_ctx contains no Callables or Objects")
	_same_bytes("step_status initial matches Damage.get_status", st1, Damage.get_status(boat.duplicate(true)))
	_same_bytes("step_status initial matches _status_for_info(_numeric_rollout_info)", st1, Damage._status_for_info(boat.duplicate(true), EquipmentDamage._numeric_rollout_info(boat.duplicate(true))))

	# Positive fuel drain & pose/cooldown changes reuse cached step_status and cond_snap.
	boat.fuel = 12.5
	boat.x += 9.0
	boat.cooldown = 0.25
	var info2: Dictionary = EquipmentDamage._prefix_ctx_info(boat, ctx)
	var st2: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, info2, ctx, Damage._status_for_info)
	check(is_same(info2, info1) and is_same(st2, st1) and is_same(ctx.get("step_status_cond_snap"), cond_snap1), "positive fuel drain reuses cached info, step_status, and cond_snap")
	_same_bytes("positive fuel drain cached step_status matches fresh Damage.get_status", st2, Damage.get_status(boat.duplicate(true)))

	# 1. fuel0 transition: refreshes pump=0.0 immediately while keeping info and cond_snap cached without re-cloning.
	boat.fuel = 0.0
	var info_f0: Dictionary = EquipmentDamage._prefix_ctx_info(boat, ctx)
	var st_f0: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, info_f0, ctx, Damage._status_for_info)
	check(is_same(info_f0, info1) and not is_same(st_f0, st1) and is_same(ctx.get("step_status_cond_snap"), cond_snap1), "fuel0 transition reuses info and cond_snap without re-cloning while refreshing step_status")
	check(float(st1.get("pump", 0.0)) > 0.0 and float(st_f0.get("pump", -1.0)) == 0.0, "fuel0 transition drops pump to 0.0 without mutating prior cached st1")
	if st1_snap.ok:
		check(_bytes("st1 after fuel0", st1).bytes == st1_snap.bytes, "prior cached st1 remains byte-identical after fuel0 transition")
	_same_bytes("fuel0 step_status matches Damage.get_status", st_f0, Damage.get_status(boat.duplicate(true)))
	boat.fuel = 25.0
	var st_fpos: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, EquipmentDamage._prefix_ctx_info(boat, ctx), ctx, Damage._status_for_info)
	check(not is_same(st_fpos, st_f0) and float(st_fpos.get("pump", 0.0)) > 0.0 and is_same(ctx.get("step_status_cond_snap"), cond_snap1), "fuel positive restoration refreshes pump > 0.0 without re-cloning cond_snap")
	_same_bytes("fuel positive restoration matches Damage.get_status", st_fpos, Damage.get_status(boat.duplicate(true)))

	# 2. water transition.
	boat.water = 64.0
	var st_water: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, EquipmentDamage._prefix_ctx_info(boat, ctx), ctx, Damage._status_for_info)
	check(not is_same(st_water, st_fpos) and is_same(ctx.get("step_status_cond_snap"), cond_snap1), "water change refreshes cached step_status without re-cloning cond_snap")
	_same_bytes("water transition matches Damage.get_status", st_water, Damage.get_status(boat.duplicate(true)))

	# 3. crew/wounded transition.
	boat.wounded = 2.0
	boat.crew = maxf(float(boat.crewMin), float(boat.crew) - 1.0)
	var st_crew: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, EquipmentDamage._prefix_ctx_info(boat, ctx), ctx, Damage._status_for_info)
	check(not is_same(st_crew, st_water) and is_same(ctx.get("step_status_cond_snap"), cond_snap1), "crew/wounded transition refreshes cached step_status without re-cloning cond_snap")
	_same_bytes("crew transition matches Damage.get_status", st_crew, Damage.get_status(boat.duplicate(true)))

	# 4. policy transition.
	boat.policy = "bail"
	var st_pol: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, EquipmentDamage._prefix_ctx_info(boat, ctx), ctx, Damage._status_for_info)
	check(not is_same(st_pol, st_crew) and is_same(ctx.get("step_status_cond_snap"), cond_snap1), "policy transition refreshes cached step_status without re-cloning cond_snap")
	_same_bytes("policy transition matches Damage.get_status", st_pol, Damage.get_status(boat.duplicate(true)))

	# 5. wrong owner & invalid ctx fallback without mutating armed owner ctx.
	var other_boat: Dictionary = _fitted("psc-step-other", false)
	if not other_boat.is_empty() and _strike(other_boat, "engine", 0.85, "Other boat disabled engine") and Records.publish(other_boat).ok:
		var ctx_before_wrong: Dictionary = _bytes("ctx before wrong owner", ctx)
		var st_wrong: Dictionary = EquipmentDamage._prefix_ctx_step_status(other_boat, EquipmentDamage._numeric_rollout_info(other_boat), ctx, Damage._status_for_info)
		_same_bytes("wrong owner fallback matches Damage.get_status(other_boat)", st_wrong, Damage.get_status(other_boat.duplicate(true)))
		if ctx_before_wrong.ok:
			check(_bytes("ctx after wrong owner", ctx).bytes == ctx_before_wrong.bytes, "wrong owner call does not read or mutate bound ctx")
	var invalid_ctx: Dictionary = {"owner": null, "valid": false}
	var st_invalid_ctx: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, EquipmentDamage._numeric_rollout_info(boat), invalid_ctx, Damage._status_for_info)
	_same_bytes("unarmed/invalid ctx fallback matches Damage.get_status", st_invalid_ctx, Damage.get_status(boat.duplicate(true)))
	check(not invalid_ctx.has("step_status"), "invalid ctx does not cache step_status")

	# 6. engine scalar transition + multi-step tick absorption.
	boat.engine = 0.42
	var st_eng_drop: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, EquipmentDamage._prefix_ctx_info(boat, ctx), ctx, Damage._status_for_info)
	check(not bool(ctx.get("valid", true)) and not ctx.has("step_status") and not ctx.has("step_status_cond_snap"), "engine scalar mismatch clears ctx, step_status, and cond_snap")
	_same_bytes("engine scalar mismatch fallback matches _status_for_info", st_eng_drop, Damage._status_for_info(boat.duplicate(true), EquipmentDamage._numeric_rollout_info(boat.duplicate(true))))
	_tick_prefix_pair("prefix step_status engine scalar absorption tick", boat, 0.1, {"inCombat": true})

	# 7. item & priority transitions in-place on armed ctx + snapshot isolation + pre-armed shared repair.
	check(Records.publish(boat).ok, "sync boat.engine before item transition probe")
	var info_rearmed: Dictionary = EquipmentDamage._prefix_ctx_info(boat, ctx)
	var st_rearmed: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, info_rearmed, ctx, Damage._status_for_info)
	var rearmed_cond_snap: Dictionary = ctx.get("step_status_cond_snap", {})
	var rearmed_snap_bytes: Dictionary = _bytes("rearmed cond_snap before in-place item strike", rearmed_cond_snap)
	check(bool(ctx.get("valid", false)) and is_same(ctx.get("step_status"), st_rearmed) and not rearmed_cond_snap.is_empty(), "ctx re-armed before in-place item edit")
	if _strike(boat, "mount0", 0.85, "Step status mount0 disable") and _strike(boat, "pumps", 0.50, "Step status pumps damage"):
		if rearmed_snap_bytes.ok:
			check(_bytes("rearmed cond_snap after in-place item strike", rearmed_cond_snap).bytes == rearmed_snap_bytes.bytes, "in-place item strike leaves prior cond_snap byte-identical")
		_differ_bytes("mutated live moduleCondition differs from prior cond_snap", boat.moduleCondition, rearmed_cond_snap)
		check(not EquipmentDamage._prefix_ctx_reuse_info(boat, ctx), "in-place item edit invalidates _prefix_ctx_reuse_info before cached info reuse")
		var st_after_item: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, info_rearmed, ctx, Damage._status_for_info)
		check(not is_same(ctx.get("info"), info_rearmed) and not is_same(ctx.get("step_status_cond_snap"), rearmed_cond_snap), "fallback re-arms fresh info and fresh cond_snap after in-place item edit")
		_same_bytes("re-armed cond_snap matches mutated moduleCondition", ctx.get("step_status_cond_snap", {}), boat.moduleCondition)
		check(not is_same(st_after_item, st_rearmed) and float(st_after_item.get("pumpFactor", 1.0)) == 0.5 and float(st_after_item.get("weaponFactors", {}).get("mount0", 1.0)) == 0.0, "in-place item edit invalidates stale step_status and refreshes factors")
		_same_bytes("in-place item edit matches Damage.get_status", st_after_item, Damage.get_status(boat.duplicate(true)))
		var snap_before_prio: Dictionary = ctx.get("step_status_cond_snap", {})
		var snap_before_prio_bytes: Dictionary = _bytes("cond_snap before priority edit", snap_before_prio)
		check(Damage.set_repair_priority(boat, "pumps") == "pumps", "set repairPriority to pumps")
		if snap_before_prio_bytes.ok:
			check(_bytes("cond_snap after priority edit", snap_before_prio).bytes == snap_before_prio_bytes.bytes, "in-place priority edit leaves prior cond_snap byte-identical")
		check(not EquipmentDamage._prefix_ctx_reuse_info(boat, ctx), "in-place repairPriority edit invalidates _prefix_ctx_reuse_info before cached info reuse")
		var st_after_prio: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, ctx.get("info"), ctx, Damage._status_for_info)
		check(str(st_after_prio.get("repairPriority", "")) == "pumps", "in-place repairPriority change refreshes step_status")
		_same_bytes("in-place repairPriority change matches Damage.get_status", st_after_prio, Damage.get_status(boat.duplicate(true)))
		boat.policy = "repair"
		boat.supplies = 10.0
		boat.wounded = 0.0
		_tick_prefix_pair("prefix step_status active pumps repair tick", boat, 0.1, {"inCombat": true, "priority": "pumps"})

	# 7b. Pre-armed ctx invalidations before shared repair (module / priority / policy / engine edits).
	var base_armed: Dictionary = _fitted("psc-step-prearmed", false)
	if not base_armed.is_empty():
		base_armed.water = 0.0
		base_armed.fire = 0.0
		base_armed.supplies = 10.0
		base_armed.policy = "balanced"
		var mod_pair: Dictionary = _tick_armed_prefix_pair(
			"pre-armed module edit into shared repair",
			base_armed,
			func(b: Dictionary) -> void:
				_strike(b, "pumps", 0.50, "Pre-armed pumps damage")
				_strike(b, "mount0", 0.85, "Pre-armed mount0 disable"),
			true,
			0.1,
			{"inCombat": true, "priority": "pumps"}
		)
		check(float(_item_at(mod_pair.wiredBoat.moduleCondition, "pumps").hp) > 0.50 and float(mod_pair.wiredStatus.get("repairedModuleHp", 0.0)) > 0.0 and float(mod_pair.wiredBoat.supplies) < 10.0, "pre-armed module edit feeds fresh info into shared repair and repairs pumps")

		var hull_armed: Dictionary = base_armed.duplicate(true)
		hull_armed.hp = 80.0
		var prio_pair: Dictionary = _tick_armed_prefix_pair(
			"pre-armed priority edit into shared repair",
			hull_armed,
			func(b: Dictionary) -> void:
				Damage.set_repair_priority(b, "hull"),
			true,
			0.1,
			{"inCombat": true}
		)
		check(float(prio_pair.wiredBoat.hp) > 80.0 and float(prio_pair.wiredStatus.get("repairedHullHp", 0.0)) > 0.0 and float(prio_pair.wiredBoat.supplies) < 10.0, "pre-armed priority edit feeds fresh info into shared repair and repairs hull")

		var pol_pair: Dictionary = _tick_armed_prefix_pair(
			"pre-armed policy edit into shared repair",
			hull_armed,
			func(b: Dictionary) -> void:
				b.policy = "repair",
			false,
			0.1,
			{"inCombat": true}
		)
		check(float(pol_pair.wiredBoat.hp) > 80.0 and float(pol_pair.wiredStatus.get("repairedHullHp", 0.0)) > 0.0 and float(pol_pair.wiredBoat.supplies) < 10.0, "pre-armed policy edit refreshes crewRepair and repairs hull")

		var eng_pair: Dictionary = _tick_armed_prefix_pair(
			"pre-armed engine scalar edit into shared repair",
			base_armed,
			func(b: Dictionary) -> void:
				b.engine = 0.42,
			true,
			0.1,
			{"inCombat": true, "priority": "engine"}
		)
		check(float(_item_at(eng_pair.wiredBoat.moduleCondition, "engine").hp) > 0.42 and float(eng_pair.wiredStatus.get("repairedModuleHp", 0.0)) > 0.0 and float(eng_pair.wiredBoat.supplies) < 10.0, "pre-armed engine edit absorbs legacy scalar and repairs engine")

	# 8. _prefix_ctx_clear erases all step_status keys.
	check(bool(ctx.get("valid", false)) and ctx.has("step_status") and ctx.has("step_status_cond_snap"), "ctx is armed before _prefix_ctx_clear check")
	EquipmentDamage._prefix_ctx_clear(ctx)
	check(not bool(ctx.get("valid", true)) and not ctx.has("info") and not ctx.has("engine_hp") and not ctx.has("step_status") and not ctx.has("step_status_cond_snap"), "_prefix_ctx_clear erases valid/info/engine_hp/step_status/step_status_cond_snap")
	for k in ctx.keys():
		check(not str(k).begins_with("step_status"), "_prefix_ctx_clear leaves no step_status* key: " + str(k))

	# 9. Tick-average output does not mutate cached instantaneous step_status.
	var avg_boat: Dictionary = _fitted("psc-step-avg", false)
	if not avg_boat.is_empty():
		avg_boat.water = 28.0
		avg_boat.fuel = 0.0002
		avg_boat.supplies = 0.0
		avg_boat.vx = 15.0
		var avg_pair: Dictionary = _tick_prefix_pair("prefix step_status mid-tick fuel0 crossing", avg_boat, 0.1, {"inCombat": true})
		var avg_ctx: Dictionary = avg_pair.ctx
		var tick_out: Dictionary = avg_pair.wiredStatus
		var inst_cached: Dictionary = avg_ctx.get("step_status", {})
		var inst_fresh: Dictionary = Damage.get_status(avg_pair.wiredBoat.duplicate(true))
		check(avg_ctx.has("step_status") and not is_same(tick_out, inst_cached), "post-tick status_can is a distinct Dictionary from cached step_status")
		# The raw cache is the last sub-step INPUT; water changed after that read.
		# The guarded accessor must reject it and return current instantaneous state.
		var cache_before_read: Dictionary = _bytes("last input before guarded refresh", inst_cached)
		var final_info: Dictionary = EquipmentDamage._prefix_ctx_info(avg_pair.wiredBoat, avg_ctx)
		check(not EquipmentDamage._prefix_ctx_step_status_valid(avg_pair.wiredBoat, final_info, avg_ctx), "post-tick changed water invalidates the last sub-step input cache")
		var inst_accessed: Dictionary = EquipmentDamage._prefix_ctx_step_status(avg_pair.wiredBoat, final_info, avg_ctx, Damage._status_for_info)
		check(not is_same(inst_accessed, inst_cached), "guarded refresh returns a new current status without changing the prior cache")
		_same_bytes("guarded step_status read after mid-tick fuel0 matches final instantaneous get_status", inst_accessed, inst_fresh)
		if cache_before_read.ok:
			check(_bytes("last input after guarded refresh", inst_cached).bytes == cache_before_read.bytes, "guarded refresh preserves the prior cached input bytes")
		_differ_bytes("tick-averaged bailing report differs from final dry instantaneous step_status", tick_out, inst_accessed)
		var cached_before_mut: Dictionary = _bytes("inst_cached before tick_out mutation", inst_cached)
		var current_before_mut: Dictionary = _bytes("current guarded status before tick_out mutation", inst_accessed)
		tick_out.inflow = -777.0
		tick_out.bailing = -888.0
		tick_out.workByTask["fire"] = 999.0
		if cached_before_mut.ok:
			check(_bytes("inst_cached after tick_out mutation", inst_cached).bytes == cached_before_mut.bytes, "mutating returned tick status never mutates cached step_status")
		if current_before_mut.ok:
			check(_bytes("current guarded status after tick_out mutation", inst_accessed).bytes == current_before_mut.bytes, "mutating tick output also leaves the current guarded cache unchanged")

func _finish() -> void:
	if failures > 0:
		push_error("private_status_contract: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	print("private_status_contract: %d checks, 0 failures" % checks)
	quit(0)
