extends RefCounted
## Pure numerical damage. Liters, cm², seconds; fractional crew represent labor.
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const HULL_DAMAGE_SCALE: float = 0.35
const CONSTANTS = {"inflowPerArea":0.055,"bailPerCrew":1.65,"pumpRate":2.3,"patchPerCrew":1.8,"patchSupplyPerArea":0.018,"hullRepairPerCrew":0.22,"hullSupplyPerHp":0.35,"fireGrowthPerSec":0.08,"fireSuppressPerCrew":0.65,"moduleHpPerCrew":0.04,"moduleSuppliesPerHp":{"pumps":1.2,"engines":1.5,"weapons":1.0},"portHullCost":3.0,"portWoundCost":12.0,"portPatchCost":0.6,"portSupplyCost":5.0}
const _UNSET_OWNER: String = "__unset_owner__"

static func number(value, fallback: float = 0.0) -> float:
	if (value is float or value is int) and not (value is bool) and is_finite(float(value)):
		return float(value)
	return fallback

static func create_ship(spec: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var hp: float = maxf(1.0, number(spec.get("hp"),100.0))
	var minimum: float = maxf(0.0,number(spec.get("crewMin"),2.0))
	var optimal: float = maxf(minimum,number(spec.get("crewOptimal"),5.0))
	var maximum: float = maxf(optimal,number(spec.get("crewMax"),optimal+2.0))
	var ship: Dictionary = {"id":spec.get("id","boat"),"type":spec.get("id","boat"),"name":spec.get("name","Boat"),"spec":spec.duplicate(true),"maxHp":hp,"hp":hp,"armor":maxf(0,number(spec.get("armor"))),"crew":optimal,"crewMin":minimum,"crewOptimal":optimal,"crewMax":maximum,"wounded":0.0,"water":0.0,"capacity":maxf(200.0,hp*4.0),"breaches":[],"fire":0.0,"engine":1.0,"supplies":20.0,"ammo":80.0,"fuel":60.0,"sunk":false,"policy":"balanced","x":0.0,"y":0.0,"angle":0.0,"vx":0.0,"vy":0.0,"cooldown":0.0}
	ship.merge(overrides,true)
	ship.spec=spec.duplicate(true)
	ship.breaches=ship.breaches.duplicate(true)
	_sanitize(ship)
	return ship

static func _sanitize(s: Dictionary) -> void:
	s.hp=clampf(number(s.hp),0.0,s.maxHp)
	s.crew=clampf(number(s.crew),0.0,s.crewMax)
	s.wounded=clampf(number(s.wounded),0.0,s.crew)
	s.water=clampf(number(s.water),0.0,s.capacity)
	s.fire=clampf(number(s.fire),0.0,100.0)
	s.engine=clampf(number(s.engine),0.0,1.0)
	for key in ["supplies","ammo","fuel"]:
		s[key]=maxf(0.0,number(s[key]))
	var valid: Array=[]
	for b in s.breaches:
		b.area=maxf(0.0,number(b.area))
		if b.area>0.001:
			valid.append(b)
	s.breaches=valid
	if s.hp<=0.0 or s.water>=s.capacity:
		s.sunk=true

static func sum_areas(s: Dictionary) -> float:
	var total: float=0.0
	for b in s.breaches:
		total+=maxf(0.0,number(b.area))
	return total

static func set_policy(s: Dictionary, policy: String) -> String:
	if policy in ["balanced","bail","repair","fight"]:
		s.policy=policy
	return s.policy

static func set_repair_priority(s: Dictionary, priority: String) -> String:
	var res: Dictionary = EquipmentDamage.set_repair_priority(s, priority)
	if res.ok:
		return str(res.repairPriority)
	if s is Dictionary and s.get("moduleCondition") is Dictionary:
		return str(s.moduleCondition.get("repairPriority", "auto"))
	return "auto"

static func get_status(s: Dictionary) -> Dictionary:
	if not s is Dictionary:
		return EquipmentDamage.status_for({}, 0.0, 0.0, 0.0, [0.5, 0.28, 0.22])
	return _status_for_info(s, EquipmentDamage.inspect_owner(s))

static func _cache_slot_key(s: Dictionary) -> String:
	var id_str: String = str(s.get("id", ""))
	return id_str if not id_str.is_empty() else str(s.get("uid", ""))

static func _find_cache_slot(s: Dictionary, frame_cache: Dictionary) -> String:
	var preferred: String = _cache_slot_key(s)
	if not preferred.is_empty() and frame_cache.has(preferred):
		var fast_entry = frame_cache.get(preferred)
		if fast_entry is Dictionary and is_same(fast_entry.get("shipRef"), s):
			return preferred
	for existing_key in frame_cache.keys():
		var entry = frame_cache.get(existing_key)
		if entry is Dictionary and is_same(entry.get("shipRef"), s):
			return str(existing_key)
	return ""

static func clear_frame_cache(frame_cache) -> void:
	if frame_cache is Dictionary:
		frame_cache.clear()

static func invalidate_frame_cache(frame_cache, s = _UNSET_OWNER) -> void:
	if not (frame_cache is Dictionary) or frame_cache.is_empty():
		return
	if s is String and s == _UNSET_OWNER:
		frame_cache.clear(); return
	if not (s is Dictionary) or s.is_empty():
		return
	for existing_key in frame_cache.keys():
		var entry = frame_cache.get(existing_key)
		if entry is Dictionary and is_same(entry.get("shipRef"), s):
			frame_cache.erase(existing_key)

static func _store_cached_info(s: Dictionary, info: Dictionary, frame_cache) -> void:
	if not (frame_cache is Dictionary) or not (s is Dictionary) or not (info is Dictionary):
		return
	if not bool(info.get("ok", false)) or str(info.get("mode", "")) != "canonical" or not (info.get("snapshot") is Dictionary):
		return
	if not (s.get("moduleCondition") is Dictionary) or not (s.moduleCondition.get("items") is Dictionary) or not (s.get("spec") is Dictionary):
		return
	var slot: String = _find_cache_slot(s, frame_cache)
	if slot.is_empty():
		var preferred: String = _cache_slot_key(s)
		if not preferred.is_empty() and not frame_cache.has(preferred):
			slot = preferred
		else:
			var idx: int = frame_cache.size()
			while frame_cache.has("__ship_%d" % idx):
				idx += 1
			slot = "__ship_%d" % idx
	var cond: Dictionary = s.moduleCondition
	var items: Dictionary = cond.items
	var item_states: Array = []
	for uid in items.keys():
		var item = items[uid]
		if not (item is Dictionary):
			return
		item_states.append({"uid":str(uid),"itemRef":item,"location":str(item.get("location","")),"hp":float(item.get("hp",0.0)),"status":str(item.get("status","")),"typeId":str(item.get("typeId","")),"lockerOrder":int(item.get("lockerOrder",0)),"cause":str(item.get("cause",""))})
	var breaches_val = s.get("breaches", [])
	frame_cache[slot] = {"shipRef":s,"shipKeyCount":s.size(),"conditionRef":cond,"condKeyCount":cond.size(),"itemsRef":items,"itemCount":items.size(),"specRef":s.spec,"specMountCount":s.spec.weaponMounts.size() if s.spec.get("weaponMounts") is Array else -1,"baseSpecRef":s.get("baseSpec"),"loadoutRef":s.get("loadout"),"birthNamespace":str(cond.get("birthNamespace","")),"nextItemSeq":int(cond.get("nextItemSeq",-1)),"repairPriority":str(cond.get("repairPriority","")),"hasLegacyEngineSynced":cond.has("legacyEngineSynced"),"legacyEngineSynced":float(cond.get("legacyEngineSynced",0.0)) if cond.has("legacyEngineSynced") else 0.0,"hasEngineScalar":s.has("engine"),"engineScalar":float(s.get("engine",0.0)) if s.has("engine") else 0.0,"hp":number(s.get("hp")),"maxHp":number(s.get("maxHp"),100.0),"water":number(s.get("water")),"capacity":number(s.get("capacity"),200.0),"fire":number(s.get("fire")),"crew":number(s.get("crew")),"wounded":number(s.get("wounded")),"shoreCrew":number(s.get("shoreCrew",0)),"crewMin":number(s.get("crewMin"),2.0),"crewOptimal":number(s.get("crewOptimal"),5.0),"supplies":number(s.get("supplies")),"sunk":bool(s.get("sunk",false)),"armor":number(s.get("armor")),"policy":str(s.get("policy","balanced")),"supportRepairFactor":number(s.get("supportRepairFactor",1.0),1.0),"breachCount":breaches_val.size() if breaches_val is Array else -1,"breachArea":sum_areas(s) if breaches_val is Array else -1.0,"itemStates":item_states,"info":info}

static func _cache_entry_valid(s: Dictionary, entry: Dictionary) -> bool:
	if not is_same(entry.get("shipRef"), s) or s.size() != int(entry.get("shipKeyCount", -1)): return false
	if not (s.get("moduleCondition") is Dictionary) or not is_same(entry.get("conditionRef"), s.moduleCondition): return false
	if not (s.get("spec") is Dictionary) or not is_same(entry.get("specRef"), s.spec): return false
	var cur_mount_count: int = s.spec.weaponMounts.size() if s.spec.get("weaponMounts") is Array else -1
	if cur_mount_count != int(entry.get("specMountCount", -2)) or not is_same(entry.get("baseSpecRef"), s.get("baseSpec")) or not is_same(entry.get("loadoutRef"), s.get("loadout")): return false
	var cond: Dictionary = s.moduleCondition
	if cond.size() != int(entry.get("condKeyCount", -1)) or not (cond.get("items") is Dictionary) or not is_same(entry.get("itemsRef"), cond.items): return false
	var items: Dictionary = cond.items
	if items.size() != int(entry.get("itemCount", -1)): return false
	if str(cond.get("birthNamespace", "")) != str(entry.get("birthNamespace", "")) or int(cond.get("nextItemSeq", -1)) != int(entry.get("nextItemSeq", -2)) or str(cond.get("repairPriority", "")) != str(entry.get("repairPriority", "")): return false
	var has_sync: bool = cond.has("legacyEngineSynced")
	if has_sync != bool(entry.get("hasLegacyEngineSynced", false)): return false
	if has_sync and (not EquipmentDamage.Core._unit(cond.get("legacyEngineSynced")) or float(cond.get("legacyEngineSynced")) != float(entry.get("legacyEngineSynced", -1.0))): return false
	var has_eng: bool = s.has("engine")
	if has_eng != bool(entry.get("hasEngineScalar", false)): return false
	if has_eng and (not EquipmentDamage.Core._unit(s.get("engine")) or float(s.get("engine")) != float(entry.get("engineScalar", -1.0))): return false
	if number(s.get("hp"), NAN) != float(entry.get("hp", -1.0)) or number(s.get("maxHp"), NAN) != float(entry.get("maxHp", -1.0)): return false
	if number(s.get("water"), NAN) != float(entry.get("water", -1.0)) or number(s.get("capacity"), NAN) != float(entry.get("capacity", -1.0)): return false
	if number(s.get("fire"), NAN) != float(entry.get("fire", -1.0)) or number(s.get("supplies"), NAN) != float(entry.get("supplies", -1.0)): return false
	if number(s.get("crew"), NAN) != float(entry.get("crew", -1.0)) or number(s.get("wounded"), NAN) != float(entry.get("wounded", -1.0)) or number(s.get("shoreCrew", 0), NAN) != float(entry.get("shoreCrew", -1.0)): return false
	if number(s.get("crewMin"), NAN) != float(entry.get("crewMin", -1.0)) or number(s.get("crewOptimal"), NAN) != float(entry.get("crewOptimal", -1.0)): return false
	if bool(s.get("sunk", false)) != bool(entry.get("sunk", false)) or number(s.get("armor"), NAN) != float(entry.get("armor", -1.0)): return false
	if str(s.get("policy", "balanced")) != str(entry.get("policy", "")) or number(s.get("supportRepairFactor", 1.0), NAN) != float(entry.get("supportRepairFactor", -1.0)): return false
	var breaches_val = s.get("breaches", [])
	if not (breaches_val is Array) or breaches_val.size() != int(entry.get("breachCount", -1)) or sum_areas(s) != float(entry.get("breachArea", -1.0)): return false
	for st_item in entry.get("itemStates", []):
		var uid: String = str(st_item.uid)
		if not items.has(uid): return false
		var item = items[uid]
		if not (item is Dictionary) or not is_same(st_item.itemRef, item): return false
		if float(item.get("hp", -1.0)) != float(st_item.hp) or str(item.get("status", "")) != str(st_item.status) or str(item.get("location", "")) != str(st_item.location) or str(item.get("typeId", "")) != str(st_item.typeId) or int(item.get("lockerOrder", -1)) != int(st_item.lockerOrder) or str(item.get("cause", "")) != str(st_item.cause): return false
	return true

static func _cached_info_or_empty(s, frame_cache) -> Dictionary:
	if not (frame_cache is Dictionary) or frame_cache.is_empty() or not (s is Dictionary): return {}
	var slot: String = _find_cache_slot(s, frame_cache)
	if slot.is_empty(): return {}
	var entry = frame_cache.get(slot)
	if not (entry is Dictionary) or not is_same(entry.get("shipRef"), s): return {}
	if not _cache_entry_valid(s, entry):
		frame_cache.erase(slot); return {}
	return entry.get("info", {})

static func inspect_owner_cached(s = null, frame_cache = null) -> Dictionary:
	if not (s is Dictionary) or s.is_empty(): return {"ok": false, "mode": "invalid", "needsInitialize": false, "error": "Boat must be a dictionary."}
	var cached: Dictionary = _cached_info_or_empty(s, frame_cache)
	if not cached.is_empty(): return cached
	return EquipmentDamage.inspect_owner(s)

static func get_status_cached(s = null, frame_cache = null) -> Dictionary:
	if not (s is Dictionary) or s.is_empty():
		var invalid: Dictionary = {"ok":false,"mode":"invalid","needsInitialize":false,"error":"A nonempty boat dictionary is required."}
		return EquipmentDamage._status_from_info({},0.0,0.0,0.0,[0.5,0.28,0.22],invalid)
	return _status_for_info(s, inspect_owner_cached(s, frame_cache))

static func _get_status_numeric(s: Dictionary) -> Dictionary:
	return _status_for_info(s, EquipmentDamage._numeric_info(s))

static func _status_for_info(s: Dictionary, info: Dictionary) -> Dictionary:
	if str(info.get("mode", "invalid")) == "invalid":
		return EquipmentDamage._status_from_info(s, 0.0, 0.0, 0.0, [0.5, 0.28, 0.22], info)
	var able: float=maxf(0.0,number(s.get("crew"))-number(s.get("wounded"))-maxf(0.0,number(s.get("shoreCrew",0))))
	var area: float=sum_areas(s)
	var cap: float=maxf(1.0,number(s.get("capacity"),200.0))
	var inflow: float=area*CONSTANTS.inflowPerArea*(1.0+number(s.get("water"))/cap*0.45)
	var weights: Array={"balanced":[0.5,0.28,0.22],"bail":[0.15,0.65,0.2],"repair":[0.15,0.2,0.65],"fight":[0.85,0.1,0.05]}.get(s.get("policy","balanced"),[0.5,0.28,0.22])
	return EquipmentDamage._status_from_info(s, able, area, inflow, weights, info)

static func _roll(rng: RandomNumberGenerator) -> float:
	# No global RNG state: callers normally supply their battle-owned seeded RNG.
	if rng!=null:
		return rng.randf()
	var local: RandomNumberGenerator=RandomNumberGenerator.new()
	local.randomize()
	return local.randf()

static func apply_hit(s: Dictionary, hit: Dictionary, rng: RandomNumberGenerator = null, frame_cache = null) -> Array:
	var events: Array=[]
	invalidate_frame_cache(frame_cache, s)
	if not s is Dictionary or not hit is Dictionary:
		return events
	var info: Dictionary = EquipmentDamage.inspect_owner(s)
	var mode: String = str(info.get("mode", "invalid"))
	if mode == "invalid":
		return events
	if s.get("sunk", false):
		return events
	var raw: float=maxf(0.0,number(hit.get("damage")))
	if raw<=0.0:
		return events
	if mode == "canonical":
		var has_world_hit: bool = hit.has("impactX") or hit.has("impactY")
		var has_local_hit: bool = hit.has("localX") or hit.has("localY")
		if has_world_hit and has_local_hit:
			return events
		if has_world_hit and (not hit.has("impactX") or not hit.has("impactY") or not EquipmentDamage.Core._number(hit.get("impactX")) or not EquipmentDamage.Core._number(hit.get("impactY"))):
			return events
		if has_local_hit and (not hit.has("localX") or not hit.has("localY") or not EquipmentDamage.Core._number(hit.get("localX")) or not EquipmentDamage.Core._number(hit.get("localY"))):
			return events
		if hit.has("blastRadius") and (not EquipmentDamage.Core._number(hit.get("blastRadius")) or float(hit.get("blastRadius")) < 0.0):
			return events
		var absorbed: Dictionary = EquipmentDamage.Records.absorb_legacy_damage(s)
		if not absorbed.ok:
			return events
		var snap: Dictionary = EquipmentDamage.Records.snapshot(s)
		if not snap.ok:
			return events
		var kind_can: String=str(hit.get("kind","bullet"))
		var explosive_can: bool=kind_can=="torpedo"
		var rocket_can: bool=kind_can=="rocket"
		var shell_can: bool=kind_can in ["shell","ram"]
		var eff_armor: float=maxf(0.0,number(s.get("armor")))*float(snap.get("armorFactor",1.0))
		var armor_can: float=maxf(0.0,eff_armor-maxf(0.0,number(hit.get("penetration"))))
		var impact_can: float=maxf(raw*0.22,raw-armor_can*(0.3 if explosive_can else 0.8))
		var damage_can: float=impact_can*HULL_DAMAGE_SCALE
		s.hp-=damage_can
		events.append("Hull hit: %.1f HP"%damage_can)
		var chance_can: float=1.0 if explosive_can else (0.8 if rocket_can else (0.72 if shell_can else 0.3))
		if _roll(rng)<chance_can:
			var area_can: float=impact_can*(5.0 if explosive_can else (1.35 if rocket_can else (1.1 if shell_can else 0.45)))
			s.breaches.append({"area":area_can,"section":"waterline" if explosive_can else str(hit.get("section","bow"))})
			events.append("Breach: %.1f cm²"%area_can)
		var mach_roll: float = _roll(rng)
		var comp_res: Dictionary = EquipmentDamage.apply_hit_equipment(s, hit, impact_can, mach_roll)
		if comp_res.ok:
			for ev in comp_res.get("events", []):
				events.append(str(ev))
		if _roll(rng)<(0.35 if explosive_can else (0.75 if rocket_can else (0.2 if kind_can=="shell" else 0.05))) or rocket_can or hit.get("incendiary",false):
			s.fire+=minf(32.0,4.0+impact_can*0.55) if rocket_can else minf(28.0,impact_can*0.55)
			events.append("Fire aboard")
		if _roll(rng)<minf(0.4,impact_can/s.maxHp*(1.8 if explosive_can else 0.65)):
			if s.wounded>=1.0 and _roll(rng)<0.18:
				s.crew-=1.0
				s.wounded-=1.0
				events.append("One crew lost")
			elif s.crew-s.wounded>=1.0:
				s.wounded+=1.0
				events.append("One crew wounded")
		_sanitize(s)
		EquipmentDamage.Records.publish(s)
		invalidate_frame_cache(frame_cache, s)
		if s.sunk:
			events.append("Ship sunk")
		return events

	var kind: String=hit.get("kind","bullet")
	var explosive: bool=kind=="torpedo"
	var rocket: bool=kind=="rocket"
	var shell: bool=kind in ["shell","ram"]
	var armor: float=maxf(0.0,s.armor-maxf(0.0,number(hit.get("penetration"))))
	var impact: float=maxf(raw*0.22,raw-armor*(0.3 if explosive else 0.8))
	var damage: float=impact*HULL_DAMAGE_SCALE
	s.hp-=damage
	events.append("Hull hit: %.1f HP"%damage)
	var chance: float=1.0 if explosive else (0.8 if rocket else (0.72 if shell else 0.3))
	if _roll(rng)<chance:
		var area: float=impact*(5.0 if explosive else (1.35 if rocket else (1.1 if shell else 0.45)))
		s.breaches.append({"area":area,"section":"waterline" if explosive else hit.get("section","bow")})
		events.append("Breach: %.1f cm²"%area)
	if _roll(rng)<(0.65 if hit.get("section","")=="engine" else (0.4 if explosive else 0.09)):
		s.engine-=minf(0.35,impact/s.maxHp*0.7)
		events.append("Engine damaged")
	if _roll(rng)<(0.35 if explosive else (0.75 if rocket else (0.2 if kind=="shell" else 0.05))) or rocket or hit.get("incendiary",false):
		s.fire+=minf(32.0,4.0+impact*0.55) if rocket else minf(28.0,impact*0.55)
		events.append("Fire aboard")
	if _roll(rng)<minf(0.4,impact/s.maxHp*(1.8 if explosive else 0.65)):
		if s.wounded>=1.0 and _roll(rng)<0.18:
			s.crew-=1.0
			s.wounded-=1.0
			events.append("One crew lost")
		elif s.crew-s.wounded>=1.0:
			s.wounded+=1.0
			events.append("One crew wounded")
	_sanitize(s)
	invalidate_frame_cache(frame_cache, s)
	if s.sunk:
		events.append("Ship sunk")
	return events

static func _healthy_canonical_no_work(s: Dictionary, info: Dictionary) -> bool:
	# Called only after fresh owner inspection and the public context's alias/type guards.
	# No proof survives this synchronous tick; damaged or malformed owners use the old path.
	if not bool(info.get("ok", false)) or str(info.get("mode", "")) != "canonical":
		return false
	if not (s.get("sunk") is bool) or s.sunk or not (s.get("breaches") is Array) or not s.breaches.is_empty():
		return false
	if not (s.get("spec") is Dictionary) or not (s.get("policy", "balanced") in ["balanced", "bail", "repair", "fight"]):
		return false
	for key in ["hp", "maxHp", "water", "capacity", "fire", "engine", "crew", "wounded", "crewMin", "crewOptimal", "crewMax", "supplies", "ammo", "fuel", "cooldown", "armor"]:
		if not EquipmentDamage.Core._number(s.get(key)) or float(s[key]) < 0.0:
			return false
	if not EquipmentDamage.Core._number(s.get("vx")) or not EquipmentDamage.Core._number(s.get("vy")):
		return false
	if s.maxHp < 1.0 or s.hp != s.maxHp or s.capacity < 1.0 or s.water != 0.0 or s.fire != 0.0 or s.wounded != 0.0 or s.engine != 1.0:
		return false
	if s.crewMin > s.crewOptimal or s.crewOptimal > s.crewMax or s.crew > s.crewMax:
		return false
	if s.has("shoreCrew") and (not EquipmentDamage.Core._number(s.shoreCrew) or float(s.shoreCrew) < 0.0 or float(s.shoreCrew) > float(s.crew)):
		return false
	if float(s.moduleCondition.get("legacyEngineSynced", -1.0)) != 1.0:
		return false
	for item in s.moduleCondition.items.values():
		if float(item.hp) != 1.0 or str(item.status) != "ok":
			return false
	return true

static func tick_ship(s: Dictionary, dt: float, _options: Dictionary = {}, frame_cache = null) -> Dictionary:
	invalidate_frame_cache(frame_cache, s)
	if not s is Dictionary:
		return get_status({})
	var info: Dictionary = EquipmentDamage.inspect_owner(s)
	var mode: String = str(info.get("mode", "invalid"))
	if mode == "invalid":
		return get_status(s)
	dt=maxf(0.0,number(dt))
	var total_in: float=0.0
	var total_bail: float=0.0
	var total_repair: float=0.0
	var elapsed: float=0.0
	var events: Array=[]

	if mode == "canonical":
		var out_info = {} if frame_cache is Dictionary else null
		var tick_ctx: Dictionary = EquipmentDamage._make_public_tick_context(s, info, _options, frame_cache)
		var status_can: Dictionary = (
			_tick_canonical_with(
				s,
				dt,
				_options,
				EquipmentDamage._tick_status_public_local.bind(tick_ctx),
				EquipmentDamage._tick_repair_public_local_from_info.bind(tick_ctx),
				EquipmentDamage._tick_publish_public_local.bind(tick_ctx),
				EquipmentDamage._tick_absorb_public_local.bind(tick_ctx),
				out_info,
				null,
				_healthy_canonical_no_work(s, info)
			)
			if bool(tick_ctx.get("eligible", false))
			else _tick_canonical_with(
				s,
				dt,
				_options,
				EquipmentDamage.inspect_owner,
				EquipmentDamage._tick_repair_step_from_info,
				EquipmentDamage.Records.publish,
				EquipmentDamage.Records.absorb_legacy_damage,
				out_info
			)
		)
		if frame_cache is Dictionary and bool(status_can.get("equipmentOk", false)):
			_store_cached_info(s, out_info.get("info", {}), frame_cache)
		return status_can

	while dt>0.00000001 and not s.sunk:
		var h: float=minf(0.25,dt)
		var t: Dictionary=get_status(s)
		var before: float=s.water
		s.water=clampf(s.water+(t.inflow-t.bailing)*h,0.0,s.capacity)
		total_in+=t.inflow*h
		total_bail+=minf(t.bailing*h,before+t.inflow*h)
		var patch: float=minf(sum_areas(s),minf(t.repair*h,s.supplies/CONSTANTS.patchSupplyPerArea))
		var left: float=patch
		for b in s.breaches:
			var amount: float=minf(b.area,left)
			b.area-=amount
			left-=amount
		s.supplies-=patch*CONSTANTS.patchSupplyPerArea
		total_repair+=patch
		if sum_areas(s)<0.001 and s.policy=="repair" and s.supplies>0.0:
			var hull: float=minf(s.maxHp-s.hp,minf(t.crewRepair*CONSTANTS.hullRepairPerCrew*h*maxf(maxf(1,float(s.spec.get("repairFactor",1))),float(s.get("supportRepairFactor",1))),s.supplies/CONSTANTS.hullSupplyPerHp))
			s.hp+=hull
			s.supplies-=hull*CONSTANTS.hullSupplyPerHp
		if s.fire>0.0:
			s.hp-=s.fire*0.003*h
			s.engine-=s.fire*0.000025*h
			s.fire=clampf(s.fire+(0.08-t.crewRepair*0.65)*h,0.0,100.0)
		if s.fuel>0.0 and (s.water>0.0 or absf(s.vx)+absf(s.vy)>1.0):
			s.fuel-=0.006*h
		s.cooldown=maxf(0.0,number(s.cooldown)-h)
		_sanitize(s)
		dt-=h
		elapsed+=h
		if s.sunk:
			events.append("Ship sunk")
	var status: Dictionary=get_status(s)
	if elapsed>0.0:
		status.inflow=total_in/elapsed
		status.bailing=total_bail/elapsed
		status.repair=total_repair/elapsed
	status.events=events
	return status


static func _tick_canonical_numeric(s: Dictionary, dt: float, options: Dictionary) -> Dictionary:
	return _tick_canonical_with(s, dt, options, EquipmentDamage._numeric_rollout_info, EquipmentDamage._tick_repair_rollout_from_info, EquipmentDamage.Records._publish_numeric, EquipmentDamage.Records._absorb_legacy_numeric)

static func _tick_canonical_with(s: Dictionary, dt: float, _options: Dictionary, status_fn: Callable, repair_fn: Callable, publish_fn: Callable, absorb_fn: Callable, out_info = null, step_status_fn = null, healthy_no_work: bool = false) -> Dictionary:
	var total_in: float=0.0
	var total_bail: float=0.0
	var total_repair: float=0.0
	var elapsed: float=0.0
	var events: Array=[]
	if _options is Dictionary and _options.has("priority") and not str(_options.get("priority")) in EquipmentDamage.Core.PRIORITIES:
		var bad_info: Dictionary = status_fn.call(s)
		if out_info is Dictionary:
			out_info["info"] = bad_info
		var bad_status: Dictionary = _status_for_info(s, bad_info)
		bad_status.equipmentOk = false
		bad_status.equipmentError = "Repair priority is unknown."
		return bad_status
	var absorbed: Dictionary = absorb_fn.call(s)
	if not absorbed.ok:
		var absorbed_info: Dictionary = status_fn.call(s)
		if out_info is Dictionary:
			out_info["info"] = absorbed_info
		return _status_for_info(s, absorbed_info)
	healthy_no_work = healthy_no_work and not bool(absorbed.get("changed", false))
	publish_fn.call(s)
	var total_avail_work: float = 0.0
	var total_used_work: float = 0.0
	var total_used_supplies: float = 0.0
	var total_hull_hp: float = 0.0
	var total_module_hp: float = 0.0
	var total_fire_supp: float = 0.0
	var work_by_task: Dictionary = EquipmentDamage.empty_task_map()
	var supplies_by_task: Dictionary = EquipmentDamage.empty_task_map()
	var module_changes: Array = []
	var step_cap: float = 1.0 / 60.0
	while dt>0.00000001 and not s.sunk:
		var h_can: float = dt if dt <= step_cap + 0.0000001 else step_cap
		if absf(dt - 2.0 * step_cap) <= 0.0000001:
			h_can = dt * 0.5
		if not healthy_no_work:
			var step_info: Dictionary = status_fn.call(s)
			var t_can: Dictionary = step_status_fn.call(s, step_info) if step_status_fn is Callable and step_status_fn.is_valid() else _status_for_info(s, step_info)
			var before_can: float = s.water
			s.water = clampf(s.water + (t_can.inflow - t_can.bailing) * h_can, 0.0, s.capacity)
			total_in += t_can.inflow * h_can
			total_bail += minf(t_can.bailing * h_can, before_can + t_can.inflow * h_can)
			var step_res: Dictionary = repair_fn.call(s, h_can, float(t_can.crewRepair), _options if _options is Dictionary else {}, step_info)
			if not step_res.ok:
				break
			total_repair += float(step_res.patchedArea)
			total_avail_work += float(step_res.availableWork)
			total_used_work += float(step_res.usedWork)
			total_used_supplies += float(step_res.usedSupplies)
			total_hull_hp += float(step_res.repairedHullHp)
			total_module_hp += float(step_res.repairedModuleHp)
			total_fire_supp += float(step_res.suppressedFire)
			for k in ["fire", "patch", "machinery", "hull"]:
				work_by_task[k] = float(work_by_task[k]) + float(step_res.workByTask[k])
				supplies_by_task[k] = float(supplies_by_task[k]) + float(step_res.suppliesByTask[k])
			for ch in step_res.moduleChanges:
				module_changes.append(ch)
		else:
			# Retain the zero-flow water write, including normalization of signed zero.
			s.water = clampf(s.water + 0.0, 0.0, s.capacity)
		if s.fuel>0.0 and (s.water>0.0 or absf(s.vx)+absf(s.vy)>1.0):
			s.fuel-=0.006*h_can
		s.cooldown=maxf(0.0,number(s.cooldown)-h_can)
		# Equipment publication set engine. Sanitize cannot change condition or locker counts.
		var published_engine: float = float(s.engine)
		_sanitize(s)
		s.engine = published_engine
		dt-=h_can
		elapsed+=h_can
		if s.sunk:
			events.append("Ship sunk")
	if healthy_no_work and elapsed > 0.0:
		# The no-work steps still finish by publishing the real equipment projection.
		publish_fn.call(s)
	var final_info: Dictionary = status_fn.call(s)
	if out_info is Dictionary:
		out_info["info"] = final_info
	var status_can: Dictionary = _status_for_info(s, final_info)
	if elapsed>0.0:
		status_can.inflow=total_in/elapsed
		status_can.bailing=total_bail/elapsed
		status_can.repair=total_repair/elapsed
	status_can.availableWork = total_avail_work
	status_can.usedWork = total_used_work
	status_can.usedSupplies = total_used_supplies
	status_can.workByTask = work_by_task
	status_can.suppliesByTask = supplies_by_task
	status_can.repairedPatchArea = total_repair
	status_can.repairedHullHp = total_hull_hp
	status_can.repairedModuleHp = total_module_hp
	status_can.suppressedFire = total_fire_supp
	status_can.moduleChanges = module_changes
	status_can.events = events
	return status_can

static func repair_at_port(s: Dictionary, budget: float) -> Dictionary:
	if EquipmentDamage.is_corrupt_owner(s):
		return {"cost":0,"repaired":false,"error":"Existing equipment condition is corrupt and was left untouched."}
	if EquipmentDamage.is_canonical_owner(s):
		return {"cost":0,"repaired":false,"error":"Canonical equipment requires paid harbor service."}
	budget=maxf(0.0,floor(number(budget)))
	if s.sunk:
		return {"cost":0,"repaired":false,"error":"A sunk boat cannot be serviced."}
	var cost: int=0
	var areas: float=sum_areas(s)
	var services: Array=[ ["breaches",areas,0.6],["hp",s.maxHp-s.hp,3.0],["wounded",s.wounded,12.0],["engine",1.0-s.engine,80.0],["fire",s.fire,0.5],["water",s.water,0.02],["supplies",20.0-s.supplies,5.0] ]
	for service in services:
		var amount: float=minf(maxf(0.0,service[1]),(budget-cost)/service[2])
		if amount<=0.0:
			continue
		cost+=mini(int(budget)-cost,int(ceil(amount*service[2]-0.000000001)))
		var key: String=service[0]
		if key=="breaches":
			for b in s.breaches:
				var part: float=minf(amount,b.area)
				b.area-=part
				amount-=part
		elif key in ["hp","engine","supplies"]:
			s[key]+=amount
		else:
			s[key]-=amount
	_sanitize(s)
	return {"cost":cost,"repaired":cost>0}
