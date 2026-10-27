extends SceneTree
## Root-only native fixture: two real Lab presets, no Main/save/render setup.
const Lab=preload("res://scripts/fleet_lab.gd")
const Battle=preload("res://scripts/battle.gd")
const Damage=preload("res://scripts/damage.gd")
const Refit=preload("res://scripts/refit.gd")
const Records=preload("res://scripts/equipment_records.gd")
const Deployment=preload("res://scripts/deployment.gd")
const CASES: Dictionary={
	"pressure_crossing":{"player":["tin_skiff"],"enemy":["furnace_turret"],"points":{"player":17,"enemy":72}},
	"pressure_breakaway":{"player":["tin_skiff","ash_corvette"],"enemy":["furnace_turret","bilge_punt"],"points":{"player":56,"enemy":86}}
}
const FITS: Dictionary={
	"tin_skiff":["light_torpedo",""],
	"ash_corvette":["stock_primary","rapid_gun",""],
	"furnace_turret":["heavy_cannon","","",""],
	"bilge_punt":["stock_primary",""]
}
var checks: int=0
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("PRESSURE PRESETS044: "+message)

func totals(battle: Dictionary,team: String) -> Dictionary:
	var result: Dictionary={"ammo":0.0,"fuel":0.0}
	for ship in battle.ships:
		if str(ship.team)==team:
			result.ammo+=float(ship.ammo)
			result.fuel+=float(ship.fuel)
	return result

func inspect_ship(world: Dictionary,ship: Dictionary,replay_ship: Dictionary,seen_ships: Dictionary,seen_items: Dictionary) -> void:
	var uid: String=str(ship.uid)
	var base: Dictionary=Lab.hull(world,str(ship.type))
	check(not uid.is_empty() and not seen_ships.has(uid),"unique hull custody "+uid)
	seen_ships[uid]=true
	var expected_fit: Dictionary={"weapons":FITS[str(ship.type)].duplicate(),"engine":"stock_engine","armor":"stock_armor"}
	var normalized: Dictionary=Refit.normalize(base,expected_fit)
	check(bool(normalized.ok) and ship.loadout==normalized.get("loadout",{}),"actual normalized fitting "+uid)
	check(ship.spec==Refit.effective_spec(base,expected_fit),"live spec comes from real fitting "+uid)
	check(float(ship.hp)==float(base.hp) and float(ship.crew)==float(base.crewOptimal) and float(ship.wounded)==0.0,"normal hull and finite crew "+uid)
	check(float(ship.water)==0.0 and float(ship.fire)==0.0 and ship.breaches.is_empty(),"no injected flood, fire or breaches "+uid)
	check(float(ship.ammo)==80.0*maxi(1,ship.spec.weaponMounts.size()) and float(ship.fuel)==120.0 and float(ship.supplies)==20.0,"normal finite ammunition, fuel and kits "+uid)
	check(ship.get("refitLocker",{})=={},"no invented spare parts "+uid)
	check(not is_same(ship,replay_ship) and not is_same(ship.moduleCondition,replay_ship.moduleCondition) and not is_same(ship.moduleCondition.items,replay_ship.moduleCondition.items),"same-seed boats own separate conditions "+uid)
	var snapshot: Dictionary=Records.snapshot(ship)
	check(bool(snapshot.get("ok",false)) and str(snapshot.get("birthNamespace",""))==uid,"canonical equipment validates for isolated owner "+uid)
	if not bool(snapshot.get("ok",false)):
		return
	for i in range(expected_fit.weapons.size()):
		var slot: String="mount%d"%i
		var wanted: String=str(expected_fit.weapons[i])
		check(not snapshot.installed.has(slot) if wanted.is_empty() else str(snapshot.installed.get(slot,{}).get("typeId",""))==wanted,"physical socket matches fitting "+uid+"/"+slot)
	check(str(snapshot.installed.get("engine",{}).get("typeId",""))=="stock_engine" and str(snapshot.installed.get("armor",{}).get("typeId",""))=="stock_armor","stock machinery and armor custody "+uid)
	for item_uid in ship.moduleCondition.items:
		var item: Dictionary=ship.moduleCondition.items[item_uid]
		check(str(item.itemUid)==str(item_uid) and not seen_items.has(str(item_uid)),"item has exactly one sandbox owner "+str(item_uid))
		seen_items[str(item_uid)]=true
	var before: PackedByteArray=var_to_bytes(ship)
	if snapshot.installed.has("engine"):
		snapshot.installed.engine.hp=0.0
	check(var_to_bytes(ship)==before,"public equipment snapshot is detached "+uid)
	var status: Dictionary=Damage.get_status(ship)
	check(bool(status.get("equipmentOk",false)) and str(status.get("equipmentMode",""))=="canonical","public damage status accepts canonical custody "+uid)

func exercise(world: Dictionary,id: String,table: Dictionary) -> void:
	check(table.has(id),"discoverable by existing dynamic Lab picker: "+id)
	if not table.has(id):
		return
	var expected: Dictionary=CASES[id]
	var config: Dictionary=Lab.preset(world,id)
	var config_before: Dictionary=config.duplicate(true)
	check(str(config.preset)==id and not str(config.label).is_empty() and not str(config.guidance).is_empty(),"preset supplies its label and actionable guidance "+id)
	check(str(config.formation)=="closing" and str(config.objective).is_empty() and str(config.context).is_empty() and config.roles.is_empty(),"ordinary closing battle without mission or role overrides "+id)
	for team in ["player","enemy"]:
		var roster: Array=[]
		for entry in config[team]:
			roster.append(str(entry.hull))
			check(int(entry.count)==1,"one real boat per roster entry "+id+"/"+str(entry.hull))
		check(roster==expected[team],"requested small roster "+id+"/"+team)
	var inspected: Dictionary=Lab.inspect(world,config)
	check(bool(inspected.get("ok",false)),"public Lab.inspect accepts both fittings and points "+id)
	if not bool(inspected.get("ok",false)):
		return
	for team in ["player","enemy"]:
		check(int(inspected[team].points)==int(expected.points[team]) and int(inspected[team].points)<=Deployment.LIMIT,"exact fitted deployment cost "+id+"/"+team)
	var created: Dictionary=Lab.create(world,config,44044)
	var repeated: Dictionary=Lab.create(world,Lab.preset(world,id),44044)
	check(bool(created.get("ok",false)) and bool(repeated.get("ok",false)),"public Lab.create builds both isolated instances "+id)
	if not bool(created.get("ok",false)) or not bool(repeated.get("ok",false)):
		return
	var battle: Dictionary=created.battle
	var replay: Dictionary=repeated.battle
	var replay_before: Dictionary=replay.duplicate(true)
	check(battle.ships.size()==expected.player.size()+expected.enemy.size() and battle.ships==replay.ships,"same seed recreates every constructed boat "+id)
	check(bool(battle.autopilot) and battle.result==null and str(Battle.get_flagship(battle).get("type",""))=="tin_skiff","ordinary autopilot start with Tinwake damage controls "+id)
	check(int(battle.deployment.limit)==300 and battle.reserves.player.is_empty() and battle.reserves.enemy.is_empty(),"normal cap with every practice boat deployed "+id)
	var seen_ships: Dictionary={}
	var seen_items: Dictionary={}
	for i in range(battle.ships.size()):
		inspect_ship(world,battle.ships[i],replay.ships[i],seen_ships,seen_items)
	for team in ["player","enemy"]:
		check(int(battle.deployment[team])==int(expected.points[team]),"actual deployed DP agrees with inspection "+id+"/"+team)
	var start: Dictionary={"player":totals(battle,"player"),"enemy":totals(battle,"enemy")}
	var positions: Dictionary={}
	for ship in battle.ships:
		positions[str(ship.id)]=Vector2(ship.x,ship.y)
	var moved: bool=false
	var ticks: int=0
	# Exercise the launched preset unchanged: no teleports, damage, injected events
	# or forced firing authority. Allow up to three simulated seconds for first
	# action; a heavy holding a firing station need not move or consume fuel.
	for _i in range(90):
		Battle.update(battle,1.0/30.0,{})
		ticks+=1
		for ship in battle.ships:
			if Vector2(positions[str(ship.id)]).distance_to(Vector2(ship.x,ship.y))>0.01:
				moved=true
		var player_now: Dictionary=totals(battle,"player")
		var enemy_now: Dictionary=totals(battle,"enemy")
		var fired: bool=float(player_now.ammo)<float(start.player.ammo) and float(enemy_now.ammo)<float(start.enemy.ammo)
		var fuel_used: bool=float(player_now.fuel)+float(enemy_now.fuel)<float(start.player.fuel)+float(start.enemy.fuel)
		if (ticks>=24 and fired and moved and fuel_used) or battle.result!=null:
			break
	check(ticks>=24 and is_equal_approx(float(battle.time),float(ticks)/30.0),"bounded real updates advance practice time "+id)
	check(moved,"real autopilot movement occurs without requiring every hull to move "+id)
	for team in ["player","enemy"]:
		var after: Dictionary=totals(battle,team)
		check(float(after.ammo)<float(start[team].ammo) and float(after.ammo)>=0.0,"real firing debits finite ammunition "+id+"/"+team)
		check(float(after.fuel)<=float(start[team].fuel) and float(after.fuel)>=0.0,"updates preserve finite fuel "+id+"/"+team)
	check(float(totals(battle,"player").fuel)+float(totals(battle,"enemy").fuel)<float(start.player.fuel)+float(start.enemy.fuel),"actual propulsion consumes carried fuel "+id)
	for ship in battle.ships:
		var status: Dictionary=Damage.get_status(ship)
		check(bool(status.get("equipmentOk",false)) and float(ship.supplies)>=0.0 and float(ship.crew)<=float(ship.crewOptimal),"updates preserve canonical equipment and finite crew/kits "+id+"/"+str(ship.uid))
	check(replay==replay_before,"updating one construction leaves the entire other battle unchanged "+id)
	check(config==config_before and Lab.preset(world,id)==config_before,"construction/updates leave preset inputs and later launches untouched "+id)

func run() -> void:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var world_before: Dictionary=world.duplicate(true)
	var catalog_before: Dictionary=Refit.catalog().duplicate(true)
	var table: Dictionary=Lab.presets()
	for id in CASES:
		exercise(world,str(id),table)
	check(world==world_before and Refit.catalog()==catalog_before,"practice construction and live updates preserve complete world/catalogue inputs")
	print("PRESSURE PRESETS044: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
