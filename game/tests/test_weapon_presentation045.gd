extends SceneTree
## Root-only native fixture: records production draws and actual Battle._fire.
## A valid texture trace proves submission/geometry, never motion or visual taste.
const Art=preload("res://scripts/boat_art.gd")
const Sprite=preload("res://scripts/boat_sprite_art.gd")
const Geometry=preload("res://scripts/weapon_geometry.gd")
const Layout=preload("res://scripts/mount_layout.gd")
const Refit=preload("res://scripts/refit.gd")
const Portrait=preload("res://scripts/boat_portrait.gd")
const Feedback=preload("res://scripts/hull_feedback.gd")
const Battle=preload("res://scripts/battle.gd")
const Tactical=preload("res://scripts/tactical_runtime.gd")
const Damage=preload("res://scripts/damage.gd")
const Trace=preload("res://tests/art042_trace.gd")
var checks: int=0
var failures: int=0
var manifest: Dictionary={}
var images: Dictionary={}

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("WEAPON045: "+message)

func _initialize() -> void:call_deferred("run")

func weapons(rec) -> Array:
	return rec.textures().filter(func(p):return "/weapons/" in str(p.path))

func texture_point(p: Dictionary,pixel: Vector2) -> Vector2:
	var points: Array=p.pts
	var origin:=Vector2(points[0][0],points[0][1])
	return origin+(Vector2(points[1][0],points[1][1])-origin)*pixel.x/float(p.src[2])+(Vector2(points[3][0],points[3][1])-origin)*pixel.y/float(p.src[3])

func record(boat: Dictionary,time: float=10.0,combat: bool=true,cached: bool=true):
	var rec=Trace.Canvas.new()
	rec.origin=Vector2(240,180);rec.scale_factor=1.0
	Art.draw_boat(rec,rec.project,boat,{"cache":cached,"lod":0,"px":float(boat.spec.size)*0.82,"combat":combat,"clock":1000.0,"battle_clock":time})
	check(rec.invalid==0 and rec.transform==Transform2D.IDENTITY,str(boat.spec.id)+" finite calls and restored canvas transform")
	return rec

func preview(spec: Dictionary):
	var portrait=Portrait.new()
	portrait.show_sockets=true;portrait.show_arcs=true
	portrait.set_spec(spec)
	var frame: Dictionary=portrait.framing(spec,Vector2(390,245))
	var rec=Trace.Canvas.new()
	rec.origin=frame.origin;rec.scale_factor=float(frame.scale)
	portrait.draw_contents(rec,Vector2(390,245))
	var sockets: Array=Layout.hardpoints(spec)
	check(portrait._socket_points.size()==sockets.size(),str(spec.id)+" normal workshop keeps every clickable socket")
	for i in range(mini(sockets.size(),portrait._socket_points.size())):
		check(Vector2(portrait._socket_points[i]).distance_to(rec.project(Vector2(sockets[i].x,sockets[i].y),10.0))<0.01,str(spec.id)+" workshop socket has physical mount origin")
	check(rec.invalid==0 and rec.transform==Transform2D.IDENTITY,str(spec.id)+" finite normal workshop draws")
	portrait.free()
	return rec

## Inspect actual source rectangles and transformed quad points. The expected
## muzzle uses the authored manifest and independent shared gameplay geometry.
func check_layers(rec,boat: Dictionary,label: String) -> void:
	var drawn: Array=weapons(rec)
	var cursor: int=0
	for mount in boat.spec.get("weaponMounts",[]):
		var variant: String=Sprite.weapon_variant(mount)
		var entry: Dictionary=manifest.weapons.get(variant,{})
		check(not entry.is_empty(),label+" known authored variant "+variant)
		if entry.is_empty():continue
		var bearing: float=float(boat.angle)+float(boat.get("localAimAngles",{}).get(str(mount.id),mount.angle))
		var unit: float=Geometry.unit(float(boat.spec.size),int(mount.size))
		var muzzle: Array=entry.muzzle
		check(absf(float(muzzle[0])*unit-Geometry.muzzle(str(mount.kind),float(boat.spec.size),int(mount.size)))<0.001,label+" canonical muzzle distance")
		var height: float=9.7+float(muzzle[2])*unit
		if str(mount.kind)!="torpedo":check(absf(height-Geometry.height(str(mount.kind),float(boat.spec.size),int(mount.size)))<0.001,label+" canonical firing height")
		else:check(is_zero_approx(Geometry.height("torpedo",float(boat.spec.size),int(mount.size))),label+" torpedo projectile stays at waterline beneath deck tube")
		var at: Vector2=Vector2(boat.x,boat.y)+Vector2(mount.x,mount.y).rotated(float(boat.angle))
		for layer in ["base","moving"]:
			if not entry.has(layer):continue
			var part: Dictionary=entry[layer]
			check(cursor<drawn.size(),label+" actual "+variant+" "+layer+" draw exists")
			if cursor>=drawn.size():continue
			var p: Dictionary=drawn[cursor];cursor+=1
			var headings: int=int(part.headings)
			var index: int=posmod(int(roundf(bearing/TAU*headings)),headings)
			var quantized: float=float(index)*TAU/headings
			var expected: Array=[float((index%int(part.columns))*int(part.cell_px[0])),float(floori(float(index)/int(part.columns))*int(part.cell_px[1])),float(part.cell_px[0]),float(part.cell_px[1])]
			check(str(p.path)==str(part.atlas) and p.src==expected,label+" real "+variant+" "+layer+" atlas region matches live bearing")
			var pivot:=Vector2(part.pivot_px[0],part.pivot_px[1])
			var density: float=float(part.pixels_per_world_unit)
			var xy: Vector2=Vector2.from_angle(quantized)*float(muzzle[0])
			var tip: Vector2=pivot+Vector2((xy.x-xy.y)*0.82,(xy.x+xy.y)*0.41-float(muzzle[2]))*density
			check(texture_point(p,tip).distance_to(rec.project(at+Vector2.from_angle(bearing)*Geometry.muzzle(str(mount.kind),float(boat.spec.size),int(mount.size)),height))<0.02,label+" "+layer+" physical muzzle and continuous heading agree")
			check(texture_point(p,pivot-Vector2(0,float(muzzle[2])*density)).distance_to(rec.project(at,height))<0.02,label+" "+layer+" firing-plane origin agrees with mount ID/anchor")
	check(cursor==drawn.size(),label+" no duplicate or decorative weapon textures")

func check_visible(rec,label: String) -> void:
	for p in weapons(rec):
		var path: String=str(p.path)
		if not images.has(path):images[path]=Image.load_from_file(ProjectSettings.globalize_path(path))
		var image: Image=images[path]
		check(image!=null and not image.is_empty(),label+" actual atlas PNG exists")
		if image==null or image.is_empty():continue
		var used: Rect2i=image.get_region(Rect2i(int(p.src[0]),int(p.src[1]),int(p.src[2]),int(p.src[3]))).get_used_rect()
		check(used.size.x>0 and used.size.y>0,label+" actual atlas cell contains visible pixels")
		var inside: bool=true
		for corner in [used.position,used.position+Vector2i(used.size.x,0),used.end,used.position+Vector2i(0,used.size.y)]:
			inside=inside and Rect2(8,42,374,195).grow(0.2).has_point(texture_point(p,Vector2(corner)))
		check(inside,label+" visible weapon pixels stay inside normal390x245 workshop")

func inspect_roster(hulls: Array) -> void:
	check(hulls.size()==36,"all36 catalogue hulls are inspected")
	for raw in hulls:
		var original: Dictionary=raw.duplicate(true)
		var spec: Dictionary=Refit.effective_spec(raw,Refit.defaults(raw))
		var boat: Dictionary=Art.preview_boat(spec,0.061)
		boat.x=13.0;boat.y=-8.0;boat.ammo=80.0
		var before: Dictionary=boat.duplicate(true)
		var rec=record(boat)
		check_layers(rec,boat,str(raw.id)+" normal battle")
		var has_hull: bool=not Sprite.hull_entry(raw).is_empty()
		check(rec.textures().size()-weapons(rec).size()==(1 if has_hull else 0),str(raw.id)+" hull art path is preserved")
		check(has_hull or rec.mesh_draws>0,str(raw.id)+" fallback hull retains cached geometry")
		var refit=preview(spec)
		check_layers(refit,Art.preview_boat(spec,0.0),str(raw.id)+" normal workshop")
		check_visible(refit,str(raw.id))
		var fit: Dictionary=Refit.defaults(raw);fit.weapons.fill("")
		var empty: Dictionary=Refit.effective_spec(raw,fit)
		check(empty.has("weaponMounts") and empty.weaponMounts.is_empty(),str(raw.id)+" actual fitting permits empty weapons")
		check(weapons(record(Art.preview_boat(empty))).is_empty() and weapons(preview(empty)).is_empty(),str(raw.id)+" empty battle/workshop have no weapon layer")
		check(boat==before and raw==original,str(raw.id)+" rendering preserves complete boat/catalogue state")

func inspect_variants(hull: Dictionary) -> void:
	var cases: Array=[["rapid_gun","gun_single"],["heavy_gun","gun_twin"],["heavy_cannon","cannon"],["fire_rocket","rocket_three"],["salvo_rocket","rocket_six"],["light_torpedo","torpedo_single"],["heavy_torpedo","torpedo_twin"]]
	for item in cases:
		var fit: Dictionary=Refit.defaults(hull);fit.weapons.fill("");fit.weapons[0]=item[0]
		var normalized: Dictionary=Refit.normalize(hull,fit)
		check(bool(normalized.ok),str(hull.id)+" compatible "+str(item[0])+" fitting")
		if not normalized.ok:continue
		var spec: Dictionary=Refit.effective_spec(hull,normalized.loadout)
		var mount: Dictionary=spec.weaponMounts[0]
		check(Sprite.weapon_variant(mount)==str(item[1]),str(hull.id)+" seven mechanisms retain distinct module selection")
		var aim: Dictionary=Layout.weapon_aim(Layout.hardpoints(hull)[0],str(mount.kind))
		check(is_equal_approx(float(mount.arc),float(aim.arc)),str(hull.id)+" real Layout arc retained")
		if str(mount.kind)=="cannon":check(is_equal_approx(float(mount.arc),PI*0.75),str(hull.id)+"044 heavy forward cannon has135degree arc")
		var boat: Dictionary=Art.preview_boat(spec,-2.4)
		boat.localAimAngles={"mount0":float(mount.angle)+float(mount.arc)*0.5}
		check_layers(record(boat),boat,str(hull.id)+" arc boundary "+str(item[1]))
		check_visible(preview(spec),str(hull.id)+" "+str(item[1]))

func inspect_recoil(hull: Dictionary,module: String) -> void:
	var fit: Dictionary=Refit.defaults(hull);fit.weapons.fill("")
	fit.weapons[0]=module;fit.weapons[1]="rapid_gun"
	var spec: Dictionary=Refit.effective_spec(hull,fit)
	check(not spec.is_empty(),str(hull.id)+" two-mount recoil fitting is legal")
	if spec.is_empty():return
	var ship: Dictionary=Damage.create_ship(spec)
	var target: Dictionary=Damage.create_ship(hull,{"ammo":0.0})
	var battle: Dictionary=Battle.create({"fleet":[ship],"enemyFleet":[target],"seed":450})
	battle.time=10.0
	ship.x=500.0;ship.y=850.0;ship.angle=0.061
	target.x=750.0;target.y=850.0
	ship.weaponCooldowns[1]=99.0
	# Manual shots still require the production terrain, traffic and lane budget.
	Tactical.begin(battle,1.0/60.0,{"manual":true})
	Tactical.after_motion(battle)
	var ammo: float=float(ship.ammo)
	Battle._fire(battle,ship,Vector2(target.x,target.y))
	var fired_once: bool=battle.projectiles.size()==1 and is_equal_approx(float(ship.get("mountShotTimes",{}).get("mount0",-1.0)),10.0)
	check(fired_once,str(hull.id)+" actual shot timestamps the fired mount")
	check(is_equal_approx(float(ship.ammo),ammo-float(spec.weaponMounts[0].ammoCost)),str(hull.id)+" actual shot consumes real ammunition once")
	if not fired_once:return
	var before: Dictionary=ship.duplicate(true)
	var idle: Dictionary=ship.duplicate(true);idle.mountShotTimes={}
	var idle_rec=record(idle)
	check_layers(idle_rec,idle,str(hull.id)+" both normal mount origins/headings")
	var rest: Array=weapons(idle_rec)
	var fired: Array=weapons(record(ship))
	check(rest.size()==4 and fired.size()==4,str(hull.id)+" separate moving/base layers on both mounts")
	if rest.size()==4 and fired.size()==4:
		check(rest[0]==fired[0] and rest[2]==fired[2] and rest[3]==fired[3],str(hull.id)+" fired cradle and other mount stay fixed")
		var mount: Dictionary=spec.weaponMounts[0]
		var bearing: float=float(ship.angle)+float(ship.localAimAngles.mount0)
		var xy: Vector2=Vector2.from_angle(bearing)*(-1.1*Geometry.unit(float(spec.size),int(mount.size)))
		var shift:=Vector2((xy.x-xy.y)*0.82,(xy.x+xy.y)*0.41)
		check((texture_point(fired[1],Vector2.ZERO)-texture_point(rest[1],Vector2.ZERO)).distance_to(shift)<0.02,str(hull.id)+" actual moving assembly recoils along barrel only")
		var halfway: Array=weapons(record(ship,10.08))
		check(halfway.size()==4 and (texture_point(halfway[1],Vector2.ZERO)-texture_point(rest[1],Vector2.ZERO)).distance_to(shift*0.5)<0.02,str(hull.id)+" recoil recovers from battle time independent of display clock")
	check(weapons(record(ship,10.20))==rest,str(hull.id)+" recoil fully recovers")
	check(weapons(record(ship,9.99))==rest and weapons(record(ship,10.0,false))==rest,str(hull.id)+" future shots and noncombat previews do not recoil")
	var empty: Dictionary=idle.duplicate(true);empty.ammo=0.0
	check(weapons(record(empty))==rest,str(hull.id)+" empty ammo alone cannot invent firing")
	var disabled: Dictionary=idle.duplicate(true)
	disabled.moduleCondition={"version":1,"items":{"weapon-fixture":{"family":"weapons","location":"mount0","status":"disabled","hp":0.0}}}
	var marks: Array=Feedback.equipment_marks(disabled,Art.mounts_of(spec))
	check(marks.size()==1 and str(marks[0].location)=="mount0" and str(marks[0].status)=="disabled",str(hull.id)+" real condition record keeps disabled mount mark")
	var damaged=record(disabled)
	check(weapons(damaged)==rest and damaged.prims!=record(idle).prims,str(hull.id)+" disabled cross overlays the installed mechanism")
	check(ship==before,str(hull.id)+" every recoil draw preserves ammo/events/condition/aim")

func inspect_fallbacks(hull: Dictionary) -> void:
	var fit: Dictionary=Refit.defaults(hull);fit.weapons.fill("");fit.weapons[0]="heavy_cannon"
	var boat: Dictionary=Art.preview_boat(Refit.effective_spec(hull,fit))
	var spec: Dictionary=boat.spec.duplicate(true);spec.weaponMounts=[]
	var empty=record(Art.preview_boat(spec),10.0,true,false)
	for layer in ["base","moving"]:
		var path: String=str(manifest.weapons.cannon[layer].atlas)
		var saved=Sprite._textures.get(path)
		Sprite._textures[path]=null
		var rec=record(boat,10.0,true,false)
		check(weapons(rec).is_empty() and rec.prims.size()>empty.prims.size(),str(hull.id)+" missing "+layer+" atlas draws mechanical weapon without partial sprites")
		Sprite._textures[path]=saved
	var live: Dictionary=Sprite._manifests[Sprite.WEAPON_MANIFEST]
	var moving: Dictionary=live.weapons.cannon.moving
	var oversized: Dictionary=moving.duplicate(true);oversized.cell_px=[9999,9999]
	live.weapons.cannon.moving=oversized
	var partial=record(boat,10.0,true,false)
	check(weapons(partial).is_empty() and partial.prims.size()>empty.prims.size(),str(hull.id)+" out-of-bounds moving cell refuses both layers before drawing")
	live.weapons.cannon.moving=moving
	# The atlas table must also follow edits to the very same source Array.
	var restored: Array=weapons(record(boat,10.0,true,false))
	var width=moving.cell_px[0]
	moving.cell_px[0]=9999
	check(weapons(record(boat,10.0,true,false)).is_empty(),str(hull.id)+" in-place atlas dimension edit invalidates warm readiness")
	moving.cell_px[0]=width
	check(weapons(record(boat,10.0,true,false))==restored,str(hull.id)+" restoring atlas dimensions restores the exact warm layers")
	var rec=Trace.Canvas.new()
	var topdown=func(p: Vector2,_h: float):return p*2.0
	Art.draw_boat(rec,topdown,boat,{"lod":0,"px":float(hull.size)*2.0})
	check(rec.texture_draws==0 and rec.invalid==0 and not rec.prims.is_empty(),str(hull.id)+" nonisometric chart retains mechanical art")
	rec=Trace.Canvas.new()
	Art.draw_boat(rec,rec.project,boat,{"lod":0,"px":float(hull.size)*2.0,"enlargement":1.4})
	check(rec.texture_draws==0 and rec.invalid==0 and not rec.prims.is_empty(),str(hull.id)+" anisotropic legacy enlargement retains mechanical art")
	var bare=preview(spec)
	check(weapons(bare).is_empty(),str(hull.id)+" bare sockets remain visible without fitted weapons")

func inspect_draw_preparation(hull: Dictionary) -> void:
	var fit: Dictionary=Refit.defaults(hull);fit.weapons.fill("")
	fit.weapons[0]="heavy_cannon";fit.weapons[1]="rapid_gun"
	var spec: Dictionary=Refit.effective_spec(hull,fit)
	var boat: Dictionary=Art.preview_boat(spec,0.061)
	var before: Dictionary=boat.duplicate(true)
	var entry: Dictionary=Sprite.hull_entry(spec)
	for heading in range(32):
		var angle: float=float(heading)*TAU/32+0.001
		var ready: Dictionary=Sprite._ready_frame(entry,angle)
		var actual: Dictionary=ready.duplicate();actual.erase("texture")
		check(actual==Sprite._frame(entry,angle) and Sprite._cell_ready(ready),"prepared hull rectangle/pivot/density exactly match reference heading%d"%heading)
	var exposed: Dictionary=Sprite.frame_info(spec,0.061)
	exposed.source=Rect2(-999,-999,1,1)
	check(Sprite.frame_info(spec,0.061).source!=exposed.source,"public frame inspection stays mutable and cannot alter prepared rectangles")
	var rec=Trace.Canvas.new();rec.origin=Vector2(240,180);rec.scale_factor=1.0
	var calls: Array=[0]
	var project=func(p: Vector2,h: float):
		calls[0]+=1
		return rec.project(p,h)
	var opts: Dictionary={"lod":0,"px":float(spec.size)*0.82,"combat":true,"clock":1000.0,"battle_clock":10.0}
	Art.draw_boat(rec,project,boat,opts)
	var mounts: Array=Art.mounts_of(spec)
	check(calls[0]==5+mounts.size() and rec.invalid==0,"one four-probe projection check per boat plus actual hull/mount origins")
	# Direct callers retain independent projection validation. Compare their
	# actual transformed quads with the shared per-draw path, not a mock image.
	var direct=Trace.Canvas.new();direct.origin=rec.origin;direct.scale_factor=rec.scale_factor
	var ctx: Dictionary={"canvas":direct,"proj":direct.project,"pos":Vector2.ZERO,"angle":float(boat.angle),"size":float(spec.size),"hull_size":float(spec.size),"enlargement":1.0,"n":0}
	check(Sprite.draw_hull(ctx,spec),"standalone hull caller keeps its checked projection path")
	for mount in mounts:
		check(Sprite.draw_weapon(ctx,mount,float(boat.angle)+float(mount.angle)),"standalone weapon caller keeps its checked projection path")
	check(direct.prims==rec.prims,"sharing projection and ready cells preserves every actual transformed draw")
	var warm: Array=rec.prims.duplicate(true)
	check(record(boat).prims==warm,"warm atlas frames preserve the complete cold drawing trace")
	rec.prims.clear();rec.scale_factor=1.7;rec.origin+=Vector2(21,-13);calls[0]=0
	Art.draw_boat(rec,project,boat,opts)
	check(calls[0]==5+mounts.size() and rec.prims!=warm,"same callable rechecks changed camera and scale on the next draw")
	check_layers(rec,boat,"changed per-draw projection")
	# A custom heading count is checked per call, outside the32-frame table.
	var custom: Dictionary=entry.duplicate(true);custom.headings=16
	var custom_ready: Dictionary=Sprite._ready_frame(custom,1.0)
	var custom_info: Dictionary=custom_ready.duplicate();custom_info.erase("texture")
	check(custom_info==Sprite._frame(custom,1.0) and Sprite._cell_ready(custom_ready),"nonstandard atlas headings retain checked reference geometry")
	var incomplete: Dictionary=Sprite._frame(entry,0.0);incomplete.source=Rect2(0,0,99999,99999)
	var rejected=Trace.Canvas.new();ctx.canvas=rejected
	check(not Sprite._draw_cell(ctx,incomplete,Vector2.ZERO,1.0) and rejected.prims.is_empty(),"public cell submission still refuses invalid source rectangles")
	Sprite.clear_cache()
	check(Sprite._atlas_frames.is_empty() and Sprite._textures.is_empty(),"clear_cache releases prepared atlas frames and their texture references")
	check(record(boat).prims==warm and boat==before,"cache clearing reloads identical art without changing any boat state")

# The checked public scale subtracts projected float32 positions. Its roundoff
# varies by boat; compare every quad within the existing .02px muzzle tolerance,
# while keeping layer order, sources, colors, flags and other primitives exact.
func same_batch_quads051(actual: Array, reference: Array) -> bool:
	if actual.size()!=reference.size():return false
	for i in range(actual.size()):
		var a: Dictionary=actual[i];var b: Dictionary=reference[i]
		if a.t!=b.t:return false
		if a.t!="texture":
			if a!=b:return false
			continue
		var af: Dictionary=a.duplicate();var bf: Dictionary=b.duplicate()
		for field in ["pts","rect"]:af.erase(field);bf.erase(field)
		if af!=bf or a.pts.size()!=4 or b.pts.size()!=4:return false
		for j in range(4):
			if Vector2(a.pts[j][0],a.pts[j][1]).distance_to(Vector2(b.pts[j][0],b.pts[j][1]))>0.02:return false
			if absf(float(a.rect[j])-float(b.rect[j]))>0.02:return false
	return true

func inspect_batch_camera051(hull: Dictionary) -> void:
	var fit: Dictionary=Refit.defaults(hull);fit.weapons.fill("")
	fit.weapons[0]="heavy_cannon";fit.weapons[1]="rapid_gun"
	var spec: Dictionary=Refit.effective_spec(hull,fit)
	var boats: Array=[]
	for i in range(3):
		var boat: Dictionary=Art.preview_boat(spec,0.061+float(i)*0.41)
		boat.localAimAngles={"mount0":0.6-float(i)*0.2,"mount1":-0.4}
		boat.mountShotTimes={"mount0":9.97};boat.vx=37.0;boat.fire=float(i)*12.0
		boat.visualHits=[{"x":-0.2,"y":0.1,"at":9.98,"power":0.7,"material":"metal","section":"deck","angle":0.3}]
		boats.append(boat)
	var previous: Array=[]
	for camera_case in [[Vector2(480,360),Vector2.ZERO,1.0],[Vector2(1280,720),Vector2(1300,900),0.65],[Vector2(1600,900),Vector2(1234.5,845.75),1.7]]:
		var view: Rect2=Rect2(Vector2.ZERO,camera_case[0])
		var camera: Vector2=camera_case[1];var scale: float=float(camera_case[2])
		var batch:=Art._BattleDraw051.new(view,camera,scale)
		var combined=Trace.Canvas.new();var reference=Trace.Canvas.new()
		reference.origin=view.size*0.5;reference.camera=camera;reference.scale_factor=scale
		check(batch.view==view,"batch viewport is the current draw snapshot")
		for i in range(boats.size()):
			var boat: Dictionary=boats[i]
			boat.x=camera.x-33.0+float(i)*57.0;boat.y=camera.y+17.0-float(i)*23.0
			var before: Dictionary=boat.duplicate(true)
			var opts: Dictionary={"cache":true,"lod":i,"px":float(spec.size)*scale*0.82,"combat":true,"clock":10.0,"battle_clock":10.0}
			var shared: Dictionary=Art._draw_battle_boat051(combined,batch,boat,opts)
			var checked: Dictionary=Art.draw_boat(reference,reference.project,boat,opts)
			check(shared==checked and bool(shared.authored_hull),"batch retains public layer/count/LOD result for each boat")
			check(boat==before,"shared camera leaves aim, recoil, scars and fire state untouched")
			check(batch.projector.call(Vector2(boat.x,boat.y),9.7)==reference.project(Vector2(boat.x,boat.y),9.7),"batch mount plane uses the exact current camera projection")
		check(combined.invalid==0 and reference.invalid==0 and combined.transform==Transform2D.IDENTITY,"batch submission restores transforms and finite geometry")
		check(same_batch_quads051(combined.prims,reference.prims),"all batch quads/layers/materials and live feedback match the checked public drawing")
		var warm=Trace.Canvas.new()
		for i in range(boats.size()):
			Art._draw_battle_boat051(warm,batch,boats[i],{"cache":true,"lod":i,"px":float(spec.size)*scale*0.82,"combat":true,"clock":10.0,"battle_clock":10.0})
		check(warm.prims==combined.prims and warm.invalid==0,"warm batch is an exact complete drawing replay")
		check(previous.is_empty() or previous!=combined.prims,"next battle draw uses its changed camera, viewport and scale")
		previous=combined.prims.duplicate(true)
		# A prior affine batch cannot authorize sprites for another callable, even
		# if a caller puts a batch or a claimed scale into its ordinary opts.
		var custom=func(p: Vector2,h: float) -> Vector2:return reference.project(p,h)+Vector2((p.x-camera.x)*0.12,h*0.25)
		var control=Trace.Canvas.new();var spoofed=Trace.Canvas.new()
		var opts: Dictionary={"cache":true,"lod":0,"px":float(spec.size)*scale*0.82,"combat":true,"clock":10.0,"battle_clock":10.0}
		Art.draw_boat(control,custom,boats[0],opts)
		opts.battle_draw051=batch;opts.screen_scale=scale
		Art.draw_boat(spoofed,custom,boats[0],opts)
		check(control.texture_draws==0 and spoofed.prims==control.prims and spoofed.invalid==0,"public custom projector keeps checked mechanical fallback after a shared batch")

func run() -> void:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	manifest=JSON.parse_string(FileAccess.get_file_as_string(Sprite.WEAPON_MANIFEST))
	inspect_roster(world.HULLS)
	for id in ["brasswind_motor_galleon","maiden_dreadnought"]:
		var found: Array=world.HULLS.filter(func(h):return str(h.id)==id)
		check(found.size()==1,"representative actual hull exists: "+id)
		if found.size()!=1:continue
		inspect_variants(found[0])
		inspect_recoil(found[0],"rapid_gun")
		inspect_recoil(found[0],"heavy_cannon")
		inspect_fallbacks(found[0])
		if id=="brasswind_motor_galleon":
			inspect_draw_preparation(found[0])
			inspect_batch_camera051(found[0])
	print("WEAPON045: %d checks, %d failures; native texture/geometry/event fixture only"%[checks,failures])
	quit(0 if failures==0 else 1)
