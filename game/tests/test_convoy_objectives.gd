extends SceneTree
## Focused v0.032 fixture. Terminal placements exercise the actual objective;
## a short real update prefix separately checks helm authority and movement.
const B=preload("res://scripts/battle.gd")
const O=preload("res://scripts/battle_objectives.gd")
const D=preload("res://scripts/damage.gd")
const C=preload("res://scripts/campaign.gd")
const Boarding=preload("res://scripts/boarding.gd")
const SPEC={"id":"skiff","name":"Fixture boat","hp":130,"armor":1,"crewMin":2,"crewOptimal":5,"crewMax":7,"cargo":30,"size":16,"speed":100,"turn":2,"pumps":1,"weapon":"gun","damage":12,"fireRate":2,"range":550}
var checks: int=0
var failures: int=0

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL convoy: ",message)

func boat(uid: String) -> Dictionary:
	return D.create_ship(SPEC,{"uid":uid,"ammo":0.0})

func encounter(kind: String="escort",count: int=1,exit: Dictionary={}) -> Dictionary:
	var carriers: Array=[]
	var cargo: Dictionary={}
	for i in range(count):
		var ship: Dictionary=boat("cargo-%d"%i)
		carriers.append(ship);cargo[ship.uid]={"timber":4.0}
	var mission: Dictionary={"kind":kind,"carrierTeam":"player" if kind=="escort" else "enemy","carrierUids":carriers.map(func(b):return b.uid),"carrierCargo":cargo,"duration":45.0}
	if not exit.is_empty():mission.exit=exit
	if kind=="escort":mission.allyUids=mission.carrierUids.duplicate()
	return B.create({"fleet":carriers+[boat("own")] if kind=="escort" else [boat("own")],"enemyFleet":[boat("enemy")] if kind=="escort" else carriers,"mission":mission,"seed":32})

func carrier(st: Dictionary,index: int=0) -> Dictionary:
	return st.convoy.actors[st.convoy.uids[index]]

func at_exit(st: Dictionary,ship: Dictionary) -> void:
	ship.x=st.convoy.exit.x;ship.y=st.convoy.exit.y

func pure_objectives() -> void:
	var st: Dictionary=encounter()
	var load: Dictionary=carrier(st)
	check(st.get("startError","").is_empty() and st.deployment.player<=300,"Loaded carrier and own escort deploy together")
	check(load.order=="move" and load.orderTarget.x==2180.0,"Player carrier initially crosses toward authored far exit")
	check(st.ships.any(func(b):return b.uid=="own" and b.order=="escort"),"Combat boat initially escorts the real carrier")
	st.time=90.0;O.update(st)
	check(st.result==null and not st.get("objectiveSuccess",false),"Waiting beyond old 45-second timer cannot complete passage")
	B.issue_order(st,[load.id],"hold");O.update(st)
	check(load.order=="hold" and st.result==null,"Player hold command keeps authority over convoy autopilot")
	for ship in st.ships:
		if ship.team=="enemy":ship.sunk=true;ship.hp=0
	B.update(st,1.0/30.0)
	check(st.result==null,"Destroying all interceptors does not replace the physical exit objective")
	at_exit(st,load);load.x+=float(st.convoy.exit.radius)-float(load.spec.size)+1.0;O.update(st)
	check(st.result==null,"The whole hull must enter the authored exit radius")
	at_exit(st,load);O.update(st)
	check(st.result=="won" and st.objectiveSuccess,"Actual carrier exit completes escort")
	check(not load.sunk and st.escapedShips.size()==1 and is_same(st.escapedShips[0],load) and not st.ships.has(load),"Escape preserves the same living hull outside combat targeting")
	check(B.objective_snapshot(st).escaped==1 and "Exit" in O.label(st),"HUD reports physical escape")
	st=encounter();load=carrier(st)
	for ship in st.ships:
		if ship.uid=="own":ship.x=300.0;ship.y=600.0
		if ship.team=="enemy":ship.x=1900.0;ship.y=400.0;ship.order="hold";ship.orderTarget={"x":1900.0,"y":400.0}
	var origin: Vector2=Vector2(load.x,load.y)
	for i in range(12):B.update(st,1.0/30.0)
	check(Vector2(load.x,load.y).distance_to(origin)>0.01 and load.x>origin.x,"Short real battle prefix moves the carrier toward the exit")
	st=encounter();load=carrier(st);at_exit(st,load);load.sunk=true;load.hp=0;O.update(st)
	check(st.result=="lost" and st.escapedShips.is_empty() and B.objective_snapshot(st).sunk==1,"A sunk carrier at the exit fails and cannot escape")
	st=encounter("intercept");load=carrier(st)
	check(load.order=="move" and load.orderTarget.x==120.0,"Intercepted enemy carrier crosses toward opposite authored exit")
	at_exit(st,load);O.update(st)
	check(st.result=="lost" and not load.sunk and B.objective_snapshot(st).escaped==1,"Escaped interceptor target stays alive; interception fails")
	st=encounter("intercept");load=carrier(st);load.sunk=true;load.hp=0;O.update(st)
	check(st.result=="won" and B.objective_snapshot(st).sunk==1,"Actually sinking the loaded target completes interception")
	st=encounter("intercept");load=carrier(st);load.captureSecured=true;load.team="player";st.captured=[load];at_exit(st,load);O.update(st)
	check(st.result=="won" and st.escapedShips.is_empty() and B.objective_snapshot(st).captured==1,"A secured prize is captured rather than escaped")
	st=encounter("escort",2);at_exit(st,carrier(st,0));carrier(st,1).sunk=true;carrier(st,1).hp=0;O.update(st)
	check(st.result=="lost" and B.objective_snapshot(st).partial and B.objective_snapshot(st).escaped==1,"Mixed physical carrier fates retain partial outcome without full credit")
	st=encounter("escort",2)
	var follower: Dictionary=st.ships.filter(func(b):return b.uid=="own")[0]
	var attacker: Dictionary=st.ships.filter(func(b):return b.uid=="enemy")[0]
	at_exit(st,carrier(st,0));O.update(st)
	check(follower.orderTarget.shipId==carrier(st,1).id and attacker.orderTarget.shipId==carrier(st,1).id,"Unchanged automatic escorts and attackers retarget the next physical carrier")
	st=encounter("escort",2);follower=st.ships.filter(func(b):return b.uid=="own")[0]
	B.issue_order(st,[follower.id],"hold");var revision: int=int(follower.orderRevision)
	at_exit(st,carrier(st,0));O.update(st)
	check(follower.order=="hold" and int(follower.orderRevision)==revision,"Mission retarget never overwrites an explicit player revision")
	st=encounter("escort",2);follower=st.ships.filter(func(b):return b.uid=="own")[0]
	st.autopilot=false;revision=int(follower.orderRevision)
	at_exit(st,carrier(st,0));O.update(st)
	check(int(follower.orderRevision)==revision,"Manual flagship keeps authority when its automatic leader exits")
	st=encounter();load=carrier(st);load.engine=0.0;load.fuel=0.0;load.supplies=0.0
	B.retreat(st);st.retreatTimer=0.01;B.update(st,1.0/30.0)
	check(st.result=="retreated" and B.objective_snapshot(st).stranded==1 and not st.get("objectiveSuccess",false),"A disabled stranded carrier permits withdrawal without an automatic objective win")
	st=encounter("escort",1,{"x":950.0,"y":200.0,"radius":70.0})
	check(not str(st.get("startError","")).is_empty(),"Land-covered authored exit refuses start")
	var heavy: Dictionary=boat("heavy");heavy.spec.deploymentPoints=300
	st=B.create({"fleet":[heavy,boat("own")],"enemyFleet":[boat("enemy")],"mission":{"kind":"escort","carrierUids":["heavy"],"allyUids":["heavy"]}})
	check(not str(st.get("startError","")).is_empty(),"Carrier consuming all 300 points cannot silently reserve the own escort")
	st=B.create({"fleet":[boat("own")],"enemyFleet":[heavy,boat("other")],"mission":{"kind":"intercept","carrierUids":["heavy","other"]}})
	check(not str(st.get("startError","")).is_empty(),"Required carrier cannot silently fall into reserves")

func campaign_custody() -> void:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var c=C.new(world);c.new_game(3201)
	c.use_reserves()
	var owner: Dictionary=c.fleet_owner("patrol-1")
	var home: Dictionary=c.port(str(owner.homePort))
	var good: String="timber"
	var qty: float=minf(10.0,float(home.stocks[good]))
	home.stocks[good]-=qty;owner.cargo[good]+=qty;owner.tradeGood=good;owner.tradeCargo=qty
	var context: Dictionary=c.EscortOps.prepare_intercept(c,{"kind":"patrol","id":owner.id,"ownerId":owner.id,"name":"Fixture loaded interception"})
	check(context.has("mission") and not context.has("startError") and qty>0,"Actual owner goods form a physical interception mission")
	if not context.has("mission") or context.has("startError"):return
	var coins: int=c.Money.total(c.state)
	var purse: int=int(c.state.coins)
	var own_cargo: Dictionary=c.state.cargo.duplicate(true)
	var convoy_cargo: Dictionary=owner.cargo.duplicate(true)
	var patrol: Dictionary=c.NavalAI._find_patrol(c.state,str(owner.id))
	var chart_position: Vector2=Vector2(patrol.x,patrol.y)
	var st: Dictionary=B.create({"fleet":c.FleetSupport.combat(c),"enemyFleet":owner.boats.filter(func(b):return not b.sunk),"mission":context.mission,"seed":3201})
	var conditions: Dictionary={}
	for uid in st.convoy.uids:
		conditions[uid]=st.convoy.actors[uid].moduleCondition.duplicate(true);at_exit(st,st.convoy.actors[uid])
	O.update(st)
	var report: Dictionary=c.battle_settled(str(st.result),owner.boats.map(func(b):return b.spec),context,st)
	check(report.get("ok",true) and report.get("convoy",{}).get("escaped",0)==conditions.size(),"Real campaign settles actual carrier escapes")
	check(owner.cargo==convoy_cargo and c.state.cargo==own_cargo and c.state.coins==purse and c.Money.total(c.state)==coins,"Escape creates no cargo or purse award and keeps finite owner goods")
	check(owner.active and Vector2(patrol.x,patrol.y)==chart_position,"Escape neither destroys nor teleports the campaign voyage to delivery")
	check(c.state.wrecks.is_empty(),"Escaped live boats produce no wrecks")
	for b in owner.boats:
		if conditions.has(str(b.uid)):check(b.moduleCondition==conditions[b.uid] and not b.sunk,"Escaped hull preserves exact equipment condition")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Physical escaped outcome saves and restores through actual Campaign")
	owner=c.fleet_owner("patrol-1")
	check(c.state.get("lastConvoyOutcome",{}).get("escaped",0)==conditions.size() and owner.cargo==convoy_cargo,"Saved campaign retains escape fates and finite cargo")
	var checkpoint: Dictionary=c.state.duplicate(true)
	context=c.EscortOps.prepare_intercept(c,{"kind":"patrol","id":owner.id,"ownerId":owner.id,"name":"Fixture stopped interception"})
	st=B.create({"fleet":c.FleetSupport.combat(c),"enemyFleet":owner.boats.filter(func(b):return not b.sunk),"mission":context.mission,"seed":3202})
	for uid in st.convoy.uids:
		var ship: Dictionary=st.convoy.actors[uid];ship.sunk=true;ship.hp=0
	O.update(st)
	var boat_count: int=owner.boats.size()
	report=c.battle_settled(str(st.result),owner.boats.map(func(b):return b.spec),context,st)
	check(report.get("ok",true) and report.get("convoy",{}).get("sunk",0)==conditions.size(),"Interception settles only the actual sunk loaded carriers")
	var recovered: float=0.0
	for row in report.get("convoy",{}).get("carriers",[]):
		var wreck: Dictionary=c.Salvage.find_wreck(c.state,str(row.sourceWreckId))
		recovered+=float(wreck.get("stores",{}).get(good,0))
	check(is_equal_approx(recovered,qty*0.5) and is_zero_approx(float(owner.cargo[good])) and is_zero_approx(float(owner.tradeCargo)),"Finite per-carrier cargo moves once to matching wrecks at the existing 50 percent recovery fraction")
	check(c.state.coins==purse and c.Money.total(c.state)==coins and owner.boats.size()==boat_count,"Interception does not create coins or free replacement hulls")
	var sequence: int=int(c.state.battleSeq)
	var wreck_snapshot: Array=c.state.wrecks.duplicate(true)
	c.battle_settled(str(st.result),[],context,st)
	check(int(c.state.battleSeq)==sequence and c.state.wrecks==wreck_snapshot,"Repeated successful settlement cannot duplicate cargo, wrecks or engagement credit")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Finite wreck cargo and stopped convoy outcome survive actual save/load")
	check(c.restore(checkpoint).ok,"Restore the same finite loaded convoy for targeted prize and partial-fate branches")
	actual_prize(c)
	for hostile_present in [false,true]:
		check(c.restore(checkpoint).ok,"Restore finite inputs for physical-arena recovery guard")
		partial_recovery(c,hostile_present)

func actual_prize(c) -> void:
	var owner: Dictionary=c.fleet_owner("patrol-1")
	var context: Dictionary=c.EscortOps.prepare_intercept(c,{"kind":"patrol","id":owner.id,"ownerId":owner.id,"name":"Actual cargo prize"})
	var st: Dictionary=B.create({"fleet":c.FleetSupport.combat(c),"enemyFleet":owner.boats.filter(func(b):return not b.sunk),"mission":context.mission,"seed":3203})
	var target: Dictionary=carrier(st)
	var source: Dictionary=B.get_flagship(st)
	# Mark a subset of the existing crew as qualified for this custody fixture;
	# the separate academy fixture covers paid qualification and hiring.
	var party: int=mini(2,floori(float(source.crew)-float(source.crewMin)-float(source.wounded)))
	source.boarders=party
	source.x=520.0;source.y=850.0;target.x=550.0;target.y=850.0
	target.hp=target.maxHp*0.3;target.surrendering=true
	var goods: Dictionary=st.convoy.cargo[str(target.uid)].duplicate(true)
	var condition: Dictionary=target.moduleCondition.duplicate(true)
	var stores: Dictionary=store_totals(c,owner)
	var people: float=0.0
	for b in c.state.fleet+owner.boats:people+=float(b.crew)
	var launched: Dictionary=Boarding.launch(st,str(source.id),str(target.id),party)
	check(launched.ok,"Actual boarding launches existing sailors onto the loaded carrier")
	if not launched.ok:return
	Boarding.tick(st,4.1);O.update(st)
	check(target.get("captureSecured",false) and st.result=="won","Actual elapsed boarding secures the living loaded prize")
	var report: Dictionary=c.battle_settled(str(st.result),owner.boats.map(func(b):return b.spec),context,st)
	var uid: String=str(target.uid)
	var prize: Dictionary={}
	for b in c.state.fleet+c.state.boardingPrizes:
		if str(b.uid)==uid:prize=b;break
	check(report.get("ok",true) and not prize.is_empty() and is_same(prize,target) and prize.get("convoyCargo",{})==goods,"Cargo is attached to the actual published campaign prize object")
	if prize.is_empty():return
	check(not owner.boats.has(prize) and prize.moduleCondition==condition and store_totals(c,owner)==stores,"Capture handoff preserves parts and finite stores across the existing automatic reserve transfer")
	var after_people: float=float(c.state.captives)
	for b in c.state.fleet+c.state.boardingPrizes+owner.boats:after_people+=float(b.crew)
	check(is_equal_approx(after_people,people),"Prize crew and captured defenders reconcile to the same actual sailors")
	var held: float=float(prize.convoyCargo.get("timber",0))+float(owner.cargo.get("timber",0))
	check(is_equal_approx(held,float(goods.get("timber",0))) and c.state.wrecks.is_empty(),"Captured cargo remains entirely in actual prize plus original owner custody with no wreck duplicate")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Actual prize cargo and crew survive JSON restore")
	prize=c.find_boat(uid)
	check(not prize.is_empty() and prize.get("convoyCargo",{})==goods,"Restored campaign prize retains assigned cargo")
	var before: float=float(c.state.cargo.get("timber",0))
	var moved: Dictionary=c.EscortOps.take_prize_cargo(c,uid,"timber",1.0)
	check(moved.ok and is_equal_approx(float(prize.convoyCargo.timber),float(goods.timber)-1.0) and is_equal_approx(float(c.state.cargo.timber),before+1.0),"Recovering prize goods transfers finite custody within actual traveling hold capacity")
	var saved: Dictionary=c.state.duplicate(true)
	check(not c.EscortOps.take_prize_cargo(c,uid,"timber",float(goods.timber)+1.0).ok and c.state==saved,"Repeated over-claim cannot duplicate prize cargo")

func store_totals(c,owner: Dictionary) -> Dictionary:
	var out: Dictionary={"fuel":float(c.state.cargo.get("fuel",0)),"ammo":float(c.state.cargo.get("ammo",0))*50.0,"supplies":float(c.state.cargo.get("supplies",0))}
	for b in c.state.fleet+c.state.boardingPrizes+owner.boats:
		for good in out:out[good]+=float(b.get(good,0))
	return out

func partial_recovery(c,hostile_present: bool) -> void:
	var owner: Dictionary=c.fleet_owner("patrol-1")
	var context: Dictionary=c.EscortOps.prepare_intercept(c,{"kind":"patrol","id":owner.id,"ownerId":owner.id,"name":"Partial physical interception"})
	var a: Dictionary=owner.boats[0];var b: Dictionary=owner.boats[1]
	var qty: float=float(owner.cargo.timber)
	context.mission.carrierUids=[str(a.uid),str(b.uid)]
	context.mission.carrierCargo={str(a.uid):{"timber":qty*0.5},str(b.uid):{"timber":qty*0.5}}
	var enemies: Array=owner.boats.duplicate()
	if hostile_present:enemies.append(c.fleet_owner("patrol-0").boats[0])
	var st: Dictionary=B.create({"fleet":c.FleetSupport.combat(c),"enemyFleet":enemies,"mission":context.mission,"seed":3204})
	a.sunk=true;a.hp=0;at_exit(st,b);O.update(st)
	var report: Dictionary=c.battle_settled(str(st.result),enemies.map(func(s):return s.spec),context,st)
	var wreck: Dictionary=c.Salvage.find_wreck(c.state,str(report.wrecks[0].id))
	check(report.convoy.partial and owner.active and report.convoy.escaped==1,"Partial interception keeps escaped owner alive and records the separate sunk carrier")
	var recovered: Dictionary=c.recover_wreck(str(wreck.id),"strip","timber",1.0)
	check((not recovered.ok and "Hostiles still control" in str(recovered.get("message",""))) if hostile_present else recovered.ok,"Actual recovery is blocked only while hostile boats remain in the physical arena")

func _initialize() -> void:
	pure_objectives()
	campaign_custody()
	print("convoy objectives: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
