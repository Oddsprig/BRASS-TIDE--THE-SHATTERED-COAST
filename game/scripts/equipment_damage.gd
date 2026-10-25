extends RefCounted
## v0.031 numerical equipment damage and conserved repair adapter for Damage.
## Preloads only EquipmentCondition, EquipmentRecords, and MountLayout.
## No Refit, Battle, Harbor, or Campaign preloads.

const Core = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Layout = preload("res://scripts/mount_layout.gd")

const HULL_DAMAGE_SCALE: float = 0.35
const INFLOW_PER_AREA: float = 0.055
const BAIL_PER_CREW: float = 1.65
const PUMP_RATE: float = 2.3
const PATCH_AREA_PER_CREW_SEC: float = 1.8
const PATCH_SUPPLY_PER_AREA: float = 0.018
const HULL_HP_PER_CREW_SEC: float = 0.22
const HULL_SUPPLY_PER_HP: float = 0.35
const FIRE_GROWTH_PER_SEC: float = 0.08
const FIRE_SUPPRESS_PER_CREW: float = 0.65
const FIRE_HULL_LOSS_PER_SEC: float = 0.003
const FIRE_ENGINE_LOSS_PER_SEC: float = 0.000025
const MODULE_HP_PER_CREW_SEC: float = 0.04
const MODULE_SUPPLIES_PER_HP: Dictionary = {
	"pumps": 1.2,
	"engines": 1.5,
	"weapons": 1.0
}
const MOUNT_LOCATIONS: Array = ["mount0", "mount1", "mount2", "mount3"]
const TASK_ORDERS: Dictionary = {
	"auto": ["fire", "patch", "machinery", "hull"],
	"hull": ["hull", "fire", "patch", "machinery"],
	"pumps": ["machinery", "fire", "patch", "hull"],
	"engine": ["machinery", "fire", "patch", "hull"],
	"weapons": ["machinery", "fire", "patch", "hull"]
}

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func number(value, fallback: float = 0.0) -> float:
	if (value is float or value is int) and not (value is bool) and is_finite(float(value)):
		return float(value)
	return fallback

static func _sum_areas(boat: Dictionary) -> float:
	var total: float = 0.0
	var breaches = boat.get("breaches", [])
	if breaches is Array:
		for b in breaches:
			if b is Dictionary:
				total += maxf(0.0, number(b.get("area")))
	return total

static func empty_task_map() -> Dictionary:
	return {"fire": 0.0, "patch": 0.0, "machinery": 0.0, "hull": 0.0}

static func inspect_owner(boat: Dictionary) -> Dictionary:
	if not boat is Dictionary:
		return {"ok": false, "mode": "invalid", "needsInitialize": false, "error": "Boat must be a dictionary."}
	if Core._foreign(boat):
		return {"ok": false, "mode": "invalid", "needsInitialize": false, "error": "Unrecognized condition metadata was left untouched."}
	if not boat.has("moduleCondition"):
		return {"ok": true, "mode": "legacy", "needsInitialize": true}
	if not boat.moduleCondition is Dictionary:
		return {"ok": false, "mode": "invalid", "needsInitialize": false, "error": "Existing equipment condition is corrupt and was left untouched."}
	if boat.has("engine") and not Core._unit(boat.get("engine")):
		return {"ok": false, "mode": "invalid", "needsInitialize": false, "error": "The legacy engine scalar is not a finite condition."}
	var snap: Dictionary = Records.snapshot(boat)
	if not snap.ok:
		return {"ok": false, "mode": "invalid", "needsInitialize": false, "error": str(snap.get("error", "Existing equipment condition is corrupt and was left untouched."))}
	var base_spec: Dictionary = {}
	if boat.get("baseSpec") is Dictionary:
		base_spec = boat.baseSpec
	elif boat.get("spec") is Dictionary:
		base_spec = boat.spec
	if base_spec.has("pumps"):
		if not Core._number(base_spec.get("pumps")) or float(base_spec.get("pumps")) < 0.0:
			return {"ok": false, "mode": "invalid", "needsInitialize": false, "error": "Base hull pump rating must be a finite nonnegative number."}
		var expects_pumps: bool = float(base_spec.get("pumps")) > 0.0
		var has_pumps_item: bool = snap.installed.has("pumps")
		if expects_pumps and not has_pumps_item:
			return {"ok": false, "mode": "invalid", "needsInitialize": false, "error": "Integral pumps record is missing and cannot regenerate."}
		if not expects_pumps and has_pumps_item:
			return {"ok": false, "mode": "invalid", "needsInitialize": false, "error": "Pump-free hull cannot carry integral pumps."}
	if boat.has("loadout"):
		if not boat.loadout is Dictionary or not boat.loadout.get("weapons") is Array:
			return {"ok": false, "mode": "invalid", "needsInitialize": false, "error": "Boat loadout is malformed."}
		var matched: String = Core._matches_loadout(boat.moduleCondition, boat.loadout, boat.loadout.weapons.size())
		if not matched.is_empty():
			return {"ok": false, "mode": "invalid", "needsInitialize": false, "error": matched}
	return {"ok": true, "mode": "canonical", "needsInitialize": false, "snapshot": snap}

static func is_canonical_owner(boat: Dictionary) -> bool:
	return str(inspect_owner(boat).get("mode", "")) == "canonical"

static func is_corrupt_owner(boat: Dictionary) -> bool:
	return str(inspect_owner(boat).get("mode", "")) == "invalid"

static func set_repair_priority(boat: Dictionary, priority: String) -> Dictionary:
	var info: Dictionary = inspect_owner(boat)
	if not info.ok or str(info.mode) != "canonical":
		return _fail(str(info.get("error", "Equipment condition is not initialized.")))
	if not priority in Core.PRIORITIES:
		return _fail("Repair priority is unknown.")
	boat.moduleCondition.repairPriority = priority
	return {"ok": true, "repairPriority": priority}

static func has_module_repair_need(snap: Dictionary) -> bool:
	if not snap.get("ok", false) or bool(snap.get("needsInitialize", true)):
		return false
	var installed: Dictionary = snap.get("installed", {})
	for loc in installed.keys():
		var item: Dictionary = installed[loc]
		var family: String = str(item.get("family", ""))
		if family in ["pumps", "engines", "weapons"] and float(item.get("hp", 1.0)) < Core.JURY_CAP - Core.EPS:
			return true
	return false

static func _installed_uid_at(condition: Dictionary, location: String) -> String:
	if not condition.get("items") is Dictionary:
		return ""
	for uid in condition.items.keys():
		var item: Dictionary = condition.items[uid]
		if str(item.get("location", "")) == location:
			return str(uid)
	return ""

static func status_for(boat: Dictionary, able: float, area: float, inflow: float, weights: Array) -> Dictionary:
	return _status_from_info(boat, able, area, inflow, weights, inspect_owner(boat))

static func _status_from_info(boat: Dictionary, able: float, area: float, inflow: float, weights: Array, info: Dictionary) -> Dictionary:
	var mode: String = str(info.get("mode", "invalid"))
	if mode == "invalid":
		return {
			"inflow": 0.0,
			"bailing": 0.0,
			"handBailing": 0.0,
			"pump": 0.0,
			"repair": 0.0,
			"crewGuns": 0.0,
			"crewBail": 0.0,
			"crewRepair": 0.0,
			"speedFactor": 0.0,
			"turnFactor": 0.0,
			"weaponFactor": 0.0,
			"weaponFactors": {},
			"engineHp": 0.0,
			"engineFactor": 0.0,
			"pumpFactor": 0.0,
			"armorFactor": 0.0,
			"effectiveArmor": 0.0,
			"repairPriority": "auto",
			"juryCap": Core.JURY_CAP,
			"equipmentOk": false,
			"equipmentMode": "invalid",
			"needsInitialize": false,
			"equipmentError": str(info.get("error", "Existing equipment condition is corrupt and was left untouched.")),
			"availableWork": 0.0,
			"usedWork": 0.0,
			"usedSupplies": 0.0,
			"workByTask": empty_task_map(),
			"suppliesByTask": empty_task_map(),
			"repairedPatchArea": 0.0,
			"repairedHullHp": 0.0,
			"repairedModuleHp": 0.0,
			"suppressedFire": 0.0,
			"moduleChanges": [],
			"events": []
		}
	var spec: Dictionary = boat.get("spec", {}) if boat.get("spec") is Dictionary else {}
	var repair_mult: float = maxf(maxf(1.0, number(spec.get("repairFactor", 1.0), 1.0)), number(boat.get("supportRepairFactor", 1.0), 1.0))
	var sunk: bool = bool(boat.get("sunk", false))
	var water: float = maxf(0.0, number(boat.get("water")))
	var capacity: float = maxf(1.0, number(boat.get("capacity"), 200.0))
	var fire: float = clampf(number(boat.get("fire")), 0.0, 100.0)
	var supplies: float = maxf(0.0, number(boat.get("supplies")))
	var fuel: float = maxf(0.0, number(boat.get("fuel")))
	var hp: float = maxf(0.0, number(boat.get("hp")))
	var max_hp: float = maxf(1.0, number(boat.get("maxHp"), 100.0))
	var crew_min: float = maxf(1.0, number(boat.get("crewMin"), 2.0))
	var crew_opt: float = maxf(1.0, number(boat.get("crewOptimal"), 5.0))
	var policy: String = str(boat.get("policy", "balanced"))
	var active: bool = water > 0.0 or area > 0.0

	if mode == "legacy":
		var damaged_leg: bool = area > 0.0 or fire > 0.0 or (policy == "repair" and hp < max_hp)
		var bail_leg: float = able * float(weights[1]) if active else 0.0
		var repair_leg: float = able * float(weights[2]) if damaged_leg and (supplies > 0.0 or fire > 0.0) else 0.0
		var guns_leg: float = maxf(0.0, able - bail_leg - repair_leg)
		var raw_eng: float = clampf(number(boat.get("engine"), 1.0), 0.0, 1.0)
		var pump_leg: float = maxf(0.0, number(spec.get("pumps"))) * PUMP_RATE * raw_eng if fuel > 0.0 else 0.0
		var speed_leg: float = clampf(raw_eng * (1.0 - 0.78 * water / capacity) * minf(1.0, able / crew_min), 0.0, 1.0)
		if sunk:
			inflow = 0.0
			bail_leg = 0.0
			repair_leg = 0.0
			guns_leg = 0.0
			pump_leg = 0.0
			speed_leg = 0.0
		var hand_leg: float = bail_leg * BAIL_PER_CREW if active and not sunk else 0.0
		var weap_leg: float = 0.0 if sunk else clampf(guns_leg / maxf(1.0, crew_opt * 0.5), 0.0, 1.0) * (1.0 - fire * 0.004)
		return {
			"inflow": inflow,
			"bailing": hand_leg + pump_leg if active and not sunk else 0.0,
			"handBailing": hand_leg,
			"pump": pump_leg if active and not sunk else 0.0,
			"repair": repair_leg * PATCH_AREA_PER_CREW_SEC * repair_mult if area > 0.0 and supplies > 0.0 else 0.0,
			"crewGuns": guns_leg,
			"crewBail": bail_leg,
			"crewRepair": repair_leg,
			"speedFactor": speed_leg,
			"turnFactor": 0.0 if sunk else 1.0,
			"weaponFactor": weap_leg,
			"weaponFactors": {},
			"engineHp": raw_eng,
			"engineFactor": 0.0 if sunk else raw_eng,
			"pumpFactor": 0.0 if sunk else (raw_eng if number(spec.get("pumps")) > 0.0 else 0.0),
			"armorFactor": 0.0 if sunk else 1.0,
			"effectiveArmor": maxf(0.0, number(boat.get("armor"))),
			"repairPriority": "auto",
			"juryCap": Core.JURY_CAP,
			"equipmentOk": true,
			"equipmentMode": "legacy",
			"needsInitialize": true,
			"availableWork": 0.0,
			"usedWork": 0.0,
			"usedSupplies": 0.0,
			"workByTask": empty_task_map(),
			"suppliesByTask": empty_task_map(),
			"repairedPatchArea": 0.0,
			"repairedHullHp": 0.0,
			"repairedModuleHp": 0.0,
			"suppressedFire": 0.0,
			"moduleChanges": [],
			"events": []
		}

	var snap: Dictionary = info.snapshot
	var priority: String = str(snap.get("repairPriority", "auto"))
	var mod_need: bool = has_module_repair_need(snap)
	var hull_need: bool = hp < max_hp and (policy == "repair" or priority == "hull")
	var damaged_can: bool = area > 0.0 or fire > 0.0 or mod_need or hull_need
	var bail_can: float = able * float(weights[1]) if active else 0.0
	var repair_can: float = able * float(weights[2]) if damaged_can and (supplies > 0.0 or fire > 0.0) else 0.0
	var guns_can: float = maxf(0.0, able - bail_can - repair_can)
	var engine_hp: float = float(snap.get("engineHp", 0.0))
	var engine_factor: float = float(snap.get("engineFactor", 0.0))
	var pump_factor: float = float(snap.get("pumpFactor", 0.0))
	var armor_factor: float = float(snap.get("armorFactor", 0.0))
	var weapon_factors: Dictionary = snap.get("weaponFactors", {}).duplicate(true)
	var pump_can: float = maxf(0.0, number(spec.get("pumps"))) * PUMP_RATE * pump_factor if fuel > 0.0 else 0.0
	var speed_can: float = clampf(engine_factor * (1.0 - 0.78 * water / capacity) * minf(1.0, able / crew_min), 0.0, 1.0)
	var turn_can: float = speed_can
	if sunk:
		inflow = 0.0
		bail_can = 0.0
		repair_can = 0.0
		guns_can = 0.0
		pump_can = 0.0
		speed_can = 0.0
		turn_can = 0.0
		engine_factor = 0.0
		pump_factor = 0.0
		armor_factor = 0.0
		for loc in weapon_factors.keys():
			weapon_factors[loc] = 0.0
	var hand_can: float = bail_can * BAIL_PER_CREW if active and not sunk else 0.0
	var weap_can: float = 0.0 if sunk else clampf(guns_can / maxf(1.0, crew_opt * 0.5), 0.0, 1.0) * (1.0 - fire * 0.004)
	return {
		"inflow": inflow,
		"bailing": hand_can + pump_can if active and not sunk else 0.0,
		"handBailing": hand_can,
		"pump": pump_can if active and not sunk else 0.0,
		"repair": repair_can * PATCH_AREA_PER_CREW_SEC * repair_mult if area > 0.0 and supplies > 0.0 else 0.0,
		"crewGuns": guns_can,
		"crewBail": bail_can,
		"crewRepair": repair_can,
		"speedFactor": speed_can,
		"turnFactor": turn_can,
		"weaponFactor": weap_can,
		"weaponFactors": weapon_factors,
		"engineHp": engine_hp,
		"engineFactor": engine_factor,
		"pumpFactor": pump_factor,
		"armorFactor": armor_factor,
		"effectiveArmor": maxf(0.0, number(boat.get("armor"))) * armor_factor,
		"repairPriority": priority,
		"juryCap": Core.JURY_CAP,
		"equipmentOk": true,
		"equipmentMode": "canonical",
		"needsInitialize": false,
		"availableWork": 0.0,
		"usedWork": 0.0,
		"usedSupplies": 0.0,
		"workByTask": empty_task_map(),
		"suppliesByTask": empty_task_map(),
		"repairedPatchArea": 0.0,
		"repairedHullHp": 0.0,
		"repairedModuleHp": 0.0,
		"suppressedFire": 0.0,
		"moduleChanges": [],
		"events": []
	}

static func _base_spec_of(boat: Dictionary) -> Dictionary:
	if boat.get("baseSpec") is Dictionary and not boat.baseSpec.is_empty():
		return boat.baseSpec
	if boat.get("spec") is Dictionary:
		return boat.spec
	return {}

static func resolve_hit_locations(boat: Dictionary, hit: Dictionary, mach_roll: float = 1.0) -> Dictionary:
	var info: Dictionary = inspect_owner(boat)
	if not info.ok or str(info.mode) != "canonical":
		return _fail(str(info.get("error", "Equipment condition is not initialized.")))
	if not hit is Dictionary:
		return _fail("Hit descriptor must be a dictionary.")
	# Never trust attacker mountId / sourceMountId / attackerMountId as victim location.
	var snap: Dictionary = info.snapshot
	var installed: Dictionary = snap.get("installed", {})
	var base_spec: Dictionary = _base_spec_of(boat)
	var hull_sz: float = Layout.hull_size(base_spec)
	var points: Array = Layout.hardpoints(base_spec)
	var struct: Dictionary = Layout.structure(base_spec)
	var kind: String = str(hit.get("kind", "bullet")).to_lower()
	var explosive: bool = kind == "torpedo"
	var section: String = str(hit.get("section", "")).to_lower()

	var has_world_impact: bool = hit.has("impactX") or hit.has("impactY")
	var has_local_impact: bool = hit.has("localX") or hit.has("localY")
	if has_world_impact and has_local_impact:
		return _fail("Hit cannot mix world impactX/impactY and normalized localX/localY coordinates.")
	if has_world_impact and (not hit.has("impactX") or not hit.has("impactY") or not Core._number(hit.get("impactX")) or not Core._number(hit.get("impactY"))):
		return _fail("Hit world impact coordinates must be finite numbers.")
	if has_local_impact and (not hit.has("localX") or not hit.has("localY") or not Core._number(hit.get("localX")) or not Core._number(hit.get("localY"))):
		return _fail("Hit normalized local coordinates must be finite numbers.")
	if hit.has("blastRadius") and (not Core._number(hit.get("blastRadius")) or float(hit.get("blastRadius")) < 0.0):
		return _fail("Hit blastRadius must be a finite nonnegative number.")

	var locations: Array = []
	var local_norm: Vector2 = Vector2.ZERO
	var used_geometry: bool = false

	if has_world_impact or has_local_impact:
		used_geometry = true
		if has_world_impact:
			var world_pt := Vector2(float(hit.impactX), float(hit.impactY))
			var ship_pos := Vector2(number(boat.get("x")), number(boat.get("y")))
			var ship_ang: float = number(boat.get("angle"))
			var local_px: Vector2 = (world_pt - ship_pos).rotated(-ship_ang)
			local_norm = local_px / maxf(8.0, hull_sz)
		else:
			local_norm = Vector2(float(hit.localX), float(hit.localY))

		var blast_norm: float = 0.0
		if hit.has("blastRadius"):
			blast_norm = clampf(float(hit.blastRadius) / maxf(8.0, hull_sz), 0.0, 1.2)

		var best_mount: String = ""
		var best_dist: float = INF
		var splash_mounts: Array = []
		for pt in points:
			var m_id: String = str(pt.id)
			if not installed.has(m_id):
				continue
			var sock_pos := Vector2(float(pt.localX), float(pt.localY))
			var dist: float = local_norm.distance_to(sock_pos)
			var rad: float = float(pt.footprintRadius) + 0.16 + blast_norm * 0.35
			if dist <= rad:
				splash_mounts.append(m_id)
				if dist < best_dist:
					best_dist = dist
					best_mount = m_id
		if blast_norm > 0.35 and splash_mounts.size() > 1:
			for m_id in splash_mounts:
				if not locations.has(m_id):
					locations.append(m_id)
		elif not best_mount.is_empty():
			locations.append(best_mount)

		var eng: Dictionary = struct.get("engine", {})
		var eng_x: float = number(eng.get("x"), -1.0)
		var eng_y: float = number(eng.get("y"), 0.0)
		var eng_hx: float = number(eng.get("length"), 0.35) * 0.5 + 0.12 + blast_norm * 0.25
		var eng_hy: float = number(eng.get("width"), 0.45) * 0.5 + 0.12 + blast_norm * 0.25
		if installed.has("engine") and absf(local_norm.x - eng_x) <= eng_hx and absf(local_norm.y - eng_y) <= eng_hy:
			if best_mount != "mount1" or absf(local_norm.x - eng_x) < best_dist:
				locations.append("engine")

		var cab: Dictionary = struct.get("cabin", {})
		var cab_x: float = number(cab.get("x"), -0.30)
		var cab_y: float = number(cab.get("y"), 0.0)
		var cab_hx: float = number(cab.get("length"), 0.72) * 0.5 + 0.06 + blast_norm * 0.25
		var cab_hy: float = number(cab.get("width"), 0.52) * 0.5 + 0.06 + blast_norm * 0.25
		var in_pump_box: bool = absf(local_norm.x - cab_x) <= cab_hx and absf(local_norm.y - cab_y) <= cab_hy
		var torpedo_bilge: bool = explosive and local_norm.x >= -0.85 and local_norm.x <= 0.35 and absf(local_norm.y) <= 0.55
		if installed.has("pumps") and (in_pump_box or torpedo_bilge):
			locations.append("pumps")
	else:
		var mapped_mount: String = ""
		if section in MOUNT_LOCATIONS:
			mapped_mount = section
		elif section in ["bow", "fore"]:
			mapped_mount = "mount0"
		elif section in ["aft", "stern"]:
			mapped_mount = "mount1"
		elif section == "port":
			mapped_mount = "mount2"
		elif section == "starboard":
			mapped_mount = "mount3"
		elif section in ["deck", "turret", "weapons"]:
			for loc in MOUNT_LOCATIONS:
				if installed.has(loc):
					mapped_mount = loc
					break
		if not mapped_mount.is_empty() and installed.has(mapped_mount):
			locations.append(mapped_mount)

		var engine_chance: float = 0.65 if section == "engine" else (0.4 if explosive else 0.09)
		if installed.has("engine") and (section == "engine" or (section.is_empty() and mach_roll < engine_chance)):
			locations.append("engine")

		if installed.has("pumps") and (section in ["pumps", "bilge", "waterline"] or (explosive and section in ["", "waterline", "hull", "pumps", "bilge"])):
			locations.append("pumps")

	if installed.has("armor") and number(hit.get("damage")) > 0.0:
		locations.append("armor")

	return {
		"ok": true,
		"usedGeometry": used_geometry,
		"localNorm": local_norm,
		"locations": locations
	}

static func _loss_for_location(location: String, kind: String, impact: float, max_hp: float) -> float:
	var ratio: float = clampf(impact / maxf(1.0, max_hp), 0.0, 2.0)
	var explosive: bool = kind == "torpedo"
	var shell: bool = kind in ["shell", "ram"]
	var rocket: bool = kind == "rocket"
	if location == "engine":
		return minf(0.35, impact / maxf(1.0, max_hp) * 0.7)
	if location.begins_with("mount"):
		var w_mult: float = 1.25 if (explosive or shell) else (1.05 if rocket else 0.85)
		return clampf(ratio * w_mult, 0.02, 0.65)
	if location == "pumps":
		var p_mult: float = 1.15 if explosive else (0.95 if (shell or rocket) else 0.75)
		return clampf(ratio * p_mult, 0.02, 0.55)
	if location == "armor":
		var a_mult: float = 0.55 if explosive else (0.45 if shell else (0.35 if rocket else 0.22))
		return clampf(ratio * a_mult, 0.01, 0.45)
	return 0.0

static func _cause_for_location(location: String, kind: String) -> String:
	var label: String = "Torpedo hit" if kind == "torpedo" else ("Rocket hit" if kind == "rocket" else ("Shell hit" if kind in ["shell", "ram"] else "Gunfire hit"))
	return label + " on " + location

static func apply_hit_equipment(boat: Dictionary, hit: Dictionary, impact: float = -1.0, mach_roll: float = 1.0) -> Dictionary:
	var info: Dictionary = inspect_owner(boat)
	if not info.ok or str(info.mode) != "canonical":
		return _fail(str(info.get("error", "Equipment condition is not initialized.")))
	if not hit is Dictionary:
		return _fail("Hit descriptor must be a dictionary.")
	var raw: float = maxf(0.0, number(hit.get("damage")))
	if raw <= 0.0:
		return {"ok": true, "changed": false, "locations": [], "changes": [], "events": []}
	var resolved: Dictionary = resolve_hit_locations(boat, hit, mach_roll)
	if not resolved.ok:
		return resolved
	var absorbed: Dictionary = Records.absorb_legacy_damage(boat)
	if not absorbed.ok:
		return absorbed
	var snap: Dictionary = Records.snapshot(boat)
	if not snap.ok:
		return snap
	var kind: String = str(hit.get("kind", "bullet")).to_lower()
	var explosive: bool = kind == "torpedo"
	var effective_impact: float = impact
	if effective_impact < 0.0:
		var eff_armor: float = maxf(0.0, number(boat.get("armor"))) * float(snap.get("armorFactor", 1.0))
		var mitigated: float = maxf(0.0, eff_armor - maxf(0.0, number(hit.get("penetration"))))
		effective_impact = maxf(raw * 0.22, raw - mitigated * (0.3 if explosive else 0.8))
	var max_hp: float = maxf(1.0, number(boat.get("maxHp"), 100.0))
	var installed: Dictionary = snap.get("installed", {})
	var changes: Array = []
	var events: Array = []
	for loc in resolved.locations:
		var loc_str: String = str(loc)
		if not installed.has(loc_str):
			continue
		var item_before: Dictionary = installed[loc_str]
		var uid: String = str(item_before.get("itemUid", ""))
		var loss: float = _loss_for_location(loc_str, kind, effective_impact, max_hp)
		if loss <= Core.EPS:
			continue
		var dmg_res: Dictionary = Core.apply_component_damage(boat.moduleCondition, {
			"itemUid": uid,
			"loss": loss,
			"cause": _cause_for_location(loc_str, kind)
		})
		if not dmg_res.ok:
			return dmg_res
		if bool(dmg_res.get("changed", false)):
			changes.append({
				"location": loc_str,
				"itemUid": uid,
				"beforeHp": float(item_before.get("hp", 1.0)),
				"afterHp": float(dmg_res.get("hp", 0.0)),
				"status": str(dmg_res.get("status", "damaged"))
			})
			if loc_str == "engine":
				events.append("Engine damaged")
			elif loc_str == "pumps":
				events.append("Pumps damaged")
			elif loc_str == "armor":
				events.append("Armor damaged")
			elif loc_str.begins_with("mount"):
				events.append("Weapon damaged: " + loc_str)

	var published: Dictionary = Records.publish(boat)
	if not published.ok:
		return published
	return {
		"ok": true,
		"changed": not changes.is_empty(),
		"locations": resolved.locations,
		"changes": changes,
		"events": events
	}

static func tick_repair_step(boat: Dictionary, h: float, crew_repair: float, options: Dictionary = {}) -> Dictionary:
	return _repair_step_from_info(boat, h, crew_repair, options, inspect_owner(boat), Core.repair_installed, Core.apply_component_damage, Records.publish)

static func _tick_repair_numeric(boat: Dictionary, h: float, crew_repair: float, options: Dictionary = {}) -> Dictionary:
	return _repair_step_from_info(boat, h, crew_repair, options, _repair_guard_numeric(boat), Core._repair_installed_numeric, Core._apply_component_damage_numeric, Records._publish_numeric)

static func _repair_guard_numeric(boat: Dictionary) -> Dictionary:
	# Same Core._records_numeric refusal as the numeric snapshot. Fresh dict; no item or factor copies.
	var records: Dictionary = Core._records_numeric(boat.moduleCondition)
	if not records.ok:
		return {
			"ok": false,
			"mode": "invalid",
			"needsInitialize": false,
			"error": str(records.get("error", "Invalid numerical equipment state."))
		}
	return {"ok": true, "mode": "canonical", "needsInitialize": false}

static func _repair_step_from_info(boat: Dictionary, h: float, crew_repair: float, options: Dictionary, info: Dictionary, repair_parts: Callable, damage_part: Callable, publish: Callable) -> Dictionary:
	if not info.ok or str(info.mode) != "canonical":
		return _fail(str(info.get("error", "Equipment condition is not initialized.")))
	h = maxf(0.0, number(h))
	crew_repair = maxf(0.0, number(crew_repair))
	var priority: String = str(options.get("priority", boat.moduleCondition.get("repairPriority", "auto")))
	if not priority in Core.PRIORITIES:
		return _fail("Repair priority is unknown.")

	var spec: Dictionary = boat.get("spec", {}) if boat.get("spec") is Dictionary else {}
	var repair_mult: float = maxf(maxf(1.0, number(spec.get("repairFactor", 1.0), 1.0)), number(boat.get("supportRepairFactor", 1.0), 1.0))
	var available_work: float = crew_repair * h
	var work_left: float = available_work
	var supplies_left: float = maxf(0.0, number(boat.get("supplies")))
	var work_by_task: Dictionary = empty_task_map()
	var supplies_by_task: Dictionary = empty_task_map()
	var patched_area: float = 0.0
	var repaired_hull_hp: float = 0.0
	var repaired_module_hp: float = 0.0
	var suppressed_fire: float = 0.0
	var module_changes: Array = []
	var fire_before: float = clampf(number(boat.get("fire")), 0.0, 100.0)
	var task_order: Array = TASK_ORDERS.get(priority, TASK_ORDERS["auto"])

	for task in task_order:
		var task_name: String = str(task)
		if task_name == "fire":
			if fire_before > 0.0:
				var fire_grown: float = minf(100.0, fire_before + FIRE_GROWTH_PER_SEC * h)
				var max_fire_work: float = fire_grown / FIRE_SUPPRESS_PER_CREW
				var f_work: float = minf(work_left, max_fire_work)
				var suppressed: float = f_work * FIRE_SUPPRESS_PER_CREW
				boat.fire = clampf(fire_grown - suppressed, 0.0, 100.0)
				work_left = maxf(0.0, work_left - f_work)
				work_by_task["fire"] = f_work
				suppressed_fire = suppressed
		elif task_name == "patch":
			var area_now: float = _sum_areas(boat)
			if area_now > 0.001 and work_left > Core.EPS and supplies_left > Core.EPS:
				var patch_rate: float = PATCH_AREA_PER_CREW_SEC * repair_mult
				var by_work: float = work_left * patch_rate
				var by_supp: float = supplies_left / PATCH_SUPPLY_PER_AREA
				var patch: float = minf(area_now, minf(by_work, by_supp))
				if patch > Core.EPS:
					var left: float = patch
					for b in boat.breaches:
						var amount: float = minf(maxf(0.0, number(b.get("area"))), left)
						b.area = maxf(0.0, number(b.get("area")) - amount)
						left = maxf(0.0, left - amount)
					var p_work: float = patch / patch_rate
					var p_supp: float = patch * PATCH_SUPPLY_PER_AREA
					work_left = maxf(0.0, work_left - p_work)
					supplies_left = maxf(0.0, supplies_left - p_supp)
					boat.supplies = supplies_left
					work_by_task["patch"] = p_work
					supplies_by_task["patch"] = p_supp
					patched_area = patch
		elif task_name == "machinery":
			if work_left > Core.EPS and supplies_left > Core.EPS:
				var hp_per_work: float = MODULE_HP_PER_CREW_SEC * repair_mult
				var mach_priority: String = "auto" if priority == "hull" else priority
				var mod_res: Dictionary = repair_parts.call(boat.moduleCondition, {
					"work": work_left,
					"supplies": supplies_left,
					"hpPerWork": hp_per_work,
					"suppliesPerHp": MODULE_SUPPLIES_PER_HP,
					"priority": mach_priority,
					"juryCap": Core.JURY_CAP
				})
				if not mod_res.ok:
					return mod_res
				var m_work: float = maxf(0.0, float(mod_res.get("usedWork", 0.0)))
				var m_supp: float = maxf(0.0, float(mod_res.get("usedSupplies", 0.0)))
				work_left = maxf(0.0, work_left - m_work)
				supplies_left = maxf(0.0, supplies_left - m_supp)
				boat.supplies = supplies_left
				work_by_task["machinery"] = m_work
				supplies_by_task["machinery"] = m_supp
				for ch in mod_res.get("changes", []):
					repaired_module_hp += maxf(0.0, float(ch.get("afterHp", 0.0)) - float(ch.get("beforeHp", 0.0)))
					module_changes.append(ch)
		elif task_name == "hull":
			var policy: String = str(boat.get("policy", "balanced"))
			var allow_hull: bool = (priority == "hull" or policy == "repair" or _sum_areas(boat) < 0.001)
			var max_hp: float = maxf(1.0, number(boat.get("maxHp"), 100.0))
			var cur_hp: float = maxf(0.0, number(boat.get("hp")))
			if allow_hull and cur_hp < max_hp - Core.EPS and work_left > Core.EPS and supplies_left > Core.EPS:
				var hull_rate: float = HULL_HP_PER_CREW_SEC * repair_mult
				var missing_hp: float = maxf(0.0, max_hp - cur_hp)
				var by_work: float = work_left * hull_rate
				var by_supp: float = supplies_left / HULL_SUPPLY_PER_HP
				var hull_gain: float = minf(missing_hp, minf(by_work, by_supp))
				if hull_gain > Core.EPS:
					var h_work: float = hull_gain / hull_rate
					var h_supp: float = hull_gain * HULL_SUPPLY_PER_HP
					boat.hp = minf(max_hp, cur_hp + hull_gain)
					work_left = maxf(0.0, work_left - h_work)
					supplies_left = maxf(0.0, supplies_left - h_supp)
					boat.supplies = supplies_left
					work_by_task["hull"] = h_work
					supplies_by_task["hull"] = h_supp
					repaired_hull_hp = hull_gain

	if fire_before > 0.0:
		var fire_after: float = clampf(number(boat.get("fire")), 0.0, 100.0)
		var avg_fire: float = 0.5 * (fire_before + fire_after)
		boat.hp = maxf(0.0, number(boat.get("hp")) - avg_fire * FIRE_HULL_LOSS_PER_SEC * h)
		var eng_uid: String = _installed_uid_at(boat.moduleCondition, "engine")
		if not eng_uid.is_empty():
			var fire_eng_loss: float = avg_fire * FIRE_ENGINE_LOSS_PER_SEC * h
			var fire_dmg: Dictionary = damage_part.call(boat.moduleCondition, {
				"itemUid": eng_uid,
				"loss": fire_eng_loss,
				"cause": "Fire aboard"
			})
			if not fire_dmg.ok:
				return fire_dmg

	var published: Dictionary = publish.call(boat)
	if not published.ok:
		return published

	var used_work: float = float(work_by_task["fire"]) + float(work_by_task["patch"]) + float(work_by_task["machinery"]) + float(work_by_task["hull"])
	var used_supplies: float = float(supplies_by_task["patch"]) + float(supplies_by_task["machinery"]) + float(supplies_by_task["hull"])
	return {
		"ok": true,
		"availableWork": available_work,
		"usedWork": used_work,
		"usedSupplies": used_supplies,
		"workByTask": work_by_task,
		"suppliesByTask": supplies_by_task,
		"patchedArea": patched_area,
		"repairedHullHp": repaired_hull_hp,
		"repairedModuleHp": repaired_module_hp,
		"suppressedFire": suppressed_fire,
		"moduleChanges": module_changes
	}

static func _numeric_info(boat: Dictionary) -> Dictionary:
	# Only the closed private prefix may call this after strict owner validation.
	var snap: Dictionary = Records._snapshot_numeric(boat)
	if not snap.ok:
		return {"ok": false, "mode": "invalid", "needsInitialize": false, "error": str(snap.get("error", "Invalid numerical equipment state."))}
	return {"ok": true, "mode": "canonical", "needsInitialize": false, "snapshot": snap}
