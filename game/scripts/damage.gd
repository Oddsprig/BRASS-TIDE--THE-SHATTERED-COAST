extends RefCounted
## Pure numerical damage. Liters, cm², seconds; fractional crew represent labor.
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const HULL_DAMAGE_SCALE: float = 0.35
const CONSTANTS = {"inflowPerArea":0.055,"bailPerCrew":1.65,"pumpRate":2.3,"patchPerCrew":1.8,"patchSupplyPerArea":0.018,"hullRepairPerCrew":0.22,"hullSupplyPerHp":0.35,"fireGrowthPerSec":0.08,"fireSuppressPerCrew":0.65,"moduleHpPerCrew":0.04,"moduleSuppliesPerHp":{"pumps":1.2,"engines":1.5,"weapons":1.0},"portHullCost":3.0,"portWoundCost":12.0,"portPatchCost":0.6,"portSupplyCost":5.0}
const _UNSET_OWNER: String = "__unset_owner__"
const OWNER_CACHE_FRAMES: int = 12 # At most 0.2s at the live 60Hz rate.
const OWNER_CACHE_LIMIT: int = 128

# Runtime object owned by one encounter, outside boats and campaign saves.
# Binding both containers prevents a duplicated battle borrowing its proof.
class BattleOwned051:
	extends RefCounted
	var ships: Array = []
	var source: Dictionary = {}
	var entries: Dictionary = {}
	var active: bool = true
	var admitted: bool = false

# Battle owns this local handle only from its damage/mount prepass through fire.
# It is closed before boarding/contact/projectile writes and never stored on st.
class BattlePhase043:
	extends RefCounted
	var source: Dictionary = {}
	var entries: Dictionary = {}
	var active: bool = true
	var owned = null
	var readsSealed051: bool = false

# Opt-in, process-local diagnostics only. Never retained in a boat or battle.
static var _runtime_profile043_enabled: bool = false
static var _runtime_profile043_counts: Dictionary = {"cacheFrames":0,"cacheLookups":0,"cacheHits":0,"cacheMisses":0,"unavailableMisses":0,"missingOwnerMisses":0,"invalidEntryMisses":0,"ownerIdentityMisses":0,"valueMisses":0,"expiryMisses":0,"expiryEvictions":0,"ownerIdentityEvictions":0,"explicitEvictions":0,"limitEvictions":0,"cacheStores":0,"phaseLookups":0,"phaseHits":0}

static func set_runtime_profile043(enabled: bool) -> void:
	_runtime_profile043_enabled = enabled
	EquipmentDamage.Records.set_runtime_profile043(enabled)

static func reset_runtime_profile043() -> void:
	for key in _runtime_profile043_counts: _runtime_profile043_counts[key] = 0
	EquipmentDamage.Records.reset_runtime_profile043()

static func runtime_profile043() -> Dictionary:
	return {"schema":1,"enabled":_runtime_profile043_enabled,"cache":_runtime_profile043_counts.duplicate(true),"equipmentSnapshots":EquipmentDamage.Records.runtime_profile043()}

static func _runtime_profile043_miss(reason: String) -> void:
	_runtime_profile043_counts.cacheMisses += 1
	_runtime_profile043_counts[reason] += 1

static func _runtime_profile043_rejection(s: Dictionary, entry: Dictionary) -> String:
	# Classify only an already rejected entry; never decide cache eligibility.
	# Identity takes priority if several independent causes changed together.
	if not is_same(entry.get("shipRef"),s) or [s.get("id"),s.get("uid"),s.get("type")] != entry.get("identity",[]): return "ownerIdentityMisses"
	for pair in [["conditionRef","moduleCondition"],["specRef","spec"],["baseSpecRef","baseSpec"],["loadoutRef","loadout"]]:
		if not is_same(entry.get(pair[0]),s.get(pair[1])): return "ownerIdentityMisses"
	if int(entry.get("framesLeft",0)) <= 0: return "expiryMisses"
	return "valueMisses"

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
	if frame_cache is BattlePhase043:
		_close_battle_owned051(frame_cache.owned)
		frame_cache = frame_cache.source
	if frame_cache is Dictionary:
		if _runtime_profile043_enabled: _runtime_profile043_counts.explicitEvictions += frame_cache.size()
		frame_cache.clear()

static func invalidate_frame_cache(frame_cache, s = _UNSET_OWNER) -> void:
	if frame_cache is BattlePhase043:
		if s is Dictionary: _drop_battle_owner051(frame_cache.owned,s)
		else: _close_battle_owned051(frame_cache.owned)
		frame_cache = frame_cache.source
	if not (frame_cache is Dictionary) or frame_cache.is_empty():
		return
	if s is String and s == _UNSET_OWNER:
		if _runtime_profile043_enabled: _runtime_profile043_counts.explicitEvictions += frame_cache.size()
		frame_cache.clear(); return
	if not (s is Dictionary) or s.is_empty():
		return
	for existing_key in frame_cache.keys():
		var entry = frame_cache.get(existing_key)
		if entry is Dictionary and is_same(entry.get("shipRef"), s):
			if _runtime_profile043_enabled: _runtime_profile043_counts.explicitEvictions += 1
			frame_cache.erase(existing_key)

static func begin_frame_cache(frame_cache: Dictionary, ships: Array) -> void:
	# Battle owns this cache. No proof survives twelve physics frames or an owner
	# leaving the encounter, even when all of its values are unchanged.
	if _runtime_profile043_enabled: _runtime_profile043_counts.cacheFrames += 1
	var live: Dictionary = {}
	for ship in ships:
		if ship is Dictionary and not ship.get("sunk", false):
			live[_cache_slot_key(ship)] = ship
	for slot in frame_cache.keys():
		var entry: Dictionary = frame_cache[slot]
		entry.framesLeft = int(entry.get("framesLeft", 0)) - 1
		if int(entry.framesLeft) <= 0 or not is_same(live.get(_cache_slot_key(entry.shipRef)), entry.shipRef):
			if _runtime_profile043_enabled:
				if int(entry.framesLeft) <= 0:
					_runtime_profile043_counts.expiryEvictions += 1
				else: _runtime_profile043_counts.ownerIdentityEvictions += 1
			frame_cache.erase(slot)

static func _status_inputs(s: Dictionary) -> Array:
	# Fuel magnitude does not affect status; crossing zero does. Cooldowns,
	# ammunition and pose are live inputs to firing/motion, not this projection.
	return [s.get("hp"),s.get("maxHp"),s.get("water"),s.get("capacity"),s.get("fire"),s.get("crew"),s.get("wounded"),s.get("shoreCrew",0),s.get("crewMin"),s.get("crewOptimal"),s.get("crewMax"),s.get("supplies"),number(s.get("fuel"))>0.0,s.get("sunk"),s.get("armor"),s.get("policy","balanced"),s.get("supportRepairFactor",1.0),s.get("breaches",[])]

static func _freeze_status(status: Dictionary) -> Dictionary:
	# Internal readers borrow this immutable projection. Public get_status_cached
	# returns a detached copy, so callers cannot poison a subsequent live read.
	for value in status.values():
		if value is Dictionary or value is Array:
			value.make_read_only()
	status.make_read_only()
	return status

static func _store_cached_info(s: Dictionary, info: Dictionary, frame_cache) -> void:
	if frame_cache is BattlePhase043: frame_cache = frame_cache.source
	if not (frame_cache is Dictionary) or not (s is Dictionary) or not (info is Dictionary): return
	if not bool(info.get("ok", false)) or str(info.get("mode", "")) != "canonical" or not (info.get("snapshot") is Dictionary): return
	if not (s.get("moduleCondition") is Dictionary) or not (s.get("spec") is Dictionary): return
	var slot: String = _find_cache_slot(s, frame_cache)
	if slot.is_empty():
		var preferred: String = _cache_slot_key(s)
		if not preferred.is_empty() and not frame_cache.has(preferred): slot = preferred
		else:
			var idx: int = frame_cache.size()
			while frame_cache.has("__ship_%d" % idx): idx += 1
			slot = "__ship_%d" % idx
	if not frame_cache.has(slot) and frame_cache.size() >= OWNER_CACHE_LIMIT:
		if _runtime_profile043_enabled: _runtime_profile043_counts.limitEvictions += 1
		frame_cache.erase(frame_cache.keys()[0])
	var cond: Dictionary = s.moduleCondition
	var snap: Dictionary = info.snapshot
	# Native deep equality against detached values replaces dozens of GDScript
	# validation/reconstruction calls. These are exact comparisons, not hashes.
	frame_cache[slot] = {"shipRef":s,"shipKeys":s.keys(),"conditionRef":cond,"conditionValue":cond.duplicate(true),"specRef":s.spec,"specValue":s.spec.duplicate(true),"baseSpecRef":s.get("baseSpec"),"baseSpecValue":s.baseSpec.duplicate(true) if s.get("baseSpec") is Dictionary else s.get("baseSpec"),"loadoutRef":s.get("loadout"),"loadoutValue":s.loadout.duplicate(true) if s.get("loadout") is Dictionary else s.get("loadout"),"engineScalar":s.get("engine"),"identity":[s.get("id"),s.get("uid"),s.get("type")],"info":info,"framesLeft":OWNER_CACHE_FRAMES,"statusInputs":_status_inputs(s).duplicate(true),"status":_freeze_status(_status_for_info(s,info)),"healthy":_healthy_canonical_no_work(s,info) and EquipmentDamage._public_tick_context_eligible(s,info,{},frame_cache),"projection":{"hasEngine":snap.installed.has("engine"),"engineHp":snap.engineHp,"refitLocker":s.get("refitLocker",{}).duplicate(true)}}
	if _runtime_profile043_enabled: _runtime_profile043_counts.cacheStores += 1

static func _cache_entry_valid(s: Dictionary, entry: Dictionary) -> bool:
	if not is_same(entry.get("shipRef"), s) or s.keys() != entry.get("shipKeys", []): return false
	if [s.get("id"),s.get("uid"),s.get("type")] != entry.get("identity", []): return false
	if not (s.get("moduleCondition") is Dictionary) or not is_same(entry.get("conditionRef"),s.moduleCondition) or s.moduleCondition != entry.get("conditionValue"): return false
	if not (s.get("spec") is Dictionary) or not is_same(entry.get("specRef"),s.spec) or s.spec != entry.get("specValue"): return false
	if not is_same(entry.get("baseSpecRef"),s.get("baseSpec")) or s.get("baseSpec") != entry.get("baseSpecValue"): return false
	if not is_same(entry.get("loadoutRef"),s.get("loadout")) or s.get("loadout") != entry.get("loadoutValue"): return false
	if not EquipmentDamage.Core._unit(s.get("engine")) or s.get("engine") != entry.get("engineScalar"): return false
	return int(entry.get("framesLeft",0)) > 0

static func _cached_entry(s, frame_cache) -> Dictionary:
	# Public APIs retain their full owner/value guard, even if given the handle.
	if frame_cache is BattlePhase043:
		if s is Dictionary: _drop_battle_owner051(frame_cache.owned,s)
		frame_cache = frame_cache.source
	if _runtime_profile043_enabled: _runtime_profile043_counts.cacheLookups += 1
	if not (frame_cache is Dictionary) or frame_cache.is_empty() or not (s is Dictionary):
		if _runtime_profile043_enabled: _runtime_profile043_miss("unavailableMisses")
		return {}
	var slot: String = _find_cache_slot(s, frame_cache)
	if slot.is_empty():
		if _runtime_profile043_enabled: _runtime_profile043_miss("missingOwnerMisses")
		return {}
	var entry = frame_cache.get(slot)
	if not (entry is Dictionary) or not is_same(entry.get("shipRef"), s):
		if _runtime_profile043_enabled: _runtime_profile043_miss("invalidEntryMisses")
		return {}
	if not _cache_entry_valid(s, entry):
		if _runtime_profile043_enabled: _runtime_profile043_miss(_runtime_profile043_rejection(s,entry))
		frame_cache.erase(slot); return {}
	if _runtime_profile043_enabled: _runtime_profile043_counts.cacheHits += 1
	return entry

static func _cached_info_or_empty(s, frame_cache) -> Dictionary:
	return _cached_entry(s,frame_cache).get("info",{})

static func inspect_owner_cached(s = null, frame_cache = null) -> Dictionary:
	if not (s is Dictionary) or s.is_empty(): return {"ok": false, "mode": "invalid", "needsInitialize": false, "error": "Boat must be a dictionary."}
	var cached: Dictionary = _cached_info_or_empty(s, frame_cache)
	if not cached.is_empty(): return cached
	return EquipmentDamage.inspect_owner(s)

static func _begin_battle_phase043(frame_cache: Dictionary) -> BattlePhase043:
	var phase: BattlePhase043 = BattlePhase043.new()
	phase.source = frame_cache
	return phase

static func _end_battle_phase043(phase) -> void:
	if phase is BattlePhase043:
		phase.active = false
		phase.readsSealed051 = false
		phase.entries.clear()
		phase.owned = null

static func _seal_battle_reads051(phase) -> void:
	# Battle alone opts in AFTER every damage/mount prepass and retarget writer.
	# Main-thread, synchronous, no await/caller callbacks; never a worker input.
	if not (phase is BattlePhase043) or not phase.active: return
	if not (phase.owned is BattleOwned051) or not phase.owned.active: return
	for owner in phase.owned.entries.values():
		var entry: Dictionary = _phase_entry043(owner.shipRef,phase)
		if not entry.is_empty(): _status_from_entry043(owner.shipRef,entry)
	phase.readsSealed051 = true

static func _create_battle_owned051(ships: Array, source: Dictionary) -> BattleOwned051:
	var owned: BattleOwned051 = BattleOwned051.new()
	owned.ships = ships; owned.source = source
	return owned

static func _battle_owned_for051(owned, ships: Array, source: Dictionary):
	return owned if owned is BattleOwned051 and owned.active and is_same(owned.ships,ships) and is_same(owned.source,source) else null

static func _close_battle_owned051(owned) -> void:
	if not (owned is BattleOwned051): return
	owned.active = false
	for entry in owned.entries.values(): entry.valid = false
	owned.entries.clear(); owned.ships = []; owned.source = {}

static func _drop_battle_owner051(owned, s: Dictionary) -> void:
	if not (owned is BattleOwned051): return
	var slot: String = _cache_slot_key(s)
	var entry: Dictionary = owned.entries.get(slot,{})
	if not is_same(entry.get("shipRef"),s):
		for key in owned.entries:
			if is_same(owned.entries[key].shipRef,s):
				slot = str(key); entry = owned.entries[key]; break
	if is_same(entry.get("shipRef"),s):
		entry.valid = false; owned.entries.erase(slot)

static func _admit_battle_owner051(owned: BattleOwned051, s: Dictionary, generation: int = 0) -> void:
	if not owned.active or s.get("sunk",false) or owned.entries.size() >= OWNER_CACHE_LIMIT: return
	var slot: String = _cache_slot_key(s)
	if slot.is_empty() or owned.entries.has(slot): return
	var info: Dictionary = EquipmentDamage.inspect_owner(s)
	if not bool(info.get("ok",false)) or str(info.get("mode","")) != "canonical": return
	if not (s.get("spec") is Dictionary) or not (s.get("breaches") is Array): return
	for key in ["baseSpec","loadout"]:
		if s.has(key) and not (s[key] is Dictionary): return
	for value in [s,s.spec,s.get("baseSpec"),s.get("loadout"),s.breaches]:
		if is_same(value,s.moduleCondition) or is_same(value,s.moduleCondition.items): return
	var present: bool = false
	for other in owned.ships:
		if is_same(other,s): present = true
		elif other is Dictionary and other.get("moduleCondition") is Dictionary:
			if is_same(other.moduleCondition,s.moduleCondition) or is_same(other.moduleCondition.get("items"),s.moduleCondition.items): return
	if not present: return
	for key in ["hp","maxHp","water","capacity","fire","engine","crew","wounded","crewMin","crewOptimal","crewMax","supplies","ammo","fuel","cooldown","armor","vx","vy"]:
		if not EquipmentDamage.Core._number(s.get(key)): return
	for breach in s.breaches:
		if not (breach is Dictionary) or not EquipmentDamage.Core._number(breach.get("area")): return
	var descriptor: Dictionary = EquipmentDamage.Records._battle_descriptor051(s)
	if not bool(descriptor.get("ok",false)): return
	var entry: Dictionary = {"valid":true,"shipRef":s,"conditionRef":s.moduleCondition,"itemsRef":s.moduleCondition.items,"specRef":s.spec,"baseSpecRef":s.get("baseSpec"),"loadoutRef":s.get("loadout"),"identity":[s.get("id"),s.get("uid"),s.get("type")],"descriptor":descriptor,"generation":generation,"infoGeneration":generation,"projectionGeneration":-1,"info":EquipmentDamage.Records._battle_freeze051(info),"projection":{},"statusInputs":[],"status":{},"healthy":false,"priority":s.moduleCondition.repairPriority}
	owned.entries[slot] = entry

static func _bind_battle_owned051(phase, owned, ships: Array, source: Dictionary) -> void:
	if not (phase is BattlePhase043) or not phase.active or _battle_owned_for051(owned,ships,source) == null: return
	phase.owned = owned
	if not owned.admitted:
		owned.admitted = true
		for s in ships: _admit_battle_owner051(owned,s)
	var live: Dictionary = {}
	for s in ships: live[_cache_slot_key(s)] = s
	for slot in owned.entries.keys():
		var entry: Dictionary = owned.entries[slot]
		if not is_same(live.get(slot),entry.shipRef) or entry.shipRef.get("sunk",false):
			_drop_battle_owner051(owned,entry.shipRef)

static func _battle_entry051(s: Dictionary, owned) -> Dictionary:
	if not (owned is BattleOwned051) or not owned.active: return {}
	var entry: Dictionary = owned.entries.get(_cache_slot_key(s),{})
	if not is_same(entry.get("shipRef"),s): return {}
	var valid: bool = bool(entry.get("valid",false)) and [s.get("id"),s.get("uid"),s.get("type")] == entry.identity
	for pair in [["conditionRef","moduleCondition"],["specRef","spec"],["baseSpecRef","baseSpec"],["loadoutRef","loadout"]]:
		valid = valid and is_same(entry.get(pair[0]),s.get(pair[1]))
	valid = valid and s.get("moduleCondition") is Dictionary and is_same(entry.itemsRef,s.moduleCondition.get("items"))
	if not valid:
		_drop_battle_owner051(owned,s); return {}
	# The public priority setter is also a reachable between-frame writer. It
	# changes no topology; a fresh generation observes it before any private read.
	if s.moduleCondition.get("repairPriority") != entry.priority:
		if not s.moduleCondition.get("repairPriority") in EquipmentDamage.Core.PRIORITIES:
			_drop_battle_owner051(owned,s); return {}
		EquipmentDamage.Records._battle_dirty051(entry)
		entry.priority = s.moduleCondition.repairPriority
	entry.info = EquipmentDamage._battle_info051(s,entry)
	if not bool(entry.valid):
		_drop_battle_owner051(owned,s); return {}
	return entry

static func _healthy_battle_entry051(s: Dictionary, entry: Dictionary) -> bool:
	# The encounter generation owns equipment proof; these scalars remain live.
	# Engine changes must reach legacy absorption before any projection publish.
	if s.get("engine") != 1.0 or s.moduleCondition.get("legacyEngineSynced") != 1.0:
		entry.healthy = false; return false
	for key in ["fuel","ammo","cooldown"]:
		if not EquipmentDamage.Core._number(s.get(key)) or s[key] < 0.0:
			entry.healthy = false; return false
	for key in ["vx","vy"]:
		if not EquipmentDamage.Core._number(s.get(key)):
			entry.healthy = false; return false
	# Crew, fire, water, breaches, policy, supplies and fuel-zero affect status.
	# Priority/official equipment writes already revoke healthy in _battle_entry051.
	if not bool(entry.healthy) or _status_inputs(s) != entry.statusInputs:
		entry.healthy = false
		if not _healthy_canonical_no_work(s,entry.info): return false
		if int(entry.projectionGeneration) != int(entry.generation):
			var published: Dictionary = EquipmentDamage.Records._battle_publish051(s,entry)
			if not bool(published.get("ok",false)) or not bool(entry.valid):
				entry.valid = false; return false
		_status_from_entry043(s,entry)
		entry.healthy = true
	return true

static func _tick_ship_in_battle051(s: Dictionary, dt: float, phase) -> Dictionary:
	if phase is BattlePhase043: phase.readsSealed051 = false
	var entry: Dictionary = _battle_entry051(s,phase.owned) if phase is BattlePhase043 and phase.active else {}
	if entry.is_empty(): return tick_ship(s,dt,{"inCombat":true},phase)
	invalidate_frame_cache(phase.source,s)
	if _healthy_battle_entry051(s,entry):
		return _tick_healthy_cached(s,maxf(0.0,number(dt)),entry,phase.source,true)
	if not bool(entry.valid):
		_drop_battle_owner051(phase.owned,s)
		return tick_ship(s,dt,{"inCombat":true},phase)
	var result: Dictionary = _tick_canonical_with(s,maxf(0.0,number(dt)),{"inCombat":true},
		EquipmentDamage._battle_info051.bind(entry),EquipmentDamage._battle_repair051.bind(entry),
		EquipmentDamage.Records._battle_publish051.bind(entry),EquipmentDamage._battle_absorb051.bind(entry))
	if not bool(entry.valid): _drop_battle_owner051(phase.owned,s)
	return result

static func _apply_hit_in_battle051(s: Dictionary, hit: Dictionary, rng: RandomNumberGenerator, frame_cache, owned) -> Array:
	var entry: Dictionary = _battle_entry051(s,owned)
	var generation: int = int(entry.get("generation",0)) + 1
	_drop_battle_owner051(owned,s) # A failed/partial transaction never keeps proof.
	var receipt: Dictionary = {}
	var events: Array = _apply_hit_checked051(s,hit,rng,frame_cache,receipt)
	if not entry.is_empty() and bool(receipt.get("ok",false)):
		_admit_battle_owner051(owned,s,generation)
	return events

static func _phase_entry043(s: Dictionary, frame_cache) -> Dictionary:
	# Main-thread Battle only, without await. Official writers revoke/dirty proof;
	# unsealed status readers also check every live scalar input.
	if not (frame_cache is BattlePhase043) or not frame_cache.active:
		return _cached_entry(s, frame_cache)
	if _runtime_profile043_enabled: _runtime_profile043_counts.phaseLookups += 1
	var owned = frame_cache.owned
	if owned is BattleOwned051 and owned.active:
		var owner_slot: String = _cache_slot_key(s)
		var borrowed: Dictionary = frame_cache.entries.get(owner_slot,{})
		if (is_same(owned.entries.get(owner_slot),borrowed) and is_same(borrowed.get("shipRef"),s)
				and bool(borrowed.get("valid",false)) and int(borrowed.infoGeneration) == int(borrowed.generation)
				and borrowed.priority == s.moduleCondition.get("repairPriority")):
			if _runtime_profile043_enabled: _runtime_profile043_counts.phaseHits += 1
			return borrowed
		var owned_entry: Dictionary = _battle_entry051(s,owned)
		if not owned_entry.is_empty():
			frame_cache.entries[owner_slot] = owned_entry
			return owned_entry
	var slot: String = _find_cache_slot(s, frame_cache.source)
	var entry = frame_cache.entries.get(slot)
	if entry is Dictionary and is_same(entry.get("shipRef"), s) and is_same(frame_cache.source.get(slot), entry) and int(entry.get("framesLeft", 0)) > 0:
		if _runtime_profile043_enabled: _runtime_profile043_counts.phaseHits += 1
		return entry
	entry = _cached_entry(s, frame_cache.source)
	if not entry.is_empty(): frame_cache.entries[slot] = entry
	return entry

static func _inspect_owner_in_phase043(s: Dictionary, frame_cache = null) -> Dictionary:
	if not (frame_cache is BattlePhase043) or not frame_cache.active:
		return inspect_owner_cached(s, frame_cache)
	var entry: Dictionary = _phase_entry043(s, frame_cache)
	return entry.info if not entry.is_empty() else EquipmentDamage.inspect_owner(s)

static func _read_status_in_phase043(s: Dictionary, frame_cache = null) -> Dictionary:
	if not (frame_cache is BattlePhase043) or not frame_cache.active:
		return read_status_cached(s, frame_cache)
	var entry: Dictionary = _phase_entry043(s, frame_cache)
	if entry.is_empty(): return read_status_cached(s, frame_cache)
	# _phase_entry043 already proves exact owner/membership/generation/priority.
	# Only owned entries can borrow the sealed status; dirty generations clear
	# statusInputs. Motion's fuel-zero crossing remains live on EVERY read.
	if (frame_cache.readsSealed051 and bool(entry.get("valid",false))
			and entry.statusInputs.size() > 12 and (number(s.get("fuel")) > 0.0) == entry.statusInputs[12]):
		return entry.status
	return _status_from_entry043(s, entry)

static func read_status_cached(s = null, frame_cache = null) -> Dictionary:
	# Read-only, synchronous runtime use. A miss never admits an unvalidated owner.
	if not (s is Dictionary) or s.is_empty():
		var invalid: Dictionary = {"ok":false,"mode":"invalid","needsInitialize":false,"error":"A nonempty boat dictionary is required."}
		return EquipmentDamage._status_from_info({},0.0,0.0,0.0,[0.5,0.28,0.22],invalid)
	var entry: Dictionary = _cached_entry(s,frame_cache)
	if entry.is_empty(): return _status_for_info(s,EquipmentDamage.inspect_owner(s))
	return _status_from_entry043(s, entry)

static func _status_from_entry043(s: Dictionary, entry: Dictionary) -> Dictionary:
	var inputs: Array = _status_inputs(s)
	if inputs != entry.statusInputs:
		entry.statusInputs = inputs.duplicate(true)
		entry.status = _freeze_status(_status_for_info(s,entry.info))
		entry.healthy = false # Re-prove no-work eligibility at the next damage tick.
	return entry.status

static func get_status_cached(s = null, frame_cache = null) -> Dictionary:
	return read_status_cached(s,frame_cache).duplicate(true)

static func _tick_healthy_cached(s: Dictionary, dt: float, entry: Dictionary, _frame_cache: Dictionary, owned_healthy051: bool = false) -> Dictionary:
	# Exact old healthy substeps, real fuel/cooldown debit and sanitation. The
	# unchanged equipment projection needs neither revalidation nor reconstruction.
	while dt > 0.00000001 and not s.sunk:
		var step: float = 1.0/60.0
		var h: float = dt if dt <= step + 0.0000001 else step
		if absf(dt - 2.0*step) <= 0.0000001: h = dt*0.5
		s.water = clampf(s.water + 0.0,0.0,s.capacity)
		if s.fuel > 0.0 and absf(s.vx)+absf(s.vy)>1.0: s.fuel -= 0.006*h
		s.cooldown = maxf(0.0,(float(s.cooldown) if owned_healthy051 else number(s.cooldown))-h)
		if owned_healthy051:
			# Admission plus this tick's live guards prove finite numbers and healthy
			# bounds. Keep normalization/clamps and fresh breaches, without repeating
			# generic number checks on every unchanged field at every 60Hz substep.
			s.hp = float(s.hp) # Already equal to maxHp >= 1.
			s.crew = clampf(float(s.crew),0.0,s.crewMax)
			s.wounded = clampf(float(s.wounded),0.0,s.crew)
			s.fire = clampf(float(s.fire),0.0,100.0)
			s.supplies = maxf(0.0,float(s.supplies))
			s.ammo = maxf(0.0,float(s.ammo))
			s.fuel = maxf(0.0,float(s.fuel))
			s.breaches = []
		else:
			_sanitize(s)
		dt -= h
	if owned_healthy051:
		# Admission/official generations already published equipment and the mutable
		# locker. Healthy substeps change neither; Battle discards this return value.
		# Retain public scalar normalization if a legacy caller supplied integer 1.
		if not (s.engine is float): s.engine = float(s.engine)
		# Only fuel crossing zero can change status during these guarded substeps.
		# Other live inputs were checked above and remain checked by phase readers.
		return entry.status if (s.fuel > 0.0) == entry.statusInputs[12] else _status_from_entry043(s,entry)
	EquipmentDamage.Records._publish_projection(s,entry.projection)
	# This synchronous no-work branch holds the validated entry. Sanitation and
	# projection leave condition/spec/base/loadout unchanged; keep the public copy.
	return _status_from_entry043(s,entry).duplicate(true)

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
	return _apply_hit_checked051(s,hit,rng,frame_cache,{})

static func _apply_hit_checked051(s: Dictionary, hit: Dictionary, rng: RandomNumberGenerator, frame_cache, receipt: Dictionary) -> Array:
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
		var published: Dictionary = EquipmentDamage.Records.publish(s)
		receipt["ok"] = bool(comp_res.get("ok",false)) and bool(published.get("ok",false))
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
	# Admit only after canonical inspection and the public context's alias/type guards.
	# Battle can retain this proof under exact owner/value guards for twelve frames.
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
	if frame_cache is BattlePhase043:
		_drop_battle_owner051(frame_cache.owned,s)
		frame_cache = frame_cache.source
	if not s is Dictionary: return get_status({})
	var entry: Dictionary = _cached_entry(s,frame_cache)
	if not entry.is_empty() and bool(entry.get("healthy",false)) and _options == {"inCombat":true} and _status_inputs(s) == entry.statusInputs:
		if EquipmentDamage.Core._number(s.get("fuel")) and s.fuel >= 0.0 and EquipmentDamage.Core._number(s.get("ammo")) and s.ammo >= 0.0 and EquipmentDamage.Core._number(s.get("cooldown")) and s.cooldown >= 0.0 and EquipmentDamage.Core._number(s.get("vx")) and EquipmentDamage.Core._number(s.get("vy")):
			return _tick_healthy_cached(s,maxf(0.0,number(dt)),entry,frame_cache)
	var info: Dictionary = entry.info if not entry.is_empty() else EquipmentDamage.inspect_owner(s)
	invalidate_frame_cache(frame_cache,s)
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
		# This exact full-validation memo dies on return. Full public guards, cache
		# admission/expiry, and every changed-condition validation remain unchanged.
		var records_validate: Callable = EquipmentDamage.Records._tick_records_exact.bind({})
		tick_ctx["records_validate"] = records_validate
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
				EquipmentDamage._inspect_owner_with_records.bind(records_validate),
				EquipmentDamage._tick_repair_step_with_records.bind(records_validate),
				EquipmentDamage.Records._publish_with.bind(records_validate),
				EquipmentDamage.Records._absorb_legacy_damage_with.bind(records_validate),
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
