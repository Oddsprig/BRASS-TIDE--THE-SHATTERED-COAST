extends SceneTree
## Prepared for Root only: one real seeded voyage, no injected site levels,
## stores, sailors, victories, capital or completed assignments.
const Campaign=preload("res://scripts/campaign.gd")
const Workers=preload("res://scripts/economy_workers.gd")
const Money=preload("res://scripts/money.gd")
const Expedition=preload("res://scripts/expedition.gd")
const Stories=preload("res://scripts/coastal_stories.gd")
var c
var workers=Workers.new()
var checks: int=0
var failures: int=0
var started_ms: int=0
var paid_days: int=0
var paid_wages: int=0
var hull_uid: String=""
var gear_ids: Array=[]
var voyage_completed: bool=false

func check(value: bool,message: String) -> bool:
	checks+=1
	if not value:failures+=1;print("FAIL expedition057: ",message)
	return value

func within_budget() -> bool:
	return check(Time.get_ticks_msec()-started_ms<38000,"Bounded native proof remains below 38 seconds including its one fixture")

func conserved(label: String) -> bool:
	return check(Money.total(c.state)==int(c.state.coinSupply),label+": actual global coin supply conserves")

func allowance_receipt(label: String,report: Dictionary) -> void:
	print("expedition057: ",label," ready=",report.get("readyForAllowance",false)," bottleneck=",report.get("bottleneck","")," days=",report.get("tripDays",0)," shore=",report.get("shoreDays",0)," wageShortfall=",report.get("wageShortfall",0)," foodShortfall=",report.get("foodShortfall",0)," kitShortfall=",report.get("kitShortfall",0)," crewShortfall=",report.get("crewShortfall",0)," extraDays=",report.get("extraDays",0))

func sync_economy() -> void:
	# Same copied-port worker, per-day seed and join/publication as Main.
	while c.pending_days>0:
		c.pending_days-=1
		workers.start(c.state.ports,1,c.TradeFlow.blockades(c),int(c.state.seed)+int(c.state.econDay)*104729)
		var result: Dictionary=workers.finish(true)
		var wages: int=int(c.Economy.daily_upkeep(c.state.fleet).wages)
		c.apply_economy(result.ports,result.events,result.days)
		paid_days+=1;paid_wages+=wages
		conserved("Paid campaign day")

func advance(seconds: float) -> bool:
	var remaining: float=seconds
	for i in range(80):
		if remaining<=0.000001:return true
		if not within_budget():return false
		var dt: float=minf(11.25,remaining)
		c.step(dt)
		sync_economy()
		remaining-=dt
	return check(false,"Elapsed work completed inside the useful chunk bound")

func sail(target: Dictionary,port_id: String="") -> bool:
	print("expedition057: sail ",target.get("name",port_id)," day ",c.state.day)
	var order: Dictionary=c.chart_course(target,port_id)
	if not check(bool(order.ok),"Real chart_course accepts: "+str(order.message)):return false
	for i in range(96):
		if c.state.path.is_empty():
			c.stop_sailing()
			if port_id.is_empty():return check(c.distance(c.state.position,target)<=180,"Actual sailed position reaches the landing")
			return check(str(c.current_port().get("id",""))==port_id,"Actual sailed position reaches the named harbor")
		if not within_budget():return false
		var length: float=0.0
		var previous: Dictionary=c.state.position
		for point in c.state.path:length+=c.distance(previous,point);previous=point
		var speed: float=c.travel_speed()
		if not check(speed>0,"Player retains actual sailing speed"):return false
		c.step(minf(4.0,maxf(0.001,length/speed)))
		sync_economy()
	return check(false,"Actual route finishes within 96 development-sized travel chunks")

func stock_kits() -> float:
	var total: float=float(c.state.cargo.get("supplies",0))
	for boat in c.active_fleet():total+=float(boat.supplies)
	return total

func work(site_id: String,action: String) -> bool:
	var quote: Dictionary=c.Exploration.quote(c.state,site_id,action)
	print("expedition057: work ",site_id," ",action," quote ",quote)
	if not check(bool(quote.ok),"Real work quote is ready: "+str(quote.message)):return false
	var kits: float=stock_kits()
	var food: float=float(c.state.cargo.food)
	var coins: int=int(c.state.coins)
	var wages_before: int=paid_wages
	var begin: Dictionary=c.begin_survey(site_id,action)
	if not check(bool(begin.ok),"Stopped public Campaign begins real "+action):return false
	check(is_equal_approx(stock_kits(),kits-float(quote.supplies)),"Quoted finite kits are consumed once")
	check(is_equal_approx(float(c.state.cargo.food),food-float(quote.food)),"Quoted shore rations are prepaid from real cargo")
	var reserved: int=0
	for boat in c.active_fleet():reserved+=int(boat.get("shoreCrew",0))
	check(reserved==int(quote.crewNeeded),"Actual sailors are reserved above living hull minimums")
	check(not c.chart_course(c.state.position).ok,"An actual shore party prevents sailing away")
	var fuel: float=float(c.find_boat(hull_uid).fuel)
	if not advance(float(quote.days)*c.DAY_SECONDS+0.00001):return false
	check(c.state.exploration.assignment.is_empty(),"Real elapsed work completes the assignment")
	check(int(c.state.exploration.sites[site_id].level)==int(quote.targetLevel),"Only completed real work raises site knowledge")
	check(is_equal_approx(float(c.find_boat(hull_uid).fuel),fuel),"Idle shore days do not consume sailing fuel")
	check(int(c.state.coins)==coins-(paid_wages-wages_before),"Real shore time pays the whole fleet's daily wages")
	check(not c.begin_survey(site_id,action).ok,"Completed work cannot consume another lot or repeat a finding")
	return conserved("Completed shore assignment")

func roundtrip(label: String) -> bool:
	sync_economy()
	var coins: int=int(c.state.coins)
	var cargo: Dictionary=c.state.cargo.duplicate(true)
	var knowledge: Dictionary=c.state.exploration.duplicate(true)
	var saved: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	var result: Dictionary=c.restore(saved)
	if not check(bool(result.ok),label+": existing restore accepts the actual voyage: "+str(result.message)):return false
	check(int(c.state.coins)==coins and c.state.cargo==cargo,label+": player purse and physical cargo survive JSON save/load")
	check(c.state.exploration==knowledge,label+": earned knowledge and work survive save/load")
	var retained: Array=c.find_boat(hull_uid).moduleCondition.items.keys()
	retained.sort()
	check(str(c.find_boat(hull_uid).uid)==hull_uid and retained==gear_ids,label+": player hull and existing equipment custody survive restore")
	return conserved(label)

func mark_field_wreck() -> Dictionary:
	for wreck in c.state.wrecks:
		if str(wreck.get("sourceId",""))=="site:shatter_wreck_field":return wreck
	return {}

func finite_recovery() -> bool:
	var wreck: Dictionary=mark_field_wreck()
	if not check(not wreck.is_empty(),"Real full survey exposes one finite authored wreck"):return false
	var hazard: Dictionary=c.fleet_owner(str(c.state.wreckHazards.get(wreck.sourceId,"")))
	var controlled: bool=not hazard.is_empty() and bool(hazard.active) and hazard.boats.any(func(b):return not b.sunk)
	var cargo: Dictionary=c.state.cargo.duplicate(true)
	var stock: Dictionary=wreck.components.duplicate(true)
	if controlled:
		var refused: Dictionary=c.recover_wreck(str(wreck.id),"strip","timber",1.0)
		print("expedition057: optional hostile recovery refused: ",refused)
		check(not refused.ok and str(refused.message).contains("Hostiles"),"Actual hostile owner refuses recovery; no free defeat")
		check(c.state.cargo==cargo and mark_field_wreck().components==stock,"Refused optional recovery transfers no lot")
		return true
	# Lift one existing finite material lot; do not claim an unpurchased hull.
	var good: String="timber"
	if not check(float(stock.get(good,0))>0,"The actual wreck contains a recoverable finite plank lot"):return false
	var qty: float=minf(1.0,float(stock[good]))
	var recovered: Dictionary=c.recover_wreck(str(wreck.id),"strip",good,qty)
	if not check(bool(recovered.ok),"Real optional finite recovery succeeds: "+str(recovered.message)):return false
	sync_economy()
	check(is_equal_approx(float(c.state.cargo.get(good,0)),float(cargo.get(good,0))+qty),"Recovered planks enter the real hold")
	check(is_equal_approx(float(mark_field_wreck().components[good]),float(stock[good])-qty),"The same quantity leaves finite wreck stock")
	var count: int=c.state.wrecks.size()
	check(not c.begin_survey("shatter_wreck_field","survey").ok and c.state.wrecks.size()==count,"Survey cannot seed a second authored wreck")
	return conserved("Finite optional recovery")

func rights_branches(late: Dictionary,secret: Dictionary) -> void:
	# Reuse the actual late physical state. The alternative story/contact/standing
	# context was produced by keep_secret at the real charted-rock checkpoint.
	# These are isolated choice assertions, not a second claimed sailed voyage.
	c.state=late.duplicate(true)
	for key in ["stories","contacts","relationships"]:c.state[key]=secret[key].duplicate(true)
	check(bool(c.StoryOps.choose(c,"middle_sea_chart","mark_field").ok),"Detached alternative uses the voyage's actually completed field survey")
	check(not c.StoryOps.choose(c,"middle_sea_chart","open_field").ok,"Secret branch refuses incompatible public registration")
	var before: int=int(c.state.coins)
	check(bool(c.StoryOps.choose(c,"middle_sea_chart","exclusive_claim").ok),"Detached late checkpoint can register the actual private right")
	check(c.state.storyRights.privateField and not c.state.storyRights.openField,"Private rights are exclusive")
	check(not c.StoryOps.choose(c,"middle_sea_chart","exclusive_claim").ok and int(c.state.coins)==before,"Private completion cannot repeat or mint coins")
	c.state=late
	c.pending_days=0
	before=int(c.state.coins)
	check(not c.StoryOps.choose(c,"middle_sea_chart","exclusive_claim").ok,"Shared branch refuses incompatible private registration")
	check(bool(c.StoryOps.choose(c,"middle_sea_chart","open_field").ok),"Actual sailed voyage registers public rights at Wren's harbor")
	check(c.state.storyRights.openField and not c.state.storyRights.privateField,"Public rights reach their existing consumer")
	check(not c.StoryOps.choose(c,"middle_sea_chart","open_field").ok,"Actual completed choice cannot repeat")
	check(int(c.state.coins)==before,"Rights decisions award no invented coin reward")

func voyage() -> void:
	var born: Dictionary=c.new_game(5701)
	if not check(bool(born.ok),"One seeded actual Campaign initializes"):return
	hull_uid=str(c.state.flagship)
	gear_ids=c.find_boat(hull_uid).moduleCondition.items.keys()
	gear_ids.sort()
	var boat: Dictionary=c.find_boat(hull_uid)
	var count: int=maxi(0,int(boat.crewMin)+4-int(boat.crew))
	var harbor: Dictionary=c.current_port()
	var quote: int=c.Economy.recruit_cost(harbor,count)
	var coins: int=int(c.state.coins)
	var sailors: int=int(boat.crew)
	var hire: Dictionary=c.recruit_crew(hull_uid,count)
	if not check(bool(hire.ok),"Existing purse pays actual recruitment quote: "+str(hire.message)):return
	check(int(c.state.coins)==coins-quote and int(c.find_boat(hull_uid).crew)==sailors+count,"Real hire costs match the quote; no free spare hands")
	check(c.Exploration.spare_crew(c.state)>=4,"Prepared actual hull has four spare able sailors")
	for purchase in [{"good":"food","qty":2},{"good":"supplies","qty":2}]:
		var good: String=str(purchase.good)
		var stock: float=float(c.current_port().stocks[good])
		var bill: int=c.Economy.price(c.current_port(),good,"buy")*int(purchase.qty)
		coins=int(c.state.coins)
		var bought: Dictionary=c.trade(str(c.current_port().id),good,int(purchase.qty),"buy")
		if not check(bool(bought.ok),"Actual paid provisioning succeeds: "+str(bought.message)):return
		check(int(bought.total)==bill and int(c.state.coins)==coins-bill and is_equal_approx(float(c.current_port().stocks[good]),stock-float(purchase.qty)),"Purchased stores match their actual quote and leave real harbor stock")
	if not conserved("Prepared player"):return
	if not sail(c.port("reed_floats"),"reed_floats"):return
	if not check(bool(c.StoryOps.start(c,"middle_sea_chart").ok),"Wren actually accepts the lead at her harbor"):return
	var stories_before: Dictionary=c.state.stories.duplicate(true)
	var paired: Dictionary={}
	for offer in c.VoyageJobs.available(c):
		if str(offer.kind)=="survey":paired=offer;break
	check(c.state.stories==stories_before,"Reading the work board advances no story decision")
	if not check(str(paired.get("siteId",""))=="middle_chart_rock","Actual funded board prefers Wren's accepted current objective"):return
	var sponsor_before: int=int(c.port("reed_floats").governmentPurse)
	if not check(bool(c.accept_voyage_job(str(paired.id)).ok),"Existing treasury funds the ordinary accepted survey escrow"):return
	check(int(c.port("reed_floats").governmentPurse)==sponsor_before-int(paired.reward),"Full job reward leaves actual sponsor funds")
	check(int(c.state.voyageJobs[0].escrow)==int(paired.reward),"The same reward is held once in escrow")
	var full: Dictionary=Expedition.preview(c,"middle_chart_rock","reed_floats","",3)
	var clue: Dictionary=Expedition.preview(c,"middle_chart_rock","reed_floats","",2)
	allowance_receipt("full paid allowance",full)
	check(float(full.shoreDays)>float(clue.shoreDays) and float(full.shoreKits)>float(clue.shoreKits),"Full level3 paid work is budgeted above the level2 clue")
	if not check(bool(full.readyForAllowance),"Actually purchased player can afford the full rock work and named return allowance"):return
	var rock: Dictionary=c.Exploration.catalog_site(c.state,"middle_chart_rock")
	if not sail(rock):return
	if not work("middle_chart_rock","chart"):return
	# Produce the alternative legitimately, then keep its detached context only.
	var actual: Dictionary=c.state
	c.state=actual.duplicate(true)
	check(bool(c.StoryOps.choose(c,"middle_sea_chart","keep_secret").ok),"Alternative first decision is earned by actual chart work")
	var secret: Dictionary=c.state.duplicate(true)
	c.state=actual
	if not check(bool(c.StoryOps.choose(c,"middle_sea_chart","share_chart").ok),"Actual clue choice changes the next destination"):return
	var journal: Dictionary={}
	for entry in Stories.journal(c.state):
		if str(entry.get("chainId",""))=="middle_sea_chart":journal=entry;break
	if not check(not journal.is_empty(),"Accepted chain has its exact chainId journal entry"):return
	check(str(journal.get("objective",{}).get("siteId",""))=="shatter_wreck_field","Earned journal names Shatter as the next objective")
	if not work("middle_chart_rock","survey"):return
	if not roundtrip("Rock fully surveyed with live escrow"):return
	var field: Dictionary=c.Exploration.catalog_site(c.state,"shatter_wreck_field")
	var allowance: Dictionary=Expedition.preview(c,"shatter_wreck_field","reed_floats")
	if not check(bool(allowance.readyForAllowance),"Current reserves cover the earned field survey and informed return"):return
	if not sail(field):return
	if not work("shatter_wreck_field","chart"):return
	if not work("shatter_wreck_field","survey"):return
	if not check(bool(c.StoryOps.choose(c,"middle_sea_chart","mark_field").ok),"Actually surveyed field earns its optional anchorage lead"):return
	if not finite_recovery():return
	var decision: Dictionary=Expedition.preview(c,"shatter_wreck_field","reed_floats","rust_salvage_anchorage")
	allowance_receipt("return now",decision.returnNow)
	allowance_receipt("optional Rust detour",decision.detour)
	check(not decision.detour.is_empty() and float(decision.detour.extraDays)>0,"Earned optional detour exposes actual extra travel/work budget")
	if not check(bool(decision.returnNow.readyForAllowance),"Returning now has an affordable named harbor allowance"):return
	if not roundtrip("Actual discovery and finite recovery"):return
	if not sail(c.port("reed_floats"),"reed_floats"):return
	var late: Dictionary=c.state.duplicate(true)
	rights_branches(late,secret)
	coins=int(c.state.coins)
	var paid: Dictionary=c.settle_voyage_job(str(paired.id))
	check(bool(paid.ok) and int(paid.get("reward",0))==int(paired.reward),"Actual return report releases the original escrow once")
	check(int(c.state.coins)==coins+int(paired.reward),"Exactly the reserved fee reaches the player purse")
	check(not c.settle_voyage_job(str(paired.id)).ok,"The same actual report cannot be paid twice")
	check(int(c.state.wageArrears)==0 and paid_days==floori(float(c.state.day))-1 and paid_wages==paid_days*(sailors+count)*c.Goods.SAILOR_WAGE,"Whole actual voyage pays every elapsed daily crew wage without arrears")
	check(c.state.fleet.size()==1 and int(c.find_boat(hull_uid).crew)==sailors+count,"Actual voyage preserves its real hired player crew and hull")
	if not roundtrip("Returned completed voyage and one-time report"):return
	voyage_completed=true
	print("expedition057: actual receipt day=",c.state.day," playerCoins=",c.state.coins," paidDays=",paid_days," paidWages=",paid_wages," food=",c.state.cargo.food," kits=",stock_kits())

func _initialize() -> void:
	started_ms=Time.get_ticks_msec()
	print("expedition057: one seeded Campaign baseline; source-prepared public voyage")
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c=Campaign.new(world)
	voyage()
	check(voyage_completed,"The entire public voyage reaches its returned, saved, once-paid checkpoint")
	within_budget()
	print("expedition057: %d checks, %d failures; %.3fs"%[checks,failures,float(Time.get_ticks_msec()-started_ms)/1000.0])
	quit(0 if failures==0 else 1)
