extends SceneTree
const Main = preload("res://scripts/main.gd")
const Money = preload("res://scripts/money.gd")
const Finance = preload("res://scripts/finance_ui.gd")
var checks: int = 0
var failures: int = 0
var game

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("RUNTIME TEST: "+message)

func _initialize():
	call_deferred("run")

func run():
	var start: int = Time.get_ticks_msec()
	game = Main.new()
	root.add_child(game)
	await process_frame
	game.save_directory = ProjectSettings.globalize_path("res://../qa/runtime-saves")
	game.audio.enabled = false
	game.new_game()
	# A repeatable controller scenario, independent of the wall-clock new-game seed.
	game.core.state.seed = 12345
	game.paused = true
	check(game.mode == "campaign" and game.core.state.fleet.size() == 1,"new campaign with one boat")
	var total: int = Money.total(game.core.state)
	check(total == game.core.state.coinSupply,"initial circulating coin total")
	for patrol in game.core.state.patrols:
		var prior: float=patrol.progress
		check(patrol.courseLength >= game.core.distance(game.core.port(patrol.from),game.core.port(patrol.to)),"NPC course accounts for water detours")
		for sample in [0.0,0.25,0.5,0.75,0.99]:
			patrol.progress=sample
			game.core.place_patrol(patrol)
			check(game.core.Navigation.is_water(game.core.nav,patrol.x,patrol.y),"NPC course remains on water")
		patrol.progress=prior
		game.core.place_patrol(patrol)
	check(game.core.Economy.daily_upkeep(game.core.state.fleet).wages == 500,"five sailors cost500cash/day")
	for tab in ["Market","Boatyard","Crew & repairs","Economy","Contracts"]:
		game.ui.open_port(tab)
		await process_frame
		check(game.ui.modal_open and game.ui.modal_kind == "port","harbor tab "+tab)
	for good in game.core.Economy.GOODS:
		Finance.good_recipe(game.ui,good)
		check(game.ui.modal_kind == "recipe","cost trace "+good)
	for hull in game.data.HULLS:
		Finance.boat_quote(game.ui,hull.id)
		check(game.ui.modal_kind == "boat_quote","boat quote "+hull.id)
	Finance.fleet_accounts(game.ui)
	game.ui.open_cargo()
	game.ui.open_guide()
	game.ui.open_menu()
	game.ui.open_settings()
	game.ui.close_modal()
	var first: Dictionary = game.core.available_contracts()[0]
	game.core.wait_day()
	game.start_economy()
	check(game.economy_task >= 0,"economy task deliberately pending before contract acceptance")
	game.accept_contract(first.id)
	check(game.economy_task < 0 and game.core.state.activeContract.get("id","") == first.id,"acceptance publishes worker snapshot before funding escrow")
	check(Money.total(game.core.state) == total,"escrow conserves all coins")
	game.core.wait_day()
	game.start_economy()
	var action_ran: Array = [false]
	var action = game.ui.button(game.ui.root,"Background test action",func():
		action_ran[0] = game.economy_task < 0
		game.core.abandon_contract())
	action.pressed.emit()
	check(action_ran[0] and game.core.state.activeContract.is_empty(),"direct modal action synchronizes before refunding contract")
	check(Money.total(game.core.state) == total,"background publication and refund preserve every coin")
	action.queue_free()
	game.accept_contract(first.id)
	game.ui.close_modal()
	var target: Dictionary = game.core.port_position(first.targetPort)
	check(game.core.chart_course(target,first.targetPort).ok,"course to opening objective")
	for frame in range(1800):
		if game.core.state.path.is_empty():
			break
		game.core.step(1.0/30.0)
	check(game.core.contract_ready(),"actual opening water route reaches destination")
	var specs: Array = []
	for id in first.enemyHulls:
		specs.append(game.core.hull(id))
	game.begin_battle(specs,{"kind":"contract","ownerId":first.ownerId,"id":first.id,"name":"Lantern Narrows"})
	check(game.mode == "battle" and game.paused,"tactical deployment starts paused")
	var flagship: Dictionary = game.Battle.get_flagship(game.battle)
	for frame in range(7200):
		if game.battle.result != null:
			break
		flagship = game.Battle.get_flagship(game.battle)
		if flagship.is_empty():
			break
		var foes: Array = game.battle.ships.filter(func(b):return b.team == "enemy" and not b.sunk)
		if foes.is_empty():
			game.Battle.update(game.battle,1.0/60.0)
			continue
		var foe: Dictionary = foes[0]
		var delta: Vector2 = Vector2(foe.x-flagship.x,foe.y-flagship.y)
		var turn: float = angle_difference(flagship.angle,delta.angle())
		var lead: float = minf(1.7,delta.length()/850.0)
		game.Battle.update(game.battle,1.0/60.0,{"forward":delta.length()>flagship.spec.range*0.75,"backward":delta.length()<flagship.spec.range*0.4,"left":turn< -0.05,"right":turn>0.05,"fire":delta.length()<flagship.spec.range,"aimX":foe.x+foe.vx*lead,"aimY":foe.y+foe.vy*lead})
	check(game.battle.result == "won","real inherited-skiff opening fight is winnable")
	game.result_handled = true
	game.settle_battle()
	check(game.ui.modal_kind == "outcome","after-action screen")
	check(game.core.state.missionIndex == 1,"funded story advances")
	check(Money.total(game.core.state) == total,"battle loot and funded reward conserve cash")
	game.ui.close_modal()
	check(game.mode == "campaign","closing result returns to campaign")
	game.paused = true
	var coins: int = game.core.state.coins
	var ammo: float = game.core.state.fleet[0].ammo
	game.save_game(false)
	game.return_to_title()
	game.load_game()
	game.paused = true
	check(game.core.state.coins == coins and is_equal_approx(game.core.state.fleet[0].ammo,ammo),"portable save/load retains cash and spent ammunition")
	check(Money.total(game.core.state) == total,"save/load retains entire coin ledger")
	game.quick_battle()
	for boat in game.battle.ships:
		if boat.team == "enemy":
			boat.sunk = true
	game.Battle.update(game.battle,1.0/60.0)
	game.result_handled = true
	game.settle_battle()
	check(game.ui.modal_kind == "outcome","quick-battle report")
	game.quick_battle()
	check(game.mode == "battle" and not game.battle.is_empty(),"replay does not dismiss the new fight")
	game.return_to_title()
	check(game.core.state.coins == coins,"quick battle never spends campaign funds")
	game.queue_free()
	await process_frame
	print("runtime: %d checks, %d failures, %dms; background/headless only"%[checks,failures,Time.get_ticks_msec()-start])
	quit(0 if failures == 0 else 1)
