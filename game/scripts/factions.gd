extends RefCounted
## Player reputation, faction-to-faction relations, and contact trust.
## Serializable campaign data only. No coins, port stocks, combat, or NPC war.
## Root integrates docking, contracts, inspections, and UI.

const REP_MIN := -100
const REP_MAX := 100
const DELTA_CAP := 25
const SPILLOVER_DIVISOR := 3
const SPILL_CAP := 8
const LEGAL_SHIFT := -12
const ENEMY_AT := -20
const CLAIM_MAX := 100
const LOG_LIMIT := 40
const EVENT_LIMIT := 80
const HOSTILE_ENTER := -50
const HOSTILE_EXIT := -35
const WARY_ENTER := -20
const WARY_EXIT := -5
const FRIENDLY_ENTER := 20
const FRIENDLY_EXIT := 5
const TRUSTED_ENTER := 50
const TRUSTED_EXIT := 35
const WITNESS_HOSTILE := -50
const WITNESS_INSPECT := -20
const INITIAL_RAIDER := -70
const CANON := ["compact", "forge", "reed", "raiders"]
const CANON_NAMES := {
	"compact": "Mercantile Compact",
	"forge": "Cinder Forge Directorate",
	"reed": "Reedwater Commune",
	"raiders": "Shatter Reef Raiders",
}
# Explicit help-cost table. Not derived from pair scores, so an enemy of an enemy does not become a friend.
const RIVALS := {
	"compact": ["raiders"],
	"forge": ["raiders"],
	"reed": ["raiders"],
	"raiders": ["compact"],
}
const PAIR_BASE := {
	"compact|forge": 15,
	"compact|reed": 5,
	"compact|raiders": -40,
	"forge|reed": -10,
	"forge|raiders": -30,
	"raiders|reed": -25,
}
const CONTACT_ROSTER := [
	{"id": "holt", "name": "Maren Holt", "portId": "brass_haven", "factionId": "compact", "role": "convoy clerk"},
	{"id": "pek", "name": "Sura Pek", "portId": "cinder_quay", "factionId": "forge", "role": "foundry factor"},
	{"id": "liss", "name": "Ivo Liss", "portId": "reed_floats", "factionId": "reed", "role": "estuary speaker"},
	{"id": "vetch", "name": "Captain Vetch", "portId": "shatter_spire", "factionId": "raiders", "role": "toll captain"},
]
const MILITARY_GOODS := ["guns", "engines"]
const BANDS := ["hostile", "wary", "neutral", "friendly", "trusted"]

static func ensure(state, world) -> Dictionary:
	if not state is Dictionary:
		return {"ok": false, "message": "state must be a dictionary"}
	if not state.get("relationships") is Dictionary:
		state.relationships = {}
	var book: Dictionary = state.relationships
	_repair_book(book)
	var defs := _faction_defs(world)
	for id in defs:
		if not book.factions.has(id):
			book.factions[id] = _new_standing(id, str(defs[id]))
		else:
			_repair_standing(book.factions[id], id, str(defs[id]))
	for id in CANON:
		if not book.factions.has(id):
			book.factions[id] = _new_standing(id, str(CANON_NAMES[id]))
		elif str(book.factions[id].get("name", "")).is_empty():
			book.factions[id].name = str(CANON_NAMES[id])
	var ids: Array = book.factions.keys()
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var key := _pair_key(str(ids[i]), str(ids[j]))
			if not book.pairs.has(key):
				book.pairs[key] = int(PAIR_BASE.get(key, 0))
			else:
				book.pairs[key] = clampi(_as_int(book.pairs[key]), REP_MIN, REP_MAX)
	if int(book.get("politicalRevision",0))<2:
		if int(book.pairs.get("raiders|reed",0))==0 and not book.log.any(func(e):return str(e.get("kind",""))=="relation" and [e.get("factionId",""),e.get("otherId","")].has("raiders")):
			book.pairs["raiders|reed"]=-25
		book.politicalRevision=2
	for row in CONTACT_ROSTER:
		var cid := str(row.id)
		if not book.contacts.has(cid):
			book.contacts[cid] = _new_contact(row)
		else:
			_repair_contact(book.contacts[cid], row)
	if world is Dictionary and world.get("PORTS") is Array:
		var index := {}
		for port in world.PORTS:
			if not port is Dictionary or not port.get("id") is String or str(port.id).is_empty():
				continue
			var port_name := str(port.id)
			if port.get("name") is String and not str(port.name).is_empty():
				port_name = str(port.name)
			var faction_id := ""
			if port.get("faction") is String:
				faction_id = str(port.faction)
			index[str(port.id)] = {"id": str(port.id), "name": port_name, "factionId": faction_id}
		book.portIndex = index
	return book

static func standing(state, faction_id) -> Dictionary:
	var id := _text_id(faction_id)
	var missing := {"ok": false, "known": false, "factionId": id, "name": "", "score": 0, "public": 0, "band": "", "label": "", "witnessed": 0, "claims": {}, "claimTotal": 0, "hostile": false, "message": "Unknown faction.", "recovery": _recovery_text()}
	var book := _book(state)
	if book.is_empty() or not book.get("factions") is Dictionary or not book.factions.has(id):
		return missing
	return _standing_view(book, id)

static func adjust(state, faction_id, amount, reason, event_id: String = "") -> Dictionary:
	if not _finite_number(amount):
		return {"ok": false, "changed": false, "repeated": false, "message": "Amount must be a finite number."}
	var book := _book(state)
	if book.is_empty():
		return {"ok": false, "changed": false, "repeated": false, "message": "Call ensure(state, world) before using factions."}
	var parsed := _parse_reason(reason)
	var channel := str(parsed.channel)
	var id := _text_id(faction_id)
	var eid := _event_id(event_id)
	var today := _day(state)
	if channel == "contact":
		return _adjust_contact(state, book, id, str(parsed.contactId), _as_int(amount), str(parsed.text), eid)
	if not book.factions.has(id):
		return {"ok": false, "changed": false, "repeated": false, "factionId": id, "message": "Unknown faction."}
	if channel == "claim" or (channel == "restitution" and not str(parsed.portId).is_empty()):
		var port := _resolve_port(state, str(parsed.portId))
		if port.is_empty():
			return {"ok": false, "changed": false, "repeated": false, "factionId": id, "message": "Unknown port."}
		if str(port.factionId) != id:
			return {"ok": false, "changed": false, "repeated": false, "factionId": id, "message": "That port belongs to another faction."}
	if not eid.is_empty() and _seen(book, eid):
		var again := _standing_view(book, id)
		again.ok = true
		again.changed = false
		again.repeated = true
		again.message = "Event already applied."
		return again
	var applied := _cap_delta(_as_int(amount))
	var effects: Array = []
	if channel == "witness":
		effects.append(_apply_witness(book, id, applied, str(parsed.text), eid, today))
	elif channel == "claim":
		effects.append(_apply_claim(book, id, str(parsed.portId), _as_int(amount), str(parsed.text), eid, today))
	elif channel == "time":
		var blocked := _time_block(book, id)
		if not blocked.is_empty():
			blocked.ok = true
			blocked.changed = false
			blocked.repeated = false
			blocked.factionId = id
			blocked.standing = _standing_view(book, id)
			return blocked
		effects.append(_apply_time(book, id, applied, str(parsed.text), eid, today))
	elif channel == "restitution":
		effects.append(_apply_restitution(book, id, applied, str(parsed.portId), str(parsed.text), eid, today))
	else:
		effects.append(_apply_public(book, id, applied, str(parsed.text), eid, today))
		if applied > 0:
			var spill := -mini(SPILL_CAP, int(applied / float(SPILLOVER_DIVISOR)))
			if spill != 0 and RIVALS.has(id):
				for rival in RIVALS[id]:
					var rival_id := str(rival)
					if rival_id == id or not book.factions.has(rival_id):
						continue
					var spill_reason := "Helping %s cost standing with %s. %s" % [_faction_name(book, id), _faction_name(book, rival_id), str(parsed.text)]
					effects.append(_apply_public(book, rival_id, spill, spill_reason, eid, today))
	if not eid.is_empty():
		_remember(book, eid)
	var changed := false
	for effect in effects:
		if effect is Dictionary and effect.get("changed", false):
			changed = true
	var view := _standing_view(book, id)
	view.ok = true
	view.changed = changed
	view.repeated = false
	view.effects = effects
	view.channel = channel
	view.message = "Standing updated." if changed else "No standing change."
	return view

static func relation(state, a, b) -> int:
	var left := _text_id(a)
	var right := _text_id(b)
	if left.is_empty() or right.is_empty() or left == right:
		return 0
	var book := _book(state)
	if book.is_empty() or not book.get("pairs") is Dictionary:
		return 0
	var key := _pair_key(left, right)
	if not book.pairs.has(key):
		return int(PAIR_BASE.get(key, 0))
	return clampi(_as_int(book.pairs[key]), REP_MIN, REP_MAX)

static func set_relation(state, a, b, value, reason) -> Dictionary:
	if not _finite_number(value):
		return {"ok": false, "changed": false, "message": "Relation must be a finite number."}
	var left := _text_id(a)
	var right := _text_id(b)
	if left.is_empty() or right.is_empty() or left == right:
		return {"ok": false, "changed": false, "relation": 0, "message": "A faction has no separate relation with itself."}
	var book := _book(state)
	if book.is_empty():
		return {"ok": false, "changed": false, "message": "Call ensure(state, world) before using factions."}
	if not book.factions.has(left) or not book.factions.has(right):
		return {"ok": false, "changed": false, "message": "Unknown faction."}
	var key := _pair_key(left, right)
	var before := relation(state, left, right)
	var after := clampi(_as_int(value), REP_MIN, REP_MAX)
	if before == after:
		return {"ok": true, "changed": false, "key": key, "relation": after, "before": before, "after": after, "message": "Relation unchanged."}
	book.pairs[key] = after
	_log(book, {"kind": "pair", "factionId": left, "otherId": right, "amount": after - before, "before": before, "after": after, "reason": _short(reason), "eventId": "", "day": _day(state)})
	return {"ok": true, "changed": true, "key": key, "relation": after, "before": before, "after": after, "symmetric": true, "message": "Faction relation updated. Player reputation was not changed."}

static func access(state, port) -> Dictionary:
	var result := {
		"ok": false, "known": false, "portId": "", "portName": "", "factionId": "", "factionName": "",
		"band": "", "label": "", "score": 0, "public": 0, "witnessed": 0, "claim": 0,
		"legal": false, "entry": "refused", "inspection": false, "restrictedGoods": _military_goods(),
		"militaryFittings": false, "repairPriority": "none", "intelligence": false, "escorts": false,
		"contracts": false, "hostile": false, "reason": "Unknown port.", "recovery": _recovery_text(),
	}
	if not state is Dictionary:
		result.reason = "state must be a dictionary"
		return result
	var resolved := _resolve_port(state, port)
	if resolved.is_empty():
		return result
	result.portId = str(resolved.id)
	result.portName = str(resolved.name)
	result.factionId = str(resolved.factionId)
	var view := standing(state, result.factionId)
	if not view.known:
		result.reason = "Port faction is not in the relationship book."
		return result
	result.known = true
	result.ok = true
	result.factionName = str(view.name)
	result.band = str(view.band)
	result.label = str(view.label)
	result.score = int(view.score)
	result.public = int(view.public)
	result.witnessed = int(view.witnessed)
	result.hostile = bool(view.hostile)
	var claim := 0
	if view.claims is Dictionary and view.claims.has(result.portId):
		claim = _as_int(view.claims[result.portId])
	result.claim = claim
	var band := str(view.band)
	var hostile := bool(view.hostile)
	var trusted := band == "trusted"
	var friendly := band == "friendly" or trusted
	var military := friendly and claim <= 0 and not hostile
	result.militaryFittings = military
	result.restrictedGoods = [] if military else _military_goods()
	result.intelligence = trusted and claim <= 0 and not hostile and int(view.witnessed) > WITNESS_INSPECT
	result.escorts = friendly and claim <= 0 and not hostile
	result.contracts = not hostile
	if hostile:
		result.entry = "refused"
		result.legal = false
		result.inspection = false
		result.repairPriority = "none"
		result.contracts = false
		result.escorts = false
		result.intelligence = false
		result.militaryFittings = false
		result.restrictedGoods = _military_goods()
		if band != "hostile" and int(view.witnessed) <= WITNESS_HOSTILE:
			result.reason = "A witnessed offense against %s is still open. Public standing is %s, but %s refuses entry until restitution." % [result.factionName, band, result.portName]
		else:
			result.reason = "Hostile standing with %s refuses entry at %s." % [result.factionName, result.portName]
		return result
	var inspected := band == "wary" or int(view.witnessed) <= WITNESS_INSPECT or claim > 0
	result.entry = "inspected" if inspected else "open"
	result.legal = true
	result.inspection = inspected
	if claim > 0:
		result.repairPriority = "held"
	elif trusted:
		result.repairPriority = "priority"
	else:
		result.repairPriority = "ordinary"
	if claim > 0:
		result.reason = "%s still has an outstanding claim of %d at %s. Trade is legal and will be inspected; military fittings and priority repair wait on restitution." % [result.factionName, claim, result.portName]
	elif int(view.witnessed) <= WITNESS_INSPECT:
		result.reason = "%s witnessed an offense that is separate from public standing (%s). Entry at %s is inspected." % [result.factionName, band, result.portName]
	elif band == "wary":
		result.reason = "%s is wary. Legal trade at %s continues under inspection; military fittings stay closed." % [result.factionName, result.portName]
	elif band == "neutral":
		result.reason = "Neutral legal access at %s. Ordinary trade and contracts are open; guns and engines stay restricted." % result.portName
	elif band == "friendly":
		result.reason = "Friendly standing with %s opens military fittings and escorts at %s." % [result.factionName, result.portName]
	else:
		result.reason = "Trusted standing with %s gives priority repair and intelligence at %s." % [result.factionName, result.portName]
	return result

static func is_hostile(state, faction_id) -> bool:
	var view := standing(state, faction_id)
	return bool(view.get("hostile", false))

static func commission(state, faction_id) -> Dictionary:
	var id := _text_id(faction_id)
	var book := _book(state)
	if book.is_empty():
		return {"ok": false, "committed": false, "repeated": false, "stipend": 0, "factionId": id, "message": "Call ensure(state, world) before using factions."}
	if not book.factions.has(id):
		return {"ok": false, "committed": false, "repeated": false, "stipend": 0, "factionId": id, "message": "Unknown faction."}
	var view := _standing_view(book, id)
	var enemies := _enemy_ids(book, id)
	var eligible := (str(view.band) == "friendly" or str(view.band) == "trusted") and not bool(view.hostile)
	var warning := _commission_warning(book, id, enemies, eligible)
	if book.commission.get("committed", false) and str(book.commission.get("factionId", "")) == id:
		return {"ok": true, "committed": true, "repeated": true, "changed": false, "stipend": 0, "factionId": id, "enemies": enemies, "warning": warning, "contract": book.commission.get("contract", {}), "message": "Commission already recorded. No stipend was minted."}
	var pending := bool(book.commission.get("pending", false)) and str(book.commission.get("pendingFactionId", "")) == id
	if not pending:
		book.commission.pending = true
		book.commission.pendingFactionId = id
		return {"ok": true, "committed": false, "repeated": false, "changed": false, "explicit": false, "stipend": 0, "factionId": id, "enemies": enemies, "warning": warning, "legalShift": LEGAL_SHIFT, "message": warning}
	if not eligible:
		book.commission.pending = false
		book.commission.pendingFactionId = ""
		var refused := "They will not commission a captain they still treat as hostile or wary." if bool(view.hostile) or str(view.band) == "hostile" or str(view.band) == "wary" else "A commission requires friendly or trusted public standing."
		return {"ok": false, "committed": false, "repeated": false, "changed": false, "stipend": 0, "factionId": id, "enemies": enemies, "warning": warning, "message": refused + " No contract was committed and no coins were minted."}
	var legal: Array = []
	for enemy in enemies:
		var enemy_id := str(enemy)
		var event := "commission-legal:%s+%s" % [id, enemy_id]
		if _seen(book, event):
			continue
		var reason := "Letters of marque for %s recorded a legal-status change against %s." % [_faction_name(book, id), _faction_name(book, enemy_id)]
		legal.append(_apply_public(book, enemy_id, LEGAL_SHIFT, reason, event, _day(state)))
		_remember(book, event)
	book.commission.committed = true
	book.commission.factionId = id
	book.commission.pending = false
	book.commission.pendingFactionId = ""
	book.commission.stipend = 0
	var contract := {
		"id": "commission-%s" % id,
		"kind": "commission",
		"factionId": id,
		"title": "Letters of marque: %s" % _faction_name(book, id),
		"reward": 0,
		"escrow": 0,
		"stipend": 0,
		"committed": true,
		"enemies": enemies.duplicate(),
		"warning": warning,
	}
	book.commission.contract = contract
	_log(book, {"kind": "commission", "factionId": id, "otherId": "", "amount": 0, "before": 0, "after": 0, "reason": warning, "eventId": "commission:%s" % id, "day": _day(state)})
	return {"ok": true, "committed": true, "repeated": false, "changed": true, "explicit": true, "stipend": 0, "factionId": id, "enemies": enemies, "warning": warning, "legal": legal, "contract": contract, "message": "Commission recorded. No stipend was minted."}

static func _repair_book(book: Dictionary) -> void:
	if not book.get("factions") is Dictionary:
		book.factions = {}
	if not book.get("pairs") is Dictionary:
		book.pairs = {}
	if not book.get("contacts") is Dictionary:
		book.contacts = {}
	if not book.get("log") is Array:
		book.log = []
	if not book.get("seen") is Dictionary:
		book.seen = {}
	if not book.get("seenOrder") is Array:
		book.seenOrder = []
	if not book.get("portIndex") is Dictionary:
		book.portIndex = {}
	if not book.get("commission") is Dictionary:
		book.commission = _blank_commission()
	else:
		var deal: Dictionary = book.commission
		if not deal.get("factionId") is String:
			deal.factionId = ""
		if not deal.get("pendingFactionId") is String:
			deal.pendingFactionId = ""
		if not deal.get("committed") is bool:
			deal.committed = false
		if not deal.get("pending") is bool:
			deal.pending = false
		deal.stipend = 0
		if not deal.get("contract") is Dictionary:
			deal.contract = {}
		elif not deal.contract.is_empty():
			deal.contract.stipend = 0
			deal.contract.reward = 0
			deal.contract.escrow = 0
	book.seq = maxi(0, _as_int(book.get("seq", 0)))
	while book.log.size() > LOG_LIMIT:
		book.log.pop_front()
	while book.seenOrder.size() > EVENT_LIMIT:
		var old = book.seenOrder.pop_front()
		book.seen.erase(old)

static func _faction_defs(world) -> Dictionary:
	var defs := {}
	if world is Dictionary and world.get("FACTIONS") is Array:
		for row in world.FACTIONS:
			if not row is Dictionary or not row.get("id") is String or str(row.id).is_empty():
				continue
			var name := str(row.id)
			if row.get("name") is String and not str(row.name).is_empty():
				name = str(row.name)
			defs[str(row.id)] = name
	return defs

static func _new_standing(id: String, faction_name: String) -> Dictionary:
	var score := INITIAL_RAIDER if id == "raiders" else 0
	return {"factionId": id, "name": faction_name, "score": score, "band": _band_enter(score), "witnessed": 0, "claims": {}}

static func _repair_standing(row: Dictionary, id: String, faction_name: String) -> void:
	row.factionId = id
	if str(row.get("name", "")).is_empty():
		row.name = faction_name
	row.score = clampi(_as_int(row.get("score", 0 if id != "raiders" else INITIAL_RAIDER)), REP_MIN, REP_MAX)
	var band := str(row.get("band", ""))
	if not BANDS.has(band):
		band = _band_enter(int(row.score))
	row.band = band
	row.witnessed = clampi(_as_int(row.get("witnessed", 0)), REP_MIN, REP_MAX)
	if not row.get("claims") is Dictionary:
		row.claims = {}
	var claims: Dictionary = row.claims
	for port_id in claims.keys():
		var owed := clampi(_as_int(claims[port_id]), 0, CLAIM_MAX)
		if owed <= 0:
			claims.erase(port_id)
		else:
			claims[port_id] = owed

static func _new_contact(row: Dictionary) -> Dictionary:
	return {"id": str(row.id), "name": str(row.name), "portId": str(row.portId), "factionId": str(row.factionId), "role": str(row.role), "trust": 0, "band": "neutral"}

static func _repair_contact(row: Dictionary, source: Dictionary) -> void:
	row.id = str(source.id)
	if str(row.get("name", "")).is_empty():
		row.name = str(source.name)
	if str(row.get("portId", "")).is_empty():
		row.portId = str(source.portId)
	if str(row.get("factionId", "")).is_empty():
		row.factionId = str(source.factionId)
	if str(row.get("role", "")).is_empty():
		row.role = str(source.role)
	row.trust = clampi(_as_int(row.get("trust", 0)), REP_MIN, REP_MAX)
	var band := str(row.get("band", ""))
	if not BANDS.has(band):
		band = _band_enter(int(row.trust))
	row.band = band

static func _blank_commission() -> Dictionary:
	return {"factionId": "", "committed": false, "pending": false, "pendingFactionId": "", "stipend": 0, "contract": {}}

static func _standing_view(book: Dictionary, id: String) -> Dictionary:
	var row: Dictionary = book.factions[id]
	var score := clampi(_as_int(row.get("score", 0)), REP_MIN, REP_MAX)
	var witnessed := clampi(_as_int(row.get("witnessed", 0)), REP_MIN, REP_MAX)
	var band := str(row.get("band", "neutral"))
	if not BANDS.has(band):
		band = _band_enter(score)
	var claims: Dictionary = row.claims if row.get("claims") is Dictionary else {}
	var claim_copy := {}
	var claim_total := 0
	for port_id in claims.keys():
		var owed := clampi(_as_int(claims[port_id]), 0, CLAIM_MAX)
		if owed > 0:
			claim_copy[str(port_id)] = owed
			claim_total += owed
	var hostile := band == "hostile" or witnessed <= WITNESS_HOSTILE
	return {
		"ok": true, "known": true, "factionId": id, "name": str(row.get("name", id)),
		"score": score, "public": score, "band": band, "label": _label(band),
		"witnessed": witnessed, "claims": claim_copy, "claimTotal": claim_total,
		"hostile": hostile, "message": "", "recovery": _recovery_text(),
	}

static func _adjust_contact(state: Dictionary, book: Dictionary, requested_faction: String, contact_id: String, amount: int, reason: String, event_id: String) -> Dictionary:
	if contact_id.is_empty() or not book.contacts.has(contact_id):
		return {"ok": false, "changed": false, "repeated": false, "message": "Unknown contact."}
	var owner := str(book.contacts[contact_id].get("factionId", ""))
	if owner != requested_faction:
		return {"ok": false, "changed": false, "repeated": false, "message": "Contact belongs to another faction."}
	if not event_id.is_empty() and _seen(book, event_id):
		var row: Dictionary = book.contacts[contact_id]
		return {"ok": true, "changed": false, "repeated": true, "contactId": contact_id, "trust": _as_int(row.trust), "band": str(row.band), "message": "Event already applied."}
	var contact: Dictionary = book.contacts[contact_id]
	var before := clampi(_as_int(contact.get("trust", 0)), REP_MIN, REP_MAX)
	var after := clampi(before + _cap_delta(amount), REP_MIN, REP_MAX)
	var band := _band_for(after, str(contact.get("band", "neutral")))
	var changed := after != before or band != str(contact.get("band", ""))
	contact.trust = after
	contact.band = band
	if changed:
		_log(book, {"kind": "trust", "factionId": str(contact.factionId), "otherId": contact_id, "amount": after - before, "before": before, "after": after, "reason": reason, "eventId": event_id, "day": _day(state)})
	if not event_id.is_empty():
		_remember(book, event_id)
	var faction_score := 0
	if book.factions.has(str(contact.factionId)):
		faction_score = _as_int(book.factions[str(contact.factionId)].score)
	return {"ok": true, "changed": changed, "repeated": false, "channel": "contact", "contactId": contact_id, "trust": after, "band": band, "factionId": str(contact.factionId), "factionScore": faction_score, "message": "Contact trust updated." if changed else "No contact change."}

static func _apply_public(book: Dictionary, faction_id: String, delta: int, reason: String, event_id: String, day: int) -> Dictionary:
	var row: Dictionary = book.factions[faction_id]
	var before := clampi(_as_int(row.get("score", 0)), REP_MIN, REP_MAX)
	var after := clampi(before + delta, REP_MIN, REP_MAX)
	var band := _band_for(after, str(row.get("band", "")))
	var changed := after != before or band != str(row.get("band", ""))
	row.score = after
	row.band = band
	if changed:
		_log(book, {"kind": "public", "factionId": faction_id, "otherId": "", "amount": after - before, "before": before, "after": after, "reason": _short(reason), "eventId": event_id, "day": day})
	return {"channel": "public", "factionId": faction_id, "before": before, "after": after, "band": band, "changed": changed}

static func _apply_witness(book: Dictionary, faction_id: String, delta: int, reason: String, event_id: String, day: int) -> Dictionary:
	var row: Dictionary = book.factions[faction_id]
	var before := clampi(_as_int(row.get("witnessed", 0)), REP_MIN, REP_MAX)
	var after := clampi(before + delta, REP_MIN, REP_MAX)
	row.witnessed = after
	var changed := after != before
	if changed:
		_log(book, {"kind": "witness", "factionId": faction_id, "otherId": "", "amount": after - before, "before": before, "after": after, "reason": _short(reason), "eventId": event_id, "day": day})
	return {"channel": "witness", "factionId": faction_id, "before": before, "after": after, "changed": changed}

static func _apply_claim(book: Dictionary, faction_id: String, port_id: String, amount: int, reason: String, event_id: String, day: int) -> Dictionary:
	var row: Dictionary = book.factions[faction_id]
	if not row.get("claims") is Dictionary:
		row.claims = {}
	var before := clampi(_as_int(row.claims.get(port_id, 0)), 0, CLAIM_MAX)
	var step := mini(DELTA_CAP, absi(_as_int(amount)))
	var after := before
	if amount < 0:
		after = clampi(before + step, 0, CLAIM_MAX)
	elif amount > 0:
		after = clampi(before - step, 0, CLAIM_MAX)
	if after <= 0:
		row.claims.erase(port_id)
		after = 0
	else:
		row.claims[port_id] = after
	var changed := after != before
	if changed:
		_log(book, {"kind": "claim", "factionId": faction_id, "otherId": port_id, "amount": after - before, "before": before, "after": after, "reason": _short(reason), "eventId": event_id, "day": day})
	return {"channel": "claim", "factionId": faction_id, "portId": port_id, "before": before, "after": after, "changed": changed}

static func _apply_time(book: Dictionary, faction_id: String, amount: int, reason: String, event_id: String, day: int) -> Dictionary:
	var row: Dictionary = book.factions[faction_id]
	var before := clampi(_as_int(row.get("score", 0)), REP_MIN, REP_MAX)
	var step := maxi(0, amount)
	var after := before
	if before < 0 and step > 0:
		after = mini(0, before + step)
	var band := _band_for(after, str(row.get("band", "")))
	var changed := after != before or band != str(row.get("band", ""))
	row.score = after
	row.band = band
	if changed:
		_log(book, {"kind": "time", "factionId": faction_id, "otherId": "", "amount": after - before, "before": before, "after": after, "reason": _short(reason), "eventId": event_id, "day": day})
	return {"channel": "time", "factionId": faction_id, "before": before, "after": after, "band": band, "changed": changed}

static func _apply_restitution(book: Dictionary, faction_id: String, amount: int, port_id: String, reason: String, event_id: String, day: int) -> Dictionary:
	var step := maxi(0, amount)
	var public_effect := _apply_public(book, faction_id, step, "Restitution: " + reason, event_id, day)
	var row: Dictionary = book.factions[faction_id]
	var witnessed_before := clampi(_as_int(row.get("witnessed", 0)), REP_MIN, REP_MAX)
	var witnessed_after := _toward_zero(witnessed_before, step)
	row.witnessed = witnessed_after
	if witnessed_after != witnessed_before:
		_log(book, {"kind": "witness", "factionId": faction_id, "otherId": "", "amount": witnessed_after - witnessed_before, "before": witnessed_before, "after": witnessed_after, "reason": "Restitution: " + _short(reason), "eventId": event_id, "day": day})
	var claim_before := 0
	var claim_after := 0
	if not port_id.is_empty() and row.get("claims") is Dictionary:
		claim_before = clampi(_as_int(row.claims.get(port_id, 0)), 0, CLAIM_MAX)
		claim_after = maxi(0, claim_before - step)
		if claim_after <= 0:
			row.claims.erase(port_id)
		else:
			row.claims[port_id] = claim_after
		if claim_after != claim_before:
			_log(book, {"kind": "claim", "factionId": faction_id, "otherId": port_id, "amount": claim_after - claim_before, "before": claim_before, "after": claim_after, "reason": "Restitution: " + _short(reason), "eventId": event_id, "day": day})
	var changed := bool(public_effect.changed) or witnessed_after != witnessed_before or claim_after != claim_before
	return {"channel": "restitution", "factionId": faction_id, "portId": port_id, "before": int(public_effect.before), "after": int(public_effect.after), "witnessedBefore": witnessed_before, "witnessedAfter": witnessed_after, "claimBefore": claim_before, "claimAfter": claim_after, "changed": changed}

static func _time_block(book: Dictionary, faction_id: String) -> Dictionary:
	var row: Dictionary = book.factions[faction_id]
	var witnessed := _as_int(row.get("witnessed", 0))
	if witnessed <= WITNESS_HOSTILE:
		return {"message": "Time does not restore standing while a capital witnessed offense remains open."}
	if _claim_total(row) > 0:
		return {"message": "Time does not restore standing while a port claim remains outstanding."}
	var score := _as_int(row.get("score", 0))
	if score >= 0:
		return {"message": "Time restores standing only toward neutral."}
	return {}

static func _commission_warning(book: Dictionary, faction_id: String, enemies: Array, eligible: bool) -> String:
	var name := _faction_name(book, faction_id)
	var enemy_names: Array = []
	for enemy in enemies:
		enemy_names.append(_faction_name(book, str(enemy)))
	var listed := ", ".join(enemy_names) if not enemy_names.is_empty() else "no declared enemy"
	if not eligible:
		return "Confirming a commission with %s will not commit yet. Current public standing must be friendly or trusted, and no capital witnessed offense may be open. Declared enemies: %s. No stipend will be minted." % [name, listed]
	return "Confirming letters of marque with %s changes legal status with %s by %d and does not mint a stipend. Call commission again to commit." % [name, listed, LEGAL_SHIFT]

static func _enemy_ids(book: Dictionary, faction_id: String) -> Array:
	var found: Array = []
	for other in book.factions.keys():
		var other_id := str(other)
		if other_id == faction_id:
			continue
		if relation({"relationships": book}, faction_id, other_id) <= ENEMY_AT:
			found.append(other_id)
	found.sort()
	return found

static func _band_for(score: int, previous: String) -> String:
	match previous:
		"hostile":
			if score < HOSTILE_EXIT:
				return "hostile"
		"wary":
			if score <= HOSTILE_ENTER:
				return "hostile"
			if score < WARY_EXIT:
				return "wary"
		"neutral":
			return _band_enter(score)
		"friendly":
			if score >= TRUSTED_ENTER:
				return "trusted"
			if score <= WARY_ENTER:
				return _band_enter(score)
			if score > FRIENDLY_EXIT:
				return "friendly"
		"trusted":
			if score > TRUSTED_EXIT:
				return "trusted"
			if score <= WARY_ENTER:
				return _band_enter(score)
	return _band_enter(score)

static func _band_enter(score: int) -> String:
	if score <= HOSTILE_ENTER:
		return "hostile"
	if score <= WARY_ENTER:
		return "wary"
	if score >= TRUSTED_ENTER:
		return "trusted"
	if score >= FRIENDLY_ENTER:
		return "friendly"
	return "neutral"

static func _label(band: String) -> String:
	match band:
		"hostile":
			return "Hostile"
		"wary":
			return "Wary"
		"friendly":
			return "Friendly"
		"trusted":
			return "Trusted"
		_:
			return "Neutral"

static func _recovery_text() -> String:
	return "Restitution clears a witnessed offense and a named port claim while public standing moves. Negotiated work is an ordinary positive public change. Time moves public standing toward neutral only, and only while no port claim and no capital witnessed offense remain."

static func _military_goods() -> Array:
	var goods: Array = []
	for good in MILITARY_GOODS:
		goods.append(good)
	return goods

static func _parse_reason(reason) -> Dictionary:
	var text: String = str(reason) if reason is String else ""
	if text.begins_with("witness:"):
		return {"channel": "witness", "text": text.substr(8), "portId": "", "contactId": ""}
	if text.begins_with("time:"):
		return {"channel": "time", "text": text.substr(5), "portId": "", "contactId": ""}
	if text.begins_with("contact:"):
		var contact_parts := text.split(":", true, 2)
		var contact_id := str(contact_parts[1]) if contact_parts.size() > 1 else ""
		var contact_text := str(contact_parts[2]) if contact_parts.size() > 2 else ""
		return {"channel": "contact", "text": contact_text, "portId": "", "contactId": contact_id}
	if text.begins_with("claim:"):
		var claim_parts := text.split(":", true, 2)
		var claim_port := str(claim_parts[1]) if claim_parts.size() > 1 else ""
		var claim_text := str(claim_parts[2]) if claim_parts.size() > 2 else ""
		return {"channel": "claim", "text": claim_text, "portId": claim_port, "contactId": ""}
	if text.begins_with("restitution:"):
		var rest_parts := text.split(":", true, 2)
		var rest_port := ""
		var rest_text := text.substr(12)
		if rest_parts.size() > 2 and _port_token(str(rest_parts[1])):
			rest_port = str(rest_parts[1])
			rest_text = str(rest_parts[2])
		return {"channel": "restitution", "text": rest_text, "portId": rest_port, "contactId": ""}
	return {"channel": "public", "text": text, "portId": "", "contactId": ""}

static func _port_token(value: String) -> bool:
	return not value.is_empty() and value.find(" ") == -1 and value.find("|") == -1

static func _resolve_port(state: Dictionary, port) -> Dictionary:
	if port is Dictionary and port.get("id") is String and not str(port.id).is_empty() and port.get("faction") is String:
		var direct_name := str(port.id)
		if port.get("name") is String and not str(port.name).is_empty():
			direct_name = str(port.name)
		return {"id": str(port.id), "name": direct_name, "factionId": str(port.faction)}
	var port_id := _port_id(port)
	if port_id.is_empty():
		return {}
	var live = state.get("ports", [])
	if live is Array:
		for candidate in live:
			if candidate is Dictionary and str(candidate.get("id", "")) == port_id:
				var live_name := port_id
				if candidate.get("name") is String and not str(candidate.name).is_empty():
					live_name = str(candidate.name)
				var live_faction := str(candidate.get("faction", "")) if candidate.get("faction") is String else ""
				return {"id": port_id, "name": live_name, "factionId": live_faction}
	var book := _book(state)
	if not book.is_empty() and book.get("portIndex") is Dictionary and book.portIndex.has(port_id):
		var indexed: Dictionary = book.portIndex[port_id]
		return {"id": str(indexed.get("id", port_id)), "name": str(indexed.get("name", port_id)), "factionId": str(indexed.get("factionId", ""))}
	return {}

static func _port_id(port) -> String:
	if port is String:
		return port
	if port is Dictionary and port.get("id") is String:
		return str(port.id)
	return ""

static func _book(state) -> Dictionary:
	if not state is Dictionary or not state.get("relationships") is Dictionary:
		return {}
	return state.relationships

static func _pair_key(a: String, b: String) -> String:
	if a <= b:
		return a + "|" + b
	return b + "|" + a

static func _log(book: Dictionary, entry: Dictionary) -> void:
	book.seq = _as_int(book.get("seq", 0)) + 1
	entry.seq = int(book.seq)
	if not entry.has("day"):
		entry.day = 1
	book.log.append(entry)
	while book.log.size() > LOG_LIMIT:
		book.log.pop_front()

static func _seen(book: Dictionary, event_id: String) -> bool:
	return book.seen is Dictionary and book.seen.has(event_id)

static func _remember(book: Dictionary, event_id: String) -> void:
	if event_id.is_empty() or _seen(book, event_id):
		return
	book.seen[event_id] = true
	book.seenOrder.append(event_id)
	while book.seenOrder.size() > EVENT_LIMIT:
		var old = book.seenOrder.pop_front()
		book.seen.erase(old)

static func _claim_total(row: Dictionary) -> int:
	if not row.get("claims") is Dictionary:
		return 0
	var total := 0
	for port_id in row.claims.keys():
		total += maxi(0, _as_int(row.claims[port_id]))
	return total

static func _toward_zero(value: int, step: int) -> int:
	if step <= 0 or value == 0:
		return value
	if value > 0:
		return maxi(0, value - step)
	return mini(0, value + step)

static func _cap_delta(amount: int) -> int:
	return clampi(amount, -DELTA_CAP, DELTA_CAP)

static func _faction_name(book: Dictionary, faction_id: String) -> String:
	if book.factions.has(faction_id):
		return str(book.factions[faction_id].get("name", faction_id))
	return faction_id

static func _day(state: Dictionary) -> int:
	return maxi(1, _as_int(state.get("day", 1)))

static func _event_id(value) -> String:
	if not value is String:
		return ""
	return value.substr(0, 80)

static func _text_id(value) -> String:
	if not value is String:
		return ""
	return value

static func _short(value) -> String:
	var text: String = str(value) if value is String else ""
	return text.substr(0, 180)

static func _finite_number(value) -> bool:
	if value is int:
		return true
	if value is float:
		return not is_nan(value) and not is_inf(value)
	return false

static func _as_int(value) -> int:
	if value is int:
		return value
	if value is float and not is_nan(value) and not is_inf(value):
		return int(value)
	if value is String and value.is_valid_int():
		return int(value)
	return 0
