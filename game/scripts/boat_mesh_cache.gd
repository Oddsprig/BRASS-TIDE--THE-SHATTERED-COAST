extends RefCounted
## Static boat geometry becomes one colored mesh. Bounded, main-thread and texture-free.
const STEPS: int=64
const LIMIT: int=512
const ISO:=Transform2D(Vector2(0.82,0.41),Vector2(-0.82,0.41),Vector2.ZERO)
static var _meshes: Dictionary={}
static var _order: Array=[]
static var hits: int=0
static var misses: int=0
static var _profile_enabled: bool=false
static var _profile_hits: int=0
static var _profile_misses: int=0
static var _profile_build_us: int=0
static var _profile_build_max_us: int=0
static var _profile_evictions: int=0
static var _profile_clears: int=0

## Main-thread, opt-in CPU counters. Reset never evicts or warms geometry.
static func profile_enable(enabled: bool=true) -> void:
	_profile_enabled=enabled

static func profile_reset() -> void:
	_profile_hits=0;_profile_misses=0;_profile_build_us=0
	_profile_build_max_us=0;_profile_evictions=0;_profile_clears=0

static func profile_read() -> Dictionary:
	return {"enabled":_profile_enabled,"hits":_profile_hits,"misses":_profile_misses,
		"build_us":_profile_build_us,"build_max_us":_profile_build_max_us,
		"evictions":_profile_evictions,"clears":_profile_clears,"entries":_meshes.size()}

class Capture extends RefCounted:
	var vertices:=PackedVector3Array()
	var colors:=PackedColorArray()
	var reference_scale: float=1.0
	func _triangle(a: Vector2,b: Vector2,c: Vector2,color: Color) -> void:
		if absf((b-a).cross(c-a))<0.00001:return
		a/=reference_scale;b/=reference_scale;c/=reference_scale
		vertices.append(Vector3(a.x,a.y,0));vertices.append(Vector3(b.x,b.y,0));vertices.append(Vector3(c.x,c.y,0))
		colors.append(color);colors.append(color);colors.append(color)
	func draw_colored_polygon(p: PackedVector2Array,c: Color) -> void:
		var indices: PackedInt32Array=Geometry2D.triangulate_polygon(p)
		for i in range(0,indices.size(),3):_triangle(p[indices[i]],p[indices[i+1]],p[indices[i+2]],c)
	func draw_line(a: Vector2,b: Vector2,c: Color,w: float=-1,_aa: bool=false) -> void:
		var offset: Vector2=(b-a).normalized().orthogonal()*maxf(0.5,w)*0.5
		_triangle(a-offset,b-offset,b+offset,c);_triangle(a-offset,b+offset,a+offset,c)
	func draw_polyline(p: PackedVector2Array,c: Color,w: float=-1,_aa: bool=false) -> void:
		for i in range(p.size()-1):draw_line(p[i],p[i+1],c,w)
	func draw_circle(p: Vector2,r: float,c: Color) -> void:
		for i in range(10):_triangle(p,p+Vector2.from_angle(i*TAU/10.0)*r,p+Vector2.from_angle((i+1)*TAU/10.0)*r,c)
	func mesh() -> ArrayMesh:
		# An intentionally empty bake has no RenderingServer mesh RID. Caching
		# an empty ArrayMesh and drawing it caused Vulkan null-mesh errors.
		if vertices.is_empty():return null
		var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors
		var result:=ArrayMesh.new()
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		return result

static func heading(angle: float) -> float:return roundf(angle/TAU*STEPS)*TAU/STEPS

static func density(projector: Callable,position: Vector2) -> float:
	var origin: Vector2=projector.call(position,0.0)
	var scale: float=(projector.call(position+Vector2(1,0),0.0)-origin).length()/Vector2(0.82,0.41).length()
	return pow(2.0,roundf(log(maxf(0.0625,scale))/log(2.0)))

static func draw(canvas,projector: Callable,position: Vector2,angle: float,key: String,bake: Callable,pivot_height: float=0.0,reference_scale: float=1.0) -> void:
	var quantized: float=heading(angle)
	var full_key: String=key+":%d"%posmod(int(roundf(angle/TAU*STEPS)),STEPS)
	if not _meshes.has(full_key):
		misses+=1
		var build_started: int=Time.get_ticks_usec() if _profile_enabled else 0
		var capture:=Capture.new()
		capture.reference_scale=reference_scale
		bake.call(capture,quantized)
		if _meshes.size()>=LIMIT:
			_meshes.erase(_order.pop_front())
			if _profile_enabled:_profile_evictions+=1
		_meshes[full_key]=capture.mesh();_order.append(full_key)
		if _profile_enabled:
			var build_us: int=Time.get_ticks_usec()-build_started
			_profile_misses+=1;_profile_build_us+=build_us
			_profile_build_max_us=maxi(_profile_build_max_us,build_us)
	else:
		hits+=1
		if _profile_enabled:_profile_hits+=1
	# Null is the cached empty-bake sentinel, not geometry to submit.
	if _meshes[full_key]==null:return
	var origin: Vector2=projector.call(position,0.0)
	var scale: float=(projector.call(position+Vector2(1,0),0.0)-origin).length()/Vector2(0.82,0.41).length()
	var transform: Transform2D=ISO*Transform2D(angle-quantized,Vector2.ZERO)*ISO.affine_inverse()
	transform=transform.scaled(Vector2(scale,scale))
	# Keep the firing plane exact while rotating the tiny cached heading interval.
	transform.origin=projector.call(position,pivot_height)-transform*Vector2(0,-pivot_height)
	canvas.draw_set_transform_matrix(transform)
	canvas.draw_mesh(_meshes[full_key],null)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

static func clear() -> void:
	_meshes.clear();_order.clear();hits=0;misses=0
	if _profile_enabled:_profile_clears+=1
