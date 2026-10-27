class_name BoatPortrait
extends Control
## Reusable boat portrait for the refit/fitting panel. Draws the exact same
## BoatArt hull and live weapon composition as the chart, fitted into this control. Works without a
## live campaign: assign `boat` (a ship Dictionary with a `spec`), or call
## set_spec(spec) to preview any hull/fitted spec directly.

const BoatArt = preload("res://scripts/boat_art.gd")
const Profiles = preload("res://scripts/hull_profiles.gd")
const Layout=preload("res://scripts/mount_layout.gd")
const SpriteArt=preload("res://scripts/boat_sprite_art.gd")
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
var display_angle: float = 0.0:
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
	draw_contents(self,size)

## Bounds and pivot use the same real frame metadata as BoatArt. Atlas alpha
## padding must not make a skiff tiny, or clip the large merchant's machinery.
func framing(spec: Dictionary,view_size: Vector2) -> Dictionary:
	var span: float=Profiles.preview_span(spec)
	var k: float=minf(view_size.x*0.78/(span*1.08),view_size.y*0.72/(span*0.60))
	var origin: Vector2=view_size*0.5+Vector2(0,view_size.y*0.06)
	if bool(SpriteArt.audit(spec).get("texture_ready",false)):
		var bounds: Rect2=SpriteArt.bounds(spec,display_angle,true)
		if bounds.size.x>0.0 and bounds.size.y>0.0:
			var top: float=44.0 if view_size.y>=100.0 else 6.0
			var edge: float=18.0 if show_sockets else 10.0
			var bottom: float=34.0 if show_sockets else 10.0
			var area:=Rect2(edge,top,maxf(1.0,view_size.x-edge*2.0),maxf(1.0,view_size.y-top-bottom))
			k=minf(area.size.x/bounds.size.x,area.size.y/bounds.size.y)
			origin=area.get_center()-bounds.get_center()*k
	return {"scale":k,"origin":origin}

## The normal refit/Lab draw path is also recordable by the focused art fixture.
## The recorder receives the same primitives/textures, projector and fittings.
func draw_contents(canvas,view_size: Vector2) -> void:
	_socket_points=[]
	var rect := Rect2(Vector2.ZERO, view_size)
	canvas.draw_rect(rect, Color("14313e"))
	canvas.draw_rect(rect, Color(0.55, 0.72, 0.63, 0.35), false, 1.0)
	# Faint chart rings behind the boat.
	var center := view_size * 0.5
	for r in [0.32, 0.55, 0.78]:
		canvas.draw_arc(center, minf(view_size.x, view_size.y) * r * 0.5, 0.0, TAU, 48, Color(0.62, 0.80, 0.70, 0.10), 1.0, true)
	var spec_v = boat.get("spec", {}) if boat is Dictionary else {}
	if not (spec_v is Dictionary) or spec_v.is_empty():
		var font := get_theme_default_font()
		if font != null:
			canvas.draw_string(font, Vector2(14, view_size.y - 14), "NO BOAT SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.82, 0.72, 0.7))
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
	var frame: Dictionary=framing(spec,view_size)
	var k: float=float(frame.scale)
	var origin: Vector2=frame.origin
	var projector := func(p: Vector2, h: float) -> Vector2:
		return origin + Vector2((p.x - p.y) * 0.82, (p.x + p.y) * 0.41 - h) * k
	if show_arcs:
		var sockets: Array=Layout.hardpoints(spec)
		if selected_socket>=0 and selected_socket<sockets.size():
			_draw_socket_arc(canvas,projector,sockets[selected_socket],spec,minf(view_size.x,view_size.y)*0.36/maxf(0.01,k))
	BoatArt.draw_boat(canvas, projector, display, {
		"accent": accent, "enemy": enemy, "lod": 0, "clock": 0.0,
		"px": maxf(4.0, k * float(spec.get("size", 16))), "enlargement": 1.0,"portrait":true})
	var font := get_theme_default_font()
	if show_sockets:
		var sockets: Array=Layout.hardpoints(spec)
		for i in range(sockets.size()):
			var socket: Dictionary=sockets[i]
			var point: Vector2=projector.call(Vector2(socket.x,socket.y).rotated(display_angle),10.0)
			_socket_points.append(point)
			canvas.draw_arc(point,15.0 if i==selected_socket else 13.0,0,TAU,20,accent if i==selected_socket else Color("8ac9b6"),2.4 if i==selected_socket else 1.2,true)
			canvas.draw_circle(point+Vector2(0,18),9,Color("0b242f"))
			if font!=null:canvas.draw_string(font,point+Vector2(-4,22),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,11,accent)
	if font != null and view_size.y>=100:
		var label := str(spec.get("name", spec.get("id", "Boat")))
		var sub := (str(spec.get("role", "")) + " · " + BoatArt.archetype(spec)).to_upper()
		canvas.draw_string(font, Vector2(12, 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("e6dfc6"))
		canvas.draw_string(font, Vector2(12, 36), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.68, 0.80, 0.72, 0.85))

## A bounded schematic sector, from the same mount ID/origin/angle/arc combat uses.
## Radius is for readability; numeric range is shown by the fitting workspace.
func _draw_socket_arc(canvas,projector: Callable,socket: Dictionary,spec: Dictionary,radius: float) -> void:
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
			canvas.draw_colored_polygon(circle,Color(accent,0.10))
		else:canvas.draw_colored_polygon(sector,Color(accent,0.10))
	canvas.draw_polyline(outline,Color(accent,0.65 if not weapon.is_empty() else 0.28),1.5,true)
	if arc<TAU-0.001:
		canvas.draw_line(center,outline[0],Color(accent,0.7),1.2,true)
		canvas.draw_line(center,outline[outline.size()-1],Color(accent,0.7),1.2,true)
	if not weapon.is_empty():
		canvas.draw_line(center,projector.call(origin+Vector2.from_angle(bearing)*radius,10.0),Color(accent,0.65),1.0,true)
