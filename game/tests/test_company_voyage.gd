extends SceneTree
const Money=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL company voyage: "+text)
func advance(scene,seconds: float,finished: Callable=Callable()) -> void:
	var c=scene.core
	for i in range(ceili(seconds*4)):
		c.step(0.25)
		if c.pending_days>0:scene.sync_economy()
		if finished.is_valid() and finished.call():break
		if i%100==0:await process_frame
func _initialize() -> void:
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("company-voyage-fixture")
	scene.new_game();scene.set_process(false);scene.set_physics_process(false)
	var c=scene.core
	var home: Dictionary=c.current_port()
	Money.move(home,"governmentPurse",c.state,"coins",300000,"Finite charter fixture capital",c.state.moneyLog)
	var supply: int=Money.total(c.state)
	# Isolate deterministic route commerce; other actual purses/crews are
	# preserved in inactive standby. Existing naval tests cover hostile combat.
	for owner in c.state.fleetOwners:owner.active=false
	for patrol in c.state.patrols:patrol.active=false
	check(c.buy_boat("tin_skiff").ok,"First real spare hull and local minimum crew purchased")
	var first_uid: String=c.state.fleet[-1].uid
	c.state.position=c.port_position("kelp_reach")
	check(c.buy_boat("tin_skiff").ok,"Second real spare hull purchased from another actual yard stock")
	var second_uid: String=c.state.fleet[-1].uid
	c.state.position=c.port_position(home.id)
	check(c.refit_boat(first_uid,"engine","economy_drive").ok,"Actual material-and-labor engine refit is paid before assignment")
	var first_ref: Dictionary=c.find_boat(first_uid)
	var second_ref: Dictionary=c.find_boat(second_uid)
	var all_people: float=first_ref.crew+second_ref.crew+c.state.fleet[0].crew
	var limits: Dictionary={"buyMax":10000,"sellMin":0,"maxCargo":10.0,"reserve":4000,"risk":0.4}
	var r: Dictionary=c.CompanyOps.create(c,[first_uid],"kelp_reach","timber",30000,limits)
	check(r.ok,"First actual company charter: "+str(r.get("message","")))
	if not r.ok:scene.queue_free();await process_frame;quit(1);return
	var ids: Array=c.state.shippingCompanies.keys()
	var first: String=str(ids[0])
	r=c.CompanyOps.create(c,[second_uid],"sawtooth_mill","iron",30000,limits)
	check(r.ok,"Second concurrent actual route charter: "+str(r.get("message","")))
	if not r.ok:scene.queue_free();await process_frame;quit(1);return
	ids=c.state.shippingCompanies.keys();var second: String=str(ids[1])
	var a: Dictionary=c.fleet_owner(first);var b: Dictionary=c.fleet_owner(second)
	check(c.state.fleet.size()==1 and is_same(a.boats[0],first_ref) and is_same(b.boats[0],second_ref),"Assigned hull dictionaries leave player capacity exactly once")
	check(c.state.fleet[0].crew+a.boats[0].crew+b.boats[0].crew==all_people,"Masters are existing numerical crew, not extra people")
	check(a.boats[0].loadout.engine=="economy_drive" and float(a.boats[0].spec.fuelUse)<1,"Actual company hull retains the purchased engine fitting")
	check(c.Fleets.upkeep(a).wages==float(a.boats[0].crew)*100+75,"Company payroll includes the existing master at the foreman wage anchor")
	check(Money.total(c.state)==supply and float(a.tradeCargo)>0 and float(b.tradeCargo)>0,"Real purses pay for physically loaded route cargo")
	var x: float=float(c.CompanyOps.api(c)._patrol(c.state,first).x)
	await advance(scene,10)
	check(float(c.CompanyOps.api(c)._patrol(c.state,first).x)!=x,"The company actually moves along its water route")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"At-sea companies, routes, inventory basis and fitted hulls save/load")
	a=c.fleet_owner(first);b=c.fleet_owner(second)
	check(a.boats[0].loadout.engine=="economy_drive" and float(a.boats[0].spec.fuelUse)<1,"Canonical NPC restoration preserves owned fitting performance")
	await advance(scene,350,func():return int(c.state.shippingCompanies[first].revenue)>0 and int(c.state.shippingCompanies[second].revenue)>0 and int(c.state.econDay)>=3)
	var ab: Dictionary=c.state.shippingCompanies[first];var bb: Dictionary=c.state.shippingCompanies[second]
	check(int(ab.revenue)>0 and int(bb.revenue)>0,"Two real routes arrive and sell actual commercial cargo")
	check(int(ab.operating)>0 and int(ab.netProfit)==int(ab.revenue)-int(ab.cogs)-int(ab.operating),"Net result accounts for paid operation and sold materials, not invested capital")
	check(Money.total(c.state)==supply,"Autonomous voyages, wages, provisioning and sales conserve world coins")
	var patrol: Dictionary=c.CompanyOps.api(c)._patrol(c.state,first)
	var before: Vector2=Vector2(patrol.x,patrol.y)
	check(c.CompanyOps.recall(c,first).ok and before.distance_to(Vector2(patrol.x,patrol.y))<=40,"Recall orders physical return; only an in-harbor berth snap is permitted")
	check(c.CompanyOps.recall(c,second).ok,"Second actual operation can also be recalled")
	await advance(scene,350,func():return c.CompanyOps.api(c)._docked(c,c.fleet_owner(first),"brass_haven") and c.CompanyOps.api(c)._docked(c,c.fleet_owner(second),"brass_haven"))
	a=c.fleet_owner(first);b=c.fleet_owner(second)
	check(c.CompanyOps.api(c)._docked(c,a,"brass_haven") and c.CompanyOps.api(c)._docked(c,b,"brass_haven"),"Both companies physically arrive at the actual home harbor")
	first_ref=a.boats[0];first_ref.hp-=3
	var damaged_hp: float=float(first_ref.hp)
	check(c.CompanyOps.collect(c,first).ok and is_same(c.find_boat(first_uid),first_ref) and c.find_boat(first_uid).hp==damaged_hp,"Collection returns the same still-damaged hull without a heal or duplicate")
	check(c.find_boat(first_uid).loadout.engine=="economy_drive" and Money.total(c.state)==supply,"Returned fitting, cargo, purse and crew savings remain actual property")
	var lost: Dictionary=b.boats[0];lost.sunk=true;lost.hp=0;lost.crew=0;lost.wounded=0
	var wrecks: int=c.state.wrecks.size()
	c.wait_day();scene.sync_economy();b=c.fleet_owner(second)
	check(b.boats.size()==1 and b.boats[0].uid==second_uid and b.boats[0].sunk and not b.active,"Injected real hull loss remains the same finite sunk record, with no replacement")
	check(c.state.wrecks.size()>wrecks and int(c.state.shippingCompanies[second].operating)>=int(b.hullBasis[second_uid].value),"Loss creates a persistent actual wreck and charges its declared hull capital basis")
	check(c.Fleets.subsidize(b,c.port("brass_haven"),1000)==0 and not c.NavalAI.request_replacement(c,b,c.port("brass_haven")).ok,"Private companies cannot take public replacement subsidies or spawn hulls")
	check(Money.total(c.state)==supply and c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Loss, accounts, owners and wrecks preserve world coins and full save integrity")
	var malformed: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	malformed.fleetOwners.filter(func(o):return o.id==second)[0].workingBasis.fuel.cost=INF
	check(not c.restore(malformed).ok,"Nonfinite working inventory cost is refused before restore")
	var food_company: Dictionary=c.CompanyOps.create(c,[first_uid],"kelp_reach","food",12000,limits)
	check(food_company.ok,"Actual returned hull can charter a shared-commodity food route: "+str(food_company.get("message","")))
	if food_company.ok:
		var food_id: String=str(c.state.shippingCompanies.keys()[-1])
		var food_owner: Dictionary=c.fleet_owner(food_id)
		check(float(food_owner.cargo.food)>float(c.state.shippingCompanies[food_id].basisQty),"Crew provisions and commercial food share one physical inventory with separate paid ownership basis")
		await advance(scene,55)
		check(Money.total(c.state)==supply and c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Real food trade, sailor eating and working-stock accounts reconcile through saved daily operations")
	scene.ui.CompanyUI.open(scene.ui)
	check(scene.ui.modal_kind=="shipping_companies","Actual charter, voyage estimate, route account and physical recall controls render")
	scene.queue_free();await process_frame
	print("company voyage: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
