extends RefCounted
## Shared inexpensive chart land artwork. The live chart and native Recorder
## use these same prepared coast/shallows/contours, with no second mock map.

static func settlement_plan(port: Dictionary,islands: Array) -> Dictionary:
	var berth:=Vector2(float(port.x),float(port.y))
	var best: float=INF
	var anchor:=berth
	var inland:=Vector2.LEFT
	var land:=PackedVector2Array()
	for island in islands:
		var ring:=PackedVector2Array()
		for p in island.points:ring.append(Vector2(p[0],p[1]))
		for i in range(ring.size()):
			var a: Vector2=ring[i];var b: Vector2=ring[(i+1)%ring.size()]
			var at: Vector2=Geometry2D.get_closest_point_to_segment(berth,a,b)
			var distance: float=at.distance_squared_to(berth)
			if distance>=best:continue
			best=distance;anchor=at;land=ring
			inland=(b-a).orthogonal().normalized()
			if not Geometry2D.is_point_in_polygon(anchor+inland*25.0,ring):inland=-inland
	var tangent: Vector2=inland.orthogonal()
	var roofs: Array=[]
	for row in range(3):
		for column in range(4):
			var at: Vector2=anchor+inland*(44.0+row*42.0)+tangent*(float(column)-1.5)*42.0
			var points:=PackedVector2Array()
			var fits: bool=true
			for offset in [Vector2(-15,-13),Vector2(15,-13),Vector2(15,13),Vector2(-15,13)]:
				var q: Vector2=at+tangent*offset.x+inland*offset.y
				points.append(q)
				fits=fits and Geometry2D.is_point_in_polygon(q,land)
			if fits:roofs.append(points)
	var color:=Color("a98052")
	if str(port.get("faction",""))=="forge":color=Color("a96146")
	elif str(port.get("faction",""))=="reed":color=Color("648979")
	elif str(port.get("faction",""))=="raiders":color=Color("8c6460")
	return {"anchor":anchor,"berth":berth,"inland":inland,"roofs":roofs,"color":color}

static func draw_settlement(canvas,projector: Callable,plan: Dictionary) -> void:
	if plan.is_empty():return
	var shore: Vector2=projector.call(plan.anchor,0.0)
	var berth: Vector2=projector.call(plan.berth,0.0)
	canvas.draw_line(shore,berth,Color("796546"),5.0,true)
	canvas.draw_line(shore,berth,Color("c9b68b"),2.0,true)
	var lane_end: Vector2=projector.call(plan.anchor+plan.inland*155.0,0.0)
	canvas.draw_line(shore,lane_end,Color("b2a783"),3.0,true)
	for roof in plan.roofs:
		var points: PackedVector2Array=screen_ring(projector,roof)
		canvas.draw_polyline(PackedVector2Array([points[0],points[1],points[2],points[3],points[0]]),Color("3e4c3d"),3.0,true)
		canvas.draw_colored_polygon(points,plan.color)
		var middle_a: Vector2=(points[0]+points[1])*0.5
		var middle_b: Vector2=(points[2]+points[3])*0.5
		canvas.draw_colored_polygon(PackedVector2Array([points[0],middle_a,middle_b,points[3]]),Color(plan.color).lightened(0.18))
		canvas.draw_line(middle_a,middle_b,Color("d4c3a2"),0.75,true)

static func screen_ring(projector: Callable,points: PackedVector2Array) -> PackedVector2Array:
	var screen:=PackedVector2Array()
	for p in points:screen.append(projector.call(p,0.0))
	return screen

static func draw(canvas,projector: Callable,points: PackedVector2Array,sheet: Dictionary,close: bool) -> void:
	if points.size()<3:return
	var shoal: PackedVector2Array=sheet.get("shoal",PackedVector2Array())
	if close and shoal.size()>=3:
		canvas.draw_colored_polygon(screen_ring(projector,shoal),Color(0.55,0.74,0.68,0.28))
	var coast: PackedVector2Array=screen_ring(projector,points)
	var ground: Color=sheet.get("ground",Color("69836a"))
	canvas.draw_colored_polygon(coast,ground)
	if close:
		var high: Color=sheet.get("high",ground.darkened(0.15))
		var index: int=0
		for ring in sheet.get("contours",[]):
			canvas.draw_colored_polygon(screen_ring(projector,ring),high if index==0 else high.darkened(0.12))
			index+=1
		for mark in sheet.get("marks",[]):
			var at: Vector2=projector.call(mark[0],0.0)
			var end: Vector2=projector.call(mark[1],0.0)
			var size: float=clampf(at.distance_to(end),3.0,10.0)
			var kind: String=str(mark[2]) if mark.size()>2 else "line"
			if kind=="trees":
				var crown:=PackedVector2Array([at+Vector2(0,-size),at+Vector2(size*0.55,size*0.45),at+Vector2(-size*0.55,size*0.45)])
				canvas.draw_line(at,at+Vector2(0,size*0.85),Color("445238"),1.0,true)
				canvas.draw_colored_polygon(crown,Color("365942"))
				canvas.draw_colored_polygon(PackedVector2Array([crown[0],crown[1],at+Vector2(0,size*0.45)]),Color("527c55"))
			elif kind=="ridge":
				canvas.draw_polyline(PackedVector2Array([at+Vector2(-size,size*0.4),at+Vector2(0,-size*0.7),at+Vector2(size,size*0.4)]),Color(ground.darkened(0.36),0.75),1.2,true)
				canvas.draw_line(at+Vector2(0,-size*0.7),at+Vector2(size*0.2,size*0.3),Color(ground.lightened(0.22),0.7),1.0,true)
			elif kind=="reeds":
				for dx in [-0.5,0.0,0.5]:
					canvas.draw_line(at+Vector2(dx*size,size*0.5),at+Vector2(dx*size+size*0.18,-size*0.5),Color("42664a"),1.1,true)
			else:canvas.draw_line(at,end,Color(ground.darkened(0.28),0.55),1.0,true)
	var outline: PackedVector2Array=coast.duplicate()
	outline.append(coast[0])
	canvas.draw_polyline(outline,Color("e2d2a4") if close else Color("dac48b"),1.6 if close else 2.0,true)
