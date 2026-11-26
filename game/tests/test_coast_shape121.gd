extends SceneTree
## v0.121 native fixture for Root's bounded TestBridge batch. Pure geometry
## over the shared coast module plus the real world.json home rings; no
## simulation, no rendering, no save or profile access.
const Shape121 = preload("res://scripts/coast_shape121.gd")
const CoastArt = preload("res://scripts/coast_art050.gd")
const Navigation = preload("res://scripts/navigation.gd")
var checks: int = 0
var failures: int = 0

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

func validate_shaped(original: Array, shaped: Array, label: String) -> PackedVector2Array:
	var before: PackedVector2Array = ring_of(original)
	var after: PackedVector2Array = ring_of(shaped)
	check(after.size() >= 16 and after.size() <= Shape121.MAX_RING, label + " bounded physical ring 16..96")
	var finite: bool = true
	for p in after: finite = finite and is_finite(p.x) and is_finite(p.y)
	check(finite, label + " finite vertices")
	# Whole-polygon containment by intersection area: no shaped edge may
	# bridge a water cove, which vertex/midpoint sampling cannot prove.
	check(Shape121._is_subset(after, before), label + " whole shaped polygon inside original land (intersection proof)")
	check(Shape121._max_macro_turn(after) < Shape121._max_macro_turn(before), label + " sharpest macro corner is rounded, not just inset")
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
	check(Shape121._max_macro_turn(dense_after) < 0.9, "authored macro corners rounded below a sharp turn")
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
		validate_shaped(data.ISLANDS[i121].points,shaped_islands[i121].points,"actual home "+str(data.ISLANDS[i121].id))
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
	print("COAST121: %d checks, %d failures; geometry only, no visual-quality verdict" % [checks, failures])
	for argument121 in OS.get_cmdline_user_args():
		if argument121.begins_with("--out="):
			var receipt121=FileAccess.open(argument121.substr(6),FileAccess.WRITE)
			if receipt121==null:quit(2);return
			receipt121.store_string(JSON.stringify({"outcome":"passed" if failures==0 else "failed","checks":checks,"failures":failures,"seconds":(Time.get_ticks_usec()-began121)/1000000.0},"\t"))
			receipt121.close()
	quit(0 if failures == 0 else 1)
