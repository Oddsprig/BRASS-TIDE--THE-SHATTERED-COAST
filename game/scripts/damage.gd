extends RefCounted
## Pure numerical damage. Liters, cm², seconds; fractional crew represent labor.
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const HULL_DAMAGE_SCALE: float = 0.35
const CONSTANTS = {"inflowPerArea":0.055,"bailPerCrew":1.65,"pumpRate":2.3,"patchPerCrew":1.8,"patchSupplyPerArea":0.018,"hullRepairPerCrew":0.22,"hullSupplyPerHp":0.35,"fireGrowthPerSec":0.08,"fireSuppressPerCrew":0.65,"moduleHpPerCrew":0.04,"moduleSuppliesPerHp":{"pumps":1.2,"engines":1.5,"weapons":1.0},"portHullCost":3.0,"portWoundCost":12.0,"portPatchCost":0.6,"portSupplyCost":5.0}

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
	var info: Dictionary = EquipmentDamage.inspect_owner(s)
	if str(info.get("mode", "invalid")) == "invalid":
		return EquipmentDamage.status_for(s, 0.0, 0.0, 0.0, [0.5, 0.28, 0.22])
	var able: float=maxf(0.0,number(s.get("crew"))-number(s.get("wounded"))-maxf(0.0,number(s.get("shoreCrew",0))))
	var area: float=sum_areas(s)
	var cap: float=maxf(1.0,number(s.get("capacity"),200.0))
	var inflow: float=area*CONSTANTS.inflowPerArea*(1.0+number(s.get("water"))/cap*0.45)
	var weights: Array={"balanced":[0.5,0.28,0.22],"bail":[0.15,0.65,0.2],"repair":[0.15,0.2,0.65],"fight":[0.85,0.1,0.05]}.get(s.get("policy","balanced"),[0.5,0.28,0.22])
	return EquipmentDamage.status_for(s, able, area, inflow, weights)

static func _roll(rng: RandomNumberGenerator) -> float:
	# No global RNG state: callers normally supply their battle-owned seeded RNG.
	if rng!=null:
		return rng.randf()
	var local: RandomNumberGenerator=RandomNumberGenerator.new()
	local.randomize()
	return local.randf()

static func apply_hit(s: Dictionary, hit: Dictionary, rng: RandomNumberGenerator = null) -> Array:
	var events: Array=[]
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
	if s.sunk:
		events.append("Ship sunk")
	return events

static func tick_ship(s: Dictionary, dt: float, _options: Dictionary = {}) -> Dictionary:
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
		if _options is Dictionary and _options.has("priority") and not str(_options.get("priority")) in EquipmentDamage.Core.PRIORITIES:
			var bad_status: Dictionary = get_status(s)
			bad_status.equipmentOk = false
			bad_status.equipmentError = "Repair priority is unknown."
			return bad_status
		var absorbed: Dictionary = EquipmentDamage.Records.absorb_legacy_damage(s)
		if not absorbed.ok:
			return get_status(s)
		EquipmentDamage.Records.publish(s)
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
			var t_can: Dictionary = get_status(s)
			var before_can: float = s.water
			s.water = clampf(s.water + (t_can.inflow - t_can.bailing) * h_can, 0.0, s.capacity)
			total_in += t_can.inflow * h_can
			total_bail += minf(t_can.bailing * h_can, before_can + t_can.inflow * h_can)
			var step_res: Dictionary = EquipmentDamage.tick_repair_step(s, h_can, float(t_can.crewRepair), _options if _options is Dictionary else {})
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
			if s.fuel>0.0 and (s.water>0.0 or absf(s.vx)+absf(s.vy)>1.0):
				s.fuel-=0.006*h_can
			s.cooldown=maxf(0.0,number(s.cooldown)-h_can)
			_sanitize(s)
			EquipmentDamage.Records.publish(s)
			dt-=h_can
			elapsed+=h_can
			if s.sunk:
				events.append("Ship sunk")
		var status_can: Dictionary = get_status(s)
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
