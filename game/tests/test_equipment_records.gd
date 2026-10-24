extends SceneTree
## Bounded unrun fixture for the detached v0.031 equipment-records adapter.
## Uses actual world.json hulls and actual Refit.catalog() passed by the caller.
## Not registered in tools/check_game.py yet; Sol executes native engine runs.

const Records = preload("res://scripts/equipment_records.gd")
const Core = preload("res://scripts/equipment_condition.gd")
const Refit = preload("res://scripts/refit.gd")
const Damage = preload("res://scripts/damage.gd")
const Layout = preload("res://scripts/mount_layout.gd")

var world: Dictionary = {}
var catalog: Dictionary = {}
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL equipment_records: " + message)

func _context(base: Dictionary, loadout: Dictionary, identity: String, known_uids: Array = []) -> Dictionary:
	return {
		"base": base,
		"loadout": loadout,
		"catalog": catalog,
		"identity": identity,
		"knownUids": known_uids
	}

func _boat_for(hull_index: int, identity: String, overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = world.HULLS[hull_index].duplicate(true)
	var boat: Dictionary = Damage.create_ship(base, overrides)
	Refit.ensure(boat, base)
	boat.uid = identity
	return boat

func _item_at(condition: Dictionary, location: String) -> Dictionary:
	for uid in condition.items.keys():
		var item: Dictionary = condition.items[uid]
		if str(item.location) == location:
			return item
	return {}

func _non_condition_state(boat: Dictionary) -> Dictionary:
	var kept: Dictionary = {}
	for key in ["id", "type", "uid", "name", "baseSpec", "loadout", "spec", "hp", "maxHp", "armor", "water", "capacity", "fire", "supplies", "ammo", "fuel", "crew", "crewMin", "crewOptimal", "crewMax", "wounded", "breaches", "policy", "sunk", "coins"]:
		if boat.has(key):
			var v = boat[key]
			kept[key] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	return kept

func test_stable_once_initialization_and_identity_rules() -> void:
	var base: Dictionary = world.HULLS[0].duplicate(true)
	var boat: Dictionary = _boat_for(0, "fleet-tin-skiff-01", {
		"hp": 91.0,
		"water": 18.0,
		"fire": 4.0,
		"engine": 0.65,
		"ammo": 42.0,
		"fuel": 33.0,
		"supplies": 11.0,
		"crew": 4.0,
		"wounded": 1.0,
		"coins": 5000,
		"breaches": [{"area": 8.0, "section": "bow"}]
	})
	var preserved_before: Dictionary = _non_condition_state(boat)
	var boat_before_bad: Dictionary = boat.duplicate(true)
	check(not Records.initialize(boat, {"base": base, "loadout": boat.loadout, "catalog": catalog}).ok and boat == boat_before_bad, "initialize refuses missing caller identity without mutating boat")
	check(not Records.initialize(boat, _context(base, boat.loadout, str(base.id))).ok and boat == boat_before_bad, "initialize refuses generic base hull id as identity")
	check(not Records.initialize(boat, _context(base, boat.loadout, "boat")).ok and boat == boat_before_bad, "initialize refuses generic 'boat' identity")

	var first: Dictionary = Records.initialize(boat, _context(base, boat.loadout, "fleet-tin-skiff-01"))
	check(first.ok and first.changed and not first.idempotent, "first initialize seeds canonical moduleCondition once")
	check(_non_condition_state(boat) == preserved_before, "initialize preserves hull HP, water, fire, stores, crew, breaches, loadout, spec, and wallet")
	check(is_equal_approx(float(boat.engine), 0.65) and boat.refitLocker.is_empty(), "initialize projects legacy engine scalar and empty locker counts")
	var mount0_item: Dictionary = _item_at(boat.moduleCondition, "mount0")
	var engine_item: Dictionary = _item_at(boat.moduleCondition, "engine")
	var armor_item: Dictionary = _item_at(boat.moduleCondition, "armor")
	var pumps_item: Dictionary = _item_at(boat.moduleCondition, "pumps")
	check(not mount0_item.is_empty() and str(mount0_item.typeId) == "stock_primary" and str(mount0_item.originHullType) == str(base.id) and is_equal_approx(float(mount0_item.hp), 1.0), "stock weapon preserves originHullType and existing hp 1.0")
	check(not engine_item.is_empty() and str(engine_item.typeId) == "stock_engine" and str(engine_item.originHullType) == str(base.id) and is_equal_approx(float(engine_item.hp), 0.65), "stock engine preserves originHullType and legacy 0.65 scalar")
	check(not armor_item.is_empty() and str(armor_item.typeId) == "stock_armor" and str(armor_item.originHullType) == str(base.id) and is_equal_approx(float(armor_item.hp), 1.0), "stock armor preserves originHullType and hp 1.0")
	check(not pumps_item.is_empty() and str(pumps_item.typeId) == "hull_pumps" and str(pumps_item.originHullType) == str(base.id) and is_equal_approx(float(pumps_item.hp), 1.0), "hull with positive base.pumps seeds integral hull_pumps")

	var first_uids: Array = first.itemUids.duplicate()
	var first_seq: int = int(boat.moduleCondition.nextItemSeq)
	boat.engine = 1.0
	boat.refitLocker = {"rapid_gun": 2}
	var second: Dictionary = Records.initialize(boat, _context(base, boat.loadout, "fleet-tin-skiff-01"))
	check(second.ok and second.idempotent and not second.changed, "second initialize on existing schema is idempotent and reports changed=false")
	check(second.itemUids == first_uids and int(boat.moduleCondition.nextItemSeq) == first_seq, "second initialize keeps identical itemUids and nextItemSeq")
	check(is_equal_approx(float(_item_at(boat.moduleCondition, "engine").hp), 0.65) and Core.list_locker(boat.moduleCondition).items.is_empty(), "existing schema never heals engine from raised boat.engine or reseeds extra locker parts")

func test_no_pump_invention_on_pump_free_base() -> void:
	var pump_free_zero: Dictionary = world.HULLS[1].duplicate(true)
	pump_free_zero.pumps = 0.0
	var boat_zero: Dictionary = Damage.create_ship(pump_free_zero)
	Refit.ensure(boat_zero, pump_free_zero)
	var init_zero: Dictionary = Records.initialize(boat_zero, _context(pump_free_zero, boat_zero.loadout, "fleet-punt-nopump-0"))
	check(init_zero.ok and _item_at(boat_zero.moduleCondition, "pumps").is_empty() and boat_zero.moduleCondition.items.size() == 3, "base with pumps=0.0 does not invent an integral pumps descriptor")
	var snap_zero: Dictionary = Records.snapshot(boat_zero)
	check(snap_zero.ok and not snap_zero.installed.has("pumps") and is_equal_approx(float(snap_zero.pumpFactor), 0.0), "snapshot on pump-free hull reports pumpFactor 0.0 without fabricating pumps")

	var pump_free_absent: Dictionary = world.HULLS[1].duplicate(true)
	pump_free_absent.erase("pumps")
	var boat_absent: Dictionary = Damage.create_ship(pump_free_absent)
	Refit.ensure(boat_absent, pump_free_absent)
	var init_absent: Dictionary = Records.initialize(boat_absent, _context(pump_free_absent, boat_absent.loadout, "fleet-punt-nopump-1"))
	check(init_absent.ok and _item_at(boat_absent.moduleCondition, "pumps").is_empty(), "base with omitted pumps field does not invent integral pumps")

	var with_pumps_base: Dictionary = world.HULLS[1].duplicate(true)
	var boat_with_pumps: Dictionary = _boat_for(1, "fleet-punt-with-pumps")
	check(Records.initialize(boat_with_pumps, _context(with_pumps_base, boat_with_pumps.loadout, "fleet-punt-with-pumps")).ok, "hull with positive pumps initializes normally")
	var before_mismatch: Dictionary = boat_with_pumps.duplicate(true)
	check(not Records.initialize(boat_with_pumps, _context(pump_free_zero, boat_with_pumps.loadout, "fleet-punt-with-pumps")).ok and boat_with_pumps == before_mismatch, "existing pumps record is refused if validated against a pump-free base")

func test_full_256_legacy_spares_retained_and_bound() -> void:
	var base: Dictionary = world.HULLS[23].duplicate(true)
	var boat: Dictionary = _boat_for(23, "fleet-dreadnought-256")
	boat.refitLocker = {
		"rapid_gun": 100,
		"light_cannon": 80,
		"stock_engine": 40,
		"scout_plating": 36
	}
	var seeded: Dictionary = Records.initialize(boat, _context(base, boat.loadout, "fleet-dreadnought-256"))
	check(seeded.ok and seeded.changed, "full 256 legacy spares across weapons, engines, and armor initialize")
	var locker_list: Dictionary = Core.list_locker(boat.moduleCondition)
	check(locker_list.ok and locker_list.items.size() == 256 and boat.moduleCondition.items.size() == 260, "all 256 locker items are retained without truncation alongside 4 installed items")
	check(boat.refitLocker == {"rapid_gun": 100, "light_cannon": 80, "stock_engine": 40, "scout_plating": 36}, "published refitLocker preserves exact 256 module counts")

	var overflow_boat: Dictionary = _boat_for(23, "fleet-dreadnought-257")
	overflow_boat.refitLocker = {
		"rapid_gun": 100,
		"light_cannon": 80,
		"stock_engine": 40,
		"scout_plating": 37
	}
	var overflow_before: Dictionary = overflow_boat.duplicate(true)
	check(not Records.initialize(overflow_boat, _context(base, overflow_boat.loadout, "fleet-dreadnought-257")).ok and overflow_boat == overflow_before, "257 legacy spares are refused whole without truncating or mutating boat")

func test_unknown_condition_refused_unchanged() -> void:
	var base: Dictionary = world.HULLS[0].duplicate(true)
	var foreign_boat: Dictionary = _boat_for(0, "fleet-foreign-01")
	foreign_boat.weaponCondition = {"mount0": 0.5}
	var foreign_before: Dictionary = foreign_boat.duplicate(true)
	check(not Records.initialize(foreign_boat, _context(base, foreign_boat.loadout, "fleet-foreign-01")).ok and foreign_boat == foreign_before, "initialize refuses foreign weaponCondition field unchanged")
	check(not Records.absorb_legacy_damage(foreign_boat).ok and foreign_boat == foreign_before, "absorb_legacy_damage refuses foreign condition field unchanged")
	check(not Records.publish(foreign_boat).ok and foreign_boat == foreign_before, "publish refuses foreign condition field unchanged")
	check(not Records.snapshot(foreign_boat).ok and foreign_boat == foreign_before, "snapshot fails closed on foreign condition field without erasing")

	var mount_foreign: Dictionary = _boat_for(0, "fleet-foreign-mount")
	mount_foreign.spec.weaponMounts[0]["disabled"] = true
	var mount_before: Dictionary = mount_foreign.duplicate(true)
	check(not Records.initialize(mount_foreign, _context(base, mount_foreign.loadout, "fleet-foreign-mount")).ok and mount_foreign == mount_before, "initialize refuses foreign condition key inside spec.weaponMounts")

	var corrupt_owner: Dictionary = _boat_for(0, "fleet-corrupt-owner")
	corrupt_owner.moduleCondition = {"version": 99, "items": {}}
	var corrupt_before: Dictionary = corrupt_owner.duplicate(true)
	check(not Records.initialize(corrupt_owner, _context(base, corrupt_owner.loadout, "fleet-corrupt-owner")).ok and corrupt_owner == corrupt_before, "initialize refuses unknown existing moduleCondition version without erasing")
	check(not Records.absorb_legacy_damage(corrupt_owner).ok and corrupt_owner == corrupt_before, "absorb_legacy_damage refuses corrupt moduleCondition unchanged")
	check(not Records.publish(corrupt_owner).ok and corrupt_owner == corrupt_before, "publish refuses corrupt moduleCondition unchanged")
	check(not Records.snapshot(corrupt_owner).ok and corrupt_owner == corrupt_before, "snapshot fails closed on corrupt existing owner without erasing")

	var bad_locker_meta: Dictionary = _boat_for(0, "fleet-bad-locker-meta")
	bad_locker_meta.refitLocker = [{"id": "rapid_gun", "count": 1, "hp": 0.5}]
	var bad_locker_before: Dictionary = bad_locker_meta.duplicate(true)
	check(not Records.initialize(bad_locker_meta, _context(base, bad_locker_meta.loadout, "fleet-bad-locker-meta")).ok and bad_locker_meta == bad_locker_before, "initialize refuses condition metadata inside legacy refitLocker")

func test_json_float_migration() -> void:
	var raw_base: Dictionary = world.HULLS[7].duplicate(true)
	var raw_boat: Dictionary = _boat_for(7, "fleet-hook-raider-json", {"engine": 0.75})
	raw_boat.refitLocker = {"rapid_gun": 3, "economy_drive": 1, "scout_plating": 2}
	var parsed_base: Dictionary = JSON.parse_string(JSON.stringify(raw_base))
	var parsed_boat: Dictionary = JSON.parse_string(JSON.stringify(raw_boat))
	var seeded: Dictionary = Records.initialize(parsed_boat, _context(parsed_base, parsed_boat.loadout, "fleet-hook-raider-json"))
	check(seeded.ok and seeded.changed and Core.list_locker(parsed_boat.moduleCondition).items.size() == 6, "JSON-parsed legacy boat with whole-float locker counts migrates cleanly")

	var roundtrip_boat: Dictionary = JSON.parse_string(JSON.stringify(parsed_boat))
	var again: Dictionary = Records.initialize(roundtrip_boat, _context(parsed_base, roundtrip_boat.loadout, "fleet-hook-raider-json"))
	check(again.ok and again.idempotent and not again.changed, "JSON-roundtripped moduleCondition with float version/nextItemSeq/lockerOrder validates idempotently")
	roundtrip_boat.engine = 0.50
	var absorbed: Dictionary = Records.absorb_legacy_damage(roundtrip_boat)
	check(absorbed.ok and absorbed.changed and is_equal_approx(float(absorbed.engineHp), 0.50), "absorb_legacy_damage accepts JSON-roundtripped moduleCondition")
	var pub: Dictionary = Records.publish(roundtrip_boat)
	check(pub.ok and is_equal_approx(float(roundtrip_boat.engine), 0.50), "publish succeeds on JSON-roundtripped moduleCondition")
	var snap: Dictionary = Records.snapshot(roundtrip_boat)
	check(snap.ok and not snap.needsInitialize and is_equal_approx(float(snap.engineHp), 0.50), "snapshot succeeds on JSON-roundtripped moduleCondition")

	var frac_boat: Dictionary = _boat_for(7, "fleet-hook-raider-frac")
	frac_boat.refitLocker = {"rapid_gun": 1.5}
	var frac_before: Dictionary = frac_boat.duplicate(true)
	check(not Records.initialize(frac_boat, _context(parsed_base, frac_boat.loadout, "fleet-hook-raider-frac")).ok and frac_boat == frac_before, "fractional locker count 1.5 is refused without rounding")

func test_duplicate_registry_refusal() -> void:
	var base: Dictionary = world.HULLS[0].duplicate(true)
	var boat_a: Dictionary = _boat_for(0, "fleet-dup-alpha")
	check(Records.initialize(boat_a, _context(base, boat_a.loadout, "fleet-dup-alpha")).ok, "first hull initializes")
	var known_a: Array = Core.collect_item_uids([boat_a.moduleCondition]).uids

	var boat_b: Dictionary = _boat_for(0, "fleet-dup-alpha")
	var b_before: Dictionary = boat_b.duplicate(true)
	check(not Records.initialize(boat_b, _context(base, boat_b.loadout, "fleet-dup-alpha", known_a)).ok and boat_b == b_before, "duplicate birth identity whose minted UIDs collide with knownUids is refused")

	boat_b.uid = "fleet-dup-beta"
	check(Records.initialize(boat_b, _context(base, boat_b.loadout, "fleet-dup-beta", known_a)).ok, "second hull with distinct identity initializes alongside knownUids")
	var b_initialized: Dictionary = boat_b.duplicate(true)
	var b_own_uids: Array = Core.collect_item_uids([boat_b.moduleCondition]).uids
	check(not Records.initialize(boat_b, _context(base, boat_b.loadout, "fleet-dup-beta", [b_own_uids[0]])).ok and boat_b == b_initialized, "existing schema refuses when one of its itemUids is claimed by another owner in knownUids")

func test_absent_installed_record_cannot_regenerate() -> void:
	var base: Dictionary = world.HULLS[0].duplicate(true)
	var fit: Dictionary = Refit.defaults(base)
	fit.weapons[1] = "rapid_gun"
	var norm: Dictionary = Refit.normalize(base, fit)
	check(norm.ok, "two-weapon loadout on tin_skiff is valid")
	var boat: Dictionary = _boat_for(0, "fleet-no-regen", {"loadout": norm.loadout})
	Refit.ensure(boat, base)
	check(Records.initialize(boat, _context(base, boat.loadout, "fleet-no-regen")).ok, "hull with mount0, mount1, engine, armor, and pumps initializes")

	for loc in ["mount0", "mount1", "engine", "armor", "pumps"]:
		var probe: Dictionary = boat.duplicate(true)
		var target_item: Dictionary = _item_at(probe.moduleCondition, loc)
		check(not target_item.is_empty(), "installed item exists at " + loc)
		probe.moduleCondition.items.erase(str(target_item.itemUid))
		var probe_before: Dictionary = probe.duplicate(true)
		var res: Dictionary = Records.initialize(probe, _context(base, probe.loadout, "fleet-no-regen"))
		check(not res.ok and probe == probe_before and _item_at(probe.moduleCondition, loc).is_empty(), "absent installed record at " + loc + " is refused and never regenerates")

func test_disabled_engine_raw_projection_and_factors() -> void:
	var base: Dictionary = world.HULLS[23].duplicate(true)
	var fit: Dictionary = Refit.defaults(base)
	fit.weapons[1] = "rapid_gun"
	fit.weapons[2] = "light_cannon"
	fit.weapons[3] = "fire_rocket"
	var norm: Dictionary = Refit.normalize(base, fit)
	check(norm.ok, "four-mount dreadnought loadout normalizes")
	var boat: Dictionary = _boat_for(23, "fleet-dreadnought-factors", {"loadout": norm.loadout, "engine": 1.0})
	Refit.ensure(boat, base)
	check(Records.initialize(boat, _context(base, boat.loadout, "fleet-dreadnought-factors")).ok, "four-mount dreadnought initializes")

	var eng_uid: String = str(_item_at(boat.moduleCondition, "engine").itemUid)
	var m0_uid: String = str(_item_at(boat.moduleCondition, "mount0").itemUid)
	var m1_uid: String = str(_item_at(boat.moduleCondition, "mount1").itemUid)
	check(Core.apply_component_damage(boat.moduleCondition, {"itemUid": eng_uid, "loss": 0.85, "cause": "Engine room shell"}).ok, "engine damaged to 0.15 disabled")
	var jury: Dictionary = Core.repair_installed(boat.moduleCondition, {
		"work": 0.10,
		"supplies": 5.0,
		"hpPerWork": 1.0,
		"suppliesPerHp": {"engines": 1.0, "weapons": 1.0, "pumps": 1.0},
		"priority": "engine"
	})
	check(jury.ok and jury.changed, "partial jury repair raises engine from 0.15 to 0.25")
	var eng_after: Dictionary = _item_at(boat.moduleCondition, "engine")
	check(is_equal_approx(float(eng_after.hp), 0.25) and str(eng_after.status) == "disabled", "0.25 hp engine below 0.30 re-enable threshold stays disabled")

	check(Core.apply_component_damage(boat.moduleCondition, {"itemUid": m0_uid, "loss": 0.85, "cause": "Direct turret hit"}).ok, "mount0 damaged to 0.15 disabled")
	check(Core.apply_component_damage(boat.moduleCondition, {"itemUid": m1_uid, "loss": 0.40, "cause": "Splinter damage"}).ok, "mount1 damaged to 0.60 damaged")

	var pub: Dictionary = Records.publish(boat)
	check(pub.ok and is_equal_approx(float(boat.engine), 0.25) and is_equal_approx(float(pub.engineHp), 0.25), "publish projects raw 0.25 installed engine hp onto boat.engine rather than 0.0")

	var snap: Dictionary = Records.snapshot(boat)
	check(snap.ok and not snap.needsInitialize, "snapshot succeeds on damaged hull")
	check(is_equal_approx(float(snap.engineHp), 0.25) and is_equal_approx(float(snap.engineFactor), 0.0), "snapshot reports raw engineHp 0.25 and derived engineFactor 0.0 while disabled")
	check(is_equal_approx(float(snap.factors.engineHp), 0.25) and is_equal_approx(float(snap.factors.engineFactor), 0.0), "factors dictionary reports engineHp 0.25 and engineFactor 0.0")
	check(is_equal_approx(float(snap.pumpFactor), 1.0) and is_equal_approx(float(snap.armorFactor), 1.0), "healthy pump and armor factors remain 1.0")
	check(is_equal_approx(float(snap.weaponFactors["mount0"]), 0.0) and is_equal_approx(float(snap.weaponFactors["mount1"]), 0.60) and is_equal_approx(float(snap.weaponFactors["mount2"]), 1.0) and is_equal_approx(float(snap.weaponFactors["mount3"]), 1.0), "weaponFactors map mount0..3 with disabled->0.0 and damaged->hp")

func test_readonly_snapshot_detached_and_legacy_absent_owner() -> void:
	var legacy_boat: Dictionary = _boat_for(0, "fleet-legacy-uninit", {"engine": 0.80})
	var legacy_before: Dictionary = legacy_boat.duplicate(true)
	var legacy_snap: Dictionary = Records.snapshot(legacy_boat)
	check(legacy_snap.ok and legacy_snap.needsInitialize and legacy_snap.installed.is_empty() and legacy_snap.installedItems.is_empty(), "snapshot on legacy absent owner reports needsInitialize without fabricating parts")
	check(legacy_boat == legacy_before and not legacy_boat.has("moduleCondition"), "snapshot on legacy boat does not mutate boat")

	var base: Dictionary = world.HULLS[0].duplicate(true)
	var boat: Dictionary = _boat_for(0, "fleet-snapshot-detached", {"engine": 0.90})
	check(Records.initialize(boat, _context(base, boat.loadout, "fleet-snapshot-detached")).ok, "boat initializes for snapshot detachment check")
	var saved_boat: Dictionary = boat.duplicate(true)
	var seq_before: int = int(boat.moduleCondition.nextItemSeq)
	var snap: Dictionary = Records.snapshot(boat)
	snap.installed["engine"].hp = 0.0
	snap.installed["engine"].status = "disabled"
	snap.installedItems[0].hp = 0.0
	snap.factors.weaponFactors["mount0"] = 0.0
	snap.weaponFactors["mount0"] = 0.0
	check(boat == saved_boat and int(boat.moduleCondition.nextItemSeq) == seq_before, "mutating returned snapshot records and factor dictionaries does not leak into canonical boat.moduleCondition")

	var preview_clone: Dictionary = boat.duplicate(true)
	var preview: Dictionary = Core.preview_next_item(preview_clone.moduleCondition)
	check(preview.ok and int(boat.moduleCondition.nextItemSeq) == seq_before, "read-only preview on cloned boat does not advance real serial")

func test_explicit_downward_sync_and_repair_publish_order() -> void:
	var base: Dictionary = world.HULLS[0].duplicate(true)
	var boat: Dictionary = _boat_for(0, "fleet-sync-repair", {"engine": 0.80})
	check(Records.initialize(boat, _context(base, boat.loadout, "fleet-sync-repair")).ok, "boat initializes at engine 0.80")

	boat.engine = 0.45
	var down: Dictionary = Records.absorb_legacy_damage(boat)
	check(down.ok and down.changed and is_equal_approx(float(down.engineHp), 0.45) and is_equal_approx(float(_item_at(boat.moduleCondition, "engine").hp), 0.45), "absorb_legacy_damage lowers canonical engine hp to 0.45")

	boat.engine = 1.0
	var up: Dictionary = Records.absorb_legacy_damage(boat)
	check(up.ok and not up.changed and is_equal_approx(float(up.engineHp), 0.45) and is_equal_approx(float(_item_at(boat.moduleCondition, "engine").hp), 0.45), "absorb_legacy_damage ignores upward legacy engine scalar")

	boat.engine = 0.45
	var repaired: Dictionary = Core.repair_installed(boat.moduleCondition, {
		"work": 0.25,
		"supplies": 5.0,
		"hpPerWork": 1.0,
		"suppliesPerHp": {"engines": 1.0, "weapons": 1.0, "pumps": 1.0},
		"priority": "engine"
	})
	check(repaired.ok and repaired.changed and is_equal_approx(float(_item_at(boat.moduleCondition, "engine").hp), 0.70), "core jury repair raises canonical engine from 0.45 to 0.70 while boat.engine is still 0.45")
	var published: Dictionary = Records.publish(boat)
	check(published.ok and is_equal_approx(float(boat.engine), 0.70) and is_equal_approx(float(_item_at(boat.moduleCondition, "engine").hp), 0.70), "publish after core repair updates boat.engine to 0.70 without undoing repair")

	var restored: Dictionary = Core.restore_installed_paid(boat.moduleCondition, {"confirmPaid": true})
	check(restored.ok and restored.changed, "paid drydock restore brings installed parts to 1.0")
	var pub_full: Dictionary = Records.publish(boat)
	check(pub_full.ok and is_equal_approx(float(boat.engine), 1.0) and is_equal_approx(float(Records.snapshot(boat).engineFactor), 1.0), "publish after paid restore sets boat.engine to 1.0")

func test_exact_paid_replacement_ordering_and_custody() -> void:
	var base: Dictionary = world.HULLS[0].duplicate(true)
	var boat: Dictionary = _boat_for(0, "fleet-paid-replace", {"engine": 0.50})
	var mount_count: int = Layout.hardpoints(base).size()
	var hull_type: String = str(base.id)
	check(Records.initialize(boat, _context(base, boat.loadout, "fleet-paid-replace")).ok, "boat initializes with stock_engine at 0.50")

	var old_engine_uid: String = str(_item_at(boat.moduleCondition, "engine").itemUid)
	boat.engine = 0.35
	var absorbed_before: Dictionary = Records.absorb_legacy_damage(boat)
	check(absorbed_before.ok and absorbed_before.changed and is_equal_approx(float(_item_at(boat.moduleCondition, "engine").hp), 0.35), "downward external engine damage is absorbed before canonical replacement")

	var moved_to_locker: Dictionary = Core.move_exact(boat.moduleCondition, {
		"itemUid": old_engine_uid,
		"location": "locker",
		"mountCount": mount_count,
		"hullType": hull_type
	})
	check(moved_to_locker.ok and moved_to_locker.changed, "damaged stock_engine moves to locker")
	var no_engine_probe: Dictionary = boat.duplicate(true)
	var no_engine_pub: Dictionary = Records.publish(no_engine_probe)
	check(no_engine_pub.ok and not no_engine_pub.hasEngine and is_equal_approx(float(no_engine_probe.engine), 0.0) and no_engine_probe.refitLocker == {"stock_engine": 1}, "publish with no installed engine sets raw boat.engine to 0.0 and updates refitLocker")

	var preview: Dictionary = Core.preview_next_item(boat.moduleCondition)
	check(preview.ok, "preview_next_item returns next monotonic itemUid")
	var acquired: Dictionary = Core.accept_acquired_item(boat.moduleCondition, {
		"acquired": true,
		"family": "engines",
		"typeId": "boost_drive",
		"originHullType": hull_type,
		"location": "engine",
		"hp": 1.0,
		"mountCount": mount_count,
		"hullType": hull_type
	})
	check(acquired.ok and acquired.changed and str(acquired.itemUid) == str(preview.itemUid) and str(acquired.itemUid) != old_engine_uid, "acquired boost_drive receives previewed UID distinct from removed stock_engine")
	boat.loadout.engine = "boost_drive"

	var published_after: Dictionary = Records.publish(boat)
	check(published_after.ok and is_equal_approx(float(boat.engine), 1.0) and boat.refitLocker == {"stock_engine": 1}, "publish after replacement sets boat.engine to 1.0 and projects removed stock_engine in refitLocker")
	var new_installed: Dictionary = _item_at(boat.moduleCondition, "engine")
	var old_in_locker: Dictionary = boat.moduleCondition.items.get(old_engine_uid, {})
	check(str(new_installed.itemUid) == str(acquired.itemUid) and str(new_installed.typeId) == "boost_drive" and is_equal_approx(float(new_installed.hp), 1.0) and str(new_installed.status) == "ok", "installed boost_drive remains hp 1.0 ok and is not damaged by stale 0.35 scalar")
	check(str(old_in_locker.location) == "locker" and str(old_in_locker.typeId) == "stock_engine" and is_equal_approx(float(old_in_locker.hp), 0.35) and str(old_in_locker.status) == "damaged", "removed stock_engine stays in locker with its original UID and 0.35 damaged condition")
	var revalidated: Dictionary = Records.initialize(boat, _context(base, boat.loadout, "fleet-paid-replace"))
	check(revalidated.ok and revalidated.idempotent and not revalidated.changed, "re-running initialize after paid replacement validates the updated loadout and custody")

func _initialize() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	catalog = Refit.catalog()
	test_stable_once_initialization_and_identity_rules()
	test_no_pump_invention_on_pump_free_base()
	test_full_256_legacy_spares_retained_and_bound()
	test_unknown_condition_refused_unchanged()
	test_json_float_migration()
	test_duplicate_registry_refusal()
	test_absent_installed_record_cannot_regenerate()
	test_disabled_engine_raw_projection_and_factors()
	test_readonly_snapshot_detached_and_legacy_absent_owner()
	test_explicit_downward_sync_and_repair_publish_order()
	test_exact_paid_replacement_ordering_and_custody()
	if failures > 0:
		push_error("equipment_records: %d checks, %d failures" % [checks, failures])
		quit(1)
	print("equipment_records: %d checks, 0 failures" % checks)
	quit(0)
