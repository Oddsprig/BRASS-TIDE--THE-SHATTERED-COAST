extends RefCounted
## Read-only career quotations. Normalizing domain reads receive a detached state;
## no accept, begin, settle, payroll, discovery, clock or market transaction runs.
const Jobs=preload("res://scripts/voyage_jobs.gd")
const Exploration=preload("res://scripts/exploration.gd")
const Expedition=preload("res://scripts/expedition.gd")
const Goods=preload("res://scripts/goods.gd")
const Economy=preload("res://scripts/economy.gd")
const Harbor=preload("res://scripts/harbor.gd")
const Reserves=preload("res://scripts/harbor_reserves.gd")
const Transport=preload("res://scripts/passenger_transport.gd")
const Fishing=preload("res://scripts/civilian_work.gd")
const Escort=preload("res://scripts/escort_ops.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Factions=preload("res://scripts/factions.gd")
const Routes=preload("res://scripts/route_cache.gd")
const Contracts=preload("res://scripts/contracts.gd")
const Choices=preload("res://scripts/civilian_choices059.gd")
const CAREERS=["explorer","merchant","escort","privateer","fisher","passenger"]

class QuoteView extends RefCounted:
	const DAY_SECONDS=45.0
	const Expedition=preload("res://scripts/expedition.gd")
	const NavalAI=preload("res://scripts/naval_ai.gd")
	const Factions=preload("res://scripts/factions.gd")
	const ToolingOps=preload("res://scripts/tooling_ops.gd")
	const CivilianWork=preload("res://scripts/civilian_work.gd")
	const VoyageJobs=preload("res://scripts/voyage_jobs.gd")
	const Contacts=preload("res://scripts/contacts.gd")
	const Damage=preload("res://scripts/damage.gd")
	const FleetSupport=preload("res://scripts/fleet_support.gd")
	var state: Dictionary
	var data: Dictionary
	var nav: Dictionary
	var speed: float
	var pending_days: int=0
	var source
	func _init(c):
		source=c;state=c.state.duplicate(true);data=c.data;nav=c.nav;speed=c.travel_speed();pending_days=int(c.pending_days)
	# These Campaign methods only write the detached preview boat passed in.
	func fitted_spec(b: Dictionary) -> Dictionary:return source.fitted_spec(b)
	func fit_boat(b: Dictionary,fresh: bool=false) -> void:source.fit_boat(b,fresh)
	func _initialize_published_boat(b: Dictionary) -> void:source._initialize_published_boat(b)
	func active_fleet() -> Array:
		var boats: Array=Expedition.traveling(state)
		boats.sort_custom(func(a,b):return a.uid==state.flagship and b.uid!=state.flagship)
		return boats
	func find_boat(uid: String) -> Dictionary:
		for b in state.get("fleet",[]):
			if str(b.get("uid",""))==uid:return b
		return {}
	func capacity() -> float:return Expedition.capacity(state)
	func cargo_weight() -> float:return Expedition.cargo_weight(state)
	func travel_speed() -> float:return speed
	func crew_count() -> int:
		var crew: int=0
		for b in state.get("fleet",[]):
			if not b.get("sunk",false):crew+=int(b.get("crew",0))
		return crew
	func distance(a: Dictionary,b: Dictionary) -> float:return Vector2(a.x,a.y).distance_to(Vector2(b.x,b.y))
	func current_port() -> Dictionary:
		if not Expedition.home_local064(state):return {}
		for p in state.get("ports",[]):
			if distance(state.position,p)<65.0:return p
		return {}
	func _find(rows: Array,id: String) -> Dictionary:
		for row in rows:
			if str(row.id)==id:return row
		return {}
	func hull(id: String) -> Dictionary:return _find(data.get("HULLS",[]),id)
	func port(id: String) -> Dictionary:return _find(state.get("ports",[]),id)
	func port_position(id: String) -> Dictionary:
		var p: Dictionary=port(id)
		return {"x":p.x,"y":p.y} if not p.is_empty() else {}
	func faction(id: String) -> Dictionary:return _find(data.get("FACTIONS",[]),id)
	func fleet_owner(id: String) -> Dictionary:return _find(state.get("fleetOwners",[]),id)

static func _length(v,a: Dictionary,b: Dictionary) -> float:
	if not Expedition.home_local064(v.state):return -1.0
	var path: Array=Routes.path(v,a,b)
	if path.size()<2:return -1.0
	var distance: float=0.0
	for i in range(1,path.size()):distance+=v.distance(path[i-1],path[i])
	return distance

static func _budget(v,distance: float,work_days: float=0.0,kits: float=0.0) -> Dictionary:
	var e: Dictionary=Expedition.report(v.state,v.data,maxf(0,distance))
	var sailing: float=maxf(0,distance)*2.0/maxf(0.01,v.travel_speed())/v.DAY_SECONDS
	var days: float=sailing+float(e.reserveDays)+work_days
	var p: Dictionary=v.current_port()
	var prices: Dictionary={}
	for good in ["food","fuel","supplies","ammo"]:prices[good]=Economy.price(p,good)
	var burn: float=0.0
	var fuel_aboard: float=0.0
	for b in v.active_fleet():
		burn+=Fishing.fuel_rate(b)
		fuel_aboard+=maxf(0,float(b.get("fuel",0)))
	# The interval still includes return and contingency. Coins buy only the
	# shortfall. Tanks and loose drums already aboard are not purchased again.
	var loose_fuel: float=maxf(0,float(v.state.get("cargo",{}).get("fuel",0)))
	var food_needed: float=Economy.daily_upkeep(v.state.get("fleet",[])).food*days
	var food_aboard: float=maxf(0,float(v.state.get("cargo",{}).get("food",0)))
	var food_buy: float=maxf(0,food_needed-food_aboard)
	var wages: int=ceili(float(e.dailyWages)*days)
	var fuel_needed: float=burn*days
	var fuel_buy: float=maxf(0,fuel_needed-fuel_aboard-loose_fuel)
	var food_coins: int=ceili(food_buy*float(prices.food))
	var fuel_coins: int=ceili(fuel_buy*float(prices.fuel))
	var kit_coins: int=ceili(kits*float(prices.supplies))
	var repair: int=0
	var repair_available: bool=not p.is_empty()
	var repair_reason: String="Current dock repair needs a harbor quote."
	if not p.is_empty():
		repair_reason="Current paid hull and installed-module service; future battle damage is unquoted."
		for b in v.active_fleet():
			var q: Dictionary=Harbor.service_quote(v,b,p)
			if q.get("ok",false):repair+=int(q.get("cost",0))
			else:repair_available=false;repair_reason=str(q.get("message","Equipment service quote unavailable."))
	var purchase_total: int=wages+food_coins+fuel_coins+kit_coins+repair
	var food_value: int=ceili(food_needed*float(prices.food))
	var fuel_value: int=ceili(fuel_needed*float(prices.fuel))
	var total: int=wages+food_value+fuel_value+kit_coins+repair
	var summary: String="%.2f days including return and %.0f contingency days: %d coins payroll (%d/day). Food %.2f required, %.2f aboard, buy %.2f / %d coins. Fuel %.2f required, %.2f in tanks and %.2f loose, buy %.2f / %d coins. %.1f work kits / %d coins; current dock repair %s. Wages include the reserve days. Only the food and fuel short of stores already aboard is purchased. Loose fuel is not bought again; load it through Hold. Future damage and ammunition expenditure are extra."%[days,e.reserveDays,wages,int(e.dailyWages),food_needed,food_aboard,food_buy,food_coins,fuel_needed,fuel_aboard,loose_fuel,fuel_buy,fuel_coins,kits,kit_coins,str(repair)+" coins" if repair_available else "unavailable"]
	summary+=" Additional cash allowance %d coins; full replacement-value allowance %d coins, including owned food and fuel valued at current replacement prices. Reward projections and reinvestment use the full value, not cash saved by consuming existing stores."%[purchase_total,total]
	if p.is_empty():summary+=" Material values use reference prices at sea; obtain a local harbor quote before buying."
	return {"days":days,"sailingDays":sailing,"workDays":work_days,"reserveDays":e.reserveDays,"dailyWages":e.dailyWages,"wageCoins":wages,
		"food":food_needed,"foodRequired":food_needed,"foodAboard":food_aboard,"foodPurchase":food_buy,"foodPurchaseCoins":food_coins,"foodCoins":food_value,
		"fuelReserve":fuel_needed,"fuelRequired":fuel_needed,"fuelAboard":fuel_aboard,"looseFuel":loose_fuel,"fuelPurchase":fuel_buy,"fuelPurchaseCoins":fuel_coins,"fuelCoins":fuel_value,
		"workKits":kits,"workKitCoins":kit_coins,
		"repairQuoteCoins":repair,"repairQuoteAvailable":repair_available,"repairNote":repair_reason,"repairKitUnitCoins":prices.supplies,"ammoCaseCoins":prices.ammo,"roundsPerCase":Goods.ROUNDS_PER_CASE,
		"additionalCashCoins":purchase_total,"replacementAllowanceCoins":total,"allowanceCoins":total,"freeHold":e.freeCapacity,"capacity":e.usableCapacity,"prices":prices,"pricePort":p.get("id",""),"summary":summary}

static func contract_offers(c) -> Array:
	return Contracts.available(QuoteView.new(c))

static func contract_quote(c,actual_offer: Dictionary) -> Dictionary:
	if actual_offer.is_empty():return {}
	var v=QuoteView.new(c)
	var j: Dictionary=actual_offer.duplicate(true)
	var current: Dictionary=v.state.get("activeContract",{})
	var active: bool=not current.is_empty() and str(current.id)==str(j.id)
	var listed: bool=active
	if active:j=current.duplicate(true)
	else:
		for offer in Contracts.available(v):
			if str(offer.id)==str(j.id):j=offer;listed=true;break
	var sponsor: Dictionary=v.port(str(j.get("port","")))
	var target: Dictionary=v.port(str(j.get("targetPort","")))
	var reached: bool=Expedition.home_local064(v.state) and not target.is_empty() and v.distance(v.state.position,target)<90.0
	var distance: float=-1.0 if target.is_empty() else (0.0 if reached else _length(v,v.state.position,target))
	var budget: Dictionary=_budget(v,maxf(0,distance))
	var endurance: Dictionary=Expedition.report(v.state,v.data,maxf(0,distance))
	var payer: String=str(j.get("payerKey","cash" if j.get("kind","")=="delivery" else "governmentPurse"))
	var reward: int=int(j.get("reward",0))
	var funded: bool=int(j.get("escrow",0))==reward if active else int(sponsor.get(payer,0))>=reward
	var blockers: Array=[]
	if not listed:blockers.append("This offer is no longer available; refresh the work board.")
	if distance<0:blockers.append("No safe sailing route. Sailing quote unavailable; allowance excludes travel.")
	if not funded:blockers.append("Contract escrow is incomplete." if active else "The sponsor cannot fund this contract's escrow today.")
	if not active and not current.is_empty():blockers.append("Finish or abandon the active contract first.")
	var dock: Dictionary=v.current_port()
	var at_sponsor: bool=not dock.is_empty() and str(dock.id)==str(j.get("port",""))
	var cargo_ok: bool=true
	if not active and j.has("cargo"):
		var good: String=str(j.cargo.good);var qty: float=float(j.cargo.qty)
		cargo_ok=float(sponsor.get("stocks",{}).get(good,0))>=qty and v.cargo_weight()+qty*float(Goods.ITEMS[good].weight)<=v.capacity()
		if not cargo_ok:blockers.append("The sponsor lacks that sealed cargo, or your hold is full.")
	if active and v.state.get("freight",{}).get("lost",false):blockers.append("Sealed freight was lost; the delivery cannot be collected.")
	var can_accept: bool=not active and listed and current.is_empty() and at_sponsor and funded and cargo_ok and distance>=0
	if not active and not at_sponsor:blockers.append("Accept at %s; this route quote excludes any detour to the sponsor."%str(sponsor.get("name","the sponsoring harbor")))
	if v.active_fleet().is_empty():blockers.append("Prepare a seaworthy, crewed traveling boat.")
	if int(v.state.get("wageArrears",0))>0:blockers.append("Existing crew wage arrears are still due.")
	if float(endurance.affordableDays)<float(budget.days):blockers.append("Current purse cannot cover the quoted payroll allowance.")
	if float(endurance.foodDays)<float(budget.days):blockers.append("Food does not cover the return and contingency allowance.")
	if float(endurance.fuelDays)<float(budget.days):blockers.append("Working fuel does not cover the allowance; load loose reserves through Hold.")
	if float(endurance.overload)>0:blockers.append("Holds are overloaded.")
	if not budget.repairQuoteAvailable:blockers.append("Current dock repair quote unavailable at sea.")
	elif int(budget.repairQuoteCoins)>0:blockers.append("Paid hull and installed-module repairs remain quoted separately below.")
	return {"offer":j,"active":active,"atSponsor":at_sponsor,"atDestination":reached,"canAccept":can_accept,"funded":funded,"payerKey":payer,
		"routeAvailable":distance>=0,"routeDistance":distance,"operatingCosts":budget,"endurance":endurance,"grossRewardCoins":reward,
		"estimatedSurplusCoins":reward-int(budget.allowanceCoins) if distance>=0 else null,"secondHull":_second_hull(v,budget,reward),"blockers":blockers,"ready":blockers.is_empty()}

static func _second_hull(v,budget: Dictionary,reward: int) -> Dictionary:
	var p: Dictionary=v.current_port();var best: Dictionary={}
	for id in Harbor.catalogue(v,p):
		var h: Dictionary=v.hull(str(id));var q: Dictionary=Harbor.quote(v,h,p)
		var crew: int=Economy.recruit_cost(p,int(h.crewMin))
		var total: int=int(q.readyPrice)+crew
		if best.is_empty() or total<int(best.entryCoins):
			best={"id":id,"name":h.name,"readyCoins":q.readyPrice,"commissionCoins":q.commissionPrice,"minimumCrew":h.crewMin,"crewAdvanceCoins":crew,"entryCoins":total,"stock":p.get("shipStock",{}).get(id,0)}
	if not best.is_empty():
		var after: int=int(v.state.get("coins",0))-int(v.state.get("wageArrears",0))+reward-int(budget.allowanceCoins)
		best["gapCoins"]=maxi(0,int(best.entryCoins)-after)
	return best

static func _offer(v,kind: String,offers: Array=[]) -> Dictionary:
	var list: Array=offers if not offers.is_empty() else Jobs.available(v)
	for j in list:
		if str(j.kind)==kind:return j
	return {}

static func _job(plan: Dictionary,v,kind: String,offers: Array=[]) -> Dictionary:
	var j: Dictionary=_offer(v,kind,offers)
	if j.is_empty():
		plan.blockers.append("No funded %s offer here today; inspect the work board at a permitted harbor."%kind.replace("_"," "))
		return {}
	plan["quote"]={"id":j.id,"kind":kind,"title":j.title,"rewardCoins":j.reward,"sponsorPort":j.port,"payerKey":j.payerKey,"materialInvoice":j.get("materialInvoice",0),"deadlineDay":j.deadlineDay,"targetPort":j.targetPort}
	plan["firstGoal"]=str(j.title)+": "+str(plan.firstGoal)
	plan.rewardSource+=" Current offer: %d coins from %s, payable only on completion; %d coins of materials are funded separately on acceptance."%[int(j.reward),str(v.port(str(j.port)).get("name",j.port)),int(j.get("materialInvoice",0))]
	if v.state.get("voyageJobs",[]).size()>=Jobs.MAX_ACTIVE:plan.blockers.append("All six side-job places are occupied; finish or safely abandon an existing commitment.")
	return j

static func _entry(plan: Dictionary,v,roles: Array) -> Dictionary:
	for b in v.active_fleet():
		if str(v.hull(str(b.type)).get("civilianRole","")) in roles:return b
	plan.blockers.append("No eligible traveling %s hull; buy or commission one, recruit actual sailors and purchase working stores."%"/".join(roles))
	var p: Dictionary=v.current_port();var best: Dictionary={}
	for id in Harbor.catalogue(v,p):
		var h: Dictionary=v.hull(str(id))
		if str(h.get("civilianRole","")) not in roles:continue
		var q: Dictionary=Harbor.quote(v,h,p)
		if best.is_empty() or int(q.commissionPrice)<int(best.commissionCoins):
			best={"id":h.id,"name":h.name,"commissionCoins":q.commissionPrice,"readyCoins":q.readyPrice,"minimumCrew":h.crewMin,"crewAdvanceCoins":Economy.recruit_cost(p,int(h.crewMin)),"capacity":h.cargo,"berths":h.crewMax}
	if not best.is_empty():
		plan["entryHull"]=best
		plan.requirements.append("Local design %s: commission %d coins or ready stock %d, plus minimum %d sailors' %d-coin advance and stores. Stock, materials, recruits and yard labor must exist."%[best.name,int(best.commissionCoins),int(best.readyCoins),int(best.minimumCrew),int(best.crewAdvanceCoins)])
	return {}

static func plan(c,career: String) -> Dictionary:
	if career not in CAREERS:return {}
	var v=QuoteView.new(c)
	var names: Dictionary={"explorer":"Explorer","merchant":"Merchant","escort":"Escort","privateer":"Privateer","fisher":"Fisher","passenger":"Passenger operator"}
	var p: Dictionary={"id":career,"name":names[career],"firstGoal":"","requirements":[],"operatingCosts":_budget(v,0),"rewardSource":"","nextStep":"","actionId":"jobs","nextActionId":"supply","ready":false,"blockers":[],"basis":"Actual current fleet and harbor quotes; 100 coins per sailor-day. No jobs are accepted or progress advanced.","limits":"One early action, not a career playthrough. The full-fleet allowance includes a return and two contingency days; it is not a promise of profit. Prices and sponsor purses can change."}
	if not Expedition.home_local064(v.state):
		p.blockers=["Return to Shatter Coast for this coastal career quote."];p.nextStep="Return through a Shatter Coast approach."
		return _display(p)
	p["convoyOpportunities"]=Choices.witnessed_convoy_opportunities086(v)
	match career:
		"explorer":_explorer(p,v)
		"merchant":_merchant(p,v)
		"escort":_escort(p,v)
		"privateer":_privateer(p,v)
		"fisher":_fisher(p,v)
		"passenger":_passenger(p,v)
	var e: Dictionary=Expedition.report(v.state,v.data,0)
	if v.active_fleet().is_empty():p.blockers.append("Crew and prepare a seaworthy traveling boat.")
	if float(e.freeCapacity)<=0:p.blockers.append("Free hold space is needed before taking more cargo or provisions.")
	if int(v.state.get("wageArrears",0))>0:p.blockers.append("Settle existing crew wage arrears before committing more payroll.")
	if float(e.affordableDays)<float(p.operatingCosts.days):p.blockers.append("Current purse covers %.2f of the quoted %.2f payroll days after existing arrears; fund the difference before committing."%[float(e.affordableDays),float(p.operatingCosts.days)])
	if float(e.foodDays)<float(p.operatingCosts.days):p.blockers.append("Crew food covers %.2f of the quoted %.2f days; buy the shortfall before sailing."%[float(e.foodDays),float(p.operatingCosts.days)])
	if float(e.fuelDays)<float(p.operatingCosts.days):p.blockers.append("The least-covered boat has %.2f working-fuel days against %.2f quoted; load each boat through Hold. Loose drums are separate."%[float(e.fuelDays),float(p.operatingCosts.days)])
	if int(p.operatingCosts.repairQuoteCoins)>0:p.blockers.append("Review the quoted paid hull and installed-module repairs before committing this fleet.")
	p.ready=p.blockers.is_empty()
	return _display(p)

static func _explorer(p: Dictionary,v) -> void:
	p.firstGoal="Accept one funded survey, sight its island, chart it, survey it and report to its sponsor."
	p.requirements=["Chart: two spare sailors above boat minimums; full survey: four. Paid crew keep their minimum aboard.","Carry the quoted food and 1 chart kit plus 2 survey kits. Sight the site and stop nearby before landing; work takes campaign time."]
	p.rewardSource="The named harbor treasury escrows the survey fee on acceptance. Site knowledge alone creates no coins, free resources or repeat survey reward."
	p.nextStep="Review the island chart's stage quote; carry the quoted kits and keep four spare sailors above boat minimums for the full survey."
	p.nextActionId="exploration"
	var j: Dictionary=_job(p,v,Jobs.KIND_SURVEY)
	if j.is_empty():return
	var site: Dictionary=Exploration.catalog_site(v.state,str(j.siteId))
	var level: int=int(v.state.get("exploration",{}).get("sites",{}).get(str(j.siteId),{}).get("level",0))
	var days: float=0.0;var kits: float=0.0
	for action in [Exploration.ACTION_CHART,Exploration.ACTION_SURVEY]:
		var q: Dictionary=Exploration.quote(v.state,str(j.siteId),action)
		if level<int(q.get("targetLevel",3)):days+=float(q.get("days",0));kits+=float(q.get("supplies",0))
	var distance: float=_length(v,v.state.position,site)
	if distance<0:p.blockers.append("No safe route to the quoted site.")
	p.operatingCosts=_budget(v,maxf(0,distance),days,kits)
	p.quote["siteId"]=j.siteId;p.quote["spareCrew"]=Exploration.spare_crew(v.state);p.quote["crewNeeded"]=4
	if Exploration.spare_crew(v.state)<4:p.blockers.append("Full survey needs four spare sailors above the traveling boats' minimum crews.")
	p.operatingCosts["rewardLessAllowanceCoins"]=int(j.reward)-int(p.operatingCosts.allowanceCoins)

static func _route_neighbors(v,origin_id: String) -> Array:
	var found: Array=[]
	var farm: String=""
	for edge in v.data.get("ROUTES",[]):
		if not (edge is Array) or edge.size()<2:continue
		var a: String=str(edge[0]);var b: String=str(edge[1]);var other: String=""
		if a==origin_id:other=b
		elif b==origin_id:other=a
		if other.is_empty() or other==origin_id or found.has(other):continue
		var port: Dictionary=v.port(other)
		if port.is_empty():continue
		found.append(other)
		if farm.is_empty() and str(port.get("industry",""))=="agriculture":farm=other
	if not farm.is_empty():
		found.erase(farm)
		found.push_front(farm)
	return found

static func _export_good(origin: Dictionary) -> String:
	# Ordinary seeded goods only. The four unseeded finished goods, including
	# preserved fish, are not a same-port sample when their sale stock is closed.
	for good in ["food","timber","logs","fuel","supplies","iron","charcoal","ore","copper","crude","saltpeter","sulfur","gunpowder","ammo","engines","guns"]:
		if floori(Reserves.exportable(origin,good))>=1:return good
	return ""

static func _market_quote(v,origin: Dictionary) -> Dictionary:
	var refused: Dictionary={"ok":false,"good":"","originPort":"","destinationPort":"","buyCoins":0,"sellCoins":0,"unitMarginCoins":0,"buyerCash":0,"stock":0.0,"exportableLots":0,"holdLots":0,"buyerLots":0,"capLots":0,"contrastPort":"","contrastSellCoins":0,"sailed":false,"guidance":"No cross-port own-account quote."}
	if origin.is_empty():
		refused.guidance="No harbor quote at sea. Own-account prices need the current dock and a different authored destination, not a same-port buy and sell."
		return refused
	var neighbors: Array=_route_neighbors(v,str(origin.id))
	refused.originPort=str(origin.id)
	if neighbors.is_empty():
		refused.guidance="No authored route leaves %s. A same-port buy and sell is not used as the route quote."%str(origin.get("name",origin.id))
		return refused
	var good: String=_export_good(origin)
	refused.destinationPort=str(neighbors[0])
	if good.is_empty():
		refused.guidance="%s has no ordinary exportable lot. Unavailable preserved fish is not sampled, and no stock is added."%str(origin.get("name",origin.id))
		return refused
	var destination: Dictionary=v.port(str(neighbors[0]))
	var buy: int=Economy.price(origin,good)
	var sell: int=Economy.price(destination,good,"sell")
	var stock: float=float(origin.get("stocks",{}).get(good,0.0))
	var exportable: int=maxi(0,floori(Reserves.exportable(origin,good)))
	var weight: float=float(Goods.ITEMS[good].weight)
	var free_hold: float=maxf(0.0,v.capacity()-v.cargo_weight())
	var hold_lots: int=floori(free_hold/weight) if weight>0.0 else 0
	var buyer_cash: int=int(destination.get("cash",0))
	var buyer_lots: int=floori(float(buyer_cash)/float(sell)) if sell>0 else 0
	var cap: int=mini(exportable,mini(hold_lots,buyer_lots))
	var margin: int=sell-buy
	var contrast_port: String=""
	var contrast_sell: int=0
	var contrast_clause: String=""
	if neighbors.size()>1:
		var other: Dictionary=v.port(str(neighbors[1]))
		contrast_port=str(other.id)
		contrast_sell=Economy.price(other,good,"sell")
		contrast_clause=" Other authored neighbor %s sells it at %d."%[str(other.get("name",other.id)),contrast_sell]
	var margin_clause: String=("Unit margin %d coins before wages."%margin) if margin>=0 else ("The book loses %d coins a lot before wages."%(-margin))
	var guidance: String="Unsailed %s: buy %d at %s (exportable %d of %.1f stock), sell %d at %s (buyer cash %d). %s Free hold %.1f fits %d lots; live cap %d.%s Not a sailed profit."%[str(Goods.ITEMS[good].name),buy,str(origin.get("name",origin.id)),exportable,stock,sell,str(destination.get("name",destination.id)),buyer_cash,margin_clause,free_hold,hold_lots,cap,contrast_clause]
	return {"ok":true,"good":good,"originPort":str(origin.id),"destinationPort":str(destination.id),"buyCoins":buy,"sellCoins":sell,"unitMarginCoins":margin,"buyerCash":buyer_cash,"stock":stock,"exportableLots":exportable,"holdLots":hold_lots,"buyerLots":buyer_lots,"capLots":cap,"weight":weight,"freeHold":free_hold,"contrastPort":contrast_port,"contrastSellCoins":contrast_sell,"sailed":false,"guidance":guidance}

static func _merchant(p: Dictionary,v) -> void:
	p.firstGoal="Carry a funded sealed freight lot between harbors before risking your own trading capital."
	p.requirements=["The lot must fit actual free hold space; the sponsor must own the goods and fund its invoice and escrow.","Buy and sell only with legal harbor access and a real buyer purse; record destination prices before planning a speculative trade."]
	p.rewardSource="Freight fees come from the sponsoring treasury's escrow; ordinary trading receipts come from the buying business's cash. The quoted unit margin is only the live book."
	p.nextStep="Compare the freight lot with free hold and the return allowance before accepting. Own-account prices are the unsailed cross-port book in the requirements, not a same-port sample and not a sailed profit."
	p.nextActionId="trade"
	var harbor: Dictionary=v.current_port()
	var market: Dictionary=_market_quote(v,harbor)
	p["marketQuote"]=market
	p.requirements.append(str(market.guidance))
	var offers: Array=Jobs.available(v)
	var j: Dictionary=_job(p,v,Jobs.KIND_FREIGHT,offers)
	var freight_alts: Array=Choices.role_alternatives086(v,Jobs.KIND_FREIGHT,offers)
	var fuel_alts: Array=Choices.role_alternatives086(v,Jobs.KIND_FUEL,offers)
	p["alternatives"]=freight_alts
	p["fuelAlternatives"]=fuel_alts
	var surplus: int=0
	if not j.is_empty():
		var distance: float=_length(v,v.state.position,v.port(str(j.targetPort)))
		if distance<0:p.blockers.append("No safe route for this fleet to the freight destination.")
		p.operatingCosts=_budget(v,maxf(0,distance))
		p.quote["freight"]=j.freight.duplicate(true)
		if float(j.freight.qty)*float(Goods.ITEMS[str(j.freight.good)].weight)>v.capacity()-v.cargo_weight():p.blockers.append("The sealed lot exceeds the current free hold.")
		surplus=int(j.reward)-int(p.operatingCosts.allowanceCoins)
		p.operatingCosts["rewardLessAllowanceCoins"]=surplus
	var reinv: Dictionary=Choices.reinvestment086(v,"freight","",surplus)
	p["reinvestment"]=reinv
	p["reinvestmentSummary"]=str(reinv.get("summary",""))
	if not freight_alts.is_empty() or not fuel_alts.is_empty():
		p["alternativesSummary"]="Board options: %d freight load/route choices and %d tanker fuel-restock choices. Compare small (<=8 lot) vs larger (9..16 lot) holds and return fuel/payroll before accepting."%[freight_alts.size(),fuel_alts.size()]

static func _escort(p: Dictionary,v) -> void:
	p.actionId="traffic";p.nextActionId="jobs"
	p.firstGoal="Hail a nearby loaded friendly convoy with an observed armed threat, then protect every carrier through the actual exit."
	p.requirements=["At least one crewed combat boat, working ammunition and stores; all convoy boats plus your escorts must fit the 300-point deployment.","The convoy must be peaceful to you, physically loaded, near enough to hail and threatened by a nearby hostile fleet."]
	p.rewardSource="Successful passage grants one service credit and +5 standing with the convoy's faction. This escort promises 0 coins and no enemy purse."
	p.nextStep="Check coastal traffic for an eligible threatened convoy and protect payroll and stores first. Use the work board for a separately funded job if you need coin income."
	p["quote"]={"rewardCoins":0,"standing":5,"serviceCredit":1}
	var witnessed: Array=p.get("convoyOpportunities",[])
	if not witnessed.is_empty():
		var first_c: Dictionary=witnessed[0]
		p["alternativesSummary"]="Witnessed convoy %s carrying %.0f %s (~%d coins value) toward %s: escort for +5 standing and 1 service credit when threatened, or intercept as piracy."%[str(first_c.get("name","Convoy")),float(first_c.get("tradeCargo",0)),str(first_c.get("tradeGood","cargo")),int(first_c.get("cargoValueCoins",0)),str(first_c.get("destinationName","harbor"))]
	for owner in v.state.get("fleetOwners",[]):
		if not owner.get("active",false) or owner.get("kind","")!="trader" or Factions.is_hostile(v.state,str(owner.faction)):continue
		var load: Dictionary=Escort._load_plan(v,owner)
		if not load.ok:continue
		var hostile: Dictionary=Escort.threat(v,owner)
		if hostile.is_empty():continue
		var target: Dictionary=v.NavalAI._find_patrol(v.state,str(owner.id))
		var distance: float=_length(v,v.state.position,target)
		p.quote.merge({"ownerId":owner.id,"targetOwnerId":hostile.id,"carrierUids":load.carrierUids})
		p.operatingCosts=_budget(v,maxf(0,distance))
		var combat: Array=v.active_fleet().filter(func(b):return not b.get("supportOnly",false))
		if combat.is_empty() or not combat.any(func(b):return float(b.get("ammo",0))>0):p.blockers.append("Prepare a crewed combat boat with actual ammunition.")
		if Deployment.total(owner.boats.filter(func(b):return not b.sunk and b.crew>=b.crewMin)+combat)>Deployment.LIMIT:p.blockers.append("Convoy plus escorts exceed 300 deployment points.")
		if distance<0:p.blockers.append("No safe approach to this convoy.")
		return
	p.blockers.append("No nearby loaded peaceful convoy with an observed armed threat; inspect coastal traffic rather than starting an invented escort.")

static func _privateer(p: Dictionary,v) -> void:
	p.firstGoal="Choose one funded bounty against its named actual raider; review Law, then defeat that fleet and report for escrow."
	p.requirements=["A crewed combat boat with working weapons, fuel, ammunition and repair stock. A bounty does not legalize attacks on peaceful shipping.","Optional boarding: qualified healthy boarders above minimum crew, physical prize capacity and a vulnerable nearby enemy. Two fresh boarders need a 2000-coin advance, real recruits and berths."]
	p.rewardSource="The named harbor's government purse funds bounty escrow. Boarding transfers an existing hull and its actual cargo; a damaged prize requires paid repair, sailors and stores."
	p.nextStep="Review Law before accepting the bounty; budget ammunition, paid repairs and return wages. Inspect Boarding before capture and repair a secured prize before deploying it."
	p.nextActionId="law"
	var witnessed: Array=p.get("convoyOpportunities",[])
	if not witnessed.is_empty():
		var first_c: Dictionary=witnessed[0]
		p["alternativesSummary"]="Witnessed trader %s carries %.0f %s (~%d coins value) at %.0f chart units: lawful bounty targets raiders, while intercepting a peaceful convoy triggers piracy law/standing penalties."%[str(first_c.get("name","Convoy")),float(first_c.get("tradeCargo",0)),str(first_c.get("tradeGood","cargo")),int(first_c.get("cargoValueCoins",0)),float(first_c.get("distance",0))]
	var j: Dictionary=_job(p,v,Jobs.KIND_BOUNTY)
	if j.is_empty():return
	var target: Dictionary=v.NavalAI._find_patrol(v.state,str(j.ownerId))
	var distance: float=_length(v,v.state.position,target) if not target.is_empty() else -1.0
	if distance<0:p.blockers.append("The named raider has no currently quoted safe approach.")
	p.operatingCosts=_budget(v,maxf(0,distance),0,1)
	p.operatingCosts["boardingAdvanceCoins"]=2*Goods.SAILOR_WAGE*10
	p.operatingCosts["rewardLessAllowanceCoins"]=int(j.reward)-int(p.operatingCosts.allowanceCoins)
	if not v.active_fleet().any(func(b):return not b.get("supportOnly",false) and float(b.get("ammo",0))>0):p.blockers.append("Prepare an armed combat boat before taking a bounty.")

static func _fisher(p: Dictionary,v) -> void:
	p.actionId="fishing";p.nextActionId="yard"
	p.firstGoal="Prepare a fishing hull, stop in safe open water, work for one elapsed day, then return to sell the actual catch."
	p.requirements=["An active civilian fishing hull, living assigned sailors, working fuel, crew food and its own free hold; recall other shore work and stop the route.","No dockside or instantaneous catch. Each 500-unit water cell provides at most 40 lots per calendar day, shared by all fishing boats."]
	p.rewardSource="Wild fish are explicit finite daily resource production. Sale coins come only from a harbor business with enough cash; unsold catch remains cargo."
	p.nextStep="Compare the yard's local hull price and crew advance with your purse; allow for stores and payroll. A catch earns coins only when a harbor business buys it."
	var b: Dictionary=_entry(p,v,["fishing"])
	p["fishingBasis"]={"catchPerCrewDay":Fishing.catch_rate(),"siteDayQuota":Fishing.SITE_QUOTA,"minimumWorkDays":0,"maximumWorkDays":7}
	if b.is_empty():
		p.operatingCosts.summary+=" Fishing labor allows at most %.2f lots per sailor-day before the shared %.0f-lot water-cell quota, fuel, food and physical hold limits; choose a real boat to quote its catch."%[Fishing.catch_rate(),Fishing.SITE_QUOTA]
		var reinv_empty: Dictionary=Choices.reinvestment086(v,"fishing","",0)
		p["reinvestment"]=reinv_empty
		p["reinvestmentSummary"]=str(reinv_empty.get("summary",""))
		return
	p.nextActionId="market"
	p.nextStep="Review this boat's current-ground quote in Fishing and clear its blockers before setting gear; return to Market with the earned catch and check the buyer's cash."
	var work: Dictionary=Fishing.fishing_quote(v,str(b.uid),1.0)
	var room: float=minf(float(work.holdFree),float(work.fleetHoldFree))
	var quota: float=float(work.quotaRemaining)
	var lots: float=maxf(0,minf(quota,minf(room,float(b.crew)*Fishing.catch_rate())))
	var harbor: Dictionary=v.current_port();var price: int=Economy.price(harbor,"preserved_fish","sell")
	p.operatingCosts=_budget(v,0,1)
	p["quote"]={"carrierUid":b.uid,"crew":b.crew,"workDays":1,"catchPerCrewDay":Fishing.catch_rate(),"catchCeiling":lots,"siteQuotaLeft":maxf(0,quota),"freeBoatHold":room,"fuelPerWorkDay":Fishing.fuel_rate(b),"sellUnitCoins":price,"saleCeilingCoins":mini(floori(lots),floori(float(harbor.get("cash",0))/maxi(1,price)))*price,"buyerCash":harbor.get("cash",0)}
	p.operatingCosts.summary+=" One working day can produce at most %.2f lots before fuel/food and calendar limits. Sailing to a chosen fishing ground is additional."%lots
	if harbor.is_empty():p.operatingCosts.summary+=" No local buyer quote at sea; unsold catch is cargo."
	else:p.operatingCosts.summary+=" Current local whole-lot sale ceiling %d coins, limited by the buyer's purse."%int(p.quote.saleCeilingCoins)
	if not work.ok:p.blockers.append(str(work.message))
	p.limits+=" Catch is an upper bound, not an earned sale. Offshore travel and the eventual buyer price are not selected yet."
	var rev: Dictionary=Choices.fishing_review(v,str(b.uid),1.0)
	p["buyerAlternatives"]=rev.get("buyerAlternatives",[])
	p["horizonAlternatives"]=rev.get("horizonAlternatives",[])
	p["reinvestment"]=rev.get("reinvestment",Choices.reinvestment086(v,"fishing",str(b.uid),int(rev.get("estimatedNet",0))))
	p["reinvestmentSummary"]=str(p.reinvestment.get("summary",""))
	p["alternativesSummary"]="Buyers ranked by net after return fuel/payroll (%d recorded home harbors); compare 0.5d / 1.0d / 2.0d horizons or shift 500+ units to a fresh 40-lot cell."%p.buyerAlternatives.size()

static func _passenger(p: Dictionary,v) -> void:
	p.firstGoal="Prepare a transport or yacht, accept a funded charter and carry its real people and bought food to the named destination."
	p.requirements=["One actual transport or yacht must have enough spare berths after crew, captives and existing passengers, plus hold space for the cohort's food.","The origin needs real civilians, provisions and sponsor coins; the destination needs reception room. Sailing distance, food and actual arrival gate settlement."]
	p.rewardSource="The harbor treasury escrows the charter fee and buys provisions. Passenger household/expert savings remain their property and are not captain revenue."
	p.nextStep="Compare the yard's hull price and minimum crew advance with your purse; stores and continuing payroll are extra. Check funded charters after crewing."
	p.nextActionId="yard"
	var b: Dictionary=_entry(p,v,["transport","yacht"])
	if b.is_empty():
		var reinv_empty: Dictionary=Choices.reinvestment086(v,"passenger_charter","",0)
		p["reinvestment"]=reinv_empty
		p["reinvestmentSummary"]=str(reinv_empty.get("summary",""))
		return
	p.nextActionId="jobs"
	p.nextStep="Review a funded charter on the work board for this carrier's spare berths, food space and return allowance; refresh if no eligible cohort is available."
	var offers: Array=Jobs.available(v)
	var j: Dictionary=_job(p,v,Jobs.KIND_CHARTER,offers)
	var charter_alts: Array=Choices.role_alternatives086(v,Jobs.KIND_CHARTER,offers,str(b.uid))
	p["alternatives"]=charter_alts
	var surplus: int=0
	if not j.is_empty():
		p.operatingCosts=_budget(v,float(j.routeDistance))
		for carrier in v.active_fleet():
			if str(carrier.uid)==str(j.carrierUid):b=carrier;break
		p.quote.merge({"carrierUid":j.carrierUid,"passengers":int(j.passengers.n),"berths":Transport.spare(v,b),"passengerFood":j.charterFood.food,"routeDays":j.routeDays,"passengerSavingsCoins":int(j.savingsHousehold)+int(j.savingsExpert)})
		surplus=int(j.reward)-int(p.operatingCosts.allowanceCoins)
		p.operatingCosts["rewardLessAllowanceCoins"]=surplus
	var reinv: Dictionary=Choices.reinvestment086(v,"passenger_charter",str(b.uid),surplus)
	p["reinvestment"]=reinv
	p["reinvestmentSummary"]=str(reinv.get("summary",""))
	if not charter_alts.is_empty():
		p["alternativesSummary"]="Charter board offers %d cohort/route choices (small <=4 passengers vs larger cohort up to spare berths and destination housing)."%charter_alts.size()

static func _display(value):
	if value is float or value is int:
		if not is_finite(float(value)):return null
		return clampf(float(value),-1000000000.0,1000000000.0) if absf(float(value))>1000000000.0 else value
	if value is Array:
		var rows: Array=[]
		for item in value:rows.append(_display(item))
		return rows
	if value is Dictionary:
		var record: Dictionary={}
		for key in value:record[key]=_display(value[key])
		return record
	return value
