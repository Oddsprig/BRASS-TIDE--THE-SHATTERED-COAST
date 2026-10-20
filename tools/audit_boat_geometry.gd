extends SceneTree
const Art=preload("res://scripts/boat_art.gd")
const Refit=preload("res://scripts/refit.gd")
class CanvasAudit extends RefCounted:
	var label=""
	var invalid: Array=[]
	var polygons=0
	func draw_colored_polygon(points: PackedVector2Array,_color: Color):
		polygons+=1
		if Geometry2D.triangulate_polygon(points).is_empty():
			invalid.append({"label":label,"index":polygons,"points":str(points)})
	func draw_line(_a,_b,_c,_w=1.0,_aa=false):pass
	func draw_polyline(_p,_c,_w=1.0,_aa=false):pass
	func draw_circle(_p,_r,_c):pass
	func draw_arc(_p,_r,_a,_b,_n,_c,_w=1.0,_aa=false):pass
func _initialize():
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var audit=CanvasAudit.new()
	var projector=func(p: Vector2,h: float):return Vector2(350,230)+Vector2((p.x-p.y)*0.82,(p.x+p.y)*0.41-h)*2.0
	for spec in world.HULLS:
		var fitted: Dictionary=Refit.effective_spec(spec,Refit.defaults(spec))
		for heading in range(360):
			for lod in range(3):
				for moving in [false,true]:
					audit.label="%s heading%d lod%d moving%s"%[spec.id,heading,lod,str(moving)]
					var boat: Dictionary=Art.preview_boat(fitted,heading*TAU/360.0)
					boat.vx=60.0 if moving else 0.0
					Art.draw_boat(audit,projector,boat,{"lod":lod,"px":30.0,"clock":1.2})
	print("GEOMETRY: ",audit.polygons," polygons; ",audit.invalid.size()," invalid")
	for i in range(mini(12,audit.invalid.size())):print(JSON.stringify(audit.invalid[i]))
	quit(0 if audit.invalid.is_empty() else 1)
