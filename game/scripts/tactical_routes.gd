extends RefCounted
## Battle-local geometry. No Battle dependency, live callbacks or campaign routes.
const WIDTH: float=2300.0
const HEIGHT: float=1700.0
const CACHE_LIMIT: int=128
const GRID_QUERY_LIMIT: int=128
const BEGIN_PROOF_LIMIT051: int=512

# Opt-in observer receipts, not navigation state. Workers never write this sink:
# only the thread which enabled the real-runtime profiler can publish a row.
const VETO_ACTOR_LIMIT051: int=80
static var _veto_thread051: int=-1
static var _veto_serial051: int=0
static var _veto_hulls051: Dictionary={}

static func _profile_veto051(enabled: bool,reset: bool=false) -> void:
	_veto_thread051=OS.get_thread_caller_id() if enabled else -1
	if reset or not enabled:
		_veto_hulls051.clear();_veto_serial051=0

static func _veto_enabled051() -> bool:
	return _veto_thread051>=0 and OS.get_thread_caller_id()==_veto_thread051

static func _veto_snapshot051() -> Dictionary:
	return {"schema":1,"actorLimit":VETO_ACTOR_LIMIT051,"minimumIntervalSeconds":0.1,"scope":"Last sampled main-thread refusal per fixed gate per hull; at most one per gate per 0.1 simulated seconds. Times/serials identify older refusals. No worker trace or clearance authority.","byHull":_veto_hulls051.duplicate(true)} if _veto_enabled051() else {}

static func _veto_due051(id: String,at: float,slot: String) -> bool:
	if not _veto_enabled051():return false
	if not _veto_hulls051.has(id):return _veto_hulls051.size()<VETO_ACTOR_LIMIT051
	var hull: Dictionary=_veto_hulls051[id]
	return not hull.has(slot) or at-float(hull[slot].time)>=0.1

static func _veto_record051(budget: Dictionary,id: String,at: float,slot: String,status: String,reason: String,candidate_id: String="",extra: Dictionary={}) -> void:
	# Throttle BEFORE constructing the receipt or copying any primitive.
	if status=="valid" or not bool(budget.get("profileRoutes051",false)) or slot not in ["route","certificate","reservation","helm","current"] or not _veto_due051(id,at,slot):return
	if not _veto_hulls051.has(id):
		if _veto_hulls051.size()>=VETO_ACTOR_LIMIT051:return
		_veto_hulls051[id]={}
	_veto_serial051+=1
	var row: Dictionary={"time":at,"serial":_veto_serial051,"status":status,"reason":reason,"candidateId":candidate_id,"clearanceTests":int(budget.get("clearanceTests",-1)),"clearanceLimit":int(budget.get("clearanceLimit",-1)),"exhaustions":int(budget.get("exhaustions",budget.get("clearanceExhausted",-1))),"fullRoutes":int(budget.get("fullRoutes",-1)),"rollouts":int(budget.get("rollouts",-1)),"samples":int(budget.get("samples",-1))}
	row["primitive"]=budget.get("vetoPrimitive051",{}).duplicate(true)
	row.merge(extra,true);_veto_hulls051[id][slot]=row

static func _veto_primitive051(budget: Dictionary,status: String,stage: String,reason: String,a: Vector2,b: Vector2,r: float,from: float=0.0,until: float=0.0,blocker: String="",extra: Dictionary={}) -> String:
	if bool(budget.get("profileRoutes051",false)) and bool(budget.get("vetoCapture051",false)):
		budget.vetoPrimitive051={"stage":stage,"reason":reason,"status":status,"segment":[[a.x,a.y],[b.x,b.y]],"radius":r,"from":from,"until":until,"blocker":blocker,"leg":str(budget.get("vetoLeg051",""))}
		budget.vetoPrimitive051.merge(extra,true)
	return status

static func _veto_result051(st: Dictionary,ship: Dictionary,candidate: Dictionary,budget: Dictionary,result: Dictionary,source: String,extra: Dictionary={}) -> void:
	if result.status=="valid" or not bool(budget.get("profileRoutes051",false)) or not _veto_due051(str(ship.id),float(st.time),"route"):return
	extra=extra.duplicate();extra["source"]=source
	_veto_record051(budget,str(ship.id),float(st.time),"route",str(result.status),str(result.get("reason","Static route search "+str(result.status))),str(candidate.get("candidateId","")),extra)

class _BeginProofs051 extends RefCounted:
	var active: bool=true
	var geometry: Dictionary={}
	var obstacles: Array=[]
	var geometry_stamp: PackedByteArray=PackedByteArray()
	var cells: Dictionary={}
	var owners: Dictionary={}
	var entries: Dictionary={}
	var traffic_bodies: Dictionary={}

class _Numeric051 extends RefCounted:
	# Private synchronous inputs, never clearance/certificate results. Runtime
	# closes this epoch before motion and before contact/boarding writes.
	var active: bool=true
	var context: Dictionary={}
	var cells: Dictionary={}
	var owners: Dictionary={}
	var bodies: Dictionary={}
	var phase=null # Actual Damage phase, admitted once by Runtime; no preload cycle.
	var at: float=0.0
	var revision: int=0

static func _numeric_grid051(st: Dictionary,ships: Array,phase) -> _Numeric051:
	var numeric: _Numeric051=_Numeric051.new()
	numeric.phase=phase
	numeric.context=st;numeric.at=float(st.time);numeric.revision=int(st.tactical.snapshotRevision)
	numeric.owners=st.tactical.ships.duplicate()
	numeric.cells=_grid051(ships,true,numeric)
	numeric.owners.make_read_only();numeric.bodies.make_read_only()
	numeric.cells._numeric051=numeric
	return numeric

static func _close_numeric051(numeric: _Numeric051) -> void:
	numeric.active=false
	if is_same(numeric.cells.get("_numeric051"),numeric):numeric.cells.erase("_numeric051")
	# Break the phase's container references as well as revoking the epoch.
	numeric.context={};numeric.cells={};numeric.owners={};numeric.bodies={};numeric.phase=null

static func _numeric_for051(cells: Dictionary,ship: Dictionary) -> _Numeric051:
	var numeric=cells.get("_numeric051")
	if not numeric is _Numeric051 or not numeric.active or not is_same(numeric.cells,cells):return null
	if numeric.phase==null or not numeric.phase.active or not numeric.phase.readsSealed051:return null
	var t: Dictionary=numeric.context.get("tactical",{})
	if not is_same(t.get("_numeric051"),numeric) or not is_same(t.get("cells"),cells):return null
	if numeric.at!=float(numeric.context.get("time",-INF)) or numeric.revision!=int(t.get("snapshotRevision",-1)):return null
	return numeric if is_same(numeric.owners.get(str(ship.id)),ship) else null

static func _numeric_body051(numeric: _Numeric051,ship: Dictionary):
	# Construction already checked the complete table. Only exact source/owner
	# identity is read here; copied/forged grids and hulls take the public math.
	if numeric==null:return null
	var body=numeric.bodies.get(str(ship.id))
	return body if body!=null and (is_same(body[0],ship) or is_same(numeric.owners.get(str(ship.id)),ship)) else null

static func _begin_proofs051(geometry: Dictionary,cells: Dictionary,owners: Dictionary) -> _BeginProofs051:
	# Runtime.begin alone owns this closed, synchronous observation scope. None
	# of these geometry/ship observations move or mutate during certification.
	var proofs: _BeginProofs051=_BeginProofs051.new()
	proofs.geometry=geometry;proofs.obstacles=geometry.obstacles
	proofs.geometry_stamp=var_to_bytes([geometry.key,geometry.revision])
	proofs.cells=cells;proofs.owners=owners.duplicate()
	var numeric=cells.get("_numeric051")
	if numeric is _Numeric051 and numeric.active and is_same(numeric.cells,cells) and numeric.phase!=null and numeric.phase.active and numeric.phase.readsSealed051:proofs.traffic_bodies=numeric.bodies
	return proofs

static func _close_begin_proofs051(proofs: _BeginProofs051) -> void:
	proofs.active=false;proofs.entries.clear();proofs.owners.clear();proofs.traffic_bodies={}
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

static func _proof_store051(proofs: _BeginProofs051,key: String,status: String,debits: Array[int],budget: Dictionary={}) -> void:
	if status not in ["valid","blocked"]:return
	debits.make_read_only()
	var proof: Dictionary={"status":status,"debits":debits}
	if bool(budget.get("profileRoutes051",false)) and bool(budget.get("vetoCapture051",false)) and status=="blocked":proof["veto051"]=budget.get("vetoPrimitive051",{}).duplicate(true)
	proof.make_read_only();proofs.entries[key]=proof

static func _sweep_begin051(proofs: _BeginProofs051,ship: Dictionary,geometry: Dictionary,a: Vector2,b: Vector2,r: float,budget: Dictionary) -> String:
	# Context identities are checked at _refine_begin051. Typed bytes preserve
	# exact ordered endpoints/radii; no rounded keys or hash-only equality.
	var profile051: bool=bool(budget.get("profileRoutes051",false))
	var started051: int=Time.get_ticks_usec() if profile051 else 0
	var key: String=var_to_bytes(["terrain",str(ship.id),proofs.geometry_stamp,a,b,r]).hex_encode()
	if proofs.entries.has(key):
		var replay051: String=_proof_replay051(proofs.entries[key],budget)
		_veto_replay051(budget,proofs.entries[key],replay051,"land",a,b,r)
		if profile051:_route_timing051(budget,"sweepMemo",Time.get_ticks_usec()-started051)
		return replay051
	if profile051:_route_timing051(budget,"sweepMemo",Time.get_ticks_usec()-started051)
	var numeric_started051: int=Time.get_ticks_usec() if profile051 else 0
	if proofs.entries.size()>=BEGIN_PROOF_LIMIT051:
		var fallback051: String=sweep(geometry,a,b,r,budget)
		if profile051:_route_timing051(budget,"sweepNumeric",Time.get_ticks_usec()-numeric_started051)
		return fallback051
	var debits: Array[int]=[]
	var status: String=_sweep_record051(geometry,a,b,r,budget,debits)
	_proof_store051(proofs,key,status,debits,budget)
	if profile051:_route_timing051(budget,"sweepNumeric",Time.get_ticks_usec()-numeric_started051)
	return status

static func _occupied_begin051(proofs: _BeginProofs051,cells: Dictionary,ship: Dictionary,a: Vector2,b: Vector2,r: float,from: float,until: float,budget: Dictionary,avoid_hostiles: bool=false,contact_id: String="") -> String:
	var profile051: bool=bool(budget.get("profileRoutes051",false))
	var started051: int=Time.get_ticks_usec() if profile051 else 0
	var own_navigation: float=maxf(r,navigation_radius(ship)) if avoid_hostiles else r
	var key: String=var_to_bytes(["traffic",str(ship.id),str(ship.team),proofs.geometry_stamp,a,b,r,from,until,own_navigation,contact_id,avoid_hostiles]).hex_encode()
	if bool(budget.get("separatingEgress051",false)):key+=":egress051"
	if proofs.entries.has(key):
		var replay051: String=_proof_replay051(proofs.entries[key],budget)
		_veto_replay051(budget,proofs.entries[key],replay051,"traffic",a,b,r,from,until)
		if profile051:_route_timing051(budget,"occupiedMemo",Time.get_ticks_usec()-started051)
		return replay051
	if profile051:_route_timing051(budget,"occupiedMemo",Time.get_ticks_usec()-started051)
	var numeric_started051: int=Time.get_ticks_usec() if profile051 else 0
	if proofs.entries.size()>=BEGIN_PROOF_LIMIT051:
		var fallback051: String=occupied(cells,ship,a,b,r,from,until,budget,avoid_hostiles,contact_id)
		if profile051:_route_timing051(budget,"occupiedNumeric",Time.get_ticks_usec()-numeric_started051)
		return fallback051
	var debits: Array[int]=[]
	var status: String=_occupied_record051(cells,ship,a,b,r,from,until,budget,avoid_hostiles,contact_id,debits,proofs)
	_proof_store051(proofs,key,status,debits,budget)
	if profile051:_route_timing051(budget,"occupiedNumeric",Time.get_ticks_usec()-numeric_started051)
	return status

static func _route_timing051(budget: Dictionary,stage: String,elapsed_us: int) -> void:
	# Opt-in caller-owned scalars only; never shared with detached worker budgets.
	if not budget.has("routeTiming051"):
		budget.routeTiming051={"sweepMemoUs":0,"sweepMemoCalls":0,"sweepNumericUs":0,"sweepNumericCalls":0,"occupiedMemoUs":0,"occupiedMemoCalls":0,"occupiedNumericUs":0,"occupiedNumericCalls":0,"routeUs":0,"routeCalls":0,"refineUs":0,"refineCalls":0,"adoptUs":0,"adoptCalls":0}
	var timing: Dictionary=budget.routeTiming051
	timing[stage+"Us"]=int(timing[stage+"Us"])+elapsed_us
	timing[stage+"Calls"]=int(timing[stage+"Calls"])+1

static func _veto_replay051(budget: Dictionary,proof: Dictionary,status: String,stage: String,a: Vector2,b: Vector2,r: float,from: float=0.0,until: float=0.0) -> void:
	if not bool(budget.get("profileRoutes051",false)) or not bool(budget.get("vetoCapture051",false)) or status=="valid":return
	if status=="pending":
		_veto_primitive051(budget,status,stage,"clearance budget during proof replay",a,b,r,from,until)
	else:
		budget.vetoPrimitive051=proof.get("veto051",{}).duplicate(true)
		budget.vetoPrimitive051["memoReplay"]=true

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
			var edge_lo121:=PackedVector2Array()
			var edge_hi121:=PackedVector2Array()
			for i in range(vertices.size()):
				var c:=Vector2(vertices[i][0],vertices[i][1])
				var d:=Vector2(vertices[(i+1)%vertices.size()][0],vertices[(i+1)%vertices.size()][1])
				edge_lo121.append(c.min(d));edge_hi121.append(c.max(d))
			t.obstacles.append({"points":vertices.duplicate(true),"lo":lo,"hi":hi,"_edgeLo121":edge_lo121,"_edgeHi121":edge_hi121})
	return {"revision":int(t.terrainRevision),"key":key,"obstacles":t.obstacles}

static func sweep(geometry: Dictionary,a: Vector2,b: Vector2,r: float,budget: Dictionary) -> String:
	if not spend(budget):return _veto_primitive051(budget,"pending","land","clearance budget",a,b,r)
	if not a.is_finite() or not b.is_finite() or minf(a.x,b.x)<r or maxf(a.x,b.x)>WIDTH-r or minf(a.y,b.y)<r or maxf(a.y,b.y)>HEIGHT-r:return _veto_primitive051(budget,"blocked","land","nonfinite endpoint or map boundary",a,b,r)
	var lo: Vector2=a.min(b)-Vector2.ONE*r
	var hi: Vector2=a.max(b)+Vector2.ONE*r
	for obstacle in geometry.obstacles:
		if not spend(budget):return _veto_primitive051(budget,"pending","land","obstacle budget",a,b,r)
		if hi.x<float(obstacle.lo.x) or hi.y<float(obstacle.lo.y) or lo.x>float(obstacle.hi.x) or lo.y>float(obstacle.hi.y):continue
		var vertices: Array=obstacle.points
		var edge_lo121=obstacle.get("_edgeLo121")
		var edge_hi121=obstacle.get("_edgeHi121")
		var edges_cached121: bool=edge_lo121 is PackedVector2Array and edge_hi121 is PackedVector2Array and edge_lo121.size()==vertices.size() and edge_hi121.size()==vertices.size()
		if not spend(budget,2):return _veto_primitive051(budget,"pending","land","endpoint budget",a,b,r)
		if inside(a,vertices) or inside(b,vertices):return _veto_land051(budget,geometry,obstacle,-1,a,b,r)
		for i in range(vertices.size()):
			if not spend(budget):return _veto_primitive051(budget,"pending","land","edge budget",a,b,r)
			# Preserve every debit and original possible-contact kernel. The
			# conservative .01 slop exceeds its .001 clearance epsilon.
			if edges_cached121:
				var edge_lo: Vector2=edge_lo121[i]
				var edge_hi: Vector2=edge_hi121[i]
				if hi.x<edge_lo.x-0.01 or hi.y<edge_lo.y-0.01 or lo.x>edge_hi.x+0.01 or lo.y>edge_hi.y+0.01:continue
			var c: Vector2=Vector2(vertices[i][0],vertices[i][1])
			var d: Vector2=Vector2(vertices[(i+1)%vertices.size()][0],vertices[(i+1)%vertices.size()][1])
			if segment_distance(a,b,c,d)<r+0.001:return _veto_land051(budget,geometry,obstacle,i,a,b,r)
	return "valid"

# These private recorders mirror the unchanged public checks, recording debits
# and borrowing closed-begin hull inputs. Pending never creates a terminal proof.
static func _sweep_record051(geometry: Dictionary,a: Vector2,b: Vector2,r: float,budget: Dictionary,debits: Array[int]) -> String:
	if not _proof_spend051(budget,debits):return _veto_primitive051(budget,"pending","land","clearance budget",a,b,r)
	if not a.is_finite() or not b.is_finite() or minf(a.x,b.x)<r or maxf(a.x,b.x)>WIDTH-r or minf(a.y,b.y)<r or maxf(a.y,b.y)>HEIGHT-r:return _veto_primitive051(budget,"blocked","land","nonfinite endpoint or map boundary",a,b,r)
	var lo: Vector2=a.min(b)-Vector2.ONE*r
	var hi: Vector2=a.max(b)+Vector2.ONE*r
	for obstacle in geometry.obstacles:
		if not _proof_spend051(budget,debits):return _veto_primitive051(budget,"pending","land","obstacle budget",a,b,r)
		if hi.x<float(obstacle.lo.x) or hi.y<float(obstacle.lo.y) or lo.x>float(obstacle.hi.x) or lo.y>float(obstacle.hi.y):continue
		var vertices: Array=obstacle.points
		var edge_lo121=obstacle.get("_edgeLo121")
		var edge_hi121=obstacle.get("_edgeHi121")
		var edges_cached121: bool=edge_lo121 is PackedVector2Array and edge_hi121 is PackedVector2Array and edge_lo121.size()==vertices.size() and edge_hi121.size()==vertices.size()
		if not _proof_spend051(budget,debits,2):return _veto_primitive051(budget,"pending","land","endpoint budget",a,b,r)
		if inside(a,vertices) or inside(b,vertices):return _veto_land051(budget,geometry,obstacle,-1,a,b,r)
		for i in range(vertices.size()):
			if not _proof_spend051(budget,debits):return _veto_primitive051(budget,"pending","land","edge budget",a,b,r)
			if edges_cached121:
				var edge_lo: Vector2=edge_lo121[i]
				var edge_hi: Vector2=edge_hi121[i]
				if hi.x<edge_lo.x-0.01 or hi.y<edge_lo.y-0.01 or lo.x>edge_hi.x+0.01 or lo.y>edge_hi.y+0.01:continue
			var c: Vector2=Vector2(vertices[i][0],vertices[i][1])
			var d: Vector2=Vector2(vertices[(i+1)%vertices.size()][0],vertices[(i+1)%vertices.size()][1])
			if segment_distance(a,b,c,d)<r+0.001:return _veto_land051(budget,geometry,obstacle,i,a,b,r)
	return "valid"

static func _veto_land051(budget: Dictionary,geometry: Dictionary,obstacle: Dictionary,edge: int,a: Vector2,b: Vector2,r: float) -> String:
	if bool(budget.get("vetoCapture051",false)):
		_veto_primitive051(budget,"blocked","land","endpoint inside island" if edge<0 else "island edge clearance",a,b,r,0.0,0.0,"island:%d"%geometry.obstacles.find(obstacle),{"edge":edge,"threshold":r+0.001})
	return "blocked"

static func grid(ships: Array,reuse_queries: bool=false) -> Dictionary:
	return _grid051(ships,reuse_queries)

static func _grid051(ships: Array,reuse_queries: bool,numeric: _Numeric051=null) -> Dictionary:
	var cells: Dictionary={"_maxSpeed":0.0,"_maxNavigationRadius":0.0}
	# Only Runtime's synchronous observation/post-motion phases opt in. Cell
	# membership is fixed until the next grid build; no result survives that build.
	if reuse_queries:cells._queryCache={}
	for ship in ships:
		if ship.get("sunk",false) or ship.get("captureSecured",false):continue
		var r: float=maxf(10.0,float(ship.spec.get("size",16)))
		var origin: Vector2=point(ship)
		var velocity: Vector2=Vector2(ship.vx,ship.vy)
		if numeric!=null:
			var body: Array=[ship,origin,velocity,r]
			body.make_read_only();numeric.bodies[str(ship.id)]=body
		cells._maxNavigationRadius=maxf(float(cells._maxNavigationRadius),r*2.75)
		cells._maxSpeed=maxf(float(cells._maxSpeed),velocity.length())
		var future: Vector2=origin+velocity*2.0
		var lo: Vector2=origin.min(future)-Vector2.ONE*(r+8.0)
		var hi: Vector2=origin.max(future)+Vector2.ONE*(r+8.0)
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

static func _is_crowd_escape051(candidate: Dictionary) -> bool:
	# Only this optional, fingerprinted nonfiring terminal shape can request
	# checked alignment. A flag never supplies a route/certificate/helm lease.
	if not candidate.get("crowdEscape051") is bool or not candidate.get("crowdEscape051",false) or candidate.get("targetId","")!="" or candidate.get("sector",-2)!=-1 or candidate.has("fireMountTargets"):
		return false
	if not candidate.get("fireMountIds") is Array or not candidate.fireMountIds.is_empty():return false
	var approach: Variant=candidate.get("approach")
	var pass_path: Variant=candidate.get("pass")
	var exit_path: Variant=candidate.get("exit")
	if not approach is Array or approach.is_empty() or approach.size()>8 or not pass_path is Array or pass_path.size()!=1 or not exit_path is Array or exit_path.size()!=1:return false
	for point051: Variant in approach:
		if not point051 is Vector2 or not point051.is_finite():return false
	return pass_path[0]==approach[-1] and exit_path[0]==approach[-1]

static func occupied(cells: Dictionary,ship: Dictionary,a: Vector2,b: Vector2,r: float,from: float,until: float,budget: Dictionary,avoid_hostiles: bool=false,contact_id: String="") -> String:
	return _occupied051(cells,ship,a,b,r,from,until,budget,avoid_hostiles,contact_id,false)

static func _checked_alignment051(cells: Dictionary,ship: Dictionary,a: Vector2,b: Vector2,r: float,dt: float,budget: Dictionary) -> String:
	# Private current integrated ZERO-throttle step only, never a route proof.
	# No ram/boarding exception: every hostile and ally retains its true floor.
	if not bool(budget.get("separatingEgress051",false)) or not is_finite(dt) or dt<=0.0 or dt>1.0/30.0 or not a.is_finite() or not b.is_finite():return "blocked"
	return _occupied051(cells,ship,a,b,r,0.0,dt,budget,true,"",true)

static func _occupied051(cells: Dictionary,ship: Dictionary,a: Vector2,b: Vector2,r: float,from: float,until: float,budget: Dictionary,avoid_hostiles: bool,contact_id: String,checked_alignment051: bool) -> String:
	var numeric051: _Numeric051=_numeric_for051(cells,ship)
	var separating_egress051: bool=bool(budget.get("separatingEgress051",false))
	var extra: float=maxf(0.0,until-2.0)*float(cells.get("_maxSpeed",0.0))
	var query_radius: float=r+80.0+extra
	var own_navigation: float=maxf(r,navigation_radius(ship)) if avoid_hostiles else r
	if avoid_hostiles:
		# The grid contains each hull's first two swept seconds. This radius
		# covers both exact hostile/allied margins; extra covers later motion.
		var padding: float=float(cells._maxNavigationRadius)+7.0 if cells.has("_maxNavigationRadius") else 220.0
		query_radius=own_navigation+padding+extra
	# Borrow only the phase-local read-only broadphase. Ordered debits remain;
	# a disjoint relative segment needs no closest-approach solve.
	for other in _neighbours(cells,a,b,query_radius):
		if str(other.id)==str(ship.id):continue
		var hostile: bool=other.team!=ship.team
		if hostile and (not avoid_hostiles or str(other.id)==contact_id):continue
		# Candidates start with their present point. A zero-time point cannot
		# decide whether a close pass escapes; check the following swept leg.
		if hostile and a==b and until<=from and not separating_egress051:continue
		if not spend(budget):return _veto_primitive051(budget,"pending","traffic","clearance budget",a,b,r,from,until,str(other.id))
		var body051=_numeric_body051(numeric051,other)
		var velocity: Vector2=body051[2] if body051!=null else Vector2(other.vx,other.vy)
		var origin051: Vector2=body051[1] if body051!=null else point(other)
		var radius051: float=float(body051[3]) if body051!=null else maxf(10.0,float(other.spec.get("size",16)))
		# Full corridor occupancy uses observed constant-velocity prediction. Beyond
		# the two-second physical prefix it is conditional, never an escape promise.
		var c: Vector2=origin051+velocity*from
		var d: Vector2=origin051+velocity*until
		var relative: Vector2=a-c
		var delta: Vector2=(b-a)-(d-c)
		var clearance: float=r+radius051+3.0
		if hostile:clearance=own_navigation+radius051*2.75+7.0
		if _traffic_apart051(relative,delta,clearance):continue
		var fraction: float=clampf(-relative.dot(delta)/maxf(0.000001,delta.length_squared()),0.0,1.0)
		if (relative+delta*fraction).length()<clearance:
			# An inherited close pass must still be able to leave. Permit only
			# continuously separating motion; no approach or crossing through it.
			if separating_egress051:
				if _can_escape_padding051(ship,relative,delta,r,radius051,a==b and from==0.0 and until==0.0):continue
				# A ZERO-throttle current step may yaw inside navigation padding.
				# Tiny approaching drift in that padding must not lock the helm's
				# heading forever. Check the entire relative sweep against the SAME
				# physical floor used by separating egress, including curved padding.
				# Ordinary positive-throttle departures still must separate above.
				if checked_alignment051:
					var own_radius: float=maxf(10.0,float(ship.spec.get("size",16)))
					var physical_floor: float=own_radius+radius051+maxf(0.0,r-own_radius-4.0)
					if (relative+delta*fraction).length()+0.0001>=physical_floor:continue
			elif hostile and relative.length()<clearance and relative.dot(delta)>=0.0 and (relative+delta).length_squared()>relative.length_squared()+0.0001:continue
			return _veto_traffic051(budget,ship,other,a,b,r,from,until,clearance,relative,delta,c,d,fraction,checked_alignment051)
	return "valid"

static func _occupied_record051(cells: Dictionary,ship: Dictionary,a: Vector2,b: Vector2,r: float,from: float,until: float,budget: Dictionary,avoid_hostiles: bool,contact_id: String,debits: Array[int],proofs: _BeginProofs051=null) -> String:
	var separating_egress051: bool=bool(budget.get("separatingEgress051",false))
	var extra: float=maxf(0.0,until-2.0)*float(cells.get("_maxSpeed",0.0))
	var query_radius: float=r+80.0+extra
	var own_navigation: float=maxf(r,navigation_radius(ship)) if avoid_hostiles else r
	var owner_id: String=str(ship.id)
	if avoid_hostiles:
		var padding: float=float(cells._maxNavigationRadius)+7.0 if cells.has("_maxNavigationRadius") else 220.0
		query_radius=own_navigation+padding+extra
	for other in _neighbours(cells,a,b,query_radius):
		var other_id: String=str(other.id)
		if other_id==owner_id:continue
		var hostile: bool=other.team!=ship.team
		if hostile and (not avoid_hostiles or other_id==contact_id):continue
		if hostile and a==b and until<=from and not separating_egress051:continue
		if not _proof_spend051(budget,debits):return _veto_primitive051(budget,"pending","traffic","clearance budget",a,b,r,from,until,other_id)
		# Only the existing closed begin may borrow immutable hull inputs. Keep
		# both time projections and all per-query debits/closest-approach math.
		var body: Array=[] if proofs==null else proofs.traffic_bodies.get(other_id,[])
		if body.is_empty() or not is_same(body[0],other):
			# Source identity, exact observed origin/velocity, physical hull radius.
			body=[other,point(other),Vector2(other.vx,other.vy),maxf(10.0,float(other.spec.get("size",16)))]
			if proofs!=null and not proofs.traffic_bodies.is_read_only() and proofs.traffic_bodies.size()<BEGIN_PROOF_LIMIT051:
				body.make_read_only();proofs.traffic_bodies[other_id]=body
		var origin: Vector2=body[1]
		var velocity: Vector2=body[2]
		var c: Vector2=origin+velocity*from
		var d: Vector2=origin+velocity*until
		var relative: Vector2=a-c
		var delta: Vector2=(b-a)-(d-c)
		var clearance: float=r+float(body[3])+3.0
		if hostile:clearance=own_navigation+float(body[3])*2.75+7.0
		if _traffic_apart051(relative,delta,clearance):continue
		var fraction: float=clampf(-relative.dot(delta)/maxf(0.000001,delta.length_squared()),0.0,1.0)
		if (relative+delta*fraction).length()<clearance:
			if separating_egress051:
				if _can_escape_padding051(ship,relative,delta,r,float(body[3]),a==b and from==0.0 and until==0.0):continue
			elif hostile and relative.length()<clearance and relative.dot(delta)>=0.0 and (relative+delta).length_squared()>relative.length_squared()+0.0001:continue
			return _veto_traffic051(budget,ship,other,a,b,r,from,until,clearance,relative,delta,c,d,fraction,false)
	return "valid"

static func _veto_traffic051(budget: Dictionary,ship: Dictionary,other: Dictionary,a: Vector2,b: Vector2,r: float,from: float,until: float,clearance: float,relative: Vector2,delta: Vector2,c: Vector2,d: Vector2,fraction: float,alignment: bool) -> String:
	if bool(budget.get("vetoCapture051",false)):
		_veto_primitive051(budget,"blocked","traffic","predicted hull clearance",a,b,r,from,until,str(other.id),{"hostile":other.team!=ship.team,"threshold":clearance,"closest":(relative+delta*fraction).length(),"initialDistance":relative.length(),"separationDot":relative.dot(delta),"physicalFloor":maxf(10.0,float(ship.spec.get("size",16)))+maxf(10.0,float(other.spec.get("size",16))),"blockerSegment":[[c.x,c.y],[d.x,d.y]],"separatingEgress":bool(budget.get("separatingEgress051",false)),"checkedAlignment":alignment})
	return "blocked"

static func _can_escape_padding051(ship: Dictionary,relative: Vector2,delta: Vector2,r: float,other_radius: float,initial_knot: bool) -> bool:
	# Owned planning/helm only. The existing closest-approach solve calls this
	# solely inside its original margin. A segment that ENTERS that margin must
	# still fail: its radial derivative is negative before the closest point.
	var own_radius: float=maxf(10.0,float(ship.spec.get("size",16)))
	# A curved prefix adds capsule deviation above hull+4. Keep that deviation
	# in the physical floor; a separating chord cannot prove a curved escape.
	var physical_floor: float=own_radius+other_radius+maxf(0.0,r-own_radius-4.0)
	# Battle's existing contact precision is 1e-4. R16 float32 resolved contacts
	# straddle the exact sum by <1e-4; never subtract a gameplay-sized margin.
	if relative.length()+0.0001<physical_floor:return false
	if initial_knot:return true # This grants no positive-duration helm step.
	# d/dt |relative+t*delta|^2 = 2*(relative.dot(delta)+t*|delta|^2).
	# Its minimum is at t=0 here: all separation is monotone, including the
	# physical closest approach. Equal-velocity/stationary padding cannot pass.
	return relative.dot(delta)>=0.0 and (relative+delta).length_squared()>relative.length_squared()

static func _traffic_apart051(relative: Vector2,delta: Vector2,clearance: float) -> bool:
	# The same clamped relative segment used below stays outside the clearance
	# circle if both endpoints lie beyond one of its enclosing square's sides.
	# Leave float32 boundary cases to the unchanged exact solve, never widen a
	# physical clearance or skip its budget debit. No result survives this call.
	var outside: float=clearance+maxf(0.001,absf(clearance)*0.000001)
	var end: Vector2=relative+delta
	return (relative.x>outside and end.x>outside) or (relative.x< -outside and end.x< -outside) or (relative.y>outside and end.y>outside) or (relative.y< -outside and end.y< -outside)

static func route(st: Dictionary,geometry: Dictionary,a: Vector2,b: Vector2,r: float,budget: Dictionary) -> Dictionary:
	return _route(st,geometry,a,b,r,budget)

static func _route(st: Dictionary,geometry: Dictionary,a: Vector2,b: Vector2,r: float,budget: Dictionary,proofs: _BeginProofs051=null,owner: Dictionary={}) -> Dictionary:
	if not bool(budget.get("profileRoutes051",false)):return _route_core051(st,geometry,a,b,r,budget,proofs,owner)
	var started051: int=Time.get_ticks_usec()
	var result051: Dictionary=_route_core051(st,geometry,a,b,r,budget,proofs,owner)
	_route_timing051(budget,"route",Time.get_ticks_usec()-started051)
	return result051

static func _route_core051(st: Dictionary,geometry: Dictionary,a: Vector2,b: Vector2,r: float,budget: Dictionary,proofs: _BeginProofs051,owner: Dictionary) -> Dictionary:
	# Exact endpoint/radius identity; terrain() clears this battle-local cache
	# on a coast edit. Never borrow endpoint edges from a nearby moving query.
	var key: String=var_to_bytes([geometry.key,geometry.revision,r,a,b]).hex_encode()
	var cache: Dictionary=st.tactical.routeCache
	var entry: Dictionary=cache.get(key,{})
	if not entry.is_empty() and entry.status!="pending":
		budget.cacheHits+=1
		if entry.status=="blocked":_veto_primitive051(budget,"blocked","route","cached terminal static route refusal",a,b,r)
		return {"status":entry.status,"path":entry.path.duplicate()}
	if entry.is_empty():
		# A pending primitive is never a clearance proof. Once terminal, this
		# direct result belongs to the exact query and need not restart either.
		var direct: String=sweep(geometry,a,b,r,budget) if proofs==null else _sweep_begin051(proofs,owner,geometry,a,b,r,budget)
		if direct=="pending":return {"status":"pending","path":[]}
		if direct=="valid":return {"status":"valid","path":[b]}
	if int(budget.fullRoutes)>=4:
		budget.exhaustions+=1
		_veto_primitive051(budget,"pending","route","four full-route slots used",a,b,r)
		return {"status":"pending","path":[]}
	budget.fullRoutes+=1 # Resumed searches still spend the global query slot.
	if entry.is_empty():
		var graph: Dictionary=_route_graph051(cache,geometry,r)
		if graph.is_empty():
			_veto_primitive051(budget,"pending","route","static graph unavailable",a,b,r)
			return {"status":"pending","path":[]}
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
			if int(entry.current)<0:
				_veto_primitive051(budget,"blocked","route","no static visibility path",a,b,r)
				return _route_done051(entry,"blocked",[])
			if int(entry.current)==1:
				var path: Array=[]
				var at: int=1
				while at>0:
					path.push_front(nodes[at]);at=int(entry.previous[at])
					if path.size()>8:
						_veto_primitive051(budget,"blocked","route","static path exceeds eight points",a,b,r)
						return _route_done051(entry,"blocked",[])
				return _route_done051(entry,"valid",path)
			entry.closed[int(entry.current)]=true;entry.next=0
		var current: int=int(entry.current)
		while int(entry.next)<nodes.size():
			var next: int=int(entry.next)
			if entry.closed.has(next) or next==current:
				entry.next+=1;continue
			# Cached graph traversal is bounded work too. On refusal keep the
			# current node AND neighbour cursor, not just a half-closed frontier.
			if not spend(budget):
				_veto_primitive051(budget,"pending","route","graph traversal budget",a,b,r)
				return {"status":"pending","path":[]}
			var cost: float=float(entry.costs[current])+nodes[current].distance_to(nodes[next])
			# Visibility cannot help a relaxation that cannot improve this node.
			# Keep its traversal debit/cursor, but do not sweep an irrelevant edge.
			if cost>=float(entry.costs[next]):
				entry.next+=1;continue
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
	if not bool(budget.get("profileRoutes051",false)):return _refine_begin_core051(st,geometry,ship,candidate,budget,proofs,live_traffic_seconds051)
	var started051: int=Time.get_ticks_usec()
	budget.vetoCapture051=_veto_due051(str(ship.id),float(st.time),"route")
	if budget.vetoCapture051:budget.erase("vetoPrimitive051")
	var result051: Dictionary=_refine_begin_core051(st,geometry,ship,candidate,budget,proofs,live_traffic_seconds051)
	_route_timing051(budget,"refine",Time.get_ticks_usec()-started051)
	if result051.status!="valid" and budget.vetoCapture051 and _veto_due051(str(ship.id),float(st.time),"route"):_veto_result051(st,ship,candidate,budget,result051,"current-refine",{"trafficHorizon":live_traffic_seconds051})
	budget.vetoCapture051=false
	return result051

static func _refine_begin_core051(st: Dictionary,geometry: Dictionary,ship: Dictionary,candidate: Dictionary,budget: Dictionary,proofs: _BeginProofs051,live_traffic_seconds051: float) -> Dictionary:
	# Never borrow a proof for a new owner, geometry, grid, tick or closed batch.
	# The public path and all live after-motion/helm/fire calls have no context.
	if not _proof_scope051(proofs,geometry,st.tactical.cells,ship):return _refine(st,geometry,ship,candidate,budget,true,null,live_traffic_seconds051)
	return _refine(st,geometry,ship,candidate,budget,true,proofs,live_traffic_seconds051)

static func _prepare_detached051(st: Dictionary,geometry: Dictionary,ship: Dictionary,candidate: Dictionary,budget: Dictionary,proof_budget051: Dictionary={},complete_static051: bool=false) -> Dictionary:
	# Exclusively worker-owned state, clock, grid and cache. Complete land routes
	# and ETA survive the advisory snapshot traffic prefix; pending stays pending.
	var prepared: Dictionary=_refine(st,geometry,ship,candidate,budget,true,null,2.0,complete_static051)
	prepared.origin051=point(ship)
	prepared.radius051=planning_radius(ship)
	prepared.terrainKey051=geometry.key
	prepared.terrainRevision051=geometry.revision
	prepared.observedAt051=float(st.time)
	prepared.trafficSeconds051=2.0
	if prepared.get("staticComplete051",false):
		prepared.erase("staticComplete051")
		var completed: Dictionary=_static_complete_proof051(ship,candidate,prepared)
		if not completed.is_empty():prepared.staticComplete051=completed
	if prepared.status=="blocked" and not prepared.has("staticComplete051") and not proof_budget051.is_empty():
		var rejection: Dictionary=_fixed_endpoint_rejection051(geometry,ship,candidate,proof_budget051)
		if not rejection.is_empty():prepared.staticRejection051=rejection
	return prepared

static func _static_complete_proof051(ship: Dictionary,candidate: Dictionary,prepared: Dictionary) -> Dictionary:
	# Only the completed opt-in walk can reach here. Seal both the request and
	# its exact routed output; later main metadata may change, paths may not.
	var requests: Array=[]
	var paths: Array=[]
	for leg: String in ["approach","pass","exit"]:
		var original: Variant=candidate.get(leg,[])
		var routed: Variant=prepared.candidate.get(leg,[])
		if not original is Array or original.size()>8 or not routed is Array or routed.size()>8:return {}
		var request: Array=original.duplicate()
		var path: Array=routed.duplicate()
		request.make_read_only();path.make_read_only()
		requests.append(request);paths.append(path)
	if not is_finite(float(prepared.eta)) or float(prepared.eta)<0.0:return {}
	requests.make_read_only();paths.make_read_only()
	var completed: Dictionary={"shipId":str(ship.id),"requests":requests,"paths":paths,"eta":prepared.eta}
	completed.make_read_only()
	return completed

static func _static_complete_matches051(ship: Dictionary,candidate: Dictionary,prepared: Dictionary) -> bool:
	# This lends STATIC work only. Joined ownership/order/age gates and every
	# current connector/traffic/certification/physical authority remain required.
	var completed: Variant=prepared.get("staticComplete051")
	if prepared.get("status")!="blocked" or prepared.get("reason")!="Hull occupies this approach" or not completed is Dictionary or not completed.is_read_only() or completed.get("shipId")!=str(ship.id) or candidate.get("shipId",str(ship.id))!=str(ship.id) or completed.get("eta")!=prepared.get("eta"):return false
	var requests: Variant=completed.get("requests")
	var paths: Variant=completed.get("paths")
	if not requests is Array or not requests.is_read_only() or requests.size()!=3 or not paths is Array or not paths.is_read_only() or paths.size()!=3 or not prepared.get("candidate") is Dictionary:return false
	var legs: Array=["approach","pass","exit"]
	for i: int in range(3):
		if not requests[i] is Array or not requests[i].is_read_only() or not paths[i] is Array or not paths[i].is_read_only() or requests[i]!=candidate.get(legs[i],[]) or paths[i]!=prepared.candidate.get(legs[i],[]):return false
	return true

static func _fixed_endpoint_rejection051(geometry: Dictionary,ship: Dictionary,candidate: Dictionary,proof_budget051: Dictionary) -> Dictionary:
	# Independent POINT proofs only: a blocked chord can have a legal detour,
	# and a snapshot hull can move. Never reinterpret a pending route as blocked.
	# The worker passes ONE private allowance across all hulls/offers, not a copy.
	if int(proof_budget051.clearanceTests)>=int(proof_budget051.clearanceLimit):return {}
	var paths: Array=[]
	var total: int=0
	for leg: String in ["approach","pass","exit"]:
		var path: Variant=candidate.get(leg,[])
		if not path is Array or path.size()>8:return {}
		for goal: Variant in path:
			if not goal is Vector2 or not goal.is_finite():return {}
		paths.append(path);total+=path.size()
	if total==0 or total>24:return {}
	var origin: Vector2=point(ship)
	var radius: float=planning_radius(ship)
	for path: Array in paths:
		for goal: Vector2 in path:
			if goal==origin:continue # Sampled origin is never a fixed future proof.
			var status: String=sweep(geometry,goal,goal,radius,proof_budget051)
			if status=="pending":return {}
			if status!="blocked":continue
			var fixed: Array=paths.duplicate(true)
			for points: Array in fixed:points.make_read_only()
			fixed.make_read_only()
			var rejection: Dictionary={"shipId":str(ship.id),"paths":fixed}
			rejection.make_read_only()
			return rejection
	return {}

static func _reject_prepared_static051(geometry: Dictionary,ship: Dictionary,candidate: Dictionary,prepared: Dictionary) -> bool:
	# Read-only advisory API. Caller MUST first establish its existing joined,
	# owned worker identity/age/order gate. This can deny an offer, never grant it.
	if prepared.get("status","")!="blocked" or prepared.get("terrainKey051")!=geometry.key or prepared.get("terrainRevision051")!=geometry.revision or prepared.get("radius051")!=planning_radius(ship):return false
	var value: Variant=prepared.get("staticRejection051")
	if not value is Dictionary or not value.is_read_only() or value.get("shipId")!=str(ship.id) or candidate.get("shipId",str(ship.id))!=str(ship.id):return false
	var paths: Variant=value.get("paths")
	if not paths is Array or not paths.is_read_only() or paths.size()!=3:return false
	var legs: Array=["approach","pass","exit"]
	for i: int in range(3):
		if not paths[i] is Array or not paths[i].is_read_only() or not candidate.get(legs[i]) is Array or paths[i]!=candidate[legs[i]]:return false
	if _veto_due051(str(ship.id),float(prepared.get("observedAt051",-1.0)),"route"):
		var receipt_budget051: Dictionary={"profileRoutes051":true}
		var requested_paths051: Array=[]
		for path051: Array in paths:
			var points051: Array=[]
			for goal051: Vector2 in path051:points051.append([goal051.x,goal051.y])
			requested_paths051.append(points051)
		_veto_record051(receipt_budget051,str(ship.id),float(prepared.get("observedAt051",-1.0)),"route","blocked","Joined worker fixed-endpoint land proof",str(candidate.get("candidateId","")),{"source":"joined-static-proof","clock":"worker observation; current publication time unavailable here","requestedPaths":requested_paths051})
	return true

static func _adopt_prepared051(st: Dictionary,geometry: Dictionary,ship: Dictionary,candidate: Dictionary,prepared: Dictionary,budget: Dictionary,proofs: _BeginProofs051,live_traffic_seconds051: float) -> Dictionary:
	if not bool(budget.get("profileRoutes051",false)):return _adopt_prepared_core051(st,geometry,ship,candidate,prepared,budget,proofs,live_traffic_seconds051)
	var started051: int=Time.get_ticks_usec()
	budget.vetoCapture051=_veto_due051(str(ship.id),float(st.time),"route")
	if budget.vetoCapture051:budget.erase("vetoPrimitive051")
	var result051: Dictionary=_adopt_prepared_core051(st,geometry,ship,candidate,prepared,budget,proofs,live_traffic_seconds051)
	_route_timing051(budget,"adopt",Time.get_ticks_usec()-started051)
	if result051.status!="valid" and budget.vetoCapture051 and _veto_due051(str(ship.id),float(st.time),"route"):_veto_result051(st,ship,candidate,budget,result051,"joined-worker-adoption",{"workerStatus":str(prepared.get("status","")),"workerObservedAt":float(prepared.get("observedAt051",-1.0)),"workerAge":float(st.time)-float(prepared.get("observedAt051",-1.0)),"workerTrafficHorizon":float(prepared.get("trafficSeconds051",-1.0)),"currentTrafficHorizon":0.3})
	budget.vetoCapture051=false
	return result051

static func _adopt_prepared_core051(st: Dictionary,geometry: Dictionary,ship: Dictionary,candidate: Dictionary,prepared: Dictionary,budget: Dictionary,proofs: _BeginProofs051,live_traffic_seconds051: float) -> Dictionary:
	# Private, completed+joined worker output, NEVER a corridor/certificate.
	# Missing, stale or mismatched snapshot checks use the existing main policy.
	var age: float=float(st.get("time",INF))-float(prepared.get("observedAt051",-INF))
	if (prepared.get("status","")!="valid" and not _static_complete_matches051(ship,candidate,prepared)) or prepared.get("terrainKey051")!=geometry.key or prepared.get("terrainRevision051")!=geometry.revision or prepared.get("radius051")!=planning_radius(ship) or prepared.get("trafficSeconds051")!=2.0 or not is_finite(age) or age<0.0 or age>0.15 or not prepared.get("origin051") is Vector2 or not prepared.origin051.is_finite():
		return _refine_begin051(st,geometry,ship,candidate,budget,proofs,live_traffic_seconds051)
	# The worker checked snapshot traffic for 2s. Only this renewable CURRENT
	# physical prefix is repeated here; current helm/contact/fire remain live.
	var current_traffic_seconds051: float=0.3
	var result: Dictionary=candidate.duplicate(true)
	if not _proof_scope051(proofs,geometry,st.tactical.cells,ship):proofs=null
	var previous: Vector2=point(ship)
	var radius: float=maxf(10.0,float(ship.spec.get("size",16)))+4.0
	var speed: float=maxf(1.0,float(ship.spec.get("speed",90))*float(ship.status.speedFactor)*(1.0 if float(ship.fuel)>0.0 else 0.2)*0.8)
	var elapsed: float=0.0
	var connector: bool=true
	var total: int=0
	for leg: String in ["approach","pass","exit"]:
		if bool(budget.get("vetoCapture051",false)):budget.vetoLeg051=leg
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
			if elapsed<=current_traffic_seconds051:
				var traffic_until: float=minf(until,current_traffic_seconds051)
				var traffic_end: Vector2=previous.lerp(waypoint,(traffic_until-elapsed)/(until-elapsed)) if traffic_until<until else waypoint
				var traffic: String=occupied(st.tactical.cells,ship,previous,traffic_end,radius,elapsed,traffic_until,budget,true,contact_target(ship)) if proofs==null else _occupied_begin051(proofs,st.tactical.cells,ship,previous,traffic_end,radius,elapsed,traffic_until,budget,true,contact_target(ship))
				if traffic!="valid":return {"status":traffic,"candidate":result,"eta":elapsed,"reason":"Checking hull clearance" if traffic=="pending" else "Hull occupies this approach"}
			elapsed=until;previous=waypoint
		result[leg]=points;total+=points.size()
	if total>24 or connector:return {"status":"blocked","candidate":result,"eta":elapsed}
	return {"status":"valid","candidate":result,"eta":elapsed,"reason":"Current connector and traffic clear"}

static func _refine(st: Dictionary,geometry: Dictionary,ship: Dictionary,candidate: Dictionary,budget: Dictionary,live_corridor: bool,proofs: _BeginProofs051=null,live_traffic_seconds051: float=-1.0,complete_static051: bool=false) -> Dictionary:
	var result: Dictionary=candidate.duplicate(true)
	var previous: Vector2=point(ship)
	var total: int=0
	var elapsed: float=0.0
	var traffic_blocked051: bool=false
	var finite_traffic051: bool=is_finite(live_traffic_seconds051) and live_traffic_seconds051>=0.0
	var radius: float=maxf(10.0,float(ship.spec.get("size",16)))+4.0
	var speed: float=1.0
	if live_corridor:speed=maxf(1.0,float(ship.spec.get("speed",90))*float(ship.status.speedFactor)*(1.0 if float(ship.fuel)>0.0 else 0.2)*0.8)
	for leg in ["approach","pass","exit"]:
		if bool(budget.get("vetoCapture051",false)):budget.vetoLeg051=leg
		var points: Array=[]
		for goal in candidate.get(leg,[]):
			if not goal is Vector2 or not goal.is_finite():return {"status":"blocked","candidate":result}
			var found: Dictionary=route(st,geometry,previous,goal,planning_radius(ship),budget) if proofs==null else _route(st,geometry,previous,goal,planning_radius(ship),budget,proofs,ship)
			if found.status!="valid":return {"status":found.status,"candidate":result}
			if bool(budget.get("vetoCapture051",false)):budget.erase("vetoPrimitive051")
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
						if traffic!="valid":
							if traffic=="blocked" and complete_static051:traffic_blocked051=true
							else:return {"status":traffic,"candidate":result,"eta":elapsed,"reason":"Checking hull clearance" if traffic=="pending" else "Hull occupies this approach"}
					elapsed=until;cursor=waypoint
			points.append_array(found.path)
			if points.size()>8:return {"status":"blocked","candidate":result}
			previous=goal
		result[leg]=points;total+=points.size()
	if total>24:return {"status":"blocked","candidate":result}
	if complete_static051 and traffic_blocked051:return {"status":"blocked","candidate":result,"eta":elapsed,"reason":"Hull occupies this approach","staticComplete051":true}
	if live_corridor:return {"status":"valid","candidate":result,"eta":elapsed,"reason":"Route clear"}
	return {"status":"valid","candidate":result}
