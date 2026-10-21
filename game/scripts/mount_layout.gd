extends RefCounted
## Pure hull chassis socket & superstructure layout for Brass Tide (v0.006).
## Preserves Refit hardpoint count, mount0..3 IDs, size thresholds, labels,
## normal gun firing arcs, and fitting budgets while separating fore/aft/side
## weapon sockets from central bridge/cabin and aft-midships engine/stack zones.

const DECK_MIN_X: float = -1.80
const DECK_MAX_X: float = 2.20
const MONO_MAX_Y: float = 0.60
const CAT_MAX_Y: float = 0.95
const CAT_OFFSET: float = 0.62
const FIXED_LAUNCHER_ARC: float = 0.9

const _ROLE_TABLE: Dictionary = {
	"skiff": {"arch": "speedboat", "sternX": -1.74, "bowX": 2.05, "halfBeam": 0.56, "bowMountX": 0.98, "aftMountX": -1.48, "sideMountX": 0.48, "sideMountY": 0.42, "cabinX": -0.30, "cabinLen": 0.70, "cabinWid": 0.50, "cabinH": 17.5, "cabinStyle": "cockpit", "engineX": -1.00, "engineLen": 0.34, "engineWid": 0.42, "engineH": 13.0, "stacks": 0, "stackSpread": 0.0, "stackR": 0.08, "slats": 3, "elev": 11.0},
	"cutter": {"arch": "hydrofoil", "sternX": -1.78, "bowX": 2.10, "halfBeam": 0.58, "bowMountX": 1.02, "aftMountX": -1.49, "sideMountX": 0.49, "sideMountY": 0.42, "cabinX": -0.31, "cabinLen": 0.72, "cabinWid": 0.50, "cabinH": 19.0, "cabinStyle": "streamlined", "engineX": -1.01, "engineLen": 0.34, "engineWid": 0.40, "engineH": 13.5, "stacks": 1, "stackSpread": 0.12, "stackR": 0.08, "slats": 4, "elev": 12.0},
	"torpedo": {"arch": "hydrofoil", "sternX": -1.80, "bowX": 2.14, "halfBeam": 0.60, "bowMountX": 1.04, "aftMountX": -1.50, "sideMountX": 0.50, "sideMountY": 0.43, "cabinX": -0.31, "cabinLen": 0.72, "cabinWid": 0.52, "cabinH": 19.5, "cabinStyle": "attack_bridge", "engineX": -1.01, "engineLen": 0.35, "engineWid": 0.44, "engineH": 14.0, "stacks": 1, "stackSpread": 0.14, "stackR": 0.085, "slats": 4, "elev": 12.0},
	"raider": {"arch": "catamaran", "sternX": -1.80, "bowX": 2.08, "halfBeam": 0.95, "bowMountX": 1.00, "aftMountX": -1.48, "sideMountX": 0.52, "sideMountY": 0.56, "cabinX": -0.28, "cabinLen": 0.73, "cabinWid": 0.58, "cabinH": 20.0, "cabinStyle": "span_bridge", "engineX": -1.00, "engineLen": 0.35, "engineWid": 0.54, "engineH": 13.5, "stacks": 2, "stackSpread": 0.20, "stackR": 0.085, "slats": 5, "elev": 11.5},
	"corvette": {"arch": "patrol", "sternX": -1.80, "bowX": 2.12, "halfBeam": 0.60, "bowMountX": 1.02, "aftMountX": -1.50, "sideMountX": 0.50, "sideMountY": 0.43, "cabinX": -0.31, "cabinLen": 0.73, "cabinWid": 0.55, "cabinH": 20.0, "cabinStyle": "wheelhouse", "engineX": -1.01, "engineLen": 0.35, "engineWid": 0.46, "engineH": 14.0, "stacks": 1, "stackSpread": 0.0, "stackR": 0.09, "slats": 4, "elev": 11.5},
	"gunboat": {"arch": "armored", "sternX": -1.80, "bowX": 2.06, "halfBeam": 0.60, "bowMountX": 1.00, "aftMountX": -1.50, "sideMountX": 0.49, "sideMountY": 0.44, "cabinX": -0.31, "cabinLen": 0.74, "cabinWid": 0.58, "cabinH": 21.0, "cabinStyle": "casemate", "engineX": -1.02, "engineLen": 0.36, "engineWid": 0.52, "engineH": 14.5, "stacks": 2, "stackSpread": 0.18, "stackR": 0.095, "slats": 5, "elev": 12.5},
	"rocket": {"arch": "monitor", "sternX": -1.78, "bowX": 2.04, "halfBeam": 0.60, "bowMountX": 1.01, "aftMountX": -1.50, "sideMountX": 0.50, "sideMountY": 0.44, "cabinX": -0.31, "cabinLen": 0.73, "cabinWid": 0.58, "cabinH": 19.5, "cabinStyle": "monitor_house", "engineX": -1.01, "engineLen": 0.36, "engineWid": 0.54, "engineH": 14.0, "stacks": 1, "stackSpread": 0.0, "stackR": 0.10, "slats": 5, "elev": 12.0},
	"cruiser": {"arch": "command", "sternX": -1.80, "bowX": 2.18, "halfBeam": 0.60, "bowMountX": 1.05, "aftMountX": -1.52, "sideMountX": 0.51, "sideMountY": 0.44, "cabinX": -0.31, "cabinLen": 0.75, "cabinWid": 0.59, "cabinH": 24.0, "cabinStyle": "command_tower", "engineX": -1.02, "engineLen": 0.37, "engineWid": 0.52, "engineH": 15.0, "stacks": 2, "stackSpread": 0.18, "stackR": 0.095, "slats": 5, "elev": 13.0}
}

static func _number(value, fallback: float = 0.0) -> float:
	return float(value) if (value is int or value is float) and is_finite(float(value)) else fallback

static func hull_size(spec: Dictionary) -> float:
	return clampf(_number(spec.get("size"), 14.0), 8.0, 48.0)

static func _size(spec: Dictionary) -> int:
	var size: float = _number(spec.get("size"), 14.0)
	return 1 if size < 19.0 else (2 if size < 27.0 else 3)

static func mount_tier(spec: Dictionary) -> int:
	return _size(spec)

static func _budget(spec: Dictionary) -> int:
	return clampi(8 + int(maxf(0.0, _number(spec.get("tier"), 1.0) - 1.0)) * 3 + int(maxf(0.0, _number(spec.get("size"), 14.0) - 13.0) * 0.75), 8, 36)

static func fitting_budget(spec: Dictionary) -> int:
	return _budget(spec)

static func archetype(spec: Dictionary) -> String:
	var role: String = str(spec.get("role", "skiff"))
	return str(_ROLE_TABLE[role].arch) if _ROLE_TABLE.has(role) else "patrol"

static func _faction_bias(faction: String) -> float:
	match faction:
		"forge": return -0.012
		"reed": return 0.014
		"raiders": return 0.008
		_: return 0.0

static func _hull_variation(spec: Dictionary) -> Dictionary:
	var role: String = str(spec.get("role", "corvette"))
	var base: Dictionary = _ROLE_TABLE.get(role, _ROLE_TABLE["corvette"])
	var tier: int = clampi(int(_number(spec.get("tier"), 1.0)), 1, 4)
	var f_bias: float = _faction_bias(str(spec.get("faction", "compact")))
	var id_str: String = str(spec.get("id", role))
	var h_step: float = float((absi(id_str.hash()) % 5) - 2) * 0.004
	var t_step: float = float(tier - 2) * 0.010
	var is_cat: bool = str(base.arch) == "catamaran"
	return {
		"role": role, "arch": str(base.arch), "isCatamaran": is_cat, "tier": tier,
		"sternX": float(base.sternX), "bowX": float(base.bowX), "halfBeam": float(base.halfBeam),
		"bowMountX": clampf(float(base.bowMountX) + t_step + f_bias + h_step, 0.96, 1.08),
		"aftMountX": clampf(float(base.aftMountX) - t_step * 0.5 + h_step, -1.53, -1.46),
		"sideMountX": clampf(float(base.sideMountX) + f_bias * 0.8 + h_step, 0.47, 0.53),
		"sideMountY": clampf(float(base.sideMountY) + t_step * 0.4, 0.54 if is_cat else 0.42, 0.58 if is_cat else 0.445),
		"cabinX": clampf(float(base.cabinX) + f_bias * 0.5 + h_step, -0.32, -0.28),
		"cabinLen": clampf(float(base.cabinLen) + float(tier - 2) * 0.010, 0.68, 0.76),
		"cabinWid": clampf(float(base.cabinWid) + float(tier - 2) * 0.010, 0.48, 0.60),
		"cabinH": float(base.cabinH) + float(tier - 1) * 0.8, "cabinStyle": str(base.cabinStyle),
		"engineX": clampf(float(base.engineX) + h_step * 0.5, -1.03, -0.98),
		"engineLen": clampf(float(base.engineLen) + float(tier - 2) * 0.008, 0.32, 0.38),
		"engineWid": clampf(float(base.engineWid) + float(tier - 2) * 0.010, 0.38, 0.56),
		"engineH": float(base.engineH),
		"stacks": int(base.stacks) + (1 if tier >= 4 and int(base.stacks) == 1 else 0),
		"stackSpread": float(base.stackSpread), "stackR": float(base.stackR),
		"slats": int(base.slats), "elev": float(base.elev)
	}

static func _socket_radius(mount_size: int, is_side: bool) -> float:
	return (0.14 if mount_size <= 1 else 0.15) if is_side else (0.16 if mount_size <= 1 else (0.18 if mount_size == 2 else 0.20))

static func _muzzle_offset(mount_size: int) -> float:
	return 0.36 if mount_size <= 1 else (0.44 if mount_size == 2 else 0.52)

static func _make_socket(id: String, label: String, slot: String, m_size: int, lx: float, ly: float, arc: float, angle: float, is_side: bool, hull_sz: float, elev: float) -> Dictionary:
	var r: float = _socket_radius(m_size, is_side)
	var muz: float = _muzzle_offset(m_size)
	var dir: Vector2 = Vector2.from_angle(angle)
	var ox: float = lx + dir.x * muz
	var oy: float = ly + dir.y * muz
	return {
		"id": id, "label": label, "slot": slot, "size": m_size,
		"x": lx * hull_sz, "y": ly * hull_sz, "localX": lx, "localY": ly,
		"arc": arc, "angle": angle, "outwardAngle": angle, "fixedArc": FIXED_LAUNCHER_ARC,
		"footprintRadius": r, "worldFootprintRadius": r * hull_sz,
		"elevation": elev, "muzzleOffset": muz, "worldMuzzleOffset": muz * hull_sz,
		"originX": ox, "originY": oy, "worldOriginX": ox * hull_sz, "worldOriginY": oy * hull_sz
	}

static func hardpoints(spec: Dictionary) -> Array:
	var size: float = hull_size(spec)
	var mount_size: int = _size(spec)
	var sec_size: int = maxi(1, mount_size - 1)
	var v: Dictionary = _hull_variation(spec)
	var elev: float = float(v.elev)
	var result: Array = [
		_make_socket("mount0", "Main deck", "bow", mount_size, float(v.bowMountX), 0.0, TAU, 0.0, false, size, elev + 0.5),
		_make_socket("mount1", "Aft deck", "aft", sec_size, float(v.aftMountX), 0.0, TAU, PI, false, size, elev)
	]
	if size >= 20.0:
		result.append(_make_socket("mount2", "Port deck", "port", sec_size, float(v.sideMountX), -float(v.sideMountY), PI * 1.25, -PI / 2.0, true, size, elev))
	if size >= 28.0:
		result.append(_make_socket("mount3", "Starboard deck", "starboard", sec_size, float(v.sideMountX), float(v.sideMountY), PI * 1.25, PI / 2.0, true, size, elev))
	return result

static func weapon_aim(point: Dictionary, kind: String, original: bool = false) -> Dictionary:
	var clean_kind: String = str(kind).to_lower()
	var fixed: bool = not original and clean_kind in ["rocket", "torpedo"]
	var base_arc: float = _number(point.get("arc"), TAU)
	var outward: float = _number(point.get("outwardAngle"), _number(point.get("angle"), 0.0))
	return {"arc": minf(base_arc, FIXED_LAUNCHER_ARC) if fixed else base_arc, "angle": 0.0 if original else outward, "fixed": fixed}

static func structure(spec: Dictionary) -> Dictionary:
	var size: float = hull_size(spec)
	var v: Dictionary = _hull_variation(spec)
	var is_cat: bool = bool(v.isCatamaran)
	var bounds: Dictionary = {
		"sternX": float(v.sternX), "bowX": float(v.bowX), "halfBeam": float(v.halfBeam),
		"minX": DECK_MIN_X, "maxX": DECK_MAX_X, "maxAbsY": CAT_MAX_Y if is_cat else MONO_MAX_Y,
		"isCatamaran": is_cat, "catamaranOffset": CAT_OFFSET if is_cat else 0.0, "demiBeam": 0.22 if is_cat else 0.0
	}
	var cabin: Dictionary = {
		"id": "cabin", "kind": "rect", "x": float(v.cabinX), "y": 0.0,
		"length": float(v.cabinLen), "width": float(v.cabinWid), "len": float(v.cabinLen), "wid": float(v.cabinWid),
		"height": float(v.cabinH), "style": str(v.cabinStyle), "glass": str(v.cabinStyle) != "cockpit",
		"upperLength": float(v.cabinLen) * 0.62, "upperWidth": float(v.cabinWid) * 0.74, "upperHeight": float(v.cabinH) + 6.0,
		"footprintRadius": Vector2(float(v.cabinLen), float(v.cabinWid)).length() * 0.5
	}
	var stacks: Array = []
	var scount: int = int(v.stacks)
	var spread: float = float(v.stackSpread)
	for i in range(scount):
		var sy: float = (spread if str(v.arch) == "hydrofoil" else 0.0) if scount == 1 else (-spread if i == 0 else spread)
		stacks.append({"id": "stack%d" % i, "kind": "circle", "x": float(v.engineX) - 0.02, "y": sy, "radius": float(v.stackR), "height": 19.0})
	var vlen: float = minf(0.26, float(v.engineLen) * 0.78)
	var vwid: float = minf(0.24, float(v.engineWid) * 0.55)
	var vents: Array = [{"id": "vent0", "kind": "rect", "x": float(v.engineX) + 0.03, "y": 0.0 if scount != 1 else -0.14, "length": vlen, "width": vwid, "len": vlen, "wid": vwid, "height": 11.5, "slats": int(v.slats)}]
	var pods: Array = []
	if str(v.arch) == "speedboat" or is_cat:
		for side in [-1.0, 1.0]:
			pods.append({"x": float(v.engineX) - (0.04 if not is_cat else 0.0), "y": side * (CAT_OFFSET if is_cat else 0.14), "length": 0.28 if is_cat else 0.22, "width": 0.18 if is_cat else 0.12, "height": 13.0})
	var engine: Dictionary = {
		"id": "engine", "kind": "rect", "x": float(v.engineX), "y": 0.0,
		"length": float(v.engineLen), "width": float(v.engineWid), "len": float(v.engineLen), "wid": float(v.engineWid),
		"height": float(v.engineH), "style": str(v.arch), "stacks": stacks, "vents": vents, "pods": pods,
		"footprintRadius": Vector2(float(v.engineLen), float(v.engineWid)).length() * 0.5
	}
	var masts: Array = [{"x": float(v.cabinX) - float(v.cabinLen) * 0.22, "y": 0.0, "height": 38.0 + float(v.tier) * 3.0, "pennant": int(v.tier) >= 2}]
	if str(v.arch) == "command":
		masts.append({"x": float(v.cabinX) + float(v.cabinLen) * 0.35, "y": 0.0, "height": 30.0, "pennant": false})
	var helm: Dictionary = {"x": float(v.cabinX) + float(v.cabinLen) * 0.18, "y": 0.10 if not is_cat else -0.14, "height": 14.0}
	var footprints: Array = [cabin, engine] + stacks + vents
	var sockets: Array = []
	for pt in hardpoints(spec):
		sockets.append({"id": pt.id, "label": pt.label, "slot": pt.slot, "size": pt.size, "x": pt.localX, "y": pt.localY, "worldX": pt.x, "worldY": pt.y, "arc": pt.arc, "angle": pt.angle, "outwardAngle": pt.outwardAngle, "footprintRadius": pt.footprintRadius, "elevation": pt.elevation, "muzzleOffset": pt.muzzleOffset, "originX": pt.originX, "originY": pt.originY})
	return {
		"hullId": str(spec.get("id", "boat")), "role": str(v.role), "archetype": str(v.arch), "faction": str(spec.get("faction", "compact")),
		"tier": int(v.tier), "size": size, "fittingBudget": _budget(spec), "bounds": bounds,
		"cabin": cabin, "bridge": cabin, "engine": engine, "stacks": stacks, "vents": vents,
		"masts": masts, "helm": helm, "footprints": footprints, "sockets": sockets
	}

static func _mount_scale(raw) -> float:
	if raw is String:
		match str(raw).to_lower():
			"small", "s": return 0.8
			"medium", "m": return 1.0
			"large", "l": return 1.3
			_: return 1.0
	var v: float = _number(raw, 0.0)
	return 1.0 if v <= 0.0 else (clampf(0.65 + 0.25 * v, 0.7, 1.5) if v <= 3.5 else 1.4)

static func mounts_of(spec: Dictionary) -> Array:
	var size: float = hull_size(spec)
	var sockets: Array = hardpoints(spec)
	var by_id: Dictionary = {}
	for s in sockets:
		by_id[str(s.id)] = s
	var out: Array = []
	var fitted = spec.get("weaponMounts", null)
	if spec.has("weaponMounts") and fitted is Array:
		for m in fitted:
			if not (m is Dictionary):
				continue
			var kind: String = str(m.get("kind", "gun")).to_lower()
			if kind in ["mg", "machinegun", "machine_gun", "autocannon", "bullet"]: kind = "gun"
			elif kind in ["shell", "howitzer"]: kind = "cannon"
			elif kind in ["missile", "rockets"]: kind = "rocket"
			elif kind in ["torpedoes", "tube"]: kind = "torpedo"
			if kind not in ["gun", "cannon", "rocket", "torpedo"]: kind = "gun"
			var mid: String = str(m.get("id", "mount%d" % out.size()))
			var sock: Dictionary = by_id.get(mid, sockets[0] if not sockets.is_empty() else {})
			var lx: float = clampf(_number(m.get("x"), float(sock.get("x", 0.0))) / size, -2.2, 2.2)
			var ly: float = clampf(_number(m.get("y"), float(sock.get("y", 0.0))) / size, -1.2, 1.2)
			var ang: float = _number(m.get("angle"), float(sock.get("angle", 0.0)))
			var muz: float = float(sock.get("muzzleOffset", 0.40))
			var dir: Vector2 = Vector2.from_angle(ang)
			out.append({"id": mid, "kind": kind, "x": lx, "y": ly, "worldX": lx * size, "worldY": ly * size, "angle": ang, "arc": _number(m.get("arc"), float(sock.get("arc", TAU))), "scale": _mount_scale(m.get("size", sock.get("size", 1))), "footprintRadius": float(sock.get("footprintRadius", 0.16)), "elevation": float(sock.get("elevation", 11.5)), "muzzleOffset": muz, "originX": lx + dir.x * muz, "originY": ly + dir.y * muz})
			if out.size() >= 6:
				break
		return out
	var primary: Dictionary = sockets[0]
	var wkind: String = str(spec.get("weapon", "gun")).to_lower()
	if wkind not in ["gun", "cannon", "rocket", "torpedo"]:
		wkind = "gun"
	out.append({"id": primary.id, "kind": wkind, "x": primary.localX, "y": primary.localY, "worldX": primary.x, "worldY": primary.y, "angle": 0.0, "arc": primary.arc, "scale": _mount_scale(primary.size), "footprintRadius": primary.footprintRadius, "elevation": primary.elevation, "muzzleOffset": primary.muzzleOffset, "originX": primary.originX, "originY": primary.originY})
	return out

static func footprint_clearance(socket: Dictionary, item: Dictionary) -> float:
	var sx: float = _number(socket.get("localX", socket.get("x", 0.0)))
	var sy: float = _number(socket.get("localY", socket.get("y", 0.0)))
	var sr: float = _number(socket.get("footprintRadius"), 0.16)
	var ix: float = _number(item.get("x"))
	var iy: float = _number(item.get("y"))
	if str(item.get("kind", "rect")) == "circle":
		return Vector2(sx - ix, sy - iy).length() - (sr + _number(item.get("radius"), 0.10))
	var hx: float = _number(item.get("length", item.get("len", 0.0))) * 0.5
	var hy: float = _number(item.get("width", item.get("wid", 0.0))) * 0.5
	return Vector2(maxf(0.0, absf(sx - ix) - hx), maxf(0.0, absf(sy - iy) - hy)).length() - sr
