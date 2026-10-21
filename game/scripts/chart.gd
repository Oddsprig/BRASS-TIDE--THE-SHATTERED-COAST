extends Node2D

const BoatArt = preload("res://scripts/boat_art.gd")
const CombatArt = preload("res://scripts/combat_art.gd")
const GOLD = Color("dfbd7d")
const FOAM = Color("95cabc")
const ENEMY = Color("e8947a")
const FRIEND = Color("8fc6b4")
var host
var camera = Vector2(1300, 900)
var scale_factor = 0.36
var zoom = 1.0
var clock = 0.0
var background: Texture2D
var title_shade: Texture2D
var serif: SystemFont
var sans: SystemFont
var mono: SystemFont
var foliage: Array = []
var villages: Array = []
var follow_camera: bool = true
var tactical: bool = false
var _campaign_follow: bool = false
var _last_mode: String = ""
var _wakes: Dictionary = {}
var _trails: Array = []
var _last_trail_stamp: float = -1.0
const WAKE_MAX_PER_BOAT: int = 26
const WAKE_MAX_BOATS: int = 64
const WAKE_LIFE_SEC: float = 6.0
const TRAIL_MAX: int = 700

func setup(game_host):
	host = game_host
	serif = SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Noto Serif"])
	sans = SystemFont.new()
	sans.font_names = PackedStringArray(["Bahnschrift", "Segoe UI"])
	mono = SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New"])
	# Finished CPU images are uploaded once. No live texture updates on worker threads.
	var image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in range(128):
		for x in range(128):
			var t = (float(x) + float(y)) / 254.0
			var color = Color("183e4b").lerp(Color("20505a"), smoothstep(0.0, 0.45, t))
			color = color.lerp(Color("102d3b"), smoothstep(0.45, 1.0, t))
			image.set_pixel(x, y, color)
	background = ImageTexture.create_from_image(image)
	var shade_image = Image.create(128, 1, false, Image.FORMAT_RGBA8)
	for x in range(128):
		shade_image.set_pixel(x, 0, Color(0.025, 0.08, 0.12, 0.9 * (1.0 - smoothstep(0.0, 0.68, float(x) / 127.0))))
	title_shade = ImageTexture.create_from_image(shade_image)
	for i in range(host.data.ISLANDS.size()):
		var island = host.data.ISLANDS[i]
		var center = polygon_center(island.points)
		var trees: Array = []
		for k in range(38):
			var p = center + Vector2((noise(i * 79 + k * 3) - 0.5) * 230, (noise(i * 47 + k * 9 + 5) - 0.5) * 160)
			if Geometry2D.is_point_in_polygon(p, polygon(island.points)):
				trees.append({"p": p, "height": 17.0 + noise(k + i * 97) * 22.0, "tone": k % 3})
		foliage.append(trees)
	for port in host.data.PORTS:
		var pos = Vector2(port.x, port.y)
		var nearest = Vector2.ZERO
		var center = Vector2.ZERO
		var distance_best = INF
		for island in host.data.ISLANDS:
			var pts = polygon(island.points)
			for j in range(pts.size()):
				var v = Geometry2D.get_closest_point_to_segment(pos, pts[j], pts[(j + 1) % pts.size()])
				if v.distance_to(pos) < distance_best:
					distance_best = v.distance_to(pos)
					nearest = v
					center = polygon_center(island.points)
		villages.append({"shore": nearest, "inland": nearest.move_toward(center, 35), "center": center})

func polygon(points: Array) -> PackedVector2Array:
	var result = PackedVector2Array()
	for p in points:
		result.append(Vector2(p[0], p[1]))
	return result

func polygon_center(points: Array) -> Vector2:
	var sum = Vector2.ZERO
	for p in points:
		sum += Vector2(p[0], p[1])
	return sum / max(1, points.size())

func noise(n: float) -> float:
	return fposmod(sin(n * 127.1 + 311.7) * 43758.5453, 1.0)

func project(p: Vector2, height: float = 0.0) -> Vector2:
	var d = p - camera
	return get_viewport_rect().size * 0.5 + Vector2((d.x - d.y) * 0.82, (d.x + d.y) * 0.41 - height) * scale_factor

func world_at(screen: Vector2) -> Vector2:
	var d = (screen - get_viewport_rect().size * 0.5) / scale_factor
	var a = d.x / 0.82
	var b = d.y / 0.41
	return camera + Vector2((a + b) * 0.5, (b - a) * 0.5)

func step(dt: float):
	clock += dt
	var viewport = get_viewport_rect().size
	if host != null and "tactical_mode" in host:
		tactical = bool(host.tactical_mode)
	var mode_now: String = str(host.mode) if host != null else ""
	var mode_changed := mode_now != _last_mode
	_last_mode = mode_now
	if host != null and host.mode == "battle" and not host.battle.is_empty():
		if mode_changed:
			_wakes.clear()
			_trails.clear()
		if follow_camera:
			var boat = host.Battle.get_flagship(host.battle)
			if not boat.is_empty():
				camera = camera.lerp(Vector2(boat.x, boat.y), 1.0 - exp(-dt * 4.0))
		scale_factor = clampf(viewport.x / 1700.0, 0.65, 1.2) * zoom * (0.52 if tactical else 1.0)
		_update_wakes(host.battle.ships)
		_update_trails(host.battle.projectiles)
	elif host != null and host.mode == "menu":
		if mode_changed:
			camera = Vector2(1360, 730)
			_wakes.clear()
			_trails.clear()
		scale_factor = minf(viewport.x / 1700.0, viewport.y / 950.0) * 1.18
	else:
		if mode_changed:
			_wakes.clear()
			_trails.clear()
		if _campaign_follow and follow_camera and host != null and host.core != null and not host.core.state.is_empty():
			var wp = host.core.state.position
			camera = camera.lerp(Vector2(wp.x, wp.y), 1.0 - exp(-dt * 4.0))
		scale_factor = minf((viewport.x - 450.0) / 3050.0, (viewport.y - 210.0) / 1850.0) * zoom * (0.75 if tactical else 1.0)
		if host != null and host.core != null and not host.core.state.is_empty():
			_update_wakes(_campaign_boats())
	queue_redraw()

func _screen_to_world_delta(screen_offset: Vector2) -> Vector2:
	var d = screen_offset / maxf(0.05, scale_factor)
	var a = d.x / 0.82
	var b = d.y / 0.41
	return Vector2((a + b) * 0.5, (b - a) * 0.5)

func pan_camera(screen_direction: Vector2, dt: float, fast: bool = false):
	if dt <= 0.0 or screen_direction.length_squared() < 0.0001:
		return
	follow_camera = false
	_campaign_follow = false
	var speed := 1150.0 if fast else 540.0
	camera += _screen_to_world_delta(screen_direction.normalized() * speed * dt)
	var world_size := Vector2(2300, 1700) if (host != null and host.mode == "battle") else Vector2(2600, 1800)
	camera.x = clampf(camera.x, -450.0, world_size.x + 450.0)
	camera.y = clampf(camera.y, -450.0, world_size.y + 450.0)
	queue_redraw()

func center_camera():
	follow_camera = true
	if host == null:
		return
	if host.mode == "battle" and not host.battle.is_empty():
		var boat = host.Battle.get_flagship(host.battle)
		if not boat.is_empty():
			camera = Vector2(boat.x, boat.y)
	elif host.mode != "menu" and host.core != null and not host.core.state.is_empty():
		_campaign_follow = true
		var wp = host.core.state.position
		camera = Vector2(wp.x, wp.y)
	queue_redraw()

func set_tactical(enabled: bool):
	tactical = enabled
	if host != null and "tactical_mode" in host:
		host.tactical_mode = enabled
	queue_redraw()

func _boat_key(boat: Dictionary, fallback: int) -> String:
	if boat.has("uid"):
		return str(boat.uid)
	if boat.has("id"):
		return str(boat.id)
	return "boat-%d" % fallback

func _campaign_boats() -> Array:
	var out: Array = []
	if host == null or host.core == null or host.core.state.is_empty():
		return out
	var world = host.core.state
	var fleet = host.core.active_fleet()
	for i in range(fleet.size()):
		var boat = fleet[i].duplicate()
		var offset = Vector2.ZERO if i == 0 else Vector2(-30 * ceili(i / 2.0), (1 if i % 2 else -1) * 30)
		boat.x = world.position.x + offset.x
		boat.y = world.position.y + offset.y
		boat.angle = world.heading
		boat.turretAngle = world.heading
		var vel = Vector2.from_angle(world.heading) * (45.0 if not world.path.is_empty() else 0.0)
		boat.vx = vel.x
		boat.vy = vel.y
		out.append(boat)
	return out

func _update_wakes(boats: Array):
	var seen: Dictionary = {}
	for i in range(boats.size()):
		var boat = boats[i]
		if not (boat is Dictionary) or bool(boat.get("sunk", false)):
			continue
		var key := _boat_key(boat, i)
		pass # key tracked implicitly by _wakes membership
		if Vector2(float(boat.get("vx", 0.0)), float(boat.get("vy", 0.0))).length() < 10.0:
			continue
		var stern: Vector2 = BoatArt.stern_of(boat)
		var spec_v = boat.get("spec", {})
		var bsize := maxf(4.0, float(spec_v.get("size", 16))) if spec_v is Dictionary else 16.0
		var samples: Array = _wakes.get(key, [])
		if samples.is_empty() or Vector2(samples[samples.size() - 1].p).distance_to(stern) > bsize * 0.5:
			samples.append({"p": stern, "d": Vector2.from_angle(float(boat.get("angle", 0.0))), "t": clock, "w": bsize * 0.42})
			while samples.size() > WAKE_MAX_PER_BOAT:
				samples.pop_front()
			_wakes[key] = samples
	for key in _wakes.keys():
		var samples: Array = _wakes[key]
		while not samples.is_empty() and clock - float(samples[0].t) > WAKE_LIFE_SEC:
			samples.pop_front()
		if samples.is_empty():
			_wakes.erase(key)
		else:
			_wakes[key] = samples
	while _wakes.size() > WAKE_MAX_BOATS:
		_wakes.erase(_wakes.keys()[0])

func _update_trails(projectiles: Array):
	while not _trails.is_empty() and clock - float(_trails[0].t) > 1.4:
		_trails.pop_front()
	if clock - _last_trail_stamp < 0.03:
		return
	_last_trail_stamp = clock
	for shot in projectiles:
		if not (shot is Dictionary):
			continue
		var kind := str(shot.get("kind", ""))
		if kind in ["torpedo", "rocket"]:
			_trails.append({"p": Vector2(float(shot.x), float(shot.y)), "t": clock, "kind": kind, "life": 1.1 if kind == "torpedo" else 1.4})
	while _trails.size() > TRAIL_MAX:
		_trails.pop_front()

func _projector() -> Callable:
	return func(p: Vector2, h: float) -> Vector2: return project(p, h)

func _draw_wakes():
	if _wakes.is_empty():
		return
	var proj := _projector()
	var view := get_viewport_rect().grow(320.0)
	for key in _wakes.keys():
		var raw: Array = _wakes[key]
		if raw.size() < 2:
			continue
		if not view.has_point(project(Vector2(raw[raw.size() - 1].p))):
			continue
		var samples: Array = []
		for s in raw:
			samples.append({"p": s.p, "d": s.d, "age": clock - float(s.t), "w": s.w})
		BoatArt.draw_wake(self, proj, samples, {"life": WAKE_LIFE_SEC})

func _draw_trails():
	if _trails.is_empty():
		return
	var proj := _projector()
	for kind in ["torpedo", "rocket"]:
		var pts: Array = []
		for s in _trails:
			if str(s.kind) == kind:
				pts.append({"p": s.p, "age": clock - float(s.t), "life": float(s.life)})
		if not pts.is_empty():
			BoatArt.draw_trail(self, proj, pts, kind, {"px": maxf(4.0, 14.0 * scale_factor)})

func _selected_battle_ids(battle: Dictionary) -> Array:
	if host != null and "selected_battle_ids" in host and host.selected_battle_ids is Array and not host.selected_battle_ids.is_empty():
		return host.selected_battle_ids
	var out: Array = []
	for s in battle.get("ships", []):
		if s is Dictionary and bool(s.get("selected", false)):
			out.append(s.get("id"))
	if out.is_empty() and battle.get("playerId") != null:
		out.append(battle.playerId)
	return out

func _draw_order_indicator(battle: Dictionary, boat: Dictionary):
	var order: String = str(boat.get("order", "engage"))
	var target_data: Dictionary = boat.get("orderTarget", {})
	var target = Vector2.INF
	if target_data.has("x") and target_data.has("y"):
		target = Vector2(target_data.x, target_data.y)
	elif target_data.has("shipId"):
		for other in battle.ships:
			if str(other.id) == str(target_data.shipId) and not other.sunk:
				target = Vector2(other.x, other.y)
				break
	if target == Vector2.INF:
		return
	var color = ENEMY if order == "attack" else FRIEND if order == "escort" else GOLD
	draw_dashed_line(project(Vector2(boat.x, boat.y)), project(target), Color(color, 0.55), 1.2, 5.0, true)
	var point = project(target)
	draw_line(point-Vector2(6,6), point+Vector2(6,6), Color(color,0.9),1.4,true)
	draw_line(point+Vector2(6,-6), point+Vector2(-6,6), Color(color,0.9),1.4,true)
	world_ring(target,14.0,Color(color,0.5),1.0)

func _step_v001(dt: float):
	clock += dt
	var viewport = get_viewport_rect().size
	if host.mode == "battle" and not host.battle.is_empty():
		var boat = host.Battle.get_flagship(host.battle)
		if not boat.is_empty():
			var target = Vector2(boat.x, boat.y)
			camera = camera.lerp(target, 1.0 - exp(-dt * 4.0))
		scale_factor = clampf(viewport.x / 1700.0, 0.65, 1.2) * zoom
	elif host.mode == "menu":
		camera = Vector2(1360, 730)
		scale_factor = minf(viewport.x / 1700.0, viewport.y / 950.0) * 1.18
	else:
		camera = Vector2(1300, 900)
		scale_factor = minf((viewport.x - 450.0) / 3050.0, (viewport.y - 210.0) / 1850.0) * zoom
	queue_redraw()

func world_line(points: Array, color: Color, width: float = 1.0, height: float = 0.0):
	var output = PackedVector2Array()
	for p in points:
		output.append(project(p, height))
	if output.size() > 1:
		draw_polyline(output, color, width, true)

func world_poly(points: Array, color: Color, height: float = 0.0):
	var output = PackedVector2Array()
	for p in points:
		output.append(project(p, height))
	if output.size() > 2:
		draw_colored_polygon(output, color)

func world_ring(center: Vector2, radius: float, color: Color, width: float = 1.0):
	var points: Array = []
	for i in range(49):
		points.append(center + Vector2.from_angle(float(i) / 48 * TAU) * radius)
	world_line(points, color, width)

func text_at(text: String, pos: Vector2, font_size: int, color: Color, font: Font = null, centered: bool = false):
	if font == null:
		font = sans
	var position = pos
	if centered:
		position.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	draw_string(font, position + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.02, 0.09, 0.13, color.a * 0.8))
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw():
	if host == null or background == null:
		return
	var viewport = get_viewport_rect().size
	draw_texture_rect(background, Rect2(Vector2.ZERO, viewport), false)
	for i in range(65):
		var p = Vector2(noise(i + 7) * viewport.x, fposmod(noise(i + 101) * viewport.y + clock * (0.6 + noise(i) * 1.2), viewport.y))
		var length = 12 + noise(i + 4) * 32
		draw_line(p, p + Vector2(length, -1.4), Color(0.61, 0.82, 0.75, 0.035 + noise(i + 11) * 0.04), 1.0, true)
	if host.mode == "battle":
		draw_battle()
	elif host.mode == "menu":
		draw_title()
	else:
		draw_campaign()

func draw_island(island: Dictionary, index: int, tactical: bool = false):
	var points = polygon(island.points)
	var center = polygon_center(island.points)
	for expansion in [1.22, 1.12, 1.055]:
		var shelf: Array = []
		for p in points:
			shelf.append(center + (p - center) * expansion)
		world_poly(shelf, Color(0.28, 0.50, 0.44, 0.12 if expansion > 1.15 else 0.19), -10)
	var array: Array = []
	for p in points:
		array.append(p)
	world_poly(array, Color("0c2933"), -20)
	world_poly(array, Color("c4b788"), 0)
	var inner: Array = []
	for p in points:
		inner.append(center + (p - center) * 0.91)
	world_poly(inner, Color("506f55") if not tactical else Color("637563"), 10)
	var core: Array = []
	for p in points:
		core.append(center + (p - center) * 0.72)
	world_poly(core, Color("315547"), 22)
	for j in range(points.size()):
		var a = center + (points[j] - center) * 0.49
		var b = center + (points[(j + 1) % points.size()] - center) * 0.49
		var color = Color("6a7b60") if j % 3 == 0 else Color("466652") if j % 2 == 0 else Color("385847")
		var tri = PackedVector2Array([project(a, 24), project(b, 24), project(center + Vector2(-15, -8), 70)])
		draw_colored_polygon(tri, color)
	if not tactical and index < foliage.size():
		for tree in foliage[index]:
			draw_tree(tree.p, tree.height, tree.tone)
	if not tactical and host.mode != "menu":
		text_at(str(island.get("name", "")).to_upper(), project(center, 85), 11, Color(0.83, 0.86, 0.69, 0.55), serif, true)

func draw_tree(p: Vector2, height: float, tone: int):
	var base = project(p, 20)
	var top = project(p, height + 20)
	var width = height * 0.32 * scale_factor
	draw_line(base, top, Color("314a3b"), maxf(1.0, scale_factor * 2.0))
	draw_colored_polygon(PackedVector2Array([top, base + Vector2(-width, -3 * scale_factor), base + Vector2(width, -3 * scale_factor)]), [Color("2b5544"), Color("60816a"), Color("3b6b51")][tone])

func draw_house(p: Vector2, size_value: float, height: float, roof: Color):
	var points = [p + Vector2(-size_value, -size_value), p + Vector2(size_value, -size_value), p + Vector2(size_value, size_value), p + Vector2(-size_value, size_value)]
	var side_a = PackedVector2Array([project(points[1], 12), project(points[2], 12), project(points[2], height + 12), project(points[1], height + 12)])
	var side_b = PackedVector2Array([project(points[2], 12), project(points[3], 12), project(points[3], height + 12), project(points[2], height + 12)])
	draw_colored_polygon(side_a, Color("9d9e7d"))
	draw_colored_polygon(side_b, Color("6e806b"))
	world_poly(points, roof, height + 12)
	var window = project(p + Vector2(size_value, 1), height * 0.5 + 12)
	draw_circle(window, maxf(1.0, scale_factor * 1.7), Color("eed797"))

func draw_harbor(p: Dictionary, index: int):
	var v = villages[index]
	var position = Vector2(p.x, p.y)
	var tangent = (v.inland - position).normalized().orthogonal()
	var color = Color(host.core.faction(p.faction).get("color", "#8fb8a3"))
	world_line([v.inland, position], Color("5a7468"), maxf(4, 11 * scale_factor), 6)
	world_line([position - tangent * 24, position + tangent * 24], Color("9d9b75"), maxf(3, 7 * scale_factor), 6)
	for i in range(8):
		var home = v.inland + tangent * (i - 3.5) * 17.0 + (v.center - v.inland).normalized() * (18 + (i % 3) * 18)
		draw_house(home, 6 + i % 3, 10 + (i % 4) * 3, Color("b09466") if i % 3 else color.darkened(0.1))
	if p.industry in ["shipyard", "foundry", "refinery"]:
		draw_house(v.inland + (v.center - v.inland).normalized() * 60, 16, 22, Color("5b6b66"))
		var foot = project(v.inland + tangent * 19, 20)
		var top = project(v.inland + tangent * 19, 76)
		draw_line(foot, top, Color("b2a88c"), maxf(2.0, scale_factor * 7))
		world_line([v.inland + tangent * 19, position + tangent * 35], color, maxf(1, 3 * scale_factor), 76)
	var s = project(position)
	var selected: bool = host.selected_port == p.id
	world_ring(position, 35 if selected else 22, GOLD if selected else Color(color, 0.65), 1.5 if selected else 1.0)
	var flag = project(position + Vector2(10, 0), 56)
	draw_line(project(position + Vector2(10, 0), 8), flag, Color("c5c9a7"), 1.3)
	draw_colored_polygon(PackedVector2Array([flag, flag + Vector2(16, 5), flag + Vector2(0, 10)]), color)
	text_at(p.name, s + Vector2(0, 28), 16 if selected else 14, GOLD if selected else Color("d7e1cc"), sans, true)
	text_at(p.industry.to_upper(), s + Vector2(0, 43), 9, Color("9db8a5"), mono, true)

func draw_campaign():
	if host.core == null or host.core.state.is_empty():
		return
	var world = host.core.state
	for x in range(0, 2601, 250):
		world_line([Vector2(x, 0), Vector2(x, 1800)], Color(0.6, 0.8, 0.69, 0.027))
	for y in range(0, 1801, 250):
		world_line([Vector2(0, y), Vector2(2600, y)], Color(0.6, 0.8, 0.69, 0.027))
	for route in host.data.ROUTES:
		var a = host.core.port(route[0])
		var b = host.core.port(route[1])
		var begin = project(Vector2(a.x, a.y))
		var end = project(Vector2(b.x, b.y))
		draw_dashed_line(begin, end, Color(0.64, 0.80, 0.65, 0.12), 1.0, 3.0, true)
	for i in range(host.data.ISLANDS.size()):
		draw_island(host.data.ISLANDS[i], i)
	if not world.path.is_empty():
		var previous = Vector2(world.position.x, world.position.y)
		for step_point in world.path:
			var point = Vector2(step_point.x, step_point.y)
			draw_dashed_line(project(previous), project(point), Color(GOLD, 0.75), 1.5, 5.0, true)
			previous = point
	_draw_wakes()
	for patrol in world.patrols:
		if not patrol.active:
			continue
		var s = project(Vector2(patrol.x, patrol.y))
		var color = ENEMY if patrol.hostile else FRIEND
		draw_colored_polygon(PackedVector2Array([s + Vector2(0, -5), s + Vector2(5, 0), s + Vector2(0, 5), s + Vector2(-5, 0)]), Color(color, 0.5))
	for i in range(world.ports.size()):
		draw_harbor(world.ports[i], i)
	var fleet = host.core.active_fleet()
	for i in range(fleet.size()):
		var boat = fleet[i].duplicate()
		var offset = Vector2.ZERO if i == 0 else Vector2(-30 * ceili(i / 2.0), (1 if i % 2 else -1) * 30)
		boat.x = world.position.x + offset.x
		boat.y = world.position.y + offset.y
		boat.angle = world.heading
		boat.turretAngle = world.heading
		boat.vx = 45 if not world.path.is_empty() else 0
		boat.vy = 0
		draw_boat(boat, GOLD if i == 0 else FRIEND, i == 0, false, 1.0, true)
	var marker = project(Vector2(world.position.x, world.position.y), 50)
	text_at("YOUR FLOTILLA", marker + Vector2(0, -12), 10, GOLD, mono, true)
	if not world.activeContract.is_empty():
		var target = host.core.port(world.activeContract.targetPort)
		var p = project(Vector2(target.x, target.y), 90)
		draw_circle(p, 12, Color(GOLD, 0.12))
		text_at("⚑", p + Vector2(0, 5), 20, GOLD, sans, true)
	var size = get_viewport_rect().size
	text_at("THE SHATTER COAST", Vector2(size.x * 0.5, size.y - 175), 12, GOLD, mono, true)
	text_at("Nothing stays afloat alone.", Vector2(size.x * 0.5, size.y - 144), 26, Color("c7d4bd"), serif, true)
	text_at("CLICK A HARBOR TO CHART A COURSE  ·  SCROLL TO ZOOM", Vector2(size.x * 0.5, size.y - 118), 10, Color("93b4a8"), mono, true)
	draw_compass(Vector2(size.x - 70, size.y - 133))

func boat_shape(p: Vector2, angle: float, shape: Array, size_value: float, height: float, color: Color):
	var points: Array = []
	for v in shape:
		points.append(p + Vector2(v[0], v[1]).rotated(angle) * size_value)
	world_poly(points, color, height)

func draw_boat(boat: Dictionary, color: Color, selected: bool = false, enemy: bool = false, enlargement: float = 1.0, no_bars: bool = false):
	# v0.002: rich BoatArt geometry with offscreen culling + zoom LOD.
	# Persistent wakes are recorded in step() and drawn by _draw_wakes().
	var spec_v = boat.get("spec", {})
	if not (spec_v is Dictionary):
		return
	var boat_size := maxf(4.0, float(spec_v.get("size", 16))) * enlargement
	var p := Vector2(float(boat.get("x", 0.0)), float(boat.get("y", 0.0)))
	var screen := project(p)
	var margin: float = 120.0 + boat_size * scale_factor * 3.2
	if not get_viewport_rect().grow(margin).has_point(screen):
		return
	if selected:
		world_ring(p, boat_size * 2.6, Color(GOLD, 0.65), 1.0)
	var screen_len: float = boat_size * 3.9 * scale_factor * 0.82
	var lod := 0 if screen_len > 78.0 else (1 if screen_len > 36.0 else 2)
	if tactical:
		lod = maxi(lod, 1)
	BoatArt.draw_boat(self, _projector(), boat, {
		"accent": color, "enemy": enemy, "lod": lod, "clock": clock,
		"px": maxf(2.0, boat_size * scale_factor * 0.82), "enlargement": enlargement})
	if not no_bars and boat.has("hp") and boat.has("maxHp"):
		var center = project(p, -35)
		var width = maxf(35, boat_size * scale_factor * 2.5)
		var hp_frac = clampf(float(boat.hp) / maxf(1.0, float(boat.maxHp)), 0, 1)
		draw_rect(Rect2(center - Vector2(width / 2, 0), Vector2(width, 4)), Color("0b2632"))
		draw_rect(Rect2(center - Vector2(width / 2, 0), Vector2(width * hp_frac, 4)), ENEMY if hp_frac < 0.25 else color)
		if float(boat.get("water", 0.0)) > 0.0 and boat.has("capacity"):
			draw_rect(Rect2(center + Vector2(-width / 2, 6), Vector2(width * clampf(float(boat.water) / maxf(1.0, float(boat.capacity)), 0, 1), 2)), Color("75b9d7"))

func _draw_boat_v001(boat: Dictionary, color: Color, selected: bool = false, enemy: bool = false, enlargement: float = 1.0, no_bars: bool = false):
	var spec = boat.spec
	var p = Vector2(boat.x, boat.y)
	var angle = float(boat.get("angle", 0))
	var boat_size = spec.size * enlargement
	var beam = 0.62 + (0.12 if spec.role in ["gunboat", "rocket", "cruiser", "raider"] else 0.0)
	var hull_points = [[1.9, 0], [0.55, -beam], [-1.45, -beam * 0.87], [-1.65, -0.3], [-1.65, 0.3], [-1.45, beam * 0.87], [0.55, beam]]
	var moving = Vector2(boat.get("vx", 0), boat.get("vy", 0)).length() > 8
	if moving:
		for i in range(6):
			var wake = p + Vector2(-boat_size * (1.8 + i * 0.57) - fposmod(clock * 25, 15), 0).rotated(angle)
			var width = boat_size * (0.37 + i * 0.14)
			world_line([wake + Vector2(-4, -width).rotated(angle), wake, wake + Vector2(-4, width).rotated(angle)], Color(0.73, 0.87, 0.75, 0.22 - i * 0.03), 1.0)
	if selected:
		world_ring(p, boat_size * 2.6, Color(GOLD, 0.65), 1.0)
	boat_shape(p, angle, hull_points, boat_size * 1.06, -7, Color(0.02, 0.12, 0.16, 0.6))
	boat_shape(p, angle, hull_points, boat_size, 4, Color("182f36"))
	var outline: Array = []
	for v in hull_points:
		outline.append(p + Vector2(v[0], v[1]).rotated(angle) * boat_size)
	outline.append(outline[0])
	world_line(outline, color.darkened(0.1), maxf(1.0, scale_factor * 2), 7)
	boat_shape(p, angle, hull_points, boat_size * 0.87, 9, Color("9e956e") if not enemy else Color("94705a"))
	if spec.role == "cutter":
		for side in [-1, 1]:
			boat_shape(p, angle, [[1.45, side * 0.82], [-1.3, side * 0.82], [-1.3, side * 0.62], [1.6, side * 0.62]], boat_size, 3, color.darkened(0.45))
	var roof = Color("d0c6a1") if not enemy else Color("b0987a")
	boat_shape(p, angle, [[-0.8, -0.35], [-0.05, -0.35], [-0.05, 0.35], [-0.8, 0.35]], boat_size, 18, roof)
	boat_shape(p, angle, [[-0.67, -0.25], [-0.14, -0.25], [-0.14, 0.25], [-0.67, 0.25]], boat_size, 20, Color("355b61"))
	var helmsman = project(p + Vector2(-0.01, 0).rotated(angle) * boat_size, 19)
	draw_circle(helmsman, maxf(1.0, scale_factor * enlargement * 1.6), Color("ddc6a0"))
	if spec.role == "raider":
		for i in range(3):
			boat_shape(p + Vector2(-1.1, (i - 1) * 0.24).rotated(angle) * boat_size, angle, [[-0.16, -0.1], [0.16, -0.1], [0.16, 0.1], [-0.16, 0.1]], boat_size, 13, Color("b7a477"))
	if spec.weapon == "torpedo":
		for side in [-1, 1]:
			world_line([p + Vector2(-0.5, side * 0.47).rotated(angle) * boat_size, p + Vector2(0.9, side * 0.47).rotated(angle) * boat_size], Color("c7c7a7"), maxf(2.0, 4 * scale_factor), 13)
	if spec.weapon == "rocket":
		for i in range(4):
			var base = p + Vector2(0.65, (i - 1.5) * 0.15).rotated(angle) * boat_size
			world_line([base, base + Vector2.from_angle(angle) * boat_size * 0.6], Color("404e4d"), maxf(2.0, 3 * scale_factor), 19)
	else:
		draw_turret(p + Vector2(0.72, 0).rotated(angle) * boat_size, float(boat.get("turretAngle", angle)), boat_size, color)
		if spec.role in ["cruiser", "gunboat"]:
			draw_turret(p + Vector2(-1.12, 0).rotated(angle) * boat_size, float(boat.get("turretAngle", angle)), boat_size * 0.8, color)
	var scars = mini(3, boat.get("breaches", []).size())
	for i in range(scars):
		draw_circle(project(p + Vector2(0.2 - i * 0.4, -beam * 0.7).rotated(angle) * boat_size, 8), maxf(1.2, boat_size * scale_factor * 0.08), Color("1c3136"))
	if float(boat.get("water", 0)) > 0:
		var flood = float(boat.water) / maxf(1, boat.capacity)
		boat_shape(p, angle, hull_points, boat_size * 0.8, 10, Color(0.19, 0.57, 0.66, flood * 0.60))
	if float(boat.get("fire", 0)) > 0:
		for i in range(3):
			var at = project(p + Vector2(-0.2 + i * 0.2, 0).rotated(angle) * boat_size, 15 + i * 4)
			draw_circle(at + Vector2(sin(clock * 16 + i) * 3, 0), (4 + i) * scale_factor, Color(1.0, 0.54 + i * 0.1, 0.22, 0.85))
	if not no_bars and boat.has("hp"):
		var center = project(p, -35)
		var width = maxf(35, boat_size * scale_factor * 2.5)
		draw_rect(Rect2(center - Vector2(width / 2, 0), Vector2(width, 4)), Color("0b2632"))
		draw_rect(Rect2(center - Vector2(width / 2, 0), Vector2(width * clampf(boat.hp / boat.maxHp, 0, 1), 4)), ENEMY if boat.hp / boat.maxHp < 0.25 else color)
		if boat.water > 0:
			draw_rect(Rect2(center + Vector2(-width / 2, 6), Vector2(width * boat.water / boat.capacity, 2)), Color("75b9d7"))

func draw_turret(p: Vector2, angle: float, size_value: float, color: Color):
	world_ring(p, size_value * 0.24, color.darkened(0.5), maxf(2.5, 5 * scale_factor))
	world_line([p, p + Vector2.from_angle(angle) * size_value * 0.95], Color("283e42"), maxf(2.5, 5 * scale_factor), 15)
	world_line([p, p + Vector2.from_angle(angle) * size_value * 0.98], Color("d1ccac"), maxf(1.2, 2.3 * scale_factor), 17)

func draw_title():
	for i in range(host.data.ISLANDS.size()):
		draw_island(host.data.ISLANDS[i], i)
	var hero = {"spec": host.data.HULLS[20], "x": 1770.0 + sin(clock * 0.04) * 45, "y": 620.0 + cos(clock * 0.04) * 45, "angle": 0.9, "turretAngle": 0.8, "vx": 45, "vy": 25, "water": 0, "fire": 0, "breaches": []}
	draw_boat(hero, GOLD, false, false, 2.0, true)
	for i in range(2):
		var escort = hero.duplicate()
		escort.spec = host.data.HULLS[2 + i * 3]
		escort.x -= 140 + i * 90
		escort.y += 140 - i * 140
		draw_boat(escort, FRIEND, false, false, 1.8, true)
	var size = get_viewport_rect().size
	draw_texture_rect(title_shade, Rect2(Vector2.ZERO, size), false)
	draw_compass(Vector2(size.x - 85, size.y - 95))
	text_at("14° 27′ N  /  108° 12′ E", Vector2(size.x - 290, size.y - 35), 11, Color(0.7, 0.83, 0.72, 0.5), mono)

func draw_battle():
	var battle = host.battle
	if battle.is_empty():
		return
	for i in range(battle.islands.size()):
		draw_island(battle.islands[i], i, true)
	var flagship = host.Battle.get_flagship(battle)
	if not flagship.is_empty():
		world_ring(Vector2(flagship.x, flagship.y), flagship.spec.range, Color(0.75, 0.84, 0.63, 0.07), 1.0)
	for wreck in battle.wrecks:
		CombatArt.wreck(self,wreck)
	_draw_wakes()
	_draw_trails()
	var selected_ids := _selected_battle_ids(battle)
	var sorted_ships = battle.ships.duplicate()
	sorted_ships.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)
	for boat in sorted_ships:
		if not boat.sunk:
			var is_sel: bool = boat.id in selected_ids or bool(boat.get("selected", false))
			draw_boat(boat, ENEMY if boat.team == "enemy" else GOLD if boat.id == battle.playerId else FRIEND, is_sel, boat.team == "enemy")
			if is_sel and boat.team == "player":
				_draw_order_indicator(battle, boat)
	for shot in battle.projectiles:
		BoatArt.draw_projectile(self, _projector(), shot, {})
		pass # projectile body drawn by BoatArt above
		pass
		pass
		pass
		pass
	for effect in battle.effects:
		CombatArt.effect(self,effect)
	if not flagship.is_empty():
		var nearest: Dictionary = {}
		var best = INF
		for foe in battle.ships:
			if foe.team != "enemy" or foe.sunk:
				continue
			var d = Vector2(foe.x - flagship.x, foe.y - flagship.y).length()
			if d < best:
				best = d
				nearest = foe
		if not nearest.is_empty():
			var p = project(Vector2(nearest.x, nearest.y))
			var size = get_viewport_rect().size
			var clamped = Vector2(clampf(p.x, 355, size.x - 355), clampf(p.y, 125, size.y - 180))
			if clamped.distance_to(p) > 15:
				var direction = (p - clamped).normalized()
				draw_colored_polygon(PackedVector2Array([clamped + direction * 12, clamped - direction * 7 + direction.orthogonal() * 6, clamped - direction * 7 - direction.orthogonal() * 6]), ENEMY)
				text_at("%d m" % best, clamped + Vector2(0, 27), 12, ENEMY, mono, true)
	var mouse = get_global_mouse_position()
	draw_arc(mouse, 9, 0, TAU, 24, Color(GOLD, 0.75), 1, true)
	draw_line(mouse - Vector2(15, 0), mouse - Vector2(5, 0), Color(GOLD, 0.8), 1, true)
	draw_line(mouse + Vector2(5, 0), mouse + Vector2(15, 0), Color(GOLD, 0.8), 1, true)
	draw_minimap()
	if host.paused and not host.ui.modal_open:
		var size = get_viewport_rect().size
		text_at("TACTICAL PAUSE", Vector2(size.x * 0.5, 128), 28, GOLD, serif, true)
		text_at("SET CREW PRIORITIES AND FLEET ORDERS · SPACE TO RESUME", Vector2(size.x * 0.5, 155), 11, Color("c6d2be"), mono, true)

func draw_minimap():
	var size = get_viewport_rect().size
	var box = Rect2(size.x - 240, size.y - 275, 190, 140)
	draw_rect(box, Color(0.025, 0.10, 0.14, 0.88))
	draw_rect(box, Color(0.5, 0.70, 0.59, 0.35), false, 1)
	for island in host.battle.islands:
		var points = PackedVector2Array()
		for p in island.points:
			points.append(box.position + Vector2(p[0] / 2300.0 * box.size.x, p[1] / 1700.0 * box.size.y))
		draw_colored_polygon(points, Color("5f7861"))
	for boat in host.battle.ships:
		if not boat.sunk:
			var p = box.position + Vector2(boat.x / 2300.0 * box.size.x, boat.y / 1700.0 * box.size.y)
			draw_circle(p, 3 if boat.id == host.battle.playerId else 2, ENEMY if boat.team == "enemy" else GOLD if boat.id == host.battle.playerId else FRIEND)
	text_at("TACTICAL CHART", box.position - Vector2(0, 9), 10, Color("acc6b4"), mono)

func draw_compass(p: Vector2):
	draw_arc(p, 27, 0, TAU, 48, Color(0.69, 0.79, 0.65, 0.35), 1, true)
	draw_line(p - Vector2(35, 0), p + Vector2(35, 0), Color(0.69, 0.79, 0.65, 0.28), 1, true)
	draw_line(p - Vector2(0, 35), p + Vector2(0, 35), Color(0.69, 0.79, 0.65, 0.28), 1, true)
	draw_colored_polygon(PackedVector2Array([p - Vector2(0, 26), p + Vector2(4, 3), p + Vector2(-4, 3)]), Color(GOLD, 0.45))
	text_at("N", p - Vector2(0, 43), 10, Color(GOLD, 0.6), mono, true)
