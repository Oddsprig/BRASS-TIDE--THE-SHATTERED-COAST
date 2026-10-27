extends RefCounted
## Chart-owned, synchronous native commands. No nodes, workers, global cache or
## render targets. Chart's own commands are PRE; this child subtree is ordered
## whole boats followed by POST. Every RID below was created by this owner.
const MAX_HULLS: int = 96
const MAX_MOUNTS: int = 16
const ISO := Transform2D(Vector2(0.82, 0.41), Vector2(-0.82, 0.41), Vector2.ZERO)

class Item extends RefCounted:
	var rid: RID
	var parent: RID
	var order: int

	func _init(parent_rid: RID, index: int) -> void:
		parent = parent_rid; order = index
		rid = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(rid, parent)
		RenderingServer.canvas_item_set_draw_index(rid, order)
		RenderingServer.canvas_item_set_use_parent_material(rid, true)

	func clear() -> void:
		if rid.is_valid(): RenderingServer.canvas_item_clear(rid)

	func release() -> void:
		if rid.is_valid(): RenderingServer.free_rid(rid)
		rid = RID()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE: release()

# Narrow live-command target for existing art and Chart's post-boat commands.
# Uses the same RenderingServer primitives/flags as CanvasItem, including the
# closed outline, aligned dash endpoints and arc sampling. Font/Texture retain
# their native draw methods rather than reproducing resource-specific behavior.
class Live extends Item:
	var proj: Callable
	var scale_factor: float = 1.0
	var tactical: bool = false

	func _init(parent_rid: RID, index: int) -> void:
		super(parent_rid, index)

	func project(p: Vector2, h: float = 0.0) -> Vector2:
		return proj.call(p, h)

	func draw_line(a: Vector2, b: Vector2, color: Color, width: float = -1.0, aa: bool = false) -> void:
		RenderingServer.canvas_item_add_line(rid, a, b, color, width, aa)

	func draw_polyline(points: PackedVector2Array, color: Color, width: float = -1.0, aa: bool = false) -> void:
		RenderingServer.canvas_item_add_polyline(rid, points, PackedColorArray([color]), width, aa)

	func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
		RenderingServer.canvas_item_add_polygon(rid, points, PackedColorArray([color]))

	func draw_circle(at: Vector2, radius: float, color: Color) -> void:
		RenderingServer.canvas_item_add_circle(rid, at, radius, color)

	func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0, aa: bool = false) -> void:
		rect = rect.abs()
		if filled: RenderingServer.canvas_item_add_rect(rid, rect, color, aa)
		elif width >= rect.size.x or width >= rect.size.y:
			RenderingServer.canvas_item_add_rect(rid, rect.grow(width * 0.5), color, aa)
		else:
			draw_polyline(PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y), rect.position]), color, width, aa)

	func draw_arc(at: Vector2, radius: float, start: float, end: float, count: int, color: Color, width: float = -1.0, aa: bool = false) -> void:
		var points := PackedVector2Array()
		points.resize(count)
		var span: float = clampf(end - start, -TAU, TAU)
		for i in range(count):
			var angle: float = float(i) / (count - 1.0) * span + start
			points[i] = at + Vector2(radius * cos(angle), radius * sin(angle))
		draw_polyline(points, color, width, aa)

	func draw_dashed_line(a: Vector2, b: Vector2, color: Color, width: float = -1.0, dash: float = 2.0, aligned: bool = true, aa: bool = false) -> void:
		var length: float = (b - a).length()
		var step: Vector2 = dash * (b - a).normalized()
		if length < dash or step == Vector2.ZERO:
			draw_line(a, b, color, width, aa); return
		var count: int = ceili(length / dash) if aligned else floori(length / dash)
		if count % 2 == 0: count -= 1
		var offset: Vector2 = a
		if aligned: offset += (b - a).normalized() * (length - count * dash) / 2.0
		var points := PackedVector2Array()
		points.resize(count + 1)
		for i in range(0, count, 2):
			points[i] = a if i == 0 else offset
			points[i + 1] = b if aligned and i == count - 1 else offset + step
			offset += step * 2
		RenderingServer.canvas_item_add_multiline(rid, points, PackedColorArray([color]), width, aa)

	func draw_string(font: Font, at: Vector2, value: String, alignment: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, size: int = 16, color: Color = Color.WHITE) -> void:
		font.draw_string(rid, at, value, alignment, width, size, color)

	func draw_texture_rect_region(texture: Texture2D, rect: Rect2, source: Rect2, color: Color = Color.WHITE, transpose: bool = false, clip_uv: bool = true) -> void:
		texture.draw_rect_region(rid, rect, source, color, transpose, clip_uv)

	func draw_set_transform_matrix(transform: Transform2D) -> void:
		RenderingServer.canvas_item_add_set_transform(rid, transform)

class Cell extends Item:
	var info: Dictionary = {}
	var scale: float = -1.0
	var rect: Rect2
	var transform: Transform2D = Transform2D.IDENTITY
	var texture: Texture2D

	func _init(parent_rid: RID, index: int) -> void:
		super(parent_rid, index)

	func update_cell(frame: Dictionary, shift: Vector2, screen_scale: float, current: Transform2D) -> void:
		# Ready descriptors are immutable and replaced when atlas identity, size or
		# metadata changes. Never keep a borrowed mutable manifest as the key.
		if not is_same(info, frame) or scale != screen_scale:
			info = frame; scale = screen_scale; texture = frame.texture
			var factor: float = scale / float(frame.density)
			rect = Rect2(-Vector2(frame.pivot) * factor, Vector2(frame.source.size) * factor)
			clear()
			texture.draw_rect_region(rid, rect, frame.source, Color.WHITE, false, true)
		transform = current
		# A moving layer's baked-frame recoil is a translation before the same
		# residual ISO affine, not a change to the fixed cradle or world bearing.
		if shift != Vector2.ZERO: transform.origin += current.basis_xform(shift)
		RenderingServer.canvas_item_set_transform(rid, transform)

	func invalidate() -> void:
		info = {}; texture = null; scale = -1.0; clear()

class Fan extends Item:
	var points := PackedVector2Array()
	var screen_points := PackedVector2Array()
	var indices := PackedInt32Array()
	var height: float
	var color: Color
	var transform: Transform2D = Transform2D.IDENTITY

	func _init(parent_rid: RID, index: int) -> void:
		super(parent_rid, index)

	func configure(local_points: PackedVector2Array, plane: float, tint: Color) -> void:
		points = local_points; height = plane; color = tint
		indices = PackedInt32Array(); clear()

	func update_fan(ctx: Dictionary, screen_scale: float) -> int:
		# Keep EXACT current screen-space rejection. Constant planar area in real
		# arithmetic is not a license to reuse a float32 threshold decision.
		screen_points.resize(points.size())
		for i in range(points.size()):
			screen_points[i] = ctx.proj.call(ctx.pos + points[i].rotated(float(ctx.angle)) * float(ctx.size), height)
		var current := PackedInt32Array()
		for i in range(1, screen_points.size() - 1):
			if absf((screen_points[i] - screen_points[0]).cross(screen_points[i + 1] - screen_points[0])) < 1.0: continue
			current.append(0); current.append(i); current.append(i + 1)
		if current != indices:
			indices = current; clear()
			if not indices.is_empty(): RenderingServer.canvas_item_add_triangle_array(rid, indices, points, PackedColorArray([color]))
		var basis: Transform2D = ISO * Transform2D(float(ctx.angle), Vector2.ZERO)
		var factor: float = float(ctx.size) * screen_scale
		transform = Transform2D(basis.x * factor, basis.y * factor, ctx.proj.call(ctx.pos, height))
		RenderingServer.canvas_item_set_transform(rid, transform)
		return indices.size() / 3

class Scar extends RefCounted:
	var root: Item
	var outer: Fan
	var inner: Fan
	var lines: Live
	var hit: Dictionary = {}
	var size: float = -1.0
	var scale: float = -1.0
	var lod: int = -1

	func _init(parent: RID, index: int) -> void:
		root = Item.new(parent, index)
		outer = Fan.new(root.rid, 0); inner = Fan.new(root.rid, 1); lines = Live.new(root.rid, 2)

	func matches(value: Dictionary, ctx: Dictionary, screen_scale: float) -> bool:
		return hit == value and size == float(ctx.size) and lod == int(ctx.lod) and scale == screen_scale

	func configure(value: Dictionary, ctx: Dictionary, screen_scale: float, outside: PackedVector2Array, inside: PackedVector2Array) -> void:
		hit = value.duplicate(true); size = float(ctx.size); lod = int(ctx.lod); scale = screen_scale
		outer.configure(outside, 10.1, Color("3b352c"))
		inner.configure(inside, 10.1 + 0.15, Color("121e20"))

	func update_scar(ctx: Dictionary) -> void:
		var count: int = outer.update_fan(ctx, scale) + inner.update_fan(ctx, scale)
		ctx.n += count; ctx.npoly += count

	func release() -> void:
		outer.release(); inner.release(); lines.release(); root.release()

class Weapon extends RefCounted:
	var root: Item
	var base: Cell
	var moving: Cell
	var frames: Dictionary

	func _init(parent: RID, index: int) -> void:
		root = Item.new(parent, index)
		base = Cell.new(root.rid, 0); moving = Cell.new(root.rid, 1)

	func release() -> void:
		base.release(); moving.release(); root.release()

class Boat extends RefCounted:
	var root: Item
	var pre: Live
	var hull: Cell
	var motor: Live
	var weapons_root: Item
	var scars_root: Item
	var after: Live
	var weapons: Array = []
	var scars: Array = []
	var inputs: Dictionary = {}
	var lod: int = -1

	func _init(parent: RID, index: int) -> void:
		root = Item.new(parent, index)
		pre = Live.new(root.rid, 0); hull = Cell.new(root.rid, 1); motor = Live.new(root.rid, 2)
		weapons_root = Item.new(root.rid, 3); scars_root = Item.new(root.rid, 4); after = Live.new(root.rid, 5)

	func prepare(current: Dictionary, index: int) -> void:
		if inputs.is_empty() or not is_same(inputs.prepared, current.prepared) or inputs.scale != current.scale:
			hull.invalidate()
			for weapon in weapons: weapon.release()
			weapons.clear(); finish_scars(0)
		inputs = current
		root.order = index
		RenderingServer.canvas_item_set_draw_index(root.rid, index)
		RenderingServer.canvas_item_set_visible(root.rid, true)
		# Culling suppresses the body, not the existing subsequent secured/order
		# indicators (their destination can still be on screen for a culled boat).
		for item in [hull, motor, weapons_root, scars_root]: RenderingServer.canvas_item_set_visible(item.rid, false)
		pre.clear(); motor.clear(); after.clear()
		while weapons.size() > current.weapons.size():
			var removed = weapons.pop_back(); removed.release()
		while weapons.size() < current.weapons.size(): weapons.append(Weapon.new(weapons_root.rid, weapons.size()))
		for i in range(weapons.size()):
			weapons[i].frames = current.weapons[i]
			RenderingServer.canvas_item_set_visible(weapons[i].moving.rid, not current.weapons[i].moving.is_empty())
		for scar in scars: scar.lines.clear()

	func show_at_lod(current: int) -> void:
		if lod != current:
			lod = current; hull.invalidate()
			for weapon in weapons:
				weapon.base.invalidate(); weapon.moving.invalidate()
			finish_scars(0)
		for item in [hull, motor, weapons_root, scars_root]: RenderingServer.canvas_item_set_visible(item.rid, true)

	func scar_at(index: int) -> Scar:
		while scars.size() <= index: scars.append(Scar.new(scars_root.rid, scars.size()))
		return scars[index]

	func finish_scars(count: int) -> void:
		while scars.size() > count:
			var removed = scars.pop_back(); removed.release()

	func release() -> void:
		finish_scars(0)
		for weapon in weapons: weapon.release()
		weapons.clear(); inputs = {}
		pre.release(); hull.release(); motor.release(); weapons_root.release(); scars_root.release(); after.release(); root.release()

var root: Item
var post: Live
var boats: Dictionary = {}

func _init(parent: RID) -> void:
	root = Item.new(parent, 0)
	post = Live.new(root.rid, MAX_HULLS)

func begin_frame(ids: Array, inputs: Array) -> bool:
	# Reject before touching any current group. Chart releases this owner and
	# draws the ENTIRE frame through the checked path on any unsupported input.
	if ids.size() > MAX_HULLS or ids.size() != inputs.size(): return false
	var seen: Dictionary = {}
	for i in range(ids.size()):
		if str(ids[i]).is_empty() or seen.has(ids[i]) or inputs[i].is_empty() or inputs[i].weapons.size() > MAX_MOUNTS: return false
		seen[ids[i]] = true
	for id in boats.keys():
		if not seen.has(id):
			boats[id].release(); boats.erase(id)
	for i in range(ids.size()):
		if not boats.has(ids[i]): boats[ids[i]] = Boat.new(root.rid, i)
		boats[ids[i]].prepare(inputs[i], i)
	post.clear()
	return true

func release() -> void:
	for boat in boats.values(): boat.release()
	boats.clear()
	if post != null: post.release()
	if root != null: root.release()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE: release()
