extends SceneTree
## prefix-scope-options-test-r1. Overlay onto prefix-call-scope-r2 before running.
## Source-only fixture; does not start an engine.
## Proves that an Object options.priority whose _to_string() mutates a non-engine
## item HP and returns "auto" would leave stale info under the old untyped idle
## gate, whereas patched EquipmentDamage._prefix_ctx_repair rejects the idle fast
## path before str() conversion, clears ctx/cond_eq_proof before fallback, and
## observes the mutated non-engine HP on subsequent _prefix_ctx_info reads.

const Core = preload("res://scripts/equipment_condition.gd")
const Damage = preload("res://scripts/damage.gd")
const Prefix = preload("res://scripts/equipment_prefix_step_status.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")

var checks: int = 0
var failures: int = 0

class PriorityMutator extends RefCounted:
	var target_boat: Dictionary
	var item_uid: String
	var next_hp: float
	var calls: int = 0

	func _init(boat_ref: Dictionary, uid: String = "pump1", hp_after: float = 0.4) -> void:
		target_boat = boat_ref
		item_uid = uid
		next_hp = hp_after

	func _to_string() -> String:
		calls += 1
		var item: Dictionary = target_boat.moduleCondition.items[item_uid]
		Core._set_hp(item, next_hp, "Priority callback", true)
		return "auto"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("prefix_scope_options: " + message)

func _boat() -> Dictionary:
	var eng: Dictionary = {
		"itemUid": "eng1",
		"family": "engines",
		"typeId": "stock_engine",
		"originHullType": "hull_a",
		"location": "engine",
		"lockerOrder": 0,
		"hp": 1.0,
		"cause": "",
		"status": "ok"
	}
	var pump: Dictionary = {
		"itemUid": "pump1",
		"family": "pumps",
		"typeId": "hull_pumps",
		"originHullType": "hull_a",
		"location": "pumps",
		"lockerOrder": 0,
		"hp": 1.0,
		"cause": "",
		"status": "ok"
	}
	var cond: Dictionary = {
		"items": {"eng1": eng, "pump1": pump},
		"repairPriority": "auto",
		"legacyEngineSynced": 1.0,
		"birthNamespace": "hull-a",
		"nextItemSeq": 3,
		"version": 1
	}
	return {
		"moduleCondition": cond,
		"engine": 1.0,
		"breaches": [],
		"fire": 0.0,
		"policy": "balanced",
		"hp": 100.0,
		"maxHp": 100.0,
		"water": 0.0,
		"capacity": 200.0,
		"crew": 5.0,
		"wounded": 0.0,
		"supplies": 20.0,
		"fuel": 10.0,
		"spec": {"pumps": 1.0},
		"sunk": false
	}

func _pump_hp(boat: Dictionary) -> float:
	return float(boat.moduleCondition.items["pump1"].hp)

func _legacy_untyped_repair_idle(boat: Dictionary, h: float, crew_repair: float, options: Dictionary, info: Dictionary, ctx: Dictionary) -> bool:
	if not EquipmentDamage._prefix_ctx_reuse_info(boat, ctx) or not is_same(info, ctx.get("info")):
		return false
	if not (options is Dictionary) or not (boat.get("moduleCondition") is Dictionary):
		return false
	var fire_before: float = clampf(EquipmentDamage.number(boat.get("fire")), 0.0, 100.0)
	if fire_before > 0.0:
		return false
	var priority: String = str(options.get("priority", boat.moduleCondition.get("repairPriority", "auto")))
	if not priority in Core.PRIORITIES:
		return false
	var current: Dictionary = ctx.get("info")
	var snap: Dictionary = current.get("snapshot")
	if str(boat.moduleCondition.get("repairPriority", "")) != str(snap.get("repairPriority", "")):
		return false
	var available_work: float = maxf(0.0, EquipmentDamage.number(crew_repair)) * maxf(0.0, EquipmentDamage.number(h))
	return available_work <= Core.EPS

func _untyped_idle_would_stale() -> void:
	var boat: Dictionary = _boat()
	var ctx: Dictionary = {"owner": boat, "valid": false}
	var init_info: Dictionary = EquipmentDamage._prefix_ctx_info(boat, ctx)
	check(bool(init_info.get("ok", false)) and bool(ctx.get("valid", false)), "untyped baseline arms canonical rollout info")
	Prefix.tick_scope_begin(ctx)
	check(Prefix.cond_valid(boat, ctx) and bool(ctx.get("cond_eq_proof", false)), "untyped baseline sets cond_eq_proof in open scope")
	var mutator := PriorityMutator.new(boat, "pump1", 0.4)
	var idle_taken: bool = _legacy_untyped_repair_idle(boat, 0.0, 0.0, {"priority": mutator}, init_info, ctx)
	check(idle_taken and mutator.calls == 1, "old untyped idle gate stringifies Object priority and accepts returned auto")
	check(absf(_pump_hp(boat) - 0.4) <= 0.0001 and float(boat.engine) == 1.0, "Object _to_string mutates non-engine pump1 hp while leaving engine scalar 1.0")
	check(bool(ctx.get("cond_eq_proof", false)) and Prefix.cond_valid(boat, ctx), "without pre-str type gate, cond_eq_proof remains live and masks the nested mutation")
	var stale_info: Dictionary = EquipmentDamage._prefix_ctx_info(boat, ctx)
	var stale_pump_hp: float = float(stale_info.get("snapshot", {}).get("installed", {}).get("pumps", {}).get("hp", -1.0))
	check(is_same(stale_info, init_info) and absf(stale_pump_hp - 1.0) <= 0.0001, "old untyped idle path reuses stale 1.0 pump snapshot after 0.4 mutation")
	Prefix.tick_scope_end(ctx)

func _patched_fallback_sees_mutation_and_fresh_info() -> void:
	var boat: Dictionary = _boat()
	var ctx: Dictionary = {"owner": boat, "valid": false}
	var init_absorb: Dictionary = EquipmentDamage._prefix_ctx_absorb(boat, ctx)
	var init_info: Dictionary = EquipmentDamage._prefix_ctx_info(boat, ctx)
	var init_status: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, init_info, ctx, Damage._status_for_info)
	check(bool(init_info.get("ok", false)) and bool(init_absorb.get("ok", false)) and bool(init_status.get("equipmentOk", false)), "patched fixture arms info, absorb_receipt, and step_status")
	Prefix.tick_scope_begin(ctx)
	check(Prefix.cond_valid(boat, ctx) and bool(ctx.get("cond_eq_proof", false)), "patched fixture sets cond_eq_proof in open scope")
	var mutator := PriorityMutator.new(boat, "pump1", 0.4)
	check(not EquipmentDamage._prefix_ctx_repair_idle(boat, 0.0, 0.0, {"priority": mutator}, init_info, ctx), "patched _prefix_ctx_repair_idle rejects Object priority before str()")
	check(mutator.calls == 0 and absf(_pump_hp(boat) - 1.0) <= 0.0001, "idle gate rejection does not invoke _to_string()")
	var repaired: Dictionary = EquipmentDamage._prefix_ctx_repair(boat, 0.0, 0.0, {"priority": mutator}, init_info, ctx)
	check(bool(repaired.get("ok", false)) and mutator.calls == 1, "patched _prefix_ctx_repair clears context then runs numeric fallback once")
	check(absf(_pump_hp(boat) - 0.4) <= 0.0001 and float(boat.engine) == 1.0, "fallback _to_string mutates non-engine pump1 hp to 0.4")
	check(bool(ctx.get("tick_scope_open", false)) and not bool(ctx.get("valid", true)) and not ctx.has("cond_eq_proof") and not ctx.has("absorb_receipt"), "patched repair invalidates ctx, absorb_receipt, and cond_eq_proof inside the open scope")
	check(not Prefix.cond_valid(boat, ctx), "cond_valid refuses reuse after fallback mutation")
	var fresh_info: Dictionary = EquipmentDamage._prefix_ctx_info(boat, ctx)
	var fresh_pump_hp: float = float(fresh_info.get("snapshot", {}).get("installed", {}).get("pumps", {}).get("hp", -1.0))
	check(bool(fresh_info.get("ok", false)) and not is_same(fresh_info, init_info) and absf(fresh_pump_hp - 0.4) <= 0.0001, "subsequent _prefix_ctx_info in the same scope computes fresh info with pump1 hp 0.4")
	var init_pump_factor: float = float(init_info.get("snapshot", {}).get("pumpFactor", 0.0))
	var fresh_pump_factor: float = float(fresh_info.get("snapshot", {}).get("pumpFactor", 1.0))
	check(fresh_pump_factor < init_pump_factor, "fresh snapshot reflects reduced pumpFactor after non-engine mutation")
	var fresh_status: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, fresh_info, ctx, Damage._status_for_info)
	check(not is_same(fresh_status, init_status) and absf(float(fresh_status.get("pumpFactor", -1.0)) - fresh_pump_factor) <= 0.0001, "subsequent _prefix_ctx_step_status computes fresh status with reduced pumpFactor")
	Prefix.tick_scope_end(ctx)

func _initialize() -> void:
	_untyped_idle_would_stale()
	_patched_fallback_sees_mutation_and_fresh_info()
	if failures > 0:
		push_error("prefix_scope_options failures %d / %d" % [failures, checks])
		quit(1)
	else:
		print("prefix_scope_options ok %d" % checks)
		quit(0)
