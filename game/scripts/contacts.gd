extends RefCounted
## v0.011 persistent harbor contacts and dated market snapshots.
## Trust here is personal and per-contact; it is NOT faction reputation and
## nothing in this module reads or writes any faction standing. All state is
## plain JSON under state["contacts"] and state["marketSnapshots"].
## Market snapshots are recorded only when the captain actually visits a
## harbor (visit()), so their day stamp is honest report age for root UI.

const Goods = preload("res://scripts/goods.gd")

const TRUST_MIN := -100
const TRUST_MAX := 100
const MAX_EVENTS := 32
const MAX_LOG := 20

# Authored original contacts at real world ports. ensure() keeps only ids
# whose port exists in the supplied world (or in state.ports).
const DEFINITIONS := [
	{"id": "contact_mara_voss", "name": "Mara Voss", "role": "shipwright", "port": "anvil_dock",
		"title": "Master shipwright of the Anvil gantry slips"},
	{"id": "contact_tobin_hale", "name": "Tobin Hale", "role": "broker", "port": "brass_haven",
		"title": "Convoy broker at the Bonded Exchange"},
	{"id": "contact_sister_wren", "name": "Sister Wren", "role": "survey_patron", "port": "reed_floats",
		"title": "Survey patron of the estuary chart-keepers"},
	{"id": "contact_cass_rye", "name": "Cass Rye", "role": "salvage_agent", "port": "rust_anchorage",
		"title": "Salvage agent for beached prize hulls"},
]


static func _is_num(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func _num(v, fallback: float = 0.0) -> float:
	return float(v) if _is_num(v) else fallback


static func _known_ports(state: Dictionary, world: Dictionary) -> Dictionary:
	var known := {}
	for p in world.get("PORTS", []) if world.get("PORTS") is Array else []:
		if p is Dictionary:
			known[str(p.get("id", ""))] = true
	for p in state.get("ports", []) if state.get("ports") is Array else []:
		if p is Dictionary:
			known[str(p.get("id", ""))] = true
	return known


static func _fresh(definition: Dictionary) -> Dictionary:
	return {
		"id": str(definition["id"]), "name": str(definition["name"]),
		"role": str(definition["role"]), "port": str(definition["port"]),
		"title": str(definition.get("title", "")), "trust": 0,
		"met": false, "lastVisitDay": 0.0, "events": [], "log": [],
	}


static func _sanitize(raw, definition: Dictionary) -> Dictionary:
	var out := _fresh(definition)
	if raw is Dictionary:
		out["trust"] = clampi(int(_num(raw.get("trust", 0))), TRUST_MIN, TRUST_MAX)
		out["met"] = bool(raw.get("met", false))
		out["lastVisitDay"] = maxf(0.0, _num(raw.get("lastVisitDay", 0.0)))
		var events: Array = []
		for event_id in raw.get("events", []) if raw.get("events") is Array else []:
			if event_id is String and not events.has(event_id):
				events.append(event_id)
		out["events"] = events.slice(maxi(0, events.size() - MAX_EVENTS))
		var log: Array = []
		for entry in raw.get("log", []) if raw.get("log") is Array else []:
			if entry is Dictionary:
				log.append({"day": _num(entry.get("day", 0.0)), "event": str(entry.get("event", "")),
					"amount": int(_num(entry.get("amount", 0))), "trust": clampi(int(_num(entry.get("trust", 0))), TRUST_MIN, TRUST_MAX)})
		out["log"] = log.slice(maxi(0, log.size() - MAX_LOG))
	return out


# Creates/normalizes state["contacts"] from the authored definitions and
# state["marketSnapshots"] ({} portId -> {day, cash, governmentPurse,
# stocks}) without inventing visits or trust. Returns the contact array.
static func ensure(state: Dictionary, world: Dictionary = {}) -> Array:
	var known := _known_ports(state, world)
	var stored := {}
	for raw in state.get("contacts", []) if state.get("contacts") is Array else []:
		if raw is Dictionary:
			stored[str(raw.get("id", ""))] = raw
	var contacts: Array = []
	for definition in DEFINITIONS:
		if not known.is_empty() and not known.has(str(definition["port"])):
			continue
		contacts.append(_sanitize(stored.get(str(definition["id"]), {}), definition))
	state["contacts"] = contacts
	if not (state.get("marketSnapshots") is Dictionary):
		state["marketSnapshots"] = {}
	else:
		var snapshots: Dictionary = {}
		for port_id in state["marketSnapshots"]:
			var snap = state["marketSnapshots"][port_id]
			if snap is Dictionary and (known.is_empty() or known.has(str(port_id))):
				snapshots[str(port_id)] = _clean_snapshot(snap)
		state["marketSnapshots"] = snapshots
	return contacts


static func _clean_snapshot(raw: Dictionary) -> Dictionary:
	var stocks := {}
	var raw_stocks: Dictionary = raw.get("stocks", {}) if raw.get("stocks") is Dictionary else {}
	for good in Goods.ITEMS:
		stocks[good] = maxf(0.0, _num(raw_stocks.get(good, 0.0)))
	return {"day": _num(raw.get("day", 0.0)),
		"cash": maxi(0, int(_num(raw.get("cash", 0)))),
		"governmentPurse": maxi(0, int(_num(raw.get("governmentPurse", 0)))),
		"stocks": stocks}


static func _find(state: Dictionary, contact_id: String) -> Dictionary:
	for contact in state.get("contacts", []) if state.get("contacts") is Array else []:
		if contact is Dictionary and str(contact.get("id", "")) == contact_id:
			return contact
	return {}


# Records an actual harbor visit: stamps that port's market snapshot with the
# given day (the ONLY way snapshots appear or refresh) and meets the local
# contact if the port has one. Returns {ok, port, day, contact, snapshot}
# with copies; an unknown/empty port dictionary is refused without writes.
static func visit(state: Dictionary, port: Dictionary, day) -> Dictionary:
	if port.is_empty() or str(port.get("id", "")).is_empty() or not _is_num(day):
		return {"ok": false, "message": "No harbor to visit."}
	ensure(state)
	var when := maxf(0.0, float(day))
	var snapshot := _clean_snapshot({"day": when, "cash": port.get("cash", 0),
		"governmentPurse": port.get("governmentPurse", 0), "stocks": port.get("stocks", {})})
	state["marketSnapshots"][str(port["id"])] = snapshot
	var met := {}
	for contact in state["contacts"]:
		if str(contact.get("port", "")) == str(port["id"]):
			contact["met"] = true
			contact["lastVisitDay"] = when
			met = contact.duplicate(true)
	return {"ok": true, "port": str(port["id"]), "day": when,
		"contact": met, "snapshot": snapshot.duplicate(true),
		"message": "Market notes recorded at %s." % str(port.get("name", port["id"]))}


# Every contact as a deep copy, sorted by id. Mutating results is harmless.
static func list_contacts(state: Dictionary) -> Array:
	ensure(state)
	var out: Array = []
	for contact in state["contacts"]:
		out.append(contact.duplicate(true))
	out.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	return out


# Applies one trust event exactly once per (contact, event_id). Repeat event
# ids return applied=false with trust unchanged. Amount is clamped with the
# resulting trust to [-100, 100]; the bounded per-contact log keeps the most
# recent MAX_LOG entries with the campaign day from state.
static func record(state: Dictionary, contact_id: String, event_id: String, amount) -> Dictionary:
	ensure(state)
	var contact := _find(state, contact_id)
	if contact.is_empty():
		return {"ok": false, "message": "Unknown contact.", "trust": 0, "applied": false}
	if event_id.is_empty() or not _is_num(amount):
		return {"ok": false, "message": "A trust event needs an id and an amount.", "trust": int(contact["trust"]), "applied": false}
	var events: Array = contact["events"]
	if events.has(event_id):
		return {"ok": true, "message": "Already recorded.", "trust": int(contact["trust"]), "applied": false}
	var delta := clampi(int(amount), -50, 50)
	contact["trust"] = clampi(int(contact["trust"]) + delta, TRUST_MIN, TRUST_MAX)
	contact["met"] = true
	events.append(event_id)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	var log: Array = contact["log"]
	log.append({"day": _num(state.get("day", 0.0)), "event": event_id, "amount": delta, "trust": int(contact["trust"])})
	while log.size() > MAX_LOG:
		log.pop_front()
	return {"ok": true, "message": "Trust recorded.", "trust": int(contact["trust"]), "applied": true}
