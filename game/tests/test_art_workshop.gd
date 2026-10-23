extends SceneTree
## Workshop geometry contracts: actual clearances, empty fittings, LOD cost and
## weapon-tip agreement. This is independent of the workshop's drawing constants.
const Art = preload("res://scripts/boat_art.gd")
const Detail = preload("res://scripts/boat_deck_detail.gd")
const Layout = preload("res://scripts/mount_layout.gd")
const Weapons = preload("res://scripts/weapon_art.gd")
const Geometry = preload("res://scripts/weapon_geometry.gd")
const Refit = preload("res://scripts/refit.gd")
var checks: int = 0
var failures: int = 0

class Recorder extends RefCounted:
	var count: int = 0
	var invalid: int = 0
	var max_x: float = -INF
	var origin := Vector2.ZERO
	var scale_factor: float = 2.0
	var capture: bool = false
	var prims: Array = []
	func project(p: Vector2, height: float) -> Vector2:
		return origin+Vector2((p.x-p.y)*0.82,(p.x+p.y)*0.41-height)*scale_factor
	func _save(kind: String, points: PackedVector2Array, color: Color, extra: Dictionary = {}) -> void:
		if not capture:return
		var encoded: Array = []
		for point in points:encoded.append([point.x,point.y])
		prims.append({"t":kind,"pts":encoded,"c":[color.r,color.g,color.b,color.a]}.merged(extra))
	func _points(points: PackedVector2Array) -> void:
		for point in points:
			if not is_finite(point.x) or not is_finite(point.y):invalid+=1
			max_x=maxf(max_x,point.x)
	func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
		count+=1;_points(points)
		_save("poly",points,color)
		if Geometry2D.triangulate_polygon(points).is_empty():invalid+=1
	func draw_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
		count+=1;_points(points)
		_save("line",points,color,{"w":width})
		if not is_finite(width) or width<=0.0:invalid+=1
	func draw_line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
		count+=1;_points(PackedVector2Array([a,b]))
		_save("seg",PackedVector2Array([a,b]),color,{"w":width})
		if not is_finite(width) or width<=0.0:invalid+=1
	func draw_circle(at: Vector2, radius: float, color: Color) -> void:
		count+=1;_points(PackedVector2Array([at]))
		_save("circle",PackedVector2Array([at]),color,{"r":radius})
		if not is_finite(radius) or radius<=0.0:invalid+=1

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("ART WORKSHOP: "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var worst_near: int = 0
	var worst_far: int = 0
	for spec in world.HULLS:
		var before: Dictionary = spec.duplicate(true)
		var plan: Dictionary = Detail.layout(spec)
		var hatch: bool = false
		for item in plan.items:
			if item.kind=="access_hatch":hatch=true
			for socket in Layout.hardpoints(spec):check(Layout.footprint_clearance(socket,item)>0.0,"working fittings clear socket "+spec.id+" "+socket.id)
		check(hatch,"free-deck access hatch exists "+spec.id)
		for rail in plan.rails:
			for socket in Layout.hardpoints(spec):check(Layout.footprint_clearance(socket,rail.footprint)>0.0,"rail gaps preserve socket "+spec.id+" "+socket.id)
		if not plan.items.is_empty():
			var previous_x: float = plan.items[0].x
			plan.items[0].x=previous_x+10.0
			check(is_equal_approx(float(Detail.layout(spec).items[0].x),previous_x),"inspection metadata is detached "+spec.id)
		for angle in [-0.45,0.0,PI*0.5,PI,PI*1.5]:
			var costs: Array = []
			for lod in range(3):
				var rec := Recorder.new()
				var boat: Dictionary = Art.preview_boat(spec,angle)
				var stats: Dictionary = Art.draw_boat(rec,rec.project,boat,{"lod":lod,"px":float(spec.size)*2.0})
				check(rec.invalid==0,"valid workshop faces at heading/LOD "+spec.id)
				check(rec.count==stats.primitives,"every workshop primitive counted "+spec.id)
				costs.append(rec.count)
			check(costs[0]>costs[1] and costs[1]>costs[2],"each LOD removes work "+spec.id)
			check(costs[0]<1600 and costs[2]<350,"bounded near/far hull geometry "+spec.id+" "+str(costs))
			worst_near=maxi(worst_near,costs[0]);worst_far=maxi(worst_far,costs[2])
		var empty_spec: Dictionary = spec.duplicate(true)
		empty_spec.weaponMounts=[]
		var empty := Recorder.new()
		var stats: Dictionary = Art.draw_boat(empty,empty.project,Art.preview_boat(empty_spec),{"lod":0,"px":float(spec.size)*2.0})
		check(stats.mounts==0 and Art.mounts_of(empty_spec).is_empty(),"empty fitting has no decorative firing mount "+spec.id)
		check(spec==before,"art leaves canonical catalogue untouched "+spec.id)
	# A magnified top-down projection independently measures the longitudinal tip.
	# Magnification keeps intentional subpixel face culling out of this measurement.
	# The tip must agree with combat's native geometry for projectile origins.
	for hull_size in [13.0,18.0,36.0]:
		for kind in ["gun","cannon","rocket","torpedo"]:
			for tier in [1,2,3]:
				var rec := Recorder.new()
				var ctx: Dictionary = {"canvas":rec,"proj":func(p: Vector2,_h: float):return p*4.0,"pos":Vector2.ZERO,"angle":0.0,"size":hull_size,"hull_size":hull_size,"enlargement":1.0,"px":hull_size*4.0,"lod":0,"clock":1.0,"n":0,"npoly":0,"nline":0,"ncirc":0}
				Weapons.draw(ctx,{"kind":kind,"size":tier,"x":0.0,"y":0.0},0.0,Art.palette({},Color.WHITE,false))
				check(absf(rec.max_x/4.0-Geometry.muzzle(kind,hull_size,tier))<0.02,"visible tip agrees with canonical muzzle %s hull %.1f tier %d actual %.4f expected %.4f"%[kind,hull_size,tier,rec.max_x/4.0,Geometry.muzzle(kind,hull_size,tier)])
				check(rec.invalid==0 and rec.count==int(ctx.n),"standalone weapon geometry remains valid "+kind)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--views=") and failures==0:capture_views(world.HULLS,arg.trim_prefix("--views="))
	print("ART WORKSHOP: %d checks, %d failures; max %d near / %d far primitives"%[checks,failures,worst_near,worst_far])
	quit(0 if failures==0 else 1)

func _fit(spec: Dictionary, empty: bool) -> Dictionary:
	if empty:
		var result: Dictionary = spec.duplicate(true)
		result.weaponMounts=[]
		return result
	var fit: Dictionary = Refit.defaults(spec)
	var modules: Array = ["stock_primary","rapid_gun","fire_rocket","light_torpedo"]
	for i in range(fit.weapons.size()):fit.weapons[i]=modules[i]
	var normalized: Dictionary = Refit.normalize(spec,fit)
	check(normalized.ok,"representative gallery uses an actual compatible fitting "+spec.id)
	return Refit.effective_spec(spec,normalized.loadout) if normalized.ok else spec

func capture_views(hulls: Array, target: String) -> void:
	var panels: Array = []
	var chosen: Array = [0,7,17,23]
	var headings: Array = [{"label":"BOW","angle":PI*0.25},{"label":"BEAM","angle":-PI*0.25},{"label":"STERN","angle":-PI*0.75}]
	for index in chosen:
		var spec: Dictionary = hulls[index]
		for empty in [true,false]:
			for heading in headings:
				var rec := Recorder.new()
				rec.capture=true;rec.origin=Vector2(260,245);rec.scale_factor=minf(5.0,80.0/float(spec.size))
				var fitted: Dictionary = _fit(spec,empty)
				var stats: Dictionary = Art.draw_boat(rec,rec.project,Art.preview_boat(fitted,heading.angle),{"lod":0,"px":float(spec.size)*rec.scale_factor,"clock":0.0})
				check(rec.invalid==0,"valid representative capture "+spec.id)
				var mode: String = "EMPTY" if empty else "FITTED"
				panels.append({"id":"%s-%s-%s"%[spec.id,mode,heading.label],"title":"%s | %s | %s"%[spec.name,mode,heading.label],"width":520,"height":380,"background":"#183e4b","stats":stats,"primitives":rec.prims})
	for empty in [true,false]:
		var rec := Recorder.new()
		rec.capture=true;rec.origin=Vector2(260,220);rec.scale_factor=0.80
		for i in range(chosen.size()):
			var fitted: Dictionary = _fit(hulls[chosen[i]],empty)
			var boat: Dictionary = Art.preview_boat(fitted,-0.50+float(i)*0.16)
			boat.x=-115.0 if i%2==0 else 115.0
			boat.y=-90.0 if i<2 else 90.0
			Art.draw_boat(rec,rec.project,boat,{"lod":1,"px":float(fitted.size)*rec.scale_factor})
		check(rec.invalid==0,"valid battle-scale capture")
		var mode: String = "EMPTY" if empty else "FITTED"
		panels.append({"id":"battle-"+mode,"title":"Battle scale | "+mode,"width":520,"height":380,"background":"#183e4b","primitives":rec.prims})
	for kind in ["gun","cannon","rocket","torpedo"]:
		for tier in [1,3]:panels.append(_weapon_panel(kind,tier,1.0,false))
	var recoil_frames: Array = []
	for time in [0.0,0.02,0.04,0.06,0.08,0.12,0.16,0.30]:
		var frame: Dictionary = _weapon_panel("cannon",3,time,true)
		frame.id="recoil-%.2f"%time
		frame.title="Cannon | %.2f seconds after discharge"%time
		recoil_frames.append(frame)
	check(recoil_frames[0].primitives!=recoil_frames[-1].primitives,"new cannon mechanisms participate in visible recoil")
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	FileAccess.open(target,FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"panels":panels,"recoilFrames":recoil_frames,"sourceBase":"e870a2e9b904bee647778f85f0cbfef86fa8f5e8","note":"v0.029 art candidate on unchanged runtime build .028; exact native drawing calls."}))
	print("WORKSHOP VIEWS: %d panels, %d recoil frames -> %s"%[panels.size(),recoil_frames.size(),target])

func _weapon_panel(kind: String, tier: int, time: float, fired: bool) -> Dictionary:
	var rec := Recorder.new()
	rec.capture=true;rec.origin=Vector2(240,245);rec.scale_factor=6.0
	var ctx: Dictionary = {"canvas":rec,"proj":rec.project,"pos":Vector2.ZERO,"angle":0.0,"size":18.0,"hull_size":18.0,"enlargement":1.0,"px":108.0,"lod":0,"clock":time,"shot_clock":time,"shots":{"mount0":0.0} if fired else {},"n":0,"npoly":0,"nline":0,"ncirc":0}
	Weapons.draw(ctx,{"id":"mount0","kind":kind,"size":tier,"x":0.0,"y":0.0},-0.45,Art.palette({},Color("dfbd7d"),false))
	check(rec.invalid==0 and rec.count==int(ctx.n),"valid detailed weapon capture "+kind)
	return {"id":"weapon-%s-%d"%[kind,tier],"title":"%s | tier %d | common physical scale"%[kind.to_upper(),tier],"width":520,"height":380,"background":"#183e4b","primitives":rec.prims}
