extends RefCounted
## Attached to the existing skirmish fixture. Records actual advancing boats,
## production projection/meshes/effects/wake history; never invents shots or hits.
const FeedbackTest=preload("res://tests/test_feedback.gd")
const Art=preload("res://scripts/boat_art.gd")
const FX=preload("res://scripts/combat_art.gd")
const Chart=preload("res://scripts/chart.gd")
const TIMES: Array=[0.0,0.25,0.5,1.0,2.0,4.0,8.0]
var frames: Array=[]
var invalid: int=0

class FrameCanvas extends FeedbackTest.Recorder:
	var camera: Vector2=Vector2.ZERO
	var tactical: bool=false
	func project(p: Vector2,h: float=0.0) -> Vector2:
		return origin+Vector2(((p.x-camera.x)-(p.y-camera.y))*0.82,((p.x-camera.x)+(p.y-camera.y))*0.41-h)*scale_factor

func sample(game,dt: float) -> void:
	game.chart.step(dt)
	if frames.size()>=TIMES.size() or float(game.battle.time)+0.00001<float(TIMES[frames.size()]):return
	var chart=game.chart
	var size: Vector2=chart.get_viewport_rect().size
	var rec=FrameCanvas.new()
	rec.origin=size*0.5;rec.camera=chart.camera;rec.scale_factor=chart.scale_factor
	var projector: Callable=func(p: Vector2,h: float=0.0)->Vector2:return chart.project(p,h)
	for island in game.battle.islands:
		var coast:=PackedVector2Array()
		for p in island.points:coast.append(chart.project(Vector2(p[0],p[1])))
		Chart.draw_chart_coast(rec,coast)
	for raw in chart._wakes.values():
		var samples: Array=[]
		for s in raw:samples.append({"p":s.p,"d":s.d,"age":chart.clock-float(s.t),"w":s.w})
		Art.draw_wake(rec,projector,samples,{"life":chart.WAKE_LIFE_SEC})
	var boats: Array=game.battle.ships.duplicate()
	boats.sort_custom(func(a,b):return a.x+a.y<b.x+b.y)
	var actors: Array=[]
	for boat in boats:
		actors.append({"id":boat.id,"team":boat.team,"x":boat.x,"y":boat.y,"hp":boat.hp,"ammo":boat.ammo,"fuel":boat.fuel,"sunk":boat.sunk})
		if boat.sunk:continue
		var at: Vector2=chart.project(Vector2(boat.x,boat.y))
		var hull_size: float=maxf(4.0,float(boat.spec.size))
		if not Rect2(Vector2.ZERO,size).grow(120.0+hull_size*chart.scale_factor*3.2).has_point(at):continue
		var length: float=hull_size*3.9*chart.scale_factor*0.82
		var lod: int=0 if length>78.0 else (1 if length>36.0 else 2)
		var color: Color=Chart.ENEMY if boat.team=="enemy" else (Chart.GOLD if boat.id==game.battle.playerId else Chart.FRIEND)
		Art.draw_boat(rec,projector,boat,{"accent":color,"enemy":boat.team=="enemy","lod":lod,"cache":true,"combat":true,"clock":chart.clock,"battle_clock":float(game.battle.time),"px":maxf(2.0,hull_size*chart.scale_factor*0.82)})
		var bar: Vector2=chart.project(Vector2(boat.x,boat.y),-35.0)
		var width: float=maxf(35.0,hull_size*chart.scale_factor*2.5)
		rec.draw_rect(Rect2(bar-Vector2(width/2.0,0),Vector2(width,4)),Color("0b2632"))
		rec.draw_rect(Rect2(bar-Vector2(width/2.0,0),Vector2(width*clampf(float(boat.hp)/maxf(1.0,float(boat.maxHp)),0.0,1.0),4)),color)
	for shot in game.battle.projectiles:Art.draw_projectile(rec,projector,shot)
	for effect in game.battle.effects:FX.effect(rec,effect)
	invalid+=int(rec.invalid)
	frames.append({"time":game.battle.time,"actors":actors,"panel":{"id":"clash-%02d"%frames.size(),"title":"Coastal Clash %.2fs"%float(game.battle.time),"width":int(size.x),"height":int(size.y),"background":"#183e4b","primitives":rec.prims}})

func save(folder: String) -> bool:
	if folder.is_empty() or frames.is_empty():return false
	var file=FileAccess.open(folder.path_join("COASTAL CLASH FRAMES v0.041.json"),FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify({"version":"0.041","frames":frames,"invalid":invalid,"limits":"Native code-drawn boats, projection and actual battle state. HUD omitted; coast uses shared chart helper. CPU preview, not a GPU or audio capture."}));file.close()
	return invalid==0
