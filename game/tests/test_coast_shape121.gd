extends SceneTree
## v0.121 native fixture for Root's bounded TestBridge batch. Pure geometry
## over the shared coast module plus the real world.json home rings; no
## simulation, no rendering, no save or profile access.
const Shape121 = preload("res://scripts/coast_shape121.gd")
const CoastArt = preload("res://scripts/coast_art050.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Battle121=preload("res://scripts/battle.gd")
const Driver121=preload("res://scripts/battle_driver051.gd")
const Chart121=preload("res://scripts/chart.gd")
const Routes121=preload("res://scripts/tactical_routes.gd")
const MeshCache121=preload("res://scripts/boat_mesh_cache.gd")
class CoastHost121 extends RefCounted:
	var mode: String="battle"
	var battle: Dictionary={}
var checks: int = 0
var failures: int = 0
var art_diagnostics121: Array=[]

func art_probe121(ok: bool,message: String) -> void:
	art_diagnostics121.append({"met":ok,"message":message})
	print("COAST121_ART_DIAGNOSTIC ",ok," ",message)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("COAST121: " + message)

func _initialize() -> void:
	call_deferred("run")

func ring_of(points: Array) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for p in points: ring.append(Vector2(float(p[0]), float(p[1])))
	return ring

func curving_vertices(ring: PackedVector2Array) -> int:
	# A natural shore turns a little at many vertices; a hexagon or square
	# turns a lot at a few. Count gentle 2..35 degree turns.
	var count: int = 0
	for i in range(ring.size()):
		var a: Vector2 = ring[i] - ring[(i + ring.size() - 1) % ring.size()]
		var b: Vector2 = ring[(i + 1) % ring.size()] - ring[i]
		if a.length() < 0.001 or b.length() < 0.001: continue
		var turn: float = absf(angle_difference(a.angle(), b.angle()))
		if turn > 0.035 and turn < 0.61: count += 1
	return count

func sharpest_headland121(ring: PackedVector2Array) -> float:
	# Compare immediate convex headland angles at a fixed geometric meaning.
	# A reflex inlet retained by clipping must not masquerade as a square
	# outer headland; vertex-count-dependent multi-edge windows change scale.
	var signed_area121: float=0.0
	for i121 in range(ring.size()):signed_area121+=ring[i121].cross(ring[(i121+1)%ring.size()])
	var winding121: float=1.0 if signed_area121>0.0 else -1.0
	var worst121: float=0.0
	for i121 in range(ring.size()):
		var a121: Vector2=ring[i121]-ring[posmod(i121-1,ring.size())]
		var b121: Vector2=ring[(i121+1)%ring.size()]-ring[i121]
		if a121.length_squared()<0.0001 or b121.length_squared()<0.0001:continue
		worst121=maxf(worst121,a121.angle_to(b121)*winding121)
	return worst121

func validate_shaped(original: Array, shaped: Array, label: String, uniform_corner_probe: bool=true) -> PackedVector2Array:
	var before: PackedVector2Array = ring_of(original)
	var after: PackedVector2Array = ring_of(shaped)
	check(after.size() >= 16 and after.size() <= Shape121.MAX_RING, label + " bounded physical ring 16..96")
	var finite: bool = true
	for p in after: finite = finite and is_finite(p.x) and is_finite(p.y)
	check(finite, label + " finite vertices")
	# Whole-polygon containment by intersection area: no shaped edge may
	# bridge a water cove, which vertex/midpoint sampling cannot prove.
	check(Shape121._is_subset(after, before), label + " whole shaped polygon inside original land (intersection proof)")
	if uniform_corner_probe:
		art_probe121(sharpest_headland121(after) < sharpest_headland121(before), label + " convex headland corners are rounded, not just inset")
	check(Shape121._simple(after), label + " simple non-self-intersecting ring")
	var ratio: float = Shape121._area(after) / maxf(0.001, Shape121._area(before))
	check(ratio >= 0.5 and ratio <= 1.001, label + " area kept, never grown (%.3f)" % ratio)
	check(curving_vertices(after) >= 8, label + " silhouette curves at many vertices, no hex/square corners")
	# Navigation agreement: every sampled point that was water outside the
	# old shore stays water (samples landward in a concave inlet are skipped
	# by construction: they were not water before shaping either).
	var nav: Dictionary = Navigation.geometry([{"points": shaped}], 4000.0, 4000.0)
	var nav_before: Dictionary = Navigation.geometry([{"points": original}], 4000.0, 4000.0)
	var center: Vector2 = Shape121._centroid(before)
	var berths_clear: bool = true
	for i in range(before.size()):
		var mid: Vector2 = (before[i] + before[(i + 1) % before.size()]) * 0.5
		var outward: Vector2 = (mid - center).normalized()
		var berth: Vector2 = mid + outward * 60.0
		if berth.x < 100.0 or berth.y < 100.0 or berth.x > 3900.0 or berth.y > 3900.0: continue
		if not Navigation.is_water(nav_before, berth.x, berth.y, 10.0): continue
		berths_clear = berths_clear and Navigation.is_water(nav, berth.x, berth.y, 10.0)
	check(berths_clear, label + " existing off-shore water remains navigable")
	return after

func run() -> void:
	var began121: int=Time.get_ticks_usec()
	# A submitted resource must survive global-cache eviction while another
	# canvas still owns commands. Only its own next draw releases that pin.
	var pin_owner121:=Node2D.new()
	var other_owner121:=Node2D.new()
	MeshCache121.begin_draw121(pin_owner121,true)
	var pin_mesh121:=ArrayMesh.new()
	var pin_weak121:=weakref(pin_mesh121)
	MeshCache121._meshes["pin_probe121"]=pin_mesh121
	MeshCache121._order.append("pin_probe121")
	MeshCache121._active_keys121["pin_probe121"]=true
	pin_mesh121=null
	MeshCache121.clear()
	check(pin_weak121.get_ref()!=null,"canvas retains submitted mesh after actual global cache clear")
	var replacement121:=ArrayMesh.new()
	var replacement_weak121:=weakref(replacement121)
	MeshCache121._meshes["pin_probe121"]=replacement121
	MeshCache121._order.append("pin_probe121");replacement121=null
	MeshCache121.clear()
	check(replacement_weak121.get_ref()==null and pin_weak121.get_ref()!=null,"rebaking an already retired key cannot pin an unsubmitted replacement or release the original commands")
	MeshCache121.begin_draw121(other_owner121)
	check(pin_weak121.get_ref()!=null,"another canvas redraw cannot release this canvas mesh")
	MeshCache121.begin_draw121(pin_owner121,true)
	check(pin_weak121.get_ref()==null,"only owner next redraw releases its previous mesh references")
	var final_pin121:=ArrayMesh.new()
	var final_weak121:=weakref(final_pin121)
	MeshCache121._meshes["final_pin_probe121"]=final_pin121
	MeshCache121._order.append("final_pin_probe121")
	MeshCache121._active_keys121["final_pin_probe121"]=true;final_pin121=null
	MeshCache121.clear()
	MeshCache121.end_draw121(pin_owner121)
	pin_owner121.free();other_owner121.free()
	check(final_weak121.get_ref()==null,"ended draw keeps no static borrowed list alive after its owner is freed")
	var first_canvas121:=Node2D.new()
	var second_canvas121:=Node2D.new()
	MeshCache121.begin_draw121(first_canvas121,true)
	var switched_mesh121:=ArrayMesh.new()
	var switched_weak121:=weakref(switched_mesh121)
	MeshCache121._meshes["switch_probe121"]=switched_mesh121
	MeshCache121._order.append("switch_probe121");switched_mesh121=null
	MeshCache121._active_keys121["switch_probe121"]=true
	MeshCache121.end_draw121(first_canvas121)
	MeshCache121.begin_draw121(second_canvas121,true)
	MeshCache121.clear()
	MeshCache121.end_draw121(second_canvas121)
	MeshCache121.begin_draw121(second_canvas121,true)
	check(switched_weak121.get_ref()!=null,"switching fast canvas keeps previous owner commands alive after cache clear and new owner redraw")
	MeshCache121.end_draw121(second_canvas121)
	MeshCache121.begin_draw121(first_canvas121)
	check(switched_weak121.get_ref()==null,"previous fast canvas releases transferred resources only at its own next redraw")
	MeshCache121.end_draw121(first_canvas121)
	first_canvas121.free();second_canvas121.free()
	var unused_canvas121:=Node2D.new()
	MeshCache121.begin_draw121(unused_canvas121,true)
	var unused_mesh121:=ArrayMesh.new()
	var unused_weak121:=weakref(unused_mesh121)
	MeshCache121._meshes["unused_probe121"]=unused_mesh121
	MeshCache121._order.append("unused_probe121");unused_mesh121=null
	MeshCache121.clear()
	check(unused_weak121.get_ref()==null,"cache clear never pins resources absent from the fast canvas retained commands")
	MeshCache121.end_draw121(unused_canvas121);unused_canvas121.free()
	# The two literal laboratory / Coastal Clash slabs from battle.gd.
	var lab: Array = [
		{"id": "lab_north", "name": "North", "color": "#66877e", "points": [[850, 80], [1130, 120], [1210, 310], [1030, 420], [820, 300]]},
		{"id": "lab_south", "name": "South", "color": "#66877e", "points": [[1040, 1320], [1240, 1250], [1430, 1450], [1320, 1640], [1070, 1580]]}]
	var lab_before: PackedByteArray = var_to_bytes(lab)
	var lab_shaped: Array = Shape121.natural_islands(lab)
	check(var_to_bytes(lab) == lab_before, "shaping never mutates its input definitions")
	check(lab_shaped.size() == 2 and lab_shaped[0].id == "lab_north" and lab_shaped[1].name == "South", "identities and count preserved")
	for i in range(2):
		validate_shaped(lab[i].points, lab_shaped[i].points, "lab slab %d" % i)
		var plan: Dictionary = CoastArt.prepare_island(lab_shaped[i])
		check(plan.land == ring_of(lab_shaped[i].points), "CoastArt clips to the same shaped physical ring %d" % i)
		for level in range(3):
			var count: int = plan.levels[level].vertices.size()
			check(count > 0 and count % 3 == 0 and count <= int(CoastArt.VERTEX_LIMITS[level]), "art LOD %d stays bounded on shaped ring %d" % [level, i])
	# A literal square and a sector-template style coarse profile.
	var square: Array = [[300, 300], [900, 300], [900, 900], [300, 900]]
	validate_shaped(square, Shape121.natural_ring(square, "square_probe"), "square")
	var profile: Array = [[560, 1000], [752, 810], [980, 700], [1220, 795], [1425, 870], [1500, 1036], [1228, 1174], [836, 1300], [654, 1132]]
	validate_shaped(profile, Shape121.natural_ring(profile, "settled_99_island_01"), "sector profile")
	# Determinism and old-save safety: same saved bytes, same shore, forever.
	var once: Array = Shape121.natural_ring(profile, "settled_99_island_01")
	var twice: Array = Shape121.natural_ring(profile, "settled_99_island_01")
	check(var_to_bytes(once) == var_to_bytes(twice), "deterministic from saved coarse bytes plus island id")
	check(var_to_bytes(Shape121.natural_islands([{ "points":once,"coast121":1}])[0].points) == var_to_bytes(once), "marked encounter shore is never re-smoothed")
	check(var_to_bytes(Shape121.natural_ring(profile, "other_island")) != var_to_bytes(once), "island id varies the coastline")
	# Authored dense path: a subdivided hexagon (72 vertices, 6 macro
	# corners) must come back with those corners visibly ROUNDED by
	# corner-cutting, bounded, simple and wholly inside the old land.
	var dense: Array = []
	var hex: Array = []
	for i in range(6): hex.append(Vector2(2000, 2000) + Vector2.from_angle(float(i) * TAU / 6.0) * Vector2(900, 620))
	for i in range(6):
		for j in range(12):
			var p: Vector2 = hex[i].lerp(hex[(i + 1) % 6], float(j) / 12.0)
			dense.append([p.x, p.y])
	var dense_before: PackedVector2Array = ring_of(dense)
	var dense_after: PackedVector2Array = validate_shaped(dense, Shape121.natural_ring_authored(dense, "isl_dense_probe"), "authored dense hexagon")
	art_probe121(sharpest_headland121(dense_after) < 0.9, "authored convex corner %.4f rounded below0.9radians" % sharpest_headland121(dense_after))
	# Glasswind-density runtime ring (36 vertices with sharp corners) must
	# shape through natural_islands, not skip past the coarse guard.
	var key36: Array = []
	var corners36: Array = []
	for i in range(9): corners36.append(Vector2(2000, 1500) + Vector2.from_angle(float(i) * TAU / 9.0) * Vector2(700, 480))
	for i in range(9):
		for j in range(4):
			var p36: Vector2 = corners36[i].lerp(corners36[(i + 1) % 9], float(j) / 4.0)
			key36.append([p36.x, p36.y])
	var glass: Array = [{"id": "glasswind_west", "name": "West", "color": "#66877e", "points": key36}]
	var glass_shaped: Array = Shape121.natural_islands(glass)
	validate_shaped(key36, glass_shaped[0].points, "glasswind-density 36 ring")
	check(int(glass_shaped[0].get("coast121", 0)) == 1, "runtime shaped copy carries the no-repeat marker")
	check(var_to_bytes(Shape121.natural_islands(glass_shaped)[0].points) == var_to_bytes(glass_shaped[0].points), "marked runtime ring is never shaped twice")
	check(var_to_bytes(Shape121.natural_islands(glass_shaped)[0].points) == var_to_bytes(glass_shaped[0].points), "same runtime ring remains a fixed point across boundaries")
	# Narrow water bay: a C-shaped island whose inlet mouth is far narrower
	# than its edges. The shaped shore must not bridge the mouth.
	var bay: Array = [[400, 400], [1600, 400], [1600, 1600], [400, 1600], [400, 1120], [1250, 1120], [1250, 880], [400, 880]]
	var bay_after: PackedVector2Array = validate_shaped(bay, Shape121.natural_ring(bay, "narrow_bay_probe"), "narrow bay")
	var mouth: Vector2 = Vector2(700, 1000)
	check(not Geometry2D.is_point_in_polygon(mouth, bay_after), "narrow bay mouth stays open water after shaping")
	# Exact shipped concave hook that crossed an old safe-water hull disk in
	# the first relay. Keep the fixture tied to real authored profile bytes.
	var templates121: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/sector_templates069.json"))
	var hook121: Array=[]
	for point121 in templates121.profiles.hook:hook121.append([1080.0+float(point121[0])*480.0,2210.0+float(point121[1])*270.0])
	var hook_after121: Array=Shape121.natural_ring(hook121,"settled_01_island_03")
	validate_shaped(hook121,hook_after121,"shipped concave hook")
	var old_hook_nav121: Dictionary=Navigation.geometry([{"points":hook121}],4200.0,3000.0)
	var new_hook_nav121: Dictionary=Navigation.geometry([{"points":hook_after121}],4200.0,3000.0)
	check(Navigation.is_water(old_hook_nav121,1354.839202,2232.034295,10.0),"reported hook hull center was safe old water")
	check(Navigation.is_water(new_hook_nav121,1354.839202,2232.034295,10.0),"reported hook hull center remains safe new water")
	var atlas121: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/ocean_regions064.json"))
	for region121 in atlas121.regions:
		if str(region121.id)!="glasswind_keys":continue
		var shaped121: Array=Shape121.natural_islands(region121.islands)
		for i121 in range(region121.islands.size()):
			validate_shaped(region121.islands[i121].points,shaped121[i121].points,"actual Glasswind "+str(i121))
			check(var_to_bytes(region121.islands[i121].points)!=var_to_bytes(shaped121[i121].points),"actual Glasswind coast changed "+str(i121))
	# Real home world: eight authored islands and their ten actual berths.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var shaped_islands: Array = Shape121.natural_islands_authored(data.ISLANDS)
	check(shaped_islands.size() == 8, "eight home islands retained")
	var ids_kept: bool = true
	for i in range(8): ids_kept = ids_kept and shaped_islands[i].id == data.ISLANDS[i].id
	check(ids_kept, "home island identities retained")
	for i121 in range(data.ISLANDS.size()):
		validate_shaped(data.ISLANDS[i121].points,shaped_islands[i121].points,"actual home "+str(data.ISLANDS[i121].id),false)
		check(var_to_bytes(data.ISLANDS[i121].points)!=var_to_bytes(shaped_islands[i121].points),"actual home coast changed "+str(data.ISLANDS[i121].id))
	for i121 in range(data.ISLANDS.size()):
		var before121: PackedVector2Array=ring_of(data.ISLANDS[i121].points)
		var probe121: PackedVector2Array=Shape121._shape_dense(before121,Shape121._seed(str(data.ISLANDS[i121].id)))
		print("COAST121_DIAGNOSTIC ",JSON.stringify({"id":data.ISLANDS[i121].id,"points":probe121.size(),"simple":Shape121._simple(probe121),"subset":Shape121._is_subset(probe121,before121),"area_ratio":Shape121._area(probe121)/Shape121._area(before121),"old_turn":Shape121._max_macro_turn(before121),"new_turn":Shape121._max_macro_turn(probe121)}))
	var home_nav: Dictionary = {"width": data.WORLD.width, "height": data.WORLD.height, "islands": shaped_islands}
	for port in data.PORTS:
		check(Navigation.is_water(home_nav, port.x, port.y, 36.0), "home berth stays navigable water " + str(port.id))
	for approach in [{"x": 5200.0, "y": 300.0}, {"x": 5200.0, "y": 6900.0}]:
		check(Navigation.is_water(home_nav, approach.x, approach.y, 80.0 + Navigation.DEFAULT_CLEARANCE), "home approach disk stays safe water")
	# Compare the cached broad phase with the complete legacy shore test at
	# exact/near boundary centers, several hull radii and open-water points.
	var battle121: Dictionary=Battle121.create({})
	# The production worker's snapshot-only turn must not advance physics,
	# consume RNG or charge a completed step before the next normal turn.
	var publish_job121:=Driver121._Job.new()
	publish_job121.state=battle121;publish_job121.boot=false;publish_job121.publish=true
	var before_publish121: Dictionary=Driver121._snapshot(battle121,false)
	var before_rng121: int=battle121.rng.state
	Driver121._work(publish_job121)
	check(int(publish_job121.receipt.stepsInJob)==0 and publish_job121.completed==0,"snapshot-only production worker turn reports no completed physics")
	check(before_publish121==Driver121._snapshot(battle121,false) and battle121.rng.state==before_rng121,"snapshot-only production worker turn preserves state, time and RNG")
	check(not publish_job121.publication.is_empty() and publish_job121.publication.time==battle121.time,"snapshot-only production worker turn publishes actual completed state")
	var mirror121: Dictionary=Driver121._snapshot(battle121,false)
	check(battle121.get("_coastRings121",[]).size()==battle121.islands.size() and not mirror121.has("_coastRings121") and mirror121.islands.all(func(row121):return not row121.has("_coastRing121")),"coast accelerators stay on owner, outside public terrain records and publications")
	# Actual Chart preparation must reuse meshes across detached publications,
	# and still invalidate for translated terrain and a transition to empty sea.
	var coast_host121:=CoastHost121.new()
	coast_host121.battle={"islands":battle121.islands}
	var coast_chart121:=Chart121.new()
	coast_chart121.host=coast_host121
	coast_chart121._prepare_battle_coast()
	var first_plan121: Dictionary=coast_chart121._battle_coast[0]
	coast_host121.battle={"islands":battle121.islands.duplicate(true)}
	coast_chart121._prepare_battle_coast()
	check(is_same(first_plan121,coast_chart121._battle_coast[0]),"detached equal worker terrain reuses actual prepared coast meshes")
	for point121 in coast_host121.battle.islands[0].points:point121[0]=float(point121[0])+30.0
	coast_chart121._prepare_battle_coast()
	check(not is_same(first_plan121,coast_chart121._battle_coast[0]),"translated encounter terrain invalidates actual coast meshes")
	coast_host121.battle={"islands":[]}
	coast_chart121._prepare_battle_coast()
	check(coast_chart121._battle_coast.is_empty(),"empty sea clears the prior island mesh cache")
	coast_chart121.free()
	var uncached121: Dictionary={"islands":battle121.islands.duplicate(true)}
	for island121 in uncached121.islands:island121.erase("_coastBounds121")
	for island121 in battle121.islands:
		for j121 in range(0,island121.points.size(),4):
			var p121:=Vector2(island121.points[j121][0],island121.points[j121][1])
			for radius121 in [0.0,10.0,45.0]:
				for offset121 in [Vector2.ZERO,Vector2(radius121,0),Vector2(-radius121-0.01,radius121+0.01)]:
					var at121: Vector2=p121+offset121
					check(Battle121._island_blocked(battle121,at121,radius121)==Battle121._island_blocked(uncached121,at121,radius121),"cached bounds preserve exact legacy land/contact result")
	check(Battle121._island_blocked(battle121,Vector2(200,800),45.0)==Battle121._island_blocked(uncached121,Vector2(200,800),45.0),"far-water cache rejection preserves legacy result")
	for island121 in battle121.islands:
		for j121 in range(0,island121.points.size(),8):
			var p121:=Vector2(island121.points[j121][0],island121.points[j121][1])
			for radius121 in [0.0,2.0,12.0]:
				for end121 in [p121+Vector2(250,120),p121-Vector2(300,90)]:
					check(Battle121._clear_shot(battle121,p121+Vector2(0,radius121),end121,radius121)==Battle121._clear_shot(uncached121,p121+Vector2(0,radius121),end121,radius121),"cached ray bounds preserve complete legacy shot clearance")
	# Same actual detailed coast, independent old kernels retained by the
	# uncached state. A dense grid also covers the one-unit native-buffer edge.
	var query_legacy121:=PackedByteArray()
	var query_native121:=PackedByteArray()
	var query_started121: int=Time.get_ticks_usec()
	for i121 in range(512):
		var sample121:=Vector2(760.0+float(i121%32)*17.0,40.0+float(i121/32)*28.0)
		for radius121 in [0.0,1.0,10.0,45.0]:query_legacy121.append(1 if Battle121._island_blocked(uncached121,sample121,radius121) else 0)
	var query_legacy_us121: int=Time.get_ticks_usec()-query_started121
	query_started121=Time.get_ticks_usec()
	for i121 in range(512):
		var sample121:=Vector2(760.0+float(i121%32)*17.0,40.0+float(i121/32)*28.0)
		for radius121 in [0.0,1.0,10.0,45.0]:query_native121.append(1 if Battle121._island_blocked(battle121,sample121,radius121) else 0)
	var query_native_us121: int=Time.get_ticks_usec()-query_started121
	check(query_legacy121==query_native121,"2048 dense-coast native/legacy grid contacts agree individually")
	var route_geometry121: Dictionary=Routes121.terrain(battle121)
	var route_legacy121: Dictionary=route_geometry121.duplicate(true)
	for obstacle121 in route_legacy121.obstacles:
		obstacle121.erase("_edgeLo121");obstacle121.erase("_edgeHi121")
	var route_public_equal121: bool=true
	var route_record_equal121: bool=true
	var route_cases121: int=0
	var route_veto_cases121: int=0
	for sample_index121 in range(32):
		for radius121 in [0.0,1.0,12.0,45.0]:
			for limit121 in [0,3,12,256]:
				var anchor121: Array=battle121.islands[0].points[sample_index121%battle121.islands[0].points.size()]
				var from121:=Vector2(anchor121[0],anchor121[1])+Vector2(radius121+0.001,float(sample_index121%3)*0.01)
				var to121: Vector2=from121 if sample_index121%3==0 else from121+Vector2(250,-110) if sample_index121%3==1 else Vector2(1800,1000)
				var before121: Dictionary={"clearanceTests":0,"clearanceLimit":limit121,"exhaustions":0,"profileRoutes051":true,"vetoCapture051":true}
				var after121: Dictionary=before121.duplicate(true)
				var old_status121: String=Routes121.sweep(route_legacy121,from121,to121,radius121,before121)
				var new_status121: String=Routes121.sweep(route_geometry121,from121,to121,radius121,after121)
				if before121.has("vetoPrimitive051"):route_veto_cases121+=1
				route_public_equal121=route_public_equal121 and old_status121==new_status121 and before121==after121
				before121={"clearanceTests":0,"clearanceLimit":limit121,"exhaustions":0,"profileRoutes051":true,"vetoCapture051":true};after121=before121.duplicate(true)
				var old_debits121: Array[int]=[]
				var new_debits121: Array[int]=[]
				old_status121=Routes121._sweep_record051(route_legacy121,from121,to121,radius121,before121,old_debits121)
				new_status121=Routes121._sweep_record051(route_geometry121,from121,to121,radius121,after121,new_debits121)
				route_record_equal121=route_record_equal121 and old_status121==new_status121 and before121==after121 and old_debits121==new_debits121
				route_cases121+=1
	check(route_public_equal121,"512 cached/complete route sweeps preserve status, pending, exact budget and veto fields")
	check(route_record_equal121,"512 recorded route sweeps preserve status, exact debit sequence, budget and veto fields")
	check(route_veto_cases121>0,"route matrix actually records nonempty veto observations")
	print("COAST121: %d checks, %d failures; geometry only, no visual-quality verdict" % [checks, failures])
	for argument121 in OS.get_cmdline_user_args():
		if argument121.begins_with("--out="):
			var receipt121=FileAccess.open(argument121.substr(6),FileAccess.WRITE)
			if receipt121==null:quit(2);return
			receipt121.store_string(JSON.stringify({"outcome":"passed" if failures==0 else "failed","checks":checks,"failures":failures,"seconds":(Time.get_ticks_usec()-began121)/1000000.0,"art_probes":art_diagnostics121,"art_requires_actual_image_review":true,"contact_query_diagnostic":{"queries_each":2048,"legacy_us":query_legacy_us121,"cached_native_us":query_native_us121,"fps_claim":false},"route_cache_diagnostic":{"cases_each":route_cases121,"public_status_budget_veto_equal":route_public_equal121,"record_status_debits_budget_veto_equal":route_record_equal121,"observed_veto_cases":route_veto_cases121}},"\t"))
			receipt121.close()
	quit(0 if failures == 0 else 1)
