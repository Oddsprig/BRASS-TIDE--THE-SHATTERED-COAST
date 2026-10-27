extends SceneTree
## Root runs this focused live-tick comparison; no private forecast workload changes.
const Damage = preload("res://scripts/damage.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Core = preload("res://scripts/equipment_condition.gd")
const Refit = preload("res://scripts/refit.gd")
const Battle = preload("res://scripts/battle.gd")
const EquipmentCombat = preload("res://scripts/equipment_combat.gd")
const Certification = preload("res://scripts/tactical_certification.gd")
const PROBE_TICKS: int = 32
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL damage hotpath040: ", message)

func eligible(ship: Dictionary, options: Dictionary, cache) -> bool:
	var info: Dictionary = EquipmentDamage.inspect_owner(ship)
	return bool(EquipmentDamage._make_public_tick_context(ship, info, options, cache).eligible) and Damage._healthy_canonical_no_work(ship, info)

func old_tick(ship: Dictionary, dt: float, options: Dictionary, cache) -> Dictionary:
	# Exact pre-change public canonical wiring. The new kernel flag defaults false;
	# all original status/repair callbacks, validation and substeps remain active.
	Damage.invalidate_frame_cache(cache, ship)
	var info: Dictionary = EquipmentDamage.inspect_owner(ship)
	if str(info.get("mode", "invalid")) == "invalid": return Damage.get_status(ship)
	dt = maxf(0.0, Damage.number(dt))
	var out_info = {} if cache is Dictionary else null
	var ctx: Dictionary = EquipmentDamage._make_public_tick_context(ship, info, options, cache)
	var result: Dictionary = (
		Damage._tick_canonical_with(ship, dt, options,
			EquipmentDamage._tick_status_public_local.bind(ctx),
			EquipmentDamage._tick_repair_public_local_from_info.bind(ctx),
			EquipmentDamage._tick_publish_public_local.bind(ctx),
			EquipmentDamage._tick_absorb_public_local.bind(ctx), out_info)
		if bool(ctx.eligible) else Damage._tick_canonical_with(ship, dt, options,
			EquipmentDamage.inspect_owner, EquipmentDamage._tick_repair_step_from_info,
			Records.publish, Records.absorb_legacy_damage, out_info)
	)
	if cache is Dictionary and bool(result.get("equipmentOk", false)):
		Damage._store_cached_info(ship, out_info.get("info", {}), cache)
	return result

func pair(label: String, source: Dictionary, dt: float, fast: bool, options: Dictionary = {}, ticks: int = 1, with_cache: bool = true) -> Dictionary:
	var actual: Dictionary = source.duplicate(true)
	var reference: Dictionary = source.duplicate(true)
	var cache = {} if with_cache else null
	var old_cache = {} if with_cache else null
	var before: PackedByteArray = var_to_bytes(actual)
	check(eligible(actual, options, cache) == fast, label + ": expected admission")
	check(var_to_bytes(actual) == before, label + ": admission is read-only")
	var condition = actual.get("moduleCondition")
	var item_refs: Dictionary = condition.items.duplicate() if condition is Dictionary and condition.get("items") is Dictionary else {}
	var old_locker = actual.get("refitLocker")
	var old_breaches: Array = actual.breaches
	var report: Dictionary = {}
	var expected: Dictionary = {}
	var same: bool = true
	for _i in range(ticks):
		report = Damage.tick_ship(actual, dt, options, cache)
		expected = old_tick(reference, dt, options, old_cache)
		same = same and var_to_bytes(actual) == var_to_bytes(reference) and var_to_bytes(report) == var_to_bytes(expected) and var_to_bytes(cache) == var_to_bytes(old_cache)
	check(same, label + ": every complete boat/report/cache equals old wiring")
	check(is_same(actual.get("moduleCondition"), condition), label + ": condition identity retained")
	var same_items: bool = true
	for uid in item_refs:
		same_items = same_items and is_same(actual.moduleCondition.items.get(uid), item_refs[uid])
	check(same_items, label + ": exact physical item references retained")
	if fast:
		check(report.usedWork == 0.0 and report.usedSupplies == 0.0 and report.availableWork == 0.0 and report.moduleChanges.is_empty(), label + ": no phantom work or damage")
		check(actual.crew == source.crew and actual.wounded == source.wounded and actual.supplies == source.supplies and actual.ammo == source.ammo, label + ": real crew and stores conserved")
		check(not is_same(actual.refitLocker, old_locker) and (is_same(actual.breaches, old_breaches) == (dt <= 0.00000001)), label + ": publication and sanitation identities retained")
	return {"ship": actual, "report": report}

func engine_uid(ship: Dictionary) -> String:
	for item in ship.moduleCondition.items.values():
		if str(item.location) == "engine": return str(item.itemUid)
	return ""

func exact_records043(source: Dictionary) -> void:
	var condition: Dictionary = source.moduleCondition.duplicate(true)
	var proof: Dictionary = {}
	var before: PackedByteArray = var_to_bytes(condition)
	var first: Dictionary = Records._tick_records_exact(condition, proof)
	check(var_to_bytes(first) == var_to_bytes(Core._records(condition)) and var_to_bytes(condition) == before, "043 exact memo seeds only a full read-only validation")
	check(first.is_read_only() and first.locations.is_read_only(), "043 borrowed validation and locations are immutable")
	check(is_same(Records._tick_records_exact(condition, proof), first), "043 unchanged exact owner reuses validation")
	var copy: Dictionary = condition.duplicate(true)
	var copied: Dictionary = Records._tick_records_exact(copy, proof)
	check(not is_same(copied, first) and is_same(proof.condition, copy), "043 equal copy cannot reuse another condition reference")
	condition = copy
	condition.nextItemSeq = int(condition.nextItemSeq) + 1
	var changed: Dictionary = Records._tick_records_exact(condition, proof)
	check(not is_same(changed, copied) and var_to_bytes(changed) == var_to_bytes(Core._records(condition)), "043 valid metadata change receives fresh full proof")
	var valid: Dictionary = condition.duplicate(true)
	var uid: String = engine_uid({"moduleCondition": condition})
	for mutation in ["birth_type", "serial", "unknown", "item_uid", "type_id", "cause", "status", "status_type", "watermark"]:
		condition = valid.duplicate(true)
		Records._tick_records_exact(condition, proof)
		match mutation:
			"birth_type": condition.birthNamespace = StringName(condition.birthNamespace)
			"serial": condition.nextItemSeq = -1
			"unknown": condition["extra"] = true
			"item_uid": condition.items[uid].itemUid = "wrong-physical-part"
			"type_id": condition.items[uid].typeId = "invalid type"
			"cause": condition.items[uid].cause = "\u00e9"
			"status": condition.items[uid].status = "disabled"
			"status_type": condition.items[uid].typeId = StringName(condition.items[uid].typeId)
			"watermark": condition.legacyEngineSynced = 0.1
		before = var_to_bytes(condition)
		var expected: Dictionary = Core._records(condition)
		var refused: Dictionary = Records._tick_records_exact(condition, proof)
		check(not bool(expected.ok) and var_to_bytes(refused) == var_to_bytes(expected) and proof.is_empty(), "043 fresh exact refusal " + mutation)
		check(var_to_bytes(condition) == before, "043 refusal leaves condition untouched " + mutation)
		check(var_to_bytes(Records._tick_records_exact(condition, proof)) == var_to_bytes(expected) and proof.is_empty(), "043 refusal is never retained " + mutation)
	condition = valid.duplicate(true)
	Records._tick_records_exact(condition, proof)
	condition.items[uid].hp = 0.5
	condition.items[uid].status = "damaged"
	condition.items[uid].cause = "Exact live change"
	condition.legacyEngineSynced = 0.5
	var damaged: Dictionary = Records._tick_records_exact(condition, proof)
	check(bool(damaged.ok) and damaged.engineHp == 0.5 and var_to_bytes(damaged) == var_to_bytes(Core._records(condition)), "043 same-reference real damage refreshes engine proof")

func live_records043(source: Dictionary) -> void:
	exact_records043(source)
	for priority in Core.PRIORITIES:
		var active: Dictionary = source.duplicate(true)
		active.hp -= 25.0
		active.water = 25.0
		active.fire = 12.0
		active.wounded = 1.0
		active.policy = "repair"
		active.moduleCondition.repairPriority = priority
		check(bool(Core.apply_component_damage(active.moduleCondition, {"itemUid": engine_uid(active), "loss": 0.5, "cause": "043 burning machinery"}).ok), "043 real damaged engine " + str(priority))
		Records.publish(active)
		var result: Dictionary = pair("043 burning finite repair " + str(priority), active, 1.0 / 30.0, false, {"inCombat": true}, 3)
		check(result.ship.fire != active.fire and result.ship.hp != active.hp and result.report.usedWork > 0.0, "043 real fire, hull and crew work " + str(priority))
		if priority == "auto":
			check(result.report.suppressedFire > 0.0 and result.report.repairedModuleHp == 0.0 and result.report.repairedHullHp == 0.0, "043 auto spends finite crew on fire first")
		elif priority == "hull":
			check(result.report.repairedHullHp > 0.0 and result.report.suppressedFire == 0.0, "043 hull priority spends the same crew before fire")
		else:
			check(result.report.repairedModuleHp > 0.0 and result.report.suppressedFire == 0.0, "043 machinery priority spends the same crew before fire " + str(priority))
		check(result.ship.ammo == active.ammo and result.ship.crew == active.crew and result.ship.wounded == active.wounded, "043 crew/ammunition conserved " + str(priority))
		active.breaches = [{"area": 3.0, "section": "bow"}]
		pair("043 breach fallback " + str(priority), active, 1.0 / 30.0, false, {"priority": priority}, 2)
	var limited: Dictionary = source.duplicate(true)
	limited.water = 5.0; limited.fire = 6.0; limited.fuel = 0.00001; limited.supplies = 0.00001
	limited.breaches = [{"area": 1.0, "section": "bow"}]
	pair("043 finite pump fuel and repair supplies", limited, 0.2, false, {"inCombat": true}, 2)
	limited = source.duplicate(true); limited.fire = 0.001; limited.crew = 0.0
	pair("043 fire with no crew", limited, 1.0 / 30.0, false, {"inCombat": true}, 2)
	var live: Dictionary = source.duplicate(true)
	var cache: Dictionary = {}
	Damage.tick_ship(live, 0.0, {"inCombat": true}, cache)
	for _i in range(Damage.OWNER_CACHE_FRAMES - 1): Damage.begin_frame_cache(cache, [live])
	check(not Damage._cached_entry(live, cache).is_empty(), "043 owner proof survives only its original eleven following frames")
	Damage.begin_frame_cache(cache, [live])
	check(cache.is_empty(), "043 owner proof still expires on frame twelve")
	Damage.tick_ship(live, 0.0, {"inCombat": true}, cache)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 43040
	Damage.apply_hit(live, {"damage": 10.0, "kind": "rocket", "section": "engine"}, rng, cache)
	check(cache.is_empty() and live.hp < source.hp and live.fire > 0.0, "043 actual hit immediately invalidates proof and changes real hull/fire")
	check(var_to_bytes(Damage.get_status_cached(live, cache)) == var_to_bytes(Damage.get_status(live)), "043 public status is fresh after the actual hit")
	Damage.tick_ship(live, 1.0 / 60.0, {"inCombat": true}, cache)
	var state: PackedByteArray = var_to_bytes(live)
	var status: Dictionary = Damage.get_status_cached(live, cache)
	var status_before: PackedByteArray = var_to_bytes(Damage.get_status_cached(live, cache))
	status.weaponFactors["poison"] = 123.0
	status.events.append("poison")
	check(var_to_bytes(live) == state and var_to_bytes(Damage.get_status_cached(live, cache)) == status_before, "043 public nested results stay detached from condition and cache")
	check(not bool(Damage.runtime_profile043().enabled) and not bool(Records.runtime_profile043().enabled), "043 runtime profiling stays disabled by default")

func fresh_records051(source: Dictionary) -> void:
	# Public references always select full Core validation. old_tick above never
	# receives records_validate, so its complete tick comparison stays independent.
	for mutation in ["same", "copy", "typed_serial", "typed_birth", "damage", "engine", "pumps", "loadout", "foreign"]:
		var live: Dictionary = source.duplicate(true)
		var proof: Dictionary = {}
		var validate: Callable = Records._tick_records_exact.bind(proof)
		var original: Dictionary = validate.call(live.moduleCondition)
		match mutation:
			"copy": live.moduleCondition = live.moduleCondition.duplicate(true)
			"typed_serial": live.moduleCondition.nextItemSeq = float(live.moduleCondition.nextItemSeq) if live.moduleCondition.nextItemSeq is int else int(live.moduleCondition.nextItemSeq)
			"typed_birth": live.moduleCondition.birthNamespace = StringName(live.moduleCondition.birthNamespace)
			"damage":
				check(bool(Core.apply_component_damage(live.moduleCondition, {"itemUid": engine_uid(live), "loss": 0.5, "cause": "051 fresh snapshot"}).ok), "051 real component damage")
			"engine": live.engine = -1.0
			"pumps": live.baseSpec.pumps = 0.0 if float(live.baseSpec.get("pumps", 0.0)) > 0.0 else 1.0
			"loadout": live.loadout.engine = "other_engine"
			"foreign": live["equipmentCondition"] = {}
		var before: PackedByteArray = var_to_bytes(live)
		var expected_snapshot: Dictionary = Records.snapshot(live)
		var actual_snapshot: Dictionary = Records._snapshot_with_records(live, validate)
		var expected_info: Dictionary = EquipmentDamage.inspect_owner(live)
		var actual_info: Dictionary = EquipmentDamage._inspect_owner_with_records(live, validate)
		check(var_to_bytes(actual_snapshot) == var_to_bytes(expected_snapshot) and var_to_bytes(actual_info) == var_to_bytes(expected_info) and var_to_bytes(live) == before, "051 fresh snapshot/inspection matches full public guards read-only " + mutation)
		if mutation in ["copy", "typed_serial", "damage"]:
			check(not is_same(proof.records, original) and is_same(proof.condition, live.moduleCondition), "051 changed identity/value/type rebuilds exact proof " + mutation)
		elif mutation == "typed_birth":
			check(proof.is_empty(), "051 fresh refusal retains no record proof")
		else:
			check(is_same(proof.records, original), "051 unchanged condition keeps its exact proof " + mutation)
		if mutation in ["typed_birth", "engine", "pumps", "loadout", "foreign"]:
			check(not bool(actual_info.ok), "051 memo never bypasses owner refusal " + mutation)
		if mutation == "same":
			actual_snapshot.installed.engine.hp = 0.0
			actual_info.snapshot.installedItems.clear()
			check(var_to_bytes(Records._snapshot_with_records(live, validate)) == var_to_bytes(expected_snapshot) and var_to_bytes(EquipmentDamage._inspect_owner_with_records(live, validate)) == var_to_bytes(expected_info) and var_to_bytes(live) == before, "051 fresh results stay detached from owner and later snapshots")

func phase_reads043(source: Dictionary) -> void:
	var live: Dictionary = source.duplicate(true)
	var cache: Dictionary = {}
	Damage.tick_ship(live, 0.0, {"inCombat": true}, cache)
	var expected_info: Dictionary = Damage.inspect_owner_cached(live, cache).duplicate(true)
	var expected_status: Dictionary = Damage.get_status_cached(live, cache)
	var before: PackedByteArray = var_to_bytes(live)
	var phase = Damage._begin_battle_phase043(cache)
	Damage.set_runtime_profile043(true)
	Damage.reset_runtime_profile043()
	var equal: bool = true
	for _i in range(16):
		equal = equal and var_to_bytes(Damage._inspect_owner_in_phase043(live, phase)) == var_to_bytes(expected_info)
		equal = equal and var_to_bytes(Damage._read_status_in_phase043(live, phase)) == var_to_bytes(expected_status)
	var counters: Dictionary = Damage.runtime_profile043().cache
	check(equal and var_to_bytes(live) == before, "043 phase borrows exact owner/status without changing the boat")
	check(counters.cacheLookups == 1 and counters.phaseLookups == 32 and counters.phaseHits == 31, "043 repeated private consumers perform one full owner guard in the phase")
	Damage.set_runtime_profile043(false)
	Damage.reset_runtime_profile043()
	live.fuel = 0.0 # Owned motion may exhaust fuel while the phase is open.
	check(var_to_bytes(Damage._read_status_in_phase043(live, phase)) == var_to_bytes(Damage.get_status(live)), "043 same-phase fuel exhaustion refreshes every status factor")
	check(Damage._read_status_in_phase043(live, phase).pump == 0.0, "043 no pump work from exhausted fuel")
	check(var_to_bytes(Certification.motion(live, 1.0 / 60.0, 0.7, 0.8, false, phase)) == var_to_bytes(Certification.motion(live, 1.0 / 60.0, 0.7, 0.8, false, cache)), "043 non-Dictionary phase handle reaches the checked motion path")
	check(EquipmentCombat.mount_cache_key(live, {}, phase) == EquipmentCombat.mount_cache_key(live, {}, cache), "043 equipment consumers use the same checked mount factors")
	var copy: Dictionary = live.duplicate(true)
	copy.moduleCondition.nextItemSeq = 0
	check(not bool(Damage._inspect_owner_in_phase043(copy, phase).ok), "043 corrupt same-ID copy cannot borrow the real owner's proof")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 43043
	Damage.apply_hit(live, {"damage": 10.0, "kind": "rocket", "section": "engine"}, rng, cache)
	check(cache.is_empty() and live.hp < source.hp and live.fire > 0.0, "043 actual hit invalidates the source cache during a borrow")
	check(var_to_bytes(Damage._read_status_in_phase043(live, phase)) == var_to_bytes(Damage.get_status(live)), "043 source-entry invalidation prevents stale same-phase damage factors")
	Damage.tick_ship(live, 0.0, {"inCombat": true}, phase)
	Damage._read_status_in_phase043(live, phase)
	var valid_condition: Dictionary = live.moduleCondition.duplicate(true)
	live.moduleCondition.nextItemSeq = 0
	check(not bool(Damage.get_status_cached(live, phase).equipmentOk) and cache.is_empty(), "043 public cache read keeps full mutation guards even with a phase handle")
	check(not bool(Damage._read_status_in_phase043(live, phase).equipmentOk), "043 public refusal also invalidates a borrowed entry")
	Damage._end_battle_phase043(phase)
	check(not phase.active and phase.entries.is_empty(), "043 closed handle retains no borrowed projections")
	live.moduleCondition = valid_condition
	Damage.tick_ship(live, 0.0, {"inCombat": true}, cache)
	check(bool(Core.apply_component_damage(live.moduleCondition, {"itemUid": engine_uid(live), "loss": 0.1, "cause": "Between-phase write"}).ok), "043 real between-phase component damage")
	Records.publish(live)
	check(var_to_bytes(Damage._read_status_in_phase043(live, phase)) == var_to_bytes(Damage.get_status(live)), "043 closed handle returns to full external-write validation")

func battle_state043(st: Dictionary) -> Dictionary:
	var value: Dictionary = st.duplicate(true)
	value.erase("rng") # Its exact state is compared separately.
	for key in ["aiUs", "phaseUs", "planningDetailUs"]:
		value.tactical.metrics.erase(key) # Only measured wall clocks differ.
	return value

func phase_battle043(source: Dictionary) -> void:
	# Same production update with only the borrow constructor bypassed. All
	# consumers then use their original fully guarded path; no combat math mirror.
	var code: String = FileAccess.get_file_as_string("res://scripts/battle.gd")
	var needle: String = "Damage._begin_battle_phase043(frame_cache)"
	check(code.count(needle) == 1, "043 one explicit Battle phase constructor")
	var owned_needle: String = "Damage._create_battle_owned051(st.ships,st.tactical.damageCache)"
	check(code.count(owned_needle) == 1, "051 one encounter context at successful battle creation")
	# Keep the original whole-state/public-cache comparison for the 043 seam.
	# The separate 051 arm below then enables the new lifetime on the same battle.
	code = code.replace(owned_needle,"null")
	var borrowed: GDScript = GDScript.new()
	borrowed.source_code = code
	if borrowed.reload() != OK:
		check(false, "043 borrowed reference update compiles"); return
	var reference: GDScript = GDScript.new()
	reference.source_code = code.replace(needle, "frame_cache")
	if reference.reload() != OK:
		check(false, "043 fully guarded reference update compiles"); return
	var boats: Array = []
	for id in ["phase-player", "phase-enemy"]:
		var boat: Dictionary = Damage.create_ship(source.baseSpec, {"id": id, "uid": id})
		Refit.ensure(boat, source.baseSpec)
		var seeded: Dictionary = Records.initialize(boat, {"base": source.baseSpec, "loadout": boat.loadout, "catalog": Refit.catalog(), "identity": id, "knownUids": []})
		check(bool(seeded.ok), "043 phase battle canonical birth " + id)
		if not bool(seeded.ok): return
		boats.append(boat)
	var a: Dictionary = borrowed.create({"fleet": [boats[0]], "enemyFleet": [boats[1]], "seed": 43043, "islands": []})
	check(a.result == null and a.ships.size() == 2, "043 bounded actual battle opens")
	if a.result != null or a.ships.size() != 2: return
	for i in range(2):
		a.ships[i].x = 1000.0 + 160.0 * i; a.ships[i].y = 850.0
		a.ships[i].vx = 12.0; a.ships[i].vy = 0.0; a.ships[i].angle = PI * i
	a.ships[0].water = 25.0; a.ships[0].breaches = [{"area": 3.0, "section": "bow"}]
	a.ships[0].fire = 2.0; a.ships[0].fuel = 0.00021; a.ships[0].policy = "repair"
	check(bool(Core.apply_component_damage(a.ships[0].moduleCondition, {"itemUid": engine_uid(a.ships[0]), "loss": 0.5, "cause": "043 phase battle machinery"}).ok), "043 phase battle starts with real engine damage")
	Records.publish(a.ships[0])
	Damage.set_repair_priority(a.ships[0], "engine")
	a.projectiles.append({"x": 1140.0, "y": 850.0, "px": 1140.0, "py": 850.0, "vx": 2400.0, "vy": 0.0, "team": "player", "damage": 12.0, "kind": "bullet", "penetration": 20.0, "life": 1.0, "owner": str(a.ships[0].id), "radius": 2.0})
	var b: Dictionary = a.duplicate(true)
	var rng_copy: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_copy.state = a.rng.state; b.rng = rng_copy
	var hp_before: float = float(a.ships[1].hp)
	var supplies_before: float = float(a.ships[0].supplies)
	var equal: bool = true
	for _i in range(12):
		var input: Dictionary = {"manual": true, "forward": true, "fire": true, "aimX": float(a.ships[1].x), "aimY": float(a.ships[1].y)}
		borrowed.update(a, 1.0 / 60.0, input)
		reference.update(b, 1.0 / 60.0, input)
		for i in range(2):
			# Public boundary guards must agree too, including any newly added keys.
			equal = equal and var_to_bytes(Damage.get_status_cached(a.ships[i], a.tactical.damageCache)) == var_to_bytes(Damage.get_status_cached(b.ships[i], b.tactical.damageCache))
		equal = equal and a.rng.state == b.rng.state and var_to_bytes(battle_state043(a)) == var_to_bytes(battle_state043(b))
	check(equal, "043 every full battle state/cache, RNG, shot, contact, order and equipment result equals fully guarded reads")
	check(a.ships[0].fuel == 0.0 and a.ships[0].supplies < supplies_before and a.ships[1].hp < hp_before, "043 actual battle covers exhausted fuel, finite repair and a swept projectile hit")
	a["_damageOwned051"] = Damage._create_battle_owned051(a.ships,a.tactical.damageCache)
	equal = true
	for _i in range(14):
		var input: Dictionary = {"manual":true,"forward":true,"fire":true,"aimX":float(a.ships[1].x),"aimY":float(a.ships[1].y)}
		Battle.update(a,1.0/60.0,input)
		reference.update(b,1.0/60.0,input)
		for i in range(2):
			equal = equal and var_to_bytes(Damage.get_status(a.ships[i])) == var_to_bytes(Damage.get_status(b.ships[i]))
		var actual: Dictionary = battle_state043(a)
		var expected: Dictionary = battle_state043(b)
		# Only derived validation caches/lifetime handles differ in this arm.
		# The original cache-equality assertion above remains intact.
		for state in [actual,expected]:
			state.erase("_damageOwned051"); state.tactical.erase("damageCache")
		equal = equal and a.rng.state == b.rng.state and var_to_bytes(actual) == var_to_bytes(expected)
	check(equal, "051 every authoritative battle packet/status/RNG equals the public reference past frame twelve")
	var owned = a._damageOwned051
	var copied: Dictionary = a.duplicate(true)
	check(Damage._battle_owned_for051(copied._damageOwned051,copied.ships,copied.tactical.damageCache) == null and owned.active, "051 copied encounter cannot borrow or close the original authority")
	a.result = "retreated"
	Battle.update(a,1.0/60.0)
	check(not owned.active and owned.entries.is_empty(), "051 actual battle result tears down every owned proof")

func owned_context051(source: Dictionary) -> void:
	var live: Dictionary = source.duplicate(true)
	var expected: Dictionary = source.duplicate(true)
	var ships: Array = [live]
	var cache: Dictionary = {}
	var owned = Damage._create_battle_owned051(ships,cache)
	var phase = Damage._begin_battle_phase043(cache)
	var before: PackedByteArray = var_to_bytes(live)
	Damage._bind_battle_owned051(phase,owned,ships,cache)
	var entry: Dictionary = Damage._battle_entry051(live,owned)
	check(not entry.is_empty() and var_to_bytes(live) == before, "051 private admission fully validates without changing its boat")
	if entry.is_empty(): return
	check(entry.descriptor.is_read_only() and entry.descriptor.items.is_read_only() and entry.descriptor.spec.is_read_only() and entry.info.snapshot.installed.engine.is_read_only(), "051 descriptor and detached equipment projections are deeply immutable")
	var descriptor: Dictionary = entry.descriptor
	var info: Dictionary = entry.info
	Damage._end_battle_phase043(phase)
	var equal: bool = true
	var retained_status: Dictionary = {}
	var borrowed_reports: bool = true
	for _i in range(14):
		Damage.begin_frame_cache(cache,ships)
		phase = Damage._begin_battle_phase043(cache)
		Damage._bind_battle_owned051(phase,owned,ships,cache)
		var report: Dictionary = Damage._tick_ship_in_battle051(live,1.0/60.0,phase)
		var reference: Dictionary = Damage.tick_ship(expected,1.0/60.0,{"inCombat":true})
		equal = equal and var_to_bytes(live) == var_to_bytes(expected) and var_to_bytes(report) == var_to_bytes(reference)
		borrowed_reports = borrowed_reports and is_same(report,entry.status) and report.is_read_only() and not reference.is_read_only()
		borrowed_reports = borrowed_reports and not live.refitLocker.is_read_only() and not is_same(live.refitLocker,entry.projection.refitLocker)
		reference.weaponFactor = -1.0 # Public tick reports remain detached and mutable.
		borrowed_reports = borrowed_reports and entry.status.weaponFactor >= 0.0
		if _i == 0: retained_status = entry.status
		Damage._end_battle_phase043(phase)
	entry = Damage._battle_entry051(live,owned)
	check(equal and is_same(entry.descriptor,descriptor) and is_same(entry.info,info) and int(entry.generation) == 0, "051 unchanged private proof survives frame twelve with exact public boat/report parity")
	check(entry.healthy and is_same(entry.status,retained_status) and entry.status.is_read_only() and int(entry.projectionGeneration) == int(entry.generation), "051 healthy ticks reuse the immutable status and current projection past frame twelve")
	check(borrowed_reports, "051 healthy Battle borrows immutable status; public reports and live inventory stay detached and mutable")
	var previous_entry: Dictionary = entry
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var old_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 51040; old_rng.seed = rng.seed
	var events: Array = Damage._apply_hit_in_battle051(live,{"damage":12.0,"kind":"rocket","section":"engine"},rng,cache,owned)
	var old_events: Array = Damage.apply_hit(expected,{"damage":12.0,"kind":"rocket","section":"engine"},old_rng)
	entry = Damage._battle_entry051(live,owned)
	check(not entry.is_empty() and not previous_entry.valid and not is_same(entry.descriptor,descriptor) and int(entry.generation) == int(previous_entry.generation)+1, "051 successful public hit re-admits after revoking the old generation")
	check(var_to_bytes(live) == var_to_bytes(expected) and events == old_events and rng.state == old_rng.state and live.fire > 0.0, "051 official hit, equipment loss, fire and RNG equal public reference")
	Damage.set_policy(live,"repair"); Damage.set_policy(expected,"repair")
	Damage.set_repair_priority(live,"engine"); Damage.set_repair_priority(expected,"engine")
	live.engine = 0.5; expected.engine = live.engine # Real legacy absorption, below the jury cap.
	live.fuel = 0.00001; expected.fuel = live.fuel
	live.shoreCrew = 1.0; expected.shoreCrew = 1.0
	var supplies: float = float(live.supplies)
	var used: float = 0.0
	for _i in range(3):
		phase = Damage._begin_battle_phase043(cache)
		Damage._bind_battle_owned051(phase,owned,ships,cache)
		var report: Dictionary = Damage._tick_ship_in_battle051(live,1.0/30.0,phase)
		var reference: Dictionary = Damage.tick_ship(expected,1.0/30.0,{"inCombat":true})
		used += float(report.usedSupplies)
		check(var_to_bytes(live) == var_to_bytes(expected) and var_to_bytes(report) == var_to_bytes(reference) and var_to_bytes(Damage._read_status_in_phase043(live,phase)) == var_to_bytes(Damage.get_status(expected)), "051 live fire/flood/crew/repair/report parity " + str(_i))
		Damage._end_battle_phase043(phase)
	check(used > 0.0 and live.supplies < supplies and live.fuel == 0.0 and live.crew == expected.crew, "051 real finite supplies, exhausted fuel and crew remain live")
	entry = Damage._battle_entry051(live,owned)
	check(not entry.is_empty() and int(entry.generation) > 1 and entry.infoGeneration == entry.generation, "051 official fire/repair/legacy writes refresh derived generations before reuse")
	before = var_to_bytes(live)
	var refused: Array = Damage._apply_hit_in_battle051(live,{"damage":1.0,"impactX":0.0},rng,cache,owned)
	check(refused.is_empty() and not entry.valid and Damage._battle_entry051(live,owned).is_empty() and var_to_bytes(live) == before, "051 failed public hit drops all authority without keeping a stale projection")
	Damage._admit_battle_owner051(owned,live)
	var copy: Dictionary = live.duplicate(true)
	copy.moduleCondition.nextItemSeq = 0
	phase = Damage._begin_battle_phase043(cache)
	Damage._bind_battle_owned051(phase,owned,ships,cache)
	check(Damage._battle_entry051(copy,owned).is_empty() and not bool(Damage._tick_ship_in_battle051(copy,0.0,phase).equipmentOk), "051 same-ID corrupt copy takes the fully checked refusal path")
	check(not Damage._battle_entry051(live,owned).is_empty(), "051 copy refusal leaves the exact original owner authoritative")
	live.spec = live.spec.duplicate(true)
	check(Damage._battle_entry051(live,owned).is_empty(), "051 spec replacement revokes authority rather than reusing a stale descriptor")
	check(var_to_bytes(Damage._tick_ship_in_battle051(live,0.0,phase)) == var_to_bytes(Damage.tick_ship(expected,0.0,{"inCombat":true})), "051 unsupported writer uses fully checked tick fallback")
	check(var_to_bytes(Damage._tick_ship_in_battle051(live,0.0,phase,false)) == var_to_bytes(Damage.tick_ship(expected,0.0,{"inCombat":true})), "051 compact ignored-result opt-in preserves the public fallback report after revocation")
	Damage._end_battle_phase043(phase)
	Damage._close_battle_owned051(owned)
	check(not owned.active and owned.entries.is_empty() and owned.ships.is_empty() and owned.source.is_empty(), "051 closure releases proofs and encounter references")
	var bounded_ships: Array = []
	for i in range(Damage.OWNER_CACHE_LIMIT+1):
		var ship: Dictionary = source.duplicate(true)
		ship.id = "owned051-%d" % i
		bounded_ships.append(ship)
	var bounded_cache: Dictionary = {}
	var bounded = Damage._create_battle_owned051(bounded_ships,bounded_cache)
	phase = Damage._begin_battle_phase043(bounded_cache)
	Damage._bind_battle_owned051(phase,bounded,bounded_ships,bounded_cache)
	check(bounded.entries.size() == Damage.OWNER_CACHE_LIMIT and Damage._battle_entry051(bounded_ships[-1],bounded).is_empty(), "051 encounter proof is bounded to 128 entries; overflow stays fully checked")
	var overflow: Dictionary = bounded_ships[-1].duplicate(true)
	check(var_to_bytes(Damage._tick_ship_in_battle051(bounded_ships[-1],0.0,phase)) == var_to_bytes(Damage.tick_ship(overflow,0.0,{"inCombat":true})), "051 overflow uses the unchanged public tick")
	var departed: Dictionary = bounded_ships.pop_front()
	Damage._bind_battle_owned051(phase,bounded,bounded_ships,bounded_cache)
	check(bounded.entries.size() == Damage.OWNER_CACHE_LIMIT-1 and Damage._battle_entry051(departed,bounded).is_empty(), "051 removal releases its exact owner proof")
	Damage._end_battle_phase043(phase)
	Damage._close_battle_owned051(bounded)

func owned_phase_reads051(source: Dictionary) -> void:
	var live: Dictionary = source.duplicate(true)
	var ships: Array = [live]
	var cache: Dictionary = {}
	var owned = Damage._create_battle_owned051(ships,cache)
	var phase = Damage._begin_battle_phase043(cache)
	Damage._bind_battle_owned051(phase,owned,ships,cache)
	var slot: String = Damage._cache_slot_key(live)
	var entry: Dictionary = owned.entries.get(slot,{})
	var expected_info: Dictionary = EquipmentDamage.inspect_owner(live)
	var expected_status: Dictionary = Damage.get_status(live)
	var before: PackedByteArray = var_to_bytes(live)
	Damage.set_runtime_profile043(true)
	Damage.reset_runtime_profile043()
	var equal: bool = true
	for _i in range(16):
		equal = equal and var_to_bytes(Damage._inspect_owner_in_phase043(live,phase)) == var_to_bytes(expected_info)
		equal = equal and var_to_bytes(Damage._read_status_in_phase043(live,phase)) == var_to_bytes(expected_status)
	var counters: Dictionary = Damage.runtime_profile043().cache
	check(equal and not entry.is_empty() and is_same(phase.entries.get(slot),entry) and var_to_bytes(live) == before, "051 owned phase borrows the exact immutable info/status without changing its boat")
	check(counters.phaseLookups == 32 and counters.phaseHits == 31 and counters.cacheLookups == 0, "051 repeated owned phase reads validate once without the public cache")
	Damage.set_runtime_profile043(false)
	Damage.reset_runtime_profile043()
	if entry.is_empty():
		Damage._end_battle_phase043(phase); Damage._close_battle_owned051(owned); return
	live.fuel = 0.0; live.wounded = 1.0; live.fire = 2.0
	var status: Dictionary = Damage._read_status_in_phase043(live,phase)
	check(status.pump == 0.0 and var_to_bytes(status) == var_to_bytes(Damage.get_status(live)), "051 owned phase hits keep fuel-zero, crew and fire immediately live")
	var generation: int = int(entry.generation)
	live.engine = 0.5
	var absorbed: Dictionary = EquipmentDamage._battle_absorb051(live,entry)
	Records._battle_publish051(live,entry)
	check(bool(absorbed.ok) and int(entry.generation) > generation and int(entry.infoGeneration) != int(entry.generation), "051 reachable legacy absorption dirties the already borrowed generation")
	check(var_to_bytes(Damage._read_status_in_phase043(live,phase)) == var_to_bytes(Damage.get_status(live)) and entry.infoGeneration == entry.generation, "051 dirty owned phase refreshes equipment info before live status")
	generation = int(entry.generation)
	Damage.set_repair_priority(live,"engine")
	status = Damage._read_status_in_phase043(live,phase)
	check(int(entry.generation) > generation and status.repairPriority == "engine" and var_to_bytes(status) == var_to_bytes(Damage.get_status(live)), "051 official priority setter refreshes a borrowed generation before reuse")
	var copy: Dictionary = live.duplicate(true)
	copy.moduleCondition.nextItemSeq = 0
	check(not bool(Damage._read_status_in_phase043(copy,phase).equipmentOk) and is_same(owned.entries.get(slot),entry) and entry.valid, "051 same-ID corrupt copy cannot borrow or revoke the real phase owner")
	Damage.tick_ship(live,0.0,{"inCombat":true},phase)
	status = Damage._read_status_in_phase043(live,phase)
	check(not entry.valid and not owned.entries.has(slot) and is_same(phase.entries.get(slot),cache.get(slot)) and var_to_bytes(status) == var_to_bytes(Damage.get_status(live)), "051 public tick revokes the owned borrow and uses checked source-cache proof")
	Damage._admit_battle_owner051(owned,live)
	Damage._read_status_in_phase043(live,phase)
	entry = owned.entries.get(slot,{})
	check(not entry.is_empty() and is_same(phase.entries.get(slot),entry) and not is_same(cache.get(slot),entry), "051 re-admission replaces the public fallback with exact owned entry membership")
	var condition: Dictionary = live.moduleCondition.duplicate(true)
	live.moduleCondition.nextItemSeq = 0
	check(not bool(Damage.get_status_cached(live,phase).equipmentOk) and not bool(Damage._read_status_in_phase043(live,phase).equipmentOk) and not bool(entry.get("valid",false)) and not owned.entries.has(slot), "051 public refusal revokes a warmed owned phase instead of returning stale status")
	live.moduleCondition = condition
	Damage._admit_battle_owner051(owned,live)
	Damage._read_status_in_phase043(live,phase)
	entry = owned.entries.get(slot,{})
	Damage._close_battle_owned051(owned)
	live.fuel = 1.0
	check(not bool(entry.get("valid",false)) and var_to_bytes(Damage._read_status_in_phase043(live,phase)) == var_to_bytes(Damage.get_status(live)), "051 encounter closure rejects an already borrowed phase entry")
	Damage._end_battle_phase043(phase)
	live.fuel = 0.0
	check(not phase.active and phase.entries.is_empty() and var_to_bytes(Damage._read_status_in_phase043(live,phase)) == var_to_bytes(Damage.get_status(live)), "051 phase closure clears all borrows and preserves checked live reads")

func sealed_phase_reads051(source: Dictionary) -> void:
	var live: Dictionary = source.duplicate(true)
	var ships: Array = [live]
	var cache: Dictionary = {}
	var owned = Damage._create_battle_owned051(ships,cache)
	var phase = Damage._begin_battle_phase043(cache)
	Damage._bind_battle_owned051(phase,owned,ships,cache)
	Damage._read_status_in_phase043(live,phase)
	live.hp -= 4.0; live.water = 3.0; live.fire = 2.0; live.wounded = 1.0
	live.breaches = [{"area":2.0,"section":"bow"}]; live.shoreCrew = 0.5
	Damage.set_policy(live,"repair")
	check(not phase.readsSealed051 and var_to_bytes(Damage._read_status_in_phase043(live,phase)) == var_to_bytes(Damage.get_status(live)), "051 default unsealed owned phase retains immediate raw scalar/policy/crew reads")
	var expected: Dictionary = live.duplicate(true)
	Damage._tick_ship_in_battle051(live,1.0/60.0,phase)
	Damage.tick_ship(expected,1.0/60.0,{"inCombat":true})
	Damage._seal_battle_reads051(phase)
	var slot: String = Damage._cache_slot_key(live)
	var entry: Dictionary = owned.entries.get(slot,{})
	check(phase.readsSealed051 and not entry.is_empty() and var_to_bytes(live) == var_to_bytes(expected), "051 seal follows a real finite fire/flood/repair prepass with unchanged numerical state")
	if entry.is_empty():
		Damage._end_battle_phase043(phase); Damage._close_battle_owned051(owned); return
	var frozen: Dictionary = entry.status
	var before: PackedByteArray = var_to_bytes(live)
	var equal: bool = true
	var status: Dictionary = {}
	Damage.set_runtime_profile043(true)
	Damage.reset_runtime_profile043()
	for _i in range(16):
		status = Damage._read_status_in_phase043(live,phase)
		equal = equal and is_same(status,frozen) and status.is_read_only() and var_to_bytes(status) == var_to_bytes(Damage.get_status(expected))
	var direct_info: Dictionary = Damage._inspect_owner_in_phase043(live,phase)
	var direct_counts: Dictionary = Damage.runtime_profile043().cache
	Damage.set_runtime_profile043(false)
	Damage.reset_runtime_profile043()
	check(equal and var_to_bytes(live) == before, "051 repeated sealed reads borrow exact post-prepass status without changing live hull/crew/stores")
	check(is_same(direct_info,entry.info) and var_to_bytes(direct_info) == var_to_bytes(EquipmentDamage.inspect_owner(live)) and direct_counts.phaseEntryCalls == 0 and direct_counts.sealedStatusHits == 16, "051 sealed owner info/status use the prepared authoritative map without a second phase-entry validation")
	live.fuel = 0.0
	status = Damage._read_status_in_phase043(live,phase)
	check(status.pump == 0.0 and not is_same(status,frozen) and var_to_bytes(status) == var_to_bytes(Damage.get_status(live)), "051 sealed reads immediately refresh fuel exhaustion and pump factors")
	live.fuel = 1.0
	check(var_to_bytes(Damage._read_status_in_phase043(live,phase)) == var_to_bytes(Damage.get_status(live)), "051 sealed fuel-zero guard also refreshes positive fuel restoration")
	var generation: int = int(entry.generation)
	live.engine = 0.5
	var absorbed: Dictionary = EquipmentDamage._battle_absorb051(live,entry)
	Records._battle_publish051(live,entry)
	status = Damage._read_status_in_phase043(live,phase)
	check(bool(absorbed.ok) and int(entry.generation) > generation and entry.infoGeneration == entry.generation and var_to_bytes(status) == var_to_bytes(Damage.get_status(live)), "051 official generation invalidation refreshes sealed equipment status")
	generation = int(entry.generation)
	Damage.set_repair_priority(live,"engine")
	status = Damage._read_status_in_phase043(live,phase)
	check(int(entry.generation) > generation and status.repairPriority == "engine" and var_to_bytes(status) == var_to_bytes(Damage.get_status(live)), "051 official priority change refreshes sealed status before reuse")
	var copy: Dictionary = live.duplicate(true)
	copy.wounded += 0.5; copy.policy = "fight"
	check(var_to_bytes(Damage._read_status_in_phase043(copy,phase)) == var_to_bytes(Damage.get_status(copy)) and is_same(owned.entries.get(slot),entry) and entry.valid, "051 same-ID copy cannot borrow sealed status or revoke the actual owner")
	live.crew -= 0.5; Damage.set_policy(live,"bail")
	Damage.tick_ship(live,0.0,{"inCombat":true},phase)
	check(not entry.valid and not owned.entries.has(slot) and var_to_bytes(Damage._read_status_in_phase043(live,phase)) == var_to_bytes(Damage.get_status(live)), "051 public tick revokes sealed authority before live crew/policy publication")
	Damage._admit_battle_owner051(owned,live)
	Damage._seal_battle_reads051(phase)
	entry = owned.entries.get(slot,{})
	var condition: Dictionary = live.moduleCondition.duplicate(true)
	live.moduleCondition.nextItemSeq = 0
	check(not bool(Damage.get_status_cached(live,phase).equipmentOk) and not bool(Damage._read_status_in_phase043(live,phase).equipmentOk) and not bool(entry.get("valid",false)), "051 public refusal revokes a sealed owner instead of returning stale status")
	live.moduleCondition = condition
	Damage._admit_battle_owner051(owned,live)
	Damage._seal_battle_reads051(phase)
	live.fire += 1.0
	Damage._tick_ship_in_battle051(live,1.0/60.0,phase)
	check(not phase.readsSealed051 and var_to_bytes(Damage._read_status_in_phase043(live,phase)) == var_to_bytes(Damage.get_status(live)), "051 another owned damage tick revokes the sealed read window before writing")
	Damage._seal_battle_reads051(phase)
	Damage._close_battle_owned051(owned)
	live.wounded += 0.5
	check(var_to_bytes(Damage._read_status_in_phase043(live,phase)) == var_to_bytes(Damage.get_status(live)), "051 encounter closure prevents sealed status reuse")
	Damage._end_battle_phase043(phase)
	live.fire += 1.0
	check(not phase.readsSealed051 and not phase.active and phase.entries.is_empty() and var_to_bytes(Damage._read_status_in_phase043(live,phase)) == var_to_bytes(Damage.get_status(live)), "051 phase closure clears sealed authority and preserves fully guarded reads")

func healthy_owned_changes051(source: Dictionary) -> void:
	for change in [
		{"label":"crew and shore labor","fields":{"crew":float(source.crew)-1.0,"shoreCrew":0.5}},
		{"label":"wounds","fields":{"wounded":1.0}},
		{"label":"water","fields":{"water":3.0}},
		{"label":"fire","fields":{"fire":2.0}},
		{"label":"breach","fields":{"breaches":[{"area":2.0,"section":"bow"}]}},
		{"label":"paid hull repair","fields":{"hp":float(source.hp)-5.0,"policy":"repair"}},
		{"label":"empty supplies","fields":{"supplies":0.0}},
		{"label":"fight policy","fields":{"policy":"fight"}},
		{"label":"repair priority","fields":{},"priority":"hull"},
		{"label":"fuel exhaustion","fields":{"fuel":0.00001}},
		{"label":"fuel refill","fields":{"fuel":0.0},"refill":true},
		{"label":"stationary","fields":{"vx":0.0,"vy":0.0}},
		{"label":"moving threshold","fields":{"vx":0.0,"vy":1.001}},
		{"label":"ammunition and cooldown","fields":{"ammo":0.0,"cooldown":0.001}},
		{"label":"negative stores","fields":{"fuel":-1.0,"ammo":-1.0,"cooldown":-0.1}},
		{"label":"legacy engine loss","fields":{"engine":0.5}},
		{"label":"invalid live legacy engine","fields":{"engine":-0.1},"absorbFailure":true},
		{"label":"healthy integer normalization","fields":{"hp":int(source.hp),"crew":int(source.crew),"wounded":0,"water":0,"fire":0,"engine":1,"supplies":3,"ammo":2,"fuel":1,"cooldown":1,"vx":2,"vy":0}},
		{"label":"healthy uneven substeps","fields":{},"dt":0.021},
		{"label":"healthy long-step fuel exhaustion","fields":{"fuel":0.00001},"dt":0.2}
	]:
		var live: Dictionary = source.duplicate(true)
		var expected: Dictionary = source.duplicate(true)
		var compact: Dictionary = source.duplicate(true)
		var compact_ships: Array = [compact]
		var compact_cache: Dictionary = {}
		var compact_owned = Damage._create_battle_owned051(compact_ships,compact_cache)
		var compact_phase = Damage._begin_battle_phase043(compact_cache)
		Damage._bind_battle_owned051(compact_phase,compact_owned,compact_ships,compact_cache)
		var ships: Array = [live]
		var cache: Dictionary = {}
		var owned = Damage._create_battle_owned051(ships,cache)
		var phase = Damage._begin_battle_phase043(cache)
		Damage._bind_battle_owned051(phase,owned,ships,cache)
		var report: Dictionary = Damage._tick_ship_in_battle051(live,0.0,phase)
		var reference: Dictionary = Damage.tick_ship(expected,0.0,{"inCombat":true})
		var equal: bool = var_to_bytes(live) == var_to_bytes(expected) and var_to_bytes(report) == var_to_bytes(reference)
		Damage._tick_ship_in_battle051(compact,0.0,compact_phase,false)
		var compact_equal: bool = not Damage._battle_entry051(compact,compact_owned).is_empty() and var_to_bytes(compact) == var_to_bytes(expected)
		live.merge(change.fields.duplicate(true),true); expected.merge(change.fields.duplicate(true),true)
		compact.merge(change.fields.duplicate(true),true)
		if change.has("priority"):
			Damage.set_repair_priority(live,str(change.priority)); Damage.set_repair_priority(expected,str(change.priority))
			Damage.set_repair_priority(compact,str(change.priority))
		for _i in range(2):
			var dt: float = float(change.get("dt",1.0/30.0))
			report = Damage._tick_ship_in_battle051(live,dt,phase)
			reference = Damage.tick_ship(expected,dt,{"inCombat":true})
			equal = equal and var_to_bytes(live) == var_to_bytes(expected) and var_to_bytes(report) == var_to_bytes(reference)
			equal = equal and var_to_bytes(Damage._read_status_in_phase043(live,phase)) == var_to_bytes(Damage.get_status(expected))
			Damage._tick_ship_in_battle051(compact,dt,compact_phase,false)
			Damage._seal_battle_reads051(compact_phase)
			compact_equal = compact_equal and var_to_bytes(compact) == var_to_bytes(expected) and var_to_bytes(Damage._read_status_in_phase043(compact,compact_phase)) == var_to_bytes(Damage.get_status(expected))
			if _i == 0 and bool(change.get("absorbFailure",false)):
				check(not report.equipmentOk and not owned.entries.has(str(live.id)) and not compact_owned.entries.has(str(compact.id)), "051 live legacy absorption failure returns checked status and revokes both owned entries without an unbound callback")
			if _i == 0 and bool(change.get("refill",false)): live.fuel = 1.0; expected.fuel = 1.0; compact.fuel = 1.0
		check(equal, "051 warmed private healthy guard and full public parity: " + str(change.label))
		check(compact_equal and not compact.refitLocker.is_read_only(), "051 compact opt-in preserves complete state and sealed live reads: " + str(change.label))
		Damage._end_battle_phase043(phase)
		Damage._close_battle_owned051(owned)
		Damage._end_battle_phase043(compact_phase)
		Damage._close_battle_owned051(compact_owned)

func idle_owned_repairs051(source: Dictionary) -> void:
	for change in [
		{"label":"idle hull scratch","fields":{"hp":float(source.hp)-3.0}},
		{"label":"uncrewed pump and fuel zero","fields":{"crew":0.0,"water":3.0,"fuel":0.00005}},
		{"label":"paid patch with capped machinery","fields":{"water":3.0,"breaches":[{"area":2.0,"section":"bow"}]}},
		{"label":"paid hull with capped machinery","fields":{"hp":float(source.hp)-3.0,"policy":"repair"}},
		{"label":"jury cap","fields":{},"engineHp":Core.JURY_CAP},
		{"label":"within jury epsilon","fields":{},"engineHp":Core.JURY_CAP-Core.EPS*0.5},
		{"label":"below jury epsilon","fields":{},"engineHp":Core.JURY_CAP-Core.EPS*2.0,"equipmentWrite":true},
		{"label":"real disabled machinery repair","fields":{},"engineHp":0.1,"equipmentWrite":true},
		{"label":"live fire on capped machinery","fields":{"fire":2.0},"equipmentWrite":true}
	]:
		var live: Dictionary = source.duplicate(true)
		live.merge(change.fields.duplicate(true),true)
		if change.has("engineHp"):
			check(bool(Core.apply_component_damage(live.moduleCondition,{"itemUid":engine_uid(live),"loss":1.0-float(change.engineHp),"cause":"051 idle repair boundary"}).ok), "051 exact engine damage setup: " + str(change.label))
		Records.publish(live)
		var expected: Dictionary = live.duplicate(true)
		var compact: Dictionary = live.duplicate(true)
		var compact_ships: Array = [compact]
		var compact_cache: Dictionary = {}
		var compact_owned = Damage._create_battle_owned051(compact_ships,compact_cache)
		var compact_phase = Damage._begin_battle_phase043(compact_cache)
		Damage._bind_battle_owned051(compact_phase,compact_owned,compact_ships,compact_cache)
		var compact_equal: bool = not Damage._battle_entry051(compact,compact_owned).is_empty()
		var ships: Array = [live]
		var cache: Dictionary = {}
		var owned = Damage._create_battle_owned051(ships,cache)
		var phase = Damage._begin_battle_phase043(cache)
		Damage._bind_battle_owned051(phase,owned,ships,cache)
		var entry: Dictionary = Damage._battle_entry051(live,owned)
		check(not entry.is_empty(), "051 exact owned repair admission: " + str(change.label))
		if entry.is_empty():
			Damage._end_battle_phase043(compact_phase); Damage._close_battle_owned051(compact_owned)
			Damage._end_battle_phase043(phase); Damage._close_battle_owned051(owned); continue
		var initial_info: Dictionary = entry.info
		var equal: bool = true
		var used_supplies: float = 0.0
		var module_gain: float = 0.0
		for dt in [0.0,1.0/60.0,1.0/30.0,0.021]:
			var report: Dictionary = Damage._tick_ship_in_battle051(live,float(dt),phase)
			var reference: Dictionary = Damage.tick_ship(expected,float(dt),{"inCombat":true})
			equal = equal and var_to_bytes(live) == var_to_bytes(expected) and var_to_bytes(report) == var_to_bytes(reference)
			equal = equal and var_to_bytes(Damage._read_status_in_phase043(live,phase)) == var_to_bytes(Damage.get_status(expected))
			used_supplies += float(report.usedSupplies)
			module_gain += float(report.repairedModuleHp)
			Damage._tick_ship_in_battle051(compact,float(dt),compact_phase,false)
			Damage._seal_battle_reads051(compact_phase)
			compact_equal = compact_equal and var_to_bytes(compact) == var_to_bytes(expected) and var_to_bytes(Damage._read_status_in_phase043(compact,compact_phase)) == var_to_bytes(Damage.get_status(expected))
		check(equal, "051 owned repair preserves every boat/report/live read at each substep boundary: " + str(change.label))
		check(compact_equal and not compact.refitLocker.is_read_only(), "051 compact canonical math preserves complete state and current sealed status: " + str(change.label))
		check((int(entry.generation) > 0) if bool(change.get("equipmentWrite",false)) else (int(entry.generation) == 0 and is_same(entry.info,initial_info)), "051 only actual equipment writers replace immutable projections: " + str(change.label))
		if str(change.label).begins_with("paid"):
			check(used_supplies > 0.0 and live.supplies < source.supplies and module_gain == 0.0, "051 patch/hull keep finite material debit without phantom machinery work: " + str(change.label))
		elif change.has("engineHp") and bool(change.get("equipmentWrite",false)):
			check(module_gain > Core.EPS and used_supplies > 0.0, "051 below-cap machinery still receives real paid repair: " + str(change.label))
		Damage._end_battle_phase043(phase)
		Damage._close_battle_owned051(owned)
		Damage._end_battle_phase043(compact_phase)
		Damage._close_battle_owned051(compact_owned)

func probe(source: Dictionary) -> Dictionary:
	var old_us: int = 0
	var new_us: int = 0
	var checksum: int = 0
	for turn in range(2):
		var boats: Array = [source.duplicate(true), source.duplicate(true)]
		var caches: Array = [{}, {}]
		for variant in ([0, 1] if turn == 0 else [1, 0]):
			var started: int = Time.get_ticks_usec()
			for _i in range(PROBE_TICKS):
				var result: Dictionary = old_tick(boats[variant], 1.0 / 60.0, {"inCombat": true}, caches[variant]) if variant == 0 else Damage.tick_ship(boats[variant], 1.0 / 60.0, {"inCombat": true}, caches[variant])
				checksum += int(bool(result.get("equipmentOk", false)))
			var elapsed: int = Time.get_ticks_usec() - started
			if variant == 0: old_us += elapsed
			else: new_us += elapsed
		check(var_to_bytes(boats[0]) == var_to_bytes(boats[1]) and var_to_bytes(caches[0]) == var_to_bytes(caches[1]), "paired microprobe preserves full state/cache")
	check(checksum == PROBE_TICKS * 4, "all measured ticks accepted")
	return {"ticksPerVariant": PROBE_TICKS * 2, "oldUs": old_us, "newUs": new_us, "note": "Same canonical moving boat, fresh validation each tick, reversed arm order; bounded CPU microprobe, not battle capacity or GPU FPS."}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var base: Dictionary = {}
	for hull in world.HULLS:
		if str(hull.id) == "maiden_dreadnought": base = hull.duplicate(true); break
	check(not base.is_empty(), "representative canonical hull exists")
	if base.is_empty(): finish({}); return
	var ship: Dictionary = Damage.create_ship(base, {"id": "damage-hotpath040", "uid": "damage-hotpath040", "vx": 12.0, "cooldown": 0.1, "refitLocker": {"rapid_gun": 1}})
	Refit.ensure(ship, base)
	var seeded: Dictionary = Records.initialize(ship, {"base": base, "loadout": ship.loadout, "catalog": Refit.catalog(), "identity": str(ship.uid), "knownUids": []})
	check(bool(seeded.ok), "real stock equipment and locker initialize")
	if not bool(seeded.ok): finish({}); return
	for dt in [0.0, 1.0 / 60.0, 1.0 / 30.0, 0.021, 0.2]:
		pair("healthy dt " + str(dt), ship, float(dt), true, {"inCombat": true}, 3)
	pair("without frame cache", ship, 1.0 / 30.0, true, {}, 2, false)
	var altered: Dictionary = ship.duplicate(true)
	altered.fuel = 0.00005
	var exhausted: Dictionary = pair("fuel exhaustion", altered, 1.0 / 30.0, true, {}, 4)
	check(exhausted.ship.fuel == 0.0 and exhausted.ship.cooldown == 0.0, "real fuel/cooldown reach zero")
	altered = ship.duplicate(true); altered.vx = 0.0; altered.shoreCrew = 1.0
	var still: Dictionary = pair("stationary with real shore crew", altered, 0.2, true)
	check(still.ship.fuel == altered.fuel and still.report.crewGuns == altered.crew - altered.shoreCrew, "stationary fuel and available crew remain exact")
	altered = ship.duplicate(true); altered.crew = 0.0; altered.supplies = 0.0; altered.ammo = 0.0; altered.fuel = 0.0
	var empty: Dictionary = pair("empty crew/stores", altered, 0.2, true, {"priority": "hull"})
	check(empty.report.speedFactor == 0.0 and empty.report.weaponFactor == 0.0, "no free crew authority")
	for field in ["hp", "water", "fire", "wounded", "engine", "supplies", "ammo", "cooldown"]:
		altered = ship.duplicate(true)
		altered[field] = {"hp": float(ship.hp) - 10.0, "water": 10.0, "fire": 5.0, "wounded": 1.0, "engine": 0.5, "supplies": -1.0, "ammo": "bad", "cooldown": -0.1}[field]
		pair("fallback " + field, altered, 1.0 / 30.0, false, {"inCombat": true})
	altered = ship.duplicate(true); altered.breaches = [{"area": 2.0, "section": "bow"}]
	pair("actual breach", altered, 1.0 / 30.0, false)
	altered = ship.duplicate(true)
	check(bool(Core.apply_component_damage(altered.moduleCondition, {"itemUid": engine_uid(altered), "loss": 0.5, "cause": "Live tick fixture"}).ok), "real machinery damage succeeds")
	var repaired: Dictionary = pair("actual paid module repair", altered, 0.2, false)
	check(repaired.report.repairedModuleHp > 0.0 and repaired.report.usedSupplies > 0.0 and repaired.ship.supplies < altered.supplies, "fallback performs and debits real repair")
	pair("unknown priority refusal", ship, 0.2, false, {"priority": "unknown"})
	altered = ship.duplicate(true); altered.moduleCondition = {}
	pair("corrupt condition refusal", altered, 0.2, false)
	var cache: Dictionary = {}
	Damage.tick_ship(ship, 0.0, {}, cache)
	var live_before: PackedByteArray = var_to_bytes(ship)
	var copy: Dictionary = ship.duplicate(true)
	copy.wounded = 1.0
	var reference: Dictionary = copy.duplicate(true)
	var actual_status: Dictionary = Damage.tick_ship(copy, 1.0 / 30.0, {}, cache)
	var expected_status: Dictionary = old_tick(reference, 1.0 / 30.0, {}, {})
	check(var_to_bytes(copy) == var_to_bytes(reference) and var_to_bytes(actual_status) == var_to_bytes(expected_status), "same-ID wounded copy cannot reuse live healthy proof")
	check(var_to_bytes(ship) == live_before and is_same(cache[str(ship.id)].shipRef, ship), "copy leaves exact live owner/cache entry intact")
	live_records043(ship)
	fresh_records051(ship)
	phase_reads043(ship)
	phase_battle043(ship)
	owned_context051(ship)
	owned_phase_reads051(ship)
	sealed_phase_reads051(ship)
	healthy_owned_changes051(ship)
	idle_owned_repairs051(ship)
	var measured: Dictionary = probe(ship)
	altered = ship.duplicate(true)
	altered.hp -= 25.0; altered.water = 25.0; altered.fire = 12.0
	altered.policy = "repair"
	altered.breaches = [{"area": 3.0, "section": "bow"}]
	check(bool(Core.apply_component_damage(altered.moduleCondition, {"itemUid": engine_uid(altered), "loss": 0.5, "cause": "043 paired active probe"}).ok), "043 paired active probe has actual machinery damage")
	Records.publish(altered)
	measured["damaged043"] = probe(altered)
	finish(measured)

func finish(measured: Dictionary) -> void:
	var folder: String = OS.get_environment("GAME_TEST_ARTIFACTS")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		var file = FileAccess.open(folder.path_join("DAMAGE HOTPATH v0.040.json"), FileAccess.WRITE)
		check(file != null, "focused artifact opens")
		if file != null:
			file.store_string(JSON.stringify({"fixture": "damage_hotpath040", "complete": failures == 0 and not measured.is_empty(), "checks": checks, "failures": failures, "probe": measured}, "\t")); file.close()
	print("%d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
