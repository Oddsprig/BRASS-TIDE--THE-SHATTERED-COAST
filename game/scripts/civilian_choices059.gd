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
const CIVILIAN_KINDS=["freight","fuel_delivery","passenger_charter"]

static func physical_hold(c,b: Dictionary) -> float:
	if b.is_empty():return 0.0
	# Same 058 physical correction as CivilianWork: lockers stay on their hull.
	var captive_overflow: float=maxf(0,float(c.state.get("captiveBerths",{}).get(str(b.uid),0))-maxf(0,float(b.crewMax)-float(b.crew)))
	return maxf(0,Transport.available_hold(c,b)-Expedition.locker_weight(b)-captive_overflow)

static func _leg(c,a: Dictionary,b: Dictionary) -> Dictionary:
	if not Expedition.home_local064(c.state) or a.is_empty() or b.is_empty():return {"ok":false,"distance":0.0}
	var path: Array=Routes.path(c,a,b)
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
	if not contact_id.is_empty():memory=c.Contacts.client_memory(c.state,contact_id).duplicate(true)
	if memory.is_empty():memory=job.get("clientMemory",{}).duplicate(true)
	return {"ok":true,"job":job,"active":active,"carrierUid":uid,"carrierName":str(b.get("name","No eligible carrier")),"carrierFits":fits,"allowanceFits":allowance_fits,
		"holdFree":hold,"fleetHoldFree":fleet_free,"lockerWeight":Expedition.locker_weight(b),"spareBerths":berths,"loadWeight":load,"passengers":people,"passengerFood":rations,
		"grossFee":gross,"payableFee":payable,"savingsCustody":custody,"feeReserved":maxi(0,int(job.get("escrow",0))-custody),"estimatedNet":payable-int(budget.operatingCost),
		"budget":budget,"originName":str(origin.get("name","Unknown harbor")),"targetName":str(target.get("name","Unknown harbor")),"targetPort":str(target.get("id","")),
		"routeOk":bool(outward.ok) and bool(returning.ok) and speed>0,"access":access,"recipient":recipient,"clientMemory":memory,"warnings":risks,
		"estimate":true,"guaranteed":false,"remainingOnly":active}

static func buyer_ports(c) -> Array:
	var rows: Array=[]
	var observations: Dictionary=c.state.get("tradeIntel",{}).get("observations",{})
	var here: String=str(c.current_port().get("id",""))
	for p in c.state.get("ports",[]):
		if str(p.id)==here or observations.has(str(p.id)):rows.append({"id":str(p.id),"name":str(p.name)})
	return rows

static func fishing_review(c,boat_uid: String,days: float=1.0,crew: int=0,buyer_port_id: String="") -> Dictionary:
	var quote: Dictionary=c.CivilianWork.fishing_quote(c,boat_uid,days,crew).duplicate(true)
	var buyer: Dictionary=c.port(buyer_port_id)
	if buyer.is_empty():
		var closest: float=INF
		for row in buyer_ports(c):
			var p: Dictionary=c.port(str(row.id))
			var distance: float=c.distance(c.state.position,p)
			if distance<closest:buyer=p;closest=distance
	var report: Dictionary=_report(c,buyer)
	var here: Dictionary=c.current_port()
	var live: bool=not buyer.is_empty() and str(buyer.id)==str(here.get("id",""))
	var sell: int=Economy.price(buyer,"preserved_fish","sell") if live else int(report.get("sell",{}).get("preserved_fish",0))
	var funds: int=int(buyer.get("cash",0)) if live else int(report.get("businessFunds",0))
	var lots: int=mini(int(quote.sellableLots),floori(float(funds)/sell)) if sell>0 else 0
	var route: Dictionary=_leg(c,c.state.position,buyer)
	var travel: float=float(route.distance)/maxf(0.01,c.travel_speed())/45.0
	var prices: Dictionary={}
	if here.is_empty() and bool(report.get("seen",false)):
		prices={"food":int(report.get("buy",{}).get("food",0)),"fuel":int(report.get("buy",{}).get("fuel",0)),"name":str(buyer.get("name","Buyer")),"day":float(report.get("observedDay",0))}
	var budget: Dictionary=_budget(c,0,travel,days,here,float(quote.fuelNeeded),float(quote.foodNeeded),boat_uid,prices)
	var risks: Array=budget.warnings.duplicate()
	if not route.ok:risks.append("No navigable return to this buyer for the actual fleet.")
	if not live and not report.get("seen",false):risks.append("No dated fish sale quote or buyer purse is recorded; visit a real Market.")
	if sell>0 and lots<int(quote.sellableLots):risks.append("The recorded buyer purse covers only %d of the %d forecast whole lots."%[lots,int(quote.sellableLots)])
	var access: Dictionary=_access(c,buyer)
	if not access.legal:risks.append(str(access.reason))
	if buyer.get("blockaded",false):risks.append("Buyer harbor is blockaded; arrival and market access can change.")
	return {"ok":bool(quote.ok),"quote":quote,"boatUid":boat_uid,"boatName":str(c.find_boat(boat_uid).get("name","No fishing boat")),"budget":budget,
		"buyer":{"portId":str(buyer.get("id","")),"name":str(buyer.get("name","Choose a recorded buyer")),"seen":live or bool(report.get("seen",false)),
			"day":float(c.state.day) if live else float(report.get("observedDay",0)),"age":maxf(0,float(c.state.day)-float(report.get("observedDay",c.state.day))) if report.get("seen",false) and not live else 0.0,"live":live,"sellQuote":sell,
			"businessFunds":funds,"liquidityLots":floori(float(funds)/sell) if sell>0 else 0,"saleLots":lots,"estimatedGross":lots*sell},
		"estimatedNet":lots*sell-int(budget.operatingCost),"carriedFish":maxf(0,float(c.state.get("cargo",{}).get("preserved_fish",0))),
		"access":access,"routeOk":bool(route.ok),"warnings":risks,"estimate":true,"guaranteed":false}
