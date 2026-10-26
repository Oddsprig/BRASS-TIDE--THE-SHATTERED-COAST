extends SceneTree
## prefix-invariants-r1 differential and contract fixture.
## Source-only candidate; does not launch an engine.
## Compares EquipmentRollout.prefix against a byte-exact Main 97fba382 reference
## prefix across healthy, fuel-crossing-0, fire, water/breaches/sinking, module
## jury repair, cannon-torpedo mount sets, and early-blocked geometry/traffic/budget
## cases for both parts=1 (1/30s) and parts=2 (1/60s), asserting exact var_to_bytes
## equality on outputs, budgets, certificates, and immutable live inputs.

const EquipmentRollout = preload("res://scripts/equipment_rollout.gd")
const Routes = preload("res://scripts/tactical_routes.gd")
const Damage = preload("res://scripts/damage.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const EquipmentCombat = preload("res://scripts/equipment_combat.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Core = preload("res://scripts/equipment_condition.gd")
const Refit = preload("res://scripts/refit.gd")

class ReferenceRollout extends RefCounted:
	const Routes=preload("res://scripts/tactical_routes.gd")
	const Damage=preload("res://scripts/damage.gd")
	const EquipmentDamage=preload("res://scripts/equipment_damage.gd")
	const EquipmentCombat=preload("res://scripts/equipment_combat.gd")
	const STEP: float=1.0/30.0
	const HULL_CLEARANCE_MARGIN: float=4.0

	static func pose(ship: Dictionary) -> Dictionary:
		return {"x":float(ship.x),"y":float(ship.y),"vx":float(ship.vx),"vy":float(ship.vy),"angle":float(ship.angle)}

	static func execution(candidate: Dictionary) -> Array:
		# Exit geometry is reserved and checked; the planner must explicitly enter a
		# breakaway/regroup phase before a newly certified exit becomes helm authority.
		var result: Array=candidate.get("approach",[]).duplicate()
		result.append_array(candidate.get("pass",[]))
		return result

	static func steering(ship: Dictionary,points: Array,index: int,target: Dictionary={},mounts: Array=[]) -> Dictionary:
		var at: int=index
		var p: Vector2=Routes.point(ship)
		while at<points.size() and p.distance_to(points[at])<14.0:at+=1
		var heading: float=float(ship.angle)
		var throttle: float=0.0
		if at<points.size():
			var delta: Vector2=points[at]-p
			heading=delta.angle()
			var turn: float=absf(angle_difference(float(ship.angle),heading))
			throttle=clampf(delta.length()/140.0,0.2,0.95)*clampf(cos(turn),0.12,1.0)
		else:
			var weight: float=-1.0
			for mount in mounts:
				if target.is_empty() or float(ship.ammo)<float(mount.ammoCost):continue
				var value: float=float(mount.damage)*float(mount.fireRate)
				if value<=weight:continue
				weight=value
				var bearing: float=(Routes.point(target)-p).angle()
				heading=bearing-float(mount.angle) if float(mount.arc)<TAU-0.01 else bearing
		return {"angle":heading,"throttle":throttle,"index":at}

	static func mount_target(candidate: Dictionary,mount_id: String) -> String:
		var map: Dictionary=candidate.get("fireMountTargets",{}) if candidate.get("fireMountTargets") is Dictionary else {}
		if map.has(mount_id):return str(map[mount_id])
		return str(candidate.get("targetId",""))

	static func primary_mounts(mounts: Array,candidate: Dictionary) -> Array:
		if not candidate.has("fireMountTargets") or not candidate.get("fireMountTargets") is Dictionary:
			return mounts
		var fire_ids: Array=candidate.get("fireMountIds",[]) if candidate.get("fireMountIds") is Array else []
		var primary_id: String=str(candidate.get("targetId",""))
		var filtered: Array=[]
		for mount in mounts:
			var mid: String=str(mount.id)
			if (fire_ids.is_empty() or mid in fire_ids) and mount_target(candidate,mid)==primary_id:
				filtered.append(mount)
		return filtered if not filtered.is_empty() else mounts

	static func motion_with_status(ship: Dictionary,dt: float,desired: float,throttle: float,boost: bool,status: Dictionary) -> Dictionary:
		# Shared by the real Battle._move and detached rollouts. Damage/cooldown are
		# advanced by Battle exactly once; a rollout never repairs or spends live stores.
		if not bool(status.get("equipmentOk",true)):
			return {"x":float(ship.x),"y":float(ship.y),"vx":0.0,"vy":0.0,"angle":float(ship.angle),"fuel":float(ship.fuel)}
		var turn_rate: float=maxf(0.0,Damage.number(ship.spec.get("turn"),1.8))*clampf(Damage.number(status.get("turnFactor"),1.0),0.0,1.0)
		var angle: float=wrapf(float(ship.angle)+clampf(angle_difference(float(ship.angle),desired),-turn_rate*dt,turn_rate*dt),-PI,PI)
		var speed: float=maxf(0.0,Damage.number(ship.spec.get("speed"),90.0))*float(status.speedFactor)*(1.0 if float(ship.fuel)>0.0 else 0.2)*throttle*(1.2 if boost else 1.0)
		var velocity: Vector2=Vector2(ship.vx,ship.vy).lerp(Vector2.from_angle(angle)*speed,1.0-exp(-dt*4.0))
		var p: Vector2=Routes.point(ship)+velocity*dt
		var fuel: float=float(ship.fuel)
		if velocity.length()>5.0:fuel=maxf(0.0,fuel-dt*(0.018 if boost else 0.01)*maxf(0.0,Damage.number(ship.spec.get("fuelUse"),1.0)))
		return {"x":p.x,"y":p.y,"vx":velocity.x,"vy":velocity.y,"angle":angle,"fuel":fuel}

	static func capability_with_status(ship: Dictionary,status: Dictionary,mask_override: float=NAN,frame_cache=null) -> Dictionary:
		# Only certify's private copy can reuse the final status from its last tick.
		# Direct scalars and module HP are still read from that copy at this sample.
		return _capability_from_fields(ship,status,EquipmentCombat.capability_fields(ship,status,mask_override,frame_cache))

	static func _capability_from_fields(ship: Dictionary,status: Dictionary,fields: Dictionary) -> Dictionary:
		var result: Dictionary={}
		for key in ["hp","water","engine","crew","wounded","fire"]:result[key]=float(ship[key])
		result.speedFactor=float(status.speedFactor);result.weaponFactor=float(status.weaponFactor)
		result.merge(fields,true)
		return result

	static func prefix(st: Dictionary,ship: Dictionary,candidate: Dictionary,budget: Dictionary,cert: Dictionary,sub_dt: float,parts: int) -> Dictionary:
		var id: String=str(ship.id)
		var live_ship: Dictionary=st.get("tactical",{}).get("ships",{}).get(id,ship)
		var copy: Dictionary=live_ship.duplicate(true)
		copy.mounts=ship.mounts.duplicate(true)
		# Local to this synchronous private rollout. Never store it on a live ship,
		# prediction record or across calls; Damage still validates every real tick.
		var rollout_status: Dictionary=Damage.get_status(copy)
		var is_canonical: bool=str(rollout_status.get("equipmentMode",""))=="canonical"
		var init_mask: float=EquipmentCombat.working_mask(copy,rollout_status) if is_canonical else NAN
		var fixed_inputs: Dictionary=_fixed_inputs(copy) if is_canonical else {}
		var points: Array=execution(candidate)
		var index: int=0
		var predicted: Array=[pose(copy)]
		var capabilities: Array=[(_capability_from_fields(copy,rollout_status,EquipmentCombat._canonical_capability_fields(copy,rollout_status,init_mask)) if is_canonical else capability_with_status(copy,rollout_status,init_mask))]
		var target: Dictionary=st.tactical.observed.get(str(candidate.get("targetId","")),{})
		var primary: Array=primary_mounts(copy.mounts,candidate)
		var chunk: Array=[Routes.point(copy)]
		var prefix_ctx: Dictionary={}
		var prefix_info: Callable=Callable()
		var prefix_repair: Callable=Callable()
		var prefix_publish: Callable=Callable()
		var prefix_absorb: Callable=Callable()
		var prefix_step_status: Callable=Callable()
		if is_canonical:
			# Local to this synchronous prefix. Not stored on the copy, certificate,
			# prediction, or return. Callables stay in these locals so ctx cannot cycle.
			# Opening get_status above and the closing inspect below keep the schema check.
			prefix_ctx={"owner":copy,"valid":false}
			prefix_info=func(boat: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_info(boat, prefix_ctx)
			prefix_repair=func(boat: Dictionary, h: float, crew_repair: float, options: Dictionary, info: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_repair(boat, h, crew_repair, options, info, prefix_ctx)
			prefix_publish=func(boat: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_publish(boat, prefix_ctx)
			prefix_absorb=func(boat: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_absorb(boat, prefix_ctx)
			prefix_step_status=func(boat: Dictionary, info: Dictionary) -> Dictionary: return EquipmentDamage._prefix_ctx_step_status(boat, info, prefix_ctx, Damage._status_for_info)
			# This copy, context and internal callbacks belong only to this synchronous
			# prefix. Motion/geometry do not write equipment. Known writers invalidate
			# the proof before mutation; no caller callback or live owner receives ctx.
			EquipmentDamage._prefix_tick_scope_begin(prefix_ctx)
		var start_time: float=0.0
		for step in range(60):
			for _part in range(parts):
				var control: Dictionary=steering(copy,points,index,target,primary)
				index=int(control.index)
				var next: Dictionary=motion_with_status(copy,sub_dt,float(control.angle),float(control.throttle),false,rollout_status)
				copy.merge(next,true)
				budget.samples+=1
				predicted.append(pose(copy));chunk.append(Routes.point(copy))
				# Advance copied condition for the NEXT tick exactly as Battle's shared
				# damage prepass will. No live resources change. Capability tolerance below
				# is numerical error only; actual incoming hits are never predicted away.
				# The returned factors describe the final post-tick state. Its inflow,
				# bailing and repair may be averages; none of these consumers use them.
				if is_canonical:
					rollout_status=Damage._tick_canonical_with(copy,sub_dt,{"inCombat":true},prefix_info,prefix_repair,prefix_publish,prefix_absorb,null,prefix_step_status)
				else:
					rollout_status=Damage.tick_ship(copy,sub_dt,{"inCombat":true})
				if is_canonical:
					copy.mounts=EquipmentCombat._condition_mounts_from_status(copy,copy.mounts,rollout_status)
					primary=primary_mounts(copy.mounts,candidate)
				capabilities.append(_capability_from_fields(copy,rollout_status,EquipmentCombat._canonical_capability_fields(copy,rollout_status,init_mask)) if is_canonical else capability_with_status(copy,rollout_status,init_mask))
			cert.rolloutSamples+=1
			# A conservative capsule contains ALL ten integrated positions, including
			# curved turning and braking drift. Six swept envelopes cover the prefix.
			if (step+1)%10==0:
				var a: Vector2=chunk[0]
				var b: Vector2=chunk[-1]
				var radius: float=maxf(10.0,float(ship.spec.get("size",16)))+HULL_CLEARANCE_MARGIN
				var deviation: float=0.0
				for p in chunk:deviation=maxf(deviation,Routes.distance(p,a,b))
				radius+=deviation
				var result: String=Routes.sweep(st.tactical.geometry,a,b,radius,budget)
				if result=="valid":result=Routes.occupied(st.tactical.cells,ship,a,b,radius,start_time,float(step+1)*STEP,budget)
				if result!="valid":
					if is_canonical:EquipmentDamage._prefix_tick_scope_end(prefix_ctx)
					cert.status=result;cert.reason="Checking turning clearance" if result=="pending" else "Cannot turn or brake safely on this approach";return {"ok":false}
				chunk=[b];start_time=float(step+1)*STEP
		if is_canonical:
			EquipmentDamage._prefix_tick_scope_end(prefix_ctx)
			var final_info: Dictionary=EquipmentDamage.inspect_owner(copy)
			if not final_info.get("ok",false) or str(final_info.get("mode",""))!="canonical" or var_to_bytes(_fixed_inputs(copy))!=var_to_bytes(fixed_inputs):
				cert.status="blocked";cert.reason="Equipment input changed; reassessing"
				return {"ok":false}
		return {"ok":true,"poses":predicted,"capabilities":capabilities,"primary":primary}

	static func _fixed_inputs(ship: Dictionary) -> Dictionary:
		var condition: Dictionary=ship.get("moduleCondition",{}).duplicate(true)
		condition.erase("legacyEngineSynced")
		for item in condition.get("items",{}).values():
			for key in ["hp","status","cause"]: item.erase(key)
		var fixed: Dictionary={"condition":condition}
		for key in ["spec","baseSpec","loadout","uid","id","type","team","crewMin","crewOptimal","crewMax","capacity","maxHp","policy","supportRepairFactor","shoreCrew"]:
			if ship.has(key): fixed[key]=ship[key].duplicate(true) if ship[key] is Dictionary or ship[key] is Array else ship[key]
		return fixed

const STANDARD_FIT: Dictionary = {
	"weapons": ["stock_primary", "rapid_gun", "light_cannon", "fire_rocket"],
	"engine": "stock_engine",
	"armor": "stock_armor"
}
const CANNON_TORPEDO_FIT: Dictionary = {
	"weapons": ["light_cannon", "light_torpedo", "rapid_gun", "fire_rocket"],
	"engine": "boost_drive",
	"armor": "scout_plating"
}
const LOCKER: Dictionary = {"rapid_gun": 2, "stock_engine": 1, "scout_plating": 1}

var world: Dictionary = {}
var catalog: Dictionary = {}
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("prefix_invariants: " + message)

func _bad_encoded(value, path: String) -> String:
	var kind: int = typeof(value)
	if kind == TYPE_OBJECT or kind == TYPE_CALLABLE or kind == TYPE_SIGNAL or kind == TYPE_RID:
		return path + " " + type_string(kind)
	if kind == TYPE_DICTIONARY:
		for key in value.keys():
			var key_bad: String = _bad_encoded(key, path + ".key")
			if not key_bad.is_empty():
				return key_bad
			var found: String = _bad_encoded(value[key], path + "." + str(key))
			if not found.is_empty():
				return found
	elif kind == TYPE_ARRAY:
		for i in value.size():
			var found: String = _bad_encoded(value[i], path + "[" + str(i) + "]")
			if not found.is_empty():
				return found
	return ""

func _bytes(label: String, value) -> Dictionary:
	var bad: String = _bad_encoded(value, label)
	if not bad.is_empty():
		check(false, label + " refused before var_to_bytes (" + bad + ")")
		return {"ok": false, "bytes": PackedByteArray()}
	return {"ok": true, "bytes": var_to_bytes(value)}

func _same_bytes(label: String, left, right) -> void:
	var a: Dictionary = _bytes(label + " A", left)
	var b: Dictionary = _bytes(label + " B", right)
	if a.ok and b.ok:
		check(a.bytes == b.bytes, label)

func _item_at(condition: Dictionary, location: String) -> Dictionary:
	for uid in condition.items.keys():
		var item: Dictionary = condition.items[uid]
		if str(item.location) == location:
			return item
	return {}

func _strike(boat: Dictionary, location: String, loss: float, cause: String) -> bool:
	var item: Dictionary = _item_at(boat.moduleCondition, location)
	if item.is_empty():
		check(false, location + " missing before " + cause)
		return false
	var struck: Dictionary = Core.apply_component_damage(boat.moduleCondition, {
		"itemUid": str(item.itemUid),
		"loss": loss,
		"cause": cause
	})
	check(struck.ok, cause + " (" + str(struck.get("error", "ok")) + ")")
	return struck.ok

func _boat(identity: String, fit: Dictionary = STANDARD_FIT, with_locker: bool = true, condition_mounts: bool = true) -> Dictionary:
	var base: Dictionary = world.HULLS[23].duplicate(true)
	var overrides: Dictionary = {"refitLocker": LOCKER.duplicate(true)} if with_locker else {}
	var boat: Dictionary = Damage.create_ship(base, overrides)
	var norm: Dictionary = Refit.normalize(base, fit)
	check(norm.ok, identity + " fit normalizes")
	if not norm.ok:
		return {}
	boat.loadout = norm.loadout
	Refit.ensure(boat, base)
	boat.uid = identity
	boat.id = "player-0-" + identity
	boat.team = "player"
	boat.x = 420.0
	boat.y = 640.0
	boat.vx = 18.0
	boat.vy = 2.0
	boat.angle = 0.15
	var init_res: Dictionary = Records.initialize(boat, {
		"base": base,
		"loadout": boat.loadout,
		"catalog": catalog,
		"identity": identity,
		"knownUids": []
	})
	check(init_res.ok, identity + " Records.initialize")
	var base_mounts: Array = boat.spec.weaponMounts.duplicate(true)
	boat.mounts = EquipmentCombat.apply_mount_condition(boat, base_mounts) if condition_mounts else base_mounts
	return boat

func _arena(ship: Dictionary, islands: Array = [], extra_ships: Array = [], clearance_limit: int = 2900) -> Dictionary:
	var enemy1: Dictionary = {
		"id": "enemy-0-target",
		"team": "enemy",
		"x": 920.0,
		"y": 680.0,
		"vx": -8.0,
		"vy": 0.0,
		"angle": PI,
		"spec": {"size": 18.0},
		"sunk": false
	}
	var enemy2: Dictionary = {
		"id": "enemy-1-secondary",
		"team": "enemy",
		"x": 880.0,
		"y": 500.0,
		"vx": -6.0,
		"vy": 2.0,
		"angle": PI,
		"spec": {"size": 16.0},
		"sunk": false
	}
	var ships_map: Dictionary = {str(ship.id): ship}
	var observed_map: Dictionary = {
		str(ship.id): ship.duplicate(true),
		"enemy-0-target": enemy1,
		"enemy-1-secondary": enemy2
	}
	for other in extra_ships:
		ships_map[str(other.id)] = other
		observed_map[str(other.id)] = other.duplicate(true)
	var geom: Dictionary = Routes.terrain({"islands": islands, "tactical": {}})
	var cells: Dictionary = Routes.grid(observed_map.values())
	return {
		"time": 12.0,
		"islands": islands.duplicate(true),
		"tactical": {
			"ships": ships_map,
			"observed": observed_map,
			"geometry": geom,
			"cells": cells,
			"dt": 1.0 / 30.0,
			"clearanceLimit": clearance_limit
		}
	}

func _default_candidate(ship: Dictionary) -> Dictionary:
	return {
		"candidateId": "cand-" + str(ship.id),
		"shipId": str(ship.id),
		"targetId": "enemy-0-target",
		"approach": [Vector2(560.0, 650.0), Vector2(700.0, 665.0)],
		"pass": [Vector2(820.0, 675.0)],
		"exit": [Vector2(500.0, 760.0)],
		"fireMountIds": ["mount0", "mount1", "mount2", "mount3"]
	}

func _budget(clearance_limit: int = 2900) -> Dictionary:
	return {
		"fullRoutes": 0,
		"cacheHits": 0,
		"rollouts": 1,
		"samples": 0,
		"clearanceTests": 0,
		"exhaustions": 0,
		"rolled": {},
		"clearanceLimit": clearance_limit
	}

func _cert() -> Dictionary:
	return {
		"status": "pending",
		"reason": "Checking a safe route",
		"rolloutSamples": 0
	}

func _assert_prefix_parity(label: String, st: Dictionary, ship: Dictionary, candidate: Dictionary, parts: int, clearance_limit: int = 2900) -> Dictionary:
	var sub_dt: float = (1.0 / 30.0) / float(parts)
	var st_a: Dictionary = st.duplicate(true)
	var st_b: Dictionary = st.duplicate(true)
	var ship_a: Dictionary = ship.duplicate(true)
	var ship_b: Dictionary = ship.duplicate(true)
	st_a.tactical.ships[str(ship_a.id)] = ship_a
	st_b.tactical.ships[str(ship_b.id)] = ship_b
	var cand_a: Dictionary = candidate.duplicate(true)
	var cand_b: Dictionary = candidate.duplicate(true)
	var budget_a: Dictionary = _budget(clearance_limit)
	var budget_b: Dictionary = _budget(clearance_limit)
	var cert_a: Dictionary = _cert()
	var cert_b: Dictionary = _cert()

	var live_st_before: Dictionary = _bytes(label + " live st before", st_a)
	var live_ship_before: Dictionary = _bytes(label + " live ship before", ship_a)
	var live_cand_before: Dictionary = _bytes(label + " live cand before", cand_a)

	var out_a: Dictionary = EquipmentRollout.prefix(st_a, ship_a, cand_a, budget_a, cert_a, sub_dt, parts)
	var out_b: Dictionary = ReferenceRollout.prefix(st_b, ship_b, cand_b, budget_b, cert_b, sub_dt, parts)

	_same_bytes(label + " prefix return var_to_bytes", out_a, out_b)
	_same_bytes(label + " budget var_to_bytes", budget_a, budget_b)
	_same_bytes(label + " cert var_to_bytes", cert_a, cert_b)
	_same_bytes(label + " live st after vs reference", st_a, st_b)
	_same_bytes(label + " live ship after vs reference", ship_a, ship_b)
	_same_bytes(label + " live candidate after vs reference", cand_a, cand_b)

	var live_st_after: Dictionary = _bytes(label + " live st after", st_a)
	var live_ship_after: Dictionary = _bytes(label + " live ship after", ship_a)
	var live_cand_after: Dictionary = _bytes(label + " live cand after", cand_a)
	if live_st_before.ok and live_st_after.ok:
		check(live_st_before.bytes == live_st_after.bytes, label + " live st is immutable")
	if live_ship_before.ok and live_ship_after.ok:
		check(live_ship_before.bytes == live_ship_after.bytes, label + " live ship is immutable")
	if live_cand_before.ok and live_cand_after.ok:
		check(live_cand_before.bytes == live_cand_after.bytes, label + " live candidate is immutable")
	return {"out": out_a, "budget": budget_a, "cert": cert_a}

func _check_source_and_helpers() -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/equipment_rollout.gd")
	check(src.find("for step in range(60):") >= 0 and src.find("for _part in range(parts):") >= 0, "source preserves 60 steps and parts loops")
	check(src.find("Damage._tick_canonical_with(copy,sub_dt,{\"inCombat\":true},prefix_info,prefix_repair,prefix_publish,prefix_absorb,null,prefix_step_status)") >= 0, "source preserves exact Damage._tick_canonical_with call")
	check(src.find("EquipmentCombat._capability_factor_fields(copy,rollout_status,init_mask)") >= 0, "source uses original _capability_factor_fields without mirrored math")
	check(src.find("Core.EPS") < 0 and src.find("EPS") < 0, "source makes no < EPS zero assumption")

	var boat: Dictionary = _boat("inv-helper-unit", STANDARD_FIT, true, false)
	var st_dict: Dictionary = Damage.get_status(boat)
	check(not EquipmentRollout._mounts_conditioned(boat, boat.mounts, st_dict), "raw unconditioned mounts fail _mounts_conditioned")
	boat.mounts = EquipmentCombat.apply_mount_condition(boat, boat.mounts, st_dict)
	check(EquipmentRollout._mounts_conditioned(boat, boat.mounts, st_dict), "conditioned mounts pass _mounts_conditioned")
	var tampered_mounts: Array = boat.mounts.duplicate(true)
	tampered_mounts[0].mountFactor = 0.5
	check(not EquipmentRollout._mounts_conditioned(boat, tampered_mounts, st_dict), "stale mountFactor fails _mounts_conditioned")

	var st_copy: Dictionary = st_dict.duplicate(true)
	st_copy["availableWork"] = 0.0
	st_copy["usedWork"] = 0.0
	st_copy["repairedModuleHp"] = 0.0
	st_copy["moduleChanges"] = []
	check(EquipmentRollout._mount_inputs_same(st_dict, st_copy, true, true, false, false), "identical status/fuel/sunk passes _mount_inputs_same")
	check(not EquipmentRollout._mount_inputs_same(st_dict, st_copy, true, false, false, false), "fuel crossing 0 fails _mount_inputs_same")
	check(not EquipmentRollout._mount_inputs_same(st_dict, st_copy, true, true, false, true), "sinking transition fails _mount_inputs_same")
	for key in ["weaponFactor", "crewGuns", "crewBail", "crewRepair", "engineFactor", "pumpFactor", "armorFactor"]:
		var diff_st: Dictionary = st_copy.duplicate(true)
		diff_st[key] = float(diff_st.get(key, 0.0)) + 0.05
		check(not EquipmentRollout._mount_inputs_same(st_dict, diff_st, true, true, false, false), key + " change fails _mount_inputs_same")
	var wf_diff: Dictionary = st_copy.duplicate(true)
	wf_diff.weaponFactors["mount1"] = 0.55
	check(not EquipmentRollout._mount_inputs_same(st_dict, wf_diff, true, true, false, false), "weaponFactors change fails _mount_inputs_same")
	var eps_work: Dictionary = st_copy.duplicate(true)
	eps_work["availableWork"] = 0.00000001
	check(not EquipmentRollout._mount_inputs_same(st_dict, eps_work, true, true, false, false), "non-zero sub-EPS availableWork fails _mount_inputs_same")

	var ctx: Dictionary = {"owner": boat, "valid": false}
	var info: Dictionary = EquipmentDamage._prefix_ctx_info(boat, ctx)
	var _step_st: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, info, ctx, Damage._status_for_info)
	EquipmentDamage._prefix_tick_scope_begin(ctx)
	var _reused: Dictionary = EquipmentDamage._prefix_ctx_step_status(boat, info, ctx, Damage._status_for_info)
	check(EquipmentRollout._prefix_cond_proof_ready(boat, ctx, st_copy), "armed scope with cond_eq_proof and zero work passes _prefix_cond_proof_ready")
	check(not EquipmentRollout._prefix_cond_proof_ready(boat, ctx, eps_work), "sub-EPS availableWork fails _prefix_cond_proof_ready")
	EquipmentDamage._prefix_drop_cond_proof(ctx)
	check(not EquipmentRollout._prefix_cond_proof_ready(boat, ctx, st_copy), "dropped cond_eq_proof fails _prefix_cond_proof_ready")
	EquipmentDamage._prefix_tick_scope_end(ctx)

func _check_all_prefix_cases() -> void:
	for parts in [1, 2]:
		var tag: String = " [parts=%d]" % parts

		# 1. Healthy canonical boat (pre-conditioned mounts and raw unconditioned mounts).
		var healthy: Dictionary = _boat("inv-healthy-" + str(parts), STANDARD_FIT, true, true)
		var res_healthy: Dictionary = _assert_prefix_parity("healthy conditioned" + tag, _arena(healthy), healthy, _default_candidate(healthy), parts)
		check(bool(res_healthy.out.get("ok", false)) and res_healthy.out.poses.size() == 1 + 60 * parts and res_healthy.out.capabilities.size() == 1 + 60 * parts, "healthy conditioned produces full 60-step prefix" + tag)

		var healthy_raw: Dictionary = _boat("inv-healthy-raw-" + str(parts), STANDARD_FIT, true, false)
		healthy_raw.supplies = 0.0 # Isolate mount conditioning; separate jury cases retain paid repairs.
		_strike(healthy_raw, "mount1", 0.45, "Pre-prefix mount1 damage with unrefreshed mounts")
		Records.publish(healthy_raw)
		var res_raw: Dictionary = _assert_prefix_parity("healthy unrefreshed mounts" + tag, _arena(healthy_raw), healthy_raw, _default_candidate(healthy_raw), parts)
		check(bool(res_raw.out.get("ok", false)) and absf(float(res_raw.out.primary[1].mountFactor) - 0.55) <= 0.0001, "unrefreshed initial mounts are conditioned on first sample" + tag)

		# 2. Fuel crosses 0 mid-prefix (with water > 0 so pump drops to 0.0 at crossing).
		var fuel_cross: Dictionary = _boat("inv-fuel0-" + str(parts), STANDARD_FIT, false, true)
		fuel_cross.fuel = 0.0025
		fuel_cross.water = 14.0
		fuel_cross.supplies = 0.0
		var res_fuel: Dictionary = _assert_prefix_parity("fuel crosses 0" + tag, _arena(fuel_cross), fuel_cross, _default_candidate(fuel_cross), parts)
		check(bool(res_fuel.out.get("ok", false)), "fuel crossing 0 completes prefix" + tag)

		# 3. Active fire aboard (changes weaponFactor, hp, engineHp, and triggers fire suppression).
		var fire_boat: Dictionary = _boat("inv-fire-" + str(parts), STANDARD_FIT, true, true)
		fire_boat.fire = 14.0
		fire_boat.supplies = 12.0
		var res_fire: Dictionary = _assert_prefix_parity("active fire" + tag, _arena(fire_boat), fire_boat, _default_candidate(fire_boat), parts)
		check(bool(res_fire.out.get("ok", false)) and float(res_fire.out.capabilities[-1].fire) != float(res_fire.out.capabilities[0].fire), "active fire evolves across prefix" + tag)

		# 4. Water steady bailing, water-to-zero crew reallocation, breached hull, and mid-prefix sinking.
		var water_steady: Dictionary = _boat("inv-water-steady-" + str(parts), STANDARD_FIT, false, true)
		water_steady.water = 120.0
		water_steady.supplies = 0.0
		var res_water_steady: Dictionary = _assert_prefix_parity("water steady bailing" + tag, _arena(water_steady), water_steady, _default_candidate(water_steady), parts)
		check(bool(res_water_steady.out.get("ok", false)) and float(res_water_steady.out.capabilities[-1].water) > 0.0 and float(res_water_steady.out.capabilities[-1].water) < 120.0, "water steady bailing reduces water while staying > 0" + tag)

		var water_drain: Dictionary = _boat("inv-water-drain-" + str(parts), STANDARD_FIT, false, true)
		water_drain.water = 3.5
		water_drain.supplies = 0.0
		var res_water_drain: Dictionary = _assert_prefix_parity("water drains to zero" + tag, _arena(water_drain), water_drain, _default_candidate(water_drain), parts)
		check(bool(res_water_drain.out.get("ok", false)) and float(res_water_drain.out.capabilities[-1].water) == 0.0, "water drains to 0 mid-prefix" + tag)

		var breached: Dictionary = _boat("inv-breached-" + str(parts), STANDARD_FIT, true, true)
		breached.water = 42.0
		breached.breaches = [{"area": 18.0, "section": "bow"}]
		breached.supplies = 15.0
		var res_breached: Dictionary = _assert_prefix_parity("breached flooding and patching" + tag, _arena(breached), breached, _default_candidate(breached), parts)
		check(bool(res_breached.out.get("ok", false)), "breached hull prefix matches reference via full calculation" + tag)

		var sinking: Dictionary = _boat("inv-sinking-" + str(parts), STANDARD_FIT, false, true)
		sinking.water = float(sinking.capacity) - 10.0
		sinking.fuel = 0.0
		sinking.wounded = float(sinking.crew)
		sinking.breaches = [{"area": 300.0, "section": "waterline"}]
		sinking.supplies = 0.0
		var res_sinking: Dictionary = _assert_prefix_parity("mid-prefix sinking" + tag, _arena(sinking), sinking, _default_candidate(sinking), parts)
		check(bool(res_sinking.out.get("ok", false)) and float(res_sinking.out.capabilities[-1].speedFactor) == 0.0 and float(res_sinking.out.primary[0].damage) == 0.0, "mid-prefix sinking zeros capabilities and mount damage" + tag)

		# 5. Module jury repair (disabled mount0, damaged mount1/pumps/engine repaired during prefix).
		for prio in ["auto", "weapons", "pumps"]:
			var jury: Dictionary = _boat("inv-jury-" + prio + "-" + str(parts), STANDARD_FIT, true, false)
			_strike(jury, "mount0", 0.85, "Disable mount0 for jury repair")
			_strike(jury, "mount1", 0.45, "Damage mount1 for jury repair")
			_strike(jury, "pumps", 0.50, "Damage pumps for jury repair")
			_strike(jury, "engine", 0.45, "Damage engine for jury repair")
			Records.publish(jury)
			Damage.set_repair_priority(jury, prio)
			jury.policy = "repair"
			jury.supplies = 18.0
			jury.mounts = EquipmentCombat.apply_mount_condition(jury, jury.spec.weaponMounts)
			var res_jury: Dictionary = _assert_prefix_parity("module jury repair prio=" + prio + tag, _arena(jury), jury, _default_candidate(jury), parts)
			check(bool(res_jury.out.get("ok", false)) and float(res_jury.out.capabilities[-1].moduleHpSum) > float(res_jury.out.capabilities[0].moduleHpSum), "module jury repair increases moduleHpSum prio=" + prio + tag)

		# 6. Cannon-torpedo mount sets with fireMountTargets filtering and terminal mount-aiming steering.
		var ct_boat: Dictionary = _boat("inv-cannon-torp-" + str(parts), CANNON_TORPEDO_FIT, true, false)
		_strike(ct_boat, "mount0", 0.35, "Cannon partial damage")
		_strike(ct_boat, "mount1", 0.40, "Torpedo partial damage")
		Records.publish(ct_boat)
		Damage.set_repair_priority(ct_boat, "weapons")
		ct_boat.policy = "repair"
		ct_boat.supplies = 15.0
		ct_boat.mounts = EquipmentCombat.apply_mount_condition(ct_boat, ct_boat.spec.weaponMounts)
		var ct_cand: Dictionary = {
			"candidateId": "cand-ct-" + str(parts),
			"shipId": str(ct_boat.id),
			"targetId": "enemy-0-target",
			"approach": [Vector2(430.0, 642.0)],
			"pass": [],
			"exit": [],
			"fireMountIds": ["mount0", "mount1", "mount2"],
			"fireMountTargets": {
				"mount0": "enemy-0-target",
				"mount1": "enemy-0-target",
				"mount2": "enemy-1-secondary"
			}
		}
		var res_ct: Dictionary = _assert_prefix_parity("cannon-torpedo mount set" + tag, _arena(ct_boat), ct_boat, ct_cand, parts)
		check(bool(res_ct.out.get("ok", false)) and res_ct.out.primary.size() == 2, "cannon-torpedo primary_mounts filters to primary target mounts" + tag)

		# 7. Early blocked cases (island sweep block, allied occupied block, clearance budget pending, and legacy boat).
		var blocked_ship: Dictionary = _boat("inv-blocked-island-" + str(parts), STANDARD_FIT, false, true)
		var blocking_islands: Array = [{"points": [[410, 580], [620, 580], [620, 720], [410, 720]]}]
		var res_island: Dictionary = _assert_prefix_parity("early blocked island sweep" + tag, _arena(blocked_ship, blocking_islands), blocked_ship, _default_candidate(blocked_ship), parts)
		check(not bool(res_island.out.get("ok", true)) and str(res_island.cert.get("status", "")) == "blocked" and int(res_island.cert.get("rolloutSamples", 0)) == 10, "island blocks at first 10-step envelope" + tag)

		var occ_ship: Dictionary = _boat("inv-blocked-ally-" + str(parts), STANDARD_FIT, false, true)
		var ally: Dictionary = {
			"id": "player-1-blocker",
			"team": "player",
			"x": 445.0,
			"y": 642.0,
			"vx": 0.0,
			"vy": 0.0,
			"angle": 0.0,
			"spec": {"size": 22.0},
			"sunk": false
		}
		var res_ally: Dictionary = _assert_prefix_parity("early blocked allied occupied" + tag, _arena(occ_ship, [], [ally]), occ_ship, _default_candidate(occ_ship), parts)
		check(not bool(res_ally.out.get("ok", true)) and str(res_ally.cert.get("status", "")) == "blocked", "allied traffic blocks envelope" + tag)

		var pend_ship: Dictionary = _boat("inv-pending-budget-" + str(parts), STANDARD_FIT, false, true)
		var res_pend: Dictionary = _assert_prefix_parity("early pending clearance budget" + tag, _arena(pend_ship, [], [ally], 0), pend_ship, _default_candidate(pend_ship), parts, 0)
		check(not bool(res_pend.out.get("ok", true)) and str(res_pend.cert.get("status", "")) == "pending", "zero clearance limit returns pending" + tag)

		var legacy_base: Dictionary = world.HULLS[0].duplicate(true)
		var legacy_ship: Dictionary = Damage.create_ship(legacy_base)
		Refit.ensure(legacy_ship, legacy_base)
		legacy_ship.id = "player-0-legacy-" + str(parts)
		legacy_ship.team = "player"
		legacy_ship.x = 420.0
		legacy_ship.y = 640.0
		legacy_ship.vx = 14.0
		legacy_ship.mounts = legacy_ship.spec.weaponMounts.duplicate(true)
		var res_leg: Dictionary = _assert_prefix_parity("legacy non-canonical boat" + tag, _arena(legacy_ship), legacy_ship, _default_candidate(legacy_ship), parts)
		check(bool(res_leg.out.get("ok", false)), "legacy boat prefix matches reference" + tag)

func _initialize() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	check(parsed is Dictionary and parsed.get("HULLS") is Array and parsed.HULLS.size() > 23, "world.json parsed with 24 hulls")
	if not (parsed is Dictionary):
		quit(1)
		return
	world = parsed
	catalog = Refit.catalog()
	_check_source_and_helpers()
	_check_all_prefix_cases()
	if failures > 0:
		push_error("prefix_invariants: %d checks, %d failures" % [checks, failures])
		quit(1)
	else:
		print("prefix_invariants: %d checks, 0 failures" % checks)
		quit(0)
