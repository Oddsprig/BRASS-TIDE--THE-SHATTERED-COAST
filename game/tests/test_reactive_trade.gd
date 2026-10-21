extends SceneTree
const C=preload("res://scripts/campaign.gd")
const M=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;print("FAIL reactive trade: ",message)
func _initialize():
	var w: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var c=C.new(w);c.new_game(141)
	var supply: int=M.total(c.state)
	var dock: Dictionary=c.port("anvil_dock")
	c.state.position=c.port_position(dock.id);c.state.path=[]
	c.TradeFlow.observe(c)
	var recorded: Dictionary=c.TradeIntel.report(c,dock.id)
	var observed_iron: float=recorded.stocks.iron
	dock.stocks.iron=0
	check(c.TradeIntel.report(c,dock.id).stocks.iron==observed_iron,"Recorded remote market remains dated rather than reading changed stock")
	var h: Dictionary=c.hull(dock.shipIds[0])
	var materials: Dictionary=c.ship_materials(h)
	for good in materials:dock.stocks[good]=float(materials[good])+5
	dock.stocks.iron=0
	M.move(dock,"governmentPurse",c.state,"coins",mini(150000,int(dock.governmentPurse)),"Fixture operating capital transfer",c.state.moneyLog)
	c.Factions.adjust(c.state,dock.faction,20,"Fixture earned yard access")
	check(not c.commission(h.id).ok,"Actual yard refuses a hull lacking iron")
	var convoy: Dictionary=c.fleet_owner("patrol-1")
	convoy.tradeGood="iron";convoy.tradeCargo=ceili(float(materials.iron))+1
	convoy.cargo.iron=convoy.tradeCargo
	var before: int=c.state.coins
	c.Fleets.dock(convoy,dock)
	check(dock.stocks.iron>=float(materials.iron) and convoy.tradeCargo==0,"Arriving real convoy sells finite iron into the actual yard inventory")
	check(c.commission(h.id).ok and dock.buildQueue.size()==1,"That physical shipment permits a funded construction order")
	check(c.state.coins<before and M.total(c.state)==supply,"Delivery, construction bill and escrow conserve all actual coins")
	var raider: Dictionary=c.fleet_owner("patrol-0")
	var p: Dictionary=c.NavalAI._find_patrol(c.state,raider.id)
	p.x=dock.x;p.y=dock.y;p.active=true;p.progress=0.5
	c.state.position=c.port_position("kelp_reach")
	for other in c.state.patrols:
		if other.id!=p.id:other.x=200+700*c.state.patrols.find(other);other.y=250
	raider.boats[0].fuel=8;raider.boats[0].ammo=50
	c.TradeFlow.daily(c)
	check(dock.blockaded and dock.id in c.TradeFlow.blockades(c),"Actual supplied hostile hull establishes the economy blockade flag")
	raider.boats[0].fuel=0;c.TradeFlow.daily(c)
	check(not dock.blockaded,"Fuel starvation lifts that actual blockade")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Actual save schema preserves observed prices and reactive blockade state")
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("reactive-trade-fixture");scene.new_game();scene.ui.open_port()
	scene.ui.TradeUI.open(scene.ui)
	check(scene.ui.modal_kind=="trade_intel" and scene.core.state.tradeIntel.observations.size()==1,"Real harbor visit records a quote and trade screen renders it")
	scene.queue_free();await process_frame
	print("reactive trade: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
