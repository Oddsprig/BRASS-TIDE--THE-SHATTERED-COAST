extends RefCounted
## Complete routes plus live 60Hz clearance; retained physical-prefix API for forecasts.
const Planner=preload("res://scripts/tactical_planner.gd")
const Routes=preload("res://scripts/tactical_routes.gd")
const Fire=preload("res://scripts/tactical_fire_control.gd")
const Damage=preload("res://scripts/damage.gd")
const Roles=preload("res://scripts/tactical_role_plans.gd")
const EquipmentCombat=preload("res://scripts/equipment_combat.gd")
const EquipmentRollout=preload("res://scripts/equipment_rollout.gd")
const EquipmentDamage=preload("res://scripts/equipment_damage.gd")
const STEP: float=1.0/30.0
# Routes.occupied adds the other hull's radius+3. Match the full corridor's
# seven-unit allied margin in actual curved prefixes and the final live step.
const HULL_CLEARANCE_MARGIN: float=4.0

class _Retained051 extends RefCounted:
	var owner: Dictionary
	var intent: Dictionary
	var record: Dictionary
	var points: Array
	var primary: Array
	var targets: Dictionary={}
	var spec: Dictionary
	var mount_source: Array
	var motion_inputs: Array
	var capability_inputs: Array
	var events: Array
	var revision: int
	var terrain_revision: int
	var chosen_at: float
	var step_at: float=-1.0
	var step_ok: bool=false

# Semantic eligibility has no intent, candidate, path, certificate or fire gate.
# The owner/target references are identity guards ONLY; all mutable predicates
# are detached, and the original chosen_at is never renewed by recertification.
class _Preference051 extends RefCounted:
	var owner: Dictionary
	var spec: Dictionary
	var mount_source: Array
	var targets: Dictionary
	var target_sides: Dictionary={}
	var options: Dictionary
	var groups: Dictionary
	var order_target: Dictionary
	var identity: Dictionary={}
	var motion_inputs: Array
	var capability_inputs: Array
	var events: Array
	var target_id: String
	var side: String
	var revision: int
	var terrain_revision: int
	var chosen_at: float
	var checked_at: float

static func _preference051(st: Dictionary,ship: Dictionary,held: _Retained051) -> _Preference051:
	var t: Dictionary=st.tactical
	var id: String=str(ship.id)
	var preference: _Preference051=_Preference051.new()
	preference.owner=ship;preference.spec=ship.spec;preference.mount_source=held.mount_source
	preference.targets=held.targets.duplicate()
	for target_id in preference.targets:preference.target_sides[target_id]=str(preference.targets[target_id].get("team",""))
	preference.options=t.options.byId[id].duplicate(true);preference.groups=t.groups.duplicate(true)
	preference.order_target=ship.orderTarget.duplicate(true)
	var memory: Dictionary=t.memory[str(ship.team)].byId.get(id,{})
	for key in ["role","phase","targetId","leaderId","firingPassId"]:preference.identity[key]=memory.get(key)
	preference.motion_inputs=held.motion_inputs.duplicate(true)
	preference.capability_inputs=held.capability_inputs.duplicate(true)
	preference.events=held.events.duplicate(true);preference.target_id=str(held.record.candidate.targetId)
	preference.side=str(ship.team);preference.revision=held.revision;preference.terrain_revision=held.terrain_revision
	preference.chosen_at=held.chosen_at;preference.checked_at=float(st.time)
	return preference

static func _preference_semantics051(st: Dictionary,ship: Dictionary,preference: _Preference051) -> bool:
	var t: Dictionary=st.tactical
	var id: String=str(ship.id)
	if str(ship.team)!=preference.side or ship.orderTarget!=preference.order_target or t.options.byId.get(id,{})!=preference.options or t.groups!=preference.groups:return false
	var memory: Dictionary=t.memory[str(ship.team)].byId.get(id,{})
	for key in preference.identity:
		if memory.get(key)!=preference.identity[key]:return false
	return true

static func _preference_conditions051(st: Dictionary,ship: Dictionary,preference: _Preference051) -> bool:
	var t: Dictionary=st.tactical
	var id: String=str(ship.id)
	if not is_same(ship,preference.owner) or str(ship.order)!="engage" or int(ship.orderRevision)!=preference.revision:return false
	if float(st.time)<preference.chosen_at or float(st.time)-preference.chosen_at>0.45+0.000001:return false
	if int(t.terrainRevision)!=preference.terrain_revision or not is_same(ship.spec,preference.spec) or not is_same(t.mountCache[id].baseMounts,preference.mount_source) or _motion_inputs(ship)!=preference.motion_inputs or not _preference_semantics051(st,ship,preference):return false
	for target_id in preference.targets:
		var target: Dictionary=t.ships.get(target_id,{})
		if not is_same(target,preference.targets[target_id]) or target.get("sunk",false) or target.get("captureSecured",false) or str(target.get("team",""))!=preference.target_sides[target_id]:return false
	return true

static func _preference_current051(st: Dictionary,ship: Dictionary,preference: _Preference051,frame_cache=null) -> bool:
	if not _preference_conditions051(st,ship,preference):return false
	var actual: Array=_live_capability(ship,Damage._read_status_in_phase043(ship,frame_cache))
	if _live_capability_lost(actual,preference.capability_inputs,_heat_wear(ship,maxf(0.0,float(st.time)-preference.checked_at),float(preference.capability_inputs[2]))):return false
	preference.capability_inputs=actual.duplicate(true);preference.checked_at=float(st.time)
	return true

static func _retain051(st: Dictionary,ship: Dictionary,intent: Dictionary,record: Dictionary,frame_cache=null) -> _Retained051:
	if str(ship.get("order",""))!="engage" or str(record.get("certificate",{}).get("scope",""))!=Planner.LIVE_CERT_SCOPE:return null
	var held: _Retained051=_Retained051.new()
	held.owner=ship;held.intent=intent;held.spec=ship.spec
	held.mount_source=st.tactical.mountCache[str(ship.id)].baseMounts
	held.revision=int(ship.orderRevision);held.terrain_revision=int(st.tactical.terrainRevision)
	held.chosen_at=float(st.time);held.motion_inputs=_motion_inputs(ship)
	held.capability_inputs=_live_capability(ship,Damage._read_status_in_phase043(ship,frame_cache)).duplicate(true)
	# _publish admitted this complete request and certificate. Seal one private
	# copy, rather than validating/fingerprinting its schema on physics reads.
	var candidate: Dictionary=record.candidate.duplicate(true)
	for key in ["approach","pass","exit","fireMountIds"]:candidate[key].make_read_only()
	if candidate.has("fireMountTargets"):candidate.fireMountTargets.make_read_only()
	candidate.make_read_only()
	held.record={"candidate":candidate,"certificate":record.certificate,"index":int(record.get("index",0))}
	held.points=execution(candidate);held.points.make_read_only()
	held.primary=primary_mounts(st.tactical.mountCache[str(ship.id)].mounts,candidate)
	var target_ids: Array=[candidate.targetId,candidate.leaderId]
	for mount_id in candidate.fireMountIds:target_ids.append(mount_target(candidate,str(mount_id)))
	for id in target_ids:
		if not str(id).is_empty():held.targets[str(id)]=st.tactical.ships.get(str(id),{})
	held.events=_retained_events051(st,ship,held)
	return held

static func _retained_events051(st: Dictionary,ship: Dictionary,held: _Retained051) -> Array:
	return _preference_events051(st,ship,str(held.record.candidate.targetId))

static func _preference_events051(st: Dictionary,ship: Dictionary,target_id: String) -> Array:
	var result: Array=[]
	var target: Dictionary=st.tactical.ships.get(target_id,{})
	var distance: float=Routes.point(ship).distance_to(Routes.point(target)) if not target.is_empty() else INF
	var mounts: Array=st.tactical.mountCache[str(ship.id)].mounts
	var timers: Array=ship.get("weaponCooldowns",[])
	for index in range(mounts.size()):
		var mount: Dictionary=mounts[index]
		var reload: float=float(timers[index]) if index<timers.size() else 0.0
		if index==0:reload=maxf(reload,float(ship.cooldown))
		result.append(ship.get("mountShotTimes",{}).get(str(mount.id),-1.0))
		result.append(reload<=0.000001)
		result.append(distance<=float(mount.range)+(Roles.radius(target) if not target.is_empty() else 0.0)+1.0)
	return result

static func _retained_current051(st: Dictionary,ship: Dictionary,held: _Retained051,frame_cache=null,preference: _Preference051=null) -> Dictionary:
	var t: Dictionary=st.tactical
	if not is_same(held.owner,ship) or not is_same(t.intents.get(str(ship.id)),held.intent) or int(ship.orderRevision)!=held.revision or str(ship.order)!="engage" or float(st.time)-held.chosen_at>0.45+0.000001:return {"ok":false,"reason":"Reconsidering maneuver"}
	if preference!=null and not _preference_semantics051(st,ship,preference):return {"ok":false,"reason":"Conditions changed; checking maneuver"}
	if int(t.terrainRevision)!=held.terrain_revision or not is_same(ship.spec,held.spec) or not is_same(t.mountCache[str(ship.id)].baseMounts,held.mount_source) or _motion_inputs(ship)!=held.motion_inputs:return {"ok":false,"reason":"Conditions changed; checking maneuver"}
	for id in held.targets:
		if not is_same(t.ships.get(id),held.targets[id]) or held.targets[id].get("sunk",false) or held.targets[id].get("captureSecured",false):return {"ok":false,"reason":"Target or leader unavailable"}
		if preference!=null and str(held.targets[id].get("team",""))!=preference.target_sides[id]:return {"ok":false,"reason":"Target or leader unavailable"}
	var actual: Array=_live_capability(ship,Damage._read_status_in_phase043(ship,frame_cache))
	if _live_capability_lost(actual,held.capability_inputs,_heat_wear(ship,float(t.dt),float(held.capability_inputs[2]))):return {"ok":false,"reason":"Damage or capability changed; reassessing"}
	held.capability_inputs=actual.duplicate(true)
	return {"ok":true,"reason":"Following retained maneuver; live clearance required","record":held.record}

static func pose(ship: Dictionary) -> Dictionary:
	return EquipmentRollout.pose(ship)

static func _motion_inputs(ship: Dictionary) -> Array:
	return [ship.spec.get("size",16),ship.spec.get("speed",90),ship.spec.get("turn",1.8),ship.spec.get("fuelUse",1),ship.spec.get("pumps",0),ship.spec.get("repairFactor",1),ship.get("supportRepairFactor",1),ship.crewMin,ship.crewOptimal,ship.capacity,ship.policy,ship.get("shoreCrew",0),float(ship.fuel)>0.0,float(ship.engine)>0.0,float(ship.crew)-float(ship.wounded)>=float(ship.crewMin)]

static func dynamics_key(ship: Dictionary) -> String:
	# Gradual bailing/repair is predicted, not byte-hashed into immutable inputs.
	return JSON.stringify(_motion_inputs(ship)).sha256_text()

static func _live_capability(ship: Dictionary, status: Dictionary) -> Array:
	return [ship.hp,ship.water,ship.fire,ship.engine,ship.crew,ship.wounded,status.speedFactor,status.turnFactor,status.weaponFactor,status.get("engineFactor",0.0),status.get("pumpFactor",0.0),status.get("armorFactor",0.0),status.get("weaponFactors",{}),status.get("repairPriority","auto"),status.get("equipmentOk",false)]

static func _heat_wear(ship: Dictionary,dt: float,previous_fire: float=-1.0) -> Vector2:
	var h: float=maxf(0.0,dt)
	# Bound only the shared damage-control tick's continuous heat wear. Safety
	# keeps no old fire sample; current fire plus all crew's possible suppression
	# bounds that short elapsed interval without adding persistent state.
	var fire_bound: float=maxf(float(ship.fire),previous_fire)
	if fire_bound<=0.0 and previous_fire>=0.0:return Vector2.ZERO
	if previous_fire<0.0:fire_bound+=maxf(0.0,float(ship.crew))*EquipmentDamage.FIRE_SUPPRESS_PER_CREW*h
	fire_bound=minf(100.0,fire_bound+EquipmentDamage.FIRE_GROWTH_PER_SEC*h)
	return Vector2(fire_bound*EquipmentDamage.FIRE_HULL_LOSS_PER_SEC*h,fire_bound*EquipmentDamage.FIRE_ENGINE_LOSS_PER_SEC*h)

static func _live_capability_lost(actual: Array,previous: Array,heat: Vector2) -> bool:
	# A live-step lease owns geometry and intent, not an exact future repair
	# state. The helm and fire gates use current factors every physical tick.
	# Keep losses/disables immediate; recovery and continuous water/fire drift
	# need no new route. Runtime.safety_check still handles danger transitions.
	if not bool(actual[14]) or actual[13]!=previous[13]:return true
	if float(actual[0])<float(previous[0])-float(heat.x)-0.0001:return true
	for index in [3,9]:
		if float(actual[index])<float(previous[index])-float(heat.y)-0.0001:return true
	for index in [4,10,11]:
		if float(actual[index])<float(previous[index])-0.0001:return true
	if float(actual[5])>float(previous[5])+0.0001:return true
	for index in [6,7,8]:
		if (float(actual[index])>0.01)!=(float(previous[index])>0.01):return true
	var weapons: Dictionary=actual[12]
	var old_weapons: Dictionary=previous[12]
	if weapons.size()!=old_weapons.size():return true
	for id in old_weapons:
		if not weapons.has(id) or float(weapons[id])<float(old_weapons[id])-0.0001:return true
	return false

static func _live_equipment(ship: Dictionary) -> Array:
	# Canonical status validates mutable module records. Comparing the entire
	# condition ledger here rejected paid repair/revision updates every tick.
	return [ship.spec,ship.get("baseSpec"),ship.get("loadout")]

static func capability(ship: Dictionary,mask_override: float=NAN,frame_cache=null) -> Dictionary:
	var status: Dictionary=Damage._read_status_in_phase043(ship,frame_cache) if frame_cache != null else Damage.get_status(ship)
	return _capability_with_status(ship,status,mask_override,frame_cache)

static func _capability_with_status(ship: Dictionary,status: Dictionary,mask_override: float=NAN,frame_cache=null) -> Dictionary:
	return EquipmentRollout.capability_with_status(ship,status,mask_override,frame_cache)

static func motion(ship: Dictionary,dt: float,desired: float,throttle: float,boost: bool=false,frame_cache=null) -> Dictionary:
	var status: Dictionary=Damage._read_status_in_phase043(ship,frame_cache) if frame_cache != null else Damage.get_status(ship)
	return _motion_with_status(ship,dt,desired,throttle,boost,status)

static func _motion_with_status(ship: Dictionary,dt: float,desired: float,throttle: float,boost: bool,status: Dictionary) -> Dictionary:
	return EquipmentRollout.motion_with_status(ship,dt,desired,throttle,boost,status)

static func paths(candidate: Dictionary) -> Array:
	var result: Array=[]
	for leg in ["approach","pass","exit"]:result.append_array(candidate.get(leg,[]))
	return result

static func execution(candidate: Dictionary) -> Array:
	return EquipmentRollout.execution(candidate)

static func steering(ship: Dictionary,points: Array,index: int,target: Dictionary={},mounts: Array=[]) -> Dictionary:
	return EquipmentRollout.steering(ship,points,index,target,mounts)

static func mount_target(candidate: Dictionary,mount_id: String) -> String:
	return EquipmentRollout.mount_target(candidate,mount_id)

static func primary_mounts(mounts: Array,candidate: Dictionary) -> Array:
	return EquipmentRollout.primary_mounts(mounts,candidate)

static func detailed_targets(view: Dictionary,ship: Dictionary,previous: Dictionary={}) -> Array:
	var context: Dictionary=Roles.ships_by_id(view)
	var protected: Dictionary=Roles.protected_ally(view,ship,previous,context)
	var ids: Array=[]
	for entry in Roles.shortlist(view,ship,context,protected):ids.append(str(entry.id))
	return ids

static func candidate_valid(candidate: Dictionary,view: Dictionary,ship: Dictionary,membership: Array=[]) -> bool:
	return _candidate_valid(candidate,view,ship,membership)

static func _begin_inputs(view: Dictionary,ship: Dictionary,membership: Array,prepared_membership051: bool=false) -> Dictionary:
	# Runtime.begin owns these detached observations for one synchronous due hull.
	# Index only invariant observations, never a candidate/route/physical verdict.
	var ids: Dictionary={}
	for mount in ship.mounts:ids[str(mount.id)]=true
	var hostiles: Dictionary={}
	for raw in view.get("ships",[]):
		if raw is Dictionary and str(raw.get("team",""))!=str(ship.get("team","")) and not raw.get("sunk",false) and not raw.get("captureSecured",false):
			hostiles[str(raw.get("id",""))]=true
	var detailed: Array=(membership if prepared_membership051 or not membership.is_empty() else detailed_targets(view,ship)).duplicate()
	if prepared_membership051:
		# Private joined preference only. Its <=16 selected IDs are checked
		# against CURRENT live hostile membership, without a third role search.
		detailed=[]
		if membership.size()<=16:
			for raw: Variant in membership:
				if raw is String and hostiles.has(raw) and raw not in detailed:detailed.append(raw)
	var cert: Dictionary=base_certificate(view,ship,{},"")
	cert.fireWindow.mountIds.make_read_only();cert.fireWindow.mountTargets.make_read_only()
	cert.fireWindow.make_read_only();cert.checkedPose.make_read_only();cert.make_read_only()
	ids.make_read_only();hostiles.make_read_only();detailed.make_read_only()
	var inputs: Dictionary={"ids":ids,"hostiles":hostiles,"detailed":detailed,"certificate":cert}
	inputs.make_read_only()
	return inputs

static func _candidate_valid(candidate: Dictionary,view: Dictionary,ship: Dictionary,membership: Array=[],begin_inputs: Dictionary={}) -> bool:
	for field in ["candidateId","shipId","targetId","leaderId","role"]:
		if not candidate.get(field,"") is String or str(candidate.get(field,"")).length()>128:return false
	if str(candidate.get("candidateId","")).is_empty() or str(candidate.get("shipId",""))!=str(ship.id) or not str(ship.id) in view.dueIds:return false
	if int(candidate.get("orderRevision",-1))!=int(ship.get("orderRevision",0)) or int(candidate.get("snapshotRevision",-1))!=int(view.snapshotRevision):return false
	var total: int=0
	for leg in ["approach","pass","exit"]:
		if not candidate.get(leg) is Array or candidate[leg].size()>8:return false
		for p in candidate[leg]:
			if not p is Vector2 or not p.is_finite():return false
		total+=candidate[leg].size()
	if total>24 or not candidate.get("fireMountIds",[]) is Array or candidate.fireMountIds.size()>16:return false
	var ids: Dictionary=begin_inputs.get("ids",{})
	if begin_inputs.is_empty():
		for mount in ship.mounts:ids[str(mount.id)]=true
	var fire_set: Dictionary={}
	for id in candidate.get("fireMountIds",[]):
		if not id is String or not ids.has(id) or fire_set.has(id):return false
		fire_set[id]=true
	var hostiles: Dictionary=begin_inputs.get("hostiles",{})
	if begin_inputs.is_empty():
		for raw in view.get("ships",[]):
			if raw is Dictionary and str(raw.get("team",""))!=str(ship.get("team","")) and not raw.get("sunk",false) and not raw.get("captureSecured",false):
				hostiles[str(raw.get("id",""))]=true
	# Runtime independently builds this position-only set once per due hull,
	# before any candidate can spend route, rollout or ballistic work.
	var detailed: Array=begin_inputs.detailed if not begin_inputs.is_empty() else (membership if not membership.is_empty() else detailed_targets(view,ship))
	if detailed.size()>16:return false
	if not candidate.fireMountIds.is_empty() and (not hostiles.has(str(candidate.get("targetId",""))) or not str(candidate.targetId) in detailed):
		return false
	if candidate.has("fireMountTargets"):
		if not candidate.get("fireMountTargets") is Dictionary:return false
		var map: Dictionary=candidate.fireMountTargets
		if map.is_empty() or map.size()>candidate.fireMountIds.size() or map.size()>16 or candidate.fireMountIds.is_empty() or str(candidate.get("targetId","")).is_empty():
			return false
		var distinct: Dictionary={str(candidate.get("targetId","")):true}
		for mount_id in map:
			if not mount_id is String or mount_id.length()>128 or not fire_set.has(mount_id):return false
			var tid=map[mount_id]
			if not tid is String or tid.is_empty() or tid.length()>128 or not hostiles.has(tid) or not tid in detailed:return false
			distinct[tid]=true
		if distinct.size()>4:return false
	return true

static func base_certificate(view: Dictionary,ship: Dictionary,candidate: Dictionary,fingerprint: String) -> Dictionary:
	return {"status":"pending","reachable":false,"exitReachable":false,"eta":0.0,"fireWindow":{"from":float(view.time),"until":float(view.time),"mountIds":[],"mountTargets":{}},"risk":1.0,"checkedAt":float(view.time),"validUntil":float(view.time),"snapshotRevision":int(view.snapshotRevision),"orderRevision":int(ship.get("orderRevision",0)),"pathFingerprint":fingerprint,"terrainRevision":view.terrainRevision,"geometryKey":JSON.stringify([view.terrainRevision,maxf(10.0,float(ship.spec.get("size",16)))]).sha256_text(),"checkedPose":pose(ship),"dynamicsKey":dynamics_key(ship),"physicalHorizonEnd":float(view.time),"rolloutSamples":0,"scope":"complete-geometry+prefix-physical","reason":"Checking a safe route"}

static func _begin_certificate(view: Dictionary,ship: Dictionary,candidate: Dictionary,fingerprint: String,begin_inputs: Dictionary) -> Dictionary:
	if begin_inputs.is_empty():return base_certificate(view,ship,candidate,fingerprint)
	var cert: Dictionary=begin_inputs.certificate.duplicate(true)
	cert.pathFingerprint=fingerprint
	return cert

static func corridor(st: Dictionary,ship: Dictionary,candidate: Dictionary,budget: Dictionary) -> Dictionary:
	var points: Array=paths(candidate)
	var previous: Vector2=Routes.point(ship)
	var elapsed: float=0.0
	var speed: float=maxf(1.0,float(ship.spec.get("speed",90))*float(ship.status.speedFactor)*(1.0 if float(ship.fuel)>0.0 else 0.2)*0.8)
	var radius: float=maxf(10.0,float(ship.spec.get("size",16)))+HULL_CLEARANCE_MARGIN
	for goal in points:
		var result: String=Routes.sweep(st.tactical.geometry,previous,goal,radius,budget)
		if result!="valid":return {"status":result,"eta":elapsed,"reason":"Checking a safe route" if result=="pending" else "Land blocks this route"}
		var until: float=elapsed+previous.distance_to(goal)/speed
		result=Routes.occupied(st.tactical.cells,ship,previous,goal,radius,elapsed,until,budget,true,Routes.contact_target(ship))
		if result!="valid":return {"status":result,"eta":elapsed,"reason":"Checking hull clearance" if result=="pending" else "Hull occupies this approach"}
		elapsed=until;previous=goal
	return {"status":"valid","eta":elapsed,"reason":"Route clear"}

static func certify(st: Dictionary,view: Dictionary,ship: Dictionary,candidate: Dictionary,fingerprint: String,budget: Dictionary,membership: Array=[]) -> Dictionary:
	return _certify(st,view,ship,candidate,fingerprint,budget,membership,false,null)

static func certify_live(st: Dictionary,view: Dictionary,ship: Dictionary,candidate: Dictionary,fingerprint: String,budget: Dictionary,membership: Array=[],frame_cache=null) -> Dictionary:
	return _certify(st,view,ship,candidate,fingerprint,budget,membership,true,frame_cache)

static func _certify_refined_live(st: Dictionary,view: Dictionary,ship: Dictionary,refined: Dictionary,fingerprint: String,budget: Dictionary,membership: Array=[],frame_cache=null,begin_inputs: Dictionary={}) -> Dictionary:
	# Runtime.begin alone supplies this same-begin Routes.refine_live result.
	# No proof is retained or reused across poses, observations or physics ticks.
	return _certify(st,view,ship,refined.candidate,fingerprint,budget,membership,true,frame_cache,refined,begin_inputs)

static func _certify(st: Dictionary,view: Dictionary,ship: Dictionary,candidate: Dictionary,fingerprint: String,budget: Dictionary,membership: Array,live_step: bool,frame_cache,refined_corridor: Dictionary={},begin_inputs: Dictionary={}) -> Dictionary:
	var cert: Dictionary=_begin_certificate(view,ship,candidate,fingerprint,begin_inputs)
	if not _candidate_valid(candidate,view,ship,membership,begin_inputs):
		cert.status="blocked";cert.reason="Weapon assignment outside bounded observed targets";return cert
	var id: String=str(ship.id)
	# Physics is 60Hz and Battle.update keeps that dt. A 30Hz sample rounded to
	# the nearest pose is already a full step ahead after one 1/60 tick, so the
	# velocity check fails and helm brakes. Retain every closed-loop half-step
	# within the 0.3s forecast: authority (0.2s) plus at least two live steps.
	# Any other dt keeps the existing single 1/30 sample.
	var sub_dt: float=float(st.tactical.get("dt",STEP))
	var parts: int=1
	if absf(sub_dt*2.0-STEP)<0.0000001:
		parts=2
	else:
		sub_dt=STEP
	# A budget refusal is pending, never evidence of a blocked route. Do not
	# recompute full corridors for a hull that cannot receive another rollout.
	if budget.rolled.has(id) or (not live_step and (int(budget.rollouts)>=16 or int(budget.samples)+Planner.CERT_PREFIX_STEPS*parts>840)):
		budget.exhaustions+=1;cert.reason="Checking the next safe maneuver";return cert
	var full: Dictionary=corridor(st,ship,candidate,budget) if refined_corridor.is_empty() else refined_corridor
	cert.eta=full.eta
	if full.status!="valid":cert.status=full.status;cert.reason=full.reason;return cert
	budget.rolled[id]=true
	if not live_step: budget.rollouts+=1
	var live_ship: Dictionary=st.get("tactical",{}).get("ships",{}).get(id,ship)
	var predicted: Array=[pose(live_ship)]
	var capabilities: Array=[]
	var primary: Array=primary_mounts(ship.mounts,candidate)
	if not live_step:
		var prefix: Dictionary=EquipmentRollout.prefix(st,ship,candidate,budget,cert,sub_dt,parts,null,Planner.CERT_PREFIX_STEPS)
		if not prefix.ok:return cert
		predicted=prefix.poses;capabilities=prefix.capabilities;primary=prefix.primary
	else:
		# The live helm already integrates this exact next step, sweeps land/allies
		# before movement and resolves actual contacts. Replaying eighteen future
		# damage/repair states bought no extra authority over those live checks.
		cert.scope=Planner.LIVE_CERT_SCOPE
		cert.physicalHorizonEnd=float(view.time)+Planner.CERT_SECONDS
	var live_status: Dictionary=Damage._read_status_in_phase043(live_ship,frame_cache)
	var target: Dictionary=st.tactical.observed.get(str(candidate.get("targetId","")),{})
	# Firing access at the proposed station is geometric/observed prediction;
	# current live fire gates still require a fresh physical intercept every tick.
	var firing: Array=[]
	var certified_targets: Dictionary={}
	var arrival: float=0.0
	var current_window: bool=false
	var station_window: bool=false
	# Route checks carry pending provenance from the active planning limit; a
	# failed budget debit is not evidence that a firing lane is obstructed.
	var fire_pending: bool=false
	if not candidate.get("fireMountIds",[]).is_empty() and not target.is_empty():
		var station: Vector2=Routes.point(ship)
		if not candidate.get("approach",[]).is_empty():station=candidate.approach[-1]
		arrival=Routes.point(ship).distance_to(station)/maxf(1.0,float(ship.spec.get("speed",90))*float(ship.status.speedFactor))
		var at_station: Dictionary=live_ship.duplicate()
		at_station.mounts=ship.mounts
		at_station.x=station.x;at_station.y=station.y
		if Routes.point(ship).distance_to(station)<14.0:
			at_station.angle=float(predicted[-1].angle)
		else:
			at_station.angle=wrapf(float(steering(at_station,[],0,target,primary).angle),-PI,PI)
		for mount in ship.mounts:
			var mount_id: String=str(mount.id)
			if not mount_id in candidate.fireMountIds:continue
			var mount_target_id: String=mount_target(candidate,mount_id)
			var mount_target_ship: Dictionary=st.tactical.observed.get(mount_target_id,{})
			var now_shot: Dictionary=Fire.solution(st,live_ship,mount,mount_target_ship,budget,st.tactical.geometry,st.tactical.cells,true,true,frame_cache,live_status)
			if now_shot.ok:current_window=true
			elif str(now_shot.get("status",""))=="pending":fire_pending=true
			var shot: Dictionary=Fire.solution(st,at_station,mount,mount_target_ship,budget,st.tactical.geometry,st.tactical.cells,true,true,frame_cache,live_status)
			if shot.ok:station_window=true
			elif str(shot.get("status",""))=="pending":fire_pending=true
			if now_shot.ok or shot.ok:
				firing.append(mount_id)
				certified_targets[mount_id]=mount_target_id
		if firing.is_empty():
			cert.status="pending" if fire_pending else "blocked"
			cert.reason="Checking firing lanes" if cert.status=="pending" else "No usable firing lane at this station"
			# A denied live hold shot must leave its existing nonfiring offer eligible.
			# Shared clearance debits, pending refusals and physical rollout caps stay.
			if live_step and not fire_pending and str(ship.get("order","engage"))=="hold":
				budget.rolled.erase(id)
			return cert
	cert.status="valid";cert.reachable=true;cert.exitReachable=true
	cert.validUntil=float(view.time)+Planner.CERT_SECONDS
	cert.physicalHorizonEnd=float(view.time)+(Planner.CERT_SECONDS if live_step else Planner.CERT_PREFIX_SECONDS)
	cert.fireWindow={"from":float(view.time)+arrival,"until":float(view.time)+arrival+(1.2 if station_window else 0.0),"mountIds":firing,"mountTargets":certified_targets}
	cert.risk=clampf(float(ship.water)/maxf(1.0,float(ship.capacity)),0.0,1.0)
	cert.reason="Route checked; live clearance at the helm" if live_step else "Route and immediate maneuver checked"
	if current_window:cert.fireWindow["from"]=float(view.time);cert.fireWindow.until=maxf(float(view.time)+0.2,float(cert.fireWindow.until))
	var motion_key: String=dynamics_key(ship)
	cert.dynamicsKey=JSON.stringify([motion_key,capabilities]).sha256_text()
	if live_step:
		st.tactical.predictions[fingerprint]={"owner":live_ship,"motionInputs":_motion_inputs(live_ship),"capabilityInputs":_live_capability(live_ship,live_status).duplicate(true),"equipmentInputs":_live_equipment(live_ship).duplicate(true),"candidate":candidate.duplicate(true),"certificate":cert.duplicate(true)}
	else:
		st.tactical.predictions[fingerprint]={"poses":predicted,"capabilities":capabilities,"motionKey":motion_key,"sampleDt":sub_dt,"candidate":candidate.duplicate(true),"certificate":cert.duplicate(true)}
	return cert

static func current(st: Dictionary,ship: Dictionary,intent: Dictionary,pose_offset: float=0.0,frame_cache=null) -> Dictionary:
	if intent.is_empty():return {"ok":false,"reason":"Choosing a safe maneuver"}
	var record: Dictionary=st.tactical.predictions.get(str(intent.get("pathFingerprint","")),{})
	if record.is_empty():return {"ok":false,"reason":"Checking the next safe maneuver"}
	var cert: Dictionary=record.certificate
	if str(cert.status)!="valid" or float(st.time)>minf(float(cert.validUntil),float(intent.get("validUntil",-1)))+0.0000001:return {"ok":false,"reason":"Checking the next safe maneuver"}
	if str(intent.get("candidateId",""))!=str(record.candidate.candidateId) or int(intent.get("snapshotRevision",-1))!=int(cert.snapshotRevision) or int(intent.get("orderRevision",-1))!=int(ship.get("orderRevision",0)):return {"ok":false,"reason":"Following the new order"}
	if st.tactical.terrainRevision!=cert.terrainRevision:return {"ok":false,"reason":"Terrain changed; checking maneuver"}
	if str(cert.get("scope",""))==Planner.LIVE_CERT_SCOPE:
		if not is_same(record.get("owner"),ship):return {"ok":false,"reason":"Boat owner changed; checking maneuver"}
		var live_inputs: Array=_live_capability(ship,Damage._read_status_in_phase043(ship,frame_cache))
		var heat: Vector2=_heat_wear(ship,float(st.tactical.dt),float(record.capabilityInputs[2]))
		if _motion_inputs(ship)!=record.motionInputs or _live_equipment(ship)!=record.equipmentInputs or _live_capability_lost(live_inputs,record.capabilityInputs,heat):
			return {"ok":false,"reason":"Damage or capability changed; reassessing"}
		# Advance only this private loss guard, never certificate time/geometry or
		# intent. A hit after recovery must compare with the recovered boat, not
		# the lower capability at the start of the bounded lease.
		if live_inputs!=record.capabilityInputs:record.capabilityInputs=live_inputs.duplicate(true)
		return {"ok":true,"reason":str(intent.get("reason","Following maneuver")),"record":record}
	if dynamics_key(ship)!=str(record.motionKey):return {"ok":false,"reason":"Conditions changed; checking maneuver"}
	var age: float=maxf(0.0,float(st.time)-float(cert.checkedAt))
	var sample_dt: float=float(record.get("sampleDt",STEP))
	if sample_dt<=0.0:sample_dt=STEP
	var at: int=roundi((age+pose_offset)/sample_dt)
	if age+pose_offset>float(cert.physicalHorizonEnd)-float(cert.checkedAt)+0.0000001 or at<0 or at>=record.poses.size():return {"ok":false,"reason":"Checking the next safe maneuver"}
	var predicted: Dictionary=record.poses[at]
	if Routes.point(ship).distance_to(Routes.point(predicted))>2.0 or Vector2(ship.vx,ship.vy).distance_to(Vector2(predicted.vx,predicted.vy))>2.0 or absf(angle_difference(float(ship.angle),float(predicted.angle)))>deg_to_rad(1.0):return {"ok":false,"reason":"Traffic changed; checking approach"}
	# Fire follows this tick's movement before the next damage prepass. Its
	# capability belongs to age, while its position belongs to age+dt.
	var condition_at: int=roundi(age/sample_dt)
	if condition_at<0 or condition_at>=record.capabilities.size():return {"ok":false,"reason":"Checking the next safe maneuver"}
	var actual: Dictionary=capability(ship,NAN,frame_cache)
	var expected: Dictionary=record.capabilities[condition_at]
	for key in expected:
		if absf(float(actual[key])-float(expected[key]))>0.0001:return {"ok":false,"reason":"Damage or capability changed; reassessing"}
	return {"ok":true,"reason":str(intent.get("reason","Following maneuver")),"record":record}

static func safe_step(st: Dictionary,ship: Dictionary,control: Dictionary,budget: Dictionary,frame_cache=null) -> Dictionary:
	var next: Dictionary=motion(ship,float(st.tactical.dt),float(control.angle),float(control.throttle),false,frame_cache)
	var r: float=maxf(10.0,float(ship.spec.get("size",16)))+HULL_CLEARANCE_MARGIN
	var clear: String=Routes.sweep(st.tactical.geometry,Routes.point(ship),Routes.point(next),r,budget)
	var contact_id: String=Routes.contact_target(ship)
	var intent: Dictionary=st.tactical.get("intents",{}).get(str(ship.id),{})
	var boarding: Dictionary=ship.get("boardingOrder",{})
	if contact_id.is_empty() and str(intent.get("phase",""))=="board" and int(intent.get("orderRevision",-1))==int(ship.get("orderRevision",0)) and str(intent.get("targetId",""))==str(boarding.get("target","")) and int(boarding.get("orderRevision",-1))==int(ship.get("orderRevision",0)):
		contact_id=str(intent.get("targetId",""))
	if bool(st.tactical.get("safety",{}).get(str(ship.id),{}).get("withdraw",false)):contact_id=""
	if clear=="valid":clear=Routes.occupied(st.tactical.cells,ship,Routes.point(ship),Routes.point(next),r,0.0,float(st.tactical.dt),budget,true,contact_id)
	if clear=="valid":return control
	return {"angle":float(ship.angle),"throttle":0.0,"reason":"Braking; checking clearance" if clear=="pending" else "Braking for land or nearby hulls","blocked":true}

static func _crowd_step051(st: Dictionary,ship: Dictionary,candidate: Dictionary,control: Dictionary,budget: Dictionary,frame_cache=null) -> Dictionary:
	# Runtime has already checked the exact current owner/order/certificate.
	# Rotate only an owned nonfiring escape; public safe_step is unchanged.
	if not Routes._is_crowd_escape051(candidate) or str(candidate.get("shipId",""))!=str(ship.id) or int(candidate.get("orderRevision",-1))!=int(ship.get("orderRevision",0)) or float(control.throttle)<=0.0 or absf(angle_difference(float(ship.angle),float(control.angle)))<=0.000001:
		return safe_step(st,ship,control,budget,frame_cache)
	var alignment: Dictionary=control.duplicate()
	alignment.throttle=0.0
	var next: Dictionary=motion(ship,float(st.tactical.dt),float(alignment.angle),0.0,false,frame_cache)
	if absf(angle_difference(float(ship.angle),float(next.angle)))<=0.000001:return safe_step(st,ship,control,budget,frame_cache)
	var r: float=maxf(10.0,float(ship.spec.get("size",16)))+HULL_CLEARANCE_MARGIN
	var clear: String=Routes.sweep(st.tactical.geometry,Routes.point(ship),Routes.point(next),r,budget)
	if clear=="valid":clear=Routes._checked_alignment051(st.tactical.cells,ship,Routes.point(ship),Routes.point(next),r,float(st.tactical.dt),budget)
	if clear=="valid":return alignment
	return {"angle":float(ship.angle),"throttle":0.0,"reason":"Braking; checking clearance" if clear=="pending" else "Braking for land or nearby hulls","blocked":true}

static func brake(st: Dictionary,ship: Dictionary,budget: Dictionary,reason: String,frame_cache=null) -> Dictionary:
	var control: Dictionary={"angle":float(ship.angle),"throttle":0.0,"reason":reason}
	var checked: Dictionary=safe_step(st,ship,control,budget,frame_cache)
	if checked.get("blocked",false):checked.reason=reason+"; braking drift is obstructed"
	return checked
