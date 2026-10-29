extends SceneTree
## Root executes through Test Bridge; body <82s within one whole batch <120s.
## The merchant earns its physical voyage. Player relocation, the short067
## provenance cases and the NPC combat branch below are DECLARED controlled
## staging; none count as an earned player crossing, survey or combat victory.
const Main=preload("res://scripts/main.gd")
const BODY_LIMIT_MS: int=82000
var main
var c
var started: int=0
var checks: int=0
var failures: int=0
var finished: bool=false
var supply: int=0
var uids: Array=[]
var parsed_midleg: bool=false
var player_staged: bool=false
var visited: Dictionary={}
var receipt: Dictionary={"status":"UNFINISHED","phases":[],"invoices":[],"controlled":[]}

func _initialize() -> void:
	started=Time.get_ticks_msec()
	_run.call_deferred()

func check(value: bool,message: String) -> bool:
	checks+=1
	if not value:failures+=1;print("FAIL shipping068: ",message)
	return value

func bounded() -> bool:
	if Time.get_ticks_msec()-started<79000:return true
	receipt.status="BODY_TIMEOUT"
	return check(false,"Bounded fixture body leaves three seconds for owned cleanup")

func phase(label: String) -> void:
	var row: Dictionary={"phase":label,"elapsedMs":Time.get_ticks_msec()-started,"day":float(c.state.day) if c!=null and not c.state.is_empty() else 0.0}
	receipt.phases.append(row);print("SHIPPING068_PHASE ",JSON.stringify(row))

func protected_state() -> PackedByteArray:
	return var_to_bytes([c.state,c.pending_days,c.events])

func same_values(a,b) -> bool:
	if (a is int or a is float) and (b is int or b is float):return is_equal_approx(float(a),float(b))
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

func physical() -> Dictionary:
	var owner: Dictionary=c.fleet_owner("patrol-7")
	var boats: Array=[]
	for boat in owner.boats:
		boats.append({"uid":str(boat.uid),"crew":float(boat.crew),"wounded":float(boat.wounded),"fuel":float(boat.fuel),"ammo":float(boat.ammo),"supplies":float(boat.supplies),"hp":float(boat.hp),"sunk":bool(boat.sunk)})
	var cargo: Dictionary={}
	for good in owner.cargo:cargo[str(good)]=float(owner.cargo[good])
	return {"boats":boats,"coins":int(owner.coins),"crewPurse":int(owner.crewPurse),"arrears":int(owner.wageArrears),"cargo":cargo,"tradeCargo":float(owner.tradeCargo),"tradeGood":str(owner.tradeGood),"route":JSON.parse_string(JSON.stringify(c.state.shipping068.model.route))}

func assert_same_physical(before: Dictionary,message: String) -> bool:
	# Explicit numerical fields are normalized above; parsed JSON keeps the same values.
	return check(same_values(physical(),before),message)

func advance(seconds: float) -> bool:
	if not bounded():return false
	var before: float=float(c.state.day)
	c.step(seconds);main.sync_economy()
	if float(c.state.day)<=before:
		receipt.status="NO_CLOCK_PROGRESS"
		receipt.failure={"dayBefore":before,"day":float(c.state.day),"log":c.state.log.slice(0,3).duplicate(true),"holding":str(c.state.shipping068.holding),"model":c.state.shipping068.model.duplicate(true)}
		receipt.failure["invalidRenderActors"]=[]
		for actor in c.OceanCampaign066.actors(c,c.state.ocean066):
			if not c.OceanCampaign066.Travel._boats_valid(actor.boats):
				receipt.failure.invalidRenderActors.append({"ownerId":actor.ownerId,"boats":actor.boats})
		var staged: Dictionary=c.ShippingFlow068.stage(c,seconds)
		receipt.failure["stagedMerchant"]=staged.get("actor",{})
		receipt.failure["stagedTypes"]=[]
		for boat in staged.get("actor",{}).get("boats",[]):
			var types: Dictionary={"uid":type_string(typeof(boat.uid)),"engineModule":type_string(typeof(boat.get("engineModule"))),"spec":{},"mounts":[]}
			for key in boat.spec:types.spec[key]=type_string(typeof(boat.spec[key]))
			for mount in boat.spec.get("weaponMounts",[]):
				var fields: Dictionary={}
				for key in mount:fields[key]=type_string(typeof(mount[key]))
				types.mounts.append(fields)
			receipt.failure.stagedTypes.append(types)
		print("SHIPPING068_FAILURE ",JSON.stringify(receipt.failure))
		return check(false,"Shared travel stage accepted no clock progress; see SHIPPING068_FAILURE for the actual refusal and shipping state")
	if not check(float(c.state.day)>=before and float(c.state.day)<=before+seconds/45.0+0.000001,"One accepted shared clock interval"):return false
	if not check(c.Money.total(c.state)==supply,"All port, fleet and player coins remain in the original supply"):return false
	for event in c.pop_events():
		if str(event.get("kind","")) in ["encounter","ocean_encounter066","defeat"]:
			receipt.status="INTERRUPTED";receipt.event=event.duplicate(true)
			return check(false,"An actual player encounter/loss interrupted this fixture; no arrival or win is substituted")
	return true

func parsed_restore() -> bool:
	phase("parsed_midleg_restore")
	main.save_game(false)
	var saved=JSON.parse_string(FileAccess.get_file_as_string(main.save_directory.path_join("voyage.json")))
	if not check(saved is Dictionary,"Actual private Main save parses as JSON"):return false
	var before: Dictionary=physical()
	var branch_invoice: Dictionary=c.state.shipping068.installation.invoice.duplicate(true)
	if not check(c.restore(saved).get("ok",false),"Parsed mid-leg save accepts the one canonical merchant and finite installation invoice"):return false
	if not assert_same_physical(before,"Restore preserves same merchant UIDs, cargo, crew, damage, purses, route and sequence"):return false
	if not check(c.restore(JSON.parse_string(JSON.stringify(c.state))).get("ok",false),"Second parsed restore cannot replay departure or setup"):return false
	check(same_values(c.state.shipping068.installation.invoice,branch_invoice),"Restore retains the exact historical invoice without a refill")
	assert_same_physical(before,"Viewing/restoring twice cannot sell, pay, reload or advance the carrier")
	for corruption in ["invoice","model","memory"]:
		var bad: Dictionary=JSON.parse_string(JSON.stringify(c.state))
		if corruption=="invoice":bad.shipping068.installation.invoice.consumed.timber=9
		elif corruption=="model":bad.shipping068.model.route.sequence+=1
		else:bad.ocean066.memory.sightings["invented-owner"]={}
		var protected: PackedByteArray=protected_state()
		var input_before: PackedByteArray=var_to_bytes(bad)
		check(not c.restore(bad).get("ok",false) and protected_state()==protected and var_to_bytes(bad)==input_before,"Raw "+corruption+" refuses before live/input/events/UID/account mutation")
	return failures==0

func loaded_and_distant() -> bool:
	phase("controlled_loaded_distant_equal_interval")
	var live: Dictionary=c.state
	var pending: int=c.pending_days
	var events: Array=c.events.duplicate(true)
	var watch: float=c.ocean_watch066
	var conditions: Array=c.ocean_conditions066.duplicate(true)
	var survey_timer: float=c.exploration_timer
	var clearance: float=c.sailing_clearance
	var seconds: float=minf(0.05,(floorf(float(live.day))+1.0-float(live.day))*45.0*0.5)
	# Two tiny branches reuse this Core/nav and the identical actual fleet/book.
	# Both player charts differ from the merchant's ocean; no market/day is replayed.
	c.state=live.duplicate(true);c.pending_days=pending;c.events=[]
	c.step(seconds)
	var loaded: Dictionary=physical()
	var loaded_day: float=float(c.state.day)
	c.state=live.duplicate(true);c.pending_days=pending;c.events=[]
	c.ocean_watch066=watch;c.ocean_conditions066=conditions.duplicate(true)
	c.exploration_timer=survey_timer;c.sailing_clearance=clearance
	var home: Dictionary=c.port("brass_haven")
	c._publish_location064({"world064":{"schema":1,"layer":"home","regionId":"shatter_coast"},"position":{"x":float(home.x),"y":float(home.y)},"heading":0.0,"path":[],"destination":""})
	c.step(seconds)
	check(same_values(physical(),loaded) and is_equal_approx(float(c.state.day),loaded_day),"Changing only the loaded player chart leaves the same distant fleet's location, goods, purses, crew and accepted interval equal")
	c.state=live;c.pending_days=pending;c.events=events
	c.ocean_watch066=watch;c.ocean_conditions066=conditions
	c.exploration_timer=survey_timer;c.sailing_clearance=clearance
	receipt.controlled.append("Two identical0.05s Core branches compare loaded-player charts; neither branch is an earned player crossing or a second merchant voyage.")
	return failures==0

func legacy_and_pending() -> bool:
	phase("legacy_and_atomic_installation")
	var installed: Dictionary=c.state.duplicate(true)
	var legacy: Dictionary=installed.duplicate(true)
	var invoice: Dictionary=legacy.shipping068.installation.invoice
	var donor: Dictionary=c.NavalAI._find_port(legacy,"kelp_reach")
	var cost: int=0
	for row in invoice.purchases:
		cost+=int(row.total);donor.stocks[row.good]+=float(row.qty)
	donor.governmentPurse+=int(invoice.total);donor.cash-=cost
	donor.population+=8;donor.workforce+=8;donor.availableWorkers+=8
	c.Economy.sync_workforce(donor)
	legacy.ports=legacy.ports.filter(func(p):return p.id!="westglass_anchorage")
	legacy.erase("shipping068")
	if not check(c.Money.total(legacy)==supply,"Declared inverse historical split produces a finite ten-port legacy fixture"):return false
	var before: Array=[legacy.fleet.map(func(b):return str(b.uid)),legacy.position.duplicate(true),legacy.cargo.duplicate(true),legacy.exploration.duplicate(true),legacy.get("wrecks",[]).duplicate(true)]
	if not check(c.restore(legacy).get("ok",false),"Absent optional shipping safely installs after raw validation and legacy preflight"):return false
	check(c.state.ports.size()==11 and c.state.shipping068.installation.status=="installed","Ten home ports plus one funded authored branch")
	check(same_values([c.state.fleet.map(func(b):return str(b.uid)),c.state.position,c.state.cargo,c.state.exploration,c.state.get("wrecks",[])],before),"Installation leaves player/party/cache/cargo/location untouched")
	var installed_before: PackedByteArray=var_to_bytes(c.state)
	c.ShippingFlow068.install(c)
	check(var_to_bytes(c.state)==installed_before,"Installed branch never resets or refills on another install call")
	# An independent copied account case, with its cash moved to another real purse.
	var saved_live: Dictionary=c.state
	c.state=legacy.duplicate(true)
	var source: Dictionary=c.port("kelp_reach")
	var transfer: int=int(source.governmentPurse)
	c.Money.move(source,"governmentPurse",source,"householdPurse",transfer,"Declared insufficient-funding fixture")
	var original_ports: PackedByteArray=var_to_bytes(c.state.ports)
	check(not c.ShippingFlow068.install(c).get("ok",false) and c.state.shipping068.installation.status=="pending","An unfunded old-save branch remains visibly pending")
	check(var_to_bytes(c.state.ports)==original_ports and c.Money.total(c.state)==supply,"Failed installation changes no population, stock or purse")
	var attempt: PackedByteArray=var_to_bytes(c.state)
	c.ShippingFlow068.install(c)
	check(var_to_bytes(c.state)==attempt,"Repeated pending attempts are coalesced within one published economy day")
	c.state=saved_live
	return failures==0

func stage_player_remote() -> bool:
	# Only the player is relocated in this declared market/visibility setup.
	var before: Dictionary=physical()
	var location: Dictionary={"world064":{"schema":1,"layer":"local","regionId":"glasswind_keys"},"position":{"x":756.0,"y":732.0},"heading":0.0,"path":[],"destination":""}
	var valid: Dictionary=c.OceanWorld064.prepare(location,c.ocean_context064,c.Routes.clearance(c))
	if not check(valid.get("ok",false),"Declared player setup uses the final actual clear-water berth"):return false
	c._publish_location064(valid.location)
	c.ShippingFlow068.after_step(c)
	receipt.controlled.append("Player relocated to certified Westglass berth for access/loaded-chart checks; no player voyage claimed.")
	check(c.current_port().is_empty() and not c.home_local064(),"Remote market does not enable HOME harbor services")
	assert_same_physical(before,"Entering the player's loaded chart preserves the distant merchant's original state")
	var private_state: PackedByteArray=protected_state()
	var view: Dictionary=c.shipping_view068()
	var port: Dictionary=c.remote_port068()
	check(view.ports.size()==1 and port.get("id")=="westglass_anchorage" and view.ownership.size()==1,"Only the actually sighted Reedwater island/harbor holding is published")
	if not port.is_empty():port.stocks.food=-999.0
	if not view.ports.is_empty():view.ports[0].name="mutated detached DTO"
	check(protected_state()==private_state,"Market and ownership DTOs are detached and do not normalize live state")
	var food: float=float(c.state.cargo.food)
	var stock: float=float(c.port("westglass_anchorage").stocks.food)
	var purse: int=int(c.state.coins)
	var price: int=c.Economy.price(c.port("westglass_anchorage"),"food","buy")
	var purchase: Dictionary=main.remote_trade068("food",1,"buy")
	if not check(purchase.get("ok",false),"Actual synchronized Main remote market purchases one finite food lot"):return false
	check(is_equal_approx(float(c.state.cargo.food),food+1.0) and is_equal_approx(float(c.port("westglass_anchorage").stocks.food),stock-1.0) and int(c.state.coins)==purse-price,"One remote trade changes actual holds, stock and purses exactly once")
	var receipt_before: int=c.state.shipping068.receipts.size()
	var protected: PackedByteArray=protected_state()
	check(not main.remote_trade068("food",1000000,"buy").get("ok",false) and protected_state()==protected and c.state.shipping068.receipts.size()==receipt_before,"An impossible remote order refuses without a receipt or account mutation")
	return failures==0

func targeted067() -> bool:
	phase("controlled_targeted067_party_cache")
	var live: Dictionary=c.state
	var pending: int=c.pending_days
	var events: Array=c.events.duplicate(true)
	c.state=live.duplicate(true)
	# This controlled landing is not an earned voyage/survey; begin reserves real hands/tools.
	var site: Dictionary=c.Exploration.catalog_site(c.state,"glasswind_west_marker")
	c._publish_location064({"world064":{"schema":1,"layer":"local","regionId":"glasswind_keys"},"position":{"x":float(site.x),"y":float(site.y)},"heading":0.0,"path":[],"destination":""})
	c.Exploration.discover_near(c.state,c.state.position,620.0)
	if not check(c.begin_survey("glasswind_west_marker","chart").get("ok",false),"Controlled067 landing begins a real two-sailor paid-tool party"):c.state=live;return false
	var party: Dictionary=JSON.parse_string(JSON.stringify(c.state.exploration.assignment))
	var hands: Array=c.state.fleet.map(func(b):return int(b.get("shoreCrew",0)))
	if not check(c.restore(JSON.parse_string(JSON.stringify(c.state))).get("ok",false),"Parsed active067 party restores with installed068 port and scheduled merchant"):c.state=live;return false
	check(same_values(c.state.exploration.assignment,party) and c.state.fleet.map(func(b):return int(b.get("shoreCrew",0)))==hands,"Restore does not recall, progress or duplicate the active shore party")
	var bad: Dictionary=JSON.parse_string(JSON.stringify(c.state));bad.fleet[0].shoreCrew=0
	var protected: PackedByteArray=protected_state()
	check(not c.restore(bad).get("ok",false) and protected_state()==protected,"Malformed raw067 reservation refuses before live shipping/party publication")
	check(c.recall_survey().get("ok",false),"Original party recall returns only unused prepaid food")
	for id in c.Remote067.SITE_IDS:
		c.state.exploration.sites[id].level=3;c.state.exploration.sites[id].rewarded=true
	var cache_site: Dictionary=c.Exploration.catalog_site(c.state,"glasswind_south_wreck")
	var cache: Dictionary=c.Salvage.seed_expedition067(c,cache_site)
	if not check(not cache.is_empty(),"Controlled surveyed precondition creates the one canonical067 cache"):c.state=live;return false
	var cache_id: String=str(cache.id)
	# One copper lot is declared already lost from a partial cache, never replenished.
	cache=c.Remote067.raw_wreck(c.state,cache_id);cache.stores.copper-=1.0
	var remaining: float=float(cache.stores.copper)
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).get("ok",false),"Parsed partial067 finite cache coexists with the068 invoice/model")
	var repeated: Dictionary=c.Salvage.seed_expedition067(c,cache_site)
	check(is_equal_approx(float(c.Remote067.raw_wreck(c.state,cache_id).stores.copper),remaining) and is_equal_approx(float(repeated.get("stores",{}).get("copper",-1)),remaining),"Restore and repeat seed return the same partial cache without refreshing its stocks")
	bad=JSON.parse_string(JSON.stringify(c.state));c.Remote067.raw_wreck(bad,cache_id).stores.copper=9.0
	protected=protected_state()
	check(not c.restore(bad).get("ok",false) and protected_state()==protected,"Raw cache stock inflation refuses without touching shipping or owners")
	receipt.controlled.append("Targeted067 landing/party and surveyed partial-cache provenance only; no full067 voyage or earned survey claimed.")
	c.state=live;c.pending_days=pending;c.events=events
	return failures==0

func controlled_conflict() -> bool:
	phase("controlled_real_npc_resolver")
	var live: Dictionary=c.state
	c.state=live.duplicate(true)
	var location: Dictionary={"world064":{"schema":1,"layer":"ocean","regionId":"open_ocean"},"position":{"x":1400.0,"y":500.0},"heading":0.0,"path":[],"destination":""}
	var route: Dictionary=c.state.shipping068.model.route
	route.phase="outbound";route.sequence=2;route.location=location.duplicate(true);route.nextDueSecond=float(c.state.day)*45.0
	var merchant: Dictionary=c.fleet_owner("patrol-7")
	merchant.atPort="";merchant.erase("harborServiceUntilDay")
	var raider: Dictionary=c.fleet_owner("patrol-0")
	var home: Dictionary=c.ocean_context064.regions.shatter_coast
	var gate: Dictionary=c.OceanWorld064._project(c.ocean_context064,home,home.approaches[0].position)
	c.state.ocean066.contact={"ownerId":"patrol-0","phase":"patrol","location":location.duplicate(true),"gate":{"regionId":"shatter_coast","approachId":"north"},"waypoint":{"x":gate.x+80.0,"y":gate.y}}
	raider.atPort="";raider.erase("harborServiceUntilDay")
	var patrol: Dictionary=c.NavalAI._find_patrol(c.state,"patrol-0")
	patrol.active=false;patrol.hidden=true;patrol.holding=true;patrol.course=[];patrol.erase("interceptPoint")
	# The raw engine resolver still judges actual hostility, range, custody and budget.
	# Use the next ledger date for this declared isolated combat setup, not a victory flag.
	c.state.navalAi.encounterDay=-1
	c.state.navalAi.encounters=[]
	var before: Dictionary=physical()
	var result: Dictionary=c.NavalAI.resolve_at068(c,"patrol-0","patrol-7",location,location)
	receipt.controlled.append({"kind":"co-located existing NPCs; real resolver outcome, not earned travel/win","result":result.duplicate(true)})
	check(result.get("ok",false),"Controlled physical NPC pair uses the real salvo/prize resolver")
	if result.get("ok",false):
		check(c.Money.total(c.state)==supply,"Real NPC conflict/prize transfers conserve the global purses")
		check(not same_values(physical(),before),"Real salvos/prizes affect the original merchant's physical state")
		var protected: PackedByteArray=protected_state()
		check(not c.NavalAI.resolve_at068(c,"patrol-0","patrol-7",location,location).get("ok",false) and protected_state()==protected,"Same-day real encounter cannot resolve or transfer its cargo twice")
	c.state=live
	return failures==0

func _run() -> void:
	if not check(OS.get_environment("GAME_TEST_ARTIFACTS").is_absolute_path(),"Root supplies a synthetic private artifact/profile directory"):await finish();return
	main=Main.new();main.qa_ocean066=true
	root.add_child.call_deferred(main);await main.ready
	main.set_process(false);main.set_physics_process(false);main.paused=true
	main.new_game(68068);c=main.core
	if not check(not c.state.is_empty() and c.state.get("shipping068",{}).get("installation",{}).get("status")=="installed","Actual Main/Core constructor installs the funded branch"):await finish();return
	supply=int(c.state.coinSupply)
	uids=c.fleet_owner("patrol-7").boats.map(func(b):return str(b.uid))
	if not legacy_and_pending():await finish();return
	phase("finite_player_waiting_budget")
	var harbor: Dictionary=c.current_port()
	var costs: Dictionary=c.Economy.daily_upkeep(c.state.fleet)
	var food: int=maxi(0,ceili(float(costs.food)*45.0-float(c.state.cargo.food)))
	var budget: int=ceili(float(costs.wages)*45.0)+food*c.Economy.price(harbor,"food","buy")+2*c.Economy.price(harbor,"supplies","buy")
	var waiting_transfer: int=maxi(0,budget-int(c.state.coins))
	if not check(c.Money.move(harbor,"governmentPurse",c.state,"coins",waiting_transfer,"Declared068 fixture player waiting wages and stores",c.state.moneyLog),"Finite derived waiting budget from actual existing harbor treasury"):await finish();return
	if food>0 and not check(c.trade(str(harbor.id),"food",food,"buy").get("ok",false),"Player waiting rations purchased from actual stock"):await finish();return
	if not check(c.trade(str(harbor.id),"supplies",2,"buy").get("ok",false),"Targeted067 tools purchased rather than seeded"):await finish();return
	var starting_days: float=float(c.fleet_owner("patrol-7").daysOperated)
	var starting_econ: int=int(c.state.econDay)
	phase("earned_merchant_round_trip")
	var returned: bool=false
	for piece in range(1800):
		if not advance(4.0):await finish();return
		var route: Dictionary=c.state.shipping068.model.route
		if not route.is_empty():
			var key: String=str(route.phase)+"/"+str(route.location.world064.layer)
			if not visited.has(key):visited[key]=true;phase(key)
			if route.phase=="lost":receipt.status="MERCHANT_LOST";check(false,"The earned shipping carrier was actually lost; no delivery is substituted");await finish();return
			if not player_staged:
				if not stage_player_remote():await finish();return
				player_staged=true
			if route.phase=="outbound" and route.location.world064.layer=="ocean" and not parsed_midleg:
				if not parsed_restore() or not loaded_and_distant():await finish();return
				parsed_midleg=true
			if route.phase=="home_service" and int(route.sequence)>=7:
				returned=true;break
		if piece%16==0:await process_frame
	if not check(returned and parsed_midleg,"Same merchant physically departs, crosses, reaches remote market, returns and begins paid HOME service within the bounded body"):await finish();return
	var delivered: bool=false
	for row in c.state.shipping068.invoices:
		receipt.invoices.append(row.duplicate(true))
		if row.kind=="deliver" and row.portId=="westglass_anchorage" and int(row.qty)>0:delivered=true
	check(delivered,"At least one real food shipment sold into finite remote stocks/purses")
	check(visited.has("outbound/home") and visited.has("outbound/ocean") and visited.has("outbound/local") and visited.has("return/ocean") and visited.has("return/home"),"The one authoritative location traverses both real local charts and the ocean in both directions")
	check(c.fleet_owner("patrol-7").boats.map(func(b):return str(b.uid))==uids,"Physical carrier retains original hull UIDs throughout the earned voyage")
	check(is_equal_approx(float(c.fleet_owner("patrol-7").daysOperated)-starting_days,float(int(c.state.econDay)-starting_econ)),"Fleets.tick applies exactly one ordinary upkeep day per published economy day")
	check(float(c.fleet_owner("patrol-7").harborServiceUntilDay)>float(c.state.day) and c.fleet_owner("patrol-7").atPort=="kelp_reach","Physical HOME arrival publishes one real quarter-day paid service")
	if not targeted067() or not controlled_conflict():await finish();return
	if failures==0:receipt.status="COMPLETED"
	await finish()

func finish() -> void:
	if finished:return
	finished=true
	if main!=null:
		main.sync_economy();main.queue_free();await process_frame
	var elapsed: int=Time.get_ticks_msec()-started
	check(elapsed<BODY_LIMIT_MS,"Whole native body including Main ready and owned cleanup is under82 seconds")
	receipt.fixture="interregional_voyage068";receipt.sourceCandidate=true
	receipt.checks=checks;receipt.failures=failures;receipt.elapsedMs=elapsed
	var directory: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if directory.is_absolute_path():
		var file=FileAccess.open(directory.path_join("interregional-voyage068-result.json"),FileAccess.WRITE)
		if file:file.store_string(JSON.stringify(receipt,"\t"));file.close()
	print("SHIPPING068_RESULT ",JSON.stringify(receipt))
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
