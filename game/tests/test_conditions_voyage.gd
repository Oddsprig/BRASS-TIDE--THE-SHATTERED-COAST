extends SceneTree
const Money=preload("res://scripts/money.gd")
const Home=preload("res://scripts/home_harbor.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL conditions voyage: "+text)
func deliver(c,port_id: String,good: String,quantity: int,business_id: String="") -> bool:
	var left: int=quantity
	for leg in range(40):
		if left<=0:return true
		var moved: bool=false
		for source in c.state.ports:
			if source.id==port_id:continue
			var available: int=floori(c.ReserveOps.Reserves.exportable(source,good))
			var room: int=floori(maxf(0,c.capacity()-c.cargo_weight())/float(c.Economy.GOODS[good].weight))
			var count: int=mini(left,mini(available,room))
			if count<=0:continue
			c.state.position=c.port_position(source.id)
			var bought: Dictionary=c.trade(source.id,good,count,"buy")
			if not bought.ok:continue
			c.state.position=c.port_position(port_id)
			var result: Dictionary=Home.transfer_goods(c,business_id,good,count,"in") if not business_id.is_empty() else c.trade(port_id,good,count,"sell")
			if not result.ok:print("Fixture delivery refused: ",result.message);return false
			left-=count;moved=true;break
		if not moved:return false
	return left<=0


func _initialize() -> void:
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("conditions-voyage-fixture")
	scene.new_game();scene.set_process(false);scene.set_physics_process(false)
	var c=scene.core
	var p: Dictionary=c.current_port()
	Money.move(p,"governmentPurse",c.state,"coins",150000,"Finite working-conditions fixture capital",c.state.moneyLog)
	var supply: int=Money.total(c.state)
	c.state.exploration.sites.cinder_workshop_ruin={"level":3,"rewarded":true}
	c.state.storyRights.workshopCharter=true
	var result: Dictionary=Home.establish(c,"workshop",p.id)
	check(result.ok,"Actual staffed workshop starts: "+str(result.message))
	if not result.ok:scene.queue_free();await process_frame;quit(1);return
	var b: Dictionary=c.state.businesses[0]
	check(Home.capital(c,b.id,30000).ok,"Capital is an actual owned-purse transfer")
	check(deliver(c,p.id,"timber",10,b.id) and deliver(c,p.id,"iron",4,b.id) and deliver(c,p.id,"food",16,b.id) and deliver(c,p.id,"supplies",2,b.id),"Actual purchased inputs and employee relief reach the private workshop")
	b.autoSell=false
	var wages: int=int(b.wagesPaid)
	var made: float=float(b.inventory.get("supplies",0))
	check(c.WorkerOps.policy(c,b.id,"overtime").ok,"Home policy saves a funded rush shift")
	c.wait_day();scene.sync_economy();b=c.state.businesses[0];p=c.current_port()
	check(float(b.workFactor)==1.25 and int(b.labor.fatigue)==10 and float(b.inventory.supplies)-made>=7,"Actual paid rush produces more kits and fatigue")
	check(int(b.wagesPaid)-wages==789 and Money.total(c.state)==supply,"Three carpenters and one mechanic receive their actual base and half-wage premiums")
	check(p.has("lastFoodMet") and int(p.lastPaid)<=int(p.lastEmployed) and c.WorkerOps.Conditions.report(p).valid,"Town conditions use copied-port actual purchase and payroll facts")
	check(c.WorkerOps.policy(c,b.id,"rest").ok,"A paid rest shift can be chosen")
	made=float(b.inventory.supplies);wages=int(b.wagesPaid)
	c.wait_day();scene.sync_economy();b=c.state.businesses[0]
	check(float(b.inventory.supplies)==made and int(b.wagesPaid)-wages==525 and int(b.labor.fatigue)==0,"Paid rest consumes elapsed time and wages without output")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Actual shifted workplace and town facts survive full save preflight")
	b=c.state.businesses[0];p=c.current_port()
	c.WorkerOps.policy(c,b.id,"normal")
	Money.move(b,"coins",p,"cash",int(b.coins),"Fixture transfers exhausted working capital to actual seller",c.state.moneyLog)
	for day in range(3):c.wait_day();scene.sync_economy()
	b=c.state.businesses[0]
	check(b.paused and b.labor.striking and int(b.arrearsHousehold)+int(b.arrearsExpert)==1575,"Three actual unpaid days explain a persistent work stoppage")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Strike and actual debt persist through save/load")
	b=c.state.businesses[0];p=c.current_port()
	Home.capital(c,b.id,12000)
	c.state.position=c.port_position("kelp_reach")
	check(not c.WorkerOps.negotiate(c,b.id).ok,"Remote captain cannot negotiate a home workforce")
	c.state.position=c.port_position(p.id)
	result=c.WorkerOps.negotiate(c,b.id)
	check(result.ok,"Actual registry, food, kit and purse fund negotiation: "+str(result.message))
	check(int(b.arrearsHousehold)+int(b.arrearsExpert)==0 and b.labor.striking and int(b.labor.restDays)==2,"Paying the debt keeps the two-day recovery obligation")
	made=float(b.inventory.supplies)
	for day in range(2):
		c.wait_day();scene.sync_economy();b=c.state.businesses[0]
		check(b.labor.striking and float(b.inventory.supplies)==made,"No output during actual negotiated paid rest day "+str(day+1))
	c.wait_day();scene.sync_economy();b=c.state.businesses[0]
	check(not b.labor.striking and not b.paused and float(b.inventory.supplies)>made,"Work resumes only after elapsed paid recovery")
	check(Money.total(c.state)==supply,"Wages, negotiation and relief preserve every world coin")
	var bad: Dictionary=JSON.parse_string(JSON.stringify(c.state));bad.businesses[0].labor.fatigue=101
	check(not c.restore(bad).ok,"Malformed labor scores are refused before state replacement")
	scene.ui.WorkerUI.open(scene.ui)
	check(scene.ui.modal_kind=="worker_conditions","Real harbor conditions and owned shift controls render")
	scene.queue_free();await process_frame
	print("conditions voyage: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
