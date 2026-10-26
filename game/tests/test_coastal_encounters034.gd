extends SceneTree
## Focused v0.034 fixture; Root runs this through Test Bridge after integration.
const B=preload("res://scripts/battle.gd")
const O=preload("res://scripts/battle_objectives.gd")
const D=preload("res://scripts/damage.gd")
const Refit=preload("res://scripts/refit.gd")
const Coast=preload("res://scripts/coastal_terrain.gd")
const Routes=preload("res://scripts/tactical_routes.gd")
const Tactical=preload("res://scripts/tactical_runtime.gd")
const Navigation=preload("res://scripts/navigation.gd")
var checks: int=0
var failures: int=0

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL coastal encounters: ",message)

func budget() -> Dictionary:
	return {"fullRoutes":0,"cacheHits":0,"clearanceTests":0,"clearanceLimit":4096,"exhaustions":0}

func boat(data: Dictionary,type: String,uid: String) -> Dictionary:
	var hull: Dictionary=data.HULLS.filter(func(h):return h.id==type)[0]
	return D.create_ship(Refit.effective_spec(hull,Refit.defaults(hull)),{"uid":uid})

func regions() -> Array:
	return [{"position":{"x":1985.0,"y":2550.0},"id":"isl_kelp","kind":"escort"},{"position":{"x":4210.0,"y":2280.0},"id":"isl_cinder","kind":"escort"},{"position":{"x":7000.0,"y":6500.0},"id":"","kind":"intercept"}]

func mission(carrier: Dictionary,kind: String) -> Dictionary:
	return {"kind":kind,"carrierTeam":"player" if kind=="escort" else "enemy","carrierUids":[carrier.uid],"allyUids":[carrier.uid] if kind=="escort" else [],"carrierCargo":{carrier.uid:{"timber":2.0}},"exit":{"x":2180.0 if kind=="escort" else 120.0,"y":850.0,"radius":70.0,"portId":"kelp_reach","portName":"Kelp Reach"}}

func coastal_geometry(data: Dictionary) -> void:
	var shapes: Array=[]
	for region in regions():
		var players: Array=[boat(data,"maiden_dreadnought","load-p"),boat(data,"tin_skiff","own")]
		var enemies: Array=[boat(data,"maiden_dreadnought","load-e"),boat(data,"tin_skiff","enemy")]
		var carrier: Dictionary=players[0] if region.kind=="escort" else enemies[0]
		var options: Dictionary=Coast.arena(data,region.position)
		options.merge({"fleet":players,"enemyFleet":enemies,"mission":mission(carrier,region.kind),"seed":34})
		var st: Dictionary=B.create(options)
		check(st.get("startError","").is_empty() and st.result==null,"coastal formation starts: "+str(region.id)+" "+str(st.get("startError","")))
		if not st.get("startError","").is_empty():continue
		shapes.append(JSON.stringify(st.islands))
		check(st.islands.is_empty() if region.id=="" else st.islands.any(func(i):return i.get("id","")==region.id),"actual named coast, or explicit empty open water, reaches Battle")
		if region.id!="":
			var local: Dictionary=st.islands.filter(func(i):return i.get("id","")==region.id)[0]
			var original: Dictionary=data.ISLANDS.filter(func(i):return i.id==region.id)[0]
			var origin: Dictionary=st.location.origin
			check(local.name==original.name and is_equal_approx(float(local.points[0][0])+float(origin.x),float(original.points[0][0])) and is_equal_approx(float(local.points[0][1])+float(origin.y),float(original.points[0][1])),"translation preserves the original named polygon exactly")
		var safe: bool=true
		var separate: bool=true
		for i in range(st.ships.size()):
			var s: Dictionary=st.ships[i]
			if B._blocked(st,Routes.point(s),B._radius(s)):safe=false
			var home: Dictionary=st.tactical.home[str(s.id)]
			if B._blocked(st,Routes.point(home),Routes.planning_radius(s)):safe=false
			for j in range(i):
				if Routes.point(s).distance_to(Routes.point(st.ships[j]))<B._radius(s)+B._radius(st.ships[j])+4.0:separate=false
		check(safe and separate,"every deployed hull and its fallback rally is in clear water without overlap")
		check(st.ships.any(func(s):return is_same(s,carrier)) and st.deployment.player<=300 and st.deployment.enemy<=300 and st.autopilot,"actual boat references, autopilot and 300-point limits are preserved")
		var exit: Dictionary=st.convoy.exit
		var at: Vector2=Vector2(exit.x,exit.y)
		check(st.convoy.exitValid and not B._blocked(st,at,float(exit.radius)+36.0) and exit.portId=="kelp_reach","exit circle is water-safe for the largest deployed hull and retains the onward port")
		check(Routes.route(st,Routes.terrain(st),Routes.point(carrier),at,Routes.planning_radius(carrier),budget()).status=="valid" and Routes.point(carrier).distance_to(at)>B.WIDTH*0.35,"carrier has a checked far exit route at its actual fitted planning clearance")
		if region.id=="isl_kelp":check(B._blocked(st,Vector2(520,850),36.0),"real Kelp coast obstructs the old spawn rather than being replaced")
		if region.id=="isl_cinder":check(B._blocked(st,Vector2(2180,850),106.0) and at.distance_to(Vector2(2180,850))>1.0,"real Cinder coast relocates the obstructed fixed convoy exit")
		st.time=46.0;O.update(st)
		check(st.result==null and int(B.objective_snapshot(st).escaped)==0,"neither elapsed time nor regional setup grants a free convoy escape")
		carrier.x=at.x;carrier.y=at.y;O.update(st)
		check(int(B.objective_snapshot(st).escaped)==1 and st.result==("won" if region.kind=="escort" else "lost"),"only the actual carrier reaching the physical exit settles passage")
	check(shapes.size()==3 and shapes[0]!=shapes[1] and shapes[2]=="[]","two real coasts differ and open water stays empty")

func planning_clearance(data: Dictionary) -> void:
	var nimble: Dictionary=boat(data,"tin_skiff","nimble")
	var large: Dictionary=boat(data,"maiden_dreadnought","large")
	var nimble_r: float=Routes.planning_radius(nimble)
	var large_r: float=Routes.planning_radius(large)
	check(nimble_r>float(nimble.spec.size)+4.0 and large_r>nimble_r and B._radius(large)==float(large.spec.size),"fitted speed/turn add planning room while collision radius remains physical")
	var gap: Dictionary={"islands":[{"points":[[800,-100],[1500,-100],[1500,805],[800,805]]},{"points":[[800,895],[1500,895],[1500,1800],[800,1800]]}]}
	Tactical.ensure(gap)
	var geometry: Dictionary=Routes.terrain(gap)
	var a: Vector2=Vector2(500,850)
	var b: Vector2=Vector2(1800,850)
	nimble.x=a.x;nimble.y=a.y;large.x=a.x;large.y=a.y
	var candidate: Dictionary={"approach":[b],"pass":[],"exit":[]}
	check(Routes.sweep(geometry,a,b,B._radius(large),budget())=="valid","test passage admits even the large hull's physical beam")
	check(Routes.refine(gap,geometry,nimble,candidate,budget()).status=="valid" and Routes.refine(gap,geometry,large,candidate,budget()).status=="blocked","existing corner routing admits the nimble hull and rejects insufficient turning room")
	var around: Dictionary=Coast.arena(data,regions()[0].position)
	Tactical.ensure(around)
	a=Vector2(250,850);b=Vector2(1000,850)
	geometry=Routes.terrain(around)
	var small_path: Dictionary=Routes.route(around,geometry,a,b,nimble_r,budget())
	var big_path: Dictionary=Routes.route(around,geometry,a,b,large_r,budget())
	var cached: Dictionary=budget()
	Routes.route(around,geometry,a,b,nimble_r,cached)
	check(small_path.status=="valid" and big_path.status=="valid" and around.tactical.routeCache.size()==2 and int(cached.cacheHits)==1,"existing route cache separates the two fitted planning radii")

func disconnected_coast(data: Dictionary) -> void:
	var players: Array=[boat(data,"maiden_dreadnought","load"),boat(data,"tin_skiff","own")]
	var enemies: Array=[boat(data,"tin_skiff","enemy")]
	var hp: float=float(players[0].hp)
	var wall: Array=[{"name":"Disconnected coast fixture","points":[[1780,-100],[1900,-100],[1900,1800],[1780,1800]]}]
	var st: Dictionary=B.create({"fleet":players,"enemyFleet":enemies,"islands":wall,"coastalEncounter":true,"mission":mission(players[0],"escort")})
	check(not st.get("startError","").is_empty() and st.ships.is_empty() and not st.get("objectiveSuccess",false),"water on each side of a coast is insufficient without a reachable far convoy exit")
	check(float(players[0].hp)==hp and float(players[0].x)==0.0 and float(players[0].y)==0.0,"refused passage never deploys or heals its actual boat")
	wall=[{"name":"Separated formations fixture","points":[[1080,-100],[1220,-100],[1220,1800],[1080,1800]]}]
	st=B.create({"fleet":players,"enemyFleet":enemies,"islands":wall,"coastalEncounter":true})
	check("connects" in str(st.get("startError","")) and st.ships.is_empty(),"opposing formations in disconnected water basins are refused before deployment")

func main_encounters(scene) -> void:
	var c=scene.core
	var owner: Dictionary={}
	for candidate in c.state.fleetOwners:
		if candidate.get("active",false) and candidate.get("kind","")=="trader" and float(candidate.get("tradeCargo",0))>0 and candidate.boats.all(func(b):return not b.sunk and b.crew>=b.crewMin):owner=candidate;break
	check(not owner.is_empty(),"Main fixture uses a real loaded campaign convoy")
	if owner.is_empty():return
	var patrol: Dictionary=c.NavalAI._find_patrol(c.state,str(owner.id))
	var goods: Dictionary=owner.cargo.duplicate(true)
	var delivered: float=float(owner.get("tradeDelivered",0))
	for region in regions():
		patrol.x=region.position.x;patrol.y=region.position.y
		c.state.position={"x":float(patrol.x)-48.0,"y":float(patrol.y)-12.0}
		scene.begin_battle([],{"kind":"patrol","id":owner.id,"ownerId":owner.id,"name":"Observed convoy contact"})
		check(scene.mode=="battle" and scene.battle.get("startError","").is_empty(),"actual Main encounter enters local coastal water")
		if scene.mode!="battle":continue
		var st: Dictionary=scene.battle
		check(st.location.campaignPosition==region.position and st.location.campaignPosition!=c.state.position,"Main centers terrain at the actual contact rather than the captain's offset position")
		check(st.islands.is_empty() if region.id=="" else st.islands.any(func(i):return i.get("id","")==region.id),"Main passes the original coast and explicit empty-terrain presence")
		check(st.mission.kind=="intercept" and scene.battle_context.mission.exit==st.convoy.exit and st.convoy.actors.values().all(func(b):return owner.boats.any(func(actual):return is_same(b,actual))),"Main preserves real convoy actors and publishes the adjusted physical exit")
		O.update(st)
		check(st.result==null and owner.cargo==goods and float(owner.get("tradeDelivered",0))==delivered,"coastal entry neither awards cargo nor delivers the convoy")
		scene.return_to_campaign()

func chart_water_routes(scene) -> void:
	var c=scene.core
	var paths: Array=scene.chart.trade_paths()
	var safe: bool=not paths.is_empty()
	var point_counts: Array=[]
	for path in paths:
		point_counts.append(path.size())
		if path.size()<2:safe=false
		for i in range(1,path.size()):
			if not Navigation._clear(c.nav,{"x":path[i-1].x,"y":path[i-1].y},{"x":path[i].x,"y":path[i].y},10.0):safe=false
	check(safe,"every drawn segment on the default coastal trade routes clears land")
	var misses: int=c.route_misses
	var hits: int=c.route_hits
	check(is_same(paths,scene.chart.trade_paths()) and c.route_misses==misses and c.route_hits==hits,"repeated chart drawing reuses static paths without even querying the campaign cache")
	# Default links need not bend. This existing port pair crosses Cinder Crown;
	# exercise its detour through the same Chart with a detached route list.
	var pair: Array=["brass_haven","anvil_dock"]
	var original_data: Dictionary=scene.data
	var fixture_data: Dictionary=original_data.duplicate(true)
	fixture_data.ROUTES=[pair]
	scene.data=fixture_data # New identity invalidates Chart's static path cache.
	var detours: Array=scene.chart.trade_paths()
	var bent: Array=detours[0] if detours.size()==1 else []
	var has_detour: bool=not Navigation._clear(c.nav,c.port(pair[0]),c.port(pair[1]),10.0) and bent.size()>2
	check(has_detour,"trade chart uses a real water polyline bending around the existing coast")
	var detour_safe: bool=not bent.is_empty()
	for i in range(1,bent.size()):
		if not Navigation._clear(c.nav,{"x":bent[i-1].x,"y":bent[i-1].y},{"x":bent[i].x,"y":bent[i].y},10.0):detour_safe=false
	check(detour_safe,"every drawn segment on the detour coastal trade route clears land")
	if not safe or not has_detour or not detour_safe:print("chart route diagnostics: default=",paths.size()," pointCounts=",point_counts," detours=",detours.size()," pair=",pair," detourPoints=",bent.size())
	scene.data=original_data

func _initialize() -> void:
	var scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false);scene.set_physics_process(false)
	scene.save_directory=OS.get_user_data_dir().path_join("coastal-034-%d"%Time.get_ticks_usec())
	scene.new_game()
	coastal_geometry(scene.data)
	planning_clearance(scene.data)
	disconnected_coast(scene.data)
	main_encounters(scene)
	chart_water_routes(scene)
	scene.queue_free()
	await process_frame
	print("coastal encounters: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
