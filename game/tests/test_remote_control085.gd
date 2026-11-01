extends "res://tests/test_voyage_career070.gd"
## Root-only one-harbor case. Ordinary15000 opening, finite paid stores/fitting,
## naturally admitted/moving075 merchant. Only player pose and diplomacy are
## declared. No NPC pose/faction, resources, sightings or battle result is set.
const Territory085=preload("res://scripts/territorial076.gd")
const Battle085=preload("res://scripts/battle.gd")
const Coast085=preload("res://scripts/coastal_terrain.gd")
const Custody085=preload("res://scripts/equipment_campaign.gd")
var target085: String=""
var defender085: String=""
var sponsor085: String=""
var corridor085: Dictionary={}
var source085: String=""
var base_geography085: String=""

func bounded() -> bool:
	if Time.get_ticks_msec()-started<43000:return true
	receipt.status="BODY_TIMEOUT"
	return check(false,"Stop work before43seconds, preserving joined cleanup below45seconds")

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

func opening085() -> bool:
	var seed: int=69069
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-seed085="):seed=int(argument.trim_prefix("--qa-seed085="))
	var world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c=Campaign.new(world)
	if not check(c.new_game(seed).get("ok",false),"One ordinary seeded career opens"):return false
	supply=int(c.state.coinSupply)
	base_geography085=JSON.stringify(c.state.sector069,"",true)+JSON.stringify(c.state.islandOwnership069,"",true)
	receipt.opening085={"seed":seed,"coins":c.state.coins,"fleet":c.state.fleet.map(func(b):return physical_boat(b).duplicate(true)),"staging":"Only the later player opening pose and faction standings are declared; all NPCs retain their actual ordinary objectives and movement."}
	var home: Dictionary=c.current_port()
	for good in ["food","supplies"]:
		var quantity: int=4 if good=="food" else 2
		var buy_coins: int=int(c.state.coins);var cash: int=int(home.cash);var stock: float=float(home.stocks[good]);var cargo: float=float(c.state.cargo[good])
		var invoice: Dictionary=c.trade(str(home.id),good,quantity,"buy")
		if not check(invoice.get("ok",false) and int(invoice.qty)==quantity and int(c.state.coins)==buy_coins-int(invoice.coins) and int(home.cash)==cash+int(invoice.coins) and float(home.stocks[good])==stock-quantity and float(c.state.cargo[good])==cargo+quantity,"Actual seller supplies the carried "+good+" for its exact finite invoice"):return false
		receipt.supplyInvoices085.append(invoice)
	# Pay the existing workshop for a real original-UID fitting before departure.
	var boat: Dictionary=c.state.fleet[0]
	var fit: Dictionary=boat.loadout.duplicate(true);fit.weapons[0]="rapid_gun"
	var coins: int=int(c.state.coins)
	var fitted: Dictionary=c.workshop_apply(str(boat.uid),fit,{})
	if not check(fitted.get("ok",false) and int(c.state.coins)<coins and c.find_boat(str(boat.uid)).loadout.weapons[0]=="rapid_gun" and c.Money.total(c.state)==supply,"Existing workshop supplies a paid physical gun; no equipment or captain money grant"):return false
	receipt.fitting085={"result":fitted,"paid":coins-int(c.state.coins),"boatUid":boat.uid}
	for _piece in range(400):
		corridor085=c.ShippingFlow068.corridor075(c.state).duplicate(true)
		if not corridor085.is_empty():break
		if not advance():return false
	if not check(not corridor085.is_empty(),"An existing merchant naturally earns funded two-group corridor admission"):return false
	defender085=str(corridor085.ownerId)
	var owner: Dictionary=c.fleet_owner(defender085)
	for id in [str(corridor085.remoteId),str(corridor085.originId)]:
		if c.port(id).get("faction")==owner.get("faction"):target085=id;break
	receipt.actualCorridor085={"corridor":corridor085,"ownerId":defender085,"faction":owner.get("faction"),"targetId":target085,"order":owner.get("order",{}).duplicate(true)}
	if not check(not target085.is_empty(),"The actual corridor has a harbor governed by this actual merchant's faction; no reflagged or invented defender"):return false
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
	var treasury: int=int(c.port(target085).governmentPurse);coins=int(c.state.coins)
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
	options.merge({"fleet":c.FleetSupport.combat(c),"enemyFleet":enemy,"seed":85085},true)
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
	if active.is_empty() or not restore_exact(active,"remote-control085-active"):return false
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
	if not check(base_geography085==JSON.stringify(c.state.sector069,"",true)+JSON.stringify(c.state.islandOwnership069,"",true) and c.Money.total(c.state)==supply and Custody085.check_state(c.state,c.data).get("ok",false),"Seeded groups/island ownership, finite coins and unique original hull/item/wreck custody remain intact"):return false
	receipt.completedControl085=c.state.territorial076.control.duplicate(true)
	return true

func _run() -> void:
	receipt.fixture="remote_control085";receipt.earnedControl085=false;receipt.erase("earnedVoyage")
	receipt.encounters085=[];receipt.supplyInvoices085=[];receipt.contests085=[]
	if check(OS.get_environment("GAME_TEST_ARTIFACTS").is_absolute_path(),"Root supplies private artifacts/profile") and opening085() and control085():receipt.earnedControl085=true;receipt.status="COMPLETED"
	if workers.group_id>=0:workers.finish(true)
	c=null
	receipt.elapsedMs=Time.get_ticks_msec()-started
	check(int(receipt.elapsedMs)<45000,"Whole085 case including setup, both continuations, saves and joined cleanup stays below45seconds")
	receipt.checks=checks;receipt.failures=failures
	if not receipt.earnedControl085 and receipt.status=="UNFINISHED":receipt.status="FAILED"
	var directory: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if directory.is_absolute_path():
		var file=FileAccess.open(directory.path_join("remote-control085-result.json"),FileAccess.WRITE)
		if file:file.store_string(JSON.stringify(receipt,"\t"));file.close()
	print("REMOTE085_RESULT ",JSON.stringify(receipt))
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 and receipt.earnedControl085 else 1)
