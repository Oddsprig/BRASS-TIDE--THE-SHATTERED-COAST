extends RefCounted
## Original chart projection. No battle renderer, Damage, nodes, worker access,
## ship cloning or live condition queries. Layout is data-only; texture loads
## happen only while a real CanvasItem draws on Main. All caches are bounded.
const Profiles = preload("res://scripts/hull_profiles.gd")
const Mounts = preload("res://scripts/mount_layout.gd")
const WeaponGeometry = preload("res://scripts/weapon_geometry.gd")
const MANIFEST: String = "res://assets/campaign054/boats/asset-manifest.json"
const MAX_VESSELS: int = 5
const FIT_CACHE_LIMIT: int = 128
const OVERVIEW_SCALE: float = 0.22
static var _manifest_loaded: bool = false
static var _manifest_data: Dictionary = {}
static var _hulls: Dictionary = {}
static var _fits: Dictionary = {}
static var _textures: Dictionary = {}
static var _equipment_commands: Dictionary = {}

static func _manifest() -> Dictionary:
	if not _manifest_loaded:
		_manifest_loaded = true
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) if FileAccess.file_exists(MANIFEST) else null
		if parsed is Dictionary and str(parsed.get("schema", "")) == "brass-tide-campaign-boats054-v1":
			_manifest_data = parsed
	return _manifest_data

static func _rect(value: Array) -> Rect2:
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))

static func _rectangle(at: Vector2, size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([at-size*0.5, at+Vector2(size.x,-size.y)*0.5, at+size*0.5, at+Vector2(-size.x,size.y)*0.5])

static func _outline(stations: Array, offset: float, inset: float = 1.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	for station in stations:
		result.append(Vector2(station.x*(0.96 if inset<1.0 else 1.0), offset-station.y*inset))
	for i in range(stations.size()-2,-1,-1):
		var station: Vector2 = stations[i]
		result.append(Vector2(station.x*(0.96 if inset<1.0 else 1.0), offset+station.y*inset))
	return result

static func _poly(points: PackedVector2Array, color: Color) -> Dictionary:
	return {"kind":"polygon", "points":points, "color":color}

static func _line(points: PackedVector2Array, color: Color, width: float = 0.035, closed: bool = false) -> Dictionary:
	var actual: PackedVector2Array = points.duplicate()
	if closed and actual.size()>1: actual.append(actual[0])
	return {"kind":"line", "points":actual, "color":color, "width":width}

static func _hull(id: String) -> Dictionary:
	if _hulls.has(id): return _hulls[id]
	var entries: Dictionary = _manifest().get("hulls", {})
	if not Profiles.has_hull(id) or not entries.has(id): return {}
	var entry: Dictionary = entries[id]
	var stations: Array = []
	for point in entry.stations: stations.append(Vector2(float(point[0]),float(point[1])))
	var colors: Dictionary = {}
	for key in entry.palette: colors[key] = Color(str(entry.palette[key]))
	var commands: Array = []
	var offsets: Array = [-0.62,0.62] if bool(entry.catamaran) else [0.0]
	for offset in offsets:
		var outside: PackedVector2Array = _outline(stations,float(offset))
		commands.append(_poly(outside,colors.hull))
		commands.append(_line(outside,colors.dark,0.06,true))
		commands.append(_poly(_outline(stations,float(offset),0.77),colors.deck))
	if bool(entry.catamaran):
		var bridge_deck: PackedVector2Array = _rectangle(Vector2(-0.175,0),Vector2(3.25,1.24))
		commands.append(_poly(bridge_deck,colors.hull))
		commands.append(_poly(_rectangle(Vector2(-0.175,0),Vector2(3.13,1.08)),colors.deck))
	var cabin: Dictionary = entry.cabin
	var engine: Dictionary = entry.engine
	var cabin_at := Vector2(float(cabin.x),float(cabin.y))
	var cabin_size := Vector2(float(cabin.len),float(cabin.wid))
	commands.append(_poly(_rectangle(Vector2(float(engine.x),0),Vector2(float(engine.len),float(engine.wid))),colors.steel.darkened(0.28)))
	commands.append(_poly(_rectangle(cabin_at,cabin_size),colors.cabin))
	commands.append(_poly(_rectangle(cabin_at+Vector2(cabin_size.x*0.22,0),Vector2(cabin_size.x*0.27,cabin_size.y*0.80)),colors.glass))
	commands.append(_line(PackedVector2Array([cabin_at+Vector2(-cabin_size.x*0.35,0),cabin_at+Vector2(cabin_size.x*0.08,0)]),colors.dark,0.07))
	var result: Dictionary = {"hull_id":id, "path":str(entry.path), "local_bounds":_rect(entry.local_bounds),
		"source_size":Vector2(float(entry.source_size[0]),float(entry.source_size[1])),
		"source_pivot":Vector2(float(entry.source_pivot[0]),float(entry.source_pivot[1])),
		"stations":stations, "role":str(entry.role), "civilian_role":str(entry.civilian_role),
		"size":float(entry.size), "tier":int(entry.tier), "catamaran":bool(entry.catamaran),
		"colors":colors, "cabin":cabin.duplicate(true), "commands":commands}
	# Canonical profiles only; unknown IDs never synthesize an owned hull.
	_hulls[id] = result
	return result

## Detached, CPU-only metadata shared by drawing, geometry proof and hit tests.
static func asset_info(spec: Dictionary) -> Dictionary:
	return _hull(str(spec.get("id",""))).duplicate(true)

static func _tier(value, fallback: int = 1) -> int:
	if value is String: return int({"small":1,"medium":2,"large":3,"s":1,"m":2,"l":3}.get(str(value).to_lower(),fallback))
	return clampi(int(value),1,3) if value is int or value is float else fallback

static func _engine_id(boat: Dictionary, spec: Dictionary) -> String:
	for source in [boat,spec]:
		var loadout = source.get("loadout",{})
		if loadout is Dictionary and loadout.get("engine") is String: return str(loadout.engine)
		for key in ["engineModule","engineId","engine"]:
			if source.get(key) is String: return str(source[key])
	var fuel: float = float(spec.get("fuelUse",1.0))
	return "heavy_drive" if fuel>1.5 else "boost_drive" if fuel>1.2 else "economy_drive" if fuel<0.8 else "stock_engine"

static func _fit_key(spec: Dictionary, engine_id: String) -> String:
	# Copy only visible static fitting fields, never a boat/condition/full spec.
	var fields: Array = [str(spec.get("id","")),str(spec.get("role","")),float(spec.get("size",14.0)),int(spec.get("tier",1)),str(spec.get("faction","")),str(spec.get("weapon","gun")),engine_id,spec.has("weaponMounts")]
	for mount in spec.get("weaponMounts",[]):
		if not mount is Dictionary: continue
		fields.append([str(mount.get("id","")),str(mount.get("moduleId","")),str(mount.get("kind","gun")),mount.get("size",1),float(mount.get("x",0.0)),float(mount.get("y",0.0)),float(mount.get("angle",0.0))])
	return JSON.stringify(fields)

static func _variant(kind: String, tier: int) -> String:
	match kind:
		"cannon": return "cannon"
		"rocket": return "rocket_six" if tier>=2 else "rocket_three"
		"torpedo": return "torpedo_twin" if tier>=2 else "torpedo_single"
		_: return "gun_twin" if tier>=2 else "gun_single"

static func _fitting(spec: Dictionary, hull: Dictionary, engine_id: String) -> Dictionary:
	var key: String = _fit_key(spec,engine_id)
	if _fits.has(key): return _fits[key]
	var raw_mounts: Array = spec.get("weaponMounts",[]) if spec.get("weaponMounts") is Array else []
	var sockets: Array = Mounts.hardpoints(spec)
	var guns: Array = []
	var hull_size: float = Mounts.hull_size(spec)
	var weapons: Dictionary = _manifest().get("weapons",{})
	for mount in Mounts.mounts_of(spec):
		var tier: int = 1
		for socket in sockets:
			if str(socket.id)==str(mount.id): tier = int(socket.size)
		var module_id: String = "stock_primary"
		for original in raw_mounts:
			if original is Dictionary and str(original.get("id",""))==str(mount.id):
				tier = _tier(original.get("size",tier),tier)
				module_id = str(original.get("moduleId",""))
		var variant: String = _variant(str(mount.kind),tier)
		var entry: Dictionary = weapons.get(variant,{})
		guns.append({"id":str(mount.id),"module_id":module_id,"kind":str(mount.kind),"size":tier,
			"x":float(mount.worldX),"y":float(mount.worldY),"local_x":float(mount.x),"local_y":float(mount.y),
			"angle":float(mount.angle),"variant":variant,"unit":WeaponGeometry.unit(hull_size,tier)/hull_size,
			"path":str(entry.get("path","")),"local_bounds":_rect(entry.get("local_bounds",[-4.2,-4.8,18.8,9.6]))})
	var transom: float = float(hull.stations[0].x)
	var transom_beam: float = maxf(0.14,float(hull.stations[0].y))
	var cat: bool = bool(hull.catamaran)
	var small: bool = hull_size<=18.5
	var nozzle: bool = str(hull.role) in ["torpedo","rocket"] or str(hull.hull_id) in ["hook_raider","aegis_corvette","krill_torpedo","manta_strike","cinder_monitor","wraith_rocket"]
	var family: String = "outboard" if small else "nozzle" if nozzle else "stern_drive"
	var ys: Array = []
	if cat: ys = [-0.62,0.62]
	elif small and str(hull.hull_id) in ["bilge_punt","marsh_dart"] and engine_id!="heavy_drive": ys = [0.0]
	elif not small and (hull_size>=28.5 or (int(hull.tier)>=4 and hull_size>=24.0)):
		var spread: float = clampf(transom_beam*0.55,0.24,0.35)
		ys = [-spread,0.0,spread]
	else:
		var spread: float = clampf(transom_beam*0.52,0.17 if small else 0.22,0.24 if small else 0.31)
		ys = [-spread,spread]
	var motors: Array = []
	var motor_entry: Dictionary = _manifest().get("motors",{}).get(family,{})
	var width_scale: float = (1.12 if ys.size()==1 else 0.90 if ys.size()==3 else 1.0)*(1.08 if engine_id=="heavy_drive" else 1.0)
	for y in ys:
		motors.append({"x":transom-(0.16 if small else 0.19),"y":float(y),"kind":family,
			"width_scale":width_scale,"path":str(motor_entry.get("path","")),"local_bounds":_rect(motor_entry.get("local_bounds",[-0.23,-0.12,0.46,0.24]))})
	var result: Dictionary = {"mounts":guns,"motors":motors}
	if _fits.size()>=FIT_CACHE_LIMIT: _fits.erase(_fits.keys()[0])
	_fits[key] = result
	return result

static func _transform(at: Vector2, angle: float, unit: float) -> Transform2D:
	return Transform2D(Vector2(cos(angle),sin(angle))*unit,Vector2(-sin(angle),cos(angle))*unit,at)

static func _bounds(rect: Rect2, transform: Transform2D) -> Rect2:
	var result := Rect2(transform*rect.position,Vector2.ZERO)
	for corner in [Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]: result = result.expand(transform*corner)
	return result

static func _eligible(boat: Dictionary) -> bool:
	return not bool(boat.get("sunk",false)) and not bool(boat.get("hidden",false)) and bool(boat.get("visible",true)) and not bool(boat.get("mothballed",false)) and str(boat.get("storedPort","")).is_empty()

## center and heading are already in chart screen space (+X is the bow).
## Ordinary scale0.30 gives the starter ~68px including its real drives.
## Overview requires <=0.22; a caller can retain ordinary art below that.
## The old marker0.32 flag cannot shrink ordinary0.30 boats to overview size.
static func layout(boats: Array, center: Vector2, heading: float, zoom: float = 1.0, opts: Dictionary = {}) -> Dictionary:
	var overview: bool = zoom<=OVERVIEW_SCALE and bool(opts.get("overview",true))
	var lod: int = 2 if overview else 0 if zoom>=0.56 else 1
	var maximum: int = clampi(int(opts.get("max_vessels",MAX_VESSELS)),1,MAX_VESSELS)
	var multiplier: float = clampf(float(opts.get("size_multiplier",1.0)),0.5,2.0)
	var regional_scale: float = clampf(pow(maxf(0.01,zoom)/0.30,0.65 if zoom>0.30 else 0.34),0.88,3.2)
	var unit: float = (7.3 if overview else 15.25)*regional_scale*multiplier
	var prepared: Array = []
	var roster_count: int = 0
	for raw in boats:
		if not raw is Dictionary or not _eligible(raw): continue
		var spec: Dictionary = raw.get("spec",{}) if raw.get("spec") is Dictionary else raw
		var hull: Dictionary = _hull(str(spec.get("id","")))
		if hull.is_empty(): continue
		roster_count += 1
		if prepared.size()>=maximum: continue
		var pixels: float = unit*sqrt(maxf(8.0,float(hull.size))/14.0)
		var fitting: Dictionary = _fitting(spec,hull,_engine_id(raw,spec))
		var local_bounds: Rect2 = hull.local_bounds
		for gun in fitting.mounts:
			local_bounds = local_bounds.merge(_bounds(gun.local_bounds,_transform(Vector2(gun.local_x,gun.local_y),float(gun.angle),float(gun.unit))))
		var vessel: Dictionary = {"uid":str(raw.get("uid",raw.get("id",spec.get("id","")))),"hull_id":str(hull.hull_id),
			"angle":heading,"length_px":local_bounds.size.x*pixels,"beam_px":local_bounds.size.y*pixels,
			"asset_path":str(hull.path),"mounts":fitting.mounts.duplicate(true),"motors":fitting.motors.duplicate(true),
			"_hull":hull,"_local_bounds":local_bounds,"_pixels":pixels}
		prepared.append(vessel)
	# Lead stays exactly on the projected physical fleet position. Two staggered
	# pairs trail it; dimensions depend only on those five real displayed hulls.
	var lead_length: float = float(prepared[0].length_px) if not prepared.is_empty() else 0.0
	var lead_beam: float = float(prepared[0].beam_px) if not prepared.is_empty() else 0.0
	var row_x: float = 0.0
	var previous_length: float = lead_length
	for row in range(1,3):
		var first: int = row*2-1
		if first>=prepared.size(): break
		var row_length: float = float(prepared[first].length_px)
		var row_beam: float = float(prepared[first].beam_px)
		if first+1<prepared.size():
			row_length = maxf(row_length,float(prepared[first+1].length_px))
			row_beam = maxf(row_beam,float(prepared[first+1].beam_px))
		row_x -= (previous_length+row_length)*0.5+(5.0 if overview else 10.0)
		for index in range(first,mini(first+2,prepared.size())):
			prepared[index]["_offset"] = Vector2(row_x,(-1.0 if index==first else 1.0)*((lead_beam+row_beam)*0.5+(5.0 if overview else 10.0)))
		previous_length = row_length
	var vessels: Array = []
	var bounds := Rect2()
	var viewport: Rect2 = opts.get("viewport",Rect2()) if opts.get("viewport") is Rect2 else Rect2()
	var culled_count: int = 0
	for vessel in prepared:
		var at: Vector2 = center+Vector2(vessel.get("_offset",Vector2.ZERO)).rotated(heading)
		var transform: Transform2D = _transform(at,heading,float(vessel._pixels))
		var vessel_bounds: Rect2 = _bounds(vessel._local_bounds,transform).grow(1.0)
		if viewport.has_area() and not viewport.grow(6.0).intersects(vessel_bounds):
			culled_count += 1
			continue
		vessel["center"] = at
		vessel["transform"] = transform
		vessel["bounds"] = vessel_bounds
		vessels.append(vessel)
		bounds = vessel_bounds if vessels.size()==1 else bounds.merge(vessel_bounds)
	var hit_radius: float = 0.0
	if not vessels.is_empty():
		bounds = bounds.grow(4.0)
		for corner in [bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]: hit_radius = maxf(hit_radius,center.distance_to(corner))
	return {"vessels":vessels,"bounds":bounds,"hit_radius":hit_radius,"roster_count":roster_count,
		"visible_count":vessels.size(),"omitted_count":maxi(0,roster_count-prepared.size()),"culled_count":culled_count,"lod":lod,"center":center,"heading":heading}

static func _texture(path: String) -> Texture2D:
	if path.is_empty(): return null
	if not _textures.has(path):
		var resource = load(path) if ResourceLoader.exists(path) else null
		_textures[path] = resource if resource is Texture2D else null
	return _textures[path]

static func _draw_texture(canvas, path: String, rect: Rect2, transform: Transform2D) -> bool:
	if not canvas is CanvasItem: return false
	var texture: Texture2D = _texture(path)
	if texture==null: return false
	canvas.draw_set_transform_matrix(transform)
	canvas.draw_texture_rect(texture,rect,false)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true

static func _draw_commands(canvas, commands: Array, transform: Transform2D) -> void:
	var pixels: float = transform.x.length()
	for command in commands:
		var points: PackedVector2Array = transform*command.points
		if str(command.kind)=="polygon": canvas.draw_colored_polygon(points,command.color)
		else: canvas.draw_polyline(points,command.color,maxf(0.65,float(command.width)*pixels),true)

static func _gun_commands(variant: String) -> Array:
	if _equipment_commands.has(variant): return _equipment_commands[variant]
	var color := Color("6b8581")
	var dark := Color("20383c")
	var commands: Array = []
	var kind: String = variant.split("_")[0]
	if kind in ["gun","cannon"]:
		commands.append(_poly(_rectangle(Vector2.ZERO,Vector2(6,5)),color))
		var length: float = 14.2 if kind=="cannon" else 8.8
		var ys: Array = [-0.75,0.75] if variant=="gun_twin" else [0.0]
		for y in ys: commands.append(_line(PackedVector2Array([Vector2(1.0,float(y)),Vector2(length,float(y))]),Color("b5c6bc"),0.8))
		commands.append(_poly(_rectangle(Vector2(-0.5,0),Vector2(3,2.5)),dark))
	else:
		var count: int = 6 if variant=="rocket_six" else 3 if kind=="rocket" else 2 if variant=="torpedo_twin" else 1
		var length: float = 5.9 if kind=="rocket" else 7.9
		for i in range(count):
			var y: float = (float(i)-float(count-1)*0.5)*(1.1 if kind=="rocket" else 2.1)
			commands.append(_poly(_rectangle(Vector2((length-2.7)*0.5,y),Vector2(length+2.7,0.85 if kind=="rocket" else 1.65)),color))
	_equipment_commands[variant] = commands
	return commands

static func _selection(canvas, bounds: Rect2, color: Color) -> void:
	var span: float = clampf(minf(bounds.size.x,bounds.size.y)*0.22,5.0,11.0)
	for corner in [bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]:
		var dx: float = span if corner.x<bounds.get_center().x else -span
		var dy: float = span if corner.y<bounds.get_center().y else -span
		canvas.draw_line(corner,corner+Vector2(dx,0),Color(color,0.82),1.15,true)
		canvas.draw_line(corner,corner+Vector2(0,dy),Color(color,0.82),1.15,true)

## Real CanvasItem submits imported textures. A recorder receives bounded,
## nautical fallback geometry from the same canonical hulls and fitted mounts.
static func draw(canvas, plan: Dictionary, accent: Color = Color("e4c479"), selected: bool = false) -> Dictionary:
	var drawn: int = 0
	var textured: int = 0
	var lod: int = int(plan.get("lod",1))
	for vessel in plan.get("vessels",[]):
		var transform: Transform2D = vessel.transform
		var hull: Dictionary = vessel._hull
		var has_texture: bool = lod<2 and _draw_texture(canvas,str(vessel.asset_path),hull.local_bounds,transform)
		if has_texture: textured += 1
		else: _draw_commands(canvas,hull.commands,transform)
		for motor in vessel.motors:
			var motor_transform: Transform2D = transform*_transform(Vector2(motor.x,motor.y),0,1.0)
			motor_transform.y *= float(motor.width_scale)
			if lod>=2 or not _draw_texture(canvas,str(motor.path),motor.local_bounds,motor_transform):
				canvas.draw_colored_polygon(motor_transform*_rectangle(Vector2.ZERO,Vector2(0.40,0.16)),Color("9eafa3"))
		for gun in vessel.mounts:
			var gun_transform: Transform2D = transform*_transform(Vector2(gun.local_x,gun.local_y),float(gun.angle),float(gun.unit))
			if lod>=2 or not _draw_texture(canvas,str(gun.path),gun.local_bounds,gun_transform): _draw_commands(canvas,_gun_commands(str(gun.variant)),gun_transform)
		# Small affiliation stripe sits on the aft deck, never behind the boat.
		var transom: float = float(hull.stations[0].x)+0.17
		var stripe: PackedVector2Array = transform*PackedVector2Array([Vector2(transom,-0.16),Vector2(transom,0.16)])
		canvas.draw_line(stripe[0],stripe[1],Color(accent,0.88),1.25,true)
		drawn += 1
	if selected and drawn>0: _selection(canvas,plan.bounds,accent)
	return {"drawn_vessels":drawn,"textured_vessels":textured,"lod":lod,"bounds":plan.get("bounds",Rect2())}
