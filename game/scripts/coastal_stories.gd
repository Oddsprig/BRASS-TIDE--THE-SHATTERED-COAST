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
const CHAINS087 := ["broken_meridian087", "unfinished_keel087", "two_lantern_anchorage087"]
const KEEL087_SOURCE_PREFIX := "site:unfinished_keel087:"
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
	# The main arc is a small append-only content file; existing nine chains stay intact.
	var campaign = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign_main110.json"))
	if campaign is Dictionary and campaign.get("chains") is Array:
		for entry in campaign.chains:
			if entry is Dictionary and entry.get("id") is String and entry.get("stages") is Array:out.append(entry.duplicate(true))
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
	var base_catalog: Array = _load()
	if not (stories.get("chains") is Dictionary):
		stories["chains"] = {}
	_ensure_destinations087(state, stories)
	stories["catalog"] = _apply_destinations087(stories, base_catalog)
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
	if chain_id in CHAINS077 or chain_id in CHAINS087:
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
	row["layer"] = "home" if row["regionId"] == Exploration.HOME_REGION else "local"
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
	if chain_id == "unfinished_keel087":
		return _recovery_sites087(state)
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
	if chain_id in CHAINS077 or chain_id in CHAINS087:
		return _outcome077(state, chain_id) if chain_id in CHAINS077 else _outcome087(state, chain_id)
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
		if not dock.is_empty() and str(dock.get("id", "")) == port_id:
			return true
	if core != null and core.has_method("work_port070"):
		var remote_dock: Dictionary = core.work_port070()
		return not remote_dock.is_empty() and str(remote_dock.get("id", "")) == port_id
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
		"none":pass
		"arc110":
			if core==null:return {"ok":false,"message":"Open the campaign aboard your actual fleet."}
			return core.Arc110.gate(core,gate)
		"arc111":
			if core==null:return {"ok":false,"message":"Open this investigation aboard your actual fleet."}
			return core.Arc111.gate(core,gate)
		"arc112":
			if core==null:return {"ok":false,"message":"Open this withdrawal aboard your actual fleet."}
			return core.Arc112.gate(core,gate)
		"arc113":
			if core==null:return {"ok":false,"message":"Open this order aboard your actual fleet."}
			return core.Arc113.optional_gate(core) if str(gate.get("mode",""))=="optional" else core.Arc113.choice_gate(core,"report_materials113")
		"arc114":
			return core.Arc114.gate(core,gate) if core!=null else {"ok":false,"message":"Return to the voyage."}
		"arc115":
			return core.Arc115.gate(core,gate) if core!=null else {"ok":false,"message":"Return to the voyage."}
		"unreleased":return {"ok":false,"message":str(gate.get("message","This campaign operation is unavailable."))}
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
		_:return {"ok":false,"message":"Unknown campaign objective; progress has not been changed."}
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
				var s_region: String = Exploration._site_region(site)
				return {"kind": "site", "id": str(site["id"]), "name": str(site["name"]), "x": float(site["x"]), "y": float(site["y"]), "regionId": s_region, "layer": "home" if s_region == Exploration.HOME_REGION else "local"}
	var port_id := str(gate.get("port", chain.get("startPort", "")))
	for p in state.get("ports", []) if state.get("ports") is Array else []:
		if p is Dictionary and str(p.get("id", "")) == port_id:
			var p_region: String = str(p.get("regionId", Exploration.HOME_REGION))
			return {"kind": "port", "id": port_id, "name": str(p.get("name", port_id)), "x": _num(p.get("x", 0.0)), "y": _num(p.get("y", 0.0)), "regionId": p_region, "layer": "home" if p_region == Exploration.HOME_REGION else "local"}
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
		if str(chain.get("id", "")) in CHAINS087 and not package_available087(state, str(chain.get("id", ""))):
			continue
		if not _at_port(core, str(chain.get("startPort", ""))):
			continue
		var contact_id := str(chain.get("startContact", ""))
		if not contact_id.is_empty() and not _contact_met(state, contact_id):
			continue
		if not _gate(core,state,chain.get("startGate",{})).ok:continue
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
		if chain_id in ["middle_sea_chart", "inverted_tide077", "last_soundings077"] or chain_id in CHAINS087:
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
	for chain_id in CHAINS087:
		var rec087 := _record(state, str(chain_id))
		if rec087.is_empty() or not (rec087.get("leads", []) as Array).has(site_id):
			continue
		var flags087: Array = rec087.get("flags", [])
		if bool(rec087.get("done", false)):
			return str(_outcome087(state, str(chain_id)).get("body", ""))
		if chain_id == "broken_meridian087":
			if flags087.has("meridian_full_survey087"):
				return "Both halves of the outer meridian table are surveyed and sealed. Return to Wren at Reedwater Floats."
			if flags087.has("meridian_turned_home087"):
				return "The single-station meridian sight is logged for a safe return to Reedwater Floats; the outer bearing remains unrevealed."
			if flags087.has("meridian_pushed_far087"):
				return "The first meridian post is charted and the farther counter-post bearing is computed."
			return "Wren's broken-meridian lead is entered; chart this outer post before deciding whether to press farther."
		if chain_id == "unfinished_keel087":
			if flags087.has("keel_verified_empty087"):
				return "You verified the slipway cradle was stripped clean; return to Mara at Anvil Dock to close the ledger."
			if flags087.has("keel_left_intact087"):
				return "You left the heavy workboat frame on the slipway to preserve voyage margin; return to Mara at Anvil Dock."
			if flags087.has("keel_recovered_paid087") or flags087.has("paid_keel_source087"):
				return "Your paid recovery lot from the stranded workboat cradle is recorded; close the slipway ledger at Anvil Dock."
			if flags087.has("keel_surveyed087"):
				return "The slipway cradle is surveyed. Weigh a paid recovery lot against hold and crew margins, or leave the frame intact."
			return "Mara's stranded-slipway lead is entered; complete a full survey before weighing recovery."
		if chain_id == "two_lantern_anchorage087":
			if flags087.has("supplied_lantern_berth087"):
				return "Four repair kits were delivered to brace the lower lantern frame; settle the night-range charter at the harbor desk."
			if flags087.has("lantern_headland_charted087"):
				return "The shifted spit alignment is plotted from the headland. Dock at the frontier harbor with four repair kits."
			return "Tobin's two-lantern headland lead is entered; chart the shifted spit alignment first."
	return ""


static func _raw_site_level087(state: Dictionary, site_id: String) -> int:
	var ex: Dictionary = state.get("exploration", {}) if state.get("exploration") is Dictionary else {}
	var sites: Dictionary = ex.get("sites", {}) if ex.get("sites") is Dictionary else {}
	var rec = sites.get(site_id, null)
	return int(_num(rec.get("level", 0))) if rec is Dictionary else 0


static func _ensure_destinations087(state: Dictionary, stories: Dictionary) -> void:
	var sector = state.get("sector069", null)
	if not (sector is Dictionary) or not (sector.get("sites") is Array) or (sector["sites"] as Array).is_empty():
		stories["destinations087"] = {
			"schema": 1, "bound": false, "available": false,
			"status": "unavailable_legacy_two_region",
			"reason": "Legacy two-region save retains its original two regions; v0.087 remote destination packages require a seeded 48-group ocean world.",
			"packages": {}
		}
		return
	var existing = stories.get("destinations087", null)
	var prev_pkgs: Dictionary = existing.get("packages", {}) if existing is Dictionary and bool(existing.get("bound", false)) and existing.get("packages") is Dictionary else {}
	var chains_book: Dictionary = stories.get("chains", {}) if stories.get("chains") is Dictionary else {}
	var used_remote: Dictionary = {}
	var mer_pkg: Dictionary = prev_pkgs.get("broken_meridian087", {}) if prev_pkgs.get("broken_meridian087") is Dictionary else {}
	var mer_started: bool = chains_book.get("broken_meridian087") is Dictionary and not (chains_book["broken_meridian087"] as Dictionary).is_empty()
	if not mer_pkg.is_empty() and bool(mer_pkg.get("available", false)):
		var s1_ok: bool = mer_started or (_raw_site_level087(state, str(mer_pkg.get("firstSiteId", ""))) == 0 and _raw_site_level087(state, str(mer_pkg.get("secondSiteId", ""))) == 0)
		if s1_ok:
			used_remote[str(mer_pkg.get("firstRegionId", ""))] = true
			used_remote[str(mer_pkg.get("secondRegionId", ""))] = true
		else:
			mer_pkg = {}
	var keel_pkg: Dictionary = prev_pkgs.get("unfinished_keel087", {}) if prev_pkgs.get("unfinished_keel087") is Dictionary else {}
	var keel_started: bool = chains_book.get("unfinished_keel087") is Dictionary and not (chains_book["unfinished_keel087"] as Dictionary).is_empty()
	if not keel_pkg.is_empty() and bool(keel_pkg.get("available", false)):
		var k_region: String = str(keel_pkg.get("regionId", ""))
		var k_site: String = str(keel_pkg.get("siteId", ""))
		var k_ok: bool = not used_remote.has(k_region) and (keel_started or _raw_site_level087(state, k_site) == 0)
		if k_ok:
			used_remote[k_region] = true
		else:
			keel_pkg = {}
	var lan_pkg: Dictionary = prev_pkgs.get("two_lantern_anchorage087", {}) if prev_pkgs.get("two_lantern_anchorage087") is Dictionary else {}
	var lan_started: bool = chains_book.get("two_lantern_anchorage087") is Dictionary and not (chains_book["two_lantern_anchorage087"] as Dictionary).is_empty()
	if not lan_pkg.is_empty() and bool(lan_pkg.get("available", false)):
		var l_site: String = str(lan_pkg.get("siteId", ""))
		if not lan_started and _raw_site_level087(state, l_site) > 0:
			lan_pkg = {}
	if not mer_pkg.is_empty() and not keel_pkg.is_empty() and not lan_pkg.is_empty():
		return
	var remote_candidates: Array = []
	var frontier_candidates: Array = []
	var tombstones: Dictionary = state.get("wreckSeededSources", {}) if state.get("wreckSeededSources") is Dictionary else {}
	var bands: Dictionary = sector.get("bands", {})
	for raw_landing in sector["sites"]:
		if not (raw_landing is Dictionary):
			continue
		var landing: Dictionary = raw_landing
		var gid: String = str(landing.get("regionId", ""))
		var band: String = str(bands.get(gid, ""))
		var site_id: String = str(landing.get("id", ""))
		if site_id.is_empty() or _raw_site_level087(state, site_id) > 0:
			continue
		var region: Dictionary = Exploration.region_record069(state, gid)
		var origin: Dictionary = region.get("oceanOrigin", {})
		var dist: float = Vector2(_num(origin.get("x", 1600.0)) - 1600.0, _num(origin.get("y", 2100.0)) - 2100.0).length()
		# Canonical landings carry resource/clue/hazard text, not an opportunity.kind.
		var opp_kind: String = str(landing.get("resource", ""))
		if band == "remote" and not used_remote.has(gid) and not tombstones.has(KEEL087_SOURCE_PREFIX + site_id):
			remote_candidates.append({"regionId": gid, "siteId": site_id, "dist": dist, "opportunity": opp_kind})
		elif band == "frontier":
			for harbor in sector.get("harbors", []):
				if harbor is Dictionary and str(harbor.get("regionId", "")) == gid and str(harbor.get("islandId", "")) == str(landing.get("islandId", "")):
					frontier_candidates.append({"regionId": gid, "siteId": site_id, "portId": str(harbor["id"]),
						"faction": str(harbor.get("faction", "compact")), "dist": dist, "opportunity": opp_kind})
					break
	remote_candidates.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]) if not is_equal_approx(float(a["dist"]), float(b["dist"])) else str(a["regionId"]) < str(b["regionId"]))
	frontier_candidates.sort_custom(func(a, b): return str(a["regionId"]) < str(b["regionId"]))
	var seed_val: int = int(state.get("seed", 0))
	if mer_pkg.is_empty():
		if remote_candidates.size() >= 2:
			var half: int = maxi(1, remote_candidates.size() / 2)
			var first_idx: int = posmod(seed_val, half)
			for idx in range(half):
				var probe: int = posmod(seed_val + idx, half)
				if str(remote_candidates[probe]["opportunity"]) in ["food", "medicinal_plants"]:
					first_idx = probe
					break
			var first_pick: Dictionary = remote_candidates[first_idx]
			var second_idx: int = remote_candidates.size() - 1
			for idx in range(first_idx + 1, remote_candidates.size()):
				if str(remote_candidates[idx]["opportunity"]) != str(first_pick["opportunity"]):
					second_idx = idx
					break
			var second_pick: Dictionary = remote_candidates[second_idx]
			mer_pkg = {
				"available": true,
				"firstRegionId": str(first_pick["regionId"]), "firstSiteId": str(first_pick["siteId"]), "firstOpportunity": str(first_pick["opportunity"]),
				"secondRegionId": str(second_pick["regionId"]), "secondSiteId": str(second_pick["siteId"]), "secondOpportunity": str(second_pick["opportunity"])
			}
			used_remote[str(first_pick["regionId"])] = true
			used_remote[str(second_pick["regionId"])] = true
		else:
			mer_pkg = {"available": false, "reason": "Insufficient unvisited remote landings remain for a two-station meridian survey."}
	if keel_pkg.is_empty():
		var keel_pool: Array = []
		for cand in remote_candidates:
			if not used_remote.has(str(cand["regionId"])):
				keel_pool.append(cand)
		if not keel_pool.is_empty():
			var preferred: Array = []
			for cand in keel_pool:
				if str(cand["opportunity"]) in ["ore", "crude", "saltpeter"]:
					preferred.append(cand)
			var pick_from: Array = preferred if not preferred.is_empty() else keel_pool
			var k_pick: Dictionary = pick_from[posmod(seed_val + 3, pick_from.size())]
			keel_pkg = {
				"available": true,
				"regionId": str(k_pick["regionId"]), "siteId": str(k_pick["siteId"]),
				"sourceId": KEEL087_SOURCE_PREFIX + str(k_pick["siteId"]),
				"opportunity": str(k_pick["opportunity"])
			}
			used_remote[str(k_pick["regionId"])] = true
		else:
			keel_pkg = {"available": false, "reason": "No unvisited remote landing remains for the unfinished keel slipway."}
	if lan_pkg.is_empty():
		if not frontier_candidates.is_empty():
			var l_pick: Dictionary = frontier_candidates[posmod(seed_val + 5, frontier_candidates.size())]
			lan_pkg = {
				"available": true,
				"regionId": str(l_pick["regionId"]), "siteId": str(l_pick["siteId"]),
				"portId": str(l_pick["portId"]), "faction": str(l_pick["faction"]),
				"opportunity": str(l_pick["opportunity"])
			}
		else:
			lan_pkg = {"available": false, "reason": "No unvisited frontier anchorage remains for the two-lantern range."}
	var any_available: bool = bool(mer_pkg.get("available", false)) or bool(keel_pkg.get("available", false)) or bool(lan_pkg.get("available", false))
	stories["destinations087"] = {
		"schema": 1, "bound": true, "available": any_available,
		"status": "bound_sector069" if any_available else "unavailable_visited",
		"seed": seed_val,
		"packages": {
			"broken_meridian087": mer_pkg,
			"unfinished_keel087": keel_pkg,
			"two_lantern_anchorage087": lan_pkg
		}
	}


static func destinations087(state: Dictionary) -> Dictionary:
	var stories: Dictionary = state.get("stories", {}) if state.get("stories") is Dictionary else {}
	var dest = stories.get("destinations087", null)
	return dest.duplicate(true) if dest is Dictionary else {"schema": 1, "bound": false, "available": false, "status": "unbound", "packages": {}}


static func package_available087(state: Dictionary, chain_id: String) -> bool:
	if not (chain_id in CHAINS087):
		return true
	if not state.has("sector069"):
		return false
	var stories: Dictionary = state.get("stories", {}) if state.get("stories") is Dictionary else {}
	var dest = stories.get("destinations087", null)
	if not (dest is Dictionary) or not bool(dest.get("bound", false)) or not (dest.get("packages") is Dictionary):
		return false
	var pkg = dest["packages"].get(chain_id, null)
	return pkg is Dictionary and bool(pkg.get("available", false))


static func _apply_destinations087(stories: Dictionary, base_catalog: Array) -> Array:
	var dest = stories.get("destinations087", null)
	if not (dest is Dictionary) or not bool(dest.get("bound", false)) or not (dest.get("packages") is Dictionary):
		return base_catalog
	var pkgs: Dictionary = dest["packages"]
	var out: Array = []
	for raw in base_catalog:
		if not (raw is Dictionary):
			continue
		var chain: Dictionary = raw.duplicate(true)
		var cid: String = str(chain.get("id", ""))
		if cid == "broken_meridian087" and pkgs.get(cid) is Dictionary and bool(pkgs[cid].get("available", false)):
			var s1: String = str(pkgs[cid].get("firstSiteId", "remote_01_survey"))
			var s2: String = str(pkgs[cid].get("secondSiteId", "remote_02_survey"))
			chain["startLead"] = s1
			for stage in chain.get("stages", []):
				if not (stage is Dictionary):
					continue
				stage["nextAction"] = str(stage.get("nextAction", "")).replace("remote_01_survey", s1).replace("remote_02_survey", s2)
				if stage.get("gate") is Dictionary and str(stage["gate"].get("type", "")) == "site":
					if str(stage["gate"].get("site", "")) == "remote_01_survey":
						stage["gate"]["site"] = s1
					elif str(stage["gate"].get("site", "")) == "remote_02_survey":
						stage["gate"]["site"] = s2
				for choice in stage.get("choices", []):
					if choice is Dictionary and choice.get("leads") is Array:
						var leads: Array = []
						for lid in choice["leads"]:
							leads.append(s2 if str(lid) == "remote_02_survey" else str(lid))
						choice["leads"] = leads
		elif cid == "unfinished_keel087" and pkgs.get(cid) is Dictionary and bool(pkgs[cid].get("available", false)):
			var ks: String = str(pkgs[cid].get("siteId", "remote_03_survey"))
			chain["startLead"] = ks
			for stage in chain.get("stages", []):
				if stage is Dictionary:
					stage["nextAction"] = str(stage.get("nextAction", "")).replace("remote_03_survey", ks)
				if stage is Dictionary and stage.get("gate") is Dictionary and str(stage["gate"].get("site", "")) == "remote_03_survey":
					stage["gate"]["site"] = ks
		elif cid == "two_lantern_anchorage087" and pkgs.get(cid) is Dictionary and bool(pkgs[cid].get("available", false)):
			var ls: String = str(pkgs[cid].get("siteId", "frontier_01_survey"))
			var lp: String = str(pkgs[cid].get("portId", "frontier_01_harbor_01"))
			chain["startLead"] = ls
			for stage in chain.get("stages", []):
				if not (stage is Dictionary):
					continue
				stage["nextAction"] = str(stage.get("nextAction", "")).replace("frontier_01_survey", ls).replace("frontier_01_harbor_01", lp)
				if stage.get("gate") is Dictionary:
					if str(stage["gate"].get("site", "")) == "frontier_01_survey":
						stage["gate"]["site"] = ls
					elif str(stage["gate"].get("port", "")) == "frontier_01_harbor_01":
						stage["gate"]["port"] = lp
				for choice in stage.get("choices", []):
					if choice is Dictionary and choice.get("cost") is Dictionary and str(choice["cost"].get("port", "")) == "frontier_01_harbor_01":
						choice["cost"]["port"] = lp
		out.append(chain)
	return out


static func _recovery_sites087(state: Dictionary) -> Array:
	var out: Array = []
	var rec := _record(state, "unfinished_keel087")
	if rec.is_empty():
		return out
	for lead in earned_leads(state, "unfinished_keel087"):
		if int(lead.get("level", 0)) < 3:
			continue
		var site_id: String = str(lead.get("id", ""))
		var source_id: String = KEEL087_SOURCE_PREFIX + site_id
		var row: Dictionary = lead.duplicate(true)
		row["sourceId"] = source_id
		row["sourceExists"] = false
		row["wreckIds"] = []
		row["remainingComponents"] = {}
		row["remainingStores"] = {}
		for wreck in state.get("wrecks", []):
			if not (wreck is Dictionary) or str(wreck.get("sourceId", "")) != source_id:
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


static func _outcome087(state: Dictionary, chain_id: String) -> Dictionary:
	var rec := _record(state, chain_id)
	if not bool(rec.get("done", false)):
		return {}
	var flags: Array = rec.get("flags", [])
	var title := ""
	var body := ""
	var next_action := "The expedition record is settled; its consequences remain in your journal."
	if chain_id == "broken_meridian087":
		if flags.has("meridian_public087") and flags.has("meridian_full_survey087"):
			title = "The outer meridian table is public"
			body = "Wren entered your two-station outer meridian drift table into the public coastal register: Reed +4, Compact -2, Wren +7. One finite four-kit sight passage is unlocked at Reedwater Floats for Silt Hollow, subject to actual stocks, treasury funds and a route."
			next_action = "Check Reedwater Floats for the once-only funded meridian sight-kit passage."
		elif flags.has("meridian_retained087") and flags.has("meridian_full_survey087"):
			title = "The outer meridian arc is retained"
			body = "You filed the baseline with Wren and held the outer meridian arc for Tobin's brokers: Wren -3, Tobin +5. One finite four-kit factor passage is unlocked at Brass Haven for Silt Hollow, subject to actual stocks, treasury funds and a route."
			next_action = "Check Brass Haven for the once-only funded meridian factor passage."
		elif flags.has("meridian_partial_filed087") and flags.has("meridian_turned_home087"):
			title = "The single-post meridian sight is filed"
			body = "You turned home within reserves after charting the first meridian post and filed an honest single-station sight with Wren: Reed +2, Wren +3. The farther counter-post was never claimed or revealed."
			next_action = "Single-station sight recorded; no outer charter passage was unlocked."
	elif chain_id == "unfinished_keel087":
		if flags.has("keel_ledger_forge087"):
			title = "The outer slipway ledger is signed at Anvil Dock"
			body = "You closed the builder forfeiture in Mara's Forge yard registry: Forge +4, Raiders -2, Mara +6."
		elif flags.has("keel_ledger_private087"):
			title = "The outer slipway scantlings are kept private"
			body = "You withheld the slipway scantling notes from the Forge registry for private salvage brokers: Mara -3, Cass +5."
		if flags.has("keel_recovered_paid087") and flags.has("paid_keel_source087"):
			body += " Your completed paid recovery lot from the stranded workboat cradle is recorded; remaining slipway stock stays finite."
		elif flags.has("keel_left_intact087"):
			body += " You left the heavy frame on the slipway to preserve return hold and ration margins; no salvage lot was claimed."
		elif flags.has("keel_verified_empty087"):
			body += " You verified that the surveyed, seeded slipway cradle had been stripped clean; no player recovery was claimed."
	elif chain_id == "two_lantern_anchorage087":
		if flags.has("lantern_channel_public087"):
			title = "The frontier two-lantern range is posted publicly"
			body = "After charting the headland and delivering four repair kits to brace the lower lantern frame, you posted the relit leading line as an open notice: Reed +4, Compact -2, Wren +5."
		elif flags.has("lantern_channel_bonded087"):
			title = "The frontier two-lantern range is bonded"
			body = "After charting the headland and delivering four repair kits to brace the lower lantern frame, you registered the relit range under Tobin's bonded desk: Compact +4, Reed -2, Tobin +6. One finite four-kit replacement passage is unlocked at Brass Haven for Silt Hollow."
			next_action = "Check Brass Haven for the once-only funded range-kit replacement passage."
	if title.is_empty():
		return {}
	var effects: Array = []
	for effect in state.get("stories", {}).get("consequences", []):
		if effect is Dictionary and str(effect.get("id", "")).begins_with("story:" + chain_id + ":"):
			effects.append(effect.duplicate(true))
	return {"title": title, "body": body, "nextAction": next_action, "consequences": effects}
