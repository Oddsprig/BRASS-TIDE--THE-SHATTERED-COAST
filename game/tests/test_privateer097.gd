extends SceneTree
## UNPLAYED staged witness for one lawful commission and a hostile shipment.
## No arguments: no battle, clock, coins, stock, or live owner cargo is written.
## The timber manifest uses a discarded copy of a seeded raider.
## Optional --earned-save=ABS --earned-sha256=SHA restores that exact file and
## continues with public commands. A missing observed cargo-bearing raider is a
## GAP (exit 2), never a manufactured pass. That mode is an automated public-API
## continuation, not a human fun proof. The earned mode does not edit production.
## A nonempty escort mission is retained against a commissioned cargo-bearing copy.
## A real NPC settlement can make captured food or fuel a prize past the raider's own reserve.
## A settled prize debit retires that proven quantity before an immediate save.
const Campaign=preload("res://scripts/campaign.gd")
const NavalCombat=preload("res://scripts/naval_combat.gd")
const Goods=preload("res://scripts/goods.gd")
const Money=preload("res://scripts/money.gd")
const BODY097_MS: int=45000
const SEEK097_SECONDS: float=90.0
var checks: int=0
var failures: int=0
var earned_save: String=""
var earned_bound: String=""
var main097
var workers097
var c097
var started097: int=0
var seeking097: bool=false
var owner097: String=""
var uid097: String=""
var supply097: int=0
var payroll097: int=0
var repair097: int=0
var stores097: int=0
var finished097: bool=false
var receipt097: Dictionary={}

func check(ok: bool,message: String) -> bool:
	checks+=1
	if not ok:failures+=1;print("FAIL privateer097: ",message)
	return ok

func _initialize() -> void:
	var earned_path: String=""
	var earned_hash: String=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--earned-save="):earned_path=argument.trim_prefix("--earned-save=")
		elif argument.begins_with("--earned-sha256="):earned_hash=argument.trim_prefix("--earned-sha256=")
	if earned_path.is_empty() and earned_hash.is_empty():
		_staged()
		return
	if earned_path.is_empty() or earned_hash.is_empty():
		print("FAIL privateer097: earned continuation needs both --earned-save=ABS and --earned-sha256=SHA")
		quit(1)
		return
	earned_save=earned_path.replace("\\","/").simplify_path()
	earned_bound=earned_hash.strip_edges().to_lower()
	_earned.call_deferred()

func _staged() -> void:
	var c=Campaign.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json")))
	check(c.new_game(121).ok and int(c.state.coins)==15000 and float(c.state.fleet[0].crew)==5.0,"Default new game keeps 15000 coins and 5 crew")
	var supply: int=Money.total(c.state)
	var raider: Dictionary={}
	var trader: Dictionary={}
	for owner in c.state.fleetOwners:
		if raider.is_empty() and str(owner.get("kind",""))=="raider" and str(owner.get("id","")).begins_with("patrol-"):raider=owner
		if trader.is_empty() and str(owner.get("kind",""))=="trader":trader=owner
	check(not raider.is_empty() and not trader.is_empty(),"Seeded world has one patrol raider and one trader")
	check(not c.Politics.commission_enemy(c,raider).lawful,"Neutral standing has no lawful privateer target")
	check(not c.Factions.accept_commission(c.state,"compact").ok and int(c.state.coins)==15000,"A commission is refused before friendly standing and mints nothing")
	c.Factions.adjust(c.state,"compact",20,"Fixture fulfilled contracts")
	var signed: Dictionary=c.Factions.accept_commission(c.state,"compact")
	check(signed.ok and signed.committed and int(signed.contract.stipend)==0 and int(signed.contract.reward)==0 and Money.total(c.state)==supply,"Explicit letters name enemies and mint no coins")
	check(signed.contract.enemies.has("raiders"),"Compact letters name the existing raider faction")
	var lawful: Dictionary=c.Politics.commission_enemy(c,raider)
	var peaceful: Dictionary=c.Politics.commission_enemy(c,trader)
	check(lawful.lawful and str(lawful.patronId)=="compact" and not peaceful.lawful,"Only the already hostile named fleet is a lawful target")
	var before: String=JSON.stringify(c.state)
	var live: Dictionary=c.prize_shipment(raider)
	var opened: Dictionary=c.intercept_shipment({"kind":"patrol","ownerId":str(raider.id)})
	check(not live.ok and not opened.handled and JSON.stringify(c.state)==before,"A raider with no captured cargo does not gain a shipment or change state")
	var copy: Dictionary=raider.duplicate(true)
	# Discarded copy only: one carrier must count as crewed so the hold math can be checked.
	for boat in copy.boats:
		if boat is Dictionary and not boat.get("sunk",false):boat.crew=maxf(float(boat.get("crew",0)),float(boat.get("crewMin",1)));break
	copy.cargo={"timber":1.0,"food":1.0}
	var planned: Dictionary=c.prize_shipment(copy)
	var aboard: float=0.0
	var stores: bool=false
	for uid in planned.carrierCargo:
		aboard+=float(planned.carrierCargo[uid].get("timber",0))
		stores=stores or planned.carrierCargo[uid].has("food") or planned.carrierCargo[uid].has("fuel")
	check(planned.ok and not stores and is_equal_approx(aboard,1.0) and float(raider.cargo.get("timber",0))==0.0,"Discarded copy assigns its timber only; the live owner gains none")
	check(not c.intercept_shipment({"kind":"patrol","ownerId":str(trader.id)}).handled,"A peaceful trader is not opened as a commissioned intercept")
	var escort_mission: Dictionary={"kind":"escort","carrierTeam":"player","carrierOwnerId":str(trader.id),"carrierUids":["staged-escort-carrier"],"allyUids":["staged-escort-carrier"],"carrierCargo":{"staged-escort-carrier":{"timber":1.0}},"exit":{"x":2180.0,"y":850.0,"radius":70.0,"portId":"","portName":""}}
	var mission_bytes: String=JSON.stringify(escort_mission)
	var escort_context: Dictionary={"kind":"escort","ownerId":str(copy.id),"allyOwnerId":str(trader.id),"escortEvent":"escort:%s:0"%str(trader.id),"name":"Escort through the interception","mission":escort_mission}
	var slot: int=-1
	for index in range(c.state.fleetOwners.size()):
		if is_same(c.state.fleetOwners[index],raider):slot=index;break
	var frozen: String=JSON.stringify(c.state)
	var converted: Dictionary={}
	var kept: Dictionary={}
	var direct: Dictionary={}
	check(slot>=0,"The seeded raider remains the live owner")
	if slot>=0:
		c.state.fleetOwners[slot]=copy
		converted=c.EscortOps.prepare_intercept(c,{"kind":"patrol","id":str(copy.id),"ownerId":str(copy.id)})
		kept=c.EscortOps.prepare_intercept(c,escort_context)
		direct=c.intercept_shipment(escort_context)
		c.state.fleetOwners[slot]=raider
	check(str(converted.get("mission",{}).get("kind",""))=="intercept","The commissioned cargo-bearing copy still opens an intercept when no mission is assigned")
	check(str(kept.get("kind",""))=="escort" and str(kept.get("escortEvent",""))==str(escort_context.escortEvent) and JSON.stringify(kept.get("mission",{}))==mission_bytes,"prepare_intercept retains the escort mission bytes and escort credit")
	check(not direct.get("handled",false) and JSON.stringify(escort_context.get("mission",{}))==mission_bytes,"intercept_shipment does not convert an existing escort mission")
	check(JSON.stringify(c.state)==frozen and float(raider.get("cargo",{}).get("timber",0))==0.0 and not c.state.fleetOwners.any(func(owner):return is_same(owner,copy)),"The copied raider is removed and the live owner stays empty")
	_operating_prize097(c)
	_settle_marker097(c)
	var scores: Dictionary={}
	for faction in ["compact","forge","reed"]:scores[faction]=int(c.Factions.standing(c.state,faction).score)
	c.Politics.settled(c,raider,"won",{})
	c.Politics.settled(c,raider,"won",{})
	check(int(c.Factions.standing(c.state,"compact").score)==int(scores.compact)+2,"The patron gains the existing two-point defense credit once")
	check(int(c.Factions.standing(c.state,"forge").score)==int(scores.forge)+2 and int(c.Factions.standing(c.state,"reed").score)==int(scores.reed)+2,"The other coastal factions keep the same two-point credit")
	var explained: bool=false
	var plain: int=0
	for entry in c.state.relationships.log:
		var reason: String=str(entry.get("reason",""))
		if reason.begins_with("Letters of marque for ") and reason.contains(str(raider.name)):explained=true
		if reason=="Defended coastal shipping":plain+=1
	check(explained and plain==2 and Money.total(c.state)==supply,"Patron credit names the letters; no coins move")
	print("privateer097: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func _arm097(owner: Dictionary,rounds: float) -> void:
	if owner.get("cargo") is Dictionary:owner.cargo["ammo"]=0.0
	var armed: bool=false
	for boat in owner.get("boats",[]):
		if not boat is Dictionary or boat.get("sunk",false):continue
		boat["ammo"]=rounds if not armed else 0.0
		armed=true

func _crew097(owner: Dictionary) -> void:
	for boat in owner.get("boats",[]):
		if boat is Dictionary and not boat.get("sunk",false):boat["crew"]=maxf(float(boat.get("crew",0)),float(boat.get("crewMin",1)))

func _fight097(book: Dictionary,pirate: Dictionary,merchant: Dictionary) -> Dictionary:
	_arm097(pirate,1.0)
	_arm097(merchant,0.0)
	return NavalCombat._resolve_physical068(book,pirate,merchant,{},{},97097)

func _shipped097(plan: Dictionary,good: String) -> float:
	var total: float=0.0
	var manifest: Dictionary=plan.get("carrierCargo",{}) if plan.get("carrierCargo") is Dictionary else {}
	for uid in manifest:
		if manifest[uid] is Dictionary:total+=float(manifest[uid].get(good,0))
	return total

func _room097(owner: Dictionary) -> float:
	var cap: float=0.0
	var used: float=0.0
	for boat in owner.get("boats",[]):
		if boat is Dictionary and not boat.get("sunk",false):cap+=float(boat.get("spec",{}).get("cargo",0))
	for key in owner.get("cargo",{}):
		if Goods.ITEMS.has(str(key)):used+=float(owner.cargo[key])*float(Goods.ITEMS[str(key)].weight)
	return cap-used

func _owner097(rows: Array,id: String) -> Dictionary:
	for owner in rows:
		if owner is Dictionary and str(owner.get("id",""))==id:return owner
	return {}

func _operating_prize097(c) -> void:
	var live: String=JSON.stringify(c.state)
	var book: Dictionary=c.state.duplicate(true)
	var pirate: Dictionary={}
	var food_trader: Dictionary={}
	var other_trader: Dictionary={}
	for owner in book.fleetOwners:
		if pirate.is_empty() and str(owner.get("kind",""))=="raider" and str(owner.get("id","")).begins_with("patrol-"):pirate=owner
		if str(owner.get("kind",""))!="trader":continue
		var manifest: String=str(owner.get("tradeGood",""))
		if not manifest in ["food","fuel","supplies","ammo"]:continue
		if float(owner.get("tradeCargo",0))<=0.0 or float(owner.get("cargo",{}).get(manifest,0))<=0.0:continue
		if manifest=="food":
			if food_trader.is_empty() or float(owner.tradeCargo)>float(food_trader.tradeCargo):food_trader=owner
		elif other_trader.is_empty() or float(owner.tradeCargo)>float(other_trader.tradeCargo):other_trader=owner
	var merchant: Dictionary=food_trader if not food_trader.is_empty() else other_trader
	check(not pirate.is_empty() and not merchant.is_empty(),"Seeded world has a patrol raider and a trader with finite operating cargo")
	if pirate.is_empty() or merchant.is_empty():
		check(JSON.stringify(c.state)==live,"Operating prize cases leave the live campaign unchanged")
		return
	var good: String=str(merchant.tradeGood)
	_crew097(pirate)
	var cargo_start: float=float(merchant.cargo.get(good,0.0))
	var trade_start: float=float(merchant.tradeCargo)
	var pirate_start: float=float(pirate.cargo.get(good,0.0))
	var finite: float=minf(cargo_start,trade_start)
	var aside: float=float(maxi(0,int(floor(finite))-1))
	if aside>=1.0:
		merchant.cargo[good]=cargo_start-aside
		merchant.tradeCargo=trade_start-aside
	var fight: Dictionary=_fight097(book,pirate,merchant)
	var event: Dictionary=fight.get("event",{}) if fight.get("event") is Dictionary else {}
	var took: int=int(event.get("capturedQty",0))
	check(fight.get("ok",false) and str(event.get("capturedGood",""))==good and took>0,"Actual settlement debits the trader and credits the raider: "+str(event.get("summary",fight.get("reason",""))))
	if not fight.get("ok",false) or took<=0:
		check(JSON.stringify(c.state)==live,"Operating prize cases leave the live campaign unchanged")
		return
	check(is_equal_approx(float(merchant.cargo.get(good,0.0)),cargo_start-aside-float(took)) and is_equal_approx(float(merchant.tradeCargo),trade_start-aside-float(took)),"The trader loses only the taken lot")
	check(is_equal_approx(float(pirate.cargo.get(good,0.0)),pirate_start+float(took)),"The raider gains only the taken lot")
	check(is_equal_approx(float(pirate.get("capturedOperating",{}).get(good,-1)),float(took)) and float(pirate.capturedOperating[good])<=float(pirate.cargo[good])+0.001,"Proven captured remainder matches the take and does not exceed cargo")
	var plan: Dictionary=c.prize_shipment(pirate)
	check(plan.ok and is_equal_approx(_shipped097(plan,good),float(took)),"Prize plan ships the captured remainder and not the raider's own reserve: "+str(plan.get("message","")))
	var other_operating: bool=false
	for uid in plan.get("carrierCargo",{}):
		if not plan.carrierCargo[uid] is Dictionary:continue
		for key in plan.carrierCargo[uid]:
			if str(key)!=good and str(key) in ["food","fuel","supplies","ammo"]:other_operating=true
	check(not other_operating,"Unproven operating goods stay out of the prize plan")
	var saved: Dictionary=c.state.duplicate(true)
	var saved_pirate: Dictionary=_owner097(saved.fleetOwners,str(pirate.id))
	saved_pirate.cargo=pirate.cargo.duplicate(true)
	saved_pirate.capturedOperating=pirate.capturedOperating.duplicate(true)
	var admitted: Dictionary=c.SaveValidation.validate(JSON.parse_string(JSON.stringify(saved)),c.data)
	var admitted_pirate: Dictionary=_owner097(admitted.get("state",{}).get("fleetOwners",[]),str(pirate.id))
	check(admitted.get("ok",false) and is_equal_approx(float(admitted_pirate.get("capturedOperating",{}).get(good,-1)),float(took)),"Save admission keeps the proven lot: "+str(admitted.get("message","")))
	var inflated: Dictionary=saved.duplicate(true)
	var inflated_pirate: Dictionary=_owner097(inflated.fleetOwners,str(pirate.id))
	inflated_pirate.capturedOperating[good]=float(inflated_pirate.cargo.get(good,0.0))+5.0
	var refused: Dictionary=c.SaveValidation.validate(inflated,c.data)
	check(not refused.get("ok",false) and str(refused.get("message","")).contains("exceeds"),"Save admission refuses a captured lot larger than the cargo aboard")
	var eater: Dictionary=pirate.duplicate(true)
	eater["atPort"]=""
	var lot0: float=float(eater.capturedOperating.get(good,0.0))
	var aboard0: float=float(eater.cargo.get(good,0.0))
	var reserve0: float=maxf(0.0,aboard0-lot0)
	if good=="food":
		var daily: float=float(c.Fleets.upkeep(eater).food)
		var portion: float=minf(lot0,1.0)
		var days: float=(reserve0+portion)/daily if daily>0.0 else 0.0
		c.Fleets.tick([eater],[],days,null)
		var eaten: float=aboard0-float(eater.cargo.get("food",0.0))
		var expected: float=maxf(0.0,lot0-maxf(0.0,eaten-reserve0))
		var left: Dictionary=eater.get("capturedOperating",{}) if eater.get("capturedOperating") is Dictionary else {}
		var remain: float=float(left.get(good,0.0))
		check(eaten+0.001>=reserve0 and is_equal_approx(remain,expected) and remain<=float(eater.cargo.get(good,0.0))+0.001,"Food consumption eats the operating reserve before the captured remainder")
	else:
		for boat in eater.get("boats",[]):
			if boat is Dictionary and not boat.get("sunk",false):boat[good]=0.0
		var home: Dictionary={}
		for port in book.ports:
			if str(port.get("id",""))==str(eater.get("homePort","")):home=port.duplicate(true);break
		if home.is_empty():
			check(false,"The raider home port was not on the detached chart")
		else:
			c.Fleets.dock(eater,home,null)
			var drop: float=aboard0-float(eater.cargo.get(good,0.0))
			var expected_lot: float=maxf(0.0,lot0-maxf(0.0,drop-reserve0))
			var left_lot: Dictionary=eater.get("capturedOperating",{}) if eater.get("capturedOperating") is Dictionary else {}
			check(drop>=0.0 and is_equal_approx(float(left_lot.get(good,0.0)),expected_lot) and float(left_lot.get(good,0.0))<=float(eater.cargo.get(good,0.0))+0.001,"Dock consumption keeps the captured remainder inside the cargo still aboard")
	if aside>=1.0:
		merchant.cargo[good]=float(merchant.cargo.get(good,0.0))+aside
		merchant.tradeCargo=float(merchant.tradeCargo)+aside
	var before_lot: float=float(pirate.capturedOperating.get(good,0.0))
	var before_pirate: float=float(pirate.cargo.get(good,0.0))
	var before_merchant: float=float(merchant.cargo.get(good,0.0))
	var room: float=_room097(pirate)
	var again: Dictionary=_fight097(book,pirate,merchant)
	var again_event: Dictionary=again.get("event",{}) if again.get("event") is Dictionary else {}
	var took2: int=int(again_event.get("capturedQty",-1)) if again.get("ok",false) else -1
	check(again.get("ok",false) and took2>=0 and is_equal_approx(float(pirate.capturedOperating.get(good,-1)),before_lot+float(took2)),"A second settlement adds only the new take")
	check(is_equal_approx(float(pirate.cargo.get(good,0.0)),before_pirate+float(max(took2,0))) and is_equal_approx(float(merchant.cargo.get(good,0.0)),before_merchant-float(max(took2,0))),"The second transfer does not duplicate cargo")
	check(float(pirate.capturedOperating.get(good,0.0))<=float(pirate.cargo.get(good,0.0))+0.001,"The captured remainder still does not exceed the cargo aboard")
	if aside>=1.0:check(took2>0 or room<1.0,"A second finite lot is taken when the crewed hold still has room")
	check(JSON.stringify(c.state)==live,"Operating prize cases leave the live campaign unchanged")

func _marked097(owner: Dictionary,good: String) -> float:
	var book=owner.get("capturedOperating",{})
	if not book is Dictionary or not book.has(good):return 0.0
	var raw=book[good]
	if not (raw is int or raw is float) or not is_finite(float(raw)):return 0.0
	return float(raw)

func _convoy_debit097(probe,owner: Dictionary,good: String,qty: float) -> Dictionary:
	var prize: Dictionary=probe.state.fleet[0]
	prize["captureSecured"]=true
	var uid: String=str(prize.get("uid",""))
	var battle: Dictionary={"result":"won","mission":{"kind":"intercept","carrierTeam":"enemy","carrierOwnerId":str(owner.get("id","")),"carrierUids":[uid]},"convoy":{"kind":"intercept","carrierTeam":"enemy","uids":[uid],"actors":{uid:prize},"cargo":{uid:{good:qty}},"exit":{"x":120.0,"y":850.0,"radius":70.0,"portId":"","portName":""}}}
	return probe.EscortOps.settle_cargo(probe,battle,[])

func _settle_marker097(c) -> void:
	var live: String=JSON.stringify(c.state)
	var probe=Campaign.new(c.data,c.nav)
	probe.state=c.state.duplicate(true)
	var pirate: Dictionary={}
	var trader: Dictionary={}
	for owner in probe.state.fleetOwners:
		if pirate.is_empty() and str(owner.get("kind",""))=="raider" and str(owner.get("id","")).begins_with("patrol-"):pirate=owner
		if trader.is_empty() and str(owner.get("kind",""))=="trader":trader=owner
	check(not pirate.is_empty() and not trader.is_empty() and not trader.has("capturedOperating"),"The detached book has a patrol raider and an unmarked trader")
	if pirate.is_empty() or trader.is_empty():
		check(JSON.stringify(c.state)==live,"Prize-marker settlement leaves the live campaign unchanged")
		return
	var reserve: float=5.0
	var proven: float=20.0
	var other_cargo: Dictionary=pirate.cargo.duplicate(true)
	pirate.cargo["food"]=reserve+proven
	pirate["capturedOperating"]={"food":proven}
	var pirate_coins: int=int(pirate.coins)
	var pirate_purse: int=int(pirate.get("crewPurse",0))
	var trade_before: float=float(pirate.get("tradeCargo",0.0))
	var supply: int=Money.total(probe.state)
	var settled: Dictionary=_convoy_debit097(probe,pirate,"food",proven)
	var trade_expected: float=maxf(0.0,trade_before-proven) if str(pirate.get("tradeGood",""))=="food" else trade_before
	check(settled.get("ok",true)!=false and int(settled.get("captured",0))==1,"Actual settlement debits the proven prize from the raider")
	check(is_equal_approx(float(pirate.cargo.get("food",-1.0)),reserve) and _marked097(pirate,"food")<=0.000001,"The five-unit reserve remains and is not marked as prize")
	var other_same: bool=true
	for key in other_cargo:
		if str(key)=="food":continue
		if not is_equal_approx(float(pirate.cargo.get(key,0.0)),float(other_cargo[key])):other_same=false
	check(other_same and is_equal_approx(float(pirate.get("tradeCargo",0.0)),trade_expected) and int(pirate.coins)==pirate_coins and int(pirate.get("crewPurse",0))==pirate_purse and Money.total(probe.state)==supply,"The prize debit changes no other goods or coins")
	var immediate: String=JSON.stringify(probe.state)
	var parsed=JSON.parse_string(immediate)
	var saved: Dictionary=_owner097(parsed.get("fleetOwners",[]) if parsed is Dictionary else [],str(pirate.id))
	check(parsed is Dictionary and is_equal_approx(float(saved.get("cargo",{}).get("food",-1.0)),reserve) and _marked097(saved,"food")<=0.000001,"Immediate JSON keeps the reserve unmarked")
	var reader=Campaign.new(c.data,c.nav)
	var restored: Dictionary=reader.restore(parsed)
	var back: Dictionary=_owner097(reader.state.get("fleetOwners",[]),str(pirate.id))
	check(restored.get("ok",false) and is_equal_approx(float(back.get("cargo",{}).get("food",-1.0)),reserve) and _marked097(back,"food")<=0.000001,"Public restore accepts the immediate post-prize save: "+str(restored.get("message","")))
	var food_before: float=float(trader.cargo.get("food",0.0))
	if food_before<4.0:
		trader.cargo["food"]=4.0
		food_before=4.0
	var trader_coins: int=int(trader.coins)
	var trader_trade: float=float(trader.get("tradeCargo",0.0))
	var trader_supply: int=Money.total(probe.state)
	var ordinary: Dictionary=_convoy_debit097(probe,trader,"food",4.0)
	var trader_trade_expected: float=maxf(0.0,trader_trade-4.0) if str(trader.get("tradeGood",""))=="food" else trader_trade
	check(ordinary.get("ok",true)!=false and int(ordinary.get("captured",0))==1 and not trader.has("capturedOperating"),"An ordinary trader debit does not create a captured marker")
	check(is_equal_approx(float(trader.cargo.get("food",-1.0)),food_before-4.0) and is_equal_approx(float(trader.get("tradeCargo",0.0)),trader_trade_expected) and int(trader.coins)==trader_coins and Money.total(probe.state)==trader_supply,"The trader debit removes only the settled food and no coins")
	check(JSON.stringify(c.state)==live,"Prize-marker settlement leaves the live campaign unchanged")

func _earned() -> void:
	started097=Time.get_ticks_msec()
	receipt097={"status":"UNFINISHED","earnedContinuation":false,"humanFunProof":false,"proof":"automated public-API continuation, not a human fun proof","sourcePrep":"UNPLAYED until this witness is run","bodyLimitMs":BODY097_MS,"phases":[],"commands":[],"avoided":[],"standing":[],"raiders":[]}
	receipt097.entry="Pass both user arguments after --. GAME_TEST_ARTIFACTS must be an absolute test profile. Do not pass --qa-campaign. No arguments keeps the staged unit. This witness does not replay test_voyage_career070."
	receipt097.expectsSave="Hash-bound career070-completed.json from unchanged test_voyage_career070, ordinary new_game 69069. Root binds file, hash, source and provenance after 095 is accepted."
	receipt097.gapExit=2
	receipt097.passExit=0
	receipt097.failExit=1
	await _continue097()
	await _finish097()

func _continue097() -> void:
	var artifacts: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if not check(artifacts.is_absolute_path(),"Earned continuation needs an absolute GAME_TEST_ARTIFACTS profile so saves stay out of the editor folder"):return
	if not check(earned_save.is_absolute_path(),"--earned-save must be an absolute path"):return
	var actual_hash: String=FileAccess.get_sha256(earned_save).to_lower()
	receipt097.earnedSave=earned_save
	receipt097.earnedSha256=actual_hash
	if not check(not actual_hash.is_empty() and actual_hash==earned_bound,"Earned save bytes do not match --earned-sha256"):return
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(earned_save))
	if not check(parsed is Dictionary,"Earned save does not decode to one campaign object"):return
	var main_script=load("res://scripts/main.gd")
	var worker_script=load("res://scripts/economy_workers.gd")
	if not check(main_script!=null and worker_script!=null,"Existing Main and economy worker scripts load"):return
	workers097=worker_script.new()
	main097=main_script.new()
	main097.qa_ocean066=true
	root.add_child.call_deferred(main097)
	await main097.ready
	main097.set_process(false)
	main097.set_physics_process(false)
	main097.paused=true
	c097=main097.core
	_did("Campaign.restore")
	var restored: Dictionary=c097.restore(parsed)
	if not check(restored.get("ok",false),"Public restore refused the hash-bound save: "+str(restored.get("message",""))):return
	main097.mode="campaign"
	main097.quick_mode=false
	main097.paused=true
	main097.ui.close_modal()
	supply097=int(c097.state.get("coinSupply",-1))
	receipt097.opened={"seed":int(c097.state.get("seed",-1)),"day":float(c097.state.day),"coins":int(c097.state.coins),"port":str(c097.current_port().get("id","")),"position":c097.state.position.duplicate(true),"fleet":c097.state.fleet.size()}
	if int(c097.state.get("seed",-1))!=69069:
		gap097("UNEXPECTED_SEED","Restored career seed is not the ordinary new_game 69069 career")
		return
	if not c097.home_local064():
		gap097("NOT_ON_HOME_CHART","Restored career is not on the home chart. This continuation does not open an offshore voyage.")
		return
	if c097.state.fleet.is_empty():
		gap097("NO_FLEET","Restored career has no boat")
		return
	if c097.Money.total(c097.state)!=supply097:
		gap097("LEDGER","Restored coin ledger does not match its coin supply")
		return
	uid097=str(c097.state.get("flagship",""))
	if c097.find_boat(uid097).is_empty():uid097=str(c097.state.fleet[0].uid)
	_phase("restored_earned_career")
	if not _commission097():return
	if not _seek097():return
	if not await _battle097():return
	if not _choice097():return
	if not _return097():return
	if payroll097+repair097+stores097<=0:
		gap097("NO_PAID_COSTS","Return, repair and stores moved no coins. No cost was invented.")
		return
	_did("Main.save_game")
	main097.save_game(false)
	var profile: String=main097.save_directory.path_join("voyage.json")
	if not FileAccess.file_exists(profile):
		gap097("SAVE_FAILED","Public save did not write the test-profile voyage")
		return
	var artifact: String=artifacts.path_join("privateer097-continuation.json")
	var text: String=FileAccess.get_file_as_string(profile)
	var copy=FileAccess.open(artifact,FileAccess.WRITE)
	if copy==null:
		gap097("SAVE_FAILED","Continuation artifact could not be written")
		return
	copy.store_string(text)
	copy.close()
	receipt097.profileSave=profile
	receipt097.profileSha256=FileAccess.get_sha256(profile).to_lower()
	receipt097.continuationPath=artifact
	receipt097.continuationSha256=FileAccess.get_sha256(artifact).to_lower()
	if receipt097.profileSha256!=receipt097.continuationSha256:
		gap097("SAVE_COPY","Profile save and continuation artifact differ")
		return
	receipt097.paid={"payroll":payroll097,"repair":repair097,"stores":stores097,"endingCoins":int(c097.state.coins)}
	receipt097.status="COMPLETED"
	receipt097.earnedContinuation=true
	receipt097.humanFunProof=false
	_phase("saved_paid_continuation")

func _commission097() -> bool:
	_phase("earned_standing_and_public_commission")
	var deal: Dictionary=c097.state.get("relationships",{}).get("commission",{}) if c097.state.get("relationships") is Dictionary else {}
	var patron: String=""
	if deal.get("committed",false):
		var contract: Dictionary=deal.get("contract",{}) if deal.get("contract") is Dictionary else {}
		var named: Array=contract.get("enemies",[]) if contract.get("enemies") is Array else []
		if not named.has("raiders"):
			return gap097("COMMISSION_OTHER","The save already has letters, and they do not name raiders. No second commission was signed.")
		patron=str(deal.get("factionId",""))
	else:
		var best: int=-999999
		for faction_id in ["compact","forge","reed"]:
			var terms: Dictionary=c097.Factions.commission_terms(c097.state,faction_id)
			var view: Dictionary=c097.Factions.standing(c097.state,faction_id)
			receipt097.standing.append({"factionId":faction_id,"score":int(view.get("score",0)),"band":str(view.get("band","")),"eligible":bool(terms.get("eligible",false)),"enemies":terms.get("enemies",[])})
			if bool(terms.get("eligible",false)) and terms.get("enemies",[]).has("raiders") and int(view.get("score",0))>best:
				best=int(view.score)
				patron=faction_id
		if patron.is_empty():
			return gap097("STANDING_NOT_ELIGIBLE","No coastal patron already offers friendly or trusted letters against raiders. Standing was not adjusted.")
	var coins: int=int(c097.state.coins)
	_did("Factions.accept_commission")
	var signed: Dictionary=c097.Factions.accept_commission(c097.state,patron)
	receipt097.commission={"patron":patron,"ok":bool(signed.get("ok",false)),"committed":bool(signed.get("committed",false)),"repeated":bool(signed.get("repeated",false)),"message":str(signed.get("message",""))}
	if not signed.get("ok",false) or not signed.get("committed",false):
		return gap097("COMMISSION_REFUSED",str(signed.get("message","Commission was refused")))
	if int(c097.state.coins)!=coins or int(signed.get("contract",{}).get("stipend",0))!=0 or int(signed.get("contract",{}).get("reward",0))!=0:
		return gap097("COMMISSION_MINTED","accept_commission changed coins or carried a stipend")
	if c097.Money.total(c097.state)!=supply097:
		return gap097("LEDGER","Coin supply changed when the letters were signed")
	return true

func _seek097() -> bool:
	_phase("bounded_observation_of_cargo_bearing_raider")
	seeking097=true
	owner097=_nearest_cargo097()
	var began: float=float(c097.state.day)*c097.DAY_SECONDS
	var last_plan: float=-INF
	if owner097.is_empty():
		var port: Dictionary=c097.port("reed_floats")
		if port.is_empty():return gap097("NO_SEARCH_COURSE","Reed Floats is not on this chart, so there is no ordinary search course")
		_did("Campaign.chart_course")
		var opened: Dictionary=c097.chart_course({"x":port.x,"y":port.y},"reed_floats")
		if not opened.get("ok",false):return gap097("NO_SEARCH_COURSE",str(opened.get("message","Ordinary coastal course was refused")))
		last_plan=float(c097.state.day)*c097.DAY_SECONDS
	for _step_index in range(180):
		if not _bounded097():return false
		var seen: String=_nearest_cargo097()
		if not seen.is_empty():
			owner097=seen
			var sight: Dictionary=receipt097.get("sighting",{})
			if c097.distance(c097.state.position,sight)<=75.0:
				c097.stop_sailing()
				break
			if float(c097.state.day)*c097.DAY_SECONDS-last_plan>=2.0:
				_did("Campaign.chart_course")
				var route: Dictionary=c097.chart_course({"x":sight.x,"y":sight.y})
				if not route.get("ok",false):return gap097("NO_INTERCEPT_COURSE",str(route.get("message","Course to the observed raider was refused")))
				last_plan=float(c097.state.day)*c097.DAY_SECONDS
		elif c097.state.path.is_empty():
			return _missing097("Reached the ordinary coastal course without a currently observed cargo-bearing raider")
		if float(c097.state.day)*c097.DAY_SECONDS-began>=SEEK097_SECONDS:break
		if not _advance097(0.5):return false
	seeking097=false
	if owner097.is_empty():return _missing097("Bounded observation found no cargo-bearing raider")
	var owner: Dictionary=c097.fleet_owner(owner097)
	var plan: Dictionary=c097.prize_shipment(owner)
	if not plan.ok:return gap097("CARGO_NOT_SHIPPABLE",str(plan.get("message","Observed cargo no longer fits a crewed hold")))
	var patrol: Dictionary=_patrol097(owner097)
	if patrol.is_empty() or c097.distance(c097.state.position,patrol)>75.0001:
		receipt097.lastSighting=receipt097.get("sighting",{})
		return gap097("INTERCEPTION_NOT_REACHED","The observed cargo-bearing raider was not reached within 75 water units. No position was written.")
	receipt097.target={"ownerId":owner097,"prizeGoods":plan.carrierCargo,"distance":c097.distance(c097.state.position,patrol)}
	return true

func _battle097() -> bool:
	_phase("actual_autopilot_battle")
	var owner: Dictionary=c097.fleet_owner(owner097)
	var expected: Array=[]
	for boat in owner.get("boats",[]):
		if boat is Dictionary and not boat.get("sunk",false):expected.append(str(boat.get("uid","")))
	expected.sort()
	if expected.is_empty():return gap097("NO_BOATS","The observed raider has no afloat boat")
	var patrol: Dictionary=_patrol097(owner097)
	if patrol.is_empty():return gap097("CONTACT_LOST","The observed raider left the chart before engage. No target was substituted.")
	_did("Main.engage_patrol")
	main097.engage_patrol(patrol)
	if main097.mode!="battle":
		return gap097("ENGAGE_REFUSED","Public engage did not start a battle. No fallback target was created.")
	var mission: Dictionary=main097.battle.get("mission",{})
	var actual: Array=[]
	for ship in main097.battle.get("ships",[]):
		if str(ship.get("team",""))=="enemy":actual.append(str(ship.get("uid","")))
	actual.sort()
	receipt097.engagement={"ownerId":owner097,"mission":str(mission.get("kind","")),"carrierOwnerId":str(mission.get("carrierOwnerId","")),"enemyUids":actual}
	if str(mission.get("kind",""))!="intercept" or str(mission.get("carrierOwnerId",""))!=owner097:
		return gap097("NO_INTERCEPT_MISSION","The battle did not carry this raider's existing shipment. It was not fought as a generic patrol.")
	if actual!=expected:
		return gap097("FALLBACK_TARGETS","Battle enemies are not the observed owner's boats")
	_did("Main.poll_battle051")
	for _poll in range(400):
		if not _bounded097():return false
		if main097.battle.get("result")!=null:break
		main097.poll_battle051(0.1,false)
		await process_frame
	await process_frame
	if main097.battle.get("result")==null:
		return gap097("BATTLE_UNFINISHED","Autopilot battle did not finish inside the bounded body. No result was written.")
	if main097.battle_report.is_empty():
		_did("Main.settle_battle")
		main097.settle_battle()
		await process_frame
	if main097.battle_report.is_empty() or not main097.battle_report.get("ok",true):
		return gap097("SETTLEMENT_REFUSED",str(main097.battle_report.get("message","Physical settlement did not publish")))
	receipt097.battle={"result":str(main097.battle.get("result","")),"seconds":float(main097.battle.get("time",0.0)),"coins":int(main097.battle_report.get("coins",0))}
	if str(main097.battle.get("result",""))!="won":
		return gap097("BATTLE_RESULT","Actual battle ended as "+str(main097.battle.get("result",""))+". No victory was substituted.")
	_did("Main.return_to_campaign")
	main097.return_to_campaign()
	if main097.mode!="campaign" or not c097.travel_lock064.is_empty():
		return gap097("RETURN_LOCKED","Settlement did not return to the campaign chart")
	if c097.Money.total(c097.state)!=supply097:
		return gap097("LEDGER","Coin supply changed across the actual battle")
	return true

func _choice097() -> bool:
	_phase("real_cargo_or_wreck_choice")
	var convoy: Dictionary=main097.battle_report.get("convoy",{})
	if convoy.is_empty():return gap097("NO_CONVOY_OUTCOME","The won battle published no shipment outcome")
	var captured_uid: String=""
	var captured_good: String=""
	var captured_qty: float=0.0
	for row in convoy.get("carriers",[]):
		if str(row.get("fate",""))!="captured":continue
		for good in row.get("cargoAboard",{}):
			if float(row.cargoAboard[good])>captured_qty:
				captured_qty=float(row.cargoAboard[good])
				captured_good=str(good)
				captured_uid=str(row.get("prizeUid",""))
	if captured_qty>0.0:
		if captured_uid.is_empty():return gap097("PRIZE_UID_MISSING","Settlement captured cargo without a held hull id")
		var weight: float=float(c097.Goods.ITEMS.get(captured_good,{}).get("weight",1.0))
		var fits: float=minf(captured_qty,maxf(0.0,c097.capacity()-c097.cargo_weight())/weight) if weight>0.0 else 0.0
		if fits<=0.0:return gap097("HOLD_FULL","Captured cargo does not fit the traveling hold. Nothing was jettisoned or added.")
		var before: float=float(c097.state.cargo.get(captured_good,0.0))
		var coins_before: int=int(c097.state.coins)
		var payroll_before: int=payroll097
		_did("Main.take_prize_cargo")
		var moved: Dictionary=main097.take_prize_cargo(captured_uid,captured_good,fits)
		if not moved.get("ok",false):return gap097("CARGO_TRANSFER_REFUSED",str(moved.get("message","Prize cargo transfer was refused")))
		var kept: bool=false
		for boat in c097.state.fleet+c097.state.get("boardingPrizes",[]):
			if str(boat.get("uid",""))==captured_uid and not boat.get("sunk",false):kept=true
		if not kept or not is_equal_approx(float(c097.state.cargo.get(captured_good,0.0)),before+fits):
			return gap097("CARGO_CUSTODY","The transfer did not keep the hull and credit the actual lot")
		if not _settle097():return false
		_count_wages097(coins_before,payroll_before)
		receipt097.choice={"kind":"keep_hull_take_cargo","uid":captured_uid,"good":captured_good,"qty":fits}
		return c097.Money.total(c097.state)==supply097 or gap097("LEDGER","Coin supply changed while moving prize cargo")
	for row in convoy.get("carriers",[]):
		if str(row.get("fate",""))!="sunk":continue
		var wreck_id: String=""
		for record in main097.battle_report.get("wrecks",[]):
			if str(record.get("uid",""))==str(row.get("uid","")):wreck_id=str(record.get("id",""))
		if wreck_id.is_empty():continue
		var wreck: Dictionary=c097.Salvage.find_wreck(c097.state,wreck_id)
		var good: String=""
		var qty: float=0.0
		for item in wreck.get("stores",{}):
			if str(item) in ["food","fuel","supplies","ammo"]:continue
			if float(wreck.stores[item])>qty:qty=float(wreck.stores[item]);good=str(item)
		if good.is_empty() or qty<=0.0:continue
		if c097.distance(c097.state.position,wreck)>180.0:
			_did("Campaign.chart_course")
			var route: Dictionary=c097.chart_course({"x":wreck.x,"y":wreck.y})
			if not route.get("ok",false):return gap097("WRECK_NOT_REACHED",str(route.get("message","No course to the actual wreck")))
			if not _finish_course097():return false
			if c097.distance(c097.state.position,wreck)>180.0:return gap097("WRECK_NOT_REACHED","The wreck is still outside recovery range. The fleet was not moved by writing its position.")
		c097.stop_sailing()
		var weight: float=float(c097.Goods.ITEMS.get(good,{}).get("weight",1.0))
		var fits: float=minf(qty,maxf(0.0,c097.capacity()-c097.cargo_weight())/weight) if weight>0.0 else 0.0
		if fits<=0.0:return gap097("HOLD_FULL","Wreck cargo does not fit the traveling hold. Nothing was jettisoned or added.")
		var before: float=float(c097.state.cargo.get(good,0.0))
		var coins_before: int=int(c097.state.coins)
		var payroll_before: int=payroll097
		_did("Main.recover_wreck")
		var stripped: Dictionary=main097.recover_wreck(wreck_id,"strip",good,fits)
		if not stripped.get("ok",false):return gap097("RECOVERY_REFUSED",str(stripped.get("message","Paid wreck recovery was refused")))
		if not _settle097():return false
		_count_wages097(coins_before,payroll_before)
		if not is_equal_approx(float(c097.state.cargo.get(good,0.0)),before+fits):
			return gap097("WRECK_CUSTODY","Strip did not credit the wreck's actual remaining lot")
		receipt097.choice={"kind":"wreck_strip","wreckId":wreck_id,"good":good,"qty":fits,"hullTaken":false}
		return c097.Money.total(c097.state)==supply097 or gap097("LEDGER","Coin supply changed during wreck recovery")
	return gap097("NO_PRIZE_CHOICE","The won shipment left no captured hull cargo and no wreck lot. Escaped goods were left aboard. No prize was created.")

func _return097() -> bool:
	_phase("paid_home_return_repair_and_stores")
	var home: String=str(c097.data.START.get("port","brass_haven"))
	if str(c097.current_port().get("id",""))!=home:
		var port: Dictionary=c097.port(home)
		if port.is_empty():return gap097("NO_HOME","The career home port is not on this chart")
		_did("Campaign.chart_course")
		var route: Dictionary=c097.chart_course({"x":port.x,"y":port.y},home)
		if not route.get("ok",false):return gap097("NO_HOME_COURSE",str(route.get("message","Home course was refused")))
		if not _finish_course097() or not _advance097(0.5):return false
	if str(c097.current_port().get("id",""))!=home:return gap097("NOT_DOCKED","The return course did not reach the home berth")
	var dock: Dictionary=c097.current_port()
	for boat in c097.state.fleet:
		var quote: Dictionary=c097.service_quote(boat,dock)
		if not quote.get("ok",false) or int(quote.get("cost",0))<=0:continue
		var coins: int=int(c097.state.coins)
		_did("Campaign.repair_boat")
		var repaired: Dictionary=c097.repair_boat(str(boat.uid))
		if not repaired.get("ok",false):return gap097("REPAIR_REFUSED",str(repaired.get("message","Home repair was refused")))
		if int(c097.state.coins)!=coins-int(quote.cost):return gap097("REPAIR_PRICE","Home repair did not debit the quoted coins")
		repair097+=int(quote.cost)
	if repair097==0:receipt097.repairNote="No positive-cost repair quote. No damage was added."
	var coins_before: int=int(c097.state.coins)
	_did("Campaign.resupply_boat")
	var stocked: Dictionary=c097.resupply_boat(uid097,"full")
	if stocked.get("ok",false):stores097+=coins_before-int(c097.state.coins)
	else:receipt097.storesNote=str(stocked.get("message",""))
	var food: int=ceili(maxf(0.0,float(c097.data.START.food)-float(c097.state.cargo.get("food",0.0))))
	if food>0:
		coins_before=int(c097.state.coins)
		_did("Campaign.trade")
		var bought: Dictionary=c097.trade(home,"food",food,"buy")
		if bought.get("ok",false):stores097+=coins_before-int(c097.state.coins)
		else:receipt097.foodNote=str(bought.get("message",""))
	if not _settle097():return false
	return c097.Money.total(c097.state)==supply097 or gap097("LEDGER","Coin supply changed during the paid return")

func _nearest_cargo097() -> String:
	var best: String=""
	var distance: float=INF
	_did("NavalAI.observe")
	for seen in c097.NavalAI.observe(c097.state):
		if not seen.get("current",false):continue
		var id: String=str(seen.get("ownerId",""))
		if id.is_empty() or c097.NavalAI.NavalOrders.enrolled066(c097.state,id):continue
		var owner: Dictionary=c097.fleet_owner(id)
		if not c097.prize_shipment(owner).ok:continue
		var candidate: float=c097.distance(c097.state.position,seen)
		if candidate<distance:
			distance=candidate
			best=id
			receipt097.sighting=seen.duplicate(true)
	return best

func _missing097(message: String) -> bool:
	receipt097.raiders=_raider_scan097()
	return gap097("NO_OBSERVED_CARGO_HOSTILE",message)

func _raider_scan097() -> Array:
	var rows: Array=[]
	var observed: Dictionary={}
	for seen in c097.NavalAI.observe(c097.state):
		if seen.get("current",false):observed[str(seen.get("ownerId",""))]=true
	for owner in c097.state.get("fleetOwners",[]):
		if str(owner.get("kind",""))!="raider":continue
		var lots: Dictionary={}
		var cargo: Dictionary=owner.get("cargo",{}) if owner.get("cargo") is Dictionary else {}
		for good in cargo:
			if str(good) in ["food","fuel","supplies","ammo"]:continue
			if float(cargo[good])>0.0:lots[str(good)]=float(cargo[good])
		var plan: Dictionary=c097.prize_shipment(owner)
		if lots.is_empty() and not plan.ok:continue
		rows.append({"id":str(owner.get("id","")),"observed":bool(observed.get(str(owner.get("id","")),false)),"hostile":c097.Politics.hostile(c097,owner),"lots":lots,"prizeOk":bool(plan.ok),"message":str(plan.get("message",""))})
		if rows.size()>=8:break
	return rows

func _patrol097(id: String) -> Dictionary:
	for patrol in c097.state.patrols:
		if str(patrol.get("id",""))==id:return patrol
	return {}

func _settle097() -> bool:
	while c097.pending_days>0:
		if not _bounded097():return false
		var before: int=int(c097.state.coins)
		c097.pending_days-=1
		_did("EconomyWorkers.finish")
		workers097.start(c097.state.ports,1,c097.TradeFlow.blockades(c097),int(c097.state.seed)+int(c097.state.econDay)*104729)
		var result: Dictionary=workers097.finish(true)
		c097.apply_economy(result.ports,result.events,result.days)
		payroll097+=maxi(0,before-int(c097.state.coins))
		if int(c097.state.wageArrears)!=0:return gap097("PAYROLL_UNPAID","An ordinary sailing day left wage arrears. No coins were granted.")
		if c097.Money.total(c097.state)!=supply097:return gap097("LEDGER","Coin supply changed during ordinary payroll")
	return true

func _advance097(seconds: float) -> bool:
	if not _bounded097():return false
	var before: float=float(c097.state.day)
	_did("Campaign.step")
	c097.step(seconds)
	if not _settle097():return false
	var clipped: bool=false
	for event in c097.pop_events():
		var kind: String=str(event.get("kind",""))
		if kind=="defeat":return gap097("VOYAGE_LOSS","An actual loss ended this continuation. No replacement fleet was granted.")
		if kind=="ocean_encounter066":return gap097("WRONG_CHART_CONTACT","An offshore contact interrupted the home-chart continuation")
		if kind!="encounter":continue
		clipped=true
		var id: String=str(event.get("patrol",""))
		var owner: Dictionary=c097.fleet_owner(id)
		if seeking097 and c097.prize_shipment(owner).ok:
			owner097=id
			continue
		if seeking097:
			c097.state.encounterGrace=90.0
			if receipt097.avoided.size()<8:receipt097.avoided.append(id)
			_did("Avoid contact")
			continue
		return gap097("INTERRUPTED","An actual encounter interrupted the paid return. It was not skipped or fought as a second battle.")
	var accepted: float=float(c097.state.day)-before
	if accepted<0.0 or (accepted<=0.0 and not clipped) or accepted>seconds/c097.DAY_SECONDS+0.000001:
		return gap097("CLOCK","Sailing did not accept a normal bounded interval")
	return c097.Money.total(c097.state)==supply097 or gap097("LEDGER","Coin supply changed while sailing")

func _finish_course097() -> bool:
	for _piece in range(80):
		if c097.state.path.is_empty():return true
		if not _advance097(4.0):return false
	return gap097("COURSE_UNFINISHED","The ordinary course did not finish inside the bounded movement loop")

func _bounded097() -> bool:
	if Time.get_ticks_msec()-started097<BODY097_MS-2000:return true
	return gap097("BODY_TIMEOUT","The 45-second continuation stopped new work. Partial state is not a pass.")

func _count_wages097(before_coins: int,before_payroll: int) -> void:
	var drop: int=maxi(0,before_coins-int(c097.state.coins))
	var counted: int=payroll097-before_payroll
	if drop>counted:payroll097+=drop-counted

func _did(command: String) -> void:
	if not receipt097.commands.has(command):receipt097.commands.append(command)

func _phase(label: String) -> void:
	var row: Dictionary={"phase":label,"elapsedMs":Time.get_ticks_msec()-started097,"day":float(c097.state.day),"coins":int(c097.state.coins)}
	receipt097.phases.append(row)
	print("PRIVATEER097_PHASE ",JSON.stringify(row))

func gap097(code: String,message: String) -> bool:
	if str(receipt097.get("status",""))=="GAP":return false
	receipt097.status="GAP"
	receipt097.earnedContinuation=false
	receipt097.humanFunProof=false
	var snap: Dictionary={}
	if c097!=null and c097.state is Dictionary and not c097.state.is_empty():snap=_snap097()
	receipt097.gap={"code":code,"message":message,"state":snap}
	print("PRIVATEER097_GAP ",JSON.stringify(receipt097.gap))
	return false

func _snap097() -> Dictionary:
	var deal: Dictionary={}
	if c097.state.get("relationships") is Dictionary and c097.state.relationships.get("commission") is Dictionary:deal=c097.state.relationships.commission
	var battle_result: String=""
	if main097!=null and main097.battle is Dictionary:battle_result=str(main097.battle.get("result",""))
	return {"day":float(c097.state.day),"coins":int(c097.state.coins),"seed":int(c097.state.get("seed",-1)),"position":c097.state.position.duplicate(true),"port":str(c097.current_port().get("id","")),"ownerId":owner097,"battleResult":battle_result,"commissionFaction":str(deal.get("factionId","")),"commissionCommitted":bool(deal.get("committed",false))}

func _finish097() -> void:
	if finished097:return
	finished097=true
	var artifacts: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if artifacts.is_absolute_path() and c097!=null and c097.state is Dictionary and not c097.state.is_empty() and str(receipt097.get("status",""))=="GAP":
		var partial: String=artifacts.path_join("privateer097-partial.json")
		var file=FileAccess.open(partial,FileAccess.WRITE)
		if file!=null:
			file.store_string(JSON.stringify(c097.state))
			file.close()
			receipt097.partialPath=partial
			receipt097.partialSha256=FileAccess.get_sha256(partial).to_lower()
			receipt097.partialMeaning="Partial earned state after a GAP. Not a completed privateer voyage and not a pass."
	if workers097!=null and workers097.group_id>=0:workers097.finish(true)
	if main097!=null:
		main097._retire_battle_driver051()
		if main097.core!=null and main097.core.state is Dictionary and not main097.core.state.is_empty() and main097.mode=="campaign":main097.sync_economy()
		main097.queue_free()
		await process_frame
	var elapsed: int=Time.get_ticks_msec()-started097
	if str(receipt097.get("status",""))=="UNFINISHED":receipt097.status="FAILED"
	receipt097.checks=checks
	receipt097.failures=failures
	receipt097.elapsedMs=elapsed
	receipt097.humanFunProof=false
	if artifacts.is_absolute_path():
		var result=FileAccess.open(artifacts.path_join("privateer097-earned-result.json"),FileAccess.WRITE)
		if result!=null:
			result.store_string(JSON.stringify(receipt097,"\t"))
			result.close()
	print("PRIVATEER097_RESULT ",JSON.stringify(receipt097))
	var code: int=0
	if failures>0 or str(receipt097.status)=="FAILED":code=1
	elif str(receipt097.status)=="GAP":code=2
	elif str(receipt097.status)!="COMPLETED":code=1
	print("privateer097 earned: %d checks, %d failures, status %s"%[checks,failures,str(receipt097.status)])
	quit(code)
