extends SceneTree
## A real eight-contract route: no money/stock/crew fixtures, no forced battle results.
## Programmatic captain input only; it never reads or sends desktop input.
const Campaign = preload("res://scripts/campaign.gd")
const Battle = preload("res://scripts/battle.gd")
const Economy = preload("res://scripts/economy.gd")
const Money = preload("res://scripts/money.gd")
const Refit = preload("res://scripts/refit.gd")
const Deployment = preload("res://scripts/deployment.gd")
var core
var checks: int = 0
var failures: int = 0
var maximum_fleet: int = 1
var autonomous: bool = false
var refits_done: int = 0

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL voyage: "+message)
	return ok

func _initialize():
	var started: int = Time.get_ticks_msec()
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	core = Campaign.new(world)
	core.new_game(901)
	for leg in range(8):
		var offer: Dictionary = core.available_contracts()[0]
		if not sail(offer.port): break
		prepare()
		expand()
		prepare()
		if not check(core.accept_contract(offer.id).ok,"sponsor can fund leg%d"%(leg+1)): break
		if not sail(offer.targetPort): break
		# Dock/refit at the destination before accepting tactical deployment, as the UI permits.
		prepare()
		if leg >= 5:
			# Spend late campaign earnings on ready hulls at the destination yard too.
			for purchase in range(3): expand()
			prepare()
		if not check(core.contract_ready(),"real water route reaches leg%d"%(leg+1)): break
		upgrade_refits()
		prepare()
		maximum_fleet = maxi(maximum_fleet,core.state.fleet.size())
		var owner: Dictionary = core.fleet_owner(offer.ownerId)
		var specs: Array = []
		for id in offer.enemyHulls: specs.append(core.hull(id))
		var battle: Dictionary = Battle.create({"fleet":core.active_fleet(),"enemyFleet":owner.boats,"seed":17+leg})
		for frame in range(18000):
			if battle.result != null: break
			Battle.update(battle,1.0/30.0,captain(battle))
		print("voyage leg%d: %s; %.1fs; %d boats; %d coins"%[leg+1,str(battle.result),battle.time,core.active_fleet().size(),core.state.coins])
		if not check(battle.result == "won","actual battle leg%d is winnable"%(leg+1)):
			for boat in battle.ships:
				print("  %s %s hp%.1f ammo%.1f crew%.1f water%.1f sunk%s"%[boat.team,boat.name,boat.hp,boat.ammo,boat.crew,boat.water,str(boat.sunk)])
			break
		core.battle_settled("won",specs,{"kind":"contract","ownerId":owner.id})
		check(Money.total(core.state) == core.state.coinSupply,"leg%d conserves all coins"%(leg+1))
		if core.state.fleet.size() < core.MAX_FLEET:
			core.salvage_boat(specs[0].id)
		maximum_fleet = maxi(maximum_fleet,core.state.fleet.size())
	check(core.state.completed and core.state.missionIndex == 8,"all eight actual contracts completed")
	check(maximum_fleet > 1,"one inherited boat grows into a flotilla")
	check(refits_done > 0,"earned coins buy real useful weapon upgrades")
	print("voyage: %d checks, %d failures, %dms; largest fleet%d"%[checks,failures,Time.get_ticks_msec()-started,maximum_fleet])
	quit(0 if failures == 0 else 1)

func daily():
	if core.pending_days <= 0: return
	var days: int = core.pending_days
	core.pending_days = 0
	var ports: Array = core.state.ports.duplicate(true)
	var blocked: Array = []
	if core.state.missionIndex < 4: blocked.append("cinder_quay")
	if core.state.missionIndex < 8: blocked.append("shatter_spire")
	var messages: Array = Economy.tick_ports(ports,days,{"interport_trade":false,"blockaded":blocked})
	core.apply_economy(ports,messages,days)

func sail(id: String) -> bool:
	if not check(core.chart_course(core.port_position(id),id).ok,"chart course to "+id): return false
	for frame in range(18000):
		if core.state.path.is_empty(): break
		core.step(1.0/30.0)
		daily()
		# Random contacts may be avoided in the game. This route check tests story fights.
		for event in core.pop_events():
			if event.kind == "encounter":
				core.state.encounterGrace = 90.0
				core.chart_course(core.port_position(id),id)
	return check(core.current_port().get("id","") == id,"arrive at "+id)

func prepare():
	var p: Dictionary = core.current_port()
	# Larger yards serve a fleet across paid working days, not unlimited instant labor.
	# These are the same Wait/Trade/Drydock actions available to the player.
	if core.state.missionIndex >= 4:
		for work_day in range(4):
			var pending: bool = false
			for boat in core.active_fleet():
				if boat.hp < boat.maxHp-0.01 or boat.water > 0.0 or boat.engine < 0.99 or not boat.breaches.is_empty():
					if not core.repair_boat(boat.uid).ok: pending = true
			if not pending: break
			var rations: int = maxi(0,ceili(core.crew_count()*0.08*3-core.state.cargo.food))
			if rations > 0: core.trade(core.current_port().id,"food",rations,"buy")
			if core.state.coins < core.crew_count()*200: break
			core.wait_day()
			daily()
			p = core.current_port()
	for boat in core.state.fleet:
		if boat.crew < boat.crewMin:
			var hired: Dictionary = core.recruit_crew(boat.uid,int(boat.crewMin-boat.crew))
			if not hired.ok: print("  hire ",boat.name,": ",hired.message)
		var repair: Dictionary = core.repair_boat(boat.uid)
		if not repair.ok: print("  repair ",boat.name,": ",repair.message)
		var supply: Dictionary = core.resupply_boat(boat.uid,"voyage")
		if not supply.ok: print("  supply ",boat.name,": ",supply.message)
		var extra: int = mini(int(boat.crewOptimal-boat.crew),int(p.recruits))
		if extra > 0 and core.state.coins > Economy.recruit_cost(p,extra)+core.crew_count()*100:
			core.recruit_crew(boat.uid,extra)
		print("  prepared %s crew%.0f hp%.0f ammo%.0f fuel%.1f DP%d mothball%s"%[boat.name,boat.crew,boat.hp,boat.ammo,boat.fuel,Deployment.cost(boat),str(boat.mothballed)])
	var needed: int = maxi(0,ceili(core.crew_count()*0.08*6.0-core.state.cargo.food))
	if needed > 0: core.trade(p.id,"food",needed,"buy")
	core.pay_wage_arrears()
	core.apply_morale()
	# Save the most capable vessel as the manually steered flagship.
	var best: float = -1.0
	for boat in core.active_fleet():
		var score: float = boat.spec.range*boat.spec.damage*boat.spec.fireRate
		if score > best:
			best = score
			core.state.flagship = boat.uid

func power(h: Dictionary) -> float:
	return h.hp*0.25+h.damage*h.fireRate*4.0+h.range*0.15

func expand():
	var p: Dictionary = core.current_port()
	var candidate: Dictionary = {}
	var best: float = -1.0
	var weakest: Dictionary = {}
	for boat in core.state.fleet:
		if weakest.is_empty() or power(boat.spec)<power(weakest.spec): weakest = boat
	for id in p.shipStock:
		if p.shipStock[id] <= 0: continue
		var h: Dictionary = core.hull(id)
		var bill: int = int(core.ship_quote(h,p).readyPrice)+Economy.recruit_cost(p,int(h.crewOptimal))+8000+core.crew_count()*300
		if core.state.coins < bill: continue
		if not core.can_add_boat(h) and power(h) < power(weakest.spec)*1.2: continue
		if power(h)>best:
			best = power(h)
			candidate = h
	if candidate.is_empty(): return
	while not core.can_add_boat(candidate) and core.state.fleet.size() > 1:
		weakest = {}
		for boat in core.state.fleet:
			if weakest.is_empty() or power(boat.spec)<power(weakest.spec): weakest=boat
		if not core.sell_boat(weakest.uid).ok: return
	var bought: Dictionary = core.buy_boat(candidate.id)
	if bought.ok: print("  earned-money expansion: ",candidate.name)

func upgrade_refits():
	var port: Dictionary = core.current_port()
	if port.is_empty(): return
	var modules: Dictionary = Refit.catalog().weapons
	# This captain pays for additional useful mounts from actual port stocks and workers.
	# No balance, coin, stock, crew or outcome is injected into this voyage.
	var uids: Array = core.state.fleet.map(func(boat):return boat.uid)
	for uid in uids:
		var boat: Dictionary = core.find_boat(uid)
		if boat.is_empty() or boat.sunk: continue
		for index in range(1,Refit.hardpoints(boat.baseSpec).size()):
			boat = core.find_boat(uid)
			if not str(boat.loadout.weapons[index]).is_empty(): continue
			var best_id: String = ""
			var best_score: float = 0.0
			for module_id in modules:
				var module: Dictionary = modules[module_id]
				var q: Dictionary = Refit.quote(port,boat,"weapon:%d"%index,str(module_id))
				if not q.get("ok",false) or int(q.cost)+core.crew_count()*300+4000 > core.state.coins: continue
				var points: int = core.fleet_points()-Deployment.cost(boat)+Deployment.cost(q.newSpec)
				if points > 300: continue
				var score: float = float(module.get("damage",0))*float(module.get("fireRate",0))*float(module.get("range",0))/400.0
				if score > best_score:
					best_score = score
					best_id = str(module_id)
			if not best_id.is_empty():
				var result: Dictionary = core.refit_boat(str(uid),"weapon:%d"%index,best_id)
				if result.ok:
					refits_done += 1
					print("  paid weapon refit: ",boat.name," / ",best_id)
				port = core.current_port()
		# Heavy opponents justify paid protection, not an assumed free armor upgrade.
		if core.state.missionIndex >= 5:
			boat = core.find_boat(uid)
			var armor_id: String = "fortress_plating" if float(boat.baseSpec.size) >= 27 else "naval_plating"
			var q: Dictionary = Refit.quote(port,boat,"armor",armor_id)
			if q.get("ok",false) and int(q.cost)+core.crew_count()*300+4000 < core.state.coins and core.fleet_points()-Deployment.cost(boat)+Deployment.cost(q.newSpec) <= 300:
				var result: Dictionary = core.refit_boat(str(uid),"armor",armor_id)
				if result.ok:
					refits_done += 1
					print("  paid armor refit: ",boat.name," / ",armor_id)
				port = core.current_port()

func captain(battle: Dictionary) -> Dictionary:
	if autonomous: return {}
	var boat: Dictionary = Battle.get_flagship(battle)
	if boat.is_empty(): return {}
	var target: Dictionary = {}
	var best: float = INF
	for enemy in battle.ships:
		if enemy.team != "enemy" or enemy.sunk: continue
		var d: float = Vector2(enemy.x-boat.x,enemy.y-boat.y).length()
		if d < best:
			best = d
			target = enemy
	if target.is_empty(): return {}
	var delta: Vector2 = Vector2(target.x-boat.x,target.y-boat.y)
	var turn: float = angle_difference(boat.angle,delta.angle())
	var shot_speed: float = 240.0 if boat.spec.weapon == "torpedo" else 850.0
	var lead: float = minf(1.7,delta.length()/shot_speed)
	return {"manual":true,"forward":delta.length()>boat.spec.range*0.75,"backward":delta.length()<boat.spec.range*0.4,"left":turn< -0.05,"right":turn>0.05,"fire":delta.length()<boat.spec.range,"aimX":target.x+target.vx*lead,"aimY":target.y+target.vy*lead}
