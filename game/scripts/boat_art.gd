extends RefCounted
## BoatArt: original code-drawn boat rendering for Brass Tide.
## Canvas-like and untyped on purpose: `canvas` is any object exposing
## draw_colored_polygon(PackedVector2Array, Color),
## draw_polyline(PackedVector2Array, Color, float),
## draw_line(Vector2, Vector2, Color, float) and
## draw_circle(Vector2, float, Color). A Node2D/Control in game, or the
## dummy recorder in tools/boat_gallery.gd under headless Godot.
## `projector` is a Callable(world_pos: Vector2, height: float) -> Vector2
## in canvas/screen coordinates. All geometry is built in boat-local units
## (x = bow, y = starboard, hull length ~3.8 units) scaled by spec.size.
## No fluid simulation, no animated crew: helm/gunner are static shapes.

const FOAM := Color(0.73, 0.87, 0.75, 1.0)
const WAKE_LIFE := 6.0
const HullProfiles=preload("res://scripts/hull_profiles.gd")
const Layout=preload("res://scripts/mount_layout.gd")
const WeaponArt = preload("res://scripts/weapon_art.gd")
const HullFeedback=preload("res://scripts/hull_feedback.gd")
const MotorArt=preload("res://scripts/motor_art.gd")
const MeshCache=preload("res://scripts/boat_mesh_cache.gd")
const DeckDetail=preload("res://scripts/boat_deck_detail.gd")
const SpriteArt=preload("res://scripts/boat_sprite_art.gd")
const WakeArt045=preload("res://scripts/wake_art045.gd")

static var _station_cache: Dictionary = {}
static var _audit_geometry: bool = "--qa-geometry" in OS.get_cmdline_user_args()
const DRAW_INPUT_LIMIT: int = 128
# Complete inputs to archetype(), palette() and mounts_of(), including the
# bare-hull Layout fallback. Presence matters as well as value/defaults.
const DRAW_INPUT_FIELDS := ["id", "role", "faction", "civilianRole", "armor", "size", "tier", "weapon", "weaponMounts"]
static var _draw_input_cache: Dictionary = {}

# Private to Chart's synchronous battle boat loop. The projector is constructed
# here from copied camera inputs, never supplied by opts or an arbitrary caller.
# No instance is retained by BoatArt or Chart beyond that one loop.
class _BattleDraw051 extends RefCounted:
	var view: Rect2
	var projector: Callable
	var sprite_scale: float
	var atlas_frames051: SpriteArt._BattleAtlas051
	var profile051: Dictionary = {}

	func _init(view_rect: Rect2, view_camera: Vector2, view_scale: float, owned_atlases051: bool = false) -> void:
		view = view_rect
		var view_origin: Vector2 = view_rect.size * 0.5
		projector = func(p: Vector2, h: float) -> Vector2:
			var d: Vector2 = p - view_camera
			return view_origin + Vector2((d.x - d.y) * 0.82, (d.x + d.y) * 0.41 - h) * view_scale
		# Nonpositive/nonfinite inputs retain the checked fallback as well.
		sprite_scale = view_scale if is_finite(view_scale) and view_scale > 0.0 else -1.0
		if owned_atlases051: atlas_frames051 = SpriteArt._BattleAtlas051.new()

# --- classification -------------------------------------------------------

static func archetype(spec: Dictionary) -> String:
	var role := str(spec.get("role", "skiff"))
	match role:
		"skiff":
			return "speedboat"
		"cutter":
			return "hydrofoil"
		"torpedo":
			return "hydrofoil"
		"raider":
			return "catamaran"
		"corvette":
			return "patrol"
		"gunboat":
			return "armored"
		"rocket":
			return "monitor"
		"cruiser":
			return "command"
		_:
			return "patrol"

static func _seed(spec: Dictionary) -> int:
	return absi(str(spec.get("id", "boat")).hash())

static func _stations(spec: Dictionary) -> Array:
	var key: String=str(spec.get("id",spec.get("role","boat")))
	if not _station_cache.has(key):_station_cache[key]=HullProfiles.stations(spec)
	return _station_cache[key]

const CAT_OFFSET := 0.62

static func _width_at(stations: Array, x: float) -> float:
	if stations.is_empty():
		return 0.0
	if x <= stations[0].x:
		return stations[0].y
	for i in range(stations.size() - 1):
		var a: Vector2 = stations[i]
		var b: Vector2 = stations[i + 1]
		if x <= b.x:
			var t := 0.0 if is_equal_approx(b.x, a.x) else (x - a.x) / (b.x - a.x)
			return lerpf(a.y, b.y, clampf(t, 0.0, 1.0))
	return stations[stations.size() - 1].y

static func _outline(stations: Array, y_offset: float = 0.0, shrink: float = 1.0, x_scale: float = 1.0) -> Array:
	var pts: Array = []
	for st in stations:
		pts.append(Vector2(st.x * x_scale, y_offset - st.y * shrink))
	for i in range(stations.size() - 1, -1, -1):
		var st: Vector2 = stations[i]
		var point=Vector2(st.x * x_scale,y_offset+st.y*shrink)
		if pts.is_empty() or pts[-1].distance_squared_to(point)>0.000001:pts.append(point)
	return pts

static func palette(spec: Dictionary, accent: Color, enemy: bool) -> Dictionary:
	var faction := str(spec.get("faction", "compact"))
	var side := Color("24383f")
	var top := Color("2f4a50")
	var deck := Color("8d8262")
	var cabin := Color("b9ac84")
	match faction:
		"forge":
			side = Color("3a2e28"); top = Color("4d3b30"); deck = Color("6e5a44"); cabin = Color("8a7154")
		"reed":
			side = Color("274036"); top = Color("33523f"); deck = Color("9a7c53"); cabin = Color("b39d6d")
		"raiders":
			side = Color("402c2c"); top = Color("523838"); deck = Color("7d6a55"); cabin = Color("97795c")
		_:  # compact
			side = Color("24383f"); top = Color("30505c"); deck = Color("8d8262"); cabin = Color("b9ac84")
	# Civilian trim belongs to these catalogue hulls; military palettes stay intact.
	match str(spec.get("civilianRole", "")):
		"fishing":
			top = Color("49634a"); deck = Color("aa885b"); cabin = Color("d0be91")
		"transport":
			top = Color("4b6262"); deck = Color("9e7950"); cabin = Color("cdc1a0")
		"tanker":
			side = Color("362f2c"); top = Color("715347"); deck = Color("87725e"); cabin = Color("c0b39a")
		"yacht":
			side = Color("24464b"); top = Color("dedbc6"); deck = Color("b79461"); cabin = Color("eee6ce")
	# Armored warboats use painted steel decks. Light craft retain timber and
	# civilian materials retain their own identity instead of every hull being brown.
	if str(spec.get("civilianRole", "")).is_empty() and int(spec.get("armor",0))>=10:
		deck=top.lightened(0.14)
		if int(spec.get("armor",0))>=18:cabin=top.lightened(0.34)
	if enemy:
		deck = deck.lerp(Color("8a5f4c"), 0.10)
		cabin = cabin.lerp(Color("a07a5e"), 0.08)
	return {
		"side": side, "top": top, "deck": deck, "deck_dark": deck.darkened(0.22),
		"seam": Color(0.08, 0.14, 0.16, 0.45), "plate": top.lightened(0.16),
		"plate2": top.lightened(0.05), "cabin": cabin, "roof": cabin.lightened(0.18),
		"glass": Color("79b7c4"), "glass_dark": Color("2d5560"),
		"metal": Color("39494d"), "metal_light": Color("c9c9a8"),
		"brass": Color("c8a35e"), "accent": accent,
		"shadow": Color(0.02, 0.11, 0.15, 0.55), "foam": FOAM,
		"ring": Color("e8e4d2"), "ring_red": Color("c45a3c"),
		"skin": Color("ddc6a0"), "cloth": Color("4a5a52"),
	}

# --- weapon mounts ----------------------------------------------------------

static func _mount_scale(raw) -> float:
	if raw is String:
		match str(raw).to_lower():
			"small", "s": return 0.8
			"medium", "m": return 1.0
			"large", "l": return 1.3
			_: return 1.0
	var v := float(raw) if (raw is int or raw is float) else 0.0
	if v <= 0.0:
		return 1.0
	if v <= 3.5:
		return clampf(0.65 + 0.25 * v, 0.7, 1.5)
	return 1.4

static func mounts_of(spec: Dictionary) -> Array:
	# Normalized mounts: {kind, x, y (boat-local units), angle (local rad), scale}
	var out: Array = []
	var fitted = spec.get("weaponMounts", [])
	var size := maxf(6.0, float(spec.get("size", 16)))
	if spec.has("weaponMounts") and fitted is Array:
		for m in fitted:
			if not (m is Dictionary):
				continue
			var kind := str(m.get("kind", "gun")).to_lower()
			if kind in ["mg", "machinegun", "machine_gun", "autocannon"]:
				kind = "gun"
			elif kind in ["shell", "howitzer"]:
				kind = "cannon"
			elif kind in ["missile", "rockets"]:
				kind = "rocket"
			elif kind in ["torpedoes", "tube"]:
				kind = "torpedo"
			if not kind in ["gun", "cannon", "rocket", "torpedo"]:
				kind = "gun"
			var mx := float(m.get("x", 0.6))
			var my := float(m.get("y", 0.0))
			# Refit/combat may author x,y in world units; local units are ~[-2.3, 2.3].
			mx /= size
			my /= size
			var raw_size=m.get("size",1)
			var tier: int=int(raw_size) if not raw_size is String else {"small":1,"medium":2,"large":3}.get(str(raw_size),1)
			out.append({"kind": kind, "x": clampf(mx, -2.2, 2.2), "y": clampf(my, -1.2, 1.2),
				"id":str(m.get("id","mount-%d"%out.size())),"moduleId":str(m.get("moduleId","")),"size":tier,
				"angle": float(m.get("angle", 0.0)), "scale": _mount_scale(raw_size)})
			if out.size() >= 6:
				break
		return out
	# Bare catalog hulls show precisely their original primary socket.
	var bare: Array=Layout.mounts_of(spec)
	for mount in bare:
		mount.size=int(Layout.hardpoints(spec)[0].size)
		mount.moduleId="stock_primary"
	return bare

# Private, read-only draw preparation. Public palette()/mounts_of() still
# return fresh values. Never retain a boat, condition, aim, shot or canvas here.
static func _same_draw_source(spec: Dictionary, source: Dictionary) -> bool:
	for field in DRAW_INPUT_FIELDS:
		if spec.has(field) != source.has(field) or spec.get(field) != source.get(field):
			return false
	return true

static func _draw_inputs(spec: Dictionary, accent: Color, enemy: bool) -> Dictionary:
	# Only immutable scalar values enter the dictionary key. Check the detached
	# source by value on EVERY hit, so editing a fit array in place is immediate.
	var key: Array = [str(spec.get("id", "")), accent, enemy]
	var cached = _draw_input_cache.get(key)
	if cached is Dictionary and _same_draw_source(spec, cached.source):
		return cached
	var source: Dictionary = {}
	for field in DRAW_INPUT_FIELDS:
		if spec.has(field): source[field] = spec[field]
	var colors: Dictionary = palette(spec, accent, enemy)
	var motor_colors: Dictionary = MotorArt._palette(colors, spec)
	var mounts: Array = mounts_of(spec)
	colors.make_read_only()
	motor_colors.make_read_only()
	for mount in mounts: mount.make_read_only()
	mounts.make_read_only()
	var prepared: Dictionary = {"source": source.duplicate(true), "archetype": archetype(spec), "palette": colors, "motor_palette": motor_colors, "mounts": mounts}
	prepared.make_read_only()
	if cached == null and _draw_input_cache.size() >= DRAW_INPUT_LIMIT:
		_draw_input_cache.clear()
	_draw_input_cache[key] = prepared
	return prepared

# --- canvas helpers (ctx carries canvas/projector/transform/counts) ---------

static func _pt(ctx: Dictionary, local: Vector2, h: float) -> Vector2:
	var world: Vector2 = ctx.pos + local.rotated(ctx.angle) * ctx.size
	var r = ctx.proj.call(world, h)
	return r if r is Vector2 else Vector2.ZERO

static func _poly(ctx: Dictionary, locals: Array, h: float, col: Color) -> void:
	if locals.size() < 3:
		return
	var pts := PackedVector2Array()
	for l in locals:
		pts.append(_pt(ctx, l, h))
	if _audit_geometry and Geometry2D.triangulate_polygon(pts).is_empty():
		push_error("BAD BOAT POLY angle %.5f height %.2f points %s"%[ctx.angle,h,str(pts)])
	ctx.canvas.draw_colored_polygon(pts, col)
	ctx.n = int(ctx.n) + 1
	ctx.npoly = int(ctx.npoly) + 1

static func _line(ctx: Dictionary, locals: Array, h: float, col: Color, width: float = 1.0, closed: bool = false) -> void:
	if locals.size() < 2:
		return
	var pts := PackedVector2Array()
	for l in locals:
		pts.append(_pt(ctx, l, h))
	if closed:
		pts.append(pts[0])
	ctx.canvas.draw_polyline(pts, col, width)
	ctx.n = int(ctx.n) + 1
	ctx.nline = int(ctx.nline) + 1

static func _seg(ctx: Dictionary, a: Vector2, b: Vector2, h: float, col: Color, width: float = 1.0) -> void:
	ctx.canvas.draw_line(_pt(ctx, a, h), _pt(ctx, b, h), col, width)
	ctx.n = int(ctx.n) + 1
	ctx.nline = int(ctx.nline) + 1

static func _circ(ctx: Dictionary, local: Vector2, h: float, r_units: float, col: Color) -> void:
	ctx.canvas.draw_circle(_pt(ctx, local, h), maxf(0.8, r_units * float(ctx.px)), col)
	ctx.n = int(ctx.n) + 1
	ctx.ncirc = int(ctx.ncirc) + 1

static func _rect(ctx: Dictionary, cx: float, cy: float, len_: float, wid: float, h: float, col: Color, rot: float = 0.0) -> void:
	var c := Vector2(cx, cy)
	var pts: Array = []
	for o in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		pts.append(c + (o * Vector2(len_, wid)).rotated(rot))
	_poly(ctx, pts, h, col)

static func _wline(ctx: Dictionary) -> float:
	# A ~1.2px screen line at current scale, never hairline-invisible.
	return maxf(1.0, float(ctx.px) * 0.05)

# --- hull construction ------------------------------------------------------

static func _one_hull(ctx: Dictionary, stations: Array, y_off: float, c: Dictionary, lift: float = 0.0) -> void:
	var lod := int(ctx.lod)
	# One solid hull: opaque faces connect the water contact to its upper rim.
	# There is no displaced shadow, reflection or complete foam outline below it.
	var contact: Array=_outline(stations,y_off)
	var rim: Array=_outline(stations,y_off,0.97,0.99)
	_poly(ctx,contact,0.0,c.side)
	for i in range(contact.size()):
		var j: int=(i+1)%contact.size()
		var points=PackedVector2Array([_pt(ctx,contact[i],0.0),_pt(ctx,contact[j],0.0),_pt(ctx,rim[j],6.5+lift),_pt(ctx,rim[i],6.5+lift)])
		# A consistent world-space light separates the sheer faces as a boat turns.
		# This is baked into the existing heading mesh; no live lighting pass.
		var edge: Vector2=(contact[j]-contact[i]).rotated(float(ctx.angle))
		var normal: Vector2=Vector2(edge.y,-edge.x).normalized()
		var sun: float=normal.dot(Vector2(-0.55,-0.83))
		var face: Color=c.side.lightened(maxf(0.0,sun)*0.18).darkened(maxf(0.0,-sun)*0.20)
		for triangle in [[points[0],points[1],points[2]],[points[0],points[2],points[3]]]:
			# The two bow-tip stations coincide; omit zero-area faces at every heading.
			if absf((triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]))<1.0:continue
			ctx.canvas.draw_colored_polygon(PackedVector2Array(triangle),face)
			ctx.n+=1;ctx.npoly+=1
	_poly(ctx, _outline(stations, y_off, 0.97, 0.99), 6.5 + lift, c.top)
	_line(ctx, _outline(stations, y_off, 0.97, 0.99), 7.0 + lift, Color(c.accent, 0.85), _wline(ctx) * 1.5, true)
	_poly(ctx, _outline(stations, y_off, 0.84, 0.94), 9.0 + lift, c.deck)
	if lod >= 2:
		return
	DeckDetail.planking(ctx,stations,y_off,lift,c)

static func _armor_plates(ctx: Dictionary, stations: Array, c: Dictionary, lift: float = 0.0) -> void:
	# Segmented side plates with seams; rivet dots at corners on full detail.
	var lod := int(ctx.lod)
	for side in [-1.0, 1.0]:
		for i in range(stations.size() - 1):
			var a: Vector2 = stations[i]
			var b: Vector2 = stations[i + 1]
			if a.y < 0.2 or b.y < 0.2:
				continue
			var quad: Array = [
				Vector2(a.x * 0.99, side * a.y * 0.80), Vector2(b.x * 0.99, side * b.y * 0.80),
				Vector2(b.x * 0.99, side * b.y * 0.96), Vector2(a.x * 0.99, side * a.y * 0.96)]
			_poly(ctx, quad, 7.6 + lift, c.plate if i % 2 == 0 else c.plate2)
			_seg(ctx, quad[0], quad[3], 7.8 + lift, c.seam, _wline(ctx) * 0.8)
			if lod == 0:
				for q in [quad[0], quad[1]]:
					_circ(ctx, Vector2(q.x, q.y * 1.06), 8.0 + lift, 0.028, c.metal_light)

static func _rivet_row(ctx: Dictionary, stations: Array, c: Dictionary, y_off: float = 0.0) -> void:
	if int(ctx.lod) != 0:
		return
	for side in [-1.0, 1.0]:
		var x: float = stations[0].x + 0.15
		while x < stations[stations.size() - 1].x - 0.25:
			var w := _width_at(stations, x)
			if w > 0.12:
				_circ(ctx, Vector2(x, y_off + side * w * 0.92), 7.4, 0.024, Color(c.metal_light, 0.8))
			x += 0.34

static func _rails(ctx: Dictionary, stations: Array, c: Dictionary, y_off: float = 0.0, lift: float = 0.0) -> void:
	if int(ctx.lod) >= 2:
		return
	for side in [-1.0, 1.0]:
		var pts: Array = []
		for st in stations:
			if st.x > -0.4:
				pts.append(Vector2(st.x * 0.96, y_off + side * st.y * 0.90))
		_line(ctx, pts, 13.0 + lift, Color(c.metal_light, 0.75), _wline(ctx))
		if int(ctx.lod) == 0:
			for p in pts:
				_circ(ctx, Vector2(p.x, p.y), 10.0 + lift, 0.022, Color(c.metal_light, 0.8))

static func _cabin(ctx: Dictionary, cx: float, cy: float, len_: float, wid: float, c: Dictionary, h_top: float = 20.0, glass: bool = true) -> void:
	_rect(ctx, cx, cy, len_ * 1.06, wid * 1.10, h_top - 5.0, Color(c.cabin).darkened(0.25))
	_rect(ctx, cx, cy, len_, wid, h_top - 2.0, c.cabin)
	if glass and int(ctx.lod) < 2:
		# Forward glazing band with mullions and a darker side window strip.
		_rect(ctx, cx + len_ * 0.30, cy, len_ * 0.34, wid * 0.86, h_top - 1.0, c.glass)
		_rect(ctx, cx + len_ * 0.30, cy, len_ * 0.34, wid * 0.30, h_top - 0.6, c.glass_dark)
		for i in range(-1, 2):
			_seg(ctx, Vector2(cx + len_ * (0.30 + i * 0.11), cy - wid * 0.43),
				Vector2(cx + len_ * (0.30 + i * 0.11), cy + wid * 0.43), h_top - 0.4, Color(c.metal, 0.8), _wline(ctx) * 0.8)
	_rect(ctx, cx - len_ * 0.08, cy, len_ * 0.72, wid * 0.88, h_top, c.roof)
	_seg(ctx, Vector2(cx - len_ * 0.42, cy), Vector2(cx + len_ * 0.26, cy), h_top + 0.3, Color(c.seam, 0.6), _wline(ctx) * 0.8)

static func _figure(ctx: Dictionary, at: Vector2, c: Dictionary, h: float = 14.0) -> void:
	# Static helm/gunner: torso lozenge + head. Never animated.
	if int(ctx.lod) >= 2:
		return
	_poly(ctx, [at + Vector2(-0.09, -0.06), at + Vector2(0.09, -0.06), at + Vector2(0.07, 0.07), at + Vector2(-0.07, 0.07)], h, c.cloth)
	_circ(ctx, at, h + 3.0, 0.055, c.skin)

static func _vents(ctx: Dictionary, cx: float, cy: float, c: Dictionary, slats: int = 4) -> void:
	if int(ctx.lod) >= 2:
		return
	_rect(ctx, cx, cy, 0.42, 0.30, 11.5, c.metal)
	for i in range(slats):
		var x := cx - 0.16 + i * (0.32 / maxf(1.0, float(slats - 1)))
		_seg(ctx, Vector2(x, cy - 0.12), Vector2(x, cy + 0.12), 12.0, Color(c.metal_light, 0.65), _wline(ctx) * 0.8)

static func _stack(ctx: Dictionary, at: Vector2, c: Dictionary, r: float = 0.10) -> void:
	_circ(ctx, at, 16.0, r, c.metal)
	_circ(ctx, at, 19.0, r * 0.72, Color(0.05, 0.07, 0.08, 1.0))
	_circ(ctx, at, 19.5, r * 0.30, Color(c.brass, 0.9))

static func _life_ring(ctx: Dictionary, at: Vector2, c: Dictionary) -> void:
	if int(ctx.lod) != 0:
		return
	_circ(ctx, at, 15.0, 0.085, c.ring)
	_circ(ctx, at, 15.4, 0.050, c.ring_red)
	_circ(ctx, at, 15.8, 0.030, c.cabin)

static func _rope_coil(ctx: Dictionary, at: Vector2, c: Dictionary) -> void:
	if int(ctx.lod) != 0:
		return
	_circ(ctx, at, 9.8, 0.10, Color("a68d5f"))
	_circ(ctx, at, 10.1, 0.065, Color("8a714a"))
	_circ(ctx, at, 10.4, 0.032, c.deck)

static func _mast(ctx: Dictionary, at: Vector2, c: Dictionary, top_h: float = 44.0, pennant: bool = true) -> void:
	if int(ctx.lod) >= 2:
		return
	var top_screen := _pt(ctx, at, top_h)
	ctx.canvas.draw_line(_pt(ctx, at, 12.0), top_screen, Color(c.metal_light, 0.9), _wline(ctx) * 1.1)
	ctx.n = int(ctx.n) + 1
	ctx.nline = int(ctx.nline) + 1
	_circ(ctx, at, top_h, 0.035, c.brass)
	if pennant:
		ctx.canvas.draw_colored_polygon(PackedVector2Array([
			top_screen, top_screen + Vector2(0.34, 0.06) * float(ctx.px), top_screen + Vector2(0.0, 0.13) * float(ctx.px)]), Color(c.accent, 0.95))
		ctx.n = int(ctx.n) + 1
		ctx.npoly = int(ctx.npoly) + 1

static func _superstructure(ctx: Dictionary, _arch: String, spec: Dictionary, c: Dictionary) -> void:
	var plan: Dictionary=Layout.structure(spec)
	var cabin: Dictionary=plan.cabin
	var identity: Dictionary=HullProfiles.profile(spec)
	cabin.height=float(identity.bridge.get("h",cabin.height))
	var engine: Dictionary=plan.engine
	var box_model: Dictionary={"ctx":ctx,"at":Vector2(engine.x,engine.y),"bearing":0.0,"u":1.0/float(ctx.size),"world_unit":1.0,"lod":ctx.lod,"h":0.0}
	WeaponArt._box(box_model,Vector3(-engine.length*ctx.size*0.5,-engine.width*ctx.size*0.5,9.6),Vector3(engine.length*ctx.size*0.5,engine.width*ctx.size*0.5,engine.height),c.metal)
	for vent in plan.vents:
		_rect(ctx,vent.x,vent.y,vent.length,vent.width,engine.height+0.3,c.metal)
		if int(ctx.lod)<2:
			for i in range(int(vent.slats)):
				var x: float=float(vent.x)-float(vent.length)*0.4+i*float(vent.length)*0.8/maxf(1.0,float(vent.slats)-1.0)
				_seg(ctx,Vector2(x,vent.y-vent.width*0.4),Vector2(x,vent.y+vent.width*0.4),engine.height+0.6,c.metal_light,0.8)
	for stack in plan.stacks:_stack(ctx,Vector2(stack.x,stack.y),c,stack.radius)
	DeckDetail.cabin(ctx,cabin,identity,c)
	if cabin.style=="cockpit" and not identity.bridge.glass:
		_figure(ctx,Vector2(plan.helm.x,plan.helm.y),c,13.0)
	if cabin.style=="command_tower":
		var upper: Dictionary=cabin.duplicate(true)
		upper.x=float(cabin.x)-0.04;upper.length=cabin.upperLength;upper.width=cabin.upperWidth
		upper.baseHeight=float(cabin.height)-2.0;upper.height=cabin.upperHeight
		DeckDetail.cabin(ctx,upper,identity,c)
		if "pagoda" in str(identity.bridgeStyle):
			upper.baseHeight=float(upper.height)-2.0;upper.height=float(upper.height)+3.0
			upper.length=float(upper.length)*0.65;upper.width=float(upper.width)*0.72
			DeckDetail.cabin(ctx,upper,identity,c)
	_deck_details(ctx,spec,identity,c)
	for mast in plan.masts:
		var top: float=maxf(cabin.height+(18.0 if "pagoda" in str(identity.bridgeStyle) else 8.0),minf(float(mast.height),14.0+float(spec.size)*0.65))
		_mast(ctx,Vector2(mast.x,mast.y),c,top,mast.pennant)
	if int(ctx.lod)==0:
		_life_ring(ctx,Vector2(cabin.x,-cabin.width*0.65),c)
		_life_ring(ctx,Vector2(cabin.x,cabin.width*0.65),c)

static func _deck_details(ctx: Dictionary,spec: Dictionary,identity: Dictionary,c: Dictionary) -> void:
	# Kept as a forwarding entry point for existing drawing callers.
	DeckDetail.draw_items(ctx,spec,c)

static func _draw_mount(ctx: Dictionary, m: Dictionary, turret_world: float, c: Dictionary) -> void:
	WeaponArt.draw(ctx,m,turret_world,c)

# --- main entry ---------------------------------------------------------------
## opts: accent:Color, enemy:bool, lod:int 0..2, clock:float,
## px:float (screen pixels per boat-local unit, for circles/line widths),
## enlargement:float. Returns primitive counts + classification for QA.
static func draw_boat(canvas, projector: Callable, boat: Dictionary, opts: Dictionary = {}) -> Dictionary:
	return _draw_boat051(canvas, projector, boat, opts, -1.0)

static func _draw_battle_boat051(canvas, batch: _BattleDraw051, boat: Dictionary, opts: Dictionary) -> Dictionary:
	# Chart opts in only for its uninterrupted native boat loop. Recorders keep
	# every metadata check even if handed an opted-in batch by a fixture/caller.
	return _draw_boat051(canvas, batch.projector, boat, opts, batch.sprite_scale, batch.atlas_frames051 if canvas is CanvasItem else null, batch.profile051)

static func _draw_boat051(canvas, projector: Callable, boat: Dictionary, opts: Dictionary, battle_scale051: float, atlas_frames051: SpriteArt._BattleAtlas051 = null, profile051: Dictionary = {}) -> Dictionary:
	var profile_enabled051: bool = not profile051.is_empty()
	var phase_started051: int = Time.get_ticks_usec() if profile_enabled051 else 0
	var spec_v = boat.get("spec", {})
	var spec: Dictionary = spec_v if spec_v is Dictionary else {}
	var accent: Color = opts.get("accent", Color("8fc6b4")) if opts.get("accent") is Color else Color("8fc6b4")
	var prepared: Dictionary = _draw_inputs(spec, accent, bool(opts.get("enemy", false)))
	var arch: String = prepared.archetype
	var c: Dictionary = prepared.palette
	var enlargement := float(opts.get("enlargement", 1.0))
	var vel := Vector2(float(boat.get("vx", 0.0)), float(boat.get("vy", 0.0)))
	var ctx: Dictionary = {
		"canvas": canvas, "proj": projector,
		"pos": Vector2(float(boat.get("x", 0.0)), float(boat.get("y", 0.0))),
		"angle": float(boat.get("angle", 0.0)),
		"size": maxf(4.0, float(spec.get("size", 16))) * enlargement,
		"hull_size":float(spec.get("size",16)),"enlargement":enlargement,
		"px": maxf(2.0, float(opts.get("px", 12.0))),
		"lod": clampi(int(opts.get("lod", 0)), 0, 2),
		"clock": float(opts.get("clock",boat.get("battleTime",0.0))), "speed": vel.length(),
		"shot_clock":float(opts.get("battle_clock",boat.get("battleTime",0.0))),
		"combat":bool(opts.get("combat",boat.has("battleTime"))),
		"portrait":bool(opts.get("portrait",false)),
		"shots":boat.get("mountShotTimes",{}) if bool(opts.get("combat",boat.has("battleTime"))) else {},"localAimAngles":boat.get("localAimAngles",{}),
		"n": 0, "npoly": 0, "nline": 0, "ncirc": 0,
	}
	var stations := _stations(spec)
	var mounts: Array = prepared.mounts
	# Only the private, constructed affine battle projector shares scale across
	# boats. Public/default/custom projectors still test their actual local basis.
	var sprite_scale: float = 0.0
	if is_equal_approx(enlargement, 1.0) and canvas.has_method("draw_texture_rect_region") and canvas.has_method("draw_set_transform_matrix"):
		sprite_scale = SpriteArt._screen_scale(ctx) if battle_scale051 < 0.0 else battle_scale051
	if profile_enabled051:
		profile051.boat_prepare_us += Time.get_ticks_usec() - phase_started051
		phase_started051 = Time.get_ticks_usec()
	ctx.authored_hull=SpriteArt._draw_hull051(ctx,spec,sprite_scale,atlas_frames051)
	if profile_enabled051:
		profile051.boat_hull_us += Time.get_ticks_usec() - phase_started051
		phase_started051 = Time.get_ticks_usec()
	if bool(ctx.authored_hull):
		MotorArt.draw_motion(ctx,spec,boat,c,prepared.motor_palette)
	elif bool(opts.get("cache",false)) and (canvas is CanvasItem or canvas.has_method("draw_mesh")):
		_cached_base(ctx,spec,boat,c,arch)
		MotorArt.draw_motion(ctx,spec,boat,c,prepared.motor_palette)
	else:_static(ctx,spec,boat,c,arch)
	if profile_enabled051:
		profile051.boat_motor_us += Time.get_ticks_usec() - phase_started051
		phase_started051 = Time.get_ticks_usec()
	for m in mounts:
		var local_bearing: float=float(ctx.localAimAngles.get(str(m.get("id","mount0")),m.angle))
		if SpriteArt._draw_weapon051(ctx,m,float(ctx.angle)+local_bearing,sprite_scale,atlas_frames051):continue
		if bool(opts.get("cache",false)) and (canvas is CanvasItem or canvas.has_method("draw_mesh")):_cached_weapon(ctx,m,float(ctx.angle)+local_bearing,c)
		else:_draw_mount(ctx,m,float(ctx.angle)+local_bearing,c)
	if profile_enabled051:
		profile051.boat_weapons_us += Time.get_ticks_usec() - phase_started051
		phase_started051 = Time.get_ticks_usec()
	_damage(ctx, boat, stations, arch, c)
	HullFeedback.draw_equipment(ctx,boat,mounts)
	if profile_enabled051:
		profile051.boat_damage_us += Time.get_ticks_usec() - phase_started051
	return {"primitives": int(ctx.n), "polygons": int(ctx.npoly), "lines": int(ctx.nline),
		"circles": int(ctx.ncirc), "archetype": arch, "mounts": mounts.size(), "lod": int(ctx.lod),
		"authored_hull":bool(ctx.authored_hull),"sprites":int(ctx.get("nsprite",0))}

static func _cached_base(ctx: Dictionary,spec: Dictionary,boat: Dictionary,c: Dictionary,arch: String) -> void:
	var engine_id: String=MotorArt._engine_id(spec,boat)
	var density: float=MeshCache.density(ctx.proj,ctx.pos)
	var key: String="hull:%s:%.2f:%d:%s:%s:%s:%s"%[str(spec.get("id","boat")),float(ctx.size),int(ctx.lod),engine_id,c.deck.to_html(),c.cabin.to_html(),c.accent.to_html()]
	key+=":density%.3f"%density
	var bake=func(rec,angle: float):
		var context: Dictionary=ctx.duplicate()
		context.canvas=rec;context.pos=Vector2.ZERO;context.angle=angle
		context.proj=func(p: Vector2,h: float):return Vector2((p.x-p.y)*0.82,(p.x+p.y)*0.41-h)*density
		context.px=context.size*0.82*density;context.clock=0.0;context.speed=0.0
		var frozen: Dictionary=boat.duplicate();frozen.engine=1.0;frozen.fuel=0.0;frozen.vx=0.0;frozen.vy=0.0
		_static(context,spec,frozen,c,arch)
	MeshCache.draw(ctx.canvas,ctx.proj,ctx.pos,ctx.angle,key,bake,0.0,density)
	ctx.n+=1

static func _cached_weapon(ctx: Dictionary,mount: Dictionary,bearing: float,c: Dictionary) -> void:
	var id: String=str(mount.get("id","mount0"))
	var age: float=float(ctx.shot_clock)-float(ctx.shots.get(id,-100.0))
	var phase: int=clampi(int(age/0.04),0,4) if age>=0.0 and age<0.16 else 4
	var density: float=MeshCache.density(ctx.proj,ctx.pos)
	var key: String="weapon:%s:%s:%d:%.2f:%.2f:%d:%d:%s:%s"%[mount.kind,str(mount.get("moduleId","")),int(mount.get("size",1)),float(ctx.hull_size),float(ctx.enlargement),int(ctx.lod),phase,c.top.to_html(),c.brass.to_html()]
	key+=":density%.3f"%density
	var bake=func(rec,angle: float):
		var context: Dictionary=ctx.duplicate()
		context.canvas=rec;context.pos=Vector2.ZERO;context.angle=0.0
		context.proj=func(p: Vector2,h: float):return Vector2((p.x-p.y)*0.82,(p.x+p.y)*0.41-h)*density
		context.px=context.size*0.82*density;context.shot_clock=phase*0.04;context.shots={id:0.0}
		var centered: Dictionary=mount.duplicate();centered.x=0.0;centered.y=0.0
		_draw_mount(context,centered,angle,c)
	var position: Vector2=ctx.pos+Vector2(mount.x,mount.y).rotated(ctx.angle)*float(ctx.size)
	var firing_height: float=WeaponArt.Geometry.height(str(mount.kind),float(ctx.hull_size),int(mount.get("size",1)))
	MeshCache.draw(ctx.canvas,ctx.proj,position,bearing,key,bake,firing_height,density)
	ctx.n+=1

static func _static(ctx: Dictionary,spec: Dictionary,boat: Dictionary,c: Dictionary,arch: String) -> void:
	var stations := _stations(spec)
	var lift := 0.0 # Solid water contact; foil silhouette remains, with no duplicated hull outline.
	if arch == "catamaran":
		_one_hull(ctx, stations, -CAT_OFFSET, c)
		_one_hull(ctx, stations, CAT_OFFSET, c)
		# Bridge deck joining the demi-hulls, with its own plank seams.
		_poly(ctx, [Vector2(-1.80, -CAT_OFFSET), Vector2(1.45, -CAT_OFFSET),
			Vector2(1.45, CAT_OFFSET), Vector2(-1.80, CAT_OFFSET)], 9.5, c.deck)
		if int(ctx.lod) < 2:
			for i in range(1, 7):
				var x := lerpf(-1.80, 1.45, float(i) / 7.0)
				_seg(ctx, Vector2(x, -CAT_OFFSET), Vector2(x, CAT_OFFSET), 9.9, c.seam, _wline(ctx) * 0.8)
		_rivet_row(ctx, stations, c, -CAT_OFFSET)
		_rivet_row(ctx, stations, c, CAT_OFFSET)
	else:
		_one_hull(ctx, stations, 0.0, c, lift)
		if (arch in ["armored", "monitor", "command"] and str(spec.get("civilianRole", "")).is_empty()) or int(spec.get("armor", 0)) >= 10:
			_armor_plates(ctx, stations, c, lift)
		else:
			_rivet_row(ctx, stations, c)
		if arch == "hydrofoil":
			# Foil wings at water level with angled struts up to the lifted hull.
			for fx in [1.05, -1.25]:
				var span := 0.95 if fx > 0.0 else 0.80
				_poly(ctx, [Vector2(fx - 0.16, -span), Vector2(fx + 0.22, 0.0), Vector2(fx - 0.16, span),
					Vector2(fx - 0.30, 0.0)], -3.0, Color(c.metal, 0.9))
				for s in [-1.0, 1.0]:
					_seg(ctx, Vector2(fx - 0.05, s * span * 0.62), Vector2(fx, s * 0.30), 2.0, c.metal_light, _wline(ctx) * 1.6)
					if float(ctx.speed) > 8.0 and int(ctx.lod) < 2:
						_circ(ctx, Vector2(fx - 0.12, s * span * 0.62), -1.0, 0.07, Color(c.foam, 0.6))
	DeckDetail.rails(ctx,spec,c)
	_superstructure(ctx, arch, spec, c)
	MotorArt.draw(ctx,spec,boat,c)
	for socket in Layout.hardpoints(spec):
		var at=Vector2(socket.localX,socket.localY)
		_rect(ctx,at.x,at.y,socket.footprintRadius*1.65,socket.footprintRadius*1.65,10.0,c.metal)
		if int(ctx.lod)==0:
			_line(ctx,[at+Vector2(-0.1,-0.1),at+Vector2(0.1,-0.1),at+Vector2(0.1,0.1)],10.4,c.brass,0.8)

static func _damage(ctx: Dictionary, boat: Dictionary, stations: Array, arch: String, c: Dictionary) -> void:
	HullFeedback.draw(ctx,boat,stations)
	var water := float(boat.get("water", 0.0))
	if water > 0.0:
		var flood := clampf(water / maxf(1.0, float(boat.get("capacity", 100.0))), 0.0, 1.0)
		if arch == "catamaran":
			_poly(ctx, _outline(stations, -CAT_OFFSET, 0.7, 0.9), 9.7, Color(0.19, 0.57, 0.66, flood * 0.55))
			_poly(ctx, _outline(stations, CAT_OFFSET, 0.7, 0.9), 9.7, Color(0.19, 0.57, 0.66, flood * 0.55))
		else:
			_poly(ctx, _outline(stations, 0.0, 0.72, 0.9), 9.7, Color(0.19, 0.57, 0.66, flood * 0.55))

# --- wakes, trails, projectiles (world-space, same canvas/projector) ---------

static func _wpt(projector: Callable, p: Vector2, h: float) -> Vector2:
	var r = projector.call(p, h)
	return r if r is Vector2 else Vector2.ZERO

## Stern wash follows the recorded travel path; no reflected hull or fake rail.
static func draw_wake(canvas, projector: Callable, samples: Array, opts: Dictionary = {}) -> int:
	return WakeArt045.draw(canvas,projector,samples,opts)

## points: [{p:Vector2, age:float, life:float}] fading dots for torpedo foam
## or rocket smoke. Caller caps the array; oldest are skipped past life.
static func draw_trail(canvas, projector: Callable, points: Array, kind: String, opts: Dictionary = {}) -> int:
	var n := 0
	var px := float(opts.get("px", 10.0))
	for s in points:
		if not (s is Dictionary):
			continue
		var life := maxf(0.05, float(s.get("life", 1.0)))
		var t := clampf(float(s.get("age", 0.0)) / life, 0.0, 1.0)
		if t >= 1.0:
			continue
		var p: Vector2 = s.get("p", Vector2.ZERO)
		if kind == "torpedo":
			canvas.draw_circle(_wpt(projector, p, -1.0), maxf(1.0, px * 0.16 * (0.5 + t)), Color(0.75, 0.90, 0.84, 0.30 * (1.0 - t)))
		else:  # rocket smoke
			canvas.draw_circle(_wpt(projector, p, 12.0), maxf(1.0, px * 0.20 * (0.4 + t * 1.3)), Color(0.72, 0.70, 0.64, 0.28 * (1.0 - t)))
		n += 1
	return n

## One projectile, visually distinct per family. shot uses battle fields
## {x,y,px,py,kind,team}; kind bullet|shell|rocket|torpedo (gun/cannon map too).
static func draw_projectile(canvas, projector: Callable, shot: Dictionary, opts: Dictionary = {}) -> int:
	var kind := str(shot.get("kind", "bullet")).to_lower()
	if kind == "gun":
		kind = "bullet"
	elif kind == "cannon":
		kind = "shell"
	var shot_height: float=float(shot.get("height",0.0 if kind=="torpedo" else 9.0))
	var a := _wpt(projector, Vector2(float(shot.get("px", shot.get("x", 0.0))), float(shot.get("py", shot.get("y", 0.0)))), shot_height)
	var b := _wpt(projector, Vector2(float(shot.get("x", 0.0)), float(shot.get("y", 0.0))), shot_height)
	var dir := (b - a)
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var friendly := str(shot.get("team", "player")) != "enemy"
	var n := 0
	match kind:
		"torpedo":
			var col := Color("9bdcc5")
			canvas.draw_line(b - dir * 14.0, b, Color(col, 0.35), 5.0)
			canvas.draw_line(b - dir * 11.0, b, col, 3.0)
			canvas.draw_circle(b, 2.6, Color("e6f4e9"))
			n = 3
		"rocket":
			var body := Color("e8c98a") if friendly else Color("e8947a")
			canvas.draw_line(b - dir * 10.0, b, body, 3.4)
			canvas.draw_circle(b - dir * 11.0, 3.2, Color(1.0, 0.62, 0.25, 0.9))
			canvas.draw_circle(b, 2.0, Color("fff2cf"))
			n = 3
		"shell":
			var col2 := Color("ffe2a6") if friendly else Color("e8947a")
			canvas.draw_line(b - dir * 8.0, b, Color(col2, 0.45), 4.2)
			canvas.draw_line(b - dir * 6.0, b, col2, 2.4)
			canvas.draw_circle(b, 2.2, col2)
			n = 3
		_:  # bullet tracer
			var col3 := Color("ffeec2") if friendly else Color("f0a58c")
			canvas.draw_line(b - dir * 6.0, b, Color(col3, 0.5), 2.2)
			canvas.draw_line(b - dir * 4.0, b, col3, 1.3)
			n = 2
	return n

## Stern world position for a boat dict, shared by chart wake recording.
static func stern_of(boat: Dictionary) -> Vector2:
	var spec_v = boat.get("spec", {})
	var size := maxf(4.0, float(spec_v.get("size", 16))) if spec_v is Dictionary else 16.0
	var angle := float(boat.get("angle", 0.0))
	# The wake begins aft of the actual profile and drive, including long civilians.
	var aft: float=float(MotorArt._plan(spec_v,boat).minX)-0.08 if spec_v is Dictionary else -2.2
	return Vector2(float(boat.get("x", 0.0)), float(boat.get("y", 0.0))) + Vector2(aft, 0.0).rotated(angle) * size

## A ready-made display boat for portraits/galleries without a live campaign.
static func preview_boat(spec: Dictionary, angle: float = -0.45) -> Dictionary:
	return {"spec": spec, "x": 0.0, "y": 0.0, "angle": angle, "turretAngle": angle + 0.35,
		"vx": 0.0, "vy": 0.0, "water": 0.0, "fire": 0.0, "breaches": [], "capacity": 100.0}




