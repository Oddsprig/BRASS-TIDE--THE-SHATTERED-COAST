extends RefCounted
## Fitted equipment drawn in physical units. Hull size never stretches a gun.
## Every shaded face is culled below half a screen pixel, including end-on tubes.

const Geometry=preload("res://scripts/weapon_geometry.gd")
const RECOIL_SECONDS: float=0.16
const RECOIL_DISTANCE: float=1.1

## Canonical model units, from this mount's actual battle shot timestamp.
## Both the authored layer and mechanical fallback use the same recovery.
static func recoil_offset(ctx: Dictionary, mount: Dictionary) -> float:
	var id: String=str(mount.get("id",""))
	var shots: Dictionary=ctx.get("shots",{})
	if not shots.has(id):return 0.0
	var age: float=float(ctx.get("shot_clock",0.0))-float(shots[id])
	if age<0.0 or age>=RECOIL_SECONDS:return 0.0
	return -RECOIL_DISTANCE*(1.0-age/RECOIL_SECONDS)

static func draw(ctx: Dictionary, mount: Dictionary, world_bearing: float, palette: Dictionary) -> void:
	var kind: String = str(mount.kind)
	var tier: int = clampi(int(mount.get("size", 1)), 1, 3)
	var world_unit: float=Geometry.unit(float(ctx.get("hull_size",ctx.size)),tier)
	var unit: float = world_unit*float(ctx.get("enlargement",1.0)) / float(ctx.size)
	var bearing: float = world_bearing - float(ctx.angle)
	var model := {"ctx":ctx, "at":Vector2(mount.x,mount.y), "bearing":bearing,
		"u":unit, "world_unit":world_unit, "lod":int(ctx.lod), "h":9.7}
	var dark := Color("1e2c31")
	var steel := Color("52656b")
	var recoil: float = recoil_offset(ctx,mount)
	# A bolt-down octagonal deck plate, bearing race and pedestal: no black discs.
	_pad(model,2.1 if kind=="gun" else 3.0,0.25,dark)
	_box(model,Vector3(-1.1,-1.0,0.3),Vector3(1.1,1.0,2.2),steel)
	match kind:
		"gun":_machine_gun(model,mount,tier,recoil,palette)
		"cannon":_cannon(model,recoil,palette)
		"rocket":_rocket(model,mount,tier,palette)
		"torpedo":_torpedo(model,tier,palette)
	draw_attached_detail(ctx,mount,world_bearing,palette)

## The authored atlas and procedural fallback share these attached highlights.
## Preserve the fitted socket, real module scale, recoil and muzzle envelope.
## Only close LOD0 boats receive this pass; no per-boat nodes or textures.
static func draw_attached_detail(ctx: Dictionary,mount: Dictionary,world_bearing: float,c: Dictionary) -> void:
	if int(ctx.lod)!=0:return
	var kind: String=str(mount.kind)
	var tier: int=clampi(int(mount.get("size",1)),1,3)
	var physical: float=Geometry.unit(float(ctx.get("hull_size",ctx.size)),tier)
	var model: Dictionary={"ctx":ctx,"at":Vector2(mount.x,mount.y),"bearing":world_bearing-float(ctx.angle),
		"u":physical*float(ctx.get("enlargement",1.0))/float(ctx.size),"world_unit":physical,"lod":int(ctx.lod),"h":9.7}
	var recoil: float=recoil_offset(ctx,mount)
	var edge:=Color("c2d0ca")
	var steel:=Color("5d747b")
	var dark:=Color("223238")
	var front_visible: bool=Vector2.from_angle(world_bearing).dot(Vector2(1,1))>0.0
	match kind:
		"gun":
			var twin: bool=tier>1 or "twin" in str(mount.get("moduleId",""))
			for y in [-0.5,0.5] if twin else [0.0]:
				# A tapered receiver top and jacket edge read as a mechanism,
				# with each channel ending at the original physical muzzle.
				_face(model,[Vector3(-2.4+recoil,y-0.33,5.32),Vector3(1.75+recoil,y-0.33,5.32),Vector3(1.25+recoil,y+0.33,5.32),Vector3(-2.4+recoil,y+0.33,5.32)],steel)
				_line(model,Vector3(1.4+recoil,y-0.28,5.04),Vector3(8.65+recoil,y-0.28,5.04),edge,0.8)
				if int(ctx.lod)==0:
					if front_visible:_line(model,Vector3(8.79+recoil,y-0.34,4.8),Vector3(8.79+recoil,y+0.34,4.8),dark,1.0)
					_line(model,Vector3(-1.9+recoil,y,5.38),Vector3(0.8+recoil,y,5.38),dark,0.65)
			if int(ctx.lod)==0:
				_box(model,Vector3(-2.7,-1.75,3.3),Vector3(-0.3,-1.0,5.05),c.brass.darkened(0.30))
				_line(model,Vector3(-1.7,-1.0,5.4),Vector3(-0.8,-0.4,5.5),edge,0.9)
		"cannon":
			# Fixed trunnion cheeks support the moving barrel and breech.
			for side in [-1.0,1.0]:
				if Vector2(0,side).rotated(world_bearing).dot(Vector2(1,1))<=0.0:continue
				_face(model,[Vector3(-2.6,side*1.8,2.3),Vector3(1.9,side*1.8,2.3),Vector3(1.0,side*1.8,5.4),Vector3(-1.6,side*1.8,5.4)],c.plate if side>0.0 else c.plate.darkened(0.2))
			_line(model,Vector3(4.25+recoil,-0.35,6.42),Vector3(12.2+recoil,-0.35,6.42),edge,0.9)
			if int(ctx.lod)==0:
				_line(model,Vector3(-2.4+recoil,-1.26,6.72),Vector3(2.3+recoil,-1.26,6.72),edge,0.7)
				if front_visible:_line(model,Vector3(14.19+recoil,-0.75,5.8),Vector3(14.19+recoil,0.75,5.8),dark,1.1)
				_line(model,Vector3(-2.5+recoil,0.85,6.3),Vector3(-3.1+recoil,1.55,6.6),c.brass,0.9)
		"rocket":
			var rows: int=2 if tier>=3 or "salvo" in str(mount.get("moduleId","")) else 1
			for row in range(rows):
				var z: float=6.0+float(row)*1.85
				for y in [-1.8,0.0,1.8]:
					_tube(model,Vector3(-4.8,y,4.5+float(row)*1.85),Vector3(5.9,y,z),0.75,Color("cc8a45"),Color("e0d4ad"))
					_face(model,[Vector3(-3.0,y-0.46,z+0.55),Vector3(4.8,y-0.46,z+0.55),Vector3(4.8,y+0.46,z+0.55),Vector3(-3.0,y+0.46,z+0.55)],Color("c49a68"))
				# Visible collars stay on the actual three/six launch cells.
				for y in [-1.8,0.0,1.8]:
					_line(model,Vector3(5.89,y-0.50,z+0.54),Vector3(5.89,y+0.50,z+0.54),edge,0.85)
				if int(ctx.lod)==0:
					for y in [-1.8,0.0,1.8]:
						if front_visible:_line(model,Vector3(5.9,y-0.48,z),Vector3(5.9,y+0.48,z),dark,1.0)
			if int(ctx.lod)==0:
				_line(model,Vector3(-3.4,-2.6,2.9),Vector3(-3.4,-2.6,5.1),c.brass,0.85)
		"torpedo":
			for y in [-1.5,1.5] if tier>1 else [0.0]:
				_tube(model,Vector3(-7.1,y,2.8),Vector3(7.6,y,2.8),1.16,Color("74b6bb"),Color("c2d0ca"))
				_tube(model,Vector3(6.5,y,2.8),Vector3(7.9,y,2.8),1.35,Color("35858b"),Color("c2d0ca"))
				_face(model,[Vector3(-6.5,y-0.72,3.82),Vector3(6.0,y-0.72,3.82),Vector3(6.0,y+0.72,3.82),Vector3(-6.5,y+0.72,3.82)],Color("9ed3d4"))
				_line(model,Vector3(-6.8,y-0.5,3.86),Vector3(6.2,y-0.5,3.86),edge,0.8)
				if int(ctx.lod)==0:
					for x in [-3.0,3.0]:
						_line(model,Vector3(x,y-1.05,3.45),Vector3(x,y+1.05,3.45),c.brass,1.0)
					if not front_visible:_line(model,Vector3(-7.2,y-0.8,2.8),Vector3(-7.2,y+0.8,2.8),dark,1.0)

static func _machine_gun(m: Dictionary, mount: Dictionary, tier: int, recoil: float, c: Dictionary) -> void:
	var steel := Color("647a82")
	var dark := Color("1e2c31")
	var edge := Color("cad8d2")
	var twin: bool = "twin" in str(mount.get("moduleId","")) or tier>1
	_box(m,Vector3(-1.3,-1.05,2.2),Vector3(0.7,1.05,4.0),c.top)
	# Separate receiver channels and jacketed barrels on the same real mount.
	for y in [-0.5,0.5] if twin else [0.0]:
		_box(m,Vector3(-2.5,y-0.36,3.9),Vector3(1.8,y+0.36,5.3),steel)
		_tube(m,Vector3(1.0+recoil,y,4.8),Vector3(8.8+recoil,y,4.8),0.39,steel,edge)
		if int(m.lod)==0:
			for x in [3.2,4.6,6.0]:
				_line(m,Vector3(x,y-0.30,5.08),Vector3(x+0.45,y-0.30,5.08),dark,0.85)
		if int(m.lod)<2:
			_line(m,Vector3(-2.1,y,5.4),Vector3(1.2,y,5.4),edge,0.8)
	_box(m,Vector3(-2.8,-1.8,3.2),Vector3(-0.2,-0.95,5.0),Color("7c7852"))
	_box(m,Vector3(-2.1,0.95,3.5),Vector3(-0.6,1.6,4.5),dark)
	_box(m,Vector3(-0.8,-2.0,2.9),Vector3(0.0,2.0,4.1),c.top)
	if int(m.lod)<2:
		# Lid, feed bridge and linked cartridges are attached hardware, not particles.
		_line(m,Vector3(-2.6,-1.7,5.1),Vector3(-0.4,-1.7,5.1),edge,0.7)
		_line(m,Vector3(-1.7,-1.0,5.3),Vector3(-0.8,-0.4,5.5),c.brass,1.3)
		_box(m,Vector3(-3.7,-0.8,3.1),Vector3(-2.6,0.8,3.8),dark)
	if int(m.lod)==0:
		for x in [-1.7,-1.4,-1.1]:_line(m,Vector3(x,-1.0,5.4),Vector3(x+0.22,-0.65,5.5),c.brass,0.9)
		_line(m,Vector3(-1.8,0.95,4.7),Vector3(-2.2,1.55,4.7),edge,0.9)
		_line(m,Vector3(0.7,0,5.5),Vector3(0.7,0,6.2),dark,0.9)

static func _cannon(m: Dictionary, recoil: float, c: Dictionary) -> void:
	var steel := Color("52656b")
	var dark := Color("1e2c31")
	var edge := Color("a3b4ae")
	# Cradle/slide stays fixed; the breech, chamber and barrel recoil together.
	_box(m,Vector3(-3.4,-2.1,2.0),Vector3(2.4,2.1,4.1),c.top)
	_box(m,Vector3(-2.5+recoil,-1.25,4.2),Vector3(2.5+recoil,1.25,6.7),steel)
	_box(m,Vector3(-3.1+recoil,-0.8,4.5),Vector3(-2.5+recoil,0.8,6.2),dark)
	_tube(m,Vector3(1.8+recoil,0,5.8),Vector3(13.8+recoil,0,5.8),0.72,steel,edge)
	_tube(m,Vector3(1.8+recoil,0,5.8),Vector3(4.2+recoil,0,5.8),1.02,dark,steel,false)
	_tube(m,Vector3(12.3+recoil,0,5.8),Vector3(14.2+recoil,0,5.8),0.96,steel,edge)
	if int(m.lod)<2:
		for y in [-1.5,1.5]:
			_tube(m,Vector3(-0.8,y,5.7),Vector3(4.0,y,5.7),0.42,Color("87938d"),edge,false)
			_tube(m,Vector3(3.7+recoil,y,5.7),Vector3(5.4+recoil,y,5.7),0.22,edge,edge,false)
		_box(m,Vector3(0.8,-2.4,3.8),Vector3(1.6,2.4,5.1),c.plate)
		_line(m,Vector3(-1.8+recoil,-1.3,6.8),Vector3(0.6+recoil,-1.3,6.8),c.brass,1.0)
	if int(m.lod)==0:
		# Interrupted breech seam, operating lever, loading tray and elevation screw.
		_line(m,Vector3(-2.45+recoil,-1.26,4.5),Vector3(-2.45+recoil,-1.26,6.6),dark,1.1)
		_line(m,Vector3(-2.7+recoil,0.82,6.0),Vector3(-3.2+recoil,1.65,6.6),c.brass,1.0)
		_box(m,Vector3(-3.4,-0.7,4.0),Vector3(-2.0,0.7,4.3),c.metal)
		_line(m,Vector3(-0.4,1.8,2.5),Vector3(1.0,1.8,4.1),edge,1.0)

static func _rocket(m: Dictionary, mount: Dictionary, tier: int, c: Dictionary) -> void:
	var steel := Color("52656b")
	var edge := Color("a3b4ae")
	var rows: int = 2 if tier>=3 or "salvo" in str(mount.get("moduleId","")) else 1
	_box(m,Vector3(-3.4,-2.8,1.7),Vector3(2.0,2.8,2.8),c.top)
	_box(m,Vector3(-2.8,-3.0,2.8),Vector3(-1.7,3.0,3.8),c.brass.darkened(0.3))
	# Cell count and front X are stable across all LODs. Upper rows share the
	# canonical muzzle station; the lower centre cell defines the firing plane.
	for row in range(rows):
		var rise: float = float(row)*1.85
		for y in [-1.8,0.0,1.8]:
			_tube(m,Vector3(-4.8,y,4.5+rise),Vector3(5.9,y,6.0+rise),0.75,steel if row==0 else c.top,edge)
		if int(m.lod)<2:
			_box(m,Vector3(-2.3,-2.8,3.9+rise),Vector3(-1.8,2.8,4.6+rise),c.metal)
	if int(m.lod)==0:
		_line(m,Vector3(-4.9,-2.5,4.3),Vector3(-3.1,-2.5,3.2),c.brass,1.1)
		_line(m,Vector3(-3.1,-2.5,3.2),Vector3(-1.9,-2.5,3.2),c.brass,1.1)
		for y in [-1.8,0.0,1.8]:
			_line(m,Vector3(-4.7,y-0.5,4.7),Vector3(-4.7,y+0.5,4.7),c.brass,0.8)

static func _torpedo(m: Dictionary, tier: int, c: Dictionary) -> void:
	var steel := Color("52656b")
	var edge := Color("a3b4ae")
	for y in [-1.5,1.5] if tier>1 else [0.0]:
		for x in [-3.0,3.0]:_box(m,Vector3(x-0.5,y-1.4,0.2),Vector3(x+0.5,y+1.4,1.6),c.top)
		_tube(m,Vector3(-7.1,y,2.8),Vector3(7.6,y,2.8),1.16,Color("6c7e76"),edge)
		_tube(m,Vector3(6.5,y,2.8),Vector3(7.9,y,2.8),1.35,steel,c.brass)
		if int(m.lod)<2:
			_line(m,Vector3(-4.0,y,4.0),Vector3(5.0,y,4.0),edge,0.8)
			_box(m,Vector3(-1.4,y-0.4,3.9),Vector3(0.2,y+0.4,4.6),c.brass.darkened(0.2))
		if int(m.lod)==0:
			# Closed rear breech, retaining straps, hinge and compressed-air pipe.
			_tube(m,Vector3(-7.3,y,2.8),Vector3(-6.8,y,2.8),1.21,steel,steel,false)
			for x in [-3.0,3.0]:_line(m,Vector3(x,y-1.05,3.4),Vector3(x,y+1.05,3.4),c.brass,1.0)
			_line(m,Vector3(-5.8,y+0.8,3.8),Vector3(-0.5,y+0.8,4.1),c.brass,0.8)
			_line(m,Vector3(6.7,y-1.0,3.6),Vector3(7.2,y-1.0,3.6),edge,1.0)

static func _p(m: Dictionary, p: Vector3) -> Vector2:
	var ctx: Dictionary=m.ctx
	var local: Vector2=m.at+Vector2(p.x,p.y).rotated(m.bearing)*float(m.u)
	var world: Vector2=ctx.pos+local.rotated(ctx.angle)*float(ctx.size)
	return ctx.proj.call(world,float(m.h)+p.z*float(m.world_unit))

static func _face(m: Dictionary, vertices: Array, color: Color) -> void:
	var p:=PackedVector2Array()
	for vertex in vertices: p.append(_p(m,vertex))
	for i in range(1,p.size()-1):
		if absf((p[i]-p[0]).cross(p[i+1]-p[0]))<1.0: continue
		m.ctx.canvas.draw_colored_polygon(PackedVector2Array([p[0],p[i],p[i+1]]),color)
		m.ctx.n+=1; m.ctx.npoly+=1

static func _line(m: Dictionary,a: Vector3,b: Vector3,c: Color,width: float) -> void:
	m.ctx.canvas.draw_line(_p(m,a),_p(m,b),c,maxf(0.65,width*float(m.ctx.px)/float(m.ctx.size)))
	m.ctx.n+=1; m.ctx.nline+=1

static func _box(m: Dictionary,a: Vector3,b: Vector3,c: Color) -> void:
	var faces: Array=[
		[Vector3(a.x,a.y,a.z),Vector3(b.x,a.y,a.z),Vector3(b.x,a.y,b.z),Vector3(a.x,a.y,b.z)],
		[Vector3(b.x,a.y,a.z),Vector3(b.x,b.y,a.z),Vector3(b.x,b.y,b.z),Vector3(b.x,a.y,b.z)],
		[Vector3(b.x,b.y,a.z),Vector3(a.x,b.y,a.z),Vector3(a.x,b.y,b.z),Vector3(b.x,b.y,b.z)],
		[Vector3(a.x,b.y,a.z),Vector3(a.x,a.y,a.z),Vector3(a.x,a.y,b.z),Vector3(a.x,b.y,b.z)]]
	faces.sort_custom(func(x,y):return (_p(m,x[0])+_p(m,x[1])).y<(_p(m,y[0])+_p(m,y[1])).y)
	# Paint the nearest two vertical faces, then the top.
	for i in range(2,4): _face(m,faces[i],c.darkened(0.34 if i==2 else 0.18))
	_face(m,[Vector3(a.x,a.y,b.z),Vector3(b.x,a.y,b.z),Vector3(b.x,b.y,b.z),Vector3(a.x,b.y,b.z)],c)

static func _pad(m: Dictionary,r: float,h: float,c: Color) -> void:
	var rim: Array=[]
	for i in range(8): rim.append(Vector3(cos(i*TAU/8)*r,sin(i*TAU/8)*r,h))
	_face(m,rim,c)
	if m.lod==0:
		for i in range(4):
			var at:=Vector3(cos(i*TAU/4)*r*0.75,sin(i*TAU/4)*r*0.75,h+0.1)
			_line(m,at-Vector3(0.18,0,0),at+Vector3(0.18,0,0),Color("a39d7b"),1.1)

static func _tube(m: Dictionary,a: Vector3,b: Vector3,r: float,body: Color,rim: Color,open_end: bool=true) -> void:
	var count: int=6 if m.lod<2 else 4
	var back: Array=[]; var front: Array=[]
	for i in range(count):
		var off:=Vector3(0,cos(i*TAU/count)*r,sin(i*TAU/count)*r)
		back.append(a+off); front.append(b+off)
	var faces: Array=[]
	for i in range(count):
		var next: int=(i+1)%count
		faces.append([back[i],front[i],front[next],back[next]])
	faces.sort_custom(func(x,y):return (_p(m,x[0])+_p(m,x[1])).y<(_p(m,y[0])+_p(m,y[1])).y)
	for i in range(count): _face(m,faces[i],body.lightened(0.09*float(i)/count).darkened(0.3 if i<count/2 else 0.0))
	_face(m,front,rim)
	if not open_end:return
	var bore: Array=[]
	for point in front: bore.append(b+(point-b)*0.62+Vector3(0.01,0,0))
	_face(m,bore,Color("131e23"))
