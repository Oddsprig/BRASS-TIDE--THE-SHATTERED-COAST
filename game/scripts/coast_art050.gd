extends RefCounted
## Original, shaded nautical artwork over the real coast. Preparation is a scene /
## encounter-boundary operation; drawing only submits immutable colored meshes.
## All opaque triangles are clipped to the collider ring. Reef strokes and pier
## symbols are chart ink, never additional land or a second navigation model.

const VERTEX_LIMITS: Array=[2500,9000,18000]
const MAX_REEF_SEGMENTS: int=20
const MAX_ROOFS: int=26

static func lod(chart_scale: float) -> int:
	return 0 if chart_scale<0.22 else 1 if chart_scale<0.8 else 2

static func _ring(source: Array) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for p in source:
		if p is Vector2:result.append(p)
		elif p is Dictionary:result.append(Vector2(float(p.get("x",0.0)),float(p.get("y",0.0))))
		elif p is Array and p.size()>=2:result.append(Vector2(float(p[0]),float(p[1])))
	return result

static func _bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():return Rect2()
	var result:=Rect2(points[0],Vector2.ZERO)
	for p in points:result=result.expand(p)
	return result

static func _new(land: PackedVector2Array) -> Dictionary:
	var levels: Array=[]
	for i in range(3):levels.append({"vertices":PackedVector3Array(),"colors":PackedColorArray()})
	var bounds: Rect2=_bounds(land)
	return {"coast050":true,"land":land,"bounds":bounds,"origin":bounds.get_center(),
		"levels":levels,"outline":PackedVector2Array(),"reef":PackedVector2Array(),"pier":PackedVector2Array()}

static func _paint(plan: Dictionary,first_lod: int,shape: PackedVector2Array,color: Color,clip: bool=true) -> void:
	if shape.size()<3 or plan.land.size()<3:return
	var pieces: Array=Geometry2D.intersect_polygons(shape,plan.land) if clip else [shape]
	for piece: PackedVector2Array in pieces:
		# Triangulate near the local origin, including tiny roof vents. Absolute
		# Float32 winding sums at the far end of the world lose small areas.
		var local:=PackedVector2Array()
		for p in piece:local.append(p-Vector2(plan.origin))
		var indices: PackedInt32Array=Geometry2D.triangulate_polygon(local)
		if indices.is_empty():continue
		for level in range(first_lod,3):
			var batch: Dictionary=plan.levels[level]
			if batch.vertices.size()+indices.size()>int(VERTEX_LIMITS[level]):continue
			for index in indices:
				var p: Vector2=local[index]
				batch.vertices.append(Vector3(p.x,p.y,0.0));batch.colors.append(color)

static func _finish(plan: Dictionary) -> Dictionary:
	for batch: Dictionary in plan.levels:
		var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=batch.vertices;arrays[Mesh.ARRAY_COLOR]=batch.colors
		var mesh:=ArrayMesh.new()
		if not batch.vertices.is_empty():mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		batch.mesh=mesh
	return plan

static func _box(at: Vector2,size: Vector2,tangent: Vector2=Vector2.RIGHT,inland: Vector2=Vector2.DOWN) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for p in [Vector2(-0.5,-0.5),Vector2(0.5,-0.5),Vector2(0.5,0.5),Vector2(-0.5,0.5)]:
		result.append(at+tangent*p.x*size.x+inland*p.y*size.y)
	return result

static func _oval(at: Vector2,size: Vector2) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for i in range(8):result.append(at+Vector2.from_angle(float(i)*TAU/8.0)*size)
	return result

static func _patch(at: Vector2,size: Vector2,phase: int=0) -> PackedVector2Array:
	# A bounded, lobed brush shape, used only while preparing the three meshes.
	# Unequal shoulders break the old regular octagon without a texture or RNG.
	var lobes: Array=[0.86,1.0,0.81,0.97,0.87,1.04,0.82,0.96,0.90,1.02,0.79,0.95]
	var result:=PackedVector2Array()
	for i in range(lobes.size()):
		result.append(at+Vector2.from_angle(float(i)*TAU/float(lobes.size()))*size*float(lobes[(i+phase)%lobes.size()]))
	return result

static func _ribbon(plan: Dictionary,points: PackedVector2Array,width: float,color: Color,first_lod: int) -> void:
	for i in range(1,points.size()):
		var a: Vector2=points[i-1];var b: Vector2=points[i]
		var side: Vector2=(b-a).normalized().orthogonal()*width*0.5
		_paint(plan,first_lod,PackedVector2Array([a-side,b-side,b+side,a+side]),color)

static func _mapped(bounds: Rect2,pairs: Array) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for p in pairs:result.append(bounds.position+Vector2(p[0],p[1])*bounds.size)
	return result

static func _profile(id: String) -> Dictionary:
	# These compositions follow the eight actual islands; no copied map, new
	# region, extra island, decorative lagoon or procedural land silhouette.
	match id:
		"isl_lantern":return {"biome":"chalk headland / orchard coast","ground":"84976a","rock":"a7a58d","leaf":"3d674b","beach":[[0.0,0.30],[0.48,0.61]],"ridge":[[0.14,0.12],[0.24,0.28],[0.38,0.39],[0.46,0.55],[0.31,0.77]],"groves":[[0.25,0.28],[0.36,0.42],[0.28,0.61],[0.19,0.80],[0.52,0.38],[0.68,0.47]],"fields":false}
		"clash_north":return {"biome":"sheltered limestone cove","ground":"81916a","rock":"a3a08e","leaf":"3d654d","beach":[[0.16,0.43],[0.68,0.89]],"ridge":[[0.16,0.44],[0.35,0.24],[0.58,0.30],[0.83,0.58]],"groves":[[0.16,0.57],[0.26,0.38],[0.38,0.23],[0.51,0.30],[0.70,0.39],[0.84,0.57],[0.88,0.68]],"fields":false}
		"clash_south":return {"biome":"dark stone headland","ground":"768969","rock":"809087","leaf":"46664c","beach":[[0.21,0.51],[0.69,0.81]],"ridge":[[0.17,0.55],[0.36,0.28],[0.52,0.31],[0.67,0.66],[0.84,0.68]],"groves":[[0.23,0.42],[0.35,0.26],[0.50,0.41],[0.65,0.67],[0.82,0.67]],"fields":false}
		"isl_kelp":return {"biome":"tidal reedbanks / salt meadow","ground":"819779","rock":"aab19a","leaf":"527c5c","beach":[[0.0,0.41],[0.72,0.86]],"ridge":[[0.22,0.20],[0.34,0.40],[0.53,0.57],[0.40,0.76]],"groves":[[0.21,0.31],[0.36,0.48],[0.53,0.55],[0.34,0.72],[0.18,0.70]],"fields":true}
		"isl_sawtooth":return {"biome":"ironwood slopes / pale crags","ground":"7b8b6b","rock":"aaa996","leaf":"365947","beach":[[0.08,0.25]],"ridge":[[0.19,0.22],[0.34,0.34],[0.47,0.46],[0.60,0.61],[0.69,0.78]],"groves":[[0.23,0.29],[0.35,0.40],[0.49,0.57],[0.62,0.65],[0.76,0.20]],"fields":false}
		"isl_verdigris":return {"biome":"polder terraces / windbreaks","ground":"9ca478","rock":"c0b98e","leaf":"567650","beach":[[0.0,0.18],[0.36,0.53]],"ridge":[[0.43,0.19],[0.48,0.36],[0.62,0.52],[0.69,0.72]],"groves":[[0.43,0.20],[0.50,0.36],[0.68,0.56],[0.76,0.74]],"fields":true}
		"isl_cinder":return {"biome":"ash spine / quarried red cliffs","ground":"8d856c","rock":"9d7961","leaf":"566b50","beach":[[0.60,0.76]],"ridge":[[0.56,0.18],[0.46,0.36],[0.58,0.52],[0.45,0.72],[0.57,0.87]],"groves":[[0.52,0.28],[0.55,0.45],[0.45,0.60]],"fields":false}
		"isl_fen":return {"biome":"reed fen / wooded levees","ground":"829c79","rock":"a8b28d","leaf":"3e7455","beach":[[0.0,0.25],[0.45,0.70]],"ridge":[[0.47,0.13],[0.55,0.32],[0.49,0.45],[0.34,0.61],[0.24,0.80]],"groves":[[0.46,0.23],[0.58,0.40],[0.30,0.63],[0.24,0.79],[0.73,0.61]],"fields":true}
		"isl_oilstone":return {"biome":"slate benches / dry scrub","ground":"8e927e","rock":"7f8d89","leaf":"63745b","beach":[[0.09,0.25],[0.69,0.80]],"ridge":[[0.22,0.28],[0.38,0.40],[0.53,0.57],[0.65,0.74]],"groves":[[0.32,0.28],[0.40,0.44],[0.62,0.59],[0.73,0.38]],"fields":false}
		"isl_shatter":return {"biome":"basalt teeth / burnt heath","ground":"85866b","rock":"6c7775","leaf":"4f6550","beach":[[0.43,0.57]],"ridge":[[0.44,0.16],[0.32,0.34],[0.26,0.53],[0.45,0.71],[0.65,0.78]],"groves":[[0.43,0.29],[0.33,0.48],[0.38,0.68],[0.62,0.73]],"fields":false}
		"glasswind_west","glasswind_keys_ocean_0":return {"biome":"wind-scoured limestone / beacon scrub","ground":"728f84","rock":"a7b1a5","leaf":"446c5b","beach":[[0.11,0.22],[0.48,0.68]],"ridge":[[0.20,0.52],[0.38,0.34],[0.56,0.44],[0.74,0.62]],"groves":[[0.30,0.44],[0.48,0.36],[0.64,0.52],[0.42,0.66],[0.56,0.68]],"fields":false}
		"glasswind_crown","glasswind_keys_ocean_1":return {"biome":"weather-bleached crown ridge / sea-pine","ground":"7c968b","rock":"b3b9aa","leaf":"48705e","beach":[[0.22,0.34],[0.64,0.82]],"ridge":[[0.18,0.48],[0.36,0.28],[0.56,0.34],[0.74,0.54],[0.62,0.74]],"groves":[[0.28,0.42],[0.46,0.34],[0.66,0.46],[0.54,0.66],[0.38,0.64]],"fields":true}
		"glasswind_south","glasswind_keys_ocean_2":return {"biome":"reef-cut basalt key / driftwood shoals","ground":"68877d","rock":"8f9c96","leaf":"3d6454","beach":[[0.11,0.29],[0.66,0.78]],"ridge":[[0.18,0.62],[0.36,0.38],[0.56,0.42],[0.76,0.58]],"groves":[[0.28,0.54],[0.46,0.44],[0.64,0.52],[0.52,0.68],[0.36,0.68]],"fields":false}
		"settled_01_island_01","settled_01_ocean_0":return {"biome":"terraced loam headlands / sheltered coves","ground":"8c996e","rock":"b6b08e","leaf":"4c7250","beach":[[0.06,0.24],[0.54,0.72]],"ridge":[[0.18,0.46],[0.36,0.30],[0.58,0.38],[0.76,0.56]],"groves":[[0.28,0.38],[0.46,0.34],[0.64,0.48],[0.38,0.64],[0.56,0.66]],"fields":true}
		"settled_01_island_02","settled_01_ocean_1":return {"biome":"sea-pine ridge / timber bench","ground":"788e6d","rock":"a59d84","leaf":"3a624b","beach":[[0.12,0.28],[0.62,0.78]],"ridge":[[0.16,0.52],[0.32,0.32],[0.50,0.26],[0.68,0.40],[0.78,0.62]],"groves":[[0.26,0.44],[0.44,0.32],[0.62,0.42],[0.52,0.64],[0.34,0.66]],"fields":false}
	var seed_sum: int=0
	for idx in range(id.length()):seed_sum+=id.unicode_at(idx)*(idx+3)
	match posmod(seed_sum,5):
		0:return {"biome":"terraced coastal loam / windbreak bench","ground":"899870","rock":"b2ac8c","leaf":"4b7251","beach":[[0.05,0.24],[0.55,0.72]],"ridge":[[0.20,0.48],[0.38,0.32],[0.58,0.38],[0.75,0.58]],"groves":[[0.28,0.40],[0.48,0.35],[0.64,0.50],[0.40,0.64]],"fields":true}
		1:return {"biome":"sea-pine ridge / shingle coves","ground":"798e6e","rock":"a4a18d","leaf":"3b634b","beach":[[0.10,0.27],[0.60,0.76]],"ridge":[[0.18,0.54],[0.34,0.34],[0.54,0.30],[0.74,0.52]],"groves":[[0.26,0.44],[0.46,0.34],[0.64,0.46],[0.50,0.66],[0.34,0.64]],"fields":false}
		2:return {"biome":"iron-stained crags / scrub shelf","ground":"85886c","rock":"9f846b","leaf":"526a4f","beach":[[0.14,0.30],[0.64,0.78]],"ridge":[[0.20,0.34],[0.38,0.42],[0.56,0.34],[0.74,0.58]],"groves":[[0.30,0.38],[0.50,0.42],[0.66,0.54],[0.42,0.66]],"fields":false}
		3:return {"biome":"salt-meadow bench / limestone point","ground":"849878","rock":"adb398","leaf":"497358","beach":[[0.0,0.22],[0.48,0.68]],"ridge":[[0.22,0.42],[0.40,0.30],[0.60,0.44],[0.74,0.64]],"groves":[[0.30,0.36],[0.50,0.38],[0.64,0.54],[0.38,0.64]],"fields":true}
	return {"biome":"rocky coastal heath","ground":"82956b","rock":"a3a48b","leaf":"466b50","beach":[[0.0,0.25],[0.56,0.72]],"ridge":[[0.22,0.32],[0.42,0.44],[0.60,0.38],[0.74,0.60]],"groves":[[0.32,0.38],[0.52,0.42],[0.64,0.56],[0.40,0.64]],"fields":false}

static func _hash122(seed: int, i: int) -> float:
	var x: float=sin(float(seed)*12.9898+float(i)*78.233)*43758.5453
	return x-floorf(x)

static func _seed122(plan: Dictionary) -> int:
	var seed: int=11
	var id: String=str(plan.get("id",""))
	for idx in range(id.length()):seed+=id.unicode_at(idx)*(idx+3)
	return seed

static func _shore_samples122(land: PackedVector2Array) -> Dictionary:
	# Use every physical edge. Smoothed normals blend the shelf around corners.
	var inward:=PackedVector2Array()
	var fractions: Array=[]
	var lengths := PackedFloat32Array()
	var perimeter := 0.0
	for k in range(land.size()):
		lengths.append(perimeter)
		perimeter += land[k].distance_to(land[(k + 1) % land.size()])
	for k in range(land.size()):
		var at: Vector2=land[k]
		var tangent: Vector2=(land[(k+2)%land.size()]-land[posmod(k-2,land.size())]).normalized()
		if tangent.is_zero_approx():
			tangent = (land[(k + 1) % land.size()] - land[posmod(k - 1, land.size())]).normalized()
		var normal: Vector2=tangent.orthogonal()
		if not Geometry2D.is_point_in_polygon(at+normal*3.0,land):normal=-normal
		inward.append(normal)
		fractions.append(float(lengths[k]) / maxf(1.0, perimeter))
	return {"points":land,"inward":inward,"fractions":fractions}

static func _tidal_widths122(seed: int,count: int,base: float,swing: float) -> Array:
	# Irregular but smooth width profile: one slow wave, one faster wave
	# and hashed variation, then wrapped moving-average smoothing so the
	# band edge undulates like a tide line and never zigzags per vertex.
	var widths: Array=[]
	var phase_a: float=float(posmod(seed,360))*TAU/360.0
	var phase_b: float=float(posmod(seed*13,360))*TAU/360.0
	for s in range(count):
		var t: float=float(s)/maxf(1.0,float(count))*TAU
		var wave: float=0.62+0.38*sin(t*2.0+phase_a)+0.22*sin(t*5.0+phase_b)+0.28*_hash122(seed,s)
		widths.append(base*(1.0-swing*0.5+swing*clampf(wave,0.15,1.35)))
	for pass_no in range(2):
		var smooth: Array=[]
		for s in range(count):
			smooth.append((float(widths[posmod(s-1,count)])+2.0*float(widths[s])+float(widths[posmod(s+1,count)]))*0.25)
		widths=smooth
	return widths

static func _offset_curve122(samples: Dictionary,widths: Array,scale: float=1.0) -> PackedVector2Array:
	var out:=PackedVector2Array()
	var points: PackedVector2Array=samples.points
	var inward: PackedVector2Array=samples.inward
	for s in range(points.size()):out.append(points[s]+inward[s]*float(widths[s])*scale)
	return out

static func _ground_layers122(plan: Dictionary,profile: Dictionary,bounds: Rect2,breadth: float) -> void:
	# Large soft tonal masses over the flat base ground so the island
	# interior reads as layered maritime terrain, not one monotone slab.
	# Deterministic stations from bounds fractions, sizes and tones from
	# the island seed; all clipped to land by _paint.
	var seed: int=_seed122(plan)
	var ground: Color=Color(profile.ground)
	var leaf: Color=Color(profile.leaf)
	var stations: Array=[[0.30,0.30],[0.62,0.26],[0.46,0.52],[0.72,0.58],[0.28,0.68],[0.58,0.80],[0.40,0.18]]
	for i in range(stations.size()):
		var at: Vector2=bounds.position+bounds.size*Vector2(float(stations[i][0])+0.07*_hash122(seed,i*3)-0.035,float(stations[i][1])+0.07*_hash122(seed,i*3+1)-0.035)
		var size: Vector2=Vector2(breadth*(0.20+0.10*_hash122(seed,i*3+2)),breadth*0.11)
		var tone: Color=ground.lightened(0.06) if i%3==0 else ground.darkened(0.05).lerp(leaf,0.12) if i%3==1 else ground.lerp(Color("b7ad7d"),0.10)
		_paint(plan,0,_patch(at,size,i*2%12),tone)
		if i%2==0:
			_paint(plan,1,_patch(at+Vector2(-size.x*0.18,-size.y*0.20),Vector2(size.x*0.52,size.y*0.55),(i*2+5)%12),tone.lightened(0.05))

static func _shallow_water(plan: Dictionary, samples: Dictionary, breadth: float) -> void:
	var land: PackedVector2Array = samples.points
	# Reserve room for the opaque base even when an unshaped ring is supplied.
	if land.size() * 15 > int(VERTEX_LIMITS[0]): return
	var widths: Array = _tidal_widths122(_seed122(plan) + 7, land.size(), clampf(breadth * 0.105, 48.0, 152.0), 1.3)
	var middle: PackedVector2Array = _offset_curve122(samples, widths, -0.35)
	var outer: PackedVector2Array = _offset_curve122(samples, widths, -1.0)
	var shore_tint := Color(0.33, 0.68, 0.60, 0.66)
	var shelf_tint := Color(0.25, 0.58, 0.56, 0.36)
	var sea_tint := Color(0.25, 0.58, 0.56, 0.0)
	var origin: Vector2 = plan.origin
	for i in range(land.size()):
		var j: int = (i + 1) % land.size()
		plan.bounds = Rect2(plan.bounds).expand(outer[i])
		var vertices: Array[Vector2] = [land[i], land[j], middle[j], land[i], middle[j], middle[i],
			middle[i], middle[j], outer[j], middle[i], outer[j], outer[i]]
		var colors: Array[Color] = [shore_tint, shore_tint, shelf_tint, shore_tint, shelf_tint, shelf_tint,
			shelf_tint, shelf_tint, sea_tint, shelf_tint, sea_tint, sea_tint]
		for batch: Dictionary in plan.levels:
			for k in range(vertices.size()):
				var point: Vector2 = vertices[k] - origin
				batch.vertices.append(Vector3(point.x, point.y, 0.0))
				batch.colors.append(colors[k])

static func _shore(plan: Dictionary,profile: Dictionary,samples: Dictionary) -> void:
	var land: PackedVector2Array=plan.land
	if land.size()<3:return
	var seed: int=_seed122(plan)
	var points: PackedVector2Array=samples.points
	var inward: PackedVector2Array=samples.inward
	var rock: Color=Color(profile.rock)
	var ground: Color=Color(profile.ground)
	var light: Vector2=Vector2(-0.6,-0.8)
	# Per-sample sand/rock from the authored beach spans, widths from the
	# tidal profile: sand runs wider and gentler, rock shelves pinch out.
	var sand_widths: Array=_tidal_widths122(seed,points.size(),34.0,0.95)
	var rock_widths: Array=_tidal_widths122(seed+3,points.size(),22.0,1.15)
	var is_sand: Array=[]
	var widths: Array=[]
	for s in range(points.size()):
		var sand: bool=false
		for span in profile.beach:
			if float(samples.fractions[s])>=float(span[0]) and float(samples.fractions[s])<=float(span[1]):sand=true
		is_sand.append(sand)
		widths.append(float(sand_widths[s]) if sand else float(rock_widths[s]))
	# One continuous shore face between the waterline and the tidal inner
	# curve, split per span only so sand and rock can take their colours.
	# No big triangular wedges: every quad follows four shore samples.
	var inner: PackedVector2Array=_offset_curve122(samples,widths)
	for s in range(points.size()):
		var n: int=(s+1)%points.size()
		var face: float=clampf(inward[s].dot(-light)*0.10,-0.10,0.10)
		var quad: PackedVector2Array=PackedVector2Array([points[s],points[n],inner[n],inner[s]])
		if bool(is_sand[s]):
			_paint(plan,0,quad,Color("d8c493").darkened(0.03-face))
		else:
			_paint(plan,0,quad,rock.darkened(0.22+face))
	# Wet waterline: a thin wet band hugging the actual shore, broken on
	# rock spans so stony shelves meet the water unevenly.
	var wet: PackedVector2Array=_offset_curve122(samples,widths,0.16)
	for s in range(points.size()):
		var n: int=(s+1)%points.size()
		if not bool(is_sand[s]) and _hash122(seed,s*3)<0.35:continue
		_paint(plan,1,PackedVector2Array([points[s],points[n],wet[n],wet[s]]),Color("8fae9c") if bool(is_sand[s]) else rock.darkened(0.42))
	# Dry berm / stony bench: a lighter broken band set back from the
	# waterline, painted only in hashed runs with soft gaps.
	for s in range(points.size()):
		var n: int=(s+1)%points.size()
		if _hash122(seed+5,s)<0.30:continue
		var a: Vector2=points[s]+inward[s]*float(widths[s])*0.38
		var b: Vector2=points[n]+inward[n]*float(widths[n])*0.38
		var a2: Vector2=points[s]+inward[s]*float(widths[s])*0.86
		var b2: Vector2=points[n]+inward[n]*float(widths[n])*0.86
		_paint(plan,1,PackedVector2Array([a,b,b2,a2]),Color("e6d5a4") if bool(is_sand[s]) else rock.lightened(0.12))
	# Turf fringe: scalloped ground patches nibbling the inner shore edge,
	# so grass meets beach/rock in lobes instead of one even rim line.
	for s in range(points.size()):
		if s%2!=0 and _hash122(seed+9,s)<0.6:continue
		var at: Vector2=points[s]+inward[s]*(float(widths[s])*1.02+6.0)
		var tangent: Vector2=inward[s].orthogonal()
		var size: Vector2=Vector2(16.0+14.0*_hash122(seed,s*7),8.0+5.0*_hash122(seed,s*11))
		_paint(plan,1,_patch(at,size,s%12),ground.lightened(0.05+0.05*_hash122(seed,s*5)))
		if not bool(is_sand[s]) and _hash122(seed,s*13)>0.55:
			# Loose shore stones as small tilted slabs, never a repeated crag
			# triangle pair marching around the coast.
			var stone: Vector2=points[s]+inward[s]*float(widths[s])*0.62+tangent*(6.0*_hash122(seed,s*17)-3.0)
			var tilt: Vector2=(tangent+inward[s]*(0.5*_hash122(seed,s*19)-0.25)).normalized()
			_paint(plan,1,_box(stone,Vector2(11.0+8.0*_hash122(seed,s*23),5.5),tilt,tilt.orthogonal()),rock.darkened(0.05))
			_paint(plan,2,_box(stone+Vector2(-1.5,-1.5),Vector2(6.5,2.6),tilt,tilt.orthogonal()),rock.lightened(0.26))
	# Broken seabed hatching stays transparent chart ink (no blocking).
	for s in range(points.size()):
		if not bool(is_sand[s]) or s%5!=0 or plan.reef.size()>=MAX_REEF_SEGMENTS*2:continue
		var at: Vector2=points[s]-inward[s]*(58.0+30.0*_hash122(seed,s*29))
		var along: Vector2=inward[s].orthogonal()
		plan.reef.append(at-along*20.0);plan.reef.append(at+along*20.0)

static func _relief(plan: Dictionary,profile: Dictionary,ridge: PackedVector2Array,breadth: float) -> void:
	var ground: Color=Color(profile.ground);var rock: Color=Color(profile.rock)
	var seed: int=_seed122(plan)
	var craggy: bool=plan.id in ["isl_cinder","isl_sawtooth","isl_oilstone","isl_shatter","glasswind_crown","glasswind_south","glasswind_keys_ocean_1","glasswind_keys_ocean_2"]
	for i in range(1,ridge.size()):
		var a: Vector2=ridge[i-1];var b: Vector2=ridge[i]
		var side: Vector2=(b-a).normalized().orthogonal()
		if side.dot(Vector2(-0.6,-0.8))<0.0:side=-side
		var width: float=breadth*(0.13 if craggy else 0.11)
		# Layered overlapping lobes instead of three whole-segment triangles:
		# a broad shaded foothill mass, a smaller lit mass toward the light,
		# then short broken crest highlights. Patch edges stay scalloped.
		for j in range(3):
			var t: float=0.22+0.28*float(j)
			var at: Vector2=a.lerp(b,t)+(b-a)*0.04*_hash122(seed,i*7+j)
			var size: Vector2=Vector2(width*(0.62-0.07*float(j)),width*0.34)
			_paint(plan,0,_patch(at-side*width*0.30,size,i+j),ground.darkened(0.10).lerp(rock,0.18))
			_paint(plan,0,_patch(at+side*width*0.16,Vector2(size.x*0.78,size.y*0.80),i+j+4),ground.lerp(rock,0.42).lightened(0.05))
			if craggy:
				_paint(plan,1,_patch(at+side*width*0.30+Vector2(0,-3),Vector2(size.x*0.34,size.y*0.36),i+j+8),rock.lightened(0.20))
			else:
				_paint(plan,1,_patch(at+side*width*0.26,Vector2(size.x*0.40,size.y*0.42),i+j+8),ground.lightened(0.07).lerp(rock,0.25))
		# Broken crest light: two short strokes with a gap, never one ruled
		# ribbon the full length of the segment.
		var crest_a: Vector2=a.lerp(b,0.14)+side*width*0.20
		var crest_m: Vector2=a.lerp(b,0.46)+side*width*0.30
		var crest_b: Vector2=a.lerp(b,0.86)+side*width*0.18
		_ribbon(plan,PackedVector2Array([crest_a,crest_m]),4.0 if craggy else 3.2,rock.lightened(0.30),1)
		_ribbon(plan,PackedVector2Array([crest_m+(b-a)*0.14,crest_b]),3.0 if craggy else 2.4,rock.lightened(0.22).lerp(ground,0.30),1)
		# Spurs as soft side lobes at uneven stations.
		for j in range(2):
			var spur: Vector2=a.lerp(b,0.30+0.38*float(j)+0.08*_hash122(seed,i*11+j))
			_paint(plan,1,_patch(spur-side*width*(0.42+0.16*_hash122(seed,i*13+j)),Vector2(width*0.26,width*0.15),j+2),rock.darkened(0.14).lerp(ground,0.38))

static func _reeds(plan: Dictionary,at: Vector2,height: float,leaf: Color,first_lod: int=1) -> void:
	for i in range(3):
		var root: Vector2=at+Vector2(float(i-1)*7.0,0)
		var tip: Vector2=root+Vector2(float(i-1)*4.0+3.0,-height*(0.80+float(i%2)*0.20))
		_paint(plan,first_lod,PackedVector2Array([root-Vector2(3,0),tip,root+Vector2(3,1)]),leaf.lightened(float(i)*0.08))

static func _grove(plan: Dictionary,at: Vector2,radius: float,leaf: Color,wet: bool) -> void:
	# Uneven natural stand: hashed tree stations (no shared offset table,
	# so no two groves stamp alike), mixed crown sizes and tones, low
	# scrub between trees, and a soft broken ground shadow.
	var offset: Vector2 = at - Vector2(plan.origin)
	var seed: int = _seed122(plan) + int(absf(offset.x)*0.37) + int(absf(offset.y)*0.73)
	_paint(plan,0,_patch(at,Vector2(radius*1.02,radius*0.56),seed%12),Color(plan.ground).lerp(leaf,0.24))
	_paint(plan,1,_patch(at+Vector2(6,12),Vector2(radius*0.88,radius*0.50),(seed+3)%12),leaf.darkened(0.20).lerp(Color(plan.ground),0.20))
	var trees: int=7+int(_hash122(seed,1)*5.0)
	for i in range(trees):
		var local: Vector2=Vector2(_hash122(seed,i*3+2)*2.0-1.0,_hash122(seed,i*3+3)*2.0-1.0)
		if local.length()>1.0:local=local.normalized()
		var p: Vector2=at+Vector2(local.x*radius*0.72,local.y*radius*0.44)
		var r: float=radius*(0.16+0.17*_hash122(seed,i*3+4))
		var crown: Vector2=p-Vector2(2,r*0.30)
		var tone: Color=leaf.lerp(Color("7d9b58"),0.30*_hash122(seed,i*5+1)).lightened(0.03+0.08*_hash122(seed,i*5+2))
		if _hash122(seed,i*7)<0.28:
			# Scrub bush: low scalloped mass, no trunk, darker underside.
			_paint(plan,1,_patch(crown+Vector2(2,4),Vector2(r*0.9,r*0.62),i),leaf.darkened(0.24))
			_paint(plan,1,_oval(crown,Vector2(r*0.72,r*0.52)),tone.darkened(0.06))
			continue
		_paint(plan,1,_patch(crown+Vector2(3,5),Vector2(r,r*0.78),i),leaf.darkened(0.23))
		_paint(plan,1,_oval(crown-Vector2(r*0.15,r*0.13),Vector2(r*0.84,r*0.66)),tone)
		_ribbon(plan,PackedVector2Array([p+Vector2(3,r*0.77),p+Vector2(0,r*0.20),p+Vector2(-r*0.37,-r*0.10)]),5.0,Color("686d4b"),1)
		_ribbon(plan,PackedVector2Array([p+Vector2(0,r*0.20),p+Vector2(r*0.40,-r*0.15)]),4.0,Color("686d4b"),1)
		_paint(plan,1,PackedVector2Array([crown+Vector2(-r*0.60,-r*0.20),crown+Vector2(-r*0.16,-r*0.54),crown+Vector2(r*0.24,-r*0.26),crown+Vector2(-r*0.08,-r*0.04)]),tone.lightened(0.15))
		_ribbon(plan,PackedVector2Array([crown+Vector2(-r*0.20,r*0.30),crown+Vector2(r*0.07,0),crown+Vector2(r*0.39,-r*0.18)]),2.5,leaf.darkened(0.10),2)
		if wet and i%2==0:_reeds(plan,p+Vector2(r*0.90,r*0.62),r*0.95,Color("879b63"))

static func prepare_island(island: Dictionary) -> Dictionary:
	var land: PackedVector2Array=_ring(island.get("points",[]))
	var plan: Dictionary=_new(land)
	plan.id=str(island.get("id",""));plan.name=str(island.get("name","Coast"))
	var profile: Dictionary=_profile(plan.id)
	plan.biome=profile.biome;plan.ground=Color(profile.ground);plan.roofs=[]
	if land.size()<3:return _finish(plan)
	var bounds: Rect2=plan.bounds
	var ridge: PackedVector2Array=_mapped(bounds,profile.ridge)
	var breadth: float=minf(bounds.size.x,bounds.size.y)
	var samples: Dictionary = _shore_samples122(land)
	_shallow_water(plan, samples, breadth)
	_paint(plan,0,land,plan.ground,false)
	_ground_layers122(plan,profile,bounds,breadth)
	_relief(plan,profile,ridge,breadth)
	_shore(plan,profile,samples)
	if bool(profile.fields):
		# Irregular meadow plots following the old terrace stations: lobed
		# patches with hashed sizes/tones and occasional broken furrows,
		# never broad rectangles. Land crops only, never extra water.
		var seed: int=_seed122(plan)
		for i in range(5):
			var center: Vector2=bounds.position+bounds.size*Vector2(0.34+float(i)*0.045+0.03*_hash122(seed,i*7)-0.015,0.37+float(i)*0.09+0.02*_hash122(seed,i*7+1)-0.01)
			var size: Vector2=Vector2(breadth*(0.115+0.035*_hash122(seed,i*7+2)),breadth*0.030)
			_paint(plan,1,_patch(center,size,(i*3)%12),Color("b0b184") if i%2==0 else Color("99a46e"))
			_paint(plan,1,_patch(center+Vector2(-size.x*0.16,-size.y*0.24),Vector2(size.x*0.58,size.y*0.60),(i*3+5)%12),Color("c2bd8d") if i%2==0 else Color("aab37a"))
			if i%2==0:
				var furrow_y: float=center.y-size.y*0.18
				_ribbon(plan,PackedVector2Array([Vector2(center.x-size.x*0.62,furrow_y),Vector2(center.x-size.x*0.05,furrow_y-size.y*0.16),Vector2(center.x+size.x*0.55,furrow_y+size.y*0.05)]),2.6,Color("cfc48d"),2)
	var wet: bool=plan.id in ["isl_kelp","isl_fen","isl_verdigris","glasswind_south","glasswind_keys_ocean_2"]
	for at: Vector2 in _mapped(bounds,profile.groves):_grove(plan,at,breadth*(0.075 if wet else 0.085),Color(profile.leaf),wet)
	plan.outline=land.duplicate();plan.outline.append(land[0])
	plan.label=bounds.get_center()
	if not Geometry2D.is_point_in_polygon(plan.label,land):
		var triangles: PackedInt32Array=Geometry2D.triangulate_polygon(land)
		if triangles.size()>=3:plan.label=(land[triangles[0]]+land[triangles[1]]+land[triangles[2]])/3.0
	# Include the offshore ink and shallows in draw-culling bounds only.
	for p in plan.reef:plan.bounds=Rect2(plan.bounds).expand(p)
	return _finish(plan)

static func _is_home_port(id: String) -> bool:
	return id in ["brass_haven","kelp_reach","sawtooth_mill","silt_hollow","cinder_quay","anvil_dock","reed_floats","naphtha_bay","rust_anchorage","shatter_spire"]

static func harbor_caption(port: Dictionary) -> String:
	match str(port.get("id","")):
		"brass_haven":return "CONVOY EXCHANGE"
		"kelp_reach":return "CURING WHARVES"
		"sawtooth_mill":return "IRONWOOD MILLS"
		"silt_hollow":return "POLDER GRANARIES"
		"cinder_quay":return "ARMOR FOUNDRY"
		"anvil_dock":return "GANTRY SHIPYARD"
		"reed_floats":return "ESTUARY MARKET"
		"naphtha_bay":return "FUEL DISTILLERY"
		"rust_anchorage":return "SALVAGE WHARVES"
		"shatter_spire":return "FORTIFIED GUNWORKS"
		"westglass_anchorage":return "TIMBER BRANCH QUAY"
	var ind: String=str(port.get("industry","")).to_lower()
	var spec: String=str(port.get("specialty","")).to_lower()
	match ind:
		"agriculture":return "TERRACED GRANARY QUAY"
		"timber":return "TIMBER BOOM ANCHORAGE"
		"foundry":return "ORE SMELTING QUAY"
		"refinery":return "SALTPETER LEACH WORKS" if spec=="saltpeter" else "NAPHTHA STILL QUAY"
		"trade":return "BOTANICAL DEPOT QUAY" if spec in ["supplies","medicinal_plants"] else "MERCHANT EXCHANGE QUAY"
	return str(port.get("industry","harbor")).to_upper()

static func _harbor_design(id: String,industry: String="",specialty: String="") -> Dictionary:
	# x runs along shore, y inland. Each silhouette is composed around its own
	# working landmark, streets and courtyards; there is no repeated house grid.
	# Building tuples: x,y,width,depth,kind (0 roof,1 shed,2 tank,3 hall,4 rack,5 fort).
	match id:
		"brass_haven":return {"landmark":"bonded exchange and packet court","roofs":[[0,82,88,50,3],[-90,82,43,27,0],[92,72,46,31,0],[-122,136,44,36,1],[112,126,55,37,1],[-75,184,45,28,0],[-17,207,38,26,0],[45,190,49,30,0],[91,225,34,25,0],[-122,232,41,27,0],[2,290,72,34,3]],"roads":[[[-155,46],[0,40],[160,48]],[[0,42],[0,151],[-42,235],[0,303]],[[-136,150],[0,151],[134,150]]]}
		"kelp_reach":return {"landmark":"curing sheds and drying fans","roofs":[[0,68,78,34,1],[-93,75,57,23,1],[83,86,58,23,1],[-58,144,80,17,4],[38,142,70,17,4],[-94,184,64,17,4],[10,189,79,17,4],[103,163,41,27,0],[-48,245,36,29,0],[15,270,41,27,0],[78,232,32,26,0]],"roads":[[[-151,43],[-22,43],[144,68]],[[-21,43],[-30,123],[12,279]],[[-114,216],[-30,219],[101,207]]]}
		"sawtooth_mill":return {"landmark":"saw hall and stepped timber yard","roofs":[[0,72,116,48,1],[-98,112,40,39,1],[92,125,53,28,1],[-42,163,93,19,4],[-28,195,88,19,4],[-11,228,84,19,4],[104,198,31,35,0],[91,253,38,31,0],[-99,263,37,27,0],[-46,297,42,28,0]],"roads":[[[-147,47],[36,45],[145,93]],[[58,55],[62,168],[49,289]],[[-128,250],[-50,267],[49,289],[116,278]]]}
		"silt_hollow":return {"landmark":"three granaries and terraced farm court","roofs":[[-60,78,43,61,1],[0,89,43,61,1],[60,100,43,61,1],[-107,155,32,24,0],[104,164,36,26,0],[-49,190,69,17,4],[-27,220,81,17,4],[0,250,94,17,4],[-97,267,32,28,0],[103,251,35,26,0],[32,304,53,32,3]],"roads":[[[-135,40],[0,40],[138,72]],[[-133,146],[-6,148],[132,180]],[[-132,146],[-140,270],[30,328]]]}
		"cinder_quay":return {"landmark":"twin furnace batteries and casting floor","roofs":[[0,78,116,54,1],[-76,142,51,63,1],[48,160,68,77,1],[-73,85,23,23,2],[79,88,25,25,2],[-89,224,41,29,0],[36,257,86,30,1],[107,213,32,29,0],[-45,290,34,29,0],[18,318,36,27,0]],"roads":[[[-141,42],[0,40],[143,44]],[[-19,43],[-17,184],[-11,321]],[[-125,219],[-18,213],[126,217]]]}
		"anvil_dock":return {"landmark":"parallel assembly slips and gantry court","roofs":[[-64,104,46,138,1],[4,123,46,161,1],[78,91,62,49,1],[-63,225,49,27,1],[12,242,47,31,1],[96,179,36,55,1],[-81,290,38,27,0],[0,300,47,30,3],[78,281,36,26,0]],"roads":[[[-128,35],[-18,34],[132,41]],[[-118,40],[-120,241],[-82,318]],[[-119,260],[-10,273],[122,250]]]}
		"reed_floats":return {"landmark":"barter crescent and covered market","roofs":[[0,83,66,44,3],[-73,83,41,25,0],[76,99,45,25,0],[-116,133,38,28,0],[106,156,42,27,0],[-90,192,47,28,1],[-22,214,47,27,1],[49,216,45,26,1],[-42,285,34,26,0],[18,298,38,26,0],[92,268,37,26,0]],"roads":[[[-146,54],[-70,44],[0,39],[80,58],[143,99]],[[-143,151],[-94,245],[4,263],[125,219]],[[0,43],[0,176],[-14,312]]]}
		"naphtha_bay":return {"landmark":"tank farm and cracking hall","roofs":[[0,76,90,38,1],[-74,132,47,47,2],[-12,155,53,53,2],[59,140,47,47,2],[-59,205,39,39,2],[29,222,47,47,2],[110,194,27,81,1],[-100,282,41,29,0],[-35,303,38,25,0],[42,297,47,31,1]],"roads":[[[-136,44],[0,41],[138,47]],[[-132,51],[-131,230],[-93,313]],[[-129,255],[19,263],[134,249]]]}
		"rust_anchorage":return {"landmark":"salvage fan and prize sheds","roofs":[[0,81,91,40,1],[-97,100,46,30,1],[94,124,52,35,1],[-62,157,65,19,4],[11,181,78,21,4],[-101,225,36,28,0],[-38,259,43,27,0],[29,246,38,26,0],[92,216,35,30,0],[9,311,62,39,5]],"roads":[[[-149,54],[-28,40],[142,78]],[[-28,43],[-15,128],[-62,218],[9,321]],[[-124,219],[-62,218],[40,207],[126,174]]]}
		"shatter_spire":return {"landmark":"bastioned gun court and armored yard","roofs":[[0,98,117,66,5],[-90,78,31,38,5],[90,81,31,38,5],[-91,164,35,43,5],[88,173,36,43,5],[-36,223,61,29,1],[45,238,59,32,1],[-93,278,40,31,0],[2,304,47,33,5],[88,294,37,29,0]],"roads":[[[-144,43],[0,39],[145,45]],[[0,40],[0,168],[-9,308]],[[-130,203],[-5,187],[128,220]]]}
		"westglass_anchorage":return {"landmark":"timber storehouse, drying rack and log quay","roofs":[[0,66,58,30,1],[-52,82,34,24,0],[50,84,36,24,1],[-42,122,48,16,4],[36,124,44,16,4],[-4,154,38,24,3]],"roads":[[[-58,34],[0,30],[58,34]],[[0,22],[0,156]],[[-46,102],[0,100],[46,102]]]}
	var ind: String=industry.to_lower()
	var spec: String=specialty.to_lower()
	match ind:
		"agriculture":return {"landmark":"terraced stone granaries, threshing court and grain chute","roofs":[[-36,68,32,44,1],[0,74,32,44,1],[36,80,32,44,1],[-40,124,48,15,4],[24,128,48,15,4],[-4,156,42,24,3]],"roads":[[[-60,34],[0,30],[60,36]],[[0,22],[0,158]],[[-50,106],[0,108],[50,110]]]}
		"timber":return {"landmark":"coastal saw shed, logyard skids and timber shear crane","roofs":[[0,68,62,32,1],[-50,88,34,24,1],[48,90,34,24,0],[-32,124,54,15,4],[28,130,50,15,4],[4,158,38,24,0]],"roads":[[[-58,34],[0,32],[58,36]],[[-12,22],[-6,110],[4,160]],[[-46,110],[0,110],[46,112]]]}
		"foundry":return {"landmark":"ore calcining kiln, blast stack and slag tip quay","roofs":[[0,70,64,34,1],[-46,82,22,22,2],[46,84,22,22,2],[-34,122,40,32,1],[28,126,42,32,1],[0,158,38,24,5]],"roads":[[[-58,34],[0,30],[58,34]],[[0,22],[0,160]],[[-46,106],[0,106],[46,106]]]}
		"refinery":
			if spec=="saltpeter":
				return {"landmark":"nitrate leaching vats, drying pans and boiling house","roofs":[[0,68,56,30,1],[-44,86,28,28,2],[44,88,28,28,2],[-34,124,48,15,4],[26,126,46,15,4],[0,156,40,24,1]],"roads":[[[-58,34],[0,30],[58,34]],[[0,22],[0,158]],[[-46,106],[0,106],[46,106]]]}
			return {"landmark":"coastal still tanks, piping manifold and drum wharf","roofs":[[0,68,56,30,1],[-44,92,30,30,2],[0,100,34,34,2],[44,94,30,30,2],[-34,142,36,24,1],[30,144,36,24,0]],"roads":[[[-58,34],[0,30],[58,34]],[[-48,38],[-48,144]],[[-46,124],[0,126],[46,124]]]}
		"trade":return {"landmark":"arcaded spice factor hall, botanical frames and bale court","roofs":[[0,70,58,34,3],[-50,82,32,24,0],[50,84,32,24,0],[-34,122,46,15,4],[30,124,46,15,4],[0,154,44,24,3]],"roads":[[[-60,36],[-24,30],[24,30],[60,38]],[[0,22],[0,156]],[[-48,106],[0,106],[48,106]]]}
	return {"landmark":"working harbor","roofs":[[0,70,62,32,1],[-48,118,34,24,0],[38,136,36,26,0]],"roads":[[[-56,34],[0,30],[56,34]],[[0,24],[0,152]]]}

static func _local(plan: Dictionary,p: Vector2) -> Vector2:
	return Vector2(plan.anchor)+Vector2(plan.tangent)*p.x+Vector2(plan.inland)*p.y

static func _building_base(plan: Dictionary,at: Vector2,size: Vector2,lift: Vector2,wall: Color,first_lod: int,windows: bool=true) -> void:
	var base: PackedVector2Array=_box(at,size,plan.tangent,plan.inland)
	_paint(plan,first_lod,_box(at+Vector2(6,9),size+Vector2(5,5),plan.tangent,plan.inland),Color("526451"))
	_paint(plan,first_lod,base,wall.darkened(0.24))
	var doorway: bool=false
	for i in range(4):
		var a: Vector2=base[i];var b: Vector2=base[(i+1)%4]
		var edge: Vector2=(b-a).normalized()
		var outward:=Vector2(edge.y,-edge.x)
		if outward.dot(lift)>=0.0:continue
		var face: Color=wall.darkened(0.21) if outward.x>0.3 else wall
		_paint(plan,first_lod,PackedVector2Array([a,b,b+lift,a+lift]),face)
		_paint(plan,1,PackedVector2Array([a,b,b+lift*0.23,a+lift*0.23]),Color("687263"))
		if not windows:continue
		var count: int=2 if a.distance_to(b)<60.0 else 3
		for j in range(count):
			var center: Vector2=a.lerp(b,(float(j)+0.5)/float(count))
			var half: Vector2=edge*3.5
			_paint(plan,1,PackedVector2Array([center-half+lift*0.32,center+half+lift*0.32,center+half+lift*0.76,center-half+lift*0.76]),Color("344f50"))
			_paint(plan,2,PackedVector2Array([center-half+lift*0.29,center+half+lift*0.29,center+half+lift*0.36,center-half+lift*0.36]),Color("e0cf9f"))
		if not doorway and a.distance_to(b)>30.0:
			var center: Vector2=a.lerp(b,0.5);var half: Vector2=edge*5.0
			_paint(plan,1,PackedVector2Array([center-half,center+half,center+half+lift*0.77,center-half+lift*0.77]),Color("496152"))
			doorway=true

static func _hip_roof(plan: Dictionary,at: Vector2,size: Vector2,roof: Color,first_lod: int) -> void:
	var axis: Vector2=plan.tangent;var across: Vector2=plan.inland
	var span: float=size.x;var depth: float=size.y
	if size.y>size.x:
		axis=plan.inland;across=-Vector2(plan.tangent);span=size.y;depth=size.x
	var rim: PackedVector2Array=_box(at,Vector2(span+6,depth+6),axis,across)
	_paint(plan,first_lod,rim,Color("455951"))
	var corners: PackedVector2Array=_box(at,Vector2(span+2,depth+2),axis,across)
	var left: Vector2=at-axis*maxf(span*0.18,span*0.5-depth*0.28)
	var right: Vector2=at+axis*maxf(span*0.18,span*0.5-depth*0.28)
	# Four pitched planes meet a real ridge, rather than a line bisecting a
	# flat rectangle. World-northwest light is shared with walls and foliage.
	var north_light: bool=(-across).dot(Vector2(-0.6,-0.8))>0.0
	var end_light: bool=(-axis).dot(Vector2(-0.6,-0.8))>0.0
	_paint(plan,first_lod,PackedVector2Array([corners[0],corners[1],right,left]),roof.lightened(0.24) if north_light else roof.darkened(0.17))
	_paint(plan,first_lod,PackedVector2Array([left,right,corners[2],corners[3]]),roof.darkened(0.17) if north_light else roof.lightened(0.24))
	_paint(plan,first_lod,PackedVector2Array([corners[0],left,corners[3]]),roof.lightened(0.10) if end_light else roof.darkened(0.27))
	_paint(plan,first_lod,PackedVector2Array([corners[1],corners[2],right]),roof.darkened(0.27) if end_light else roof.lightened(0.10))
	_ribbon(plan,PackedVector2Array([left,right]),3.5,roof.lightened(0.46),1)
	if span>55.0:
		for offset in [-0.22,0.22]:
			var seam: Vector2=at+axis*span*offset
			_ribbon(plan,PackedVector2Array([seam-across*depth*0.44,seam,seam+across*depth*0.44]),2.0,roof.lightened(0.08),2)

static func _rack(plan: Dictionary,at: Vector2,size: Vector2,first_lod: int) -> void:
	var tangent: Vector2=plan.tangent;var inland: Vector2=plan.inland
	_paint(plan,first_lod,_box(at+Vector2(4,6),size+Vector2(3,3),tangent,inland),Color("586b51"))
	_paint(plan,first_lod,_box(at,size,tangent,inland),Color("706b4b"))
	for offset in [-0.38,0.0,0.38]:
		_paint(plan,1,_box(at+tangent*size.x*offset,Vector2(5,size.y+9),tangent,inland),Color("d5bd87"))
	for offset in [-0.25,0.25]:
		_paint(plan,1,_box(at+inland*size.y*offset,Vector2(size.x+4,3.5),tangent,inland),Color("d8cc9c"))
	for i in range(5):
		var p: Vector2=at+tangent*(float(i)-2.0)*size.x*0.16
		_paint(plan,1,PackedVector2Array([p-inland*size.y*0.28-tangent*2.8,p+inland*size.y*0.26-tangent*2.0,p+inland*size.y*0.36+tangent*2.2,p-inland*size.y*0.23+tangent*3.0]),Color("acb6a0"))

static func _slip(plan: Dictionary,at: Vector2,size: Vector2,first_lod: int) -> void:
	var tangent: Vector2=plan.tangent;var inland: Vector2=plan.inland
	_paint(plan,first_lod,_box(at,size+Vector2(8,4),tangent,inland),Color("b2a880"))
	_paint(plan,first_lod,_box(at,size-Vector2(7,0),tangent,inland),Color("485e59"))
	for offset in [-0.43,0.43]:
		_paint(plan,1,_box(at+tangent*size.x*offset,Vector2(4,size.y),tangent,inland),Color("d2c39b"))
	for i in range(5):
		var y: float=(float(i)-2.0)*size.y*0.17
		_paint(plan,1,_box(at+inland*y,Vector2(size.x*0.88,6),tangent,inland),Color("92794f"))
	# Timber keel and exposed ribs are a land-clipped construction landmark,
	# not a spawned boat, fake water-filled dock, or navigable silhouette.
	var keel:=PackedVector2Array()
	for p in [[0,-0.43],[0.28,-0.25],[0.30,0.30],[0.14,0.43],[-0.14,0.43],[-0.30,0.30],[-0.28,-0.25]]:
		keel.append(at+tangent*float(p[0])*size.x+inland*float(p[1])*size.y)
	_paint(plan,1,keel,Color("a3895f"))
	_paint(plan,1,_box(at,Vector2(5,size.y*0.80),tangent,inland),Color("e0c99b"))
	for i in range(5):
		var p: Vector2=at+inland*(float(i)-2.0)*size.y*0.14
		_ribbon(plan,PackedVector2Array([p-tangent*size.x*0.27-inland*5,p-tangent*size.x*0.18,p+tangent*size.x*0.18,p+tangent*size.x*0.27-inland*5]),4.0,Color("e0c99b"),1)

static func _roof(plan: Dictionary,item: Array,index: int) -> void:
	var at: Vector2=_local(plan,Vector2(item[0],item[1]))
	var size:=Vector2(item[2],item[3]);var kind: int=int(item[4])
	var tangent: Vector2=plan.tangent;var inland: Vector2=plan.inland
	var roof: Color=Color(plan.color).lightened(float(index%3)*0.045)
	if kind==1:roof=Color("6f8580")
	elif kind==3:roof=Color("b59b64")
	elif kind==5:roof=Color("7e8b80")
	var shape: PackedVector2Array=_box(at,size,tangent,inland)
	if kind==2:shape=_oval(at,size*0.5)
	var pieces: Array=Geometry2D.intersect_polygons(shape,plan.land)
	for piece in pieces:
		if plan.roofs.size()<MAX_ROOFS:plan.roofs.append(piece)
	var first_lod: int=0 if index<3 else 1
	if kind==4:
		_rack(plan,at,size,first_lod)
		return
	if plan.id=="anvil_dock" and index<2:
		_slip(plan,at,size,first_lod)
		return
	var lift:=Vector2(-3,-12 if kind==3 or kind==5 else -9)
	if kind==2:
		_paint(plan,first_lod,_oval(at+Vector2(5,7),size*0.54),Color("4e6258"))
		_paint(plan,first_lod,shape,Color("617c77"))
		_paint(plan,first_lod,_oval(at+lift,size*0.50),Color("d0cdae"))
		_paint(plan,1,_oval(at+lift+Vector2(2,2),size*0.38),Color("a3b1a0"))
		_paint(plan,1,_oval(at+lift-Vector2(3,3),size*0.22),Color("c6cdb4"))
		_paint(plan,1,_box(at+lift,Vector2(7,7),tangent,inland),Color("597b78"))
		return
	var wall: Color=Color("c5b58f") if kind==0 or kind==3 else Color("a5ae98")
	_building_base(plan,at,size,lift,wall,first_lod)
	if kind==5:
		_paint(plan,first_lod,_box(at+lift,size+Vector2(4,4),tangent,inland),Color("566962"))
		_paint(plan,1,_box(at+lift,size-Vector2(5,5),tangent,inland),Color("c0bea0"))
		_paint(plan,1,_box(at+lift,size*0.61,tangent,inland),Color("536e63"))
		_paint(plan,1,_box(at+lift-Vector2(2,3),size*0.43,tangent,inland),Color("999f7e"))
		for offset in [-0.38,0.0,0.38]:
			for side in [-1.0,1.0]:
				_paint(plan,1,_box(at+lift+tangent*size.x*offset+inland*size.y*0.44*side,Vector2(7,6),tangent,inland),Color("e0cc9c"))
		return
	_hip_roof(plan,at+lift,size,roof,first_lod)
	if kind==1:
		# The raised skylight is part of the regional roof, ahead of close seams.
		var vent: Vector2=at+lift-inland*size.y*0.17
		_paint(plan,1,_box(vent,Vector2(size.x*0.48,7),tangent,inland),Color("334f52"))
		_paint(plan,1,_box(vent-inland*3,Vector2(size.x*0.48,3),tangent,inland),Color("b8c7b1"))
	elif kind==3:
		# Open arcade on the inland-facing side of the public market/exchange.
		for offset in [-0.35,-0.12,0.12,0.35]:
			var p: Vector2=at+tangent*size.x*offset+inland*(size.y*0.5+2.0)+lift*0.45
			_paint(plan,1,_box(p,Vector2(7,10),tangent,inland),Color("344f4e"))
			_paint(plan,1,_box(p+tangent*5,Vector2(3,12),tangent,inland),Color("e4cfa0"))
	elif index%3==1:
		var chimney: Vector2=at+lift+tangent*size.x*0.21
		_paint(plan,1,_box(chimney,Vector2(6,9),tangent,inland),Color("6b6851"))
		_paint(plan,1,_box(chimney-Vector2(1,3),Vector2(8,4),tangent,inland),Color("d0b187"))

static func _work_pile(plan: Dictionary,point: Vector2,size: Vector2,color: Color) -> void:
	var at: Vector2=_local(plan,point)
	var lift:=Vector2(-2,-5)
	_building_base(plan,at,size,lift,color.darkened(0.08),1,false)
	_paint(plan,1,_box(at+lift,size,plan.tangent,plan.inland),color.lightened(0.13))
	for offset in [-0.22,0.22]:
		_paint(plan,1,_box(at+lift+Vector2(plan.tangent)*size.x*offset,Vector2(3,size.y),plan.tangent,plan.inland),color.darkened(0.22))

static func _chimney(plan: Dictionary,point: Vector2,size: Vector2,height: float,color: Color) -> void:
	var at: Vector2=_local(plan,point);var lift:=Vector2(-3,-height)
	_building_base(plan,at,size,lift,color,1,false)
	_paint(plan,1,_box(at+lift,size+Vector2(5,5),plan.tangent,plan.inland),color.lightened(0.20))
	_paint(plan,1,_box(at+lift,size*0.62,plan.tangent,plan.inland),Color("3c5351"))
	_ribbon(plan,PackedVector2Array([at+lift*0.52-Vector2(plan.tangent)*size.x*0.5,at+lift*0.52+Vector2(plan.tangent)*size.x*0.5]),3.0,color.lightened(0.25),1)

static func _gantry(plan: Dictionary,y: float) -> void:
	var left: Vector2=_local(plan,Vector2(-98,y));var right: Vector2=_local(plan,Vector2(40,y))
	var rise:=Vector2(-5,-28)
	for foot: Vector2 in [left,right]:
		_building_base(plan,foot,Vector2(13,20),rise,Color("737d63"),1,false)
		_paint(plan,1,_box(foot+rise,Vector2(16,14),plan.tangent,plan.inland),Color("d2b572"))
	_ribbon(plan,PackedVector2Array([left+rise+Vector2(2,4),right+rise+Vector2(2,4)]),10.0,Color("485d57"),1)
	_ribbon(plan,PackedVector2Array([left+rise,right+rise]),7.0,Color("d8ba76"),1)
	_ribbon(plan,PackedVector2Array([left+rise*0.30,left+rise+(right-left)*0.18]),4.0,Color("c1a56b"),1)
	_ribbon(plan,PackedVector2Array([right+rise*0.30,right+rise-(right-left)*0.18]),4.0,Color("c1a56b"),1)
	var hook: Vector2=left.lerp(right,0.57)+rise
	_ribbon(plan,PackedVector2Array([hook,hook+Vector2(0,18),hook+Vector2(6,21),hook+Vector2(8,15)]),3.0,Color("354e4e"),1)

static func _landmark(plan: Dictionary) -> void:
	var tangent: Vector2=plan.tangent;var inland: Vector2=plan.inland
	match str(plan.id):
		"brass_haven":
			# The exchange's copper clock turret anchors the opening title/home
			# composition at normal scale, above its warm roof and pale arcade.
			var tower: Vector2=_local(plan,Vector2(8,82))+Vector2(-3,-9)
			var rise:=Vector2(-3,-24)
			_building_base(plan,tower,Vector2(20,23),rise,Color("d1c297"),0,false)
			_hip_roof(plan,tower+rise,Vector2(24,27),Color("5c9083"),0)
			var clock: Vector2=tower+rise*0.45+Vector2(7,2)
			_paint(plan,1,_oval(clock,Vector2(5,5)),Color("eddbac"))
			_ribbon(plan,PackedVector2Array([clock+Vector2(0,-3),clock,clock+Vector2(3,1)]),1.8,Color("45635b"),1)
			var steps: Vector2=_local(plan,Vector2(0,51))
			_paint(plan,1,_box(steps,Vector2(66,11),tangent,inland),Color("dcd0a7"))
			_paint(plan,1,_box(steps-inland*4,Vector2(54,5),tangent,inland),Color("efe3ba"))
			_chimney(plan,Vector2(-36,28),Vector2(9,9),19.0,Color("b7a57a"))
			_paint(plan,1,_oval(_local(plan,Vector2(-36,28))+Vector2(-3,-22),Vector2(5,5)),Color("f0d78a"))
			_work_pile(plan,Vector2(-110,53),Vector2(21,17),Color("b29466"))
			_work_pile(plan,Vector2(113,55),Vector2(23,14),Color("ae8a5a"))
			_work_pile(plan,Vector2(132,78),Vector2(15,18),Color("c2aa7e"))
		"kelp_reach":
			for point in [Vector2(-58,144),Vector2(38,142)]:
				var at: Vector2=_local(plan,point)
				var crown: Vector2=at-inland*24+Vector2(-2,-8)
				for spread in [-1.0,0.0,1.0]:
					_ribbon(plan,PackedVector2Array([crown,at+tangent*spread*31+inland*12]),3.0,Color("bcc19b"),1)
				_ribbon(plan,PackedVector2Array([at-tangent*31+inland*12,at+tangent*31+inland*12]),3.0,Color("5b7861"),1)
			_chimney(plan,Vector2(-93,75),Vector2(10,12),17.0,Color("797a61"))
			_work_pile(plan,Vector2(65,53),Vector2(25,15),Color("a7ad84"))
			_work_pile(plan,Vector2(-128,127),Vector2(18,24),Color("aa9568"))
		"anvil_dock":
			for y in [58.0,171.0]:_gantry(plan,y)
			_work_pile(plan,Vector2(77,132),Vector2(29,17),Color("8d9b92"))
			_work_pile(plan,Vector2(87,224),Vector2(29,14),Color("a18758"))
		"cinder_quay":
			for x in [-73.0,79.0]:
				_chimney(plan,Vector2(x,82),Vector2(18,24),35.0,Color("796e58"))
				var mouth: Vector2=_local(plan,Vector2(x,94))
				_paint(plan,1,_box(mouth,Vector2(12,9),tangent,inland),Color("435750"))
				_paint(plan,1,_box(mouth,Vector2(7,5),tangent,inland),Color("d29a58"))
			_work_pile(plan,Vector2(62,218),Vector2(35,16),Color("9aa397"))
			_work_pile(plan,Vector2(-62,192),Vector2(32,14),Color("927c5c"))
		"sawtooth_mill":
			for y in [162.0,194.0,226.0]:
				_work_pile(plan,Vector2(-27,y),Vector2(70,12),Color("bf9b61"))
				for x in [-51.0,-27.0,-3.0]:
					_paint(plan,1,_oval(_local(plan,Vector2(x,y+5)),Vector2(4,4)),Color("dec18c"))
			var wheel: Vector2=_local(plan,Vector2(-46,70))+Vector2(-3,-8)
			_paint(plan,1,_oval(wheel,Vector2(14,14)),Color("455b54"))
			_paint(plan,1,_oval(wheel,Vector2(10,10)),Color("aa9563"))
			for dir in [Vector2(1,0),Vector2(0,1)]:
				_ribbon(plan,PackedVector2Array([wheel-dir*11,wheel+dir*11]),4.0,Color("d4bf90"),1)
			_chimney(plan,Vector2(37,71),Vector2(12,15),26.0,Color("7d7b61"))
		"silt_hollow":
			for point in [Vector2(-60,78),Vector2(0,89),Vector2(60,100)]:
				var at: Vector2=_local(plan,point+Vector2(0,33))
				_paint(plan,1,_box(at,Vector2(17,10),tangent,inland),Color("536955"))
				_paint(plan,1,_box(at+inland*6,Vector2(22,5),tangent,inland),Color("decc9a"))
			for point in [Vector2(-49,190),Vector2(-27,220),Vector2(0,250)]:
				for x in [-22.0,0.0,22.0]:
					var sack: Vector2=_local(plan,point+Vector2(x,0))
					_paint(plan,1,_oval(sack+Vector2(2,3),Vector2(10,6)),Color("837d54"))
					_paint(plan,1,_oval(sack,Vector2(8,5)),Color("dbc68e"))
		"reed_floats":
			for point in [Vector2(-76,186),Vector2(-8,207),Vector2(60,208)]:
				var at: Vector2=_local(plan,point)+Vector2(-2,-5)
				_hip_roof(plan,at,Vector2(25,18),Color("b8ac70"),1)
				_paint(plan,1,_box(at+tangent*5,Vector2(5,17),tangent,inland),Color("4f8272"))
			_work_pile(plan,Vector2(-116,105),Vector2(18,14),Color("ac9769"))
			_work_pile(plan,Vector2(114,125),Vector2(18,14),Color("b7ad7a"))
		"naphtha_bay":
			_ribbon(plan,PackedVector2Array([_local(plan,Vector2(-104,110)),_local(plan,Vector2(-105,247)),_local(plan,Vector2(78,247))]),7.0,Color("586e61"),1)
			_ribbon(plan,PackedVector2Array([_local(plan,Vector2(-104,110)),_local(plan,Vector2(-105,247)),_local(plan,Vector2(78,247))]),3.5,Color("d3b77d"),1)
			_chimney(plan,Vector2(110,174),Vector2(18,24),38.0,Color("a1ae99"))
			_chimney(plan,Vector2(110,212),Vector2(13,18),27.0,Color("8b9e90"))
			_work_pile(plan,Vector2(59,69),Vector2(28,16),Color("858f78"))
		"rust_anchorage":
			var hub: Vector2=_local(plan,Vector2(-61,157))
			_paint(plan,1,_oval(hub,Vector2(16,13)),Color("4e655b"))
			_paint(plan,1,_oval(hub-Vector2(2,3),Vector2(12,10)),Color("be9768"))
			_ribbon(plan,PackedVector2Array([hub-tangent*22,hub+tangent*22]),5.0,Color("d2b788"),1)
			for i in range(3):
				var scrap: Vector2=_local(plan,Vector2(11+float(i)*17,181+float(i%2)*8))
				_paint(plan,1,_box(scrap,Vector2(9,31),tangent+inland*0.3,inland),Color("a88d68") if i%2==0 else Color("7e9386"))
			_work_pile(plan,Vector2(-116,151),Vector2(20,16),Color("9c895f"))
			_work_pile(plan,Vector2(94,175),Vector2(22,17),Color("9d9d7b"))
		"shatter_spire":
			var wall:=PackedVector2Array()
			for p in [[-118,44],[117,44],[128,191],[73,219],[-83,207],[-118,44]]:wall.append(_local(plan,Vector2(p[0],p[1])))
			_ribbon(plan,wall,13.0,Color("455c54"),1)
			var parapet:=PackedVector2Array()
			for p in wall:parapet.append(p+Vector2(-2,-5))
			_ribbon(plan,parapet,6.0,Color("b9b795"),1)
			for x in [-71.0,71.0]:
				var gun: Vector2=_local(plan,Vector2(x,123))
				_paint(plan,1,_box(gun,Vector2(20,22),tangent,inland),Color("b3ad84"))
				_paint(plan,1,_box(gun-inland*9,Vector2(7,25),tangent,inland),Color("42615d"))
			_work_pile(plan,Vector2(-35,262),Vector2(30,17),Color("929f8b"))
		"westglass_anchorage":
			_work_pile(plan,Vector2(-38,52),Vector2(26,13),Color("bf9b61"))
			_work_pile(plan,Vector2(36,54),Vector2(24,13),Color("a7ad84"))
			for x in [-48.0,-38.0,-28.0,26.0,36.0,46.0]:
				_paint(plan,1,_oval(_local(plan,Vector2(x,56)),Vector2(3.5,3.5)),Color("dec18c"))
			var crane: Vector2=_local(plan,Vector2(18,32))
			_paint(plan,1,_box(crane,Vector2(11,11),tangent,inland),Color("637466"))
			_ribbon(plan,PackedVector2Array([crane-tangent*4,crane-inland*14+Vector2(-2,-14),crane+tangent*4]),3.2,Color("d3ba83"),1)
			var wheel_w: Vector2=_local(plan,Vector2(-28,66))+Vector2(-2,-6)
			_paint(plan,1,_oval(wheel_w,Vector2(10,10)),Color("455b54"))
			_paint(plan,1,_oval(wheel_w,Vector2(7,7)),Color("aa9563"))
		_:
			var ind: String=str(plan.get("industry","")).to_lower()
			var spec: String=str(plan.get("specialty","")).to_lower()
			match ind:
				"agriculture":
					for x in [-36.0,0.0,36.0]:
						var chute: Vector2=_local(plan,Vector2(x,46))
						_paint(plan,1,_box(chute,Vector2(13,8),tangent,inland),Color("536955"))
						_paint(plan,1,_box(chute-inland*4,Vector2(17,4),tangent,inland),Color("decc9a"))
					var thresh: Vector2=_local(plan,Vector2(-4,104))
					_paint(plan,1,_oval(thresh,Vector2(14,10)),Color("c9c093"))
					for x in [-42.0,-28.0,16.0,30.0]:
						var sack: Vector2=_local(plan,Vector2(x,126))
						_paint(plan,1,_oval(sack+Vector2(1,2),Vector2(7,4.5)),Color("837d54"))
						_paint(plan,1,_oval(sack,Vector2(6,4)),Color("dbc68e"))
				"timber":
					for y in [124.0,130.0]:
						_work_pile(plan,Vector2(-28 if y<127.0 else 26,y-18.0),Vector2(34,11),Color("bf9b61"))
						for dx in [-10.0,0.0,10.0]:
							_paint(plan,1,_oval(_local(plan,Vector2((-28.0 if y<127.0 else 26.0)+dx,y-14.0)),Vector2(3.5,3.5)),Color("dec18c"))
					var wheel_t: Vector2=_local(plan,Vector2(-30,66))+Vector2(-2,-6)
					_paint(plan,1,_oval(wheel_t,Vector2(11,11)),Color("455b54"))
					_paint(plan,1,_oval(wheel_t,Vector2(8,8)),Color("aa9563"))
					_chimney(plan,Vector2(26,68),Vector2(10,12),21.0,Color("7d7b61"))
				"foundry":
					for x in [-46.0,46.0]:
						_chimney(plan,Vector2(x,80),Vector2(14,18),27.0,Color("796e58"))
						var hearth: Vector2=_local(plan,Vector2(x,90))
						_paint(plan,1,_box(hearth,Vector2(10,7),tangent,inland),Color("435750"))
						_paint(plan,1,_box(hearth,Vector2(6,4),tangent,inland),Color("d29a58"))
					_work_pile(plan,Vector2(-32,52),Vector2(24,13),Color("a36f52"))
					_work_pile(plan,Vector2(32,54),Vector2(24,13),Color("8b968e"))
				"refinery":
					if spec=="saltpeter":
						for x in [-32.0,26.0]:
							var pan: Vector2=_local(plan,Vector2(x,54))
							_paint(plan,1,_box(pan,Vector2(26,12),tangent,inland),Color("637368"))
							_paint(plan,1,_box(pan,Vector2(22,8),tangent,inland),Color("e5e0ca"))
						_chimney(plan,Vector2(24,68),Vector2(11,14),24.0,Color("9aa595"))
					else:
						_ribbon(plan,PackedVector2Array([_local(plan,Vector2(-44,92)),_local(plan,Vector2(0,100)),_local(plan,Vector2(44,94))]),5.5,Color("586e61"),1)
						_ribbon(plan,PackedVector2Array([_local(plan,Vector2(-44,92)),_local(plan,Vector2(0,100)),_local(plan,Vector2(44,94))]),2.6,Color("d3b77d"),1)
						_chimney(plan,Vector2(34,138),Vector2(13,16),28.0,Color("9aa694"))
						_work_pile(plan,Vector2(-30,52),Vector2(22,12),Color("7b8774"))
				"trade":
					var cupola: Vector2=_local(plan,Vector2(0,70))+Vector2(-2,-8)
					_building_base(plan,cupola,Vector2(16,18),Vector2(-2,-16),Color("d2c398"),1,false)
					_hip_roof(plan,cupola+Vector2(-2,-16),Vector2(20,22),Color("5c9083"),1)
					_work_pile(plan,Vector2(-34,52),Vector2(20,12),Color("b39668"))
					_work_pile(plan,Vector2(34,52),Vector2(20,12),Color("96a889"))
				_:
					_work_pile(plan,Vector2(-32,54),Vector2(22,13),Color("b09567"))
					_work_pile(plan,Vector2(32,56),Vector2(20,12),Color("9ba483"))

static func prepare_harbor(port: Dictionary,islands: Array) -> Dictionary:
	var berth:=Vector2(float(port.x),float(port.y))
	var best: float=INF;var anchor: Vector2=berth;var inland:=Vector2.LEFT
	var land:=PackedVector2Array()
	for island in islands:
		var ring: PackedVector2Array=_ring(island.get("points",[]))
		for i in range(ring.size()):
			var a: Vector2=ring[i];var b: Vector2=ring[(i+1)%ring.size()]
			var at: Vector2=Geometry2D.get_closest_point_to_segment(berth,a,b)
			var distance: float=at.distance_squared_to(berth)
			if distance>=best:continue
			best=distance;anchor=at;land=ring
			inland=(b-a).orthogonal().normalized()
			if not Geometry2D.is_point_in_polygon(anchor+inland*3.0,ring):inland=-inland
	var plan: Dictionary=_new(land)
	plan.origin=anchor
	plan.id=str(port.id);plan.industry=str(port.get("industry",""));plan.specialty=str(port.get("specialty",""))
	plan.anchor=anchor;plan.berth=berth;plan.inland=inland;plan.tangent=inland.orthogonal()
	plan.caption=harbor_caption(port);plan.roofs=[]
	plan.color=Color("a77d59")
	if str(port.get("faction",""))=="forge":plan.color=Color("a66c51")
	elif str(port.get("faction",""))=="reed":plan.color=Color("779382")
	elif str(port.get("faction",""))=="raiders":plan.color=Color("8d7163")
	var design: Dictionary=_harbor_design(plan.id,plan.industry,plan.specialty)
	plan.landmark=design.landmark
	if land.size()<3:return _finish(plan)
	var is_remote: bool=not _is_home_port(plan.id)
	# Paving remains on actual land; the real berth connector below stays ink.
	var footing:=PackedVector2Array()
	var foot_pts: Array=[[-64,6],[64,6],[68,18],[-68,18]] if is_remote else [[-140,7],[138,8],[144,21],[-144,21]]
	for p in foot_pts:footing.append(_local(plan,Vector2(p[0],p[1])))
	_paint(plan,1,footing,Color("556760"))
	var apron:=PackedVector2Array()
	var apron_pts: Array=[[-68,14],[68,14],[74,42],[0,46],[-72,42]] if is_remote else [[-146,17],[141,18],[151,51],[98,60],[-36,45],[-149,57]]
	for p in apron_pts:apron.append(_local(plan,Vector2(p[0],p[1])))
	_paint(plan,1,apron,Color("b3ac87"))
	var court:=PackedVector2Array()
	var court_pts: Array=[[-32,16],[32,16],[36,36],[-36,36]] if is_remote else [[-54,19],[54,19],[58,44],[-58,44]]
	for p in court_pts:court.append(_local(plan,Vector2(p[0],p[1])))
	_paint(plan,1,court,Color("cac19b"))
	var cope_x: float=62.0 if is_remote else 138.0
	var cope_y: float=20.0 if is_remote else 22.0
	_ribbon(plan,PackedVector2Array([_local(plan,Vector2(-cope_x,cope_y)),_local(plan,Vector2(cope_x,cope_y+1.0))]),5.0,Color("dbcca0"),1)
	for bx in [-16.0,16.0]:
		var bastion: Vector2=_local(plan,Vector2(bx,cope_y-2.0))
		_paint(plan,1,_box(bastion,Vector2(8,7),plan.tangent,plan.inland),Color("dfd2a8"))
		_paint(plan,1,_box(bastion,Vector2(3.5,3.5),plan.tangent,plan.inland),Color("3e5250"))
	for road in design.roads:
		var points:=PackedVector2Array()
		for p in road:points.append(_local(plan,Vector2(p[0],p[1])))
		_ribbon(plan,points,14.0,Color("6e7e65"),0)
		_ribbon(plan,points,8.0,Color("c5bb95"),1)
	for i in range(mini(MAX_ROOFS,design.roofs.size())):_roof(plan,design.roofs[i],i)
	_landmark(plan)
	# Existing real berth connector remains chart ink, with an open quay symbol.
	# No filled pier / breakwater extends the actual land collision silhouette.
	var head_span: float=7.0 if is_remote else 8.0
	plan.pier=PackedVector2Array([anchor+inland*10.0,anchor,berth,berth+plan.tangent*head_span,berth-plan.tangent*head_span])
	var extent:=PackedVector2Array([anchor,berth])
	for p in [Vector2(-180,0),Vector2(180,0),Vector2(180,340),Vector2(-180,340)]:extent.append(_local(plan,p))
	plan.bounds=_bounds(extent).grow(60)
	return _finish(plan)

static func _screen_bounds(projector: Callable,bounds: Rect2) -> Rect2:
	var corners:=PackedVector2Array()
	for p in [bounds.position,bounds.position+Vector2(bounds.size.x,0),bounds.end,bounds.position+Vector2(0,bounds.size.y)]:
		corners.append(projector.call(p,0.0))
	return _bounds(corners)

static func draw(canvas,projector: Callable,plan: Dictionary,chart_scale: float=0.6,viewport: Rect2=Rect2()) -> int:
	if plan.is_empty() or plan.land.size()<3:return 0
	if viewport.has_area() and not viewport.grow(12).intersects(_screen_bounds(projector,plan.bounds)):return 0
	var level: int=lod(chart_scale)
	var batch: Dictionary=plan.levels[level]
	var origin: Vector2=plan.origin
	var zero: Vector2=projector.call(origin,0.0)
	var x: Vector2=projector.call(origin+Vector2(100,0),0.0)
	var y: Vector2=projector.call(origin+Vector2(0,100),0.0)
	canvas.draw_set_transform_matrix(Transform2D((x-zero)/100.0,(y-zero)/100.0,zero))
	canvas.draw_mesh(batch.mesh,null)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	var calls: int=1
	if not plan.outline.is_empty():
		var outline:=PackedVector2Array()
		for p in plan.outline:outline.append(projector.call(p,0.0))
		# Softer, thinner waterline than the old even rim stroke.
		canvas.draw_polyline(outline,Color(0.81,0.82,0.64,0.46),1.0 if level>0 else 1.4,true);calls+=1
	if level>0 and not plan.reef.is_empty():
		var reef:=PackedVector2Array()
		for p in plan.reef:reef.append(projector.call(p,0.0))
		if canvas.has_method("draw_multiline"):
			canvas.draw_multiline(reef,Color(0.60,0.77,0.68,0.24),1.1,true);calls+=1
		else:
			# The existing source-capture Recorder predates draw_multiline.
			for i in range(0,reef.size(),2):
				canvas.draw_line(reef[i],reef[i+1],Color(0.60,0.77,0.68,0.24),1.1,true);calls+=1
	if not plan.pier.is_empty():
		var pier:=PackedVector2Array()
		for p in plan.pier:pier.append(projector.call(p,0.0))
		canvas.draw_polyline(pier,Color("72664c"),4.0 if level>0 else 2.0,true)
		canvas.draw_polyline(pier,Color("d7c7a0"),1.5 if level>0 else 1.0,true);calls+=2
	return calls
