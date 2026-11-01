extends SceneTree
## Focused native fixture for v0.086: Civilian Careers Worth Repeating.
## Source-only candidate authored by helper; Root alone executes queued engine runs.
## All four civilian role witnesses are EXPLICITLY LABELED STAGED (staged=true,
## earnedFromDefaultStarter=false) on independent forks of one validated baseline.
const Money=preload("res://scripts/money.gd")
const Economy=preload("res://scripts/economy.gd")
const Goods=preload("res://scripts/goods.gd")
const Harbor=preload("res://scripts/harbor.gd")
const Jobs=preload("res://scripts/voyage_jobs.gd")
const Work=preload("res://scripts/civilian_work.gd")
const Choices=preload("res://scripts/civilian_choices059.gd")
const VoyageUI=preload("res://scripts/voyage_ui.gd")
const Guidance=preload("res://scripts/campaign_guidance.gd")
const GuidanceUI=preload("res://scripts/guidance_ui.gd")
const CareerCosts=preload("res://scripts/career_costs.gd")
const Transport=preload("res://scripts/passenger_transport.gd")
const Expedition=preload("res://scripts/expedition.gd")
const Navigation=preload("res://scripts/navigation.gd")
const Support=preload("res://scripts/fleet_support.gd")
const Escort=preload("res://scripts/escort_ops.gd")
const FleetIdentity=preload("res://scripts/fleet_identity.gd")
const WorkRegion=preload("res://scripts/voyage_region070.gd")
const BUDGET_SECONDS=38.0
const FIXTURE_HULLS=["kelpnet_dory","fenhopper_lighter","gullwing_daysailer","seepoil_tanker","brinehook_longliner","tideledger_coaster","osprey_cabin_cruiser","blackwater_fleet_tanker"]
const ROLE_FITTINGS={"fishing":"cargo_rig","freight":"cargo_rig","passenger_charter":"cargo_rig","fuel_delivery":"auxiliary_tanks"}
var checks: int=0
var failures: int=0
var steps: int=0
var payroll_days: int=0
var began_us: int=0
var phase_us: int=0
var scene
var c
var supply: int=0
var census: int=0
var baseline: Dictionary={}
var baseline_cache: Dictionary={}
var baseline_encounters: Dictionary={}
var phases: Array=[]
var receipts: Array=[]
var current_receipt: Dictionary={}
var convoy_witness: Dictionary={}

func elapsed() -> float:
	return float(Time.get_ticks_usec()-began_us)/1000000.0

func phase(label: String) -> void:
	var now: int=Time.get_ticks_usec()
	phases.append({"phase":label,"seconds":float(now-phase_us)/1000000.0,"elapsed":elapsed(),"steps":steps,"payrollDays":payroll_days})
	phase_us=now

func within_budget(label: String) -> bool:
	if elapsed()<=BUDGET_SECONDS:return true
	check(false,label+" exceeded 086 fixture time budget ("+str(elapsed())+"s)")
	return false

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL civilian086: ",message)

func close(a: float,b: float) -> bool:
	return absf(a-b)<=0.02

func snapshot() -> String:
	return JSON.stringify({"state":c.state,"pendingDays":c.pending_days})

func people_breakdown(s: Dictionary) -> Dictionary:
	var ports: int=0;var fleet: int=0;var prizes: int=0;var owners: int=0
	var captives: int=0;var crisis: int=0;var charters: int=0;var rescues: int=0
	for p in s.get("ports",[]):ports+=int(p.get("workforce",0))+int(p.get("defenders",0))
	for b in s.get("fleet",[]):
		if not b.get("sunk",false):fleet+=int(b.get("crew",0))
	for b in s.get("boardingPrizes",[]):
		if not b.get("sunk",false):prizes+=int(b.get("crew",0))
	for owner in s.get("fleetOwners",[]):
		for b in owner.get("boats",[]):
			if not b.get("sunk",false):owners+=int(b.get("crew",0))
	for n in s.get("captiveBerths",{}).values():captives+=int(n)
	for job in s.get("regionalCrises",{}).get("jobs",[]):crisis+=int(job.get("passengers",{}).get("n",0))
	for job in s.get("voyageJobs",[]):
		if str(job.get("state",""))=="active":charters+=int(job.get("passengers",{}).get("n",0))
	for wreck in s.get("wrecks",[]):
		if not wreck.get("resolved",false):rescues+=int(wreck.get("survivors",0))
	var total: int=ports+fleet+prizes+owners+captives+crisis+charters+rescues
	return {"total":total,"ports":ports,"fleet":fleet,"prizes":prizes,"owners":owners,"captives":captives,"crisis":crisis,"charters":charters,"rescues":rescues}

func people(s: Dictionary) -> int:
	return int(people_breakdown(s).total)

func encounter_id(event: Dictionary) -> String:
	return "%s@%.4f:%s>%s:%s"%[str(event.get("kind","battle")),float(event.get("day",0)),str(event.get("a","")),str(event.get("b","")),str(event.get("winner",""))]

func valid_losses(event: Dictionary) -> float:
	# NavalCombat records original crew minus physical survivors for EACH side,
	# including deaths aboard surviving hulls. Keep the actual numeric values.
	var losses: float=0.0
	for key in ["crewLostA","crewLostB"]:
		if not (event.get(key) is int or event.get(key) is float):return -1.0
		var lost: float=float(event[key])
		if not is_finite(lost) or lost<0.0:return -1.0
		losses+=lost
	return losses

func record_encounter_events(r: Dictionary) -> bool:
	var events: Array=c.state.get("navalAi",{}).get("encounters",[])
	# Validate the entire observed batch before publishing detached records;
	# neither baseline history nor a rejected batch can mutate the receipt.
	var recorded: Dictionary=r.encounterRecords.duplicate(true)
	for raw in events:
		if not raw is Dictionary:return false
		var id: String=encounter_id(raw)
		if baseline_encounters.has(id):
			if raw!=baseline_encounters[id]:return false
			continue
		if valid_losses(raw)<0:return false
		if recorded.has(id) and recorded[id]!=raw:return false
		recorded[id]=raw.duplicate(true)
	r.encounterRecords=recorded
	return true

func recorded_npc_losses(r: Dictionary) -> float:
	if not record_encounter_events(r):return -999999
	var losses: float=0.0
	for raw in r.encounterRecords.values():
		var lost: float=valid_losses(raw)
		if lost<0:return -999999
		losses+=lost
	return losses

func encounter_coverage(r: Dictionary) -> bool:
	if not record_encounter_events(r):return false
	for id in r.encounterRecords:
		var raw: Dictionary=r.encounterRecords[id]
		if valid_losses(raw)>0 and not c.state.get("navalAi",{}).get("encounters",[]).any(func(item):return item is Dictionary and encounter_id(item)==id and item==raw):
			return false
	return true

func join_calendar(r: Dictionary,context: String) -> bool:
	var before_day: int=int(c.state.econDay)
	var queued: int=int(c.pending_days)+(int(scene.economy_workers.days) if scene.economy_task>=0 else 0)
	scene.sync_economy()
	var published: int=int(c.state.econDay)-before_day
	payroll_days+=published
	var joined: bool=c.pending_days==0 and scene.economy_task<0 and scene.economy_workers.group_id<0 and published==queued
	r.get_or_add("calendarPublications",[]).append({"context":context,"queuedDays":queued,"publishedDays":published,"econDay":int(c.state.econDay),"pendingDays":int(c.pending_days),"economyTask":int(scene.economy_task),"workerGroupId":int(scene.economy_workers.group_id)})
	check(joined,str(r.kind)+": copied economy worker publishes exactly the queued calendar days after join")
	if not joined:r.blocker="Calendar publication contract failed: "+context
	record_encounter_events(r)
	return joined

func button_in(node: Node,caption: String,prefix: bool=false) -> Button:
	if node is Button and ((not prefix and node.text==caption) or (prefix and node.text.begins_with(caption))):return node
	for child in node.get_children():
		var found: Button=button_in(child,caption,prefix)
		if found!=null:return found
	return null

func text_in(node: Node,needle: String) -> bool:
	if node is Label and needle in str(node.text):return true
	for child in node.get_children():
		if text_in(child,needle):return true
	return false

func _initialize() -> void:
	began_us=Time.get_ticks_usec();phase_us=began_us
	scene=load("res://main.tscn").instantiate();root.add_child(scene)
	await process_frame
	scene.set_process(false);scene.set_physics_process(false)
	scene.audio.enabled=false;scene.music.enabled=false
	scene.save_directory=OS.get_user_data_dir().path_join("civilian-careers086-%d"%began_us)
	c=scene.core
	check(c.new_game(59059).ok,"seeded Campaign on Main's existing world/navigation publishes")
	scene.mode="campaign";scene.paused=true
	if c.state.is_empty():finish();return
	supply=Money.total(c.state);census=people(c.state)
	var dock: Dictionary=c.current_port()
	# STAGED OPENING FIXTURE STOCK: ready empty shells, conversion materials and
	# shipwright eligibility at the starting yard so each staged role witness pays
	# full Harbor hull/crew/store and FleetIdentity conversion prices without minting
	# coins or people. Explicitly labeled staged=true, earnedFromDefaultStarter=false.
	for id in FIXTURE_HULLS:dock.shipStock[id]=int(dock.shipStock.get(id,0))+1
	for good in ["timber","iron","supplies","food","fuel"]:
		dock.stocks[good]=maxf(float(dock.stocks.get(good,0)),40.0)
	dock.training.qualified.shipwright=maxi(2,int(dock.training.qualified.get("shipwright",0)))
	var donor: Dictionary=c.port("shatter_spire")
	check(Money.move(donor,"governmentPurse",c.state,"coins",220000,"Declared staged 086 civilian fixture capital",c.state.moneyLog),"staged opening capital transfers from an existing counted treasury purse")
	check(Money.total(c.state)==supply and people(c.state)==census,"staged fixture setup conserves global coins and people")
	var restored: Dictionary=c.SaveValidation.validate(JSON.parse_string(JSON.stringify(c.state)),c.data)
	check(restored.ok,"staged baseline passes parsed SaveValidation: "+str(restored.get("message","")))
	if not restored.ok:finish();return
	baseline=c.state.duplicate(true);baseline_cache=c.route_cache.duplicate(true)
	for event in baseline.get("navalAi",{}).get("encounters",[]):baseline_encounters[encounter_id(event)]=event.duplicate(true)
	phase("validated staged baseline")
	if within_budget("fishing"):fishing_cycle()
	phase("fishing buyer ranking, horizon/ground choices and paid conversion reinvestment")
	if failures>0 or receipts.size()!=1:finish();return
	if within_budget("freight"):job_cycle(Jobs.KIND_FREIGHT,"fenhopper_lighter")
	phase("freight load/route alternatives, delivery and paid conversion reinvestment")
	if failures>0 or receipts.size()!=2:finish();return
	if within_budget("charter"):job_cycle(Jobs.KIND_CHARTER,"osprey_cabin_cruiser")
	phase("passenger charter cohort/custody alternatives, delivery and paid conversion reinvestment")
	if failures>0 or receipts.size()!=3:finish();return
	if within_budget("fuel"):job_cycle(Jobs.KIND_FUEL,"seepoil_tanker")
	phase("fuel delivery tier/recipient arrival, delivery and paid tank conversion reinvestment")
	if failures>0 or receipts.size()!=4:finish();return
	if within_budget("convoy"):witnessed_convoy_checks()
	phase("witnessed civilian convoy piracy intercept and escort opportunity")
	finish()

func begin_branch(kind: String,hull_id: String) -> Dictionary:
	scene.sync_economy()
	current_receipt={"kind":kind,"hull":hull_id,"staged":true,"earnedFromDefaultStarter":false,"status":"STARTED","operatingNet":0,"reinvestment":{"ok":false}}
	c.state=baseline.duplicate(true);c.route_cache=baseline_cache.duplicate(true)
	c.pending_days=0;c.events=[];c.exploration_timer=0.0;c.sailing_clearance=0.0
	var dock: Dictionary=c.current_port()
	var acquisition_open: int=int(c.state.coins)
	var ready: Dictionary=Harbor.quote(c,c.hull(hull_id),dock)
	var advance_quote: int=Economy.recruit_cost(dock,int(c.hull(hull_id).crewMin))
	var born_uid: String="boat-%d"%int(c.state.nextUid)
	var bought: Dictionary=c.buy_boat(hull_id)
	check(bought.ok,kind+": staged paid hull + minimum trained crew purchase succeeds: "+str(bought.get("message","")))
	if not bought.ok:return {}
	var boat: Dictionary=c.find_boat(born_uid)
	var acquisition_spent: int=acquisition_open-int(c.state.coins)
	check(not boat.is_empty() and acquisition_spent==int(ready.readyPrice)+advance_quote,kind+": paid acquisition debits exact ready hull price plus crew advance")
	var food_to_sell: int=maxi(0,floori(float(c.state.cargo.food))-3)
	if food_to_sell>0:check(c.trade(str(dock.id),"food",food_to_sell,"sell").ok,kind+": surplus inherited rations sold through finite harbor market")
	var sale_open: int=int(c.state.coins)
	check(c.sell_boat("boat-1").ok,kind+": starter skiff sold through ordinary harbor API")
	var capital_recovered: int=int(c.state.coins)-sale_open
	var stores_open: int=int(c.state.coins)
	check(c.resupply_boat(born_uid,"voyage").ok,kind+": paid working stores loaded")
	var stores_paid: int=stores_open-int(c.state.coins)
	check(Money.total(c.state)==supply and people(c.state)==census,kind+": staged branch start conserves global coins and people")
	var prices: Dictionary={}
	for good in ["food","fuel","supplies","ammo"]:prices[good]=Economy.price(dock,good,"buy")
	current_receipt={"kind":kind,"staged":true,"earnedFromDefaultStarter":false,
		"stagingBasis":"Declared finite treasury transfer (220000 coins from shatter_spire) and ready yard shell on forked baseline; full ready price, crew advance, working stores and post-voyage conversion paid through ordinary APIs.",
		"boatUid":born_uid,"hull":hull_id,"origin":str(dock.id),"status":"STARTED",
		"hullCapitalPaid":int(ready.readyPrice),"crewAdvancePaid":advance_quote,"inheritedHullCapitalRecovered":capital_recovered,"openingStoresPaid":stores_paid,
		"openingCoins":int(c.state.coins),"openingArrears":int(c.state.wageArrears),"openingDay":float(c.state.day),"openingEconDay":int(c.state.econDay),
		"physicalItemUids":boat.moduleCondition.items.keys(),"crew":int(boat.crew),"dailyWages":int(Economy.daily_upkeep(c.state.fleet).wages),"specialistPremiumPerDay":Support.premium(c.state),
		"openingFuel":float(boat.fuel),"openingFood":float(c.state.cargo.food),"openingKits":float(boat.supplies),"openingAmmo":float(boat.ammo),
		"prices":prices,"grossIncome":0,"passengerSavingsCustody":0,"sailingDistance":0.0,"sailingDays":0.0,"returnDays":0.0,"steps":0,"encounterRecords":{},"operatingNet":0,"reinvestment":{"ok":false},"calendarPublications":[]}
	return current_receipt

func advance(seconds: float,r: Dictionary) -> bool:
	if seconds<=0:return true
	if not within_budget(str(r.kind)+" clock"):return false
	var before: Dictionary=c.state.position.duplicate()
	var before_day: float=float(c.state.day)
	check(seconds<=c.DAY_SECONDS,str(r.kind)+": public clock interval never exceeds one day")
	if seconds>c.DAY_SECONDS:return false
	c.step(seconds);steps+=1;r.steps=int(r.steps)+1
	r.sailingDistance=float(r.sailingDistance)+c.distance(before,c.state.position)
	if c.pending_days>0 and not join_calendar(r,"ordinary calendar publication"):return false
	if c.events.any(func(event):return str(event.get("kind","")) in ["encounter","ocean_encounter066","defeat"]):
		r.status="BLOCKED_ENCOUNTER";r.blocker="Hostile encounter interrupted route."
		return false
	if float(c.state.day)<=before_day:
		check(false,str(r.kind)+": public clock must publish positive elapsed time")
		r.blocker="Clock refused progression";r.clockContext={"requestedSeconds":seconds,"day":before_day,"events":c.events.duplicate(true),"recentLog":c.state.get("log",[]).slice(-6)}
		return false
	return true

func sail(r: Dictionary,target: Dictionary,destination: String="",returning: bool=false) -> bool:
	var route: Dictionary=c.chart_course(target,destination)
	check(route.ok,str(r.kind)+": chart_course accepted: "+str(route.get("message","")))
	if not route.ok:r.status="BLOCKED_ROUTE";r.blocker=route.get("message","");return false
	var departure: float=float(c.state.day)
	for _i in range(120):
		if c.state.path.is_empty():break
		if not advance(1.0,r):return false
	var duration: float=float(c.state.day)-departure
	r.sailingDays=float(r.sailingDays)+duration
	if returning:r.returnDays=float(r.returnDays)+duration
	var arrived: bool=c.state.path.is_empty() and (destination.is_empty() or str(c.current_port().get("id",""))==destination)
	check(arrived,str(r.kind)+": bounded physical sailing reaches destination")
	return arrived

func settle_calendar(r: Dictionary) -> bool:
	if int(c.state.econDay)==int(r.openingEconDay):
		# From an exact day boundary the epsilon must be a SECOND bounded step;
		# Campaign.step explicitly refuses a single interval over DAY_SECONDS.
		var target_day: float=float(floori(float(c.state.day))+1)+0.001/c.DAY_SECONDS
		while float(c.state.day)<target_day:
			if not advance(minf(c.DAY_SECONDS,maxf(0.001,(target_day-float(c.state.day))*c.DAY_SECONDS)),r):return false
	if not join_calendar(r,"final calendar publication"):return false
	var joined: bool=c.pending_days==0 and scene.economy_task<0 and scene.economy_workers.group_id<0 and int(c.state.econDay)>int(r.openingEconDay)
	check(joined,str(r.kind)+": ordinary economy/payroll joined")
	return joined

func execute_paid_reinvestment(r: Dictionary) -> bool:
	r.reinvestment={"ok":false,"requestedConversion":str(ROLE_FITTINGS.get(str(r.kind),"cargo_rig"))}
	var uid: String=str(r.boatUid)
	var conv_id: String=str(ROLE_FITTINGS.get(str(r.kind),"cargo_rig"))
	var boat: Dictionary=c.find_boat(uid)
	var dock: Dictionary=c.current_port()
	var hold_before: float=float(boat.spec.get("cargo",0))
	var tank_before: float=float(boat.spec.get("fuelCapacity",60))
	var reinv_quote: Dictionary=Choices.reinvestment086(c,str(r.kind),uid,maxi(0,int(r.get("operatingNet",0))))
	var fit_quote: Dictionary=reinv_quote.get("nextFitting",{})
	var hull_quote: Dictionary=reinv_quote.get("nextHull",{})
	check(not fit_quote.is_empty() and int(fit_quote.get("costCoins",0))>0 and not hull_quote.is_empty() and int(hull_quote.get("readyCoins",0))>0,str(r.kind)+": Choices.reinvestment086 quotes both paid interior fitting and next role hull")
	if not bool(fit_quote.get("ready",false)) or int(fit_quote.get("costCoins",0))<=0:
		r.blocker="Conversion quote refused";r.reinvestment.quote=reinv_quote;check(false,str(r.kind)+": paid conversion requires an available real yard quote");return false
	var coins_before: int=int(c.state.coins)
	var res: Dictionary=FleetIdentity.install_conversion(c,uid,conv_id)
	check(res.ok,str(r.kind)+": paid post-voyage conversion reinvestment succeeds: "+str(res.get("message","")))
	if not bool(res.get("ok",false)):
		r.blocker=str(res.get("message","Conversion installer refused"));r.reinvestment.result=res;return false
	var spent: int=coins_before-int(c.state.coins)
	check(spent==int(fit_quote.get("costCoins",0)) and spent>0,str(r.kind)+": paid conversion debits exact quoted materials + shipwright labor + yard margin/tax")
	boat=c.find_boat(uid)
	if conv_id=="cargo_rig":
		check(float(boat.spec.get("cargo",0))>hold_before,str(r.kind)+": cargo_rig reinvestment increases physical hull hold capacity")
	elif conv_id=="auxiliary_tanks":
		check(float(boat.spec.get("fuelCapacity",60))>tank_before,str(r.kind)+": auxiliary_tanks reinvestment increases physical engine tank capacity")
	r.reinvestment={"conversionInstalled":str(boat.get("conversion","")),"requestedConversion":conv_id,"ok":bool(res.ok) and spent==int(fit_quote.get("costCoins",0)) and spent>0 and str(boat.get("conversion",""))==conv_id,"conversionCostPaid":spent,"holdBefore":hold_before,"holdAfter":float(boat.spec.get("cargo",0)),
		"tankBefore":tank_before,"tankAfter":float(boat.spec.get("fuelCapacity",60)),"nextHullQuote":hull_quote,"dock":str(dock.get("id",""))}
	return bool(r.reinvestment.ok)

func finish_receipt(r: Dictionary,paid: bool) -> void:
	if paid:
		if not settle_calendar(r):paid=false
	else:
		join_calendar(r,"blocked branch joins only already queued work")
	var boat: Dictionary=c.find_boat(str(r.boatUid))
	if boat.is_empty():
		check(false,str(r.kind)+": working boat survives receipt")
		r.status="BLOCKED_WORKING_BOAT";r.blocker="Original working UID is no longer afloat"
		export_role_state(r);receipts.append(r.duplicate(true));current_receipt={};return
	var fuel_used: float=maxf(0,float(r.openingFuel)-float(boat.fuel))
	var food_used: float=maxf(0,float(r.openingFood)-float(c.state.cargo.food))
	var kits_used: float=maxf(0,float(r.openingKits)-float(boat.supplies))
	var ammo_used: float=maxf(0,float(r.openingAmmo)-float(boat.ammo))/Goods.ROUNDS_PER_CASE
	var dock: Dictionary=c.current_port()
	var prices: Dictionary=r.prices.duplicate(true)
	if not dock.is_empty():
		for good in prices:prices[good]=maxi(int(prices[good]),Economy.price(dock,good,"buy"))
	var store_value: int=ceili(fuel_used*int(prices.fuel))+ceili(food_used*int(prices.food))+ceili(kits_used*int(prices.supplies))+ceili(ammo_used*int(prices.ammo))
	var operating_cash: int=int(r.openingCoins)+int(r.grossIncome)-int(c.state.coins)
	var days: int=int(c.state.econDay)-int(r.openingEconDay)
	var wages: int=days*(int(r.dailyWages)+int(r.specialistPremiumPerDay))
	check(operating_cash==wages and int(r.dailyWages)==int(r.crew)*Goods.SAILOR_WAGE,str(r.kind)+": exact calendar payroll equals captain's operating cash debit at 100 coins per sailor-day")
	r.payrollDays=days;r.wagesAndPremiums=wages;r.actualOperatingCashPaid=operating_cash
	r.consumedStoresReplacementCoins=store_value
	r.operatingNet=int(r.grossIncome)-operating_cash-store_value
	r.returnIncluded=float(r.returnDays)>0
	if paid:
		var invested: bool=execute_paid_reinvestment(r)
		check(invested and bool(r.get("reinvestment",{}).get("ok",false)),str(r.kind)+": installer returns a complete successful native reinvestment receipt")
		r.status="STAGED_PAID_REINVESTED" if int(r.operatingNet)>0 and invested and bool(r.get("reinvestment",{}).get("ok",false)) else "BLOCKED_REINVESTMENT"
		check(float(r.sailingDistance)>0 and r.returnIncluded and int(r.operatingNet)>0,str(r.kind)+": staged witness completes outward+return work with positive net before paid reinvestment")
	else:
		r.status="BLOCKED"
		check(false,str(r.kind)+": staged role witness failed to complete paid work: "+str(r.get("blocker","")))
	r.closingCoins=int(c.state.coins);r.closingDay=float(c.state.day)
	r.conservation={"coinsTotal":Money.total(c.state),"supply":supply,"people":people(c.state),"census":census,"recordedNpcDeaths":recorded_npc_losses(r)}
	check(Money.total(c.state)==supply and int(c.state.coinSupply)==supply and encounter_coverage(r) and people(c.state)+recorded_npc_losses(r)==census,str(r.kind)+": exact coin and people conservation after paid reinvestment")
	check(int(c.state.wageArrears)==int(r.openingArrears) and c.cargo_weight()<=c.capacity()+0.0001 and boat.moduleCondition.items.keys()==r.physicalItemUids,str(r.kind)+": no wage arrears, overload or lost module UIDs")
	var parsed: Dictionary=export_role_state(r)
	var coin_now: int=int(c.state.coins)
	var conv_now: String=str(boat.get("conversion",""))
	var restored: Dictionary=c.restore(parsed)
	var after: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	var saved_boat: Dictionary={}
	for b in parsed.fleet:
		if str(b.uid)==str(r.boatUid):saved_boat=b;break
	var actual_boat: Dictionary={}
	for b in after.fleet:
		if str(b.uid)==str(r.boatUid):actual_boat=b;break
	var kept: bool=not saved_boat.is_empty() and not actual_boat.is_empty() and conv_now==str(r.get("reinvestment",{}).get("conversionInstalled",""))
	for key in ["coins","coinSupply","crewPurse","wageArrears","cargo","voyageJobs","civilianWork","nextUid"]:
		kept=kept and after.get(key)==parsed.get(key)
	for key in ["uid","conversion","moduleCondition","loadout","crew","fuel","supplies","ammo"]:
		kept=kept and actual_boat.get(key)==saved_boat.get(key)
	check(restored.ok and int(c.state.coins)==coin_now and str(c.find_boat(str(r.boatUid)).get("conversion",""))==conv_now and kept,str(r.kind)+": disk restore preserves exact money, catch/quota/jobs, conversion, item custody/condition and original working UID")
	receipts.append(r.duplicate(true))
	current_receipt={}

func export_role_state(r: Dictionary) -> Dictionary:
	scene.sync_economy()
	check(c.pending_days==0 and scene.economy_task<0 and scene.economy_workers.group_id<0,str(r.kind)+": actual role state exports only after copied economy workers join")
	var parsed: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	var boat: Dictionary=c.find_boat(str(r.get("boatUid","")))
	var folder: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	var save_name: String="civilian086-%s-%s.json"%[str(r.kind),"completed" if str(r.status)=="STAGED_PAID_REINVESTED" else "blocked"]
	check(not folder.is_empty(),str(r.kind)+": Root supplies the required GAME_TEST_ARTIFACTS directory")
	if not folder.is_empty():
		var saved=FileAccess.open(folder.path_join(save_name),FileAccess.WRITE)
		check(saved!=null,str(r.kind)+": actual career state opens for export")
		if saved!=null:saved.store_string(JSON.stringify(c.state,"\t"));saved.close()
		var disk=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(save_name)))
		check(disk is Dictionary and disk==parsed,str(r.kind)+": exported career save is the entire actual completed or explicitly blocked state")
		if disk is Dictionary:
			parsed=disk
			r.completedSave={"file":save_name,"sha256":FileAccess.get_sha256(folder.path_join(save_name)),"staged":true,"earnedFromDefaultStarter":false,"day":float(c.state.day),"coins":int(c.state.coins),"boatUid":str(r.get("boatUid","")),"conversion":str(boat.get("conversion","")),"status":str(r.status)}
	return parsed

func fishing_buyer_ranking_checks(uid: String) -> void:
	var saved_state: Dictionary=c.state.duplicate(true)
	var saved_cache: Dictionary=c.route_cache.duplicate(true)
	var saved_pending: int=c.pending_days
	var home_id: String=str(c.state.lastPort)
	var second_port: Dictionary={}
	for p in c.state.ports:
		if str(p.id)!=home_id and str(p.get("regionId","shatter_coast"))=="shatter_coast":
			var leg: Dictionary=Choices._leg(c,c.state.position,p)
			if bool(leg.ok):second_port=p;break
	check(not second_port.is_empty(),"fishing buyer ranking test finds a second reachable Shatter Coast harbor")
	if not second_port.is_empty():
		var obs: Dictionary=c.state.get("tradeIntel",{}).get("observations",{})
		obs[home_id]={"day":float(c.state.day),"cash":0,"businessFunds":0,"sell":{"preserved_fish":60},"buy":{"food":34,"fuel":44},"stocks":{"preserved_fish":5.0,"food":20.0,"fuel":20.0},"seen":true}
		obs[str(second_port.id)]={"day":float(c.state.day),"cash":900,"businessFunds":900,"sell":{"preserved_fish":68},"buy":{"food":34,"fuel":44},"stocks":{"preserved_fish":1.0,"food":20.0,"fuel":20.0},"seen":true}
		# Inject a non-home port at the EXACT current XY coordinates to prove home-region authority.
		c.state.ports.append({"id":"outer_fake_harbor","name":"Outer Fake Harbor","regionId":"outer_reach","x":float(c.state.position.x),"y":float(c.state.position.y),"faction":"free_harbors","cash":5000,"governmentPurse":5000,"stocks":{"preserved_fish":0.0,"food":20.0,"fuel":20.0}})
		obs["outer_fake_harbor"]={"day":float(c.state.day),"cash":5000,"businessFunds":5000,"sell":{"preserved_fish":95},"buy":{"food":30,"fuel":40},"stocks":{"preserved_fish":0.0},"seen":true}
		c.state.tradeIntel["observations"]=obs
		var before_snap: String=snapshot()
		var auto_rev: Dictionary=Choices.fishing_review(c,uid,1.0,3,"")
		check(snapshot()==before_snap,"default fishing_review with buyer ranking is 100% pure")
		check(str(auto_rev.buyer.portId)==str(second_port.id),"default fishing_review skips illiquid closer port and non-home equal-XY port to pick reachable liquid Shatter Coast buyer ranked by net")
		check(not Choices.buyer_ports(c).any(func(row):return str(row.id)=="outer_fake_harbor"),"buyer_ports excludes non-home region ports")
		var explicit_non_home: Dictionary=Choices.fishing_review(c,uid,1.0,3,"outer_fake_harbor")
		check(not bool(explicit_non_home.routeOk),"explicit non-home buyer is refused by home-region route authority")
		var explicit_illiquid: Dictionary=Choices.fishing_review(c,uid,1.0,3,home_id)
		check(str(explicit_illiquid.buyer.portId)==home_id and int(explicit_illiquid.buyer.saleLots)==0 and explicit_illiquid.warnings.any(func(w):return "covers only 0" in str(w)),"explicitly selected illiquid buyer is preserved along with its purse warning")
		check(auto_rev.get("horizonAlternatives",[]).size()==3 and not str(auto_rev.get("groundAlternativeNote","")).is_empty() and not auto_rev.get("reinvestment",{}).is_empty(),"fishing_review exposes horizonAlternatives, groundAlternativeNote and reinvestment quote")
	c.state=saved_state;c.route_cache=saved_cache;c.pending_days=saved_pending

func fishing_cycle() -> void:
	var r: Dictionary=begin_branch("fishing","kelpnet_dory")
	if r.is_empty():return
	var uid: String=str(r.boatUid)
	var home: Dictionary=c.current_port();var point: Dictionary={}
	for delta in [Vector2(220,0),Vector2(-220,0),Vector2(0,220),Vector2(0,-220)]:
		var candidate: Dictionary={"x":float(home.x)+delta.x,"y":float(home.y)+delta.y}
		if Navigation.is_water(c.nav,candidate.x,candidate.y,maxf(10,float(c.find_boat(uid).spec.size))):point=candidate;break
	if point.is_empty() or not sail(r,point):r.blocker="No safe fishing ground";finish_receipt(r,false);return
	fishing_buyer_ranking_checks(uid)
	var before_ui: String=snapshot()
	var cache_before: Dictionary=c.route_cache.duplicate(true)
	var g_rep: Dictionary=Guidance.report(c,0.0,"fisher")
	check(g_rep.ok and snapshot()==before_ui and c.route_cache==cache_before and not str(g_rep.careerPlan.get("alternativesSummary","")).is_empty() and not str(g_rep.careerPlan.get("reinvestmentSummary","")).is_empty(),"Guidance.report for fisher is pure and surfaces alternatives + reinvestment")
	VoyageUI.review_fishing(scene.ui,uid,1.0,3,"")
	check(scene.ui.modal_open and snapshot()==before_ui,"VoyageUI.review_fishing opens purely with default ranked buyer")
	var close_btn: Button=button_in(scene.ui.overlay,"Close review · return to chart")
	if close_btn!=null:close_btn.pressed.emit()
	var quote: Dictionary=Work.fishing_quote(c,uid,1.0,3)
	var before_fish: float=float(c.state.cargo.preserved_fish)
	check(c.start_fishing(uid,1.0,3).ok,"start_fishing succeeds on open water")
	for _i in range(4):
		if not advance(c.DAY_SECONDS*0.25,r):break
	var catch_amount: float=float(c.state.cargo.preserved_fish)-before_fish
	check(catch_amount>0 and catch_amount<=float(quote.catchMax)+0.0001,"elapsed fishing time produces bounded finite catch")
	if not Work.fishing_status(c).is_empty():c.cancel_fishing(uid)
	var rev_return: Dictionary=Choices.fishing_review(c,uid,1.0,3,"")
	var chosen_buyer_id: String=str(rev_return.buyer.get("portId",r.origin))
	if chosen_buyer_id.is_empty():chosen_buyer_id=str(r.origin)
	if not sail(r,c.port_position(chosen_buyer_id),chosen_buyer_id,true):r.blocker="Fishing return failed";finish_receipt(r,false);return
	var buyer: Dictionary=c.current_port()
	var wallet: int=int(c.state.coins);var lots: int=floori(catch_amount)
	var buyer_cash: int=int(buyer.cash)
	var sale_due: int=lots*Economy.price(buyer,"preserved_fish","sell")
	var sold: Dictionary=c.trade(str(buyer.id),"preserved_fish",lots,"sell")
	r.grossIncome=int(c.state.coins)-wallet;r.catchLots=catch_amount;r.soldLots=lots;r.selectedBuyer=str(buyer.id)
	check(sold.ok and int(r.grossIncome)==sale_due and sale_due>0 and buyer_cash-int(buyer.cash)==sale_due,"fishing catch transfers the exact quoted whole-lot sale from the finite buyer purse")
	finish_receipt(r,bool(sold.ok))

func observe_fuel(r: Dictionary,uid: String) -> Dictionary:
	var previous: Dictionary={}
	for patrol in c.state.patrols:
		var owner: Dictionary=c.fleet_owner(str(patrol.id))
		if not owner.is_empty() and not str(owner.id).begins_with("story-"):
			previous[str(owner.id)]={"x":float(patrol.x),"y":float(patrol.y),"atPort":str(owner.atPort),"active":bool(patrol.active),"holding":bool(patrol.get("holding",false)),"service":c.NavalLifecycle.harbor_service(c,owner,patrol)}
	var arrivals: Dictionary={}
	for index in range(25):
		var current: Dictionary={}
		for patrol in c.state.patrols:
			var owner: Dictionary=c.fleet_owner(str(patrol.id))
			if not owner.is_empty() and not str(owner.id).begins_with("story-"):
				current[str(owner.id)]={"x":float(patrol.x),"y":float(patrol.y),"atPort":str(owner.atPort),"active":bool(patrol.active),"holding":bool(patrol.get("holding",false)),"service":c.NavalLifecycle.harbor_service(c,owner,patrol)}
		for id in current:
			if not previous.has(id):continue
			var old: Dictionary=previous[id];var now: Dictionary=current[id]
			if old.active and not old.holding and str(old.atPort).is_empty() and not now.service.is_empty() and c.distance(old,now)>0:
				arrivals[id]=now.duplicate(true)
		var offers: Array=Jobs.available(c)
		for job in offers:
			if str(job.kind)!=Jobs.KIND_FUEL or str(job.get("loadTier",""))!="small" or not arrivals.has(str(job.ownerId)):continue
			var owner: Dictionary=c.fleet_owner(str(job.ownerId))
			var service: Dictionary=c.NavalLifecycle.harbor_service(c,owner)
			if service.is_empty() or str(owner.get("purpose","")) in ["withdraw","repair","replace"]:continue
			var review: Dictionary=Choices.job_review(c,job,uid)
			var leg: float=ceilf(float(review.budget.outwardDays)*c.DAY_SECONDS)/c.DAY_SECONDS
			if bool(review.carrierFits) and bool(review.allowanceFits) and bool(review.routeOk) and float(review.budget.outwardDays)>0 and bool(review.recipient.present) and bool(review.recipient.eligible) and leg<float(service.remainingDays) and Jobs.fuel_demand(owner,true)-Jobs._fuel_promised(c,str(owner.id))>=9.0 and minf(float(review.holdFree),float(review.fleetHoldFree))>=9.0:
				r.fuelServiceAtQuote=service.duplicate(true)
				return job.duplicate(true)
		if index==24:break
		previous=current
		if not advance(c.DAY_SECONDS*0.05,r):break
	return {}

func verify_fuel_tier_alternatives(r: Dictionary,uid: String,observed: Dictionary) -> Dictionary:
	var dock: Dictionary=c.current_port()
	var owner_id: String=str(observed.ownerId)
	var owner: Dictionary=c.fleet_owner(owner_id)
	var route: Dictionary=WorkRegion.route(c,c.port(str(observed.targetPort)),dock)
	if not bool(route.get("ok",false)):r.blocker="No actual recipient route for fuel tier quote";check(false,str(r.blocker));return {}
	# Stage only a FINITE sponsor budget, through a counted purse transfer. Keep
	# the actual paid hull/lockers, owner tanks, cargo and independent arrival.
	var quote: Dictionary=Jobs._funded_load(c,dock,float(route.referenceDays),Jobs.KIND_FUEL,12,"fuel")
	if quote.is_empty() or int(quote.get("qty",0))<9:r.blocker="Actual sponsor cannot fund 9..12 drums";check(false,str(r.blocker));return {}
	var budget: int=int(quote.reward)+int(quote.invoice)
	var opening_treasury: int=int(dock.governmentPurse)
	var opening_households: int=int(dock.householdPurse)
	var intact: PackedByteArray=var_to_bytes([owner,c.state.fleet,c.state.cargo,dock.stocks])
	var moved: bool=Money.move(dock,"governmentPurse",dock,"householdPurse",opening_treasury-budget,"Declared staged 086 fuel sponsor budget; existing household purse retains surplus",c.state.moneyLog)
	r.fuelTierFunding={"staged":true,"basis":"Actual source treasury retains the native 12-drum invoice plus catalog fee; its surplus transfers to the same harbor's existing household purse. No tank, cargo, hold, boat or price edits.","portId":str(dock.id),"ownerId":owner_id,"governmentBefore":opening_treasury,"governmentAfter":int(dock.governmentPurse),"householdsBefore":opening_households,"householdsAfter":int(dock.householdPurse),"transferredCoins":opening_treasury-budget,"nativeQuote":quote.duplicate(true),"realDemand":Jobs.fuel_demand(owner,true)-Jobs._fuel_promised(c,owner_id),"realCarrierFree":Jobs._carrier_free(c,c.find_boat(uid))}
	check(moved and Money.total(c.state)==supply and intact==var_to_bytes([owner,c.state.fleet,c.state.cargo,dock.stocks]),"fuel tier staging transfers only existing coins and preserves actual recipient tanks, cargo, paid hull and source stock")
	if not moved:return {}
	var tier_offers: Array=Jobs.available(c)
	var fuel_alts: Array=Choices.role_alternatives086(c,Jobs.KIND_FUEL,tier_offers,uid).filter(func(a):return str(a.ownerId)==owner_id)
	r.fuelTierAlternatives=fuel_alts.duplicate(true)
	var both: bool=fuel_alts.any(func(a):return str(a.loadTier)=="small" and float(a.loadWeight)<=8.0) and fuel_alts.any(func(a):return str(a.loadTier)=="larger" and float(a.loadWeight)>=9.0 and float(a.loadWeight)<=15.0)
	check(both,"fuel_delivery generates both small (<=8) and larger (9..15) drum tiers when recipient demand and hold exceed 8")
	if not both:r.blocker="Actual finitely funded board lacks paired fuel tiers";return {}
	for job in tier_offers:
		if str(job.kind)==Jobs.KIND_FUEL and str(job.ownerId)==owner_id and str(job.loadTier)=="small":return job.duplicate(true)
	return {}

func job_cycle(kind: String,hull_id: String) -> void:
	var r: Dictionary=begin_branch(kind,hull_id)
	if r.is_empty():return
	var uid: String=str(r.boatUid)
	var offers: Array=Jobs.available(c)
	var alts: Array=Choices.role_alternatives086(c,kind,offers,uid)
	r.boardContext={"portId":str(c.current_port().id),"governmentPurse":int(c.current_port().governmentPurse),"stocks":c.current_port().stocks.duplicate(true),"availableWorkers":int(c.current_port().get("availableWorkers",0)),"boatUid":uid,"realHoldFree":Jobs._carrier_free(c,c.find_boat(uid)),"realSpareBerths":Transport.spare(c,c.find_boat(uid)),"alternatives":alts.duplicate(true)}
	var chosen: Dictionary={}
	if kind==Jobs.KIND_FREIGHT:
		var both: bool=alts.size()>=2 and alts.any(func(a):return str(a.loadTier)=="small") and alts.any(func(a):return str(a.loadTier)=="larger")
		check(both,"freight board exposes both small and larger load/route alternatives")
		if not both:r.blocker="Actual freight board lacks paired load tiers";return
		# Fresh day-one harbors have no regional finished goods yet. Select a real
		# funded, fitting bulk OR regional offer instead of requiring absent stock.
		for job in offers:
			if str(job.kind)!=kind or str(job.get("loadTier",""))!="small":continue
			var review: Dictionary=Choices.job_review(c,job,uid)
			if bool(review.carrierFits) and bool(review.allowanceFits) and bool(review.routeOk) and int(review.estimatedNet)>0:chosen=job.duplicate(true);break
	elif kind==Jobs.KIND_CHARTER:
		var both: bool=alts.size()>=2 and alts.any(func(a):return str(a.loadTier)=="small" and int(a.passengers)<=4) and alts.any(func(a):return str(a.loadTier)=="larger" and int(a.passengers)>4)
		check(both,"charter board exposes both small (<=4) and larger cohort alternatives")
		if not both:r.blocker="Actual charter board lacks paired cohorts on the paid yacht";return
		for job in offers:
			if str(job.kind)==kind and int(job.passengers.n)<=Transport.spare(c,c.find_boat(uid)):chosen=job.duplicate(true);break
	elif kind==Jobs.KIND_FUEL:
		chosen=observe_fuel(r,uid);offers=Jobs.available(c)
		alts=Choices.role_alternatives086(c,kind,offers,uid)
		check(not alts.is_empty(),"fuel board exposes live recipient restock alternatives")
		if not chosen.is_empty():chosen=verify_fuel_tier_alternatives(r,uid,chosen)
		if failures>0:return
	if chosen.is_empty():
		r.blocker="No eligible funded "+kind+" offer found";finish_receipt(r,false);return
	var before_ui: String=snapshot()
	var rev: Dictionary=Choices.job_review(c,chosen,uid)
	check(rev.ok and rev.carrierFits and not rev.get("reinvestment",{}).is_empty() and not rev.get("carrierAlternatives",[]).is_empty() and snapshot()==before_ui,kind+": Choices.job_review is pure and includes carrierAlternatives + reinvestment")
	VoyageUI.review_job(scene.ui,chosen,uid)
	check(scene.ui.modal_open and snapshot()==before_ui,kind+": VoyageUI.review_job opens purely with reinvestment summary")
	var decline: Button=button_in(scene.ui.overlay,"Decline",true)
	if decline!=null:decline.pressed.emit()
	var id: String=str(chosen.id)
	r.offer=chosen.duplicate(true);r.alternativesCount=alts.size()
	var accepted: Dictionary=c.accept_voyage_job(id,uid)
	check(accepted.ok,kind+": accept_voyage_job succeeds: "+str(accepted.get("message","")))
	if not accepted.ok:r.blocker=str(accepted.get("message",""));finish_receipt(r,false);return
	var active: Dictionary=Jobs._find(c.state,id)
	r.passengerSavingsCustody=int(active.get("savingsHousehold",0))+int(active.get("savingsExpert",0))
	var destination: String=str(chosen.targetPort)
	if not sail(r,c.port_position(destination),destination):r.blocker="Outward route interrupted";finish_receipt(r,false);return
	var wallet: int=int(c.state.coins)
	var settled: Dictionary=c.settle_voyage_job(id)
	check(settled.ok,kind+": settle_voyage_job succeeds at destination: "+str(settled.get("message","")))
	if settled.ok:
		r.grossIncome=int(c.state.coins)-wallet
		check(int(r.grossIncome)==int(chosen.reward),kind+": captain receives exact contracted fee excluding any custody savings")
	if not sail(r,c.port_position(str(r.origin)),str(r.origin),true):r.blocker="Return route interrupted";finish_receipt(r,false);return
	finish_receipt(r,bool(settled.ok))

func witnessed_convoy_checks() -> void:
	scene.sync_economy()
	c.state=baseline.duplicate(true);c.route_cache=baseline_cache.duplicate(true)
	c.pending_days=0;c.events=[]
	var trader: Dictionary={};var raider: Dictionary={}
	for owner in c.state.fleetOwners:
		var location: Dictionary=c.NavalAI.NavalOrders.canonical_location068(c.state,str(owner.id))
		if location.is_empty() or not Expedition.home_local064(location):continue
		if bool(owner.get("active",false)) and str(owner.get("kind",""))=="trader" and float(owner.get("tradeCargo",0))>0 and not c.Politics.hostile(c,owner) and bool(Escort._load_plan(c,owner).ok):trader=owner;break
	if not trader.is_empty():
		for owner in c.state.fleetOwners:
			var location: Dictionary=c.NavalAI.NavalOrders.canonical_location068(c.state,str(owner.id))
			if location.is_empty() or not Expedition.home_local064(location):continue
			if bool(owner.get("active",false)) and str(owner.get("kind",""))=="raider" and c.Factions.relation(c.state,str(trader.faction),str(owner.faction))<=-20 and owner.get("boats",[]).any(func(b):return not b.get("sunk",false) and float(b.get("ammo",0))>0 and int(b.get("crew",0))>=int(b.get("crewMin",1))):raider=owner;break
	check(not trader.is_empty() and not raider.is_empty(),"witnessed convoy test locates existing active trader and raider owners")
	if trader.is_empty() or raider.is_empty():return
	# Declared positions only. The loaded trader, its cargo, armed raider, purses
	# and existing hostile relationship are reused without adding any goods/boats.
	var home: Dictionary=c.current_port()
	var open_pt: Dictionary={"x":float(home.x)+180.0,"y":float(home.y)}
	for delta in [Vector2(180,0),Vector2(-180,0),Vector2(0,180),Vector2(0,-180)]:
		var cand: Dictionary={"x":float(home.x)+delta.x,"y":float(home.y)+delta.y}
		if Navigation.is_water(c.nav,cand.x,cand.y,16.0):open_pt=cand;break
	c.state.position=open_pt.duplicate()
	trader.atPort="";raider.atPort=""
	for p in c.state.patrols:
		if str(p.id)==str(trader.id):
			p.active=true;p.holding=false;p.x=open_pt.x+80.0;p.y=open_pt.y;p.to="brass_haven"
		elif str(p.id)==str(raider.id):
			p.active=true;p.holding=false;p.x=open_pt.x+240.0;p.y=open_pt.y
	var before_snap: String=snapshot()
	var cache_before: Dictionary=c.route_cache.duplicate(true)
	var witnessed: Array=Choices.witnessed_convoy_opportunities086(c)
	var escort_rep: Dictionary=Guidance.report(c,0.0,"escort")
	var priv_rep: Dictionary=Guidance.report(c,0.0,"privateer")
	check(snapshot()==before_snap and c.route_cache==cache_before,"witnessed convoy discovery and Guidance reports are 100% pure")
	var entry: Dictionary={}
	for row in witnessed:
		if str(row.get("ownerId",""))==str(trader.id):entry=row;break
	check(not entry.is_empty() and bool(entry.get("escortEligible",false)) and bool(entry.get("piracyInterceptEligible",false)) and int(entry.get("cargoValueCoins",0))>0,"witnessed loaded trader within 1800 units exposes both escortEligible and piracyInterceptEligible with positive cargoValueCoins")
	check(escort_rep.get("convoyOpportunities",[]).size()>=1 and priv_rep.get("convoyOpportunities",[]).size()>=1,"Guidance.report surfaces witnessed convoy opportunities for both Escort and Privateer")
	# 1. Verify existing Escort.start opportunity on a forked state.
	var escort_fork: Dictionary=c.state.duplicate(true)
	Escort.start(scene,str(trader.id))
	var started_escort: bool=scene.mode=="battle" and str(scene.battle_context.get("kind",""))=="escort" and str(scene.battle_context.get("allyOwnerId",""))==str(trader.id) and str(scene.battle_context.get("ownerId",""))==str(raider.id) and str(scene.battle.get("mission",{}).get("kind",""))=="escort"
	check(started_escort,"witnessed convoy enters actual Main.begin_battle through Escort.start(Main,id) against the observed threat")
	check(Money.total(c.state)==supply and people(c.state)==census,"Escort.start conserves global coins and people")
	scene._retire_battle_driver051();scene.Tactical.retire_planning051(scene.battle)
	scene.battle={};scene.battle_context={};scene.mode="campaign";scene.paused=true;c.travel_lock064=""
	# 2. Verify existing piracy Escort.prepare_intercept opportunity on a forked state.
	c.state=escort_fork.duplicate(true)
	var intercept: Dictionary=Escort.prepare_intercept(c,{"kind":"patrol","id":str(trader.id),"ownerId":str(trader.id),"name":"Declared witnessed civilian interception"})
	var prepared: bool=str(intercept.get("startError","")).is_empty() and str(intercept.get("mission",{}).get("kind",""))=="intercept" and str(intercept.get("mission",{}).get("carrierOwnerId",""))==str(trader.id) and not intercept.get("mission",{}).get("carrierUids",[]).is_empty()
	check(prepared,"witnessed convoy connects to the actual context-dictionary interception API and physical cargo mission")
	check(Money.total(c.state)==supply and people(c.state)==census,"Escort.prepare_intercept conserves global coins and people")
	convoy_witness={"staged":true,"stagingBasis":"Declared nearby chart positions only; actual pre-existing cargo, boats, purses and hostile relationship retained.","traderOwnerId":str(trader.id),"threatOwnerId":str(raider.id),"observedDay":float(entry.get("observedDay",0)),"tradeGood":entry.get("tradeGood",""),"tradeCargo":entry.get("tradeCargo",0),"cargo":entry.get("cargo",{}),"cargoValueCoins":entry.get("cargoValueCoins",0),"escortStarted":started_escort,"piracyInterceptPrepared":prepared,"battleOutcome":"UNRESOLVED_START_OPPORTUNITY_ONLY"}
	c.state=baseline.duplicate(true);c.route_cache=baseline_cache.duplicate(true)

func finish() -> void:
	if scene!=null:
		# A native source/API error may abort a nested function without reaching
		# its receipt. Preserve that exact blocked state and fail before any role
		# continues; no uninitialized reinvestment/operating fields are read.
		if not current_receipt.is_empty() and not receipts.any(func(r):return str(r.kind)==str(current_receipt.kind)):
			current_receipt.status="BLOCKED_SOURCE_CONTRACT"
			current_receipt.blocker=str(current_receipt.get("blocker","Role returned without its required completed receipt; inspect native stack"))
			current_receipt.blockedContext={"events":c.events.duplicate(true),"recentLog":c.state.get("log",[]).slice(-6),"pendingDays":int(c.pending_days),"economyTask":int(scene.economy_task),"workerGroupId":int(scene.economy_workers.group_id)}
			check(false,str(current_receipt.kind)+": stop at the failed native source/precondition contract")
			export_role_state(current_receipt);receipts.append(current_receipt.duplicate(true))
		scene.sync_economy();scene.free()
	var whole: float=elapsed()
	check(whole<BUDGET_SECONDS,"entire 086 fixture stays below 38 seconds; actual="+str(whole))
	check(receipts.size()==4 and receipts.all(func(r):return bool(r.get("staged",false)) and not bool(r.get("earnedFromDefaultStarter",true)) and str(r.get("status",""))=="STAGED_PAID_REINVESTED"),"all four staged civilian role witnesses complete paid work and paid reinvestment")
	check(bool(convoy_witness.get("escortStarted",false)) and bool(convoy_witness.get("piracyInterceptPrepared",false)),"witnessed civilian convoy connects to both existing escort and piracy intercept opportunities")
	var artifact: Dictionary={
		"ok":failures==0,
		"version":"v0.086",
		"sourceOnlyAuthor":"Argon-1 (quality086-argon-careers); Root executes queued native verification",
		"seed":59059,
		"stagedFixture":true,
		"earnedFromDefaultStarter":false,
		"checks":checks,
		"failures":failures,
		"wholeSeconds":whole,
		"bodyCapSeconds":BUDGET_SECONDS,
		"steps":steps,
		"payrollDays":payroll_days,
		"phases":phases,
		"receipts":receipts,
		"convoyWitness":convoy_witness,
		"completedSaves":receipts.map(func(r):return r.get("completedSave",{}))
	}
	var folder: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if not folder.is_empty():
		var file=FileAccess.open(folder.path_join("civilian-careers086-result.json"),FileAccess.WRITE)
		check(file!=null,"required civilian-careers086-result.json opens for writing")
		artifact.ok=failures==0;artifact.checks=checks;artifact.failures=failures
		if file!=null:file.store_string(JSON.stringify(artifact,"\t"));file.close()
	print("CIVILIAN086_RESULT ",JSON.stringify({"ok":failures==0,"checks":checks,"failures":failures,"wholeSeconds":whole,"staged":true,"earnedFromDefaultStarter":false,"roles":receipts.map(func(r):return {"kind":r.kind,"status":r.status,"operatingNet":r.operatingNet,"conversionInstalled":r.get("reinvestment",{}).get("conversionInstalled","")}),"convoyWitness":convoy_witness}))
	quit(0 if failures==0 else 1)
