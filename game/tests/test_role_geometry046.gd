extends SceneTree
## Narrow source contracts. Root owns native execution and six-scenario motion proof.
const Lab = preload("res://scripts/fleet_lab.gd")
const Battle = preload("res://scripts/battle.gd")
const Tactical = preload("res://scripts/tactical_runtime.gd")
const Planner = preload("res://scripts/tactical_planner.gd")
const Roles = preload("res://scripts/tactical_role_plans.gd")
const Stations = preload("res://scripts/tactical_stations.gd")
const Routes = preload("res://scripts/tactical_routes.gd")
const Certification = preload("res://scripts/tactical_certification.gd")
const Damage = preload("res://scripts/damage.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ROLE GEOMETRY046: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var original_world: Dictionary = world.duplicate(true)
	var config: Dictionary = Lab.preset(world, "duel")
	config.player = [Lab.entry(world, "maiden_dreadnought"), Lab.entry(world, "tin_skiff")]
	config.enemy = [Lab.entry(world, "cobalt_frigate", 2)]
	config.player[0].loadout.weapons = ["stock_primary", "rapid_gun", "fire_rocket", "light_torpedo"]
	var made: Dictionary = Lab.create(world, config, 46046)
	check(bool(made.get("ok", false)), "real Lab accepts the cannon-primary mixed fit")
	if not bool(made.get("ok", false)):
		quit(1)
		return
	var battle: Dictionary = made.battle
	var own_id: String = str(battle.ships[0].id)
	var friend_id: String = str(battle.ships[1].id)
	# Layout only, before the first real update. No timer, event or store injection.
	for i: int in range(battle.ships.size()):
		var boat: Dictionary = battle.ships[i]
		boat.x = 650.0 if boat.team == "player" else 1200.0
		boat.y = (850.0 if i == 0 else 1100.0) if boat.team == "player" else (800.0 if i == 2 else 900.0)
		boat.angle = 0.0 if boat.team == "player" else PI
	Battle.update(battle, 1.0 / 60.0)
	var view: Dictionary = Tactical.view(battle, "player", [own_id])
	var context: Dictionary = Roles.ships_by_id(view)
	var own: Dictionary = context[own_id]
	var before: PackedByteArray = var_to_bytes(view)
	check(Roles.infer_role(view, own) == "heavy", "real cannon-primary dreadnought keeps its heavy role despite secondary tubes")
	var first: Dictionary = Roles.decide(view, own, {}, context)
	check(not str(first.state.targetId).is_empty(), "role selects an observed opponent")
	var reservations: Dictionary = {}
	reservations[friend_id] = {"targetId": str(first.state.targetId), "sector": 2, "until": float(view.time) + 2.0}
	var held: PackedByteArray = var_to_bytes(reservations)
	var shared: Dictionary = Roles.decide(view, own, {}, context, reservations)
	check(str(shared.state.targetId) != str(first.state.targetId), "existing friendly pressure separates otherwise similar autonomous targets")
	var committed: Dictionary = first.state.duplicate(true)
	committed.commitUntil = float(view.time) + 1.0
	check(Roles.decide(view, own, committed, context, reservations).state.targetId == first.state.targetId, "pressure does not jitter a live target commitment")
	var requests: Array = Stations.candidates(view, own, first, context, reservations)
	check(not requests.is_empty() and requests.size() <= Stations.MAX_OFFERS, "real snapshot yields bounded station requests")
	for candidate: Dictionary in requests:
		check(Stations.valid_candidate(candidate), "candidate field and point caps remain unchanged")
		var pass_target: Dictionary = context[str(candidate.targetId)]
		var pass_clearance: float = Routes.navigation_radius(own) + Routes.navigation_radius(pass_target) + 7.0
		var path: Array = candidate.approach + candidate["pass"] + candidate.exit
		var pass_clear: bool = true
		for j: int in range(path.size() - 1):
			pass_clear = pass_clear and Routes.distance(Roles.pos(pass_target), path[j], path[j + 1]) >= pass_clearance - 0.0001
		check(pass_clear, "ordinary approach/pass/exit does not cut through its observed target envelope")
	var target: Dictionary = context[str(first.state.targetId)]
	var center: Vector2 = Roles.pos(target)
	var clearance: float = Routes.navigation_radius(own) + Routes.navigation_radius(target) + 12.0
	var around: Array = Stations._target_approach(center + Vector2.LEFT * 400.0, center + Vector2.RIGHT * 400.0, target, clearance, 1.0)
	check(around.size() > 2 and around.size() <= Stations.MAX_LEG, "opposite-side setup uses a bounded route around the hull")
	var clear: bool = true
	for j: int in range(around.size() - 1):
		clear = clear and Routes.distance(center, around[j], around[j + 1]) >= clearance - 0.0001
	check(clear, "all offered orbit chords preserve hull stand-off")
	check(var_to_bytes(view) == before and var_to_bytes(reservations) == held, "role and station requests cannot mutate snapshots or shared reservations")
	check(Battle.issue_order(battle, [own_id], "attack", {"shipId": str(first.state.targetId)}), "public attack command accepts the observed target")
	var ordered_view: Dictionary = Tactical.view(battle, "player", [own_id])
	var ordered_context: Dictionary = Roles.ships_by_id(ordered_view)
	check(Roles.decide(ordered_view, ordered_context[own_id], {}, ordered_context, reservations).state.targetId == first.state.targetId, "team pressure cannot divert an explicit attack")
	check(world == original_world, "Lab and planning preserve source world data")
	view_parity051(battle, own_id, friend_id)
	solo_recovery051(view, context[friend_id])
	proof_reuse051()
	finite_traffic051()
	detached_routes051()
	static_rejections051(world)
	static_completion051()
	padding_egress051(world)
	crowd_escape051(world)
	reservation_egress051(world)
	print("ROLE GEOMETRY046: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func view_parity051(source: Dictionary, own_id: String, ally_id: String) -> void:
	# Pure views of the existing real Lab boats. No update, certificate or result
	# grant; the public full view remains the independent decision reference.
	var source_before: PackedByteArray=var_to_bytes([source.ships,source.tactical.mountCache,source.tactical.options,source.tactical.observed])
	var st: Dictionary=source.duplicate(true)
	var t: Dictionary=st.tactical
	# Deep duplication need not preserve aliases across the two containers.
	t.ships={}
	for boat: Dictionary in st.ships:t.ships[str(boat.id)]=boat
	var own: Dictionary=t.ships[own_id]
	var ally: Dictionary=t.ships[ally_id]
	var ally_ammo: float=float(ally.ammo)
	var ally_hp: float=float(ally.hp)
	var ally_water: float=float(ally.water)
	var enemy_id: String=""
	for id in t.ships:
		if t.ships[id].team!=own.team:enemy_id=str(id);break
	var cases: Array=[{"role":"auto"},{"role":"skirmisher"},{"role":"striker"},{"role":"screen"},{"role":"heavy"},{"role":"support"},{"role":"support","dry":true},{"role":"screen","wounded":true},{"role":"auto","escort":true}]
	var slim: Dictionary={}
	var full: Dictionary={}
	var profiling: bool=bool(Tactical.runtime_profile043().enabled)
	for trial: Dictionary in cases:
		own.order="escort" if trial.get("escort",false) else "engage"
		own.orderTarget={"shipId":ally_id} if trial.get("escort",false) else {}
		ally.order="escort";ally.orderTarget={"shipId":own_id}
		ally.ammo=0.0 if trial.get("dry",false) else ally_ammo
		ally.hp=float(ally.maxHp)*0.4 if trial.get("wounded",false) else ally_hp
		ally.water=float(ally.capacity)*0.25 if trial.get("wounded",false) else ally_water
		t.options.byId[own_id].role=trial.role
		# Match the actual closed-begin seam: observations precede planning, with
		# no motion or live input mutation between either side's snapshot calls.
		t.observed={}
		for id in t.ships:t.observed[id]=Tactical._observed(t.ships[id],t.mountCache[id].mounts)
		var held: PackedByteArray=var_to_bytes([st.ships,t.mountCache,t.options,t.memory])
		full=Tactical.view(st,str(own.team),[own_id])
		Tactical.set_runtime_profile043(true);Tactical.reset_runtime_profile043()
		slim=Tactical._begin_view051(st,str(own.team),[own_id])
		var counts: Dictionary=Tactical.runtime_profile043()
		Tactical.set_runtime_profile043(profiling)
		check(int(counts.ownCopies)==1 and int(counts.observedCalls)==0 and int(counts.enemyCopies)==0,"private view builds only the due owner and reuses closed observations")
		var full_context: Dictionary=Roles.ships_by_id(full)
		var slim_context: Dictionary=Roles.ships_by_id(slim)
		check(var_to_bytes(slim_context[own_id])==var_to_bytes(full_context[own_id]),"due owner retains every full public field and value")
		var ally_fields_match: bool=true
		for key: String in ["ammo","order","orderTarget","status"]:
			ally_fields_match=ally_fields_match and var_to_bytes(slim_context[ally_id][key])==var_to_bytes(full_context[ally_id][key])
		check(ally_fields_match and not slim_context[ally_id].has("breaches") and not slim_context[ally_id].has("crew") and not slim_context[ally_id].has("supplies") and not slim_context[ally_id].has("fuel"),"non-due protector retains current decision inputs without unused owner stores")
		check(full_context[ally_id].has("breaches") and full_context[ally_id].has("crew") and full_context[ally_id].has("fuel"),"public view still includes full non-due owner schema")
		var full_header: Dictionary=full.duplicate();full_header.erase("ships")
		var slim_header: Dictionary=slim.duplicate();slim_header.erase("ships")
		check(var_to_bytes(slim_header)==var_to_bytes(full_header),"private view preserves revisions, due IDs, options, groups and public mission")
		var inputs_before: PackedByteArray=var_to_bytes([full,slim,t.memory])
		var memory: Dictionary=t.memory[str(own.team)]
		var expected: Dictionary=Planner._prepare_begin(full,memory)
		var actual: Dictionary=Planner._prepare_begin(slim,memory)
		for key: String in ["dueIds","decisions","sources","candidates","scored"]:
			check(var_to_bytes(actual[key])==var_to_bytes(expected[key]),"private/public %s parity for %s"%[key,str(trial)])
		var expected_result: Dictionary=Planner._resolve_planned(full,memory,[],expected,Stations.LIVE_TRAFFIC_SECONDS051)
		var actual_result: Dictionary=Planner._resolve_planned(slim,memory,[],actual,Stations.LIVE_TRAFFIC_SECONDS051)
		check(var_to_bytes(actual_result)==var_to_bytes(expected_result),"actual no-offer resolution parity without manufactured certificates")
		check(var_to_bytes([full,slim,t.memory])==inputs_before and var_to_bytes([st.ships,t.mountCache,t.options,t.memory])==held,"pure planning/resolution cannot mutate views or their live source")
	var last_full: Dictionary=Roles.ships_by_id(full)
	var last_slim: Dictionary=Roles.ships_by_id(slim)
	var enemy: Dictionary=last_slim[enemy_id]
	check(var_to_bytes(enemy)==var_to_bytes(last_full[enemy_id]) and is_same(enemy,t.observed[enemy_id]),"private enemy reuses exactly the public observation with no hidden knowledge")
	check(enemy.is_read_only() and enemy.spec.is_read_only() and enemy.mounts.is_read_only() and enemy.mounts[0].is_read_only() and enemy.mountShotTimes.is_read_only(),"shared enemy and nested observations are immutable")
	check(last_slim[own_id].mounts.is_read_only() and not is_same(enemy.mounts,t.mountCache[enemy_id].mounts),"due owners share frozen observations detached from live mount fits")
	var reverse_full: Dictionary=Tactical.view(st,"enemy",[enemy_id])
	var reverse_slim: Dictionary=Tactical._begin_view051(st,"enemy",[enemy_id])
	check(var_to_bytes(Roles.ships_by_id(reverse_slim)[enemy_id])==var_to_bytes(Roles.ships_by_id(reverse_full)[enemy_id]),"opposite side also receives a complete fresh due owner")
	check(not enemy.has("ammo") and not enemy.has("status") and not enemy.has("order") and var_to_bytes(enemy)==var_to_bytes(last_full[enemy_id]),"opposite-side owner enrichment cannot leak into shared enemy observations")
	var slim_before: PackedByteArray=var_to_bytes(slim)
	var live_before: PackedByteArray=var_to_bytes([st.ships,t.mountCache,t.options])
	last_full[enemy_id].mounts[0].range+=1.0
	last_full[ally_id].orderTarget["copySafety051"]=true
	last_full[own_id].status.speedFactor=0.0
	check(var_to_bytes(slim)==slim_before and var_to_bytes([st.ships,t.mountCache,t.options])==live_before,"public copies remain mutable without poisoning private or live inputs")
	own.spec.speed+=1.0;own.orderTarget["copySafety051"]=true
	t.mountCache[enemy_id].mounts[0].range+=1.0
	t.ships[enemy_id].mountShotTimes["copySafety051"]=float(st.time)
	check(var_to_bytes(slim)==slim_before,"saved private snapshot stays detached after live nested inputs change")
	var fresh: Dictionary=Roles.ships_by_id(Tactical.view(st,str(own.team),[own_id]))
	check(fresh[own_id].spec.speed==own.spec.speed and fresh[own_id].orderTarget.has("copySafety051"),"public owner reads stay fresh after the private begin closes")
	check(var_to_bytes([source.ships,source.tactical.mountCache,source.tactical.options,source.tactical.observed])==source_before,"view parity cases preserve the actual source battle")

func solo_recovery051(source_view: Dictionary,source: Dictionary) -> void:
	# Detached role observations only: no synthetic certificate or battle grant.
	var own: Dictionary=source.duplicate(true)
	var enemy: Dictionary={}
	for boat: Dictionary in source_view.ships:
		if boat.team!=own.team:enemy=boat.duplicate(true);break
	var v: Dictionary=source_view.duplicate(true)
	v.time=2.0;v.ships=[own,enemy];v.dueIds=[str(own.id)]
	own.x=500.0;own.y=850.0;enemy.x=1000.0;enemy.y=850.0
	own.cooldown=0.0;own.weaponCooldowns=[0.0]
	var gun_id: String=str(own.mounts[0].id)
	own.mountShotTimes[gun_id]=1.5
	var prior: Dictionary={"role":"skirmisher","phase":"fire-pass","targetId":str(enemy.id),"leaderId":"","orderRevision":own.orderRevision,"phaseSince":0.0,"pursuitSince":2.0,"progressAt":2.0,"progressPos":Roles.pos(own),"passShots":4,"passShortShots":4,"passFirstShotAt":0.1,"passOpportunitySince":0.1,"shotTimes":own.mountShotTimes.duplicate(true)}
	var base: Dictionary=v.duplicate(true)
	var choice: Dictionary=Roles.decide(v,own,prior,Roles.ships_by_id(v))
	check(choice.state.get("localRecovery",false) and choice.state.phase=="breakaway","healthy solo gun burst enters bounded local recovery")
	if not choice.state.get("localRecovery",false):return
	var requests: Array=Stations.candidates(v,own,choice,Roles.ships_by_id(v))
	check(not requests.is_empty() and requests[0].approach[-1]==choice.state.localRally and Roles.pos(own).distance_to(choice.state.localRally)<=maxf(90.0,Routes.navigation_radius(own)*2.0)+0.001,"routine solo rally is anchored near the pass instead of birth home")
	check(requests.all(func(candidate):return candidate.fireMountIds.is_empty()),"local route requests claim no future firing window")
	check(Roles.solo_recovery_guns(v,own,choice.state)==[gun_id],"current-step recovery requests the useful gun only")
	v.time=4.1
	var blocked: Dictionary=Roles.decide(v,own,choice.state,Roles.ships_by_id(v))
	check(blocked.state.get("localRecovery",false),"elapsed recovery without observed travel cannot invent clearance")
	own.x-=70.0;own.cooldown=1.0;own.weaponCooldowns=[1.0]
	var loading: Dictionary=Roles.decide(v,own,choice.state,Roles.ships_by_id(v))
	check(loading.state.get("localRecovery",false),"real travel alone cannot bypass an unfinished gun reload")
	own.mountShotTimes[gun_id]=3.0
	var resumed: Dictionary=Roles.decide(v,own,choice.state,Roles.ships_by_id(v))
	check(resumed.state.phase=="approach" and not resumed.state.get("localRecovery",false),"observed completed reload/shot plus travel and turn time resumes the solo pass")
	for variant: String in ["wounded","dry","flood","fire","impaired","protector","rocket","named-rally"]:
		var trial: Dictionary=base.duplicate(true)
		var boat: Dictionary=trial.ships[0]
		match variant:
			"wounded":boat.hp=float(boat.maxHp)*0.4
			"dry":boat.ammo=0.0
			"flood":boat.water=float(boat.capacity)*0.5
			"fire":boat.fire=30.0
			"impaired":boat.status.speedFactor=0.2
			"protector":
				var ally: Dictionary=boat.duplicate(true);ally.id="protector051";ally.x=250.0
				trial.ships.append(ally)
			"rocket":boat.mounts[0].kind="rocket";boat.mounts[0].arc=TAU
			"named-rally":
				trial.options.byId[str(boat.id)].rally={"x":80.0,"y":80.0}
				trial.options.byId[str(boat.id)].erase("defaultRally051")
		var refusal: Dictionary=Roles.decide(trial,boat,choice.state,Roles.ships_by_id(trial))
		check(not refusal.state.get("localRecovery",false) and Roles.solo_recovery_guns(trial,boat,refusal.state).is_empty(),"routine solo recovery preserves "+variant+" refusal")

func proof_budget051(limit: int) -> Dictionary:
	return {"fullRoutes":0,"cacheHits":0,"rollouts":0,"samples":0,"clearanceTests":0,"exhaustions":0,"rolled":{},"clearanceLimit":limit}

func proof_state051(ships: Array) -> Dictionary:
	return {"tactical":{"routeCache":{},"cells":Routes.grid(ships,true)}}

func proof_pair051(label: String,reference: Dictionary,cached: Dictionary,geometry: Dictionary,owner: Dictionary,candidate: Dictionary,proofs: Routes._BeginProofs051,limit: int=4096) -> Dictionary:
	var old_budget: Dictionary=proof_budget051(limit)
	var new_budget: Dictionary=proof_budget051(limit)
	var expected: Dictionary=Routes.refine_live(reference,geometry,owner,candidate,old_budget)
	var actual: Dictionary=Routes._refine_begin051(cached,geometry,owner,candidate,new_budget,proofs)
	check(var_to_bytes(actual)==var_to_bytes(expected),label+": full typed refinement result matches public reference")
	check(var_to_bytes(new_budget)==var_to_bytes(old_budget),label+": every budget field matches public reference")
	check(var_to_bytes(cached.tactical.routeCache)==var_to_bytes(reference.tactical.routeCache),label+": persistent route cache matches public reference")
	return actual

func proof_reuse051() -> void:
	# Small paired source-candidate cases only. Public sweep/occupied stay the
	# independent reference; Root owns any native execution of this fixture.
	var geometry: Dictionary={"key":"open051","revision":51,"obstacles":[]}
	var owner: Dictionary={"id":"own051","team":"player","x":400.0,"y":800.0,"vx":0.0,"vy":0.0,"spec":{"size":12.0,"speed":80.0,"turn":2.0},"status":{"speedFactor":1.0},"fuel":100.0,"order":"engage","orderTarget":{}}
	var candidate: Dictionary={"approach":[Vector2(400,800),Vector2(600,800)],"pass":[Vector2(600,800)],"exit":[Vector2(600,800)],"candidateId":"stop051"}
	var held: PackedByteArray=var_to_bytes([geometry,owner,candidate])
	var reference: Dictionary=proof_state051([owner.duplicate(true)])
	var cached: Dictionary=proof_state051([owner])
	var owners: Dictionary={str(owner.id):owner}
	var proofs: Routes._BeginProofs051=Routes._begin_proofs051(geometry,cached.tactical.cells,owners)
	check(proof_pair051("repeated stop suffix",reference,cached,geometry,owner,candidate,proofs).status=="valid","open stopping route is valid")
	check(proofs.entries.size()==6,"four edge visits store only three exact terrain/traffic pairs")
	proof_pair051("same owner next offer",reference,cached,geometry,owner,candidate,proofs)
	check(proofs.entries.size()==6,"identical next offer reuses completed proofs")
	for limit: int in [0,1,2,3]:
		proof_pair051("warm proof tight budget %d"%limit,reference,cached,geometry,owner,candidate,proofs,limit)
	var shifted: Dictionary=candidate.duplicate(true)
	shifted.approach[1]=Vector2(600.00006103515625,800)
	proof_pair051("one float32 endpoint step",reference,cached,geometry,owner,shifted,proofs)
	check(proofs.entries.size()>6,"neighboring exact endpoints do not share a rounded proof")
	check(var_to_bytes([geometry,owner,candidate])==held,"proofs do not mutate geometry, owners or candidates")

	var corner_owner: Dictionary=owner.duplicate(true)
	corner_owner.x=480.0;corner_owner.y=720.0
	var land: Dictionary={"key":"corner051","revision":52,"obstacles":[{"points":[[500,600],[700,600],[700,700],[500,700]],"lo":Vector2(500,600),"hi":Vector2(700,700)}]}
	var corner: Dictionary={"approach":[Vector2(480,720)],"pass":[],"exit":[]}
	var land_reference: Dictionary=proof_state051([corner_owner.duplicate(true)])
	var land_cached: Dictionary=proof_state051([corner_owner])
	var land_proofs: Routes._BeginProofs051=Routes._begin_proofs051(land,land_cached.tactical.cells,{str(corner_owner.id):corner_owner})
	check(proof_pair051("polygon terminal proof",land_reference,land_cached,land,corner_owner,corner,land_proofs).status=="valid","near-corner route exercises a clear overlapping polygon bound")
	for limit: int in [2,3]:
		proof_pair051("warm spend(2) boundary %d"%limit,land_reference,land_cached,land,corner_owner,corner,land_proofs,limit)
	var pending_proofs: Routes._BeginProofs051=Routes._begin_proofs051(land,land_cached.tactical.cells,{str(corner_owner.id):corner_owner})
	proof_pair051("cold pending polygon",land_reference,land_cached,land,corner_owner,corner,pending_proofs,3)
	check(pending_proofs.entries.is_empty(),"pending geometry is never stored as a proof")
	proof_pair051("pending then enough budget",land_reference,land_cached,land,corner_owner,corner,pending_proofs)
	check(not pending_proofs.entries.is_empty(),"later completed walk may create terminal proofs")

	var ally: Dictionary=owner.duplicate(true)
	ally.id="ally051"
	var blocked_reference: Dictionary=proof_state051([owner.duplicate(true),ally.duplicate(true)])
	var blocked_cached: Dictionary=proof_state051([owner,ally])
	var blocked_proofs: Routes._BeginProofs051=Routes._begin_proofs051(geometry,blocked_cached.tactical.cells,owners)
	check(proof_pair051("ally blocks origin",blocked_reference,blocked_cached,geometry,owner,candidate,blocked_proofs).status=="blocked","live ally proof blocks this origin")
	proof_pair051("repeat blocked ally",blocked_reference,blocked_cached,geometry,owner,candidate,blocked_proofs)
	proof_pair051("blocked traffic debit refusal",blocked_reference,blocked_cached,geometry,owner,candidate,blocked_proofs,1)
	var foreign_owner: Dictionary=owner.duplicate(true)
	foreign_owner.team="enemy"
	check(not Routes._proof_scope051(blocked_proofs,geometry,blocked_cached.tactical.cells,foreign_owner),"equal-ID foreign owner is outside the closed scope")
	proof_pair051("new owner identity",blocked_reference,blocked_cached,geometry,foreign_owner,candidate,blocked_proofs)
	check(blocked_proofs.entries.size()==2,"foreign owner cannot add or borrow the registered owner's proofs")
	var entry_count: int=proofs.entries.size()
	reference.tactical.cells=blocked_reference.tactical.cells
	cached.tactical.cells=blocked_cached.tactical.cells
	check(proof_pair051("new observation grid",reference,cached,geometry,owner,candidate,proofs).status=="blocked","rebuilt grid cannot borrow the old clear proof")
	var new_geometry: Dictionary=geometry.duplicate(true)
	check(not Routes._proof_scope051(blocked_proofs,new_geometry,blocked_cached.tactical.cells,owner),"equal geometry values with a new identity miss")
	proof_pair051("new geometry identity",blocked_reference,blocked_cached,new_geometry,owner,candidate,blocked_proofs)
	check(proofs.entries.size()==entry_count and blocked_proofs.entries.size()==2,"new grid and geometry leave the old scopes untouched")

	var island: Dictionary={"key":"detour051","revision":53,"obstacles":[{"points":[[500,750],[600,750],[600,850],[500,850]],"lo":Vector2(500,750),"hi":Vector2(600,850)}]}
	var crossing: Dictionary={"approach":[Vector2(400,800),Vector2(800,800)],"pass":[Vector2(800,800)],"exit":[Vector2(800,800)]}
	var detour_reference: Dictionary=proof_state051([owner.duplicate(true)])
	var detour_cached: Dictionary=proof_state051([owner])
	var detour_proofs: Routes._BeginProofs051=Routes._begin_proofs051(island,detour_cached.tactical.cells,owners)
	check(proof_pair051("land graph detour",detour_reference,detour_cached,island,owner,crossing,detour_proofs).status=="valid","land blockage retains a valid graph detour")
	check(not detour_cached.tactical.routeCache.is_empty(),"graph route still populates the persistent cache")
	proof_pair051("persistent graph hit",detour_reference,detour_cached,island,owner,crossing,detour_proofs)

	var hostile: Dictionary=owner.duplicate(true)
	hostile.id="large051";hostile.team="enemy";hostile.x=1200.0;hostile.vx=-70.0;hostile.spec.size=120.0
	var late_reference: Dictionary=proof_state051([owner.duplicate(true),hostile.duplicate(true)])
	var late_cached: Dictionary=proof_state051([owner,hostile])
	var late_proofs: Routes._BeginProofs051=Routes._begin_proofs051(geometry,late_cached.tactical.cells,owners)
	check(proof_pair051("late oversized hostile",late_reference,late_cached,geometry,owner,crossing,late_proofs).status=="blocked","full-time grid bounds retain oversized hostile clearance")
	proof_pair051("repeat late hostile",late_reference,late_cached,geometry,owner,crossing,late_proofs)
	# Distinct exact traffic queries share only fixed observed hull inputs. A
	# new observation must reconstruct them, including velocity/physical size.
	var moving: Dictionary=owner.duplicate(true)
	moving.id="moving-body051";moving.x=380.0;moving.y=900.0;moving.vx=45.0;moving.vy=-4.0
	var moving_reference: Dictionary=proof_state051([owner.duplicate(true),moving.duplicate(true)])
	var moving_cached: Dictionary=proof_state051([owner,moving])
	var moving_proofs: Routes._BeginProofs051=Routes._begin_proofs051(geometry,moving_cached.tactical.cells,owners)
	check(proof_pair051("moving hull first route",moving_reference,moving_cached,geometry,owner,candidate,moving_proofs).status=="valid","moving ally stays clear on the initial route")
	proof_pair051("moving hull distinct exact endpoint",moving_reference,moving_cached,geometry,owner,shifted,moving_proofs)
	Routes._close_begin_proofs051(moving_proofs)
	moving.x=430.0;moving.y=760.0;moving.vx=0.0;moving.vy=200.0;moving.spec.size=20.0
	moving_reference=proof_state051([owner.duplicate(true),moving.duplicate(true)])
	moving_cached=proof_state051([owner,moving])
	var changed_proofs: Routes._BeginProofs051=Routes._begin_proofs051(geometry,moving_cached.tactical.cells,owners)
	check(proof_pair051("new observation moving crossing",moving_reference,moving_cached,geometry,owner,candidate,changed_proofs).status=="blocked","new velocity, origin and size retain the current crossing veto")
	for limit: int in [0,1,2]:
		proof_pair051("moving crossing debit refusal %d"%limit,moving_reference,moving_cached,geometry,owner,candidate,changed_proofs,limit)
	Routes._close_begin_proofs051(changed_proofs)
	for scope: Routes._BeginProofs051 in [proofs,land_proofs,pending_proofs,blocked_proofs,detour_proofs,late_proofs]:
		Routes._close_begin_proofs051(scope)
	check(not blocked_proofs.active and blocked_proofs.entries.is_empty(),"closing the begin scope expires every proof")
	proof_pair051("closed scope",blocked_reference,blocked_cached,geometry,owner,candidate,blocked_proofs)
	var next_begin: Routes._BeginProofs051=Routes._begin_proofs051(geometry,blocked_cached.tactical.cells,owners)
	check(next_begin.entries.is_empty(),"new begin starts without previous proofs")
	Routes._close_begin_proofs051(next_begin)

func finite_traffic051() -> void:
	# Private policy only. The unchanged public full-corridor API is the
	# reference; no engine clock, real motion or public traffic rule is altered.
	var geometry: Dictionary={"key":"finite051","revision":54,"obstacles":[]}
	var owner: Dictionary={"id":"finite-own051","team":"player","x":400.0,"y":800.0,"vx":0.0,"vy":0.0,"spec":{"size":12.0,"speed":100.0,"turn":2.0},"status":{"speedFactor":1.0},"fuel":100.0,"order":"engage","orderTarget":{}}
	# Actual nominal speed is 80, so these complete legs take 8+2+2 seconds.
	var long_path: Dictionary={"approach":[Vector2(400,800),Vector2(1040,800)],"pass":[Vector2(1040,960)],"exit":[Vector2(1200,960)]}
	var late: Dictionary=owner.duplicate(true)
	late.id="late051";late.team="enemy";late.x=1040.0;late.y=1440.0;late.vy=-80.0
	var clear_state: Dictionary=proof_state051([owner])
	var clear_full: Dictionary=Routes.refine_live(clear_state,geometry,owner,long_path,proof_budget051(4096))
	check(clear_full.status=="valid" and clear_full.eta==12.0,"full public empty-water reference retains the twelve-second route")
	# Edge two runs [1,3]. Its exact t=2 clip is (480,880), not the
	# fraction 2/3 of that edge. Allied clearance is (12+4)+12+3=31.
	var straddle: Dictionary={"approach":[Vector2(400,800),Vector2(480,800),Vector2(480,960)],"pass":[Vector2(560,960)],"exit":[]}
	var beyond: Dictionary=owner.duplicate(true)
	beyond.id="beyond051";beyond.x=480.0;beyond.y=912.0
	var inside: Dictionary=beyond.duplicate(true)
	inside.id="inside051";inside.y=910.0
	var near: Dictionary=owner.duplicate(true)
	near.id="near051";near.x=440.0
	var hold: Dictionary={"approach":[Vector2(400,800)],"pass":[],"exit":[]}
	var overlap: Dictionary=owner.duplicate(true)
	overlap.id="overlap051"
	var hostile_hold: Dictionary=overlap.duplicate(true)
	hostile_hold.id="hostile-hold051";hostile_hold.team="enemy"
	var separating: Dictionary=hostile_hold.duplicate(true)
	separating.id="separating051";separating.x=390.0
	var contact: Dictionary=hostile_hold.duplicate(true)
	contact.id="contact051";contact.x=550.0
	var rammer: Dictionary=owner.duplicate(true)
	rammer.order="ram";rammer.orderTarget={"shipId":str(contact.id)}
	var land: Dictionary={"key":"finite-land051","revision":55,"obstacles":[{"points":[[1000,700],[1100,700],[1100,900],[1000,900]],"lo":Vector2(1000,700),"hi":Vector2(1100,900)}]}
	var land_path: Dictionary={"approach":[Vector2(400,800),Vector2(560,800)],"pass":[Vector2(1040,800)],"exit":[]}
	var cases: Array=[
		{"label":"late moving crossing","other":late,"path":long_path,"full":"blocked","finite":"valid","long":true,"fallback":true},
		{"label":"straddling edge outside exact prefix","other":beyond,"path":straddle,"full":"blocked","finite":"valid"},
		{"label":"straddling edge inside exact prefix","other":inside,"path":straddle,"full":"blocked","finite":"blocked","same":true},
		{"label":"near allied blocker","other":near,"path":{"approach":[Vector2(400,800),Vector2(480,800)],"pass":[],"exit":[]},"full":"blocked","finite":"blocked","same":true,"budget":true},
		{"label":"initial hold allied overlap","other":overlap,"path":hold,"full":"blocked","finite":"blocked","same":true,"budget":true},
		{"label":"initial hold hostile exception","other":hostile_hold,"path":hold,"full":"valid","finite":"valid","same":true,"budget":true},
		{"label":"inherited separating hostile","other":separating,"path":long_path,"full":"valid","finite":"valid","same":true},
		{"label":"explicit physical contact exception","own":rammer,"other":contact,"path":long_path,"full":"valid","finite":"valid","same":true},
		{"label":"land beyond two seconds","geometry":land,"path":land_path,"full":"blocked","finite":"blocked","same":true}
	]
	for trial: Dictionary in cases:
		var g: Dictionary=trial.get("geometry",geometry)
		var own: Dictionary=trial.get("own",owner)
		var path: Dictionary=trial.path
		var ships: Array=[own]
		if trial.has("other"):ships.append(trial.other)
		var original: PackedByteArray=var_to_bytes([g,ships,path])
		var st: Dictionary=proof_state051(ships)
		var old_budget: Dictionary=proof_budget051(4096)
		var expected: Dictionary=Routes.refine_live(st,g,own,path,old_budget)
		var proofs: Routes._BeginProofs051=Routes._begin_proofs051(g,st.tactical.cells,{str(own.id):own})
		var new_budget: Dictionary=proof_budget051(4096)
		var actual: Dictionary=Routes._refine_begin051(st,g,own,path,new_budget,proofs,2.0)
		var label: String=str(trial.label)
		check(expected.status==trial.full,label+": unchanged public full-corridor result")
		check(actual.status==trial.finite,label+": private two-second traffic result")
		if trial.get("same",false):check(var_to_bytes(actual)==var_to_bytes(expected),label+": complete typed result remains identical")
		if trial.get("budget",false):check(var_to_bytes(new_budget)==var_to_bytes(old_budget),label+": uncut prefix retains every work debit")
		if trial.get("long",false):check(var_to_bytes(actual)==var_to_bytes(clear_full),label+": full waypoints and twelve-second ETA remain unchanged")
		Routes._close_begin_proofs051(proofs)
		if trial.get("fallback",false):
			var fallback: Dictionary=Routes._refine_begin051(st,g,own,path,proof_budget051(4096),proofs,2.0)
			check(var_to_bytes(fallback)==var_to_bytes(actual),label+": closed proof scope retains policy through fully checked fallback")
		check(var_to_bytes([g,ships,path])==original,label+": source geometry, owners and route remain detached")

func detached_routes051() -> void:
	# Pure owned worker/main states. No worker dispatch, clock advance or engine
	# runner is added; public full traffic remains the independent reference.
	var geometry: Dictionary={"key":"detached051","revision":56,"obstacles":[{"points":[[430,650],[470,650],[470,750],[430,750]],"lo":Vector2(430,650),"hi":Vector2(470,750)}]}
	var owner: Dictionary={"id":"detached-own051","team":"player","x":400.0,"y":800.0,"vx":0.0,"vy":0.0,"spec":{"size":12.0,"speed":100.0,"turn":2.0},"status":{"speedFactor":1.0},"fuel":100.0,"order":"engage","orderTarget":{}}
	var request: Dictionary={"approach":[Vector2(400,800),Vector2(1040,800)],"pass":[Vector2(1040,960)],"exit":[Vector2(1200,960)]}
	var before: PackedByteArray=var_to_bytes([geometry,owner,request])
	var worker: Dictionary=proof_state051([owner.duplicate(true)])
	worker.time=0.0
	var full: Dictionary=Routes.refine_live(worker,geometry,owner,request,proof_budget051(2900))
	var prepared: Dictionary=Routes._prepare_detached051(worker,geometry,owner,request,proof_budget051(2900))
	check(prepared.status=="valid" and prepared.candidate==full.candidate and prepared.eta==12.0 and prepared.eta==full.eta,"detached preparation retains every static edge and the full twelve-second ETA")
	check(prepared.origin051==Routes.point(owner) and prepared.radius051==Routes.planning_radius(owner) and prepared.terrainKey051==geometry.key and prepared.terrainRevision051==geometry.revision and prepared.observedAt051==worker.time and prepared.trafficSeconds051==2.0,"detached preparation stamps its exact origin, radius, terrain, clock and two-second snapshot policy")
	var no_work: Dictionary=Routes._prepare_detached051(worker,geometry,owner,request,proof_budget051(0))
	check(no_work.status=="pending","zero worker clearance allowance cannot produce a completed prepared route")
	var later: Dictionary=owner.duplicate(true)
	later.id="detached-later051";later.x=540.0
	var blocked_worker: Dictionary=proof_state051([owner.duplicate(true),later.duplicate(true)])
	blocked_worker.time=0.0
	check(Routes._prepare_detached051(blocked_worker,geometry,owner,request,proof_budget051(2900)).status=="blocked","worker preparation really checks snapshot traffic within two seconds")
	var current: Dictionary=proof_state051([owner,later])
	current.time=0.125
	var adopted: Dictionary=Routes._adopt_prepared051(current,geometry,owner,request,prepared,proof_budget051(4096),null,2.0)
	check(adopted.status=="valid" and adopted.candidate.approach==[Vector2(1040,800)] and adopted.candidate["pass"]==request["pass"] and adopted.candidate.exit==request.exit and adopted.eta==12.0,"fresh worker adoption retains all future edges and full ETA beyond the current prefix")
	var boundary: Dictionary=current.duplicate()
	boundary.time=0.15
	check(Routes._adopt_prepared051(boundary,geometry,owner,request,prepared,proof_budget051(4096),null,2.0).status=="valid","the exact 0.15s worker age boundary remains eligible")
	check(Routes.refine_live(current,geometry,owner,request,proof_budget051(4096)).status=="blocked","public full traffic still refuses the later obstruction")
	var fallback_budget: Dictionary=proof_budget051(4096)
	var fallback: Dictionary=Routes._refine_begin051(current,geometry,owner,request,fallback_budget,null,2.0)
	check(fallback.status=="blocked","ordinary main two-second fallback still sees the later obstruction")
	var changes: Array=[
		{"label":"stale","field":"observedAt051","value":-0.1},
		{"label":"future","field":"observedAt051","value":0.25},
		{"label":"nonfinite clock","field":"observedAt051","value":NAN},
		{"label":"unstamped clock","field":"observedAt051","erase":true},
		{"label":"changed terrain key","field":"terrainKey051","value":"other051"},
		{"label":"changed terrain revision","field":"terrainRevision051","value":57},
		{"label":"changed radius","field":"radius051","value":prepared.radius051+1.0},
		{"label":"changed snapshot policy","field":"trafficSeconds051","value":1.0},
		{"label":"unstamped origin","field":"origin051","erase":true},
		{"label":"pending worker path","field":"status","value":"pending"}
	]
	for change: Dictionary in changes:
		var invalid: Dictionary=prepared.duplicate(true)
		if change.get("erase",false):invalid.erase(change.field)
		else:invalid[change.field]=change.value
		var work: Dictionary=proof_budget051(4096)
		var actual: Dictionary=Routes._adopt_prepared051(current,geometry,owner,request,invalid,work,null,2.0)
		check(var_to_bytes(actual)==var_to_bytes(fallback) and var_to_bytes(work)==var_to_bytes(fallback_budget),str(change.label)+": adoption falls back with the exact full main result and debits")
	var near: Dictionary=later.duplicate(true)
	near.id="detached-near051";near.x=450.0
	var obstructed: Dictionary=proof_state051([owner,near])
	obstructed.time=current.time
	var refused: Dictionary=Routes._adopt_prepared051(obstructed,geometry,owner,request,prepared,proof_budget051(4096),null,2.0)
	check(refused.status=="blocked" and refused.reason=="Hull occupies this approach","a newly appearing CURRENT obstacle within 0.3s vetoes a completed worker route")
	var crossing: Dictionary=near.duplicate(true)
	crossing.x=416.0;crossing.y=760.0;crossing.vy=200.0
	var crossing_state: Dictionary=proof_state051([owner,crossing])
	crossing_state.time=current.time
	check(Routes._adopt_prepared051(crossing_state,geometry,owner,request,prepared,proof_budget051(4096),null,2.0).status=="blocked","current traffic crossing within 0.3s vetoes an otherwise clear worker route")
	var moved: Dictionary=owner.duplicate(true)
	moved.y=700.0
	var moved_state: Dictionary=proof_state051([moved])
	moved_state.time=current.time
	var connector: Dictionary=Routes._adopt_prepared051(moved_state,geometry,moved,request,prepared,proof_budget051(4096),null,2.0)
	check(connector.status=="blocked" and connector.reason=="Checking current land connector","actual current pose must pass a fresh full land connector")
	check(Routes._adopt_prepared051(current,geometry,owner,request,prepared,proof_budget051(0),null,2.0).status=="pending","fresh adoption cannot waive the current connector's work debit")
	check(var_to_bytes([geometry,owner,request])==before,"worker preparation and current adoption preserve their source geometry, owner and request")

func static_rejections051(world: Dictionary) -> void:
	# R13 raw records these initial poses/islands, but no request/rejection log.
	# Generate the concrete station through the actual source, not a new planner.
	var spec: Dictionary=world.HULLS.filter(func(h):return h.id=="bilge_punt")[0].duplicate(true)
	var owner: Dictionary={"id":"player-0-bilge_punt","team":"player","x":1000.0,"y":610.0,"vx":0.0,"vy":0.0,"angle":0.0,"ammo":80.0,"fuel":120.0,"formationIndex":0,"order":"engage","orderRevision":1,"spec":spec,"status":{"speedFactor":1.0,"weaponFactor":1.0},"mounts":[{"id":"mount0","kind":"gun","range":spec.range,"damage":spec.damage,"fireRate":spec.fireRate,"speed":850.0,"arc":TAU}]}
	var enemy: Dictionary=owner.duplicate(true)
	enemy.id="enemy-0-bilge_punt";enemy.team="enemy";enemy.x=1290.0;enemy.angle=PI
	var view: Dictionary={"time":0.0,"snapshotRevision":1,"ships":[owner,enemy],"options":{"byId":{}}}
	var context: Dictionary=Roles.ships_by_id(view)
	var decision: Dictionary={"state":{"role":"skirmisher","phase":"approach","targetId":enemy.id},"range":Roles.role_range(view,owner,"skirmisher"),"targets":[enemy.id],"detailedIds":[enemy.id]}
	var request: Dictionary={}
	for candidate: Dictionary in Stations.candidates(view,owner,decision,context):
		if candidate.sector==1:request=candidate
	check(not request.is_empty(),"R13 starting poses generate the existing skirmisher sector-one offer")
	if request.is_empty():return
	var islands: Array=[{"points":[[850,80],[1130,120],[1210,310],[1030,420],[820,300]]},{"points":[[1040,1320],[1240,1250],[1430,1450],[1320,1640],[1070,1580]]}]
	var blocker: Dictionary=owner.duplicate(true)
	blocker.id="snapshot-traffic051"
	var worker: Dictionary=proof_state051([owner,enemy,blocker])
	worker.time=0.0;worker.islands=islands
	var geometry: Dictionary=Routes.terrain(worker)
	check(Routes.inside(request.exit[-1],islands[0].points),"source-generated R13 exit near (1116,200) is inside the real northern island")
	var held: PackedByteArray=var_to_bytes([geometry,owner,request])
	var old_state: Dictionary=worker.duplicate(true)
	var old_budget: Dictionary=proof_budget051(4096)
	var expected: Dictionary=Routes._refine_begin051(old_state,geometry,owner,request,old_budget,null,2.0)
	var budget: Dictionary=proof_budget051(4096)
	var prepared: Dictionary=Routes._prepare_detached051(worker,geometry,owner,request,budget,proof_budget051(128))
	check(prepared.status==expected.status and prepared.candidate==expected.candidate and prepared.get("eta")==expected.get("eta") and prepared.get("reason")==expected.get("reason"),"worker static provenance preserves the exact original refinement result")
	check(budget==old_budget and worker.tactical.routeCache==old_state.tactical.routeCache,"worker endpoint proof does not debit the next offer or change the route cache")
	check(prepared.status=="blocked" and prepared.reason=="Hull occupies this approach" and Routes._reject_prepared_static051(geometry,owner,request,prepared),"independent fixed exit proof can expose impossible land hidden after snapshot traffic refusal")
	check(prepared.staticRejection051.is_read_only() and prepared.staticRejection051.paths.is_read_only() and prepared.staticRejection051.paths[2].is_read_only(),"worker rejection provenance seals detached exact original paths")
	var reminted: Dictionary=request.duplicate(true)
	reminted.candidateId="fresh-main051";reminted.snapshotRevision=2
	check(Routes._reject_prepared_static051(geometry,owner,reminted,prepared),"main may remint request metadata while retaining every exact fixed waypoint")
	for leg: String in ["approach","pass","exit"]:
		var changed: Dictionary=request.duplicate(true)
		changed[leg][0]+=Vector2(0.000244140625,0)
		check(not Routes._reject_prepared_static051(geometry,owner,changed,prepared),leg+": neighboring exact path cannot borrow a static rejection")
	for field: String in ["terrainKey051","terrainRevision051","radius051","staticRejection051"]:
		var missing: Dictionary=prepared.duplicate()
		missing.erase(field)
		check(not Routes._reject_prepared_static051(geometry,owner,request,missing),field+": unstamped worker result cannot reject a current offer")
	for status: String in ["pending","valid"]:
		var changed: Dictionary=prepared.duplicate()
		changed.status=status
		check(not Routes._reject_prepared_static051(geometry,owner,request,changed),status+": only completed blocked worker packets can carry a rejection")
	var changed_geometry: Dictionary=geometry.duplicate()
	changed_geometry.revision+=1
	check(not Routes._reject_prepared_static051(changed_geometry,owner,request,prepared),"terrain revision invalidates static endpoint provenance")
	changed_geometry=geometry.duplicate();changed_geometry.key="different051"
	check(not Routes._reject_prepared_static051(changed_geometry,owner,request,prepared),"terrain identity invalidates static endpoint provenance")
	var changed_owner: Dictionary=owner.duplicate(true)
	changed_owner.spec.size+=1.0
	check(not Routes._reject_prepared_static051(geometry,changed_owner,request,prepared),"changed planning disk invalidates static endpoint provenance")
	changed_owner=owner.duplicate(true);changed_owner.id="replacement051"
	check(not Routes._reject_prepared_static051(geometry,changed_owner,request,prepared),"another owner cannot borrow the joined worker's rejection")
	var default_packet: Dictionary=Routes._prepare_detached051(worker,geometry,owner,request,proof_budget051(4096))
	check(not default_packet.has("staticRejection051"),"default preparation without a private job allowance produces no proof")
	for limit: int in [0,1]:
		var limited: Dictionary=Routes._prepare_detached051(worker,geometry,owner,request,proof_budget051(limit),proof_budget051(128))
		check(limited.status=="pending" and not limited.has("staticRejection051"),"pending route allowance %d never creates static rejection authority"%limit)
	for limit: int in [0,1,2]:
		var limited: Dictionary=Routes._prepare_detached051(worker,geometry,owner,request,proof_budget051(4096),proof_budget051(limit))
		check(limited.status=="blocked" and not limited.has("staticRejection051"),"pending/exhausted proof allowance %d leaves the blocked route unchanged"%limit)
	var shared: Dictionary=proof_budget051(128)
	var proven: int=0
	var unchanged: bool=true
	for i: int in range(64):
		var normal: Dictionary=proof_budget051(4096)
		var packet: Dictionary=Routes._prepare_detached051(worker,geometry,owner,request,normal,shared)
		if packet.has("staticRejection051"):proven+=1
		unchanged=unchanged and packet.status==expected.status and packet.candidate==expected.candidate and normal==old_budget
	check(proven>0 and shared.clearanceTests==128,"all blocked hull/offer calls together consume at most one 128-debit job allowance")
	check(unchanged,"shared proof exhaustion preserves every normal route result and budget")
	var exhausted: Dictionary=Routes._prepare_detached051(worker,geometry,owner,request,proof_budget051(4096),shared)
	check(not exhausted.has("staticRejection051") and shared.clearanceTests==128,"later offers cannot renew or exceed the exhausted job proof allowance")
	var open_geometry: Dictionary={"key":"open-static051","revision":1,"obstacles":[]}
	var legal: Dictionary={"approach":[Routes.point(owner),Vector2(1080,610)],"pass":[],"exit":[]}
	var dynamic: Dictionary=Routes._prepare_detached051(worker,open_geometry,owner,legal,proof_budget051(4096),proof_budget051(128))
	check(dynamic.status=="blocked" and not Routes._reject_prepared_static051(open_geometry,owner,legal,dynamic),"snapshot traffic alone cannot reject a usable fixed route")
	var current: Dictionary=proof_state051([owner])
	check(Routes.refine_live(current,open_geometry,owner,legal,proof_budget051(4096)).status=="valid","moving traffic may clear; the original alternative remains usable on main")
	var crossing: Dictionary=legal.duplicate(true)
	crossing.approach[1]=Vector2(1400,610)
	var corridor: Dictionary={"key":"chord-static051","revision":1,"obstacles":[{"points":[[1150,550],[1190,550],[1190,650],[1150,650]],"lo":Vector2(1150,550),"hi":Vector2(1190,650)}]}
	var chord: Dictionary=Routes._prepare_detached051(worker,corridor,owner,crossing,proof_budget051(4096),proof_budget051(128))
	check(chord.status=="blocked" and not Routes._reject_prepared_static051(corridor,owner,crossing,chord),"blocked direct segment with clear endpoints is never a terminal rejection")
	check(Routes.refine_live(current,corridor,owner,crossing,proof_budget051(4096)).status=="valid","full main graph can still find a detour around the blocked chord")
	var outside: Dictionary=legal.duplicate(true)
	outside.approach[1]=Vector2(0,610)
	var bounds: Dictionary=Routes._prepare_detached051(worker,open_geometry,owner,outside,proof_budget051(4096),proof_budget051(128))
	check(Routes._reject_prepared_static051(open_geometry,owner,outside,bounds),"fixed endpoint disk outside battle bounds is provably impossible")
	var near_land: Dictionary=legal.duplicate(true)
	near_land.approach[1]=Vector2(1125,610)
	var disk: Dictionary=Routes._prepare_detached051(worker,corridor,owner,near_land,proof_budget051(4096),proof_budget051(128))
	check(not Routes.inside(near_land.approach[1],corridor.obstacles[0].points) and Routes._reject_prepared_static051(corridor,owner,near_land,disk),"fixed disk overlapping shore is impossible even when its center is outside land")
	var origin_land: Dictionary={"key":"origin-static051","revision":1,"obstacles":[{"points":[[990,600],[1010,600],[1010,620],[990,620]],"lo":Vector2(990,600),"hi":Vector2(1010,620)}]}
	var origin_only: Dictionary=Routes._prepare_detached051(worker,origin_land,owner,legal,proof_budget051(4096),proof_budget051(128))
	check(origin_only.status=="blocked" and not Routes._reject_prepared_static051(origin_land,owner,legal,origin_only),"sampled origin in land is never mistaken for a fixed future endpoint proof")
	check(var_to_bytes([geometry,owner,request])==held,"provenance and read-only predicate preserve all source geometry, owner fields and request paths")

func static_completion051() -> void:
	# Existing main adoption is the independent reference for current authority;
	# default/public refinement still stops at the first snapshot traffic refusal.
	var geometry: Dictionary={"key":"complete-static051","revision":57,"obstacles":[{"points":[[430,650],[470,650],[470,750],[430,750]],"lo":Vector2(430,650),"hi":Vector2(470,750)}]}
	var owner: Dictionary={"id":"complete-own051","team":"player","x":400.0,"y":800.0,"vx":0.0,"vy":0.0,"spec":{"size":12.0,"speed":100.0,"turn":2.0},"status":{"speedFactor":1.0},"fuel":100.0,"order":"engage","orderTarget":{}}
	var blocker: Dictionary=owner.duplicate(true)
	blocker.id="complete-old-traffic051"
	var request: Dictionary={"shipId":owner.id,"approach":[Vector2(400,800),Vector2(1040,800)],"pass":[Vector2(1040,960)],"exit":[Vector2(1200,960)]}
	var held: PackedByteArray=var_to_bytes([geometry,owner,blocker,request])
	var worker: Dictionary=proof_state051([owner,blocker])
	worker.time=0.0
	var default_budget: Dictionary=proof_budget051(2900)
	var original: Dictionary=Routes._prepare_detached051(worker,geometry,owner,request,default_budget)
	check(original.status=="blocked" and not original.has("staticComplete051") and default_budget.clearanceTests==3,"default preparation still stops on the initial traffic block after the same three debits")
	var worker_budget: Dictionary=proof_budget051(2900)
	var prepared: Dictionary=Routes._prepare_detached051(worker,geometry,owner,request,worker_budget,{},true)
	var clear_worker: Dictionary=proof_state051([owner])
	clear_worker.time=worker.time
	var clear_packet: Dictionary=Routes._prepare_detached051(clear_worker,geometry,owner,request,proof_budget051(2900))
	check(prepared.status==original.status and prepared.reason==original.reason and prepared.trafficSeconds051==2.0,"worker completion retains the blocked snapshot forecast and its original two-second policy")
	check(prepared.candidate==clear_packet.candidate and prepared.eta==12.0 and prepared.eta==clear_packet.eta,"after old traffic blocks, every static leg and the full twelve-second ETA still finish")
	check(worker_budget.clearanceTests==10 and worker_budget.fullRoutes==0 and worker_budget.exhaustions==0,"completion debits all four static queries and both snapshot traffic queries on the original worker budget")
	check(prepared.has("staticComplete051") and Routes._static_complete_matches051(owner,request,prepared),"only the fully completed traffic-blocked route lends an exact static proof")
	var completed: Dictionary=prepared.get("staticComplete051",{})
	check(completed.is_read_only() and completed.get("requests",[]).is_read_only() and completed.get("paths",[]).is_read_only(),"static completion seals its owner, request, routed paths and ETA")
	if completed.is_empty():return
	check(completed.requests[2].is_read_only() and completed.paths[2].is_read_only(),"future exit paths are detached and sealed as well as the first leg")
	var current: Dictionary=proof_state051([owner])
	current.time=0.125
	var reference_budget: Dictionary=proof_budget051(4096)
	var reference: Dictionary=Routes._adopt_prepared051(current,geometry,owner,request,clear_packet,reference_budget,null,2.0)
	var current_budget: Dictionary=proof_budget051(4096)
	var adopted: Dictionary=Routes._adopt_prepared051(current,geometry,owner,request,prepared,current_budget,null,2.0)
	check(adopted.status=="valid" and var_to_bytes(adopted)==var_to_bytes(reference),"old snapshot traffic that CURRENTLY cleared reuses exactly the existing valid-worker adoption path")
	check(current_budget==reference_budget and current_budget.clearanceTests==2,"reused blocked packet pays the same fresh connector debits as ordinary adoption")
	var fallback_budget: Dictionary=proof_budget051(4096)
	var fallback: Dictionary=Routes._refine_begin051(current,geometry,owner,request,fallback_budget,null,2.0)
	check(fallback.status=="valid" and fallback.eta==adopted.eta and fallback_budget.clearanceTests>current_budget.clearanceTests,"full static work moves to the worker without changing the completed ETA")
	var obstructed: Dictionary=proof_state051([owner,blocker])
	obstructed.time=current.time
	var blocked_budget: Dictionary=proof_budget051(4096)
	var still_blocked: Dictionary=Routes._adopt_prepared051(obstructed,geometry,owner,request,prepared,blocked_budget,null,2.0)
	var ordinary_budget: Dictionary=proof_budget051(4096)
	var ordinary: Dictionary=Routes._adopt_prepared051(obstructed,geometry,owner,request,clear_packet,ordinary_budget,null,2.0)
	check(still_blocked.status=="blocked" and var_to_bytes(still_blocked)==var_to_bytes(ordinary) and blocked_budget==ordinary_budget,"CURRENT traffic that remains blocked vetoes reuse with unchanged authority and debits")
	var late: Dictionary=blocker.duplicate(true)
	late.x=540.0
	var late_state: Dictionary=proof_state051([owner,late])
	late_state.time=0.0
	var late_packet: Dictionary=Routes._prepare_detached051(late_state,geometry,owner,request,proof_budget051(2900),{},true)
	check(late_packet.status=="blocked" and late_packet.has("staticComplete051"),"worker still checks traffic beyond the 0.3s main prefix through its full two-second snapshot")
	var moved: Dictionary=owner.duplicate(true)
	moved.y=700.0
	var moved_state: Dictionary=proof_state051([moved])
	moved_state.time=current.time
	var connector: Dictionary=Routes._adopt_prepared051(moved_state,geometry,moved,request,prepared,proof_budget051(4096),null,2.0)
	check(connector.status=="blocked" and connector.reason=="Checking current land connector","even a complete static packet cannot borrow the old origin's clear land connector")
	check(Routes._adopt_prepared051(current,geometry,owner,request,prepared,proof_budget051(0),null,2.0).status=="pending","static reuse cannot waive a refused fresh-connector debit")
	for limit: int in [0,1,2,3,4,5]:
		var limited_budget: Dictionary=proof_budget051(limit)
		var limited: Dictionary=Routes._prepare_detached051(worker,geometry,owner,request,limited_budget,{},true)
		check(limited.status=="pending" and not limited.has("staticComplete051") and limited_budget.clearanceTests<=limit and limited_budget.exhaustions>0,"worker exhaustion %d before or AFTER the first traffic block never lends static completion"%limit)
	var changes: Array=[
		{"label":"stale blocked proof","field":"observedAt051","value":-0.1},
		{"label":"changed terrain key","field":"terrainKey051","value":"other-complete051"},
		{"label":"changed terrain revision","field":"terrainRevision051","value":58},
		{"label":"changed radius","field":"radius051","value":prepared.radius051+1.0},
		{"label":"changed snapshot forecast","field":"trafficSeconds051","value":0.3},
		{"label":"changed full ETA","field":"eta","value":prepared.eta+0.125},
		{"label":"pending packet","field":"status","value":"pending"},
		{"label":"missing completion","field":"staticComplete051","erase":true}
	]
	for change: Dictionary in changes:
		var invalid: Dictionary=prepared.duplicate()
		if change.get("erase",false):invalid.erase(change.field)
		else:invalid[change.field]=change.value
		var work: Dictionary=proof_budget051(4096)
		var actual: Dictionary=Routes._adopt_prepared051(current,geometry,owner,request,invalid,work,null,2.0)
		check(var_to_bytes(actual)==var_to_bytes(fallback) and work==fallback_budget,str(change.label)+": unusable completion retains exact main fallback results and debits")
	for leg: String in ["approach","pass","exit"]:
		var changed: Dictionary=request.duplicate(true)
		changed[leg][-1]+=Vector2(0.000244140625,0)
		var expected_budget: Dictionary=proof_budget051(4096)
		var expected: Dictionary=Routes._refine_begin051(current,geometry,owner,changed,expected_budget,null,2.0)
		var work: Dictionary=proof_budget051(4096)
		var actual: Dictionary=Routes._adopt_prepared051(current,geometry,owner,changed,prepared,work,null,2.0)
		check(var_to_bytes(actual)==var_to_bytes(expected) and work==expected_budget,leg+": any exact request-path change falls back without borrowing old static land work")
		var altered: Dictionary=prepared.duplicate()
		altered.candidate=prepared.candidate.duplicate(true)
		altered.candidate[leg][-1]+=Vector2(0.000244140625,0)
		check(not Routes._static_complete_matches051(owner,request,altered),leg+": changed routed output cannot borrow the sealed path or ETA")
	var foreign: Dictionary=owner.duplicate(true)
	foreign.id="other-complete-owner051"
	check(not Routes._static_complete_matches051(foreign,request,prepared),"a different owner cannot borrow a completed worker path")
	var changed_geometry: Dictionary=geometry.duplicate()
	changed_geometry.revision+=1
	var changed_owner: Dictionary=owner.duplicate(true)
	changed_owner.spec.size+=1.0
	for inputs: Dictionary in [{"geometry":changed_geometry,"owner":owner},{"geometry":geometry,"owner":changed_owner}]:
		var expected_budget: Dictionary=proof_budget051(4096)
		var expected: Dictionary=Routes._refine_begin051(current,inputs.geometry,inputs.owner,request,expected_budget,null,2.0)
		var work: Dictionary=proof_budget051(4096)
		var actual: Dictionary=Routes._adopt_prepared051(current,inputs.geometry,inputs.owner,request,prepared,work,null,2.0)
		check(var_to_bytes(actual)==var_to_bytes(expected) and work==expected_budget,"actual terrain/radius changes require the original full main walk and debits")
	var late_land: Dictionary=geometry.duplicate(true)
	late_land.key="late-static-fail051"
	late_land.obstacles.append({"points":[[1180,940],[1220,940],[1220,980],[1180,980]],"lo":Vector2(1180,940),"hi":Vector2(1220,980)})
	var failed: Dictionary=Routes._prepare_detached051(worker,late_land,owner,request,proof_budget051(2900),{},true)
	check(failed.status=="blocked" and not failed.has("staticComplete051"),"land failure in the remaining exit AFTER old traffic blocks cannot lend static completion")
	var exhausted_budget: Dictionary=proof_budget051(2900)
	exhausted_budget.fullRoutes=4
	var exhausted_worker: Dictionary=proof_state051([owner,blocker])
	exhausted_worker.time=0.0
	var exhausted: Dictionary=Routes._prepare_detached051(exhausted_worker,late_land,owner,request,exhausted_budget,{},true)
	check(exhausted.status=="pending" and not exhausted.has("staticComplete051") and exhausted_budget.fullRoutes==4 and exhausted_budget.exhaustions>0,"the existing four-search worker cap also refuses later static completion")
	var detour: Dictionary={"key":"complete-detour051","revision":58,"obstacles":[{"points":[[500,750],[600,750],[600,850],[500,850]],"lo":Vector2(500,750),"hi":Vector2(600,850)}]}
	var detour_worker: Dictionary=proof_state051([owner,blocker])
	detour_worker.time=0.0
	var detour_budget: Dictionary=proof_budget051(2900)
	var detour_packet: Dictionary=Routes._prepare_detached051(detour_worker,detour,owner,request,detour_budget,{},true)
	var detour_clear: Dictionary=proof_state051([owner])
	detour_clear.time=0.0
	var detour_reference: Dictionary=Routes._prepare_detached051(detour_clear,detour,owner,request,proof_budget051(2900))
	check(detour_packet.status=="blocked" and detour_packet.has("staticComplete051") and detour_packet.candidate==detour_reference.candidate and detour_packet.eta==detour_reference.eta and detour_budget.fullRoutes>0,"traffic-blocked worker finishes the SAME full static A-star detour and ETA as the clear snapshot")
	var detour_main_budget: Dictionary=proof_budget051(4096)
	var detour_adopted: Dictionary=Routes._adopt_prepared051(current,detour,owner,request,detour_packet,detour_main_budget,null,2.0)
	check(detour_adopted.status=="valid" and detour_adopted.eta==detour_reference.eta and detour_main_budget.fullRoutes==0,"main reuse checks its fresh connector without repeating worker A-star or future static legs")
	var oversized: Dictionary=request.duplicate(true)
	oversized.exit=[]
	for i: int in range(9):oversized.exit.append(Vector2(1200,960))
	var unbounded: Dictionary=Routes._prepare_detached051(worker,geometry,owner,oversized,proof_budget051(2900),{},true)
	check(unbounded.status=="blocked" and not unbounded.has("staticComplete051"),"worker completion preserves the existing eight-point bound on every routed leg")
	check(var_to_bytes([geometry,owner,blocker,request])==held,"worker completion and all current/fallback paths preserve source geometry, hulls and request inputs")

func egress_budget051(limit: int=4096) -> Dictionary:
	var budget: Dictionary=proof_budget051(limit)
	budget.separatingEgress051=true
	return budget

func padding_egress051(world: Dictionary) -> void:
	# EXACT R16 endBoatMotion051 binary positions/velocities, job d7551b6f.
	# All thirteen resolved 26/27m contacts, including the -9.4e-5m roundoff.
	# The player-2 case also retains its third, padding-only player-9 neighbor.
	var contacts: Array=[
		["enemy-14-bilge_punt","bilge_punt",Vector2(1342.71118164063,677.167053222656),Vector2(-3.31222852964497e-12,4.35917645838675e-14),"enemy-8-bilge_punt","bilge_punt",Vector2(1328.28125,698.795227050781),Vector2(-1.09413568519998e-16,3.76436364098062e-17)],
		["enemy-15-tin_skiff","tin_skiff",Vector2(1336.36877441406,724.555480957031),Vector2(-7.35727559604549e-13,2.60965619773568e-13),"enemy-8-bilge_punt","bilge_punt",Vector2(1328.28125,698.795227050781),Vector2(-1.09413568519998e-16,3.76436364098062e-17)],
		["enemy-16-tin_skiff","tin_skiff",Vector2(1275.60095214844,781.056396484375),Vector2(-1.04687978819129e-06,-2.9610541787406e-06),"enemy-2-bilge_punt","bilge_punt",Vector2(1291.59985351563,759.307067871094),Vector2(0.0,0.0)],
		["enemy-17-tin_skiff","tin_skiff",Vector2(1404.79992675781,849.729797363281),Vector2(-4.34420203025702e-17,1.32339881739808e-17),"enemy-3-bilge_punt","bilge_punt",Vector2(1377.80004882813,849.768676757813),Vector2(0.001701032044366,-0.000314727454679087)],
		["enemy-19-tin_skiff","tin_skiff",Vector2(1301.3076171875,1013.95440673828),Vector2(-6.24666681567549e-15,-9.36724842522585e-15),"enemy-5-bilge_punt","bilge_punt",Vector2(1289.78149414063,989.538208007813),Vector2(0.0,0.0)],
		["enemy-2-bilge_punt","bilge_punt",Vector2(1291.59985351563,759.307067871094),Vector2(0.0,0.0),"enemy-9-bilge_punt","bilge_punt",Vector2(1298.56079101563,734.256164550781),Vector2(-3.35618805899387e-17,-1.27592692204366e-17)],
		["enemy-4-bilge_punt","bilge_punt",Vector2(1295.83251953125,915.571594238281),Vector2(0.0,0.0),"enemy-6-bilge_punt","bilge_punt",Vector2(1270.97802734375,907.93896484375),Vector2(1.92907191376435e-06,2.35772674272994e-07)],
		["player-1-bilge_punt","bilge_punt",Vector2(958.461120605469,605.418273925781),Vector2(-8.75024792207357e-12,6.63040423346667e-13),"player-14-bilge_punt","bilge_punt",Vector2(935.976867675781,592.362243652344),Vector2(5.92037053062655e-12,-4.72820697525189e-12)],
		["player-10-bilge_punt","bilge_punt",Vector2(917.75,834.2890625),Vector2(0.0,0.0),"player-3-bilge_punt","bilge_punt",Vector2(937.655578613281,851.015258789063),Vector2(-6.06461938446046e-08,-1.53820032267049e-08)],
		["player-12-bilge_punt","bilge_punt",Vector2(979.892028808594,1004.52996826172),Vector2(5.17485216917134e-17,2.51762262879803e-17),"player-5-bilge_punt","bilge_punt",Vector2(1001.01977539063,989.376770019531),Vector2(0.0,0.0)],
		["player-13-bilge_punt","bilge_punt",Vector2(986.298828125,1081.2626953125),Vector2(2.42314454077406e-18,1.15580075495899e-18),"player-19-tin_skiff","tin_skiff",Vector2(961.624328613281,1070.30053710938),Vector2(3.54223757530886e-15,2.77722663998546e-15)],
		["player-2-bilge_punt","bilge_punt",Vector2(1000.03430175781,762.109558105469),Vector2(0.0,0.0),"player-15-tin_skiff","tin_skiff",Vector2(993.778442382813,735.844299316406),Vector2(3.00875969104497e-13,-6.68978286937245e-14)],
		["player-18-tin_skiff","tin_skiff",Vector2(1001.94848632813,956.336853027344),Vector2(3.63225041136086e-14,-3.58656831515283e-15),"player-6-bilge_punt","bilge_punt",Vector2(1028.45715332031,961.464294433594),Vector2(-2.37335854080811e-07,-1.16917782122528e-07)]
	]
	var specs: Dictionary={}
	for spec: Dictionary in world.HULLS:specs[str(spec.id)]=spec
	var geometry: Dictionary={"key":"padding-egress051","revision":59,"obstacles":[]}
	for sample: Array in contacts:
		var origin: Vector2=sample[2]
		var velocity: Vector2=sample[3]
		var other_origin: Vector2=sample[6]
		var other_velocity: Vector2=sample[7]
		var team: String=str(sample[0]).get_slice("-",0)
		var owner: Dictionary=Damage.create_ship(specs[sample[1]],{"id":sample[0],"team":team,"x":origin.x,"y":origin.y,"vx":velocity.x,"vy":velocity.y,"fuel":100.0,"order":"engage","orderTarget":{}})
		owner.status=Damage.get_status(owner)
		var friend: Dictionary=Damage.create_ship(specs[sample[5]],{"id":sample[4],"team":team,"x":other_origin.x,"y":other_origin.y,"vx":other_velocity.x,"vy":other_velocity.y})
		var ships: Array=[owner,friend]
		var outward: Vector2=(origin-other_origin).normalized()
		if str(owner.id)=="player-2-bilge_punt":
			ships.append(Damage.create_ship(specs.bilge_punt,{"id":"player-9-bilge_punt","team":"player","x":976.313842773438,"y":784.154052734375,"vx":5.45179273456246e-18,"vy":2.74511466804298e-18}))
			outward=Vector2.RIGHT # Separates from BOTH actual neighbors.
		owner.angle=outward.angle()
		var st: Dictionary=proof_state051(ships)
		st.time=0.0;st.tactical.geometry=geometry;st.tactical.dt=1.0/60.0
		var end: Vector2=origin+outward*160.0
		var request: Dictionary={"shipId":owner.id,"approach":[origin,end],"pass":[],"exit":[]}
		var label: String=str(owner.id)
		var public_budget: Dictionary=proof_budget051(2900)
		check(Routes._prepare_detached051(st,geometry,owner,request,public_budget).status=="blocked" and not public_budget.has("separatingEgress051"),label+": unchanged public/default padding refusal")
		var prepared: Dictionary=Routes._prepare_detached051(st,geometry,owner,request,egress_budget051(2900),{},true)
		check(prepared.status=="valid" and prepared.trafficSeconds051==2.0,label+": exact captured contact escapes through the full worker forecast")
		var adopted: Dictionary=Routes._adopt_prepared051(st,geometry,owner,request,prepared,egress_budget051(),null,0.3)
		check(adopted.status=="valid" and adopted.eta==prepared.eta,label+": current connector/traffic retains the complete route ETA")
		var control: Dictionary={"angle":outward.angle(),"throttle":0.5}
		check(not Certification.safe_step(st,owner,control,egress_budget051()).get("blocked",false),label+": actual float32 60Hz outward motion clears the unchanged physical floor")
		check(Certification.safe_step(st,owner,control,proof_budget051(4096)).get("blocked",false),label+": default live-step reference still refuses its planning padding")
		var turning: Dictionary=owner.duplicate(true)
		turning.angle=wrapf(outward.angle()+PI,-PI,PI)
		check(Certification.safe_step(st,turning,control,egress_budget051()).get("blocked",false),label+": actual limited turn still points inward and must brake")
		var inward: Dictionary=request.duplicate(true)
		inward.approach[1]=origin-outward*40.0
		check(Routes._prepare_detached051(st,geometry,owner,inward,egress_budget051()).status=="blocked",label+": deferred zero-time origin cannot authorize its next inward leg")
		var proofs: Routes._BeginProofs051=Routes._begin_proofs051(geometry,st.tactical.cells,{str(owner.id):owner})
		var radius: float=Battle._radius(owner)+4.0
		check(Routes._occupied_begin051(proofs,st.tactical.cells,owner,origin,end,radius,0.0,1.0,proof_budget051(4096),true)=="blocked",label+": first store the independent default refusal")
		var direct_budget: Dictionary=egress_budget051()
		var memo_budget: Dictionary=egress_budget051()
		var direct: String=Routes.occupied(st.tactical.cells,owner,origin,end,radius,0.0,1.0,direct_budget,true)
		check(Routes._occupied_begin051(proofs,st.tactical.cells,owner,origin,end,radius,0.0,1.0,memo_budget,true)==direct and direct=="valid" and memo_budget==direct_budget,label+": egress key cannot borrow default refusal; numeric/debit parity")
		var warm_budget: Dictionary=egress_budget051()
		check(Routes._occupied_begin051(proofs,st.tactical.cells,owner,origin,end,radius,0.0,1.0,warm_budget,true)==direct and warm_budget==direct_budget,label+": warm exact proof replays every neighbor debit")
		var pending_budget: Dictionary=egress_budget051(0)
		check(Routes._occupied_begin051(proofs,st.tactical.cells,owner,origin,end,radius,0.0,1.0,pending_budget,true)=="pending" and pending_budget.clearanceTests==0 and pending_budget.exhaustions==1,label+": warm proof cannot bypass a pending debit")
		if ships.size()==3:
			var partial_budget: Dictionary=egress_budget051(1)
			check(Routes._occupied_begin051(proofs,st.tactical.cells,owner,origin,end,radius,0.0,1.0,partial_budget,true)=="pending" and partial_budget.clearanceTests==1 and partial_budget.exhaustions==1,"actual three-boat escape still debits BOTH neighbors; partial work is pending")
		check(Routes._prepare_detached051(st,geometry,owner,request,egress_budget051(0),{},true).status=="pending",label+": worker budget exhaustion remains pending")
		var changed: Dictionary=friend.duplicate(true)
		changed.vx=outward.x*240.0;changed.vy=outward.y*240.0
		var current: Dictionary=proof_state051([owner,changed])
		current.time=0.05
		check(Routes._adopt_prepared051(current,geometry,owner,request,prepared,egress_budget051(),proofs,0.3).status=="blocked",label+": changed current traffic vetoes the old worker escape and old begin scope")
		Routes._close_begin_proofs051(proofs)
	# Independent analytic cases separate padding from genuine hull penetration,
	# ordinary entry/crossing, nonseparating tangent co-motion and swept curvature.
	var owner: Dictionary=Damage.create_ship(specs.bilge_punt,{"id":"egress-own051","team":"player","x":400.0,"y":800.0,"fuel":100.0,"order":"engage","orderTarget":{}})
	owner.status=Damage.get_status(owner)
	var friend: Dictionary=owner.duplicate(true)
	friend.id="egress-other051";friend.x=374.0
	var cases: Array=[
		{"name":"outward contact","end":Vector2(420,800),"status":"valid"},
		{"name":"inward contact","end":Vector2(380,800),"status":"blocked"},
		{"name":"cross through hull","end":Vector2(340,800),"status":"blocked"},
		{"name":"stationary padding","end":Vector2(400,800),"status":"blocked"},
		{"name":"nonseparating tangent co-motion","end":Vector2(400,810),"vy":10.0,"status":"blocked"},
		{"name":"straight tangent strictly separates","end":Vector2(400,810),"status":"valid"},
		{"name":"closing relative velocity","end":Vector2(420,800),"vx":30.0,"status":"blocked"},
		{"name":"true hull overlap","x":374.001,"end":Vector2(420,800),"status":"blocked"},
		{"name":"penetration just beyond contact precision","x":374.0002,"end":Vector2(420,800),"status":"blocked"},
		{"name":"outside padding inward entry","start":Vector2(420,800),"end":Vector2(400,800),"status":"blocked"},
		{"name":"outside padding crossing","start":Vector2(420,800),"end":Vector2(340,800),"status":"blocked"},
		{"name":"ordinary clear outside segment","start":Vector2(450,800),"end":Vector2(470,800),"status":"valid"},
		{"name":"single initial origin knot","end":Vector2(400,800),"until":0.0,"status":"valid"},
		{"name":"later zero-time station","end":Vector2(400,800),"from":0.1,"until":0.1,"status":"blocked"},
		{"name":"curved capsule retains deviation","end":Vector2(420,800),"deviation":2.0,"status":"blocked"},
		{"name":"hostile padding outward","end":Vector2(420,800),"team":"enemy","status":"valid"},
		{"name":"hostile inward","end":Vector2(380,800),"team":"enemy","status":"blocked"},
		{"name":"hostile true hull overlap","x":374.001,"end":Vector2(420,800),"team":"enemy","status":"blocked"}
	]
	for trial: Dictionary in cases:
		var other: Dictionary=friend.duplicate(true)
		other.x=trial.get("x",374.0);other.vx=trial.get("vx",0.0);other.vy=trial.get("vy",0.0);other.team=trial.get("team","player")
		var cells: Dictionary=Routes.grid([owner,other],true)
		var a: Vector2=trial.get("start",Vector2(400,800))
		var r: float=Battle._radius(owner)+4.0+float(trial.get("deviation",0.0))
		var work: Dictionary=egress_budget051()
		check(Routes.occupied(cells,owner,a,trial.end,r,float(trial.get("from",0.0)),float(trial.get("until",1.0)),work,true)==trial.status and work.clearanceTests==1,str(trial.name)+": exact safety predicate and ordered debit")
	var state: Dictionary=proof_state051([owner,friend])
	state.tactical.geometry=geometry;state.tactical.dt=1.0/60.0
	var drifting: Dictionary=owner.duplicate(true)
	drifting.vx=-10.0
	check(Certification.safe_step(state,drifting,{"angle":0.0,"throttle":0.5},egress_budget051()).get("blocked",false),"outward requested steering cannot excuse actual inward braking drift")
	var pending: Dictionary=egress_budget051(0)
	check(Certification.safe_step(state,owner,{"angle":0.0,"throttle":0.5},pending).get("blocked",false) and pending.exhaustions==1,"live 60Hz step cannot turn a budget refusal into clearance")

func crowd_escape051(world: Dictionary) -> void:
	# Exact R17 endBoatMotion051, job102dae18; headings were NOT captured.
	# These five hulls contain enemy-9's 23.60..27.02 degree cone and enemy-17's
	# empty cone. Only the turn/drift input below is a controlled fixture input.
	var samples: Array=[
		["enemy-9-bilge_punt","bilge_punt",Vector2(1367.20446777344,761.511779785156),Vector2.ZERO],
		["enemy-3-bilge_punt","bilge_punt",Vector2(1341.17980957031,762.465942382813),Vector2(9.27106066228589e-6,-3.91227922591497e-6)],
		["enemy-16-tin_skiff","tin_skiff",Vector2(1378.01574707031,736.770812988281),Vector2(-5.46002892692302e-14,-2.70252655025722e-14)],
		["enemy-17-tin_skiff","tin_skiff",Vector2(1354.8447265625,785.752563476563),Vector2(-7.5797573377339e-15,-5.4255183482563e-15)],
		["enemy-4-bilge_punt","bilge_punt",Vector2(1348.86999511719,812.083190917969),Vector2(0.000448718055849895,-0.000187288242159411)]
	]
	var ships: Array=[]
	var context: Dictionary={}
	for sample: Array in samples:
		var boat: Dictionary=Damage.create_ship(Lab.hull(world,sample[1]),{"id":sample[0],"team":"enemy","x":sample[2].x,"y":sample[2].y,"vx":sample[3].x,"vy":sample[3].y,"fuel":120.0,"order":"engage","orderRevision":0,"orderTarget":{},"mounts":[]})
		boat.status=Damage.get_status(boat)
		ships.append(boat);context[str(boat.id)]=boat
	var owner: Dictionary=ships[0]
	var view: Dictionary={"time":0.0,"snapshotRevision":1,"ships":ships,"options":{"byId":{}}}
	var state: Dictionary={"role":"skirmisher","phase":"regroup","targetId":"","leaderId":""}
	var decision: Dictionary={"state":state}
	var before: PackedByteArray=var_to_bytes([view,state])
	var reference: Array=Stations.candidates(view,owner,decision,context)
	var offers: Array=Stations._candidates_crowd051(view,owner,decision,context)
	check(offers.size()<=8 and not offers.is_empty() and Routes._is_crowd_escape051(offers[-1]),"R17 narrow cone supplies exactly one final owned nonfiring terminal fallback within eight offers")
	if offers.is_empty() or not Routes._is_crowd_escape051(offers[-1]):return
	var request: Dictionary=offers[-1]
	check(offers.slice(0,offers.size()-1)==reference.slice(0,mini(reference.size(),7)),"owned fallback preserves the first seven normal alternatives and public generation")
	var origin: Vector2=Routes.point(owner)
	var delta: Vector2=request.approach[-1]-origin
	check(rad_to_deg(delta.angle())>23.60 and rad_to_deg(delta.angle())<27.03,"actual enemy-9 escape lies inside the captured narrow cone, without angular sampling")
	for other: Dictionary in [ships[1],ships[2],ships[3]]:
		var relative: Vector2=origin-Routes.point(other)
		var moving_delta: Vector2=delta-Vector2(other.vx,other.vy)*delta.length()/(Roles.speed(owner)*0.8)
		check(relative.dot(moving_delta)>=0.0 and (relative+moving_delta).length_squared()>relative.length_squared(),"R17 departure separates from EACH current contact including its actual velocity")
	check(Stations._crowd_escape051(view,ships[3],state,context).is_empty(),"actual enemy-17 empty intersection supplies no escape authority")
	var overlap: Dictionary=owner.duplicate(true)
	overlap.x=ships[1].x;overlap.y=ships[1].y
	check(Stations._crowd_escape051(view,overlap,state,context).is_empty(),"true physical penetration supplies no crowd candidate")
	check(Stations.valid_candidate(request) and not Stations.fingerprint(request).is_empty(),"owned terminal flag has a bounded valid schema and fingerprint")
	var unmarked: Dictionary=request.duplicate(true)
	unmarked.erase("crowdEscape051")
	check(Stations.valid_candidate(unmarked) and Stations.fingerprint(unmarked)!=Stations.fingerprint(request) and not Stations.same_request(request,unmarked),"removing the owned alignment flag changes fingerprint and request identity")
	var reminted: Dictionary=request.duplicate(true)
	reminted.candidateId="joined-current-crowd051";reminted.snapshotRevision=2
	check(Stations.valid_candidate(reminted) and Routes._is_crowd_escape051(reminted),"worker request-ID remint retains the fingerprinted optional policy flag")
	var firing: Dictionary=request.duplicate(true)
	firing.fireMountIds=["mount0"]
	check(not Stations.valid_candidate(firing),"crowd alignment flag cannot be attached to a firing request")
	var geometry: Dictionary={"key":"crowd051","revision":61,"obstacles":[]}
	var st: Dictionary=proof_state051(ships)
	st.time=0.0;st.tactical.geometry=geometry;st.tactical.dt=1.0/60.0
	var prepared: Dictionary=Routes._prepare_detached051(st,geometry,owner,request,egress_budget051(2900),{},true)
	check(prepared.status=="valid" and prepared.trafficSeconds051==2.0,"R17 crowd request still passes full worker static route and two-second snapshot traffic")
	var adopted: Dictionary=Routes._adopt_prepared051(st,geometry,owner,request,prepared,egress_budget051(),null,0.3)
	check(adopted.status=="valid" and Stations.same_request(request,adopted.candidate),"fresh main connector/current traffic preserves exact owned request identity")
	var turning: Dictionary=owner.duplicate(true)
	turning.angle=wrapf(delta.angle()+PI,-PI,PI)
	var control: Dictionary={"angle":delta.angle(),"throttle":0.5,"index":1}
	check(Certification.safe_step(st,turning,control,egress_budget051()).get("blocked",false),"unchanged reference moving turn points inward and brakes")
	var alignment: Dictionary=Certification._crowd_step051(st,turning,request,control,egress_budget051())
	check(not alignment.get("blocked",false) and alignment.throttle==0.0 and alignment.angle==control.angle,"owned escape preserves the requested heading with checked zero throttle")
	var next: Dictionary=Certification.motion(turning,1.0/60.0,float(alignment.angle),float(alignment.throttle))
	check(Routes.point(next)==origin and absf(angle_difference(float(turning.angle),float(next.angle)))>0.01,"actual integrated stationary alignment changes heading without moving the circular hull")
	check(Certification._crowd_step051(st,turning,unmarked,control,egress_budget051()).get("blocked",false),"unmarked public request cannot borrow equality-only alignment")
	var drifting: Dictionary=turning.duplicate(true)
	drifting.vx=-delta.normalized().x*10.0;drifting.vy=-delta.normalized().y*10.0
	check(Certification._crowd_step051(st,drifting,request,control,egress_budget051()).get("blocked",false),"requested zero throttle cannot excuse actual inward residual drift against any contact")
	var pending: Dictionary=egress_budget051(1)
	var pending_step: Dictionary=Certification._crowd_step051(st,turning,request,control,pending)
	check(pending_step.get("blocked",false) and pending_step.reason=="Braking; checking clearance" and pending.clearanceTests==1 and pending.exhaustions==1,"alignment still debits the land sweep then keeps neighbor-budget refusal pending")
	var departed: Dictionary=turning.duplicate(true)
	departed.angle=control.angle
	check(not Certification._crowd_step051(st,departed,request,control,egress_budget051()).get("blocked",false),"aligned departure still passes strict ordinary current physical/traffic clearance")
	var stationary: Dictionary={"angle":control.angle,"throttle":0.0}
	check(Certification._crowd_step051(st,departed,request,stationary,egress_budget051()).get("blocked",false),"completed nonturning hold cannot borrow alignment equality inside padding")
	check(var_to_bytes([view,state])==before,"crowd generation, preparation and checked alignment preserve captured inputs")

func reservation_path051(ship: Dictionary, path: Array, now: float, seconds: float=2.0) -> Dictionary:
	var goal: Vector2=path[-1] if not path.is_empty() else Roles.pos(ship)
	var candidate: Dictionary=Stations._candidate({"snapshotRevision":1},ship,{"role":"skirmisher"},"",-1,path,[goal],[goal],[],0)
	return Stations._reservation_begin051(candidate,ship,now,seconds)

func reservation_egress051(world: Dictionary) -> void:
	# R18 jobc32b538e endBoatMotion051: exact Ash/Tin poses, velocities/headings.
	# Equipment is healthy fixture input, NOT a reconstruction of unseen damage.
	# The live Tin terminal reservation is controlled; R18 saved no final prefix.
	var samples: Array=[
		["enemy-1-ash_corvette","ash_corvette",Vector2(1668.71557617188,756.889465332031),Vector2(4.14731912314892e-5,2.61469886027044e-5),0.545971393585205],
		["enemy-0-tin_skiff","tin_skiff",Vector2(1639.35205078125,737.838256835938),Vector2(1.97076906260918e-6,1.28188526105077e-6),0.426796057743496]
	]
	var ships: Array=[]
	var context: Dictionary={}
	for sample: Array in samples:
		var boat: Dictionary=Damage.create_ship(Lab.hull(world,sample[1]),{"id":sample[0],"team":"enemy","x":sample[2].x,"y":sample[2].y,"vx":sample[3].x,"vy":sample[3].y,"angle":sample[4],"fuel":120.0,"order":"engage","orderRevision":0,"orderTarget":{},"mounts":[]})
		boat.status=Damage.get_status(boat)
		ships.append(boat);context[str(boat.id)]=boat
	var ash: Dictionary=ships[0]
	var tin: Dictionary=ships[1]
	var now: float=12.0166666666668
	var distance: float=Roles.pos(ash).distance_to(Roles.pos(tin))
	check(absf(distance-35.002359)<0.00001 and distance>Roles.radius(ash)+Roles.radius(tin) and distance<42.0,"actual R18 Ash/Tin are outside physical hulls but inside reservation padding")
	var tin_reservation: Dictionary=reservation_path051(tin,[Roles.pos(tin)],now)
	var memory: Dictionary={"byId":{},"reservations":{str(tin.id):tin_reservation}}
	var view: Dictionary={"time":now,"snapshotRevision":1,"terrainRevision":73,"dt":1.0/60.0,"side":"enemy","dueIds":[str(ash.id)],"ships":ships,"options":{"byId":{}}}
	var original: PackedByteArray=var_to_bytes([ships,memory,view])
	var planned: Dictionary=Planner._prepare_begin(view,memory)
	check(not planned.candidates.is_empty() and planned.candidates.size()<=8 and Routes._is_crowd_escape051(planned.candidates[-1]),"actual Ash generation reaches the final bounded crowd offer with a LIVE Tin reservation")
	if planned.candidates.is_empty() or not Routes._is_crowd_escape051(planned.candidates[-1]):return
	var request: Dictionary=planned.candidates[-1]
	var heading: float=(request.approach[-1]-Roles.pos(ash)).angle()
	check(absf(rad_to_deg(heading)-61.488)<0.01 and absf(float(ash.angle)-0.545971393585205)<0.000001,"captured Ash heading differs from the generated 61.488 degree separating request")
	var st: Dictionary={"time":now,"ships":ships,"islands":[]}
	var t: Dictionary=Tactical.ensure(st)
	t.ships=context;t.observed=context;t.cells=Routes.grid(ships,true)
	t.snapshotRevision=1;t.terrainRevision=73;t.dt=1.0/60.0
	t.geometry={"key":"reservation-egress051","revision":73,"obstacles":[]}
	t.metrics={"planningDetailUs":{},"orderApplyAges":[],"certificateAges":[]}
	t.mountCache[str(ash.id)]={"mounts":[],"baseMounts":[]}
	t.budget=egress_budget051()
	var refined: Dictionary=Routes._refine_begin051(st,t.geometry,ash,request,t.budget,null,2.0)
	check(refined.status=="valid","actual Ash escape passes fresh land and full current traffic refinement")
	if refined.status!="valid":return
	t.memory.enemy=memory
	check(Tactical._reserved_path(st,"enemy",ash,refined.candidate)=="valid" and t.memory.enemy.reservations.has(str(tin.id)),"actual Runtime pre-certification reservation gate admits the checked escape without clearing live Tin")
	var shape: Dictionary=Stations._reservation_begin051(refined.candidate,ash,now,2.0)
	var counters: Dictionary={"clearanceTests":0,"clearanceExhausted":0}
	check(not Stations._conflict_begin051(shape,tin_reservation,counters,4096) and counters.clearanceTests>=2,"synchronized whole prefix releases the actual Ash padding trap while retaining LIVE Tin reservation")
	var public_counters: Dictionary={"clearanceTests":0,"clearanceExhausted":0}
	check(Stations.conflict(shape,tin_reservation,public_counters,4096),"public/default reservation conflict still refuses the original padded capsule")
	var legacy: Dictionary=tin_reservation.duplicate(true)
	legacy.erase("speed051")
	check(Stations._conflict_begin051(shape,legacy,{"clearanceTests":0,"clearanceExhausted":0},4096),"untimed legacy reservation cannot borrow the private separating proof")
	for limit: int in [0,1]:
		var pending: Dictionary={"clearanceTests":0,"clearanceExhausted":0}
		check(Stations._conflict_begin051(shape,tin_reservation,pending,limit) and pending.clearanceTests==limit and pending.clearanceExhausted==1,"reservation debit exhaustion stays pending before any unchecked prefix can pass")
	var fingerprint: String=Stations.fingerprint(refined.candidate)
	var certificate: Dictionary=Certification._certify_refined_live(st,view,ash,refined,fingerprint,t.budget)
	check(certificate.status=="valid","same actual refined escape receives a fresh live certificate")
	var offer: Dictionary={"candidate":refined.candidate,"certificate":certificate}
	var resolved: Dictionary=Planner._resolve_planned(view,memory,[offer],planned,2.0)
	check(resolved.counters.accepted==1 and resolved.byId[str(ash.id)].candidateId==request.candidateId and resolved.memory.reservations.has(str(tin.id)),"real resolution admits Ash and preserves Tin's still-live reservation")
	var pending_view: Dictionary=view.duplicate(true)
	pending_view.options.clearanceRemaining=1
	var pending_result: Dictionary=Planner._resolve_planned(pending_view,memory,[offer],planned.duplicate(true),2.0)
	check(pending_result.counters.accepted==0 and pending_result.counters.clearanceExhausted==1 and pending_result.byId[str(ash.id)].phase=="pending","real resolution cannot turn a partial reservation proof into movement authority")
	check(var_to_bytes([ships,memory,view])==original,"generation through certification and resolution preserves captured inputs and live reservation")
	t.intents=resolved.byId;t.memory.enemy=resolved.memory
	var helm: Dictionary=Tactical.helm(st,ash)
	var next: Dictionary=Certification.motion(ash,t.dt,float(helm.angle),float(helm.throttle))
	check(not helm.get("blocked",false) and helm.throttle==0.0 and absf(angle_difference(float(ash.angle),float(next.angle)))>0.001 and t.memory.enemy.reservations.has(str(tin.id)),"actual helm checks alignment from captured heading without revoking LIVE Tin reservation")
	var radial: Vector2=(Roles.pos(ash)-Roles.pos(tin)).normalized()
	tin.vx=radial.x*20.0;tin.vy=radial.y*20.0
	t.cells=Routes.grid(ships,true)
	check(Certification._crowd_step051(st,ash,refined.candidate,{"angle":heading,"throttle":0.5},egress_budget051()).get("blocked",false),"changed Tin traffic approaching the physical hull still refuses actual integrated alignment/drift")
	# Bounded analytic pieces isolate later turns, crossings, arrival holds and
	# absolute clocks; no P16 diagnosis, new observer or rollout harness.
	var a: Dictionary=ash.duplicate(true)
	var b: Dictionary=tin.duplicate(true)
	a.spec=a.spec.duplicate(true);b.spec=b.spec.duplicate(true)
	a.spec.speed=25.0;b.spec.speed=25.0;a.status.speedFactor=1.0;b.status.speedFactor=1.0
	a.x=535.00236;a.y=800.0;b.x=500.0;b.y=800.0
	var origin: Vector2=Roles.pos(a)
	var hold: Dictionary=reservation_path051(b,[Roles.pos(b)],now)
	for path: Array in [[origin-Vector2(5,0)],[origin-Vector2(80,0)],[origin],[origin+Vector2(10,0),origin+Vector2(5,0),origin+Vector2(15,0)]]:
		check(Stations._conflict_begin051(reservation_path051(a,path,now),hold,{"clearanceTests":0,"clearanceExhausted":0},4096),"inward, crossing, stationary and outward-then-inward prefixes remain refused despite endpoint separation")
	var outward: Dictionary=reservation_path051(a,[origin+Vector2(15,0)],now)
	check(not Stations._conflict_begin051(outward,hold,{"clearanceTests":0,"clearanceExhausted":0},4096),"outward departure followed by a terminal arrival hold preserves a strict prefix gain")
	var reversed_leg: Dictionary=outward.duplicate(true)
	reversed_leg.approach=[origin+Vector2(10,0)];reversed_leg["pass"]=[origin+Vector2(5,0)];reversed_leg.exit=[origin+Vector2(15,0)]
	check(Stations._conflict_begin051(reversed_leg,hold,{"clearanceTests":0,"clearanceExhausted":0},4096),"moving pass/exit legs cannot hide an inward middle piece behind a farther final endpoint")
	var following: Dictionary=reservation_path051(b,[Roles.pos(b)+Vector2(30,0)],now)
	check(Stations._conflict_begin051(outward,following,{"clearanceTests":0,"clearanceExhausted":0},4096),"actual arrival piece keeps a follower from approaching after the escaping boat stops")
	a.x=534.9
	check(Stations._conflict_begin051(reservation_path051(a,[Roles.pos(a)+Vector2(15,0)],now),hold,{"clearanceTests":0,"clearanceExhausted":0},4096),"genuine physical penetration grants no reservation egress")
	a.x=545.0
	check(Stations._conflict_begin051(reservation_path051(a,[Vector2(485,800)],now),hold,{"clearanceTests":0,"clearanceExhausted":0},4096),"ordinary crossing from outside padding retains original capsule refusal")
	a.x=origin.x;b.x=510.0
	var earlier: Dictionary=reservation_path051(b,[Vector2(500,800)],now-0.5)
	check(not Stations._conflict_begin051(outward,earlier,{"clearanceTests":0,"clearanceExhausted":0},4096),"older live reservation is evaluated at the shared absolute start after its actual arrival")
	b.x=500.0
	var corners_a: Dictionary=reservation_path051(a,[origin+Vector2(10,0),origin+Vector2(10,20)],now)
	var corners_b: Dictionary=reservation_path051(b,[Vector2(500,820),Vector2(480,820)],now)
	var merged: Dictionary={"clearanceTests":0,"clearanceExhausted":0}
	check(not Stations._conflict_begin051(corners_a,corners_b,merged,4096) and merged.clearanceTests==5,"different arrival clocks merge into four charged relative pieces including the terminal hold")
	var partial: Dictionary={"clearanceTests":0,"clearanceExhausted":0}
	check(Stations._conflict_begin051(corners_a,corners_b,partial,4) and partial.clearanceTests==4 and partial.clearanceExhausted==1,"late piece exhaustion cannot reuse a partial monotonic proof")
