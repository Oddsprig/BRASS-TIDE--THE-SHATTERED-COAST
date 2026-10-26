class_name BoatPortrait
extends Control
## Reusable boat portrait for the refit/fitting panel. Draws the exact same
## BoatArt geometry as the chart, fitted into this control. Works without a
## live campaign: assign `boat` (a ship Dictionary with a `spec`), or call
## set_spec(spec) to preview any hull/fitted spec directly.

const BoatArt = preload("res://scripts/boat_art.gd")
const Profiles = preload("res://scripts/hull_profiles.gd")
const Layout=preload("res://scripts/mount_layout.gd")
signal mount_selected(index: int)
var _socket_points: Array=[]
var show_arcs: bool=false:
	set(value):
		show_arcs=value
		queue_redraw()
var selected_socket: int=0:
	set(value):
		selected_socket=value
		queue_redraw()
var show_sockets: bool=false:
	set(value):
		show_sockets=value
		mouse_filter=Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
		queue_redraw()

var boat: Dictionary = {}:
	set(value):
		boat = value if value is Dictionary else {}
		queue_redraw()
var accent: Color = Color("dfbd7d"):
	set(value):
		accent = value
		queue_redraw()
var enemy: bool = false:
	set(value):
		enemy = value
		queue_redraw()
var display_angle: float = -0.45:
	set(value):
		display_angle = value
		queue_redraw()

func _init() -> void:
	custom_minimum_size = Vector2(360, 230)
	mouse_filter = MOUSE_FILTER_IGNORE

## Preview a bare hull or fitted effective spec with no campaign state.
func set_spec(spec: Dictionary) -> void:
	boat = BoatArt.preview_boat(spec, display_angle)

func _gui_input(event: InputEvent) -> void:
	if show_sockets and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		for i in range(_socket_points.size()):
			if event.position.distance_to(_socket_points[i])<=17.0:
				mount_selected.emit(i);accept_event();return

func _draw() -> void:
	_socket_points=[]
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color("14313e"))
	draw_rect(rect, Color(0.55, 0.72, 0.63, 0.35), false, 1.0)
	# Faint chart rings behind the boat.
	var center := size * 0.5
	for r in [0.32, 0.55, 0.78]:
		draw_arc(center, minf(size.x, size.y) * r * 0.5, 0.0, TAU, 48, Color(0.62, 0.80, 0.70, 0.10), 1.0, true)
	var spec_v = boat.get("spec", {}) if boat is Dictionary else {}
	if not (spec_v is Dictionary) or spec_v.is_empty():
		var font := get_theme_default_font()
		if font != null:
			draw_string(font, Vector2(14, size.y - 14), "NO BOAT SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.82, 0.72, 0.7))
		return
	var spec: Dictionary = spec_v
	var display: Dictionary = boat.duplicate()
	display.x = 0.0
	display.y = 0.0
	display.angle=display_angle
	display.localAimAngles={}
	display.turretAngle=display_angle
	display.vx = 0.0
	display.vy = 0.0
	var world_len := Profiles.preview_span(spec)
	var k := minf(size.x * 0.78 / (world_len * 1.08), size.y * 0.72 / (world_len * 0.60))
	var origin := center + Vector2(0, size.y * 0.06)
	var projector := func(p: Vector2, h: float) -> Vector2:
		return origin + Vector2((p.x - p.y) * 0.82, (p.x + p.y) * 0.41 - h) * k
	if show_arcs:
		var sockets: Array=Layout.hardpoints(spec)
		if selected_socket>=0 and selected_socket<sockets.size():
			_draw_socket_arc(projector,sockets[selected_socket],spec,minf(size.x,size.y)*0.36/maxf(0.01,k))
	BoatArt.draw_boat(self, projector, display, {
		"accent": accent, "enemy": enemy, "lod": 0, "clock": 0.0,
		"px": maxf(4.0, k * float(spec.get("size", 16))), "enlargement": 1.0})
	var font := get_theme_default_font()
	if show_sockets:
		var sockets: Array=Layout.hardpoints(spec)
		for i in range(sockets.size()):
			var socket: Dictionary=sockets[i]
			var point: Vector2=projector.call(Vector2(socket.x,socket.y).rotated(display_angle),10.0)
			_socket_points.append(point)
			draw_arc(point,15.0 if i==selected_socket else 13.0,0,TAU,20,accent if i==selected_socket else Color("8ac9b6"),2.4 if i==selected_socket else 1.2,true)
			draw_circle(point+Vector2(0,18),9,Color("0b242f"))
			if font!=null:draw_string(font,point+Vector2(-4,22),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,11,accent)
	if font != null and size.y>=100:
		var label := str(spec.get("name", spec.get("id", "Boat")))
		var sub := (str(spec.get("role", "")) + " · " + BoatArt.archetype(spec)).to_upper()
		draw_string(font, Vector2(12, 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("e6dfc6"))
		draw_string(font, Vector2(12, 36), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.68, 0.80, 0.72, 0.85))

## A bounded schematic sector, from the same mount ID/origin/angle/arc combat uses.
## Radius is for readability; numeric range is shown by the fitting workspace.
func _draw_socket_arc(projector: Callable,socket: Dictionary,spec: Dictionary,radius: float) -> void:
	var weapon: Dictionary={}
	for mount in spec.get("weaponMounts",[]):
		if str(mount.get("id",""))==str(socket.id):weapon=mount;break
	var arc: float=float(weapon.get("arc",socket.arc))
	var bearing: float=display_angle+float(weapon.get("angle",socket.angle))
	var origin: Vector2=Vector2(socket.x,socket.y).rotated(display_angle)
	var center: Vector2=projector.call(origin,10.0)
	var outline: PackedVector2Array=[]
	var sector: PackedVector2Array=[center]
	for i in range(49):
		var angle: float=bearing-arc*0.5+arc*float(i)/48.0
		var point: Vector2=projector.call(origin+Vector2.from_angle(angle)*radius,10.0)
		outline.append(point);sector.append(point)
	if not weapon.is_empty():
		if arc>=TAU-0.001:
			var circle: PackedVector2Array=outline.duplicate()
			circle.resize(circle.size()-1)
			draw_colored_polygon(circle,Color(accent,0.10))
		else:draw_colored_polygon(sector,Color(accent,0.10))
	draw_polyline(outline,Color(accent,0.65 if not weapon.is_empty() else 0.28),1.5,true)
	if arc<TAU-0.001:
		draw_line(center,outline[0],Color(accent,0.7),1.2,true)
		draw_line(center,outline[outline.size()-1],Color(accent,0.7),1.2,true)
	if not weapon.is_empty():
		draw_line(center,projector.call(origin+Vector2.from_angle(bearing)*radius,10.0),Color(accent,0.65),1.0,true)
