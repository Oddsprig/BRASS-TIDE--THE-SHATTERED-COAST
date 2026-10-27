extends SceneTree
## Prepared source fixture. Root alone runs native checks through Test Bridge.
## Synthetic geometry and actual Lab/Battle poses test wake submission only.
const Wake = preload("res://scripts/wake_art045.gd")
const Chart = preload("res://scripts/chart.gd")
const Art = preload("res://scripts/boat_art.gd")
const Lab = preload("res://scripts/fleet_lab.gd")
const Battle = preload("res://scripts/battle.gd")
var checks: int = 0
var failures: Array = []

class Recorder extends RefCounted:
	var polygons: Array = []
	var colors: Array[Color] = []
	var heights: Array[float] = []
	var invalid: int = 0
	var camera := Vector2.ZERO
	var screen_origin := Vector2.ZERO
	var view_scale: float = 1.0
	func project(point: Vector2, height: float) -> Vector2:
		heights.append(height)
		return screen_origin + (point - camera) * view_scale
	func iso(point: Vector2, height: float) -> Vector2:
		heights.append(height)
		var d: Vector2 = point - camera
		return screen_origin + Vector2((d.x - d.y) * Chart.ISO_X, (d.x + d.y) * Chart.ISO_Y - height) * view_scale
	func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
		polygons.append(points.duplicate())
		colors.append(color)
		for point in points:
			if not point.is_finite():
				invalid += 1
		if Geometry2D.triangulate_polygon(points).size() != (points.size() - 2) * 3:
			invalid += 1
		for edge in range(points.size()):
			for other in range(edge + 2, points.size()):
				if edge == 0 and other == points.size() - 1:
					continue # Consecutive edges share their endpoint by design.
				if Geometry2D.segment_intersects_segment(points[edge], points[(edge + 1) % points.size()], points[other], points[(other + 1) % points.size()]) != null:
					invalid += 1

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("WAKE045: " + message)

func straight() -> Array:
	var samples: Array = []
	for index in range(9):
		samples.append({"p": Vector2(index * 5.0, 0.0), "d": Vector2.LEFT, "age": (8 - index) * 0.06, "w": 6.0})
	return samples

func recorded(samples: Array, opts: Dictionary = {}, isometric: bool = false, view: Dictionary = {}) -> Recorder:
	var recorder := Recorder.new()
	recorder.camera = view.get("camera", Vector2.ZERO)
	recorder.screen_origin = view.get("origin", Vector2.ZERO)
	recorder.view_scale = float(view.get("scale", 1.0))
	var label: String = " " + str(view.get("label", ""))
	var before: PackedByteArray = var_to_bytes([samples, opts, view])
	var projector: Callable = recorder.iso if isometric else recorder.project
	var count: int = Wake.draw(recorder, projector, samples, opts)
	check(count == recorder.polygons.size() and count <= Wake.MAX_PRIMITIVES, "draw count equals actual bounded polygon calls")
	check(recorder.invalid == 0, "every submitted polygon is finite, noncrossing and fully triangulable" + label)
	check(recorder.heights.size() <= Wake.MAX_VERTICES * Wake.MAX_PRIMITIVES and recorder.heights.all(func(h): return h == 0.0), "bounded projection work stays on the water plane")
	check(recorder.polygons.all(func(p): return p.size() >= 3 and p.size() <= Wake.MAX_VERTICES), "every strip has a hard vertex bound")
	check(recorder.colors.all(func(c): return is_finite(c.a) and c.a >= 0.0 and c.a <= 0.180001), "foam is restrained finite translucency")
	check(var_to_bytes([samples, opts, view]) == before, "drawing does not mutate path samples, options or projection inputs")
	return recorder

func centers_follow(recorder: Recorder, path: Array, message: String) -> void:
	var follows: bool = not recorder.polygons.is_empty() and path.size() >= 2
	for polygon in recorder.polygons:
		if polygon.size() != path.size() * 2 - 1:
			follows = false
			continue
		follows = follows and Vector2(polygon[0]).distance_to(path[0].p) < 0.0001
		for index in range(1, path.size()):
			var center: Vector2 = (polygon[index] + polygon[polygon.size() - index]) * 0.5
			follows = follows and center.distance_to(path[index].p) < 0.0001
	check(follows, message)

func geometry_cases() -> void:
	var line: Array = straight()
	var line_rec: Recorder = recorded(line)
	check(line_rec.polygons.size() == 3, "one joined wash uses three filled strips, without dots or dashes")
	var public_rec := Recorder.new()
	var public_count: int = Art.draw_wake(public_rec, public_rec.project, line)
	check(public_count == line_rec.polygons.size() and public_rec.polygons == line_rec.polygons, "Root's BoatArt delegation reaches the same bounded production renderer")
	centers_follow(line_rec, line, "straight strips end at the real stern samples despite deliberately wrong bow headings")
	var confined: bool = true
	for polygon in line_rec.polygons:
		for point in polygon:
			confined = confined and point.x >= 0.0 and point.x <= 40.0 and absf(point.y) <= 6.0 * 0.62 + 0.0001
	check(confined, "straight wash never extends past the stern or grows long side rails")
	var rotated_heading: Array = line.duplicate(true)
	for sample in rotated_heading:
		sample.d = Vector2.UP
	check(recorded(rotated_heading).polygons == line_rec.polygons, "heading-only changes cannot rotate an existing world path")
	var curve: Array = []
	for index in range(9):
		var angle: float = float(index) / 8.0 * PI * 0.5
		curve.append({"p": Vector2.from_angle(angle) * 32.0, "d": Vector2.RIGHT, "age": (8 - index) * 0.06, "w": 6.0})
	var curve_rec: Recorder = recorded(curve)
	centers_follow(curve_rec, curve, "a ninety-degree turn stays joined along actual curved travel")
	check(recorded(curve, {}, true).polygons.size() == 3, "the production isometric water projection keeps curved strips valid")
	var reverse: Array = []
	var positions: Array[float] = [0.0, 6.0, 12.0, 18.0, 12.0, 6.0, 0.0]
	for index in range(positions.size()):
		reverse.append({"p": Vector2(positions[index], 0.0), "d": Vector2.RIGHT, "age": (positions.size() - index - 1) * 0.08, "w": 6.0})
	var reverse_rec: Recorder = recorded(reverse)
	centers_follow(reverse_rec, reverse.slice(3), "reverse wash follows astern displacement and stops at the reversal cusp")
	var aged: Array = line.duplicate(true)
	for sample in aged:
		sample.age += 0.25
	var aged_rec: Recorder = recorded(aged)
	check(not aged_rec.colors.is_empty() and aged_rec.colors[0].a < line_rec.colors[0].a, "a stopped wash loses opacity without emitting new marks")
	centers_follow(aged_rec, line.slice(1), "stopping leaves the surviving foam anchored in its original world positions")
	for sample in aged:
		sample.age += 0.71
	check(recorded(aged).polygons.is_empty(), "resting wash expires completely within the hard lifetime")
	check(recorded(line, {"life": 6.0}).polygons == line_rec.polygons, "legacy six-second option cannot lengthen the short wash")
	check(recorded(line, {"clip_rect": Rect2(200, 200, 20, 20)}).polygons.is_empty(), "fully offscreen wash submits no polygons")
	check(not recorded(line, {"clip_rect": Rect2(10, -2, 10, 4)}).polygons.is_empty(), "a visible middle remains drawable when both path ends are outside the viewport")
	var many: Array = []
	for index in range(600):
		many.append({"p": Vector2(index, 0.0), "age": (599 - index) * 0.001, "w": 6000.0})
	var many_rec: Recorder = recorded(many)
	check(many_rec.polygons.size() == 3 and Wake._path(many, Wake.LIFE_SEC).size() == Wake.MAX_SAMPLES and many_rec.polygons[0].size() <= Wake.MAX_VERTICES, "oversized input retains the hard sample cap; redundant subpixel vertices may be removed")
	var long_path: Array = []
	for index in range(12):
		long_path.append({"p": Vector2(index * 12.0, 0.0), "age": (11 - index) * 0.04, "w": 6000.0})
	var long_rec: Recorder = recorded(long_path)
	var extent: Rect2 = Rect2(long_rec.polygons[0][0], Vector2.ZERO)
	for point in long_rec.polygons[0]:
		extent = extent.expand(point)
	check(extent.size.x <= Wake.MAX_LENGTH + 0.0001, "even a fast path is clipped to the absolute world-length cap")
	check(extent.size.y <= Wake.MAX_WIDTH * 0.62 * 2.0 + 0.0001, "oversized emission width cannot exceed the absolute wash width cap")
	for invalid in [[], [{"p": Vector2.ZERO, "age": 0.0}], [{"p": Vector2(NAN, 0), "age": 0.0}], [{"p": Vector2.ZERO, "age": INF}], [{"p": Vector2.ZERO, "age": -0.1}], [{"p": Vector2.ZERO, "age": 0.0, "w": NAN}], ["bad sample"]]:
		check(recorded(invalid).polygons.is_empty(), "empty, isolated or invalid input cannot create a ghost patch")
	var resting: Array = []
	for index in range(20):
		resting.append({"p": Vector2.ZERO, "age": (19 - index) * 0.01, "w": 6.0})
	check(recorded(resting).polygons.is_empty(), "repeated stationary anchors cannot manufacture a hull-shaped puddle")
	check(recorded([{"p": Vector2.ZERO, "age": 0.1}, {"p": Vector2(10000, 0), "age": 0.0}]).polygons.is_empty(), "a relocation cannot draw a connecting streak")
	var bad_projector: Callable = func(_p: Vector2, _h: float) -> Vector2: return Vector2(INF, 0)
	var bad_rec := Recorder.new()
	check(Wake.draw(bad_rec, bad_projector, line) == 0 and bad_rec.polygons.is_empty(), "invalid projected coordinates never reach a canvas call")

func slow_turn_cases() -> void:
	# A long leg then two short turns totals <135 degrees, so _path retains it.
	# The old rotating sections let the stern cap cross the first long leg;
	# shrinking only interior widths did not constrain that cap.
	var positions: Array[Vector2] = [Vector2.ZERO, Vector2(10, 0), Vector2(10.02, 1.0), Vector2(9.32, 1.72)]
	var corner: Array = []
	for index in range(positions.size()):
		corner.append({"p": positions[index], "age": (positions.size() - index - 1) * 0.10, "w": 6.0})
	check(Wake._path(corner, Wake.LIFE_SEC).size() == positions.size(), "regression exercises the entire legal slow turn, without dropping older visible legs")
	var corner_rec: Recorder = recorded(corner)
	check(corner_rec.polygons.size() == Wake.MAX_PRIMITIVES, "a folded-path repair keeps all three visible bands")
	centers_follow(corner_rec, corner, "ordered sections retain every actual stern center through the tight turn")
	for rotation in [0.0, 0.7, 2.2, 4.0]:
		for mirror in [-1.0, 1.0]:
			var moved: Array = corner.duplicate(true)
			for sample in moved:
				sample.p = Vector2(sample.p.x, sample.p.y * mirror).rotated(rotation) + Vector2(1300, 850)
			for scale in [0.49, 0.94, 1.2]:
				var rec: Recorder = recorded(moved, {}, true, {"origin": Vector2(800, 500), "camera": Vector2(1100, 850), "scale": scale, "label": "translated slow corner"})
				check(rec.polygons.size() == Wake.MAX_PRIMITIVES, "visible turned bands are repaired rather than hidden at battle/tactical scale")
	# Float32 screen translation can collapse a very narrow fading tail. Check
	# each submission through the same native triangulator as the other cases.
	for spacing in [0.051, 0.12, 0.4]:
		for age in [0.0, 0.25, 0.5, 0.68]:
			var slow: Array = []
			for index in range(8):
				var angle: float = index * 0.10
				slow.append({"p": Vector2(1350, 850) + Vector2(sin(angle), 1.0 - cos(angle)) * spacing * 10.0, "age": age + (7 - index) * 0.002, "w": 12.0})
			recorded(slow, {}, true, {"origin": Vector2(1280, 800), "camera": Vector2(1100, 850), "scale": 0.49, "label": "slow/fading projected tip"})
	var invisible: Array = [{"p": Vector2.ZERO, "age": 0.01, "w": 6.0}, {"p": Vector2(0.11, 0), "age": 0.0, "w": 6.0}]
	check(recorded(invisible, {}, true, {"origin": Vector2(800, 500), "scale": 0.49}).polygons.is_empty(), "paint below 0.01 screen pixel squared is safely culled")
	var collapsed := PackedVector2Array([Vector2(800, 500), Vector2(801, 500), Vector2(803, 499), Vector2(803, 501), Vector2(801, 500)])
	var cleaned: PackedVector2Array = Wake._paint_polygon(collapsed)
	check(cleaned.size() == 3 and Geometry2D.triangulate_polygon(cleaned).size() == 3, "a rounded out-and-back tip is removed without discarding its visible triangle")

func boat_for(spec: Dictionary, uid: String = "wake045") -> Dictionary:
	return {"uid": uid, "spec": spec, "x": 300.0, "y": 300.0, "angle": 0.0, "vx": 60.0, "vy": 0.0, "sunk": false, "crew": 7.0, "fuel": 11.0, "ammo": 13.0, "supplies": 2.0}

func update_read_only(chart, boats: Array) -> void:
	var before: PackedByteArray = var_to_bytes(boats)
	chart._update_wakes(boats)
	check(var_to_bytes(boats) == before, "wake producer leaves boats, finite stores, crew and source specs unchanged")

func samples_of(chart, uid: String) -> Array:
	var samples: Array = []
	for sample in chart._wakes.get(uid, []):
		samples.append({"p": sample.p, "d": sample.d, "w": sample.w, "age": chart.clock - float(sample.t)})
	return samples

func chart_cases(spec: Dictionary) -> void:
	var chart = Chart.new()
	var boat: Dictionary = boat_for(spec)
	update_read_only(chart, [boat])
	check(recorded(samples_of(chart, boat.uid)).polygons.is_empty(), "one actual stern observation is not enough to invent travel")
	for index in range(1, 19):
		chart.clock = index * 0.03
		boat.x += 4.0
		update_read_only(chart, [boat])
	var emitted: Array = chart._wakes[boat.uid]
	check(emitted.size() == Wake.MAX_SAMPLES, "a continuously moving producer discards excess observations at the hard sample cap")
	check(emitted.back().p == Art.stern_of(boat), "live producer uses the physical transom and drive anchor")
	check(Vector2(emitted.back().d).dot(Vector2.RIGHT) > 0.999, "live direction follows actual travel")
	var last_stamp: float = emitted.back().t
	var last_position: Vector2 = emitted.back().p
	boat.vx = 0.0
	chart.clock += 0.18
	update_read_only(chart, [boat])
	check(float(chart._wakes[boat.uid].back().t) == last_stamp and Vector2(chart._wakes[boat.uid].back().p) == last_position, "rest never refreshes or drifts the last emitted sample")
	chart.clock = last_stamp + Wake.LIFE_SEC + 0.01
	update_read_only(chart, [boat])
	check(chart._wakes.is_empty(), "producer releases expired history even while every boat is at rest")
	boat = boat_for(spec)
	boat.vx = 2.0
	chart.clock = 2.0
	update_read_only(chart, [boat])
	for index in range(1, 7):
		chart.clock = 2.0 + index * 0.1
		boat.x += 0.2
		update_read_only(chart, [boat])
	check(chart._wakes[boat.uid].size() >= 3 and not recorded(samples_of(chart, boat.uid)).polygons.is_empty(), "two-unit-per-second pose inputs produce a small bounded wash below the old ten-unit cutoff")
	last_stamp = chart._wakes[boat.uid].back().t
	boat.angle += 0.4
	chart.clock += 0.05
	update_read_only(chart, [boat])
	check(float(chart._wakes[boat.uid].back().t) == last_stamp, "in-place bow rotation and stale velocity cannot emit extra foam")
	boat.angle = 0.0
	boat.vx = -20.0
	boat.x -= 3.0
	chart.clock += 0.06
	update_read_only(chart, [boat])
	check(Vector2(chart._wakes[boat.uid].back().d).dot(Vector2.LEFT) > 0.999, "reverse producer direction follows displacement instead of bow heading")
	boat.x += 1000.0
	chart.clock += 0.06
	update_read_only(chart, [boat])
	check(chart._wakes[boat.uid].size() == 1, "producer starts a fresh path after relocation")
	chart._wakes.clear()
	var boats: Array = []
	for index in range(Chart.WAKE_MAX_BOATS + 8):
		boats.append(boat_for(spec, "bounded-%d" % index))
	for frame in range(20):
		chart.clock = 5.0 + frame * 0.025
		for runner in boats:
			runner.x += 2.0
		update_read_only(chart, boats)
	var bounded: bool = chart._wakes.size() <= Chart.WAKE_MAX_BOATS
	for history in chart._wakes.values():
		bounded = bounded and history.size() <= Wake.MAX_SAMPLES and history.size() <= Chart.WAKE_MAX_PER_BOAT
	check(bounded, "live producer enforces both per-boat and whole-fleet history caps")
	check(not recorded(samples_of(chart, "bounded-%d" % (boats.size() - 1)), {}, true).polygons.is_empty(), "bounded live histories remain valid under the battle projection")
	chart.free()

func lab_battle_cases(world: Dictionary) -> void:
	# Match --qa-lab=all_weapons: unedited preset, seed 83, autopilot and 60 Hz.
	# Run the actual battle and Chart producer, rather than hand-authoring poses.
	var built: Dictionary = Lab.create(world, Lab.preset(world, "all_weapons"), 83)
	check(bool(built.get("ok", false)) and built.get("battle") is Dictionary, "movie regression constructs the actual all_weapons Lab battle")
	if not bool(built.get("ok", false)) or not (built.get("battle") is Dictionary):
		return
	var battle: Dictionary = built.battle
	var chart = Chart.new()
	var flagship: Dictionary = Battle.get_flagship(battle)
	chart.camera = Vector2(flagship.x, flagship.y)
	var painted: Dictionary = {}
	var curved: bool = false
	for frame in range(300):
		Battle.update(battle, 1.0 / 60.0, {})
		Battle.pop_events(battle) # Main drains these through audio; no playback here.
		chart.clock += 1.0 / 60.0
		flagship = Battle.get_flagship(battle)
		if not flagship.is_empty():
			chart.camera = chart.camera.lerp(Vector2(flagship.x, flagship.y), 1.0 - exp(-4.0 / 60.0))
		update_read_only(chart, battle.ships)
		for key in chart._wakes:
			var samples: Array = samples_of(chart, str(key))
			var path: Array = Wake._path(samples, Wake.LIFE_SEC)
			check(path.size() <= Wake.MAX_SAMPLES and path.all(func(s): return float(s.age) >= 0.0 and float(s.age) < Wake.LIFE_SEC), "actual battle histories retain the sample/lifetime caps")
			for index in range(2, path.size()):
				var a: Vector2 = Vector2(path[index - 1].p) - Vector2(path[index - 2].p)
				var b: Vector2 = Vector2(path[index].p) - Vector2(path[index - 1].p)
				curved = curved or absf(a.angle_to(b)) > 0.01
			for tactical in [false, true]:
				# Chart.project at the project's 1600x1000 logical canvas size.
				var scale: float = clampf(1600.0 / 1700.0, 0.65, 1.2) * (0.52 if tactical else 1.0)
				var rec: Recorder = recorded(samples, {}, true, {"origin": Vector2(800, 500), "camera": chart.camera, "scale": scale, "label": "all_weapons frame=%d boat=%s tactical=%s" % [frame, key, tactical]})
				if not rec.polygons.is_empty():
					painted[key] = true
	check(is_equal_approx(float(battle.time), 5.0), "movie regression advances all five actual combat seconds")
	check(curved, "actual Lab poses include a curved stern path")
	check(painted.size() >= 3, "multiple actual moving boats retain visible wash during the movie interval")
	chart.free()

func run() -> void:
	geometry_cases()
	slow_turn_cases()
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var spec: Dictionary = Lab.hull(world, "tin_skiff")
	check(not spec.is_empty(), "fixture uses the existing Tinwake hull schema")
	if not spec.is_empty():
		chart_cases(spec)
		lab_battle_cases(world)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file: FileAccess = FileAccess.open(arg.substr(6), FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify({"checks": checks, "failures": failures, "limits": "Synthetic geometry plus five seconds of actual Lab/Battle poses and Chart recording; no GPU, movie, motion or audio acceptance."}))
				file.close()
	print("wake045: %d checks, %d failures; presentation geometry only" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
