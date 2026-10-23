extends RefCounted
## Pure read-only expedition accounting; physical tank/rack overflow occupies holds.
const Tooling=preload("res://scripts/industrial_tooling.gd")
const Goods=preload("res://scripts/goods.gd")
const Damage=preload("res://scripts/damage.gd")
const DAY_SECONDS: float=45.0

static func traveling(state: Dictionary) -> Array:
	return state.get("fleet",[]).filter(func(b):return b is Dictionary and not b.get("sunk",false) and not b.get("mothballed",false) and not b.get("needsHarborRepair",false) and str(b.get("storedPort","")).is_empty() and float(b.get("crew",0))>=float(b.get("crewMin",1)))

static func capacity(state: Dictionary) -> float:
	var total: float=0.0
	for b in traveling(state):total+=maxf(0,float(b.get("spec",{}).get("cargo",0)))
	return total

static func cargo_weight(state: Dictionary) -> float:
	var total: float=0.0
	for item in state.get("tooling",{}).get("items",[]):
		if item.get("location","")=="cargo":total+=float(Tooling.KINDS.get(item.get("kind",""),{"weight":0}).weight)
	for key in Goods.ITEMS:total+=maxf(0,float(state.get("cargo",{}).get(key,0)))*float(Goods.ITEMS[key].weight)
	var freight: Dictionary=state.get("freight",{})
	if not freight.is_empty():total+=maxf(0,float(freight.get("qty",0)))*float(Goods.ITEMS.get(freight.get("good",""),{"weight":1}).weight)
	for job in state.get("voyageJobs",[]):
		var lot: Dictionary=job.get("freight",{})
		if not lot.is_empty():total+=maxf(0,float(lot.get("qty",0)))*float(Goods.ITEMS.get(lot.get("good",""),{"weight":1}).weight)
	for b in state.get("fleet",[]):
		if b.get("sunk",false) or not str(b.get("storedPort","")).is_empty():continue
		total+=store_overflow(b)
		if not b.get("needsHarborRepair",false):total+=maxf(0,float(state.get("captiveBerths",{}).get(str(b.get("uid","")),0))-maxf(0,float(b.get("crewMax",0))-float(b.get("crew",0))))
	return total

static func store_overflow(b: Dictionary) -> float:
	var spec: Dictionary=b.get("spec",{})
	return maxf(0,float(b.get("fuel",0))-float(spec.get("fuelCapacity",60)))+maxf(0,float(b.get("supplies",0))-float(spec.get("kitCapacity",20)))+maxf(0,float(b.get("ammo",0))-float(spec.get("ammoCapacity",80)))/Goods.ROUNDS_PER_CASE

static func report(state: Dictionary,world: Dictionary,route_distance: float=0.0) -> Dictionary:
	var fleet: Array=traveling(state)
	var crew: int=0
	var all_crew: int=0
	var fuel_days: float=1000000.0
	var repair_kits: float=maxf(0,float(state.get("cargo",{}).get("supplies",0)))
	var speed: float=170.0
	for b in state.get("fleet",[]):
		if not b.get("sunk",false):all_crew+=maxi(0,int(b.get("crew",0)))
	for b in fleet:
		crew+=maxi(0,int(b.crew))
		var spec: Dictionary=b.spec
		var use_per_day: float=DAY_SECONDS*(0.011+float(spec.get("size",14))*0.0002)*maxf(0.2,float(spec.get("fuelUse",1)))
		fuel_days=minf(fuel_days,maxf(0,float(b.get("fuel",0)))/maxf(0.00001,use_per_day))
		repair_kits+=maxf(0,float(b.get("supplies",0)))
		speed=minf(speed,float(spec.get("speed",0))*maxf(0.25,float(Damage.get_status(b).speedFactor))*(1.0 if b.fuel>0 else 0.3))
	var capacity_value: float=capacity(state)
	var weight: float=cargo_weight(state)
	var wages: int=all_crew*Goods.SAILOR_WAGE
	for specialist in state.get("specialists",[]):
		if not specialist.get("discharged",false) and not specialist.get("lost",false):wages+=int(specialist.get("premiumPerDay",0))
	var food_days: float=maxf(0,float(state.get("cargo",{}).get("food",0)))/maxf(0.01,all_crew*0.08) if all_crew>0 else 0.0
	var funds: float=maxf(0,float(state.get("coins",0))-float(state.get("wageArrears",0)))
	var affordable: float=funds/maxi(1,wages) if wages>0 else 0.0
	var reserve: float=2.0
	var trip: float=maxf(0,route_distance)*2.0/maxf(0.01,speed*1.55*float(world.get("CAMPAIGN_SCALE",1)))/DAY_SECONDS+reserve
	var warnings: Array=[]
	if fleet.is_empty():warnings.append("No seaworthy crewed boat is traveling.");fuel_days=0.0
	if weight>capacity_value+0.001:warnings.append("Holds overloaded by %.1f space; offload or activate a carrier before sailing."%(weight-capacity_value))
	if food_days<trip:warnings.append("Food is short of the round-trip and contingency allowance.")
	if fuel_days<trip:warnings.append("At least one boat needs more working fuel for this allowance. Load loose fuel reserves if available.")
	if affordable<trip:warnings.append("Your purse cannot cover the projected payroll after existing wage arrears.")
	if repair_kits<2:warnings.append("Little repair stock remains. Breaches consume actual kits.")
	return {"usableCapacity":capacity_value,"cargoWeight":weight,"freeCapacity":maxf(0,capacity_value-weight),"overload":maxf(0,weight-capacity_value),"crew":crew,"dailyWages":wages,"fuelDays":fuel_days,"foodDays":food_days,"repairKits":repair_kits,"reserveDays":reserve,"affordableDays":affordable,"tripDays":trip,"returnWages":ceili(trip*wages),"warnings":warnings}
