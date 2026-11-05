extends "res://tests/test_voyage_career070.gd"
## SOURCE ONLY / UNPLAYED. Reuse070's actual economy, sailing and disk APIs.
## One ordinary career; absence of a funded opportunity is ROUTE_GAP, never
## a pass. A quiet earned passage is valid; any interception requires real exits.
## No money/stocks/positions/clock/actors/results are supplied to it.
## Explicit alternate accounting branches run in separate restored careers.
## Default: earned only. --escort096-resume-r4 continues the real active prefix;
## --escort096-staged-r4 runs detached guards only, never earned progress.
const Main096=preload("res://scripts/main.gd")
const Traffic096=preload("res://scripts/naval_ui.gd")
const Reserves096=preload("res://scripts/harbor_reserves.gd")
const LIMIT096_MS: int=34000
const PREFIX096_PATH: String="C:/Users/bligh/Documents/Codex/.runtime/game-test-bridge/jobs/3932ad627b584db19e0294a200a2e7f7/attempt-001/earned-escort096/career070-escort096-active.json"
const PREFIX096_SHA256: String="cfd14f6da9f9ce880be9f8ddd3c687723e0d739a62752cf6faa8e7f1da3adc3a"
const PREFIX096_SOURCE: String="dcc5f72fb02864e125806e7c1c7716dad2ed333e"
const PREFIX096_CONTRACT_SOURCE: Dictionary={
	"escort_ops.gd":"f4a8eba935b3ca815932f4bc50b2e5e62441a4d3cc878a1e0f08a8dc9bfb79dc",
	"voyage_jobs.gd":"e138cad136b0702cf6026c5846a4d9a6dd1408469daeee13afb36c74b744308b",
	"naval_ui.gd":"41e8fa422a19e4dffb5ecfd4b4ed7001e35ce3b56d884515a083cdfa8ef108b6",
	"campaign_state_validation.gd":"509949f0bee91bfd3cc82bbf848494d6631e7a69a9e392796f3ee7d74976ecf1"}
var main096
var owner096: String=""
var job096: String=""
var finished096: bool=false
var battles096: int=0

func check(value: bool,message: String) -> bool:
	# Root's fatal scanner may stop on the inherited FAIL line. Persist the
	# actual live context first, without depending on cleanup or a terminal receipt.
	if not value and c!=null and not c.state.is_empty() and not finished096:retain_gap096(message)
	return super.check(value,message)

func retain_gap096(message: String) -> void:
	# Diagnostic only. Read every real trader, including distant/unloaded ones;
	# these records never select a contact or grant remote player access.
	var context: Dictionary={"label":"ACTUAL_GAP_CONTEXT_ONLY_NOT_EARNED","status":receipt.status,"message":message,"elapsedMs":Time.get_ticks_msec()-started,"seed":c.state.seed,"day":c.state.day,"position":c.state.position.duplicate(true),"world064":c.state.get("world064",{}).duplicate(true),"destination":c.state.get("destination",""),"pathPoints":c.state.get("path",[]).size(),"pursuedOwner":owner096,"jobId":job096,"coins":c.state.coins,"wageArrears":c.state.wageArrears,"coinSupply":supply,"totalCoins":c.Money.total(c.state),"travelLock":c.travel_lock064,"events":c.events.duplicate(true),"observations":c.NavalAI.sightings(c.state),"traders":[]}
	var escorts: Array=c.FleetSupport.combat(c)
	for client in c.state.fleetOwners:
		if client.get("kind","")!="trader":continue
		var id: String=str(client.id)
		var p: Dictionary=c.NavalAI._find_patrol(c.state,id)
		var home: Dictionary=c.port(str(client.get("homePort","")))
		var target: Dictionary=c.port(str(p.get("to","")))
		var good: String=str(client.get("tradeGood",""))
		var qty: float=float(client.get("tradeCargo",0))
		var loaded: Dictionary=c.EscortOps._load_plan(c,client)
		# Performance normalizes its argument: use a detached owner so this
		# diagnostic cannot mutate the actual purse, hulls, stores or route.
		var speed: float=float(c.NavalAI.fleet_performance(client.duplicate(true)).speed)*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0))
		var remaining: float=maxf(0,float(p.get("courseLength",0))*(1.0-float(p.get("progress",0))))
		var fee: int=c.VoyageJobs._route_reward(c,remaining/maxf(1.0,speed)/float(c.DAY_SECONDS),"",false,home) if not home.is_empty() else 0
		var wages: float=float(c.Fleets.upkeep(client).wages)
		var event: String="escort:%s:%d"%[id,int(p.get("voyageSeq",0))]
		var range_to_client: float=c.distance(c.state.position,p) if p.has("x") and p.has("y") else -1.0
		var gates: Dictionary={"homeChart":c.home_local064(),"travelUnlocked":c.travel_lock064.is_empty(),"noPendingEncounter":not c.events.any(func(e):return str(e.get("kind","")) in ["encounter","ocean_encounter066","defeat"]),"activeClient":client.get("active",false),"activePatrol":p.get("active",false),"visiblePatrol":not p.get("hidden",false),"sailingPatrol":not p.get("holding",false),"independentClient":not client.get("playerCompany",false),"peacefulClient":not c.Politics.hostile(c,client),"coastalOwner":not c.NavalAI.NavalOrders.enrolled066(c.state,id),"within600":range_to_client>=0 and range_to_client<=c.EscortOps.CONTRACT_RADIUS,"waterCourse":not p.get("course",[]).is_empty(),"deliveryRoute":not p.has("interceptPoint"),"namedAwayHarbor":not target.is_empty() and not home.is_empty() and target.get("id")==p.get("to") and target.get("id")!=home.get("id"),"actualTradeLoad":c.Goods.ITEMS.has(good) and qty>0 and float(client.get("cargo",{}).get(good,0))+0.000001>=qty,"physicalHoldFit":loaded.get("ok",false),"playerCombatBoat":not escorts.is_empty(),"allClientBoatsCrewed":not client.boats.any(func(b):return b.get("sunk",false) or b.get("captureSecured",false) or float(b.crew)<float(b.crewMin)),"deploymentFits":c.Deployment.total(client.boats+escorts)<=c.Deployment.LIMIT,"remainingLeg160":remaining>=160.0,"clientCanFundFeeAndWages":int(client.get("coins",0))>=fee+int(wages),"uncreditedPassage":not c.state.get("escortEvents",{}).has(event) and not c.VoyageJobs._is_closed(c.state,event)}
		var rejected: Array=[]
		for gate in gates:
			if not gates[gate]:rejected.append(gate)
		var patrol: Dictionary={}
		for key in ["from","to","x","y","progress","courseLength","active","holding","hidden","voyageSeq","routeFailure"]:patrol[key]=p.get(key)
		var market: Dictionary={}
		if not home.is_empty() and c.Goods.ITEMS.has(good):market={"stock":home.get("stocks",{}).get(good,0),"exportable":Reserves096.exportable(home,good) if home.get("reserves") is Dictionary else home.get("stocks",{}).get(good,0),"buyPrice":c.Economy.price(home,good,"buy"),"cargoWeight":c.Economy.cargo_weight(client.cargo),"holdCapacity":c.Fleets._capacity(client),"budgetAboveThreeWageDays":maxf(0,int(client.coins)-ceilf(wages*3.0))}
		context.traders.append({"ownerId":id,"homePort":client.get("homePort",""),"tradeCargo":qty,"tradeGood":good,"actualTradeGoodAboard":client.get("cargo",{}).get(good,0),"coins":client.get("coins",0),"crewPurse":client.get("crewPurse",0),"wageArrears":client.get("wageArrears",0),"atPort":client.get("atPort",""),"purpose":client.get("purpose",""),"reason":client.get("reason",""),"patrol":patrol,"distance":range_to_client,"remainingRoute":remaining,"requiredFee":fee,"dailyWages":wages,"loadedCarrierUids":loaded.get("carrierUids",[]),"loadError":loaded.get("message",""),"falseOfferGates":rejected,"homeLoadingInputs":market})
	receipt.failureContext=context
	var path: String=OS.get_environment("GAME_TEST_ARTIFACTS").path_join("escort096-gap.json")
	var file=FileAccess.open(path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(context,"\t"));file.close()
	print("ESCORT096_GAP_CONTEXT ",JSON.stringify(context))

func bounded() -> bool:
	if not finished096 and Time.get_ticks_msec()-started<30500:return true
	receipt.status="BODY_TIMEOUT"
	return check(false,"096 stops work at30.5s for cleanup inside34s; no retry or substituted outcome")

func gap096(code: String,message: String) -> bool:
	receipt.status="ROUTE_GAP";receipt.gap={"code":code,"message":message,"day":c.state.day,"position":c.state.position.duplicate(true)}
	return check(false,message)

func advance(seconds: float) -> bool:
	if not bounded():return false
	var before: float=float(c.state.day)
	c.step(seconds)
	if not settle_days():return false
	for event in c.pop_events():
		if str(event.get("kind","")) in ["encounter","ocean_encounter066","defeat"]:
			return gap096("ACTUAL_INTERRUPTION","Actual encounter/loss interrupts this ordinary route: "+str(event))
	return check(float(c.state.day)>before and c.Money.total(c.state)==supply and int(c.state.wageArrears)==0,"Actual accepted time, normal payroll and every real purse remain reconciled")

func current096(id: String="",seeking: bool=false) -> Dictionary:
	var nearest: Dictionary={};var distance: float=INF
	for seen in c.NavalAI.observe(c.state):
		if not Traffic096.can_hail(c.state,seen) or (not id.is_empty() and str(seen.ownerId)!=id):continue
		var owner: Dictionary=c.fleet_owner(str(seen.ownerId))
		if owner.get("kind","")!="trader" or c.Politics.hostile(c,owner) or float(owner.get("tradeCargo",0))<=0:continue
		if seeking:
			var p: Dictionary=c.NavalAI._find_patrol(c.state,str(seen.ownerId))
			if owner.get("playerCompany",false) or c.NavalAI.NavalOrders.enrolled066(c.state,str(seen.ownerId)) or p.get("holding",false) or p.has("interceptPoint") or p.get("course",[]).is_empty() or str(p.get("to",""))==str(owner.get("homePort","")) or float(p.get("courseLength",0))*(1.0-float(p.get("progress",0)))<160.0:continue
		var d: float=c.distance(c.state.position,seen)
		if d<distance:nearest=seen;distance=d
	return nearest

func seek096() -> Dictionary:
	var began: float=float(c.state.day)
	var last_plan: float=-INF
	var destination: Dictionary=c.port("kelp_reach")
	var route: Dictionary=c.chart_course({"x":destination.x,"y":destination.y},str(destination.id))
	if not check(route.get("ok",false),"Ordinary exploration course to Kelp Reach, the known fishery source of loaded coastal traffic"):return {}
	for _piece in range(360):
		if not bounded():return {}
		var seen: Dictionary=current096(owner096,true)
		if seen.is_empty() and not owner096.is_empty():seen=current096("",true)
		if not seen.is_empty():
			owner096=str(seen.ownerId)
			var offer: Dictionary=c.EscortOps.offer(c,owner096)
			if not offer.is_empty():c.stop_sailing();return offer
			if float(c.state.day)*45.0-last_plan>=2.0:
				route=c.chart_course({"x":seen.x,"y":seen.y})
				if not check(route.get("ok",false),"Real water course to the current peaceful loaded sighting"):return {}
				last_plan=float(c.state.day)*45.0
		if (float(c.state.day)-began)*45.0>=180.0 or not advance(0.5):return {}
	return {}

func button096(node: Node,prefix: String) -> Button:
	if node is Button and str(node.text).begins_with(prefix):return node
	for child in node.get_children():
		var found: Button=button096(child,prefix)
		if found!=null:return found
	return null

func accept096(offer: Dictionary) -> bool:
	var client: Dictionary=c.fleet_owner(owner096)
	var purse: int=int(client.coins);var coins: int=int(c.state.coins)
	var seen: Dictionary=current096(owner096)
	if not check(not seen.is_empty(),"Ordinary current contact exists before hailing"):return false
	Traffic096.hail(main096.ui,seen)
	var button: Button=button096(main096.ui.overlay,"Accept funded escort (")
	if not check(main096.ui.modal_kind=="escort_review" and button!=null,"Actual player hail exposes the paid offer/review button"):return false
	button.pressed.emit()
	var job: Dictionary=c.EscortOps.contracted(c,owner096)
	if not check(not job.is_empty(),"Actual visible Accept button creates the funded contract"):return false
	job096=str(job.id);main096.ui.close_modal()
	receipt.acceptance={"job":job.duplicate(true),"clientPurseBefore":purse,"clientPurseAfter":client.coins,"playerBefore":coins,"playerAfter":c.state.coins}
	if not check(int(job.escrow)==int(offer.reward) and int(client.coins)==purse-int(job.escrow) and int(c.state.coins)==coins and c.Money.total(c.state)==supply,"Only the real client's existing purse funds escrow; acceptance pays nothing"):return false
	if not check(not c.VoyageJobs.accept_escort(c,owner096,int(job.reward)).ok and not c.VoyageJobs.finish(c,job096).ok and int(c.state.coins)==coins,"Duplicate acceptance and payment at the rendezvous are refused"):return false
	var detached: Dictionary=c.VoyageJobs._sanitize_job(job)
	detached.escort.carrierUids.clear();detached.escort.carrierCargo.clear()
	if not check(not c.EscortOps.contracted(c,owner096).escort.carrierUids.is_empty(),"Detached job projections cannot mutate the live carrier binding"):return false
	var active: Dictionary=parsed_save("escort096-active")
	return not active.is_empty() and restore_exact(active,"escort096-active")

func resume_actual096() -> Dictionary:
	# This is an actual ordinary new_game/UI acceptance prefix, not070's
	# historical synthetic checkpoint mode. Never accept another file/hash.
	for script in PREFIX096_CONTRACT_SOURCE:
		if not check(FileAccess.get_file_as_string("res://scripts/"+script).replace("\r\n","\n").sha256_text()==PREFIX096_CONTRACT_SOURCE[script],"R4 escort contract source binding: "+script):return {}
	if not check(FileAccess.get_sha256(PREFIX096_PATH)==PREFIX096_SHA256,"Exact R4 actual earned-prefix disk SHA256; no substituted save"):return {}
	var active=JSON.parse_string(FileAccess.get_file_as_string(PREFIX096_PATH))
	if not check(active is Dictionary,"Actual R4 active prefix decodes"):return {}
	supply=int(active.coinSupply)
	if not restore_exact(active,"escort096-r4-actual-prefix"):return {}
	var job: Dictionary=c.EscortOps.contracted(c)
	if not check(int(c.state.seed)==69069 and int(c.state.coins)==15000 and c.crew_count()==5 and int(c.state.wageArrears)==0 and c.Money.total(c.state)==supply and str(job.get("id",""))=="escort:patrol-1:1" and job.state=="active" and int(job.escrow)==1170 and float(job.escort.accompaniedDistance)==0.0 and not job.escort.battlePending,"R4 normal opening, actual funded client and untraveled active contract survive public restore"):return {}
	owner096=str(job.ownerId);job096=str(job.id)
	receipt.prefixContractSourceSha256=PREFIX096_CONTRACT_SOURCE.duplicate()
	receipt.actualPrefix={"path":PREFIX096_PATH,"sha256":PREFIX096_SHA256,"sourceCommit":PREFIX096_SOURCE,"nativeJobId":"3932ad627b584db19e0294a200a2e7f7","contractId":job096,"bytes":FileAccess.get_file_as_bytes(PREFIX096_PATH).size(),"day":c.state.day,"coins":c.state.coins,"escrow":job.escrow,"runningFixtureSha256":FileAccess.get_sha256("res://tests/test_escort096.gd"),"lineage":"ACTUAL_NORMAL_NEW_GAME_UI_ACCEPTANCE; R4_BODY_TIMEOUT_NOT_A_COMPLETED_VOYAGE","priorFailedRunChecksCredited":0}
	return active

func staged_only096(active: Dictionary) -> bool:
	# c is a separate Campaign restored from the exact real prefix, with no
	# Main/earned career. Preserve every old guard, outside the passage body.
	if not save_guards096(active) or not staged096(active):return false
	if not bounded():return false
	# Reconstruct only the detached pre-acceptance test book for the existing
	# legacy/partial-load regressions: reverse the held transfer, never add
	# coins, change a route/clock, close a voyage or supply a gameplay outcome.
	var input: PackedByteArray=var_to_bytes(active)
	var job: Dictionary=c.EscortOps.contracted(c,owner096)
	var client: Dictionary=c.fleet_owner(owner096)
	var fee: int=int(job.escrow)
	if not check(c.Money.move(job,"escrow",client,"coins",fee,"STAGED acceptance rollback only",c.state.moneyLog),"STAGED prior escrow returns only to its original payer for detached offer regression setup"):return false
	c.state.voyageJobs.erase(job)
	if not check(c.Money.total(c.state)==supply and var_to_bytes(active)==input,"STAGED acceptance rollback conserves coins and leaves the actual prefix input unchanged"):return false
	receipt.controlled.append({"label":"STAGED_SETUP_ONLY","case":"reverse_escrow_for_legacy_and_partial_load","heldCoinsReturned":fee,"earnedProgress":false})
	if not legacy_save096() or not staged_partial_load096():return false
	receipt.stagedGuardsComplete=true;receipt.status="STAGED_COMPLETED"
	return true

func legacy_save096() -> bool:
	# STAGED SAVE GUARD ONLY: omit the optional book BEFORE any work is
	# accepted, never remove held coins from the earned career.
	if not bounded():return false
	var legacy: Dictionary=c.state.duplicate(true);legacy.erase("voyageJobs")
	var input: PackedByteArray=var_to_bytes(legacy);var live: PackedByteArray=protected_state()
	var staged=Campaign.new(c.data,c.nav)
	var result: Dictionary=staged.restore(legacy)
	if not check(result.get("ok",false) and same_values(physical(c.state),physical(staged.state)) and staged.Money.total(staged.state)==supply and var_to_bytes(legacy)==input and protected_state()==live,"STAGED legacy book without escort jobs restores unchanged, with no ledger or live-state mutation"):return false
	receipt.controlled.append({"label":"STAGED_SAVE_GUARD_ONLY","case":"legacy_optional_job_book","restored":true})
	return true

func staged_partial_load096() -> bool:
	# STAGED SAVE GUARD ONLY: reuse the actual two-boat rendezvous client in
	# a separate career. Return surplus cargo to stock; never clone a boat.
	if not bounded():return false
	var live: PackedByteArray=protected_state()
	var staged=Campaign.new(c.data,c.nav)
	if not check(staged.restore(c.state.duplicate(true)).get("ok",false),"STAGED partial-load career restores the real pre-acceptance state"):return false
	var client: Dictionary=staged.fleet_owner(owner096)
	if not check(client.get("boats",[]).size()==2,"STAGED partial-load case uses two existing client boats"):return false
	var boats: Array=client.boats.duplicate()
	boats.sort_custom(func(a,b):return str(a.uid)<str(b.uid))
	var original_boats: PackedByteArray=var_to_bytes(client.boats)
	var free: float=maxf(0.0,float(boats[0].spec.get("cargo",0))-staged.Expedition.store_overflow(boats[0]))
	var weight: float=0.0
	for good in client.cargo:weight+=float(client.cargo[good])*float(staged.Goods.ITEMS[good].weight)
	if not check(weight>0 and free>0 and float(client.tradeCargo)>0,"STAGED real client has cargo and a working first hold"):return false
	var scale: float=minf(1.0,free*0.5/weight)
	var home: Dictionary=staged.port(str(client.homePort))
	var conserved: bool=true
	for good in client.cargo:
		var before: float=float(client.cargo[good])+float(home.stocks.get(good,0))
		var kept: float=float(client.cargo[good])*scale
		home.stocks[good]=float(home.stocks.get(good,0))+float(client.cargo[good])-kept
		client.cargo[good]=kept
		conserved=conserved and absf(float(client.cargo[good])+float(home.stocks[good])-before)<0.000001
	client.tradeCargo=float(client.tradeCargo)*scale
	var loaded: Dictionary=staged.EscortOps._load_plan(staged,client)
	if not check(conserved and loaded.get("ok",false) and loaded.carrierUids==[str(boats[0].uid)] and loaded.carrierCargo.size()==2 and loaded.carrierCargo[str(boats[1].uid)].is_empty(),"STAGED unchanged load planner retains two holds with exactly one loaded carrier; goods conserved"):return false
	var offer: Dictionary=staged.EscortOps.offer(staged,owner096)
	if not check(not offer.is_empty() and offer.escort.carrierUids==loaded.carrierUids and offer.escort.carrierCargo.size()==1 and same_values(offer.escort.carrierCargo[str(boats[0].uid)],loaded.carrierCargo[str(boats[0].uid)]),"STAGED contract snapshots only the exact loaded carrier and its actual cargo"):return false
	var purse: int=int(client.coins);var coins: int=int(staged.state.coins)
	var accepted: Dictionary=staged.VoyageJobs.accept_escort(staged,owner096,int(offer.reward))
	var job: Dictionary=staged.EscortOps.contracted(staged,owner096)
	if not check(accepted.get("ok",false) and int(job.escrow)==int(offer.reward) and int(client.coins)==purse-int(job.escrow) and int(staged.state.coins)==coins and staged.Money.total(staged.state)==supply and var_to_bytes(client.boats)==original_boats,"STAGED active one-load contract is client-funded, conserves coins and keeps both original boats"):return false
	var path: String=OS.get_environment("GAME_TEST_ARTIFACTS").path_join("escort096-staged-partial-active.json")
	var file=FileAccess.open(path,FileAccess.WRITE)
	if not check(file!=null,"STAGED partial-load active save opens"):return false
	file.store_string(JSON.stringify(staged.state));file.close()
	var saved=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not check(saved is Dictionary and staged.SaveValidation.job_error070(saved,staged.data).is_empty(),"STAGED two-boat one-load active disk save passes the strict raw job gate"):return false
	var input: PackedByteArray=var_to_bytes(saved);var expected: Dictionary=physical(saved)
	var result: Dictionary=staged.restore(saved)
	if not check(result.get("ok",false) and same_values(expected,physical(staged.state)) and var_to_bytes(saved)==input and staged.Money.total(staged.state)==supply and protected_state()==live,"STAGED partial-load disk restore preserves all physical books, coins and original input; earned career untouched"):return false
	receipt.controlled.append({"label":"STAGED_SAVE_GUARD_ONLY","case":"two_boats_one_loaded_active_save","client":owner096,"clientBoatUids":boats.map(func(b):return str(b.uid)),"carrierUids":job.escort.carrierUids.duplicate(),"carrierCargo":job.escort.carrierCargo.duplicate(true),"savePath":path,"restored":true,"totalCoins":staged.Money.total(staged.state)})
	return true

func save_guards096(active: Dictionary) -> bool:
	# Corrupt only detached copies. These refusals are not earned play.
	var live: PackedByteArray=protected_state();var state_ref: Dictionary=c.state
	for broken in ["unknown_kind","legacy_coins_purse","purse","client","client_purse","carrier","cargo_ledger","destination","voyage","escrow_over","escrow_missing","fractional_fee","passenger_savings","chronology","shape","expired_held","arrival","coins"]:
		if not bounded():return false
		var bad: Dictionary=active.duplicate(true);var job: Dictionary=bad.voyageJobs[0]
		match broken:
			"unknown_kind":job.kind="unknown096"
			"legacy_coins_purse":job.kind="freight"
			"purse":job.payerKey="governmentPurse"
			"client":job.ownerId="foreign-client096"
			"client_purse":
				for owner in bad.fleetOwners:
					if owner.id==job.ownerId:owner.coins="invalid";break
			"carrier":job.escort.carrierUids[0]=str(bad.fleet[0].uid)
			"cargo_ledger":job.escort.carrierCargo["foreign-carrier096"]={}
			"destination":
				for port in bad.ports:
					if str(port.id) not in [job.port,job.targetPort]:job.targetPort=str(port.id);break
			"voyage":job.escort.voyageSeq+=1;job.id="escort:%s:%d"%[job.ownerId,int(job.escort.voyageSeq)]
			"escrow_over":job.escrow=int(job.reward)+1
			"escrow_missing":job.escrow=0
			"fractional_fee":job.reward=float(job.reward)+0.5
			"passenger_savings":job.savingsHousehold=1
			"chronology":job.acceptedDay=float(bad.day)+1
			"shape":job.failed="false"
			"expired_held":job.state="expired"
			"arrival":job.escort.arrived=true
			"coins":bad.coins=int(bad.coins)+1
		var input: PackedByteArray=var_to_bytes(bad)
		var raw_problem: String=c.SaveValidation.job_error070(bad,c.data)
		if not check(raw_problem.is_empty()==(broken=="coins"),"STAGED "+broken+" reaches its exact raw job gate; coin conservation remains the existing full-save gate"):return false
		var result: Dictionary=c.restore(bad)
		if not check(not result.get("ok",false) and is_same(c.state,state_ref) and protected_state()==live and var_to_bytes(bad)==input,"STAGED "+broken+" restore refuses before input, live state or contexts are published"):return false
		receipt.controlled.append({"label":"STAGED_SAVE_GUARD_ONLY","case":broken,"refusal":str(result.get("message",""))})
	return true

func staged096(active: Dictionary) -> bool:
	# Staged accounting ONLY: clone the already funded real save. These
	# terminal callbacks are never a battle, death, voyage or success witness.
	for branch in ["abandon","lost","retreated","won_without_carriers"]:
		if not bounded():return false
		var staged=Campaign.new(c.data)
		if not check(staged.restore(active).get("ok",false),"Separate staged "+branch+" career restores the real accepted escrow"):return false
		var job: Dictionary=staged.EscortOps.contracted(staged,owner096)
		var client: Dictionary=staged.fleet_owner(owner096)
		var fee: int=int(job.escrow);var purse: int=int(client.coins);var coins: int=int(staged.state.coins)
		var physical_before: PackedByteArray=var_to_bytes(staged.state.fleet+client.boats)
		if branch=="abandon":
			if not check(staged.VoyageJobs.abandon(staged,job096).ok,"Staged voluntary withdrawal returns escrow at sea without erasing NPC cargo"):return false
		else:
			job.escort.battlePending=true;job.escort.interceptions=1
			var context: Dictionary={"kind":"escort","allyOwnerId":owner096,"escortJobId":job096,"escortEvent":job096}
			var result: String="won" if branch=="won_without_carriers" else branch
			staged.EscortOps.settled(staged,result,context,{})
			if not check(job.state=="expired" and job.failed and int(job.escrow)==0,"Staged "+branch+" cannot earn a fee without actual complete carrier escape"):return false
			if branch=="lost":
				var expired: Dictionary=JSON.parse_string(JSON.stringify(staged.state))
				var input: PackedByteArray=var_to_bytes(expired)
				if not check(staged.restore(expired).get("ok",false) and same_values(physical(expired),physical(staged.state)) and var_to_bytes(expired)==input,"STAGED refunded loss save restores the zero escrow and every real purse/cost unchanged"):return false
				client=staged.fleet_owner(owner096)
				receipt.controlled.append({"label":"STAGED_SAVE_GUARD_ONLY","case":"refunded_loss_json_restore","restored":true})
			staged.EscortOps.settled(staged,result,context,{})
			if not check(staged.VoyageJobs.abandon(staged,job096).ok,"Expired staged branch can close without another refund"):return false
		if not check(int(client.coins)==purse+fee and int(staged.state.coins)==coins and staged.Money.total(staged.state)==supply and var_to_bytes(staged.state.fleet+client.boats)==physical_before,"Staged "+branch+" refunds exactly once and preserves every actual boat cost"):return false
		if not check(not staged.VoyageJobs.finish(staged,job096).ok and not staged.VoyageJobs.abandon(staged,job096).ok and int(client.coins)==purse+fee,"Staged closed "+branch+" cannot repay/refund twice"):return false
		receipt.controlled.append({"label":"STAGED_ACCOUNTING_ONLY","branch":branch,"refund":fee,"playerPayment":0})
	return true

func interception096() -> bool:
	if battles096>0:return gap096("SECOND_THREAT","A second natural interception exceeds this one-voyage bounded witness")
	c.EscortOps.start(main096,owner096)
	if not check(main096.mode=="battle" and str(main096.battle_context.get("escortJobId",""))==job096,"Existing Protect button path starts a real owned-carrier worker battle"):return false
	battles096+=1
	for _poll in range(4800):
		if not bounded():return false
		if main096.battle.get("result")!=null:break
		main096.poll_battle051(0.1,false)
		await process_frame
	if main096.battle.get("result")==null:return gap096("PHYSICAL_EXIT_UNFINISHED","Real battle did not reach a terminal objective inside the bounded probe")
	main096.settle_battle()
	var job: Dictionary=c.EscortOps.contracted(c,owner096)
	receipt.interception={"context":main096.battle_context.duplicate(true),"result":main096.battle.result,"battleSeconds":main096.battle.time,"report":main096.battle_report.duplicate(true)}
	if not check(str(main096.battle.result)=="won" and job.state=="active" and job.escort.exitSecured and not job.escort.battlePending,"Every original loaded carrier actually escapes before contract passage resumes"):return false
	var held: int=int(job.escrow);var coins: int=int(c.state.coins)
	main096.settle_battle()
	if not check(int(c.state.coins)==coins and int(c.EscortOps.contracted(c,owner096).escrow)==held,"Reopening the physical outcome pays no fee or repeated reward"):return false
	main096.return_to_campaign();main096.paused=true
	return check(c.Money.total(c.state)==supply,"Original hull damage, ammunition, stores and finite NPC cargo settle through Main")

func passage096() -> bool:
	var last_plan: float=-INF
	for _piece in range(900):
		if not bounded():return false
		var job: Dictionary=c.EscortOps.contracted(c,owner096)
		if job.is_empty() or job.state!="active":return gap096("CONTRACT_ENDED","Actual contract ended: "+str(job.get("escort",{}).get("failure","missing")))
		if job.escort.arrived:return true
		var seen: Dictionary=current096(owner096)
		# Delivery unloads the trade lot; completion is observed on the next
		# normal step by the existing clock, without a fabricated arrival.
		if seen.is_empty():
			if not advance(0.5):return false
			job=c.EscortOps.contracted(c,owner096)
			if not job.is_empty() and job.escort.arrived:return true
			return gap096("LOADED_CONTACT_LOST","The actual loaded client is no longer a current local contact")
		if not c.EscortOps.threat(c,c.fleet_owner(owner096)).is_empty():
			receipt.naturalInterceptionObserved=true
			if not (await interception096()):return false
			continue
		if c.distance(c.state.position,seen)>120.0 and float(c.state.day)*45.0-last_plan>=1.0:
			if not check(c.chart_course({"x":seen.x,"y":seen.y}).get("ok",false),"Normal local water course follows the moving loaded client"):return false
			last_plan=float(c.state.day)*45.0
		elif c.distance(c.state.position,seen)<=120.0:c.stop_sailing()
		if not advance(0.5):return false
	return gap096("PASSAGE_UNFINISHED","Original convoy did not complete its actual route/sale within450 simulated seconds")

func complete096() -> bool:
	var job: Dictionary=c.EscortOps.contracted(c,owner096).duplicate(true)
	if not sail(str(job.targetPort)):return false
	var coins: int=int(c.state.coins)
	var paid: Dictionary=c.settle_voyage_job(job096)
	if not check(paid.get("ok",false) and int(c.state.coins)==coins+int(job.reward) and c.EscortOps.contracted(c,owner096).is_empty(),"Actual delivery-harbor report releases exactly the funded fee once"):return false
	gross_paid=int(job.reward)
	if not check(not c.settle_voyage_job(job096).ok and int(c.state.coins)==coins+gross_paid,"Repeated success claim cannot pay again"):return false
	receipt.completedContract=job
	if not sail("brass_haven"):return false
	# This short earned route can return before the first daily payroll.
	# Wait at the actual home berth for the next normal wage publication;
	# then replace the supplies consumed by both passage and berth standby.
	var standby_day: float=float(c.state.day)
	var next_payroll: float=float(c.state.econDay)+1.0
	while payroll<=0 and float(c.state.day)<next_payroll+0.05:
		if not advance(0.5):return false
	receipt.berthStandby={"fromDay":standby_day,"toDay":c.state.day,"publishedPayroll":payroll,"reason":"Ordinary home-berth time until actual first daily wage publication; no direct clock or purse writes."}
	var boat: Dictionary=c.state.fleet[0]
	var before: Dictionary=physical_boat(boat).duplicate(true)
	var before_service: int=int(c.state.coins)
	var quote: Dictionary=c.service_quote(boat,c.current_port())
	if not check(quote.get("ok",false),"Reached home quotes actual existing damage, materials and labor"):return false
	if int(quote.get("cost",0))>0 and not check(c.repair_boat(str(boat.uid)).get("ok",false),"Actual repair uses real stores, workers and captain coins"):return false
	var repair: int=before_service-int(c.state.coins)
	var before_stores: int=int(c.state.coins)
	if not check(c.resupply_boat(str(boat.uid),"full").get("ok",false),"Next-job fuel/ammunition/kits are bought through the actual harbor"):return false
	var food: int=ceili(maxf(0,float(c.data.START.food)-float(c.state.cargo.food)))
	if food>0 and not check(c.trade("brass_haven","food",food,"buy").get("ok",false),"Consumed rations are replaced from paid finite stock"):return false
	var replacements: int=before_stores-int(c.state.coins)
	if not check(payroll>0 and int(c.state.coins)==15000+gross_paid-payroll-repair-replacements and int(c.state.wageArrears)==0,"Starting capital, fee, all normal wages, actual damage and replacement stores reconcile"):return false
	var saved: Dictionary=parsed_save("escort096-completed")
	if saved.is_empty():return false
	# The actual legacy return loop survives a newly published corridor;
	# extending it beyond the original80-unit gate bound still must fail.
	var bad_waypoint: Dictionary=saved.duplicate(true)
	bad_waypoint.ocean066.contact.waypoint.x=float(bad_waypoint.ocean066.contact.waypoint.x)+1.0
	var live_waypoint: PackedByteArray=protected_state()
	var bad_input: PackedByteArray=var_to_bytes(bad_waypoint)
	var refused_waypoint: Dictionary=c.restore(bad_waypoint)
	if not check(not refused_waypoint.get("ok",false) and str(refused_waypoint.get("message","")).contains("waypoint must") and protected_state()==live_waypoint and var_to_bytes(bad_waypoint)==bad_input,"Actual completed book still refuses an over-bound legacy waypoint atomically"):return false
	if not restore_exact(saved,"escort096-completed"):return false
	if not check(saved.get("lastEscortVoyage",{}).get("payment",0)==gross_paid and job096 in saved.doneVoyageJobs and c.work_port070().get("id")=="brass_haven","Earned completed save retains paid client route/carrier evidence and physical home return"):return false
	receipt.accounting={"startingCoins":15000,"clientFee":gross_paid,"payroll":payroll,"repairs":repair,"replacementStores":replacements,"endingCoins":c.state.coins,"coinSupply":supply,"totalCoins":c.Money.total(c.state)}
	receipt.returnBoatBeforeService=before;receipt.returnBoatAfterService=physical_boat(c.state.fleet[0]).duplicate(true)
	receipt.physicalInterception=battles096>0;receipt.earnedVoyage=true;receipt.wholeLoop=true
	receipt.earnedEvidence="EARNED_PAID_VOYAGE_WITH_NATURAL_INTERCEPTION" if battles096>0 else "EARNED_QUIET_PAID_VOYAGE"
	receipt.physicalExitEvidence="EARNED_VOYAGE_ACTUAL_CARRIER_EXITS" if battles096>0 else "NOT_OBSERVED_ON_THIS_EARNED_VOYAGE"
	receipt.status="COMPLETED"
	return true

func _run() -> void:
	receipt.fixture="escort096";receipt.bodyLimitMs=LIMIT096_MS;receipt.earnedVoyage=false;receipt.naturalInterceptionObserved=false
	var staged_only: bool=OS.get_cmdline_user_args().has("--escort096-staged-r4")
	var resume: bool=staged_only or OS.get_cmdline_user_args().has("--escort096-resume-r4")
	receipt.mode="STAGED_SAVE_ACCOUNTING_ONLY" if staged_only else ("EARNED_ACTUAL_PREFIX_CONTINUATION" if resume else "EARNED_ONLY_NEW_GAME")
	receipt.stagedGuardsComplete=false
	if not check(OS.get_environment("GAME_TEST_ARTIFACTS").is_absolute_path(),"Private artifact/profile path required"):await finish096();return
	if staged_only:
		var world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
		if not check(world is Dictionary,"Staged-only campaign definitions decode"):await finish096();return
		c=Campaign.new(world)
		var active: Dictionary=resume_actual096()
		if not active.is_empty():staged_only096(active)
		await finish096();return
	main096=Main096.new();main096.qa_ocean066=true
	root.add_child.call_deferred(main096);await main096.ready
	main096.set_process(false);main096.set_physics_process(false);main096.paused=true
	c=main096.core
	if resume:
		if not resume_actual096().is_empty():
			main096.mode="campaign";main096.quick_mode=false;main096.ui.close_modal();main096.ui.build_hud()
			if await passage096():complete096()
		await finish096();return
	main096.new_game(69069);main096.paused=true;c=main096.core
	if not check(not c.state.is_empty() and int(c.state.coins)==15000 and c.crew_count()==5,"Ordinary new_game starts with exactly15000coins and5crew"):await finish096();return
	supply=int(c.state.coinSupply)
	receipt.initial={"coins":c.state.coins,"crew":c.crew_count(),"boat":physical_boat(c.state.fleet[0]).duplicate(true)}
	var offer: Dictionary=seek096()
	if offer.is_empty():
		if failures==0:gap096("NO_NATURAL_FUNDED_PASSAGE","No ordinary local loaded client with a fundable remaining route was reached; no encounter or resources supplied")
	elif accept096(offer) and (await passage096()):complete096()
	await finish096()

func finish096() -> void:
	if finished096:return
	finished096=true
	if workers.group_id>=0:workers.finish(true)
	if main096!=null:
		main096._retire_battle_driver051();main096.sync_economy();main096.queue_free()
		await process_frame
	c=null
	var elapsed: int=Time.get_ticks_msec()-started
	check(elapsed<LIMIT096_MS,"Whole096 body, ordinary economy and owned worker/Main cleanup stays below34s")
	if receipt.status=="UNFINISHED" or failures>0 and receipt.status in ["COMPLETED","STAGED_COMPLETED"]:receipt.status="FAILED"
	receipt.checks=checks;receipt.failures=failures;receipt.elapsedMs=elapsed
	var path: String=OS.get_environment("GAME_TEST_ARTIFACTS").path_join("escort096-result.json")
	var file=FileAccess.open(path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(receipt,"\t"));file.close()
	print("ESCORT096_RESULT ",JSON.stringify(receipt));print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 and (receipt.earnedVoyage or receipt.stagedGuardsComplete) else 1)
