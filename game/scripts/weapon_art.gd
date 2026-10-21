extends RefCounted
## Fitted equipment drawn in physical units. Hull size never stretches a gun.
## Every shaded face is culled below half a screen pixel, including end-on tubes.

const Geometry=preload("res://scripts/weapon_geometry.gd")

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
	var edge := Color("a3b4ae")
	var bronze: Color = palette.brass
	var age: float = float(ctx.get("clock",0.0))-float(ctx.get("shots",{}).get(str(mount.get("id","")),-100.0))
	var recoil: float = -1.1 * maxf(0.0,1.0-age/0.16) if age>=0.0 else 0.0
	# A bolt-down octagonal deck plate, bearing race and pedestal: no black discs.
	_pad(model,2.1 if kind=="gun" else 3.0,0.25,dark)
	_box(model,Vector3(-1.1,-1.0,0.3),Vector3(1.1,1.0,2.2),steel)
	match kind:
		"gun":
			_box(model,Vector3(-2.5,-0.9,3.8),Vector3(1.8,0.9,5.3),steel)
			_box(model,Vector3(-2.8,-1.8,3.5),Vector3(-0.2,-0.95,5.0),Color("7c7852"))
			_box(model,Vector3(-2.1,0.95,3.8),Vector3(-0.6,1.6,4.8),dark)
			var twin: bool = "twin" in str(mount.get("moduleId","")) or tier>1
			for s in [-0.5,0.5] if twin else [0.0]:
				_tube(model,Vector3(1.0+recoil,s,4.8),Vector3(8.8+recoil,s,4.8),0.39,steel,edge)
				if model.lod==0:
					for x in [3.2,4.6,6.0]: _box(model,Vector3(x-0.2,s-0.46,4.45),Vector3(x+0.2,s+0.46,5.2),dark)
			_box(model,Vector3(-0.8,-2.0,2.9),Vector3(0.0,2.0,4.1),palette.top)
			if model.lod==0:
				_line(model,Vector3(-2.5,-1.0,5.4),Vector3(-0.6,-1.0,5.4),bronze,0.8)
				_box(model,Vector3(-3.7,-0.8,3.1),Vector3(-2.6,0.8,3.8),dark)
		"cannon":
			# Armored angular shield, independent breech block, trunnions and recoil slide.
			_box(model,Vector3(-3.4,-2.1,2.0),Vector3(2.4,2.1,4.1),palette.top)
			_box(model,Vector3(-2.5+recoil,-1.25,4.2),Vector3(2.5+recoil,1.25,6.7),steel)
			_box(model,Vector3(-3.1+recoil,-0.8,4.5),Vector3(-2.5+recoil,0.8,6.2),dark)
			_tube(model,Vector3(1.8+recoil,0,5.8),Vector3(13.8+recoil,0,5.8),0.72,steel,edge)
			_tube(model,Vector3(1.8+recoil,0,5.8),Vector3(4.2+recoil,0,5.8),1.02,dark,steel)
			_tube(model,Vector3(12.3+recoil,0,5.8),Vector3(14.2+recoil,0,5.8),0.96,steel,edge)
			if model.lod<2:
				for y in [-1.5,1.5]:
					_tube(model,Vector3(-0.8,y,5.7),Vector3(5.4,y,5.7),0.42,Color("87938d"),edge)
				_box(model,Vector3(0.8,-2.4,3.8),Vector3(1.6,2.4,5.1),palette.plate)
				_line(model,Vector3(-1.8,-1.3,6.8),Vector3(0.6,-1.3,6.8),bronze,1.0)
		"rocket":
			_box(model,Vector3(-3.4,-2.8,1.7),Vector3(2.0,2.8,2.8),palette.top)
			for y in [-2.0,0.0,2.0] if model.lod<2 else [-1.2,1.2]:
				_tube(model,Vector3(-4.8,y,4.5),Vector3(5.9,y,6.0),0.85,steel,edge)
				if model.lod==0:
					_tube(model,Vector3(-3.8,y,6.4),Vector3(5.0,y,7.6),0.75,palette.top,edge)
			_box(model,Vector3(-2.8,-3.0,2.8),Vector3(-1.7,3.0,3.8),bronze.darkened(0.3))
		"torpedo":
			for y in [-1.5,1.5] if tier>1 else [0.0]:
				for x in [-3.0,3.0]: _box(model,Vector3(x-0.5,y-1.4,0.2),Vector3(x+0.5,y+1.4,1.6),palette.top)
				_tube(model,Vector3(-7.1,y,2.8),Vector3(7.6,y,2.8),1.16,Color("6c7e76"),edge)
				_tube(model,Vector3(6.5,y,2.8),Vector3(7.9,y,2.8),1.35,steel,bronze)
				if model.lod<2:
					_line(model,Vector3(-4.0,y,4.0),Vector3(5.0,y,4.0),edge,0.8)
					_box(model,Vector3(-1.4,y-0.4,3.9),Vector3(0.2,y+0.4,4.6),bronze.darkened(0.2))

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

static func _tube(m: Dictionary,a: Vector3,b: Vector3,r: float,body: Color,rim: Color) -> void:
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
	var bore: Array=[]
	for point in front: bore.append(b+(point-b)*0.62+Vector3(0.01,0,0))
	_face(m,bore,Color("131e23"))
