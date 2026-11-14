extends RefCounted
## Short, shaped combat feedback and staged sinking in the same cheap 2D projection as boats.
## Consumes existing numeric effect/wreck metadata only; never mutates gameplay, RNG, camera or audio.

const MAX_EFFECT_PRIMS: int = 35
const MAX_WRECK_OVERLAY_PRIMS: int = 96
const WATER_TINT := Color(0.15, 0.34, 0.39, 1.0)
const FOAM_LIGHT := Color(0.88, 0.98, 0.94, 1.0)
const FOAM_MID := Color(0.70, 0.91, 0.85, 1.0)
const FOAM_DEEP := Color(0.46, 0.74, 0.69, 1.0)

## Only the two existing explicit polygon guards use this probe. It does not
## include CanvasItem/renderer triangulation or alter the validation result.
class PolygonProfile extends RefCounted:
	static var enabled: bool = false
	static var calls: int = 0
	static var elapsed_us: int = 0
	static var max_us: int = 0
	static var rejected: int = 0

	static func valid(points: PackedVector2Array) -> bool:
		var started: int = Time.get_ticks_usec() if enabled else 0
		var result: bool = not Geometry2D.triangulate_polygon(points).is_empty()
		if enabled:
			var elapsed: int = Time.get_ticks_usec() - started
			calls += 1
			elapsed_us += elapsed
			max_us = maxi(max_us, elapsed)
			if not result: rejected += 1
		return result

static func profile_enable(enabled: bool = true) -> void:
	PolygonProfile.enabled = enabled

static func profile_reset() -> void:
	PolygonProfile.calls = 0; PolygonProfile.elapsed_us = 0
	PolygonProfile.max_us = 0; PolygonProfile.rejected = 0

static func profile_read() -> Dictionary:
	return {"enabled": PolygonProfile.enabled, "triangulation_calls": PolygonProfile.calls,
		"triangulation_us": PolygonProfile.elapsed_us, "triangulation_max_us": PolygonProfile.max_us,
		"triangulation_rejected": PolygonProfile.rejected}

class FadeCanvas extends RefCounted:
	var target
	var alpha: float = 1.0
	var submerge: float = 0.0
	var tint: Color = WATER_TINT
	var suppress_submerged_base: bool = false
	var last_h: float = 10.0
	var count: int = 0

	func _init(target_canvas, alpha_scale: float = 1.0, submerge_t: float = 0.0, skip_base: bool = false) -> void:
		target = target_canvas
		alpha = clampf(alpha_scale, 0.0, 1.0)
		submerge = clampf(submerge_t, 0.0, 1.0)
		suppress_submerged_base = skip_base

	func _skip() -> bool:
		return target == null or alpha <= 0.01 or (suppress_submerged_base and last_h <= 0.5)

	func _color(c: Color) -> Color:
		var out: Color = c.lerp(tint, submerge * 0.52)
		out.a = clampf(c.a * alpha, 0.0, 1.0)
		return out

	func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
		if _skip() or points.size() < 3:
			return
		var col: Color = _color(color)
		if col.a <= 0.01 or not PolygonProfile.valid(points):
			return
		target.draw_colored_polygon(points, col)
		count += 1

	func draw_polyline(points: PackedVector2Array, color: Color, width: float = -1.0, _aa: bool = false) -> void:
		if _skip() or points.size() < 2:
			return
		var col: Color = _color(color)
		if col.a <= 0.01:
			return
		target.draw_polyline(points, col, width, _aa)
		count += 1

	func draw_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0, _aa: bool = false) -> void:
		if _skip() or from.distance_squared_to(to) < 0.04:
			return
		var col: Color = _color(color)
		if col.a <= 0.01:
			return
		target.draw_line(from, to, col, width, _aa)
		count += 1

	func draw_circle(position: Vector2, radius: float, color: Color) -> void:
		if _skip() or radius <= 0.05:
			return
		var col: Color = _color(color)
		if col.a <= 0.01:
			return
		target.draw_circle(position, radius, col)
		count += 1

	func draw_arc(center: Vector2, radius: float, start: float, end: float, point_count: int, color: Color, width: float = -1.0, _aa: bool = false) -> void:
		if _skip() or radius <= 0.05:
			return
		var col: Color = _color(color)
		if col.a <= 0.01:
			return
		if target.has_method("draw_arc"):
			target.draw_arc(center, radius, start, end, point_count, col, width, _aa)
			count += 1
		else:
			var pts := PackedVector2Array()
			var n: int = maxi(2, point_count)
			for i in range(n + 1):
				pts.append(center + Vector2.from_angle(lerpf(start, end, float(i) / float(n))) * radius)
			draw_polyline(pts, color, width, _aa)

	func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0) -> void:
		if _skip():
			return
		var col: Color = _color(color)
		if col.a <= 0.01:
			return
		if target.has_method("draw_rect"):
			target.draw_rect(rect, col, filled, width)
			count += 1
		else:
			var corners := PackedVector2Array([
				rect.position,
				rect.position + Vector2(rect.size.x, 0.0),
				rect.position + rect.size,
				rect.position + Vector2(0.0, rect.size.y)
			])
			if filled:
				draw_colored_polygon(corners, color)
			else:
				corners.append(corners[0])
				draw_polyline(corners, color, width)

static func _num(value, fallback: float = 0.0) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return float(value)
	return fallback

static func _scale(chart) -> float:
	if chart != null and "scale_factor" in chart:
		return maxf(0.35, _num(chart.scale_factor, 0.75))
	return 0.75

static func _lod(chart, item: Dictionary = {}) -> int:
	if item.has("lod"):
		return clampi(int(_num(item.get("lod"), 0.0)), 0, 2)
	if chart != null and "lod" in chart:
		return clampi(int(_num(chart.lod, 0.0)), 0, 2)
	var s: float = _scale(chart)
	var tac: bool = bool(chart.tactical) if (chart != null and "tactical" in chart) else false
	if tac or s < 0.40:
		return 2
	if s < 0.64:
		return 1
	return 0

static func _project(chart, world_pos: Vector2, height: float = 0.0) -> Vector2:
	if chart != null:
		if chart.has_method("project"):
			var r = chart.project(world_pos, height)
			if r is Vector2:
				return r
		if "proj" in chart and chart.proj is Callable:
			var r2 = chart.proj.call(world_pos, height)
			if r2 is Vector2:
				return r2
	var s: float = _scale(chart)
	return Vector2(320.0, 210.0) + Vector2((world_pos.x - world_pos.y) * 0.82, (world_pos.x + world_pos.y) * 0.41 - height) * s

static func _det_unit(seq: int, idx: int, salt: int = 0) -> float:
	var h: int = (seq * 1103515245 + idx * 374761393 + salt * 668265263) & 0x7fffffff
	return float(h % 10000) / 10000.0

static func _det_signed(seq: int, idx: int, salt: int = 0) -> float:
	return _det_unit(seq, idx, salt) * 2.0 - 1.0

static func _det_angle(seq: int, idx: int, count: int, base: float = 0.0, spread: float = TAU) -> float:
	var total: int = maxi(1, count)
	var step: float = spread / float(total)
	var offset: float = -spread * 0.5 + step * (float(idx) + 0.5) if spread < TAU - 0.01 else float(idx) * step + float(seq) * 2.39996
	return base + offset + _det_signed(seq, idx, 19) * step * 0.28

static func _fx_poly(fx: Dictionary, pts: PackedVector2Array, col: Color) -> void:
	if int(fx.n) >= int(fx.max_n) or col.a <= 0.01 or pts.size() < 3:
		return
	if not PolygonProfile.valid(pts):
		return
	fx.canvas.draw_colored_polygon(pts, col)
	fx.n = int(fx.n) + 1

static func _fx_line(fx: Dictionary, a: Vector2, b: Vector2, col: Color, width: float = 1.0) -> void:
	if int(fx.n) >= int(fx.max_n) or col.a <= 0.01 or a.distance_squared_to(b) < 0.09:
		return
	fx.canvas.draw_line(a, b, col, maxf(0.8, width), true)
	fx.n = int(fx.n) + 1

static func _fx_circle(fx: Dictionary, p: Vector2, r: float, col: Color) -> void:
	if int(fx.n) >= int(fx.max_n) or col.a <= 0.01 or r <= 0.15:
		return
	fx.canvas.draw_circle(p, r, col)
	fx.n = int(fx.n) + 1

static func _fx_arc(fx: Dictionary, c: Vector2, r: float, a0: float, a1: float, segs: int, col: Color, width: float = 1.0) -> void:
	if int(fx.n) >= int(fx.max_n) or col.a <= 0.01 or r <= 0.25:
		return
	var canvas = fx.canvas
	if canvas.has_method("draw_arc"):
		canvas.draw_arc(c, r, a0, a1, maxi(4, segs), col, maxf(0.8, width), true)
		fx.n = int(fx.n) + 1
	else:
		var pts := PackedVector2Array()
		var n: int = maxi(4, segs)
		for i in range(n + 1):
			pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(i) / float(n))) * r)
		canvas.draw_polyline(pts, col, maxf(0.8, width), true)
		fx.n = int(fx.n) + 1

static func _fx_water_ring(fx: Dictionary, c: Vector2, r: float, col: Color, width: float = 1.0) -> void:
	if int(fx.n) >= int(fx.max_n) or col.a <= 0.01 or r <= 0.25:
		return
	# A surface footprint in the existing isometric water plane, one primitive.
	var pts := PackedVector2Array()
	var n: int = 16 if int(fx.lod) < 2 else 10
	for i in range(n + 1):
		var a: float = TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a), sin(a) * 0.50) * r)
	fx.canvas.draw_polyline(pts, col, maxf(0.8, width), true)
	fx.n = int(fx.n) + 1

static func _star_poly(center: Vector2, r_outer: float, r_inner: float, points_count: int, seq: int, rot: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var total: int = maxi(4, points_count) * 2
	for i in range(total):
		var ang: float = rot + float(i) * TAU / float(total)
		var jitter: float = 0.88 + 0.24 * _det_unit(seq, i, 41)
		var rad: float = (r_outer if i % 2 == 0 else r_inner) * jitter
		pts.append(center + Vector2.from_angle(ang) * maxf(1.2, rad))
	return pts

static func _shard_poly(center: Vector2, dir: Vector2, len_v: float, wid_v: float) -> PackedVector2Array:
	var side: Vector2 = dir.orthogonal()
	return PackedVector2Array([
		center + dir * len_v,
		center + side * wid_v * 0.55 - dir * len_v * 0.15,
		center - dir * len_v * 0.75,
		center - side * wid_v * 0.45 - dir * len_v * 0.20
	])

static func effect(chart, e: Dictionary) -> int:
	if chart == null or e.is_empty():
		return 0
	var life: float = maxf(0.01, _num(e.get("life"), 0.45))
	var age: float = maxf(0.0, _num(e.get("age"), 0.0))
	if age >= life:
		return 0
	var t: float = clampf(age / life, 0.0, 1.0)
	var alpha: float = clampf(1.0 - t, 0.0, 1.0)
	if alpha <= 0.01:
		return 0
	var scale_value: float = _scale(chart)
	var lod: int = _lod(chart, e)
	var pos := Vector2(_num(e.get("x"), 0.0), _num(e.get("y"), 0.0))
	if e.get("position") is Vector2:
		pos = e.position
	var h: float = _num(e.get("height"), 0.0)
	var p: Vector2 = _project(chart, pos, h)
	var ground: Vector2 = _project(chart, pos, 0.0)
	var ang: float = _num(e.get("angle"), 0.0)
	var dir_world: Vector2 = Vector2.from_angle(ang)
	var p_ahead: Vector2 = _project(chart, pos + dir_world * 20.0, h)
	var screen_dir: Vector2 = (p_ahead - p).normalized() if p_ahead.distance_squared_to(p) > 0.01 else Vector2.from_angle(ang)
	var side: Vector2 = screen_dir.orthogonal()
	var seq: int = int(_num(e.get("seq", e.get("id", 0)), 0.0))
	var family: String = str(e.get("family", e.get("weaponFamily", "gun"))).to_lower()
	var kind: String = str(e.get("kind", "hit")).to_lower()
	var etype: String = str(e.get("type", kind)).to_lower()
	var subtype: String = str(e.get("subtype", "")).to_lower()
	var reason: String = str(e.get("reason", e.get("cause", subtype))).to_lower()
	var mat: String = str(e.get("material", "wood")).to_lower()
	var hull_mat: String = str(e.get("hullMaterial", mat)).to_lower()
	var mag: float = clampf(_num(e.get("magnitude"), 1.0), 0.25, 2.8)
	var radius: float = maxf(3.5, _num(e.get("radius"), 12.0)) * scale_value
	var length_val: float = maxf(4.0, _num(e.get("length"), 14.0)) * scale_value
	var width_val: float = maxf(2.0, _num(e.get("width"), 6.0)) * scale_value
	var fx: Dictionary = {"canvas": chart, "n": 0, "max_n": MAX_EFFECT_PRIMS, "lod": lod, "scale": scale_value}

	if kind == "fire" or etype == "muzzle":
		_draw_muzzle_effect(fx, p, ground, screen_dir, side, family, t, alpha, radius, length_val, width_val, seq)
		return int(fx.n)
	if kind == "sink" or subtype == "hull_down":
		var flood_only: bool = (reason == "flooding") and not bool(e.get("incendiary", false))
		_draw_sink_effect(fx, p, ground, t, alpha, radius, mag, hull_mat, flood_only, bool(e.get("incendiary", false)), seq)
		return int(fx.n)
	# Equipment failures keep their identity even when the last hit was explosive.
	if kind == "engine" or mat == "engine" or subtype == "engine_failure":
		_draw_hull_impact(fx, e, p, screen_dir, side, family, kind, mat, hull_mat, subtype, t, alpha, radius, length_val, mag, seq)
		return int(fx.n)
	var is_land: bool = bool(e.get("land", false)) or mat == "land"
	var is_splash: bool = bool(e.get("splash", false)) or etype == "splash" or mat == "water"
	if kind == "miss":
		if is_land:
			_draw_land_impact(fx, p, screen_dir, family, t, alpha, radius, scale_value, seq)
		else:
			_draw_water_plume(fx, ground, family, t, alpha, radius, mag, scale_value, seq, false)
		return int(fx.n)
	if family == "torpedo" or (is_splash and kind != "hit" and kind != "engine"):
		_draw_water_plume(fx, ground, family, t, alpha, radius, mag, scale_value, seq, kind == "hit")
		return int(fx.n)
	if family == "rocket" or etype == "explosion":
		_draw_rocket_blast(fx, p, ground, screen_dir, t, alpha, radius, mag, mat, hull_mat, is_splash, seq)
		return int(fx.n)
	_draw_hull_impact(fx, e, p, screen_dir, side, family, kind, mat, hull_mat, subtype, t, alpha, radius, length_val, mag, seq)
	return int(fx.n)

static func _draw_muzzle_effect(fx: Dictionary, p: Vector2, ground: Vector2, dir: Vector2, side: Vector2, family: String, t: float, alpha: float, radius: float, length_val: float, width_val: float, seq: int) -> void:
	var lod: int = int(fx.lod)
	var s: float = float(fx.scale)
	# One impulse per reported shot. Smoke may linger after the light goes out.
	var flash_env: float = clampf(1.0 - t * 3.6, 0.0, 1.0)
	var flash_a: float = alpha * flash_env
	if family == "gun":
		var gun_a: float = alpha * clampf(1.0 - t * 1.65, 0.0, 1.0)
		var gun_len: float = maxf(5.0, length_val * (0.88 + 0.24 * _det_unit(seq, 0, 11)) * (1.0 - 0.28 * t))
		var gun_w: float = maxf(1.4, width_val * 0.46)
		_fx_poly(fx, PackedVector2Array([p - side * gun_w, p + dir * gun_len, p + side * gun_w]), Color(1.0, 0.70, 0.22, gun_a * 0.94))
		_fx_line(fx, p, p + dir * gun_len * 0.78, Color(1.0, 0.99, 0.86, gun_a), maxf(1.1, 1.8 * s))
		if lod < 2:
			for side_sign in [-1.0, 1.0]:
				_fx_line(fx, p, p + dir * gun_len * 0.28 + side * side_sign * gun_w * 1.55, Color(1.0, 0.85, 0.42, gun_a * 0.82), 1.0)
		if lod == 0:
			_fx_circle(fx, p + dir * 3.0 * s + Vector2(0.0, -t * 6.0 * s), radius * (0.18 + 0.24 * t), Color(0.58, 0.60, 0.56, alpha * t * 0.30))
		return
	if family == "rocket":
		# Rearward exhaust, rather than a second cannon-shaped forward flash.
		var back_len: float = length_val * (1.10 + 0.45 * t)
		var back_w: float = maxf(2.2, width_val * (0.58 + 0.35 * t))
		var smoke_n: int = 4 if lod == 0 else (2 if lod == 1 else 1)
		for i in range(smoke_n):
			var drift: Vector2 = -dir * (back_len * 0.42 + float(i) * radius * (0.32 + 0.50 * t)) + side * _det_signed(seq, i, 21) * radius * 0.24
			_fx_circle(fx, p + drift + Vector2(0.0, -t * 12.0 * s), radius * (0.18 + 0.12 * float(i) + 0.30 * t), Color(0.56, 0.54, 0.50, alpha * 0.48))
		var exhaust_a: float = alpha * clampf(1.0 - t * 1.45, 0.0, 1.0)
		_fx_poly(fx, PackedVector2Array([
			p - side * back_w * 0.28,
			p - dir * back_len * 0.72 - side * back_w,
			p - dir * back_len,
			p - dir * back_len * 0.72 + side * back_w,
			p + side * back_w * 0.28
		]), Color(1.0, 0.42, 0.10, exhaust_a * 0.90))
		_fx_line(fx, p - dir * back_len * 0.78, p, Color(1.0, 0.93, 0.64, exhaust_a), maxf(1.2, 2.6 * s))
		_fx_line(fx, p, p + dir * length_val * 0.34, Color(1.0, 0.98, 0.82, flash_a), maxf(1.1, 2.0 * s))
		return
	if family == "torpedo":
		var mist_len: float = length_val * (0.75 + 0.55 * t)
		var mist_w: float = maxf(2.5, width_val * (0.45 + 0.45 * t))
		_fx_poly(fx, PackedVector2Array([
			ground - side * mist_w * 0.35,
			ground + dir * mist_len - side * mist_w * 0.85,
			ground + dir * mist_len * 1.28,
			ground + dir * mist_len + side * mist_w * 0.85,
			ground + side * mist_w * 0.35
		]), Color(0.80, 0.96, 0.92, alpha * 0.68))
		_fx_line(fx, ground, ground + dir * mist_len * 1.15, Color(0.95, 1.0, 0.98, alpha * 0.92), 2.4 * s)
		_fx_water_ring(fx, ground, radius * (0.35 + 0.65 * t), Color(FOAM_MID, alpha * 0.72), 1.4 * s)
		var spray_n: int = 4 if lod == 0 else (2 if lod == 1 else 1)
		for i in range(spray_n):
			var side_sign: float = -1.0 if i % 2 == 0 else 1.0
			var spread_ang: float = (0.28 + 0.16 * float(i >> 1)) * side_sign
			var v: Vector2 = dir.rotated(spread_ang) * mist_len * (0.65 + 0.25 * _det_unit(seq, i, 3))
			_fx_line(fx, ground + dir * 2.0 * s, ground + v + Vector2(0.0, -3.5 * s * (1.0 - t)), Color(FOAM_LIGHT, alpha * 0.84), 1.6 * s)
		var bub_n: int = 4 if lod == 0 else (2 if lod == 1 else 1)
		for i in range(bub_n):
			var d_step: float = (0.25 + 0.24 * float(i)) * mist_len
			var jitter_y: float = _det_signed(seq, i, 9) * mist_w * 0.45
			_fx_circle(fx, ground + dir * d_step + side * jitter_y, maxf(1.1, (2.2 - 0.3 * float(i)) * s), Color(FOAM_LIGHT, alpha * 0.82))
		return

	var cone_len: float = length_val * (1.15 - 0.42 * t)
	var cone_w: float = maxf(2.2, width_val * (0.65 - 0.20 * t))
	_fx_poly(fx, PackedVector2Array([
		p - side * cone_w * 0.42,
		p + dir * cone_len * 0.68 - side * cone_w * 0.26,
		p + dir * cone_len * 1.48,
		p + dir * cone_len * 0.68 + side * cone_w * 0.26,
		p + side * cone_w * 0.42
	]), Color(1.0, 0.58, 0.16, flash_a * 0.92))
	if lod < 2:
		_fx_poly(fx, PackedVector2Array([
			p - side * cone_w * 0.22,
			p + dir * cone_len * 0.96,
			p + side * cone_w * 0.22
		]), Color(1.0, 0.96, 0.78, flash_a * 0.96))
	_fx_line(fx, p, p + dir * cone_len * 1.22, Color(1.0, 0.98, 0.86, flash_a), maxf(1.2, 2.8 * s))
	_fx_circle(fx, p + dir * cone_len * 0.20, maxf(1.4, cone_w * 0.38), Color(1.0, 0.86, 0.46, flash_a * 0.85))

	if family == "cannon":
		for side_sign in [-1.0, 1.0]:
			var jet_dir: Vector2 = (dir * 0.45 + side * side_sign * 0.89).normalized()
			_fx_line(fx, p + dir * 2.0 * s, p + jet_dir * cone_w * 1.35, Color(1.0, 0.76, 0.30, flash_a * 0.85), maxf(1.0, 1.9 * s))
		if lod < 2:
			_fx_arc(fx, p, radius * (0.32 + 0.90 * t), dir.angle() - 1.25, dir.angle() + 1.25, 10, Color(1.0, 0.84, 0.46, alpha * flash_env * 0.72), 1.3 * s)
		var c_smoke: int = 4 if lod == 0 else (2 if lod == 1 else 1)
		for i in range(c_smoke):
			var puff_pos: Vector2 = p + dir * (cone_len * 0.35 + float(i) * radius * 0.32 * (0.5 + t)) + side * float(i - 1) * radius * 0.26
			_fx_circle(fx, puff_pos + Vector2(0.0, -t * (12.0 + 4.0 * float(i)) * s), radius * (0.18 + 0.46 * t), Color(0.28, 0.30, 0.29, alpha * (0.16 + 0.30 * t)))

	var spark_n: int = 4 if lod == 0 else (2 if lod == 1 else 1)
	for i in range(spark_n):
		var sang: float = dir.angle() + _det_signed(seq, i, 31) * 0.65
		var sdir: Vector2 = Vector2.from_angle(sang)
		var dist: float = (cone_len * 0.45 + radius * (0.35 + 1.15 * t)) * (0.7 + 0.5 * _det_unit(seq, i, 37))
		var tip: Vector2 = p + sdir * dist
		var tail: Vector2 = tip - sdir * maxf(2.5, (4.5 + 2.0 * float(i % 2)) * s)
		_fx_line(fx, tail, tip, Color(1.0, 0.86, 0.40, alpha * clampf(1.0 - t * 1.8, 0.0, 1.0)), maxf(1.0, 1.6 * s))
		if lod == 0 and i < 2:
			_fx_circle(fx, tip, maxf(0.9, 1.3 * s), Color(1.0, 0.98, 0.84, flash_a * 0.95))

static func _draw_water_plume(fx: Dictionary, ground: Vector2, family: String, t: float, alpha: float, radius: float, mag: float, s: float, seq: int, is_direct_hit: bool) -> void:
	var lod: int = int(fx.lod)
	var base_h: float = 14.0 if family == "gun" else (42.0 if family == "cannon" else (50.0 if family == "rocket" else 64.0))
	if is_direct_hit and family == "torpedo":
		base_h = 74.0
	var rise: float = clampf(t / 0.22, 0.0, 1.0)
	var fall: float = clampf((t - 0.25) / 0.75, 0.0, 1.0)
	var env: float = (0.20 + 0.80 * (1.0 - (1.0 - rise) * (1.0 - rise))) * (1.0 - fall * 0.88)
	var col_h: float = base_h * (0.82 + 0.22 * mag) * s * env
	var spread: float = radius * ((0.42 if family == "torpedo" else 0.22) + 0.78 * t)
	_fx_water_ring(fx, ground, spread, Color(FOAM_LIGHT, alpha * 0.82), maxf(1.1, 2.0 * s))
	if lod < 2:
		_fx_water_ring(fx, ground, spread * 1.32, Color(FOAM_MID, alpha * 0.48), maxf(0.9, 1.3 * s))
	if family == "rocket":
		var flash_r: float = radius * (0.28 + 0.25 * (1.0 - t))
		_fx_circle(fx, ground + Vector2(0.0, -flash_r * 0.35), flash_r, Color(1.0, 0.62, 0.20, alpha * clampf(1.0 - t * 3.2, 0.0, 1.0)))
	var col_w: float = maxf(2.2 * s, spread * (0.58 if family == "torpedo" else 0.30))
	if col_h > 2.5:
		_fx_poly(fx, PackedVector2Array([
			ground + Vector2(-col_w, 0.0),
			ground + Vector2(-col_w * 0.38, -col_h * 0.92),
			ground + Vector2(0.0, -col_h * 1.06),
			ground + Vector2(col_w * 0.38, -col_h * 0.92),
			ground + Vector2(col_w, 0.0)
		]), Color(0.82, 0.98, 1.0, alpha * 0.76))
	var jet_n: int = 6 if lod == 0 else (4 if lod == 1 else 2)
	for i in range(jet_n):
		var frac: float = (float(i) / float(maxi(1, jet_n - 1))) * 2.0 - 1.0
		var x_base: float = frac * spread * 0.42
		var x_top: float = frac * spread * (0.65 + 0.25 * _det_unit(seq, i, 53))
		var jet_h: float = col_h * (1.04 - absf(frac) * 0.34) * (0.86 + 0.24 * _det_unit(seq, i, 59))
		var top: Vector2 = ground + Vector2(x_top, -maxf(2.0 * s, jet_h))
		_fx_line(fx, ground + Vector2(x_base, 0.0), top, Color(0.82, 0.96, 0.91, alpha * 0.86), maxf(1.1, 2.6 * s))
		if lod < 2:
			_fx_circle(fx, top, maxf(1.1, (1.6 + 0.5 * float(i % 2)) * s), Color(0.95, 1.0, 0.97, alpha * 0.92))
	if is_direct_hit:
		var frag_n: int = 4 if lod == 0 else (2 if lod == 1 else 1)
		for i in range(frag_n):
			var ang: float = -PI * 0.5 + _det_signed(seq, i, 71) * 0.95
			var v: Vector2 = Vector2.from_angle(ang) * (radius * (0.45 + 1.15 * t)) + Vector2(0.0, t * t * 18.0 * s)
			var pt: Vector2 = ground + Vector2(0.0, -col_h * 0.35) + v
			_fx_line(fx, pt, pt - v.normalized() * maxf(3.0, 5.5 * s), Color(0.70, 0.84, 0.80, alpha * 0.90), maxf(1.1, 1.8 * s))
	elif lod == 0:
		for i in range(3):
			var drop_x: float = _det_signed(seq, i, 83) * spread * 1.05
			var drop_y: float = -col_h * (0.25 + 0.45 * _det_unit(seq, i, 89)) + t * t * 14.0 * s
			_fx_circle(fx, ground + Vector2(drop_x, drop_y), maxf(1.0, 1.4 * s), Color(FOAM_LIGHT, alpha * 0.78))

static func _draw_land_impact(fx: Dictionary, p: Vector2, dir: Vector2, family: String, t: float, alpha: float, radius: float, s: float, seq: int) -> void:
	var lod: int = int(fx.lod)
	var dust_n: int = 3 if lod == 0 else (2 if lod == 1 else 1)
	for i in range(dust_n):
		var off: Vector2 = Vector2.from_angle(_det_angle(seq, i, dust_n)) * radius * 0.35 * t + Vector2(0.0, -t * 10.0 * s)
		_fx_circle(fx, p + off, radius * (0.26 + 0.24 * t), Color(0.62, 0.54, 0.38, alpha * 0.52))
	if family in ["cannon", "rocket"]:
		var impact_a: float = alpha * clampf(1.0 - t * 3.4, 0.0, 1.0)
		var blast_k: float = 0.72 if family == "rocket" else 0.42
		_fx_poly(fx, _star_poly(p, radius * blast_k * (1.0 + 0.30 * t), radius * 0.22, 7 if family == "rocket" else 4, seq), Color(1.0, 0.58, 0.18, impact_a))
	var frag_n: int = 6 if lod == 0 else (4 if lod == 1 else 2)
	for i in range(frag_n):
		var ang: float = (-dir).angle() + _det_signed(seq, i, 97) * 1.35
		var delta: Vector2 = Vector2.from_angle(ang) * radius * (0.28 + 1.25 * t)
		var pt: Vector2 = p + delta + Vector2(0.0, t * t * 12.0 * s - t * 8.0 * s)
		var is_spark: bool = i % 2 == 0
		var col: Color = Color(1.0, 0.82, 0.36, alpha * 0.92) if is_spark else Color(0.58, 0.48, 0.32, alpha * 0.88)
		_fx_line(fx, pt, pt - delta.normalized() * maxf(2.5, 4.8 * s), col, maxf(1.0, 1.7 * s))

static func _draw_sink_effect(fx: Dictionary, p: Vector2, ground: Vector2, t: float, alpha: float, radius: float, mag: float, hull_mat: String, flood_only: bool, on_fire: bool, seq: int) -> void:
	var lod: int = int(fx.lod)
	var s: float = float(fx.scale)
	_fx_water_ring(fx, ground, radius * (0.45 + 0.88 * t), Color(FOAM_LIGHT, alpha * 0.82), maxf(1.2, 2.1 * s))
	if lod < 2:
		_fx_water_ring(fx, ground, radius * (0.72 + 1.18 * t), Color(FOAM_MID, alpha * 0.52), maxf(1.0, 1.4 * s))
	if flood_only:
		var swell_w: float = radius * (0.52 + 0.30 * t)
		var swell_h: float = radius * 0.58 * sin(clampf(t * 1.2, 0.08, 1.0) * PI * 0.85)
		_fx_poly(fx, PackedVector2Array([
			ground + Vector2(-swell_w, 0.0),
			ground + Vector2(-swell_w * 0.45, -swell_h),
			ground + Vector2(0.0, -swell_h * 1.18),
			ground + Vector2(swell_w * 0.45, -swell_h),
			ground + Vector2(swell_w, 0.0)
		]), Color(FOAM_MID, alpha * 0.64))
		var jet_n: int = 5 if lod == 0 else (3 if lod == 1 else 2)
		for i in range(jet_n):
			var frac: float = (float(i) / float(maxi(1, jet_n - 1))) * 2.0 - 1.0
			var jtop: Vector2 = ground + Vector2(frac * swell_w * 0.85, -swell_h * (1.15 - absf(frac) * 0.35))
			_fx_line(fx, ground + Vector2(frac * swell_w * 0.45, 0.0), jtop, Color(FOAM_LIGHT, alpha * 0.85), maxf(1.1, 2.2 * s))
		var bub_n: int = 7 if lod == 0 else (4 if lod == 1 else 2)
		for i in range(bub_n):
			var boff: Vector2 = Vector2.from_angle(_det_angle(seq, i, bub_n)) * radius * (0.18 + 0.58 * t * _det_unit(seq, i, 103))
			_fx_circle(fx, ground + boff + Vector2(0.0, -t * 10.0 * s), maxf(1.1, (1.6 + float(i % 3) * 0.7) * s), Color(FOAM_LIGHT, alpha * 0.86))
		var plank_n: int = 4 if lod == 0 else (2 if lod == 1 else 1)
		var plank_col: Color = Color(0.76, 0.56, 0.32, alpha * 0.85) if hull_mat == "wood" else Color(0.64, 0.78, 0.76, alpha * 0.85)
		for i in range(plank_n):
			var pang: float = _det_angle(seq, i, plank_n, 0.4)
			var pdir: Vector2 = Vector2.from_angle(pang)
			var ppos: Vector2 = ground + pdir * radius * (0.25 + 0.55 * t)
			_fx_line(fx, ppos - pdir.orthogonal() * 3.5 * s, ppos + pdir.orthogonal() * 3.5 * s, plank_col, maxf(1.1, 1.8 * s))
		return

	var smoke_n: int = (5 if lod == 0 else (3 if lod == 1 else 2)) if on_fire else 0
	for i in range(smoke_n):
		var soff: Vector2 = Vector2.from_angle(_det_angle(seq, i, smoke_n)) * radius * (0.20 + 0.48 * t)
		_fx_circle(fx, p + soff + Vector2(0.0, -t * radius * (0.55 + 0.15 * float(i))), radius * (0.28 + 0.22 * t), Color(0.22, 0.20, 0.19, alpha * 0.56))
	if on_fire and t < 0.72:
		var blast_a: float = alpha * clampf((0.72 - t) / 0.72, 0.15, 1.0)
		_fx_poly(fx, _star_poly(p, radius * (0.58 + 0.28 * t), radius * (0.26 + 0.12 * t), 7, seq, t * 1.2), Color(1.0, 0.46, 0.12, blast_a * 0.90))
		_fx_circle(fx, p, radius * (0.26 + 0.18 * (1.0 - t)), Color(1.0, 0.92, 0.62, blast_a * 0.95))
	var frag_n: int = 6 if lod == 0 else (4 if lod == 1 else 2)
	var is_armor: bool = hull_mat in ["armor", "metal"]
	for i in range(frag_n):
		var fang: float = _det_angle(seq, i, frag_n)
		var fdir: Vector2 = Vector2.from_angle(fang)
		var dist: float = radius * (0.28 + 1.32 * t) * (0.75 + 0.45 * _det_unit(seq, i, 109))
		var end_p: Vector2 = p + fdir * dist + Vector2(0.0, t * t * 16.0 * s - t * 11.0 * s)
		var fcol: Color = Color(0.70, 0.80, 0.78, alpha * 0.94) if is_armor else Color(0.84, 0.62, 0.34, alpha * 0.90)
		if on_fire and i % 2 == 0:fcol=Color(1.0, 0.82, 0.34, alpha * 0.94)
		_fx_line(fx, end_p, end_p - fdir * maxf(3.0, (5.5 + mag) * s), fcol, maxf(1.1, 1.9 * s))
		if lod == 0 and i < 2:
			_fx_poly(fx, _shard_poly(end_p, fdir.rotated(t * 2.2), 3.6 * s, 2.2 * s), fcol)

static func _draw_rocket_blast(fx: Dictionary, p: Vector2, ground: Vector2, dir: Vector2, t: float, alpha: float, radius: float, mag: float, mat: String, hull_mat: String, is_splash: bool, seq: int) -> void:
	var lod: int = int(fx.lod)
	var s: float = float(fx.scale)
	if is_splash or mat == "water":
		_fx_water_ring(fx, ground, radius * (0.42 + 0.85 * t), Color(FOAM_LIGHT, alpha * 0.76), maxf(1.1, 1.8 * s))
	var smoke_n: int = 5 if lod == 0 else (3 if lod == 1 else 1)
	for i in range(smoke_n):
		var soff: Vector2 = Vector2.from_angle(_det_angle(seq, i, smoke_n)) * radius * (0.22 + 0.52 * t)
		_fx_circle(fx, p + soff + Vector2(0.0, -t * radius * 0.85), radius * (0.30 + 0.20 * t), Color(0.24, 0.22, 0.20, alpha * 0.54))
	var fire_a: float = alpha * clampf(1.0 - t * 3.4, 0.0, 1.0)
	_fx_poly(fx, _star_poly(p, radius * (0.64 + 0.70 * minf(t, 0.30)), radius * 0.25, 7, seq), Color(1.0, 0.48, 0.12, fire_a * 0.92))
	if lod < 2:
		_fx_poly(fx, _star_poly(p, radius * 0.34, radius * 0.16, 5, seq + 7), Color(1.0, 0.93, 0.66, fire_a * 0.96))
	_fx_arc(fx, p, radius * (0.38 + 1.35 * t), 0.0, TAU, 14, Color(1.0, 0.74, 0.26, alpha * clampf(1.0 - t * 2.2, 0.0, 1.0) * 0.68), maxf(1.0, 1.5 * s))
	var spark_n: int = 6 if lod == 0 else (4 if lod == 1 else 2)
	var metallic: bool = mat in ["armor", "metal", "engine"] or hull_mat in ["armor", "metal"]
	for i in range(spark_n):
		var sang: float = _det_angle(seq, i, spark_n, (-dir).angle())
		var sdir: Vector2 = Vector2.from_angle(sang)
		var dist: float = radius * (0.30 + 1.38 * t) * (0.72 + 0.48 * _det_unit(seq, i, 127))
		var tip: Vector2 = p + sdir * dist + Vector2(0.0, t * t * 13.0 * s - t * 9.0 * s)
		var col: Color = Color(1.0, 0.88, 0.44, alpha * 0.95) if (metallic or i % 2 == 0) else Color(0.92, 0.66, 0.34, alpha * 0.90)
		_fx_line(fx, tip, tip - sdir * maxf(3.2, (5.5 + mag) * s), col, maxf(1.1, 1.9 * s))
		if lod == 0 and i < 3:
			_fx_circle(fx, tip, maxf(1.0, 1.5 * s), Color(1.0, 0.97, 0.82, alpha * 0.94))

static func _draw_hull_impact(fx: Dictionary, e: Dictionary, p: Vector2, dir: Vector2, side: Vector2, family: String, kind: String, mat: String, hull_mat: String, subtype: String, t: float, alpha: float, radius: float, length_val: float, mag: float, seq: int) -> void:
	# Finish the cosmetic burst within the first 65% of its existing timeline.
	if t >= 0.65:
		return
	t = clampf(t / 0.65, 0.0, 1.0)
	alpha *= 0.85 * (1.0 - t)
	radius *= 0.75
	length_val *= 0.75
	var lod: int = int(fx.lod)
	var s: float = float(fx.scale)
	var impact_a: float = alpha * clampf(1.0 - t * 3.2, 0.0, 1.0)
	var travel: float = 1.0 - (1.0 - t) * (1.0 - t)
	var is_engine: bool = kind == "engine" or mat == "engine" or bool(e.get("engineDamaged", false)) or "engine" in subtype
	var is_metal_or_armor: bool = is_engine or mat in ["armor", "metal"] or hull_mat in ["armor", "metal"] or "armor" in subtype or "metal" in subtype
	var is_cannon: bool = family == "cannon" and kind != "engine"
	# Only the damage system's reported breach selects an opening. Other armor
	# contacts retain short reflected fragments, never a new gameplay projectile.
	var penetrated: bool = bool(e.get("breach", false))
	var reflect_dir: Vector2 = -dir

	if is_engine:
		var eng_smoke: int = 2 if lod == 0 else 1
		for i in range(eng_smoke):
			var eoff: Vector2 = Vector2(_det_signed(seq, i, 131) * radius * 0.32, -t * (14.0 + 6.0 * float(i)) * s)
			_fx_circle(fx, p + eoff, radius * (0.22 + 0.18 * t), Color(0.18, 0.19, 0.20, alpha * 0.34))
		if bool(e.get("incendiary", false)):
			_fx_circle(fx, p, radius * (0.30 * (1.0 - 0.4 * t)), Color(1.0, 0.54, 0.14, alpha * 0.88))

	if is_cannon:
		var burst_r: float = radius * (0.48 + 0.22 * (1.0 - t))
		_fx_poly(fx, _star_poly(p, burst_r, burst_r * 0.44, 6, seq), Color(1.0, 0.54, 0.14, impact_a * 0.88))
		if lod < 2:
			for i in range(1):
				var c_off: Vector2 = reflect_dir * (4.0 + float(i) * 7.0) * s * t + Vector2(0.0, -t * (10.0 + float(i) * 5.0) * s)
				_fx_circle(fx, p + c_off, radius * (0.18 + 0.16 * t), Color(0.28, 0.26, 0.24, alpha * 0.26))

	if is_metal_or_armor:
		var glint_r: float = maxf(3.2 * s, radius * (0.42 - 0.14 * t))
		var glint_col: Color = Color(1.0, 0.90, 0.52, impact_a * 0.96) if (mat == "armor" or hull_mat == "armor") else Color(1.0, 0.96, 0.80, impact_a * 0.96)
		_fx_poly(fx, _star_poly(p, glint_r, glint_r * 0.32, 4, seq, dir.angle() + 0.4), glint_col)
		_fx_circle(fx, p, maxf(1.5 * s, glint_r * 0.42), Color(1.0, 0.98, 0.90, impact_a * 0.95))
		if lod < 2:
			if penetrated:
				# A short dark opening replaces the reflected streak, never adds a
				# projectile, scar record or numerical hole to the hull.
				_fx_line(fx, p - side * radius * 0.18, p + side * radius * 0.18, Color(0.07, 0.12, 0.13, alpha * 0.94), maxf(1.8, 3.4 * s))
			else:
				_fx_arc(fx, p, radius * (0.30 + 0.78 * t), reflect_dir.angle() - 1.15, reflect_dir.angle() + 1.15, 10, Color(1.0, 0.82, 0.36, alpha * 0.72), maxf(1.0, 1.5 * s))
				var rico_ang: float = reflect_dir.angle() + (0.42 if seq % 2 == 0 else -0.42)
				var rico_vec: Vector2 = Vector2.from_angle(rico_ang) * length_val * (0.55 + 0.85 * t)
				_fx_line(fx, p, p + rico_vec, Color(1.0, 0.96, 0.78, alpha * 0.92), maxf(1.2, 2.2 * s))
		var spark_n: int = 5 if lod == 0 else (3 if lod == 1 else 2)
		for i in range(spark_n):
			var sang: float = _det_angle(seq, i, spark_n, reflect_dir.angle(), PI * 1.35)
			var sdir: Vector2 = Vector2.from_angle(sang)
			var speed_k: float = 0.68 + 0.58 * _det_unit(seq, i, 149)
			var dist: float = radius * (0.26 + 1.55 * travel) * speed_k
			var tip: Vector2 = p + sdir * dist + Vector2(0.0, t * t * 14.0 * s - t * 9.0 * s)
			var streak_len: float = maxf(3.2, (6.2 + 2.8 * mag) * s * (1.0 - 0.28 * t))
			var tail: Vector2 = tip - sdir * streak_len
			var spark_col: Color = Color(1.0, 0.87, 0.42, alpha * 0.96) if i % 2 == 0 else Color(0.85, 0.95, 1.0, alpha * 0.96)
			_fx_line(fx, tail, tip, spark_col, maxf(1.1, 2.0 * s))
			if lod == 0 and i < 2:
				_fx_circle(fx, tip, maxf(1.0, 1.45 * s), Color(1.0, 0.99, 0.88, alpha * 0.96))
		if lod == 0:
			for i in range(2):
				var sh_ang: float = reflect_dir.angle() + _det_signed(seq, i, 163) * 0.85
				var sh_dir: Vector2 = Vector2.from_angle(sh_ang)
				var sh_pos: Vector2 = p + sh_dir * radius * (0.32 + 0.92 * t)
				_fx_poly(fx, _shard_poly(sh_pos, sh_dir.rotated(t * 3.0), 3.4 * s, 2.0 * s), Color(0.76, 0.82, 0.80, alpha * 0.90))
		return

	# Wood impact: high-contrast timber burst, polygonal plank shards, and flying wood splinters.
	var burst_w: float = maxf(3.0 * s, radius * (0.38 - 0.10 * t))
	_fx_poly(fx, _star_poly(p, burst_w, burst_w * 0.42, 5, seq, dir.angle()), Color(0.96, 0.80, 0.48, impact_a * 0.90))
	if lod < 2:
		_fx_circle(fx, p + reflect_dir * 3.0 * s * t + Vector2(0.0, -t * 7.0 * s), radius * (0.18 + 0.14 * t), Color(0.66, 0.50, 0.32, alpha * 0.24))
	var shard_n: int = 2 if lod == 0 else 1
	for i in range(shard_n):
		var pang: float = _det_angle(seq, i, shard_n, reflect_dir.angle(), PI * 1.25)
		var pdir: Vector2 = Vector2.from_angle(pang)
		var ppos: Vector2 = p + pdir * radius * (0.25 + 1.05 * t * (0.75 + 0.4 * _det_unit(seq, i, 173))) + Vector2(0.0, t * t * 12.0 * s - t * 8.0 * s)
		var rot_dir: Vector2 = pdir.rotated(0.4 + t * (2.4 if i % 2 == 0 else -2.4))
		var plank_col: Color = Color(0.90, 0.68, 0.38, alpha * 0.94) if i % 2 == 0 else Color(0.72, 0.48, 0.24, alpha * 0.92)
		_fx_poly(fx, _shard_poly(ppos, rot_dir, maxf(3.4, (5.8 + mag) * s), maxf(1.4, 1.8 * s)), plank_col)
	var splinter_n: int = 5 if lod == 0 else (3 if lod == 1 else 2)
	for i in range(splinter_n):
		var wang: float = _det_angle(seq, i, splinter_n, reflect_dir.angle(), PI * 1.45)
		var wdir: Vector2 = Vector2.from_angle(wang)
		var wdist: float = radius * (0.24 + 1.42 * travel) * (0.68 + 0.52 * _det_unit(seq, i, 181))
		var wend: Vector2 = p + wdir * wdist + Vector2(0.0, t * t * 14.0 * s - t * 9.5 * s)
		var wlen: float = maxf(3.5, (6.5 + 2.4 * mag) * s * (1.0 - 0.22 * t))
		var is_ember: bool = bool(e.get("incendiary", false)) and (i == 0 or (lod == 0 and i == 3))
		var wcol: Color = Color(1.0, 0.76, 0.28, alpha * 0.92) if is_ember else (Color(0.95, 0.80, 0.50, alpha * 0.94) if i % 2 == 0 else Color(0.68, 0.45, 0.22, alpha * 0.92))
		_fx_line(fx, wend - wdir * wlen, wend, wcol, maxf(1.1, 2.0 * s))

static func wreck(chart, w: Dictionary) -> int:
	if chart == null or w.is_empty():
		return 0
	var scale_value: float = _scale(chart)
	var lod: int = _lod(chart, w)
	var t: float = clampf(_num(w.get("sinkProgress"), 1.0), 0.0, 1.0)
	var age: float = maxf(0.0, _num(w.get("age"), t * 2.2))
	var w_pos := Vector2(_num(w.get("x"), 0.0), _num(w.get("y"), 0.0))
	var center: Vector2 = _project(chart, w_pos, 0.0)
	var bsize: float = maxf(10.0, _num(w.get("size"), 16.0))
	var base_angle: float = _num(w.get("angle"), 0.0)
	var list_angle: float = _num(w.get("listAngle"), 0.38)
	if absf(list_angle) < 0.05:
		list_angle = 0.38
	var seed_val: int = int(_num(w.get("seq"), float(absi(str(w.get("id", w.get("hull", "wreck"))).hash()) % 100000)))
	var cause: String = str(w.get("cause", w.get("reason", "hull"))).to_lower()
	var on_fire: bool = bool(w.get("onFire", false))
	var flood_only: bool = (cause == "flooding") and not on_fire
	var fx: Dictionary = {"canvas": chart, "n": 0, "max_n": MAX_WRECK_OVERLAY_PRIMS, "lod": lod, "scale": scale_value}

	# 1. Expanding foam collar and surface churn under the settling hull.
	var ring_fade: float = clampf(1.0 - maxf(0.0, age - 1.4) / 4.2, 0.0, 1.0)
	if ring_fade > 0.02:
		var inner_r: float = bsize * scale_value * (0.62 + 0.58 * t + minf(0.45, maxf(0.0, age - 2.0) * 0.12))
		_fx_water_ring(fx, center, inner_r, Color(FOAM_LIGHT, ring_fade * (0.62 if t < 1.0 else 0.36)), maxf(1.1, 1.8 * scale_value))
		if lod < 2:
			_fx_water_ring(fx, center, inner_r * (1.28 + 0.18 * t), Color(FOAM_MID, ring_fade * 0.38), maxf(0.9, 1.2 * scale_value))

	# 2. Listing, settling, fading hull (never projects negative height or a second reflected outline).
	var boat_prims: int = 0
	if t < 1.0 and w.get("spec") is Dictionary:
		var hull_alpha: float = clampf((1.0 - t) * (1.06 - 0.38 * t), 0.05, 1.0)
		var submerge_t: float = clampf(t * 1.12, 0.0, 1.0)
		var fade := FadeCanvas.new(chart, hull_alpha, submerge_t, true)
		var yaw: float = base_angle + list_angle * 0.24 * t
		var roll: float = list_angle * sin(minf(1.0, t * 1.30) * PI * 0.5) * 1.28
		var trim_sign: float = 1.0 if (seed_val % 2 == 0) else -1.0
		var pitch: float = trim_sign * 0.22 * t
		var waterline: float = lerpf(1.2, 16.0, clampf(t * 1.18, 0.0, 1.0))
		var v_scale: float = maxf(0.14, 1.0 - t * 0.72)
		var beam_scale: float = maxf(0.68, cos(roll) * (1.0 - 0.14 * t))
		var len_scale: float = maxf(0.76, cos(pitch) * (1.0 - 0.10 * t))
		var projector: Callable = func(pos: Vector2, h: float) -> Vector2:
			fade.last_h = h
			var h_above: float = maxf(0.0, h - waterline) * v_scale
			var rel: Vector2 = (pos - w_pos).rotated(-yaw)
			var tilted := Vector2(
				rel.x * len_scale - h_above * sin(pitch) * 0.34,
				rel.y * beam_scale + h_above * sin(roll) * 0.62
			)
			return _project(chart, w_pos + tilted.rotated(yaw), h_above)
		var boat: Dictionary = {
			"spec": w.spec,
			"x": w_pos.x,
			"y": w_pos.y,
			"angle": yaw,
			"turretAngle": _num(w.get("turretAngle"), base_angle) + list_angle * 0.20 * t,
			"localAimAngles": w.get("localAimAngles", {}),
			"vx": 0.0,
			"vy": 0.0,
			"water": 0.0,
			"fire": 0.0,
			"breaches": []
		}
		var boat_art = chart.get("BoatArt") if (chart != null and "BoatArt" in chart) else null
		if boat_art == null:
			boat_art = load("res://scripts/boat_art.gd")
		if boat_art != null:
			var boat_lod: int = maxi(1, lod)
			boat_art.draw_boat(fade, projector, boat, {
				"lod": boat_lod,
				"px": maxf(2.0, bsize * scale_value),
				"accent": Color("65746b"),
				"clock": age
			})
			boat_prims = fade.count

	# 3. Staged sinking overlays: hull-break blast/fire/smoke (when not flooding-only), foam surge, bubbles, and floating debris.
	if t < 1.0:
		var stage_a: float = clampf(1.0 - t * 0.82, 0.15, 1.0)
		var foam_n: int = 4 if lod == 0 else (3 if lod == 1 else 2)
		for i in range(foam_n):
			var fang: float = (float(i) - float(foam_n - 1) * 0.5) * 0.65
			var fworld: Vector2 = w_pos + Vector2(cos(fang) * bsize * 0.55, sin(fang) * bsize * 0.32).rotated(base_angle)
			var fp: Vector2 = _project(chart, fworld, 0.0)
			_fx_circle(fx, fp, maxf(1.5, bsize * scale_value * (0.14 + 0.12 * sin(t * PI))), Color(FOAM_LIGHT, (1.0 - t * 0.45) * 0.58))

		if not flood_only:
			if on_fire and t < 0.36:
				var blast_a: float = clampf((0.36 - t) / 0.36, 0.0, 1.0)
				var br: float = bsize * scale_value * (0.42 + 0.35 * (t / 0.36))
				_fx_poly(fx, _star_poly(center + Vector2(0.0, -4.0 * scale_value), br, br * 0.45, 6, seed_val, t * 2.0), Color(1.0, 0.48, 0.14, blast_a * 0.86))
				_fx_circle(fx, center + Vector2(0.0, -4.0 * scale_value), br * 0.38, Color(1.0, 0.92, 0.60, blast_a * 0.92))
			if on_fire and t < 0.78:
				var fire_env: float = clampf((0.78 - t) / 0.78, 0.0, 1.0)
				var flame_n: int = 3 if lod == 0 else (2 if lod == 1 else 1)
				for i in range(flame_n):
					var fx_off: float = (float(i) - 0.8) * bsize * 0.34 * (1.0 - 0.4 * t)
					var fw_pos: Vector2 = w_pos + Vector2(fx_off, list_angle * bsize * 0.18 * t).rotated(base_angle)
					var fp2: Vector2 = _project(chart, fw_pos, (10.0 + float(i) * 3.5) * (1.0 - t * 0.75))
					var fr: float = maxf(1.4, bsize * scale_value * (0.15 - 0.02 * float(i)) * fire_env)
					_fx_circle(fx, fp2, fr, Color(1.0, 0.54 + 0.14 * float(i % 2), 0.16, fire_env * 0.86))
			var smoke_n: int = (4 if lod == 0 else (3 if lod == 1 else 1)) if on_fire else 0
			for i in range(smoke_n):
				var s_progress: float = fposmod(t * 1.4 + float(i) * 0.27, 1.0)
				var s_world: Vector2 = w_pos + Vector2((float(i) - 1.2) * bsize * 0.25, 0.0).rotated(base_angle)
				var s_h: float = (12.0 + s_progress * 32.0) * (1.0 - 0.25 * t)
				var sp: Vector2 = _project(chart, s_world, s_h) + Vector2(sin(age * 2.5 + float(i)) * 3.5 * scale_value, 0.0)
				var is_steam: bool = t > 0.58 and i % 2 == 1
				var scol: Color = Color(0.80, 0.88, 0.86, stage_a * 0.42) if is_steam else Color(0.20, 0.20, 0.19, stage_a * 0.48)
				_fx_circle(fx, sp, maxf(1.8, bsize * scale_value * (0.16 + 0.16 * s_progress)), scol)
		else:
			var surge_n: int = 4 if lod == 0 else (2 if lod == 1 else 1)
			for i in range(surge_n):
				var sang: float = _det_angle(seed_val, i, surge_n, base_angle)
				var sbase: Vector2 = _project(chart, w_pos + Vector2.from_angle(sang) * bsize * 0.35, 0.0)
				var stop: Vector2 = sbase + Vector2(cos(sang) * 4.5, -bsize * (0.35 + 0.25 * sin(t * PI))) * scale_value
				_fx_line(fx, sbase, stop, Color(FOAM_LIGHT, stage_a * 0.78), maxf(1.0, 1.8 * scale_value))

	# 4. Escaping air bubbles and floating wreckage debris (during and after submergence).
	var tail_fade: float = clampf(1.0 - maxf(0.0, age - 1.8) / 4.5, 0.18, 1.0)
	var bubble_fade: float = clampf(1.0 - maxf(0.0, age - 1.8) / 4.5, 0.0, 1.0)
	var bub_count: int = 6 if lod == 0 else (4 if lod == 1 else 2)
	for i in range(bub_count):
		var bubble_phase: float = fposmod(age * 0.85 + float(i) * 0.19, 1.0)
		var b_ang: float = _det_angle(seed_val, i, bub_count, 0.3)
		var b_dist: float = bsize * (0.14 + (0.42 + 0.28 * t) * _det_unit(seed_val, i, 211))
		var b_pos: Vector2 = _project(chart, w_pos + Vector2.from_angle(b_ang) * b_dist, (1.0 - t) * 3.0)
		var b_rad: float = maxf(0.9, (1.2 + float(i % 3) * 0.55) * scale_value * (0.55 + 0.65 * bubble_phase))
		_fx_circle(fx, b_pos, b_rad, Color(FOAM_LIGHT, bubble_fade * sin(bubble_phase * PI) * (0.30 + 0.46 * t)))

	var deb_count: int = 6 if lod == 0 else (4 if lod == 1 else 3)
	for i in range(deb_count):
		var d_ang: float = float(i) * 1.18 + float(seed_val % 17) * 0.37
		var d_dist: float = bsize * (0.22 + float(i) * 0.13 + 0.28 * t)
		var d_world: Vector2 = w_pos + Vector2.from_angle(d_ang) * d_dist
		var dp: Vector2 = _project(chart, d_world, 0.0)
		var plank_dir: Vector2 = Vector2.from_angle(d_ang + 1.1 + float(i) * 0.5)
		var plen: float = maxf(2.4, (3.6 + float(i % 2) * 1.8) * scale_value)
		var dcol: Color = Color(0.74, 0.54, 0.31, tail_fade * 0.72) if str(w.get("material","wood"))=="wood" else Color(0.56, 0.70, 0.66, tail_fade * 0.58)
		_fx_line(fx, dp - plank_dir * plen * 0.5, dp + plank_dir * plen * 0.5, dcol, maxf(1.0, 1.5 * scale_value))
		if lod == 0 and i == 0 and t > 0.25:
			_fx_poly(fx, _shard_poly(dp, plank_dir, 3.2 * scale_value, 1.8 * scale_value), dcol)

	return boat_prims + int(fx.n)
