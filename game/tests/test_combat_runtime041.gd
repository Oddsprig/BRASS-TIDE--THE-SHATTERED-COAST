extends SceneTree
## One bounded source candidate fixture. Root alone runs the native 15s job.
const Damage=preload("res://scripts/damage.gd")
const Core=preload("res://scripts/equipment_condition.gd")
const Records=preload("res://scripts/equipment_records.gd")
const Lab=preload("res://scripts/fleet_lab.gd")
const Battle=preload("res://scripts/battle.gd")
const Certification=preload("res://scripts/tactical_certification.gd")
const Planner=preload("res://scripts/tactical_planner.gd")
const Tactical=preload("res://scripts/tactical_runtime.gd")
const Routes=preload("res://scripts/tactical_routes.gd")
const Benchmark=preload("res://scripts/runtime_benchmark.gd")
const DT: float=1.0/60.0
var checks: int=0
var failures: Array=[]
var started: int=0
var report: Dictionary={}

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);print("FAIL combat_runtime041: "+message)

func uid_at(ship: Dictionary,location: String) -> String:
	for item in ship.moduleCondition.items.values():
		if str(item.location)==location:return str(item.itemUid)
	return ""

func cache_checks(source: Dictionary) -> void:
	var ship: Dictionary=source.duplicate(true)
	ship.vx=12.0;ship.cooldown=0.15
	var cache: Dictionary={}
	Damage.tick_ship(ship,DT,{"inCombat":true},cache)
	var info: Dictionary=Damage.inspect_owner_cached(ship,cache)
	var reference: Dictionary=ship.duplicate(true)
	var same: bool=true
	for tick in range(8):
		Damage.begin_frame_cache(cache,[ship])
		var actual: Dictionary=Damage.tick_ship(ship,DT,{"inCombat":true},cache)
		var expected: Dictionary=Damage.tick_ship(reference,DT,{"inCombat":true})
		same=same and var_to_bytes(ship)==var_to_bytes(reference) and var_to_bytes(actual)==var_to_bytes(expected)
	check(same,"eight cached healthy frames match full public ship state and tick reports")
	check(is_same(Damage.inspect_owner_cached(ship,cache),info),"healthy frames retain the same exact-owner inspection")
	check(Damage.get_status_cached(ship,cache)==Damage.get_status(ship),"instantaneous cached status equals the public projection")
	var public_status: Dictionary=Damage.get_status_cached(ship,cache)
	public_status.speedFactor=0.0;public_status.weaponFactors["mount0"]=0.0
	check(Damage.read_status_cached(ship,cache).speedFactor>0.0 and Damage.read_status_cached(ship,cache).weaponFactors.mount0>0.0,"public status edits cannot poison the immutable runtime projection")
	var clone: Dictionary=ship.duplicate(true)
	clone.wounded=1.0
	var live_before: PackedByteArray=var_to_bytes(ship)
	check(not is_same(Damage.inspect_owner_cached(clone,cache),info) and Damage.get_status_cached(clone,cache)==Damage.get_status(clone),"same-ID wounded copy receives its own inspection and current status")
	clone.moduleCondition={}
	check(not Damage.get_status_cached(clone,cache).equipmentOk,"same-ID corrupt copy fails closed")
	check(var_to_bytes(ship)==live_before and is_same(Damage.inspect_owner_cached(ship,cache),info),"copy and corrupt reads leave the exact live owner and cache untouched")
	ship.fuel=0.0
	check(Damage.get_status_cached(ship,cache)==Damage.get_status(ship) and Damage.read_status_cached(ship,cache).pump==0.0,"fuel crossing zero immediately refreshes pump status")
	ship.fuel=120.0;ship.wounded=1.0
	check(Damage.get_status_cached(ship,cache)==Damage.get_status(ship),"crew scalar edits immediately refresh status")
	ship.wounded=0.0;ship.water=12.0;ship.breaches.append({"area":2.0,"section":"bow"})
	check(Damage.get_status_cached(ship,cache)==Damage.get_status(ship) and Damage.read_status_cached(ship,cache).inflow>0.0,"in-place breach and water edits immediately refresh flood status")
	ship.water=0.0;ship.breaches=[]
	Damage.set_repair_priority(ship,"weapons")
	check(Damage.get_status_cached(ship,cache).repairPriority=="weapons" and Damage._cached_entry(ship,cache).is_empty(),"priority change invalidates the canonical proof")
	Damage.tick_ship(ship,DT,{"inCombat":true},cache)
	var gun_uid: String=uid_at(ship,"mount0")
	check(not gun_uid.is_empty() and Core.apply_component_damage(ship.moduleCondition,{"itemUid":gun_uid,"loss":0.6,"cause":"Runtime fixture"}).ok,"actual installed gun receives component damage")
	check(Damage.get_status_cached(ship,cache)==Damage.get_status(ship) and Damage.read_status_cached(ship,cache).weaponFactors.mount0<1.0,"actual module damage invalidates condition and weapon factors immediately")
	var supplies: float=ship.supplies
	var repaired: Dictionary=Damage.tick_ship(ship,0.2,{"inCombat":true},cache)
	check(repaired.repairedModuleHp>0.0 and repaired.usedSupplies>0.0 and ship.supplies<supplies,"damaged fallback performs real repair with finite crew work and supply debit")
	check(Damage.get_status_cached(ship,cache)==Damage.get_status(ship),"repaired module factors are current after publication")
	ship.engine=0.5
	check(Damage.get_status_cached(ship,cache)==Damage.get_status(ship),"legacy engine scalar change rejects the equipment proof")
	Damage.tick_ship(ship,DT,{"inCombat":true},cache)
	var rng: RandomNumberGenerator=RandomNumberGenerator.new();rng.seed=4101
	Damage.apply_hit(ship,{"damage":8.0,"kind":"bullet","section":"bow"},rng,cache)
	check(Damage._cached_entry(ship,cache).is_empty() and Damage.get_status_cached(ship,cache)==Damage.get_status(ship),"actual hit removes the owned entry and returns current damaged status")
	var fresh: Dictionary=source.duplicate(true)
	cache={};Damage.tick_ship(fresh,DT,{"inCombat":true},cache)
	var old_info: Dictionary=Damage.inspect_owner_cached(fresh,cache)
	fresh.spec.pumps=float(fresh.spec.pumps)+1.0
	check(not is_same(Damage.inspect_owner_cached(fresh,cache),old_info),"in-place specification edits invalidate equipment inspection")
	cache={};fresh=source.duplicate(true);Damage.tick_ship(fresh,DT,{"inCombat":true},cache)
	old_info=Damage.inspect_owner_cached(fresh,cache)
	fresh.loadout.weapons[0]=""
	check(not Damage.get_status_cached(fresh,cache).equipmentOk and not is_same(Damage.inspect_owner_cached(fresh,cache),old_info),"in-place refit mismatch is refused rather than using old gun authority")
	cache={};fresh=source.duplicate(true);Damage.tick_ship(fresh,DT,{"inCombat":true},cache)
	for tick in range(Damage.OWNER_CACHE_FRAMES):Damage.begin_frame_cache(cache,[fresh])
	check(cache.is_empty(),"unchanged proof still expires after twelve live physics frames")

func route_budget() -> Dictionary:
	return {"fullRoutes":0,"cacheHits":0,"rollouts":0,"samples":0,"clearanceTests":0,"clearanceLimit":4096,"exhaustions":0,"rolled":{}}

func route_state(ship: Dictionary,islands: Array,allies: Array=[]) -> Dictionary:
	var st: Dictionary={"time":0.0,"islands":islands}
	var t: Dictionary=Tactical.ensure(st)
	t.ships[str(ship.id)]=ship;t.dt=DT;t.snapshotRevision=1
	t.cells=Routes.grid([ship]+allies);t.geometry=Routes.terrain(st)
	return st

func candidate_input_checks(source: Dictionary) -> void:
	var ship: Dictionary=source.duplicate(true)
	ship.x=600.0;ship.y=850.0;ship.team="player"
	var ships: Array=[ship]
	for index in range(21):
		var enemy: Dictionary=ship.duplicate(true)
		enemy.id="begin-enemy-"+str(index);enemy.team="enemy"
		enemy.x=1000.0+float(index)*60.0
		ships.append(enemy)
	for marker in ["ally","sunk","secured"]:
		var other: Dictionary=ship.duplicate(true)
		other.id="begin-"+marker;other.team="player" if marker=="ally" else "enemy"
		other.sunk=marker=="sunk";other.captureSecured=marker=="secured"
		ships.append(other)
	var view: Dictionary={"snapshotRevision":7,"terrainRevision":3,"time":2.0,"dt":DT,"side":"player","dueIds":[str(ship.id)],"ships":ships}
	var before: PackedByteArray=var_to_bytes([view,ship])
	var membership: Array=Certification.detailed_targets(view,ship)
	var inputs: Dictionary=Certification._begin_inputs(view,ship,membership)
	check(membership.size()==16,"same-begin preparation retains the independent sixteen-target shortlist")
	check(inputs.is_read_only() and inputs.ids.is_read_only() and inputs.hostiles.is_read_only() and inputs.detailed.is_read_only() and inputs.certificate.is_read_only() and inputs.certificate.checkedPose.is_read_only() and inputs.certificate.fireWindow.mountIds.is_read_only(),"same-begin observation indexes and certificate template are immutable")
	var candidate: Dictionary={"candidateId":"begin-candidate","shipId":str(ship.id),"targetId":str(membership[0]),"leaderId":"","role":"skirmisher","sector":0,"approach":[Vector2(750,850)],"pass":[Vector2(850,850)],"exit":[Vector2(950,850)],"fireMountIds":["mount0"],"orderRevision":int(ship.orderRevision),"snapshotRevision":7}
	var cases: Array=[
		{"name":"valid raw offer","patch":{},"valid":true},
		{"name":"foreign hull","patch":{"shipId":"foreign"},"valid":false},
		{"name":"old observation","patch":{"snapshotRevision":6},"valid":false},
		{"name":"old order","patch":{"orderRevision":int(ship.orderRevision)-1},"valid":false},
		{"name":"ally target","patch":{"targetId":"begin-ally"},"valid":false},
		{"name":"sunk target","patch":{"targetId":"begin-sunk"},"valid":false},
		{"name":"secured target","patch":{"targetId":"begin-secured"},"valid":false},
		{"name":"outside shortlist","patch":{"targetId":"begin-enemy-20"},"valid":false},
		{"name":"unknown mount","patch":{"fireMountIds":["foreign"]},"valid":false},
		{"name":"duplicate mount","patch":{"fireMountIds":["mount0","mount0"]},"valid":false},
		{"name":"non-string mount","patch":{"fireMountIds":[1]},"valid":false},
		{"name":"non-array leg","patch":{"exit":{}},"valid":false},
		{"name":"nonfinite path","patch":{"pass":[Vector2(INF,0)]},"valid":false},
		{"name":"empty alternate map","patch":{"fireMountTargets":{}},"valid":false},
		{"name":"non-map alternate targets","patch":{"fireMountTargets":[]},"valid":false},
		{"name":"unfitted alternate mount","patch":{"fireMountTargets":{"foreign":str(membership[0])}},"valid":false},
		{"name":"allied alternate target","patch":{"fireMountTargets":{"mount0":"begin-ally"}},"valid":false},
		{"name":"far alternate target","patch":{"fireMountTargets":{"mount0":"begin-enemy-20"}},"valid":false},
		{"name":"valid alternate target","patch":{"fireMountTargets":{"mount0":str(membership[1])}},"valid":true},
		{"name":"unarmed departure","patch":{"fireMountIds":[],"targetId":""},"valid":true}]
	for row in cases:
		var offer: Dictionary=candidate.merged(row.patch,true)
		var direct: bool=Certification.candidate_valid(offer,view,ship,membership)
		var shared: bool=Certification._candidate_valid(offer,view,ship,membership,inputs)
		check(direct==bool(row.valid) and shared==direct,"shared validation preserves exact refusal/acceptance: "+str(row.name))
	var long_leg: Dictionary=candidate.duplicate(true)
	for index in range(9):long_leg.approach.append(Vector2(index,0))
	check(not Certification.candidate_valid(long_leg,view,ship,membership) and not Certification._candidate_valid(long_leg,view,ship,membership,inputs),"shared inputs do not weaken path-point limits")
	var refined: Dictionary=candidate.duplicate(true)
	refined.approach=[Vector2(650,850),Vector2(700,800),Vector2(750,850)]
	check(Certification.candidate_valid(refined,view,ship,membership) and Certification._candidate_valid(refined,view,ship,membership,inputs),"refined geometry receives the same complete per-candidate validation")
	for offer in [candidate,refined]:
		var fingerprint: String=Planner.fingerprint(offer)
		var direct: Dictionary=Certification.base_certificate(view,ship,offer,fingerprint)
		var shared: Dictionary=Certification._begin_certificate(view,ship,offer,fingerprint,inputs)
		check(not fingerprint.is_empty() and var_to_bytes(shared)==var_to_bytes(direct),"shared hull constants preserve every certificate field and refined fingerprint")
		shared.checkedPose.x=-1.0;shared.fireWindow.mountIds.append("foreign")
		check(var_to_bytes(Certification._begin_certificate(view,ship,offer,fingerprint,inputs))==var_to_bytes(direct),"returned certificate poses and fire windows cannot mutate the shared template")
	var fallback: Dictionary=Certification._begin_inputs(view,ship,[])
	check(Certification._candidate_valid(candidate,view,ship,[],fallback)==Certification.candidate_valid(candidate,view,ship),"empty supplied membership retains the original independently computed fallback")
	check(before==var_to_bytes([view,ship]),"preparation and repeated raw/refined validation do not mutate snapshot, mounts or boat")
	# Only a new local packet is used after observations change; none is saved in
	# a boat/battle, and public calls always rebuild from the current arguments.
	view.time=3.0;view.snapshotRevision=8;view.terrainRevision=4
	ship.orderRevision+=1;ship.x+=5.0;ship.spec.speed+=1.0
	ship.mounts=[]
	ships[1].sunk=true
	var next: Dictionary=Certification._begin_inputs(view,ship,Certification.detailed_targets(view,ship))
	var next_candidate: Dictionary=candidate.duplicate(true)
	next_candidate.snapshotRevision=8;next_candidate.orderRevision=ship.orderRevision
	check(not next.ids.has("mount0") and not next.hostiles.has("begin-enemy-0") and not Certification._candidate_valid(next_candidate,view,ship,[],next) and not Certification.candidate_valid(next_candidate,view,ship),"new observations immediately remove lost weapons and sunk contacts")
	check(next.certificate.snapshotRevision==8 and next.certificate.orderRevision==ship.orderRevision and next.certificate.terrainRevision==4 and next.certificate.checkedAt==3.0 and next.certificate.checkedPose.x==ship.x and next.certificate.dynamicsKey!=inputs.certificate.dynamicsKey,"next begin rebuilds pose, order, terrain, time and dynamics certificate inputs")
	var empty_view: Dictionary=view.duplicate(true)
	empty_view.ships=[ship]
	var empty_inputs: Dictionary=Certification._begin_inputs(empty_view,ship,[])
	var departure: Dictionary=next_candidate.merged({"targetId":"","fireMountIds":[]},true)
	check(empty_inputs.detailed.is_empty() and Certification._candidate_valid(departure,empty_view,ship,[],empty_inputs)==Certification.candidate_valid(departure,empty_view,ship),"zero hostile contacts retains the empty-shortlist departure behavior")

func traffic_query_checks(source: Dictionary) -> void:
	var fleet: Array=[]
	for index in range(42):
		var ship: Dictionary=source.duplicate(true)
		ship.id="traffic-"+str(index);ship.team="player" if index<21 else "enemy"
		ship.x=80.0+float(index%7)*340.0;ship.y=70.0+float(index/7)*260.0
		ship.vx=float(index%5-2)*65.0;ship.vy=float(index%3-1)*80.0
		ship.spec.size=10.0+float(index%4)*6.0
		fleet.append(ship)
	fleet[1].x=90.0;fleet[1].y=70.0;fleet[1].vx=0.0;fleet[1].vy=0.0
	fleet[2].sunk=true;fleet[3].captureSecured=true
	var plain: Dictionary=Routes.grid(fleet)
	var shared: Dictionary=Routes.grid(fleet,true)
	var queries: Array=[
		[Vector2(80,70),Vector2(110,70),14.0,0.0,DT],
		[Vector2(600,850),Vector2(1400,850),20.0,0.0,5.0],
		[Vector2(1400,850),Vector2(600,850),32.0,5.0,12.0],
		[Vector2(-500,-200),Vector2(2800,2000),10.0,0.0,0.2],
		[Vector2(159.999,319.999),Vector2(160,320),0.0,0.0,2.0],
		[Vector2(4000,4000),Vector2(4100,4100),1.0,0.0,1.0]]
	var equal_members: bool=true
	var equal_traffic: bool=true
	var outcomes: Dictionary={}
	# The second pass hits populated windows with different budgets. No narrow
	# phase status or budget result may be shared along with the neighbour list.
	for repeat in range(2):
		for query: Array in queries:
			equal_members=equal_members and var_to_bytes(Routes.neighbours(plain,query[0],query[1],query[2]))==var_to_bytes(Routes.neighbours(shared,query[0],query[1],query[2]))
			for limit in [0,1,4,4096]:
				var old_budget: Dictionary={"clearanceTests":2,"clearanceLimit":limit+2,"exhaustions":0}
				var new_budget: Dictionary=old_budget.duplicate()
				var expected: String=Routes.occupied(plain,fleet[0],query[0],query[1],query[2],query[3],query[4],old_budget)
				var actual: String=Routes.occupied(shared,fleet[0],query[0],query[1],query[2],query[3],query[4],new_budget)
				equal_traffic=equal_traffic and actual==expected and new_budget==old_budget
				outcomes[actual]=true
	check(equal_members,"shared traffic windows preserve exact ordered neighbour payloads, cell edges, reverse/long sweeps and outside-grid queries")
	check(equal_traffic and outcomes.has("valid") and outcomes.has("blocked") and outcomes.has("pending"),"cold/reused traffic checks preserve actual swept-hull outcomes and every budget debit/exhaustion")
	var a: Vector2=Vector2(-500,-200);var b: Vector2=Vector2(2800,2000)
	var expected: Array=Routes.neighbours(plain,a,b,10.0)
	var published: Array=Routes.neighbours(shared,a,b,10.0)
	published.clear()
	check(Routes.neighbours(shared,a,b,10.0)==expected and not expected.is_empty(),"editing a public neighbour Array cannot poison a shared route/fire query")
	var overflow_equal: bool=true
	for index in range(140):
		var p: Vector2=Vector2(float(index%14)*160.0+80.0,float(index/14)*160.0+80.0)
		overflow_equal=overflow_equal and Routes.neighbours(shared,p,p,1.0)==Routes.neighbours(plain,p,p,1.0)
	check(overflow_equal and shared._queryCache.size()==128,"traffic query storage is bounded; uncached windows after saturation retain exact membership")
	# Shared lists retain current owner references, never saved narrow-phase
	# poses. This same-window repeat must respond to an actual hull-position edit.
	var actor: Dictionary=source.duplicate(true);actor.id="traffic-actor";actor.x=500.0;actor.y=850.0;actor.vx=0.0;actor.vy=0.0
	var ally: Dictionary=actor.duplicate(true);ally.id="traffic-ally";ally.x=505.0
	var pair: Dictionary=Routes.grid([actor,ally],true)
	var budget: Dictionary=route_budget()
	check(Routes.occupied(pair,actor,Vector2(500,850),Vector2(510,850),20.0,0.0,DT,budget)=="blocked","shared broadphase still refuses a real close allied hull")
	ally.x=1000.0;budget=route_budget()
	check(Routes.occupied(pair,actor,Vector2(500,850),Vector2(510,850),20.0,0.0,DT,budget)=="valid","same-window reuse recomputes physical separation from the current owner")
	var st: Dictionary={"tactical":{"ships":{str(actor.id):actor,str(ally.id):ally},"cells":pair}}
	Tactical.after_motion(st)
	check(not is_same(st.tactical.cells,pair) and st.tactical.cells._queryCache.is_empty() and Routes.neighbours(st.tactical.cells,Vector2(1000,850),Vector2(1000,850),1.0).has(ally),"post-motion rebuild discards old windows and sees a hull in its new cells")
	report.trafficBroadphase={"actors":fleet.size(),"orderedMembershipEqual":equal_members,"trafficAndBudgetEqual":equal_traffic,"outcomes":outcomes,"overflowEqual":overflow_equal,"retainedWindows":shared._queryCache.size()}
	# Real light-roster and largest-hull radii; no reduced collision margin.
	actor.spec.size=14.0
	var hostile: Dictionary=actor.duplicate(true);hostile.id="traffic-hostile";hostile.team="enemy";hostile.x=720.0;hostile.y=1100.0
	var tight: Dictionary=Routes.grid([actor,hostile],true)
	var legacy: Dictionary=Routes.grid([actor,hostile],true);legacy.erase("_maxNavigationRadius")
	var tight_budget: Dictionary=route_budget();var legacy_budget: Dictionary=route_budget()
	var tight_result: String=Routes.occupied(tight,actor,Vector2(500,850),Vector2(510,850),20.0,0.0,DT,tight_budget,true)
	var legacy_result: String=Routes.occupied(legacy,actor,Vector2(500,850),Vector2(510,850),20.0,0.0,DT,legacy_budget,true)
	check(tight_result=="valid" and legacy_result==tight_result and int(tight_budget.clearanceTests)<int(legacy_budget.clearanceTests),"light hostile query omits an irrelevant far hull while retaining the legacy-cell fallback")
	var clearance: float=Routes.navigation_radius(actor)+Routes.navigation_radius(hostile)+7.0
	hostile.x=510.0+clearance-0.1;hostile.y=850.0
	tight=Routes.grid([actor,hostile],true)
	check(Routes.occupied(tight,actor,Vector2(500,850),Vector2(510,850),20.0,0.0,DT,route_budget(),true)=="blocked","tight hostile query retains the exact inside-clearance edge")
	hostile.x=510.0+clearance+0.1;tight=Routes.grid([actor,hostile],true)
	check(Routes.occupied(tight,actor,Vector2(500,850),Vector2(510,850),20.0,0.0,DT,route_budget(),true)=="valid","tight hostile query retains the exact outside-clearance edge")
	hostile.spec.size=36.0;hostile.x=510.0+Routes.navigation_radius(actor)+Routes.navigation_radius(hostile)+6.9
	tight=Routes.grid([actor,hostile],true)
	check(float(tight._maxNavigationRadius)==99.0 and Routes.occupied(tight,actor,Vector2(500,850),Vector2(510,850),20.0,0.0,DT,route_budget(),true)=="blocked","grid maximum includes the actual largest hull envelope rather than assuming light radii")
	hostile.spec.size=14.0;hostile.x=580.0;hostile.y=1200.0;hostile.vy=-350.0
	tight=Routes.grid([actor,hostile],true)
	check(Routes.occupied(tight,actor,Vector2(500,850),Vector2(510,850),20.0,0.0,1.0,route_budget(),true)=="blocked","tight query finds a hostile crossing from outside the current-pose window through the two-second swept grid")
	hostile.y=1550.0;hostile.vy=-175.0;tight=Routes.grid([actor,hostile],true)
	check(Routes.occupied(tight,actor,Vector2(500,850),Vector2(510,850),20.0,3.0,4.0,route_budget(),true)=="blocked","tight query retains future hostile crossings beyond two seconds with the existing speed padding")
	report.trafficBroadphase.hostileQuery={"lightQueryRadius":Routes.navigation_radius(actor)+38.5+7.0,"legacyQueryRadius":Routes.navigation_radius(actor)+220.0,"tightClearance":tight_budget.clearanceTests,"legacyClearance":legacy_budget.clearanceTests}

func route_checks(source: Dictionary) -> void:
	var ship: Dictionary=source.duplicate(true)
	ship.x=600.0;ship.y=850.0;ship.vx=0.0;ship.vy=0.0
	ship.status=Damage.get_status(ship);ship.mounts=[]
	var candidate: Dictionary={"candidateId":"route-fixture","shipId":str(ship.id),"targetId":"","leaderId":"","role":"skirmisher","sector":-1,"approach":[Vector2(600,850),Vector2(1400,850)],"pass":[Vector2(1400,850)],"exit":[Vector2(1500,850)],"fireMountIds":[],"orderRevision":int(ship.orderRevision),"snapshotRevision":1}
	var island: Dictionary={"points":[[900,750],[1100,750],[1100,950],[900,950]]}
	var comparisons: Array=[]
	for islands: Array in [[],[island]]:
		var trial_reference: Dictionary=route_state(ship,islands)
		var trial_live: Dictionary=route_state(ship,islands)
		var trial_old_budget: Dictionary=route_budget();var trial_new_budget: Dictionary=route_budget()
		var trial_old_route: Dictionary=Routes.refine(trial_reference,trial_reference.tactical.geometry,ship,candidate,trial_old_budget)
		var trial_new_route: Dictionary=Routes.refine_live(trial_live,trial_live.tactical.geometry,ship,candidate,trial_new_budget)
		check(trial_old_route.status=="valid" and trial_new_route.status=="valid","reference and combined walk find complete clear-water or island-detour routes")
		if trial_old_route.status!="valid" or trial_new_route.status!="valid":continue
		check(trial_old_route.candidate==trial_new_route.candidate and (islands.is_empty() or trial_new_route.candidate.approach.size()>candidate.approach.size()),"combined walk preserves every approach/pass/exit point including a real land detour")
		var view: Dictionary={"snapshotRevision":1,"terrainRevision":trial_reference.tactical.terrainRevision,"time":0.0,"dt":DT,"side":str(ship.team),"dueIds":[str(ship.id)],"ships":[ship]}
		var fingerprint: String=Planner.fingerprint(trial_old_route.candidate)
		var old_cert: Dictionary=Certification.certify_live(trial_reference,view,ship,trial_old_route.candidate,fingerprint,trial_old_budget)
		var new_cert: Dictionary=Certification._certify_refined_live(trial_live,view,ship,trial_new_route,fingerprint,trial_new_budget)
		check(old_cert.status=="valid" and old_cert==new_cert,"same-begin corridor result produces the complete unchanged live certificate")
		var prepared_state: Dictionary=route_state(ship,islands)
		var prepared_budget: Dictionary=route_budget()
		var prepared_route: Dictionary=Routes.refine_live(prepared_state,prepared_state.tactical.geometry,ship,candidate,prepared_budget)
		var prepared_inputs: Dictionary=Certification._begin_inputs(view,ship,[])
		var prepared_cert: Dictionary=Certification._certify_refined_live(prepared_state,view,ship,prepared_route,fingerprint,prepared_budget,[],null,prepared_inputs)
		check(var_to_bytes(prepared_cert)==var_to_bytes(new_cert) and var_to_bytes(prepared_state.tactical.predictions)==var_to_bytes(trial_live.tactical.predictions),"prepared certification preserves the full actual certificate and published prediction on clear/detoured routes")
		check(prepared_budget==trial_new_budget,"same-begin observation reuse preserves every geometry/traffic/rollout budget debit")
		var invalid_route: Dictionary=prepared_route.duplicate(true)
		invalid_route.candidate.fireMountIds=["foreign"]
		var refused_budget: Dictionary=route_budget();var prepared_refused_budget: Dictionary=route_budget()
		var refused: Dictionary=Certification._certify_refined_live(prepared_state,view,ship,invalid_route,fingerprint,refused_budget)
		var prepared_refused: Dictionary=Certification._certify_refined_live(prepared_state,view,ship,invalid_route,fingerprint,prepared_refused_budget,[],null,prepared_inputs)
		check(refused.status=="blocked" and var_to_bytes(prepared_refused)==var_to_bytes(refused) and refused_budget==prepared_refused_budget and refused_budget==route_budget(),"refined weapon tampering is refused before any physical/traffic work by both paths")
		check(int(trial_new_budget.clearanceTests)<int(trial_old_budget.clearanceTests),"complete valid route uses fewer bounded clearance operations")
		comparisons.append({"islandDetour":not islands.is_empty(),"referenceClearance":trial_old_budget.clearanceTests,"combinedClearance":trial_new_budget.clearanceTests})
	# The approach crosses an actual ally. Its later pass crosses land and would
	# need a graph search, but no complete maneuver can use that blocked approach.
	var ally: Dictionary=ship.duplicate(true);ally.id="route-blocker";ally.x=675.0
	candidate.approach=[Vector2(600,850),Vector2(750,850)];candidate.pass=[Vector2(750,850),Vector2(1400,850)]
	var reference: Dictionary=route_state(ship,[island],[ally]);var live: Dictionary=route_state(ship,[island],[ally])
	var old_budget: Dictionary=route_budget();var new_budget: Dictionary=route_budget()
	var old_route: Dictionary=Routes.refine(reference,reference.tactical.geometry,ship,candidate,old_budget)
	var new_route: Dictionary=Routes.refine_live(live,live.tactical.geometry,ship,candidate,new_budget)
	check(old_route.status=="valid" and Certification.corridor(reference,ship,old_route.candidate,old_budget).status=="blocked" and new_route.status=="blocked","combined walk rejects the same actual allied approach conflict")
	check(int(old_budget.fullRoutes)>0 and int(new_budget.fullRoutes)==0 and int(new_budget.clearanceTests)<int(old_budget.clearanceTests),"blocked approach stops before the unusable pass/exit graph search")
	var pending_budget: Dictionary=route_budget();pending_budget.clearanceLimit=0
	check(Routes.refine_live(live,live.tactical.geometry,ship,candidate,pending_budget).status=="pending","exhausted route work remains pending and grants no corridor proof")
	report.routeComparisons=comparisons
	report.blockedApproach={"referenceClearance":old_budget.clearanceTests,"combinedClearance":new_budget.clearanceTests,"referenceSearches":old_budget.fullRoutes,"combinedSearches":new_budget.fullRoutes}
	# Default traffic queries retain allied-only semantics. Normal navigation
	# opts into actual moving hostile hull clearance; fire queries do not.
	var hostile: Dictionary=ship.duplicate(true);hostile.id="route-hostile";hostile.team="enemy";hostile.x=1000.0
	var cells: Dictionary=Routes.grid([ship,hostile],true)
	check(Routes.occupied(cells,ship,Vector2(600,850),Vector2(1400,850),18.0,0.0,1.0,route_budget())=="valid" and Routes.occupied(cells,ship,Vector2(600,850),Vector2(1400,850),18.0,0.0,1.0,route_budget(),true)=="blocked","normal navigation refuses crossing a hostile hull while default traffic query is unchanged")
	check(Routes.occupied(cells,ship,Vector2(600,850),Vector2(1400,850),18.0,0.0,1.0,route_budget(),true,str(hostile.id))=="valid","an explicit contact target can retain its boarding or ramming approach")
	check(Routes.occupied(Routes.grid([ship,hostile,ally],true),ship,Vector2(600,850),Vector2(1400,850),18.0,0.0,1.0,route_budget(),true,str(hostile.id))=="blocked","explicit hostile contact never bypasses an allied hull")
	var no_budget: Dictionary=route_budget();no_budget.clearanceLimit=0
	check(Routes.occupied(cells,ship,Vector2(600,850),Vector2(1400,850),18.0,0.0,1.0,no_budget,true)=="pending","hostile clearance exhaustions remain pending rather than fabricated obstruction")
	hostile.x=620.0;cells=Routes.grid([ship,hostile],true)
	check(Routes.occupied(cells,ship,Vector2(600,850),Vector2(550,850),18.0,0.0,DT,route_budget(),true)=="valid" and Routes.occupied(cells,ship,Vector2(600,850),Vector2(630,850),18.0,0.0,DT,route_budget(),true)=="blocked","an inherited close hostile pass can separate but cannot drive through the target")
	var escape: Dictionary=candidate.merged({"approach":[Vector2(600,850),Vector2(550,850)],"pass":[Vector2(550,850)],"exit":[Vector2(500,850)]},true)
	var escape_state: Dictionary=route_state(ship,[],[hostile])
	check(Routes.refine_live(escape_state,escape_state.tactical.geometry,ship,escape,route_budget()).status=="valid","the complete separating exit is not rejected by its zero-time initial point")
	hostile.x=float(ship.x)+Routes.navigation_radius(ship)+Routes.navigation_radius(hostile)+6.9
	var hostile_state: Dictionary=route_state(ship,[],[hostile])
	check(Certification.safe_step(hostile_state,ship,{"angle":0.0,"throttle":1.0},route_budget()).get("blocked",false),"actual next-step autopilot refuses entry into the hostile art envelope")

func authority_checks(st: Dictionary) -> void:
	var ship: Dictionary=st.ships[0]
	ship.x=600.0;ship.y=850.0
	st.ships[1].x=1700.0;st.ships[1].y=850.0
	check(Battle.issue_order(st,[str(ship.id)],"move",{"x":1000.0,"y":850.0}),"explicit clear-water move is accepted")
	for tick in range(2):Battle.update(st,DT)
	var intent: Dictionary=st.tactical.intents.get(str(ship.id),{})
	var record: Dictionary=st.tactical.predictions.get(str(intent.get("pathFingerprint","")),{})
	check(not record.is_empty(),"public movement obtains real live-step route authority")
	if record.is_empty():return
	check(str(record.certificate.scope)==Planner.LIVE_CERT_SCOPE and int(record.certificate.rolloutSamples)==0 and int(st.tactical.metrics.work.samples)==0,"live runtime does no detached future damage/physics replay or claimed forecast samples")
	check(Certification.current(st,ship,intent).ok and absf(float(st.time)-2.0*DT)<0.000001 and absf(float(ship.vx))>0.0,"actual boat moves at the retained sixty physical updates per second")
	check(not Certification.current(st,ship.duplicate(true),intent).ok,"same-ID ship copy cannot borrow live maneuver authority")
	var hp: float=ship.hp;ship.hp-=1.0
	check(not Certification.current(st,ship,intent).ok,"actual hull loss invalidates live authority immediately")
	ship.hp=hp
	var speed: float=ship.spec.speed;ship.spec.speed+=1.0
	check(not Certification.current(st,ship,intent).ok,"dynamics change invalidates live authority immediately")
	ship.spec.speed=speed
	var condition: Dictionary=ship.moduleCondition.duplicate(true)
	for location in ["engine","pumps","mount0"]:
		var uid: String=uid_at(ship,location)
		check(not uid.is_empty() and Core.apply_component_damage(ship.moduleCondition,{"itemUid":uid,"loss":1.0,"cause":"Runtime disable fixture"}).ok and Records.publish(ship).ok,"actual installed component can be disabled: "+str(location))
		check(not Certification.current(st,ship,intent).ok,"disabled installed component immediately revokes live authority: "+str(location))
		ship.moduleCondition=condition.duplicate(true);Records.publish(ship)
	var fuel: float=ship.fuel;ship.fuel=0.0
	check(not Certification.current(st,ship,intent).ok,"fuel exhaustion immediately revokes live maneuver authority")
	ship.fuel=fuel
	ship.moduleCondition={}
	check(not Certification.current(st,ship,intent).ok,"corrupt current equipment cannot retain a live maneuver")
	ship.moduleCondition=condition.duplicate(true);Records.publish(ship)
	var now: float=st.time;st.time=float(record.certificate.validUntil)+DT
	check(not Certification.current(st,ship,intent).ok,"expired bounded authority cannot steer or fire")
	st.time=now
	var budget: Dictionary={"clearanceTests":0,"clearanceLimit":4096,"exhaustions":0}
	var edge: Dictionary=ship.duplicate(true);edge.x=2295.0
	check(Certification.safe_step(st,edge,{"angle":0.0,"throttle":1.0},budget).get("blocked",false),"live next-step sweep refuses an actual boundary crossing")
	var ally: Dictionary=ship.duplicate(true);ally.id="fixture-close-ally";ally.x=ship.x+1.0
	st.tactical.cells=Routes.grid([ship,ally])
	budget={"clearanceTests":0,"clearanceLimit":4096,"exhaustions":0}
	check(Certification.safe_step(st,ship,{"angle":0.0,"throttle":1.0},budget).get("blocked",false),"live next-step sweep still refuses allied hull overlap")
	st.tactical.cells=Routes.grid(st.ships)
	check(Battle.issue_order(st,[str(ship.id)],"hold",{"x":ship.x,"y":ship.y}) and not Certification.current(st,ship,intent).ok,"new order revokes the previous maneuver immediately")
	Battle.set_autopilot(st,false)
	Battle.update(st,DT,{"forward":true,"right":true})
	check(str(st.tactical.manualId)==str(ship.id) and absf(float(st.time)-3.0*DT)<0.000001,"manual flagship retains direct per-tick helm authority")

func recovery_checks(world: Dictionary) -> void:
	var created: Dictionary=Lab.create(world,{"player":[Lab.entry(world,"tin_skiff")],"enemy":[Lab.entry(world,"tin_skiff")]},4601)
	check(bool(created.get("ok",false)),"recovery fixture uses canonical public Lab birth")
	if not bool(created.get("ok",false)):return
	var st: Dictionary=created.battle
	var ship: Dictionary=st.ships[0];var id: String=str(ship.id)
	ship.x=600.0;ship.y=850.0;ship.water=float(ship.capacity)*0.2;ship.hp=float(ship.maxHp)*0.8;ship.fire=4.0;ship.policy="repair"
	st.ships[1].x=1700.0;st.ships[1].y=850.0
	var engine_uid: String=uid_at(ship,"engine")
	check(not engine_uid.is_empty() and Core.apply_component_damage(ship.moduleCondition,{"itemUid":engine_uid,"loss":0.4,"cause":"Runtime recovery fixture"}).ok and Records.publish(ship).ok,"recovery fixture starts with a real damaged engine below its at-sea repair cap")
	check(Damage.set_repair_priority(ship,"engine")=="engine" and Battle.issue_order(st,[id],"move",{"x":1000.0,"y":850.0}),"repair priority and explicit move use existing public APIs")
	Battle.update(st,DT)
	var intent: Dictionary=st.tactical.intents.get(id,{})
	var fingerprint: String=str(intent.get("pathFingerprint",""))
	var record: Dictionary=st.tactical.predictions.get(fingerprint,{})
	check(not record.is_empty() and Certification.current(st,ship,intent).ok,"damaged bailing boat obtains a real useful live-step maneuver")
	if record.is_empty():return
	var certificate: PackedByteArray=var_to_bytes(record.certificate)
	var water: float=ship.water;var engine: float=ship.engine;var hp: float=ship.hp;var supplies: float=ship.supplies;var ammo: float=ship.ammo;var crew: float=ship.crew
	var condition_before: PackedByteArray=var_to_bytes(ship.moduleCondition)
	var continuous: bool=true
	for tick in range(6):
		Battle.update(st,DT)
		continuous=continuous and str(st.tactical.intents.get(id,{}).get("pathFingerprint",""))==fingerprint and Certification.current(st,ship,intent).ok
	check(continuous and float(ship.fire)>0.0 and float(ship.hp)<hp,"six actual 60Hz bailing/repair ticks with real fire heat preserve useful intent instead of reassessing every frame")
	check(float(ship.water)<water and float(ship.engine)>engine and var_to_bytes(ship.moduleCondition)!=condition_before and float(ship.supplies)<supplies,"real bailing and component recovery change the ledger and consume finite carried supplies")
	check(float(ship.ammo)==ammo and float(ship.crew)==crew and float(ship.supplies)>=0.0 and var_to_bytes(record.certificate)==certificate,"recovery neither invents ammo/crew/stores nor extends certificate time or geometry")
	var recovered: float=float(ship.engine)-engine
	if recovered>0.0004:
		check(Core.apply_component_damage(ship.moduleCondition,{"itemUid":engine_uid,"loss":recovered*0.5,"cause":"Runtime hit after recovery"}).ok and Records.publish(ship).ok,"actual component loss follows the recorded recovery")
		check(float(ship.engine)>engine and not Certification.current(st,ship,intent).ok,"damage after recovery is refused even above the original certified engine condition")
		Battle.update(st,DT)
		check(int(st.tactical.intents.get(id,{}).get("snapshotRevision",-1))==int(st.tactical.snapshotRevision),"abrupt component damage requests a fresh maneuver on the next live begin")
	else:check(false,"real recovery is large enough to exercise the hit-after-repair guard")
	report.recovery046={"continuousIntent":continuous,"waterRemoved":water-float(ship.water),"suppliesUsed":supplies-float(ship.supplies),"recoveredEngine":recovered,"ticks":8}

func cadence_checks(world: Dictionary) -> void:
	var created: Dictionary=Lab.create(world,{"player":[Lab.entry(world,"tin_skiff")],"enemy":[Lab.entry(world,"tin_skiff")]},4602)
	check(bool(created.get("ok",false)),"cadence fixture uses canonical public Lab birth")
	if not bool(created.get("ok",false)):return
	var st: Dictionary=created.battle
	var ship: Dictionary=st.ships[0];var id: String=str(ship.id)
	ship.x=600.0;ship.y=850.0;st.ships[1].x=1700.0;st.ships[1].y=850.0
	# A real closed water pocket makes the outside destination unreachable.
	# This is a scheduler-only probe: begin advances observations, not physics.
	st.islands=[
		{"points":[[480,730],[520,730],[520,970],[480,970]]},
		{"points":[[680,730],[720,730],[720,970],[680,970]]},
		{"points":[[480,730],[720,730],[720,770],[480,770]]},
		{"points":[[480,930],[720,930],[720,970],[480,970]]}]
	check(Battle.issue_order(st,[id],"move",{"x":1000.0,"y":850.0}),"blocked-route probe accepts a real clear-water destination outside the pocket")
	Tactical.accept_command(st,st.ships[1],"hold",{"x":1700.0,"y":850.0})
	Tactical.reset_runtime_profile043();Tactical.set_runtime_profile043(true)
	var attempts: Array=[];var last: float=-INF
	for tick in range(13):
		st.time+=DT;Tactical.begin(st,DT)
		var at: float=float(st.tactical.lastDecision.get(id,-1.0))
		if at!=last:attempts.append(at);last=at
	var profile: Dictionary=Tactical.runtime_profile043()
	Tactical.set_runtime_profile043(false)
	check(not st.tactical.intents.has(id) and attempts.size()==3,"unchanged blocked route gets three bounded retries across thirteen observation ticks")
	check(int(profile.beginCalls)==13 and int(profile.viewCalls)<=6,"blocked retry cadence avoids repeated detached world/planning copies while observation stays at 60Hz")
	check(Battle.issue_order(st,[id],"hold",{"x":ship.x,"y":ship.y}),"new explicit hold replaces the unreachable move")
	st.time+=DT;Tactical.begin(st,DT)
	check(float(st.tactical.lastDecision.get(id,-1.0))==float(st.time) and Certification.current(st,ship,st.tactical.intents.get(id,{})).ok,"explicit order bypasses the blocked-route retry wait on the next begin")
	var hold_intent: Dictionary=st.tactical.intents.get(id,{})
	var hold_diagnostic: Dictionary={"time":float(st.time),"lastDecision":float(st.tactical.lastDecision.get(id,-1.0)),"currentReason":str(Certification.current(st,ship,hold_intent).reason),"runtimeReason":str(st.tactical.reasons.get(id,""))}
	st.time+=DT;Tactical.begin(st,DT,{"manual":true})
	check(str(st.tactical.manualId)==id and not st.tactical.intents.has(id),"temporary manual control takes helm authority immediately")
	st.time+=DT;Tactical.begin(st,DT)
	check(str(st.tactical.manualId).is_empty() and float(st.tactical.lastDecision.get(id,-1.0))==float(st.time) and Certification.current(st,ship,st.tactical.intents.get(id,{})).ok,"manual release immediately requests autopilot rather than waiting for retry cadence")
	var released_intent: Dictionary=st.tactical.intents.get(id,{})
	var released_diagnostic: Dictionary={"time":float(st.time),"lastDecision":float(st.tactical.lastDecision.get(id,-1.0)),"currentReason":str(Certification.current(st,ship,released_intent).reason),"runtimeReason":str(st.tactical.reasons.get(id,""))}
	# A nearby target behind the actual pocket wall must not veto legal holding.
	st.ships[1].x=850.0
	check(Battle.issue_order(st,[id],"hold",{"x":ship.x,"y":ship.y}),"occluded-shot probe repeats the same public hold order")
	st.time+=DT;Tactical.begin(st,DT)
	var sight_budget: Dictionary={"clearanceTests":0,"clearanceLimit":4096,"exhaustions":0}
	var mount: Dictionary=st.tactical.mountCache[id].mounts[0]
	check(Routes.point(ship).distance_to(Routes.point(st.ships[1]))<float(mount.range) and Routes.sweep(st.tactical.geometry,Routes.point(ship),Routes.point(st.ships[1]),0.0,sight_budget)=="blocked","hold probe has an in-range enemy actually occluded by land")
	var occluded_intent: Dictionary=st.tactical.intents.get(id,{})
	check(float(st.tactical.lastDecision.get(id,-1.0))==float(st.time) and Certification.current(st,ship,occluded_intent).ok,"an occluded firing lane still permits the existing nonfiring hold fallback")
	check(int(st.tactical.budget.rollouts)==0 and int(st.tactical.budget.samples)==0 and int(st.tactical.metrics.planningCalls.certify)<=2 and int(st.tactical.budget.clearanceTests)<=2900,"hold fallback stays within live-only work and the shared clearance cap")
	var shot_permits: int=0
	for intent: Dictionary in [hold_intent,released_intent,occluded_intent]:
		for gate: Dictionary in intent.get("fireGate",{}).values():
			if bool(gate.get("permit",false)):shot_permits+=1
	check(shot_permits==0,"out-of-range and occluded hold fallbacks grant no false firing authority")
	report.cadence046={"observationTicks":13,"attemptTimes":attempts,"profile":profile,"physicsAdvanced":false,"commandHold":hold_diagnostic,"manualRelease":released_diagnostic,"holdShotPermits":shot_permits}

func heavy_pressure_checks(world: Dictionary) -> void:
	var config: Dictionary=Lab.preset(world,"all_weapons")
	var original: Dictionary=config.duplicate(true)
	var created: Dictionary=Lab.create(world,config,83)
	check(bool(created.get("ok",false)),"seed-83 all-weapons regression uses the unchanged public Lab preset")
	if not bool(created.get("ok",false)):return
	var st: Dictionary=created.battle
	var ship: Dictionary=Battle.get_flagship(st)
	var id: String=str(ship.id)
	var opening: Dictionary={"ammo":float(ship.ammo),"fuel":float(ship.fuel),"supplies":float(ship.supplies),"boats":st.ships.size()}
	var costs: Dictionary={}
	for mount: Dictionary in ship.spec.weaponMounts:costs[str(mount.id)]=float(mount.ammoCost)
	check(st.autopilot and st.result==null and st.events.is_empty() and st.projectiles.is_empty() and opening.boats==5 and costs.size()==4 and opening.ammo==float(ship.spec.ammoCapacity),"real surrounded flagship and four opponents start loaded without manufactured shots")
	var first_shot_tick: int=-1
	var shots: int=0
	var spent: float=0.0
	var checked_holds: int=0
	var local_holds: bool=true
	var real_events: bool=true
	var within_caps: bool=true
	var timeline: Array=[]
	# Eighteen ordinary 60Hz ticks, with no pose/stat edits, private planner call,
	# injected hit/fire, refills or forced result. Winning is not this assertion.
	for tick: int in range(18):
		Battle.update(st,DT,{})
		var intent: Dictionary=st.tactical.intents.get(id,{})
		var record: Dictionary=st.tactical.predictions.get(str(intent.get("pathFingerprint","")),{})
		if str(intent.get("role",""))=="heavy" and str(intent.get("phase",""))=="pressure" and not record.is_empty():
			checked_holds+=1
			var candidate: Dictionary=record.candidate
			local_holds=local_holds and str(record.certificate.status)=="valid" and candidate.exit.size()==1 and not candidate.approach.is_empty() and not candidate.pass.is_empty() and candidate.exit[0]==candidate.approach[-1] and candidate.pass[-1]==candidate.exit[0]
		for event: Dictionary in Battle.pop_events(st):
			if str(event.kind)!="fire" or str(event.sourceId)!=id:continue
			var mount_id: String=str(event.mountId)
			real_events=real_events and costs.has(mount_id) and float(event.time)>0.0 and float(event.time)<=float(st.time) and Battle.mount_shot_time(ship,mount_id)>0.0
			spent+=float(costs.get(mount_id,0.0));shots+=1
			if first_shot_tick<0:first_shot_tick=tick+1
		within_caps=within_caps and int(st.tactical.budget.clearanceTests)<=4096 and int(st.tactical.budget.rollouts)==0 and int(st.tactical.budget.samples)==0
		if tick in [0,8,17]:timeline.append({"tick":tick+1,"time":st.time,"ammo":ship.ammo,"phase":intent.get("phase",""),"reason":st.tactical.reasons.get(id,""),"fireReasons":st.tactical.fireReasons.get(id,{}).duplicate(true)})
	check(shots>0 and first_shot_tick>0 and first_shot_tick<=18 and float(ship.ammo)<float(opening.ammo),"surrounded heavy fires through normal AI within 0.3s instead of indefinitely checking a future rally")
	check(real_events and is_equal_approx(float(opening.ammo)-float(ship.ammo),spent) and float(ship.ammo)>=0.0,"real installed-mount fire events and acknowledgements explain every flagship ammo debit")
	check(checked_holds>0 and local_holds,"accepted pressure certificate ends at the checked gun station and promises no remote rally")
	check(within_caps and st.autopilot and str(st.tactical.manualId).is_empty() and is_equal_approx(float(st.time),18.0*DT) and st.result==null and st.ships.size()==int(opening.boats),"all-weapons prefix retains 60Hz autopilot, boats, route budgets and ordinary outcome")
	check(float(ship.fuel)>=0.0 and float(ship.fuel)<=float(opening.fuel) and float(ship.supplies)>=0.0 and float(ship.supplies)<=float(opening.supplies) and config==original and Lab.preset(world,"all_weapons")==original,"prefix uses finite stores and leaves ambush roster, fits and preset unchanged")
	# The same real battle must still obey the existing explicit routed escape.
	var rally: Dictionary=st.tactical.home[id].duplicate(true)
	var pressure_intent: Dictionary=st.tactical.intents.get(id,{}).duplicate(true)
	check(Battle.issue_order(st,[id],"withdraw",rally) and not Certification.current(st,ship,pressure_intent).ok,"explicit withdrawal immediately revokes the pressure hold")
	var before_withdraw: float=ship.ammo
	Battle.update(st,DT,{})
	var withdrawal: Dictionary=st.tactical.intents.get(id,{})
	var withdraw_record: Dictionary=st.tactical.predictions.get(str(withdrawal.get("pathFingerprint","")),{})
	var routed: bool=withdrawal.is_empty() or (not withdraw_record.is_empty() and str(withdrawal.get("phase",""))=="withdraw" and withdraw_record.candidate.fireMountIds.is_empty() and not withdraw_record.candidate.exit.is_empty() and withdraw_record.candidate.exit[-1]==Vector2(rally.x,rally.y))
	check(str(ship.order)=="withdraw" and routed and float(ship.ammo)==before_withdraw,"withdrawal needs its own checked route to rally and cannot borrow pressure fire authority")
	report.heavyPressure046={"seed":83,"dt":DT,"opening":opening,"ticks":18,"firstShotTick":first_shot_tick,"fireEvents":shots,"ammoSpent":spent,"checkedHoldTicks":checked_holds,"timeline":timeline,"withdrawReason":st.tactical.reasons.get(id,"")}

func run() -> void:
	started=Time.get_ticks_usec()
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var created: Dictionary=Lab.create(world,{"player":[Lab.entry(world,"tin_skiff")],"enemy":[Lab.entry(world,"tin_skiff")]},4101)
	check(bool(created.get("ok",false)),"canonical fixture boats use actual public fitting and deployment")
	if bool(created.get("ok",false)):
		cache_checks(created.battle.ships[0])
		var candidate_source: Dictionary=created.battle.ships[0].duplicate(true)
		candidate_source.mounts=Battle._mounts(created.battle.ships[0])
		candidate_input_checks(candidate_source)
		traffic_query_checks(created.battle.ships[0])
		route_checks(created.battle.ships[0])
		authority_checks(created.battle)
		recovery_checks(world)
		cadence_checks(world)
		heavy_pressure_checks(world)
		var benchmark=Benchmark.new()
		benchmark.action_sample(world,report,started)
		check(benchmark.failures.is_empty(),"shared compact action sample completes, moves both sides and emits/debits real automatic shots")
		report.actionFailures=benchmark.failures
	var folder: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	check(not folder.is_empty(),"Root supplies the focused artifact directory")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		var file=FileAccess.open(folder.path_join("COMBAT RUNTIME v0.041.json"),FileAccess.WRITE)
		check(file!=null,"focused artifact opens")
		if file!=null:
			report.fixture="combat_runtime041";report.complete=failures.is_empty();report.checks=checks;report.failures=failures;report.wallUs=Time.get_ticks_usec()-started
			file.store_string(JSON.stringify(report,"\t"));file.close()
	print("COMBAT_RUNTIME041 %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
