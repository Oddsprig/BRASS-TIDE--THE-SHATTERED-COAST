extends "res://tests/test_voyage_career070.gd"
## One source-only campaign case, reusing070's courses, finite escrow, payroll,
## worker cleanup and save checks. Root alone runs it. No grants/checkpoints.
## Earn the second boat from START15000 plus actual funded freight/dispatch.
## The later loss/damage opening is DECLARED, never an earned combat outcome.
const BODY083_MS: int=55000
var stores083: int=0
var purchase083: int=0
var repairs083: int=0
var starter083: String=""
var partner083: String=""
var solo_capacity083: float=0.0

func provision083() -> bool:
	var port: Dictionary=c.current_port()
	var coins: int=int(c.state.coins)
	for boat in c.active_fleet():
		if float(boat.fuel)<3.0 or float(boat.supplies)<6.0:
			var stocks: Dictionary=port.stocks.duplicate(true)
			var before: Dictionary=physical_boat(boat).duplicate(true)
			if not check(c.resupply_boat(str(boat.uid),"voyage").get("ok",false),"Pay the existing voyage-load invoice"):return false
			for good in ["fuel","supplies","ammo"]:
				var units: float=50.0 if good=="ammo" else 1.0
				if not check(is_equal_approx(float(stocks[good])-float(port.stocks[good]),(float(boat[good])-float(before[good]))/units),"Working "+good+" leaves finite local stock"):return false
	var need: int=ceili(maxf(0,float(c.data.START.food)-float(c.state.cargo.food)))
	if need>0 and not check(c.trade(str(port.id),"food",need,"buy").get("ok",false),"Replace consumed rations with a real purchase"):return false
	stores083+=coins-int(c.state.coins)
	return check(int(c.state.wageArrears)==0 and c.Money.total(c.state)==supply,"Stores and normal payroll retain the finite world ledger")

func next_boat083() -> Dictionary:
	var port: Dictionary=c.current_port()
	var best: Dictionary={}
	for id in c.Harbor.catalogue(c,port):
		var h: Dictionary=c.hull(str(id))
		if int(port.shipStock.get(id,0))<=0:continue
		var q: Dictionary=c.Harbor.purchase_plan(c,h,port)
		if not q.crewAvailable or not q.stockAvailable or not q.repairQuoteAvailable:continue
		if best.is_empty() or int(q.purchaseCoins)<int(best.plan.purchaseCoins):best={"id":id,"plan":q}
	return best

func funded_leg083(require_support: bool=false) -> bool:
	if not bounded():return false
	var offers: Array=c.VoyageJobs.available(c)
	var chosen: Dictionary={}
	var weight: float=-1.0
	for offer in offers:
		if str(offer.kind)!="freight":continue
		var load: float=float(offer.freight.qty)*float(c.Goods.ITEMS[str(offer.freight.good)].weight)
		if load>weight:chosen=offer;weight=load
	var dispatch: Dictionary={}
	for offer in c.available_contracts():
		if str(offer.kind)=="delivery" and (chosen.is_empty() or str(offer.targetPort)==str(chosen.targetPort)):
			dispatch=offer;break
	if not check(not chosen.is_empty() or not dispatch.is_empty(),"A current funded cargo client exists; no invented offer"):return false
	var target: String=str(chosen.targetPort) if not chosen.is_empty() else str(dispatch.targetPort)
	var accepted: Array=[]
	if not chosen.is_empty():
		if not accept(chosen):return false
		accepted.append(chosen)
		if not compatible_freight070(target,accepted):return false
	# Dispatch is an independent existing contract, only if its eight kit lots
	# still fit beside the already accepted side-job freight.
	if not dispatch.is_empty() and c.cargo_weight()+8.0<=c.capacity():
		var sponsor: Dictionary=c.current_port()
		var purse: int=int(sponsor.cash)
		var coins: int=int(c.state.coins)
		var result: Dictionary=c.accept_contract(str(dispatch.id))
		if not check(result.get("ok",false) and int(c.state.activeContract.escrow)==int(dispatch.reward) and int(sponsor.cash)==purse-int(dispatch.reward) and int(c.state.coins)==coins,"Dispatch fee is held from its real sponsor, without a captain advance"):return false
	else:dispatch={}
	c.Manifest.allocate(c.state)
	if require_support:
		var carried: Dictionary=c.state.cargoManifest.get(partner083,{})
		if not check(c.cargo_weight()>solo_capacity083 and not carried.is_empty(),"Bought support carrier carries actual funded cargo that exceeds the original boat's entire hold"):return false
		receipt.supportCargo={"weight":c.cargo_weight(),"soloCapacity":solo_capacity083,"fleetCapacity":c.capacity(),"partnerManifest":carried.duplicate(true),"jobs":accepted.duplicate(true)}
	if not sail(target):return false
	for job in accepted:
		if not pay(str(job.id)):return false
	if not dispatch.is_empty():
		var held: int=int(c.state.activeContract.escrow)
		var coins: int=int(c.state.coins)
		if not check(c.finish_contract().get("ok",false) and int(c.state.coins)==coins+held,"Arrived dispatch releases its exact held escrow"):return false
		gross_paid+=held
	return provision083()

func buy_partner083(choice: Dictionary) -> bool:
	var p: Dictionary=c.current_port()
	var h: Dictionary=c.hull(str(choice.id))
	var frozen: PackedByteArray=protected_state()
	var q: Dictionary=c.Harbor.purchase_plan(c,h,p)
	if not check(protected_state()==frozen and q.shortfallCoins==0 and q.purchaseCoins==q.hullQuote.readyPrice+q.crewAdvance,"Purchase preview is pure and includes crew, stores and return payroll"):return false
	receipt.purchaseQuote=q
	var coins: int=int(c.state.coins);var crew_purse: int=int(c.state.crewPurse)
	var stock: int=int(p.shipStock[h.id]);var workforce: int=int(p.workforce)
	var old_ids: Array=c.state.fleet.map(func(b):return str(b.uid))
	if not check(c.buy_boat(str(h.id)).get("ok",false),"Actual earned-purse purchase of the quoted ready hull"):return false
	var boat: Dictionary=c.state.fleet.back();partner083=str(boat.uid)
	if not check(not partner083 in old_ids and boat.get("moduleCondition") is Dictionary and int(c.state.coins)==coins-int(q.purchaseCoins) and int(c.state.crewPurse)==crew_purse+int(q.crewAdvance) and int(p.shipStock[h.id])==stock-1 and int(p.workforce)==workforce-int(h.crewMin) and int(boat.crew)==int(h.crewMin),"Actual hull, crew/workforce and sailor advance match the invoice; no free stores or replacement UID"):return false
	if not check(boat.fuel==0 and boat.ammo==0 and boat.supplies==0 and c.FleetSupport.reserve(c,partner083).get("ok",false),"Purchased hull starts empty; its explicit support role grants no stores"):return false
	purchase083=int(q.purchaseCoins)
	if not provision083():return false
	var actual: Dictionary=c.expedition_report()
	var split: Dictionary=c.Deployment.split(c.active_fleet())
	return check(actual.usableCapacity==q.after.usableCapacity and actual.dailyWages==q.after.dailyWages and c.active_fleet().any(func(b):return str(b.uid)==partner083) and split.reserve.any(func(b):return str(b.uid)==partner083) and split.points<=300,"Carrier adds the quoted hold and actual wages while traveling outside300DP combat deployment")

func declared_loss083() -> bool:
	phase("DECLARED_one_hull_loss_and_survivor_damage_not_earned_combat")
	var lost: Dictionary=c.find_boat(starter083)
	var survivor: Dictionary=c.find_boat(partner083)
	var original: Dictionary=physical_boat(lost).duplicate(true)
	var purses: int=int(c.state.coins)
	c.Manifest.allocate(c.state)
	lost.team="player";lost.sunk=true;lost.hp=0.0
	survivor.hp=maxf(1.0,float(survivor.maxHp)-4.0)
	var battle: Dictionary={"ships":[lost],"result":"retreated","world064":c.world_location064().world064,"engagementSource060":"fixture083-declared-loss"}
	var report: Dictionary=c.battle_settled("retreated",[],{"kind":"fixture083","objectiveOnly":true},battle)
	if not check(bool(report.get("ok",true)) and c.find_boat(starter083).is_empty() and c.state.fleet.size()==1 and int(c.state.coins)==purses and report.get("wrecks",[]).size()==1,"Declared hull loss publishes one physical wreck, keeps the real survivor and grants no victory/loot coins"):return false
	var wreck: Dictionary=c.Salvage.find_wreck(c.state,str(report.wrecks[0].id))
	if not check(str(wreck.uid)==starter083 and wreck.get("sourceModuleCondition") is Dictionary and str(lost.get("equipmentRetiredTo",""))==str(wreck.id),"Original hull and physical equipment retain exactly one wreck custodian"):return false
	var quote: Dictionary=c.service_quote(survivor,c.current_port())
	var coins: int=int(c.state.coins);var kits: float=float(survivor.supplies)
	var result: Dictionary=c.repair_boat(partner083)
	if not check(quote.get("ok",false) and int(quote.cost)>0 and result.get("ok",false) and int(c.state.coins)==coins-int(quote.cost) and survivor.hp==survivor.maxHp and float(survivor.supplies)<kits,"Pay the actual surviving hull's repair bill with earned/retained capital and finite kits"):return false
	repairs083=int(quote.cost)
	if not check(c.FleetSupport.reserve(c,partner083).get("ok",false) and not survivor.supportOnly,"Real surviving carrier can rejoin combat deployment after the declared loss"):return false
	receipt.controlledLoss={"declared":true,"earnedCombat":false,"lostBoatBefore":original,"wreck":wreck.duplicate(true),"survivorUid":partner083,"paidRepair":quote}
	var reserve: Dictionary=c.expedition_report()
	if not check(int(c.state.coins)>=int(reserve.returnWages) and c.Money.total(c.state)==supply,"Recovery remains affordable with real two-day payroll and no rescue grant/loan"):return false
	return funded_leg083()

func _run() -> void:
	receipt.fixture="fleet_growth083";receipt.earnedGrowth=false
	receipt.erase("earnedVoyage")
	receipt.bodyLimitMs=BODY083_MS;receipt.workStopMs=BODY083_MS-1500
	if not check(OS.get_environment("GAME_TEST_ARTIFACTS").is_absolute_path(),"Root supplies a private artifact/profile directory"):finish083();return
	var world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c=Campaign.new(world)
	if not check(c.new_game(69069).get("ok",false) and int(c.state.coins)==15000 and c.state.fleet.size()==1,"Ordinary START15000 career, no staged capital or second hull"):finish083();return
	supply=int(c.state.coinSupply);starter083=str(c.state.fleet[0].uid);solo_capacity083=c.capacity()
	receipt.start={"coins":c.state.coins,"boat":physical_boat(c.state.fleet[0]).duplicate(true),"cargo":c.state.cargo.duplicate(true)}
	var choice: Dictionary={}
	for leg in range(24):
		phase("ordinary_funded_leg_"+str(leg+1))
		if not funded_leg083():finish083();return
		choice=next_boat083()
		if not choice.is_empty() and int(choice.plan.shortfallCoins)==0:break
	if not check(not choice.is_empty() and int(choice.plan.shortfallCoins)==0 and int(c.state.coins)>15000 and gross_paid>0 and payroll>0,"Bounded actual work leaves a surplus after all charged wages/replacement stores and funds a useful second hull plus reserves"):finish083();return
	if not buy_partner083(choice) or not funded_leg083(true) or not declared_loss083():finish083();return
	var saved: Dictionary=parsed_save("growth083-completed")
	if saved.is_empty() or not restore_exact(saved,"growth083-completed"):finish083();return
	var expected: int=15000+gross_paid-payroll-stores083-purchase083-repairs083
	if not check(int(c.state.coins)==expected and int(c.state.wageArrears)==0 and int(c.state.debt)==0 and c.Money.total(c.state)==supply,"All ordinary income, actual wages, purchased stores, hull/crew advance and recovery reconcile exactly"):finish083();return
	receipt.accounting={"start":15000,"fundedEscrowPaid":gross_paid,"actualWages":payroll,"storesBought":stores083,"hullAndCrewAdvance":purchase083,"survivorRepair":repairs083,"endingCoins":c.state.coins,"worldTotal":c.Money.total(c.state),"coinSupply":supply}
	receipt.earnedGrowth=true;receipt.status="COMPLETED"
	finish083()

func finish083() -> void:
	if workers.group_id>=0:workers.finish(true)
	c=null
	receipt.elapsedMs=Time.get_ticks_msec()-started
	check(int(receipt.elapsedMs)<BODY083_MS,"Whole083 case includes setup, saves and joined worker cleanup below55seconds")
	if (failures>0 or not receipt.earnedGrowth) and receipt.status in ["UNFINISHED","COMPLETED"]:receipt.status="FAILED"
	receipt.checks=checks;receipt.failures=failures
	var directory: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if directory.is_absolute_path():
		var file=FileAccess.open(directory.path_join("fleet-growth083-result.json"),FileAccess.WRITE)
		if file:file.store_string(JSON.stringify(receipt,"\t"));file.close()
	print("FLEET083_RESULT ",JSON.stringify(receipt))
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 and receipt.earnedGrowth else 1)
