extends SceneTree
## Native headless fixture for v0.031 live equipment combat integration.
## Exercises public Battle.create and Battle.update across manual and autopilot fire,
## per-mount weapon condition/cadence/re-enable, engine speed/turnFactor parity at 30/60Hz,
## pump flooding/sinking, armor mitigation, AI role/range/station updates, certificate
## invalidation vs gradual repair, boarding capture custody, legacy parity, and corrupt fail-closed.
## Supports independent single-family staging via OS.get_cmdline_user_args() (-- --family=<id>)
## or Root-generated _initialize() call selection, with BEGIN/END family and per-phase progress markers.

const Battle = preload("res://scripts/battle.gd")
const Damage = preload("res://scripts/damage.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const EquipmentCombat = preload("res://scripts/equipment_combat.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Core = preload("res://scripts/equipment_condition.gd")
const Refit = preload("res://scripts/refit.gd")
const Layout = preload("res://scripts/mount_layout.gd")
const Tactical = preload("res://scripts/tactical_runtime.gd")
const Certification = preload("res://scripts/tactical_certification.gd")
const Roles = preload("res://scripts/tactical_role_plans.gd")
const Stations = preload("res://scripts/tactical_stations.gd")

const SELECTED_FAMILY: String = "all"
const FAMILY_ORDER: Array = ["weapons_cadence", "jury_repair", "engine_parity", "pump_and_armor", "ai_role_cert", "boarding_legacy_corrupt"]

var world: Dictionary = {}
var catalog: Dictionary = {}
var checks: int = 0
var failures: int = 0
var _loaded: bool = false

func _ensure_loaded() -> void:
	if _loaded:
		return
	ProjectSettings.set_setting("application/run/flush_stdout_on_print", true)
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	catalog = Refit.catalog()
	_loaded = true

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL equipment_combat: " + message)

func _approx(a: float, b: float, tol: float = 0.0001) -> bool:
	return absf(a - b) <= tol

func _new_phase_stats() -> Dictionary:
	return {"startedUsec": Time.get_ticks_usec(), "checksBefore": checks, "failuresBefore": failures, "ticks": 0, "rollouts": 0, "samples": 0, "aiUs": 0}

func _record_step_stats(st: Dictionary, stats: Dictionary) -> void:
	stats.ticks = int(stats.get("ticks", 0)) + 1
	var tac: Dictionary = st.get("tactical", {}) if st.get("tactical") is Dictionary else {}
	var budget: Dictionary = tac.get("budget", {}) if tac.get("budget") is Dictionary else {}
	var metrics: Dictionary = tac.get("metrics", {}) if tac.get("metrics") is Dictionary else {}
	stats.rollouts = int(stats.get("rollouts", 0)) + int(budget.get("rollouts", 0))
	stats.samples = int(stats.get("samples", 0)) + int(budget.get("samples", 0))
	stats.aiUs = int(stats.get("aiUs", 0)) + int(metrics.get("aiUs", 0))

func _begin_family(family_id: String, func_name: String) -> Dictionary:
	_ensure_loaded()
	var ctx: Dictionary = {"id": family_id, "funcName": func_name, "startedUsec": Time.get_ticks_usec(), "checksBefore": checks, "failuresBefore": failures, "ticks": 0, "rollouts": 0, "samples": 0}
	print("BEGIN family %s (%s) checks=%d failures=%d" % [family_id, func_name, checks, failures])
	return ctx

func _mark_phase(fam_ctx: Dictionary, phase_name: String, stats: Dictionary, dt: float, sim_time: float) -> void:
	var wall_ms: float = float(Time.get_ticks_usec() - int(stats.get("startedUsec", 0))) / 1000.0
	var ai_ms: float = float(int(stats.get("aiUs", 0))) / 1000.0
	var ticks: int = int(stats.get("ticks", 0))
	var rollouts: int = int(stats.get("rollouts", 0))
	var samples: int = int(stats.get("samples", 0))
	var delta_checks: int = checks - int(stats.get("checksBefore", checks))
	fam_ctx.ticks = int(fam_ctx.get("ticks", 0)) + ticks
	fam_ctx.rollouts = int(fam_ctx.get("rollouts", 0)) + rollouts
	fam_ctx.samples = int(fam_ctx.get("samples", 0)) + samples
	print("PHASE %s.%s ticks=%d dt=%.5f simTime=%.2fs wallMs=%.2f aiMs=%.2f rollouts=%d samples=%d phaseChecks=%d checks=%d failures=%d" % [str(fam_ctx.get("id", "unknown")), phase_name, ticks, dt, sim_time, wall_ms, ai_ms, rollouts, samples, delta_checks, checks, failures])

func _end_family(fam_ctx: Dictionary) -> void:
	var wall_ms: float = float(Time.get_ticks_usec() - int(fam_ctx.get("startedUsec", 0))) / 1000.0
	var fam_checks: int = checks - int(fam_ctx.get("checksBefore", 0))
	var fam_failures: int = failures - int(fam_ctx.get("failuresBefore", 0))
	print("END family %s (%s) ticks=%d rollouts=%d samples=%d wallMs=%.2f familyChecks=%d familyFailures=%d checks=%d failures=%d" % [str(fam_ctx.get("id", "unknown")), str(fam_ctx.get("funcName", "")), int(fam_ctx.get("ticks", 0)), int(fam_ctx.get("rollouts", 0)), int(fam_ctx.get("samples", 0)), wall_ms, fam_checks, fam_failures, checks, failures])

func _hull_by_id(hull_id: String) -> Dictionary:
	_ensure_loaded()
	for h in world.get("HULLS", []):
		if str(h.get("id", "")) == hull_id:
			return h.duplicate(true)
	return world.HULLS[0].duplicate(true)

func _canonical_boat(hull_id: String, identity: String, overrides: Dictionary = {}, custom_loadout: Dictionary = {}) -> Dictionary:
	var base: Dictionary = _hull_by_id(hull_id)
	var boat: Dictionary = Damage.create_ship(base, overrides)
	boat.baseSpec = base.duplicate(true)
	if not custom_loadout.is_empty():
		var norm: Dictionary = Refit.normalize(base, custom_loadout)
		check(norm.ok, "custom loadout normalizes for " + identity + " (" + str(norm.get("error", "ok")) + ")")
		boat.loadout = norm.loadout
	Refit.ensure(boat, base)
	boat.uid = identity
	var init_res: Dictionary = Records.initialize(boat, {"base": base, "loadout": boat.loadout, "catalog": catalog, "identity": identity, "knownUids": []})
	check(init_res.ok, "Records.initialize succeeded for " + identity + " (" + str(init_res.get("error", "ok")) + ")")
	return boat

func _item_at(condition: Dictionary, location: String) -> Dictionary:
	for uid in condition.get("items", {}).keys():
		var item: Dictionary = condition.items[uid]
		if str(item.get("location", "")) == location:
			return item
	return {}

func test_per_mount_disable_and_damaged_cadence_in_public_battle() -> void:
	var fam: Dictionary = _begin_family("weapons_cadence", "test_per_mount_disable_and_damaged_cadence_in_public_battle")
	# 1. Canonical 2-mount boat (tin_skiff size 14: mount0 bow angle 0.0 arc TAU, mount1 aft angle PI arc TAU):
	#    mount0 disabled by actual nonlethal combat hits stops firing in manual & autopilot while mount1
	#    continues firing with exact ammo debit, events, independent cooldowns, and persisted hull/store damage.
	var phase_auto: Dictionary = _new_phase_stats()
	var fit: Dictionary = {"weapons": ["stock_primary", "rapid_gun"], "engine": "stock_engine", "armor": "stock_armor"}
	var p_auto: Dictionary = _canonical_boat("tin_skiff", "combat-auto-dual", {"ammo": 80.0, "supplies": 12.0}, fit)
	var e_auto: Dictionary = _canonical_boat("tin_skiff", "combat-auto-target", {"ammo": 0.0, "supplies": 0.0})
	e_auto.spec.speed = 0.0
	var pts: Array = Layout.hardpoints(p_auto.baseSpec)
	check(pts.size() == 2 and str(pts[0].id) == "mount0" and str(pts[1].id) == "mount1", "tin_skiff Layout.hardpoints provides 2 sockets (mount0 bow, mount1 aft)")
	check(_approx(float(pts[0].angle), 0.0) and _approx(float(pts[1].angle), PI) and _approx(float(pts[1].arc), TAU), "aft mount1 has angle PI and arc TAU")

	var st_auto: Dictionary = Battle.create({"fleet": [p_auto], "enemyFleet": [e_auto], "islands": [], "seed": 101})
	var ship_a: Dictionary = st_auto.ships[0]
	var target_a: Dictionary = st_auto.ships[1]
	# Orient ship_a with angle PI (bow West, aft mount1 facing East at angle PI+PI=0) toward target_a at (820, 860).
	ship_a.x = 600.0; ship_a.y = 850.0; ship_a.angle = PI
	target_a.x = 820.0; target_a.y = 860.0
	check(Battle.issue_order(st_auto, [str(ship_a.id)], "hold"), "autopilot dual-mount boat accepts hold order")

	# Disable mount0 through 2 controlled nonlethal bow hits (54.0 shell -> 0.45 mount0 loss each -> 0.10 HP <= 0.20)
	# without resetting ship_a.hp, fire, water, breaches, or wounded.
	var hit_rng := RandomNumberGenerator.new(); hit_rng.seed = 77
	var world_m0: Vector2 = Vector2(float(ship_a.x), float(ship_a.y)) + Vector2(float(pts[0].x), float(pts[0].y)).rotated(float(ship_a.angle))
	for _i in range(2):
		Damage.apply_hit(ship_a, {"damage": 54.0, "kind": "shell", "penetration": 10.0, "impactX": world_m0.x, "impactY": world_m0.y}, hit_rng)
	var m0_item: Dictionary = _item_at(ship_a.moduleCondition, "mount0")
	var m1_item: Dictionary = _item_at(ship_a.moduleCondition, "mount1")
	var arm_item: Dictionary = _item_at(ship_a.moduleCondition, "armor")
	check(float(m0_item.hp) <= Core.DISABLE_HP and str(m0_item.status) == "disabled", "mount0 disabled at <=0.20 HP by real nonlethal bow hits (got hp=%.3f, status=%s)" % [float(m0_item.hp), str(m0_item.status)])
	check(_approx(float(m1_item.hp), 1.0) and str(m1_item.status) == "ok", "aft mount1 remains intact at 1.0 HP")
	check(float(ship_a.hp) < float(ship_a.maxHp) and float(ship_a.hp) > 90.0 and float(arm_item.hp) < 1.0, "hull HP (%.1f/%.1f) and armor condition (%.3f) persist without reset or free heal" % [float(ship_a.hp), float(ship_a.maxHp), float(arm_item.hp)])

	var m0_shots_auto: int = 0
	var m1_shots_auto: int = 0
	var ammo_before_auto: float = float(ship_a.ammo)
	var supplies_before_auto: float = float(ship_a.supplies)
	for _tick in range(60):
		Battle.update(st_auto, 1.0 / 30.0)
		_record_step_stats(st_auto, phase_auto)
		for ev in Battle.pop_events(st_auto):
			if str(ev.get("kind", "")) == "fire" and str(ev.get("sourceId", "")) == str(ship_a.id):
				if str(ev.get("mountId", "")) == "mount0":
					m0_shots_auto += 1
				elif str(ev.get("mountId", "")) == "mount1":
					m1_shots_auto += 1
	check(m0_shots_auto == 0 and m1_shots_auto >= 3, "autopilot Battle.update fires working aft mount1 (%d shots) and never fires disabled mount0 (%d shots)" % [m1_shots_auto, m0_shots_auto])
	check(_approx(ammo_before_auto - float(ship_a.ammo), float(m1_shots_auto)), "autopilot ammo debit equals exact mount1 shots emitted")
	check(float(ship_a.hp) < float(ship_a.maxHp) and float(ship_a.supplies) < supplies_before_auto, "damaged hull and finite repair supply debit persist across Battle.update without refill")
	check(_approx(float(ship_a.weaponCooldowns[0]), 0.0) and float(ship_a.weaponCooldowns[1]) >= 0.0, "disabled mount0 cooldown stays 0.0 while mount1 tracks independent cooldown")
	check(not Core._foreign(ship_a), "ship.spec and weaponMounts remain free of foreign condition metadata")
	_mark_phase(fam, "autopilot_dual_mount", phase_auto, 1.0 / 30.0, float(st_auto.time))

	# Manual flagship fire with mount0 disabled and aft mount1 bearing directly on astern target.
	var phase_man: Dictionary = _new_phase_stats()
	var p_man: Dictionary = _canonical_boat("tin_skiff", "combat-manual-dual", {"ammo": 80.0, "supplies": 0.0}, fit)
	var e_man: Dictionary = _canonical_boat("tin_skiff", "combat-manual-target", {"ammo": 0.0, "supplies": 0.0})
	e_man.spec.speed = 0.0
	var st_man: Dictionary = Battle.create({"fleet": [p_man], "enemyFleet": [e_man], "islands": [], "seed": 102})
	Battle.set_autopilot(st_man, false)
	var ship_m: Dictionary = st_man.ships[0]
	var target_m: Dictionary = st_man.ships[1]
	ship_m.x = 600.0; ship_m.y = 850.0; ship_m.angle = 0.0
	target_m.x = 380.0; target_m.y = 850.0
	var m0_uid_m: String = str(_item_at(ship_m.moduleCondition, "mount0").itemUid)
	check(Core.apply_component_damage(ship_m.moduleCondition, {"itemUid": m0_uid_m, "loss": 0.85, "cause": "Direct hit on mount0"}).ok, "manual flagship mount0 disabled at 0.15 HP")
	Records.publish(ship_m)
	var ammo_before_man: float = float(ship_m.ammo)
	var m0_shots_man: int = 0
	var m1_shots_man: int = 0
	for _tick in range(30):
		Battle.update(st_man, 1.0 / 30.0, {"fire": true, "aimX": target_m.x, "aimY": target_m.y})
		_record_step_stats(st_man, phase_man)
		for ev in Battle.pop_events(st_man):
			if str(ev.get("kind", "")) == "fire" and str(ev.get("sourceId", "")) == str(ship_m.id):
				if str(ev.get("mountId", "")) == "mount0":
					m0_shots_man += 1
				elif str(ev.get("mountId", "")) == "mount1":
					m1_shots_man += 1
	var tac_man: Dictionary = Battle.tactical_status(st_man, str(ship_m.id))
	check(m0_shots_man == 0 and m1_shots_man >= 3, "manual Battle.update fires aft mount1 (%d) and never fires disabled mount0 (%d)" % [m1_shots_man, m0_shots_man])
	check(_approx(ammo_before_man - float(ship_m.ammo), float(m1_shots_man)), "manual ammo debit matches exact mount1 shots emitted")
	check(str(tac_man.get("weapons", {}).get("mount0", "")) == "Weapon disabled", "manual tactical_status reports Weapon disabled for mount0")
	_mark_phase(fam, "manual_dual_mount", phase_man, 1.0 / 30.0, float(st_man.time))

	# 2. Damaged (0.50 HP) weapon mount scales reload cadence once without double-scaling projectile damage.
	var phase_half: Dictionary = _new_phase_stats()
	var p_half: Dictionary = _canonical_boat("tin_skiff", "combat-half-gun", {"ammo": 80.0, "supplies": 0.0})
	var e_half: Dictionary = _canonical_boat("tin_skiff", "combat-half-target", {"ammo": 0.0, "supplies": 0.0})
	e_half.spec.speed = 0.0
	var m0_half_uid: String = str(_item_at(p_half.moduleCondition, "mount0").itemUid)
	check(Core.apply_component_damage(p_half.moduleCondition, {"itemUid": m0_half_uid, "loss": 0.50, "cause": "Bent barrel"}).ok, "mount0 damaged to 0.50 HP")
	Records.publish(p_half)
	var st_half: Dictionary = Battle.create({"fleet": [p_half], "enemyFleet": [e_half], "islands": [], "seed": 103})
	Battle.set_autopilot(st_half, false)
	var ship_h: Dictionary = st_half.ships[0]
	var target_h: Dictionary = st_half.ships[1]
	ship_h.x = 600.0; ship_h.y = 850.0; ship_h.angle = 0.0
	target_h.x = 800.0; target_h.y = 850.0
	var base_rate: float = float(ship_h.spec.weaponMounts[0].fireRate)
	var base_dmg: float = float(ship_h.spec.weaponMounts[0].damage)
	Battle.update(st_half, 1.0 / 30.0, {"fire": true, "aimX": target_h.x, "aimY": target_h.y})
	_record_step_stats(st_half, phase_half)
	check(st_half.projectiles.size() == 1, "damaged 0.50 mount emits projectile on trigger")
	if st_half.projectiles.size() == 1:
		var proj: Dictionary = st_half.projectiles[0]
		check(_approx(float(proj.damage), base_dmg), "projectile damage is unscaled baseDamage (%.2f vs %.2f), never double-scaled" % [float(proj.damage), base_dmg])
	var expected_cd: float = 1.0 / (base_rate * 0.50)
	check(_approx(float(ship_h.weaponCooldowns[0]), expected_cd, 0.001), "0.50 mount reload cooldown doubles from %.4f to %.4f (got %.4f)" % [1.0 / base_rate, expected_cd, float(ship_h.weaponCooldowns[0])])
	_mark_phase(fam, "damaged_cadence_single_shot", phase_half, 1.0 / 30.0, float(st_half.time))
	_end_family(fam)

func test_jury_repair_reenable_threshold_and_priority_in_battle() -> void:
	var fam: Dictionary = _begin_family("jury_repair", "test_jury_repair_reenable_threshold_and_priority_in_battle")
	var phase_reenable: Dictionary = _new_phase_stats()
	var p_rep: Dictionary = _canonical_boat("tin_skiff", "combat-jury-reenable", {"ammo": 80.0, "supplies": 25.0, "policy": "repair"})
	var e_rep: Dictionary = _canonical_boat("tin_skiff", "combat-jury-target", {"ammo": 0.0, "supplies": 0.0})
	e_rep.spec.speed = 0.0
	# Disable mount0 at 0.15 HP (<= 0.20 DISABLE_HP) and damage engine to 0.45 HP, then prioritize weapons repair.
	var m0_uid: String = str(_item_at(p_rep.moduleCondition, "mount0").itemUid)
	var eng_uid: String = str(_item_at(p_rep.moduleCondition, "engine").itemUid)
	check(Core.apply_component_damage(p_rep.moduleCondition, {"itemUid": m0_uid, "loss": 0.85, "cause": "Mount jammed"}).ok, "mount0 disabled at 0.15 HP (<= 0.20 DISABLE_HP)")
	check(str(_item_at(p_rep.moduleCondition, "mount0").status) == "disabled", "mount0 status is disabled at 0.15 HP")
	check(Core.apply_component_damage(p_rep.moduleCondition, {"itemUid": eng_uid, "loss": 0.55, "cause": "Engine worn"}).ok, "engine damaged to 0.45 HP")
	Records.publish(p_rep)
	check(Damage.set_repair_priority(p_rep, "weapons") == "weapons", "set_repair_priority selects weapons first")

	var st: Dictionary = Battle.create({"fleet": [p_rep], "enemyFleet": [e_rep], "islands": [], "seed": 202})
	Battle.set_autopilot(st, false)
	var ship: Dictionary = st.ships[0]
	var target: Dictionary = st.ships[1]
	ship.x = 600.0; ship.y = 850.0; ship.angle = 0.0
	target.x = 800.0; target.y = 850.0

	var shots_below_30: int = 0
	var shots_after_30: int = 0
	var observed_hysteresis_disabled: bool = false
	var crossed_30: bool = false
	for _tick in range(180):
		var hp_before: float = float(_item_at(ship.moduleCondition, "mount0").hp)
		Battle.update(st, 1.0 / 30.0, {"fire": true, "aimX": target.x, "aimY": target.y})
		_record_step_stats(st, phase_reenable)
		var m0_now: Dictionary = _item_at(ship.moduleCondition, "mount0")
		var hp_after: float = float(m0_now.hp)
		if hp_after > Core.DISABLE_HP + 0.01 and hp_after < Core.REENABLE_HP - 0.005:
			if str(m0_now.status) == "disabled":
				observed_hysteresis_disabled = true
		if hp_after >= Core.REENABLE_HP - 0.0001 and str(m0_now.status) == "damaged":
			crossed_30 = true
		for ev in Battle.pop_events(st):
			if str(ev.get("kind", "")) == "fire" and str(ev.get("sourceId", "")) == str(ship.id):
				if hp_after < Core.REENABLE_HP - 0.0001 and hp_before < Core.REENABLE_HP - 0.0001:
					shots_below_30 += 1
				else:
					shots_after_30 += 1
	check(observed_hysteresis_disabled, "prior disabled mount0 remains disabled across hysteresis band (0.20 < hp < 0.30, including ~0.22 HP)")
	check(shots_below_30 == 0, "disabled weapon emits zero shots while jury repair is below 0.30 HP")
	check(crossed_30 and shots_after_30 >= 2, "weapon re-enables across 0.30 HP and resumes firing in Battle.update (%d shots)" % shots_after_30)
	_mark_phase(fam, "hysteresis_and_reenable", phase_reenable, 1.0 / 30.0, float(st.time))

	# Continue ticking repair in 3 bounded 150-tick sub-phases (450 ticks total) to verify 0.75 JURY_CAP ceiling at sea.
	for chunk_idx in range(3):
		var phase_cap: Dictionary = _new_phase_stats()
		for _tick in range(150):
			Battle.update(st, 1.0 / 30.0, {})
			_record_step_stats(st, phase_cap)
			Battle.pop_events(st)
		if chunk_idx == 2:
			var final_m0_hp: float = float(_item_at(ship.moduleCondition, "mount0").hp)
			var final_eng_hp: float = float(_item_at(ship.moduleCondition, "engine").hp)
			check(_approx(final_m0_hp, Core.JURY_CAP, 0.001) and _approx(final_eng_hp, Core.JURY_CAP, 0.001), "combat jury repair caps mount0 (%.3f) and engine (%.3f) at 0.75 JURY_CAP" % [final_m0_hp, final_eng_hp])
			check(float(ship.supplies) < 25.0, "combat jury repair spends finite ship supplies")
		_mark_phase(fam, "jury_cap_075_part%d" % (chunk_idx + 1), phase_cap, 1.0 / 30.0, float(st.time))
	_end_family(fam)

func _run_engine_parity_for_dts(dts: Array, family_id: String, func_name: String) -> void:
	var fam: Dictionary = _begin_family(family_id, func_name)
	for dt_val in dts:
		var dt: float = float(dt_val)
		var hz: int = roundi(1.0 / dt)
		var phase_man: Dictionary = _new_phase_stats()
		var p_dis: Dictionary = _canonical_boat("tin_skiff", "combat-eng-dis-" + str(hz), {"supplies": 0.0})
		var p_half: Dictionary = _canonical_boat("tin_skiff", "combat-eng-half-" + str(hz), {"supplies": 0.0})
		var p_full: Dictionary = _canonical_boat("tin_skiff", "combat-eng-full-" + str(hz), {"supplies": 0.0})
		var e_dummy: Dictionary = _canonical_boat("tin_skiff", "combat-eng-dummy-" + str(hz), {"ammo": 0.0, "supplies": 0.0})
		e_dummy.spec.speed = 0.0

		check(Core.apply_component_damage(p_dis.moduleCondition, {"itemUid": str(_item_at(p_dis.moduleCondition, "engine").itemUid), "loss": 0.85, "cause": "Cracked block"}).ok, "engine disabled at 0.15")
		check(Core.apply_component_damage(p_half.moduleCondition, {"itemUid": str(_item_at(p_half.moduleCondition, "engine").itemUid), "loss": 0.55, "cause": "Scored piston"}).ok, "engine damaged to 0.45")
		Records.publish(p_dis)
		Records.publish(p_half)

		# Verify manual turning and movement for disabled vs 0.45 vs 1.0 engine.
		var travel: Dictionary = {}
		var turned: Dictionary = {}
		for pair in [["dis", p_dis], ["half", p_half], ["full", p_full]]:
			var label: String = pair[0]
			var boat: Dictionary = pair[1]
			var st_m: Dictionary = Battle.create({"fleet": [boat], "enemyFleet": [e_dummy.duplicate(true)], "islands": [], "seed": 303})
			Battle.set_autopilot(st_m, false)
			var s: Dictionary = st_m.ships[0]
			s.x = 500.0; s.y = 850.0; s.angle = 0.0
			st_m.ships[1].x = 1800.0; st_m.ships[1].y = 850.0
			var steps: int = roundi(1.0 / dt)
			for _t in range(steps):
				Battle.update(st_m, dt, {"forward": true, "right": true})
				_record_step_stats(st_m, phase_man)
				Battle.pop_events(st_m)
			travel[label] = Vector2(float(s.x) - 500.0, float(s.y) - 850.0).length()
			turned[label] = absf(float(s.angle))
		check(_approx(float(travel["dis"]), 0.0, 0.001) and _approx(float(turned["dis"]), 0.0, 0.001), "disabled engine stops speed and turning in Battle.update dt=" + str(dt))
		check(float(travel["half"]) > 10.0 and float(travel["half"]) < float(travel["full"]) * 0.65, "0.45 engine reduces distance traveled vs full engine dt=" + str(dt))
		check(float(turned["half"]) > 0.20 and float(turned["half"]) < float(turned["full"]) * 0.65, "0.45 engine reduces turn angle vs full engine dt=" + str(dt))
		_mark_phase(fam, "manual_turn_%dhz" % hz, phase_man, dt, 3.0)

		# Verify autopilot Certification.motion matches Battle.update with partial engine damage + active repair at both 30Hz and 60Hz.
		var phase_cert: Dictionary = _new_phase_stats()
		var p_cert: Dictionary = _canonical_boat("tin_skiff", "combat-eng-cert-" + str(hz), {"supplies": 15.0, "policy": "repair"})
		check(Core.apply_component_damage(p_cert.moduleCondition, {"itemUid": str(_item_at(p_cert.moduleCondition, "engine").itemUid), "loss": 0.50, "cause": "Wear"}).ok, "cert engine at 0.50")
		Records.publish(p_cert)
		var st_c: Dictionary = Battle.create({"fleet": [p_cert], "enemyFleet": [e_dummy.duplicate(true)], "islands": [], "seed": 304})
		var sc: Dictionary = st_c.ships[0]
		sc.x = 500.0; sc.y = 850.0; sc.angle = 0.0
		st_c.ships[1].x = 1750.0; st_c.ships[1].y = 1200.0
		check(Battle.issue_order(st_c, [str(sc.id)], "move", {"x": 950.0, "y": 1050.0}), "autopilot curved move order accepted dt=" + str(dt))
		var valid_frames: int = 0
		var max_cap_err: float = 0.0
		for _t in range(roundi(0.5 / dt)):
			Battle.update(st_c, dt)
			_record_step_stats(st_c, phase_cert)
			Battle.pop_events(st_c)
			var intent: Dictionary = st_c.tactical.intents.get(str(sc.id), {})
			var cur: Dictionary = Certification.current(st_c, sc, intent, dt)
			if bool(cur.get("ok", false)):
				valid_frames += 1
				var rec: Dictionary = cur.record
				var s_dt: float = float(rec.get("sampleDt", 1.0 / 30.0))
				var idx: int = clampi(roundi((float(st_c.time) - float(rec.certificate.checkedAt)) / s_dt), 0, rec.capabilities.size() - 1)
				var exp_cap: Dictionary = rec.capabilities[idx]
				var act_cap: Dictionary = Certification.capability(sc, float(exp_cap.get("equipMask", NAN)))
				for k in exp_cap:
					max_cap_err = maxf(max_cap_err, absf(float(act_cap[k]) - float(exp_cap[k])))
		check(valid_frames >= roundi(0.3 / dt) and max_cap_err <= 0.0001, "gradual engine repair and curved turnFactor rollout keep certificate valid without drift (valid=%d, err=%.6f) dt=%s" % [valid_frames, max_cap_err, str(dt)])
		_mark_phase(fam, "autopilot_cert_%dhz" % hz, phase_cert, dt, float(st_c.time))
	_end_family(fam)

func test_engine_turn_factor_and_30_60_parity() -> void:
	_run_engine_parity_for_dts([1.0 / 30.0, 1.0 / 60.0], "engine_parity", "test_engine_turn_factor_and_30_60_parity")

func test_engine_turn_factor_30hz_only() -> void:
	_run_engine_parity_for_dts([1.0 / 30.0], "engine_parity_30", "test_engine_turn_factor_30hz_only")

func test_engine_turn_factor_60hz_only() -> void:
	_run_engine_parity_for_dts([1.0 / 60.0], "engine_parity_60", "test_engine_turn_factor_60hz_only")

func test_pump_flooding_sink_and_armor_mitigation_in_battle() -> void:
	var fam: Dictionary = _begin_family("pump_and_armor", "test_pump_flooding_sink_and_armor_mitigation_in_battle")
	# 1. Integral pump disable increases net flooding in Battle.update until breached hull sinks.
	#    Read effective flood capacity, crew handBailing, and hand+motor pump bailing from Damage.get_status,
	#    and select waterline breach inflow strictly between handBailing and hand+motor pump across the trace.
	var phase_pumps_1: Dictionary = _new_phase_stats()
	var p_good_pump: Dictionary = _canonical_boat("tin_skiff", "combat-pump-ok", {"water": 1.0, "supplies": 0.0, "policy": "bail"})
	var p_dead_pump: Dictionary = _canonical_boat("tin_skiff", "combat-pump-dead", {"water": 1.0, "supplies": 0.0, "policy": "bail"})
	var pump_uid: String = str(_item_at(p_dead_pump.moduleCondition, "pumps").itemUid)
	check(Core.apply_component_damage(p_dead_pump.moduleCondition, {"itemUid": pump_uid, "loss": 0.85, "cause": "Bilge torpedo"}).ok, "integral pumps disabled at 0.15 HP")
	Records.publish(p_dead_pump)
	var st_rates_ok: Dictionary = Damage.get_status(p_good_pump)
	var st_rates_dead: Dictionary = Damage.get_status(p_dead_pump)
	var eff_cap: float = float(p_good_pump.capacity)
	var hand_bail: float = float(st_rates_ok.handBailing)
	var full_bail: float = float(st_rates_ok.bailing)
	var dead_bail: float = float(st_rates_dead.bailing)
	var start_water: float = eff_cap - 12.0
	var target_inflow: float = hand_bail + (full_bail - hand_bail) * 0.68
	var breach_area: float = roundf(target_inflow / (float(Damage.CONSTANTS.inflowPerArea) * (1.0 + (start_water / eff_cap) * 0.45)))
	for b_ship in [p_good_pump, p_dead_pump]:
		b_ship.water = start_water
		b_ship.breaches = [{"area": breach_area, "section": "waterline"}]
	var st_init_ok: Dictionary = Damage.get_status(p_good_pump)
	var e_hold: Dictionary = _canonical_boat("tin_skiff", "combat-pump-enemy", {"ammo": 0.0, "supplies": 0.0})
	e_hold.spec.speed = 0.0

	var st_ok: Dictionary = Battle.create({"fleet": [p_good_pump], "enemyFleet": [e_hold.duplicate(true)], "islands": [], "seed": 401})
	var st_dead: Dictionary = Battle.create({"fleet": [p_dead_pump], "enemyFleet": [e_hold.duplicate(true)], "islands": [], "seed": 401})
	st_ok.ships[1].x = 1800.0; st_dead.ships[1].x = 1800.0
	var sink_event_seen: bool = false
	for _t in range(90):
		Battle.update(st_ok, 1.0 / 30.0)
		_record_step_stats(st_ok, phase_pumps_1)
		Battle.pop_events(st_ok)
		Battle.update(st_dead, 1.0 / 30.0)
		_record_step_stats(st_dead, phase_pumps_1)
		for ev in Battle.pop_events(st_dead):
			if str(ev.get("kind", "")) == "sink" and str(ev.get("targetId", "")) == str(st_dead.ships[0].id):
				sink_event_seen = true
	_mark_phase(fam, "integral_pump_flood_sink_part1", phase_pumps_1, 1.0 / 30.0, float(st_ok.time))

	var phase_pumps_2: Dictionary = _new_phase_stats()
	for _t in range(90):
		Battle.update(st_ok, 1.0 / 30.0)
		_record_step_stats(st_ok, phase_pumps_2)
		Battle.pop_events(st_ok)
		Battle.update(st_dead, 1.0 / 30.0)
		_record_step_stats(st_dead, phase_pumps_2)
		for ev in Battle.pop_events(st_dead):
			if str(ev.get("kind", "")) == "sink" and str(ev.get("targetId", "")) == str(st_dead.ships[0].id):
				sink_event_seen = true
	var st_end_ok: Dictionary = Damage.get_status(st_ok.ships[0])
	var inflow_bounded: bool = float(st_init_ok.inflow) > hand_bail and float(st_init_ok.inflow) < full_bail and float(st_end_ok.inflow) > float(st_end_ok.handBailing) and float(st_end_ok.inflow) < float(st_end_ok.bailing) and _approx(dead_bail, hand_bail)
	check(not bool(st_ok.ships[0].sunk) and float(st_ok.ships[0].water) < start_water - 8.0 and inflow_bounded, "boat with working integral pumps keeps inflow (%.2f..%.2f L/s) strictly between handBailing (%.2f) and hand+pump (%.2f) and stays afloat (water=%.2f/%.1f)" % [float(st_end_ok.inflow), float(st_init_ok.inflow), hand_bail, full_bail, float(st_ok.ships[0].water), eff_cap])
	check(bool(st_dead.ships[0].sunk) and sink_event_seen and st_dead.wrecks.size() == 1, "boat with disabled integral pumps floods to capacity and sinks in Battle.update with sink event and wreck")
	_mark_phase(fam, "integral_pump_flood_sink_part2", phase_pumps_2, 1.0 / 30.0, float(st_ok.time))

	# 2. Armor condition damage reduces effectiveArmor mitigation on live projectile hits in Battle.update.
	#    ash_corvette has size 21 (>=20.0 -> 3 hardpoints: mount0, mount1, mount2).
	var phase_armor: Dictionary = _new_phase_stats()
	var fit_arm: Dictionary = {"weapons": ["stock_primary", "rapid_gun", ""], "engine": "stock_engine", "armor": "naval_plating"}
	var p_arm_ok: Dictionary = _canonical_boat("ash_corvette", "combat-armor-ok", {"ammo": 0.0, "supplies": 0.0}, fit_arm)
	var p_arm_bad: Dictionary = _canonical_boat("ash_corvette", "combat-armor-bad", {"ammo": 0.0, "supplies": 0.0}, fit_arm)
	var arm_uid: String = str(_item_at(p_arm_bad.moduleCondition, "armor").itemUid)
	check(Core.apply_component_damage(p_arm_bad.moduleCondition, {"itemUid": arm_uid, "loss": 0.85, "cause": "Shattered armor"}).ok, "armor disabled at 0.15 HP")
	Records.publish(p_arm_bad)
	var st_a1: Dictionary = Battle.create({"fleet": [p_arm_ok], "enemyFleet": [e_hold.duplicate(true)], "islands": [], "seed": 402})
	var st_a2: Dictionary = Battle.create({"fleet": [p_arm_bad], "enemyFleet": [e_hold.duplicate(true)], "islands": [], "seed": 402})
	for st_x in [st_a1, st_a2]:
		var s: Dictionary = st_x.ships[0]
		s.x = 600.0; s.y = 850.0; s.angle = 0.0
		st_x.projectiles.append({"x": 575.0, "y": 850.0, "px": 575.0, "py": 850.0, "vx": 1500.0, "vy": 0.0, "team": "enemy", "damage": 45.0, "penetration": 2.0, "kind": "shell", "life": 1.0, "owner": str(st_x.ships[1].id), "radius": 3.0})
		Battle.update(st_x, 1.0 / 30.0)
		_record_step_stats(st_x, phase_armor)
		Battle.pop_events(st_x)
	check(float(st_a2.ships[0].hp) < float(st_a1.ships[0].hp) - 3.0, "disabled armor suffers greater hull HP loss from live projectile impact (ok=%.2f vs disabled=%.2f)" % [float(st_a1.ships[0].hp), float(st_a2.ships[0].hp)])
	_mark_phase(fam, "armor_mitigation_impact", phase_armor, 1.0 / 30.0, float(st_a1.time))
	_end_family(fam)

func test_ai_role_range_station_and_certificate_invalidation() -> void:
	var fam: Dictionary = _begin_family("ai_role_cert", "test_ai_role_range_station_and_certificate_invalidation")
	# Striker (reed_stinger size 17: 2 hardpoints) with fixed torpedo (mount0, range 480, weighted DPS 38*0.65*1.8=44.46)
	# + rapid gun (mount1, range 420, base DPS 11*4.0=44.0). Pre-damage mount1 to 0.22 HP (feasible working window
	# 0.20 < hp <= 44.46/(4*44.0)=0.2526136) so intact mount0 covers >=80% weighted DPS (useful_range 480.0) while
	# mount1 remains working ("damaged"), then transition 480.0 -> 420.0 when bow hits disable mount0.
	var phase_init: Dictionary = _new_phase_stats()
	var fit_str: Dictionary = {"weapons": ["light_torpedo", "rapid_gun"], "engine": "stock_engine", "armor": "stock_armor"}
	var p_str: Dictionary = _canonical_boat("reed_stinger", "combat-striker-role", {"ammo": 60.0, "supplies": 15.0, "policy": "repair"}, fit_str)
	var m1_str_uid: String = str(_item_at(p_str.moduleCondition, "mount1").itemUid)
	Core.apply_component_damage(p_str.moduleCondition, {"itemUid": m1_str_uid, "loss": 0.78, "cause": "Scored barrel"})
	Records.publish(p_str)
	var e_str: Dictionary = _canonical_boat("ash_corvette", "combat-striker-target", {"ammo": 0.0, "supplies": 0.0})
	e_str.spec.speed = 0.0
	var st: Dictionary = Battle.create({"fleet": [p_str], "enemyFleet": [e_str], "islands": [], "seed": 505})
	var ship: Dictionary = st.ships[0]
	var enemy: Dictionary = st.ships[1]
	ship.x = 600.0; ship.y = 850.0; ship.angle = 0.0
	enemy.x = 1150.0; enemy.y = 850.0
	check(Battle.issue_order(st, [str(ship.id)], "attack", {"shipId": str(enemy.id)}), "striker accepts attack order on target")

	Battle.update(st, 1.0 / 30.0)
	_record_step_stats(st, phase_init)
	Battle.pop_events(st)
	var view_before: Dictionary = Tactical.view(st, "player", [str(ship.id)])
	var own_before: Dictionary = Roles.ships_by_id(view_before)[str(ship.id)]
	var m1_before: Dictionary = _item_at(ship.moduleCondition, "mount1")
	check(Roles.infer_role(view_before, own_before) == "striker", "intact fixed torpedo tube infers striker role")
	check(str(m1_before.status) == "damaged" and float(m1_before.hp) > Core.DISABLE_HP and _approx(Roles.useful_range(view_before, own_before), 480.0), "intact torpedo striker with working 0.22 HP rapid_gun has useful_range 480.0 (got %.1f, mount1 hp=%.3f)" % [Roles.useful_range(view_before, own_before), float(m1_before.hp)])
	var old_intent: Dictionary = st.tactical.intents.get(str(ship.id), {}).duplicate(true)
	check(not old_intent.is_empty() and bool(Certification.current(st, ship, old_intent, 1.0 / 30.0).get("ok", false)), "initial striker certificate is valid")
	_mark_phase(fam, "initial_striker_cert", phase_init, 1.0 / 30.0, float(st.time))

	# Incoming nonlethal bow shells disable mount0 (light_torpedo) in a single live Battle.update step without healing/reset.
	var phase_hit: Dictionary = _new_phase_stats()
	for _hit_i in range(4):
		st.projectiles.append({"x": float(ship.x) + 18.0, "y": float(ship.y), "px": float(ship.x) + 18.0, "py": float(ship.y), "vx": -1500.0, "vy": 0.0, "team": "enemy", "damage": 36.0, "penetration": 10.0, "kind": "shell", "section": "bow", "life": 1.0, "owner": str(enemy.id), "radius": 3.0})
	Battle.update(st, 1.0 / 30.0)
	_record_step_stats(st, phase_hit)
	Battle.pop_events(st)
	var m0_after: Dictionary = _item_at(ship.moduleCondition, "mount0")
	check(float(m0_after.hp) <= Core.DISABLE_HP and str(m0_after.status) == "disabled", "bow hits in Battle.update disable mount0 torpedo tube (hp=%.3f)" % float(m0_after.hp))
	check(float(ship.hp) < float(ship.maxHp) and float(ship.hp) > 120.0, "striker hull damage persists without reset (hp=%.1f/%.1f)" % [float(ship.hp), float(ship.maxHp)])

	# Old certificate must immediately invalidate with "Damage or capability changed; reassessing".
	var invalidated: Dictionary = Certification.current(st, ship, old_intent, 1.0 / 30.0)
	check(not bool(invalidated.get("ok", true)) and str(invalidated.get("reason", "")) == "Damage or capability changed; reassessing", "disabling mount0 invalidates prior certificate (reason=%s)" % str(invalidated.get("reason", "")))
	_mark_phase(fam, "bow_hit_disable_invalidation", phase_hit, 1.0 / 30.0, float(st.time))

	# Next ticks update AI observation, role (striker -> skirmisher), useful_range (480 -> 420), and candidate fireMountIds (mount1 only).
	var phase_replan: Dictionary = _new_phase_stats()
	Battle.update(st, 1.0 / 30.0)
	_record_step_stats(st, phase_replan)
	Battle.pop_events(st)
	Battle.update(st, 1.0 / 30.0)
	_record_step_stats(st, phase_replan)
	Battle.pop_events(st)
	var view_after: Dictionary = Tactical.view(st, "player", [str(ship.id)])
	var own_after: Dictionary = Roles.ships_by_id(view_after)[str(ship.id)]
	var ctx_after: Dictionary = Roles.ships_by_id(view_after)
	var dec_after: Dictionary = Roles.decide(view_after, own_after, {}, ctx_after)
	var cands_after: Array = Stations.candidates(view_after, own_after, dec_after, ctx_after)
	check(Roles.infer_role(view_after, own_after) == "skirmisher", "disabled fixed torpedo tube transitions role from striker to skirmisher (got %s)" % Roles.infer_role(view_after, own_after))
	check(_approx(Roles.useful_range(view_after, own_after), 420.0), "disabled torpedo drops useful_range from 480.0 to working gun 420.0 (got %.1f)" % Roles.useful_range(view_after, own_after))
	check(not cands_after.is_empty() and cands_after[0].get("fireMountIds", []) == ["mount1"], "station candidates assign only working mount1 (got %s)" % str(cands_after[0].get("fireMountIds", [])))

	# Changing repairPriority alone (with hull/water/fire unchanged) invalidates current certificate immediately.
	var active_intent: Dictionary = st.tactical.intents.get(str(ship.id), {}).duplicate(true)
	check(bool(Certification.current(st, ship, active_intent, 1.0 / 30.0).get("ok", false)), "re-certified skirmisher intent is valid before priority change")
	check(Damage.set_repair_priority(ship, "weapons") == "weapons", "set_repair_priority changes to weapons")
	var after_prio: Dictionary = Certification.current(st, ship, active_intent, 1.0 / 30.0)
	check(not bool(after_prio.get("ok", true)) and str(after_prio.get("reason", "")) == "Damage or capability changed; reassessing", "repairPriority transition alone invalidates old certificate immediately")
	_mark_phase(fam, "skirmisher_replan_and_priority", phase_replan, 1.0 / 30.0, float(st.time))
	_end_family(fam)

func test_boarding_capture_custody_legacy_and_corrupt_fail_closed() -> void:
	var fam: Dictionary = _begin_family("boarding_legacy_corrupt", "test_boarding_capture_custody_legacy_and_corrupt_fail_closed")
	# 1. Capturing a damaged canonical enemy boat preserves birthNamespace, itemUids, causes, and locker spares.
	var phase_board: Dictionary = _new_phase_stats()
	var p_board: Dictionary = _canonical_boat("ash_corvette", "combat-boarder-p", {"crew": 16.0, "boarders": 8, "ammo": 0.0, "supplies": 10.0})
	var e_prize: Dictionary = _canonical_boat("tin_skiff", "enemy-prize-canonical-7", {"crew": 2.0, "wounded": 1.0, "ammo": 0.0, "supplies": 0.0, "refitLocker": {"rapid_gun": 1}})
	var prize_eng_uid: String = str(_item_at(e_prize.moduleCondition, "engine").itemUid)
	var prize_m0_uid: String = str(_item_at(e_prize.moduleCondition, "mount0").itemUid)
	check(Core.apply_component_damage(e_prize.moduleCondition, {"itemUid": prize_eng_uid, "loss": 0.85, "cause": "Boarding cripple"}).ok, "prize engine disabled at 0.15 HP")
	check(Core.apply_component_damage(e_prize.moduleCondition, {"itemUid": prize_m0_uid, "loss": 0.40, "cause": "Splintered mount"}).ok, "prize mount0 damaged to 0.60")
	Records.publish(e_prize)
	var before_cond: Dictionary = e_prize.moduleCondition.duplicate(true)

	var st_b: Dictionary = Battle.create({"fleet": [p_board], "enemyFleet": [e_prize], "islands": [], "seed": 606})
	var sb: Dictionary = st_b.ships[0]
	var sp: Dictionary = st_b.ships[1]
	sb.x = 700.0; sb.y = 850.0; sb.vx = 0.0; sb.vy = 0.0
	sp.x = 724.0; sp.y = 850.0; sp.vx = 0.0; sp.vy = 0.0
	check(Battle.BoardingCombat.order(st_b, str(sb.id), str(sp.id), 6).ok, "boarding order accepted against crippled canonical prize")
	for _t in range(420):
		Battle.update(st_b, 1.0 / 30.0)
		_record_step_stats(st_b, phase_board)
		Battle.pop_events(st_b)
		if bool(sp.get("captureSecured", false)):
			break
	check(bool(sp.get("captureSecured", false)), "crippled canonical prize captured in Battle.update")
	check(sp.moduleCondition == before_cond, "captured canonical prize preserves exact birthNamespace, itemUids, damaged HPs, causes, and locker spares without minting or healing")
	_mark_phase(fam, "boarding_canonical_capture", phase_board, 1.0 / 30.0, float(st_b.time))

	# 2. Legacy plain boat without moduleCondition keeps legacy behavior (turnFactor=1.0, full cadence).
	var phase_leg: Dictionary = _new_phase_stats()
	var leg_spec: Dictionary = _hull_by_id("tin_skiff")
	var leg_ship: Dictionary = Damage.create_ship(leg_spec, {"engine": 0.40, "ammo": 40.0})
	var st_leg: Dictionary = Battle.create({"fleet": [leg_ship], "enemySpecs": [leg_spec], "islands": [], "seed": 607})
	var s_leg: Dictionary = st_leg.ships[0]
	var leg_status: Dictionary = Damage.get_status(s_leg)
	check(str(leg_status.get("equipmentMode", "")) == "legacy" and _approx(float(leg_status.get("turnFactor", 0.0)), 1.0), "legacy boat without moduleCondition keeps legacy mode and turnFactor=1.0")
	_mark_phase(fam, "legacy_mode_parity", phase_leg, 1.0 / 30.0, float(st_leg.time))

	# 3. Corrupt canonical record fails closed in Battle.create and Battle.update without healing or overwrite.
	var phase_bad: Dictionary = _new_phase_stats()
	var bad_ship: Dictionary = _canonical_boat("tin_skiff", "combat-corrupt-owner", {"ammo": 50.0, "fuel": 50.0, "supplies": 10.0})
	bad_ship.moduleCondition.nextItemSeq = 0 # Actual schema corruption: valid serials start at 1.
	var snap_corrupt: Dictionary = bad_ship.moduleCondition.duplicate(true)
	var e_leg: Dictionary = Damage.create_ship(leg_spec, {"ammo": 0.0})
	e_leg.spec.speed = 0.0
	var st_bad: Dictionary = Battle.create({"fleet": [bad_ship], "enemyFleet": [e_leg], "islands": [], "seed": 608})
	Battle.set_autopilot(st_bad, false)
	var sb_bad: Dictionary = st_bad.ships[0]
	var start_pos := Vector2(float(sb_bad.x), float(sb_bad.y))
	var start_ang: float = float(sb_bad.angle)
	st_bad.ships[1].x = float(sb_bad.x) + 180.0; st_bad.ships[1].y = float(sb_bad.y)
	for _t in range(20):
		Battle.update(st_bad, 1.0 / 30.0, {"forward": true, "right": true, "fire": true, "aimX": st_bad.ships[1].x, "aimY": st_bad.ships[1].y})
		_record_step_stats(st_bad, phase_bad)
	var bad_st: Dictionary = Damage.get_status(sb_bad)
	check(not bool(bad_st.get("equipmentOk", true)) and _approx(float(bad_st.speedFactor), 0.0) and _approx(float(bad_st.turnFactor), 0.0) and _approx(float(bad_st.weaponFactor), 0.0), "corrupt canonical owner fails closed with zero speed/turn/weapon factors")
	check(Vector2(float(sb_bad.x), float(sb_bad.y)).distance_to(start_pos) <= 0.0001 and _approx(float(sb_bad.angle), start_ang) and st_bad.projectiles.is_empty() and _approx(float(sb_bad.ammo), 50.0), "corrupt canonical owner cannot move, turn, or fire in Battle.update")
	check(sb_bad.moduleCondition == snap_corrupt, "corrupt canonical owner moduleCondition is left untouched")
	_mark_phase(fam, "corrupt_owner_fail_closed", phase_bad, 1.0 / 30.0, float(st_bad.time))
	_end_family(fam)

func _canonical_family_id(raw: String) -> String:
	var key: String = raw.strip_edges().to_lower().trim_prefix("--")
	if key in ["", "all", "*"]: return "all"
	if key in ["1", "f1", "family1", "weapons", "weapons_cadence", "mount_disable", "per_mount_disable", "test_per_mount_disable_and_damaged_cadence_in_public_battle"]: return "weapons_cadence"
	if key in ["2", "f2", "family2", "jury", "jury_repair", "repair_reenable", "jury_reenable", "test_jury_repair_reenable_threshold_and_priority_in_battle"]: return "jury_repair"
	if key in ["3", "f3", "family3", "engine", "engine_parity", "engine_turn", "turn_30_60", "test_engine_turn_factor_and_30_60_parity"]: return "engine_parity"
	if key in ["3a", "engine_parity_30", "engine_30", "engine_30hz", "test_engine_turn_factor_30hz_only"]: return "engine_parity_30"
	if key in ["3b", "engine_parity_60", "engine_60", "engine_60hz", "test_engine_turn_factor_60hz_only"]: return "engine_parity_60"
	if key in ["4", "f4", "family4", "pump", "pumps", "pump_and_armor", "pump_armor", "flooding_armor", "test_pump_flooding_sink_and_armor_mitigation_in_battle"]: return "pump_and_armor"
	if key in ["5", "f5", "family5", "ai", "ai_role", "ai_role_cert", "certificate_invalidation", "test_ai_role_range_station_and_certificate_invalidation"]: return "ai_role_cert"
	if key in ["6", "f6", "family6", "boarding", "boarding_custody", "boarding_legacy_corrupt", "custody_fail_closed", "test_boarding_capture_custody_legacy_and_corrupt_fail_closed"]: return "boarding_legacy_corrupt"
	return ""

func run_family(family_id: String) -> bool:
	var cid: String = _canonical_family_id(family_id)
	match cid:
		"weapons_cadence": test_per_mount_disable_and_damaged_cadence_in_public_battle(); return true
		"jury_repair": test_jury_repair_reenable_threshold_and_priority_in_battle(); return true
		"engine_parity": test_engine_turn_factor_and_30_60_parity(); return true
		"engine_parity_30": test_engine_turn_factor_30hz_only(); return true
		"engine_parity_60": test_engine_turn_factor_60hz_only(); return true
		"pump_and_armor": test_pump_flooding_sink_and_armor_mitigation_in_battle(); return true
		"ai_role_cert": test_ai_role_range_station_and_certificate_invalidation(); return true
		"boarding_legacy_corrupt": test_boarding_capture_custody_legacy_and_corrupt_fail_closed(); return true
		"all":
			for fid in FAMILY_ORDER: run_family(str(fid))
			return true
		_:
			push_error("FAIL equipment_combat: unknown family selector '" + family_id + "'")
			failures += 1
			return false

func _resolve_requested_families() -> Dictionary:
	var tokens: Array = []
	for raw in OS.get_cmdline_user_args():
		var arg: String = str(raw).strip_edges()
		if arg.is_empty(): continue
		if arg in ["--list", "--list-families"]: return {"ok": true, "listOnly": true, "families": FAMILY_ORDER.duplicate()}
		if arg.begins_with("--family=") or arg.begins_with("--case=") or arg.begins_with("--only=") or arg.begins_with("--suite="):
			for item in arg.split("=", true, 1)[1].split(",", false): tokens.append(item)
		else:
			tokens.append(arg)
	if tokens.is_empty():
		for raw_cmd in OS.get_cmdline_args():
			var cmd: String = str(raw_cmd).strip_edges()
			if cmd == "--list-families": return {"ok": true, "listOnly": true, "families": FAMILY_ORDER.duplicate()}
			if cmd.begins_with("--family=") or cmd.begins_with("--case="):
				for item in cmd.split("=", true, 1)[1].split(",", false): tokens.append(item)
	if tokens.is_empty():
		var env_fam: String = OS.get_environment("BRASS_COMBAT_FAMILY").strip_edges()
		if env_fam.is_empty(): env_fam = OS.get_environment("BRASS_TEST_FAMILY").strip_edges()
		if not env_fam.is_empty():
			for item in env_fam.split(",", false): tokens.append(item)
	if tokens.is_empty():
		tokens.append(SELECTED_FAMILY)
	var resolved: Array = []
	for tok in tokens:
		var cid: String = _canonical_family_id(str(tok))
		if cid.is_empty():
			return {"ok": false, "listOnly": false, "error": "Unknown equipment_combat family selector: " + str(tok), "families": []}
		if cid == "all":
			for fid in FAMILY_ORDER:
				if not resolved.has(fid): resolved.append(fid)
		elif not resolved.has(cid):
			resolved.append(cid)
	return {"ok": true, "listOnly": false, "families": resolved}

func _initialize() -> void:
	_ensure_loaded()
	var suite_started_usec: int = Time.get_ticks_usec()
	var sel: Dictionary = _resolve_requested_families()
	if bool(sel.get("listOnly", false)):
		for i in range(FAMILY_ORDER.size()): print("FAMILY %d %s" % [i + 1, str(FAMILY_ORDER[i])])
		quit(0)
		return
	if not bool(sel.get("ok", false)):
		push_error("FAIL equipment_combat: " + str(sel.get("error", "Invalid family selection")))
		quit(1)
		return
	var families: Array = sel.get("families", [])
	print("PLAN equipment_combat families=%s userArgs=%s" % [JSON.stringify(families), JSON.stringify(OS.get_cmdline_user_args())])
	for fid in families:
		run_family(str(fid))
	var total_wall_ms: float = float(Time.get_ticks_usec() - suite_started_usec) / 1000.0
	if failures > 0 or checks <= 0:
		push_error("equipment_combat: %d checks, %d failures (families=%s wallMs=%.2f)" % [checks, failures, JSON.stringify(families), total_wall_ms])
		quit(1)
		return
	print("equipment_combat: %d checks, 0 failures (families=%s wallMs=%.2f)" % [checks, JSON.stringify(families), total_wall_ms])
	quit(0)
