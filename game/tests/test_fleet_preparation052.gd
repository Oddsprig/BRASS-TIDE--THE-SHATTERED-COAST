extends SceneTree
## Root-run only: actual Main controls, isolated saves, no desktop input.
const Money=preload("res://scripts/money.gd")
var game
var checks: int=0
var failures: int=0
var started: int=0
var finished: bool=false

func check(ok: bool,message: String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL fleet preparation052: "+message)
	return ok

func descendants(node: Node) -> Array:
	var result: Array=[node]
	for child in node.get_children():result.append_array(descendants(child))
	return result

func visible_text() -> String:
	var result: Array[String]=[]
	for node in descendants(game.ui.overlay):
		if (node is Label or node is Button) and node.is_visible_in_tree():result.append(str(node.text))
	return "\n".join(result)

func press(prefix: String,within: Node=null) -> bool:
	for node in descendants(game.ui.overlay if within==null else within):
		if node is Button and str(node.text).begins_with(prefix):
			if not check(not node.disabled,"Enabled native control: "+prefix):return false
			node.pressed.emit()
			return true
	check(false,"Native control exists: "+prefix)
	return false

func hull_card(name_text: String):
	for node in descendants(game.ui.overlay):
		if node is Label and str(node.text)==name_text:
			var card: Node=node.get_parent()
			while card!=game.ui.overlay and not card is PanelContainer:card=card.get_parent()
			return card if card is PanelContainer else null
	return null

func open_preparation() -> bool:
	game.ui.open_campaign_tools()
	if not press("Prepare expedition"):return false
	return check(game.ui.modal_kind=="expedition","Campaign tools signal opens the real preparation page")

func exercise() -> void:
	var c=game.core
	game.selected_port=str(game.data.MISSIONS[0].targetPort)
	var original: String=JSON.stringify(c.state)
	if not open_preparation():return
	check(original==JSON.stringify(c.state),"Reading preparation preserves the whole actual career")
	var text: String=visible_text()
	for label in ["Limit: ","Allowance gaps:","PROTECT THE RETURN","USEFUL PAYLOAD","A PARTNER FOR THE NEXT VOYAGE"]:
		check(label in text,"Actual changed preparation presents "+label)
	check("return" in text.to_lower() and "payroll" in text.to_lower() and "fuel" in text.to_lower(),"Actual preparation controls show return payroll and fuel")
	check("300" in text and "owned" in text.to_lower(),"Preparation explains ownership and the 300-point battle budget")
	_check_yard_choice(c)
	if not press("Fuel by boat & voyage cautions"):return
	check("Tank " in visible_text(),"Fuel-detail signal reveals actual per-boat fitted tank limits")
	if not press("Cargo, stores & accounts"):return
	check(game.ui.modal_kind=="cargo","Preparation links to the existing cargo and accounts window")
	if not press("Prepare expedition"):return
	check(game.ui.modal_kind=="expedition","Cargo return signal reopens preparation")
	if not press("Manage traveling boats and stored reserves"):return
	check(game.ui.modal_kind=="fleet","Preparation links to the actual fleet controls")
	if not press("Review expedition limits & support choices"):return
	if not press("Review local boatyard"):return
	check(game.ui.modal_kind=="port" and game.ui.port_tab=="Boatyard","Preparation next-boat signal opens the actual local purchase path")
	_paid_partner(c)

func _check_yard_choice(c) -> void:
	for node in descendants(game.ui.overlay):
		if not node is OptionButton:continue
		if not check(node.item_count>=2,"Local preparation offers concrete next-boat choices"):return
		node.select(1)
		node.item_selected.emit(1)
		var selected: Dictionary={}
		for hull in c.data.HULLS:
			if str(hull.name)==node.get_item_text(1):selected=hull;break
		if not check(not selected.is_empty(),"Selected support choice names an actual hull"):return
		var q: Dictionary=c.Harbor.quote(c,selected,c.current_port())
		var advance: int=c.Economy.recruit_cost(c.current_port(),int(selected.crewMin))
		check((game.ui.money(int(q.readyPrice)+advance)+" coins before stores") in visible_text(),"Selection signal shows the real Harbor quote plus exact minimum-crew advance")
		return
	check(false,"Actual next-boat selector exists")

func _paid_partner(c) -> void:
	var p: Dictionary=c.current_port()
	var h: Dictionary=c.hull("harbor_sloop")
	var q: Dictionary=c.ship_quote(h,p)
	var advance: int=c.Economy.recruit_cost(p,int(h.crewMin))
	var global_coins: int=Money.total(c.state)
	# Fund only this synthetic profile by transferring existing treasury coins.
	var funding: int=maxi(0,int(q.readyPrice)+advance+10000-int(c.state.coins))
	if not check(Money.move(p,"governmentPurse",c.state,"coins",funding,"052 synthetic purchase funding",c.state.moneyLog),"Existing treasury can fund the quoted partner without minting"):return
	check(Money.total(c.state)==global_coins,"Funding preserves the exact global purse total")
	var before: Dictionary=c.expedition_report()
	var captain: int=int(c.state.coins)
	var sailors: int=int(c.state.crewPurse)
	var yard: int=int(p.cash)
	var treasury: int=int(p.governmentPurse)
	var workforce: int=int(p.workforce)
	var stock: int=int(p.shipStock[h.id])
	var materials: Dictionary=p.stocks.duplicate(true)
	var cargo: Dictionary=c.state.cargo.duplicate(true)
	var first: Dictionary=c.state.fleet[0].duplicate(true)
	var tax: int=mini(int(q.readyPrice),int(q.get("tax",0))+int(q.get("readyStorageTax",0)))
	game.ui.open_port("Boatyard")
	var card=hull_card(str(h.name))
	if not check(card!=null,"Actual stocked partner appears in the real Boatyard"):return
	if not press("Buy hull + minimum crew",card):return
	if not check(c.state.fleet.size()==2,"Native Boatyard purchase adds exactly one paid partner"):return
	var partner: Dictionary=c.state.fleet[1]
	check(partner.type==h.id and int(partner.crew)==int(h.crewMin),"Paid hull has the exact purchased design and recruited minimum crew")
	check(c.state.coins==captain-int(q.readyPrice)-advance and c.state.crewPurse==sailors+advance,"Captain pays the real ready quote and exact crew advance into sailors' purse")
	check(p.cash==yard+int(q.readyPrice)-tax and p.governmentPurse==treasury+tax,"Quoted hull proceeds and duties reach the exact yard and government purses")
	check(Money.total(c.state)==global_coins,"Paid progression conserves every coin globally")
	check(p.shipStock[h.id]==stock-1 and p.workforce==workforce-int(h.crewMin),"Purchase consumes one real completed hull and transfers finite shore labor")
	check(p.stocks==materials and c.state.cargo==cargo and c.state.fleet[0]==first,"Buying prebuilt stock neither consumes raw materials twice nor changes cargo or the original boat")
	check(partner.fuel==0 and partner.ammo==0 and partner.supplies==0,"Paid hull creates no free working fuel, ammunition or repair kits")
	var after: Dictionary=c.expedition_report()
	check(is_equal_approx(after.usableCapacity-before.usableCapacity,float(partner.spec.cargo)),"Real second boat increases expedition hold capacity")
	check(after.dailyWages-before.dailyWages==int(partner.crew)*100 and after.foodPerDay>before.foodPerDay,"More useful capacity carries its real crew payroll and ration burden")
	check(after.fuelDays==0 and after.fuelShortfall>0 and not after.readyForAllowance,"Unprovisioned purchased partner visibly limits fleet range")
	var snapshot: String=JSON.stringify(c.state)
	if not open_preparation():return
	text_check_partner(str(partner.name))
	check(snapshot==JSON.stringify(c.state),"Post-purchase preparation does not auto-provision or spend the remaining purse")
	# Existing Fleet control can stand down this paid partner. Its owned crew
	# remain on payroll while its hold disappears from the active expedition.
	if not press("Manage traveling boats and stored reserves"):return
	var partner_card=hull_card(str(partner.name))
	if not check(partner_card!=null,"Paid partner appears in actual Fleet controls"):return
	if not press("Stand down",partner_card):return
	var idle: Dictionary=c.expedition_report()
	check(c.state.fleet.size()==2 and c.active_fleet().size()==1,"Native stand-down retains the owned boat outside the active fleet")
	check(is_equal_approx(idle.usableCapacity,before.usableCapacity) and idle.dailyWages==after.dailyWages,"Stand-down removes capacity without silently erasing owned sailors' wages")
	if not open_preparation():return
	check(visible_text().contains(str(partner.name)) and c.expedition_report().supportOptions.size()==1,"Preparation offers the actual owned reserve as a pure support choice")

func text_check_partner(name_text: String) -> void:
	var text: String=visible_text()
	check(name_text in text and "fuel" in text.to_lower(),"Changed preparation displays the actual new partner and its working fuel limit")

func _initialize() -> void:
	started=Time.get_ticks_msec()
	call_deferred("run")

func _process(_delta: float) -> bool:
	# Cooperative deadline protects every await; Root also supplies a 25s
	# process bound, since a synchronous native stall cannot service this loop.
	if not finished and Time.get_ticks_msec()-started>=20000:
		check(false,"Cooperative 20s fixture deadline exceeded")
		finish()
	return false

func run() -> void:
	if not check(DisplayServer.get_name()=="headless","Root supplies headless, Dummy audio and a synthetic APPDATA profile"):
		finish();return
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	game.audio.enabled=false;game.music.enabled=false
	game.save_directory=OS.get_user_data_dir().path_join("fleet-preparation052-%d"%Time.get_ticks_usec())
	await process_frame
	if finished:return
	game.new_game();game.paused=true
	check(not game.core.state.is_empty() and game.mode=="campaign","Actual Main starts an isolated paid career")
	if not game.core.state.is_empty():exercise()
	if is_instance_valid(game):game.queue_free()
	await process_frame
	if not finished:finish()

func finish() -> void:
	if finished:return
	if failures==0:check(Time.get_ticks_msec()-started<20000,"Fixture completes inside its cooperative 20s deadline")
	finished=true
	if is_instance_valid(game) and not game.is_queued_for_deletion():game.queue_free()
	print("fleet preparation052: %d checks, %d failures, %dms; native controls only"%[checks,failures,Time.get_ticks_msec()-started])
	quit(0 if failures==0 else 1)
