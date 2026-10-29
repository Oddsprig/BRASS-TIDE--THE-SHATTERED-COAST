extends SceneTree
## Source-only handoff fixture; Root alone executes it in the shared lane.
## Controlled endpoint/clock staging exercises model boundaries, not an earned
## crossing, funded branch installation, combat win or whole-game acceptance.
const Shipping = preload("res://scripts/shipping068.gd")
const Travel = preload("res://scripts/ocean_travel066.gd")
const OceanCampaign = preload("res://scripts/ocean_campaign066.gd")
const World = preload("res://scripts/ocean_world064.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Economy = preload("res://scripts/economy.gd")
const Fleets = preload("res://scripts/fleet_economy.gd")
const Orders = preload("res://scripts/naval_orders.gd")
const NavalAI = preload("res://scripts/naval_ai.gd")
const Money = preload("res://scripts/money.gd")
const Jobs = preload("res://scripts/voyage_jobs.gd")

class LedgerCore:
	extends RefCounted
	var state: Dictionary = {}
	var ocean_context064: Dictionary = {}
	func world_location064() -> Dictionary:
		return {"world064":state.world064,"position":state.position,"heading":0.0,"path":[],"destination":""}

var checks: int = 0
var failures: int = 0
var core: LedgerCore
var context: Dictionary = {}
var owner: Dictionary = {}
var origin: Dictionary = {}
var remote: Dictionary = {}
var patrol: Dictionary = {}
var world: Dictionary = {}
var book: Dictionary = {}
var started: int = 0


func check(value: bool, message: String) -> bool:
	checks+=1
	if not value:failures+=1;print("FAIL shipping068: ",message)
	return value


func _initialize() -> void:
	started=Time.get_ticks_msec()
	world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var atlas: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/ocean_regions064.json"))
	var nav: Dictionary=Navigation.create(world.ISLANDS,world.WORLD.width,world.WORLD.height,40.0*float(world.CAMPAIGN_SCALE))
	var made: Dictionary=World.create(world,atlas,nav)
	if not check(made.get("ok",false),"Actual two-region geometry creates once"):
		finish();return
	context=made.context
	var geometry_before: PackedByteArray=var_to_bytes(context)
	var ports: Array=[]
	for definition in world.PORTS:ports.append(Economy.create_port(definition))
	var owners: Array=Fleets.create_owners(ports,world)
	core=LedgerCore.new();core.ocean_context064=context
	core.state={"day":1.0,"econDay":1,"seed":17,"ports":ports,"fleetOwners":owners,"patrols":[],"fleet":[],"boardingPrizes":[],"moneyLog":[],"world064":{"schema":1,"layer":"home","regionId":World.HOME},"position":{"x":world.PORTS[0].x,"y":world.PORTS[0].y}}
	owner=Orders.find_owner(core.state,Shipping.OWNER);origin=Orders.find_port(core.state,Shipping.ORIGIN)
	if not check(not owner.is_empty() and not origin.is_empty() and owner.kind=="trader","Use the actual existing Kelp trader and its original hulls"):
		finish();return
	remote=Economy.create_port({"id":Shipping.REMOTE_PORT,"name":"Westglass Anchorage","regionId":World.REMOTE,"islandId":"glasswind_west","faction":"reed","industry":"timber","specialty":"logs","x":756.0,"y":732.0,"workforce":8,"population":8})
	# No default port wealth enters this controlled market fixture.
	for key in ["cash","governmentPurse","householdPurse","expertPurse","recruitPurse"]:remote[key]=0
	for good in Economy.GOODS:remote.stocks[good]=0.0;remote.publicStores[good]=0.0
	remote.shipStock={};remote.shipIds=[];remote.buildQueue=[]
	ports.append(remote)
	var berth: Dictionary=Navigation.harbor_approach(nav,origin,20.0)
	if not check(not berth.is_empty(),"The source-defined Kelp berth has a safe controlled staging point"):
		finish();return
	patrol={"id":Shipping.OWNER,"x":berth.x,"y":berth.y,"active":true,"holding":true,"course":[],"from":Shipping.ORIGIN,"to":Shipping.ORIGIN}
	core.state.patrols=[patrol]
	owner.atPort=Shipping.ORIGIN
	Fleets.dock(owner,origin)
	# Sell the previous coastal manifest through the real finite ledger.
	var qty: int=mini(floori(float(owner.tradeCargo)),int(origin.cash)/maxi(1,Economy.price(origin,str(owner.tradeGood),"sell")))
	if qty>0:trade(origin,str(owner.tradeGood),qty,"sell")
	if not check(float(owner.tradeCargo)<1.0,"Prior coastal lot settles through an actual funded market before model tests"):
		finish();return
	owner.harborServiceUntilDay=1.0
	book=Shipping.empty_book()
	legacy_and_admission()
	if failures==0:service_and_loading()
	if failures==0:shared_step()
	if failures==0:delivery_and_return()
	if failures==0:raw_validation()
	if failures==0:one_upkeep()
	if failures==0:controlled_conflict()
	home_destination_filters()
	check(geometry_before==var_to_bytes(context),"All model operations preserve the shared immutable navigation and geometry")
	check(Time.get_ticks_msec()-started<20000,"Bounded model fixture body remains below twenty seconds")
	finish()


func snapshot() -> Dictionary:
	var copy: Dictionary=owner.duplicate(true)
	return {"owner":copy,"patrol":patrol.duplicate(true),"originPort":origin.duplicate(true),"remotePort":remote.duplicate(true),"reserves":Orders.fleet_reserves(copy),"performance":Orders.fleet_performance(copy),"clearance":20.0,"campaignScale":float(world.CAMPAIGN_SCALE)}


func planned(now: float) -> Dictionary:
	var physical: Dictionary=snapshot()
	var before: PackedByteArray=var_to_bytes([book,physical,core.state])
	var result: Dictionary=Shipping.plan(context,book,physical,now)
	check(before==var_to_bytes([book,physical,core.state]),"Plan never publishes accounts, cargo, clock, phase or snapshot mutation")
	check(result.get("ok",false),"Bounded pure shipping plan succeeds: "+str(result.get("message","")))
	return result


func publish(next_book: Dictionary) -> void:
	book=next_book
	core.state.shipping068={"model":book}
	patrol.active=false;patrol.hidden=true;patrol.holding=true;patrol.course=[]
	if book.route.phase in ["outbound","return","lost"]:owner.atPort="";owner.erase("harborServiceUntilDay")
	else:owner.atPort=Shipping.ORIGIN if book.route.phase=="home_service" else Shipping.REMOTE_PORT


func legacy_and_admission() -> void:
	check(Shipping.prepare({},context).book==Shipping.empty_book(),"Absent legacy model remains safe and unenrolled")
	var pending: Dictionary=snapshot();pending.owner.atPort=""
	check(Shipping.plan(context,book,pending,45.0).book.route.is_empty(),"Owner on its old voyage cannot enroll early")
	var entered: Dictionary=planned(45.0)
	check(entered.command.is_empty() and entered.book.route.sequence==0,"Admission publishes no invoice or duplicate service")
	publish(entered.book)
	check(Orders.enrolled066(core.state,Shipping.OWNER),"The existing enrollment guard covers the merchant")
	check(not is_finite(Orders.owner_position(core.state,owner).x),"Dormant HOME projection cannot publish a second position")
	check(Shipping.prepare(core.state,context).get("ok",false),"Raw physical admission validates without a normalizer")


func service_and_loading() -> void:
	var required: Dictionary=Shipping.requirements(context,snapshot())
	if not check(required.get("ok",false),"Conservative reserve uses actual northern water routes"):
		print(required);return
	check(float(required.days)>0.5 and int(required.wageCoins)>0 and float(required.food)>0.0 and float(required.fuel)>0.0,"Reserve includes real crew wages/food/fuel and service time")
	var need: int=int(required.wageCoins)+int(required.repairCoins)+ceili(float(required.food))*Economy.price(origin,"food","buy")+ceili(float(required.fuel))*Economy.price(origin,"fuel","buy")+64*Economy.price(origin,"food","buy")
	for boat in owner.boats:
		need+=maxi(0,ceili(2.0-float(boat.supplies)))*Economy.price(origin,"supplies","buy")
	var transfer: int=maxi(0,need-int(owner.coins))
	if not check(int(origin.governmentPurse)>=transfer and (transfer==0 or Money.move(origin,"governmentPurse",owner,"coins",transfer,"Controlled model reserve funding",core.state.moneyLog)),"Fixture readiness comes from an existing donor purse"):
		return
	var before: int=coins()
	var service: Dictionary=planned(45.0)
	check(service.command.kind=="service" and service.command.sequence==1,"One due watch proposes only service sequence one")
	var done: Dictionary=Fleets.dock_at068(owner,origin,book.route.location,float(required.days),core)
	if not check(done.get("ok",false),"Actual canonical berth runs finite existing provisioning"):
		print(done);return
	publish(service.book)
	check(coins()==before,"Provisioning/repairs conserve all purse coins")
	var repeat_before: PackedByteArray=var_to_bytes(core.state)
	check(Fleets.dock_at068(owner,origin,book.route.location,float(required.days),core).get("spent",-1)==0,"An in-progress service visit cannot charge twice")
	check(repeat_before==var_to_bytes(core.state),"Repeated service/view does not change stores or receipts")
	check(planned(46.0).command.is_empty(),"Paid quarter-day service does not depart after one second")
	core.state.day=1.25
	var loading: Dictionary=planned(56.25)
	if not check(loading.command.get("kind")=="load" and loading.command.good=="food" and int(loading.command.qty)>0 and int(loading.command.qty)<=64,"Funded outbound food lot is positive and bounded after reserves"):
		print(loading);return
	var food_before: float=float(owner.cargo.food)+float(origin.stocks.food)
	before=coins()
	check(trade(origin,"food",int(loading.command.qty),"buy"),"Outbound lots use real Economy.transact")
	publish(loading.book)
	check(coins()==before and absf(food_before-float(owner.cargo.food)-float(origin.stocks.food))<0.000001,"Actual load conserves both food lots and coins")
	check(book.route.phase=="outbound" and book.route.sequence==2 and not book.route.location.path.is_empty(),"Successful invoice alone publishes departure at its same location")
	check(Shipping.actor(book,snapshot()).canMove,"Actual powered merchant exposes the existing Travel actor DTO")
	var holding: Dictionary=snapshot();holding.owner.coins=0
	var at_home: Dictionary=service.book.duplicate(true)
	check(Shipping.plan(context,at_home,holding,56.25).command.is_empty(),"Unfunded departure holds without free remittance or loading")


func shared_step() -> void:
	var made: Dictionary=Travel.create(context,17,null,["player","patrol-0",Shipping.OWNER],56.25)
	if not check(made.get("ok",false),"One shared ocean runtime admits exactly three owners"):
		return
	var raider_boats: Array=OceanCampaign.render_boats(Orders.find_owner(core.state,"patrol-0").get("boats",[]))
	var raider_valid: bool=Travel._boats_valid(raider_boats)
	if not check(not raider_boats.is_empty() and raider_valid,"Actual unfitted patrol-0 render DTO validates without assumed equipment"):
		print("raider_boats=",raider_boats,"; Travel._boats_valid=",raider_valid)
		return
	# create_owners does not fit mounts; exercise numeric size with a declared DTO.
	var numeric_mount_boats: Array=[{"uid":"controlled-numeric-mount","spec":{"id":"controlled-mount-hull","weaponMounts":[{"id":"controlled-mount","size":1}]}}]
	if not check(Travel._boats_valid(numeric_mount_boats),"Explicit controlled render DTO validates its numeric mount size field"):
		return
	var participants: Array=[]
	var relations: Array=[]
	for id in ["player","patrol-0",Shipping.OWNER]:
		# Controlled nearby DTOs exercise shared sensing caps, not fleet relocation.
		participants.append({"ownerId":id,"location":Shipping._location("ocean",World.OCEAN,{"x":2400.0+participants.size(),"y":1400.0}),"baseSpeed":0.0,"clearance":20.0,"canMove":false,"canIntercept":false,"detectionRange":1800.0,"interceptRange":75.0,"boats":raider_boats if id=="patrol-0" else []})
	for a in participants:
		for b in participants:
			if a.ownerId!=b.ownerId:relations.append({"observerId":a.ownerId,"targetId":b.ownerId,"hostile":false})
	var before: PackedByteArray=var_to_bytes([participants,relations,made.memory])
	var result: Dictionary=Travel.step(made.context,participants,relations,made.memory,{"startSecond":56.25,"dt":4.0,"watchDue":true,"decisionOwnerIds":[]})
	if not check(result.get("ok",false),"Three actors/six directed relations share a single accepted step"):
		print(result);return
	check(before==var_to_bytes([participants,relations,made.memory]),"Shared step leaves all input DTOs and single memory unchanged")
	check(result.acceptedSeconds==4.0 and result.locations.size()==3,"Only one bounded accepted interval is returned")
	for id in ["player","patrol-0",Shipping.OWNER]:check(result.memory.sightings.get(id,{}).size()==2,"Each observer retains at most its two actual dated contacts")
	var fourth: Array=participants.duplicate(true);fourth.append(participants[0].duplicate(true));fourth[-1].ownerId="extra"
	check(not Travel.step(made.context,fourth,relations,made.memory,{"startSecond":56.25,"dt":1.0,"watchDue":false,"decisionOwnerIds":[]}).get("ok",false),"A fourth actor is refused rather than silently dropped")
	var resumed: Dictionary=planned(500.0)
	check(resumed.command.is_empty() and resumed.book.route.nextDueSecond==501.0,"Missed watches coalesce to one decision without transaction replay")


func delivery_and_return() -> void:
	# Stage this command boundary deliberately; the B fixture proves earned travel.
	book.route.location=Shipping._location("local",World.REMOTE,Shipping.BERTH)
	book.route.nextDueSecond=56.25
	var purchase_price: int=Economy.price(remote,"food","sell")
	check(Money.move(origin,"governmentPurse",remote,"cash",purchase_price*3,"Controlled finite buyer cash",core.state.moneyLog),"Remote test buyer uses an existing purse, never default port wealth")
	var before_coins: int=coins()
	var before_food: float=float(owner.cargo.food)+float(remote.stocks.food)
	var arrived: Dictionary=planned(56.25)
	if not check(arrived.command.get("kind")=="deliver" and arrived.command.qty==mini(3,floori(float(owner.tradeCargo))),"Actual buyer cash caps the partial delivery"):
		print(arrived);return
	check(trade(remote,"food",int(arrived.command.qty),"sell"),"Partial sale commits through the existing finite market")
	publish(arrived.book)
	check(coins()==before_coins and absf(before_food-float(owner.cargo.food)-float(remote.stocks.food))<0.000001,"Delivery conserves food/coins and leaves unsold lots aboard")
	check(float(owner.tradeCargo)>0.0 and book.route.sequence==3,"The remainder remains the original physical manifest")
	check(planned(56.25).command.is_empty(),"Repeated arrival in the same watch cannot sell again")
	var service: Dictionary=planned(57.25)
	if not check(service.command.get("kind")=="service" and service.command.sequence==4,"The following watch performs service instead of replaying delivery"):
		return
	core.state.day=57.25/45.0
	var required: Dictionary=Shipping.requirements(context,snapshot())
	var result: Dictionary=Fleets.dock_at068(owner,remote,book.route.location,float(required.days)*0.5,core)
	if not check(result.get("ok",false),"Remote service uses the actual finite port and canonical surviving hulls"):
		print(result);return
	publish(service.book)
	core.state.day=68.5/45.0
	var returning: Dictionary=planned(68.5)
	if not check(returning.command.get("kind")=="load" and returning.command.qty==0 and returning.command.good=="food" and returning.book.route.phase=="return","Unsold food reverses physically with no overwritten manifest or invented logs"):
		print(returning);return
	var before: PackedByteArray=var_to_bytes([owner.cargo,owner.coins,owner.crewPurse,owner.boats,remote])
	publish(returning.book)
	check(before==var_to_bytes([owner.cargo,owner.coins,owner.crewPurse,owner.boats,remote]) and owner.atPort=="" and not owner.has("harborServiceUntilDay"),"Departure preserves every inventory/purse/hull while clearing berth publication")
	var missing: Dictionary=snapshot();missing.owner.tradeCargo=0.0;missing.owner.tradeGood="logs"
	var serviced: Dictionary=service.book.duplicate(true)
	missing.owner.atPort=Shipping.REMOTE_PORT;missing.owner.harborServiceUntilDay=57.25/45.0+0.25
	var optional: Dictionary=Shipping.plan(context,serviced,missing,68.5)
	check(optional.get("ok",false) and optional.command.get("kind")=="load" and optional.command.qty==0 and optional.command.good=="logs","No exportable return logs means an honest empty optional return lot")
	var damaged: Dictionary=snapshot();damaged.performance.seaworthy=false
	var outward: Dictionary=book.duplicate(true);outward.route.phase="outbound";outward.route.sequence=2;outward.route.nextDueSecond=68.5
	var diverted: Dictionary=Shipping.plan(context,outward,damaged,68.5)
	check(diverted.get("ok",false) and diverted.book.route.phase=="return" and diverted.book.route.sequence==2 and diverted.command.is_empty(),"Unsafe outward voyage reverses without fabricating a remote invoice")


func raw_validation() -> void:
	var raw: Dictionary=JSON.parse_string(JSON.stringify(core.state))
	var before: PackedByteArray=var_to_bytes(raw)
	check(Shipping.prepare(raw,context).get("ok",false),"Parsed mid-leg save retains actual owner/UID/route identity")
	check(before==var_to_bytes(raw),"Prepare success changes no raw input account, event, cargo or clock")
	for kind in ["null","schema","extra","owner","sequence","clock","location","projection","custody","manifest"]:
		var broken: Dictionary=raw.duplicate(true)
		match kind:
			"null":broken.shipping068.model=null
			"schema":broken.shipping068.model.schema=true
			"extra":broken.shipping068.model.duplicateInventory={}
			"owner":broken.shipping068.model.route.ownerId="patrol-1"
			"sequence":broken.shipping068.model.route.sequence=1.5
			"clock":broken.shipping068.model.route.nextDueSecond=float(broken.day)*45.0+1000.0
			"location":broken.shipping068.model.route.location.position.x=NAN
			"projection":broken.patrols[0].active=true
			"custody":broken.fleet.append(broken.fleetOwners[7].boats[0].duplicate(true))
			"manifest":broken.fleetOwners[7].tradeCargo=float(broken.fleetOwners[7].cargo.food)+1000.0
		var snapshot_before: PackedByteArray=var_to_bytes(broken)
		check(not Shipping.prepare(broken,context).get("ok",false),"Malformed-present raw model refuses: "+kind)
		check(snapshot_before==var_to_bytes(broken),"Raw refusal preserves input exactly: "+kind)
	var lost: Dictionary=raw.duplicate(true)
	for boat in lost.fleetOwners[7].boats:boat.sunk=true
	lost.fleetOwners[7].active=false
	lost.shipping068.model.route.phase="lost";lost.shipping068.model.route.location.path=[];lost.shipping068.model.route.location.destination=""
	check(Shipping.prepare(lost,context).get("ok",false),"A physically wiped original carrier can persist as lost without relaunch")
	var no_hulls: Dictionary=snapshot()
	for boat in no_hulls.owner.boats:boat.sunk=true
	check(Shipping.actor(book,no_hulls).get("canMove",true)==false,"Wiped physical hulls cannot expose a moving carrier")


func home_destination_filters() -> void:
	for salt in range(14):
		var target: Dictionary=Jobs._destination(core.state,origin,salt)
		check(not target.is_empty() and target.get("id")!=Shipping.REMOTE_PORT,"Coastal job selection cannot index the installed remote harbor")
	check(Jobs._destination(core.state,remote,0).is_empty(),"Remote harbor opens no new coastal player job origin")
	check(Orders.home_ports064(core.state).size()==10 and Orders.home_port064(core.state,Shipping.REMOTE_PORT).is_empty(),"Home AI catalog keeps exactly its original ten ports")


func one_upkeep() -> void:
	var costs: Dictionary=Fleets.upkeep(owner)
	var crew_cash: int=int(owner.crewPurse)
	var food: float=float(owner.cargo.food)
	var fuel: float=0.0
	for boat in owner.boats:fuel+=float(boat.fuel)
	var day: float=float(core.state.day)
	var before_coins: int=coins()
	Fleets.tick([owner],core.state.ports,0.1,core)
	var after_fuel: float=0.0
	for boat in owner.boats:after_fuel+=float(boat.fuel)
	check(core.state.day==day and coins()==before_coins,"The sole NPC upkeep path pays conserved purses without advancing campaign time")
	check(int(owner.crewPurse)>crew_cash and absf(food-float(owner.cargo.food)-float(costs.food)*0.1)<0.000001 and absf(fuel-after_fuel-float(costs.fuel)*0.1)<0.000001,"Enrolled merchant receives exactly the existing payroll and food/fuel burn")
	var physical: Dictionary=snapshot()
	var before: PackedByteArray=var_to_bytes([owner,core.state.day])
	Shipping.plan(context,book,physical,float(core.state.day)*45.0)
	Shipping.actor(book,physical)
	check(before==var_to_bytes([owner,core.state.day]),"Shipping scheduling/render snapshot adds no second upkeep or campaign clock")


func controlled_conflict() -> void:
	# Explicit controlled staging proves resolver reuse, never an earned voyage/win.
	var raider: Dictionary=Orders.find_owner(core.state,"patrol-0")
	var refuge: Dictionary=Orders.find_port(core.state,str(raider.homePort))
	Fleets.dock(raider,refuge)
	raider.atPort="";raider.erase("harborServiceUntilDay")
	core.state.patrols.append({"id":"patrol-0","x":float(refuge.x),"y":float(refuge.y),"active":false,"hidden":true,"holding":true,"course":[]})
	var location_a: Dictionary=Shipping._location("ocean",World.OCEAN,{"x":2400.0,"y":1400.0})
	var location_b: Dictionary=Shipping._location("ocean",World.OCEAN,{"x":2401.0,"y":1400.0})
	core.state.ocean066={"contact":{"ownerId":"patrol-0","phase":"patrol","location":location_a},"memory":Travel.empty_memory()}
	book.route.location=location_b;book.route.phase="return"
	var original: Array=owner.boats
	var fake: Dictionary=location_b.duplicate(true);fake.position.x+=1.0
	var before: PackedByteArray=var_to_bytes(core.state)
	check(not NavalAI.resolve_at068(core,"patrol-0",Shipping.OWNER,location_a,fake).get("ok",false),"NPC combat refuses a claimed position that differs from the canonical carrier")
	check(before==var_to_bytes(core.state),"Refused physical contact spends no budget, ammo, cargo or purse")
	var before_coins: int=coins()
	var outcome: Dictionary=NavalAI.resolve_at068(core,"patrol-0",Shipping.OWNER,location_a,location_b)
	if not check(outcome.get("ok",false),"A staged hostile NPC contact calls the real existing salvo/prize resolver"):
		print(outcome);return
	check(int(outcome.event.salvos)>0 and int(outcome.event.shotsA)+int(outcome.event.shotsB)>0,"Controlled NPC encounter actually fires finite physical ammunition")
	check(coins()==before_coins and is_same(owner.boats,original),"NPC settlement conserves purse coins and retains original physical hull owners")
	check(int(core.state.navalAi.encounterCount)==1 and core.state.navalAi.encounterOwners.has(Shipping.OWNER),"Offscreen combat consumes the same existing daily encounter budget")
	for wreck in core.state.get("wrecks",[]):check(wreck.get("world064")==location_a.world064 and (World._distance(wreck,location_a.position)<0.000001 or World._distance(wreck,location_b.position)<0.000001),"Any NPC wreck stays at its actual ocean loss location")
	before=var_to_bytes(core.state)
	check(not NavalAI.resolve_at068(core,"patrol-0",Shipping.OWNER,location_a,location_b).get("ok",false),"The same daily participants cannot resolve twice")
	check(before==var_to_bytes(core.state),"Repeated NPC refusal leaves losses, stores, payouts and budget unchanged")


func trade(port: Dictionary, good: String, qty: int, side: String) -> bool:
	var wallet: Dictionary={"coins":int(owner.coins),"cargo":owner.cargo}
	var result: Dictionary=Economy.transact(port,wallet,good,qty,side,Fleets._capacity(owner))
	if not result.get("ok",false):return false
	owner.coins=int(wallet.coins)
	owner.tradeGood=good
	owner.tradeCargo=maxf(0.0,float(owner.tradeCargo)+(float(result.qty) if side=="buy" else -float(result.qty)))
	return true


func coins() -> int:
	var count: int=Fleets.total_coins(core.state.fleetOwners)
	for port in core.state.ports:
		for key in ["cash","governmentPurse","householdPurse","expertPurse","recruitPurse"]:count+=int(port.get(key,0))
	return count


func finish() -> void:
	print("shipping068: %d checks, %d failures; controlled model fixture %dms"%[checks,failures,Time.get_ticks_msec()-started])
	quit(0 if failures==0 else 1)
