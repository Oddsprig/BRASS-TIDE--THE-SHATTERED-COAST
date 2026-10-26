extends SceneTree
## One Coastal Clash fixture. Uses the public lab entry, autopilot and Battle.update.
## Proves finite cargo, a physical exit, and live firing. No teleports and no campaign payout.
const Main=preload("res://scripts/main.gd")
const Lab=preload("res://scripts/fleet_lab.gd")
const Objectives=preload("res://scripts/battle_objectives.gd")
const Money=preload("res://scripts/money.gd")
const Capture=preload("res://tests/clash_capture041.gd")
var checks: int=0
var failures: int=0

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL coastal: ",message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game=Main.new()
	root.add_child(game)
	await process_frame
	game.audio.enabled=false
	game.music.enabled=false
	game.save_directory=ProjectSettings.globalize_path("res://../qa/coastal-clash-saves")
	var clash_button=game.ui.title_root.find_child("CoastalClash",true,false)
	check(clash_button!=null and str(clash_button.text)=="Coastal Clash","title offers Coastal Clash before any other menu")
	var config: Dictionary=Lab.preset(game.data,"coastal_clash")
	var cargo: Dictionary=config.carrierCargo
	var cargo_total: float=0.0
	for good in cargo:
		cargo_total+=float(cargo[good])
		check(float(cargo[good])>0.0 and float(cargo[good])<100.0,"preset cargo %s is a finite lot"%str(good))
	check(cargo.has("ammo") and cargo.has("timber") and cargo.has("fuel") and cargo_total<30.0,"packet cargo is the small authored manifest")
	check(str(config.objective)=="escort" and str(config.context)=="coastal_clash" and not config.has("duration"),"preset is a standalone escort skirmish")
	var built: Dictionary=Lab.create(game.data,config,41041)
	check(bool(built.get("ok",false)),"public setup accepted the skirmish (%s)"%str(built.get("error","")))
	if not bool(built.get("ok",false)):
		print("COASTAL CLASH: ",checks," checks, ",failures," failures")
		quit(1)
		return
	game.new_game()
	game.paused=true
	var original=game.core
	var saved: String=FileAccess.get_file_as_string(game.save_directory.path_join("voyage.json"))
	var snapshot: Dictionary=original.state.duplicate(true)
	var coins: int=Money.total(snapshot)
	game.start_coastal_clash()
	game.paused=true
	check(game.lab_active and game.quick_mode and game.mode=="battle","Coastal Clash enters an isolated battle")
	check(str(game.battle_context.get("kind",""))=="coastal_clash","battle context stays a skirmish")
	check(game.battle.get("autopilot",false) and str(game.battle.get("startError","")).is_empty(),"autopilot battle starts without a setup error")
	check(not game.battle.mission.has("duration"),"mission has no timed-win field")
	check(Objectives.is_convoy(game.battle) and game.battle.get("objectiveOnly",false),"victory is the convoy objective")
	check(game.battle.deployment.player<=300 and game.battle.deployment.enemy<=300,"both fleets stay inside 300 points")
	check(game.battle.deployment.player>0 and game.battle.ships.size()>=9 and game.battle.ships.size()<=16,"small mixed fleets deploy together")
	var carrier: Dictionary={}
	for ship in game.battle.ships:
		if str(ship.get("uid",""))==str(game.battle.convoy.uids[0]): carrier=ship
	check(not carrier.is_empty() and str(carrier.type)=="fourport_packet","the loaded boat is the Fourport Packet")
	check(str(game.battle.playerId)!=str(carrier.id),"flagship is an escort, not the packet")
	check(str(carrier.order)=="move" and is_equal_approx(float(carrier.orderTarget.x),float(game.battle.convoy.exit.x)),"packet is ordered to the authored exit")
	check(is_equal_approx(float(game.battle.convoy.exit.x),2180.0) and is_equal_approx(float(game.battle.convoy.exit.y),850.0),"exit is the physical eastern gate")
	check(bool(game.battle.convoy.get("exitValid",false)),"exit was accepted as water-safe")
	var aboard: Dictionary=game.battle.convoy.cargo.get(carrier.uid,{})
	check(aboard.has("ammo") and aboard.has("timber") and aboard.has("fuel"),"battle keeps the packet's finite cargo")
	for good in cargo:
		check(is_equal_approx(float(aboard.get(good,0.0)),float(cargo[good])),"cargo %s is unchanged from the preset"%str(good))
	var families: Dictionary={}
	var escorting: bool=false
	var ammo_before: Dictionary={}
	var nearest: float=99999.0
	for ship in game.battle.ships:
		ammo_before[str(ship.uid)]=float(ship.ammo)
		check(float(ship.ammo)>0.0 and float(ship.ammo)<=float(ship.spec.ammoCapacity)+0.01,"starting ammo is finite for "+str(ship.name))
		check(is_equal_approx(float(ship.fuel),120.0) and float(ship.fuel)<1000.0,"starting fuel is the finite laboratory load for "+str(ship.name))
		if str(ship.team)=="player" and str(ship.uid)!=str(carrier.uid) and str(ship.order)=="escort": escorting=true
		for mount in ship.spec.get("weaponMounts",[]):
			families[str(mount.get("kind",""))]=true
		if str(ship.team)=="enemy":
			nearest=minf(nearest,Vector2(ship.x,ship.y).distance_to(Vector2(carrier.x,carrier.y)))
	check(escorting,"a combat boat is escorting the packet")
	check(families.has("torpedo") and (families.has("gun") or families.has("cannon")),"guns and torpedoes are actually fitted")
	check(nearest<800.0,"raiders start close enough to fight (nearest %.0f)"%nearest)
	var guidance=game.ui.left_body.find_child("SkirmishGuidance",true,false)
	check(guidance!=null and str(guidance.text).contains("exit") and str(guidance.text).contains("WASD"),"battle HUD states the exit and the command keys")
	var capture=Capture.new()
	capture.sample(game,0.0)
	var start_x: float=float(carrier.x)
	var player_fire: int=0
	var enemy_fire: int=0
	var hit_damage: float=0.0
	var steps: int=15*30
	for step in range(steps):
		if game.battle.get("result")!=null:
			break
		game.Battle.update(game.battle,1.0/30.0,{})
		capture.sample(game,1.0/30.0)
		for ev in game.Battle.pop_events(game.battle):
			var kind: String=str(ev.get("type",ev.get("kind","")))
			if kind=="fire":
				if str(ev.get("sourceTeam",ev.get("team","")))=="player": player_fire+=1
				elif str(ev.get("sourceTeam",ev.get("team","")))=="enemy": enemy_fire+=1
			elif kind=="hit":
				hit_damage+=maxf(0.0,float(ev.get("damage",0.0)))
		if step+1>=8*30 and player_fire>0 and enemy_fire>0 and hit_damage>0.0:
			break
	check(game.battle.get("autopilot",false),"autopilot stayed on through the engagement")
	check(player_fire>0 and enemy_fire>0,"both fleets fired under autopilot (player %d, enemy %d)"%[player_fire,enemy_fire])
	check(hit_damage>0.0,"live hits dealt hull damage (%.1f)"%hit_damage)
	var ammo_spent: bool=false
	var fuel_spent: bool=false
	var fuel_ok: bool=true
	for ship in game.battle.ships:
		if float(ship.ammo)<float(ammo_before.get(str(ship.uid),ship.ammo))-0.5: ammo_spent=true
		if float(ship.ammo)<0.0 or float(ship.fuel)<0.0: fuel_ok=false
		if not is_equal_approx(float(ship.fuel),120.0): fuel_spent=true
	if carrier.get("battleEscaped",false):
		if float(carrier.ammo)<float(ammo_before.get(str(carrier.uid),carrier.ammo))-0.5: ammo_spent=true
		if not is_equal_approx(float(carrier.fuel),120.0): fuel_spent=true
		if float(carrier.fuel)<0.0: fuel_ok=false
	check(ammo_spent,"firing spent finite ammunition")
	check(fuel_spent and fuel_ok,"movement spent finite fuel and never drove it negative")
	check(float(carrier.x)>start_x+5.0 or bool(carrier.get("sunk",false)) or bool(carrier.get("battleEscaped",false)),"the packet steamed toward the exit or was physically stopped")
	var snap: Dictionary=Objectives.snapshot(game.battle)
	var carried: Dictionary=snap.carriers[0].cargoAboard if not snap.get("carriers",[]).is_empty() else {}
	for good in cargo:
		check(is_equal_approx(float(carried.get(good,0.0)),float(cargo[good])),"outcome still shows the same finite %s"%str(good))
	if str(game.battle.get("result",""))=="won":
		check(float(game.battle.time)>=12.0 and int(snap.get("escaped",0))==int(snap.get("total",0)),"a win is the packet physically clearing the exit")
	elif str(game.battle.get("result",""))=="lost":
		check(int(snap.get("escaped",0))<int(snap.get("total",0)) and int(snap.get("sunk",0))+int(snap.get("captured",0))+int(snap.get("stranded",0))>0,"a loss is a real packet fate, not a clock")
	elif str(game.battle.get("result",""))=="retreated":
		check(not bool(game.battle.get("objectiveSuccess",false)),"withdrawal is not an objective win")
	else:
		check(game.battle.get("result")==null and int(snap.get("afloat",0))>0,"unfinished passage is not awarded")
	check(int(game.core.state.get("coins",-1))==0,"the skirmish purse stays empty")
	check(game.career_core==original and game.career_core.state==snapshot and Money.total(game.career_core.state)==coins,"captain state and coins are untouched")
	check(FileAccess.get_file_as_string(game.save_directory.path_join("voyage.json"))==saved,"the voyage file is not rewritten")
	check(capture.save(OS.get_environment("GAME_TEST_ARTIFACTS")),"actual chronological battle art is captured with finite geometry")
	game.return_to_title()
	check(game.mode=="menu" and not game.lab_active and game.core==original,"leaving the skirmish restores the captain")
	check(game.ui.title_root.find_child("CoastalClash",true,false)!=null,"Coastal Clash remains on the title with the voyage buttons")
	game.queue_free()
	await process_frame
	print("COASTAL CLASH: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
