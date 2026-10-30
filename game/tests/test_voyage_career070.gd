extends SceneTree
## SOURCE ONLY: Root runs this once in the shared Test Bridge lane/private profile.
## One ordinary career, actual courses/crossings, finite freight/survey escrows,
## normal payroll and replacement stores, HOME return and a useful paid Cargo Rig.
## Corrupt-input refusals are labeled separately; none is published as earned play.
const Campaign=preload("res://scripts/campaign.gd")
const Workers=preload("res://scripts/economy_workers.gd")
const BODY_LIMIT_MS: int=55000
const REGION: String="settled_01"
const SPONSOR: String="settled_01_harbor_01"
const DESTINATION: String="settled_01_harbor_02"
const SITE: String="settled_01_survey"
const BOAT_PHYSICAL: Array=["uid","type","crew","wounded","shoreCrew","fuel","ammo","supplies","hp","maxHp","sunk","armor","engine","fire","water","breaches","moduleCondition","boarders","loadout","refitLocker","conversion","storedPort","mothballed","towed","needsHarborRepair"]
var c
var workers=Workers.new()
var started: int=0
var checks: int=0
var failures: int=0
var supply: int=0
var payroll: int=0
var gross_paid: int=0
var receipt: Dictionary={"status":"UNFINISHED","earnedVoyage":false,"phases":[],"accepted":[],"payments":[],"crossings":[],"controlled":[]}

func _initialize() -> void:
	started=Time.get_ticks_msec()
	_run.call_deferred()

func check(value: bool,message: String) -> bool:
	checks+=1
	if not value:failures+=1;print("FAIL career070: ",message)
	return value

func bounded() -> bool:
	if Time.get_ticks_msec()-started<BODY_LIMIT_MS-1500:return true
	receipt.status="BODY_TIMEOUT"
	return check(false,"55-second body includes setup, actual work, saves and worker cleanup")

func phase(label: String) -> void:
	var row: Dictionary={"phase":label,"elapsedMs":Time.get_ticks_msec()-started,"day":float(c.state.day),"coins":int(c.state.coins)}
	receipt.phases.append(row);print("CAREER070_PHASE ",JSON.stringify(row))

func same_values(a,b) -> bool:
	# Exact decoded physical values: no epsilon or rounded financial comparison.
	if (a is int or a is float) and (b is int or b is float):return a==b
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same_values(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for index in range(a.size()):
			if not same_values(a[index],b[index]):return false
		return true
	return a==b

func protected_state() -> PackedByteArray:
	return var_to_bytes([c.state,c.events,c.pending_days,c.nav,c.ocean_context064,c.ocean_context066,c.route_cache,c.route_hits,c.route_misses,c.ocean_watch066,c.ocean_conditions066,c.exploration_timer,c.sailing_clearance,c.travel_lock064])

func physical_boat(boat: Dictionary) -> Dictionary:
	var out: Dictionary={}
	for key in BOAT_PHYSICAL:
		if boat.has(key):out[key]=boat[key]
	return out

func physical(snapshot: Dictionary,rebuild_forecasts: bool=false) -> Dictionary:
	var ports: Array=snapshot.ports.duplicate(true)
	if rebuild_forecasts:
		# Exactly the four derived reserve forecasts refresh on restore. Every
		# other port field, stock, worker subset, policy, escrow and purse is exact.
		var forecast: Dictionary={"ports":snapshot.ports.duplicate(true),"fleetOwners":snapshot.fleetOwners}
		c.ReserveOps.refresh({"state":forecast})
		for index in range(ports.size()):
			if not ports[index].has("reserves"):c.ReserveOps.Reserves.ensure(ports[index])
			for key in ["observedDemand","incoming","contractedLots","availableRecipes"]:ports[index].reserves[key]=forecast.ports[index].reserves[key]
	var owners: Array=[]
	for owner in snapshot.fleetOwners:
		var out: Dictionary={}
		for key in ["id","kind","faction","homePort","coins","crewPurse","wageArrears","cargo","tradeGood","tradeCargo","atPort"]:
			if owner.has(key):out[key]=owner[key]
		out.boats=owner.get("boats",[]).map(func(b):return physical_boat(b))
		owners.append(out)
	var player: Dictionary={}
	for key in ["coins","crewPurse","wageArrears","debt","cargo","day","econDay","world064","position","heading","path","destination","lastPort","flagship","cargoManifest","surveyFoodCredit"]:player[key]=snapshot.get(key)
	player.fleet=snapshot.fleet.map(func(b):return physical_boat(b))
	var out: Dictionary={"ports":ports,"owners":owners,"player":player,"coinSupply":snapshot.coinSupply,"totalCoins":c.Money.total(snapshot)}
	for key in ["voyageJobs","doneVoyageJobs","contacts","marketSnapshots","exploration","shipping068","sector069","sectorApplied069","sectorKnowledge069","islandOwnership069"]:out[key]=snapshot.get(key)
	return out.duplicate(true)

func parsed_save(label: String) -> Dictionary:
	var path: String=OS.get_environment("GAME_TEST_ARTIFACTS").path_join("career070-"+label+".json")
	var file=FileAccess.open(path,FileAccess.WRITE)
	if not check(file!=null,"Private "+label+" save opens"):return {}
	file.store_string(JSON.stringify(c.state));file.close()
	var saved=JSON.parse_string(FileAccess.get_file_as_string(path))
	return saved if check(saved is Dictionary,"Actual "+label+" disk save decodes") else {}

func restore_exact(saved: Dictionary,label: String) -> bool:
	if not bounded():return false
	var expected: Dictionary=physical(saved,true)
	var input: PackedByteArray=var_to_bytes(saved)
	var restored: Dictionary=c.restore(saved)
	if not check(restored.get("ok",false),label+" restore: "+str(restored.get("message",""))):return false
	var actual: Dictionary=physical(c.state)
	var scopes: Dictionary={}
	for key in expected:scopes[key]=same_values(expected[key],actual[key])
	receipt[label+"RestoreScopes"]=scopes
	print("CAREER070_RESTORE ",label," ",JSON.stringify(scopes))
	if not same_values(expected,actual):
		var rows: Array=[]
		restore_diff070(expected,actual,"restore",rows)
		receipt.restoreDifferences=rows
		for row in rows:print("CAREER070_RESTORE_DIFF ",JSON.stringify(row))
	return check(same_values(expected,actual) and var_to_bytes(saved)==input,label+" retains exact decoded physical books and original client escrow without recall/resupply")

func restore_diff070(expected,actual,path: String,rows: Array,has_expected: bool=true,has_actual: bool=true) -> void:
	if rows.size()>=8:return
	if has_expected and has_actual and same_values(expected,actual):return
	if not has_expected or not has_actual or typeof(expected)!=typeof(actual):
		rows.append({"path":path,"expected":JSON.stringify(expected,"",true,true).left(320) if has_expected else "<missing>","actual":JSON.stringify(actual,"",true,true).left(320) if has_actual else "<missing>"});return
	if expected is Dictionary:
		for key in expected:
			restore_diff070(expected[key],actual.get(key),path+"."+str(key),rows,true,actual.has(key))
		for key in actual:
			if not expected.has(key):restore_diff070(null,actual[key],path+"."+str(key),rows,false,true)
	elif expected is Array:
		for index in range(maxi(expected.size(),actual.size())):
			restore_diff070(expected[index] if index<expected.size() else null,actual[index] if index<actual.size() else null,path+"["+str(index)+"]",rows,index<expected.size(),index<actual.size())
	else:rows.append({"path":path,"expected":JSON.stringify(expected,"",true,true).left(320),"actual":JSON.stringify(actual,"",true,true).left(320)})

func checkpoint070(path: String,bound: String) -> void:
	receipt.status="CHECKPOINT_DIAGNOSTIC";receipt.diagnosticOnly=true;receipt.earnedVoyage=false
	var allowed: String="C:/Users/bligh/Documents/Codex/.runtime/game-test-bridge/jobs/c6d7e124ba124a838ac05ef701879a11/attempt-001/voyage-career/career070-active.json"
	if not check(path.replace("\\","/").simplify_path()==allowed and bound=="2d64250f608faefbaf6e828fa49092669b586acef98bd2e55a18df1ac61a3c1b" and FileAccess.get_sha256(path)==bound,"Hash-bound synthetic checkpoint only"):return
	var saved=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not check(saved is Dictionary,"Synthetic active-job checkpoint decodes"):return
	var world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c=Campaign.new(world)
	supply=int(saved.coinSupply)
	restore_exact(saved,"checkpoint")

func controlled_save_cases(saved: Dictionary) -> bool:
	phase("CONTROLLED_corrupt_endpoint_refusals")
	for kind in ["sponsor_region","target_account","survey_site"]:
		if not bounded():return false
		var bad: Dictionary=saved.duplicate(true)
		if kind=="sponsor_region":bad.voyageJobs[0].regionId="glasswind_keys"
		elif kind=="target_account":bad.voyageJobs[0].targetPort="absent_harbor070"
		else:
			for job in bad.voyageJobs:
				if job.kind=="survey":job.siteId="absent_site070"
		var frozen: PackedByteArray=protected_state()
		var input: PackedByteArray=var_to_bytes(bad)
		var state_ref: Dictionary=c.state
		var result: Dictionary=c.restore(bad)
		if not check(not result.get("ok",false) and is_same(c.state,state_ref) and protected_state()==frozen and var_to_bytes(bad)==input,"CONTROLLED "+kind+" refuses before live/input/cache publication"):return false
		receipt.controlled.append({"case":kind,"refusal":str(result.get("message",""))})
	return true

func settle_days() -> bool:
	while c.pending_days>0:
		if not bounded():return false
		var due: int=int(c.Economy.daily_upkeep(c.state.fleet).wages)
		var before: int=int(c.state.coins)
		c.pending_days-=1
		workers.start(c.state.ports,1,c.TradeFlow.blockades(c),int(c.state.seed)+int(c.state.econDay)*104729)
		var result: Dictionary=workers.finish(true)
		c.apply_economy(result.ports,result.events,result.days)
		if not check(before-int(c.state.coins)==due and int(c.state.wageArrears)==0,"Actual working crew paid the normal100coins/sailor-day"):return false
		payroll+=due
	return true

func advance(seconds: float) -> bool:
	if not bounded():return false
	var before: float=float(c.state.day)
	c.step(seconds)
	if not settle_days():return false
	for event in c.pop_events():
		if event.get("kind","") in ["encounter","ocean_encounter066","defeat"]:
			receipt.status="INTERRUPTED";receipt.event=event
			return check(false,"Actual encounter/loss interrupts this voyage; no substituted arrival or victory")
	if not check(float(c.state.day)>before and float(c.state.day)<=before+seconds/45.0+0.000001,"Only accepted normal movement/work advances the clock"):return false
	return check(c.Money.total(c.state)==supply,"All live client, crew, harbor and player accounts conserve world coins")

func finish_course() -> bool:
	for _piece in range(240):
		if c.state.path.is_empty():return true
		if not advance(4.0):return false
	return check(false,"Actual water course exceeded the bounded movement loop")

func gate(region: String,approach: String) -> bool:
	var result: Dictionary=c.approach_course064(region,approach)
	if not check(result.get("ok",false),"Real approach course: "+str(result.get("message",""))) or not finish_course():return false
	result=c.transition064(region,approach)
	if not check(result.get("ok",false),"Real paired crossing: "+str(result.get("message",""))):return false
	receipt.crossings.append({"regionId":region,"approachId":approach,"actualWorld":c.world_location064().world064,"day":float(c.state.day)})
	return true

func sail(port_id: String) -> bool:
	var port: Dictionary=c.port(port_id)
	var plotted: Dictionary=c.chart_course({"x":port.x,"y":port.y},port_id)
	if not check(plotted.get("ok",false),"Real harbor course: "+str(plotted.get("message",""))) or not finish_course() or not advance(0.5):return false
	return check(c.work_port070().get("id")==port_id and is_same(c.work_port070(),c.port(port_id)),"Stopped actual berth resolves the one live "+port_id+" account")

func accept(offer: Dictionary) -> bool:
	# Another compatible acceptance can change local material prices. Compare
	# this transaction with its current offer, not the earlier board snapshot.
	var shown: int=int(offer.get("reward",0))
	var fresh: Dictionary={}
	for candidate in c.VoyageJobs.available(c):
		if str(candidate.id)==str(offer.id):fresh=candidate;break
	if not check(not fresh.is_empty(),"Selected work still has a current funded offer"):return false
	offer=fresh
	var port: Dictionary=c.port(str(offer.port))
	var purse: int=int(port[str(offer.payerKey)])
	var coins: int=int(c.state.coins)
	var freight: Dictionary=offer.get("freight",{})
	var stock: float=float(port.stocks.get(str(freight.get("good","")),0))
	var result: Dictionary=c.accept_voyage_job(str(offer.id))
	if not check(result.get("ok",false),"Normal funded acceptance: "+str(result.get("message",""))):return false
	var job: Dictionary=c.VoyageJobs._find(c.state,str(offer.id))
	var invoice: int=int(offer.get("materialInvoice",0)) if offer.payerKey=="governmentPurse" else 0
	receipt.lastAcceptance={"kind":offer.kind,"earlierFee":shown,"currentFee":offer.reward,"heldEscrow":job.escrow,"payerBefore":purse,"payerAfter":port[str(offer.payerKey)],"invoice":invoice,"playerBefore":coins,"playerAfter":c.state.coins}
	if not check(int(job.escrow)==int(offer.reward) and int(port[str(offer.payerKey)])==purse-int(offer.reward)-invoice and int(c.state.coins)==coins,"Actual client's existing purse funds escrow; captain receives no advance"):return false
	if not freight.is_empty() and not check(float(port.stocks[str(freight.good)])==stock-float(freight.qty),"One sealed freight lot leaves the actual sponsor stock"):return false
	receipt.accepted.append({"id":job.id,"kind":job.kind,"port":job.port,"targetPort":job.targetPort,"grossFee":job.reward,"escrow":job.escrow,"materialInvoice":invoice})
	return check(c.Money.total(c.state)==supply,"Accepting work never creates coins or a second job book")

func pay(id: String) -> bool:
	var job: Dictionary=c.VoyageJobs._find(c.state,id).duplicate(true)
	var port: Dictionary=c.work_port070()
	var coins: int=int(c.state.coins)
	var stock: float=float(port.stocks.get(str(job.freight.get("good","")),0))
	var result: Dictionary=c.settle_voyage_job(id)
	if not check(result.get("ok",false),"Actual settlement: "+str(result.get("message",""))):return false
	if not check(int(c.state.coins)==coins+int(job.escrow) and c.VoyageJobs._find(c.state,id).is_empty(),"Captain receives exactly the held client escrow once"):return false
	if job.kind=="freight" and not check(float(port.stocks[str(job.freight.good)])==stock+float(job.freight.qty),"Real destination receives the complete sealed lot"):return false
	var logged: bool=false
	for person in c.state.contacts:
		if str(person.get("id",""))!="harbor:"+str(job.port):continue
		for entry in person.get("log",[]):
			if entry.get("event")=="job:"+id+":paid" and entry.get("port")==str(port.id):logged=true
	if not check(logged,"The sponsoring harbor records payment at the actual work berth"):return false
	gross_paid+=int(job.escrow)
	receipt.payments.append({"id":id,"coins":job.escrow,"actualPort":port.id,"day":float(c.state.day)})
	return check(c.Money.total(c.state)==supply,"Payment only transfers the original finite escrow")

func survey(action: String) -> bool:
	var kits: float=c.Remote067.kits(c.state)
	var crew: int=c.crew_count()
	var result: Dictionary=c.begin_survey(SITE,action)
	if not check(result.get("ok",false),"Real shore "+action+": "+str(result.get("message",""))):return false
	if not check(c.Remote067.kits(c.state)==kits-float(result.supplies),"Actual paid survey kits are consumed once"):return false
	for _piece in range(40):
		if c.state.exploration.assignment.is_empty():break
		var remaining: float=(float(c.state.exploration.assignment.daysTotal)-float(c.state.exploration.assignment.daysDone))*45.0
		if not advance(minf(4.0,maxf(0.001,remaining))):return false
	return check(c.state.exploration.assignment.is_empty() and c.crew_count()==crew and c.state.fleet.all(func(b):return int(b.get("shoreCrew",0))==0),"The same paid sailors finish and return from "+action)

func replace_stores() -> bool:
	var boat: Dictionary=c.state.fleet[0]
	var port: Dictionary=c.current_port()
	var stocks: Dictionary=port.stocks.duplicate(true)
	var fuel: float=float(boat.fuel)
	var kits: float=float(boat.supplies)
	var coins: int=int(c.state.coins)
	var result: Dictionary=c.resupply_boat(str(boat.uid),"full")
	if not check(result.get("ok",false),"Buy real fuel and kit replacements: "+str(result.get("message",""))):return false
	if not check(float(boat.fuel)>fuel and float(boat.supplies)>kits and is_equal_approx(float(stocks.fuel)-float(port.stocks.fuel),float(boat.fuel)-fuel) and is_equal_approx(float(stocks.supplies)-float(port.stocks.supplies),float(boat.supplies)-kits) and int(c.state.coins)<coins,"Replacement fuel/kits consume real harbor stock and captain coins"):return false
	var food: int=ceili(maxf(0,float(c.data.START.food)-float(c.state.cargo.food)))
	if food>0 and not check(c.trade(str(port.id),"food",food,"buy").get("ok",false),"Pay for all consumed starting rations before counting profit"):return false
	receipt.replacementStores={"fuel":float(boat.fuel)-fuel,"supplies":float(boat.supplies)-kits,"food":food,"paidCoins":coins-int(c.state.coins)}
	return true

func buy_useful_improvement() -> bool:
	var uid: String=str(c.state.fleet[0].uid)
	var port: Dictionary=c.current_port()
	var quote: Dictionary=c.FleetIdentity.quote_conversion(c,uid,"cargo_rig")
	if not check(quote.get("ok",false),"Existing useful Cargo Rig quote: "+str(quote.get("message",""))):return false
	var net: int=int(c.state.coins)-int(c.data.START.coins)
	if not check(net>=int(quote.cost) and int(quote.materialCost)>0 and int(quote.shipwrightWages)>0,"True net voyage earnings after payroll/replacements cover the complete useful conversion"):return false
	var stocks: Dictionary=port.stocks.duplicate(true)
	var purses: Dictionary={}
	for key in ["cash","householdPurse","expertPurse","governmentPurse"]:purses[key]=port[key]
	var labor: float=float(port.get("_yardWorkersUsed",0))
	var capacity: float=c.capacity()
	var coins: int=int(c.state.coins)
	var result: Dictionary=c.FleetIdentity.install_conversion(c,uid,"cargo_rig")
	if not check(result.get("ok",false),"Real paid Cargo Rig installation: "+str(result.get("message",""))):return false
	for good in quote.materials:
		if not check(float(port.stocks[good])==float(stocks[good])-float(quote.materials[good]),"Cargo Rig consumes real "+str(good)):return false
	if not check(int(c.state.coins)==coins-int(quote.cost) and int(port.cash)==int(purses.cash)+int(quote.materialCost)+int(quote.margin) and int(port.householdPurse)==int(purses.householdPurse)+int(quote.shipwrightWages) and int(port.expertPurse)==int(purses.expertPurse)+int(quote.mechanicWages)+int(quote.engineerWages) and int(port.governmentPurse)==int(purses.governmentPurse)+int(quote.tax),"Conversion pays the real supplier, workers, specialists and duty exactly"):return false
	if not check(c.capacity()>capacity and c.state.fleet[0].conversion=="cargo_rig" and float(port.get("_yardWorkersUsed",0))>labor and int(c.state.coins)>=int(c.data.START.coins),"Useful35percent hold improvement consumes yard labor while preserving all starting capital"):return false
	receipt.upgrade={"conversion":"cargo_rig","cost":quote.cost,"netBeforePurchase":net,"netAfterPurchase":int(c.state.coins)-int(c.data.START.coins),"holdBefore":capacity,"holdAfter":c.capacity(),"materials":quote.materials,"workerWages":quote.shipwrightWages,"specialistWages":int(quote.mechanicWages)+int(quote.engineerWages)}
	return check(c.Money.total(c.state)==supply,"Useful purchase conserves every actual account")

func earned_voyage() -> bool:
	phase("normal_starter_and_paid_capable_crew")
	var boat: Dictionary=c.state.fleet[0]
	if not check(int(c.state.coins)==int(c.data.START.coins) and c.state.fleet.size()==1 and c.Goods.SAILOR_WAGE==100,"Unmodified normal starter purse, hull and sailor wage"):return false
	var uid: String=str(boat.uid)
	if not check(c.recruit_crew(uid,2).get("ok",false) and c.crew_count()==7,"Normal paid hires provide minimum3plus4survey hands"):return false
	phase("earned_outward_crossing")
	if not gate("shatter_coast","south") or not gate(REGION,"north") or not sail(SPONSOR):return false
	var frozen: PackedByteArray=protected_state()
	if not check(c.current_port().is_empty() and not c.work_port070().is_empty() and not c.recruit_crew(uid,1).get("ok",false) and not c.resupply_boat(uid).get("ok",false) and protected_state()==frozen,"Generated work berth grants no HOME crew or resupply service"):return false
	var offers: Array=c.VoyageJobs.available(c)
	if not check(protected_state()==frozen,"Available work leaves live books and the explicitly player-owned navigation cache unchanged"):return false
	var freight: Dictionary={};var survey_job: Dictionary={}
	for offer in offers:
		if offer.kind=="freight" and offer.targetPort==DESTINATION and freight.is_empty():freight=offer
		elif offer.kind=="survey" and offer.siteId==SITE:survey_job=offer
	if not check(not freight.is_empty() and not survey_job.is_empty(),"Actual complementary-island freight and observed local survey are compatible and funded"):return false
	frozen=protected_state()
	var preview: Dictionary=c.VoyageJobs.offer_view070(c,survey_job)
	if not check(preview.get("routeOk",false) and protected_state()==frozen and int(preview.grossFee)==int(survey_job.reward) and int(preview.crewNeeded)==4 and preview.expectedCosts.get("includesReturn",false) and preview.likelySurplus==float(preview.grossFee)-float(preview.expectedCosts.totalValue),"Selected pure preview prices actual7crew and subtracts whole-trip costs/return once"):return false
	receipt.surveyQuote={"grossFee":preview.grossFee,"expectedCosts":preview.expectedCosts,"returnReserve":preview.returnReserve,"likelySurplus":preview.likelySurplus}
	if not accept(freight) or not accept(survey_job):return false
	var active: Dictionary=parsed_save("active")
	if active.is_empty() or not restore_exact(active,"active") or not controlled_save_cases(active):return false
	phase("earned_freight_and_paid_shore_work")
	if not sail(DESTINATION) or not pay(str(freight.id)):return false
	# Use the same circuit's return hold only if an actual funded client and
	# exportable stock now exist. No reverse contract or stock is manufactured.
	var return_freight: Dictionary={}
	for offer in c.VoyageJobs.available(c):
		if offer.kind=="freight" and offer.targetPort==SPONSOR:return_freight=offer;break
	receipt.returnFreightAvailable=not return_freight.is_empty()
	if not return_freight.is_empty() and not accept(return_freight):return false
	if not sail(SPONSOR):return false
	if not return_freight.is_empty() and not pay(str(return_freight.id)):return false
	if not survey("chart") or not survey("survey") or not pay(str(survey_job.id)):return false
	phase("earned_home_return_and_replacement_costs")
	if not gate(REGION,"north") or not gate("shatter_coast","south") or not sail("brass_haven"):return false
	if not check(c.state.fleet.size()==1 and str(c.state.fleet[0].uid)==uid and c.crew_count()==7 and int(c.state.wageArrears)==0 and payroll>0 and gross_paid>0,"Same working fleet returns with real client income and all payroll paid"):return false
	if not replace_stores() or not buy_useful_improvement():return false
	var saved: Dictionary=parsed_save("completed")
	if saved.is_empty() or not restore_exact(saved,"completed"):return false
	receipt.payrollPaid=payroll;receipt.grossPaid=gross_paid;receipt.finalCoins=c.state.coins;receipt.earnedVoyage=true
	return true

func _run() -> void:
	var checkpoint: String="";var bound: String=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--restore-checkpoint="):checkpoint=argument.trim_prefix("--restore-checkpoint=")
		elif argument.begins_with("--checkpoint-sha256="):bound=argument.trim_prefix("--checkpoint-sha256=")
	if not checkpoint.is_empty():checkpoint070(checkpoint,bound);finish();return
	if not check(OS.get_environment("GAME_TEST_ARTIFACTS").is_absolute_path(),"Root supplies a private test artifact/profile directory"):finish();return
	var world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	if not check(world is Dictionary,"Actual campaign definitions decode"):finish();return
	c=Campaign.new(world)
	var result: Dictionary=c.new_game(69069)
	if not check(result.get("ok",false),"Normal fresh career: "+str(result.get("message",""))):finish();return
	supply=int(c.state.coinSupply)
	if earned_voyage():receipt.status="COMPLETED" if failures==0 else "FAILED"
	finish()

func finish() -> void:
	if workers.group_id>=0:workers.finish(true)
	c=null
	var elapsed: int=Time.get_ticks_msec()-started
	check(elapsed<BODY_LIMIT_MS,"Whole source fixture including setup/worker cleanup is under55seconds")
	if receipt.status=="UNFINISHED":receipt.status="FAILED"
	receipt.checks=checks;receipt.failures=failures;receipt.elapsedMs=elapsed
	print("CAREER070_RESULT ",JSON.stringify(receipt))
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
