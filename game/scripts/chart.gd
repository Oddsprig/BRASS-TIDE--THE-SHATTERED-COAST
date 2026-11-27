extends Node2D

const Locality064=preload("res://scripts/expedition.gd")
const OceanChart064=preload("res://scripts/ocean_chart064.gd")
const BoatArt = preload("res://scripts/boat_art.gd")
const CombatArt = preload("res://scripts/combat_art.gd")
const NauticalArt=preload("res://scripts/nautical_art.gd")
const CoastArt050=preload("res://scripts/coast_art050.gd")
const FleetArt054=preload("res://scripts/campaign_fleet_art054.gd")
const LandmarkArt054=preload("res://scripts/campaign_landmark_art054.gd")
const Refits054=preload("res://scripts/refit.gd")
const GOLD = Color("dfbd7d")
const FOAM = Color("95cabc")
const ENEMY = Color("e8947a")
const FRIEND = Color("8fc6b4")
var host
var _ocean_painter064=OceanChart064.new()
var _world_key064: String=""
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
var battle_overlays: Dictionary = {"arcs":false,"threat":false,"routes":false}
const OVERLAY_BOATS: int = 4
const OVERLAY_MOUNTS: int = 12
const OVERLAY_THREATS: int = 4
const OVERLAY_THREAT_MOUNTS: int = 8
const OVERLAY_ARC_STEPS: int = 16
const OVERLAY_PATH_SEGMENTS: int = 24
var _campaign_follow: bool = false
var _last_mode: String = ""
var _map_labels: Array=[]
var _title_starter054: Dictionary={}
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
var _coast_battle_source=null
var _battle_coast: Array=[]
var _battle_render051: Dictionary={}
var _battle_view120: Rect2=Rect2()
var _follow_fit120: float=1.0
var _overview_camera120: Vector2=Vector2.ZERO
var _overview_follow120: bool=true
var _overview_zoom120: float=1.0
var _overview_fit120: float=1.0
var _hover_probe120: float=-1.0
var _hover_mouse120: Vector2=Vector2.INF
var _hover_id120: String=""

func reset_battle_presentation051() -> void:
	clear_battle_poses051()
	_wakes.clear();_trails.clear();_last_trail_stamp=-1.0
	_follow_fit120=1.0
	_hover_probe120=-1.0;_hover_id120="";_hover_mouse120=Vector2.INF

func clear_battle_poses051() -> void:
	_battle_render051={}

func _prepare_battle_presentation051() -> void:
	_battle_render051={}
	if host==null or host.mode!="battle" or host.battle.is_empty():return
	if not "battle_driver051" in host or host.battle_driver051==null:return
	var poses: Dictionary=host.battle_driver051.presentation_poses()
	var previous: Dictionary=poses.get("previous",{})
	var current: Dictionary=poses.get("current",{})
	var fraction: float=clampf(host.battle_driver051.presentation_fraction(),0.0,1.0)
	var ships: Array=[]
	for ship: Dictionary in host.battle.ships:
		var id: String=str(ship.id)
		var now: Dictionary=current.get(id,ship)
		var before: Dictionary=previous.get(id,now)
		# Only these disposable Main draw records receive interpolated poses.
		# All conditions, stores, mount state and HP retain the latest publication.
		var visual: Dictionary=ship.duplicate()
		visual.x=lerpf(float(before.x),float(now.x),fraction)
		visual.y=lerpf(float(before.y),float(now.y),fraction)
		visual.angle=lerp_angle(float(before.angle),float(now.angle),fraction)
		visual.turretAngle=lerp_angle(float(before.get("turretAngle",before.angle)),float(now.get("turretAngle",now.angle)),fraction)
		ships.append(visual)
	_battle_render051=host.battle.duplicate()
	_battle_render051.ships=ships

func battle_boats051() -> Array:
	if not _battle_render051.is_empty():return _battle_render051.ships
	return host.battle.get("ships",[]) if host!=null else []

func battle_boat_position051(boat: Dictionary) -> Vector2:
	for visual: Dictionary in battle_boats051():
		if str(visual.id)==str(boat.id):return Vector2(visual.x,visual.y)
	return Vector2(boat.x,boat.y)

func pick_battle_boat120(screen: Vector2, team: String="") -> Dictionary:
	# Root's two Main callers consume only this observed boat's ID/team. Use
	# the same interpolated pose and real baked occupied bounds as the draw.
	if host==null or host.mode!="battle" or not battle_view_rect120().has_point(screen):return {}
	var picked120: Dictionary={}
	var depth120: float=-INF
	for boat120: Dictionary in battle_boats051():
		if boat120.sunk or boat120.get("captureSecured",false) or (not team.is_empty() and str(boat120.team)!=team):continue
		var point120: Vector2=Vector2(boat120.x,boat120.y)
		var center120: Vector2=project(point120)
		var occupied120: Rect2=BoatArt.SpriteArt.bounds(boat120.spec,float(boat120.angle))
		var hit120: bool=false
		if occupied120.has_area():
			var screen_bounds120: Rect2=Rect2(center120+occupied120.position*scale_factor,occupied120.size*scale_factor)
			hit120=screen_bounds120.grow(4.0).has_point(screen)
		else:
			# Existing procedural fallback: its actual station outline at deck
			# height, with the original two hulls for a catamaran. No mock boat.
			var stations120: Array=BoatArt._stations(boat120.spec)
			var offsets120: Array=[-BoatArt.CAT_OFFSET,BoatArt.CAT_OFFSET] if str(boat120.spec.get("role",""))=="raider" else [0.0]
			for offset120: float in offsets120:
				var outline120: PackedVector2Array=PackedVector2Array()
				for local120: Vector2 in BoatArt._outline(stations120,offset120):
					outline120.append(project(point120+local120.rotated(float(boat120.angle))*maxf(4.0,float(boat120.spec.get("size",16))),6.5))
				if outline120.size()>=3 and Geometry2D.is_point_in_polygon(screen,outline120):hit120=true
		# Tiny overview symbols remain selectable without a 42px empty-water
		# catchment. When bounds overlap, the frontmost drawn boat wins.
		hit120=hit120 or center120.distance_squared_to(screen)<=16.0*16.0
		var boat_depth120: float=float(boat120.x)+float(boat120.y)
		if hit120 and boat_depth120>=depth120:
			picked120=boat120;depth120=boat_depth120
	return picked120

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
	_ensure_chart_sheet()
	_prepare_battle_coast()

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

func set_battle_view120(rectangle: Rect2) -> void:
	var next120: Rect2=rectangle.intersection(get_viewport_rect())
	if next120==_battle_view120:return
	_battle_view120=next120
	if host!=null and host.mode=="battle" and not host.battle.is_empty() and follow_camera:
		_frame_battle120(host.battle,0.0,true)

func battle_view_rect120() -> Rect2:
	if _battle_view120.has_area():return _battle_view120
	var viewport120: Vector2=get_viewport_rect().size
	return Rect2(12,124,maxf(1.0,viewport120.x-24),maxf(1.0,viewport120.y-304))

func _projection_origin120() -> Vector2:
	return get_viewport_rect().size*0.5 if nautical_chart() else battle_view_rect120().get_center()

func _frame_battle120(battle: Dictionary, dt: float, instant: bool=false) -> void:
	# Presentation only: no ship/order, worker or campaign state is written here.
	if not is_inside_tree():return
	var usable120: Rect2=battle_view_rect120().grow(-32.0)
	var viewport120: Vector2=get_viewport_rect().size
	var requested120: float=clampf(viewport120.x/1700.0,0.65,1.2)*zoom
	var bounds120: Rect2
	if tactical:
		# Tab must show the whole arena, independently of the close combat zoom.
		bounds120=Rect2(_chart_plane(Vector2.ZERO),Vector2.ZERO)
		for corner120: Vector2 in [Vector2(2300,0),Vector2(2300,1700),Vector2(0,1700)]:
			bounds120=bounds120.expand(_chart_plane(corner120))
		bounds120=bounds120.grow(100.0)
	else:
		var focal120: Dictionary=host.Battle.get_flagship(battle)
		if bool(battle.get("autopilot",true)):
			var selected120: Array=_selected_battle_ids(battle)
			var found120: bool=false
			for selected_id120: Variant in selected120:
				for boat120: Dictionary in battle.ships:
					if str(boat120.id)==str(selected_id120) and boat120.team=="player" and not boat120.sunk and not boat120.get("captureSecured",false):
						focal120=boat120;found120=true
						break
				if found120:break
		if focal120.is_empty():return
		var point120: Vector2=Vector2(focal120.x,focal120.y)
		var target120: Dictionary={}
		var target_id120: String=str(focal120.get("orderTarget",{}).get("shipId",""))
		var distance120: float=INF
		for other120: Dictionary in battle.ships:
			if other120.sunk or other120.get("captureSecured",false) or other120.team==focal120.team:continue
			var delta120: float=point120.distance_squared_to(Vector2(other120.x,other120.y))
			if str(other120.id)==target_id120:
				target120=other120
				distance120=-1.0
			elif distance120>=0.0 and delta120<distance120:
				distance120=delta120
				target120=other120
		var midpoint120: Vector2=point120
		if not target120.is_empty() and point120.distance_to(Vector2(target120.x,target120.y))<=1350.0:
			midpoint120=(point120+Vector2(target120.x,target120.y))*0.5
		else:target120={}
		var started120: bool=false
		for member120: Dictionary in battle.ships:
			if member120.sunk or member120.get("captureSecured",false):continue
			var member_point120: Vector2=Vector2(member120.x,member120.y)
			if str(member120.id)!=str(focal120.id) and str(member120.id)!=str(target120.get("id","")) and member_point120.distance_squared_to(midpoint120)>620.0*620.0:continue
			# Include hull/deck/health-bar extent rather than fitting bare centers.
			var size120: float=maxf(10.0,float(member120.spec.get("size",16)))
			var half120: Vector2=Vector2(size120*3.0+35.0,size120*1.8+45.0)
			var envelope120: Rect2=Rect2(_chart_plane(member_point120)-half120,half120*2.0)
			bounds120=bounds120.merge(envelope120) if started120 else envelope120
			started120=true
	var fit120: float=maxf(0.05,minf(maxf(1.0,usable120.size.x)/maxf(1.0,bounds120.size.x),maxf(1.0,usable120.size.y)/maxf(1.0,bounds120.size.y)))
	var scale120: float=fit120*zoom/maxf(0.01,_overview_zoom120) if tactical else minf(requested120,fit120)
	var weight120: float=1.0 if instant else 1.0-exp(-maxf(0.0,dt)*4.0)
	# Zoom out immediately when needed; ease closer only after space opens up.
	scale_factor=scale120 if instant or scale120<scale_factor else lerpf(scale_factor,scale120,weight120)
	_follow_fit120=scale_factor/maxf(0.01,requested120)
	var camera_plane120: Vector2=_chart_plane(camera.lerp(_plane_to_world(bounds120.get_center()),weight120))
	var half_view120: Vector2=usable120.size/(2.0*maxf(0.01,scale_factor))
	# Ease inside the allowed interval, but never ease a followed hull under HUD.
	var minimum120: Vector2=bounds120.end-half_view120
	var maximum120: Vector2=bounds120.position+half_view120
	camera=_plane_to_world(Vector2(clampf(camera_plane120.x,minimum120.x,maxf(minimum120.x,maximum120.x)),clampf(camera_plane120.y,minimum120.y,maxf(minimum120.y,maximum120.y))))

func project(p: Vector2, height: float = 0.0) -> Vector2:
	var d = p - camera
	var origin := _projection_origin120()
	if nautical_chart():
		return origin + d * scale_factor
	return origin + Vector2((d.x - d.y) * ISO_X, (d.x + d.y) * ISO_Y - height) * scale_factor

func world_at(screen: Vector2) -> Vector2:
	var d = (screen - _projection_origin120()) / maxf(0.0001, scale_factor)
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
	_prepare_battle_presentation051()
	var viewport = get_viewport_rect().size
	if host != null and "tactical_mode" in host:
		tactical = bool(host.tactical_mode)
	var mode_now: String = str(host.mode) if host != null else ""
	var identity064: Dictionary=host.core.state.get("world064",{}) if host!=null and host.core!=null else {}
	var key064: String=str(identity064.get("layer","home"))+"/"+str(identity064.get("regionId","shatter_coast"))
	var mode_changed: bool=mode_now != _last_mode or key064!=_world_key064
	_world_key064=key064
	_last_mode = mode_now
	if mode_now=="battle":_prepare_battle_coast()
	if host != null and host.mode == "battle" and not host.battle.is_empty():
		if mode_changed:
			_wakes.clear()
			_trails.clear()
		if follow_camera:
			_frame_battle120(_battle_render051 if not _battle_render051.is_empty() else host.battle,dt,mode_changed)
		else:
			scale_factor=clampf(viewport.x/1700.0,0.65,1.2)*zoom*_follow_fit120
		var wake_started: int=Time.get_ticks_usec() if _profile_enabled else 0
		_update_wakes(battle_boats051())
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
	var bounds: Rect2=Rect2(0,0,2300,1700) if (host != null and host.mode == "battle") else active_bounds064()
	camera.x = clampf(camera.x, bounds.position.x-450.0, bounds.end.x+450.0)
	camera.y = clampf(camera.y, bounds.position.y-450.0, bounds.end.y+450.0)
	queue_redraw()

func center_camera():
	follow_camera = true
	if host == null:
		return
	if host.mode == "battle" and not host.battle.is_empty():
		_frame_battle120(_battle_render051 if not _battle_render051.is_empty() else host.battle,0.0,true)
	elif host.mode != "menu" and host.core != null and not host.core.state.is_empty():
		zoom=1.0
		_campaign_follow = true
		var wp = host.core.state.position
		camera = Vector2(wp.x, wp.y)
	queue_redraw()

func active_bounds064() -> Rect2:
	if host!=null and host.mode=="campaign" and host.core!=null and not host.core.state.is_empty() and not Locality064.home_local064(host.core.state):
		return _ocean_painter064.world_bounds(host.core.world_view064())
	return Rect2(0,0,float(host.data.WORLD.width),float(host.data.WORLD.height))

func _ocean_view066() -> Dictionary:
	if host!=null and host.core!=null and host.core is Object and host.core.has_method("ocean_view066"):
		var v=host.core.ocean_view066()
		if v is Dictionary:return v
	return {}

func _exploration_view067() -> Dictionary:
	if host!=null and host.core!=null and host.core is Object and host.core.has_method("exploration_view067"):
		var v=host.core.exploration_view067()
		if v is Dictionary:return v
	return {}

func _shipping_view068() -> Dictionary:
	if host!=null and host.core!=null and host.core is Object and host.core.has_method("shipping_view068"):
		var v=host.core.shipping_view068()
		if v is Dictionary:return v
	return {}

func _sector_view069() -> Dictionary:
	if host!=null and host.core!=null and host.core is Object and host.core.has_method("sector_view069"):
		var v=host.core.sector_view069()
		if v is Dictionary:return v
	return {}

func pick_port068(screen: Vector2) -> Dictionary:
	if host==null or host.core==null:return {}
	return _ocean_painter064.pick_port068(self,host.core.world_view064(),_shipping_view068(),screen)

func pick_local067(screen: Vector2) -> Dictionary:
	if host==null or host.core==null:return {}
	return _ocean_painter064.pick_local067(self,host.core.world_view064(),_exploration_view067(),screen)

func pick_contact066(screen: Vector2) -> Dictionary:
	if host==null or host.core==null:return {}
	return _ocean_painter064.pick_contact(self,host.core.world_view064(),_ocean_view066(),screen,_shipping_view068())

func pick_ocean064(screen: Vector2) -> Dictionary:
	var view064: Dictionary=host.core.world_view064()
	var view068: Dictionary=_shipping_view068()
	var hit066: Dictionary=_ocean_painter064.pick_contact(self,view064,_ocean_view066(),screen,view068)
	if not hit066.is_empty():return hit066
	var hit068: Dictionary=_ocean_painter064.pick_port068(self,view064,view068,screen)
	if not hit068.is_empty():return hit068
	var hit067: Dictionary=_ocean_painter064.pick_local067(self,view064,_exploration_view067(),screen)
	if not hit067.is_empty():return hit067
	return _ocean_painter064.pick_region(view064,world_at(screen))

func regional_scale() -> float:
	var viewport=get_viewport_rect().size
	if host!=null and host.mode=="campaign" and not Locality064.home_local064(host.core.state):
		var bounds064: Rect2=active_bounds064()
		return maxf(0.10,minf((viewport.x-560.0)/maxf(1.0,minf(3000.0,bounds064.size.x)),(viewport.y-260.0)/maxf(1.0,minf(2000.0,bounds064.size.y))))
	return maxf(0.15,minf((viewport.x-560.0)/2100.0,(viewport.y-260.0)/1150.0))

func territory_view():
	follow_camera=false;_campaign_follow=false
	var viewport=get_viewport_rect().size
	if not Locality064.home_local064(host.core.state):
		var bounds064: Rect2=active_bounds064()
		var usable064: Rect2=chart_label_bounds(viewport).grow(-40)
		var fit064: float=minf(usable064.size.x/maxf(1,bounds064.size.x),usable064.size.y/maxf(1,bounds064.size.y))
		zoom=clampf(fit064/regional_scale(),0.10,1.0)
		camera=bounds064.get_center()-(usable064.get_center()-viewport*0.5)/maxf(0.01,regional_scale()*zoom)
		queue_redraw();return
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
	if enabled and not tactical:
		_overview_camera120=camera;_overview_follow120=follow_camera
		_overview_zoom120=zoom;_overview_fit120=_follow_fit120
		follow_camera=true
	elif not enabled and tactical:
		camera=_overview_camera120;follow_camera=_overview_follow120
		zoom=_overview_zoom120;_follow_fit120=_overview_fit120
	tactical = enabled
	if host != null and "tactical_mode" in host:
		host.tactical_mode = enabled
	if enabled and host!=null and not host.battle.is_empty():_frame_battle120(host.battle,0.0,true)
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
			# Gentle motion leaves a thin wash; fast travel opens the same bounded
			# strip behind the drive. No heading extension or stationary emission.
			var speed_mix: float = smoothstep(0.5, 60.0, velocity.length())
			var width: float = minf(WakeArt.MAX_WIDTH, bsize * lerpf(0.20, 0.48, speed_mix))
			# Preserve the live transom, but do not spend all twelve samples on
			# twelve render frames. A tip keeps its original interval start while
			# moving; older anchors then cover the actual foam lifetime at any FPS.
			var tip_started: float = float(samples[-1].get("started", samples[-1].t)) if not samples.is_empty() else clock
			var replace_tip: bool = samples.size() > 1 and clock - tip_started < WakeArt.SAMPLE_INTERVAL
			var sample: Dictionary = {"p": stern, "c": center, "d": direction, "t": clock, "w": width, "started": tip_started if replace_tip else clock}
			if replace_tip:samples[-1] = sample
			else:samples.append(sample)
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
	# Every caller consumes this inside its current draw. Camera, viewport and
	# mode stay fixed there; querying the viewport again for every gun/foam
	# vertex adds work without changing the projection.
	var view_origin: Vector2 = _projection_origin120()
	var view_camera: Vector2 = camera
	var view_scale: float = scale_factor
	if nautical_chart():
		return func(p: Vector2, _h: float) -> Vector2: return view_origin + (p - view_camera) * view_scale
	return func(p: Vector2, h: float) -> Vector2:
		var d: Vector2 = p - view_camera
		return view_origin + Vector2((d.x - d.y) * ISO_X, (d.x + d.y) * ISO_Y - h) * view_scale

func _draw_wakes():
	const WakeArt = preload("res://scripts/wake_art045.gd")
	if _wakes.is_empty():
		return
	var proj := _projector()
	var view := get_viewport_rect()
	var wake_batch := WakeArt._FrameBatch051.new(self)
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
		var primitives: int=BoatArt.draw_wake(self, proj, samples, {"life": minf(WAKE_LIFE_SEC, WakeArt.LIFE_SEC), "clip_rect": view, "affine_water": true, "_frame_batch051": wake_batch})
		if _profile_drawing:
			_profile_frame.wake_paths+=1;_profile_frame.wake_samples+=samples.size()
			_profile_frame.wake_primitives+=primitives
	wake_batch._flush() # Same draw position, before trails/hulls; no frame retention.

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
	if host != null and "selected_battle_ids" in host and host.selected_battle_ids is Array:
		return host.selected_battle_ids
	var out: Array = []
	for s in battle.get("ships", []):
		if s is Dictionary and bool(s.get("selected", false)):
			out.append(s.get("id"))
	if out.is_empty() and battle.get("playerId") != null:
		out.append(battle.playerId)
	return out

func _draw_order_indicator(battle: Dictionary, boat: Dictionary, show_route: bool = false):
	if show_route:
		var intent: Dictionary=host.Battle.tactical_status(battle,str(boat.id))
		var previous: Vector2=Vector2(boat.x,boat.y)
		var segments: int=0
		for key in ["path","exit"]:
			for next in intent.get(key,[]):
				if segments>=OVERLAY_PATH_SEGMENTS:break
				segments+=1
				if next is Vector2:
					if key=="path":draw_line(project(previous),project(next),Color(GOLD,0.68),1.5,true)
					else:draw_dashed_line(project(previous),project(next),Color(FRIEND,0.35),1.2,5.0,true)
					previous=next
		# A current observed target link, never a promise of a future projectile hit.
		if not intent.get("path",[]).is_empty():
			var target_id: String=str(battle.get("tactical",{}).get("intents",{}).get(str(boat.id),{}).get("targetId",""))
			for other in battle.ships:
				if str(other.id)==target_id and not other.sunk:
					draw_dashed_line(project(Vector2(boat.x,boat.y)),project(Vector2(other.x,other.y)),Color(ENEMY,0.4),1.0,7.0,true)
					break
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
	# A reached Hold is already shown by selection and the order/status panel.
	# Its destination cross otherwise lies over the gun and deck on light hulls.
	if order == "hold" and Vector2(boat.x, boat.y).distance_to(target) < 14.0:
		return
	var color = ENEMY if order == "attack" else FRIEND if order == "escort" else GOLD
	# Destination marks are orders, never an invented straight navigable path.
	var point = project(target)
	draw_line(point-Vector2(6,6), point+Vector2(6,6), Color(color,0.9),1.4,true)
	draw_line(point+Vector2(6,-6), point+Vector2(-6,6), Color(color,0.9),1.4,true)
	world_ring(target,14.0,Color(color,0.5),1.0)

func _draw_mount_ranges(battle: Dictionary, boat: Dictionary, color: Color, budget: int) -> int:
	if budget <= 0:return 0
	var mounts: Array = host.Battle._combat_mounts(battle, boat)
	var used: int = 0
	for mount: Dictionary in mounts:
		if used >= budget:break
		if float(mount.get("damage", 0.0)) <= 0.0:continue
		var origin: Vector2 = Vector2(boat.x, boat.y) + Vector2(mount.x, mount.y).rotated(float(boat.angle))
		var bearing: float = float(boat.angle) + float(mount.angle)
		var arc: float = clampf(float(mount.arc), 0.01, TAU)
		var reach: float = float(mount.range)
		var points: Array = []
		for i: int in range(OVERLAY_ARC_STEPS + 1):
			points.append(origin + Vector2.from_angle(bearing - arc * 0.5 + arc * float(i) / float(OVERLAY_ARC_STEPS)) * reach)
		world_line(points, color, 1.2)
		if arc < TAU - 0.01:
			world_line([origin, points[0]], Color(color, color.a * 0.5))
			world_line([origin, points[-1]], Color(color, color.a * 0.5))
		used += 1
	return used

func _draw_battle_ranges(battle: Dictionary, selected_ids: Array):
	if not battle_overlays.arcs and not battle_overlays.threat:return
	var selected: Array = []
	for boat in battle.ships:
		if boat.id in selected_ids and boat.team == "player" and not boat.sunk and not boat.get("captureSecured",false):
			selected.append(boat)
			if selected.size() >= OVERLAY_BOATS:break
	var used: int = 0
	if battle_overlays.arcs:
		for boat: Dictionary in selected:
			used += _draw_mount_ranges(battle, boat, Color(FRIEND, 0.35), OVERLAY_MOUNTS - used)
	if not battle_overlays.threat or selected.is_empty():return
	var nearest: Array = []
	for enemy in battle.ships:
		if enemy.team != "enemy" or enemy.sunk or enemy.get("captureSecured",false):continue
		var distance: float = INF
		for boat: Dictionary in selected:distance = minf(distance, Vector2(enemy.x-boat.x,enemy.y-boat.y).length_squared())
		var index: int = 0
		while index < nearest.size() and float(nearest[index].distance) <= distance:index += 1
		if index < OVERLAY_THREATS:
			nearest.insert(index, {"boat":enemy,"distance":distance})
			if nearest.size() > OVERLAY_THREATS:nearest.pop_back()
	used = 0
	for entry: Dictionary in nearest:
		used += _draw_mount_ranges(battle, entry.boat, Color(ENEMY, 0.23), OVERLAY_THREAT_MOUNTS - used)

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
	BoatArt.MeshCache.begin_draw121(self)
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
			"boat_prepare_us":0,"boat_hull_us":0,"boat_motor_us":0,"boat_weapons_us":0,"boat_damage_us":0,
			"lod0":0,"lod1":0,"lod2":0,"sort_us":0,
			"wake_updates":_profile_wake_updates,"wake_update_us":_profile_wake_update_us,
			"trail_update_us":_profile_trail_update_us,"wake_draw_us":0,"trail_draw_us":0,
			"wake_paths":0,"wake_samples":0,"wake_primitives":0,"trail_primitives":0,
			"projectiles_total":0,"projectile_primitives":0,"projectiles_us":0,
			"effects_total":0,"effects_submitted":0,"effect_primitives":0,"effects_us":0,
			"wrecks_total":0,"wrecks_submitted":0,"wreck_primitives":0,"wrecks_us":0,
			"coast_draw_calls":0,"coast_us":0}
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
		_chart_sheet.append(CoastArt050.prepare_island(island))
	for port in host.data.PORTS:_chart_towns[str(port.id)]=NauticalArt.settlement_plan(port,host.data.ISLANDS)
	_chart_ready = true

func _prepare_battle_coast() -> void:
	if host==null or str(host.mode)!="battle":return
	var islands: Array=host.battle.get("islands",[])
	# Worker publications detach arrays, including unchanged terrain. Compare
	# their values before rebuilding meshes; identity changes every adoption.
	# Retain the last prepared array so real geometry/metadata changes and an
	# empty-sea transition still invalidate the cache.
	if is_same(_coast_battle_source,islands) or _coast_battle_source==islands:return
	# Encounter islands are immutable terrain authority, including an empty sea.
	# Never key this by campaign index: translated encounter rings differ.
	_battle_coast.clear()
	for island in islands:_battle_coast.append(CoastArt050.prepare_island(island))
	_coast_battle_source=islands

func _draw_cached_ring(pts: PackedVector2Array, color: Color) -> void:
	if pts.size() < 3:
		return
	var screen := PackedVector2Array()
	for p in pts:
		screen.append(project(p))
	draw_colored_polygon(screen, color)

func draw_island(island: Dictionary, index: int, tactical: bool = false):
	var sheets: Array=_chart_sheet if nautical_chart() else _battle_coast
	if index<0 or index>=sheets.size():return
	var sheet: Dictionary=sheets[index]
	var started: int=Time.get_ticks_usec() if _profile_drawing else 0
	var calls: int=NauticalArt.draw(self,_projector(),sheet.land,sheet,not campaign_overview(),scale_factor,get_viewport_rect())
	if _profile_drawing:
		_profile_frame.coast_draw_calls+=calls;_profile_frame.coast_us+=Time.get_ticks_usec()-started
	if not nautical_chart() and calls>0 and not str(island.get("name","")).is_empty():
		text_at(str(island.name).to_upper(),project(sheet.label),11,Color(0.86,0.88,0.74,0.7),serif,true)

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
	if not get_viewport_rect().grow(16).intersects(campaign_harbor_bounds054(p)):return
	var color = Color(host.core.faction(p.faction).get("color", "#8fb8a3"))
	var selected: bool = host.selected_port == p.id
	var started: int=Time.get_ticks_usec() if _profile_drawing else 0
	var calls: int=NauticalArt.draw_settlement(self,_projector(),_chart_towns.get(str(p.id),{}),scale_factor,get_viewport_rect())
	if _profile_drawing:
		_profile_frame.coast_draw_calls+=calls;_profile_frame.coast_us+=Time.get_ticks_usec()-started
	_draw_harbor_selection054(p,GOLD if selected else color,selected)

func campaign_harbor_bounds054(port: Dictionary) -> Rect2:
	# Reserve the actual roofs and physical berth connector, not a square glyph.
	var sheet: Dictionary=_chart_towns.get(str(port.id),{})
	var at: Vector2=project(Vector2(port.x,port.y))
	var bounds:=Rect2(at-Vector2(9,9),Vector2(18,18))
	for roof: PackedVector2Array in sheet.get("roofs",[]):
		for point: Vector2 in roof:bounds=bounds.expand(project(point))
	for point: Vector2 in sheet.get("pier",PackedVector2Array()):bounds=bounds.expand(project(point))
	return bounds.grow(5)

func campaign_harbor_hit054(port: Dictionary,screen: Vector2) -> bool:
	var berth: Vector2=project(Vector2(port.x,port.y))
	if berth.distance_to(screen)<45.0:return true
	if not campaign_harbor_bounds054(port).has_point(screen):return false
	var sheet: Dictionary=_chart_towns.get(str(port.id),{})
	# Clicking a visible waterfront roof works without turning its whole label
	# reservation rectangle into an invisible obstacle to ordinary route clicks.
	for roof: PackedVector2Array in sheet.get("roofs",[]):
		var points:=PackedVector2Array()
		for point: Vector2 in roof:points.append(project(point))
		if Geometry2D.is_point_in_polygon(screen,points):return true
	var pier: PackedVector2Array=sheet.get("pier",PackedVector2Array())
	for i in range(1,pier.size()):
		if Geometry2D.get_closest_point_to_segment(screen,project(pier[i-1]),project(pier[i])).distance_to(screen)<7.0:return true
	return false

func _draw_harbor_selection054(port: Dictionary,color: Color,selected: bool) -> void:
	var sheet: Dictionary=_chart_towns.get(str(port.id),{})
	var berth: Vector2=project(Vector2(port.x,port.y))
	var anchor: Vector2=project(sheet.get("anchor",Vector2(port.x,port.y)))
	if selected:
		# Thin open anchorage arcs leave water, the boat and real dock visible.
		draw_arc(berth,13.0,0.15,1.1,10,Color(color,0.65),1.0,true)
		draw_arc(berth,13.0,3.3,4.25,10,Color(color,0.65),1.0,true)
		draw_line(anchor,berth,Color(color,0.55),1.0,true)
	else:
		var tangent: Vector2=Vector2(sheet.get("tangent",Vector2.RIGHT))
		draw_line(anchor-tangent*5.0,anchor+tangent*5.0,Color(color,0.55),1.2,true)

func campaign_player_art054() -> Dictionary:
	if host==null or host.core==null or host.core.state.is_empty():return FleetArt054.layout([],Vector2.ZERO,0.0,scale_factor)
	var world: Dictionary=host.core.state
	return FleetArt054.layout(host.core.active_fleet(),project(Vector2(world.position.x,world.position.y)),float(world.heading),scale_factor,{"viewport":get_viewport_rect(),"overview":zoom<0.7})

func _campaign_patrol_heading054(patrol: Dictionary) -> float:
	# place_patrol uses this same measured segment; no new route calculation.
	var left: float=maxf(0.0,float(patrol.get("progress",0))*float(patrol.get("courseLength",0)))
	var course: Array=patrol.get("course",[])
	for i in range(1,course.size()):
		var delta:=Vector2(float(course[i].x)-float(course[i-1].x),float(course[i].y)-float(course[i-1].y))
		var length: float=delta.length()
		if (left<=length or i==course.size()-1) and length>0.0001:return delta.angle()
		left-=length
	var destination: Dictionary=host.core.port(str(patrol.get("to","")))
	if not destination.is_empty():return Vector2(float(destination.x)-float(patrol.x),float(destination.y)-float(patrol.y)).angle()
	return float(patrol.get("heading",0.0))

func campaign_patrol_art054(patrol: Dictionary) -> Dictionary:
	var boats: Array=[]
	if bool(patrol.get("active",false)) and not bool(patrol.get("hidden",false)):
		var owner: Dictionary=host.core.fleet_owner(str(patrol.get("id","")))
		if bool(owner.get("active",false)):
			for boat: Dictionary in owner.get("boats",[]):
				if bool(boat.get("sunk",false)) or bool(boat.get("mothballed",false)) or bool(boat.get("hidden",false)) or not str(boat.get("storedPort","")).is_empty():continue
				boats.append(boat)
	return FleetArt054.layout(boats,project(Vector2(patrol.x,patrol.y)),_campaign_patrol_heading054(patrol),scale_factor,{"viewport":get_viewport_rect(),"overview":zoom<0.7})

func campaign_site_art054(site: Dictionary,level: int) -> Dictionary:
	return LandmarkArt054.plan(site,level,project(Vector2(site.x,site.y)),scale_factor)

func campaign_wreck_art054(wreck: Dictionary) -> Dictionary:
	return LandmarkArt054.wreck_plan(wreck,project(Vector2(wreck.x,wreck.y)),scale_factor)

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

static func chart_label_bounds(viewport: Vector2,right_panel_visible: bool=true) -> Rect2:
	var right_margin: float=355.0 if right_panel_visible else 25.0
	return Rect2(345,110,maxf(0,viewport.x-345-right_margin),maxf(0,viewport.y-260))

static func chart_label_layout(entries: Array,bounds: Rect2,font: Font,exclusions: Array=[]) -> Array:
	var ordered: Array=entries.duplicate()
	ordered.sort_custom(func(a,b):return int(a.priority)>int(b.priority) if int(a.priority)!=int(b.priority) else str(a.text)<str(b.text))
	var occupied: Array=exclusions.duplicate()
	for entry in entries:
		var art: Rect2=entry.get("art_bounds",Rect2(entry.at-Vector2(17,17),Vector2(34,34)))
		if art.has_area():occupied.append(art.grow(4))
	var placed: Array=[]
	for entry in ordered:
		var at: Vector2=entry.at
		if str(entry.text).is_empty() or not bounds.grow(24).has_point(at):continue
		var font_size: int=15 if int(entry.priority)>=80 else 14
		var subtitle: String=str(entry.get("subtitle",""))
		var width: float=font.get_string_size(str(entry.text),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		if not subtitle.is_empty():width=maxf(width,font.get_string_size(subtitle,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x)
		var size:=Vector2(ceilf(width)+12,font_size+8+(14 if not subtitle.is_empty() else 0))
		if size.x>bounds.size.x or size.y>bounds.size.y:continue
		var offsets: Array=[Vector2(22,-size.y*0.5),Vector2(-22-size.x,-size.y*0.5),Vector2(-size.x*0.5,-22-size.y),Vector2(-size.x*0.5,22),Vector2(22,22),Vector2(-22-size.x,22),Vector2(22,-22-size.y),Vector2(-22-size.x,-22-size.y)]
		var art: Rect2=entry.get("art_bounds",Rect2(at-Vector2(17,17),Vector2(34,34)))
		if art.has_area():
			offsets=[Vector2(art.end.x-at.x+10,-size.y*0.5),Vector2(art.position.x-at.x-size.x-10,-size.y*0.5),Vector2(-size.x*0.5,art.position.y-at.y-size.y-10),Vector2(-size.x*0.5,art.end.y-at.y+10)]+offsets
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
	var edge: Vector2=Vector2(label.at).clamp(rect.position,rect.end)
	var art: Rect2=label.get("art_bounds",Rect2())
	var start: Vector2=edge.clamp(art.position,art.end) if art.has_area() else Vector2(label.at)
	if start.distance_to(edge)>12.0:canvas.draw_line(start,edge,Color(color,0.25),0.8,true)
	var baseline:=rect.position+Vector2(6,int(label.font_size)+1)
	# A small glyph halo retains contrast over coast and water without painting
	# a black slab across the miniature artwork or the physical shore behind it.
	_chart_label_text054(canvas,font,baseline,str(label.text),int(label.font_size),color)
	if not str(label.get("subtitle","")).is_empty():_chart_label_text054(canvas,font,baseline+Vector2(0,14),str(label.subtitle),11,Color("a7bca8"))

static func _chart_label_text054(canvas,font: Font,at: Vector2,text: String,font_size: int,color: Color) -> void:
	if canvas.has_method("draw_string_outline"):
		canvas.draw_string_outline(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,3,Color(0.04,0.12,0.14,0.85))
	else:
		# Existing source recorder has draw_string only; production uses outline.
		canvas.draw_string(font,at+Vector2(0,1),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color(0.04,0.12,0.14,0.85))
	canvas.draw_string(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _draw_chart_labels(entries: Array):
	var right_panel_visible: bool=true
	if host is Object:
		var hud=host.get("ui")
		if is_instance_valid(hud):
			var body=hud.get("right_body")
			if is_instance_valid(body) and body.get_parent() is CanvasItem:
				right_panel_visible=body.get_parent().visible
	var size: Vector2=get_viewport_rect().size
	var exclusions: Array=[Rect2(size-Vector2(112,193),Vector2(84,100))]
	_map_labels=chart_label_layout(entries,chart_label_bounds(size,right_panel_visible),sans,exclusions)
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
	if host!=null and host.core!=null and not host.core.state.is_empty() and not Locality064.home_local064(host.core.state):
		var view064: Dictionary=host.core.world_view064()
		if view064.is_empty():
			text_at("Chart unavailable",get_viewport_rect().size*0.5,22,GOLD,serif,true)
			return
		_ocean_painter064.draw(self,view064,_ocean_view066(),_exploration_view067(),_shipping_view068(),_sector_view069())
		return
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
		if i<_chart_sheet.size():
			labels.append({"at":project(_chart_sheet[i].label),"text":str(host.data.ISLANDS[i].name),"priority":25,"color":Color("b5c5a0")})
	if not world.path.is_empty():
		var previous = Vector2(world.position.x, world.position.y)
		for step_point in world.path:
			var point = Vector2(step_point.x, step_point.y)
			draw_dashed_line(project(previous), project(point), Color(GOLD, 0.75), 1.5, 5.0, true)
			previous = point
	for patrol in world.patrols:
		if not patrol.active or bool(patrol.get("hidden",false)):
			continue
		var s = project(Vector2(patrol.x, patrol.y))
		if not get_viewport_rect().grow(512).has_point(s):continue
		var art: Dictionary=campaign_patrol_art054(patrol)
		if art.vessels.is_empty():continue
		var color = ENEMY if patrol.hostile else FRIEND
		FleetArt054.draw(self,art,color)
		labels.append({"at":s,"art_bounds":art.bounds,"text":str(patrol.get("name","Fleet")) if not overview else "","priority":10,"color":color})
	for i in range(world.ports.size()):
		var p: Dictionary=world.ports[i]
		if str(p.get("regionId","shatter_coast"))!="shatter_coast":continue
		draw_harbor(p, i)
		labels.append({"at":project(Vector2(p.x,p.y)),"art_bounds":campaign_harbor_bounds054(p),"text":str(p.name),"priority":110 if p.id==host.selected_port else 100 if p.id==target_id else 80 if p.id==world.lastPort else 60,"subtitle":"CONTRACT DESTINATION" if p.id==target_id else CoastArt050.harbor_caption(p) if p.id==host.selected_port or p.id==world.lastPort else "","color":GOLD if p.id==host.selected_port or p.id==target_id else Color("d7e1cc")})
	var knowledge: Dictionary=world.get("exploration",{})
	for site in knowledge.get("catalog",[]):
		if str(site.get("regionId","shatter_coast"))!="shatter_coast":continue
		var level: int=int(knowledge.get("sites",{}).get(site.id,{}).get("level",0))
		if level<=0:continue
		var at: Vector2=project(Vector2(site.x,site.y))
		if not get_viewport_rect().grow(50).has_point(at):continue
		var selected: bool=str(host.selected_site)==str(site.id)
		var color: Color=GOLD if level<3 else FRIEND
		var art: Dictionary=campaign_site_art054(site,level)
		if not get_viewport_rect().intersects(art.bounds):continue
		LandmarkArt054.draw(self,art,selected)
		var show_site_label: bool=selected or (level>=2 and not overview)
		labels.append({"at":at,"art_bounds":Rect2(art.bounds).grow(5 if selected else 0),"text":art.label if show_site_label else "","priority":120 if selected else 20,"color":color})
	for wreck in world.get("wrecks",[]):
		if not Locality064.home_local064(wreck) or wreck.get("status","")!="unclaimed":continue
		var marker_pos: Vector2=project(Vector2(wreck.x,wreck.y))
		if not get_viewport_rect().grow(50).has_point(marker_pos):continue
		var art: Dictionary=campaign_wreck_art054(wreck)
		if not get_viewport_rect().intersects(art.bounds):continue
		LandmarkArt054.draw(self,art)
		labels.append({"at":marker_pos,"art_bounds":art.bounds,"text":"","priority":0})
	var marker: Vector2=project(Vector2(world.position.x,world.position.y))
	var player_art: Dictionary=campaign_player_art054()
	FleetArt054.draw(self,player_art,GOLD,true)
	if not player_art.vessels.is_empty():
		labels.append({"at":marker,"art_bounds":Rect2(player_art.bounds).grow(5),"text":"YOUR FLOTILLA","priority":105,"color":GOLD})
	var gates064: Array=[] if host.core is Dictionary else host.core.world_view064().get("approaches",[])
	for gate064 in gates064:
		var gate_point064: Vector2=Vector2(gate064.position.x,gate064.position.y)
		world_ring(gate_point064,float(gate064.radius),Color(GOLD,0.7),1.5)
		labels.append({"at":project(gate_point064),"text":str(gate064.name),"priority":90,"color":GOLD})
	_draw_chart_labels(labels)
	var size = get_viewport_rect().size
	draw_compass(Vector2(size.x - 70, size.y - 133))

func boat_shape(p: Vector2, angle: float, shape: Array, size_value: float, height: float, color: Color):
	var points: Array = []
	for v in shape:
		points.append(p + Vector2(v[0], v[1]).rotated(angle) * size_value)
	world_poly(points, color, height)

func draw_boat(boat: Dictionary, color: Color, selected: bool = false, enemy: bool = false, enlargement: float = 1.0, no_bars: bool = false):
	_draw_boat051(boat, color, selected, enemy, enlargement, no_bars, null)

func _draw_boat051(boat: Dictionary, color: Color, selected: bool, enemy: bool, enlargement: float, no_bars: bool, battle_draw051: BoatArt._BattleDraw051):
	# v0.002: rich BoatArt geometry with offscreen culling + zoom LOD.
	# Persistent wakes are recorded in step() and drawn by _draw_wakes().
	var spec_v = boat.get("spec", {})
	if not (spec_v is Dictionary):
		if _profile_drawing:_profile_frame.boats_invalid+=1
		return
	var boat_size := maxf(4.0, float(spec_v.get("size", 16))) * enlargement
	var p := Vector2(float(boat.get("x", 0.0)), float(boat.get("y", 0.0)))
	var view: Rect2 = battle_draw051.view if battle_draw051 != null else get_viewport_rect()
	var projector: Callable = battle_draw051.projector if battle_draw051 != null else _projector()
	var screen: Vector2 = projector.call(p, 0.0)
	var margin: float = 120.0 + boat_size * scale_factor * 3.2
	if not view.grow(margin).has_point(screen):
		if _profile_drawing:_profile_frame.boats_culled+=1
		return
	if selected:
		world_ring(p, boat_size * 2.6, Color(GOLD, 0.65), 1.0)
	var screen_len: float = boat_size * 3.9 * scale_factor * 0.82
	var lod := 0 if screen_len > 78.0 else (1 if screen_len > 36.0 else 2)
	if tactical:
		lod = maxi(lod, 1)
	var opts: Dictionary = {
		"accent": color, "enemy": enemy, "lod": lod, "clock": clock,
		"cache":true,
		"combat":host.mode=="battle","battle_clock":float(host.battle.get("time",0))+float(host.battle.get("visualTailTime",0)) if host.mode=="battle" else 0.0,
		"px": maxf(2.0, boat_size * scale_factor * 0.82), "enlargement": enlargement}
	var draw_stats: Dictionary = BoatArt._draw_battle_boat051(self, battle_draw051, boat, opts) if battle_draw051 != null else BoatArt.draw_boat(self, projector, boat, opts)
	if _profile_drawing:
		_profile_frame.boats_visible+=1
		if view.has_point(screen):_profile_frame.boat_centers_on_screen+=1
		_profile_frame.boat_primitives+=int(draw_stats.get("primitives",0))
		_profile_frame.boat_sprites+=int(draw_stats.get("sprites",0))
		_profile_frame.authored_hulls+=int(bool(draw_stats.get("authored_hull",false)))
		if lod==0:_profile_frame.lod0+=1
		elif lod==1:_profile_frame.lod1+=1
		else:_profile_frame.lod2+=1
	if not no_bars and boat.has("hp") and boat.has("maxHp"):
		var center: Vector2 = projector.call(p, -35.0)
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
	for port in host.data.PORTS:
		NauticalArt.draw_settlement(self,_projector(),_chart_towns.get(str(port.id),{}),scale_factor,get_viewport_rect())
	var boats: Array=[]
	var point:=Vector2(float(home.x),float(home.y))
	var heading: float=0.4
	if host.core!=null and not host.core.state.is_empty():
		boats=host.core.active_fleet()
		heading=float(host.core.state.heading)
		# Menu composition stages the real source roster at the home waterfront;
		# a career far from home must not leave the title's boat art offscreen.
	else:
		# The actual configured single starter hull and its canonical default fit.
		# No campaign is created and no extra owned boats are invented for a title.
		if str(_title_starter054.get("type",""))!=str(host.data.START.hull):
			for spec: Dictionary in host.data.HULLS:
				if str(spec.id)==str(host.data.START.hull):
					var fitted: Dictionary=Refits054.effective_spec(spec,Refits054.defaults(spec))
					_title_starter054={"uid":"title-starter","type":spec.id,"spec":fitted}
					break
		if not _title_starter054.is_empty():boats.append(_title_starter054)
	var art: Dictionary=FleetArt054.layout(boats,project(point),heading,scale_factor,{"viewport":get_viewport_rect(),"size_multiplier":1.3})
	FleetArt054.draw(self,art,GOLD)
	var size = get_viewport_rect().size
	draw_texture_rect(title_shade, Rect2(Vector2.ZERO, size), false)
	draw_compass(Vector2(size.x - 85, size.y - 95))
	text_at("14° 27′ N  /  108° 12′ E", Vector2(size.x - 290, size.y - 35), 11, Color(0.7, 0.83, 0.72, 0.5), mono)

func draw_battle():
	var battle: Dictionary=_battle_render051 if not _battle_render051.is_empty() else host.battle
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
		var safe_exit120: Rect2=battle_view_rect120().grow(-28.0)
		var edge: Vector2=Vector2(clampf(at.x,safe_exit120.position.x,safe_exit120.end.x),clampf(at.y,safe_exit120.position.y,safe_exit120.end.y))
		if edge.distance_to(at)>35:
			var direction: Vector2=(at-edge).normalized()
			draw_line(edge,edge+direction*22,GOLD,2,true)
			text_at("CONVOY EXIT",edge+Vector2(0,-15),12,GOLD,mono,true)
	var flagship = host.Battle.get_flagship(battle)
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
	_draw_battle_ranges(battle, selected_ids)
	var route_boats: int = 0
	phase_started=Time.get_ticks_usec() if _profile_drawing else 0
	var sorted_ships = battle.ships.duplicate()
	sorted_ships.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)
	if _profile_drawing:_profile_frame.sort_us=Time.get_ticks_usec()-phase_started
	phase_started=Time.get_ticks_usec() if _profile_drawing else 0
	# BoatArt's cached projector uses a full-window origin. Offset its camera by
	# the inverse screen delta so hulls, hit tests, effects and orders agree.
	var render_camera120: Vector2=camera+_screen_to_world_delta(get_viewport_rect().size*0.5-_projection_origin120())
	var battle_draw051: BoatArt._BattleDraw051 = null if nautical_chart() else BoatArt._BattleDraw051.new(get_viewport_rect(), render_camera120, scale_factor, true)
	if battle_draw051 != null and _profile_drawing: battle_draw051.profile051 = _profile_frame
	for boat in sorted_ships:
		if not boat.sunk:
			if _profile_drawing:_profile_frame.boats_live+=1
			var is_sel: bool = boat.id in selected_ids
			_draw_boat051(boat, ENEMY if boat.team == "enemy" else GOLD if boat.id == battle.playerId else FRIEND, is_sel, boat.team == "enemy", 1.0, false, battle_draw051)
			if boat.get("captureSecured",false):text_at("SECURED PRIZE",project(Vector2(boat.x,boat.y))+Vector2(0,-38),11,GOLD,mono,true)
			if is_sel and boat.team == "player":
				_draw_order_indicator(battle, boat, bool(battle_overlays.routes) and route_boats < OVERLAY_BOATS)
				route_boats += 1
	if _profile_drawing:_profile_frame.boats_us=Time.get_ticks_usec()-phase_started
	phase_started=Time.get_ticks_usec() if _profile_drawing else 0
	var projectile_projector120: Callable=_projector()
	for shot in battle.projectiles:
		var primitives: int=BoatArt.draw_projectile(self, projectile_projector120, shot, {})
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
			var edge120: Rect2=battle_view_rect120().grow(-28.0)
			var clamped = Vector2(clampf(p.x, edge120.position.x, edge120.end.x), clampf(p.y, edge120.position.y, edge120.end.y))
			if clamped.distance_to(p) > 15:
				var direction = (p - clamped).normalized()
				draw_colored_polygon(PackedVector2Array([clamped + direction * 12, clamped - direction * 7 + direction.orthogonal() * 6, clamped - direction * 7 - direction.orthogonal() * 6]), ENEMY)
				var nearest_label120: Vector2=Vector2(clampf(clamped.x,edge120.position.x+64.0,edge120.end.x-64.0),clamped.y+27.0)
				text_at("NEAREST · %d m" % best, nearest_label120, 11, ENEMY, mono, true)
	_draw_battle_contact120(battle)
	var mouse = get_global_mouse_position()
	if battle_view_rect120().has_point(mouse) and not host.ui.modal_open:
		draw_arc(mouse, 9, 0, TAU, 24, Color(GOLD, 0.75), 1, true)
		draw_line(mouse - Vector2(15, 0), mouse - Vector2(5, 0), Color(GOLD, 0.8), 1, true)
		draw_line(mouse + Vector2(5, 0), mouse + Vector2(15, 0), Color(GOLD, 0.8), 1, true)
	# The minimap occupies reserved HUD space; it never covers boats on the water.
	if host.paused and not host.ui.modal_open:
		var pause_origin120: Vector2=battle_view_rect120().position+Vector2(battle_view_rect120().size.x*0.5,28)
		text_at("TACTICAL OVERVIEW" if tactical else "PAUSED",pause_origin120,24,GOLD,serif,true)
		text_at("RIGHT-CLICK ORDERS · TAB TO RETURN" if tactical else "SET ORDERS · SPACE TO RESUME",pause_origin120+Vector2(0,24),11,Color("c6d2be"),mono,true)

func _draw_battle_contact120(battle: Dictionary) -> void:
	if host.ui.modal_open:return
	var water120: Rect2=battle_view_rect120().grow(-8.0)
	var mouse120: Vector2=get_global_mouse_position()
	var selected120: Dictionary={}
	for selected_id120: Variant in _selected_battle_ids(battle):
		for boat120: Dictionary in battle.ships:
			if str(boat120.id)==str(selected_id120) and boat120.team=="player" and not boat120.sunk and not boat120.get("captureSecured",false):
				selected120=boat120
				break
		if not selected120.is_empty():break
	var target120: Dictionary={}
	var order120: String=str(selected120.get("order",""))
	var target_id120: String=str(selected120.get("orderTarget",{}).get("shipId","")) if order120 in ["attack","escort"] else ""
	for candidate120: Dictionary in battle.ships:
		if str(candidate120.id)==target_id120 and not candidate120.sunk and not candidate120.get("captureSecured",false):
			target120=candidate120
			break
	var queued120: bool=not selected120.is_empty() and str(selected120.id)==str(battle.playerId) and not battle.get("autopilot",true)
	if not target120.is_empty():
		var point120: Vector2=project(Vector2(target120.x,target120.y))
		var marker_box120: Rect2=water120.grow_individual(-76.0,-28.0,-76.0,-28.0)
		var marker120: Vector2=Vector2(clampf(point120.x,marker_box120.position.x,marker_box120.end.x),clampf(point120.y,marker_box120.position.y,marker_box120.end.y))
		var color120: Color=ENEMY if order120=="attack" else FRIEND
		if marker120.distance_to(point120)>16.0:
			var direction120: Vector2=(point120-marker120).normalized()
			draw_colored_polygon(PackedVector2Array([marker120+direction120*12,marker120-direction120*7+direction120.orthogonal()*6,marker120-direction120*7-direction120.orthogonal()*6]),color120)
		else:draw_arc(marker120,20.0,0,TAU,24,color120,2.0,true)
		text_at(("QUEUED " if queued120 else "ORDERED ")+("ATTACK" if order120=="attack" else "ESCORT"),marker120-Vector2(0,25),11,color120,mono,true)
	if water120.has_point(mouse120):
		# Picking reads baked bounds only on movement or at most ten times/sec.
		# The small card's condition/role still comes from each current publication.
		if mouse120.distance_squared_to(_hover_mouse120)>4.0 or clock-_hover_probe120>=0.1 or _hover_probe120<0.0:
			_hover_id120=str(pick_battle_boat120(mouse120).get("id",""))
			_hover_mouse120=mouse120;_hover_probe120=clock
	else:_hover_id120=""
	var contact120: Dictionary={}
	for hovered120: Dictionary in battle.ships:
		if str(hovered120.id)==_hover_id120 and not hovered120.sunk and not hovered120.get("captureSecured",false):
			contact120=hovered120
			break
	var hovering120: bool=not contact120.is_empty()
	if not hovering120:contact120=target120
	if contact120.is_empty():return
	var card_size120: Vector2=Vector2(340,94)
	var card_at120: Vector2=mouse120+Vector2(22,22) if hovering120 else water120.position+Vector2(12,water120.size.y-card_size120.y-12)
	if hovering120 and card_at120.x+card_size120.x>water120.end.x:card_at120.x=mouse120.x-card_size120.x-18
	if hovering120 and card_at120.y+card_size120.y>water120.end.y:card_at120.y=mouse120.y-card_size120.y-18
	card_at120=Vector2(clampf(card_at120.x,water120.position.x,water120.end.x-card_size120.x),clampf(card_at120.y,water120.position.y,water120.end.y-card_size120.y))
	var card120: Rect2=Rect2(card_at120,card_size120)
	var accent120: Color=ENEMY if contact120.team=="enemy" else FRIEND
	draw_rect(card120,Color(0.035,0.10,0.14,0.96))
	draw_rect(card120,Color(accent120,0.8),false,1.0)
	var name120: String=("Enemy: " if contact120.team=="enemy" else "Ally: ")+str(contact120.name)
	text_at(name120.left(34),card_at120+Vector2(12,20),14,accent120,mono)
	var intent120: Dictionary=battle.get("tactical",{}).get("intents",{}).get(str(contact120.id),{})
	var role120: String=str(contact120.spec.get("role","Boat")).capitalize()
	if not str(intent120.get("role","")).is_empty():role120+=" · "+str(intent120.role).capitalize()
	text_at(role120.left(42),card_at120+Vector2(12,40),12,FOAM,mono)
	var condition120: String="Hull %.0f%% · Crew %d · Water %.0f%%"%[100.0*float(contact120.hp)/maxf(1.0,float(contact120.maxHp)),int(contact120.crew),100.0*float(contact120.water)/maxf(1.0,float(contact120.capacity))]
	text_at(condition120,card_at120+Vector2(12,59),12,Color("d3dfd5"),mono)
	var last120: String="Fire %.0f%%"%float(contact120.fire)
	if not target120.is_empty():last120=("Queued target: " if queued120 else "Order target: ")+str(target120.name)
	text_at(last120.left(46),card_at120+Vector2(12,79),11,GOLD if not target120.is_empty() else FOAM,mono)

func battle_minimap_rect() -> Rect2:
	var size = get_viewport_rect().size
	# Keep the chart above the compact selected-status band (height minus192).
	return Rect2(size.x - 240, size.y - 344, 190, 140)

func draw_minimap():
	paint_battle_minimap103(self,battle_minimap_rect())

func paint_battle_minimap103(canvas: CanvasItem,box: Rect2) -> void:
	canvas.draw_rect(box, Color(0.025, 0.10, 0.14, 0.88))
	canvas.draw_rect(box, Color(0.5, 0.70, 0.59, 0.35), false, 1)
	canvas.draw_string(mono,box.position+Vector2(6,13),"OVERVIEW",HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("acc6b4"))
	var plot: Rect2=Rect2(box.position+Vector2(4,20),Vector2(maxf(1,box.size.x-8),maxf(1,box.size.y-24)))
	for island in host.battle.islands:
		var points = PackedVector2Array()
		for p in island.points:
			points.append(plot.position + Vector2(p[0] / 2300.0 * plot.size.x, p[1] / 1700.0 * plot.size.y))
		canvas.draw_colored_polygon(points, Color("5f7861"))
	for boat in battle_boats051():
		if not boat.sunk:
			var p = plot.position + Vector2(boat.x / 2300.0 * plot.size.x, boat.y / 1700.0 * plot.size.y)
			canvas.draw_circle(p, 3 if boat.id == host.battle.playerId else 2, ENEMY if boat.team == "enemy" else GOLD if boat.id == host.battle.playerId else FRIEND)

func draw_compass(p: Vector2):
	draw_arc(p, 27, 0, TAU, 48, Color(0.69, 0.79, 0.65, 0.35), 1, true)
	draw_line(p - Vector2(35, 0), p + Vector2(35, 0), Color(0.69, 0.79, 0.65, 0.28), 1, true)
	draw_line(p - Vector2(0, 35), p + Vector2(0, 35), Color(0.69, 0.79, 0.65, 0.28), 1, true)
	draw_colored_polygon(PackedVector2Array([p - Vector2(0, 26), p + Vector2(4, 3), p + Vector2(-4, 3)]), Color(GOLD, 0.45))
	text_at("N", p - Vector2(0, 43), 10, Color(GOLD, 0.6), mono, true)
