extends SceneTree
const M=preload("res://scripts/money.gd")
const Home=preload("res://scripts/home_harbor.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL industrial voyage: "+text)
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
	scene.save_directory=OS.get_user_data_dir().path_join("industrial-voyage-fixture")
	scene.new_game();scene.set_process(false);scene.set_physics_process(false)
	var c=scene.core
	var home: Dictionary=c.current_port()
	M.move(home,"governmentPurse",c.state,"coins",150000,"Finite industrial fixture capital",c.state.moneyLog)
	var supply: int=M.total(c.state)
	var site: Dictionary=c.Exploration.catalog_site(c.state,"cinder_workshop_ruin")
	c.state.exploration.sites[site.id]={"level":3,"rewarded":true}
	c.state.position={"x":site.x,"y":site.y}
	var capacity_before: float=float(c.state.fleet[0].spec.cargo)
	c.state.fleet[0].spec.cargo=3.0
	check(not c.ToolingOps.begin(c,site.id,"machine_tools").ok,"Equipment requires one real carrier hold, not fractional virtual carriage")
	c.state.fleet[0].spec.cargo=capacity_before
	var before_kits: float=float(c.state.fleet[0].supplies)
	check(c.ToolingOps.begin(c,site.id,"machine_tools").ok,"Actual fully surveyed source accepts an existing spare crew")
	check(float(c.state.fleet[0].supplies)==before_kits-1 and int(c.state.fleet[0].shoreCrew)==2,"Recovery consumes real kits and reserves crew as a subset")
	check(not c.ToolingOps.claim(c).ok and not c.chart_course(c.port_position("anvil_dock")).ok,"Unfinished recovery refuses claim and sailing")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Actual active recovery job survives full save preflight")
	for day in range(2):c.wait_day();scene.sync_economy()
	check(c.ToolingOps.claim(c).ok and c.state.toolingRecovery.is_empty(),"Elapsed real economic days and ordinary payroll permit machinery claim")
	check(M.total(c.state)==supply and c.state.tooling.items.size()==1,"Recovery neither duplicates coins nor machinery")
	var item: Dictionary=c.state.tooling.items[0]
	check(item.location=="cargo" and c.cargo_weight()>=4 and c.state.cargoManifest.values().any(func(v):return v is Dictionary and v.has("@tool:"+str(item.id))),"Physical machine uses a single carrier's hold manifest")
	var p: Dictionary=c.port("anvil_dock");c.state.position=c.port_position(p.id);c.state.path=[]
	c.state.storyRights.workshopCharter=true
	c.Factions.adjust(c.state,p.faction,25,"Fixture earned workshop partnership","industry-fixture")
	# The shipyard consumed its iron on engines. A real paid cargo delivery
	# supplies both workshop construction and the later bay; no fixture stock mint.
	for leg in range(2):
		c.state.position=c.port_position("cinder_quay")
		var purchase: Dictionary=c.trade("cinder_quay","iron",6,"buy")
		check(purchase.ok,"Buy a hold-limited foundry iron load: "+str(purchase.message))
		c.state.position=c.port_position(p.id)
		var delivery: Dictionary=c.trade(p.id,"iron",6,"sell")
		check(delivery.ok,"Actual cargo delivery supplies the shipyard: "+str(delivery.message))
	var established: Dictionary=Home.establish(c,"workshop",p.id)
	check(established.ok,"Actual paid chartered workshop can be established: "+str(established.message))
	if not established.ok:
		scene.queue_free();await process_frame;quit(1);return
	var b: Dictionary=c.state.businesses[0]
	check(Home.capital(c,b.id,60000).ok,"Business receives real operating capital without income")
	var q: Dictionary=c.ToolingOps.Tooling.quote_install(c,item.id,b.id)
	check(q.ok,"Actual workshop installation bill is feasible: "+str(q.get("message","")))
	var workers: int=int(p.workforce)
	check(c.ToolingOps.Tooling.install(c,item.id,b.id).ok and int(p.workforce)==workers-int(q.get("workers",0)),"Paid installation reserves actual town workers")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Commissioning staff and spent material bills restore")
	for day in range(2):c.wait_day();scene.sync_economy()
	p=c.port("anvil_dock");b=c.state.businesses[0];item=c.state.tooling.items[0]
	check(item.location=="active" and int(p.workforce)==workers,"Elapsed commissioning returns its staff once")
	check(deliver(c,p.id,"timber",4,b.id) and deliver(c,p.id,"iron",1,b.id),"Paid hold-limited supplies reach the actual private workshop")
	check(float(b.inventory.get("timber",0))>=4 and float(b.inventory.get("iron",0))>=1,"Owned inputs remain in private inventory instead of being consumed by public industry")
	b.autoSell=false
	var made_before: float=float(b.inventory.get("supplies",0))
	c.wait_day();scene.sync_economy();p=c.current_port();b=c.state.businesses[0]
	check(float(b.inventory.get("supplies",0))-made_before>=7 and float(b.toolingFactor)>1,"Actual maintained paid carpenters improve the real kit recipe")
	check(M.total(c.state)==supply and int(b.otherExpenses)>0,"Machinery expenses are real transfers and cannot be treated as earned dividends")
	# Supply the public bay immediately before its paid order, while the
	# workshop's own material buffer remains private.
	var bay_supplied: bool=true
	for good in c.YardDevelopment.MATERIALS:
		var missing: int=maxi(0,ceili(float(c.YardDevelopment.MATERIALS[good])-float(p.stocks.get(good,0))))
		if missing>0:bay_supplied=deliver(c,p.id,good,missing) and bay_supplied
	c.state.position=c.port_position(p.id)
	check(bay_supplied,"Actual public shipyard receives its complete finite bay material bill")
	var bay: Dictionary=c.YardDevelopment.quote(c,b.id)
	check(bay.ok,"Real staffed shipyard can quote an added bay: "+str(bay.get("message","")))
	if bay.ok:
		check(c.YardDevelopment.begin(c,b.id).ok and c.YardDevelopment.bays(c.state,p.id)==0,"Paid team and materials begin a real timed bay")
		check(M.total(c.state)==supply and c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Held construction wages count once and load safely")
		for day in range(5):c.wait_day();scene.sync_economy()
		check(c.YardDevelopment.bays(c.state,"anvil_dock")==1 and int(c.state.yardProjects[0].escrow)==0,"Five paid days complete an actual extra chartered building slip")
	var malformed: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	malformed.yardSeq=INF
	check(not c.restore(malformed).ok,"Nonfinite construction sequence is refused before state mutation")
	malformed=JSON.parse_string(JSON.stringify(c.state));malformed.yardProjects[0].householdPaid-=1;malformed.yardProjects[0].escrow+=1
	check(not c.restore(malformed).ok,"Un-earned construction wages cannot pass a balanced forged escrow")
	b=c.state.businesses[0];b.productionProgress=0.5
	var purse_before: int=int(b.coins)
	check(c.ToolingOps.cancel_batch(c,b.id).ok and b.productionProgress==0 and int(b.coins)==purse_before,"Recipe work may be cancelled without refunding earned wages")
	check(M.total(c.state)==supply,"All industrial days conserve the canonical world coin supply")
	scene.ui.ToolingUI.open(scene.ui)
	check(scene.ui.modal_kind=="industrial_tooling","Actual machinery, staff, production and bay controls render")
	scene.queue_free();await process_frame
	print("industrial voyage: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
