extends "res://tests/test_voyage_career070.gd"
## Root-only authored85086 advanced expedition: finite declared treasury advance,
## real paid fittings/stores and original hull/item custody; not starter progression.
## Merchant admission, funding, movement, encounters and battle results remain real.
## Only player opening poses, expedition finance and diplomacy are declared.
const Territory085=preload("res://scripts/territorial076.gd")
const Battle085=preload("res://scripts/battle.gd")
const Coast085=preload("res://scripts/coastal_terrain.gd")
const Custody085=preload("res://scripts/equipment_campaign.gd")
var target085: String=""
var defender085: String=""
var sponsor085: String=""
var corridor085: Dictionary={}
var source085: String=""
var base_geography085: Dictionary={}

func geography085() -> Dictionary:
	# Decode BOTH complete books before exact same_values comparison, as083/084.
	# Retain every field; compare exact decoded numbers without an epsilon.
	return JSON.parse_string(JSON.stringify({"sector069":c.state.sector069,"islandOwnership069":c.state.islandOwnership069},"",true))

func expedition085(home: Dictionary) -> bool:
	var npcs: PackedByteArray=var_to_bytes(c.state.fleetOwners)
	var original_fleet: PackedByteArray=var_to_bytes(c.state.fleet)
	var treasury: int=int(home.governmentPurse);var coins: int=int(c.state.coins)
	var advanced: bool=c.Money.move(home,"governmentPurse",c.state,"coins",50000,"Declared085 finite captain expedition advance; not earned starter income",c.state.moneyLog)
	receipt.advance085={"declaredSetup":true,"earnedIncome":false,"sourcePort":home.id,"sourceAccount":"governmentPurse","amount":50000,"treasuryBefore":treasury,"treasuryAfter":home.governmentPurse,"captainBefore":coins,"captainAfter":c.state.coins,"worldCoins":c.Money.total(c.state)}
	if not check(advanced and int(home.governmentPurse)==treasury-50000 and int(c.state.coins)==coins+50000 and c.Money.total(c.state)==supply and int(c.state.coinSupply)==supply,"Declared50000 advance transfers existing home treasury coins exactly; no minted or earned income"):return false
	for good in ["food","supplies"]:
		var quantity: int=4 if good=="food" else 2
		var buy_coins: int=int(c.state.coins);var cash: int=int(home.cash);var stock: float=float(home.stocks[good]);var cargo: float=float(c.state.cargo[good])
		var invoice: Dictionary=c.trade(str(home.id),good,quantity,"buy")
		receipt.supplyInvoices085.append(invoice)
		if not check(invoice.get("ok",false) and int(invoice.qty)==quantity and int(c.state.coins)==buy_coins-int(invoice.coins) and int(home.cash)==cash+int(invoice.coins) and float(home.stocks[good])==stock-quantity and float(c.state.cargo[good])==cargo+quantity,"Actual seller supplies the carried "+good+" for its exact finite invoice"):return false
	if not check(original_fleet==var_to_bytes(c.state.fleet),"Treasury advance and carried provisions change no original hull, item or working store"):return false
	var boat: Dictionary=c.state.fleet[0]
	var original: Dictionary=boat.duplicate(true)
	var fit: Dictionary=boat.loadout.duplicate(true)
	fit.weapons=["rapid_gun","rapid_gun"];fit.armor="scout_plating"
	var quote: Dictionary=c.workshop_preview(str(boat.uid),fit)
	receipt.fitting085={"declaredSetup":true,"boatUid":boat.uid,"before":physical_boat(original).duplicate(true),"originalItems":original.moduleCondition.items.duplicate(true),"requested":fit,"quote":quote.duplicate(true)}
	if not check(quote.get("ok",false) and quote.usedPoints==8 and quote.usedPoints<=quote.maxPoints and int(quote.cost)>0,"Existing workshop quotes both compatible rapid guns and light plating within the original hull's fitting budget: "+str(quote.get("message",""))):return false
	var before_yard: Dictionary=home.duplicate(true);coins=int(c.state.coins)
	var fitted: Dictionary=c.workshop_apply(str(boat.uid),fit,quote)
	receipt.fitting085.merge({"result":fitted,"paid":coins-int(c.state.coins),"after":physical_boat(boat).duplicate(true),"itemsAfter":boat.moduleCondition.items.duplicate(true)})
	if not check(fitted.get("ok",false) and fitted.get("changed",false) and same_values(boat.loadout,fit) and int(c.state.coins)==coins-int(quote.cost),"Reviewed production fitting buys its exact bill and publishes the requested physical equipment"):return false
	for payment in [["cash","businessIncome"],["householdPurse","workerWages"],["expertPurse","expertWages"],["governmentPurse","tax"]]:
		if not check(int(home[payment[0]])==int(before_yard[payment[0]])+int(quote[payment[1]]),"Exact fitting payment reaches the existing "+str(payment[0])):return false
	for good in quote.materials:
		if not check(float(home.stocks[good])==float(before_yard.stocks[good])-float(quote.materials[good]),"Paid fitting consumes its quoted physical "+str(good)):return false
	for uid in original.moduleCondition.items:
		var item: Dictionary=boat.moduleCondition.items.get(uid,{}).duplicate(true)
		var expected: Dictionary=original.moduleCondition.items[uid].duplicate(true)
		for key in ["location","lockerOrder"]:item.erase(key);expected.erase(key)
		if not check(same_values(item,expected),"Original item UID and exact condition remain aboard or in its locker: "+str(uid)):return false
	for key in ["uid","type","crew","wounded","hp","maxHp","fuel","ammo","supplies","engine"]:
		if not check(same_values(boat.get(key),original.get(key)),"Paid fitting does not grant or reset the original "+key):return false
	# Two real guns increase the magazine to160. Buy the missing80 rounds normally.
	var ammo: float=float(boat.ammo);var target: float=float(boat.spec.ammoCapacity)
	var cases: float=(target-ammo)/c.Goods.ROUNDS_PER_CASE
	var ammo_cost: int=ceili(cases*c.Economy.price(home,"ammo")-0.000001)
	var ammo_stock: float=float(home.stocks.ammo);var ammo_cash: int=int(home.cash);coins=int(c.state.coins)
	var supplied: Dictionary=c.resupply_boat(str(boat.uid),"full")
	receipt.workingStores085={"result":supplied,"profile":"full","ammoBefore":ammo,"ammoAfter":boat.ammo,"cases":cases,"stockBefore":ammo_stock,"stockAfter":home.stocks.ammo,"paid":coins-int(c.state.coins),"cashBefore":ammo_cash,"cashAfter":home.cash,"fuel":boat.fuel,"supplies":boat.supplies}
	if not check(supplied.get("ok",false) and float(boat.ammo)==target and int(c.state.coins)==coins-ammo_cost and int(home.cash)==ammo_cash+ammo_cost and float(home.stocks.ammo)==ammo_stock-cases and boat.fuel==original.fuel and boat.supplies==original.supplies,"Normal full resupply buys the exact missing ammunition from real harbor stock without granting fuel or kits"):return false
	return check(npcs==var_to_bytes(c.state.fleetOwners) and c.Money.total(c.state)==supply and int(c.state.coinSupply)==supply and Custody085.check_state(c.state,c.data).get("ok",false),"Declared expedition purchases retain every NPC, original hull/item custody and conserved world coins")

func bounded() -> bool:
	if Time.get_ticks_msec()-started<58000:return true
	receipt.status="BODY_TIMEOUT"
	return check(false,"Stop work before58seconds, preserving saves and joined cleanup below60seconds")

func advance(seconds: float=4.0) -> bool:
	if not bounded():return false
	c.step(seconds)
	if not settle_days():return false
	for event in c.pop_events():
		if str(event.get("kind","")) not in ["encounter","ocean_encounter066","defeat"]:continue
		receipt.encounters085.append(event.duplicate(true))
		if event.get("kind")=="ocean_encounter066" and str(event.get("ownerId",event.get("id","")))==defender085:continue
		receipt.status="ACTUAL_UNRELATED_INTERRUPTION"
		return check(false,"Unrelated actual encounter interrupts this bounded case; it is not skipped or passed")
	return true

func opening085(context_only: bool=false) -> bool:
	var seed: int=85086
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-seed085="):seed=int(argument.trim_prefix("--qa-seed085="))
	var world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c=Campaign.new(world)
	if not check(c.new_game(seed).get("ok",false),"One ordinary seeded career opens"):return false
	supply=int(c.state.coinSupply)
	base_geography085=geography085()
	receipt.opening085={"seed":seed,"coins":c.state.coins,"fleet":c.state.fleet.map(func(b):return physical_boat(b).duplicate(true)),"earnedStarterProgression":false,"staging":"Fixed85086 advanced expedition: finite declared50000 home treasury advance, paid fitting/stores, player-only Glasswind waiting pose and later source berth, plus faction standings; all NPCs retain actual objectives, purses, fittings and movement."}
	var home: Dictionary=c.current_port()
	if not expedition085(home):return false
	# The existing075 chronology uses this authored safe-water player opening.
	# Keep HOME patrols and all NPC movement live; no encounter is consumed here.
	var waiting_assets: PackedByteArray=var_to_bytes(c.state)
	var wait_pose: Dictionary={"world064":{"schema":1,"layer":"local","regionId":c.OceanWorld064.REMOTE},"position":c.ocean_context064.regions[c.OceanWorld064.REMOTE].approaches[0].position,"heading":0.0,"path":[],"destination":""}
	var waiting: Dictionary=c.OceanWorld064.prepare_player(wait_pose,c.ocean_context064,c.Routes.clearance(c))
	if not check(waiting.get("ok",false),"Declared player-only Glasswind waiting pose passes ordinary safe-water preparation"):return false
	var before_wait: Dictionary=c.state.duplicate(true)
	c._publish_location064(waiting.location)
	for key in ["world064","position","heading","path","destination"]:before_wait[key]=c.state[key].duplicate(true) if c.state[key] is Dictionary or c.state[key] is Array else c.state[key]
	if not check(waiting_assets!=var_to_bytes(c.state) and var_to_bytes(before_wait)==var_to_bytes(c.state),"Declared waiting pose changes only player spatial fields; no NPC, resource, knowledge or clock writes"):return false
	receipt.declaredWait085={"location":c.world_location064(),"earnedVoyage":false,"npcPosesChanged":false}
	for _piece in range(400):
		corridor085=c.ShippingFlow068.corridor075(c.state).duplicate(true)
		if not corridor085.is_empty():break
		if not advance():return false
	if not check(not corridor085.is_empty(),"An existing merchant naturally earns funded two-group corridor admission"):return false
	defender085=str(corridor085.ownerId)
	var owner: Dictionary=c.fleet_owner(defender085)
	for id in [str(corridor085.remoteId),str(corridor085.originId)]:
		if c.port(id).get("faction")==owner.get("faction"):target085=id;break
	receipt.actualCorridor085={"corridor":corridor085,"ownerId":defender085,"faction":owner.get("faction"),"targetId":target085,"order":owner.get("order",{}).duplicate(true),"day":c.state.day,"route":c.state.shipping068.model.route.duplicate(true),"endpoints":[str(corridor085.originId),str(corridor085.remoteId)].map(func(id):return {"id":id,"faction":c.port(id).get("faction"),"regionId":c.port(id).get("regionId")}),"owner":owner.duplicate(true),"playerCoins":c.state.coins,"cargo":c.state.cargo.duplicate(true),"payrollPerDay":c.Economy.daily_upkeep(c.state.fleet).wages,"minimumLocalControlCoins":800+2*int(c.Economy.daily_upkeep(c.state.fleet).wages)}
	if target085.is_empty():receipt.status="INELIGIBLE_CORRIDOR_CONTEXT"
	if not check(not target085.is_empty(),"The actual corridor has a harbor governed by this actual merchant's faction; no reflagged or invented defender"):return false
	if context_only:return true # Endpoint match only; no presence/battle/control claim.
	source085=str(corridor085.originId) if target085==str(corridor085.remoteId) else str(corridor085.remoteId)
	var source: Dictionary=c.port(source085)
	var assets: PackedByteArray=var_to_bytes([c.state.fleet,c.state.fleetOwners,c.state.businesses,c.state.ports,c.state.cargo,c.state.coins])
	var location: Dictionary={"world064":{"schema":1,"layer":"local","regionId":source.regionId},"position":{"x":source.x,"y":source.y},"heading":0.0,"path":[],"destination":""}
	var prepared: Dictionary=c.OceanWorld064.prepare_player(location,c.ocean_context064,c.Routes.clearance(c))
	if not check(prepared.get("ok",false),"Declared initial player-only source berth is real navigable water"):return false
	c._publish_location064(prepared.location)
	c.ShippingFlow068.observe_sector069(c)
	if not check(assets==var_to_bytes([c.state.fleet,c.state.fleetOwners,c.state.businesses,c.state.ports,c.state.cargo,c.state.coins]),"Declared player pose changes no original NPC, hull, equipment, stock, workers or purse"):return false
	receipt.declaredPose085={"location":c.world_location064(),"earnedVoyage":false,"npcPosesChanged":false}
	var from_gate: Dictionary=corridor085.originGate if source085==str(corridor085.originId) else corridor085.remoteGate
	var to_gate: Dictionary=corridor085.remoteGate if target085==str(corridor085.remoteId) else corridor085.originGate
	if not gate(str(from_gate.regionId),str(from_gate.approachId)) or not gate(str(to_gate.regionId),str(to_gate.approachId)) or not sail(target085):return false
	var old: String=str(c.port(target085).faction)
	for faction in c.Factions.CANON:
		if faction!=old and faction!="raiders":sponsor085=str(faction);break
	var before: Dictionary=c.state.relationships.duplicate(true)
	c.state.relationships.factions[sponsor085].score=20;c.state.relationships.factions[sponsor085].band="friendly"
	c.state.relationships.factions[old].score=-60;c.state.relationships.factions[old].band="hostile"
	c.Factions.set_relation(c.state,old,sponsor085,-30,"Declared085 political opening; no earned standing claimed")
	receipt.declaredPolitics085={"before":before,"after":c.state.relationships.duplicate(true),"sponsor":sponsor085,"governor":old,"earnedStanding":false}
	for _piece in range(240):
		if not Territory085._defender(c,c.port(target085),defender085).is_empty():break
		if not advance(1.0):return false
	var treasury: int=int(c.port(target085).governmentPurse);var coins: int=int(c.state.coins)
	var begun: Dictionary=Territory085.start(c,target085,sponsor085)
	receipt.start085=begun
	return check(begun.get("ok",false) and c.state.territorial076.control.defenderId==defender085 and int(c.state.coins)==coins-800 and int(c.port(target085).governmentPurse)==treasury+800,"Land the original two spare sailors and pay800 once to this real remote treasury: "+str(begun.get("message","")))

func contest085(retreat: bool) -> bool:
	var admitted: Dictionary={}
	for _piece in range(240):
		admitted=c.encounter_context066(defender085)
		if admitted.get("ok",false):break
		if not advance(0.5):return false
	if not check(admitted.get("ok",false),"Actual original defender comes within75units with a fresh same-chart sighting"):return false
	var owner: Dictionary=c.fleet_owner(defender085)
	var enemy: Array=owner.boats.filter(func(b):return not b.sunk)
	var context: Dictionary=admitted.context
	context.ownerUids066=enemy.map(func(b):return str(b.uid))
	var geography: Dictionary={"ISLANDS":c.world_view064().get("islands",[])}
	var options: Dictionary=Coast085.arena(geography,c.state.position)
	options.merge({"fleet":c.FleetSupport.combat(c),"enemyFleet":enemy,"seed":int(c.state.seed)},true)
	var battle: Dictionary=Battle085.create(options)
	battle.world064=c.state.world064.duplicate(true);battle.chartPosition=c.state.position.duplicate(true)
	if not check(str(battle.get("startError","")).is_empty(),"Actual remote island arena admits original physical combatants"):Battle085._close_damage_owned051(battle);return false
	if retreat:Battle085.retreat(battle)
	for _tick in range(2400):
		if battle.result!=null:break
		if not bounded():Battle085._close_damage_owned051(battle);return false
		Battle085.update(battle,1.0/30.0,{})
	if not check(battle.result!=null,"Actual battle reaches its own terminal result"):Battle085._close_damage_owned051(battle);return false
	var result: Dictionary=c.battle_settled(str(battle.result),enemy.map(func(b):return b.spec),context,battle)
	receipt.contests085.append({"declaredRetreatOrder":retreat,"result":battle.result,"seconds":battle.time,"report":result,"control":c.state.territorial076.control.duplicate(true)})
	Battle085._close_damage_owned051(battle)
	if not check(result.get("ok",true) and c.Money.total(c.state)==supply,"Native offshore settlement retains original custody and finite purses"):return false
	return check(str(battle.result)==("retreated" if retreat else "won"),"Requested continuation requires its actual terminal result; no manufactured victory or retreat")

func control085() -> bool:
	var active: Dictionary=parsed_save("remote-control085-active")
	if active.is_empty():return false
	var active_path: String=OS.get_environment("GAME_TEST_ARTIFACTS").path_join("career070-remote-control085-active.json")
	receipt.activeArtifact085={"path":active_path,"sha256":FileAccess.get_sha256(active_path),"pendingDays":c.pending_days,"scope":"Actual paid active prefix; no reconstructed preparation or outcome."}
	if not restore_exact(active,"remote-control085-active"):return false
	# One invalid copy of the actual paid prefix: swapping corridor ends must
	# not manufacture another admitted route or alter either physical account.
	var false_route: Dictionary=active.duplicate(true)
	false_route.territorial076.control.corridor085.originId=corridor085.remoteId
	false_route.territorial076.control.corridor085.remoteId=corridor085.originId
	var route_input: PackedByteArray=var_to_bytes(false_route)
	var before_route: PackedByteArray=protected_state()
	var refused_route: Dictionary=c.restore(false_route)
	if not check(not refused_route.get("ok",false) and protected_state()==before_route and var_to_bytes(false_route)==route_input,"Control receipt cannot substitute reversed endpoints for its actual admitted075 corridor"):return false
	receipt.corridorRefusal085={"message":refused_route.get("message",""),"actual":active.territorial076.control.corridor085,"substituted":false_route.territorial076.control.corridor085}
	if not contest085(true):return false
	var interrupted: Dictionary=c.state.territorial076.control
	var frozen: PackedByteArray=protected_state()
	if not check(interrupted.status=="interrupted" and interrupted.funded==800 and not interrupted.battleWon and not Territory085.negotiate(c).get("ok",false) and protected_state()==frozen,"Real retreat interrupts the supplier, retains its paid treasury contribution and cannot grant surrender"):return false
	receipt.interrupted085={"control":interrupted.duplicate(true),"coins":c.state.coins,"treasury":c.port(target085).governmentPurse,"paidSupportDays":interrupted.supportDays,"limit":"Actual retreat continuation from the same funded prefix; no supplied day is invented."}
	# Separate continuation of the exact saved finite prefix, never earned travel
	# or a resurrection within either branch. The actual active save must restore.
	if not restore_exact(active,"remote-control085-success-fork"):return false
	if not contest085(false):return false
	for _piece in range(40):
		if int(c.state.territorial076.control.supportDays)==2:break
		if not advance():return false
	var job: Dictionary=c.state.territorial076.control
	if not check(job.status=="active" and job.supportDays==2 and job.supportGoods=={"food":4.0,"supplies":2.0} and int(c.state.wageArrears)==0 and payroll>0,"Actual published payroll and two local support days deliver exactly4food/2repair-kit lots"):return false
	var private_assets: PackedByteArray=var_to_bytes([c.state.businesses,c.state.tooling,c.state.territorial076.improvement])
	var total: int=c.Money.total(c.state)
	var negotiated: Dictionary=Territory085.negotiate(c)
	if not check(negotiated.get("ok",false) and c.port(target085).faction==sponsor085 and job.status=="complete" and c.Money.total(c.state)==total and private_assets==var_to_bytes([c.state.businesses,c.state.tooling,c.state.territorial076.improvement]),"Explicit funded surrender changes this harbor alone and retains companies, tools,084 receipts and all purses"):return false
	var unchanged: PackedByteArray=protected_state()
	if not check(Territory085.negotiate(c).get("changed",true)==false and protected_state()==unchanged,"Repeated negotiation consumes and grants nothing"):return false
	var saved: Dictionary=parsed_save("remote-control085-completed")
	if saved.is_empty() or not restore_exact(saved,"remote-control085-completed"):return false
	if not check(same_values(saved.territorial076,c.state.territorial076) and c.port(target085).faction==sponsor085 and c.Politics.access(c,c.port(target085)).get("legal",false) and c.work_port070().get("id")==target085,"Exact paid control receipt and new governor's actual berth access survive disk restore"):return false
	# Leave through the actual approach and return by the ordinary paired gate;
	# this is movement after the declared opening, never another pose assignment.
	var return_gate: Dictionary=corridor085.remoteGate if target085==str(corridor085.remoteId) else corridor085.originGate
	if not gate(str(return_gate.regionId),str(return_gate.approachId)) or not gate(str(return_gate.regionId),str(return_gate.approachId)) or not sail(target085):return false
	if not check(c.port(target085).faction==sponsor085 and c.work_port070().get("id")==target085,"Actual departure and ordinary return retain this harbor's new governor and paid-service access"):return false
	receipt.traffic085={"day":c.state.day,"merchantRoute":c.state.shipping068.model.route.duplicate(true),"otherContact":c.state.ocean066.contact.duplicate(true),"datedLog":c.state.log.slice(0,8),"limit":"Actual short continuation; unchanged075 paid-recovery coverage is retained by source proof, not claimed newly executed here."}
	saved=JSON.parse_string(JSON.stringify(c.state))
	var bad: Dictionary=saved.duplicate(true)
	var neighbor: Dictionary=bad.ports.filter(func(p):return str(p.id)==source085)[0]
	for faction in c.Factions.CANON:
		if faction!=neighbor.faction:neighbor.faction=faction;break
	var bad_input: PackedByteArray=var_to_bytes(bad);unchanged=protected_state()
	if not check(not c.restore(bad).get("ok",false) and protected_state()==unchanged and var_to_bytes(bad)==bad_input,"One unexplained neighboring governor refuses before live or input publication"):return false
	if not check(same_values(base_geography085,geography085()) and c.Money.total(c.state)==supply and Custody085.check_state(c.state,c.data).get("ok",false),"Complete decoded seeded groups/island ownership, finite coins and unique original hull/item/wreck custody remain exact"):return false
	receipt.completedControl085=c.state.territorial076.control.duplicate(true)
	return true

func opening_context085(stage: String="opening") -> void:
	if c==null or c.state.is_empty():return
	var before: PackedByteArray=protected_state()
	var saved: Dictionary=parsed_save("remote-control085-context")
	if saved.is_empty():return
	var directory: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	var path: String=directory.path_join("career070-remote-control085-context.json")
	var owner: Dictionary=c.fleet_owner(defender085) if not defender085.is_empty() else {}
	var context: Dictionary={"status":receipt.status,"stage":stage,"earnedControl085":false,"diagnosticOnly":true,"seed":c.state.seed,"day":c.state.day,"econDay":c.state.econDay,"coins":c.state.coins,"crewPurse":c.state.crewPurse,"wageArrears":c.state.wageArrears,"cargo":c.state.cargo.duplicate(true),"pendingDays":c.pending_days,"payroll":payroll,"location":c.world_location064(),"corridor":c.ShippingFlow068.corridor075(c.state).duplicate(true),"targetId":target085,"sourceId":source085,"sponsor":sponsor085,"control":c.state.get("territorial076",{}).get("control",{}).duplicate(true),"defender":owner.duplicate(true),"encounters":receipt.encounters085.duplicate(true),"pendingEvents":c.events.duplicate(true),"stateArtifact":{"path":path,"sha256":FileAccess.get_sha256(path)},"scope":"Actual current opening/control failure context, not reconstructed progress; resumption requires hash-bound production restore and handling pending days/encounters. Operation state is recorded without acceptance."}
	var context_path: String=directory.path_join("remote-control085-opening-context.json")
	var file=FileAccess.open(context_path,FileAccess.WRITE)
	if not check(file!=null,"Private actual "+stage+" context artifact opens"):return
	file.store_string(JSON.stringify(context,"\t"));file.close()
	receipt.contextArtifact085={"path":path,"sha256":context.stateArtifact.sha256,"pendingDays":c.pending_days,"status":receipt.status,"stage":stage,"summaryPath":context_path,"summarySha256":FileAccess.get_sha256(context_path),"scope":context.scope}
	check(protected_state()==before,"Saving actual failed/diagnostic context changes no live state, pending work, events or physical accounts")

func _run() -> void:
	receipt.fixture="remote_control085";receipt.earnedControl085=false;receipt.erase("earnedVoyage")
	receipt.encounters085=[];receipt.supplyInvoices085=[];receipt.contests085=[]
	var context_only: bool=OS.get_cmdline_user_args().has("--qa-eligibility085")
	receipt.diagnosticOnly=context_only
	if check(OS.get_environment("GAME_TEST_ARTIFACTS").is_absolute_path(),"Root supplies private artifacts/profile"):
		if context_only:
			if opening085(true):receipt.status="MATCHING_ENDPOINT_CONTEXT_ONLY"
			elif receipt.status=="UNFINISHED":receipt.status="OPENING_FAILED"
			opening_context085()
		else:
			var opened: bool=opening085()
			if opened:
				if control085():receipt.earnedControl085=true;receipt.status="COMPLETED"
				else:
					if receipt.status=="UNFINISHED":receipt.status="CONTROL_FAILED"
					opening_context085("control")
			else:
				if receipt.status=="UNFINISHED":receipt.status="OPENING_FAILED"
				opening_context085()
	if workers.group_id>=0:workers.finish(true)
	c=null
	receipt.elapsedMs=Time.get_ticks_msec()-started
	check(int(receipt.elapsedMs)<60000,"Whole085 case including setup, both continuations, saves and joined cleanup stays below60seconds")
	receipt.checks=checks;receipt.failures=failures
	if not receipt.earnedControl085 and receipt.status=="UNFINISHED":receipt.status="FAILED"
	var directory: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if directory.is_absolute_path():
		var file=FileAccess.open(directory.path_join("remote-control085-result.json"),FileAccess.WRITE)
		if file:file.store_string(JSON.stringify(receipt,"\t"));file.close()
	print("REMOTE085_RESULT ",JSON.stringify(receipt))
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 and (receipt.earnedControl085 or (context_only and receipt.status=="MATCHING_ENDPOINT_CONTEXT_ONLY")) else 1)
