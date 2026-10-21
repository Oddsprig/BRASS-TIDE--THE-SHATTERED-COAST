extends SceneTree
## v0.002 fleet points, fitting persistence and save validation (campaign integration).
## Headless only. Root serializes test runs; this helper did NOT run this file.
## Requires root-integrated game/scripts/deployment.gd and game/scripts/refit.gd (public contract).
const C=preload("res://scripts/campaign.gd")
const V=preload("res://scripts/save_validation.gd")
const Damage=preload("res://scripts/damage.gd")
const Money=preload("res://scripts/money.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Refits=preload("res://scripts/refit.gd")
var world: Dictionary
var c
var checks: int=0
var failures: Array=[]

func check(ok: bool,message: String) -> bool:
	checks+=1
	if not ok:
		failures.append("line%d: %s"%[get_stack()[1].line,message])
		print("FAIL fleet points: "+failures[-1])
	return ok

func same(a,b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in range(a.size()):
			if not same(a[i],b[i]): return false
		return true
	return a==b

func copy_json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func conservation(label: String) -> void:
	check(Money.total(c.state)==int(c.state.coinSupply),label+": exact global coin conservation")

func home() -> Dictionary:
	return c.port(world.START.port)

func cheapest_hull() -> Dictionary:
	var best: Dictionary={}
	for h in world.HULLS:
		if best.is_empty() or c.hull_points(h)<c.hull_points(best):
			best=c.hull(h.id)
	return best

func dearest_hull() -> Dictionary:
	var best: Dictionary={}
	for h in world.HULLS:
		if best.is_empty() or c.hull_points(h)>c.hull_points(best):
			best=c.hull(h.id)
	return best

## A valid, non-default loadout for this hull in one slot family, or {} if the catalog has none.
func alternative_loadout(base: Dictionary,family: String,slot_key: String) -> Dictionary:
	var defaults: Dictionary=Refits.defaults(base)
	var group=Refits.catalog().get(family,{})
	for id in group:
		if str(id)==str(defaults.get(slot_key,"")): continue
		var candidate: Dictionary=defaults.duplicate(true)
		candidate[slot_key]=str(id)
		var result=Refits.normalize(base.duplicate(true),candidate)
		if result is Dictionary and result.get("ok",true)!=false:
			return V._normalized_loadout(result)
	return {}

func first_alternative(base: Dictionary) -> Dictionary:
	for pair in [["armor","armor"],["engines","engine"]]:
		var loadout: Dictionary=alternative_loadout(base,pair[0],pair[1])
		if not loadout.is_empty():
			return {"loadout":loadout,"slot":pair[1],"module":str(loadout[pair[1]])}
	return {}

func _initialize() -> void:
	var started: int=Time.get_ticks_msec()
	world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c=C.new(world)
	_test_api_and_starter()
	_test_many_light_boats()
	_test_rejection_over_limit()
	_test_legacy_save()
	_test_fitted_round_trip()
	_test_invalid_modules()
	_test_failed_install_atomicity()
	print("fleet points: %d checks, %d failures, %dms"%[checks,failures.size(),Time.get_ticks_msec()-started])
	quit(0 if failures.is_empty() else 1)

func _test_api_and_starter() -> void:
	c.new_game(123)
	check(c.fleet_limit()==300 and Deployment.LIMIT==300,"Fleet limit is 300 deployment points")
	check(c.MAX_FLEET>=38,"Roster safety cap admits 300 DP of minimum-cost hulls")
	var starter: Dictionary=c.state.fleet[0]
	check(starter.get("baseSpec") is Dictionary and starter.get("loadout") is Dictionary,"New-game boat carries base spec and loadout")
	var base: Dictionary=c.hull(starter.type)
	var expected: Dictionary=Refits.effective_spec(base.duplicate(true),starter.loadout)
	check(same(starter.baseSpec.hp,base.hp) and same(starter.spec.hp,expected.hp) and same(starter.maxHp,expected.hp),"Starter fitted spec comes from canonical base and loadout")
	check(same(starter.spec.damage,base.damage) and same(starter.spec.range,base.range),"Default fitting reproduces the base primary weapon")
	check(c.fleet_points()==Deployment.total(c.state.fleet) and c.fleet_points()>0,"fleet_points uses Deployment.total")

func _test_many_light_boats() -> void:
	c.new_game(123)
	var coins: int=c.state.coins
	var h: Dictionary=cheapest_hull()
	var cost: int=c.hull_points(h)
	check(cost>=8 and cost<=75,"Hull deployment cost within contract range")
	var added: int=0
	while c.can_add_boat(h) and added<120:
		c.add_boat(h,0)
		added+=1
	check(c.state.fleet.size()>8,"More than eight light boats fit within 300 points (cost %d, roster %d)"%[cost,c.state.fleet.size()])
	check(c.fleet_points()>c.fleet_limit() and c.state.fleet.size()==c.MAX_FLEET,"Owned reserves exceed300 and stop at the separate roster bound")
	check(not c.can_add_boat(h),"Next light hull exceeds the owned roster bound")
	var deployment: Dictionary=Deployment.split(c.state.fleet)
	check(deployment.points<=300 and deployment.deployed.size()+deployment.reserve.size()==c.state.fleet.size(),"All owned hulls survive the300-point battle split")
	check(c.state.coins==coins,"Fixture add_boat moves no coins")
	conservation("Light flotilla")
	var saved: Dictionary=copy_json(c.state)
	var validation: Dictionary=V.validate(saved,world)
	check(validation.ok,"Large legal roster passes save validation: "+str(validation.message))
	var count: int=c.state.fleet.size()
	check(c.restore(saved).ok and c.state.fleet.size()==count,"Large legal roster restores without dropping boats")

func _test_rejection_over_limit() -> void:
	c.new_game(123)
	var heavy: Dictionary=dearest_hull()
	var guard: int=0
	while c.can_add_boat(heavy) and guard<10:
		c.add_boat(heavy,0)
		guard+=1
	check(c.fleet_points()>300 and c.can_add_boat(heavy),"Heavy reserve ownership is independent of300-point deployment")
	var light: Dictionary=cheapest_hull()
	while c.can_add_boat(light) and guard<120:
		c.add_boat(light,0)
		guard+=1
	check(not c.can_add_boat(light) and c.state.fleet.size()==c.MAX_FLEET,"Fleet is filled to the owned hull safety bound")
	var p: Dictionary=home()
	var id: String=str(p.shipIds[0])
	p.shipStock[id]=maxi(1,int(p.shipStock.get(id,0)))
	var snapshot: Dictionary=c.state.duplicate(true)
	var bought: Dictionary=c.buy_boat(id)
	check(not bought.ok and same(snapshot,c.state),"Purchase beyond owned roster capacity is refused without mutation")
	check(str(bought.message).contains("register"),"Refusal explains the separate fleet register")
	check(not c.commission(id).ok and same(snapshot,c.state),"Commission beyond owned roster capacity is refused without taking coins or materials")
	c.state.recoverable={"hull":id,"claimed":false}
	snapshot=c.state.duplicate(true)
	check(not c.salvage_boat(id).ok and same(snapshot,c.state),"Salvage beyond owned roster capacity is refused and the wreck stays unclaimed")
	p.buildQueue.append({"id":"fleet-points-test","hull":id,"owner":"player","ready":true,"escrow":0})
	snapshot=c.state.duplicate(true)
	check(not c.collect_boat(p.buildQueue.size()-1).ok and same(snapshot,c.state),"Finished hull stays on the slip while the owned roster is full")
	p.buildQueue.pop_back()

func _test_legacy_save() -> void:
	c.new_game(123)
	var legacy: Dictionary=copy_json(c.state)
	legacy.version="0.001"
	var heavy: Dictionary=dearest_hull()
	var raw_points: int=0
	for i in range(7):
		var boat: Dictionary=Damage.create_ship(heavy)
		boat.uid="boat-%d"%(i+2)
		boat.mothballed=false
		legacy.fleet.append(copy_json(boat))
	legacy.nextUid=9
	for boat in legacy.fleet:
		for key in ["baseSpec","loadout","refitLocker"]:
			boat.erase(key)
		boat.spec=copy_json(c.hull(boat.type)) # v0.001 stored the plain hull spec
		raw_points+=Deployment.cost(c.hull(boat.type))
	legacy.fleet[1].hp=float(legacy.fleet[1].hp)-50.0
	legacy.fleet[1].ammo=12.5
	legacy.fleet[2].fuel=3.25
	legacy=copy_json(legacy)
	check(legacy.fleet.size()==8 and raw_points>300,"Legacy fixture is an eight-boat over-cap v0.001 roster (%d DP)"%raw_points)
	var validation: Dictionary=V.validate(legacy,world)
	check(validation.ok,"Old save without refit fields validates: "+str(validation.message))
	var before: Dictionary=legacy.duplicate(true)
	check(c.restore(legacy).ok,"Over-cap legacy save restores")
	check(c.state.fleet.size()==8,"No legacy boat is deleted, mothballed or stranded")
	for i in range(8):
		var a: Dictionary=c.state.fleet[i]
		var b: Dictionary=before.fleet[i]
		var kept: bool=a.uid==b.uid and same(a.hp,b.hp) and same(a.ammo,b.ammo) and same(a.fuel,b.fuel) and same(a.supplies,b.supplies) and same(a.crew,b.crew) and a.get("mothballed",false)==b.get("mothballed",false)
		check(kept,"Legacy boat %d keeps identity, damage, stores, crew and status"%i)
		check(a.get("loadout") is Dictionary and a.get("baseSpec") is Dictionary,"Legacy boat %d receives default fitting on load"%i)
	check(c.state.coins==int(before.coins) and c.state.crewPurse==int(before.crewPurse),"Legacy load creates no coins")
	conservation("Legacy restore")
	check(c.fleet_points()>c.fleet_limit(),"Legacy roster stays over the cap rather than being trimmed")
	check(c.can_add_boat(cheapest_hull()),"Legacy owner can expand reserves beyond300 deployment points")
	var split: Dictionary=Deployment.split(c.active_fleet())
	check(split.deployed.size()+split.reserve.size()==c.active_fleet().size() and split.points<=300,"Battle split keeps every legacy boat in deployment or reserve")

func _test_fitted_round_trip() -> void:
	c.new_game(123)
	var boat: Dictionary=c.state.fleet[0]
	var base: Dictionary=c.hull(boat.type)
	var choice: Dictionary=first_alternative(base)
	if not check(not choice.is_empty(),"Catalog offers a non-default armor or engine for the starter hull"):
		return
	boat.loadout=choice.loadout
	c.fit_boat(boat)
	c.apply_morale()
	var expected: Dictionary=Refits.effective_spec(base.duplicate(true),choice.loadout)
	check(same(boat.maxHp,expected.hp) and same(boat.spec.hp,expected.hp) and same(boat.armor,expected.get("armor",boat.armor)),"Fitted boat adopts effective HP and armor")
	boat.hp=maxf(1.0,minf(boat.hp,boat.maxHp)-20.0)
	boat.ammo=17.0
	var points: int=Deployment.cost(boat)
	var hp: float=boat.hp
	var loadout: Dictionary=boat.loadout.duplicate(true)
	var saved: Dictionary=copy_json(c.state)
	saved.fleet[0].spec.damage=9999
	saved.fleet[0].spec.range=99999
	saved.fleet[0].spec.speed=999
	saved.fleet[0].spec.armor=999
	saved.fleet[0].armor=999
	saved.fleet[0].baseSpec.hp=99999
	saved.fleet[0].spec.deploymentPoints=1
	var validation: Dictionary=V.validate(saved,world)
	check(validation.ok,"Fitted save validates (spec is rebuilt, not trusted): "+str(validation.message))
	check(c.restore(saved).ok,"Fitted save restores")
	boat=c.state.fleet[0]
	check(same(boat.loadout,loadout),"Loadout round-trips")
	check(same(boat.spec.damage,expected.damage) and same(boat.spec.range,expected.range),"Tampered weapon stats are rebuilt from the loadout")
	check(same(boat.spec.speed,float(expected.speed)*clampf(c.state.morale/85.0,0.35,1.0)),"Tampered speed is rebuilt and morale-scaled")
	check(same(boat.armor,expected.get("armor",boat.armor)) and same(boat.spec.get("armor",0),expected.get("armor",0)),"Tampered armor is rebuilt")
	check(same(boat.baseSpec.hp,base.hp),"Tampered base spec is replaced by world data")
	check(same(boat.hp,hp) and same(boat.maxHp,expected.hp),"Fitted round-trip does not heal damage")
	check(same(boat.ammo,17.0),"Fitted round-trip does not refill stores")
	check(Deployment.cost(boat)==points,"Deployment points survive round-trip; serialized deploymentPoints ignored")
	conservation("Fitted round-trip")
	var bad: Dictionary=copy_json(c.state)
	bad.fleet[0].maxHp=float(expected.hp)+500.0
	bad.fleet[0].hp=float(expected.hp)+400.0
	var snapshot: Dictionary=c.state.duplicate(true)
	check(not V.validate(bad,world).ok,"Inflated max HP is rejected")
	check(not c.restore(bad).ok and same(snapshot,c.state),"Inflated max HP restore leaves the live voyage unchanged")

func _test_invalid_modules() -> void:
	c.new_game(123)
	var snapshot: Dictionary=c.state.duplicate(true)
	var good: Dictionary=copy_json(c.state)
	var cases: Array=[]
	var bad: Dictionary=good.duplicate(true)
	bad.fleet[0].loadout.armor="no_such_module_v002"
	cases.append([bad,"Unknown armor module"])
	bad=good.duplicate(true)
	bad.fleet[0].loadout.engine="no_such_engine_v002"
	cases.append([bad,"Unknown engine module"])
	bad=good.duplicate(true)
	bad.fleet[0].loadout.weapons=["no_such_weapon_v002"]
	cases.append([bad,"Unknown weapon module"])
	bad=good.duplicate(true)
	bad.fleet[0].loadout="heavy guns please"
	cases.append([bad,"Non-dictionary loadout"])
	bad=good.duplicate(true)
	bad.fleet[0].refitLocker=["no_such_module_v002"]
	cases.append([bad,"Unknown locker module"])
	bad=good.duplicate(true)
	bad.fleet[0].refitLocker="crate"
	cases.append([bad,"Malformed locker"])
	bad=good.duplicate(true)
	bad.fleet[0].baseSpec=[1,2]
	cases.append([bad,"Malformed base spec record"])
	for entry in cases:
		var before: Dictionary=entry[0].duplicate(true)
		check(not V.validate(entry[0],world).ok,entry[1]+" is rejected by validation")
		check(same(entry[0],before),entry[1]+" validation leaves input untouched")
		check(not c.restore(entry[0]).ok and same(snapshot,c.state),entry[1]+" restore leaves live voyage unchanged")
	var ids: Array=V._module_ids().keys()
	ids=ids.filter(func(id):return not str(id).is_empty())
	if check(not ids.is_empty(),"Refit catalog exposes module IDs"):
		var locker: Dictionary=good.duplicate(true)
		locker.fleet[0].refitLocker=[ids[0]]
		check(V.validate(locker,world).ok,"Locker holding a known module validates")
	var uid: String=c.state.fleet[0].uid
	check(not c.refit_boat(uid,"armor","no_such_module_v002").ok and same(snapshot,c.state),"Unknown module install refused without mutation")
	check(not c.refit_boat(uid,"weapon:99","no_such_module_v002").ok and same(snapshot,c.state),"Unknown slot refused without mutation")
	check(not c.refit_boat("boat-999","armor","no_such_module_v002").ok and same(snapshot,c.state),"Unknown boat refused without mutation")

func _test_failed_install_atomicity() -> void:
	c.new_game(123)
	var boat: Dictionary=c.state.fleet[0]
	var choice: Dictionary=first_alternative(c.hull(boat.type))
	if not check(not choice.is_empty(),"Catalog offers a module for the atomicity fixture"):
		return
	var p: Dictionary=home()
	var position: Dictionary=c.state.position.duplicate()
	c.state.position={"x":float(p.x)+400.0,"y":float(p.y)}
	var snapshot: Dictionary=c.state.duplicate(true)
	check(c.current_port().is_empty() and not c.refit_boat(boat.uid,choice.slot,choice.module).ok and same(snapshot,c.state),"Refit away from a harbor is refused without mutation")
	c.state.position=position
	var quote: Dictionary=Refits.quote(p,boat,choice.slot,choice.module)
	check(int(quote.get("cost",0))>0,"Non-default module has a real coin cost")
	# Broke captain: coins move to the harbor business purse (conserved), then the install must fail atomically.
	Money.move(c.state,"coins",p,"cash",int(c.state.coins),"Fixture: captain deposits purse")
	conservation("Broke captain fixture")
	snapshot=c.state.duplicate(true)
	var result: Dictionary=c.refit_boat(boat.uid,choice.slot,choice.module)
	check(not result.ok and same(snapshot,c.state),"Unaffordable install changes no coins, stocks, workers, loadout or locker")
	conservation("Failed install")
	# Explicit stocked/workforce unit fixture: positive install must execute, never skip.
	c.new_game(123)
	boat=c.state.fleet[0]
	p=home()
	p.workforce=200
	p.workers=0
	p.publicWorkers=0
	p.availableWorkers=200
	p.availableSpecialists=40
	p.specialists=40
	for good in p.stocks: p.stocks[good]=100.0
	preload("res://scripts/construction.gd").begin_day(p)
	quote=Refits.quote(p,boat,choice.slot,choice.module)
	var needed: int=maxi(0,int(quote.get("cost",0))-int(c.state.coins))
	Money.move(p,"governmentPurse",c.state,"coins",needed,"Unit fixture treasury transfer")
	check(quote.get("ok",false) and c.state.coins>=int(quote.get("cost",0)),"Funded stocked positive fixture is installable")
	if quote.get("ok",false) and c.state.coins>=int(quote.get("cost",0)):
		var hp: float=boat.hp
		var ammo: float=boat.ammo
		var uid: String=boat.uid
		result=c.refit_boat(boat.uid,choice.slot,choice.module)
		check(result.ok,"Affordable install at a stocked harbor succeeds: "+str(result.message))
		if result.ok:
			boat=c.find_boat(uid)
			var expected: Dictionary=Refits.effective_spec(c.hull(boat.type).duplicate(true),boat.loadout)
			check(same(boat.maxHp,expected.hp) and boat.hp<=hp+0.0001 and same(boat.ammo,ammo),"Install applies effective stats without healing or refilling")
			check(str(boat.loadout.get(choice.slot,""))==choice.module,"Install records the new module in the loadout")
			conservation("Successful install")
