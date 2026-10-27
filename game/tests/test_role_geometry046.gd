extends SceneTree
## Narrow source contracts. Root owns native execution and six-scenario motion proof.
const Lab = preload("res://scripts/fleet_lab.gd")
const Battle = preload("res://scripts/battle.gd")
const Tactical = preload("res://scripts/tactical_runtime.gd")
const Roles = preload("res://scripts/tactical_role_plans.gd")
const Stations = preload("res://scripts/tactical_stations.gd")
const Routes = preload("res://scripts/tactical_routes.gd")
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
	solo_recovery051(view, context[friend_id])
	proof_reuse051()
	finite_traffic051()
	print("ROLE GEOMETRY046: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

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
