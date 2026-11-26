extends RefCounted
## v0.121 natural coasts: ONE deterministic reshaping of the physical island
## ring, applied at load / world-create / battle-create boundaries only.
## Navigation, battle collision, tactical routes and CoastArt050 all keep
## reading the same `points`, so the drawn shore IS the collider shore.
##
## What "natural" means here, for every ring density:
## - Coarse rings (generated profiles, laboratory slabs): each straight edge
##   gains an asymmetric inward-displaced midpoint, then corner-cutting
##   (Chaikin) rounds every vertex. Hexagons and pentagons become curving
##   headlands and recessed bays.
## - Dense authored rings (home world.json, Glasswind): the ring is first
##   simplified to its macro vertices, then corner-cut, so the few sharp
##   macro corners that survive dense authoring are visibly ROUNDED, not
##   merely nudged inward, then a smooth varying inset breaks straight runs.
## - A ring whose macro turns are already gentle is returned unchanged, and
##   runtime-shaped island copies carry a `coast121` marker against repeat
##   shaping. Main marks translated home encounters at that boundary. Saved bytes are never mutated: shaping re-derives
##   from the same authored/saved source bytes on every launch.
##
## Safety contract: the shaped polygon is a true SUBSET of the original
## land polygon, proven with a polygon intersection (not vertex sampling),
## so no shaped edge can bridge a narrow water cove. Every point that was
## navigable water stays navigable water with equal or greater clearance;
## berths, approaches, landings, spawns and exits need no relocation.
## Shaping is a pure function of the source ring plus island id (no RNG
## state is consumed). Any failed guard falls back toward the original ring.

const MAX_RING: int = 96
const COARSE_MAX: int = 16
const DENSE_TARGET: int = 12
const GENTLE_TURN: float = 0.30

static func _seed(id: String) -> int:
	var seed: int = 7
	for idx in range(id.length()):
		seed += id.unicode_at(idx) * (idx + 3)
	return seed

static func _hash01(seed: int, i: int) -> float:
	var x: float = sin(float(seed) * 12.9898 + float(i) * 78.233) * 43758.5453
	return x - floorf(x)

static func _vec(points: Array) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for p in points:
		if p is Vector2:
			ring.append(p)
		elif p is Array and p.size() >= 2:
			ring.append(Vector2(float(p[0]), float(p[1])))
		elif p is Dictionary:
			ring.append(Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0))))
	var clean := PackedVector2Array()
	for p in ring:
		if not is_finite(p.x) or not is_finite(p.y): continue
		if not clean.is_empty() and clean[clean.size() - 1].distance_squared_to(p) < 0.0001: continue
		clean.append(p)
	if clean.size() > 1 and clean[0].distance_squared_to(clean[clean.size() - 1]) < 0.0001:
		clean.remove_at(clean.size() - 1)
	return clean

static func _pairs(ring: PackedVector2Array) -> Array:
	var out: Array = []
	for p in ring: out.append([p.x, p.y])
	return out

static func _centroid(ring: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in ring: c += p
	return c / maxf(1.0, float(ring.size()))

static func _area(ring: PackedVector2Array) -> float:
	var twice: float = 0.0
	for i in range(ring.size()):
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		twice += a.x * b.y - b.x * a.y
	return absf(twice) * 0.5

static func _breadth(ring: PackedVector2Array) -> float:
	var bounds := Rect2(ring[0], Vector2.ZERO)
	for p in ring: bounds = bounds.expand(p)
	return maxf(1.0, minf(bounds.size.x, bounds.size.y))

static func _inside_or_on(p: Vector2, ring: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(p, ring): return true
	for i in range(ring.size()):
		if Geometry2D.get_closest_point_to_segment(p, ring[i], ring[(i + 1) % ring.size()]).distance_squared_to(p) < 0.000001:
			return true
	return false

static func _is_subset(shaped: PackedVector2Array, original: PackedVector2Array) -> bool:
	# Split each complete edge at every old-boundary crossing. Each open
	# interval has a single inside/outside classification; this also catches
	# narrow coves whose mouth misses the edge's midpoint. Tolerance is one
	# thousandth of a world unit, never a percentage of the island's area.
	for p in shaped:
		if not _inside_or_on(p, original): return false
	for i in range(shaped.size()):
		var a: Vector2=shaped[i]
		var b: Vector2=shaped[(i+1)%shaped.size()]
		var delta: Vector2=b-a
		var length_squared: float=delta.length_squared()
		if length_squared<0.000001:return false
		var splits: Array[float]=[0.0,1.0]
		for j in range(original.size()):
			var hit=Geometry2D.segment_intersects_segment(a,b,original[j],original[(j+1)%original.size()])
			if hit!=null:splits.append(clampf((Vector2(hit)-a).dot(delta)/length_squared,0.0,1.0))
		splits.sort()
		for j in range(1,splits.size()):
			if splits[j]-splits[j-1]<0.0000001:continue
			if not _inside_or_on(a+delta*((splits[j]+splits[j-1])*0.5),original):return false
	return _area(shaped)>0.0

static func _simple(ring: PackedVector2Array) -> bool:
	var n: int = ring.size()
	if n < 3: return false
	for i in range(n):
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % n]
		if a.distance_squared_to(b) < 0.0001: return false
		for j in range(i + 2, n):
			if i == 0 and j == n - 1: continue
			if Geometry2D.segment_intersects_segment(a, b, ring[j], ring[(j + 1) % n]) != null:
				return false
	return true

static func _subset_repair(candidate: PackedVector2Array, original: PackedVector2Array, center: Vector2) -> PackedVector2Array:
	# Use the actual clipped ring as physical land, rather than retaining a
	# candidate which merely has a similar area. A tiny inward clip margin
	# keeps float rounding from moving an old water boundary outward.
	var clips: Array=Geometry2D.offset_polygon(original,-0.5)
	var best:=PackedVector2Array()
	var largest: float=0.0
	for clip: PackedVector2Array in clips:
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(candidate,clip):
			var area: float=_area(piece)
			if area>largest:best=_vec(_pairs(piece));largest=area
	if best.is_empty():return PackedVector2Array()
	# Corner cutting removes only a convex ear wholly inside the current
	# simple ring. It never fills a water cove while enforcing the hard cap.
	while best.size()>MAX_RING:
		var chosen: int=-1
		var smallest: float=INF
		var signed_area: float=0.0
		for j in range(best.size()):signed_area+=best[j].cross(best[(j+1)%best.size()])
		var winding: float=1.0 if signed_area>0.0 else -1.0
		for i in range(best.size()):
			var a: Vector2=best[posmod(i-1,best.size())]
			var b: Vector2=best[i]
			var c: Vector2=best[(i+1)%best.size()]
			var turn: float=(b-a).cross(c-b)*winding
			if turn<=0.0:continue
			var trial: PackedVector2Array=best.duplicate()
			trial.remove_at(i)
			if turn<smallest and _simple(trial) and _is_subset(trial,original):chosen=i;smallest=turn
		if chosen<0:return PackedVector2Array()
		best.remove_at(chosen)
	return best

static func _valid(ring: PackedVector2Array, original: PackedVector2Array) -> bool:
	if ring.size() < 3 or ring.size() > MAX_RING: return false
	for p in ring:
		if not is_finite(p.x) or not is_finite(p.y): return false
	var area: float = _area(ring)
	var source: float = _area(original)
	if source <= 0.0 or area < source * 0.5 or area > source * 1.001: return false
	return _simple(ring) and _is_subset(ring, original)

static func _inset(seed: int, angle: float, breadth: float, scale: float) -> float:
	# Smooth low-frequency inset: neighbouring shore vertices move together,
	# so a straight authored edge becomes a gentle curve, never a zigzag.
	var phase_a: float = float(posmod(seed, 360)) * TAU / 360.0
	var phase_b: float = float(posmod(seed * 7, 360)) * TAU / 360.0
	var wave: float = 0.5 + 0.5 * sin(angle * 2.0 + phase_a)
	var swell: float = 0.6 + 0.4 * sin(angle * 3.0 + phase_b)
	return (breadth * 0.008 + breadth * 0.030 * wave * swell) * scale

static func _chaikin(ring: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(ring.size()):
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		out.append(a * 0.75 + b * 0.25)
		out.append(a * 0.25 + b * 0.75)
	return out

static func _macro_turn(ring: PackedVector2Array, i: int, k: int) -> float:
	var n: int = ring.size()
	var a: Vector2 = ring[i] - ring[posmod(i - k, n)]
	var b: Vector2 = ring[posmod(i + k, n)] - ring[i]
	if a.length() < 0.001 or b.length() < 0.001: return 0.0
	return absf(angle_difference(a.angle(), b.angle()))

static func _max_macro_turn(ring: PackedVector2Array) -> float:
	var k: int = maxi(1, ring.size() / 24)
	var worst: float = 0.0
	for i in range(ring.size()): worst = maxf(worst, _macro_turn(ring, i, k))
	return worst

static func _removal_safe(pts: Array, i: int) -> bool:
	# Dropping vertex i replaces its two edges with one chord; that chord
	# must not cross any non-adjacent edge (concave authored rings can
	# self-intersect under naive simplification and then fail every gate).
	var n: int = pts.size()
	var a: Vector2 = pts[posmod(i - 1, n)]
	var b: Vector2 = pts[posmod(i + 1, n)]
	for j in range(n):
		var c: Vector2 = pts[j]
		var d: Vector2 = pts[posmod(j + 1, n)]
		if c == a or c == b or d == a or d == b: continue
		if Geometry2D.segment_intersects_segment(a, b, c, d) != null: return false
	return true

static func _simplify(ring: PackedVector2Array, target: int) -> PackedVector2Array:
	# Bounded Visvalingam simplification: repeatedly drop the SAFE vertex
	# whose triangle has least area. Macro corners (large triangles)
	# survive, so the following corner-cut rounds the real silhouette,
	# not micro-noise. Stops early if no removal stays simple.
	var pts: Array = []
	for p in ring: pts.append(p)
	while pts.size() > maxi(3, target):
		var worst: int = -1
		var worst_area: float = INF
		for i in range(pts.size()):
			var a: Vector2 = pts[posmod(i - 1, pts.size())]
			var b: Vector2 = pts[i]
			var c: Vector2 = pts[posmod(i + 1, pts.size())]
			var area: float = absf((b - a).cross(c - a)) * 0.5
			if area < worst_area and _removal_safe(pts, i):
				worst_area = area
				worst = i
		if worst < 0: break
		pts.remove_at(worst)
	var out := PackedVector2Array()
	for p in pts: out.append(p)
	return out

static func _shape_coarse(ring: PackedVector2Array, seed: int) -> PackedVector2Array:
	var center: Vector2 = _centroid(ring)
	var breadth: float = _breadth(ring)
	# Break every long straight edge once, at an asymmetric point pulled
	# inward by an edge-specific depth: shallow = headland, deep = bay.
	var doubled := PackedVector2Array()
	for i in range(ring.size()):
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		var tip: float = _inset(seed, (a - center).angle(), breadth, 0.5)
		doubled.append(a.move_toward(center, minf(tip, a.distance_to(center) * 0.2)))
		var t: float = 0.38 + 0.24 * _hash01(seed, i * 2 + 1)
		var mid: Vector2 = a.lerp(b, t)
		var depth: float = minf(a.distance_to(b) * (0.04 + 0.10 * _hash01(seed, i * 2)), breadth * 0.06)
		doubled.append(mid.move_toward(center, minf(depth, mid.distance_to(center) * 0.25)))
	var shaped: PackedVector2Array = doubled
	for iteration in range(2):
		if shaped.size() * 2 > MAX_RING: break
		shaped = _chaikin(shaped)
	return _subset_repair(shaped, ring, center)

static func _coastal_coves121(ring: PackedVector2Array, seed: int) -> PackedVector2Array:
	# Forty arc-length samples avoid inheriting ruler-straight authored runs.
	# Local inward normals create coves on every side, including non-star-shaped
	# islands where pulling toward a global center leaves whole edges untouched.
	var lengths: Array[float]=[]
	var perimeter: float=0.0
	for i in range(ring.size()):
		var length: float=ring[i].distance_to(ring[(i+1)%ring.size()])
		lengths.append(length);perimeter+=length
	if perimeter<1.0:return PackedVector2Array()
	var breadth: float=_breadth(ring)
	var signed_area121: float=0.0
	for i in range(ring.size()):signed_area121+=ring[i].cross(ring[(i+1)%ring.size()])
	var winding121: float=1.0 if signed_area121>0.0 else -1.0
	var phase: float=float(posmod(seed,360))*TAU/360.0
	var samples:=PackedVector2Array()
	var edge: int=0
	var passed: float=0.0
	for i in range(40):
		var u: float=float(i)/40.0
		var distance: float=perimeter*u
		while edge<ring.size()-1 and passed+lengths[edge]<distance:
			passed+=lengths[edge];edge+=1
		var a: Vector2=ring[edge]
		var b: Vector2=ring[(edge+1)%ring.size()]
		var t: float=clampf((distance-passed)/maxf(0.001,lengths[edge]),0.0,1.0)
		var at: Vector2=a.lerp(b,t)
		var edge_delta121: Vector2=b-a
		var inward: Vector2=Vector2(-edge_delta121.y,edge_delta121.x).normalized()*winding121
		var broad: float=0.5+0.5*sin(u*TAU*5.0+phase)
		var broken: float=0.5+0.5*sin(u*TAU*9.0+phase*2.0)
		var depth: float=breadth*(0.025+0.075*broad*broad+0.008*broken)
		samples.append(at+inward*depth)
	var curved121: PackedVector2Array=_chaikin(samples)
	for _pass121 in range(2):
		var smoothed121:=PackedVector2Array()
		for i in range(curved121.size()):smoothed121.append(curved121[posmod(i-1,curved121.size())]*0.25+curved121[i]*0.5+curved121[(i+1)%curved121.size()]*0.25)
		curved121=smoothed121
	return _subset_repair(curved121,ring,_centroid(ring))

static func _shape_dense(ring: PackedVector2Array, seed: int) -> PackedVector2Array:
	var coves: PackedVector2Array=_coastal_coves121(ring,seed)
	if _valid(coves,ring):
		# Native morphological opening rounds visible headlands at a spatial
		# radius, rather than adding tiny bevels to an inherited pointed horn.
		# The final old-footprint clip remains the physical safety authority.
		var radius121: float=minf(95.0,_breadth(ring)*0.06)
		var rounded121:=PackedVector2Array()
		var largest121: float=0.0
		for inset121: PackedVector2Array in Geometry2D.offset_polygon(coves,-radius121,Geometry2D.JOIN_ROUND):
			for expanded121: PackedVector2Array in Geometry2D.offset_polygon(inset121,radius121,Geometry2D.JOIN_ROUND):
				var reduced121: PackedVector2Array=expanded121 if expanded121.size()<=88 else _simplify(expanded121,88)
				var candidate121: PackedVector2Array=_subset_repair(reduced121,ring,_centroid(ring))
				if _valid(candidate121,ring) and _area(candidate121)>largest121:
					rounded121=candidate121;largest121=_area(candidate121)
		if not rounded121.is_empty():return rounded121
		return coves
	# Already-rounded rings (e.g. a shaped home coast translated into a
	# battle) are a fixed point: no macro corner left to cut.
	if ring.size() >= 24 and _max_macro_turn(ring) < GENTLE_TURN: return ring
	var center: Vector2 = _centroid(ring)
	var breadth: float = _breadth(ring)
	var base: PackedVector2Array = ring if ring.size() <= DENSE_TARGET else _simplify(ring, DENSE_TARGET)
	# Corner-cutting is what visibly rounds the surviving macro corners;
	# one pass doubles the count, a second runs only within the cap.
	var shaped: PackedVector2Array = _chaikin(base)
	if shaped.size() * 2 <= MAX_RING: shaped = _chaikin(shaped)
	var curved := PackedVector2Array()
	for p in shaped:
		var depth: float = _inset(seed, (p - center).angle(), breadth, 3.0)
		curved.append(p.move_toward(center, minf(depth, p.distance_to(center) * 0.2)))
	return _subset_repair(curved, ring, center)

## Coarse saved/generated/lab rings. Deterministic in (points, id).
static func natural_ring(points: Array, id: String) -> Array:
	var ring: PackedVector2Array = _vec(points)
	if ring.size() < 3: return points.duplicate(true)
	if ring.size() > COARSE_MAX: return natural_ring_dense(points, id)
	var shaped: PackedVector2Array = _shape_coarse(ring, _seed(id))
	if _valid(shaped, ring): return _pairs(shaped)
	var smooth: PackedVector2Array = _subset_repair(_chaikin(ring), ring, _centroid(ring))
	if smooth.size() * 2 <= MAX_RING: smooth = _subset_repair(_chaikin(smooth), ring, _centroid(ring))
	if _valid(smooth, ring): return _pairs(smooth)
	return points.duplicate(true)

## Dense rings (Glasswind's 36-vertex keys, any runtime ring over the
## coarse cap): simplify to macro vertices, corner-cut, curve, contain.
static func natural_ring_dense(points: Array, id: String) -> Array:
	var ring: PackedVector2Array = _vec(points)
	if ring.size() < 3: return points.duplicate(true)
	if ring.size() <= COARSE_MAX: return natural_ring(points, id)
	var shaped: PackedVector2Array = _shape_dense(ring, _seed(id))
	if shaped == ring: return points.duplicate(true)
	if _valid(shaped, ring): return _pairs(shaped)
	var base: PackedVector2Array = ring if ring.size() <= DENSE_TARGET else _simplify(ring, DENSE_TARGET)
	var smooth: PackedVector2Array = _subset_repair(_chaikin(base), ring, _centroid(ring))
	if _valid(smooth, ring): return _pairs(smooth)
	return points.duplicate(true)

## Dense authored home rings from world.json, shaped once per launch from
## the unchanged file bytes at Main's data load. Same dense core as the
## runtime path; kept as its own entry so home islands never gain the
## runtime marker key their strict definition validation forbids.
static func natural_ring_authored(points: Array, id: String) -> Array:
	return natural_ring_dense(points, id)

## Runtime island sets (ocean regions, battle islands). Copies shaped here
## carry `coast121 = 1` so a shaped copy fed back through any later
## boundary is skipped verbatim. The marker exists only on these runtime
## duplicates, after all saved-definition validation has run; it is never
## written to a save by this module.
static func natural_islands(islands: Array) -> Array:
	var out: Array = []
	for index in range(islands.size()):
		var island = islands[index]
		if not island is Dictionary:
			out.append(island)
			continue
		var local: Dictionary = island.duplicate(true)
		if int(local.get("coast121", 0)) == 1:
			out.append(local)
			continue
		var pts = local.get("points", [])
		if pts is Array and pts.size() >= 3:
			local.points = natural_ring(pts, str(local.get("id", "island_%d" % index)))
			local["coast121"] = 1
		out.append(local)
	return out

static func natural_islands_authored(islands: Array) -> Array:
	var out: Array = []
	for index in range(islands.size()):
		var island = islands[index]
		if not island is Dictionary:
			out.append(island)
			continue
		var local: Dictionary = island.duplicate(true)
		var pts = local.get("points", [])
		if pts is Array and pts.size() >= 3:
			local.points = natural_ring_authored(pts, str(local.get("id", "island_%d" % index)))
		out.append(local)
	return out
