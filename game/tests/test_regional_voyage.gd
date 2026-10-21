extends SceneTree
const Money=preload("res://scripts/money.gd")
const Home=preload("res://scripts/home_harbor.gd")
const R=preload("res://scripts/regional_campaigns.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,text: String):
	checks+=1
	if not ok:failures+=1;print("FAIL regional voyage: "+text)
func _initialize():
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("regional-voyage-fixture")
	scene.new_game();scene.set_process(false);scene.set_physics_process(false)
	var c=scene.core
	var p: Dictionary=c.current_port()
	check(c.state.regionalCampaigns.operations.is_empty(),"New career initializes an optional empty regional book")
	Money.move(p,"governmentPurse",c.state,"coins",50000,"Fixture finite business capital",c.state.moneyLog)
	var supply: int=Money.total(c.state)
	check(Home.establish(c,"warehouse",p.id).ok,"Actual local construction establishes the development's business")
	check(c.RegionalOps.start(c,"harbor").ok,"Real harbor goal starts at its selected physical port")
	check(c.trade(p.id,"timber",12,"buy").ok and c.RegionalOps.contribute(c,"harbor","timber",12).ok,"Real purchased timber enters harbor stock through the physical hold")
	for i in range(3):
		c.wait_day();scene.sync_economy()
		check(Money.total(c.state)==supply and scene.economy_task<0,"Published day %d joins workers and conserves every purse"%(i+1))
	check(c.state.businesses[0].wagesPaid==600 and c.state.regionalCampaigns.operations.harbor.status=="complete","Actual three daily payrolls finish developed-harbor proof")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	check(c.restore(saved).ok,"Actual save restores paid businesses, regional books, dates and facts")
	check(not c.RegionalOps.start(c,"harbor").ok,"Restored goal cannot complete or fund again")
	var protected: String=JSON.stringify(c.state)
	var bad: Dictionary=saved.duplicate(true);bad.regionalCampaigns.operations.harbor.clearDays=-1
	check(not c.restore(bad).ok and JSON.stringify(c.state)==protected,"Invalid negative regional progress is refused before live-state mutation")
	bad=saved.duplicate(true);bad.campaignFocus.portId="invented-harbor"
	check(not c.restore(bad).ok and JSON.stringify(c.state)==protected,"Unknown selected harbors are refused without changing the voyage")
	scene.ui.RegionalUI.open(scene.ui)
	check(scene.ui.modal_kind=="regional" and scene.ui.modal_open,"Actual regional UI builds selectors, progress, donations and history")
	scene.ui.close_modal()
	c.new_game(181)
	var offer: Dictionary={}
	for row in c.VoyageJobs.available(c):
		if row.kind=="freight" and c.Politics.access(c,c.port(row.targetPort)).legal:offer=row;break
	check(not offer.is_empty() and c.accept_voyage_job(offer.id).ok,"A funded compatible freight job carries real sealed goods")
	var total: int=Money.total(c.state)
	c.state.position=c.port_position(offer.targetPort) # arrival fixture: navigation has separate actual-voyage coverage
	check(c.settle_voyage_job(offer.id).ok,"Actual contract settlement supplies the destination")
	var delivered: int=int(c.state.campaignFacts.goodsDelivered)
	check(delivered==int(offer.freight.qty) and c.state.regionalFacts.passages.size()==1,"Actual freight settlement publishes destination quantity and the real port pair")
	check(not c.settle_voyage_job(offer.id).ok and c.state.campaignFacts.goodsDelivered==delivered and Money.total(c.state)==total,"Repeated settlement cannot manufacture progress, goods or coins")
	c.new_game(182)
	var owner: Dictionary={}
	for row in c.state.fleetOwners:
		if row.kind=="patrol" and not str(row.id).begins_with("story-"):owner=row;break
	var base: Dictionary=c.port(str(owner.homePort))
	c.state.position=c.port_position(base.id)
	c.state.campaignFocus.fromPort=base.id;c.state.campaignFocus.toPort="brass_haven" if base.id!="brass_haven" else "anvil_dock"
	c.Factions.adjust(c.state,base.faction,25,"Fixture earned patrol mandate")
	var patrol: Dictionary=c.NavalAI._find_patrol(c.state,owner.id)
	var position:=Vector2(float(patrol.x),float(patrol.y))
	var ids: Array=owner.boats.map(func(b):return b.uid)
	total=Money.total(c.state)
	var begun: Dictionary=c.RegionalOps.start(c,"corridor")
	check(begun.ok and int(begun.funded)>0 and str(begun.ownerId)==str(owner.id),"Actual Friendly harbor funds its existing patrol for an explicit operation")
	check(Money.total(c.state)==total and owner.boats.map(func(b):return b.uid)==ids,"Operation changes neither total coins nor existing hull identity")
	check(position.distance_to(Vector2(float(patrol.x),float(patrol.y)))<0.001 and not patrol.course.is_empty(),"Watch redirects from the actual sea position without teleporting")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Patrol assignment, funded purse and partially sailed route survive actual restore")
	c.new_game(183)
	owner=c.fleet_owner("patrol-1");patrol=c.NavalAI._find_patrol(c.state,owner.id)
	var destination: Dictionary=c.port("anvil_dock" if owner.homePort!="anvil_dock" else "brass_haven")
	Money.move(destination,"cash",destination,"governmentPurse",int(destination.cash),"Fixture no liquid buyer",c.state.moneyLog)
	var source: Dictionary=c.port(owner.homePort)
	source.stocks.fuel-=1;owner.cargo.fuel+=1;owner.tradeGood="fuel";owner.tradeCargo=1
	for b in owner.boats:b.fuel=0 # consumed-store fixture: held trading fuel will load into working tanks
	patrol.from=source.id;patrol.to=destination.id;patrol.progress=1;patrol.holding=false;patrol.active=true
	c.NavalLifecycle.step(c,0)
	check(c.state.regionalFacts.passages.is_empty(),"Loading held fuel into own tanks is not a merchant sale or delivered passage")
	check(float(owner.get("tradeDelivered",0))==0,"An illiquid buyer produces no successful sale receipt")
	Money.move(destination,"governmentPurse",destination,"cash",5000,"Fixture funded real buyer",c.state.moneyLog)
	source.stocks.fuel-=1;owner.cargo.fuel+=1;owner.tradeCargo=1
	patrol.from=source.id;patrol.to=destination.id;patrol.progress=1;patrol.holding=false;patrol.active=true
	c.NavalLifecycle.step(c,0)
	check(float(owner.get("tradeDelivered",0))==1 and c.state.regionalFacts.passages.size()==1,"Actual paid NPC sale records a real shipment between its two ports")
	scene.queue_free();await process_frame
	print("regional voyage: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
