extends SceneTree
## One campaign initialization, short coastal paths, no long simulation.
const Campaign=preload("res://scripts/campaign.gd")
const Navigation=preload("res://scripts/navigation.gd")
const Routes=preload("res://scripts/route_cache.gd")
const Lifecycle=preload("res://scripts/naval_lifecycle.gd")
const AI=preload("res://scripts/naval_ai.gd")
const Money=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0
var c
var baseline: Dictionary
var world_nav: Dictionary

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL coastal navigation034: ",message)

func box(x: float,y: float,w: float,h: float) -> Dictionary:
	return {"points":[[x,y],[x+w,y],[x+w,y+h],[x,y+h]]}

func people() -> float:
	var total: float=0.0
	for p in c.state.ports:total+=float(p.workforce)
	for boat in c.state.fleet:total+=float(boat.crew)
	for owner in c.state.fleetOwners:
		for boat in owner.boats:total+=float(boat.crew)
	return total

func reset(nav: Dictionary) -> void:
	c.state=baseline.duplicate(true);c.nav=nav;c.route_cache.clear()
	c.route_hits=0;c.route_misses=0;c.sailing_clearance=0.0;c.events.clear()
	c.state.navalEncounterElapsed=0.0
	for p in c.state.patrols:p.active=false

func borrow_large_boat() -> Dictionary:
	# Move one existing crewed hull, keeping its people, stores and UID finite.
	var owner: Dictionary=c.fleet_owner("patrol-2")
	var boat: Dictionary=owner.boats.pop_back()
	boat.mothballed=false;c.state.fleet.append(boat)
	return boat

func _initialize() -> void:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c=Campaign.new(world)
	var started: Dictionary=c.new_game(3401)
	check(bool(started.ok),"actual campaign initializes")
	if not started.ok:
		print("%d checks, %d failures"%[checks,failures]);quit(1);return
	world_nav=c.nav;baseline=c.state.duplicate(true)
	_test_initial_traffic()
	_test_passage_and_cache()
	_test_harbors()
	_test_old_route_restore()
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func _test_initial_traffic() -> void:
	var usable: int=0
	var refused: int=0
	for p in c.state.patrols:
		var actual: float=Routes.clearance(c,p)
		if p.get("course",[]).size()>=2:
			usable+=1
			check(Navigation.path_clear(c.nav,{"x":p.x,"y":p.y},c.remaining_patrol_course(p),actual),"initial %s remaining course clears its owner's actual hulls"%p.id)
			check(is_equal_approx(float(p.courseClearance),actual),"initial %s records owner clearance"%p.id)
		else:
			refused+=1
			check(not str(p.get("routeFailure","")).is_empty(),"initial %s refusal explains the unsafe course"%p.id)
			check(c.distance(p,c.port(str(p.from)))<0.001,"initial %s refusal keeps its original port coordinate"%p.id)
	print("Initial coastal traffic: %d usable, %d refused"%[usable,refused])
	check(usable+refused==9 and usable>0,"enabling hull clearance preserves usable independent NPC traffic")
	check(Money.total(c.state)==int(c.state.coinSupply),"initial route setup conserves actual coins")

func _test_passage_and_cache() -> void:
	var nav: Dictionary=Navigation.create([box(240,0,120,180),box(240,220,120,180)],600,400,40)
	reset(nav)
	var start: Dictionary={"x":80.0,"y":200.0}
	var end: Dictionary={"x":520.0,"y":200.0}
	var small: float=Routes.clearance(c)
	var large: float=float(c.hull("maiden_dreadnought").size)
	var nodes_before: int=nav.nodes.size()
	var small_path: Array=c.cached_path(start,end,small)
	check(small_path.size()>=2 and Navigation.path_clear(nav,start,small_path,small),"real skiff clearance sails the narrow passage with safe legs")
	check(c.cached_path(start,end,large).is_empty(),"real dreadnought clearance refuses the same passage")
	check(c.route_cache.size()==2,"identical endpoints at different clearances occupy different cache keys")
	check(not c.cached_path(start,end).is_empty(),"generic cached_path retains its default ten-unit contract")
	check(Routes.path(c,start,end)==small_path and Routes.path(c,start,end,large).is_empty(),"adapter forwards derived and explicit clearance into the cache")
	if not small_path.is_empty():small_path[0].x=0.0
	var detached: Array=c.cached_path(start,end,small)
	check(not detached.is_empty() and detached[0].x==80.0,"returned path edits cannot poison a clearance-specific cache entry")
	var npc: Dictionary=c.state.patrols[2]
	check(Routes.clearance(c,npc)>small and Routes.path(c,{"id":npc.id,"x":80.0,"y":200.0},end).is_empty(),"NPC route derives its real owner rather than the smaller player fleet")
	check(nav.nodes.size()==nodes_before,"hull queries reuse the original coarse grid")
	var total_people: float=people()
	var total_coins: int=Money.total(c.state)
	var boat: Dictionary=borrow_large_boat()
	check(Routes.clearance(c)==float(boat.spec.size),"active larger player hull increases sailing clearance")
	boat.mothballed=true
	check(Routes.clearance(c)==small,"mothballed reserve does not enlarge sailing clearance")
	boat.mothballed=false;boat.storedPort=str(c.data.START.port)
	check(Routes.clearance(c)==small,"stored reserve does not enlarge sailing clearance")
	boat.storedPort="";boat.mothballed=true;boat.towed=true
	check(Routes.clearance(c)==float(boat.spec.size),"an explicitly towed physical hull still needs its own clearance")
	boat.towed=false;boat.mothballed=false
	c.state.position=start.duplicate();c.state.path=[end.duplicate()];c.state.destination=""
	c.sailing_clearance=small
	check(not c.validate_sailing_route() and c.state.path.is_empty() and c.state.position==start,"enlarged active fleet stops an old skiff route without teleporting")
	# Exercise the same active-course guard on a real NPC owner.
	reset(nav)
	npc=c.state.patrols[2]
	npc.active=true;npc.holding=false;npc.x=start.x;npc.y=start.y;npc.progress=0.0
	npc.course=[start.duplicate(),end.duplicate()];npc.courseLength=440.0;npc.courseClearance=small
	var owner: Dictionary=c.fleet_owner(str(npc.id))
	owner.purpose="patrol";owner.destination=npc.to;owner.atPort=""
	Lifecycle.step(c,0.01)
	check(npc.holding and not str(npc.get("routeFailure","")).is_empty() and c.distance(npc,start)<0.001,"active NPC refuses an obsolete small-boat route in place")
	check(people()==total_people and Money.total(c.state)==total_coins,"navigation and refusals preserve real people and every purse")
	var detour: Dictionary=Navigation.create([box(250,130,100,140)],600,400,40)
	var around: Array=Navigation.find_path(detour,{"x":60.0,"y":200.0},{"x":540.0,"y":200.0},large)
	check(around.size()>2 and Navigation.path_clear(detour,around[0],around,large),"large-hull grid edges and shortened detour legs all retain clearance")

func _test_harbors() -> void:
	var nav: Dictionary=Navigation.create([box(250,100,100,200)],600,400,40)
	reset(nav)
	var total_people: float=people()
	var total_coins: int=Money.total(c.state)
	borrow_large_boat()
	var actual: float=Routes.clearance(c)
	var dock: Dictionary=c.port(str(c.data.START.port))
	dock.x=368.0;dock.y=200.0
	c.state.position={"x":450.0,"y":200.0}
	check(not Navigation.is_water(nav,dock.x,dock.y,actual),"harbor dot is too close to shore for the real larger hull")
	var approach: Dictionary=Navigation.harbor_approach(nav,dock,actual)
	check(not approach.is_empty() and c.distance(approach,dock)<65.0 and Navigation.is_water(nav,approach.x,approach.y,actual),"safe player approach remains within existing paid-service range")
	var result: Dictionary=c.chart_course(dock,str(dock.id))
	check(bool(result.ok) and Navigation.path_clear(nav,c.state.position,c.state.path,actual),"actual player course validates every leg to the safe approach")
	if result.ok:
		var length: float=0.0
		var previous: Dictionary=c.state.position
		for point in c.state.path:
			length+=c.distance(previous,point);previous=point
		c.step(length/maxf(0.001,c.travel_speed())+0.001)
		check(str(c.current_port().get("id",""))==str(dock.id) and c.distance(c.state.position,approach)<0.001,"player arrival retains safe endpoint and the original service port")
		check(c.distance(c.state.position,dock)>0.5 and Navigation.is_water(nav,c.state.position.x,c.state.position.y,actual),"arrival never appends a final unsafe leg or snaps to the port dot")
		check(c.events.any(func(event):return event.get("kind","")=="arrival" and event.get("port","")==dock.id),"safe approach publishes the existing arrival event with unchanged port ID")
	check(people()==total_people and Money.total(c.state)==total_coins,"player approach conserves real crews and coins")
	# Same geometry, actual independent owner and the tighter NPC docking range.
	reset(nav)
	var p: Dictionary=c.state.patrols[2]
	var owner: Dictionary=c.fleet_owner(str(p.id))
	dock=c.port(str(owner.homePort));dock.x=368.0;dock.y=200.0
	p.active=true;p.holding=false;p.x=410.0;p.y=200.0;owner.atPort=""
	owner.purpose="resupply";owner.destination=dock.id
	actual=Routes.clearance(c,p)
	Lifecycle.route(c,p,str(dock.id))
	check(not p.course.is_empty() and Navigation.path_clear(nav,{"x":p.x,"y":p.y},p.course,actual),"actual NPC course reaches a safe approach using owner hull clearance")
	if not p.course.is_empty():
		var endpoint: Dictionary=p.course[-1].duplicate()
		check(c.distance(endpoint,dock)<40.0,"NPC approach stays inside its existing docking range")
		var speed: float=float(AI.fleet_performance(owner).speed)*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0))
		Lifecycle.step(c,float(p.courseLength)/maxf(0.001,speed)+0.01)
		check(c.distance(p,endpoint)<0.001 and c.distance(p,dock)>0.5 and Navigation.is_water(nav,p.x,p.y,actual),"NPC arrival and subsequent order retain the physical safe endpoint")
		check(str(owner.atPort)==str(dock.id),"NPC paid docking service still uses its actual original port")
	check(people()==total_people and Money.total(c.state)==total_coins,"NPC docking preserves finite people and total coins")
	# An enclosed port cannot be reached from either service radius.
	reset(nav);borrow_large_boat()
	dock=c.port(str(c.data.START.port));dock.x=300.0;dock.y=200.0
	c.state.position={"x":450.0,"y":200.0}
	var before: Dictionary=c.state.position.duplicate()
	result=c.chart_course(dock,str(dock.id))
	check(not result.ok and "hull this size" in str(result.message) and c.state.position==before,"unusable player harbor explicitly refuses without changing position")
	p=c.state.patrols[5];owner=c.fleet_owner(str(p.id))
	p.x=450.0;p.y=200.0;owner.atPort=""
	Lifecycle.route(c,p,str(dock.id))
	check(p.holding and "hull this size" in str(p.routeFailure) and c.distance(p,before)<0.001,"unusable NPC harbor explicitly refuses without changing position")
	check(people()==total_people and Money.total(c.state)==total_coins,"harbor-size refusals conserve crews and coins")

func _test_old_route_restore() -> void:
	reset(world_nav)
	var old_path: Array=[]
	# Pick a real named-island edge with a former ten-unit route twelve units
	# off shore. The actual starter's fourteen-unit hull cannot sail that leg.
	for island in world_nav.islands:
		var points: Array=island.points
		for i in range(points.size()):
			var a: Vector2=Vector2(points[i][0],points[i][1])
			var b: Vector2=Vector2(points[(i+1)%points.size()][0],points[(i+1)%points.size()][1])
			var tangent: Vector2=(b-a).normalized()
			for sign_value in [-1.0,1.0]:
				var center: Vector2=(a+b)*0.5+Vector2(-tangent.y,tangent.x)*12.0*sign_value
				var start: Dictionary={"x":center.x-tangent.x*10.0,"y":center.y-tangent.y*10.0}
				var end: Dictionary={"x":center.x+tangent.x*10.0,"y":center.y+tangent.y*10.0}
				if Navigation.path_clear(world_nav,start,[end],10.0) and not Navigation.path_clear(world_nav,start,[end],Routes.clearance(c)):
					old_path=[start,end];break
			if not old_path.is_empty():break
		if not old_path.is_empty():break
	check(old_path.size()==2,"default world exposes a concrete old-clearance coastal leg")
	if old_path.is_empty():return
	c.state.position=old_path[0];c.state.path=[old_path[1]];c.state.destination=""
	var before: Dictionary=c.state.position.duplicate()
	var total_people: float=people()
	var total_coins: int=Money.total(c.state)
	var restored: Dictionary=c.restore(JSON.parse_string(JSON.stringify(c.state)))
	check(bool(restored.ok),"actual JSON campaign restore accepts the existing revision and finite ledger")
	if not restored.ok:print("RESTORE: ",restored)
	check(c.state.path.is_empty() and c.distance(c.state.position,before)<0.001,"restored old-clearance course stops at the saved coordinate")
	check(c.state.log.any(func(line):return "hull this size" in str(line)),"restored route refusal explains the hull-size restriction")
	check(int(c.state.mapRevision)==int(c.data.MAP_REVISION) and c.nav==world_nav,"clearance validation neither migrates the coast nor rebuilds the grid")
	check(people()==total_people and Money.total(c.state)==total_coins,"restore and route refusal preserve actual people and all coins")
