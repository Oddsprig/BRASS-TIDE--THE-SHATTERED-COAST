extends SceneTree
## SOURCE ONLY. Root executes in one shared lane with a private profile.
## One normal fresh career: real courses/crossings, finite market, paid surveys,
## return and parsed disk restore. No treasury grant, clock edit or NPC suppression.
## Constructed legacy compatibility staging removes current generated accounts
## and their receipts, then stages old party/cache preconditions; not an earned voyage.
const Campaign=preload("res://scripts/campaign.gd")
const Workers=preload("res://scripts/economy_workers.gd")
const BODY_LIMIT_MS: int=55000
const RESTORE_CHECKPOINT: String="C:/Users/bligh/Documents/Codex/.runtime/game-test-bridge/jobs/a611797641b44a7ab6c8974a6853db89/attempt-001/sector-voyage/sector069-private-voyage.json"
var c
var workers=Workers.new()
var started: int=0
var checks: int=0
var failures: int=0
var supply: int=0
var receipt: Dictionary={"status":"UNFINISHED","phases":[],"controlled":[],"trades":[]}

func _initialize() -> void:
	started=Time.get_ticks_msec()
	_run.call_deferred()

func check(value: bool,message: String) -> bool:
	checks+=1
	if not value:failures+=1;print("FAIL sector069: ",message)
	return value

func bounded() -> bool:
	if Time.get_ticks_msec()-started<BODY_LIMIT_MS-1500:return true
	receipt.status="BODY_TIMEOUT"
	return check(false,"55-second body includes setup, real work, restores and cleanup")

func phase(label: String) -> void:
	var row: Dictionary={"phase":label,"elapsedMs":Time.get_ticks_msec()-started,"day":float(c.state.day) if c!=null and not c.state.is_empty() else 0.0}
	receipt.phases.append(row);print("SECTOR069_PHASE ",JSON.stringify(row))

func same_values(a,b) -> bool:
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

func expected_restore_ports(snapshot: Dictionary) -> Array:
	# Only these forecasts/recipe metadata are rebuilt by ReserveOps.refresh.
	# Start from decoded saved values; every physical field and policy stays exact.
	var expected: Array=snapshot.ports.duplicate(true)
	var forecasts: Dictionary={"ports":snapshot.ports.duplicate(true),"fleetOwners":snapshot.fleetOwners}
	c.ReserveOps.refresh({"state":forecasts})
	for index in range(expected.size()):
		# Pre-fix synthetic Westglass saves lack this book; keep all existing books exact.
		if expected[index].id=="westglass_anchorage" and not expected[index].has("training"):c.TrainingOps.Training.ensure(expected[index])
		for key in ["observedDemand","incoming","contractedLots","availableRecipes"]:
			expected[index].reserves[key]=forecasts.ports[index].reserves[key]
	return expected

func difference_value(value,present: bool=true) -> Dictionary:
	return {"type":type_string(typeof(value)) if present else "MISSING","value":JSON.stringify(value,"",true,true) if present else "<missing>"}

func restore_differences(saved,actual,path: String,rows: Array,saved_present: bool=true,actual_present: bool=true) -> void:
	# Match the assertion: equal numeric values and equivalent string keys are equal.
	# Keep one extra row to disclose truncation; no financial tolerances.
	if rows.size()>=5:return
	if saved_present and actual_present and same_values(saved,actual):return
	if not saved_present or not actual_present or typeof(saved)!=typeof(actual):
		rows.append({"path":path,"expected":difference_value(saved,saved_present),"restored":difference_value(actual,actual_present)});return
	if saved is Dictionary:
		for key in saved:
			var child: String=path+"["+type_string(typeof(key))+":"+JSON.stringify(key,"",true,true)+"]"
			if actual.has(key):
				restore_differences(saved[key],actual[key],child,rows)
			else:restore_differences(saved[key],null,child,rows,true,false)
			if rows.size()>=5:return
		for key in actual:
			if not saved.has(key):restore_differences(null,actual[key],path+"["+type_string(typeof(key))+":"+JSON.stringify(key,"",true,true)+"]",rows,false,true)
			if rows.size()>=5:return
	elif saved is Array:
		for index in range(maxi(saved.size(),actual.size())):
			restore_differences(saved[index] if index<saved.size() else null,actual[index] if index<actual.size() else null,path+"["+str(index)+"]",rows,index<saved.size(),index<actual.size())
			if rows.size()>=5:return
	elif saved!=actual:
		rows.append({"path":path,"expected":difference_value(saved),"restored":difference_value(actual)})

func expected_restore_values(snapshot: Dictionary,total_coins: int) -> Dictionary:
	# Capture before restore in both modes; diagnostics must use this exact composite.
	return {"sector069":snapshot.sector069,"ports":expected_restore_ports(snapshot),"merchant":merchant(snapshot),"coinSupply":snapshot.coinSupply,"totalCoins":total_coins}

func compare_restore(expected: Dictionary) -> bool:
	var actual: Dictionary={"sector069":c.state.sector069,"ports":c.state.ports,"merchant":merchant(),"coinSupply":c.state.coinSupply,"totalCoins":c.Money.total(c.state)}
	var components: Dictionary={}
	var matches: bool=true
	for scope in expected:
		components[scope]=same_values(actual[scope],expected[scope])
		if not components[scope]:matches=false
	receipt.restoreComparison="canonical_expected_restore_composite";receipt.restoreComponents=components
	print("SECTOR069_RESTORE_COMPONENTS ",JSON.stringify(components))
	receipt.restoreDifferences=[];receipt.restoreDifferenceLimit=12;receipt.restoreDifferenceLimitPerScope=4;receipt.restoreDifferencesTruncatedScopes=[]
	if matches:return true
	# Money scalars first so truncating nested differences cannot hide conservation.
	for scope in ["coinSupply","totalCoins","sector069","ports","merchant"]:
		var rows: Array=[]
		restore_differences(expected[scope],actual[scope],scope,rows)
		var limit: int=mini(4,12-receipt.restoreDifferences.size())
		if rows.size()>limit:receipt.restoreDifferencesTruncatedScopes.append(scope)
		for row in rows.slice(0,limit):
			receipt.restoreDifferences.append(row)
			print("SECTOR069_RESTORE_DIFF ",JSON.stringify(row))
	return false

func checkpoint_diagnostic(options: Dictionary) -> void:
	receipt.status="CHECKPOINT_DIAGNOSTIC";receipt.diagnosticOnly=true;receipt.earnedVoyage=false
	var path: String=str(options.get("restore-checkpoint",""))
	var bound: String=str(options.get("checkpoint-sha256",""))
	receipt.checkpoint=path;receipt.checkpointSha256=bound
	if not check(path.is_absolute_path() and path.replace("\\","/").simplify_path()==RESTORE_CHECKPOINT,"Diagnostic accepts only the absolute synthetic checkpoint path"):return
	if not check(bound.length()==64 and bound.is_valid_hex_number() and FileAccess.get_sha256(path)==bound,"Checkpoint FileAccess SHA256 matches the exact bound hash"):return
	var saved=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not check(saved is Dictionary,"Bound synthetic checkpoint decodes as a saved snapshot"):return
	var world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	if not check(world is Dictionary,"Diagnostic campaign definitions decode"):return
	c=Campaign.new(world)
	var expected: Dictionary=expected_restore_values(saved,int(saved.coinSupply))
	var restored: Dictionary=c.restore(saved)
	if not check(restored.get("ok",false),"Checkpoint restore: "+str(restored.get("message",""))):return
	check(compare_restore(expected),"Checkpoint matches the exact earned-voyage restore composite")

func protected_state() -> PackedByteArray:
	return var_to_bytes([c.state,c.events,c.pending_days,c.ocean_context064,c.ocean_context066,c.route_cache,c.ocean_watch066,c.ocean_conditions066,c.exploration_timer,c.sailing_clearance,c.travel_lock064])

func merchant(snapshot: Dictionary={}) -> Dictionary:
	if snapshot.is_empty():snapshot=c.state
	var owner: Dictionary={}
	for row in snapshot.get("fleetOwners",[]):
		if row.get("id")=="patrol-7":owner=row;break
	var boats: Array=[]
	for boat in owner.get("boats",[]):
		var row: Dictionary={}
		for key in ["uid","type","crew","wounded","fuel","ammo","supplies","hp","maxHp","sunk","armor","engine","fire","water","breaches","moduleCondition","boarders","loadout","refitLocker"]:row[key]=boat.get(key)
		boats.append(row)
	return {"boats":boats,"id":owner.get("id"),"faction":owner.get("faction"),"homePort":owner.get("homePort"),"coins":owner.get("coins"),"crewPurse":owner.get("crewPurse"),"arrears":owner.get("wageArrears"),"cargo":owner.get("cargo",{}).duplicate(true),"tradeGood":owner.get("tradeGood"),"tradeCargo":owner.get("tradeCargo"),"route":snapshot.get("shipping068",{}).get("model",{}).get("route",{}).duplicate(true)}

func settle() -> void:
	while c.pending_days>0:
		c.pending_days-=1
		workers.start(c.state.ports,1,c.TradeFlow.blockades(c),int(c.state.seed)+int(c.state.econDay)*104729)
		var result: Dictionary=workers.finish(true)
		c.apply_economy(result.ports,result.events,result.days)

func advance(seconds: float) -> bool:
	if not bounded():return false
	var before: float=float(c.state.day)
	c.step(seconds);settle()
	if not check(float(c.state.day)>before and float(c.state.day)<=before+seconds/45.0+0.000001,"One actual accepted clock interval"):return false
	if not check(c.Money.total(c.state)==supply,"All live purses conserve the declared world supply"):return false
	for event in c.pop_events():
		if event.get("kind","") in ["encounter","ocean_encounter066","defeat"]:
			receipt.status="INTERRUPTED";receipt.event=event
			return check(false,"Actual encounter/loss interrupted the voyage; no arrival or win is substituted")
	return true

func finish_course() -> bool:
	for _piece in range(400):
		if c.state.path.is_empty():return true
		if not advance(4.0):return false
	return check(false,"Physical course exceeded its bounded movement loop")

func gate(region: String,approach: String) -> bool:
	var plotted: Dictionary=c.approach_course064(region,approach)
	if not check(plotted.get("ok",false),"Actual approach course: "+str(plotted.get("message",""))):return false
	if not finish_course():return false
	var crossed: Dictionary=c.transition064(region,approach)
	return check(crossed.get("ok",false),"Actual paired chart crossing: "+str(crossed.get("message","")))

func parsed_save() -> Dictionary:
	var directory: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	var path: String=directory.path_join("sector069-private-voyage.json")
	var file=FileAccess.open(path,FileAccess.WRITE)
	if not check(file!=null,"Private actual save file opens"):return {}
	file.store_string(JSON.stringify(c.state));file.close()
	var saved=JSON.parse_string(FileAccess.get_file_as_string(path))
	return saved if check(saved is Dictionary,"Actual private save parses") else {}

func survey(site: Dictionary,action: String) -> bool:
	var kits: float=c.Remote067.kits(c.state)
	var coins: int=int(c.state.coins)
	var crew: float=c.state.fleet.reduce(func(total,boat):return total+float(boat.crew),0.0)
	var begun: Dictionary=c.begin_survey(str(site.id),action)
	if not check(begun.get("ok",false),"Actual generated paid "+action+": "+str(begun.get("message",""))):return false
	check(is_equal_approx(c.Remote067.kits(c.state),kits-float(begun.supplies)),"Finite kits debited once")
	var frozen: PackedByteArray=protected_state()
	check(not c.chart_course(c.state.position).get("ok",false) and not c.remote_trade068("food",1,"buy").get("ok",false) and protected_state()==frozen,"Deployed party blocks sailing/trade without altering accounts")
	for _piece in range(40):
		if c.state.exploration.assignment.is_empty():break
		if not advance(minf(4.0,maxf(0.001,(float(c.state.exploration.assignment.daysTotal)-float(c.state.exploration.assignment.daysDone))*45.0))):return false
	if not check(c.state.exploration.assignment.is_empty(),"Actual paid generated party completed"):return false
	check(c.state.fleet.all(func(b):return int(b.get("shoreCrew",0))==0) and is_zero_approx(float(c.state.surveyFoodCredit)),"Completion returns the same sailors and unused prepaid rations once")
	check(is_equal_approx(c.state.fleet.reduce(func(total,boat):return total+float(boat.crew),0.0),crew) and int(c.state.coins)<coins,"Survey creates no crew; normal payroll really ran")
	return true

func generated() -> bool:
	phase("fresh_world_and_public_knowledge")
	var world=c.world_view064()
	check(world.get("regions",[]).size()==48 and c.state.sector069.regionOrder.size()==48,"One world view supplies all48 geometry")
	check(c.state.sector069.harbors.size()==19 and c.state.sector069.sites.size()==46,"Canonical generated services and paid landings exist")
	check(c.state.sector069.openingLedger.totals.workers==280 and c.state.sector069.openingLedger.totals.coins==980000,"Explicit finite opening workers/coins")
	var opening_goods_match: bool=c.state.sector069.openingLedger.harbors.size()==19
	for row in c.state.sector069.openingLedger.harbors:
		var port: Dictionary=c.port(str(row.portId))
		for key in ["stocks","publicStores"]:
			var expected: Dictionary=row.allocation[key]
			var actual=port.get(key)
			if not actual is Dictionary or actual.size()!=expected.size():opening_goods_match=false;continue
			for good in expected:
				var amount=actual.get(good)
				if not (amount is int or amount is float) or not is_finite(float(amount)) or amount!=expected[good]:opening_goods_match=false
	check(opening_goods_match,"All19 initialized harbors retain exactly the ledger goods and key sets")
	check(int(c.state.coins)==int(c.data.START.coins) and c.state.fleet.size()==1,"World creation adds no player grant or new boat")
	var first: Dictionary=c.port("settled_01_harbor_01")
	var second: Dictionary=c.port("settled_01_harbor_02")
	check(first.faction=="compact" and second.faction=="reed" and first.islandId!=second.islandId and first.specialty!=second.specialty and first.stocks[first.specialty]>0 and second.stocks[second.specialty]>0,"Two actual mixed-faction islands/markets have complementary finite goods")
	var frozen: PackedByteArray=protected_state()
	var overlay: Dictionary=c.sector_view069()
	var mixed: Dictionary={}
	for group in overlay.groups:
		if group.regionId=="settled_01":mixed=group
	var segments: Array=mixed.get("segments",[])
	check(mixed.get("ownershipSummary")=="mixed" and segments.any(func(s):return s.factionId=="compact" and s.knownAssets>=2) and segments.any(func(s):return s.factionId=="reed" and s.knownAssets>=2),"Public settled chart shows both real factions; separately known neutral islands retain their own segment")
	for group in overlay.groups:
		if group.band=="remote":check(group.knowledge=="unknown" and group.ownershipSummary=="unknown" and group.segments.is_empty(),"Unknown remote holdings stay unknown")
	if not overlay.ports.is_empty():overlay.ports[0].name="detached mutation"
	check(protected_state()==frozen,"Overlay is detached, read-only and has no geography duplication")
	check(not c.ShippingFlow068.install_sector069(c,c.state.sector069).get("ok",false) and protected_state()==frozen,"Repeat sector installation cannot mint or refill")
	var boat: Dictionary=c.state.fleet[0]
	var hire: int=maxi(0,int(boat.crewMin)+4-int(boat.crew))
	if hire>0 and not check(c.recruit_crew(str(boat.uid),hire).get("ok",false),"Normal paid hires reserve four spare hands"):return false
	var owned: String=str(boat.uid)
	phase("earned_generated_crossing")
	if not gate("shatter_coast","south") or not gate("settled_01","north"):return false
	if not check(c.world_location064().world064.regionId=="settled_01" and c.current_port().is_empty(),"Same physical fleet enters generated local chart without HOME services"):return false
	var plotted: Dictionary=c.chart_course({"x":first.x,"y":first.y},str(first.id))
	if not check(plotted.get("ok",false),"Canonical known generated berth plots") or not finish_course() or not advance(0.5):return false
	var landing: Dictionary={}
	for row in c.state.sector069.sites:
		if row.regionId=="settled_01":landing=row;break
	phase("finite_generated_trade_and_paid_findings")
	first=c.port("settled_01_harbor_01")
	var stock: float=float(first.stocks.food)
	var food: float=float(c.state.cargo.food)
	var purse: int=int(c.state.coins)
	var bought: Dictionary=c.remote_trade068("food",1,"buy",str(first.id))
	receipt.trades.append(bought)
	if not check(bought.get("ok",false),"Finite actual generated harbor trade: "+str(bought.get("message",""))):return false
	check(is_equal_approx(float(first.stocks.food),stock-1) and is_equal_approx(float(c.state.cargo.food),food+1) and int(c.state.coins)==purse-int(bought.total),"Trade debits the one live stock and transfers actual coins")
	frozen=protected_state()
	check(not c.remote_trade068("food",1,"buy",str(second.id)).get("ok",false) and protected_state()==frozen,"A different island berth cannot trade through local proximity alone")
	if c.distance(c.state.position,landing)>180:
		if not check(c.chart_course({"x":landing.x,"y":landing.y}).get("ok",false),"Actual survey landing course") or not finish_course() or not advance(0.5):return false
	var sighted: Array=c.exploration_view067().sites
	check(not sighted.is_empty() and not sighted[0].has("resource") and not sighted[0].has("discovery"),"Resource findings are absent before paid survey")
	if not survey(landing,"chart") or not survey(landing,"survey"):return false
	var findings: Array=c.exploration_view067().sites
	check(findings.size()==1 and findings[0].level==3 and findings[0].resource==landing.resource and findings[0].discovery==landing.discovery,"Actual paid survey reveals useful canonical resource/hazard findings")
	frozen=protected_state()
	check(not c.begin_survey(str(landing.id),"survey").get("ok",false) and protected_state()==frozen,"Survey finding cannot be paid/rewarded twice")
	check(not c.state.wreckSeededSources.has(c.Remote067.SOURCE),"Generated findings grant no Glasswind cache or cargo")
	phase("earned_home_return_and_parsed_restore")
	frozen=protected_state()
	var return_quote: Dictionary=c.VoyageCosts065.quote(c.state,c.data,c.ocean_context064,
		{"targetRegionId":"shatter_coast","targetApproachId":"south","outExit":"north","backExit":"","homeEntry":"","returnPortId":"brass_haven","idleDays":0.0},
		{"speed":c.travel_speed(),"clearance":c.Routes.clearance(c),"blocker":c.transition_blocker064()})
	if not check(return_quote.get("ok",false) and protected_state()==frozen,"Direct generated return quote preserves live navigation and all accounts: "+str(return_quote.get("message",""))):return false
	if not gate("settled_01","north") or not gate("shatter_coast","south"):return false
	var home: Dictionary=c.port("brass_haven")
	if not check(c.chart_course({"x":home.x,"y":home.y},str(home.id)).get("ok",false),"Actual home harbor return course") or not finish_course():return false
	check(c.current_port().get("id")=="brass_haven" and c.state.fleet[0].uid==owned and int(c.state.wageArrears)==0,"Same original boat returns on actual starting funds with wages paid")
	check(same_values(c.port("westglass_anchorage").get("training"),{"schema":1,"nextId":0,"qualified":{"sailor":0,"gunner":0,"mechanic":0,"boarder":0},"jobs":[]}),"Funded Westglass branch has an empty training book with no qualified crew or escrow before save")
	var saved: Dictionary=parsed_save()
	if saved.is_empty():return false
	var expected: Dictionary=expected_restore_values(saved,supply)
	if not check(c.restore(saved).get("ok",false),"Actual parsed generated career restores"):return false
	check(compare_restore(expected),"Restore keeps exact saved geography, physical harbor/merchant accounts and supply; reserve forecasts match canonical recalculation")
	for kind in ["ledger","missing_port","missing_site","null_sector"]:
		if not bounded():return false
		var bad: Dictionary=JSON.parse_string(JSON.stringify(saved))
		if kind=="ledger":bad.sector069.openingLedger.harbors[0].allocation.cash+=1
		elif kind=="missing_port":bad.ports=bad.ports.filter(func(p):return p.id!="settled_01_harbor_01")
		elif kind=="missing_site":bad.exploration.catalog=bad.exploration.catalog.filter(func(s):return s.id!="settled_01_survey")
		else:bad.sector069=null
		frozen=protected_state()
		var input: PackedByteArray=var_to_bytes(bad)
		check(not c.restore(bad).get("ok",false) and protected_state()==frozen and var_to_bytes(bad)==input,"Corrupt present "+kind+" refuses before live/input/context publication")
	return failures==0

func legacy() -> bool:
	phase("controlled_legacy068_retention")
	var old: Dictionary=c.state.duplicate(true)
	if not check(int(old.coinSupply)==supply and c.Money.total(old)==supply,"After-trade source supply conserves before constructed legacy staging"):return false
	var generated_ids: Array=old.sector069.sites.map(func(s):return str(s.id))
	var generated_ports: Array=old.sector069.harbors.map(func(p):return str(p.id))
	var removed_coins: int=0
	for port in old.ports:
		if str(port.id) in generated_ports:removed_coins+=c.Money.port_total(port)
	old.ports=old.ports.filter(func(p):return str(p.id) not in generated_ports)
	old.coinSupply=int(old.coinSupply)-removed_coins
	old.shipping068.receipts=old.shipping068.receipts.filter(func(row):return str(row.portId) not in generated_ports)
	old.exploration.catalog=old.exploration.catalog.filter(func(s):return str(s.id) not in generated_ids)
	for id in generated_ids:old.exploration.sites.erase(id)
	old.exploration.leads=old.exploration.leads.filter(func(row):return row.get("fromSite","") not in generated_ids and row.get("toSite","") not in generated_ids)
	for key in ["sector069","sectorApplied069","sectorKnowledge069","islandOwnership069"]:old.erase(key)
	if not check(c.Money.total(old)==int(old.coinSupply),"Constructed legacy subtracts exact current removed purses without rebasing supply"):return false
	var accounts: Array=expected_restore_ports(old)
	var physical: Dictionary=merchant()
	if not check(c.restore(old).get("ok",false),"Constructed finite068-compatible absent-sector save restores"):return false
	supply=int(c.state.coinSupply)
	check(not c.state.has("sector069") and c.world_view064().regions.size()==2 and same_values(c.state.ports,accounts) and same_values(merchant(),physical),"Legacy keeps exactly two regions and unchanged old accounts/merchant")
	receipt.controlled.append("Constructed compatibility staging removes exact generated ports' CURRENT purses (%d coins), their shipping receipts and generated site rows; actual old accounts/merchant/party/cache remain. No owner save is touched; old landing/cache setup is controlled provenance testing, not an earned voyage." % removed_coins)
	var site: Dictionary=c.Exploration.catalog_site(c.state,"glasswind_west_marker")
	var location: Dictionary={"world064":{"schema":1,"layer":"local","regionId":"glasswind_keys"},"position":{"x":site.x,"y":site.y},"heading":0.0,"path":[],"destination":""}
	var valid: Dictionary=c.OceanWorld064.prepare(location,c.ocean_context064,c.Routes.clearance(c))
	if not check(valid.get("ok",false),"Controlled old067 landing is canonical safe water"):return false
	c._publish_location064(valid.location);c.Exploration.discover_near(c.state,c.state.position,620.0)
	if not check(c.begin_survey(str(site.id),"chart").get("ok",false),"Old067 party reserves actual hands/kits"):return false
	var hands: Array=c.state.fleet.map(func(b):return int(b.get("shoreCrew",0)))
	var party_save: Dictionary=parsed_save()
	if party_save.is_empty():return false
	var party: Dictionary=party_save.exploration.assignment.duplicate(true)
	physical=merchant(party_save)
	if not check(c.restore(party_save).get("ok",false),"Absent-sector active shore party restores"):return false
	check(same_values(c.state.exploration.assignment,party) and c.state.fleet.map(func(b):return int(b.get("shoreCrew",0)))==hands and same_values(merchant(),physical),"Old party and original merchant survive without recall/respawn")
	if not check(c.recall_survey().get("ok",false),"Actual old party recall returns only unused rations"):return false
	for id in c.Remote067.SITE_IDS:c.state.exploration.sites[id]={"level":3,"rewarded":true}
	var cache: Dictionary=c.Salvage.seed_expedition067(c,c.Exploration.catalog_site(c.state,"glasswind_south_wreck"))
	if not check(not cache.is_empty(),"Controlled old survey preconditions reveal one canonical cache"):return false
	var id: String=str(cache.id)
	c.Remote067.raw_wreck(c.state,id).stores.copper-=1.0
	var stores: Dictionary=c.Remote067.raw_wreck(c.state,id).stores.duplicate(true)
	var cache_save: Dictionary=parsed_save()
	if cache_save.is_empty():return false
	for wreck in cache_save.get("wrecks",[]):
		if wreck.id==id:stores=wreck.stores.duplicate(true);break
	physical=merchant(cache_save)
	if not check(c.restore(cache_save).get("ok",false),"Depleted old cache restores on the two-region world"):return false
	c.Salvage.seed_expedition067(c,c.Exploration.catalog_site(c.state,"glasswind_south_wreck"))
	check(same_values(c.Remote067.raw_wreck(c.state,id).stores,stores) and same_values(merchant(),physical) and c.Money.total(c.state)==supply,"Old cache stays depleted and merchant/account supply stays exact")
	return failures==0

func _run() -> void:
	var options: Dictionary={}
	for argument in OS.get_cmdline_user_args():
		for name in ["restore-checkpoint","checkpoint-sha256"]:
			if argument.begins_with("--"+name):options[name]=argument.trim_prefix("--"+name+"=")
	if not options.is_empty():checkpoint_diagnostic(options);finish();return
	if not check(OS.get_environment("GAME_TEST_ARTIFACTS").is_absolute_path(),"Root supplies a private artifact/profile directory"):finish();return
	var world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c=Campaign.new(world)
	var made: Dictionary=c.new_game(69069)
	if not check(made.get("ok",false),"Actual fresh campaign: "+str(made.get("message",""))):finish();return
	supply=int(c.state.coinSupply)
	if generated() and bounded() and legacy():receipt.status="COMPLETED"
	finish()

func finish() -> void:
	if workers.group_id>=0:workers.finish(true)
	c=null
	var elapsed: int=Time.get_ticks_msec()-started
	check(elapsed<BODY_LIMIT_MS,"Whole fixture body and owned worker cleanup remain under55seconds")
	receipt.checks=checks;receipt.failures=failures;receipt.elapsedMs=elapsed;receipt.sourceCandidate=not receipt.get("diagnosticOnly",false)
	print("SECTOR069_RESULT ",JSON.stringify(receipt))
	print("%d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
