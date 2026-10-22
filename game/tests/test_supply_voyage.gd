extends SceneTree
const R=preload("res://scripts/harbor_reserves.gd")
const M=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL supply voyage: "+text)
func _initialize() -> void:
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("supply-voyage-fixture")
	scene.new_game();scene.set_process(false);scene.set_physics_process(false)
	var c=scene.core
	var p: Dictionary=c.current_port()
	var total: int=M.total(c.state)
	var r: Dictionary=R.report(p)
	check(r.resupplyDays>=1 and r.resupplyDays<=14 and r.goods.food.dailyDemand>0,"Actual coast gets a bounded route horizon and household demand")
	var owned: float=float(p.stocks.food)
	var available: int=floori(R.exportable(p,"food"))
	var before: String=JSON.stringify(c.state)
	check(not c.trade(p.id,"food",ceili(owned),"buy").ok and before==JSON.stringify(c.state),"Protected stock cannot be bought through the actual trade path")
	check(available>=1 and c.trade(p.id,"food",1,"buy").ok,"Real surplus remains purchasable")
	check(M.total(c.state)==total and float(p.stocks.food)==owned-1,"Trading moves one actual lot and conserves coins")
	check(not c.ReserveOps.policy(c,"commercial").ok,"A neutral visiting captain cannot command town reserve policy")
	c.Factions.adjust(c.state,p.faction,25,"Supply fixture earned friendly standing","supply-test")
	check(c.ReserveOps.policy(c,"commercial").ok,"A friendly harbor partner can advise commercial policy")
	var government_food: float=float(p.publicStores.food)
	var private_food: float=float(p.stocks.food)
	check(c.ReserveOps.release_food(c).ok,"Approved release hires actual available office staff")
	check(float(p.publicStores.food)<government_food and is_equal_approx(float(p.publicStores.food)+float(p.stocks.food),government_food+private_food) and M.total(c.state)==total,"Public release transfers physical stock and real fees once")
	c.wait_day();scene.sync_economy()
	p=c.current_port();r=R.report(p)
	check(M.total(c.state)==total and r.goods.food.dailyDemand>0,"Copied daily production, stock priorities and consumption reconcile")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Coverage settings and real inventories restore through actual preflight")
	var bad: Dictionary=c.state.duplicate(true);bad.ports[0].reserves.resupplyDays=-1
	var held: String=JSON.stringify(c.state)
	check(not c.restore(bad).ok and JSON.stringify(c.state)==held,"Malformed reserve settings refuse before live mutation")
	scene.ui.SupplyUI.open(scene.ui)
	check(scene.ui.modal_kind=="harbor_reserves","Real reserve report renders in the harbor UI")
	scene.queue_free();await process_frame
	print("supply voyage: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
