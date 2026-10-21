extends SceneTree
const C=preload("res://scripts/campaign.gd")
const H=preload("res://scripts/home_harbor.gd")
const M=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;print("FAIL home voyage: ",message)
func _initialize():
	var w: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var c=C.new(w);c.new_game(171)
	var p: Dictionary=c.current_port()
	M.move(p,"governmentPurse",c.state,"coins",50000,"Fixture finite operating capital",c.state.moneyLog)
	var supply: int=M.total(c.state)
	var workforce: int=p.workforce
	var q: Dictionary=H.quote(c,"warehouse",p.id)
	check(q.ok and H.establish(c,"warehouse",p.id).ok,"Actual funded staffed warehouse establishes at the existing harbor")
	var b: Dictionary=c.state.businesses[0]
	check(p.workforce==workforce-2 and b.employees.size()==2 and M.total(c.state)==supply,"Staff leave the town and opening capital remains counted once")
	check(c.trade(p.id,"timber",4,"buy").ok and H.transfer_goods(c,b.id,"timber",4,"in").ok,"Actual bought goods store ashore through the campaign hold")
	check(b.inventory.timber==4 and c.state.cargo.timber==0 and b.inKindCapital>0,"Physical goods and material contribution basis have distinct finite records")
	check(not H.dividend(c,b.id,1).ok,"Contributed cash or goods do not count as earned dividends")
	var spare: Dictionary=c.add_boat(c.hull("bilge_punt"),0) # physical uncrewed hull fixture
	check(c.toggle_storage(spare.uid).ok,"Actual stored ownership uses an available staffed berth")
	var day: int=int(c.state.day)
	c.wait_day();c.pending_days=0;c.apply_economy(c.state.ports,[],1)
	check(int(c.state.day)==day+1 and int(b.wagesPaid)==200 and spare.get("storageProvider","")=="Staffed warehouse","Day advancement pays the company's actual workers and covers its private berth")
	check(spare.berthArrears==0 and M.total(c.state)==supply,"Paid private watch creates no duplicate berth fee or coins")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Actual save restores staff, business purse, stock basis and stored hull")
	b=c.state.businesses[0];p=c.current_port();spare=c.find_boat(spare.uid)
	check(H.transfer_goods(c,b.id,"timber",1,"out").ok and b.inventory.timber==3,"Stored inventory loads back into actual available fleet capacity")
	c.state.position=c.port_position("kelp_reach")
	check(not H.capital(c,b.id,100).ok and not H.dividend(c,b.id,100).ok,"Remote capital and dividends require the real home harbor")
	c.state.position=c.port_position(p.id)
	check(c.FleetIdentity.hire_specialist(c,c.state.fleet[0].uid,"surveyor").ok,"Specialist can be hired alongside a shore business")
	var person: String=c.state.specialists[-1].id
	check(c.FleetSupport.dismiss(c,person).ok and c.FleetIdentity.hire_specialist(c,c.state.fleet[0].uid,"surveyor").ok,"A discharged role can be filled again by a newly recruited person")
	c.new_game(172);p=c.current_port();spare=c.add_boat(c.hull("bilge_punt"),0)
	c.toggle_storage(spare.uid)
	var coins: int=c.state.coins
	c.HomeOps.daily(c)
	check(coins-c.state.coins==28*c.HomeOps.slots(spare) and spare.storageProvider=="Public harbor watch","Public storage pays the actual harbor watch and registry tariff")
	M.move(c.state,"coins",p,"governmentPurse",int(c.state.coins),"Fixture empty captain purse",c.state.moneyLog)
	c.HomeOps.daily(c)
	check(spare.berthArrears>0 and not c.toggle_storage(spare.uid).ok,"Unpaid berth rent becomes a liability and prevents free collection")
	M.move(p,"governmentPurse",c.state,"coins",1000,"Fixture funded arrears payment",c.state.moneyLog)
	check(c.HomeOps.pay_arrears(c,spare.uid).ok and c.toggle_storage(spare.uid).ok,"Actual arrears payment releases the preserved stored hull")
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("home-voyage-fixture");scene.new_game();scene.ui.HomeUI.open(scene.ui)
	check(scene.ui.modal_kind=="home_harbor","Actual home-harbor quotes and ledger screen renders")
	scene.queue_free();await process_frame
	print("home voyage: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
