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
const CoastMigration=preload("res://scripts/coast_migration.gd")
const SaveValidation = preload("res://scripts/save_validation.gd")
const Expedition=preload("res://scripts/expedition.gd")
const Manifest=preload("res://scripts/hold_manifest.gd")
const Exploration=preload("res://scripts/exploration.gd")
const Salvage=preload("res://scripts/salvage.gd")
const VoyageJobs=preload("res://scripts/voyage_jobs.gd")
const Contacts=preload("res://scripts/contacts.gd")
const NavalAI=preload("res://scripts/naval_ai.gd")
const NavalLifecycle=preload("res://scripts/naval_lifecycle.gd")
const Politics=preload("res://scripts/politics.gd")
const Factions=preload("res://scripts/factions.gd")
# v0.002 modules owned by the Combat and Refit helpers (public contract only; root copies them in).
const Deployment = preload("res://scripts/deployment.gd")
const Refits = preload("res://scripts/refit.gd")
# Ownership and traveling roster safety bounds are independent of battle deployment.
const MAX_FLEET = SaveValidation.MAX_ROSTER
const MAX_TRAVELING: int=48
const DAY_SECONDS = 45.0

var data: Dictionary
var state: Dictionary = {}
var nav: Dictionary = {}
var events: Array = []
var pending_days: int = 0
var exploration_timer: float=0.0

func _init(world_data: Dictionary):
	data = world_data
	for h in data.HULLS:
		h.price = Construction.quote(h).readyPrice
	nav = Navigation.create(data.ISLANDS,float(data.WORLD.width),float(data.WORLD.height),40.0*float(data.get("CAMPAIGN_SCALE",1.0)))

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
	fit_boat(initial,true)
	var cargo: Dictionary = {}
	for good in Economy.GOODS:
		cargo[good] = float(start.food) if good == "food" else 0.0
	state = {"mapRevision":int(data.get("MAP_REVISION",1)),"format":2,"version":Version.text(),"seed":seed_value,"nextUid":2,"coins":int(start.coins),"crewPurse":int(start.crew)*Goods.SAILOR_WAGE*10,"wageArrears":0,"debt":0,"day":1.0,"econDay":1,"renown":0,"morale":85.0,"ports":ports,"fleet":[initial],"cargo":cargo,"position":port_position(start.port),"heading":0.0,"path":[],"destination":"","lastPort":start.port,"flagship":initial.uid,"missionIndex":0,"activeContract":{},"freight":{},"doneSide":[],"wins":0,"losses":0,"kills":0,"completed":false,"patrols":[],"fleetOwners":[],"log":[],"moneyLog":[],"recoverable":{},"encounterGrace":90.0,"coinSupply":0}
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
		var initial_owner: Dictionary=fleet_owner("patrol-%d"%i)
		var route: Array=initial_owner.get("route",data.ROUTES[(i * 3 + 1) % data.ROUTES.size()])
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
	VoyageJobs.ensure(self)
	Contacts.ensure(state,data)
	Politics.ensure(self)
	NavalAI.ensure(state,data)
	state.cargoManifest={}
	state.surveyFoodCredit=0.0
	state.wreckHazards={}
	state.blueprints={}
	state.defeatedOwners={}
	Salvage.ensure(state)
	if int(data.get("MAP_REVISION",1))>=2:
		Exploration.ensure(state,data)
		Exploration.discover_near(state,state.position,1000.0)
	else:state.exploration={"version":1,"catalog":[],"sites":{},"assignment":{},"leads":[],"log":[]}
	Manifest.allocate(state)
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
		if not s.sunk and not s.get("mothballed", false) and not s.get("needsHarborRepair",false) and str(s.get("storedPort","")).is_empty() and s.crew >= s.crewMin:
			fleet.append(s)
	fleet.sort_custom(func(a, b): return a.uid == state.flagship and b.uid != state.flagship)
	return fleet

func capacity() -> float:
	return Expedition.capacity(state)

func cargo_weight() -> float:
	return Expedition.cargo_weight(state)

func expedition_report(route_distance: float=0.0) -> Dictionary:
	var result: Dictionary=Expedition.report(state,data,route_distance)
	var sailing: float=route_distance*2.0/maxf(0.01,travel_speed())/DAY_SECONDS
	result.tripDays=sailing+float(result.reserveDays)
	result.returnWages=ceili(result.tripDays*result.dailyWages)
	return result

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
	var powered_mass: float=0.0
	var tow_mass: float=0.0
	var tow_factor: float=1.0
	for s in state.fleet:
		if s.sunk or not str(s.get("storedPort","")).is_empty():continue
		if s.get("mothballed",false) or s.crew<s.crewMin or s.get("needsHarborRepair",false):tow_mass+=float(s.spec.size)
		else:powered_mass+=float(s.spec.size)
		if s.get("towed",false):tow_factor=minf(tow_factor,float(s.get("towSpeedFactor",1)))
	return speed*1.55*float(data.get("CAMPAIGN_SCALE",1.0))*powered_mass/maxf(1,powered_mass+tow_mass*0.8)*tow_factor

func chart_course(target: Dictionary, destination: String = "") -> Dictionary:
	if not state.get("exploration",{}).get("assignment",{}).is_empty():return fail("Recall your shore party before sailing away.")
	if active_fleet().is_empty():
		return fail("Crew a boat before setting sail.")
	if active_fleet().size()>MAX_TRAVELING:return fail("Store boats at a harbor: up to %d active boats may accompany one expedition."%MAX_TRAVELING)
	if cargo_weight()>capacity()+0.001:return fail("The traveling holds are overloaded. Offload cargo or activate a carrier before sailing.")
	Manifest.allocate(state)
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
	exploration_timer+=dt
	if exploration_timer>=0.5 and int(data.get("MAP_REVISION",1))>=2:
		exploration_timer=0.0
		for site in Exploration.discover_near(state,state.position,620.0):
			log_entry("Sighted %s. Open Island charts (I) to investigate."%site.name)
	advance_surveys(dt/DAY_SECONDS)
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
		if s.sunk or not str(s.get("storedPort","")).is_empty():
			continue
		Damage.tick_ship(s, dt, {"inCombat": false})
		if moving and not s.get("mothballed", false):
			s.fuel = maxf(0.0, s.fuel - dt * (0.011 + s.spec.size * 0.0002) * maxf(0.2,float(s.spec.get("fuelUse",1.0))))
		if s.sunk:
			log_entry("%s was lost to flooding." % s.name)
	for lost in Manifest.losses(state):log_entry("Lost %.1f %s aboard %s."%[lost.qty,lost.good,lost.boat])
	state.fleet = state.fleet.filter(func(s): return not s.sunk)
	if state.fleet.is_empty():
		events.append({"kind": "defeat"})
		return
	var old_day: int = int(state.day)
	state.day += dt / DAY_SECONDS
	if int(state.day) > old_day:
		pending_days += int(state.day) - old_day
	NavalLifecycle.step(self,dt)

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
			log_entry("Crew wages short by %d coins. Unpaid wages accumulate and morale falls."%(due-paid))
		elif state.wageArrears == 0:
			state.morale = minf(100.0,state.morale+1.0)
		var food_need: float = float(costs.food)
		var prepaid: float=minf(food_need,float(state.get("surveyFoodCredit",0)))
		state.surveyFoodCredit=maxf(0,float(state.get("surveyFoodCredit",0))-prepaid)
		food_need-=prepaid
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
		NavalLifecycle.daily(self)
		VoyageJobs.ensure(self)
		VoyageJobs._expire_overdue(self,state)
		state.econDay += 1
	apply_morale()
	Manifest.allocate(state)
	for patrol in state.patrols:
		var owner: Dictionary = fleet_owner(patrol.id)
		if not owner.is_empty():
			patrol.active = owner.active and owner.boats.any(func(b):return not b.sunk)
	if Money.total(state) != int(state.coinSupply):
		push_error("Coin conservation failed: %d != %d"%[Money.total(state),state.coinSupply])

func apply_morale():
	var factor: float = clampf(state.morale/85.0,0.35,1.0)
	for boat in state.fleet:
		# Morale scales the canonical fitted design, never a stale or serialized spec.
		var base: Dictionary = fitted_spec(boat)
		boat.economyFactor = factor
		boat.spec.speed = float(base.speed)*factor
		boat.spec.fireRate = float(base.fireRate)*factor
		var mounts = base.get("weaponMounts")
		var live = boat.spec.get("weaponMounts")
		if mounts is Array and live is Array and mounts.size() == live.size():
			for i in range(mounts.size()):
				if mounts[i] is Dictionary and live[i] is Dictionary and mounts[i].has("fireRate"):
					live[i].fireRate = float(mounts[i].fireRate)*factor

func pay_wage_arrears() -> Dictionary:
	var amount: int = mini(int(state.coins),int(state.wageArrears))
	if amount <= 0:
		return fail("No payable crew arrears, or your purse is empty.")
	Money.move(state,"coins",state,"crewPurse",amount,"Captain settles unpaid wages",state.moneyLog)
	state.wageArrears -= amount
	state.morale = minf(100.0,state.morale+10.0)
	apply_morale()
	return ok("Paid %d coins of owed wages into the sailors' purse."%amount)

func repay_loan(amount: int = 5000) -> Dictionary:
	var payment: int = mini(amount,mini(int(state.coins),int(state.debt)))
	if payment <= 0:
		return fail("No payable harbor loan.")
	Money.move(state,"coins",port(data.START.port),"governmentPurse",payment,"Repayment to harbor treasury",state.moneyLog)
	state.debt -= payment
	return ok("Repaid %d coins to Brass Haven."%payment)

func fleet_owner(id: String) -> Dictionary:
	for owner in state.get("fleetOwners",[]):
		if owner.id == id:
			return owner
	return {}

func wait_day():
	state.day += 1.0
	pending_days += 1
	state.encounterGrace = 60.0
	advance_surveys(1.0)

func begin_survey(site_id: String, action: String) -> Dictionary:
	var site: Dictionary=Exploration.catalog_site(state,site_id)
	if site.is_empty() or distance(state.position,site)>180:return fail("Approach within180water units of this landing first.")
	if not state.path.is_empty():return fail("Stop the fleet before landing your survey party.")
	var result: Dictionary=Exploration.begin(state,site_id,action)
	if not result.ok:return result
	state.surveyFoodCredit=float(state.get("surveyFoodCredit",0))+float(result.food)
	var left: int=int(result.crewNeeded)
	for b in active_fleet():
		var assigned: int=mini(left,maxi(0,int(b.crew)-ceili(b.wounded)-int(b.crewMin)))
		b.shoreCrew=assigned
		left-=assigned
	Manifest.allocate(state)
	log_entry("Landed %d sailors at %s; wages continue and assigned hands cannot man the boats."%[result.crewNeeded,result.siteName])
	return result

func recall_survey() -> Dictionary:
	if state.exploration.assignment.is_empty():return fail("No shore party is assigned.")
	state.exploration.assignment={}
	for b in state.fleet:b.shoreCrew=0
	state.cargo.food+=float(state.get("surveyFoodCredit",0))
	state.surveyFoodCredit=0.0
	Manifest.allocate(state)
	return ok("Party recalled; unused prepaid rations returned. Survey tools already used are spent.")

func advance_surveys(days: float) -> void:
	if int(data.get("MAP_REVISION",1))<2:return
	for event in Exploration.advance(state,days):
		for b in state.fleet:b.shoreCrew=0
		log_entry("%s: %s. %s"%[event.siteName,event.levelName,event.discovery])
		events.append(event)
		var lead: String=str(event.get("leadId",""))
		var next: Dictionary=Exploration.catalog_site(state,lead)
		if not next.is_empty():Exploration.discover_near(state,next,1.0)
		if int(event.level)>=3:
			var found: Dictionary=Exploration.catalog_site(state,event.siteId)
			if str(found.get("kind","")) in ["wreck_field","salvage_anchorage"]:Salvage.seed_site_wreck(self,found,"harbor_sloop")
			if str(found.get("kind",""))=="workshop_ruin":
				state.blueprints["manta_strike"]=true
				log_entry("Recovered Manta Strike workshop drawings. License them at a shipyard to unlock paid construction.")

func license_blueprint(id: String) -> Dictionary:
	var p: Dictionary=current_port()
	if p.is_empty() or p.industry!="shipyard" or not state.blueprints.get(id,false) or hull(id).is_empty():return fail("Take a recovered hull drawing to a shipyard.")
	if not id in p.shipIds:p.shipIds.append(id)
	return ok("Design licensed at %s. The yard still requires physical materials, workers, expert wages and coins."%p.name)

func recovery_days(weight: float) -> float:
	return maxf(0.1,weight/maxf(1,Exploration.spare_crew(state)*20.0))

func recover_wreck(id: String,mode: String,good: String="",qty: float=0.0) -> Dictionary:
	var w: Dictionary=Salvage.find_wreck(state,id)
	if w.is_empty() or distance(state.position,w)>180:return fail("Approach this wreck within180water units first.")
	var hazard: Dictionary=fleet_owner(str(state.wreckHazards.get(w.sourceId,"")))
	if not hazard.is_empty() and hazard.active and hazard.boats.any(func(b):return not b.sunk):return fail("Hostiles still control this wreck field. Secure the waters before recovery.")
	if not state.path.is_empty() or not state.exploration.assignment.is_empty():return fail("Stop the fleet and recall shore parties before recovery.")
	var q: Dictionary=Salvage.quote(self,id,mode)
	if mode=="strip" and Exploration.spare_crew(state)<1:return fail("Recovery needs at least one spare able sailor above the boat minimums.")
	var result: Dictionary=Salvage.strip_good(self,id,good,qty) if mode=="strip" and not good.is_empty() else Salvage.recover(self,id,mode)
	if not result.ok:return result
	var work_days: float=recovery_days(float(result.get("weight",q.get("weight",1)))) if mode=="strip" else maxf(1,float(q.get("ordinary",100))/200.0)
	var previous_day: int=int(state.day)
	state.day+=work_days
	pending_days+=int(state.day)-previous_day
	Manifest.allocate(state)
	log_entry(str(result.message)+" %.2f working days; normal wages/provisions apply."%work_days)
	return result

func jettison(good: String,qty: int) -> Dictionary:
	if not Goods.ITEMS.has(good) or qty<=0 or float(state.cargo.get(good,0))<qty:return fail("Choose a positive owned cargo lot.")
	Salvage.ensure(state)
	state.wreckSeq+=1
	state.cargo[good]-=qty
	state.wrecks.append({"id":"wreck-%d"%state.wreckSeq,"sourceId":"jettison:%d"%state.wreckSeq,"hull":"","name":"Marked cargo float","x":state.position.x,"y":state.position.y,"stores":{good:float(qty)},"components":{},"status":"unclaimed","day":state.day})
	Salvage.ensure(state)
	Manifest.allocate(state)
	return ok("Cargo set on a marked float. It can be recovered later if space is available.")

func trade(id: String, good: String, qty: int, side: String) -> Dictionary:
	var permission: Dictionary=Politics.permit(self,"buy_good" if side=="buy" else "trade",good)
	if not permission.ok:return permission
	var p = current_port()
	if p.is_empty() or p.id != id:
		return fail("Enter this harbor to trade.")
	var overflow: float=maxf(0,cargo_weight()-Economy.cargo_weight(state.cargo)-freight_weight())
	var result: Dictionary=Economy.transact(p,state,good,qty,side,maxf(0,capacity()-freight_weight()-overflow))
	Manifest.allocate(state)
	return result

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
	boat.storedPort=""
	fit_boat(boat,true)
	state.fleet.append(boat)
	return boat

## v0.002 fittings. The base hull is always rebuilt from world data; the loadout is the only
## fitting input. Never heals damage, refills stores, recruits or moves coins.
func fitted_spec(boat: Dictionary) -> Dictionary:
	var base: Dictionary = hull(str(boat.get("type",""))).duplicate(true)
	if base.is_empty():
		return boat.get("spec",{})
	var loadout = boat.get("loadout")
	if not loadout is Dictionary:
		loadout = Refits.defaults(base)
	return Refits.effective_spec(base,loadout)

func fit_boat(boat: Dictionary, fresh: bool = false) -> void:
	var base: Dictionary = hull(str(boat.get("type",""))).duplicate(true)
	if base.is_empty():
		return
	boat.baseSpec = base.duplicate(true)
	Refits.ensure(boat,base)
	boat.spec = Refits.effective_spec(base,boat.loadout)
	var max_hp: float = maxf(1.0,float(boat.spec.get("hp",base.hp)))
	if fresh:
		boat.hp = max_hp # a newly built hull is delivered to its fitted design
	boat.maxHp = max_hp
	boat.hp = clampf(float(boat.hp),0.0,max_hp) # existing damage is never healed
	boat.armor = maxf(0.0,float(boat.spec.get("armor",base.get("armor",0.0))))

## v0.002 deployment-point ownership limit (replaces the eight-boat cap).
func hull_points(h: Dictionary) -> int:
	var base: Dictionary = hull(str(h.get("id",""))).duplicate(true)
	if base.is_empty():
		return Deployment.cost(h)
	return Deployment.cost(Refits.effective_spec(base,Refits.defaults(base)))

func fleet_points() -> int:
	return Deployment.total(state.get("fleet",[]).filter(func(s): return not s.get("sunk",false)))

func fleet_limit() -> int:
	return Deployment.LIMIT

func can_add_boat(spec: Dictionary) -> bool:
	if state.is_empty() or hull(str(spec.get("id",""))).is_empty():
		return false
	if state.fleet.size() >= MAX_FLEET:
		return false
	return true

func points_refusal(spec: Dictionary) -> String:
	return "The fleet register holds at most %d owned hulls. Sell a hull or collect an existing stored boat; battle deployment remains 300 points per side."%MAX_FLEET

func set_boat_active(uid: String, enabled: bool) -> Dictionary:
	var b: Dictionary=find_boat(uid)
	if b.is_empty() or not str(b.get("storedPort","")).is_empty():return fail("Collect this boat from its harbor first.")
	if int(b.get("shoreCrew",0))>0:return fail("Recall the shore party before changing this boat's status.")
	if enabled and b.crew<b.crewMin:return fail("Hire the minimum crew before activation.")
	if enabled and b.get("needsHarborRepair",false):return fail("This recovered hull needs paid harbor repairs before it can sail under its own power.")
	if not enabled and b.uid==state.flagship:return fail("Choose another active flagship first.")
	var before: bool=b.get("mothballed",false)
	b.mothballed=not enabled
	if cargo_weight()>capacity()+0.001:
		b.mothballed=before
		return fail("Offload cargo before standing down its carrier.")
	Manifest.allocate(state)
	return ok("Boat activated." if enabled else "Boat stood down; it contributes no expedition hold space.")

func toggle_storage(uid: String) -> Dictionary:
	var b: Dictionary=find_boat(uid)
	var p: Dictionary=current_port()
	if b.is_empty() or p.is_empty() or not state.path.is_empty():return fail("Dock at a harbor to store or collect a boat.")
	if int(b.get("shoreCrew",0))>0:return fail("Recall the shore party before storing its boat.")
	var stored: String=str(b.get("storedPort",""))
	if not stored.is_empty():
		if stored!=p.id:return fail("This boat is stored at %s."%port(stored).name)
		b.storedPort=""
		b.mothballed=b.crew<b.crewMin
		Manifest.allocate(state)
		return ok("Boat collected. Hire sailors and provision it before activation.")
	if uid==state.flagship:return fail("Choose another active flagship before storing this boat.")
	b.storedPort=p.id
	if cargo_weight()>capacity()+0.001:
		b.storedPort=""
		return fail("Offload cargo before storing its carrier.")
	var savings: int=floori(float(state.crewPurse)*float(b.crew)/maxi(1,crew_count()))
	Money.move(state,"crewPurse",p,"householdPurse",savings,"Stored boat sailors take savings ashore",state.moneyLog)
	p.workforce+=int(b.crew);p.recruits+=int(b.crew)
	b.crew=0.0;b.wounded=0.0;b.mothballed=true
	Economy.sync_workforce(p)
	Manifest.allocate(state)
	return ok("Hull stored at %s; sailors and their savings returned ashore. Stores and fittings stay with the hull."%p.name)

func refit_boat(uid: String, slot: String, module_id: String) -> Dictionary:
	var advanced: bool=module_id in ["heavy_cannon","salvo_rocket","heavy_torpedo","heavy_drive","fortress_plating","naval_plating"]
	var permission: Dictionary=Politics.permit(self,"military" if advanced else "service")
	if not permission.ok:return permission
	var boat: Dictionary = find_boat(uid)
	if boat.is_empty() or boat.get("sunk",false):
		return fail("That boat is not in your flotilla.")
	var dock: Dictionary = current_port()
	if dock.is_empty() or not state.path.is_empty():
		return fail("Refits need a harbor yard. Dock before refitting.")
	if not str(boat.get("storedPort","")).is_empty() and boat.storedPort!=dock.id:return fail("Visit the harbor storing this hull before refitting it.")
	var previous: Dictionary = state
	state = previous.duplicate(true)
	var result: Dictionary = Refits.install(state,current_port(),find_boat(uid),slot,module_id)
	if not result.get("ok",false):
		state = previous
		return fail(str(result.get("message","The yard refused this refit.")))
	fit_boat(find_boat(uid))
	apply_morale()
	if Money.total(state) != int(state.coinSupply):
		state = previous
		return fail("The fitting bill could not be reconciled; your original boat and purses are unchanged.")
	log_entry(str(result.get("message","Refit complete.")))
	return ok(str(result.get("message","Refit complete.")))

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
	Manifest.allocate(state)

func available_contracts() -> Array:
	return Contracts.available(self)

func accept_contract(id: String) -> Dictionary:
	var permission: Dictionary=Politics.permit(self,"contract")
	if not permission.ok:return permission
	return Contracts.accept(self,id)

func accept_voyage_job(id: String) -> Dictionary:
	var permission: Dictionary=Politics.permit(self,"contract")
	if not permission.ok:return permission
	var result: Dictionary=VoyageJobs.accept(self,id)
	if result.ok:Contacts.visit(state,current_port(),state.day)
	Manifest.allocate(state)
	return result

func settle_voyage_job(id: String,abandon: bool=false) -> Dictionary:
	var before: Dictionary=VoyageJobs._find(state,id).duplicate(true)
	var result: Dictionary=VoyageJobs.abandon(self,id) if abandon else VoyageJobs.finish(self,id)
	if result.ok:
		if not abandon:Politics.job_completed(self,before)
		for contact in Contacts.list_contacts(state):
			if contact.port==before.get("port",""):Contacts.record(state,contact.id,"job:"+id+(":abandoned" if abandon else ":paid"),-5 if abandon else 5)
	Manifest.allocate(state)
	return result

func contract_ready() -> bool:
	return not state.activeContract.is_empty() and not state.freight.get("lost",false) and distance(state.position,port(state.activeContract.targetPort)) < 90

func finish_contract() -> Dictionary:
	var before: Dictionary=state.activeContract.duplicate(true)
	var result: Dictionary=Contracts.finish(self)
	if result.ok:Politics.job_completed(self,before)
	return result

func abandon_contract() -> Dictionary:
	return Contracts.abandon(self)

func battle_settled(result: String, enemy_specs: Array, context: Dictionary,physical_battle: Dictionary={}) -> Dictionary:
	var physical_wrecks: Array=[]
	if not physical_battle.is_empty():
		var source: String="battle:%d:%d"%[state.seed,state.wins+state.losses]
		physical_wrecks=Salvage.record_battle(self,physical_battle,source)
		for ship in physical_battle.get("ships",[]):
			if ship.get("sunk",false):ship.wreckRecorded=true
		if result!="won":
			state.wreckHazards[source]=str(context.get("ownerId",""))
			while state.wreckHazards.size()>256:state.wreckHazards.erase(state.wreckHazards.keys()[0])
		for record in physical_wrecks:
			if not record.friendly:continue
			var live: Dictionary=Salvage.find_wreck(state,record.id)
			for good in state.get("cargoManifest",{}).get(record.uid,{}):
				if Goods.ITEMS.has(good):live.stores[good]=float(live.stores.get(good,0))+float(state.cargoManifest[record.uid][good])*0.5
	for lost in Manifest.losses(state):log_entry("Lost %.1f %s aboard %s."%[lost.qty,lost.good,lost.boat])
	state.fleet = state.fleet.filter(func(s):return not s.sunk)
	Manifest.allocate(state)
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
			Money.move(owner,"coins",state,"coins",loot,"Captured fleet operating coins",state.moneyLog)
			owner.active = owner.boats.any(func(b):return not b.sunk) if not physical_battle.is_empty() else false
			state.defeatedOwners[owner.id]=int(state.defeatedOwners.get(owner.id,0))+1
		state.renown += enemy_specs.size()*3
		if not enemy_specs.is_empty() and physical_battle.is_empty():
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
	Politics.settled(self,owner,result,context)
	use_reserves()
	apply_morale()
	log_entry("Engagement %s. %d boats remain."%[result,state.fleet.size()])
	return {"coins":loot,"salvage":salvage,"wrecks":physical_wrecks,"fleetLost":active_fleet().is_empty(),"completed":state.completed}

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
	if h.is_empty() or state.recoverable.get("hull","") != id or state.recoverable.get("claimed",true):
		return fail("No unclaimed wreck of that design.")
	if not can_add_boat(h):
		return fail(points_refusal(h))
	var q: Dictionary = salvage_quote(id)
	if state.coins < q.total:
		return fail("Recovery needs %d coins for tug labor, inspection and the company fee."%q.total)
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
	# Re-crew an owned living hull before buying another; never strand boats to fit a cap.
	var existing: Dictionary = state.fleet[0] if not state.fleet.is_empty() else {}
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
	log_entry("Brass Haven lent %d coins; the yard supplied a real hull, labor and stores."%borrowed)
	return ok("Rescue funded by a %d-coins harbor loan."%borrowed)

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
	if int(data.get("MAP_REVISION",1))>=2:
		var prepared: Dictionary=CoastMigration.prepare(saved,data,nav)
		if not prepared.ok: return fail(prepared.message)
		saved=prepared.state
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
	var incoming: Dictionary = saved.duplicate(true)
	new_game(int(saved.get("seed", 1)))
	for key in state.keys():
		if incoming.has(key):
			state[key] = incoming[key]
	state.coins = maxi(0, int(state.coins))
	state.day = maxf(1.0, float(state.day))
	state.missionIndex = clampi(int(state.missionIndex), 0, data.MISSIONS.size())
	for s in state.fleet:
		# Canonical base + validated loadout; serialized combat stats are not trusted.
		fit_boat(s)
		Damage.tick_ship(s, 0.0)
	for owner in state.fleetOwners:
		for b in owner.boats:
			canonical_npc_boat(b)
	for patrol in state.patrols:
		set_patrol_course(patrol,port(patrol.from),port(patrol.to))
		place_patrol(patrol)
	state.path = incoming.get("path",[]).duplicate(true)
	Manifest.allocate(state)
	pending_days = 0
	Exploration.ensure(state,data)
	Salvage.ensure(state)
	VoyageJobs.ensure(self)
	Contacts.ensure(state,data)
	Politics.ensure(self)
	NavalAI.ensure(state,data)
	if not state.recoverable.is_empty() and not state.recoverable.get("claimed",true):
		var legacy_site: Dictionary=state.position.duplicate(true)
		legacy_site.id="legacy-recovery"
		Salvage.seed_site_wreck(self,legacy_site,state.recoverable.hull,"legacy-recovery")
		state.recoverable.claimed=true
	apply_morale()
	if Money.total(state) != int(state.coinSupply):
		return fail("The saved coin ledger is inconsistent; use your backup.")
	return ok("Voyage restored.")

func canonical_npc_boat(boat: Dictionary) -> void:
	var base: Dictionary = hull(str(boat.get("type","")))
	if base.is_empty():
		return
	var factor: float = clampf(float(boat.get("economyFactor",1.0)),0.35,1.0)
	boat.spec = base.duplicate(true)
	boat.maxHp = maxf(1.0,float(base.hp))
	boat.hp = clampf(float(boat.hp),0.0,boat.maxHp)
	boat.armor = maxf(0.0,float(base.get("armor",0.0)))
	if boat.has("economyBaseSpeed"):
		boat.economyBaseSpeed = float(base.speed)
		boat.economyBaseFireRate = float(base.fireRate)
		boat.spec.speed = float(base.speed)*factor
		boat.spec.fireRate = float(base.fireRate)*factor

func ok(message: String) -> Dictionary:
	return {"ok": true, "message": message}

func fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}
