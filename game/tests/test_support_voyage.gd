extends SceneTree
const C=preload("res://scripts/campaign.gd")
const B=preload("res://scripts/battle.gd")
const D=preload("res://scripts/deployment.gd")
const M=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;print("FAIL support voyage: ",message)
func _initialize():
	var w: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var c=C.new(w);c.new_game(151)
	var p: Dictionary=c.current_port()
	M.move(p,"governmentPurse",c.state,"coins",50000,"Fixture paid operating capital transfer",c.state.moneyLog)
	var supply: int=M.total(c.state)
	var boat: Dictionary=c.state.fleet[0]
	var site: Dictionary=c.state.exploration.catalog[0]
	c.Exploration.discover_near(c.state,site,1)
	var before: float=c.Exploration.quote(c.state,site.id,"chart").days
	check(c.FleetIdentity.install_conversion(c,boat.uid,"survey_rig").ok,"Actual paid survey conversion installs")
	var specialists: int=p.specialists
	check(c.FleetIdentity.hire_specialist(c,boat.uid,"surveyor").ok and p.specialists==specialists-1,"Specialist occupies a berth and leaves the permanent harbor expert pool")
	c.fit_boat(boat);c.apply_morale()
	check(c.Exploration.quote(c.state,site.id,"chart").days<before,"Fitted survey room and paid surveyor shorten actual survey work")
	var base: float=boat.spec.surveyFactor
	for i in range(8):c.apply_morale()
	check(boat.spec.surveyFactor==base,"Canonical morale publication does not stack support bonuses")
	c.apply_economy(c.state.ports,[],1)
	check(c.state.specialists[0].coins==75 and M.total(c.state)==supply,"Real daily base payroll plus professional premium count each coin once")
	check(c.FleetSupport.reserve(c,boat.uid).ok and D.split(c.active_fleet()).points==0 and D.split(c.active_fleet()).reserve.size()==1,"Traveling support retains its hold while staying outside combat deployment")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Actual save restores conversion, support policy, specialist purse and paid benefits")
	boat=c.state.fleet[0]
	c.FleetSupport.reserve(c,boat.uid)
	check(c.FleetSupport.dismiss(c,c.state.specialists[0].id).ok and M.total(c.state)==supply,"Discharge transfers actual savings ashore and reconciles specialist workforce")
	var fuel_before: float=boat.fuel
	check(c.FleetIdentity.install_conversion(c,boat.uid,"auxiliary_tanks").ok and boat.spec.fuelCapacity==90 and boat.fuel==fuel_before,"Auxiliary tank is real fitted storage and never grants free fuel")
	var tow: Dictionary=c.add_boat(c.hull("bilge_punt"),0) # disabled physical-hull fixture, with no stores or crew
	tow.towed=true;tow.needsHarborRepair=true;tow.towSpeedFactor=0.55
	var tow_speed: float=c.travel_speed()
	check(c.FleetIdentity.install_conversion(c,boat.uid,"tug_rig").ok,"Paid tug conversion uses real parts and professional labor")
	check(c.travel_speed()>tow_speed,"Actual tow travel improves with the paid tug aboard")
	if boat.get("supportOnly",false):check(c.FleetSupport.reserve(c,boat.uid).ok,"Paid tug can return to combat deployment")
	check(not boat.supportOnly,"Paid tug is in combat deployment for the protected passage")
	var ally: Dictionary=c.fleet_owner("patrol-1")
	var enemy: Dictionary=c.fleet_owner("patrol-0")
	for ship in c.active_fleet()+ally.boats+enemy.boats:ship.ammo=0
	# Current escort contract: actual loaded carriers must physically reach a
	# certified exit. A timed survival flag does not establish cargo passage.
	var mission: Dictionary=c.EscortOps._mission(c,ally,"escort")
	mission.allyUids=ally.boats.map(func(s):return s.uid)
	mission.exit={"x":800.0,"y":850.0,"radius":170.0}
	var battle: Dictionary=B.create({"fleet":ally.boats+c.FleetSupport.combat(c),"enemyFleet":enemy.boats,"mission":mission,"islands":[],"seed":18})
	check(not mission.has("startError") and str(battle.get("startError",""))=="" and battle.has("convoy") and battle.result==null,"Loaded convoy and an actual combat escort deploy without an instant passage win")
	for i in range(1400):
		if battle.result!=null:break
		B.update(battle,1.0/30.0,{})
	print("support passage diagnostic ",JSON.stringify({"result":battle.result,"time":battle.time,"startError":battle.get("startError",mission.get("startError","")),"outcome":battle.get("convoyOutcome",{})}))
	check(battle.result=="won" and battle.objectiveOnly and battle.get("objectiveSuccess",false) and int(battle.get("convoyOutcome",{}).get("escaped",0))==int(battle.get("convoyOutcome",{}).get("total",-1)) and enemy.boats.any(func(s):return not s.sunk),"Protect objective wins through actual loaded-carrier exit passage while the enemy survives")
	check(battle.deployment.player<=300 and battle.deployment.enemy<=300,"Allied convoy shares the same per-side deployment budget")
	var purse: int=c.state.coins
	var context: Dictionary={"kind":"escort","ownerId":enemy.id,"allyOwnerId":ally.id,"escortEvent":"fixture-passage","objectiveOnly":true}
	var report: Dictionary=c.battle_settled("won",enemy.boats.map(func(s):return s.spec),context,battle)
	check(c.state.coins==purse and enemy.active and not c.state.defeatedOwners.has(enemy.id),"Protection victory does not loot or falsely destroy the surviving enemy company")
	check(c.state.campaignFacts.escortsSaved==1 and M.total(c.state)==supply,"Actual protected passage records one future campaign fact with conserved money")
	c.EscortOps.settled(c,"won",context,report.get("convoy",{}))
	check(c.state.campaignFacts.escortsSaved==1,"Same passage cannot farm completion credit")
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("support-voyage-fixture");scene.new_game()
	scene.ui.IdentityUI.open(scene.ui,scene.core.state.fleet[0].uid)
	check(scene.ui.modal_kind=="fleet_identity","Actual role, conversion, specialist and history screen renders")
	scene.queue_free();await process_frame
	print("support voyage: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
