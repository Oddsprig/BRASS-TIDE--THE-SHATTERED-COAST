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
var started_usec: int=0
var deadline_usec: int=0
var expired: bool=false
var complete: bool=false

func _initialize() -> void:
	started_usec=Time.get_ticks_usec()
	call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("ART042: "+message)

func within_deadline() -> bool:
	if expired:return false
	if Time.get_ticks_usec()<deadline_usec:return true
	expired=true
	check(false,"fixture work deadline exceeded; trace is incomplete")
	return false

func subset(rec,needle: String) -> Array:
	return rec.textures().filter(func(p):return needle in str(p.path))

func texture_point(primitive: Dictionary,pixel: Vector2) -> Vector2:
	var points: Array=primitive.pts
	var origin:=Vector2(points[0][0],points[0][1])
	return origin+(Vector2(points[1][0],points[1][1])-origin)*pixel.x/float(primitive.src[2])+(Vector2(points[3][0],points[3][1])-origin)*pixel.y/float(primitive.src[3])

## Bounds use actual alpha pixels from the exact PNG region drawn by BoatArt.
## Transparent atlas padding may extend beyond a panel; visible art may not.
func check_visible(rec,box: Rect2,label: String) -> void:
	check(rec.invalid==0,label+" finite native draw calls")
	for p in rec.textures():
		if not within_deadline():return
		var path: String=str(p.path)
		if not images.has(path):images[path]=Image.load_from_file(ProjectSettings.globalize_path(path))
		var image: Image=images[path]
		check(image!=null and not image.is_empty(),label+" real source PNG "+path)
		if image==null or image.is_empty():continue
		var s: Array=p.src
		var used: Rect2i=image.get_region(Rect2i(int(s[0]),int(s[1]),int(s[2]),int(s[3]))).get_used_rect()
		check(used.size.x>0 and used.size.y>0,label+" visible nonempty sprite "+path)
		var inside: bool=true
		for corner in [used.position,used.position+Vector2i(used.size.x,0),used.end,used.position+Vector2i(0,used.size.y)]:
			var point: Vector2=texture_point(p,Vector2(corner))
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
	var audit: Dictionary=Sprite.audit(ship.spec)
	check(bool(audit.get("texture_ready",false)),id+" actual baked atlas is loaded")
	var probe: Dictionary=ship.duplicate(true)
	probe.x=0.0;probe.y=0.0
	probe.angle=0.061 # Exercise the actual residual transform between baked headings.
	var info: Dictionary=Sprite.frame_info(probe.spec,float(probe.angle))
	check(not info.is_empty(),id+" directional frame exists")
	var rec=boat_canvas(probe)
	var hulls: Array=subset(rec,"/"+id+"/")
	var guns: Array=subset(rec,"/weapons/")
	check(hulls.size()==1,id+" one real directional hull draw")
	check(guns.size()>=Art.mounts_of(ship.spec).size(),id+" fitted weapons have actual texture layers")
	if not info.is_empty() and hulls.size()==1:
		# Residual XY rotates about the physical 9.7-high deck plane. The
		# recorded quad includes that matrix; raw destination rects do not.
		var deck_pixel: Vector2=Vector2(info.pivot)-Vector2(0,9.7*float(info.density))
		check(texture_point(hulls[0],deck_pixel).distance_to(rec.project(Vector2.ZERO,9.7))<0.01,id+" pivot and residual transform retain physical deck anchor")
	check_visible(rec,Rect2(0,0,480,300),id+" battle detail")
	if not within_deadline():return
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
	check(is_zero_approx(float(portrait.display_angle)),id+" normal refit shows heading0 deck and machinery")
	var refit=Trace.Canvas.new()
	portrait.draw_contents(refit,Vector2(390,245))
	var portrait_path: String=str(audit.get("entry",{}).get("portrait",""))
	check(int(audit.get("entry",{}).get("portrait_heading",-1))==0,id+" high-density portrait bake is heading0")
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
			panels.append(rec.panel("armed-corvette","Actual fitted corvette / residual angle0.061 / scale1.3",Vector2(480,300)))
			panels.append(aimed.panel("aimed-corvette","Actual local aim +0.61 rad / inspection scale1.3",Vector2(480,300)))
			panels.append(empty.panel("empty-corvette","Same corvette / all weapons removed",Vector2(480,300)))
	check(ship==before,id+" all capture/refit paths preserve complete ship state")

func inspect_fitted_families(world: Dictionary) -> void:
	var spec: Dictionary=Lab.hull(world,"brasswind_motor_galleon")
	var cases: Array=[
		["all-families",["rapid_gun","light_cannon","fire_rocket","light_torpedo"],["gun_single","cannon","rocket_three","torpedo_single"]],
		["twin-gun",["heavy_gun","","",""],["gun_twin"]],
		["heavy-cannon",["heavy_cannon","","",""],["cannon"]],
		["salvo-rockets",["salvo_rocket","","",""],["rocket_six"]],
		["twin-torpedoes",["heavy_torpedo","","",""],["torpedo_twin"]]]
	for item in cases:
		if not within_deadline():return
		var fit: Dictionary=Refit.defaults(spec)
		fit.weapons=item[1].duplicate()
		var normalized: Dictionary=Refit.normalize(spec,fit)
		check(bool(normalized.ok),str(item[0])+" is a valid actual workshop fitting")
		if not bool(normalized.ok):continue
		var effective: Dictionary=Refit.effective_spec(spec,fit)
		var portrait=Portrait.new()
		portrait.set_spec(effective)
		var rec=Trace.Canvas.new()
		portrait.draw_contents(rec,Vector2(390,245))
		for variant in item[2]:
			check(not subset(rec,"/weapons/"+str(variant)+"-").is_empty(),str(item[0])+" loads actual "+str(variant)+" weapon layers")
		check_visible(rec,Rect2(8,42,374,195),str(item[0])+" normal fitted portrait")
		panels.append(rec.panel("fitted-"+str(item[0]),"Brasswind / "+str(item[0])+" / actual workshop fit",Vector2(390,245)))
		portrait.free()

func capture(game) -> void:
	if not within_deadline():return
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
	if not within_deadline():return
	var normal_scale: float=clampf(game.chart.get_viewport_rect().size.x/1700.0,0.65,1.2)
	check(game.chart.follow_camera and is_equal_approx(game.chart.zoom,1.0) and not game.chart.tactical and is_equal_approx(game.chart.scale_factor,normal_scale),"representative trace uses real default follow camera and normal zoom")
	var before: Dictionary=game.battle.duplicate(true)
	var battle=Trace.battle_canvas(game)
	check(battle.invalid==0,"actual normal-zoom battle trace is finite")
	for id in IDS:check(not subset(battle,"/"+str(id)+"/").is_empty(),str(id)+" actual battle uses baked hull")
	check(game.battle==before,"normal battle capture leaves complete state untouched")
	var view_size: Vector2=game.chart.get_viewport_rect().size
	var panel: Dictionary=battle.panel("battle-normal","Launched Lab / actual normal battle zoom %.3f"%float(game.chart.scale_factor),view_size)
	panel.camera=[game.chart.camera.x,game.chart.camera.y];panel.scale_factor=game.chart.scale_factor
	panel.deployment_points=[budget.player.points,budget.enemy.points];panel.actor_counts=[budget.player.boats,budget.enemy.boats]
	panels.append(panel)
	for ship in game.battle.ships:
		if not within_deadline():return
		if ship.team=="player":inspect_boat(game.data,ship,game.ui)
	inspect_fitted_families(game.data)
	if not within_deadline():return
	var fallback_spec: Dictionary=Lab.hull(game.data,"bilge_punt")
	var fallback: Dictionary=Art.preview_boat(Refit.effective_spec(fallback_spec,Refit.defaults(fallback_spec)))
	var old=boat_canvas(fallback)
	check(old.invalid==0 and old.texture_draws==0 and old.mesh_draws>0,"other33 hulls retain actual existing fallback geometry")
	check(game.data==world_before,"Lab and art leave world data unchanged")
	game.return_to_title()
	check(game.core==captain and captain.state==captain_state,"leaving Lab restores captain object and full state")
	complete=true

func run() -> void:
	var artifacts: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if artifacts.is_empty():artifacts=ProjectSettings.globalize_path("res://../qa")
	var target: String=artifacts.path_join("art042-trace.json")
	var seconds: float=30.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):target=arg.trim_prefix("--out=")
		if arg.begins_with("--seconds="):seconds=clampf(arg.trim_prefix("--seconds=").to_float(),1.0,90.0)
	deadline_usec=started_usec+int(seconds*1000000.0)
	var game=Main.new()
	game.process_mode=Node.PROCESS_MODE_DISABLED
	root.add_child(game)
	game.audio.enabled=false;game.music.enabled=false
	game.save_directory=target.get_base_dir().path_join("isolated-art042-saves")
	capture(game)
	within_deadline()
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var file=FileAccess.open(target,FileAccess.WRITE)
	check(file!=null,"focused trace report opens")
	if file!=null:
		file.store_string(JSON.stringify({"schema":"brass-tide-art042-trace-v1","checks":checks,"failures":failures,"complete":complete and not expired,"elapsed_ms":float(Time.get_ticks_usec()-started_usec)/1000.0,"deadline_seconds":seconds,"panels":panels,"limits":"Actual BoatArt textures/geometry, normal Lab camera/LOD and refit factory. Opening snapshots; coast helper/background/HUD differ from rendered game. CPU replay, no GPU/FPS/audio proof. Root outer batch deadline must include imports/startup/cleanup."}))
		file.close()
	game.queue_free()
	await process_frame
	print("ART042: %d checks, %d failures; %d actual drawing-call panels"%[checks,failures,panels.size()])
	quit(0 if failures==0 else 1)
