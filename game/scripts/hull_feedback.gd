extends RefCounted
## Bounded cosmetic hit records. No random draws, numerical damage or economy changes.
const Profiles=preload("res://scripts/hull_profiles.gd")
const Faces=preload("res://scripts/weapon_art.gd")
const Layout=preload("res://scripts/mount_layout.gd")
const MAX_SCARS: int=8
const MAX_EQUIPMENT_MARKS: int=6

static func equipment_marks(boat: Dictionary,mounts: Array) -> Array:
	# Live presentation reads the already validated installed records, never locker
	# parts or a second full damage status. No cached condition/repair state.
	var marks: Array=[]
	var condition=boat.get("moduleCondition")
	if bool(boat.get("sunk",false)) or not condition is Dictionary:return marks
	if condition.get("version")!=1 or not condition.get("items") is Dictionary:return marks
	var structure: Dictionary={}
	for value in condition.items.values():
		if not value is Dictionary or str(value.get("status","ok")) not in ["damaged","disabled"]:continue
		var location: String=str(value.get("location",""))
		var anchor: Vector2=Vector2.ZERO
		var height: float=12.5
		var found: bool=false
		if str(value.get("family",""))=="weapons":
			for mount in mounts:
				if str(mount.get("id",""))==location:
					anchor=Vector2(mount.x,mount.y);found=true;break
		elif location in ["engine","pumps"] and str(value.get("family","")) in ["engines","pumps"]:
			if structure.is_empty():structure=Layout.structure(boat.spec)
			# Integral pumps occupy the cabin/bilge damage box, not a gun socket.
			var part: Dictionary=structure.engine if location=="engine" else structure.cabin
			anchor=Vector2(part.x,part.y);height=float(part.height)+1.5;found=true
		if found and marks.size()<MAX_EQUIPMENT_MARKS:
			marks.append({"location":location,"at":anchor,"height":height,"status":str(value.status),"hp":float(value.hp)})
	return marks

static func _engine_hp(boat: Dictionary) -> float:
	# The installed record can change during repair on the very same hull ID.
	# Read it live; never retain an engine-condition snapshot in art caches.
	var condition=boat.get("moduleCondition")
	if condition is Dictionary and condition.get("version")==1 and condition.get("items") is Dictionary:
		for item in condition.items.values():
			if item is Dictionary and item.get("family")=="engines" and item.get("location")=="engine":
				return clampf(float(item.hp),0,1)
	return clampf(float(boat.get("engine",1)),0,1)

static func draw_equipment(ctx: Dictionary,boat: Dictionary,mounts: Array) -> void:
	if int(ctx.lod)>=2:return
	var scale: float=clampf(float(ctx.px)/maxf(4,float(ctx.size)),0.65,2.0)
	for mark in equipment_marks(boat,mounts):
		var p: Vector2=_p(ctx,mark.at,float(mark.height))
		var disabled: bool=str(mark.status)=="disabled"
		var r: float=(3.6 if disabled else 3.0)*scale
		var color:=Color("ff765c") if disabled else Color("ffd278")
		_circle(ctx,p,r+scale,Color(0.07,0.10,0.10,0.88))
		# Broken amber slash versus a red cross also separates state without color.
		_line(ctx,p+Vector2(-r,-r),p+Vector2(r,r),color,1.6*scale)
		if disabled:_line(ctx,p+Vector2(-r,r),p+Vector2(r,-r),color,1.6*scale)
		else:_line(ctx,p+Vector2(r,-r),p+Vector2(r*0.25,-r*0.25),color,1.6*scale)

static func record(ship: Dictionary, point: Vector2, time: float, power: float, material: String, section: String, angle: float) -> void:
	var spec: Dictionary=ship.get("spec",{})
	var size: float=maxf(4.0,float(spec.get("size",16)))
	var at: Vector2=((point-Vector2(ship.get("x",0),ship.get("y",0))).rotated(-float(ship.get("angle",0))))/size
	var stations: Array=Profiles.stations(spec)
	at.x=clampf(at.x,float(stations[0].x)+0.14,float(stations[-1].x)-0.25)
	var beam: float=_beam(stations,at.x)
	if str(spec.get("role",""))=="raider":
		var side: float=1.0 if at.y>=0 else -1.0
		at.y=side*0.62+clampf(at.y-side*0.62,-beam*0.65,beam*0.65)
	else:at.y=clampf(at.y,-beam*0.78,beam*0.78)
	if not ship.get("visualHits") is Array:ship.visualHits=[]
	ship.visualHits.append({"x":at.x,"y":at.y,"at":maxf(0,time),"power":clampf(power,0.2,2.4),"material":material,"section":section,"angle":angle-float(ship.get("angle",0))})
	while ship.visualHits.size()>MAX_SCARS:ship.visualHits.pop_front()
	ship.lastImpactTime=maxf(0,time)

static func _beam(stations: Array,x: float) -> float:
	for i in range(stations.size()-1):
		if x<=float(stations[i+1].x):return lerpf(float(stations[i].y),float(stations[i+1].y),clampf((x-stations[i].x)/maxf(0.001,stations[i+1].x-stations[i].x),0,1))
	return maxf(0.04,float(stations[-2].y))

static func _p(ctx: Dictionary,at: Vector2,h: float) -> Vector2:
	return ctx.proj.call(ctx.pos+at.rotated(ctx.angle)*float(ctx.size),h)

static func _poly(ctx: Dictionary,points: PackedVector2Array,col: Color) -> void:
	var indices: PackedInt32Array=Geometry2D.triangulate_polygon(points)
	for i in range(0,indices.size(),3):
		var a: Vector2=points[indices[i]];var b: Vector2=points[indices[i+1]];var c: Vector2=points[indices[i+2]]
		if absf((b-a).cross(c-a))<1.0:continue
		ctx.canvas.draw_colored_polygon(PackedVector2Array([a,b,c]),col)
		ctx.n+=1;ctx.npoly+=1

static func _line(ctx: Dictionary,a: Vector2,b: Vector2,col: Color,w: float=1.0) -> void:
	ctx.canvas.draw_line(a,b,col,w)
	ctx.n+=1;ctx.nline+=1

static func _circle(ctx: Dictionary,p: Vector2,r: float,col: Color) -> void:
	ctx.canvas.draw_circle(p,maxf(0.6,r),col)
	ctx.n+=1;ctx.ncirc+=1

static func draw(ctx: Dictionary,boat: Dictionary,stations: Array) -> void:
	var hp: float=float(boat.get("hp",boat.get("maxHp",100)))
	var max_hp: float=maxf(1,float(boat.get("maxHp",hp)))
	var damaged: bool=hp<max_hp-0.1 or not boat.get("breaches",[]).is_empty()
	var scars: Array=boat.get("visualHits",[]) if boat.get("visualHits") is Array else []
	var lod: int=int(ctx.lod)
	var scale: float=maxf(0.45,float(ctx.px)/maxf(4,float(ctx.size)))
	if damaged:
		var count: int=mini(MAX_SCARS if lod==0 else 4 if lod==1 else 2,scars.size())
		for i in range(count):
			var hit: Dictionary=scars[scars.size()-1-i]
			var at:=Vector2(hit.get("x",0),hit.get("y",0))
			var power: float=clampf(float(hit.get("power",1)),0.2,2.4)
			var r: float=(0.045+0.035*power)*float(ctx.size)
			var model: Dictionary={"ctx":ctx,"at":at,"bearing":float(hit.get("angle",0)),"u":1.0/float(ctx.size),"world_unit":1.0,"lod":lod,"h":10.1}
			var patch: Array=[Vector3(-r,-r*0.3,0),Vector3(-r*0.3,-r*0.8,0),Vector3(r*0.9,-r*0.5,0),Vector3(r,r*0.4,0),Vector3(r*0.1,r*0.65,0),Vector3(-r*0.7,r*0.4,0)]
			Faces._face(model,patch,Color("3b352c"))
			Faces._face(model,[Vector3(-r*0.45,-r*0.2,0.15),Vector3(r*0.6,-r*0.22,0.15),Vector3(r*0.22,r*0.3,0.15),Vector3(-r*0.35,r*0.22,0.15)],Color("121e20"))
			if lod==0:
				Faces._line(model,Vector3(-r,-r*0.3,0.3),Vector3(-r*1.6,-r*0.85,0.3),Color("ac9d77"),0.7)
				Faces._line(model,Vector3(r,r*0.35,0.3),Vector3(r*1.65,r*0.7,0.3),Color("292a23"),0.8)
		# Old saves still display opened seams even without localized hit records.
		if scars.is_empty():
			for i in range(mini(4,boat.get("breaches",[]).size())):
				var at:=Vector2(0.6-i*0.5,(0.25 if i%2==0 else -0.25))
				if str(boat.spec.get("role",""))=="raider":at.y+=0.62 if i%2==0 else -0.62
				var p: Vector2=_p(ctx,at,10.2)
				_line(ctx,p-Vector2(3,1)*scale,p+Vector2(4,1)*scale,Color("111d1d"),maxf(1,2*scale))
	# The flash is tied to battle time; an old save cannot replay it in port.
	if bool(ctx.get("combat",false)) and not scars.is_empty():
		var hit: Dictionary=scars[-1]
		var age: float=float(ctx.get("shot_clock",0))-float(hit.get("at",-100))
		if age>=0 and age<0.18:
			var p: Vector2=_p(ctx,Vector2(hit.x,hit.y),11)
			var radius: float=(3+float(hit.power)*3)*scale
			var glint:=Color(0.82,0.94,1.0) if str(hit.get("material","wood")) in ["armor","metal"] else Color(1,0.74,0.33)
			glint.a=(1-age/0.18)*0.5
			_circle(ctx,p,radius,glint)
	var fire: float=clampf(float(boat.get("fire",0)),0,100)
	var engine: float=_engine_hp(boat)
	var clock: float=float(ctx.clock)
	if engine<0.72 and lod<2:
		_smoke(ctx,Vector2(-1.04,0.03),engine<0.3,clock,scale,3 if lod==0 else 2)
	if fire<=0 or lod>=2:return
	# Pointed, layered flame tongues follow damaged deck positions; smoke drifts upward.
	var tongues: int=3 if lod==0 else 2
	for i in range(tongues):
		var at:=Vector2(-0.42+i*0.28,0.08 if i%2==0 else -0.08)
		if not scars.is_empty():
			var hit: Dictionary=scars[i%scars.size()]
			at=Vector2(hit.x,hit.y)+Vector2((i-1)*0.07,0)
		var p: Vector2=_p(ctx,at,12)
		var phase: float=clock*9.0+i*2.1
		var height: float=(9+minf(20,fire*0.25))*(0.75+0.17*sin(phase)+0.12*sin(float(i)*2.7))*scale
		var width: float=(3+fire*0.025)*scale
		var lean: float=sin(phase*0.7)*width
		_poly(ctx,PackedVector2Array([p+Vector2(-width,1),p+Vector2(-width*0.9,-height*0.2),p+Vector2(-width*0.45+lean*0.2,-height*0.44),p+Vector2(-width*0.65+lean*0.6,-height*0.65),p+Vector2(lean,-height),p+Vector2(width*0.2+lean*0.8,-height*0.72),p+Vector2(width*0.05+lean*0.5,-height*0.48),p+Vector2(width*0.8,-height*0.27),p+Vector2(width,1)]),Color(0.94,0.25,0.045,0.88))
		_poly(ctx,PackedVector2Array([p+Vector2(-width*0.6,0),p+Vector2(-width*0.3,-height*0.23),p+Vector2(lean*0.4,-height*0.64),p+Vector2(width*0.4,-height*0.2),p+Vector2(width*0.6,0)]),Color(1,0.63,0.12,0.95))
		_poly(ctx,PackedVector2Array([p+Vector2(-width*0.2,0),p+Vector2(lean*0.15,-height*0.32),p+Vector2(width*0.25,0)]),Color(1,0.89,0.52,0.92))
	if lod==0:
		for i in range(2):
			var rise: float=fposmod(clock*0.8+i*0.45,1.0)
			var p: Vector2=_p(ctx,Vector2(-0.15-rise*0.15,sin(clock+i)*0.1),18+rise*25)
			_line(ctx,p,p+Vector2(0,2)*scale,Color(1,0.57,0.14,(1-rise)*0.8),maxf(0.7,scale))
	_smoke(ctx,Vector2(-0.1,0),true,clock,scale,5 if lod==0 else 3)

static func _smoke(ctx: Dictionary,at: Vector2,dark: bool,clock: float,scale: float,count: int) -> void:
	for i in range(count):
		var phase: float=fposmod(clock*0.42+float(i)/count,1.0)
		var p: Vector2=_p(ctx,at+Vector2(-phase*0.4,phase*0.1),20+phase*30)
		var radius: float=(2.5+phase*7)*scale
		var color:=Color(0.13,0.16,0.16,(1-phase)*0.48) if dark else Color(0.49,0.54,0.52,(1-phase)*0.35)
		_circle(ctx,p,radius,color)
