extends SceneTree
## One bounded mount-key comparison. Root alone runs the native fixture.
const Damage = preload("res://scripts/damage.gd")
const EquipmentCombat = preload("res://scripts/equipment_combat.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Core = preload("res://scripts/equipment_condition.gd")
const Refit = preload("res://scripts/refit.gd")
const PROBE_CALLS: int = 128
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL performance hotpath039: ", message)

# Frozen pre-change derivation; its Damage dependency is unchanged by this patch.
func old_key(ship: Dictionary, status: Dictionary = {}, frame_cache = null) -> String:
	if not (ship is Dictionary) or not (ship.get("moduleCondition") is Dictionary): return "legacy"
	var info: Dictionary = Damage.inspect_owner_cached(ship, frame_cache)
	if str(info.get("mode", "")) != "canonical": return "legacy"
	var st_dict: Dictionary = status if (not status.is_empty() and status.has("equipmentMode")) else Damage._status_for_info(ship, info)
	if not bool(st_dict.get("equipmentOk", true)): return "invalid"
	var wf: Dictionary = st_dict.get("weaponFactors", {}) if st_dict.get("weaponFactors") is Dictionary else {}
	return "%.4f:%.4f:%.4f:%.4f" % [Damage.number(wf.get("mount0", -1.0), -1.0), Damage.number(wf.get("mount1", -1.0), -1.0), Damage.number(wf.get("mount2", -1.0), -1.0), Damage.number(wf.get("mount3", -1.0), -1.0)]

func same_key(label: String, ship: Dictionary, cache: Dictionary, status: Dictionary = {}) -> String:
	var before: PackedByteArray = var_to_bytes(ship)
	var expected: String = old_key(ship, status) # Fresh inspection, independent of cache admission.
	var actual: String = EquipmentCombat.mount_cache_key(ship, status, cache)
	var same: bool = actual == expected
	for _i in range(4): same = same and EquipmentCombat.mount_cache_key(ship, status, cache) == expected
	check(same, label + ": repeated keys equal old full-status derivation")
	check(var_to_bytes(ship) == before, label + ": entire boat is read-only")
	return actual

func mount_uid(ship: Dictionary) -> String:
	for item in ship.moduleCondition.items.values():
		if str(item.location) == "mount0": return str(item.itemUid)
	return ""

func warm(ship: Dictionary, cache: Dictionary) -> void:
	Damage.tick_ship(ship, 0.0, {"inCombat": true}, cache)
	check(cache.size() == 1 and is_same(cache[str(ship.id)].shipRef, ship), "ordinary damage tick admits exact live boat")

func probe(ship: Dictionary, cache: Dictionary) -> Dictionary:
	var before: PackedByteArray = var_to_bytes({"ship": ship, "cache": cache})
	for _i in range(8): old_key(ship, {}, cache); EquipmentCombat.mount_cache_key(ship, {}, cache)
	var old_us: int = 0
	var new_us: int = 0
	var checksum: int = 0
	for turn in range(2):
		# Reverse order on the second half; both variants retain the same validation.
		for variant in ([0, 1] if turn == 0 else [1, 0]):
			var started: int = Time.get_ticks_usec()
			for _i in range(PROBE_CALLS):
				checksum += (old_key(ship, {}, cache) if variant == 0 else EquipmentCombat.mount_cache_key(ship, {}, cache)).length()
			var elapsed: int = Time.get_ticks_usec() - started
			if variant == 0: old_us += elapsed
			else: new_us += elapsed
	check(checksum > 0 and var_to_bytes({"ship": ship, "cache": cache}) == before, "paired microprobe preserves full live boat and frame cache")
	return {"callsPerVariant": PROBE_CALLS * 2, "oldUs": old_us, "newUs": new_us, "note": "Same stock canonical dreadnought and warmed Damage cache; includes unchanged inspection guards. Short CPU microprobe only; no battle speed or GPU claim."}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var base: Dictionary = {}
	for hull in world.HULLS:
		if str(hull.id) == "maiden_dreadnought": base = hull.duplicate(true); break
	check(not base.is_empty(), "representative canonical baseline hull exists")
	if base.is_empty(): finish({}); return
	var ship: Dictionary = Damage.create_ship(base, {"id": "hotpath039-live", "uid": "hotpath039-live"})
	Refit.ensure(ship, base)
	var seeded: Dictionary = Records.initialize(ship, {"base": base, "loadout": ship.loadout, "catalog": Refit.catalog(), "identity": str(ship.uid), "knownUids": []})
	check(bool(seeded.ok), "real stock loadout initializes canonical equipment")
	if not bool(seeded.ok): finish({}); return
	var cache: Dictionary = {}
	var intact: String = same_key("cold", ship, cache)
	check(cache.is_empty(), "cold reads never admit a boat")
	warm(ship, cache)
	var cache_before: PackedByteArray = var_to_bytes(cache)
	same_key("warm", ship, cache)
	check(var_to_bytes(cache) == cache_before, "warm reads leave existing cache byte-identical")
	var measured: Dictionary = probe(ship, cache)
	var damaged: Dictionary = Core.apply_component_damage(ship.moduleCondition, {"itemUid": mount_uid(ship), "loss": 0.85, "cause": "Hotpath fixture hit"})
	check(bool(damaged.ok), "real in-place component damage succeeds")
	var disabled_key: String = same_key("damaged", ship, cache)
	check(disabled_key != intact and cache.is_empty(), "condition edit invalidates admitted snapshot and disables mount")
	warm(ship, cache)
	var repair: Dictionary = Core.repair_installed(ship.moduleCondition, {"work": float(ship.crew), "supplies": float(ship.supplies), "hpPerWork": 0.04, "suppliesPerHp": {"weapons": 1.0}, "priority": "weapons"})
	check(bool(repair.ok) and float(repair.get("usedSupplies", 0.0)) > 0.0, "jury repair consumes finite crew work and actual supply allowance")
	ship.supplies -= float(repair.get("usedSupplies", 0.0))
	var repaired: String = same_key("repaired", ship, cache)
	check(repaired != disabled_key and cache.is_empty(), "real repair invalidates snapshot and re-enables mount")
	warm(ship, cache)
	ship.crew = maxf(0.0, float(ship.crew) - 1.0)
	same_key("crew scalar changed", ship, cache)
	check(cache.is_empty(), "scalar edit retains existing Damage invalidation")
	warm(ship, cache)
	ship.fuel = 0.0
	same_key("fuel zero", ship, cache) # Mount factors do not depend on fuel; full status does.
	cache_before = var_to_bytes(cache)
	var copy: Dictionary = ship.duplicate(true)
	check(bool(Core.apply_component_damage(copy.moduleCondition, {"itemUid": mount_uid(copy), "loss": 0.7}).ok), "same-ID detached copy has independent real damage")
	check(same_key("same-ID copy", copy, cache) != EquipmentCombat.mount_cache_key(ship, {}, cache), "copy factors never reuse live boat snapshot")
	check(var_to_bytes(cache) == cache_before, "copy reads neither admit nor evict live boat")
	ship.sunk = true
	same_key("sunk with empty slots", ship, cache)
	check(cache.is_empty(), "sunk scalar invalidates live snapshot")
	var explicit_status: Dictionary = {"equipmentMode": "canonical", "equipmentOk": true, "weaponFactors": {"mount0": 0.12345}}
	same_key("explicit status on sunk boat", ship, cache, explicit_status)
	explicit_status.equipmentOk = false
	check(same_key("explicit invalid status", ship, cache, explicit_status) == "invalid", "caller refusal remains authoritative")
	var legacy: Dictionary = Damage.create_ship(base)
	check(same_key("legacy", legacy, cache) == "legacy", "legacy key unchanged")
	copy.moduleCondition = {}
	check(same_key("corrupt copy", copy, cache) == "legacy", "existing corrupt-owner key behavior unchanged")
	finish(measured)

func finish(measured: Dictionary) -> void:
	var folder: String = OS.get_environment("GAME_TEST_ARTIFACTS")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		var file = FileAccess.open(folder.path_join("HOTPATH v0.039.json"), FileAccess.WRITE)
		check(file != null, "microprobe artifact opens")
		if file != null:
			file.store_string(JSON.stringify({"fixture": "performance_hotpath039", "complete": failures == 0 and not measured.is_empty(), "checks": checks, "failures": failures, "probe": measured}, "\t")); file.close()
	print("%d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
