extends RefCounted
## Main-thread battle lifetime; detached A boundary and authoritative publication.
const Planner=preload("res://scripts/tactical_planner.gd")
const Stations=preload("res://scripts/tactical_stations.gd")
const Routes=preload("res://scripts/tactical_routes.gd")
const Certification=preload("res://scripts/tactical_certification.gd")
const Fire=preload("res://scripts/tactical_fire_control.gd")
const Roles=preload("res://scripts/tactical_role_plans.gd")
const Damage=preload("res://scripts/damage.gd")
const EquipmentCombat=preload("res://scripts/equipment_combat.gd")

# Optional cumulative diagnostics; independent of authoritative tactical state.
static var _runtime_profile043_enabled: bool=false
static var _runtime_profile043_counts: Dictionary={"beginCalls":0,"viewCalls":0,"observedCalls":0,"observedUs":0,"observedMountsCopied":0,"observedMountCopyUs":0,"ownCopies":0,"ownCopyUs":0,"enemyCopies":0,"enemyCopyUs":0,"enemyMountsCopied":0,
	"retainedAdmissions":0,"retainedDue":0,"fullDue":0,"retainedMissOwnerDeadline":0,"retainedMissConditions":0,"retainedMissTarget":0,"retainedMissCapability":0,"retainedMissOther":0,
	"retainedDropTime":0,"retainedDropEvents":0,"retainedDropPhase":0,"retainedDropCompletion":0,"retainedDropBoarding":0,
	"workerDispatches":0,"workerAdoptions":0,"workerDrops":0,"workerSyncFallbacks":0,
	"certificationInputCalls":0,"certificationRefineCalls":0,"certificationAdoptCalls":0,"certificationReservedPathCalls":0,"workerFixedEndpointRejects051":0}

static func set_runtime_profile043(enabled: bool) -> void:
	_runtime_profile043_enabled=enabled

static func reset_runtime_profile043() -> void:
	for key in _runtime_profile043_counts:_runtime_profile043_counts[key]=0

static func runtime_profile043() -> Dictionary:
	var result: Dictionary=_runtime_profile043_counts.duplicate(true)
	result.schema=1;result.enabled=_runtime_profile043_enabled
	return result

static func defaults() -> Dictionary:
	return {"doctrine":"steady","role":"auto","group":0,"formation":"line","protectedAllyId":"","rally":{},"leash":600.0,"conditionalWithdrawal":false,"mounts":{}}

static func enable_planning051(st: Dictionary) -> void:
	# Main and the real voyage use this SAME workload policy. Ordinary duels
	# keep immediate synchronous role planning; side batches serve actual fleets.
	var t: Dictionary=ensure(st)
	var counts: Dictionary={"player":0,"enemy":0}
	var manual_id: String=str(st.get("playerId","")) if not bool(st.get("autopilot",true)) else str(t.manualId)
	for ship: Dictionary in st.get("ships",[]):
		if ship.sunk or ship.get("captureSecured",false) or str(ship.id)==manual_id:continue
		var side: String=str(ship.team)
		if not counts.has(side):continue
		counts[side]+=1
		if int(counts[side])>1:
			Planner._enable_workers051(t)
			return
	# Also safe if the owner reactivates an encounter after its fleet shrinks.
	Planner._retire_workers051(t)

static func retire_planning051(st: Dictionary) -> void:
	if st.get("tactical") is Dictionary:Planner._retire_workers051(st.tactical)

static func poll_planning051() -> void:
	Planner._poll_tasks051()

static func drain_planning051() -> void:
	# Owner shutdown/fixture teardown ONLY. Never called by Battle.update.
	Planner._poll_tasks051(true)

static func _worker_capability051(st: Dictionary,id: String,previous: Array=[],frame_cache=null) -> Array:
	var ship: Dictionary=st.tactical.ships[id]
	var actual: Array=[Certification._motion_inputs(ship),Certification._live_capability(ship,Damage._read_status_in_phase043(ship,frame_cache)).duplicate(true)]
	if not previous.is_empty() and (actual[0]!=previous[0] or Certification._live_capability_lost(actual[1],previous[1],Vector2.ZERO)):return []
	return actual

static func ensure(st: Dictionary) -> Dictionary:
	if not st.get("tactical") is Dictionary:
		st.tactical={"snapshotRevision":0,"terrainRevision":0,"terrainKey":"","options":{"byId":{}},"groups":{1:[],2:[],3:[],4:[]},"memory":{"player":{"byId":{},"reservations":{}},"enemy":{"byId":{},"reservations":{}}},"intents":{},"predictions":{},"mountCache":{},"pending":{},"lastDecision":{},"lastSafety":{},"orderTimes":{},"reasons":{},"fireReasons":{},"passes":{},"salvoSpent":{},"home":{},"trace":[],"counters":{"droppedDecisions":0,"decisions":0,"lateDecisions":0,"lateSafety":0,"rejectedIntents":0,"oldestDecisionAge":0.0,"oldestSafetyAge":0.0,"oldestPendingAge":0.0,"orderAcks":[]},"ships":{},"observed":{},"cells":{},"geometry":{},"dt":1.0/30.0,"manualId":"","routeCache":{},"budget":{},"failures":{}}
	if not st.tactical.has("certificationAttempts"):
		st.tactical.certificationAttempts={};st.tactical.lastCertified={};st.tactical.safety={}
	if not st.tactical.has("retained051"):st.tactical.retained051={}
	if not st.tactical.has("preferences051"):st.tactical.preferences051={}
	return st.tactical

static func register(st: Dictionary,ship: Dictionary,mounts: Array) -> void:
	var t: Dictionary=ensure(st)
	var id: String=str(ship.id)
	var base_mounts: Array=mounts.duplicate(true)
	t.mountCache[id]={"source":ship.spec.get("weaponMounts",ship.spec).duplicate(true),"baseMounts":base_mounts,"conditionKey":EquipmentCombat.mount_cache_key(ship),"mounts":EquipmentCombat.apply_mount_condition(ship,base_mounts)}
	if not t.options.byId.has(id):t.options.byId[id]=defaults()
	if not t.home.has(id):
		var home: Vector2=Vector2(clampf(float(ship.x)+(-260.0 if ship.team=="player" else 260.0),50.0,2250.0),clampf(float(ship.y),50.0,1650.0))
		var budget: Dictionary={"clearanceTests":0,"clearanceLimit":4096,"exhaustions":0}
		if Routes.sweep(Routes.terrain(st),home,home,Routes.planning_radius(ship),budget)!="valid":home=Routes.point(ship)
		t.home[id]={"x":home.x,"y":home.y}
	if not ship.has("orderRevision"):ship.orderRevision=0
	if not t.orderTimes.has(id):t.orderTimes[id]=float(st.time)

static func refresh_mounts(st: Dictionary,ship: Dictionary,frame_cache=null) -> Array:
	var t: Dictionary=ensure(st)
	var id: String=str(ship.id)
	if not t.mountCache.has(id):return []
	var entry: Dictionary=t.mountCache[id]
	var cond_key: String=EquipmentCombat.mount_cache_key(ship,{},frame_cache)
	if str(entry.get("conditionKey",""))!=cond_key:
		var base_mounts: Array=entry.get("baseMounts",entry.get("mounts",[]))
		entry.conditionKey=cond_key
		entry.mounts=EquipmentCombat.apply_mount_condition(ship,base_mounts,{},frame_cache)
		t.mountCache[id]=entry
	return entry.mounts

static func accept_command(st: Dictionary,ship: Dictionary,order: String,target: Dictionary={},automatic: bool=false) -> void:
	var t: Dictionary=ensure(st)
	var id: String=str(ship.id)
	var previous_revision: int=int(ship.get("orderRevision",0))
	ship.orderRevision=previous_revision+1
	ship.order=order;ship.orderTarget=target.duplicate(true)
	# Only approach metadata is cancelled. Launched parties/jobs own real crew
	# independently in Boarding and are deliberately never recalled here.
	ship.erase("boardingOrder")
	_drop_retained051(t,id);t.pending[id]=float(st.time)
	t.lastDecision[id]=-1.0;t.orderTimes[id]=float(st.time)
	t.certificationAttempts[id]=-2.0
	t.reasons[id]="Order received: "+order.capitalize()
	if order=="attack":t.passes.erase(id)
	else:Fire.carry_revision(st,ship,previous_revision)
	for side in t.memory:
		if order=="attack":t.memory[side].get("byId",{}).erase(id)
		t.memory[side].get("reservations",{}).erase(id)
	t.counters.orderAcks.append({"shipId":id,"revision":int(ship.orderRevision),"time":float(st.time),"age":0.0,"automatic":automatic})
	if t.counters.orderAcks.size()>512:t.counters.orderAcks.pop_front()

static func control_changed(st: Dictionary) -> void:
	var t: Dictionary=ensure(st)
	var id: String=str(st.get("playerId",""))
	_drop_retained051(t,id)
	t.certificationAttempts[id]=-2.0
	t.reasons[id]="Checking order after control change"

static func _active_party_target(st: Dictionary,id: String) -> String:
	# Job identity for duplicate-approach suppression and metadata cleanup.
	# It is not a helm order. boarding.gd still records an escape if the source leaves.
	for job in st.get("boarding",{}).get("jobs",[]):
		if job is Dictionary and str(job.get("status",""))=="active" and str(job.get("source",""))==id:
			return str(job.get("target",""))
	return ""

static func _survival_override(st: Dictionary,ship: Dictionary,frame_cache=null) -> bool:
	var t: Dictionary=st.tactical
	var id: String=str(ship.id)
	if bool(t.get("safety",{}).get(id,{}).get("withdraw",false)):return true
	var order: String=str(ship.get("order","engage"))
	var conditional: bool=bool(t.options.byId.get(id,defaults()).get("conditionalWithdrawal",false))
	# Explicit move/hold/withdraw/board already own the helm. Engage, and an
	# explicit order with survival permission, still break for flood, dry guns, or no fuel.
	if order!="engage" and not conditional:return false
	if float(ship.get("fuel",0.0))<=0.0:return true
	if float(Damage._read_status_in_phase043(ship,frame_cache).get("weaponFactor",1.0))<=0.01:return true
	for mount in t.mountCache.get(id,{}).get("mounts",[]):
		if float(ship.get("ammo",0.0))>=float(mount.get("ammoCost",1.0)) and float(mount.get("damage",0.0))>0.0:return false
	return true

static func _boarding_contact(st: Dictionary,ship: Dictionary,frame_cache=null) -> String:
	# Continuity for one unchanged automatic engage revision. A new order, manual
	# helm, or survival break is left exactly as stored on the live ship.
	var plan: Dictionary=ship.get("boardingOrder",{})
	if plan.is_empty() or not bool(plan.get("automatic",false)):return ""
	if int(plan.get("orderRevision",-1))!=int(ship.get("orderRevision",0)):return ""
	if str(ship.get("order","engage"))!="engage":return ""
	if str(ship.id)==str(st.tactical.get("manualId","")) or _survival_override(st,ship,frame_cache):return ""
	var target: String=str(plan.get("target",""))
	return target if not target.is_empty() else ""

static func _live(st: Dictionary,id: String) -> Dictionary:
	for ship in st.get("ships",[]):
		if str(ship.id)==id and not ship.sunk and not ship.get("captureSecured",false):return ship
	return {}

static func set_options(st: Dictionary,ids: Array,patch: Dictionary) -> bool:
	if st.get("result")!=null or ids.is_empty() or patch.is_empty():return false
	var allowed: Array=["doctrine","role","group","formation","protectedAllyId","rally","leash","conditionalWithdrawal","mounts","mountGroup"]
	for key in patch:
		if not key in allowed:return false
	if patch.has("doctrine") and not patch.doctrine in ["cautious","steady","aggressive"]:return false
	if patch.has("role") and not patch.role in ["auto","skirmisher","striker","heavy","screen","support"]:return false
	if patch.has("formation") and not patch.formation in ["line","screen","column"]:return false
	if patch.has("group") and (not patch.group is int or int(patch.group)<0 or int(patch.group)>4):return false
	if patch.has("leash") and (not (patch.leash is int or patch.leash is float) or not is_finite(float(patch.leash)) or float(patch.leash)<80.0 or float(patch.leash)>2300.0):return false
	if patch.has("conditionalWithdrawal") and not patch.conditionalWithdrawal is bool:return false
	if patch.has("protectedAllyId"):
		if not patch.protectedAllyId is String:return false
		if not str(patch.protectedAllyId).is_empty():
			var protected: Dictionary=_live(st,str(patch.protectedAllyId))
			if protected.is_empty() or protected.team!="player":return false
	if patch.has("rally"):
		if not patch.rally is Dictionary:return false
		if not patch.rally.is_empty():
			if patch.rally.size()!=2 or not patch.rally.has("x") or not patch.rally.has("y"):return false
			for key in ["x","y"]:
				if not (patch.rally[key] is float or patch.rally[key] is int) or not is_finite(float(patch.rally[key])):return false
	if patch.has("mounts"):
		if not patch.mounts is Dictionary or patch.mounts.size()>16:return false
		for id in patch.mounts:
			if not id is String or id.length()>128 or not patch.mounts[id] is Dictionary:return false
			for key in patch.mounts[id]:
				var value=patch.mounts[id][key]
				if key=="hold":
					if not value is bool:return false
				elif key=="reserve":
					if not value is int or value<0 or value>1000000:return false
				else:return false
	if patch.has("mountGroup"):
		if not patch.mountGroup is Dictionary or not patch.mountGroup.get("kind","") in ["all","gun","cannon","rocket","torpedo"]:return false
		for key in patch.mountGroup:
			if key=="kind":continue
			if key=="hold":
				if not patch.mountGroup[key] is bool:return false
			elif key=="reserve":
				if not patch.mountGroup[key] is int or int(patch.mountGroup[key])<0 or int(patch.mountGroup[key])>1000000:return false
			else:return false
	var t: Dictionary=ensure(st)
	var staged: Dictionary={}
	for id in ids:
		if not (id is String or id is StringName):return false
		var ship: Dictionary=_live(st,str(id))
		if ship.is_empty() or ship.team!="player" or not t.mountCache.has(str(id)):return false
		var next: Dictionary=t.options.byId.get(str(id),defaults()).duplicate(true)
		for key in patch:
			if key=="mountGroup":
				for mount in t.mountCache[str(id)].mounts:
					if str(patch.mountGroup.kind)!="all" and str(mount.kind)!=str(patch.mountGroup.kind):continue
					var choice: Dictionary=next.mounts.get(str(mount.id),{"hold":false,"reserve":0}).duplicate(true)
					for field in ["hold","reserve"]:
						if patch.mountGroup.has(field):choice[field]=patch.mountGroup[field]
					next.mounts[str(mount.id)]=choice
			elif key=="mounts":
				var installed: Array=[]
				for mount in t.mountCache[str(id)].mounts:installed.append(str(mount.id))
				for mount_id in patch.mounts:
					if not mount_id in installed:return false
					var choice: Dictionary=next.mounts.get(mount_id,{"hold":false,"reserve":0}).duplicate(true)
					choice.merge(patch.mounts[mount_id],true);next.mounts[mount_id]=choice
			else:next[key]=patch[key].duplicate(true) if patch[key] is Dictionary else patch[key]
		staged[str(id)]=next
	# No live option or order changes until every recipient and mount validates.
	for id in staged:
		t.options.byId[id]=staged[id]
		_drop_retained051(t,id);t.pending[id]=float(st.time)
		t.reasons[id]="Tactical choices updated"
	t.groups={1:[],2:[],3:[],4:[]}
	for id in t.options.byId:
		var group: int=int(t.options.byId[id].group)
		if group>0 and not _live(st,id).is_empty():t.groups[group].append(id)
	return true

static func _observed(ship: Dictionary,mounts: Array,begin_borrow051: bool=false) -> Dictionary:
	var profile_started: int=Time.get_ticks_usec() if _runtime_profile043_enabled else 0
	var out: Dictionary={}
	for key in ["id","uid","team","name","x","y","vx","vy","angle","hp","maxHp","water","capacity","fire","engine","sunk","captureSecured"]:
		if ship.has(key):out[key]=ship[key]
	out.spec={}
	for key in ["id","size","speed","turn","fuelUse","armor","role","tier","hp"]:
		if ship.spec.has(key):out.spec[key]=ship.spec[key]
	var mounts_started: int=Time.get_ticks_usec() if _runtime_profile043_enabled else 0
	# Battle replaces conditioned mount arrays; it never edits a published array.
	# Main's pure begin may read that generation directly. Public/worker views
	# still detach it, and shot times below remain the actual pre-motion sample.
	out.mounts=mounts if begin_borrow051 else mounts.duplicate(true)
	if _runtime_profile043_enabled:
		_runtime_profile043_counts.observedMountCopyUs+=Time.get_ticks_usec()-mounts_started
		_runtime_profile043_counts.observedMountsCopied+=0 if begin_borrow051 else mounts.size()
	out.mountShotTimes=ship.get("mountShotTimes",{}).duplicate(true)
	if _runtime_profile043_enabled:
		_runtime_profile043_counts.observedUs+=Time.get_ticks_usec()-profile_started
		_runtime_profile043_counts.observedCalls+=1
	return out

static func _own(ship: Dictionary,mounts: Array,frame_cache=null,observed051: Dictionary={},begin_borrow051: bool=false) -> Dictionary:
	var profile_started: int=Time.get_ticks_usec() if _runtime_profile043_enabled else 0
	var out: Dictionary=_observed(ship,mounts) if observed051.is_empty() else observed051.duplicate()
	for key in ["crew","wounded","crewMin","crewOptimal","crewMax","supplies","ammo","fuel","cooldown","policy","shoreCrew","order","orderTarget","orderRevision","formationIndex","boardingOrder","breaches","supportRepairFactor"]:
		if ship.has(key):out[key]=ship[key].duplicate(true) if not begin_borrow051 and (ship[key] is Dictionary or ship[key] is Array) else ship[key]
	# Keep only numerical movement/crew/pump inputs, never the full catalogue fit.
	out.spec={}
	for key in ["id","size","speed","turn","fuelUse","armor","role","tier","hp","pumps","repairFactor"]:
		if ship.spec.has(key):out.spec[key]=ship.spec[key]
	out.weaponCooldowns=ship.get("weaponCooldowns",[]) if begin_borrow051 else ship.get("weaponCooldowns",[]).duplicate()
	var status051: Dictionary=Damage._read_status_in_phase043(ship,frame_cache)
	out.status=status051 if begin_borrow051 else status051.duplicate(true)
	if _runtime_profile043_enabled:
		_runtime_profile043_counts.ownCopyUs+=Time.get_ticks_usec()-profile_started
		_runtime_profile043_counts.ownCopies+=1
	return out

static func view(st: Dictionary,side: String,due: Array,frame_cache=null) -> Dictionary:
	# Public callers retain full, detached, mutable owner and enemy records.
	return _view051(st,side,due,frame_cache,false)

static func _begin_view051(st: Dictionary,side: String,due: Array,frame_cache=null,current051: Variant=null) -> Dictionary:
	# Only an explicit context opts the closed synchronous begin into borrowing.
	# Omitted contexts retain detached, frozen shared observations for callers
	# that keep this private view after begin returns.
	return _view051(st,side,due,frame_cache,true,false,current051)

static func _begin_context051(st: Dictionary,side: String,frame_cache,current051: Dictionary) -> Dictionary:
	if not current051.has("sides"):
		current051.sides={};current051.owners={};current051.indexes={}
		current051.mission=public_mission(st)
	if not current051.sides.has(side):
		var t: Dictionary=st.tactical
		var context: Dictionary=t.observed.duplicate()
		for id in t.ships:
			var ship: Dictionary=t.ships[id]
			if str(ship.team)!=side:continue
			var ally: Dictionary=t.observed[id].duplicate()
			ally.ammo=ship.ammo;ally.order=ship.order;ally.orderTarget=ship.orderTarget
			ally.status=Damage._read_status_in_phase043(ship,frame_cache)
			context[id]=ally
		current051.sides[side]=context
	return current051.sides[side]

static func _begin_owner051(st: Dictionary,id: String,frame_cache,current051: Dictionary) -> Dictionary:
	if not current051.owners.has(id):
		var t: Dictionary=st.tactical
		current051.owners[id]=_own(t.ships[id],t.mountCache[id].mounts,frame_cache,t.observed[id],true)
	return current051.owners[id]

static func _worker_view051(st: Dictionary,side: String,due: Array,frame_cache=null) -> Dictionary:
	# Construct the exclusively owned capsule once, using the same schema and
	# lean friendly records. No main/worker Dictionary or Array is shared.
	return _view051(st,side,due,frame_cache,true,true)

static func _view_read_only051(value: Variant) -> void:
	if value is Dictionary or value is Array:
		if value.is_read_only():return
		for child in (value.values() if value is Dictionary else value):_view_read_only051(child)
		value.make_read_only()

static func _view051(st: Dictionary,side: String,due: Array,frame_cache,closed_begin051: bool,worker_owned051: bool=false,current051: Variant=null) -> Dictionary:
	if _runtime_profile043_enabled:_runtime_profile043_counts.viewCalls+=1
	var t: Dictionary=st.tactical
	var ships: Array=[]
	var choices: Dictionary={}
	var main051: bool=closed_begin051 and not worker_owned051 and current051 is Dictionary
	if main051 and not current051.has("sides"):
		current051.sides={};current051.owners={};current051.indexes={}
		current051.mission=public_mission(st)
	# Selection may already have built the friendly context. Otherwise build
	# the snapshot directly below, without a second all-hull preparation pass.
	var context051: Dictionary=current051.sides.get(side,{}) if main051 else {}
	var index051: Dictionary={}
	for id in t.ships:
		var ship: Dictionary=t.ships[id]
		var mounts: Array=t.mountCache[id].mounts
		var observed051: Dictionary={}
		if closed_begin051:
			observed051=t.observed[id].duplicate(true) if worker_owned051 else t.observed[id]
			if not main051 and not worker_owned051 and not observed051.is_read_only():
				# Begin observations can borrow live mount generations. Detach before
				# freezing, then share this exact observation on either side only once.
				observed051=observed051.duplicate(true)
				_view_read_only051(observed051)
				t.observed[id]=observed051
			# Explicit main readers finish before helm/motion/fire writes; their
			# borrowed live mount/status/option graphs must stay mutable.
		if ship.team==side:
			var own: Dictionary
			if not closed_begin051 or id in due:
				own=_begin_owner051(st,str(id),frame_cache,current051) if main051 else _own(ship,mounts,frame_cache,observed051)
			else:
				# Roles._leader_score/working_mounts need these current friendly
				# inputs, but never crew, breaches, fuel/supplies or cooldown copies.
				own=context051[id] if main051 and not context051.is_empty() else observed051.duplicate()
				if not main051 or context051.is_empty():
					for key in ["ammo","order","orderTarget"]:
						if ship.has(key):own[key]=ship[key].duplicate(true) if not main051 and ship[key] is Dictionary else ship[key]
					var status051: Dictionary=Damage._read_status_in_phase043(ship,frame_cache)
					own.status=status051 if main051 else status051.duplicate(true)
			own.orderSince=float(t.orderTimes.get(id,0.0))
			own.failedTargetIds=t.failures.get(id,[]).duplicate()
			var contact: String=_boarding_contact(st,ship,frame_cache)
			if not contact.is_empty():
				own.order="board";own.orderTarget={"shipId":contact}
			# Preserve the targetless legacy attack API. Nearest is selected ONCE
			# before planner/fire gating, not as a hidden per-mount fallback.
			if own.order=="attack" and own.orderTarget.is_empty():
				var best: float=INF
				for enemy_id in t.observed:
					var enemy: Dictionary=t.observed[enemy_id]
					if enemy.team==side:continue
					var distance: float=Routes.point(ship).distance_squared_to(Routes.point(enemy))
					if distance<best:best=distance;own.orderTarget={"shipId":enemy_id}
			ships.append(own)
			if main051:index051[id]=own
			choices[id]=t.options.byId.get(id,defaults()).duplicate(not main051)
			# This contact is still the live automatic engage command. Retain its
			# survival permission only in the detached planner view; explicit board
			# choices and the launched crew job remain exactly as accepted.
			if not contact.is_empty():choices[id].conditionalWithdrawal=true
			if choices[id].rally.is_empty():
				# A birth home already inside the completed pass is not an egress.
				# Only that short post-shot breakaway uses the existing checked local
				# rally geometry. Regroup/home and all explicit destinations stay intact.
				var retained: Dictionary=t.memory[side].byId.get(id,{})
				var departure: Variant=retained.get("launchPos",retained.get("breakawayFrom"))
				var spent_pass: bool=int(retained.get("passShots",0))>0 or not retained.get("passSpent",{}).is_empty()
				var home: Dictionary=t.home[id]
				var local_radius: float=maxf(60.0,maxf(10.0,float(ship.spec.size))*2.0)
				var short_home: bool=departure is Vector2 and departure.distance_to(Vector2(home.x,home.y))<local_radius
				var local_egress: bool=str(retained.get("phase","")) in ["breakaway","turn-away"] and spent_pass and short_home
				if own.order=="withdraw" or not local_egress:
					choices[id].rally=home if main051 else home.duplicate(true)
					choices[id].defaultRally051=true # Detached default, never a user option.
			if own.order=="withdraw" and own.orderTarget.has("x"):choices[id].rally=own.orderTarget if main051 else own.orderTarget.duplicate(true)
		else:
			if closed_begin051:
				ships.append(observed051)
				if main051:index051[id]=observed051
			else:
				var profile_started: int=Time.get_ticks_usec() if _runtime_profile043_enabled else 0
				ships.append(t.observed[id].duplicate(true))
				if _runtime_profile043_enabled:
					_runtime_profile043_counts.enemyCopyUs+=Time.get_ticks_usec()-profile_started
					_runtime_profile043_counts.enemyCopies+=1
					var copied_mounts = t.observed[id].get("mounts",[])
					if copied_mounts is Array:_runtime_profile043_counts.enemyMountsCopied+=copied_mounts.size()
	var groups: Dictionary={1:[],2:[],3:[],4:[]}
	for group in t.groups:
		for id in t.groups[group]:
			if choices.has(id):groups[group].append(id)
	if main051:current051.indexes[side]=index051
	return {"snapshotRevision":int(t.snapshotRevision),"terrainRevision":t.terrainRevision,"time":float(st.time),"dt":float(t.dt),"side":side,"dueIds":due.duplicate(),"ships":ships,"groups":groups,"options":{"byId":choices,"clearanceRemaining":maxi(0,int(t.budget.get("clearanceLimit",4096))-int(t.budget.clearanceTests))},"mission":current051.mission if main051 else public_mission(st)}

static func public_mission(st: Dictionary) -> Dictionary:
	var source: Dictionary=st.get("mission",{})
	var result: Dictionary={"kind":str(source.get("kind","")).left(128),"duration":maxf(0.0,Damage.number(source.get("duration"))),"allyUids":[]}
	if source.get("allyUids",[]) is Array:
		for id in source.get("allyUids",[]):
			if id is String and id.length()<=128:result.allyUids.append(id)
	return result

static func _order_lifetime(st: Dictionary,ship: Dictionary) -> void:
	var t: Dictionary=st.tactical
	var id: String=str(ship.id)
	var order: String=str(ship.get("order","engage"))
	var target: Dictionary=ship.get("orderTarget",{})
	if order in ["move","withdraw"]:
		var goal: Dictionary=target if target.has("x") else t.options.byId.get(id,defaults()).get("rally",{})
		if goal.is_empty() and order=="withdraw":goal=t.home.get(id,{})
		if goal.has("x") and Routes.point(ship).distance_to(Vector2(goal.x,goal.y))<14.0 and Vector2(ship.vx,ship.vy).length()<8.0:
			accept_command(st,ship,"hold",{"x":float(ship.x),"y":float(ship.y)},true)
			t.reasons[id]="Holding at destination" if order=="move" else "Holding at rally point"
	elif order=="escort" and target.has("shipId") and _live(st,str(target.shipId)).is_empty():
		accept_command(st,ship,"hold",{"x":float(ship.x),"y":float(ship.y)},true)
		t.reasons[id]="Escort leader lost; holding position"
	elif order=="attack":
		var target_id: String=str(target.get("shipId",""))
		var lost: bool=not target_id.is_empty() and _live(st,target_id).is_empty()
		var latest: float=-INF
		for value in ship.get("mountShotTimes",{}).values():latest=maxf(latest,float(value))
		var since: float=float(t.orderTimes.get(id,st.time))
		if lost or (float(st.time)-maxf(since,latest)>18.0):
			if not target_id.is_empty():t.failures[id]=[target_id]
			accept_command(st,ship,"engage",{},true)
			t.reasons[id]="Attack complete; target unavailable" if lost else "Attack could not reach a firing lane; regrouping"

static func _prune(t: Dictionary,live: Dictionary,now: float) -> void:
	for key in ["intents","mountCache","pending","lastDecision","lastSafety","orderTimes","reasons","fireReasons","passes","home","failures","certificationAttempts","lastCertified","safety","retained051","preferences051"]:
		for id in t[key].keys():
			if not live.has(id):t[key].erase(id)
	for id in t.options.byId.keys():
		if not live.has(id):t.options.byId.erase(id)
	for side in t.memory:
		for key in ["byId","reservations"]:
			for id in t.memory[side].get(key,{}).keys():
				if not live.has(id):t.memory[side][key].erase(id)
	for key in t.predictions.keys():
		if float(t.predictions[key].certificate.validUntil)<now-0.001:t.predictions.erase(key)
	# Spent counters need only current live passes, never an ever-growing history.
	var retained: Dictionary={}
	for id in t.passes:
		if not live.has(id):continue
		for mount in t.mountCache.get(id,{}).get("mounts",[]):
			var key: String=Fire.pass_key(id,str(mount.id),int(live[id].get("orderRevision",0)),str(t.passes[id].id))
			if t.salvoSpent.has(key):retained[key]=t.salvoSpent[key]
	t.salvoSpent=retained

static func safety_check(st: Dictionary,ship: Dictionary,frame_cache=null) -> void:
	var t: Dictionary=st.tactical
	var id: String=str(ship.id)
	var now: float=float(st.time)
	var previous: Dictionary=t.safety.get(id,{})
	var age: float=now-float(t.lastSafety.get(id,0.0))
	# Resolve current condition before the cadence gate, then share that status.
	# Battle may lend its checked projection until contact/projectile writes.
	var status: Dictionary=Damage._read_status_in_phase043(ship,frame_cache)
	var heat: Vector2=Vector2.ZERO
	if float(ship.fire)>0.0 or (not previous.is_empty() and (float(ship.hp)<float(previous.hp) or float(ship.engine)<float(previous.engine))):heat=Certification._heat_wear(ship,age)
	var equipment_previous: Dictionary=previous
	if not previous.is_empty() and heat.y>0.0 and previous.has("moduleHpSum"):
		equipment_previous=previous.duplicate()
		equipment_previous.moduleHpSum=float(previous.moduleHpSum)-float(heat.y)
	var equip_abrupt: bool=EquipmentCombat.safety_abrupt(ship,equipment_previous,status,frame_cache)
	var abrupt: bool=not previous.is_empty() and (float(ship.hp)<float(previous.hp)-float(heat.x)-0.0001 or float(ship.crew)<float(previous.crew)-0.0001 or float(ship.engine)<float(previous.engine)-float(heat.y)-0.0001 or equip_abrupt)
	var opts: Dictionary=t.options.byId.get(id,defaults())
	var doctrine: String=str(opts.doctrine)
	var hp_limit: float=0.60 if doctrine=="cautious" else (0.30 if doctrine=="aggressive" else 0.45)
	var flood_limit: float=0.30 if doctrine=="cautious" else (0.60 if doctrine=="aggressive" else 0.45)
	var net: float=float(status.inflow)-float(status.bailing)
	var sinking: bool=net>0.0 and (float(ship.capacity)-float(ship.water))/net<8.0
	var danger: bool=float(ship.hp)/maxf(1.0,float(ship.maxHp))<=hp_limit or float(ship.water)/maxf(1.0,float(ship.capacity))>=flood_limit or float(ship.fire)>=25.0 or sinking
	if age<0.1-0.000001 and not abrupt and not previous.is_empty() and danger==bool(previous.get("danger",danger)):return
	var allowed: bool=str(ship.get("order","engage"))=="engage" or bool(opts.conditionalWithdrawal)
	var equip_mask: float=EquipmentCombat.working_mask(ship,status,frame_cache)
	var prio_code: float=EquipmentCombat.priority_code(status)
	var discrete_equip: bool=not previous.is_empty() and ((previous.has("equipMask") and absf(equip_mask-float(previous.get("equipMask",equip_mask)))>0.001) or (previous.has("repairPriorityCode") and absf(prio_code-float(previous.get("repairPriorityCode",prio_code)))>0.001))
	t.safety[id]={"checkedAt":now,"hp":float(ship.hp),"crew":float(ship.crew),"engine":float(ship.engine),"water":float(ship.water),"netFlood":net,"danger":danger,"withdraw":danger and allowed,"speedFactor":float(status.speedFactor),"equipMask":equip_mask,"repairPriorityCode":prio_code,"moduleHpSum":EquipmentCombat.module_hp_sum(ship)}
	t.lastSafety[id]=now;t.metrics.safetyAges.append(age)
	t.counters.oldestSafetyAge=maxf(float(t.counters.oldestSafetyAge),age)
	if age>0.1+0.000001:t.counters.lateSafety+=1
	# This is an actual condition/authority reevaluation, separate from the fair
	# physical-certification queue. It cannot invent an unchecked escape path.
	if danger and allowed and id!=str(t.manualId) and not bool(previous.get("withdraw",false)):
		_drop_retained051(t,id);t.certificationAttempts[id]=-2.0
		if not t.pending.has(id):t.pending[id]=now
		t.reasons[id]="Fire or flooding danger; seeking a safe local rally"
	elif (abrupt or discrete_equip) and id!=str(t.manualId):
		_drop_retained051(t,id);t.certificationAttempts[id]=-2.0
		if not t.pending.has(id):t.pending[id]=now

static func _reserved_path(st: Dictionary,side: String,ship: Dictionary,candidate: Dictionary) -> String:
	# Reject a known swept conflict BEFORE the one physical rollout. A still
	# repeats its authoritative final check after B certifies the chosen route.
	var t: Dictionary=st.tactical
	# Match current physical-prefix time for renewable MAIN planning claims.
	# The same horizon reaches final resolution; future helm/fire stay live.
	var shape: Dictionary=Stations._reservation_begin051(candidate,ship,float(st.time),Planner.CERT_PREFIX_SECONDS)
	var counters: Dictionary={"clearanceTests":int(t.budget.clearanceTests),"clearanceExhausted":0}
	var status: String="valid"
	for other_id in t.memory[side].get("reservations",{}):
		if str(other_id)==str(ship.id):continue
		var other: Dictionary=t.memory[side].reservations[other_id]
		if float(other.get("until",0.0))<=float(st.time):continue
		if Stations._conflict_begin051(shape,other,counters,int(t.budget.clearanceLimit)):
			status="pending" if int(counters.clearanceExhausted)>0 else "blocked"
			break
	t.budget.clearanceTests=int(counters.clearanceTests)
	t.budget.exhaustions+=int(counters.clearanceExhausted)
	return status

static func _retained_observation051(st: Dictionary,id: String,frame_cache,current051: Dictionary,share051: bool=false) -> Dictionary:
	# One pure semantic read may cross ONLY the wait/observe seam in this begin.
	# Main has not moved/fired/published this owner between those two readers;
	# normal current/phase/event/physical guards still run at consumption.
	var t: Dictionary=st.tactical
	var ship: Dictionary=t.ships[id]
	var side: String=str(ship.team)
	var context: Dictionary=_begin_context051(st,side,frame_cache,current051)
	var own: Dictionary=_begin_owner051(st,id,frame_cache,current051)
	var previous: Dictionary=t.memory[side].byId.get(id,{})
	var shared: Dictionary=current051.get("retainedObservation051",{}).get(id,{})
	if not shared.is_empty():
		current051.retainedObservation051.erase(id) # Transfer once, including an empty result.
		if not is_same(shared.owner,ship) or not is_same(shared.own,own) or not is_same(shared.observed,t.observed.get(id)) or not is_same(shared.previous,previous):return {}
		if int(shared.revision)!=int(t.snapshotRevision) or float(shared.at)!=float(st.time):return {}
		return shared.decision
	own.orderSince=float(t.orderTimes.get(id,0.0));own.failedTargetIds=t.failures.get(id,[])
	var old_owner: Dictionary=context[id]
	context[id]=own
	var view051: Dictionary={"time":float(st.time),"side":side,"options":t.options,"groups":t.groups,"ships":context.values(),"mission":current051.mission}
	var decision: Dictionary=Planner._observe_retained051(view051,own,previous,context)
	context[id]=old_owner
	if share051:
		if not current051.has("retainedObservation051"):current051.retainedObservation051={}
		current051.retainedObservation051[id]={"owner":ship,"own":own,"observed":t.observed[id],"previous":previous,"revision":int(t.snapshotRevision),"at":float(st.time),"decision":decision}
	return decision

static func _worker_wait_guard051(st: Dictionary,id: String,slot: Dictionary,frame_cache,current051: Dictionary) -> bool:
	# An unfinished preference cannot justify delaying changed current inputs.
	# This pure retained observer neither publishes memory nor renews authority.
	var t: Dictionary=st.tactical
	var ship: Dictionary=t.ships[id]
	var side: String=str(ship.team)
	var baseline: Dictionary=slot.guards[id].memory
	var previous: Dictionary=t.memory[side].byId.get(id,{})
	if baseline.is_empty() or previous.is_empty():return false
	var keys: Array=["role","phase","targetId","leaderId","firingPassId","passSequence","passShots","passShortShots","passSpent","localRecovery","phaseSince","passSince","passFirstShotAt","passOpportunitySince","shotTimes","lastUsefulShot","safeSince"]
	for key: String in keys:
		if previous.get(key)!=baseline.get(key):return false
	for key: String in ["targetId","leaderId"]:
		var target_id: String=str(previous.get(key,""))
		if target_id.is_empty():continue
		var target: Dictionary=t.ships.get(target_id,{})
		if target.is_empty() or not is_same(target,slot.owners.get(target_id)):return false
		if (str(target.team)==side)!=(key=="leaderId"):return false
	if not _boarding_contact(st,ship,frame_cache).is_empty():return false
	for other: Dictionary in t.ships.values():
		if str(ship.order)!="board" and other.team!=ship.team and Roles.pos(ship).distance_to(Roles.pos(other))<Routes.navigation_radius(ship)+Routes.navigation_radius(other)+24.0:return false
	var observed: Dictionary=_retained_observation051(st,id,frame_cache,current051,true)
	if observed.is_empty():return false
	for key: String in keys:
		if observed.state.get(key)!=previous.get(key):return false
	return true

static func begin(st: Dictionary,dt: float,input: Dictionary={},frame_cache=null) -> void:
	var begin_started: int=Time.get_ticks_usec()
	Planner._poll_tasks051()
	if _runtime_profile043_enabled:_runtime_profile043_counts.beginCalls+=1
	var t: Dictionary=ensure(st)
	t.dt=dt;t.snapshotRevision+=1
	t.metrics={"aiUs":0,"activeCount":0,"normalLimit":0,"decisionAges":[],"safetyAges":[],"certificateAges":[],"certificationAges":[],"certificationAttemptAges":[],"orderApplyAges":[],"pendingAges":[],"droppedDecisions":0}
	# Existing per-step phase clocks stay separate from optional cumulative counts.
	# liveCertification is inside certification; helmCurrent/helmSafety are
	# inside helmTotal. These clocks never participate in a tactical decision.
	t.metrics.planningDetailUs={"observation":0,"snapshots":0,"proposals":0,"certification":0,"physicalCertification":0,"liveCertification":0,"resolution":0,"beginTotal":0,"helmCurrent":0,"helmSafety":0,"helmTotal":0}
	t.metrics.planningCalls={"candidates":0,"certify":0,"helm":0}
	var detail: Dictionary=t.metrics.planningDetailUs
	var phase_started: int=0
	var profile051: bool=_runtime_profile043_enabled
	var profile_started051: int=0
	if profile051:
		# Main-only opt-in subclocks. Each is contained in observation or
		# certification; existing liveCertification is the physical call below.
		detail.observationTerrain=0;detail.observationPrep=0;detail.observationPruneGrid=0
		detail.observationSafety=0;detail.observationSelection=0
		detail.certificationInputs=0;detail.certificationValidation=0
		detail.certificationRefine=0;detail.certificationAdopt=0;detail.certificationReservedPath=0
	t.budget={"fullRoutes":0,"cacheHits":0,"rollouts":0,"samples":0,"clearanceTests":0,"exhaustions":0,"rolled":{},"clearanceLimit":2900}
	t.budget.separatingEgress051=true # Shared by owned planning and every actual helm step.
	if profile051:
		t.budget.profileRoutes051=true # Only this main-owned budget, never worker capsules.
		profile_started051=Time.get_ticks_usec()
	t.geometry=Routes.terrain(st)
	if profile051:
		detail.observationTerrain=Time.get_ticks_usec()-profile_started051
		profile_started051=Time.get_ticks_usec()
	t.ships={};t.observed={}
	for ship in st.ships:
		if ship.sunk or ship.get("captureSecured",false):continue
		var id: String=str(ship.id)
		t.ships[id]=ship
		_order_lifetime(st,ship)
		t.observed[id]=_observed(ship,refresh_mounts(st,ship,frame_cache),true)
	if profile051:
		detail.observationPrep=Time.get_ticks_usec()-profile_started051
		profile_started051=Time.get_ticks_usec()
	_prune(t,t.ships,float(st.time))
	t.cells=Routes.grid(t.observed.values(),true)
	if profile051:
		detail.observationPruneGrid=Time.get_ticks_usec()-profile_started051
		profile_started051=Time.get_ticks_usec()
	var manual: bool=input.get("manual",false)==true or not st.get("autopilot",true)
	var new_manual_id: String=str(st.get("playerId","")) if manual else ""
	if new_manual_id!=str(t.manualId):
		if not str(t.manualId).is_empty():
			t.certificationAttempts[t.manualId]=-2.0;t.lastDecision[t.manualId]=-1.0
			_drop_retained051(t,str(t.manualId))
		if not new_manual_id.is_empty():_drop_retained051(t,new_manual_id)
		t.manualId=new_manual_id
	for ship in t.ships.values():safety_check(st,ship,frame_cache)
	if profile051:
		detail.observationSafety=Time.get_ticks_usec()-profile_started051
		profile_started051=Time.get_ticks_usec()
	var queued: Array=t.ships.keys()
	# Oldest decisions across BOTH sides own the fixed due slots, preserving the
	# <=0.2s observation cadence. Actual certification attempts break age ties;
	# budget-only deferral still never impersonates physical certification.
	queued.sort_custom(func(a,b):
		var aa: float=float(t.certificationAttempts.get(a,-1.0))
		var bb: float=float(t.certificationAttempts.get(b,-1.0))
		var ap: float=float(t.lastDecision.get(a,0.0))
		var bp: float=float(t.lastDecision.get(b,0.0))
		if ap!=bp:return ap<bp
		return aa<bb if aa!=bb else str(a)<str(b))
	var cap: int=maxi(1,ceili(float(queued.size())/10.0))
	t.metrics.activeCount=queued.size();t.metrics.normalLimit=cap
	var due: Array=[]
	var observed_due051: int=0
	var selected_due051: int=0
	var current051: Dictionary={}
	for id in queued:
		if id==t.manualId:continue
		var certified_age: float=float(st.time)-float(t.lastCertified.get(id,0.0))
		t.metrics.certificationAges.append(certified_age)
		# Renew before the existing 0.2s lease ends. Commands and rejected
		# maneuvers remain immediately eligible; stable plans need no per-tick
		# proposal, full route certification or detached world reconstruction.
		var last: float=float(t.lastDecision.get(id,-1.0))
		# A rejected route must not reconstruct/reject the same world at 60Hz.
		# Existing command/condition/control invalidations set last=-1 and bypass
		# this bounded retry delay. Live helm/fire checks never wait for it.
		var interval: float=Planner.OBSERVATION_SECONDS051 if t.has("workers051") else (0.15 if t.intents.has(id) else 0.1)
		if last>=0.0 and float(st.time)-last<interval-0.000001:continue
		# Waiting owns a fair selection slot, never an observation or authority.
		if selected_due051>=cap:continue
		selected_due051+=1
		if Planner._waiting_worker051(st,str(id),_worker_capability051,_worker_wait_guard051,frame_cache,current051):continue
		# Consume a terminal unfinished generation before a real retained
		# observation can change lastDecision and move its handoff deadline.
		var expired_slot051: Dictionary=Planner._member_slot051(t,str(id))
		if not expired_slot051.is_empty() and not bool(expired_slot051.joined) and float(st.time)>=Planner._worker_wait_until051(st,str(id),expired_slot051)-0.000001:
			var expired051: Dictionary=Planner._take_worker051(st,str(t.ships[id].team),[id],_worker_capability051,frame_cache,_worker_wait_guard051,current051)
			if _runtime_profile043_enabled:_runtime_profile043_counts.workerDrops+=int(expired051.get("dropped051",0))
		observed_due051+=1
		if not _observe_retained051(st,str(id),frame_cache,current051):due.append(id)
	if _runtime_profile043_enabled:
		_runtime_profile043_counts.retainedDue+=observed_due051-due.size()
		_runtime_profile043_counts.fullDue+=due.size()
	if profile051:detail.observationSelection=Time.get_ticks_usec()-profile_started051
	detail.observation=Time.get_ticks_usec()-begin_started
	var snapshots: Dictionary={}
	# These bundles and all authority still belong to this synchronous begin.
	# Certification changes clearanceRemaining, not planning observations.
	var planning: Dictionary={}
	var memories: Dictionary={}
	var copies: Dictionary={}
	var proposed: Dictionary={}
	var offers: Dictionary={"player":[],"enemy":[]}
	# Snapshot and propose both sides BEFORE certification spends the shared pool.
	for side in ["player","enemy"]:
		var side_due: Array=[]
		for id in due:
			if t.ships[id].team==side:side_due.append(id)
		if side_due.is_empty():continue
		phase_started=Time.get_ticks_usec()
		var suggestion051: Dictionary=Planner._take_worker051(st,side,side_due,_worker_capability051,frame_cache,_worker_wait_guard051,current051)
		for id in suggestion051.get("pending051",[]):
			side_due.erase(id);due.erase(id)
		# Pending members keep their slot and receive no synchronous duplicate.
		detail.proposals+=Time.get_ticks_usec()-phase_started
		if side_due.is_empty():continue
		phase_started=Time.get_ticks_usec()
		var snapshot: Dictionary=_begin_view051(st,side,side_due,frame_cache,current051)
		snapshots[side]=snapshot
		# Private synchronous readers construct fresh due records. Resolution
		# copies its containers; publication copies only the actual due outputs.
		memories[side]=t.memory[side]
		detail.snapshots+=Time.get_ticks_usec()-phase_started
		phase_started=Time.get_ticks_usec()
		planning[side]=Planner._prepare_with_worker051(snapshot,memories[side],suggestion051,current051.indexes[side],current051.get("freshDecisions051",{}))
		for id in side_due:copies[id]=planning[side].context[id]
		# Admission evidence belongs ONLY to this closed begin and exact offers.
		planning[side].beginView051=snapshot;planning[side].beginOffers051={}
		if _runtime_profile043_enabled and t.has("workers051"):
			var adopted051: int=planning[side].get("workerIds051",[]).size()
			_runtime_profile043_counts.workerAdoptions+=adopted051
			_runtime_profile043_counts.workerDrops+=int(suggestion051.get("dropped051",0))+suggestion051.get("allowed",[]).size()-adopted051
			_runtime_profile043_counts.workerSyncFallbacks+=side_due.size()-adopted051
		var candidates: Array=planning[side].get("candidates",[])
		for raw in candidates:
			if not raw is Dictionary:continue
			var id: String=str(raw.get("shipId",""))
			if not id in side_due:continue
			if not proposed.has(id):proposed[id]=[]
			if proposed[id].size()<8:proposed[id].append(raw)
		detail.proposals+=Time.get_ticks_usec()-phase_started
	# Actual physical work follows GLOBAL fair order, never player-first batches.
	phase_started=Time.get_ticks_usec()
	# These exact terminal proofs borrow only the closed detached observations.
	# They die before resolution, real movement, helm or fire can change inputs.
	var route_proofs051: Routes._BeginProofs051=Routes._begin_proofs051(t.geometry,t.cells,copies)
	for id in due:
		var ship: Dictionary=copies[id]
		var side: String=str(ship.team)
		var snapshot: Dictionary=snapshots[side]
		var real_attempt: bool=false
		if profile051:profile_started051=Time.get_ticks_usec()
		# Both synchronous decisions and joined preferences already selected their
		# bounded targets. Recheck CURRENT hostile membership below, not roles.
		var membership: Array=planning[side].decisions[id].detailedIds
		var candidate_inputs: Dictionary={}
		if profile051:detail.certificationInputs+=Time.get_ticks_usec()-profile_started051
		for raw in proposed.get(id,[]):
			# The existing per-hull allowance cannot certify another offer after a
			# corridor reaches firing checks. Do not refine the remaining routes
			# only to have certification refuse them before its corridor walk.
			if t.budget.rolled.has(id):break
			t.metrics.planningCalls.candidates+=1
			if candidate_inputs.is_empty():
				if profile051:profile_started051=Time.get_ticks_usec()
				candidate_inputs=Certification._begin_inputs(snapshot,ship,membership,true)
				membership=candidate_inputs.detailed
				if profile051:
					detail.certificationInputs+=Time.get_ticks_usec()-profile_started051
					_runtime_profile043_counts.certificationInputCalls+=1
			if profile051:profile_started051=Time.get_ticks_usec()
			# fingerprint(raw).is_empty() only tested this schema. Hash the final
			# routed candidate once; no raw-path JSON/hash is used as authority.
			var rejected051: bool=not Certification._candidate_valid(raw,snapshot,ship,membership,candidate_inputs) or not Stations.valid_candidate(raw) or not order_candidate(snapshot,ship,raw)
			if profile051:detail.certificationValidation+=Time.get_ticks_usec()-profile_started051
			if rejected051:continue
			if profile051:profile_started051=Time.get_ticks_usec()
			var prepared_route051: Dictionary=planning[side].get("routes051",{}).get(str(raw.candidateId),{})
			# Only a joined, current worker preference may lend this negative proof.
			# A fixed endpoint inside land cannot gain a route from a newer pose.
			# Traffic refusals, pending work and blocked chords keep every alternative.
			if id in planning[side].get("workerIds051",[]) and Routes._reject_prepared_static051(t.geometry,ship,raw,prepared_route051):
				real_attempt=true
				t.reasons[id]="Fixed route endpoint cannot fit; checking another station"
				if profile051:_runtime_profile043_counts.workerFixedEndpointRejects051+=1
				continue
			var refined: Dictionary=Routes._refine_begin051(st,t.geometry,ship,raw,t.budget,route_proofs051,Stations.LIVE_TRAFFIC_SECONDS051) if prepared_route051.is_empty() else Routes._adopt_prepared051(st,t.geometry,ship,raw,prepared_route051,t.budget,route_proofs051,Stations.LIVE_TRAFFIC_SECONDS051)
			if profile051:
				if prepared_route051.is_empty():
					detail.certificationRefine+=Time.get_ticks_usec()-profile_started051
					_runtime_profile043_counts.certificationRefineCalls+=1
				else:
					detail.certificationAdopt+=Time.get_ticks_usec()-profile_started051
					_runtime_profile043_counts.certificationAdoptCalls+=1
			var candidate: Dictionary=refined.candidate
			if refined.status=="valid" and str(ship.get("order","engage"))=="engage" and candidate.fireMountIds.is_empty():
				if profile051:profile_started051=Time.get_ticks_usec()
				var reservation_status: String=_reserved_path(st,side,ship,candidate)
				if profile051:
					detail.certificationReservedPath+=Time.get_ticks_usec()-profile_started051
					_runtime_profile043_counts.certificationReservedPathCalls+=1
				if reservation_status!="valid":
					t.reasons[id]="Checking reserved escape geometry" if reservation_status=="pending" else "Reserved escape blocked; checking another exit"
					if reservation_status=="pending":break
					real_attempt=true
					continue
			if profile051:profile_started051=Time.get_ticks_usec()
			# A denied corridor cannot acquire authority. Validate its final shape
			# without serializing/hashing a path that resolution will only reject.
			var fingerprint: String=Planner.fingerprint(candidate) if refined.status=="valid" else ""
			var shape_valid051: bool=not fingerprint.is_empty() if refined.status=="valid" else Stations.valid_candidate(candidate)
			if profile051:detail.certificationValidation+=Time.get_ticks_usec()-profile_started051
			if not shape_valid051:continue
			var cert: Dictionary
			if refined.status=="valid":
				var certify_started: int=Time.get_ticks_usec()
				t.metrics.planningCalls.certify+=1
				cert=Certification._certify_refined_live(st,snapshot,ship,refined,fingerprint,t.budget,membership,frame_cache,candidate_inputs)
				detail.liveCertification+=Time.get_ticks_usec()-certify_started
			else:
				cert=Certification._begin_certificate(snapshot,ship,candidate,fingerprint,candidate_inputs)
				cert.status=refined.status
				cert.reason=refined.get("reason","Checking a route around land" if refined.status=="pending" else "No clear route to this station")
			if cert.status in ["valid","blocked"] or int(cert.rolloutSamples)>0:real_attempt=true
			var offer051: Dictionary=_seal_begin_offer051(raw,candidate,cert,fingerprint)
			if offer051.is_empty():t.counters.rejectedIntents+=1;continue
			offers[side].append(offer051)
			planning[side].beginOffers051[str(candidate.candidateId)]=offer051
			t.reasons[id]=str(cert.reason)
			if cert.status=="valid":break
		if real_attempt or proposed.get(id,[]).is_empty():
			t.metrics.certificationAttemptAges.append(maxf(0.0,float(st.time)-maxf(0.0,float(t.certificationAttempts.get(id,0.0)))))
			t.certificationAttempts[id]=float(st.time)
	Routes._close_begin_proofs051(route_proofs051)
	detail.certification=Time.get_ticks_usec()-phase_started
	# Alternate resolution priority too: reservation accounting has the same cap.
	phase_started=Time.get_ticks_usec()
	var side_order: Array=["player","enemy"] if int(t.snapshotRevision)%2==1 else ["enemy","player"]
	for side in side_order:
		if not snapshots.has(side):continue
		var snapshot: Dictionary=snapshots[side]
		snapshot.options.clearanceRemaining=maxi(0,int(t.budget.clearanceLimit)-int(t.budget.clearanceTests))
		var resolved: Dictionary=Planner._resolve_planned(snapshot,memories[side],offers[side],planning[side],Planner.CERT_PREFIX_SECONDS)
		var spent: int=int(resolved.get("counters",{}).get("clearanceTests",0))
		if spent<0 or spent>int(snapshot.options.clearanceRemaining):
			t.counters.rejectedIntents+=1;continue
		t.budget.clearanceTests+=spent
		_publish(st,snapshot,resolved,offers[side],frame_cache,planning[side])
		for id in snapshot.dueIds:
			var previous_time: float=float(t.lastDecision.get(id,0.0))
			if previous_time<0.0:previous_time=float(t.orderTimes.get(id,st.time))
			var age: float=float(st.time)-previous_time
			t.metrics.decisionAges.append(age)
			t.counters.oldestDecisionAge=maxf(float(t.counters.oldestDecisionAge),age)
			if age>0.2+0.000001:t.counters.lateDecisions+=1
			t.lastDecision[id]=float(st.time);t.counters.decisions+=1
			var intent: Dictionary=t.intents.get(id,{})
			if not intent.is_empty() and int(intent.get("snapshotRevision",-1))==int(t.snapshotRevision) and Certification.current(st,t.ships[id],intent,0.0,frame_cache).ok:
				t.lastCertified[id]=float(st.time);t.pending.erase(id)
			elif not t.pending.has(id):t.pending[id]=float(st.time)
	for id in t.pending:
		var age: float=float(st.time)-float(t.pending[id])
		t.metrics.pendingAges.append(age)
		t.counters.oldestPendingAge=maxf(float(t.counters.oldestPendingAge),age)
	detail.resolution=Time.get_ticks_usec()-phase_started
	# One deadline-ordered SIDE batch per 150ms; completion never refills it.
	# Pure 2900 traffic/128 proof/4 route allowances and main checks stay unchanged.
	phase_started=Time.get_ticks_usec()
	var worker_tally051: Dictionary=Planner._dispatch_batch051(st,queued,_worker_view051,_worker_capability051,frame_cache,planning)
	if _runtime_profile043_enabled:
		_runtime_profile043_counts.workerDispatches+=int(worker_tally051.dispatches)
		_runtime_profile043_counts.workerDrops+=int(worker_tally051.drops)
	detail.proposals+=Time.get_ticks_usec()-phase_started
	t.budget.clearanceLimit=4096 # Reserved current helm/fire legality work.
	detail.beginTotal=Time.get_ticks_usec()-begin_started

static func _seal_begin_offer051(source: Dictionary,candidate: Dictionary,cert: Dictionary,fingerprint: String) -> Dictionary:
	# The raw request passed current membership/order checks, and the routed
	# candidate just passed complete schema validation. Route
	# refinement may change paths ONLY. Seal the exact values before lending
	# their admission to resolve/publication, never a later tick/public caller.
	if (fingerprint.is_empty() and cert.get("status") not in ["pending","blocked"]) or str(cert.get("pathFingerprint",""))!=fingerprint or not Stations.same_request(source,candidate):return {}
	# Fixed schemas: seal only their known containers, without recursive walks
	# or deep copies of every scalar on every rejected route offer.
	for key in ["approach","pass","exit","fireMountIds"]:candidate[key].make_read_only()
	if candidate.has("fireMountTargets"):candidate.fireMountTargets.make_read_only()
	candidate.make_read_only()
	cert.fireWindow.mountIds.make_read_only();cert.fireWindow.mountTargets.make_read_only()
	cert.fireWindow.make_read_only();cert.checkedPose.make_read_only();cert.make_read_only()
	var offer: Dictionary={"candidate":candidate,"certificate":cert,"fingerprint051":fingerprint}
	offer.make_read_only()
	return offer

static func _publish(st: Dictionary,snapshot: Dictionary,resolved: Dictionary,offers: Array,frame_cache=null,prepared051: Dictionary={}) -> void:
	var t: Dictionary=st.tactical
	var side: String=str(snapshot.side)
	var accepted: Dictionary={}
	var offered: Dictionary={}
	if not resolved.get("byId",{}) is Dictionary:return
	for offer in offers:
		if offer.certificate.status=="valid":offered[str(offer.candidate.candidateId)]=offer
	for id in resolved.get("byId",{}):
		var intent=resolved.byId[id]
		if not id in snapshot.dueIds or not t.ships.has(id) or not intent is Dictionary:continue
		var offer: Dictionary=offered.get(str(intent.get("candidateId","")),{})
		if offer.is_empty():
			if str(intent.get("phase",""))=="pending" and str(intent.get("reason","")).length()<=128:t.reasons[id]=str(intent.reason)
			else:t.counters.rejectedIntents+=1
			continue
		var candidate: Dictionary=offer.candidate
		var cert: Dictionary=offer.certificate
		var admitted051: bool=Planner._admitted_begin_offer051(snapshot,prepared051,offer)
		var fingerprint051: String=str(offer.fingerprint051) if admitted051 else Planner.fingerprint(candidate)
		if str(candidate.shipId)!=str(id) or str(intent.get("pathFingerprint",""))!=fingerprint051 or str(intent.get("pathFingerprint",""))!=str(cert.pathFingerprint) or int(intent.get("snapshotRevision",-1))!=int(snapshot.snapshotRevision) or int(intent.get("orderRevision",-1))!=int(t.ships[id].get("orderRevision",0)):t.counters.rejectedIntents+=1;continue
		if not intent.get("waypoints",[]) is Array or not intent.get("exit",[]) is Array or intent.waypoints.size()+intent.exit.size()>24:continue
		var combined: Array=intent.waypoints.duplicate();combined.append_array(intent.exit)
		if combined!=Certification.paths(candidate) or str(intent.get("targetId",""))!=str(candidate.targetId) or str(intent.get("leaderId",""))!=str(candidate.leaderId) or str(intent.get("role",""))!=str(candidate.role) or int(intent.get("sector",-2))!=int(candidate.sector):t.counters.rejectedIntents+=1;continue
		if not (intent.get("validUntil") is int or intent.get("validUntil") is float) or not is_finite(float(intent.validUntil)) or float(intent.validUntil)>float(cert.validUntil) or float(intent.validUntil)<float(st.time):continue
		if str(intent.get("reason","")).length()>128 or not intent.get("fireGate",{}) is Dictionary:continue
		var valid: bool=true
		var installed: Array=[]
		for mount in t.mountCache[id].mounts:installed.append(str(mount.id))
		var window: Dictionary=cert.get("fireWindow",{}) if cert.get("fireWindow") is Dictionary else {}
		var has_window_targets: bool=window.has("mountTargets")
		var window_targets: Dictionary=window.get("mountTargets",{}) if window.get("mountTargets") is Dictionary else {}
		if (candidate.has("fireMountTargets") and not window.get("mountTargets") is Dictionary) or (has_window_targets and (not window.get("mountTargets") is Dictionary or window_targets.size()!=window.get("mountIds",[]).size())):
			t.counters.rejectedIntents+=1;continue
		var distinct_targets: Dictionary={}
		if not str(candidate.get("targetId","")).is_empty():distinct_targets[str(candidate.targetId)]=true
		for mount_id in intent.get("fireGate",{}):
			var gate=intent.fireGate[mount_id]
			if not gate is Dictionary or not mount_id in installed or not gate.get("permit",false) is bool or not gate.get("shotLimit",0) is int or int(gate.get("shotLimit",0))<0 or str(gate.get("reason","")).length()>128 or str(gate.get("firingPassId","")).length()>128:valid=false;break
			if bool(gate.get("permit",false)):
				var expected_target: String=Certification.mount_target(candidate,str(mount_id))
				var live_target: Dictionary=t.ships.get(expected_target,{})
				if not mount_id in candidate.fireMountIds or not mount_id in window.get("mountIds",[]) or str(gate.get("targetId",""))!=expected_target or live_target.is_empty() or str(live_target.get("team",""))==side:valid=false;break
				if (candidate.has("fireMountTargets") or has_window_targets) and (not window_targets.has(mount_id) or str(window_targets.get(mount_id,""))!=expected_target):valid=false;break
				distinct_targets[expected_target]=true
		if not valid or distinct_targets.size()>4:t.counters.rejectedIntents+=1;continue
		accepted[id]=intent.duplicate(true)
	var original_choices051: Dictionary=prepared051.get("originalPreferenceChosenAt051",{})
	for id in accepted.keys():
		# A fresh certificate does not renew semantic eligibility. Only a new
		# full role choice may start another .45s preference window.
		if original_choices051.has(id):
			var original: float=float(original_choices051[id])
			# Planner has checked this begin's owner/generation/time or joined a
			# current worker choice. Its original may be an old semantic choice
			# OR a newly computed full choice; neither starts at recertification.
			if not is_finite(original) or original<0.0 or float(st.time)<original or float(st.time)-original>0.45+0.000001:
				accepted.erase(id);_drop_retained051(t,str(id));continue
		t.intents[id]=accepted[id]
		t.retained051.erase(id)
		t.reasons[id]=str(accepted[id].get("reason","Following maneuver"))
		Fire.accept_pass(st,t.ships[id],accepted[id])
		var held: Certification._Retained051=Certification._retain051(st,t.ships[id],accepted[id],t.predictions.get(str(accepted[id].pathFingerprint),{}),frame_cache)
		if held!=null:
			if original_choices051.has(id):held.chosen_at=float(original_choices051[id])
			t.retained051[id]=held
		else:t.preferences051.erase(id)
		if _runtime_profile043_enabled and held!=null:_runtime_profile043_counts.retainedAdmissions+=1
		t.trace.append({"time":float(st.time),"shipId":id,"order":str(t.ships[id].order),"phase":str(accepted[id].get("phase","")),"reason":t.reasons[id],"targetId":str(accepted[id].get("targetId",""))})
	# dueIds alone can publish per-hull memory/reservations; non-due state stays.
	var memory: Dictionary=resolved.get("memory",{})
	for key in ["byId","reservations"]:
		for id in snapshot.dueIds:
			if not memory.get(key,{}) is Dictionary:continue
			# Waiting observations/phase ages must survive a blocked route. They
			# grant no helm/fire permission; only an accepted intent can reserve it.
			if memory[key].has(id) and (key=="byId" or accepted.has(id)):
				var count: Dictionary={"nodes":0}
				if memory[key][id] is Dictionary and bounded_value(memory[key][id],count):t.memory[side][key][id]=memory[key][id].duplicate(true)
			elif not memory[key].has(id):t.memory[side][key].erase(id)
	# Capture semantic predicates AFTER the current decision memory publishes.
	# This detached eligibility never contains the new geometry/fire authority.
	for id in accepted:
		var held=t.retained051.get(id)
		if held is Certification._Retained051:t.preferences051[id]=Certification._preference051(st,t.ships[id],held)

static func bounded_value(value: Variant,count: Dictionary,depth: int=0) -> bool:
	count.nodes+=1
	if depth>8 or int(count.nodes)>2048:return false
	if value is Dictionary:
		if value.size()>64:return false
		for key in value:
			# Native Dictionary dot assignments create StringName textual keys.
			if not (key is String or key is StringName) or str(key).length()>128 or not bounded_value(value[key],count,depth+1):return false
		return true
	if value is Array:
		if value.size()>64:return false
		for child in value:
			if not bounded_value(child,count,depth+1):return false
		return true
	if value is Vector2:return value.is_finite()
	if value is String:return value.length()<=256
	if value is float:return is_finite(value)
	return value==null or value is int or value is bool

static func order_candidate(snapshot: Dictionary,ship: Dictionary,candidate: Dictionary) -> bool:
	var order: String=str(ship.get("order","engage"))
	var target: Dictionary=ship.get("orderTarget",{})
	var opts: Dictionary=snapshot.options.byId.get(str(ship.id),defaults())
	var conditional: bool=bool(opts.conditionalWithdrawal)
	if order in ["move","withdraw","board"] and (not candidate.get("fireMountIds",[]).is_empty() or candidate.has("fireMountTargets")):
		return false
	if order in ["attack","board"] and candidate.has("fireMountTargets"):
		return false
	if order in ["attack","board"] and target.has("shipId"):
		if str(candidate.targetId)!=str(target.shipId) and not (conditional and candidate.fireMountIds.is_empty()):return false
	if order=="escort" and target.has("shipId") and str(candidate.leaderId)!=str(target.shipId) and str(target.shipId)!=str(ship.id):return false
	if order in ["move","hold","withdraw"] and not conditional:
		var goal: Dictionary=opts.rally if order=="withdraw" else target
		if goal.has("x") and (candidate.approach.is_empty() or candidate.approach[-1].distance_to(Vector2(goal.x,goal.y))>0.000001):return false
	return true

static func _drop_retained051(t: Dictionary,id: String,preference_expiry051: bool=false,physical_only051: bool=false) -> void:
	# Semantic-only reuse belongs to pooled fleet planning. Ordinary synchronous
	# encounters must make a full choice after physical authority is lost.
	physical_only051=physical_only051 and t.has("workers051")
	var held=t.retained051.get(id)
	var preference=t.get("preferences051",{}).get(id)
	if held is Certification._Retained051:
		held.step_ok=false
		if physical_only051 and preference is Certification._Preference051:
			# Preserve the latest real capability baseline, not an old lower HP
			# value after repair. No corridor or fire grant survives this transfer.
			preference.capability_inputs=held.capability_inputs.duplicate(true)
			preference.checked_at=maxf(preference.checked_at,held.step_at)
	if not physical_only051:t.get("preferences051",{}).erase(id)
	t.retained051.erase(id);t.intents.erase(id)
	for side in t.memory:t.memory[side].get("reservations",{}).erase(id)
	# Normal expiry removes authority, not the last useful observation. Preserve
	# its generation for a matching prefetch; every urgent/event drop still -1s.
	if not preference_expiry051:t.lastDecision[id]=-1.0

static func _current051(st: Dictionary,ship: Dictionary,intent: Dictionary,pose_offset: float=0.0,frame_cache=null) -> Dictionary:
	var id: String=str(ship.id)
	var held=st.tactical.retained051.get(id)
	if not held is Certification._Retained051:return Certification.current(st,ship,intent,pose_offset,frame_cache)
	var preference=st.tactical.preferences051.get(id)
	var result: Dictionary=Certification._retained_current051(st,ship,held,frame_cache,preference if preference is Certification._Preference051 else null)
	if not result.ok:
		if _runtime_profile043_enabled:
			match str(result.reason):
				"Reconsidering maneuver":_runtime_profile043_counts.retainedMissOwnerDeadline+=1
				"Conditions changed; checking maneuver":_runtime_profile043_counts.retainedMissConditions+=1
				"Target or leader unavailable":_runtime_profile043_counts.retainedMissTarget+=1
				"Damage or capability changed; reassessing":_runtime_profile043_counts.retainedMissCapability+=1
				_:_runtime_profile043_counts.retainedMissOther+=1
		_drop_retained051(st.tactical,id)
	return result

static func _observe_retained051(st: Dictionary,id: String,frame_cache=null,current051: Dictionary={}) -> bool:
	var t: Dictionary=st.tactical
	var held=t.retained051.get(id)
	var preference=t.preferences051.get(id)
	var pooled051: bool=t.has("workers051")
	if not pooled051 and not held is Certification._Retained051:return false
	if not preference is Certification._Preference051:return false
	# Preserve ordinary synchronous reconsideration at .30s. Only pooled fleets
	# may reuse fresh stable semantics up to the ORIGINAL .45s hard deadline;
	# physical drops and recertification never renew that choice timestamp.
	if float(st.time)-preference.chosen_at>=(0.45 if pooled051 else 0.30)-0.000001:
		if _runtime_profile043_enabled:_runtime_profile043_counts.retainedDropTime+=1
		_drop_retained051(t,id,t.has("workers051"));return false
	var ship: Dictionary=t.ships[id]
	if held is Certification._Retained051:
		if not _current051(st,ship,t.intents.get(id,{}),0.0,frame_cache).ok:return false
	elif not Certification._preference_current051(st,ship,preference,frame_cache):
		_drop_retained051(t,id);return false
	if not _boarding_contact(st,ship,frame_cache).is_empty():
		if _runtime_profile043_enabled:_runtime_profile043_counts.retainedDropBoarding+=1
		_drop_retained051(t,id);return false
	var side: String=str(ship.team)
	var previous: Dictionary=t.memory[side].byId.get(id,{})
	var decision: Dictionary=_retained_observation051(st,id,frame_cache,current051)
	var changed: bool=decision.is_empty() or preference.events!=Certification._preference_events051(st,ship,preference.target_id)
	if _runtime_profile043_enabled and changed:_runtime_profile043_counts["retainedDropPhase" if decision.is_empty() else "retainedDropEvents"]+=1
	if held is Certification._Retained051 and int(held.record.index)>=held.points.size() and str(held.intent.phase) in ["approach","stage","align"]:
		if _runtime_profile043_enabled and not changed:_runtime_profile043_counts.retainedDropCompletion+=1
		changed=true
	if not decision.is_empty():
		for key in ["role","phase","targetId","leaderId","firingPassId"]:
			if decision.state.get(key)!=previous.get(key):
				if _runtime_profile043_enabled and not changed:_runtime_profile043_counts.retainedDropPhase+=1
				changed=true
	if changed:_drop_retained051(t,id);return false
	if not held is Certification._Retained051:
		# This is a fresh complete decision for THIS begin, not stored authority.
		# Planner consumes it once, then generates current paths/certification.
		if not current051.has("freshDecisions051"):current051.freshDecisions051={}
		current051.freshDecisions051[id]={"owner":current051.owners[id],"revision":int(t.snapshotRevision),"at":float(st.time),"decision":decision.duplicate(true),"originalPreferenceChosenAt":preference.chosen_at}
		return false
	t.memory[side].byId[id]=decision.state
	var age: float=float(st.time)-float(t.lastDecision.get(id,st.time))
	t.metrics.decisionAges.append(age);t.counters.oldestDecisionAge=maxf(float(t.counters.oldestDecisionAge),age)
	if age>0.2+0.000001:t.counters.lateDecisions+=1
	t.lastDecision[id]=float(st.time);t.counters.decisions+=1
	return true

static func helm(st: Dictionary,ship: Dictionary,frame_cache=null) -> Dictionary:
	var helm_started: int=Time.get_ticks_usec()
	var t: Dictionary=st.tactical
	var detail: Dictionary=t.metrics.get("planningDetailUs",{})
	if not detail.is_empty():t.metrics.planningCalls.helm+=1
	var id: String=str(ship.id)
	var intent: Dictionary=t.intents.get(id,{})
	var current_started: int=Time.get_ticks_usec()
	var current: Dictionary=_current051(st,ship,intent,0.0,frame_cache)
	if not detail.is_empty():detail.helmCurrent+=Time.get_ticks_usec()-current_started
	if not t.get("appliedRevisions") is Dictionary:t.appliedRevisions={}
	if int(t.appliedRevisions.get(id,-1))!=int(ship.get("orderRevision",0)):
		t.metrics.orderApplyAges.append(maxf(0.0,float(st.time)-float(t.orderTimes.get(id,st.time))))
		t.appliedRevisions[id]=int(ship.get("orderRevision",0))
	if not current.ok:
		if not intent.is_empty():_drop_retained051(t,id)
		if not t.pending.has(id):t.pending[id]=float(st.time)
		if not intent.is_empty() or not t.reasons.has(id):t.reasons[id]=str(current.reason)
		var brake_started: int=Time.get_ticks_usec()
		var braked: Dictionary=Certification.brake(st,ship,t.budget,str(t.reasons[id]),frame_cache)
		if not detail.is_empty():
			detail.helmSafety+=Time.get_ticks_usec()-brake_started
			detail.helmTotal+=Time.get_ticks_usec()-helm_started
		return braked
	var target_id: String=str(intent.get("targetId",""))
	var target: Dictionary=t.observed.get(target_id,{})
	if not target_id.is_empty() and (target.is_empty() or target.team==ship.team):
		_drop_retained051(t,id)
		var brake_started: int=Time.get_ticks_usec()
		var braked: Dictionary=Certification.brake(st,ship,t.budget,"Target unavailable; reassessing",frame_cache)
		if not detail.is_empty():
			detail.helmSafety+=Time.get_ticks_usec()-brake_started
			detail.helmTotal+=Time.get_ticks_usec()-helm_started
		return braked
	var record: Dictionary=current.record
	t.metrics.certificateAges.append(maxf(0.0,float(st.time)-float(record.certificate.checkedAt)))
	var held=t.retained051.get(id)
	var points: Array=held.points if held is Certification._Retained051 else Certification.execution(record.candidate)
	var primary: Array=held.primary if held is Certification._Retained051 else Certification.primary_mounts(t.mountCache[id].mounts,record.candidate)
	var control: Dictionary=Certification.steering(ship,points,int(record.get("index",0)),target,primary)
	record.index=int(control.index)
	var safety_started: int=Time.get_ticks_usec()
	var safe: Dictionary=Certification._crowd_step051(st,ship,record.candidate,control,t.budget,frame_cache) if Routes._is_crowd_escape051(record.candidate) else Certification.safe_step(st,ship,control,t.budget,frame_cache)
	if held is Certification._Retained051:
		held.step_at=float(st.time);held.step_ok=not bool(safe.get("blocked",false))
	if not detail.is_empty():detail.helmSafety+=Time.get_ticks_usec()-safety_started
	if safe.get("blocked",false):
		t.reasons[id]=str(safe.reason)
		_drop_retained051(t,id,false,true)
		if not t.pending.has(id):t.pending[id]=float(st.time)
	if not detail.is_empty():detail.helmTotal+=Time.get_ticks_usec()-helm_started
	return safe

static func finish(st: Dictionary,ai_us: int) -> void:
	var t: Dictionary=st.tactical
	t.metrics.aiUs=ai_us
	t.metrics.work={}
	for key in ["fullRoutes","cacheHits","rollouts","samples","clearanceTests","exhaustions"]:t.metrics.work[key]=int(t.budget[key])
	t.metrics.work.cacheEntries=t.routeCache.size()
	# Optional fixed scalar route clocks belong to the same main-owned budget.
	# Routes leaves this absent with profiling off and on all worker budgets.
	if _runtime_profile043_enabled and t.budget.get("profileRoutes051",false) and t.budget.get("routeTiming051") is Dictionary:
		for key in t.budget.routeTiming051:t.metrics.work[key]=int(t.budget.routeTiming051[key])
	for id in t.ships:
		var ship: Dictionary=t.ships[id]
		var intent: Dictionary=t.intents.get(id,{})
		t.trace.append({"sim_time":float(st.time),"hull_uid":str(ship.get("uid",id)),"shipId":id,"encounter_id":str(st.get("mission",{}).get("id","")),"party":str(ship.team),"order":str(ship.order),"intent_reason":str(t.reasons.get(id,"Checking a safe maneuver")),"observed_target":str(intent.get("targetId","")),"role":str(intent.get("role","")),"station":int(intent.get("sector",-1)),"approach_path":intent.get("waypoints",[]).duplicate(),"exit_path":intent.get("exit",[]).duplicate(),"weapon_opportunity":ship.get("mountShotTimes",{}).duplicate(true),"withheld_reason":t.fireReasons.get(id,{}).duplicate(true),"withdrawal_reason":str(t.reasons.get(id,"")) if str(intent.get("phase","")) in ["withdraw","breakaway","regroup","turn-away"] else "","condition":{"hp":float(ship.hp),"water":float(ship.water),"fire":float(ship.fire),"engine":float(ship.engine)},"stores":{"fuel":float(ship.fuel),"ammo":float(ship.ammo),"supplies":float(ship.supplies)},"objective_state":st.get("mission",{}).get("status","")})
	# Both publication and per-hull rows are synchronous within this step. Trim
	# once, keeping the same last 512 rows and the existing Array reference.
	if t.trace.size()>512:t.trace.assign(t.trace.slice(t.trace.size()-512))

static func after_motion(st: Dictionary) -> void:
	# All real helm movement publishes before ANY automatic fire target lookup.
	st.tactical.cells=Routes.grid(st.tactical.ships.values(),true)

static func _battle_fire_gates051(st: Dictionary,ship: Dictionary,frame_cache=null) -> Dictionary:
	# Only Battle's closed fire phase: its prepass has refreshed mutable fittings
	# and decremented/synchronized every real timer. Never retain readiness; the
	# first possibly ready mount takes the unchanged complete current fire path.
	var t: Dictionary=st.tactical
	var id: String=str(ship.id)
	var mounts: Array=t.mountCache[id].mounts
	var choices: Dictionary=t.options.byId.get(id,{}).get("mounts",{})
	var timers: Array=ship.weaponCooldowns
	var order: String=str(ship.get("order","engage"))
	var reasons: Dictionary={}
	for index in range(mounts.size()):
		var mount: Dictionary=mounts[index]
		var mount_id: String=str(mount.id)
		var choice: Dictionary=choices.get(mount_id,{})
		var reason: String=""
		if float(mount.get("damage",0.0))<=0.0:reason="Weapon disabled"
		elif order in ["move","withdraw","board"]:reason="Holding fire during maneuver"
		elif bool(choice.get("hold",false)):reason="Automatic fire held"
		elif float(ship.ammo)<float(mount.ammoCost):reason="Out of ammunition"
		elif float(ship.ammo)-float(mount.ammoCost)<float(choice.get("reserve",0)):reason="Keeping working ammunition reserve"
		elif (index<timers.size() and float(timers[index])>0.0) or (index==0 and float(ship.cooldown)>0.0):reason="Reloading"
		else:return fire_gates(st,ship,frame_cache)
		reasons[mount_id]=reason
	# No current/prediction/route authority is needed to emit nothing. Publish
	# current physical holds even when a previous retained fire window expired.
	t.fireReasons[id]=reasons
	return {}

static func fire_gates(st: Dictionary,ship: Dictionary,frame_cache=null) -> Dictionary:
	var t: Dictionary=st.tactical
	var id: String=str(ship.id)
	var intent: Dictionary=t.intents.get(id,{})
	var out: Dictionary={}
	t.fireReasons[id]={}
	if not _current051(st,ship,intent,float(t.dt),frame_cache).ok:
		for mount in t.mountCache[id].mounts:t.fireReasons[id][str(mount.id)]="Checking the firing maneuver"
		return out
	var mounts: Array=t.mountCache[id].mounts
	var ship_status: Dictionary=Damage._read_status_in_phase043(ship,frame_cache) if not mounts.is_empty() else {}
	var fire_state: Dictionary=st
	var held=t.retained051.get(id)
	if held is Certification._Retained051:
		if not held.step_ok or held.step_at!=float(st.time):return out
		# A current-step fire view, NOT a renewed complete-corridor certificate.
		# Fire.gate keeps every real solution/stores/salvo/ally/land check intact.
		var candidate: Dictionary=held.record.candidate
		var own: Dictionary=ship.duplicate();own.mounts=mounts;own.status=ship_status
		var memory: Dictionary=t.memory[str(ship.team)].byId[id]
		var step_view: Dictionary={"time":float(st.time),"options":t.options}
		var recovery_guns: Array=Roles.solo_recovery_guns(step_view,own,memory)
		if not recovery_guns.is_empty() and not bool(t.safety.get(id,{}).get("withdraw",false)):
			# Only this already-cleared physical step requests these guns. Neither
			# the sealed route nor its nonfiring/expired public window is changed.
			candidate=candidate.duplicate()
			candidate.fireMountIds=recovery_guns
			candidate.erase("fireMountTargets")
		var targets: Dictionary={}
		for mount_id in candidate.fireMountIds:targets[mount_id]=Certification.mount_target(candidate,str(mount_id))
		var step_proof: Dictionary={"scope":"retained-current-step","checkedAt":float(st.time),"validUntil":float(st.time)+float(t.dt),"fireWindow":{"from":float(st.time),"until":float(st.time)+float(t.dt),"mountIds":candidate.fireMountIds,"mountTargets":targets}}
		intent=intent.duplicate();intent.validUntil=step_proof.validUntil
		intent.fireGate=Planner._fire_gates(step_view,own,memory,candidate,step_proof)
		var fire_t: Dictionary=t.duplicate();fire_t.predictions={}
		fire_t.predictions[str(intent.pathFingerprint)]={"candidate":candidate,"certificate":step_proof}
		fire_state=st.duplicate();fire_state.tactical=fire_t
	for index in range(mounts.size()):
		var mount: Dictionary=mounts[index]
		var target_id: String=str(intent.get("fireGate",{}).get(str(mount.id),{}).get("targetId",""))
		var target: Dictionary=t.ships.get(target_id,{})
		var result: Dictionary=Fire.gate(fire_state,ship,mount,index,intent,t.options.byId.get(id,defaults()),target,t.budget,frame_cache,ship_status)
		t.fireReasons[id][str(mount.id)]=str(result.reason)
		if result.ok:result.target=target;out[str(mount.id)]=result
	return out

static func status(st: Dictionary,id: String) -> Dictionary:
	var t: Dictionary=ensure(st)
	var ship: Dictionary=_live(st,id)
	if ship.is_empty() or ship.team!="player":return {}
	var intent: Dictionary=t.intents.get(id,{})
	var manual: bool=id==str(st.get("playerId","")) and (not st.get("autopilot",true) or id==str(t.manualId))
	var paths: Array=[]
	var exits: Array=[]
	var reason: String=str(t.reasons.get(id,"Choosing a safe maneuver"))
	if not manual and not intent.is_empty():
		var checked: Dictionary=_current051(st,ship,intent,float(t.dt))
		if checked.ok:paths=intent.get("waypoints",[]).duplicate();exits=intent.get("exit",[]).duplicate()
		else:reason=str(checked.reason)
	var target: Dictionary=_live(st,str(intent.get("targetId","")))
	var weapons: Dictionary=t.fireReasons.get(id,{}).duplicate(true)
	var mounts: Array=refresh_mounts(st,ship)
	for index in range(mounts.size()):
		var mount: Dictionary=mounts[index]
		var mount_id: String=str(mount.id)
		if manual:
			if EquipmentCombat.mount_factor(ship,mount,index)<=0.01 or float(mount.get("damage",1.0))<=0.0:
				weapons[mount_id]="Weapon disabled"
			else:
				weapons[mount_id]="Out of ammunition" if float(ship.ammo)<float(mount.ammoCost) else ("Reloading" if index<ship.weaponCooldowns.size() and float(ship.weaponCooldowns[index])>0.0 else "Manual aim and trigger")
		else:weapons[mount_id]=player_reason(str(weapons.get(mount_id,"Waiting for a firing opportunity")))
	return {"order":str(ship.order),"reason":"Manual helm and fire; queued order suspended" if manual else player_reason(reason),"role":str(intent.get("role",t.options.byId.get(id,defaults()).role)),"phase":str(intent.get("phase","")),"targetName":str(target.get("name","")),"path":paths,"exit":exits,"weapons":weapons,"options":t.options.byId.get(id,defaults()).duplicate(true),"mounts":mounts.duplicate(true)}

static func player_reason(value: String) -> String:
	var lower: String=value.to_lower()
	for word in ["revision","fingerprint","snapshot","certificate","sector","budget"]:
		if word in lower:return "Holding while a safe approach is checked"
	return value.replace("certified","clear").left(180)
