extends SceneTree
## Independent frozen-reference probe. Submit one family per bounded native job.
## Trace logs retain lossless Variant bytes, not rounded JSON numeric snapshots.
var Certification: GDScript = load("res://scripts/tactical_certification.gd")
const Damage = preload("res://scripts/damage.gd")
const EquipmentCombat = preload("res://scripts/equipment_combat.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Core = preload("res://scripts/equipment_condition.gd")
const Refit = preload("res://scripts/refit.gd")
const Battle = preload("res://scripts/battle.gd")
const Tactical = preload("res://scripts/tactical_runtime.gd")
const Routes = preload("res://scripts/tactical_routes.gd")
const REFERENCE_PATH: String = "res://tests/equipment_rollout_reference.gd"
const REFERENCE_SHA256: String = "ad52e2d1251b656a27f4024db934d3b0d130d6d1829ac1bb3462ee81b5d9daf8"
const CASES: Array = ["healthy", "damaged", "disabled", "reenable", "fire_flood", "dry_crew", "sinking", "transitions", "legacy", "corrupt"]
# Exactly the instantaneous fields read by motion, mount projection and capability.
# tick_ship's averaged inflow/bailing/repair and accumulated work are excluded.
const FACTOR_KEYS: Array = ["equipmentMode", "equipmentOk", "speedFactor", "turnFactor", "weaponFactor", "weaponFactors", "engineFactor", "pumpFactor", "armorFactor", "repairPriority"]
var checks: int = 0
var failures: int = 0
var reference: GDScript
var world: Dictionary = {}

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL equipment_rollout: " + message)
	return ok

func same(a: Variant, b: Variant, message: String) -> bool:
	return check(var_to_bytes(a) == var_to_bytes(b), message)

func emit_record(kind: String, value: Dictionary) -> void:
	# One full state plus equal candidate hash is lossless for equal pairs. A
	# mismatch additionally retains the entire candidate state for diagnosis.
	print("ROLLOUT_" + kind + " " + Marshalls.raw_to_base64(var_to_bytes(value)))

func digest(value: Variant) -> String:
	return var_to_bytes(value).hex_encode().sha256_text()

func item_at(ship: Dictionary, location: String) -> Dictionary:
	for item in ship.get("moduleCondition", {}).get("items", {}).values():
		if str(item.get("location", "")) == location: return item
	return {}

func hurt(ship: Dictionary, location: String, loss: float) -> void:
	var item: Dictionary = item_at(ship, location)
	if not check(not item.is_empty(), "fixture has " + location): return
	check(Core.apply_component_damage(ship.moduleCondition, {"itemUid": str(item.itemUid), "loss": loss, "cause": "Rollout probe damage"}).ok, "damage " + location)
	check(Records.publish(ship).ok, "publish damaged " + location)

func boat(case_id: String) -> Dictionary:
	var base: Dictionary = {}
	for hull in world.get("HULLS", []):
		if str(hull.get("id", "")) == "tin_skiff": base = hull.duplicate(true)
	if not check(not base.is_empty(), "exact tin_skiff fixture exists"): return {}
	var ship: Dictionary = Damage.create_ship(base, {"id": "rollout-own", "team": "player", "uid": "rollout-probe-hull", "x": 600.0, "y": 850.0, "vx": 11.0, "vy": -3.0, "angle": 0.15, "order": "move", "orderTarget": {"x": 900.0, "y": 990.0}, "orderRevision": 7, "supplies": 12.0, "policy": "repair", "cooldown": 0.8})
	if case_id != "legacy":
		ship.baseSpec = base.duplicate(true)
		ship.loadout = {"weapons": ["stock_primary", "rapid_gun"], "engine": "stock_engine", "armor": "stock_armor"}
		Refit.ensure(ship, base)
		check(Records.initialize(ship, {"base": base, "loadout": ship.loadout, "catalog": Refit.catalog(), "identity": "rollout-probe-hull", "knownUids": []}).ok, "canonical fixture birth")
		if case_id in ["damaged", "fire_flood", "transitions"]:
			for pair in [["engine", 0.45], ["pumps", 0.35], ["armor", 0.4], ["mount0", 0.5], ["mount1", 0.3]]: hurt(ship, str(pair[0]), float(pair[1]))
		if case_id == "disabled":
			for location in ["engine", "pumps", "mount0"]: hurt(ship, location, 0.85)
			ship.supplies = 0.0
		if case_id == "reenable":
			hurt(ship, "mount0", 0.8001)
			check(Damage.set_repair_priority(ship, "weapons") == "weapons", "weapon repair priority")
		if case_id == "corrupt": ship.moduleCondition.nextItemSeq = 0
	else:
		ship.engine = 0.4
		ship.water = 40.0
		ship.breaches = [{"area": 4.0, "section": "waterline"}]
	if case_id == "fire_flood":
		ship.hp *= 0.65; ship.water = float(ship.capacity) * 0.3
		ship.breaches = [{"area": 12.0, "section": "waterline"}, {"area": 4.0, "section": "bow"}]
		ship.fire = 8.0; ship.wounded = 1.0; ship.shoreCrew = 0.5
		ship.fuel = 0.0001; ship.supplies = 0.04
		# Machinery must receive work before fire suppression to exercise a real
		# finite supply debit; auto priority would spend all work on the fire.
		check(Damage.set_repair_priority(ship, "engine") == "engine", "finite-supply machinery work precedes fire")
	if case_id == "dry_crew":
		ship.crew = float(ship.crewMin); ship.wounded = minf(1.0, float(ship.crew))
		ship.shoreCrew = 0.5; ship.fuel = 0.0; ship.supplies = 0.0; ship.ammo = 0.0
	if case_id == "sinking":
		ship.water = float(ship.capacity) - 0.001
		ship.breaches = [{"area": 100000.0, "section": "waterline"}]
		ship.fuel = 0.0; ship.supplies = 0.0
	ship.mounts = EquipmentCombat.apply_mount_condition(ship, Battle._base_mounts(ship))
	ship.status = Damage.get_status(ship)
	return ship

func factors(status: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in FACTOR_KEYS: out[key] = status.get(key)
	return out

func intervene(ship: Dictionary, rng: RandomNumberGenerator, tick: int, hz: int) -> Array:
	if tick == hz / 2:
		return Damage.apply_hit(ship, {"damage": 24.0, "kind": "shell", "penetration": 5.0, "section": "bow"}, rng)
	if tick == hz:
		Damage.set_repair_priority(ship, "engine")
		ship.policy = "bail"; ship.wounded = minf(float(ship.crew), float(ship.wounded) + 0.5)
	return []

func trace_case(case_id: String, hz: int) -> void:
	var original: Dictionary = boat(case_id)
	if original.is_empty(): return
	var before: Dictionary = original.duplicate(true)
	var a: Dictionary = original.duplicate(true)
	var b: Dictionary = original.duplicate(true)
	var ra := RandomNumberGenerator.new(); ra.seed = 381031
	var rb := RandomNumberGenerator.new(); rb.seed = 381031
	var initial_rng: int = ra.state
	var status: Dictionary = Damage.get_status(b)
	var canonical: bool = str(status.get("equipmentMode", "")) == "canonical"
	var mask_a: float = EquipmentCombat.working_mask(a) if canonical else NAN
	var mask_b: float = EquipmentCombat.working_mask(b, status) if canonical else NAN
	var dt: float = 1.0 / float(hz)
	var points: Array = [Vector2(900.0, 990.0), Vector2(1020.0, 850.0)]
	var ia: int = 0
	var ib: int = 0
	var caps_a: Array = [reference.capability(a, mask_a)]
	var caps_b: Array = [Certification._capability_with_status(b, status, mask_b)]
	emit_record("BEGIN", {"case": case_id, "hz": hz, "seed": 381031, "state": before, "rng": ra.state})
	for tick in range(2 * hz):
		if case_id == "transitions":
			var ea: Array = intervene(a, ra, tick, hz)
			var eb: Array = intervene(b, rb, tick, hz)
			same(ea, eb, "identical hit/priority events")
			# Production's private loop has no external edits. This probe explicitly
			# refreshes at injected hit/crew/priority boundaries, never across one.
			if tick == hz / 2 or tick == hz: status = Damage.get_status(b)
		var ca: Dictionary = reference.steering(a, points, ia, {}, a.mounts)
		var cb: Dictionary = Certification.steering(b, points, ib, {}, b.mounts)
		same(ca, cb, case_id + " steering " + str(tick))
		ia = int(ca.index); ib = int(cb.index)
		var ma: Dictionary = reference.motion(a, dt, float(ca.angle), float(ca.throttle))
		var mb: Dictionary = Certification._motion_with_status(b, dt, float(cb.angle), float(cb.throttle), false, status)
		same(ma, mb, case_id + " motion " + str(tick))
		a.merge(ma, true); b.merge(mb, true)
		same(a, b, case_id + " full state after motion " + str(tick))
		var ta: Dictionary = Damage.tick_ship(a, dt, {"inCombat": true})
		status = Damage.tick_ship(b, dt, {"inCombat": true})
		same(ta, status, case_id + " full tick report " + str(tick))
		if canonical:
			a.mounts = EquipmentCombat.apply_mount_condition(a, a.mounts)
			b.mounts = EquipmentCombat.apply_mount_condition(b, b.mounts, status)
		caps_a.append(reference.capability(a, mask_a))
		caps_b.append(Certification._capability_with_status(b, status, mask_b))
		same(a, b, case_id + " full post-tick ship " + str(tick))
		same(caps_a[-1], caps_b[-1], case_id + " capability " + str(tick))
		same(factors(status), factors(Damage.get_status(b)), case_id + " returned factors are final " + str(tick))
		same(ra.state, rb.state, case_id + " RNG " + str(tick))
		emit_record("SAMPLE", {"case": case_id, "hz": hz, "tick": tick, "state": a, "candidateState": b if var_to_bytes(a) != var_to_bytes(b) else null, "referenceHash": digest(a), "candidateHash": digest(b), "motion": ma, "candidateMotion": mb, "capability": caps_a[-1], "candidateCapability": caps_b[-1], "tickReport": ta, "candidateTickReport": status, "rng": ra.state, "candidateRng": rb.state})
	same(caps_a, caps_b, case_id + " entire 2-second capability sequence")
	same(original, before, case_id + " live input remains unchanged")
	check(caps_a.size() == 2 * hz + 1, "full 60/120 substep count")
	if case_id == "reenable": check(str(item_at(b, "mount0").status) != "disabled", "actual repair crossed reenable threshold")
	if case_id == "sinking": check(bool(b.sunk), "actual flood caused sinking")
	if case_id == "fire_flood": check(float(b.fuel) == 0.0 and float(b.supplies) == 0.0, "finite fuel/supplies exhausted (fuel=%s supplies=%s)" % [str(b.fuel), str(b.supplies)])
	if case_id == "corrupt": check(not bool(status.equipmentOk) and float(status.speedFactor) == 0.0, "corrupt remains fail-closed")
	if case_id == "transitions": check(ra.state != initial_rng and str(status.repairPriority) == "engine", "hit RNG and changed repair priority observed")
	print("PHASE trace %s hz=%d samples=%d checks=%d failures=%d" % [case_id, hz, 2 * hz, checks, failures])

func budget() -> Dictionary:
	return {"fullRoutes": 0, "cacheHits": 0, "rollouts": 0, "samples": 0, "clearanceTests": 0, "exhaustions": 0, "rolled": {}, "clearanceLimit": 4096}

func certificate_inputs(case_id: String, hz: int) -> Dictionary:
	var live: Dictionary = boat(case_id)
	var enemy: Dictionary = Damage.create_ship(live.spec, {"id": "rollout-enemy", "team": "enemy", "x": 820.0, "y": 850.0, "vx": 0.0, "vy": 0.0})
	enemy.mounts = []
	var rng := RandomNumberGenerator.new(); rng.seed = 381031
	var st: Dictionary = {"time": 3.0, "islands": [], "ships": [live, enemy], "rng": rng, "projectiles": []}
	Tactical.ensure(st)
	st.tactical.dt = 1.0 / float(hz)
	st.tactical.geometry = Routes.terrain(st)
	st.tactical.ships = {str(live.id): live, str(enemy.id): enemy}
	st.tactical.observed = {str(live.id): Tactical._observed(live, live.mounts), str(enemy.id): Tactical._observed(enemy, [])}
	st.tactical.cells = Routes.grid(st.tactical.observed.values())
	var own: Dictionary = Tactical._own(live, live.mounts)
	var view: Dictionary = {"time": 3.0, "snapshotRevision": 4, "terrainRevision": st.tactical.terrainRevision, "dueIds": [str(live.id)], "ships": [own, st.tactical.observed[str(enemy.id)]]}
	var candidate: Dictionary = {"candidateId": "rollout-candidate", "shipId": str(live.id), "targetId": str(enemy.id), "leaderId": "", "role": "skirmisher", "orderRevision": 7, "snapshotRevision": 4, "approach": [Vector2(680.0, 900.0)], "pass": [Vector2(740.0, 920.0)], "exit": [Vector2(650.0, 960.0)], "fireMountIds": []}
	return {"st": st, "view": view, "own": own, "candidate": candidate}

func certificate_case(case_id: String, hz: int) -> void:
	var input: Dictionary = certificate_inputs(case_id, hz)
	var initial_ship: Dictionary = input.st.ships[0].duplicate(true)
	var sa: Dictionary = input.st.duplicate(true)
	var sb: Dictionary = input.st.duplicate(true)
	var initial_rng: int = input.st.rng.state
	sa.rng = RandomNumberGenerator.new(); sa.rng.state = initial_rng
	sb.rng = RandomNumberGenerator.new(); sb.rng.state = initial_rng
	var ba: Dictionary = budget()
	var bb: Dictionary = budget()
	var start: int = Time.get_ticks_usec()
	var ca: Dictionary = reference.certify(sa, input.view, input.own, input.candidate, "probe", ba, ["rollout-enemy"])
	var before_us: int = Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	var cb: Dictionary = Certification.certify(sb, input.view, input.own, input.candidate, "probe", bb, ["rollout-enemy"])
	var after_us: int = Time.get_ticks_usec() - start
	same(ca, cb, case_id + " exact actual certify result")
	same(ba, bb, case_id + " same geometry/sample/rollout budget")
	same(sa.tactical.predictions, sb.tactical.predictions, case_id + " actual full prediction/capability arrays")
	same(sa.ships, sb.ships, case_id + " actual certify full live ship state")
	same(sb.ships[0], initial_ship, case_id + " private copy never mutates live ship")
	same(sa.rng.state, sb.rng.state, case_id + " actual certify RNG state")
	same(sb.rng.state, initial_rng, case_id + " actual certify consumes no live RNG")
	check(ca.status == "valid" and int(ca.rolloutSamples) == 60 and int(ba.samples) == 2 * hz, "unchanged complete 2s / 60 samples")
	emit_record("CERTIFICATE", {"case": case_id, "hz": hz, "reference": ca, "candidate": cb, "referencePredictions": sa.tactical.predictions, "candidatePredictions": sb.tactical.predictions, "budget": ba, "referenceUsec": before_us, "candidateUsec": after_us, "seed": 381031})
	print("PHASE certificate %s hz=%d referenceUsec=%d candidateUsec=%d samples=%d checks=%d failures=%d" % [case_id, hz, before_us, after_us, int(ba.samples), checks, failures])

func freshness() -> void:
	var ship: Dictionary = boat("damaged")
	var old: Dictionary = Damage.get_status(ship)
	ship.status = old.duplicate(true) # Deliberately stale caller-owned observation.
	check(Damage.set_repair_priority(ship, "pumps") == "pumps", "priority changed")
	var rng := RandomNumberGenerator.new(); rng.seed = 381031
	Damage.apply_hit(ship, {"damage": 22.0, "kind": "shell", "section": "engine"}, rng)
	var fresh: Dictionary = Damage.get_status(ship)
	check(str(fresh.repairPriority) == "pumps" and float(fresh.engineFactor) < float(old.engineFactor), "public status sees priority and real hit immediately")
	same(Certification.capability(ship), reference.capability(ship), "public capability stays fresh after priority and hit")
	same(Certification.motion(ship, 1.0 / 60.0, 0.8, 0.9, true), reference.motion(ship, 1.0 / 60.0, 0.8, 0.9, true), "public boosted motion stays fresh")
	var old_seq: Variant = ship.moduleCondition.nextItemSeq
	ship.moduleCondition.nextItemSeq = 0
	check(not bool(Damage.get_status(ship).equipmentOk), "public get_status revalidates actual corrupt transition")
	same(Certification.capability(ship), reference.capability(ship), "public capability fails closed without stale status")
	same(Certification.motion(ship, 1.0 / 30.0, -0.9, -0.55), reference.motion(ship, 1.0 / 30.0, -0.9, -0.55), "public motion fails closed without stale status")
	ship.moduleCondition.nextItemSeq = old_seq
	ship.equipmentState = {"forged": true}
	check(not bool(Damage.get_status(ship).equipmentOk), "public get_status freshly refuses foreign metadata")
	ship.erase("equipmentState")
	check(bool(Damage.get_status(ship).equipmentOk), "public status recovers only after actual foreign field removal")

func installed_case(case_id: String, hz: int) -> void:
	# One installed dependency graph ONLY. The oracle is a SEPARATE native
	# process rooted at frozen original/ad52, compared losslessly by Root.
	var input: Dictionary = certificate_inputs(case_id, hz)
	if case_id == "transitions":
		var live: Dictionary = input.st.ships[0]
		Damage.apply_hit(live, {"damage": 24.0, "kind": "shell", "penetration": 5.0, "section": "bow"}, input.st.rng)
		Damage.set_repair_priority(live, "engine")
		live.policy = "bail"; live.wounded = minf(float(live.crew), float(live.wounded) + 0.5)
		input.own = Tactical._own(live, live.mounts)
	var before: Dictionary = input.st.ships[0].duplicate(true)
	var rng_before: int = input.st.rng.state
	var work: Dictionary = budget()
	emit_record("INSTALLED_BEGIN", {"case": case_id, "hz": hz, "state": before, "rng": rng_before})
	var cert: Dictionary = Certification.certify(input.st, input.view, input.own, input.candidate, "probe", work, ["rollout-enemy"])
	check(cert.status == "valid" and int(cert.rolloutSamples) == 60 and int(work.samples) == 2 * hz, "actual installed prefix preserves full work " + case_id)
	same(input.st.ships[0], before, "actual installed prefix live purity " + case_id)
	same(input.st.rng.state, rng_before, "actual installed prefix consumes no live RNG " + case_id)
	check(input.st.tactical.predictions.get("probe", {}).get("poses", []).size() == 2 * hz + 1, "actual installed full pose sequence " + case_id)
	emit_record("INSTALLED_CERT", {"case": case_id, "hz": hz, "certificate": cert, "predictions": input.st.tactical.predictions, "budget": work, "live": input.st.ships, "rng": input.st.rng.state})
	print("PHASE installed %s hz=%d samples=%d checks=%d failures=%d" % [case_id, hz, int(work.samples), checks, failures])

func _initialize() -> void:
	ProjectSettings.set_setting("application/run/flush_stdout_on_print", true)
	var family: String = "freshness"
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--family="): family = str(arg).trim_prefix("--family=")
	if not check(family in ["trace30", "trace60", "certificate30", "certificate60", "freshness", "installed30", "installed60"], "known bounded family"):
		quit(1); return
	if not family.begins_with("installed"):
		if not check(FileAccess.get_sha256(REFERENCE_PATH) == REFERENCE_SHA256, "frozen reference bytes exactly pinned"):
			quit(1); return
		reference = GDScript.new()
		reference.source_code = FileAccess.get_file_as_string(REFERENCE_PATH)
		if not check(reference.reload() == OK, "reference cert compiles; NOT an old-math oracle if dependencies changed"):
			quit(1); return
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	print("BEGIN equipment_rollout family=" + family)
	if family == "freshness": freshness()
	else:
		var hz: int = 60 if family.ends_with("60") else 30
		for case_id in CASES:
			if family.begins_with("installed"): installed_case(case_id, hz)
			elif family.begins_with("trace"): trace_case(case_id, hz)
			else: certificate_case(case_id, hz)
	print("equipment_rollout: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
