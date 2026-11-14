extends RefCounted
## Main-thread painter, region/approach/contact picker, and CoastArt050 cache adapter for v0.064-v0.069.
## Consumes one OceanWorld064 view (legacy two coasts, or all 48 generated coasts) and separate read-only views.
## Core.sector_view069 is politics, services, and earned sites only. It is not a second atlas.
## Owns Open Ocean and local coastal drawing; home campaign drawing stays on Chart.

const CoastArt050 = preload("res://scripts/coast_art050.gd")
const NauticalArt = preload("res://scripts/nautical_art.gd")
const FleetArt054 = preload("res://scripts/campaign_fleet_art054.gd")
const LandmarkArt054 = preload("res://scripts/campaign_landmark_art054.gd")

const GOLD := Color("dfbd7d")
const FOAM := Color("95cabc")
const ENEMY := Color("e8947a")
const FRIEND := Color("8fc6b4")
const FOG_TINT := Color("9bb8bd")
const SQUALL_TINT := Color("d6a86c")
const CURRENT_TINT := Color("76c2b4")
const VALID_APPROACH_IDS: Array = ["north", "south"]
const HOME_REGION_ID: String = "shatter_coast"
const GLASSWIND_REGION_ID: String = "glasswind_keys"
const OCEAN_REGION_ID: String = "open_ocean"
const LEGACY_REGION_COUNT: int = 2
const GENERATED_REGION_COUNT: int = 48
const GENERATED_OCEAN_WIDTH: float = 12800.0
const GENERATED_OCEAN_HEIGHT: float = 8400.0
const KNOWN_OWNERSHIP: Array = ["single", "mixed", "neutral", "contested", "allied"]
const FACTION_COLOR := {
	"compact": Color("2f80ed"),
	"forge": Color("d97706"),
	"reed": Color("10b981"),
	"raiders": Color("ef4444")
}
const FACTION_LABEL := {
	"compact": "COMPACT",
	"forge": "FORGE",
	"reed": "REEDWATER",
	"raiders": "RAIDERS"
}
const HOME_ISLAND_IDS: Array = [
	"isl_lantern", "isl_kelp", "isl_sawtooth", "isl_verdigris",
	"isl_cinder", "isl_fen", "isl_oilstone", "isl_shatter"
]
const OCEAN_CACHE_LIMIT: int = 48
const LOCAL_CACHE_LIMIT: int = 16
const HARBOR_CACHE_LIMIT: int = 16
const ZONE_CACHE_LIMIT: int = 8

var _local_region_cache: Dictionary = {}
var _ocean_region_cache: Dictionary = {}
var _zone_cache: Dictionary = {}
var _harbor_cache068: Dictionary = {}
var _fallback_font: SystemFont = null


static func _is_finite_number(value) -> bool:
	if value is bool:
		return false
	if value is int or value is float:
		return is_finite(float(value))
	return false


static func _valid_point(value) -> bool:
	if not (value is Dictionary):
		return false
	return _is_finite_number(value.get("x", null)) and _is_finite_number(value.get("y", null))


static func _to_vec2(point: Dictionary) -> Vector2:
	return Vector2(float(point["x"]), float(point["y"]))


static func _safe_region_id(region_id: String) -> bool:
	if region_id.is_empty() or region_id.length() > 64:
		return false
	for i in range(region_id.length()):
		var code: int = region_id.unicode_at(i)
		var digit: bool = code >= 48 and code <= 57
		var upper: bool = code >= 65 and code <= 90
		var lower: bool = code >= 97 and code <= 122
		if not (digit or upper or lower or code == 95 or code == 45):
			return false
	return true


static func _valid_layer_pair(layer: String, region_id: String, view = null) -> bool:
	if layer == "home":
		return region_id == HOME_REGION_ID
	if layer == "ocean":
		return region_id == OCEAN_REGION_ID
	if layer == "local":
		if region_id == GLASSWIND_REGION_ID:
			return true
		return _generated_local_member(view, region_id)
	return false


static func generated_member(view, region_id: String) -> bool:
	return _generated_local_member(view, region_id)


static func _generated_local_member(view, region_id: String) -> bool:
	if region_id == HOME_REGION_ID or region_id == GLASSWIND_REGION_ID or region_id == OCEAN_REGION_ID:
		return false
	if not _safe_region_id(region_id) or not (view is Dictionary):
		return false
	var regions = view.get("regions", null)
	if not _ocean_regions_ok(regions) or regions.size() != GENERATED_REGION_COUNT:
		return false
	for rv in regions:
		if str(rv.get("regionId", "")) == region_id and str(rv.get("layer", "")) == "local":
			return true
	return false


static func _valid_bounds_dict(bounds) -> bool:
	if not (bounds is Dictionary):
		return false
	if not _is_finite_number(bounds.get("x", null)) or not _is_finite_number(bounds.get("y", null)):
		return false
	if not _is_finite_number(bounds.get("width", null)) or not _is_finite_number(bounds.get("height", null)):
		return false
	return float(bounds["width"]) > 0.0 and float(bounds["height"]) > 0.0


static func _valid_approach(av, expected_region_id: String = "") -> bool:
	if not (av is Dictionary):
		return false
	if not (av.get("regionId", null) is String) or not (av.get("id", null) is String) or not (av.get("name", null) is String):
		return false
	var region_id: String = str(av["regionId"])
	var approach_id: String = str(av["id"])
	if region_id.is_empty() or not (approach_id in VALID_APPROACH_IDS):
		return false
	if not expected_region_id.is_empty() and region_id != expected_region_id:
		return false
	if not _valid_point(av.get("position", null)):
		return false
	if not _is_finite_number(av.get("radius", null)) or float(av["radius"]) <= 0.0:
		return false
	return true


static func _extract_island_pairs(points) -> Array:
	if not (points is Array) or points.size() < 3:
		return []
	var out: Array = []
	for p in points:
		if p is Array and p.size() >= 2 and _is_finite_number(p[0]) and _is_finite_number(p[1]):
			out.append([float(p[0]), float(p[1])])
		elif _valid_point(p):
			out.append([float(p["x"]), float(p["y"])])
		else:
			return []
	return out


static func _extract_silhouette_pairs(ring) -> Array:
	if not (ring is Array) or ring.size() < 3:
		return []
	var out: Array = []
	for p in ring:
		if not _valid_point(p):
			return []
		out.append([float(p["x"]), float(p["y"])])
	return out


static func _valid_island_record(island, disallow_home_ids: bool) -> bool:
	if not (island is Dictionary):
		return false
	if not (island.get("id", null) is String) or not (island.get("name", null) is String):
		return false
	var island_id: String = str(island["id"])
	if island_id.is_empty() or str(island["name"]).is_empty():
		return false
	if disallow_home_ids and island_id in HOME_ISLAND_IDS:
		return false
	var pairs: Array = _extract_island_pairs(island.get("points", null))
	return pairs.size() >= 3


static func _valid_region_view(rv) -> bool:
	if not (rv is Dictionary):
		return false
	if not (rv.get("regionId", null) is String) or not (rv.get("name", null) is String) or not (rv.get("layer", null) is String):
		return false
	var region_id: String = str(rv["regionId"])
	var layer: String = str(rv["layer"])
	var authored_local: bool = layer == "local" and region_id == GLASSWIND_REGION_ID
	var authored_home: bool = layer == "home" and region_id == HOME_REGION_ID
	var generated_local: bool = layer == "local" and _safe_region_id(region_id) and region_id != HOME_REGION_ID and region_id != GLASSWIND_REGION_ID and region_id != OCEAN_REGION_ID
	if not (authored_home or authored_local or generated_local):
		return false
	var silhouettes = rv.get("silhouettes", null)
	if not (silhouettes is Array) or silhouettes.is_empty():
		return false
	for ring in silhouettes:
		if _extract_silhouette_pairs(ring).size() < 3:
			return false
	var approaches = rv.get("approaches", null)
	if not (approaches is Array):
		return false
	for av in approaches:
		if not _valid_approach(av, region_id):
			return false
	return true


static func _ocean_regions_ok(regions) -> bool:
	if not (regions is Array):
		return false
	if regions.size() != LEGACY_REGION_COUNT and regions.size() != GENERATED_REGION_COUNT:
		return false
	var seen: Dictionary = {}
	for rv in regions:
		if not _valid_region_view(rv):
			return false
		var region_id: String = str(rv["regionId"])
		if seen.has(region_id):
			return false
		seen[region_id] = str(rv["layer"])
	if regions.size() == LEGACY_REGION_COUNT:
		return seen.size() == LEGACY_REGION_COUNT and seen.get(HOME_REGION_ID, "") == "home" and seen.get(GLASSWIND_REGION_ID, "") == "local"
	if seen.get(HOME_REGION_ID, "") != "home" or seen.get(GLASSWIND_REGION_ID, "") != "local" or seen.size() != GENERATED_REGION_COUNT:
		return false
	for region_id in seen:
		if region_id != HOME_REGION_ID and str(seen[region_id]) != "local":
			return false
	return true


static func _valid_view(view, require_full_draw_fields: bool = false) -> bool:
	if not (view is Dictionary):
		return false
	if view.has("ok") and view.has("view") and not view.has("layer"):
		return false
	if not (view.get("layer", null) is String) or not (view.get("regionId", null) is String):
		return false
	var layer: String = str(view["layer"])
	var region_id: String = str(view["regionId"])
	if not _valid_layer_pair(layer, region_id, view):
		return false
	if not _valid_bounds_dict(view.get("bounds", null)):
		return false
	if not require_full_draw_fields:
		return true
	if not (view.get("name", null) is String) or str(view["name"]).is_empty():
		return false
	if not _valid_point(view.get("position", null)):
		return false
	if not _is_finite_number(view.get("heading", null)):
		return false
	if not (view.get("destination", null) is String):
		return false
	var path = view.get("path", null)
	if not (path is Array):
		return false
	for wp in path:
		if not _valid_point(wp):
			return false
	var boats = view.get("boats", null)
	if not (boats is Array):
		return false
	var approaches = view.get("approaches", null)
	if not (approaches is Array):
		return false
	var home_interactions = view.get("homeInteractions", null)
	if not (home_interactions is bool):
		return false
	if bool(home_interactions) != (layer == "home" and region_id == HOME_REGION_ID):
		return false
	var islands = view.get("islands", null)
	if not (islands is Array):
		return false
	if layer == "local":
		var published = view.get("regions", null)
		if published is Array and not published.is_empty():
			if not _ocean_regions_ok(published) or not _region_in_view(view, region_id):
				return false
		elif region_id != GLASSWIND_REGION_ID:
			return false
		if islands.is_empty():
			return false
		for isl in islands:
			if not _valid_island_record(isl, true):
				return false
		for av in approaches:
			if not _valid_approach(av, region_id):
				return false
	elif layer == "home":
		if islands.is_empty():
			return false
		for isl in islands:
			if not _valid_island_record(isl, false):
				return false
		for av in approaches:
			if not _valid_approach(av, region_id):
				return false
	elif layer == "ocean":
		if not islands.is_empty():
			return false
		var regions = view.get("regions", null)
		if not _ocean_regions_ok(regions):
			return false
		if regions.size() == GENERATED_REGION_COUNT:
			var ocean_width: float = float(view["bounds"]["width"])
			var ocean_height: float = float(view["bounds"]["height"])
			if not is_equal_approx(ocean_width, GENERATED_OCEAN_WIDTH) or not is_equal_approx(ocean_height, GENERATED_OCEAN_HEIGHT):
				return false
		for av in approaches:
			if not _valid_approach(av):
				return false
	return true


static func _region_in_view(view: Dictionary, region_id: String) -> bool:
	var regions = view.get("regions", null)
	if not (regions is Array):
		return false
	for rv in regions:
		if not (rv is Dictionary) or str(rv.get("regionId", "")) != region_id or not _valid_region_view(rv):
			continue
		var layer: String = str(rv.get("layer", ""))
		if region_id == HOME_REGION_ID:
			return layer == "home"
		return layer == "local"
	return false


static func _resolve_ocean_view066(chart, ocean_view066 = null) -> Dictionary:
	if ocean_view066 is Dictionary:
		return ocean_view066
	if ocean_view066 == null and chart != null:
		if chart is Object and chart.has_method("_ocean_view066"):
			var v = chart._ocean_view066()
			if v is Dictionary:
				return v
		var h = chart.get("host")
		if h != null and h.get("core") != null and h.core is Object and h.core.has_method("ocean_view066"):
			var v2 = h.core.ocean_view066()
			if v2 is Dictionary:
				return v2
	return {}


static func _resolve_exploration_view067(chart, exploration_view067 = null) -> Dictionary:
	if exploration_view067 is Dictionary:
		return exploration_view067
	if exploration_view067 == null and chart != null:
		if chart is Object and chart.has_method("_exploration_view067"):
			var v = chart._exploration_view067()
			if v is Dictionary:
				return v
		var h = chart.get("host")
		if h != null and h.get("core") != null and h.core is Object and h.core.has_method("exploration_view067"):
			var v2 = h.core.exploration_view067()
			if v2 is Dictionary:
				return v2
	return {}


static func _resolve_shipping_view068(chart, shipping_view068 = null) -> Dictionary:
	if shipping_view068 is Dictionary:
		return shipping_view068
	if shipping_view068 == null and chart != null:
		if chart is Object and chart.has_method("_shipping_view068"):
			var v = chart._shipping_view068()
			if v is Dictionary:
				return v
		var h = chart.get("host")
		if h != null and h.get("core") != null and h.core is Object and h.core.has_method("shipping_view068"):
			var v2 = h.core.shipping_view068()
			if v2 is Dictionary:
				return v2
	return {}


static func _resolve_sector_view069(chart, sector_view069 = null) -> Dictionary:
	if sector_view069 is Dictionary:
		return sector_view069
	if sector_view069 == null and chart != null:
		if chart is Object and chart.has_method("_sector_view069"):
			var v = chart._sector_view069()
			if v is Dictionary:
				return v
		var h = chart.get("host")
		if h != null and h.get("core") != null and h.core is Object and h.core.has_method("sector_view069"):
			var v2 = h.core.sector_view069()
			if v2 is Dictionary:
				return v2
	return {}


static func _sector_schema1(sector) -> bool:
	if not (sector is Dictionary) or sector.is_empty():
		return false
	var schema = sector.get("schema", null)
	if schema is bool or not (schema is int or schema is float):
		return false
	return int(schema) == 1


static func _sector_groups(sector) -> Dictionary:
	var out: Dictionary = {}
	if not _sector_schema1(sector):
		return out
	var groups = sector.get("groups", null)
	if not (groups is Array):
		return out
	for group in groups:
		if not (group is Dictionary):
			continue
		var region_id: String = str(group.get("regionId", "")).strip_edges()
		if region_id.is_empty() or out.has(region_id):
			continue
		out[region_id] = group
	return out


static func _known_group(group) -> Dictionary:
	if not (group is Dictionary) or group.is_empty():
		return {}
	var knowledge: String = str(group.get("knowledge", "")).strip_edges().to_lower()
	if knowledge.begins_with("unknown"):
		return {}
	var summary: String = str(group.get("ownershipSummary", "")).strip_edges().to_lower()
	if summary.is_empty() or summary == "unknown" or not (summary in KNOWN_OWNERSHIP):
		return {}
	return group


static func _segment_parts(group: Dictionary) -> Array:
	var raw = group.get("segments", null)
	if not (raw is Array):
		return []
	var out: Array = []
	for seg in raw:
		if not (seg is Dictionary):
			continue
		var faction_id: String = str(seg.get("factionId", "")).strip_edges().to_lower()
		if not FACTION_COLOR.has(faction_id):
			continue
		var weight: float = 1.0
		if _is_finite_number(seg.get("knownAssets", null)) and float(seg["knownAssets"]) > 0.0:
			weight = float(seg["knownAssets"])
		out.append({"factionId": faction_id, "weight": weight, "color": FACTION_COLOR[faction_id]})
	return out


static func _join_labels(names: Array) -> String:
	var joined: String = ""
	for name in names:
		if str(name).is_empty():
			continue
		if not joined.is_empty():
			joined += " · "
		joined += str(name)
	return joined


static func _ownership_line(group) -> String:
	var known: Dictionary = _known_group(group)
	if known.is_empty():
		return ""
	var summary: String = str(known.get("ownershipSummary", "")).strip_edges().to_lower()
	var names: Array = []
	for part in _segment_parts(known):
		var label: String = str(FACTION_LABEL.get(str(part["factionId"]), ""))
		if not label.is_empty() and not names.has(label):
			names.append(label)
	if summary == "neutral":
		return "NEUTRAL WATERS"
	if summary == "single" and names.size() == 1:
		return "KNOWN %s HOLDING" % str(names[0])
	if summary == "mixed" and names.size() >= 2:
		return "MIXED KNOWN HOLDINGS · %s" % _join_labels(names)
	if summary == "contested" and not names.is_empty():
		return "CONTESTED · %s" % _join_labels(names)
	if summary == "allied" and not names.is_empty():
		return "ALLIED · %s" % _join_labels(names)
	return ""


static func known_ownership_line(group) -> String:
	return _ownership_line(group)


static func _legacy_holding_line(rows) -> String:
	if not (rows is Array):
		return ""
	var names: Array = []
	for row in rows:
		if not (row is Dictionary):
			continue
		var faction_id: String = str(row.get("faction", "")).strip_edges().to_lower()
		var label: String = str(FACTION_LABEL.get(faction_id, ""))
		if not label.is_empty() and not names.has(label):
			names.append(label)
	if names.size() == 1:
		return "KNOWN %s HOLDING" % str(names[0])
	if names.size() >= 2:
		return "MIXED KNOWN HOLDINGS · %s" % _join_labels(names)
	return ""


static func _legacy_segment_parts(rows) -> Array:
	if not (rows is Array):
		return []
	var out: Array = []
	var seen: Dictionary = {}
	for row in rows:
		if not (row is Dictionary):
			continue
		var faction_id: String = str(row.get("faction", "")).strip_edges().to_lower()
		if seen.has(faction_id) or not FACTION_COLOR.has(faction_id):
			continue
		seen[faction_id] = true
		out.append({"factionId": faction_id, "weight": 1.0, "color": FACTION_COLOR[faction_id]})
	return out


static func _sector_island_faction(sector, region_id: String, island_id: String) -> String:
	if island_id.is_empty() or _known_group(_sector_groups(sector).get(region_id, {})).is_empty():
		return ""
	var rows = sector.get("ownership", null)
	if not (rows is Array):
		return ""
	for row in rows:
		if not (row is Dictionary):
			continue
		if str(row.get("regionId", "")).strip_edges() != region_id:
			continue
		if str(row.get("islandId", "")).strip_edges() != island_id:
			continue
		var faction_id: String = str(row.get("faction", "")).strip_edges().to_lower()
		if FACTION_LABEL.has(faction_id):
			return faction_id
	return ""


static func _local_ports(view064: Dictionary, view068: Dictionary, sector) -> Array:
	var ports: Array = _extract_local_ports068(view064, view068)
	if not _sector_schema1(sector):
		return ports
	var seen: Dictionary = {}
	for port in ports:
		seen[str(port.get("id", ""))] = true
	var active_region: String = str(view064.get("regionId", ""))
	var raw_ports = sector.get("ports", [])
	var matched: Array = []
	if raw_ports is Array:
		for raw_port in raw_ports:
			if raw_port is Dictionary and str(raw_port.get("regionId", "")) == active_region:
				matched.append(raw_port)
	for port in _extract_local_ports068(view064, {"ports": matched}):
		var port_id: String = str(port.get("id", ""))
		if port_id.is_empty() or seen.has(port_id):
			continue
		seen[port_id] = true
		ports.append(port)
	return ports


static func _sites_view(view064: Dictionary, view067: Dictionary, sector) -> Dictionary:
	if not _sector_schema1(sector):
		return view067
	var active_region: String = str(view064.get("regionId", ""))
	var parent_region: String = ""
	if view067.get("world064") is Dictionary:
		parent_region = str(view067["world064"].get("regionId", ""))
	var same_chart: bool = parent_region.is_empty() or parent_region == active_region
	var merged: Array = []
	var seen: Dictionary = {}
	if same_chart and view067.get("sites") is Array:
		for site in view067["sites"]:
			if not (site is Dictionary):
				continue
			var site_id: String = str(site.get("id", ""))
			if site_id.is_empty() or seen.has(site_id):
				continue
			seen[site_id] = true
			merged.append(site)
	var extra = sector.get("sites", [])
	if extra is Array:
		for site in extra:
			if not (site is Dictionary) or str(site.get("regionId", "")) != active_region:
				continue
			var site_id: String = str(site.get("id", ""))
			if site_id.is_empty() or seen.has(site_id):
				continue
			seen[site_id] = true
			merged.append(site)
	var combined: Dictionary = view067.duplicate() if same_chart else {}
	combined["sites"] = merged
	if not active_region.is_empty():
		combined["world064"] = {"layer": "local", "regionId": active_region}
	return combined


static func _extract_local_ports068(view064: Dictionary, view068: Dictionary) -> Array:
	if str(view064.get("layer", "")) != "local" or view068.is_empty():
		return []
	var active_region: String = str(view064.get("regionId", "glasswind_keys"))
	var raw_ports = view068.get("ports", null)
	if not (raw_ports is Array) or raw_ports.is_empty():
		return []
	var out: Array = []
	for raw_p in raw_ports:
		if not (raw_p is Dictionary):
			continue
		if raw_p.has("known") and not bool(raw_p["known"]):
			continue
		if raw_p.has("installed") and not bool(raw_p["installed"]):
			continue
		var pid: String = str(raw_p.get("id", "")).strip_edges()
		if pid.is_empty() or not _is_finite_number(raw_p.get("x", null)) or not _is_finite_number(raw_p.get("y", null)):
			continue
		var p_reg: String = str(raw_p.get("regionId", active_region))
		if p_reg != active_region:
			continue
		out.append({
			"id": pid,
			"name": str(raw_p.get("name", "Westglass Anchorage")),
			"regionId": p_reg,
			"islandId": str(raw_p.get("islandId", "glasswind_west")),
			"faction": str(raw_p.get("faction", "reed")),
			"industry": str(raw_p.get("industry", "timber")),
			"specialty": str(raw_p.get("specialty", "logs")),
			"x": float(raw_p["x"]),
			"y": float(raw_p["y"]),
			"atBerth": bool(raw_p.get("atBerth", false))
		})
	return out


static func _extract_ownership068(view068: Dictionary) -> Dictionary:
	var by_island: Dictionary = {}
	var by_region: Dictionary = {}
	if view068.is_empty():
		return {"islands": by_island, "regions": by_region}
	var raw_own = view068.get("ownership", null)
	if raw_own is Array:
		for item in raw_own:
			if not (item is Dictionary):
				continue
			var reg_id: String = str(item.get("regionId", "")).strip_edges()
			var isl_id: String = str(item.get("islandId", "")).strip_edges()
			var port_id: String = str(item.get("portId", "")).strip_edges()
			var fac: String = str(item.get("faction", "")).strip_edges()
			if not isl_id.is_empty() and not fac.is_empty():
				by_island[isl_id] = {"islandId": isl_id, "portId": port_id, "faction": fac, "regionId": reg_id}
			if not reg_id.is_empty() and not fac.is_empty():
				if not by_region.has(reg_id):
					by_region[reg_id] = []
				by_region[reg_id].append({"islandId": isl_id, "portId": port_id, "faction": fac})
	var raw_ports = view068.get("ports", null)
	if raw_ports is Array:
		for p in raw_ports:
			if not (p is Dictionary):
				continue
			if p.has("known") and not bool(p["known"]):
				continue
			if p.has("installed") and not bool(p["installed"]):
				continue
			var reg_id: String = str(p.get("regionId", "glasswind_keys")).strip_edges()
			var isl_id: String = str(p.get("islandId", "glasswind_west")).strip_edges()
			var port_id: String = str(p.get("id", "")).strip_edges()
			var fac: String = str(p.get("faction", "reed")).strip_edges()
			if not isl_id.is_empty() and not by_island.has(isl_id):
				by_island[isl_id] = {"islandId": isl_id, "portId": port_id, "faction": fac, "regionId": reg_id}
			if not reg_id.is_empty() and not by_region.has(reg_id):
				by_region[reg_id] = [{"islandId": isl_id, "portId": port_id, "faction": fac}]
	return {"islands": by_island, "regions": by_region}


static func _extract_local_sites067(view064: Dictionary, view067: Dictionary) -> Array:
	if str(view064.get("layer", "")) != "local" or view067.is_empty():
		return []
	var active_region: String = str(view064.get("regionId", "glasswind_keys"))
	if view067.get("world064") is Dictionary and not view067["world064"].is_empty():
		var w64: Dictionary = view067["world064"]
		if w64.has("layer") and str(w64["layer"]) != "local":
			return []
		if w64.has("regionId") and str(w64["regionId"]) != active_region:
			return []
	var raw_sites = view067.get("sites", null)
	if not (raw_sites is Array) or raw_sites.is_empty():
		return []
	var out: Array = []
	for raw_s in raw_sites:
		if not (raw_s is Dictionary):
			continue
		var sid: String = str(raw_s.get("id", "")).strip_edges()
		if sid.is_empty() or not _is_finite_number(raw_s.get("x", null)) or not _is_finite_number(raw_s.get("y", null)):
			continue
		var lvl: int = int(raw_s["level"]) if _is_finite_number(raw_s.get("level", null)) else 0
		if lvl <= 0:
			continue
		var s_reg: String = str(raw_s.get("regionId", active_region))
		if s_reg != active_region:
			continue
		out.append({
			"id": sid,
			"kind": str(raw_s.get("kind", "")),
			"regionId": s_reg,
			"x": float(raw_s["x"]),
			"y": float(raw_s["y"]),
			"level": lvl,
			"levelName": str(raw_s.get("levelName", "Sighted" if lvl == 1 else ("Charted" if lvl == 2 else "Surveyed"))),
			"name": str(raw_s.get("name", "Uncharted Landing")),
			"clue": str(raw_s.get("clue", "")),
			"hazard": str(raw_s.get("hazard", "")) if lvl >= 2 else "",
			"discovery": str(raw_s.get("discovery", "")) if lvl >= 3 else "",
			"resource": str(raw_s.get("resource", "")) if lvl >= 3 else "",
			"leadId": str(raw_s.get("leadId", "")) if lvl >= 3 else ""
		})
	return out


static func _extract_local_wrecks067(view064: Dictionary, view067: Dictionary) -> Array:
	if str(view064.get("layer", "")) != "local" or view067.is_empty():
		return []
	var active_region: String = str(view064.get("regionId", "glasswind_keys"))
	var raw_wrecks = view067.get("wrecks", null)
	if not (raw_wrecks is Array) or raw_wrecks.is_empty():
		return []
	var out: Array = []
	for raw_w in raw_wrecks:
		if not (raw_w is Dictionary):
			continue
		var wid: String = str(raw_w.get("id", "")).strip_edges()
		if wid.is_empty() or not _is_finite_number(raw_w.get("x", null)) or not _is_finite_number(raw_w.get("y", null)):
			continue
		var status: String = str(raw_w.get("status", "unclaimed"))
		if status != "unclaimed":
			continue
		if raw_w.get("world064") is Dictionary and not raw_w["world064"].is_empty():
			var ww: Dictionary = raw_w["world064"]
			if ww.has("layer") and str(ww["layer"]) != "local":
				continue
			if ww.has("regionId") and str(ww["regionId"]) != active_region:
				continue
		out.append({
			"id": wid,
			"name": str(raw_w.get("name", "Collapsed Supply Coaster")),
			"x": float(raw_w["x"]),
			"y": float(raw_w["y"]),
			"status": status,
			"cargoOnly": bool(raw_w.get("cargoOnly", true))
		})
	return out


func _draw_local_sites_and_wrecks067(chart, view064: Dictionary, view067: Dictionary, labels: Array, metrics: Dictionary) -> void:
	var sites: Array = _extract_local_sites067(view064, view067)
	var wrecks: Array = _extract_local_wrecks067(view064, view067)
	if sites.is_empty() and wrecks.is_empty():
		return
	var scale_val: float = _scale_factor(chart)
	var visible_by_id: Dictionary = {}
	for s in sites:
		visible_by_id[str(s["id"])] = s
	var assignment: Dictionary = view067.get("assignment", {}) if view067.get("assignment") is Dictionary else {}
	var active_site_id: String = str(assignment.get("siteId", ""))
	var selected_site_id: String = ""
	var h = chart.get("host")
	if h != null and h.get("selected_site") is String:
		selected_site_id = str(h.selected_site)
	var destination: String = str(view064.get("destination", ""))
	for s in sites:
		if int(s["level"]) < 3:
			continue
		var lead_id: String = str(s.get("leadId", ""))
		if lead_id.is_empty() or not visible_by_id.has(lead_id):
			continue
		var target_s: Dictionary = visible_by_id[lead_id]
		var p0: Vector2 = chart.project(Vector2(float(s["x"]), float(s["y"])))
		var p1: Vector2 = chart.project(Vector2(float(target_s["x"]), float(target_s["y"])))
		chart.draw_dashed_line(p0, p1, Color(GOLD, 0.56), 1.35, 6.0, true)
		metrics["leads_drawn"] = int(metrics.get("leads_drawn", 0)) + 1
	for s in sites:
		var sid: String = str(s["id"])
		var lvl: int = int(s["level"])
		var pos := Vector2(float(s["x"]), float(s["y"]))
		var screen_pos: Vector2 = chart.project(pos)
		var is_working: bool = (active_site_id == sid)
		var is_selected: bool = (selected_site_id == sid or destination == sid or is_working)
		var art: Dictionary = LandmarkArt054.plan(s, lvl, screen_pos, scale_val)
		LandmarkArt054.draw(chart, art, is_selected)
		if is_working:
			chart.draw_arc(screen_pos, 18.0, 0.0, TAU, 24, Color(GOLD, 0.82), 1.4, true)
		var sub: String = "SIGHTED LANDING" if lvl == 1 else ("CHARTED LANDING" if lvl == 2 else "SURVEYED")
		if is_working:
			sub = "SHORE PARTY WORKING"
		elif lvl >= 3 and not str(s.get("leadId", "")).is_empty() and visible_by_id.has(str(s["leadId"])):
			sub = "SURVEYED · BEARING LOGGED"
		labels.append({
			"at": screen_pos,
			"art_bounds": Rect2(art.get("bounds", Rect2())).grow(4.0),
			"text": str(s["name"]) if is_selected or lvl >= 2 else "",
			"subtitle": sub if is_selected or lvl >= 2 else "",
			"priority": 92 if is_selected else (84 if lvl >= 2 else 78),
			"color": GOLD if (is_selected or lvl >= 2) else FOAM
		})
		metrics["sites_drawn"] = int(metrics.get("sites_drawn", 0)) + 1
	for w in wrecks:
		var wid: String = str(w["id"])
		var pos := Vector2(float(w["x"]), float(w["y"]))
		var screen_pos: Vector2 = chart.project(pos)
		var art: Dictionary = LandmarkArt054.wreck_plan(w, screen_pos, scale_val)
		LandmarkArt054.draw(chart, art, destination == wid)
		labels.append({
			"at": screen_pos,
			"art_bounds": Rect2(art.get("bounds", Rect2())).grow(4.0),
			"text": str(w["name"]),
			"subtitle": "CARGO CACHE" if bool(w.get("cargoOnly", true)) else "WRECK",
			"priority": 88,
			"color": GOLD
		})
		metrics["wrecks_drawn"] = int(metrics.get("wrecks_drawn", 0)) + 1


func pick_local067(chart, view_or_exp067: Dictionary, screen_or_exp067, maybe_screen = null) -> Dictionary:
	if chart == null:
		return {}
	var view064: Dictionary = {}
	var view067: Dictionary = {}
	var screen := Vector2.INF
	if maybe_screen is Vector2:
		view064 = view_or_exp067
		if screen_or_exp067 is Dictionary:
			view067 = screen_or_exp067
		screen = maybe_screen
	elif screen_or_exp067 is Vector2:
		screen = screen_or_exp067
		if view_or_exp067.has("sites") and not view_or_exp067.has("layer"):
			view067 = view_or_exp067
			var h = chart.get("host")
			if h != null and h.get("core") != null and h.core is Object and h.core.has_method("world_view064"):
				var v64 = h.core.world_view064()
				if v64 is Dictionary:
					view064 = v64
		else:
			view064 = view_or_exp067
			view067 = _resolve_exploration_view067(chart, null)
	else:
		return {}
	if not screen.is_finite() or str(view064.get("layer", "")) != "local":
		return {}
	var scale_val: float = _scale_factor(chart)
	var sites: Array = _extract_local_sites067(view064, _sites_view(view064, view067, _resolve_sector_view069(chart, null)))
	var wrecks: Array = _extract_local_wrecks067(view064, view067)
	var best_w: Dictionary = {}
	var best_w_dist: float = INF
	for w in wrecks:
		var pos := Vector2(float(w["x"]), float(w["y"]))
		var screen_pos: Vector2 = chart.project(pos)
		var art: Dictionary = LandmarkArt054.wreck_plan(w, screen_pos, scale_val)
		var art_bounds: Rect2 = Rect2(art.get("bounds", Rect2()))
		var dist: float = screen_pos.distance_to(screen)
		if (art_bounds.has_area() and art_bounds.grow(4.0).has_point(screen)) or dist <= 20.0:
			if dist < best_w_dist:
				best_w_dist = dist
				best_w = w
	var best_s: Dictionary = {}
	var best_s_dist: float = INF
	for s in sites:
		var pos := Vector2(float(s["x"]), float(s["y"]))
		var screen_pos: Vector2 = chart.project(pos)
		var art: Dictionary = LandmarkArt054.plan(s, int(s["level"]), screen_pos, scale_val)
		var art_bounds: Rect2 = Rect2(art.get("bounds", Rect2()))
		var dist: float = screen_pos.distance_to(screen)
		if (art_bounds.has_area() and art_bounds.grow(4.0).has_point(screen)) or dist <= 22.0:
			if dist < best_s_dist:
				best_s_dist = dist
				best_s = s
	if not best_w.is_empty():
		if best_s.is_empty() or int(best_s.get("level", 0)) >= 3 or best_w_dist + 2.0 < best_s_dist:
			return {"kind": "wreck", "wreckId": str(best_w["id"])}
	if not best_s.is_empty():
		return {"kind": "site", "siteId": str(best_s["id"])}
	return {}


func _prepare_local_harbor068(port: Dictionary, islands: Array) -> Dictionary:
	var pid: String = str(port.get("id", "westglass_anchorage"))
	var px: float = float(port.get("x", 756.0))
	var py: float = float(port.get("y", 732.0))
	var cache_key: String = "%s:%.1f,%.1f:%s:%s:%s:%d" % [pid, px, py, str(port.get("faction", "reed")), str(port.get("industry", "timber")), str(port.get("specialty", "logs")), islands.size()]
	if _harbor_cache068.has(cache_key):
		return _harbor_cache068[cache_key]
	var norm_islands: Array = []
	for isl in islands:
		if not (isl is Dictionary):
			continue
		var pairs: Array = _extract_island_pairs(isl.get("points", []))
		if pairs.size() >= 3:
			norm_islands.append({
				"id": str(isl.get("id", "")),
				"name": str(isl.get("name", "")),
				"points": pairs
			})
	var plan: Dictionary = NauticalArt.settlement_plan({
		"id": pid,
		"name": str(port.get("name", "Westglass Anchorage")),
		"faction": str(port.get("faction", "reed")),
		"industry": str(port.get("industry", "timber")),
		"specialty": str(port.get("specialty", "logs")),
		"x": px,
		"y": py
	}, norm_islands)
	if _harbor_cache068.size() >= HARBOR_CACHE_LIMIT:
		_harbor_cache068.erase(_harbor_cache068.keys()[0])
	_harbor_cache068[cache_key] = plan
	return plan


func _draw_local_ports068(chart, view064: Dictionary, view068: Dictionary, labels: Array, metrics: Dictionary, sector = null) -> void:
	var ports: Array = _local_ports(view064, view068, sector if sector is Dictionary else {})
	if ports.is_empty():
		return
	var islands: Array = view064.get("islands", []) if view064.get("islands") is Array else []
	var projector: Callable = chart._projector()
	var scale_val: float = _scale_factor(chart)
	var viewport_rect: Rect2 = chart.get_viewport_rect()
	var destination: String = str(view064.get("destination", ""))
	var h = chart.get("host")
	var selected_port: String = str(h.selected_port) if (h != null and h.get("selected_port") is String) else ""
	for p in ports:
		var pid: String = str(p["id"])
		var plan: Dictionary = _prepare_local_harbor068(p, islands)
		var started: int = Time.get_ticks_usec() if bool(chart.get("_profile_drawing")) else 0
		var calls: int = NauticalArt.draw_settlement(chart, projector, plan, scale_val, viewport_rect)
		_record_coast_profile(chart, calls, started)
		metrics["coast_draw_calls"] = int(metrics.get("coast_draw_calls", 0)) + calls
		var berth_world := Vector2(float(p["x"]), float(p["y"]))
		var berth_screen: Vector2 = chart.project(berth_world)
		var anchor_world: Vector2 = plan.get("anchor", berth_world)
		var anchor_screen: Vector2 = chart.project(anchor_world)
		var is_at_berth: bool = bool(p.get("atBerth", false))
		var is_selected: bool = (selected_port == pid or destination == pid or is_at_berth)
		var faction_id: String = str(p.get("faction", "")).strip_edges().to_lower()
		var authored_reed: bool = pid == "westglass_anchorage" or (str(view064.get("regionId", "")) == GLASSWIND_REGION_ID and faction_id == "reed")
		var ring_col: Color = GOLD if is_selected else (FACTION_COLOR[faction_id] if FACTION_COLOR.has(faction_id) and not authored_reed else FRIEND)
		chart.draw_line(anchor_screen, berth_screen, Color("a99878", 0.56), 1.6, true)
		chart.draw_arc(berth_screen, 9.5 if is_selected else 7.5, -0.35, PI * 0.85, 16, Color(ring_col, 0.92 if is_selected else 0.78), 1.8 if is_selected else 1.5, true)
		chart.draw_arc(berth_screen, 9.5 if is_selected else 7.5, PI * 1.15, PI * 1.85, 14, Color(ring_col, 0.92 if is_selected else 0.78), 1.8 if is_selected else 1.5, true)
		chart.draw_circle(berth_screen, 2.6, GOLD if is_selected else Color("dfcea3"))
		var sub: String = "DOCKED · REEDWATER TIMBER QUAY" if is_at_berth else ("COURSE TARGET · REEDWATER QUAY" if destination == pid else "REEDWATER TIMBER BRANCH · BERTH")
		if not authored_reed:
			var faction_label: String = str(FACTION_LABEL.get(faction_id, ""))
			if is_at_berth:
				sub = "DOCKED · %s BERTH" % faction_label if not faction_label.is_empty() else "DOCKED"
			elif destination == pid:
				sub = "COURSE TARGET · %s BERTH" % faction_label if not faction_label.is_empty() else "COURSE TARGET"
			else:
				sub = "%s BERTH" % faction_label if not faction_label.is_empty() else "BERTH"
		var art_rect: Rect2 = _project_rect(chart, plan.get("bounds", Rect2(berth_world - Vector2(40, 40), Vector2(80, 80))))
		labels.append({
			"at": berth_screen,
			"art_bounds": art_rect.expand(berth_screen).grow(6.0),
			"text": str(p["name"]).to_upper(),
			"subtitle": sub,
			"priority": 98 if is_selected else 91,
			"color": GOLD if is_selected else Color("e5d5ad")
		})
		metrics["ports_drawn"] = int(metrics.get("ports_drawn", 0)) + 1


func pick_port068(chart, view_or_ship068: Dictionary, screen_or_ship068, maybe_screen = null) -> Dictionary:
	if chart == null:
		return {}
	var view064: Dictionary = {}
	var view068: Dictionary = {}
	var screen := Vector2.INF
	if maybe_screen is Vector2:
		view064 = view_or_ship068
		if screen_or_ship068 is Dictionary:
			view068 = screen_or_ship068
		screen = maybe_screen
	elif screen_or_ship068 is Vector2:
		screen = screen_or_ship068
		if view_or_ship068.has("ports") and not view_or_ship068.has("layer"):
			view068 = view_or_ship068
			var h = chart.get("host")
			if h != null and h.get("core") != null and h.core is Object and h.core.has_method("world_view064"):
				var v64 = h.core.world_view064()
				if v64 is Dictionary:
					view064 = v64
		else:
			view064 = view_or_ship068
			view068 = _resolve_shipping_view068(chart, null)
	else:
		return {}
	if not screen.is_finite() or str(view064.get("layer", "")) != "local":
		return {}
	var ports: Array = _local_ports(view064, view068, _resolve_sector_view069(chart, null))
	if ports.is_empty():
		return {}
	var islands: Array = view064.get("islands", []) if view064.get("islands") is Array else []
	var best_p: Dictionary = {}
	var best_dist: float = INF
	for p in ports:
		var berth_world := Vector2(float(p["x"]), float(p["y"]))
		var berth_screen: Vector2 = chart.project(berth_world)
		var dist: float = berth_screen.distance_to(screen)
		var hit: bool = (dist <= 42.0)
		var plan: Dictionary = _prepare_local_harbor068(p, islands)
		if not hit and not plan.is_empty():
			for roof: PackedVector2Array in plan.get("roofs", []):
				var poly := PackedVector2Array()
				for pt in roof:
					poly.append(chart.project(pt))
				if Geometry2D.is_point_in_polygon(screen, poly):
					hit = true
					dist = minf(dist, 18.0)
					break
			if not hit:
				var pier: PackedVector2Array = plan.get("pier", PackedVector2Array())
				for segment in range(1, pier.size()):
					var a: Vector2 = chart.project(pier[segment-1])
					var b: Vector2 = chart.project(pier[segment])
					var seg_d: float = Geometry2D.get_closest_point_to_segment(screen, a, b).distance_to(screen)
					if seg_d <= 14.0:
						hit = true
						dist = minf(dist, seg_d)
		if hit and dist < best_dist:
			best_dist = dist
			best_p = p
	if not best_p.is_empty():
		return {
			"kind": "port",
			"portId": str(best_p["id"]),
			"regionId": str(best_p.get("regionId", "glasswind_keys")),
			"islandId": str(best_p.get("islandId", "glasswind_west")),
			"x": float(best_p["x"]),
			"y": float(best_p["y"])
		}
	return {}


static func _normalize_render_boats066(raw_boats) -> Array:
	if not (raw_boats is Array):
		return []
	var out: Array = []
	for raw in raw_boats:
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw.duplicate(true)
		var spec_dict: Dictionary = entry.get("spec", {}).duplicate(true) if entry.get("spec") is Dictionary else {}
		var hull_id: String = str(spec_dict.get("id", entry.get("hullId", entry.get("hull_id", entry.get("type", "")))))
		if hull_id.is_empty() and entry.get("id") is String:
			var candidate_id: String = str(entry["id"])
			if not FleetArt054.asset_info({"id": candidate_id}).is_empty():
				hull_id = candidate_id
		if not hull_id.is_empty():
			spec_dict["id"] = hull_id
			var info: Dictionary = FleetArt054.asset_info({"id": hull_id})
			if not info.is_empty():
				if not spec_dict.has("size"):
					spec_dict["size"] = float(info.get("size", 14.0))
				if not spec_dict.has("role"):
					spec_dict["role"] = str(info.get("role", "raider"))
				if not spec_dict.has("tier"):
					spec_dict["tier"] = int(info.get("tier", 1))
			entry["spec"] = spec_dict
		out.append(entry)
	return out


static func _extract_zones066(view064: Dictionary, view066: Dictionary) -> Array:
	if view066.is_empty():
		return []
	var raw_zones = view066.get("zones", null)
	if not (raw_zones is Array) or raw_zones.is_empty():
		return []
	var cond_by_id: Dictionary = {}
	var raw_conds = view066.get("conditions", null)
	if raw_conds is Array:
		for c in raw_conds:
			if c is Dictionary:
				var cid: String = str(c.get("zoneId", c.get("id", "")))
				if not cid.is_empty():
					cond_by_id[cid] = c
	elif raw_conds is Dictionary:
		for k in raw_conds:
			if raw_conds[k] is Dictionary:
				cond_by_id[str(k)] = raw_conds[k]
	var active_layer: String = str(view064.get("layer", "ocean"))
	var out: Array = []
	for raw_z in raw_zones:
		if not (raw_z is Dictionary):
			continue
		var z_layer: String = str(raw_z.get("layer", "ocean"))
		if not view064.is_empty() and z_layer != active_layer:
			continue
		var r_dict = raw_z.get("rect", raw_z.get("bounds", null))
		if not _valid_bounds_dict(r_dict):
			continue
		var rect := Rect2(float(r_dict["x"]), float(r_dict["y"]), float(r_dict["width"]), float(r_dict["height"]))
		var zid: String = str(raw_z.get("id", raw_z.get("zoneId", "zone_%d" % out.size())))
		var cond: Dictionary = cond_by_id.get(zid, {})
		var cur_raw = cond.get("current", raw_z.get("current", null))
		var cur_vec := Vector2.ZERO
		if _valid_point(cur_raw):
			cur_vec = _to_vec2(cur_raw)
		elif _is_finite_number(raw_z.get("heading", null)):
			cur_vec = Vector2.from_angle(float(raw_z["heading"])) * 10.0
		var sf_raw = cond.get("speedFactor", raw_z.get("speedFactor", raw_z.get("speedMultiplier", 1.0)))
		var speed_factor: float = clampf(float(sf_raw), 0.1, 3.0) if _is_finite_number(sf_raw) else 1.0
		var vf_raw = cond.get("visibilityFactor", raw_z.get("visibilityFactor", raw_z.get("detectionMultiplier", 1.0)))
		var vis_factor: float = clampf(float(vf_raw), 0.1, 3.0) if _is_finite_number(vf_raw) else 1.0
		var w_label: String = str(cond.get("label", raw_z.get("weatherLabel", raw_z.get("label", "")))).strip_edges()
		var z_name: String = str(raw_z.get("name", "")).strip_edges()
		if z_name.is_empty():
			z_name = zid.replace("_", " ").capitalize() if not zid.is_empty() else "Ocean Zone"
		var z_kind: String = str(raw_z.get("kind", "")).strip_edges().to_lower()
		var w_lower: String = w_label.to_lower()
		if z_kind.is_empty() or z_kind == "zone":
			if vis_factor < 0.78 or "fog" in w_lower or "mist" in w_lower or "haze" in w_lower:
				z_kind = "fog"
			elif speed_factor < 0.88 or "squall" in w_lower or "storm" in w_lower or "gale" in w_lower or "chop" in w_lower:
				z_kind = "squall"
			elif cur_vec.length() > 0.5:
				z_kind = "current"
			else:
				z_kind = "clear"
		var summary: String = str(raw_z.get("summary", "")).strip_edges()
		if summary.is_empty():
			var parts: Array = []
			if not w_label.is_empty():
				parts.append(w_label.to_upper())
			parts.append("SPD %d%%" % roundi(speed_factor * 100.0))
			parts.append("SIGHT %d%%" % roundi(vis_factor * 100.0))
			if cur_vec.length() >= 0.5:
				parts.append("CUR %.0f" % cur_vec.length())
			summary = " · ".join(parts)
		out.append({
			"id": zid,
			"name": z_name,
			"kind": z_kind,
			"rect": rect,
			"current": cur_vec,
			"speedFactor": speed_factor,
			"visibilityFactor": vis_factor,
			"weatherLabel": w_label,
			"summary": summary
		})
	return out


func _prepare_zone066(z: Dictionary) -> Dictionary:
	var rect: Rect2 = z["rect"]
	var cur: Vector2 = z["current"]
	var kind: String = str(z["kind"])
	var cache_key: String = "%s:%.1f,%.1f,%.1f,%.1f:%.1f,%.1f:%s" % [
		str(z["id"]), rect.position.x, rect.position.y, rect.size.x, rect.size.y, cur.x, cur.y, kind
	]
	if _zone_cache.has(cache_key):
		return _zone_cache[cache_key]
	var corners: Array = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y)
	]
	var border: Array = corners.duplicate()
	border.append(rect.position)
	var streamlines: Array = []
	var chevrons: Array = []
	var center: Vector2 = rect.get_center()
	var dir: Vector2 = cur.normalized() if cur.length() > 0.25 else Vector2.RIGHT
	var perp: Vector2 = dir.orthogonal()
	var span_along: float = minf(rect.size.x, rect.size.y) * 0.36
	var span_across: float = minf(rect.size.x, rect.size.y) * 0.24
	if cur.length() > 0.25:
		for lane in [-1.0, 0.0, 1.0]:
			var lane_center: Vector2 = center + perp * (lane * span_across)
			var p_start: Vector2 = (lane_center - dir * span_along).clamp(rect.position + Vector2(18.0, 18.0), rect.end - Vector2(18.0, 18.0))
			var p_end: Vector2 = (lane_center + dir * span_along).clamp(rect.position + Vector2(18.0, 18.0), rect.end - Vector2(18.0, 18.0))
			if p_start.distance_to(p_end) >= 24.0:
				streamlines.append([p_start, p_end])
				for frac in [0.38, 0.74]:
					var tip: Vector2 = p_start.lerp(p_end, float(frac))
					var head_len: float = clampf(minf(rect.size.x, rect.size.y) * 0.045, 12.0, 26.0)
					var head_wid: float = head_len * 0.55
					chevrons.append([
						tip,
						tip - dir * head_len + perp * head_wid,
						tip - dir * head_len - perp * head_wid
					])
	var weather_bands: Array = []
	if kind in ["fog", "squall"]:
		for idx in range(-2, 3):
			var y_off: float = float(idx) * (rect.size.y * 0.16)
			var y_val: float = clampf(center.y + y_off, rect.position.y + 14.0, rect.end.y - 14.0)
			var inset: float = (18.0 + float(absi(idx)) * 14.0)
			var x0: float = rect.position.x + minf(inset, rect.size.x * 0.25)
			var x1: float = rect.end.x - minf(inset, rect.size.x * 0.25)
			if x1 > x0 + 20.0:
				if kind == "squall":
					weather_bands.append([Vector2(x0, y_val - 8.0), Vector2(x1, y_val + 8.0)])
				else:
					weather_bands.append([Vector2(x0, y_val), Vector2(x1, y_val)])
	var plan: Dictionary = {
		"cacheKey": cache_key,
		"corners": corners,
		"border": border,
		"streamlines": streamlines,
		"chevrons": chevrons,
		"weatherBands": weather_bands,
		"center": center
	}
	if _zone_cache.size() >= ZONE_CACHE_LIMIT:
		_zone_cache.erase(_zone_cache.keys()[0])
	_zone_cache[cache_key] = plan
	return plan


func _draw_zones066(chart, view064: Dictionary, view066: Dictionary, labels: Array) -> int:
	var zones: Array = _extract_zones066(view064, view066)
	if zones.is_empty():
		return 0
	var count: int = 0
	for z in zones:
		var plan: Dictionary = _prepare_zone066(z)
		var kind: String = str(z["kind"])
		var base_color: Color = FOG_TINT if kind == "fog" else (SQUALL_TINT if kind == "squall" else CURRENT_TINT)
		var fill_alpha: float = 0.075 if kind in ["fog", "squall"] else 0.055
		var border_alpha: float = 0.28 if kind in ["fog", "squall"] else 0.22
		chart.world_poly(plan["corners"], Color(base_color, fill_alpha))
		chart.world_line(plan["border"], Color(base_color, border_alpha), 1.15)
		for band in plan["weatherBands"]:
			var b_pts: Array = band
			if b_pts.size() >= 2:
				chart.draw_dashed_line(
					chart.project(b_pts[0]),
					chart.project(b_pts[1]),
					Color(base_color, 0.22),
					1.1,
					7.0 if kind == "fog" else 4.5,
					true
				)
		for stream in plan["streamlines"]:
			chart.world_line(stream, Color(CURRENT_TINT, 0.34), 1.25)
		for chev in plan["chevrons"]:
			chart.world_poly(chev, Color(CURRENT_TINT, 0.46))
		var center_world: Vector2 = plan["center"]
		var screen_center: Vector2 = chart.project(center_world)
		labels.append({
			"at": screen_center,
			"art_bounds": Rect2(screen_center - Vector2(28.0, 14.0), Vector2(56.0, 28.0)),
			"text": str(z["name"]).to_upper(),
			"subtitle": str(z["summary"]),
			"priority": 32,
			"color": base_color
		})
		count += 1
	return count


static func _extract_contacts066(view064: Dictionary, view066: Dictionary, view068: Dictionary = {}) -> Array:
	var combined: Array = []
	if not view066.is_empty() and view066.get("contacts") is Array:
		combined.append_array(view066["contacts"])
	if not view068.is_empty() and view068.get("contacts") is Array:
		combined.append_array(view068["contacts"])
	if combined.is_empty():
		return []
	var active_layer: String = str(view064.get("layer", ""))
	var active_region: String = str(view064.get("regionId", ""))
	var out: Array = []
	var seen_ids: Dictionary = {}
	for raw_c in combined:
		if not (raw_c is Dictionary):
			continue
		var vis: String = str(raw_c.get("visibility", ""))
		if vis not in ["visible", "last_known"]:
			continue
		if raw_c.get("world064") is Dictionary and not raw_c["world064"].is_empty() and not active_layer.is_empty():
			var cw: Dictionary = raw_c["world064"]
			if cw.has("layer") and str(cw["layer"]) != active_layer:
				continue
			if cw.has("regionId") and not active_region.is_empty() and str(cw["regionId"]) != active_region:
				continue
		if not _valid_point(raw_c.get("position", null)):
			continue
		var cid: String = str(raw_c.get("id", raw_c.get("ownerId", "")))
		var oid: String = str(raw_c.get("ownerId", cid))
		if cid.is_empty() or seen_ids.has(cid) or (not oid.is_empty() and seen_ids.has(oid)):
			continue
		seen_ids[cid] = true
		if not oid.is_empty():
			seen_ids[oid] = true
		var heading: float = float(raw_c["heading"]) if _is_finite_number(raw_c.get("heading", null)) else 0.0
		var unc: float = maxf(0.0, float(raw_c["uncertaintyRadius"])) if _is_finite_number(raw_c.get("uncertaintyRadius", null)) else 0.0
		var age_sec: float = maxf(0.0, float(raw_c["ageSeconds"])) if _is_finite_number(raw_c.get("ageSeconds", null)) else 0.0
		var sighted_day: float = float(raw_c["sightedDay"]) if _is_finite_number(raw_c.get("sightedDay", null)) else 0.0
		out.append({
			"id": cid,
			"ownerId": oid,
			"name": str(raw_c.get("name", "Offshore Contact")),
			"faction": str(raw_c.get("faction", "")),
			"role": str(raw_c.get("role", "trader" if oid == "patrol-7" else "raider")),
			"hostile": bool(raw_c.get("hostile", oid != "patrol-7" and str(raw_c.get("role", "")).to_lower() != "trader")),
			"visibility": vis,
			"position": {"x": float(raw_c["position"]["x"]), "y": float(raw_c["position"]["y"])},
			"heading": heading,
			"uncertaintyRadius": 0.0 if vis == "visible" else unc,
			"ageSeconds": 0.0 if vis == "visible" else age_sec,
			"sightedDay": sighted_day,
			"intentLabel": str(raw_c.get("intentLabel", "")),
			"provenance": str(raw_c.get("provenance", "")),
			"boats": _normalize_render_boats066(raw_c.get("boats", []))
		})
	return out


func _draw_dashed_world_ring(chart, center: Vector2, radius: float, color: Color, width: float = 1.25) -> void:
	var steps: int = 36
	for i in range(0, steps, 2):
		var a0: float = float(i) / float(steps) * TAU
		var a1: float = float(i + 1) / float(steps) * TAU
		var p0: Vector2 = chart.project(center + Vector2.from_angle(a0) * radius)
		var p1: Vector2 = chart.project(center + Vector2.from_angle(a1) * radius)
		chart.draw_line(p0, p1, color, width, true)


func _draw_resume_course066(chart, player_pos: Vector2, view066: Dictionary) -> void:
	if view066.is_empty():
		return
	var travel = view066.get("travel066", null)
	if not (travel is Dictionary):
		return
	var resume_path = travel.get("resumePath", null)
	if not (resume_path is Array) or resume_path.is_empty():
		return
	var previous: Vector2 = player_pos
	var drawn_any: bool = false
	for wp in resume_path:
		if not _valid_point(wp):
			continue
		var pt: Vector2 = _to_vec2(wp)
		chart.draw_dashed_line(chart.project(previous), chart.project(pt), Color(FOAM, 0.48), 1.3, 6.0, true)
		previous = pt
		drawn_any = true
	if drawn_any:
		var end_screen: Vector2 = chart.project(previous)
		chart.draw_arc(end_screen, 4.5, 0.0, TAU, 16, Color(FOAM, 0.62), 1.1, true)


func _draw_contacts066(chart, view064: Dictionary, view066: Dictionary, labels: Array, metrics: Dictionary, view068: Dictionary = {}) -> void:
	var contacts: Array = _extract_contacts066(view064, view066, view068)
	if contacts.is_empty():
		return
	var viewport_rect: Rect2 = chart.get_viewport_rect()
	var scale_val: float = _scale_factor(chart)
	var zoom_val: float = _zoom(chart)
	var ocean_layer: bool = str(view064.get("layer", "ocean")) == "ocean"
	for c in contacts:
		var vis: String = str(c["visibility"])
		var pos: Vector2 = _to_vec2(c["position"])
		var screen_pos: Vector2 = chart.project(pos)
		var heading: float = float(c["heading"])
		var hostile: bool = bool(c["hostile"])
		var is_trader: bool = not hostile and str(c.get("role", "")).to_lower() == "trader"
		var base_color: Color = ENEMY if hostile else (GOLD if is_trader else FRIEND)
		var art: Dictionary = FleetArt054.layout(
			c["boats"],
			screen_pos,
			heading,
			scale_val,
			{"viewport": viewport_rect, "overview": zoom_val < 0.7}
		)
		var bow_dir: Vector2 = Vector2.from_angle(heading)
		var r_px: float = clampf(float(art.get("hit_radius", 14.0)), 12.0, 32.0)
		if vis == "visible":
			var stats: Dictionary = FleetArt054.draw(chart, art, base_color, false)
			chart.draw_arc(screen_pos, r_px + 3.0, heading - 0.6, heading + 0.6, 12, Color(base_color, 0.72), 1.3, true)
			chart.draw_line(screen_pos + bow_dir * (r_px + 3.0), screen_pos + bow_dir * (r_px + 9.0), Color(base_color, 0.88), 1.4, true)
			metrics["contacts_drawn"] = int(metrics.get("contacts_drawn", 0)) + 1
			metrics["vessels_drawn"] = int(metrics.get("vessels_drawn", 0)) + int(stats.get("drawn_vessels", 0))
			metrics["textured_vessels"] = int(metrics.get("textured_vessels", 0)) + int(stats.get("textured_vessels", 0))
			var intent_lbl: String = str(c.get("intentLabel", "")).strip_edges()
			var role_lbl: String = str(c.get("role", "fleet")).strip_edges()
			var sub: String = intent_lbl.to_upper() if not intent_lbl.is_empty() else ("HOSTILE " + role_lbl.to_upper() if hostile else role_lbl.to_upper())
			var art_rect: Rect2 = Rect2(art.get("bounds", Rect2())).grow(4.0) if Rect2(art.get("bounds", Rect2())).has_area() else Rect2(screen_pos - Vector2(r_px, r_px), Vector2(r_px * 2.0, r_px * 2.0))
			labels.append({
				"at": screen_pos,
				"art_bounds": art_rect,
				"text": str(c["name"]),
				"subtitle": sub,
				"priority": 96,
				"color": base_color
			})
		else:
			var raw_unc: float = float(c["uncertaintyRadius"])
			var world_unc: float = raw_unc / 10.0 if (ocean_layer and raw_unc > 360.0) else raw_unc
			world_unc = clampf(world_unc, 22.0 if ocean_layer else 60.0, 320.0 if ocean_layer else 900.0)
			_draw_dashed_world_ring(chart, pos, world_unc, Color(base_color, 0.48), 1.3)
			var stats: Dictionary = FleetArt054.draw(chart, art, Color(base_color, 0.42), false)
			chart.draw_arc(screen_pos, r_px + 3.5, 0.0, TAU, 20, Color(base_color, 0.40), 1.1, true)
			chart.draw_dashed_line(screen_pos, screen_pos + bow_dir * (r_px + 11.0), Color(base_color, 0.55), 1.2, 4.0, true)
			metrics["contacts_drawn"] = int(metrics.get("contacts_drawn", 0)) + 1
			metrics["uncertain_drawn"] = int(metrics.get("uncertain_drawn", 0)) + 1
			metrics["vessels_drawn"] = int(metrics.get("vessels_drawn", 0)) + int(stats.get("drawn_vessels", 0))
			metrics["textured_vessels"] = int(metrics.get("textured_vessels", 0)) + int(stats.get("textured_vessels", 0))
			var age_s: int = maxi(0, roundi(float(c["ageSeconds"])))
			var sub: String = "LAST SIGHTED %ds AGO" % age_s
			var intent_lbl: String = str(c.get("intentLabel", "")).strip_edges()
			if not intent_lbl.is_empty():
				sub += " · " + intent_lbl.to_upper()
			var art_rect: Rect2 = Rect2(art.get("bounds", Rect2())).grow(4.0) if Rect2(art.get("bounds", Rect2())).has_area() else Rect2(screen_pos - Vector2(r_px, r_px), Vector2(r_px * 2.0, r_px * 2.0))
			labels.append({
				"at": screen_pos,
				"art_bounds": art_rect,
				"text": str(c["name"]),
				"subtitle": sub,
				"priority": 94,
				"color": Color(base_color, 0.84)
			})


func pick_contact(chart, view_or_ocean066: Dictionary, screen_or_ocean066, maybe_screen = null, maybe_shipping068 = null) -> Dictionary:
	if chart == null:
		return {}
	var view064: Dictionary = {}
	var view066: Dictionary = {}
	var screen := Vector2.INF
	if maybe_screen is Vector2:
		view064 = view_or_ocean066
		if screen_or_ocean066 is Dictionary:
			view066 = screen_or_ocean066
		screen = maybe_screen
	elif screen_or_ocean066 is Vector2:
		screen = screen_or_ocean066
		if view_or_ocean066.has("contacts") and not view_or_ocean066.has("layer"):
			view066 = view_or_ocean066
			var h = chart.get("host")
			if h != null and h.get("core") != null and h.core is Object and h.core.has_method("world_view064"):
				var v64 = h.core.world_view064()
				if v64 is Dictionary:
					view064 = v64
		else:
			view064 = view_or_ocean066
			view066 = _resolve_ocean_view066(chart, null)
			if view066.is_empty() and view_or_ocean066.has("contacts"):
				view066 = view_or_ocean066
	else:
		return {}
	if not screen.is_finite():
		return {}
	var view068: Dictionary = _resolve_shipping_view068(chart, maybe_shipping068)
	var contacts: Array = _extract_contacts066(view064, view066, view068)
	if contacts.is_empty():
		return {}
	var viewport_rect: Rect2 = chart.get_viewport_rect()
	var scale_val: float = _scale_factor(chart)
	var zoom_val: float = _zoom(chart)
	for pass_vis in ["visible", "last_known"]:
		var best_c: Dictionary = {}
		var best_dist: float = INF
		for c in contacts:
			if str(c["visibility"]) != pass_vis:
				continue
			var pos: Vector2 = _to_vec2(c["position"])
			var screen_pos: Vector2 = chart.project(pos)
			var art: Dictionary = FleetArt054.layout(
				c["boats"],
				screen_pos,
				float(c["heading"]),
				scale_val,
				{"viewport": viewport_rect, "overview": zoom_val < 0.7}
			)
			var art_bounds: Rect2 = Rect2(art.get("bounds", Rect2()))
			var hit_radius: float = clampf(float(art.get("hit_radius", 16.0)) + (4.0 if pass_vis == "visible" else 8.0), 16.0, 36.0)
			var dist: float = screen_pos.distance_to(screen)
			var inside_bounds: bool = art_bounds.has_area() and art_bounds.grow(4.0).has_point(screen)
			if inside_bounds or dist <= hit_radius:
				if dist < best_dist:
					best_dist = dist
					best_c = c
		if not best_c.is_empty():
			return {
				"kind": "contact",
				"contactId": str(best_c["id"]),
				"ownerId": str(best_c["ownerId"]),
				"visibility": str(best_c["visibility"])
			}
	return {}


func world_bounds(view: Dictionary) -> Rect2:
	if not _valid_view(view, false):
		return Rect2()
	var b: Dictionary = view["bounds"]
	return Rect2(float(b["x"]), float(b["y"]), float(b["width"]), float(b["height"]))


func content_bounds(view: Dictionary) -> Rect2:
	var fallback: Rect2 = world_bounds(view)
	if fallback.size.x <= 0.0 or fallback.size.y <= 0.0:
		return Rect2()
	var layer: String = str(view.get("layer", ""))
	var rect := Rect2()
	var first: bool = true
	if layer == "ocean":
		var regions = view.get("regions", [])
		if regions is Array:
			for rv in regions:
				if not (rv is Dictionary):
					continue
				for ring in rv.get("silhouettes", []):
					for p in _extract_silhouette_pairs(ring):
						var pt := Vector2(float(p[0]), float(p[1]))
						if first:
							rect = Rect2(pt, Vector2.ONE)
							first = false
						else:
							rect = rect.expand(pt)
				for av in rv.get("approaches", []):
					if _valid_approach(av):
						var pt := _to_vec2(av["position"])
						if first:
							rect = Rect2(pt, Vector2.ONE)
							first = false
						else:
							rect = rect.expand(pt)
	else:
		var islands = view.get("islands", [])
		if islands is Array:
			for isl in islands:
				if not (isl is Dictionary):
					continue
				for p in _extract_island_pairs(isl.get("points", [])):
					var pt := Vector2(float(p[0]), float(p[1]))
					if first:
						rect = Rect2(pt, Vector2.ONE)
						first = false
					else:
						rect = rect.expand(pt)
		var approaches = view.get("approaches", [])
		if approaches is Array:
			for av in approaches:
				if _valid_approach(av):
					var pt := _to_vec2(av["position"])
					if first:
						rect = Rect2(pt, Vector2.ONE)
						first = false
					else:
						rect = rect.expand(pt)
	return rect if not first else fallback


static func _local_cache_key(layer: String, region_id: String, bounds_rect: Rect2, islands: Array) -> String:
	var parts: Array = [
		layer,
		region_id,
		"%.1f,%.1f,%.1f,%.1f" % [bounds_rect.position.x, bounds_rect.position.y, bounds_rect.size.x, bounds_rect.size.y],
		str(islands.size())
	]
	for isl in islands:
		var pairs: Array = _extract_island_pairs(isl.get("points", []))
		var first_pt: String = "%.1f:%.1f" % [float(pairs[0][0]), float(pairs[0][1])] if not pairs.is_empty() else ""
		var last_pt: String = "%.1f:%.1f" % [float(pairs[-1][0]), float(pairs[-1][1])] if not pairs.is_empty() else ""
		parts.append("%s#%d#%s#%s" % [str(isl.get("id", "")), pairs.size(), first_pt, last_pt])
	return ":".join(parts)


func prepare_local_region(view: Dictionary) -> Dictionary:
	if not _valid_view(view, false):
		return {}
	var layer: String = str(view["layer"])
	var region_id: String = str(view["regionId"])
	if layer != "local":
		return {}
	var islands = view.get("islands", null)
	if not (islands is Array) or islands.is_empty():
		return {}
	for isl in islands:
		if not _valid_island_record(isl, true):
			return {}
	var bounds_rect: Rect2 = world_bounds(view)
	var cache_key: String = _local_cache_key(layer, region_id, bounds_rect, islands)
	if _local_region_cache.has(cache_key):
		return _local_region_cache[cache_key]
	var sheets: Array = []
	for i in range(islands.size()):
		var isl: Dictionary = islands[i]
		var pairs: Array = _extract_island_pairs(isl.get("points", []))
		var normalized: Dictionary = {
			"id": str(isl["id"]),
			"name": str(isl["name"]),
			"color": str(isl.get("color", "")),
			"points": pairs
		}
		var sheet: Dictionary = CoastArt050.prepare_island(normalized)
		sheet["regionId"] = region_id
		sheet["layer"] = layer
		sheets.append(sheet)
	var entry: Dictionary = {
		"cacheKey": cache_key,
		"layer": layer,
		"regionId": region_id,
		"name": str(view.get("name", region_id)),
		"bounds": bounds_rect,
		"sheets": sheets
	}
	if _local_region_cache.size() >= LOCAL_CACHE_LIMIT:
		_local_region_cache.erase(_local_region_cache.keys()[0])
	_local_region_cache[cache_key] = entry
	return entry


static func _ocean_cache_key(rv: Dictionary) -> String:
	var region_id: String = str(rv.get("regionId", ""))
	var layer: String = str(rv.get("layer", ""))
	var silhouettes: Array = rv.get("silhouettes", [])
	var parts: Array = ["ocean", layer, region_id, str(silhouettes.size())]
	for ring in silhouettes:
		var pairs: Array = _extract_silhouette_pairs(ring)
		var first_pt: String = "%.1f:%.1f" % [float(pairs[0][0]), float(pairs[0][1])] if not pairs.is_empty() else ""
		var last_pt: String = "%.1f:%.1f" % [float(pairs[-1][0]), float(pairs[-1][1])] if not pairs.is_empty() else ""
		parts.append("%d#%s#%s" % [pairs.size(), first_pt, last_pt])
	return ":".join(parts)


static func _compact_ocean_reef(land: PackedVector2Array) -> PackedVector2Array:
	var reef := PackedVector2Array()
	var n: int = land.size()
	if n < 3:
		return reef
	for i in range(0, n, 3):
		if reef.size() >= 24:
			break
		var a: Vector2 = land[i]
		var b: Vector2 = land[(i + 1) % n]
		var seg: Vector2 = b - a
		if seg.length_squared() < 4.0:
			continue
		var middle: Vector2 = (a + b) * 0.5
		var along: Vector2 = seg.normalized()
		var outward: Vector2 = -seg.orthogonal().normalized()
		if Geometry2D.is_point_in_polygon(middle + outward * 2.0, land):
			outward = -outward
		var at: Vector2 = middle + outward * (7.5 + float(i % 2) * 2.5)
		reef.append(at - along * 4.5)
		reef.append(at + along * 4.5)
	return reef


func _prepare_ocean_region(rv: Dictionary) -> Dictionary:
	if not _valid_region_view(rv):
		return {}
	var cache_key: String = _ocean_cache_key(rv)
	if _ocean_region_cache.has(cache_key):
		return _ocean_region_cache[cache_key]
	var region_id: String = str(rv["regionId"])
	var region_name: String = str(rv["name"])
	var region_layer: String = str(rv["layer"])
	var silhouettes: Array = rv["silhouettes"]
	var sheets: Array = []
	var polygons: Array = []
	var group_bounds := Rect2()
	var has_bounds: bool = false
	for i in range(silhouettes.size()):
		var pairs: Array = _extract_silhouette_pairs(silhouettes[i])
		if pairs.size() < 3:
			continue
		var profile_id: String = HOME_ISLAND_IDS[i % HOME_ISLAND_IDS.size()] if region_id == "shatter_coast" else "%s_ocean_%d" % [region_id, i]
		var sheet: Dictionary = CoastArt050.prepare_island({
			"id": profile_id,
			"name": region_name,
			"points": pairs
		})
		sheet["id"] = "%s_silhouette_%d" % [region_id, i]
		sheet["regionId"] = region_id
		sheet["layer"] = "ocean"
		sheet["reef"] = _compact_ocean_reef(sheet.get("land", PackedVector2Array()))
		var land_poly: PackedVector2Array = sheet.get("land", PackedVector2Array())
		var poly_bounds: Rect2 = CoastArt050._bounds(land_poly)
		sheet["bounds"] = poly_bounds.grow(14.0)
		sheets.append(sheet)
		polygons.append(land_poly)
		if not has_bounds:
			group_bounds = poly_bounds
			has_bounds = true
		else:
			group_bounds = group_bounds.merge(poly_bounds)
	if sheets.is_empty():
		return {}
	var entry: Dictionary = {
		"cacheKey": cache_key,
		"regionId": region_id,
		"name": region_name,
		"layer": region_layer,
		"sheets": sheets,
		"polygons": polygons,
		"group_bounds": group_bounds,
		"group_center": group_bounds.get_center()
	}
	if _ocean_region_cache.size() >= OCEAN_CACHE_LIMIT:
		_ocean_region_cache.erase(_ocean_region_cache.keys()[0])
	_ocean_region_cache[cache_key] = entry
	return entry


static func _collect_ocean_approaches(view: Dictionary) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var regions = view.get("regions", [])
	if regions is Array:
		for rv in regions:
			if not (rv is Dictionary):
				continue
			var r_id: String = str(rv.get("regionId", ""))
			var r_apps = rv.get("approaches", [])
			if not (r_apps is Array):
				continue
			for av in r_apps:
				if not _valid_approach(av, r_id):
					continue
				var key: String = "%s:%s" % [str(av["regionId"]), str(av["id"])]
				if not seen.has(key):
					seen[key] = true
					out.append(av)
	var top_apps = view.get("approaches", [])
	if top_apps is Array:
		for av in top_apps:
			if not _valid_approach(av):
				continue
			var key: String = "%s:%s" % [str(av["regionId"]), str(av["id"])]
			if not seen.has(key):
				seen[key] = true
				out.append(av)
	return out


static func _rect_area(value) -> float:
	if not (value is Rect2):
		return 0.0
	return value.size.x * value.size.y


static func _silhouette_bounds(rv: Dictionary) -> Rect2:
	var rect := Rect2()
	var first: bool = true
	for ring in rv.get("silhouettes", []):
		for pair in _extract_silhouette_pairs(ring):
			var point := Vector2(float(pair[0]), float(pair[1]))
			if first:
				rect = Rect2(point, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(point)
	return rect


func _group_on_screen(chart, world_rect: Rect2) -> bool:
	if chart == null or not world_rect.has_area():
		return false
	var screen_rect: Rect2 = _project_rect(chart, world_rect.grow(36.0))
	return chart.get_viewport_rect().grow(64.0).intersects(screen_rect)


func _draw_faction_segments(chart, center: Vector2, world_radius: float, parts: Array) -> void:
	if parts.is_empty() or not center.is_finite():
		return
	var total: float = 0.0
	for part in parts:
		total += float(part.get("weight", 0.0))
	if total <= 0.0:
		return
	var screen_center: Vector2 = chart.project(center)
	var screen_radius: float = clampf(world_radius * _scale_factor(chart), 14.0, 78.0)
	var cursor: float = -PI * 0.5
	var gap: float = 0.12 if parts.size() > 1 else 0.0
	for part in parts:
		var sweep: float = TAU * float(part.get("weight", 0.0)) / total
		var start: float = cursor + gap * 0.5
		var finish: float = cursor + sweep - gap * 0.5
		if finish > start:
			chart.draw_arc(screen_center, screen_radius, start, finish, 18, part.get("color", GOLD), 2.6, true)
		cursor += sweep


func pick_region(view: Dictionary, world_position: Vector2) -> Dictionary:
	if not world_position.is_finite() or not _valid_view(view, false):
		return {}
	var bounds_rect: Rect2 = world_bounds(view)
	if not bounds_rect.grow(120.0).has_point(world_position):
		return {}
	var layer: String = str(view["layer"])
	var active_region_id: String = str(view["regionId"])
	if layer == "local" or layer == "home":
		var approaches = view.get("approaches", null)
		if not (approaches is Array):
			return {}
		var best_av: Dictionary = {}
		var best_dist: float = INF
		for av in approaches:
			if not _valid_approach(av, active_region_id):
				continue
			var center: Vector2 = _to_vec2(av["position"])
			var radius: float = float(av["radius"])
			var dist: float = world_position.distance_to(center)
			if dist <= radius and dist < best_dist:
				best_dist = dist
				best_av = av
		if not best_av.is_empty():
			return {
				"regionId": str(best_av["regionId"]),
				"approachId": str(best_av["id"]),
				"kind": "approach"
			}
		return {}
	if layer != "ocean":
		return {}
	var regions = view.get("regions", null)
	if not _ocean_regions_ok(regions):
		return {}
	var ocean_approaches: Array = _collect_ocean_approaches(view)
	# 1. Exact AV.radius hit takes highest priority.
	var best_exact_av: Dictionary = {}
	var best_exact_dist: float = INF
	for av in ocean_approaches:
		var center: Vector2 = _to_vec2(av["position"])
		var radius: float = float(av["radius"])
		var dist: float = world_position.distance_to(center)
		if dist <= radius and dist < best_exact_dist:
			best_exact_dist = dist
			best_exact_av = av
	if not best_exact_av.is_empty():
		return {
			"regionId": str(best_exact_av["regionId"]),
			"approachId": str(best_exact_av["id"]),
			"kind": "approach"
		}
	# 2. Direct interior hit on any published silhouette.
	for rv in regions:
		var rough: Rect2 = _silhouette_bounds(rv)
		if rough.has_area() and not rough.grow(8.0).has_point(world_position):
			continue
		var reg_plan: Dictionary = _prepare_ocean_region(rv)
		if reg_plan.is_empty():
			continue
		for poly: PackedVector2Array in reg_plan.get("polygons", []):
			if Geometry2D.is_point_in_polygon(world_position, poly):
				return {
					"regionId": str(rv["regionId"]),
					"approachId": "",
					"kind": "region"
				}
	return {}


static func _empty_metrics(layer: String = "", region_id: String = "", delegate_home: bool = false) -> Dictionary:
	return {
		"ok": delegate_home,
		"delegate_home": delegate_home,
		"layer": layer,
		"regionId": region_id,
		"regions_drawn": 0,
		"islands_drawn": 0,
		"vessels_drawn": 0,
		"textured_vessels": 0,
		"approaches_drawn": 0,
		"coast_draw_calls": 0,
		"zones_drawn": 0,
		"contacts_drawn": 0,
		"uncertain_drawn": 0,
		"sites_drawn": 0,
		"wrecks_drawn": 0,
		"leads_drawn": 0,
		"ports_drawn": 0
	}


func _ensure_chart_fonts(chart) -> void:
	if _fallback_font == null:
		_fallback_font = SystemFont.new()
		_fallback_font.font_names = PackedStringArray(["Consolas", "Bahnschrift", "Segoe UI"])
	if chart.get("sans") == null:
		chart.set("sans", _fallback_font)
	if chart.get("mono") == null:
		chart.set("mono", _fallback_font)
	if chart.get("serif") == null:
		chart.set("serif", _fallback_font)


static func _scale_factor(chart) -> float:
	var raw = chart.get("scale_factor") if chart != null else null
	return maxf(0.05, float(raw)) if _is_finite_number(raw) else 0.36


static func _zoom(chart) -> float:
	var raw = chart.get("zoom") if chart != null else null
	return maxf(0.05, float(raw)) if _is_finite_number(raw) else 1.0


static func _project_rect(chart, world_rect: Rect2) -> Rect2:
	var p0: Vector2 = chart.project(world_rect.position)
	var out := Rect2(p0, Vector2.ZERO)
	for corner in [
		Vector2(world_rect.end.x, world_rect.position.y),
		world_rect.end,
		Vector2(world_rect.position.x, world_rect.end.y)
	]:
		out = out.expand(chart.project(corner))
	return out


func _draw_graticule(chart, bounds_rect: Rect2, overview: bool, major_step: int = 1000, minor_step: int = 500) -> void:
	var x0: int = int(bounds_rect.position.x)
	var y0: int = int(bounds_rect.position.y)
	var x1: int = int(bounds_rect.end.x)
	var y1: int = int(bounds_rect.end.y)
	for x in range(x0, x1 + 1, major_step):
		chart.world_line([Vector2(x, y0), Vector2(x, y1)], Color(0.6, 0.8, 0.69, 0.028))
	for y in range(y0, y1 + 1, major_step):
		chart.world_line([Vector2(x0, y), Vector2(x1, y)], Color(0.6, 0.8, 0.69, 0.028))
	if not overview and minor_step > 0:
		for x in range(x0 + minor_step, x1, major_step):
			chart.world_line([Vector2(x, y0), Vector2(x, y1)], Color(0.6, 0.8, 0.69, 0.018))
		for y in range(y0 + minor_step, y1, major_step):
			chart.world_line([Vector2(x0, y), Vector2(x1, y)], Color(0.6, 0.8, 0.69, 0.018))
	chart.world_line([
		bounds_rect.position,
		Vector2(bounds_rect.end.x, bounds_rect.position.y),
		bounds_rect.end,
		Vector2(bounds_rect.position.x, bounds_rect.end.y),
		bounds_rect.position
	], Color(0.69, 0.79, 0.65, 0.16), 1.1)


func _draw_course(chart, position: Vector2, path: Array) -> void:
	if path.is_empty():
		return
	var previous: Vector2 = position
	for step_point in path:
		if not _valid_point(step_point):
			continue
		var point: Vector2 = _to_vec2(step_point)
		chart.draw_dashed_line(chart.project(previous), chart.project(point), Color(GOLD, 0.78), 1.5, 5.0, true)
		previous = point
	var end_screen: Vector2 = chart.project(previous)
	chart.draw_arc(end_screen, 5.5, 0.0, TAU, 20, Color(GOLD, 0.82), 1.2, true)


func _draw_approach_gate(chart, av: Dictionary, destination: String, ocean_layer: bool, labels: Array) -> void:
	var region_id: String = str(av["regionId"])
	var approach_id: String = str(av["id"])
	var pos: Vector2 = _to_vec2(av["position"])
	var radius: float = float(av["radius"])
	var target_key: String = "approach:%s:%s" % [region_id, approach_id]
	var selected: bool = (destination == target_key)
	var color: Color = GOLD if selected else FOAM
	var screen_pos: Vector2 = chart.project(pos)
	var scale_val: float = _scale_factor(chart)
	var screen_radius: float = clampf(radius * scale_val, 9.0 if ocean_layer else 12.0, 42.0)
	chart.world_ring(pos, radius, Color(color, 0.75 if selected else 0.48), 1.4 if selected else 1.1)
	chart.draw_arc(screen_pos, screen_radius, -0.85, 0.85, 14, Color(color, 0.85), 1.5 if selected else 1.2, true)
	chart.draw_arc(screen_pos, screen_radius, PI - 0.85, PI + 0.85, 14, Color(color, 0.85), 1.5 if selected else 1.2, true)
	var dir_y: float = -1.0 if approach_id == "north" else 1.0
	var tip: Vector2 = screen_pos + Vector2(0.0, dir_y * (screen_radius + 5.0))
	chart.draw_colored_polygon(PackedVector2Array([
		tip,
		screen_pos + Vector2(-4.0, dir_y * (screen_radius - 2.0)),
		screen_pos + Vector2(4.0, dir_y * (screen_radius - 2.0))
	]), Color(color, 0.88))
	var gate_title: String = str(av["name"])
	if ocean_layer:
		gate_title = "%s · %s" % [str(av["name"]), "NORTH" if approach_id == "north" else "SOUTH"]
	labels.append({
		"at": screen_pos,
		"art_bounds": Rect2(screen_pos - Vector2(screen_radius, screen_radius), Vector2(screen_radius * 2.0, screen_radius * 2.0)),
		"text": gate_title,
		"subtitle": "COURSE TARGET" if selected else ("COASTAL ENTRY" if ocean_layer else "OCEAN APPROACH"),
		"priority": 100 if selected else (68 if ocean_layer else 74),
		"color": color
	})


func draw_approaches(chart, view: Dictionary, labels: Array = []) -> int:
	if chart == null or not _valid_view(view, false):
		return 0
	var layer: String = str(view["layer"])
	var region_id: String = str(view["regionId"])
	var destination: String = str(view.get("destination", ""))
	var count: int = 0
	if layer == "ocean":
		var gate_view: Rect2 = chart.get_viewport_rect().grow(80.0)
		for av in _collect_ocean_approaches(view):
			if not gate_view.has_point(chart.project(_to_vec2(av["position"]))):
				continue
			_draw_approach_gate(chart, av, destination, true, labels)
			count += 1
	else:
		var approaches = view.get("approaches", [])
		if approaches is Array:
			for av in approaches:
				if not _valid_approach(av, region_id):
					continue
				_draw_approach_gate(chart, av, destination, false, labels)
				count += 1
	return count


func _draw_scale_bar(chart, viewport_size: Vector2, ocean_layer: bool) -> void:
	var scale_val: float = _scale_factor(chart)
	var world_units: float = 400.0 if ocean_layer else 500.0
	var bar_px: float = clampf(world_units * scale_val, 56.0, 160.0)
	var origin := Vector2(viewport_size.x - 230.0, viewport_size.y - 118.0)
	var bar_color := Color(0.69, 0.79, 0.65, 0.55)
	chart.draw_line(origin, origin + Vector2(bar_px, 0.0), bar_color, 1.4, true)
	chart.draw_line(origin - Vector2(0.0, 4.0), origin + Vector2(0.0, 4.0), bar_color, 1.4, true)
	chart.draw_line(origin + Vector2(bar_px * 0.5, -3.0), origin + Vector2(bar_px * 0.5, 3.0), bar_color, 1.1, true)
	chart.draw_line(origin + Vector2(bar_px, -4.0), origin + Vector2(bar_px, 4.0), bar_color, 1.4, true)
	var caption: String = "1 : 10 OCEAN SCALE" if ocean_layer else "LOCAL COASTAL SCALE"
	chart.text_at(caption, origin + Vector2(bar_px * 0.5, -8.0), 9, Color(0.74, 0.84, 0.75, 0.68), chart.get("mono"), true)


func _record_coast_profile(chart, calls: int, started_usec: int) -> void:
	if not bool(chart.get("_profile_drawing")):
		return
	var pf = chart.get("_profile_frame")
	if pf is Dictionary:
		pf["coast_draw_calls"] = int(pf.get("coast_draw_calls", 0)) + calls
		pf["coast_us"] = int(pf.get("coast_us", 0)) + (Time.get_ticks_usec() - started_usec)


func _draw_local_layer(chart, view: Dictionary, view066: Dictionary = {}, view067: Dictionary = {}, view068: Dictionary = {}, sector = null) -> Dictionary:
	var region_id: String = str(view["regionId"])
	var metrics: Dictionary = _empty_metrics("local", region_id, false)
	var region_plan: Dictionary = prepare_local_region(view)
	if region_plan.is_empty():
		return metrics
	_ensure_chart_fonts(chart)
	var viewport_rect: Rect2 = chart.get_viewport_rect()
	var overview: bool = bool(chart.campaign_overview())
	var projector: Callable = chart._projector()
	var scale_val: float = _scale_factor(chart)
	var zoom_val: float = _zoom(chart)
	var bounds_rect: Rect2 = region_plan["bounds"]
	var labels: Array = []
	var sector_on: bool = _sector_schema1(sector)
	var own_islands: Dictionary = {}
	if not sector_on:
		var legacy_islands = _extract_ownership068(view068).get("islands", {})
		if legacy_islands is Dictionary:
			own_islands = legacy_islands
	_draw_graticule(chart, bounds_rect, overview, 1000, 500)
	metrics["zones_drawn"] = _draw_zones066(chart, view, view066, labels)
	var sheets: Array = region_plan["sheets"]
	var islands: Array = view["islands"]
	for i in range(sheets.size()):
		var sheet: Dictionary = sheets[i]
		var sheet_bounds = sheet.get("bounds", null)
		if sheet_bounds is Rect2 and sheet_bounds.has_area() and not _group_on_screen(chart, sheet_bounds):
			continue
		var started: int = Time.get_ticks_usec() if bool(chart.get("_profile_drawing")) else 0
		var calls: int = NauticalArt.draw(chart, projector, sheet.land, sheet, not overview, scale_val, viewport_rect)
		_record_coast_profile(chart, calls, started)
		metrics["coast_draw_calls"] = int(metrics["coast_draw_calls"]) + calls
		metrics["islands_drawn"] = int(metrics["islands_drawn"]) + 1
		var isl_id: String = str(islands[i].get("id", sheet.get("id", ""))) if i < islands.size() else str(sheet.get("id", ""))
		var isl_name: String = str(islands[i].get("name", sheet.get("name", ""))) if i < islands.size() else str(sheet.get("name", ""))
		if not isl_name.is_empty():
			var isl_sub: String = ""
			var fac: String = _sector_island_faction(sector, region_id, isl_id) if sector_on else ""
			if fac.is_empty() and not sector_on and region_id == GLASSWIND_REGION_ID and own_islands.has(isl_id):
				var legacy_fac: String = str(own_islands[isl_id].get("faction", "")).to_lower()
				if legacy_fac == "reed":
					fac = "reed"
			if fac == "reed" and region_id == GLASSWIND_REGION_ID:
				isl_sub = "REEDWATER BRANCH HOLDING"
			elif FACTION_LABEL.has(fac):
				isl_sub = "KNOWN %s HOLDING" % str(FACTION_LABEL[fac])
			if FACTION_COLOR.has(fac):
				chart.draw_arc(chart.project(sheet.label), 14.0, -2.2, 2.2, 16, FACTION_COLOR[fac], 2.2, true)
			labels.append({
				"at": chart.project(sheet.label),
				"art_bounds": _project_rect(chart, sheet.bounds),
				"text": isl_name,
				"subtitle": isl_sub,
				"priority": 45,
				"color": Color("c4d2b0")
			})
	metrics["approaches_drawn"] = draw_approaches(chart, view, labels)
	_draw_local_sites_and_wrecks067(chart, view, _sites_view(view, view067, sector), labels, metrics)
	_draw_local_ports068(chart, view, view068, labels, metrics, sector)
	var player_pos: Vector2 = _to_vec2(view["position"])
	_draw_resume_course066(chart, player_pos, view066)
	_draw_course(chart, player_pos, view["path"])
	_draw_contacts066(chart, view, view066, labels, metrics, view068)
	var marker: Vector2 = chart.project(player_pos)
	var player_art: Dictionary = FleetArt054.layout(
		view["boats"],
		marker,
		float(view["heading"]),
		scale_val,
		{"viewport": viewport_rect, "overview": zoom_val < 0.7}
	)
	var fleet_stats: Dictionary = FleetArt054.draw(chart, player_art, GOLD, true)
	metrics["vessels_drawn"] = int(metrics["vessels_drawn"]) + int(fleet_stats.get("drawn_vessels", 0))
	metrics["textured_vessels"] = int(metrics["textured_vessels"]) + int(fleet_stats.get("textured_vessels", 0))
	if not player_art.get("vessels", []).is_empty():
		labels.append({
			"at": marker,
			"art_bounds": Rect2(player_art.bounds).grow(5.0),
			"text": "YOUR FLOTILLA",
			"priority": 105,
			"color": GOLD
		})
	chart._draw_chart_labels(labels)
	var size: Vector2 = viewport_rect.size
	var title_text: String = str(view.get("name", "GLASSWIND KEYS" if region_id == GLASSWIND_REGION_ID else "COASTAL WATERS")).to_upper()
	chart.text_at(title_text, Vector2(size.x * 0.5, size.y - 175.0), 12, GOLD, chart.get("mono"), true)
	chart.text_at("WASD CAMERA  ·  I SURVEYS  ·  M TERRITORY  ·  CLICK HARBOR, LANDING, WRECK, CONTACT OR WATER  ·  SCROLL ZOOM", Vector2(size.x * 0.5, size.y - 118.0), 10, Color("93b4a8"), chart.get("mono"), true)
	_draw_scale_bar(chart, size, false)
	chart.draw_compass(Vector2(size.x - 70.0, size.y - 133.0))
	metrics["ok"] = true
	metrics["regions_drawn"] = 1
	return metrics


func _draw_ocean_layer(chart, view: Dictionary, view066: Dictionary = {}, view067: Dictionary = {}, view068: Dictionary = {}, sector = null) -> Dictionary:
	var metrics: Dictionary = _empty_metrics("ocean", "open_ocean", false)
	_ensure_chart_fonts(chart)
	var viewport_rect: Rect2 = chart.get_viewport_rect()
	var overview: bool = bool(chart.campaign_overview())
	var projector: Callable = chart._projector()
	var scale_val: float = _scale_factor(chart)
	var zoom_val: float = _zoom(chart)
	var bounds_rect: Rect2 = world_bounds(view)
	var labels: Array = []
	var sector_on: bool = _sector_schema1(sector)
	var sector_groups: Dictionary = _sector_groups(sector) if sector_on else {}
	var own_regions: Dictionary = {}
	if not sector_on:
		var legacy_regions = _extract_ownership068(view068).get("regions", {})
		if legacy_regions is Dictionary:
			own_regions = legacy_regions
	_draw_graticule(chart, bounds_rect, overview, 800, 400)
	metrics["zones_drawn"] = _draw_zones066(chart, view, view066, labels)
	var regions: Array = view["regions"]
	var generated_atlas: bool = regions.size() == GENERATED_REGION_COUNT
	var region_centers: Array = []
	for rv in regions:
		var rough: Rect2 = _silhouette_bounds(rv)
		if not _group_on_screen(chart, rough):
			continue
		var reg_plan: Dictionary = _prepare_ocean_region(rv)
		if reg_plan.is_empty():
			return _empty_metrics("ocean", "open_ocean", false)
		var group_bounds: Rect2 = reg_plan["group_bounds"].grow(28.0)
		var group_center: Vector2 = reg_plan["group_center"]
		region_centers.append(group_center)
		var ring_radius: float = maxf(group_bounds.size.x, group_bounds.size.y) * 0.52
		chart.world_ring(group_center, ring_radius, Color(0.58, 0.78, 0.70, 0.14), 1.0)
		var sheets: Array = reg_plan["sheets"]
		if generated_atlas and overview and sheets.size() > 1:
			var largest: Dictionary = sheets[0]
			var largest_area: float = _rect_area(largest.get("bounds", null))
			for candidate in sheets:
				var area: float = _rect_area(candidate.get("bounds", null))
				if area > largest_area:
					largest = candidate
					largest_area = area
			sheets = [largest]
		for sheet: Dictionary in sheets:
			var started: int = Time.get_ticks_usec() if bool(chart.get("_profile_drawing")) else 0
			var calls: int = NauticalArt.draw(
				chart,
				projector,
				sheet.land,
				sheet,
				true,
				maxf(scale_val, 0.30),
				viewport_rect
			)
			_record_coast_profile(chart, calls, started)
			metrics["coast_draw_calls"] = int(metrics["coast_draw_calls"]) + calls
			metrics["islands_drawn"] = int(metrics["islands_drawn"]) + 1
		metrics["regions_drawn"] = int(metrics["regions_drawn"]) + 1
		var is_home_group: bool = str(rv["layer"]) == "home"
		var rv_reg_id: String = str(rv.get("regionId", ""))
		var known_line: String = _ownership_line(sector_groups.get(rv_reg_id, {}))
		var group_sub: String = ""
		var segment_parts: Array = _segment_parts(_known_group(sector_groups.get(rv_reg_id, {}))) if sector_on else []
		if is_home_group:
			group_sub = "HOME WATERS"
		elif rv_reg_id == GLASSWIND_REGION_ID:
			if not known_line.is_empty():
				group_sub = "REMOTE KEYS · %s" % known_line
			elif not sector_on:
				var legacy_line: String = _legacy_holding_line(own_regions.get(rv_reg_id, []))
				group_sub = "REMOTE KEYS · %s" % legacy_line if not legacy_line.is_empty() else "REMOTE KEYS"
				segment_parts = _legacy_segment_parts(own_regions.get(rv_reg_id, []))
			else:
				group_sub = "REMOTE KEYS"
		else:
			group_sub = known_line
		_draw_faction_segments(chart, group_center, ring_radius, segment_parts)
		var group_screen: Vector2 = chart.project(group_center)
		var group_screen_bounds: Rect2 = _project_rect(chart, reg_plan["group_bounds"])
		labels.append({
			"at": group_screen,
			"art_bounds": group_screen_bounds,
			"text": str(rv["name"]).to_upper(),
			"subtitle": group_sub,
			"priority": 92 if is_home_group else (88 if rv_reg_id == GLASSWIND_REGION_ID else 76),
			"color": GOLD if is_home_group else Color("d7e1cc")
		})
	if regions.size() == LEGACY_REGION_COUNT and region_centers.size() == 2:
		chart.draw_dashed_line(
			chart.project(region_centers[0]),
			chart.project(region_centers[1]),
			Color(0.64, 0.80, 0.65, 0.11),
			1.0,
			6.0,
			true
		)
	metrics["approaches_drawn"] = draw_approaches(chart, view, labels)
	_draw_local_sites_and_wrecks067(chart, view, view067, labels, metrics)
	var player_pos: Vector2 = _to_vec2(view["position"])
	_draw_resume_course066(chart, player_pos, view066)
	_draw_course(chart, player_pos, view["path"])
	_draw_contacts066(chart, view, view066, labels, metrics, view068)
	var marker: Vector2 = chart.project(player_pos)
	var player_art: Dictionary = FleetArt054.layout(
		view["boats"],
		marker,
		float(view["heading"]),
		scale_val,
		{"viewport": viewport_rect, "overview": zoom_val < 0.7}
	)
	var fleet_stats: Dictionary = FleetArt054.draw(chart, player_art, GOLD, true)
	metrics["vessels_drawn"] = int(metrics["vessels_drawn"]) + int(fleet_stats.get("drawn_vessels", 0))
	metrics["textured_vessels"] = int(metrics["textured_vessels"]) + int(fleet_stats.get("textured_vessels", 0))
	var travel066: Dictionary = view066.get("travel066", {}) if view066.get("travel066") is Dictionary else {}
	var mode066: String = str(travel066.get("mode", "direct")).to_upper()
	var player_sub: String = ""
	if mode066 in ["INVESTIGATE", "AVOID", "DIVERT"]:
		player_sub = "COURSE: " + mode066
	if not player_art.get("vessels", []).is_empty():
		labels.append({
			"at": marker,
			"art_bounds": Rect2(player_art.bounds).grow(5.0),
			"text": "YOUR FLOTILLA",
			"subtitle": player_sub,
			"priority": 105,
			"color": GOLD
		})
	chart._draw_chart_labels(labels)
	var size: Vector2 = viewport_rect.size
	var active_zone_summary: String = str(travel066.get("activeZoneSummary", "")).strip_edges()
	if not active_zone_summary.is_empty():
		chart.text_at(active_zone_summary.to_upper(), Vector2(size.x * 0.5, size.y - 196.0), 10, FOAM, chart.get("mono"), true)
	chart.text_at(str(view.get("name", "OPEN OCEAN")).to_upper(), Vector2(size.x * 0.5, size.y - 175.0), 12, GOLD, chart.get("mono"), true)
	chart.text_at("WASD CAMERA  ·  M TERRITORY  ·  HOME FLEET  ·  CLICK CONTACT, APPROACH OR WATER  ·  SCROLL ZOOM", Vector2(size.x * 0.5, size.y - 118.0), 10, Color("93b4a8"), chart.get("mono"), true)
	_draw_scale_bar(chart, size, true)
	chart.draw_compass(Vector2(size.x - 70.0, size.y - 133.0))
	metrics["ok"] = true
	return metrics


func draw(chart, view: Dictionary, ocean_view066 = null, exploration_view067 = null, shipping_view068 = null, sector_view069 = null) -> Dictionary:
	if chart == null or not _valid_view(view, true):
		return _empty_metrics()
	var view066: Dictionary = _resolve_ocean_view066(chart, ocean_view066)
	var view067: Dictionary = _resolve_exploration_view067(chart, exploration_view067)
	var view068: Dictionary = _resolve_shipping_view068(chart, shipping_view068)
	var sector: Dictionary = _resolve_sector_view069(chart, sector_view069)
	var layer: String = str(view["layer"])
	if layer == "home":
		return _empty_metrics("home", "shatter_coast", true)
	if layer == "local":
		return _draw_local_layer(chart, view, view066, view067, view068, sector)
	if layer == "ocean":
		return _draw_ocean_layer(chart, view, view066, view067, view068, sector)
	return _empty_metrics()
