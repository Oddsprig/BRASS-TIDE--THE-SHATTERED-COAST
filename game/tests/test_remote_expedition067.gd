extends SceneTree
## SOURCE CANDIDATE ONLY; Root owns native execution and the shared test lane.
## One actual Main/Core, one calculated finite treasury budget, real hires/stores,
## south approaches, three paid surveys, partial fixed cache, physical home return.
## No encounter suppression, NPC edits, position/clock edits or assigned victories.
const Main=preload("res://scripts/main.gd")
const IDS: Array=["glasswind_west_marker","glasswind_crown_log","glasswind_south_wreck"]
const ANCHORS: Array=[{"x":1360.0,"y":1380.0},{"x":2780.0,"y":1540.0},{"x":1820.0,"y":1640.0}]
var main
var c
var checks: int=0
var failures: int=0
var started: int=0
var finished: bool=false
var receipt: Dictionary={"status":"UNFINISHED","invoices":[],"phases":[]}
var supply: int=0
var owned: Array=[]
var parts: Array=[]

func _initialize() -> void:
	started=Time.get_ticks_msec()
	_run.call_deferred()

func check(value: bool,message: String) -> bool:
	checks+=1
	if not value:failures+=1;print("FAIL remote067: ",message)
	return value

func bounded() -> bool:
	if Time.get_ticks_msec()-started<43500:return true
	receipt.status="BODY_TIMEOUT"
	return check(false,"45-second body ceiling includes Main ready, paid voyage and cleanup")

func phase(label: String) -> void:
	receipt.phases.append({"phase":label,"elapsedMs":Time.get_ticks_msec()-started,"day":float(c.state.day) if c!=null and not c.state.is_empty() else 0})
	print("REMOTE067_PHASE ",label)

func protected_state() -> PackedByteArray:
	return var_to_bytes([c.state,c.pending_days,c.events,c.data,main.economy_task])

func equipment_ids() -> Array:
	var ids: Array=[]
	for boat in c.state.fleet:
		for item in boat.get("moduleCondition",{}).get("items",{}).values():ids.append(str(item.itemUid))
	ids.sort()
	return ids

func observe_events() -> bool:
	for event in c.pop_events():
		if str(event.get("kind","")) in ["encounter","ocean_encounter066","defeat"]:
			receipt.status="INTERRUPTED";receipt.event=event.duplicate(true)
			return check(false,"Unexpected real contact/loss interrupted the voyage; no arrival or victory is claimed")
	return true

func advance(seconds: float) -> bool:
	if not bounded():return false
	var before: float=float(c.state.day)
	c.step(seconds)
	main.sync_economy()
	if not check(float(c.state.day)>before and float(c.state.day)<=before+seconds/45.0+0.000001,"Only actual accepted Core.step time advances the one clock"):return false
	if not check(c.Money.total(c.state)==supply,"Normal settlement conserves all actual world purses"):return false
	return observe_events()

func finish_course() -> bool:
	for _piece in range(240):
		if c.state.path.is_empty():return true
		if not advance(4.0):return false
	return check(false,"The physical plotted route exceeded the bounded sailing loop")

func travel(intent: Dictionary) -> bool:
	for _action in range(8):
		if not bounded():return false
		var chosen: Dictionary=intent.duplicate(true)
		if c.state.world064.layer=="ocean" or c.state.world064.regionId==chosen.targetRegionId:chosen.outExit=""
		if chosen.targetRegionId=="shatter_coast":
			chosen.backExit="";chosen.homeEntry=""
			if c.home_local064():chosen.targetApproachId=""
		var q: Dictionary=c.voyage_quote065(chosen)
		if not check(q.get("routeOk",false),"Explicit normal route quote: "+str(q.get("message",""))):return false
		if q.get("nextAction",{}).get("kind")=="none":return true
		var action: Dictionary=main.voyage_action065(chosen)
		if not check(action.get("ok",false),"Actual Main approach/course/crossing callback: "+str(action.get("message",""))):return false
		if not finish_course():return false
	return check(false,"Physical travel did not reach its destination within eight explicit actions")

func sailor_total() -> int:
	var total: int=0
	for boat in c.state.fleet:total+=int(boat.crew)
	return total

func survey(site_id: String,action: String,save_party: bool=false) -> bool:
	var before_kits: float=c.Remote067.kits(c.state)
	var before_food: float=c.state.cargo.food
	var sailors: int=sailor_total()
	var begun: Dictionary=c.begin_survey(site_id,action)
	if not check(begun.get("ok",false),"Actual paid regional "+action+": "+str(begun.get("message",""))):return false
	check(is_equal_approx(c.Remote067.kits(c.state),before_kits-float(begun.supplies)),"Finite survey kits debited once from cargo then actual racks")
	check(is_equal_approx(float(c.state.cargo.food)+float(c.state.surveyFoodCredit),before_food),"Prepaid shore food remains within the existing food account")
	var ashore: int=0
	for boat in c.state.fleet:ashore+=int(boat.get("shoreCrew",0))
	check(ashore==int(begun.crewNeeded) and sailor_total()==sailors,"Reserved hands are the same numerical sailors, above the physical boat minimum")
	check(c.state.exploration.assignment.world064=={"schema":1,"layer":"local","regionId":"glasswind_keys"},"Assignment stores canonical regional identity")
	var frozen: PackedByteArray=protected_state()
	check(not c.chart_course(c.state.position).get("ok",false),"Movement is blocked while the regional party is deployed")
	check(not c.transition064("glasswind_keys","south").get("ok",false),"Region exit is blocked while the regional party is deployed")
	check(protected_state()==frozen,"Refused movement and crossing preserve actual party, stores and purses")
	if save_party:
		if not advance(45.0*0.25):return false
		main.save_game(false)
		var saved=JSON.parse_string(FileAccess.get_file_as_string(main.save_directory.path_join("voyage.json")))
		if not check(saved is Dictionary,"Actual private Main save contains the deployed party"):return false
		var paid: float=float(c.state.exploration.assignment.daysDone)
		var credit: float=float(c.state.surveyFoodCredit)
		if not check(c.restore(saved).get("ok",false),"Parsed active regional party restores through real raw preflight"):return false
		check(is_equal_approx(float(c.state.exploration.assignment.daysDone),paid) and is_equal_approx(float(c.state.surveyFoodCredit),credit),"Regional save/load retains actual progress and prepaid food")
		for corruption in ["identity","region","moving","crew","credit"]:
			var bad: Dictionary=saved.duplicate(true)
			if corruption=="identity":bad.exploration.assignment.erase("world064")
			elif corruption=="region":bad.exploration.assignment.world064.regionId="shatter_coast"
			elif corruption=="moving":bad.path=[bad.position.duplicate(true)]
			elif corruption=="crew":bad.fleet[0].shoreCrew=0
			else:bad.surveyFoodCredit=float(bad.exploration.assignment.foodSpent)+1
			var input: PackedByteArray=var_to_bytes(bad)
			var live: PackedByteArray=protected_state()
			check(not c.restore(bad).get("ok",false),"Malformed regional "+corruption+" save refuses")
			check(protected_state()==live and var_to_bytes(bad)==input,"Refused regional "+corruption+" save preserves input/live/events/pending/UIDs/purses")
		var recalled_credit: float=float(c.state.surveyFoodCredit)
		var recalled_food: float=float(c.state.cargo.food)
		var spent_kits: float=c.Remote067.kits(c.state)
		var recalled_day: float=float(c.state.day)
		if not check(c.recall_survey().get("ok",false),"Actual regional party can be recalled at its matching stationary landing"):return false
		check(c.state.fleet.all(func(physical):return int(physical.get("shoreCrew",0))==0) and c.state.exploration.assignment.is_empty(),"Recall returns exactly the reserved sailors to their existing boats")
		check(is_equal_approx(float(c.state.cargo.food),recalled_food+recalled_credit) and is_zero_approx(float(c.state.surveyFoodCredit)) and float(c.state.day)==recalled_day and c.Remote067.kits(c.state)==spent_kits,"Recall refunds unused food once; spent kits and actual elapsed time remain spent")
		var recalled: PackedByteArray=protected_state()
		check(not c.recall_survey().get("ok",false) and protected_state()==recalled,"Repeated recall cannot refund rations twice")
		var restarted: Dictionary=c.begin_survey(site_id,action)
		if not check(restarted.get("ok",false) and is_equal_approx(c.Remote067.kits(c.state),spent_kits-float(restarted.get("supplies",0))),"Actual re-landing pays fresh finite kits and restarts unfinished work"):return false
	for _piece in range(40):
		if c.state.exploration.assignment.is_empty():break
		if not advance(minf(4.0,maxf(0.001,(float(c.state.exploration.assignment.daysTotal)-float(c.state.exploration.assignment.daysDone))*45.0))):return false
	if not check(c.state.exploration.assignment.is_empty(),"Actual paid survey work completed"):return false
	check(c.state.fleet.all(func(boat):return int(boat.get("shoreCrew",0))==0) and is_zero_approx(float(c.state.surveyFoodCredit)),"Completion releases hands and unused food credit once")
	check(sailor_total()==sailors,"Survey completion creates no crew")
	return true

func _run() -> void:
	if not check(OS.get_environment("GAME_TEST_ARTIFACTS").is_absolute_path(),"Root supplies an isolated native artifact/profile directory"):await finish();return
	main=Main.new();main.qa_ocean066=true
	root.add_child.call_deferred(main)
	await main.ready
	main.set_process(false);main.set_physics_process(false);main.paused=true
	main.save_directory=OS.get_environment("GAME_TEST_ARTIFACTS").path_join("remote067-profile/saves")
	main.new_game(67067);c=main.core
	if not check(not c.state.is_empty(),"Actual Main/Core career initialized"):await finish();return
	supply=int(c.state.coinSupply);owned=c.state.fleet.map(func(boat):return str(boat.uid));parts=equipment_ids()
	phase("finite_preparation")
	var dock: Dictionary=c.current_port()
	var boat: Dictionary=c.state.fleet[0]
	var hire: int=maxi(0,int(boat.crewMin)+4-int(boat.crew))
	var target_fleet: Array=c.state.fleet.duplicate(true);target_fleet[0].crew+=hire
	var upkeep: Dictionary=c.Economy.daily_upkeep(target_fleet)
	var outward: Dictionary={"targetRegionId":"glasswind_keys","targetApproachId":"south","outExit":"south","backExit":"south","homeEntry":"south","returnPortId":"brass_haven","idleDays":15.75}
	var planned: Dictionary=c.voyage_quote065(outward)
	if not check(planned.get("routeOk",false),"Real south-route preparation is navigable"):await finish();return
	# One disclosed conservative budget: authored work, local landing travel,
	# route allowance and four extra wage days. It is never topped up later.
	var payroll_days: int=ceili(float(planned.allowance.payrollDays))+4
	var food_units: int=2
	var kit_units: int=2
	var budget: int=c.Economy.recruit_cost(dock,hire)+int(upkeep.wages)*payroll_days+food_units*c.Economy.price(dock,"food","buy")+kit_units*c.Economy.price(dock,"supplies","buy")
	var transfer: int=maxi(0,budget-int(c.state.coins))
	var treasury: Dictionary=c.port("brass_haven")
	if not check(transfer>0 and int(treasury.governmentPurse)>=transfer,"One calculated finite preparation budget needs actual existing treasury capital"):await finish();return
	if not check(c.Money.move(treasury,"governmentPurse",c.state,"coins",transfer,"Declared067 finite expedition preparation budget",c.state.moneyLog),"Actual treasury debited without changing coinSupply"):await finish();return
	receipt.invoices.append({"budget":budget,"treasuryTransfer":transfer,"payrollDays":payroll_days,"hire":hire,"foodUnits":food_units,"kitUnits":kit_units})
	if not check(c.recruit_crew(str(boat.uid),hire).get("ok",false),"Actual paid harbor hires reserve four spare hands"):await finish();return
	for purchase in [{"good":"food","qty":food_units},{"good":"supplies","qty":kit_units}]:
		var bought: Dictionary=c.trade(str(dock.id),str(purchase.good),int(purchase.qty),"buy")
		receipt.invoices.append(bought)
		if not check(bought.get("ok",false),"Actual stock/purse purchase: "+str(purchase.good)):await finish();return
	check(c.state.fleetOwners.any(func(owner):return owner.get("active",false)),"Actual NPC fleets remain active")
	check(c.Money.total(c.state)==supply and c.Remote067.spare_crew(c.state)>=4,"Paid preparation conserves coins and uses actual crew")
	phase("south_route_outward")
	if not travel(outward):await finish();return
	if not check(c.Remote067.local(c.state),"Same actual fleet enters Glasswind through its south approach"):await finish();return
	var hidden: PackedByteArray=protected_state()
	var unseen: Dictionary=c.exploration_view067()
	check(unseen.sites.is_empty() and unseen.wrecks.is_empty(),"No unknown local sites, names or loot leak on arrival")
	check(not c.begin_survey(IDS[2],"survey").get("ok",false),"Raw unknown final site cannot skip sightings and surveys")
	check(protected_state()==hidden,"Unknown view and refused work are pure")
	phase("three_paid_landings")
	for index in range(IDS.size()):
		if not check(c.chart_course(ANCHORS[index]).get("ok",false),"World.plot accepts the locked safe-water landing anchor") or not finish_course():await finish();return
		if not advance(0.5):await finish();return
		if not check(c.distance(c.state.position,ANCHORS[index])<0.001,"Physical sailing reaches the locked landing anchor"):await finish();return
		if not survey(str(IDS[index]),"chart",index==0) or not survey(str(IDS[index]),"survey"):await finish();return
		if index<2:
			check(not c.state.wreckSeededSources.has(c.Remote067.SOURCE),"Survey knowledge creates no early cache or cargo")
			if index==0:
				check(int(c.state.exploration.sites.get(IDS[1],{}).get("level",0))==0,"West's earned bearing does not automatically sight distant Crown; independently observed South is allowed")
	phase("finite_paid_partial_cargo")
	var cache: Dictionary={}
	for row in c.state.wrecks:
		if row.get("sourceId")==c.Remote067.SOURCE:cache=row
	if not check(not cache.is_empty(),"All three actual surveys reveal exactly the finite collapsed coaster"):await finish();return
	var cache_id: String=str(cache.id)
	check(cache.stores=={"engines":1,"copper":8,"supplies":12,"timber":16} and cache.components.is_empty() and is_equal_approx(c.Salvage._goods_weight(cache.stores),64),"Exactly the fixed64-weight manifest exists with no derived material lots")
	check(c.Salvage._goods_weight(cache.stores)>c.capacity()-c.cargo_weight(),"The stocked original skiff cannot carry the whole cache; an explicit partial lot is meaningful")
	var repeated: PackedByteArray=protected_state()
	c.Salvage.seed_expedition067(c,c.Exploration.catalog_site(c.state,IDS[2]))
	check(protected_state()==repeated,"Repeat reveal is exactly idempotent")
	# Create one real unsettled boundary for the pure inspection/refusal checks.
	var until_boundary: float=(floorf(float(c.state.day))+1.0-float(c.state.day))*45.0
	c.step(minf(45.0,until_boundary+0.001))
	if not observe_events():await finish();return
	var review: PackedByteArray=protected_state()
	var dto: Dictionary=c.exploration_view067()
	var q: Dictionary=c.recovery_quote(cache_id,"strip","engines",1)
	check(q.get("ok",false) and q.workDays>=1 and q.kitsRequired==q.workDays,"Pure explicit cargo quote prices real whole-day work and finite kits")
	check(dto.wrecks.size()==1 and not dto.wrecks[0].has("stores"),"Frame DTO has known markers only; manifest requires explicit quote")
	check(not c.Salvage.strip_good(c,cache_id,"engines",1).get("ok",false) and not c.Salvage.recover(c,cache_id,"strip").get("ok",false),"Raw Salvage entry points cannot bypass paid Core recovery")
	check(not c.recover_wreck(cache_id,"tow").get("ok",false) and not c.recover_wreck(cache_id,"gear").get("ok",false),"Collapsed cache cannot yield a hull or canonical fittings")
	check(not c.recover_wreck(cache_id,"strip","engines",2).get("ok",false),"Over-source cargo requests refuse instead of clamping into a grant")
	check(protected_state()==review,"DTO, quotes and refused raw/paid actions preserve pending days and every account")
	var prior_food: float=float(c.state.cargo.food)
	var prior_coins: int=int(c.state.coins)
	var prior_day: float=float(c.state.day)
	var prior_econ: int=int(c.state.econDay)
	var prior_kits: float=c.Remote067.kits(c.state)
	var result: Dictionary=main.recover_wreck(cache_id,"strip","engines",1)
	receipt.invoices.append(result)
	if not check(result.get("ok",false) and result.get("completed",false),"Actual Main paid cargo action completes: "+str(result.get("message",""))):
		if not result.get("completed",false):receipt.status="INTERRUPTED_WORK"
		await finish();return
	check(is_equal_approx(float(c.state.day)-prior_day,float(q.workDays)) and int(c.state.econDay)-prior_econ==int(q.payrollDays) and c.pending_days==0,"Bounded Core.step work settles every ordinary calendar day once")
	check(prior_coins-int(c.state.coins)==int(q.wages)+int(q.arrears) and is_equal_approx(prior_food-float(c.state.cargo.food),float(q.food)),"Actual payroll/food agree with quoted pending plus working days")
	check(is_equal_approx(prior_kits-c.Remote067.kits(c.state),float(q.kitsRequired)),"Exactly one existing kit is spent per real working day")
	check(float(c.state.cargo.engines)==1 and not c.state.cargoManifest.get("unassigned",{}).has("engines"),"Recovered engine commodity occupies the same boats' physical manifest")
	cache=c.Remote067.raw_wreck(c.state,cache_id)
	check(float(cache.stores.engines)==0 and c.Salvage._goods_weight(cache.stores)>0 and cache.status=="unclaimed","A partial finite cache remains at its original anchor")
	for corruption in ["extra_stores","tombstone","gear"]:
		var bad: Dictionary=JSON.parse_string(JSON.stringify(c.state))
		var bad_cache: Dictionary=c.Remote067.raw_wreck(bad,cache_id)
		if corruption=="extra_stores":bad_cache.stores.copper=9
		elif corruption=="tombstone":bad.wreckSeededSources[c.Remote067.SOURCE]=false
		else:bad_cache.sourceModuleCondition={}
		var protected: PackedByteArray=protected_state()
		check(not c.restore(bad).get("ok",false) and protected_state()==protected,"Raw cache "+corruption+" corruption refuses before normalization or publication")
	var pruned=c.Salvage.QuoteView.new(c)
	pruned.state.wrecks=pruned.state.wrecks.filter(func(row):return row.get("id")!=cache_id)
	var pruned_before: PackedByteArray=var_to_bytes(pruned.state)
	check(c.Salvage.seed_expedition067(pruned,c.Exploration.catalog_site(c.state,IDS[2])).is_empty() and var_to_bytes(pruned.state)==pruned_before,"Detached pruned-cache case retains the existing tombstone and cannot reseed finite stores")
	phase("physical_return_and_market")
	var returning: Dictionary={"targetRegionId":"shatter_coast","targetApproachId":"south","outExit":"south","backExit":"","homeEntry":"","returnPortId":"brass_haven","idleDays":0.0}
	var return_before: PackedByteArray=protected_state()
	var return_quote: Dictionary=c.voyage_quote065(returning)
	check(return_quote.get("routeOk",false) and protected_state()==return_before,"Explicit return review quotes a real route without moving, selling or settling")
	if not travel(returning):await finish();return
	check(c.current_port().get("id")=="brass_haven" and float(c.state.cargo.engines)==1,"Physical south route returns the recovered commodity to the actual home harbor")
	var sale: Dictionary=c.trade("brass_haven","engines",1,"sell")
	receipt.invoices.append(sale)
	check(sale.get("ok",false) and float(c.state.cargo.engines)==0,"Normal finite market trade pays for the carried commodity")
	check(c.state.fleet.map(func(physical):return str(physical.uid))==owned and equipment_ids()==parts,"Round trip keeps the same physical fleet and exact equipment UIDs")
	check(c.Money.total(c.state)==supply and int(c.state.wageArrears)==0,"All real voyage/survey/work/return wages conserve the original supply")
	main.save_game(false)
	var saved=JSON.parse_string(FileAccess.get_file_as_string(main.save_directory.path_join("voyage.json")))
	check(saved is Dictionary and c.restore(saved).get("ok",false),"Actual final partial-cache/cargo history restores from parsed private save")
	if failures==0:receipt.status="COMPLETED"
	await finish()

func finish() -> void:
	if finished:return
	finished=true
	if main!=null:
		main.sync_economy();main.queue_free()
		await process_frame
	var elapsed: int=Time.get_ticks_msec()-started
	check(elapsed<45000,"Whole native body including ready and owned cleanup is below45 seconds")
	receipt.fixture="remote_expedition067";receipt.sourceCandidate=true
	receipt.checks=checks;receipt.failures=failures;receipt.elapsedMs=elapsed
	var directory: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if directory.is_absolute_path():
		var file=FileAccess.open(directory.path_join("remote-expedition067-result.json"),FileAccess.WRITE)
		if file:file.store_string(JSON.stringify(receipt,"\t"));file.close()
	print("REMOTE067_RESULT ",JSON.stringify(receipt))
	quit(0 if failures==0 else 1)
