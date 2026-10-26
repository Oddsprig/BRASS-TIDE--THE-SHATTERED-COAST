extends SceneTree
## One short v0.037 playable flow. Root alone runs native checks.
const Orders=preload("res://scripts/naval_orders.gd")
const Fleets=preload("res://scripts/fleet_economy.gd")
const Money=preload("res://scripts/money.gd")
const Factions=preload("res://scripts/factions.gd")
const Regional=preload("res://scripts/regional_campaigns.gd")
const RegionalUI=preload("res://scripts/regional_ui.gd")
var checks: int=0
var failures: int=0
var scene
var c

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL operation flow037: ",message)

func same_data(a,b) -> bool:
	if (a is int or a is float) and (b is int or b is float):return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same_data(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in range(a.size()):
			if not same_data(a[i],b[i]):return false
		return true
	return a==b

func button_in(node: Node,caption: String) -> Button:
	if node is Button and node.text==caption:return node
	for child in node.get_children():
		var found: Button=button_in(child,caption)
		if found!=null:return found
	return null

func text_in(node: Node,needle: String) -> bool:
	if node is Label and needle in str(node.text):return true
	for child in node.get_children():
		if text_in(child,needle):return true
	return false

func station(owner: Dictionary,p: Dictionary,home: Dictionary) -> void:
	p.active=true;p.from=home.id;p.to=home.id;p.progress=0.0;p.holding=true
	c.set_patrol_course(p,home,home)
	check(not p.course.is_empty(),"actual hull has a safe home water approach")
	if not p.course.is_empty():p.x=p.course[0].x;p.y=p.course[0].y
	owner.atPort=home.id;owner.progress=0.0
	Orders.build_order(c.state,owner,"patrol",home.id,"Fixture patrol at its real home harbor.")

func _initialize() -> void:
	scene=load("res://main.tscn").instantiate();root.add_child(scene)
	await process_frame
	scene.set_process(false);scene.set_physics_process(false)
	scene.save_directory=OS.get_user_data_dir().path_join("operation-flow-037-%d"%Time.get_ticks_usec())
	scene.new_game();c=scene.core
	check(not c.state.is_empty(),"actual Main publishes an isolated career")
	if not c.state.is_empty():_flow()
	scene.sync_economy();scene.free()
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func _flow() -> void:
	c.new_game(3701);c.state.day=5.25;c.state.econDay=5
	for actor in c.state.patrols:actor.active=false
	var owner: Dictionary=c.fleet_owner("patrol-5")
	var p: Dictionary=Orders.find_patrol(c.state,str(owner.id))
	var home: Dictionary=c.port(str(owner.homePort))
	var other: Dictionary=c.port("anvil_dock")
	station(owner,p,home)
	var convoy: Dictionary=c.fleet_owner("patrol-4")
	var carrier: Dictionary=Orders.find_patrol(c.state,str(convoy.id))
	carrier.active=true;carrier.from=home.id;carrier.to=other.id;carrier.progress=0.2;carrier.holding=false
	c.set_patrol_course(carrier,home,other);c.place_patrol(carrier);convoy.atPort=""
	Orders.build_order(c.state,convoy,"deliver",other.id,"Fixture existing loaded tanker crossing the corridor.")
	check(float(convoy.tradeCargo)>0 and float(convoy.cargo.get(convoy.tradeGood,0))>=float(convoy.tradeCargo),"selected convoy carries its actual paid civilian goods")
	c.state.position={"x":home.x,"y":home.y};c.state.lastPort=home.id;c.state.path=[]
	Factions.adjust(c.state,str(home.faction),25,"Fixture earned local watch mandate")
	var bought: Dictionary=c.trade(str(home.id),"fuel",9,"buy")
	check(bought.ok,"player buys the nine actual fuel drums later delivered through the panel")
	# A market transaction publishes into existing live objects; read them again.
	owner=c.fleet_owner("patrol-5");p=Orders.find_patrol(c.state,str(owner.id));home=c.port(str(owner.homePort))
	c.state.campaignFocus.fromPort=home.id;c.state.campaignFocus.toPort=other.id
	var ids: Array=c.state.fleetOwners.map(func(o):return o.id)
	var hulls: Array=owner.boats.map(func(b):return b.uid)
	var money: int=Money.total(c.state)
	var treasury: int=int(home.governmentPurse)
	var begun: Dictionary=c.RegionalOps.start(c,"corridor")
	check(begun.ok and begun.ownerId==owner.id and int(begun.funded)>0,"existing paid patrol receives the corridor assignment and finite grant")
	if not begun.ok or begun.ownerId!=owner.id:return
	var op: Dictionary=c.state.regionalCampaigns.operations.corridor
	check(int(home.governmentPurse)==treasury-int(begun.funded) and int(home.governmentPurse)>=int(home.publicWorkers)*int(c.Goods.WAGES.laborer)*2,"grant preserves the sponsor's two public-payroll days")
	check(Money.total(c.state)==money and c.state.fleetOwners.map(func(o):return o.id)==ids and owner.boats.map(func(b):return b.uid)==hulls,"assignment conserves all coins, existing owners and physical hulls")
	check(not c.RegionalOps.start(c,"corridor").ok and int(home.governmentPurse)==treasury-int(begun.funded),"active corridor cannot repeat its treasury grant")
	var plan: Dictionary=op.get("currentPlan",{})
	check(plan.get("ready",false) and owner.order.purpose=="escort" and owner.order.targetOwnerId==convoy.id,"shared order screens the real loaded convoy")
	if not plan.get("ready",false):print("PLAN037: ",plan)
	var position: Dictionary={"x":p.x,"y":p.y}
	c.step(1.0)
	check(c.distance(position,p)>1 and not p.holding,"supplied operation advances its real patrol on the live campaign clock")
	check(int(c.state.econDay)==5 and int(op.get("patrolVisits",0))==0,"partial sailing cannot invent a daily tick or endpoint arrival")
	var seq: int=int(owner.orderSeq)
	var journal_size: int=c.state.regionalCampaigns.journal.size()
	c.RegionalOps.refresh(c);c.RegionalOps.refresh(c)
	check(int(owner.orderSeq)==seq and c.state.regionalCampaigns.journal.size()==journal_size,"unchanged observed order does not spam orders or the bounded journal")
	station(owner,p,home)
	# Reassign real fuel to another existing stock ledger, rather than erase it.
	var depot: Dictionary=c.port("brass_haven")
	depot.stocks.fuel+=float(home.stocks.fuel)+float(owner.cargo.fuel)
	home.stocks.fuel=0.0;owner.cargo.fuel=0.0
	for boat in owner.boats:depot.stocks.fuel+=float(boat.fuel);boat.fuel=0.0
	var spent_before: int=int(owner.coins)
	c.RegionalOps.refresh(c)
	check(not op.currentPlan.ready and owner.purpose in ["resupply","repair"],"empty working tanks stall the existing force")
	position={"x":p.x,"y":p.y};c.step(1.0)
	check(c.distance(position,p)<0.001 and p.holding and int(owner.coins)==spent_before,"unsupplied patrol stays at its actual harbor without free fuel or spending")
	RegionalUI.open(scene.ui)
	check(text_in(scene.ui,"Stalled:") and text_in(scene.ui,"Reserves / route + return:") and text_in(scene.ui,"Treasury grant:"),"existing regional panel exposes reserves, paid support and first stall")
	var deliver: Button=button_in(scene.ui,"Deliver owned cargo · no payment")
	check(deliver!=null,"corridor exposes its existing owned-cargo contribution action")
	var cargo_before: float=float(c.state.cargo.fuel)
	if deliver!=null:
		for control in deliver.get_parent().get_children():
			if control is OptionButton:
				check(control.item_count==4 and str(control.get_item_metadata(0))=="fuel","corridor offers fuel, ammo, food and repair supplies")
			if control is SpinBox:control.value=9
		deliver.pressed.emit()
	check(is_equal_approx(float(c.state.cargo.fuel),cargo_before-9) and is_equal_approx(float(home.stocks.fuel),9),"actual panel transfers nine owned drums to sponsor stock")
	check(owner.boats.all(func(b):return float(b.fuel)==0.0) and int(owner.coins)==spent_before,"donation alone performs no free tank filling or paid work")
	check(Money.total(c.state)==money,"player cargo contribution neither creates nor removes coins")
	var port_cash: int=int(home.cash)
	var wages_before: int=int(owner.crewPurse)
	Fleets.tick([owner],c.state.ports,0.01,c)
	check(owner.boats.all(func(b):return float(b.fuel)>0) and int(owner.coins)<spent_before and int(home.cash)>port_cash and int(owner.crewPurse)>wages_before,"ordinary dock service buys donated stock and pays actual crew wages")
	c.RegionalOps.refresh(c)
	check(op.currentPlan.ready and owner.purpose=="escort" and not p.holding,"funded ordinary resupply resumes the same physical convoy order")
	position={"x":p.x,"y":p.y};c.step(1.0)
	check(c.distance(position,p)>1,"resupplied patrol resumes actual water-route progress")
	check(c.state.regionalCampaigns.journal.any(func(e):return e.get("kind","")=="operation-resumed"),"stall and observed resumption enter the existing bounded journal")
	check(Money.total(c.state)==money,"market, grant, crew pay and resupply conserve the same coin supply")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	var expected: Dictionary=saved.regionalCampaigns.duplicate(true)
	var restored: Dictionary=c.restore(saved)
	check(restored.ok,"actual save loader accepts the observed supplied operation: "+str(restored.get("message","")))
	check(same_data(c.state.regionalCampaigns,expected),"JSON save/load preserves every regional book, readiness, grant and progress field")
