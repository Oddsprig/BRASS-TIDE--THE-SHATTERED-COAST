extends RefCounted
## v0.009 island exploration: deterministic persistent sites and survey progression.
## Pure data only. Root owns proximity gates, crew assignment UI, chart drawing
## and any physical recovery of resources a surveyed site merely identifies.
## State lives under state["exploration"] as plain JSON-friendly types.

const CATALOG_PATH := "res://data/island_sites.json"
const STATE_VERSION := 1
const LEVEL_UNKNOWN := 0
const LEVEL_SIGHTED := 1
const LEVEL_CHARTED := 2
const LEVEL_SURVEYED := 3
const LEVEL_NAMES := ["unknown", "sighted", "charted", "surveyed"]
const ACTION_CHART := "chart"
const ACTION_SURVEY := "survey"
# Existing campaign equation (economy.gd daily_upkeep): 0.08 food per crew per day.
const FOOD_PER_CREW_DAY := 0.08
const MAX_LOG := 60
const MAX_LEADS := 64

# Action table: target level, required level, spare crew, duration in game days,
# repair/survey kits (cargo "supplies") consumed once at begin().
const ACTIONS := {
	ACTION_CHART: {"from": LEVEL_SIGHTED, "to": LEVEL_CHARTED, "crew": 2, "days": 1.0, "supplies": 1.0},
	ACTION_SURVEY: {"from": LEVEL_CHARTED, "to": LEVEL_SURVEYED, "crew": 4, "days": 2.5, "supplies": 2.0},
}
const ACTION_ALIASES := {
	"coastal_chart": ACTION_CHART, "chart_coast": ACTION_CHART,
	"landed_survey": ACTION_SURVEY, "deep_survey": ACTION_SURVEY,
}

static var _catalog_cache: Array = []
static var _catalog_loaded := false


static func _is_num(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func _num(v, fallback: float = 0.0) -> float:
	return float(v) if _is_num(v) else fallback


static func _clean_site(raw) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var id := str(raw.get("id", ""))
	if id.is_empty() or not _is_num(raw.get("x", null)) or not _is_num(raw.get("y", null)):
		return {}
	return {
		"id": id, "name": str(raw.get("name", id)),
		"x": float(raw["x"]), "y": float(raw["y"]),
		"kind": str(raw.get("kind", "")), "region": str(raw.get("region", "")),
		"clue": str(raw.get("clue", "")), "discovery": str(raw.get("discovery", "")),
		"hazard": str(raw.get("hazard", "")), "resource": str(raw.get("resource", "")),
		"leadId": str(raw.get("leadId", "")),
	}


static func _sort_sites(list: Array) -> void:
	list.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))


static func _load_catalog() -> Array:
	if _catalog_loaded:
		return _catalog_cache.duplicate(true)
	_catalog_loaded = true
	var out: Array = []
	if FileAccess.file_exists(CATALOG_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if parsed is Dictionary and parsed.get("sites") is Array:
			for raw in parsed["sites"]:
				var site := _clean_site(raw)
				if not site.is_empty() and not out.any(func(s): return s["id"] == site["id"]):
					out.append(site)
	if out.is_empty():
		out = _fallback_catalog()
	_sort_sites(out)
	_catalog_cache = out.duplicate(true)
	return out


static func _fallback_catalog() -> Array:
	# Same authored sites as the JSON catalog; only used if the file is unreadable.
	var rows := [
		["lantern_fresh_cove", "Lantern Freshwater Cove", 1750.0, 5350.0, "freshwater_cove", "Lantern Cay", "food", "kelp_shoal_cut"],
		["kelp_shoal_cut", "Kelpback Shoal Cut", 1850.0, 2300.0, "shoal_shortcut", "Kelpback Shoal", "route", ""],
		["kelp_defended_camp", "Kelpback Toll Camp", 1400.0, 2950.0, "defended_camp", "Kelpback Shoal", "", "rust_salvage_anchorage"],
		["sawtooth_timber_stand", "Sawtooth Ironwood Stand", 2350.0, 1400.0, "timber_stand", "Sawtooth Crag", "timber", ""],
		["verdigris_salt_pans", "Verdigris Salt Pans", 3700.0, 5400.0, "salt_seam", "Verdigris Atoll", "saltpeter", ""],
		["reed_marsh_landing", "Middle Marsh Landing", 5050.0, 5250.0, "marsh_landing", "Southern Marshes", "food", "fen_sheltered_inlet"],
		["cinder_ore_seam", "Cinder Crown Ore Seam", 4650.0, 2700.0, "ore_seam", "Cinder Crown", "ore", ""],
		["cinder_workshop_ruin", "Cinder Crown Workshop Ruin", 5800.0, 2700.0, "workshop_ruin", "Cinder Crown", "workshop", "oilstone_seep_terrace"],
		["fen_sheltered_inlet", "Kettle Fen Sheltered Inlet", 6050.0, 4400.0, "sheltered_inlet", "Kettle Fen Isle", "route", ""],
		["oilstone_seep_terrace", "Oilstone Seep Terrace", 7300.0, 1600.0, "oil_seep", "Oilstone Bluff", "crude", ""],
		["naphtha_sulfur_vents", "Naphtha Sulfur Vents", 8050.0, 1750.0, "sulfur_vents", "Oilstone Bluff", "sulfur", ""],
		["middle_chart_rock", "Middle Sea Chart Rock", 3200.0, 3450.0, "chart_fragment", "Middle Sea", "", "shatter_wreck_field"],
		["rust_salvage_anchorage", "Rust Salvage Anchorage", 8350.0, 3200.0, "salvage_anchorage", "Shatter Coast", "supplies", "shatter_wreck_field"],
		["shatter_wreck_field", "Shatter Wreck Field", 8450.0, 4000.0, "wreck_field", "Shatter Coast", "supplies", ""],
	]
	var out: Array = []
	for r in rows:
		out.append({"id": r[0], "name": r[1], "x": r[2], "y": r[3], "kind": r[4], "region": r[5],
			"clue": "", "discovery": "", "hazard": "", "resource": r[6], "leadId": r[7]})
	return out


static func _catalog(state: Dictionary) -> Array:
	var ex: Dictionary = state.get("exploration", {}) if state.get("exploration") is Dictionary else {}
	var stored = ex.get("catalog", null)
	if stored is Array and not stored.is_empty():
		return stored
	return _load_catalog()


static func _site_record(ex: Dictionary, site_id: String) -> Dictionary:
	var progress: Dictionary = ex.get("sites", {}) if ex.get("sites") is Dictionary else {}
	var rec = progress.get(site_id, null)
	return rec if rec is Dictionary else {"level": LEVEL_UNKNOWN, "rewarded": false}


static func _merged(state: Dictionary, site: Dictionary) -> Dictionary:
	var ex: Dictionary = state.get("exploration", {}) if state.get("exploration") is Dictionary else {}
	var rec := _site_record(ex, str(site["id"]))
	var level := clampi(int(rec.get("level", LEVEL_UNKNOWN)), LEVEL_UNKNOWN, LEVEL_SURVEYED)
	var out := site.duplicate(true)
	out["level"] = level
	out["levelName"] = LEVEL_NAMES[level]
	out["rewarded"] = bool(rec.get("rewarded", false))
	return out


static func catalog_site(state: Dictionary, site_id: String) -> Dictionary:
	for site in _catalog(state):
		if site is Dictionary and str(site.get("id", "")) == site_id:
			return site
	return {}


static func _log(ex: Dictionary, text: String) -> void:
	var log: Array = ex.get("log", []) if ex.get("log") is Array else []
	log.append(text)
	while log.size() > MAX_LOG:
		log.pop_front()
	ex["log"] = log


# Creates/normalizes state["exploration"]. Catalog priority: world["ISLAND_SITES"]
# (root-supplied), then the JSON file read once, then the built-in fallback.
# The resolved catalog is copied into state so saves keep stable identities even
# if the data file changes later. Returns the exploration sub-state.
static func ensure(state: Dictionary, world: Dictionary = {}) -> Dictionary:
	var catalog: Array = []
	if world.get("ISLAND_SITES") is Array:
		for raw in world["ISLAND_SITES"]:
			var site := _clean_site(raw)
			if not site.is_empty() and not catalog.any(func(s): return s["id"] == site["id"]):
				catalog.append(site)
		_sort_sites(catalog)
	if catalog.is_empty():
		catalog = _load_catalog()
	var ex: Dictionary = state.get("exploration", {}) if state.get("exploration") is Dictionary else {}
	ex["version"] = STATE_VERSION
	if not (ex.get("catalog") is Array) or (ex["catalog"] as Array).is_empty():
		ex["catalog"] = catalog.duplicate(true)
	if not (ex.get("sites") is Dictionary):
		ex["sites"] = {}
	# Drop progress for ids absent from the stored catalog; clamp levels.
	var known := {}
	for site in ex["catalog"]:
		if site is Dictionary:
			known[str(site.get("id", ""))] = true
	for id in (ex["sites"] as Dictionary).keys():
		if not known.has(str(id)):
			ex["sites"].erase(id)
		elif ex["sites"][id] is Dictionary:
			var rec: Dictionary = ex["sites"][id]
			rec["level"] = clampi(int(rec.get("level", LEVEL_UNKNOWN)), LEVEL_UNKNOWN, LEVEL_SURVEYED)
			rec["rewarded"] = bool(rec.get("rewarded", false))
	if not (ex.get("assignment") is Dictionary):
		ex["assignment"] = {}
	if not (ex.get("leads") is Array):
		ex["leads"] = []
	if not (ex.get("log") is Array):
		ex["log"] = []
	state["exploration"] = ex
	return ex


# All catalog sites merged with persistent progress, sorted by id. Deep copies.
static func sites(state: Dictionary) -> Array:
	ensure(state)
	var out: Array = []
	for site in _catalog(state):
		if site is Dictionary:
			out.append(_merged(state, site))
	_sort_sites(out)
	return out


static func _position_xy(position) -> Array:
	if position is Dictionary and _is_num(position.get("x", null)) and _is_num(position.get("y", null)):
		return [float(position["x"]), float(position["y"])]
	if position is Vector2 and is_finite(position.x) and is_finite(position.y):
		return [float(position.x), float(position.y)]
	if position is Array and position.size() >= 2 and _is_num(position[0]) and _is_num(position[1]):
		return [float(position[0]), float(position[1])]
	return []


# Sights every unknown site within radius of position. Returns only newly
# sighted merged sites; repeat calls return [] and never downgrade progress.
static func discover_near(state: Dictionary, position, radius) -> Array:
	var ex := ensure(state)
	var xy := _position_xy(position)
	var r := _num(radius, -1.0)
	if xy.size() != 2 or r < 0.0:
		return []
	var found: Array = []
	for site in _catalog(state):
		if not (site is Dictionary):
			continue
		var dx: float=float(site["x"])-float(xy[0])
		var dy: float=float(site["y"])-float(xy[1])
		if sqrt(dx * dx + dy * dy) > r:
			continue
		var id := str(site["id"])
		var rec := _site_record(ex, id)
		if int(rec.get("level", LEVEL_UNKNOWN)) >= LEVEL_SIGHTED:
			continue
		rec["level"] = LEVEL_SIGHTED
		ex["sites"][id] = rec
		_log(ex, "Sighted %s: %s" % [str(site["name"]), str(site.get("clue", ""))])
		found.append(_merged(state, site))
	_sort_sites(found)
	return found


# Real spare hands: living, non-mothballed boats above their minimum crew.
# Boats stored in port (storedPort nonempty) contribute nobody, matching the
# traveling-fleet rule root applies in v0.008. Root remains the authority on
# availability; this module only refuses to invent crew that are not there.
static func spare_crew(state: Dictionary) -> int:
	var spare := 0
	var fleet = state.get("fleet", null)
	if not (fleet is Array):
		return 0
	for boat in fleet:
		if not (boat is Dictionary) or bool(boat.get("sunk", false)) or bool(boat.get("mothballed", false)):
			continue
		if str(boat.get("storedPort", "")) != "":
			continue
		spare += maxi(0,int(_num(boat.get("crew",0)))-ceili(_num(boat.get("wounded",0)))-int(_num(boat.get("crewMin",0))))
	return spare


static func _action_key(action) -> String:
	var key := str(action)
	return str(ACTION_ALIASES.get(key, key))


# Read-only cost/eligibility quote. Never mutates cargo, crew or progress
# (beyond ensure() normalization). Food cost uses the existing campaign rate:
# FOOD_PER_CREW_DAY * assigned crew * days. Supplies are cargo "supplies" kits.
static func quote(state: Dictionary, site_id: String, action) -> Dictionary:
	ensure(state)
	var key := _action_key(action)
	var site := catalog_site(state, site_id)
	var base := {"ok": false, "siteId": site_id, "action": key, "message": ""}
	if site.is_empty():
		base["message"] = "Unknown site."
		return base
	if not ACTIONS.has(key):
		base["message"] = "Unknown exploration action."
		return base
	var spec: Dictionary = ACTIONS[key]
	var ex: Dictionary = state["exploration"]
	var level := int(_site_record(ex, site_id).get("level", LEVEL_UNKNOWN))
	var crew := int(spec["crew"])
	var days := float(spec["days"])
	var food := snappedf(FOOD_PER_CREW_DAY * float(crew) * days, 0.01)
	var cargo: Dictionary = state.get("cargo", {}) if state.get("cargo") is Dictionary else {}
	var have_food := maxf(0.0, _num(cargo.get("food", 0.0)))
	var have_supplies := maxf(0.0, _num(cargo.get("supplies", 0.0)))
	for boat in state.get("fleet",[]):
		if not boat.get("sunk",false) and not boat.get("mothballed",false) and str(boat.get("storedPort","")).is_empty():have_supplies+=maxf(0,_num(boat.get("supplies",0)))
	var spare := spare_crew(state)
	base.merge({
		"siteName": str(site["name"]), "level": level, "levelName": LEVEL_NAMES[level],
		"targetLevel": int(spec["to"]), "crewNeeded": crew, "spareCrew": spare,
		"days": days, "food": food, "supplies": float(spec["supplies"]),
		"haveFood": have_food, "haveSupplies": have_supplies,
		"hazard": str(site.get("hazard", "")), "resource": str(site.get("resource", "")),
	}, true)
	var busy: Dictionary = ex.get("assignment", {})
	if level < int(spec["from"]):
		base["message"] = "Site must be %s first." % LEVEL_NAMES[int(spec["from"])]
	elif level >= int(spec["to"]):
		base["message"] = "Already %s; surveys do not repeat." % LEVEL_NAMES[int(spec["to"])]
	elif not busy.is_empty():
		base["message"] = "A survey party is already assigned to %s." % str(busy.get("siteId", "another site"))
	elif spare < crew:
		base["message"] = "Needs %d spare crew above boat minimums; %d available." % [crew, spare]
	elif have_food < food:
		base["message"] = "Needs %.2f food in cargo; %.2f aboard." % [food, have_food]
	elif have_supplies < float(spec["supplies"]):
		base["message"] = "Needs %.0f supply kits in cargo or working racks; %.2f aboard." % [float(spec["supplies"]), have_supplies]
	else:
		base["ok"] = true
		base["message"] = "Ready: %d crew, %.1f days, %.2f food, %.0f supply kits." % [crew, days, food, float(spec["supplies"])]
	return base


# Starts the single queued assignment. Consumes quoted cargo exactly once and
# records the crew reservation; boat crew numbers are root's to adjust, so no
# sailors are created, removed or double-counted here.
static func begin(state: Dictionary, site_id: String, action) -> Dictionary:
	var q := quote(state, site_id, action)
	if not bool(q["ok"]):
		return q
	var cargo: Dictionary = state.get("cargo", {}) if state.get("cargo") is Dictionary else {}
	cargo["food"] = maxf(0.0, _num(cargo.get("food", 0.0)) - float(q["food"]))
	var left: float=float(q.supplies)
	var cargo_use: float=minf(left,maxf(0,_num(cargo.get("supplies",0))))
	cargo.supplies=maxf(0,_num(cargo.get("supplies",0))-cargo_use)
	left-=cargo_use
	for boat in state.get("fleet",[]):
		if boat.get("sunk",false) or boat.get("mothballed",false) or not str(boat.get("storedPort","")).is_empty():continue
		var use: float=minf(left,maxf(0,_num(boat.get("supplies",0))))
		boat.supplies=maxf(0,_num(boat.get("supplies",0))-use)
		left-=use
		if left<=0.00001:break
	state["cargo"] = cargo
	var ex: Dictionary = state["exploration"]
	ex["assignment"] = {
		"siteId": site_id, "action": str(q["action"]), "targetLevel": int(q["targetLevel"]),
		"crewReserved": int(q["crewNeeded"]), "daysTotal": float(q["days"]),
		"daysDone": 0.0, "foodSpent": float(q["food"]), "suppliesSpent": float(q["supplies"]),
	}
	_log(ex, "%s party landed at %s (%d crew, %.1f days)." % [str(q["action"]).capitalize(), str(q["siteName"]), int(q["crewNeeded"]), float(q["days"])])
	var out := q.duplicate(true)
	out["assignment"] = (ex["assignment"] as Dictionary).duplicate(true)
	out["message"] = "Survey party assigned to %s." % str(q["siteName"])
	return out


static func _add_lead(ex: Dictionary, from_site: Dictionary) -> Dictionary:
	var lead_id := str(from_site.get("leadId", ""))
	if lead_id.is_empty():
		return {}
	var leads: Array = ex.get("leads", [])
	var lead_key := "%s->%s" % [str(from_site["id"]), lead_id]
	for lead in leads:
		if lead is Dictionary and str(lead.get("id", "")) == lead_key:
			return {}
	var entry := {"id": lead_key, "fromSite": str(from_site["id"]), "toSite": lead_id,
		"kind": str(from_site.get("kind", "")), "resource": str(from_site.get("resource", "")), "claimed": false}
	leads.append(entry)
	while leads.size() > MAX_LEADS:
		leads.pop_front()
	ex["leads"] = leads
	return entry


# Advances the active assignment by game days. Returns completion events only;
# partial progress returns []. Completion raises the level exactly once, and a
# surveyed site grants its knowledge/lead record exactly once (rewarded flag).
# No coins, goods or boats are created: resource/route/workshop findings are
# opportunities recorded on the site and in leads for root to act on.
static func advance(state: Dictionary, days) -> Array:
	var ex := ensure(state)
	var step := _num(days, 0.0)
	var assignment: Dictionary = ex.get("assignment", {}) if ex.get("assignment") is Dictionary else {}
	if step <= 0.0 or assignment.is_empty():
		return []
	assignment["daysDone"] = minf(float(assignment.get("daysTotal", 0.0)),
		maxf(0.0, _num(assignment.get("daysDone", 0.0))) + step)
	ex["assignment"] = assignment
	if float(assignment["daysDone"]) < float(assignment.get("daysTotal", 0.0)):
		return []
	var site_id := str(assignment.get("siteId", ""))
	var site := catalog_site(state, site_id)
	ex["assignment"] = {}
	if site.is_empty():
		return []
	var rec := _site_record(ex, site_id)
	var target := clampi(int(assignment.get("targetLevel", LEVEL_UNKNOWN)), LEVEL_SIGHTED, LEVEL_SURVEYED)
	if int(rec.get("level", LEVEL_UNKNOWN)) >= target:
		return []  # already settled elsewhere; never settle twice
	rec["level"] = target
	var events: Array = []
	var event := {"kind": "survey_complete", "siteId": site_id, "siteName": str(site["name"]),
		"level": target, "levelName": LEVEL_NAMES[target],
		"discovery": str(site.get("discovery", "")), "resource": str(site.get("resource", "")),
		"leadId": str(site.get("leadId", ""))}
	if target == LEVEL_SURVEYED and not bool(rec.get("rewarded", false)):
		rec["rewarded"] = true
		event["lead"] = _add_lead(ex, site)
	elif target == LEVEL_CHARTED:
		event["lead"] = _add_lead(ex, site)
	ex["sites"][site_id] = rec
	_log(ex, "%s is now %s." % [str(site["name"]), LEVEL_NAMES[target]])
	events.append(event)
	return events


# Convenience for root/UI: current assignment (deep copy) or {}.
static func assignment(state: Dictionary) -> Dictionary:
	ensure(state)
	var ex: Dictionary = state["exploration"]
	var current = ex.get("assignment", {})
	return current.duplicate(true) if current is Dictionary else {}
