extends Node2D

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
		world_ring(Vector2(wreck.x, wreck.y), wreck.size * 1.5, Color(0.02, 0.10, 0.13, 0.35), wreck.size * scale_factor * 0.55)
	var sorted_ships = battle.ships.duplicate()
	sorted_ships.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)
	for boat in sorted_ships:
		if not boat.sunk:
			draw_boat(boat, ENEMY if boat.team == "enemy" else GOLD if boat.id == battle.playerId else FRIEND, boat.id == battle.playerId, boat.team == "enemy")
	for shot in battle.projectiles:
		var a = project(Vector2(shot.px, shot.py), 9)
		var b = project(Vector2(shot.x, shot.y), 9)
		var direction = (b - a).normalized()
		var color = Color("9bdcc5") if shot.kind == "torpedo" else ENEMY if shot.team == "enemy" else Color("ffe2a6")
		draw_line(a - direction * (9 if shot.kind == "torpedo" else 5), b, Color(color, 0.28), 5.0, true)
		draw_line(a, b, color, 3.0 if shot.kind == "torpedo" else 2.0, true)
	for effect in battle.effects:
		var t = effect.age / effect.life
		var p = project(Vector2(effect.x, effect.y), 10)
		var r = (32 if effect.type == "explosion" else 11 if effect.type == "muzzle" else 18) * scale_factor * (0.2 + t)
		var color = Color(0.65, 0.88, 0.79, 1.0 - t) if effect.type == "splash" else Color(1, 0.72, 0.37, 1 - t)
		draw_circle(p, r * 1.8, Color(color, (1.0 - t) * 0.10))
		draw_circle(p, r * 0.6, color)
		draw_arc(p, r, 0, TAU, 16, Color(0.94, 0.91, 0.71, 1 - t), 1.0, true)
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
