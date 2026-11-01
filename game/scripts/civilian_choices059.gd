extends RefCounted
## One selected read. Never opens offers, swaps live state or settles the calendar.
const Expedition=preload("res://scripts/expedition.gd")
const Routes=preload("res://scripts/route_cache.gd")
const Transport=preload("res://scripts/passenger_transport.gd")
const Intel=preload("res://scripts/trade_intel.gd")
const Economy=preload("res://scripts/economy.gd")
const Goods=preload("res://scripts/goods.gd")
const Factions=preload("res://scripts/factions.gd")
const Support=preload("res://scripts/fleet_support.gd")
const Harbor=preload("res://scripts/harbor.gd")
const Escort=preload("res://scripts/escort_ops.gd")
const Deployment=preload("res://scripts/deployment.gd")
const FleetIdentity=preload("res://scripts/fleet_identity.gd")
const CivilianWork=preload("res://scripts/civilian_work.gd")
const Contacts=preload("res://scripts/contacts.gd")
const Objectives=preload("res://scripts/battle_objectives.gd")
const CIVILIAN_KINDS=["freight","fuel_delivery","passenger_charter"]
const NEXT_ROLE_HULLS={"fishing":"brinehook_longliner","freight":"tideledger_coaster","fuel_delivery":"blackwater_fleet_tanker","passenger_charter":"osprey_cabin_cruiser"}
const ROLE_FITTINGS={"fishing":"cargo_rig","freight":"cargo_rig","fuel_delivery":"auxiliary_tanks","passenger_charter":"cargo_rig"}

# The real conversion quote normalizes relationships. Keep that normalization
# on detached state, including when quoting the last visited yard from sea.
class ConversionView086 extends RefCounted:
	var state: Dictionary
	var data: Dictionary
	var dock: Dictionary
	var source
	func _init(c,p: Dictionary):
		state=c.state.duplicate(true);data=c.data;dock=p.duplicate(true);source=c
		state.path=[]
	func current_port() -> Dictionary:return dock
	func find_boat(uid: String) -> Dictionary:
		for b in state.get("fleet",[]):
			if str(b.get("uid",""))==uid:return b
		return {}
	func fitted_spec(b: Dictionary) -> Dictionary:return source.fitted_spec(b)
	func fail(message: String) -> Dictionary:return {"ok":false,"message":message}

static func physical_hold(c,b: Dictionary) -> float:
	if b.is_empty():return 0.0
	# Same 058 physical correction as CivilianWork: lockers stay on their hull.
	var captive_overflow: float=maxf(0,float(c.state.get("captiveBerths",{}).get(str(b.uid),0))-maxf(0,float(b.crewMax)-float(b.crew)))
	return maxf(0,Transport.available_hold(c,b)-Expedition.locker_weight(b)-captive_overflow)

static func _home_point086(p: Dictionary) -> bool:
	return not p.is_empty() and str(p.get("regionId","shatter_coast"))=="shatter_coast"

static func _leg(c,a: Dictionary,b: Dictionary) -> Dictionary:
	if not Expedition.home_local064(c.state) or not _home_point086(a) or not _home_point086(b):return {"ok":false,"distance":0.0}
	# A preview must not fill Campaign.cached_path or change its hit counters.
	var path: Array=Routes.path({"state":c.state,"nav":c.nav},a,b)
	var distance: float=0.0
	for i in range(1,path.size()):distance+=c.distance(path[i-1],path[i])
	return {"ok":not path.is_empty(),"distance":distance}

static func _access(c,p: Dictionary) -> Dictionary:
	# Politics.access calls ensure on the live campaign. These existing faction
	# reads plus the saved pass give the same civilian entry without that write.
	var a: Dictionary=Factions.access(c.state,p)
	var until: float=float(c.state.get("relationships",{}).get("safeConduct",{}).get(str(p.get("id","")),0))
	if until>float(c.state.day):
		a.legal=true;a.contracts=true;a.inspection=true
		a.reason="Paid civilian safe conduct until day %.2f; inspected entry. Fleets at sea remain independent."%until
	return a

static func _report(c,p: Dictionary) -> Dictionary:
	# Intel.report repairs its quote book. Copy just that book, never live ports,
	# an entire world or a Campaign constructor, and do not record a new visit.
	var state: Dictionary=c.state.duplicate()
	state.tradeIntel=c.state.get("tradeIntel",{}).duplicate(true)
	return Intel.report({"state":state,"world":c.data,"nav":c.nav},str(p.get("id","")))

static func _budget(c,outward: float,returning: float,work: float,price_port: Dictionary,work_fuel: float=0.0,work_food: float=0.0,working_uid: String="",prices: Dictionary={}) -> Dictionary:
	var duration: float=maxf(0,outward)+maxf(0,returning)+maxf(0,work)
	var phase: float=fposmod(float(c.state.day),1.0)
	# Round up the last partial payroll day; expose that conservative model.
	var payroll: int=ceili(duration+phase) if duration>0 else 0
	var prep: Dictionary=Expedition.report(c.state,c.data,0,c.travel_speed(),{"outwardDays":outward,"returnDays":returning,"shoreDays":work,"shoreFood":work_food,"foodCredit":float(c.state.get("surveyFoodCredit",0))})
	var daily: Dictionary=Economy.daily_upkeep(c.state.get("fleet",[]))
	var wages_per_day: int=int(daily.wages)+Support.premium(c.state)
	var arrears: int=ceili(float(c.state.get("wageArrears",0)))+Support.premium(c.state,true)
	var pending: int=maxi(maxi(0,int(c.pending_days)),maxi(0,floori(float(c.state.day))-int(c.state.get("econDay",floori(float(c.state.day))))))
	var food_price: int=int(prices.get("food",Economy.price(price_port,"food","buy") if not price_port.is_empty() else 0))
	var fuel_price: int=int(prices.get("fuel",Economy.price(price_port,"fuel","buy") if not price_port.is_empty() else 0))
	var fuel: float=work_fuel
	var burn: float=0.0
	var boat_fuel: Array=[]
	# Campaign burns moving fuel on every afloat, unstored powered hull,
	# including an undercrewed/towed hull; its tanks cannot be pooled.
	for b in c.state.get("fleet",[]):
		if b.get("sunk",false) or b.get("mothballed",false) or not str(b.get("storedPort","")).is_empty():continue
		var rate: float=Expedition._fuel_per_day(b)
		burn+=rate;fuel+=rate*(outward+returning)
		var needed: float=rate*(outward+returning+float(prep.reserveDays))+(work_fuel if str(b.uid)==working_uid else 0.0)
		var loaded: float=maxf(0,float(b.get("fuel",0)))
		var tank: float=maxf(0,float(b.spec.get("fuelCapacity",60)))
		boat_fuel.append({"uid":str(b.uid),"name":str(b.name),"loaded":loaded,"required":needed,"shortfall":maxf(0,needed-loaded),"tankShortfall":maxf(0,needed-tank)})
	var food: float=maxf(work_food,float(daily.food)*payroll)
	var wages: int=wages_per_day*payroll
	var costs: int=wages+ceili(food*food_price)+ceili(fuel*fuel_price)
	var reserve: int=ceili(float(prep.reserveDays)*(wages_per_day+float(daily.food)*food_price+burn*fuel_price))
	var food_required: float=maxf(work_food,float(daily.food)*(payroll+int(prep.reserveDays)+pending)-float(c.state.get("surveyFoodCredit",0)))
	var fuel_short: float=0.0
	for row in boat_fuel:fuel_short+=float(row.shortfall)
	var food_short: float=maxf(0,food_required-float(c.state.get("cargo",{}).get("food",0)))
	var preparation: int=ceili(food_short)*food_price+ceili(maxf(0,fuel_short-float(c.state.get("cargo",{}).get("fuel",0))))*fuel_price
	var pending_cost: int=pending*wages_per_day
	var funding: int=(payroll+int(prep.reserveDays))*wages_per_day+pending_cost+arrears+preparation
	var risks: Array=[]
	if food_price<=0 or fuel_price<=0:risks.append("No current or dated replacement prices; operating margin is unavailable.")
	if food_short>0.000001:risks.append("Load %.2f more crew ration bales for work, return and contingency."%food_short)
	for row in boat_fuel:
		if float(row.shortfall)>0.000001:risks.append("%s needs %.2f more working fuel; %.2f of its allowance is beyond its own tank."%[row.name,row.shortfall,row.tankShortfall])
	if funding>int(c.state.get("coins",0)):risks.append("Departure allowance needs %d more actual coins before any fee is earned."%(funding-int(c.state.get("coins",0))))
	if pending>0:risks.append("%d prior calendar days await ordinary economy settlement; this review does not settle them."%pending)
	if float(prep.overload)>0.000001:risks.append("Current fleet holds are overloaded by %.2f space."%float(prep.overload))
	return {"operatingDays":duration,"outwardDays":outward,"returnDays":returning,"workDays":work,"payrollDays":payroll,
		"dailyWages":wages_per_day,"wages":wages,"food":food,"fuel":fuel,"foodCost":ceili(food*food_price),"fuelCost":ceili(fuel*fuel_price),"operatingCost":costs,
		"reserveDays":float(prep.reserveDays),"reserveFunding":reserve,"arrears":arrears,"pendingDays":pending,"pendingPayroll":pending_cost,
		"preparationCost":preparation,"fundingRequired":funding,"fundingShortfall":maxi(0,funding-int(c.state.get("coins",0))),
		"priced":food_price>0 and fuel_price>0,"pricePort":str(prices.get("name",price_port.get("name","No current replacement quote"))),"priceDay":float(prices.get("day",c.state.day)),
		"foodRequired":food_required,"foodShortfall":food_short,"fuelShortfall":fuel_short,"looseFuel":float(c.state.get("cargo",{}).get("fuel",0)),
		"boats":boat_fuel,"preparation":prep,"warnings":risks}

static func _conversion_quote086(c,boat: Dictionary,port: Dictionary,conv_id: String) -> Dictionary:
	var conv: Dictionary=FleetIdentity.CONVERSIONS.get(conv_id,{})
	if conv.is_empty():return {}
	var view=ConversionView086.new(c,port)
	var q: Dictionary=FleetIdentity.quote_conversion(view,str(boat.get("uid","")),conv_id)
	var here: bool=not port.is_empty() and str(c.current_port().get("id",""))==str(port.id) and c.state.path.is_empty()
	return {"id":conv_id,"name":str(conv.get("name",conv_id)),"trade":str(conv.get("trade","")),"installed":str(boat.get("conversion",""))==conv_id,
		"costCoins":int(q.get("cost",0)),"materialsCoins":int(q.get("materialCost",0)),
		"laborCoins":int(q.get("shipwrightWages",0))+int(q.get("mechanicWages",0))+int(q.get("engineerWages",0)),
		"yardMarginCoins":int(q.get("margin",0)),"taxCoins":int(q.get("tax",0)),"quoteAvailable":q.has("cost"),
		"ready":here and bool(q.get("ok",false)),"referenceOnly":not here,"message":str(q.get("message","")),
		"portId":str(port.get("id","")),"portName":str(port.get("name","Reference yard"))}

static func reinvestment086(c,role_or_kind: String,boat_uid: String="",estimated_net: int=0) -> Dictionary:
	var hull_id: String=str(NEXT_ROLE_HULLS.get(role_or_kind,"tideledger_coaster"))
	var conv_id: String=str(ROLE_FITTINGS.get(role_or_kind,"cargo_rig"))
	var dock: Dictionary=c.current_port()
	var at_harbor: bool=not dock.is_empty()
	if dock.is_empty():dock=c.port(str(c.state.get("lastPort","")))
	if dock.is_empty():
		for p in c.state.get("ports",[]):
			if _home_point086(p):dock=p;break
	var boat: Dictionary=c.find_boat(boat_uid) if not boat_uid.is_empty() else {}
	if boat.is_empty() and not c.active_fleet().is_empty():boat=c.active_fleet()[0]
	var h: Dictionary=c.hull(hull_id)
	var hq: Dictionary=Harbor.quote(c,h,dock)
	var crew_min: int=int(h.get("crewMin",1))
	var crew_advance: int=Economy.recruit_cost(dock,crew_min) if not dock.is_empty() else crew_min*Goods.SAILOR_WAGE*10
	var entry_coins: int=int(hq.get("readyPrice",0))+crew_advance
	var purchase: Dictionary=Harbor.purchase_plan(c,h,dock)
	var reserve: int=int(purchase.get("returnReserveCoins",0))
	var net_pos: int=maxi(0,estimated_net)
	var fitting: Dictionary=_conversion_quote086(c,boat,dock,conv_id)
	if bool(fitting.get("installed",false)):
		var alt_id: String="auxiliary_tanks" if conv_id=="cargo_rig" else "cargo_rig"
		fitting=_conversion_quote086(c,boat,dock,alt_id)
	var fit_cost: int=int(fitting.get("costCoins",0))
	fitting["netContributionCoins"]=mini(net_pos,fit_cost)
	fitting["remainingGapCoins"]=maxi(0,fit_cost-int(c.state.get("coins",0))-net_pos)
	var next_hull: Dictionary={"id":hull_id,"name":str(h.get("name",hull_id)),"readyCoins":int(hq.get("readyPrice",0)),
		"commissionCoins":int(hq.get("commissionPrice",0)),"minimumCrew":crew_min,"crewAdvanceCoins":crew_advance,"entryCoins":entry_coins,
		"stock":int(dock.get("shipStock",{}).get(hull_id,0)),"cargo":float(h.get("cargo",0)),"berths":int(h.get("crewMax",0)),
		"returnReserveCoins":reserve,"purchaseAndReserveCoins":entry_coins+reserve,"purchasePlan":purchase,
		"netContributionCoins":mini(net_pos,entry_coins+reserve),"remainingGapCoins":maxi(0,entry_coins+reserve-int(c.state.get("coins",0))-net_pos)}
	var fit_price: String="%d coins"%fit_cost if bool(fitting.get("quoteAvailable",false)) else "quote unavailable"
	var summary: String="Reinvestment at %s: %s (%s, %s) or %s (%d ready + %d crew advance = %d coins; %d commission), plus %d coins working stores/payroll/repair reserve. %s"%[
		str(dock.get("name","yard")),str(fitting.get("name","Fitting")),fit_price,str(fitting.get("trade","interior conversion")),
		str(next_hull.name),int(next_hull.readyCoins),crew_advance,entry_coins,int(next_hull.commissionCoins),reserve,
		"Yard reference; return for a fresh quote." if not at_harbor else "Check actual yard stock, crew and stores before buying."]
	return {"role":role_or_kind,"portId":str(dock.get("id","")),"portName":str(dock.get("name","Reference harbor")),"atHarbor":at_harbor,
		"nextHull":next_hull,"nextFitting":fitting,"summary":summary}

static func witnessed_convoy_opportunities086(c) -> Array:
	var rows: Array=[]
	if not Expedition.home_local064(c.state) or not c.has_method("fleet_owner"):return rows
	var combat: Array=c.active_fleet().filter(func(b):return not b.get("supportOnly",false))
	for owner in c.state.get("fleetOwners",[]):
		if not owner is Dictionary or not bool(owner.get("active",false)) or str(owner.get("kind",""))!="trader":continue
		var patrol: Dictionary={}
		for p in c.state.get("patrols",[]):
			if str(p.get("id",""))==str(owner.get("id","")) and bool(p.get("active",false)):patrol=p;break
		if patrol.is_empty():continue
		var location: Dictionary=c.NavalAI.NavalOrders.canonical_location068(c.state,str(owner.id))
		if location.is_empty() or not Expedition.home_local064(location):continue
		var dist: float=c.distance(c.state.position,location.position)
		if dist>1800.0:continue
		var load: Dictionary=Escort._load_plan(c,owner)
		if not bool(load.get("ok",false)):continue
		var threat: Dictionary=Escort.threat(c,owner)
		var good: String=str(owner.get("tradeGood","food"))
		var qty: float=float(owner.get("cargo",{}).get(good,0))
		var dest_id: String=str(patrol.get("to",owner.get("destination","")))
		var dest_port: Dictionary=c.port(dest_id)
		var cargo_val: int=0
		for actual_good in owner.get("cargo",{}):
			var unit_val: int=int(Goods.ITEMS.get(actual_good,{}).get("base",60))
			cargo_val+=maxi(0,roundi(float(owner.cargo[actual_good])*unit_val))
		var convoy_boats: Array=owner.get("boats",[]).filter(func(b):return not b.get("sunk",false) and int(b.get("crew",0))>=int(b.get("crewMin",1)))
		var dp: int=Deployment.total(convoy_boats+combat)
		var hostile_to_player: bool=Factions.is_hostile(c.state,str(owner.get("faction","")))
		var mission: Dictionary=Escort._mission(c,owner,"escort")
		mission["allyUids"]=convoy_boats.map(func(b):return str(b.uid))
		var event: String="escort:%s:%d"%[str(owner.id),int(patrol.get("voyageSeq",0))]
		var escort_ok: bool=not hostile_to_player and not threat.is_empty() and dp<=Deployment.LIMIT and not combat.is_empty() and not convoy_boats.is_empty() and not c.state.get("escortEvents",{}).has(event)
		if escort_ok:escort_ok=not mission.has("startError") and Objectives.deployment_error(convoy_boats+combat,threat.get("boats",[]).filter(func(b):return not b.get("sunk",false)),mission).is_empty()
		var intercept: Dictionary=Escort.prepare_intercept(c,{"kind":"patrol","ownerId":str(owner.id),"id":str(owner.id)})
		var piracy_ok: bool=intercept.has("mission") and str(intercept.get("startError","")).is_empty()
		rows.append({"ownerId":str(owner.get("id","")),"name":str(owner.get("name","Trader convoy")),"faction":str(owner.get("faction","")),
			"destination":dest_id,"destinationName":str(dest_port.get("name",dest_id)),"distance":dist,"hailReady":dist<=260.0,
			"tradeGood":good,"tradeCargo":qty,"cargo":owner.get("cargo",{}).duplicate(true),"cargoValueCoins":cargo_val,"valueBasis":"Reference catalog prices; no live remote market quote.","observedDay":float(c.state.day),"carrierUids":load.get("carrierUids",[]).duplicate(),
			"threatOwnerId":str(threat.get("id","")),"threatName":str(threat.get("name","")),"deploymentPoints":dp,
			"escortEligible":escort_ok,"escortStandingReward":5,"escortServiceCredit":1,"piracyInterceptEligible":piracy_ok})
	rows.sort_custom(func(a,b):
		if not is_equal_approx(float(a.distance),float(b.distance)):return float(a.distance)<float(b.distance)
		return str(a.ownerId)<str(b.ownerId)
	)
	return rows

static func _carrier_alternatives086(c,kind: String,required: float,people: int) -> Array:
	var rows: Array=[]
	var fleet_free: float=maxf(0,c.capacity()-c.cargo_weight())
	for candidate in c.active_fleet():
		var role: String=str(candidate.get("spec",{}).get("civilianRole",""))
		var role_ok: bool=true
		if kind=="fuel_delivery":role_ok=role in ["transport","tanker"]
		elif kind=="passenger_charter":role_ok=role in ["transport","yacht"]
		var hold: float=physical_hold(c,candidate)
		var berths: int=Transport.spare(c,candidate)
		var fits: bool=role_ok and fleet_free+0.000001>=required and hold+0.000001>=required and (people==0 or berths>=people)
		rows.append({"uid":str(candidate.uid),"name":str(candidate.name),"role":role,"holdFree":hold,"spareBerths":berths,"fits":fits})
	return rows

static func role_alternatives086(c,kind: String,offers: Array=[],carrier_uid: String="") -> Array:
	var list: Array=offers
	if list.is_empty() and c.get("VoyageJobs")!=null:list=c.VoyageJobs.available(c)
	var rows: Array=[]
	for item in list:
		if not item is Dictionary or str(item.get("kind",""))!=kind:continue
		var rev: Dictionary=job_review(c,item,carrier_uid)
		if not bool(rev.get("ok",false)):continue
		rows.append({"id":str(item.get("id","")),"title":str(item.get("title","")),"kind":kind,"loadTier":str(item.get("loadTier","small")),
			"port":str(item.get("port","")),"targetPort":str(rev.get("targetPort","")),"targetName":str(rev.get("targetName","")),
			"ownerId":str(item.get("ownerId","")),"loadWeight":float(rev.get("loadWeight",0)),"passengers":int(rev.get("passengers",0)),
			"passengerFood":float(rev.get("passengerFood",0)),"carrierUid":str(rev.get("carrierUid","")),"carrierName":str(rev.get("carrierName","")),
			"carrierFits":bool(rev.get("carrierFits",false)),"allowanceFits":bool(rev.get("allowanceFits",false)),"routeOk":bool(rev.get("routeOk",false)),
			"outwardDays":float(rev.get("budget",{}).get("outwardDays",0)),"returnDays":float(rev.get("budget",{}).get("returnDays",0)),
			"grossFee":int(rev.get("grossFee",0)),"operatingCost":int(rev.get("budget",{}).get("operatingCost",0)),"estimatedNet":int(rev.get("estimatedNet",0)),
			"recipientPresent":bool(rev.get("recipient",{}).get("present",kind!="fuel_delivery")),"repeatClientCount":int(rev.get("clientMemory",{}).get("completedCount",0))})
	return rows

static func job_review(c,offer: Dictionary,carrier_uid: String="") -> Dictionary:
	var job: Dictionary=offer.duplicate(true)
	var active: bool=false
	for carried in c.state.get("voyageJobs",[]):
		if str(carried.id)==str(job.get("id","")):job=carried.duplicate(true);active=true;break
	if not str(job.get("kind","")) in CIVILIAN_KINDS:return {"ok":false,"message":"Use the existing survey or bounty terms for this work."}
	var origin: Dictionary=c.port(str(job.get("port","")))
	var target: Dictionary=c.port(str(job.get("targetPort","")))
	var kind: String=str(job.kind)
	var lot: Dictionary=job.get("freight",{})
	var load: float=float(lot.get("qty",0))*float(Goods.ITEMS.get(str(lot.get("good","")),{"weight":1}).weight)
	var people: int=int(job.get("passengers",{}).get("n",0))
	var rations: float=float(job.get("charterFood",{}).get("food",0))
	var uid: String=str(job.get("carrierUid","")) if active else carrier_uid
	if uid.is_empty():
		for candidate in c.active_fleet():
			var role: String=str(candidate.spec.get("civilianRole",""))
			if kind=="fuel_delivery" and role not in ["transport","tanker"]:continue
			if kind=="passenger_charter" and role not in ["transport","yacht"]:continue
			uid=str(candidate.uid)
			if physical_hold(c,candidate)+0.000001>=maxf(load,rations) and (people==0 or Transport.spare(c,candidate)>=people):break
	var b: Dictionary=c.find_boat(uid)
	var hold: float=physical_hold(c,b)
	var berths: int=Transport.spare(c,b) if not b.is_empty() else 0
	var fleet_free: float=maxf(0,c.capacity()-c.cargo_weight())
	var required: float=rations if kind=="passenger_charter" else load
	var fits: bool=not b.is_empty() and c.active_fleet().has(b)
	if not active:
		fits=fits and fleet_free+0.000001>=required
		if kind=="fuel_delivery":fits=fits and str(b.get("spec",{}).get("civilianRole","")) in ["transport","tanker"] and hold+0.000001>=load
		if kind=="passenger_charter":fits=fits and str(b.get("spec",{}).get("civilianRole","")) in ["transport","yacht"] and hold+0.000001>=rations and berths>=people
	var outward: Dictionary=_leg(c,c.state.position,target)
	var returning: Dictionary=_leg(c,target,origin)
	var speed: float=c.travel_speed()
	var outward_days: float=float(outward.distance)/maxf(0.01,speed)/45.0
	var return_days: float=float(returning.distance)/maxf(0.01,speed)/45.0
	# routeDays sizes purchased passenger provisions; settlement requires actual
	# sailing and positive elapsed time, not a mandatory whole-day wait.
	var work: float=0.0
	var price_port: Dictionary=c.current_port()
	var prices: Dictionary={}
	if price_port.is_empty():
		var report: Dictionary=_report(c,origin)
		if report.get("seen",false):prices={"food":int(report.get("buy",{}).get("food",0)),"fuel":int(report.get("buy",{}).get("fuel",0)),"name":str(origin.get("name","Recorded origin")),"day":float(report.get("observedDay",0))}
	var budget: Dictionary=_budget(c,outward_days,return_days,work,price_port,0,0,"",prices)
	var gross: int=int(job.get("reward",0))
	var custody: int=int(job.get("savingsHousehold",0))+int(job.get("savingsExpert",0))
	var payable: int=mini(gross,maxi(0,int(job.get("escrow",0))-custody)) if active else gross
	var access: Dictionary=_access(c,target)
	var risks: Array=budget.warnings.duplicate()
	if not fits:risks.append("The selected carrier or whole fleet cannot carry this actual load with its current occupants, lockers and working stores.")
	if not outward.ok or not returning.ok or speed<=0:risks.append("No navigable outward and return route for the actual fleet.")
	if not access.legal:risks.append(str(access.reason))
	if active and (str(job.get("state",""))!="active" or job.get("failed",false)):payable=0;risks.append("This commitment is expired or failed; the contracted fee is not available as income.")
	if target.get("blockaded",false):risks.append("Destination is blockaded; access and supply can change before arrival.")
	if float(c.state.day)+outward_days+work>float(job.get("deadlineDay",0)):risks.append("Estimated arrival/work exceeds the current deadline.")
	if active and kind=="passenger_charter" and float(job.get("voyageDistance",0))+float(outward.distance)+65.0<float(job.get("routeDistance",0)):risks.append("The remaining direct route will not satisfy the charter's recorded sailing-distance promise; prior travel is not a free completion.")
	var added_weight: float=0.0 if active else required
	var fuel_overflow: float=0.0
	for row in budget.boats:fuel_overflow+=float(row.tankShortfall)
	var allowance_extra: float=ceilf(float(budget.foodShortfall))+maxf(0,fuel_overflow-float(budget.looseFuel))
	var allowance_fits: bool=added_weight+allowance_extra<=fleet_free+0.000001
	if not allowance_fits:risks.append("This load plus missing return/contingency stores exceeds current free fleet hold by %.2f space; offload or prepare another real carrier."%(added_weight+allowance_extra-fleet_free))
	var recipient: Dictionary={}
	if kind=="fuel_delivery":
		recipient=c.VoyageJobs.recipient_status(c,job).duplicate(true)
		risks.append(str(recipient.message))
	var memory: Dictionary={}
	var contact_id: String=str(job.get("sponsorContactId",""))
	if contact_id.is_empty() and kind=="fuel_delivery":contact_id="captain:"+str(job.get("ownerId",""))
	if not contact_id.is_empty():memory=Contacts.client_memory(c.state,contact_id).duplicate(true)
	if memory.is_empty():memory=job.get("clientMemory",{}).duplicate(true)
	var net: int=payable-int(budget.operatingCost)
	return {"ok":true,"job":job,"active":active,"carrierUid":uid,"carrierName":str(b.get("name","No eligible carrier")),"carrierFits":fits,"allowanceFits":allowance_fits,
		"holdFree":hold,"fleetHoldFree":fleet_free,"lockerWeight":Expedition.locker_weight(b),"spareBerths":berths,"loadWeight":load,"passengers":people,"passengerFood":rations,
		"grossFee":gross,"payableFee":payable,"savingsCustody":custody,"feeReserved":maxi(0,int(job.get("escrow",0))-custody),"estimatedNet":net,
		"budget":budget,"originName":str(origin.get("name","Unknown harbor")),"targetName":str(target.get("name","Unknown harbor")),"targetPort":str(target.get("id","")),
		"routeOk":bool(outward.ok) and bool(returning.ok) and speed>0,"access":access,"recipient":recipient,"clientMemory":memory,"warnings":risks,
		"carrierAlternatives":_carrier_alternatives086(c,kind,required,people),"reinvestment":reinvestment086(c,kind,uid,net),
		"convoyOpportunities":witnessed_convoy_opportunities086(c),"estimate":true,"guaranteed":false,"remainingOnly":active}

static func buyer_ports(c) -> Array:
	var rows: Array=[]
	if not Expedition.home_local064(c.state):return rows
	var observations: Dictionary=c.state.get("tradeIntel",{}).get("observations",{})
	var here: String=str(c.current_port().get("id",""))
	for p in c.state.get("ports",[]):
		if not _home_point086(p):continue
		if str(p.id)==here or observations.has(str(p.id)):rows.append({"id":str(p.id),"name":str(p.name)})
	return rows

static func _eval_buyer086(c,buyer: Dictionary,quote: Dictionary,days: float,boat_uid: String,here: Dictionary) -> Dictionary:
	var in_home: bool=_home_point086(buyer)
	var report: Dictionary=_report(c,buyer) if in_home else {}
	var live: bool=in_home and not buyer.is_empty() and str(buyer.get("id",""))==str(here.get("id",""))
	var seen: bool=live or bool(report.get("seen",false))
	var sell: int=Economy.price(buyer,"preserved_fish","sell") if live else int(report.get("sell",{}).get("preserved_fish",0))
	var funds: int=int(buyer.get("cash",0)) if live else int(report.get("businessFunds",0))
	var liq_lots: int=floori(float(funds)/sell) if sell>0 else 0
	var lots: int=mini(int(quote.sellableLots),liq_lots) if sell>0 else 0
	var route: Dictionary=_leg(c,c.state.position,buyer)
	var speed: float=c.travel_speed()
	var route_ok: bool=bool(route.ok) and speed>0
	var travel: float=float(route.distance)/maxf(0.01,speed)/45.0
	var prices: Dictionary={}
	if here.is_empty() and bool(report.get("seen",false)):
		prices={"food":int(report.get("buy",{}).get("food",0)),"fuel":int(report.get("buy",{}).get("fuel",0)),"name":str(buyer.get("name","Buyer")),"day":float(report.get("observedDay",0))}
	var budget: Dictionary=_budget(c,0,travel,days,here,float(quote.fuelNeeded),float(quote.foodNeeded),boat_uid,prices)
	var access: Dictionary=_access(c,buyer) if not buyer.is_empty() else {"legal":false,"reason":"No recorded buyer harbor selected."}
	var blockaded: bool=bool(buyer.get("blockaded",false))
	var qualifies: bool=in_home and route_ok and bool(access.legal) and not blockaded and seen and sell>0 and liq_lots>=1
	var net: int=lots*sell-int(budget.operatingCost)
	var direct_dist: float=c.distance(c.state.position,buyer) if in_home else INF
	return {"buyer":buyer,"report":report,"live":live,"seen":seen,"sell":sell,"funds":funds,"liquidityLots":liq_lots,"lots":lots,
		"route":route,"routeOk":route_ok,"travelDays":travel,"budget":budget,"access":access,"blockaded":blockaded,"qualifies":qualifies,"estimatedNet":net,"directDistance":direct_dist}

static func fishing_review(c,boat_uid: String,days: float=1.0,crew: int=0,buyer_port_id: String="") -> Dictionary:
	var quote: Dictionary=CivilianWork.fishing_quote(c,boat_uid,days,crew).duplicate(true)
	var here: Dictionary=c.current_port()
	var evals: Array=[]
	for row in buyer_ports(c):
		var p: Dictionary=c.port(str(row.id))
		if not p.is_empty():evals.append(_eval_buyer086(c,p,quote,days,boat_uid,here))
	evals.sort_custom(func(a,b):
		if bool(a.qualifies)!=bool(b.qualifies):return bool(a.qualifies)
		if bool(a.qualifies):
			if int(a.estimatedNet)!=int(b.estimatedNet):return int(a.estimatedNet)>int(b.estimatedNet)
			if int(a.lots)!=int(b.lots):return int(a.lots)>int(b.lots)
			if not is_equal_approx(float(a.route.distance),float(b.route.distance)):return float(a.route.distance)<float(b.route.distance)
		else:
			if bool(a.routeOk)!=bool(b.routeOk):return bool(a.routeOk)
			if not is_equal_approx(float(a.directDistance),float(b.directDistance)):return float(a.directDistance)<float(b.directDistance)
		return str(a.buyer.get("id",""))<str(b.buyer.get("id",""))
	)
	var chosen: Dictionary={}
	if not buyer_port_id.is_empty():
		for ev in evals:
			if str(ev.buyer.get("id",""))==buyer_port_id:chosen=ev;break
		if chosen.is_empty():chosen=_eval_buyer086(c,c.port(buyer_port_id),quote,days,boat_uid,here)
	elif not evals.is_empty():
		chosen=evals[0]
	else:
		chosen=_eval_buyer086(c,{},quote,days,boat_uid,here)
	var buyer_alternatives: Array=[]
	for ev in evals:
		buyer_alternatives.append({"portId":str(ev.buyer.get("id","")),"name":str(ev.buyer.get("name","")),"qualifies":bool(ev.qualifies),
			"routeOk":bool(ev.routeOk),"routeDistance":float(ev.route.distance),"returnDays":float(ev.travelDays),"legal":bool(ev.access.legal),
			"blockaded":bool(ev.blockaded),"seen":bool(ev.seen),"sellQuote":int(ev.sell),"businessFunds":int(ev.funds),
			"liquidityLots":int(ev.liquidityLots),"saleLots":int(ev.lots),"estimatedGross":int(ev.lots)*int(ev.sell),
			"operatingCost":int(ev.budget.operatingCost),"estimatedNet":int(ev.estimatedNet)})
	var horizon_alternatives: Array=[]
	for h_days in [0.5,1.0,2.0]:
		var hq: Dictionary=CivilianWork.fishing_quote(c,boat_uid,h_days,crew)
		horizon_alternatives.append({"requestedDays":h_days,"ok":bool(hq.get("ok",false)),"catchMax":float(hq.get("catchMax",0)),
			"sellableLots":int(hq.get("sellableLots",0)),"fuelNeeded":float(hq.get("fuelNeeded",0)),"foodNeeded":float(hq.get("foodNeeded",0)),
			"limitingCause":str(hq.get("limitingCause","none"))})
	var ground_note: String="Current 500-unit cell %s has %.1f / %.0f daily lots left (limit: %s)."%[str(quote.get("siteId","")),float(quote.get("quotaRemaining",0)),float(quote.get("quotaDaily",40)),str(quote.get("limitingCause","none"))]
	if float(quote.get("quotaRemaining",0))+0.0001<float(quote.get("holdFree",0)):
		ground_note+=" Shifting 500+ units to an adjacent open-water cell accesses a separate 40-lot daily quota at extra sailing fuel/time."
	var buyer: Dictionary=chosen.buyer
	var report: Dictionary=chosen.report
	var live: bool=bool(chosen.live)
	var sell: int=int(chosen.sell)
	var funds: int=int(chosen.funds)
	var lots: int=int(chosen.lots)
	var budget: Dictionary=chosen.budget
	var access: Dictionary=chosen.access
	var risks: Array=budget.warnings.duplicate()
	if not bool(chosen.routeOk):risks.append("No navigable return to this buyer for the actual fleet.")
	if not live and not bool(report.get("seen",false)):risks.append("No dated fish sale quote or buyer purse is recorded; visit a real Market.")
	if sell>0 and lots<int(quote.sellableLots):risks.append("The recorded buyer purse covers only %d of the %d forecast whole lots."%[lots,int(quote.sellableLots)])
	if not bool(access.legal):risks.append(str(access.reason))
	if buyer.get("blockaded",false):risks.append("Buyer harbor is blockaded; arrival and market access can change.")
	return {"ok":bool(quote.ok),"quote":quote,"boatUid":boat_uid,"boatName":str(c.find_boat(boat_uid).get("name","No fishing boat")),"budget":budget,
		"buyer":{"portId":str(buyer.get("id","")),"name":str(buyer.get("name","Choose a recorded buyer")),"seen":live or bool(report.get("seen",false)),
			"day":float(c.state.day) if live else float(report.get("observedDay",0)),"age":maxf(0,float(c.state.day)-float(report.get("observedDay",c.state.day))) if report.get("seen",false) and not live else 0.0,"live":live,"sellQuote":sell,
			"businessFunds":funds,"liquidityLots":int(chosen.liquidityLots),"saleLots":lots,"estimatedGross":lots*sell},
		"estimatedNet":int(chosen.estimatedNet),"carriedFish":maxf(0,float(c.state.get("cargo",{}).get("preserved_fish",0))),
		"access":access,"routeOk":bool(chosen.routeOk),"warnings":risks,"buyerAlternatives":buyer_alternatives,
		"horizonAlternatives":horizon_alternatives,"groundAlternativeNote":ground_note,
		"reinvestment":reinvestment086(c,"fishing",boat_uid,int(chosen.estimatedNet)),
		"convoyOpportunities":witnessed_convoy_opportunities086(c),"estimate":true,"guaranteed":false}
