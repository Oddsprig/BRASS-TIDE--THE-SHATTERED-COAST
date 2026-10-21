extends RefCounted
## MotorArt: stern outboard motors, stern drives/nozzles, and aft machinery detail (v0.007).
## Self-contained RefCounted module anchored to actual HullProfiles.stations(spec)[0].x transom.
## Positive x is bow; negative x is stern. All stern propulsion units extend aft of stations[0].x
## and maintain strict positive clearance from the aft weapon socket (mount1) and all other mounts.

const HullProfiles = preload("res://scripts/hull_profiles.gd")
const Layout = preload("res://scripts/mount_layout.gd")
const WeaponArt = preload("res://scripts/weapon_art.gd")

const CAT_OFFSET: float = 0.62
const SMALL_HULL_MAX_SIZE: float = 18.5
const TRIPLE_DRIVE_MIN_SIZE: float = 28.5
static var _render_cache: Dictionary={}

const _SINGLE_OUTBOARD_HULLS: Dictionary = {
	"bilge_punt": true,
	"marsh_dart": true
}

const _NOZZLE_ROLES: Dictionary = {
	"torpedo": true,
	"rocket": true
}

const _NOZZLE_HULLS: Dictionary = {
	"hook_raider": true,
	"aegis_corvette": true,
	"krill_torpedo": true,
	"manta_strike": true,
	"cinder_monitor": true,
	"wraith_rocket": true
}

static func _num(value, fallback: float = 0.0) -> float:
	return float(value) if (value is int or value is float) and is_finite(float(value)) else fallback

static func _resolve_spec(spec: Dictionary, boat: Dictionary) -> Dictionary:
	if not spec.is_empty():
		return spec
	var bs = boat.get("spec", {})
	return bs if bs is Dictionary else {}

static func _engine_id(spec: Dictionary, boat: Dictionary) -> String:
	var b_loadout = boat.get("loadout", {})
	if b_loadout is Dictionary and b_loadout.get("engine") is String and not str(b_loadout.get("engine")).is_empty():
		return str(b_loadout.get("engine"))
	var s_loadout = spec.get("loadout", {})
	if s_loadout is Dictionary and s_loadout.get("engine") is String and not str(s_loadout.get("engine")).is_empty():
		return str(s_loadout.get("engine"))
	for key in ["engineModule", "engineId"]:
		if spec.get(key) is String and not str(spec.get(key)).is_empty():
			return str(spec.get(key))
		if boat.get(key) is String and not str(boat.get(key)).is_empty():
			return str(boat.get(key))
	if boat.get("engine") is String and not str(boat.get("engine")).is_empty():
		return str(boat.get("engine"))
	if spec.get("engine") is String and not str(spec.get("engine")).is_empty():
		return str(spec.get("engine"))
	var fuel_use: float = _num(spec.get("fuelUse"), 1.0)
	if fuel_use < 0.80:
		return "economy_drive"
	if fuel_use > 1.50:
		return "heavy_drive"
	if fuel_use > 1.20:
		return "boost_drive"
	return "stock_engine"

static func _engine_health(spec: Dictionary, boat: Dictionary) -> float:
	var raw = boat.get("engine", spec.get("engineHealth", 1.0))
	if raw is int or raw is float:
		return clampf(_num(raw, 1.0), 0.0, 1.0)
	return 1.0

static func _steer_angle(boat: Dictionary) -> float:
	for key in ["rudder", "steer", "turnInput"]:
		if boat.has(key):
			return clampf(_num(boat.get(key), 0.0) * 0.22, -0.25, 0.25)
	return 0.0

static func _min_socket_clearance(sockets: Array, item: Dictionary) -> float:
	var best: float = 99.0
	for s in sockets:
		if s is Dictionary:
			best = minf(best, Layout.footprint_clearance(s, item))
	return best

static func _aft_socket_clearance(sockets: Array, item: Dictionary) -> float:
	for s in sockets:
		if s is Dictionary and (str(s.get("id", "")) == "mount1" or str(s.get("slot", "")) == "aft"):
			return Layout.footprint_clearance(s, item)
	return _min_socket_clearance(sockets, item)

## Returns deterministic stern propulsion & aft machinery layout metadata without mutating inputs.
static func layout(spec: Dictionary, boat: Dictionary = {}) -> Dictionary:
	var eff_spec: Dictionary = _resolve_spec(spec, boat)
	var prof: Dictionary = HullProfiles.profile(eff_spec)
	var stations: Array = HullProfiles.stations(eff_spec)
	var st0: Vector2 = stations[0] if not stations.is_empty() else Vector2(-1.88, 0.42)
	var transom_x: float = float(st0.x)
	var transom_hb: float = maxf(0.14, float(st0.y))
	var hull_id: String = str(prof.get("hullId", eff_spec.get("id", "tin_skiff")))
	var role: String = str(eff_spec.get("role", "skiff"))
	var arch: String = str(prof.get("archetype", Layout.archetype(eff_spec)))
	var faction: String = str(eff_spec.get("faction", "compact"))
	var tier: int = clampi(int(_num(eff_spec.get("tier"), 1.0)), 1, 4)
	var size: float = Layout.hull_size(eff_spec)
	var is_cat: bool = arch == "catamaran" or role == "raider"
	var is_small: bool = size <= SMALL_HULL_MAX_SIZE
	var eng_id: String = _engine_id(eff_spec, boat)
	var eng_health: float = _engine_health(eff_spec, boat)
	var steer: float = _steer_angle(boat)
	var sockets: Array = Layout.hardpoints(eff_spec)
	var struct_plan: Dictionary = Layout.structure(eff_spec)
	var engine_bay: Dictionary = struct_plan.get("engine", {"x": -1.00, "y": 0.0, "length": 0.35, "width": 0.44, "height": 14.0})

	var family: String = "outboard"
	var kind: String = "twin_outboard"
	var count: int = 2
	var y_positions: Array = []

	if is_small:
		family = "outboard"
		var single_default: bool = _SINGLE_OUTBOARD_HULLS.has(hull_id) and eng_id != "heavy_drive"
		if is_cat:
			count = 2
			kind = "twin_outboard"
			y_positions = [-CAT_OFFSET, CAT_OFFSET]
		elif single_default:
			count = 1
			kind = "single_outboard"
			y_positions = [0.0]
		else:
			count = 2
			kind = "twin_outboard"
			var spread_sm: float = clampf(transom_hb * 0.52, 0.17, 0.24)
			y_positions = [-spread_sm, spread_sm]
	else:
		var use_nozzle: bool = _NOZZLE_HULLS.has(hull_id) or _NOZZLE_ROLES.has(role)
		family = "nozzle" if use_nozzle else "stern_drive"
		if is_cat:
			count = 2
			kind = "twin_nozzle" if use_nozzle else "twin_stern_drive"
			y_positions = [-CAT_OFFSET, CAT_OFFSET]
		elif size >= TRIPLE_DRIVE_MIN_SIZE or (tier >= 4 and size >= 24.0):
			count = 3
			kind = "triple_nozzle" if use_nozzle else "triple_stern_drive"
			var spread_3: float = clampf(transom_hb * 0.55, 0.24, 0.35)
			y_positions = [-spread_3, 0.0, spread_3]
		else:
			count = 2
			kind = "twin_nozzle" if use_nozzle else "twin_stern_drive"
			var spread_2: float = clampf(transom_hb * 0.52, 0.22, 0.31)
			y_positions = [-spread_2, spread_2]

	var w_scale: float = 1.0
	if count == 1:
		w_scale = 1.12
	elif count == 3:
		w_scale = 0.90
	if eng_id == "heavy_drive":
		w_scale *= 1.08

	var units: Array = []
	var global_min_x: float = transom_x
	var global_max_x: float = transom_x - 1.0
	var min_aft_clear: float = 99.0
	var min_any_clear: float = 99.0

	for i in range(y_positions.size()):
		var uy: float = float(y_positions[i])
		var u_len: float = 0.38 if is_small else 0.44
		var u_wid: float = (0.18 if is_small else 0.20) * w_scale
		var u_min_x: float = transom_x - (0.35 if is_small else 0.41)
		var u_max_x: float = transom_x + 0.03
		var ux: float = (u_min_x + u_max_x) * 0.5
		var top_h: float = (15.4 if is_small else 13.6) + (0.6 if eng_id == "heavy_drive" else 0.0)
		var unit_fp: Dictionary = {"kind": "rect", "x": ux, "y": uy, "length": u_len, "width": u_wid, "len": u_len, "wid": u_wid}
		var aft_clear: float = _aft_socket_clearance(sockets, unit_fp)
		var any_clear: float = _min_socket_clearance(sockets, unit_fp)
		min_aft_clear = minf(min_aft_clear, aft_clear)
		min_any_clear = minf(min_any_clear, any_clear)
		global_min_x = minf(global_min_x, u_min_x)
		global_max_x = maxf(global_max_x, u_max_x)

		var unit_dict: Dictionary = {
			"id": "motor%d" % i,
			"index": i,
			"kind": family,
			"configuration": kind,
			"x": ux,
			"y": uy,
			"z": 0.0,
			"transomX": transom_x,
			"minX": u_min_x,
			"maxX": u_max_x,
			"length": u_len,
			"width": u_wid,
			"len": u_len,
			"wid": u_wid,
			"height": top_h,
			"scale": w_scale,
			"steerAngle": steer,
			"worldX": ux * size,
			"worldY": uy * size,
			"aftSocketClearance": aft_clear,
			"socketClearance": any_clear,
			"cowling": {
				"x": transom_x - (0.18 if is_small else 0.15),
				"y": uy,
				"zMin": 5.8 if is_small else 5.0,
				"zMax": top_h,
				"length": 0.30 if is_small else 0.33,
				"width": u_wid,
				"height": top_h,
				"style": "outboard_hood" if is_small else ("nozzle_shroud" if family == "nozzle" else "armored_doghouse")
			},
			"vents": {
				"x": transom_x - (0.20 if is_small else 0.16),
				"y": uy,
				"z": top_h - 1.2,
				"slats": 4 if tier >= 2 else 3,
				"length": 0.16,
				"width": u_wid * 0.72
			},
			"bands": {
				"x": transom_x - (0.18 if is_small else 0.15),
				"y": uy,
				"z": 10.0 if is_small else 8.9,
				"count": 2 if eng_id in ["boost_drive", "heavy_drive"] or tier >= 2 else 1,
				"width": u_wid * 1.04
			},
			"bracket": {
				"x": transom_x - 0.025,
				"y": uy,
				"zMin": 4.2 if is_small else 3.2,
				"zMax": 9.6 if is_small else 9.2,
				"length": 0.13,
				"width": u_wid * 0.76
			},
			"lowerLeg": {
				"x": transom_x - (0.15 if is_small else 0.17),
				"y": uy,
				"zMin": -1.2,
				"zMax": 6.0 if is_small else 5.2,
				"length": 0.18,
				"width": u_wid * 0.46,
				"plateZ": 0.35
			},
			"propellerHousing": {
				"x": transom_x - (0.22 if is_small else 0.28),
				"y": uy,
				"zMin": -3.3,
				"zMax": -0.7 if is_small else 0.6,
				"length": 0.24 if is_small else 0.30,
				"width": u_wid * (0.58 if is_small else 0.86),
				"radius": 0.055 if is_small else 0.082,
				"blades": 3,
				"shrouded": not is_small
			},
			"exhaust": {
				"x": transom_x - (0.34 if is_small else 0.36),
				"y": uy,
				"z": 7.8 if is_small else 4.4,
				"ports": 2 if not is_small or count == 2 else 1,
				"radius": 0.032 if is_small else 0.045
			}
		}
		units.append(unit_dict)

	var machinery: Array = []
	if not is_small:
		var q_y: float = CAT_OFFSET if is_cat else clampf(transom_hb * 0.62, 0.28, 0.38)
		var q_x: float = transom_x + 0.16
		var q_len: float = 0.20
		var q_wid: float = 0.11
		var q_h: float = 12.4 + float(tier) * 0.25
		for side_idx in range(2):
			var sy: float = -q_y if side_idx == 0 else q_y
			var pod_item: Dictionary = {
				"id": "stern_gearbox_%d" % side_idx,
				"kind": "transfer_gearbox",
				"x": q_x,
				"y": sy,
				"zMin": 9.2,
				"zMax": q_h,
				"height": q_h,
				"length": q_len,
				"width": q_wid,
				"len": q_len,
				"wid": q_wid,
				"slats": 3
			}
			var pod_aft_clear: float = _aft_socket_clearance(sockets, pod_item)
			var pod_any_clear: float = _min_socket_clearance(sockets, pod_item)
			if pod_any_clear >= 0.05:
				pod_item["aftSocketClearance"] = pod_aft_clear
				pod_item["socketClearance"] = pod_any_clear
				machinery.append(pod_item)
				min_aft_clear = minf(min_aft_clear, pod_aft_clear)
				min_any_clear = minf(min_any_clear, pod_any_clear)

	var eb_x: float = _num(engine_bay.get("x"), -1.00)
	var eb_len: float = _num(engine_bay.get("length", engine_bay.get("len")), 0.35)
	var eb_wid: float = _num(engine_bay.get("width", engine_bay.get("wid")), 0.44)
	var eb_h: float = _num(engine_bay.get("height"), 13.8)
	var hdr_len: float = eb_len * 0.64
	var hdr_wid: float = eb_wid * 0.24
	for bank_idx in range(2):
		var by: float = (-1.0 if bank_idx == 0 else 1.0) * eb_wid * 0.26
		var bank_item: Dictionary = {
			"id": "engine_manifold_%d" % bank_idx,
			"kind": "exhaust_manifold",
			"x": eb_x,
			"y": by,
			"zMin": eb_h,
			"zMax": eb_h + (1.4 if is_small else 2.1),
			"height": eb_h + (1.4 if is_small else 2.1),
			"length": hdr_len,
			"width": hdr_wid,
			"len": hdr_len,
			"wid": hdr_wid,
			"slats": 3
		}
		var bank_aft_clear: float = _aft_socket_clearance(sockets, bank_item)
		var bank_any_clear: float = _min_socket_clearance(sockets, bank_item)
		if bank_any_clear >= 0.05:
			bank_item["aftSocketClearance"] = bank_aft_clear
			bank_item["socketClearance"] = bank_any_clear
			machinery.append(bank_item)
			min_aft_clear = minf(min_aft_clear, bank_aft_clear)
			min_any_clear = minf(min_any_clear, bank_any_clear)

	return {
		"hullId": hull_id,
		"role": role,
		"archetype": arch,
		"faction": faction,
		"tier": tier,
		"size": size,
		"isSmallHull": is_small,
		"isCatamaran": is_cat,
		"transomX": transom_x,
		"sternX": transom_x,
		"transomHalfBeam": transom_hb,
		"engineId": eng_id,
		"engineHealth": eng_health,
		"propulsion": family,
		"family": family,
		"kind": kind,
		"count": units.size(),
		"motorCount": units.size(),
		"beyondStern": global_min_x < transom_x,
		"minX": global_min_x,
		"maxX": global_max_x,
		"aftSocketClearance": min_aft_clear,
		"minSocketClearance": min_any_clear,
		"clearsSockets": min_any_clear > 0.04,
		"units": units,
		"motors": units,
		"drives": units,
		"machinery": machinery,
		"components": {
			"cowling": true,
			"vents": true,
			"bands": true,
			"bracket": true,
			"lowerLeg": true,
			"propellerHousing": true,
			"exhaust": true
		}
	}

static func _palette(palette: Dictionary, spec: Dictionary) -> Dictionary:
	var top: Color = palette.get("top", Color("30505c")) if palette.get("top") is Color else Color("30505c")
	var side: Color = palette.get("side", Color("24383f")) if palette.get("side") is Color else Color("24383f")
	var plate: Color = palette.get("plate", top.lightened(0.16)) if palette.get("plate") is Color else top.lightened(0.16)
	var metal: Color = palette.get("metal", Color("39494d")) if palette.get("metal") is Color else Color("39494d")
	var metal_light: Color = palette.get("metal_light", Color("c9c9a8")) if palette.get("metal_light") is Color else Color("c9c9a8")
	var brass: Color = palette.get("brass", Color("c8a35e")) if palette.get("brass") is Color else Color("c8a35e")
	var accent: Color = palette.get("accent", Color("8fc6b4")) if palette.get("accent") is Color else Color("8fc6b4")
	var foam: Color = palette.get("foam", Color(0.73, 0.87, 0.75, 1.0)) if palette.get("foam") is Color else Color(0.73, 0.87, 0.75, 1.0)
	var cabin: Color = palette.get("cabin", Color("b9ac84")) if palette.get("cabin") is Color else Color("b9ac84")
	var faction: String = str(spec.get("faction", "compact"))
	if palette.is_empty():
		match faction:
			"forge":
				side = Color("3a2e28"); top = Color("4d3b30"); plate = top.lightened(0.16); cabin = Color("8a7154")
			"reed":
				side = Color("274036"); top = Color("33523f"); plate = top.lightened(0.16); cabin = Color("b39d6d")
			"raiders":
				side = Color("402c2c"); top = Color("523838"); plate = top.lightened(0.16); cabin = Color("97795c")
	return {
		"side": side,
		"top": top,
		"plate": plate,
		"cabin": cabin,
		"metal": metal,
		"metal_light": metal_light,
		"brass": brass,
		"accent": accent,
		"foam": foam,
		"dark": Color("1a262b"),
		"steel": Color("506369"),
		"edge": Color("a5b6b0"),
		"copper": Color("b87948")
	}

static func _model(ctx: Dictionary, at: Vector2, bearing: float = 0.0, h: float = 0.0) -> Dictionary:
	return {
		"ctx": ctx,
		"at": at,
		"bearing": bearing,
		"u": 1.0,
		"world_unit": 1.0,
		"lod": clampi(int(ctx.get("lod", 0)), 0, 2),
		"h": h
	}

static func _line3d(m: Dictionary, a: Vector3, b: Vector3, col: Color, width_mult: float = 1.0) -> void:
	var sz: float = maxf(4.0, _num(m.ctx.get("size"), 16.0))
	WeaponArt._line(m, a, b, col, width_mult * sz * 0.05)

static func _circ3d(m: Dictionary, p: Vector3, r_units: float, col: Color) -> void:
	var pt: Vector2 = WeaponArt._p(m, p)
	var px: float = maxf(2.0, _num(m.ctx.get("px"), 12.0))
	m.ctx.canvas.draw_circle(pt, maxf(0.8, r_units * px), col)
	m.ctx.n = int(m.ctx.get("n", 0)) + 1
	m.ctx.ncirc = int(m.ctx.get("ncirc", 0)) + 1

static func _band_color(plan: Dictionary, c: Dictionary) -> Color:
	var eng_id: String = str(plan.get("engineId", "stock_engine"))
	match eng_id:
		"economy_drive":
			return c.copper
		"boost_drive":
			return c.accent.lightened(0.16)
		"heavy_drive":
			return c.brass.lightened(0.12)
		_:
			return c.accent

static func _draw_outboard(ctx: Dictionary, unit: Dictionary, plan: Dictionary, c: Dictionary, lod: int, clock: float, speed: float,steer: float=0.0) -> void:
	var tx: float = float(unit.get("transomX", plan.get("transomX", -1.88)))
	var uy: float = float(unit.get("y", 0.0))
	var w: float = float(unit.get("scale", 1.0))
	var m: Dictionary = _model(ctx, Vector2(tx, uy), steer, 0.0)
	var cowl_col: Color = c.top.darkened(0.10)
	var cowl_cap: Color = c.plate.lightened(0.06)
	var band_col: Color = _band_color(plan, c)

	if lod == 2:
		# Compact far LOD: submerged leg/gearcase box + cowling/bracket box + band + prop/exhaust lines (<=14 prims/unit).
		WeaponArt._box(m, Vector3(-0.30, -0.048 * w, -3.0), Vector3(-0.06, 0.048 * w, 5.8), c.steel)
		WeaponArt._box(m, Vector3(-0.34, -0.086 * w, 5.8), Vector3(0.03, 0.086 * w, 14.4), cowl_col)
		_line3d(m, Vector3(-0.35, -0.088 * w, 10.2), Vector3(-0.35, 0.088 * w, 10.2), band_col, 1.3)
		_line3d(m, Vector3(-0.36, 0.0, -2.0), Vector3(-0.26, 0.0, -2.0), c.brass, 1.2)
		return

	# 1. Submerged propeller housing (gearcase torpedo + skeg + bronze prop hub & blades)
	WeaponArt._box(m, Vector3(-0.33, -0.046 * w, -3.2), Vector3(-0.08, 0.046 * w, -0.9), c.dark)
	WeaponArt._face(m, [Vector3(-0.29, 0.0, -4.0), Vector3(-0.11, 0.0, -3.2), Vector3(-0.26, 0.0, -3.2)], c.dark)
	WeaponArt._box(m, Vector3(-0.38, -0.030 * w, -2.5), Vector3(-0.32, 0.030 * w, -1.5), c.brass)
	var blade_count: int = 3 if lod == 0 else 2
	var spin: float = clock * (15.0 if speed > 1.0 else 0.0) + float(unit.get("index", 0)) * 1.1
	for b_idx in range(blade_count):
		var ang: float = spin + float(b_idx) * TAU / float(blade_count)
		var by: float = cos(ang) * 0.078 * w
		var bz: float = -2.0 + sin(ang) * 0.95
		_line3d(m, Vector3(-0.36, 0.0, -2.0), Vector3(-0.39, by, bz), c.metal_light, 1.1)

	# 2. Lower leg strut + anti-cavitation plate
	WeaponArt._box(m, Vector3(-0.24, -0.038 * w, -1.0), Vector3(-0.06, 0.038 * w, 6.2), c.steel)
	WeaponArt._face(m, [
		Vector3(-0.32, -0.076 * w, 0.3),
		Vector3(-0.05, -0.064 * w, 0.3),
		Vector3(-0.05, 0.064 * w, 0.3),
		Vector3(-0.32, 0.076 * w, 0.3)
	], c.edge.darkened(0.14))

	# 3. Transom clamping bracket straddling stations[0].x
	WeaponArt._box(m, Vector3(-0.09, -0.066 * w, 4.3), Vector3(0.04, 0.066 * w, 9.6), c.metal)
	if lod == 0:
		for s in [-1.0, 1.0]:
			_line3d(m, Vector3(-0.07, s * 0.042 * w, 9.8), Vector3(0.03, s * 0.042 * w, 9.8), c.brass, 1.0)

	# 4. Sculpted outboard powerhead cowling + upper hood cap
	WeaponArt._box(m, Vector3(-0.34, -0.088 * w, 6.0), Vector3(-0.03, 0.088 * w, 12.8), cowl_col)
	WeaponArt._box(m, Vector3(-0.31, -0.074 * w, 12.7), Vector3(-0.05, 0.074 * w, 14.9), cowl_cap)
	if lod == 0:
		WeaponArt._box(m, Vector3(-0.26, -0.046 * w, 14.8), Vector3(-0.09, 0.046 * w, 15.7), c.dark)

	# 5. Cowling wrap bands
	WeaponArt._box(m, Vector3(-0.35, -0.093 * w, 9.4), Vector3(-0.025, 0.093 * w, 10.6), band_col)
	if lod == 0:
		_line3d(m, Vector3(-0.35, -0.088 * w, 12.2), Vector3(-0.03, -0.088 * w, 12.2), c.brass, 0.95)
		_line3d(m, Vector3(-0.35, 0.088 * w, 12.2), Vector3(-0.03, 0.088 * w, 12.2), c.brass, 0.95)
		_line3d(m, Vector3(-0.35, -0.088 * w, 12.2), Vector3(-0.35, 0.088 * w, 12.2), c.brass, 1.05)

	# 6. Cooling vents / louver slats on upper cowling
	var slats: int = 4 if lod == 0 else 2
	for i in range(slats):
		var vz: float = 11.2 + float(i) * (2.6 / maxf(1.0, float(slats - 1)))
		_line3d(m, Vector3(-0.345, -0.058 * w, vz), Vector3(-0.345, 0.058 * w, vz), c.edge, 0.9)
	if lod == 0:
		for s in [-1.0, 1.0]:
			_line3d(m, Vector3(-0.28, s * 0.078 * w, 13.8), Vector3(-0.10, s * 0.078 * w, 13.8), c.dark, 1.0)

	# 7. Exhaust relief housing + snout & moving prop wash
	WeaponArt._box(m, Vector3(-0.39, -0.042 * w, 7.1), Vector3(-0.33, 0.042 * w, 8.7), c.dark)
	_line3d(m, Vector3(-0.395, -0.036 * w, 7.9), Vector3(-0.395, 0.036 * w, 7.9), c.brass, 1.0)
	if speed > 1.0:
		var pulse: float = 0.04 * sin(clock * 9.0 + float(unit.get("index", 0)) * 1.7)
		_circ3d(m, Vector3(-0.44 + pulse, 0.0, -0.6), 0.045, Color(c.foam, 0.55))
		if lod == 0:
			_line3d(m, Vector3(-0.38, -0.05 * w, -0.4), Vector3(-0.52, -0.09 * w, -0.8), Color(c.foam, 0.50), 1.1)
			_line3d(m, Vector3(-0.38, 0.05 * w, -0.4), Vector3(-0.52, 0.09 * w, -0.8), Color(c.foam, 0.50), 1.1)

static func _draw_stern_drive(ctx: Dictionary, unit: Dictionary, plan: Dictionary, c: Dictionary, lod: int, clock: float, speed: float,steer: float=0.0) -> void:
	var tx: float = float(unit.get("transomX", plan.get("transomX", -1.96)))
	var uy: float = float(unit.get("y", 0.0))
	var w: float = float(unit.get("scale", 1.0))
	var is_nozzle: bool = str(unit.get("kind", "stern_drive")) == "nozzle"
	var m: Dictionary = _model(ctx, Vector2(tx, uy), steer, 0.0)
	var cowl_col: Color = c.top.darkened(0.08)
	var cowl_cap: Color = c.plate
	var band_col: Color = _band_color(plan, c)

	if lod == 2:
		# Compact far LOD: submerged nozzle/gearcase box + upper drive cowling box + band + exhaust/nozzle lines (<=14 prims/unit).
		WeaponArt._box(m, Vector3(-0.38, -0.072 * w, -3.0), Vector3(-0.06, 0.072 * w, 4.8), c.steel)
		WeaponArt._box(m, Vector3(-0.32, -0.092 * w, 4.8), Vector3(0.03, 0.092 * w, 13.0), cowl_col)
		_line3d(m, Vector3(-0.33, -0.094 * w, 9.0), Vector3(-0.33, 0.094 * w, 9.0), band_col, 1.3)
		_line3d(m, Vector3(-0.40, -0.06 * w, -1.2), Vector3(-0.40, 0.06 * w, -1.2), c.brass, 1.2)
		return

	# 1. Submerged propeller housing & shrouded Kort nozzle / directional jet ring
	WeaponArt._box(m, Vector3(-0.30, -0.052 * w, -3.3), Vector3(-0.08, 0.052 * w, -0.3), c.dark)
	WeaponArt._box(m, Vector3(-0.42, -0.082 * w, -2.9), Vector3(-0.23, 0.082 * w, 0.6), c.steel if is_nozzle else c.dark.lightened(0.08))
	WeaponArt._face(m, [
		Vector3(-0.43, -0.076 * w, -2.7),
		Vector3(-0.43, 0.076 * w, -2.7),
		Vector3(-0.43, 0.076 * w, 0.4),
		Vector3(-0.43, -0.076 * w, 0.4)
	], c.brass if is_nozzle else c.edge)
	var blade_count: int = 3 if lod == 0 else 2
	var spin: float = clock * (13.0 if speed > 1.0 else 0.0) + float(unit.get("index", 0)) * 0.9
	for b_idx in range(blade_count):
		var ang: float = spin + float(b_idx) * TAU / float(blade_count)
		var by: float = cos(ang) * 0.068 * w
		var bz: float = -1.15 + sin(ang) * 0.95
		_line3d(m, Vector3(-0.43, 0.0, -1.15), Vector3(-0.44, by, bz), c.brass.lightened(0.15), 1.1)

	# 2. Lower leg strut + hydrofoil anti-cavitation plate
	WeaponArt._box(m, Vector3(-0.27, -0.048 * w, -0.5), Vector3(-0.06, 0.048 * w, 5.2), c.steel)
	WeaponArt._face(m, [
		Vector3(-0.35, -0.088 * w, 0.6),
		Vector3(-0.06, -0.074 * w, 0.6),
		Vector3(-0.06, 0.074 * w, 0.6),
		Vector3(-0.35, 0.088 * w, 0.6)
	], c.edge.darkened(0.16))

	# 3. Transom gimbal bracket & hydraulic trim rams
	WeaponArt._box(m, Vector3(-0.10, -0.078 * w, 3.2), Vector3(0.04, 0.078 * w, 9.2), c.metal)
	if lod == 0:
		for s in [-1.0, 1.0]:
			_line3d(m, Vector3(-0.02, s * 0.066 * w, 5.6), Vector3(-0.25, s * 0.056 * w, 1.8), c.brass, 1.05)

	# 4. Armored stern-drive doghouse cowling + sloped upper inspection hood
	WeaponArt._box(m, Vector3(-0.32, -0.095 * w, 5.0), Vector3(0.02, 0.095 * w, 11.3), cowl_col)
	WeaponArt._box(m, Vector3(-0.27, -0.076 * w, 11.2), Vector3(0.00, 0.076 * w, 13.4), cowl_cap)
	if lod == 0:
		WeaponArt._face(m,[Vector3(-0.22,-0.048*w,13.6),Vector3(-0.04,-0.048*w,13.6),Vector3(-0.04,0.048*w,13.6),Vector3(-0.22,0.048*w,13.6)],c.metal)

	# 5. Clamping & faction wrap bands
	WeaponArt._box(m, Vector3(-0.33, -0.100 * w, 8.3), Vector3(0.025, 0.100 * w, 9.4), band_col)
	if lod == 0:
		_line3d(m, Vector3(-0.28, -0.080 * w, 11.8), Vector3(0.00, -0.080 * w, 11.8), c.brass, 0.95)
		_line3d(m, Vector3(-0.28, 0.080 * w, 11.8), Vector3(0.00, 0.080 * w, 11.8), c.brass, 0.95)

	# 6. Cooling vents / intake louvers on upper drive cowling
	var slats: int = 4 if lod == 0 else 2
	for i in range(slats):
		var vx: float = -0.24 + float(i) * (0.18 / maxf(1.0, float(slats - 1)))
		_line3d(m, Vector3(vx, -0.058 * w, 13.55), Vector3(vx, 0.058 * w, 13.55), c.edge, 0.9)

	# 7. Flanged wet-exhaust housing & flapper rim + speed wash
	WeaponArt._face(m,[Vector3(-0.38,-0.046*w,3.5),Vector3(-0.38,0.046*w,3.5),Vector3(-0.38,0.046*w,5.0),Vector3(-0.38,-0.046*w,5.0)],c.dark)
	_line3d(m, Vector3(-0.385, -0.040 * w, 4.3), Vector3(-0.385, 0.040 * w, 4.3), c.brass, 1.05)
	if speed > 1.0:
		var pulse: float = 0.05 * sin(clock * 8.5 + float(unit.get("index", 0)) * 1.5)
		_circ3d(m, Vector3(-0.48 + pulse, 0.0, -0.7), 0.052, Color(c.foam, 0.58))
		if lod == 0:
			_line3d(m, Vector3(-0.42, -0.06 * w, -0.5), Vector3(-0.58, -0.10 * w, -1.0), Color(c.foam, 0.52), 1.15)
			_line3d(m, Vector3(-0.42, 0.06 * w, -0.5), Vector3(-0.58, 0.10 * w, -1.0), Color(c.foam, 0.52), 1.15)

static func _draw_tie_bar(ctx: Dictionary, units: Array, plan: Dictionary, c: Dictionary, lod: int) -> void:
	if lod >= 2 or units.is_empty():
		return
	var tx: float = float(plan.get("transomX", -1.88))
	var m: Dictionary = _model(ctx, Vector2(tx, 0.0), 0.0, 0.0)
	if units.size() == 1:
		# Single outboard steering tiller arm & throttle conduit into the stern well
		_line3d(m, Vector3(-0.04, 0.0, 9.8), Vector3(0.08, 0.05, 10.3), c.metal_light, 1.15)
		if lod == 0:
			_line3d(m, Vector3(-0.06, -0.03, 9.2), Vector3(0.06, -0.06, 9.6), c.brass, 0.9)
		return
	var y_min: float = float(units[0].get("y", -0.22))
	var y_max: float = float(units[units.size() - 1].get("y", 0.22))
	var bar_z: float = 8.9 if bool(plan.get("isSmallHull", true)) else 8.4
	_line3d(m, Vector3(-0.05, y_min, bar_z), Vector3(-0.05, y_max, bar_z), c.metal_light, 1.2)
	if lod == 0:
		_line3d(m, Vector3(-0.02, y_min * 0.85, bar_z + 0.7), Vector3(-0.02, y_max * 0.85, bar_z + 0.7), c.brass, 0.95)

static func _draw_machinery(ctx: Dictionary, item: Dictionary, plan: Dictionary, c: Dictionary, lod: int) -> void:
	if lod >= 2:
		return
	var kind: String = str(item.get("kind", "transfer_gearbox"))
	var ix: float = float(item.get("x", -1.70))
	var iy: float = float(item.get("y", 0.30))
	var ilen: float = float(item.get("length", 0.20))
	var iwid: float = float(item.get("width", 0.11))
	var z0: float = float(item.get("zMin", 9.2))
	var z1: float = float(item.get("zMax", 12.5))
	var m: Dictionary = _model(ctx, Vector2(ix, iy), 0.0, 0.0)

	if kind == "transfer_gearbox":
		var tx: float = float(plan.get("transomX", -1.96))
		WeaponArt._box(m, Vector3(-ilen * 0.5, -iwid * 0.5, z0), Vector3(ilen * 0.5, iwid * 0.5, z1), c.metal)
		# Drive-shaft conduit linking stern gearbox aft to transom bracket
		_line3d(m, Vector3(-ilen * 0.5, 0.0, z1 - 0.8), Vector3(tx - ix, 0.0, 8.8), c.brass, 1.05)
		if lod == 0:
			WeaponArt._box(m, Vector3(-ilen * 0.28, -iwid * 0.34, z1 - 0.1), Vector3(ilen * 0.28, iwid * 0.34, z1 + 1.1), c.plate)
			for s_idx in range(2):
				var sx: float = -ilen * 0.22 + float(s_idx) * ilen * 0.44
				_line3d(m, Vector3(sx, -iwid * 0.38, z1 + 0.2), Vector3(sx, iwid * 0.38, z1 + 0.2), c.edge, 0.85)
	elif kind == "exhaust_manifold":
		if lod == 1:
			_line3d(m, Vector3(-ilen * 0.45, 0.0, z0 + 0.5), Vector3(ilen * 0.45, 0.0, z0 + 0.5), c.brass, 1.15)
			return
		WeaponArt._box(m, Vector3(-ilen * 0.5, -iwid * 0.5, z0 - 0.2), Vector3(ilen * 0.5, iwid * 0.5, z1), c.dark.lightened(0.12))
		_line3d(m, Vector3(-ilen * 0.44, 0.0, z1 + 0.2), Vector3(ilen * 0.44, 0.0, z1 + 0.2), c.brass, 1.0)

## Draws stern outboard motors or stern drives/nozzles plus machinery detail onto ctx.canvas.
static func _plan(eff_spec: Dictionary,boat: Dictionary) -> Dictionary:
	# Structural geometry is static for a hull/engine fit. Health and motion stay live.
	var engine_id: String=_engine_id(eff_spec,boat)
	var cache_key: String="%s:%s:%.2f:%s:%d"%[str(eff_spec.get("id","boat")),str(eff_spec.get("role","skiff")),Layout.hull_size(eff_spec),engine_id,int(eff_spec.get("tier",1))]
	if not _render_cache.has(cache_key):
		if _render_cache.size()>=128:_render_cache.clear()
		_render_cache[cache_key]=layout(eff_spec,{"loadout":{"engine":engine_id}})
	return _render_cache[cache_key]

static func draw_motion(ctx: Dictionary,spec: Dictionary,boat: Dictionary,palette: Dictionary) -> void:
	if int(ctx.lod)>=2:return
	var plan: Dictionary=_plan(spec,boat)
	var health: float=_engine_health(spec,boat)
	var c: Dictionary=_palette(palette,spec)
	for unit in plan.units:
		var model: Dictionary=_model(ctx,Vector2(unit.transomX,unit.y))
		if float(ctx.speed)>1.0 and health>0.05 and _num(boat.get("fuel"),60)>0:
			var phase: float=sin(float(ctx.clock)*9+unit.index*1.5)*0.04
			var spin: float=float(ctx.clock)*15+unit.index
			var blade:=Vector3(0,cos(spin)*0.07,sin(spin)*0.95)
			_line3d(model,Vector3(-0.38,0,-1.6)-blade,Vector3(-0.38,0,-1.6)+blade,c.brass,1.0)
			_line3d(model,Vector3(-0.35,-0.05,-0.5),Vector3(-0.53+phase,-0.09,-0.5),Color(c.foam,0.55),1.0)
			_line3d(model,Vector3(-0.35,0.05,-0.5),Vector3(-0.53+phase,0.09,-0.5),Color(c.foam,0.5),1.0)
	if health<0.55:
		var unit: Dictionary=plan.units[0]
		var model: Dictionary=_model(ctx,Vector2(unit.transomX,unit.y))
		var phase: float=fposmod(float(ctx.clock)*0.5,1.0)
		_circ3d(model,Vector3(-0.3-phase*0.2,0,16+phase*15),0.07+phase*0.05,Color(0.14,0.16,0.16,(1-phase)*0.35))

static func draw(ctx: Dictionary, spec: Dictionary, boat: Dictionary = {}, palette: Dictionary = {}) -> void:
	if not ctx.has("canvas") or not ctx.has("proj"):
		return
	var eff_spec: Dictionary = _resolve_spec(spec, boat)
	var plan: Dictionary = _plan(eff_spec,boat)
	var c: Dictionary = _palette(palette, eff_spec)
	var lod: int = clampi(int(ctx.get("lod", 0)), 0, 2)
	var clock: float = _num(ctx.get("clock"), _num(boat.get("battleTime"), 0.0))
	var vel := Vector2(_num(boat.get("vx"), 0.0), _num(boat.get("vy"), 0.0))
	var speed: float = maxf(_num(ctx.get("speed"), 0.0), vel.length())
	var eng_health: float = _engine_health(eff_spec,boat)
	if eng_health<=0.05 or _num(boat.get("fuel"),60)<=0 or bool(boat.get("sunk",false)):speed=0.0
	var steer: float=_steer_angle(boat)

	# 1. Draw aft machinery items sorted back-to-front in screen Y
	var mach_items: Array = plan.get("machinery", []).duplicate()
	mach_items.sort_custom(func(a, b):
		var pa: Vector2 = WeaponArt._p(_model(ctx, Vector2(float(a.x), float(a.y))), Vector3.ZERO)
		var pb: Vector2 = WeaponArt._p(_model(ctx, Vector2(float(b.x), float(b.y))), Vector3.ZERO)
		return pa.y < pb.y
	)
	for item in mach_items:
		if item is Dictionary:
			_draw_machinery(ctx, item, plan, c, lod)

	# 2. Draw tie-bar / steering linkage at transom
	var units: Array = plan.get("units", []).duplicate()
	_draw_tie_bar(ctx, units, plan, c, lod)

	# 3. Draw stern propulsion units sorted back-to-front in screen Y
	units.sort_custom(func(a, b):
		var pa: Vector2 = WeaponArt._p(_model(ctx, Vector2(float(a.transomX), float(a.y))), Vector3.ZERO)
		var pb: Vector2 = WeaponArt._p(_model(ctx, Vector2(float(b.transomX), float(b.y))), Vector3.ZERO)
		return pa.y < pb.y
	)
	var is_small: bool = bool(plan.get("isSmallHull", true))
	for unit in units:
		if not (unit is Dictionary):
			continue
		if is_small:
			_draw_outboard(ctx, unit, plan, c, lod, clock, speed,steer)
		else:
			_draw_stern_drive(ctx, unit, plan, c, lod, clock, speed,steer)

	# 4. Subtle deterministic engine-damage smoke at stern when engine health is degraded
	if eng_health < 0.85 and lod < 2 and not units.is_empty():
		var u0: Dictionary = units[0]
		var dm: Dictionary = _model(ctx, Vector2(float(u0.get("transomX", -1.90)), float(u0.get("y", 0.0))), 0.0, 0.0)
		var severity: float = clampf(1.0 - eng_health, 0.15, 1.0)
		var drift: float = 0.05 * sin(clock * 5.0)
		_circ3d(dm, Vector3(-0.28, drift, 16.5), 0.065 + severity * 0.035, Color(0.14, 0.15, 0.16, 0.38 * severity))
		if lod == 0 and eng_health < 0.55:
			_circ3d(dm, Vector3(-0.34, -drift, 21.0), 0.085, Color(0.18, 0.18, 0.19, 0.30 * severity))
