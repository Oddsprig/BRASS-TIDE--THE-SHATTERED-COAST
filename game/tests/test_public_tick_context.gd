extends SceneTree
## SOURCE ONLY: supplementary public_tick_context; not original174 or private931.
## Both arms use the actual shared kernel. No copied repair loop or expected math.
const Damage = preload("res://scripts/damage.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Core = preload("res://scripts/equipment_condition.gd")
const Refit = preload("res://scripts/refit.gd")
const FIT: Dictionary = {"weapons": ["stock_primary", "rapid_gun", "light_cannon", "fire_rocket"], "engine": "stock_engine", "armor": "stock_armor"}

class PriorityProbe extends RefCounted:
	var calls: int = 0
	var meta: Dictionary
	var text: String
	func _init(target: Dictionary, value: String) -> void:
		meta = target
		text = value
	func _to_string() -> String:
		calls += 1
		meta["conversions"] = int(meta.get("conversions", 0)) + 1
		return text

var world: Dictionary = {}
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("public_tick_context: " + message)

func _safe(value, depth: int = 0) -> bool:
	if depth > 64 or typeof(value) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]:
		return false
	if value is Dictionary:
		for key in value.keys():
			if not _safe(key, depth + 1) or not _safe(value[key], depth + 1): return false
	elif value is Array:
		for item in value:
			if not _safe(item, depth + 1): return false
	return true

func _same(label: String, left, right) -> void:
	var safe: bool = _safe(left) and _safe(right)
	check(safe, label + " encodable without Objects/callables/cycles")
	if safe: check(var_to_bytes(left) == var_to_bytes(right), label + " exact Variant bytes")

func _boat() -> Dictionary:
	var base: Dictionary = world.HULLS[23].duplicate(true)
	var boat: Dictionary = Damage.create_ship(base, {"policy": "repair", "refitLocker": {"rapid_gun": 2, "stock_engine": 1}})
	var norm: Dictionary = Refit.normalize(base, FIT)
	check(bool(norm.get("ok", false)), "factory loadout normalizes")
	if not norm.get("ok", false): return {}
	boat.loadout = norm.loadout
	Refit.ensure(boat, base)
	boat.uid = "public-tick-context-r1"
	var seeded: Dictionary = Records.initialize(boat, {"base": base, "loadout": boat.loadout, "catalog": Refit.catalog(), "identity": boat.uid, "knownUids": []})
	check(bool(seeded.get("ok", false)), "real Records.initialize: " + str(seeded.get("error", "ok")))
	if not seeded.get("ok", false): return {}
	return boat

func _engine(boat: Dictionary) -> Dictionary:
	for item in boat.moduleCondition.items.values():
		if str(item.location) == "engine": return item
	return {}

func _original(boat: Dictionary, dt: float, options: Dictionary, cache) -> Dictionary:
	# Accepted B1a canonical entry only: actual helpers, same order/normalization.
	Damage.invalidate_frame_cache(cache, boat)
	var info: Dictionary = EquipmentDamage.inspect_owner(boat)
	check(bool(info.get("ok", false)) and str(info.get("mode", "")) == "canonical", "reference entry remains canonical")
	if not info.get("ok", false) or str(info.get("mode", "")) != "canonical": return {}
	dt = maxf(0.0, Damage.number(dt))
	var out_info = {} if cache is Dictionary else null
	var status: Dictionary = Damage._tick_canonical_with(
		boat, dt, options,
		EquipmentDamage.inspect_owner,
		EquipmentDamage._tick_repair_step_from_info,
		Records.publish,
		Records.absorb_legacy_damage,
		out_info
	)
	if cache is Dictionary and bool(status.get("equipmentOk", false)):
		Damage._store_cached_info(boat, out_info.get("info", {}), cache)
	return status

func _pair(label: String, source: Dictionary, dt: float, options: Dictionary = {}, eligible: bool = true, published: bool = true, probe: bool = false, cache_mode: String = "warm") -> Dictionary:
	var wired: Dictionary = source.duplicate(true)
	var original: Dictionary = source.duplicate(true)
	# Explicitly rebuild this intended alias; deep duplication need not retain it.
	if source.has("breachAlias"):
		check(not wired.breaches.is_empty() and not original.breaches.is_empty(), label + " alias has a breach")
		if wired.breaches.is_empty() or original.breaches.is_empty(): return {}
		wired.breachAlias = wired.breaches[0]
		original.breachAlias = original.breaches[0]
	var wo: Dictionary = options.duplicate(true)
	var ro: Dictionary = options.duplicate(true)
	var wp: PriorityProbe = null
	var rp: PriorityProbe = null
	if probe:
		wired["probeMeta"] = {"conversions": 0}
		original["probeMeta"] = {"conversions": 0}
		wp = PriorityProbe.new(wired.probeMeta, str(options.priority))
		rp = PriorityProbe.new(original.probeMeta, str(options.priority))
		wo.priority = wp
		ro.priority = rp
	var wi: Dictionary = EquipmentDamage.inspect_owner(wired)
	var ri: Dictionary = EquipmentDamage.inspect_owner(original)
	var canonical: bool = bool(wi.get("ok", false)) and bool(ri.get("ok", false)) and str(wi.get("mode", "")) == "canonical" and str(ri.get("mode", "")) == "canonical"
	check(canonical, label + " BOTH initial owners canonical, including alias case")
	if not canonical: return {}
	var wc = null if cache_mode == "none" else {}
	var rc = null if cache_mode == "none" else {}
	if cache_mode == "warm":
		Damage._store_cached_info(wired, wi, wc)
		Damage._store_cached_info(original, ri, rc)
		check(wc.has(str(wired.id)) and rc.has(str(original.id)), label + " real cache warmed before entry invalidation")
	elif cache_mode == "cold": check(wc.is_empty() and rc.is_empty(), label + " genuinely cold frame caches")
	check(bool(EquipmentDamage._make_public_tick_context(wired, wi, wo, wc).eligible) == eligible, label + " wired branch eligibility precondition")
	check(bool(EquipmentDamage._make_public_tick_context(original, ri, ro, rc).eligible) == eligible, label + " reference branch eligibility precondition")
	if probe: check(wp.calls == 0 and rp.calls == 0, label + " eligibility does not convert priority Object")
	_same(label + " initial owners", wired, original)
	var wl: Dictionary = wired.refitLocker
	var rl: Dictionary = original.refitLocker
	var locker_before: Dictionary = wl.duplicate(true)
	var wb: Array = wired.breaches
	var rb: Array = original.breaches
	var ws: Dictionary = Damage.tick_ship(wired, dt, wo, wc)
	var rs: Dictionary = _original(original, dt, ro, rc)
	check(bool(ws.get("equipmentOk", false)) == published and bool(rs.get("equipmentOk", false)) == published, label + " expected acceptance/refusal on BOTH arms")
	_same(label + " WHOLE owned boats", wired, original)
	_same(label + " returned tick reports", ws, rs)
	_same(label + " full frame caches", wc, rc)
	var expected_keys: Array = source.keys()
	if probe: expected_keys.append("probeMeta")
	check(wired.keys() == original.keys() and wired.keys() == expected_keys, label + " exact key order/no leaked context")
	check((not is_same(wired.refitLocker, wl)) == published and (not is_same(original.refitLocker, rl)) == published, label + " matching fresh locker identities/refusal")
	_same(label + " escaped wired locker unchanged", wl, locker_before)
	_same(label + " escaped original locker unchanged", rl, locker_before)
	check(is_same(wired.breaches, wb) == is_same(original.breaches, rb), label + " breach-array identity parity")
	_same(label + " escaped breach arrays", wb, rb)
	if source.has("breachAlias"):
		check(is_same(wired.breachAlias, wb[0]) and is_same(original.breachAlias, rb[0]), label + " retained breach-dictionary aliases survive")
		check(float(wb[0].area) < float(source.breachAlias.area), label + " actual repair mutates the retained breach")
	if probe:
		check(wp.calls > 0 and wp.calls == rp.calls, label + " actual Object conversion counts match")
		check(wired.probeMeta.conversions == wp.calls and original.probeMeta.conversions == rp.calls, label + " safe metadata mutations match conversions")
	for boat in [wired, original]:
		check(boat.crew == source.crew and boat.wounded == source.wounded, label + " crew preserved")
		for key in ["supplies", "fuel", "ammo"]:
			check(is_finite(float(boat[key])) and float(boat[key]) >= 0.0, label + " finite nonnegative " + key)
	var before_w: Dictionary = wired.duplicate(true)
	var before_r: Dictionary = original.duplicate(true)
	_same(label + " fresh public statuses", Damage.get_status(wired), Damage.get_status(original))
	_same(label + " wired public observer purity", wired, before_w)
	_same(label + " reference public observer purity", original, before_r)
	if wc is Dictionary and rc is Dictionary and wc.has(str(wired.id)) and rc.has(str(original.id)):
		check(is_same(wc[str(wired.id)].shipRef, wired) and is_same(rc[str(original.id)].shipRef, original), label + " cached owner identities")
	return {"wired": wired, "original": original, "wiredStatus": ws, "originalStatus": rs}

func _paid(label: String, before: Dictionary, pair: Dictionary) -> void:
	check(not pair.is_empty(), label + " completed both arms")
	if pair.is_empty(): return # Failed precondition already counted; never a skip/pass.
	for arm in ["wired", "original"]:
		check(float(_engine(pair[arm]).hp) > float(_engine(before).hp), label + " " + arm + " actual module HP gain")
		check(float(pair[arm].supplies) < float(before.supplies), label + " " + arm + " actual supply debit")
		check(float(pair[arm + "Status"].get("usedSupplies", 0.0)) > 0.0 and float(pair[arm + "Status"].get("repairedModuleHp", 0.0)) > 0.0, label + " " + arm + " reported paid repair")

func _cases(base: Dictionary) -> void:
	_pair("healthy warmed multi-quantum", base, 0.1)
	_pair("healthy cold multi-quantum", base, 0.1, {}, true, true, false, "cold")
	_pair("healthy no out-info", base, 0.1, {}, true, true, false, "none")
	var wet: Dictionary = base.duplicate(true)
	wet.water = 30.0
	check(wet.breaches.is_empty(), "wet fast path has EMPTY breaches")
	var wet_pair: Dictionary = _pair("wet empty breaches", wet, 0.1)
	if not wet_pair.is_empty(): check(float(wet_pair.wired.water) < float(wet.water), "wet case actually bails")
	var damaged: Dictionary = base.duplicate(true)
	var engine: Dictionary = _engine(damaged)
	check(not engine.is_empty(), "real fitted engine exists")
	if engine.is_empty(): return
	var struck: Dictionary = Core.apply_component_damage(damaged.moduleCondition, {"itemUid": str(engine.itemUid), "loss": 0.5, "cause": "Public context fixture wear"})
	var pub: Dictionary = Records.publish(damaged)
	check(bool(struck.get("ok", false)) and bool(pub.get("ok", false)) and float(_engine(damaged).hp) < Core.JURY_CAP, "real engine damage below jury cap/publish succeeds")
	if not struck.get("ok", false) or not pub.get("ok", false): return
	_paid("engine repair", damaged, _pair("engine repair", damaged, 0.1, {"priority": "engine"}))
	var burning: Dictionary = damaged.duplicate(true)
	burning.fire = 1.0
	var fire_pair: Dictionary = _pair("repair plus fire", burning, 1.0 / 60.0, {"priority": "engine"})
	_paid("repair plus fire", burning, fire_pair)
	if not fire_pair.is_empty(): check(float(fire_pair.wired.hp) < float(burning.hp), "fire really damages hull while machinery receives paid repair")
	var partial: Dictionary = damaged.duplicate(true)
	partial.supplies = 0.0001
	_paid("partial stores", partial, _pair("partial stores", partial, 0.1, {"priority": "engine"}))
	var idle: Dictionary = damaged.duplicate(true)
	idle.crew = 0.0
	var idle_pair: Dictionary = _pair("zero able work", idle, 0.1)
	if not idle_pair.is_empty(): check(float(idle_pair.wiredStatus.get("availableWork", -1.0)) == 0.0 and float(idle_pair.wiredStatus.get("usedSupplies", -1.0)) == 0.0, "zero work is actually reached")
	var eps_boat: Dictionary = damaged.duplicate(true)
	eps_boat.crew = 5.0
	eps_boat.policy = "bail"
	var rate: float = float(Damage.get_status(eps_boat).crewRepair)
	check(rate > 0.0, "EPS setup has observed repair crew")
	if rate > 0.0:
		for scale in [0.5, 1.0, 2.0]:
			# Choose duration from REAL status, not a copied crew/repair formula.
			var h: float = Core.EPS * scale / rate
			check(h > 0.00000001 and h < 1.0 / 60.0, "EPS case executes exactly one real quantum")
			var ep: Dictionary = _pair("EPS work " + str(scale), eps_boat, h)
			if not ep.is_empty():
				check(float(ep.wiredStatus.get("availableWork", -1.0)) > 0.0 and (float(ep.wiredStatus.get("availableWork", -1.0)) <= Core.EPS) == (scale <= 1.0), "observed work reaches requested EPS side")
				if scale == 1.0: check(float(ep.wiredStatus.get("availableWork", -1.0)) == Core.EPS, "observed work is exactly EPS")
	var downward: Dictionary = base.duplicate(true)
	downward.engine = 0.45
	check(float(downward.engine) < float(_engine(downward).hp), "external scalar genuinely below installed HP")
	var dp: Dictionary = _pair("downward legacy sync", downward, 0.1)
	if not dp.is_empty(): check(float(_engine(dp.wired).hp) < float(_engine(base).hp) and float(dp.wired.engine) == float(_engine(dp.wired).hp), "downward write absorbed and real projection published")
	_pair("zero dt", damaged, 0.0)
	_pair("negative dt normalization", damaged, -1.0)
	var sunk: Dictionary = damaged.duplicate(true)
	sunk.sunk = true
	_pair("already sunk", sunk, 0.1)
	var breach: Dictionary = base.duplicate(true)
	breach.breaches.append({"area": 18.0, "section": "bow"})
	breach["breachAlias"] = breach.breaches[0] # No foreign condition metadata key.
	_pair("nonempty breach alias fallback", breach, 0.1, {}, false)
	var bad: Dictionary = _pair("unknown priority refusal", damaged, 0.1, {"priority": "unknown"}, false, false)
	if not bad.is_empty():
		check(not bool(bad.wiredStatus.get("equipmentOk", true)), "unknown priority actually refused")
		_same("unknown priority preserves whole owner", bad.wired, damaged)
	_pair("opts-only priority Object fallback", damaged, 0.1, {"priority": "engine"}, false, true, true)

func _guard_only(base: Dictionary) -> void:
	var boat: Dictionary = base.duplicate(true)
	var info: Dictionary = EquipmentDamage.inspect_owner(boat)
	check(bool(info.get("ok", false)) and str(info.get("mode", "")) == "canonical", "guard-only probes start on a real canonical owner")
	if not info.get("ok", false) or str(info.get("mode", "")) != "canonical": return
	var probe: PriorityProbe = PriorityProbe.new({}, "balanced")
	boat.policy = probe
	check(not EquipmentDamage._make_public_tick_context(boat, info, {}, {}).eligible and probe.calls == 0, "policy Object guard refuses WITHOUT conversion/encoding")
	check(not _safe(boat), "policy Object excluded from byte comparisons")
	boat.policy = base.policy
	boat[probe] = 0
	check(not EquipmentDamage._make_public_tick_context(boat, info, {}, {}).eligible and probe.calls == 0, "owner Object-key guard refuses WITHOUT conversion/encoding")
	check(not _safe(boat), "Object key excluded from byte comparisons")
	boat.erase(probe)

func _finish() -> void:
	print("public_tick_context: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _initialize() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var valid: bool = parsed is Dictionary and parsed.get("HULLS") is Array and parsed.HULLS.size() > 23
	check(valid, "real world.json hull 23 exists")
	if not valid:
		_finish()
		return
	world = parsed
	var base: Dictionary = _boat()
	if not base.is_empty():
		_cases(base)
		_guard_only(base)
	_finish()
