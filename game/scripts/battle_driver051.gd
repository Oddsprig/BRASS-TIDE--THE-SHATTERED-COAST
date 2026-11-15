extends RefCounted
## Main owns this scheduler and its display. Only the in-flight job owns _state.
const Battle=preload("res://scripts/battle.gd")
const PlayerCommands=preload("res://scripts/battle_commands047.gd")
const Tactical=preload("res://scripts/tactical_runtime.gd")
const Damage=preload("res://scripts/damage.gd")
const Records=preload("res://scripts/equipment_records.gd")
const STEP: float=1.0/30.0
const MAX_STEPS_PER_JOB: int=4
const PUBLIC_TACTICAL: Array=["snapshotRevision","terrainRevision","terrainKey","options","groups","intents","predictions","reasons","fireReasons","trace","counters","metrics","manualId","dt","failures"]
# Acquired through _plain, then written only by numerical combat/objective/
# boarding code. No Objects, Callables, Signals or RIDs may be added to these
# public groups. Unknown state fields and legacy predictions stay sanitized.
const PLAIN_STATE_GROUPS051: Array=["ships","reserves","projectiles","effects","wrecks","islands","mission","location","deployment","log","convoy","escapedShips","captured","convoyOutcome","coastalDefenses","boarding"]

class _Job extends RefCounted:
	var state: Dictionary={}
	var commands: Array=[]
	var input: Dictionary={}
	var steps: int=0
	var completed: int=0
	var boot: bool=false
	var retiring: bool=false
	var publication: Dictionary={}
	var events: Array=[]
	var poses: Dictionary={}
	var receipt: Dictionary={}

var _state: Dictionary={}
var _mirror: Dictionary={}
var _commands: Array=[]
var _events: Array=[]
var _owners: Dictionary={} # Original campaign dictionaries; NEVER given to a job.
var _reserve_owners: Dictionary={}
var _port_owners: Dictionary={}
var _profile_flags: Dictionary={}
var _job: _Job=null
var _task: int=-1
var _sequence: int=0
var _boot: bool=true
var _retired: bool=false
var _claimed: bool=false
var _debt: float=0.0
var _desired_time: float=0.0
var _published_at: int=0
var _poses: Dictionary={"previous":{},"current":{}}
var _telemetry: Dictionary={"workerStepHz":30,"workerThreadId":-1,"completedSteps":0,"stateTime":0.0,"workerJobUs":0,"simulationUs":0,"snapshotUs":0,"stepsInJob":0,"mainPollUs":0,"simulationLagSeconds":0.0,"jobsCompleted":0,"lastCommandSequence":0,"commandResults":[],"totalWorkerJobUs":0,"totalSimulationUs":0,"totalSnapshotUs":0,"lastSimulationJobUs":0,"lastSimulationUs":0,"lastSimulationSnapshotUs":0}

func _init(initial: Dictionary) -> void:
	# Acquire only at a Main-owned encounter boundary. Never clone phase/goal/RNG
	# Objects through duplicate(true): those objects would still alias live state.
	if not Tactical.claim_battle_worker051():
		_retired=true
		_mirror={"startError":"Another battle driver still owns the simulation.","result":"lost","ships":[],"projectiles":[],"effects":[],"wrecks":[],"islands":[],"time":0.0}
		return
	_claimed=true
	Tactical.retire_planning051(initial)
	Tactical.Planner._poll_tasks051(true)
	Battle._close_damage_owned051(initial)
	_profile_flags={"damage":bool(Damage.runtime_profile043().get("enabled",false)),"records":bool(Records.runtime_profile043().get("enabled",false)),"tactical":bool(Tactical.runtime_profile043().get("enabled",false))}
	Damage.set_runtime_profile043(false)
	Records.set_runtime_profile043(false)
	Tactical.set_runtime_profile043(false)
	for ship: Dictionary in initial.get("ships",[]):_remember_owner(ship)
	for side in initial.get("reserves",{}):_reserve_owners[side]=initial.reserves[side].duplicate()
	for fort: Dictionary in initial.get("coastalDefenses",[]):
		var port: Dictionary=fort.get("port",{})
		if not port.is_empty():_port_owners[str(port.get("id",""))]=port
	for key in initial:
		if key in ["tactical","rng","_damageOwned051","_battleDriver051","_battleMirror051"]:continue
		if not initial[key] is Object:_state[key]=_plain(initial[key])
	var random: RandomNumberGenerator=RandomNumberGenerator.new()
	if initial.get("rng") is RandomNumberGenerator:
		random.seed=initial.rng.seed;random.state=initial.rng.state
	_state.rng=random # New RNG; exclusive worker ownership after construction.
	_relink_ship_aliases(_state)
	var t: Dictionary=Tactical.ensure(_state)
	for key in ["options","groups","home","orderTimes"]:
		if initial.get("tactical",{}).has(key):t[key]=_plain(initial.tactical[key])
	_desired_time=float(_state.get("time",0.0))
	_telemetry.stateTime=_desired_time
	# Before submission Main still owns the detached state. This one initial
	# display copy performs no update and contains no mutable authoritative refs.
	_mirror=_snapshot(_state,false)
	_poses.current=_pose_table(_mirror);_poses.previous=_plain(_poses.current)
	_published_at=Time.get_ticks_usec()
	_attach_mirror()

func advance(delta: float,input: Dictionary={},paused: bool=false) -> Dictionary:
	var started: int=Time.get_ticks_usec()
	if not _retired:
		_poll()
		if not paused and _mirror.get("result")==null:
			var elapsed: float=maxf(0.0,Damage.number(delta))
			_debt+=elapsed;_desired_time+=elapsed
		if _task<0 and _mirror.get("result")==null:
			var steps: int=mini(MAX_STEPS_PER_JOB,int(floor((_debt+0.000000001)/STEP))) if not paused else 0
			if steps>0 or not _commands.is_empty():
				_debt=maxf(0.0,_debt-float(steps)*STEP)
				_submit(steps,input,false)
	_telemetry.mainPollUs=Time.get_ticks_usec()-started
	_attach_mirror()
	return _mirror

func queue_command(kind: String,payload: Dictionary={}) -> bool:
	if _retired or _mirror.get("result")!=null:return false
	if kind not in ["flagship","autopilot","order","fleet_order","options","retreat","crew_policy","repair_priority","player_command","boarding_auto","boarding_order","boarding_abort","lab_refill"]:return false
	if not _is_plain(payload):return false
	_sequence+=1
	_commands.append({"sequence":_sequence,"kind":kind,"payload":_plain(payload)})
	return true

func take_events() -> Array:
	var result: Array=_events
	_events=[]
	return result

func telemetry() -> Dictionary:
	var result: Dictionary=_telemetry.duplicate(true)
	result.simulationLagSeconds=maxf(0.0,_desired_time-float(result.stateTime))
	result.inFlight=_task>=0
	result.retired=_retired
	return result

func presentation_fraction() -> float:
	return clampf(float(Time.get_ticks_usec()-_published_at)/1000000.0/STEP,0.0,1.0)

func presentation_poses() -> Dictionary:
	return _poses # Main-only detached tables, replaced after each joined job.

func retire() -> Dictionary:
	if _retired:return _mirror
	# Teardown is the ONLY path which waits for unfinished authoritative work.
	if _task>=0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_adopt()
	_submit(0,{},true)
	WorkerThreadPool.wait_for_task_completion(_task)
	_adopt()
	# The authoritative worker may have been refused an older child-task join.
	# Main joins retained handles before releasing ownership or campaign records.
	Tactical.Planner._poll_tasks051(true)
	_retired=true
	if _claimed:Tactical.release_battle_worker051();_claimed=false
	Damage.set_runtime_profile043(bool(_profile_flags.get("damage",false)))
	Records.set_runtime_profile043(bool(_profile_flags.get("records",false)))
	Tactical.set_runtime_profile043(bool(_profile_flags.get("tactical",false)))
	# Restore the original campaign owner identities only after exclusive worker
	# ownership and all detached tactical children have ended.
	for side in _mirror.get("reserves",{}):
		var reserve: Array=_mirror.reserves[side]
		var originals: Array=_reserve_owners.get(side,[])
		for index in range(mini(reserve.size(),originals.size())):
			_sync_record(originals[index],reserve[index]);reserve[index]=originals[index]
	var ships: Array=[]
	for ship: Dictionary in _mirror.get("ships",[]):ships.append(_restore_owner(ship))
	_mirror.ships=ships
	for key in ["escapedShips","captured"]:
		if _mirror.get(key) is Array:
			for index in range(_mirror[key].size()):_mirror[key][index]=_restore_owner(_mirror[key][index])
	_relink_ship_aliases(_mirror)
	for fort: Dictionary in _mirror.get("coastalDefenses",[]):
		var port: Dictionary=fort.get("port",{})
		var original: Dictionary=_port_owners.get(str(port.get("id","")),{})
		if not original.is_empty():_sync_record(original,port);fort.port=original
	# Boarding.settle requires its synchronous battle RNG even when no prizes
	# exist. Reconstruct it on Main after ownership ends; never publish the worker
	# RNG or share it with the display during active combat.
	var final_random: RandomNumberGenerator=RandomNumberGenerator.new()
	if _state.get("rng") is RandomNumberGenerator:
		final_random.seed=_state.rng.seed;final_random.state=_state.rng.state
	_mirror.rng=final_random
	_state={}
	_attach_mirror()
	return _mirror

func _submit(steps: int,input: Dictionary,retiring: bool) -> void:
	var next: _Job=_Job.new()
	next.state=_state;_state={} # Main retains no readable authoritative container.
	next.steps=steps;next.input=_plain(input);next.commands=_commands;_commands=[]
	next.completed=int(_telemetry.completedSteps);next.boot=_boot;_boot=false
	next.retiring=retiring
	_job=next
	_task=WorkerThreadPool.add_task(_work.bind(next),false,"Brass Tide authoritative battle 30Hz")

func _poll() -> void:
	if _task<0 or not WorkerThreadPool.is_task_completed(_task):return
	WorkerThreadPool.wait_for_task_completion(_task)
	_adopt()

func _adopt() -> void:
	_state=_job.state
	_mirror=_job.publication
	_events.append_array(_job.events)
	_poses=_job.poses
	for key in _job.receipt:_telemetry[key]=_job.receipt[key]
	_telemetry.jobsCompleted=int(_telemetry.jobsCompleted)+1
	_telemetry.totalWorkerJobUs=int(_telemetry.totalWorkerJobUs)+int(_job.receipt.workerJobUs)
	_telemetry.totalSimulationUs=int(_telemetry.totalSimulationUs)+int(_job.receipt.simulationUs)
	_telemetry.totalSnapshotUs=int(_telemetry.totalSnapshotUs)+int(_job.receipt.snapshotUs)
	if int(_job.receipt.stepsInJob)>0:
		_telemetry.lastSimulationJobUs=int(_job.receipt.workerJobUs)
		_telemetry.lastSimulationUs=int(_job.receipt.simulationUs)
		_telemetry.lastSimulationSnapshotUs=int(_job.receipt.snapshotUs)
	_published_at=Time.get_ticks_usec()
	_task=-1;_job=null

func _attach_mirror() -> void:
	_mirror._battleMirror051=true
	_mirror._battleDriver051=weakref(self)
	_mirror.simulation051=telemetry()

static func _work(job: _Job) -> void:
	var started: int=Time.get_ticks_usec()
	var st: Dictionary=job.state
	if job.boot:
		var t: Dictionary=Tactical.ensure(st)
		t.damageCache={}
		for ship: Dictionary in st.get("ships",[]):
			Tactical.register(st,ship,Battle._base_mounts(ship))
			if not ship.get("sunk",false) and not ship.get("captureSecured",false):t.ships[str(ship.id)]=ship
		st._damageOwned051=Damage._create_battle_owned051(st.ships,t.damageCache)
		Tactical.enable_planning051(st,true)
	var acknowledgements: Array=[]
	for command: Dictionary in job.commands:
		var acknowledgement: Dictionary=_command_result(st,str(command.kind),command.payload)
		acknowledgement.sequence=command.sequence;acknowledgement.kind=command.kind
		acknowledgements.append(acknowledgement)
	var previous: Dictionary=_pose_table(st)
	var steps_done: int=0
	var simulation_started: int=Time.get_ticks_usec()
	for index in range(job.steps):
		if st.get("result")!=null:break
		# The initial table already describes the first step's starting pose.
		if index>0:previous=_pose_table(st)
		Battle.update(st,STEP,job.input)
		steps_done+=1
	var simulation_us: int=Time.get_ticks_usec()-simulation_started
	if job.retiring or st.get("result")!=null:
		Tactical.retire_planning051(st)
		Tactical.Planner._poll_tasks051(true) # Owned teardown, including retired slots.
		Battle._close_damage_owned051(st)
	var snapshot_started: int=Time.get_ticks_usec()
	job.events=_plain(Battle.pop_events(st))
	var snapshot_detail051: Dictionary={}
	job.publication=_snapshot(st,true,snapshot_detail051)
	job.poses={"previous":previous,"current":_pose_table(st)}
	var snapshot_us: int=Time.get_ticks_usec()-snapshot_started
	job.completed+=steps_done
	job.receipt={"workerStepHz":30,"workerThreadId":OS.get_thread_caller_id(),"completedSteps":job.completed,"stateTime":float(st.get("time",0.0)),"workerJobUs":Time.get_ticks_usec()-started,"simulationUs":simulation_us,"snapshotUs":snapshot_us,"snapshotDetailUs":snapshot_detail051,"stepsInJob":steps_done,"commandResults":acknowledgements}
	if not acknowledgements.is_empty():job.receipt.lastCommandSequence=int(acknowledgements[-1].sequence)
	job.commands=[];job.input={}

static func _command_result(st: Dictionary,kind: String,p: Dictionary) -> Dictionary:
	# Called only by the authoritative job, including paused command-only jobs.
	# Existing adapters retain their complete live-owner validation and accounting.
	if st.get("result")!=null:return {"ok":false,"message":"The battle has already ended."}
	match kind:
		"player_command":
			if not p.get("ids") is Array or not p.get("command") is String or not p.get("target",{}) is Dictionary:
				return {"ok":false,"message":"Choose boats and a valid fleet command."}
			return PlayerCommands.apply(st,p.ids,p.command,p.get("target",{}))
		"boarding_auto":
			if not p.get("enabled") is bool:return {"ok":false,"message":"Choose whether automatic boarding is enabled."}
			st.autoBoard=p.enabled
			return {"ok":true,"message":"Automatic boarding enabled." if p.enabled else "Automatic boarding disabled."}
		"boarding_order":
			if not (p.get("sourceId") is String or p.get("sourceId") is StringName) or not (p.get("targetId") is String or p.get("targetId") is StringName) or not p.get("count") is int:
				return {"ok":false,"message":"Choose a source boat, target and whole number of boarders."}
			if int(p.count)<1 or int(p.count)>128:return {"ok":false,"message":"Choose between 1 and 128 boarders."}
			return Battle.BoardingCombat.order(st,str(p.sourceId),str(p.targetId),int(p.count))
		"boarding_abort":
			if not (p.get("id") is String or p.get("id") is StringName):return {"ok":false,"message":"Choose an active boarding party to recall."}
			var result: Dictionary=Battle.BoardingCombat.Boarding.abort(st,str(p.id))
			result.message=str(result.get("reason","Party recovery resolved using actual contact and berths."))
			return result
		"lab_refill":return _lab_refill(st)
	return {"ok":_apply_command(st,kind,p)}

static func _lab_refill(st: Dictionary) -> Dictionary:
	# This private flag comes only from the initial Lab state. Neither queue
	# payloads nor presentation mirrors can grant career battles free stores.
	if not st.get("_labCommands051",false) is bool or not st.get("_labCommands051",false):
		return {"ok":false,"message":"Repair/refill is available only in the fleet laboratory."}
	var cache: Dictionary=Tactical.ensure(st).get("damageCache",{})
	var count: int=0
	for ship: Dictionary in st.get("ships",[]):
		if ship.get("sunk",false):continue
		# Match the existing Lab fixture action; never revive actors, restore crew
		# or replace fitted equipment. Revoke proofs before these numeric writes.
		Damage._drop_battle_owner051(st.get("_damageOwned051"),ship)
		Damage.invalidate_frame_cache(cache,ship)
		ship.hp=ship.maxHp;ship.water=0.0;ship.fire=0.0;ship.engine=1.0;ship.breaches=[]
		ship.ammo=float(ship.spec.ammoCapacity);ship.fuel=120.0;ship.supplies=20.0
		count+=1
	return {"ok":true,"message":"Laboratory fixtures repaired and resupplied.","count":count}

static func _apply_command(st: Dictionary,kind: String,p: Dictionary) -> bool:
	if st.get("result")!=null:return false
	if kind in ["order","options","crew_policy","repair_priority"] and not p.get("ids") is Array:return false
	if kind in ["order","fleet_order"] and (not p.get("order") is String or not p.get("target",{}) is Dictionary):return false
	if kind=="options" and not p.get("options") is Dictionary:return false
	match kind:
		"flagship":return Battle.select_flagship(st,p.get("id",""))
		"autopilot":Battle.set_autopilot(st,bool(p.get("enabled",true)));return true
		"order":return Battle.issue_order(st,p.get("ids",[]),str(p.get("order","")),p.get("target",{}))
		"fleet_order":
			var order: String=str(p.get("order",""))
			return Battle.set_order(st,order,p.get("target",{}))==order
		"options":return Battle.set_tactical_options(st,p.get("ids",[]),p.get("options",{}))
		"retreat":Battle.retreat(st);return true
		"crew_policy":return Battle.set_crew_policy(st,p.get("ids",[]),str(p.get("policy","")))
		"repair_priority":return Battle.set_repair_priority(st,p.get("ids",[]),str(p.get("priority","")))
	return false

static func _snapshot(st: Dictionary,with_status: bool,detail051: Variant=null) -> Dictionary:
	# Four bounded stage clocks per publication, independent of acceptance gates.
	var stage051: int=Time.get_ticks_usec() if detail051 is Dictionary else 0
	var result: Dictionary={}
	for key in st:
		if str(key).begins_with("_") or key in ["rng","tactical","events"]:continue
		if not st[key] is Object:
			result[key]=_copy_plain_owned051(st[key]) if key in PLAIN_STATE_GROUPS051 else _plain(st[key])
	result.events=[] # Audio goes through take_events(), never repeated UI snapshots.
	if detail051 is Dictionary:
		detail051.stateCopy=Time.get_ticks_usec()-stage051;stage051=Time.get_ticks_usec()
	var t: Dictionary=st.get("tactical",{})
	var damage_cache: Dictionary=t.get("damageCache",{})
	var damage_owned=Damage._battle_owned_for051(st.get("_damageOwned051"),st.get("ships",[]),damage_cache) if with_status and st.get("result")==null else null
	var status_phase=null
	if damage_owned!=null:
		# A NEW post-contact/projectile phase validates every CURRENT status input
		# once. This closed snapshot has no actor/equipment/crew/policy writers,
		# command callbacks or awaits. Status may retire goals, not physical state.
		# Never borrow Battle's earlier pre-contact phase or a previous job's seal.
		status_phase=Damage._begin_battle_phase043(damage_cache)
		Damage._bind_battle_owned051(status_phase,damage_owned,st.ships,damage_cache)
		Damage._seal_battle_reads051(status_phase)
	if detail051 is Dictionary:
		detail051.statusPreparation=Time.get_ticks_usec()-stage051;stage051=Time.get_ticks_usec()
	var public_t: Dictionary={"statusById051":{},"mountsById051":{},"damageStatusById051":{},"mountCache":{}}
	for ship: Dictionary in st.get("ships",[]):
		var id: String=str(ship.get("id",""))
		public_t.mountsById051[id]=_copy_plain_owned051(Battle._combat_mounts(st,ship,status_phase)) if with_status else _copy_plain_owned051(Battle._base_mounts(ship))
		# Existing command adapter tests public mount availability. This is a
		# detached publication row, never the live source/condition cache entry.
		public_t.mountCache[id]={"mounts":public_t.mountsById051[id]}
		if with_status:
			# status constructs a fresh row and deep-copies weapons/options/mounts.
			# Its path/exit arrays are shallow copies: detach their nested values,
			# then publish that row without cloning the already detached branches.
			# Reuse the post-step phase for its equipment reads too; null would
			# rebuild canonical inspection for mounts and each goal/status check.
			var tactical_status: Dictionary=Tactical.status(st,id,status_phase)
			for key in ["path","exit"]:
				if tactical_status.has(key):tactical_status[key]=_copy_plain_owned051(tactical_status[key])
			public_t.statusById051[id]=tactical_status
			# Public/noncanonical/result reads retain fresh inspection. Only this
			# exclusive worker stage borrows a still-validated canonical owner.
			var owned_status: bool=status_phase!=null and not Damage._battle_entry051(ship,damage_owned).is_empty()
			public_t.damageStatusById051[id]=_copy_plain_owned051(Damage._read_status_in_phase043(ship,status_phase) if owned_status else Damage.get_status(ship))
	if status_phase!=null:Damage._end_battle_phase043(status_phase)
	if detail051 is Dictionary:
		detail051.shipRows=Time.get_ticks_usec()-stage051;stage051=Time.get_ticks_usec()
	# status may retire an invalid goal on the authoritative owner. Publish the
	# matching post-status public fields, rather than an older intent table.
	for key in PUBLIC_TACTICAL:
		# Public intent/HUD/trace writers emit only copied numeric/string/value
		# data. Legacy predictions also carry owner/proof inputs: retain their
		# recursive sanitizer rather than widening that ownership assumption.
		if t.has(key):public_t[key]=_plain(t[key]) if key=="predictions" else _copy_plain_owned051(t[key])
	result.tactical=public_t
	_relink_ship_aliases(result)
	if detail051 is Dictionary:detail051.tacticalCopy=Time.get_ticks_usec()-stage051
	return result

static func _copy_plain_owned051(value: Variant) -> Variant:
	# Only for the audited publication groups above, never an ingress boundary.
	# Native deep copy detaches EVERY mutable Dictionary/Array; sharing even an
	# unchanged spec or module record with the authoritative owner is forbidden.
	# duplicate(true) does NOT detach Objects, hence _plain remains mandatory for
	# acquisition/commands/input, unknown fields and private planning records.
	if value is Dictionary or value is Array:return value.duplicate(true)
	if typeof(value)>=TYPE_PACKED_BYTE_ARRAY:return value.duplicate()
	return value

static func _relink_ship_aliases(st: Dictionary) -> void:
	# Variant deep copies do not retain aliases ACROSS containers. Convoy actors,
	# escaped carriers and captured prizes must refer to this state's own ships.
	var by_key: Dictionary={}
	for key in ["ships","escapedShips","captured"]:
		for ship: Dictionary in st.get(key,[]):
			var identity: String=_owner_key(ship)
			if not by_key.has(identity):by_key[identity]=ship
	for key in ["escapedShips","captured"]:
		var ships: Array=st.get(key,[])
		for index in range(ships.size()):ships[index]=by_key.get(_owner_key(ships[index]),ships[index])
	if st.get("convoy") is Dictionary:
		var actors: Dictionary=st.convoy.get("actors",{})
		for uid in actors:
			var actor: Dictionary=actors[uid]
			actors[uid]=by_key.get(_owner_key(actor),actor)

static func _pose_table(st: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for ship: Dictionary in st.get("ships",[]):
		result[str(ship.get("id",""))]={"x":float(ship.get("x",0.0)),"y":float(ship.get("y",0.0)),"angle":float(ship.get("angle",0.0)),"turretAngle":float(ship.get("turretAngle",0.0))}
	return result

static func _is_plain(value: Variant) -> bool:
	if value is Object or value is Callable or value is Signal or typeof(value)==TYPE_RID:return false
	if value is Dictionary:
		for key in value:
			if not _is_plain(key) or not _is_plain(value[key]):return false
	elif value is Array:
		for item in value:
			if not _is_plain(item):return false
	return true

static func _plain(value: Variant) -> Variant:
	if value is Object or value is Callable or value is Signal or typeof(value)==TYPE_RID:return null
	if value is Dictionary:
		var result: Dictionary={}
		for key in value:
			if key is Object or key is Callable or key is Signal or typeof(key)==TYPE_RID or value[key] is Object or value[key] is Callable or value[key] is Signal or typeof(value[key])==TYPE_RID:continue
			result[key]=_plain(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value:
			if not item is Object and not item is Callable and not item is Signal and typeof(item)!=TYPE_RID:result.append(_plain(item))
		return result
	if typeof(value)>=TYPE_PACKED_BYTE_ARRAY:return value.duplicate()
	return value

static func _owner_key(ship: Dictionary) -> String:
	var uid: String=str(ship.get("uid",""))
	return "uid:"+uid if not uid.is_empty() else "id:"+str(ship.get("id",""))

func _remember_owner(ship: Dictionary) -> void:
	var key: String=_owner_key(ship)
	if not key.is_empty():_owners[key]=ship

func _restore_owner(ship: Dictionary) -> Dictionary:
	var original: Dictionary=_owners.get(_owner_key(ship),{})
	if original.is_empty():return ship
	_sync_record(original,ship)
	return original

static func _sync_record(destination: Dictionary,source: Dictionary) -> void:
	# Retain existing equipment dictionaries used by campaign registries as well
	# as the top-level hull identity. Executed once after all workers are joined.
	if is_same(destination,source):return
	for key in destination.keys():
		if not source.has(key):destination.erase(key)
	for key in source:
		if source[key] is Dictionary and destination.get(key) is Dictionary and not destination[key].is_read_only():
			_sync_record(destination[key],source[key])
		elif source[key] is Array and destination.get(key) is Array and not destination[key].is_read_only():
			var target: Array=destination[key]
			var values: Array=source[key]
			target.resize(values.size())
			for index in range(values.size()):
				if values[index] is Dictionary and target[index] is Dictionary and not target[index].is_read_only():_sync_record(target[index],values[index])
				else:target[index]=_plain(values[index])
		else:destination[key]=_plain(source[key])
