extends SceneTree
## SOURCE FIXTURE, UNRUN. Root owns the shared native lane.
## One current Core, actual courses/transfers and normal copied-port day jobs.
## Controlled refusal/loss branches restore detached fixtures afterwards; they
## do not assert earned combat, passenger work or a whole-game quality outcome.
const Campaign=preload("res://scripts/campaign.gd")
const Workers=preload("res://scripts/economy_workers.gd")
const Money=preload("res://scripts/money.gd")
var c
var workers=Workers.new()
var checks: int=0
var failures: int=0
var started: int=0
var paid_days: int=0
var baseline: Dictionary={}

func check(ok: bool,message: String) -> bool:
	checks+=1
	if not ok:failures+=1;print("FAIL ocean064: ",message)
	return ok

func same(a,b) -> bool:
	if (a is int or a is float) and (b is int or b is float):return a==b
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for index in range(a.size()):
			if not same(a[index],b[index]):return false
		return true
	return a==b

func field_value(value) -> String:
	var detail: String
	if value is Dictionary or value is Array:detail="size=%d"%value.size()
	else:detail=var_to_str(value).left(160)
	return "%s(%s)"%[type_string(typeof(value)),detail]

func field_differences(actual,expected,path: String,rows: Array) -> void:
	if rows.size()>=12:return
	if actual is Dictionary and expected is Dictionary:
		for key in actual:
			if rows.size()>=12:return
			var child: String=path+"."+str(key)
			if not expected.has(key):rows.append(child+": actual="+field_value(actual[key])+"; expected=<missing>")
			else:field_differences(actual[key],expected[key],child,rows)
		for key in expected:
			if rows.size()>=12:return
			if not actual.has(key):rows.append(path+"."+str(key)+": actual=<missing>; expected="+field_value(expected[key]))
		return
	if actual is Array and expected is Array:
		if actual.size()!=expected.size():rows.append(path+".size: actual=%d; expected=%d"%[actual.size(),expected.size()])
		for index in range(mini(actual.size(),expected.size())):
			if rows.size()>=12:return
			field_differences(actual[index],expected[index],path+"[%d]"%index,rows)
		return
	if not same(actual,expected):rows.append(path+": actual="+field_value(actual)+"; expected="+field_value(expected))

func check_same(actual,expected,message: String) -> bool:
	var equal: bool=same(actual,expected)
	if not check(equal,message):
		var rows: Array=[]
		field_differences(actual,expected,"$",rows)
		for row in rows:print("DIFF ocean064: ",message," | ",row)
	return equal

func parsed(value) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func nonspatial() -> Dictionary:
	var copy: Dictionary=c.state.duplicate(true)
	for key in ["world064","position","heading","path","destination"]:copy.erase(key)
	return copy

func custody(saved: Dictionary) -> Dictionary:
	var boats: Array=[]
	for boat in saved.fleet:
		var row: Dictionary={}
		for key in ["uid","type","crew","wounded","hp","water","fire","engine","fuel","ammo","supplies","moduleCondition","loadout","refitLocker"]:
			if boat.has(key):row[key]=boat[key].duplicate(true) if boat[key] is Array or boat[key] is Dictionary else boat[key]
		boats.append(row)
	var owners: Array=[]
	for owner in saved.fleetOwners:
		var physical: Array=[]
		for boat in owner.boats:
			var record: Dictionary={}
			for key in ["uid","type","crew","wounded","hp","fuel","ammo","supplies","moduleCondition"]:
				if boat.has(key):record[key]=boat[key].duplicate(true) if boat[key] is Array or boat[key] is Dictionary else boat[key]
			physical.append(record)
		owners.append({"id":owner.id,"coins":owner.coins,"crewPurse":owner.crewPurse,"wageArrears":owner.wageArrears,"cargo":owner.cargo.duplicate(true),"boats":physical})
	return {"owners":owners,"coins":saved.coins,"crewPurse":saved.crewPurse,"wageArrears":saved.wageArrears,"debt":saved.debt,"cargo":saved.cargo.duplicate(true),"coinSupply":saved.coinSupply,"boats":boats,"ports":saved.ports.duplicate(true)}

func sync_days() -> void:
	while c.pending_days>0:
		c.pending_days-=1
		var prior: int=int(c.state.econDay)
		workers.start(c.state.ports,1,c.TradeFlow.blockades(c),int(c.state.seed)+prior*104729)
		var completed: Dictionary=workers.finish(true)
		c.apply_economy(completed.ports,completed.events,completed.days)
		paid_days+=1
		check(int(c.state.econDay)==prior+1,"One copied-port publication advances one economy day")
		check(Money.total(c.state)==int(c.state.coinSupply),"Actual daily payroll and home economy conserve global coins")

func sail(region: String,approach: String) -> bool:
	var course: Dictionary=c.approach_course064(region,approach)
	if not check(bool(course.ok),"Actual approach course accepted: "+str(course.message)):return false
	return finish_course()

func finish_course() -> bool:
	for _piece in range(160):
		if c.state.path.is_empty():return true
		if Time.get_ticks_msec()-started>=55000:return check(false,"One bounded voyage fixture exceeded55 seconds")
		var length: float=0.0
		var previous: Dictionary=c.state.position
		for point in c.state.path:length+=c.distance(previous,point);previous=point
		var scale_units: float=10.0 if c.state.world064.layer=="ocean" else 1.0
		var dt: float=minf(4.0,maxf(0.001,length*scale_units/maxf(0.01,c.travel_speed())))
		var before: float=float(c.state.day)
		c.step(dt)
		check(is_equal_approx(float(c.state.day)-before,dt/c.DAY_SECONDS),"Sailing uses exactly the existing campaign clock")
		sync_days()
		for event in c.pop_events():
			if event.get("kind","") in ["encounter","defeat"]:return check(false,"Real voyage interrupted by encounter/loss; never counted as arrival")
	return check(false,"Course completes within160 bounded movement chunks")

func cross(region: String,approach: String) -> bool:
	var accounts: Dictionary=nonspatial()
	var location: Dictionary=c.world_location064()
	var pending: int=c.pending_days
	var result: Dictionary=c.transition064(region,approach)
	if not check(bool(result.ok),"Actual transfer accepted: "+str(result.message)):return false
	check(same(nonspatial(),accounts) and c.pending_days==pending,"Transfer changes no clock, accounts, stores, grace, crew or NPC state")
	check(float(c.state.heading)==float(location.heading),"Transfer preserves the actual heading")
	check(c.state.path.is_empty() and c.state.destination.is_empty(),"Only active course intent clears on transfer")
	return true

func roundtrip(label: String) -> void:
	var save: Dictionary=parsed(c.state)
	var restore: Dictionary=c.restore(save)
	check(bool(restore.ok),label+": real Core.restore accepts JSON: "+str(restore.message))
	check_same(c.world_location064(),{"world064":save.world064,"position":save.position,"heading":save.heading,"path":save.path,"destination":save.destination},label+": exact parsed spatial record survives restore")
	check_same(custody(c.state),custody(save),label+": exact parsed boats, crew, stores, purses and ports survive restore")
	check(Money.total(c.state)==int(save.coinSupply),label+": original coin supply remains conserved")

func refusal_cases() -> void:
	var anchor: Dictionary=c.state.duplicate(true)
	# The real fixture is stopped at home north approach. A hostile physical
	# patrol is placed in direct contact even though initial grace is positive.
	var patrol: Dictionary=c.state.patrols[0]
	var owner: Dictionary=c.fleet_owner(str(patrol.id))
	check(c.Politics.hostile(c,owner),"Controlled direct-contact actor uses the existing hostile predicate")
	patrol.x=c.state.position.x;patrol.y=c.state.position.y
	var before: PackedByteArray=var_to_bytes(c.state)
	check(not c.transition064("shatter_coast","north").ok,"Direct hostile contact blocks departure even during grace")
	check(var_to_bytes(c.state)==before,"Blocked direct contact does not erase pursuit, move or refill anything")
	c.state=anchor.duplicate(true)
	owner=c.fleet_owner(str(patrol.id));patrol=c.state.patrols[0]
	owner.atPort="";owner.order.targetOwnerId="player";owner.order.purpose="intercept"
	check(not c.transition064("shatter_coast","north").ok,"Currently live armed hostile pursuit blocks departure beyond direct contact")
	c.state=anchor.duplicate(true)
	for kind in ["shore","tooling","gear","charter","cohort","overload","battle","pending"]:
		if kind=="shore":c.state.exploration.assignment={"siteId":"controlled"}
		elif kind=="tooling":c.state.toolingRecovery={"siteId":"controlled"}
		elif kind=="gear":
			var work: Dictionary=c.CivilianWork.ensure(c)
			work.fishing=[{"boatUid":str(c.state.fleet[0].uid)}]
		elif kind=="charter":c.state.voyageJobs=[{"kind":"passenger_charter","passengers":{"n":1}}]
		elif kind=="cohort":c.state.regionalCrises.jobs=[{"id":"controlled-cohort","stage":"outward","n":1,"food":{}}]
		elif kind=="overload":c.state.cargo.food=c.capacity()+100.0
		elif kind=="battle":c.travel_lock064="Controlled unresolved battle"
		elif kind=="pending":c.events=[{"kind":"encounter","patrol":"patrol-0"}]
		before=var_to_bytes(c.state)
		check(not c.transition064("shatter_coast","north").ok,"Transfer refuses controlled "+kind)
		check(var_to_bytes(c.state)==before,"Refused "+kind+" leaves all saved state intact")
		c.state=anchor.duplicate(true);c.events=[];c.travel_lock064=""
	check(not c.transition064("shatter_coast","south").ok,"The opposite coast side is not a teleport")
	check(not c.transition064("glasswind_keys","north").ok,"A local departure belongs to its actual region")
	# Controlled safe off-center point inside the actual approach, to prove
	# projection preserves the exact position rather than snapping to its center.
	c.state.position.x+=13.0
	var offset: Dictionary=c.state.position.duplicate(true)
	var account_before: Dictionary=nonspatial()
	check(c.transition064("shatter_coast","north").ok,"Safe off-center departure succeeds")
	check(is_equal_approx(float(c.state.position.x),700.0+float(offset.x)/10.0) and is_equal_approx(float(c.state.position.y),1100.0+float(offset.y)/10.0),"Exact off-center projection never snaps to the approach center")
	check(c.transition064("shatter_coast","north").ok and is_equal_approx(float(c.state.position.x),float(offset.x)) and is_equal_approx(float(c.state.position.y),float(offset.y)),"Inverse transfer preserves that actual off-center location")
	check(same(nonspatial(),account_before),"Immediate off-center round trip leaves every nonspatial field exact")
	c.state=anchor

func locality_and_provenance() -> void:
	var live: Dictionary=c.state.duplicate(true)
	# Intentional coordinate overlap tests only; no earned voyage or valid
	# remote navigation is claimed for these independently controlled branches.
	c.state.position=c.port_position("kelp_reach")
	check(c.current_port().is_empty(),"Remote coordinates overlapping a home harbor never dock")
	check(not c.LawOps.near(c,c.port("kelp_reach")),"Remote coordinates never trigger home customs")
	check(not c.chart_course(c.port_position("kelp_reach"),"kelp_reach").ok,"Remote course cannot name a home harbor")
	var site: Dictionary=c.state.exploration.catalog[0]
	c.state.position={"x":site.x,"y":site.y}
	check(not c.begin_survey(str(site.id),"chart").ok,"Remote overlap cannot start home shore work")
	check(not c.ToolingOps.offer(c,"cinder_workshop_ruin","machine_tools").ok,"Remote overlap cannot seed home machinery wrecks")
	check(not c.CivilianWork.start_fishing(c,str(c.state.fleet[0].uid)).ok,"Remote waters cannot mint home fishing catch")
	c.state=live.duplicate(true)
	var paid_before: int=paid_days
	var npc_before: Dictionary=c.state.patrols[1].duplicate(true)
	var work_before: float=float(c.state.fleetOwners[1].get("daysOperated",0))
	var fuel_before: float=float(c.state.fleet[0].fuel)
	var coins_before: int=int(c.state.coins)
	var food_before: float=float(c.state.cargo.food)
	var grace_before: float=float(c.state.encounterGrace)
	c.step(c.DAY_SECONDS);sync_days();c.pop_events()
	check(paid_days==paid_before+1,"One stationary remote day pays one ordinary day")
	check(float(c.state.fleet[0].fuel)==fuel_before,"Idle remote time does not charge sailing fuel")
	check(int(c.state.coins)<coins_before and float(c.state.cargo.food)<food_before,"Remote time pays actual wages and consumes carried rations")
	check(float(c.state.encounterGrace)<=grace_before,"Remote time cannot replenish encounter grace")
	check(not same(c.state.patrols[1],npc_before) or float(c.state.fleetOwners[1].get("daysOperated",0))>work_before,"Home NPC navigation or paid operation continues offshore")
	check(c.current_port().is_empty(),"Remote day settlement never replaces ports with a docking facade")
	check(c.state.ports.size()==10,"All ten original home economic accounts remain present")
	var cargo_before: float=float(c.state.cargo.food)
	check(c.jettison("food",1).ok,"Remote jettison removes a finite owned lot")
	var wreck_id: String=str(c.state.wrecks[-1].id)
	var remote: Dictionary=c.Salvage.find_wreck(c.state,wreck_id)
	check(remote.get("world064",{})==c.state.world064 and float(c.state.cargo.food)==cargo_before-1.0,"Normal lookup retains the jettison's actual world provenance and cargo debit")
	roundtrip("Remote jettison")
	var after: Dictionary=c.Salvage.find_wreck(c.state,wreck_id)
	check_same(after.get("world064"),remote.get("world064"),"JSON restore and repeated lookup retain remote provenance")
	var after_voyage: Dictionary=c.state.duplicate(true)
	# Unmarked NPC battle: actual existing NPC hull/equipment, declared sunk
	# solely to check loss-record origin while the captain remains offshore.
	var npc: Dictionary=c.fleet_owner("patrol-0").boats[0]
	npc.sunk=true;npc.hp=0.0
	var npc_wrecks: Array=c.Salvage.record_battle(c,{"ships":[npc],"chartPosition":c.port_position("kelp_reach")},"ocean064-controlled-home-npc")
	check(not npc_wrecks.is_empty(),"Existing home NPC battle records its actual physical equipment offshore")
	if not npc_wrecks.is_empty():
		check(c.Expedition.home_local064(c.Salvage.find_wreck(c.state,str(npc_wrecks[0].id))),"Unmarked NPC battle origin defaults home, independent of player layer")
	var explicit: Dictionary=c.fleet_owner("patrol-1").boats[0]
	explicit.sunk=true;explicit.hp=0.0
	var explicit_wrecks: Array=c.Salvage.record_battle(c,{"ships":[explicit],"chartPosition":c.state.position,"world064":c.state.world064.duplicate(true)},"ocean064-controlled-explicit-local")
	check(not explicit_wrecks.is_empty(),"Explicit off-home loss creates a retained finite physical wreck")
	if not explicit_wrecks.is_empty():
		var marked: Dictionary=c.Salvage.find_wreck(c.state,str(explicit_wrecks[0].id))
		check(marked.get("world064",{})==c.state.world064 and not c.Expedition.home_local064(marked),"Explicit encounter identity survives ordinary loss lookup")
	# Direct home recovery must refuse the remote ID, even at identical numbers.
	c.state.world064={"schema":1,"layer":"home","regionId":"shatter_coast"}
	c.state.position={"x":remote.x,"y":remote.y}
	var no_recovery_change: Dictionary=custody(c.state)
	var wrong_quote: Dictionary=c.recovery_quote(wreck_id,"strip")
	var wrong_action: Dictionary=c.recover_wreck(wreck_id,"strip")
	check(not wrong_quote.ok and not wrong_action.ok and "another chart" in str(wrong_quote.message) and "another chart" in str(wrong_action.message),"Core directly refuses wrong-region wreck IDs for their actual provenance")
	check(same(custody(c.state),no_recovery_change),"Wrong-region recovery moves no goods, physical parts, wages or purse")
	var raw: Dictionary=remote.duplicate(true);raw.world064=null
	c.state.wrecks.append(raw.merged({"id":"wreck-invalid064"},true))
	var invalid: Dictionary=c.Salvage.find_wreck(c.state,"wreck-invalid064")
	check(not c.Expedition.home_local064(invalid),"Malformed present wreck metadata cannot normalize into a home recovery")
	c.state=after_voyage

func bad_restore_cases() -> void:
	var save: Dictionary=parsed(c.state)
	for kind in ["null","empty","pair","schema","bounds","route","destination","homeAccounts"]:
		var bad: Dictionary=save.duplicate(true)
		if kind=="null":bad.world064=null
		elif kind=="empty":bad.world064={}
		elif kind=="pair":bad.world064={"schema":1,"layer":"local","regionId":"shatter_coast"}
		elif kind=="schema":bad.world064.schema=true
		elif kind=="bounds":bad.position={"x":4801.0,"y":200.0}
		elif kind=="route":bad.path=[{"x":3510.0,"y":-1.0}]
		elif kind=="destination":bad.destination="approach:glasswind_keys:west"
		elif kind=="homeAccounts":bad.ports[0].x=10401.0
		var before: PackedByteArray=var_to_bytes(c.state)
		check(not c.restore(bad).ok,"Real restore refuses malformed "+kind)
		check(var_to_bytes(c.state)==before,"Refused "+kind+" never publishes or relocates the current voyage")

func voyage() -> void:
	var legacy: Dictionary=parsed(baseline);legacy.erase("world064")
	check(c.restore(legacy).ok,"Existing map2 save without world field restores through legacy home path")
	check(c.home_local064() and c.state.position==legacy.position,"Legacy home location remains at its actual harbor")
	var restored_view: Dictionary=c.world_view064()
	var view_error: String="" if not restored_view.is_empty() else str(c._world_view_result064().get("message","World view failed."))
	if not check(not restored_view.is_empty(),"Real restored active fleet produces a nonempty plain-data world view: "+view_error):return
	var owned: Array=c.state.fleet.map(func(b):return str(b.uid))
	var starting_fuel: float=float(c.state.fleet[0].fuel)
	if not sail("shatter_coast","north"):return
	refusal_cases()
	if not cross("shatter_coast","north"):return
	var course: Dictionary=c.approach_course064("glasswind_keys","south")
	if not check(course.ok,"Core plots an ocean approach before mid-course save"):return
	c.step(5.0);sync_days();c.pop_events()
	check(not c.state.path.is_empty(),"Mid-ocean save retains a real unfinished course")
	roundtrip("Mid-ocean")
	bad_restore_cases()
	if not finish_course() or not cross("glasswind_keys","south"):return
	check(c.world_view064().islands.size()==3,"Entered real remote view has exactly its three authored islands")
	roundtrip("Glasswind Keys")
	locality_and_provenance()
	if not cross("glasswind_keys","south"):return
	if not sail("shatter_coast","north") or not cross("shatter_coast","north"):return
	var home: Dictionary=c.chart_course(c.port_position("brass_haven"),"brass_haven")
	if not check(home.ok,"Return home uses the existing harbor route"):return
	if not finish_course():return
	check(c.current_port().get("id","")=="brass_haven","Actual round trip returns to the original home harbor")
	check(c.state.fleet.map(func(b):return str(b.uid))==owned,"Actual voyage returns with the original owned hull UIDs")
	check(float(c.state.fleet[0].fuel)<starting_fuel,"Actual ocean/local sailing consumes real working fuel")
	check(paid_days>0,"The real voyage pays ordinary upkeep during elapsed travel")
	roundtrip("Returned home")

func _initialize() -> void:
	started=Time.get_ticks_msec()
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c=Campaign.new(world)
	var birth: Dictionary=c.new_game(64064)
	if check(birth.ok,"One current canonical career starts"):
		baseline=c.state.duplicate(true)
		if check(not c.ocean_context064.is_empty(),"A's actual world module created with shared home navigation"):voyage()
	workers.finish(true)
	print("ocean064: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
