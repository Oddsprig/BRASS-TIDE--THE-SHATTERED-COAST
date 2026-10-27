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
					newest_first.append({"p": Vector2(newer.p).lerp(point, fraction), "age": lerpf(float(newer.age), age, fraction), "w": lerpf(float(newer.w), width, fraction)})
				break
			distance += step
		newest_first.append({"p": point, "age": age, "w": width})
		if newest_first.size() >= MAX_SAMPLES:
			break
	newest_first.reverse()
	return newest_first

## Canvas contract: draw_colored_polygon(PackedVector2Array, Color).
## projector(world: Vector2, height: float) -> Vector2. Every height is zero.
## opts.life may shorten the wash; opts.clip_rect is a screen-space cull rect.
## The CanvasItem/viewport performs the final edge crop, including partial strips.
static func draw(canvas, projector: Callable, samples: Array, opts: Dictionary = {}) -> int:
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
	var sides: Array[Vector2] = []
	var widths: Array[float] = []
	for index in range(path.size()):
		var incoming: Vector2 = (Vector2(path[index].p) - Vector2(path[maxi(0, index - 1)].p)).normalized()
		var outgoing: Vector2 = (Vector2(path[mini(index + 1, path.size() - 1)].p) - Vector2(path[index].p)).normalized()
		var tangent: Vector2 = (incoming + outgoing).normalized()
		sides.append(tangent.orthogonal())
		var along: float = distances[index] / length
		var age_fade: float = sqrt(maxf(0.0, 1.0 - float(path[index].age) / life))
		var width: float = minf(float(path[index].w) * 0.62, length * 0.24)
		if index > 0 and index + 1 < path.size():
			# Stay inside the bend radius; a slow tight turn must not fold its ribbon.
			var sine_half: float = sqrt(maxf(0.0, (1.0 - incoming.dot(outgoing)) * 0.5))
			if sine_half > 0.01:
				var spacing: float = minf(distances[index] - distances[index - 1], distances[index + 1] - distances[index])
				width = minf(width, spacing / (2.0 * sine_half) * 0.42)
		widths.append(width * smoothstep(0.0, 0.65, along) * age_fade)
	var colors: Array[Color] = [Color(0.58, 0.81, 0.78, 0.13 * fade), Color(0.75, 0.91, 0.86, 0.17 * fade), Color(0.92, 0.98, 0.93, 0.18 * fade)]
	var scales: Array[float] = [1.0, 0.57, 0.20]
	var count: int = 0
	for layer in range(MAX_PRIMITIVES):
		var polygon := PackedVector2Array()
		for index in range(path.size()):
			var world: Vector2 = Vector2(path[index].p) + sides[index] * widths[index] * scales[layer]
			var projected = projector.call(world, 0.0)
			if not (projected is Vector2) or not projected.is_finite():
				return count
			polygon.append(projected)
		# The tail is one shared point, not duplicate zero-width edge vertices.
		for index in range(path.size() - 1, 0, -1):
			var world: Vector2 = Vector2(path[index].p) - sides[index] * widths[index] * scales[layer]
			var projected = projector.call(world, 0.0)
			if not (projected is Vector2) or not projected.is_finite():
				return count
			polygon.append(projected)
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			bounds = bounds.expand(point)
		if opts.get("clip_rect") is Rect2 and not Rect2(opts.clip_rect).intersects(bounds):
			continue
		canvas.draw_colored_polygon(polygon, colors[layer])
		count += 1
	return count
