extends SceneTree
const Art=preload("res://scripts/boat_art.gd")
const Damage=preload("res://scripts/damage.gd")
const Refit=preload("res://scripts/refit.gd")
class Page extends Node2D:
	var boats: Array=[]
	var heading: float=0.55
	var cache: bool=true
	var font: Font=ThemeDB.fallback_font
	func _draw() -> void:
		draw_rect(Rect2(0,0,1920,1200),Color("183e4b"))
		for i in range(boats.size()):
			var at: Vector2=Vector2((i%6)*320+160,(i/6)*185+102)
			var boat: Dictionary=boats[i]
			boat.angle=heading
			var projection: Callable=func(p: Vector2,h: float=0.0) -> Vector2:
				return at+Vector2((p.x-p.y)*0.82,(p.x+p.y)*0.41-h)*0.95
			Art.draw_boat(self,projection,boat,{"lod":0,"cache":cache,"px":float(boat.spec.size)*0.95*0.82,"combat":false})
			draw_string(font,at+Vector2(-145,70),str(boat.spec.name),HORIZONTAL_ALIGNMENT_LEFT,290,14,Color("dfbd7d"))
var page: Page
var started: int
func _initialize() -> void:
	started=Time.get_ticks_msec()
	call_deferred("run")
func run() -> void:
	root.content_scale_size=Vector2i(1920,1200)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	page=Page.new()
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	for spec in world.HULLS:
		var boat: Dictionary=Damage.create_ship(Refit.effective_spec(spec,Refit.defaults(spec)))
		boat.loadout=Refit.defaults(spec)
		page.boats.append(boat)
	if page.boats.size()!=36:push_error("Expected existing36 boats");quit(1);return
	root.add_child(page)
	for pose in [{"name":"front-cached","heading":0.55,"cache":true},{"name":"back-cached","heading":PI+0.55,"cache":true},{"name":"front-direct","heading":0.55,"cache":false},{"name":"back-direct","heading":PI+0.55,"cache":false}]:
		page.heading=pose.heading;page.cache=pose.cache;page.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var path: String=OS.get_environment("GAME_TEST_ARTIFACTS").path_join(str(pose.name)+".png")
		if root.get_texture().get_image().save_png(path)!=OK:quit(1);return
		print("ART102_CAPTURE ",path)
		if Time.get_ticks_msec()-started>18000:push_error("ART102 body cap");quit(1);return
	print("ART102_DONE ",JSON.stringify({"boats":page.boats.size(),"views":4,"authoredAtlasCanvasPath":true,"scope":"Review gallery, not normal-play acceptance or motion proof","elapsedMs":Time.get_ticks_msec()-started}))
	quit(0)
