extends RefCounted
## Shared inexpensive chart land artwork. The live chart and native Recorder
## use these same prepared coast/shallows/contours, with no second mock map.

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
			canvas.draw_line(projector.call(mark[0],0.0),projector.call(mark[1],0.0),Color(ground.darkened(0.28),0.55),1.0,true)
	var outline: PackedVector2Array=coast.duplicate()
	outline.append(coast[0])
	canvas.draw_polyline(outline,Color("e2d2a4") if close else Color("dac48b"),1.6 if close else 2.0,true)
