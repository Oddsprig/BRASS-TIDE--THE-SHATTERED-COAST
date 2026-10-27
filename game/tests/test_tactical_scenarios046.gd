extends SceneTree
## Compact public-Lab prefixes, not full-pass, motion, play-feel or FPS proof.
const Lab=preload("res://scripts/fleet_lab.gd")
const Battle=preload("res://scripts/battle.gd")
const Damage=preload("res://scripts/damage.gd")
const Refit=preload("res://scripts/refit.gd")
const Records=preload("res://scripts/equipment_records.gd")
const Tactical=preload("res://scripts/tactical_runtime.gd")
const Roles=preload("res://scripts/tactical_role_plans.gd")
const DT: float=1.0/60.0
const CASES: Dictionary={
	"tactical_flanker_heavy":{"player":{"tin_skiff":"skirmisher","bilge_punt":"skirmisher"},"enemy":{"furnace_turret":"heavy"},"ticks":36},
	"tactical_escort_raider":{"player":{"fourport_packet":"support","ash_corvette":"screen"},"enemy":{"marsh_dart":"skirmisher","bilge_punt":"skirmisher"},"ticks":36},
	"tactical_strike_pass":{"player":{"tin_skiff":"striker"},"enemy":{"furnace_turret":"heavy"},"ticks":90},
	"tactical_withdrawal":{"player":{"tin_skiff":"skirmisher"},"enemy":{"furnace_turret":"heavy"},"ticks":36},
	"tactical_wounded_cover":{"player":{"tin_skiff":"skirmisher","ash_corvette":"screen"},"enemy":{"marsh_dart":"skirmisher","bilge_punt":"skirmisher"},"ticks":36},
	"tactical_mixed":{"player":{"cobalt_frigate":"heavy","tin_skiff":"skirmisher","reed_stinger":"striker","fourport_packet":"support"},"enemy":{"furnace_turret":"heavy","marsh_dart":"skirmisher","barbed_lance":"striker"},"ticks":36}
}
var checks: int=0
var failures: int=0

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("TACTICAL SCENARIOS046: "+message)

func boat(battle: Dictionary,team: String,hull_id: String) -> Dictionary:
	for ship in battle.ships:
		if str(ship.team)==team and str(ship.type)==hull_id:return ship
	return {}

func exercise(world: Dictionary,id: String) -> void:
	var config: Dictionary=Lab.preset(world,id)
	var original: Dictionary=config.duplicate(true)
	var inspected: Dictionary=Lab.inspect(world,config)
	check(str(config.preset)==id and not str(config.label).is_empty() and not str(config.guidance).is_empty() and bool(inspected.get("ok",false)),"named public picker preset and legal fits/DP: "+id)
	if not bool(inspected.get("ok",false)):return
	var made: Dictionary=Lab.create(world,config,46046)
	check(bool(made.get("ok",false)),"ordinary public Lab construction: "+id)
	if not bool(made.get("ok",false)):return
	var battle: Dictionary=made.battle
	var expected: Dictionary=CASES[id]
	var starts: Dictionary={}
	var costs: Dictionary={}
	var spent: Dictionary={}
	var item_uids: Dictionary={}
	check(battle.autopilot and battle.result==null and battle.projectiles.is_empty() and battle.events.is_empty() and is_zero_approx(float(battle.time)),"no manufactured opening shots or result: "+id)
	for team in ["player","enemy"]:
		check(int(inspected[team].boats)==expected[team].size() and int(battle.deployment[team])==int(inspected[team].points) and int(battle.deployment[team])<=300 and battle.reserves[team].is_empty(),"every small practice boat really deploys: "+id+"/"+team)
	for ship in battle.ships:
		var sid: String=str(ship.id)
		var base: Dictionary=Lab.hull(world,str(ship.type))
		var fit: Dictionary=Refit.normalize(base,config[ship.team].filter(func(e):return str(e.hull)==str(ship.type))[0].loadout)
		var snap: Dictionary=Records.snapshot(ship)
		check(bool(snap.get("ok",false)) and not bool(snap.get("needsInitialize",true)) and ship.loadout==fit.loadout and ship.spec==Refit.effective_spec(base,fit.loadout),"real fitted canonical owner: "+id+"/"+sid)
		for item_uid in ship.moduleCondition.items:
			check(not item_uids.has(str(item_uid)),"unique physical equipment custody: "+id+"/"+str(item_uid))
			item_uids[str(item_uid)]=true
		check(float(ship.ammo)==float(ship.spec.ammoCapacity) and float(ship.fuel)==120.0 and float(ship.supplies)==20.0 and float(ship.crew)==float(base.crewOptimal),"normal finite birth stores and crew: "+id+"/"+sid)
		check(float(ship.water)==0.0 and float(ship.get("lastShotTime",0.0))<0.0,"no injected water or shot acknowledgement: "+id+"/"+sid)
		var damaged: bool=ship.team=="player" and ship.type=="tin_skiff" and id in ["tactical_withdrawal","tactical_wounded_cover"]
		if damaged:
			var fraction: float=float(ship.hp)/float(ship.maxHp)
			check((fraction>0.39 and fraction<0.41) if id=="tactical_withdrawal" else (fraction>0.69 and fraction<0.71),"declared canonical shell changes actual hull: "+id)
			check(float(snap.get("installed",{}).get("armor",{}).get("hp",1.0))<1.0 and str(ship.policy)==("bail" if id=="tactical_withdrawal" else "repair") and str(config.guidance).contains("INITIAL DAMAGE"),"real armor damage and labelled damage-control policy: "+id)
		else:
			check(float(ship.hp)==float(ship.maxHp) and float(ship.fire)==0.0 and float(ship.wounded)==0.0 and ship.breaches.is_empty(),"other boats start healthy: "+id+"/"+sid)
		starts[sid]={"position":Vector2(ship.x,ship.y),"ammo":float(ship.ammo),"fuel":float(ship.fuel),"supplies":float(ship.supplies),"crew":float(ship.crew)}
		costs[sid]={};spent[sid]=0.0
		for mount in ship.spec.weaponMounts:costs[sid][str(mount.id)]=float(mount.ammoCost)
	# Only normal simulation and the existing event drain. No direct fire, hit,
	# teleport, refill, private planner call or forced result in this chronology.
	var chronological: bool=true
	var finite: bool=true
	var fired: int=0
	var previous_seq: int=0
	for tick in range(int(expected.ticks)):
		Battle.update(battle,DT,{})
		chronological=chronological and is_equal_approx(float(battle.time),float(tick+1)*DT) and battle.result==null
		for event in Battle.pop_events(battle):
			chronological=chronological and int(event.seq)>previous_seq and float(event.time)>0.0 and float(event.time)<=float(battle.time)
			previous_seq=int(event.seq)
			if str(event.kind)!="fire":continue
			var source: String=str(event.sourceId)
			var mount_id: String=str(event.mountId)
			var real_mount: bool=costs.has(source) and costs.get(source,{}).has(mount_id)
			chronological=chronological and real_mount
			if real_mount:spent[source]+=float(costs[source][mount_id])
			fired+=1
		for ship in battle.ships:
			for key in ["x","y","vx","vy","angle","hp","water","fire","engine","crew","wounded","ammo","fuel","supplies"]:finite=finite and is_finite(float(ship[key]))
	check(chronological and finite,"bounded real 60Hz time, state and event chronology: "+id)
	check(str(battle.tactical.manualId).is_empty(),"both teams retain ordinary autopilot: "+id)
	var moved: bool=false
	for ship in battle.ships:
		var sid: String=str(ship.id)
		var start: Dictionary=starts[sid]
		moved=moved or Vector2(ship.x,ship.y).distance_to(start.position)>0.01
		check(is_equal_approx(float(start.ammo)-float(ship.ammo),float(spent[sid])) and float(ship.ammo)>=0.0 and float(ship.fuel)>=0.0 and float(ship.fuel)<=float(start.fuel) and float(ship.supplies)>=0.0 and float(ship.supplies)<=float(start.supplies),"actual shots explain finite store debits: "+id+"/"+sid)
		check(bool(Damage.get_status(ship).get("equipmentOk",false)) and float(ship.crew)<=float(start.crew) and float(ship.wounded)>=0.0 and float(ship.wounded)<=float(ship.crew) and battle.tactical.lastSafety.has(sid) and battle.tactical.memory[ship.team].byId.has(sid),"canonical condition, finite crew and real AI participation on each team: "+id+"/"+sid)
	check(moved,"autopilot actually advances at least one practice boat: "+id)
	for team in ["player","enemy"]:
		var view: Dictionary=Tactical.view(battle,team,[])
		var context: Dictionary=Roles.ships_by_id(view)
		for hull_id in expected[team]:
			var ship: Dictionary=boat(battle,team,str(hull_id))
			check(not ship.is_empty() and context.has(str(ship.id)) and Roles.infer_role(view,context[str(ship.id)])==str(expected[team][hull_id]),"actual fitted role: "+id+"/"+team+"/"+str(hull_id))
	if id=="tactical_strike_pass":
		var striker: Dictionary=boat(battle,"player","tin_skiff")
		check(float(spent.get(str(striker.id),0.0))>=2.0 and Battle.mount_shot_time(striker,"mount0")>0.0,"fitted strike prefix emits a real finite-ammo torpedo: "+id)
	if id=="tactical_withdrawal":
		check(bool(battle.tactical.safety.get(str(boat(battle,"player","tin_skiff").id),{}).get("withdraw",false)),"real hull danger requests withdrawal without a forced order")
	if id=="tactical_wounded_cover" or id=="tactical_escort_raider":
		var escort: Dictionary=boat(battle,"player","ash_corvette")
		var ally: Dictionary=boat(battle,"player","tin_skiff" if id=="tactical_wounded_cover" else "fourport_packet")
		check(str(battle.tactical.memory.player.byId.get(str(escort.id),{}).get("leaderId",""))==str(ally.id),"screen protects the actual carrier or wounded ally: "+id)
		if id=="tactical_escort_raider":check(Battle.objective_snapshot(battle).carriers[0].cargoAboard==config.carrierCargo,"real isolated carrier keeps its actual assigned cargo")
	check(config==original and Lab.preset(world,id)==original,"construction and chronology preserve public preset inputs: "+id)
	print("TACTICAL SCENARIOS046 prefix ",id,": ",expected.ticks," real ticks, ",fired," real shots; no motion/FPS verdict")

func run() -> void:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var original: Dictionary=world.duplicate(true)
	var catalog: Dictionary=Refit.catalog().duplicate(true)
	var table: Dictionary=Lab.presets()
	for id in CASES:
		check(table.has(id),"discoverable through existing Lab picker: "+str(id))
		if table.has(id):exercise(world,str(id))
	check(world==original and Refit.catalog()==catalog,"all practice starts preserve source world and catalogue")
	print("TACTICAL SCENARIOS046: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
