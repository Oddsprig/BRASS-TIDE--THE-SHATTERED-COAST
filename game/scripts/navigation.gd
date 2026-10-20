extends RefCounted

const DEFAULT_WIDTH := 2600.0
const DEFAULT_HEIGHT := 1800.0
const DEFAULT_CELL := 40.0
const DEFAULT_CLEARANCE := 10.0
const MAX_NODES := 5000
const CLEAR_STEP := 2.0


static func _is_finite_num(v) -> bool:
	if v is int or v is float:
		return is_finite(float(v))
	return false


static func _point_pair(p) -> Array:
	if p is Array and p.size() >= 2 and _is_finite_num(p[0]) and _is_finite_num(p[1]):
		return [float(p[0]), float(p[1])]
	if p is Vector2 and is_finite(p.x) and is_finite(p.y):
		return [float(p.x), float(p.y)]
	if p is Dictionary and _is_finite_num(p.get("x", null)) and _is_finite_num(p.get("y", null)):
		return [float(p["x"]), float(p["y"])]
	return []


static func _inside(x: float, y: float, poly: Array) -> bool:
	var inside_poly := false
	var count := poly.size()
	var j := count - 1
	for i in range(count):
		var a: Array = poly[i]
		var b: Array = poly[j]
		var ay := float(a[1])
		var by := float(b[1])
		if (ay > y) != (by > y):
			var ax := float(a[0])
			var bx := float(b[0])
			var intersect_x := (bx - ax) * (y - ay) / (by - ay) + ax
			if x < intersect_x:
				inside_poly = not inside_poly
		j = i
	return inside_poly


static func _edge_distance(x: float, y: float, a: Array, b: Array) -> float:
	var ax := float(a[0])
	var ay := float(a[1])
	var bx := float(b[0])
	var by := float(b[1])
	var dx := bx - ax
	var dy := by - ay
	var denom := dx * dx + dy * dy
	var t := 0.0
	if denom > 0.0:
		t = clampf(((x - ax) * dx + (y - ay) * dy) / denom, 0.0, 1.0)
	var px := x - ax - dx * t
	var py := y - ay - dy * t
	return sqrt(px * px + py * py)


static func is_water(nav: Dictionary, x, y, clearance = DEFAULT_CLEARANCE) -> bool:
	if nav == null or nav.is_empty():
		return false
	if not _is_finite_num(x) or not _is_finite_num(y):
		return false
	var c := DEFAULT_CLEARANCE
	if _is_finite_num(clearance):
		c = maxf(0.0, float(clearance))
	elif _is_finite_num(nav.get("clearance", null)):
		c = maxf(0.0, float(nav["clearance"]))
	var fx := float(x)
	var fy := float(y)
	var width := float(nav.get("width", DEFAULT_WIDTH))
	var height := float(nav.get("height", DEFAULT_HEIGHT))
	if fx < c or fy < c or fx > width - c or fy > height - c:
		return false
	var islands: Array = nav.get("islands", [])
	for island in islands:
		if not (island is Dictionary):
			continue
		if island.has("minX"):
			if fx < float(island["minX"]) - c or fx > float(island["maxX"]) + c or fy < float(island["minY"]) - c or fy > float(island["maxY"]) + c:
				continue
		var pts: Array = island.get("points", [])
		var n := pts.size()
		if n < 3:
			continue
		if _inside(fx, fy, pts):
			return false
		for i in range(n):
			if _edge_distance(fx, fy, pts[i], pts[(i + 1) % n]) <= c:
				return false
	return true


static func isWater(nav: Dictionary, x, y, clearance = DEFAULT_CLEARANCE) -> bool:
	return is_water(nav, x, y, clearance)


static func _clear(nav: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	var ax := float(a["x"])
	var ay := float(a["y"])
	var bx := float(b["x"])
	var by := float(b["y"])
	var c := float(nav.get("clearance", DEFAULT_CLEARANCE))
	if not is_water(nav, ax, ay, c) or not is_water(nav, bx, by, c):
		return false
	var seg_min_x := minf(ax, bx) - c
	var seg_max_x := maxf(ax, bx) + c
	var seg_min_y := minf(ay, by) - c
	var seg_max_y := maxf(ay, by) + c
	var any_overlap := false
	var islands: Array = nav.get("islands", [])
	for island in islands:
		if island is Dictionary and island.has("minX"):
			if seg_max_x >= float(island["minX"]) and seg_min_x <= float(island["maxX"]) and seg_max_y >= float(island["minY"]) and seg_min_y <= float(island["maxY"]):
				any_overlap = true
				break
		else:
			any_overlap = true
			break
	if not any_overlap:
		return true
	var dx := bx - ax
	var dy := by - ay
	var d := sqrt(dx * dx + dy * dy)
	var steps := maxi(1, int(ceil(d / CLEAR_STEP)))
	for i in range(1, steps):
		var t := float(i) / float(steps)
		if not is_water(nav, ax + dx * t, ay + dy * t, c):
			return false
	return true


static func create(islands = [], width = DEFAULT_WIDTH, height = DEFAULT_HEIGHT, cell = DEFAULT_CELL) -> Dictionary:
	var w := float(width) if (_is_finite_num(width) and float(width) > 20.0) else DEFAULT_WIDTH
	var h := float(height) if (_is_finite_num(height) and float(height) > 20.0) else DEFAULT_HEIGHT
	var c := maxf(10.0, float(cell)) if (_is_finite_num(cell) and float(cell) > 0.0) else DEFAULT_CELL
	while ceil(w / c) * ceil(h / c) >= float(MAX_NODES):
		c *= 1.05
	var clean_islands: Array = []
	if islands is Array:
		for raw_island in islands:
			if not (raw_island is Dictionary):
				continue
			var raw_pts = raw_island.get("points", null)
			if not (raw_pts is Array) or raw_pts.size() < 3:
				continue
			var pts: Array = []
			var min_x := INF
			var min_y := INF
			var max_x := -INF
			var max_y := -INF
			for raw_pt in raw_pts:
				var pair := _point_pair(raw_pt)
				if pair.size() == 2:
					var px := float(pair[0])
					var py := float(pair[1])
					pts.append([px, py])
					min_x = minf(min_x, px)
					min_y = minf(min_y, py)
					max_x = maxf(max_x, px)
					max_y = maxf(max_y, py)
			if pts.size() >= 3:
				clean_islands.append({
					"points": pts,
					"minX": min_x,
					"minY": min_y,
					"maxX": max_x,
					"maxY": max_y
				})
	var cols := int(ceil(w / c))
	var rows := int(ceil(h / c))
	var nav := {
		"width": w,
		"height": h,
		"cell": c,
		"clearance": DEFAULT_CLEARANCE,
		"cols": cols,
		"rows": rows,
		"islands": clean_islands,
		"nodes": [],
		"edges": []
	}
	var nodes: Array = nav["nodes"]
	var edges: Array = nav["edges"]
	for y in range(rows):
		for x in range(cols):
			var px := minf(w - DEFAULT_CLEARANCE, (float(x) + 0.5) * c)
			var py := minf(h - DEFAULT_CLEARANCE, (float(y) + 0.5) * c)
			if is_water(nav, px, py, DEFAULT_CLEARANCE):
				nodes.append({"x": px, "y": py})
			else:
				nodes.append(null)
			edges.append([])
	var total := nodes.size()
	for id in range(total):
		var node_a = nodes[id]
		if node_a == null:
			continue
		var cx := id % cols
		var cy := int(id / cols)
		var edge_list: Array = edges[id]
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := cx + dx
				var ny := cy + dy
				if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
					continue
				var next_id := ny * cols + nx
				var node_b = nodes[next_id]
				if node_b == null:
					continue
				if dx != 0 and dy != 0:
					if nodes[cy * cols + nx] == null or nodes[ny * cols + cx] == null:
						continue
				if _clear(nav, node_a, node_b):
					var ddx := float(node_a["x"]) - float(node_b["x"])
					var ddy := float(node_a["y"]) - float(node_b["y"])
					edge_list.append({
						"id": next_id,
						"cost": sqrt(ddx * ddx + ddy * ddy)
					})
	return nav


static func _connectors(nav: Dictionary, p: Dictionary) -> Array:
	var cell := float(nav["cell"])
	var cols := int(nav["cols"])
	var rows := int(nav["rows"])
	var nodes: Array = nav["nodes"]
	var cx := int(floor(float(p["x"]) / cell))
	var cy := int(floor(float(p["y"]) / cell))
	var out: Array = []
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= cols or y >= rows:
				continue
			var id := y * cols + x
			var n = nodes[id]
			if n != null and _clear(nav, p, n):
				var ddx := float(p["x"]) - float(n["x"])
				var ddy := float(p["y"]) - float(n["y"])
				out.append({
					"id": id,
					"cost": sqrt(ddx * ddx + ddy * ddy)
				})
	return out


static func _heap_push(heap: Array, id: int, f: float) -> void:
	var item := {"id": id, "f": f}
	var i := heap.size()
	heap.append(item)
	while i > 0:
		var parent := (i - 1) >> 1
		if float(heap[parent]["f"]) <= f:
			break
		heap[i] = heap[parent]
		i = parent
	heap[i] = item


static func _heap_pop(heap: Array) -> Dictionary:
	var top: Dictionary = heap[0]
	var last: Dictionary = heap.pop_back()
	var n := heap.size()
	if n > 0:
		var last_f := float(last["f"])
		var i := 0
		while i * 2 + 1 < n:
			var j := i * 2 + 1
			if j + 1 < n and float(heap[j + 1]["f"]) < float(heap[j]["f"]):
				j += 1
			if last_f <= float(heap[j]["f"]):
				break
			heap[i] = heap[j]
			i = j
		heap[i] = last
	return top


static func find_path(nav: Dictionary, from: Dictionary, to: Dictionary) -> Array:
	if nav == null or nav.is_empty() or from == null or to == null:
		return []
	var fx = from.get("x", null)
	var fy = from.get("y", null)
	var tx = to.get("x", null)
	var ty = to.get("y", null)
	var c := float(nav.get("clearance", DEFAULT_CLEARANCE))
	if not is_water(nav, fx, fy, c) or not is_water(nav, tx, ty, c):
		return []
	var start := {"x": fx, "y": fy}
	var end := {"x": tx, "y": ty}
	if _clear(nav, start, end):
		return [start, end]
	var begins := _connectors(nav, start)
	var ends := _connectors(nav, end)
	if begins.is_empty() or ends.is_empty():
		return []
	var goals := {}
	for n in ends:
		goals[int(n["id"])] = float(n["cost"])
	var nodes: Array = nav["nodes"]
	var edges: Array = nav["edges"]
	var count := nodes.size()
	var g := PackedFloat64Array()
	g.resize(count)
	g.fill(INF)
	var parents := PackedInt32Array()
	parents.resize(count)
	parents.fill(-1)
	var closed := PackedByteArray()
	closed.resize(count)
	closed.fill(0)
	var heap: Array = []
	var end_x := float(end["x"])
	var end_y := float(end["y"])
	for n in begins:
		var nid := int(n["id"])
		var ncost := float(n["cost"])
		if ncost < g[nid]:
			g[nid] = ncost
			var node_pos: Dictionary = nodes[nid]
			var h := sqrt(pow(float(node_pos["x"]) - end_x, 2.0) + pow(float(node_pos["y"]) - end_y, 2.0))
			_heap_push(heap, nid, ncost + h)
	var best := -1
	var best_cost := INF
	while not heap.is_empty():
		var item := _heap_pop(heap)
		var id := int(item["id"])
		if float(item["f"]) >= best_cost:
			break
		if closed[id] != 0:
			continue
		closed[id] = 1
		if goals.has(id):
			var total_goal_cost := g[id] + float(goals[id])
			if total_goal_cost < best_cost:
				best = id
				best_cost = total_goal_cost
		var adj: Array = edges[id]
		for edge in adj:
			var next_id := int(edge["id"])
			if closed[next_id] != 0:
				continue
			var cost := g[id] + float(edge["cost"])
			if cost < g[next_id]:
				g[next_id] = cost
				parents[next_id] = id
				var next_pos: Dictionary = nodes[next_id]
				var dx := float(next_pos["x"]) - end_x
				var dy := float(next_pos["y"]) - end_y
				_heap_push(heap, next_id, cost + sqrt(dx * dx + dy * dy))
	if best < 0:
		return []
	var chain: Array = [end]
	var at := best
	while at >= 0:
		var node_pt: Dictionary = nodes[at]
		chain.append({"x": float(node_pt["x"]), "y": float(node_pt["y"])})
		at = parents[at]
	chain.append(start)
	chain.reverse()
	var path: Array = [{"x": start["x"], "y": start["y"]}]
	var index := 0
	var last_idx := chain.size() - 1
	while index < last_idx:
		var next_idx := last_idx
		while next_idx > index + 1 and not _clear(nav, chain[index], chain[next_idx]):
			next_idx -= 1
		var chosen: Dictionary = chain[next_idx]
		path.append({"x": chosen["x"], "y": chosen["y"]})
		index = next_idx
	return path


static func findPath(nav: Dictionary, from: Dictionary, to: Dictionary) -> Array:
	return find_path(nav, from, to)
