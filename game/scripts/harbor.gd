extends RefCounted
const Lifecycle = preload("res://scripts/equipment_lifecycle.gd")
const Politics=preload("res://scripts/politics.gd")
const Goods = preload("res://scripts/goods.gd")
const Economy = preload("res://scripts/economy.gd")
const Construction = preload("res://scripts/construction.gd")
const Money = preload("res://scripts/money.gd")
const EquipmentService = preload("res://scripts/equipment_service.gd")

## Add civilian drawings to existing faction yards without free hull stock or
## changing authored ports. Both the menu and paid construction use this list.
static func catalogue(core, p: Dictionary) -> Array:
	var ids: Array = p.get("shipIds", []).duplicate()
	if p.is_empty() or ids.is_empty():
		return ids
	for h in core.data.HULLS:
		if h.get("civilianRole", "") in ["fishing", "transport", "tanker", "yacht"] and h.get("faction", "") == p.get("faction", "") and not h.id in ids:
			ids.append(h.id)
	return ids

static func quote(core, h: Dictionary, at: Dictionary = {}) -> Dictionary:
	var p: Dictionary = core.current_port() if at.is_empty() else at
	var prices: Dictionary = {}
	if not p.is_empty():
		for good in Economy.GOODS:
			prices[good] = Economy.price(p, good)
	return Construction.quote(h, prices)

## Read-only sailing budget beside the hull invoice. Project the same default
## fit, minimum crew and paid voyage load that buy()/resupply() actually use.
## No birth, UID reservation, recruitment, route search or payment is published.
static func purchase_plan(core, h: Dictionary, at: Dictionary = {}, route_distance: float = 0.0) -> Dictionary:
	var p: Dictionary = core.current_port() if at.is_empty() else at
	if p.is_empty() or h.is_empty() or core.state.is_empty():return {}
	var invoice: Dictionary = quote(core,h,p)
	var advance: int = Economy.recruit_cost(p,int(h.crewMin))
	var entry: int = int(invoice.readyPrice)+advance
	var snapshot: Dictionary = core.state.duplicate()
	snapshot.fleet = core.state.fleet.duplicate(true)
	snapshot.coins = maxi(0,int(core.state.coins)-entry)
	var boat: Dictionary = core.Damage.create_ship(h,{"uid":"yard-preview","crew":int(h.crewMin),"fuel":0.0,"ammo":0.0,"supplies":0.0,"supportOnly":true})
	core.fit_boat(boat,true)
	core._initialize_published_boat(boat)
	# These stores are valued below, never granted to a live hull. Fuel is
	# present for the projected sailing speed rather than the empty-tank penalty.
	boat.fuel = 3.0;boat.supplies = 6.0
	boat.ammo = maxf(80.0,float(boat.spec.get("ammoCapacity",80*maxi(1,boat.spec.get("weaponMounts",[]).size()))))
	snapshot.fleet.append(boat)
	var distance: float = maxf(0,route_distance) if is_finite(route_distance) else 0.0
	var before_speed: float = core.travel_speed()
	var after_speed: float = core.Expedition._route_speed(snapshot,core.data,core.Expedition.traveling(snapshot))
	var before_days: float = distance/maxf(0.01,before_speed)/core.DAY_SECONDS
	var after_days: float = distance/maxf(0.01,after_speed)/core.DAY_SECONDS
	# Explicit plans use the existing whole-day payroll rule, including today's
	# partial day, even for a reserve-only preview at the yard.
	var before: Dictionary = core.Expedition.report(core.state,core.data,distance,before_speed,{"outwardDays":before_days,"returnDays":before_days})
	var after: Dictionary = core.Expedition.report(snapshot,core.data,distance,after_speed,{"outwardDays":after_days,"returnDays":after_days})
	var needs: Dictionary = {"food":ceili(float(after.foodShortfall)),"fuel":3.0+maxf(0,float(after.fuelShortfall)-float(after.looseFuel)),"supplies":6.0,"ammo":float(boat.ammo)/Goods.ROUNDS_PER_CASE}
	var stores: int = 0
	var stock_ok: bool = true
	for good in needs:
		stores += ceili(float(needs[good])*Economy.price(p,good)-0.000001)
		if float(p.stocks.get(good,0))+0.000001<float(needs[good]):stock_ok=false
	var repairs: int = 0
	var repair_available: bool = true
	for owned in core.Expedition.traveling(core.state):
		var service: Dictionary = service_quote(core,owned,p)
		if not service.get("ok",false):repair_available=false
		else:repairs += int(service.cost)
	var payroll: int = int(after.returnWages)+ceili(float(after.wageArrears))
	var reserve: int = payroll+stores+repairs
	var balance: int = int(core.state.coins)-entry
	var recruit_probe: Dictionary = Economy.recruit(p.duplicate(true),{"coins":advance,"crewPurse":0,"cargo":{}},int(h.crewMin),int(h.crewMax))
	return {"hullQuote":invoice,"minimumCrew":int(h.crewMin),"crewAdvance":advance,"purchaseCoins":entry,
		"cashAfterPurchase":balance,"payrollCoins":payroll,"storeCoins":stores,"repairCoins":repairs,"returnReserveCoins":reserve,
		"cashAfterReserve":balance-reserve,"shortfallCoins":maxi(0,reserve-balance),"storeNeeds":needs,
		"stockAvailable":stock_ok,"crewAvailable":bool(recruit_probe.ok),"repairQuoteAvailable":repair_available,
		"completedStock":int(p.get("shipStock",{}).get(h.id,0)),"routeIncluded":distance>0,"routeDistance":distance,
		"before":before,"after":after}

static func buy(core, id: String) -> Dictionary:
	var requested: Dictionary=core.hull(id)
	var permission: Dictionary=Politics.permit(core,"military" if int(requested.get("tier",1))>=5 else "service")
	if not permission.ok:return permission
	var p: Dictionary = core.current_port()
	var h: Dictionary = core.hull(id)
	if p.is_empty() or h.is_empty() or p.shipStock.get(id, 0) <= 0:
		return core.fail("That hull is not in stock here.")
	if not core.can_add_boat(h):
		return core.fail(core.points_refusal(h))
	var q: Dictionary = quote(core, h, p)
	var price: int = int(q.readyPrice)
	var probe_wallet: Dictionary = {"coins":core.state.coins-price,"crewPurse":0,"cargo":{}}
	var hire: Dictionary = Economy.recruit(p.duplicate(true), probe_wallet, int(h.crewMin), int(h.crewMax))
	if not hire.ok:
		return core.fail("The hull and minimum crew advance exceed your purse or the available workforce.")
	var birth_uid := "boat-%d" % int(core.state.nextUid)
	var staged: Dictionary = Lifecycle.stage_birth(core.state, core.data, h, birth_uid, {})
	if not staged.ok:
		return core.fail(str(staged.get("message", "Equipment birth was refused.")))
	if birth_uid != "boat-%d" % int(core.state.nextUid):
		return core.fail("The hull register changed before payment.")
	var tax: int = mini(price, int(q.get("tax", 0))+int(q.get("readyStorageTax",0)))
	Money.move(core.state,"coins",p,"cash",price-tax,"Completed hull purchase",core.state.moneyLog)
	Money.move(core.state,"coins",p,"governmentPurse",tax,"Hull sales duty",core.state.moneyLog)
	p.shipStock[id] -= 1
	var recruited: Dictionary = Economy.recruit(p, core.state, int(h.crewMin), int(h.crewMax))
	var boat: Dictionary = core.add_boat(h, int(recruited.get("count", 0)), staged)
	core.log_entry("Purchased %s. Crew advance is in the sailors' purse; buy working stores before sailing." % boat.name)
	return core.ok("%s joined your flotilla with %d sailors." % [boat.name,boat.crew])

static func commission(core, id: String) -> Dictionary:
	var requested: Dictionary=core.hull(id)
	var permission: Dictionary=Politics.permit(core,"military" if int(requested.get("tier",1))>=5 else "service")
	if not permission.ok:return permission
	var p: Dictionary = core.current_port()
	var h: Dictionary = core.hull(id)
	if p.is_empty() or h.is_empty() or not id in catalogue(core, p):
		return core.fail("This yard does not build that design.")
	if p.buildQueue.size() >= 2+core.YardDevelopment.bays(core.state,str(p.id)):
		return core.fail("The public and chartered building slips are occupied.")
	if not core.can_add_boat(h):
		return core.fail(core.points_refusal(h))
	var q: Dictionary = quote(core, h, p)
	if core.state.coins < q.commissionPrice or not core.can_materials(p,q.materials):
		return core.fail("The yard needs the quoted coins and physical materials before booking this hull.")
	var order: Dictionary = Construction.make_order(h,q,"player")
	var wages: int = int(order.escrow)
	var tax: int = int(q.get("tax",0))
	if wages+tax > q.commissionPrice:
		return core.fail("The yard quote could not be reconciled.")
	var journal_problem: String = EquipmentService.journal_error(core.state)
	if not journal_problem.is_empty():return core.fail(journal_problem)
	core.consume_materials(p,q.materials)
	core.state.coins -= int(q.commissionPrice)
	p.cash += int(q.commissionPrice)-wages-tax
	p.governmentPurse += tax
	p.buildQueue.append(order)
	core.state.moneyLog.push_front({"reason":"Commission: materials, wages in escrow, yard income and duty","cash":int(q.commissionPrice),"from":"coins","to":"yard construction"})
	if core.state.moneyLog.size()>60:core.state.moneyLog.resize(60)
	return core.ok("%s booked. Wages are held in escrow and paid as the workforce builds it." % h.name)

static func collect(core, index: int) -> Dictionary:
	var permission: Dictionary=Politics.permit(core,"service")
	if not permission.ok:return permission
	var p: Dictionary = core.current_port()
	if p.is_empty() or index < 0 or index >= p.buildQueue.size():
		return core.fail("No hull is ready to collect.")
	var order: Dictionary = p.buildQueue[index]
	if order.get("owner", "player") != "player" or not order.get("ready",false) or int(order.get("escrow",0)) != 0:
		return core.fail("The hull is unfinished.")
	var h: Dictionary = core.hull(str(order.hull))
	if not core.can_add_boat(h):
		# The finished hull stays safely on the slip until points are free.
		return core.fail(core.points_refusal(h))
	var birth_uid := "boat-%d" % int(core.state.nextUid)
	var staged: Dictionary = Lifecycle.stage_birth(core.state, core.data, h, birth_uid, {})
	if not staged.ok:
		return core.fail(str(staged.get("message", "Equipment birth was refused.")))
	if birth_uid != "boat-%d" % int(core.state.nextUid):
		return core.fail("The hull register changed before collection.")
	var boat: Dictionary = core.add_boat(h, 0, staged)
	p.buildQueue.remove_at(index)
	return core.ok("%s launched. Hire sailors and buy fuel, ammunition and repair kits." % boat.name)

static func tick_yards(core, days: int):
	for p in core.state.ports:
		for day in range(days):
			Construction.begin_day(p)
			var finished: Array = []
			for order in p.buildQueue:
				var was_ready: bool = bool(order.get("ready",false))
				Construction.advance(p,order,1.0)
				if not was_ready and order.get("ready",false):
					if order.get("owner","player") == "yard" and str(order.get("npcOwnerId","")).is_empty():
						p.shipStock[order.hull] = int(p.shipStock.get(order.hull,0))+1
						finished.append(order)
					elif order.get("owner","player")=="player":
						core.log_entry("Your %s is ready at %s." % [core.hull(order.hull).name,p.name])
			for order in finished:
				if int(order.get("escrow",0)) == 0:
					p.buildQueue.erase(order)
			if p.buildQueue.size() >= 2:
				continue
			for id in catalogue(core, p):
				if p.shipStock.get(id,0) > 0 or p.buildQueue.any(func(o): return o.hull == id):
					continue
				var h: Dictionary = core.hull(id)
				var q: Dictionary = quote(core,h,p)
				var order: Dictionary = Construction.make_order(h,q,"yard")
				if p.cash >= order.escrow and core.can_materials(p,q.materials):
					core.consume_materials(p,q.materials)
					p.cash -= int(order.escrow)
					p.buildQueue.append(order)
				break

static func recruit(core, uid: String, count: int) -> Dictionary:
	var permission: Dictionary=Politics.permit(core,"service")
	if not permission.ok:return permission
	var boat: Dictionary = core.find_boat(uid)
	var p: Dictionary = core.current_port()
	if boat.is_empty() or p.is_empty():
		return core.fail("Hire sailors at a harbor.")
	if not str(boat.get("storedPort","")).is_empty() and boat.storedPort!=p.id:return core.fail("Visit the harbor storing this hull before assigning crew.")
	var captive_count: int=int(core.state.get("captiveBerths",{}).get(uid,0))+core.CrisisOps.Transport.assigned(core.state,uid)
	var result: Dictionary = Economy.recruit(p,core.state,count,maxi(0,int(boat.crewMax-boat.crew)-captive_count))
	if result.ok:
		boat.crew += result.count
		if boat.crew >= boat.crewMin:
			boat.mothballed = false
		core.Manifest.allocate(core.state)
	return result

static func sell(core, uid: String) -> Dictionary:
	var permission: Dictionary=Politics.permit(core,"service")
	if not permission.ok:return permission
	var boat: Dictionary = core.find_boat(uid)
	var p: Dictionary = core.current_port()
	if boat.is_empty() or p.is_empty() or core.state.fleet.size() <= 1:
		return core.fail("Keep one boat. Hull sales require a harbor.")
	if int(boat.get("shoreCrew",0))>0:return core.fail("Recall its shore party before selling the hull.")
	if core.CrisisOps.Transport.assigned(core.state,uid)>0:return core.fail("Discharge passengers safely before selling their actual carrier.")
	if int(core.state.get("captiveBerths",{}).get(uid,0))>0:return core.fail("Release captives safely before selling their carrier.")
	if not str(boat.get("storedPort","")).is_empty() and boat.storedPort!=p.id:return core.fail("Visit the harbor storing this hull before selling it.")
	var lost_capacity: float=float(boat.spec.cargo) if core.active_fleet().has(boat) else 0.0
	if core.cargo_weight() > core.capacity()-lost_capacity:
		return core.fail("Sell cargo before reducing your hold space.")
	if not core.FleetSupport.aboard(core,uid).is_empty():return core.fail("Discharge specialists with their savings before selling this hull.")
	var q: Dictionary = quote(core,core.hull(boat.type),p)
	var value: int = floori(float(q.materialCost+q.laborCost+q.supervisionCost)*0.65*boat.hp/boat.maxHp)
	if p.cash < value:
		return core.fail("This yard cannot afford that hull today.")
	var total_crew: int = maxi(1,core.crew_count())
	var savings: int = floori(float(core.state.crewPurse)*float(boat.crew)/total_crew)
	Money.move(core.state,"crewPurse",p,"householdPurse",savings,"Discharged sailors take their savings ashore",core.state.moneyLog)
	Money.move(p,"cash",core.state,"coins",value,"Yard buys a used hull",core.state.moneyLog)
	p.recruits += int(boat.crew)
	p.workforce += int(boat.crew)
	core.TrainingOps.Training.return_qualified(p,int(boat.get("boarders",0)),"boarder")
	core.TrainingOps.Training.return_qualified(p,maxi(0,int(boat.crew)-int(boat.get("boarders",0))),"sailor")
	p.stocks.fuel += boat.fuel
	p.stocks.supplies += boat.supplies
	p.stocks.ammo += boat.ammo/Goods.ROUNDS_PER_CASE
	p.shipStock[boat.type] = int(p.shipStock.get(boat.type,0))+1
	core.state.fleet.erase(boat)
	if core.state.flagship == uid:
		core.state.flagship = core.state.fleet[0].uid
	return core.ok("Sold %s for %d coins; sailors and their savings returned ashore." % [boat.name,value])

static func service_quote(core, boat: Dictionary, p: Dictionary) -> Dictionary:
	return EquipmentService.service_quote(core, boat, p)

static func repair(core, uid: String) -> Dictionary:
	return EquipmentService.repair(core, uid)

static func resupply(core, uid: String, profile: String = "full") -> Dictionary:
	var permission: Dictionary=Politics.permit(core,"service")
	if not permission.ok:return permission
	var boat: Dictionary = core.find_boat(uid)
	var p: Dictionary = core.current_port()
	if boat.is_empty() or p.is_empty():
		return core.fail("Enter harbor to buy working stores.")
	if not str(boat.get("storedPort","")).is_empty() and boat.storedPort!=p.id:return core.fail("This hull is stored at another harbor.")
	var spent: int = 0
	# A voyage load avoids tying up a new captain's cash in a full long-range fuel tank.
	# Ammunition is purchased first; each transaction still consumes actual local stock.
	var magazine: float = maxf(80.0,float(boat.spec.get("ammoCapacity",80*maxi(1,boat.spec.get("weaponMounts",[]).size()))))
	var targets: Dictionary = {"fuel":3.0,"ammo":magazine,"supplies":6.0} if profile == "voyage" else {"fuel":float(boat.spec.get("fuelCapacity",60)),"ammo":magazine,"supplies":20.0}
	for good in ["ammo","supplies","fuel"]:
		var conversion: float = Goods.ROUNDS_PER_CASE if good == "ammo" else 1.0
		var target: float = targets[good]
		var need: float = maxf(0.0,(target-boat[good])/conversion)
		var unit: int = Economy.price(p,good)
		var amount: float = minf(need,minf(float(p.stocks[good]),float(core.state.coins)/maxi(1,unit)))
		if amount <= 0:
			continue
		var cost: int = ceili(amount*unit-0.000001)
		Money.move(core.state,"coins",p,"cash",cost,"Working stores: "+good,core.state.moneyLog)
		p.stocks[good] -= amount
		boat[good] += amount*conversion
		spent += cost
	return core.ok("%s: %d coins spent; %.0f rounds, %.1f fuel and %.1f repair kits aboard." % [boat.name,spent,boat.ammo,boat.fuel,boat.supplies]) if spent > 0 else core.fail("Stores full, stock low, or your purse is empty.")

static func use_reserves(core):
	for boat in core.state.fleet:
		if boat.sunk or not str(boat.get("storedPort","")).is_empty():
			continue
		for good in ["ammo","fuel","supplies"]:
			var conversion: float = Goods.ROUNDS_PER_CASE if good == "ammo" else 1.0
			var target: float = maxf(80.0,float(boat.spec.get("ammoCapacity",80*maxi(1,boat.spec.get("weaponMounts",[]).size())))) if good == "ammo" else float(boat.spec.get("fuelCapacity",60)) if good == "fuel" else 20.0
			var amount: float = minf(core.state.cargo.get(good,0.0),maxf(0.0,(target-boat[good])/conversion))
			core.state.cargo[good] -= amount
			boat[good] += amount*conversion
