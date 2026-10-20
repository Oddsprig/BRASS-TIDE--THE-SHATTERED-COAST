extends SceneTree
const R=preload("res://scripts/refit.gd")
const D=preload("res://scripts/damage.gd")
const E=preload("res://scripts/economy.gd")
const C=preload("res://scripts/construction.gd")
const G=preload("res://scripts/goods.gd")
const M=preload("res://scripts/money.gd")
const DP=preload("res://scripts/deployment.gd")
const B=preload("res://scripts/battle.gd")
var world: Dictionary
var checks: int=0
var failures: int=0

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL refit: "+message)

func fixture(hull: int=0) -> Dictionary:
	var ship: Dictionary=D.create_ship(world.HULLS[hull],{"hp":71.0,"crew":3.0,"wounded":1.0,"water":30.0,"engine":0.65,"ammo":17.0,"fuel":9.0,"supplies":6.0,"breaches":[{"area":10.0,"section":"bow"}]})
	ship.uid="test-owned"
	var port: Dictionary=E.create_port(world.PORTS[0])
	# Controlled paid-stock/workforce fixture built with the real economy module.
	port.workforce=100
	port.workers=0
	port.publicWorkers=0
	port.availableWorkers=100
	port.specialists=20
	port.availableSpecialists=20
	for good in G.ITEMS: port.stocks[good]=100.0
	C.begin_day(port)
	return {"coins":1000000,"crewPurse":0,"ports":[port],"fleet":[ship],"moneyLog":[]}

func condition(ship: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key in ["hp","maxHp","water","engine","ammo","fuel","supplies","crew","wounded","breaches","fire","sunk"]: result[key]=ship[key].duplicate(true) if ship[key] is Array else ship[key]
	return result

func test_defaults() -> void:
	for base in world.HULLS:
		var defaults: Dictionary=R.defaults(base)
		var fit: Dictionary=R.normalize(base,defaults)
		var spec: Dictionary=R.effective_spec(base,defaults)
		check(fit.ok and defaults.weapons[0]=="stock_primary" and defaults.weapons.size()==R.hardpoints(base).size(),"defaults match hardpoints: "+base.id)
		check(spec.weaponMounts.size()==1 and spec.weaponMounts[0].kind==base.weapon,"defaults contain only the original primary: "+base.id)
		for key in ["speed","turn","hp","armor","damage","fireRate","range","pumps"]:
			check(is_equal_approx(float(spec[key]),float(base[key])),"default preserves "+key+": "+base.id)
		check(DP.cost(spec)==DP.cost(base),"default preserves hull deployment points: "+base.id)
	var state: Dictionary=fixture()
	var ship: Dictionary=state.fleet[0]
	var before: Dictionary=condition(ship)
	R.ensure(ship)
	check(condition(ship)==before and ship.refitLocker.is_empty(),"legacy migration changes no wounds, crew, working stores or health")
	var saved: Dictionary=ship.duplicate(true)
	R.ensure(ship)
	check(ship==saved,"ensure is exactly idempotent")
	var altered: Dictionary=world.HULLS[0].duplicate(true)
	altered.hp=100.0
	R.ensure(ship,altered)
	check(ship.hp<=before.hp and is_equal_approx(ship.hp/ship.maxHp,float(before.hp)/before.maxHp),"lower canonical maximum preserves damage ratio without healing")

func test_loadouts() -> void:
	var small: Dictionary=world.HULLS[0]
	var large: Dictionary=world.HULLS[23]
	var cat: Dictionary=R.catalog()
	var families: Dictionary={"gun":0,"cannon":0,"rocket":0,"torpedo":0}
	for id in cat.weapons:
		if cat.weapons[id].kind in families:
			families[cat.weapons[id].kind]+=1
			var fit: Dictionary=R.defaults(large)
			fit.weapons[0]=id
			check(R.normalize(large,fit).ok and R.effective_spec(large,fit).weaponMounts[0].kind==cat.weapons[id].kind,"weapon fits suitable real hull: "+id)
	for family in families: check(families[family]>=2,"two meaningful "+family+" choices")
	check(cat.engines.size()>=4 and cat.armor.size()>=4,"three alternative engines and armor sets plus originals")
	var magazine: Dictionary=R.defaults(small)
	magazine.weapons[1]="rapid_gun"
	check(R.effective_spec(small,magazine).ammoCapacity==160 and R.effective_spec(small,R.defaults(small)).ammoCapacity==80,"paid extra weapon mount expands magazine capacity without supplying ammunition")
	var fit: Dictionary=R.defaults(small)
	fit.weapons[0]="unknown"
	check(not R.normalize(small,fit).ok,"reject unknown weapon")
	fit=R.defaults(small)
	fit.engine="light_cannon"
	check(not R.normalize(small,fit).ok,"reject wrong module family")
	fit=R.defaults(small)
	fit.weapons[0]="heavy_cannon"
	check(not R.normalize(small,fit).ok,"large weapon cannot overload a tiny hardpoint")
	fit=R.defaults(small)
	fit.weapons[0]="light_torpedo"
	fit.weapons[1]="rapid_gun"
	check(not R.normalize(small,fit).ok,"fitting-point budget rejects combined overload")
	fit=R.defaults(small)
	fit.weapons[1]="stock_primary"
	check(not R.normalize(small,fit).ok,"default primary cannot be cloned into an extra hardpoint")
	fit=R.defaults(small)
	fit.weapons.pop_back()
	check(not R.normalize(small,fit).ok,"reject incorrect slot count")
	fit=R.defaults(small)
	fit.weapons=[0,""]
	check(not R.normalize(small,fit).ok,"reject non-string module IDs")
	fit=R.defaults(small)
	fit.secretDamage=999
	check(not R.normalize(small,fit).ok,"reject unrecognized loadout fields")
	var base: Dictionary=world.HULLS[23]
	fit=R.defaults(base)
	fit.engine="economy_drive"
	var economical: Dictionary=R.effective_spec(base,fit)
	fit.engine="heavy_drive"
	var fast: Dictionary=R.effective_spec(base,fit)
	check(economical.speed<base.speed and economical.fuelUse<1.0 and fast.speed>base.speed and fast.fuelUse>1.0,"engines trade actual speed against fuel")
	fit=R.defaults(base)
	fit.armor="fortress_plating"
	var armored: Dictionary=R.effective_spec(base,fit)
	check(armored.armor>base.armor and armored.speed<base.speed and armored.hp==base.hp,"armor adds protection and drag without creating health")

func test_paid_install() -> void:
	var state: Dictionary=fixture()
	var ship: Dictionary=state.fleet[0]
	var port: Dictionary=state.ports[0]
	var original: Dictionary=state.duplicate(true)
	var q: Dictionary=R.quote(port,ship,"engine","boost_drive")
	check(q.ok and state==original,"quote succeeds and is entirely read only")
	check(q.cost==q.materialCost+q.workerWages+q.expertWages+q.tax+q.margin and q.businessIncome==q.materialCost+q.margin,"itemized coin quote reconciles exactly")
	check(q.workerWages==int(ceil(q.workerDays*G.WAGES.shipwright)) and q.expertWages==int(ceil(q.expertDays*G.WAGES.engineer)) and G.SAILOR_WAGE==100,"paid shipwright/engineer days use actual anchored wages")
	check(q.materials.engines>=1.0 and q.materialCost>=G.cost("engines"),"engine price includes a real whole paid machinery assembly")
	var coins: int=M.total(state)
	var health: Dictionary=condition(ship)
	var before_port: Dictionary=port.duplicate(true)
	var result: Dictionary=R.install(state,port,ship,"engine","boost_drive")
	check(result.ok and M.total(state)==coins,"paid install conserves all captain/port coins")
	check(state.coins==original.coins-q.cost and port.cash==before_port.cash+q.businessIncome,"exact parts/margin payment enters the real business purse")
	check(port.householdPurse==before_port.householdPurse+q.workerWages and port.expertPurse==before_port.expertPurse+q.expertWages and port.governmentPurse==before_port.governmentPurse+q.tax,"exact worker/expert/duty payments enter existing counted purses")
	check(not port.has("workerPurse"),"no uncounted worker purse is introduced")
	for good in q.materials: check(is_equal_approx(port.stocks[good],before_port.stocks[good]-q.materials[good]),"physical material consumed: "+good)
	check(condition(ship)==health and ship.spec.speed>world.HULLS[0].speed,"engine fitting changes performance without healing or stores/crew refill")
	check(port.availableWorkers==before_port.availableWorkers and port.availableSpecialists==before_port.availableSpecialists,"shared reservations do not double-subtract civilian availability")
	check(is_equal_approx(port._yardWorkersUsed,q.workerDays+q.expertDays) and is_equal_approx(port._yardSpecialistsUsed,q.expertDays),"install reserves real ordinary and expert work in the existing yard contract")
	check(ship.refitLocker.get("stock_engine",0)==1,"removed paid original engine becomes one locker asset")
	var saved: Dictionary=ship.duplicate(true)
	R.ensure(ship)
	check(ship==saved,"ensure after paid install is idempotent")

func test_locker() -> void:
	var state: Dictionary=fixture()
	var ship: Dictionary=state.fleet[0]
	var port: Dictionary=state.ports[0]
	var total: int=M.total(state)
	check(R.install(state,port,ship,"engine","boost_drive").ok,"purchase engine for locker cycle")
	C.begin_day(port)
	var q: Dictionary=R.quote(port,ship,"engine","stock_engine")
	check(q.ok and q.fromLocker and q.materials.is_empty() and q.materialCost==0 and q.workerWages>0 and q.expertWages>0,"owned part reinstallation costs real labor but no new materials")
	var stock: Dictionary=port.stocks.duplicate(true)
	check(R.install(state,port,ship,"engine","stock_engine").ok,"original locker engine reinstalls")
	check(port.stocks==stock and ship.refitLocker.get("stock_engine",0)==0 and ship.refitLocker.get("boost_drive",0)==1,"old/new locker asset counts transfer without duplication")
	for i in range(4):
		C.begin_day(port)
		var id: String="boost_drive" if i%2==0 else "stock_engine"
		var before_coins: int=state.coins
		check(R.install(state,port,ship,"engine",id).ok and state.coins<before_coins,"every owned-part swap still pays labor")
		check(int(ship.refitLocker.get("stock_engine",0))+int(ship.refitLocker.get("boost_drive",0))==1,"exactly one spare engine survives repeated swaps")
	check(M.total(state)==total,"locker cycles cannot create or destroy coins")
	C.begin_day(port)
	check(R.install(state,port,ship,"weapon:0","").ok and ship.spec.weaponMounts.is_empty() and ship.refitLocker.get("stock_primary",0)==1,"weapon removal stores its unique paid asset")
	C.begin_day(port)
	q=R.quote(port,ship,"weapon:0","stock_primary")
	check(q.fromLocker and q.materials.is_empty() and R.install(state,port,ship,"weapon:0","stock_primary").ok,"removed original weapon reinstalls from its locker")
	check(ship.spec.weaponMounts.size()==1 and not ship.refitLocker.has("stock_primary"),"reinstall consumes the spare weapon asset exactly once")

func refused_without_change(state: Dictionary,slot: String,id: String,message: String) -> void:
	var before: Dictionary=state.duplicate(true)
	var result: Dictionary=R.install(state,state.ports[0],state.fleet[0],slot,id)
	check(not result.ok and state==before,message)

func test_refusals() -> void:
	var state: Dictionary=fixture()
	var q: Dictionary=R.quote(state.ports[0],state.fleet[0],"engine","boost_drive")
	state.coins=q.cost-1
	refused_without_change(state,"engine","boost_drive","insufficient coins is atomic even on an unmigrated boat")
	state=fixture()
	state.ports[0].stocks.engines=0.0
	refused_without_change(state,"engine","boost_drive","insufficient physical components is atomic")
	state=fixture()
	state.ports[0].availableWorkers=0
	refused_without_change(state,"engine","boost_drive","zero available workers cannot fit an engine")
	state=fixture()
	state.ports[0].availableSpecialists=0
	refused_without_change(state,"engine","boost_drive","zero available experts cannot fit an engine")
	state=fixture()
	C._record_yard_reservation(state.ports[0],100,20,98.0,79.0,19.0)
	refused_without_change(state,"engine","boost_drive","construction/repair reservations prevent refit overbooking")
	state=fixture()
	state.fleet[0].loadout=R.defaults(world.HULLS[0])
	state.fleet[0].loadout.weapons[0]="invented"
	refused_without_change(state,"engine","boost_drive","malformed existing loadout cannot be replaced by free defaults")
	state=fixture()
	state.fleet[0].refitLocker={"boost_drive":-1}
	refused_without_change(state,"engine","boost_drive","negative locker count is rejected without mutation")
	state=fixture()
	state.fleet[0].refitLocker={"unknown":1}
	refused_without_change(state,"engine","boost_drive","unknown locker asset is rejected")
	state=fixture()
	refused_without_change(state,"weapon:99","rapid_gun","invalid slot is atomic")
	refused_without_change(state,"weapon:0","heavy_cannon","oversized module is atomic")
	state=fixture()
	for i in range(19):
		var ship: Dictionary=D.create_ship(world.HULLS[0])
		ship.uid="padding-%d"%i
		state.fleet.append(ship)
	check(DP.total(state.fleet)==300,"real starter hull roster fills 300 deployment points")
	refused_without_change(state,"engine","boost_drive","refit cannot exceed fleet deployment-point limit")
	state=fixture()
	state.fleet[0].refitLocker=[{"id":"rapid_gun","count":2},"light_cannon"]
	R.ensure(state.fleet[0])
	check(state.fleet[0].refitLocker=={"rapid_gun":2,"light_cannon":1},"valid saved locker lists normalize to exact asset counts")

func autopilot_ahead(ship: Dictionary) -> Dictionary:
	var target: Dictionary=D.create_ship(world.HULLS[23],{"ammo":0.0})
	target.spec.speed=0.0
	var battle: Dictionary=B.create({"fleet":[ship],"enemyFleet":[target],"seed":19})
	ship.x=500.0
	ship.y=850.0
	ship.angle=0.0
	target.x=850.0
	target.y=850.0
	B.update(battle,1.0/30.0,{})
	return battle

func test_fitted_autopilot() -> void:
	var state: Dictionary=fixture(23)
	var port: Dictionary=state.ports[0]
	var ship: Dictionary=D.create_ship(world.HULLS[23])
	ship.uid="paid-four-family-boat"
	state.fleet=[ship]
	var total: int=M.total(state)
	for pair in [["weapon:1","rapid_gun"],["weapon:2","fire_rocket"],["weapon:3","light_torpedo"]]:
		C.begin_day(port)
		check(R.install(state,port,ship,pair[0],pair[1]).ok,"real paid autopilot fitting: "+pair[1])
	check(ship.ammo==80.0 and M.total(state)==total,"three paid fittings conserve coins and do not refill the original 80 rounds")
	var points: Array=R.hardpoints(ship.baseSpec)
	for index in [2,3]:
		var mount: Dictionary=ship.spec.weaponMounts[index]
		check(mount.x==points[index].x and mount.y==points[index].y and is_equal_approx(mount.arc,0.9) and mount.angle==0.0,"side-deck launcher keeps real position and fixed forward arc")
	var battle: Dictionary=autopilot_ahead(ship)
	var fired: Dictionary={}
	for shot in battle.projectiles:
		if shot.team=="player": fired[shot.mountId]=shot.kind
	check(fired=={"mount0":"shell","mount1":"bullet","mount2":"rocket","mount3":"torpedo"},"zero-input autopilot actually fires all four paid fitted weapon families")
	check(ship.ammo==74.0 and ship.weaponCooldowns.all(func(value):return value>0.0),"four independent mounts consume exactly six rounds and start four cooldowns")
	for id in ["fire_rocket","light_torpedo"]:
		var fit: Dictionary=R.defaults(world.HULLS[23])
		fit.weapons[1]=id
		var aft: Dictionary=D.create_ship(R.effective_spec(world.HULLS[23],fit))
		battle=autopilot_ahead(aft)
		check(battle.projectiles.any(func(shot):return shot.team=="player" and shot.mountId=="mount1"),"aft-deck "+id+" fires alongside the stronger forward stock cannon")

func _initialize() -> void:
	world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	test_defaults()
	test_loadouts()
	test_paid_install()
	test_locker()
	test_refusals()
	test_fitted_autopilot()
	print("refit: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
