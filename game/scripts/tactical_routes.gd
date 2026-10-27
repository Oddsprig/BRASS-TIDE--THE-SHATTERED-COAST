extends RefCounted
## Battle-local geometry. No Battle dependency, live callbacks or campaign routes.
const WIDTH: float=2300.0
const HEIGHT: float=1700.0
const CACHE_LIMIT: int=128
const GRID_QUERY_LIMIT: int=128
const BEGIN_PROOF_LIMIT051: int=512

class _BeginProofs051 extends RefCounted:
	var active: bool=true
	var geometry: Dictionary={}
	var obstacles: Array=[]
	var geometry_stamp: PackedByteArray=PackedByteArray()
	var cells: Dictionary={}
	var owners: Dictionary={}
	var entries: Dictionary={}

static func _begin_proofs051(geometry: Dictionary,cells: Dictionary,owners: Dictionary) -> _BeginProofs051:
	# Runtime.begin alone owns this closed, synchronous observation scope. None
	# of these geometry/ship observations move or mutate during certification.
	var proofs: _BeginProofs051=_BeginProofs051.new()
	proofs.geometry=geometry;proofs.obstacles=geometry.obstacles
	proofs.geometry_stamp=var_to_bytes([geometry.key,geometry.revision])
	proofs.cells=cells;proofs.owners=owners.duplicate()
	return proofs

static func _close_begin_proofs051(proofs: _BeginProofs051) -> void:
	proofs.active=false;proofs.entries.clear();proofs.owners.clear()
	proofs.geometry={};proofs.obstacles=[];proofs.cells={}

static func _proof_scope051(proofs: _BeginProofs051,geometry: Dictionary,cells: Dictionary,ship: Dictionary) -> bool:
	return proofs!=null and proofs.active and is_same(proofs.geometry,geometry) and is_same(proofs.obstacles,geometry.obstacles) and is_same(proofs.cells,cells) and proofs.geometry_stamp==var_to_bytes([geometry.key,geometry.revision]) and proofs.owners.has(str(ship.id)) and is_same(proofs.owners[str(ship.id)],ship)

static func _proof_spend051(budget: Dictionary,debits: Array[int],count: int=1) -> bool:
	if not spend(budget,count):return false
	debits.append(count)
	return true

static func _proof_replay051(proof: Dictionary,budget: Dictionary) -> String:
	# Keep individual spend(2) boundaries and the first refusal, not a summed
	# debit: finite work, exhaustions and subsequent fair slots must be identical.
	for count: int in proof.debits:
		if not spend(budget,count):return "pending"
	return str(proof.status)

static func _proof_store051(proofs: _BeginProofs051,key: String,status: String,debits: Array[int]) -> void:
	if status not in ["valid","blocked"]:return
	debits.make_read_only()
	var proof: Dictionary={"status":status,"debits":debits}
	proof.make_read_only();proofs.entries[key]=proof

static func _sweep_begin051(proofs: _BeginProofs051,ship: Dictionary,geometry: Dictionary,a: Vector2,b: Vector2,r: float,budget: Dictionary) -> String:
	# Context identities are checked at _refine_begin051. Typed bytes preserve
	# exact ordered endpoints/radii; no rounded keys or hash-only equality.
	var key: String=var_to_bytes(["terrain",str(ship.id),proofs.geometry_stamp,a,b,r]).hex_encode()
	if proofs.entries.has(key):return _proof_replay051(proofs.entries[key],budget)
	if proofs.entries.size()>=BEGIN_PROOF_LIMIT051:return sweep(geometry,a,b,r,budget)
	var debits: Array[int]=[]
	var status: String=_sweep_record051(geometry,a,b,r,budget,debits)
	_proof_store051(proofs,key,status,debits)
	return status

static func _occupied_begin051(proofs: _BeginProofs051,cells: Dictionary,ship: Dictionary,a: Vector2,b: Vector2,r: float,from: float,until: float,budget: Dictionary,avoid_hostiles: bool=false,contact_id: String="") -> String:
	var own_navigation: float=maxf(r,navigation_radius(ship)) if avoid_hostiles else r
	var key: String=var_to_bytes(["traffic",str(ship.id),str(ship.team),proofs.geometry_stamp,a,b,r,from,until,own_navigation,contact_id,avoid_hostiles]).hex_encode()
	if proofs.entries.has(key):return _proof_replay051(proofs.entries[key],budget)
	if proofs.entries.size()>=BEGIN_PROOF_LIMIT051:return occupied(cells,ship,a,b,r,from,until,budget,avoid_hostiles,contact_id)
	var debits: Array[int]=[]
	var status: String=_occupied_record051(cells,ship,a,b,r,from,until,budget,avoid_hostiles,contact_id,debits)
	_proof_store051(proofs,key,status,debits)
	return status

static func spend(budget: Dictionary, count: int=1) -> bool:
	if int(budget.clearanceTests)+count>int(budget.get("clearanceLimit",4096)):
		budget.exhaustions+=1
		return false
	budget.clearanceTests+=count
	return true

static func point(s: Dictionary) -> Vector2:
	return Vector2(float(s.x),float(s.y))

static func planning_radius(ship: Dictionary) -> float:
	var spec: Dictionary=ship.spec
	# A quarter of the fitted full-speed turning radius leaves room to set up a turn.
	# This is route clearance only; collisions and the real helm keep physical size.
	var allowance: float=clampf(maxf(0.0,float(spec.get("speed",90)))/maxf(0.1,float(spec.get("turn",1.8)))*0.25,0.0,64.0)
	return maxf(10.0,float(spec.get("size",16)))+4.0+allowance

static func navigation_radius(ship: Dictionary) -> float:
	# Art hull stations extend to 2.65*size. Use a conservative heading-free
	# envelope for hostile navigation; physical contacts and firing keep theirs.
	return maxf(10.0,float(ship.spec.get("size",16)))*2.75

static func contact_target(ship: Dictionary) -> String:
	return str(ship.get("orderTarget",{}).get("shipId","")) if str(ship.get("order","")) in ["board","ram"] else ""

static func distance(p: Vector2,a: Vector2,b: Vector2) -> float:
	var d: Vector2=b-a
	return p.distance_to(a+d*clampf((p-a).dot(d)/maxf(0.000001,d.length_squared()),0.0,1.0))

static func inside(p: Vector2,vertices: Array) -> bool:
	var yes: bool=false
	var j: int=vertices.size()-1
	for i in range(vertices.size()):
		var a: Vector2=Vector2(vertices[i][0],vertices[i][1])
		var b: Vector2=Vector2(vertices[j][0],vertices[j][1])
		if (a.y>p.y)!=(b.y>p.y) and p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x:yes=not yes
		j=i
	return yes

static func segment_distance(a: Vector2,b: Vector2,c: Vector2,d: Vector2) -> float:
	var ab: Vector2=b-a
	var cd: Vector2=d-c
	var den: float=ab.cross(cd)
	if absf(den)>0.0000001:
		var t: float=(c-a).cross(cd)/den
		var u: float=(c-a).cross(ab)/den
		if t>=0.0 and t<=1.0 and u>=0.0 and u<=1.0:return 0.0
	return minf(minf(distance(a,c,d),distance(b,c,d)),minf(distance(c,a,b),distance(d,a,b)))

static func terrain(st: Dictionary) -> Dictionary:
	var key: String=JSON.stringify(st.get("islands",[])).sha256_text()
	var t: Dictionary=st.tactical
	if t.get("terrainKey","")!=key:
		t.terrainKey=key;t.terrainRevision=int(t.get("terrainRevision",0))+1
		t.routeCache={}
		t.obstacles=[]
		for island in st.get("islands",[]):
			var vertices: Array=island.get("points",[])
			if vertices.size()<3:continue
			var lo: Vector2=Vector2(INF,INF)
			var hi: Vector2=Vector2(-INF,-INF)
			for p in vertices:
				lo=lo.min(Vector2(p[0],p[1]));hi=hi.max(Vector2(p[0],p[1]))
			t.obstacles.append({"points":vertices.duplicate(true),"lo":lo,"hi":hi})
	return {"revision":int(t.terrainRevision),"key":key,"obstacles":t.obstacles}

static func sweep(geometry: Dictionary,a: Vector2,b: Vector2,r: float,budget: Dictionary) -> String:
	if not spend(budget):return "pending"
	if not a.is_finite() or not b.is_finite() or minf(a.x,b.x)<r or maxf(a.x,b.x)>WIDTH-r or minf(a.y,b.y)<r or maxf(a.y,b.y)>HEIGHT-r:return "blocked"
	var lo: Vector2=a.min(b)-Vector2.ONE*r
	var hi: Vector2=a.max(b)+Vector2.ONE*r
	for obstacle in geometry.obstacles:
		if not spend(budget):return "pending"
		if hi.x<float(obstacle.lo.x) or hi.y<float(obstacle.lo.y) or lo.x>float(obstacle.hi.x) or lo.y>float(obstacle.hi.y):continue
		var vertices: Array=obstacle.points
		if not spend(budget,2):return "pending"
		if inside(a,vertices) or inside(b,vertices):return "blocked"
		for i in range(vertices.size()):
			if not spend(budget):return "pending"
			var c: Vector2=Vector2(vertices[i][0],vertices[i][1])
			var d: Vector2=Vector2(vertices[(i+1)%vertices.size()][0],vertices[(i+1)%vertices.size()][1])
			if segment_distance(a,b,c,d)<r+0.001:return "blocked"
	return "valid"

# These two private recorders mirror the unchanged public reference checks;
# only spend recording differs. Pending walks never create a terminal proof.
static func _sweep_record051(geometry: Dictionary,a: Vector2,b: Vector2,r: float,budget: Dictionary,debits: Array[int]) -> String:
	if not _proof_spend051(budget,debits):return "pending"
	if not a.is_finite() or not b.is_finite() or minf(a.x,b.x)<r or maxf(a.x,b.x)>WIDTH-r or minf(a.y,b.y)<r or maxf(a.y,b.y)>HEIGHT-r:return "blocked"
	var lo: Vector2=a.min(b)-Vector2.ONE*r
	var hi: Vector2=a.max(b)+Vector2.ONE*r
	for obstacle in geometry.obstacles:
		if not _proof_spend051(budget,debits):return "pending"
		if hi.x<float(obstacle.lo.x) or hi.y<float(obstacle.lo.y) or lo.x>float(obstacle.hi.x) or lo.y>float(obstacle.hi.y):continue
		var vertices: Array=obstacle.points
		if not _proof_spend051(budget,debits,2):return "pending"
		if inside(a,vertices) or inside(b,vertices):return "blocked"
		for i in range(vertices.size()):
			if not _proof_spend051(budget,debits):return "pending"
			var c: Vector2=Vector2(vertices[i][0],vertices[i][1])
			var d: Vector2=Vector2(vertices[(i+1)%vertices.size()][0],vertices[(i+1)%vertices.size()][1])
			if segment_distance(a,b,c,d)<r+0.001:return "blocked"
	return "valid"

static func grid(ships: Array,reuse_queries: bool=false) -> Dictionary:
	var cells: Dictionary={"_maxSpeed":0.0,"_maxNavigationRadius":0.0}
	# Only Runtime's synchronous observation/post-motion phases opt in. Cell
	# membership is fixed until the next grid build; no result survives that build.
	if reuse_queries:cells._queryCache={}
	for ship in ships:
		if ship.get("sunk",false) or ship.get("captureSecured",false):continue
		var r: float=maxf(10.0,float(ship.spec.get("size",16)))
		cells._maxNavigationRadius=maxf(float(cells._maxNavigationRadius),r*2.75)
		cells._maxSpeed=maxf(float(cells._maxSpeed),Vector2(ship.vx,ship.vy).length())
		var future: Vector2=point(ship)+Vector2(ship.vx,ship.vy)*2.0
		var lo: Vector2=point(ship).min(future)-Vector2.ONE*(r+8.0)
		var hi: Vector2=point(ship).max(future)+Vector2.ONE*(r+8.0)
		for x in range(maxi(-2,floori(lo.x/160.0)),mini(17,floori(hi.x/160.0))+1):
			for y in range(maxi(-2,floori(lo.y/160.0)),mini(13,floori(hi.y/160.0))+1):
				var cell: Vector2i=Vector2i(x,y)
				if not cells.has(cell):cells[cell]=[]
				cells[cell].append(ship)
	return cells

static func neighbours(cells: Dictionary,a: Vector2,b: Vector2,r: float) -> Array:
	# Public callers own the Array, as before. Entries remain the original hull
	# references, so live narrow-phase checks never borrow old poses/conditions.
	var result: Array=_neighbours(cells,a,b,r)
	return result.duplicate() if cells.has("_queryCache") else result

static func _neighbours(cells: Dictionary,a: Vector2,b: Vector2,r: float) -> Array:
	var lo: Vector2=a.min(b)-Vector2.ONE*r
	var hi: Vector2=a.max(b)+Vector2.ONE*r
	var min_x: int=maxi(-2,floori(lo.x/160.0))
	var max_x: int=mini(17,floori(hi.x/160.0))
	var min_y: int=maxi(-2,floori(lo.y/160.0))
	var max_y: int=mini(13,floori(hi.y/160.0))
	# neighbours has no geometric filter after this exact inclusive cell window.
	# Identical windows therefore have identical membership AND discovery order.
	var query: Vector4i=Vector4i(min_x,max_x,min_y,max_y)
	var shared: bool=cells.has("_queryCache")
	if shared and cells._queryCache.has(query):return cells._queryCache[query]
	var result: Array=[]
	var seen: Dictionary={}
	for x in range(min_x,max_x+1):
		for y in range(min_y,max_y+1):
			for other in cells.get(Vector2i(x,y),[]):
				if not seen.has(str(other.id)):
					seen[str(other.id)]=true;result.append(other)
	if shared and cells._queryCache.size()<GRID_QUERY_LIMIT:
		result.make_read_only()
		cells._queryCache[query]=result
	return result

static func occupied(cells: Dictionary,ship: Dictionary,a: Vector2,b: Vector2,r: float,from: float,until: float,budget: Dictionary,avoid_hostiles: bool=false,contact_id: String="") -> String:
	var extra: float=maxf(0.0,until-2.0)*float(cells.get("_maxSpeed",0.0))
	var query_radius: float=r+80.0+extra
	var own_navigation: float=maxf(r,navigation_radius(ship)) if avoid_hostiles else r
	if avoid_hostiles:
		# The grid contains each hull's first two swept seconds. This radius
		# covers both exact hostile/allied margins; extra covers later motion.
		var padding: float=float(cells._maxNavigationRadius)+7.0 if cells.has("_maxNavigationRadius") else 220.0
		query_radius=own_navigation+padding+extra
	# Borrow only the phase-local read-only broadphase. All exact ally sweeps and
	# their ordered budget debits still run on every route/live safety query.
	for other in _neighbours(cells,a,b,query_radius):
		if str(other.id)==str(ship.id):continue
		var hostile: bool=other.team!=ship.team
		if hostile and (not avoid_hostiles or str(other.id)==contact_id):continue
		# Candidates start with their present point. A zero-time point cannot
		# decide whether a close pass escapes; check the following swept leg.
		if hostile and a==b and until<=from:continue
		if not spend(budget):return "pending"
		var velocity: Vector2=Vector2(other.vx,other.vy)
		# Full corridor occupancy uses observed constant-velocity prediction. Beyond
		# the two-second physical prefix it is conditional, never an escape promise.
		var c: Vector2=point(other)+velocity*from
		var d: Vector2=point(other)+velocity*until
		var relative: Vector2=a-c
		var delta: Vector2=(b-a)-(d-c)
		var fraction: float=clampf(-relative.dot(delta)/maxf(0.000001,delta.length_squared()),0.0,1.0)
		var clearance: float=r+maxf(10.0,float(other.spec.get("size",16)))+3.0
		if hostile:clearance=own_navigation+navigation_radius(other)+7.0
		if (relative+delta*fraction).length()<clearance:
			# An inherited close pass must still be able to leave. Permit only
			# continuously separating motion; no approach or crossing through it.
			if hostile and relative.length()<clearance and relative.dot(delta)>=0.0 and (relative+delta).length_squared()>relative.length_squared()+0.0001:continue
			return "blocked"
	return "valid"

static func _occupied_record051(cells: Dictionary,ship: Dictionary,a: Vector2,b: Vector2,r: float,from: float,until: float,budget: Dictionary,avoid_hostiles: bool,contact_id: String,debits: Array[int]) -> String:
	var extra: float=maxf(0.0,until-2.0)*float(cells.get("_maxSpeed",0.0))
	var query_radius: float=r+80.0+extra
	var own_navigation: float=maxf(r,navigation_radius(ship)) if avoid_hostiles else r
	if avoid_hostiles:
		var padding: float=float(cells._maxNavigationRadius)+7.0 if cells.has("_maxNavigationRadius") else 220.0
		query_radius=own_navigation+padding+extra
	for other in _neighbours(cells,a,b,query_radius):
		if str(other.id)==str(ship.id):continue
		var hostile: bool=other.team!=ship.team
		if hostile and (not avoid_hostiles or str(other.id)==contact_id):continue
		if hostile and a==b and until<=from:continue
		if not _proof_spend051(budget,debits):return "pending"
		var velocity: Vector2=Vector2(other.vx,other.vy)
		var c: Vector2=point(other)+velocity*from
		var d: Vector2=point(other)+velocity*until
		var relative: Vector2=a-c
		var delta: Vector2=(b-a)-(d-c)
		var fraction: float=clampf(-relative.dot(delta)/maxf(0.000001,delta.length_squared()),0.0,1.0)
		var clearance: float=r+maxf(10.0,float(other.spec.get("size",16)))+3.0
		if hostile:clearance=own_navigation+navigation_radius(other)+7.0
		if (relative+delta*fraction).length()<clearance:
			if hostile and relative.length()<clearance and relative.dot(delta)>=0.0 and (relative+delta).length_squared()>relative.length_squared()+0.0001:continue
			return "blocked"
	return "valid"

static func route(st: Dictionary,geometry: Dictionary,a: Vector2,b: Vector2,r: float,budget: Dictionary) -> Dictionary:
	return _route(st,geometry,a,b,r,budget)

static func _route(st: Dictionary,geometry: Dictionary,a: Vector2,b: Vector2,r: float,budget: Dictionary,proofs: _BeginProofs051=null,owner: Dictionary={}) -> Dictionary:
	# Exact endpoint/radius identity; terrain() clears this battle-local cache
	# on a coast edit. Never borrow endpoint edges from a nearby moving query.
	var key: String=var_to_bytes([geometry.key,geometry.revision,r,a,b]).hex_encode()
	var cache: Dictionary=st.tactical.routeCache
	var entry: Dictionary=cache.get(key,{})
	if not entry.is_empty() and entry.status!="pending":
		budget.cacheHits+=1
		return {"status":entry.status,"path":entry.path.duplicate()}
	if entry.is_empty():
		# A pending primitive is never a clearance proof. Once terminal, this
		# direct result belongs to the exact query and need not restart either.
		var direct: String=sweep(geometry,a,b,r,budget) if proofs==null else _sweep_begin051(proofs,owner,geometry,a,b,r,budget)
		if direct=="pending":return {"status":"pending","path":[]}
		if direct=="valid":return {"status":"valid","path":[b]}
	if int(budget.fullRoutes)>=4:
		budget.exhaustions+=1
		return {"status":"pending","path":[]}
	budget.fullRoutes+=1 # Resumed searches still spend the global query slot.
	if entry.is_empty():
		var graph: Dictionary=_route_graph051(cache,geometry,r)
		if graph.is_empty():return {"status":"pending","path":[]}
		var initial_nodes: Array=[a,b]
		initial_nodes.append_array(graph.nodes)
		var initial_costs: Array=[]
		var initial_previous: Array=[]
		for i in range(initial_nodes.size()):initial_costs.append(INF);initial_previous.append(-1)
		initial_costs[0]=0.0
		entry={"status":"pending","path":[],"graph":graph,"nodes":initial_nodes,"costs":initial_costs,"previous":initial_previous,"closed":{},"edges":{Vector2i(0,1):"blocked"},"endpointEdges":[_route_endpoint051(graph,a),_route_endpoint051(graph,b)],"current":-1,"next":0}
		if cache.size()>=CACHE_LIMIT:cache.erase(cache.keys()[0])
		cache[key]=entry
	var nodes: Array=entry.nodes
	while true:
		if int(entry.current)<0:
			var best: float=INF
			for i in range(nodes.size()):
				if not entry.closed.has(i) and float(entry.costs[i])+nodes[i].distance_to(b)<best:
					best=float(entry.costs[i])+nodes[i].distance_to(b);entry.current=i
			if int(entry.current)<0:return _route_done051(entry,"blocked",[])
			if int(entry.current)==1:
				var path: Array=[]
				var at: int=1
				while at>0:
					path.push_front(nodes[at]);at=int(entry.previous[at])
					if path.size()>8:return _route_done051(entry,"blocked",[])
				return _route_done051(entry,"valid",path)
			entry.closed[int(entry.current)]=true;entry.next=0
		var current: int=int(entry.current)
		while int(entry.next)<nodes.size():
			var next: int=int(entry.next)
			if entry.closed.has(next) or next==current:
				entry.next+=1;continue
			# Cached graph traversal is bounded work too. On refusal keep the
			# current node AND neighbour cursor, not just a half-closed frontier.
			if not spend(budget):return {"status":"pending","path":[]}
			var edge_key: Vector2i=Vector2i(mini(current,next),maxi(current,next))
			# Reuse land visibility only for exact static/radius/endpoint inputs;
			# a moving goal must not discard checks from an unchanged origin.
			var edges: Dictionary=entry.graph.edges if current>=2 and next>=2 else entry.edges
			if mini(current,next)<2 and maxi(current,next)>=2:
				edges=entry.endpointEdges[mini(current,next)]
				edge_key=Vector2i(maxi(current,next),maxi(current,next))
			if not edges.has(edge_key):
				var status: String=sweep(geometry,nodes[current],nodes[next],r,budget) if proofs==null else _sweep_begin051(proofs,owner,geometry,nodes[current],nodes[next],r,budget)
				if status=="pending":return {"status":"pending","path":[]}
				edges[edge_key]=status
			if edges[edge_key]=="valid":
				var cost: float=float(entry.costs[current])+nodes[current].distance_to(nodes[next])
				if cost<float(entry.costs[next]):entry.costs[next]=cost;entry.previous[next]=current
			entry.next+=1
		entry.current=-1
	return {"status":"pending","path":[]}

static func _route_graph051(cache: Dictionary,geometry: Dictionary,r: float) -> Dictionary:
	# Shared only through the existing <=128 route entries; <=126 static nodes
	# and <=7875 undirected static edges per exact terrain/revision/radius.
	var signature: PackedByteArray=var_to_bytes([geometry.key,geometry.revision,r])
	for cached in cache.values():
		if cached is Dictionary and cached.graph.signature==signature:return cached.graph
	var nodes: Array=[]
	for obstacle in geometry.obstacles:
		var center: Vector2=Vector2.ZERO
		for p in obstacle.points:center+=Vector2(p[0],p[1])
		center/=float(obstacle.points.size())
		for p in obstacle.points:
			if nodes.size()>=126:return {}
			var v: Vector2=Vector2(p[0],p[1])
			nodes.append(v+(v-center).normalized()*(r*2.5+12.0))
	return {"signature":signature,"nodes":nodes,"edges":{},"endpoints":{}}

static func _route_endpoint051(graph: Dictionary,endpoint: Vector2) -> Dictionary:
	# Each exact endpoint's <=126 terminal sweeps remain useful when only the
	# other endpoint changes. Keep at most 128 recently used endpoint records.
	var key: String=var_to_bytes(endpoint).hex_encode()
	var edges: Dictionary=graph.endpoints.get(key,{})
	graph.endpoints.erase(key)
	if graph.endpoints.size()>=CACHE_LIMIT:graph.endpoints.erase(graph.endpoints.keys()[0])
	graph.endpoints[key]=edges
	return edges

static func _route_done051(entry: Dictionary,status: String,path: Array) -> Dictionary:
	entry.status=status;entry.path=path.duplicate()
	# Completed searches retain their static graph, not their frontier arrays.
	for field: String in ["nodes","costs","previous","closed","edges","endpointEdges","current","next"]:entry.erase(field)
	return {"status":status,"path":path}

static func refine(st: Dictionary,geometry: Dictionary,ship: Dictionary,candidate: Dictionary,budget: Dictionary) -> Dictionary:
	return _refine(st,geometry,ship,candidate,budget,false)

static func refine_live(st: Dictionary,geometry: Dictionary,ship: Dictionary,candidate: Dictionary,budget: Dictionary) -> Dictionary:
	# One synchronous route/corridor walk. Each returned edge already passed
	# terrain at planning_radius (at least hull radius+4); check allied traffic
	# as that edge is built, before searching an unusable pass or exit.
	return _refine(st,geometry,ship,candidate,budget,true)

static func _refine_begin051(st: Dictionary,geometry: Dictionary,ship: Dictionary,candidate: Dictionary,budget: Dictionary,proofs: _BeginProofs051,live_traffic_seconds051: float=-1.0) -> Dictionary:
	# Never borrow a proof for a new owner, geometry, grid, tick or closed batch.
	# The public path and all live after-motion/helm/fire calls have no context.
	if not _proof_scope051(proofs,geometry,st.tactical.cells,ship):return _refine(st,geometry,ship,candidate,budget,true,null,live_traffic_seconds051)
	return _refine(st,geometry,ship,candidate,budget,true,proofs,live_traffic_seconds051)

static func _adopt_prepared051(st: Dictionary,geometry: Dictionary,ship: Dictionary,candidate: Dictionary,prepared: Dictionary,budget: Dictionary,proofs: _BeginProofs051,live_traffic_seconds051: float) -> Dictionary:
	# Private, completed+joined worker output, NEVER a corridor/certificate.
	# Unfinished static searches use the ordinary bounded main route path.
	if prepared.get("status","")!="valid" or prepared.get("terrainKey051")!=geometry.key or prepared.get("terrainRevision051")!=geometry.revision or prepared.get("radius051")!=planning_radius(ship):
		return _refine_begin051(st,geometry,ship,candidate,budget,proofs,live_traffic_seconds051)
	var result: Dictionary=candidate.duplicate(true)
	if not _proof_scope051(proofs,geometry,st.tactical.cells,ship):proofs=null
	var previous: Vector2=point(ship)
	var radius: float=maxf(10.0,float(ship.spec.get("size",16)))+4.0
	var speed: float=maxf(1.0,float(ship.spec.get("speed",90))*float(ship.status.speedFactor)*(1.0 if float(ship.fuel)>0.0 else 0.2)*0.8)
	var elapsed: float=0.0
	var connector: bool=true
	var total: int=0
	for leg: String in ["approach","pass","exit"]:
		var points: Array=prepared.candidate.get(leg,[]).duplicate()
		# A zero-distance deployment origin is not a future station. Connect
		# from the ACTUAL pose to the first remaining fully land-routed waypoint.
		if leg=="approach" and points.size()>1 and points[0]==prepared.origin051:points.pop_front()
		if points.size()>8:return {"status":"blocked","candidate":result,"eta":elapsed}
		for waypoint: Vector2 in points:
			if not waypoint.is_finite():return {"status":"blocked","candidate":result,"eta":elapsed}
			if connector:
				var land: String=sweep(geometry,previous,waypoint,planning_radius(ship),budget) if proofs==null else _sweep_begin051(proofs,ship,geometry,previous,waypoint,planning_radius(ship),budget)
				if land!="valid":return {"status":land,"candidate":result,"eta":elapsed,"reason":"Checking current land connector"}
				connector=false
			var until: float=elapsed+previous.distance_to(waypoint)/speed
			if elapsed<=live_traffic_seconds051:
				var traffic_until: float=minf(until,live_traffic_seconds051)
				var traffic_end: Vector2=previous.lerp(waypoint,(traffic_until-elapsed)/(until-elapsed)) if traffic_until<until else waypoint
				var traffic: String=occupied(st.tactical.cells,ship,previous,traffic_end,radius,elapsed,traffic_until,budget,true,contact_target(ship)) if proofs==null else _occupied_begin051(proofs,st.tactical.cells,ship,previous,traffic_end,radius,elapsed,traffic_until,budget,true,contact_target(ship))
				if traffic!="valid":return {"status":traffic,"candidate":result,"eta":elapsed,"reason":"Checking hull clearance" if traffic=="pending" else "Hull occupies this approach"}
			elapsed=until;previous=waypoint
		result[leg]=points;total+=points.size()
	if total>24 or connector:return {"status":"blocked","candidate":result,"eta":elapsed}
	return {"status":"valid","candidate":result,"eta":elapsed,"reason":"Current connector and traffic clear"}

static func _refine(st: Dictionary,geometry: Dictionary,ship: Dictionary,candidate: Dictionary,budget: Dictionary,live_corridor: bool,proofs: _BeginProofs051=null,live_traffic_seconds051: float=-1.0) -> Dictionary:
	var result: Dictionary=candidate.duplicate(true)
	var previous: Vector2=point(ship)
	var total: int=0
	var elapsed: float=0.0
	var finite_traffic051: bool=is_finite(live_traffic_seconds051) and live_traffic_seconds051>=0.0
	var radius: float=maxf(10.0,float(ship.spec.get("size",16)))+4.0
	var speed: float=1.0
	if live_corridor:speed=maxf(1.0,float(ship.spec.get("speed",90))*float(ship.status.speedFactor)*(1.0 if float(ship.fuel)>0.0 else 0.2)*0.8)
	for leg in ["approach","pass","exit"]:
		var points: Array=[]
		for goal in candidate.get(leg,[]):
			if not goal is Vector2 or not goal.is_finite():return {"status":"blocked","candidate":result}
			var found: Dictionary=route(st,geometry,previous,goal,planning_radius(ship),budget) if proofs==null else _route(st,geometry,previous,goal,planning_radius(ship),budget,proofs,ship)
			if found.status!="valid":return {"status":found.status,"candidate":result}
			if live_corridor:
				var cursor: Vector2=previous
				for waypoint: Vector2 in found.path:
					var until: float=elapsed+cursor.distance_to(waypoint)/speed
					# Private planning checks only its renewable traffic prefix. Every
					# full land edge above, route point and ETA below is still retained.
					# Inclusive boundary preserves zero-time initial/hold point checks.
					if not finite_traffic051 or elapsed<=live_traffic_seconds051:
						var traffic_until: float=minf(until,live_traffic_seconds051) if finite_traffic051 else until
						var traffic_end: Vector2=cursor.lerp(waypoint,(traffic_until-elapsed)/(until-elapsed)) if traffic_until<until else waypoint
						var traffic: String=occupied(st.tactical.cells,ship,cursor,traffic_end,radius,elapsed,traffic_until,budget,true,contact_target(ship)) if proofs==null else _occupied_begin051(proofs,st.tactical.cells,ship,cursor,traffic_end,radius,elapsed,traffic_until,budget,true,contact_target(ship))
						if traffic!="valid":return {"status":traffic,"candidate":result,"eta":elapsed,"reason":"Checking hull clearance" if traffic=="pending" else "Hull occupies this approach"}
					elapsed=until;cursor=waypoint
			points.append_array(found.path)
			if points.size()>8:return {"status":"blocked","candidate":result}
			previous=goal
		result[leg]=points;total+=points.size()
	if total>24:return {"status":"blocked","candidate":result}
	if live_corridor:return {"status":"valid","candidate":result,"eta":elapsed,"reason":"Route clear"}
	return {"status":"valid","candidate":result}
