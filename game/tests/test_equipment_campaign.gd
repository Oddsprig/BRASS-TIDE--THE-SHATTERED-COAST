extends SceneTree
## Unrun native fixture. Sol runs this unchanged. No pass is claimed here.
## Headless campaign only. prepare_state is not a payment and does not publish.
const Campaign = preload("res://scripts/campaign.gd")
const Damage = preload("res://scripts/damage.gd")
const Condition = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Refit = preload("res://scripts/refit.gd")
const Preflight = preload("res://scripts/equipment_campaign.gd")

var world: Dictionary
var c
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL campaign-equipment: " + message)

func hull(id: String) -> Dictionary:
	for spec in world.HULLS:
		if str(spec.get("id", "")) == id:
			return spec
	return {}

func find_uid(state: Dictionary, uid: String) -> Dictionary:
	for boat in state.get("fleet", []):
		if boat is Dictionary and str(boat.get("uid", "")) == uid:
			return boat
	for boat in state.get("boardingPrizes", []):
		if boat is Dictionary and str(boat.get("uid", "")) == uid:
			return boat
	for owner in state.get("fleetOwners", []):
		if not owner is Dictionary:
			continue
		for boat in owner.get("boats", []):
			if boat is Dictionary and str(boat.get("uid", "")) == uid:
				return boat
	return {}

func legacy_career() -> Dictionary:
	var legacy: Dictionary = c.state.duplicate(true)
	for boat in legacy.get("fleet", []):
		if boat is Dictionary:
			boat.erase("moduleCondition")
	for boat in legacy.get("boardingPrizes", []):
		if boat is Dictionary:
			boat.erase("moduleCondition")
	for owner in legacy.get("fleetOwners", []):
		if not owner is Dictionary:
			continue
		for boat in owner.get("boats", []):
			if boat is Dictionary:
				boat.erase("moduleCondition")
	return legacy

func story_rows(state: Dictionary) -> Array:
	var rows: Array = []
	for owner in state.get("fleetOwners", []):
		if not owner is Dictionary or not str(owner.get("id", "")).begins_with("story-"):
			continue
		var ordinal := 0
		for boat in owner.get("boats", []):
			rows.append({"id": str(owner.id), "ordinal": ordinal, "boat": boat})
			ordinal += 1
	return rows

func item_at(condition: Dictionary, location: String) -> Dictionary:
	for key in condition.items.keys():
		var item: Dictionary = condition.items[key]
		if str(item.location) == location:
			return item
	return {}

func locker_of(condition: Dictionary, type_id: String) -> Array:
	var found: Array = []
	for key in condition.items.keys():
		var item: Dictionary = condition.items[key]
		if str(item.location) == "locker" and str(item.typeId) == type_id:
			found.append(item)
	return found

func same_ids(left: Dictionary, right: Dictionary) -> bool:
	if str(left.birthNamespace) != str(right.birthNamespace) or int(left.nextItemSeq) != int(right.nextItemSeq):
		return false
	var a: Array = Condition._uid_list(left)
	var b: Array = Condition._uid_list(right)
	if a != b:
		return false
	for key in a:
		var part_a: Dictionary = left.items[key]
		var part_b: Dictionary = right.items[key]
		if str(part_a.itemUid) != str(part_b.itemUid) or str(part_a.cause) != str(part_b.cause):
			return false
		if str(part_a.status) != str(part_b.status) or not is_equal_approx(float(part_a.hp), float(part_b.hp)):
			return false
	return true

func holder_ids(holders: Array, uid: String) -> int:
	var count := 0
	for row in holders:
		if row is Dictionary and str(row.get("id", "")) == uid:
			count += 1
	return count

func refuses(saved: Dictionary, label: String) -> void:
	var before: Dictionary = saved.duplicate(true)
	var denied: Dictionary = Preflight.prepare_state(saved, world)
	check(not denied.ok and not denied.has("state"), label)
	check(saved == before, label + " leaves the caller unchanged")

func refuses_birth(saved: Dictionary, label: String) -> void:
	var before: Dictionary = saved.duplicate(true)
	var denied: Dictionary = Preflight.prepare_state(saved, world)
	var looked: Dictionary = Preflight.check_state(saved, world)
	check(not denied.ok and not denied.has("state") and str(denied.message) == "Two owners share one birth namespace.", label)
	check(not looked.ok and str(looked.message) == "Two owners share one birth namespace.", label + " is the same on a read")
	check(saved == before, label + " leaves the caller unchanged")

func seeded_boat(uid: String, identity: String, known: Array) -> Dictionary:
	var spec: Dictionary = hull("tin_skiff")
	var boat: Dictionary = Damage.create_ship(spec, {"fuel": 0.0, "ammo": 0.0, "supplies": 0.0, "crew": 0.0})
	boat.uid = uid
	boat.loadout = Refit.defaults(spec)
	var seeded: Dictionary = Records.initialize(boat, {
		"base": spec.duplicate(true),
		"loadout": boat.loadout,
		"catalog": Refit.catalog(),
		"identity": identity,
		"knownUids": known.duplicate()
	})
	check(seeded.ok, "namespace seed " + uid)
	return boat

func core_ok(boat: Dictionary) -> bool:
	if not boat.has("moduleCondition") or not boat.get("loadout") is Dictionary:
		return false
	return Condition.validate(boat.moduleCondition, {
		"mountCount": boat.loadout.weapons.size(),
		"hullType": str(boat.type),
		"knownUids": [],
		"loadout": boat.loadout
	}).ok

func disjoint_items(left: Dictionary, right: Dictionary) -> bool:
	if not left.get("moduleCondition") is Dictionary or not right.get("moduleCondition") is Dictionary:
		return false
	var other: Dictionary = {}
	for uid in Condition._uid_list(right.moduleCondition):
		other[str(uid)] = true
	for uid in Condition._uid_list(left.moduleCondition):
		if other.has(str(uid)):
			return false
	return true

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		print("FAIL campaign-equipment: fixture is headless only")
		quit(1)
		return
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c = Campaign.new(world)
	c.new_game(31)
	roundtrip()
	ownership()
	story_identity()
	capture_and_scalars()
	retirement()
	birth_namespaces()
	rejections()
	batch_bound()
	print("Campaign equipment: %d checks, %d failures" % [checks, failures])
	print("NOTE campaign-equipment: this process was not a claimed pass. prepare_state does not publish, pay, or replenish.")
	quit(0 if failures == 0 else 1)

func roundtrip() -> void:
	var legacy: Dictionary = legacy_career()
	var career: Dictionary = legacy.duplicate(true)
	var looked: Dictionary = Preflight.check_state(legacy, world)
	check(looked.ok and not looked.ready and int(looked.legacy) > 0 and int(looked.migrated) == 0, "a synthetic pre-equipment career is readable and still legacy")
	check(legacy == career, "check_state does not write the live career")
	var hull_id: String = str(world.HULLS[0].id)
	var hull_keys: int = world.HULLS[0].size()
	var prepared: Dictionary = Preflight.prepare_state(legacy, world)
	check(prepared.ok and prepared.ready and int(prepared.migrated) > 0 and int(prepared.legacy) == 0, "prepare migrates the detached copy once")
	check(legacy == career, "prepare_state does not write the live career")
	check(str(world.HULLS[0].id) == hull_id and world.HULLS.size() == 24 and world.HULLS[0].size() == hull_keys, "the world catalogue is not written")
	check(not legacy.fleet[0].has("moduleCondition") and prepared.state.fleet[0].has("moduleCondition"), "the published copy is the only migrated fleet")
	check(int(prepared.state.coins) == int(career.coins) and int(prepared.state.crewPurse) == int(career.crewPurse), "coins and the crew purse are not replenished")
	check(int(prepared.state.nextUid) == int(career.nextUid), "prepare does not spend the hull uid counter")
	check(is_equal_approx(float(prepared.state.fleet[0].hp), float(career.fleet[0].hp)), "hull hit points are not repaired")
	check(int(prepared.state.fleet[0].crew) == int(career.fleet[0].crew), "crew is not recruited")
	check(prepared.state.ports[0].workforce == career.ports[0].workforce, "harbor workforce is not changed")
	var before_second: Dictionary = prepared.state.fleet[0].moduleCondition.duplicate(true)
	var again: Dictionary = Preflight.prepare_state(prepared.state, world)
	check(again.ok and int(again.migrated) == 0, "a second prepare seeds nothing")
	check(same_ids(prepared.state.fleet[0].moduleCondition, again.state.fleet[0].moduleCondition), "the second prepare keeps the same parts")
	check(prepared.state.fleet[0].moduleCondition == before_second, "the second prepare does not write the previous result")
	var text: String = JSON.stringify(prepared.state)
	var parsed = JSON.parse_string(text)
	check(parsed is Dictionary, "the prepared career can be stored as JSON")
	if parsed is Dictionary:
		var restored: Dictionary = Preflight.prepare_state(parsed, world)
		check(restored.ok and int(restored.migrated) == 0, "JSON roundtrip does not seed a second set")
		check(same_ids(prepared.state.fleet[0].moduleCondition, restored.state.fleet[0].moduleCondition), "JSON roundtrip keeps fleet item ids and hit points")

func ownership() -> void:
	var saved: Dictionary = legacy_career()
	saved.fleet[0].storedPort = "brass_haven"
	saved.fleet[0].mothballed = true
	saved.fleet[0].refitLocker = {"rapid_gun": 2}
	var prize: Dictionary = Damage.create_ship(hull("bilge_punt"), {"fuel": 0.0, "ammo": 0.0, "supplies": 0.0, "crew": 0.0})
	prize.uid = "prize-1"
	if not saved.get("boardingPrizes") is Array:
		saved.boardingPrizes = []
	saved.boardingPrizes.append(prize)
	var before: Dictionary = saved.duplicate(true)
	var prepared: Dictionary = Preflight.prepare_state(saved, world)
	check(prepared.ok, "stored, prize, and story hulls prepare")
	check(saved == before, "ownership prepare leaves its input unchanged")
	if not prepared.ok:
		return
	var player: Dictionary = prepared.state.fleet[0]
	check(str(player.storedPort) == "brass_haven" and bool(player.mothballed), "storage and support flags stay")
	check(str(player.moduleCondition.birthNamespace) == "boat-1", "the player birth namespace is the existing uid")
	var spares: Array = locker_of(player.moduleCondition, "rapid_gun")
	check(spares.size() == 2 and str(spares[0].itemUid) != str(spares[1].itemUid), "two loose parts of one type keep distinct ids")
	check(is_equal_approx(float(spares[0].hp), 1.0) and is_equal_approx(float(spares[1].hp), 1.0), "the loose parts are not repaired or damaged")
	var npc: Dictionary = find_uid(prepared.state, "npc-0-0")
	check(npc.has("moduleCondition") and str(npc.moduleCondition.birthNamespace) == "npc-0-0", "an existing npc uid is the birth namespace")
	var held: Dictionary = find_uid(prepared.state, "prize-1")
	check(held.has("moduleCondition") and str(held.moduleCondition.birthNamespace) == "prize-1", "a held prize uses its own uid")
	check(holder_ids(prepared.holders, "boat-1") == 1, "the player hull is one holder")
	var aliased: Dictionary = legacy_career()
	aliased.fleet.append(aliased.fleet[0])
	var alias_before: Dictionary = aliased.duplicate(true)
	var alias_run: Dictionary = Preflight.prepare_state(aliased, world)
	check(alias_run.ok and holder_ids(alias_run.holders, "boat-1") == 1, "one object stored twice is one owner")
	check(aliased.fleet[0] == alias_before.fleet[0], "the aliased caller hull is not rewritten")

func story_identity() -> void:
	var legacy: Dictionary = legacy_career()
	var stories: Array = story_rows(legacy)
	check(stories.size() > 0 and str(stories[0].boat.get("uid", "")) == "legacy-story-0-0", "story-0 boat 0 keeps legacy-story-0-0")
	var kept := true
	for row in stories:
		var expected: String = "legacy-%s-%d" % [str(row.id), int(row.ordinal)]
		if str(row.boat.get("uid", "")) != expected or row.boat.has("moduleCondition"):
			kept = false
	check(kept, "every final story uid is legacy-owner-ordinal and still has no parts")
	var prepared: Dictionary = Preflight.prepare_state(legacy, world)
	check(prepared.ok, "final story identities prepare")
	if not prepared.ok:
		return
	var prepared_rows: Array = story_rows(prepared.state)
	var same := prepared_rows.size() == stories.size()
	if same:
		for index in stories.size():
			var expected_uid: String = "legacy-%s-%d" % [str(stories[index].id), int(stories[index].ordinal)]
			var boat: Dictionary = prepared_rows[index].boat
			if str(boat.get("uid", "")) != expected_uid or not boat.has("moduleCondition"):
				same = false
			elif str(boat.moduleCondition.birthNamespace) != expected_uid:
				same = false
			elif not (Condition.mint_uid(expected_uid, 1) in Condition._uid_list(boat.moduleCondition)):
				same = false
	check(same, "prepare keeps each story uid, birth namespace, and parts")
	var again: Dictionary = Preflight.prepare_state(prepared.state, world)
	check(again.ok and not prepared_rows.is_empty() and same_ids(prepared_rows[0].boat.moduleCondition, story_rows(again.state)[0].boat.moduleCondition), "story parts are not reminted")
	check(str(story_rows(legacy)[0].boat.uid) == "legacy-story-0-0" and not story_rows(legacy)[0].boat.has("moduleCondition"), "the live story hull is not rewritten")
	var detached: Dictionary = legacy.duplicate(true)
	var omitted: Dictionary = story_rows(detached)[0].boat
	omitted.erase("uid")
	var fallback: Dictionary = Preflight.prepare_state(detached, world)
	check(fallback.ok, "a detached story hull with no uid still prepares")
	if fallback.ok:
		var named: Dictionary = story_rows(fallback.state)[0].boat
		check(str(named.get("uid", "")) == "story-0-o0" and str(named.moduleCondition.birthNamespace) == "story-0-o0", "the missing-uid copy is story-0-o0")
		check(Condition.mint_uid("story-0-o0", 1) in Condition._uid_list(named.moduleCondition), "that copy mints parts in the derived namespace")
	check(str(story_rows(legacy)[0].boat.uid) == "legacy-story-0-0", "the live story uid stays legacy-story-0-0")
	var blocked: Dictionary = legacy.duplicate(true)
	story_rows(blocked)[0].boat.erase("uid")
	var known: Array = []
	var holder: Dictionary = seeded_boat("held-birth", "mint-held", known)
	if not holder.has("moduleCondition"):
		return
	holder.moduleCondition.birthNamespace = "story-0-o0"
	var held_uids: Array = Condition._uid_list(holder.moduleCondition)
	check(core_ok(holder) and not held_uids.is_empty() and str(held_uids[0]) != Condition.mint_uid("story-0-o0", 1), "the blocking owner is valid and its parts were not minted in story-0-o0")
	if not blocked.get("boardingPrizes") is Array:
		blocked.boardingPrizes = []
	blocked.boardingPrizes.append(holder)
	refuses_birth(blocked, "a missing-uid story proposal that hits an existing birth namespace is refused")

func capture_and_scalars() -> void:
	var low: Dictionary = legacy_career()
	low.fleet[0].engine = 0.10
	var low_run: Dictionary = Preflight.prepare_state(low, world)
	check(low_run.ok, "a lower legacy scalar prepares")
	if low_run.ok:
		var born: Dictionary = item_at(low_run.state.fleet[0].moduleCondition, "engine")
		check(is_equal_approx(float(born.hp), 0.10) and str(born.status) == "disabled", "migration keeps 0.10 and does not heal the engine")
		check(is_equal_approx(float(low.fleet[0].engine), 0.10) and not low.fleet[0].has("moduleCondition"), "the lower-scalar caller is unchanged")
	var base_run: Dictionary = Preflight.prepare_state(legacy_career(), world)
	check(base_run.ok, "canonical scalar cases start from one prepare")
	if not base_run.ok:
		return
	var damaged: Dictionary = base_run.state.duplicate(true)
	var engine_uid: String = str(item_at(damaged.fleet[0].moduleCondition, "engine").itemUid)
	damaged.fleet[0].engine = 0.10
	var down: Dictionary = Preflight.prepare_state(damaged, world)
	check(down.ok, "downward absorb prepares")
	if down.ok:
		var lowered: Dictionary = item_at(down.state.fleet[0].moduleCondition, "engine")
		check(str(lowered.itemUid) == engine_uid and is_equal_approx(float(lowered.hp), 0.10), "downward absorb keeps the id and the lower hit points")
		check(str(lowered.cause) == "Legacy engine scalar" and str(lowered.status) == "disabled", "downward absorb records the scalar cause")
		check(is_equal_approx(float(damaged.fleet[0].engine), 0.10) and is_equal_approx(float(item_at(damaged.fleet[0].moduleCondition, "engine").hp), 1.0), "downward absorb does not write the caller")
	var raised: Dictionary = down.state.duplicate(true) if down.ok else base_run.state.duplicate(true)
	var raised_uid: String = str(item_at(raised.fleet[0].moduleCondition, "engine").itemUid)
	var raised_hp: float = float(item_at(raised.fleet[0].moduleCondition, "engine").hp)
	raised.fleet[0].engine = 0.95
	var up: Dictionary = Preflight.prepare_state(raised, world)
	check(up.ok, "an upward scalar prepares")
	if up.ok:
		var kept: Dictionary = item_at(up.state.fleet[0].moduleCondition, "engine")
		check(str(kept.itemUid) == raised_uid and is_equal_approx(float(kept.hp), raised_hp), "an upward scalar does not heal the part")
		check(float(up.state.fleet[0].engine) <= float(kept.hp) + 0.0001, "the prepared scalar is not above the part")
	var renamed: Dictionary = base_run.state.duplicate(true)
	var birth: Dictionary = renamed.fleet[0].moduleCondition.duplicate(true)
	renamed.fleet[0].uid = "prize-9"
	var captured: Dictionary = Preflight.prepare_state(renamed, world)
	check(captured.ok, "a renamed hull uid prepares")
	if captured.ok:
		check(str(captured.state.fleet[0].uid) == "prize-9", "the captured uid stays on the copy")
		check(same_ids(birth, captured.state.fleet[0].moduleCondition), "birth, ids, hit points, and cause survive the rename")
		check(str(captured.state.fleet[0].moduleCondition.birthNamespace) == "boat-1" and str(captured.state.fleet[0].uid) == "prize-9", "a renamed hull keeps its own birth namespace")
		check(str(renamed.fleet[0].uid) == "prize-9" and same_ids(birth, renamed.fleet[0].moduleCondition), "the rename caller is otherwise unchanged")

func retirement() -> void:
	var saved: Dictionary = legacy_career()
	var npc: Dictionary = find_uid(saved, "npc-0-0")
	npc.sunk = true
	var grave: Dictionary = Preflight.prepare_state(saved, world)
	check(grave.ok, "a sunk legacy hull does not block the other hulls")
	if grave.ok:
		var quiet: Dictionary = find_uid(grave.state, "npc-0-0")
		check(not quiet.has("moduleCondition") and not quiet.has("equipmentRetiredTo"), "a graveyard hull is not seeded")
		check(grave.state.fleet[0].has("moduleCondition"), "living hulls still migrate beside a graveyard hull")
	var marked: Dictionary = legacy_career()
	var source: Dictionary = find_uid(marked, "npc-0-0")
	source.sunk = true
	source.equipmentRetiredTo = "wreck-4"
	marked.wrecks = []
	var pruned: Dictionary = Preflight.prepare_state(marked, world)
	check(pruned.ok, "a retirement marker still prepares after the wreck is gone")
	if pruned.ok:
		var retired: Dictionary = find_uid(pruned.state, "npc-0-0")
		check(str(retired.equipmentRetiredTo) == "wreck-4" and not retired.has("moduleCondition"), "pruning does not reseed or clear the marker")
	var parked: Dictionary = legacy_career()
	var held_source: Dictionary = find_uid(parked, "npc-0-0")
	held_source.sunk = true
	held_source.equipmentRetiredTo = "wreck-4"
	parked.wrecks = [{"id": "wreck-4", "hull": str(held_source.type), "status": "towed", "equipmentCustody": "transferred"}]
	var transferred: Dictionary = Preflight.prepare_state(parked, world)
	check(transferred.ok and not find_uid(transferred.state, "npc-0-0").has("moduleCondition"), "transferred custody does not reseed the source")
	var named_marker: Dictionary = legacy_career()
	var marked_npc: Dictionary = find_uid(named_marker, "npc-0-0")
	marked_npc.sunk = true
	marked_npc.equipmentRetiredTo = "boat-1"
	var marker_run: Dictionary = Preflight.prepare_state(named_marker, world)
	check(marker_run.ok and str(find_uid(marker_run.state, "npc-0-0").equipmentRetiredTo) == "boat-1", "a retirement marker is not a birth namespace")
	check(marker_run.ok and str(marker_run.state.fleet[0].moduleCondition.birthNamespace) == "boat-1", "the player namespace stays beside that marker")
	var living: Dictionary = legacy_career()
	var live_npc: Dictionary = find_uid(living, "npc-0-0")
	live_npc.equipmentRetiredTo = "wreck-4"
	refuses(living, "a living hull cannot hide behind a retirement marker")
	var bad_mark: Dictionary = legacy_career()
	var bad_npc: Dictionary = find_uid(bad_mark, "npc-0-0")
	bad_npc.sunk = true
	bad_npc.equipmentRetiredTo = 4
	refuses(bad_mark, "a non-string retirement marker is refused")

func birth_namespaces() -> void:
	var known: Array = []
	var left: Dictionary = seeded_boat("hull-a", "mint-a", known)
	if not left.has("moduleCondition"):
		return
	for uid in Condition._uid_list(left.moduleCondition):
		known.append(str(uid))
	var right: Dictionary = seeded_boat("hull-b", "mint-b", known)
	if not right.has("moduleCondition"):
		return
	check(str(left.uid) != str(right.uid) and disjoint_items(left, right), "the pair has different hulls and no shared item")
	check(core_ok(left) and core_ok(right), "each owner is valid on its own")
	var separate: Dictionary = {"fleet": [left], "boardingPrizes": [right], "fleetOwners": [], "wrecks": []}
	var separate_run: Dictionary = Preflight.check_state(separate, world)
	check(separate_run.ok, "a boat and a held prize with different birth namespaces still pass")
	var alias_run: Dictionary = Preflight.check_state({"fleet": [left, left], "boardingPrizes": [], "fleetOwners": [], "wrecks": []}, world)
	check(alias_run.ok, "one physical boat stored twice is one birth namespace")
	left.moduleCondition.birthNamespace = "shared-birth"
	right.moduleCondition.birthNamespace = "shared-birth"
	check(core_ok(left) and core_ok(right) and disjoint_items(left, right), "the shared namespace leaves each owner valid and its items disjoint")
	check(str(left.moduleCondition.birthNamespace) == "shared-birth" and str(right.moduleCondition.birthNamespace) == "shared-birth", "the pair shares one birth namespace")
	var packed: Dictionary = {"fleet": [left], "boardingPrizes": [right], "fleetOwners": [], "wrecks": []}
	refuses_birth(packed, "distinct hulls that share a birth namespace are refused")
	var wreck_known: Array = []
	var wreck_boat: Dictionary = seeded_boat("hull-w", "mint-w", wreck_known)
	if not wreck_boat.has("moduleCondition"):
		return
	for uid in Condition._uid_list(wreck_boat.moduleCondition):
		wreck_known.append(str(uid))
	var wreck_peer: Dictionary = seeded_boat("hull-v", "mint-v", wreck_known)
	if not wreck_peer.has("moduleCondition"):
		return
	check(core_ok(wreck_boat) and core_ok(wreck_peer) and disjoint_items(wreck_boat, wreck_peer), "the wreck pair is valid and its items do not overlap")
	var wreck: Dictionary = {
		"id": "wreck-birth",
		"hull": str(wreck_boat.type),
		"status": "unclaimed",
		"equipmentCustody": "wreck",
		"sourceLoadout": wreck_peer.loadout.duplicate(true),
		"sourceModuleCondition": wreck_peer.moduleCondition.duplicate(true)
	}
	var apart: Dictionary = {"fleet": [wreck_boat], "boardingPrizes": [], "fleetOwners": [], "wrecks": [wreck]}
	var apart_run: Dictionary = Preflight.check_state(apart, world)
	check(apart_run.ok, "an active wreck with its own birth namespace still passes")
	wreck_boat.moduleCondition.birthNamespace = "shared-birth"
	wreck.sourceModuleCondition.birthNamespace = "shared-birth"
	check(core_ok(wreck_boat) and Condition.validate(wreck.sourceModuleCondition, {"mountCount": wreck_peer.loadout.weapons.size(), "hullType": str(wreck_boat.type), "knownUids": [], "loadout": wreck_peer.loadout}).ok, "the shared wreck namespace is still valid on each owner")
	check(disjoint_items(wreck_boat, {"moduleCondition": wreck.sourceModuleCondition}), "the wreck collision does not reuse an item uid")
	var with_wreck: Dictionary = {"fleet": [wreck_boat], "boardingPrizes": [], "fleetOwners": [], "wrecks": [wreck]}
	refuses_birth(with_wreck, "an active wreck that shares a birth namespace is refused")

func rejections() -> void:
	var twin: Dictionary = legacy_career()
	var copy: Dictionary = twin.fleet[0].duplicate(true)
	twin.fleet.append(copy)
	refuses(twin, "two hulls with one uid are refused")
	var corrupt: Dictionary = legacy_career()
	corrupt.fleet[0].moduleCondition = {"version": 1}
	refuses(corrupt, "a present corrupt record is not reseeded")
	var foreign: Dictionary = legacy_career()
	foreign.fleet[0].equipmentCondition = {"hp": 1}
	refuses(foreign, "foreign equipment metadata is left untouched")
	var nan_engine: Dictionary = legacy_career()
	nan_engine.fleet[0].engine = NAN
	var nan_coins: int = int(nan_engine.coins)
	var nan_denied: Dictionary = Preflight.prepare_state(nan_engine, world)
	check(not nan_denied.ok and not nan_engine.fleet[0].has("moduleCondition"), "a NaN engine scalar is refused")
	check(int(nan_engine.coins) == nan_coins and is_nan(float(nan_engine.fleet[0].engine)), "the NaN caller career stays")
	var ready: Dictionary = Preflight.prepare_state(legacy_career(), world)
	check(ready.ok, "rejection fixtures can start from a prepared copy")
	if not ready.ok:
		return
	var unknown_part: Dictionary = ready.state.duplicate(true)
	item_at(unknown_part.fleet[0].moduleCondition, "mount0").typeId = "ghost_gun"
	refuses(unknown_part, "an unknown catalog type is refused")
	var unknown_origin: Dictionary = ready.state.duplicate(true)
	item_at(unknown_origin.fleet[0].moduleCondition, "mount0").originHullType = "ghost_hull"
	refuses(unknown_origin, "an origin outside the 24 hulls is refused")
	var bad_loadout: Dictionary = ready.state.duplicate(true)
	bad_loadout.fleet[0].loadout.weapons.append("rapid_gun")
	refuses(bad_loadout, "a loadout that does not match the hull is refused")
	var bad_slot: Dictionary = ready.state.duplicate(true)
	var moved: Dictionary = item_at(bad_slot.fleet[0].moduleCondition, "mount0")
	moved.typeId = "rapid_gun"
	moved.location = "mount3"
	refuses(bad_slot, "a weapon on a missing hardpoint is refused")
	var bad_counter: Dictionary = ready.state.duplicate(true)
	bad_counter.fleet[0].moduleCondition.nextItemSeq = NAN
	var counter_coins: int = int(bad_counter.coins)
	var counter_denied: Dictionary = Preflight.prepare_state(bad_counter, world)
	check(not counter_denied.ok and is_nan(float(bad_counter.fleet[0].moduleCondition.nextItemSeq)), "a NaN item counter is refused and kept")
	check(int(bad_counter.coins) == counter_coins, "the NaN counter refusal does not move coins")
	var bad_wreck: Dictionary = ready.state.duplicate(true)
	bad_wreck.wrecks = [{"id": "wreck-9", "status": "towed", "equipmentCustody": "transferred", "sourceModuleCondition": {"version": 1}}]
	refuses(bad_wreck, "transferred custody that still holds a payload is refused")

func batch_bound() -> void:
	var spec: Dictionary = hull("tin_skiff")
	var boats: Array = []
	var known: Array = []
	var loadout: Dictionary = Refit.defaults(spec)
	for index in range(513):
		var boat: Dictionary = Damage.create_ship(spec, {"fuel": 0.0, "ammo": 0.0, "supplies": 0.0, "crew": 0.0})
		boat.uid = "batch-%04d" % index
		boat.loadout = loadout.duplicate(true)
		var seeded: Dictionary = Records.initialize(boat, {"base": spec.duplicate(true), "loadout": boat.loadout, "catalog": Refit.catalog(), "identity": boat.uid, "knownUids": known.duplicate()})
		check(seeded.ok, "batch seed %d" % index)
		if not seeded.ok:
			return
		for uid in seeded.get("itemUids", []):
			known.append(str(uid))
		boats.append(boat)
	var packed: Dictionary = {"fleet": [], "fleetOwners": [{"id": "batch-yard", "boats": boats}], "boardingPrizes": [], "wrecks": []}
	var fingerprint: Dictionary = boats[0].moduleCondition.duplicate(true)
	var clean: Dictionary = Preflight.check_state(packed, world)
	check(clean.ok and clean.ready and int(clean.physical) == 513, "513 owners are checked without a new roster cap")
	check(boats[0].moduleCondition == fingerprint, "the batch check does not rewrite a hull")
	var dirty: Dictionary = packed.duplicate(true)
	var donor: String = str(item_at(dirty.fleetOwners[0].boats[0].moduleCondition, "mount0").itemUid)
	var host: Dictionary = dirty.fleetOwners[0].boats[512]
	var copied: Dictionary = dirty.fleetOwners[0].boats[0].moduleCondition.items[donor].duplicate(true)
	copied.location = "locker"
	copied.lockerOrder = 4
	copied.itemUid = donor
	host.erase("refitLocker")
	host.moduleCondition.items[donor] = copied
	var crossed: Dictionary = Preflight.check_state(dirty, world)
	check(not crossed.ok, "a repeated item uid across the 512 boundary is refused")
	check(str(host.moduleCondition.items[donor].itemUid) == donor, "the crossed record is left in place")
