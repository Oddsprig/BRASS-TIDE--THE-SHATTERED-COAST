extends SceneTree
## Headless boat-art gallery + focused art check (no window, no input).
## Run from repo root (root serializes all Godot runs):
##   godot --headless --path game --script <abs path>/tools/boat_gallery.gd -- --out=<path.json>
## Records the exact BoatArt draw primitives for every hull (plus fitted,
## damaged, wake and projectile panels) through a dummy canvas recorder and
## writes them as JSON for software rasterising (PNG/GIF) by root tooling.
## Also asserts the art contract: 24 hulls, 6+ distinct archetypes, rich
## primitive counts at full detail, cheaper LODs, and all four fitted weapon
## families visible. Exit code 0 = pass, 1 = failure. Default output:
## <repo>/qa/boat_gallery.json (res://../qa/boat_gallery.json).

const BoatArt = preload("res://scripts/boat_art.gd")

const PANEL_W := 640.0
const PANEL_H := 420.0
const BACKGROUND := "#183e4b"

var checks := 0
var failures := 0

class Recorder extends RefCounted:
	var prims: Array = []

	func _col(c: Color) -> Array:
		return [snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001), snappedf(c.a, 0.001)]

	func _pts(points: PackedVector2Array) -> Array:
		var out: Array = []
		for p in points:
			out.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
		return out

	func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
		prims.append({"t": "poly", "pts": _pts(points), "c": _col(color)})

	func draw_polyline(points: PackedVector2Array, color: Color, width: float = -1.0, _aa: bool = false) -> void:
		prims.append({"t": "line", "pts": _pts(points), "c": _col(color), "w": snappedf(maxf(0.5, width), 0.01)})

	func draw_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0, _aa: bool = false) -> void:
		prims.append({"t": "seg", "pts": _pts(PackedVector2Array([from, to])), "c": _col(color), "w": snappedf(maxf(0.5, width), 0.01)})

	func draw_circle(position: Vector2, radius: float, color: Color) -> void:
		prims.append({"t": "circle", "pts": _pts(PackedVector2Array([position])), "r": snappedf(radius, 0.01), "c": _col(color)})

	func draw_arc(center: Vector2, radius: float, start: float, end: float, point_count: int, color: Color, width: float = -1.0, _aa: bool = false) -> void:
		var pts := PackedVector2Array()
		var n := maxi(2, point_count)
		for i in range(n + 1):
			pts.append(center + Vector2.from_angle(lerpf(start, end, float(i) / float(n))) * radius)
		draw_polyline(pts, color, width)

	func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0) -> void:
		var corners := PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0),
			rect.position + rect.size, rect.position + Vector2(0, rect.size.y)])
		if filled:
			draw_colored_polygon(corners, color)
		else:
			corners.append(corners[0])
			draw_polyline(corners, color, width)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BOAT GALLERY: " + message)

func _scale_for(spec: Dictionary) -> float:
	var world_len := maxf(20.0, float(spec.get("size", 16)) * 4.6)
	return minf(PANEL_W * 0.78 / (world_len * 1.08), PANEL_H * 0.72 / (world_len * 0.60))

func _projector_for(spec: Dictionary) -> Callable:
	var k := _scale_for(spec)
	var origin := Vector2(PANEL_W, PANEL_H) * 0.5 + Vector2(0, PANEL_H * 0.05)
	return func(p: Vector2, h: float) -> Vector2:
		return origin + Vector2((p.x - p.y) * 0.82, (p.x + p.y) * 0.41 - h) * k

func _panel(id: String, title: String, boat: Dictionary, lod: int = 0) -> Dictionary:
	var spec: Dictionary = boat.get("spec", {})
	var rec := Recorder.new()
	var k_px := maxf(4.0, _scale_for(spec)*float(spec.get("size", 16)))
	var stats := BoatArt.draw_boat(rec, _projector_for(spec), boat, {
		"accent": Color("dfbd7d"), "enemy": false, "lod": lod, "clock": 1.25, "px": k_px})
	return {"id": id, "title": title, "width": PANEL_W, "height": PANEL_H,
		"background": BACKGROUND, "archetype": stats.archetype, "mounts": stats.mounts,
		"stats": stats, "primitives": rec.prims}

func _out_path() -> String:
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	for i in range(args.size()):
		var a := str(args[i])
		if a.begins_with("--out="):
			return a.trim_prefix("--out=")
		if a == "--out" and i + 1 < args.size():
			return str(args[i + 1])
	return ProjectSettings.globalize_path("res://../qa/boat_gallery.json")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var start := Time.get_ticks_msec()
	var raw := FileAccess.get_file_as_string("res://data/world.json")
	var world_v = JSON.parse_string(raw)
	check(world_v is Dictionary, "world.json parses")
	if not (world_v is Dictionary):
		_finish(start, [])
		return
	var hulls: Array = world_v.get("HULLS", [])
	check(hulls.size() == 24, "24 hulls in world data (got %d)" % hulls.size())
	if hulls.is_empty():
		_finish(start, [])
		return
	var panels: Array = []
	var archetypes: Dictionary = {}
	var min_prims := 1 << 30
	var max_prims := 0
	var total_prims := 0
	for spec in hulls:
		if not (spec is Dictionary):
			continue
		var boat := BoatArt.preview_boat(spec, -0.45)
		boat.vx = 40.0
		boat.vy = 18.0
		var panel := _panel(str(spec.get("id", "?")), str(spec.get("name", "")), boat, 0)
		panels.append(panel)
		archetypes[str(panel.archetype)] = true
		var n := int(panel.stats.primitives)
		total_prims += n
		min_prims = mini(min_prims, n)
		max_prims = maxi(max_prims, n)
		check(n >= 55, "%s is visibly rich at LOD0 (%d primitives >= 55)" % [spec.get("id", "?"), n])
		check(int(panel.stats.mounts) >= 1, "%s draws at least one weapon mount" % spec.get("id", "?"))
		check(panel.primitives.size() == n, "%s recorder captured every primitive" % spec.get("id", "?"))
	for want in ["speedboat", "catamaran", "hydrofoil", "armored", "monitor", "command", "patrol"]:
		check(archetypes.has(want), "archetype present: " + want)
	# LOD must get strictly cheaper on the largest hull.
	var big: Dictionary = hulls[hulls.size() - 1]
	var lod_counts: Array = []
	for lod in [0, 1, 2]:
		var p := _panel("lod%d" % lod, "LOD %d" % lod, BoatArt.preview_boat(big, -0.45), lod)
		lod_counts.append(int(p.stats.primitives))
		panels.append(p)
	check(lod_counts[0] > lod_counts[1] and lod_counts[1] > lod_counts[2],
		"LOD primitive counts decrease (%s)" % str(lod_counts))
	# Fitted variant: one hull carrying all four weapon families at once.
	var fitted: Dictionary = big.duplicate(true)
	fitted.weaponMounts = [
		{"kind": "gun", "x": 1.15, "y": 0.0, "angle": 0.0, "size": "small"},
		{"kind": "cannon", "x": 0.45, "y": 0.0, "angle": 0.0, "size": "large"},
		{"kind": "rocket", "x": -0.55, "y": 0.0, "angle": 0.0, "size": "medium"},
		{"kind": "torpedo", "x": -0.15, "y": -0.55, "angle": 0.0, "size": "medium"},
		{"kind": "torpedo", "x": -0.15, "y": 0.55, "angle": 0.0, "size": "medium"},
	]
	# Fitted positions follow combat's world-unit hardpoint contract.
	for mount in fitted.weaponMounts:
		mount.x *= float(big.size)
		mount.y *= float(big.size)
	var fitted_panel := _panel("fitted_all_families", "Fitted: gun+cannon+rocket+torpedoes", BoatArt.preview_boat(fitted, -0.45), 0)
	panels.append(fitted_panel)
	check(int(fitted_panel.stats.mounts) == 5, "fitted panel draws all 5 fitted mounts (4 families)")
	var mounts := BoatArt.mounts_of(fitted)
	var kinds: Dictionary = {}
	for m in mounts:
		kinds[str(m.kind)] = true
	for want_kind in ["gun", "cannon", "rocket", "torpedo"]:
		check(kinds.has(want_kind), "fitted mount family normalized: " + want_kind)
	# World-unit mount coordinates (refit-style) must normalize onto the hull.
	var world_units: Dictionary = big.duplicate(true)
	world_units.weaponMounts = [{"kind": "cannon", "x": float(big.get("size", 16)) * 0.6, "y": 0.0, "angle": 0.0, "size": 2}]
	var wm := BoatArt.mounts_of(world_units)
	check(wm.size() == 1 and absf(float(wm[0].x) - 0.6) < 0.01, "world-unit mount x normalizes to local units")
	# Damaged variant: breaches, flooding and fire must add primitives.
	var hurt := BoatArt.preview_boat(big, -0.45)
	var clean_n := int(_panel("tmp_clean", "", hurt, 0).stats.primitives)
	hurt.breaches = [{}, {}, {}]
	hurt.water = 45.0
	hurt.fire = 2.0
	var hurt_panel := _panel("damaged", "Damaged: breaches + flood + fire", hurt, 0)
	panels.append(hurt_panel)
	check(int(hurt_panel.stats.primitives) > clean_n, "damage state adds visible primitives")
	_add_motion_panels(panels, big)
	_finish(start, panels, {"hulls": hulls.size(), "archetypes": archetypes.keys(),
		"min_primitives_lod0": min_prims, "max_primitives_lod0": max_prims,
		"total_primitives_24_lod0": total_prims, "lod_counts_big_hull": lod_counts})

func _add_motion_panels(panels: Array, spec: Dictionary) -> void:
	# Three wake frames along a curved (turning) stern path + projectile set,
	# recorded through the same primitives root rasterises for GIF inspection.
	var proj := func(p: Vector2,h: float) -> Vector2:
		return Vector2(PANEL_W,PANEL_H)*0.5+Vector2((p.x-p.y)*0.82,(p.x+p.y)*0.41-h)*1.05
	var size := float(spec.get("size", 16))
	for frame in range(3):
		var rec := Recorder.new()
		var samples: Array = []
		var count := 8 + frame * 7
		for i in range(count):
			var t := float(i) / 21.0
			var ang := -0.45 - t * 0.55
			var p := Vector2(-120.0 + t * 216.0, 70.0 - t * 97.0 + sin(t * PI) * 14.0)
			samples.append({"p": p, "d": Vector2.from_angle(ang), "age": (1.0 - t) * 5.4, "w": size * 0.42})
		var latest: Dictionary = samples.back()
		var heading: Vector2 = latest.d
		var position: Vector2 = latest.p+heading*1.75*size
		var boat := BoatArt.preview_boat(spec, heading.angle())
		boat.x = position.x
		boat.y = position.y
		boat.vx = 60.0
		boat.vy = -35.0
		var wake_n := BoatArt.draw_wake(rec, proj, samples, {"life": 6.0})
		var stats := BoatArt.draw_boat(rec, proj, boat, {"accent": Color("dfbd7d"), "lod": 0, "clock": float(frame), "px": 40.0})
		panels.append({"id": "wake_frame_%d" % frame, "title": "Curved wake, frame %d" % frame,
			"width": PANEL_W, "height": PANEL_H, "background": BACKGROUND,
			"archetype": stats.archetype, "stats": stats, "wake_primitives": wake_n, "primitives": rec.prims})
		check(wake_n >= 3, "wake frame %d emits banded wake polylines" % frame)
	var rec2 := Recorder.new()
	var n_shots := 0
	var kinds := ["bullet", "shell", "rocket", "torpedo"]
	for i in range(kinds.size()):
		var y := -90.0 + float(i) * 55.0
		n_shots += BoatArt.draw_projectile(rec2, proj,
			{"x": 60.0, "y": y, "px": 45.0, "py": y + 4.0, "kind": kinds[i], "team": "player"}, {})
		var trail: Array = []
		for j in range(8):
			trail.append({"p": Vector2(45.0 - float(j) * 14.0, y + 4.0 + float(j)), "age": float(j) * 0.12, "life": 1.2})
		if kinds[i] in ["torpedo", "rocket"]:
			n_shots += BoatArt.draw_trail(rec2, proj, trail, kinds[i], {"px": 26.0})
	panels.append({"id": "projectiles", "title": "Bullet / shell / rocket / torpedo + trails",
		"width": PANEL_W, "height": PANEL_H, "background": BACKGROUND, "primitives": rec2.prims})
	check(n_shots >= 20, "projectile panel emits distinct family primitives (%d)" % n_shots)

func _finish(start: int, panels: Array, summary: Dictionary = {}) -> void:
	var out := _out_path()
	var payload := {"tool": "tools/boat_gallery.gd", "format": 1,
		"note": "Exact BoatArt draw primitives in panel pixel coordinates. poly/line/seg pts are [x,y]; circle has pts[0]=center and r. c is [r,g,b,a] 0..1.",
		"summary": summary, "checks": checks, "failures": failures, "panels": panels}
	var dir := out.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("BOAT GALLERY: cannot write " + out)
		quit(1)
		return
	f.store_string(JSON.stringify(payload))
	f.close()
	print("boat_gallery: %d checks, %d failures, %d panels, %dms -> %s" % [checks, failures, panels.size(), Time.get_ticks_msec() - start, out])
	quit(0 if failures == 0 else 1)
