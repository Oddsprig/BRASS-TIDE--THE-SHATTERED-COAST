extends SceneTree
## One career, three existing actors, one real coastal corridor. No long loop.
const Campaign=preload("res://scripts/campaign.gd")
const Regional=preload("res://scripts/regional_campaigns.gd")
const Orders=preload("res://scripts/regional_orders.gd")
const Naval=preload("res://scripts/naval_orders.gd")
const Fleets=preload("res://scripts/fleet_economy.gd")
const Money=preload("res://scripts/money.gd")
const Factions=preload("res://scripts/factions.gd")
const Navigation=preload("res://scripts/navigation.gd")
const Routes=preload("res://scripts/route_cache.gd")
const Parts=preload("res://scripts/equipment_condition.gd")
const Records=preload("res://scripts/equipment_records.gd")
var checks: int=0
var failures: int=0
var c
var guard: Dictionary
var convoy: Dictionary
var hostile: Dictionary
var actor: Dictionary
var sponsor: Dictionary
var context: Dictionary
var total: int

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL supplied037: "+message)

func quote() -> Dictionary:return Orders.plan(c.state,guard,str(guard.atPort),context)

func fuel() -> float:
	var n: float=float(c.state.cargo.fuel)
	for p in c.state.ports:n+=float(p.stocks.fuel)
	for o in c.state.fleetOwners:
		n+=float(o.cargo.fuel)
		for b in o.boats:n+=float(b.fuel)
	for b in c.state.fleet:n+=float(b.fuel)
	return n

func _initialize() -> void:
	c=Campaign.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json")))
	check(c.new_game(3701).ok,"actual career initializes")
	if failures>0:finish();return
	guard=c.fleet_owner("patrol-5");convoy=c.fleet_owner("patrol-4");hostile=c.fleet_owner("patrol-0")
	sponsor=c.port("naphtha_bay");actor=Naval.find_patrol(c.state,str(guard.id))
	check(guard.homePort==sponsor.id and guard.kind=="patrol" and convoy.kind=="trader","existing patrol and loaded civilian owners are used")
	if failures>0:finish();return
	for o in c.state.fleetOwners:o.active=false
	for p in c.state.patrols:p.active=false
	guard.active=true;convoy.active=true;hostile.active=true
	# Controlled initial positions only; product orders never move or create actors.
	var start: Dictionary=Navigation.harbor_approach(c.nav,sponsor,Routes.clearance(c,actor),40.0)
	check(not start.is_empty(),"real sponsoring harbor has a safe patrol approach")
	if start.is_empty():finish();return
	actor.x=start.x;actor.y=start.y;actor.from=sponsor.id;actor.to="anvil_dock";actor.holding=true;actor.active=true
	actor.progress=0.0;actor.course=[start.duplicate(),start.duplicate()];actor.courseLength=0.0
	guard.atPort=sponsor.id
	var merchant: Dictionary=Naval.find_patrol(c.state,str(convoy.id))
	merchant.active=true;merchant.from=sponsor.id;merchant.to="anvil_dock";merchant.holding=false;merchant.progress=0.15
	merchant.course=Routes.path(c,sponsor,c.port("anvil_dock"),Routes.clearance(c,merchant));merchant.courseLength=Orders._length(merchant.course)
	c.place_patrol(merchant);convoy.atPort=""
	var raider: Dictionary=Naval.find_patrol(c.state,str(hostile.id))
	raider.x=merchant.x;raider.y=merchant.y;raider.to=hostile.homePort;raider.active=true;raider.holding=false;hostile.atPort=""
	c.state.position=Navigation.harbor_approach(c.nav,sponsor,Routes.clearance(c),65.0);c.state.path=[];c.state.lastPort=sponsor.id
	c.state.campaignFocus.fromPort=sponsor.id;c.state.campaignFocus.toPort="anvil_dock"
	Factions.adjust(c.state,str(sponsor.faction),25,"Fixture earned local watch mandate")
	context={"nav":c.nav,"scale":c.data.get("CAMPAIGN_SCALE",1.0),"daySeconds":c.DAY_SECONDS}
	total=Money.total(c.state)
	var before: int=int(sponsor.governmentPurse)
	var begun: Dictionary=Regional.start(c,"corridor")
	check(begun.ok and begun.ownerId==guard.id and int(begun.funded)>0,"real corridor assigns and funds its existing patrol")
	check(int(sponsor.governmentPurse)==before-int(begun.funded) and int(sponsor.governmentPurse)>=int(sponsor.publicWorkers)*int(c.Goods.WAGES.laborer)*2,"grant debits treasury and preserves two public-payroll days")
	check(Money.total(c.state)==total,"grant creates no coins")
	if not begun.ok or begun.ownerId!=guard.id:finish();return
	var funded: int=int(guard.coins)
	check(Regional.cancel(c,"corridor").ok and Regional.start(c,"corridor").ok and int(guard.coins)==funded,"withdraw and restart cannot duplicate paid support")
	supply_and_resume()
	objectives_and_service()
	var snapshot: Dictionary=c.state.duplicate(true)
	var expected: Dictionary=JSON.parse_string(JSON.stringify(snapshot.regionalCampaigns))
	var restored: Dictionary=c.restore(JSON.parse_string(JSON.stringify(snapshot)))
	check(restored.ok,"active supplied operation restores through real Campaign validator: "+str(restored.get("message","")))
	if restored.ok:check(JSON.parse_string(JSON.stringify(c.state.regionalCampaigns))==expected,"complete operation, plan, funding and journal retain parsed-JSON representation")
	check(Money.total(c.state)==total,"all paid support and restore conserve actual circulating coins")
	finish()

func supply_and_resume() -> void:
	hostile.active=false;Naval.find_patrol(c.state,str(hostile.id)).active=false
	var quantity: float=fuel()
	for b in guard.boats:sponsor.stocks.fuel+=float(b.fuel);b.fuel=0.0
	var stalled: Dictionary=quote()
	check(not stalled.ready and stalled.hold and stalled.readiness.shortage=="fuel","empty working tanks stall at dock with the actual first shortage")
	Regional.observe_plan(c.state,guard,stalled)
	var seq: int=int(c.state.regionalCampaigns.seq)
	Regional.observe_plan(c.state,guard,stalled)
	check(int(c.state.regionalCampaigns.seq)==seq,"repeated stalled readings do not fill the bounded journal")
	var bought: Dictionary=c.trade(str(sponsor.id),"fuel",1,"buy")
	var donated: Dictionary=Regional.contribute(c,"corridor","fuel",1) if bought.ok else {}
	check(bought.ok and donated.get("ok",false) and absf(fuel()-quantity)<0.0001,"player bought hold cargo reaches actual sponsor stock with finite fuel and coins")
	var crew_cash: int=int(guard.crewPurse)
	Fleets.tick([guard],c.state.ports,1.0,c)
	check(int(guard.lastPayroll)>0 and int(guard.crewPurse)>crew_cash,"existing fleet payroll pays actual sailors before their provision purchase")
	check(absf(fuel()-(quantity-float(guard.lastFuelConsumed)))<0.0001,"existing paid dock loads tanks; only recorded operating fuel is consumed")
	var resumed: Dictionary=quote()
	check(resumed.ready and resumed.purpose=="escort" and resumed.targetOwnerId==convoy.id,"paid dock and crew provisions resume a real loaded friendly convoy escort")
	if not resumed.ready:print("READINESS: "+JSON.stringify(resumed.readiness))
	Regional.observe_plan(c.state,guard,resumed)
	check(c.state.regionalCampaigns.journal[0].kind=="operation-resumed","actual supply restoration is observable in the same corridor journal")
	var expected_fuel: float=0.0
	for b in guard.boats:
		if not b.sunk:expected_fuel+=float(Fleets.upkeep({"boats":[b]}).fuel)*float(resumed.readiness.get("reserveDays",1))+0.6
	check(absf(float(resumed.readiness.fuelNeed)-expected_fuel)<0.0001 and resumed.readiness.routeDistance>0 and resumed.readiness.returnDistance>0,"quote uses each real hull's fuel rate and both safe sailing legs")
	var detached: Dictionary=guard.duplicate(true)
	detached.boats[0].crew=0.0;detached.targetBoats=guard.boats.size()+1
	check(Orders.readiness(c.state,detached,"anvil_dock",context).shortage=="crew","first actual crew shortage survives concurrent missing hull strength")
	check(Money.total(c.state)==total,"contribution, loading and payroll preserve every purse")

func objectives_and_service() -> void:
	hostile.active=true
	var raider: Dictionary=Naval.find_patrol(c.state,str(hostile.id));raider.active=true
	var intercept: Dictionary=quote()
	check(intercept.ready and intercept.purpose=="intercept" and intercept.targetOwnerId==hostile.id,"actual nearby hostile returning toward its hostile refuge remains interceptable")
	check(intercept.get("interceptPoint",{})=={"x":float(raider.x),"y":float(raider.y)} and intercept.destination in c.state.regionalCampaigns.operations.corridor.ends,"intercept follows its actual sea position without an enemy-port service destination")
	hostile.active=false;raider.active=false
	var merchant: Dictionary=Naval.find_patrol(c.state,str(convoy.id));merchant.active=false
	check(quote().purpose=="patrol" and str(quote().targetOwnerId).is_empty(),"missing convoy and hostile fall back to the real corridor endpoints")
	var boat: Dictionary=guard.boats[0]
	var engine_uid: String=""
	for key in boat.moduleCondition.items:
		if boat.moduleCondition.items[key].location=="engine":engine_uid=str(key)
	var damaged: Dictionary=Parts.apply_component_damage(boat.moduleCondition,{"itemUid":engine_uid,"loss":0.5,"cause":"operation_fixture_damage"})
	check(damaged.ok and Records.publish(boat).ok,"existing canonical engine takes persistent physical damage")
	var stalled: Dictionary=quote()
	check(not stalled.ready and stalled.readiness.shortage=="machinery","installed engine condition stalls the watch without a new machinery stat")
	Regional.observe_plan(c.state,guard,stalled)
	var cash: int=int(guard.coins);var experts: int=int(sponsor.expertPurse)
	Fleets.dock(guard,sponsor,c)
	var repaired: Dictionary=quote()
	check(repaired.ready and float(boat.engine)>0.68 and int(guard.coins)<cash and int(sponsor.expertPurse)>experts,"existing paid dock service restores actual engine, pays experts and resumes endpoint patrol")
	Regional.observe_plan(c.state,guard,repaired)
	check(Money.total(c.state)==total,"paid canonical repair conserves actual coins")

func finish() -> void:
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
