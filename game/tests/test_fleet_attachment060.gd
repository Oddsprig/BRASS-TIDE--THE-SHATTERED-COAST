extends SceneTree
## One shared Main/world/nav. Source-only author; Root alone runs native checks.
const B=preload("res://scripts/battle.gd")
const Driver=preload("res://scripts/battle_driver051.gd")
const Identity=preload("res://scripts/fleet_identity.gd")
const Training=preload("res://scripts/crew_training.gd")
const Builds=preload("res://scripts/workshop_builds048.gd")
const Money=preload("res://scripts/money.gd")
const STEP: float=1.0/30.0
const WORK_SECONDS: float=40.0
const CAP_SECONDS: float=45.0
var scene
var c
var began_us: int=0
var phase_us: int=0
var checks: int=0
var failures: int=0
var supply: int=0
var baseline: Dictionary={}
var boat_uids: Array=[]
var enemy_owner_id: String=""
var enemy_uid: String=""
var receipts: Array=[]
var phases: Array=[]

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL fleet attachment060: "+message)

func elapsed() -> float:return float(Time.get_ticks_usec()-began_us)/1000000.0

func phase(name: String) -> void:
	var now: int=Time.get_ticks_usec()
	phases.append({"phase":name,"seconds":float(now-phase_us)/1000000.0})
	print("fleet attachment060 phase ",JSON.stringify(phases[-1]))
	phase_us=now

func budget(name: String) -> bool:
	if elapsed()<WORK_SECONDS:return true
	check(false,"40-second work budget reached before "+name+"; unfinished work is not a pass")
	return false

func gear_uids(boat: Dictionary) -> Array:
	var ids: Array=[]
	for item in boat.get("moduleCondition",{}).get("items",{}).values():ids.append(str(item.itemUid))
	ids.sort()
	return ids

func snapshot() -> String:
	return JSON.stringify({"state":c.state,"pending":c.pending_days,"events":c.events,"economyTask":scene.economy_task})

func button_in(node: Node,caption: String) -> Button:
	if node is Button and str(node.text)==caption:return node
	for child in node.get_children():
		var found: Button=button_in(child,caption)
		if found!=null:return found
	return null

func fork() -> void:
	# Prior drivers have retired; no live owner/task survives a branch boundary.
	c.state=baseline.duplicate(true);c.pending_days=0;c.events=[]

func run() -> void:
	began_us=Time.get_ticks_usec();phase_us=began_us
	scene=load("res://main.tscn").instantiate();root.add_child(scene)
	await process_frame
	scene.set_process(false);scene.set_physics_process(false)
	scene.audio.enabled=false;scene.music.enabled=false
	scene.save_directory=OS.get_user_data_dir().path_join("fleet-attachment060-%d"%began_us)
	c=scene.core
	check(c.new_game(60060).get("ok",false),"one Main campaign publishes on its existing world and navigation")
	scene.mode="campaign";scene.paused=true
	if c.state.is_empty():await finish();return
	supply=Money.total(c.state)
	var p: Dictionary=c.current_port()
	# Explicit finite OPENING stock, not earned progression or free working gear.
	p.shipStock.iron_bastion=2
	for good in ["iron","copper","timber","guns","engines","supplies","fuel","ammo"]:p.stocks[good]=maxf(float(p.stocks.get(good,0)),120.0)
	var opening_quote: Dictionary=c.Harbor.quote(c,c.hull("iron_bastion"),p)
	# Two paid hulls plus two current ready-hull values as the explicitly declared
	# fitting/stores/recovery allowance; qualified crew advances are additional.
	# This is conservative test capital, not a boat price or earned progression.
	var opening_capital: int=4*int(opening_quote.readyPrice)+c.Economy.recruit_cost(p,2*int(c.hull("iron_bastion").crewOptimal))
	check(Money.move(c.port("shatter_spire"),"governmentPurse",c.state,"coins",opening_capital,"Declared finite quote-based opening attachment060 capital",c.state.moneyLog),"opening capital comes from an existing finite treasury")
	print("attachment060 declared opening capital ",opening_capital,"; ready-hull basis ",opening_quote.readyPrice)
	check(Money.total(c.state)==supply,"opening stock fixture mints no coins")
	for index in range(2):
		var before_crew: float=float(p.workforce)
		var purchase_quote: Dictionary=c.Harbor.quote(c,c.hull("iron_bastion"),p)
		print("attachment060 purchase ",JSON.stringify({"index":index,"coinsBefore":c.state.coins,"readyPrice":purchase_quote.readyPrice,"minimumCrewAdvance":c.Economy.recruit_cost(p,int(c.hull("iron_bastion").crewMin)),"workforce":p.workforce,"recruits":p.recruits,"qualifiedSailors":p.training.qualified.sailor}))
		var bought: Dictionary=c.buy_boat("iron_bastion")
		check(bought.get("ok",false),"actual paid Bastion hull and minimum crew purchase %d: %s"%[index,bought.get("message","")])
		if not bought.get("ok",false):await finish();return
		var boat: Dictionary=c.state.fleet[-1]
		boat.name="Cinder Wake" if index==0 else "Bellwater"
		boat_uids.append(str(boat.uid))
		check(float(p.workforce)==before_crew-float(boat.crew),"hull purchase recruits existing people")
		check(c.recruit_crew(boat.uid,int(boat.crewOptimal-boat.crew)-1).ok,"ordinary paid recruitment leaves exactly one professional berth")
		var hired: Dictionary=Identity.hire_specialist(c,boat.uid,"pilot" if index==0 else "gunner")
		check(hired.ok and float(boat.crew)==float(boat.crewOptimal),"paid specialist consumes one actual sailor and equalizes working crew")
		var choice: Dictionary=Builds.examples(c.hull("iron_bastion"))[index]
		var quote: Dictionary=c.workshop_preview(boat.uid,choice.loadout)
		var wallet: int=int(c.state.coins)
		var materials: Dictionary=p.stocks.duplicate(true)
		var fitted: Dictionary=c.workshop_apply(boat.uid,choice.loadout,quote)
		check(fitted.ok and int(c.state.coins)==wallet-int(quote.get("cost",0)),"existing physical workshop charges the actual whole-fit bill")
		for good in quote.get("materials",{}):check(absf(float(p.stocks[good])-(float(materials[good])-float(quote.materials[good])))<0.0001,"paid fit consumes finite "+str(good))
		check(Identity.set_command_preference(c,boat.uid,"cautious" if index==0 else "aggressive",str(choice.role)).ok,"explicit next-battle intent is stored by physical boat UID")
		check(c.resupply_boat(boat.uid).ok,"actual harbor stock supplies ammunition, fuel and repair kits")
		check(Money.total(c.state)==supply and c.Preflight.check_state(c.state,c.data).ok,"acquisition/refit preserves money and unique physical custody")
	# Choose one already-owned canonical NPC Bastion as the identical opponent.
	for owner in c.state.fleetOwners:
		for boat in owner.boats:
			if str(boat.type)=="iron_bastion" and not boat.sunk:enemy_owner_id=str(owner.id);enemy_uid=str(boat.uid);break
		if not enemy_uid.is_empty():break
	check(not enemy_uid.is_empty(),"existing finite NPC roster supplies the same Bastion opponent to every comparison")
	c.apply_morale();c.Manifest.allocate(c.state)
	phase("one Main/world/nav; finite paid hull, staff, fittings and stores")
	if budget("training and pure UI"):training_and_review()
	phase("paid course/cancellation and pending-day pure review")
	if not budget("parsed save"):await finish();return
	var restored: Dictionary=c.restore(JSON.parse_string(JSON.stringify(c.state)))
	check(restored.ok,"actual parsed save restores physical fits, staff purses and saved intent: "+str(restored.get("message","")))
	if not restored.ok or enemy_uid.is_empty():await finish();return
	for index in range(2):
		var view: Dictionary=c.FleetSupport.selected_view(c,str(boat_uids[index]))
		check(view.commandPreference.doctrine==("cautious" if index==0 else "aggressive") and view.commandPreference.role==("skirmisher" if index==0 else "heavy") and view.staff[0].active,"parsed restoration preserves each exact paid staff/intent choice")
	baseline=c.state.duplicate(true)
	var healthy: Array=[]
	var damaged: Array=[]
	for index in range(2):
		if not budget("healthy worker comparison"):break
		fork();healthy.append(await fight(str(boat_uids[index]),false,false))
	for index in range(2):
		if not budget("half-HP doctrine comparison"):break
		fork();damaged.append(await fight(str(boat_uids[index]),true,false))
	if healthy.size()==2:
		check(int(healthy[0].fires)>0 and int(healthy[1].fires)>0,"both paid fitted builds actually fire on autopilot")
		check(float(healthy[0].travel)>2.0 and float(healthy[1].travel)>2.0,"both comparable original hulls actually move in worker combat")
		check(absf(float(healthy[0].travel)-float(healthy[1].travel))>1.0 or healthy[0].phases!=healthy[1].phases,"real motion/role phases distinguish gun-pressure pilot and cannon-anchor gunner")
	else:check(false,"both matched healthy comparisons must finish")
	if damaged.size()==2:
		check(bool(damaged[0].withdrew) and not bool(damaged[1].withdrew),"same half-HP condition produces cautious local withdrawal and aggressive continued fighting")
		check(float(damaged[0].travel)>1.0 and float(damaged[1].travel)>1.0,"doctrine evidence includes actual motion, not only unequal options or specs")
	else:check(false,"both matched damaged comparisons must finish")
	phase("matched actual worker movement, fire and local withdrawal")
	if budget("unpaid premium"):fork();unpaid_transition()
	if budget("named loss and recovery"):
		fork()
		var loss: Dictionary=await fight(str(boat_uids[0]),false,true)
		if loss.get("result")=="lost":loss_and_recovery(loss)
		else:check(false,"controlled physical sinking must reach a real worker loss")
	phase("unpaid transition; named actual loss, history, finite paid recovery")
	await finish()

func training_and_review() -> void:
	var p: Dictionary=c.current_port()
	var q: Dictionary=Training.quote(p.duplicate(true),1,"sailor")
	var workers: int=int(p.workforce)
	var materials: Dictionary=p.stocks.duplicate(true)
	var enrolled: Dictionary=c.TrainingOps.enroll(c,1,"sailor")
	check(enrolled.ok,"real local people/material/coin eligibility commissions a course")
	if enrolled.ok:
		check(int(p.workforce)==workers-int(q.reservedWorkers) and int(q.reservedWorkers)==2,"one trainee and one instructor are reserved existing people")
		var cancelled: Dictionary=c.TrainingOps.cancel(c,str(enrolled.id))
		check(cancelled.ok and int(cancelled.refund)==int(q.traineeWages)+int(q.instructorWages),"immediate cancellation returns only actual unspent wage escrow")
		check(int(p.workforce)==workers and not c.TrainingOps.cancel(c,str(enrolled.id)).ok,"reserved people return once; duplicate cancellation refuses")
		check(float(p.stocks.food)<float(materials.food) and float(p.stocks.supplies)<float(materials.supplies) and Money.total(c.state)==supply,"cancellation retains spent materials and conserves all purses")
	c.wait_day()
	check(c.pending_days>0,"actual calendar wait leaves payroll pending before pure reviews")
	var before: String=snapshot()
	var selected: Dictionary=c.FleetSupport.selected_view(c,str(boat_uids[0]))
	check(selected.ok and selected.staff.size()==1 and selected.payroll.basePerSailorDay==100,"selected view describes the actual paid named sailor and base wage")
	selected.staff[0].name="Detached edit"
	check(snapshot()==before,"editing a detached staff view does not rename live people or settle payroll")
	scene.ui.IdentityUI.open(scene.ui,str(boat_uids[0]))
	var header: Button=button_in(scene.ui.overlay,String.chr(215))
	check(header!=null,"selected-boat review has the normal header close")
	if header!=null:header.pressed.emit()
	check(snapshot()==before,"selected-boat review and actual header-X leave state and pending payroll unchanged")
	scene.ui.IdentityUI.conversions(scene.ui,str(boat_uids[0]))
	var decline: Button=button_in(scene.ui.overlay,"Back to boat")
	if decline!=null:decline.pressed.emit()
	check(decline!=null and snapshot()==before,"conversion review decline does not pay, hire, install or join economy")
	scene.ui.EconomicUI.open(scene.ui)
	decline=button_in(scene.ui.overlay,"Close review")
	if decline!=null:decline.pressed.emit()
	check(decline!=null and snapshot()==before,"training review dismissal does not normalize live accounts or commission work")
	scene.ui.EconomicUI.open(scene.ui)
	header=button_in(scene.ui.overlay,String.chr(215))
	if header!=null:header.pressed.emit()
	check(header!=null and snapshot()==before,"training review header-X also leaves payroll pending")
	scene.sync_economy()
	check(c.pending_days==0 and Money.total(c.state)==supply,"explicit account synchronization settles real full base payroll and premiums with conserved money")
	for uid in boat_uids:
		var view: Dictionary=c.FleetSupport.selected_view(c,str(uid))
		check(view.staff[0].active and int(view.staff[0].coins)==int(view.staff[0].premiumPerDay),"actual paid day credits each named premium purse exactly once")

func fight(uid: String,damaged: bool,loss: bool) -> Dictionary:
	var boat: Dictionary=c.find_boat(uid)
	var enemy: Dictionary={}
	for candidate in c.fleet_owner(enemy_owner_id).boats:
		if str(candidate.uid)==enemy_uid:enemy=candidate;break
	if damaged:boat.hp=float(boat.maxHp)*0.50
	if loss:
		# Controlled opening damage; the worker must actually integrate inflow/sink.
		boat.water=float(boat.capacity)-0.01;boat.breaches=[{"area":100.0,"section":"waterline"}]
	var original: Dictionary=boat
	var gear: Array=gear_uids(boat)
	var ammo: float=float(boat.ammo)
	var fuel: float=float(boat.fuel)
	var st: Dictionary=B.create({"fleet":[boat],"enemyFleet":[enemy],"islands":[],"seed":60601})
	st.autoBoard=false
	var options: Dictionary=st.tactical.options.byId[str(st.playerId)]
	var preference: Dictionary=Identity.command_preference(boat)
	check(options.doctrine==preference.doctrine and options.role==preference.role,"fresh actual tactical registration seeds the saved physical-boat intent")
	for ship in st.ships:
		ship.x=600.0 if ship.team=="player" else 1000.0;ship.y=850.0
		ship.angle=0.0 if ship.team=="player" else PI;ship.turretAngle=ship.angle
		st.tactical.home[str(ship.id)]={"x":380.0 if ship.team=="player" else 1220.0,"y":850.0}
	var start: Dictionary=boat.get("_serviceStart060",{}).duplicate(true)
	check(not start.is_empty(),"actual deployment captures the source participant before worker transfer")
	var driver=Driver.new(st)
	var view: Dictionary=driver.advance(0.0,{},true)
	var fires: int=0
	var phases_seen: Array=[]
	var samples: Array=[]
	var withdrew: bool=false
	var target: int=90 if not damaged and not loss else 45
	while int(driver.telemetry().completedSteps)<target and view.get("result")==null and elapsed()<WORK_SECONDS:
		var wanted: int=mini(target,int(driver.telemetry().completedSteps)+4)
		view=driver.advance(float(wanted-int(driver.telemetry().completedSteps))*STEP,{},false)
		while driver.telemetry().inFlight and elapsed()<WORK_SECONDS:
			await process_frame
			view=driver.advance(0.0,{},true)
		for event in driver.take_events():
			if str(event.get("kind",""))=="fire" and str(event.get("sourceId",""))==str(view.playerId):fires+=1
		var intent: Dictionary=view.get("tactical",{}).get("intents",{}).get(str(view.playerId),{})
		var phase_name: String=str(intent.get("phase",""))
		if not phase_name.is_empty() and not phases_seen.has(phase_name):phases_seen.append(phase_name)
		if phase_name in ["breakaway","regroup"] and ("danger" in str(intent.get("reason","")).to_lower() or "protection" in str(intent.get("reason","")).to_lower()):withdrew=true
		if samples.size()<12 and not view.ships.is_empty():samples.append({"time":view.time,"x":view.ships[0].x,"y":view.ships[0].y,"phase":phase_name,"reason":intent.get("reason","")})
	# Only poll/await completed work; the public retirement joins teardown children.
	while driver.telemetry().inFlight and elapsed()<CAP_SECONDS-2.0:
		await process_frame
		view=driver.advance(0.0,{},true)
	check(not driver.telemetry().inFlight,"authoritative work completes before public retirement")
	var final: Dictionary=driver.retire()
	var telemetry: Dictionary=driver.telemetry()
	check(telemetry.retired and not telemetry.inFlight and int(telemetry.workerThreadId)>0 and int(telemetry.workerThreadId)!=OS.get_thread_caller_id(),"public retirement joins actual 30Hz worker ownership")
	check(is_same(c.find_boat(uid),original) and is_same(final.ships[0],original),"retirement restores the exact original physical campaign owner")
	check(original.get("_serviceStart060",{})==start,"deployment participant snapshot survives the actual worker and original-owner retirement")
	check(gear_uids(original)==gear and float(original.ammo)<=ammo and float(original.fuel)<=fuel,"actual combat preserves item UID custody and consumes only carried stores")
	var travel: float=Vector2(float(original.x)-600.0,float(original.y)-850.0).length()
	var receipt: Dictionary={"uid":uid,"name":original.name,"damaged":damaged,"controlledLoss":loss,"travel":travel,"fires":fires,"ammoUsed":ammo-float(original.ammo),"fuelUsed":fuel-float(original.fuel),"gearUids":gear,"phases":phases_seen,"withdrew":withdrew,"samples":samples,"telemetry":telemetry,"result":final.get("result"),"battle":final}
	if not loss:check(int(telemetry.completedSteps)>=target and (fires==0 or float(receipt.ammoUsed)>0.0),"bounded live comparison finishes requested real steps with paid ammunition")
	var detached: Dictionary=receipt.duplicate();detached.erase("battle");receipts.append(detached)
	return receipt

func unpaid_transition() -> void:
	var p: Dictionary=c.current_port()
	var held: int=int(c.state.coins)
	check(Money.move(c.state,"coins",p,"governmentPurse",held,"Finite fixture reserve held ashore during premium shortfall",c.state.moneyLog),"unpaid transition moves rather than erases the captain's coins")
	Identity.tick(c,1.0)
	var view: Dictionary=c.FleetSupport.selected_view(c,str(boat_uids[0]))
	check(not view.staff[0].active and int(view.staff[0].arrears)==25 and view.staff[0].effects.is_empty(),"unpaid real pilot premium disables its effect and remains a separate arrears account")
	check(Money.total(c.state)==supply,"unpaid premium conserves every coin")
	check(Money.move(p,"governmentPurse",c.state,"coins",held,"Same finite reserve returned for professional arrears",c.state.moneyLog),"recovery uses the same held coins")
	Identity.tick(c,1.0)
	view=c.FleetSupport.selected_view(c,str(boat_uids[0]))
	check(view.staff[0].active and int(view.staff[0].arrears)==0 and Money.total(c.state)==supply,"real payment clears premium arrears and restores only the paid benefit")

func loss_and_recovery(loss: Dictionary) -> void:
	var final: Dictionary=loss.battle
	var lost_uid: String=str(loss.uid)
	var named_staff: String=str(c.FleetSupport.aboard(c,lost_uid)[0].name)
	var report: Dictionary=c.battle_settled(str(final.result),[],{"objectiveOnly":true},final)
	check(report.get("participants",[]).size()==1 and report.get("losses",[]).size()==1,"only the actual sunk participant earns service; idle boats receive none")
	if report.get("losses",[]).is_empty():return
	var entry: Dictionary=report.losses[0]
	check(str(entry.uid)==lost_uid and str(entry.name)==str(loss.name) and str(entry.fate)=="sunk" and int(entry.service.get("battles",0))==1,"after-action loss names the original UID and earned battle history")
	check(c.find_boat(lost_uid).is_empty() and c.find_boat(str(boat_uids[1])).get("service",{}).get("battles",0)==0,"sunk hull leaves living fleet while undeployed peer gets no battle credit")
	check(c.state.specialists.any(func(r):return str(r.name)==named_staff and r.get("lost",false) and not r.active),"named lost specialist is reconciled without reviving a person or benefit")
	var before: String=JSON.stringify(c.state)
	check(c.battle_settled(str(final.result),[],{"objectiveOnly":true},final)==report and JSON.stringify(c.state)==before,"same physical settlement cannot duplicate service, loot, losses or wrecks")
	var wreck: Dictionary={}
	for row in c.state.wrecks:
		if str(row.uid)==lost_uid:wreck=row;break
	check(not wreck.is_empty() and wreck.service==entry.service and wreck.serviceHistory==entry.serviceHistory,"named wreck keeps detached earned service and loss detail")
	if wreck.is_empty() or not budget("paid tow"):return
	var wreck_id: String=str(wreck.id)
	var item_ids: Array=loss.gearUids.duplicate()
	var saved: Dictionary=c.restore(JSON.parse_string(JSON.stringify(c.state)))
	check(saved.ok,"named loss, staff estate and wreck attachment survive parsed save validation: "+str(saved.get("message","")))
	if not saved.ok:return
	var quote: Dictionary=c.recovery_quote(wreck_id,"tow")
	var coins: int=int(c.state.coins)
	var towed: Dictionary=c.recover_wreck(wreck_id,"tow")
	check(towed.get("ok",false),"existing finite paid tow recovers the marked hull: "+str(towed.get("message","")))
	if not towed.get("ok",false):return
	check(int(c.state.coins)==coins-int(quote.get("total",0)) and int(quote.get("total",0))>0,"recovery pays the exact quoted tug labor, inspection and company fees")
	var boat: Dictionary=c.find_boat(str(towed.boatUid))
	check(not str(boat.uid)==lost_uid and str(boat.salvageWreckId)==wreck_id and str(boat.name)==str(loss.name),"existing new recovery UID links back to the named original wreck")
	check(boat.service==entry.service and boat.serviceHistory.size()>=entry.serviceHistory.size(),"paid recovery carries useful earned history forward")
	check(float(boat.crew)==0.0 and float(boat.ammo)==0.0 and float(boat.fuel)==0.0 and float(boat.supplies)==0.0 and boat.needsHarborRepair and float(boat.hp)<float(boat.maxHp),"tow remains damaged and empty; real recruitment, repairs and stores are still due")
	if not item_ids.is_empty():check(gear_uids(boat)==item_ids,"recovery transfers the same finite equipment item UIDs")
	scene.sync_economy()
	check(Money.total(c.state)==supply and c.Preflight.check_state(c.state,c.data).ok,"recovery time wages/provisions and physical custody reconcile through normal economy")
	var copy: Dictionary=boat.service.duplicate(true);boat.service.battles+=1
	check(entry.service==copy,"returned report service is detached from recovered living hull")
	boat.service=copy
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"recovered damaged hull/history and lost specialist state reload honestly")

func finish() -> void:
	if scene!=null:scene.queue_free();await process_frame
	var whole: float=elapsed()
	check(whole<CAP_SECONDS,"entire native fixture setup/work/cleanup stays below45s; actual="+str(whole))
	var artifact: Dictionary={"sourceOnlyAuthor":"C; Root alone executes/accepts","seed":60060,"checks":checks,"failures":failures,"wholeSeconds":whole,"phases":phases,"fights":receipts,"limits":"Declared finite opening stock/capital; bounded worker behavior and paid attachment/history only. No full progression, UI art, motion review or strict051 performance acceptance."}
	var file=FileAccess.open(OS.get_user_data_dir().path_join("fleet-attachment060-report.json"),FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(artifact,"  "))
	print("fleet attachment060: %d checks, %d failures, %.3fs"%[checks,failures,whole])
	quit(0 if failures==0 else 1)
