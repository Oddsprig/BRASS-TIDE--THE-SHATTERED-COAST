extends SceneTree
## One bounded current career, six public quotes and one real escrow transaction.
## Empty canonical fixture shells hire actual paid crew; no clock/playthrough.
const Campaign=preload("res://scripts/campaign.gd")
const Guidance=preload("res://scripts/campaign_guidance.gd")
const Expedition=preload("res://scripts/expedition.gd")
const Exploration=preload("res://scripts/exploration.gd")
const Jobs=preload("res://scripts/voyage_jobs.gd")
const Money=preload("res://scripts/money.gd")
const Births=preload("res://scripts/equipment_lifecycle.gd")
const Work=preload("res://scripts/civilian_work.gd")
const Transport=preload("res://scripts/passenger_transport.gd")
const Economy=preload("res://scripts/economy.gd")
const Navigation=preload("res://scripts/navigation.gd")
var c
var checks: int=0
var failures: int=0
var records: Array=[]

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL career balance038: "+message)

func close(a: float,b: float) -> bool:return absf(a-b)<0.0001

func read_plan(id: String) -> Dictionary:
	var before: Dictionary=c.state.duplicate(true);var world: Dictionary=c.data.duplicate(true)
	var cache: Dictionary=c.route_cache.duplicate(true);var events: Array=c.events.duplicate(true);var pending: int=c.pending_days
	var report: Dictionary=Guidance.report(c,0.0,id)
	var p: Dictionary=report.get("careerPlan",{})
	check(report.ok and p.get("id","")==id and not str(p.get("firstGoal","")).is_empty() and not p.get("requirements",[]).is_empty(),id+": actual first goal and entry requirements")
	check(c.state==before and c.data==world and c.route_cache==cache and c.events==events and c.pending_days==pending,id+": report preserves full state, world, route cache and pending work")
	if p.is_empty():return p
	check(int(p.operatingCosts.dailyWages)==int(Expedition.report(c.state,c.data).dailyWages) and close(float(p.operatingCosts.wageCoins),ceilf(float(p.operatingCosts.days)*float(p.operatingCosts.dailyWages))),id+": actual full-fleet 100-coin payroll and return allowance")
	check(not str(p.rewardSource).is_empty() and not str(p.nextStep).is_empty() and not str(p.operatingCosts.summary).is_empty() and not str(p.limits).is_empty(),id+": concrete reward source, cost quote, next step and limits")
	records.append(p.duplicate(true))
	return p

func offered(id: String) -> Dictionary:
	for j in Jobs.available(c):
		if str(j.id)==id:return j
	return {}

func add_empty_shell(id: String,count: int) -> String:
	var h: Dictionary=c.hull(id)
	var staged: Dictionary=Births.stage_birth(c.state,c.data,h,"boat-%d"%int(c.state.nextUid),{})
	check(staged.ok,"canonical empty fixture shell: "+id)
	if not staged.ok:return ""
	var b: Dictionary=c.add_boat(h,0,staged)
	check(c.recruit_crew(str(b.uid),count).ok and c.resupply_boat(str(b.uid),"voyage").ok,"existing paid sailors and actual purchased stores: "+id)
	return str(b.uid)

func _initialize() -> void:
	c=Campaign.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json")))
	check(c.new_game(3801).ok,"current campaign publishes")
	if c.state.is_empty():finish();return
	var explorer: Dictionary=read_plan("explorer")
	var survey: Dictionary=offered(str(explorer.get("quote",{}).get("id","")))
	check(not survey.is_empty() and int(explorer.quote.rewardCoins)==int(survey.reward),"explorer uses the actual finite treasury survey offer")
	if not survey.is_empty():
		var chart: Dictionary=Exploration.quote(c.state,str(survey.siteId),"chart")
		var landed: Dictionary=Exploration.quote(c.state,str(survey.siteId),"survey")
		check(close(float(explorer.operatingCosts.workDays),float(chart.days)+float(landed.days)) and close(float(explorer.operatingCosts.workKits),float(chart.supplies)+float(landed.supplies)),"survey allowance includes real chart+landed work, provisions and three kits")
	var merchant: Dictionary=read_plan("merchant")
	var freight: Dictionary=offered(str(merchant.get("quote",{}).get("id","")))
	check(not freight.is_empty() and int(merchant.quote.rewardCoins)==int(freight.reward) and merchant.quote.freight==freight.freight,"merchant quotes the actual funded lot and fee")
	check(int(merchant.marketQuote.sellCoins)<int(merchant.marketQuote.buyCoins) and int(merchant.marketQuote.buyerCash)==int(c.current_port().cash),"local trading spread and buyer purse do not promise riskless profit")
	var privateer: Dictionary=read_plan("privateer")
	var bounty: Dictionary=offered(str(privateer.get("quote",{}).get("id","")))
	check(not bounty.is_empty() and int(privateer.quote.rewardCoins)==int(bounty.reward) and int(privateer.operatingCosts.boardingAdvanceCoins)==2000,"privateer uses funded named-raider bounty and actual optional boarder advance")
	# Reposition two existing actors only to quote the actual observed escort path.
	var convoy: Dictionary={};var raider: Dictionary={};var home: Dictionary=c.current_port()
	for owner in c.state.fleetOwners:
		if owner.kind=="trader" and convoy.is_empty():convoy=owner
		if owner.kind=="raider" and str(owner.id).begins_with("patrol-") and raider.is_empty():raider=owner
	for p in c.state.patrols:
		if p.id==convoy.get("id","") or p.id==raider.get("id",""):p.x=float(home.x)+200;p.y=float(home.y)
	var escort: Dictionary=read_plan("escort")
	check(escort.quote.get("ownerId","")==convoy.get("id","missing") and not escort.quote.get("carrierUids",[]).is_empty() and int(escort.quote.rewardCoins)==0 and int(escort.quote.standing)==5,"real loaded escort offers standing and service, never invented coins")
	if not freight.is_empty():
		var total: int=Money.total(c.state);var treasury: int=int(home.governmentPurse);var business: int=int(home.cash)
		check(c.accept_voyage_job(str(freight.id)).ok,"actual public freight acceptance reserves finite reward and physical lot")
		var held: Dictionary=Jobs._find(c.state,str(freight.id))
		check(int(held.get("escrow",0))==int(freight.reward) and int(home.governmentPurse)==treasury-int(freight.reward)-int(freight.materialInvoice) and int(home.cash)==business+int(freight.materialInvoice) and Money.total(c.state)==total,"quoted reward and invoice reconcile real sponsor, business and escrow purses")
		check(not c.settle_voyage_job(str(freight.id)).ok and c.settle_voyage_job(str(freight.id),true).ok and Money.total(c.state)==total,"no origin payout; ordinary abandonment refunds and preserves coins")
	var fisher_entry: Dictionary=Guidance.report(c,0.0,"fisher").careerPlan
	check(not fisher_entry.ready and fisher_entry.has("entryHull") and int(fisher_entry.entryHull.commissionCoins)>0 and int(fisher_entry.entryHull.crewAdvanceCoins)>0,"missing fishing hull shows actual local paid entry rather than hiding career")
	Money.move(home,"governmentPurse",c.state,"coins",200000,"Finite career fixture capital for paid civilian crew/stores",c.state.moneyLog)
	var supply: int=Money.total(c.state)
	var fish_uid: String=add_empty_shell("brinehook_longliner",8)
	var transport_uid: String=add_empty_shell("fenhopper_lighter",4)
	check(Money.total(c.state)==supply,"fixture crew advances and working-store purchases conserve circulating coins")
	if fish_uid.is_empty() or transport_uid.is_empty():finish();return
	var fisher: Dictionary=read_plan("fisher")
	check(close(float(fisher.quote.catchPerCrewDay),Work.catch_rate()) and float(fisher.quote.catchCeiling)<=Work.SITE_QUOTA and float(fisher.quote.catchCeiling)<=float(fisher.quote.freeBoatHold) and close(float(fisher.quote.fuelPerWorkDay),Work.fuel_rate(c.find_boat(fish_uid))),"one fishing day uses actual labor, site quota, fuel and physical hold limits")
	check(int(fisher.quote.saleCeilingCoins)<=int(home.cash) and int(fisher.quote.sellUnitCoins)==Economy.price(home,"preserved_fish","sell") and not fisher.ready,"catch sale uses a real buyer and dockside gear remains unavailable")
	var passenger: Dictionary=read_plan("passenger")
	var charter: Dictionary=offered(str(passenger.get("quote",{}).get("id","")))
	check(not charter.is_empty() and int(passenger.quote.rewardCoins)==int(charter.reward),"passenger uses one actual funded charter quote")
	if not charter.is_empty():
		var q: Dictionary=Transport.charter_quote(c,str(charter.port),str(charter.targetPort),int(charter.passengers.n),str(charter.carrierUid))
		check(not q.is_empty() and passenger.quote.carrierUid==q.carrierUid and close(float(passenger.quote.passengerFood),float(q.charterFood.food)) and int(passenger.quote.passengers)<=Transport.spare(c,c.find_boat(str(q.carrierUid))),"actual single carrier, paid provisions and real spare berths agree")
		check(int(passenger.quote.passengerSavingsCoins)==int(q.savingsHousehold)+int(q.savingsExpert) and "not captain revenue" in str(passenger.rewardSource),"passenger savings are distinct from the earning fee")
	check(Money.total(c.state)==supply and c.state.voyageJobs.is_empty() and float(c.state.day)==1.0,"all quote work leaves jobs, purses and campaign time unchanged")
	finish()

func finish() -> void:
	var folder: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		var file=FileAccess.open(folder.path_join("CAREER BASIS v0.038.json"),FileAccess.WRITE)
		check(file!=null,"six-quote balance artifact opens")
		if file!=null:file.store_string(JSON.stringify({"basis":"Actual starter fleet for explorer/merchant/escort/privateer; paid crews on explicit empty canonical fixture shells for fisher/passenger. No career clock advance. All allowances name the actual full traveling fleet and paid inactive crew. No numerical economy change justified by these single-action quotes.","careers":records},"\t"));file.close()
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
