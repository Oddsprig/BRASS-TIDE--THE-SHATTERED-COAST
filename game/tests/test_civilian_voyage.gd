extends SceneTree
const Money=preload("res://scripts/money.gd")
const Regional=preload("res://scripts/regional_goods.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL civilian voyage: "+text)
func _initialize() -> void:
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("civilian-voyage-fixture")
	scene.new_game();scene.set_process(false);scene.set_physics_process(false)
	var c=scene.core
	var supply: int=Money.total(c.state)
	for p in c.state.ports:
		for good in Regional.IDS:check(float(p.stocks[good])==0,"No free new starting commodity: "+str(p.id)+"/"+good)
	var legacy: Dictionary=c.state.duplicate(true);legacy.erase("economyGoodsRevision");legacy.version="0.022"
	for good in Regional.IDS:
		legacy.cargo.erase(good)
		for p in legacy.ports:p.stocks.erase(good);p.publicStores.erase(good)
		for owner in legacy.fleetOwners:owner.cargo.erase(good)
	var original: String=JSON.stringify(legacy)
	check(c.restore(legacy).ok and JSON.stringify(legacy)==original,"Actual old save receives only zero columns on a copied snapshot")
	check(Money.total(c.state)==supply and c.state.economyGoodsRevision==1,"Zero-column migration preserves canonical world coins")
	for day in range(3):c.wait_day();scene.sync_economy()
	var p: Dictionary=c.port("sawtooth_mill")
	var r: Dictionary=Regional.report(p)
	check(r.lastWages>0 and r.lastProduction.has("fine_timber") and r.lastSpent>0,"Actual timber port pays workers, finishes existing planks and sells to real households")
	check(Money.total(c.state)==supply,"Geographic production and household buying conserve every world coin")
	check(int(p.lastPayroll.total)==int(p.lastPayroll.household)+int(p.lastPayroll.expert)+int(p.lastPayroll.tax),"Expanded paid-work summary reconciles actual net wage recipients and tax")
	c.state.position=c.port_position(p.id);c.state.path=[]
	var before: float=float(p.stocks.fine_timber)
	var trade: Dictionary=c.trade(p.id,"fine_timber",1,"buy")
	check(trade.ok and float(p.stocks.fine_timber)==before-1 and float(c.state.cargo.fine_timber)==1,"Actual market sale removes the same physical finished-timber lot: "+str(trade.message))
	var carried: Dictionary=c.state.duplicate(true);c.Manifest.allocate(carried)
	carried.fleet[0].sunk=true;c.Manifest.losses(carried)
	check(float(carried.cargo.fine_timber)==0,"New civilian cargo is lost with its actual assigned carrier")
	var offers: Array=c.VoyageJobs.available(c)
	var offer: Dictionary={}
	for job in offers:
		if job.kind=="freight" and job.freight.good in Regional.IDS:offer=job;break
	check(not offer.is_empty(),"Solvent government can sponsor an actual regional freight lot")
	if not offer.is_empty():
		var good: String=offer.freight.good
		var amount: float=float(offer.freight.qty)
		before=float(p.stocks[good])
		check(c.VoyageJobs.accept(c,str(offer.id)).ok and float(p.stocks[good])==before-amount,"Sponsored freight buys the same local physical inventory")
		var destination: Dictionary=c.port(str(offer.targetPort));before=float(destination.stocks[good])
		c.state.position=c.port_position(str(destination.id))
		check(c.VoyageJobs.finish(c,str(offer.id)).ok and float(destination.stocks[good])==before+amount,"Only actual destination arrival unloads the regional sealed lot")
	check(Money.total(c.state)==supply and c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Expanded markets, manifests, job receipts and fractions pass real save/load")
	var bad: Dictionary=JSON.parse_string(JSON.stringify(c.state));bad.cargo.erase("fine_timber")
	check(not c.restore(bad).ok,"A revisioned save cannot silently refill a missing column")
	scene.ui.RegionalGoodsUI.open(scene.ui)
	check(scene.ui.modal_kind=="regional_goods","Actual regional bills, production and household-purchase reports render")
	scene.queue_free();await process_frame
	print("civilian voyage: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
