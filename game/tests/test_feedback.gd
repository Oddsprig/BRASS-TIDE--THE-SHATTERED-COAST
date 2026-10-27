extends SceneTree
## Actual hit records, renderer geometry and the last-kill cosmetic tail.
const Battle=preload("res://scripts/battle.gd")
const Damage=preload("res://scripts/damage.gd")
const Events=preload("res://scripts/combat_events.gd")
const Feedback=preload("res://scripts/hull_feedback.gd")
const Faces=preload("res://scripts/weapon_art.gd")
const Art=preload("res://scripts/boat_art.gd")
const FX=preload("res://scripts/combat_art.gd")
const Main=preload("res://scripts/main.gd")
const Motors=preload("res://scripts/motor_art.gd")
const Profiles=preload("res://scripts/hull_profiles.gd")
const Layout=preload("res://scripts/mount_layout.gd")
const Refit=preload("res://scripts/refit.gd")
const MeshCache=preload("res://scripts/boat_mesh_cache.gd")
var checks: int=0
var failures: int=0

class Recorder extends RefCounted:
	const BoatArt=preload("res://scripts/boat_art.gd")
	var prims: Array=[]
	var invalid: int=0
	var scale_factor: float=2.0
	var origin:=Vector2(350,260)
	var transform:=Transform2D.IDENTITY
	var mesh_draws: int=0
	func draw_set_transform_matrix(value: Transform2D) -> void:transform=value
	func draw_mesh(mesh: ArrayMesh,_texture) -> void:
		mesh_draws+=1
		if mesh.get_surface_count()==0:return
		var arrays: Array=mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		for i in range(0,vertices.size(),3):
			var points:=PackedVector2Array()
			for j in range(3):points.append(transform*Vector2(vertices[i+j].x,vertices[i+j].y))
			# PRIMITIVE_TRIANGLES is already triangulated; even a collapsed triangle
			# is valid mesh input. Preserve every triangle and its finite-point check.
			prims.append({"t":"poly","pts":_points(points),"c":_color(colors[i])})
	func project(p: Vector2,h: float=0) -> Vector2:return origin+Vector2((p.x-p.y)*0.82,(p.x+p.y)*0.41-h)*scale_factor
	func _points(p: PackedVector2Array) -> Array:
		var points: Array=[]
		for v in p:
			if not is_finite(v.x) or not is_finite(v.y):invalid+=1
			points.append([v.x,v.y])
		return points
	func _color(c: Color) -> Array:return [c.r,c.g,c.b,c.a]
	func draw_colored_polygon(p: PackedVector2Array,c: Color) -> void:
		if Geometry2D.triangulate_polygon(p).is_empty():invalid+=1
		var painted:=PackedVector2Array()
		for point in p:painted.append(transform*point)
		prims.append({"t":"poly","pts":_points(painted),"c":_color(c)})
	func draw_line(a: Vector2,b: Vector2,c: Color,w: float=-1,_aa: bool=false) -> void:
		prims.append({"t":"seg","pts":_points(PackedVector2Array([a,b])),"c":_color(c),"w":maxf(0.5,w)})
	func draw_polyline(p: PackedVector2Array,c: Color,w: float=-1,_aa: bool=false) -> void:
		prims.append({"t":"line","pts":_points(p),"c":_color(c),"w":maxf(0.5,w)})
	func draw_circle(p: Vector2,r: float,c: Color) -> void:
		if r<0 or not is_finite(r):invalid+=1
		prims.append({"t":"circle","pts":_points(PackedVector2Array([p])),"c":_color(c),"r":maxf(0,r)})
	func draw_arc(p: Vector2,r: float,a: float,b: float,n: int,c: Color,w: float=-1,_aa: bool=false) -> void:
		var points:=PackedVector2Array()
		for i in range(maxi(2,n)+1):points.append(p+Vector2.from_angle(lerpf(a,b,float(i)/maxi(2,n)))*r)
		draw_polyline(points,c,w)
	func draw_rect(r: Rect2,c: Color,filled: bool=true,w: float=-1) -> void:
		var points:=PackedVector2Array([r.position,r.position+Vector2(r.size.x,0),r.end,r.position+Vector2(0,r.size.y)])
		if filled:draw_colored_polygon(points,c)
		else:points.append(points[0]);draw_polyline(points,c,w)

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("FEEDBACK: "+message)

func _initialize() -> void:call_deferred("run")

func motor_draw(spec: Dictionary,boat: Dictionary,lod: int,time: float=0.0) -> Recorder:
	var rec:=Recorder.new()
	var ctx: Dictionary={"canvas":rec,"proj":rec.project,"pos":Vector2.ZERO,"angle":-0.45,"size":float(spec.size),"hull_size":float(spec.size),"enlargement":1.0,"px":float(spec.size)*2.0,"lod":lod,"clock":time,"speed":60.0,"n":0,"npoly":0,"nline":0,"ncirc":0}
	Motors.draw(ctx,spec,boat,Art.palette(spec,Color("dfbd7d"),false))
	check(rec.prims.size()==int(ctx.n),"all motor primitives counted "+spec.id)
	return rec

func test_motors(hulls: Array) -> void:
	var max_near: int=0
	var max_far: int=0
	for spec in hulls:
		var original: Dictionary=spec.duplicate(true)
		var boat: Dictionary=Damage.create_ship(spec)
		var plan: Dictionary=Motors.layout(spec,boat)
		check(plan.transomX==Profiles.stations(spec)[0].x,"motors attach to actual hull transom "+spec.id)
		check(plan.count>=1 and plan.count<=3 and plan.minX<plan.transomX,"physical drive extends behind hull "+spec.id)
		for item in plan.units+plan.machinery:
			for socket in Layout.hardpoints(spec):check(Layout.footprint_clearance(socket,item)>0.04,"motor machinery clears every interchangeable socket "+spec.id)
		var counts: Array=[]
		for lod in range(3):
			var rec: Recorder=motor_draw(spec,boat,lod)
			check(rec.invalid==0,"motor art geometry finite and valid "+spec.id)
			counts.append(rec.prims.size())
		check(counts[0]>counts[1] and counts[1]>counts[2],"motors reduce detail at each zoom level "+spec.id)
		check(counts[0]<=250 and counts[2]<=50,"motors stay within close/far drawing budgets "+spec.id+" "+str(counts))
		max_near=maxi(max_near,counts[0]);max_far=maxi(max_far,counts[2])
		check(spec==original,"motor layout/render does not change numerical hull "+spec.id)
		boat.fuel=0.0
		check(motor_draw(spec,boat,0,0.1).prims==motor_draw(spec,boat,0,0.7).prims,"empty fuel stops powered prop animation "+spec.id)
		for id in ["economy_drive","boost_drive","heavy_drive"]:
			var fit: Dictionary=Refit.defaults(spec);fit.engine=id
			var normalized: Dictionary=Refit.normalize(spec,fit)
			if not normalized.ok:continue
			var effective: Dictionary=Refit.effective_spec(spec,normalized.loadout)
			check(Motors.layout(effective).engineId==id,"paid engine package reaches renderer "+spec.id+" "+id)
	print("MOTOR BUDGET: max %d close / %d far primitives per boat"%[max_near,max_far])

func test_meshes(hulls: Array) -> void:
	MeshCache.clear()
	for spec in hulls:
		var boat: Dictionary=Art.preview_boat(Refit.effective_spec(spec,Refit.defaults(spec)))
		for angle in [-2.1,-0.51,0.0,0.03,1.63,3.02]:
			boat.angle=angle
			var before: Dictionary=boat.duplicate(true)
			var rec:=Recorder.new()
			Art.draw_boat(rec,rec.project,boat,{"cache":true,"lod":1,"px":spec.size*2,"clock":0.3})
			check(rec.mesh_draws==1+boat.spec.weaponMounts.size(),"hull and physical weapons use separate mesh draws "+spec.id)
			check(rec.invalid==0 and not rec.prims.is_empty(),"cached geometry capture is valid "+spec.id)
			check(boat==before,"mesh capture does not change fitted ship "+spec.id)
			var misses: int=MeshCache.misses
			var again:=Recorder.new()
			Art.draw_boat(again,again.project,boat,{"cache":true,"lod":1,"px":spec.size*2,"clock":0.3})
			check(MeshCache.misses==misses and again.prims==rec.prims,"repeat frame reuses identical cached equipment geometry")
	check(MeshCache._meshes.size()<=MeshCache.LIMIT,"colored mesh cache remains bounded")
	for mesh in MeshCache._meshes.values():
		check(mesh.get_surface_count()==1 and mesh.surface_get_array_len(0)%3==0,"valid native triangle surface")
	MeshCache.clear()

func test_draw_inputs(spec: Dictionary) -> void:
	# Compare warm preparation with the public uncached values and actual drawing.
	# This is a narrow source candidate fixture, not a rendered-performance probe.
	Art._draw_input_cache.clear()
	var fitted: Dictionary=Refit.effective_spec(spec,Refit.defaults(spec))
	var before: Dictionary=fitted.duplicate(true)
	var accent:=Color("dfbd7d")
	var prepared: Dictionary=Art._draw_inputs(fitted,accent,false)
	check(is_same(prepared,Art._draw_inputs(fitted.duplicate(true),accent,false)),"equal detached fits reuse drawing preparation")
	check(prepared.palette==Art.palette(fitted,accent,false) and prepared.mounts==Art.mounts_of(fitted),"prepared palette and sockets equal uncached public values")
	var exposed_palette: Dictionary=Art.palette(fitted,accent,false)
	var exposed_mounts: Array=Art.mounts_of(fitted)
	exposed_palette.top=Color.WHITE;exposed_mounts[0].x=999.0
	check(prepared.palette!=exposed_palette and prepared.mounts!=exposed_mounts,"public inspection copies cannot change prepared art")
	var ship: Dictionary=Art.preview_boat(fitted)
	ship.battleTime=0.3
	var opts: Dictionary={"cache":true,"lod":1,"px":float(spec.size)*2.0,"clock":0.3,"accent":accent}
	Art._draw_input_cache.clear()
	var cold:=Recorder.new();var warm:=Recorder.new()
	Art.draw_boat(cold,cold.project,ship,opts);Art.draw_boat(warm,warm.project,ship,opts)
	check(cold.invalid==0 and warm.invalid==0 and cold.prims==warm.prims,"warm preparation preserves every actual drawing primitive")
	check(fitted==before,"preparing and drawing leave the fitted spec untouched")
	# A new array identity and an in-place edit must both invalidate immediately.
	for field in ["x","y","angle","size","kind","id","moduleId"]:
		var changed: Dictionary=fitted.duplicate(true)
		changed.weaponMounts[0][field]={"x":7.0,"y":-3.0,"angle":0.6,"size":2,"kind":"rocket","id":"mount043","moduleId":"043-fit"}[field]
		Art._draw_inputs(fitted,accent,false)
		var fresh: Dictionary=Art._draw_inputs(changed,accent,false)
		check(fresh.mounts==Art.mounts_of(changed),"same-id fit edit is visible immediately: "+field)
		changed.weaponMounts[0][field]=fitted.weaponMounts[0].get(field)
		check(Art._draw_inputs(changed,accent,false).mounts==Art.mounts_of(changed),"in-place fit edit is visible immediately: "+field)
	var empty: Dictionary=fitted.duplicate(true);empty.weaponMounts=[]
	check(Art._draw_inputs(empty,accent,false).mounts.is_empty(),"removing the last fitted weapon leaves no cached gun")
	empty.erase("weaponMounts")
	for changes in [{"role":"raider"},{"size":31.0},{"tier":4},{"weapon":"rocket"},{"faction":"raiders"},{"civilianRole":"yacht"},{"armor":18}]:
		var changed: Dictionary=empty.duplicate(true);changed.merge(changes,true)
		var fresh: Dictionary=Art._draw_inputs(changed,accent,false)
		check(fresh.archetype==Art.archetype(changed) and fresh.palette==Art.palette(changed,accent,false) and fresh.mounts==Art.mounts_of(changed),"same-id bare hull preparation follows "+str(changes.keys()))
	check(Art._draw_inputs(fitted,Color("8fc6b4"),true).palette==Art.palette(fitted,Color("8fc6b4"),true),"accent and enemy tint remain exact per draw")
	prepared=Art._draw_inputs(fitted,accent,false)
	for changes in [{"x":19.0,"angle":0.35},{"localAimAngles":{"mount0":0.7}},{"mountShotTimes":{"mount0":0.28}},{"hp":50.0,"maxHp":100.0,"water":20.0,"fire":30.0,"engine":0.3,"fuel":10.0}]:
		var animated: Dictionary=ship.duplicate(true);animated.merge(changes,true)
		var live_before: Dictionary=animated.duplicate(true)
		var live:=Recorder.new();Art.draw_boat(live,live.project,animated,opts)
		check(is_same(prepared,Art._draw_inputs(fitted,accent,false)) and live.prims!=warm.prims and live.invalid==0,"shared static preparation keeps live draw fields: "+str(changes.keys()))
		check(animated==live_before,"live drawing does not write boat state")
	for i in range(Art.DRAW_INPUT_LIMIT+1):
		var other: Dictionary=fitted.duplicate(true);other.id="prepared043-%d"%i
		Art._draw_inputs(other,accent,false)
	check(Art._draw_input_cache.size()<=Art.DRAW_INPUT_LIMIT,"drawing preparation stays bounded across hull identities")
	Art._draw_input_cache.clear()

func test_equipment_marks051(spec: Dictionary) -> void:
	# Exercise the actual BoatArt caller with a warm preparation, then inspect
	# its visible circles against the public physical layout, never cache fields.
	var boat: Dictionary=Damage.create_ship(spec.duplicate(true),{"uid":"feedback-marker051"})
	var seeded: Dictionary=Damage.EquipmentDamage.Records.initialize(boat,{"base":boat.spec,"loadout":Refit.defaults(boat.spec),"catalog":Refit.catalog(),"identity":str(boat.uid)})
	check(bool(seeded.get("ok",false)),"marker regression initializes real installed equipment")
	if not bool(seeded.get("ok",false)):return
	var items: Dictionary={}
	for item: Dictionary in boat.moduleCondition.items.values():
		if str(item.location) in ["engine","pumps"]:items[str(item.location)]=item
	check(items.size()==2,"marker regression has actual engine and integral pump records")
	if items.size()!=2:return
	boat.x=140.0;boat.y=210.0;boat.angle=0.7
	var opts: Dictionary={"lod":0,"px":float(spec.size)*2.0,"clock":0.3,"combat":false}
	var warm:=Recorder.new();Art.draw_boat(warm,warm.project,boat,opts)
	var mutations: Array=[{}, {"role":"cruiser" if str(spec.get("role",""))!="cruiser" else "skiff"}, {"tier":4 if int(spec.get("tier",1))!=4 else 1}, {"faction":"reed" if str(spec.get("faction",""))!="reed" else "forge"}, {"size":float(spec.size)+7.0}]
	for phase: int in range(3):
		if phase==1:
			check(Damage.EquipmentDamage.Core.restore_installed_paid(boat.moduleCondition,{"confirmPaid":true}).ok,"synthetic paid restoration repairs the same installed marker records")
		else:
			for location: String in ["engine","pumps"]:
				var loss: float=0.90 if ((location=="engine")== (phase==0)) else 0.55
				check(Damage.EquipmentDamage.Core.apply_component_damage(boat.moduleCondition,{"itemUid":str(items[location].itemUid),"loss":loss,"cause":"Marker regression"}).ok,"actual condition transition reaches "+location+" marker phase "+str(phase))
		for changes: Dictionary in (mutations if phase==2 else [{}]):
			boat.spec.merge(changes,true) # In-place edits preserve the exact hull ID.
			var before: PackedByteArray=var_to_bytes(boat)
			var rec:=Recorder.new();Art.draw_boat(rec,rec.project,boat,opts)
			var circles: Array=rec.prims.filter(func(prim):return prim.t=="circle" and prim.c==rec._color(Color(0.07,0.10,0.10,0.88)))
			var marks: Array=Feedback.equipment_marks(boat,Art.mounts_of(boat.spec))
			var structure: Dictionary=Layout.structure(boat.spec)
			var expected: Array=[]
			for location: String in ["engine","pumps"]:
				var item: Dictionary=items[location]
				if str(item.status) not in ["damaged","disabled"]:continue
				var part: Dictionary=structure.engine if location=="engine" else structure.cabin
				var anchor:=Vector2(part.x,part.y)
				var height: float=float(part.height)+1.5
				expected.append({"location":location,"at":anchor,"height":height,"status":str(item.status),"hp":float(item.hp)})
				var center: Vector2=rec.project(Vector2(boat.x,boat.y)+anchor.rotated(float(boat.angle))*float(boat.spec.size),height)
				var scale: float=clampf(float(opts.px)/float(boat.spec.size),0.65,2.0)
				var radius: float=((3.6 if str(item.status)=="disabled" else 3.0)+1.0)*scale
				check(circles.any(func(circle):return circle.pts==[[center.x,center.y]] and is_equal_approx(float(circle.r),radius)),"warm art places the current "+str(item.status)+" "+location+" marker at its physical anchor: "+str(changes))
			check(circles.size()==expected.size() and marks==expected and rec.invalid==0,"same-ID preparation and public fresh marks follow repair/spec edits without stale overlays phase="+str(phase)+" "+str(changes))
			check(var_to_bytes(boat)==before,"equipment marker rendering preserves all live boat/condition data")

func test_effects(hulls: Array) -> void:
	var max_effect: int=0
	for family in ["gun","cannon","rocket","torpedo"]:
		for material in ["wood","metal","armor","water"]:
			for kind in ["fire","hit","miss","engine","sink"]:
				var state: Dictionary={"time":0.0,"effects":[],"wrecks":[]}
				var e: Dictionary=Events.add_effect(state,Vector2.ZERO,"muzzle" if kind=="fire" else "splash" if kind=="miss" else "explosion" if kind=="sink" else "hit",{"kind":kind,"family":family,"material":material,"hullMaterial":material,"reason":"hull","seq":701})
				for lod in range(3):
					e.lod=lod
					for t in [0.0,0.15,0.5,0.92]:
						e.age=t*e.life
						var before: Dictionary=e.duplicate(true)
						var rec:=Recorder.new()
						var count: int=FX.effect(rec,e)
						check(count==rec.prims.size() and count<=35,"strict effect budget and accounting "+family+" "+material+" "+kind)
						check(rec.invalid==0 and e==before,"effects use valid geometry and leave combat data untouched")
						max_effect=maxi(max_effect,count)
				e.age=e.life
				check(FX.effect(Recorder.new(),e)==0,"expired effects stop drawing")
	for index in [0,6,10,14,17,23]:
		for cause in ["hull","flooding"]:
			var boat: Dictionary=Damage.create_ship(hulls[index]);boat.sunk=true
			if cause=="hull":boat.hp=0.0
			else:boat.water=boat.capacity
			var state: Dictionary={"time":0.0,"effects":[],"wrecks":[]}
			var wreck: Dictionary=Events.record_wreck(state,boat,boat.spec.size)
			for angle in [-1.5,0.0,1.5,3.0]:
				for t in [0.0,0.45,0.9,1.0]:
					wreck.angle=angle;wreck.sinkProgress=t;wreck.age=t*2.2
					var rec:=Recorder.new()
					var before: Dictionary=wreck.duplicate(true)
					FX.wreck(rec,wreck)
					check(rec.invalid==0 and wreck==before,"sinking renderer handles class/heading/phase without changing wreck")
	print("EFFECT BUDGET: max %d primitives per effect"%max_effect)

func _identity_proj(p: Vector2,_h: float) -> Vector2: return p

func _old_fan(points: PackedVector2Array) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for i in range(1,points.size()-1):
		if absf((points[i]-points[0]).cross(points[i+1]-points[0]))<1.0: continue
		indices.append(0); indices.append(i); indices.append(i+1)
	return indices

func _projected(model: Dictionary,vertices: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for vertex in vertices: points.append(Faces._p(model,vertex))
	return points

func _same_points(got,expect: PackedVector2Array) -> bool:
	if got.size()!=expect.size(): return false
	for i in got.size():
		if not is_equal_approx(float(got[i].x),expect[i].x) or not is_equal_approx(float(got[i].y),expect[i].y): return false
	return true

func _same_indices(got,expect: PackedInt32Array) -> bool:
	if got.size()!=expect.size(): return false
	for i in got.size():
		if int(got[i])!=int(expect[i]): return false
	return true

func _same_tri(prim: Dictionary,points: PackedVector2Array,a: int,b: int,c: int,color: Color) -> bool:
	var got: Array=prim.pts
	var cols: Array=prim.c
	if prim.t!="poly" or got.size()!=3: return false
	var expect: Array=[points[a],points[b],points[c]]
	for i in range(3):
		if not is_equal_approx(float(got[i][0]),expect[i].x) or not is_equal_approx(float(got[i][1]),expect[i].y): return false
	return is_equal_approx(float(cols[0]),color.r) and is_equal_approx(float(cols[1]),color.g) and is_equal_approx(float(cols[2]),color.b) and is_equal_approx(float(cols[3]),color.a)

func test_flame_batch051() -> void:
	# Compare the batched path with the old per-triangle flame loop. Include
	# empty, exactly-threshold and partially rejected triangulations.
	var contours: Array=[
		PackedVector2Array([Vector2.ZERO,Vector2(2,0),Vector2(2,0.499)]),
		PackedVector2Array([Vector2.ZERO,Vector2(2,0),Vector2(2,0.5)]),
		PackedVector2Array([Vector2.ZERO,Vector2(2,0),Vector2(2,4),Vector2(0,4),Vector2(-0.01,0.499)]),
		PackedVector2Array([Vector2(-3,1),Vector2(-2.7,-3),Vector2(-1,-7),Vector2(-2,-11),Vector2(1,-17),Vector2(1.4,-12),Vector2(0.65,-8),Vector2(2.4,-4),Vector2(3,1)])]
	var color:=Color(0.94,0.25,0.045,0.88)
	for points in contours:
		var old: PackedInt32Array=Geometry2D.triangulate_polygon(points)
		var expected:=PackedInt32Array()
		for i in range(0,old.size(),3):
			var a: Vector2=points[old[i]];var b: Vector2=points[old[i+1]];var c: Vector2=points[old[i+2]]
			if absf((b-a).cross(c-a))<1.0:continue
			expected.append(old[i]);expected.append(old[i+1]);expected.append(old[i+2])
		var rec:=Recorder.new()
		var ctx: Dictionary={"canvas":rec,"n":0,"npoly":0,"nline":0,"ncirc":0}
		Feedback._poly(ctx,points,color)
		var count: int=expected.size()/3
		check(rec.invalid==0 and rec.prims.size()==count and int(ctx.n)==count and int(ctx.npoly)==count,"flame batch keeps the old visible triangle count")
		var same: bool=rec.prims.size()==count
		if same:
			for i in range(count):
				if not _same_tri(rec.prims[i],points,expected[i*3],expected[i*3+1],expected[i*3+2],color):same=false
		check(same,"flame batch keeps original triangle order, color and sliver gaps")

func _check_fan(model: Dictionary,vertices: Array,label: String) -> PackedInt32Array:
	var canvas=model.ctx.canvas
	var before: int=canvas.prims.size() if canvas is Recorder else -1
	var got: Dictionary=Feedback._scar_fan(model,vertices)
	var points: PackedVector2Array=_projected(model,vertices)
	var old: PackedInt32Array=_old_fan(points)
	check(_same_points(got.points,points),"scar fan keeps the weapon projection "+label)
	check(_same_indices(got.indices,old),"scar fan indices match the old surviving fan "+label)
	if before>=0: check(canvas.prims.size()==before,"scar fan read does not draw "+label)
	return old

func _scar_patches(size: float,power: float) -> Array:
	var r: float=(0.045+0.035*power)*size
	return [
		[Vector3(-r,-r*0.3,0),Vector3(-r*0.3,-r*0.8,0),Vector3(r*0.9,-r*0.5,0),Vector3(r,r*0.4,0),Vector3(r*0.1,r*0.65,0),Vector3(-r*0.7,r*0.4,0)],
		[Vector3(-r*0.45,-r*0.2,0.15),Vector3(r*0.6,-r*0.22,0.15),Vector3(r*0.22,r*0.3,0.15),Vector3(-r*0.35,r*0.22,0.15)]]

func _check_draw_patches(size: float,heading: float,lod: int) -> void:
	var rec := Recorder.new()
	var ctx: Dictionary={"canvas":rec,"proj":rec.project,"pos":Vector2(30,80),"angle":heading,"size":size,"px":size*2.0,"lod":lod,"clock":5.0,"combat":false,"n":0,"npoly":0,"nline":0,"ncirc":0}
	var boat: Dictionary={"hp":40.0,"maxHp":100.0,"fire":0.0,"engine":1.0,"breaches":[],"spec":{"role":"escort","size":size},"visualHits":[{"x":0.15,"y":-0.2,"at":1.0,"power":1.0,"angle":0.7,"material":"wood","section":"mid"}]}
	var before: PackedByteArray=var_to_bytes(boat)
	Feedback.draw(ctx,boat,[])
	check(var_to_bytes(boat)==before,"scar batch draw does not write the boat")
	var model: Dictionary={"ctx":ctx,"at":Vector2(0.15,-0.2),"bearing":0.7,"u":1.0/size,"world_unit":1.0,"lod":lod,"h":10.1}
	var patches: Array=_scar_patches(size,1.0)
	var colors: Array=[Color("3b352c"),Color("121e20")]
	var expect: int=0
	var fans: Array=[]
	for patch in patches:
		var fan: Dictionary=Feedback._scar_fan(model,patch)
		fans.append(fan)
		expect+=fan.indices.size()/3
	var polys: Array=[]
	for prim in rec.prims:
		if prim.t=="poly": polys.append(prim)
	var lines: int=2 if lod==0 else 0
	check(polys.size()==expect and int(ctx.npoly)==expect and int(ctx.nline)==lines,"draw keeps only surviving scar triangles plus the old crack lines s%.0f lod%d"%[size,lod])
	check(int(ctx.n)==expect+lines and rec.prims.size()==expect+lines,"recorder triangle commands still match the primitive count")
	if size>=36.0: check(expect>0,"a large scar still has a visible fan triangle")
	var cursor: int=0
	var ordered: bool=true
	for patch_i in range(2):
		var indices: PackedInt32Array=fans[patch_i].indices
		var points: PackedVector2Array=fans[patch_i].points
		for step in range(0,indices.size(),3):
			if cursor>=polys.size() or not _same_tri(polys[cursor],points,indices[step],indices[step+1],indices[step+2],colors[patch_i]): ordered=false
			cursor+=1
	check(ordered and cursor==polys.size(),"draw order is the outer fan, then the inner fan, with no extra polygon")

func test_scar_fan() -> void:
	var flat: Dictionary={"canvas":Recorder.new(),"proj":_identity_proj,"pos":Vector2.ZERO,"angle":0.0,"size":1.0,"px":12.0,"lod":0,"n":0,"npoly":0,"nline":0,"ncirc":0}
	var model: Dictionary={"ctx":flat,"at":Vector2.ZERO,"bearing":0.0,"u":1.0,"world_unit":1.0,"lod":0,"h":0.0}
	# cross 1.0 stays; the next sliver is 0.998 and must stay absent.
	var boundary: Array=[Vector3(0,0,0),Vector3(2,0,0),Vector3(2,0.5,0),Vector3(2,0.999,0),Vector3(0,4,0)]
	check(_same_indices(_check_fan(model,boundary,"exact threshold"),PackedInt32Array([0,1,2,0,3,4])),"cross of 1 stays and the 0.998 sliver stays omitted")
	var dropped: Array=[Vector3(0,0,0),Vector3(0.2,0,0),Vector3(0.2,0.2,0),Vector3(0,0.2,0)]
	check(_check_fan(model,dropped,"subpixel").is_empty(),"subpixel patch refuses every fan triangle")
	var full: Array=[Vector3(0,0,0),Vector3(20,0,0),Vector3(20,20,0),Vector3(0,20,0)]
	check(_check_fan(model,full,"full quad").size()==6,"large quad keeps both fan triangles")
	var rec: Recorder=flat.canvas
	Feedback._face_batch(model,dropped,Color("3b352c"))
	check(rec.prims.is_empty() and int(flat.n)==0,"empty fan submits no polygon")
	Feedback._face_batch(model,boundary,Color("121e20"))
	var kept: Dictionary=Feedback._scar_fan(model,boundary)
	check(rec.prims.size()==2 and int(flat.n)==2 and int(flat.npoly)==2,"partial fan submits one polygon per surviving triangle")
	check(rec.prims[0].pts.size()==3 and rec.prims[1].pts.size()==3,"partial fan does not draw the convex patch")
	check(_same_tri(rec.prims[0],kept.points,0,1,2,Color("121e20")) and _same_tri(rec.prims[1],kept.points,0,3,4,Color("121e20")),"recorded triangles are the kept fan and skip the sliver")
	var oblique := Recorder.new()
	for heading in [0.0,0.9,2.1,4.0]:
		for bearing in [-0.6,1.8]:
			for size in [4.0,18.0,46.0]:
				for scale in [0.4,2.2]:
					oblique.scale_factor=scale
					var ctx: Dictionary={"canvas":oblique,"proj":oblique.project,"pos":Vector2(120,-40),"angle":heading,"size":size,"px":size*scale,"lod":0,"n":0,"npoly":0,"nline":0,"ncirc":0}
					var posed: Dictionary={"ctx":ctx,"at":Vector2(0.2,-0.15),"bearing":bearing,"u":1.0/size,"world_unit":1.0,"lod":0,"h":10.1}
					var patches: Array=_scar_patches(size,1.0)
					_check_fan(posed,patches[0],"outer h%.1f b%.1f s%.0f x%.1f"%[heading,bearing,size,scale])
					_check_fan(posed,patches[1],"inner h%.1f b%.1f s%.0f x%.1f"%[heading,bearing,size,scale])
	_check_draw_patches(6.0,0.2,0)
	_check_draw_patches(36.0,2.6,0)
	_check_draw_patches(36.0,2.6,2)

func run() -> void:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var spec: Dictionary=world.HULLS[0]
	test_draw_inputs(spec)
	test_equipment_marks051(spec)
	if "--qa-draw-inputs043" in OS.get_cmdline_user_args():
		print("DRAW INPUTS043: %d checks, %d failures"%[checks,failures])
		quit(0 if failures==0 else 1)
		return
	test_motors(world.HULLS)
	test_effects(world.HULLS)
	test_meshes(world.HULLS)
	var ship: Dictionary=Damage.create_ship(spec)
	var battle: Dictionary=Battle.create({"fleet":[ship],"enemySpecs":[spec],"seed":701})
	var random_state: int=battle.rng.state
	ship.angle=0.7
	var point: Vector2=Vector2(ship.x,ship.y)+Vector2(0.5,0.2).rotated(ship.angle)*spec.size
	var initial: Dictionary=ship.duplicate(true)
	Events.emit_hit(battle,{"kind":"shell","vx":100,"vy":0,"team":"enemy","owner":"enemy-0"},ship,point,"bow",["Breach: bow"],12)
	check(ship.visualHits.size()==1,"actual impact stores a bounded localized scar")
	check(absf(ship.visualHits[0].x-0.5)<0.001 and absf(ship.visualHits[0].y-0.2)<0.001,"hit location follows moving/rotating hull coordinates")
	check(battle.rng.state==random_state,"cosmetic telemetry consumes no battle randomness")
	for key in ["hp","crew","engine","water","ammo","supplies","fuel","breaches"]:check(ship[key]==initial[key],"feedback does not mutate "+key)
	for i in range(40):Feedback.record(ship,point,float(i),1.0,"metal","engine",0)
	check(ship.visualHits.size()==Feedback.MAX_SCARS,"long engagements keep at most eight scars per hull")
	check(ship.visualHits[0].at==32 and ship.visualHits[-1].at==39,"oldest scars expire in order")
	test_scar_fan()
	test_flame_batch051()
	ship.hp=ship.maxHp*0.5;ship.engine=0.25;ship.fire=48.0
	var hashes: Dictionary={}
	for lod in range(3):
		for heading in range(0,360,15):
			ship.angle=heading*PI/180.0
			var rec:=Recorder.new()
			var stats: Dictionary=Art.draw_boat(rec,rec.project,ship,{"lod":lod,"px":spec.size*2.0,"clock":2.1,"combat":true,"battle_clock":39.05})
			check(rec.invalid==0,"damaged hull has finite triangulatable geometry heading %d LOD%d"%[heading,lod])
			check(stats.primitives==rec.prims.size(),"renderer accounts for all damage primitives")
	for time in [0.1,0.22,0.44]:
		var rec:=Recorder.new()
		Art.draw_boat(rec,rec.project,ship,{"lod":0,"px":28,"clock":time,"combat":false})
		hashes[JSON.stringify(rec.prims)]=true
	check(hashes.size()==3,"fire and damaged engine smoke visibly animate without a crew simulation")
	var pristine: Dictionary=Art.preview_boat(spec)
	pristine.visualHits=ship.visualHits.duplicate(true)
	var repaired:=Recorder.new();var clean:=Recorder.new()
	Art.draw_boat(repaired,repaired.project,pristine,{"clock":1.0,"combat":false})
	pristine.erase("visualHits")
	Art.draw_boat(clean,clean.project,pristine,{"clock":1.0,"combat":false})
	check(repaired.prims==clean.prims,"fully repaired hull has no stale damage scars or impact flash")
	# A real final kill: combat resolves, then only effects and wrecks may advance.
	var final: Dictionary=Battle.create({"fleet":[Damage.create_ship(spec)],"enemySpecs":[spec],"seed":702})
	var victim: Dictionary=final.ships[1]
	victim.hp=0.0;victim.sunk=true
	Battle.update(final,1.0/60.0)
	check(final.result=="won" and final.wrecks.size()==1,"final enemy creates a wreck before victory")
	var before: Dictionary={"ships":final.ships.duplicate(true),"shots":final.projectiles.duplicate(true),"rng":final.rng.state,"time":final.time,"result":final.result,"events":final.events.duplicate(true)}
	for i in range(120):Battle.advance_visuals(final,1.0/30.0)
	check(final.wrecks[0].sinkProgress==1.0 and not final.wrecks[0].sinking,"last wreck completes sinking after victory")
	check(final.effects.is_empty(),"last explosion expires after battle result")
	check(final.ships==before.ships and final.projectiles==before.shots,"cosmetic tail does not move, repair, fire or spend stores")
	check(final.rng.state==before.rng and final.time==before.time and final.result==before.result and final.events==before.events,"combat time, randomness, outcome and reward events remain frozen")
	var live: Dictionary=Battle.create({"fleet":[Damage.create_ship(spec)],"enemySpecs":[spec],"seed":703})
	Battle.advance_visuals(live,0.1)
	check(not live.has("visualTailTime"),"cosmetic tail cannot double-advance a running battle")
	# Actual Main result panel wiring, including user pause.
	var game=Main.new();root.add_child(game);await process_frame
	game.set_process(false);game.set_physics_process(false)
	game.battle=final;game.mode="battle";game.result_handled=true;game.paused=false
	game.ui.modal("Feedback fixture");game.ui.modal_kind="outcome"
	var age: float=final.wrecks[0].age
	game._process(0.1)
	check(final.wrecks[0].age>age,"Main advances result-panel animation even with modal open")
	age=final.wrecks[0].age;game.paused=true;game._process(0.1)
	check(final.wrecks[0].age==age,"explicit pause freezes the cosmetic tail")
	game.paused=false;game.ui.modal_kind="menu";game._process(0.1)
	check(final.wrecks[0].age==age,"Escape menu freezes the cosmetic tail")
	game.return_to_title();game.queue_free();await process_frame
	print("FEEDBACK: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
