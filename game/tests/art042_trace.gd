extends RefCounted
## Narrow texture extension of the existing vector FeedbackRecorder.
## No invented hulls, glyph art, image extraction or offscreen game renderer.
const Feedback=preload("res://tests/test_feedback.gd")
const Art=preload("res://scripts/boat_art.gd")
const Chart=preload("res://scripts/chart.gd")

class Canvas extends Feedback.Recorder:
	var texture_draws: int=0
	var camera: Vector2=Vector2.ZERO
	var tactical: bool=false

	func project(p: Vector2,h: float=0.0) -> Vector2:
		var d: Vector2=p-camera
		return origin+Vector2((d.x-d.y)*0.82,(d.x+d.y)*0.41-h)*scale_factor

	func draw_set_transform(offset: Vector2,rotation: float=0.0,scale: Vector2=Vector2.ONE) -> void:
		transform=Transform2D(rotation,scale,0.0,offset)

	func draw_texture_rect_region(texture: Texture2D,rect: Rect2,source: Rect2,modulate: Color=Color.WHITE,transpose: bool=false,clip_uv: bool=true) -> void:
		if texture==null or texture.resource_path.is_empty() or not FileAccess.file_exists(texture.resource_path):
			invalid+=1
			return
		if rect.size.x<=0.0 or rect.size.y<=0.0 or source.size.x<=0.0 or source.size.y<=0.0:
			invalid+=1
			return
		var texture_size: Vector2=Vector2(texture.get_width(),texture.get_height())
		if source.position.x<0.0 or source.position.y<0.0 or source.end.x>texture_size.x+0.01 or source.end.y>texture_size.y+0.01:
			invalid+=1
		var points:=PackedVector2Array([
			transform*rect.position,
			transform*(rect.position+Vector2(rect.size.x,0.0)),
			transform*rect.end,
			transform*(rect.position+Vector2(0.0,rect.size.y))])
		texture_draws+=1
		prims.append({"t":"texture","path":texture.resource_path,"src":[source.position.x,source.position.y,source.size.x,source.size.y],"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"pts":_points(points),"c":_color(modulate),"transpose":transpose,"clip_uv":clip_uv,"texture_size":[texture_size.x,texture_size.y]})

	func draw_texture_rect(texture: Texture2D,rect: Rect2,tile: bool,modulate: Color=Color.WHITE,transpose: bool=false) -> void:
		# The v042 renderer uses finite atlas regions, never repeating image tiles.
		if texture==null or tile:
			invalid+=1
			return
		draw_texture_rect_region(texture,rect,Rect2(Vector2.ZERO,Vector2(texture.get_width(),texture.get_height())),modulate,transpose)

	func draw_texture(texture: Texture2D,position: Vector2,modulate: Color=Color.WHITE) -> void:
		if texture==null:
			invalid+=1
			return
		draw_texture_rect(texture,Rect2(position,Vector2(texture.get_width(),texture.get_height())),false,modulate)

	func draw_string(_font: Font,position: Vector2,value: String,alignment: int=0,width: float=-1.0,font_size: int=16,modulate: Color=Color.WHITE,_justification_flags: int=3,_direction: int=0,_orientation: int=0) -> void:
		prims.append({"t":"text","pts":_points(PackedVector2Array([transform*position])),"text":value,"font_size":font_size,"alignment":alignment,"width":width,"c":_color(modulate)})

	func textures() -> Array:
		return prims.filter(func(p):return str(p.get("t",""))=="texture")

	func panel(id: String,title: String,view_size: Vector2) -> Dictionary:
		return {"id":id,"title":title,"width":int(view_size.x),"height":int(view_size.y),"background":"#183e4b","primitives":prims,"texture_draws":texture_draws,"mesh_draws":mesh_draws,"invalid":invalid}

## Uses the real launched Lab's camera, projection, fit, LOD and boat ordering.
## Mirrors the existing clash_capture041 adapter; only textures are added.
static func battle_canvas(game) -> Canvas:
	var rec:=Canvas.new()
	var chart=game.chart
	var view_size: Vector2=chart.get_viewport_rect().size
	rec.origin=view_size*0.5
	rec.camera=chart.camera
	rec.scale_factor=chart.scale_factor
	var projector: Callable=chart.project
	for island in game.battle.islands:
		var coast:=PackedVector2Array()
		for p in island.points:coast.append(chart.project(Vector2(p[0],p[1])))
		Chart.draw_chart_coast(rec,coast)
	var boats: Array=game.battle.ships.duplicate()
	boats.sort_custom(func(a,b):return a.x+a.y<b.x+b.y)
	for boat in boats:
		if boat.sunk:continue
		var hull_size: float=maxf(4.0,float(boat.spec.size))
		if not Rect2(Vector2.ZERO,view_size).grow(120.0+hull_size*chart.scale_factor*3.2).has_point(chart.project(Vector2(boat.x,boat.y))):continue
		var length: float=hull_size*3.9*chart.scale_factor*0.82
		var lod: int=0 if length>78.0 else (1 if length>36.0 else 2)
		var color: Color=Chart.ENEMY if boat.team=="enemy" else (Chart.GOLD if boat.id==game.battle.playerId else Chart.FRIEND)
		Art.draw_boat(rec,projector,boat,{"accent":color,"enemy":boat.team=="enemy","lod":lod,"cache":true,"combat":true,"clock":chart.clock,"battle_clock":float(game.battle.time),"px":maxf(2.0,hull_size*chart.scale_factor*0.82),"enlargement":1.0})
	return rec
