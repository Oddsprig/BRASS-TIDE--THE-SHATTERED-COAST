extends SceneTree
## Actual hit records, renderer geometry and the last-kill cosmetic tail.
const Battle=preload("res://scripts/battle.gd")
const Damage=preload("res://scripts/damage.gd")
const Events=preload("res://scripts/combat_events.gd")
const Feedback=preload("res://scripts/hull_feedback.gd")
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
			for j in range(3):points.append(Vector2(vertices[i+j].x,vertices[i+j].y))
			draw_colored_polygon(points,colors[i])
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

func run() -> void:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var spec: Dictionary=world.HULLS[0]
	test_draw_inputs(spec)
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
