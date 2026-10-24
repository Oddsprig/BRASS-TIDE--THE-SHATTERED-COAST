extends SceneTree
## Bounded checks for the detached v0.031 equipment-condition prototype.
## Not registered in tools/check_game.py. No Battle, Refit, Damage, or campaign preload.
const Core = preload("res://scripts/equipment_condition.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func ship(engine: float) -> Dictionary:
	return {"id": "launch", "type": "launch", "uid": "spawn-pending", "engine": engine}

func part(family: String, type_id: String, location: String, hp: float = -1.0) -> Dictionary:
	var row: Dictionary = {"family": family, "typeId": type_id, "originHullType": "launch", "location": location}
	if hp >= 0.0:
		row.hp = hp
	return row

func request(identity: String, installed: Array, locker: Array = []) -> Dictionary:
	return {"identity": identity, "hullType": "launch", "mountCount": 2, "installed": installed, "locker": locker, "engineScalar": 1.0}

func at(condition: Dictionary, location: String) -> Dictionary:
	for key in condition.items.keys():
		if str(condition.items[key].location) == location:
			return condition.items[key]
	return {}

func test_scalar_cannot_heal() -> void:
	var boat: Dictionary = ship(0.25)
	var seeded: Dictionary = Core.legacy_seed(boat, request("phys-launch-a", [part("weapons", "stock_primary", "mount0"), part("engines", "stock_engine", "engine")]))
	check(seeded.ok and seeded.hasEngine and is_equal_approx(float(at(boat.moduleCondition, "engine").hp), 0.25), "legacy engine scalar 0.25 is the birth condition even when the request scalar is 1")
	var birth: String = str(at(boat.moduleCondition, "engine").itemUid)
	var seq: int = int(boat.moduleCondition.nextItemSeq)
	boat.engine = 1.0
	var rejected: Dictionary = Core.note_engine_scalar(boat.moduleCondition, boat.engine)
	check(rejected.ok and not rejected.changed and is_equal_approx(float(at(boat.moduleCondition, "engine").hp), 0.25) and boat.engine == 1.0, "raising the legacy engine scalar to 1 does not heal the engine part")
	var again: Dictionary = Core.legacy_seed(boat, request("phys-launch-a", [part("weapons", "stock_primary", "mount0"), part("engines", "stock_engine", "engine", 1.0)], [part("weapons", "rapid_gun", "locker")]))
	check(again.ok and again.idempotent and int(again.nextItemSeq) == seq and str(at(boat.moduleCondition, "engine").itemUid) == birth and is_equal_approx(float(at(boat.moduleCondition, "engine").hp), 0.25) and Core.list_locker(boat.moduleCondition).items.is_empty(), "a second seed keeps the same ids and does not heal or add the extra locker part")
	var lowered: Dictionary = Core.note_engine_scalar(boat.moduleCondition, 0.125)
	check(lowered.ok and lowered.changed and is_equal_approx(float(lowered.engineHp), 0.125) and str(at(boat.moduleCondition, "engine").status) == "disabled" and boat.engine == 1.0, "a lower legacy scalar damages the canonical engine without writing the ship field")
	var described: Dictionary = ship(1.0)
	var kept: Dictionary = Core.legacy_seed(described, request("phys-launch-described", [part("engines", "stock_engine", "engine", 0.125)]))
	check(kept.ok and is_equal_approx(float(at(described.moduleCondition, "engine").hp), 0.125), "an explicit damaged engine descriptor is not raised to a healthy scalar")

func test_distinct_hulls_and_capture() -> void:
	var left: Dictionary = ship(1.0)
	var right: Dictionary = ship(1.0)
	var gear: Array = [part("weapons", "stock_primary", "mount0"), part("engines", "stock_engine", "engine")]
	check(Core.legacy_seed(left, request("phys-launch-a", gear)).ok, "first launch seeds")
	var collided: Dictionary = request("phys-launch-a", gear)
	collided.knownUids = Core.collect_item_uids([left.moduleCondition]).uids
	var blocked: Dictionary = Core.legacy_seed(right, collided)
	check(not blocked.ok and not right.has("moduleCondition") and left.moduleCondition.items.size() == 2, "the same birth namespace cannot mint a second hull's copy of those UIDs")
	check(Core.legacy_seed(right, request("phys-launch-b", gear)).ok, "a second physical launch seeds under its own namespace")
	var owned: Dictionary = Core.collect_item_uids([left.moduleCondition, right.moduleCondition])
	check(owned.ok and owned.uids.size() == 4 and str(at(left.moduleCondition, "mount0").typeId) == str(at(right.moduleCondition, "mount0").typeId) and str(at(left.moduleCondition, "mount0").itemUid) != str(at(right.moduleCondition, "mount0").itemUid), "two hulls of one design keep distinct physical copies of the same factory type")
	var before: Array = Core.collect_item_uids([left.moduleCondition]).uids
	var birth_namespace: String = str(left.moduleCondition.birthNamespace)
	var serial: int = int(left.moduleCondition.nextItemSeq)
	left.uid = "captured-9"
	var noted: Dictionary = Core.acknowledge_hull_uid(left.moduleCondition, left.uid)
	check(noted.ok and not noted.changed and noted.birthNamespace == birth_namespace and noted.itemUids == before and int(left.moduleCondition.nextItemSeq) == serial, "a capture uid does not regenerate item UIDs or the birth namespace")
	var renamed: Dictionary = Core.legacy_seed(left, request("captured-9", gear))
	check(not renamed.ok and Core.collect_item_uids([left.moduleCondition]).uids == before and str(left.moduleCondition.birthNamespace) == birth_namespace, "reseeding under the new hull uid is refused and the original parts remain")

func test_corrupt_and_opaque_are_kept() -> void:
	var opaque: Dictionary = ship(0.4)
	opaque.moduleConditions = {"engine": {"condition": 0.4, "serial": "retained"}}
	var opaque_before: Dictionary = opaque.duplicate(true)
	check(not Core.legacy_seed(opaque, request("phys-opaque", [part("engines", "stock_engine", "engine")])).ok and opaque == opaque_before and not opaque.has("moduleCondition"), "old moduleConditions metadata is not converted or deleted")
	var mounted: Dictionary = ship(0.4)
	mounted.spec = {"weaponMounts": [{"id": "mount0", "hp": 0.5}]}
	var mounted_before: Dictionary = mounted.duplicate(true)
	check(not Core.legacy_seed(mounted, request("phys-mounted", [])).ok and mounted == mounted_before, "a weapon mount that already carries hp is not overwritten")
	var rogue: Dictionary = ship(0.4)
	rogue.moduleCondition = {"version": 1, "birthNamespace": "phys-rogue", "nextItemSeq": 1, "repairPriority": "auto", "items": {}, "rogue": true}
	var rogue_before: Dictionary = rogue.duplicate(true)
	check(not Core.legacy_seed(rogue, request("phys-rogue", [part("engines", "stock_engine", "engine", 1.0)])).ok and rogue == rogue_before, "a corrupt new-schema record is not erased and reseeded")
	var typed: Dictionary = ship(0.4)
	check(not Core.legacy_seed(typed, request("launch", [])).ok and not typed.has("moduleCondition"), "the hull type id is not accepted as a physical item namespace")
	var generic: Dictionary = {"id": "launch", "type": "launch", "engine": 1.0}
	check(not Core.legacy_seed(generic, request("launch", [])).ok and not generic.has("moduleCondition"), "a generic spec id is not accepted as a physical item namespace")

func test_atomic_custody() -> void:
	var donor: Dictionary = ship(1.0)
	var host: Dictionary = ship(1.0)
	check(Core.legacy_seed(donor, request("phys-donor", [part("weapons", "rapid_gun", "mount0", 1.0), part("weapons", "light_cannon", "mount1", 1.0)])).ok, "donor seeds two weapons")
	check(Core.legacy_seed(host, request("phys-host", [part("weapons", "rapid_gun", "mount0", 1.0)])).ok, "host seeds its own weapon")
	var damaged: Dictionary = Core.apply_component_damage(donor.moduleCondition, {"itemUid": at(donor.moduleCondition, "mount0").itemUid, "loss": 0.5, "cause": "Splinter"})
	var uid: String = str(damaged.itemUid)
	check(damaged.ok and is_equal_approx(float(at(donor.moduleCondition, "mount0").hp), 0.5), "component damage sticks to the named part")
	var donor_snap: Dictionary = donor.moduleCondition.duplicate(true)
	var host_snap: Dictionary = host.moduleCondition.duplicate(true)
	var occupied: Dictionary = Core.transfer_exact(donor.moduleCondition, host.moduleCondition, {"itemUid": uid, "location": "mount0", "mountCount": 2, "hullType": "launch", "sourceMountCount": 2, "sourceHullType": "launch"})
	check(not occupied.ok and donor.moduleCondition == donor_snap and host.moduleCondition == host_snap, "transfer onto an occupied hardpoint changes neither hull")
	var duplicated: Dictionary = Core.transfer_exact(donor.moduleCondition, host.moduleCondition, {"itemUid": uid, "location": "locker", "mountCount": 2, "hullType": "launch", "sourceMountCount": 2, "sourceHullType": "launch", "knownUids": [uid]})
	check(not duplicated.ok and donor.moduleCondition == donor_snap and host.moduleCondition == host_snap, "a UID already registered elsewhere is not moved")
	var parked: Dictionary = Core.move_exact(donor.moduleCondition, {"itemUid": uid, "location": "locker", "mountCount": 2, "hullType": "launch"})
	check(parked.ok and is_equal_approx(float(parked.hp), 0.5) and str(at(donor.moduleCondition, "locker").itemUid) == uid, "the damaged part enters the locker without healing")
	var repaired: Dictionary = Core.repair_installed(donor.moduleCondition, {"work": 10.0, "supplies": 10.0, "hpPerWork": 1.0, "suppliesPerHp": {"weapons": 1.0}})
	check(repaired.ok and is_equal_approx(float(at(donor.moduleCondition, "locker").hp), 0.5), "locker stock is not repaired by the installed-part work pool")
	var returned: Dictionary = Core.move_exact(donor.moduleCondition, {"itemUid": uid, "location": "mount0", "mountCount": 2, "hullType": "launch"})
	check(returned.ok and str(returned.itemUid) == uid and is_equal_approx(float(at(donor.moduleCondition, "mount0").hp), 0.5) and str(at(donor.moduleCondition, "mount0").cause) == "Splinter", "the same damaged part returns to its hardpoint")
	var blocked_move: Dictionary = donor.moduleCondition.duplicate(true)
	check(not Core.move_exact(donor.moduleCondition, {"itemUid": at(donor.moduleCondition, "mount1").itemUid, "location": "mount0", "mountCount": 2, "hullType": "launch"}).ok and donor.moduleCondition == blocked_move, "a move onto an occupied hardpoint is rejected")
	var first_hp: float = float(at(donor.moduleCondition, "mount0").hp)
	var second_hp: float = float(at(donor.moduleCondition, "mount1").hp)
	var first_uid: String = str(at(donor.moduleCondition, "mount0").itemUid)
	var second_uid: String = str(at(donor.moduleCondition, "mount1").itemUid)
	var swapped: Dictionary = Core.swap_exact(donor.moduleCondition, {"firstUid": first_uid, "secondUid": second_uid, "mountCount": 2, "hullType": "launch"})
	check(swapped.ok and str(at(donor.moduleCondition, "mount1").itemUid) == first_uid and is_equal_approx(float(at(donor.moduleCondition, "mount1").hp), first_hp) and str(at(donor.moduleCondition, "mount0").itemUid) == second_uid and is_equal_approx(float(at(donor.moduleCondition, "mount0").hp), second_hp), "a swap exchanges places and keeps each part's damage")
	var moved: Dictionary = Core.transfer_exact(donor.moduleCondition, host.moduleCondition, {"itemUid": first_uid, "location": "locker", "mountCount": 2, "hullType": "launch", "sourceMountCount": 2, "sourceHullType": "launch"})
	check(moved.ok and is_equal_approx(float(moved.hp), first_hp) and not donor.moduleCondition.items.has(first_uid) and host.moduleCondition.items.has(first_uid) and int(donor.moduleCondition.nextItemSeq) == int(donor_snap.nextItemSeq), "transfer keeps the original UID and does not spend a serial")
	var shared: Dictionary = Core.collect_item_uids([donor.moduleCondition, host.moduleCondition])
	check(shared.ok, "after one transfer the two hulls still have no shared UID")

func test_repair_pool() -> void:
	var boat: Dictionary = ship(0.5)
	var gear: Array = [part("pumps", "hull_pumps", "pumps", 0.125), part("engines", "stock_engine", "engine", 0.5), part("armor", "stock_armor", "armor", 0.5), part("weapons", "rapid_gun", "mount0", 0.125), part("weapons", "light_cannon", "mount1", 0.125)]
	check(Core.legacy_seed(boat, request("phys-repair", gear)).ok, "repair fixture seeds")
	check(str(at(boat.moduleCondition, "pumps").status) == "disabled" and str(at(boat.moduleCondition, "mount0").status) == "disabled" and str(at(boat.moduleCondition, "engine").status) == "damaged", "birth hp at or below 0.20 is disabled and 0.50 is damaged")
	var rates: Dictionary = {"pumps": 1.0, "engines": 1.0, "weapons": 1.0}
	var first: Dictionary = Core.repair_installed(boat.moduleCondition, {"work": 0.25, "supplies": 10.0, "hpPerWork": 1.0, "suppliesPerHp": rates})
	check(first.ok and is_equal_approx(float(first.usedWork), 0.25) and is_equal_approx(float(first.usedSupplies), 0.25), "one work pool is debited once")
	check(is_equal_approx(float(at(boat.moduleCondition, "pumps").hp), 0.30) and str(at(boat.moduleCondition, "pumps").status) == "damaged", "disabled pumps are brought to the re-enable line before other spending")
	check(is_equal_approx(float(at(boat.moduleCondition, "mount0").hp), 0.20) and str(at(boat.moduleCondition, "mount0").status) == "disabled" and is_equal_approx(float(at(boat.moduleCondition, "mount1").hp), 0.125) and is_equal_approx(float(at(boat.moduleCondition, "engine").hp), 0.5) and is_equal_approx(float(at(boat.moduleCondition, "armor").hp), 0.5), "the same work is not spent again on the engine, armor, or the second weapon")
	var stalled: Dictionary = boat.moduleCondition.duplicate(true)
	var dry: Dictionary = Core.repair_installed(boat.moduleCondition, {"work": 10.0, "supplies": 0.0, "hpPerWork": 1.0, "suppliesPerHp": rates})
	var idle: Dictionary = Core.repair_installed(boat.moduleCondition, {"work": 0.0, "supplies": 10.0, "hpPerWork": 1.0, "suppliesPerHp": rates})
	check(dry.ok and idle.ok and float(dry.usedWork) == 0.0 and float(idle.usedWork) == 0.0 and boat.moduleCondition == stalled, "zero work or zero supplies heals nothing")
	var negative: Dictionary = boat.moduleCondition.duplicate(true)
	check(not Core.repair_installed(boat.moduleCondition, {"work": -1.0, "supplies": 10.0, "hpPerWork": 1.0, "suppliesPerHp": rates}).ok and boat.moduleCondition == negative, "a negative work budget is refused")
	var weapons_first: Dictionary = ship(0.125)
	check(Core.legacy_seed(weapons_first, request("phys-repair-weapons", [part("pumps", "hull_pumps", "pumps", 0.125), part("engines", "stock_engine", "engine", 0.125), part("weapons", "rapid_gun", "mount0", 0.125)])).ok, "priority fixture seeds")
	var aimed: Dictionary = Core.repair_installed(weapons_first.moduleCondition, {"work": 0.05, "supplies": 10.0, "hpPerWork": 1.0, "suppliesPerHp": rates, "priority": "weapons"})
	check(aimed.ok and is_equal_approx(float(at(weapons_first.moduleCondition, "mount0").hp), 0.175) and is_equal_approx(float(at(weapons_first.moduleCondition, "pumps").hp), 0.125) and is_equal_approx(float(at(weapons_first.moduleCondition, "engine").hp), 0.125), "an explicit weapons priority spends the only slice on the weapon")
	var finished: Dictionary = Core.repair_installed(boat.moduleCondition, {"work": 10.0, "supplies": 10.0, "hpPerWork": 1.0, "suppliesPerHp": rates})
	check(finished.ok and is_equal_approx(float(finished.usedWork), 1.875) and is_equal_approx(float(at(boat.moduleCondition, "pumps").hp), 0.75) and is_equal_approx(float(at(boat.moduleCondition, "engine").hp), 0.75) and is_equal_approx(float(at(boat.moduleCondition, "mount0").hp), 0.75) and is_equal_approx(float(at(boat.moduleCondition, "mount1").hp), 0.75), "remaining work reaches the jury cap across disabled and damaged parts")
	check(str(at(boat.moduleCondition, "pumps").status) == "damaged" and str(at(boat.moduleCondition, "mount0").status) == "damaged" and float(at(boat.moduleCondition, "pumps").hp) < 0.999 and is_equal_approx(float(at(boat.moduleCondition, "armor").hp), 0.5), "jury repair re-enables parts and does not restore them or the armor to sound")
	var paid_blocked: Dictionary = boat.moduleCondition.duplicate(true)
	check(not Core.restore_installed_paid(boat.moduleCondition, {}).ok and boat.moduleCondition == paid_blocked, "full restoration without a paid confirmation does nothing")
	var spare: Dictionary = Core.move_exact(boat.moduleCondition, {"itemUid": at(boat.moduleCondition, "mount1").itemUid, "location": "locker", "mountCount": 2, "hullType": "launch"})
	var spare_hp: float = float(spare.hp)
	var restored: Dictionary = Core.restore_installed_paid(boat.moduleCondition, {"confirmPaid": true})
	check(spare.ok and restored.ok and is_equal_approx(float(at(boat.moduleCondition, "engine").hp), 1.0) and str(at(boat.moduleCondition, "engine").status) == "ok" and is_equal_approx(float(at(boat.moduleCondition, "locker").hp), spare_hp) and float(restored.usedWork) == 0.0, "paid restoration completes installed parts and leaves the locker part damaged")

func test_stock_bounds_and_preview() -> void:
	var bare: Dictionary = ship(1.0)
	var asked: Dictionary = request("phys-bare", [part("weapons", "stock_primary", "mount0")])
	asked.loadout = {"weapons": ["stock_primary", ""], "engine": "stock_engine", "armor": ""}
	var before: Dictionary = bare.duplicate(true)
	check(not Core.legacy_seed(bare, asked).ok and bare == before, "a loadout that names a missing engine does not mint one")
	var no_pumps: Dictionary = ship(1.0)
	check(Core.legacy_seed(no_pumps, request("phys-no-pumps", [part("weapons", "stock_primary", "mount0")])).ok and at(no_pumps.moduleCondition, "pumps").is_empty() and not Core.project(no_pumps.moduleCondition).hasEngine, "absent pumps and an absent engine stay absent")
	var foreign: Dictionary = ship(1.0)
	check(Core.legacy_seed(foreign, request("phys-foreign", [part("weapons", "stock_primary", "mount0")])).ok, "factory primary seeds on its own hull")
	var other: Dictionary = ship(1.0)
	check(Core.legacy_seed(other, {"identity": "phys-other", "hullType": "cutter", "mountCount": 2, "installed": [], "engineScalar": 1.0}).ok and other.moduleCondition.items.is_empty(), "another design can exist with no parts")
	var stock_uid: String = str(at(foreign.moduleCondition, "mount0").itemUid)
	var foreign_snap: Dictionary = foreign.moduleCondition.duplicate(true)
	var other_snap: Dictionary = other.moduleCondition.duplicate(true)
	check(not Core.transfer_exact(foreign.moduleCondition, other.moduleCondition, {"itemUid": stock_uid, "location": "mount0", "mountCount": 2, "hullType": "cutter", "sourceMountCount": 2, "sourceHullType": "launch"}).ok and foreign.moduleCondition == foreign_snap and other.moduleCondition == other_snap, "a factory primary is not installed on another hull design")
	var preview_snap: Dictionary = other.moduleCondition.duplicate(true)
	var preview: Dictionary = Core.preview_next_item(other.moduleCondition)
	check(preview.ok and other.moduleCondition == preview_snap and int(preview.serial) == int(other.moduleCondition.nextItemSeq), "a read-only preview does not spend the serial")
	check(not Core.accept_acquired_item(other.moduleCondition, {"acquired": false, "family": "weapons", "typeId": "rapid_gun", "originHullType": "cutter", "location": "locker", "mountCount": 2, "hullType": "cutter"}).ok and other.moduleCondition == preview_snap, "an unpaid acquisition mints nothing")
	var bought: Dictionary = Core.accept_acquired_item(other.moduleCondition, {"acquired": true, "family": "weapons", "typeId": "rapid_gun", "originHullType": "cutter", "location": "locker", "mountCount": 2, "hullType": "cutter"})
	check(bought.ok and str(bought.itemUid) == str(preview.itemUid) and int(other.moduleCondition.nextItemSeq) == int(preview.serial) + 1, "the later real acquisition uses the serial the preview showed")
	var primary: Dictionary = ship(1.0)
	var bad_mount: Dictionary = request("phys-bad-mount", [part("weapons", "stock_primary", "mount1")])
	check(not Core.legacy_seed(primary, bad_mount).ok and not primary.has("moduleCondition"), "the factory primary is refused off the main hardpoint")
	var many: Dictionary = ship(1.0)
	var locker: Array = []
	for _i in 256:
		locker.append(part("weapons", "rapid_gun", "locker"))
	var filled: Dictionary = Core.legacy_seed(many, request("phys-locker-bound", [], locker))
	check(filled.ok and many.moduleCondition.items.size() == 256 and int(Core.list_locker(many.moduleCondition).counts.rapid_gun) == 256 and Core.project(many.moduleCondition).refitLocker.rapid_gun == 256, "256 locker parts, the current refit bound, are kept and only projected")
	var overflow: Dictionary = ship(1.0)
	var too_many: Array = locker.duplicate(true)
	too_many.append(part("weapons", "rapid_gun", "locker"))
	var overflow_before: Dictionary = overflow.duplicate(true)
	check(not Core.legacy_seed(overflow, request("phys-locker-over", [], too_many)).ok and overflow == overflow_before, "the 257th locker part refuses the seed instead of dropping one")

func round_trip(condition: Dictionary):
	return JSON.parse_string(JSON.stringify(condition))

func force_whole_floats(condition: Dictionary) -> void:
	condition.version = float(condition.version)
	condition.nextItemSeq = float(condition.nextItemSeq)
	if condition.has("legacyEngineSynced"):
		condition.legacyEngineSynced = float(condition.legacyEngineSynced)
	for key in condition.items.keys():
		var item: Dictionary = condition.items[key]
		item.hp = float(item.hp)
		item.lockerOrder = float(item.lockerOrder)

func test_json_roundtrip_custody_and_rates() -> void:
	var left: Dictionary = ship(0.25)
	var right: Dictionary = ship(1.0)
	var left_gear: Array = [part("weapons", "rapid_gun", "mount0", 0.5), part("weapons", "light_cannon", "mount1", 0.4), part("engines", "stock_engine", "engine", 0.25)]
	check(Core.legacy_seed(left, request("phys-json-a", left_gear, [part("weapons", "rapid_gun", "locker", 0.5)])).ok, "json fixture seeds the source hull")
	check(Core.legacy_seed(right, request("phys-json-b", [part("weapons", "stock_primary", "mount0"), part("engines", "stock_engine", "engine")])).ok, "json fixture seeds the destination hull")
	var birth_namespace: String = str(left.moduleCondition.birthNamespace)
	var serial: float = float(left.moduleCondition.nextItemSeq)
	var birth_uids: Array = Core.collect_item_uids([left.moduleCondition]).uids
	var engine_hp: float = float(at(left.moduleCondition, "engine").hp)
	var locker_uid: String = str(at(left.moduleCondition, "locker").itemUid)
	var locker_hp: float = float(at(left.moduleCondition, "locker").hp)
	var locker_order: float = float(at(left.moduleCondition, "locker").lockerOrder)
	var mount0_uid: String = str(at(left.moduleCondition, "mount0").itemUid)
	var mount1_uid: String = str(at(left.moduleCondition, "mount1").itemUid)
	var mount0_hp: float = float(at(left.moduleCondition, "mount0").hp)
	var mount1_hp: float = float(at(left.moduleCondition, "mount1").hp)
	var restored = round_trip(left.moduleCondition)
	var other = round_trip(right.moduleCondition)
	check(restored is Dictionary and other is Dictionary, "native JSON.stringify and parse_string return the owner dictionaries")
	check(str(restored.birthNamespace) == birth_namespace and is_equal_approx(float(restored.nextItemSeq), serial) and is_equal_approx(float(restored.version), 1.0), "a JSON round trip keeps the birth namespace, serial, and version value")
	check(restored.items.has(locker_uid) and restored.items.has(mount0_uid) and is_equal_approx(float(restored.items[locker_uid].hp), locker_hp) and is_equal_approx(float(restored.items[locker_uid].lockerOrder), locker_order) and str(restored.items[locker_uid].location) == "locker", "a JSON round trip keeps the locker UID, hp, order, and place")
	check(is_equal_approx(float(restored.items[mount0_uid].hp), mount0_hp) and is_equal_approx(float(at(restored, "engine").hp), engine_hp), "a JSON round trip keeps installed damage")
	force_whole_floats(restored)
	force_whole_floats(other)
	check(Core.validate(restored, {"mountCount": 2.0, "hullType": "launch"}).ok and Core.validate(other, {"mountCount": 2.0, "hullType": "launch"}).ok, "whole-valued floats from JSON validate, including a float mount count")
	var captured_before: Dictionary = restored.duplicate(true)
	var noted: Dictionary = Core.acknowledge_hull_uid(restored, "captured-json-7")
	check(noted.ok and not noted.changed and noted.birthNamespace == birth_namespace and is_equal_approx(float(noted.nextItemSeq), serial) and noted.itemUids == birth_uids and restored == captured_before, "a restored owner keeps its birth namespace and serial when the hull uid changes")
	var swapped: Dictionary = Core.swap_exact(restored, {"firstUid": mount0_uid, "secondUid": mount1_uid, "mountCount": 2.0, "hullType": "launch"})
	check(swapped.ok and str(at(restored, "mount0").itemUid) == mount1_uid and is_equal_approx(float(at(restored, "mount0").hp), mount1_hp) and str(at(restored, "mount1").itemUid) == mount0_uid and is_equal_approx(float(at(restored, "mount1").hp), mount0_hp), "a swap on the restored owner exchanges the same damaged parts")
	var moved: Dictionary = Core.transfer_exact(restored, other, {"itemUid": locker_uid, "location": "locker", "mountCount": 2.0, "hullType": "launch", "sourceMountCount": 2.0, "sourceHullType": "launch"})
	check(moved.ok and is_equal_approx(float(moved.hp), locker_hp) and str(moved.itemUid) == locker_uid and not restored.items.has(locker_uid) and other.items.has(locker_uid) and is_equal_approx(float(restored.nextItemSeq), serial) and is_equal_approx(float(other.nextItemSeq), float(right.moduleCondition.nextItemSeq)), "a transfer of the restored locker part keeps its UID and does not spend a serial")
	var shared: Dictionary = Core.collect_item_uids([restored, other])
	check(shared.ok and shared.uids.has(locker_uid) and shared.uids.has(mount0_uid), "after the transfer the two restored owners still have distinct UIDs")
	var engine_before: float = float(at(restored, "engine").hp)
	var repaired: Dictionary = Core.repair_installed(restored, {"work": 0.1, "supplies": 1.0, "hpPerWork": 1.0, "suppliesPerHp": {"engines": 2.0, "weapons": 2.0}})
	check(repaired.ok and is_equal_approx(float(repaired.usedWork), 0.1) and is_equal_approx(float(repaired.usedSupplies), 0.2) and is_equal_approx(float(at(restored, "engine").hp), engine_before + 0.1), "repair after a JSON round trip debits work and supplies once")
	var dry_before: Dictionary = restored.duplicate(true)
	var dry: Dictionary = Core.repair_installed(restored, {"work": 10.0, "supplies": 0.0, "hpPerWork": 1.0, "suppliesPerHp": {"engines": 2.0, "weapons": 2.0}})
	check(dry.ok and float(dry.usedWork) == 0.0 and float(dry.usedSupplies) == 0.0 and restored == dry_before, "zero supplies do not heal any installed part")
	var free_before: Dictionary = restored.duplicate(true)
	var free: Dictionary = Core.repair_installed(restored, {"work": 10.0, "supplies": 0.0, "hpPerWork": 1.0, "suppliesPerHp": {"engines": 0.0, "weapons": 1.0}})
	var priced_free: Dictionary = Core.repair_installed(restored, {"work": 10.0, "supplies": 10.0, "hpPerWork": 1.0, "suppliesPerHp": {"engines": 0.0}})
	check(not free.ok and not priced_free.ok and restored == free_before, "a zero material rate is refused and does not heal from an empty or full supply budget")
	var false_rate_before: Dictionary = restored.duplicate(true)
	check(not Core.repair_installed(restored, {"work": 10.0, "supplies": 10.0, "hpPerWork": 1.0, "suppliesPerHp": {"engines": true}}).ok and restored == false_rate_before, "a boolean supply rate is not treated as a number")
	var large_before_hp: float = float(at(restored, "engine").hp)
	var large: Dictionary = Core.repair_installed(restored, {"work": 1e20, "supplies": 1e20, "hpPerWork": 1e6, "suppliesPerHp": {"engines": 1e6, "weapons": 1e6}})
	check(large.ok and is_finite(float(large.usedWork)) and is_finite(float(large.usedSupplies)) and float(large.usedWork) > 0.0 and float(large.usedSupplies) > 0.0 and float(large.usedWork) <= 1e20 and float(large.usedSupplies) <= 1e20, "a large finite budget publishes a positive finite debit inside that budget")
	check(is_finite(float(at(restored, "engine").hp)) and float(at(restored, "engine").hp) > large_before_hp and float(at(restored, "engine").hp) <= 0.75 and is_finite(float(at(restored, "mount0").hp)) and float(at(restored, "mount0").hp) <= 0.75, "a large finite repair stays inside the jury cap and does not publish a non-finite condition")
	var extreme_ship: Dictionary = ship(0.5)
	check(Core.legacy_seed(extreme_ship, request("phys-json-extreme", [part("engines", "stock_engine", "engine", 0.5)])).ok, "extreme-rate fixture seeds")
	var extreme = round_trip(extreme_ship.moduleCondition)
	force_whole_floats(extreme)
	var extreme_before: Dictionary = extreme.duplicate(true)
	var extreme_repair: Dictionary = Core.repair_installed(extreme, {"work": 1e308, "supplies": 1e308, "hpPerWork": 1e308, "suppliesPerHp": {"engines": 1e308}})
	var extreme_clean: bool = extreme_repair.ok and is_finite(float(extreme_repair.usedWork)) and is_finite(float(extreme_repair.usedSupplies)) and float(extreme_repair.usedWork) >= 0.0 and float(extreme_repair.usedSupplies) >= 0.0 and float(extreme_repair.usedWork) <= 1e308 and float(extreme_repair.usedSupplies) <= 1e308 and is_finite(float(at(extreme, "engine").hp)) and float(at(extreme, "engine").hp) <= 0.75
	check(extreme_clean or (not extreme_repair.ok and extreme == extreme_before), "an overflowing intermediate either stays a finite nonnegative debit or leaves the owner unchanged")
	var broken = round_trip(left.moduleCondition)
	broken.nextItemSeq = 1.5
	var fraction_before: Dictionary = broken.duplicate(true)
	check(not Core.validate(broken, {"mountCount": 2.0, "hullType": "launch"}).ok and broken == fraction_before and is_equal_approx(float(broken.nextItemSeq), 1.5), "a fractional serial is rejected and is not truncated")
	var flagged = round_trip(left.moduleCondition)
	flagged.nextItemSeq = true
	var flagged_before: Dictionary = flagged.duplicate(true)
	check(not Core.validate(flagged, {"mountCount": 2, "hullType": "launch"}).ok and flagged == flagged_before, "a boolean serial is rejected")
	var named = round_trip(left.moduleCondition)
	named.nextItemSeq = "4"
	var named_before: Dictionary = named.duplicate(true)
	check(not Core.validate(named, {"mountCount": 2, "hullType": "launch"}).ok and named == named_before, "a string serial is rejected")
	var poisoned = round_trip(left.moduleCondition)
	poisoned.nextItemSeq = NAN
	var poisoned_before: Dictionary = poisoned.duplicate(true)
	check(not Core.validate(poisoned, {"mountCount": 2, "hullType": "launch"}).ok and is_nan(float(poisoned.nextItemSeq)) and str(poisoned.birthNamespace) == birth_namespace and poisoned.items.has(mount0_uid), "a NaN serial is rejected and left in place")
	var unbounded = round_trip(left.moduleCondition)
	unbounded.nextItemSeq = INF
	var unbounded_before: Dictionary = unbounded.duplicate(true)
	check(not Core.validate(unbounded, {"mountCount": 2, "hullType": "launch"}).ok and unbounded == unbounded_before, "an infinite serial is rejected")
	var misordered = round_trip(left.moduleCondition)
	misordered.items[mount0_uid].lockerOrder = 2.5
	var misordered_before: Dictionary = misordered.duplicate(true)
	check(not Core.validate(misordered, {"mountCount": 2, "hullType": "launch"}).ok and misordered == misordered_before, "a fractional locker order is rejected and is not truncated")
	var hull: Dictionary = ship(0.25)
	hull.moduleCondition = round_trip(left.moduleCondition)
	hull.moduleCondition.nextItemSeq = 2.5
	var hull_before: Dictionary = hull.duplicate(true)
	check(not Core.legacy_seed(hull, request("phys-json-a", left_gear)).ok and hull == hull_before, "a corrupt saved owner is not erased and reseeded")
	var hold: Dictionary = ship(1.0)
	var keep: Dictionary = ship(1.0)
	check(Core.legacy_seed(hold, request("phys-json-hold", [part("weapons", "rapid_gun", "mount0", 0.4)], [part("weapons", "light_cannon", "locker", 0.4)])).ok, "custody fixture seeds a locker part")
	check(Core.legacy_seed(keep, request("phys-json-keep", [part("weapons", "stock_primary", "mount0", 1.0)])).ok, "custody fixture seeds the other hull")
	var hold_saved = round_trip(hold.moduleCondition)
	var keep_saved = round_trip(keep.moduleCondition)
	force_whole_floats(hold_saved)
	force_whole_floats(keep_saved)
	var shared_uid: String = str(at(hold_saved, "locker").itemUid)
	var stolen: Dictionary = hold_saved.items[shared_uid].duplicate(true)
	stolen.location = "mount1"
	stolen.lockerOrder = 0.0
	keep_saved.items[shared_uid] = stolen
	var hold_before: Dictionary = hold_saved.duplicate(true)
	var keep_before: Dictionary = keep_saved.duplicate(true)
	var clash: Dictionary = Core.collect_item_uids([hold_saved, keep_saved])
	check(not clash.ok and str(clash.error).contains("share") and hold_saved == hold_before and keep_saved == keep_before, "the same UID in one hull's locker and another hull's hardpoint is refused for both")
	var wide: Dictionary = ship(1.0)
	var wide_request: Dictionary = request("phys-json-wide", [part("weapons", "stock_primary", "mount0"), part("weapons", "rapid_gun", "mount1"), part("weapons", "light_cannon", "mount2"), part("weapons", "rapid_gun", "mount3")])
	wide_request.mountCount = 4.0
	var widened: Dictionary = Core.legacy_seed(wide, wide_request)
	check(widened.ok and wide.moduleCondition.items.size() == 4 and str(at(wide.moduleCondition, "mount3").location) == "mount3", "four mounts, the current hardpoint ceiling, still seed")

func test_root_spare_and_registry_regressions() -> void:
	var boat: Dictionary = ship(0.4)
	var seed_request: Dictionary = request("phys-root-spares", [part("weapons", "stock_primary", "mount0", 0.35), part("engines", "stock_engine", "engine", 0.4)], [part("weapons", "rapid_gun", "locker", 0.5), part("weapons", "light_cannon", "locker", 0.6)])
	var seeded: Dictionary = Core.legacy_seed(boat, seed_request)
	check(seeded.ok, "spare fixture has two existing real locker parts")
	if not seeded.ok: return
	var original: Dictionary = boat.duplicate(true)
	var gun_uid: String = str(at(boat.moduleCondition, "mount0").itemUid)
	var parked: Dictionary = Core.move_exact(boat.moduleCondition, {"itemUid": gun_uid, "location": "locker", "mountCount": 2, "hullType": "launch"})
	check(parked.ok and Core.list_locker(boat.moduleCondition).items.size() == 3 and is_equal_approx(float(boat.moduleCondition.items[gun_uid].hp), 0.35), "a locker accepts a third distinct damaged spare rather than acting as one slot")
	boat = original.duplicate(true)
	var duplicate_request: Dictionary = seed_request.duplicate(true)
	duplicate_request.knownUids = [gun_uid]
	var before: Dictionary = boat.duplicate(true)
	check(not Core.legacy_seed(boat, duplicate_request).ok and boat == before, "idempotent ensure refuses a physical UID already owned elsewhere without touching this hull")
	var wrong_fit: Dictionary = seed_request.duplicate(true)
	wrong_fit.loadout = {"weapons": ["heavy_cannon", ""], "engine": "stock_engine", "armor": ""}
	check(not Core.legacy_seed(boat, wrong_fit).ok and boat == before, "idempotent ensure validates explicit loadout context instead of hiding a missing part")
	var preview: Dictionary = Core.preview_next_item(boat.moduleCondition)
	var old_count: int = boat.moduleCondition.items.size()
	var bought: Dictionary = Core.accept_acquired_item(boat.moduleCondition, {"acquired": true, "family": "weapons", "typeId": "rapid_gun", "originHullType": "launch", "location": "locker", "hp": 0.45, "cause": "Purchased used", "mountCount": 2, "hullType": "launch"})
	check(bought.ok and boat.moduleCondition.items.size() == old_count + 1 and str(bought.get("itemUid", "")) == str(preview.itemUid), "explicitly acquired real part is accepted once with the previewed monotonic identity")
	if bought.ok:
		check(is_equal_approx(float(boat.moduleCondition.items[str(bought.itemUid)].hp), 0.45) and int(boat.moduleCondition.nextItemSeq) == int(preview.serial) + 1, "acquisition retains used condition and advances only the accepted serial")
	var donor: Dictionary = original.duplicate(true)
	var receiver: Dictionary = ship(1.0)
	check(Core.legacy_seed(receiver, request("phys-root-receiver", [part("weapons", "rapid_gun", "mount0")])).ok, "separate receiver seeded")
	var engine: Dictionary = at(donor.moduleCondition, "engine").duplicate(true)
	engine.location = "locker"; engine.lockerOrder = 1
	receiver.moduleCondition.items[str(engine.itemUid)] = engine
	var donor_before: Dictionary = donor.duplicate(true)
	var receiver_before: Dictionary = receiver.duplicate(true)
	var transfer: Dictionary = Core.transfer_exact(donor.moduleCondition, receiver.moduleCondition, {"itemUid": gun_uid, "location": "locker", "mountCount": 2, "hullType": "launch", "sourceMountCount": 2, "sourceHullType": "launch"})
	check(not transfer.ok and donor == donor_before and receiver == receiver_before, "transfer refuses existing cross-owner corruption even when the moved item is a different UID")

func _initialize() -> void:
	test_root_spare_and_registry_regressions()
	test_scalar_cannot_heal()
	test_distinct_hulls_and_capture()
	test_corrupt_and_opaque_are_kept()
	test_atomic_custody()
	test_repair_pool()
	test_stock_bounds_and_preview()
	test_json_roundtrip_custody_and_rates()
	if failures > 0:
		push_error("equipment condition prototype stopped with %d unmet checks" % failures)
		quit(1)
	print("equipment condition prototype checks %d" % checks)
	quit(0)
