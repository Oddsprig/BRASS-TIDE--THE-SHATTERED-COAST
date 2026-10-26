extends RefCounted
## Workshop detail in hull-local XY and physical height units. Baked by BoatArt's
## existing main-thread mesh cache; this module allocates no nodes or resources.
const Profiles = preload("res://scripts/hull_profiles.gd")
const Layout = preload("res://scripts/mount_layout.gd")
const Shapes = preload("res://scripts/weapon_art.gd")
static var _plans: Dictionary = {}

static func _model(ctx: Dictionary, at: Vector2 = Vector2.ZERO) -> Dictionary:
	return {"ctx":ctx, "at":at, "bearing":0.0, "u":1.0, "world_unit":1.0, "lod":ctx.lod, "h":0.0}

static func _line(m: Dictionary, a: Vector3, b: Vector3, color: Color, width: float = 0.75) -> void:
	Shapes._line(m,a,b,color,width*float(m.ctx.size)*0.05)

static func _rect(m: Dictionary, x: float, y: float, length: float, width: float, z: float, color: Color) -> void:
	Shapes._face(m,[Vector3(x-length*0.5,y-width*0.5,z),Vector3(x+length*0.5,y-width*0.5,z),Vector3(x+length*0.5,y+width*0.5,z),Vector3(x-length*0.5,y+width*0.5,z)],color)

static func _width(stations: Array, x: float) -> float:
	for i in range(stations.size()-1):
		var a: Vector2 = stations[i]
		var b: Vector2 = stations[i+1]
		if x>=a.x and x<=b.x:
			return lerpf(a.y,b.y,(x-a.x)/(b.x-a.x))
	return 0.0

static func _clear(sockets: Array, item: Dictionary) -> bool:
	for socket in sockets:
		if Layout.footprint_clearance(socket,item)<0.025:return false
	return true

static func _overlaps(a: Dictionary, b: Dictionary) -> bool:
	return absf(float(a.x)-float(b.x))<(float(a.get("len",a.get("length",0.0)))+float(b.get("len",b.get("length",0.0))))*0.5+0.025 and absf(float(a.y)-float(b.y))<(float(a.get("wid",a.get("width",0.0)))+float(b.get("wid",b.get("width",0.0))))*0.5+0.025

static func _supported(stations: Array, item: Dictionary, cat: bool) -> bool:
	for dx in [-0.5,0.5]:
		for dy in [-0.5,0.5]:
			var x: float = float(item.x)+dx*float(item.len)
			var y: float = float(item.y)+dy*float(item.wid)
			if cat and x>=-1.80 and x<=1.45 and absf(y)<=0.62:continue
			if cat:y=absf(y)-0.62
			if absf(y)>_width(stations,x/0.94)*0.84:return false
	return true

static func _plan(spec: Dictionary) -> Dictionary:
	var key: String = "%s:%s:%d:%.3f"%[str(spec.get("id","")),str(spec.get("role","corvette")),int(spec.get("tier",1)),Layout.hull_size(spec)]
	if _plans.has(key):return _plans[key]
	var identity: Dictionary = Profiles.profile(spec)
	var stations: Array = identity.stations
	var sockets: Array = Layout.hardpoints(spec)
	var cat: bool = str(identity.archetype)=="catamaran"
	var civilian: bool = str(spec.get("civilianRole","")) in ["fishing","transport","tanker","yacht"]
	var structure: Dictionary = Layout.structure(spec)
	var items: Array = []
	for original in identity.deckAccents+identity.cargoDetails:
		if original.kind=="outboard_pair" or not _clear(sockets,original):continue
		if civilian:
			if not _supported(stations,original,cat) or _overlaps(original,structure.cabin) or _overlaps(original,structure.engine):continue
		var item: Dictionary = original.duplicate(true)
		item["closeOnly"]=original in identity.cargoDetails
		items.append(item)
	# These additions occupy actual free deck, including on an empty fitting.
	var additions: Array = [{"kind":"access_hatch","x":0.25,"y":0.0,"len":0.26,"wid":0.30,"h":11.0,"closeOnly":false}]
	var stern_x: float = float(stations[0].x)*0.94+0.18
	var stern_beam: float = _width(stations,stern_x/0.94)*0.84
	for side in [-1.0,1.0]:
		additions.append({"kind":"mooring_bitt","x":stern_x,"y":side*(0.62 if cat else stern_beam*0.65),"len":0.13,"wid":0.12,"h":12.3,"closeOnly":true})
	for item in additions:
		if civilian and item.kind=="access_hatch":
			for solid in items:
				if _overlaps(item,solid):
					item.x=0.64
					break
		if not _clear(sockets,item) or not _supported(stations,item,cat):continue
		var occupied: bool = false
		for solid in [structure.cabin,structure.engine]:
			if absf(float(item.x)-float(solid.x))<(float(item.len)+float(solid.length))*0.5+0.025 and absf(float(item.y)-float(solid.y))<(float(item.wid)+float(solid.width))*0.5+0.025:occupied=true
		if civilian:
			for solid in items:
				if _overlaps(item,solid):occupied=true
		if not occupied:items.append(item)
	var rails: Array = []
	for side in [-1.0,1.0]:
		for i in range(stations.size()-2):
			var a: Vector2 = stations[i]
			var b: Vector2 = stations[i+1]
			# Catamarans use their outer sheer; never a rail across the bridge deck.
			var offset: float = side*0.62 if cat else 0.0
			a=Vector2(a.x*0.94,offset+side*a.y*0.89)
			b=Vector2(b.x*0.94,offset+side*b.y*0.89)
			var footprint: Dictionary = {"x":(a.x+b.x)*0.5,"y":(a.y+b.y)*0.5,"len":absf(b.x-a.x)+0.025,"wid":absf(b.y-a.y)+0.025}
			if _clear(sockets,footprint):rails.append({"a":a,"b":b,"footprint":footprint})
	var plan: Dictionary = {"items":items,"rails":rails,"hullId":identity.hullId,"bridgeStyle":identity.bridgeStyle}
	if _plans.size()>=128:_plans.clear()
	_plans[key]=plan
	return plan

## Detached metadata for geometry QA. Only the drawing path shares cached plans.
static func layout(spec: Dictionary) -> Dictionary:
	return _plan(spec).duplicate(true)

static func planking(ctx: Dictionary, stations: Array, offset: float, lift: float, c: Dictionary) -> void:
	if int(ctx.lod)>=2:return
	var m: Dictionary = _model(ctx,Vector2(0,offset))
	var rows: int = 7 if int(ctx.lod)==0 else 3
	var max_beam: float = 0.0
	for station in stations:max_beam=maxf(max_beam,float(station.y)*0.84)
	for row in range(1,rows+1):
		var y: float = lerpf(-max_beam,max_beam,float(row)/float(rows+1))
		for i in range(stations.size()-1):
			var a: Vector2 = stations[i]*Vector2(0.94,0.84)
			var b: Vector2 = stations[i+1]*Vector2(0.94,0.84)
			if maxf(a.y,b.y)<=absf(y):continue
			var x0: float = a.x
			var x1: float = b.x
			if a.y<absf(y):x0=lerpf(a.x,b.x,(absf(y)-a.y)/(b.y-a.y))
			if b.y<absf(y):x1=lerpf(a.x,b.x,(absf(y)-a.y)/(b.y-a.y))
			_line(m,Vector3(x0,y,9.25+lift),Vector3(x1,y,9.25+lift),Color(c.deck_dark,0.55),0.5)
		if int(ctx.lod)==0:
			# Staggered butt joints, clipped to the inset deck instead of a square grid.
			for x in [-1.18+float(row%3)*0.22,0.35+float(row%3)*0.22]:
				var half_width: float = _width(stations,x/0.94)*0.84
				if absf(y)+0.045<half_width:_line(m,Vector3(x,y-0.04,9.3+lift),Vector3(x,y+0.04,9.3+lift),c.seam,0.55)

static func rails(ctx: Dictionary, spec: Dictionary, c: Dictionary) -> void:
	if int(ctx.lod)>=2:return
	var m: Dictionary = _model(ctx)
	for rail in _plan(spec).rails:
		var a: Vector2 = rail.a
		var b: Vector2 = rail.b
		_line(m,Vector3(a.x,a.y,13.2),Vector3(b.x,b.y,13.2),c.metal_light,0.8)
		if int(ctx.lod)==0:
			_line(m,Vector3(a.x,a.y,11.3),Vector3(b.x,b.y,11.3),Color(c.metal_light,0.65),0.45)
			_line(m,Vector3(a.x,a.y,9.4),Vector3(a.x,a.y,13.2),c.metal_light,0.8)
			_line(m,Vector3(b.x,b.y,9.4),Vector3(b.x,b.y,13.2),c.metal_light,0.8)

static func cabin(ctx: Dictionary, plan: Dictionary, identity: Dictionary, c: Dictionary) -> void:
	var m: Dictionary = _model(ctx,Vector2(plan.x,plan.y))
	var length: float = plan.length
	var width: float = plan.width
	var height: float = float(plan.get("height",identity.bridge.h))
	var base_height: float = float(plan.get("baseHeight",9.8))
	var style: String = str(identity.bridgeStyle)
	if str(plan.style)=="cockpit" and not bool(identity.bridge.glass):
		Shapes._box(m,Vector3(-length*0.5,-width*0.5,9.8),Vector3(length*0.5,width*0.5,11.5),c.cabin)
		_rect(m,0,0,length*0.84,width*0.78,11.6,c.glass_dark.darkened(0.2))
		Shapes._box(m,Vector3(-length*0.30,-width*0.30,11.6),Vector3(-length*0.12,width*0.30,13.0),c.cloth)
		var rake: float = 0.36 if "windscreen" in style else 0.25
		Shapes._face(m,[Vector3(length*0.48,-width*0.5,12),Vector3(length*0.48,width*0.5,12),Vector3(length*rake,width*0.44,height),Vector3(length*rake,-width*0.44,height)],c.glass if "windscreen" in style else c.plate)
		if int(ctx.lod)==0:
			_line(m,Vector3(length*rake,-width*0.44,height),Vector3(length*rake,width*0.44,height),c.metal_light)
			_line(m,Vector3(0.10,-0.08,14.0),Vector3(0.10,0.08,14.0),c.brass,1.1)
		return
	# The pilothouse is a raked solid inside the unchanged cabin footprint.
	var swept: bool = "canopy" in style or "hood" in style or "interceptor" in style
	var front: float = length*(0.28 if swept else 0.40)
	var bottom: Array = [Vector3(-length*0.5,-width*0.5,base_height),Vector3(length*0.5,-width*0.5,base_height),Vector3(length*0.5,width*0.5,base_height),Vector3(-length*0.5,width*0.5,base_height)]
	var top: Array = [Vector3(-length*0.44,-width*0.44,height-2.0),Vector3(front,-width*0.42,height-2.0),Vector3(front,width*0.42,height-2.0),Vector3(-length*0.44,width*0.44,height-2.0)]
	var faces: Array = []
	for i in range(4):faces.append([bottom[i],bottom[(i+1)%4],top[(i+1)%4],top[i]])
	faces.sort_custom(func(a,b):return (Shapes._p(m,a[0])+Shapes._p(m,a[1])).y<(Shapes._p(m,b[0])+Shapes._p(m,b[1])).y)
	for i in range(2,4):
		var face: Array = faces[i]
		Shapes._face(m,face,c.cabin.darkened(0.22 if i==2 else 0.10))
		if int(ctx.lod)>=2:continue
		var low: float = 0.50 if bool(identity.bridge.glass) else 0.75
		var high: float = 0.88 if bool(identity.bridge.glass) else 0.85
		var left: Vector3 = face[0].lerp(face[3],low)
		var right: Vector3 = face[1].lerp(face[2],low)
		var upper_left: Vector3 = face[0].lerp(face[3],high)
		var upper_right: Vector3 = face[1].lerp(face[2],high)
		Shapes._face(m,[left.lerp(right,0.12),left.lerp(right,0.88),upper_left.lerp(upper_right,0.88),upper_left.lerp(upper_right,0.12)],c.glass if bool(identity.bridge.glass) else c.glass_dark)
		if int(ctx.lod)==0:
			for t in [0.36,0.65]:_line(m,left.lerp(right,t),upper_left.lerp(upper_right,t),c.metal,0.6)
			_line(m,upper_left.lerp(upper_right,0.12),upper_left.lerp(upper_right,0.88),c.roof,0.7)
	Shapes._face(m,top,c.roof)
	if int(ctx.lod)>=2:return
	var roof_h: float = height-1.8
	# Roof furniture follows each original bridge design, with no weapon-like tubes.
	if "gantry" in style or "span" in style or "packet" in style:
		Shapes._box(m,Vector3(-length*0.25,-width*0.43,roof_h),Vector3(length*0.08,width*0.43,height+1.8),c.plate)
	elif "rangefinder" in style:
		Shapes._box(m,Vector3(-length*0.15,-width*0.35,roof_h),Vector3(length*0.05,width*0.35,height+2.0),c.metal)
		_rect(m,-length*0.05,0,length*0.15,width*0.50,height+2.1,c.glass_dark)
	elif "citadel" in style or "cupola" in style or "bunker" in style:
		Shapes._box(m,Vector3(-length*0.31,-width*0.29,roof_h),Vector3(length*0.04,width*0.29,height+2.0),c.plate)
	elif swept:
		Shapes._face(m,[Vector3(-length*0.42,-width*0.26,roof_h),Vector3(front,width*0.0,roof_h),Vector3(-length*0.42,width*0.26,roof_h),Vector3(-length*0.40,0,height+1.2)],c.plate)
	else:
		_rect(m,-length*0.15,0,length*0.32,width*0.47,roof_h,c.deck_dark)
		_line(m,Vector3(-length*0.30,0,roof_h+0.1),Vector3(0.0,0,roof_h+0.1),c.brass)
	if int(ctx.lod)==0:
		# Door/ladder on the aft wall; rungs remain inside the canonical cabin box.
		for step in range(3):
			var z: float = base_height+1.2+float(step)*2.0
			if z<height-3.0:_line(m,Vector3(-length*0.49,-width*0.13,z),Vector3(-length*0.49,width*0.13,z),c.metal_light,0.65)

static func draw_items(ctx: Dictionary, spec: Dictionary, c: Dictionary) -> void:
	if int(ctx.lod)>=2:return
	var items: Array = _plan(spec).items.duplicate()
	items.sort_custom(func(a,b):return Shapes._p(_model(ctx,Vector2(a.x,a.y)),Vector3.ZERO).y<Shapes._p(_model(ctx,Vector2(b.x,b.y)),Vector3.ZERO).y)
	for item in items:
		if int(ctx.lod)>0 and bool(item.closeOnly):continue
		_item(ctx,item,c)

static func _item(ctx: Dictionary, item: Dictionary, c: Dictionary) -> void:
	var m: Dictionary = _model(ctx,Vector2(item.x,item.y))
	var kind: String = str(item.kind)
	var l: float = item.len
	var w: float = item.wid
	var z: float = maxf(9.8,float(item.h))
	if kind=="merchant_mast":
		Shapes._box(m,Vector3(-l*0.42,-w*0.42,9.4),Vector3(l*0.42,w*0.42,11.0),c.deck_dark)
		_line(m,Vector3(0,0,10.0),Vector3(0,0,z),c.brass,1.4)
		_line(m,Vector3(-l*0.45,0,z-3.0),Vector3(l*0.45,0,z-3.0),c.metal_light,1.0)
		_line(m,Vector3(-l*0.4,0,10.0),Vector3(0,0,z-1.0),c.metal_light,0.5)
		return
	if kind in ["net_tarp_stack","packet_tarp_stack","bale_tarp_stack"]:
		Shapes._box(m,Vector3(-l*0.5,-w*0.5,9.4),Vector3(l*0.5,w*0.5,z-0.8),c.deck_dark)
		Shapes._face(m,[Vector3(-l*0.5,-w*0.5,z-0.8),Vector3(l*0.5,-w*0.5,z-0.8),Vector3(l*0.5,0,z),Vector3(-l*0.5,0,z)],c.cloth)
		Shapes._face(m,[Vector3(-l*0.5,0,z),Vector3(l*0.5,0,z),Vector3(l*0.5,w*0.5,z-0.8),Vector3(-l*0.5,w*0.5,z-0.8)],c.cloth.lightened(0.15))
		for x in [-l*0.25,l*0.25]:
			_line(m,Vector3(x,-w*0.5,z-0.6),Vector3(x,0,z+0.1),c.brass,0.7)
			_line(m,Vector3(x,0,z+0.1),Vector3(x,w*0.5,z-0.6),c.brass,0.7)
		return
	if kind in ["oil_cask","cargo_drum"]:
		var top: Array = []
		var faces: Array = []
		for i in range(8):top.append(Vector3(cos(i*TAU/8.0)*l*0.48,sin(i*TAU/8.0)*w*0.48,z))
		for i in range(8):
			var a: Vector3 = top[i]
			var b: Vector3 = top[(i+1)%8]
			faces.append([Vector3(a.x,a.y,9.4),Vector3(b.x,b.y,9.4),b,a])
		faces.sort_custom(func(a,b):return (Shapes._p(m,a[0])+Shapes._p(m,a[1])).y<(Shapes._p(m,b[0])+Shapes._p(m,b[1])).y)
		for i in range(4,8):Shapes._face(m,faces[i],c.metal.darkened(0.12*float(i%2)))
		Shapes._face(m,top,c.plate)
		_rect(m,0,0,l*0.28,w*0.25,z+0.1,c.brass)
		if int(ctx.lod)==0:
			for height in [10.2,z-0.8]:
				for i in range(8):
					var a: Vector3 = top[i]
					var b: Vector3 = top[(i+1)%8]
					_line(m,Vector3(a.x,a.y,height),Vector3(b.x,b.y,height),c.brass,0.65)
		return
	if "searchlight" in kind:
		Shapes._box(m,Vector3(-l*0.28,-w*0.28,9.4),Vector3(l*0.28,w*0.28,z-1.5),c.metal)
		Shapes._box(m,Vector3(-l*0.42,-w*0.45,z-2.0),Vector3(l*0.28,w*0.45,z),c.plate)
		Shapes._face(m,[Vector3(l*0.29,-w*0.35,z-1.8),Vector3(l*0.29,w*0.35,z-1.8),Vector3(l*0.29,w*0.35,z-0.3),Vector3(l*0.29,-w*0.35,z-0.3)],c.ring)
		return
	if "davit" in kind or "hoist" in kind:
		Shapes._box(m,Vector3(-l*0.46,-w*0.40,9.4),Vector3(-l*0.15,w*0.40,z),c.metal)
		_line(m,Vector3(-l*0.30,0,z),Vector3(l*0.45,0,z),c.brass,1.3)
		_line(m,Vector3(-l*0.30,0,10.0),Vector3(l*0.45,0,z),c.metal_light,0.85)
		_line(m,Vector3(l*0.45,0,z),Vector3(l*0.45,0,10.0),c.metal_light,0.65)
		return
	if "sawtooth" in kind:
		for tooth in range(3):
			var x: float = -l*0.5+float(tooth)*l/3.0
			Shapes._face(m,[Vector3(x,-w*0.5,9.4),Vector3(x+l/3.0,0,z),Vector3(x,w*0.5,9.4)],c.plate)
		return
	if "rope" in kind or "reel" in kind:
		# A restrained oval hawser coil, or a bolted working winch with cheek plates.
		if "reel" in kind:
			Shapes._box(m,Vector3(-l*0.45,-w*0.42,9.4),Vector3(l*0.45,w*0.42,z),c.metal)
		var coil: Array = []
		for i in range(9):coil.append(Vector3(cos(i*TAU/8.0)*l*0.38,sin(i*TAU/8.0)*w*0.38,z+0.2))
		for i in range(8):_line(m,coil[i],coil[i+1],c.brass,0.8)
		return
	if "fender" in kind or "prow" in kind or "crest" in kind or "glacis" in kind or "vane" in kind or "sprit" in kind or "blade" in kind:
		Shapes._face(m,[Vector3(-l*0.5,-w*0.5,9.4),Vector3(l*0.5,0,z),Vector3(-l*0.5,w*0.5,9.4),Vector3(-l*0.3,0,z+0.8)],c.plate)
		_line(m,Vector3(-l*0.3,0,z+0.8),Vector3(l*0.5,0,z),c.metal_light,0.9)
		return
	Shapes._box(m,Vector3(-l*0.5,-w*0.5,9.4),Vector3(l*0.5,w*0.5,z),c.metal if "bitt" in kind or "manifold" in kind else c.deck_dark)
	if kind=="mooring_bitt":
		_line(m,Vector3(0,-w*0.48,z),Vector3(0,w*0.48,z),c.metal_light,1.3)
	elif "drum" in kind or "cask" in kind or "bottle" in kind or "canister" in kind:
		for x in [-l*0.27,l*0.27]:_line(m,Vector3(x,-w*0.5,z+0.1),Vector3(x,w*0.5,z+0.1),c.brass,0.75)
	elif "manifold" in kind or "ejector" in kind or "scoop" in kind or "pump" in kind:
		for i in range(3):
			var x: float = l*(-0.30+float(i)*0.30)
			_line(m,Vector3(x,-w*0.37,z+0.1),Vector3(x,w*0.37,z+0.1),c.metal_light,0.85)
	else:
		_rect(m,0,0,l*0.80,w*0.73,z+0.1,c.plate if "plate" in kind or "belt" in kind else c.deck)
		if int(ctx.lod)==0:
			_line(m,Vector3(-l*0.26,0,z+0.2),Vector3(l*0.26,0,z+0.2),c.seam,0.6)
			_line(m,Vector3(-l*0.24,-w*0.30,z+0.3),Vector3(-l*0.24,w*0.30,z+0.3),c.brass,0.8)
