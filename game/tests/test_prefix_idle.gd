extends "res://tests/test_prefix_invariants.gd"
## Focused idle cases. Source fixture; does not launch an engine by itself.
const RolloutIdle = preload("res://scripts/equipment_rollout_idle.gd")
const PrefixStepStatus = preload("res://scripts/equipment_prefix_step_status.gd")

func _arm(boat: Dictionary) -> Dictionary:
	var ctx: Dictionary = {"owner": boat, "valid": false}
	# Absorb first: a cold receipt clears cached info/proof by design.
	var _receipt: Dictionary = EquipmentDamage._prefix_ctx_absorb(boat, ctx)
	var info: Dictionary = EquipmentDamage._prefix_ctx_info(boat, ctx)
	EquipmentDamage._prefix_tick_scope_begin(ctx)
	var _st: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, info, ctx, Damage._status_for_info)
	return ctx

func _canonical_tick(boat: Dictionary, ctx: Dictionary, dt: float) -> Dictionary:
	var info_fn: Callable = func(b: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_info(b, ctx)
	var repair_fn: Callable = func(b: Dictionary, h: float, crew_repair: float, options: Dictionary, info: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_repair(b, h, crew_repair, options, info, ctx)
	var publish_fn: Callable = func(b: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_publish(b, ctx)
	var absorb_fn: Callable = func(b: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_absorb(b, ctx)
	var step_fn: Callable = func(b: Dictionary, info: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_step_status(b, info, ctx, Damage._status_for_info)
	return Damage._tick_canonical_with(boat, dt, {"inCombat": true}, info_fn, repair_fn, publish_fn, absorb_fn, null, step_fn)

func _check_idle_source() -> void:
	_check_source_and_helpers()
	var rollout: String = FileAccess.get_file_as_string("res://scripts/equipment_rollout.gd")
	var idle_src: String = FileAccess.get_file_as_string("res://scripts/equipment_rollout_idle.gd")
	check(rollout.find("idle_probe=null") >= 0 and rollout.find("if idle_probe is Dictionary:") >= 0, "prefix takes an optional probe and stores only a Dictionary")
	check(idle_src.find("static var") < 0 and idle_src.find("ready_calls") < 0 and idle_src.find("last_return") < 0, "idle module has no mutable global witness")
	var gate_at: int = idle_src.find("if not _types(")
	var valid_at: int = idle_src.find("PrefixStepStatus.valid(")
	check(gate_at >= 0 and valid_at > gate_at, "finite type gate runs before PrefixStepStatus.valid")

func _check_one_dt(label: String, dt: float, fuel_value: float = 60.0, cooldown_value: float = 0.0) -> void:
	var fresh: Dictionary = _boat("idle-" + label, STANDARD_FIT, true, true)
	fresh.fuel = fuel_value
	fresh.cooldown = cooldown_value
	var live: Dictionary = fresh.duplicate(true)
	var ref: Dictionary = fresh.duplicate(true)
	var ctx_live: Dictionary = _arm(live)
	var ctx_ref: Dictionary = _arm(ref)
	var probe: Dictionary = {}
	ctx_live["idle_probe"] = probe
	var hit: Array = RolloutIdle.try_prefix(live, dt, ctx_live)
	var full: Dictionary = _canonical_tick(ref, ctx_ref, dt)
	check(hit.size() == 1, label + " dry substep is a ready hit")
	if hit.size() == 1:
		_same_bytes(label + " full status", hit[0], full)
		_same_bytes(label + " boat after physical steps", live, ref)
		check(int(probe.get("hits", 0)) == 1, label + " probe.hits is the one ready hit")
		var witness = probe.get("status")
		check(witness is Dictionary and not is_same(witness, hit[0]), label + " probe status is a different dictionary")
		_same_bytes(label + " detached status", witness, hit[0])
		hit[0].weaponFactors["mount1"] = -1.0
		check(float(witness.weaponFactors.get("mount1", 0.0)) != -1.0, label + " returned status does not alias the witness")
		witness.events.append("tamper")
		check(not hit[0].events.has("tamper"), label + " witness does not alias the returned status")
	var next_live: Dictionary = _canonical_tick(live, ctx_live, dt)
	var next_ref: Dictionary = _canonical_tick(ref, ctx_ref, dt)
	_same_bytes(label + " subsequent original tick status", next_live, next_ref)
	_same_bytes(label + " subsequent original tick boat", live, ref)
	var bare: Dictionary = fresh.duplicate(true)
	var ctx_bare: Dictionary = _arm(bare)
	var bare_hit: Array = RolloutIdle.try_prefix(bare, dt, ctx_bare)
	check(not bare_hit.is_empty() and int(probe.get("hits", 0)) == 1 and ctx_bare.get("idle_probe") == null, label + " null probe retains nothing")

func _check_bool_before_valid() -> void:
	var boat: Dictionary = _boat("idle-bool-wounded", STANDARD_FIT, true, true)
	var ctx: Dictionary = _arm(boat)
	check(float(boat.wounded) == 0.0, "healthy wounded is numeric zero before the type swap")
	boat.wounded = false
	var info = ctx.get("info")
	check(PrefixStepStatus.valid(boat, info, ctx), "bool false wounded still passes PrefixStepStatus.valid by fallback")
	var probe: Dictionary = {}
	ctx["idle_probe"] = probe
	var hit: Array = RolloutIdle.try_prefix(boat, 1.0 / 60.0, ctx)
	check(hit.is_empty() and int(probe.get("hits", 0)) == 0, "bool wounded misses before that conversion and records no hit")

func _check_prefix_probe() -> void:
	var idle_boat: Dictionary = _boat("idle-prefix", STANDARD_FIT, true, true)
	var probe: Dictionary = {}
	var out: Dictionary = EquipmentRollout.prefix(_arena(idle_boat), idle_boat, _default_candidate(idle_boat), _budget(), _cert(), 1.0 / 30.0, 1, probe)
	check(bool(out.get("ok", false)) and int(probe.get("hits", 0)) > 0 and probe.get("status") is Dictionary, "prefix records ready hits and a full status on the caller probe")
	var saved: int = int(probe.hits)
	var other: Dictionary = _boat("idle-other-probe", STANDARD_FIT, true, true)
	var other_probe: Dictionary = {}
	EquipmentRollout.prefix(_arena(other), other, _default_candidate(other), _budget(), _cert(), 1.0 / 30.0, 1, other_probe)
	var saved_other: int = int(other_probe.get("hits", 0))
	check(int(probe.hits) == saved and saved_other > 0, "each caller's probe is its own witness")
	var quiet: Dictionary = _boat("idle-null-probe", STANDARD_FIT, true, true)
	EquipmentRollout.prefix(_arena(quiet), quiet, _default_candidate(quiet), _budget(), _cert(), 1.0 / 30.0, 1)
	check(int(probe.hits) == saved and int(other_probe.get("hits", 0)) == saved_other, "default null probe writes neither witness")
	_assert_prefix_parity("idle healthy against inherited reference", _arena(idle_boat), idle_boat, _default_candidate(idle_boat), 1)
	var fire_boat: Dictionary = _boat("idle-fire-miss", STANDARD_FIT, true, true)
	fire_boat.fire = 14.0
	var fire_probe: Dictionary = {}
	_assert_prefix_parity("fire miss against inherited reference", _arena(fire_boat), fire_boat, _default_candidate(fire_boat), 1)
	var fire_out: Dictionary = EquipmentRollout.prefix(_arena(fire_boat), fire_boat, _default_candidate(fire_boat), _budget(), _cert(), 1.0 / 30.0, 1, fire_probe)
	check(bool(fire_out.get("ok", false)) and int(fire_probe.get("hits", 0)) == 0, "active fire takes the canonical arm and records no idle hit")

func _zero(negative: bool) -> float:
	var raw: PackedByteArray = PackedByteArray()
	raw.resize(8)
	raw.fill(0)
	if negative: raw[7] = 128
	return raw.decode_double(0)

func _initialize() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	check(parsed is Dictionary and parsed.get("HULLS") is Array and parsed.HULLS.size() > 23, "world.json parsed with 24 hulls")
	if not (parsed is Dictionary):
		quit(1)
		return
	world = parsed
	catalog = Refit.catalog()
	_check_idle_source()
	_check_one_dt("dt-1-30", 1.0 / 30.0)
	_check_one_dt("dt-1-60", 1.0 / 60.0)
	for parts in [1, 2]:
		var delta: float = (1.0 / 30.0) / float(parts)
		_check_one_dt("zero-fuel-p%d" % parts, delta, _zero(false), _zero(true))
		_check_one_dt("negative-zero-fuel-p%d" % parts, delta, _zero(true), _zero(false))
		_check_one_dt("cross-zero-p%d" % parts, delta, 0.00005, delta * 0.25)
		_check_one_dt("remaining-cooldown-p%d" % parts, delta, 1.0, delta * 2.0)
	_check_bool_before_valid()
	_check_prefix_probe()
	if failures > 0:
		push_error("prefix_idle: %d checks, %d failures" % [checks, failures])
		quit(1)
	else:
		print("prefix_idle: %d checks, 0 failures" % checks)
		quit(0)
