extends RefCounted
## Authored 0.042 assets only. BoatArt retains procedural art for other hulls,
## non-isometric charts, missing bakes and recorders without texture support.
## An atlas cell is an offline render, never a viewport rendered at runtime.

const Geometry = preload("res://scripts/weapon_geometry.gd")
const HULL_MANIFEST := "res://assets/boats042/asset-manifest.json"
const WEAPON_MANIFEST := "res://assets/boats042/weapons/asset-manifest.json"
const IDS := ["tin_skiff", "ash_corvette", "brasswind_motor_galleon"]
const ISO := Transform2D(Vector2(0.82, 0.41), Vector2(-0.82, 0.41), Vector2.ZERO)
static var _manifests: Dictionary = {}
static var _textures: Dictionary = {}

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

static func hull_entry(spec: Dictionary) -> Dictionary:
	var id: String = str(spec.get("id", ""))
	if id not in IDS: return {}
	var manifest: Dictionary = _manifest(HULL_MANIFEST)
	if str(manifest.get("schema", "")) != "brass-tide-boats042-v1": return {}
	var entry = manifest.get("hulls", {}).get(id, {})
	return entry if entry is Dictionary else {}

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

static func _draw_cell(ctx: Dictionary, info: Dictionary, origin: Vector2, scale: float) -> bool:
	var texture: Texture2D = _texture(str(info.path))
	if texture == null or float(info.density) <= 0.0: return false
	var source: Rect2 = info.source
	if source.end.x > texture.get_width() or source.end.y > texture.get_height(): return false
	var factor: float = scale / float(info.density)
	ctx.canvas.draw_texture_rect_region(texture, Rect2(origin - Vector2(info.pivot) * factor, source.size * factor), source, Color.WHITE, false, true)
	ctx.n += 1
	ctx.nsprite = int(ctx.get("nsprite", 0)) + 1
	return true

static func draw_hull(ctx: Dictionary, spec: Dictionary) -> bool:
	if not ctx.canvas.has_method("draw_texture_rect_region"): return false
	# Legacy enlargement scales XY but deliberately leaves world heights alone.
	# A single bitmap cannot represent that anisotropic 3D operation accurately.
	if not is_equal_approx(float(ctx.get("enlargement", 1.0)), 1.0): return false
	var scale: float = _screen_scale(ctx)
	if scale <= 0.0: return false
	var info: Dictionary = frame_info(spec, float(ctx.angle), bool(ctx.get("portrait", false)) or scale > 2.0)
	if info.is_empty(): return false
	var entry: Dictionary = hull_entry(spec)
	if not is_equal_approx(float(spec.get("size", 0)), float(entry.get("size", 0))): return false
	return _draw_cell(ctx, info, ctx.proj.call(ctx.pos, 0.0), scale)

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
static func draw_weapon(ctx: Dictionary, mount: Dictionary, bearing: float) -> bool:
	if not bool(ctx.get("authored_hull", false)) or not ctx.canvas.has_method("draw_texture_rect_region"): return false
	if not ctx.canvas.has_method("draw_set_transform_matrix"): return false
	var manifest: Dictionary = _manifest(WEAPON_MANIFEST)
	if str(manifest.get("schema", "")) != "brass-tide-weapons042-v1": return false
	var entry: Dictionary = manifest.get("weapons", {}).get(weapon_variant(mount), {})
	if entry.is_empty(): return false
	var scale: float = _screen_scale(ctx)
	if scale <= 0.0: return false
	var tier: int = clampi(int(mount.get("size", 1)), 1, 3)
	var unit: float = Geometry.unit(float(ctx.hull_size), tier)
	var kind: String = str(mount.kind)
	var base: Dictionary = entry.get("base", {})
	var moving: Dictionary = entry.get("moving", {})
	var base_info: Dictionary = _frame(base, bearing)
	if _texture(str(base_info.path)) == null: return false
	var moving_info: Dictionary = _frame(moving, bearing) if not moving.is_empty() else {}
	if not moving_info.is_empty() and _texture(str(moving_info.path)) == null: return false
	var position: Vector2 = ctx.pos + Vector2(mount.x, mount.y).rotated(float(ctx.angle)) * float(ctx.size)
	var origin: Vector2 = ctx.proj.call(position, 9.7)
	var residual: float = wrapf(bearing - float(base_info.angle), -PI, PI)
	var transform: Transform2D = ISO * Transform2D(residual, Vector2.ZERO) * ISO.affine_inverse()
	# Correct the residual about the shared firing plane, keeping the actual
	# WeaponGeometry muzzle position exact even between baked directions.
	var muzzle_h: float = Geometry.height(kind, float(ctx.hull_size), tier) - 9.7
	if kind == "torpedo": muzzle_h = 2.8 * unit
	var plane: Vector2 = Vector2(0, -muzzle_h * scale)
	transform.origin = origin + plane - transform * plane
	ctx.canvas.draw_set_transform_matrix(transform)
	var drew: bool = _draw_cell(ctx, base_info, Vector2.ZERO, scale * unit)
	if not moving_info.is_empty():
		var age: float = float(ctx.get("shot_clock", 0.0)) - float(ctx.get("shots", {}).get(str(mount.get("id", "")), -100.0))
		var recoil: float = -1.1 * maxf(0.0, 1.0 - age / 0.16) if age >= 0.0 and age < 0.16 else 0.0
		# Offset is expressed in the baked frame before the residual transform.
		var xy: Vector2 = Vector2.from_angle(float(base_info.angle)) * recoil * unit
		var shift: Vector2 = Vector2((xy.x - xy.y) * 0.82, (xy.x + xy.y) * 0.41) * scale
		_draw_cell(ctx, moving_info, shift, scale * unit)
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
	_manifests.clear()
	_textures.clear()
