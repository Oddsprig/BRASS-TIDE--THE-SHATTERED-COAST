extends SceneTree
## Root runs this source fixture; captures the actual production chart helpers.
const Chart=preload("res://scripts/chart.gd")
const FeedbackTest=preload("res://tests/test_feedback.gd")
var checks: int=0
var failures: int=0

class ChartRecorder extends FeedbackTest.Recorder:
	var labels: Array=[]
	func draw_string(_font: Font,at: Vector2,text: String,_alignment: int=0,_width: float=-1,font_size: int=16,color: Color=Color.WHITE) -> void:
		labels.append({"text":text,"at":[at.x,at.y],"size":font_size,"c":[color.r,color.g,color.b,color.a]})

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("CHART040: "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.size=Vector2i(1600,1000)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var sites: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/island_sites.json")).sites
	var original: PackedByteArray=var_to_bytes(data)
	var home: Dictionary=data.PORTS[0]
	var home_position:=Vector2(home.x,home.y)
	var chart=Chart.new()
	root.add_child(chart)
	# Only camera data is needed: no new campaign, workers, route finding or upload.
	chart.host={"mode":"campaign","data":data,"core":{"state":{"position":{"x":home.x,"y":home.y}}}}
	chart.sans=SystemFont.new();chart.sans.font_names=PackedStringArray(["Bahnschrift","Segoe UI"])
	chart.territory_view()
	chart.scale_factor=chart.regional_scale()*chart.zoom
	var territory_scale: float=chart.scale_factor
	check(chart.campaign_overview() and not chart.follow_camera,"M shows strategic overview and disables follow")
	var fit_bounds: Rect2=Chart.chart_label_bounds(Vector2(1600,1000)).grow(-39)
	var coasts_fit: bool=true
	for island in data.ISLANDS:
		for point in island.points:coasts_fit=coasts_fit and fit_bounds.has_point(chart.project(Vector2(point[0],point[1])))
	for port in data.PORTS:coasts_fit=coasts_fit and fit_bounds.has_point(chart.project(Vector2(port.x,port.y)))
	check(coasts_fit,"M fits all authored coastlines and harbor hit centers inside the usable chart area")
	var center: Vector2=chart.project(home_position)
	check(chart.world_at(center).distance_to(home_position)<0.001,"projected harbor center remains the exact inverse/hit position")
	var rec=ChartRecorder.new()
	for island in data.ISLANDS:
		var coast:=PackedVector2Array()
		for p in island.points:coast.append(chart.project(Vector2(p[0],p[1])))
		Chart.draw_chart_coast(rec,coast)
	check(rec.prims.size()==data.ISLANDS.size()*2,"overview coast uses one actual polygon plus a closed constant-width outline")
	var entries: Array=[]
	for port in data.PORTS:
		var at: Vector2=chart.project(Vector2(port.x,port.y))
		var selected: bool=port.id==home.id
		Chart.draw_chart_marker(rec,Chart.chart_marker_geometry("harbor",at,territory_scale),Chart.GOLD if selected else Chart.FRIEND,selected)
		entries.append({"at":at,"text":port.name,"priority":110 if selected else 60,"color":Chart.GOLD if selected else Chart.FRIEND})
	# Authored coordinates and real production geometry, with known sites exposed
	# explicitly for this capture; no discovery or reward state is changed.
	for site in sites:
		var at: Vector2=chart.project(Vector2(site.x,site.y))
		Chart.draw_chart_marker(rec,Chart.chart_marker_geometry("site",at,territory_scale),Chart.FRIEND)
		entries.append({"at":at,"text":site.name,"priority":20,"color":Chart.FRIEND})
	var fleet_geometry: Dictionary=Chart.chart_marker_geometry("fleet",center,territory_scale,0.0)
	var start: int=rec.prims.size()
	Chart.draw_chart_marker(rec,fleet_geometry,Chart.GOLD,true)
	check(rec.prims.size()-start==3,"overview flotilla is exactly one shared fleet symbol and selection ring")
	entries.append({"at":center,"text":"YOUR FLOTILLA","priority":105,"color":Chart.GOLD})
	var before_entries: PackedByteArray=var_to_bytes(entries)
	var bounds: Rect2=Chart.chart_label_bounds(Vector2(1600,1000))
	var layout: Array=Chart.chart_label_layout(entries,bounds,chart.sans)
	check(not layout.is_empty() and layout[0].text==home.name,"selected harbor receives first label placement in actual crowded overview")
	check(layout.any(func(label):return str(label.text)=="YOUR FLOTILLA"),"player label remains readable at the same physical harbor position")
	var collision: bool=false
	for i in range(layout.size()):
		check(bounds.encloses(layout[i].rect) and int(layout[i].font_size)>=14,"placed label has readable type and stays clear of HUD edges")
		for j in range(i):collision=collision or Rect2(layout[i].rect).grow(3).intersects(layout[j].rect)
		Chart.draw_chart_label(rec,layout[i],chart.sans)
	check(not collision,"production label plates do not overlap")
	check(var_to_bytes(entries)==before_entries and Chart.chart_label_layout(entries,bounds,chart.sans)==layout,"label placement is read-only and repeatable")
	var panel: Dictionary={"id":"territory","title":"Actual M overview: authored coast / ports / known sites / one flotilla","width":1600,"height":1000,"background":"#183e4b","primitives":rec.prims,"labels":rec.labels}
	var overview_invalid: int=rec.invalid
	# Same centers/symbol calculation at territory, regional and close zoom. The
	# upper bounds stay within Main's existing 15px fleet and 22px site hit radii.
	var glyphs=ChartRecorder.new()
	for kind in ["harbor","fleet","site"]:
		var row: int=["harbor","fleet","site"].find(kind)
		for i in range(3):
			var scale_value: float=[territory_scale,chart.regional_scale(),1.8][i]
			var at:=Vector2(95+i*145,100+row*110)
			var geometry: Dictionary=Chart.chart_marker_geometry(kind,at,scale_value,0.0)
			var before_geometry: PackedByteArray=var_to_bytes(geometry)
			start=glyphs.prims.size()
			Chart.draw_chart_marker(glyphs,geometry,Chart.FRIEND)
			check(float(geometry.radius)>=7.0 and float(geometry.radius)<=12.0 and geometry.center==at,"screen-readable bounded marker keeps exact center: "+kind)
			check(glyphs.prims.size()-start<=3 and var_to_bytes(geometry)==before_geometry,"marker primitives are bounded and read-only: "+kind)
			for point in geometry.points:check(Vector2(point).distance_to(at)<=float(geometry.radius)*1.1,"fleet/site geometry fits its screen radius")
	var panels: Array=[panel,{"id":"symbols","title":"Harbor / fleet / site at M, Home and close zoom","width":520,"height":430,"background":"#183e4b","primitives":glyphs.prims,"labels":[]}]
	chart.center_camera();chart.scale_factor=chart.regional_scale()
	check(chart.follow_camera and chart._campaign_follow and chart.zoom==1.0 and chart.camera==home_position and not chart.campaign_overview(),"Home retains fleet centering and normal regional zoom")
	check(chart.project(home_position).distance_to(Vector2(800,500))<0.001,"Home puts the exact hit center at viewport center")
	chart.pan_camera(Vector2.RIGHT,0.1)
	check(not chart.follow_camera and not chart._campaign_follow and chart.project(home_position).distance_to(Vector2(746,500))<0.01,"WASD pan retains screen direction, speed and follow release")
	check(var_to_bytes(data)==original and data.HULLS.size()==36,"chart helpers leave authored map and all 36 boats unchanged")
	check(overview_invalid==0 and glyphs.invalid==0,"all actual coast and marker primitives are finite and triangulable")
	chart.free()
	var directory: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
		var file=FileAccess.open(directory.path_join("chart-readability040.json"),FileAccess.WRITE)
		check(file!=null,"native chart capture opens")
		if file!=null:
			file.store_string(JSON.stringify({"checks":checks,"failures":failures,"panels":panels,"territoryScale":territory_scale,"limits":"Actual production projection / marker / coast / label calls. Capture exposes authored sites for review. No GPU gameplay, worker, input or route mutation; font baselines recorded separately for CPU annotation."}));file.close()
	print("CHART040: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
