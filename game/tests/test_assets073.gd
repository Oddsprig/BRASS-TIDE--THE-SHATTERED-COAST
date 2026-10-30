extends SceneTree
## Root runs this against completed bakes in the frozen source checkout.
## Pixel/receipt coverage only; Root owns the separate visual and motion review.
const Layout=preload("res://scripts/mount_layout.gd")
const Profiles=preload("res://scripts/hull_profiles.gd")
const Sprite=preload("res://scripts/boat_sprite_art.gd")
const Refits=preload("res://scripts/refit.gd")
const HULL_SOURCES=["tools/quality042/models.py","tools/quality042/bake.py","tools/quality049/recipes.py","tools/quality049/catalog.json"]
const WEAPON_SOURCES=["tools/quality042/weapons/bake_weapons.py","tools/quality042/weapons/weapon_models.py","tools/quality042/bake.py","tools/quality042/models.py"]
const VARIANTS={"gun_single":["gun",1,2],"gun_twin":["gun",2,2],"cannon":["cannon",1,2],"rocket_three":["rocket",1,1],"rocket_six":["rocket",3,1],"torpedo_single":["torpedo",1,1],"torpedo_twin":["torpedo",2,1]}
const LEGACY=["tin_skiff","ash_corvette","brasswind_motor_galleon"]
const MIB: int=1024*1024
# Allocation estimates, not measured VRAM. Include a full RGBA8 mip chain.
const TOTAL_BASE_LIMIT: int=384*MIB
const TOTAL_MIP_LIMIT: int=512*MIB
var checks: int=0
var failures: int=0
var started: int=0
var expired: bool=false
var base_bytes: Dictionary={"hull_atlas":0,"portrait":0,"weapon_atlas":0}
var mip_bytes: Dictionary={"hull_atlas":0,"portrait":0,"weapon_atlas":0}

func _initialize() -> void:
	started=Time.get_ticks_msec()
	call_deferred("run")

func check(ok: bool,message: String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("ASSETS073: "+message)
	return ok

func within_deadline() -> bool:
	if expired:return false
	if Time.get_ticks_msec()-started<13000:return true
	expired=true
	check(false,"13s work deadline; remaining assets UNRUN (Root includes startup/cleanup)")
	return false

func read_json(path: String) -> Dictionary:
	if not check(FileAccess.file_exists(path),"JSON exists: "+path):return {}
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if check(parsed is Dictionary,"JSON dictionary: "+path) else {}

func source_path(path: String) -> String:
	return ProjectSettings.globalize_path("res://../"+path)

func source_hash(paths: Array,include_names: bool=false) -> String:
	# Match the two existing bakers' byte ordering; never freeze a new hash here.
	var digest:=HashingContext.new()
	if not check(digest.start(HashingContext.HASH_SHA256)==OK,"source SHA256 starts"):return ""
	for relative in paths:
		var path: String=source_path(str(relative))
		if not check(FileAccess.file_exists(path),"frozen bake source exists: "+str(relative)):return ""
		if include_names:digest.update(str(relative).get_file().to_utf8_buffer())
		digest.update(FileAccess.get_file_as_bytes(path))
	return digest.finish().hex_encode()

func rectangle(value: Array) -> Rect2i:
	return Rect2i(int(value[0]),int(value[1]),int(value[2]),int(value[3]))

func allocation_with_mips(w: int,h: int) -> int:
	# Same RGBA8 accounting as test_roster_art049, without loading GPU textures.
	var total: int=0
	while true:
		total+=w*h*4
		if w==1 and h==1:return total
		w=maxi(1,w>>1);h=maxi(1,h>>1)
	return total

func inspect_pixels(entry: Dictionary,label: String,category: String,portrait: bool=false) -> bool:
	if not within_deadline():return false
	var prefix: String="portrait_" if portrait else ""
	var cell=entry.get(prefix+"cell_px",[])
	var pivot=entry.get(prefix+"pivot_px",[])
	var bounds=([entry.get("portrait_bounds_px",[])] if portrait else entry.get("frame_bounds_px",[]))
	var count: int=1 if portrait else 32
	if not check(Sprite._finite_hull_array(cell,2) and Sprite._finite_hull_array(pivot,2) and bounds is Array and bounds.size()==count,label+" complete cell/pivot/bounds"):return false
	var size:=Vector2i(int(cell[0]),int(cell[1]))
	if not check(size.x>0 and size.y>0 and float(size.x)==float(cell[0]) and float(size.y)==float(cell[1]) and size.x*size.y*count*4<=32*MIB,label+" integral bounded canvas"):return false
	check(float(pivot[0])>0 and float(pivot[0])<size.x and float(pivot[1])>0 and float(pivot[1])<size.y,label+" waterline pivot inside cell")
	if not portrait:check(int(entry.get("headings",0))==32 and int(entry.get("columns",0))==8 and int(entry.get("rows",0))==4,label+" 32 cells in8x4 atlas")
	var path: String=str(entry.get("portrait" if portrait else "atlas",""))
	if not check(FileAccess.file_exists(path),label+" PNG exists"):return false
	check(FileAccess.get_sha256(path)==str(entry.get("portrait_sha256" if portrait else "atlas_sha256","")),label+" actual PNG SHA256 matches manifest")
	var image: Image=Image.load_from_file(ProjectSettings.globalize_path(path))
	if not check(image!=null and not image.is_empty(),label+" actual PNG decodes"):return false
	var expected_size: Vector2i=size if portrait else size*Vector2i(8,4)
	if not check(image.get_size()==expected_size and image.get_format()==Image.FORMAT_RGBA8,label+" actual RGBA8 dimensions"):return false
	base_bytes[category]+=image.get_width()*image.get_height()*4
	mip_bytes[category]+=allocation_with_mips(image.get_width(),image.get_height())
	var directions: Dictionary={}
	for heading in range(count):
		if not within_deadline():return false
		if not check(Sprite._finite_hull_array(bounds[heading],4),label+" numeric alpha rectangle%d"%heading):continue
		var region:=Rect2i(Vector2i.ZERO if portrait else Vector2i(heading%8,heading>>3)*size,size)
		var frame: Image=image.get_region(region)
		var used: Rect2i=frame.get_used_rect()
		check(used==rectangle(bounds[heading]),label+" recorded bounds equal actual alpha%d"%heading)
		check(used.size.x>0 and used.size.y>0 and used.position.x>0 and used.position.y>0 and used.end.x<size.x and used.end.y<size.y,label+" nonempty alpha with all four margins%d"%heading)
		if not portrait:
			var info: Dictionary=Sprite._frame(entry,float(heading)*TAU/32)
			check(int(info.heading)==heading and Rect2i(info.source)==region and Vector2(info.pivot)==Vector2(pivot[0],pivot[1]),label+" actual consumer directional cell%d"%heading)
			var digest:=HashingContext.new()
			digest.start(HashingContext.HASH_SHA256);digest.update(frame.get_data())
			directions[digest.finish().hex_encode()]=true
		frame=null
	if not portrait:check(directions.size()>1,label+" actual directional pixels differ; repeated single image rejected")
	image=null # Free before the next atlas or portrait, with no Texture2D cache.
	return true

func inspect_sockets(hull: Dictionary,entry: Dictionary) -> void:
	var id: String=str(hull.id)
	var actual: Array=Layout.hardpoints(hull)
	var sockets: Array=entry.get("sockets",[])
	if not check(sockets.size()==actual.size(),id+" complete physical mount topology"):return
	for i in range(actual.size()):
		var a: Dictionary=actual[i];var b: Dictionary=sockets[i]
		check(str(a.id)=="mount%d"%i and str(b.get("id",""))==str(a.id) and int(b.get("size",0))==int(a.size),id+" original mount ID/tier%d"%i)
		var xy=b.get("world_xy",[]);var local=b.get("local_xy",[])
		if not check(Sprite._finite_hull_array(xy,2) and Sprite._finite_hull_array(local,2),id+" physical mount coordinates%d"%i):continue
		check(Vector2(xy[0],xy[1]).distance_to(Vector2(a.x,a.y))<.001 and Vector2(local[0],local[1]).distance_to(Vector2(a.localX,a.localY))<.0001,id+" original world/local mount XY%d"%i)
		check(absf(float(b.get("radius",0))-float(a.worldFootprintRadius))<.001 and absf(float(b.get("elevation",0))-float(a.elevation))<.001 and absf(wrapf(float(b.get("angle",0))-float(a.angle),-PI,PI))<.0001,id+" original well footprint/elevation/bearing%d"%i)
		check(is_equal_approx(float(a.arc),TAU if i<2 else PI*1.25) and is_equal_approx(float(a.fixedArc),.9),id+" unchanged chassis arcs%d"%i)
	var fit: Dictionary=Refits.defaults(hull)
	fit.weapons.fill("")
	var bare: Dictionary=Refits.effective_spec(hull,fit)
	check(not bare.is_empty() and Layout.mounts_of(bare).is_empty() and Sprite.hull_entry(bare)==entry,id+" empty actual refit has no guns and preserves authored hull")

func inspect_hull(hull: Dictionary,entry: Dictionary,catalog: Dictionary,source: String) -> bool:
	var id: String=str(hull.id)
	if not check(not entry.is_empty() and Sprite.hull_entry(hull)==entry,id+" actual runtime hull lookup"):return false
	var original: Dictionary=Profiles._PROFILES.get(id,{})
	for key in ["size","role","tier","faction"]:check(hull.get(key)==original.get(key),id+" original catalog "+str(key))
	check(is_equal_approx(float(entry.get("size",0)),float(hull.size)) and float(entry.get("pixels_per_world_unit",0))==2.0 and float(entry.get("portrait_pixels_per_world_unit",0))==4.0,id+" unchanged physical size/densities")
	var receipt: Dictionary=read_json(str(entry.get("atlas","")).get_base_dir().path_join("bake-receipt.json"))
	check(source.length()==64 and str(receipt.get("source_sha256",""))==source and str(entry.get("source_sha256",""))==source and str(entry.get("atlas_source_sha256",""))==source and str(entry.get("portrait_source_sha256",""))==source,id+" atlas/portrait bind current actual bake sources")
	check(str(receipt.get("hull_id",""))==id and int(receipt.get("headings",0))==32 and receipt.get("atlas_sha256")==entry.get("atlas_sha256") and receipt.get("frame_bounds_px")==entry.get("frame_bounds_px"),id+" published atlas receipt identity/hash/bounds")
	var config: Dictionary=receipt.get("canvas_config",{})
	for key in ["cell_px","pivot_px","pixels_per_world_unit","portrait_cell_px","portrait_pivot_px","portrait_pixels_per_world_unit"]:check(config.get(key)==entry.get(key),id+" receipt canvas "+str(key))
	var frames: Array=receipt.get("frames",[])
	if not check(frames.size()==32,id+" complete32 actual source frame receipts"):return false
	for heading in range(32):
		var frame: Dictionary=frames[heading]
		check(frame.get("source_sha256")==source and frame.get("hull_id")==id and int(frame.get("heading",-1))==heading and int(frame.get("density",0))==2 and int(frame.get("aa",0))==2 and str(frame.get("png_sha256","")).length()==64,id+" source/direction/AA frame receipt%d"%heading)
		check(frame.get("canvas_config")==config and frame.get("cell_px")==entry.get("cell_px") and frame.get("pivot_px")==entry.get("pivot_px") and frame.get("sockets")==entry.get("sockets"),id+" frame retains canvas and physical mounts%d"%heading)
		var bbox=frame.get("bounds_px",[])
		if check(Sprite._finite_hull_array(bbox,4),id+" measured source frame bounds%d"%heading):
			check([bbox[0],bbox[1],bbox[2]-bbox[0],bbox[3]-bbox[1]]==entry.frame_bounds_px[heading],id+" source frame bounds bind packed pixels%d"%heading)
	var cell=entry.get("cell_px",[]);var pivot=entry.get("pivot_px",[])
	if not check(Sprite._finite_hull_array(cell,2) and Sprite._finite_hull_array(pivot,2),id+" base canvas metadata"):return false
	check(entry.get("portrait_cell_px")==[int(cell[0])*2,int(cell[1])*2] and entry.get("portrait_pivot_px")==[int(pivot[0])*2,int(pivot[1])*2] and int(entry.get("portrait_heading",-1))==0,id+" normal refit portrait has doubled waterline pivot at heading0")
	check(receipt.get("atlas_size_px")==[int(cell[0])*8,int(cell[1])*4] and int(receipt.get("gpu_rgba8_bytes",0))==int(cell[0])*int(cell[1])*32*4,id+" receipt allocation matches actual canvas")
	var stations: Array=Profiles.stations(hull)
	var physical=entry.get("physical_bounds_world",[])
	if check(Sprite._finite_hull_array(physical,6),id+" finite measured model envelope"):
		check(float(physical[0])<=stations[0].x*float(hull.size)+.01 and float(physical[3])>=stations[-1].x*float(hull.size)-.01,id+" physical model reaches original stern/bow")
	if id not in LEGACY:
		var frozen: Dictionary=catalog.get(id,{})
		for key in ["size","role","tier","faction"]:check(frozen.get(key)==hull.get(key),id+" frozen recipe catalog "+str(key))
		var audit: Dictionary=entry.get("roster049",{})
		check(audit==receipt.get("roster049") and audit.get("installed_guns_in_hull",true)==false and entry.get("installed_guns_in_hull",true)==false and audit.get("physical_size")==hull.size,id+" measured hull remains gun-free at original scale")
		check(float(audit.get("minimum_high_structure_clearance_world",0))>=float(hull.size)*.04,id+" measured high structures clear original mount footprints")
		check(audit.get("stations")==frozen.get("stations"),id+" actual recipe stations retain frozen catalog")
		var authored: Array=audit.get("stations",[])
		if check(authored.size()==stations.size(),id+" full physical station topology"):
			for i in range(stations.size()):check(Sprite._finite_hull_array(authored[i],2) and Vector2(authored[i][0],authored[i][1]).distance_to(stations[i])<.0001,id+" original station%d"%i)
	inspect_sockets(hull,entry)
	if not inspect_pixels(entry,id+" atlas","hull_atlas"):return false
	return inspect_pixels(entry,id+" portrait","portrait",true)

func inspect_weapon(id: String,entry: Dictionary,source: String) -> bool:
	if not check(not entry.is_empty(),id+" actual weapon manifest entry"):return false
	var expected: Array=VARIANTS[id]
	check(str(entry.get("kind",""))==str(expected[0]) and Sprite.weapon_variant({"kind":expected[0],"size":expected[1]})==id,id+" actual installed weapon variant lookup")
	var muzzle: Array={"gun":[8.8,0,4.8],"cannon":[14.2,0,5.8],"rocket":[5.9,0,6.0],"torpedo":[7.9,0,2.8]}[expected[0]]
	check(entry.get("muzzle")==muzzle,id+" unchanged physical muzzle")
	var receipt: Dictionary=read_json("res://assets/boats042/weapons/"+id+"-bake-receipt.json")
	check(source.length()==64 and str(entry.get("source_sha256",""))==source and str(receipt.get("source_sha256",""))==source and receipt.get("variant")==id and int(receipt.get("headings",0))==32,id+" source-bound actual weapon receipt")
	var layers: Array=receipt.get("layers",[])
	if not check(layers.size()==int(expected[2]) and entry.has("moving")== (int(expected[2])==2),id+" complete base/moving layer topology"):return false
	var seen: Dictionary={}
	for report in layers:
		if not within_deadline():return false
		var name: String=str(report.get("layer",""))
		if not check(name in ["base","moving"] and not seen.has(name),id+" unique physical layer"):return false
		seen[name]=true
		var layer: Dictionary=entry.get(name,{})
		check(layer.get("atlas")=="res://assets/boats042/weapons/"+id+"-"+name+".png" and report.get("atlas")==id+"-"+name+".png" and report.get("sha256")==layer.get("atlas_sha256") and report.get("frame_bounds_px")==layer.get("frame_bounds_px"),id+" "+name+" actual published layer binding")
		check(layer.get("cell_px")==[256,192] and layer.get("pivot_px")==[128,128] and float(layer.get("pixels_per_world_unit",0))==6.0 and int(report.get("gpu_rgba8_bytes",0))==2048*768*4,id+" "+name+" unchanged canvas/pivot/density/allocation")
		var hashes: Array=report.get("frame_sha256",[])
		if check(hashes.size()==32,id+" "+name+" all32 packed frame receipts"):
			for hash_value in hashes:check(str(hash_value).length()==64,id+" "+name+" frame SHA256 recorded")
		if not inspect_pixels(layer,id+" "+name,"weapon_atlas"):return false
	check(seen.has("base"),id+" base layer is present")
	return true

func inspect_chart_hulls(hulls: Array) -> int:
	var manifest: Dictionary=read_json("res://assets/campaign054/boats/asset-manifest.json")
	var entries: Dictionary=manifest.get("hulls",{})
	check(manifest.get("schema")=="brass-tide-campaign-boats054-v1" and hulls.size()==36 and entries.size()==36 and manifest.get("installed_weapons_baked",true)==false,"chart schema/all36 hull IDs/no baked installed weapons")
	var inputs: Dictionary=manifest.get("input_sha256",{})
	var paths: Array=["game/scripts/hull_profiles.gd","game/scripts/mount_layout.gd","game/data/world.json","tools/quality049/catalog.json","game/scripts/boat_deck_detail.gd","game/scripts/motor_art.gd","tools/quality054/build_campaign_boats.py"]
	check(inputs.size()==paths.size(),"chart all seven current source input receipts including recipe catalog")
	for relative in paths:
		if not within_deadline():return 0
		var path: String=source_path(str(relative))
		var expected: String=str(inputs.get(relative,""))
		check(FileAccess.file_exists(path) and expected.length()==64 and FileAccess.get_sha256(path)==expected,"chart actual frozen input SHA256: "+str(relative))
	var artifacts: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	check(artifacts.is_empty() or artifacts.is_absolute_path(),"chart existing artifact directory is absolute")
	var completed: int=0
	for hull in hulls:
		if not within_deadline():break
		var id: String=str(hull.id)
		var entry: Dictionary=entries.get(id,{})
		var path: String=str(entry.get("path",""))
		var pixels=entry.get("source_size",[])
		if not check(not entry.is_empty() and path=="res://assets/campaign054/boats/"+id+".svg" and FileAccess.file_exists(path),id+" chart own source SVG exists"):continue
		check(str(entry.get("sha256","")).length()==64 and FileAccess.get_sha256(path)==str(entry.get("sha256","")),id+" chart actual source SVG SHA256")
		if not check(Sprite._finite_hull_array(pixels,2) and float(int(pixels[0]))==float(pixels[0]) and float(int(pixels[1]))==float(pixels[1]) and int(pixels[0])>0 and int(pixels[1])>0 and int(pixels[0])*int(pixels[1])*4<=32*MIB,id+" chart integral bounded source dimensions"):continue
		var image:=Image.new()
		if not check(image.load_svg_from_string(FileAccess.get_file_as_string(path))==OK and not image.is_empty(),id+" chart SVG CPU rasterizes"):continue
		var size:=Vector2i(int(pixels[0]),int(pixels[1]))
		check(image.get_size()==size,id+" chart actual source pixel dimensions")
		var used: Rect2i=image.get_used_rect()
		check(used.size.x>0 and used.size.y>0 and used.position.x>0 and used.position.y>0 and used.end.x<size.x and used.end.y<size.y,id+" chart nonempty alpha with all four margins")
		if artifacts.is_absolute_path():
			check(image.save_png(artifacts.path_join("chart073-"+id+".png"))==OK,id+" chart raster inspection artifact saved")
		image=null
		completed+=1
	check(completed==36,"all36 chart hull SVGs actually decoded and inspected")
	return completed

func run() -> void:
	var manifest: Dictionary=read_json(Sprite.HULL_MANIFEST)
	var weapons: Dictionary=read_json(Sprite.WEAPON_MANIFEST)
	var world: Dictionary=read_json("res://data/world.json")
	var catalog: Dictionary=read_json(source_path("tools/quality049/catalog.json"))
	var hulls: Array=world.get("HULLS",[])
	var entries: Dictionary=manifest.get("hulls",{})
	var variants: Dictionary=weapons.get("weapons",{})
	check(manifest.get("schema")=="brass-tide-boats042-v1" and hulls.size()==36 and entries.size()==36 and catalog.size()==33,"actual36 original hulls and frozen33 recipe catalog")
	var coordinates: Dictionary=manifest.get("coordinates",{})
	check(coordinates.get("installed_guns_in_hull",true)==false and coordinates.get("projection")==[.82,.41,-1.0] and float(coordinates.get("weapon_geometry_base_elevation",0))==9.7,"unchanged gun-free hull/projection/physical deck contract")
	check(weapons.get("schema")=="brass-tide-weapons042-v1" and variants.size()==7 and float(weapons.get("deck_height",0))==9.7 and weapons.get("projection")=={"x":.82,"y":.41,"height":1},"actual seven variants and unchanged shared projection/deck")
	var hull_source: String=source_hash(HULL_SOURCES)
	var weapon_source: String=source_hash(WEAPON_SOURCES,true)
	var chart_count: int=inspect_chart_hulls(hulls)
	var hull_count: int=0;var weapon_count: int=0;var layer_count: int=0
	var seen: Dictionary={}
	for hull in hulls:
		if not within_deadline():break
		check(not seen.has(str(hull.id)) and Profiles.has_hull(str(hull.id)),"unique original hull "+str(hull.id))
		seen[str(hull.id)]=true
		if inspect_hull(hull,entries.get(str(hull.id),{}),catalog,hull_source):hull_count+=1
		Sprite.clear_cache()
	for id in VARIANTS:
		if not within_deadline():break
		if inspect_weapon(str(id),variants.get(id,{}),weapon_source):
			weapon_count+=1;layer_count+=int(VARIANTS[id][2])
	check(hull_count==36 and weapon_count==7 and layer_count==10,"all36 hull atlases/portraits and seven variants/ten layers inspected")
	var total_base: int=int(base_bytes.hull_atlas)+int(base_bytes.portrait)+int(base_bytes.weapon_atlas)
	var total_mips: int=int(mip_bytes.hull_atlas)+int(mip_bytes.portrait)+int(mip_bytes.weapon_atlas)
	check(total_base>0 and total_base<=TOTAL_BASE_LIMIT and total_mips<=TOTAL_MIP_LIMIT,"bounded complete RGBA8 base/mip totals (estimates, not measured VRAM)")
	within_deadline()
	print(JSON.stringify({"fixture":"assets073","checks":checks,"failures":failures,"hulls_inspected":hull_count,"chart_hulls_inspected":chart_count,"weapon_variants_inspected":weapon_count,"weapon_atlases_inspected":layer_count,"complete":failures==0 and not expired,"elapsed_ms":Time.get_ticks_msec()-started,"RGBA8_base_bytes":base_bytes,"RGBA8_with_mips_bytes":mip_bytes,"total_base_bytes":total_base,"total_with_mips_bytes":total_mips,"limits":"Pixel/receipt/physical asset coverage only. No aesthetic, gun-free mesh visual, imported texture residency, motion, refit-screen, performance or gameplay acceptance. Root must view all36 and moving/refit witnesses."}))
	print("ASSETS073: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
