extends SceneTree
const C=preload("res://scripts/campaign.gd")
const M=preload("res://scripts/money.gd")
const R=preload("res://scripts/naval_replacements.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;print("FAIL naval recovery: ",message)
func _initialize():
	var w: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var c=C.new(w);c.new_game(152)
	var owner: Dictionary=c.fleet_owner("patrol-0")
	var home: Dictionary=c.port(owner.homePort)
	var p: Dictionary=c.NavalAI._find_patrol(c.state,owner.id)
	M.move(home,"governmentPurse",owner,"coins",50000,"Fixture funded company capital",c.state.moneyLog)
	var supply: int=M.total(c.state)
	var h: Dictionary=c.hull("bilge_punt")
	var order: Dictionary=c.Construction.make_order(h,c.ship_quote(h,home),"yard")
	order.npcOwnerId=owner.id;order.ready=true;order.escrow=0
	home.buildQueue=[order];owner.atPort=""
	var x: float=p.x
	var count: int=owner.boats.size()
	check(R.collect_replacements(c,home).is_empty() and owner.boats.size()==count and p.x==x,"Ready hull stays at the yard while surviving boats are at sea")
	home.buildQueue=[]
	for boat in owner.boats:boat.sunk=true;boat.hp=0;boat.crew=0
	owner.atPort=home.id;home.shipStock.bilge_punt=1
	var replacement: Dictionary=c.NavalAI.request_replacement(c,owner,home,"bilge_punt")
	check(replacement.ok and p.x==home.x and p.y==home.y and p.holding,"Replacement for a wiped company launches at the actual paid home yard")
	check(M.total(c.state)==supply,"Replacement and finite sailor advance preserve global coins")
	var boat: Dictionary=owner.boats.filter(func(b):return not b.sunk)[0]
	boat.water=boat.capacity*0.35;boat.breaches=[];boat.policy="bail"
	var water: float=boat.water
	c.Fleets.tick([owner],c.state.ports,1.0)
	check(boat.water<water,"NPC damage control pumps persistent flooding outside combat")
	boat.hp=boat.maxHp*0.4;boat.engine=0.9;boat.supplies=10
	home.availableWorkers=5;home.availableSpecialists=0;home._yardWorkersUsed=0
	var hp: float=boat.hp
	c.Fleets._repair(owner,home,boat)
	check(boat.hp>hp and boat.engine==0.9,"Unavailable engine expert does not block a paid ordinary hull repair")
	boat.crew=1.8;boat.crewMin=2;boat.crewMax=2;boat.wounded=0
	var recruits: int=home.recruits
	c.NavalLifecycle.hire(c,owner,home)
	check(boat.crew==2 and home.recruits==recruits-1,"Fractional surviving labor reconciles to whole sailors without exceeding berths")
	c.new_game(153)
	p=c.state.patrols[4];owner=c.fleet_owner(p.id)
	c.NavalAI.build_order(c.state,owner,"withdraw",owner.homePort,"Fixture mid-voyage withdrawal")
	c.NavalLifecycle.route(c,p,owner.homePort)
	var position: Vector2=Vector2(p.x,p.y)
	var id: String=p.id
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Withdrawn fleet restores through actual campaign")
	p=c.NavalAI._find_patrol(c.state,id)
	check(Vector2(p.x,p.y).distance_to(position)<0.001,"Restoring a redirected route keeps its actual sea position")
	c.new_game(154);owner=c.fleet_owner("patrol-1");home=c.port(owner.homePort)
	for other in c.state.fleetOwners:
		if other.id!=owner.id:other.active=false
	M.move(owner,"coins",home,"governmentPurse",int(owner.coins),"Fixture empty operating purse",c.state.moneyLog)
	for good in owner.cargo:owner.cargo[good]=0
	owner.tradeGood="timber";owner.tradeCargo=10;owner.cargo.timber=10
	owner.boats[0].sunk=true;owner.boats[0].hp=0;owner.boats[0].crew=0
	c.NavalLifecycle.daily(c)
	check(is_equal_approx(float(owner.cargo.timber),5),"First carrier loss removes its share of the physical cargo")
	c.state.day+=1;c.state.econDay+=1
	owner.boats[1].sunk=true;owner.boats[1].hp=0;owner.boats[1].crew=0
	c.NavalLifecycle.daily(c)
	check(owner.cargo.timber==0 and owner.tradeCargo==0,"Second carrier loss removes all remaining cargo; no phantom hold")
	check(c.state.wrecks.size()==2,"Sequential losses create distinct physical wreck records")
	print("naval recovery: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
