extends SceneTree
## One bounded v042 art fixture. Root runs after the real bakes are imported.
## Records production BoatArt + the normal refit portrait factory, never mocks.
const Main=preload("res://scripts/main.gd")
const Lab=preload("res://scripts/fleet_lab.gd")
const Refit=preload("res://scripts/refit.gd")
const RefitUI=preload("res://scripts/refit_ui.gd")
const Portrait=preload("res://scripts/boat_portrait.gd")
const Art=preload("res://scripts/boat_art.gd")
const Sprite=preload("res://scripts/boat_sprite_art.gd")
const Trace=preload("res://tests/art042_trace.gd")
const IDS: Array=["tin_skiff","ash_corvette","brasswind_motor_galleon"]
var checks: int=0
var failures: int=0
var panels: Array=[]
var images: Dictionary={}

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("ART042: "+message)

func subset(rec,needle: String) -> Array:
	return rec.textures().filter(func(p):return needle in str(p.path))

## Bounds use actual alpha pixels from the exact PNG region drawn by BoatArt.
## Transparent atlas padding may extend beyond a panel; visible art may not.
func check_visible(rec,box: Rect2,label: String) -> void:
	check(rec.invalid==0,label+" finite native draw calls")
	for p in rec.textures():
		var path: String=str(p.path)
		if not images.has(path):images[path]=Image.load_from_file(ProjectSettings.globalize_path(path))
		var image: Image=images[path]
		check(image!=null and not image.is_empty(),label+" real source PNG "+path)
		if image==null or image.is_empty():continue
		var s: Array=p.src
		var used: Rect2i=image.get_region(Rect2i(int(s[0]),int(s[1]),int(s[2]),int(s[3]))).get_used_rect()
		check(used.size.x>0 and used.size.y>0,label+" visible nonempty sprite "+path)
		var origin: Vector2=Vector2(p.pts[0][0],p.pts[0][1])
		var ex: Vector2=Vector2(p.pts[1][0],p.pts[1][1])-origin
		var ey: Vector2=Vector2(p.pts[3][0],p.pts[3][1])-origin
		var inside: bool=true
		for corner in [used.position,used.position+Vector2i(used.size.x,0),used.end,used.position+Vector2i(0,used.size.y)]:
			var point: Vector2=origin+ex*float(corner.x)/float(s[2])+ey*float(corner.y)/float(s[3])
			inside=inside and box.grow(0.2).has_point(point)
		check(inside,label+" visible sprite stays in panel "+path)

func boat_canvas(boat: Dictionary):
	var rec=Trace.Canvas.new()
	rec.scale_factor=1.3
	rec.origin=Vector2(240,170)
	Art.draw_boat(rec,rec.project,boat,{"cache":true,"lod":0,"px":float(boat.spec.size)*rec.scale_factor*0.82,"combat":true,"clock":0.0,"battle_clock":0.0})
	return rec

func inspect_boat(world: Dictionary,ship: Dictionary,ui) -> void:
	var id: String=str(ship.spec.id)
	var before: Dictionary=ship.duplicate(true)
	var spec: Dictionary=Lab.hull(world,id)
	var info: Dictionary=Sprite.frame_info(ship.spec,float(ship.angle))
	var audit: Dictionary=Sprite.audit(ship.spec)
	check(bool(audit.get("texture_ready",false)),id+" actual baked atlas is loaded")
	check(not info.is_empty(),id+" directional frame exists")
	var probe: Dictionary=ship.duplicate(true)
	probe.x=0.0;probe.y=0.0
	var rec=boat_canvas(probe)
	var hulls: Array=subset(rec,"/"+id+"/")
	var guns: Array=subset(rec,"/weapons/")
	check(hulls.size()==1,id+" one real directional hull draw")
	check(guns.size()>=Art.mounts_of(ship.spec).size(),id+" fitted weapons have actual texture layers")
	if not info.is_empty() and hulls.size()==1:
		var factor: float=rec.scale_factor/float(info.density)
		var expected: Vector2=rec.origin-Vector2(info.pivot)*factor
		var dest: Array=hulls[0].rect
		check(Vector2(dest[0],dest[1]).distance_to(expected)<0.01,id+" waterline pivot maps to actual projector origin")
	check_visible(rec,Rect2(0,0,480,300),id+" battle detail")
	var turned: Dictionary=probe.duplicate(true)
	turned.localAimAngles={"mount0":0.61}
	var aimed=boat_canvas(turned)
	check(subset(aimed,"/"+id+"/")==hulls,id+" gun bearing does not rotate hull texture")
	check(subset(aimed,"/weapons/")!=guns,id+" actual live weapon layer rotates with aim")
	check(turned.localAimAngles=={"mount0":0.61},id+" renderer leaves local aim untouched")
	# Normal refit factory and 390x245 play size, including physical socket overlays.
	var body:=VBoxContainer.new()
	root.add_child(body)
	RefitUI.preview(ui,body,ship)
	var portrait=body.get_child(0)
	check(portrait.get_script()==Portrait and portrait.show_sockets,id+" actual public refit preview factory")
	var refit=Trace.Canvas.new()
	portrait.draw_contents(refit,Vector2(390,245))
	var portrait_path: String=str(audit.get("entry",{}).get("portrait",""))
	check(not portrait_path.is_empty() and subset(refit,portrait_path).size()==1,id+" normal refit uses higher-density real portrait")
	check(portrait._socket_points.size()==Refit.hardpoints(spec).size(),id+" refit retains all clickable physical mounts")
	check_visible(refit,Rect2(8,42,374,195),id+" normal refit")
	panels.append(refit.panel("refit-"+id,ship.name+" / normal refit 390x245",Vector2(390,245)))
	body.free()
	# A real empty fit must remove every gun texture, keeping the same hull.
	var bare_fit: Dictionary=Refit.defaults(spec)
	bare_fit.weapons.fill("")
	var normalized: Dictionary=Refit.normalize(spec,bare_fit)
	check(bool(normalized.ok),id+" normal fitting rules allow an empty fitting")
	if normalized.ok:
		var bare: Dictionary=Art.preview_boat(Refit.effective_spec(spec,normalized.loadout),float(probe.angle))
		var empty=boat_canvas(bare)
		check(Art.mounts_of(bare.spec).is_empty() and subset(empty,"/weapons/").is_empty(),id+" removing fit removes every installed weapon layer")
		check(subset(empty,"/"+id+"/")==hulls,id+" unequipping weapons preserves actual hull image/pivot")
		if id=="ash_corvette":
			panels.append(rec.panel("armed-corvette","Actual fitted corvette / inspection scale1.3",Vector2(480,300)))
			panels.append(aimed.panel("aimed-corvette","Actual local aim +0.61 rad / inspection scale1.3",Vector2(480,300)))
			panels.append(empty.panel("empty-corvette","Same corvette / all weapons removed",Vector2(480,300)))
	check(ship==before,id+" all capture/refit paths preserve complete ship state")

func run() -> void:
	var target: String=ProjectSettings.globalize_path("res://../qa/art042-trace.json")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):target=arg.trim_prefix("--out=")
	var game=Main.new()
	game.process_mode=Node.PROCESS_MODE_DISABLED
	root.add_child(game)
	game.audio.enabled=false;game.music.enabled=false
	game.save_directory=target.get_base_dir().path_join("isolated-art042-saves")
	var captain=game.core
	var captain_state: Dictionary=captain.state.duplicate(true)
	var world_before: Dictionary=game.data.duplicate(true)
	game.open_lab()
	check(game.ui.modal_kind=="lab" and str(game.lab_config.get("preset",""))=="finished_boats","public Lab opens representative preset")
	var listed: Array=[]
	for item in game.lab_config.player:listed.append(item.hull)
	check(listed==IDS,"public Lab offers all three representative boats")
	var budget: Dictionary=Lab.inspect(game.data,game.lab_config)
	check(bool(budget.ok) and budget.player.points<=300 and budget.enemy.points<=300,"normal300-point deployment rules retained")
	game.start_lab();game.paused=true
	check(game.mode=="battle" and game.lab_active and game.battle.autopilot,"normal launch enters isolated battle on autopilot")
	game.chart.step(0.0)
	var before: Dictionary=game.battle.duplicate(true)
	var battle=Trace.battle_canvas(game)
	check(battle.invalid==0,"actual normal-zoom battle trace is finite")
	for id in IDS:check(not subset(battle,"/"+str(id)+"/").is_empty(),str(id)+" actual battle uses baked hull")
	check(game.battle==before,"normal battle capture leaves complete state untouched")
	var view_size: Vector2=game.chart.get_viewport_rect().size
	var panel: Dictionary=battle.panel("battle-normal","Launched Lab / actual normal battle zoom %.3f"%float(game.chart.scale_factor),view_size)
	panel.camera=[game.chart.camera.x,game.chart.camera.y];panel.scale_factor=game.chart.scale_factor
	panels.append(panel)
	for ship in game.battle.ships:
		if ship.team=="player":inspect_boat(game.data,ship,game.ui)
	var fallback_spec: Dictionary=Lab.hull(game.data,"bilge_punt")
	var fallback: Dictionary=Art.preview_boat(Refit.effective_spec(fallback_spec,Refit.defaults(fallback_spec)))
	var old=boat_canvas(fallback)
	check(old.invalid==0 and old.texture_draws==0 and old.mesh_draws>0,"other33 hulls retain actual existing fallback geometry")
	check(game.data==world_before,"Lab and art leave world data unchanged")
	game.return_to_title()
	check(game.core==captain and captain.state==captain_state,"leaving Lab restores captain object and full state")
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var file=FileAccess.open(target,FileAccess.WRITE)
	check(file!=null,"focused trace report opens")
	if file!=null:
		file.store_string(JSON.stringify({"schema":"brass-tide-art042-trace-v1","checks":checks,"failures":failures,"panels":panels,"limits":"Actual BoatArt textures, geometry, fits and normal refit factory; CPU drawing-call replay, no GPU/FPS/audio proof."}))
		file.close()
	game.queue_free()
	await process_frame
	print("ART042: %d checks, %d failures; %d actual drawing-call panels"%[checks,failures,panels.size()])
	quit(0 if failures==0 else 1)
