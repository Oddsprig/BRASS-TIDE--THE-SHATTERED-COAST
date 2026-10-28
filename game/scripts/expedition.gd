extends RefCounted
## Pure read-only expedition accounting; physical tank/rack overflow occupies holds.
const Passengers=preload("res://scripts/passenger_manifest.gd")
const Tooling=preload("res://scripts/industrial_tooling.gd")
const Goods=preload("res://scripts/goods.gd")
const Damage=preload("res://scripts/damage.gd")
const Economy=preload("res://scripts/economy.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Exploration=preload("res://scripts/exploration.gd")
const Routes=preload("res://scripts/route_cache.gd")
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

static func report(state: Dictionary,world: Dictionary,route_distance: float=0.0,actual_speed: float=-1.0,plan: Dictionary={}) -> Dictionary:
	var fleet: Array=traveling(state)
	var flagship: String=str(state.get("flagship",""))
	fleet.sort_custom(func(a,b):return str(a.get("uid",""))==flagship and str(b.get("uid",""))!=flagship)
	var speed: float=actual_speed if is_finite(actual_speed) and actual_speed>=0 else _route_speed(state,world,fleet)
	var route: float=maxf(0,route_distance) if is_finite(route_distance) else 0.0
	var reserve: float=2.0
	var outward: float=float(plan.get("outwardDays",route/maxf(0.01,speed)/DAY_SECONDS))
	var returning: float=float(plan.get("returnDays",outward))
	var trip: float=outward+returning+reserve+float(plan.get("shoreDays",0))
	var fuel_trip: float=trip if plan.is_empty() else outward+returning+reserve
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
		var row: Dictionary=_fuel_allowance(b,fuel_trip)
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
	var payroll_days: float=trip if plan.is_empty() else ceilf(trip+fposmod(float(state.get("day",0)),1.0))
	# Shore rations are prepaid out of this same daily consumption, not extra.
	var food_required: float=maxf(float(plan.get("shoreFood",0)),food_per_day*payroll_days-float(plan.get("foodCredit",0)))
	var food_shortfall: float=maxf(0,food_required-food)
	var food_days: float=food/maxf(0.01,food_per_day) if food_per_day>0 else 0.0
	var arrears: float=maxf(0,float(state.get("wageArrears",0)))
	var coins: float=maxf(0,float(state.get("coins",0)))
	var funds: float=maxf(0,coins-arrears)
	var affordable: float=funds/maxi(1,wages) if wages>0 else 0.0
	var return_wages: int=ceili(payroll_days*wages)
	var wage_shortfall: float=maxf(0,return_wages+arrears-coins)
	var provisioned_weight: float=weight+food_shortfall*float(Goods.ITEMS.food.weight)+float(plan.get("kitShortfall",0))*float(Goods.ITEMS.supplies.weight)
	var allowance_overload: float=maxf(0,provisioned_weight-capacity_value)
	var support_options: Array=[]
	for b in owned:
		if b in fleet:continue
		var option: Dictionary=_fuel_allowance(b,fuel_trip)
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
	if food_shortfall>0.001:warnings.append("Food is short by %.1f bales for planned travel, work and the two-day contingency."%food_shortfall)
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
		"routeDistance":route,"routeSpeed":speed,"outwardDays":outward,"returnDays":returning,"payrollDays":payroll_days,
		"foodPerDay":food_per_day,"foodAvailable":food,"foodRequired":food_required,"foodShortfall":food_shortfall,
		"fuelRequired":fuel_required,"fuelShortfall":fuel_shortfall,"looseFuel":maxf(0,float(state.get("cargo",{}).get("fuel",0))),
		"wageArrears":arrears,"fundsAfterArrears":funds,"wageShortfall":wage_shortfall,
		"payloadAfterFood":maxf(0,capacity_value-provisioned_weight),"allowanceOverload":allowance_overload,
		"ownedCount":owned.size(),"travelingCount":fleet.size(),"storedCount":stored,"inactiveCount":owned.size()-fleet.size(),
		"ownedDP":Deployment.total(owned),"activeDP":Deployment.total(fleet),"battleDP":int(battle.points),"battleLimit":Deployment.LIMIT,"battleReserveCount":battle.reserve.size(),
		"readyForAllowance":ready,"bottleneck":bottleneck,"boats":boats,"supportOptions":support_options}

static func _known_site(state: Dictionary,site_id: String) -> Dictionary:
	if int(state.get("exploration",{}).get("sites",{}).get(site_id,{}).get("level",0))<1:return {}
	return Exploration.catalog_site(state,site_id).duplicate(true)

static func _leg(c,a: Dictionary,b: Dictionary) -> Dictionary:
	var path: Array=Routes.path(c,a,b)
	var length: float=0.0
	for i in range(1,path.size()):length+=c.distance(path[i-1],path[i])
	return {"ok":not path.is_empty(),"distance":length,"path":path}

static func _legal_return(c,p: Dictionary) -> bool:
	if p.is_empty():return false
	return bool(c.Factions.access(c.state,p).legal) or float(c.state.get("relationships",{}).get("safeConduct",{}).get(str(p.id),0))>float(c.state.day)

static func _return_harbor(c,origin: Dictionary,port_id: String) -> Dictionary:
	if not port_id.is_empty():return c.port(port_id).duplicate(true)
	# Sort cheap geometric distances first, then accept the first real route.
	var ports: Array=c.state.get("ports",[]).duplicate()
	ports.sort_custom(func(a,b):return c.distance(origin,a)<c.distance(origin,b))
	for p in ports:
		if _legal_return(c,p) and _leg(c,origin,p).ok:return p.duplicate(true)
	return {}

static func _shore_plan(state: Dictionary,site_id: String,target_level: int) -> Dictionary:
	# quote/assignment normalize their input: only detached projections reach them.
	var copy: Dictionary=state.duplicate(true)
	var ex: Dictionary=Exploration.ensure(copy)
	var level: int=int(ex.sites.get(site_id,{}).get("level",0))
	var active: Dictionary=ex.assignment.duplicate(true)
	var work: Array=[]
	var days: float=0.0
	var chart_days: float=0.0
	var survey_days: float=0.0
	var food: float=0.0
	var kits: float=0.0
	var crew: int=0
	var blocked: String=""
	if not active.is_empty():
		if str(active.siteId)!=site_id:blocked="Another landing has a party ashore; recall it before this voyage."
		else:
			var remaining: float=maxf(0,float(active.daysTotal)-float(active.daysDone))
			work.append({"action":str(active.action),"days":remaining,"food":0.0,"supplies":0.0,"crewNeeded":int(active.crewReserved),"inProgress":true,"message":"Already paid shore stores; remaining work only."})
			days+=remaining
			if str(active.action)=="chart":chart_days+=remaining
			else:survey_days+=remaining
			crew=maxi(crew,int(active.crewReserved))
			level=maxi(level,int(active.targetLevel))
	ex.assignment={}
	for action in ["chart","survey"]:
		var goal: int=2 if action=="chart" else 3
		if level>=goal or goal>clampi(target_level,2,3):continue
		ex.sites[site_id]={"level":level}
		var q: Dictionary=Exploration.quote(copy,site_id,action)
		q["inProgress"]=false
		work.append(q.duplicate(true))
		days+=float(q.days);food+=float(q.food);kits+=float(q.supplies)
		crew=maxi(crew,int(q.crewNeeded))
		if action=="chart":chart_days+=float(q.days)
		else:survey_days+=float(q.days)
		level=goal
	return {"shoreDays":days,"chartDays":chart_days,"surveyDays":survey_days,"shoreFood":food,"shoreKits":kits,"crewNeeded":crew,"spareCrew":Exploration.spare_crew(state),"work":work,"workMessage":blocked}

static func _island_allowance(c,outward: float,returning: float,shore: Dictionary,route_ok: bool,message: String) -> Dictionary:
	var speed: float=c.travel_speed()
	var plan: Dictionary=shore.duplicate(true)
	var spare: int=0
	for b in c.active_fleet():spare+=maxi(0,int(b.crew)-ceili(float(b.get("wounded",0)))-int(b.crewMin))
	plan.spareCrew=mini(int(plan.get("spareCrew",0)),spare)
	plan.outwardDays=outward/maxf(0.01,speed)/DAY_SECONDS
	plan.returnDays=returning/maxf(0.01,speed)/DAY_SECONDS
	plan.foodCredit=maxf(0,float(c.state.get("surveyFoodCredit",0)))
	var supplies: float=maxf(0,float(c.state.get("cargo",{}).get("supplies",0)))
	for b in c.state.get("fleet",[]):
		if not b.get("sunk",false) and not b.get("mothballed",false) and str(b.get("storedPort","")).is_empty():supplies+=maxf(0,float(b.get("supplies",0)))
	plan.kitShortfall=maxf(0,float(plan.get("shoreKits",0))-supplies)
	var r: Dictionary=report(c.state,c.data,(outward+returning)*0.5,speed,plan)
	r.merge(plan,true)
	r.merge({"routeOk":route_ok,"routeMessage":message,"routeDistance":outward+returning,"travelDays":plan.outwardDays+plan.returnDays,"kitShortfall":plan.kitShortfall,"crewShortfall":maxi(0,int(plan.get("crewNeeded",0))-int(plan.get("spareCrew",0)))},true)
	if not route_ok:r.bottleneck="No safe return route";r.warnings.append(message)
	elif not str(plan.get("workMessage","")).is_empty():r.bottleneck="Recall shore party";r.warnings.append(plan.workMessage)
	elif r.crewShortfall>0:r.bottleneck="Spare shore crew";r.warnings.append("Hire %d more able spare sailors above boat minimums."%r.crewShortfall)
	elif r.kitShortfall>0.001:r.bottleneck="Shore kits";r.warnings.append("Shore work needs %.1f more actual kits."%r.kitShortfall)
	r.readyForAllowance=r.readyForAllowance and route_ok and str(plan.get("workMessage","")).is_empty() and r.crewShortfall==0 and r.kitShortfall<=0.001
	return r

## One panel-time quotation. Navigation caches may warm; save data stays untouched.
static func preview(c,site_id: String,return_port_id: String="",detour_site_id: String="",target_level: int=3) -> Dictionary:
	var site: Dictionary=_known_site(c.state,site_id)
	var blank: Dictionary={"shoreDays":0.0,"chartDays":0.0,"surveyDays":0.0,"shoreFood":0.0,"shoreKits":0.0,"crewNeeded":0,"spareCrew":Exploration.spare_crew(c.state),"work":[],"workMessage":""}
	if site.is_empty():
		var refused: Dictionary=_island_allowance(c,0,0,blank,false,"This landing is not known. Earn or sight its clue first.")
		refused.merge({"siteId":"","siteName":"Unknown landing","returnPortId":"","returnPortName":"Unselected","returnNow":{},"detour":{}},true)
		return refused
	var outbound: Dictionary={"ok":true,"distance":0.0}
	var origin: Dictionary=site
	if c.distance(c.state.position,site)<=180:
		origin=c.state.position
	else:outbound=_leg(c,c.state.position,site)
	var harbor: Dictionary=_return_harbor(c,origin,return_port_id)
	var back: Dictionary={"ok":false,"distance":0.0} if harbor.is_empty() else _leg(c,origin,harbor)
	var legal: bool=_legal_return(c,harbor)
	var route_ok: bool=outbound.ok and back.ok and legal
	var message: String="Safe water routes quoted; hostile encounters and recovery add separate risk."
	if not route_ok:message="No safe water route to this landing and an accessible named return harbor. Choose another route or harbor."
	var shore: Dictionary=_shore_plan(c.state,site_id,target_level)
	if not c.state.get("toolingRecovery",{}).is_empty():shore.workMessage="Finish or recall the machinery recovery party before this voyage."
	var r: Dictionary=_island_allowance(c,float(outbound.distance),float(back.distance),shore,route_ok,message)
	r.merge({"siteId":site_id,"siteName":str(site.name),"returnPortId":str(harbor.get("id","")),"returnPortName":str(harbor.get("name","Unselected")),"targetLevel":clampi(target_level,2,3)},true)
	var now: Dictionary={"ok":false,"distance":0.0} if harbor.is_empty() else _leg(c,c.state.position,harbor)
	r.returnNow=_island_allowance(c,0,float(now.distance),blank,now.ok and legal,"Return directly to "+r.returnPortName+"; recall any shore party first (unused rations return).")
	r.detour={}
	if not detour_site_id.is_empty() and detour_site_id!=site_id:
		var detour: Dictionary=_known_site(c.state,detour_site_id)
		if detour.is_empty():r.detour=_island_allowance(c,0,0,blank,false,"Optional landing is not known; no details quoted.")
		else:
			var side: Dictionary=_leg(c,origin,detour)
			var home: Dictionary={"ok":false,"distance":0.0} if harbor.is_empty() else _leg(c,detour,harbor)
			var after_main: Dictionary=c.state.duplicate(true)
			after_main.exploration.assignment={}
			var extra: Dictionary=_shore_plan(after_main,detour_site_id,3)
			var combined: Dictionary=shore.duplicate(true)
			for key in ["shoreDays","chartDays","surveyDays","shoreFood","shoreKits"]:combined[key]+=extra[key]
			combined.crewNeeded=maxi(int(shore.crewNeeded),int(extra.crewNeeded))
			combined.work.append_array(extra.work)
			r.detour=_island_allowance(c,float(outbound.distance)+float(side.distance),float(home.distance),combined,outbound.ok and side.ok and home.ok and legal,"Optional "+str(detour.name)+" before returning to "+r.returnPortName)
			r.detour["siteName"]=str(detour.name)
		r.detour["extraDays"]=float(r.detour.tripDays)-float(r.returnNow.tripDays)
	return r
