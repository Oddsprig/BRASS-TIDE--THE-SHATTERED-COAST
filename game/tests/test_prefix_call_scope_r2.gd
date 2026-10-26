extends "res://tests/test_prefix_tick_scope_r1.gd"
## Additional source-only tests. The e9d34975 parent stays byte-identical.
## _initialize below invokes every original assertion group in original order.

func _sixty_comparisons_in_one_scope() -> void:
	var boat: Dictionary = _boat()
	var ctx: Dictionary = _arm(boat)
	EquipmentDamage._prefix_tick_scope_begin(ctx)
	check(Prefix.cond_valid(boat, ctx), "whole-prefix proof starts with a real exact comparison")
	var original_condition: PackedByteArray = var_to_bytes(boat.moduleCondition)
	var snap: Dictionary = ctx.get("step_status_cond_snap")
	# Only the detached saved snapshot is changed. A deep compare would fail;
	# every successful call below therefore exercises the already-proved branch.
	snap.items["eng1"].hp = 0.25
	for step in range(60):
		check(Prefix.cond_valid(boat, ctx) and bool(ctx.get("tick_scope_open", false)) and bool(ctx.get("cond_eq_proof", false)), "one locally open prefix retains its proof at comparison " + str(step + 1))
	check(var_to_bytes(boat.moduleCondition) == original_condition, "all60 comparisons leave the owned condition unchanged")
	EquipmentDamage._prefix_tick_scope_end(ctx)
	check(not bool(ctx.get("tick_scope_open", true)) and not bool(ctx.get("cond_eq_proof", false)), "one end closes the entire60-comparison prefix")
	check(not Prefix.cond_valid(boat, ctx), "after close the unchanged deep-compare guard sees the deliberately different snapshot")
	snap.items["eng1"].hp = 1.0
	check(Prefix.cond_valid(boat, ctx) and not bool(ctx.get("cond_eq_proof", false)), "closed equality succeeds without reviving an open-scope proof")

func _foreign_publish_barrier() -> void:
	var boat: Dictionary = _boat()
	var ctx: Dictionary = _arm(boat)
	EquipmentDamage._prefix_tick_scope_begin(ctx)
	check(Prefix.cond_valid(boat, ctx), "foreign publish starts with an armed proof")
	var before: PackedByteArray = var_to_bytes(boat)
	var foreign: Dictionary = {"moduleCondition": boat.moduleCondition, "engine": 0.4, "refitLocker": {"sentinel": 7}}
	check(not is_same(foreign, boat) and is_same(foreign.moduleCondition, boat.moduleCondition), "foreign boat really shares the exact armed condition")
	var published: Dictionary = EquipmentDamage._prefix_ctx_publish(foreign, ctx)
	check(bool(published.get("ok", false)) and float(foreign.engine) == 1.0 and foreign.refitLocker.is_empty(), "foreign fallback really publishes engine and locker projections")
	check(bool(ctx.get("tick_scope_open", false)) and not bool(ctx.get("cond_eq_proof", false)), "same-condition foreign publish drops the proof while leaving this local scope open")
	check(var_to_bytes(boat) == before, "foreign publication does not change the actual owner or shared condition")
	check(Prefix.cond_valid(boat, ctx) and bool(ctx.get("cond_eq_proof", false)), "owner can prove its own unchanged condition again")
	var unrelated: Dictionary = {"moduleCondition": boat.moduleCondition.duplicate(true), "engine": 0.4}
	EquipmentDamage._prefix_ctx_publish(unrelated, ctx)
	check(bool(ctx.get("cond_eq_proof", false)), "a distinct foreign condition does not borrow or invalidate the owner's proof")
	boat.engine = 0.4
	EquipmentDamage._prefix_ctx_publish(boat, ctx)
	check(not bool(ctx.get("cond_eq_proof", false)) and not bool(ctx.get("valid", true)) and float(boat.engine) == 1.0, "bound scalar miss clears the proof before normal publication")
	EquipmentDamage._prefix_tick_scope_end(ctx)
	var source: String = FileAccess.get_file_as_string("res://scripts/equipment_damage.gd")
	var begin: int = source.find("static func _prefix_ctx_publish(")
	var end: int = source.find("\nstatic func ", begin + 1)
	var body: String = source.substr(begin, end - begin)
	var barrier: int = body.find("_prefix_drop_cond_proof_if_same_condition(boat, ctx)")
	var fallback: int = body.find("return Records._publish_numeric(boat)")
	check(begin >= 0 and end > begin and barrier >= 0 and fallback > barrier, "foreign barrier is before the original numeric publication, not after its writes")

func _initialize() -> void:
	_between_ticks()
	_within_tick_writes()
	_error_and_owner()
	_callbacks()
	_sixty_comparisons_in_one_scope()
	_foreign_publish_barrier()
	print("prefix_call_scope_r2: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
