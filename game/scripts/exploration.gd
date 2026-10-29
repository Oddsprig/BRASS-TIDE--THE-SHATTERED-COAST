extends RefCounted
## v0.009 island exploration: deterministic persistent sites and survey progression.
## Pure data only. Root owns proximity gates, crew assignment UI, chart drawing
## and any physical recovery of resources a surveyed site merely identifies.
## State lives under state["exploration"] as plain JSON-friendly types.

const CATALOG_PATH := "res://data/island_sites.json"
const WorldIdentity = preload("res://scripts/ocean_travel066.gd")
const HOME_REGION := "shatter_coast"
const REMOTE_REGION := "glasswind_keys"
const REMOTE_IDS := ["glasswind_west_marker", "glasswind_crown_log", "glasswind_south_wreck"]
const WORK_RADIUS := 180.0
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
	return (v is int or v is float) and not v is bool and is_finite(float(v))


static func _num(v, fallback: float = 0.0) -> float:
	return float(v) if _is_num(v) else fallback


static func current_region(state: Dictionary) -> String:
	if not state.has("world064"):
		return HOME_REGION
	var identity = state.get("world064")
	if not WorldIdentity.same_world(identity, identity):
		return ""
	return str(identity["regionId"]) if identity["layer"] in ["home", "local"] else ""


static func _site_region(site: Dictionary) -> String:
	if not site.has("regionId"):
		return HOME_REGION
	var region = site.get("regionId")
	return region if region is String and region in [HOME_REGION, REMOTE_REGION] else ""


static func _remote_stationary(state: Dictionary, site: Dictionary) -> bool:
	var xy := _position_xy(state.get("position"))
	var path = state.get("path")
	if xy.size() != 2 or not path is Array or not path.is_empty():
		return false
	var dx: float = float(xy[0]) - float(site["x"])
	var dy: float = float(xy[1]) - float(site["y"])
	return dx * dx + dy * dy <= WORK_RADIUS * WORK_RADIUS


static func _clean_site(raw) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var id := str(raw.get("id", ""))
	if id.is_empty() or not _is_num(raw.get("x", null)) or not _is_num(raw.get("y", null)):
		return {}
	var out := {
		"id": id, "name": str(raw.get("name", id)),
		"x": float(raw["x"]), "y": float(raw["y"]),
		"kind": str(raw.get("kind", "")), "region": str(raw.get("region", "")),
		"clue": str(raw.get("clue", "")), "discovery": str(raw.get("discovery", "")),
		"hazard": str(raw.get("hazard", "")), "resource": str(raw.get("resource", "")),
		"leadId": str(raw.get("leadId", "")),
	}
	if raw.has("regionId"):
		if _site_region(raw).is_empty():
			return {}
		out["regionId"] = raw["regionId"]
	return out


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
	# Same three identities/anchors as the authored remote catalog; no reward seed.
	var remote_rows := [
		[REMOTE_IDS[0], "Westglass Bearing Stones", 1360.0, 1380.0, "bearing_marker", "Westglass Isle", "Pale stones stand above a narrow landing.", "The stones give an eastward bearing toward a raised signal ridge.", REMOTE_IDS[1]],
		[REMOTE_IDS[1], "Windglass Keeper's Log", 2780.0, 1540.0, "signal_log", "Windglass Crown", "A broken signal frame stands on the ridge.", "A keeper's log gives a south-west bearing toward a split stern.", REMOTE_IDS[2]],
		[REMOTE_IDS[2], "Longglass Supply Wreck", 1820.0, 1640.0, "expedition_cache", "Longglass Key", "Split timbers interrupt the pale surf.", "A collapsed supply coaster holds finite surviving stores. Recovery needs a separate working party and hold space.", ""],
	]
	for r in remote_rows:
		out.append({"id": r[0], "name": r[1], "x": r[2], "y": r[3], "kind": r[4], "region": r[5],
			"regionId": REMOTE_REGION, "clue": r[6], "discovery": r[7], "hazard": "Swell and loose timbers make the landing slow.", "resource": "supplies" if r[0] == REMOTE_IDS[2] else "", "leadId": r[8]})
	return out


static func _remote_catalog() -> Array:
	var out: Array = []
	for site in _load_catalog():
		if site["id"] in REMOTE_IDS:
			out.append(site)
	return out


static func _whole(value, low: int, high: int) -> bool:
	return _is_num(value) and float(value) >= low and float(value) <= high and float(value) == floorf(float(value))


# This gate reads the RAW save, before ensure can clamp/coerce/append anything.
# General fleet/custody/economy validation and publication remain B's boundary.
static func validate_remote067(saved: Dictionary) -> String:
	if saved.has("world064") and not WorldIdentity.same_world(saved["world064"], saved["world064"]):
		return "Invalid exploration world identity."
	if not saved.has("exploration"):
		return ""
	var raw = saved["exploration"]
	if not raw is Dictionary:
		return "Invalid exploration book."
	var ex: Dictionary = raw
	if not _whole(ex.get("version"), STATE_VERSION, STATE_VERSION) or not ex.get("catalog") is Array or not ex.get("sites") is Dictionary or not ex.get("assignment") is Dictionary:
		return "Invalid exploration catalog/progress/assignment."
	if ex["catalog"].size() > 128 or ex["sites"].size() > 128:
		return "Oversized exploration book."
	for key in ["leads", "log"]:
		if not ex.get(key) is Array or ex[key].size() > 128:
			return "Invalid exploration history."
	var authored: Dictionary = {}
	for site in _remote_catalog():
		authored[site["id"]] = site
	var known: Dictionary = {}
	for site in ex["catalog"]:
		if not site is Dictionary or not site.get("id") is String or site["id"].is_empty() or known.has(site["id"]):
			return "Invalid or duplicate exploration site."
		var region := _site_region(site)
		if region.is_empty() or not _is_num(site.get("x")) or not _is_num(site.get("y")):
			return "Invalid exploration region/location."
		if (site["id"] in REMOTE_IDS) != (region == REMOTE_REGION):
			return "Exploration site and region disagree."
		var width: float = 4200.0 if region == REMOTE_REGION else 10400.0
		var height: float = 3000.0 if region == REMOTE_REGION else 7200.0
		if float(site["x"]) < 0.0 or float(site["y"]) < 0.0 or float(site["x"]) > width or float(site["y"]) > height:
			return "Exploration location is outside its region."
		for key in ["name", "kind", "region", "clue", "discovery", "hazard", "resource", "leadId"]:
			if not site.get(key) is String:
				return "Invalid exploration text."
		if region == REMOTE_REGION:
			var canonical: Dictionary = authored.get(site["id"], {})
			if canonical.is_empty() or float(site["x"]) != float(canonical["x"]) or float(site["y"]) != float(canonical["y"]):
				return "Remote exploration anchor is not authoritative."
			for key in ["name", "kind", "region", "clue", "discovery", "hazard", "resource", "leadId"]:
				if site[key] != canonical[key]:
					return "Remote exploration catalog does not match its authored site."
		known[site["id"]] = site
	for site in known.values():
		var next_id: String = site["leadId"]
		if not next_id.is_empty() and (not known.has(next_id) or _site_region(known[next_id]) != _site_region(site)):
			return "Exploration lead crosses or leaves its catalog."
	for id in ex["sites"]:
		var rec = ex["sites"][id]
		if not id is String or not known.has(id) or not rec is Dictionary or not _whole(rec.get("level"), LEVEL_UNKNOWN, LEVEL_SURVEYED) or not rec.get("rewarded") is bool:
			return "Invalid exploration progress."
		if id in REMOTE_IDS and rec["rewarded"] != (rec["level"] == LEVEL_SURVEYED):
			return "Remote exploration finding disagrees with progress."
	if int(_site_record(ex, REMOTE_IDS[2]).get("level", 0)) == LEVEL_SURVEYED and not _remote_prerequisites(ex):
		return "Remote final survey lacks its earlier findings."
	for lead in ex["leads"]:
		if not lead is Dictionary:
			return "Invalid exploration lead."
		if lead.get("fromSite") in REMOTE_IDS or lead.get("toSite") in REMOTE_IDS:
			var from_id = lead.get("fromSite")
			if not from_id is String or not known.has(from_id) or from_id not in REMOTE_IDS or known[from_id]["leadId"] != lead.get("toSite") or int(_site_record(ex, from_id).get("level", 0)) != LEVEL_SURVEYED:
				return "Remote exploration lead is unearned."
			if lead.get("id") != "%s->%s" % [from_id, lead["toSite"]] or not lead.get("claimed") is bool:
				return "Invalid remote exploration lead identity."
	return _validate_assignment067(saved, ex, known)


static func _remote_prerequisites(ex: Dictionary) -> bool:
	return int(_site_record(ex, REMOTE_IDS[0]).get("level", 0)) == LEVEL_SURVEYED and int(_site_record(ex, REMOTE_IDS[1]).get("level", 0)) == LEVEL_SURVEYED


static func _validate_assignment067(saved: Dictionary, ex: Dictionary, known: Dictionary) -> String:
	var a: Dictionary = ex["assignment"]
	if a.is_empty():
		return ""
	var id = a.get("siteId")
	if not id is String or not known.has(id):
		return "Unknown exploration assignment site."
	var site: Dictionary = known[id]
	var region := _site_region(site)
	var identity = a.get("world064", {"schema": 1, "layer": "home", "regionId": HOME_REGION})
	var current = saved.get("world064", {"schema": 1, "layer": "home", "regionId": HOME_REGION})
	if region != current_region(saved) or not WorldIdentity.same_world(identity, current):
		return "Exploration assignment belongs to another world."
	if region != REMOTE_REGION:
		return "" # Existing home accounting remains with the original validator.
	if not a.has("world064") or not _remote_stationary(saved, site):
		return "Remote party needs its local identity and stopped landing anchor."
	var action = a.get("action")
	if not action is String or not ACTIONS.has(action):
		return "Invalid remote exploration action."
	var spec: Dictionary = ACTIONS[action]
	if not _whole(a.get("targetLevel"), int(spec["to"]), int(spec["to"])) or not _whole(a.get("crewReserved"), int(spec["crew"]), int(spec["crew"])):
		return "Invalid remote exploration target/reservation."
	if int(_site_record(ex, id).get("level", 0)) != int(spec["from"]) or (id == REMOTE_IDS[2] and action == ACTION_SURVEY and not _remote_prerequisites(ex)):
		return "Remote party lacks the required exploration progress."
	for key in ["daysTotal", "daysDone", "foodSpent", "suppliesSpent"]:
		if not _is_num(a.get(key)) or float(a[key]) < 0.0 or float(a[key]) > 1000.0:
			return "Invalid remote exploration accounting."
	if float(a["daysTotal"]) <= 0.0 or float(a["daysDone"]) >= float(a["daysTotal"]):
		return "Invalid remote exploration duration."
	if float(a["suppliesSpent"]) != float(spec["supplies"]) or not is_equal_approx(float(a["foodSpent"]), snappedf(FOOD_PER_CREW_DAY * float(a["crewReserved"]) * float(a["daysTotal"]), 0.01)):
		return "Invalid remote exploration stores."
	var credit = saved.get("surveyFoodCredit", 0.0)
	if not _is_num(credit) or float(credit) < 0.0 or float(credit) > float(a["foodSpent"]) + 0.0000001 or not saved.get("fleet") is Array:
		return "Invalid remote party food credit/fleet."
	var reserved: int = 0
	for boat in saved["fleet"]:
		if not boat is Dictionary or not _whole(boat.get("shoreCrew", 0), 0, 1000):
			return "Invalid remote shore crew reservation."
		var shore: int = int(boat.get("shoreCrew", 0))
		if shore == 0:
			continue
		if boat.get("sunk", false) or boat.get("mothballed", false) or not str(boat.get("storedPort", "")).is_empty():
			return "Inactive boats cannot reserve remote shore crew."
		for key in ["crew", "wounded", "crewMin"]:
			if not _is_num(boat.get(key)) or float(boat[key]) < 0.0:
				return "Invalid remote party crew capacity."
		if shore > int(boat["crew"]) - ceili(float(boat["wounded"])) - int(boat["crewMin"]):
			return "Remote party exceeds able spare sailors."
		reserved += shore
	if reserved != int(a["crewReserved"]):
		return "Remote shore sailors do not match the assignment."
	return ""


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
	# Old v1 catalogs are frozen. Extend only the three new authored identities;
	# existing home rows, records, assignment and leads remain in place.
	for site in _remote_catalog():
		var remote_id: String = site["id"]
		if not ex["catalog"].any(func(s): return s is Dictionary and s.get("id") == remote_id):
			ex["catalog"].append(site.duplicate(true))
		if not ex["sites"].has(remote_id):
			ex["sites"][remote_id] = {"level": LEVEL_UNKNOWN, "rewarded": false}
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


static func _visible_site(state: Dictionary, site: Dictionary) -> Dictionary:
	if _site_region(site) != current_region(state):
		return {}
	var ex: Dictionary = state.get("exploration", {}) if state.get("exploration") is Dictionary else {}
	var level: int = clampi(int(_site_record(ex, str(site["id"])).get("level", LEVEL_UNKNOWN)), LEVEL_UNKNOWN, LEVEL_SURVEYED)
	if level == LEVEL_UNKNOWN:
		return {}
	var out := {"id": str(site["id"]), "regionId": _site_region(site),
		"x": float(site["x"]), "y": float(site["y"]), "level": level, "levelName": LEVEL_NAMES[level],
		"name": "Uncharted shore landmark" if level == LEVEL_SIGHTED else str(site["name"]), "clue": str(site.get("clue", ""))}
	if level >= LEVEL_CHARTED:
		out["hazard"] = str(site.get("hazard", ""))
	if level >= LEVEL_SURVEYED:
		out["discovery"] = str(site.get("discovery", ""))
		out["resource"] = str(site.get("resource", ""))
		var next := catalog_site(state, str(site.get("leadId", "")))
		if not next.is_empty() and _site_region(next) == _site_region(site) and int(_site_record(ex, str(next["id"])).get("level", LEVEL_UNKNOWN)) >= LEVEL_SIGHTED:
			out["leadId"] = str(next["id"])
	return out


# Render/UI boundary: never ensure/normalize the caller or expose level-zero rows.
static func visible_sites(state: Dictionary) -> Array:
	if current_region(state).is_empty():
		return []
	var out: Array = []
	for site in _catalog(state):
		if site is Dictionary:
			var dto := _visible_site(state, site)
			if not dto.is_empty():
				out.append(dto)
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
	var region := current_region(state)
	if xy.size() != 2 or r < 0.0 or region.is_empty():
		return []
	var found: Array = []
	for site in _catalog(state):
		if not (site is Dictionary) or _site_region(site) != region:
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
		var observed := _visible_site(state, site) if region == REMOTE_REGION else _merged(state, site)
		_log(ex, "Sighted %s: %s" % [str(observed["name"]), str(observed.get("clue", ""))])
		found.append(observed)
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
		spare += maxi(0,int(_num(boat.get("crew",0)))-ceili(_num(boat.get("wounded",0)))-int(_num(boat.get("crewMin",0)))-int(_num(boat.get("shoreCrew",0))))
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
	var region := current_region(state)
	if site.is_empty() or region.is_empty() or _site_region(site) != region:
		base["message"] = "Unknown site."
		return base
	var ex: Dictionary = state["exploration"]
	var level := int(_site_record(ex, site_id).get("level", LEVEL_UNKNOWN))
	var remote: bool = region == REMOTE_REGION
	if remote and level == LEVEL_UNKNOWN:
		base["message"] = "Unknown site."
		return base
	if not ACTIONS.has(key):
		base["message"] = "Unknown exploration action."
		return base
	var spec: Dictionary = ACTIONS[key]
	var crew := int(spec["crew"])
	var survey_factor: float=1.0
	for boat in state.get("fleet",[]):
		if not boat.get("sunk",false) and not boat.get("mothballed",false) and str(boat.get("storedPort","")).is_empty() and float(boat.get("crew",0))-float(boat.get("wounded",0))-float(boat.get("shoreCrew",0))>float(boat.get("crewMin",1)):survey_factor=maxf(survey_factor,float(boat.get("spec",{}).get("surveyFactor",1)))
	var days := float(spec["days"])/survey_factor
	var food := snappedf(FOOD_PER_CREW_DAY * float(crew) * days, 0.01)
	var cargo: Dictionary = state.get("cargo", {}) if state.get("cargo") is Dictionary else {}
	var have_food := maxf(0.0, _num(cargo.get("food", 0.0)))
	var have_supplies := maxf(0.0, _num(cargo.get("supplies", 0.0)))
	for boat in state.get("fleet",[]):
		if not boat.get("sunk",false) and not boat.get("mothballed",false) and str(boat.get("storedPort","")).is_empty():have_supplies+=maxf(0,_num(boat.get("supplies",0)))
	var spare := spare_crew(state)
	base.merge({
		"siteName": "Uncharted shore landmark" if remote and level == LEVEL_SIGHTED else str(site["name"]), "level": level, "levelName": LEVEL_NAMES[level],
		"targetLevel": int(spec["to"]), "crewNeeded": crew, "spareCrew": spare,
		"days": days, "food": food, "supplies": float(spec["supplies"]),
		"haveFood": have_food, "haveSupplies": have_supplies,
		"hazard": str(site.get("hazard", "")) if not remote or level >= LEVEL_CHARTED else "",
		"resource": str(site.get("resource", "")) if not remote or level >= LEVEL_SURVEYED else "",
	}, true)
	var busy: Dictionary = ex.get("assignment", {})
	if remote and not _remote_stationary(state, site):
		base["message"] = "Stop the fleet within 180 water units of the observed landing first."
	elif remote and site_id == REMOTE_IDS[2] and key == ACTION_SURVEY and not _remote_prerequisites(ex):
		base["message"] = "Survey the other two landings and connect their bearings first."
	elif level < int(spec["from"]):
		base["message"] = "Site must be %s first." % LEVEL_NAMES[int(spec["from"])]
	elif level >= int(spec["to"]):
		base["message"] = "Already %s; surveys do not repeat." % LEVEL_NAMES[int(spec["to"])]
	elif not busy.is_empty():
		base["message"] = "A shore party is already assigned; recall it before another landing." if remote else "A survey party is already assigned to %s." % str(busy.get("siteId", "another site"))
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
	if current_region(state) == REMOTE_REGION:
		ex["assignment"]["world064"] = {"schema": 1, "layer": "local", "regionId": REMOTE_REGION}
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
	var site_id := str(assignment.get("siteId", ""))
	var site := catalog_site(state, site_id)
	var region := current_region(state)
	if site.is_empty() or region.is_empty() or _site_region(site) != region:
		return []
	if region == REMOTE_REGION:
		if not WorldIdentity.same_world(assignment.get("world064"), state.get("world064")) or not _remote_stationary(state, site):
			return []
	elif assignment.has("world064") and not WorldIdentity.same_world(assignment["world064"], state.get("world064", {"schema": 1, "layer": "home", "regionId": HOME_REGION})):
		return []
	assignment["daysDone"] = minf(float(assignment.get("daysTotal", 0.0)),
		maxf(0.0, _num(assignment.get("daysDone", 0.0))) + step)
	ex["assignment"] = assignment
	if float(assignment["daysDone"]) < float(assignment.get("daysTotal", 0.0)):
		return []
	ex["assignment"] = {}
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
	if region == REMOTE_REGION:
		ex["sites"][site_id] = rec
		var dto := _visible_site(state, site)
		event["regionId"] = region
		event["discovery"] = str(dto.get("discovery", ""))
		event["resource"] = str(dto.get("resource", ""))
		event["leadId"] = str(dto.get("leadId", ""))
		event["lead"] = {}
		if target == LEVEL_SURVEYED and not bool(rec.get("rewarded", false)):
			rec["rewarded"] = true
			var lead := _add_lead(ex, site)
			if not str(dto.get("leadId", "")).is_empty():
				event["lead"] = lead.duplicate(true)
	elif target == LEVEL_SURVEYED and not bool(rec.get("rewarded", false)):
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
