extends RefCounted
## Isolated fixtures using the actual fitting, deployment and damage rules.
const Damage=preload("res://scripts/damage.gd")
const Refit=preload("res://scripts/refit.gd")
const Records=preload("res://scripts/equipment_records.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Battle=preload("res://scripts/battle.gd")
const Routes=preload("res://scripts/tactical_routes.gd")

static func hull(world: Dictionary,id: String) -> Dictionary:
	for spec in world.HULLS:
		if spec.id==id: return spec
	return {}

static func entry(world: Dictionary,id: String,count: int=1) -> Dictionary:
	return {"hull":id,"count":count,"loadout":Refit.defaults(hull(world,id))}

static func presets() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/lab_presets.json")).scenarios

static func preset(world: Dictionary,id: String) -> Dictionary:
	var table: Dictionary=presets()
	var source: Dictionary=table.get(id,table.duel)
	var fits: Dictionary=source.get("fits",{}) if source.get("fits") is Dictionary else {}
	var config: Dictionary={
		"player":[],
		"enemy":[],
		"formation":str(source.get("formation","")),
		"objective":str(source.get("objective","")),
		"label":str(source.get("label","")),
		"context":str(source.get("context","")),
		"guidance":str(source.get("guidance","")),
		"carrierHull":str(source.get("carrierHull","")),
		"carrierCargo":source.get("carrierCargo",{}).duplicate(true) if source.get("carrierCargo") is Dictionary else {},
		"exit":source.get("exit",{}).duplicate(true) if source.get("exit") is Dictionary else {},
		"roles":source.get("roles",{}).duplicate(true) if source.get("roles") is Dictionary else {}
	}
	for team in ["player","enemy"]:
		for spec_id in source[team]:
			var item: Dictionary=entry(world,str(spec_id),int(source.get(team+"Repeat",1)))
			if team=="player" and source.get("playerFit","")=="all_families":
				item.loadout.weapons=["stock_primary","rapid_gun","fire_rocket","light_torpedo"]
			elif fits.get(spec_id) is Dictionary:
				item.loadout=fits[spec_id].duplicate(true)
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
	var carrier_uid: String=""
	var mission: Dictionary={}
	if str(config.get("objective",""))=="escort" and not fleets.player.is_empty():
		var carrier: Dictionary=fleets.player[0]
		var wanted: String=str(config.get("carrierHull",""))
		if not wanted.is_empty():
			for ship in fleets.player:
				if str(ship.get("type",""))==wanted or str(ship.spec.get("id",""))==wanted:
					carrier=ship
					break
		carrier_uid=str(carrier.uid)
		var cargo: Dictionary=config.get("carrierCargo",{}) if config.get("carrierCargo") is Dictionary else {}
		if cargo.is_empty(): cargo={"timber":4.0}
		mission={"kind":"escort","carrierTeam":"player","carrierUids":[carrier_uid],"allyUids":[carrier_uid],"carrierCargo":cargo.duplicate(true)}
		var exit: Dictionary=config.get("exit",{}) if config.get("exit") is Dictionary else {}
		if exit.has("x") and exit.has("y"): mission.exit=exit.duplicate(true)
	var place: String="Coastal Clash" if str(config.get("context",""))=="coastal_clash" else "Fleet battle laboratory"
	var options: Dictionary={"fleet":fleets.player,"enemyFleet":fleets.enemy,"seed":seed_value,"location":{"name":place}}
	if not mission.is_empty(): options.mission=mission
	var battle: Dictionary=Battle.create(options)
	if not str(battle.get("startError","")).is_empty():
		return {"ok":false,"error":str(battle.startError)}
	configure_formation(battle,str(config.get("formation","")))
	var carrier_id: String=""
	for ship in battle.ships:
		if str(ship.get("uid",""))==carrier_uid:
			carrier_id=str(ship.id)
			break
	var role_error: String=_assign_roles(battle,config.get("roles",{}) if config.get("roles") is Dictionary else {},carrier_id)
	if not role_error.is_empty(): return {"ok":false,"error":role_error}
	return {"ok":true,"battle":battle}

static func _assign_roles(battle: Dictionary,roles: Dictionary,carrier_id: String) -> String:
	for hull_id in roles:
		var role: String=str(roles[hull_id])
		if not role in ["auto","skirmisher","striker","heavy","screen","support"]:
			return "Unknown tactical role for %s."%str(hull_id)
		var ids: Array=[]
		for ship in battle.ships:
			if str(ship.get("team",""))!="player": continue
			if str(ship.get("type",""))==str(hull_id) or str(ship.spec.get("id",""))==str(hull_id):
				ids.append(ship.id)
		if ids.is_empty(): continue
		var patch: Dictionary={"role":role}
		if role=="screen" and not carrier_id.is_empty():
			patch.protectedAllyId=carrier_id
			patch.formation="screen"
		if not Battle.set_tactical_options(battle,ids,patch):
			return "Could not assign the %s role to %s."%[role,str(hull_id)]
	return ""

static func configure_formation(battle: Dictionary,formation: String):
	if formation=="surrounded":
		var players: Array=battle.ships.filter(func(s):return s.team=="player")
		var enemies: Array=battle.ships.filter(func(s):return s.team=="enemy")
		if players.size()!=1 or enemies.size()!=4:return
		var center=Vector2(1100,850)
		players[0].x=center.x;players[0].y=center.y;players[0].angle=0.0
		for i in range(enemies.size()):
			var position: Vector2=center+Vector2.from_angle(i*TAU/4)*330.0
			enemies[i].x=position.x;enemies[i].y=position.y
			enemies[i].angle=(center-position).angle()
		return
	if formation=="closing":
		_close_on_player(battle)

static func _close_on_player(battle: Dictionary) -> void:
	var players: Array=battle.ships.filter(func(s):return s.team=="player")
	var enemies: Array=battle.ships.filter(func(s):return s.team=="enemy")
	if players.is_empty() or enemies.is_empty(): return
	var anchor: Vector2=Vector2.ZERO
	for ship in players:
		anchor+=Vector2(ship.x,ship.y)
	anchor/=float(players.size())
	var geometry: Dictionary=Routes.terrain(battle)
	var spacing: float=120.0
	var count: int=enemies.size()
	for gap in [340.0,440.0,560.0,700.0]:
		var points: Array=[]
		var clear: bool=true
		var origin_y: float=anchor.y-(float(count)-1.0)*spacing*0.5
		for i in range(count):
			var ship: Dictionary=enemies[i]
			var radius: float=maxf(12.0,float(ship.spec.get("size",16.0)))
			var point: Vector2=Vector2(anchor.x+gap,origin_y+float(i)*spacing)
			var budget: Dictionary={"clearanceTests":0,"clearanceLimit":4096,"exhaustions":0}
			if Routes.sweep(geometry,point,point,radius,budget)!="valid":
				clear=false
				break
			for other in players:
				var other_r: float=maxf(12.0,float(other.spec.get("size",16.0)))
				if point.distance_to(Vector2(other.x,other.y))<radius+other_r+8.0:
					clear=false
					break
			if not clear: break
			for j in range(points.size()):
				var prior_r: float=maxf(12.0,float(enemies[j].spec.get("size",16.0)))
				if point.distance_to(points[j])<radius+prior_r+8.0:
					clear=false
					break
			if not clear: break
			points.append(point)
		if not clear or points.size()!=count: continue
		for i in range(count):
			var ship: Dictionary=enemies[i]
			var point: Vector2=points[i]
			ship.x=point.x
			ship.y=point.y
			ship.vx=0.0
			ship.vy=0.0
			ship.angle=(anchor-point).angle()
			ship.turretAngle=ship.angle
		return
