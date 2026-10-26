extends SceneTree
## prefix-tick-scope-r1. Overlay onto prefix-step-status-r2 before running.
## Does not start an engine. Root reviews before any native run.
## Proves the closed-tick condition proof: between-tick nested edits, in-tick
## writes, error exit, owner isolation, and uncontrolled callbacks.

const Prefix = preload("res://scripts/equipment_prefix_step_status.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")

var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("prefix_tick_scope_r1: " + message)

func _boat() -> Dictionary:
	var item: Dictionary = {"location": "engine", "hp": 1.0, "status": "ok", "cause": "", "family": "engines"}
	var cond: Dictionary = {
		"items": {"eng1": item},
		"repairPriority": "auto",
		"legacyEngineSynced": 1.0,
		"birthNamespace": "hull-a",
		"nextItemSeq": 2,
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
		"spec": {},
		"sunk": false
	}

func _info_for(boat: Dictionary) -> Dictionary:
	var hp: float = float(boat.moduleCondition.items["eng1"].hp)
	return {
		"ok": true,
		"mode": "canonical",
		"needsInitialize": false,
		"snapshot": {
			"ok": true,
			"repairPriority": "auto",
			"engineHp": hp,
			"installed": {"engine": {"family": "engines", "hp": hp}}
		}
	}

func _arm(boat: Dictionary) -> Dictionary:
	var ctx: Dictionary = {"owner": boat, "valid": false}
	var info: Dictionary = _info_for(boat)
	check(Prefix.arm_info(boat, info, ctx), "arm_info accepts the fixture")
	ctx["info"] = info
	ctx["engine_hp"] = float(boat.engine)
	ctx["valid"] = true
	return ctx

func _nested_hp(boat: Dictionary) -> float:
	return float(boat.moduleCondition.items["eng1"].hp)

func _between_ticks() -> void:
	var boat: Dictionary = _boat()
	var ctx: Dictionary = _arm(boat)
	Prefix.tick_scope_begin(ctx)
	check(Prefix.cond_valid(boat, ctx), "first compare inside the tick holds")
	check(bool(ctx.get("cond_eq_proof", false)), "first compare stores the proof on this ctx")
	# Tamper the clone only. A live proof must skip cond == cond_snap.
	var snap: Dictionary = ctx.get("step_status_cond_snap")
	snap.items["eng1"].hp = 0.25
	check(Prefix.cond_valid(boat, ctx), "open proof skips the deep compare")
	snap.items["eng1"].hp = 1.0
	Prefix.tick_scope_end(ctx)
	check(not bool(ctx.get("tick_scope_open", true)) and not bool(ctx.get("cond_eq_proof", false)), "end closes scope and drops the proof")
	boat.moduleCondition.items["eng1"].hp = 0.5
	ctx["cond_eq_proof"] = true
	check(not Prefix.cond_valid(boat, ctx), "between ticks a stale proof cannot hide nested hp")
	boat.moduleCondition.items["eng1"].hp = 1.0
	ctx["cond_eq_proof"] = true
	ctx["tick_scope_open"] = true
	Prefix.tick_scope_begin(ctx)
	check(not bool(ctx.get("cond_eq_proof", false)), "begin drops a proof a skipped end would have left")

func _within_tick_writes() -> void:
	var boat: Dictionary = _boat()
	var ctx: Dictionary = _arm(boat)
	Prefix.tick_scope_begin(ctx)
	check(Prefix.cond_valid(boat, ctx) and bool(ctx.get("cond_eq_proof", false)), "proof is live before the write barrier")
	EquipmentDamage._prefix_drop_cond_proof(ctx)
	check(not bool(ctx.get("cond_eq_proof", false)) and _nested_hp(boat) == 1.0, "barrier clears the proof before the nested write")
	boat.moduleCondition.items["eng1"].hp = 0.5
	check(bool(ctx.get("tick_scope_open", false)) and not Prefix.cond_valid(boat, ctx), "after the barrier, nested hp fails cond_valid inside the same tick")

	var written: Dictionary = _boat()
	var written_ctx: Dictionary = _arm(written)
	Prefix.tick_scope_begin(written_ctx)
	check(Prefix.cond_valid(written, written_ctx), "absorb fixture compares equal")
	written.engine = 0.4
	var absorbed: Dictionary = EquipmentDamage._prefix_ctx_absorb(written, written_ctx)
	check(bool(absorbed.get("changed", false)) and _nested_hp(written) < 1.0, "absorb writes engine hp")
	check(bool(written_ctx.get("tick_scope_open", false)) and not bool(written_ctx.get("cond_eq_proof", false)), "absorb leaves the tick open and the proof dead")
	check(not Prefix.cond_valid(written, written_ctx), "same-tick cond_valid sees the absorb write")

	var fired: Dictionary = _boat()
	var fired_ctx: Dictionary = _arm(fired)
	Prefix.tick_scope_begin(fired_ctx)
	check(Prefix.cond_valid(fired, fired_ctx), "repair fixture compares equal")
	var idle_info: Dictionary = fired_ctx.get("info")
	var idle: Dictionary = EquipmentDamage._prefix_ctx_repair(fired, 0.0, 0.0, {}, idle_info, fired_ctx)
	check(bool(idle.get("ok", false)) and _nested_hp(fired) == 1.0 and bool(fired_ctx.get("cond_eq_proof", false)), "idle repair does not write condition and keeps the proof")
	fired.fire = 1.0
	var busy: Dictionary = EquipmentDamage._prefix_ctx_repair(fired, 1.0, 0.0, {}, idle_info, fired_ctx)
	check(bool(fired_ctx.get("tick_scope_open", false)) and not bool(fired_ctx.get("cond_eq_proof", false)), "non-idle repair drops the proof and stays inside the tick")
	check(_nested_hp(fired) < 1.0, "non-idle repair writes engine hp: " + str(busy.get("error", busy.get("ok", false))))
	check(not Prefix.cond_valid(fired, fired_ctx), "same-tick cond_valid does not reuse across that write")
	var seen: Dictionary = EquipmentDamage._prefix_ctx_info(fired, fired_ctx)
	var seen_hp: float = float(seen.get("snapshot", {}).get("engineHp", -1.0))
	check(bool(seen.get("ok", false)) and absf(seen_hp - _nested_hp(fired)) <= 0.0001, "later info callback in the same tick reads the written hp")
	fired.engine = _nested_hp(fired)
	var armed_again: Dictionary = EquipmentDamage._prefix_ctx_info(fired, fired_ctx)
	check(bool(armed_again.get("ok", false)) and Prefix.cond_valid(fired, fired_ctx), "once the scalar matches, the same tick can prove the written condition")
	var proved: Dictionary = fired_ctx.get("step_status_cond_snap", {})
	check(not proved.is_empty() and absf(float(proved.items["eng1"].hp) - _nested_hp(fired)) <= 0.0001, "the new proof matches the written hp")

func _error_and_owner() -> void:
	var boat: Dictionary = _boat()
	var ctx: Dictionary = _arm(boat)
	Prefix.tick_scope_begin(ctx)
	check(Prefix.cond_valid(boat, ctx), "error-exit fixture compares equal")
	Prefix.tick_scope_end(ctx)
	check(not bool(ctx.get("tick_scope_open", true)) and not bool(ctx.get("cond_eq_proof", false)), "the statement after the invocation clears a normal or error return")
	Prefix.tick_scope_end(ctx)
	check(not bool(ctx.get("tick_scope_open", true)), "a second end stays closed")

	var owner: Dictionary = _boat()
	var owner_ctx: Dictionary = _arm(owner)
	Prefix.tick_scope_begin(owner_ctx)
	check(Prefix.cond_valid(owner, owner_ctx), "owner proof is set")
	var other: Dictionary = _boat()
	check(not Prefix.cond_valid(other, owner_ctx), "another owner fails cond_valid")
	check(not bool(owner_ctx.get("cond_eq_proof", false)), "a foreign miss drops the owner proof instead of lending it")
	check(Prefix.cond_valid(owner, owner_ctx), "the owner can prove its own condition again")

	var shared: Dictionary = _boat()
	var shared_ctx: Dictionary = _arm(shared)
	Prefix.tick_scope_begin(shared_ctx)
	check(Prefix.cond_valid(shared, shared_ctx), "shared-condition fixture compares equal")
	var intruder: Dictionary = {"moduleCondition": shared.moduleCondition, "engine": 0.4, "breaches": []}
	EquipmentDamage._prefix_drop_cond_proof_if_same_condition(intruder, shared_ctx)
	check(not bool(shared_ctx.get("cond_eq_proof", false)) and _nested_hp(shared) == 1.0, "same condition object loses the proof before the foreign write")
	var foreign: Dictionary = EquipmentDamage._prefix_ctx_absorb(intruder, shared_ctx)
	check(bool(foreign.get("changed", false)) and _nested_hp(shared) < 1.0, "unbound absorb writes the shared condition")
	check(not Prefix.cond_valid(shared, shared_ctx), "the owner does not reuse a proof across that foreign write")

func _callbacks() -> void:
	var boat: Dictionary = _boat()
	var ctx: Dictionary = _arm(boat)
	var info: Dictionary = ctx.get("info")
	check(not bool(ctx.get("tick_scope_open", false)), "prefix callbacks do not open the scope by themselves")
	ctx["cond_eq_proof"] = true
	boat.moduleCondition.items["eng1"].hp = 0.42
	check(not Prefix.cond_valid(boat, ctx), "a forced proof is ignored while the scope is closed")
	boat.moduleCondition.items["eng1"].hp = 1.0
	Prefix.tick_scope_begin(ctx)
	check(Prefix.cond_valid(boat, ctx), "controlled publish fixture compares equal")
	var published: Dictionary = EquipmentDamage._prefix_ctx_publish(boat, ctx)
	check(bool(published.get("ok", false)) and published.size() == 1 and bool(ctx.get("cond_eq_proof", false)) and _nested_hp(boat) == 1.0, "no-write publish keeps the proof")
	var external := func(target: Dictionary) -> void:
		target.moduleCondition.items["eng1"].hp = 0.2
	Prefix.tick_scope_end(ctx)
	external.call(boat)
	ctx["cond_eq_proof"] = true
	check(not Prefix.cond_valid(boat, ctx), "an uncontrolled callback's nested write is visible when the scope is closed")
	var rollout: String = FileAccess.get_file_as_string("res://scripts/equipment_rollout.gd")
	var begin_at: int = rollout.find("EquipmentDamage._prefix_tick_scope_begin(prefix_ctx)")
	var call_at: int = rollout.find("Damage._tick_canonical_with(copy,sub_dt,{\"inCombat\":true},prefix_info,prefix_repair,prefix_publish,prefix_absorb,null,prefix_step_status)")
	var end_at: int = rollout.find("EquipmentDamage._prefix_tick_scope_end(prefix_ctx)")
	check(begin_at >= 0 and call_at > begin_at and end_at > call_at, "begin, the closed call, and end are lexical and in that order")
	check(rollout.find("\ntry:") < 0 and rollout.find("\ntry ") < 0, "the scope does not invent try/finally")
	var damage_text: String = FileAccess.get_file_as_string("res://scripts/damage.gd")
	check(damage_text.find("_prefix_tick_scope_begin") < 0, "Damage._tick_canonical_with is not wrapped for public or numeric callers")

func _initialize() -> void:
	_between_ticks()
	_within_tick_writes()
	_error_and_owner()
	_callbacks()
	if failures > 0:
		push_error("prefix_tick_scope_r1 failures %d / %d" % [failures, checks])
		quit(1)
	else:
		print("prefix_tick_scope_r1 ok %d" % checks)
		quit(0)
