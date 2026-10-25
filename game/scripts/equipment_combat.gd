extends RefCounted
## Narrow numeric adapter connecting canonical equipment condition to Battle and Tactical runtime.
## Never mutates ship.spec or ship.spec.weaponMounts; preserves legacy boats and fails closed on corrupt records.

const Damage = preload("res://scripts/damage.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const MountLayout = preload("res://scripts/mount_layout.gd")

const MOUNT_LOCATIONS: Array = ["mount0", "mount1", "mount2", "mount3"]

static func is_canonical_owner(ship: Dictionary) -> bool:
	return EquipmentDamage.is_canonical_owner(ship)

static func is_corrupt_owner(ship: Dictionary) -> bool:
	if not EquipmentDamage.is_canonical_owner(ship):
		return false
	var info: Dictionary = EquipmentDamage.inspect_owner(ship)
	return not bool(info.get("ok", false))

static func status_of(ship: Dictionary, status: Dictionary = {}) -> Dictionary:
	if not status.is_empty() and status.has("equipmentMode"):
		return status
	if not EquipmentDamage.is_canonical_owner(ship) and ship.get("status") is Dictionary and ship.status.has("equipmentMode"):
		return ship.status
	return Damage.get_status(ship)

static func mount_location(ship: Dictionary, mount: Dictionary, index: int = 0) -> String:
	var explicit_slot: String = str(mount.get("slotId", ""))
	if explicit_slot in MOUNT_LOCATIONS:
		return explicit_slot
	var mid: String = str(mount.get("id", ""))
	if mid in MOUNT_LOCATIONS:
		return mid
	var slot_name: String = str(mount.get("slot", "")).to_lower()
	if slot_name in ["bow", "fore"]:
		return "mount0"
	if slot_name in ["aft", "stern"]:
		return "mount1"
	if slot_name == "port":
		return "mount2"
	if slot_name == "starboard":
		return "mount3"
	if ship.get("loadout") is Dictionary and ship.loadout.get("weapons") is Array:
		var weapons: Array = ship.loadout.weapons
		var active_idx: int = 0
		for h_idx in range(mini(weapons.size(), MOUNT_LOCATIONS.size())):
			if not str(weapons[h_idx]).is_empty():
				if active_idx == index:
					return MOUNT_LOCATIONS[h_idx]
				active_idx += 1
	if index >= 0 and index < MOUNT_LOCATIONS.size():
		return MOUNT_LOCATIONS[index]
	return ""

static func mount_factor(ship: Dictionary, mount: Dictionary, index: int = 0, status: Dictionary = {}) -> float:
	var st_dict: Dictionary = status_of(ship, status)
	if not bool(st_dict.get("equipmentOk", true)) or str(st_dict.get("equipmentMode", "")) == "invalid":
		return 0.0
	if str(st_dict.get("equipmentMode", "legacy")) != "canonical":
		return 1.0
	var loc: String = mount_location(ship, mount, index)
	var wf: Dictionary = st_dict.get("weaponFactors", {}) if st_dict.get("weaponFactors") is Dictionary else {}
	if not loc.is_empty() and wf.has(loc):
		return clampf(Damage.number(wf.get(loc, 0.0), 0.0), 0.0, 1.0)
	if mount.has("mountFactor"):
		return clampf(Damage.number(mount.get("mountFactor"), 0.0), 0.0, 1.0)
	return 0.0

static func apply_mount_condition(ship: Dictionary, base_mounts: Array, status: Dictionary = {}) -> Array:
	if not EquipmentDamage.is_canonical_owner(ship) and not (ship.get("status") is Dictionary and str(ship.status.get("equipmentMode", "legacy")) != "legacy"):
		return base_mounts.duplicate(true)
	var st_dict: Dictionary = status_of(ship, status)
	var mode: String = str(st_dict.get("equipmentMode", "legacy"))
	if mode == "legacy":
		return base_mounts.duplicate(true)
	return _condition_mounts_from_status(ship, base_mounts, st_dict)

static func _condition_mounts_from_status(ship: Dictionary, base_mounts: Array, st_dict: Dictionary) -> Array:
	var result: Array = []
	for i in range(base_mounts.size()):
		var raw: Dictionary = base_mounts[i]
		var m: Dictionary = raw.duplicate(true)
		var base_dmg: float = clampf(Damage.number(raw.get("baseDamage", raw.get("damage", 10.0)), 10.0), 0.0, 100000.0)
		var base_rate: float = clampf(Damage.number(raw.get("baseFireRate", raw.get("fireRate", 1.0)), 1.0), 0.05, 60.0)
		var loc: String = mount_location(ship, m, i)
		var factor: float = mount_factor(ship, m, i, st_dict)
		m.baseDamage = base_dmg
		m.baseFireRate = base_rate
		m.slotId = loc
		m.mountIndex = i
		m.mountFactor = factor
		if factor <= 0.01 or not bool(st_dict.get("equipmentOk", true)):
			m.damage = 0.0
			m.fireRate = base_rate
		else:
			# Scale firing cadence once via fireRate; keep per-round hit damage unscaled.
			m.damage = base_dmg
			m.fireRate = clampf(base_rate * factor, 0.01, 60.0)
		result.append(m)
	return result

static func mount_cache_key(ship: Dictionary, status: Dictionary = {}) -> String:
	if not EquipmentDamage.is_canonical_owner(ship):
		return "legacy"
	var st_dict: Dictionary = status_of(ship, status)
	if not bool(st_dict.get("equipmentOk", true)):
		return "invalid"
	var wf: Dictionary = st_dict.get("weaponFactors", {}) if st_dict.get("weaponFactors") is Dictionary else {}
	return "%.4f:%.4f:%.4f:%.4f" % [
		Damage.number(wf.get("mount0", -1.0), -1.0),
		Damage.number(wf.get("mount1", -1.0), -1.0),
		Damage.number(wf.get("mount2", -1.0), -1.0),
		Damage.number(wf.get("mount3", -1.0), -1.0)
	]

static func working_mask(ship: Dictionary, status: Dictionary = {}) -> float:
	var st_dict: Dictionary = status_of(ship, status)
	if not bool(st_dict.get("equipmentOk", true)) or str(st_dict.get("equipmentMode", "")) == "invalid":
		return -1.0
	if str(st_dict.get("equipmentMode", "legacy")) != "canonical":
		return 0.0
	var mask: int = 0
	if Damage.number(st_dict.get("engineFactor"), 0.0) > 0.01:
		mask |= 1
	if Damage.number(st_dict.get("pumpFactor"), 0.0) > 0.01:
		mask |= 2
	if Damage.number(st_dict.get("armorFactor"), 0.0) > 0.01:
		mask |= 4
	var wf: Dictionary = st_dict.get("weaponFactors", {}) if st_dict.get("weaponFactors") is Dictionary else {}
	for i in range(MOUNT_LOCATIONS.size()):
		var loc: String = MOUNT_LOCATIONS[i]
		if wf.has(loc):
			mask |= (1 << (3 + i * 2))
			if Damage.number(wf.get(loc), 0.0) > 0.01:
				mask |= (1 << (4 + i * 2))
	return float(mask)

static func priority_code(status: Dictionary) -> float:
	var prio: String = str(status.get("repairPriority", "auto"))
	match prio:
		"weapons":
			return 1.0
		"engine":
			return 2.0
		"pumps":
			return 3.0
		"armor":
			return 4.0
		"hull":
			return 5.0
		_:
			return 0.0

static func module_hp_sum(ship: Dictionary) -> float:
	if not (ship.get("moduleCondition") is Dictionary and ship.moduleCondition.get("items") is Dictionary):
		return 0.0
	var total: float = 0.0
	var items: Dictionary = ship.moduleCondition.items
	for uid in items.keys():
		var item = items[uid]
		if item is Dictionary and str(item.get("location", "locker")) != "locker":
			total += Damage.number(item.get("hp"), 0.0)
	return total

static func capability_fields(ship: Dictionary, status: Dictionary = {}, mask_override: float = NAN) -> Dictionary:
	var st_dict: Dictionary = status_of(ship, status)
	var mode: String = str(st_dict.get("equipmentMode", "legacy"))
	if mode == "legacy":
		return {}
	if EquipmentDamage.is_canonical_owner(ship):
		return _canonical_capability_fields(ship, st_dict, mask_override)
	return _capability_factor_fields(ship, st_dict, mask_override)

static func _canonical_capability_fields(ship: Dictionary, st_dict: Dictionary, mask_override: float = NAN) -> Dictionary:
	var out: Dictionary = _capability_factor_fields(ship, st_dict, mask_override)
	out["moduleHpSum"] = module_hp_sum(ship)
	return out

static func _capability_factor_fields(ship: Dictionary, st_dict: Dictionary, mask_override: float = NAN) -> Dictionary:
	var wf: Dictionary = st_dict.get("weaponFactors", {}) if st_dict.get("weaponFactors") is Dictionary else {}
	var mask: float = mask_override if is_finite(mask_override) else working_mask(ship, st_dict)
	var out: Dictionary = {
		"turnFactor": Damage.number(st_dict.get("turnFactor"), 0.0),
		"pumpFactor": Damage.number(st_dict.get("pumpFactor"), 0.0),
		"armorFactor": Damage.number(st_dict.get("armorFactor"), 0.0),
		"mount0": Damage.number(wf.get("mount0"), 0.0),
		"mount1": Damage.number(wf.get("mount1"), 0.0),
		"mount2": Damage.number(wf.get("mount2"), 0.0),
		"mount3": Damage.number(wf.get("mount3"), 0.0),
		"equipMask": mask,
		"repairPriorityCode": priority_code(st_dict)
	}
	return out

static func safety_abrupt(ship: Dictionary, previous: Dictionary, status: Dictionary = {}) -> bool:
	if previous.is_empty() or not EquipmentDamage.is_canonical_owner(ship):
		return false
	var st_dict: Dictionary = status_of(ship, status)
	var cur_mask: float = working_mask(ship, st_dict)
	var cur_prio: float = priority_code(st_dict)
	var cur_mod_hp: float = module_hp_sum(ship)
	if previous.has("equipMask") and absf(cur_mask - Damage.number(previous.get("equipMask"), cur_mask)) > 0.001:
		return true
	if previous.has("repairPriorityCode") and absf(cur_prio - Damage.number(previous.get("repairPriorityCode"), cur_prio)) > 0.001:
		return true
	if previous.has("moduleHpSum") and cur_mod_hp < Damage.number(previous.get("moduleHpSum"), cur_mod_hp) - 0.0001:
		return true
	return false

static func canonical_hit_section(ship: Dictionary, point: Vector2, kind: String, eng_roll: bool) -> String:
	if kind == "torpedo":
		return "waterline"
	if eng_roll:
		return "engine"
	if not EquipmentDamage.is_canonical_owner(ship):
		return "bow"
	var base_spec: Dictionary = ship.get("baseSpec") if ship.get("baseSpec") is Dictionary and not ship.baseSpec.is_empty() else (ship.get("spec") if ship.get("spec") is Dictionary else {})
	var hull_sz: float = maxf(8.0, Damage.number(base_spec.get("size"), 16.0))
	var local_px: Vector2 = (point - Vector2(Damage.number(ship.get("x")), Damage.number(ship.get("y")))).rotated(-Damage.number(ship.get("angle")))
	var local_norm: Vector2 = local_px / hull_sz
	var installed: Dictionary = {}
	if ship.get("moduleCondition") is Dictionary and ship.moduleCondition.get("items") is Dictionary:
		for item in ship.moduleCondition.items.values():
			if item is Dictionary:
				installed[str(item.get("location", ""))] = true
	if local_norm.y < -0.25 and local_norm.x > -0.35 and installed.has("mount2"):
		return "port"
	if local_norm.y > 0.25 and local_norm.x > -0.35 and installed.has("mount3"):
		return "starboard"
	if local_norm.x < -0.25 and installed.has("mount1"):
		return "aft"
	if installed.has("mount0"):
		return "bow"
	if installed.has("mount1"):
		return "aft"
	if installed.has("mount2"):
		return "port"
	if installed.has("mount3"):
		return "starboard"
	return "bow"
