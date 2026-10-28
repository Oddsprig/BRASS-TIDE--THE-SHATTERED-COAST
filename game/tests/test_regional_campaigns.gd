extends SceneTree
## Root-reviewed tests: finite funding, actual deliveries, sustained progress and time-limited diplomacy.
const R=preload("res://scripts/regional_campaigns.gd")
const Rules=preload("res://scripts/regional_rules.gd")
const RO=preload("res://scripts/regional_orders.gd")
const Damage=preload("res://scripts/damage.gd")
const Money=preload("res://scripts/money.gd")
const Factions=preload("res://scripts/factions.gd")
const Home=preload("res://scripts/home_harbor.gd")
const WorkerOps=preload("res://scripts/worker_ops.gd")
const Economy=preload("res://scripts/economy.gd")
const RegionalOps=preload("res://scripts/regional_ops.gd")
class HarborCore:
	extends RefCounted
	var state: Dictionary
	func port(id: String) -> Dictionary:
		for p in state.ports:
			if p.id==id:return p
		return {}
var checks: int=0
var failures: int=0
func check(ok: bool,text: String):
	checks+=1
	if not ok:failures+=1;print("FAIL regional: "+text)
func boat(id: String) -> Dictionary:
	var b: Dictionary=Damage.create_ship({"id":id,"hp":80,"crewMin":1,"crewOptimal":3,"crewMax":4,"size":16,"speed":80,"cargo":20},{"crew":3,"fuel":8,"ammo":40})
	b.uid=id
	return b
func port(id: String,x: float,faction: String) -> Dictionary:
	return {"id":id,"name":id,"x":x,"y":0,"faction":faction,"industry":"trade","cash":1000,"householdPurse":100,"expertPurse":100,"governmentPurse":5000,"stocks":{"food":2,"fuel":2,"supplies":1,"ammo":1,"timber":1}}
func fresh() -> Dictionary:
	var s: Dictionary={"day":1,"coins":500,"crewPurse":0,"ports":[port("harbor",0,"compact"),port("mill",800,"forge"),port("reef",1600,"raiders")],"fleet":[],"fleetOwners":[],"patrols":[],"cargo":{"food":20,"timber":15},"position":{"x":0,"y":0},"path":[],"lastPort":"harbor","campaignFacts":{"goodsDelivered":0,"escortsSaved":0,"bountyWins":0,"licensedDesigns":0},"regionalFacts":{"deliveries":{},"passages":{}},"campaignFocus":{"fromPort":"harbor","toPort":"mill","portId":"harbor","peaceA":"compact","peaceB":"raiders"}}
	Factions.ensure(s,{})
	return s
func _initialize():
	funding_and_watch()
	harbor_development()
	diplomacy()
	survey_roundtrip()
	print("regional campaigns: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
func funding_and_watch():
	var s: Dictionary=fresh()
	var patrol: Dictionary={"id":"patrol","kind":"patrol","faction":"compact","homePort":"harbor","atPort":"harbor","active":true,"coins":100,"crewPurse":0,"boats":[boat("p-a"),boat("p-b")]}
	var raider: Dictionary={"id":"raider","kind":"raider","faction":"raiders","homePort":"reef","atPort":"","active":true,"coins":15,"crewPurse":0,"boats":[boat("r-a")]}
	s.fleetOwners=[patrol,raider];s.patrols=[{"id":"raider","x":20,"y":0,"active":true,"from":"reef","to":"harbor","progress":0.5}]
	Factions.adjust(s,"compact",25,"unit fixture earned standing")
	var total: int=Money.total(s)
	var ids: Array=s.fleetOwners.map(func(o):return o.id)
	R.available(s)
	check(Money.total(s)==total,"listing goals moves no money")
	var begun: Dictionary=R.start(s,"corridor")
	check(begun.ok and begun.funded==4200 and begun.ownerId=="patrol","two crews of three receive exactly seven wage-days")
	check(s.ports[0].governmentPurse==800 and patrol.coins==4300,"treasury and owner move equally")
	check(Money.total(s)==total and s.fleetOwners.map(func(o):return o.id)==ids and patrol.boats.size()==2,"funding preserves coins, owners and hulls")
	check(not R.start(s,"corridor").ok and patrol.coins==4300,"an active goal cannot fund twice")
	check(R.journal(s)[0].purpose=="upkeep" and R.journal(s)[0].funder=="harbor","funding cause and source are journaled")
	check(R.tick(s,0).is_empty(),"zero-time ticks do not advance")
	check(R.tick(s).is_empty(),"hostile corridor cannot complete")
	var op: Dictionary=s.regionalCampaigns.operations.corridor
	var unquoted: Dictionary=RO.plan(s,patrol,"harbor")
	check(not unquoted.ready and unquoted.hold and unquoted.destination=="harbor" and "route" in str(unquoted.reason),"a unit without live navigation holds for a real route-and-return quote")
	RO.arrival(s,patrol,s.ports[0]);RO.arrival(s,patrol,s.ports[0])
	check(op.patrolVisits==0,"repeated readings at the start are not passages")
	RO.arrival(s,patrol,s.ports[1]);RO.arrival(s,patrol,s.ports[1]);RO.arrival(s,patrol,s.ports[0])
	check(op.patrolVisits==2,"two different real endpoint arrivals are remembered once")
	raider.boats[0].fuel=0
	for i in range(6):
		s.day+=1
		check(R.tick(s).is_empty(),"clear day %d alone cannot finish early"%(i+1))
	check(op.clearDays==6,"six distinct days are six progress days")
	R.tick(s);R.tick(s)
	check(op.clearDays==6,"repeated same-day ticks cannot manufacture days")
	raider.boats[0].fuel=8;s.day+=1;R.tick(s)
	check(op.clearDays==0,"renewed threat resets consecutive clear days")
	raider.boats[0].fuel=0
	for i in range(6):s.day+=1;R.tick(s)
	s.day+=1
	var done: Array=R.tick(s)
	check(done.size()==1 and done[0].cause=="sustained-corridor","seven clear days plus actual visits finish once")
	check(R.tick(s).is_empty() and not R.start(s,"corridor").ok and Money.total(s)==total,"completed stable route neither pays nor repeats")
	s.campaignFocus.toPort="reef"
	check(R.available(s).filter(func(x):return x.id=="corridor")[0].ready,"a different corridor is a different stable goal")
	var neutral: Dictionary=fresh()
	neutral.fleetOwners=[patrol.duplicate(true),raider.duplicate(true)]
	neutral.fleetOwners[1].boats[0].fuel=8
	var before: int=int(neutral.ports[0].governmentPurse)
	check(R.start(neutral,"corridor").funded==0 and neutral.ports[0].governmentPurse==before,"neutral standing cannot requisition the treasury")
	var distant: Dictionary=fresh()
	distant.fleetOwners=[patrol.duplicate(true),raider.duplicate(true)];distant.position.x=5000
	Factions.adjust(distant,"compact",25,"unit fixture earned standing")
	check(R.start(distant,"corridor").funded==0,"government funding cannot be arranged remotely")
	var restart: Dictionary=fresh()
	restart.fleetOwners=[patrol.duplicate(true),raider.duplicate(true)]
	restart.patrols=[{"id":"raider","x":20,"y":0,"active":true,"from":"reef","to":"harbor","progress":0.5}]
	restart.fleetOwners[1].boats[0].fuel=8
	Factions.adjust(restart,"compact",25,"unit fixture earned standing")
	check(R.start(restart,"corridor").funded==4200,"restart fixture's actual local hostile justifies the original grant")
	var purse: int=restart.fleetOwners[0].coins
	check(R.cancel(restart,"corridor").ok and R.start(restart,"corridor").ok,"Optional watch can be withdrawn and chosen again")
	check(restart.fleetOwners[0].coins==purse and restart.ports[0].governmentPurse==800,"Withdrawal cannot farm or refund regional grants")
func harbor_development():
	var s: Dictionary=fresh()
	# Existing warehouse/staff and buyer cash are initial unit-fixture resources.
	# No Campaign/Main/world/nav construction; Home.tick runs real WorkerOps shifts.
	s.econDay=0;s.moneyLog=[]
	var p: Dictionary=s.ports[0]
	p.merge({"cash":10000,"workforce":2,"availableWorkers":2,"availableSpecialists":0,"publicStores":{}},true)
	var b: Dictionary={"id":"business-1","homePort":"harbor","kind":"warehouse","coins":1000,"paused":false,"employees":[{"id":"staff-1-0","name":"Ana","occupation":"laborer","wage":100,"specialist":false},{"id":"staff-1-1","name":"Piet","occupation":"laborer","wage":100,"specialist":false}],"wagesPaid":0}
	s.businesses=[b]
	var core=HarborCore.new()
	core.state=s
	Home.ensure(s);WorkerOps.ensure(core)
	var total: int=Money.total(s)
	check(not R.contribute(s,"harbor","timber",1).ok,"a closed goal refuses cargo")
	check(R.start(s,"harbor").ok,"harbor development starts")
	var op: Dictionary=s.regionalCampaigns.operations.harbor
	s.position.x=800
	var count: float=float(s.cargo.timber)+float(s.ports[0].stocks.timber)
	check(not R.contribute(s,"harbor","timber",3).ok and float(s.cargo.timber)+float(s.ports[0].stocks.timber)==count,"remote contribution refuses without moving stock")
	s.position.x=0
	check(not R.contribute(s,"harbor","timber",90).ok and s.cargo.timber==15,"oversized contribution is atomic")
	check(not R.contribute(s,"harbor","guns",1).ok,"nonaccepted materials are refused")
	var captain_before: int=int(s.coins)
	var buyer_before: int=int(p.cash)
	var sale: Dictionary=Economy.transact(p,s,"timber",6,"sell")
	check(sale.ok and sale.qty==6 and sale.total>0 and s.cargo.timber==9 and p.stocks.timber==7 and s.coins==captain_before+sale.total and p.cash==buyer_before-sale.total,"six sold lots move actual timber and buyer coins")
	# Publish only this successful physical sale, as the live trade adapter does.
	if sale.ok:RegionalOps.delivered(core,"harbor",float(sale.qty))
	var donation_purses: Array=[s.coins,p.cash,p.householdPurse,p.expertPurse,p.governmentPurse,b.coins]
	check(R.contribute(s,"harbor","timber",5).ok and s.cargo.timber==4,"six sold plus five donated physical lots reach the actual stock")
	check(R.tick(s).is_empty(),"deliveries alone do not create paid development")
	check(R.contribute(s,"harbor","timber",1).ok,"twelfth lot is delivered")
	check([s.coins,p.cash,p.householdPurse,p.expertPurse,p.governmentPurse,b.coins]==donation_purses and s.regionalFacts.deliveries.harbor==6 and op.contributed.timber==6,"six donated lots are unpaid and never become sold receipts")
	var view: Dictionary=Rules.harbor_view(s,op)
	check(view.deliveredLots==6 and view.donatedLots==6 and view.harborLots==12 and R.tick(s).is_empty(),"distinct six sold plus six donated lots add once and still require paid work")
	var wage_only: Dictionary=s.duplicate(true)
	wage_only.businesses[0].wagesPaid=600
	check(R.tick(wage_only).is_empty() and wage_only.regionalCampaigns.operations.harbor.staffDays==0,"editing three days of wage amounts alone earns no working days")
	var household_before: int=int(p.householdPurse)
	for i in range(2):
		Home.tick(core,1)
		# Match test_home_harbor.business_day: publish the completed shift's day.
		s.day+=1;s.econDay+=1
		check(b.paidWorkDays==i+1 and b.lastPaidWorkDay==s.econDay and b.labor.lastProcessedEconomicDay==s.econDay,"each actual paid shift records a distinct published working day")
		check(b.wagesPaid==(i+1)*200 and b.coins==1000-(i+1)*200 and p.householdPurse==household_before+(i+1)*200,"canonical payroll transfers two laborers' real daily wages")
		check(R.tick(s).is_empty() and op.staffDays==i+1,"two paid working days are not three")
		R.tick(s);R.tick(s)
		check(op.staffDays==i+1 and op.harborLots==12,"repeated goal ticks cannot duplicate working days or distinct deliveries")
	var restored: Variant=JSON.parse_string(JSON.stringify(s))
	check(restored is Dictionary,"harbor businesses and active progress survive JSON roundtrip")
	if not restored is Dictionary:return
	s=restored;core.state=s
	Home.ensure(s);R.ensure(s)
	p=core.port("harbor");b=s.businesses[0];op=s.regionalCampaigns.operations.harbor
	check(b.paidWorkDays==2 and b.lastPaidWorkDay==2 and b.labor.lastProcessedEconomicDay==2 and op.businessDays[b.id]==0 and op.staffDays==2 and Rules.harbor_view(s,op).harborLots==12,"reload preserves actual shift receipts, start baseline and both supply ledgers")
	check(R.tick(s).is_empty() and not R.start(s,"harbor").ok,"reload neither invents a third day nor restarts the active goal")
	Home.tick(core,1)
	s.day+=1;s.econDay+=1
	var done: Array=R.tick(s)
	check(done.size()==1 and done[0].cause=="paid-harbor-development" and b.paidWorkDays==3 and b.lastPaidWorkDay==3 and b.labor.lastProcessedEconomicDay==3 and op.staffDays==3,"three distinct actual paid working days and twelve lots complete development")
	check(b.coins==400 and b.wagesPaid==600 and p.householdPurse==household_before+600 and b.employees.map(func(e):return e.id)==["staff-1-0","staff-1-1"],"three canonical payrolls preserve exact employee identities and wage accounting")
	check(Money.total(s)==total and float(s.cargo.timber)+float(s.ports[0].stocks.timber)==count,"business pay and cargo conserve coins and timber")
	var finished: Dictionary=s.duplicate(true)
	check(not R.contribute(s,"harbor","timber",1).ok and not R.start(s,"harbor").ok and R.tick(s).is_empty(),"finished development does not consume or pay again")
	check(s==finished,"completed same-day refusal and progress reads leave money, stock, receipts and journal unchanged")
func diplomacy():
	var s: Dictionary=fresh()
	s.day=10
	Factions.adjust(s,"compact",25,"unit fixture earned mandate")
	check(not R.propose_peace(s,"compact","forge").ok,"peaceful factions are not rewritten")
	check(not R.propose_peace(s,"compact","raiders").ok,"hostility alone is not a treaty")
	check(R.start(s,"ceasefire").ok,"ceasefire goal starts without a commission")
	var total: int=Money.total(s)
	check(R.contribute(s,"ceasefire","food",5).ok,"five real food lots reach the first party")
	check(not R.propose_peace(s,"compact","raiders").ok,"one-sided relief cannot establish peace")
	s.position.x=5000
	check(not R.contribute(s,"ceasefire","food",5).ok,"relief cannot teleport from sea")
	s.position.x=1600
	check(not R.contribute(s,"ceasefire","food",5).ok,"hostile entry cannot donate through access gates")
	for i in range(3):Factions.adjust(s,"raiders",25,"unit fixture earned public reconciliation")
	Factions.adjust(s,"compact",25,"unit fixture renewed Compact mandate after reconciliation")
	check(R.contribute(s,"ceasefire","food",5).ok,"actual relief reaches the other accessible party")
	var op: Dictionary=s.regionalCampaigns.operations.ceasefire
	check(op.relief.compact==5 and op.relief.raiders==5 and s.cargo.food==10,"both relief receipts are physical and separate")
	check(not R.propose_peace(s,"compact","raiders").ok,"talks require elapsed days")
	s.day=12;R.tick(s)
	check(not R.propose_peace(s,"compact","raiders").ok,"two days are not three")
	var rep: Array=[Factions.standing(s,"compact").public,Factions.standing(s,"raiders").public]
	s.day=13;R.tick(s)
	var deal: Dictionary=R.propose_peace(s,"raiders","compact")
	check(deal.ok and deal.untilDay==43 and deal.cooldownUntil==73,"three-day talks produce a dated thirty-day treaty")
	check(Factions.relation(s,"compact","raiders")==0 and Factions.relation(s,"raiders","compact")==0,"one symmetric faction pair becomes neutral")
	check([Factions.standing(s,"compact").public,Factions.standing(s,"raiders").public]==rep,"treaty does not grant player reputation")
	check(not s.relationships.commission.committed and Money.total(s)==total,"no forced commission, coin gift or escrow")
	check(not R.propose_peace(s,"compact","raiders").ok and not R.start(s,"ceasefire").ok,"treaty and cooldown cannot be stacked")
	s.day=43
	var ended: Array=R.tick(s)
	check(ended.size()==1 and Factions.relation(s,"compact","raiders")==-40,"expiry restores the actual previous dispute")
	check(R.tick(s).is_empty(),"expiry is once only")
	s.day=73
	check(R.start(s,"ceasefire").ok,"fresh talks can start after the full cooldown")
	var rec: Dictionary=s.regionalCampaigns.peace["compact|raiders"]
	rec.active=true;rec.untilDay=74;Factions.set_relation(s,"compact","raiders",15,"a later independent accord")
	s.day=74;R.tick(s)
	check(Factions.relation(s,"compact","raiders")==15,"expiry never overwrites a later diplomatic change")
func survey_roundtrip():
	var s: Dictionary=fresh()
	s.exploration={"catalog":[{"id":"a","leadId":"b"},{"id":"b","leadId":"c"},{"id":"c","leadId":""}],"sites":{"a":{"level":3},"b":{"level":3},"c":{"level":2}}}
	check(R.start(s,"survey").ok and R.tick(s).is_empty(),"two surveyed links and a chart are not three full surveys")
	s.exploration.sites.c.level=3
	check(R.tick(s).size()==1 and not R.start(s,"survey").ok,"three connected full surveys complete once")
	var book=JSON.parse_string(JSON.stringify(s.regionalCampaigns))
	s.regionalCampaigns=book;R.ensure(s)
	check(R.tick(s).is_empty() and not R.start(s,"survey").ok,"roundtrip preserves completed IDs")
	check(not R.start(s,"conquest").ok and s.fleetOwners.is_empty(),"unknown goals never spawn fleets")
