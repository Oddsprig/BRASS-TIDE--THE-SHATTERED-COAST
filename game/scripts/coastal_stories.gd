extends RefCounted
## v0.016 original connected exploration chains over the real v0.009 sites,
## ports and v0.011 contacts. Data lives in res://data/coastal_stories.json
## (read once; copied into state on ensure so saves keep stable chains).
## Rewards are knowledge and opportunities only: no coins, boats, crew or
## goods are created. The only physical transfer is an explicit delivery
## cost (player cargo -> named port stocks). Faction/contact consequences
## are RECORDED as pending records for root to apply, never applied here.
## Every accepted choice writes one stable event id exactly once.

const Goods = preload("res://scripts/goods.gd")
const Exploration = preload("res://scripts/exploration.gd")
const Contacts = preload("res://scripts/contacts.gd")

const CATALOG_PATH := "res://data/coastal_stories.json"
const MAX_EVENTS := 128
const MAX_CONSEQUENCES := 64
const CHAINS077 := ["inverted_tide077", "last_soundings077"]
const LONGGLASS_SITE077 := "glasswind_keys:abandoned_cache067"
const LONGGLASS_SOURCE077 := "site:glasswind_keys:abandoned_cache067"

static var _cache: Array = []
static var _loaded := false


static func _is_num(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func _num(v, fallback: float = 0.0) -> float:
	return float(v) if _is_num(v) else fallback


static func _load() -> Array:
	if _loaded:
		return _cache.duplicate(true)
	_loaded = true
	var out: Array = []
	if FileAccess.file_exists(CATALOG_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if parsed is Dictionary and parsed.get("chains") is Array:
			for raw in parsed["chains"]:
				if raw is Dictionary and not str(raw.get("id", "")).is_empty() and raw.get("stages") is Array and not (raw["stages"] as Array).is_empty():
					out.append(raw.duplicate(true))
	out.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	_cache = out.duplicate(true)
	return out


static func catalog(state: Dictionary) -> Array:
	var stories: Dictionary = state.get("stories", {}) if state.get("stories") is Dictionary else {}
	var stored = stories.get("catalog", null)
	return stored if stored is Array and not stored.is_empty() else _load()


static func _chain_def(state: Dictionary, chain_id: String) -> Dictionary:
	for chain in catalog(state):
		if chain is Dictionary and str(chain.get("id", "")) == chain_id:
			return chain
	return {}


static func _stage_def(chain: Dictionary, stage_id: String) -> Dictionary:
	for stage in chain.get("stages", []) if chain.get("stages") is Array else []:
		if stage is Dictionary and str(stage.get("id", "")) == stage_id:
			return stage
	return {}


static func _record(state: Dictionary, chain_id: String) -> Dictionary:
	var stories: Dictionary = state.get("stories", {})
	var chains: Dictionary = stories.get("chains", {}) if stories.get("chains") is Dictionary else {}
	var rec = chains.get(chain_id, null)
	return rec if rec is Dictionary else {}


# Normalizes state["stories"] {catalog, chains{}, events[], consequences[],
# notified[]}. Progress for chains/stages absent from the catalog is dropped.
static func ensure(state: Dictionary) -> Dictionary:
	var stories: Dictionary = state.get("stories", {}) if state.get("stories") is Dictionary else {}
	stories["catalog"] = _load()
	if not (stories.get("chains") is Dictionary):
		stories["chains"] = {}
	for key in ["events", "consequences", "notified"]:
		if not (stories.get(key) is Array):
			stories[key] = []
	for chain_id in (stories["chains"] as Dictionary).keys():
		var def := _chain_def({"stories": stories}, str(chain_id))
		var rec = stories["chains"][chain_id]
		if def.is_empty() or not (rec is Dictionary) or _stage_def(def, str(rec.get("stage", ""))).is_empty() and not bool(rec.get("done", false)):
			stories["chains"].erase(chain_id)
			continue
		rec["flags"] = rec.get("flags", []) if rec.get("flags") is Array else []
		rec["leads"] = rec.get("leads", []) if rec.get("leads") is Array else []
		rec["done"] = bool(rec.get("done", false))
	while (stories["events"] as Array).size() > MAX_EVENTS:
		stories["events"].pop_front()
	while (stories["consequences"] as Array).size() > MAX_CONSEQUENCES:
		stories["consequences"].pop_front()
	state["stories"] = stories
	return stories


static func _site_level(state: Dictionary, site_id: String) -> int:
	for site in Exploration.sites(state):
		if str(site.get("id", "")) == site_id:
			return int(site.get("level", 0))
	return -1


# Only knowledge changes: no survey levels, findings, cargo or story events.
static func _sight_lead(state: Dictionary, site_id: String) -> void:
	var site := _cache_site077(state) if site_id == LONGGLASS_SITE077 else Exploration.catalog_site(state, site_id)
	if not site.is_empty():
		Exploration.discover_near(state, site, 0.0)


# Called on acceptance and by StoryOps when restoring accepted 056 records.
# Journal reads never call this. Existing flags/stages identify earned bearings;
# Campaign may already have sighted Shatter while charting the rock.
static func reconcile_knowledge(state: Dictionary, chain_id: String) -> void:
	if chain_id in CHAINS077:
		var accepted := _record(state, chain_id)
		if accepted.is_empty():
			return
		var first := str(_chain_def(state, chain_id).get("startLead", ""))
		if not first.is_empty() and not (accepted.get("leads", []) as Array).has(first):
			accepted["leads"].append(first)
		for id in accepted.get("leads", []):
			_sight_lead(state, str(id))
		return
	if chain_id != "middle_sea_chart":
		return
	var rec := _record(state, chain_id)
	if rec.is_empty():
		return
	var ids: Array = [str(_chain_def(state, chain_id).get("startLead", "middle_chart_rock"))]
	if (rec.get("flags", []) as Array).has("shared_chart") or (rec.get("flags", []) as Array).has("kept_secret"):
		ids.append("shatter_wreck_field")
	if str(rec.get("stage", "")) == "choose_a_claim":
		ids.append("rust_salvage_anchorage")
	for id in ids:
		if not str(id).is_empty() and not (rec["leads"] as Array).has(id):
			rec["leads"].append(id)
	for id in rec.get("leads", []):
		_sight_lead(state, str(id))


static func _known_site(state: Dictionary, site_id: String) -> Dictionary:
	var site := _cache_site077(state) if site_id == LONGGLASS_SITE077 else Exploration.catalog_site(state, site_id)
	var level := int(site.get("level", 0)) if site_id == LONGGLASS_SITE077 else int(state.get("exploration", {}).get("sites", {}).get(site_id, {}).get("level", 0))
	if site.is_empty() or level < Exploration.LEVEL_SIGHTED:
		return {}
	var row := {"kind": "site", "id": site_id, "name": str(site["name"]),
		"x": float(site["x"]), "y": float(site["y"]), "level": level}
	row["regionId"] = Exploration._site_region(site)
	row["layer"] = "local"
	if site_id == LONGGLASS_SITE077:
		row["id"] = str(site.get("id", site_id))
		row["sourceId"] = LONGGLASS_SOURCE077
	return row


# Detached, already earned AND known locations. Never reveals catalog futures.
static func earned_leads(state: Dictionary, chain_id: String) -> Array:
	var out: Array = []
	for id in _record(state, chain_id).get("leads", []):
		var site := _known_site(state, str(id))
		if site.is_empty():
			continue
		site["nextAction"] = "Site surveyed; consult its existing opportunities and return reserves." if int(site["level"]) >= 3 else "Survey this charted bearing if the voyage's reserves allow." if int(site["level"]) == 2 else "Chart this sighted bearing, then survey it if the voyage's reserves allow."
		out.append(site)
	return out


# Snapshot actual stock only. A surveyed site is not a recovery permission:
# Campaign.recover_wreck still checks proximity, hostiles, party and resources.
static func _recovery_sites(state: Dictionary, chain_id: String) -> Array:
	var out: Array = []
	if chain_id == "last_soundings077":
		return _recovery_sites077(state)
	if chain_id != "middle_sea_chart":
		return out
	for lead in earned_leads(state, chain_id):
		if not str(lead["id"]) in ["shatter_wreck_field", "rust_salvage_anchorage"] or int(lead["level"]) < 3:
			continue
		var row: Dictionary = lead.duplicate(true)
		row["wreckIds"] = []
		row["remainingComponents"] = {}
		row["remainingStores"] = {}
		for wreck in state.get("wrecks", []):
			if not (wreck is Dictionary) or str(wreck.get("sourceId", "")) != "site:" + str(row["id"]) or str(wreck.get("status", "")) != "unclaimed":
				continue
			row["wreckIds"].append(str(wreck["id"]))
			for pair in [["components", "remainingComponents"], ["stores", "remainingStores"]]:
				for good in wreck.get(pair[0], {}):
					row[pair[1]][good] = _num(row[pair[1]].get(good, 0.0)) + maxf(0.0, _num(wreck[pair[0]][good]))
		out.append(row)
	return out


static func _outcome(state: Dictionary, chain_id: String) -> Dictionary:
	if chain_id in CHAINS077:
		return _outcome077(state, chain_id)
	if chain_id != "middle_sea_chart" or not bool(_record(state, chain_id).get("done", false)):
		return {}
	var rights: Dictionary = state.get("storyRights", {})
	var right: String = "openField" if bool(rights.get("openField", false)) else "privateField" if bool(rights.get("privateField", false)) else ""
	if right.is_empty():
		return {}
	var is_public: bool = right == "openField"
	var ports: Array = []
	for port in state.get("ports", []):
		if port is Dictionary and (is_public or str(port.get("faction", "")) == "raiders"):
			ports.append(str(port["id"]))
	var effects: Array = []
	for effect in state.get("stories", {}).get("consequences", []):
		if effect is Dictionary and str(effect.get("id", "")).begins_with("story:middle_sea_chart:"):
			effects.append({"kind": str(effect["kind"]), "target": str(effect["target"]),
				"amount": int(effect["amount"]), "reason": str(effect["reason"]), "applied": bool(effect.get("applied", false))})
	return {"right": right, "title": "Low Lantern's bearing made public" if is_public else "Low Lantern's bearing kept private",
		"body": ("Wren has registered the survey. Sharing earned Wren's trust (+8) and Reed standing (+3); opening the field earned Reed +4 and Reef -3. Nearby Commune traders may now spend their own kits and spare hands on Shatter's remaining finite materials." if is_public else "The survey stays out of Wren's register. Keeping the field private cost Wren 4 trust; Commune traders receive no public recovery right. The private salvage-yard charter is registered only through Reef harbors.") + " Your recovered cargo remains yours. Low Lantern's shelter bearing at Rust is an optional future voyage; no hull, goods or coins were awarded. Surveyed Shatter's finite hull-jig source and Rust's engine-fixture source use the existing paid machinery recovery, when still unextracted.",
		"consequences": effects,
		"charter": {"kind": "salvage_yard", "portIds": ports,
			"conditions": "Dock with legal service access at a candidate harbor. A surveyed field, available physical materials, setup workers and specialists, paid staff, setup coins and working capital are required; the current home-harbor quote decides availability. The yard stores and works real inventory; it does not generate wreck stock."}}


static func _npc_defeated(state: Dictionary, owner_id: String) -> bool:
	if int(state.get("defeatedOwners",{}).get(owner_id,0))>0:return true
	for owner in state.get("fleetOwners", []) if state.get("fleetOwners") is Array else []:
		if owner is Dictionary and str(owner.get("id", "")) == owner_id:
			if int(owner.get("defeats",0))>0:return true
			if not bool(owner.get("active", false)):
				return true
			var boats: Array = owner.get("boats", []) if owner.get("boats") is Array else []
			return not boats.is_empty() and boats.all(func(b): return b is Dictionary and bool(b.get("sunk", false)))
	return false


static func _at_port(core, port_id: String) -> bool:
	if core != null and core.has_method("current_port"):
		var dock: Dictionary = core.current_port()
		return not dock.is_empty() and str(dock.get("id", "")) == port_id
	return false


static func _visited(state: Dictionary, port_id: String) -> bool:
	var snaps = state.get("marketSnapshots", null)
	return snaps is Dictionary and snaps.has(port_id)


static func _contact_met(state: Dictionary, contact_id: String) -> bool:
	for contact in Contacts.list_contacts(state):
		if str(contact.get("id", "")) == contact_id:
			return bool(contact.get("met", false))
	return false


# Gate check -> {ok, message}. Types: site {site,level}, at_port {port},
# visit {port} (a dated Contacts snapshot exists), npc_defeated {owner},
# contact_met {contact}, none/missing (always ok).
static func _gate(core, state: Dictionary, gate: Dictionary) -> Dictionary:
	match str(gate.get("type", "none")):
		"site":
			var level := _site_level(state, str(gate.get("site", "")))
			if level < 0:
				return {"ok": false, "message": "Unknown survey site."}
			if level < int(gate.get("level", 1)):
				return {"ok": false, "message": "That site is not %s yet." % Exploration.LEVEL_NAMES[clampi(int(gate.get("level", 1)), 0, 3)]}
		"at_port":
			if not _at_port(core, str(gate.get("port", ""))):
				return {"ok": false, "message": "Be at the named harbor first."}
		"visit":
			if not _visited(state, str(gate.get("port", ""))):
				return {"ok": false, "message": "Visit that harbor first."}
		"npc_defeated":
			if not _npc_defeated(state, str(gate.get("owner", ""))):
				return {"ok": false, "message": "That fleet is still at sea."}
		"contact_met":
			if not _contact_met(state, str(gate.get("contact", ""))):
				return {"ok": false, "message": "Meet that contact first."}
	return {"ok": true, "message": ""}


static func _location(core, state: Dictionary, chain: Dictionary, stage: Dictionary) -> Dictionary:
	var gate: Dictionary = stage.get("gate", {}) if stage.get("gate") is Dictionary else {}
	if str(gate.get("type", "")) == "site":
		if str(chain.get("id", "")) in CHAINS077:
			var site_id := str(gate.get("site", ""))
			var known := _known_site(state, site_id)
			if not known.is_empty() and (_record(state, str(chain["id"])).get("leads", []) as Array).has(site_id):
				return known
		else:
			var site := Exploration.catalog_site(state, str(gate.get("site", "")))
			if not site.is_empty():
				return {"kind": "site", "id": str(site["id"]), "name": str(site["name"]), "x": float(site["x"]), "y": float(site["y"])}
	var port_id := str(gate.get("port", chain.get("startPort", "")))
	for p in state.get("ports", []) if state.get("ports") is Array else []:
		if p is Dictionary and str(p.get("id", "")) == port_id:
			return {"kind": "port", "id": port_id, "name": str(p.get("name", port_id)), "x": _num(p.get("x", 0.0)), "y": _num(p.get("y", 0.0))}
	return {"kind": "port", "id": port_id, "name": port_id, "x": 0.0, "y": 0.0}


# Chains that can be started right now: not begun, captain docked at the
# start port, and its start contact (if any) already met through a visit.
static func available(core) -> Array:
	if core == null or not (core.get("state") is Dictionary):
		return []
	var state: Dictionary = core.state
	ensure(state)
	Contacts.ensure(state, core.data if core.get("data") is Dictionary else {})
	var out: Array = []
	for chain in catalog(state):
		if not (chain is Dictionary) or not _record(state, str(chain["id"])).is_empty():
			continue
		if not _at_port(core, str(chain.get("startPort", ""))):
			continue
		var contact_id := str(chain.get("startContact", ""))
		if not contact_id.is_empty() and not _contact_met(state, contact_id):
			continue
		var first: Dictionary = (chain["stages"] as Array)[0]
		out.append({"id": str(chain["id"]), "title": str(chain["title"]),
			"approach": str(chain.get("approach", "")), "summary": str(chain.get("summary", "")),
			"startPort": str(chain["startPort"]), "startContact": contact_id,
			"stage": str(first["id"]), "nextAction": str(first.get("nextAction", "")),
			"location": _location(core, state, chain, first),
			"choices": (first.get("choices", []) as Array).duplicate(true)})
	return out


static func _fail(core, message: String) -> Dictionary:
	return core.fail(message) if core != null and core.has_method("fail") else {"ok": false, "message": message}


static func _apply_cost(core, state: Dictionary, cost: Dictionary) -> Dictionary:
	if cost.is_empty():
		return {"ok": true, "message": ""}
	var good := str(cost.get("good", ""))
	var qty := _num(cost.get("qty", 0.0))
	var port_id := str(cost.get("port", ""))
	if not Goods.ITEMS.has(good) or qty <= 0.0:
		return {"ok": false, "message": "That delivery is malformed."}
	if not _at_port(core, port_id):
		return {"ok": false, "message": "Deliver at the named harbor."}
	var cargo: Dictionary = state.get("cargo", {}) if state.get("cargo") is Dictionary else {}
	if _num(cargo.get(good, 0.0)) + 0.000001 < qty:
		return {"ok": false, "message": "Your hold lacks the promised %s." % str(Goods.ITEMS[good]["name"])}
	var target: Dictionary = core.port(port_id) if core.has_method("port") else {}
	if target.is_empty() or not (target.get("stocks") is Dictionary):
		return {"ok": false, "message": "That harbor cannot receive cargo."}
	cargo[good] = _num(cargo.get(good, 0.0)) - qty
	state["cargo"] = cargo
	target["stocks"][good] = _num(target["stocks"].get(good, 0.0)) + qty
	return {"ok": true, "message": ""}


# Starts (when needed) and advances one chain by one chosen decision. Gate,
# required-flag and delivery-cost checks all run before any write, so a
# refusal is atomic. On success exactly one event id
# "story:<chain>:<stage>:<choice>" is recorded; the same choice can never
# settle twice. Consequences are appended as pending records for root.
static func choose(core, chain_id: String, choice_id: String) -> Dictionary:
	if core == null or not (core.get("state") is Dictionary):
		return _fail(core, "No campaign state.")
	var state: Dictionary = core.state
	var stories := ensure(state)
	var chain := _chain_def(state, chain_id)
	if chain.is_empty():
		return _fail(core, "Unknown coastal story.")
	var rec := _record(state, chain_id)
	var starting := rec.is_empty()
	if starting:
		var startable := false
		for offer in available(core):
			if str(offer.get("id", "")) == chain_id:
				startable = true
		if not startable:
			return _fail(core, "Start this story at its harbor, after meeting its contact.")
		rec = {"stage": str((chain["stages"] as Array)[0]["id"]), "flags": [], "leads": [],
			"done": false, "startedDay": _num(state.get("day", 0.0))}
		# Starting is itself the harbor commitment: the record persists even
		# when the first stage's gate (elsewhere) is not met yet.
		stories["chains"][chain_id] = rec
		reconcile_knowledge(state, chain_id)
	if bool(rec.get("done", false)):
		return _fail(core, "That story is finished.")
	var stage := _stage_def(chain, str(rec["stage"]))
	if stage.is_empty():
		return _fail(core, "That story has lost its place.")
	var choice := {}
	for candidate in stage.get("choices", []) if stage.get("choices") is Array else []:
		if candidate is Dictionary and str(candidate.get("id", "")) == choice_id:
			choice = candidate
	if choice.is_empty():
		return _fail(core, "That is not a choice this story offers now.")
	var event_id := "story:%s:%s:%s" % [chain_id, str(stage["id"]), choice_id]
	if event_id in (stories["events"] as Array):
		return _fail(core, "That decision is already made.")
	var required := str(choice.get("requiresFlag", ""))
	if not required.is_empty() and not (rec["flags"] as Array).has(required):
		return _fail(core, "An earlier decision closed that path.")
	var gate := _gate(core, state, stage.get("gate", {}) if stage.get("gate") is Dictionary else {})
	if not bool(gate["ok"]):
		return _fail(core, str(gate["message"]))
	# Validate the destination before the (mutating) delivery transfer.
	var next_id := str(choice.get("next", "done"))
	if next_id != "done" and _stage_def(chain, next_id).is_empty():
		return _fail(core, "That choice leads nowhere charted.")
	var paid := _apply_cost(core, state, choice.get("cost", {}) if choice.get("cost") is Dictionary else {})
	if not bool(paid["ok"]):
		return _fail(core, str(paid["message"]))
	if starting:
		stories["chains"][chain_id] = rec
	stories["events"].append(event_id)
	while (stories["events"] as Array).size() > MAX_EVENTS:
		stories["events"].pop_front()
	for flag in choice.get("setFlags", []) if choice.get("setFlags") is Array else []:
		if not (rec["flags"] as Array).has(str(flag)):
			rec["flags"].append(str(flag))
	for lead in choice.get("leads", []) if choice.get("leads") is Array else []:
		if not (rec["leads"] as Array).has(str(lead)):
			rec["leads"].append(str(lead))
		if chain_id in ["middle_sea_chart", "inverted_tide077", "last_soundings077"]:
			_sight_lead(state, str(lead))
	var reveal := str(choice.get("reveal", ""))
	if not reveal.is_empty():
		var site := Exploration.catalog_site(state, reveal)
		if not site.is_empty():
			Exploration.discover_near(state, {"x": float(site["x"]), "y": float(site["y"])}, 1.0)
	var recorded: Array = []
	for raw in choice.get("consequences", []) if choice.get("consequences") is Array else []:
		if raw is Dictionary and str(raw.get("kind", "")) in ["faction", "contact"]:
			var entry := {"id": "%s:%s:%s" % [event_id, str(raw["kind"]), str(raw.get("target", ""))],
				"kind": str(raw["kind"]), "target": str(raw.get("target", "")),
				"amount": int(_num(raw.get("amount", 0))), "reason": str(raw.get("reason", "")),
				"day": _num(state.get("day", 0.0)), "applied": false}
			stories["consequences"].append(entry)
			recorded.append(entry.duplicate(true))
	while (stories["consequences"] as Array).size() > MAX_CONSEQUENCES:
		stories["consequences"].pop_front()
	rec["done"] = next_id == "done"
	if not rec["done"]:
		rec["stage"] = next_id
	if core.has_method("log_entry"):
		core.log_entry("%s: %s." % [str(chain["title"]), str(choice.get("text", choice_id))])
	var out: Dictionary = core.ok(str(choice.get("text", "Decision made."))) if core.has_method("ok") else {"ok": true, "message": str(choice.get("text", ""))}
	out.merge({"chainId": chain_id, "stage": str(rec["stage"]), "done": bool(rec["done"]),
		"eventId": event_id, "consequences": recorded, "leads": (rec["leads"] as Array).duplicate()}, true)
	return out


# One journal entry per started chain: stage, next action, where to go, and
# the choices on offer. Finished chains remain listed with done=true.
static func journal(state: Dictionary) -> Array:
	ensure(state)
	var stories: Dictionary = state["stories"]
	var out: Array = []
	for chain in catalog(state):
		if not (chain is Dictionary):
			continue
		var rec := _record(state, str(chain["id"]))
		if rec.is_empty():
			continue
		var stage := _stage_def(chain, str(rec["stage"]))
		var gate: Dictionary = stage.get("gate", {})
		var objective: Dictionary = {}
		if not bool(rec["done"]) and str(gate.get("type", "")) == "site":
			objective = {"siteId": str(gate["site"]), "requiredLevel": int(gate.get("level", 1))}
		var outcome := _outcome(state, str(chain["id"]))
		out.append({"chainId": str(chain["id"]), "title": str(chain["title"]),
			"approach": str(chain.get("approach", "")), "stage": str(rec["stage"]),
			"stageTitle": str(stage.get("title", "")), "done": bool(rec["done"]),
			"nextAction": str(outcome.get("nextAction", "Check remaining recovery or a paid salvage-yard charter; budget the Rust detour before sailing.")) if not outcome.is_empty() else "Finished." if bool(rec["done"]) else str(stage.get("nextAction", "")),
			"body": str(stage.get("body", "")), "objective": objective,
			"earnedLeads": earned_leads(state, str(chain["id"])), "outcome": outcome,
			"recoverySites": _recovery_sites(state, str(chain["id"])),
			"location": _location(null, state, chain, stage),
			"flags": (rec["flags"] as Array).duplicate(), "leads": (rec["leads"] as Array).duplicate(),
			"choices": [] if bool(rec["done"]) else (stage.get("choices", []) as Array).duplicate(true)})
	return out


# Notifies once when an active stage's gate newly becomes satisfiable, so
# root can prompt the captain. Never advances a chain by itself: every
# progression still needs the player's choose().
static func tick(core) -> Array:
	var events: Array = []
	if core == null or not (core.get("state") is Dictionary):
		return events
	var state: Dictionary = core.state
	var stories := ensure(state)
	for chain in catalog(state):
		if not (chain is Dictionary):
			continue
		var rec := _record(state, str(chain["id"]))
		if rec.is_empty() or bool(rec["done"]):
			continue
		var stage := _stage_def(chain, str(rec["stage"]))
		var key := "ready:%s:%s" % [str(chain["id"]), str(rec["stage"])]
		if key in (stories["notified"] as Array):
			continue
		if bool(_gate(core, state, stage.get("gate", {}) if stage.get("gate") is Dictionary else {})["ok"]):
			stories["notified"].append(key)
			events.append({"kind": "gate_ready", "chainId": str(chain["id"]), "stage": str(rec["stage"]),
				"nextAction": str(stage.get("nextAction", "")), "location": _location(core, state, chain, stage)})
	while (stories["notified"] as Array).size() > MAX_EVENTS:
		stories["notified"].pop_front()
	return events


# The cache is a finite wreck at the surveyed south sounding, not another site.
static func _cache_site077(state: Dictionary) -> Dictionary:
	if state.get("wreckSeededSources", {}).get(LONGGLASS_SOURCE077, false) != true:
		return {}
	for site_id in ["glasswind_west_marker", "glasswind_crown_log", "glasswind_south_wreck"]:
		if _site_level(state, site_id) < 3:
			return {}
	var site := Exploration.catalog_site(state, "glasswind_south_wreck")
	if site.is_empty():
		return {}
	for wreck in state.get("wrecks", []):
		if wreck is Dictionary and str(wreck.get("sourceId", "")) == LONGGLASS_SOURCE077:
			var bearing: Dictionary = site.duplicate(true)
			bearing["level"] = 3
			bearing["layer"] = "local"
			return bearing
	return {}


static func _recovery_sites077(state: Dictionary) -> Array:
	var out: Array = []
	for lead in earned_leads(state, "last_soundings077"):
		if str(lead.get("sourceId", "")) != LONGGLASS_SOURCE077 or int(lead["level"]) < 3:
			continue
		var row: Dictionary = lead.duplicate(true)
		row["sourceExists"] = false
		row["wreckIds"] = []
		row["remainingComponents"] = {}
		row["remainingStores"] = {}
		for wreck in state.get("wrecks", []):
			if not (wreck is Dictionary) or str(wreck.get("sourceId", "")) != LONGGLASS_SOURCE077:
				continue
			row["sourceExists"] = true
			if str(wreck.get("status", "")) != "unclaimed":
				continue
			row["wreckIds"].append(str(wreck.get("id", "")))
			for pair in [["components", "remainingComponents"], ["stores", "remainingStores"]]:
				for good in wreck.get(pair[0], {}):
					row[pair[1]][good] = _num(row[pair[1]].get(good, 0.0)) + maxf(0.0, _num(wreck[pair[0]][good]))
		out.append(row)
	return out


static func _outcome077(state: Dictionary, chain_id: String) -> Dictionary:
	var rec := _record(state, chain_id)
	if not bool(rec.get("done", false)):
		return {}
	var flags: Array = rec.get("flags", [])
	var title := ""
	var body := ""
	var next_action := "The register is settled; its consequences remain in your journal."
	if chain_id == "inverted_tide077":
		if flags.has("tide_public077") and not flags.has("tide_bonded077"):
			title = "The inverted tide book is public"
			body = "Wren has registered your measured correction publicly: Reed +4, Compact -2, Wren +6. One finite four-kit freight opportunity is unlocked at Reedwater Floats for Silt Hollow, subject to actual stocks, treasury funds and a route."
		elif flags.has("tide_bonded077") and not flags.has("tide_public077"):
			title = "The inverted tide book is bonded"
			body = "Your measured correction is in the bonded register: Compact +4, Reed -2, Tobin +6, Wren -3. One finite four-kit freight opportunity is unlocked at Brass Haven for Silt Hollow, subject to actual stocks, treasury funds and a route."
		next_action = "Check the chosen origin harbor for the once-only funded passage. The tide-book decision is already complete."
	elif chain_id == "last_soundings077":
		if flags.has("soundings_public077"):
			title = "The last soundings are in Wren's register"
			body = "You registered the soundings with Wren at Reedwater Floats: Reed +4, Raiders -3, Wren +6."
		elif flags.has("soundings_cass077"):
			title = "The last soundings are in Cass's register"
			body = "You registered the soundings with Cass at Rust Anchorage after obtaining normal service access: Raiders +4, Reed -3, Cass +6. This decision grants no harbor permission."
		if flags.has("paid_longglass077"):
			body += " Your completed paid load from the actual Longglass cache is recorded. Remaining stock stays finite; the register grants no goods, machinery or payment."
		elif flags.has("empty_longglass077"):
			body += " The surveyed, seeded cache was verified exhausted. This branch records exhaustion and claims no paid recovery for this lead; nothing was refilled or granted."
	if title.is_empty():
		return {}
	var effects: Array = []
	for effect in state.get("stories", {}).get("consequences", []):
		if effect is Dictionary and str(effect.get("id", "")).begins_with("story:" + chain_id + ":"):
			effects.append(effect.duplicate(true))
	return {"title": title, "body": body, "nextAction": next_action, "consequences": effects}


# Read saved knowledge and earned records only; no ensure, discovery or restore.
static func site_reflection(state: Dictionary, site_id: String) -> String:
	var exploration: Dictionary = state.get("exploration", {}) if state.get("exploration") is Dictionary else {}
	var sites: Dictionary = exploration.get("sites", {}) if exploration.get("sites") is Dictionary else {}
	var known = sites.get(site_id, null)
	if not (known is Dictionary) or _num(known.get("level", 0)) < 1.0:
		return ""
	for chain_id in CHAINS077:
		var rec := _record(state, str(chain_id))
		if rec.is_empty() or not (rec.get("leads", []) as Array).has(site_id):
			continue
		var flags: Array = rec.get("flags", [])
		if bool(rec.get("done", false)):
			return str(_outcome077(state, str(chain_id)).get("body", ""))
		if chain_id == "inverted_tide077":
			if flags.has("matched_marsh_scales077"):
				return "The salt staff and marsh scales agree. Wren still awaits your register choice at Reedwater Floats."
			if flags.has("read_salt_staff077"):
				return "Your chart has the salt staff's reversed marks; the marsh comparison is still unfinished."
			return "Wren's salt-staff lead is entered; no tide register has been settled."
		if flags.has("empty_longglass077"):
			return "You verified the surveyed cache was exhausted. This records no paid recovery for this lead; the selected harbor register still awaits your permitted turn-in."
		if flags.has("paid_longglass077"):
			return "A completed paid load from the actual Longglass cache is recorded for this lead. A harbor register still needs your choice and permitted turn-in."
		if flags.has("south_soundings077"):
			return "Your three soundings are recorded. Check the real cache through paid recovery; depletion alone proves no work by your party."
		if flags.has("crown_soundings077"):
			return "The west marker and crown log have been surveyed and recorded; the south wreck sounding remains."
		if flags.has("west_soundings077"):
			return "The west marker's sounding is recorded; the crown and south records remain unfinished."
		return "Tobin's west-marker lead is entered; no recovery is claimed."
	return ""
