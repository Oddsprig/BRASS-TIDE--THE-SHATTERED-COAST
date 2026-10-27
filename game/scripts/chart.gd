extends Node2D

const BoatArt = preload("res://scripts/boat_art.gd")
const CombatArt = preload("res://scripts/combat_art.gd")
const NauticalArt=preload("res://scripts/nautical_art.gd")
const GOLD = Color("dfbd7d")
const FOAM = Color("95cabc")
const ENEMY = Color("e8947a")
const FRIEND = Color("8fc6b4")
var host
var camera = Vector2(1300, 900)
var scale_factor = 0.36
var zoom = 1.0
var clock = 0.0
var presentation_us: int=0
var _profile_enabled: bool=false
var _profile_drawing: bool=false
var _profile_draws: int=0
var _profile_frame: Dictionary={}
var _profile_wake_update_us: int=0
var _profile_trail_update_us: int=0
var _profile_wake_updates: int=0
var background: Texture2D
var title_shade: Texture2D
var serif: SystemFont
var sans: SystemFont
var mono: SystemFont
var foliage: Array = []
var villages: Array = []
var _trade_data=null
var _trade_revision: int=-1
var _trade_paths: Array=[]
var follow_camera: bool = true
var tactical: bool = false
var _campaign_follow: bool = false
var _last_mode: String = ""
var _map_labels: Array=[]
var _wakes: Dictionary = {}
var _trails: Array = []
var _last_trail_stamp: float = -1.0
const WAKE_MAX_PER_BOAT: int = 26
const WAKE_MAX_BOATS: int = 64
const WAKE_LIFE_SEC: float = 6.0
const TRAIL_MAX: int = 700
const ISO_X := 0.82
const ISO_Y := 0.41
var _chart_sheet: Array = []
var _chart_ready: bool = false
var _chart_towns: Dictionary={}

## Main-thread opt-in attribution only. Timings are CPU submission, not GPU/FPS.
## Static child counters include every caller in this process, including UI.
func profile_enable(enabled: bool=true) -> void:
	_profile_enabled=enabled
	BoatArt.MeshCache.profile_enable(enabled)
	CombatArt.profile_enable(enabled)

func profile_reset() -> void:
	_profile_draws=0;_profile_frame={}
	_profile_wake_update_us=0;_profile_trail_update_us=0;_profile_wake_updates=0
	BoatArt.MeshCache.profile_reset()
	CombatArt.profile_reset()

func profile_read() -> Dictionary:
	return {"enabled":_profile_enabled,"draws":_profile_draws,"last_frame":_profile_frame.duplicate(),
		"mesh_cache":BoatArt.MeshCache.profile_read(),"combat_art":CombatArt.profile_read()}

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

func nautical_chart() -> bool:
	# Campaign and the title chart are top-down. Battles keep the isometric frame.
	return host == null or str(host.mode) != "battle"

func project(p: Vector2, height: float = 0.0) -> Vector2:
	var d = p - camera
	var origin := get_viewport_rect().size * 0.5
	if nautical_chart():
		return origin + d * scale_factor
	return origin + Vector2((d.x - d.y) * ISO_X, (d.x + d.y) * ISO_Y - height) * scale_factor

func world_at(screen: Vector2) -> Vector2:
	var d = (screen - get_viewport_rect().size * 0.5) / maxf(0.0001, scale_factor)
	if nautical_chart():
		return camera + d
	var a = d.x / ISO_X
	var b = d.y / ISO_Y
	return camera + Vector2((a + b) * 0.5, (b - a) * 0.5)

func _chart_plane(p: Vector2) -> Vector2:
	if nautical_chart():
		return p
	return Vector2((p.x - p.y) * ISO_X, (p.x + p.y) * ISO_Y)

func _plane_to_world(p: Vector2) -> Vector2:
	if nautical_chart():
		return p
	return Vector2((p.x / ISO_X + p.y / ISO_Y) * 0.5, (p.y / ISO_Y - p.x / ISO_X) * 0.5)

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
		var wake_started: int=Time.get_ticks_usec() if _profile_enabled else 0
		_update_wakes(host.battle.ships)
		if _profile_enabled:
			_profile_wake_update_us+=Time.get_ticks_usec()-wake_started
			_profile_wake_updates+=1
		var trail_started: int=Time.get_ticks_usec() if _profile_enabled else 0
		_update_trails(host.battle.projectiles)
		if _profile_enabled:_profile_trail_update_us+=Time.get_ticks_usec()-trail_started
	elif host != null and host.mode == "menu":
		if mode_changed:
			var home: Dictionary=host.data.PORTS[0]
			camera = Vector2(home.x,home.y)+Vector2(-120,150)
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
		scale_factor = regional_scale() * zoom * (0.75 if tactical else 1.0)
	queue_redraw()

func _screen_to_world_delta(screen_offset: Vector2) -> Vector2:
	var d = screen_offset / maxf(0.05, scale_factor)
	if nautical_chart():
		return d
	var a = d.x / ISO_X
	var b = d.y / ISO_Y
	return Vector2((a + b) * 0.5, (b - a) * 0.5)

func pan_camera(screen_direction: Vector2, dt: float, fast: bool = false):
	if dt <= 0.0 or screen_direction.length_squared() < 0.0001:
		return
	follow_camera = false
	_campaign_follow = false
	var speed := 1150.0 if fast else 540.0
	camera += _screen_to_world_delta(screen_direction.normalized() * speed * dt)
	var world_size := Vector2(2300, 1700) if (host != null and host.mode == "battle") else Vector2(host.data.WORLD.width,host.data.WORLD.height)
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
		zoom=1.0
		_campaign_follow = true
		var wp = host.core.state.position
		camera = Vector2(wp.x, wp.y)
	queue_redraw()

func regional_scale() -> float:
	var viewport=get_viewport_rect().size
	return maxf(0.15,minf((viewport.x-560.0)/2100.0,(viewport.y-260.0)/1150.0))

func territory_view():
	follow_camera=false;_campaign_follow=false
	var viewport=get_viewport_rect().size
	var coast: Rect2=Rect2()
	var first: bool=true
	for island in host.data.ISLANDS:
		for point in island.points:
			var p:=_chart_plane(Vector2(float(point[0]),float(point[1])))
			if first:coast=Rect2(p,Vector2.ONE);first=false
			else:coast=coast.expand(p)
	for port in host.data.PORTS:
		coast=coast.expand(_chart_plane(Vector2(float(port.x),float(port.y))))
	var usable: Rect2=chart_label_bounds(viewport).grow(-40)
	var fit_scale: float=minf(usable.size.x/maxf(1.0,coast.size.x),usable.size.y/maxf(1.0,coast.size.y))
	zoom=clampf(fit_scale/regional_scale(),0.10,1.0)
	fit_scale=regional_scale()*zoom
	var center: Vector2=coast.get_center()-(usable.get_center()-viewport*0.5)/maxf(0.01,fit_scale)
	camera=_plane_to_world(center)
	queue_redraw()
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
	const WakeArt = preload("res://scripts/wake_art045.gd")
	# Keep only the history the wash can actually draw. Never refresh a resting
	# stern's timestamp: existing foam fades in its original world position.
	for key in _wakes.keys():
		var samples: Array = _wakes[key]
		while not samples.is_empty() and clock - float(samples[0].t) >= WakeArt.LIFE_SEC:
			samples.pop_front()
		if samples.is_empty():
			_wakes.erase(key)
	for i in range(boats.size()):
		var boat = boats[i]
		if not (boat is Dictionary) or bool(boat.get("sunk", false)):
			continue
		var key := _boat_key(boat, i)
		var velocity := Vector2(float(boat.get("vx", 0.0)), float(boat.get("vy", 0.0)))
		if not velocity.is_finite() or velocity.length_squared() < 0.25:
			continue
		var stern: Vector2 = BoatArt.stern_of(boat)
		var center := Vector2(float(boat.get("x", 0.0)), float(boat.get("y", 0.0)))
		if not stern.is_finite() or not center.is_finite():
			continue
		var spec_v = boat.get("spec", {})
		var bsize := maxf(4.0, float(spec_v.get("size", 16))) if spec_v is Dictionary else 16.0
		var samples: Array = _wakes.get(key, [])
		var travel: float = INF if samples.is_empty() else Vector2(samples[-1].p).distance_to(stern)
		var elapsed: float = INF if samples.is_empty() else clock - float(samples[-1].t)
		var center_travel: float = INF if samples.is_empty() else Vector2(samples[-1].get("c", center)).distance_to(center)
		if center_travel < 0.05:
			continue # Bow rotation or a stale nonzero velocity alone cannot churn.
		if samples.is_empty() or travel > maxf(1.0, bsize * 0.10) or (elapsed >= 0.10 and travel >= 0.10):
			var direction: Vector2 = velocity.normalized() if samples.is_empty() else (stern - Vector2(samples[-1].p)).normalized()
			if travel > WakeArt.MAX_LENGTH and not samples.is_empty():
				samples.clear() # Do not connect a relocation to the old path.
			if not samples.is_empty() and travel < 0.05:
				continue
			samples.append({"p": stern, "c": center, "d": direction, "t": clock, "w": minf(WakeArt.MAX_WIDTH, bsize * 0.42)})
			while samples.size() > mini(WAKE_MAX_PER_BOAT, WakeArt.MAX_SAMPLES):
				samples.pop_front()
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
	const WakeArt = preload("res://scripts/wake_art045.gd")
	if _wakes.is_empty():
		return
	var proj := _projector()
	var view := get_viewport_rect()
	for key in _wakes.keys():
		var raw: Array = _wakes[key]
		if raw.size() < 2:
			continue
		var bounds := Rect2(project(Vector2(raw[0].p)), Vector2.ZERO)
		for s in raw:
			bounds = bounds.expand(project(Vector2(s.p)))
		if not view.intersects(bounds.grow(WakeArt.MAX_WIDTH * scale_factor * 2.0)):
			continue
		var samples: Array = []
		for s in raw:
			samples.append({"p": s.p, "d": s.d, "age": clock - float(s.t), "w": s.w})
		var primitives: int=BoatArt.draw_wake(self, proj, samples, {"life": minf(WAKE_LIFE_SEC, WakeArt.LIFE_SEC), "clip_rect": view})
		if _profile_drawing:
			_profile_frame.wake_paths+=1;_profile_frame.wake_samples+=samples.size()
			_profile_frame.wake_primitives+=primitives

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
			var primitives: int=BoatArt.draw_trail(self, proj, pts, kind, {"px": maxf(4.0, 14.0 * scale_factor)})
			if _profile_drawing:_profile_frame.trail_primitives+=primitives

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
	var intent: Dictionary=host.Battle.tactical_status(battle,str(boat.id))
	var path: Array=intent.get("path",[])
	if not path.is_empty():
		var previous: Vector2=Vector2(boat.x,boat.y)
		for next in path:
			if next is Vector2:draw_line(project(previous),project(next),Color(GOLD,0.68),1.5,true);previous=next
		for next in intent.get("exit",[]):
			if next is Vector2:draw_dashed_line(project(previous),project(next),Color(FRIEND,0.35),1.2,5.0,true);previous=next
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
	# Destination marks are orders, never an invented straight navigable path.
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
	var started: int=Time.get_ticks_usec()
	var viewport = get_viewport_rect().size
	_profile_drawing=_profile_enabled
	if _profile_drawing:
		_profile_frame={"mode":str(host.mode),"viewport_width":int(viewport.x),"viewport_height":int(viewport.y),
			"scale_factor":scale_factor,"tactical":tactical,"presentation_us":0,
			"boats_total":0,"boats_live":0,"boats_visible":0,"boat_centers_on_screen":0,"boats_culled":0,"boats_invalid":0,
			"authored_hulls":0,"boat_sprites":0,"boat_primitives":0,"boats_us":0,
			"lod0":0,"lod1":0,"lod2":0,"sort_us":0,
			"wake_updates":_profile_wake_updates,"wake_update_us":_profile_wake_update_us,
			"trail_update_us":_profile_trail_update_us,"wake_draw_us":0,"trail_draw_us":0,
			"wake_paths":0,"wake_samples":0,"wake_primitives":0,"trail_primitives":0,
			"projectiles_total":0,"projectile_primitives":0,"projectiles_us":0,
			"effects_total":0,"effects_submitted":0,"effect_primitives":0,"effects_us":0,
			"wrecks_total":0,"wrecks_submitted":0,"wreck_primitives":0,"wrecks_us":0}
		_profile_wake_update_us=0;_profile_trail_update_us=0;_profile_wake_updates=0
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
	presentation_us=Time.get_ticks_usec()-started
	if _profile_drawing:
		_profile_draws+=1
		_profile_frame.draw=_profile_draws
		_profile_frame.presentation_us=presentation_us
		_profile_frame.counted_primitives=(int(_profile_frame.boat_primitives)+int(_profile_frame.wake_primitives)
			+int(_profile_frame.trail_primitives)+int(_profile_frame.projectile_primitives)
			+int(_profile_frame.effect_primitives)+int(_profile_frame.wreck_primitives))
	_profile_drawing=false

func _segments_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab := b - a
	var cd := d - c
	var denom := ab.x * cd.y - ab.y * cd.x
	if absf(denom) < 0.000001:
		return false
	var ac := c - a
	var t := (ac.x * cd.y - ac.y * cd.x) / denom
	var u := (ac.x * ab.y - ac.y * ab.x) / denom
	return t > 0.001 and t < 0.999 and u > 0.001 and u < 0.999

func _simple_ring(pts: PackedVector2Array) -> bool:
	var n := pts.size()
	if n < 3:
		return false
	for i in n:
		for j in range(i + 1, n):
			if abs(i - j) <= 1 or (i == 0 and j == n - 1):
				continue
			if _segments_cross(pts[i], pts[(i + 1) % n], pts[j], pts[(j + 1) % n]):
				return false
	return true

func _scaled_ring(center: Vector2, pts: PackedVector2Array, factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(center + (p - center) * factor)
	return out

func _outset_ring(center: Vector2, pts: PackedVector2Array, distance: float) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	for i in n:
		var prev: Vector2 = pts[(i + n - 1) % n]
		var curr: Vector2 = pts[i]
		var next: Vector2 = pts[(i + 1) % n]
		var bisector := (prev - curr).normalized() + (next - curr).normalized()
		if bisector.length_squared() < 0.0001:
			bisector = curr - center
		bisector = bisector.normalized()
		if bisector.dot(curr - center) < 0.0:
			bisector = -bisector
		out.append(curr + bisector * distance)
	return out

func _chart_marks(island_id: String, pts: PackedVector2Array, center: Vector2) -> Array:
	var marks: Array = []
	var span := 180.0
	for p in pts:
		span = maxf(span, center.distance_to(p) * 0.55)
	var seed := float(island_id.length() * 17)
	for k in 96:
		if marks.size()>=36:break
		var at := center + Vector2(noise(seed + k * 3.1) - 0.5, noise(seed + k * 5.7) - 0.5) * span * 2.0
		if not Geometry2D.is_point_in_polygon(at, pts):
			continue
		var dir := Vector2.from_angle(noise(seed + k * 9.0) * TAU)
		var length := 22.0 + noise(seed + k) * 18.0
		if island_id in ["isl_kelp", "isl_fen", "isl_verdigris"]:
			dir = Vector2(0.25, -1.0).normalized()
			length = 16.0 + float(k % 3) * 6.0
		var kind: String="reeds" if island_id in ["isl_kelp","isl_fen","isl_verdigris"] else "ridge" if island_id in ["isl_cinder","isl_shatter","isl_oilstone"] else "trees"
		marks.append([at,at+dir*length,kind])
	return marks

func _ensure_chart_sheet() -> void:
	if host == null or _chart_ready:
		return
	_chart_sheet.clear()
	for island in host.data.ISLANDS:
		var pts := polygon(island.points)
		var center := polygon_center(island.points)
		var shoal := _outset_ring(center, pts, 130.0)
		if not _simple_ring(shoal):
			shoal = PackedVector2Array()
		var contours: Array = []
		for factor in [0.72, 0.46]:
			var ring := _scaled_ring(center, pts, factor)
			if not _simple_ring(ring):
				continue
			var inside_land := true
			for vertex in ring:
				if not Geometry2D.is_point_in_polygon(vertex, pts):
					inside_land = false
					break
			if inside_land:
				contours.append(ring)
		var tint := Color(str(island.get("color", "#6d7d62")))
		_chart_sheet.append({
			"ground": Color("82956b").lerp(tint, 0.20),
			"high": Color("506b4c").lerp(tint, 0.18),
			"shoal": shoal,
			"contours": contours,
			"marks": _chart_marks(str(island.get("id", "")), pts, center),
		})
	for port in host.data.PORTS:_chart_towns[str(port.id)]=NauticalArt.settlement_plan(port,host.data.ISLANDS)
	_chart_ready = true

func _draw_cached_ring(pts: PackedVector2Array, color: Color) -> void:
	if pts.size() < 3:
		return
	var screen := PackedVector2Array()
	for p in pts:
		screen.append(project(p))
	draw_colored_polygon(screen, color)

func draw_island(island: Dictionary, index: int, tactical: bool = false):
	var points = polygon(island.points)
	var center = polygon_center(island.points)
	var bounds=Rect2(project(points[0]),Vector2.ZERO)
	for p in points: bounds=bounds.expand(project(p))
	if not get_viewport_rect().grow(160).intersects(bounds.grow(100)):return
	if nautical_chart():
		_ensure_chart_sheet()
		var sheet: Dictionary = _chart_sheet[index] if index < _chart_sheet.size() else {}
		var close: bool = not campaign_overview()
		NauticalArt.draw(self,_projector(),points,sheet,close)
		if close and not str(island.get("name", "")).is_empty():
			text_at(str(island.get("name", "")).to_upper(), project(center), 12, Color(0.86, 0.88, 0.74, 0.7), serif, true)
		return
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
	if host.mode=="campaign":world_line(array+[array[0]],Color("cfbf92"),1.5)
	if host.mode != "menu" and not str(island.get("name","")).is_empty():
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
	var position = Vector2(p.x, p.y)
	var screen=project(position)
	if not get_viewport_rect().grow(240).has_point(screen):return
	var color = Color(host.core.faction(p.faction).get("color", "#8fb8a3"))
	var selected: bool = host.selected_port == p.id
	if nautical_chart():
		if not campaign_overview():
			_ensure_chart_sheet()
			NauticalArt.draw_settlement(self,_projector(),_chart_towns.get(str(p.id),{}))
		draw_chart_marker(self,chart_marker_geometry("harbor",screen,scale_factor),GOLD if selected else color,selected)
		return
	if campaign_overview():
		draw_chart_marker(self,chart_marker_geometry("harbor",screen,scale_factor),GOLD if selected else color,selected)
		return
	var v = villages[index]
	var tangent = (v.inland - position).normalized().orthogonal()
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
	draw_chart_marker(self,chart_marker_geometry("harbor",screen,scale_factor),GOLD if selected else color,selected)
	var flag = project(position + Vector2(10, 0), 56)
	draw_line(project(position + Vector2(10, 0), 8), flag, Color("c5c9a7"), 1.3)
	draw_colored_polygon(PackedVector2Array([flag, flag + Vector2(16, 5), flag + Vector2(0, 10)]), color)

func campaign_overview() -> bool:
	return scale_factor<0.32

static func chart_marker_geometry(kind: String,center: Vector2,chart_scale: float,heading: float=0.0) -> Dictionary:
	# Screen dimensions deliberately do not inherit world/hull size. These centers
	# remain exactly project(world position), as used by Main.click_chart.
	# Heading 0 points east, matching the top-down campaign chart.
	var base: float=9.0 if kind=="fleet" else 8.0 if kind=="harbor" else 7.0
	var radius: float=base+clampf((chart_scale-0.15)*3.0,0.0,3.0)
	var points:=PackedVector2Array()
	if kind=="fleet":
		var forward:=Vector2.from_angle(heading)
		var side:=forward.orthogonal()
		for p in [Vector2(1,0),Vector2(-0.7,0.75),Vector2(-0.35,0),Vector2(-0.7,-0.75)]:points.append(center+(forward*p.x+side*p.y)*radius)
	elif kind=="site":
		for p in [Vector2(0,-1),Vector2(1,0),Vector2(0,1),Vector2(-1,0)]:points.append(center+p*radius)
	return {"kind":kind,"center":center,"radius":radius,"points":points}

static func draw_chart_marker(canvas,geometry: Dictionary,color: Color,selected: bool=false) -> void:
	var at: Vector2=geometry.center
	var radius: float=geometry.radius
	canvas.draw_circle(at,radius+2.0,Color("102d3b"))
	if str(geometry.kind)=="harbor":
		canvas.draw_arc(at,radius,0,TAU,24,color,2.0,true)
		canvas.draw_rect(Rect2(at-Vector2(2.5,2.5),Vector2(5,5)),color)
	else:
		canvas.draw_colored_polygon(geometry.points,color)
		if str(geometry.kind)=="site":canvas.draw_circle(at,2.0,Color("102d3b"))
	if selected:canvas.draw_arc(at,radius+4.0,0,TAU,28,GOLD,1.5,true)

static func draw_chart_coast(canvas,points: PackedVector2Array) -> void:
	if points.size()<3:return
	canvas.draw_colored_polygon(points,Color("69836a"))
	var outline: PackedVector2Array=points.duplicate()
	outline.append(points[0])
	canvas.draw_polyline(outline,Color("dac48b"),2.0,true)

static func chart_label_bounds(viewport: Vector2) -> Rect2:
	return Rect2(345,110,maxf(0,viewport.x-700),maxf(0,viewport.y-260))

static func chart_label_layout(entries: Array,bounds: Rect2,font: Font) -> Array:
	var ordered: Array=entries.duplicate()
	ordered.sort_custom(func(a,b):return int(a.priority)>int(b.priority) if int(a.priority)!=int(b.priority) else str(a.text)<str(b.text))
	var occupied: Array=[]
	for entry in entries:occupied.append(Rect2(entry.at-Vector2(17,17),Vector2(34,34)))
	var placed: Array=[]
	for entry in ordered:
		var at: Vector2=entry.at
		if str(entry.text).is_empty() or not bounds.grow(24).has_point(at):continue
		var font_size: int=16 if int(entry.priority)>=80 else 14
		var subtitle: String=str(entry.get("subtitle",""))
		var width: float=font.get_string_size(str(entry.text),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		if not subtitle.is_empty():width=maxf(width,font.get_string_size(subtitle,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x)
		var size:=Vector2(ceilf(width)+16,font_size+10+(14 if not subtitle.is_empty() else 0))
		if size.x>bounds.size.x or size.y>bounds.size.y:continue
		var offsets: Array=[Vector2(22,-size.y*0.5),Vector2(-22-size.x,-size.y*0.5),Vector2(-size.x*0.5,-22-size.y),Vector2(-size.x*0.5,22),Vector2(22,22),Vector2(-22-size.x,22),Vector2(22,-22-size.y),Vector2(-22-size.x,-22-size.y)]
		if int(entry.priority)>=60:
			for offset in offsets.duplicate():offsets.append(offset*1.5)
		for offset in offsets:
			var rect:=Rect2(at+offset,size)
			if int(entry.priority)>=60:rect.position=rect.position.clamp(bounds.position,bounds.end-size)
			if not bounds.encloses(rect):continue
			var collision: bool=false
			for other in occupied:
				if rect.grow(3).intersects(other):collision=true;break
			if collision:continue
			var label: Dictionary=entry.duplicate()
			label.rect=rect;label.font_size=font_size
			placed.append(label);occupied.append(rect)
			break
	return placed

static func draw_chart_label(canvas,label: Dictionary,font: Font) -> void:
	var rect: Rect2=label.rect
	var color: Color=label.get("color",Color("d7e1cc"))
	canvas.draw_line(label.at,Vector2(label.at).clamp(rect.position,rect.end),Color(color,0.45),1.0,true)
	canvas.draw_rect(rect,Color(0.035,0.12,0.16,0.92))
	canvas.draw_string(font,rect.position+Vector2(8,int(label.font_size)+2),str(label.text),HORIZONTAL_ALIGNMENT_LEFT,-1,int(label.font_size),color)
	if not str(label.get("subtitle","")).is_empty():canvas.draw_string(font,rect.position+Vector2(8,int(label.font_size)+16),str(label.subtitle),HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("9db8a5"))

func _draw_chart_labels(entries: Array):
	_map_labels=chart_label_layout(entries,chart_label_bounds(get_viewport_rect().size),sans)
	for label in _map_labels:draw_chart_label(self,label,sans)

func trade_paths() -> Array:
	var revision: int=int(host.data.get("MAP_REVISION",1))
	if is_same(_trade_data,host.data) and _trade_revision==revision:return _trade_paths
	_trade_data=host.data;_trade_revision=revision;_trade_paths=[]
	for route in host.data.ROUTES:
		var a: Dictionary=host.core.port(route[0])
		var b: Dictionary=host.core.port(route[1])
		var path: Array=host.core.cached_path(a,b,10.0)
		if path.is_empty():continue
		var line: Array=[]
		for p in path:line.append(Vector2(p.x,p.y))
		_trade_paths.append(line)
	return _trade_paths

func draw_campaign():
	if host.core == null or host.core.state.is_empty():
		return
	var world = host.core.state
	var overview: bool=campaign_overview()
	var labels: Array=[]
	var target_id: String=str(world.activeContract.get("targetPort",""))
	var w=int(host.data.WORLD.width);var h=int(host.data.WORLD.height)
	for x in range(0,w+1,1000):
		world_line([Vector2(x,0),Vector2(x,h)],Color(0.6,0.8,0.69,0.027))
	for y in range(0,h+1,1000):
		world_line([Vector2(0,y),Vector2(w,y)],Color(0.6,0.8,0.69,0.027))
	if not overview:
		for x in range(500,w,1000):
			world_line([Vector2(x,0),Vector2(x,h)],Color(0.6,0.8,0.69,0.018))
		for y in range(500,h,1000):
			world_line([Vector2(0,y),Vector2(w,y)],Color(0.6,0.8,0.69,0.018))
	for path in trade_paths():
		for i in range(1,path.size()):
			draw_dashed_line(project(path[i-1]),project(path[i]),Color(0.64,0.80,0.65,0.12),1.0,3.0,true)
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
		if not get_viewport_rect().grow(30).has_point(s):continue
		var color = ENEMY if patrol.hostile else FRIEND
		draw_chart_marker(self,chart_marker_geometry("fleet",s,scale_factor),color)
		labels.append({"at":s,"text":str(patrol.get("name","Fleet")) if not overview else "","priority":10,"color":color})
	for i in range(world.ports.size()):
		var p: Dictionary=world.ports[i]
		draw_harbor(p, i)
		labels.append({"at":project(Vector2(p.x,p.y)),"text":str(p.name),"priority":110 if p.id==host.selected_port else 100 if p.id==target_id else 80 if p.id==world.lastPort else 60,"subtitle":"CONTRACT DESTINATION" if p.id==target_id else str(p.industry).to_upper() if not overview else "","color":GOLD if p.id==host.selected_port or p.id==target_id else Color("d7e1cc")})
	var knowledge: Dictionary=world.get("exploration",{})
	for site in knowledge.get("catalog",[]):
		var level: int=int(knowledge.get("sites",{}).get(site.id,{}).get("level",0))
		if level<=0:continue
		var at: Vector2=project(Vector2(site.x,site.y))
		if not get_viewport_rect().grow(30).has_point(at):continue
		var selected: bool=str(host.selected_site)==str(site.id)
		var color: Color=GOLD if level<3 else FRIEND
		draw_chart_marker(self,chart_marker_geometry("site",at,scale_factor),color,selected)
		labels.append({"at":at,"text":"Unsurveyed site" if level==1 else str(site.name),"priority":120 if selected else 20,"color":color})
	for wreck in world.get("wrecks",[]):
		if wreck.get("status","")!="unclaimed":continue
		var marker_pos: Vector2=project(Vector2(wreck.x,wreck.y))
		if not get_viewport_rect().grow(30).has_point(marker_pos):continue
		draw_circle(marker_pos,7,Color(GOLD,0.12))
		draw_line(marker_pos+Vector2(-4,-4),marker_pos+Vector2(4,4),GOLD,1.5)
		draw_line(marker_pos+Vector2(-4,4),marker_pos+Vector2(4,-4),GOLD,1.5)
		labels.append({"at":marker_pos,"text":"","priority":0})
	var marker: Vector2=project(Vector2(world.position.x,world.position.y))
	draw_chart_marker(self,chart_marker_geometry("fleet",marker,scale_factor,float(world.heading)),GOLD,true)
	labels.append({"at":marker,"text":"YOUR FLOTILLA","priority":105,"color":GOLD})
	_draw_chart_labels(labels)
	var size = get_viewport_rect().size
	text_at("THE SHATTER COAST", Vector2(size.x * 0.5, size.y - 175), 12, GOLD, mono, true)
	text_at("Nothing stays afloat alone.", Vector2(size.x * 0.5, size.y - 144), 26, Color("c7d4bd"), serif, true)
	text_at("WASD CAMERA  ·  M TERRITORY  ·  HOME FLEET  ·  CLICK HARBOR TO SAIL  ·  SCROLL ZOOM", Vector2(size.x * 0.5, size.y - 118), 10, Color("93b4a8"), mono, true)
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
		if _profile_drawing:_profile_frame.boats_invalid+=1
		return
	var boat_size := maxf(4.0, float(spec_v.get("size", 16))) * enlargement
	var p := Vector2(float(boat.get("x", 0.0)), float(boat.get("y", 0.0)))
	var screen := project(p)
	var margin: float = 120.0 + boat_size * scale_factor * 3.2
	if not get_viewport_rect().grow(margin).has_point(screen):
		if _profile_drawing:_profile_frame.boats_culled+=1
		return
	if selected:
		world_ring(p, boat_size * 2.6, Color(GOLD, 0.65), 1.0)
	var screen_len: float = boat_size * 3.9 * scale_factor * 0.82
	var lod := 0 if screen_len > 78.0 else (1 if screen_len > 36.0 else 2)
	if tactical:
		lod = maxi(lod, 1)
	var draw_stats: Dictionary=BoatArt.draw_boat(self, _projector(), boat, {
		"accent": color, "enemy": enemy, "lod": lod, "clock": clock,
		"cache":true,
		"combat":host.mode=="battle","battle_clock":float(host.battle.get("time",0))+float(host.battle.get("visualTailTime",0)) if host.mode=="battle" else 0.0,
		"px": maxf(2.0, boat_size * scale_factor * 0.82), "enlargement": enlargement})
	if _profile_drawing:
		_profile_frame.boats_visible+=1
		if get_viewport_rect().has_point(screen):_profile_frame.boat_centers_on_screen+=1
		_profile_frame.boat_primitives+=int(draw_stats.get("primitives",0))
		_profile_frame.boat_sprites+=int(draw_stats.get("sprites",0))
		_profile_frame.authored_hulls+=int(bool(draw_stats.get("authored_hull",false)))
		if lod==0:_profile_frame.lod0+=1
		elif lod==1:_profile_frame.lod1+=1
		else:_profile_frame.lod2+=1
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
	var home: Dictionary=host.data.PORTS[0]
	var at := project(Vector2(float(home.x), float(home.y)))
	draw_chart_marker(self, chart_marker_geometry("harbor", at, scale_factor), GOLD, true)
	draw_chart_marker(self, chart_marker_geometry("fleet", at + Vector2(28, 16), scale_factor, 0.4), GOLD, false)
	var size = get_viewport_rect().size
	draw_texture_rect(title_shade, Rect2(Vector2.ZERO, size), false)
	draw_compass(Vector2(size.x - 85, size.y - 95))
	text_at("14° 27′ N  /  108° 12′ E", Vector2(size.x - 290, size.y - 35), 11, Color(0.7, 0.83, 0.72, 0.5), mono)

func draw_battle():
	var battle = host.battle
	if battle.is_empty():
		return
	if _profile_drawing:
		_profile_frame.boats_total=battle.ships.size()
		_profile_frame.projectiles_total=battle.projectiles.size()
		_profile_frame.effects_total=battle.effects.size()
		_profile_frame.wrecks_total=battle.wrecks.size()
	for i in range(battle.islands.size()):
		draw_island(battle.islands[i], i, true)
	var goal: Dictionary=host.Battle.objective_snapshot(battle).get("exit",{})
	if goal.has("x") and goal.has("y"):
		var exit_point: Vector2=Vector2(float(goal.x),float(goal.y))
		var radius: float=float(goal.get("radius",70))
		world_ring(exit_point,radius,Color(GOLD,0.85),2.0)
		var at: Vector2=project(exit_point)
		text_at("CONVOY EXIT",at+Vector2(0,-30),14,GOLD,mono,true)
		var view: Vector2=get_viewport_rect().size
		var edge: Vector2=Vector2(clampf(at.x,355,view.x-355),clampf(at.y,125,view.y-180))
		if edge.distance_to(at)>35:
			var direction: Vector2=(at-edge).normalized()
			draw_line(edge,edge+direction*22,GOLD,2,true)
			text_at("CONVOY EXIT",edge+Vector2(0,-15),12,GOLD,mono,true)
	var flagship = host.Battle.get_flagship(battle)
	if not flagship.is_empty():
		world_ring(Vector2(flagship.x, flagship.y), flagship.spec.range, Color(0.75, 0.84, 0.63, 0.07), 1.0)
	var phase_started: int=Time.get_ticks_usec() if _profile_drawing else 0
	var active_wrecks: int=0
	for wreck in battle.wrecks:
		if bool(wreck.get("sinking",false)):active_wrecks+=1
	for wreck in battle.wrecks:
		var margin: float=maxf(100,float(wreck.size)*scale_factor*3.2)
		if get_viewport_rect().grow(margin).has_point(project(Vector2(wreck.x,wreck.y))):
			var primitives: int=0
			if active_wrecks>=8:
				var coarse: Dictionary=wreck.duplicate();coarse.lod=2;primitives=CombatArt.wreck(self,coarse)
			else:primitives=CombatArt.wreck(self,wreck)
			if _profile_drawing:
				_profile_frame.wrecks_submitted+=1;_profile_frame.wreck_primitives+=primitives
	if _profile_drawing:_profile_frame.wrecks_us=Time.get_ticks_usec()-phase_started
	phase_started=Time.get_ticks_usec() if _profile_drawing else 0
	_draw_wakes()
	if _profile_drawing:_profile_frame.wake_draw_us=Time.get_ticks_usec()-phase_started
	phase_started=Time.get_ticks_usec() if _profile_drawing else 0
	_draw_trails()
	if _profile_drawing:_profile_frame.trail_draw_us=Time.get_ticks_usec()-phase_started
	for fort in battle.get("coastalDefenses",[]):
		var at: Vector2=project(Vector2(fort.x,fort.y))
		var color: Color=ENEMY if fort.team=="enemy" else FRIEND
		draw_colored_polygon(PackedVector2Array([at+Vector2(-25,0),at+Vector2(0,-13),at+Vector2(25,0),at+Vector2(0,13)]),Color("627271"))
		draw_line(at+Vector2(-20,1),at+Vector2(0,10),GOLD,2,true)
		draw_circle(at+Vector2(0,-5),7,Color("354d54"))
		draw_line(at+Vector2(0,-7),at+Vector2(25 if fort.team=="player" else -25,-7),Color("a7b8b4"),5,true)
		text_at(str(fort.port.name)+" watch",at+Vector2(0,30),11,color,mono,true)
	for job in battle.get("boarding",{}).get("jobs",[]):
		if job.status!="active":continue
		var source: Dictionary={};var target: Dictionary={}
		for b in battle.ships:
			if str(b.id)==str(job.source):source=b
			if str(b.id)==str(job.target):target=b
		if not source.is_empty() and not target.is_empty():
			draw_line(project(Vector2(source.x,source.y)),project(Vector2(target.x,target.y)),FRIEND,2,true)
			text_at("BOARDING · %d"%int(job.alive),project(Vector2(target.x,target.y))+Vector2(0,-50),12,GOLD,mono,true)
	var selected_ids := _selected_battle_ids(battle)
	phase_started=Time.get_ticks_usec() if _profile_drawing else 0
	var sorted_ships = battle.ships.duplicate()
	sorted_ships.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)
	if _profile_drawing:_profile_frame.sort_us=Time.get_ticks_usec()-phase_started
	phase_started=Time.get_ticks_usec() if _profile_drawing else 0
	for boat in sorted_ships:
		if not boat.sunk:
			if _profile_drawing:_profile_frame.boats_live+=1
			var is_sel: bool = boat.id in selected_ids or bool(boat.get("selected", false))
			draw_boat(boat, ENEMY if boat.team == "enemy" else GOLD if boat.id == battle.playerId else FRIEND, is_sel, boat.team == "enemy")
			if boat.get("captureSecured",false):text_at("SECURED PRIZE",project(Vector2(boat.x,boat.y))+Vector2(0,-38),11,GOLD,mono,true)
			if is_sel and boat.team == "player":
				_draw_order_indicator(battle, boat)
	if _profile_drawing:_profile_frame.boats_us=Time.get_ticks_usec()-phase_started
	phase_started=Time.get_ticks_usec() if _profile_drawing else 0
	for shot in battle.projectiles:
		var primitives: int=BoatArt.draw_projectile(self, _projector(), shot, {})
		if _profile_drawing:_profile_frame.projectile_primitives+=primitives
		pass # projectile body drawn by BoatArt above
		pass
		pass
		pass
		pass
	if _profile_drawing:_profile_frame.projectiles_us=Time.get_ticks_usec()-phase_started
	phase_started=Time.get_ticks_usec() if _profile_drawing else 0
	for effect in battle.effects:
		var margin: float=maxf(100,float(effect.get("radius",20))*scale_factor*3.0)
		if get_viewport_rect().grow(margin).has_point(project(Vector2(effect.x,effect.y),float(effect.get("height",0)))):
			var primitives: int=CombatArt.effect(self,effect)
			if _profile_drawing:
				_profile_frame.effects_submitted+=1;_profile_frame.effect_primitives+=primitives
	if _profile_drawing:_profile_frame.effects_us=Time.get_ticks_usec()-phase_started
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
