extends RefCounted
## Main owns detached presentation and the mailbox; one Thread owns combat.
const Battle=preload("res://scripts/battle.gd")
const PlayerCommands=preload("res://scripts/battle_commands047.gd")
const Tactical=preload("res://scripts/tactical_runtime.gd")
const Damage=preload("res://scripts/damage.gd")
const Records=preload("res://scripts/equipment_records.gd")
const STEP: float=1.0/30.0
const DISPLAY_US: int=66667
const PUBLIC_TACTICAL: Array=["snapshotRevision","terrainRevision","terrainKey","options","groups","intents","predictions","reasons","fireReasons","trace","counters","metrics","manualId","dt","failures"]
const PLAIN_STATE_GROUPS051: Array=["ships","reserves","projectiles","effects","wrecks","islands","mission","location","deployment","log","convoy","escapedShips","captured","convoyOutcome","coastalDefenses","boarding"]

class _Mailbox extends RefCounted:
	var mutex: Mutex=Mutex.new()
	var wake: Semaphore=Semaphore.new()
	var wake_pending: bool=false # At most ONE outstanding semaphore credit.
	var elapsed: float=0.0
	var input: Dictionary={}
	var paused: bool=true
	var commands: Array=[]
	var accepting: bool=true
	var retiring: bool=false
	var busy: bool=false
	var finished: bool=false
	var remaining_debt: float=0.0
	var actual_completed: int=0
	var actual_time: float=0.0
	var thread_id: int=-1
	var packet: Dictionary={} # Replaceable DETACHED frame, never live state.
	var events: Array=[] # Lossless queues, independent of frame coalescing.
	var acknowledgements: Array=[]

class _Job extends RefCounted:
	# Worker-local kernel arguments; never given to Main or put in the mailbox.
	var state: Dictionary={}
	var commands: Array=[]
	var input: Dictionary={}
	var steps: int=0
	var completed: int=0
	var boot: bool=true
	var retiring: bool=false
	var publish: bool=false
	var publication: Dictionary={}
	var poses: Dictionary={}
	var events: Array=[]
	var receipt: Dictionary={}

var _mailbox: _Mailbox=_Mailbox.new()
var _thread: Thread=null
var _mirror: Dictionary={}
var _events: Array=[]
var _owners: Dictionary={} # Original campaign records stay exclusively on Main.
var _reserve_owners: Dictionary={}
var _port_owners: Dictionary={}
var _profile_flags: Dictionary={}
var _sequence: int=0
var _retired: bool=false
var _claimed: bool=false
var _desired_time: float=0.0
var _published_at: int=0
var _presentation_span: float=STEP
var _poses: Dictionary={"previous":{},"current":{}}
var _telemetry: Dictionary={"workerStepHz":30,"workerThreadId":-1,"completedSteps":0,"stateTime":0.0,"workerJobUs":0,"simulationUs":0,"snapshotUs":0,"stepsInJob":0,"mainPollUs":0,"simulationLagSeconds":0.0,"jobsCompleted":0,"lastCommandSequence":0,"commandResults":[],"totalWorkerJobUs":0,"totalSimulationUs":0,"totalSnapshotUs":0,"lastSimulationJobUs":0,"lastSimulationUs":0,"lastSimulationSnapshotUs":0}

func _init(initial: Dictionary) -> void:
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
	var owned: Dictionary={}
	for key in initial:
		if key in ["tactical","rng","_damageOwned051","_battleDriver051","_battleMirror051"]:continue
		if not initial[key] is Object:owned[key]=_plain(initial[key])
	var random: RandomNumberGenerator=RandomNumberGenerator.new()
	if initial.get("rng") is RandomNumberGenerator:
		random.seed=initial.rng.seed;random.state=initial.rng.state
	owned.rng=random
	_relink_ship_aliases(owned)
	var t: Dictionary=Tactical.ensure(owned)
	for key in ["options","groups","home","orderTimes"]:
		if initial.get("tactical",{}).has(key):t[key]=_plain(initial.tactical[key])
	_desired_time=float(owned.get("time",0.0))
	_telemetry.stateTime=_desired_time
	_mailbox.actual_time=_desired_time
	# The sole initial acquisition snapshot precedes Thread ownership.
	_mirror=_snapshot(owned,false)
	_poses.current=_pose_table(_mirror);_poses.previous=_plain(_poses.current)
	_published_at=Time.get_ticks_usec()
	_thread=Thread.new()
	var error: Error=_thread.start(_run_worker.bind(_mailbox,owned),Thread.PRIORITY_HIGH)
	if error!=OK:
		_thread=null
		Tactical.retire_planning051(owned)
		Battle._close_damage_owned051(owned)
		_retired=true
		_mirror.startError="The battle worker could not start."
		_mirror.result="lost"
		_release_owner()
	owned={} # Main NEVER retains the authoritative state after successful start.
	_attach_mirror()

func advance(delta: float,input: Dictionary={},paused: bool=false) -> Dictionary:
	var started: int=Time.get_ticks_usec()
	if not _retired:
		_poll()
		var detached_input: Dictionary=_plain(input)
		_mailbox.mutex.lock()
		if _mailbox.accepting:
			_mailbox.input=detached_input
			_mailbox.paused=paused
			if not paused:
				var elapsed: float=maxf(0.0,Damage.number(delta))
				_mailbox.elapsed+=elapsed;_desired_time+=elapsed
			_notify_locked(_mailbox)
		_mailbox.mutex.unlock()
	_telemetry.mainPollUs=Time.get_ticks_usec()-started
	_attach_mirror()
	return _mirror

func queue_command(kind: String,payload: Dictionary={}) -> bool:
	if _retired or _mirror.get("result")!=null:return false
	if kind not in ["flagship","autopilot","order","fleet_order","options","retreat","crew_policy","repair_priority","player_command","boarding_auto","boarding_order","boarding_abort","lab_refill"]:return false
	if not _is_plain(payload):return false
	var detached: Dictionary=_plain(payload)
	_mailbox.mutex.lock()
	if not _mailbox.accepting:
		_mailbox.mutex.unlock();return false
	_sequence+=1
	_mailbox.commands.append({"sequence":_sequence,"kind":kind,"payload":detached})
	_notify_locked(_mailbox)
	_mailbox.mutex.unlock()
	return true

func take_events() -> Array:
	var result: Array=_events
	_events=[]
	return result

func telemetry() -> Dictionary:
	var result: Dictionary=_telemetry.duplicate(true)
	result.simulationLagSeconds=maxf(0.0,_desired_time-float(result.stateTime))
	_mailbox.mutex.lock()
	result.inFlight=_mailbox.busy or (not _mailbox.finished and not _mailbox.paused and _mailbox.remaining_debt+_mailbox.elapsed+0.000000001>=STEP) or not _mailbox.commands.is_empty()
	result.actualCompletedSteps=_mailbox.actual_completed
	result.actualStateTime=_mailbox.actual_time
	result.remainingDebtSeconds=_mailbox.remaining_debt+_mailbox.elapsed
	result.workerFinished=_mailbox.finished
	result.workerThreadId=_mailbox.thread_id
	_mailbox.mutex.unlock()
	result.workerRunning=_thread!=null and _thread.is_alive()
	result.workerJoined=_thread==null
	result.retired=_retired
	return result

func presentation_fraction() -> float:
	if _presentation_span<=0.0:return 1.0
	return clampf(float(Time.get_ticks_usec()-_published_at)/1000000.0/_presentation_span,0.0,1.0)

func presentation_poses() -> Dictionary:
	return _poses # Main-only tables; previous is the LAST ADOPTED display pose.

func retire() -> Dictionary:
	if _retired:return _mirror
	_mailbox.mutex.lock()
	_mailbox.accepting=false
	_mailbox.retiring=true
	_notify_locked(_mailbox) # Also wakes an idle or paused Thread.
	_mailbox.mutex.unlock()
	# Only teardown joins. Finish at most the ALREADY admitted step. Remaining
	# debt is reported, never simulated offscreen or relabelled as completed time.
	var final_state: Dictionary=_thread.wait_to_finish()
	_thread=null
	_poll()
	Tactical.Planner._poll_tasks051(true) # Retained child handles, before release.
	# A terminal packet may already have been exposed and edited on Main. Never
	# restore campaign records FROM that packet or replace its ships in place.
	# The joined state is now exclusively Main-owned; make a NEW full final copy.
	var final_snapshot_started: int=Time.get_ticks_usec()
	_mirror=_snapshot(final_state,true,{},true)
	_telemetry.finalMainSnapshotUs=Time.get_ticks_usec()-final_snapshot_started
	var final_poses: Dictionary=_pose_table(_mirror)
	_poses={"previous":final_poses.duplicate(true),"current":final_poses}
	_presentation_span=0.0
	_retired=true
	_release_owner()
	_restore_campaign_owners()
	var final_random: RandomNumberGenerator=RandomNumberGenerator.new()
	if final_state.get("rng") is RandomNumberGenerator:
		final_random.seed=final_state.rng.seed;final_random.state=final_state.rng.state
	_mirror.rng=final_random
	final_state={}
	_attach_mirror()
	return _mirror

func _release_owner() -> void:
	if _claimed:Tactical.release_battle_worker051();_claimed=false
	Damage.set_runtime_profile043(bool(_profile_flags.get("damage",false)))
	Records.set_runtime_profile043(bool(_profile_flags.get("records",false)))
	Tactical.set_runtime_profile043(bool(_profile_flags.get("tactical",false)))

func _restore_campaign_owners() -> void:
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

func _poll() -> void:
	_mailbox.mutex.lock()
	var packet: Dictionary=_mailbox.packet;_mailbox.packet={}
	var feedback: Array=_mailbox.events;_mailbox.events=[]
	var acknowledgements: Array=_mailbox.acknowledgements;_mailbox.acknowledgements=[]
	_mailbox.mutex.unlock()
	_events.append_array(feedback)
	if not acknowledgements.is_empty():
		_telemetry.commandResults=acknowledgements
		_telemetry.lastCommandSequence=int(acknowledgements[-1].sequence)
	if packet.is_empty():return
	var receipt: Dictionary=packet.receipt
	var added: int=int(receipt.completedSteps)-int(_telemetry.completedSteps)
	var worker_us: int=int(receipt.totalWorkerJobUs)-int(_telemetry.totalWorkerJobUs)
	var simulation_us: int=int(receipt.totalSimulationUs)-int(_telemetry.totalSimulationUs)
	var snapshot_us: int=int(receipt.totalSnapshotUs)-int(_telemetry.totalSnapshotUs)
	var prior: Dictionary=_poses.current
	var span: float=float(packet.display.time)-float(_mirror.get("time",0.0))
	_mirror=packet.display
	if span>0.000000001:
		var previous: Dictionary={}
		for id in packet.poses:previous[id]=prior.get(id,packet.poses[id])
		_poses={"previous":previous,"current":packet.poses}
		_presentation_span=span
		_published_at=Time.get_ticks_usec()
	elif _mirror.get("result")!=null:
		_poses={"previous":packet.poses.duplicate(true),"current":packet.poses}
		_presentation_span=0.0
	# A same-time command frame keeps the existing in-progress interpolation.
	for key in receipt:_telemetry[key]=receipt[key]
	_telemetry.stepsInJob=added
	_telemetry.workerJobUs=worker_us
	_telemetry.simulationUs=simulation_us
	_telemetry.snapshotUs=snapshot_us
	if added>0:
		_telemetry.lastSimulationJobUs=worker_us
		_telemetry.lastSimulationUs=simulation_us
		_telemetry.lastSimulationSnapshotUs=snapshot_us

func _attach_mirror() -> void:
	_mirror._battleMirror051=true
	_mirror._battleDriver051=weakref(self)
	_mirror.simulation051=telemetry()

static func _notify_locked(mail: _Mailbox) -> void:
	# Caller holds mutex. Credits stay coalesced while the Thread is running;
	# only the waiter clears this flag AFTER consuming the one existing credit.
	if not mail.wake_pending:
		mail.wake_pending=true
		mail.wake.post()

static func _run_worker(mail: _Mailbox,initial: Dictionary) -> Dictionary:
	var job: _Job=_Job.new();job.state=initial;initial={}
	# Chart interpolates hulls/turrets, but projectile/FX packets are direct.
	# Preserve their per-real-step cadence in cheap encounters. This fixed
	# publication budget NEVER changes actor participation or physical stepping.
	var per_step_display: bool=job.state.get("ships",[]).size()<=6
	var debt: float=0.0
	var dirty: bool=false
	var observe_next_step: bool=false
	var published_at: int=Time.get_ticks_usec()
	var totals: Dictionary={"completedSteps":0,"stateTime":float(job.state.get("time",0.0)),"totalWorkerJobUs":0,"totalSimulationUs":0,"totalSnapshotUs":0,"jobsCompleted":0,"workerTurns":0,"workerStepHz":30,"workerThreadId":OS.get_thread_caller_id(),"displayBudgetHz":30 if per_step_display else 15}
	var feedback: Array=[]
	var acknowledgements: Array=[]
	mail.mutex.lock();mail.thread_id=OS.get_thread_caller_id();mail.mutex.unlock()
	while true:
		mail.mutex.lock()
		debt+=mail.elapsed;mail.elapsed=0.0
		var paused: bool=mail.paused
		var retiring: bool=mail.retiring
		job.input=mail.input
		job.commands=mail.commands;mail.commands=[]
		mail.remaining_debt=debt
		mail.mutex.unlock()
		var runnable: bool=not retiring and not paused and debt+0.000000001>=STEP and job.state.get("result")==null
		job.steps=1 if runnable else 0
		job.retiring=retiring and not runnable
		# Large-fleet routine DISPLAY obeys a wall interval, even in catch-up.
		# Physics never waits for that interval or Main to adopt a frame.
		job.publish=job.retiring or not job.commands.is_empty() or (dirty and paused) or (observe_next_step and job.steps>0) or (per_step_display and job.steps>0) or ((dirty or job.steps>0) and Time.get_ticks_usec()-published_at>=DISPLAY_US)
		if job.steps==0 and job.commands.is_empty() and not job.publish and job.state.get("result")==null:
			mail.mutex.lock();mail.busy=false;mail.mutex.unlock()
			mail.wake.wait()
			mail.mutex.lock();mail.wake_pending=false;mail.mutex.unlock()
			continue # No CPU work or simulation time is charged for waiting.
		mail.mutex.lock();mail.busy=true;mail.mutex.unlock()
		var started: int=Time.get_ticks_usec()
		_work(job)
		debt=maxf(0.0,debt-float(job.receipt.stepsInJob)*STEP)
		dirty=dirty or int(job.receipt.stepsInJob)>0 or not job.receipt.commandResults.is_empty()
		if int(job.receipt.stepsInJob)>0:observe_next_step=false
		if not job.receipt.commandResults.is_empty() and int(job.receipt.stepsInJob)==0:observe_next_step=true
		feedback.append_array(job.events)
		acknowledgements.append_array(job.receipt.commandResults)
		var finished: bool=job.retiring or job.state.get("result")!=null
		if finished:
			# Close ingress before the final transfer. Commands admitted while the
			# terminal step ran still get their own FIFO declined receipts.
			mail.mutex.lock()
			mail.accepting=false
			var tail: Array=mail.commands;mail.commands=[]
			debt+=mail.elapsed;mail.elapsed=0.0
			mail.mutex.unlock()
			for command: Dictionary in tail:
				var result: Dictionary=_plain(_command_result(job.state,str(command.kind),command.payload))
				result.sequence=command.sequence;result.kind=command.kind
				acknowledgements.append(result)
		totals.completedSteps=job.completed;totals.stateTime=float(job.state.get("time",0.0))
		totals.totalWorkerJobUs=int(totals.totalWorkerJobUs)+Time.get_ticks_usec()-started
		totals.totalSimulationUs=int(totals.totalSimulationUs)+int(job.receipt.simulationUs)
		totals.totalSnapshotUs=int(totals.totalSnapshotUs)+int(job.receipt.snapshotUs)
		totals.workerTurns=int(totals.workerTurns)+1
		mail.mutex.lock()
		mail.actual_completed=job.completed;mail.actual_time=float(job.state.get("time",0.0));mail.remaining_debt=debt
		if job.publish:
			totals.jobsCompleted=int(totals.jobsCompleted)+1
			totals.snapshotDetailUs=job.receipt.snapshotDetailUs
			mail.packet={"display":job.publication,"poses":job.poses,"receipt":totals.duplicate(true)}
			mail.events.append_array(feedback);feedback=[]
			mail.acknowledgements.append_array(acknowledgements);acknowledgements=[]
			dirty=false;published_at=Time.get_ticks_usec()
		mail.busy=false
		mail.finished=finished
		mail.mutex.unlock()
		if finished:return job.state # Main may read only AFTER wait_to_finish().
	return {}

static func _work(job: _Job) -> void:
	var st: Dictionary=job.state
	if job.boot:
		var t: Dictionary=Tactical.ensure(st)
		t.damageCache={}
		for ship: Dictionary in st.get("ships",[]):
			Tactical.register(st,ship,Battle._base_mounts(ship))
			if not ship.get("sunk",false) and not ship.get("captureSecured",false):t.ships[str(ship.id)]=ship
		st._damageOwned051=Damage._create_battle_owned051(st.ships,t.damageCache)
		Tactical.enable_planning051(st,true)
		job.boot=false
	var acknowledgements: Array=[]
	for command: Dictionary in job.commands:
		var acknowledgement: Dictionary=_plain(_command_result(st,str(command.kind),command.payload))
		acknowledgement.sequence=command.sequence;acknowledgement.kind=command.kind
		acknowledgements.append(acknowledgement)
	var steps_done: int=0
	var simulation_started: int=Time.get_ticks_usec()
	for index in range(job.steps):
		if st.get("result")!=null:break
		Battle.update(st,STEP,job.input)
		steps_done+=1
	var simulation_us: int=Time.get_ticks_usec()-simulation_started
	if job.retiring or st.get("result")!=null:
		Tactical.retire_planning051(st)
		Tactical.Planner._poll_tasks051(true)
		Battle._close_damage_owned051(st)
		job.publish=true
	job.events=_plain(Battle.pop_events(st))
	var snapshot_detail051: Dictionary={}
	var snapshot_us: int=0
	if job.publish:
		var snapshot_started: int=Time.get_ticks_usec()
		job.publication=_snapshot(st,true,snapshot_detail051,job.retiring or st.get("result")!=null)
		job.poses=_pose_table(st)
		snapshot_us=Time.get_ticks_usec()-snapshot_started
	job.completed+=steps_done
	job.receipt={"simulationUs":simulation_us,"snapshotUs":snapshot_us,"snapshotDetailUs":snapshot_detail051,"stepsInJob":steps_done,"commandResults":acknowledgements}
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

static func _snapshot(st: Dictionary,with_status: bool,detail051: Variant=null,include_trace120: bool=true) -> Dictionary:
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
		# This CLOSED post-step publication has no pose/equipment writers. Bind
		# a NEW current numeric table, never the pre-contact epoch, so pure
		# capability/status reads can use their existing exact current proofs.
		# No helm, fire, physical step or certificate is executed here.
		Tactical.after_motion(st,status_phase)
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
	if status_phase!=null:
		Tactical._close_numeric051(st)
		Damage._end_battle_phase043(status_phase)
	if detail051 is Dictionary:
		detail051.shipRows=Time.get_ticks_usec()-stage051;stage051=Time.get_ticks_usec()
	# status may retire an invalid goal on the authoritative owner. Publish the
	# matching post-status public fields, rather than an older intent table.
	# Routine display has current status/intents; the bounded developer history
	# stays on the exclusive worker. Result/retirement publishes its full detached
	# history. Direct/legacy snapshots retain full history by default. The actual
	# profiler retires before its end-history read; no measured interval is changed.
	public_t.traceDeferred120=not include_trace120
	for key in PUBLIC_TACTICAL:
		if key=="trace" and not include_trace120:
			public_t.trace=[];continue
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

