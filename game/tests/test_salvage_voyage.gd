extends SceneTree
## Root-only prepared native proof. One Main/Campaign/world/nav and one seeded
## validated baseline; scenarios copy state, never rebuild the world. The sunk
## existing NPC and captured-prize flags below are DECLARED FIXTURE SETUP, not
## earned combat. The paid upgrade receives no coins, goods, crew or new parts.
const Salvage=preload("res://scripts/salvage.gd")
const Damage=preload("res://scripts/damage.gd")
const Money=preload("res://scripts/money.gd")
const Condition=preload("res://scripts/equipment_condition.gd")
const Records=preload("res://scripts/equipment_records.gd")
const Recovery=preload("res://scripts/equipment_recovery.gd")
const Preflight=preload("res://scripts/equipment_campaign.gd")
const SaveValidation=preload("res://scripts/save_validation.gd")
const Expedition=preload("res://scripts/expedition.gd")
const Decisions=preload("res://scripts/recovery_decisions.gd")
const Refit=preload("res://scripts/refit.gd")
const TOTAL_MS: int=35000
const EPS: float=0.000000001
var checks: int=0
var failures: int=0
var started_ms: int=0
var scene
var c
var baseline: Dictionary={}
var prepared: Dictionary={}
var full_hold: Dictionary={}
var source_parts: Dictionary={}
var wreck_id: String=""
var carrier_uid: String=""
var source_uid: String=""
var anchor: Dictionary={}
var gear_request: Dictionary={}

func check(ok: bool,message: String) -> bool:
	checks+=1
	if not ok:failures+=1;print("FAIL salvage voyage: ",message)
	return ok

func phase(label: String) -> bool:
	print("salvage058 phase: ",label," ms=",Time.get_ticks_msec()-started_ms," checks=",checks," failures=",failures)
	return check(Time.get_ticks_msec()-started_ms<TOTAL_MS-1500,"Phase stays inside the bounded fixture: "+label)

func snapshot() -> String:
	return JSON.stringify({"state":c.state,"pending":c.pending_days,"events":c.events,"economyTask":scene.economy_task})

func branch(saved: Dictionary) -> void:
	# Only detached scenario resets. No unjoined Main job may lose its owner.
	assert(scene.economy_task<0)
	c.state=saved.duplicate(true)
	c.pending_days=0;c.events.clear();c.sailing_clearance=0.0

func conserved(label: String) -> bool:
	return check(Money.total(c.state)==int(c.state.coinSupply),label+": actual global coins conserve")

func item_at(condition: Dictionary,location: String) -> Dictionary:
	for item in condition.get("items",{}).values():
		if str(item.get("location",""))==location:return item
	return {}

func same_part(a: Dictionary,b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():return false
	for key in ["itemUid","family","typeId","originHullType","hp","status","cause"]:
		if a.get(key)!=b.get(key):return false
	return true

func sorted_keys(items: Dictionary) -> Array:
	var ids: Array=items.keys();ids.sort();return ids

func sail(target: Dictionary,port_id: String="") -> bool:
	var order: Dictionary=c.chart_course(target,port_id)
	if not check(bool(order.ok),"Actual chart_course: "+str(order.message)):return false
	for i in range(12):
		if c.state.path.is_empty():
			c.stop_sailing()
			return check(c.distance(c.state.position,target)<65.0 if port_id.is_empty() else str(c.current_port().get("id",""))==port_id,"Actual route reaches its named endpoint")
		if Time.get_ticks_msec()-started_ms>=TOTAL_MS-1500:return check(false,"Sailing obeys the fixture deadline")
		var length: float=0.0
		var previous: Dictionary=c.state.position
		for point in c.state.path:length+=c.distance(previous,point);previous=point
		var speed: float=c.travel_speed()
		if not check(speed>0,"The real crewed fleet retains sailing speed"):return false
		c.step(minf(4.0,maxf(0.001,length/speed+0.00001)))
		scene.sync_economy()
	return check(false,"The short real return route finishes within twelve chunks")

func _initialize():
	started_ms=Time.get_ticks_msec()
	call_deferred("run")

func run() -> void:
	phase("one Main and validated seed83 baseline")
	scene=load("res://main.tscn").instantiate()
	scene.process_mode=Node.PROCESS_MODE_DISABLED
	root.add_child(scene)
	scene.audio.enabled=false;scene.music.enabled=false
	scene.paused=true;scene.set_process(false);scene.set_physics_process(false)
	scene.mode="campaign"
	scene.save_directory=OS.get_user_data_dir().path_join("salvage058-%d"%Time.get_ticks_usec())
	c=scene.core
	var seeded: Dictionary=c.new_game(83)
	if not check(bool(seeded.ok),"The single seeded campaign publishes: "+str(seeded.message)):
		await finish();return
	var validation: Dictionary=SaveValidation.validate(c.state.duplicate(true),c.data)
	if not check(bool(validation.ok),"The shared baseline passes real save validation: "+str(validation.get("message",""))):
		await finish();return
	baseline=c.state.duplicate(true)
	legacy_assertions()
	if not phase("one existing damaged NPC encounter fixture") or not prepare_encounter():
		await finish();return
	if not preview_and_owned_prize() or not phase("actual paid useful tow and upgrade") or not paid_upgrade():
		await finish();return
	if not phase("nearly full finite strip choice") or not constrained_strip():
		await finish();return
	if not phase("selected gear refusals and real in-flight Main ownership") or not selected_gear():
		await finish();return
	if phase("later paid cargo and exact physical save/restore"):later_cargo_and_restore()
	await finish()

func legacy_assertions() -> void:
	# All fourteen original meaningful assertions remain, on a detached baseline.
	var initial_food: float=c.state.cargo.food
	check(c.jettison("food",3).ok and c.state.cargo.food==initial_food-3,"A marked float contains actual offloaded goods")
	var float_id: String=c.state.wrecks[0].id
	check(c.recover_wreck(float_id,"strip").ok and c.state.cargo.food==initial_food,"The same finite food can be recovered into available space")
	check(not c.recover_wreck(float_id,"strip").ok,"Claimed cargo cannot duplicate")
	var site: Dictionary=c.state.position.duplicate(true)
	site.id="finite-test-site"
	var w: Dictionary=Salvage.seed_site_wreck(c,site,"harbor_sloop")
	check(Salvage.strip_good(c,w.id,"timber",0.1).ok,"Recover one selected component instead of the entire wreck")
	check(not Salvage.quote(c,w.id,"tow").ok,"Structural stripping forbids a second complete hull recovery")
	var amount: float=c.state.cargo.timber
	check(Salvage.strip_good(c,w.id,"timber",0.1).ok and is_equal_approx(c.state.cargo.timber,amount+0.1),"Remaining finite lots can still be stripped")
	var ship: Dictionary=Damage.create_ship(c.hull("tin_skiff"),{"ammo":2.25,"fuel":0.004,"supplies":0.004})
	ship.sunk=true;ship.team="enemy"
	var records: Array=Salvage.record_battle(c,{"ships":[ship]},"fractional-stores")
	check(is_equal_approx(records[0].stores.ammo,2.25/50.0),"Fractional ammo cases retain every original round without rounding up")
	check(is_equal_approx(records[0].stores.fuel,0.004),"Tiny remaining fuel is neither minted nor lost to display rounding")
	for i in range(140):Salvage.record_battle(c,{"ships":[ship]},"prune-fixture-%d"%i)
	check(c.state.wrecks.size()<=128,"Wreck history stays bounded")
	check(Salvage.seed_site_wreck(c,site,"harbor_sloop").is_empty(),"A pruned ancient site cannot spawn a fresh replacement wreck")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	check(c.restore(saved).ok,"Persistent wrecks and provenance pass actual campaign restore")
	check(Money.total(c.state)==int(c.state.coinSupply),"Recovery keeps the global coin ledger exact")
	branch(baseline)
	c.jettison("food",1)
	scene.ui.RecoveryUI.open(scene.ui)
	check(scene.ui.modal_kind=="recovery","Recovery board opens in actual Main")
	scene.ui.RecoveryUI.blueprints(scene.ui)
	check(scene.ui.modal_kind=="blueprints","Drawing library opens in actual Main")
	scene.ui.close_modal()

func prepare_encounter() -> bool:
	branch(baseline)
	carrier_uid=str(c.state.fleet[0].uid)
	# Actual elapsed time, not an injected day: selected work will cross payroll.
	c.step(42.75);scene.sync_economy()
	var home: Dictionary=c.port("brass_haven")
	for offset in [Vector2(160,0),Vector2(-160,0),Vector2(0,160),Vector2(0,-160)]:
		var candidate: Dictionary={"x":float(home.x)+offset.x,"y":float(home.y)+offset.y}
		if c.Navigation.is_water(c.nav,candidate.x,candidate.y,c.Routes.clearance(c)) and not c.Routes.path(c,c.state.position,candidate).is_empty():
			anchor=candidate;break
	if not check(not anchor.is_empty(),"A short real water route exists outside harbor service range"):return false
	if not sail(anchor):return false
	if not check(c.current_port().is_empty(),"Recovery work occurs offshore, outside harbor crew spending"):return false
	var owner: Dictionary=c.fleet_owner("patrol-2")
	var actor: Dictionary={}
	for boat in owner.get("boats",[]):
		if str(boat.get("type",""))=="bilge_punt" and not boat.get("sunk",false):actor=boat;break
	if not check(not actor.is_empty() and actor.get("moduleCondition") is Dictionary,"Use one existing canonical small NPC boat; create no replacement item"):return false
	source_uid=str(actor.uid)
	for location in ["mount0","engine"]:
		var part: Dictionary=item_at(actor.moduleCondition,location)
		if not check(not part.is_empty(),"Existing actor has its real "+location):return false
		var loss: float=0.375 if location=="mount0" else 0.125
		if not check(Condition.apply_component_damage(actor.moduleCondition,{"itemUid":str(part.itemUid),"loss":loss,"cause":"Declared recovery058 fixture damage"}).ok,"Physically damage existing "+location):return false
	if not check(Records.publish(actor).ok,"Publish real damaged source equipment"):return false
	# DECLARED ENCOUNTER SETUP ONLY. No Battle victory, reward or earned capture.
	# Keep every owner/hostile; mark this existing actor sunk and let record_battle
	# retire its actual condition and freeze its actual finite onboard stores.
	actor.team="enemy";actor.sunk=true;actor.hp=0.0
	var wrecks: Array=Salvage.record_battle(c,{"ships":[actor],"chartPosition":c.state.position},"recovery058-declared-encounter")
	if not check(wrecks.size()==1,"One existing source actor becomes exactly one declared wreck"):return false
	var wreck: Dictionary=wrecks[0]
	wreck_id=str(wreck.id)
	source_parts=wreck.get("sourceModuleCondition",{}).get("items",{}).duplicate(true)
	check(str(wreck.get("equipmentCustody",""))=="wreck" and not actor.has("moduleCondition") and str(actor.get("equipmentRetiredTo",""))==wreck_id,"Existing actor retires exactly once into canonical wreck custody")
	check(c.state.fleetOwners.size()==baseline.fleetOwners.size() and c.state.patrols.size()==baseline.patrols.size(),"Fixture deletes no hostile, owner or chart patrol")
	var gun: Dictionary=item_at(wreck.sourceModuleCondition,"mount0")
	var engine: Dictionary=item_at(wreck.sourceModuleCondition,"engine")
	gear_request={"itemUids":[str(gun.itemUid),str(engine.itemUid)],"carrierUid":carrier_uid,"acceptForfeiture":true}
	var custody: Dictionary=Preflight.check_state(c.state,c.data)
	if not check(bool(custody.ok),"Prepared physical encounter passes whole-campaign custody: "+str(custody.get("message",""))):return false
	prepared=c.state.duplicate(true)
	print("salvage058 fixture ONLY: owner=patrol-2 source=",source_uid," wreck=",wreck_id," parts=",source_parts.size()," purse=",c.state.coins," day=",c.state.day," hostiles retained; no earned combat claimed")
	return conserved("Declared encounter setup")

func preview_and_owned_prize() -> bool:
	var before: String=snapshot()
	var comparison: Dictionary=Decisions.compare(c,wreck_id,"tow","",0.0,{},"brass_haven")
	if not check(bool(comparison.ok),"Real detached tow comparison: "+str(comparison.message)):return false
	check(snapshot()==before,"Tow preview does not debit, advance, mutate custody or open an offer")
	check(bool(comparison.after.get("routeOk",false)) and str(comparison.after.get("returnPortId",""))=="brass_haven" and not comparison.after.get("path",[]).is_empty(),"Comparison names a legal navigable Brass Haven return")
	check(float(comparison.after.get("routeSpeed",0))<float(comparison.before.get("routeSpeed",0)) and float(comparison.after.get("workDays",0))>0,"Tow comparison includes slower return and positive work before return")
	check(comparison.service.get("quote",{}).get("ok",false) and comparison.service.get("projectionOnly",false),"Later paid repair is a real quote, explicitly a projection")
	scene.ui.RecoveryUI.open(scene.ui,wreck_id)
	scene.ui.RecoveryUI.leave(scene.ui)
	check(snapshot()==before,"Open and leave the actual recovery board without work, payment or extraction")
	scene.ui.RecoveryUI.gear(scene.ui,wreck_id,gear_request.itemUids,carrier_uid)
	scene.ui.RecoveryUI.leave(scene.ui)
	check(snapshot()==before,"Actual gear selection and decline remain a pure preview before final forfeiture")
	# Board-only fixture: re-label the EXISTING owned starter; add no free boat.
	var owned: Dictionary=c.find_boat(carrier_uid)
	owned.captureSecured=true;owned.convoyCargo={};owned.supportOnly=true
	before=snapshot()
	var prizes: Array=scene.ui.RecoveryUI.captured_prizes(c)
	check(prizes.size()==1 and str(prizes[0].uid)==carrier_uid,"An empty secured owned prize remains visible by its actual UID")
	var prize: Dictionary=Decisions.prize(c,carrier_uid,"brass_haven")
	check(prize.get("ok",false) and prize.get("equipment",[]).size()==owned.moduleCondition.items.size(),"Empty prize inspection retains real fitted equipment")
	scene.ui.RecoveryUI.owned_prize(scene.ui,carrier_uid)
	scene.ui.RecoveryUI.leave(scene.ui)
	check(snapshot()==before and not c.find_boat(carrier_uid).is_empty(),"Closing the board preserves the already-owned empty prize")
	branch(prepared)
	return true

func paid_upgrade() -> bool:
	var q: Dictionary=c.recovery_quote(wreck_id,"tow")
	if not check(bool(q.ok),"Paid tow quote is actually affordable: "+str(q.message)):return false
	var coins: int=int(c.state.coins)
	var savings: int=int(c.state.crewPurse)
	var food: float=float(c.state.cargo.food)
	var day: float=float(c.state.day)
	var capacity: float=c.capacity()
	var upkeep: Dictionary=c.Economy.daily_upkeep(c.state.fleet)
	var work: float=maxf(1.0,float(q.ordinary)/200.0)
	var payroll: int=int(day+work)-int(day)
	var taken: Dictionary=scene.recover_wreck(wreck_id,"tow")
	if not check(bool(taken.ok),"Actual Main tow pays its real contract: "+str(taken.message)):return false
	var boat_uid: String=str(taken.get("boatUid",""))
	var boat: Dictionary=c.find_boat(boat_uid)
	check(not boat.is_empty() and boat.crew==0 and boat.fuel==0 and boat.ammo==0 and boat.supplies==0 and boat.get("needsHarborRepair",false),"Paid tow retains a damaged, uncrewed, empty hull requiring service")
	check(is_equal_approx(c.capacity(),capacity) and boat.get("supportOnly",false),"Unrepaired tow donates no working hold or combat deployment")
	check(absf(float(c.state.day)-day-work)<EPS and c.pending_days==0,"Main joins normal work-day settlement")
	check(int(c.state.coins)==coins-int(q.total)-payroll*int(upkeep.wages) and int(c.state.crewPurse)==savings+payroll*int(upkeep.wages),"Tow fee and integer-day normal sailor wages are paid from the limited purse")
	check(absf(float(c.state.cargo.food)-(food-payroll*float(upkeep.food)))<EPS and c.state.wageArrears==0,"Tow work consumes normal finite provisions without wage arrears")
	for uid in source_parts:
		check(same_part(source_parts[uid],boat.get("moduleCondition",{}).get("items",{}).get(uid,{})),"Tow preserves actual source item identity and damage: "+str(uid))
	if not conserved("Actual tow") or not sail(c.port("brass_haven"),"brass_haven"):return false
	boat=c.find_boat(boat_uid)
	var harbor: Dictionary=c.current_port()
	var bill: Dictionary=c.service_quote(boat,harbor)
	if not check(bill.get("ok",false) and int(bill.get("cost",0))>0,"Real harbor quotes a positive full installed-equipment/hull bill"):return false
	coins=int(c.state.coins)
	var stocks: Dictionary=harbor.stocks.duplicate(true)
	var repaired: Dictionary=c.repair_boat(boat_uid)
	if not check(bool(repaired.ok),"Normal paid harbor repair really succeeds: "+str(repaired.message)):return false
	boat=c.find_boat(boat_uid);harbor=c.current_port()
	check(int(c.state.coins)==coins-int(bill.cost) and absf(float(harbor.stocks.supplies)-(float(stocks.supplies)-float(bill.purchase)))<EPS,"Repair debits the quoted purse and finite real kit stock")
	for good in bill.get("equipmentMaterials",{}):
		check(absf(float(harbor.stocks[good])-(float(stocks[good])-float(bill.equipmentMaterials[good])))<EPS,"Repair consumes real "+str(good))
	check(boat.hp==boat.maxHp and not boat.get("needsHarborRepair",false) and not boat.get("towed",false),"Paid service releases the repaired hull from tow")
	check(sorted_keys(boat.moduleCondition.items)==sorted_keys(source_parts),"Paid repair keeps the original physical part UIDs")
	for part in boat.moduleCondition.items.values():check(float(part.hp)==1.0,"Only actual paid service restores installed part "+str(part.itemUid))
	var count: int=int(boat.crewMin)
	var hires: int=c.Economy.recruit_cost(harbor,count)
	var recruits: int=int(harbor.recruits)
	coins=int(c.state.coins)
	var hired: Dictionary=c.recruit_crew(boat_uid,count)
	if not check(bool(hired.ok),"Recruit actual harbor sailors: "+str(hired.message)):return false
	check(int(c.state.coins)==coins-hires and int(c.current_port().recruits)==recruits-count and int(c.find_boat(boat_uid).crew)==count,"Minimum crew is paid and removed from the finite harbor workforce")
	coins=int(c.state.coins);stocks=c.current_port().stocks.duplicate(true)
	var supplied: Dictionary=c.resupply_boat(boat_uid,"voyage")
	if not check(bool(supplied.ok),"Buy real voyage stores: "+str(supplied.message)):return false
	boat=c.find_boat(boat_uid);harbor=c.current_port()
	check(int(c.state.coins)<coins and boat.fuel>=3.0 and boat.ammo>=80.0 and boat.supplies>=6.0,"Working fuel, rounds and kits are bought, never recovered perfect/free")
	check(float(harbor.stocks.fuel)<float(stocks.fuel) and float(harbor.stocks.ammo)<float(stocks.ammo) and float(harbor.stocks.supplies)<float(stocks.supplies),"Paid stores consume the harbor's actual three stocks")
	if boat.get("supportOnly",false):check(c.FleetSupport.reserve(c,boat_uid).ok,"The repaired crewed partner can join normal combat deployment")
	check(c.active_fleet().has(boat) and not boat.get("supportOnly",false) and c.capacity()>capacity and int(c.state.coins)>0 and int(c.state.coins)<int(prepared.coins),"The finite purse yields an actually useful crewed partner with more working hold")
	print("salvage058 paid outcome: tow=",q.total," workDays=",work," sailorWages=",payroll*int(upkeep.wages)," repair=",bill.cost," hires=",hires," starting=",prepared.coins," remaining=",c.state.coins," capacity=",c.capacity())
	return conserved("Paid useful upgrade")

func constrained_strip() -> bool:
	branch(prepared)
	if not sail(c.port("brass_haven"),"brass_haven"):return false
	var fill: int=floori(c.capacity()-c.cargo_weight())-1
	if not check(fill>0 and c.trade("brass_haven","food",fill,"buy").ok,"Nearly full hold is loaded through real paid trade"):return false
	if not sail(anchor):return false
	full_hold=c.state.duplicate(true) # Reuse this actual paid hold for refusal.
	var tow: Dictionary=c.recovery_quote(wreck_id,"tow")
	var keep: int=int(tow.get("total",0))-1
	# Declared low-reserve branch only: park existing coins in an existing purse.
	# This conserves coins and funds neither the claimed upgrade nor extraction.
	if not check(keep>=int(c.Economy.daily_upkeep(c.state.fleet).wages) and Money.move(c.state,"coins",c.port("brass_haven"),"governmentPurse",int(c.state.coins)-keep,"Declared constrained-reserve fixture",c.state.moneyLog),"Constrained branch parks actual surplus coins without minting any"):return false
	var quantity: float=0.25
	var before: String=snapshot()
	var strip: Dictionary=Decisions.compare(c,wreck_id,"strip","timber",quantity,{},"brass_haven")
	var towing: Dictionary=Decisions.compare(c,wreck_id,"tow","",0.0,{},"brass_haven")
	if not check(strip.get("ok",false) and not towing.get("ok",false),"Finite half-space strip is affordable while the tow contract is beyond this purse"):return false
	check(snapshot()==before,"Both constrained comparisons leave the actual state untouched")
	scene.ui.RecoveryUI.store_choice(scene.ui,wreck_id,"timber",quantity)
	scene.ui.RecoveryUI.leave(scene.ui)
	check(snapshot()==before,"Actual selected-store preview and decline do not charge or strip")
	check(c.capacity()-c.cargo_weight()>0 and c.capacity()-c.cargo_weight()<=1.001 and float(strip.after.get("workDays",0))<maxf(1.0,float(tow.get("ordinary",100))/200.0),"One free hold space favors a smaller finite working commitment")
	var wreck: Dictionary=Salvage.find_wreck(c.state,wreck_id)
	var timber: float=float(wreck.components.get("timber",0))
	var cargo: float=float(c.state.cargo.timber)
	var wallet: int=int(c.state.coins)
	var food: float=float(c.state.cargo.food)
	var day: float=float(c.state.day)
	var result: Dictionary=scene.recover_wreck(wreck_id,"strip","timber",quantity)
	if not check(bool(result.ok),"Actual Main strips only the chosen finite plank lot: "+str(result.message)):return false
	wreck=Salvage.find_wreck(c.state,wreck_id)
	check(absf(float(wreck.components.get("timber",0))-(timber-quantity))<EPS and absf(float(c.state.cargo.timber)-(cargo+quantity))<EPS,"Selected plank quantity leaves the rest finite, without duplication")
	var work: Dictionary=strip.quote
	check(int(work.get("wages",0))>0 and int(c.state.coins)==wallet-int(work.wages) and absf(float(c.state.cargo.food)-(food-float(work.food)))<EPS and absf(float(c.state.day)-day-float(work.workDays))<EPS,"Finite strip pays its real rounded wages and food while advancing actual work time")
	check(not c.recovery_quote(wreck_id,"tow").ok and c.state.wageArrears==0 and c.cargo_weight()<=c.capacity()+EPS,"Structural strip forfeits tow while normal work remains paid and carried")
	print("salvage058 constrained strip: quantity=",quantity," coins=",c.state.coins," free=",c.capacity()-c.cargo_weight())
	return conserved("Constrained finite strip")

func selected_gear() -> bool:
	branch(prepared)
	var quote: Dictionary=c.recovery_quote(wreck_id,"gear","",0.0,gear_request)
	if not check(bool(quote.ok),"Exact selected gear quote is ready: "+str(quote.message)):return false
	var declined: Dictionary=gear_request.duplicate(true);declined.acceptForfeiture=false
	var before: String=snapshot()
	var refused: Dictionary=scene.recover_wreck(wreck_id,"gear","",0.0,declined)
	check(not refused.ok and snapshot()==before,"Declining explicit forfeiture advances nothing, charges nothing and transfers nothing")
	branch(full_hold);before=snapshot()
	refused=scene.recover_wreck(wreck_id,"gear","",0.0,gear_request)
	check(not refused.ok and snapshot()==before,"The real nearly full hold refuses selected parts atomically")
	branch(prepared)
	check(Money.move(c.state,"coins",c.port("brass_haven"),"governmentPurse",int(c.state.coins),"Declared unaffordable-work fixture",c.state.moneyLog),"Work refusal uses a conserved empty purse")
	before=snapshot();refused=scene.recover_wreck(wreck_id,"gear","",0.0,gear_request)
	check(not refused.ok and snapshot()==before,"Insufficient actual work coins refuse without time, food, arrears or partial extraction")
	branch(prepared);c.find_boat(carrier_uid).needsHarborRepair=true
	before=snapshot();refused=scene.recover_wreck(wreck_id,"gear","",0.0,gear_request)
	check(not refused.ok and snapshot()==before,"An unsupported carrier cannot borrow somebody else's hold")
	branch(prepared);c.find_boat(carrier_uid).supportOnly=true
	before=snapshot()
	var support_quote: Dictionary=c.recovery_quote(wreck_id,"gear","",0.0,gear_request)
	check(support_quote.ok and snapshot()==before and c.capacity()>0,"A legitimate crewed traveling support hull keeps its physical hold and recovery eligibility")
	branch(prepared)
	# Actual Main ownership boundary: normal elapsed time produces one pending day,
	# start_economy takes that day into its real copied-port worker. Even if the
	# worker already finished computing, Main must join it before another publish.
	c.step(c.DAY_SECONDS)
	if not check(c.pending_days==1 and scene.economy_task<0,"Actual elapsed day is pending before Main starts its worker"):return false
	scene.start_economy()
	if not check(scene.economy_task>=0 and c.pending_days==0,"Main owns a real in-flight economy result after taking pending days"):return false
	var held_state: Dictionary=c.state
	var held_ports: Array=c.state.ports
	before=snapshot()
	refused=scene.recover_wreck(wreck_id,"gear","",0.0,gear_request)
	check(not refused.ok and is_same(c.state,held_state) and is_same(c.state.ports,held_ports) and snapshot()==before and scene.economy_task>=0,"In-flight Main ownership refuses gear without joining, swapping ports, payment or transfer")
	scene.sync_economy()
	if not check(scene.economy_task<0 and c.pending_days==0,"Normal Main completion joins its original copied-port owner"):return false
	if not conserved("Normal Main worker completion"):return false
	quote=c.recovery_quote(wreck_id,"gear","",0.0,gear_request)
	if not check(bool(quote.ok),"Gear can retry after normal completion: "+str(quote.message)):return false
	var wreck: Dictionary=Salvage.find_wreck(c.state,wreck_id)
	var stores: Dictionary=wreck.stores.duplicate(true)
	var components: Dictionary=wreck.components.duplicate(true)
	var selected_ids: Array=[]
	var all_ids: Array=[]
	for part in quote.get("selected",[]):
		selected_ids.append(str(part.itemUid));all_ids.append(str(part.itemUid))
		check(same_part(source_parts.get(str(part.itemUid),{}),part),"Quote discloses the selected part's actual condition and origin")
	for part in quote.get("forfeitedItems",[]):all_ids.append(str(part.itemUid))
	all_ids.sort();selected_ids.sort()
	var wanted: Array=gear_request.itemUids.duplicate();wanted.sort()
	check(selected_ids==wanted and all_ids==sorted_keys(source_parts) and quote.get("forfeitedHull",false) and quote.get("forfeitedComponents",{})==components and quote.get("retainedStores",{})==stores,"Before committing, selected/lost parts, hull, all component losses and retained loose stores are explicit")
	var wallet: int=int(c.state.coins)
	var savings: int=int(c.state.crewPurse)
	var cargo: Dictionary=c.state.cargo.duplicate(true)
	var day: float=float(c.state.day)
	var econ_day: int=int(c.state.econDay)
	var carrier: Dictionary=c.find_boat(carrier_uid)
	var birth: String=str(carrier.moduleCondition.birthNamespace)
	var cursor: int=int(carrier.moduleCondition.nextItemSeq)
	var result: Dictionary=scene.recover_wreck(wreck_id,"gear","",0.0,gear_request)
	if not check(bool(result.ok),"Actual Main retries and extracts exact parts after its worker completes: "+str(result.message)):return false
	check(int(quote.get("payrollDays",0))>0 and float(quote.get("workDays",0))>0 and int(quote.get("wages",0))>0 and float(quote.get("food",0))>0,"This selected extraction crosses a real rounded payroll day")
	check(absf(float(c.state.day)-day-float(quote.workDays))<EPS and int(c.state.econDay)==econ_day+int(quote.payrollDays) and c.pending_days==0,"Selected work advances real time and joins the correct normal payroll days")
	check(int(c.state.coins)==wallet-int(quote.coinsRequired) and int(c.state.crewPurse)==savings+int(quote.wages)+int(quote.arrears) and c.state.wageArrears==0,"Actual selected work pays crew from conserved coins, including any arrears")
	check(absf(float(c.state.cargo.food)-(float(cargo.food)-float(quote.food)))<EPS,"Selected work consumes its actual quoted finite provisions")
	check(int(result.get("wagesPaid",-1))==wallet-int(c.state.coins) and absf(float(result.get("foodConsumed",-1))-(float(cargo.food)-float(c.state.cargo.food)))<EPS,"Published actual work receipt agrees with the paid coins and consumed provisions")
	for good in cargo:
		if str(good)!="food":check(c.state.cargo[good]==cargo[good],"Selected physical gear does not also mint commodity "+str(good))
	carrier=c.find_boat(carrier_uid)
	check(str(carrier.moduleCondition.birthNamespace)==birth and int(carrier.moduleCondition.nextItemSeq)==cursor,"Cross-hull transfer mints no replacement part or birth serial")
	for uid in wanted:
		var part: Dictionary=carrier.moduleCondition.items.get(uid,{})
		check(same_part(source_parts.get(uid,{}),part) and str(part.get("location",""))=="locker","Exact selected UID/hp/origin/cause/status survives in the carrier locker: "+str(uid))
	check(absf(Expedition.locker_weight(carrier)-float(quote.lockerWeight))<EPS and float(quote.weight)>0,"Real selected parts retain positive physical carrying weight")
	wreck=Salvage.find_wreck(c.state,wreck_id)
	check(str(wreck.get("equipmentCustody",""))=="retired" and not wreck.has("sourceModuleCondition") and wreck.get("hullStripped",false) and wreck.components.is_empty() and wreck.stores==stores,"Whole original source is retired; hull/components are forfeited and loose stores remain finite")
	var live_registry: Dictionary=Recovery.registry(c.state,"")
	check(live_registry.ok,"Full live equipment registry accepts the completed transfer")
	for uid in source_parts:
		check(live_registry.get("uids",[]).count(uid)==(1 if uid in wanted else 0),"Selected parts have one owner; forfeited parts have no live duplicate: "+str(uid))
	var gate: Dictionary=Preflight.check_state(c.state,c.data)
	check(gate.ok,"Whole-campaign catalog/origin/birth/custody preflight accepts the result: "+str(gate.get("message","")))
	before=snapshot()
	check(not scene.recover_wreck(wreck_id,"gear","",0.0,gear_request).ok and snapshot()==before,"Selected gear cannot be extracted twice")
	check(not scene.recover_wreck(wreck_id,"tow").ok and snapshot()==before,"Forfeited source cannot become a second recovered boat")
	check(not scene.recover_wreck(wreck_id,"strip","timber",0.1).ok and snapshot()==before,"Forfeited structural components cannot be recovered a second time")
	print("salvage058 selected outcome: UIDs=",wanted," weight=",quote.weight," workDays=",quote.workDays," payrollDays=",quote.payrollDays," paid=",quote.coinsRequired," food=",quote.food)
	return conserved("Selected exact gear and duplicate refusals")

func later_cargo_and_restore() -> void:
	if not sail(c.port("brass_haven"),"brass_haven"):return
	var carrier: Dictionary=c.find_boat(carrier_uid)
	var before: String=snapshot()
	var fitting: Dictionary=Refit.install(c.state,c.current_port(),carrier,"weapon:0","stock_primary",{"itemUid":str(gear_request.itemUids[0])})
	check(not fitting.ok and str(fitting.get("message","")).contains("different hull design") and snapshot()==before,"Ordinary paid fitting refuses a foreign factory gun without healing, swapping or charging")
	var mass: float=Expedition.locker_weight(carrier)
	var fill: int=floori(c.capacity()-c.cargo_weight())
	if not check(fill>0 and c.trade("brass_haven","food",fill,"buy").ok,"Later normal paid trade fills only space left after real locker mass"):return
	carrier=c.find_boat(carrier_uid)
	var manifest: Dictionary=c.state.cargoManifest.get(carrier_uid,{})
	check(mass>0 and absf(Expedition.locker_weight(carrier)-mass)<EPS and c.Economy.cargo_weight(manifest)+mass<=float(carrier.spec.cargo)+EPS and c.state.cargoManifest.get("unassigned",{}).is_empty(),"Manifest reserves this physical hull's own locker before ordinary cargo")
	before=snapshot()
	var overfill: Dictionary=c.trade("brass_haven","food",1,"buy")
	check(not overfill.ok and str(overfill.message).contains("hold capacity") and snapshot()==before,"Later extra cargo refuses atomically because recovered parts still weigh something")
	var ids_before: Array=Recovery.registry(c.state,"").get("uids",[]);ids_before.sort()
	var parts_before: Dictionary=carrier.moduleCondition.items.duplicate(true)
	var raw_cargo: Dictionary=c.state.cargo.duplicate(true)
	var raw_wallet: Variant=c.state.coins
	scene.save_game(false)
	var text: String=FileAccess.get_file_as_string(scene.save_directory.path_join("voyage.json"))
	var parsed=JSON.parse_string(text)
	if not check(not text.is_empty() and parsed is Dictionary,"Actual Main writes the isolated selected-gear save"):return
	var parsed_cargo: Dictionary=parsed.cargo.duplicate(true)
	var wallet: Variant=parsed.coins
	check(wallet==raw_wallet and sorted_keys(parsed_cargo)==sorted_keys(raw_cargo),"Actual JSON save keeps exact purse and cargo key set")
	for good in raw_cargo:
		var raw: float=float(raw_cargo[good])
		var serialized: float=float(parsed_cargo.get(good,-1))
		if raw!=serialized:print("salvage058 JSON cargo ",good," raw=%.17f parsed=%.17f delta=%.17f"%[raw,serialized,serialized-raw])
		check(is_finite(serialized) and serialized>=0 and (serialized==raw if floorf(raw)==raw else absf(serialized-raw)<=0.000000000001),"JSON retains integral/zero lots exactly and logs any bounded fractional serialization drift: "+str(good))
	var restored: Dictionary=c.restore(parsed)
	if not check(restored.ok,"Actual Campaign.restore accepts the selected-gear save: "+str(restored.message)):return
	carrier=c.find_boat(carrier_uid)
	check(sorted_keys(carrier.moduleCondition.items)==sorted_keys(parts_before),"Save/restore keeps every physical carrier item UID without replacement")
	for uid in gear_request.itemUids:
		check(same_part(source_parts.get(uid,{}),carrier.moduleCondition.items.get(uid,{})) and str(carrier.moduleCondition.items.get(uid,{}).get("location",""))=="locker","Save/restore keeps selected exact UID, damage and origin: "+str(uid))
	check(c.state.coins==wallet and sorted_keys(c.state.cargo)==sorted_keys(parsed_cargo),"Restore retains exact purse and all parsed cargo keys")
	for good in parsed_cargo:check(c.state.cargo[good]==parsed_cargo[good],"Restore retains the exact parsed cargo quantity: "+str(good))
	var ids_after: Array=Recovery.registry(c.state,"").get("uids",[]);ids_after.sort()
	check(ids_before==ids_after and Preflight.check_state(c.state,c.data).ok,"Restore preserves global live custody and never reseeds the retired NPC's fittings")
	check(absf(Expedition.locker_weight(carrier)-mass)<EPS and c.cargo_weight()<=c.capacity()+EPS,"Physical carrying survives save/restore and later cargo")
	conserved("Final selected-gear save")

func finish() -> void:
	if scene!=null:scene.sync_economy()
	scene.queue_free()
	await process_frame
	check(Time.get_ticks_msec()-started_ms<TOTAL_MS,"Entire single fixture including Main setup and cleanup is below 35 seconds")
	print("salvage058 totalMs=",Time.get_ticks_msec()-started_ms,"; runtime budget target 8% CPU / two cores is Root-owned, not set or measured here")
	print("salvage voyage: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
