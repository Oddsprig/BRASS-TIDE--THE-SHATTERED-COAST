extends RefCounted
## Independent fixture support, not game runtime. Actual native physics and stores.
const B=preload("res://scripts/battle.gd")
const D=preload("res://scripts/damage.gd")
const Refit=preload("res://scripts/refit.gd")
const T=preload("res://scripts/tactical_runtime.gd")
const DT: float=1.0/30.0
const SPEC: Dictionary={"id":"skiff","name":"Skiff","role":"skiff","tier":1,"hp":150,"armor":1,"crewMin":2,"crewOptimal":5,"crewMax":7,"size":16,"speed":100,"turn":2,"pumps":1,"weapon":"gun","damage":12,"fireRate":2,"range":550}

static func config() -> Dictionary:
	var path: String=ProjectSettings.globalize_path("res://").path_join("../tools/tactical_scenarios.json").simplify_path()
	return JSON.parse_string(FileAccess.get_file_as_string(path))

static func world() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))

static func pos(ship: Dictionary) -> Vector2:
	return Vector2(float(ship.x),float(ship.y))

static func stock(data: Dictionary,id: String,uid: String) -> Dictionary:
	for raw in data.HULLS:
		if str(raw.id)!=id:continue
		var base: Dictionary=raw.duplicate(true)
		var ship: Dictionary=D.create_ship(base,{"uid":uid})
		ship.loadout=Refit.defaults(base)
		Refit.ensure(ship,base)
		ship.ammo=float(ship.spec.ammoCapacity)
		return ship
	return {}

static func roster(data: Dictionary,ids: Array,prefix: String) -> Array:
	var result: Array=[]
	for index in range(ids.size()):result.append(stock(data,str(ids[index]),prefix+str(index)))
	return result

static func load_roster(data: Dictionary,profile: Dictionary,prefix: String,extra: int=0) -> Array:
	var result: Array=[]
	for index in range(int(profile.per_side)+extra):
		if profile.has("hull"):result.append(stock(data,str(profile.hull),prefix+str(index)))
		else:
			var spec: Dictionary=SPEC.duplicate(true)
			spec.deploymentPoints=int(profile.synthetic_deployment_points)
			result.append(D.create_ship(spec,{"uid":prefix+str(index)}))
	return result

static func find(st: Dictionary,id: String) -> Dictionary:
	for ship in st.ships:
		if str(ship.id)==id:return ship
	return {}

static func live(ship: Dictionary) -> bool:
	return not ship.is_empty() and not ship.sunk and not ship.get("captureSecured",false)

static func command(st: Dictionary,ship: Dictionary,order: String,target: Dictionary={}) -> void:
	if ship.team=="player":B.issue_order(st,[ship.id],order,target)
	else:T.accept_command(st,ship,order,target)

static func rectangle(x1: float,y1: float,x2: float,y2: float) -> Dictionary:
	return {"points":[[x1,y1],[x2,y1],[x2,y2],[x1,y2]]}

static func create_case(definitions: Dictionary,scenario_id: String,variant_id: String,seed: int,orientation: String) -> Dictionary:
	var definition: Dictionary={}
	var variant: Dictionary={}
	for row in definitions.scenarios:
		if str(row.id)==scenario_id:definition=row.duplicate(true);break
	for row in definition.get("variants",[]):
		if str(row.id)==variant_id:variant=row.duplicate(true);break
	if definition.is_empty() or variant.is_empty():return {"error":"Unknown frozen scenario/variant"}
	var data: Dictionary=world()
	var actors: Array=roster(data,variant.get("actors",definition.actors),"case-actor-")
	var opponents: Array=roster(data,variant.get("opponents",definition.opponents),"case-opponent-")
	var swapped: bool=orientation=="teams_swapped"
	var options: Dictionary={"fleet":opponents if swapped else actors,"enemyFleet":actors if swapped else opponents,"seed":seed}
	var terrain: String=str(variant.get("terrain",""))
	if terrain=="central_island":options.islands=[rectangle(980,650,1180,1050)]
	if terrain=="trapped_actor":
		var x: float=1600.0 if swapped else 520.0
		options.islands=[rectangle(x-125,700,x-95,1000),rectangle(x+95,700,x+125,1000),rectangle(x-125,700,x+125,730),rectangle(x-125,970,x+125,1000)]
	var st: Dictionary=B.create(options)
	st.autoBoard=false
	if variant.get("opponent_stationary",false):
		for ship in opponents:ship.spec.speed=0.0
	if variant.has("actor_ammo"):
		for ship in actors:ship.ammo=float(variant.actor_ammo)
	if definition.has("actor_damage"):
		var damage: Dictionary=definition.actor_damage
		var ship: Dictionary=actors[0]
		ship.hp=float(ship.maxHp)*float(damage.hp_fraction);ship.water=float(ship.capacity)*float(damage.water_fraction)
		ship.fire=float(damage.fire);ship.breaches=[{"area":float(damage.breach_area),"section":"waterline"}]
		D.set_policy(ship,str(damage.policy))
	if definition.has("protect_opponent_index"):
		var leader: Dictionary=opponents[int(definition.protect_opponent_index)]
		for index in range(opponents.size()):
			if index!=int(definition.protect_opponent_index):command(st,opponents[index],"escort",{"shipId":str(leader.id)})
	if definition.has("protect_actor_index") or variant.has("protect_actor_index"):
		var leader_index: int=int(variant.get("protect_actor_index",definition.get("protect_actor_index",0)))
		for index in range(actors.size()):
			if index!=leader_index:command(st,actors[index],"escort",{"shipId":str(actors[leader_index].id)})
	if variant.get("actor_last_hold",false):command(st,actors[-1],"hold")
	if variant.get("opponent_withdraw",false):
		for ship in opponents:command(st,ship,"withdraw",{"x":2100.0 if ship.team=="enemy" else 200.0,"y":850.0})
	return {"state":st,"actors":actors,"opponents":opponents,"definition":definition,"variant":variant}

static func event_at(case: Dictionary,tick: int) -> Dictionary:
	var event: Dictionary=case.variant.get("event",{})
	if event.is_empty() or tick!=int(event.tick):return {}
	var st: Dictionary=case.state
	var result: Dictionary={"tick":tick,"kind":event.kind}
	if event.kind=="displace_screen":
		for index in range(1,case.opponents.size()):
			var ship: Dictionary=case.opponents[index]
			command(st,ship,"move",{"x":float(ship.x),"y":450.0})
	elif event.kind=="destroy_screen":
		for index in range(1,case.opponents.size()):D.apply_hit(case.opponents[index],{"damage":100000.0,"kind":"shell"},st.rng)
	elif event.kind=="destroy_actor_leader":D.apply_hit(case.actors[int(case.definition.protect_actor_index)],{"damage":100000.0,"kind":"shell"},st.rng)
	return result

static func point_segment(p: Vector2,a: Vector2,b: Vector2) -> float:
	var delta: Vector2=b-a
	return p.distance_to(a+delta*clampf((p-a).dot(delta)/maxf(0.000001,delta.length_squared()),0.0,1.0))

static func polygon(island: Dictionary) -> PackedVector2Array:
	var points: PackedVector2Array=[]
	for raw in island.points:points.append(raw if raw is Vector2 else Vector2(float(raw[0]),float(raw[1])))
	return points

static func ray_land(st: Dictionary,a: Vector2,b: Vector2,radius: float) -> bool:
	for island in st.islands:
		var points: PackedVector2Array=polygon(island)
		if Geometry2D.is_point_in_polygon(a,points) or Geometry2D.is_point_in_polygon(b,points):return true
		for index in range(points.size()):
			var p: Vector2=points[index];var q: Vector2=points[(index+1)%points.size()]
			if Geometry2D.segment_intersects_segment(a,b,p,q)!=null:return true
			if minf(minf(point_segment(p,a,b),point_segment(q,a,b)),minf(point_segment(a,p,q),point_segment(b,p,q)))<radius-0.0001:return true
	return false

static func snapshot(st: Dictionary) -> Dictionary:
	var boats: Array=[]
	for ship in st.ships:
		var id: String=str(ship.id)
		var intent: Dictionary=st.get("tactical",{}).get("intents",{}).get(id,{})
		var planner: Dictionary=st.get("tactical",{}).get("memory",{}).get(str(ship.team),{}).get("byId",{}).get(id,{})
		var separation: float=INF
		for other in st.ships:
			if str(other.id)!=id and live(other):separation=minf(separation,pos(ship).distance_to(pos(other)))
		boats.append({"id":id,"uid":str(ship.uid),"party":str(ship.team),"x":float(ship.x),"y":float(ship.y),"vx":float(ship.vx),"vy":float(ship.vy),"heading":float(ship.angle),"radius":maxf(10.0,float(ship.spec.size)),"order":str(ship.order),"order_revision":int(ship.get("orderRevision",0)),"target":str(intent.get("targetId","")),"role":str(intent.get("role","")),"phase":str(intent.get("phase","")),"intent_reason":str(st.get("tactical",{}).get("reasons",{}).get(id,"")),"approach":intent.get("waypoints",[]).duplicate(),"exit":intent.get("exit",[]).duplicate(),"separation":separation if is_finite(separation) else null,"condition":{"hp":float(ship.hp),"water":float(ship.water),"fire":float(ship.fire),"engine":float(ship.engine),"crew":float(ship.crew)},"stores":{"ammo":float(ship.ammo),"fuel":float(ship.fuel),"supplies":float(ship.supplies)},"mounts":B._mounts(ship).duplicate(true),"shots":ship.get("mountShotTimes",{}).duplicate(true),"withheld":st.get("tactical",{}).get("fireReasons",{}).get(id,{}).duplicate(true),"sunk":bool(ship.sunk),"secured":bool(ship.get("captureSecured",false))})
		var retained: Dictionary={}
		for key in ["phase","phaseSince","passSince","passOpportunitySince","sector","anchor","commitUntil","blockedStation","waitSince","passShots","passShortShots","reason"]:
			if planner.has(key):retained[key]=planner[key]
		boats[-1]["planner_memory"]=retained
	return {"sim_time":float(st.time),"result":st.result,"boats":boats,"work":st.get("tactical",{}).get("metrics",{}).get("work",{}).duplicate(true),"objective":st.get("mission",{}).get("status","")}

static func encode(value: Variant) -> Variant:
	if value is Vector2:return [value.x,value.y]
	if value is Dictionary:
		var result: Dictionary={}
		for key in value:result[str(key)]=encode(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value:result.append(encode(item))
		return result
	return value

static func opening(st: Dictionary) -> Dictionary:
	# Fixed <=0.2 s real-update contract. Does not drain or fabricate events,
	# alter cooldowns, replenish rounds, or invoke the private firing method.
	var start: float=float(st.time);var cursor: int=int(st.eventSeq)
	var events: Array=[];var effects: Dictionary={};var stamps: Dictionary={}
	var okay: bool=true
	for frame in range(6):
		var before: Dictionary={};var previous: Dictionary={}
		for ship in st.ships:
			before[str(ship.id)]=float(ship.ammo);previous[str(ship.id)]=ship.weaponCooldowns.duplicate()
		B.update(st,DT)
		var costs: Dictionary={};var emitted: Dictionary={}
		for event in st.events:
			if int(event.seq)<=cursor:continue
			cursor=maxi(cursor,int(event.seq))
			if str(event.kind)!="fire":continue
			events.append(event.duplicate(true))
			var ship: Dictionary=find(st,str(event.sourceId));var fitted: Array=B._mounts(ship)
			var index: int=int(event.mountIndex)
			if ship.is_empty() or index<0 or index>=fitted.size():okay=false;continue
			var mount: Dictionary=fitted[index];var key: String=str(ship.id)+"/"+str(mount.id)
			if stamps.has(key) or str(event.mountId)!=str(mount.id):okay=false
			if not is_equal_approx(B.mount_shot_time(ship,str(mount.id)),float(event.time)) or not is_equal_approx(B.mount_shot_time(ship,index),float(event.time)):okay=false
			if float(ship.weaponCooldowns[index])<1.0/float(mount.fireRate)-0.000001 or float(event.time)-start>0.2+0.000001:okay=false
			stamps[key]=float(event.time);emitted[key]=true
			costs[str(ship.id)]=float(costs.get(str(ship.id),0.0))+float(mount.ammoCost)
		for ship in st.ships:
			var id: String=str(ship.id)
			if not is_equal_approx(float(before[id])-float(ship.ammo),float(costs.get(id,0.0))):okay=false
			for index in range(ship.weaponCooldowns.size()):
				var mount: Dictionary=B._mounts(ship)[index];var key: String=id+"/"+str(mount.id)
				if not emitted.has(key) and not is_equal_approx(float(ship.weaponCooldowns[index]),maxf(0.0,float(previous[id][index])-DT)):okay=false
		for effect in st.effects:
			if effect.kind=="fire" and not effects.has(int(effect.seq)):effects[int(effect.seq)]=effect.duplicate(true)
	print("OBS opening "+JSON.stringify({"start":start,"end":st.time,"events":encode(events),"individualShotTimes":stamps,"accountingAndCooldownsValid":okay}))
	return {"ok":okay and float(st.time)-start<=0.2+0.000001,"events":events,"effects":effects.values(),"stamps":stamps}

static func run_case(definitions: Dictionary,scenario_id: String,variant_id: String,seed: int,orientation: String,ticks: int,process_started: int=0) -> Dictionary:
	var started: int=Time.get_ticks_usec() if process_started==0 else process_started
	var case: Dictionary=create_case(definitions,scenario_id,variant_id,seed,orientation)
	if case.has("error"):return {"status":"INVALID_FIXTURE","failures":[case.error]}
	var st: Dictionary=case.state
	var traces: Array=[snapshot(st)]
	var events: Array=[]
	var scripted_events: Array=[]
	var starts: Dictionary={};var previous: Dictionary={};var traveled: Dictionary={}
	var first_shot_pos: Dictionary={};var minimum_range: Dictionary={}
	var useful_actor_shots: int=0
	var enemy_shots: int=0
	var separated: bool=false
	var breakaway: bool=false
	var protective_motion: bool=false
	var survival_retreat: bool=false
	var physical_issues: Dictionary={}
	var minimum_ally_gap: float=INF
	var missing_memory: int=0
	var aged_memory: bool=false
	var last_phase: Dictionary={};var last_since: Dictionary={}
	var last_role: Dictionary={};var last_revision: Dictionary={};var stores: Dictionary={}
	var exited: Dictionary={};var second_pass: bool=false
	var actual_hits: int=0
	var status: String="COMPLETE_OBSERVATION_WINDOW"
	var frames: int=0
	for ship in st.ships:
		starts[str(ship.id)]=pos(ship);previous[str(ship.id)]=pos(ship);traveled[str(ship.id)]=0.0
		stores[str(ship.id)]={"ammo":float(ship.ammo),"fuel":float(ship.fuel),"supplies":float(ship.supplies)}
	for tick in range(ticks):
		if st.result!=null:status="TERMINAL_OUTCOME";break
		if Time.get_ticks_usec()-started>int(definitions.behavior_protocol.process_work_bound_seconds)*1000000:status="WORK_BOUND_INCOMPLETE";break
		var injected: Dictionary=event_at(case,tick)
		if not injected.is_empty():scripted_events.append(injected)
		var ammo_before: float=0.0
		for ship in st.ships:ammo_before+=float(ship.ammo)
		B.update(st,DT,{})
		frames+=1
		var work: Dictionary=st.tactical.budget
		for key in ["fullRoutes","rollouts","samples","clearanceTests"]:
			if int(work.get(key,0))>int(definitions.exact_work_limits[key]):physical_issues["Actual shared "+key+" work cap exceeded"]=true
		if st.tactical.routeCache.size()>int(definitions.exact_work_limits.cacheEntries) or st.tactical.trace.size()>int(definitions.exact_work_limits.traceRecords):physical_issues["Actual bounded runtime cache or trace exceeded"]=true
		var raw_events: Array=B.pop_events(st)
		var prior_positions: Dictionary=previous.duplicate()
		var spent: float=0.0
		for event in raw_events:
			if str(event.kind)=="hit":
				var hit_source: Dictionary=find(st,str(event.sourceId));var hit_target: Dictionary=find(st,str(event.targetId))
				if hit_source in case.actors and not hit_target.is_empty() and hit_source.team!=hit_target.team:actual_hits+=1
			if str(event.kind)!="fire":continue
			var shooter: Dictionary=find(st,str(event.sourceId))
			var target: Dictionary=find(st,str(event.targetId))
			var mount: Dictionary={}
			if shooter.is_empty():physical_issues["Unknown emitting hull"]=true;continue
			for fitted in B._mounts(shooter):
				if str(fitted.id)==str(event.mountId):mount=fitted;break
			if shooter.is_empty() or mount.is_empty():physical_issues["Unknown emitted mount"]=true;continue
			spent+=float(mount.ammoCost)
			if target.is_empty() or target.team==shooter.team:physical_issues["Automatic shot has no real hostile target"]=true
			if absf(angle_difference(float(shooter.angle)+float(mount.angle),float(event.angle)))>float(mount.arc)*0.5+0.10:physical_issues["Emitted shot outside actual mount arc"]=true
			var muzzle: Vector2=Vector2(event.x,event.y)
			if ray_land(st,muzzle,muzzle,float(5 if mount.kind=="torpedo" else 3)):physical_issues["Actual emitted muzzle intersects land"]=true
			events.append({"event":event.duplicate(true),"shooter_pose":{"x":float(shooter.x),"y":float(shooter.y),"vx":float(shooter.vx),"vy":float(shooter.vy),"heading":float(shooter.angle)},"target_pose":{} if target.is_empty() else {"x":float(target.x),"y":float(target.y),"vx":float(target.vx),"vy":float(target.vy)},"mount":mount.duplicate(true),"ammo_after":float(shooter.ammo)})
			if shooter in case.actors:
				useful_actor_shots+=1
				if not first_shot_pos.has(str(shooter.id)):first_shot_pos[str(shooter.id)]=pos(shooter)
			else:enemy_shots+=1
		var ammo_after: float=0.0
		for ship in st.ships:
			ammo_after+=float(ship.ammo)
			var id: String=str(ship.id)
			var old_position: Vector2=prior_positions[id]
			for other in st.ships:
				if other.team!=ship.team or str(other.id)<=id or not live(ship) or not live(other):continue
				var relative: Vector2=old_position-(prior_positions[str(other.id)] as Vector2)
				var travel: Vector2=(pos(ship)-old_position)-(pos(other)-(prior_positions[str(other.id)] as Vector2))
				var fraction: float=clampf(-relative.dot(travel)/maxf(0.000001,travel.length_squared()),0.0,1.0)
				var gap: float=(relative+travel*fraction).length()-maxf(10.0,float(ship.spec.size))-maxf(10.0,float(other.spec.size))
				minimum_ally_gap=minf(minimum_ally_gap,gap)
				if gap<6.8:physical_issues["Actual allied swept hull gap below B's 7-unit clearance"]=true
			var memory: Dictionary=st.tactical.memory[str(ship.team)].byId.get(id,{})
			if live(ship) and tick>=6 and memory.is_empty():missing_memory+=1
			if not memory.is_empty():
				var phase: String=str(memory.get("phase",""))
				var since: float=float(memory.get("phaseSince",st.time))
				if phase==str(last_phase.get(id,"")) and str(memory.get("role",""))==str(last_role.get(id,"")) and int(memory.get("orderRevision",-1))==int(last_revision.get(id,-2)) and since!=float(last_since.get(id,since)):physical_issues["Stable memory phase age was reset without a phase, role or order change"]=true
				if float(st.time)-since>=0.5:aged_memory=true
				last_phase[id]=phase;last_since[id]=since
				last_role[id]=str(memory.get("role",""));last_revision[id]=int(memory.get("orderRevision",-1))
			for key in ["ammo","fuel","supplies"]:
				if float(ship[key])>float(stores[id][key])+0.000001:physical_issues["Unfunded working store increase"]=true
				stores[id][key]=float(ship[key])
			traveled[id]+=pos(ship).distance_to(previous[id]);previous[id]=pos(ship)
			if live(ship) and ray_land(st,pos(ship),pos(ship),maxf(10.0,float(ship.spec.size))-0.2):physical_issues["Actual hull penetrates land"]=true
			for key in ["hp","water","ammo","fuel","supplies","crew","x","y","vx","vy"]:
				if not is_finite(float(ship[key])):physical_issues["Nonfinite physical state"]=true
			if float(ship.ammo)<0.0 or float(ship.fuel)<0.0 or float(ship.supplies)<0.0:physical_issues["Negative working store"]=true
		if absf((ammo_before-ammo_after)-spent)>0.00001:physical_issues["Finite actual emissions do not match spent working rounds"]=true
		if case.actors.size()>=3 and live(case.opponents[0]):
			var bearings: Array=[]
			var spread: float=0.0
			for actor in case.actors:
				if live(actor) and float(traveled[str(actor.id)])>=float(definitions.physical_metrics.separated_approach_min_travel_world_units):bearings.append((pos(actor)-pos(case.opponents[0])).angle())
			for a in bearings:
				for b in bearings:spread=maxf(spread,absf(angle_difference(float(a),float(b))))
			if bearings.size()>=3 and spread>=deg_to_rad(float(definitions.physical_metrics.separated_approach_min_bearing_spread_degrees)):separated=true
		for actor in case.actors:
			var id: String=str(actor.id)
			if not live(actor) or not live(case.opponents[0]):continue
			var delta: Vector2=pos(actor)-pos(case.opponents[0])
			if scenario_id=="A4" and actor==case.actors[0] and delta.length()-(starts[id] as Vector2).distance_to(starts[str(case.opponents[0].id)])>=float(definitions.physical_metrics.exit_radial_gain_world_units) and Vector2(actor.vx,actor.vy).dot(delta.normalized())>5.0 and float(traveled[id])>=80.0:survival_retreat=true
			if first_shot_pos.has(id):
				minimum_range[id]=minf(float(minimum_range.get(id,delta.length())),delta.length())
				var exiting: bool=delta.length()-float(minimum_range[id])>=float(definitions.physical_metrics.exit_radial_gain_world_units) and Vector2(actor.vx,actor.vy).dot(delta.normalized())>5.0 and pos(actor).distance_to(first_shot_pos[id])>=float(definitions.physical_metrics.exit_radial_gain_world_units)
				if exiting:breakaway=true
				if exiting and not exited.has(id):exited[id]={"time":float(st.time),"distance":delta.length()}
				if exited.has(id) and float(actor.get("lastShotTime",-1.0))>float(exited[id].time) and delta.length()<float(exited[id].distance)-32.0:second_pass=true
		if case.definition.has("protect_opponent_index") and live(case.opponents[0]):
			for index in range(1,case.opponents.size()):
				var screen: Dictionary=case.opponents[index]
				for threat in case.actors:
					if not live(screen) or not live(threat):continue
					var a: Vector2=pos(case.opponents[0]);var b: Vector2=pos(threat)
					var fraction: float=(pos(screen)-a).dot(b-a)/maxf(1.0,(b-a).length_squared())
					if fraction>0.0 and fraction<1.0 and point_segment(pos(screen),a,b)<=float(definitions.physical_metrics.screen_intercept_max_distance_to_threat_ally_segment) and float(traveled[str(screen.id)])>=40.0:protective_motion=true
		if tick%int(definitions.behavior_protocol.trace_every_ticks)==0 or not raw_events.is_empty():traces.append(snapshot(st))
	if st.result!=null:status="TERMINAL_OUTCOME"
	traces.append(snapshot(st))
	var failures: Array=physical_issues.keys()
	if missing_memory>0:failures.append("Actual live hull frames lost persistent planner memory")
	if not aged_memory:failures.append("No persistent phase age progressed for half a second")
	var actor_losses: int=0
	for actor in case.actors:
		if not live(actor):actor_losses+=1
	var counter_defeat: bool=actor_losses>0 and enemy_shots>0
	if status=="WORK_BOUND_INCOMPLETE":failures.append("Work bound reached; behavior case incomplete")
	if case.variant.get("requires_separated_approach",false) and not separated:failures.append("No observed separated reachable approach from native starting positions")
	if case.variant.get("requires_useful_fire",false) and useful_actor_shots<int(definitions.physical_metrics.minimum_useful_firing_events_favorable_case):failures.append("No actual useful actor firing pass")
	if case.variant.get("requires_useful_fire",false) and useful_actor_shots>0 and actual_hits==0 and not counter_defeat:failures.append("Favorable emitted shots produced no actual hostile hit or real counter defeat")
	if scenario_id in ["A1","A3"] and case.variant.get("requires_useful_fire",false) and not second_pass and not counter_defeat:failures.append("No actual second firing pass after separated exit/re-entry")
	if scenario_id in ["A1","A3"] and useful_actor_shots>0 and not breakaway and not counter_defeat:failures.append("Firing did not lead to an observed physical breakaway or real counter defeat")
	if case.variant.get("requires_no_actor_fire",false) and useful_actor_shots>0:failures.append("Empty tubes emitted free rounds")
	if case.variant.get("requires_protective_motion",false) and not protective_motion:failures.append("No actual screen movement between threat and protected ally")
	if scenario_id=="A4" and variant_id!="trapped_hull" and not survival_retreat and not counter_defeat:failures.append("Damaged boat made no physical survival retreat or observed counter defeat")
	if scenario_id in ["A2","A5"]:
		var motion: bool=false
		for actor in case.actors:
			if float(traveled[str(actor.id)])>=float(definitions.physical_metrics.movement_min_world_units):motion=true
		if not motion and not counter_defeat:failures.append("No observed adaptation/movement from initial separated positions")
	if scenario_id=="A5" and variant_id=="leader_destroyed":
		var leader_id: String=str(case.actors[int(case.definition.protect_actor_index)].id)
		for actor in case.actors:
			if live(actor) and actor.order=="escort" and str(actor.orderTarget.get("shipId",""))==leader_id:failures.append("Actual live escort retains destroyed leader order")
	return encode({"mode":"behavior","status":status,"scenario":scenario_id,"variant":variant_id,"orientation":orientation,"seed":seed,"ticks_requested":ticks,"ticks_observed":frames,"simulated_seconds":float(st.time),"terminal_result":st.result,"failures":failures,"metrics":{"traveled":traveled,"actor_shots":useful_actor_shots,"opponent_shots":enemy_shots,"actual_actor_hits":actual_hits,"minimum_allied_swept_hull_gap":minimum_ally_gap if is_finite(minimum_ally_gap) else null,"missing_memory_frames":missing_memory,"aged_memory":aged_memory,"actual_second_pass":second_pass,"separated_approach":separated,"physical_breakaway":breakaway,"protective_motion":protective_motion,"survival_retreat":survival_retreat,"actor_losses":actor_losses,"counter_defeat":counter_defeat},"scripted_events":scripted_events,"fire_events":events,"trace":traces,"scope":"Actual position/heading/shot/mount/store observations; no GPU, audio or guaranteed-light-win claim"})
