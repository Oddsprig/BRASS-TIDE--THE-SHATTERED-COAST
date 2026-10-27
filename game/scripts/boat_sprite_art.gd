extends RefCounted
## Manifest-backed authored hulls and seven interchangeable weapon variants.
## BoatArt retains procedural hulls, non-isometric charts and missing-asset art.
## An atlas cell is an offline render, never a viewport rendered at runtime.

const Geometry = preload("res://scripts/weapon_geometry.gd")
const WeaponArt = preload("res://scripts/weapon_art.gd")
const HULL_MANIFEST := "res://assets/boats042/asset-manifest.json"
const WEAPON_MANIFEST := "res://assets/boats042/weapons/asset-manifest.json"
const IDS := ["tin_skiff", "ash_corvette", "brasswind_motor_galleon"]
const ISO := Transform2D(Vector2(0.82, 0.41), Vector2(-0.82, 0.41), Vector2.ZERO)
const HULL_REFERENCE_HEIGHT := 9.7
const FRAME_CELL_DEFAULT := [384, 320]
const FRAME_PIVOT_DEFAULT := [192, 200]
static var _manifests: Dictionary = {}
static var _textures: Dictionary = {}
static var _hull_entries: Dictionary = {}
static var _atlas_frames: Dictionary = {}
static var _iso_inverse: Transform2D = ISO.affine_inverse()
const ATLAS_FRAME_LIMIT: int = 128

# Owned only by one synchronous Chart boat loop. Its real CanvasItem submits
# cannot edit manifests/textures between boats; no public or recorder draw uses
# this snapshot. A new loop checks each atlas again through _ready_frame().
class _BattleAtlas051 extends RefCounted:
	var snapshots: Dictionary = {}

static func _manifest(path: String) -> Dictionary:
	if not _manifests.has(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_manifests[path] = parsed if parsed is Dictionary else {}
	return _manifests[path]

static func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		var resource = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
		_textures[path] = resource if resource is Texture2D else null
	return _textures[path]

static func _finite_hull_array(value, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)): return false
	return true

## Called once per cached entry. Root supplies completed actual bake bounds;
## source seeds lack32 real bounds and cannot become runtime-eligible.
static func _valid_hull_entry(entry: Dictionary) -> bool:
	if entry.get("headings", 0) != 32 or entry.get("columns", 0) != 8 or entry.get("rows", 0) != 4 or entry.get("pixels_per_world_unit", 0) != 2: return false
	var cell = entry.get("cell_px", [])
	var pivot = entry.get("pivot_px", [])
	var bounds = entry.get("frame_bounds_px", [])
	if not _finite_hull_array(cell, 2) or not _finite_hull_array(pivot, 2): return false
	for dimension in cell:
		if float(dimension) <= 0 or float(dimension) != floorf(float(dimension)): return false
	if float(pivot[0]) < 0 or float(pivot[1]) < 0 or float(pivot[0]) > float(cell[0]) or float(pivot[1]) > float(cell[1]): return false
	if not bounds is Array or bounds.size() != 32: return false
	for bound in bounds:
		if not _finite_hull_array(bound, 4): return false
		for number in bound:
			if float(number) != floorf(float(number)): return false
		if float(bound[0]) < 0 or float(bound[1]) < 0 or float(bound[2]) <= 0 or float(bound[3]) <= 0: return false
		if float(bound[0]) + float(bound[2]) > float(cell[0]) or float(bound[1]) + float(bound[3]) > float(cell[1]): return false
	var atlas = entry.get("atlas", "")
	return atlas is String and not atlas.is_empty() and ResourceLoader.exists(atlas)

static func hull_entry(spec: Dictionary) -> Dictionary:
	var id: String = str(spec.get("id", ""))
	if not _hull_entries.has(id):
		var manifest: Dictionary = _manifest(HULL_MANIFEST)
		var hulls = manifest.get("hulls", {})
		var entry = hulls.get(id, {}) if hulls is Dictionary else {}
		_hull_entries[id] = entry if str(manifest.get("schema", "")) == "brass-tide-boats042-v1" and entry is Dictionary and _valid_hull_entry(entry) else {}
	return _hull_entries[id]

## Inspection shared by the actual renderer, the portrait and native recorder.
## Coordinates are pixel rectangles in the original atlas; no mock geometry.
static func frame_info(spec: Dictionary, angle: float, high_detail: bool = false) -> Dictionary:
	var entry: Dictionary = hull_entry(spec)
	if entry.is_empty(): return {}
	var info: Dictionary = _frame(entry, angle)
	# The portrait is a real second-density bake at exactly direction 28.
	# Other headings keep using their actual directional atlas cell.
	if high_detail and info.heading == int(entry.get("portrait_heading", 28)) and absf(wrapf(angle - float(info.angle), -PI, PI)) < 0.0001:
		var portrait: String = str(entry.get("portrait", ""))
		if not portrait.is_empty() and _texture(portrait) != null:
			var cell: Array = entry.get("portrait_cell_px", [768, 640])
			info.path = portrait
			info.source = Rect2(0, 0, float(cell[0]), float(cell[1]))
			info.pivot = _v2(entry.get("portrait_pivot_px", [384, 400]))
			info.density = float(entry.get("portrait_pixels_per_world_unit", 4.0))
	return info

static func _v2(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

static func _frame(entry: Dictionary, angle: float) -> Dictionary:
	var headings: int = maxi(1, int(entry.get("headings", 32)))
	var columns: int = maxi(1, int(entry.get("columns", 8)))
	var heading: int = posmod(int(roundf(angle / TAU * headings)), headings)
	var cell: Vector2 = _v2(entry.get("cell_px", [384, 320]))
	return {"path": str(entry.get("atlas", "")), "heading": heading,
		"angle": float(heading) * TAU / headings,
		"source": Rect2(Vector2(heading % columns, floori(float(heading) / columns)) * cell, cell),
		"pivot": _v2(entry.get("pivot_px", [192, 200])),
		"density": float(entry.get("pixels_per_world_unit", 2.0))}

## Returns zero for the nautical chart and nonstandard test projectors. It is
## safer to use existing geometry than distort an isometric bitmap into them.
static func _screen_scale(ctx: Dictionary) -> float:
	var origin: Vector2 = ctx.proj.call(ctx.pos, 0.0)
	var ex: Vector2 = ctx.proj.call(ctx.pos + Vector2.RIGHT, 0.0) - origin
	var ey: Vector2 = ctx.proj.call(ctx.pos + Vector2.DOWN, 0.0) - origin
	var eh: Vector2 = ctx.proj.call(ctx.pos, 1.0) - origin
	var scale: float = ex.length() / Vector2(0.82, 0.41).length()
	var tolerance: float = maxf(0.001, scale * 0.001)
	if ex.distance_to(Vector2(0.82, 0.41) * scale) > tolerance or ey.distance_to(Vector2(-0.82, 0.41) * scale) > tolerance or eh.distance_to(Vector2(0, -scale)) > tolerance: return 0.0
	return scale

static func _cell_ready(info: Dictionary) -> bool:
	var texture: Texture2D = _texture(str(info.path))
	if texture == null or float(info.density) <= 0.0: return false
	var source: Rect2 = info.source
	return source.position.x >= 0.0 and source.position.y >= 0.0 and source.size.x > 0.0 and source.size.y > 0.0 and source.end.x <= texture.get_width() and source.end.y <= texture.get_height()

# Only atlas geometry/readiness is retained. Each path has one bounded snapshot;
# every hit compares fresh metadata values, texture identity and current size.
# No warm Array key, aliased metadata, boat, aim or condition is retained.
static func _ready_frame(entry: Dictionary, angle: float) -> Dictionary:
	var path: String = str(entry.get("atlas", ""))
	var texture: Texture2D = _texture(path)
	if texture == null: return {}
	var headings: int = maxi(1, int(entry.get("headings", 32)))
	var columns: int = maxi(1, int(entry.get("columns", 8)))
	var texture_size: Vector2 = texture.get_size()
	var cell: Vector2 = _v2(entry.get("cell_px", FRAME_CELL_DEFAULT))
	var pivot: Vector2 = _v2(entry.get("pivot_px", FRAME_PIVOT_DEFAULT))
	var density: float = float(entry.get("pixels_per_world_unit", 2.0))
	# Nonstandard heading counts keep the checked reference path, without
	# allocating an arbitrary number of descriptors from custom metadata.
	if headings != 32:
		var info: Dictionary = _frame(entry, angle)
		if not _cell_ready(info): return {}
		info.texture = texture
		return info
	var cached = _atlas_frames.get(path)
	if (cached is Dictionary and is_same(cached.texture, texture)
		and cached.texture_size == texture_size and cached.headings == headings
		and cached.columns == columns and cached.cell == cell
		and cached.pivot == pivot and cached.density == density):
		return cached.frames[posmod(int(roundf(angle / TAU * headings)), headings)]
	var frames: Array = []
	for heading in range(headings):
		var info: Dictionary = _frame(entry, float(heading) * TAU / headings)
		if _cell_ready(info): info.texture = texture
		else: info = {}
		info.make_read_only()
		frames.append(info)
	frames.make_read_only()
	if not _atlas_frames.has(path) and _atlas_frames.size() >= ATLAS_FRAME_LIMIT: _atlas_frames.clear()
	var prepared: Dictionary = {"texture": texture, "texture_size": texture_size,
		"headings": headings, "columns": columns, "cell": cell, "pivot": pivot,
		"density": density, "frames": frames}
	prepared.make_read_only()
	_atlas_frames[path] = prepared
	return frames[posmod(int(roundf(angle / TAU * headings)), headings)]

static func _battle_ready_frame051(entry: Dictionary, angle: float, batch: _BattleAtlas051) -> Dictionary:
	if batch == null or int(entry.get("headings", 32)) != 32:
		return _ready_frame(entry, angle)
	var path: String = str(entry.get("atlas", ""))
	var snapshot = batch.snapshots.get(path)
	# Distinct manifest entries may name one texture with different geometry.
	# Only the exact already-checked entry shares its immutable descriptor table.
	if snapshot is Dictionary and is_same(snapshot.entry, entry):
		return snapshot.frames[posmod(int(roundf(angle / TAU * 32)), 32)]
	var info: Dictionary = _ready_frame(entry, angle)
	if not info.is_empty() and batch.snapshots.size() < ATLAS_FRAME_LIMIT:
		batch.snapshots[path] = {"entry": entry, "frames": _atlas_frames[path].frames}
	return info

static func _draw_cell(ctx: Dictionary, info: Dictionary, origin: Vector2, scale: float) -> bool:
	if not _cell_ready(info): return false
	return _draw_ready_cell(ctx, info, _texture(str(info.path)), origin, scale)

static func _draw_ready_cell(ctx: Dictionary, info: Dictionary, texture: Texture2D, origin: Vector2, scale: float) -> bool:
	var source: Rect2 = info.source
	var factor: float = scale / float(info.density)
	ctx.canvas.draw_texture_rect_region(texture, Rect2(origin - Vector2(info.pivot) * factor, source.size * factor), source, Color.WHITE, false, true)
	ctx.n += 1
	ctx.nsprite = int(ctx.get("nsprite", 0)) + 1
	return true

## Rotate residual XY in the ISO basis about the actual weapon-base plane.
## The cell still uses its authored waterline pixel pivot. A flattened image
## cannot separate every pixel's elevation: points at other heights lean by
## at most ~0.196 * height difference * scale over the half-heading interval.
static func _hull_transform(info: Dictionary, angle: float, scale: float) -> Transform2D:
	var residual: float = wrapf(angle - float(info.angle), -PI, PI)
	var transform: Transform2D = ISO * Transform2D(residual, Vector2.ZERO) * _iso_inverse
	var plane: Vector2 = Vector2(0, -HULL_REFERENCE_HEIGHT * scale)
	transform.origin = plane - transform * plane
	return transform

static func draw_hull(ctx: Dictionary, spec: Dictionary, screen_scale: float = -1.0) -> bool:
	return _draw_hull051(ctx, spec, screen_scale, null)

static func _draw_hull051(ctx: Dictionary, spec: Dictionary, screen_scale: float, batch: _BattleAtlas051) -> bool:
	if not ctx.canvas.has_method("draw_texture_rect_region"): return false
	if not ctx.canvas.has_method("draw_set_transform_matrix"): return false
	# Legacy enlargement scales XY but deliberately leaves world heights alone.
	# A single bitmap cannot represent that anisotropic 3D operation accurately.
	if not is_equal_approx(float(ctx.get("enlargement", 1.0)), 1.0): return false
	var scale: float = _screen_scale(ctx) if screen_scale < 0.0 else screen_scale
	if scale <= 0.0: return false
	var entry: Dictionary = hull_entry(spec)
	if entry.is_empty(): return false
	if not is_equal_approx(float(spec.get("size", 0)), float(entry.get("size", 0))): return false
	# Public inspection remains fresh/mutable. The exceptional exact-heading
	# portrait uses its existing checked selection instead of mutating a frame.
	var info: Dictionary
	if bool(ctx.get("portrait", false)) or scale > 2.0:
		info = frame_info(spec, float(ctx.angle), true)
		if info.is_empty() or not _cell_ready(info): return false
		info.texture = _texture(str(info.path))
	else:
		info = _battle_ready_frame051(entry, float(ctx.angle), batch)
		if info.is_empty(): return false
	var transform: Transform2D = _hull_transform(info, float(ctx.angle), scale)
	transform.origin += Vector2(ctx.proj.call(ctx.pos, 0.0))
	ctx.canvas.draw_set_transform_matrix(transform)
	var drew: bool = _draw_ready_cell(ctx, info, info.texture, Vector2.ZERO, scale)
	ctx.canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	return drew

static func weapon_variant(mount: Dictionary) -> String:
	var kind: String = str(mount.get("kind", "gun"))
	var tier: int = int(mount.get("size", 1))
	match kind:
		"gun": return "gun_twin" if tier > 1 or "twin" in str(mount.get("moduleId", "")) else "gun_single"
		"cannon": return "cannon"
		"rocket": return "rocket_six" if tier >= 3 or "salvo" in str(mount.get("moduleId", "")) else "rocket_three"
		"torpedo": return "torpedo_twin" if tier > 1 else "torpedo_single"
	return ""

## Both sprite layers rotate from the physical fitting bearing. The moving
## receiver/barrel layer translates after a REAL mount shot, leaving its cradle
## fixed. No invented firing clock, extra projectiles, or cached damage state.
static func draw_weapon(ctx: Dictionary, mount: Dictionary, bearing: float, screen_scale: float = -1.0) -> bool:
	return _draw_weapon051(ctx, mount, bearing, screen_scale, null)

static func _draw_weapon051(ctx: Dictionary, mount: Dictionary, bearing: float, screen_scale: float, batch: _BattleAtlas051) -> bool:
	# A fitting's physical size and pivot do not depend on the hull's art path.
	if not ctx.canvas.has_method("draw_texture_rect_region"): return false
	if not ctx.canvas.has_method("draw_set_transform_matrix"): return false
	# Legacy enlargement changes XY but not height; retain its mechanical art.
	if not is_equal_approx(float(ctx.get("enlargement", 1.0)), 1.0): return false
	var manifest: Dictionary = _manifest(WEAPON_MANIFEST)
	if str(manifest.get("schema", "")) != "brass-tide-weapons042-v1": return false
	var entry: Dictionary = manifest.get("weapons", {}).get(weapon_variant(mount), {})
	if entry.is_empty(): return false
	var scale: float = _screen_scale(ctx) if screen_scale < 0.0 else screen_scale
	if scale <= 0.0: return false
	var tier: int = clampi(int(mount.get("size", 1)), 1, 3)
	var unit: float = Geometry.unit(float(ctx.hull_size), tier)
	var kind: String = str(mount.kind)
	var base: Dictionary = entry.get("base", {})
	var moving: Dictionary = entry.get("moving", {})
	var base_info: Dictionary = _battle_ready_frame051(base, bearing, batch)
	var moving_info: Dictionary = _battle_ready_frame051(moving, bearing, batch) if not moving.is_empty() else {}
	# Refuse the whole mechanism before submitting either layer. A partial
	# atlas must not leave a sprite over the procedural fallback weapon.
	if base_info.is_empty(): return false
	if not moving.is_empty() and moving_info.is_empty(): return false
	var position: Vector2 = ctx.pos + Vector2(mount.x, mount.y).rotated(float(ctx.angle)) * float(ctx.size)
	var origin: Vector2 = ctx.proj.call(position, 9.7)
	var residual: float = wrapf(bearing - float(base_info.angle), -PI, PI)
	var transform: Transform2D = ISO * Transform2D(residual, Vector2.ZERO) * _iso_inverse
	# Correct the residual about the shared firing plane, keeping the actual
	# WeaponGeometry muzzle position exact even between baked directions.
	var muzzle_h: float = Geometry.height(kind, float(ctx.hull_size), tier) - 9.7
	if kind == "torpedo": muzzle_h = 2.8 * unit
	var plane: Vector2 = Vector2(0, -muzzle_h * scale)
	transform.origin = origin + plane - transform * plane
	ctx.canvas.draw_set_transform_matrix(transform)
	var drew: bool = _draw_ready_cell(ctx, base_info, base_info.texture, Vector2.ZERO, scale * unit)
	if not moving_info.is_empty():
		var recoil: float = WeaponArt.recoil_offset(ctx, mount)
		# Offset is expressed in the baked frame before the residual transform.
		var xy: Vector2 = Vector2.from_angle(float(base_info.angle)) * recoil * unit
		var shift: Vector2 = Vector2((xy.x - xy.y) * 0.82, (xy.x + xy.y) * 0.41) * scale
		_draw_ready_cell(ctx, moving_info, moving_info.texture, shift, scale * unit)
	ctx.canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	return drew

static func audit(spec: Dictionary) -> Dictionary:
	var entry: Dictionary = hull_entry(spec)
	var path: String = str(entry.get("atlas", ""))
	return {"id": str(spec.get("id", "")), "authored": not entry.is_empty(),
		"atlas": path, "texture_ready": _texture(path) != null if not path.is_empty() else false,
		"entry": entry, "weapon_manifest": _manifest(WEAPON_MANIFEST),
		"cached_textures": _textures.size(), "projection": [0.82, 0.41, 1.0]}

## Conservative occupied rectangle at ISO scale 1, relative to the waterline.
## Offline alpha bounds can tighten framing; a missing bake is never guessed.
static func bounds(spec: Dictionary, angle: float, portrait: bool = false) -> Rect2:
	var info: Dictionary = frame_info(spec, angle, portrait)
	if info.is_empty(): return Rect2()
	var entry: Dictionary = hull_entry(spec)
	var density: float = float(info.density)
	if density <= 0.0: return Rect2()
	var occupied := Rect2(Vector2.ZERO, Rect2(info.source).size)
	var supplied = entry.get("portrait_bounds_px", []) if str(info.path) == str(entry.get("portrait", "")) else []
	var frames: Array = entry.get("frame_bounds_px", [])
	if supplied.is_empty() and int(info.heading) < frames.size(): supplied = frames[int(info.heading)]
	if supplied is Array and supplied.size() == 4:
		occupied = Rect2(float(supplied[0]), float(supplied[1]), float(supplied[2]), float(supplied[3]))
	var result := Rect2((occupied.position - Vector2(info.pivot)) / density, occupied.size / density)
	# Frame the same residual-corrected bitmap that draw_hull actually submits.
	var transform: Transform2D = _hull_transform(info, angle, 1.0)
	var corners := [result.position, Vector2(result.end.x, result.position.y), result.end, Vector2(result.position.x, result.end.y)]
	result = Rect2(transform * Vector2(corners[0]), Vector2.ZERO)
	for corner in corners: result = result.expand(transform * Vector2(corner))
	# Include the largest installed mechanism at its physical fitting anchor.
	# This envelope includes recoil, bases, feeds and tube mouths in every pose.
	for mount in spec.get("weaponMounts", []):
		if not mount is Dictionary: continue
		var unit: float = Geometry.unit(float(spec.get("size", 14)), int(mount.get("size", 1)))
		var base: Vector2 = Vector2(float(mount.get("x", 0)), float(mount.get("y", 0))).rotated(angle)
		var bearing: float = angle + float(mount.get("angle", 0))
		for x in [-9.0, 15.0]:
			for y in [-4.0, 4.0]:
				for z in [9.7, 9.7 + 9.0 * unit]:
					var p: Vector2 = base + Vector2(x, y).rotated(bearing) * unit
					result = result.expand(Vector2((p.x-p.y)*0.82, (p.x+p.y)*0.41-float(z)))
	return result

static func clear_cache() -> void:
	_atlas_frames.clear()
	_manifests.clear()
	_textures.clear()
	_hull_entries.clear()
