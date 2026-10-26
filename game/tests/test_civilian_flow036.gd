extends SceneTree
## Focused v0.036 integration. Root alone runs the bounded native fixture.
const Money=preload("res://scripts/money.gd")
const Orders=preload("res://scripts/naval_orders.gd")
const AI=preload("res://scripts/naval_ai.gd")
const Contacts=preload("res://scripts/contacts.gd")
const Transport=preload("res://scripts/passenger_transport.gd")
var checks: int=0
var failures: int=0
var scene
var c

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL civilian flow036: ",message)

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

func picker_in(node: Node) -> OptionButton:
	if node is OptionButton:return node
	for child in node.get_children():
		var found: OptionButton=picker_in(child)
		if found!=null:return found
	return null

func text_in(node: Node,needle: String) -> bool:
	if (node is Label or node is Button) and needle in str(node.text):return true
	for child in node.get_children():
		if text_in(child,needle):return true
	return false

func physical(owner: Dictionary) -> Dictionary:
	return {"boats":owner.boats.duplicate(true),"cargo":owner.cargo.duplicate(true),"coins":owner.coins,"crewPurse":owner.crewPurse,"route":owner.route.duplicate()}

func middle(course: Array) -> Dictionary:
	var longest: float=0.0
	var point: Dictionary={}
	for i in range(1,course.size()):
		var length: float=c.distance(course[i-1],course[i])
		if length>longest:
			longest=length;point={"x":(float(course[i-1].x)+float(course[i].x))*0.5,"y":(float(course[i-1].y)+float(course[i].y))*0.5}
	return point

func _initialize() -> void:
	scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false);scene.set_physics_process(false)
	scene.save_directory=OS.get_user_data_dir().path_join("civilian-flow-036-%d"%Time.get_ticks_usec())
	scene.new_game();c=scene.core
	check(scene.mode=="campaign" and not c.state.is_empty(),"actual Main publishes a career in isolated save custody")
	if not c.state.is_empty():
		_test_traffic()
		_test_fishing_ui()
		_test_fuel_board()
		_test_witnesses()
	scene.sync_economy();scene.free()
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func _test_traffic() -> void:
	var roles: Dictionary={}
	var before: Dictionary={}
	for i in range(9):
		var owner: Dictionary=c.fleet_owner("patrol-%d"%i)
		check(not owner.is_empty() and owner.kind==("raider" if i%3==0 else ("trader" if i%3==1 else "patrol")) and owner.boats.size()==1+i%3,"existing funded owner identity, kind and fleet count retained: %d"%i)
		if owner.kind=="trader":
			check(float(owner.tradeCargo)>0 and float(owner.cargo.get(owner.tradeGood,0))>=float(owner.tradeCargo),"civilian traffic loads actual paid hold cargo: "+str(owner.id))
			for boat in owner.boats:
				var role: String=str(boat.spec.get("civilianRole",""))
				if role.is_empty():continue
				roles[role]=true
				check(boat.crew>=boat.crewMin and boat.spec.faction==c.port(owner.homePort).faction,"civilian hull uses its existing home faction and real allocated crew: "+str(boat.type))
				if role=="tanker":check(owner.tradeGood=="fuel","tanker trade cargo is real fuel")
		before[owner.id]=physical(owner)
	check(roles.size()==4,"existing nine-owner traffic includes fishing, transport, tanker and yacht")
	check(Money.total(c.state)==int(c.state.coinSupply),"civilian endowments circulate the existing coin supply")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	var result: Dictionary=c.restore(saved)
	check(result.ok,"loaded civilian traffic passes actual full save validation: "+str(result.get("message","")))
	for id in before:check(same_data(physical(c.fleet_owner(id)),before[id]),"load preserves all physical boats, cargo, crew and purses: "+str(id))
	var patrol: Dictionary=Orders.find_patrol(c.state,"patrol-1")
	var start: Dictionary={"x":patrol.x,"y":patrol.y}
	c.state.encounterGrace=1000.0
	c.step(0.25)
	check(c.distance(start,patrol)>0,"real Core.step moves loaded civilian traffic between daily ticks")
	start={"x":patrol.x,"y":patrol.y}
	c.wait_day()
	check(c.distance(start,patrol)<0.000001,"wait_day alone does not claim NPC movement")
	scene.sync_economy()
	check(Money.total(c.state)==int(c.state.coinSupply),"normal daily upkeep retains finite circulating purses")

func _take_existing(owner_id: String,role: String) -> Dictionary:
	var owner: Dictionary=c.fleet_owner(owner_id)
	for boat in owner.boats:
		if str(boat.spec.get("civilianRole",""))!=role:continue
		# Fixture custody transfer, not a production grant: no boat, sailor,
		# equipment item or working store is created or duplicated.
		owner.boats.erase(boat);c.state.fleet.append(boat)
		c._initialize_published_boat(boat);c.Manifest.allocate(c.state)
		return boat
	return {}

func _test_fishing_ui() -> void:
	var point: Dictionary=middle(Orders.find_patrol(c.state,"patrol-1").course)
	var boat: Dictionary=_take_existing("patrol-1","fishing")
	check(not boat.is_empty() and not point.is_empty(),"fixture moves an existing crewed fishing hull into player custody")
	if boat.is_empty() or point.is_empty():return
	c.state.position=point;c.stop_sailing()
	check(c.current_port().is_empty(),"fishing scenario is on existing water away from a harbor")
	scene.ui.VoyageUI.open(scene.ui,"Fishing")
	var picker: OptionButton=picker_in(scene.ui.overlay)
	var launch: Button=button_in(scene.ui.overlay,"Begin fishing and return to sea")
	check(picker!=null and launch!=null and not launch.disabled and str(picker.get_selected_metadata())==str(boat.uid),"actual fishing board selects the named eligible hull")
	check(text_in(scene.ui.overlay,"free hold") and text_in(scene.ui.overlay,"spare berths"),"actual picker exposes physical hold and berth reservations")
	if launch==null:return
	var caught: float=float(c.state.cargo.preserved_fish)
	launch.pressed.emit()
	var jobs: Array=c.CivilianWork.fishing_status(c)
	check(jobs.size()==1 and str(jobs[0].boatUid)==str(boat.uid) and not scene.ui.modal_open,"actual UI callback starts fishing and releases the live campaign clock")
	var day: float=float(c.state.day)
	var fuel: float=float(boat.fuel)
	var food: float=float(c.state.cargo.food)
	c.step(2.25)
	check(is_equal_approx(float(c.state.day)-day,0.05),"fishing uses the existing Core.step day clock exactly once")
	check(float(c.state.cargo.preserved_fish)>caught and float(boat.fuel)<fuel and float(c.state.cargo.food)<food,"Core.step earns catch from elapsed crew work and consumes actual stores")
	caught=float(c.state.cargo.preserved_fish)
	c.wait_day()
	check(is_equal_approx(float(c.state.cargo.preserved_fish),caught),"dockside/day-skip action earns no fishing work")
	scene.sync_economy()
	var saved: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	var restored: Dictionary=c.restore(saved)
	check(restored.ok and same_data(c.CivilianWork.fishing_status(c),saved.civilianWork.fishing),"actual save restore retains the assigned fishing hull, crew, catch and elapsed work")
	check(c.cancel_fishing(str(boat.uid)).ok and c.CivilianWork.fishing_status(c).is_empty() and is_equal_approx(float(c.state.cargo.preserved_fish),caught),"recalling actual crew keeps earned catch and cannot repeat work")

func _test_fuel_board() -> void:
	var carrier: Dictionary=_take_existing("patrol-1","transport")
	check(not carrier.is_empty(),"fixture transfers an existing transport with actual free hold")
	if carrier.is_empty():return
	c.state.position=c.port_position("brass_haven");c.stop_sailing()
	# A physically present returning owner needs replenishment. Move its own
	# remaining tank fuel into this harbor's stock to set the finite demand;
	# no test-only coin, good or replacement hull is created.
	var recipient: Dictionary=c.fleet_owner("patrol-2")
	var target: Dictionary=c.port("anvil_dock")
	var patrol: Dictionary=Orders.find_patrol(c.state,str(recipient.id))
	var endpoint: Dictionary=c.Routes.endpoint(c,target,c.Routes.clearance(c,patrol))
	check(not endpoint.is_empty(),"recipient fixture has an actual water-safe harbor approach")
	if endpoint.is_empty():return
	recipient.atPort=target.id
	patrol.x=endpoint.x;patrol.y=endpoint.y;patrol.holding=true;patrol.active=false
	for boat in recipient.boats:
		target.stocks.fuel=float(target.stocks.fuel)+float(boat.fuel);boat.fuel=0.0
	target.stocks.fuel=float(target.stocks.fuel)+float(recipient.cargo.fuel);recipient.cargo.fuel=0.0
	var offer: Dictionary={}
	for candidate in c.VoyageJobs.available(c):
		if candidate.kind=="fuel_delivery" and str(candidate.ownerId)==str(recipient.id):offer=candidate;break
	check(not offer.is_empty(),"board offers funded fuel against an actual needy owner and physical origin stock")
	if offer.is_empty():return
	scene.ui.VoyageUI.open(scene.ui)
	check(text_in(scene.ui.overlay,str(offer.title)) and text_in(scene.ui.overlay,"Accept funded job"),"actual harbor board exposes the funded fuel row")
	scene.ui.close_modal()
	var accepted: Dictionary=c.accept_voyage_job(str(offer.id),str(carrier.uid))
	check(accepted.ok and str(accepted.get("job",{}).get("carrierUid",""))==str(carrier.uid),"Campaign adapter passes the chosen real carrier to funded job acceptance")
	if not accepted.ok:return
	var id: String=str(offer.id)
	check(float(c.state.cargoManifest.get(carrier.uid,{}).get("@job:"+id,0))==float(offer.freight.qty),"sealed fuel is pinned to the selected physical carrier")
	var before_guard: Dictionary=c.state.duplicate(true)
	check(not c.set_boat_active(str(carrier.uid),false).ok and not c.toggle_storage(str(carrier.uid)).ok and not c.sell_boat(str(carrier.uid)).ok and same_data(c.state,before_guard),"assigned loaded fuel carrier cannot be stood down, stored or sold")
	var sailing: Dictionary=c.chart_course(target,str(target.id))
	check(sailing.ok,"actual player route reaches the recipient's existing coastal harbor")
	var steps: int=0
	while sailing.ok and not c.state.path.is_empty() and steps<240:
		c.step(0.5);steps+=1
		if c.pending_days>0:scene.sync_economy()
	check(c.current_port().get("id","")==str(target.id),"bounded actual Core.step sailing reaches the delivery harbor")
	var captain_before: int=Contacts._find(c.state,"captain:"+str(recipient.id)).log.size()
	var service_before: int=int(carrier.get("service",{}).get("trades",0))
	var paid: Dictionary=c.settle_voyage_job(id)
	check(paid.ok,"actual funded fuel settlement completes through Campaign: "+str(paid.get("message","")))
	var captain: Dictionary=Contacts._find(c.state,"captain:"+str(recipient.id))
	check(captain.log.size()==captain_before+1 and captain.events.has("job:"+id+":paid"),"witnessed recipient captain remembers the settled job once")
	check(int(carrier.get("service",{}).get("trades",0))==service_before+1,"only the assigned carrier receives the completed delivery service")
	var contacts_before: Array=Contacts.list_contacts(c.state)
	check(not c.settle_voyage_job(id).ok and same_data(Contacts.list_contacts(c.state),contacts_before),"repeated settlement cannot duplicate captain/contact memory")
	check(Money.total(c.state)==int(c.state.coinSupply),"delivery escrow, fuel custody and actual NPC upkeep conserve coins")
	var freight: Dictionary={}
	for candidate in c.VoyageJobs.available(c):
		if candidate.kind=="freight":freight=candidate;break
	check(not freight.is_empty(),"settlement harbor still offers an actual funded freight lot")
	if not freight.is_empty():
		var loaded: Dictionary=c.accept_voyage_job(str(freight.id))
		check(loaded.ok,"real freight can be accepted before safe-discharge memory check")
		if loaded.ok:
			c.state.position=c.port_position("brass_haven");c.stop_sailing()
			var memory_before: Array=Contacts.list_contacts(c.state)
			var abandoned: Dictionary=c.settle_voyage_job(str(freight.id),true)
			check(abandoned.ok and same_data(Contacts.list_contacts(c.state),memory_before),"unrelated safe discharge penalizes neither the stranger nor the distant sponsor contact")

func _test_witnesses() -> void:
	var a: Dictionary=c.fleet_owner("patrol-3")
	var b: Dictionary=c.fleet_owner("patrol-7")
	var pa: Dictionary=Orders.find_patrol(c.state,str(a.id))
	var pb: Dictionary=Orders.find_patrol(c.state,str(b.id))
	var point: Dictionary=middle(pa.course)
	check(not point.is_empty(),"captain encounter fixture uses an existing coastal water route")
	if point.is_empty():return
	pa.x=point.x;pa.y=point.y;pb.x=point.x;pb.y=point.y;c.state.position=point
	AI.ensure(c.state);c.state.navalAi.encounterCount=0;c.state.navalAi.encounterOwners={}
	var outcome: Dictionary=AI.resolve_encounter(c.state,a,b,pa,pb,3606)
	check(outcome.get("ok",false) and outcome.get("event",{}).get("witnessed",false),"actual nearby hostile fleet encounter is marked witnessed")
	Contacts.witnessed_encounters(c.state)
	var captain: Dictionary=Contacts._find(c.state,"captain:"+str(b.id))
	check(captain.met and captain.log.any(func(entry):return str(entry.get("detail",""))==str(outcome.get("summary","missing"))),"recurring captain remembers the actual witnessed outcome")
	var before: Array=Contacts.list_contacts(c.state)
	Contacts.witnessed_encounters(c.state)
	check(same_data(Contacts.list_contacts(c.state),before),"rescanning witnessed outcomes is deduplicated")
	# A separate actual result resolved outside the watch grants no intel.
	var far: Dictionary=c.fleet_owner("patrol-0")
	var other: Dictionary=c.fleet_owner("patrol-8")
	var pf: Dictionary=Orders.find_patrol(c.state,str(far.id))
	var po: Dictionary=Orders.find_patrol(c.state,str(other.id))
	pf.x=point.x;pf.y=point.y;po.x=point.x;po.y=point.y
	for port in c.state.ports:
		if c.distance(port,point)>3600:c.state.position=c.port_position(port.id);break
	AI.ensure(c.state);c.state.navalAi.encounterCount=0;c.state.navalAi.encounterOwners={}
	var remote: Dictionary=AI.resolve_encounter(c.state,far,other,pf,po,3607)
	check(remote.get("ok",false) and not remote.get("event",{}).get("witnessed",true),"actual remote fleet outcome stays outside the captain's watch")
	var unseen: Dictionary=Contacts._find(c.state,"captain:"+str(far.id)).duplicate(true)
	Contacts.witnessed_encounters(c.state)
	check(same_data(Contacts._find(c.state,"captain:"+str(far.id)),unseen),"remote result grants no captain contact or memory")
	var memories: Array=JSON.parse_string(JSON.stringify(Contacts.list_contacts(c.state)))
	var saved: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	var result: Dictionary=c.restore(saved)
	check(result.ok and same_data(Contacts.list_contacts(c.state),memories),"recurring captain memories persist through actual save validation and restore: "+str(result.get("message","")))
