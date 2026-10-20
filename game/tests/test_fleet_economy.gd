extends SceneTree
const F=preload("res://scripts/fleet_economy.gd")
const E=preload("res://scripts/economy.gd")
const G=preload("res://scripts/goods.gd")
var failed: Array=[]
var count: int=0
var world: Dictionary
func check(ok: bool,message: String) -> void:
	count+=1
	if not ok:
		failed.append(message)
		print("FAIL "+message)
func ports_fixture() -> Array:
	var ports: Array=[]
	for p in world.PORTS:
		var port: Dictionary=p.duplicate(true)
		port.cash=2000000
		port.householdPurse=1000000
		port.expertPurse=300000
		port.governmentPurse=2000000
		port.workers=0
		port.publicWorkers=0
		port.availableWorkers=100
		port.specialists=12
		port.specialistWorkers=12
		port.availableSpecialists=12
		port.workforce=100
		port.recruits=100
		port.prosperity=70.0
		port.stocks={}
		port.buildQueue=[]
		for good in G.ITEMS:
			port.stocks[good]=100.25
		ports.append(port)
	return ports
func coins(owners: Array,ports: Array) -> int:
	var total: int=F.total_coins(owners)
	for p in ports:
		for field in ["cash","householdPurse","expertPurse","governmentPurse"]:
			total+=int(p.get(field,0))
		for job in p.get("buildQueue",[]):
			total+=int(job.get("escrow",0))
	return total
func find(items: Array,id: String) -> Dictionary:
	for item in items:
		if item.id==id:
			return item
	return {}
func _initialize() -> void:
	var started: int=Time.get_ticks_msec()
	world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	check(E.GOODS.size()==16,"Requires refreshed real sixteen-good bronze-cash Economy")
	var original_world: Dictionary=world.duplicate(true)
	var ports: Array=ports_fixture()
	var total: int=coins([],ports)
	var owners: Array=F.create_owners(ports,world)
	check(owners.size()==9,"Nine real chart fleet owners")
	check(coins(owners,ports)==total,"Initial owner capital is transferred, never minted")
	for i in range(owners.size()):
		var owner: Dictionary=owners[i]
		check(owner.id=="patrol-%d"%i and owner.route==world.ROUTES[(i*3+1)%world.ROUTES.size()],"Owner matches patrol route %d"%i)
		check(not owner.boats.is_empty(),"Owner owns concrete boats %d"%i)
		owner.atPort=""
		owner.cargo.food=100.0
		for boat in owner.boats:
			boat.fuel=10.0
	var a: Dictionary=owners[0]
	var costs: Dictionary=F.upkeep(a)
	check(costs.wages==a.boats[0].crew*100,"100 bronze cash per living sailor per day")
	var purse: int=a.crewPurse
	var capital: int=a.coins
	F.tick([a],[],1.0)
	check(a.crewPurse==purse+costs.wages and a.coins==capital-costs.wages,"Salary enters real crew purse")
	check(a.wageArrears==0,"Paid salary leaves no liability")
	check(coins(owners,ports)==total,"Salary transfer conserves total cash")
	check(is_equal_approx(a.cargo.food,100.0-costs.food),"Crew consume real food")
	var paid_speed: float=a.boats[0].spec.speed
	a.coins=0
	# Removing this fixture purse is explicit setup; establish a new conservation baseline.
	total=coins(owners,ports)
	F.tick([a],[],3.0)
	check(a.wageArrears==3*costs.wages,"Missed wages recorded only as liability")
	check(a.morale<85 and a.performanceFactor<1 and a.boats[0].spec.speed<paid_speed and a.boats[0].spec.fireRate<a.boats[0].economyBaseFireRate,"Arrears lower actual movement and firing performance")
	check(coins(owners,ports)==total,"Arrears do not mint or destroy coins")
	var home: Dictionary=find(ports,a.homePort)
	var govt: int=home.governmentPurse
	var subsidy: int=F.subsidize(a,home,2000)
	check(subsidy==2000 and home.governmentPurse==govt-2000 and a.coins==2000,"Explicit affordable subsidy transfers existing public purse")
	F.tick([a],[],0.25)
	check(a.wageArrears==0 and a.lastPayroll==3*costs.wages+int(costs.wages*0.25),"Fresh funds settle arrears and current salary")
	check(coins(owners,ports)==total,"Subsidy and arrears settlement conserve cash")
	check(world==original_world,"Spec performance scaling never mutates world hulls")
	var isolated: Dictionary=a.boats[0].spec
	isolated.speed=1
	check(world==original_world and owners[1].boats[0].spec.speed!=1,"Each boat owns independent deep spec")
	# Fractional days must accrue integer salaries without losing fractional liabilities.
	ports=ports_fixture()
	owners=F.create_owners(ports,world)
	a=owners[0]
	a.atPort=""
	a.cargo.food=100.0
	capital=a.coins
	for i in range(10):
		F.tick([a],[],0.1)
	check(a.coins==capital-F.upkeep(a).wages and a.wageArrears==0,"Ten fractional days equal one salary day")
	# A sunk fleet retains both owner and paid sailors' cash.
	total=coins(owners,ports)
	for boat in a.boats:
		boat.sunk=true
	var before: int=F.total_coins([a])
	F.tick([a],[],1.0)
	check(F.total_coins([a])==before and F.upkeep(a).wages==0,"Sinking never erases a purse or pays nonexistent crew")
	check(coins(owners,ports)==total,"Sunk fleet cash stays in circulation")
	_test_dock_and_trade()
	_test_long_run()
	_test_no_capital()
	_test_normalization_and_pools()
	if E.GOODS.size()==16:
		_test_real_economy()
	print("fleet cash: %d checks, %d failures, %d ms"%[count,failed.size(),Time.get_ticks_msec()-started])
	if failed.is_empty():
		quit(0)
	else:
		quit(1)
		assert(failed.is_empty(),"Fleet cash failures above")
func _test_dock_and_trade() -> void:
	var ports: Array=ports_fixture()
	var owners: Array=F.create_owners(ports,world)
	var owner: Dictionary=owners[1]
	var home: Dictionary=find(ports,owner.homePort)
	var destination: Dictionary=find(ports,str(owner.route[1]))
	var total: int=coins(owners,ports)
	owner.crewPurse=10000
	# Explicit fixture endowment: track the updated cash baseline.
	total=coins(owners,ports)
	var business: int=home.cash
	var crew: int=owner.crewPurse
	var snapshots: Dictionary=home.stocks.duplicate()
	F.dock(owner,home)
	check(home.cash>business and owner.crewPurse<crew,"Port stores and crew food purchases pay real businesses")
	check(owner.cargo.food>0 and home.stocks.food<snapshots.food,"Crew buys physical ration stock")
	check(owner.boats[0].ammo>=50 and home.stocks.ammo<snapshots.ammo,"One ammunition case becomes fifty ready rounds")
	check(owner.boats[0].fuel>0 and owner.boats[0].supplies>0,"Boat stores are bought from finite inventory")
	check(owner.cargo[owner.tradeGood]>0,"Merchant buys actual source cargo")
	check(coins(owners,ports)==total,"Dock purchases conserve all cash")
	var sold: float=owner.cargo[owner.tradeGood]
	var stocks: float=destination.stocks[owner.tradeGood]
	F.dock(owner,destination)
	check(owner.cargo[owner.tradeGood]<sold and destination.stocks[owner.tradeGood]>stocks,"Merchant sells only owned cargo into destination stock")
	check(coins(owners,ports)==total,"Merchant round trip conserves coins")
	owner.coins=0
	owner.crewPurse=0
	owner.cargo={}
	for good in G.ITEMS:
		owner.cargo[good]=0.0
	for boat in owner.boats:
		boat.fuel=0
		boat.ammo=0
		boat.supplies=0
	var before: Dictionary=destination.stocks.duplicate()
	F.dock(owner,destination)
	check(destination.stocks==before and owner.boats[0].ammo==0,"Empty purses cannot receive free stores")
	owner.coins=10000
	owner.boats[0].hp-=20
	owner.boats[0].supplies=4
	total=coins(owners,ports)
	var household: int=destination.householdPurse
	var hp: float=owner.boats[0].hp
	F.dock(owner,destination)
	check(owner.boats[0].hp>hp and destination.householdPurse==household+100,"Drydock labor is paid to resident worker purse")
	check(coins(owners,ports)==total,"Repair labor and material purchases conserve cash")
	owner.boats[0].hp-=10
	destination.availableWorkers=0
	hp=owner.boats[0].hp
	F.dock(owner,destination)
	check(owner.boats[0].hp==hp,"No idle civilian worker means no phantom repair labor")
	destination.availableWorkers+=2
	owner.boats[0].hp=owner.boats[0].maxHp
	owner.boats[0].engine=0.5
	owner.boats[0].supplies=2
	var expert: int=destination.expertPurse
	total=coins(owners,ports)
	F.dock(owner,destination)
	check(owner.boats[0].engine>0.5 and destination.expertPurse==expert+150,"Engine mechanics receive explicit150cash wage")
	check(coins(owners,ports)==total,"Expert repair transfer conserves money")
func _test_long_run() -> void:
	var ports: Array=ports_fixture()
	var owners: Array=F.create_owners(ports,world)
	ports[0].buildQueue=[{"escrow":1234}]
	var total: int=coins(owners,ports)
	for day in range(365):
		for owner in owners:
			owner.atPort=owner.route[day%2]
		F.tick(owners,ports,1.0)
		check(coins(owners,ports)==total,"Day%d exact aggregate cash conservation including escrow"%day)
	for owner in owners:
		check(owner.coins>=0 and owner.crewPurse>=0 and owner.wageArrears>=0 and owner.log.size()<=16,"Finite owner balances and bounded logs")
		for good in owner.cargo:
			check(is_finite(float(owner.cargo[good])) and owner.cargo[good]>=0,"Finite owned cargo "+good)
		for boat in owner.boats:
			for field in ["hp","fuel","ammo","supplies"]:
				check(is_finite(float(boat[field])) and boat[field]>=0,"Finite boat stock "+field)
	check(world.HULLS[0].speed>0,"World remains untouched")

func _test_real_economy() -> void:
	var ports: Array=[]
	for definition in world.PORTS:
		ports.append(E.create_port(definition))
	var total: int=coins([],ports)
	var owners: Array=F.create_owners(ports,world)
	check(coins(owners,ports)==total,"Real seeded economy capital conservation")
	for day in range(365):
		E.tick_ports(ports,1.0)
		for owner in owners:
			owner.atPort=owner.route[day%2]
		F.tick(owners,ports,1.0)
		check(coins(owners,ports)==total,"Real economy plus nine NPC fleets conserve cash day%d"%day)
	for port in ports:
		for good in G.ITEMS:
			check(port.stocks[good]>=0 and is_finite(float(port.stocks[good])),"Real economy finite "+good)

func _test_no_capital() -> void:
	var ports: Array=ports_fixture()
	var civilian_before: int=0
	for port in ports:
		port.cash=0
		port.governmentPurse=0
		civilian_before+=port.availableWorkers
	var total: int=coins([],ports)
	var owners: Array=F.create_owners(ports,world)
	check(F.total_coins(owners)==0 and coins(owners,ports)==total,"No sponsoring coins means zero fleet capital, no refill")
	var assigned: int=0
	for owner in owners:
		owner.atPort=owner.homePort
		for boat in owner.boats:
			assigned+=int(boat.crew)
	var civilians: int=0
	for port in ports:
		civilians+=port.availableWorkers
	check(civilian_before-civilians==assigned,"NPC sailors leave fixed civilian workforce exactly once")
	F.tick(owners,ports,1.0)
	check(F.total_coins(owners)==0 and coins(owners,ports)==total,"Bankrupt fleet cannot mint salary or store money")
	for owner in owners:
		check(owner.wageArrears==F.upkeep(owner).wages and owner.morale<85,"Bankrupt owner's wages accrue as unhappy liabilities")
	check(F.subsidize(owners[0],ports[0],9999)==0,"Empty government purse cannot grant subsidy")

func _test_normalization_and_pools() -> void:
	var ports: Array=ports_fixture()
	var work_before: int=0
	var recruits_before: int=0
	for port in ports:
		work_before+=port.workforce
		recruits_before+=port.recruits
	var owners: Array=F.create_owners(ports,world)
	var sailors: int=0
	for owner in owners:
		for boat in owner.boats:
			sailors+=int(boat.crew)
	var work_after: int=0
	var recruits_after: int=0
	for port in ports:
		work_after+=port.workforce
		recruits_after+=port.recruits
	check(work_after==work_before-sailors and recruits_after==recruits_before-sailors,"Initial crew reduces canonical workforce and recruits, not idle alone")
	E.tick_ports(ports,1)
	var work_next: int=0
	for port in ports:
		work_next+=port.workforce
	check(work_next==work_after,"Economy day cannot recreate assigned fleet sailors")
	var boat: Dictionary=owners[0].boats[0]
	var external: Dictionary={"id":"story-0","coins":12345,"crewPurse":87,"wageArrears":5,"cargo":{},"tradeCargo":{},"boats":[boat]}
	var normalized: Dictionary=F.normalize_owner(external)
	check(is_same(external,normalized) and is_same(external.boats[0],boat),"Normalize retains owner and ship identity")
	check(external.coins==12345 and external.crewPurse==87 and external.wageArrears==5,"Normalize never creates or erases existing money/liabilities")
	check(external.cargo.size()==16 and (external.tradeCargo is int or external.tradeCargo is float),"External story owners gain16cargo keys and numeric business lots")
	var before: Dictionary=external.duplicate(true)
	F.normalize_owner(external)
	check(before==external,"Normalization idempotent")
	external.atPort=""
	var money: int=F.total_coins([external])
	F.tick([external],[],0.5)
	check(F.total_coins([external])==money and external.daysOperated==0.5,"Sparse story owner ticks without missing fields or money loss")
	var port: Dictionary=ports[0]
	port.availableWorkers=1
	port.workers=30
	port.publicWorkers=10
	port.workforce=41
	if port.has("_lastWorkersField"):
		port._lastWorkersField=30
	external.coins=10000
	external.crewPurse=0
	external.cargo.food=0
	boat.hp=boat.maxHp-20
	boat.supplies=4
	var hp: float=boat.hp
	F.dock(external,port)
	check(boat.hp>hp and port.availableWorkers==0 and port.workers==31,"One idle worker repairs even when many others already employed, then reserves slot")
	if port.has("_lastWorkersField"):
		check(port._lastWorkersField==port.workers,"Legacy workforce sync marker follows explicit employment")
	E.tick_ports([port],1)
	check(port.workforce==41,"Repair employment cannot reset canonical workforce")
