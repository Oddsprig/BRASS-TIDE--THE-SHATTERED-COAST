extends RefCounted
## Custody for one wreck's physical equipment. Preloads Core, Records, and Refit.
## Does not preload Campaign, Battle, Harbor, or Money. Does not reseed a hull,
## write spec weapon mounts, or treat a caller flag as payment.
## Campaign.add_boat(spec, crew) has no preserved-owner argument. Salvage rehearses
## on a detached boat, copies that prepared record onto the boat add_boat returns,
## then fit_boat rebuilds the hull. This file does not call a future constructor.
## equipmentRetiredTo on a sunk hull is the wreck id that took its parts. It is not
## an owner. Save must keep that field with the hull. A later migration must not
## initialize a hull that still has it. This file does not edit Save.

const Core = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Refits = preload("res://scripts/refit.gd")

const STORE_GOODS = ["fuel", "ammo", "supplies", "food"]
const UID_BATCH := 512
const UNREADABLE := "This wreck's equipment record cannot be read, so nothing was taken."

static func _fail(result: Dictionary) -> Dictionary:
	var message: String = str(result.get("message", result.get("error", UNREADABLE)))
	return {"ok": false, "accepted": false, "legacy": false, "error": message, "message": message}

static func _raw_copy(value):
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value

static func _refused(ship: Dictionary, message: String) -> Dictionary:
	var raw = ship.get("moduleCondition", null)
	return {"ok": true, "accepted": false, "legacy": false, "raw": _raw_copy(raw), "error": message, "message": message}

## Read-only toward the caller's hull. A detached scratch absorbs a lower engine
## scalar before the snapshot is copied, so tow cannot heal pending legacy damage.
## An upward scalar is left on the part. Legacy when the hull has no moduleCondition.
## A present record that fails catalog, base, or loadout agreement is returned raw.
static func prepare(ship: Dictionary, base: Dictionary, known_uids: Array) -> Dictionary:
	if not ship is Dictionary:
		return _fail({"error": "The hull record is missing."})
	if not ship.has("moduleCondition"):
		return {"ok": true, "accepted": false, "legacy": true}
	if Core._foreign(ship) or not base is Dictionary or base.is_empty():
		return _refused(ship, UNREADABLE)
	if not known_uids is Array:
		return _refused(ship, UNREADABLE)
	var original = ship.moduleCondition
	if not original is Dictionary:
		return _refused(ship, UNREADABLE)
	var structural: Dictionary = Core._records(original)
	if not structural.ok:
		return _refused(ship, str(structural.error))
	var scratch: Dictionary = ship.duplicate(true)
	if bool(structural.get("hasEngine", false)):
		if not Core._unit(scratch.get("engine", null)):
			return _refused(ship, "The legacy engine scalar is missing.")
		var absorbed: Dictionary = Records.absorb_legacy_damage(scratch)
		if not absorbed.ok:
			return _refused(ship, str(absorbed.get("error", UNREADABLE)))
	var raw = scratch.moduleCondition
	var hull_info: Dictionary = Records._validate_base(base, scratch)
	if not hull_info.ok:
		return _refused(ship, str(hull_info.error))
	var catalog: Dictionary = Refits.catalog()
	var cat_check: Dictionary = Records._validate_catalog(catalog)
	if not cat_check.ok:
		return _refused(ship, str(cat_check.error))
	var fitted: Dictionary = Records._validate_condition_catalog(raw, catalog, cat_check.familyByType, hull_info)
	if not fitted.ok:
		return _refused(ship, str(fitted.error))
	var loadout = scratch.get("loadout", null)
	var ctx: Dictionary = {"mountCount": int(hull_info.mountCount), "hullType": str(hull_info.hullType), "knownUids": known_uids, "loadout": loadout}
	var agreed: Dictionary = Core.validate(raw, ctx)
	if not agreed.ok:
		return _refused(ship, str(agreed.error))
	return {
		"ok": true,
		"accepted": true,
		"legacy": false,
		"condition": raw.duplicate(true),
		"sourceUid": str(ship.get("uid", "")),
		"birth": str(raw.birthNamespace),
		"nextItemSeq": int(raw.nextItemSeq),
		"itemUids": Core._uid_list(raw)
	}

static func _optional_rows(state: Dictionary, key: String) -> Dictionary:
	if not state.has(key):
		return {"ok": true, "rows": []}
	if not state.get(key) is Array:
		return _fail({"error": "A campaign owner list is unreadable."})
	return {"ok": true, "rows": state[key]}

static func _same_boat(boats: Array, skip) -> bool:
	if not skip is Dictionary:
		return false
	for boat in boats:
		if is_same(boat, skip):
			return true
	return false

## Every live custodian: player fleet, boarding prizes, fleetOwners[].boats, and
## active wrecks. The same dictionary is one owner. Distinct hulls that share a
## uid are an error. skip_owner is that exact hull, or a uid string only when one
## hull has it. Retired and transferred history is not active. A present corrupt
## record fails the scan. Core.collect_item_uids stays at 512 per call; a larger
## roster is compared in batches without lowering the campaign caps.
static func _scan(state: Dictionary, skip_wreck_id: String, skip_owner) -> Dictionary:
	if not state is Dictionary:
		return _fail({"error": "Campaign state is missing."})
	var boats: Array = []
	for key in ["fleet", "boardingPrizes"]:
		var listed: Dictionary = _optional_rows(state, key)
		if not listed.ok:
			return listed
		for boat in listed.rows:
			if not boat is Dictionary:
				return _fail({"error": "A fleet entry is not a hull record."})
			if not _same_boat(boats, boat):
				boats.append(boat)
	if state.has("fleetOwners"):
		if not state.fleetOwners is Array:
			return _fail({"error": "Fleet owners are unreadable."})
		for owner in state.fleetOwners:
			if not owner is Dictionary or not owner.get("boats") is Array:
				return _fail({"error": "A fleet owner record is unreadable."})
			for boat in owner.boats:
				if not boat is Dictionary:
					return _fail({"error": "A fleet entry is not a hull record."})
				if not _same_boat(boats, boat):
					boats.append(boat)
	var uid_seen: Dictionary = {}
	for boat in boats:
		var uid := str(boat.get("uid", ""))
		if uid.is_empty():
			continue
		if uid_seen.has(uid) and not is_same(uid_seen[uid], boat):
			return _fail({"error": "Two hulls share one uid."})
		uid_seen[uid] = boat
	var skip_boat = null
	if skip_owner is Dictionary:
		skip_boat = skip_owner
	elif skip_owner is String and not str(skip_owner).is_empty():
		var matches: Array = []
		for boat in boats:
			if str(boat.get("uid", "")) == str(skip_owner):
				matches.append(boat)
		if matches.size() > 1:
			return _fail({"error": "Two hulls share one uid."})
		if matches.size() == 1:
			skip_boat = matches[0]
	elif skip_owner != null and not (skip_owner is String):
		return _fail({"error": "The hull to skip is not a real record."})
	var conditions: Array = []
	var holders: Array = []
	for boat in boats:
		if skip_boat != null and is_same(boat, skip_boat):
			continue
		if Core._foreign(boat):
			return _fail({"error": UNREADABLE})
		if boat.has("equipmentRetiredTo"):
			if boat.has("moduleCondition"):
				return _fail({"error": "A retired hull still carries equipment."})
			continue
		if not boat.has("moduleCondition"):
			continue
		if not boat.moduleCondition is Dictionary or not Core._records(boat.moduleCondition).ok:
			return _fail({"error": UNREADABLE})
		conditions.append(boat.moduleCondition)
		holders.append({"kind": "boat", "id": str(boat.get("uid", ""))})
	var wrecks: Dictionary = _optional_rows(state, "wrecks")
	if not wrecks.ok:
		return wrecks
	for wreck in wrecks.rows:
		if not wreck is Dictionary:
			return _fail({"error": "A wreck record is unreadable."})
		if not skip_wreck_id.is_empty() and str(wreck.get("id", "")) == skip_wreck_id:
			continue
		if skip_owner is Dictionary and is_same(wreck, skip_owner):
			continue
		var custody := str(wreck.get("equipmentCustody", ""))
		if custody == "refused":
			continue
		if custody == "transferred" or custody == "retired":
			if wreck.has("sourceModuleCondition"):
				return _fail({"error": UNREADABLE})
			continue
		var problem := refusal(wreck)
		if not problem.is_empty():
			return _fail({"error": problem})
		if is_active(wreck):
			conditions.append(wreck.sourceModuleCondition)
			holders.append({"kind": "wreck", "id": str(wreck.get("id", ""))})
	return {"ok": true, "conditions": conditions, "holders": holders}

static func _collect_uids(conditions: Array) -> Dictionary:
	var ordered: Array = []
	var seen: Dictionary = {}
	var index := 0
	while index < conditions.size():
		var batch: Array = []
		var end: int = mini(index + UID_BATCH, conditions.size())
		while index < end:
			batch.append(conditions[index])
			index += 1
		var part: Dictionary = Core.collect_item_uids(batch)
		if not part.ok:
			return _fail(part)
		for uid in part.get("uids", []):
			var key := str(uid)
			if seen.has(key):
				return _fail({"error": "Two hulls share one physical part."})
			seen[key] = true
			ordered.append(key)
	return {"ok": true, "uids": ordered}

static func registry(state: Dictionary, skip_wreck_id: String, skip_owner = null) -> Dictionary:
	var scan: Dictionary = _scan(state, skip_wreck_id, skip_owner)
	if not scan.ok:
		return scan
	return _collect_uids(scan.conditions)

## Consistent custody only. transferred or retired with a payload still present,
## wreck custody without a valid payload, and an invented custody all refuse.
## The raw value is left where it was. Store-only recovery stays wreck custody.
## A retired hull with hullStripped can still give up remaining commodity lots.
static func refusal(wreck: Dictionary) -> String:
	if not wreck is Dictionary:
		return UNREADABLE
	var custody := str(wreck.get("equipmentCustody", ""))
	if not custody in ["", "wreck", "transferred", "retired", "refused"]:
		return UNREADABLE
	var status := str(wreck.get("status", ""))
	var has_payload := wreck.has("sourceModuleCondition")
	if custody == "refused":
		return UNREADABLE
	if custody == "transferred":
		if has_payload or status != "towed":
			return UNREADABLE
		return ""
	if custody == "retired":
		if has_payload:
			return UNREADABLE
		if status == "stripped" or bool(wreck.get("hullStripped", false)):
			return ""
		return UNREADABLE
	if custody == "wreck":
		if status != "" and status != "unclaimed":
			return UNREADABLE
		if not has_payload:
			return UNREADABLE
	elif has_payload and status != "" and status != "unclaimed":
		return UNREADABLE
	elif not has_payload:
		return ""
	var raw = wreck.sourceModuleCondition
	if not raw is Dictionary or not Core._records(raw).ok:
		return UNREADABLE
	return ""

static func is_active(wreck: Dictionary) -> bool:
	if not wreck is Dictionary or not wreck.has("sourceModuleCondition"):
		return false
	var custody := str(wreck.get("equipmentCustody", ""))
	if custody != "" and custody != "wreck":
		return false
	if str(wreck.get("status", "unclaimed")) not in ["", "unclaimed"]:
		return false
	var raw = wreck.sourceModuleCondition
	return raw is Dictionary and Core._records(raw).ok

static func is_store_good(good: String) -> bool:
	return good in STORE_GOODS

## Copies the saved snapshot onto a sanitized wreck. Does not drop a corrupt value
## and does not invent a record for an old wreck that never stored one.
static func retain(raw: Dictionary, wreck: Dictionary) -> void:
	if not raw is Dictionary or not wreck is Dictionary:
		return
	if raw.has("sourceModuleCondition"):
		wreck.sourceModuleCondition = _raw_copy(raw.sourceModuleCondition)
	if raw.has("equipmentCustody"):
		wreck.equipmentCustody = raw.equipmentCustody
	if raw.has("retiredSourceUid"):
		wreck.retiredSourceUid = raw.retiredSourceUid
	if raw.has("transferredItemUids"):
		wreck.transferredItemUids = _raw_copy(raw.transferredItemUids)

## Detached boat. Proves the snapshot still matches the hull, catalog, and loadout,
## then publishes onto that copy. The live boat is untouched. The returned boat is
## the prepared boundary Campaign.add_boat cannot accept directly.
static func rehearse(base: Dictionary, loadout, condition: Dictionary, hull_uid: String, known_uids: Array) -> Dictionary:
	if not condition is Dictionary or not base is Dictionary or not known_uids is Array:
		return _fail({"error": UNREADABLE})
	var hull_info: Dictionary = Records._validate_base(base, {"type": str(base.get("id", "")), "spec": base, "baseSpec": base})
	if not hull_info.ok:
		return _fail(hull_info)
	var catalog: Dictionary = Refits.catalog()
	var cat_check: Dictionary = Records._validate_catalog(catalog)
	if not cat_check.ok:
		return _fail(cat_check)
	var fitted: Dictionary = Records._validate_condition_catalog(condition, catalog, cat_check.familyByType, hull_info)
	if not fitted.ok:
		return _fail(fitted)
	var ctx: Dictionary = {"mountCount": int(hull_info.mountCount), "hullType": str(hull_info.hullType), "knownUids": known_uids, "loadout": loadout}
	var agreed: Dictionary = Core.validate(condition, ctx)
	if not agreed.ok:
		return _fail(agreed)
	var draft: Dictionary = {
		"uid": hull_uid,
		"type": str(base.get("id", "")),
		"baseSpec": base.duplicate(true),
		"spec": base.duplicate(true),
		"loadout": loadout.duplicate(true) if loadout is Dictionary else {},
		"engine": 1.0,
		"hp": 1.0,
		"maxHp": 1.0
	}
	var attached: Dictionary = attach(draft, condition)
	if not attached.ok:
		return attached
	return {
		"ok": true,
		"boat": draft,
		"condition": draft.moduleCondition,
		"engine": draft.engine,
		"refitLocker": draft.refitLocker.duplicate(true) if draft.get("refitLocker", {}) is Dictionary else {},
		"itemUids": attached.itemUids,
		"birth": attached.birth,
		"nextItemSeq": attached.nextItemSeq
	}

## Writes the copy onto a detached boat and publishes that boat's own engine scalar
## from the installed part. Birth id and item ids stay as recorded. The source
## hull's old scalar is not written onto this boat.
static func attach(boat: Dictionary, condition: Dictionary) -> Dictionary:
	var structural: Dictionary = Core._records(condition)
	if not structural.ok:
		return _fail(structural)
	var birth: String = str(condition.birthNamespace)
	var serial: int = int(condition.nextItemSeq)
	var before: Dictionary = condition.duplicate(true)
	boat.moduleCondition = condition.duplicate(true)
	var published: Dictionary = Records.publish(boat)
	if not published.ok:
		boat.erase("moduleCondition")
		return _fail(published)
	var noted: Dictionary = Core.acknowledge_hull_uid(boat.moduleCondition, str(boat.get("uid", "")))
	if not noted.ok or str(boat.moduleCondition.birthNamespace) != birth or int(boat.moduleCondition.nextItemSeq) != serial:
		boat.erase("moduleCondition")
		return _fail({"error": "Recovery would have changed the equipment identity."})
	for part_id in before.items.keys():
		if not boat.moduleCondition.items.has(part_id):
			boat.erase("moduleCondition")
			return _fail({"error": "Recovery would have changed a part."})
		var kept: Dictionary = boat.moduleCondition.items[part_id]
		var original: Dictionary = before.items[part_id]
		if str(kept.itemUid) != str(original.itemUid) or str(kept.location) != str(original.location) or str(kept.status) != str(original.status) or str(kept.cause) != str(original.cause) or not is_equal_approx(float(kept.hp), float(original.hp)):
			boat.erase("moduleCondition")
			return _fail({"error": "Recovery would have changed a part."})
	return {"ok": true, "engine": boat.engine, "itemUids": Core._uid_list(boat.moduleCondition), "birth": birth, "nextItemSeq": serial}

## Drops the active snapshot. The uid list remains so a later registry can see
## that this wreck is not a second owner. Store-only stripping does not call this.
static func release(wreck: Dictionary, custody: String) -> void:
	var uids: Array = []
	if is_active(wreck):
		uids = Core._uid_list(wreck.sourceModuleCondition)
	elif wreck.get("transferredItemUids", []) is Array:
		uids = wreck.transferredItemUids.duplicate(true)
	wreck.transferredItemUids = uids
	if wreck.has("sourceModuleCondition"):
		wreck.erase("sourceModuleCondition")
	wreck.equipmentCustody = custody

static func active_holders(state: Dictionary) -> Dictionary:
	var scan: Dictionary = _scan(state, "", null)
	if not scan.ok:
		return scan
	return {"ok": true, "holders": scan.holders}
