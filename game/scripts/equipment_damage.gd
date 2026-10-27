extends RefCounted
## v0.031 numerical equipment damage and conserved repair adapter for Damage.
## Preloads only EquipmentCondition, EquipmentRecords, and MountLayout.
## No Refit, Battle, Harbor, or Campaign preloads.

const Core = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Layout = preload("res://scripts/mount_layout.gd")
const PrefixStepStatus = preload("res://scripts/equipment_prefix_step_status.gd")

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
	return _inspect_owner_with_records(boat, Core._records)

static func _inspect_owner_with_records(boat: Dictionary, validate: Callable) -> Dictionary:
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
	var snap: Dictionary = Records._snapshot_with_records(boat, validate)
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
	return _tick_repair_step_from_info(boat, h, crew_repair, options, inspect_owner(boat))

static func _tick_repair_step_from_info(boat: Dictionary, h: float, crew_repair: float, options: Dictionary, info: Dictionary) -> Dictionary:
	return _repair_step_from_info(boat, h, crew_repair, options, info, Core.repair_installed, Core.apply_component_damage, Records.publish)

static func _tick_repair_step_with_records(boat: Dictionary, h: float, crew_repair: float, options: Dictionary, info: Dictionary, validate: Callable) -> Dictionary:
	# Same transaction kernels, rollback and post-write full validation. Only an
	# exact, unchanged condition can reuse a successful validation within this tick.
	return _repair_step_from_info(boat, h, crew_repair, options, info, Core._repair_installed_with.bind(validate), Core._apply_component_damage_with.bind(validate), Records._publish_with.bind(validate))

# These callbacks are admitted only by Damage's encounter-owned context. They
# use the same live substeps/transactions, never the forecast/rollout adapters.
static func _battle_info051(boat: Dictionary, entry: Dictionary) -> Dictionary:
	if not bool(entry.get("valid",false)): return inspect_owner(boat)
	if int(entry.infoGeneration) != int(entry.generation):
		var snap: Dictionary = Records._snapshot_with_records(boat,Records._battle_records051.bind(entry))
		if not bool(snap.get("ok",false)):
			entry.valid = false
			return inspect_owner(boat)
		entry.info = Records._battle_freeze051({"ok":true,"mode":"canonical","needsInitialize":false,"snapshot":snap})
		entry.infoGeneration = entry.generation
	return entry.info

static func _battle_absorb051(boat: Dictionary, entry: Dictionary) -> Dictionary:
	var validate: Callable = Records._battle_records051.bind(entry)
	var records: Dictionary = validate.call(boat.moduleCondition)
	if not records.ok: return records
	if records.hasEngine and Core._unit(boat.get("engine")) and float(boat.engine) < float(records.engineHp)-0.0001:
		Records._battle_dirty051(entry)
	var result: Dictionary = Records._absorb_legacy_damage_with(boat,validate)
	if not bool(result.get("ok",false)): entry.valid = false
	return result

static func _battle_repair_none051(_condition: Dictionary, _request: Dictionary) -> Dictionary:
	return {"ok":true,"changed":false,"usedWork":0.0,"usedSupplies":0.0,"changes":[]}

static func _battle_repair051(boat: Dictionary, h: float, crew_repair: float, options: Dictionary, info: Dictionary, entry: Dictionary) -> Dictionary:
	# This exact generation's installed snapshot uses the same families/cap/EPS
	# as Core. No candidate means no transaction, dirty generation or reprojection.
	# Fire's later engine write and every real repair still use the original kernels.
	var repair_parts: Callable = _battle_repair_none051
	if not (bool(entry.get("valid",false)) and is_same(info,entry.info) and int(entry.infoGeneration) == int(entry.generation) and not has_module_repair_need(info.snapshot)):
		repair_parts = Records._battle_write051.bind(entry,Core._repair_installed_with)
	var result: Dictionary = _repair_step_from_info(boat,h,crew_repair,options,info,
		repair_parts,
		Records._battle_write051.bind(entry,Core._apply_component_damage_with),
		Records._battle_publish051.bind(entry))
	if not bool(result.get("ok",false)): entry.valid = false
	return result

static func _is_string_value(value) -> bool:
	var value_type: int = typeof(value)
	return value_type == TYPE_STRING or value_type == TYPE_STRING_NAME

static func _public_tick_context_eligible(boat: Dictionary, entry_info: Dictionary, options, frame_cache) -> bool:
	if not (boat is Dictionary) or not (entry_info is Dictionary) or not (options is Dictionary):
		return false
	if not bool(entry_info.get("ok", false)):
		return false
	var mode_val = entry_info.get("mode")
	if not _is_string_value(mode_val) or String(mode_val) != "canonical":
		return false
	if not (entry_info.get("snapshot") is Dictionary):
		return false
	var cond = boat.get("moduleCondition")
	if not (cond is Dictionary):
		return false
	var items = cond.get("items")
	if not (items is Dictionary):
		return false
	var breaches = boat.get("breaches")
	if not (breaches is Array) or not breaches.is_empty():
		return false
	if is_same(cond, boat) or is_same(items, boat) or is_same(items, cond):
		return false
	if is_same(options, boat) or is_same(options, cond) or is_same(options, items):
		return false
	if is_same(frame_cache, boat) or is_same(frame_cache, cond) or is_same(frame_cache, items):
		return false
	var spec = boat.get("spec")
	if is_same(spec, boat) or is_same(spec, cond) or is_same(spec, items):
		return false
	var base_spec = boat.get("baseSpec")
	if is_same(base_spec, boat) or is_same(base_spec, cond) or is_same(base_spec, items):
		return false
	var loadout = boat.get("loadout")
	if is_same(loadout, boat) or is_same(loadout, cond) or is_same(loadout, items):
		return false
	for key in boat.keys():
		if not _is_string_value(key):
			return false
	if spec is Dictionary:
		var mounts = spec.get("weaponMounts")
		if mounts is Array:
			for mount in mounts:
				if mount is Dictionary:
					for mount_key in mount.keys():
						if not _is_string_value(mount_key):
							return false
	for item_uid in items.keys():
		if not _is_string_value(item_uid):
			return false
		var item = items[item_uid]
		if not (item is Dictionary):
			return false
		if not _is_string_value(item.get("family")) or not _is_string_value(item.get("location")) or not _is_string_value(item.get("status")):
			return false
	if boat.has("policy") and not _is_string_value(boat.get("policy")):
		return false
	if options.has("priority"):
		var opt_prio = options.get("priority")
		if not _is_string_value(opt_prio) or not (String(opt_prio) in Core.PRIORITIES):
			return false
	var cond_prio = cond.get("repairPriority")
	if not _is_string_value(cond_prio) or not (String(cond_prio) in Core.PRIORITIES):
		return false
	if boat.has("engine") and not Core._unit(boat.get("engine")):
		return false
	return true

static func _make_public_tick_context(boat: Dictionary, entry_info: Dictionary, options = {}, frame_cache = null) -> Dictionary:
	var eligible: bool = _public_tick_context_eligible(boat, entry_info, options, frame_cache)
	return {
		"owner": boat if eligible else null,
		"condition": boat.moduleCondition if eligible else null,
		"items": boat.moduleCondition.items if eligible else null,
		"eligible": eligible,
		"info_valid": eligible,
		"info": entry_info if eligible else {},
		"publish_valid": false,
		"publish_projection": {}
	}

static func _invalidate_public_tick_context(tick_ctx: Dictionary, disable_eligibility: bool = false) -> void:
	if not (tick_ctx is Dictionary):
		return
	if disable_eligibility:
		tick_ctx["eligible"] = false
		tick_ctx["owner"] = null
		tick_ctx["condition"] = null
		tick_ctx["items"] = null
	tick_ctx["info_valid"] = false
	tick_ctx["info"] = {}
	tick_ctx["publish_valid"] = false
	tick_ctx["publish_projection"] = {}

static func _tick_context_runtime_valid(boat: Dictionary, tick_ctx: Dictionary) -> bool:
	if not (tick_ctx is Dictionary) or not bool(tick_ctx.get("eligible", false)):
		return false
	if not (boat is Dictionary) or not is_same(tick_ctx.get("owner"), boat):
		return false
	var cond = boat.get("moduleCondition")
	if not (cond is Dictionary) or not is_same(tick_ctx.get("condition"), cond):
		return false
	var items = cond.get("items")
	if not (items is Dictionary) or not is_same(tick_ctx.get("items"), items):
		return false
	var breaches = boat.get("breaches")
	if not (breaches is Array) or not breaches.is_empty():
		return false
	if boat.has("engine") and not Core._unit(boat.get("engine")):
		return false
	if boat.has("policy") and not _is_string_value(boat.get("policy")):
		return false
	var cond_prio = cond.get("repairPriority")
	if not _is_string_value(cond_prio) or not (String(cond_prio) in Core.PRIORITIES):
		return false
	return true

static func _tick_status_public_local(boat: Dictionary, tick_ctx: Dictionary) -> Dictionary:
	if _tick_context_runtime_valid(boat, tick_ctx) and bool(tick_ctx.get("info_valid", false)):
		var cached_info = tick_ctx.get("info")
		if cached_info is Dictionary and bool(cached_info.get("ok", false)) and _is_string_value(cached_info.get("mode")) and String(cached_info.get("mode")) == "canonical":
			return cached_info
	var validate = tick_ctx.get("records_validate")
	var fresh: Dictionary = _inspect_owner_with_records(boat, validate) if validate is Callable else inspect_owner(boat)
	if _tick_context_runtime_valid(boat, tick_ctx) and bool(fresh.get("ok", false)) and _is_string_value(fresh.get("mode")) and String(fresh.get("mode")) == "canonical" and (fresh.get("snapshot") is Dictionary):
		tick_ctx["condition"] = boat.moduleCondition
		tick_ctx["items"] = boat.moduleCondition.items
		tick_ctx["info"] = fresh
		tick_ctx["info_valid"] = true
	else:
		_invalidate_public_tick_context(tick_ctx, true)
	return fresh

static func _tick_absorb_public_local(boat: Dictionary, tick_ctx: Dictionary) -> Dictionary:
	var validate = tick_ctx.get("records_validate")
	var absorbed: Dictionary = Records._absorb_legacy_damage_with(boat, validate) if validate is Callable else Records.absorb_legacy_damage(boat)
	if not bool(absorbed.get("ok", false)):
		_invalidate_public_tick_context(tick_ctx, true)
	elif bool(absorbed.get("changed", false)):
		_invalidate_public_tick_context(tick_ctx, false)
	return absorbed

static func _tick_publish_public_local(boat: Dictionary, tick_ctx: Dictionary) -> Dictionary:
	if _tick_context_runtime_valid(boat, tick_ctx) and bool(tick_ctx.get("publish_valid", false)):
		var proj = tick_ctx.get("publish_projection")
		if proj is Dictionary and proj.has("hasEngine") and proj.has("engineHp") and (proj.get("refitLocker") is Dictionary):
			return Records._publish_projection(boat, proj)
	var validate = tick_ctx.get("records_validate")
	var published: Dictionary = Records._publish_with(boat, validate) if validate is Callable else Records.publish(boat)
	if bool(published.get("ok", false)) and _tick_context_runtime_valid(boat, tick_ctx) and (published.get("refitLocker") is Dictionary):
		tick_ctx["condition"] = boat.moduleCondition
		tick_ctx["items"] = boat.moduleCondition.items
		tick_ctx["publish_projection"] = {
			"hasEngine": bool(published.get("hasEngine", false)),
			"engineHp": float(published.get("engineHp", 0.0)),
			"refitLocker": published.get("refitLocker", {}).duplicate(true)
		}
		tick_ctx["publish_valid"] = true
	else:
		_invalidate_public_tick_context(tick_ctx, true)
	return published

static func _tick_repair_public_local_from_info(boat: Dictionary, h: float, crew_repair: float, options: Dictionary, info: Dictionary, tick_ctx: Dictionary) -> Dictionary:
	if _tick_context_runtime_valid(boat, tick_ctx) and bool(tick_ctx.get("info_valid", false)) and (info is Dictionary) and is_same(info, tick_ctx.get("info")) and (options is Dictionary):
		var prio_ok: bool = true
		var priority: String = ""
		if options.has("priority"):
			var raw_prio = options.get("priority")
			if _is_string_value(raw_prio):
				priority = String(raw_prio)
			else:
				prio_ok = false
		else:
			var cond_prio = boat.moduleCondition.get("repairPriority", "auto")
			if _is_string_value(cond_prio):
				priority = String(cond_prio)
			else:
				prio_ok = false
		if prio_ok and (priority in Core.PRIORITIES):
			var h_idle: float = maxf(0.0, number(h))
			var crew_idle: float = maxf(0.0, number(crew_repair))
			var available_work: float = crew_idle * h_idle
			var fire_before: float = clampf(number(boat.get("fire")), 0.0, 100.0)
			if fire_before <= 0.0 and available_work <= Core.EPS:
				return _repair_step_from_info(
					boat,
					h,
					crew_repair,
					options,
					info,
					Core.repair_installed,
					Core.apply_component_damage,
					_tick_publish_public_local.bind(tick_ctx)
				)
	_invalidate_public_tick_context(tick_ctx, false)
	var validate = tick_ctx.get("records_validate")
	if validate is Callable:
		return _tick_repair_step_with_records(boat, h, crew_repair, options, info, validate)
	return _tick_repair_step_from_info(boat, h, crew_repair, options, info)

static func _tick_repair_numeric(boat: Dictionary, h: float, crew_repair: float, options: Dictionary = {}) -> Dictionary:
	return _tick_repair_numeric_from_info(boat, h, crew_repair, options, _repair_guard_numeric(boat))

static func _tick_repair_numeric_from_info(boat: Dictionary, h: float, crew_repair: float, options: Dictionary, info: Dictionary) -> Dictionary:
	return _repair_step_from_info(boat, h, crew_repair, options, info, Core._repair_installed_numeric, Core._apply_component_damage_numeric, Records._publish_numeric)

static func _tick_repair_rollout_from_info(boat: Dictionary, h: float, crew_repair: float, options: Dictionary, info: Dictionary) -> Dictionary:
	# Only Damage._tick_canonical_numeric calls this, after that call's pre-loop _publish_numeric.
	# info is this step's _numeric_rollout_info result, taken before the water write. Same quantum: no second item walk.
	# The pre-loop refitLocker object stays. A replacement locker from publish is not an external identity.
	# Live tick_ship boats do not use this adapter. A failed gate tail-calls the original numeric repair.
	if not (info is Dictionary) or not bool(info.get("ok", false)) or str(info.get("mode", "")) != "canonical":
		return _tick_repair_numeric_from_info(boat, h, crew_repair, options, info)
	if not (boat is Dictionary) or not (boat.get("moduleCondition") is Dictionary):
		return _tick_repair_numeric_from_info(boat, h, crew_repair, options, info)
	var h_idle: float = maxf(0.0, number(h))
	var crew_idle: float = maxf(0.0, number(crew_repair))
	var available_work: float = crew_idle * h_idle
	var priority: String = str(options.get("priority", boat.moduleCondition.get("repairPriority", "auto")))
	var fire_before: float = clampf(number(boat.get("fire")), 0.0, 100.0)
	if not priority in Core.PRIORITIES or fire_before > 0.0 or not (available_work <= Core.EPS):
		return _tick_repair_numeric_from_info(boat, h, crew_repair, options, info)
	var work_by_task: Dictionary = empty_task_map()
	var supplies_by_task: Dictionary = empty_task_map()
	var used_work: float = float(work_by_task["fire"]) + float(work_by_task["patch"]) + float(work_by_task["machinery"]) + float(work_by_task["hull"])
	var used_supplies: float = float(supplies_by_task["patch"]) + float(supplies_by_task["machinery"]) + float(supplies_by_task["hull"])
	return {
		"ok": true,
		"availableWork": available_work,
		"usedWork": used_work,
		"usedSupplies": used_supplies,
		"workByTask": work_by_task,
		"suppliesByTask": supplies_by_task,
		"patchedArea": 0.0,
		"repairedHullHp": 0.0,
		"repairedModuleHp": 0.0,
		"suppressedFire": 0.0,
		"moduleChanges": []
	}

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
	if not (info is Dictionary) or not bool(info.get("ok", false)) or str(info.get("mode", "")) != "canonical":
		return _fail(str(info.get("error", "Equipment condition is not initialized.")) if info is Dictionary else "Equipment condition is not initialized.")
	if not (boat is Dictionary) or not (boat.get("moduleCondition") is Dictionary):
		return _fail("Equipment condition is not initialized.")
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

static func _numeric_rollout_info(boat: Dictionary) -> Dictionary:
	# Same four-field wrapper as _numeric_info. Snapshot is the private status readout.
	var snap: Dictionary = Records._rollout_status_fields(boat)
	if not snap.ok:
		return {"ok": false, "mode": "invalid", "needsInitialize": false, "error": str(snap.get("error", "Invalid numerical equipment state."))}
	return {"ok": true, "mode": "canonical", "needsInitialize": false, "snapshot": snap}

# Prefix-local callbacks for one EquipmentRollout.prefix canonical arm.
# Damage._tick_canonical_with stays the caller of these callables and is not edited.
# The loop, scalar math, and accumulators stay in that body. Nothing here copies them.
# ctx is that prefix's local dictionary only: owner, valid, info, engine_hp, absorb_receipt.
# Callables are not stored on ctx. Another boat pointer does not read or write ctx.
# Reuse reads this call's breaches array. Missing or nonempty uses the original numeric
# functions and does not refuse a boat the original functions still accept.
# A kept absorb dictionary is a real Records._absorb_legacy_numeric return with ok and
# changed == false. changed true is not kept and is not treated as a no-write.
# _prefix_ctx_publish_ok_only assigns nothing. published.ok is the only field the repair
# body reads. That dictionary is not Records._publish_numeric's return.
# Eligibility also requires an absent policy, or a present TYPE_STRING or TYPE_STRING_NAME policy.
# That policy read is typeof only. It does not call str, because Object._to_string can write after inspection.

static func _prefix_ctx_bound(boat: Dictionary, ctx: Dictionary) -> bool:
	return boat is Dictionary and ctx is Dictionary and is_same(boat, ctx.get("owner"))

static func _prefix_ctx_clear_step_status(ctx: Dictionary) -> void:
	PrefixStepStatus.clear(ctx)

static func _prefix_ctx_clear(ctx: Dictionary) -> void:
	ctx["valid"] = false
	ctx.erase("info")
	ctx.erase("engine_hp")
	PrefixStepStatus.clear(ctx)

static func _prefix_tick_scope_begin(ctx: Dictionary) -> void:
	PrefixStepStatus.tick_scope_begin(ctx)

static func _prefix_tick_scope_end(ctx: Dictionary) -> void:
	PrefixStepStatus.tick_scope_end(ctx)

static func _prefix_drop_cond_proof(ctx: Dictionary) -> void:
	if ctx is Dictionary:
		ctx.erase("cond_eq_proof")

static func _prefix_drop_cond_proof_if_same_condition(boat: Dictionary, ctx: Dictionary) -> void:
	if not (ctx is Dictionary) or not (boat is Dictionary):
		return
	if is_same(boat.get("moduleCondition"), ctx.get("step_status_cond")):
		ctx.erase("cond_eq_proof")

static func _prefix_ctx_drop_receipt(ctx: Dictionary) -> void:
	ctx.erase("absorb_receipt")

static func _prefix_ctx_breaches_empty(boat: Dictionary) -> bool:
	var breaches = boat.get("breaches")
	return breaches is Array and breaches.is_empty()

static func _prefix_ctx_receipt_is_nowrite(receipt) -> bool:
	return receipt is Dictionary and bool(receipt.get("ok", false)) and receipt.get("changed") == false and Core._unit(receipt.get("engineHp"))

static func _prefix_ctx_info_acceptable(boat: Dictionary, info: Dictionary) -> bool:
	# Damage._status_for_info calls _status_from_info, which assigns str(boat.get("policy", "balanced")).
	# An Object policy makes that str() run Object._to_string, which can mutate condition after a cached inspection.
	# A present policy is eligible only for TYPE_STRING or TYPE_STRING_NAME. This check does not call str.
	# A missing policy stays eligible and uses the default balanced weights. Any other present type returns false,
	# so arm leaves the context unarmed and info, absorb, publish, and repair tail-call the original functions.
	# That miss is not a refusal. No priority typeof gate is added. repairPriority stays core metadata.
	# _prefix_ctx_repair_idle still stringifies options.priority and the stored repairPriority, then requires
	# Core.PRIORITIES membership. A miss clears and tail-calls. This patch does not change that gate.
	if boat.has("policy"):
		var policy_type: int = typeof(boat.get("policy"))
		if policy_type != TYPE_STRING and policy_type != TYPE_STRING_NAME:
			return false
	if not (info is Dictionary) or not bool(info.get("ok", false)) or str(info.get("mode", "")) != "canonical":
		return false
	if bool(info.get("needsInitialize", true)):
		return false
	if not _prefix_ctx_breaches_empty(boat):
		return false
	var snap = info.get("snapshot")
	if not (snap is Dictionary) or not bool(snap.get("ok", false)):
		return false
	var installed = snap.get("installed")
	if not (installed is Dictionary) or not (installed.get("engine") is Dictionary):
		return false
	var engine_row: Dictionary = installed.get("engine")
	if not Core._unit(boat.get("engine")) or not Core._unit(snap.get("engineHp")) or not Core._unit(engine_row.get("hp")):
		return false
	if float(engine_row.get("hp")) != float(snap.get("engineHp")):
		return false
	return true

static func _prefix_ctx_arm(boat: Dictionary, ctx: Dictionary, info: Dictionary) -> void:
	if not _prefix_ctx_bound(boat, ctx):
		return
	if not _prefix_ctx_info_acceptable(boat, info):
		_prefix_ctx_clear(ctx)
		_prefix_ctx_drop_receipt(ctx)
		return
	var snap: Dictionary = info.get("snapshot")
	var record_hp: float = float(snap.get("engineHp"))
	if float(boat.engine) != record_hp:
		_prefix_ctx_clear(ctx)
		return
	if not PrefixStepStatus.arm_info(boat, info, ctx):
		_prefix_ctx_clear(ctx)
		_prefix_ctx_drop_receipt(ctx)
		return
	ctx["info"] = info
	ctx["engine_hp"] = record_hp
	ctx["valid"] = true
	var receipt = ctx.get("absorb_receipt")
	if not _prefix_ctx_receipt_is_nowrite(receipt) or float(receipt.get("engineHp")) != record_hp:
		_prefix_ctx_drop_receipt(ctx)

static func _prefix_ctx_reuse_info(boat: Dictionary, ctx: Dictionary) -> bool:
	if not bool(ctx.get("valid", false)):
		return false
	var info = ctx.get("info")
	if not (info is Dictionary) or not _prefix_ctx_info_acceptable(boat, info):
		return false
	if not ctx.has("engine_hp") or float(boat.engine) != float(ctx.get("engine_hp")):
		return false
	var snap: Dictionary = info.get("snapshot")
	if float(snap.get("engineHp")) != float(ctx.get("engine_hp")):
		return false
	return PrefixStepStatus.cond_valid(boat, ctx)

static func _prefix_ctx_publish_ok_only(_boat: Dictionary) -> Dictionary:
	return {"ok": true}

static func _prefix_ctx_info(boat: Dictionary, ctx: Dictionary) -> Dictionary:
	if not _prefix_ctx_bound(boat, ctx):
		return _numeric_rollout_info(boat)
	if _prefix_ctx_reuse_info(boat, ctx):
		var current: Dictionary = ctx.get("info")
		return current
	_prefix_ctx_clear(ctx)
	var info: Dictionary = _numeric_rollout_info(boat)
	_prefix_ctx_arm(boat, ctx, info)
	return info

static func _prefix_ctx_absorb(boat: Dictionary, ctx: Dictionary) -> Dictionary:
	if not _prefix_ctx_bound(boat, ctx):
		_prefix_drop_cond_proof_if_same_condition(boat, ctx)
		return Records._absorb_legacy_numeric(boat)
	var receipt = ctx.get("absorb_receipt")
	if _prefix_ctx_reuse_info(boat, ctx) and _prefix_ctx_receipt_is_nowrite(receipt) and float(receipt.get("engineHp")) == float(ctx.get("engine_hp")):
		var kept: Dictionary = receipt
		return kept
	_prefix_ctx_clear(ctx)
	_prefix_ctx_drop_receipt(ctx)
	_prefix_drop_cond_proof(ctx)
	var fresh: Dictionary = Records._absorb_legacy_numeric(boat)
	if _prefix_ctx_receipt_is_nowrite(fresh):
		ctx["absorb_receipt"] = fresh
	return fresh

static func _prefix_ctx_publish(boat: Dictionary, ctx: Dictionary) -> Dictionary:
	if not _prefix_ctx_bound(boat, ctx):
		_prefix_drop_cond_proof_if_same_condition(boat, ctx)
		return Records._publish_numeric(boat)
	if _prefix_ctx_reuse_info(boat, ctx):
		return _prefix_ctx_publish_ok_only(boat)
	_prefix_ctx_clear(ctx)
	var published: Dictionary = Records._publish_numeric(boat)
	if not bool(published.get("ok", false)):
		_prefix_ctx_drop_receipt(ctx)
	return published

static func _prefix_ctx_repair_idle(boat: Dictionary, h: float, crew_repair: float, options: Dictionary, info: Dictionary, ctx: Dictionary) -> bool:
	if not _prefix_ctx_reuse_info(boat, ctx) or not is_same(info, ctx.get("info")):
		return false
	if not (options is Dictionary) or not (boat.get("moduleCondition") is Dictionary):
		return false
	var fire_before: float = clampf(number(boat.get("fire")), 0.0, 100.0)
	if fire_before > 0.0:
		return false
	if options.has("priority") and not _is_string_value(options.get("priority")):
		return false
	var priority: String = str(options.get("priority", boat.moduleCondition.get("repairPriority", "auto")))
	if not priority in Core.PRIORITIES:
		return false
	var current: Dictionary = ctx.get("info")
	var snap: Dictionary = current.get("snapshot")
	if str(boat.moduleCondition.get("repairPriority", "")) != str(snap.get("repairPriority", "")):
		return false
	var available_work: float = maxf(0.0, number(crew_repair)) * maxf(0.0, number(h))
	return available_work <= Core.EPS

static func _prefix_ctx_repair(boat: Dictionary, h: float, crew_repair: float, options: Dictionary, info: Dictionary, ctx: Dictionary) -> Dictionary:
	if not _prefix_ctx_bound(boat, ctx):
		_prefix_drop_cond_proof_if_same_condition(boat, ctx)
		return _tick_repair_rollout_from_info(boat, h, crew_repair, options, info)
	if _prefix_ctx_repair_idle(boat, h, crew_repair, options, info, ctx):
		# Idle gate: fire is 0 and available work <= Core.EPS. _repair_step_from_info
		# then cannot reach repair_parts or damage_part, and publish is the no-write stub.
		return _repair_step_from_info(boat, h, crew_repair, options, info, Core._repair_installed_numeric, Core._apply_component_damage_numeric, _prefix_ctx_publish_ok_only)
	_prefix_ctx_clear(ctx)
	_prefix_ctx_drop_receipt(ctx)
	_prefix_drop_cond_proof(ctx)
	return _tick_repair_rollout_from_info(boat, h, crew_repair, options, info)

static func _prefix_ctx_step_status_valid(boat: Dictionary, info: Dictionary, ctx: Dictionary) -> bool:
	return _prefix_ctx_reuse_info(boat, ctx) and PrefixStepStatus.valid(boat, info, ctx)

static func _prefix_ctx_arm_step_status(boat: Dictionary, info: Dictionary, status: Dictionary, ctx: Dictionary) -> void:
	if not _prefix_ctx_bound(boat, ctx) or not _prefix_ctx_reuse_info(boat, ctx):
		PrefixStepStatus.clear_status(ctx)
		return
	PrefixStepStatus.arm(boat, info, status, ctx)

static func _prefix_ctx_step_status(boat: Dictionary, info: Dictionary, ctx: Dictionary, status_for_info_fn: Callable) -> Dictionary:
	if not _prefix_ctx_bound(boat, ctx):
		return status_for_info_fn.call(boat, info)
	if _prefix_ctx_reuse_info(boat, ctx) and (info is Dictionary) and is_same(info, ctx.get("info")):
		if PrefixStepStatus.valid(boat, info, ctx):
			var cached: Dictionary = ctx.get("step_status")
			return cached
		PrefixStepStatus.clear_status(ctx)
		var fresh: Dictionary = status_for_info_fn.call(boat, info)
		PrefixStepStatus.arm(boat, info, fresh, ctx)
		return fresh
	var use_info: Dictionary = info
	if is_same(info, ctx.get("info")):
		_prefix_ctx_clear(ctx)
		use_info = _numeric_rollout_info(boat)
		_prefix_ctx_arm(boat, ctx, use_info)
	else:
		_prefix_ctx_clear(ctx)
	var fallback: Dictionary = status_for_info_fn.call(boat, use_info)
	if bool(ctx.get("valid", false)) and is_same(use_info, ctx.get("info")):
		PrefixStepStatus.arm(boat, use_info, fallback, ctx)
	return fallback
