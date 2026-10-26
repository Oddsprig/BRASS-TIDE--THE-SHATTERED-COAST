extends SceneTree
## Root runs this source fixture; captures the actual production chart helpers.
const Chart=preload("res://scripts/chart.gd")
const FeedbackTest=preload("res://tests/test_feedback.gd")
const Navigation=preload("res://scripts/navigation.gd")
const CoastMigration=preload("res://scripts/coast_migration.gd")
const NauticalArt=preload("res://scripts/nautical_art.gd")
const Campaign=preload("res://scripts/campaign.gd")
const Money=preload("res://scripts/money.gd")
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
	# Production chart helpers only. Route checks use Navigation on the authored coast.
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
	var saved_scale: float=chart.scale_factor
	var saved_camera: Vector2=chart.camera
	var origin: Vector2=chart.get_viewport_rect().size*0.5
	chart.scale_factor=1.0
	chart.camera=home_position
	var east: Vector2=chart.project(home_position+Vector2(100,0))
	var south: Vector2=chart.project(home_position+Vector2(0,100))
	check(east.distance_to(origin+Vector2(100,0))<0.001 and south.distance_to(origin+Vector2(0,100))<0.001,"campaign chart axes are uniform and square")
	check(chart.world_at(east).distance_to(home_position+Vector2(100,0))<0.001,"campaign pan/hit inverse matches the top-down chart")
	chart.host.mode="battle"
	var iso: Vector2=chart.project(home_position+Vector2(100,0))
	check(iso.distance_to(origin+Vector2(82,41))<0.001,"battle keeps the isometric boat projection")
	check(chart.world_at(iso).distance_to(home_position+Vector2(100,0))<0.001,"battle hit inverse matches the isometric projection")
	chart.host.mode="campaign"
	chart.scale_factor=saved_scale
	chart.camera=saved_camera
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
	# Same prepared land materials and same draw function as production Home view.
	chart._ensure_chart_sheet()
	var home_rec=ChartRecorder.new()
	var home_projector: Callable=func(p: Vector2,h: float=0.0)->Vector2:return chart.project(p,h)
	for index in range(data.ISLANDS.size()):
		NauticalArt.draw(home_rec,home_projector,chart.polygon(data.ISLANDS[index].points),chart._chart_sheet[index],true)
	Chart.draw_chart_marker(home_rec,Chart.chart_marker_geometry("harbor",chart.project(home_position),chart.scale_factor),Chart.GOLD,true)
	Chart.draw_chart_marker(home_rec,Chart.chart_marker_geometry("fleet",chart.project(home_position)+Vector2(28,16),chart.scale_factor),Chart.GOLD)
	var home_labels: Array=Chart.chart_label_layout([{"at":chart.project(home_position),"text":str(home.name),"priority":110,"subtitle":"HOME HARBOR","color":Chart.GOLD}],bounds,chart.sans)
	for label in home_labels:Chart.draw_chart_label(home_rec,label,chart.sans)
	panels.append({"id":"home","title":"Normal Home zoom: actual coast, shallows and contours","width":1600,"height":1000,"background":"#183e4b","primitives":home_rec.prims,"labels":home_rec.labels})
	check(home_rec.invalid==0,"normal chart materials use finite triangulable production geometry")
	var nearest: Dictionary=data.ISLANDS[0]
	var nearest_d: float=INF
	for island in data.ISLANDS:
		var centroid:=Vector2.ZERO
		for point in island.points:centroid+=Vector2(point[0],point[1])
		centroid/=maxf(1,island.points.size())
		if centroid.distance_to(home_position)<nearest_d:
			nearest_d=centroid.distance_to(home_position)
			nearest=island
	var land:=Rect2()
	var land_started:=false
	for point in nearest.points:
		var screen_point: Vector2=chart.project(Vector2(point[0],point[1]))
		if not land_started:
			land=Rect2(screen_point,Vector2.ZERO);land_started=true
		else:land=land.expand(screen_point)
	check(land.size.x>420.0 and land.size.y>420.0,"Home shows a substantial nearby coast")
	check(land.grow(200).has_point(chart.project(home_position)),"Home harbor sits against that coast")
	var nav: Dictionary=Navigation.create(data.ISLANDS,data.WORLD.width,data.WORLD.height)
	var ports_by_id: Dictionary={}
	for port in data.PORTS:
		ports_by_id[port.id]=port
		check(Navigation.is_water(nav,port.x,port.y,36.0),"harbor stays navigable for the largest hull: "+str(port.id))
	for route in data.ROUTES:
		var route_a: Dictionary=ports_by_id[route[0]]
		var route_b: Dictionary=ports_by_id[route[1]]
		var water_path: Array=Navigation.find_path(nav,{"x":route_a.x,"y":route_a.y},{"x":route_b.x,"y":route_b.y},36.0)
		check(water_path.size()>=2,"chart route remains water: "+str(route[0])+" -> "+str(route[1]))
	var inland:=Vector2.ZERO
	var inland_found:=false
	for island in data.ISLANDS:
		var sample:=Vector2.ZERO
		for point in island.points:sample+=Vector2(point[0],point[1])
		sample/=maxf(1,island.points.size())
		if not Navigation.is_water(nav,sample.x,sample.y,10.0):
			inland=sample;inland_found=true;break
	check(inland_found,"a real inland sample exists on the expanded coast")
	var stranded: Dictionary=CoastMigration.place_on_water(nav,{"x":inland.x,"y":inland.y})
	check(bool(stranded.get("moved",false)) and Navigation.is_water(nav,stranded.point.x,stranded.point.y,10.0),"inland chart position corrects onto safe water")
	var stayed: Dictionary=CoastMigration.place_on_water(nav,{"x":home.x,"y":home.y})
	check(not bool(stayed.get("moved",false)) and is_equal_approx(float(stayed.point.x),float(home.x)) and is_equal_approx(float(stayed.point.y),float(home.y)),"a harbor already in the water is not moved")
	var career=Campaign.new(data.duplicate(true))
	career.new_game(41041)
	check(not career.state.is_empty(),"current campaign birth succeeds on the expanded coast")
	if not career.state.is_empty() and inland_found:
		var saved: Dictionary=career.state.duplicate(true)
		saved.position={"x":inland.x,"y":inland.y};saved.path=[];saved.destination=""
		var before_save: PackedByteArray=var_to_bytes(saved)
		var prepared: Dictionary=CoastMigration.prepare(saved,data,nav)
		check(bool(prepared.get("ok",false)),"full current-revision save prepares on new coast: "+str(prepared.get("message","")))
		if bool(prepared.get("ok",false)):
			check(Navigation.is_water(nav,prepared.state.position.x,prepared.state.position.y),"loaded stranded captain is placed on real water")
			check(Money.total(prepared.state)==Money.total(saved) and prepared.state.coinSupply==saved.coinSupply,"complete save migration conserves every purse")
			check(prepared.state.fleet==saved.fleet and prepared.state.ports==saved.ports,"complete save migration preserves crew, boats, harbor stocks and workers")
		check(var_to_bytes(saved)==before_save,"save preparation never rewrites its source state")
	check(int(data.MAP_REVISION)==2,"coast growth keeps the existing map revision")
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
