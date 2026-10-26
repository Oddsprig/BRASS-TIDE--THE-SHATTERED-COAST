extends RefCounted
## A translated window of the existing coast, never a second world map.
const WIDTH: float=2300.0
const HEIGHT: float=1700.0

static func arena(data: Dictionary,position: Dictionary) -> Dictionary:
	var origin: Vector2=Vector2(float(position.x)-WIDTH*0.5,float(position.y)-HEIGHT*0.5)
	var window: Rect2=Rect2(origin,Vector2(WIDTH,HEIGHT))
	var islands: Array=[]
	var names: PackedStringArray=[]
	for island in data.get("ISLANDS",[]):
		var source: Array=island.get("points",[])
		if source.size()<3:continue
		var bounds: Rect2=Rect2(Vector2(source[0][0],source[0][1]),Vector2.ZERO)
		for p in source:bounds=bounds.expand(Vector2(p[0],p[1]))
		if not window.intersects(bounds,true):continue
		var local: Dictionary=island.duplicate(true)
		local.points=[]
		for p in source:local.points.append([float(p[0])-origin.x,float(p[1])-origin.y])
		islands.append(local)
		names.append(str(island.get("name","Coast")))
	var name: String="Open water" if names.is_empty() else " / ".join(names)+(" passage" if names.size()>1 else " approaches")
	# Presence matters: a genuinely empty window must not restore laboratory islands.
	return {"islands":islands,"coastalEncounter":true,"location":{"name":name,"campaignPosition":position.duplicate(true),"origin":{"x":origin.x,"y":origin.y}}}
