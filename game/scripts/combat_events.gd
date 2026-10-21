extends RefCounted
## Pure bounded combat event, effect, wreck and mount-shot metadata for Battle.
## State belongs exclusively to the battle dictionary passed by the caller.

const MAX_EVENTS: int = 256
const MAX_STEP_EVENTS: int = 128
const MAX_EFFECTS: int = 200
const MAX_WRECKS: int = 64
const SINK_DURATION: float = 2.2
const FAMILIES: Array = ["gun", "cannon", "rocket", "torpedo"]
const EVENT_KINDS: Array = ["fire", "hit", "miss", "sink", "engine"]
const MATERIALS: Array = ["wood", "armor", "water", "land", "engine", "metal"]

static func number(value, fallback: float = 0.0) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return float(value)
	return fallback

static func weapon_family(raw_kind) -> String:
	var kind: String = str(raw_kind).to_lower()
	match kind:
		"gun", "bullet", "mg", "machinegun", "machine_gun", "autocannon":
			return "gun"
		"cannon", "shell", "howitzer", "ram":
			return "cannon"
		"rocket", "rockets", "missile":
			return "rocket"
		"torpedo", "torpedoes", "tube":
			return "torpedo"
		"hull", "ship", "wreck", "engine":
			return "hull"
		_:
			return "gun" if not kind.is_empty() else ""

static func projectile_kind(raw_kind) -> String:
	var kind: String = str(raw_kind).to_lower()
	match kind:
		"gun", "bullet":
			return "bullet"
		"cannon", "shell":
			return "shell"
		"rocket", "rockets":
			return "rocket"
		"torpedo", "torpedoes":
			return "torpedo"
		_:
			return "bullet" if not kind.is_empty() else ""

static func weapon_variant(family: String, mount_or_proj: Dictionary = {}) -> String:
	var module_id: String = str(mount_or_proj.get("moduleId", "")).to_lower()
	if module_id.begins_with("heavy_") or module_id == "salvo_rocket":
		return "heavy"
	if module_id in ["rapid_gun", "light_cannon", "fire_rocket", "light_torpedo"]:
		return "light"
	var size_val: int = int(number(mount_or_proj.get("size"), 1.0))
	if size_val >= 2:
		return "heavy"
	var dmg: float = number(mount_or_proj.get("damage"), 0.0)
	match family:
		"gun":
			return "heavy" if dmg >= 15.0 else "light"
		"cannon":
			return "heavy" if dmg >= 38.0 else "light"
		"rocket":
			return "heavy" if dmg >= 42.0 else "light"
		"torpedo":
			return "heavy" if dmg >= 50.0 else "light"
		_:
			return "light"

static func archetype(spec: Dictionary) -> String:
	var role: String = str(spec.get("role", "skiff"))
	match role:
		"skiff":
			return "speedboat"
		"cutter", "torpedo":
			return "hydrofoil"
		"raider":
			return "catamaran"
		"corvette":
			return "patrol"
		"gunboat":
			return "armored"
		"rocket":
			return "monitor"
		"cruiser":
			return "command"
		_:
			return "patrol"

static func hull_material(ship_or_spec: Dictionary) -> String:
	var spec: Dictionary = ship_or_spec.get("spec", ship_or_spec) if ship_or_spec.get("spec") is Dictionary else ship_or_spec
	var armor_val: float = maxf(number(ship_or_spec.get("armor"), 0.0), number(spec.get("armor"), 0.0))
	var role: String = str(spec.get("role", "skiff"))
	var loadout_armor: String = ""
	if ship_or_spec.get("loadout") is Dictionary:
		loadout_armor = str(ship_or_spec.loadout.get("armor", ""))
	if armor_val >= 6.0 or role in ["gunboat", "rocket", "cruiser"] or loadout_armor in ["naval_plating", "fortress_plating"]:
		return "armor"
	return "wood"

static func _engine_stage(engine_value: float) -> int:
	var e: float = clampf(number(engine_value, 1.0), 0.0, 1.0)
	if e <= 0.05:
		return 3
	if e <= 0.35:
		return 2
	if e <= 0.65:
		return 1
	return 0

static func ensure_state(st: Dictionary) -> void:
	if not (st.get("events") is Array):
		st.events = []
	if not (st.get("eventSeq") is int or st.get("eventSeq") is float):
		st.eventSeq = 0
	if not (st.get("droppedEvents") is int or st.get("droppedEvents") is float):
		st.droppedEvents = 0
	if not (st.get("_stepEvents") is int or st.get("_stepEvents") is float):
		st._stepEvents = 0
	if not (st.get("_engineTracker") is Dictionary):
		st._engineTracker = {}
	if not (st.get("_hitTracker") is Dictionary):
		st._hitTracker = {}

static func begin_step(st: Dictionary) -> void:
	ensure_state(st)
	st._stepEvents = 0

static func sync_mount_shots(ship: Dictionary, mounts: Array) -> void:
	if not (ship.get("lastShotTime") is float or ship.get("lastShotTime") is int):
		ship.lastShotTime = -1.0
	if not (ship.get("lastShotMount") is String):
		ship.lastShotMount = ""
	if not (ship.get("lastShotFamily") is String):
		ship.lastShotFamily = ""
	if not (ship.get("battleTime") is float or ship.get("battleTime") is int):
		ship.battleTime = 0.0
	if not (ship.get("weaponShotTimes") is Array):
		ship.weaponShotTimes = []
	while ship.weaponShotTimes.size() < mounts.size():
		ship.weaponShotTimes.append(-1.0)
	if ship.weaponShotTimes.size() > mounts.size():
		ship.weaponShotTimes.resize(mounts.size())
	if not (ship.get("mountShotTimes") is Dictionary):
		ship.mountShotTimes = {}
	var valid_ids: Dictionary = {}
	for i in range(mounts.size()):
		var mount: Dictionary = mounts[i]
		var mount_id: String = str(mount.get("id", "mount-%d" % i))
		valid_ids[mount_id] = true
		if not ship.mountShotTimes.has(mount_id):
			ship.mountShotTimes[mount_id] = -1.0
	for existing_id in ship.mountShotTimes.keys():
		if not valid_ids.has(str(existing_id)):
			ship.mountShotTimes.erase(existing_id)

static func record_mount_shot(ship: Dictionary, mount: Dictionary, index: int, time: float) -> void:
	var t: float = maxf(0.0, number(time, 0.0))
	var mount_id: String = str(mount.get("id", "mount-%d" % index))
	var fam: String = weapon_family(mount.get("kind", "gun"))
	ship.lastShotTime = t
	ship.lastShotMount = mount_id
	ship.lastShotFamily = fam
	ship.battleTime = maxf(number(ship.get("battleTime"), 0.0), t)
	if not (ship.get("weaponShotTimes") is Array):
		ship.weaponShotTimes = []
	while ship.weaponShotTimes.size() <= index:
		ship.weaponShotTimes.append(-1.0)
	if index >= 0:
		ship.weaponShotTimes[index] = t
	if not (ship.get("mountShotTimes") is Dictionary):
		ship.mountShotTimes = {}
	ship.mountShotTimes[mount_id] = t

static func mount_shot_time(ship: Dictionary, mount_id_or_index) -> float:
	if mount_id_or_index is int:
		var idx: int = int(mount_id_or_index)
		var arr = ship.get("weaponShotTimes", [])
		if arr is Array and idx >= 0 and idx < arr.size():
			return number(arr[idx], -1.0)
		return -1.0
	var key: String = str(mount_id_or_index)
	var by_mount = ship.get("mountShotTimes", {})
	if by_mount is Dictionary and by_mount.has(key):
		return number(by_mount[key], -1.0)
	if key.is_valid_int():
		var idx2: int = int(key)
		var arr2 = ship.get("weaponShotTimes", [])
		if arr2 is Array and idx2 >= 0 and idx2 < arr2.size():
			return number(arr2[idx2], -1.0)
	return -1.0

static func mount_shot_age(ship: Dictionary, mount_id_or_index, now: float = NAN) -> float:
	var shot_time: float = mount_shot_time(ship, mount_id_or_index)
	if shot_time < 0.0:
		return INF
	var ref_time: float = now if is_finite(now) else number(ship.get("battleTime"), shot_time)
	return maxf(0.0, ref_time - shot_time)

static func register_ship(st: Dictionary, ship: Dictionary, mounts: Array) -> void:
	ensure_state(st)
	ship.lastShotTime = -1.0
	ship.lastShotMount = ""
	ship.lastShotFamily = ""
	ship.battleTime = 0.0
	ship.weaponShotTimes = []
	ship.mountShotTimes = {}
	sync_mount_shots(ship, mounts)
	var ship_id: String = str(ship.get("id", ""))
	if not ship_id.is_empty():
		st._engineTracker[ship_id] = {
			"engine": clampf(number(ship.get("engine"), 1.0), 0.0, 1.0),
			"stage": _engine_stage(number(ship.get("engine"), 1.0))
		}
		st._hitTracker.erase(ship_id)

static func push_event(st: Dictionary, raw: Dictionary) -> Dictionary:
	ensure_state(st)
	if int(st._stepEvents) >= MAX_STEP_EVENTS:
		st.droppedEvents = int(st.droppedEvents) + 1
		return {}
	st._stepEvents = int(st._stepEvents) + 1
	st.eventSeq = int(st.eventSeq) + 1
	var seq: int = int(st.eventSeq)
	var kind: String = str(raw.get("kind", "hit"))
	if kind not in EVENT_KINDS:
		kind = "hit"
	var fam: String = weapon_family(raw.get("family", raw.get("weapon", "gun")))
	var proj_kind: String = str(raw.get("projectileKind", ""))
	if proj_kind.is_empty() and fam in FAMILIES:
		proj_kind = projectile_kind(fam)
	var x: float = number(raw.get("x"), 0.0)
	var y: float = number(raw.get("y"), 0.0)
	if raw.get("position") is Vector2:
		var pos_v: Vector2 = raw.position
		x = number(pos_v.x, x)
		y = number(pos_v.y, y)
	var angle: float = wrapf(number(raw.get("angle"), 0.0), -PI, PI)
	if raw.get("direction") is Vector2 and raw.direction.length_squared() > 0.0001:
		angle = wrapf(raw.direction.angle(), -PI, PI)
	var dir: Vector2 = Vector2.from_angle(angle)
	var source_id: String = str(raw.get("sourceId", raw.get("source", "")))
	var target_id: String = str(raw.get("targetId", raw.get("target", "")))
	var mount_id: String = str(raw.get("mountId", raw.get("mount", "")))
	var mat: String = str(raw.get("material", "water"))
	if mat not in MATERIALS:
		mat = "water"
	var hull_mat: String = str(raw.get("hullMaterial", mat if mat in ["wood", "armor"] else "wood"))
	var subtype: String = str(raw.get("subtype", kind))
	var reason: String = str(raw.get("reason", subtype))
	var event: Dictionary = {
		"id": seq,
		"seq": seq,
		"sequence": seq,
		"kind": kind,
		"type": str(raw.get("type", kind)),
		"subtype": subtype,
		"reason": reason,
		"time": number(raw.get("time"), number(st.get("time"), 0.0)),
		"family": fam,
		"weaponFamily": fam,
		"weapon": fam,
		"projectileKind": proj_kind,
		"variant": str(raw.get("variant", "light")),
		"moduleId": str(raw.get("moduleId", "")),
		"sourceId": source_id,
		"source": source_id,
		"sourceUid": str(raw.get("sourceUid", source_id)),
		"sourceHull": str(raw.get("sourceHull", "")),
		"sourceTeam": str(raw.get("sourceTeam", raw.get("team", ""))),
		"targetId": target_id,
		"target": target_id,
		"targetUid": str(raw.get("targetUid", target_id)),
		"targetHull": str(raw.get("targetHull", "")),
		"targetTeam": str(raw.get("targetTeam", "")),
		"shipId": str(raw.get("shipId", target_id if not target_id.is_empty() else source_id)),
		"team": str(raw.get("team", "player")),
		"mountId": mount_id,
		"mount": mount_id,
		"mountIndex": int(number(raw.get("mountIndex"), -1.0)),
		"x": x,
		"y": y,
		"position": Vector2(x, y),
		"angle": angle,
		"direction": dir,
		"dx": dir.x,
		"dy": dir.y,
		"material": mat,
		"hullMaterial": hull_mat,
		"section": str(raw.get("section", "")),
		"magnitude": clampf(number(raw.get("magnitude"), 1.0), 0.05, 10.0),
		"damage": maxf(0.0, number(raw.get("damage"), 0.0)),
		"engine": clampf(number(raw.get("engine"), 1.0), 0.0, 1.0),
		"splash": bool(raw.get("splash", false)),
		"land": bool(raw.get("land", false)),
		"expired": bool(raw.get("expired", false)),
		"direct": bool(raw.get("direct", false)),
		"breach": bool(raw.get("breach", false)),
		"incendiary": bool(raw.get("incendiary", false)),
		"engineDamaged": bool(raw.get("engineDamaged", false)),
		"sunk": bool(raw.get("sunk", false))
	}
	if st.events.size() >= MAX_EVENTS:
		st.events.pop_front()
		st.droppedEvents = int(st.droppedEvents) + 1
	st.events.append(event)
	return event

static func pop_events(st: Dictionary) -> Array:
	ensure_state(st)
	if st.events.is_empty():
		return []
	var out: Array = st.events.duplicate()
	st.events.clear()
	return out

static func _effect_profile(type: String, fam: String, variant: String, mat: String, raw: Dictionary) -> Dictionary:
	var heavy: bool = variant == "heavy"
	var kind: String = str(raw.get("kind", "fire" if type == "muzzle" else ("miss" if type == "splash" else "hit")))
	var life: float = 1.3 if type == "explosion" else (0.16 if type == "muzzle" else 0.45)
	var mag: float = 1.0
	var radius: float = 14.0
	var length: float = 14.0
	var width: float = 6.0
	var height: float = 9.0
	var recoil: float = 0.0
	var smoke: float = 0.2
	var fragments: int = 2
	var subtype: String = str(raw.get("subtype", type))
	if kind == "fire" or type == "muzzle":
		height = 14.0
		match fam:
			"gun":
				life = 0.11 if not heavy else 0.14
				mag = 0.45 if not heavy else 0.62
				radius = 6.0 if not heavy else 8.0
				length = 11.0 if not heavy else 15.0
				width = 3.5 if not heavy else 5.0
				recoil = 0.08 if not heavy else 0.12
				smoke = 0.12
				fragments = 1
				subtype = "muzzle_flash"
			"cannon":
				life = 0.22 if not heavy else 0.28
				mag = 0.88 if not heavy else 1.15
				radius = 11.0 if not heavy else 14.5
				length = 18.0 if not heavy else 24.0
				width = 7.5 if not heavy else 10.0
				recoil = 0.26 if not heavy else 0.36
				smoke = 0.65
				fragments = 3
				subtype = "cannon_flash"
			"rocket":
				life = 0.26 if not heavy else 0.32
				mag = 0.90 if not heavy else 1.15
				radius = 9.5 if not heavy else 12.5
				length = 16.0 if not heavy else 21.0
				width = 6.5 if not heavy else 8.5
				recoil = 0.0
				smoke = 0.75
				fragments = 3
				subtype = "rack_ignition"
			"torpedo":
				life = 0.30 if not heavy else 0.36
				mag = 0.72 if not heavy else 0.92
				radius = 8.5 if not heavy else 11.0
				length = 14.0 if not heavy else 18.0
				width = 5.5 if not heavy else 7.0
				height = 0.0
				recoil = 0.0
				smoke = 0.10
				fragments = 2
				subtype = "tube_launch"
	elif kind == "miss":
		var is_land: bool = bool(raw.get("land", mat == "land"))
		height = 6.0 if is_land else 0.0
		match fam:
			"gun":
				life = 0.28 if is_land else 0.32
				mag = 0.40 if not heavy else 0.54
				radius = 7.0 if not heavy else 9.0
				length = 10.0 if not heavy else 13.0
				width = 4.0
				smoke = 0.20 if is_land else 0.05
				fragments = 2
				subtype = "dirt_kick" if is_land else "water_kick"
			"cannon":
				life = 0.48 if is_land else 0.56
				mag = 0.82 if not heavy else 1.05
				radius = 13.0 if not heavy else 16.5
				length = 18.0 if not heavy else 23.0
				width = 7.5
				smoke = 0.45 if is_land else 0.15
				fragments = 4
				subtype = "land_impact" if is_land else "water_plume"
			"rocket":
				life = 0.62 if not heavy else 0.72
				mag = 0.95 if not heavy else 1.20
				radius = 18.0 if not heavy else 22.0
				length = 20.0
				width = 12.0
				smoke = 0.70 if is_land else 0.45
				fragments = 5
				subtype = "land_blast" if is_land else "water_blast"
			"torpedo":
				life = 0.52 if is_land else 0.72
				mag = 0.88 if not heavy else 1.12
				radius = 15.0 if not heavy else 19.0
				length = 22.0
				width = 9.0
				smoke = 0.25 if is_land else 0.10
				fragments = 4
				subtype = "shore_surge" if is_land else "water_surge"
	elif kind == "sink":
		life = 1.65
		mag = clampf(number(raw.get("magnitude"), 1.35), 0.75, 2.4)
		radius = clampf(number(raw.get("radius"), 22.0), 12.0, 48.0)
		length = radius * 1.45
		width = radius * 0.95
		height = 0.0
		smoke = 0.60
		fragments = 6
		subtype = "hull_down"
	elif kind == "engine":
		life = 0.75
		mag = clampf(number(raw.get("magnitude"), 0.75), 0.30, 1.25)
		radius = 11.0
		length = 16.0
		width = 7.0
		height = 13.0
		smoke = 0.85
		fragments = 3
		subtype = "engine_failure"
	else:
		match fam:
			"gun":
				life = 0.25 if not heavy else 0.32
				mag = 0.52 if not heavy else 0.68
				radius = 8.5 if not heavy else 10.5
				length = 12.0
				width = 5.0
				height = 9.0
				smoke = 0.18
				fragments = 3
				subtype = "armor_ricochet" if mat == "armor" else "wood_hit"
			"cannon":
				life = 0.46 if not heavy else 0.56
				mag = 0.95 if not heavy else 1.22
				radius = 14.5 if not heavy else 18.5
				length = 19.0
				width = 8.5
				height = 10.0
				smoke = 0.55
				fragments = 5
				subtype = "armor_sparks" if mat == "armor" else "wood_splinters"
			"rocket":
				life = 0.68 if not heavy else 0.78
				mag = 1.12 if not heavy else 1.35
				radius = 20.0 if not heavy else 24.5
				length = 22.0
				width = 14.0
				height = 12.0
				smoke = 0.80
				fragments = 5
				subtype = "rocket_blast"
			"torpedo":
				life = 0.88 if not heavy else 1.02
				mag = 1.30 if not heavy else 1.55
				radius = 22.0 if not heavy else 27.0
				length = 28.0
				width = 13.0
				height = 0.0
				smoke = 0.35
				fragments = 6
				subtype = "water_column"
	return {
		"life": number(raw.get("life"), life),
		"magnitude": number(raw.get("magnitude"), mag),
		"radius": number(raw.get("radius"), radius),
		"length": number(raw.get("length"), length),
		"width": number(raw.get("width"), width),
		"height": number(raw.get("height"), height),
		"recoil": number(raw.get("recoil"), recoil),
		"smoke": number(raw.get("smoke"), smoke),
		"fragments": int(number(raw.get("fragments"), float(fragments))),
		"subtype": str(raw.get("subtype", subtype))
	}

static func add_effect(st: Dictionary, p: Vector2, type: String, raw: Dictionary = {}) -> Dictionary:
	var fam: String = weapon_family(raw.get("family", raw.get("weapon", "gun" if type == "muzzle" else "cannon")))
	var variant: String = str(raw.get("variant", weapon_variant(fam, raw)))
	var mat: String = str(raw.get("material", "water" if type == "splash" else ("metal" if type == "muzzle" else "wood")))
	if mat not in MATERIALS:
		mat = "water" if type == "splash" else "wood"
	var kind: String = str(raw.get("kind", "fire" if type == "muzzle" else ("miss" if type == "splash" else "hit")))
	var angle: float = wrapf(number(raw.get("angle"), 0.0), -PI, PI)
	if raw.get("direction") is Vector2 and raw.direction.length_squared() > 0.0001:
		angle = wrapf(raw.direction.angle(), -PI, PI)
	var dir: Vector2 = Vector2.from_angle(angle)
	var profile: Dictionary = _effect_profile(type, fam, variant, mat, raw)
	var effect: Dictionary = {
		"x": number(p.x, 0.0),
		"y": number(p.y, 0.0),
		"position": Vector2(number(p.x, 0.0), number(p.y, 0.0)),
		"type": type,
		"kind": kind,
		"subtype": profile.subtype,
		"reason": str(raw.get("reason", kind)),
		"age": 0.0,
		"life": maxf(0.05, float(profile.life)),
		"family": fam,
		"weaponFamily": fam,
		"projectileKind": str(raw.get("projectileKind", projectile_kind(fam))),
		"variant": variant,
		"material": mat,
		"hullMaterial": str(raw.get("hullMaterial", mat if mat in ["wood", "armor"] else "wood")),
		"angle": angle,
		"direction": dir,
		"dx": dir.x,
		"dy": dir.y,
		"magnitude": clampf(float(profile.magnitude), 0.05, 10.0),
		"radius": maxf(2.0, float(profile.radius)),
		"length": maxf(2.0, float(profile.length)),
		"width": maxf(1.0, float(profile.width)),
		"height": float(profile.height),
		"recoil": maxf(0.0, float(profile.recoil)),
		"smoke": clampf(float(profile.smoke), 0.0, 1.0),
		"fragments": maxi(0, int(profile.fragments)),
		"sourceId": str(raw.get("sourceId", raw.get("source", ""))),
		"targetId": str(raw.get("targetId", raw.get("target", ""))),
		"mountId": str(raw.get("mountId", raw.get("mount", ""))),
		"team": str(raw.get("team", "player")),
		"section": str(raw.get("section", "")),
		"splash": bool(raw.get("splash", type == "splash" or mat == "water")),
		"land": bool(raw.get("land", mat == "land")),
		"expired": bool(raw.get("expired", false)),
		"breach": bool(raw.get("breach", false)),
		"incendiary": bool(raw.get("incendiary", false)),
		"engineDamaged": bool(raw.get("engineDamaged", false)),
		"sunk": bool(raw.get("sunk", false)),
		"seq": int(number(raw.get("seq"), 0.0))
	}
	st.effects.append(effect)
	if st.effects.size() > MAX_EFFECTS:
		st.effects.pop_front()
	return effect

static func emit_fire(st: Dictionary, ship: Dictionary, mount: Dictionary, mount_index: int, muzzle: Vector2, angle: float, target_ship: Dictionary = {}) -> Dictionary:
	record_mount_shot(ship, mount, mount_index, number(st.get("time"), 0.0))
	var fam: String = weapon_family(mount.get("kind", "gun"))
	var variant: String = weapon_variant(fam, mount)
	var proj_kind: String = projectile_kind(fam)
	var hull_mat: String = hull_material(ship)
	var mat: String = "water" if fam == "torpedo" else "metal"
	var mag: float = (0.45 if fam == "gun" else (0.88 if fam == "cannon" else (0.90 if fam == "rocket" else 0.72))) * (1.25 if variant == "heavy" else 1.0)
	var target_id: String = str(target_ship.get("id", ""))
	var target_spec: Dictionary = target_ship.get("spec", {}) if target_ship.get("spec") is Dictionary else {}
	var ev: Dictionary = push_event(st, {
		"kind": "fire",
		"type": "fire",
		"subtype": "launch" if fam in ["rocket", "torpedo"] else "muzzle",
		"reason": "fire",
		"family": fam,
		"projectileKind": proj_kind,
		"variant": variant,
		"moduleId": str(mount.get("moduleId", "")),
		"sourceId": str(ship.get("id", "")),
		"sourceUid": str(ship.get("uid", ship.get("id", ""))),
		"sourceHull": str(ship.get("type", ship.get("spec", {}).get("id", "boat"))) if ship.get("spec") is Dictionary else str(ship.get("type", "boat")),
		"sourceTeam": str(ship.get("team", "player")),
		"targetId": target_id,
		"targetUid": str(target_ship.get("uid", target_id)),
		"targetHull": str(target_ship.get("type", target_spec.get("id", ""))),
		"targetTeam": str(target_ship.get("team", "")),
		"shipId": str(ship.get("id", "")),
		"team": str(ship.get("team", "player")),
		"mountId": str(mount.get("id", "mount-%d" % mount_index)),
		"mountIndex": mount_index,
		"height":number(mount.get("barrelHeight"),9.0),
		"x": muzzle.x,
		"y": muzzle.y,
		"angle": angle,
		"material": mat,
		"hullMaterial": hull_mat,
		"magnitude": mag,
		"damage": number(mount.get("damage"), 10.0) * (1.8 if fam == "torpedo" else 1.0),
		"splash": fam == "torpedo",
		"incendiary": fam == "rocket"
	})
	add_effect(st, muzzle, "muzzle", {
		"kind": "fire",
		"height":number(mount.get("barrelHeight"),9.0),
		"family": fam,
		"projectileKind": proj_kind,
		"variant": variant,
		"material": mat,
		"hullMaterial": hull_mat,
		"angle": angle,
		"magnitude": mag,
		"sourceId": str(ship.get("id", "")),
		"targetId": target_id,
		"mountId": str(mount.get("id", "mount-%d" % mount_index)),
		"team": str(ship.get("team", "player")),
		"splash": fam == "torpedo",
		"incendiary": fam == "rocket",
		"seq": int(ev.get("seq", 0))
	})
	return ev

static func emit_hit(st: Dictionary, proj: Dictionary, target_ship: Dictionary, point: Vector2, section: String, damage_events: Array, hp_lost: float, direct: bool = true) -> Dictionary:
	ensure_state(st)
	var fam: String = weapon_family(proj.get("family", proj.get("kind", "bullet")))
	var proj_kind: String = projectile_kind(proj.get("kind", fam))
	var variant: String = str(proj.get("variant", weapon_variant(fam, proj)))
	var mat: String = hull_material(target_ship)
	var vel: Vector2 = Vector2(number(proj.get("vx"), 1.0), number(proj.get("vy"), 0.0))
	var angle: float = vel.angle() if vel.length_squared() > 0.0001 else number(proj.get("angle"), 0.0)
	var breached: bool = false
	var engine_damaged: bool = false
	var ignited: bool = false
	for entry in damage_events:
		var text: String = str(entry)
		if text.begins_with("Breach:"):
			breached = true
		elif text == "Engine damaged":
			engine_damaged = true
		elif text == "Fire aboard":
			ignited = true
	var sunk_now: bool = bool(target_ship.get("sunk", false))
	var source_id: String = str(proj.get("owner", proj.get("sourceId", "")))
	var mount_id: String = str(proj.get("mountId", proj.get("mount", "primary")))
	var source_team: String = str(proj.get("team", "player"))
	var target_id: String = str(target_ship.get("id", ""))
	var target_spec: Dictionary = target_ship.get("spec", {}) if target_ship.get("spec") is Dictionary else {}
	if not target_id.is_empty():
		st._hitTracker[target_id] = {
			"sourceId": source_id,
			"team": source_team,
			"mountId": mount_id,
			"family": fam,
			"material": mat
		}
	var base_mag: float = (0.55 if fam == "gun" else (1.0 if fam == "cannon" else (1.15 if fam == "rocket" else 1.35))) * (1.2 if variant == "heavy" else 1.0) * (1.0 if direct else 0.7)
	var ev: Dictionary = push_event(st, {
		"kind": "hit",
		"type": "hit",
		"subtype": "direct" if direct else "blast",
		"reason": "direct" if direct else "blast",
		"family": fam,
		"projectileKind": proj_kind,
		"variant": variant,
		"moduleId": str(proj.get("moduleId", "")),
		"sourceId": source_id,
		"sourceUid": str(proj.get("sourceUid", source_id)),
		"sourceHull": str(proj.get("sourceHull", "")),
		"sourceTeam": source_team,
		"targetId": target_id,
		"targetUid": str(target_ship.get("uid", target_id)),
		"targetHull": str(target_ship.get("type", target_spec.get("id", "boat"))),
		"targetTeam": str(target_ship.get("team", "")),
		"shipId": target_id,
		"team": source_team,
		"mountId": mount_id,
		"mountIndex": int(number(proj.get("mountIndex"), 0.0)),
		"x": point.x,
		"y": point.y,
		"angle": angle,
		"material": mat,
		"hullMaterial": mat,
		"section": section,
		"magnitude": base_mag,
		"damage": maxf(0.0, hp_lost),
		"engine": number(target_ship.get("engine"), 1.0),
		"splash": fam == "torpedo",
		"direct": direct,
		"breach": breached,
		"incendiary": ignited or bool(proj.get("incendiary", false)),
		"engineDamaged": engine_damaged,
		"sunk": sunk_now
	})
	if direct:
		var effect_type: String = "explosion" if proj_kind in ["torpedo", "rocket"] else "hit"
		add_effect(st, point, effect_type, {
			"kind": "hit",
			"reason": "direct",
			"family": fam,
			"projectileKind": proj_kind,
			"variant": variant,
			"material": mat,
			"hullMaterial": mat,
			"angle": angle,
			"magnitude": base_mag,
			"sourceId": source_id,
			"targetId": target_id,
			"mountId": mount_id,
			"team": source_team,
			"section": section,
			"splash": fam == "torpedo",
			"breach": breached,
			"incendiary": ignited or bool(proj.get("incendiary", false)),
			"engineDamaged": engine_damaged,
			"sunk": sunk_now,
			"seq": int(ev.get("seq", 0))
		})
	if engine_damaged:
		emit_engine_failure(st, target_ship, "hit", point, proj)
	return ev

static func emit_miss(st: Dictionary, proj: Dictionary, point: Vector2, hit_land: bool) -> Dictionary:
	var fam: String = weapon_family(proj.get("family", proj.get("kind", "bullet")))
	var proj_kind: String = projectile_kind(proj.get("kind", fam))
	var variant: String = str(proj.get("variant", weapon_variant(fam, proj)))
	var mat: String = "land" if hit_land else "water"
	var reason: String = "land" if hit_land else "expired"
	var subtype: String = "land" if hit_land else "splash"
	var vel: Vector2 = Vector2(number(proj.get("vx"), 1.0), number(proj.get("vy"), 0.0))
	var angle: float = vel.angle() if vel.length_squared() > 0.0001 else number(proj.get("angle"), 0.0)
	var source_id: String = str(proj.get("owner", proj.get("sourceId", "")))
	var mount_id: String = str(proj.get("mountId", proj.get("mount", "primary")))
	var source_team: String = str(proj.get("team", "player"))
	var mag: float = (0.40 if fam == "gun" else (0.82 if fam == "cannon" else (0.95 if fam == "rocket" else 0.88))) * (1.2 if variant == "heavy" else 1.0)
	var ev: Dictionary = push_event(st, {
		"kind": "miss",
		"type": "miss",
		"subtype": subtype,
		"reason": reason,
		"family": fam,
		"projectileKind": proj_kind,
		"variant": variant,
		"moduleId": str(proj.get("moduleId", "")),
		"sourceId": source_id,
		"sourceUid": str(proj.get("sourceUid", source_id)),
		"sourceHull": str(proj.get("sourceHull", "")),
		"sourceTeam": source_team,
		"targetId": "",
		"targetUid": "",
		"targetHull": "",
		"targetTeam": "",
		"shipId": source_id,
		"team": source_team,
		"mountId": mount_id,
		"mountIndex": int(number(proj.get("mountIndex"), 0.0)),
		"x": point.x,
		"y": point.y,
		"angle": angle,
		"material": mat,
		"hullMaterial": mat,
		"section": "land" if hit_land else "water",
		"magnitude": mag,
		"damage": 0.0,
		"splash": not hit_land,
		"land": hit_land,
		"expired": not hit_land,
		"direct": false,
		"incendiary": bool(proj.get("incendiary", false))
	})
	var effect_type: String = "explosion" if proj_kind == "rocket" else ("hit" if hit_land else "splash")
	add_effect(st, point, effect_type, {
		"kind": "miss",
		"subtype": subtype,
		"reason": reason,
		"family": fam,
		"projectileKind": proj_kind,
		"variant": variant,
		"material": mat,
		"hullMaterial": mat,
		"angle": angle,
		"magnitude": mag,
		"sourceId": source_id,
		"targetId": "",
		"mountId": mount_id,
		"team": source_team,
		"section": "land" if hit_land else "water",
		"splash": not hit_land,
		"land": hit_land,
		"expired": not hit_land,
		"incendiary": bool(proj.get("incendiary", false)),
		"seq": int(ev.get("seq", 0))
	})
	return ev

static func emit_engine_failure(st: Dictionary, ship: Dictionary, reason: String, point: Vector2, proj: Dictionary = {}) -> Dictionary:
	ensure_state(st)
	var ship_id: String = str(ship.get("id", ""))
	var eng: float = clampf(number(ship.get("engine"), 1.0), 0.0, 1.0)
	if not ship_id.is_empty():
		st._engineTracker[ship_id] = {
			"engine": eng,
			"stage": _engine_stage(eng)
		}
	var last_hit: Dictionary = st._hitTracker.get(ship_id, {})
	var fam: String = weapon_family(proj.get("family", proj.get("kind", last_hit.get("family", "cannon"))))
	var proj_kind: String = projectile_kind(proj.get("kind", fam))
	var source_id: String = str(proj.get("owner", last_hit.get("sourceId", ship_id)))
	var mount_id: String = str(proj.get("mountId", last_hit.get("mountId", "")))
	var hull_mat: String = hull_material(ship)
	var ship_spec: Dictionary = ship.get("spec", {}) if ship.get("spec") is Dictionary else {}
	var angle: float = number(ship.get("angle"), 0.0)
	var mag: float = clampf(1.0 - eng + 0.25, 0.30, 1.25)
	var ev: Dictionary = push_event(st, {
		"kind": "engine",
		"type": "engine",
		"subtype": "engine_failure",
		"reason": reason,
		"family": fam,
		"projectileKind": proj_kind,
		"variant": "heavy" if eng <= 0.35 else "light",
		"sourceId": source_id,
		"sourceUid": source_id,
		"sourceTeam": str(proj.get("team", last_hit.get("team", ship.get("team", "player")))),
		"targetId": ship_id,
		"targetUid": str(ship.get("uid", ship_id)),
		"targetHull": str(ship.get("type", ship_spec.get("id", "boat"))),
		"targetTeam": str(ship.get("team", "player")),
		"shipId": ship_id,
		"team": str(ship.get("team", "player")),
		"mountId": mount_id,
		"mountIndex": int(number(proj.get("mountIndex"), -1.0)),
		"x": point.x,
		"y": point.y,
		"angle": angle,
		"material": "engine",
		"hullMaterial": hull_mat,
		"section": "engine",
		"magnitude": mag,
		"damage": 0.0,
		"engine": eng,
		"engineDamaged": true,
		"sunk": bool(ship.get("sunk", false))
	})
	add_effect(st, point, "hit", {
		"kind": "engine",
		"subtype": "engine_failure",
		"reason": reason,
		"family": fam,
		"projectileKind": proj_kind,
		"variant": "heavy" if eng <= 0.35 else "light",
		"material": "engine",
		"hullMaterial": hull_mat,
		"angle": angle,
		"magnitude": mag,
		"sourceId": source_id,
		"targetId": ship_id,
		"mountId": mount_id,
		"team": str(ship.get("team", "player")),
		"section": "engine",
		"engineDamaged": true,
		"sunk": bool(ship.get("sunk", false)),
		"seq": int(ev.get("seq", 0))
	})
	return ev

static func check_ship_engine(st: Dictionary, ship: Dictionary) -> void:
	ensure_state(st)
	if bool(ship.get("sunk", false)):
		return
	var ship_id: String = str(ship.get("id", ""))
	if ship_id.is_empty():
		return
	var eng: float = clampf(number(ship.get("engine"), 1.0), 0.0, 1.0)
	var stage: int = _engine_stage(eng)
	var prev: Dictionary = st._engineTracker.get(ship_id, {"engine": 1.0, "stage": 0})
	var prev_eng: float = number(prev.get("engine"), 1.0)
	var prev_stage: int = int(number(prev.get("stage"), 0.0))
	if stage > prev_stage or (eng <= 0.85 and prev_eng - eng >= 0.15):
		var reason: String = "fire" if number(ship.get("fire"), 0.0) > 0.0 else "failure"
		emit_engine_failure(st, ship, reason, Vector2(number(ship.get("x"), 0.0), number(ship.get("y"), 0.0)))
	elif eng > prev_eng:
		st._engineTracker[ship_id] = {"engine": eng, "stage": stage}

static func record_wreck(st: Dictionary, ship: Dictionary, radius: float) -> Dictionary:
	ensure_state(st)
	var ship_id: String = str(ship.get("id", ""))
	var last_hit: Dictionary = st._hitTracker.get(ship_id, {})
	var ship_spec: Dictionary = ship.get("spec", {}) if ship.get("spec") is Dictionary else {}
	var hull_id: String = str(ship.get("type", ship_spec.get("id", "boat")))
	var mat: String = hull_material(ship)
	var flooded: bool = number(ship.get("water"), 0.0) >= maxf(1.0, number(ship.get("capacity"), 100.0)) - 0.001 and number(ship.get("hp"), 0.0) > 0.0
	var cause: String = "flooding" if flooded else ("fire" if number(ship.get("fire"), 0.0) > 0.0 and str(last_hit.get("sourceId", "")).is_empty() else "hull")
	var hash_val: int = absi(str(ship.get("id", hull_id)).hash())
	var list_sign: float = 1.0 if hash_val % 2 == 0 else -1.0
	var wreck: Dictionary = {
		"x": number(ship.get("x"), 0.0),
		"y": number(ship.get("y"), 0.0),
		"angle": number(ship.get("angle"), 0.0),
		"turretAngle": number(ship.get("turretAngle"), number(ship.get("angle"), 0.0)),
		"name": str(ship.get("name", "Boat")),
		"team": str(ship.get("team", "enemy")),
		"size": maxf(10.0, radius),
		"id": ship_id,
		"uid": str(ship.get("uid", ship_id)),
		"type": hull_id,
		"hull": hull_id,
		"role": str(ship_spec.get("role", "skiff")),
		"faction": str(ship_spec.get("faction", "compact")),
		"archetype": archetype(ship_spec),
		"spec": ship_spec.duplicate(true),
		"material": mat,
		"cause": cause,
		"killerId": str(last_hit.get("sourceId", "")),
		"killerFamily": weapon_family(last_hit.get("family", "cannon")),
		"killerMount": str(last_hit.get("mountId", "")),
		"sunkAt": number(st.get("time"), 0.0),
		"age": 0.0,
		"sinkDuration": SINK_DURATION,
		"sinkProgress": 0.0,
		"sinking": true,
		"listAngle": list_sign * 0.38,
		"foamRadius": maxf(14.0, radius * 1.45),
		"breaches": int(ship.get("breaches", []).size()) if ship.get("breaches") is Array else 0,
		"onFire": number(ship.get("fire"), 0.0) > 0.0
	}
	st.wrecks.append(wreck)
	if st.wrecks.size() > MAX_WRECKS:
		st.wrecks.pop_front()
	return wreck

static func tick_wrecks(st: Dictionary, dt: float) -> void:
	if not (st.get("wrecks") is Array):
		return
	for wreck in st.wrecks:
		if not (wreck is Dictionary):
			continue
		var age: float = maxf(0.0, number(wreck.get("age"), 0.0) + dt)
		var duration: float = maxf(0.1, number(wreck.get("sinkDuration"), SINK_DURATION))
		wreck.age = age
		wreck.sinkProgress = clampf(age / duration, 0.0, 1.0)
		wreck.sinking = age < duration

static func emit_sink(st: Dictionary, ship: Dictionary, wreck: Dictionary) -> Dictionary:
	ensure_state(st)
	var ship_id: String = str(ship.get("id", ""))
	var last_hit: Dictionary = st._hitTracker.get(ship_id, {})
	var fam: String = weapon_family(last_hit.get("family", "cannon"))
	var proj_kind: String = projectile_kind(fam)
	var source_id: String = str(last_hit.get("sourceId", ship_id))
	var mount_id: String = str(last_hit.get("mountId", ""))
	var hull_mat: String = str(wreck.get("material", hull_material(ship)))
	var radius: float = maxf(10.0, number(wreck.get("size"), 16.0))
	var mag: float = clampf(radius / 14.0, 0.80, 2.20)
	var pos: Vector2 = Vector2(number(ship.get("x"), 0.0), number(ship.get("y"), 0.0))
	var angle: float = number(ship.get("angle"), 0.0)
	var cause: String = str(wreck.get("cause", "hull"))
	var ev: Dictionary = push_event(st, {
		"kind": "sink",
		"type": "sink",
		"subtype": "sinking",
		"reason": cause,
		"family": fam,
		"projectileKind": proj_kind,
		"variant": "heavy" if radius >= 20.0 else "light",
		"sourceId": source_id,
		"sourceUid": source_id,
		"sourceTeam": str(last_hit.get("team", "player" if str(ship.get("team", "")) == "enemy" else "enemy")),
		"targetId": ship_id,
		"targetUid": str(ship.get("uid", ship_id)),
		"targetHull": str(wreck.get("type", "boat")),
		"targetTeam": str(ship.get("team", "enemy")),
		"shipId": ship_id,
		"team": str(ship.get("team", "enemy")),
		"mountId": mount_id,
		"mountIndex": -1,
		"x": pos.x,
		"y": pos.y,
		"angle": angle,
		"material": "water",
		"hullMaterial": hull_mat,
		"section": "waterline" if cause == "flooding" else "hull",
		"magnitude": mag,
		"damage": number(ship.get("maxHp"), 100.0),
		"engine": number(ship.get("engine"), 0.0),
		"splash": true,
		"breach": int(wreck.get("breaches", 0)) > 0,
		"incendiary": bool(wreck.get("onFire", false)),
		"sunk": true
	})
	add_effect(st, pos, "explosion", {
		"kind": "sink",
		"subtype": "hull_down",
		"reason": cause,
		"family": fam,
		"projectileKind": proj_kind,
		"variant": "heavy" if radius >= 20.0 else "light",
		"material": "water",
		"hullMaterial": hull_mat,
		"angle": angle,
		"magnitude": mag,
		"radius": maxf(14.0, radius * 1.35),
		"sourceId": source_id,
		"targetId": ship_id,
		"mountId": mount_id,
		"team": str(ship.get("team", "enemy")),
		"section": "waterline" if cause == "flooding" else "hull",
		"splash": true,
		"breach": int(wreck.get("breaches", 0)) > 0,
		"incendiary": bool(wreck.get("onFire", false)),
		"sunk": true,
		"seq": int(ev.get("seq", 0))
	})
	return ev
