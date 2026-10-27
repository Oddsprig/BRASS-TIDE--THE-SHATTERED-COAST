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
	var a: Dictionary = Battle.create({"fleet": [boats[0]], "enemyFleet": [boats[1]], "seed": 43043, "islands": []})
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
		Battle.update(a, 1.0 / 60.0, input)
		reference.update(b, 1.0 / 60.0, input)
		for i in range(2):
			# Public boundary guards must agree too, including any newly added keys.
			equal = equal and var_to_bytes(Damage.get_status_cached(a.ships[i], a.tactical.damageCache)) == var_to_bytes(Damage.get_status_cached(b.ships[i], b.tactical.damageCache))
		equal = equal and a.rng.state == b.rng.state and var_to_bytes(battle_state043(a)) == var_to_bytes(battle_state043(b))
	check(equal, "043 every full battle state/cache, RNG, shot, contact, order and equipment result equals fully guarded reads")
	check(a.ships[0].fuel == 0.0 and a.ships[0].supplies < supplies_before and a.ships[1].hp < hp_before, "043 actual battle covers exhausted fuel, finite repair and a swept projectile hit")

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
	phase_reads043(ship)
	phase_battle043(ship)
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
