class_name BoatPortrait
extends Control
## Reusable boat portrait for the refit/fitting panel. Draws the exact same
## BoatArt geometry as the chart, fitted into this control. Works without a
## live campaign: assign `boat` (a ship Dictionary with a `spec`), or call
## set_spec(spec) to preview any hull/fitted spec directly.

const BoatArt = preload("res://scripts/boat_art.gd")

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

func _draw() -> void:
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
	if not display.has("angle"):
		display.angle = display_angle
	if not display.has("turretAngle"):
		display.turretAngle = float(display.angle) + 0.35
	display.vx = 0.0
	display.vy = 0.0
	# Fit: hull length in world units is ~4.4 * spec.size (command is longest).
	var world_len := maxf(20.0, float(spec.get("size", 16)) * 4.6)
	var k := minf(size.x * 0.78 / (world_len * 1.08), size.y * 0.72 / (world_len * 0.60))
	var origin := center + Vector2(0, size.y * 0.06)
	var projector := func(p: Vector2, h: float) -> Vector2:
		return origin + Vector2((p.x - p.y) * 0.82, (p.x + p.y) * 0.41 - h) * k
	BoatArt.draw_boat(self, projector, display, {
		"accent": accent, "enemy": enemy, "lod": 0, "clock": 0.0,
		"px": maxf(4.0, k * float(spec.get("size", 16))), "enlargement": 1.0})
	var font := get_theme_default_font()
	if font != null:
		var label := str(spec.get("name", spec.get("id", "Boat")))
		var sub := (str(spec.get("role", "")) + " · " + BoatArt.archetype(spec)).to_upper()
		draw_string(font, Vector2(12, 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("e6dfc6"))
		draw_string(font, Vector2(12, 36), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.68, 0.80, 0.72, 0.85))
