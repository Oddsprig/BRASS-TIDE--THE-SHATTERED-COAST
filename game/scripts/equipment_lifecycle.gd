extends RefCounted
## Staging and adoption for one equipment birth. Read-only until the caller publishes.
## stage_birth does not write counters, purses, stock, people, or lists.
## adopt copies an accepted boat. It does not initialize, attach, or refuse.
## A preserved birth keeps its namespace, item ids, part hp, cause, and serial.
## The new hull uid is the only identity that changes. Hull hp is not raised.
## A wreck source must use the fitted 0.35 tow contract, not a requested hp.
## A new legacy or site recovery is staged disabled, before payment, on a private blank.
## Older careers that still have no moduleCondition keep the normal migration.
## Source exclusion is the wreck or the one boat that actually holds these parts.
## An unknown uid is not skipped, so a live custodian cannot be cloned.
## Frozen preflight and recovery are called, not edited.

const Damage = preload("res://scripts/damage.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Recovery = preload("res://scripts/equipment_recovery.gd")
const Refits = preload("res://scripts/refit.gd")
const Core = preload("res://scripts/equipment_condition.gd")
const Preflight = preload("res://scripts/equipment_campaign.gd")

## Same fraction Salvage stamps on a paid tow. Effective fitted max HP, not a request.
const TOW_HP_FRACTION := 0.35
const NEXT_UID_LIMIT := 9007199254740991
const LEGACY_RECOVERY_CAUSE := "Legacy wreck recovery"

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message, "error": message}

static func _remember(rows: Array, boat) -> void:
	if not boat is Dictionary:
		return
	for old in rows:
		if is_same(old, boat):
			return
	rows.append(boat)

static func _boats(state: Dictionary) -> Array:
	var rows: Array = []
	for key in ["fleet", "boardingPrizes"]:
		var listed = state.get(key, [])
		if listed is Array:
			for boat in listed:
				_remember(rows, boat)
	var owners = state.get("fleetOwners", [])
	if owners is Array:
		for owner in owners:
			if owner is Dictionary and owner.get("boats") is Array:
				for boat in owner.boats:
					_remember(rows, boat)
	return rows

static func _uid_taken(state: Dictionary, uid: String) -> bool:
	for boat in _boats(state):
		if str(boat.get("uid", "")) == uid:
			return true
	return false

static func _birth_owner(state: Dictionary, birth_scope: String, skip_uid: String, skip_wreck: String):
	for boat in _boats(state):
		if not skip_uid.is_empty() and str(boat.get("uid", "")) == skip_uid:
			continue
		if boat.has("equipmentRetiredTo"):
			continue
		if boat.get("sunk", false) == true and not boat.has("moduleCondition"):
			continue
		if boat.get("moduleCondition") is Dictionary:
			if str(boat.moduleCondition.get("birthNamespace", "")) == birth_scope:
				return boat
		elif str(boat.get("uid", "")) == birth_scope:
			return boat
	var wrecks = state.get("wrecks", [])
	if wrecks is Array:
		for wreck in wrecks:
			if not wreck is Dictionary or str(wreck.get("id", "")) == skip_wreck:
				continue
			if Recovery.is_active(wreck) and str(wreck.sourceModuleCondition.get("birthNamespace", "")) == birth_scope:
				return wreck
	return null

static func _uids_of(condition: Dictionary) -> Array:
	if not condition is Dictionary or not Core._records(condition).ok:
		return []
	return Core._uid_list(condition)

static func _same_uids(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	var seen: Dictionary = {}
	for uid in left:
		seen[str(uid)] = true
	for uid in right:
		if not seen.has(str(uid)):
			return false
	return true

static func _known(scan: Dictionary) -> Array:
	var uids: Array = []
	for uid in scan.get("uids", []):
		uids.append(str(uid))
	return uids

static func _overlaps(known: Array, own: Array) -> bool:
	var seen: Dictionary = {}
	for uid in known:
		seen[str(uid)] = true
	for uid in own:
		if seen.has(str(uid)):
			return true
	return false

static func _spec_id(spec: Dictionary) -> String:
	return str(spec.get("id", ""))

static func _loadout_for(spec: Dictionary, supplied) -> Dictionary:
	if supplied is Dictionary:
		var given: Dictionary = Refits.normalize(spec, supplied)
		if given.ok:
			return given.loadout
	var normal: Dictionary = Refits.normalize(spec, Refits.defaults(spec))
	if normal.ok:
		return normal.loadout
	return {}

## Read-only. Hull points a tow may restore: 0.35 of the fitted design maximum.
## Empty loadout keeps the hull defaults. A provided loadout is normalized alone.
## Other births still use _loadout_for, which may fall back to those defaults.
static func tow_contract(spec: Dictionary, loadout) -> Dictionary:
	var fitted_loadout: Dictionary = {}
	if not loadout is Dictionary:
		return _fail("Preserved loadout is unreadable.")
	if loadout.is_empty():
		var defaults: Dictionary = Refits.normalize(spec, {})
		if not bool(defaults.get("ok", false)):
			return _fail("Preserved loadout is unreadable.")
		fitted_loadout = defaults.loadout
	else:
		var given: Dictionary = Refits.normalize(spec, loadout)
		if not bool(given.get("ok", false)):
			return _fail("Preserved loadout is unreadable.")
		fitted_loadout = given.loadout
	if fitted_loadout.is_empty():
		return _fail("Preserved loadout is unreadable.")
	var fitted: Dictionary = Refits.effective_spec(spec, fitted_loadout)
	if fitted.is_empty():
		return _fail("Preserved loadout is unreadable.")
	var max_hp := maxf(1.0, float(fitted.get("hp", 1.0)))
	return {"ok": true, "maxHp": max_hp, "hullHp": max_hp * TOW_HP_FRACTION}

## Read-only. The next boat-N must be a positive whole uid that nobody holds.
static func next_hull_uid(state: Dictionary) -> Dictionary:
	var raw = state.get("nextUid", null)
	if raw is bool or not (raw is int or raw is float):
		return _fail("The next hull uid is not a positive whole number.")
	if raw is int:
		if raw < 1 or raw > NEXT_UID_LIMIT:
			return _fail("The next hull uid is not a positive whole number.")
	else:
		var n := float(raw)
		if not is_finite(n) or n < 1.0 or n > float(NEXT_UID_LIMIT) or floor(n) != n:
			return _fail("The next hull uid is not a positive whole number.")
	var uid := "boat-%d" % int(raw)
	if _uid_taken(state, uid):
		return _fail("Two hulls share one uid.")
	if _birth_owner(state, uid, "", "") != null:
		return _fail("Two owners share one birth namespace.")
	return {"ok": true, "uid": uid}

## Private blank only. Fresh part ids exist because a legacy wreck had none.
## Installed gear is disabled at 0 hp before the caller pays or publishes.
static func stage_legacy_recovery(state: Dictionary, world: Dictionary, spec: Dictionary, identity: String, loadout) -> Dictionary:
	if not state is Dictionary or not world is Dictionary or not spec is Dictionary:
		return _fail("Birth inputs are missing.")
	if not Core._identity(identity) or _spec_id(spec).is_empty():
		return _fail("Birth identity is malformed.")
	var contract: Dictionary = tow_contract(spec, loadout)
	if not bool(contract.get("ok", false)):
		return contract
	if not loadout is Dictionary:
		return _fail("Preserved loadout is unreadable.")
	var fitted: Dictionary = Refits.normalize(spec, {} if loadout.is_empty() else loadout)
	if not bool(fitted.get("ok", false)) or not fitted.get("loadout") is Dictionary or fitted.loadout.is_empty():
		return _fail("Preserved loadout is unreadable.")
	if _uid_taken(state, identity) or _birth_owner(state, identity, "", "") != null:
		return _fail("Two owners share one birth namespace.")
	var scan: Dictionary = Recovery.registry(state, "", null)
	if not bool(scan.get("ok", false)):
		return _fail(str(scan.get("message", scan.get("error", "Equipment birth was refused."))))
	var boat: Dictionary = _blank(spec, identity, float(contract.hullHp))
	boat.maxHp = float(contract.maxHp)
	boat.hp = float(contract.hullHp)
	if boat.has("refitLocker"):
		boat.erase("refitLocker")
	boat.loadout = fitted.loadout.duplicate(true)
	boat.engine = 1.0
	var seeded: Dictionary = Records.initialize(boat, {
		"base": spec.duplicate(true),
		"loadout": boat.loadout,
		"catalog": Refits.catalog(),
		"identity": identity,
		"knownUids": _known(scan)
	})
	if not bool(seeded.get("ok", false)):
		return _fail(str(seeded.get("error", seeded.get("message", "Equipment birth was refused."))))
	if str(boat.moduleCondition.birthNamespace) != identity:
		return _fail("A new hull keeps the birth it was given.")
	var own: Array = _uids_of(boat.moduleCondition)
	if own.is_empty():
		return _fail("Legacy wreck gear could not be prepared.")
	for uid in own:
		var item: Dictionary = boat.moduleCondition.items[str(uid)]
		if str(item.get("location", "")) == "locker":
			return _fail("A legacy wreck recovery does not mint locker parts.")
		var loss := float(item.get("hp", 0.0))
		if loss <= 0.000001:
			loss = 1.0
		var damaged: Dictionary = Core.apply_component_damage(boat.moduleCondition, {"itemUid": str(uid), "loss": loss, "cause": LEGACY_RECOVERY_CAUSE})
		if not bool(damaged.get("ok", false)):
			return _fail(str(damaged.get("error", damaged.get("message", "Legacy wreck gear could not be disabled."))))
		if float(item.hp) > 0.0001 or str(item.status) != "disabled" or str(item.cause) != LEGACY_RECOVERY_CAUSE:
			return _fail("Legacy wreck gear did not stay disabled.")
	var published: Dictionary = Records.publish(boat)
	if not bool(published.get("ok", false)):
		return _fail(str(published.get("error", published.get("message", "Equipment birth was refused."))))
	if float(boat.get("engine", 1.0)) > 0.0001:
		return _fail("Legacy wreck engine did not stay at zero.")
	if not boat.get("refitLocker") is Dictionary or not boat.refitLocker.is_empty():
		return _fail("A legacy wreck recovery does not mint locker parts.")
	boat.hp = float(contract.hullHp)
	boat.fuel = 0.0
	boat.ammo = 0.0
	boat.supplies = 0.0
	boat.crew = 0.0
	var agreed: Dictionary = _confirms(state, world, boat, "", "", false)
	if not bool(agreed.get("ok", false)):
		return agreed
	return {"ok": true, "fresh": false, "hullHp": float(contract.hullHp), "boat": boat, "message": "Legacy wreck recovery accepted."}

static func _blank(spec: Dictionary, uid: String, hull_hp: float) -> Dictionary:
	var boat: Dictionary = Damage.create_ship(spec, {"crew": 0.0, "fuel": 0.0, "ammo": 0.0, "supplies": 0.0, "hp": hull_hp})
	boat.uid = uid
	boat.fuel = 0.0
	boat.ammo = 0.0
	boat.supplies = 0.0
	return boat

static func _without_uid(rows: Array, skip_uid: String) -> Array:
	var kept: Array = []
	for boat in rows:
		if boat is Dictionary and str(boat.get("uid", "")) == skip_uid:
			continue
		kept.append(boat)
	return kept

static func _drop_source(copy: Dictionary, skip_uid: String, skip_wreck: String) -> void:
	if not skip_uid.is_empty():
		for key in ["fleet", "boardingPrizes"]:
			if copy.get(key) is Array:
				copy[key] = _without_uid(copy[key], skip_uid)
		if copy.get("fleetOwners") is Array:
			for owner in copy.fleetOwners:
				if owner is Dictionary and owner.get("boats") is Array:
					owner.boats = _without_uid(owner.boats, skip_uid)
	if not skip_wreck.is_empty() and copy.get("wrecks") is Array:
		var kept: Array = []
		for wreck in copy.wrecks:
			if wreck is Dictionary and str(wreck.get("id", "")) == skip_wreck:
				continue
			kept.append(wreck)
		copy.wrecks = kept

static func _confirms(state: Dictionary, world: Dictionary, boat: Dictionary, skip_uid: String, skip_wreck: String, allow_taken_uid: bool) -> Dictionary:
	var copy: Dictionary = state.duplicate(true)
	_drop_source(copy, skip_uid, skip_wreck)
	var placed: Dictionary = boat.duplicate(true)
	if _uid_taken(copy, str(placed.uid)):
		if not allow_taken_uid:
			return _fail("Two hulls share one uid.")
		var serial := 1
		var token := "rehearse-%d" % serial
		while _uid_taken(copy, token):
			serial += 1
			token = "rehearse-%d" % serial
		placed.uid = token
	if not copy.get("fleet") is Array:
		copy.fleet = []
	copy.fleet.append(placed)
	var checked: Dictionary = Preflight.check_state(copy, world)
	if not checked.ok:
		return _fail(str(checked.get("message", "Equipment birth was refused.")))
	return {"ok": true}

static func _source_of(state: Dictionary, preserved: Dictionary, spec: Dictionary) -> Dictionary:
	var wreck_id := str(preserved.get("sourceWreckId", ""))
	var source_uid := str(preserved.get("sourceUid", ""))
	if not wreck_id.is_empty() and not source_uid.is_empty():
		return _fail("Preserved equipment names two custodians.")
	if wreck_id.is_empty() and source_uid.is_empty():
		return {"ok": true, "skip_uid": "", "skip_wreck": "", "matched": false}
	if not wreck_id.is_empty():
		var wreck: Dictionary = {}
		var wrecks := 0
		var wreck_rows: Array = state.get("wrecks", []) if state.get("wrecks", []) is Array else []
		for row in wreck_rows:
			if row is Dictionary and str(row.get("id", "")) == wreck_id:
				wrecks += 1
				wreck = row
		if wrecks != 1 or not Recovery.is_active(wreck) or wreck.sourceModuleCondition != preserved.get("moduleCondition"):
			return _fail("The named wreck is not the custodian of these parts.")
		if str(wreck.get("hull", "")) != str(spec.get("id", "")):
			return _fail("Preserved hull design differs from its wreck.")
		var actual_fit: Dictionary = Refits.normalize(spec, wreck.get("sourceLoadout", {}))
		var requested_fit: Dictionary = Refits.normalize(spec, preserved.loadout)
		if not actual_fit.ok or not requested_fit.ok or actual_fit.loadout != requested_fit.loadout:
			return _fail("Preserved loadout differs from its wreck.")
		return {"ok": true, "skip_uid": "", "skip_wreck": wreck_id, "matched": true}
	var found: Array = []
	for boat in _boats(state):
		if str(boat.get("uid", "")) == source_uid:
			found.append(boat)
	if found.size() != 1 or not found[0].get("moduleCondition") is Dictionary or found[0].moduleCondition != preserved.get("moduleCondition"):
		return _fail("The named hull is not the custodian of these parts.")
	if str(found[0].get("type", "")) != str(spec.get("id", "")):
		return _fail("Preserved hull design differs from its custodian.")
	var actual: Dictionary = Refits.normalize(spec, found[0].get("loadout", Refits.defaults(spec)))
	var requested: Dictionary = Refits.normalize(spec, preserved.loadout)
	if not actual.ok or not requested.ok or actual.loadout != requested.loadout:
		return _fail("Preserved loadout differs from its custodian.")
	if float(preserved.hullHp) > float(found[0].get("hp", 0.0)):
		return _fail("Preserved hull hp cannot exceed its custodian.")
	return {"ok": true, "skip_uid": source_uid, "skip_wreck": "", "matched": true}

static func stage_birth(state: Dictionary, world: Dictionary, spec: Dictionary, identity: String, preserved: Dictionary = {}) -> Dictionary:
	if not state is Dictionary or not world is Dictionary or not spec is Dictionary:
		return _fail("Birth inputs are missing.")
	if not Core._identity(identity) or _spec_id(spec).is_empty():
		return _fail("Birth identity is malformed.")
	var keeping := preserved.has("moduleCondition")
	if keeping:
		if str(preserved.get("sourceUid", "")).is_empty() and str(preserved.get("sourceWreckId", "")).is_empty():
			return _fail("A preserved birth needs an explicit custodian.")
		return _stage_preserved(state, world, spec, identity, preserved, false)
	if _uid_taken(state, identity) or _birth_owner(state, identity, "", "") != null:
		return _fail("Two owners share one birth namespace.")
	var scan: Dictionary = Recovery.registry(state, "", null)
	if not scan.ok:
		return _fail(str(scan.get("message", scan.get("error", "Equipment birth was refused."))))
	var boat: Dictionary = _blank(spec, identity, maxf(1.0, float(spec.get("hp", 1.0))))
	var loadout: Dictionary = _loadout_for(spec, null)
	if loadout.is_empty():
		return _fail("Hull loadout could not be prepared.")
	boat.loadout = loadout
	var seeded: Dictionary = Records.initialize(boat, {
		"base": spec.duplicate(true),
		"loadout": loadout,
		"catalog": Refits.catalog(),
		"identity": identity,
		"knownUids": _known(scan)
	})
	if not seeded.ok:
		return _fail(str(seeded.get("error", seeded.get("message", "Equipment birth was refused."))))
	if str(boat.moduleCondition.birthNamespace) != identity:
		return _fail("A new hull keeps the birth it was given.")
	var agreed: Dictionary = _confirms(state, world, boat, "", "", false)
	if not agreed.ok:
		return agreed
	boat.fuel = 0.0
	boat.ammo = 0.0
	boat.supplies = 0.0
	return {"ok": true, "fresh": true, "boat": boat, "message": "Birth accepted."}

static func _stage_preserved(state: Dictionary, world: Dictionary, spec: Dictionary, identity: String, preserved: Dictionary, allow_taken_uid: bool) -> Dictionary:
	var condition = preserved.get("moduleCondition")
	if not condition is Dictionary or not Core._records(condition).ok:
		return _fail("Preserved equipment is unreadable.")
	if not preserved.get("loadout") is Dictionary:
		return _fail("Preserved loadout is missing.")
	if not (preserved.get("hullHp") is float or preserved.get("hullHp") is int) or not is_finite(float(preserved.hullHp)) or float(preserved.hullHp) <= 0.0:
		return _fail("Preserved hull hp is missing.")
	var hull_hp := float(preserved.hullHp)
	var own: Array = _uids_of(condition)
	var source: Dictionary = _source_of(state, preserved, spec)
	if not source.ok:
		return source
	if not str(source.get("skip_wreck", "")).is_empty():
		var contract := tow_contract(spec, preserved.get("loadout", {}))
		if not contract.ok or not is_equal_approx(hull_hp, float(contract.hullHp)):
			return _fail("Preserved hull hp is not the tow recovery contract.")
		hull_hp = float(contract.hullHp)
	var birth := str(condition.birthNamespace)
	var holder = _birth_owner(state, birth, str(source.skip_uid), str(source.skip_wreck))
	if holder != null:
		return _fail("Two owners share one birth namespace.")
	if not allow_taken_uid and _uid_taken(state, identity):
		return _fail("Two hulls share one uid.")
	var scan: Dictionary = Recovery.registry(state, str(source.skip_wreck), null if str(source.skip_uid).is_empty() else str(source.skip_uid))
	if not scan.ok:
		return _fail(str(scan.get("message", scan.get("error", "Equipment birth was refused."))))
	if _overlaps(_known(scan), own):
		return _fail("Two hulls share one physical part.")
	var boat: Dictionary = _blank(spec, identity, hull_hp)
	var loadout: Dictionary = _loadout_for(spec, preserved.loadout)
	if loadout.is_empty():
		return _fail("Preserved loadout is unreadable.")
	boat.loadout = loadout
	var attached: Dictionary = Recovery.attach(boat, condition.duplicate(true))
	if not attached.ok:
		return _fail(str(attached.get("message", attached.get("error", "Preserved equipment was refused."))))
	if str(boat.moduleCondition.birthNamespace) != birth or int(boat.moduleCondition.nextItemSeq) != int(condition.nextItemSeq) or not _same_uids(_uids_of(boat.moduleCondition), own):
		return _fail("Preserved equipment would have changed identity.")
	var agreed: Dictionary = _confirms(state, world, boat, str(source.skip_uid), str(source.skip_wreck), allow_taken_uid)
	if not agreed.ok:
		return agreed
	boat.hp = hull_hp
	boat.fuel = 0.0
	boat.ammo = 0.0
	boat.supplies = 0.0
	return {"ok": true, "fresh": false, "hullHp": hull_hp, "boat": boat, "message": "Preserved birth accepted."}

static func materialize(spec: Dictionary, crew: int, staged: Dictionary, fresh: bool) -> Dictionary:
	var source: Dictionary = staged.get("boat", {}) if staged.get("boat") is Dictionary else {}
	var hull_hp: float = float(staged.get("hullHp", source.get("hp", spec.get("hp", 1.0))))
	var boat: Dictionary = Damage.create_ship(spec, {"crew": float(crew), "fuel": 0.0, "ammo": 0.0, "supplies": 0.0, "hp": hull_hp if not fresh else maxf(1.0, float(spec.get("hp", 1.0)))})
	boat.uid = str(source.get("uid", ""))
	if source.get("loadout") is Dictionary:
		boat.loadout = source.loadout.duplicate(true)
	if source.get("moduleCondition") is Dictionary:
		boat.moduleCondition = source.moduleCondition.duplicate(true)
	if source.has("engine"):
		boat.engine = source.engine
	if source.get("refitLocker") is Dictionary:
		boat.refitLocker = source.refitLocker.duplicate(true)
	boat.fuel = 0.0
	boat.ammo = 0.0
	boat.supplies = 0.0
	boat.crew = float(crew)
	if not fresh:
		boat.hp = hull_hp
	return boat

static func retain_wrecks(raw_rows: Array, state: Dictionary) -> void:
	var by_id: Dictionary = {}
	for raw in raw_rows:
		if raw is Dictionary and not str(raw.get("id", "")).is_empty():
			by_id[str(raw.id)] = raw
	var wrecks = state.get("wrecks", [])
	if wrecks is Array:
		for wreck in wrecks:
			if wreck is Dictionary and by_id.has(str(wreck.get("id", ""))):
				Recovery.retain(by_id[str(wreck.id)], wreck)

static func rehearse_captures(state: Dictionary, world: Dictionary, boats: Array) -> Dictionary:
	var rows: Array = []
	var scratch: Dictionary = state.duplicate(true)
	var captured_births: Dictionary = {}
	for boat in boats:
		if not boat is Dictionary:
			return _fail("Captured hull is unreadable.")
		var identity := str(boat.get("uid", ""))
		if not Core._identity(identity):
			return _fail("Captured hull uid is malformed.")
		var spec: Dictionary = {}
		var catalogue = world.get("HULLS", [])
		if catalogue is Array:
			for hull in catalogue:
				if hull is Dictionary and str(hull.get("id", "")) == str(boat.get("type", "")):
					spec = hull
					break
		if spec.is_empty():
			return _fail("Captured hull design is unknown.")
		var staged: Dictionary
		var source_uid := ""
		if boat.get("moduleCondition") is Dictionary:
			var owner_uid := ""
			var owners := 0
			for held in _boats(scratch):
				if held.get("moduleCondition") is Dictionary and _same_uids(_uids_of(held.moduleCondition), _uids_of(boat.moduleCondition)):
					owners += 1
					owner_uid = str(held.get("uid", ""))
			if owners > 1 or (owners == 1 and owner_uid != identity):
				return _fail("Captured parts already have a different custodian.")
			source_uid = owner_uid
			var preserved: Dictionary = {
				"moduleCondition": boat.moduleCondition,
				"loadout": boat.get("loadout", {}),
				"hullHp": float(boat.get("hp", 0.0)),
				"sourceUid": owner_uid
			}
			staged = _stage_preserved(scratch, world, spec, identity, preserved, true)
		else:
			if _birth_owner(scratch, identity, "", "") != null:
				return _fail("Two owners share one birth namespace.")
			var scan: Dictionary = Recovery.registry(scratch, "", null)
			if not scan.ok:
				return _fail(str(scan.get("message", scan.get("error", "Captured equipment was refused."))))
			var fresh: Dictionary = _blank(spec, identity, maxf(0.1, float(boat.get("hp", 1.0))))
			var loadout: Dictionary = _loadout_for(spec, boat.get("loadout"))
			if loadout.is_empty():
				return _fail("Captured loadout is unreadable.")
			fresh.loadout = loadout
			if boat.has("engine"):
				fresh.engine = boat.engine
			if boat.get("refitLocker") is Dictionary:
				fresh.refitLocker = boat.refitLocker.duplicate(true)
			var seeded: Dictionary = Records.initialize(fresh, {
				"base": spec.duplicate(true),
				"loadout": loadout,
				"catalog": Refits.catalog(),
				"identity": identity,
				"knownUids": _known(scan)
			})
			if not seeded.ok:
				return _fail(str(seeded.get("error", "Captured equipment was refused.")))
			staged = {"ok": true, "fresh": false, "hullHp": float(boat.get("hp", fresh.hp)), "boat": fresh}
			var agreed: Dictionary = _confirms(scratch, world, fresh, "", "", true)
			if not agreed.ok:
				return agreed
		if not staged.ok:
			return staged
		var birth := str(staged.boat.moduleCondition.birthNamespace)
		if captured_births.has(birth):
			return _fail("The same equipment birth was captured twice.")
		captured_births[birth] = true
		_drop_source(scratch, source_uid, "")
		rows.append({"boat": boat, "physical": boat.get("moduleCondition") is Dictionary, "staged": staged})
		var published: Dictionary = staged.boat.duplicate(true)
		if _uid_taken(scratch, str(published.uid)):
			var serial := 1
			var token := "rehearse-%d" % serial
			while _uid_taken(scratch, token):
				serial += 1
				token = "rehearse-%d" % serial
			published.uid = token
		if not scratch.get("fleet") is Array:
			scratch.fleet = []
		scratch.fleet.append(published)
	return {"ok": true, "rows": rows, "message": "Captures rehearsed."}

static func install_legacy(boat: Dictionary, staged: Dictionary) -> void:
	var source: Dictionary = staged.get("boat", {}) if staged.get("boat") is Dictionary else {}
	if source.get("loadout") is Dictionary:
		boat.loadout = source.loadout.duplicate(true)
	if source.get("moduleCondition") is Dictionary:
		boat.moduleCondition = source.moduleCondition.duplicate(true)
	if source.has("engine"):
		boat.engine = source.engine
	if source.get("refitLocker") is Dictionary:
		boat.refitLocker = source.refitLocker.duplicate(true)
