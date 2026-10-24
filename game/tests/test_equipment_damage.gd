extends SceneTree
## Bounded unrun native fixture for the v0.031 equipment damage & repair adapter.
## Seeds canonical equipment via EquipmentRecords using real world.json hulls and
## Refit.catalog(), then exercises Damage.apply_hit, Damage.get_status, and
## Damage.tick_ship. Sol owns the engine lease and executes native runs.

const Damage = preload("res://scripts/damage.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Core = preload("res://scripts/equipment_condition.gd")
const Refit = preload("res://scripts/refit.gd")
const Layout = preload("res://scripts/mount_layout.gd")

var world: Dictionary = {}
var catalog: Dictionary = {}
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL equipment_damage: " + message)

func _approx(a: float, b: float, tol: float = 0.0001) -> bool:
	return absf(a - b) <= tol

func _context(base: Dictionary, loadout: Dictionary, identity: String, known_uids: Array = []) -> Dictionary:
	return {
		"base": base,
		"loadout": loadout,
		"catalog": catalog,
		"identity": identity,
		"knownUids": known_uids
	}

func _canonical_boat(hull_index: int, identity: String, overrides: Dictionary = {}, custom_loadout: Dictionary = {}) -> Dictionary:
	var base: Dictionary = world.HULLS[hull_index].duplicate(true)
	var boat: Dictionary = Damage.create_ship(base, overrides)
	if not custom_loadout.is_empty():
		var norm: Dictionary = Refit.normalize(base, custom_loadout)
		check(norm.ok, "custom loadout normalizes for " + identity)
		boat.loadout = norm.loadout
	Refit.ensure(boat, base)
	boat.uid = identity
	var init_res: Dictionary = Records.initialize(boat, _context(base, boat.loadout, identity))
	check(init_res.ok, "Records.initialize succeeded for " + identity + " (" + str(init_res.get("error", "ok")) + ")")
	return boat

func _item_at(condition: Dictionary, location: String) -> Dictionary:
	for uid in condition.items.keys():
		var item: Dictionary = condition.items[uid]
		if str(item.location) == location:
			return item
	return {}

func test_hit_geometry_and_section_fallback_without_locker_damage() -> void:
	var base: Dictionary = world.HULLS[23].duplicate(true)
	var fit: Dictionary = {
		"weapons": ["stock_primary", "rapid_gun", "light_cannon", "fire_rocket"],
		"engine": "stock_engine",
		"armor": "stock_armor"
	}
	var boat: Dictionary = _canonical_boat(23, "fleet-dreadnought-hit-geo", {
		"x": 420.0,
		"y": -180.0,
		"angle": 0.65,
		"refitLocker": {"rapid_gun": 2, "stock_engine": 1, "scout_plating": 1}
	}, fit)
	var rng := RandomNumberGenerator.new()
	rng.seed = 901

	var hull_sz: float = Layout.hull_size(base)
	var points: Array = Layout.hardpoints(base)
	var struct: Dictionary = Layout.structure(base)
	var ship_pos := Vector2(float(boat.x), float(boat.y))
	var ship_ang: float = float(boat.angle)

	# 1. World impact at mount0 (bow socket), with decoy attacker mountId="mount3".
	var pt0: Dictionary = points[0]
	var world_m0: Vector2 = ship_pos + Vector2(float(pt0.x), float(pt0.y)).rotated(ship_ang)
	Damage.apply_hit(boat, {
		"damage": 140.0,
		"kind": "shell",
		"penetration": 20.0,
		"impactX": world_m0.x,
		"impactY": world_m0.y,
		"mountId": "mount3",
		"sourceMountId": "mount2"
	}, rng)
	var m0_hp: float = float(_item_at(boat.moduleCondition, "mount0").hp)
	var m1_hp: float = float(_item_at(boat.moduleCondition, "mount1").hp)
	var m2_hp: float = float(_item_at(boat.moduleCondition, "mount2").hp)
	var m3_hp: float = float(_item_at(boat.moduleCondition, "mount3").hp)
	var eng_hp_1: float = float(_item_at(boat.moduleCondition, "engine").hp)
	var pmp_hp_1: float = float(_item_at(boat.moduleCondition, "pumps").hp)
	var arm_hp_1: float = float(_item_at(boat.moduleCondition, "armor").hp)
	check(_approx(float(boat.hp), 651.0), "mount0 shell hit reduces hull HP from 700.0 to 651.0 (got=%.4f)" % float(boat.hp))
	check(_approx(m0_hp, 0.75), "world impact at mount0 socket reduces mount0 hp by 0.25 to 0.75 (got=%.4f)" % m0_hp)
	check(_approx(m1_hp, 1.0) and _approx(m2_hp, 1.0) and _approx(m3_hp, 1.0), "other mounts ignore attacker mountId decoy and remain 1.0 (got=%.2f,%.2f,%.2f)" % [m1_hp, m2_hp, m3_hp])
	check(_approx(eng_hp_1, 1.0) and _approx(pmp_hp_1, 1.0), "bow socket impact does not damage engine or pumps (got eng=%.4f, pumps=%.4f)" % [eng_hp_1, pmp_hp_1])
	check(_approx(arm_hp_1, 0.91), "140-damage shell on 700-HP hull reduces armor hp by 0.09 to 0.91 (got=%.4f)" % arm_hp_1)

	# 2. World impact at aft-midships engine zone.
	var eng_local := Vector2(float(struct.engine.x) * hull_sz, float(struct.engine.y) * hull_sz)
	var world_eng: Vector2 = ship_pos + eng_local.rotated(ship_ang)
	Damage.apply_hit(boat, {
		"damage": 210.0,
		"kind": "shell",
		"penetration": 20.0,
		"impactX": world_eng.x,
		"impactY": world_eng.y
	}, rng)
	var eng_hp_2: float = float(_item_at(boat.moduleCondition, "engine").hp)
	check(_approx(eng_hp_2, 0.79) and _approx(float(boat.engine), 0.79), "engine-room impact reduces canonical engine hp and boat.engine once by 0.21 to 0.79 without double debit (got item=%.4f, scalar=%.4f)" % [eng_hp_2, float(boat.engine)])
	check(_approx(float(_item_at(boat.moduleCondition, "mount0").hp), 0.75) and _approx(float(_item_at(boat.moduleCondition, "mount1").hp), 1.0), "engine-room impact leaves mount0 at 0.75 and mount1 at 1.0")

	# 3. World impact at amidships cabin/bilge pump zone.
	var pump_local := Vector2(float(struct.cabin.x) * hull_sz, float(struct.cabin.y) * hull_sz)
	var world_pump: Vector2 = ship_pos + pump_local.rotated(ship_ang)
	Damage.apply_hit(boat, {
		"damage": 280.0,
		"kind": "torpedo",
		"penetration": 20.0,
		"impactX": world_pump.x,
		"impactY": world_pump.y
	}, rng)
	var pmp_hp_3: float = float(_item_at(boat.moduleCondition, "pumps").hp)
	check(_approx(pmp_hp_3, 0.54), "bilge torpedo impact reduces integral pumps hp by 0.46 to 0.54 (got=%.4f)" % pmp_hp_3)

	# 4. Standalone explicit section fallback (no impactX/impactY) for aft mount1.
	Damage.apply_hit(boat, {
		"damage": 140.0,
		"kind": "shell",
		"penetration": 20.0,
		"section": "aft"
	}, rng)
	var m1_hp_4: float = float(_item_at(boat.moduleCondition, "mount1").hp)
	check(_approx(m1_hp_4, 0.75), "standalone section='aft' fallback reduces mount1 hp by 0.25 to 0.75 (got=%.4f)" % m1_hp_4)

	# 5. Locker spares are untouched by combat hits.
	var locker_items: Array = Core.list_locker(boat.moduleCondition).items
	check(locker_items.size() == 4, "all 4 locker spares remain in locker (got=%d)" % locker_items.size())
	for item in locker_items:
		check(_approx(float(item.hp), 1.0) and str(item.status) == "ok", "locker spare " + str(item.itemUid) + " stays undamaged at 1.0")

	# 6. Normalized localX/localY vs world impactX/impactY exact equivalence.
	var boat_world_eq: Dictionary = _canonical_boat(23, "fleet-dreadnought-world-eq", {
		"x": 420.0,
		"y": -180.0,
		"angle": 0.65
	}, fit)
	var boat_local_eq: Dictionary = _canonical_boat(23, "fleet-dreadnought-local-eq", {
		"x": 420.0,
		"y": -180.0,
		"angle": 0.65
	}, fit)
	var hit_world_eq: Dictionary = {
		"damage": 140.0,
		"kind": "shell",
		"penetration": 20.0,
		"impactX": world_m0.x,
		"impactY": world_m0.y
	}
	var hit_local_eq: Dictionary = {
		"damage": 140.0,
		"kind": "shell",
		"penetration": 20.0,
		"localX": float(pt0.localX),
		"localY": float(pt0.localY)
	}
	var res_world_loc: Dictionary = EquipmentDamage.resolve_hit_locations(boat_world_eq, hit_world_eq)
	var res_local_loc: Dictionary = EquipmentDamage.resolve_hit_locations(boat_local_eq, hit_local_eq)
	check(res_world_loc.ok and res_local_loc.ok and res_world_loc.locations == res_local_loc.locations and Vector2(res_world_loc.localNorm).distance_to(Vector2(res_local_loc.localNorm)) <= 0.0001, "world impactX/Y and normalized localX/Y resolve identical localNorm and locations")
	var rng_w := RandomNumberGenerator.new(); rng_w.seed = 905
	var rng_l := RandomNumberGenerator.new(); rng_l.seed = 905
	Damage.apply_hit(boat_world_eq, hit_world_eq, rng_w)
	Damage.apply_hit(boat_local_eq, hit_local_eq, rng_l)
	check(_approx(float(boat_world_eq.hp), float(boat_local_eq.hp)) and _approx(float(_item_at(boat_world_eq.moduleCondition, "mount0").hp), float(_item_at(boat_local_eq.moduleCondition, "mount0").hp)) and _approx(float(_item_at(boat_world_eq.moduleCondition, "armor").hp), float(_item_at(boat_local_eq.moduleCondition, "armor").hp)), "world impactX/Y and normalized localX/Y produce identical hull, mount0, and armor HP")

	# 7. Valid normalized local coordinate 3.0 is kept in normalized hull units, never silently treated as pixels.
	var res_local_3: Dictionary = EquipmentDamage.resolve_hit_locations(boat_local_eq, {
		"damage": 140.0,
		"kind": "shell",
		"penetration": 20.0,
		"localX": 3.0,
		"localY": 0.0
	})
	check(res_local_3.ok and Vector2(res_local_3.localNorm).distance_to(Vector2(3.0, 0.0)) <= 0.0001 and res_local_3.locations == ["armor"], "normalized localX=3.0 stays at localNorm=(3.0,0.0) without dividing by hull_size into pumps/cabin (got localNorm=%s, locations=%s)" % [str(res_local_3.localNorm), str(res_local_3.locations)])

	# 8. Refusal of ambiguous or partial coordinate fields without mutating boat.
	var snap_ambig: Dictionary = boat_local_eq.duplicate(true)
	for bad_hit in [
		{"damage": 140.0, "kind": "shell", "impactX": world_m0.x, "impactY": world_m0.y, "localX": float(pt0.localX), "localY": float(pt0.localY)},
		{"damage": 140.0, "kind": "shell", "localX": float(pt0.localX)},
		{"damage": 140.0, "kind": "shell", "impactX": world_m0.x},
		{"damage": 140.0, "kind": "shell", "localX": float(pt0.localX), "localY": "bad"},
		{"damage": 140.0, "kind": "shell", "localX": float(pt0.localX), "localY": float(pt0.localY), "blastRadius": -2.0}
	]:
		var bad_loc: Dictionary = EquipmentDamage.resolve_hit_locations(boat_local_eq, bad_hit)
		var bad_eq: Dictionary = EquipmentDamage.apply_hit_equipment(boat_local_eq, bad_hit)
		var bad_ev: Array = Damage.apply_hit(boat_local_eq, bad_hit, rng_l)
		check(not bad_loc.ok and not bad_eq.ok and bad_ev.is_empty() and boat_local_eq == snap_ambig, "ambiguous/invalid hit coordinate descriptor is refused with zero mutation: " + str(bad_hit))

func test_armor_condition_mitigation_and_weapon_factors() -> void:
	var fit: Dictionary = {
		"weapons": ["stock_primary", "rapid_gun", "light_cannon", "fire_rocket"],
		"engine": "stock_engine",
		"armor": "stock_armor"
	}
	var boat_full: Dictionary = _canonical_boat(23, "fleet-armor-full", {}, fit)
	var boat_half: Dictionary = _canonical_boat(23, "fleet-armor-half", {}, fit)
	var boat_zero: Dictionary = _canonical_boat(23, "fleet-armor-zero", {}, fit)

	var half_arm_uid: String = str(_item_at(boat_half.moduleCondition, "armor").itemUid)
	var zero_arm_uid: String = str(_item_at(boat_zero.moduleCondition, "armor").itemUid)
	check(Core.apply_component_damage(boat_half.moduleCondition, {"itemUid": half_arm_uid, "loss": 0.50, "cause": "Rust"}).ok, "half armor damaged to 0.50")
	check(Core.apply_component_damage(boat_zero.moduleCondition, {"itemUid": zero_arm_uid, "loss": 0.85, "cause": "Shattered belt"}).ok, "zero armor disabled at 0.15")

	var st_full: Dictionary = Damage.get_status(boat_full)
	var st_half: Dictionary = Damage.get_status(boat_half)
	var st_zero: Dictionary = Damage.get_status(boat_zero)
	check(_approx(float(st_full.armorFactor), 1.0) and _approx(float(st_full.effectiveArmor), 20.0), "full armor reports armorFactor=1.0, effectiveArmor=20.0 (got=%.2f,%.2f)" % [float(st_full.armorFactor), float(st_full.effectiveArmor)])
	check(_approx(float(st_half.armorFactor), 0.50) and _approx(float(st_half.effectiveArmor), 10.0), "0.50 armor reports armorFactor=0.50, effectiveArmor=10.0 (got=%.2f,%.2f)" % [float(st_half.armorFactor), float(st_half.effectiveArmor)])
	check(_approx(float(st_zero.armorFactor), 0.0) and _approx(float(st_zero.effectiveArmor), 0.0), "disabled 0.15 armor reports armorFactor=0.0, effectiveArmor=0.0 (got=%.2f,%.2f)" % [float(st_zero.armorFactor), float(st_zero.effectiveArmor)])

	var rng_a := RandomNumberGenerator.new(); rng_a.seed = 44
	var rng_b := RandomNumberGenerator.new(); rng_b.seed = 44
	var rng_c := RandomNumberGenerator.new(); rng_c.seed = 44
	var shell_hit: Dictionary = {"damage": 50.0, "kind": "shell", "penetration": 4.0, "section": "bow"}
	Damage.apply_hit(boat_full, shell_hit, rng_a)
	Damage.apply_hit(boat_half, shell_hit, rng_b)
	Damage.apply_hit(boat_zero, shell_hit, rng_c)

	# Expected hull HP after 50-damage shell (penetration 4):
	# full armor (20): mitigated=16, impact=50 - 12.8 = 37.2, hull loss=13.02 -> 686.98
	# half armor (10): mitigated=6, impact=50 - 4.8 = 45.2, hull loss=15.82 -> 684.18
	# disabled armor (0): mitigated=0, impact=50.0, hull loss=17.50 -> 682.50
	check(_approx(float(boat_full.hp), 686.98), "intact armor leaves hull at 686.98 HP (got=%.4f)" % float(boat_full.hp))
	check(_approx(float(boat_half.hp), 684.18), "0.50 armor leaves hull at 684.18 HP (got=%.4f)" % float(boat_half.hp))
	check(_approx(float(boat_zero.hp), 682.50), "disabled armor leaves hull at 682.50 HP (got=%.4f)" % float(boat_zero.hp))

	# Per-mount weaponFactors vs crew/fire weaponFactor
	var m0_uid: String = str(_item_at(boat_full.moduleCondition, "mount0").itemUid)
	var m1_uid: String = str(_item_at(boat_full.moduleCondition, "mount1").itemUid)
	check(Core.apply_component_damage(boat_full.moduleCondition, {"itemUid": m0_uid, "loss": 0.85, "cause": "Mount0 knocked out"}).ok, "mount0 disabled")
	check(Core.apply_component_damage(boat_full.moduleCondition, {"itemUid": m1_uid, "loss": 0.40, "cause": "Mount1 bent"}).ok, "mount1 damaged to 0.60")
	boat_full.fire = 0.0
	boat_full.water = 0.0
	boat_full.breaches = []
	boat_full.wounded = 0.0
	var st_weap: Dictionary = Damage.get_status(boat_full)
	check(_approx(float(st_weap.weaponFactors["mount0"]), 0.0), "disabled mount0 has weaponFactors['mount0']=0.0 (got=%.4f)" % float(st_weap.weaponFactors["mount0"]))
	check(_approx(float(st_weap.weaponFactors["mount1"]), 0.60), "damaged mount1 has weaponFactors['mount1']=0.60 (got=%.4f)" % float(st_weap.weaponFactors["mount1"]))
	check(_approx(float(st_weap.weaponFactors["mount2"]), 1.0) and _approx(float(st_weap.weaponFactors["mount3"]), 1.0), "undamaged mount2..3 remain 1.0")
	check(_approx(float(st_weap.weaponFactor), 1.0), "legacy ship weaponFactor remains crew/fire ability 1.0 (got=%.4f)" % float(st_weap.weaponFactor))

func test_disabled_engine_raw_projection_and_speed_turn_impairment() -> void:
	# tin_skiff: crew=5.0, crewMin=3.0, policy="bail" -> weights[2]=0.20 -> crewRepair=1.0 sailor
	var boat: Dictionary = _canonical_boat(0, "fleet-skiff-engine-hyst", {
		"policy": "bail",
		"supplies": 10.0,
		"water": 0.0,
		"fire": 0.0
	})
	var eng_uid: String = str(_item_at(boat.moduleCondition, "engine").itemUid)
	check(Core.apply_component_damage(boat.moduleCondition, {"itemUid": eng_uid, "loss": 0.85, "cause": "Cracked manifold"}).ok, "engine damaged to 0.15 disabled")
	Records.publish(boat)
	var st0: Dictionary = Damage.get_status(boat)
	check(_approx(float(boat.engine), 0.15) and _approx(float(st0.engineHp), 0.15) and _approx(float(st0.engineFactor), 0.0) and _approx(float(st0.speedFactor), 0.0) and _approx(float(st0.turnFactor), 0.0), "at 0.15 disabled: raw engine=0.15 while engineFactor/speedFactor/turnFactor=0.0")

	# Tick 2.5s: crewRepair=1.0 -> availableWork=2.5 crew-s -> +0.10 HP (0.15 -> 0.25), supplies used = 0.10 * 1.5 = 0.15
	var tick_to_25: Dictionary = Damage.tick_ship(boat, 2.5)
	var eng_25: Dictionary = _item_at(boat.moduleCondition, "engine")
	check(_approx(float(eng_25.hp), 0.25) and str(eng_25.status) == "disabled", "after 2.5s repair, engine is at 0.25 HP and still disabled below 0.30 threshold (got hp=%.4f, status=%s)" % [float(eng_25.hp), str(eng_25.status)])
	check(_approx(float(boat.engine), 0.25), "raw boat.engine projects 0.25 rather than 0.0 while disabled (got=%.4f)" % float(boat.engine))
	check(_approx(float(tick_to_25.engineHp), 0.25) and _approx(float(tick_to_25.engineFactor), 0.0), "status reports engineHp=0.25 and engineFactor=0.0 (got hp=%.4f, factor=%.4f)" % [float(tick_to_25.engineHp), float(tick_to_25.engineFactor)])
	check(_approx(float(tick_to_25.speedFactor), 0.0) and _approx(float(tick_to_25.turnFactor), 0.0), "disabled 0.25 engine keeps speedFactor=0.0 and turnFactor=0.0 (got speed=%.4f, turn=%.4f)" % [float(tick_to_25.speedFactor), float(tick_to_25.turnFactor)])
	check(_approx(float(tick_to_25.usedWork), 2.5) and _approx(float(tick_to_25.usedSupplies), 0.15) and _approx(float(boat.supplies), 9.85), "2.5s engine repair consumes 2.5 crew-s and 0.15 supplies (got work=%.4f, supp=%.4f, rem=%.4f)" % [float(tick_to_25.usedWork), float(tick_to_25.usedSupplies), float(boat.supplies)])

	# Tick another 2.5s: +0.10 HP (0.25 -> 0.35), crossing the 0.30 re-enable threshold!
	var tick_to_35: Dictionary = Damage.tick_ship(boat, 2.5)
	var eng_35: Dictionary = _item_at(boat.moduleCondition, "engine")
	check(_approx(float(eng_35.hp), 0.35) and str(eng_35.status) == "damaged", "after another 2.5s repair, engine reaches 0.35 and re-enables to damaged (got hp=%.4f, status=%s)" % [float(eng_35.hp), str(eng_35.status)])
	check(_approx(float(boat.engine), 0.35) and _approx(float(tick_to_35.engineFactor), 0.35) and _approx(float(tick_to_35.speedFactor), 0.35) and _approx(float(tick_to_35.turnFactor), 0.35), "re-enabled 0.35 engine restores speedFactor=0.35 and turnFactor=0.35 (got speed=%.4f, turn=%.4f)" % [float(tick_to_35.speedFactor), float(tick_to_35.turnFactor)])

func test_mechanical_pump_failure_and_hand_bailing() -> void:
	# tin_skiff: pumps=2.4, crew=5.0, policy="balanced" -> weights[1]=0.28 -> crewBail=1.4 sailors
	# handBailing = 1.4 * 1.65 = 2.31 L/s; full mechanical pump = 2.4 * 2.3 * 1.0 = 5.52 L/s; total = 7.83 L/s
	var boat: Dictionary = _canonical_boat(0, "fleet-skiff-pumps", {
		"water": 120.0,
		"supplies": 0.0,
		"fuel": 60.0,
		"policy": "balanced"
	})
	var st_healthy: Dictionary = Damage.get_status(boat)
	check(_approx(float(st_healthy.handBailing), 2.31) and _approx(float(st_healthy.pump), 5.52) and _approx(float(st_healthy.bailing), 7.83), "healthy pumps: hand=2.31, pump=5.52, total=7.83 L/s (got hand=%.4f, pump=%.4f, total=%.4f)" % [float(st_healthy.handBailing), float(st_healthy.pump), float(st_healthy.bailing)])

	var pmp_uid: String = str(_item_at(boat.moduleCondition, "pumps").itemUid)
	check(Core.apply_component_damage(boat.moduleCondition, {"itemUid": pmp_uid, "loss": 0.50, "cause": "Valve crack"}).ok, "pumps damaged to 0.50")
	var st_half: Dictionary = Damage.get_status(boat)
	check(_approx(float(st_half.pumpFactor), 0.50) and _approx(float(st_half.pump), 2.76) and _approx(float(st_half.handBailing), 2.31) and _approx(float(st_half.bailing), 5.07), "0.50 pumps: pump=2.76, hand=2.31, total=5.07 L/s (got total=%.4f)" % float(st_half.bailing))

	check(Core.apply_component_damage(boat.moduleCondition, {"itemUid": pmp_uid, "loss": 0.35, "cause": "Impeller jammed"}).ok, "pumps disabled at 0.15 while engine remains 1.0")
	var st_failed: Dictionary = Damage.get_status(boat)
	check(_approx(float(st_failed.engineFactor), 1.0) and _approx(float(st_failed.pumpFactor), 0.0) and _approx(float(st_failed.pump), 0.0) and _approx(float(st_failed.handBailing), 2.31) and _approx(float(st_failed.bailing), 2.31), "disabled pumps with healthy engine: mechanical pump=0.0 while handBailing=2.31 L/s (got pump=%.4f, bailing=%.4f)" % [float(st_failed.pump), float(st_failed.bailing)])

	# Advance 10.0s with disabled pumps and 0 supplies: hand bailing removes 2.31 * 10 = 23.1 L (120.0 -> 96.9)
	Damage.tick_ship(boat, 10.0)
	check(_approx(float(boat.water), 96.9), "hand bailing alone lowers water from 120.0 to 96.9 L over 10s (got=%.4f)" % float(boat.water))

	# Pump-free hull base (pumps=0.0): no pumps record, mechanical pump=0.0, hand bailing works
	var pump_free_base: Dictionary = world.HULLS[1].duplicate(true)
	pump_free_base.pumps = 0.0
	var punt: Dictionary = Damage.create_ship(pump_free_base, {"crew": 4.0, "water": 50.0, "policy": "bail"})
	Refit.ensure(punt, pump_free_base)
	punt.uid = "fleet-punt-handbail"
	check(Records.initialize(punt, _context(pump_free_base, punt.loadout, "fleet-punt-handbail")).ok, "pump-free hull initializes")
	var st_punt: Dictionary = Damage.get_status(punt)
	# crew=4.0, bail weight=0.65 -> crewBail=2.6 -> handBailing = 2.6 * 1.65 = 4.29 L/s
	check(_approx(float(st_punt.pump), 0.0) and _approx(float(st_punt.bailing), 4.29), "pump-free hull has pump=0.0 and handBailing=4.29 L/s (got=%.4f)" % float(st_punt.bailing))

func test_single_repair_labor_pool_conservation_and_zero_kits_no_crew() -> void:
	# tin_skiff: crew=5.0, policy="bail" -> crewRepair=1.0 sailor (1.0 crew-s per second)
	var boat: Dictionary = _canonical_boat(0, "fleet-skiff-labor-pool", {
		"hp": 120.0,
		"fire": 10.0,
		"breaches": [{"area": 18.0, "section": "bow"}],
		"supplies": 10.0,
		"policy": "bail"
	})
	var eng_uid: String = str(_item_at(boat.moduleCondition, "engine").itemUid)
	check(Core.apply_component_damage(boat.moduleCondition, {"itemUid": eng_uid, "loss": 0.50, "cause": "Shrapnel"}).ok, "engine damaged to 0.50")
	Records.publish(boat)

	# 1. Over 2.0s in "auto" priority, fire=10.0 requires >15 crew-s, so 100% of the 2.0 crew-s pool goes to fire.
	var res_fire_first: Dictionary = Damage.tick_ship(boat, 2.0)
	check(_approx(float(res_fire_first.availableWork), 2.0) and _approx(float(res_fire_first.usedWork), 2.0), "2.0s tick conserved 2.0 crew-s of repair work (got avail=%.4f, used=%.4f)" % [float(res_fire_first.availableWork), float(res_fire_first.usedWork)])
	check(_approx(float(res_fire_first.workByTask["fire"]), 2.0) and _approx(float(res_fire_first.workByTask["patch"]), 0.0) and _approx(float(res_fire_first.workByTask["machinery"]), 0.0) and _approx(float(res_fire_first.workByTask["hull"]), 0.0), "active fire absorbs all 2.0 crew-s in auto priority without duplicating crewRepair onto patch/machinery/hull")
	check(_approx(float( boat.fire ), 8.86) and _approx(Damage.sum_areas(boat), 18.0) and _approx(float(boat.supplies), 10.0), "fire drops to 8.86 while breach stays 18.0 cm² and supplies stay 10.0 (got fire=%.4f, area=%.4f, supp=%.4f)" % [float(boat.fire), Damage.sum_areas(boat), float(boat.supplies)])

	# 2. Mid-step transition: small fire (0.57) takes exactly 1.0 crew-s (including 0.08/s growth over 1.0s -> 0.65 / 0.65 = 1.0 crew-s),
	# leaving 1.0 crew-s out of 2.0s for breach patching (1.0 * 1.8 = 1.8 cm² patched, 0.0324 supplies used).
	var boat_split: Dictionary = _canonical_boat(0, "fleet-skiff-labor-split", {
		"hp": 120.0,
		"fire": 0.57,
		"breaches": [{"area": 18.0, "section": "bow"}],
		"supplies": 10.0,
		"policy": "bail"
	})
	var res_split: Dictionary = Damage.tick_ship(boat_split, 2.0)
	check(_approx(float(boat_split.fire), 0.0), "small fire is completely extinguished during 2.0s tick (got=%.4f)" % float(boat_split.fire))
	check(_approx(float(res_split.workByTask["fire"]), 1.0, 0.02) and _approx(float(res_split.workByTask["patch"]), 1.0, 0.02) and _approx(float(res_split.usedWork), 2.0), "2.0 crew-s splits ~1.0s to fire and ~1.0s to breach patching (got fire=%.4f, patch=%.4f, total=%.4f)" % [float(res_split.workByTask["fire"]), float(res_split.workByTask["patch"]), float(res_split.usedWork)])
	check(_approx(Damage.sum_areas(boat_split), 16.2, 0.04) and _approx(float(boat_split.supplies), 9.9676, 0.001), "remainder of labor pool patches ~1.8 cm² and spends ~0.0324 supplies (got area=%.4f, supp=%.4f)" % [Damage.sum_areas(boat_split), float(boat_split.supplies)])

	# 3. Zero supply kits: fire suppression still works, material repairs (patch, machinery, hull) spend 0 work and 0 supplies.
	var boat_no_kits: Dictionary = _canonical_boat(0, "fleet-skiff-zero-kits", {
		"hp": 120.0,
		"fire": 5.0,
		"breaches": [{"area": 18.0, "section": "bow"}],
		"supplies": 0.0,
		"policy": "bail"
	})
	var nk_eng_uid: String = str(_item_at(boat_no_kits.moduleCondition, "engine").itemUid)
	check(Core.apply_component_damage(boat_no_kits.moduleCondition, {"itemUid": nk_eng_uid, "loss": 0.40, "cause": "Wear"}).ok, "engine at 0.60")
	Records.publish(boat_no_kits)
	var res_nk_fire: Dictionary = Damage.tick_ship(boat_no_kits, 2.0)
	check(_approx(float(boat_no_kits.fire), 3.86) and _approx(float(res_nk_fire.workByTask["fire"]), 2.0) and _approx(float(res_nk_fire.usedSupplies), 0.0) and _approx(Damage.sum_areas(boat_no_kits), 18.0), "with 0 supplies, crew still suppresses fire (5.0 -> 3.86) and spends 0 supplies")

	var dry_hp_before: float = float(boat_no_kits.hp)
	boat_no_kits.fire = 0.0
	var res_nk_dry: Dictionary = Damage.tick_ship(boat_no_kits, 2.0)
	check(_approx(float(res_nk_dry.usedWork), 0.0) and _approx(float(res_nk_dry.usedSupplies), 0.0) and _approx(Damage.sum_areas(boat_no_kits), 18.0) and _approx(float(boat_no_kits.hp), dry_hp_before), "with 0 supplies and 0 fire, no material repair work or supplies are consumed")

	# 4. Zero able crew (all crew wounded): fire grows, no repairs occur.
	var boat_no_crew: Dictionary = _canonical_boat(0, "fleet-skiff-zero-crew", {
		"crew": 3.0,
		"wounded": 3.0,
		"fire": 4.0,
		"breaches": [{"area": 10.0, "section": "bow"}],
		"supplies": 10.0,
		"policy": "repair"
	})
	var res_nc: Dictionary = Damage.tick_ship(boat_no_crew, 2.0)
	check(_approx(float(res_nc.availableWork), 0.0) and _approx(float(res_nc.usedWork), 0.0) and _approx(float(boat_no_crew.fire), 4.16) and _approx(Damage.sum_areas(boat_no_crew), 10.0), "with 0 able crew, availableWork=0.0, fire grows 4.0 -> 4.16, and breaches stay 10.0")

func test_finite_stores_partial_repair_and_jury_cap() -> void:
	var boat: Dictionary = _canonical_boat(0, "fleet-skiff-partial-cap", {
		"policy": "bail",
		"supplies": 0.15,
		"refitLocker": {"rapid_gun": 1}
	})
	var eng_uid: String = str(_item_at(boat.moduleCondition, "engine").itemUid)
	check(Core.apply_component_damage(boat.moduleCondition, {"itemUid": eng_uid, "loss": 0.60, "cause": "Bearing score"}).ok, "engine damaged to 0.40")
	Records.publish(boat)

	# 1. Supply-starved partial repair: 0.15 supplies / 1.5 suppliesPerHp = +0.10 engine HP (0.40 -> 0.50), using 2.5 crew-s out of 5.0s
	var res_partial: Dictionary = Damage.tick_ship(boat, 5.0)
	var eng_part: Dictionary = _item_at(boat.moduleCondition, "engine")
	check(_approx(float(eng_part.hp), 0.50) and _approx(float(boat.engine), 0.50), "0.15 supplies partially repairs engine from 0.40 to 0.50 (got=%.4f)" % float(eng_part.hp))
	check(_approx(float(res_partial.usedWork), 2.50) and _approx(float(res_partial.usedSupplies), 0.15) and _approx(float(boat.supplies), 0.0), "partial repair stops at 2.50 crew-s and 0.0 remaining supplies (got work=%.4f, supp=%.4f, rem=%.4f)" % [float(res_partial.usedWork), float(res_partial.usedSupplies), float(boat.supplies)])

	# 2. Jury cap 0.75 across pumps, engine, weapons; armor and locker remain yard-only.
	boat.supplies = 10.0
	var pmp_uid: String = str(_item_at(boat.moduleCondition, "pumps").itemUid)
	var m0_uid: String = str(_item_at(boat.moduleCondition, "mount0").itemUid)
	var arm_uid: String = str(_item_at(boat.moduleCondition, "armor").itemUid)
	var lck_uid: String = str(Core.list_locker(boat.moduleCondition).items[0].itemUid)
	check(Core.apply_component_damage(boat.moduleCondition, {"itemUid": pmp_uid, "loss": 0.50, "cause": "Seal leak"}).ok, "pumps at 0.50")
	check(Core.apply_component_damage(boat.moduleCondition, {"itemUid": m0_uid, "loss": 0.50, "cause": "Barrel pitting"}).ok, "mount0 at 0.50")
	check(Core.apply_component_damage(boat.moduleCondition, {"itemUid": arm_uid, "loss": 0.60, "cause": "Plate dent"}).ok, "armor at 0.40")
	check(Core.apply_component_damage(boat.moduleCondition, {"itemUid": lck_uid, "loss": 0.65, "cause": "Old battle damage"}).ok, "locker gun at 0.35")
	Records.publish(boat)

	# Each of pumps (0.50->0.75), engine (0.50->0.75), mount0 (0.50->0.75) gains 0.25 HP (total 0.75 HP = 18.75 crew-s, 0.925 supplies).
	var res_cap: Dictionary = Damage.tick_ship(boat, 40.0)
	check(_approx(float(_item_at(boat.moduleCondition, "pumps").hp), 0.75) and str(_item_at(boat.moduleCondition, "pumps").status) == "damaged", "pumps stops at 0.75 jury cap")
	check(_approx(float(_item_at(boat.moduleCondition, "engine").hp), 0.75) and _approx(float(boat.engine), 0.75), "engine stops at 0.75 jury cap")
	check(_approx(float(_item_at(boat.moduleCondition, "mount0").hp), 0.75), "mount0 stops at 0.75 jury cap")
	check(_approx(float(_item_at(boat.moduleCondition, "armor").hp), 0.40), "installed armor is not repaired at sea and stays 0.40")
	check(_approx(float(boat.moduleCondition.items[lck_uid].hp), 0.35), "locker item is not repaired at sea and stays 0.35")
	check(_approx(float(res_cap.repairedModuleHp), 0.75) and _approx(float(res_cap.usedWork), 18.75) and _approx(float(res_cap.usedSupplies), 0.925) and _approx(float(boat.supplies), 9.075), "jury repair to 0.75 cap uses exactly 18.75 crew-s and 0.925 supplies (got work=%.4f, supp=%.4f, rem=%.4f)" % [float(res_cap.usedWork), float(res_cap.usedSupplies), float(boat.supplies)])

	var before_port: Dictionary = boat.duplicate(true)
	var port_res: Dictionary = Damage.repair_at_port(boat, 10000.0)
	check(int(port_res.cost) == 0 and not bool(port_res.repaired) and boat == before_port, "Damage.repair_at_port refuses imaginary scalar port restoration on canonical boat")

func test_priority_choices_allocation() -> void:
	var base_boat: Dictionary = _canonical_boat(0, "fleet-skiff-priority", {
		"hp": 120.0,
		"supplies": 10.0,
		"policy": "bail"
	})
	for loc in ["pumps", "engine", "mount0"]:
		var uid: String = str(_item_at(base_boat.moduleCondition, loc).itemUid)
		check(Core.apply_component_damage(base_boat.moduleCondition, {"itemUid": uid, "loss": 0.60, "cause": "Test damage"}).ok, loc + " damaged to 0.40")
	Records.publish(base_boat)

	var b_hull: Dictionary = base_boat.duplicate(true)
	var b_pumps: Dictionary = base_boat.duplicate(true)
	var b_engine: Dictionary = base_boat.duplicate(true)
	var b_weapons: Dictionary = base_boat.duplicate(true)
	check(Damage.set_repair_priority(b_hull, "hull") == "hull", "set priority hull")
	check(Damage.set_repair_priority(b_pumps, "pumps") == "pumps", "set priority pumps")
	check(Damage.set_repair_priority(b_engine, "engine") == "engine", "set priority engine")
	check(Damage.set_repair_priority(b_weapons, "weapons") == "weapons", "set priority weapons")

	var r_hull: Dictionary = Damage.tick_ship(b_hull, 2.5)
	var r_pumps: Dictionary = Damage.tick_ship(b_pumps, 2.5)
	var r_engine: Dictionary = Damage.tick_ship(b_engine, 2.5)
	var r_weapons: Dictionary = Damage.tick_ship(b_weapons, 2.5)

	check(_approx(float(b_hull.hp), 120.55) and _approx(float(r_hull.workByTask["hull"]), 2.5) and _approx(float(r_hull.usedSupplies), 0.1925) and _approx(float(_item_at(b_hull.moduleCondition, "pumps").hp), 0.40), "hull priority allocates all 2.5 crew-s to hull (+0.55 HP, 0.1925 supplies)")
	check(_approx(float(_item_at(b_pumps.moduleCondition, "pumps").hp), 0.50) and _approx(float(_item_at(b_pumps.moduleCondition, "engine").hp), 0.40) and _approx(float(b_pumps.hp), 120.0) and _approx(float(r_pumps.usedSupplies), 0.12), "pumps priority allocates all 2.5 crew-s to pumps (0.40 -> 0.50, 0.12 supplies)")
	check(_approx(float(_item_at(b_engine.moduleCondition, "engine").hp), 0.50) and _approx(float(_item_at(b_engine.moduleCondition, "pumps").hp), 0.40) and _approx(float(b_engine.hp), 120.0) and _approx(float(r_engine.usedSupplies), 0.15), "engine priority allocates all 2.5 crew-s to engine (0.40 -> 0.50, 0.15 supplies)")
	check(_approx(float(_item_at(b_weapons.moduleCondition, "mount0").hp), 0.50) and _approx(float(_item_at(b_weapons.moduleCondition, "pumps").hp), 0.40) and _approx(float(b_weapons.hp), 120.0) and _approx(float(r_weapons.usedSupplies), 0.10), "weapons priority allocates all 2.5 crew-s to mount0 (0.40 -> 0.50, 0.10 supplies)")

	var actual_max_hp: float = float(world.HULLS[0].hp)
	# Hull-first with full hull + damaged engine: allocates real crewRepair and repairs machinery after clear hull/fire/patch.
	var b_hull_full: Dictionary = _canonical_boat(0, "fleet-skiff-hull-first-full", {
		"hp": actual_max_hp,
		"supplies": 10.0,
		"policy": "bail"
	})
	var hf_keys_before: Array = b_hull_full.keys()
	hf_keys_before.sort()
	var hf_eng_uid: String = str(_item_at(b_hull_full.moduleCondition, "engine").itemUid)
	check(Core.apply_component_damage(b_hull_full.moduleCondition, {"itemUid": hf_eng_uid, "loss": 0.60, "cause": "Hull-first engine test"}).ok, "hull-first full-hull engine damaged to 0.40")
	Records.publish(b_hull_full)
	check(Damage.set_repair_priority(b_hull_full, "hull") == "hull", "set priority hull on full-hull boat")
	var st_hf_before: Dictionary = Damage.get_status(b_hull_full)
	check(_approx(float(st_hf_before.crewRepair), 1.0), "full hull with damaged engine under hull priority allocates crewRepair=1.0 (got=%.4f)" % float(st_hf_before.crewRepair))
	var r_hull_full: Dictionary = Damage.tick_ship(b_hull_full, 2.5)
	var hf_keys_after: Array = b_hull_full.keys()
	hf_keys_after.sort()
	check(_approx(float(b_hull_full.hp), actual_max_hp) and _approx(float(r_hull_full.workByTask["hull"]), 0.0) and _approx(float(r_hull_full.workByTask["machinery"]), 2.5) and _approx(float(r_hull_full.usedWork), 2.5), "full hull under hull priority passes all 2.5 crew-s to machinery (got hullWork=%.4f, machWork=%.4f)" % [float(r_hull_full.workByTask["hull"]), float(r_hull_full.workByTask["machinery"])])
	check(_approx(float(_item_at(b_hull_full.moduleCondition, "engine").hp), 0.50) and _approx(float(b_hull_full.engine), 0.50) and _approx(float(r_hull_full.usedSupplies), 0.15) and _approx(float(b_hull_full.supplies), 9.85), "full hull under hull priority advances engine 0.40 -> 0.50 and spends 0.15 supplies (got eng=%.4f, supp=%.4f, rem=%.4f)" % [float(_item_at(b_hull_full.moduleCondition, "engine").hp), float(r_hull_full.usedSupplies), float(b_hull_full.supplies)])
	check(_approx(float(b_hull_full.crew), 5.0) and _approx(float(b_hull_full.wounded), 0.0) and hf_keys_after == hf_keys_before, "hull-first machinery repair adds no extra people or boat fields")

	# Hull-first with partial hull (missing 0.22 HP = 1.0 crew-s) + damaged engine (0.40):
	# repairs hull to the actual maximum first (1.0 crew-s, 0.077 supplies), then spills remaining 1.5 crew-s into engine (+0.06 HP -> 0.46, 0.09 supplies).
	var b_hull_partial: Dictionary = _canonical_boat(0, "fleet-skiff-hull-first-partial", {
		"hp": actual_max_hp - 0.22,
		"supplies": 10.0,
		"policy": "bail"
	})
	var hp_eng_uid: String = str(_item_at(b_hull_partial.moduleCondition, "engine").itemUid)
	check(Core.apply_component_damage(b_hull_partial.moduleCondition, {"itemUid": hp_eng_uid, "loss": 0.60, "cause": "Partial hull spillover test"}).ok, "partial-hull boat engine damaged to 0.40")
	Records.publish(b_hull_partial)
	check(Damage.set_repair_priority(b_hull_partial, "hull") == "hull", "set priority hull on partial-hull boat")
	var r_hull_partial: Dictionary = Damage.tick_ship(b_hull_partial, 2.5)
	check(_approx(float(b_hull_partial.hp), actual_max_hp) and _approx(float(r_hull_partial.repairedHullHp), 0.22) and _approx(float(r_hull_partial.workByTask["hull"]), 1.0) and _approx(float(r_hull_partial.suppliesByTask["hull"]), 0.077), "partial hull under hull priority spends 1.0 crew-s and 0.077 supplies finishing hull to its actual maximum (got hp=%.4f, hullWork=%.4f, hullSupp=%.4f)" % [float(b_hull_partial.hp), float(r_hull_partial.workByTask["hull"]), float(r_hull_partial.suppliesByTask["hull"])])
	check(_approx(float(_item_at(b_hull_partial.moduleCondition, "engine").hp), 0.46) and _approx(float(b_hull_partial.engine), 0.46) and _approx(float(r_hull_partial.repairedModuleHp), 0.06) and _approx(float(r_hull_partial.workByTask["machinery"]), 1.5) and _approx(float(r_hull_partial.suppliesByTask["machinery"]), 0.09), "remaining 1.5 crew-s under hull priority spills over to engine (0.40 -> 0.46, 0.09 supplies; got eng=%.4f, machWork=%.4f, machSupp=%.4f)" % [float(_item_at(b_hull_partial.moduleCondition, "engine").hp), float(r_hull_partial.workByTask["machinery"]), float(r_hull_partial.suppliesByTask["machinery"])])
	check(_approx(float(r_hull_partial.usedWork), 2.5) and _approx(float(r_hull_partial.usedSupplies), 0.167) and _approx(float(b_hull_partial.supplies), 9.833), "partial hull + engine spillover conserves 2.5 crew-s and 0.167 total supplies (got usedWork=%.4f, usedSupp=%.4f, remSupp=%.4f)" % [float(r_hull_partial.usedWork), float(r_hull_partial.usedSupplies), float(b_hull_partial.supplies)])

func test_timestep_30_60_equivalence() -> void:
	var base_boat: Dictionary = _canonical_boat(0, "fleet-skiff-dt-equiv", {
		"hp": 125.0,
		"water": 80.0,
		"fire": 6.0,
		"breaches": [{"area": 12.0, "section": "bow"}],
		"supplies": 15.0,
		"fuel": 50.0,
		"cooldown": 1.5,
		"policy": "repair"
	})
	check(Core.apply_component_damage(base_boat.moduleCondition, {"itemUid": str(_item_at(base_boat.moduleCondition, "engine").itemUid), "loss": 0.85, "cause": "Hit"}).ok, "engine at 0.15")
	check(Core.apply_component_damage(base_boat.moduleCondition, {"itemUid": str(_item_at(base_boat.moduleCondition, "pumps").itemUid), "loss": 0.55, "cause": "Hit"}).ok, "pumps at 0.45")
	check(Core.apply_component_damage(base_boat.moduleCondition, {"itemUid": str(_item_at(base_boat.moduleCondition, "mount0").itemUid), "loss": 0.50, "cause": "Hit"}).ok, "mount0 at 0.50")
	Records.publish(base_boat)

	var boat_30: Dictionary = base_boat.duplicate(true)
	var boat_60: Dictionary = base_boat.duplicate(true)
	var work_30: float = 0.0
	var supp_30: float = 0.0
	var work_60: float = 0.0
	var supp_60: float = 0.0

	for _i in range(180):
		var st30: Dictionary = Damage.tick_ship(boat_30, 1.0 / 30.0)
		work_30 += float(st30.usedWork)
		supp_30 += float(st30.usedSupplies)
	for _i in range(360):
		var st60: Dictionary = Damage.tick_ship(boat_60, 1.0 / 60.0)
		work_60 += float(st60.usedWork)
		supp_60 += float(st60.usedSupplies)

	for key in ["hp", "water", "fire", "engine", "supplies", "fuel", "cooldown"]:
		check(_approx(float(boat_30[key]), float(boat_60[key]), 0.00001), "30Hz vs 60Hz equivalence for " + key + " (30Hz=%.6f, 60Hz=%.6f)" % [float(boat_30[key]), float(boat_60[key])])
	check(_approx(Damage.sum_areas(boat_30), Damage.sum_areas(boat_60), 0.00001), "30Hz vs 60Hz equivalence for breach area")
	check(_approx(work_30, work_60, 0.00001) and _approx(supp_30, supp_60, 0.00001), "30Hz vs 60Hz equivalence for cumulative usedWork and usedSupplies (work %.6f vs %.6f, supp %.6f vs %.6f)" % [work_30, work_60, supp_30, supp_60])
	for loc in ["pumps", "engine", "mount0", "armor"]:
		var item30: Dictionary = _item_at(boat_30.moduleCondition, loc)
		var item60: Dictionary = _item_at(boat_60.moduleCondition, loc)
		check(_approx(float(item30.hp), float(item60.hp), 0.00001) and str(item30.status) == str(item60.status), "30Hz vs 60Hz equivalence for module at " + loc)

func test_legacy_without_schema_and_corrupt_owner_refusal() -> void:
	var base: Dictionary = world.HULLS[0].duplicate(true)
	var legacy_boat: Dictionary = Damage.create_ship(base, {"engine": 0.60, "water": 60.0, "breaches": [{"area": 10.0, "section": "bow"}]})
	check(not legacy_boat.has("moduleCondition"), "Damage.create_ship never seeds moduleCondition automatically")
	var leg_before: Dictionary = legacy_boat.duplicate(true)
	var leg_status: Dictionary = Damage.get_status(legacy_boat)
	check(bool(leg_status.equipmentOk) and str(leg_status.equipmentMode) == "legacy" and bool(leg_status.needsInitialize) and leg_status.weaponFactors.is_empty(), "get_status on legacy absent owner reports legacy mode and needsInitialize=true")
	check(legacy_boat == leg_before, "get_status on legacy boat does not mutate or seed boat")

	var rng := RandomNumberGenerator.new(); rng.seed = 25
	Damage.apply_hit(legacy_boat, {"damage": 20.0, "kind": "bullet"}, rng)
	Damage.tick_ship(legacy_boat, 1.0)
	check(not legacy_boat.has("moduleCondition"), "apply_hit and tick_ship on legacy boat retain legacy numerical behavior without seeding moduleCondition")

	# Corrupt existing owner cases: bad version, erased integral pumps, erased loadout weapon, foreign condition field
	var corrupt_ver: Dictionary = _canonical_boat(0, "fleet-corrupt-ver")
	corrupt_ver.moduleCondition = {"version": 99, "items": {}}

	var corrupt_missing_pump: Dictionary = _canonical_boat(0, "fleet-corrupt-pump")
	var pump_uid: String = str(_item_at(corrupt_missing_pump.moduleCondition, "pumps").itemUid)
	corrupt_missing_pump.moduleCondition.items.erase(pump_uid)

	var corrupt_missing_weap: Dictionary = _canonical_boat(0, "fleet-corrupt-weap")
	var m0_uid: String = str(_item_at(corrupt_missing_weap.moduleCondition, "mount0").itemUid)
	corrupt_missing_weap.moduleCondition.items.erase(m0_uid)

	var foreign_owner: Dictionary = _canonical_boat(0, "fleet-foreign-owner")
	foreign_owner.weaponCondition = {"mount0": 0.5}

	for pair in [["corrupt_ver", corrupt_ver], ["missing_pump", corrupt_missing_pump], ["missing_weap", corrupt_missing_weap], ["foreign_owner", foreign_owner]]:
		var label: String = str(pair[0])
		var bad_boat: Dictionary = pair[1]
		var snap_before: Dictionary = bad_boat.duplicate(true)
		var st_bad: Dictionary = Damage.get_status(bad_boat)
		check(not bool(st_bad.equipmentOk) and str(st_bad.equipmentMode) == "invalid" and not bool(st_bad.needsInitialize), label + ": get_status fails closed with equipmentOk=false, mode=invalid, needsInitialize=false")
		check(_approx(float(st_bad.speedFactor), 0.0) and _approx(float(st_bad.turnFactor), 0.0) and _approx(float(st_bad.engineFactor), 0.0) and _approx(float(st_bad.pumpFactor), 0.0) and _approx(float(st_bad.armorFactor), 0.0) and _approx(float(st_bad.weaponFactor), 0.0) and st_bad.weaponFactors.is_empty(), label + ": failed-closed status zeroes all equipment factors")
		check(bad_boat == snap_before, label + ": get_status does not erase, reseed, or heal corrupt owner")

		var hit_events: Array = Damage.apply_hit(bad_boat, {"damage": 50.0, "kind": "shell", "section": "engine"}, rng)
		check(hit_events.is_empty() and bad_boat == snap_before, label + ": apply_hit refuses corrupt owner without mutation")

		var tick_bad: Dictionary = Damage.tick_ship(bad_boat, 2.0)
		check(not bool(tick_bad.equipmentOk) and bad_boat == snap_before, label + ": tick_ship refuses corrupt owner without mutation")

func test_detached_observer_no_mutation_and_sync_ordering() -> void:
	var base: Dictionary = world.HULLS[0].duplicate(true)
	var boat: Dictionary = _canonical_boat(0, "fleet-skiff-detached-sync", {
		"policy": "bail",
		"supplies": 10.0
	})
	var uids_before: Array = Core.collect_item_uids([boat.moduleCondition]).uids
	var seq_before: int = int(boat.moduleCondition.nextItemSeq)

	# External downward legacy engine write (1.0 -> 0.45) absorbed BEFORE tick_ship repair (+0.10 -> 0.55) and published AFTER.
	boat.engine = 0.45
	var tick_res: Dictionary = Damage.tick_ship(boat, 2.5)
	check(_approx(float(_item_at(boat.moduleCondition, "engine").hp), 0.55) and _approx(float(boat.engine), 0.55), "tick_ship absorbs downward 0.45 scalar before repairing +0.10 to 0.55 and publishing 0.55 (got item=%.4f, scalar=%.4f)" % [float(_item_at(boat.moduleCondition, "engine").hp), float(boat.engine)])

	# Repeated Refit.ensure and Damage.get_status preserve UIDs, hp, and nextItemSeq.
	for _i in range(3):
		Refit.ensure(boat, base)
		var st_rep: Dictionary = Damage.get_status(boat)
		check(_approx(float(st_rep.engineHp), 0.55) and _approx(float(st_rep.engineFactor), 0.55), "repeated get_status/ensure preserves 0.55 engine condition")
	check(Core.collect_item_uids([boat.moduleCondition]).uids == uids_before and int(boat.moduleCondition.nextItemSeq) == seq_before, "repeated get_status/ensure preserves exact itemUids and nextItemSeq")

	# Mutating returned status and tick dictionaries never leaks into canonical boat.
	var saved_boat: Dictionary = boat.duplicate(true)
	var st_obs: Dictionary = Damage.get_status(boat)
	st_obs.weaponFactors["mount0"] = 0.0
	st_obs.workByTask["engine"] = 99.0
	st_obs.suppliesByTask["engine"] = 99.0
	st_obs.events.append("mutated")
	tick_res.weaponFactors["mount0"] = 0.0
	tick_res.moduleChanges.clear()
	check(boat == saved_boat, "mutating returned status/tick dictionaries does not mutate canonical boat")

func _initialize() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	catalog = Refit.catalog()
	test_hit_geometry_and_section_fallback_without_locker_damage()
	test_armor_condition_mitigation_and_weapon_factors()
	test_disabled_engine_raw_projection_and_speed_turn_impairment()
	test_mechanical_pump_failure_and_hand_bailing()
	test_single_repair_labor_pool_conservation_and_zero_kits_no_crew()
	test_finite_stores_partial_repair_and_jury_cap()
	test_priority_choices_allocation()
	test_timestep_30_60_equivalence()
	test_legacy_without_schema_and_corrupt_owner_refusal()
	test_detached_observer_no_mutation_and_sync_ordering()
	if failures > 0:
		push_error("equipment_damage: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	print("equipment_damage: %d checks, 0 failures" % checks)
	quit(0)
