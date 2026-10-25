extends RefCounted
## Isolated fixtures using the actual fitting, deployment and damage rules.
const Damage=preload("res://scripts/damage.gd")
const Refit=preload("res://scripts/refit.gd")
const Records=preload("res://scripts/equipment_records.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Battle=preload("res://scripts/battle.gd")

static func hull(world: Dictionary,id: String) -> Dictionary:
	for spec in world.HULLS:
		if spec.id==id: return spec
	return {}

static func entry(world: Dictionary,id: String,count: int=1) -> Dictionary:
	return {"hull":id,"count":count,"loadout":Refit.defaults(hull(world,id))}

static func presets() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/lab_presets.json")).scenarios

static func preset(world: Dictionary,id: String) -> Dictionary:
	var source: Dictionary=presets().get(id,presets().duel)
	var config: Dictionary={"player":[],"enemy":[],"formation":source.get("formation","")}
	for team in ["player","enemy"]:
		for spec_id in source[team]:
			var item: Dictionary=entry(world,spec_id,int(source.get(team+"Repeat",1)))
			if team=="player" and source.get("playerFit","")=="all_families":
				item.loadout.weapons=["stock_primary","rapid_gun","fire_rocket","light_torpedo"]
			config[team].append(item)
	return config

static func inspect(world: Dictionary,config: Dictionary) -> Dictionary:
	var result: Dictionary={"ok":true,"error":"","player":{"points":0,"boats":0,"crew":0},"enemy":{"points":0,"boats":0,"crew":0}}
	for team in ["player","enemy"]:
		if not config.get(team) is Array or config[team].is_empty() or config[team].size()>24:
			return {"ok":false,"error":"Each side needs 1–24 fleet entries."}
		for item in config[team]:
			if not item is Dictionary or not item.get("count") is int or item.count<1 or item.count>40:
				return {"ok":false,"error":"Boat quantity must be 1–40."}
			var spec: Dictionary=hull(world,str(item.get("hull","")))
			if spec.is_empty(): return {"ok":false,"error":"Choose a known hull."}
			var fit: Dictionary=Refit.normalize(spec,item.get("loadout",{}))
			if not fit.ok: return {"ok":false,"error":spec.name+": "+fit.message}
			result[team].points+=Deployment.cost(Refit.effective_spec(spec,fit.loadout))*item.count
			result[team].boats+=item.count
			result[team].crew+=int(spec.crewOptimal)*item.count
		if result[team].points>300 or result[team].boats>40:
			result.ok=false
			result.error="%s exceeds 300 points or 40 boats. Reduce its roster."%team.capitalize()
	return result

static func create(world: Dictionary,config: Dictionary,seed_value: int) -> Dictionary:
	var checked: Dictionary=inspect(world,config)
	if not checked.ok: return checked
	var catalog: Dictionary=Refit.catalog()
	var known_uids: Array=[]
	var fleets: Dictionary={"player":[],"enemy":[]}
	for team in fleets:
		for item in config[team]:
			var spec: Dictionary=hull(world,item.hull)
			var fit: Dictionary=Refit.normalize(spec,item.get("loadout",{}))
			if not fit.ok: return {"ok":false,"error":spec.name+": "+fit.message}
			for n in range(item.count):
				var ship: Dictionary=Damage.create_ship(spec)
				ship.uid="lab-%s-%d"%[team,fleets[team].size()]
				ship.loadout=fit.loadout.duplicate(true)
				var seeded: Dictionary=Records.initialize(ship,{"base":spec.duplicate(true),"loadout":ship.loadout.duplicate(true),"catalog":catalog,"identity":ship.uid,"knownUids":known_uids})
				if not seeded.ok: return {"ok":false,"error":str(seeded.get("error","Laboratory equipment initialization failed."))}
				known_uids.append_array(seeded.get("itemUids",[]))
				Refit.ensure(ship,spec)
				ship.ammo=float(ship.spec.ammoCapacity)
				ship.fuel=120.0
				fleets[team].append(ship)
	var battle: Dictionary=Battle.create({"fleet":fleets.player,"enemyFleet":fleets.enemy,"seed":seed_value,"location":{"name":"Fleet battle laboratory"}})
	if config.get("objective","")=="escort" and not fleets.player.is_empty():
		battle.mission={"kind":"escort","allyUids":[fleets.player[0].uid],"duration":45.0}
	configure_formation(battle,str(config.get("formation","")))
	return {"ok":true,"battle":battle}

static func configure_formation(battle: Dictionary,formation: String):
	if formation!="surrounded":return
	var players: Array=battle.ships.filter(func(s):return s.team=="player")
	var enemies: Array=battle.ships.filter(func(s):return s.team=="enemy")
	if players.size()!=1 or enemies.size()!=4:return
	var center=Vector2(1100,850)
	players[0].x=center.x;players[0].y=center.y;players[0].angle=0.0
	for i in range(enemies.size()):
		var position: Vector2=center+Vector2.from_angle(i*TAU/4)*330.0
		enemies[i].x=position.x;enemies[i].y=position.y
		enemies[i].angle=(center-position).angle()
