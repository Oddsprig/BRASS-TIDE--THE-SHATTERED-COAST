extends SceneTree
## Focused v0.032 fixture. Root runs it headlessly in the shared test lane.
## Actual Main convoy outcomes, marked wreck choices, and finite captured cargo.
const Battle=preload("res://scripts/battle.gd")
const Boarding=preload("res://scripts/boarding.gd")
const Objectives=preload("res://scripts/battle_objectives.gd")
const Salvage=preload("res://scripts/salvage.gd")
const Recovery=preload("res://scripts/equipment_recovery.gd")
const Condition=preload("res://scripts/equipment_condition.gd")
const Records=preload("res://scripts/equipment_records.gd")
const Money=preload("res://scripts/money.gd")
const Flow=preload("res://scripts/recovery_flow.gd")
var checks: int=0
var failures: int=0

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL convoy recovery voyage: ",message)

func text_in(node: Node,needle: String) -> bool:
	if (node is Label or node is Button) and needle in str(node.text):return true
	for child in node.get_children():
		if text_in(child,needle):return true
	return false

func button_in(node: Node,caption: String) -> Button:
	if node is Button and node.text==caption:return node
	for child in node.get_children():
		var found: Button=button_in(child,caption)
		if found!=null:return found
	return null

func convoy(c) -> Dictionary:
	for p in c.state.patrols:
		var owner: Dictionary=c.fleet_owner(str(p.id))
		if owner.is_empty() or owner.kind!="trader" or c.Politics.hostile(c,owner):continue
		if owner.boats.size()<2 or owner.boats.any(func(b):return b.sunk or b.crew<b.crewMin):continue
		var harbor: Dictionary=c.port(owner.homePort)
		if float(owner.cargo.get("timber",0))<=0:
			# Make room by selling existing trade cargo back to its real market.
			var wallet: Dictionary={"coins":owner.coins,"cargo":owner.cargo}
			var offered: int=mini(8,floori(float(owner.get("tradeCargo",0))))
			var sold: Dictionary=c.Economy.transact(harbor,wallet,str(owner.tradeGood),offered,"sell",c.Fleets._capacity(owner))
			if sold.ok:
				owner.coins=wallet.coins
				owner.tradeCargo=maxf(0,float(owner.tradeCargo)-float(sold.get("qty",0)))
		# Buy actual stock through the existing paid fleet market, without new goods or coins.
		var amount: int=c.Fleets._purchase(owner,harbor,"timber",4,false,false,c,true)
		if owner.tradeGood=="timber":owner.tradeCargo+=amount
		elif float(owner.tradeCargo)<=0 and amount>0:
			owner.tradeGood="timber";owner.tradeCargo=amount
		if float(owner.cargo.get("timber",0))<=0:continue
		p.x=c.state.position.x;p.y=c.state.position.y
		return {"owner":owner,"patrol":p}
	return {}

func parts(condition: Dictionary) -> Array:
	var out: Array=[]
	var keys: Array=condition.get("items",{}).keys()
	keys.sort()
	for key in keys:
		var item: Dictionary=condition.items[key]
		out.append([str(item.itemUid),str(item.location),float(item.hp),str(item.status),str(item.cause)])
	return out

func wreck_differences(expected: Array,actual: Array) -> Array:
	var out: Array=[]
	if expected.size()!=actual.size():out.append({"expectedCount":expected.size(),"actualCount":actual.size()})
	for index in range(mini(expected.size(),actual.size())):
		var fields: Array=[]
		for field in expected[index]:
			if not actual[index].has(field) or expected[index][field]!=actual[index][field]:fields.append(str(field))
		for field in actual[index]:
			if not expected[index].has(field):fields.append(str(field))
		if not fields.is_empty():out.append({"wreckId":expected[index].get("id"),"fields":fields})
	return out

func _initialize() -> void:
	var scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.save_directory=OS.get_user_data_dir().path_join("convoy-recovery-032-%d"%Time.get_ticks_usec())
	scene.new_game()
	check(scene.mode=="campaign" and not scene.core.state.is_empty(),"real Main starts a new voyage in an isolated save directory")
	if not scene.core.state.is_empty():
		_test_escort(scene)
		scene.new_game()
		_test_intercept_recovery(scene)
		scene.new_game()
		_test_captured_cargo(scene)
	scene.queue_free()
	await process_frame
	print("convoy recovery voyage: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func _test_escort(scene) -> void:
	var c=scene.core
	var chosen: Dictionary=convoy(c)
	check(not chosen.is_empty(),"escort has a real funded loaded convoy")
	if chosen.is_empty():return
	var owner: Dictionary=chosen.owner
	for p in c.state.patrols:
		if c.fleet_owner(str(p.id)).get("kind","")=="raider":
			p.x=chosen.patrol.x;p.y=chosen.patrol.y
			break
	scene.show_patrol_encounter(str(owner.id))
	check(text_in(scene.ui.overlay,"Protect convoy to its exit") and not text_in(scene.ui.overlay,"45-second"),"Main encounter states a physical protection objective")
	var goods: Dictionary=owner.cargo.duplicate(true)
	var delivered: float=float(owner.get("tradeDelivered",0))
	c.EscortOps.start(scene,str(owner.id))
	check(scene.mode=="battle" and scene.battle.get("mission",{}).get("kind","")=="escort","escort enters real Main.begin_battle")
	if scene.mode!="battle":return
	check(scene.battle.autopilot and int(scene.battle.deployment.limit)==300,"autopilot and the 300-point deployment limit remain active")
	var save_path: String=scene.save_directory.path_join("voyage.json")
	var before_outcome: String=FileAccess.get_file_as_string(save_path)
	scene.save_game(false)
	scene.save_game(false,true)
	check(FileAccess.get_file_as_string(save_path)==before_outcome and scene.mode=="battle","active battle keeps both default and explicit settled-save guards")
	scene.battle.time=46.0
	Objectives.update(scene.battle)
	check(scene.battle.result==null,"46 seconds without a physical exit is not success")
	var snapshot: Dictionary=Battle.objective_snapshot(scene.battle)
	var exit_zone: Dictionary=snapshot.get("exit",{})
	check(float(exit_zone.get("x",0))>2000 and "exit" in str(snapshot.get("label","")).to_lower(),"protect goal uses the far exit and a physical HUD label")
	for boat in scene.battle.ships:
		if str(boat.get("uid","")) in scene.battle.mission.get("carrierUids",scene.battle.mission.get("allyUids",[])):
			boat.x=float(exit_zone.get("x",2180));boat.y=float(exit_zone.get("y",850))
	Objectives.update(scene.battle)
	check(scene.battle.result=="won" and int(Battle.objective_snapshot(scene.battle).get("escaped",0))>0,"owned carriers physically reaching the zone finish escort")
	if scene.battle.result==null:return
	scene.save_game(false,true)
	check(FileAccess.get_file_as_string(save_path)==before_outcome,"a finished battle cannot save before successful settlement")
	scene.settle_battle()
	check(scene.ui.modal_kind=="outcome" and not scene.battle_report.get("convoy",{}).is_empty(),"Main settlement presents the actual convoy outcome")
	var sequence: int=int(c.state.battleSeq)
	var saved_outcome: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	check(scene.mode=="battle" and int(saved_outcome.get("battleSeq",-1))==sequence and saved_outcome.get("cargo",{})==c.state.cargo,"settled voyage file is written on the outcome screen before Return")
	scene.settle_battle()
	check(int(c.state.battleSeq)==sequence,"reopening the report cannot settle the voyage twice")
	check(owner.cargo==goods and is_equal_approx(float(owner.get("tradeDelivered",0)),delivered),"escaped cargo stays owned and is not delivered at the battle exit")
	scene.return_to_campaign()
	check(scene.mode=="campaign" and scene.has_save(),"Main returns to the campaign and writes the voyage")
	scene.load_game()
	check(c.fleet_owner(str(owner.id)).cargo==goods,"actual Main save/load preserves escaped convoy goods")
	check(Money.total(c.state)==int(c.state.coinSupply),"escort settlement and save preserve the coin ledger")

func _test_intercept_recovery(scene) -> void:
	var c=scene.core
	var chosen: Dictionary=convoy(c)
	check(not chosen.is_empty(),"intercept uses real finite convoy cargo")
	if chosen.is_empty():return
	var owner: Dictionary=chosen.owner
	var cargo_before: float=float(owner.cargo.timber)
	scene.show_patrol_encounter(str(owner.id))
	check(text_in(scene.ui.overlay,"Intercept this convoy"),"Main exposes interception from the voyage contact")
	scene.engage_patrol(chosen.patrol)
	check(scene.mode=="battle" and scene.battle.mission.get("kind","")=="intercept","Main prepares the actual convoy intercept mission")
	if scene.mode!="battle":return
	var snapshot: Dictionary=Battle.objective_snapshot(scene.battle)
	check(float(snapshot.get("exit",{}).get("x",2300))<300,"enemy carriers must reach the opposite physical exit")
	for boat in scene.battle.ships:
		if boat.team!="enemy":continue
		for item in boat.moduleCondition.items.values():
			if item.location in ["engine","mount0"]:
				check(Condition.apply_component_damage(boat.moduleCondition,{"itemUid":str(item.itemUid),"loss":0.75,"cause":"Convoy recovery fixture"}).ok,"actual carrier module takes damage")
		check(Records.publish(boat).ok,"damaged equipment publishes without a replacement birth")
		boat.hp=0.0;boat.sunk=true
	Objectives.update(scene.battle)
	check(scene.battle.result=="won","stopping the real loaded carriers ends interception")
	if scene.battle.result==null:return
	scene.settle_battle()
	var ids: Array=Flow.wreck_ids(scene.battle_report)
	check(ids.size()==2,"exactly the two physical enemy hulls become marked wrecks")
	if ids.size()!=2:return
	var cargo_id: String=""
	var wreck_timber: float=0.0
	for id in ids:
		var w: Dictionary=Salvage.find_wreck(c.state,str(id))
		wreck_timber+=float(w.stores.get("timber",0))
		if float(w.stores.get("timber",0))>0:cargo_id=str(id)
	check(not cargo_id.is_empty() and float(owner.cargo.timber)+wreck_timber<=cargo_before+0.00001,"marked cargo came from the actual owner once")
	if cargo_id.is_empty():return
	var sequence: int=int(c.state.battleSeq)
	var coins: int=int(c.state.coins)
	var cargo: Dictionary=c.state.cargo.duplicate(true)
	var convoy_cargo: Dictionary=owner.cargo.duplicate(true)
	# The save contract is JSON, whose numeric representation can round native floats.
	# Compare complete records in that representation, retaining every cargo/part field.
	var wrecks: Array=JSON.parse_string(JSON.stringify(c.state.wrecks))
	if c.state.wrecks!=wrecks:
		print("Outcome raw/JSON wreck baseline differs: ",wreck_differences(c.state.wrecks,wrecks))
	var saved_outcome: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(scene.save_directory.path_join("voyage.json")))
	var saved_ok: bool=scene.mode=="battle" and int(saved_outcome.get("battleSeq",-1))==sequence and saved_outcome.get("wrecks",[])==wrecks and int(saved_outcome.get("coins",-1))==coins
	check(saved_ok,"interception saves real wreck cargo and credit before leaving the outcome")
	if not saved_ok:
		print("Outcome save diagnostic: ",{"mode":scene.mode,"expectedSequence":sequence,"savedSequence":saved_outcome.get("battleSeq"),"expectedCoins":coins,"savedCoins":saved_outcome.get("coins"),"wreckDifferences":wreck_differences(wrecks,saved_outcome.get("wrecks",[]))})
	scene.load_game()
	var loaded_ok: bool=scene.mode=="campaign" and int(c.state.battleSeq)==sequence and int(c.state.coins)==coins and c.state.cargo==cargo and c.fleet_owner(str(owner.id)).cargo==convoy_cargo and JSON.parse_string(JSON.stringify(c.state.wrecks))==wrecks
	check(loaded_ok,"loading directly from outcome restores each settled cargo lot, wreck and credit once")
	if not loaded_ok:
		print("Outcome load diagnostic: ",{"mode":scene.mode,"expectedSequence":sequence,"loadedSequence":c.state.battleSeq,"expectedCoins":coins,"loadedCoins":c.state.coins,"cargoMatches":c.state.cargo==cargo,"ownerCargoMatches":c.fleet_owner(str(owner.id)).cargo==convoy_cargo,"wreckDifferences":wreck_differences(wrecks,JSON.parse_string(JSON.stringify(c.state.wrecks)))})
	scene.settle_battle()
	var repeat_ok: bool=int(c.state.battleSeq)==sequence and int(c.state.coins)==coins and c.state.cargo==cargo and JSON.parse_string(JSON.stringify(c.state.wrecks))==wrecks
	check(repeat_ok,"loaded outcome cannot duplicate settlement cargo or credit")
	if not repeat_ok:
		print("Outcome repeat diagnostic: ",{"mode":scene.mode,"expectedSequence":sequence,"actualSequence":c.state.battleSeq,"expectedCoins":coins,"actualCoins":c.state.coins,"cargoMatches":c.state.cargo==cargo,"wreckDifferences":wreck_differences(wrecks,JSON.parse_string(JSON.stringify(c.state.wrecks)))})
	scene.open_battle_recovery()
	check(scene.mode=="campaign" and scene.ui.modal_kind=="recovery" and text_in(scene.ui.overlay,"Abandon for now"),"outcome returns to campaign recovery with an explicit leave-marked choice")
	var untouched: Dictionary=c.state.duplicate(true)
	var pending: int=c.pending_days
	scene.ui.RecoveryUI.leave(scene.ui)
	check(c.state==untouched and c.pending_days==pending and not scene.ui.modal_open,"abandon UI performs zero work, payment, loot, or custody changes")
	scene.save_game(false)
	var saved_wreck: Dictionary=Salvage.find_wreck(c.state,cargo_id).duplicate(true)
	scene.load_game()
	check(Salvage.find_wreck(c.state,cargo_id)==saved_wreck,"Main save/load preserves the unclaimed wreck, lots, and exact condition")
	var expected_parts: Array=parts(saved_wreck.sourceModuleCondition)
	var qty: float=minf(1.0,float(saved_wreck.stores.timber))
	var prior_timber: float=float(c.state.cargo.timber)
	var took: Dictionary=scene.recover_wreck(cargo_id,"strip","timber",qty)
	check(took.ok and is_equal_approx(float(c.state.cargo.timber),prior_timber+qty),"Main recovers only the selected finite loose cargo")
	check(not Salvage.find_wreck(c.state,cargo_id).hullStripped and Salvage.quote(c,cargo_id,"tow").ok,"taking loose timber cargo preserves the intact tow option")
	var roster_size: int=c.state.fleet.size()
	var crew_before: int=c.crew_count()
	var tow: Dictionary=scene.recover_wreck(cargo_id,"tow")
	check(tow.ok and c.state.fleet.size()==roster_size+1,"existing paid tow adds one damaged hull")
	if not tow.ok:return
	var boat: Dictionary=c.find_boat(str(tow.boatUid))
	check(parts(boat.moduleCondition)==expected_parts,"tow preserves the same part UIDs, damage, status, cause and locations")
	check(boat.crew==0 and boat.fuel==0 and boat.ammo==0 and boat.supplies==0 and c.crew_count()<=crew_before,"towing creates no crew or working stores")
	check(boat.supportOnly and boat.needsHarborRepair and boat.mothballed,"tow needs paid repair and a crew before combat deployment")
	check(not scene.recover_wreck(cargo_id,"tow").ok,"the same physical wreck cannot be claimed twice")
	var strip_id: String=str(ids[0]) if str(ids[0])!=cargo_id else str(ids[1])
	var other: Dictionary=Salvage.find_wreck(c.state,strip_id)
	var timber: float=float(other.stores.get("timber",0))+minf(0.1,float(other.components.get("timber",0)))
	var strip: Dictionary=scene.recover_wreck(strip_id,"strip","timber",timber)
	check(strip.ok and Salvage.find_wreck(c.state,strip_id).hullStripped and not Salvage.quote(c,strip_id,"tow").ok,"removing actual structural timber permanently forfeits the second hull tow")
	check(Recovery.registry(c.state,"").ok and Money.total(c.state)==int(c.state.coinSupply),"final equipment custody is unique and every coin remains accounted for")
	var final_parts: Array=parts(boat.moduleCondition)
	scene.save_game(false)
	scene.load_game()
	check(parts(c.find_boat(str(tow.boatUid)).moduleCondition)==final_parts and Salvage.find_wreck(c.state,strip_id).hullStripped,"actual Main save/load preserves towed condition and structural stripping")

func _test_captured_cargo(scene) -> void:
	var c=scene.core
	c.use_reserves()
	var chosen: Dictionary=convoy(c)
	check(not chosen.is_empty(),"captured cargo starts with actual funded convoy goods")
	if chosen.is_empty():return
	scene.engage_patrol(chosen.patrol)
	check(scene.mode=="battle" and scene.battle.mission.get("kind","")=="intercept","captured cargo enters the actual Main interception")
	if scene.mode!="battle":return
	var source: Dictionary=Battle.get_flagship(scene.battle)
	# Qualify only existing spare sailors; boarding still transfers the actual people.
	source.boarders=maxi(0,floori(float(source.crew)-float(source.crewMin)-float(source.wounded)))
	for carrier_uid in scene.battle.mission.carrierUids:
		var target: Dictionary=scene.battle.convoy.actors[str(carrier_uid)]
		source.x=520.0;source.y=850.0;target.x=550.0;target.y=850.0
		target.hp=target.maxHp*0.3;target.surrendering=true
		var launch: Dictionary=Boarding.launch(scene.battle,str(source.id),str(target.id),1)
		check(launch.ok,"actual boarding transfers one existing sailor to each carrier")
		if not launch.ok:return
		Boarding.tick(scene.battle,4.1)
	Objectives.update(scene.battle)
	check(scene.battle.result=="won","capturing every loaded carrier finishes the interception")
	if scene.battle.result==null:return
	scene.settle_battle()
	var review: Button=button_in(scene.ui.overlay,"Review captured cargo")
	check(Flow.wreck_ids(scene.battle_report).is_empty() and review!=null and not review.disabled,"all-captured outcome offers cargo review with no wrecks")
	if review==null or review.disabled:return
	review.pressed.emit()
	var prizes: Array=scene.ui.RecoveryUI.captured_prizes(c)
	check(scene.mode=="campaign" and scene.ui.modal_kind=="recovery" and not prizes.is_empty(),"outcome button opens actual held cargo after returning to campaign")
	if prizes.is_empty():return
	var prize: Dictionary=prizes[0]
	var uid: String=str(prize.uid)
	var good: String=""
	for key in prize.convoyCargo:
		if float(prize.convoyCargo[key])>0:good=str(key);break
	var held: float=float(prize.convoyCargo[good])
	var before: float=float(c.state.cargo.get(good,0))
	var amount: float=minf(1.0,held)
	var take: Button=button_in(scene.ui.overlay,"Take 1")
	check(text_in(scene.ui.overlay,"%s · %.2f aboard prize"%[c.Goods.ITEMS[good].name,held]) and take!=null and not take.disabled and button_in(scene.ui.overlay,"Take what fits")!=null,"recovery displays actual good quantities and both transfer controls")
	if take==null or take.disabled:return
	take.pressed.emit()
	check(is_equal_approx(float(prize.convoyCargo[good]),held-amount) and is_equal_approx(float(c.state.cargo[good]),before+amount),"Take 1 debits the actual held prize and credits campaign cargo exactly once")
	var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(scene.save_directory.path_join("voyage.json")))
	check(saved.get("cargo",{})==c.state.cargo,"successful captured-cargo transfer saves immediately")
	prizes=scene.ui.RecoveryUI.captured_prizes(c)
	check(not prizes.is_empty(),"the real convoy has goods remaining after taking one")
	if prizes.is_empty():return
	var space_prize: Dictionary=prizes[0]
	var space_good: String=""
	for key in space_prize.convoyCargo:
		if float(space_prize.convoyCargo[key])>0:space_good=str(key);break
	# Keep actual goods aboard while temporarily removing all traveling hold capacity.
	var traveling: Array=c.Expedition.traveling(c.state)
	for boat in traveling:boat.mothballed=true
	var unchanged: Dictionary=c.state.duplicate(true)
	scene.ui.RecoveryUI.open(scene.ui)
	var full: Button=button_in(scene.ui.overlay,"Take what fits")
	check(full!=null and full.disabled and not scene.take_prize_cargo(str(space_prize.uid),space_good,minf(0.1,float(space_prize.convoyCargo[space_good]))).ok and c.state==unchanged,"full traveling holds disable transfer and the actual API refuses without changing custody")
	for boat in traveling:boat.mothballed=false
	scene.ui.RecoveryUI.open(scene.ui)
	prizes=scene.ui.RecoveryUI.captured_prizes(c)
	if not prizes.is_empty():
		var remaining: Dictionary=prizes[0]
		var next_good: String=""
		for key in remaining.convoyCargo:
			if float(remaining.convoyCargo[key])>0:next_good=str(key);break
		var lot: float=float(remaining.convoyCargo[next_good])
		var fits: float=minf(lot,maxf(0,c.capacity()-c.cargo_weight())/float(c.Goods.ITEMS[next_good].weight))
		var prior: float=float(c.state.cargo.get(next_good,0))
		var take_fits: Button=button_in(scene.ui.overlay,"Take what fits")
		check(take_fits!=null and not take_fits.disabled,"restored real hold space enables Take what fits")
		if take_fits!=null and not take_fits.disabled:
			take_fits.pressed.emit()
			check(is_equal_approx(float(remaining.convoyCargo[next_good]),lot-fits) and is_equal_approx(float(c.state.cargo[next_good]),prior+fits) and c.cargo_weight()<=c.capacity()+0.000001,"Take what fits moves only real available goods within actual hold capacity")
	unchanged=c.state.duplicate(true)
	check(not scene.take_prize_cargo(uid,good,held+1.0).ok and c.state==unchanged,"repeated overclaim cannot duplicate captured goods")
	var cargo: Dictionary=c.state.cargo.duplicate(true)
	var held_cargo: Dictionary=prize.convoyCargo.duplicate(true)
	scene.load_game()
	var restored: Dictionary={}
	for boat in c.state.fleet+c.state.get("boardingPrizes",[]):
		if str(boat.uid)==uid:restored=boat;break
	check(not restored.is_empty() and restored.get("convoyCargo",{})==held_cargo and c.state.cargo==cargo and Money.total(c.state)==int(c.state.coinSupply),"actual save/load preserves both cargo owners with no duplicated goods or coin credit")
