extends RefCounted
const Goods = preload("res://scripts/goods.gd")
const Economy = preload("res://scripts/economy.gd")
const Construction = preload("res://scripts/construction.gd")
const Money = preload("res://scripts/money.gd")

static func quote(core, h: Dictionary, at: Dictionary = {}) -> Dictionary:
	var p: Dictionary = core.current_port() if at.is_empty() else at
	var prices: Dictionary = {}
	if not p.is_empty():
		for good in Economy.GOODS:
			prices[good] = Economy.price(p, good)
	return Construction.quote(h, prices)

static func buy(core, id: String) -> Dictionary:
	var p: Dictionary = core.current_port()
	var h: Dictionary = core.hull(id)
	if p.is_empty() or h.is_empty() or p.shipStock.get(id, 0) <= 0:
		return core.fail("That hull is not in stock here.")
	if core.state.fleet.size() >= core.MAX_FLEET:
		return core.fail("Your eight-boat flotilla is full.")
	var q: Dictionary = quote(core, h, p)
	var price: int = int(q.readyPrice)
	var probe_wallet: Dictionary = {"coins":core.state.coins-price,"crewPurse":0,"cargo":{}}
	var hire: Dictionary = Economy.recruit(p.duplicate(true), probe_wallet, int(h.crewMin), int(h.crewMax))
	if not hire.ok:
		return core.fail("The hull and minimum crew advance exceed your purse or the available workforce.")
	var tax: int = mini(price, int(q.get("tax", 0))+int(q.get("readyStorageTax",0)))
	Money.move(core.state,"coins",p,"cash",price-tax,"Completed hull purchase",core.state.moneyLog)
	Money.move(core.state,"coins",p,"governmentPurse",tax,"Hull sales duty",core.state.moneyLog)
	p.shipStock[id] -= 1
	var recruited: Dictionary = Economy.recruit(p, core.state, int(h.crewMin), int(h.crewMax))
	var boat: Dictionary = core.add_boat(h, recruited.count)
	core.log_entry("Purchased %s. Crew advance is in the sailors' purse; buy working stores before sailing." % boat.name)
	return core.ok("%s joined your flotilla with %d sailors." % [boat.name,boat.crew])

static func commission(core, id: String) -> Dictionary:
	var p: Dictionary = core.current_port()
	var h: Dictionary = core.hull(id)
	if p.is_empty() or h.is_empty() or not id in p.get("shipIds", []):
		return core.fail("This yard does not build that design.")
	if p.buildQueue.size() >= 2:
		return core.fail("Both building slips are occupied.")
	var q: Dictionary = quote(core, h, p)
	if core.state.coins < q.commissionPrice or not core.can_materials(p,q.materials):
		return core.fail("The yard needs the quoted cash and physical materials before booking this hull.")
	var order: Dictionary = Construction.make_order(h,q,"player")
	var wages: int = int(order.escrow)
	var tax: int = int(q.get("tax",0))
	if wages+tax > q.commissionPrice:
		return core.fail("The yard quote could not be reconciled.")
	core.consume_materials(p,q.materials)
	core.state.coins -= int(q.commissionPrice)
	p.cash += int(q.commissionPrice)-wages-tax
	p.governmentPurse += tax
	p.buildQueue.append(order)
	core.state.moneyLog.push_front({"reason":"Commission: materials, wages in escrow, yard income and duty","cash":int(q.commissionPrice)})
	return core.ok("%s booked. Wages are held in escrow and paid as the workforce builds it." % h.name)

static func collect(core, index: int) -> Dictionary:
	var p: Dictionary = core.current_port()
	if p.is_empty() or index < 0 or index >= p.buildQueue.size():
		return core.fail("No hull is ready to collect.")
	var order: Dictionary = p.buildQueue[index]
	if order.get("owner", "player") != "player" or not order.get("ready",false) or int(order.get("escrow",0)) != 0 or core.state.fleet.size() >= core.MAX_FLEET:
		return core.fail("The hull is unfinished or your flotilla is full.")
	var boat: Dictionary = core.add_boat(core.hull(str(order.hull)),0)
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
					if order.get("owner","player") == "yard":
						p.shipStock[order.hull] = int(p.shipStock.get(order.hull,0))+1
						finished.append(order)
					else:
						core.log_entry("Your %s is ready at %s." % [core.hull(order.hull).name,p.name])
			for order in finished:
				if int(order.get("escrow",0)) == 0:
					p.buildQueue.erase(order)
			if p.buildQueue.size() >= 2:
				continue
			for id in p.get("shipIds",[]):
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
	var boat: Dictionary = core.find_boat(uid)
	var p: Dictionary = core.current_port()
	if boat.is_empty() or p.is_empty():
		return core.fail("Hire sailors at a harbor.")
	var result: Dictionary = Economy.recruit(p,core.state,count,int(boat.crewMax-boat.crew))
	if result.ok:
		boat.crew += result.count
		if boat.crew >= boat.crewMin:
			boat.mothballed = false
	return result

static func sell(core, uid: String) -> Dictionary:
	var boat: Dictionary = core.find_boat(uid)
	var p: Dictionary = core.current_port()
	if boat.is_empty() or p.is_empty() or core.state.fleet.size() <= 1:
		return core.fail("Keep one boat. Hull sales require a harbor.")
	if core.cargo_weight() > core.capacity()-boat.spec.cargo:
		return core.fail("Sell cargo before reducing your hold space.")
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
	p.stocks.fuel += boat.fuel
	p.stocks.supplies += boat.supplies
	p.stocks.ammo += boat.ammo/Goods.ROUNDS_PER_CASE
	p.shipStock[boat.type] = int(p.shipStock.get(boat.type,0))+1
	core.state.fleet.erase(boat)
	if core.state.flagship == uid:
		core.state.flagship = core.state.fleet[0].uid
	return core.ok("Sold %s for %d cash; sailors and their savings returned ashore." % [boat.name,value])

static func service_quote(core, boat: Dictionary, p: Dictionary) -> Dictionary:
	var damage: float = maxf(0.0,boat.maxHp-boat.hp)
	var area: float = core.Damage.sum_areas(boat)
	var material: float = damage*0.20+area*0.018+(1.0-boat.engine)*4.0
	var own: float = minf(boat.supplies,material)
	var purchase: float = maxf(0.0,material-own)
	var ordinary: int = ceili((damage*0.08+area*0.002+boat.water*0.0001)*Goods.WAGES.shipwright)
	var expert: int = ceili(((1.0-boat.engine)*12.0+boat.wounded+boat.fire*0.002)*Goods.WAGES.mechanic)
	var materials: int = ceili(purchase*Economy.price(p,"supplies"))
	var fee: int = ceili((ordinary+expert)*0.10)
	return {"cost":materials+ordinary+expert+fee,"material":material,"own":own,"purchase":purchase,"ordinary":ordinary,"expert":expert,"materials":materials,"fee":fee}

static func repair(core, uid: String) -> Dictionary:
	var boat: Dictionary = core.find_boat(uid)
	var p: Dictionary = core.current_port()
	if boat.is_empty() or p.is_empty():
		return core.fail("Enter harbor for paid drydock service.")
	var q: Dictionary = service_quote(core,boat,p)
	if core.state.coins < q.cost or p.stocks.supplies < q.purchase:
		return core.fail("Drydock needs the quoted cash and repair kits.")
	var ordinary_days: float = (maxf(0.0,boat.maxHp-boat.hp)*0.08+core.Damage.sum_areas(boat)*0.002+boat.water*0.0001)
	var expert_days: float = ((1.0-boat.engine)*12.0+boat.wounded+boat.fire*0.002)
	var free_workers: float = maxf(0.0,float(p.get("availableWorkers",0))-float(p.get("_yardWorkersUsed",0)))
	var free_specialists: float = maxf(0.0,float(p.get("availableSpecialists",p.get("specialistWorkers",0)))-float(p.get("_yardSpecialistsUsed",0)))
	if free_workers+0.000001 < ceili(ordinary_days+expert_days) or free_specialists+0.000001 < ceili(expert_days):
		return core.fail("The yard has no available workforce or specialist.")
	Money.move(core.state,"coins",p,"cash",q.materials+q.fee,"Repair materials and yard fee",core.state.moneyLog)
	Money.move(core.state,"coins",p,"householdPurse",q.ordinary,"Drydock shipwright wages",core.state.moneyLog)
	Money.move(core.state,"coins",p,"expertPurse",q.expert,"Mechanics and treatment specialists",core.state.moneyLog)
	p.workers += ceili(ordinary_days+expert_days)
	p.availableWorkers = maxi(0,int(p.availableWorkers)-ceili(ordinary_days+expert_days))
	p.availableSpecialists = maxi(0,int(p.get("availableSpecialists",p.get("specialistWorkers",0)))-ceili(expert_days))
	p.stocks.supplies -= q.purchase
	boat.supplies = maxf(0.0,boat.supplies-q.own)
	boat.hp = boat.maxHp
	boat.breaches = []
	boat.water = 0.0
	boat.engine = 1.0
	boat.fire = 0.0
	boat.wounded = 0.0
	return core.ok("%s repaired for %d cash, paid to suppliers, shipwrights and specialists." % [boat.name,q.cost])

static func resupply(core, uid: String, profile: String = "full") -> Dictionary:
	var boat: Dictionary = core.find_boat(uid)
	var p: Dictionary = core.current_port()
	if boat.is_empty() or p.is_empty():
		return core.fail("Enter harbor to buy working stores.")
	var spent: int = 0
	# A voyage load avoids tying up a new captain's cash in a full long-range fuel tank.
	# Ammunition is purchased first; each transaction still consumes actual local stock.
	var targets: Dictionary = {"fuel":3.0,"ammo":80.0,"supplies":6.0} if profile == "voyage" else {"fuel":60.0,"ammo":80.0,"supplies":20.0}
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
	return core.ok("%s: %d cash spent; %.0f rounds, %.1f fuel and %.1f repair kits aboard." % [boat.name,spent,boat.ammo,boat.fuel,boat.supplies]) if spent > 0 else core.fail("Stores full, stock low, or your purse is empty.")

static func use_reserves(core):
	for boat in core.state.fleet:
		if boat.sunk:
			continue
		for good in ["ammo","fuel","supplies"]:
			var conversion: float = Goods.ROUNDS_PER_CASE if good == "ammo" else 1.0
			var target: float = 80.0 if good == "ammo" else 60.0 if good == "fuel" else 20.0
			var amount: float = minf(core.state.cargo.get(good,0.0),maxf(0.0,(target-boat[good])/conversion))
			core.state.cargo[good] -= amount
			boat[good] += amount*conversion
