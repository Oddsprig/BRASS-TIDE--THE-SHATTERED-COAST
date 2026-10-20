extends SceneTree
## A real eight-contract route: no money/stock/crew fixtures, no forced battle results.
## Programmatic captain input only; it never reads or sends desktop input.
const Campaign = preload("res://scripts/campaign.gd")
const Battle = preload("res://scripts/battle.gd")
const Economy = preload("res://scripts/economy.gd")
const Money = preload("res://scripts/money.gd")
var core
var checks: int = 0
var failures: int = 0
var maximum_fleet: int = 1

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
		if not check(core.contract_ready(),"real water route reaches leg%d"%(leg+1)): break
		maximum_fleet = maxi(maximum_fleet,core.state.fleet.size())
		var owner: Dictionary = core.fleet_owner(offer.ownerId)
		var specs: Array = []
		for id in offer.enemyHulls: specs.append(core.hull(id))
		var battle: Dictionary = Battle.create({"fleet":core.active_fleet(),"enemyFleet":owner.boats,"seed":17+leg})
		for frame in range(18000):
			if battle.result != null: break
			Battle.update(battle,1.0/30.0,captain(battle))
		print("voyage leg%d: %s; %.1fs; %d boats; %d cash"%[leg+1,str(battle.result),battle.time,core.active_fleet().size(),core.state.coins])
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
		print("  prepared %s crew%.0f hp%.0f ammo%.0f fuel%.1f mothball%s"%[boat.name,boat.crew,boat.hp,boat.ammo,boat.fuel,str(boat.mothballed)])
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
		if core.state.fleet.size() >= core.MAX_FLEET and power(h) < power(weakest.spec)*1.2: continue
		if power(h)>best:
			best = power(h)
			candidate = h
	if candidate.is_empty(): return
	if core.state.fleet.size() >= core.MAX_FLEET:
		if not core.sell_boat(weakest.uid).ok: return
	var bought: Dictionary = core.buy_boat(candidate.id)
	if bought.ok: print("  earned-money expansion: ",candidate.name)

func captain(battle: Dictionary) -> Dictionary:
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
	return {"forward":delta.length()>boat.spec.range*0.75,"backward":delta.length()<boat.spec.range*0.4,"left":turn< -0.05,"right":turn>0.05,"fire":delta.length()<boat.spec.range,"aimX":target.x+target.vx*lead,"aimY":target.y+target.vy*lead}
