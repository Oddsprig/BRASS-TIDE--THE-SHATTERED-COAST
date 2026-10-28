extends RefCounted
## Read-only career quotations. Normalizing domain reads receive a detached state;
## no accept, begin, settle, payroll, discovery, clock or market transaction runs.
const Jobs=preload("res://scripts/voyage_jobs.gd")
const Exploration=preload("res://scripts/exploration.gd")
const Expedition=preload("res://scripts/expedition.gd")
const Goods=preload("res://scripts/goods.gd")
const Economy=preload("res://scripts/economy.gd")
const Harbor=preload("res://scripts/harbor.gd")
const Transport=preload("res://scripts/passenger_transport.gd")
const Fishing=preload("res://scripts/civilian_work.gd")
const Escort=preload("res://scripts/escort_ops.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Factions=preload("res://scripts/factions.gd")
const Routes=preload("res://scripts/route_cache.gd")
const Navigation=preload("res://scripts/navigation.gd")
const Contracts=preload("res://scripts/contracts.gd")
const CAREERS=["explorer","merchant","escort","privateer","fisher","passenger"]

class QuoteView extends RefCounted:
	const DAY_SECONDS=45.0
	const Expedition=preload("res://scripts/expedition.gd")
	const NavalAI=preload("res://scripts/naval_ai.gd")
	const Factions=preload("res://scripts/factions.gd")
	const ToolingOps=preload("res://scripts/tooling_ops.gd")
	var state: Dictionary
	var data: Dictionary
	var nav: Dictionary
	var speed: float
	func _init(c):
		state=c.state.duplicate(true);data=c.data;nav=c.nav;speed=c.travel_speed()
	func active_fleet() -> Array:
		var boats: Array=Expedition.traveling(state)
		boats.sort_custom(func(a,b):return a.uid==state.flagship and b.uid!=state.flagship)
		return boats
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
	for b in v.active_fleet():burn+=Fishing.fuel_rate(b)
	# Fuel is a conservative tank allowance for the whole interval, including
	# contingency. Idle shore work does not itself consume this entire allowance.
	var food: float=Economy.daily_upkeep(v.state.get("fleet",[])).food*days
	var wages: int=ceili(float(e.dailyWages)*days)
	var fuel: float=burn*days
	var repair: int=0
	var repair_available: bool=not p.is_empty()
	var repair_reason: String="Current dock repair needs a harbor quote."
	if not p.is_empty():
		repair_reason="Current paid hull and installed-module service; future battle damage is unquoted."
		for b in v.active_fleet():
			var q: Dictionary=Harbor.service_quote(v,b,p)
			if q.get("ok",false):repair+=int(q.get("cost",0))
			else:repair_available=false;repair_reason=str(q.get("message","Equipment service quote unavailable."))
	var total: int=wages+ceili(food*prices.food)+ceili(fuel*prices.fuel)+ceili(kits*prices.supplies)+repair
	var summary: String="%.2f days including return and %.0f contingency days: %d coins payroll (%d/day), %.2f food / %d coins, %.2f fuel reserve / %d coins, %.1f work kits / %d coins; current dock repair %s. Stores already owned reduce purchases. Future damage and ammunition expenditure are extra."%[days,e.reserveDays,wages,int(e.dailyWages),food,ceili(food*prices.food),fuel,ceili(fuel*prices.fuel),kits,ceili(kits*prices.supplies),str(repair)+" coins" if repair_available else "unavailable"]
	if p.is_empty():summary+=" Material values use reference prices at sea; obtain a local harbor quote before buying."
	return {"days":days,"sailingDays":sailing,"workDays":work_days,"reserveDays":e.reserveDays,"dailyWages":e.dailyWages,"wageCoins":wages,
		"food":food,"foodCoins":ceili(food*prices.food),"fuelReserve":fuel,"fuelCoins":ceili(fuel*prices.fuel),"workKits":kits,"workKitCoins":ceili(kits*prices.supplies),
		"repairQuoteCoins":repair,"repairQuoteAvailable":repair_available,"repairNote":repair_reason,"repairKitUnitCoins":prices.supplies,"ammoCaseCoins":prices.ammo,"roundsPerCase":Goods.ROUNDS_PER_CASE,
		"allowanceCoins":total,"freeHold":e.freeCapacity,"capacity":e.usableCapacity,"prices":prices,"pricePort":p.get("id",""),"summary":summary}

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

static func _offer(v,kind: String) -> Dictionary:
	for j in Jobs.available(v):
		if str(j.kind)==kind:return j
	return {}

static func _job(plan: Dictionary,v,kind: String) -> Dictionary:
	var j: Dictionary=_offer(v,kind)
	if j.is_empty():
		plan.blockers.append("No funded %s offer here today; inspect the work board at a permitted harbor."%kind.replace("_"," "))
		return {}
	plan["quote"]={"id":j.id,"kind":kind,"title":j.title,"rewardCoins":j.reward,"sponsorPort":j.port,"payerKey":j.payerKey,"materialInvoice":j.get("materialInvoice",0),"deadlineDay":j.deadlineDay,"targetPort":j.targetPort}
	plan["firstGoal"]=str(j.title)+"; complete the physical work, then release the funded escrow."
	plan.rewardSource+=" Current offer: %d coins from %s; %d coins of separately funded materials, payable only on completion."%[int(j.reward),str(v.port(str(j.port)).get("name",j.port)),int(j.get("materialInvoice",0))]
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
	if float(e.affordableDays)<float(p.operatingCosts.days):p.blockers.append("Current purse does not cover this fleet's quoted payroll allowance.")
	if float(e.foodDays)<float(p.operatingCosts.days):p.blockers.append("Buy enough crew food for the quoted allowance.")
	if float(e.fuelDays)<float(p.operatingCosts.days):p.blockers.append("Load working fuel into each boat for the quoted allowance; loose drums are separate.")
	if int(p.operatingCosts.repairQuoteCoins)>0:p.blockers.append("Review the quoted paid hull and installed-module repairs before committing this fleet.")
	p.ready=p.blockers.is_empty()
	return _display(p)

static func _explorer(p: Dictionary,v) -> void:
	p.firstGoal="Accept one funded survey, sight its island, chart it, survey it and report to its sponsor."
	p.requirements=["Chart: two spare sailors above boat minimums; full survey: four. Paid crew keep their minimum aboard.","Carry the quoted food and 1 chart kit plus 2 survey kits. Sight the site and stop nearby before landing; work takes campaign time."]
	p.rewardSource="The named harbor treasury escrows the survey fee on acceptance. Site knowledge alone creates no coins, free resources or repeat survey reward."
	p.nextStep="Recruit enough qualified spare crew or prepare a survey launch, then check the island chart's actual stage quote."
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

static func _merchant(p: Dictionary,v) -> void:
	p.firstGoal="Carry a funded sealed freight lot between harbors before risking your own trading capital."
	p.requirements=["The lot must fit actual free hold space; the sponsor must own the goods and fund its invoice and escrow.","Buy and sell only with legal harbor access and a real buyer purse; record destination prices before planning a speculative trade."]
	p.rewardSource="Freight fees come from the sponsoring treasury's escrow; ordinary trading receipts come from the buying business's cash. A local buy/sell spread includes a loss."
	p.nextStep="Record another harbor's prices in Trade, compare the return costs, then consider a paid cargo lighter."
	p.nextActionId="trade"
	var harbor: Dictionary=v.current_port()
	p["marketQuote"]={"good":"preserved_fish","buyCoins":Economy.price(harbor,"preserved_fish"),"sellCoins":Economy.price(harbor,"preserved_fish","sell"),"buyerCash":harbor.get("cash",0),"stock":harbor.get("stocks",{}).get("preserved_fish",0)}
	var j: Dictionary=_job(p,v,Jobs.KIND_FREIGHT)
	if j.is_empty():return
	var distance: float=_length(v,v.state.position,v.port(str(j.targetPort)))
	if distance<0:p.blockers.append("No safe route for this fleet to the freight destination.")
	p.operatingCosts=_budget(v,maxf(0,distance))
	p.quote["freight"]=j.freight.duplicate(true)
	if float(j.freight.qty)*float(Goods.ITEMS[str(j.freight.good)].weight)>v.capacity()-v.cargo_weight():p.blockers.append("The sealed lot exceeds the current free hold.")
	p.operatingCosts["rewardLessAllowanceCoins"]=int(j.reward)-int(p.operatingCosts.allowanceCoins)

static func _escort(p: Dictionary,v) -> void:
	p.actionId="traffic";p.nextActionId="jobs"
	p.firstGoal="Hail a nearby loaded friendly convoy with an observed armed threat, then protect every carrier through the actual exit."
	p.requirements=["At least one crewed combat boat, working ammunition and stores; all convoy boats plus your escorts must fit the 300-point deployment.","The convoy must be peaceful to you, physically loaded, near enough to hail and threatened by a nearby hostile fleet."]
	p.rewardSource="Successful passage grants one service credit and +5 standing with the convoy's faction. This escort promises 0 coins and no enemy purse."
	p.nextStep="Use the service credit and standing for access; choose a separately funded freight or bounty if your next voyage needs cash."
	p["quote"]={"rewardCoins":0,"standing":5,"serviceCredit":1}
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
	p.nextStep="Inspect Law before combat and Boarding before capture; repair a secured prize before using it in the battle line."
	p.nextActionId="law"
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
	p.nextStep="Compare the local fishing design and paid crew advance in the yard; once equipped, use Fishing and sell through the actual Market."
	var b: Dictionary=_entry(p,v,["fishing"])
	p["fishingBasis"]={"catchPerCrewDay":Fishing.catch_rate(),"siteDayQuota":Fishing.SITE_QUOTA,"minimumWorkDays":0,"maximumWorkDays":7}
	if b.is_empty():
		p.operatingCosts.summary+=" Fishing labor allows at most %.2f lots per sailor-day before the shared %.0f-lot water-cell quota, fuel, food and physical hold limits; choose a real boat to quote its catch."%[Fishing.catch_rate(),Fishing.SITE_QUOTA]
		return
	p.nextActionId="market"
	var room: float=minf(Transport.available_hold(v,b),v.capacity()-v.cargo_weight())
	var cell: String=Fishing.site_id(v.state.position)
	var book: Dictionary=v.state.get("civilianWork",{})
	var quota: float=Fishing.SITE_QUOTA-float(book.get("sites",{}).get(cell,0)) if int(book.get("resourceDay",-1))==floori(float(v.state.day)) else Fishing.SITE_QUOTA
	var lots: float=maxf(0,minf(quota,minf(room,float(b.crew)*Fishing.catch_rate())))
	var harbor: Dictionary=v.current_port();var price: int=Economy.price(harbor,"preserved_fish","sell")
	p.operatingCosts=_budget(v,0,1)
	p["quote"]={"carrierUid":b.uid,"crew":b.crew,"workDays":1,"catchPerCrewDay":Fishing.catch_rate(),"catchCeiling":lots,"siteQuotaLeft":maxf(0,quota),"freeBoatHold":room,"fuelPerWorkDay":Fishing.fuel_rate(b),"sellUnitCoins":price,"saleCeilingCoins":mini(floori(lots),floori(float(harbor.get("cash",0))/maxi(1,price)))*price,"buyerCash":harbor.get("cash",0)}
	p.operatingCosts.summary+=" One working day can produce at most %.2f lots before fuel/food and calendar limits. Sailing to a chosen fishing ground is additional."%lots
	if harbor.is_empty():p.operatingCosts.summary+=" No local buyer quote at sea; unsold catch is cargo."
	else:p.operatingCosts.summary+=" Current local whole-lot sale ceiling %d coins, limited by the buyer's purse."%int(p.quote.saleCeilingCoins)
	if not harbor.is_empty():p.blockers.append("Leave the harbor and stop in safe open water before setting gear.")
	if not Navigation.is_water(v.nav,v.state.position.x,v.state.position.y,maxf(10,float(b.spec.size))):p.blockers.append("This hull needs safe open water before fishing.")
	if not v.state.get("path",[]).is_empty():p.blockers.append("Stop the sailing route before setting gear.")
	if not v.state.get("exploration",{}).get("assignment",{}).is_empty() or not v.state.get("toolingRecovery",{}).is_empty():p.blockers.append("Recall the existing work party before fishing.")
	if lots<=0:p.blockers.append("The fishing boat has no free hold or this cell's daily quota is exhausted.")
	p.limits+=" Catch is an upper bound, not an earned sale. Offshore travel and the eventual buyer price are not selected yet."

static func _passenger(p: Dictionary,v) -> void:
	p.firstGoal="Prepare a transport or yacht, accept a funded charter and carry its real people and bought food to the named destination."
	p.requirements=["One actual transport or yacht must have enough spare berths after crew, captives and existing passengers, plus hold space for the cohort's food.","The origin needs real civilians, provisions and sponsor coins; the destination needs reception room. Sailing distance, food and actual arrival gate settlement."]
	p.rewardSource="The harbor treasury escrows the charter fee and buys provisions. Passenger household/expert savings remain their property and are not captain revenue."
	p.nextStep="Compare a paid transport design in the yard; when crewed, inspect one charter's actual berth and provision quote on the work board."
	p.nextActionId="yard"
	var b: Dictionary=_entry(p,v,["transport","yacht"])
	if b.is_empty():return
	var j: Dictionary=_job(p,v,Jobs.KIND_CHARTER)
	if j.is_empty():return
	p.nextActionId="jobs"
	p.operatingCosts=_budget(v,float(j.routeDistance))
	for carrier in v.active_fleet():
		if str(carrier.uid)==str(j.carrierUid):b=carrier;break
	p.quote.merge({"carrierUid":j.carrierUid,"passengers":int(j.passengers.n),"berths":Transport.spare(v,b),"passengerFood":j.charterFood.food,"routeDays":j.routeDays,"passengerSavingsCoins":int(j.savingsHousehold)+int(j.savingsExpert)})
	p.operatingCosts["rewardLessAllowanceCoins"]=int(j.reward)-int(p.operatingCosts.allowanceCoins)

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
