extends SceneTree
## SOURCE CANDIDATE ONLY. Root runs it through the shared native lane.
## One initialized Main/Core. Initial funded fixture: real treasury capital,
## purchased second hull/crew, paid auxiliary tanks, quartermaster and stores.
## Initial morale is declared 100 so fully funded daily morale cannot change
## speed. No clock, damage, position or store edits occur during actual travel.
const Money=preload("res://scripts/money.gd")
var scene
var c
var checks: int=0
var failures: int=0
var started: int=0
var moving_seconds: float=0.0
var course_count: int=0
var supply: int=0
var source_uid: String=""
var target_uid: String=""
var receipt: Dictionary={"status":"UNFINISHED"}

func check(ok: bool,message: String) -> bool:
	checks+=1
	if not ok:failures+=1;print("FAIL long voyage065: ",message)
	return ok

func within_budget() -> bool:
	if Time.get_ticks_msec()-started<55000:return true
	receipt.status="BODY_TIMEOUT"
	return check(false,"55-second whole fixture body watchdog; remaining work is unproved")

func same(a,b) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in range(a.size()):
			if not same(a[i],b[i]):return false
		return true
	return a==b

func protected_state() -> PackedByteArray:
	return var_to_bytes([c.state,c.pending_days,c.events,c.data,scene.economy_task])

func without_tank_values() -> Dictionary:
	var saved: Dictionary=c.state.duplicate(true)
	for boat in saved.fleet:boat.erase("fuel")
	return saved

func intent_remote() -> Dictionary:
	return {"targetRegionId":"glasswind_keys","targetApproachId":"south","outExit":"north","backExit":"south","homeEntry":"north","returnPortId":"brass_haven","idleDays":0.25}

func intent_home() -> Dictionary:
	return {"targetRegionId":"shatter_coast","targetApproachId":"north","outExit":"south","backExit":"","homeEntry":"","returnPortId":"brass_haven","idleDays":0.0}

func intent_here(intent: Dictionary) -> Dictionary:
	# Mirror the locked seven-field UI selection rule as the actual layer changes.
	# Explicit selected gate IDs stay intact whenever that crossing is needed.
	var chosen: Dictionary=intent.duplicate(true)
	if c.state.world064.layer=="ocean" or c.state.world064.regionId==chosen.targetRegionId:chosen.outExit=""
	if chosen.targetRegionId=="shatter_coast":
		chosen.backExit="";chosen.homeEntry=""
		if c.home_local064():chosen.targetApproachId=""
	return chosen

func button_in(node: Node,caption: String) -> Button:
	if node is Button and str(node.text)==caption:return node
	for child in node.get_children():
		var found: Button=button_in(child,caption)
		if found!=null:return found
	return null

func quote_row(quote: Dictionary,uid: String) -> Dictionary:
	for row in quote.get("stores",{}).get("boats",[]):
		if str(row.get("uid",""))==uid:return row
	return {}

func exact_transfer(source: String,target: String,quantity: float) -> bool:
	var a: float=float(c.find_boat(source).fuel)
	var b: float=float(c.find_boat(target).fuel)
	var other: Dictionary=without_tank_values()
	var before_day: float=float(c.state.day)
	var result: Dictionary=c.transfer_fuel065(source,target,quantity)
	if not check(bool(result.get("ok",false)),"Exact explicit tank transfer: "+str(result.get("message",""))):return false
	check(float(c.find_boat(source).fuel)==a-quantity and float(c.find_boat(target).fuel)==b+quantity,"Exactly the requested quantity moves; no partial clamp")
	check(float(c.find_boat(source).fuel)+float(c.find_boat(target).fuel)==a+b,"Combined working fuel is exactly conserved")
	check(same(without_tank_values(),other) and float(c.state.day)==before_day,"Transfer preserves all other state: coins, cargo/freight, time, crew, damage, fittings and UIDs")
	return true

func transfer_cases() -> void:
	# These exact binary fractions also prove receiving above the base60 limit
	# is permitted by the actual paid auxiliary90 tank, without refitting it.
	if not exact_transfer(source_uid,target_uid,0.125):return
	if not exact_transfer(target_uid,source_uid,0.125):return
	check(float(c.find_boat(source_uid).fuel)>60.0,"Canonical interior conversion supplies actual receiving capacity")
	var anchor: Dictionary=c.state.duplicate(true)
	for kind in ["zero","negative","nan","infinite","same","missing_source","missing_target","npc","stock","room","stored_source","stored_target","sunk_source","sunk_target","moving","battle","encounter","defeat"]:
		var source: String=source_uid
		var target: String=target_uid
		var quantity: float=0.125
		if kind=="zero":quantity=0.0
		elif kind=="negative":quantity=-1.0
		elif kind=="nan":quantity=NAN
		elif kind=="infinite":quantity=INF
		elif kind=="same":target=source
		elif kind=="missing_source":source="not-owned"
		elif kind=="missing_target":target="not-owned"
		elif kind=="npc":source=str(c.fleet_owner("patrol-0").boats[0].uid)
		elif kind=="stock":quantity=float(c.find_boat(source).fuel)+1.0
		elif kind=="room":quantity=58.0
		elif kind=="stored_source":c.find_boat(source).storedPort="brass_haven"
		elif kind=="stored_target":c.find_boat(target).storedPort="brass_haven"
		elif kind=="sunk_source":c.find_boat(source).sunk=true
		elif kind=="sunk_target":c.find_boat(target).sunk=true
		elif kind=="moving":c.state.path=[c.state.position.duplicate()]
		elif kind=="battle":c.travel_lock064="Controlled unresolved battle"
		elif kind=="encounter":c.events=[{"kind":"encounter","patrol":"patrol-0"}]
		elif kind=="defeat":c.events=[{"kind":"defeat"}]
		var protected: PackedByteArray=protected_state()
		check(not c.transfer_fuel065(source,target,quantity).get("ok",false),"Transfer refuses "+kind)
		check(protected_state()==protected,"Refused "+kind+" leaves every state byte unchanged")
		c.state=anchor.duplicate(true);c.travel_lock064="";c.events=[]
	# Explicit real transfer makes the low-fuel purchased escort usable; no
	# quote implicitly draws from the support boat's larger tank.
	exact_transfer(source_uid,target_uid,4.0)
	var before_main: Dictionary=without_tank_values()
	var before_total: float=float(c.find_boat(source_uid).fuel)+float(c.find_boat(target_uid).fuel)
	check(scene.transfer_fuel065(target_uid,source_uid,0.25).get("ok",false),"Main explicit transfer rechecks, saves privately and refreshes the preparation panel")
	check(same(without_tank_values(),before_main) and float(c.find_boat(source_uid).fuel)+float(c.find_boat(target_uid).fuel)==before_total,"Main transfer conserves every nonfuel field and combined fuel")
	scene.ui.close_modal()

func pending_reviews() -> void:
	check(c.pending_days>0 and scene.economy_task<0,"Read-only review starts with genuinely unjoined payroll")
	var protected: PackedByteArray=protected_state()
	var intent: Dictionary=intent_remote()
	var quote: Dictionary=c.voyage_quote065(intent)
	check(quote.get("routeOk",false) and int(quote.get("expected",{}).get("pendingDays",-1))==c.pending_days,"Quote counts pending calendar days once")
	check(protected_state()==protected,"Quote leaves state, world, events and pending payroll exact")
	scene.ui.voyage_intent065=intent.duplicate(true)
	scene.ui.open_voyage_preparation065()
	check(protected_state()==protected and scene.ui.modal_open,"Actual preparation opens without settlement or allocation")
	var refresh: Button=button_in(scene.ui.overlay,"Refresh")
	check(refresh!=null,"Preparation exposes explicit Refresh")
	if refresh!=null:refresh.pressed.emit()
	check(protected_state()==protected,"Actual Refresh button does not settle pending payroll")
	var close: Button=button_in(scene.ui.overlay,"×")
	check(close!=null,"Shared modal header close exists")
	if close!=null:close.pressed.emit()
	check(protected_state()==protected and not scene.ui.modal_open,"Actual header Close pays nothing")
	scene.ui.open_ocean064()
	scene.ui.close_modal()
	check(protected_state()==protected,"Existing approach entry/review/close also stays pure")
	for panel in ["fleet","cargo"]:
		if panel=="fleet":scene.ui.open_fleet()
		else:scene.ui.open_cargo()
		check(protected_state()==protected,"Actual "+panel+" linked view does not settle pending costs")
		close=button_in(scene.ui.overlay,"×")
		check(close!=null,"Actual "+panel+" shared header close exists")
		if close!=null:close.pressed.emit()
		check(protected_state()==protected,"Actual "+panel+" close does not settle pending costs")
	# Detached returns may be edited freely without granting live authority.
	if not quote.get("stores",{}).get("boats",[]).is_empty():quote.stores.boats[0].loadedFuel=-123.0
	check(protected_state()==protected,"Quote's nested tank rows cannot alias live stock")

func quote_variants() -> void:
	var anchor: Dictionary=c.state.duplicate(true)
	var healthy: Dictionary=c.voyage_quote065(intent_remote())
	var target: Dictionary=c.find_boat(target_uid)
	target.fuel=0.0
	var shortage: Dictionary=c.voyage_quote065(intent_remote())
	check(shortage.get("routeOk",false) and not shortage.get("readyForAllowance",true),"Dry escort remains route-valid but reserve-short despite the full support tank")
	check(float(quote_row(shortage,target_uid).get("loadedShortfall",0))>0.0,"Per-hull loaded deficit is visible, never magically shared")
	c.state=anchor.duplicate(true)
	var damaged: Dictionary=c.find_boat(target_uid)
	var engine_uid: String=""
	for item in damaged.moduleCondition.items.values():
		if str(item.location)=="engine":engine_uid=str(item.itemUid)
	var hit: Dictionary=c.Preflight.Core.apply_component_damage(damaged.moduleCondition,{"itemUid":engine_uid,"loss":0.5,"cause":"Declared detached065 damage comparison"})
	check(hit.get("ok",false) and c.Preflight.Records.publish(damaged).get("ok",false),"Damage variant uses canonical actual equipment APIs")
	var slow: Dictionary=c.voyage_quote065(intent_remote())
	check(float(slow.get("timing",{}).get("movingSeconds",0))>float(healthy.get("timing",{}).get("movingSeconds",0)),"Actual damaged speed increases forecast moving time")
	check(not slow.get("maintenance",{}).get("usageKnown",true) and slow.get("maintenance",{}).get("expectedSupplies",0)==null,"Damaged maintenance stays conditional and unknown")
	c.state=anchor.duplicate(true)
	# Controlled inactive existing owned hull, not a newly minted tow.
	target=c.find_boat(target_uid);target.needsHarborRepair=true;target.mothballed=false
	var tow: Dictionary=c.voyage_quote065(intent_remote())
	var row: Dictionary=quote_row(tow,target_uid)
	check(not row.is_empty() and row.get("burnsWhileMoving",false) and not row.get("traveling",true),"Actual fueled repair-only tow stays in moving-burn inventory")
	c.state=anchor.duplicate(true)
	var pursuer: Dictionary=c.fleet_owner("patrol-0")
	pursuer.atPort="";pursuer.order.targetOwnerId="player";pursuer.order.purpose="intercept"
	check(not c.transition_blocker064().is_empty(),"Controlled existing armed hostile pursuit blocks crossing")
	var fleeing: Dictionary=c.voyage_quote065(intent_remote())
	check(fleeing.get("routeOk",false) and not fleeing.get("readyForAllowance",true),"Pursuit is a readiness warning while the safe outward course remains routable")
	check(scene.voyage_action065(intent_remote()).get("ok",false) and not c.state.path.is_empty(),"Main still permits ordinary sailing toward the approach while crossing is blocked")
	c.state=anchor
	scene.ui.close_modal()

func advance(seconds: float,moving: bool) -> bool:
	if not within_budget():return false
	c.step(seconds)
	if moving:moving_seconds+=seconds
	scene.sync_economy()
	check(Money.total(c.state)==supply,"Actual copied-port settlement conserves all world purses")
	for event in c.pop_events():
		if event.get("kind","") in ["encounter","defeat"]:
			receipt.status="INTERRUPTED";receipt.event=event
			return check(false,"Actual voyage interrupted; never counted as arrival")
	return true

func finish_course(fixed_speed: float) -> bool:
	course_count+=1
	for _piece in range(160):
		if c.state.path.is_empty():return true
		if not within_budget():return false
		var length: float=0.0
		var previous: Dictionary=c.state.position
		for point in c.state.path:length+=c.distance(previous,point);previous=point
		var scale_units: float=float(c.ocean_context064.ocean.localUnitsPerUnit) if c.state.world064.layer=="ocean" else 1.0
		var speed: float=c.travel_speed()
		check(absf(speed-fixed_speed)<0.000001,"Declared healthy funded speed remains constant during actual sailing")
		if not advance(minf(4.0,maxf(0.001,length*scale_units/maxf(0.01,speed))),true):return false
	return check(false,"Actual course exceeded160 bounded pieces")

func travel(intent: Dictionary,fixed_speed: float) -> bool:
	for _action in range(8):
		if not within_budget():return false
		var chosen: Dictionary=intent_here(intent)
		var quote: Dictionary=c.voyage_quote065(chosen)
		if not check(quote.get("routeOk",false),"Fresh actual route remains valid: "+str(quote.get("message",""))):return false
		var action: Dictionary=quote.get("nextAction",{})
		if action.get("kind","none")=="none":return true
		var before: Dictionary=c.state.duplicate(true)
		if not check(scene.voyage_action065(chosen).get("ok",false),"Main sync/requote/nextAction executes through the real Core"):return false
		if action.kind=="course":
			if not finish_course(fixed_speed):return false
		else:
			check(c.state.day==before.day and c.state.coins==before.coins and same(c.state.fleet,before.fleet),"Actual crossing changes no time, coins or fleet stores")
	return check(false,"One destination exceeded eight explicit next actions")

func paid_voyage() -> void:
	var planned: Dictionary=c.voyage_quote065(intent_remote())
	if not check(planned.get("routeOk",false),"Funded healthy voyage has an actual route"):return
	var before: Dictionary=c.state.duplicate(true)
	var fixed_speed: float=float(planned.timing.speed)
	var owned: Array=c.state.fleet.map(func(b):return str(b.uid))
	if not travel(intent_remote(),fixed_speed):return
	check(c.state.world064.layer=="local" and c.state.world064.regionId=="glasswind_keys","Outward next actions actually enter Glasswind Keys")
	var outward_moving: float=moving_seconds
	# Review the real return button at the actual remote arrival. The original
	# home-entry choice differs from the outbound arrival side and must survive.
	scene.ui.voyage_intent065=intent_here(intent_remote())
	scene.ui.open_voyage_preparation065()
	var review_before: PackedByteArray=protected_state()
	var return_button: Button=button_in(scene.ui.overlay,"Plan return to Shatter Coast")
	check(return_button!=null,"Actual remote panel exposes return planning")
	if return_button!=null:return_button.pressed.emit()
	check(scene.ui.voyage_intent065.targetRegionId=="shatter_coast" and scene.ui.voyage_intent065.targetApproachId=="north" and scene.ui.voyage_intent065.outExit=="south","Return planning preserves the selected home entry and remote departure")
	check(protected_state()==review_before,"Actual return-plan review changes no voyage, stores or pending payroll")
	scene.ui.close_modal()
	if not advance(float(planned.timing.idleDays)*c.DAY_SECONDS,false):return
	if not travel(intent_home(),fixed_speed):return
	check(c.current_port().get("id","")=="brass_haven","Actual return reaches the named home harbor")
	check(c.state.fleet.map(func(b):return str(b.uid))==owned,"Actual funded round trip retains every owned hull UID")
	var expected: Dictionary=planned.expected
	var actual_days: int=int(c.state.econDay)-int(before.econDay)
	var elapsed_seconds: float=(float(c.state.day)-float(before.day))*c.DAY_SECONDS
	check(actual_days==int(expected.totalPayrollDays),"Expected pending plus chronological future payroll matches actual settled days")
	check(int(before.coins)-int(c.state.coins)==int(expected.coinsRequired),"Actual captain debit equals expected base wages plus premiums, independently of allowance")
	check(absf(float(before.cargo.food)-float(c.state.cargo.food)-float(expected.food))<0.00000001,"Actual rations match once-counted expected day-boundary food")
	var terminal_bound: float=float(course_count)*0.001+0.00001
	check(absf(moving_seconds-float(planned.timing.movingSeconds))<=terminal_bound,"Actual moving time agrees with route distance/current speed under declared terminal-step bound")
	check(absf(outward_moving-float(planned.timing.outwardDays)*c.DAY_SECONDS)<=terminal_bound,"Outward consumption stays distinct from conservative return allowance")
	for boat in c.state.fleet:
		var prior: Dictionary={}
		for original in before.fleet:
			if original.uid==boat.uid:prior=original
		var expected_fuel: float=c.Expedition._fuel_per_day(prior)*moving_seconds/c.DAY_SECONDS
		check(absf(float(prior.fuel)-float(boat.fuel)-expected_fuel)<0.000001,"Actual per-hull moving fuel agrees with the reused canonical burn helper: "+str(boat.uid))
		check(boat.supplies==prior.supplies and boat.hp==prior.hp and same(boat.moduleCondition,prior.moduleCondition),"Dry healthy travel consumes zero repair kits and preserves physical equipment: "+str(boat.uid))
	check(planned.maintenance.usageKnown and planned.maintenance.expectedSupplies==0,"Healthy quote explicitly forecasts zero maintenance use")
	check(Money.total(c.state)==supply,"Paid provisioning, movement and payroll never mint global coins")
	scene.save_game(false)
	var saved=JSON.parse_string(FileAccess.get_file_as_string(scene.save_directory.path_join("voyage.json")))
	check(saved is Dictionary and not saved.has("voyage_intent065") and not saved.has("voyageQuote065"),"Actual private save contains state only; transient preparation/quote is no authority")
	receipt={"status":"COMPLETED","movingSeconds":moving_seconds,"outwardMovingSeconds":outward_moving,"elapsedSeconds":elapsed_seconds,"payrollDays":actual_days,"expected":expected,"allowance":planned.allowance,"fuel":planned.stores.boats,"terminalSecondsBound":terminal_bound,"quoteConditions":"Initial morale100, healthy/dry, zero vx/vy, funded fixed crew/spec/speed, no new damage/encounters, explicit idle and ordinary calendar publication"}

func _initialize() -> void:
	started=Time.get_ticks_msec()
	print("long voyage065 phase: one Main/world/navigation initialization")
	scene=load("res://main.tscn").instantiate();root.add_child(scene)
	scene.set_process(false);scene.set_physics_process(false)
	await process_frame
	if not check(scene.is_node_ready() and scene.core!=null and scene.chart!=null and scene.ui!=null and scene.audio!=null and scene.music!=null,"Main is ready with Core, chart, UI, audio and music before fixture access"):
		receipt.status="INITIALIZATION_FAILED"
		await finish();return
	scene.audio.enabled=false;scene.music.enabled=false
	scene.save_directory=OS.get_user_data_dir().path_join("long-voyage065-%d"%started)
	c=scene.core
	if not check(c.new_game(65065).get("ok",false),"Actual canonical career initializes"):await finish();return
	scene.mode="campaign";scene.paused=true
	if not check(Money.move(c.port("shatter_spire"),"governmentPurse",c.state,"coins",40000,"Declared funded065 comparison capital",c.state.moneyLog),"Declared starting capital moves from an existing treasury"):await finish();return
	source_uid=str(c.state.fleet[0].uid);target_uid="boat-%d"%int(c.state.nextUid)
	var bought: Dictionary=c.buy_boat("tin_skiff")
	if not check(bought.get("ok",false),"Second owned hull/crew purchase: "+str(bought.get("message",""))):await finish();return
	var converted: Dictionary=c.FleetIdentity.install_conversion(c,source_uid,"auxiliary_tanks")
	if not check(converted.get("ok",false),"Paid auxiliary tank conversion: "+str(converted.get("message",""))):await finish();return
	var hired: Dictionary=c.FleetIdentity.hire_specialist(c,source_uid,"quartermaster")
	if not check(hired.get("ok",false),"Paid quartermaster hiring: "+str(hired.get("message",""))):await finish();return
	# Harbor.resupply reports no sale as failure even when paid stores suffice.
	# Inspect both results independently; a real shortage still fails setup.
	var store_results: Array=[]
	var stores_ok: bool=true
	for loadout in [{"uid":source_uid,"profile":"full"},{"uid":target_uid,"profile":"voyage"}]:
		var boat: Dictionary=c.find_boat(loadout.uid)
		var harbor: Dictionary=c.current_port()
		var prior_boat: Dictionary=boat.duplicate(true)
		var prior_harbor: Dictionary=harbor.duplicate(true)
		var prior_coins: int=int(c.state.coins)
		var prior_total: int=Money.total(c.state)
		var targets: Dictionary={"ammo":maxf(80.0,float(boat.spec.get("ammoCapacity",80*maxi(1,boat.spec.get("weaponMounts",[]).size())))),"fuel":3.0 if loadout.profile=="voyage" else float(boat.spec.get("fuelCapacity",60)),"supplies":6.0 if loadout.profile=="voyage" else 20.0}
		var result: Dictionary=c.resupply_boat(loadout.uid,loadout.profile)
		var ready_before: bool=true
		var ready_after: bool=true
		var conserved: bool=true
		var invoice: int=0
		for good in targets:
			var conversion: float=float(c.Goods.ROUNDS_PER_CASE) if good=="ammo" else 1.0
			var loaded: float=float(boat[good])-float(prior_boat[good])
			var used: float=float(prior_harbor.stocks[good])-float(harbor.stocks[good])
			ready_before=ready_before and float(prior_boat[good])>=float(targets[good])-0.000000001
			ready_after=ready_after and float(boat[good])>=float(targets[good])-0.000000001
			conserved=conserved and loaded>=0.0 and used>=0.0 and float(harbor.stocks[good])>=0.0 and absf(loaded-used*conversion)<0.000000001 and loaded<=maxf(0.0,float(targets[good])-float(prior_boat[good]))+0.000000001
			invoice+=ceili(used*c.Economy.price(prior_harbor,good)-0.000001)
		var paid: bool=prior_coins-int(c.state.coins)==invoice and int(harbor.cash)-int(prior_harbor.cash)==invoice and Money.total(c.state)==prior_total
		var diagnostic: Dictionary={"uid":loadout.uid,"profile":loadout.profile,"result":result,"targets":targets,"readyBefore":ready_before,"readyAfter":ready_after,"stockConserved":conserved,"invoicePaid":paid,"beforeStores":{"ammo":prior_boat.ammo,"fuel":prior_boat.fuel,"supplies":prior_boat.supplies},"afterStores":{"ammo":boat.ammo,"fuel":boat.fuel,"supplies":boat.supplies},"beforeStock":prior_harbor.stocks,"afterStock":harbor.stocks.duplicate(true),"beforeCoins":prior_coins,"afterCoins":c.state.coins,"invoice":invoice}
		store_results.append(diagnostic)
		stores_ok=check(ready_after and conserved and paid and (result.get("ok",false) or (ready_before and invoice==0)),"Working stores meet the actual profile with conserved stock and a paid invoice: "+JSON.stringify(diagnostic)) and stores_ok
	if not stores_ok:
		receipt.status="SETUP_FAILED";receipt.storeResults=store_results
		await finish();return
	c.state.morale=100.0;c.apply_morale() # Declared INITIAL fixed-speed condition.
	supply=int(c.state.coinSupply)
	check(Money.total(c.state)==supply,"Opening paid fixture conserves the original world coin supply")
	transfer_cases()
	if within_budget():quote_variants()
	var idle_fuel: Array=c.state.fleet.map(func(b):return b.fuel)
	# Genuine calendar crossing, deliberately not yet joined, proves review purity.
	c.step(c.DAY_SECONDS)
	check(c.state.fleet.map(func(b):return b.fuel)==idle_fuel,"Dry stationary pending day burns no moving fuel")
	if within_budget():pending_reviews()
	if within_budget():paid_voyage()
	await finish()

func finish() -> void:
	if scene!=null:
		scene.queue_free();await process_frame
	check(Time.get_ticks_msec()-started<55000,"Initialization, fixture body, joins and cleanup stay below55 seconds")
	if failures>0 and receipt.status=="COMPLETED":receipt.status="FAILED"
	print("long voyage065 receipt ",JSON.stringify(receipt))
	print("long voyage065: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 and receipt.status=="COMPLETED" else 1)
