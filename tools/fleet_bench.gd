extends SceneTree
## Silent headless battle fixtures. No Main/Campaign, audio, input or save access.
const Lab=preload("res://scripts/fleet_lab.gd")
const Battle=preload("res://scripts/battle.gd")
const Damage=preload("res://scripts/damage.gd")
const Refit=preload("res://scripts/refit.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Version=preload("res://scripts/version.gd")
var failures: Array=[]
var checks: int=0

func check(ok: bool,message: String):
	checks+=1
	if not ok: failures.append(message)

func hull(world: Dictionary,id: String) -> Dictionary:
	for spec in world.HULLS:
		if spec.id==id: return spec.duplicate(true)
	return {}

func roster(world: Dictionary,ids: Array,repeats: int,fit: String,team: String) -> Array:
	var fleet: Array=[]
	for repeat_index in range(repeats):
		for id in ids:
			var base: Dictionary=hull(world,str(id))
			check(not base.is_empty(),"known hull: "+str(id))
			if base.is_empty(): continue
			var loadout: Dictionary=Refit.defaults(base)
			if fit=="all_families": loadout.weapons=["stock_primary","rapid_gun","fire_rocket","light_torpedo"]
			var validated: Dictionary=Refit.normalize(base,loadout)
			check(validated.get("ok",false),"valid fitting: "+str(id))
			if not validated.get("ok",false): continue
			var ship: Dictionary=Damage.create_ship(base)
			ship.uid="bench-%s-%d"%[team,fleet.size()]
			ship.loadout=loadout
			Refit.ensure(ship,base)
			# Explicit laboratory fixture stores; never a purchase or campaign award.
			ship.ammo=float(ship.spec.ammoCapacity)
			fleet.append(ship)
	return fleet

func _initialize():
	var args: Dictionary={"scenario":"duel","seed":"83","out":"","seconds":"","runid":""}
	for value in OS.get_cmdline_user_args():
		var pair: PackedStringArray=str(value).trim_prefix("--").split("=",true,1)
		if pair.size()!=2 or not args.has(pair[0]):
			push_error("Unknown bench argument: "+str(value))
			quit(1)
			return
		args[pair[0]]=pair[1]
	var config_path: String=get_script().resource_path.get_base_dir().path_join("bench_scenarios.json")
	var definitions=JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not definitions is Dictionary or not definitions.get("scenarios",{}).has(args.scenario):
		push_error("Unknown battle preset or unreadable scenario file.")
		quit(1)
		return
	var config: Dictionary=definitions.scenarios[args.scenario]
	var seconds: float=float(config.seconds) if str(args.seconds).is_empty() else str(args.seconds).to_float()
	if not is_finite(seconds) or seconds<=0.0 or seconds>180.0 or not str(args.seed).is_valid_int():
		push_error("Bench needs finite seconds in (0,180] and an integer seed.")
		quit(1)
		return
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var snapshot: Dictionary=world.duplicate(true)
	var players: Array=roster(world,config.player,int(config.get("playerRepeat",1)),str(config.get("playerFit","")),"player")
	var enemies: Array=roster(world,config.enemy,int(config.get("enemyRepeat",1)),"","enemy")
	var reserves_before: Array=players.duplicate(true)
	var battle: Dictionary=Battle.create({"fleet":players,"enemyFleet":enemies,"seed":int(args.seed)})
	Lab.configure_formation(battle,str(config.get("formation","")))
	check(battle.autopilot,"default flagship autopilot")
	check(battle.deployment.player<=300 and battle.deployment.enemy<=300,"deployment stays within 300 per side")
	if config.has("requirePoints"):
		check(battle.deployment.player==config.requirePoints and battle.deployment.enemy==config.requirePoints,"full deployment exactly 300 versus 300")
	if config.has("requirePlayerReserves"):
		check(battle.reserves.player.size()==config.requirePlayerReserves,"over-cap boats retained in safe reserve")
	var initial_count: int=battle.ships.size()
	var peak_projectiles: int=0
	var peak_effects: int=0
	var player_kinds: Dictionary={}
	var frames: int=0
	var started: int=Time.get_ticks_msec()
	var max_tick_us: int=0
	var samples_us: Array=[]
	for frame in range(ceili(seconds*30.0)):
		if battle.result!=null: break
		if Time.get_ticks_msec()-started>10000:
			failures.append("10-second owned-process work budget reached")
			break
		var before: int=Time.get_ticks_usec()
		Battle.update(battle,1.0/30.0,{})
		var tick_us: int=Time.get_ticks_usec()-before
		samples_us.append(tick_us)
		max_tick_us=maxi(max_tick_us,tick_us)
		frames+=1
		peak_projectiles=maxi(peak_projectiles,battle.projectiles.size())
		peak_effects=maxi(peak_effects,battle.effects.size())
		for projectile in battle.projectiles:
			if projectile.team=="player": player_kinds[str(projectile.kind)]=true
		if frame%30==0:
			for ship in battle.ships:
				for key in ["hp","water","ammo","fuel","supplies","crew","x","y"]:
					check(is_finite(float(ship[key])),"finite "+str(key)+" on "+str(ship.uid))
	for ship in battle.ships:
		check(ship.hp>=0 and ship.ammo>=0 and ship.fuel>=0 and ship.supplies>=0,"nonnegative condition/stores on "+str(ship.uid))
	for required in config.get("requirePlayerKinds",[]): check(player_kinds.has(required),"actual AI fired "+str(required))
	check(peak_projectiles<=400 and peak_effects<=200,"runtime projectile/effect caps respected")
	check(world==snapshot,"canonical source world is unchanged")
	for reserve in battle.reserves.player:
		for original in reserves_before:
			if reserve.uid==original.uid: check(reserve==original,"undeployed reserve unchanged")
	samples_us.sort()
	var p95_us: int=0 if samples_us.is_empty() else int(samples_us[mini(samples_us.size()-1,int(floor(samples_us.size()*0.95)))])
	var report: Dictionary={"schema":1,"tool":"fleet_bench","runId":args.runid,"gameVersion":Version.text(),"fixture":"isolated boats; no campaign or economy loaded","scenario":args.scenario,"label":config.label,"seed":int(args.seed),"requestedSeconds":seconds,"simulatedSeconds":battle.time,"frames":frames,"result":battle.result,"deployedBoats":initial_count,"deployment":battle.deployment,"playerReserves":battle.reserves.player.size(),"peakProjectiles":peak_projectiles,"peakEffects":peak_effects,"playerProjectileKinds":player_kinds.keys(),"wallMs":Time.get_ticks_msec()-started,"simulationTickP95us":p95_us,"simulationTickMaxUs":max_tick_us,"rendered":false,"audioAuditioned":false,"checks":checks,"failures":failures}
	if not str(args.out).is_empty():
		var file: FileAccess=FileAccess.open(str(args.out),FileAccess.WRITE)
		if file==null:
			push_error("Cannot write bench report")
			quit(1)
			return
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	print("BRASS BENCH %s: %d checks, %d failures, %d boats, %.1fs simulated in %dms"%[args.scenario,checks,failures.size(),initial_count,battle.time,report.wallMs])
	for failure in failures: print("FAIL bench: "+str(failure))
	quit(0 if failures.is_empty() else 1)
