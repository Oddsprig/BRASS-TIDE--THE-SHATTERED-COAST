extends RefCounted
## Pure numerical damage. Liters, cm², seconds; fractional crew represent labor.
const HULL_DAMAGE_SCALE: float = 0.35
const CONSTANTS = {"inflowPerArea":0.055,"bailPerCrew":1.65,"pumpRate":2.3,"patchPerCrew":1.8,"patchSupplyPerArea":0.018,"hullRepairPerCrew":0.22,"hullSupplyPerHp":0.35,"portHullCost":3.0,"portWoundCost":12.0,"portPatchCost":0.6,"portSupplyCost":5.0}

static func number(value, fallback: float = 0.0) -> float:
	if (value is float or value is int) and is_finite(float(value)):
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

static func get_status(s: Dictionary) -> Dictionary:
	var able: float=maxf(0.0,s.crew-s.wounded)
	var area: float=sum_areas(s)
	var inflow: float=area*CONSTANTS.inflowPerArea*(1.0+s.water/s.capacity*0.45)
	var weights: Array={"balanced":[0.5,0.28,0.22],"bail":[0.15,0.65,0.2],"repair":[0.15,0.2,0.65],"fight":[0.85,0.1,0.05]}.get(s.policy,[0.5,0.28,0.22])
	var active: bool=s.water>0.0 or area>0.0
	var damaged: bool=area>0.0 or s.fire>0.0 or (s.policy=="repair" and s.hp<s.maxHp)
	var bail: float=able*weights[1] if active else 0.0
	var repair: float=able*weights[2] if damaged and (s.supplies>0.0 or s.fire>0.0) else 0.0
	var guns: float=maxf(0.0,able-bail-repair)
	var pump: float=maxf(0.0,number(s.spec.get("pumps")))*CONSTANTS.pumpRate*s.engine if s.fuel>0 else 0.0
	var speed: float=clampf(s.engine*(1.0-0.78*s.water/s.capacity)*minf(1.0,able/maxf(1.0,s.crewMin)),0.0,1.0)
	if s.sunk:
		inflow=0.0
		bail=0.0
		repair=0.0
		guns=0.0
		pump=0.0
		speed=0.0
	return {"inflow":inflow,"bailing":bail*CONSTANTS.bailPerCrew+pump if active and not s.sunk else 0.0,"repair":repair*CONSTANTS.patchPerCrew if area>0.0 and s.supplies>0.0 else 0.0,"crewGuns":guns,"crewBail":bail,"crewRepair":repair,"speedFactor":speed,"weaponFactor":0.0 if s.sunk else clampf(guns/maxf(1.0,s.crewOptimal*0.5),0.0,1.0)*(1.0-s.fire*0.004),"events":[]}

static func _roll(rng: RandomNumberGenerator) -> float:
	# No global RNG state: callers normally supply their battle-owned seeded RNG.
	if rng!=null:
		return rng.randf()
	var local: RandomNumberGenerator=RandomNumberGenerator.new()
	local.randomize()
	return local.randf()

static func apply_hit(s: Dictionary, hit: Dictionary, rng: RandomNumberGenerator = null) -> Array:
	var events: Array=[]
	if s.sunk:
		return events
	var raw: float=maxf(0.0,number(hit.get("damage")))
	if raw<=0.0:
		return events
	var kind: String=hit.get("kind","bullet")
	var explosive: bool=kind=="torpedo"
	var shell: bool=kind in ["shell","ram"]
	var armor: float=maxf(0.0,s.armor-maxf(0.0,number(hit.get("penetration"))))
	var impact: float=maxf(raw*0.22,raw-armor*(0.3 if explosive else 0.8))
	var damage: float=impact*HULL_DAMAGE_SCALE
	s.hp-=damage
	events.append("Hull hit: %.1f HP"%damage)
	var chance: float=1.0 if explosive else (0.72 if shell else 0.3)
	if _roll(rng)<chance:
		var area: float=impact*(5.0 if explosive else (1.1 if shell else 0.45))
		s.breaches.append({"area":area,"section":hit.get("section","bow")})
		events.append("Breach: %.1f cm²"%area)
	if _roll(rng)<(0.65 if hit.get("section","")=="engine" else (0.4 if explosive else 0.09)):
		s.engine-=minf(0.35,impact/s.maxHp*0.7)
		events.append("Engine damaged")
	if _roll(rng)<(0.35 if explosive else (0.2 if kind=="shell" else 0.05)):
		s.fire+=minf(28.0,impact*0.55)
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
	dt=maxf(0.0,number(dt))
	var total_in: float=0.0
	var total_bail: float=0.0
	var total_repair: float=0.0
	var elapsed: float=0.0
	var events: Array=[]
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
			var hull: float=minf(s.maxHp-s.hp,minf(t.crewRepair*CONSTANTS.hullRepairPerCrew*h,s.supplies/CONSTANTS.hullSupplyPerHp))
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
