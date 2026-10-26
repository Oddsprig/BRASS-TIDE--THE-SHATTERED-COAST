extends SceneTree
## Root alone runs this short headless/Dummy fixture through Test Bridge.
const Battle=preload("res://scripts/battle.gd")
const Lab=preload("res://scripts/fleet_lab.gd")
const Damage=preload("res://scripts/damage.gd")
const Core=preload("res://scripts/equipment_condition.gd")
const EquipmentCombat=preload("res://scripts/equipment_combat.gd")
const Tactical=preload("res://scripts/tactical_runtime.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Certification=preload("res://scripts/tactical_certification.gd")
const Planner=preload("res://scripts/tactical_planner.gd")
const Rollout=preload("res://scripts/equipment_rollout.gd")
const Routes=preload("res://scripts/tactical_routes.gd")
const SEED: int=4040
const DT: float=1.0/60.0
const WARMUP: int=4
const MEASURED: int=12
const ADMISSION_US: int=24000000
var started_us: int=0
var checks: int=0
var failures: Array=[]
var stops: Array=[]
var report: Dictionary={}

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);print("FAIL combat_hotpath040: "+message)

func admit(label: String,previous_us: int=0) -> bool:
	# Cooperative only; Root also supplies the external 30s process deadline.
	if Time.get_ticks_usec()-started_us+maxi(3000000,previous_us*2)<ADMISSION_US:return true
	stops.append(label)
	return false

func distribution(values: Array) -> Dictionary:
	if values.is_empty():return {"count":0,"medianUs":null,"p95Us":null,"maxUs":null,"totalUs":0}
	var sorted: Array=values.duplicate();sorted.sort()
	var total: int=0;var count: int=sorted.size();var middle: int=floori(float(count)/2.0)
	for value in sorted:total+=int(value)
	return {"count":count,"medianUs":float(sorted[middle]) if count%2 else (float(sorted[middle-1])+float(sorted[middle]))/2.0,"p95Us":int(sorted[ceili(count*0.95)-1]),"maxUs":int(sorted[-1]),"totalUs":total}

func safety_checks(template: Dictionary) -> void:
	var ship: Dictionary=template.duplicate(true)
	var st: Dictionary={"time":1.0}
	var t: Dictionary=Tactical.ensure(st);t.metrics={"safetyAges":[]}
	var id: String=str(ship.id);var cache: Dictionary={}
	Damage.tick_ship(ship,0.0,{"inCombat":true},cache)
	check(not cache.is_empty(),"actual canonical damage prepass primes the existing frame cache")
	var status: Dictionary=Damage.get_status_cached(ship,cache)
	check(status==Damage.get_status(ship),"frame-cache-aware status equals fresh public status")
	Tactical.safety_check(st,ship,cache)
	var previous: Dictionary=t.safety[id].duplicate(true)
	check(not EquipmentCombat.safety_abrupt(ship,previous,status,cache) and not EquipmentCombat.safety_abrupt(ship,previous,{},cache),"supplied and recomputed intact status agree")
	st.time=1.02;Tactical.safety_check(st,ship,cache)
	check(float(t.lastSafety[id])==1.0 and t.metrics.safetyAges.size()==1,"unchanged condition preserves the existing 0.1s cadence")
	var mount_uid: String=""
	for uid in ship.moduleCondition.items:
		if str(ship.moduleCondition.items[uid].location)=="mount0":mount_uid=str(uid)
	check(not mount_uid.is_empty(),"canonical test hull has an actual mount0 item")
	if mount_uid.is_empty():return
	var scalars: Array=[ship.hp,ship.crew,ship.engine]
	check(Core.apply_component_damage(ship.moduleCondition,{"itemUid":mount_uid,"loss":0.05,"cause":"hotpath fixture"}).ok,"real component damage lowers HP without disabling the mount")
	status=Damage.get_status_cached(ship,cache)
	check(status==Damage.get_status(ship) and [ship.hp,ship.crew,ship.engine]==scalars,"in-frame module edit invalidates cached ownership without changing hull/crew/engine")
	check(EquipmentCombat.working_mask(ship,status)==float(previous.equipMask) and EquipmentCombat.safety_abrupt(ship,previous,status,cache) and EquipmentCombat.safety_abrupt(ship,previous,{},cache),"subthreshold HP loss is detected immediately with either status path")
	Tactical.safety_check(st,ship,cache)
	check(float(t.lastSafety[id])==1.02 and float(t.safety[id].moduleHpSum)<float(previous.moduleHpSum),"module HP loss bypasses cadence even when the working mask is unchanged")
	Damage.tick_ship(ship,0.0,{"inCombat":true},cache)
	previous=t.safety[id].duplicate(true)
	check(Core.apply_component_damage(ship.moduleCondition,{"itemUid":mount_uid,"loss":0.85,"cause":"hotpath fixture"}).ok,"real component damage disables the installed mount")
	st.time=1.03;t.pending.erase(id);t.certificationAttempts[id]=1.02
	Tactical.safety_check(st,ship,cache)
	check(float(t.lastSafety[id])==1.03 and float(t.safety[id].equipMask)!=float(previous.equipMask) and float(t.certificationAttempts[id])==-2.0 and t.pending.has(id),"disabled equipment is immediately reevaluated and queued through existing authority")
	Damage.tick_ship(ship,0.0,{"inCombat":true},cache)
	check(Damage.set_repair_priority(ship,"weapons")=="weapons","public repair-priority change succeeds")
	st.time=1.04;Tactical.safety_check(st,ship,cache)
	check(float(t.lastSafety[id])==1.04 and float(t.safety[id].repairPriorityCode)==1.0 and Damage.get_status_cached(ship,cache)==Damage.get_status(ship),"priority-only edit invalidates cached status and bypasses cadence")
	st.time=1.15;Tactical.safety_check(st,ship,cache)
	check(float(t.lastSafety[id])==1.15,"unchanged equipment is still checked when the original cadence is due")
	var legacy: Dictionary=Damage.create_ship(template.spec)
	check(not EquipmentCombat.safety_abrupt(legacy,previous,Damage.get_status_cached(legacy,cache),cache),"legacy equipment retains its no-canonical-abrupt behavior")
	var corrupt: Dictionary=ship.duplicate(true);corrupt.moduleCondition.items[mount_uid].hp=-1.0
	var invalid: Dictionary=Damage.get_status_cached(corrupt,cache)
	check(not bool(invalid.equipmentOk) and not EquipmentCombat.safety_abrupt(corrupt,previous,invalid,cache),"corrupt ownership still fails closed and never reuses another ship's status")

func trace_checks(st: Dictionary) -> void:
	var ids: Array=[]
	for ship in st.ships:
		if str(ship.team)=="player":ids.append(str(ship.id))
	check(Battle.issue_order(st,ids,"hold"),"real public hold orders prepare a short trace sample")
	var short: Dictionary=st.duplicate(true)
	short.rng=RandomNumberGenerator.new();short.rng.seed=st.rng.seed;short.rng.state=st.rng.state
	Battle.update(short,DT)
	var rows: Array=short.tactical.trace.duplicate(true)
	var published: int=0;var finished: int=0
	for row in rows:
		if row.has("time"):published+=1
		if row.has("sim_time"):finished+=1
	# Publication is conditional on an accepted certified intent, not every tick.
	check(finished==st.ships.size() and rows.size()==published+finished and published<=int(short.tactical.metrics.normalLimit),"short real Battle step traces every hull and any accepted certified publications")
	report.trace={"publicationRows":published,"perHullRows":finished}
	var retained: Array=st.tactical.trace
	for index in range(512):retained.append({"oldRow":index,"payload":{"unchanged":true}})
	var expected: Array=retained.duplicate(true);expected.append_array(rows)
	# Oracle is the prior per-row FIFO result, independent of the new batch trim.
	while expected.size()>512:expected.pop_front()
	Battle.update(st,DT)
	check(is_same(retained,st.tactical.trace) and retained.size()==512 and retained==expected,"full trace preserves Array identity and every field/order of the exact last512 rows")
	check(st.ships==short.ships and st.projectiles==short.projectiles and st.tactical.intents==short.tactical.intents and Battle.pop_events(st)==Battle.pop_events(short),"trace pressure does not change actual ships, projectiles, intents or emitted events")
	# With no active hulls, finish must still trim publication rows from this step.
	var empty: Dictionary={"time":st.time};var t: Dictionary=Tactical.ensure(empty)
	t.metrics={};t.budget={"fullRoutes":0,"cacheHits":0,"rollouts":0,"samples":0,"clearanceTests":0,"exhaustions":0}
	var no_hulls: Array=t.trace
	no_hulls.append_array(expected);no_hulls.append_array(rows)
	expected=expected.duplicate(true);expected.append_array(rows)
	while expected.size()>512:expected.pop_front()
	Tactical.finish(empty,123)
	check(is_same(no_hulls,t.trace) and no_hulls==expected and int(t.metrics.aiUs)==123,"end-of-step trim also handles no-hull publication tails without losing newest rows")

func fresh_budget() -> Dictionary:
	return {"rolled":{},"rollouts":0,"samples":0,"clearanceTests":0,"clearanceLimit":2900,"exhaustions":0}

func prefix_checks(original: Dictionary) -> void:
	var st: Dictionary=original.duplicate(true)
	st.rng=RandomNumberGenerator.new();st.rng.seed=SEED
	st.islands=[]
	var ship: Dictionary=st.ships[0];var enemy: Dictionary=st.ships[1]
	ship.x=600.0;ship.y=650.0;enemy.x=1600.0;enemy.y=1100.0
	check(Battle.issue_order(st,[str(ship.id)],"move",{"x":1000.0,"y":650.0}) and Battle.issue_order(st,[str(enemy.id)],"hold"),"public clear-water move and hold orders prepare bounded authority checks")
	# Two hulls share one fair due slot; two real ticks let each receive it.
	for tick in range(2):Battle.update(st,DT)
	var intent: Dictionary=st.tactical.intents.get(str(ship.id),{})
	var record: Dictionary=st.tactical.predictions.get(str(intent.get("pathFingerprint","")),{})
	check(not record.is_empty(),"actual public move receives a physically certified intent")
	if record.is_empty():return
	var cert: Dictionary=record.certificate
	check(int(cert.rolloutSamples)==9 and record.poses.size()==19 and record.capabilities.size()==19 and is_equal_approx(float(record.sampleDt),DT) and is_equal_approx(float(cert.physicalHorizonEnd)-float(cert.checkedAt),0.3) and is_equal_approx(float(cert.validUntil)-float(cert.checkedAt),0.2),"actual live certificate retains all18 exact1/60 substeps over0.3s and only0.2s authority")
	check(bool(Certification.current(st,ship,intent,DT).ok),"new certificate remains current after actual movement and before fire at age+dt")
	var view: Dictionary=Tactical.view(st,"player",[str(ship.id)])
	var own: Dictionary={}
	for observed in view.ships:
		if str(observed.id)==str(ship.id):own=observed
	var candidate: Dictionary=record.candidate
	var live_before: PackedByteArray=var_to_bytes(st.ships);var rng_before: int=st.rng.state
	var short_work: Dictionary=fresh_budget();var long_work: Dictionary=fresh_budget()
	var short_cert: Dictionary={"rolloutSamples":0};var long_cert: Dictionary={"rolloutSamples":0}
	var short: Dictionary=Rollout.prefix(st,own,candidate,short_work,short_cert,DT,2,null,9)
	var full: Dictionary=Rollout.prefix(st,own,candidate,long_work,long_cert,DT,2)
	check(short.ok and full.ok and short.poses==full.poses.slice(0,19) and short.capabilities==full.capabilities.slice(0,19) and int(short_work.samples)==18 and int(long_work.samples)==120,"short forecast is the exact numerical prefix of the unchanged private120-step reference")
	check(var_to_bytes(st.ships)==live_before and st.rng.state==rng_before,"forecast copies never change real hulls, stores, equipment or RNG")
	var at_30: Dictionary=Rollout.prefix(st,own,candidate,fresh_budget(),{"rolloutSamples":0},1.0/30.0,1,null,9)
	check(at_30.ok and at_30.poses.size()==10 and at_30.capabilities.size()==10,"1/30 caller also retains every exact step through the authority-covering forecast")
	# Budget provenance: denial cannot claim this route was geometrically blocked.
	var no_second: Dictionary=fresh_budget();no_second.rolled[str(ship.id)]=true
	var denied: Dictionary=Certification.certify(st,view,own,candidate,Planner.fingerprint(candidate),no_second)
	check(str(denied.status)=="pending" and int(no_second.clearanceTests)==0 and int(no_second.samples)==0 and int(no_second.exhaustions)==1,"already-rolled hull returns pending before any repeated corridor or forecast work")
	var capped: Dictionary=fresh_budget();capped.samples=840
	denied=Certification.certify(st,view,own,candidate,Planner.fingerprint(candidate),capped)
	check(str(denied.status)=="pending" and int(capped.clearanceTests)==0 and int(capped.samples)==840,"exhausted sample budget refuses early without fabricating blocked geometry")
	var authority: Dictionary=st.duplicate(true)
	# The shorter forecast must not hide land farther along the reserved exit.
	var exit_candidate: Dictionary=candidate.duplicate(true)
	exit_candidate.approach=[Vector2(650.0,650.0)];exit_candidate["pass"]=[];exit_candidate.exit=[Vector2(1000.0,650.0)]
	st.islands=[{"points":[[800.0,600.0],[840.0,600.0],[840.0,700.0],[800.0,700.0]]}]
	st.tactical.geometry=Routes.terrain(st)
	check(str(Certification.corridor(st,own,exit_candidate,fresh_budget()).status)=="blocked","full exit corridor still rejects land well beyond0.3s physical lookahead")
	st.islands=[];st.tactical.geometry=Routes.terrain(st)
	var ally: Dictionary=enemy.duplicate(true);ally.id="close-ally";ally.team="player";ally.x=ship.x+1.0;ally.y=ship.y
	st.tactical.cells=Routes.grid([ship,ally])
	var turning_cert: Dictionary={"rolloutSamples":0}
	var turning: Dictionary=Rollout.prefix(st,own,candidate,fresh_budget(),turning_cert,DT,2,null,9)
	check(not bool(turning.ok) and str(turning_cert.get("status",""))=="blocked" and int(turning_cert.rolloutSamples)==9,"final partial forecast chunk still checks all curved poses against allied traffic")
	var blocked: Dictionary=Certification.safe_step(st,ship,{"angle":ship.angle,"throttle":0.9},fresh_budget())
	check(bool(blocked.get("blocked",false)) and float(blocked.throttle)==0.0,"unchanged live-step swept allied collision check still brakes")
	var exhausted: Dictionary=fresh_budget();exhausted.clearanceLimit=0
	blocked=Certification.safe_step(st,ship,{"angle":ship.angle,"throttle":0.9},exhausted)
	check(bool(blocked.get("blocked",false)) and float(blocked.throttle)==0.0,"live safety still brakes when clearance work is unavailable")
	st.tactical.cells=Routes.grid(st.ships)
	# Probe the authority edge with the actual stored prediction, not a new move.
	var boundary: Dictionary=authority.duplicate(true);var boundary_ship: Dictionary=boundary.ships[0]
	boundary.time=float(cert.validUntil)
	var edge_index: int=roundi((float(boundary.time)-float(cert.checkedAt)+DT)/DT)
	boundary_ship.merge(record.poses[edge_index],true)
	check(bool(Certification.current(boundary,boundary_ship,intent,DT).ok),"authority end plus next exact physics/fire step is covered by real stored poses")
	boundary.time+=DT
	check(not bool(Certification.current(boundary,boundary_ship,intent,DT).ok),"expired0.2s authority cannot borrow the remaining forecast tail")
	var authority_ship: Dictionary=authority.ships[0]
	check(not bool(Certification.current(authority,authority_ship,intent,0.3+DT).ok),"out-of-horizon pose lookup fails closed rather than clamping to the last pose")
	var module_uid: String=""
	for uid in authority_ship.moduleCondition.items:
		if str(authority_ship.moduleCondition.items[uid].location)=="mount0":module_uid=str(uid)
	check(not module_uid.is_empty() and bool(Core.apply_component_damage(authority_ship.moduleCondition,{"itemUid":module_uid,"loss":0.05,"cause":"authority fixture"}).ok),"real component damage is applied inside current authority")
	var damaged: Dictionary=Certification.current(authority,authority_ship,intent,DT)
	check(not bool(damaged.ok) and str(damaged.reason)=="Damage or capability changed; reassessing","immediate real module damage still invalidates the short certificate")
	report.prefix={"authoritySeconds":0.2,"physicalSeconds":0.3,"exactSteps60Hz":18,"exactSteps30Hz":9,"fullCorridor":true,"liveCollisionSafety":true}

func engagement_tick(st: Dictionary,evidence: Dictionary) -> void:
	# Observe existing records only. No status/current/gate/planner calls, RNG or
	# extra update: this runs outside the measured Battle.update clock.
	var t: Dictionary=st.tactical
	var sample: Dictionary={"time":float(st.time),"publishedIntents":0,"intentHulls":t.intents.size(),"pendingHulls":t.pending.size(),"movedBoats":0}
	for row in t.trace:
		if row.has("time") and float(row.time)==float(st.time):
			sample.publishedIntents+=1;evidence.publishedIntents+=1
			evidence.byId[str(row.shipId)].publishedIntents+=1
	for ship in st.ships:
		var id: String=str(ship.id);var hull: Dictionary=evidence.byId[id]
		var position: Vector2=Vector2(ship.x,ship.y);var distance: float=position.distance_to(hull.last)
		hull.distance+=distance;hull.last=position;hull.displacement=position.distance_to(hull.start)
		if distance>0.0001:sample.movedBoats+=1
		hull.pending=t.pending.has(id);hull.hasIntent=t.intents.has(id);hull.reason=str(t.reasons.get(id,""))
		if hull.pending:
			evidence.pendingReasonCounts[hull.reason]=int(evidence.pendingReasonCounts.get(hull.reason,0))+1
		for reason in t.fireReasons.get(id,{}).values():
			if str(reason)=="Firing lane ready":evidence.readyMountTicks+=1
			else:evidence.withheldReasonCounts[str(reason)]=int(evidence.withheldReasonCounts.get(str(reason),0))+1
	evidence.samples.append(sample)

func common_reasons(counts: Dictionary) -> Array:
	var rows: Array=[]
	for reason in counts:rows.append({"reason":str(reason),"count":int(counts[reason])})
	rows.sort_custom(func(a,b):return int(a.count)>int(b.count) if int(a.count)!=int(b.count) else str(a.reason)<str(b.reason))
	return rows.slice(0,5)

func light_window(world: Dictionary) -> void:
	var section: Dictionary={"hull":"bilge_punt","seed":SEED,"terrain":"Unchanged public Lab default islands/formation","dt":DT,"warmupRequested":WARMUP,"measuredRequested":MEASURED,"warmupCompleted":0,"measuredCompleted":0,"warmupUs":[],"ticksUs":[],"aiUs":[],"samples":[],"events":0,"fireEvents":0,"eventKinds":{},"fireFamilies":{},"peakProjectiles":0,"peakEffects":0,"peakRouteCacheEntries":0,"work":{}}
	report.lightBattle=section
	var single: Dictionary={"player":[Lab.entry(world,"bilge_punt")],"enemy":[Lab.entry(world,"bilge_punt")]}
	var quote: Dictionary=Lab.inspect(world,single)
	check(quote.ok and int(quote.player.points)>0,"public Lab quotes a finite positive light-boat deployment cost")
	if not quote.ok or int(quote.player.points)<=0:return
	var count: int=mini(40,floori(300.0/float(quote.player.points)))
	section.unitPoints=int(quote.player.points);section.requestedBoatsPerSide=count
	var config: Dictionary={"player":[Lab.entry(world,"bilge_punt",count)],"enemy":[Lab.entry(world,"bilge_punt",count)]}
	section.quote=Lab.inspect(world,config)
	if not admit("light Lab.create"):return
	var before: int=Time.get_ticks_usec();var created: Dictionary=Lab.create(world,config,SEED)
	section.createUs=Time.get_ticks_usec()-before
	check(created.ok,"public Lab creates both canonical near300DP light fleets")
	if not created.ok:return
	var st: Dictionary=created.battle
	check(not st.has("startError"),"real Lab deployment fits every requested light hull in safe water")
	if st.has("startError"):section.startError=str(st.startError);return
	var players: Array=st.ships.filter(func(ship):return str(ship.team)=="player")
	var enemies: Array=st.ships.filter(func(ship):return str(ship.team)=="enemy")
	section.actual={"playerBoats":players.size(),"enemyBoats":enemies.size(),"playerPoints":Deployment.total(players),"enemyPoints":Deployment.total(enemies),"totalBoats":st.ships.size()}
	check(players.size()==count and enemies.size()==count and int(section.actual.playerPoints)==count*int(section.unitPoints) and int(section.actual.enemyPoints)==count*int(section.unitPoints) and int(section.actual.playerPoints)>300-int(section.unitPoints) and int(section.actual.playerPoints)<=300,"actual deployed boats on both sides match the derived near300DP quote")
	var evidence: Dictionary={"scope":"All completed warmup+measured ticks from unchanged spawn; movement cutoff0.0001world units. Publication means actual accepted trace row; a stored intent alone may be pending. Reason counts are hull-ticks or mount-ticks, not unique refusals. This short window is not sustained engagement proof.","samples":[],"byId":{},"publishedIntents":0,"readyMountTicks":0,"pendingReasonCounts":{},"withheldReasonCounts":{}}
	section.engagement=evidence
	for ship in st.ships:
		var position: Vector2=Vector2(ship.x,ship.y)
		evidence.byId[str(ship.id)]={"team":str(ship.team),"start":position,"last":position,"distance":0.0,"displacement":0.0,"publishedIntents":0}
	var previous: int=0
	for tick in range(WARMUP+MEASURED):
		if st.result!=null or not admit("light tick %d"%tick,previous):break
		before=Time.get_ticks_usec();Battle.update(st,DT);previous=Time.get_ticks_usec()-before
		var measured: bool=tick>=WARMUP
		section["ticksUs" if measured else "warmupUs"].append(previous)
		section["measuredCompleted" if measured else "warmupCompleted"]+=1
		if measured:
			section.aiUs.append(int(st.tactical.metrics.aiUs))
			var sample: Dictionary={"tick":tick-WARMUP+1,"simTime":float(st.time),"updateUs":previous,"aiUs":int(st.tactical.metrics.aiUs)}
			if st.tactical.metrics.get("phaseUs") is Dictionary:sample.phaseUs=st.tactical.metrics.phaseUs.duplicate(true)
			if st.tactical.metrics.get("planningDetailUs") is Dictionary:sample.planningDetailUs=st.tactical.metrics.planningDetailUs.duplicate(true)
			if st.tactical.metrics.get("planningCalls") is Dictionary:sample.planningCalls=st.tactical.metrics.planningCalls.duplicate(true)
			section.samples.append(sample)
			for key in ["fullRoutes","cacheHits","rollouts","samples","clearanceTests","exhaustions"]:section.work[key]=int(section.work.get(key,0))+int(st.tactical.metrics.work[key])
			section.peakRouteCacheEntries=maxi(int(section.peakRouteCacheEntries),int(st.tactical.metrics.work.cacheEntries))
		for event in Battle.pop_events(st):
			section.events+=1
			section.eventKinds[str(event.kind)]=int(section.eventKinds.get(str(event.kind),0))+1
			if str(event.kind)=="fire":
				section.fireEvents+=1;section.fireFamilies[str(event.family)]=int(section.fireFamilies.get(str(event.family),0))+1
		section.peakProjectiles=maxi(int(section.peakProjectiles),st.projectiles.size());section.peakEffects=maxi(int(section.peakEffects),st.effects.size())
		engagement_tick(st,evidence)
	evidence.movedBoats=0;evidence.movedBySide={"player":0,"enemy":0};evidence.boatsWithPublishedIntents=0
	for hull in evidence.byId.values():
		if float(hull.distance)>0.0001:evidence.movedBoats+=1;evidence.movedBySide[str(hull.team)]+=1
		if int(hull.publishedIntents)>0:evidence.boatsWithPublishedIntents+=1
		hull.erase("start");hull.erase("last")
	evidence.commonPendingReasons=common_reasons(evidence.pendingReasonCounts);evidence.commonWithheldReasons=common_reasons(evidence.withheldReasonCounts)
	section.timing=distribution(section.ticksUs);section.aiTiming=distribution(section.aiUs)
	section.simSeconds=float(st.time);section.result=st.result;section.eventTicks=int(section.warmupCompleted)+int(section.measuredCompleted)
	section.complete=int(section.warmupCompleted)==WARMUP and int(section.measuredCompleted)==MEASURED
	var finite: bool=true
	for ship in st.ships:finite=finite and is_finite(float(ship.hp)) and is_finite(float(ship.x)) and is_finite(float(ship.y)) and float(ship.ammo)>=0.0
	check(finite,"short crowded light-boat simulation retains finite positions/HP and nonnegative ammunition")
	check(bool(section.complete) and is_equal_approx(float(st.time),(WARMUP+MEASURED)*DT),"all requested light-boat ticks complete at the actual 1/60dt; a partial window never passes")
	check(evidence.samples.size()==int(section.warmupCompleted)+int(section.measuredCompleted) and evidence.byId.size()==st.ships.size(),"every actual hull and completed tick has read-only movement/approval/refusal evidence, including honest zero engagement")
	print("HOTPATH040 engagement moved=%d/%d approvedPublications=%d approvedHulls=%d pending=%s fireWithheld=%s"%[evidence.movedBoats,st.ships.size(),evidence.publishedIntents,evidence.boatsWithPublishedIntents,JSON.stringify(evidence.commonPendingReasons),JSON.stringify(evidence.commonWithheldReasons)])
	print("HOTPATH040 light boats=%d points=%d/%d warmup=%d/%d measured=%d/%d events=%d medianUs=%s p95Us=%s aiUs=%s"%[st.ships.size(),section.actual.playerPoints,section.actual.enemyPoints,section.warmupCompleted,WARMUP,section.measuredCompleted,MEASURED,section.events,str(section.timing.medianUs),str(section.timing.p95Us),str(section.aiTiming.totalUs)])

func _initialize() -> void:
	started_us=Time.get_ticks_usec()
	if DisplayServer.get_name()!="headless":
		check(false,"requires Root's headless/Dummy Test Bridge invocation")
		print("%d checks, %d failures"%[checks,failures.size()]);quit(1);return
	report={"schema":1,"fixture":"combat_hotpath040","fixtureSha256":FileAccess.get_sha256(get_script().resource_path),"worldSha256":FileAccess.get_sha256("res://data/world.json"),"sourceBinding":"Root's exact-source Test Bridge receipt binds all res:// code.","envelope":{"externalDeadlineSeconds":30,"admissionUs":ADMISSION_US,"gameMiB":512,"builderMiB":1024,"jobCpuPercent":8,"logicalCpuLimit":2,"enforcement":"External Test Bridge job; this fixture changes no system settings."},"limits":"Short headless CPU simulation under caps; not measured FPS, rendered gameplay, listening, or long-run throughput. aiUs overlaps total update time. Events include warmup and measured ticks; timings and work counters cover measured ticks only. Queue/startup/import are outside this fixture clock and remain in Root's batch receipt."}
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var duo: Dictionary=Lab.create(world,{"player":[Lab.entry(world,"bilge_punt")],"enemy":[Lab.entry(world,"bilge_punt")]},SEED)
	var duo_ok: bool=bool(duo.ok) and not duo.get("battle",{}).has("startError")
	check(duo_ok,"public Lab creates the small authentic equivalence fixture")
	if duo_ok:
		safety_checks(duo.battle.ships[0])
		if admit("prefix authority and safety"):prefix_checks(duo.battle)
		if admit("trace equivalence"):trace_checks(duo.battle)
	light_window(world)
	check(stops.is_empty() and bool(report.lightBattle.get("complete",false)),"no guard stop or incomplete measurement is accepted")
	check(Time.get_ticks_usec()-started_us<30000000,"cooperative fixture work finishes inside Root's external30s boundary")
	report.guardStops=stops;report.complete=stops.is_empty() and bool(report.lightBattle.get("complete",false))
	report.wallUs=Time.get_ticks_usec()-started_us;report.engineStaticBytes=OS.get_static_memory_usage();report.engineStaticPeakBytes=OS.get_static_memory_peak_usage()
	var folder: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	check(not folder.is_empty(),"GAME_TEST_ARTIFACTS supplies an explicit evidence destination")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		var file=FileAccess.open(folder.path_join("COMBAT HOTPATH v0.040.json"),FileAccess.WRITE)
		check(file!=null,"hot-path measurement artifact opens")
		if file!=null:
			report.status="partial" if not bool(report.complete) else ("complete" if failures.is_empty() else "failed")
			report.checks=checks;report.failures=failures;report.passed=failures.is_empty();file.store_string(JSON.stringify(report,"\t"));file.close()
	print("%d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
