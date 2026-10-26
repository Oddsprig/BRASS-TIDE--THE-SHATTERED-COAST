extends RefCounted
## Pure campaign equipment preflight. Not wired into Campaign or Save.
## prepare_state copies the career, migrates it, and returns that copy.
## check_state only reads. Neither call writes the caller's career or the world.
## No scenes, workers, coins, RNG, or wall clock. No new hulls are built.
##
## prepare_state(saved, world) -> {ok, ready, state, migrated, legacy, physical, retired, holders, itemUids, message}
## check_state(state, world) -> {ok, ready, legacy, physical, retired, migrated, holders, itemUids, message}
## ready is true only when ok and no living hull is still legacy.
## Publish prepare_state().state only after the caller's other checks. This file does not publish it.
##
## Campaign.new_game finishes through CompanyOps.ensure. A story hull in that
## career already has uid legacy-{ownerId}-{ordinal}. story-0 boat 0 is
## legacy-story-0-0. Those uids are kept. They are not rewritten.
## A fleetOwners boat that still omits uid is named `{ownerId}-o{ordinal}`
## on the copy only. ordinal is its index in that owner's boats array.
## story-0's first omitted boat is story-0-o0. That proposal is a birth namespace.
## It is not a hull type, a battle slot, or a global counter.
## Player, npc-i-j, prize-N, owner-rN, and legacy-story-N-M uids already on a hull are kept.
## A canonical birthNamespace stays when a later hull uid changes.
## Birth namespaces are unique across living boats, held prizes, and active wrecks.
## One dictionary counts once. A shared namespace refuses. Nothing is rewritten.
## equipmentRetiredTo is not an owner and is not a namespace. A sunk hull that has
## it is never seeded, including after its wreck is transferred or removed.

const Recovery = preload("res://scripts/equipment_recovery.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Core = preload("res://scripts/equipment_condition.gd")
const Refits = preload("res://scripts/refit.gd")

const MARKER := "equipmentRetiredTo"

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "ready": false, "error": message, "message": message}

static func _remember(boat, originals: Array) -> void:
	if not boat is Dictionary:
		return
	for old in originals:
		if is_same(old, boat):
			return
	originals.append(boat)

static func _boat_lists(state: Dictionary) -> Array:
	var lists: Array = []
	if state.get("fleet") is Array:
		lists.append(state.fleet)
	if state.get("boardingPrizes") is Array:
		lists.append(state.boardingPrizes)
	if state.get("fleetOwners") is Array:
		for owner in state.fleetOwners:
			if owner is Dictionary and owner.get("boats") is Array:
				lists.append(owner.boats)
	return lists

static func _clone_boats(source: Dictionary, copy: Dictionary) -> void:
	var originals: Array = []
	for listed in _boat_lists(source):
		for boat in listed:
			_remember(boat, originals)
	var clones: Array = []
	for boat in originals:
		clones.append(boat.duplicate(true))
	var source_lists: Array = _boat_lists(source)
	var copy_lists: Array = _boat_lists(copy)
	for index in mini(source_lists.size(), copy_lists.size()):
		var rebuilt: Array = []
		for boat in source_lists[index]:
			var placed = boat
			if boat is Dictionary:
				var matched := false
				for found in range(originals.size()):
					if is_same(originals[found], boat):
						placed = clones[found]
						matched = true
						break
				if not matched:
					placed = boat.duplicate(true)
			rebuilt.append(placed)
		copy_lists[index].clear()
		for boat in rebuilt:
			copy_lists[index].append(boat)

static func prepare_state(saved: Dictionary, world: Dictionary) -> Dictionary:
	if not saved is Dictionary:
		return _fail("Campaign state is missing.")
	var copy: Dictionary = saved.duplicate(true)
	_clone_boats(saved, copy)
	var built: Dictionary = _compile(copy, world, true)
	if not built.ok:
		return built
	built.state = copy
	return built

static func check_state(state: Dictionary, world: Dictionary) -> Dictionary:
	if not state is Dictionary:
		return _fail("Campaign state is missing.")
	return _compile(state, world, false)

static func _world(world: Dictionary) -> Dictionary:
	if not world is Dictionary or not world.get("HULLS") is Array:
		return _fail("World definitions are unavailable.")
	if world.HULLS.is_empty():
		return _fail("World hull catalogue is empty.")
	var hulls: Dictionary = {}
	for hull in world.HULLS:
		if not hull is Dictionary or not Core._token(hull.get("id")):
			return _fail("World hull id is malformed.")
		var hull_id: String = str(hull.id)
		if hulls.has(hull_id):
			return _fail("World hull id is duplicated.")
		var info: Dictionary = Records._validate_base(hull, {"type": hull_id})
		if not info.ok:
			return _fail(str(info.get("error", "World hull definition is unreadable.")))
		hulls[hull_id] = hull
	return {"ok": true, "hulls": hulls}

static func _list(state: Dictionary, key: String) -> Dictionary:
	if not state.has(key):
		return {"ok": true, "rows": []}
	if not state.get(key) is Array:
		return _fail("A campaign owner list is unreadable.")
	return {"ok": true, "rows": state[key]}

static func _place(rows: Array, seen: Array, boat, owner_id: String, ordinal: int) -> Dictionary:
	if not boat is Dictionary:
		return _fail("A fleet entry is not a hull record.")
	for old in seen:
		if is_same(old, boat):
			return {"ok": true}
	seen.append(boat)
	rows.append({"boat": boat, "ownerId": owner_id, "ordinal": ordinal})
	return {"ok": true}

static func _rows(state: Dictionary) -> Dictionary:
	var rows: Array = []
	var seen: Array = []
	for key in ["fleet", "boardingPrizes"]:
		var listed: Dictionary = _list(state, key)
		if not listed.ok:
			return listed
		var index := 0
		for boat in listed.rows:
			var placed: Dictionary = _place(rows, seen, boat, "", index)
			if not placed.ok:
				return placed
			index += 1
	if state.has("fleetOwners"):
		if not state.fleetOwners is Array:
			return _fail("Fleet owners are unreadable.")
		for owner in state.fleetOwners:
			if not owner is Dictionary or not owner.get("boats") is Array:
				return _fail("A fleet owner record is unreadable.")
			var owner_id: String = str(owner.get("id", ""))
			var ordinal := 0
			for boat in owner.boats:
				var placed_owner: Dictionary = _place(rows, seen, boat, owner_id, ordinal)
				if not placed_owner.ok:
					return placed_owner
				ordinal += 1
	return {"ok": true, "rows": rows}

static func _identity_of(boat: Dictionary, owner_id: String, ordinal: int, hulls: Dictionary) -> Dictionary:
	if boat.has("uid") and str(boat.get("uid", "")) != "":
		if not boat.get("uid") is String or not Core._identity(boat.uid):
			return _fail("A hull uid is malformed.")
		if hulls.has(str(boat.uid)):
			return _fail("Item identity cannot default to a generic hull type id.")
		return {"ok": true, "identity": str(boat.uid), "assign": false}
	if boat.has("moduleCondition") and boat.moduleCondition is Dictionary and Core._identity(str(boat.moduleCondition.get("birthNamespace", ""))):
		var birth: String = str(boat.moduleCondition.birthNamespace)
		if hulls.has(birth):
			return _fail("Item identity cannot default to a generic hull type id.")
		return {"ok": true, "identity": birth, "assign": true}
	if owner_id != "" and Core._identity(owner_id):
		var derived: String = "%s-o%d" % [owner_id, ordinal]
		if not Core._identity(derived) or hulls.has(derived):
			return _fail("A derived hull namespace is malformed.")
		return {"ok": true, "identity": derived, "assign": true}
	return _fail("A hull has no stable uid.")

static func _sunk(boat: Dictionary) -> Dictionary:
	if not boat.has("sunk"):
		return {"ok": true, "sunk": false}
	if not boat.sunk is bool:
		return _fail("A hull sinking flag is unreadable.")
	return {"ok": true, "sunk": boat.sunk}

static func _marker(boat: Dictionary, sunk: bool) -> Dictionary:
	if not boat.has(MARKER):
		return {"ok": true, "retired": false}
	var raw = boat.get(MARKER)
	if not raw is String or not Core._identity(raw):
		return _fail("Retirement marker is unreadable.")
	if not sunk:
		return _fail("A living hull cannot use a retirement marker.")
	if boat.has("moduleCondition"):
		return _fail("A retired hull still carries equipment.")
	return {"ok": true, "retired": true}

static func _legacy_inputs(boat: Dictionary, base: Dictionary) -> Dictionary:
	if boat.has("engine") and not Core._unit(boat.get("engine")):
		return _fail("The legacy engine scalar is not a finite condition.")
	if not boat.has("engine"):
		return _fail("The legacy engine scalar is missing.")
	if boat.has("loadout"):
		if not boat.loadout is Dictionary:
			return _fail("Loadout is malformed.")
		var normal: Dictionary = Refits.normalize(base, boat.loadout)
		if not normal.ok:
			return _fail(str(normal.get("error", "Loadout is malformed.")))
	if boat.has("refitLocker"):
		var catalog: Dictionary = Refits.catalog()
		var families: Dictionary = Records._validate_catalog(catalog)
		if not families.ok:
			return _fail(str(families.get("error", "Equipment catalog is malformed.")))
		var parsed: Dictionary = Records._parse_legacy_locker(boat, families.familyByType, str(base.get("id", "")))
		if not parsed.ok:
			return _fail(str(parsed.get("error", "Refit locker is unreadable.")))
	return {"ok": true}

static func _locker_agrees(boat: Dictionary, base: Dictionary, condition: Dictionary) -> Dictionary:
	if not boat.has("refitLocker"):
		return {"ok": true}
	var catalog: Dictionary = Refits.catalog()
	var families: Dictionary = Records._validate_catalog(catalog)
	if not families.ok:
		return _fail(str(families.get("error", "Equipment catalog is malformed.")))
	var parsed: Dictionary = Records._parse_legacy_locker(boat, families.familyByType, str(base.get("id", "")))
	if not parsed.ok:
		return _fail(str(parsed.get("error", "Refit locker is unreadable.")))
	var projected: Dictionary = Core.project(condition)
	if not projected.ok:
		return _fail(str(projected.get("error", "Equipment projection failed.")))
	var counts: Dictionary = parsed.counts
	var live: Dictionary = projected.refitLocker
	for key in counts.keys():
		if int(counts[key]) != int(live.get(key, 0)):
			return _fail("Refit locker does not match the physical parts.")
	for key in live.keys():
		if int(live[key]) != int(counts.get(key, 0)):
			return _fail("Refit locker does not match the physical parts.")
	return {"ok": true}

static func _origins(condition: Dictionary, hulls: Dictionary) -> Dictionary:
	if not condition is Dictionary or not condition.get("items") is Dictionary:
		return _fail("Existing equipment condition is corrupt and was left untouched.")
	for key in condition.items.keys():
		var item = condition.items[key]
		if not item is Dictionary or not hulls.has(str(item.get("originHullType", ""))):
			return _fail("Equipment item origin is not a catalogue hull.")
	return {"ok": true}

static func _without(all_uids: Array, own: Array) -> Array:
	var skip: Dictionary = {}
	for uid in own:
		skip[str(uid)] = true
	var rest: Array = []
	for uid in all_uids:
		if not skip.has(str(uid)):
			rest.append(str(uid))
	return rest

static func _seed(boat: Dictionary, base: Dictionary, identity: String, known: Array) -> Dictionary:
	if boat.has("moduleCondition"):
		return _fail("Equipment condition is already present.")
	var source = boat.loadout if boat.get("loadout") is Dictionary else Refits.defaults(base)
	var normal: Dictionary = Refits.normalize(base, source)
	if not normal.ok:
		return _fail(str(normal.get("error", "Loadout is malformed.")))
	var clean: Dictionary = normal.loadout.duplicate(true)
	boat.loadout = clean
	var seeded: Dictionary = Records.initialize(boat, {
		"base": base.duplicate(true),
		"loadout": clean,
		"catalog": Refits.catalog(),
		"identity": identity,
		"knownUids": known.duplicate()
	})
	if not seeded.ok:
		return _fail(str(seeded.get("error", "Legacy equipment could not be prepared.")))
	if str(boat.moduleCondition.birthNamespace) != identity:
		return _fail("Existing parts keep their birth namespace.")
	return {"ok": true, "itemUids": seeded.get("itemUids", [])}

static func _absorb(boat: Dictionary) -> Dictionary:
	var structural: Dictionary = Core._records(boat.moduleCondition)
	if not structural.ok:
		return _fail(str(structural.get("error", "Existing equipment condition is corrupt and was left untouched.")))
	if bool(structural.get("hasEngine", false)):
		if not boat.has("engine") or not Core._unit(boat.get("engine")):
			return _fail("The legacy engine scalar is missing.")
		var absorbed: Dictionary = Records.absorb_legacy_damage(boat)
		if not absorbed.ok:
			return _fail(str(absorbed.get("error", "The legacy engine scalar is not a finite condition.")))
		var published: Dictionary = Records.publish(boat)
		if not published.ok:
			return _fail(str(published.get("error", "Equipment projection failed.")))
	elif boat.has("engine") and not Core._unit(boat.get("engine")):
		return _fail("The legacy engine scalar is not a finite condition.")
	var noted: Dictionary = Core.acknowledge_hull_uid(boat.moduleCondition, str(boat.get("uid", "")))
	if not noted.ok or str(noted.get("birthNamespace", "")) != str(boat.moduleCondition.birthNamespace):
		return _fail("Existing parts keep their birth namespace.")
	return {"ok": true}

static func _agree(hulls: Dictionary, base: Dictionary, loadout, condition: Dictionary, hull_uid: String, known: Array) -> Dictionary:
	var origins: Dictionary = _origins(condition, hulls)
	if not origins.ok:
		return origins
	if not loadout is Dictionary:
		return _fail("Loadout is missing.")
	var ready: Dictionary = Recovery.rehearse(base.duplicate(true), loadout, condition, hull_uid, known)
	if not ready.ok:
		return _fail(str(ready.get("error", ready.get("message", "Equipment does not agree with this hull."))))
	return {"ok": true}

static func _wrecks(state: Dictionary, hulls: Dictionary) -> Dictionary:
	var listed: Dictionary = _list(state, "wrecks")
	if not listed.ok:
		return listed
	var active: Array = []
	for wreck in listed.rows:
		if not wreck is Dictionary:
			return _fail("A wreck record is unreadable.")
		var problem: String = Recovery.refusal(wreck)
		if not problem.is_empty():
			return _fail(problem)
		if Recovery.is_active(wreck):
			var hull_id: String = str(wreck.get("hull", ""))
			if not hulls.has(hull_id):
				return _fail("World hull catalogue does not contain this wreck.")
			active.append(wreck)
	return {"ok": true, "active": active}

static func _claim_birth(table: Dictionary, birth_scope: String, owner) -> Dictionary:
	if not Core._identity(birth_scope):
		return _fail("Birth namespace is malformed.")
	if table.has(birth_scope) and not is_same(table[birth_scope], owner):
		return _fail("Two owners share one birth namespace.")
	table[birth_scope] = owner
	return {"ok": true}

## Hull uids and item uids are checked elsewhere. This is only birthNamespace.
## Retired markers and sunk hulls with no record are not owners. A proposal for a
## new legacy birth is checked against owners already in the table.
static func _births(jobs: Array, wrecks: Array) -> Dictionary:
	var table: Dictionary = {}
	for job in jobs:
		if bool(job.retired) or not bool(job.physical):
			continue
		var marked: Dictionary = _claim_birth(table, str(job.boat.moduleCondition.birthNamespace), job.boat)
		if not marked.ok:
			return marked
	for wreck in wrecks:
		var marked_wreck: Dictionary = _claim_birth(table, str(wreck.sourceModuleCondition.birthNamespace), wreck)
		if not marked_wreck.ok:
			return marked_wreck
	for job in jobs:
		if bool(job.retired) or bool(job.physical) or bool(job.sunk):
			continue
		var proposed: Dictionary = _claim_birth(table, str(job.identity), job.boat)
		if not proposed.ok:
			return proposed
	return {"ok": true}

static func _compile(state: Dictionary, world: Dictionary, write: bool) -> Dictionary:
	var gate: Dictionary = _world(world)
	if not gate.ok:
		return gate
	var hulls: Dictionary = gate.hulls
	var listed: Dictionary = _rows(state)
	if not listed.ok:
		return listed
	var wrecked: Dictionary = _wrecks(state, hulls)
	if not wrecked.ok:
		return wrecked
	var claimed: Dictionary = {}
	var jobs: Array = []
	for row in listed.rows:
		var boat: Dictionary = row.boat
		var sunk_flag: Dictionary = _sunk(boat)
		if not sunk_flag.ok:
			return sunk_flag
		if Core._foreign(boat):
			return _fail("Unrecognized condition metadata was left untouched.")
		var marked: Dictionary = _marker(boat, bool(sunk_flag.sunk))
		if not marked.ok:
			return marked
		var hull_id: String = str(boat.get("type", ""))
		if not hulls.has(hull_id):
			return _fail("World hull catalogue does not contain this hull.")
		var base: Dictionary = hulls[hull_id]
		if boat.has("moduleCondition"):
			if not boat.moduleCondition is Dictionary:
				return _fail("Existing equipment condition is corrupt and was left untouched.")
			var structural: Dictionary = Core._records(boat.moduleCondition)
			if not structural.ok:
				return _fail("Existing equipment condition is corrupt and was left untouched.")
		var inputs: Dictionary = _legacy_inputs(boat, base)
		if not inputs.ok:
			return inputs
		if boat.has("moduleCondition"):
			var counts: Dictionary = _locker_agrees(boat, base, boat.moduleCondition)
			if not counts.ok:
				return counts
		var named: Dictionary = _identity_of(boat, str(row.ownerId), int(row.ordinal), hulls)
		if not named.ok:
			return named
		var identity: String = str(named.identity)
		if claimed.has(identity) and not is_same(claimed[identity], boat):
			return _fail("Two hulls share one uid.")
		claimed[identity] = boat
		jobs.append({
			"boat": boat,
			"base": base,
			"identity": identity,
			"assign": bool(named.assign),
			"sunk": bool(sunk_flag.sunk),
			"retired": bool(marked.retired),
			"physical": boat.has("moduleCondition")
		})
	var births: Dictionary = _births(jobs, wrecked.active)
	if not births.ok:
		return births
	var known: Array = []
	for wreck in wrecked.active:
		for uid in Core._uid_list(wreck.sourceModuleCondition):
			known.append(str(uid))
	for job in jobs:
		if not job.physical:
			continue
		for uid in Core._uid_list(job.boat.moduleCondition):
			known.append(str(uid))
	var migrated := 0
	var legacy := 0
	var physical := 0
	var retired := 0
	for job in jobs:
		var boat: Dictionary = job.boat
		if job.retired:
			retired += 1
			continue
		if job.sunk and not job.physical:
			continue
		if job.physical:
			physical += 1
			if write and job.assign:
				boat.uid = str(job.identity)
			if write:
				var absorbed: Dictionary = _absorb(boat)
				if not absorbed.ok:
					return absorbed
			continue
		legacy += 1
		var scratch: Dictionary = boat if write else boat.duplicate(true)
		if job.assign:
			scratch.uid = str(job.identity)
		var seeded: Dictionary = _seed(scratch, job.base, str(job.identity), known)
		if not seeded.ok:
			return seeded
		for uid in seeded.get("itemUids", []):
			known.append(str(uid))
		if write:
			migrated += 1
			physical += 1
			legacy -= 1
	var scan: Dictionary = Recovery.registry(state, "", null)
	if not scan.ok:
		return _fail(str(scan.get("error", scan.get("message", "Two hulls share one physical part."))))
	var item_uids: Array = scan.get("uids", [])
	for job in jobs:
		if job.retired or (job.sunk and not job.boat.has("moduleCondition")):
			continue
		if not job.boat.has("moduleCondition"):
			continue
		var own: Array = Core._uid_list(job.boat.moduleCondition)
		var agreed: Dictionary = _agree(hulls, job.base, job.boat.get("loadout"), job.boat.moduleCondition, str(job.boat.get("uid", job.identity)), _without(item_uids, own))
		if not agreed.ok:
			return agreed
	for wreck in wrecked.active:
		var own_wreck: Array = Core._uid_list(wreck.sourceModuleCondition)
		var wreck_fit: Dictionary = _agree(hulls, hulls[str(wreck.hull)], wreck.get("sourceLoadout"), wreck.sourceModuleCondition, str(wreck.get("id", "wreck")), _without(item_uids, own_wreck))
		if not wreck_fit.ok:
			return wreck_fit
	var holders: Dictionary = Recovery.active_holders(state)
	if not holders.ok:
		return _fail(str(holders.get("error", holders.get("message", "A campaign owner list is unreadable."))))
	var ready := legacy == 0
	return {
		"ok": true,
		"ready": ready,
		"legacy": legacy,
		"physical": physical,
		"retired": retired,
		"migrated": migrated,
		"holders": holders.get("holders", []),
		"itemUids": item_uids,
		"message": "Equipment preflight is ready." if ready else "Legacy hulls still need prepare_state."
	}
