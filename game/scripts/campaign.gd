extends RefCounted

const Damage = preload("res://scripts/damage.gd")
const Economy = preload("res://scripts/economy.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Version = preload("res://scripts/version.gd")
const Goods = preload("res://scripts/goods.gd")
const Money = preload("res://scripts/money.gd")
const Harbor = preload("res://scripts/harbor.gd")
const Construction = preload("res://scripts/construction.gd")
const Fleets = preload("res://scripts/fleet_economy.gd")
const Contracts = preload("res://scripts/contracts.gd")
const SaveValidation = preload("res://scripts/save_validation.gd")
const MAX_FLEET = 8
const DAY_SECONDS = 45.0

var data: Dictionary
var state: Dictionary = {}
var nav: Dictionary = {}
var events: Array = []
var pending_days: int = 0

func _init(world_data: Dictionary):
	data = world_data
	for h in data.HULLS:
		h.price = Construction.quote(h).readyPrice
	nav = Navigation.create(data.ISLANDS)

func hull(id: String) -> Dictionary:
	for h in data.HULLS:
		if h.id == id:
			return h
	return {}

func port(id: String) -> Dictionary:
	for p in state.get("ports", []):
		if p.id == id:
			return p
	return {}

func faction(id: String) -> Dictionary:
	for f in data.FACTIONS:
		if f.id == id:
			return f
	return {}

func new_game(seed_value: int = 1):
	var start = data.START
	var ports: Array = []
	for definition in data.PORTS:
		var p = Economy.create_port(definition)
		p.shipStock = {}
		p.buildQueue = []
		p.industryProgress = 0.0
		for id in definition.get("shipIds", []):
			p.shipStock[id] = 1 if hull(id).tier <= 3 or definition.industry == "shipyard" else 0
		ports.append(p)
	var initial = Damage.create_ship(hull(start.hull), {"crew": start.crew, "ammo": start.ammo, "fuel": start.fuel, "supplies": start.supplies})
	initial.uid = "boat-1"
	initial.mothballed = false
	var cargo: Dictionary = {}
	for good in Economy.GOODS:
		cargo[good] = float(start.food) if good == "food" else 0.0
	state = {"format":2,"version":Version.text(),"seed":seed_value,"nextUid":2,"coins":int(start.coins),"crewPurse":int(start.crew)*Goods.SAILOR_WAGE*10,"wageArrears":0,"debt":0,"day":1.0,"econDay":1,"renown":0,"morale":85.0,"ports":ports,"fleet":[initial],"cargo":cargo,"position":port_position(start.port),"heading":0.0,"path":[],"destination":"","lastPort":start.port,"flagship":initial.uid,"missionIndex":0,"activeContract":{},"freight":{},"doneSide":[],"wins":0,"losses":0,"kills":0,"completed":false,"patrols":[],"fleetOwners":[],"log":[],"moneyLog":[],"recoverable":{},"encounterGrace":90.0,"coinSupply":0}
	var home: Dictionary = port(start.port)
	home.workforce = maxi(0,int(home.workforce)-int(start.crew))
	home.recruits = maxi(0,int(home.recruits)-int(start.crew))
	Economy.sync_workforce(home)
	state.fleetOwners = Fleets.create_owners(ports,data)
	for i in range(data.MISSIONS.size()):
		var mission: Dictionary = data.MISSIONS[i]
		var boats: Array = []
		for id in mission.enemyHulls:
			boats.append(Damage.create_ship(hull(id)))
		var base: Dictionary = port("shatter_spire")
		var owner: Dictionary = {"id":"story-%d"%i,"name":"Blockade detachment %d"%(i+1),"kind":"raider","homePort":base.id,"faction":"raiders","coins":0,"crewPurse":0,"wageArrears":0,"morale":85.0,"cargo":{},"tradeCargo":0,"boats":boats,"active":true,"route":[base.id,mission.targetPort],"progress":0.0,"atPort":base.id,"log":[]}
		var capital: int = 0
		for b in boats:
			capital += int(b.crew)*Goods.SAILOR_WAGE*45
			base.workforce = maxi(0,int(base.workforce)-int(b.crew))
			base.availableWorkers = maxi(0,int(base.availableWorkers)-int(b.crew))
		Money.move(base,"governmentPurse",owner,"coins",mini(capital,int(base.governmentPurse)),"Blockade operating purse",state.moneyLog)
		state.fleetOwners.append(owner)
	pending_days = 0
	for i in range(9):
		var route = data.ROUTES[(i * 3 + 1) % data.ROUTES.size()]
		var a = port(route[0])
		var b = port(route[1])
		var t = float(i % 5) / 5.0
		var patrol: Dictionary = {"id": "patrol-%d" % i, "name": "Reef raiders" if i % 3 == 0 else "Coastal convoy", "hostile": i % 3 == 0, "active": true, "from": a.id, "to": b.id, "x": a.x, "y": a.y, "progress": t, "strength": 1 + i % 3}
		set_patrol_course(patrol,a,b)
		place_patrol(patrol)
		state.patrols.append(patrol)
		var owner: Dictionary = fleet_owner("patrol-%d"%i)
		if not owner.is_empty():
			Fleets.dock(owner,port(owner.homePort))
			owner.atPort = ""
	state.coinSupply = Money.total(state)
	log_entry("You inherited a Tinwake skiff, five sailors, and a debt-free start. The coast is yours to explore.")
	events.clear()

func port_position(id: String) -> Dictionary:
	for p in data.PORTS:
		if p.id == id:
			return {"x": p.x, "y": p.y}
	return {"x": 495.0, "y": 1240.0}

func set_patrol_course(patrol: Dictionary, a: Dictionary, b: Dictionary):
	# Precompute once per voyage/load; never pathfind or simulate water per frame.
	patrol.course = Navigation.find_path(nav,a,b)
	patrol.courseLength = 0.0
	for i in range(1,patrol.course.size()):
		patrol.courseLength += distance(patrol.course[i-1],patrol.course[i])

func place_patrol(patrol: Dictionary):
	var left: float = patrol.progress*patrol.courseLength
	for i in range(1,patrol.course.size()):
		var a: Dictionary = patrol.course[i-1]
		var b: Dictionary = patrol.course[i]
		var length: float = distance(a,b)
		if left <= length or i == patrol.course.size()-1:
			var fraction: float = clampf(left/maxf(0.001,length),0.0,1.0)
			patrol.x = lerpf(a.x,b.x,fraction)
			patrol.y = lerpf(a.y,b.y,fraction)
			return
		left -= length

func active_fleet() -> Array:
	var fleet: Array = []
	for s in state.get("fleet", []):
		if not s.sunk and not s.get("mothballed", false) and s.crew >= s.crewMin:
			fleet.append(s)
	fleet.sort_custom(func(a, b): return a.uid == state.flagship and b.uid != state.flagship)
	return fleet

func capacity() -> float:
	var result = 0.0
	for s in state.get("fleet", []):
		if not s.sunk:
			result += s.spec.cargo
	return result

func cargo_weight() -> float:
	var weight = freight_weight()
	for key in Economy.GOODS:
		weight += state.get("cargo", {}).get(key, 0.0) * Economy.GOODS[key].weight
	return weight

func freight_weight() -> float:
	var freight = state.get("freight", {})
	if freight.is_empty():
		return 0.0
	return freight.qty * Economy.GOODS[freight.good].weight

func crew_count() -> int:
	var result = 0
	for s in state.get("fleet", []):
		if not s.sunk:
			result += int(s.crew)
	return result

func current_port() -> Dictionary:
	if state.is_empty():
		return {}
	for p in state.ports:
		if distance(state.position, p) < 65.0:
			return p
	return {}

func distance(a: Dictionary, b: Dictionary) -> float:
	return Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y))

func travel_speed() -> float:
	var fleet = active_fleet()
	if fleet.is_empty():
		return 0.0
	var speed = 170.0
	for s in fleet:
		speed = minf(speed, s.spec.speed * maxf(0.25, Damage.get_status(s).speedFactor) * (1.0 if s.fuel > 0 else 0.3))
	return speed * 1.55

func chart_course(target: Dictionary, destination: String = "") -> Dictionary:
	if active_fleet().is_empty():
		return fail("Crew a boat before setting sail.")
	var path = Navigation.find_path(nav, state.position, target)
	if path.is_empty():
		return fail("No safe water route. Choose a harbor or open water.")
	path.pop_front()
	state.path = path
	state.destination = destination
	return ok("Course set for %s." % (port(destination).get("name", "open water")))

func stop_sailing():
	state.path = []
	state.destination = ""

func step(dt: float):
	if state.is_empty():
		return
	state.encounterGrace = maxf(0.0, state.encounterGrace - dt)
	var moving: bool = not state.path.is_empty()
	if moving:
		var step_left = travel_speed() * dt
		while step_left > 0 and not state.path.is_empty():
			var target = state.path[0]
			var delta = Vector2(target.x - state.position.x, target.y - state.position.y)
			var d = delta.length()
			state.heading = delta.angle()
			if d <= step_left:
				state.position = {"x": target.x, "y": target.y}
				state.path.pop_front()
				step_left -= d
			else:
				var v = delta / d * step_left
				state.position.x += v.x
				state.position.y += v.y
				step_left = 0.0
		if state.path.is_empty() and not state.destination.is_empty():
			state.lastPort = state.destination
			events.append({"kind": "arrival", "port": state.destination})
			state.destination = ""
	for s in state.fleet:
		if s.sunk:
			continue
		Damage.tick_ship(s, dt, {"inCombat": false})
		if moving and not s.get("mothballed", false):
			s.fuel = maxf(0.0, s.fuel - dt * (0.011 + s.spec.size * 0.0002))
		if s.sunk:
			log_entry("%s was lost to flooding." % s.name)
	state.fleet = state.fleet.filter(func(s): return not s.sunk)
	if state.fleet.is_empty():
		events.append({"kind": "defeat"})
		return
	var old_day: int = int(state.day)
	state.day += dt / DAY_SECONDS
	if int(state.day) > old_day:
		pending_days += int(state.day) - old_day
	for p in state.patrols:
		if not p.active:
			continue
		var a = port(p.from)
		var b = port(p.to)
		var sailing_owner: Dictionary = fleet_owner(p.id)
		var performance: float = float(sailing_owner.get("performanceFactor",1.0))
		var has_fuel: bool = sailing_owner.get("boats",[]).any(func(boat):return not boat.sunk and boat.fuel > 0)
		p.progress += dt * 35.0 * performance * (1.0 if has_fuel else 0.2) / maxf(1.0, p.courseLength)
		if p.progress >= 1.0:
			p.progress = 0.0
			var owner: Dictionary = fleet_owner(p.id)
			if not owner.is_empty():
				Fleets.dock(owner,b)
			var previous = p.from
			p.from = p.to
			p.to = previous
			p.course.reverse()
			var swap = a
			a = b
			b = swap
		place_patrol(p)
		var owner: Dictionary = fleet_owner(p.id)
		if not owner.is_empty():
			owner.progress = p.progress
			owner.atPort = ""
		if moving and p.hostile and state.encounterGrace <= 0 and distance(state.position, p) < 75 and state.day > 2.0:
			state.encounterGrace = 60.0
			stop_sailing()
			events.append({"kind": "encounter", "patrol": p.id})

func apply_economy(ports: Array, messages: Array, days: int):
	state.ports = ports
	for message in messages.slice(0,3):
		log_entry(str(message))
	for i in range(days):
		var costs: Dictionary = Economy.daily_upkeep(state.fleet)
		var due: int = int(costs.wages)
		var paid: int = mini(int(state.coins),due)
		Money.move(state,"coins",state,"crewPurse",paid,"Captain pays sailors",state.moneyLog)
		state.wageArrears += due-paid
		if paid < due:
			state.morale = maxf(10.0,state.morale-8.0)
			log_entry("Crew wages short by %d cash. Unpaid wages accumulate and morale falls."%(due-paid))
		elif state.wageArrears == 0:
			state.morale = minf(100.0,state.morale+1.0)
		var food_need: float = float(costs.food)
		if state.cargo.food >= food_need:
			state.cargo.food -= food_need
		else:
			state.cargo.food = 0.0
			state.morale = maxf(10.0,state.morale-5.0)
			log_entry("Rations exhausted. Buy food at a harbor.")
		var dock: Dictionary = current_port()
		if not dock.is_empty():
			Money.move(state,"crewPurse",dock,"cash",mini(int(state.crewPurse),crew_count()*12),"Sailors spend ashore",state.moneyLog)
		for p in state.ports:
			Construction.begin_day(p)
		for message in Fleets.tick(state.fleetOwners,state.ports,1.0).slice(0,2):
			log_entry(str(message))
		Harbor.tick_yards(self,1)
		state.econDay += 1
	apply_morale()
	for patrol in state.patrols:
		var owner: Dictionary = fleet_owner(patrol.id)
		if not owner.is_empty():
			patrol.active = owner.active and owner.boats.any(func(b):return not b.sunk)
	if Money.total(state) != int(state.coinSupply):
		push_error("Coin conservation failed: %d != %d"%[Money.total(state),state.coinSupply])

func apply_morale():
	var factor: float = clampf(state.morale/85.0,0.35,1.0)
	for boat in state.fleet:
		var base: Dictionary = hull(boat.type)
		boat.economyFactor = factor
		boat.spec.speed = base.speed*factor
		boat.spec.fireRate = base.fireRate*factor

func pay_wage_arrears() -> Dictionary:
	var amount: int = mini(int(state.coins),int(state.wageArrears))
	if amount <= 0:
		return fail("No payable crew arrears, or your purse is empty.")
	Money.move(state,"coins",state,"crewPurse",amount,"Captain settles unpaid wages",state.moneyLog)
	state.wageArrears -= amount
	state.morale = minf(100.0,state.morale+10.0)
	apply_morale()
	return ok("Paid %d cash of owed wages into the sailors' purse."%amount)

func repay_loan(amount: int = 5000) -> Dictionary:
	var payment: int = mini(amount,mini(int(state.coins),int(state.debt)))
	if payment <= 0:
		return fail("No payable harbor loan.")
	Money.move(state,"coins",port(data.START.port),"governmentPurse",payment,"Repayment to harbor treasury",state.moneyLog)
	state.debt -= payment
	return ok("Repaid %d cash to Brass Haven."%payment)

func fleet_owner(id: String) -> Dictionary:
	for owner in state.get("fleetOwners",[]):
		if owner.id == id:
			return owner
	return {}

func wait_day():
	state.day += 1.0
	pending_days += 1
	state.encounterGrace = 60.0

func trade(id: String, good: String, qty: int, side: String) -> Dictionary:
	var p = current_port()
	if p.is_empty() or p.id != id:
		return fail("Enter this harbor to trade.")
	return Economy.transact(p, state, good, qty, side, maxf(0.0, capacity() - freight_weight()))

func ship_materials(h: Dictionary) -> Dictionary:
	return Construction.blueprint(h).materials

func ship_quote(h: Dictionary, at: Dictionary = {}) -> Dictionary:
	return Harbor.quote(self,h,at)

func can_materials(p: Dictionary, materials: Dictionary) -> bool:
	for key in materials:
		if p.stocks.get(key,0.0) < materials[key]:
			return false
	return true

func consume_materials(p: Dictionary, materials: Dictionary):
	for key in materials:
		p.stocks[key] -= materials[key]

func find_boat(uid: String) -> Dictionary:
	for boat in state.fleet:
		if boat.uid == uid:
			return boat
	return {}

func add_boat(h: Dictionary, crew: int = 0) -> Dictionary:
	var boat: Dictionary = Damage.create_ship(h,{"crew":crew,"fuel":0.0,"ammo":0.0,"supplies":0.0})
	boat.uid = "boat-%d"%state.nextUid
	state.nextUid += 1
	boat.mothballed = crew < boat.crewMin
	state.fleet.append(boat)
	return boat

func buy_boat(id: String) -> Dictionary:
	return Harbor.buy(self,id)

func commission(id: String) -> Dictionary:
	return Harbor.commission(self,id)

func collect_boat(index: int) -> Dictionary:
	return Harbor.collect(self,index)

func recruit_crew(uid: String, count: int) -> Dictionary:
	return Harbor.recruit(self,uid,count)

func sell_boat(uid: String) -> Dictionary:
	return Harbor.sell(self,uid)

func service_quote(boat: Dictionary, p: Dictionary) -> Dictionary:
	return Harbor.service_quote(self,boat,p)

func repair_boat(uid: String) -> Dictionary:
	return Harbor.repair(self,uid)

func resupply_boat(uid: String, profile: String = "full") -> Dictionary:
	return Harbor.resupply(self,uid,profile)

func use_reserves():
	Harbor.use_reserves(self)

func available_contracts() -> Array:
	return Contracts.available(self)

func accept_contract(id: String) -> Dictionary:
	return Contracts.accept(self,id)

func contract_ready() -> bool:
	return not state.activeContract.is_empty() and distance(state.position,port(state.activeContract.targetPort)) < 90

func finish_contract() -> Dictionary:
	return Contracts.finish(self)

func abandon_contract() -> Dictionary:
	return Contracts.abandon(self)

func battle_settled(result: String, enemy_specs: Array, context: Dictionary) -> Dictionary:
	state.fleet = state.fleet.filter(func(s):return not s.sunk)
	state.encounterGrace = 75.0
	stop_sailing()
	var loot: int = 0
	var salvage: Dictionary = {}
	var owner: Dictionary = fleet_owner(str(context.get("ownerId","")))
	if result == "won":
		state.wins += 1
		state.kills += enemy_specs.size()
		if not owner.is_empty():
			loot = floori(float(owner.coins)*0.30)
			Money.move(owner,"coins",state,"coins",loot,"Captured fleet operating cash",state.moneyLog)
			owner.active = false
		state.renown += enemy_specs.size()*3
		if not enemy_specs.is_empty():
			salvage = enemy_specs[0]
			state.recoverable = {"hull":salvage.id,"claimed":false}
		if context.get("kind","") == "contract" and not state.activeContract.is_empty():
			state.activeContract.cleared = true
			var completion: Dictionary = finish_contract()
			loot += completion.get("reward",0)
		elif context.get("kind","") == "patrol":
			for patrol in state.patrols:
				if patrol.id == context.get("id",""):
					patrol.active = false
	else:
		state.losses += 1
		state.morale = maxf(10.0,state.morale-6)
	use_reserves()
	apply_morale()
	log_entry("Engagement %s. %d boats remain."%[result,state.fleet.size()])
	return {"coins":loot,"salvage":salvage,"fleetLost":active_fleet().is_empty(),"completed":state.completed}

func salvage_quote(id: String) -> Dictionary:
	var h: Dictionary = hull(id)
	if h.is_empty():
		return {}
	var ordinary: int = ceili(h.size/14.0*3.0*Goods.SAILOR_WAGE)
	var expert: int = Goods.WAGES.engineer
	var fee: int = ceili((ordinary+expert)*0.10)
	return {"ordinary":ordinary,"expert":expert,"fee":fee,"total":ordinary+expert+fee}

func salvage_boat(id: String) -> Dictionary:
	var h: Dictionary = hull(id)
	if h.is_empty() or state.fleet.size() >= MAX_FLEET or state.recoverable.get("hull","") != id or state.recoverable.get("claimed",true):
		return fail("No unclaimed wreck of that design, or your flotilla is full.")
	var q: Dictionary = salvage_quote(id)
	if state.coins < q.total:
		return fail("Recovery needs %d cash for tug labor, inspection and the company fee."%q.total)
	var base: Dictionary = port(state.lastPort)
	Money.move(state,"coins",base,"householdPurse",q.ordinary,"Salvage tug crew wages",state.moneyLog)
	Money.move(state,"coins",base,"expertPurse",q.expert,"Salvage engineer inspection",state.moneyLog)
	Money.move(state,"coins",base,"cash",q.fee,"Salvage company fee",state.moneyLog)
	state.recoverable.claimed = true
	var boat: Dictionary = add_boat(h,0)
	boat.hp = boat.maxHp*0.35
	return ok("%s recovered. Hire a crew, repair it and buy stores."%boat.name)

func rescue() -> Dictionary:
	if not active_fleet().is_empty():
		return fail("You already have a usable boat.")
	var home: Dictionary = port(data.START.port)
	var candidate: Dictionary = {}
	var selected_quote: Dictionary = {}
	var existing: Dictionary = state.fleet[0] if state.fleet.size() >= MAX_FLEET else {}
	var hull_cost: int = 0
	if existing.is_empty():
		for id in home.shipIds:
			if home.shipStock.get(id,0) <= 0:
				continue
			var offer: Dictionary = hull(id)
			var q: Dictionary = ship_quote(offer,home)
			if candidate.is_empty() or q.readyPrice < selected_quote.readyPrice:
				candidate = offer
				selected_quote = q
		if candidate.is_empty():
			return fail("No replacement hull is ready at Brass Haven. Load your saved voyage or start a new campaign.")
		hull_cost = int(selected_quote.readyPrice)
	else:
		candidate = hull(existing.type)
	var wanted_crew: int = maxi(int(candidate.crewMin),mini(int(candidate.crewOptimal),int(data.START.crew)))
	var current_crew: int = int(existing.get("crew",0))
	var hires: int = maxi(0,wanted_crew-current_crew)
	if home.recruits < hires or home.workforce < hires:
		return fail("Brass Haven lacks sailors for another rescue. Load your saved voyage or start a new campaign.")
	var hiring: int = Economy.recruit_cost(home,hires) if hires > 0 else 0
	var repair: Dictionary = service_quote(existing,home) if not existing.is_empty() else {"cost":0,"purchase":0}
	if home.stocks.supplies < repair.purchase:
		return fail("The harbor lacks repair kits for this rescue.")
	var store_cost: int = 0
	for good in ["ammo","fuel","supplies"]:
		var target: float = 80.0 if good == "ammo" else 60.0 if good == "fuel" else 20.0
		var conversion: float = Goods.ROUNDS_PER_CASE if good == "ammo" else 1.0
		var have: float = float(existing.get(good,0.0))
		var amount: float = maxf(0.0,(target-have)/conversion)
		store_cost += ceili(minf(amount,float(home.stocks[good]))*Economy.price(home,good))
	var rations: int = ceili(maxf(0.0,8.0-state.cargo.food))
	var borrowed: int = hull_cost+hiring+int(repair.cost)+store_cost+rations*Economy.price(home,"food")+wanted_crew*Goods.SAILOR_WAGE*5
	if home.governmentPurse < borrowed:
		return fail("The harbor treasury cannot fund another rescue. Load a saved voyage or start a new campaign.")
	state.position = port_position(home.id)
	state.lastPort = home.id
	stop_sailing()
	Money.move(home,"governmentPurse",state,"coins",borrowed,"Harbor rescue loan",state.moneyLog)
	state.debt += borrowed
	var starter: Dictionary
	if existing.is_empty():
		var tax: int = int(selected_quote.get("tax",0))+int(selected_quote.get("readyStorageTax",0))
		Money.move(state,"coins",home,"cash",hull_cost-tax,"Real replacement hull from yard stock",state.moneyLog)
		Money.move(state,"coins",home,"governmentPurse",tax,"Replacement hull registry duty",state.moneyLog)
		home.shipStock[candidate.id] -= 1
		starter = add_boat(candidate,0)
	else:
		starter = existing
		starter.sunk = false
		var fixed: Dictionary = Harbor.repair(self,starter.uid)
		if not fixed.ok:
			# Return the unused loan rather than leave a failed rescue with invented resources.
			Money.move(state,"coins",home,"governmentPurse",borrowed,"Failed rescue loan returned",state.moneyLog)
			state.debt -= borrowed
			return fixed
	if hires > 0:
		var hired: Dictionary = Harbor.recruit(self,starter.uid,hires)
		if not hired.ok:
			return hired
	starter.mothballed = false
	state.flagship = starter.uid
	Harbor.resupply(self,starter.uid)
	if rations > 0:
		Economy.transact(home,state,"food",mini(rations,floori(home.stocks.food)),"buy",capacity())
	state.encounterGrace = 120.0
	apply_morale()
	log_entry("Brass Haven lent %d cash; the yard supplied a real hull, labor and stores."%borrowed)
	return ok("Rescue funded by a %d-cash harbor loan."%borrowed)

func log_entry(message: String):
	if state.is_empty():
		return
	state.log.push_front("Day %d · %s" % [int(state.day), message])
	if state.log.size() > 45:
		state.log.resize(45)

func pop_events() -> Array:
	var result = events.duplicate()
	events.clear()
	return result

func restore(saved: Dictionary) -> Dictionary:
	var validation: Dictionary = SaveValidation.validate(saved,data)
	if not validation.ok:
		return fail("Save refused: "+str(validation.message)+" Use your backup.")
	if saved.get("format", 0) != 2 or not saved.get("fleet", null) is Array or saved.fleet.size() > MAX_FLEET:
		return fail("This save is not a Brass Tide v0.001 campaign.")
	if not saved.get("position", null) is Dictionary or not saved.get("ports", null) is Array:
		return fail("The save has missing world data.")
	if saved.ports.size() != data.PORTS.size():
		return fail("The save has the wrong coast layout.")
	for s in saved.fleet:
		if not s is Dictionary or hull(str(s.get("type", ""))).is_empty():
			return fail("The save contains an unknown boat.")
	if Money.total(saved) != int(saved.get("coinSupply",-1)):
		return fail("The saved coin ledger is inconsistent; use your backup.")
	new_game(int(saved.get("seed", 1)))
	for key in state.keys():
		if saved.has(key):
			state[key] = saved[key]
	state.coins = maxi(0, int(state.coins))
	state.day = maxf(1.0, float(state.day))
	state.missionIndex = clampi(int(state.missionIndex), 0, data.MISSIONS.size())
	for s in state.fleet:
		s.spec = hull(s.type).duplicate(true)
		s.maxHp = s.spec.hp
		Damage.tick_ship(s, 0.0)
	for patrol in state.patrols:
		set_patrol_course(patrol,port(patrol.from),port(patrol.to))
		place_patrol(patrol)
	state.path = []
	pending_days = 0
	apply_morale()
	if Money.total(state) != int(state.coinSupply):
		return fail("The saved coin ledger is inconsistent; use your backup.")
	return ok("Voyage restored.")

func ok(message: String) -> Dictionary:
	return {"ok": true, "message": message}

func fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}
