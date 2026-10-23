extends SceneTree
## Combined economic campaign pressure test, using actual copied-port workers.
const Money=preload("res://scripts/money.gd")
const Home=preload("res://scripts/home_harbor.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL campaign systems: "+text)
func procure(c,p: Dictionary,good: String,required: float) -> bool:
	var needed: int=ceili(maxf(0,required-float(p.publicStores.get(good,0))))
	if needed<1:return true
	var wallet: Dictionary={"coins":p.governmentPurse,"cargo":p.publicStores}
	var r: Dictionary=c.Economy.transact(p,wallet,good,needed,"buy",100000)
	if r.ok:p.governmentPurse=wallet.coins
	return bool(r.ok)
func _initialize() -> void:
	var started: int=Time.get_ticks_msec()
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("campaign-systems-fixture");scene.new_game();scene.set_process(false);scene.set_physics_process(false)
	var c=scene.core
	# Existing foreign actors stand by; this isolates actual company movement and
	# the shared economy. Naval hostile combat has separate native voyage coverage.
	for o in c.state.fleetOwners:o.active=false
	for p in c.state.patrols:p.active=false
	Money.move(c.current_port(),"governmentPurse",c.state,"coins",220000,"Finite combined campaign fixture",c.state.moneyLog)
	var direct: Array=c.Navigation.find_path(c.nav,c.port_position("brass_haven"),c.port_position("kelp_reach"))
	var cached: Array=c.cached_path(c.port_position("brass_haven"),c.port_position("kelp_reach"))
	check(JSON.stringify(direct)==JSON.stringify(cached),"Cached routes equal the actual pure navigation result")
	if not cached.is_empty():cached[0].x+=5000
	check(JSON.stringify(direct)==JSON.stringify(c.cached_path(c.port_position("brass_haven"),c.port_position("kelp_reach"))),"Caller edits cannot poison a cached path")
	for i in range(130):
		var end: Dictionary=c.port_position("kelp_reach");end.x+=float(i)*0.25
		c.cached_path(c.port_position("brass_haven"),end)
	check(c.route_cache.size()<=128,"Route-cache growth is bounded independently of player chart movement")
	c.cached_path({},c.port_position("kelp_reach"))
	check(JSON.stringify(direct)==JSON.stringify(c.cached_path(c.port_position("brass_haven"),c.port_position("kelp_reach"))),"Malformed endpoints cannot poison an unrelated valid cached route")
	var goods: Dictionary={};var hulls: Array=[]
	for good in c.Goods.ITEMS:goods[str(good)]=ceili(c.Goods.cost(str(good)))
	for h in c.data.HULLS:
		var bill: Dictionary=c.ship_quote(h)
		hulls.append({"id":h.id,"name":h.name,"readyCoins":int(bill.readyPrice),"materialCoins":int(bill.materialCost),"assemblyCoins":int(bill.laborCost),"supervisionCoins":int(bill.supervisionCost),"workerDays":float(bill.workerDays),"minimumCrew":int(h.crewMin),"dailyMinimumCrewCoins":int(h.crewMin)*100,"deploymentPoints":c.hull_points(h)})
	print("BALANCE_SNAPSHOT "+JSON.stringify({"sailorDayCoins":100,"initialCaptainCoins":int(c.data.START.coins),"goodsProductionCoins":goods,"hulls":hulls}))
	var supply: int=Money.total(c.state)
	check(c.data.HULLS.size()==24 and c.Goods.ITEMS.size()==20,"All original 24 hull roles and expanded 20 goods are present")
	check(Home.establish(c,"warehouse",str(c.current_port().id)).ok,"Actual staffed company premises use finite construction capital")
	var business: Dictionary=c.state.businesses[0]
	Money.move(business,"coins",c.state,"coins",int(business.coins),"Actual unpaid obligation pressure fixture",c.state.moneyLog)
	check(c.TrainingOps.enroll(c,2,"boarder").ok,"Actual paid training runs alongside businesses and physical commerce")
	check(c.LawOps.license(c,"guns",2).ok,"Finite paid customs record runs through the same campaign clock")
	check(c.buy_boat("tin_skiff").ok,"Actual spare boat and local crew are purchased")
	var uid: String=str(c.state.fleet[-1].uid)
	var limits: Dictionary={"buyMax":10000,"sellMin":0,"maxCargo":8.0,"reserve":3000,"risk":0.4}
	var charter: Dictionary=c.CompanyOps.create(c,[uid],"kelp_reach","timber",18000,limits)
	check(charter.ok,"Actual privately funded company begins its water route")
	if not charter.ok:scene.queue_free();await process_frame;quit(1);return
	var company: String=str(charter.id)
	var max_workers: int=0;var step_us: Array=[];var day_us: Array=[]
	var cohort: String="";var arrived: bool=false;var admitted: bool=false;var defense: bool=false
	for cycle in range(60):
		var target: int=floori(float(c.state.day))+1
		var count: int=0
		while floori(float(c.state.day))<target and count<200:
			var tick: int=Time.get_ticks_usec();c.step(0.25)
			if count%10==0:step_us.append(Time.get_ticks_usec()-tick)
			if c.pending_days>0:
				var economic: int=Time.get_ticks_usec();scene.sync_economy();day_us.append(Time.get_ticks_usec()-economic)
			count+=1
		max_workers=maxi(max_workers,scene.economy_workers.last_workers)
		check(Money.total(c.state)==supply and scene.economy_workers.group_id<0,"Coins conserve and worker copies join on day %d"%cycle)
		if cycle==2:
			check(c.state.regionalCrises.crises["brass_haven:wages"].active,"Actual shared campaign detects the three-day wage crisis")
			var passage: Dictionary=c.CrisisOps.begin(c,"kelp_reach",3)
			check(passage.ok,"A real funded civilian cohort fits the retained flagship: "+str(passage.get("message","")))
			if passage.ok:cohort=str(passage.id);c.chart_course(c.port_position("kelp_reach"),"kelp_reach")
		if not cohort.is_empty() and not arrived and c.current_port().get("id","")=="kelp_reach":
			var r: Dictionary=c.CrisisOps.arrive(c,cohort)
			if r.ok:arrived=true
		if arrived and not admitted and c.state.regionalCrises.jobs.is_empty():
			admitted=true;c.chart_course(c.port_position("brass_haven"),"brass_haven")
		if cycle>=7 and not defense and c.current_port().get("id","")=="brass_haven":
			c.Factions.adjust(c.state,"compact",25,"Paid watch fixture standing","campaign-watch")
			var p: Dictionary=c.current_port()
			for good in ["guns","ammo","timber","iron","supplies","food"]:procure(c,p,good,float({"guns":1,"ammo":8,"timber":8,"iron":2,"supplies":6,"food":4}[good]))
			var built: Dictionary=c.BoardingOps.build(c,"garrison",1)
			check(built.ok,"Actual public defense commissions alongside training and carrier accounts: "+str(built.get("message","")))
			defense=bool(built.ok)
		if cycle%10==9:
			check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Combined live features save and restore at day %d"%cycle)
		if cycle%10==0:await process_frame
	check(admitted and int(c.state.campaignFacts.get("resettlersAdmitted",0))==3,"Actual shared voyages admit existing people once")
	check(defense and c.port("brass_haven").get("defenses",{}).get("lastDay",0)==int(c.state.econDay),"Actual coastal crew provisions and wages follow every published economic day")
	check(c.state.tradeLaw.permits.is_empty(),"Thirty-day actual consignment coverage expires during the campaign")
	check(int(c.port("brass_haven").training.qualified.boarder)==2,"Actual completed training remains a finite qualification subset")
	var book: Dictionary=c.state.shippingCompanies[company]
	check(int(book.netProfit)==int(book.revenue)-int(book.cogs)-int(book.operating) and int(book.invested)==18000,"Physical company revenue, material basis, operation and invested capital stay distinct")
	check(int(book.revenue)>0 or str(book.status)=="waiting","Company either performs actual sales or records an actual operating shortage")
	check(c.state.regionalCrises.crises.size()<=c.state.ports.size()*3 and c.state.log.size()<=45 and c.state.moneyLog.size()<=60,"Combined campaign histories and facts remain bounded")
	# Buy a second genuine hull, then verify a carrier/flagship loss with one
	# newly introduced civilian good in the actual persistent wreck inventory.
	c.state.position=c.port_position("kelp_reach");c.stop_sailing()
	var extra: Dictionary=c.buy_boat("tin_skiff")
	check(extra.ok,"A real reserve hull is bought before the flagship-loss regression")
	if extra.ok:
		var source: Dictionary={}
		for p in c.state.ports:
			if c.ReserveOps.Reserves.exportable(p,"fine_timber")>=1:source=p;break
		check(not source.is_empty(),"Actual civilian finished timber is available from an existing producer")
		if not source.is_empty():
			c.state.position=c.port_position(str(source.id))
			check(c.trade(str(source.id),"fine_timber",1,"buy").ok,"Actual civilian salvage lot is bought from finite stock")
			c.Manifest.allocate(c.state)
			var carrier: Dictionary={}
			for b in c.state.fleet:
				if float(c.state.cargoManifest.get(str(b.uid),{}).get("fine_timber",0))>0:carrier=b;break
			check(not carrier.is_empty(),"The civilian lot has a real assigned carrier")
			if not carrier.is_empty():
				c.state.flagship=str(carrier.uid)
				var fight: Dictionary=scene.Battle.create({"fleet":c.FleetSupport.combat(c),"enemySpecs":[c.hull("tin_skiff")],"seed":28028})
				carrier.sunk=true;carrier.hp=0;carrier.crew=0;carrier.wounded=0;carrier.boarders=0
				c.battle_settled("lost",[c.hull("tin_skiff")],{"kind":"test","name":"Civilian carrier loss"},fight)
				check(c.state.fleet.any(func(b):return str(b.uid)==str(c.state.flagship)),"A surviving actual boat becomes flagship when the previous flagship sinks")
				check(c.state.wrecks.any(func(w):return float(w.stores.get("fine_timber",0))>0),"Real civilian cargo enters the persistent wreck without an unknown-good loophole")
				check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Civilian wreck inventory and a surviving flagship restore through complete validation")
	var snapshot: String=JSON.stringify(c.state)
	var r: Dictionary=scene.ui.GuidanceUI.Guidance.report(c,0,"merchant")
	check(JSON.stringify(c.state)==snapshot and r.cards.size()<=8,"Combined campaign guidance is bounded and read-only")
	scene.ui.GuidanceUI.open(scene.ui)
	check(scene.ui.modal_kind=="captain_priorities","Actual career, readiness and system-navigation controls render")
	check(Money.total(c.state)==supply and c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Combined final campaign retains exact coins and a valid save")
	step_us.sort();day_us.sort()
	var metrics: Dictionary={"cpu":OS.get_processor_name(),"logicalThreads":OS.get_processor_count(),"workerLanes":max_workers,"routeCacheEntries":c.route_cache.size(),"routeCacheHits":c.route_hits,"routeCacheMisses":c.route_misses,"economicDays":60,"campaignStepP95us":step_us[floori((step_us.size()-1)*0.95)],"economicPublicationP95us":day_us[floori((day_us.size()-1)*0.95)],"companyNetCoins":int(book.netProfit),"elapsedMs":Time.get_ticks_msec()-started,"rendering":"headless; GPU frame pacing not measured"}
	print("CAMPAIGN_METRICS "+JSON.stringify(metrics))
	check(Time.get_ticks_msec()-started<45000,"Sixty combined campaign days stay a short background check")
	scene.queue_free();await process_frame
	print("campaign systems: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
