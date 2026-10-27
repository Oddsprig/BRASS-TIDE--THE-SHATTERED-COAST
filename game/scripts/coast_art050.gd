extends RefCounted
## Original, flat nautical artwork over the real coast. Preparation is a scene /
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
	for p in source:result.append(Vector2(float(p[0]),float(p[1])))
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
		"isl_lantern":return {"biome":"chalk headland / orchard coast","ground":"899470","rock":"a6a18a","leaf":"42684d","beach":[[0.0,0.30],[0.48,0.61]],"ridge":[[0.14,0.12],[0.24,0.28],[0.38,0.39],[0.46,0.55],[0.31,0.77]],"groves":[[0.25,0.28],[0.36,0.42],[0.28,0.61],[0.19,0.80],[0.52,0.38]],"fields":false}
		"isl_kelp":return {"biome":"tidal reedbanks / salt meadow","ground":"819779","rock":"aab19a","leaf":"527c5c","beach":[[0.0,0.41],[0.72,0.86]],"ridge":[[0.22,0.20],[0.34,0.40],[0.53,0.57],[0.40,0.76]],"groves":[[0.21,0.31],[0.36,0.48],[0.53,0.55],[0.34,0.72],[0.18,0.70]],"fields":true}
		"isl_sawtooth":return {"biome":"ironwood slopes / pale crags","ground":"7b8b6b","rock":"aaa996","leaf":"365947","beach":[[0.08,0.25]],"ridge":[[0.19,0.22],[0.34,0.34],[0.47,0.46],[0.60,0.61],[0.69,0.78]],"groves":[[0.23,0.29],[0.35,0.40],[0.49,0.57],[0.62,0.65],[0.76,0.20]],"fields":false}
		"isl_verdigris":return {"biome":"polder terraces / windbreaks","ground":"9ca478","rock":"c0b98e","leaf":"567650","beach":[[0.0,0.18],[0.36,0.53]],"ridge":[[0.43,0.19],[0.48,0.36],[0.62,0.52],[0.69,0.72]],"groves":[[0.43,0.20],[0.50,0.36],[0.68,0.56],[0.76,0.74]],"fields":true}
		"isl_cinder":return {"biome":"ash spine / quarried red cliffs","ground":"8d856c","rock":"9d7961","leaf":"566b50","beach":[[0.60,0.76]],"ridge":[[0.56,0.18],[0.46,0.36],[0.58,0.52],[0.45,0.72],[0.57,0.87]],"groves":[[0.52,0.28],[0.55,0.45],[0.45,0.60]],"fields":false}
		"isl_fen":return {"biome":"reed fen / wooded levees","ground":"829c79","rock":"a8b28d","leaf":"3e7455","beach":[[0.0,0.25],[0.45,0.70]],"ridge":[[0.47,0.13],[0.55,0.32],[0.49,0.45],[0.34,0.61],[0.24,0.80]],"groves":[[0.46,0.23],[0.58,0.40],[0.30,0.63],[0.24,0.79],[0.73,0.61]],"fields":true}
		"isl_oilstone":return {"biome":"slate benches / dry scrub","ground":"8e927e","rock":"7f8d89","leaf":"63745b","beach":[[0.09,0.25],[0.69,0.80]],"ridge":[[0.22,0.28],[0.38,0.40],[0.53,0.57],[0.65,0.74]],"groves":[[0.32,0.28],[0.40,0.44],[0.62,0.59],[0.73,0.38]],"fields":false}
		"isl_shatter":return {"biome":"basalt teeth / burnt heath","ground":"85866b","rock":"6c7775","leaf":"4f6550","beach":[[0.43,0.57]],"ridge":[[0.44,0.16],[0.32,0.34],[0.26,0.53],[0.45,0.71],[0.65,0.78]],"groves":[[0.43,0.29],[0.33,0.48],[0.38,0.68],[0.62,0.73]],"fields":false}
	return {"biome":"rocky coastal heath","ground":"82956b","rock":"a3a48b","leaf":"466b50","beach":[[0.0,0.25]],"ridge":[[0.30,0.30],[0.50,0.50],[0.65,0.65]],"groves":[[0.40,0.40]],"fields":false}

static func _shore(plan: Dictionary,profile: Dictionary) -> void:
	var land: PackedVector2Array=plan.land
	for i in range(land.size()):
		var a: Vector2=land[i];var b: Vector2=land[(i+1)%land.size()]
		var middle: Vector2=(a+b)*0.5
		var inward: Vector2=(b-a).orthogonal().normalized()
		if not Geometry2D.is_point_in_polygon(middle+inward*3.0,land):inward=-inward
		var sand: bool=false
		for span in profile.beach:
			if float(i)/land.size()>=float(span[0]) and float(i)/land.size()<=float(span[1]):sand=true
		var width: float=(32.0+float(i%4)*6.0) if sand else (18.0+float(i%3)*8.0)
		_paint(plan,0,PackedVector2Array([a,b,b+inward*width,a+inward*width]),Color("d5c79b") if sand else Color(profile.rock).darkened(0.27))
		_paint(plan,1,PackedVector2Array([a+inward*(width-4),b+inward*(width-4),b+inward*(width+4),a+inward*(width+4)]),Color("b6b58a") if sand else Color(profile.rock).lightened(0.16))
		# Deliberately transparent, broken seabed hatching rather than opaque
		# rocks on water a captain is allowed to cross. It has no blocking meaning.
		if sand and i%4==0 and plan.reef.size()<MAX_REEF_SEGMENTS*2:
			var along: Vector2=(b-a).normalized()*22.0
			var at: Vector2=middle-inward*(64.0+float(i%3)*18.0)
			plan.reef.append(at-along);plan.reef.append(at+along)

static func _grove(plan: Dictionary,at: Vector2,radius: float,leaf: Color,wet: bool) -> void:
	_paint(plan,1,_oval(at+Vector2(8,12),Vector2(radius,radius*0.63)),leaf.darkened(0.15))
	_paint(plan,1,_oval(at,Vector2(radius*0.90,radius*0.59)),leaf)
	var offsets: Array=[[-0.52,-0.12],[-0.19,-0.32],[0.19,-0.29],[0.52,-0.04],[-0.31,0.17],[0.03,0.10],[0.37,0.21]]
	for i in range(offsets.size()):
		var p: Vector2=at+Vector2(offsets[i][0],offsets[i][1])*radius
		var r: float=radius*(0.20+float(i%3)*0.025)
		if wet:
			for dx in [-7.0,0.0,7.0]:
				_paint(plan,2,PackedVector2Array([p+Vector2(dx-2,12),p+Vector2(dx+3,-r),p+Vector2(dx+4,12)]),leaf.lightened(0.17))
		else:
			_paint(plan,2,_oval(p+Vector2(3,6),Vector2(r,r*0.74)),leaf.darkened(0.24))
			_paint(plan,2,_oval(p,Vector2(r,r*0.69)),leaf.lightened(0.10+float(i%2)*0.07))

static func prepare_island(island: Dictionary) -> Dictionary:
	var land: PackedVector2Array=_ring(island.get("points",[]))
	var plan: Dictionary=_new(land)
	plan.id=str(island.get("id",""));plan.name=str(island.get("name","Coast"))
	var profile: Dictionary=_profile(plan.id)
	plan.biome=profile.biome;plan.ground=Color(profile.ground);plan.roofs=[]
	if land.size()<3:return _finish(plan)
	_paint(plan,0,land,plan.ground,false)
	var bounds: Rect2=plan.bounds
	var ridge: PackedVector2Array=_mapped(bounds,profile.ridge)
	var breadth: float=minf(bounds.size.x,bounds.size.y)
	_ribbon(plan,ridge,breadth*0.24,Color(profile.rock).darkened(0.14),0)
	_ribbon(plan,ridge,breadth*0.12,Color(profile.rock).lightened(0.06),0)
	for i in range(1,ridge.size()):
		var at: Vector2=ridge[i];var prior: Vector2=ridge[i-1]
		var side: Vector2=(at-prior).normalized().orthogonal()*breadth*0.10
		_paint(plan,1,PackedVector2Array([prior-side,at,at+side*0.65]),Color(profile.rock).lightened(0.18))
		_paint(plan,1,PackedVector2Array([prior-side,at,prior-side*1.65]),Color(profile.rock).darkened(0.22))
		_ribbon(plan,PackedVector2Array([prior,at]),5.0,Color(profile.rock).lightened(0.33),2)
	_shore(plan,profile)
	if bool(profile.fields):
		# Contour-following strips are land crops / salt meadow, never extra water.
		for i in range(5):
			var center: Vector2=bounds.position+bounds.size*Vector2(0.34+float(i)*0.045,0.37+float(i)*0.09)
			_paint(plan,1,_box(center,Vector2(breadth*0.27,breadth*0.055)),Color("b4b58a") if i%2==0 else Color("9ca873"))
			_ribbon(plan,PackedVector2Array([center-Vector2(breadth*0.135,0),center+Vector2(breadth*0.135,0)]),3.0,Color("74875e"),2)
	var wet: bool=plan.id in ["isl_kelp","isl_fen","isl_verdigris"]
	for at: Vector2 in _mapped(bounds,profile.groves):_grove(plan,at,breadth*(0.075 if wet else 0.085),Color(profile.leaf),wet)
	plan.outline=land.duplicate();plan.outline.append(land[0])
	plan.label=bounds.get_center()
	if not Geometry2D.is_point_in_polygon(plan.label,land):
		var triangles: PackedInt32Array=Geometry2D.triangulate_polygon(land)
		if triangles.size()>=3:plan.label=(land[triangles[0]]+land[triangles[1]]+land[triangles[2]])/3.0
	# Include the offshore ink in the draw-culling bounds, never in the land ring.
	for p in plan.reef:plan.bounds=Rect2(plan.bounds).expand(p)
	return _finish(plan)

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
	return str(port.get("industry","harbor")).to_upper()

static func _harbor_design(id: String) -> Dictionary:
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
	return {"landmark":"working harbor","roofs":[[0,78,78,41,1],[-66,144,38,27,0],[42,183,41,29,0]],"roads":[[[0,30],[0,220]]]}

static func _local(plan: Dictionary,p: Vector2) -> Vector2:
	return Vector2(plan.anchor)+Vector2(plan.tangent)*p.x+Vector2(plan.inland)*p.y

static func _roof(plan: Dictionary,item: Array,index: int) -> void:
	var at: Vector2=_local(plan,Vector2(item[0],item[1]))
	var size:=Vector2(item[2],item[3]);var kind: int=int(item[4])
	var tangent: Vector2=plan.tangent;var inland: Vector2=plan.inland
	var roof: Color=plan.color
	if kind==1:roof=Color("727d79")
	elif kind==3:roof=Color("b19a6d")
	elif kind==5:roof=Color("697875")
	var shape: PackedVector2Array=_box(at,size,tangent,inland)
	if kind==2:shape=_oval(at,size*0.5)
	var pieces: Array=Geometry2D.intersect_polygons(shape,plan.land)
	for piece in pieces:
		if plan.roofs.size()<MAX_ROOFS:plan.roofs.append(piece)
	var first_lod: int=0 if index<3 else 1
	_paint(plan,first_lod,_box(at+tangent*5+inland*7,size,tangent,inland),Color("4d5d51"))
	_paint(plan,first_lod,shape,roof)
	if kind==2:
		_paint(plan,1,_oval(at-Vector2(3,4),size*0.37),Color("c1c3a6"))
		_paint(plan,2,_box(at,Vector2(9,9),tangent,inland),Color("5d7773"))
	else:
		_paint(plan,first_lod,_box(at-tangent*size.x*0.25,Vector2(size.x*0.5,size.y),tangent,inland),roof.lightened(0.16))
		_paint(plan,1,_box(at,Vector2(2,size.y),tangent,inland),Color("d6c29a"))
		if kind==4:
			for offset in [-0.3,0.0,0.3]:_paint(plan,2,_box(at+tangent*size.x*offset,Vector2(3,size.y),tangent,inland),Color("d4bd8b"))
		elif kind==5:
			_paint(plan,1,_box(at,size*0.64,tangent,inland),Color("9a9b7e"))
		elif kind==1:
			_paint(plan,2,_box(at-inland*size.y*0.12,Vector2(size.x*0.52,4),tangent,inland),Color("a9b7ac"))
		elif kind==3:
			# Public exchange / market arcade, distinct from a warehouse roof.
			for offset in [-0.36,-0.12,0.12,0.36]:
				_paint(plan,1,_box(at+tangent*size.x*offset-inland*size.y*0.36,Vector2(5,8),tangent,inland),Color("e0d0a9"))

static func _landmark(plan: Dictionary) -> void:
	var tangent: Vector2=plan.tangent;var inland: Vector2=plan.inland
	match str(plan.id):
		"anvil_dock":
			for y in [58.0,171.0]:
				_paint(plan,1,_box(_local(plan,Vector2(-29,y)),Vector2(137,8),tangent,inland),Color("c4ad70"))
				for x in [-98.0,40.0]:_paint(plan,1,_box(_local(plan,Vector2(x,y)),Vector2(12,25),tangent,inland),Color("4d6263"))
		"cinder_quay":
			for x in [-73.0,79.0]:
				_paint(plan,1,_box(_local(plan,Vector2(x,82)),Vector2(12,38),tangent,inland),Color("4b5550"))
				_paint(plan,2,_box(_local(plan,Vector2(x,64)),Vector2(16,11),tangent,inland),Color("c68a57"))
		"naphtha_bay":
			_ribbon(plan,PackedVector2Array([_local(plan,Vector2(-104,110)),_local(plan,Vector2(-105,247)),_local(plan,Vector2(78,247))]),4.0,Color("d3b77d"),1)
		"shatter_spire":
			var wall:=PackedVector2Array()
			for p in [[-118,44],[117,44],[128,191],[73,219],[-83,207],[-118,44]]:wall.append(_local(plan,Vector2(p[0],p[1])))
			_ribbon(plan,wall,9.0,Color("515e59"),1)
		"sawtooth_mill":
			for y in [162.0,194.0,226.0]:
				_paint(plan,1,_box(_local(plan,Vector2(-27,y)),Vector2(70,8),tangent,inland),Color("ba945c"))

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
	var design: Dictionary=_harbor_design(plan.id)
	plan.landmark=design.landmark
	if land.size()<3:return _finish(plan)
	for road in design.roads:
		var points:=PackedVector2Array()
		for p in road:points.append(_local(plan,Vector2(p[0],p[1])))
		_ribbon(plan,points,14.0,Color("6e7e65"),0)
		_ribbon(plan,points,8.0,Color("c5bb95"),1)
	for i in range(mini(MAX_ROOFS,design.roofs.size())):_roof(plan,design.roofs[i],i)
	_landmark(plan)
	# Existing real berth connector remains chart ink, with an open quay symbol.
	# No filled pier / breakwater extends the actual land collision silhouette.
	plan.pier=PackedVector2Array([anchor,berth])
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
		canvas.draw_polyline(outline,Color("dfd2a6"),1.4 if level>0 else 1.8,true);calls+=1
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
