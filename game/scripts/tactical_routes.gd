extends RefCounted
## Battle-local geometry. No Battle dependency, live callbacks or campaign routes.
const WIDTH: float=2300.0
const HEIGHT: float=1700.0
const CACHE_LIMIT: int=128

static func spend(budget: Dictionary, count: int=1) -> bool:
	if int(budget.clearanceTests)+count>int(budget.get("clearanceLimit",4096)):
		budget.exhaustions+=1
		return false
	budget.clearanceTests+=count
	return true

static func point(s: Dictionary) -> Vector2:
	return Vector2(float(s.x),float(s.y))

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

static func grid(ships: Array) -> Dictionary:
	var cells: Dictionary={"_maxSpeed":0.0}
	for ship in ships:
		if ship.get("sunk",false) or ship.get("captureSecured",false):continue
		var r: float=maxf(10.0,float(ship.spec.get("size",16)))
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
	var lo: Vector2=a.min(b)-Vector2.ONE*r
	var hi: Vector2=a.max(b)+Vector2.ONE*r
	var result: Array=[]
	var seen: Dictionary={}
	for x in range(maxi(-2,floori(lo.x/160.0)),mini(17,floori(hi.x/160.0))+1):
		for y in range(maxi(-2,floori(lo.y/160.0)),mini(13,floori(hi.y/160.0))+1):
			for other in cells.get(Vector2i(x,y),[]):
				if not seen.has(str(other.id)):
					seen[str(other.id)]=true;result.append(other)
	return result

static func occupied(cells: Dictionary,ship: Dictionary,a: Vector2,b: Vector2,r: float,from: float,until: float,budget: Dictionary) -> String:
	var extra: float=maxf(0.0,until-2.0)*float(cells.get("_maxSpeed",0.0))
	for other in neighbours(cells,a,b,r+80.0+extra):
		if str(other.id)==str(ship.id) or other.team!=ship.team:continue
		if not spend(budget):return "pending"
		var velocity: Vector2=Vector2(other.vx,other.vy)
		# Full corridor occupancy uses observed constant-velocity prediction. Beyond
		# the two-second physical prefix it is conditional, never an escape promise.
		var c: Vector2=point(other)+velocity*from
		var d: Vector2=point(other)+velocity*until
		var relative: Vector2=a-c
		var delta: Vector2=(b-a)-(d-c)
		var fraction: float=clampf(-relative.dot(delta)/maxf(0.000001,delta.length_squared()),0.0,1.0)
		if (relative+delta*fraction).length()<r+maxf(10.0,float(other.spec.get("size",16)))+3.0:return "blocked"
	return "valid"

static func route(st: Dictionary,geometry: Dictionary,a: Vector2,b: Vector2,r: float,budget: Dictionary) -> Dictionary:
	var key: String=JSON.stringify([geometry.key,r,a.x,a.y,b.x,b.y]).sha256_text()
	var cache: Dictionary=st.tactical.routeCache
	if cache.has(key):
		budget.cacheHits+=1
		return {"status":"valid","path":cache[key].duplicate()}
	# Direct segment checks are bounded geometry, not graph searches.
	var direct: String=sweep(geometry,a,b,r,budget)
	if direct=="pending":return {"status":"pending","path":[]}
	if direct=="valid":return {"status":"valid","path":[b]}
	if int(budget.fullRoutes)>=4:
		budget.exhaustions+=1
		return {"status":"pending","path":[]}
	budget.fullRoutes+=1 # Failed searches spend the same global query allowance.
	var nodes: Array=[a,b]
	for obstacle in geometry.obstacles:
		var center: Vector2=Vector2.ZERO
		for p in obstacle.points:center+=Vector2(p[0],p[1])
		center/=float(obstacle.points.size())
		for p in obstacle.points:
			var v: Vector2=Vector2(p[0],p[1])
			var n: Vector2=v+(v-center).normalized()*(r*2.5+12.0)
			if nodes.size()>=128:return {"status":"pending","path":[]}
			nodes.append(n)
	var costs: Array=[]
	var previous: Array=[]
	var closed: Dictionary={}
	var edges: Dictionary={}
	for i in range(nodes.size()):costs.append(INF);previous.append(-1)
	costs[0]=0.0
	for iteration in range(nodes.size()):
		var current: int=-1
		var best: float=INF
		for i in range(nodes.size()):
			if not closed.has(i) and float(costs[i])+nodes[i].distance_to(b)<best:
				best=float(costs[i])+nodes[i].distance_to(b);current=i
		if current<0:break
		if current==1:
			var path: Array=[]
			var at: int=1
			while at>0:
				path.push_front(nodes[at]);at=int(previous[at])
				if path.size()>8:return {"status":"blocked","path":[]}
			if cache.size()>=CACHE_LIMIT:cache.erase(cache.keys()[0])
			cache[key]=path.duplicate()
			return {"status":"valid","path":path}
		closed[current]=true
		for next in range(nodes.size()):
			if closed.has(next) or next==current:continue
			var edge_key: Vector2i=Vector2i(mini(current,next),maxi(current,next))
			if not edges.has(edge_key):edges[edge_key]=sweep(geometry,nodes[current],nodes[next],r,budget)
			if edges[edge_key]=="pending":return {"status":"pending","path":[]}
			if edges[edge_key]!="valid":continue
			var cost: float=float(costs[current])+nodes[current].distance_to(nodes[next])
			if cost<float(costs[next]):costs[next]=cost;previous[next]=current
	return {"status":"blocked","path":[]}

static func refine(st: Dictionary,geometry: Dictionary,ship: Dictionary,candidate: Dictionary,budget: Dictionary) -> Dictionary:
	var result: Dictionary=candidate.duplicate(true)
	var previous: Vector2=point(ship)
	var total: int=0
	for leg in ["approach","pass","exit"]:
		var points: Array=[]
		for goal in candidate.get(leg,[]):
			if not goal is Vector2 or not goal.is_finite():return {"status":"blocked","candidate":result}
			var found: Dictionary=route(st,geometry,previous,goal,maxf(10.0,float(ship.spec.get("size",16)))+4.0,budget)
			if found.status!="valid":return {"status":found.status,"candidate":result}
			points.append_array(found.path)
			if points.size()>8:return {"status":"blocked","candidate":result}
			previous=goal
		result[leg]=points;total+=points.size()
	if total>24:return {"status":"blocked","candidate":result}
	return {"status":"valid","candidate":result}
