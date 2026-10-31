extends "res://tests/test_voyage_career070.gd"
## SOURCE ONLY: Root owns Test Bridge, native acceptance and UI capture.
## Reuse070's ordinary15000-coin paid jobs/survey, HOME return, replacement
## stores and net-funded useful improvement. No new encounter/battle proof.
## Six starter career readings are quotes, not six earned career playthroughs.
## Two detached synthetic fishing refusal cases are quotes, not normal journeys.
const Guidance078=preload("res://scripts/campaign_guidance.gd")
const Expedition078=preload("res://scripts/expedition.gd")
const Costs078=preload("res://scripts/career_costs.gd")
const Work078=preload("res://scripts/civilian_work.gd")
const Births078=preload("res://scripts/equipment_lifecycle.gd")
const Transport078=preload("res://scripts/passenger_transport.gd")
const Navigation078=preload("res://scripts/navigation.gd")
const CAREERS078: Array=["explorer","merchant","escort","privateer","fisher","passenger"]
const BODY078_LIMIT_MS: int=55000
const WORK078_STOP_MS: int=53500
const WITNESS078: String="C:/Users/bligh/Documents/Codex/2026-10-20/how/work/quality-v078/witness-state078.json"

func bounded() -> bool:
	if Time.get_ticks_msec()-started<WORK078_STOP_MS:return true
	receipt.status="BODY_TIMEOUT"
	return check(false,"078 stops new work at53.5seconds; whole body including cleanup must be under55seconds")

func earned_work070(rerun_corrupt: bool=true) -> bool:
	if not check(int(c.state.coins)==15000 and int(c.data.START.coins)==15000 and float(c.state.day)==1.0 and c.state.fleet.size()==1,"Six quotes and the voyage use the same untouched normal15000-coin starter"):return false
	receipt.initial={"coins":c.state.coins,"day":c.state.day,"boat":physical_boat(c.state.fleet[0]).duplicate(true),"cargo":c.state.cargo.duplicate(true)}
	if not career_quotes078() or not fisher_refusals078():return false
	return super.earned_work070(rerun_corrupt)

func earned_voyage() -> bool:
	var uid: String=str(c.state.fleet[0].uid)
	receipt.notRerun=["070 controlled corrupt-input cases","072 encounter/withdrawal/paid battle repair","Headless UI text bindings; Root captures the actual UI separately"]
	return earned_work070(false) and earned_home070(uid)

func career_quotes078() -> bool:
	phase("six_read_only_starter_career_quotes_not_playthroughs")
	var frozen: PackedByteArray=protected_state()
	var world: PackedByteArray=var_to_bytes(c.data)
	var economy: Dictionary=Expedition078.report(c.state,c.data)
	var offers: Array=c.VoyageJobs.available(c)
	receipt.careerQuotes=[]
	receipt.careerAffordability=[]
	for id in CAREERS078:
		if not bounded():return false
		var report: Dictionary=Guidance078.report(c,0.0,id)
		var plan: Dictionary=report.get("careerPlan",{})
		if not check(report.get("ok",false) and str(report.get("career",""))==id and str(plan.get("id",""))==id and not plan.get("requirements",[]).is_empty(),id+": actual public career and requirements"):return false
		var costs: Dictionary=plan.get("operatingCosts",{})
		if not check(int(costs.get("dailyWages",-1))==c.crew_count()*100 and int(costs.dailyWages)==int(economy.dailyWages) and int(costs.get("wageCoins",-1))==ceili(float(costs.get("days",0))*int(costs.dailyWages)),id+": ordinary100-coin full-fleet payroll and complete allowance"):return false
		if not check(float(costs.get("capacity",-1))==float(economy.usableCapacity) and float(costs.get("freeHold",-1))==float(economy.freeCapacity) and float(costs.get("reserveDays",0))==2.0,id+": actual cargo capacity and return contingency"):return false
		if not check(bool(plan.get("ready",false))==plan.get("blockers",[]).is_empty() and (float(economy.affordableDays)>=float(costs.days) or not plan.ready),id+": readiness cannot promise unaffordable ordinary payroll"):return false
		receipt.careerAffordability.append({"career":id,"availablePayrollDays":economy.affordableDays,"requiredPayrollDays":costs.days,"wageCoins":costs.wageCoins,"ready":plan.ready})
		var quoted: Dictionary=plan.get("quote",{})
		if quoted.has("id"):
			var matching: Array=offers.filter(func(j):return str(j.id)==str(quoted.id))
			if not check(matching.size()==1 and int(quoted.rewardCoins)==int(matching[0].reward) and str(quoted.payerKey)==str(matching[0].payerKey),id+": reward names one actual funded offer and payer"):return false
		if id in ["fisher","passenger"]:
			var roles: Array=["fishing"] if id=="fisher" else ["transport","yacht"]
			var present: bool=c.active_fleet().any(func(b):return str(b.spec.get("civilianRole","")) in roles)
			if not present:
				var entry: Dictionary=plan.get("entryHull",{})
				if not check(not plan.ready and not entry.is_empty(),id+": missing real hull role shows a blocked paid entry"):return false
				var hull: Dictionary=c.hull(str(entry.id))
				var price: Dictionary=c.Harbor.quote(c,hull,c.current_port())
				if not check(str(hull.get("civilianRole","")) in roles and int(entry.commissionCoins)==int(price.commissionPrice) and int(entry.readyCoins)==int(price.readyPrice) and int(entry.crewAdvanceCoins)==c.Economy.recruit_cost(c.current_port(),int(hull.crewMin)),id+": eligible hull and actual construction/recruit advances, no free role"):return false
		if id=="merchant" and quoted.has("freight"):
			var lot: Dictionary=quoted.freight
			var weight: float=float(lot.qty)*float(c.Goods.ITEMS[str(lot.good)].weight)
			if not check(weight<=float(economy.freeCapacity) or (not plan.ready and str(plan.blockers).contains("free hold")),"Merchant freight uses physical free hold"):return false
		if id=="escort" and not check(int(quoted.get("rewardCoins",-1))==0 and int(quoted.get("standing",0))==5 and int(quoted.get("serviceCredit",0))==1,"Escort guidance distinguishes standing/service from coin revenue"):return false
		for field in ["firstGoal","nextStep","rewardSource","limits"]:
			if not check(not str(plan.get(field,"")).is_empty(),id+": public plan supplies "+field):return false
		if not check(protected_state()==frozen and var_to_bytes(c.data)==world,id+": public queries preserve typed live state, navigation, purses, actors, pending work and world data"):return false
		receipt.careerQuotes.append(plan.duplicate(true))
	return true

func fisher_refusals078() -> bool:
	phase("SYNTHETIC_detached_fishing_quotes_not_normal_journeys")
	var primary: PackedByteArray=protected_state();var world: PackedByteArray=var_to_bytes(c.data)
	var fork=Campaign.new(c.data,c.nav,false);fork.state=c.state.duplicate(true)
	var ids: Array=[]
	for id in ["brinehook_longliner","fenhopper_lighter"]:
		var h: Dictionary=fork.hull(id)
		var birth: Dictionary=Births078.stage_birth(fork.state,fork.data,h,"boat-%d"%int(fork.state.nextUid),{})
		if not check(birth.get("ok",false),"SYNTHETIC canonical empty quote shell: "+id):return false
		var b: Dictionary=fork.add_boat(h,0,birth)
		if not check(not b.is_empty() and fork.recruit_crew(str(b.uid),int(h.crewMin)).get("ok",false) and (id=="fenhopper_lighter" or fork.resupply_boat(str(b.uid),"voyage").get("ok",false)),"SYNTHETIC shell uses paid existing minimum crew; fishing stores are purchased"):return false
		ids.append(str(b.uid))
	var home: Dictionary=fork.current_port();var offshore: Dictionary={}
	for delta in [Vector2(220,0),Vector2(-220,0),Vector2(0,220),Vector2(0,-220)]:
		var point: Dictionary={"x":float(home.x)+delta.x,"y":float(home.y)+delta.y}
		if Navigation078.is_water(fork.nav,point.x,point.y,18):offshore=point;break
	if not check(not offshore.is_empty(),"SYNTHETIC quote-only offshore position exists; no normal voyage movement"):return false
	fork.state.position=offshore;fork.state.path=[];fork.state.destination=""
	if not check(Work078.fishing_quote(fork,str(ids[0]),1.0).get("ok",false),"SYNTHETIC baseline can set gear before either negative case"):return false
	var opening: Dictionary=fork.state.duplicate(true)
	receipt.fisherQuoteCases=[]
	for kind in ["selected_locker_full_other_carrier_empty","already_assigned_gear"]:
		if not bounded():return false
		fork.state=opening.duplicate(true)
		var boat: Dictionary=fork.find_boat(str(ids[0]))
		if kind=="selected_locker_full_other_carrier_empty":
			var engine: Dictionary={}
			for item in boat.moduleCondition.items.values():
				if item.location=="engine":engine=item;break
			if not check(not engine.is_empty(),"SYNTHETIC locker reuses this shell's physical engine UID"):return false
			engine.location="locker";engine.lockerOrder=0;boat.spec.cargo=Expedition078.locker_weight(boat)
		else:Work078.ensure(fork).fishing.append({"boatUid":str(boat.uid),"siteId":Work078.site_id(fork.state.position),"crew":int(boat.crew),"daysTotal":1.0,"daysDone":0.0,"catch":0.0,"lastDay":float(fork.state.day)})
		var frozen: PackedByteArray=var_to_bytes([fork.state,fork.events,fork.pending_days,fork.route_cache,fork.route_hits,fork.route_misses])
		var q: Dictionary=Work078.fishing_quote(fork,str(boat.uid),1.0)
		var plan: Dictionary=Costs078.plan(fork,"fisher")
		var reason: String="hold" if kind=="selected_locker_full_other_carrier_empty" else "assignment"
		if not check(not q.ok and q.limitingCause==reason and not plan.ready and str(q.message) in plan.blockers and float(plan.quote.freeBoatHold)==minf(float(q.holdFree),float(q.fleetHoldFree)),"SYNTHETIC "+kind+": career forwards the actual live quote refusal and physical hold"):return false
		var spare: Dictionary=fork.find_boat(str(ids[1]))
		if reason=="hold" and not check(float(q.holdFree)==0.0 and float(q.fleetHoldFree)>0 and Transport078.available_hold(fork,spare)==float(spare.spec.cargo),"SYNTHETIC selected locker is full while the separate carrier is empty"):return false
		if not check(var_to_bytes([fork.state,fork.events,fork.pending_days,fork.route_cache,fork.route_hits,fork.route_misses])==frozen,"SYNTHETIC "+kind+": both quotes preserve the complete detached state, events and route counters"):return false
		receipt.fisherQuoteCases.append({"case":kind,"basis":"SYNTHETIC quote only; staged empty hulls, paid crews/fishing stores, offshore position, locker/capacity or zero-work gear; no clock advance, catch or sale","earnedVoyage":false,"workQuote":q,"careerPlan":plan})
	return check(protected_state()==primary and var_to_bytes(c.data)==world,"Synthetic quotes leave every normal-starter book, actor, position, clock, purse and runtime context untouched")

func witness078() -> void:
	var encoded: String=JSON.stringify(c.state)
	var file=FileAccess.open(WITNESS078,FileAccess.WRITE)
	if not check(file!=null,"Actual final normal-voyage witness opens at Root's agreed capture path"):return
	file.store_string(encoded)
	var written: bool=file.get_error()==OK
	file.close()
	var digest: String=FileAccess.get_sha256(WITNESS078)
	if not check(written and digest==encoded.sha256_text(),"Full ordinary final state is written exactly and bound by SHA256"):return
	receipt.witness={"path":WITNESS078,"sha256":digest,"kind":"actual_normal_start_final_state","coins":c.state.coins,"day":c.state.day,"uid":str(c.state.fleet[0].uid)}

func finish() -> void:
	if workers.group_id>=0:workers.finish(true)
	if c!=null and receipt.get("earnedVoyage",false) and failures==0:witness078()
	c=null
	var directory: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	var file=FileAccess.open(directory.path_join("quality078-result.json"),FileAccess.WRITE) if directory.is_absolute_path() else null
	check(file!=null,"Private quality078 result artifact opens")
	receipt.fixture="quality078";receipt.bodyLimitMs=BODY078_LIMIT_MS;receipt.workStopMs=WORK078_STOP_MS
	receipt.quoteBasis="Six read-only career reviews on the untouched normal starter plus two explicitly detached synthetic fishing refusals. Only the inherited070 full paid voyage is earned progression; no staged hulls, funds, actors, positions, clock or outcomes enter it."
	receipt.elapsed_ms=Time.get_ticks_msec()-started
	check(int(receipt.elapsed_ms)<BODY078_LIMIT_MS,"Whole078 body includes Campaign setup, quotes, normal paid voyage, witness and joined worker cleanup under55seconds")
	receipt.complete=receipt.get("earnedVoyage",false) and receipt.has("witness") and failures==0
	receipt.earnedVoyage=receipt.complete
	if receipt.complete:receipt.status="COMPLETED"
	elif receipt.status in ["UNFINISHED","COMPLETED"]:receipt.status="FAILED"
	receipt.checks=checks;receipt.failures=failures;receipt.elapsedMs=receipt.elapsed_ms
	if file:file.store_string(JSON.stringify(receipt,"\t"));file.close()
	print("QUALITY078_RESULT ",JSON.stringify(receipt))
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if receipt.complete else 1)
