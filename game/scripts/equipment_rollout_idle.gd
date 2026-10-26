extends RefCounted
## One private prefix substep. A miss returns [] and prefix calls Damage._tick_canonical_with.
## No static mutable state. probe.hits and a detached status exist only when this call's ctx holds a Dictionary.
const Damage = preload("res://scripts/damage.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const PrefixStepStatus = preload("res://scripts/equipment_prefix_step_status.gd")
const Core = preload("res://scripts/equipment_condition.gd")

static func _finite(v) -> bool:
	return (v is int or v is float) and not (v is bool) and is_finite(float(v))

static func _text(v) -> bool:
	var t: int = typeof(v)
	return t == TYPE_STRING or t == TYPE_STRING_NAME

static func _optional_finite(host: Dictionary, key: String) -> bool:
	return not host.has(key) or _finite(host.get(key))

static func _types(s: Dictionary, spec: Dictionary, st: Dictionary) -> bool:
	for key in ["hp", "maxHp", "water", "fire", "capacity", "fuel", "cooldown", "vx", "vy", "engine", "crew", "wounded", "crewMax", "supplies", "ammo"]:
		if not _finite(s.get(key)):
			return false
	if not _optional_finite(s, "armor") or not _optional_finite(s, "supportRepairFactor") or not _optional_finite(s, "shoreCrew") or not _optional_finite(s, "crewMin") or not _optional_finite(s, "crewOptimal"):
		return false
	if not _optional_finite(spec, "repairFactor") or not _optional_finite(spec, "pumps"):
		return false
	for key in ["inflow", "bailing", "crewRepair", "repair"]:
		if not _finite(st.get(key)):
			return false
	return true

static func _clamped(s: Dictionary) -> bool:
	if s.hp != clampf(s.hp, 0.0, s.maxHp):
		return false
	if s.crew != clampf(s.crew, 0.0, s.crewMax):
		return false
	if s.wounded != clampf(s.wounded, 0.0, s.crew):
		return false
	if s.water != clampf(s.water, 0.0, s.capacity):
		return false
	if s.fire != clampf(s.fire, 0.0, 100.0):
		return false
	for key in ["supplies", "ammo", "fuel"]:
		if s[key] != maxf(0.0, s[key]):
			return false
	return true

static func _admit(s: Dictionary, dt: float, ctx: Dictionary) -> bool:
	if not (s is Dictionary) or not (ctx is Dictionary) or not is_same(s, ctx.get("owner")):
		return false
	if ctx.get("valid") != true or ctx.get("tick_scope_open") != true or ctx.get("cond_eq_proof") != true:
		return false
	if not _finite(dt) or not (dt > 0.00000001):
		return false
	var info = ctx.get("info")
	var st = ctx.get("step_status")
	if not (info is Dictionary) or not (st is Dictionary) or not is_same(info, ctx.get("step_status_info")) or not is_same(st, ctx.get("step_status")):
		return false
	var snap = info.get("snapshot")
	if not (snap is Dictionary) or not is_same(snap, ctx.get("step_status_snap")) or is_same(st, ctx) or is_same(info, ctx):
		return false
	if s.has("policy") and not _text(s.get("policy")):
		return false
	var spec_raw = s.get("spec")
	var spec: Dictionary = spec_raw if spec_raw is Dictionary else {}
	if not _types(s, spec, st):
		return false
	if not PrefixStepStatus.valid(s, info, ctx):
		return false
	if not EquipmentDamage._prefix_ctx_breaches_empty(s):
		return false
	if st.crewRepair != 0.0 or st.inflow != 0.0 or st.bailing != 0.0 or st.repair != 0.0:
		return false
	if s.get("sunk") != false:
		return false
	if s.hp != s.maxHp or s.hp <= 0.0 or s.capacity <= 0.0 or s.water != 0.0 or s.fire != 0.0:
		return false
	if not Core._unit(s.engine) or not _finite(snap.get("engineHp")) or s.engine != snap.get("engineHp"):
		return false
	var receipt = ctx.get("absorb_receipt")
	if not EquipmentDamage._prefix_ctx_receipt_is_nowrite(receipt) or not _finite(receipt.get("engineHp")) or receipt.get("engineHp") != s.engine:
		return false
	return _clamped(s)

static func _note(ctx: Dictionary, status: Dictionary) -> void:
	var probe = ctx.get("idle_probe")
	if not (probe is Dictionary):
		return
	var seen = probe.get("hits", 0)
	probe["hits"] = (seen + 1) if (seen is int and not (seen is bool)) else 1
	probe["status"] = status.duplicate(true)

static func try_prefix(s: Dictionary, dt: float, ctx: Dictionary) -> Array:
	if not _admit(s, dt, ctx):
		return []
	var st: Dictionary = ctx.get("step_status")
	var step_cap: float = 1.0 / 60.0
	var left: float = dt
	var events: Array = []
	while left > 0.00000001 and not s.sunk:
		var h: float = left if left <= step_cap + 0.0000001 else step_cap
		if absf(left - 2.0 * step_cap) <= 0.0000001:
			h = left * 0.5
		s.water = clampf(s.water + (st.inflow - st.bailing) * h, 0.0, s.capacity)
		if s.fuel > 0.0 and (s.water > 0.0 or absf(s.vx) + absf(s.vy) > 1.0):
			s.fuel -= 0.006 * h
		s.cooldown = maxf(0.0, Damage.number(s.cooldown) - h)
		var published_engine: float = float(s.engine)
		Damage._sanitize(s)
		s.engine = published_engine
		left -= h
		if s.sunk:
			events.append("Ship sunk")
	var out: Dictionary = st.duplicate(true)
	out.inflow = 0.0
	out.bailing = 0.0
	out.repair = 0.0
	out.availableWork = 0.0
	out.usedWork = 0.0
	out.usedSupplies = 0.0
	out.workByTask = EquipmentDamage.empty_task_map()
	out.suppliesByTask = EquipmentDamage.empty_task_map()
	out.repairedPatchArea = 0.0
	out.repairedHullHp = 0.0
	out.repairedModuleHp = 0.0
	out.suppressedFire = 0.0
	out.moduleChanges = []
	out.events = events
	_note(ctx, out)
	return [out]
