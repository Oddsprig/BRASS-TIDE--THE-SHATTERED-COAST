extends RefCounted
## Short stern wash, submitted on the main thread before the hulls. No state,
## textures, shaders, particles, reflection or synthetic heading extension.
## samples are oldest -> newest: {p: stern Vector2, age: seconds, w: half-width}.
## Legacy d (bow heading) is deliberately ignored: the actual path owns the bend.
const LIFE_SEC: float = 0.7
const MAX_SAMPLES: int = 12
const MAX_INPUT_SAMPLES: int = 26
const MAX_PRIMITIVES: int = 3
const MAX_LENGTH: float = 96.0
const MAX_WIDTH: float = 12.0
const MAX_VERTICES: int = MAX_SAMPLES * 2 - 1
const MIN_PAINT_AREA: float = 0.01 # Screen pixels squared, below visible paint.
const MIN_EDGE_SQUARED: float = 0.000001
const MIN_CORNER_CROSS: float = 0.0001

## Private to one Chart._draw_wakes call. Even an 80-boat input is bounded by
## the existing sample/band ceilings; the live producer currently retains64.
class _FrameBatch051 extends RefCounted:
	const MAX_BANDS: int = 80 * MAX_PRIMITIVES
	const MAX_POINTS: int = MAX_BANDS * MAX_VERTICES
	const MAX_INDICES: int = MAX_BANDS * (MAX_VERTICES - 2) * 3
	var canvas: CanvasItem
	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()
	var bands: int = 0
	var active: bool = true

	func _init(target: CanvasItem) -> void:
		canvas = target

	func _append_band(screen_points: PackedVector2Array, band_indices: PackedInt32Array, color: Color) -> bool:
		if not active:
			return false
		if bands >= MAX_BANDS or screen_points.size() > MAX_VERTICES or points.size() + screen_points.size() > MAX_POINTS or indices.size() + band_indices.size() > MAX_INDICES:
			_fallback()
			return false
		var offset: int = points.size()
		points.append_array(screen_points)
		for index in band_indices:
			indices.append(offset + index)
		for _point in screen_points:
			colors.append(color)
		bands += 1
		return true

	func _flush() -> void:
		if indices.is_empty():
			return
		canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, points, colors)
		points.clear()
		indices.clear()
		colors.clear()
		bands = 0

	func _fallback() -> void:
		# Paint the collected prefix BEFORE any ordinary band. Never reorder a
		# translucent fallback, or discard the prefix when a limit is reached.
		_flush()
		active = false

static func _life(opts: Dictionary) -> float:
	var value: float = float(opts.get("life", LIFE_SEC))
	return clampf(value, 0.1, LIFE_SEC) if is_finite(value) else LIFE_SEC

## Bounded read-only suffix. A teleport, reversal cusp or tight loop ends the
## strip instead of bridging across water the stern did not travel through.
static func _path(samples: Array, life: float) -> Array:
	var newest_first: Array = []
	var distance: float = 0.0
	var turn: float = 0.0
	var previous_direction := Vector2.ZERO
	var limit: float = MAX_LENGTH
	for index in range(samples.size() - 1, maxi(-1, samples.size() - MAX_INPUT_SAMPLES - 1), -1):
		var sample = samples[index]
		if not (sample is Dictionary) or not (sample.get("p") is Vector2):
			break
		var point: Vector2 = sample.p
		var age: float = float(sample.get("age", life))
		var width: float = float(sample.get("w", 5.0))
		if not point.is_finite() or not is_finite(age) or not is_finite(width) or age < 0.0 or age >= life or width <= 0.0:
			break
		width = minf(width, MAX_WIDTH)
		if newest_first.is_empty():
			limit = minf(MAX_LENGTH, width * 10.0)
		else:
			var newer: Dictionary = newest_first.back()
			if age < float(newer.age):
				break
			var delta: Vector2 = Vector2(newer.p) - point
			var step: float = delta.length()
			if step < 0.05:
				continue
			if step > minf(limit, width * 6.0):
				break
			var direction: Vector2 = delta / step
			if previous_direction != Vector2.ZERO:
				var alignment: float = clampf(previous_direction.dot(direction), -1.0, 1.0)
				turn += acos(alignment)
				if alignment <= 0.0 or turn > PI * 0.75:
					break
			previous_direction = direction
			if distance + step > limit:
				var fraction: float = (limit - distance) / step
				if fraction > 0.001:
					var clipped: Vector2 = Vector2(newer.p).lerp(point, fraction)
					if clipped != Vector2(newer.p): # Float32 clipping must not add a duplicate tail.
						newest_first.append({"p": clipped, "age": lerpf(float(newer.age), age, fraction), "w": lerpf(float(newer.w), width, fraction)})
				break
			distance += step
		newest_first.append({"p": point, "age": age, "w": width})
		if newest_first.size() >= MAX_SAMPLES:
			break
	newest_first.reverse()
	return newest_first

## _path admits a direction sector of at most 135 degrees. Its bisector has a
## positive dot product with EVERY segment, even when a short slow turn follows
## a long step. Parallel sections normal to that axis are strictly ordered;
## neither edge nor the full-width stern cap can fold across an older section.
## Rotating local normals did not have that guarantee at nonuniform spacing.
static func _side(path: Array) -> Vector2:
	var first: Vector2 = (Vector2(path[1].p) - Vector2(path[0].p)).normalized()
	var previous: Vector2 = first
	var angle: float = 0.0
	var low: float = 0.0
	var high: float = 0.0
	for index in range(2, path.size()):
		var direction: Vector2 = (Vector2(path[index].p) - Vector2(path[index - 1].p)).normalized()
		angle += previous.angle_to(direction)
		low = minf(low, angle)
		high = maxf(high, angle)
		previous = direction
	return first.rotated((low + high) * 0.5).orthogonal()

## Affine water projection can round the fading tip's two edges to the same
## screen point. Remove only subpixel edges/zero-area corners, including a
## collapsed out-and-back tip. Do not reject a visible path on triangulation
## failure: the ordered construction above supplies the noncrossing boundary.
static func _paint_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var polygon: PackedVector2Array = points.duplicate()
	var changed: bool = true
	while changed and polygon.size() >= 3:
		changed = false
		for index in range(polygon.size()):
			var before: Vector2 = polygon[(index + polygon.size() - 1) % polygon.size()]
			var point: Vector2 = polygon[index]
			var after: Vector2 = polygon[(index + 1) % polygon.size()]
			if before.distance_squared_to(point) <= MIN_EDGE_SQUARED or absf((point - before).cross(after - point)) <= MIN_CORNER_CROSS:
				polygon.remove_at(index)
				changed = true
				break
	if polygon.size() < 3:
		return PackedVector2Array()
	# Translation-relative area avoids subtracting large screen coordinates.
	var origin: Vector2 = polygon[0]
	var twice_area: float = 0.0
	for index in range(1, polygon.size() - 1):
		twice_area += (polygon[index] - origin).cross(polygon[index + 1] - origin)
	return polygon if absf(twice_area) >= MIN_PAINT_AREA * 2.0 else PackedVector2Array()

## Uncut ribbon, plus-rail then minus-rail. The tip is one triangle. Each later
## span is a trapezoid with sides parallel to _side, so these two triangles stay
## inside that span and do not cover a neighbor. Not valid after a vertex is cut.
static func _ribbon_indices(count: int) -> PackedInt32Array:
	var indices := PackedInt32Array()
	if count < 3:
		return indices
	var samples: int = (count + 1) / 2
	indices.append(0)
	indices.append(1)
	indices.append(count - 1)
	for index in range(1, samples - 1):
		indices.append(index)
		indices.append(index + 1)
		indices.append(count - index)
		indices.append(index + 1)
		indices.append(count - index - 1)
		indices.append(count - index)
	return indices

## Read-only. uncut means _paint_polygon removed nothing. A cut outline uses
## Geometry2D.triangulate_polygon, the same indices draw_colored_polygon builds.
static func _band_indices(polygon: PackedVector2Array, uncut: bool) -> PackedInt32Array:
	if polygon.size() < 3:
		return PackedInt32Array()
	if uncut and polygon.size() % 2 == 1:
		return _ribbon_indices(polygon.size())
	return Geometry2D.triangulate_polygon(polygon)

## Canvas contract: one colored band, then identity. Enter at identity.
## By default a CanvasItem gets one triangle array per band. Chart's private
## frame batch instead retains screen points/colors in that same paint order.
## Any other canvas, including
## recorders, still gets draw_colored_polygon with the same local vertices.
## projector(world: Vector2, height: float) -> Vector2 is the affine water plane.
## Every height is zero. Geometry cleanup is in projected screen coordinates.
## opts.life may shorten the wash; opts.clip_rect is a screen-space cull rect.
## The CanvasItem/viewport performs the final edge crop, including partial strips.
static func draw(canvas, projector: Callable, samples: Array, opts: Dictionary = {}) -> int:
	var batch: _FrameBatch051 = null
	var requested_batch = opts.get("_frame_batch051")
	if requested_batch is _FrameBatch051:
		batch = requested_batch
		if not (canvas is CanvasItem) or canvas != batch.canvas or not bool(opts.get("affine_water", false)):
			batch._fallback()
			batch = null
	var life: float = _life(opts)
	var path: Array = _path(samples, life)
	if path.size() < 2:
		return 0
	var distances: Array[float] = [0.0]
	for index in range(1, path.size()):
		distances.append(distances.back() + Vector2(path[index].p).distance_to(path[index - 1].p))
	var length: float = distances.back()
	if length < 0.1:
		return 0
	var fade: float = pow(1.0 - float(path.back().age) / life, 1.6)
	var side: Vector2 = _side(path)
	var widths: Array[float] = []
	for index in range(path.size()):
		var along: float = distances[index] / length
		var age_fade: float = sqrt(maxf(0.0, 1.0 - float(path[index].age) / life))
		var width: float = minf(float(path[index].w) * 0.62, length * 0.24)
		widths.append(width * smoothstep(0.0, 0.65, along) * age_fade)
	var colors: Array[Color] = [Color(0.58, 0.81, 0.78, 0.13 * fade), Color(0.75, 0.91, 0.86, 0.17 * fade), Color(0.92, 0.98, 0.93, 0.18 * fade)]
	var scales: Array[float] = [1.0, 0.57, 0.20]
	# The water projector is affine. Project each center once, then share its
	# screen-space side vector across all three bands instead of invoking the
	# projector twice per vertex per band. The foam geometry and fades stay live.
	var affine: bool = bool(opts.get("affine_water", false))
	var centers := PackedVector2Array()
	var screen_side := Vector2.ZERO
	if affine:
		for sample: Dictionary in path:
			var center = projector.call(Vector2(sample.p), 0.0)
			if not (center is Vector2) or not center.is_finite():
				return 0
			centers.append(center)
		var side_point = projector.call(Vector2(path[0].p) + side, 0.0)
		if not (side_point is Vector2) or not side_point.is_finite():
			return 0
		screen_side = Vector2(side_point) - centers[0]
	var count: int = 0
	for layer in range(MAX_PRIMITIVES):
		var polygon := PackedVector2Array()
		for index in range(path.size()):
			if affine:
				polygon.append(centers[index] + screen_side * widths[index] * scales[layer])
			else:
				var projected = projector.call(Vector2(path[index].p) + side * widths[index] * scales[layer], 0.0)
				if not (projected is Vector2) or not projected.is_finite():return count
				polygon.append(projected)
		# The tail is one shared point, not duplicate zero-width edge vertices.
		for index in range(path.size() - 1, 0, -1):
			if affine:
				polygon.append(centers[index] - screen_side * widths[index] * scales[layer])
			else:
				var projected = projector.call(Vector2(path[index].p) - side * widths[index] * scales[layer], 0.0)
				if not (projected is Vector2) or not projected.is_finite():return count
				polygon.append(projected)
		var built: int = polygon.size()
		polygon = _paint_polygon(polygon)
		if polygon.is_empty():
			continue
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			bounds = bounds.expand(point)
		if opts.get("clip_rect") is Rect2 and not Rect2(opts.clip_rect).intersects(bounds):
			continue
		# Ear clipping sums absolute float32 crosses. Thin foam loses that sign
		# near a large screen origin, so only the submission is translated.
		# Cleaned vertices and screen paint stay the same. An uncut band does
		# not call the triangulator; a cut band asks for its exact indices.
		var uncut: bool = polygon.size() == built
		# An uncut ribbon's indices depend only on vertex count. The frame
		# batch consumes screen points, so no local copy/translation is needed.
		# Cut bands still condition their coordinates for native triangulation.
		if batch != null and batch.active and uncut and affine:
			var ribbon: PackedInt32Array = _ribbon_indices(polygon.size())
			if batch._append_band(polygon, ribbon, colors[layer]):
				count += 1
				continue
		# Keep the original projected points, before float32 origin subtraction.
		# Indices still come from the exact same conditioned local polygon.
		var screen_polygon: PackedVector2Array = polygon.duplicate() if batch != null and batch.active else PackedVector2Array()
		var origin: Vector2 = polygon[0]
		for index in range(polygon.size()):
			polygon[index] -= origin
		if canvas is CanvasItem:
			# Only Chart's explicit affine water projection proves parallel rails.
			# Arbitrary public/custom projectors retain native triangulation.
			var indices: PackedInt32Array = _band_indices(polygon, uncut and affine)
			if not indices.is_empty():
				if batch != null and batch._append_band(screen_polygon, indices, colors[layer]):
					count += 1
					continue
				canvas.draw_set_transform_matrix(Transform2D(0.0, origin))
				# One color is copied onto every vertex, as draw_colored_polygon does.
				RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, polygon, PackedColorArray([colors[layer]]))
				canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		else:
			canvas.draw_set_transform_matrix(Transform2D(0.0, origin))
			canvas.draw_colored_polygon(polygon, colors[layer])
			canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		count += 1
	return count
