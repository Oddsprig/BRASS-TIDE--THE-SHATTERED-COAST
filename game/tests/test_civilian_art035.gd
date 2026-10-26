extends SceneTree
## One bounded source-roster art fixture. Root runs headless/Dummy in Test Bridge.
## The existing gallery Recorder captures exact BoatArt calls, without a viewport.
const Art = preload("res://scripts/boat_art.gd")
const Profiles = preload("res://scripts/hull_profiles.gd")
const Detail = preload("res://scripts/boat_deck_detail.gd")
const Layout = preload("res://scripts/mount_layout.gd")
const Motor = preload("res://scripts/motor_art.gd")
const Refit = preload("res://scripts/refit.gd")
const EXPECTED: Dictionary = {
	"kelpnet_dory":["fishing","skiff","open_windscreen"],
	"brinehook_longliner":["fishing","skiff","customs_canopy"],
	"mother_gull_trawler":["fishing","raider","estuary_span"],
	"fenhopper_lighter":["transport","raider","estuary_span"],
	"tideledger_coaster":["transport","raider","estuary_span"],
	"fourport_packet":["transport","raider","packet_house"],
	"brasswind_motor_galleon":["transport","raider","packet_house"],
	"seepoil_tanker":["tanker","corvette","turtleback_conning"],
	"blackwater_fleet_tanker":["tanker","corvette","brass_wheelhouse"],
	"gullwing_daysailer":["yacht","cutter","stepped_cockpit"],
	"osprey_cabin_cruiser":["yacht","cutter","interceptor_canopy"],
	"aurelian_court_yacht":["yacht","cruiser","commodore_tower"]
}
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("CIVILIAN ART035: "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	# Load the actual existing recorder script outside game/, without instantiating
	# its SceneTree or running its broader gallery suite.
	var gallery: GDScript = load(ProjectSettings.globalize_path("res://../tools/boat_gallery.gd"))
	check(gallery!=null,"existing native gallery recorder is available")
	var hulls: Array = world.get("HULLS",[])
	check(hulls.size()==36,"canonical roster contains the existing24 plus12 civilians")
	check(Profiles.hull_ids().size()==36,"profile catalogue contains36 explicit identities")
	var by_id: Dictionary = {}
	for hull in hulls:by_id[str(hull.id)]=hull
	var panels: Array = []
	var silhouettes: Dictionary = {}
	if gallery!=null:
		for id in EXPECTED:
			check(by_id.has(id),"canonical civilian exists "+id)
			if not by_id.has(id):continue
			var spec: Dictionary = by_id[id]
			var before: Dictionary = spec.duplicate(true)
			var identity: Dictionary = Profiles.profile(spec)
			check(Profiles.has_hull(id) and identity.hullId==id,"explicit profile, no military fallback "+id)
			check(spec.get("civilianRole","")==EXPECTED[id][0] and spec.role==EXPECTED[id][1] and identity.bridgeStyle==EXPECTED[id][2],"canonical role and accepted bridge "+id)
			var valid: bool = identity.stations.size()>=8
			var previous_x: float = -INF
			for station in identity.stations:
				valid=valid and is_finite(station.x) and is_finite(station.y) and station.x>previous_x and station.y>=0.0
				previous_x=station.x
			check(valid,"finite ordered original silhouette "+id)
			silhouettes[str(identity.stations)]=true
			_check_deck(spec,identity)
			var motors: Dictionary = Motor.layout(spec)
			check(motors.hullId==id and motors.beyondStern and motors.clearsSockets and motors.count>=1,"actual stern motor and socket clearance "+id)
			var fitted: Dictionary = Refit.effective_spec(spec,Refit.defaults(spec))
			var stock: Array = Art.mounts_of(fitted)
			var socket: Dictionary = Layout.hardpoints(spec)[0]
			check(not fitted.is_empty() and stock.size()==1 and stock[0].id==socket.id and absf(stock[0].x*float(spec.size)-float(socket.x))<0.001 and absf(stock[0].y*float(spec.size)-float(socket.y))<0.001,"stock art uses actual refit hardpoint "+id)
			var panel: Dictionary = gallery._panel(id,str(spec.name),Art.preview_boat(fitted),0)
			panels.append(panel)
			check(panel.invalid==0 and panel.primitives.size()==int(panel.stats.primitives) and int(panel.stats.mounts)==1,"finite exact native primitives and stock mount "+id)
			_check_panel_bounds(panel)
			var repeat: Dictionary = gallery._panel(id,str(spec.name),Art.preview_boat(fitted),0)
			check(repeat.primitives==panel.primitives,"warm profile/detail/motor caches keep drawing stable "+id)
			var empty_fit: Dictionary = Refit.defaults(spec)
			for i in range(empty_fit.weapons.size()):empty_fit.weapons[i]=""
			var empty: Dictionary = Refit.effective_spec(spec,empty_fit)
			var empty_panel: Dictionary = gallery._panel(id,"empty",Art.preview_boat(empty),0)
			check(empty_panel.invalid==0 and int(empty_panel.stats.mounts)==0 and empty_panel.primitives!=panel.primitives,"empty refit leaves no decorative weapon "+id)
			# One stern-facing view validates faces hidden by the contact-sheet heading.
			var stern: Dictionary = gallery._panel(id,"stern",Art.preview_boat(fitted,-PI*0.75),1)
			check(stern.invalid==0 and int(stern.stats.primitives)<int(panel.stats.primitives),"valid stern view and cheaper LOD "+id)
			_check_interchangeable(spec)
			check(spec==before,"drawing/refit inspection leaves canonical data unchanged "+id)
	check(panels.size()==12 and silhouettes.size()==12,"all12 have distinct silhouettes and exact captured panels")
	_write_capture(panels)
	print("CIVILIAN ART035: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func _check_panel_bounds(panel: Dictionary) -> void:
	var lower: Vector2 = Vector2(INF,INF)
	var upper: Vector2 = Vector2(-INF,-INF)
	for primitive in panel.primitives:
		var pad: float = float(primitive.get("r",float(primitive.get("w",0.0))*0.5))
		for point in primitive.pts:
			var pos: Vector2 = Vector2(float(point[0]),float(point[1]))
			lower=lower.min(pos-Vector2.ONE*pad)
			upper=upper.max(pos+Vector2.ONE*pad)
	var margin: float = 12.0
	check(lower.x>=margin and lower.y>=margin and upper.x<=float(panel.width)-margin and upper.y<=float(panel.height)-margin,"captured boat keeps12px panel margin %s [%s,%s]"%[panel.id,lower,upper])

func _check_deck(spec: Dictionary, identity: Dictionary) -> void:
	var plan: Dictionary = Detail.layout(spec)
	var structure: Dictionary = Layout.structure(spec)
	var sockets: Array = Layout.hardpoints(spec)
	var clear: bool = true
	var hatch: bool = false
	var intended: int = identity.deckAccents.size()+identity.cargoDetails.size()
	var actual: int = 0
	for item in plan.items:
		if item.kind=="access_hatch":hatch=true
		if item.kind not in ["access_hatch","mooring_bitt"]:actual+=1
		for socket in sockets:clear=clear and Layout.footprint_clearance(socket,item)>0.0
		for solid in [structure.cabin,structure.engine]:clear=clear and not _overlap(item,solid)
	for i in range(plan.items.size()):
		for j in range(i+1,plan.items.size()):clear=clear and not _overlap(plan.items[i],plan.items[j])
	for rail in plan.rails:
		for socket in sockets:clear=clear and Layout.footprint_clearance(socket,rail.footprint)>0.0
	check(clear and hatch and not plan.rails.is_empty(),"props, bridge, machinery and rails leave hardpoints clear "+str(spec.id))
	check(actual==intended,"every authored working prop survives deck validation %s (%d/%d)"%[spec.id,actual,intended])
	if not clear or actual!=intended:print("DECK035 ",spec.id," actual=",plan.items," authored=",identity.deckAccents+identity.cargoDetails)
	var cached: Dictionary = Detail.layout(spec)
	check(cached==plan,"cached deck layout is stable "+str(spec.id))
	if not plan.items.is_empty():plan.items[0].x=99.0
	identity.stations[0]=Vector2(99,99)
	check(Detail.layout(spec)==cached and Profiles.profile(spec).stations[0].x!=99.0,"profile and cached inspection copies are detached "+str(spec.id))

func _overlap(a: Dictionary, b: Dictionary) -> bool:
	return absf(float(a.x)-float(b.x))<(float(a.get("len",a.get("length",0)))+float(b.get("len",b.get("length",0))))*0.5 and absf(float(a.y)-float(b.y))<(float(a.get("wid",a.get("width",0)))+float(b.get("wid",b.get("width",0))))*0.5

func _check_interchangeable(spec: Dictionary) -> void:
	# A single occupied optional socket stays within even the smallest fitting
	# budget. Each existing family must retain the same physical mount centre.
	var socket: Dictionary = Layout.hardpoints(spec)[1]
	var valid: bool = true
	for module in ["rapid_gun","light_cannon","fire_rocket","light_torpedo"]:
		var fit: Dictionary = Refit.defaults(spec)
		for i in range(fit.weapons.size()):fit.weapons[i]=""
		fit.weapons[1]=module
		var normalized: Dictionary = Refit.normalize(spec,fit)
		valid=valid and bool(normalized.ok)
		if not normalized.ok:continue
		var effective: Dictionary = Refit.effective_spec(spec,normalized.loadout)
		var mounts: Array = Art.mounts_of(effective)
		valid=valid and mounts.size()==1
		if mounts.size()==1:valid=valid and mounts[0].id==socket.id and absf(mounts[0].x*float(spec.size)-float(socket.x))<0.001 and absf(mounts[0].y*float(spec.size)-float(socket.y))<0.001
	check(valid,"four interchangeable weapon families keep canonical socket centres "+str(spec.id))

func _write_capture(panels: Array) -> void:
	var folder: String = OS.get_environment("GAME_TEST_ARTIFACTS")
	if folder.is_empty():folder=ProjectSettings.globalize_path("user://civilian-art035")
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join("civilian-gallery.json")
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file!=null,"exact draw capture file opens")
	if file==null:return
	file.store_string(JSON.stringify({"tool":"game/tests/test_civilian_art035.gd","format":1,
		"note":"Exact native BoatArt primitives via tools/boat_gallery.gd Recorder; no synthetic Python hull geometry.",
		"gallery":{"title":"ORIGINAL CIVILIAN HULLS","hull_ids":EXPECTED.keys()},
		"summary":{"hulls":panels.size()},"checks":checks,"failures":failures,"panels":panels}))
	file.close()
	print("CIVILIAN GALLERY035: ",path)
