extends SceneTree
## Bounded source candidate. Root alone runs this fixture through Test Bridge.
## Measures trajectories and real damage control, without AI, shots or rendering.
const Damage=preload("res://scripts/damage.gd")
const Rollout=preload("res://scripts/equipment_rollout.gd")
const Certification=preload("res://scripts/tactical_certification.gd")
const Battle=preload("res://scripts/battle.gd")
const Refit=preload("res://scripts/refit.gd")
const Records=preload("res://scripts/equipment_records.gd")
const Core=preload("res://scripts/equipment_condition.gd")
const STEP: float=1.0/30.0
const OPEN_WATER: Dictionary={"islands":[]}
var world: Dictionary={}
var checks: int=0
var failures: Array=[]
var metrics: Dictionary={}

func check(ok: bool,message: String) -> bool:
	checks+=1
	if not ok:failures.append(message);print("FAIL combat_pressure044: "+message)
	return ok

func _initialize() -> void:call_deferred("run")

func boat(hull_id: String) -> Dictionary:
	var base: Dictionary={}
	for spec in world.HULLS:
		if str(spec.id)==hull_id:base=spec
	if not check(not base.is_empty(),"authored hull exists: "+hull_id):return {}
	var s: Dictionary=Damage.create_ship(base,{"id":"pressure-"+hull_id,"uid":"pressure044-"+hull_id,"team":"player","x":700.0,"y":850.0})
	s.loadout=Refit.defaults(base)
	var seeded: Dictionary=Records.initialize(s,{"base":base.duplicate(true),"loadout":s.loadout.duplicate(true),"catalog":Refit.catalog(),"identity":s.uid,"knownUids":[]})
	if not check(bool(seeded.ok),"canonical stock equipment birth: "+hull_id):return {}
	Refit.ensure(s,base)
	check(str(Damage.get_status(s).equipmentMode)=="canonical","measurement uses actual canonical condition: "+hull_id)
	return s

func speed(s: Dictionary) -> float:return Vector2(s.vx,s.vy).length()
func point(s: Dictionary) -> Vector2:return Vector2(s.x,s.y)

func stopping(source: Dictionary,launch_speed: float) -> Dictionary:
	var s: Dictionary=source.duplicate(true)
	s.vx=launch_speed;s.vy=0.0
	var start: Vector2=point(s)
	var stopped: float=-1.0
	var straight: bool=true
	for tick in range(240):
		s.merge(Certification.motion(s,STEP,0.0,0.0),true)
		straight=straight and float(s.vx)>=0.0 and absf(float(s.y)-start.y)<0.000001
		if speed(s)<=0.5:stopped=(tick+1)*STEP;break
	return {"seconds":stopped,"distance":point(s).distance_to(start),"initial_speed":launch_speed,"final_speed":speed(s),"straight":straight}

func response(source: Dictionary) -> Dictionary:
	var s: Dictionary=source.duplicate(true)
	var fraction_at_one: float=0.0
	for tick in range(90):
		s.merge(Certification.motion(s,STEP,0.0,1.0),true)
		if tick==29:fraction_at_one=speed(s)/float(s.spec.speed)
	var turning: Dictionary=source.duplicate(true)
	turning.vx=float(turning.spec.speed)
	var bow_time: float=-1.0
	var course_time: float=-1.0
	var bow_error: float=0.0
	var max_bow_step: float=0.0
	for tick in range(150):
		var before: float=turning.angle
		turning.merge(Certification.motion(turning,STEP,PI/2.0,1.0),true)
		max_bow_step=maxf(max_bow_step,absf(angle_difference(before,float(turning.angle))))
		bow_error=absf(angle_difference(float(turning.angle),PI/2.0))
		if bow_time<0.0 and bow_error<0.03:bow_time=(tick+1)*STEP
		if speed(turning)>10.0 and absf(angle_difference(Vector2(turning.vx,turning.vy).angle(),PI/2.0))<deg_to_rad(5.0):
			course_time=(tick+1)*STEP;break
	return {"fraction_at_1s":fraction_at_one,"fraction_at_3s":speed(s)/float(s.spec.speed),"bow_seconds":bow_time,"course_seconds":course_time,"course_lag_seconds":course_time-bow_time,"forward_travel":float(turning.x)-float(source.x),"max_bow_step":max_bow_step,"final_bow_error":bow_error}

func hurt_engine(s: Dictionary,loss: float) -> void:
	for item in s.moduleCondition.items.values():
		if str(item.location)=="engine":
			check(bool(Core.apply_component_damage(s.moduleCondition,{"itemUid":str(item.itemUid),"loss":loss,"cause":"Withdrawal recovery fixture"}).ok),"damage actual installed engine")
			check(bool(Records.publish(s).ok),"publish actual engine condition")
			return
	check(false,"canonical boat has an engine")

func live_forecast(source: Dictionary) -> void:
	var live: Dictionary=source.duplicate(true)
	var forecast: Dictionary=source.duplicate(true)
	var matched: bool=true
	var pure: bool=true
	for tick in range(90):
		if tick==40:live.fuel=0.0;forecast.fuel=0.0
		if tick==60:hurt_engine(live,0.85);hurt_engine(forecast,0.85)
		Damage.tick_ship(live,STEP,{"inCombat":true});Damage.tick_ship(forecast,STEP,{"inCombat":true})
		var heading: float=0.0 if tick<20 else PI/2.0
		var throttle: float=1.0 if tick<70 else 0.0
		var boost: bool=tick<15
		var status: Dictionary=Damage.get_status(forecast)
		var before: PackedByteArray=var_to_bytes([forecast,status])
		var direct: Dictionary=Rollout.motion_with_status(forecast,STEP,heading,throttle,boost,status)
		var next: Dictionary=Certification.motion(forecast,STEP,heading,throttle,boost)
		pure=pure and before==var_to_bytes([forecast,status]) and var_to_bytes(direct)==var_to_bytes(next)
		Battle._move(OPEN_WATER,live,STEP,heading,throttle,boost)
		forecast.merge(next,true)
		for key in ["x","y","vx","vy","angle","fuel"]:
			matched=matched and is_equal_approx(float(live[key]),float(forecast[key]))
	check(matched,"live and forecast trajectories/fuel agree through boost, turn, fuel loss, engine loss and braking: "+str(source.type))
	check(pure,"motion/status inputs are read-only and both forecast entry points agree: "+str(source.type))

func withdrawal(skiff: Dictionary,corvette: Dictionary) -> Dictionary:
	var departures: Array=[skiff.duplicate(true),skiff.duplicate(true)]
	var chasers: Array=[corvette.duplicate(true),corvette.duplicate(true)]
	var leaked: Dictionary=departures[1]
	leaked.water=float(leaked.capacity)*0.25
	leaked.breaches=[{"area":90.0,"section":"bow"}]
	leaked.supplies=0.02
	leaked.hp*=0.85
	for s in departures:
		s.vx=float(s.spec.speed);Damage.set_policy(s,"fight")
	for s in chasers:
		s.x=float(skiff.x)-float(skiff.spec.range);s.vx=float(s.spec.speed)
	var escape_times: Array=[-1.0,-1.0]
	var start_supply: float=leaked.supplies
	var start_ammo: float=leaked.ammo
	var crew_ok: bool=true
	for tick in range(300):
		for i in range(2):
			var s: Dictionary=departures[i]
			var foe: Dictionary=chasers[i]
			var flow: Dictionary=Damage.tick_ship(s,STEP,{"inCombat":true})
			Damage.tick_ship(foe,STEP,{"inCombat":true})
			crew_ok=crew_ok and float(flow.crewGuns)+float(flow.crewBail)+float(flow.crewRepair)<=float(s.crew)-float(s.wounded)+0.000001
			Battle._move(OPEN_WATER,s,STEP,0.0,1.0,false);Battle._move(OPEN_WATER,foe,STEP,0.0,1.0,false)
			if float(escape_times[i])<0.0 and point(s).distance_to(point(foe))>float(foe.spec.range):escape_times[i]=(tick+1)*STEP
	var early_gap: float=point(departures[0]).distance_to(point(chasers[0]))
	var late_gap: float=point(leaked).distance_to(point(chasers[1]))
	check(float(escape_times[0])>0.0 and float(escape_times[0])<10.0,"dry skiff leaves the real corvette range within the bounded withdrawal")
	check(float(escape_times[1])<0.0 and late_gap<early_gap,"overcommitted leaking skiff cannot repeat that escape against the same pursuit")
	check(float(leaked.water)>0.0 and Damage.sum_areas(leaked)>0.0 and not leaked.sunk,"late withdrawal retains actual flooding and an unclosed breach")
	check(float(leaked.supplies)<start_supply and float(leaked.supplies)>=0.0 and float(leaked.ammo)==start_ammo and crew_ok,"withdrawal uses finite patch kits and shared crew without inventing ammunition")
	return {"late":leaked,"metrics":{"early_escape_seconds":escape_times[0],"late_escape_seconds":escape_times[1],"early_gap":early_gap,"late_gap":late_gap,"late_water":leaked.water,"late_breach_area":Damage.sum_areas(leaked),"late_kits":leaked.supplies}}

func damage_control(s: Dictionary,seconds: float,policy: String,ledger: Dictionary) -> void:
	Damage.set_policy(s,policy)
	for _tick in range(int(round(seconds/STEP))):
		var before: float=s.supplies
		var report: Dictionary=Damage.tick_ship(s,STEP,{"inCombat":true})
		ledger.used_work+=float(report.usedWork);ledger.available_work+=float(report.availableWork)
		ledger.used_kits+=float(report.usedSupplies)
		ledger.conserved=bool(ledger.conserved) and bool(report.equipmentOk) and float(report.usedWork)<=float(report.availableWork)+0.000001 and absf(before-float(s.supplies)-float(report.usedSupplies))<0.000001 and float(s.supplies)>=0.0

func recovery(late: Dictionary) -> void:
	var damaged: Dictionary=late.duplicate(true)
	hurt_engine(damaged,0.55)
	var supplied: Dictionary=damaged.duplicate(true)
	var empty: Dictionary=damaged.duplicate(true)
	# Paired snapshots with different carried kits; no stores are added mid-run.
	supplied.supplies=3.0;empty.supplies=0.0
	var start: Dictionary=Damage.get_status(damaged)
	var start_water: float=damaged.water
	var start_area: float=Damage.sum_areas(damaged)
	var ledgers: Array=[]
	for s in [supplied,empty]:
		var ledger: Dictionary={"used_work":0.0,"available_work":0.0,"used_kits":0.0,"conserved":true}
		damage_control(s,6.0,"bail",ledger)
		check(float(s.water)<start_water,"existing bail policy drains water with real crew, even without kits")
		damage_control(s,24.0,"repair",ledger)
		ledgers.append(ledger)
	var fixed: Dictionary=Damage.get_status(supplied)
	var unfixed: Dictionary=Damage.get_status(empty)
	check(Damage.sum_areas(supplied)<0.001 and float(supplied.water)<start_water*0.25,"carried kits and repair hands close the breach and recover water clearance")
	check(float(fixed.engineHp)>float(start.engineHp) and float(fixed.engineHp)<=float(fixed.juryCap)+0.000001,"actual field engine repair improves condition only to its existing jury cap")
	check(is_equal_approx(float(unfixed.engineHp),float(start.engineHp)) and is_equal_approx(Damage.sum_areas(empty),start_area) and float(empty.supplies)==0.0,"no kits grant no free patching or machinery recovery")
	check(float(fixed.speedFactor)>float(unfixed.speedFactor) and float(supplied.water)<float(empty.water),"successful recovery restores more usable movement than empty-store bailing alone")
	for i in range(2):
		var s: Dictionary=[supplied,empty][i]
		check(bool(ledgers[i].conserved) and float(ledgers[i].used_work)<=float(ledgers[i].available_work)+0.000001,"real damage-control work and kit debits remain finite and conserved")
		check(float(s.crew)==float(damaged.crew) and float(s.ammo)==float(damaged.ammo),"recovery does not create crew or ammunition")
	check(absf(3.0-float(supplied.supplies)-float(ledgers[0].used_kits))<0.000001,"funded recovery's kit ledger agrees with remaining stores")
	# Start a separate return leg from rest; the stopping measurements above own braking.
	var returning: Dictionary=supplied.duplicate(true)
	returning.vx=0.0;returning.vy=0.0
	var origin: Vector2=point(returning)
	var fuel_before: float=returning.fuel
	for _tick in range(30):Battle._move(OPEN_WATER,returning,STEP,0.0,1.0,false)
	check(point(returning).distance_to(origin)>20.0 and float(returning.fuel)<fuel_before,"recovered boat can begin a return leg while still spending real propulsion fuel")
	metrics.recovery={"seconds":30.0,"carried_kits":3.0,"remaining_kits":supplied.supplies,"used_kits":ledgers[0].used_kits,"used_work":ledgers[0].used_work,"water_after":supplied.water,"empty_water_after":empty.water,"engine_after":fixed.engineHp,"empty_engine_after":unfixed.engineHp,"return_distance_1s":point(returning).distance_to(origin)}

func run() -> void:
	if DisplayServer.get_name()!="headless":quit(2);return
	world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var light: Dictionary=boat("tin_skiff")
	var medium: Dictionary=boat("ash_corvette")
	var heavy: Dictionary=boat("furnace_turret")
	if light.is_empty() or medium.is_empty() or heavy.is_empty():quit(1);return
	var light_stop: Dictionary=stopping(light,float(light.spec.speed))
	var medium_stop: Dictionary=stopping(medium,float(medium.spec.speed))
	var heavy_stop: Dictionary=stopping(heavy,float(heavy.spec.speed))
	for result in [light_stop,medium_stop,heavy_stop]:
		check(float(result.seconds)>0.0 and float(result.final_speed)<=0.5 and bool(result.straight),"healthy hull stops without reverse motion within eight simulated seconds")
	check(float(light_stop.seconds)<1.6 and float(light_stop.distance)<35.0,"light skiff retains prompt braking from its actual cruising speed")
	check(float(light_stop.seconds)<float(medium_stop.seconds) and float(medium_stop.seconds)<float(heavy_stop.seconds),"stopping time increases across the three actual hull sizes")
	check(float(heavy_stop.distance)>float(light_stop.distance)*1.15,"heavy hull needs more stopping distance despite its lower cruising speed")
	var equal_light: Dictionary=stopping(light,60.0)
	var equal_heavy: Dictionary=stopping(heavy,60.0)
	check(float(equal_heavy.distance)>float(equal_light.distance)*1.5 and float(equal_heavy.seconds)>float(equal_light.seconds)*1.5,"equal-speed trial isolates heavier hull momentum from different top speeds")
	var light_response: Dictionary=response(light)
	var medium_response: Dictionary=response(medium)
	var heavy_response: Dictionary=response(heavy)
	check(float(light_response.fraction_at_1s)>0.95 and float(heavy_response.fraction_at_1s)>0.75,"light boats stay agile and heavy acceleration remains usable")
	check(float(light_response.fraction_at_1s)>float(medium_response.fraction_at_1s) and float(medium_response.fraction_at_1s)>float(heavy_response.fraction_at_1s),"larger hulls take longer to acquire their own cruising speed")
	check(float(heavy_response.course_seconds)>float(light_response.course_seconds)*1.3 and float(heavy_response.course_lag_seconds)>float(light_response.course_lag_seconds),"heavy course changes carry the previous velocity longer after the bow turns")
	for pair in [[light,light_response],[medium,medium_response],[heavy,heavy_response]]:
		var result: Dictionary=pair[1]
		check(float(result.fraction_at_3s)>0.98 and float(result.fraction_at_3s)<=1.000001,"inertia retains the actual cruising-speed target")
		check(float(result.bow_seconds)>0.0 and float(result.course_seconds)>0.0 and float(result.final_bow_error)<0.03 and float(result.max_bow_step)<=float(pair[0].spec.turn)*STEP+0.000001,"bow/course settle without exceeding the existing hull turn limit")
	live_forecast(light);live_forecast(heavy)
	var escape: Dictionary=withdrawal(light,medium)
	recovery(escape.late)
	metrics.stopping={"light":light_stop,"medium":medium_stop,"heavy":heavy_stop,"equal_speed_light":equal_light,"equal_speed_heavy":equal_heavy}
	metrics.response={"light":light_response,"medium":medium_response,"heavy":heavy_response}
	metrics.withdrawal=escape.metrics
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file: FileAccess=FileAccess.open(arg.substr(6),FileAccess.WRITE)
			if file==null:check(false,"Root-owned report path is writable")
			else:file.store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":metrics}));file.close()
	print("combat_pressure044 metrics "+JSON.stringify(metrics))
	print("combat_pressure044: %d checks, %d failures; numerical movement only"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
