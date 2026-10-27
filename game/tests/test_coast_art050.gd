extends SceneTree
## Source-only handoff: Root runs this one bounded fixture through TestBridge.
## Actual authored world / translated encounter rings, no simulation or mock map.
const CoastArt=preload("res://scripts/coast_art050.gd")
const NauticalArt=preload("res://scripts/nautical_art.gd")
const Terrain=preload("res://scripts/coastal_terrain.gd")
const Navigation=preload("res://scripts/navigation.gd")
const Chart=preload("res://scripts/chart.gd")
const FeedbackTest=preload("res://tests/test_feedback.gd")
var checks: int=0
var failures: int=0
var peak_vertices: Array=[0,0,0]

class Recorder extends FeedbackTest.Recorder:
	func draw_multiline(points: PackedVector2Array,color: Color,width: float=-1.0,antialiased: bool=false) -> void:
		for i in range(0,points.size(),2):draw_line(points[i],points[i+1],color,width,antialiased)

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("COAST050: "+message)

func _initialize() -> void:call_deferred("run")

func fingerprint(plan: Dictionary) -> PackedByteArray:
	var values: Array=[plan.land,plan.bounds,plan.origin,plan.outline,plan.reef,plan.pier,plan.get("roofs",[])]
	for batch in plan.levels:values.append([batch.vertices,batch.colors,batch.mesh.get_instance_id()])
	return var_to_bytes(values)

func on_land(p: Vector2,ring: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(p,ring):return true
	# Float32 clipping / mesh storage can round a shared coastline by <0.05 units.
	for i in range(ring.size()):
		if Geometry2D.get_closest_point_to_segment(p,ring[i],ring[(i+1)%ring.size()]).distance_squared_to(p)<0.0025:return true
	return false

func validate(plan: Dictionary,label: String) -> void:
	var prior: int=0
	for i in range(3):
		var batch: Dictionary=plan.levels[i]
		var count: int=batch.vertices.size()
		peak_vertices[i]=maxi(int(peak_vertices[i]),count)
		check(count>=prior and count>0 and count%3==0 and count<=int(CoastArt.VERTEX_LIMITS[i]),label+" bounded prepared LOD "+str(i))
		check(batch.colors.size()==count and batch.mesh.get_surface_count()==1,label+" one colored triangle batch "+str(i))
		prior=count
	var vertices: PackedVector3Array=plan.levels[2].vertices
	var contained: bool=true;var finite: bool=true
	for i in range(0,vertices.size(),3):
		var tri:=PackedVector2Array()
		for j in range(3):
			var v: Vector3=vertices[i+j]
			finite=finite and is_finite(v.x) and is_finite(v.y) and v.z==0.0
			var p: Vector2=Vector2(v.x,v.y)+Vector2(plan.origin)
			tri.append(p);contained=contained and on_land(p,plan.land)
		# Vertices alone miss a triangle bridging the mouth of a concave bay.
		for p in [(tri[0]+tri[1]+tri[2])/3.0,(tri[0]+tri[1])*0.5,(tri[1]+tri[2])*0.5,(tri[2]+tri[0])*0.5]:
			contained=contained and on_land(p,plan.land)
	check(finite and contained,label+" every opaque triangle stays on actual collider land, including bay spans")
	check(plan.reef.size()<=CoastArt.MAX_REEF_SEGMENTS*2 and plan.reef.size()%2==0,label+" bounded line-only approach ink")
	var before: PackedByteArray=fingerprint(plan)
	for scale_value in [0.1,0.5,1.2]:
		var rec:=Recorder.new()
		var projector: Callable=func(p: Vector2,_h: float=0.0)->Vector2:return (p-Vector2(plan.origin))*scale_value+Vector2(800,500)
		var calls: int=CoastArt.draw(rec,projector,plan,scale_value,Rect2(0,0,1600,1000))
		check(calls>=1 and calls<=3 and rec.mesh_draws==1 and rec.invalid==0,label+" at most three paint calls / one cached mesh at "+str(scale_value))
		check(rec.transform==Transform2D.IDENTITY,label+" restores caller draw transform")
		var old_draws: int=rec.mesh_draws
		check(CoastArt.draw(rec,projector,plan,scale_value,Rect2(100000,100000,20,20))==0 and rec.mesh_draws==old_draws,label+" offscreen submits nothing")
	check(fingerprint(plan)==before,label+" drawing never rebuilds or changes prepared geometry / meshes")

func labels_at_sizes(chart,data: Dictionary) -> void:
	for viewport: Vector2i in [Vector2i(1600,1000),Vector2i(1280,800)]:
		root.size=viewport
		await process_frame
		chart.territory_view();chart.scale_factor=chart.regional_scale()*chart.zoom
		var entries: Array=[]
		for port in data.PORTS:
			entries.append({"at":chart.project(Vector2(port.x,port.y)),"text":str(port.name),"priority":110 if port.id=="brass_haven" else 60,"subtitle":CoastArt.harbor_caption(port)})
		for sheet in chart._chart_sheet:entries.append({"at":chart.project(sheet.label),"text":sheet.name,"priority":25})
		entries.append({"at":chart.project(Vector2(data.PORTS[0].x,data.PORTS[0].y)),"text":"YOUR FLOTILLA","priority":105})
		var bounds: Rect2=Chart.chart_label_bounds(Vector2(viewport))
		var placed: Array=Chart.chart_label_layout(entries,bounds,chart.sans)
		check(placed.any(func(p):return p.text=="Brass Haven") and placed.any(func(p):return p.text=="YOUR FLOTILLA"),"selected real home and flotilla labels survive captions at "+str(viewport))
		var clear: bool=true
		for i in range(placed.size()):
			clear=clear and bounds.encloses(placed[i].rect)
			for j in range(i):clear=clear and not Rect2(placed[i].rect).grow(3).intersects(placed[j].rect)
		check(clear,"existing overview label layout keeps caption / region plates apart at "+str(viewport))

func run() -> void:
	root.size=Vector2i(1600,1000)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var original: PackedByteArray=var_to_bytes(data)
	var chart=Chart.new();root.add_child(chart)
	chart.host={"mode":"campaign","data":data,"core":{"state":{"position":{"x":data.PORTS[0].x,"y":data.PORTS[0].y}}}}
	chart.sans=SystemFont.new();chart.sans.font_names=PackedStringArray(["Bahnschrift","Segoe UI"])
	chart._ensure_chart_sheet()
	check(data.WORLD.width==10400 and data.WORLD.height==7200 and chart._chart_sheet.size()==8 and chart._chart_towns.size()==10,"actual eight-island / ten-port world, no duplicate map")
	check(CoastArt.lod(0.1)==0 and CoastArt.lod(0.22)==1 and CoastArt.lod(0.8)==2,"explicit overview / regional / close LOD thresholds")
	var biomes: Dictionary={}
	for i in range(data.ISLANDS.size()):
		var sheet: Dictionary=chart._chart_sheet[i]
		check(sheet.land==chart.polygon(data.ISLANDS[i].points),"exact source coastline "+str(sheet.id))
		biomes[sheet.biome]=true;validate(sheet,str(sheet.id))
	check(biomes.size()==8,"eight authored terrain identities")
	var canonical: Dictionary={"brass_haven":"trade","kelp_reach":"fishery","sawtooth_mill":"timber","silt_hollow":"agriculture","cinder_quay":"foundry","anvil_dock":"shipyard","reed_floats":"trade","naphtha_bay":"refinery","rust_anchorage":"fishery","shatter_spire":"shipyard"}
	var landmarks: Dictionary={};var layouts: Dictionary={}
	# Nav's public water query accepts the real source rings directly; no new
	# pathfinding graph, route framework or campaign birth is needed for art.
	var nav: Dictionary={"width":data.WORLD.width,"height":data.WORLD.height,"islands":data.ISLANDS}
	for port in data.PORTS:
		var plan: Dictionary=chart._chart_towns[str(port.id)]
		check(plan.industry==canonical[port.id] and plan.industry==str(port.industry) and plan.specialty==str(port.specialty),"actual canonical industry / specialty "+str(port.id))
		check(plan.berth==Vector2(port.x,port.y) and Navigation.is_water(nav,port.x,port.y,36.0),"original navigable berth and click center "+str(port.id))
		check(plan.roofs.size()>0 and plan.roofs.size()<=CoastArt.MAX_ROOFS and plan.caption==CoastArt.harbor_caption(port),"prepared working town and meaningful caption "+str(port.id))
		landmarks[plan.landmark]=true;layouts[var_to_bytes(plan.levels[1].vertices)]=true
		validate(plan,str(port.id))
	check(landmarks.size()==10 and layouts.size()==10,"ten distinct harbor layouts and working landmarks")
	var first_mesh: ArrayMesh=chart._chart_sheet[0].levels[2].mesh
	var first_town: ArrayMesh=chart._chart_towns.brass_haven.levels[2].mesh
	chart._ensure_chart_sheet()
	check(is_same(first_mesh,chart._chart_sheet[0].levels[2].mesh) and is_same(first_town,chart._chart_towns.brass_haven.levels[2].mesh),"campaign cache preparation is idempotent")
	await labels_at_sizes(chart,data)
	# Two actual coastal encounters and an actual empty window, with no Battle
	# updates, spawn overrides or generated replacement islands.
	for position in [{"x":1985.0,"y":2550.0},{"x":4210.0,"y":2280.0},{"x":7000.0,"y":6500.0}]:
		var encounter: Dictionary=Terrain.arena(data,position)
		var before: PackedByteArray=var_to_bytes(encounter)
		chart.host.mode="battle";chart.host.battle=encounter
		chart._prepare_battle_coast()
		check(chart._battle_coast.size()==encounter.islands.size(),"cache uses the actual translated encounter, including open water")
		var mesh_ids: Array=[]
		for i in range(encounter.islands.size()):
			var island: Dictionary=encounter.islands[i];var sheet: Dictionary=chart._battle_coast[i]
			check(sheet.land==chart.polygon(island.points),"battle art has exact local collision ring "+str(island.id))
			validate(sheet,"encounter "+str(island.id))
			mesh_ids.append(sheet.levels[2].mesh.get_instance_id())
			chart.camera=sheet.origin;chart.scale_factor=1.1
			var rec:=Recorder.new()
			check(NauticalArt.draw(rec,chart.project,sheet.land,sheet,true,1.1,Rect2(0,0,1280,800))>0 and rec.invalid==0,"same prepared terrain draws through actual isometric Chart.project")
		chart._prepare_battle_coast()
		var repeated: Array=[]
		for sheet in chart._battle_coast:repeated.append(sheet.levels[2].mesh.get_instance_id())
		check(mesh_ids==repeated and var_to_bytes(encounter)==before,"battle cache identity is reused and actual encounter stays unchanged")
	check(var_to_bytes(data)==original,"all art / draw / label preparation leaves world, ports, routes, economy and roster bytes unchanged")
	chart.free()
	print("COAST050: %d checks, %d failures; peak vertices by LOD %s; no simulation or visual-quality verdict"%[checks,failures,str(peak_vertices)])
	quit(0 if failures==0 else 1)
