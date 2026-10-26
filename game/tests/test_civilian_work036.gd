extends SceneTree
## One bounded campaign. Staged empty fixture hulls hire/pay actual local crews;
## every earning action then uses the public Campaign clock and transaction APIs.
const Campaign=preload("res://scripts/campaign.gd")
const Births=preload("res://scripts/equipment_lifecycle.gd")
const Money=preload("res://scripts/money.gd")
const Work=preload("res://scripts/civilian_work.gd")
const Jobs=preload("res://scripts/voyage_jobs.gd")
const Transport=preload("res://scripts/passenger_transport.gd")
const Manifest=preload("res://scripts/hold_manifest.gd")
const Navigation=preload("res://scripts/navigation.gd")
const Factions=preload("res://scripts/factions.gd")
var c
var checks: int=0
var failures: int=0
var fisher_uid: String=""
var carrier_uid: String=""
var supply: int=0

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL civilian036: "+message)

func close(a: float,b: float) -> bool:return absf(a-b)<0.0001

func people() -> int:
	var n: int=int(c.state.regionalCrises.lostPeople)
	for p in c.state.ports:
		n+=int(p.workforce)+int(p.get("defenses",{}).get("crew",0))
		for course in p.training.jobs:n+=int(course.reservedWorkers)
	for b in c.state.fleet+c.state.boardingPrizes:n+=int(b.crew)
	for o in c.state.fleetOwners:
		for b in o.boats:n+=int(b.crew)
	for business in c.state.businesses:n+=business.employees.size()
	for j in c.state.regionalCrises.jobs:n+=int(j.n)
	for j in c.state.voyageJobs:n+=int(j.get("passengers",{}).get("n",0))
	return n

func new_hull(id: String,crew: int) -> String:
	var h: Dictionary=c.hull(id)
	var staged: Dictionary=Births.stage_birth(c.state,c.data,h,"boat-%d"%int(c.state.nextUid),{})
	check(staged.ok,"canonical empty fixture birth: "+id)
	if not staged.ok:return ""
	var b: Dictionary=c.add_boat(h,0,staged)
	check(c.recruit_crew(str(b.uid),crew).ok,"finite paid sailors crew "+id)
	check(c.resupply_boat(str(b.uid),"voyage").ok,"physical purchased voyage stores: "+id)
	return str(b.uid)

func offer(kind: String) -> Dictionary:
	for j in Jobs.available(c):
		if j.kind==kind:return j
	return {}

func sail(target: Dictionary,id: String="") -> bool:
	var r: Dictionary=c.chart_course(target,id)
	if not r.ok:print("Course refused: "+str(r.message));return false
	for i in range(360):
		if c.state.path.is_empty():return true
		c.step(0.5)
	return c.state.path.is_empty()

func restore_checkpoint(snapshot: Dictionary,label: String) -> bool:
	var r: Dictionary=c.restore(JSON.parse_string(JSON.stringify(snapshot)))
	check(r.ok,label+": "+str(r.get("message","")))
	return bool(r.ok)

func _initialize() -> void:
	c=Campaign.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json")))
	check(c.new_game(3601).ok,"actual v036 career publishes")
	# This fixture isolates civilian transactions from unrelated NPC combat.
	for o in c.state.fleetOwners:o.active=false
	for p in c.state.patrols:p.active=false
	Money.move(c.current_port(),"governmentPurse",c.state,"coins",200000,"Finite civilian fixture capital",c.state.moneyLog)
	supply=Money.total(c.state)
	var census: int=people()
	fisher_uid=new_hull("brinehook_longliner",8)
	carrier_uid=new_hull("fenhopper_lighter",4)
	check(people()==census and Money.total(c.state)==supply,"fixture crews and working stores conserve people and all coins")
	if fisher_uid.is_empty() or carrier_uid.is_empty():finish();return
	fishing()
	if not sail(c.port_position("brass_haven"),"brass_haven"):check(false,"actual fishing boat returns to market");finish();return
	var p: Dictionary=c.current_port()
	var cash: int=int(c.state.coins);var port_cash: int=int(p.cash);var stocked: float=float(p.stocks.preserved_fish)
	var sold: Dictionary=c.trade("brass_haven","preserved_fish",1,"sell")
	check(sold.ok and c.state.coins>cash and p.cash<port_cash and close(float(p.stocks.preserved_fish),stocked+1),"ordinary catch sale uses actual buyer coins and increases port stock")
	check(Money.total(c.state)==supply,"catch sale mints no coins")
	fuel_delivery()
	charters()
	check(Money.total(c.state)==supply and people()==census,"all completed civilian actions retain actual people and circulating coins")
	finish()

func fishing() -> void:
	check(not c.start_fishing(fisher_uid,1.0,2).ok,"dockside catch refused")
	check(not c.start_fishing(carrier_uid,1.0,2).ok,"transport cannot impersonate fishing hull")
	var home: Dictionary=c.current_port();var point: Dictionary={}
	for delta in [Vector2(220,0),Vector2(-220,0),Vector2(0,220),Vector2(0,-220)]:
		var candidate: Dictionary={"x":float(home.x)+delta.x,"y":float(home.y)+delta.y}
		if Navigation.is_water(c.nav,candidate.x,candidate.y,18) and c.distance(candidate,home)>65:point=candidate;break
	check(not point.is_empty() and sail(point),"actual chart sailing reaches safe offshore working water")
	if point.is_empty():return
	check(not c.start_fishing(fisher_uid,0.0,2).ok and not c.start_fishing(fisher_uid,1.0,99).ok,"zero time and invented workers refused")
	var b: Dictionary=c.find_boat(fisher_uid)
	var fuel: float=float(b.fuel);var food: float=float(c.state.cargo.food);var fish: float=float(c.state.cargo.preserved_fish);var day: float=float(c.state.day)
	check(c.start_fishing(fisher_uid,1.0,8).ok,"real crew sets gear without instant production")
	check(close(float(c.state.cargo.preserved_fish),fish),"starting work grants no catch")
	c.step(c.DAY_SECONDS*0.25)
	var caught: float=float(c.state.cargo.preserved_fish)-fish
	check(close(float(c.state.day),day+0.25) and caught>0 and caught<=8.0*Work.catch_rate()*0.25+0.00001,"catch requires actual elapsed campaign clock and bounded existing crew labor")
	check(close(fuel-float(b.fuel),Work.fuel_rate(b)*0.25) and close(food-float(c.state.cargo.food),8.0*0.08*0.25),"real fishing burns the stated physical fuel and rations")
	var before: float=float(c.state.cargo.preserved_fish)
	Work.tick(c,0.25)
	check(close(before,float(c.state.cargo.preserved_fish)),"repeated same-clock tick cannot harvest again")
	var book: Dictionary=JSON.parse_string(JSON.stringify(c.state.civilianWork))
	check(restore_checkpoint(c.state.duplicate(true),"active fishing full JSON roundtrip") and c.state.civilianWork==book,"active site quota and work survive restore exactly in saved JSON representation")
	var bad: Dictionary=c.state.duplicate(true);bad.civilianWork.fishing[0].catch=1e6
	check(not c.restore(bad).ok,"fabricated unearned fishing work refused before publication")
	c.step(c.DAY_SECONDS*0.5)
	for amount in c.state.civilianWork.sites.values():check(float(amount)<=Work.SITE_QUOTA+0.00001,"shared site/day source remains finite")
	check(close(float(c.state.cargo.preserved_fish)-fish,Work.SITE_QUOTA),"actual crew work exhausts exactly the finite cell/day wild source")
	check(c.cancel_fishing(fisher_uid).ok,"cancellation recovers gear without erasing earned physical catch")
	check(not c.start_fishing(fisher_uid,1.0,8).ok,"recalling and restarting gear cannot reset the same site/day quota")
	before=float(c.state.cargo.preserved_fish);c.step(0.25)
	check(close(before,float(c.state.cargo.preserved_fish)) and c.cargo_weight()<=c.capacity()+0.00001,"cancelled work creates no extra catch or hold capacity")

func fuel_delivery() -> void:
	var owner: Dictionary=c.fleet_owner("patrol-1")
	var target: Dictionary=c.port(str(owner.homePort))
	owner.active=true;owner.atPort=str(target.id)
	# A finite needy-recipient setup returns every existing fuel drum to port stock.
	target.stocks.fuel=float(target.stocks.fuel)+float(owner.cargo.fuel);owner.cargo.fuel=0.0
	for b in owner.boats:target.stocks.fuel=float(target.stocks.fuel)+float(b.fuel);b.fuel=0.0
	var job: Dictionary=offer(Jobs.KIND_FUEL)
	check(not job.is_empty(),"actual needy fleet creates a sponsor-funded fuel offer")
	if job.is_empty():return
	var id: String=str(job.id);var qty: float=float(job.freight.qty)
	var p: Dictionary=c.current_port();var stock: float=float(p.stocks.fuel);var purse: int=int(p.governmentPurse)
	var relation: int=Factions.relation(c.state,str(p.faction),str(owner.faction))
	Factions.set_relation(c.state,str(p.faction),str(owner.faction),-70,"Focused hostile sponsor fixture")
	check(not Jobs.available(c).any(func(j):return j.kind==Jobs.KIND_FUEL and j.ownerId==owner.id) and not c.accept_voyage_job(id,carrier_uid).ok and close(float(p.stocks.fuel),stock) and int(p.governmentPurse)==purse,"treasury never offers or loads sponsor-funded enemy fuel")
	Factions.set_relation(c.state,str(p.faction),str(owner.faction),relation,"Restore actual fixture diplomacy")
	check(Jobs._fuel_allowed(c,p,{"faction":p.faction}),"same-faction fuel sponsorship retains existing legal trade")
	check(not c.accept_voyage_job(id,str(c.state.flagship)).ok and close(float(p.stocks.fuel),stock),"ineligible hull refusal does not consume stock or funding")
	check(c.accept_voyage_job(id,carrier_uid).ok,"actual transport loads the funded sealed fuel lot")
	check(close(float(p.stocks.fuel),stock-qty) and int(p.governmentPurse)==purse-int(job.reward)-int(job.materialInvoice),"real origin stock and finite treasury fund fuel plus escrow")
	check(close(float(c.state.cargoManifest.get(carrier_uid,{}).get("@job:"+id,0)),qty),"sealed lot occupies the actual selected carrier")
	check(not c.settle_voyage_job(id).ok and Money.total(c.state)==supply,"origin cannot claim recipient delivery fee")
	if not restore_checkpoint(c.state.duplicate(true),"sealed fuel full JSON roundtrip"):return
	check(sail(c.port_position(str(job.targetPort)),str(job.targetPort)),"actual transport sails to recipient harbor")
	owner=c.fleet_owner(str(job.ownerId))
	var receiver_fuel: float=0.0
	for b in owner.boats:receiver_fuel+=float(b.fuel)
	var wallet: int=int(c.state.coins)
	var sponsor: Dictionary=c.port(str(job.port))
	Factions.set_relation(c.state,str(sponsor.faction),str(owner.faction),-70,"War begins before actual receipt")
	check(not c.settle_voyage_job(id).ok and int(c.state.coins)==wallet and close(float(Jobs._find(c.state,id).freight.qty),qty),"changed hostility refuses actual receipt without paying or erasing sealed fuel")
	Factions.set_relation(c.state,str(sponsor.faction),str(owner.faction),relation,"Restore actual fixture diplomacy")
	check(c.settle_voyage_job(id).ok,"present needy NPC fleet receives its actual sealed fuel")
	var received: float=0.0
	for b in owner.boats:received+=float(b.fuel)
	check(close(received-receiver_fuel,qty) and int(c.state.coins)==wallet+int(job.reward),"sealed fuel becomes recipient operating fuel and sponsor pays exactly once")
	wallet=int(c.state.coins)
	check(not c.settle_voyage_job(id).ok and int(c.state.coins)==wallet and Money.total(c.state)==supply,"repeat fuel settlement cannot duplicate drums or coins")

func charters() -> void:
	var job: Dictionary=offer(Jobs.KIND_CHARTER)
	check(not job.is_empty(),"actual local workers and provisions produce a funded charter offer")
	if job.is_empty():return
	var census: int=people();var id: String=str(job.id)
	var n: int=int(job.passengers.n)
	var p: Dictionary=c.current_port();var workers: int=int(p.workforce);var food: float=float(p.stocks.food)
	check(not c.accept_voyage_job(id,fisher_uid).ok,"fishing hull cannot impersonate a charter transport")
	check(c.accept_voyage_job(id,carrier_uid).ok,"funded charter boards an existing counted cohort on one actual transport")
	check(int(p.workforce)==workers-n and float(p.stocks.food)<food and Transport.assigned(c.state,carrier_uid)==n,"real workers and bought provisions leave origin and occupy actual berths")
	check(people()==census and Money.total(c.state)==supply,"charter fee and travelers' existing savings remain in counted escrow")
	check(not c.recruit_crew(carrier_uid,Transport.spare(c,c.find_boat(carrier_uid))+1).ok and not c.toggle_storage(carrier_uid).ok,"reserved passenger berths cannot be hired or stored again")
	check(not c.settle_voyage_job(id).ok,"stationary origin cannot settle a passenger charter")
	if not restore_checkpoint(c.state.duplicate(true),"boarded people, savings, food and route evidence roundtrip"):return
	var target: Dictionary=c.port(str(job.targetPort));workers=int(target.workforce)
	check(sail(c.port_position(str(job.targetPort)),str(job.targetPort)),"charter physically sails its real water route")
	var active: Dictionary=Jobs._find(c.state,id)
	check(float(active.foodConsumed)>0 and float(active.voyageDistance)>0 and int(active.escrow)==int(active.reward)+int(active.savingsHousehold)+int(active.savingsExpert),"observed sailing consumes actual cohort food while fee and savings remain escrowed")
	var wallet: int=int(c.state.coins)
	check(c.settle_voyage_job(id).ok,"physical destination receives the existing passenger cohort and its savings")
	check(int(target.workforce)==workers+n and int(c.state.coins)==wallet+int(job.reward) and people()==census,"arrival pays only funded fee and conserves every person")
	check(not c.settle_voyage_job(id).ok and Money.total(c.state)==supply,"completed charter cannot be paid or discharged twice")
	job=offer(Jobs.KIND_CHARTER)
	check(not job.is_empty(),"destination can sponsor one further finite charter")
	if job.is_empty():return
	id=str(job.id);p=c.current_port()
	check(c.accept_voyage_job(id,carrier_uid).ok,"second funded cohort boards for bounded cancellation/loss cases")
	var checkpoint: Dictionary=c.state.duplicate(true)
	active=Jobs._find(c.state,id);active.deadlineDay=float(c.state.day)+0.001
	var sponsor: int=int(p.governmentPurse);n=int(active.passengers.n)
	c.step(0.5);active=Jobs._find(c.state,id)
	check(active.state==Jobs.STATE_EXPIRED and int(p.governmentPurse)==sponsor+int(active.reward) and int(active.escrow)==int(active.savingsHousehold)+int(active.savingsExpert),"actual elapsed expiry refunds sponsor fee while keeping real people and their savings aboard")
	check(Transport.assigned(c.state,carrier_uid)==n and c.settle_voyage_job(id,true).ok and people()==census,"safe abandonment discharges existing passengers, savings and remaining food at a real harbor")
	if not restore_checkpoint(checkpoint,"pre-expiry checkpoint for actual carrier-loss branch"):return
	active=Jobs._find(c.state,id);n=int(active.passengers.n)
	var lost: int=int(c.state.regionalCrises.lostPeople);var lost_purse: int=int(c.state.regionalCrises.lostPurse)
	var savings: int=int(active.savingsHousehold)+int(active.savingsExpert)
	c.find_boat(carrier_uid).sunk=true;Work.tick(c,0.0)
	check(int(c.state.regionalCrises.lostPeople)==lost+n and int(c.state.regionalCrises.lostPurse)==lost_purse+savings,"lost actual carrier moves its cohort and savings to existing explicit loss custody")
	Work.tick(c,0.0)
	check(int(c.state.regionalCrises.lostPeople)==lost+n and not c.settle_voyage_job(id).ok and Money.total(c.state)==supply,"loss cannot repeat or claim a successful charter fee")
	if restore_checkpoint(checkpoint,"surviving fixture checkpoint remains valid"):c.settle_voyage_job(id,true)

func finish() -> void:
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
