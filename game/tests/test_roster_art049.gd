extends SceneTree
## Source candidate, UNRUN. Root runs after real33 bakes and runtime activation.
## Stream one atlas at a time: no all-roster Texture2D cache or invented pixels.
const Layout=preload("res://scripts/mount_layout.gd")
const Profiles=preload("res://scripts/hull_profiles.gd")
const Sprite=preload("res://scripts/boat_sprite_art.gd")
const Refits=preload("res://scripts/refit.gd")
const Portrait=preload("res://scripts/boat_portrait.gd")
const Trace=preload("res://tests/art042_trace.gd")
const LEGACY=["tin_skiff","ash_corvette","brasswind_motor_galleon"]
var checks: int=0
var failures: int=0
var deadline: int=0
var atlas_bytes: int=0
var portrait_bytes: int=0
var panels: Array=[]

func check(ok: bool,message: String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("ROSTER049: "+message)
	return ok

func _initialize() -> void:
	deadline=Time.get_ticks_msec()+85000
	call_deferred("run")

func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {}
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func rect(value: Array) -> Rect2i:
	return Rect2i(int(value[0]),int(value[1]),int(value[2]),int(value[3]))

func mip_bytes(w: int,h: int) -> int:
	var total: int=0
	while true:
		total+=w*h*4
		if w==1 and h==1:return total
		w=maxi(1,w>>1);h=maxi(1,h>>1)
	return total

func inspect(hull: Dictionary,entry: Dictionary) -> bool:
	var id: String=str(hull.id)
	if not check(not entry.is_empty(),id+" has actual runtime manifest entry"):return false
	check(not Sprite.hull_entry(hull).is_empty(),id+" production lookup admits real authored asset")
	check(is_equal_approx(float(entry.get("size",0)),float(hull.size)),id+" physical size matches catalog")
	check(int(entry.get("headings",0))==32 and int(entry.get("columns",0))==8 and int(entry.get("rows",0))==4,id+" 32 directional cells")
	check(is_equal_approx(float(entry.get("pixels_per_world_unit",0)),2),id+" physical density2")
	var cell: Array=entry.get("cell_px",[])
	var pivot: Array=entry.get("pivot_px",[])
	var bounds: Array=entry.get("frame_bounds_px",[])
	if not check(cell.size()==2 and pivot.size()==2 and bounds.size()==32,id+" complete measured cell/pivot/bounds"):return false
	check(float(pivot[0])>0 and float(pivot[0])<float(cell[0]) and float(pivot[1])>0 and float(pivot[1])<float(cell[1]),id+" finite in-cell waterline pivot")
	var atlas_path: String=str(entry.get("atlas",""))
	if not check(FileAccess.file_exists(atlas_path),id+" actual atlas PNG exists"):return false
	check(FileAccess.get_sha256(atlas_path)==str(entry.get("atlas_sha256","")),id+" actual atlas hash")
	var image: Image=Image.load_from_file(ProjectSettings.globalize_path(atlas_path))
	if not check(image!=null and not image.is_empty(),id+" actual atlas decodes"):return false
	if not check(image.get_size()==Vector2i(int(cell[0])*8,int(cell[1])*4),id+" actual atlas dimensions"):return false
	atlas_bytes+=mip_bytes(image.get_width(),image.get_height())
	for h in range(32):
		if not check(Time.get_ticks_msec()<deadline,"bounded atlas inspection; remaining work UNRUN"):return false
		var info: Dictionary=Sprite.frame_info(hull,float(h)*TAU/32)
		check(not info.is_empty() and int(info.get("heading",-1))==h,id+" actual heading lookup%d"%h)
		var region:=Rect2i((h%8)*int(cell[0]),floori(float(h)/8)*int(cell[1]),int(cell[0]),int(cell[1]))
		var used: Rect2i=image.get_region(region).get_used_rect()
		if not check(bounds[h] is Array and bounds[h].size()==4,id+" actual alpha rectangle%d"%h):continue
		check(used==rect(bounds[h]),id+" measured alpha equals actual pixels%d"%h)
		check(used.size.x>0 and used.size.y>0 and used.position.x>0 and used.position.y>0 and used.end.x<int(cell[0]) and used.end.y<int(cell[1]),id+" nonempty unclipped silhouette%d"%h)
	image=null
	var sockets: Array=entry.get("sockets",[])
	var actual: Array=Layout.hardpoints(hull)
	if check(sockets.size()==actual.size(),id+" all interchangeable empty wells"):
		for i in range(actual.size()):
			var a: Dictionary=actual[i];var b: Dictionary=sockets[i]
			check(str(b.get("id",""))==str(a.id) and int(b.get("size",0))==int(a.size),id+" well ID/tier%d"%i)
			var xy: Array=b.get("world_xy",[]);var local: Array=b.get("local_xy",[])
			if not check(xy.size()==2 and local.size()==2,id+" physical well coordinates%d"%i):continue
			check(Vector2(float(xy[0]),float(xy[1])).distance_to(Vector2(a.x,a.y))<.001,id+" real MountLayout XY%d"%i)
			check(Vector2(float(local[0]),float(local[1])).distance_to(Vector2(a.localX,a.localY))<.0001,id+" real MountLayout local XY%d"%i)
			check(absf(float(b.get("radius",0))-float(a.worldFootprintRadius))<.001 and absf(float(b.get("elevation",0))-float(a.elevation))<.001,id+" real well footprint/elevation%d"%i)
			check(absf(wrapf(float(b.get("angle",0))-float(a.angle),-PI,PI))<.0001,id+" real well outward bearing%d"%i)
	var portrait_path: String=str(entry.get("portrait",""))
	var portrait_cell: Array=entry.get("portrait_cell_px",[])
	var portrait_pivot: Array=entry.get("portrait_pivot_px",[])
	var portrait_bounds: Array=entry.get("portrait_bounds_px",[])
	if not check(FileAccess.file_exists(portrait_path) and portrait_cell.size()==2 and portrait_pivot.size()==2 and portrait_bounds.size()==4,id+" actual portrait and bounds"):return false
	check(FileAccess.get_sha256(portrait_path)==str(entry.get("portrait_sha256","")),id+" portrait hash")
	check(int(portrait_cell[0])==int(cell[0])*2 and int(portrait_cell[1])==int(cell[1])*2 and int(portrait_pivot[0])==int(pivot[0])*2 and int(portrait_pivot[1])==int(pivot[1])*2,id+" portrait retains exact doubled waterline pivot")
	var portrait: Image=Image.load_from_file(ProjectSettings.globalize_path(portrait_path))
	if check(portrait!=null and not portrait.is_empty(),id+" actual portrait decodes"):
		check(portrait.get_size()==Vector2i(int(portrait_cell[0]),int(portrait_cell[1])) and portrait.get_used_rect()==rect(portrait_bounds),id+" actual portrait size and alpha")
		portrait_bytes+=mip_bytes(portrait.get_width(),portrait.get_height())
	portrait=null
	if id in LEGACY:return true
	var receipt: Dictionary=read_json(atlas_path.get_base_dir()+"/bake-receipt.json")
	check(str(receipt.get("source_sha256",""))==str(entry.get("atlas_source_sha256","")) and str(receipt.get("source_sha256","")).length()==64,id+" actual bake source binding")
	check(str(receipt.get("atlas_sha256",""))==str(entry.get("atlas_sha256","")),id+" bake receipt binds actual atlas")
	var audit: Dictionary=entry.get("roster049",{})
	check(audit.get("installed_guns_in_hull",true)==false and float(audit.get("minimum_high_structure_clearance_world",0))>=float(hull.size)*.04,id+" empty wells and roofs outside physical footprints")
	var stations: Array=audit.get("stations",[]);var expected: Array=Profiles.stations(hull)
	if check(stations.size()==expected.size(),id+" complete physical station audit"):
		for i in range(expected.size()):check(Vector2(float(stations[i][0]),float(stations[i][1])).distance_to(expected[i])<.0001,id+" authored station agrees with profile%d"%i)
	var physical: Array=entry.get("physical_bounds_world",[])
	if check(physical.size()==6,id+" actual model envelope recorded"):
		check(float(physical[0])<=expected[0].x*float(hull.size) and float(physical[3])>=expected[-1].x*float(hull.size),id+" physical hull reaches its canonical stern and bow")
	return true

func record_fitted_view(hull: Dictionary) -> void:
	var view=Portrait.new()
	view.set_spec(Refits.effective_spec(hull,Refits.defaults(hull)))
	view.show_sockets=true
	var canvas=Trace.Canvas.new()
	view.draw_contents(canvas,Vector2(390,245))
	check(canvas.invalid==0 and canvas.texture_draws>0,str(hull.id)+" actual fitted portrait submits valid authored textures")
	panels.append(canvas.panel("roster-"+str(hull.id),str(hull.name)+" / actual normal fitting view",Vector2(390,245)))
	view.free()
	# Draw records retain only values/paths. Avoid keeping36 atlases resident in QA.
	Sprite.clear_cache()

func run() -> void:
	var world: Dictionary=read_json("res://data/world.json")
	var manifest: Dictionary=read_json(Sprite.HULL_MANIFEST)
	var hulls: Array=world.get("HULLS",[])
	check(hulls.size()==36 and manifest.get("hulls",{}).size()==36,"actual full36 roster without filler")
	var completed: int=0
	for hull in hulls:
		if not check(Time.get_ticks_msec()<deadline,"bounded roster inspection; remaining hulls UNRUN"):break
		if inspect(hull,manifest.get("hulls",{}).get(str(hull.id),{})):
			completed+=1
			record_fitted_view(hull)
	check(completed==36,"all36 actually inspected")
	var artifacts: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if artifacts.is_absolute_path():
		var file=FileAccess.open(artifacts.path_join("roster049-trace.json"),FileAccess.WRITE)
		check(file!=null,"existing draw-call replay artifact is writable")
		if file!=null:file.store_string(JSON.stringify({"schema":"brass-tide-art042-trace-v1","checks":checks,"failures":failures,"complete":completed==36 and failures==0,"panels":panels,"limits":"Actual normal fitted Portrait drawing calls; CPU replay needs Root visual review. No GPU/FPS/audio/motion/collision acceptance."}))
	print(JSON.stringify({"fixture":"roster_art049","checks":checks,"failures":failures,"hulls_inspected":completed,"atlas_RGBA8_with_mips":atlas_bytes,"portrait_RGBA8_with_mips":portrait_bytes,"limits":"Asset/mount/bounds coverage only; no visual quality, motion, FPS or collision acceptance"}))
	print("ROSTER049: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
