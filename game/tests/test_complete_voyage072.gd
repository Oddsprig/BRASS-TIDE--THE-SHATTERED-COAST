extends "res://tests/test_voyage_career070.gd"
## SOURCE ONLY. Root runs one fresh career through Test Bridge/private artifacts.
## Reuses070's earned work, exact saves, payroll, escrow and store replacement.
## Ordinary accounts may spend starting capital on this risky detour. No net
## profit or preserved15000-coin claim;070's stronger assertions remain separate.
## No checkpoint replay, grants, actor/clock/position edits or controlled damage.
const Main072=preload("res://scripts/main.gd")
const Equipment072=preload("res://scripts/equipment_records.gd")
const COAST_PORT072: String="reed_floats"
const SEEK_SECONDS072: float=120.0
var main072
var seeking072: bool=false
var encounter072: Dictionary={}
var owner_id072: String=""
var uid072: String=""
var battle_delta072: int=0
var repair_cost072: int=0
var upgrade_cost072: int=0
var hire_cost072: int=0
var finished072: bool=false

func check(value: bool,message: String) -> bool:
	checks+=1
	if not value:failures+=1;print("FAIL complete072: ",message)
	return value

func bounded() -> bool:
	if not finished072 and Time.get_ticks_msec()-started<51500:return true
	receipt.status="BODY_TIMEOUT"
	return check(false,"55-second whole body reserves time for owned worker/Main cleanup")

func gap072(code: String,message: String) -> bool:
	receipt.status="ROUTE_GAP"
	receipt.gap={"code":code,"message":message,"day":float(c.state.day),"coins":int(c.state.coins),"position":c.state.position.duplicate(true)}
	return check(false,message)

func phase(label: String) -> void:
	var row: Dictionary={"phase":label,"elapsedMs":Time.get_ticks_msec()-started,"day":float(c.state.day),"coins":int(c.state.coins),"world":c.world_location064().world064,"position":c.state.position.duplicate(true)}
	receipt.phases.append(row);print("COMPLETE072_PHASE ",JSON.stringify(row))

func advance(seconds: float) -> bool:
	if not bounded():return false
	var before: float=float(c.state.day)
	c.step(seconds)
	if not settle_days():return false
	var intercepted: bool=false
	for event in c.pop_events():
		var kind: String=str(event.get("kind",""))
		if kind=="defeat":return gap072("VOYAGE_LOSS","Actual loss ends this same career; no replacement fleet granted")
		if kind not in ["encounter","ocean_encounter066"]:continue
		if not seeking072:
			receipt.unexpectedEncounter=event
			return gap072("INTERRUPTED","An actual encounter interrupted the planned work/return leg")
		if not encounter072.is_empty():return gap072("MULTIPLE_CONTACTS","A second actual encounter interrupted the bounded detour")
		encounter072=event.duplicate(true);intercepted=true
	var accepted: float=float(c.state.day)-before
	if not check((accepted>0.0 or intercepted) and accepted>=0.0 and accepted<=seconds/45.0+0.000001,"Only accepted normal sailing/work advances the clock; an actual interception may clip to zero"):return false
	return check(int(c.state.coinSupply)==supply and c.Money.total(c.state)==supply,"Every original harbor, client, crew and fleet purse conserves the initial coin supply")

func sighting072(id: String="") -> Dictionary:
	var nearest: Dictionary={}
	var distance: float=INF
	# This is the game's ordinary local observation API, not hidden patrol intel.
	for seen in c.NavalAI.observe(c.state):
		if not seen.get("current",false) or (not id.is_empty() and str(seen.ownerId)!=id):continue
		if c.NavalAI.NavalOrders.enrolled066(c.state,str(seen.ownerId)):continue
		var owner: Dictionary=c.fleet_owner(str(seen.ownerId))
		if not c.Politics.hostile(c,owner):continue
		var candidate: float=c.distance(c.state.position,seen)
		if candidate<distance:nearest=seen.duplicate(true);distance=candidate
	return nearest

func seek_contact072() -> bool:
	phase("earned_coastal_exploration_and_actual_hostile_approach")
	if not check(c.home_local064(),"Physical HOME crossing precedes coastal observation"):return false
	var port: Dictionary=c.port(COAST_PORT072)
	var route: Dictionary=c.chart_course({"x":port.x,"y":port.y},COAST_PORT072)
	if not check(route.get("ok",false),"Normal exploration course to existing Reed Floats: "+str(route.get("message",""))):return false
	var began: float=float(c.state.day)*45.0
	var last_plan: float=-INF
	var last_seen: Dictionary={}
	seeking072=true
	for _piece in range(240):
		if not bounded():return false
		if not encounter072.is_empty():break
		var seen: Dictionary=sighting072(owner_id072)
		if not seen.is_empty():
			if owner_id072.is_empty():receipt.firstHostileSighting=seen.duplicate(true)
			owner_id072=str(seen.ownerId);last_seen=seen
			if c.distance(c.state.position,seen)<=75.0:
				c.stop_sailing();break # Normal stop, not an invented encounter event.
			if float(c.state.day)*45.0-last_plan>=2.0:
				route=c.chart_course({"x":seen.x,"y":seen.y})
				if not check(route.get("ok",false),"Real water course to the current dated hostile sighting: "+str(route.get("message",""))):return false
				last_plan=float(c.state.day)*45.0
		elif c.state.path.is_empty():
			return gap072("NO_CURRENT_HOSTILE","Reached the real exploration/last-sighting endpoint without a currently observed hostile")
		if float(c.state.day)*45.0-began>=SEEK_SECONDS072:break
		if not advance(0.5):return false
	if not encounter072.is_empty():
		if str(encounter072.kind)!="encounter":return gap072("WRONG_CHART_CONTACT","Unexpected offshore contact on this HOME detour")
		owner_id072=str(encounter072.patrol)
	var patrol: Dictionary=c.NavalAI._find_patrol(c.state,owner_id072)
	var fresh: Dictionary=sighting072(owner_id072)
	if patrol.is_empty() or fresh.is_empty() or c.distance(c.state.position,patrol)>75.0001:
		receipt.lastHostileSighting=last_seen
		return gap072("INTERCEPTION_NOT_REACHED","No existing hostile physically reached within75units during the bounded ordinary detour")
	if not check(c.Politics.hostile(c,c.fleet_owner(owner_id072)) and not c.NavalAI.NavalOrders.enrolled066(c.state,owner_id072),"Actual current hostile remains owned and on this chart"):return false
	receipt.encounter={"ownerId":owner_id072,"event":encounter072,"sighting":fresh,"playerPosition":c.state.position.duplicate(true),"hostilePosition":{"x":patrol.x,"y":patrol.y},"distance":c.distance(c.state.position,patrol),"acceptedDetourSeconds":float(c.state.day)*45.0-began}
	return true

func battle072() -> bool:
	phase("actual_owned_worker_battle_and_normal_withdrawal")
	var player: Dictionary=c.find_boat(uid072)
	var original: Dictionary=physical_boat(player).duplicate(true)
	var owner: Dictionary=c.fleet_owner(owner_id072)
	var enemies: Array=owner.boats.filter(func(b):return not b.get("sunk",false))
	if not check(not enemies.is_empty(),"Observed hostile has existing physical boats before Main engagement"):return false
	var enemy_uids: Array=enemies.map(func(b):return str(b.uid))
	var coins: int=int(c.state.coins)
	main072.engage_patrol(c.NavalAI._find_patrol(c.state,owner_id072))
	if not check(main072.mode=="battle" and main072.battle_driver051!=null and not main072.quick_mode and not main072.lab_active,"Actual Main engagement starts the existing detached30Hz worker"):return false
	if not check(str(main072.battle_context.ownerId)==owner_id072 and main072.battle.ships.filter(func(b):return b.team=="enemy").map(func(b):return str(b.uid))==enemy_uids,"Battle uses exactly the observed owner's original UIDs, no fallback targets"):return false
	var withdrew: bool=false
	var damaged: bool=false
	for _poll in range(720):
		if not bounded():return false
		if main072.battle.get("result")!=null:break
		for shown in main072.battle.get("ships",[]):
			if str(shown.get("uid",""))==uid072:
				damaged=damaged or float(shown.hp)<float(original.hp) or float(shown.wounded)>float(original.wounded) or float(shown.engine)<float(original.engine)
		if not withdrew and (damaged or float(main072.battle.time)>=20.0):
			main072.withdraw_fleet();withdrew=true
			receipt.withdrawOrder={"battleSecond":main072.battle.time,"observedPlayerDamage":damaged}
		main072.poll_battle051(0.1,false)
		await process_frame
	if main072.battle.get("result")==null:return gap072("BATTLE_UNFINISHED","Normal worker battle/12-second withdrawal did not finish inside this one bounded body")
	main072.settle_battle()
	if not check(main072.battle_driver051==null and not main072.battle_report.is_empty() and main072.battle_report.get("ok",true),"Worker joined before physical settlement and retirement"):return false
	if not withdrew or str(main072.battle.result)!="retreated":return gap072("WITHDRAWAL_NOT_COMPLETED","Actual battle ended as "+str(main072.battle.result)+"; this fixture cannot claim its requested normal withdrawal")
	if not check(is_same(c.find_boat(uid072),player) and not player.get("sunk",false),"Same actual starter object/UID survives; no replacement hull or crew"):return false
	for enemy in enemies:
		var retained: bool=c.fleet_owner(owner_id072).boats.any(func(b):return is_same(b,enemy))
		var captured: bool=(c.state.fleet+c.state.get("boardingPrizes",[])).any(func(b):return is_same(b,enemy))
		var wrecked: bool=c.state.wrecks.any(func(w):return str(w.get("uid",""))==str(enemy.uid))
		if not check(retained or captured or wrecked,"Original hostile UID retains actual boat/prize/wreck custody"):return false
	battle_delta072=int(c.state.coins)-coins
	receipt.battle={"result":main072.battle.result,"withdrawOrdered":withdrew,"observedPlayerDamage":damaged,"battleSeconds":main072.battle.time,"playerBefore":original,"playerAfter":physical_boat(player).duplicate(true),"enemyUids":enemy_uids,"coinDelta":battle_delta072,"crewLost":float(original.crew)-float(player.crew),"report":main072.battle_report.duplicate(true)}
	var frozen: PackedByteArray=protected_state()
	var repeated: Dictionary=c.battle_settled(str(main072.battle.result),main072.battle_enemies,main072.battle_context,main072.battle)
	if not check(same_values(repeated,main072.battle_report) and protected_state()==frozen,"Repeated physical settlement changes no coins, people, stores, custody or caches"):return false
	main072.return_to_campaign();seeking072=false
	return check(main072.mode=="campaign" and c.travel_lock064.is_empty() and c.Money.total(c.state)==supply,"Normal settled return releases travel lock and conserves all purses")

func topology072(boat: Dictionary) -> Dictionary:
	var snapshot: Dictionary=Equipment072.snapshot(boat)
	if not snapshot.get("ok",false):return {}
	var topology: Dictionary={"birthNamespace":snapshot.birthNamespace,"nextItemSeq":snapshot.nextItemSeq,"items":{}}
	for item in snapshot.get("installedItems",[]):topology.items[str(item.itemUid)]={"location":str(item.location),"typeId":str(item.typeId)}
	return topology

func paid_repair072() -> bool:
	phase("actual_paid_repair_at_reached_harbor")
	var boat: Dictionary=c.find_boat(uid072)
	var port: Dictionary=c.current_port()
	var quote: Dictionary=c.service_quote(boat,port)
	receipt.repairQuote=quote
	if not quote.get("ok",false):return gap072("REPAIR_QUOTE_REFUSED",str(quote.get("message",quote.get("error","No actual repair quote"))))
	if int(quote.cost)<=0 or float(quote.workerDays)<=0.0:return gap072("NO_PAID_REPAIR_NEEDED","Natural combat/recovery left no actual positive-cost drydock work; no damage manufactured")
	var before: Dictionary=physical_boat(boat).duplicate(true)
	var topology: Dictionary=topology072(boat)
	var stocks: Dictionary=port.stocks.duplicate(true)
	var purses: Dictionary={}
	for key in ["cash","householdPurse","expertPurse","governmentPurse"]:purses[key]=port[key]
	var workers_used: float=float(port.get("_yardWorkersUsed",0))
	var coins: int=int(c.state.coins)
	var result: Dictionary=c.repair_boat(uid072)
	if not result.get("ok",false):return gap072("PAID_REPAIR_REFUSED",str(result.get("message","Actual harbor repair refused")))
	if not check(int(result.cost)==int(quote.cost) and int(c.state.coins)==coins-int(quote.cost) and int(port.cash)==int(purses.cash)+int(quote.materials)+int(quote.fee) and int(port.householdPurse)==int(purses.householdPurse)+int(quote.ordinary) and int(port.expertPurse)==int(purses.expertPurse)+int(quote.expert) and int(port.governmentPurse)==int(purses.governmentPurse),"Actual repair pays the exact suppliers, shipwrights, treatment specialists and yard fee"):return false
	if not check(is_equal_approx(float(port.stocks.supplies),float(stocks.supplies)-float(quote.purchase)) and is_equal_approx(float(boat.supplies),float(before.supplies)-float(quote.own)),"Repair consumes the quote's finite harbor kits and original onboard kits"):return false
	for good in quote.equipmentMaterials:
		if not check(is_equal_approx(float(port.stocks[good]),float(stocks[good])-float(quote.equipmentMaterials[good])),"Repair consumes actual "+str(good)+" stock"):return false
	var restored: Dictionary=c.service_quote(boat,port)
	if not check(not topology.is_empty() and topology072(boat)==topology and float(boat.crew)==float(before.crew) and float(boat.hp)==float(boat.maxHp) and float(boat.wounded)==0.0 and boat.breaches.is_empty() and float(boat.water)==0.0 and float(boat.fire)==0.0 and float(port.get("_yardWorkersUsed",0))>workers_used and restored.get("ok",false) and int(restored.cost)==0,"Paid recovery retains physical equipment UIDs and numerical crew, restores actual hull/equipment condition and uses real labor"):return false
	repair_cost072=int(quote.cost)
	receipt.repair={"actualPort":port.id,"uid":uid072,"cost":repair_cost072,"before":before,"after":physical_boat(boat).duplicate(true),"quote":quote,"pursesBefore":purses,"installedUids":topology}
	return check(c.Money.total(c.state)==supply,"Paid repair conserves every original world account")

func paid_improvement072() -> bool:
	phase("home_return_and_affordable_useful_paid_improvement")
	var boat: Dictionary=c.find_boat(uid072)
	var port: Dictionary=c.current_port()
	var permission: Dictionary=c.Politics.permit(c,"service")
	var quote: Dictionary=c.FleetIdentity.specialist_quote(c.state,boat,port,"surveyor",permission)
	receipt.surveyorQuote=quote
	if not quote.get("eligible",false) or int(quote.advance)<=0 or int(c.state.coins)<int(quote.advance):return gap072("IMPROVEMENT_UNAFFORDABLE",str(quote.get("message","No affordable useful existing improvement")))
	var coins: int=int(c.state.coins);var purse: int=int(c.state.crewPurse)
	var people: int=int(port.workforce);var recruits: int=int(port.recruits)
	var crew: float=float(boat.crew);var factor: float=float(boat.spec.get("surveyFactor",1.0))
	var result: Dictionary=c.FleetIdentity.hire_specialist(c,uid072,"surveyor")
	if not check(result.get("ok",false),"Real paid existing surveyor hire: "+str(result.get("message",""))):return false
	if not check(int(c.state.coins)==coins-int(quote.advance) and int(c.state.crewPurse)==purse+int(quote.advance) and int(port.workforce)==people-1 and int(port.recruits)==recruits-1 and float(boat.crew)==crew+1.0,"Exact ordinary-purse advance transfers one existing worker into a real crew berth"):return false
	if not check(float(boat.spec.get("surveyFactor",1.0))>factor and boat.get("specialistActive",{}).get("surveyor",false),"Purchased specialist usefully improves the same hull's existing survey work rate"):return false
	upgrade_cost072=int(quote.advance)
	receipt.upgrade={"specialist":"surveyor","cost":upgrade_cost072,"funding":"Ordinary voyage purse including remaining starting capital; no net-profit-only claim","netBeforePurchase":coins-int(c.data.START.coins),"netAfterPurchase":int(c.state.coins)-int(c.data.START.coins),"surveyFactorBefore":factor,"surveyFactorAfter":boat.spec.surveyFactor,"baseDailyWage":quote.basePerDay,"premiumDailyWage":quote.premiumPerDay}
	return check(c.Money.total(c.state)==supply,"Useful paid improvement conserves the actual purse and workforce transfers")

func _run() -> void:
	receipt.fixture="complete_voyage072";receipt.wholeLoop=false
	receipt.notRerun=["070 controlled corrupt-input cases (not passed by072)","070 net-profit-only upgrade and preserved15000capital assertions (unchanged in070)"]
	if not check(OS.get_environment("GAME_TEST_ARTIFACTS").is_absolute_path(),"Root supplies one private artifact/profile directory"):await finish072();return
	main072=Main072.new();main072.qa_ocean066=true
	root.add_child.call_deferred(main072)
	await main072.ready
	main072.set_process(false);main072.set_physics_process(false);main072.paused=true
	main072.new_game(69069);c=main072.core
	if not check(not c.state.is_empty(),"Actual Main creates one ordinary fresh69069career"):await finish072();return
	supply=int(c.state.coinSupply);uid072=str(c.state.fleet[0].uid)
	receipt.initial={"coins":c.state.coins,"coinSupply":supply,"boat":physical_boat(c.state.fleet[0]).duplicate(true),"cargo":c.state.cargo.duplicate(true)}
	var before_work: int=int(c.state.coins)
	if not earned_work070(false):await finish072();return
	#070's accepted work has no other captain transfers: paid two-person hire,
	# escrow receipts and exact daily payroll. Keep that identity reviewable.
	hire_cost072=before_work+gross_paid-payroll-int(c.state.coins)
	if not check(hire_cost072==2*c.Goods.SAILOR_WAGE*10,"Earned work charges exactly the original two normal hiring advances"):await finish072();return
	phase("earned_work_complete_and_physical_home_crossings")
	if not gate(REGION,"north") or not gate("shatter_coast","south") or not seek_contact072():await finish072();return
	if not (await battle072()):await finish072();return
	if not sail(COAST_PORT072) or not paid_repair072() or not sail("brass_haven"):await finish072();return
	phase("home_replacement_stores_after_work_combat_and_repair")
	if not check(c.current_port().get("id")=="brass_haven" and str(c.find_boat(uid072).uid)==uid072 and int(c.state.wageArrears)==0 and payroll>0 and gross_paid>0,"Same working starter physically returns HOME with real income and all payroll paid"):await finish072();return
	var ammo: float=float(c.find_boat(uid072).ammo)
	if not replace_stores() or not paid_improvement072():await finish072();return
	receipt.replacementStores.ammo=float(c.find_boat(uid072).ammo)-ammo
	var expected: int=int(c.data.START.coins)-hire_cost072+gross_paid+battle_delta072-payroll-repair_cost072-int(receipt.replacementStores.paidCoins)-upgrade_cost072
	if not check(int(c.state.coins)==expected,"Ending ordinary purse reconciles all income, combat proceeds/losses, hiring, payroll, paid repair, replacement stores and improvement"):await finish072();return
	var saved: Dictionary=parsed_save("completed072")
	if saved.is_empty() or not restore_exact(saved,"completed072"):await finish072();return
	receipt.accounting={"startingCoins":c.data.START.coins,"grossClientEscrowPaid":gross_paid,"crewHiringAdvance":hire_cost072,"payrollPaid":payroll,"battleCoinDelta":battle_delta072,"repairPaid":repair_cost072,"replacementStoresPaid":receipt.replacementStores.paidCoins,"usefulImprovementPaid":upgrade_cost072,"endingCoins":c.state.coins,"netChange":int(c.state.coins)-int(c.data.START.coins),"wageArrears":c.state.wageArrears,"coinSupply":supply,"totalCoins":c.Money.total(c.state)}
	receipt.endingReserves={"boat":physical_boat(c.find_boat(uid072)).duplicate(true),"cargo":c.state.cargo.duplicate(true),"crewPurse":c.state.crewPurse}
	receipt.wholeLoop=true
	await finish072()

func finish072() -> void:
	if finished072:return
	finished072=true
	if workers.group_id>=0:workers.finish(true)
	if main072!=null:
		main072._retire_battle_driver051();main072.sync_economy()
		main072.queue_free()
		await process_frame
	c=null
	var elapsed: int=Time.get_ticks_msec()-started
	check(elapsed<BODY_LIMIT_MS,"Whole body includes Main setup, both joined worker paths, saves and cleanup under55seconds")
	if receipt.get("wholeLoop",false) and failures==0:receipt.status="COMPLETED";receipt.earnedVoyage=true
	else:
		receipt.earnedVoyage=false
		if receipt.status=="UNFINISHED":receipt.status="FAILED"
	receipt.checks=checks;receipt.failures=failures;receipt.elapsedMs=elapsed
	var directory: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if directory.is_absolute_path():
		var file=FileAccess.open(directory.path_join("complete-voyage072-result.json"),FileAccess.WRITE)
		if file:file.store_string(JSON.stringify(receipt,"\t"));file.close()
	print("COMPLETE072_RESULT ",JSON.stringify(receipt))
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 and receipt.earnedVoyage else 1)
