extends RefCounted
## Pure read-only expedition accounting; physical tank/rack overflow occupies holds.
const Passengers=preload("res://scripts/passenger_manifest.gd")
const Tooling=preload("res://scripts/industrial_tooling.gd")
const Goods=preload("res://scripts/goods.gd")
const Damage=preload("res://scripts/damage.gd")
const Economy=preload("res://scripts/economy.gd")
const Deployment=preload("res://scripts/deployment.gd")
const DAY_SECONDS: float=45.0

static func traveling(state: Dictionary) -> Array:
	return state.get("fleet",[]).filter(func(b):return b is Dictionary and not b.get("sunk",false) and not b.get("mothballed",false) and not b.get("needsHarborRepair",false) and str(b.get("storedPort","")).is_empty() and float(b.get("crew",0))>=float(b.get("crewMin",1)))

static func capacity(state: Dictionary) -> float:
	var total: float=0.0
	for b in traveling(state):total+=maxf(0,float(b.get("spec",{}).get("cargo",0)))
	return total

static func cargo_weight(state: Dictionary) -> float:
	var total: float=Passengers.food_weight(state)
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

static func _fuel_per_day(b: Dictionary) -> float:
	var spec: Dictionary=b.get("spec",{})
	return DAY_SECONDS*(0.011+float(spec.get("size",14))*0.0002)*maxf(0.2,float(spec.get("fuelUse",1)))

static func _route_speed(state: Dictionary,world: Dictionary,fleet: Array) -> float:
	# Legacy three-argument callers use the same towing/damage model as Campaign.
	if fleet.is_empty():return 0.0
	var speed: float=170.0
	for b in fleet:
		speed=minf(speed,float(b.spec.get("speed",0))*maxf(0.25,float(Damage.get_status(b).speedFactor))*(1.0 if b.fuel>0 else 0.3))
	var powered_mass: float=0.0
	var tow_mass: float=0.0
	var tow_factor: float=1.0
	for b in state.get("fleet",[]):
		if b.get("sunk",false) or not str(b.get("storedPort","")).is_empty():continue
		if b.get("mothballed",false) or float(b.get("crew",0))<float(b.get("crewMin",1)) or b.get("needsHarborRepair",false):tow_mass+=float(b.spec.size)
		else:powered_mass+=float(b.spec.size)
		if b.get("towed",false):
			var best_tug: float=0.55
			for tug in fleet:best_tug=maxf(best_tug,float(tug.spec.get("towSpeedFactor",0.55)))
			tow_factor=minf(tow_factor,maxf(best_tug,float(b.get("towSpeedFactor",0.55))))
	return speed*1.55*float(world.get("CAMPAIGN_SCALE",1.0))*powered_mass/maxf(1,powered_mass+tow_mass*0.8)*tow_factor

static func _fuel_allowance(b: Dictionary,days: float) -> Dictionary:
	var burn: float=_fuel_per_day(b)
	var loaded: float=maxf(0,float(b.get("fuel",0)))
	var tank: float=maxf(0,float(b.get("spec",{}).get("fuelCapacity",60)))
	var required: float=days*burn
	return {"uid":str(b.get("uid","")),"name":str(b.get("name","Boat")),
		"fuelPerDay":burn,"loadedFuel":loaded,"tankCapacity":tank,
		"loadedDays":loaded/maxf(0.00001,burn),"tankDays":tank/maxf(0.00001,burn),
		"fuelRequired":required,"fuelShortfall":maxf(0,required-loaded),"tankShortfall":maxf(0,required-tank)}

static func report(state: Dictionary,world: Dictionary,route_distance: float=0.0,actual_speed: float=-1.0) -> Dictionary:
	var fleet: Array=traveling(state)
	var flagship: String=str(state.get("flagship",""))
	fleet.sort_custom(func(a,b):return str(a.get("uid",""))==flagship and str(b.get("uid",""))!=flagship)
	var speed: float=actual_speed if is_finite(actual_speed) and actual_speed>=0 else _route_speed(state,world,fleet)
	var route: float=maxf(0,route_distance) if is_finite(route_distance) else 0.0
	var reserve: float=2.0
	var outward: float=route/maxf(0.01,speed)/DAY_SECONDS
	var trip: float=outward*2.0+reserve
	var owned: Array=[]
	var stored: int=0
	for b in state.get("fleet",[]):
		if b.get("sunk",false):continue
		owned.append(b)
		if not str(b.get("storedPort","")).is_empty():stored+=1
	var crew: int=0
	var fuel_days: float=1000000.0 if not fleet.is_empty() else 0.0
	var fuel_required: float=0.0
	var fuel_shortfall: float=0.0
	var boats: Array=[]
	var repair_kits: float=maxf(0,float(state.get("cargo",{}).get("supplies",0)))
	for b in fleet:
		crew+=maxi(0,int(b.get("crew",0)))
		var row: Dictionary=_fuel_allowance(b,trip)
		boats.append(row)
		fuel_days=minf(fuel_days,float(row.loadedDays))
		fuel_required+=float(row.fuelRequired)
		fuel_shortfall+=float(row.fuelShortfall)
		repair_kits+=maxf(0,float(b.get("supplies",0)))
	var capacity_value: float=capacity(state)
	var weight: float=cargo_weight(state)
	# Daily upkeep includes stored/mothballed sailors and fitted food efficiencies.
	var upkeep: Dictionary=Economy.daily_upkeep(state.get("fleet",[]))
	var wages: int=int(upkeep.wages)
	for specialist in state.get("specialists",[]):
		if not specialist.get("discharged",false) and not specialist.get("lost",false):wages+=int(specialist.get("premiumPerDay",0))
	var food_per_day: float=maxf(0,float(upkeep.food))
	var food: float=maxf(0,float(state.get("cargo",{}).get("food",0)))
	var food_required: float=food_per_day*trip
	var food_shortfall: float=maxf(0,food_required-food)
	var food_days: float=food/maxf(0.01,food_per_day) if food_per_day>0 else 0.0
	var arrears: float=maxf(0,float(state.get("wageArrears",0)))
	var coins: float=maxf(0,float(state.get("coins",0)))
	var funds: float=maxf(0,coins-arrears)
	var affordable: float=funds/maxi(1,wages) if wages>0 else 0.0
	var return_wages: int=ceili(trip*wages)
	var wage_shortfall: float=maxf(0,return_wages+arrears-coins)
	var provisioned_weight: float=weight+food_shortfall*float(Goods.ITEMS.food.weight)
	var allowance_overload: float=maxf(0,provisioned_weight-capacity_value)
	var support_options: Array=[]
	for b in owned:
		if b in fleet:continue
		var option: Dictionary=_fuel_allowance(b,trip)
		var missing_crew: int=maxi(0,int(b.get("crewMin",1))-int(b.get("crew",0)))
		var blockers: Array=[]
		var stored_port: String=str(b.get("storedPort",""))
		if not stored_port.is_empty():blockers.append("Stored at %s; recover at that harbor before joining."%stored_port)
		if b.get("mothballed",false):blockers.append("Reactivate this mothballed boat at a harbor.")
		if b.get("needsHarborRepair",false):blockers.append("Harbor repair is required.")
		if missing_crew>0:blockers.append("Hire %d sailors to reach minimum crew."%missing_crew)
		if float(option.fuelShortfall)>0.001:blockers.append("Load %.1f fuel for the current allowance."%float(option.fuelShortfall))
		option.merge({"storedPort":stored_port,"addedCapacity":maxf(0,float(b.spec.get("cargo",0))),
			"crewToMinimum":missing_crew,"additionalDailyWages":missing_crew*Goods.SAILOR_WAGE,
			"additionalFoodPerDay":snappedf(missing_crew*0.08*clampf(float(b.spec.get("upkeepFactor",1)),0.8,1.0),0.01),
			"blockers":blockers,"projectionOnly":true})
		support_options.append(option)
	var warnings: Array=[]
	if not is_finite(route_distance) or route_distance<0:warnings.append("Choose a finite nonnegative route distance; this preview uses zero travel distance.")
	if fleet.is_empty():warnings.append("No seaworthy crewed boat is traveling.")
	if weight>capacity_value+0.001:warnings.append("Holds overloaded by %.1f space; offload or activate a carrier before sailing."%(weight-capacity_value))
	if food_shortfall>0.001:warnings.append("Food is short by %.1f bales for the outward, return and two-day contingency allowance."%food_shortfall)
	if allowance_overload>0.001 and food_shortfall>0.001:warnings.append("The remaining food allowance would exceed current holds by %.1f space."%allowance_overload)
	if fuel_shortfall>0.001:warnings.append("Loaded boat fuel is short by %.1f drums. Loose reserves must be loaded through Supplies; each boat has its own tank limit."%fuel_shortfall)
	for row in boats:
		if float(row.tankShortfall)>0.001:warnings.append("%s: allowance exceeds its tank by %.1f drums; plan fuel stops or extra hold cargo. Support tanks are not shared."%[row.name,row.tankShortfall])
	if wage_shortfall>0:warnings.append("Your purse is short by %d coins for return payroll and existing wage arrears."%ceili(wage_shortfall))
	if repair_kits<2:warnings.append("Little repair stock remains. Breaches consume actual kits.")
	var bottleneck: String="Allowance covered"
	if not is_finite(route_distance) or route_distance<0:bottleneck="Choose a valid route"
	elif fleet.is_empty():bottleneck="No traveling boat"
	elif route>0 and speed<=0:bottleneck="No sailing speed"
	elif allowance_overload>0.001:bottleneck="Hold capacity"
	elif fuel_shortfall>0.001 and (food_shortfall<=0.001 or fuel_days<=food_days) and (wage_shortfall<=0 or fuel_days<=affordable):bottleneck="Loaded fuel"
	elif food_shortfall>0.001 and (wage_shortfall<=0 or food_days<=affordable):bottleneck="Food"
	elif wage_shortfall>0:bottleneck="Payroll"
	elif fuel_shortfall>0.001:bottleneck="Loaded fuel"
	var ready: bool=not fleet.is_empty() and (route<=0 or speed>0) and allowance_overload<=0.001 and food_shortfall<=0.001 and fuel_shortfall<=0.001 and wage_shortfall<=0 and is_finite(route_distance) and route_distance>=0
	var battle: Dictionary=Deployment.split(fleet)
	return {"usableCapacity":capacity_value,"cargoWeight":weight,"freeCapacity":maxf(0,capacity_value-weight),"overload":maxf(0,weight-capacity_value),"crew":crew,"dailyWages":wages,"fuelDays":fuel_days,"foodDays":food_days,"repairKits":repair_kits,"reserveDays":reserve,"affordableDays":affordable,"tripDays":trip,"returnWages":return_wages,"warnings":warnings,
		"routeDistance":route,"routeSpeed":speed,"outwardDays":outward,"returnDays":outward,
		"foodPerDay":food_per_day,"foodAvailable":food,"foodRequired":food_required,"foodShortfall":food_shortfall,
		"fuelRequired":fuel_required,"fuelShortfall":fuel_shortfall,"looseFuel":maxf(0,float(state.get("cargo",{}).get("fuel",0))),
		"wageArrears":arrears,"fundsAfterArrears":funds,"wageShortfall":wage_shortfall,
		"payloadAfterFood":maxf(0,capacity_value-provisioned_weight),"allowanceOverload":allowance_overload,
		"ownedCount":owned.size(),"travelingCount":fleet.size(),"storedCount":stored,"inactiveCount":owned.size()-fleet.size(),
		"ownedDP":Deployment.total(owned),"activeDP":Deployment.total(fleet),"battleDP":int(battle.points),"battleLimit":Deployment.LIMIT,"battleReserveCount":battle.reserve.size(),
		"readyForAllowance":ready,"bottleneck":bottleneck,"boats":boats,"supportOptions":support_options}
