extends SceneTree
## One bounded fixture; native UNRUN by this source-only seat.
const Builds=preload("res://scripts/workshop_builds048.gd")
const Refits=preload("res://scripts/refit.gd")
const Lab=preload("res://scripts/fleet_lab.gd")
const Battle=preload("res://scripts/battle.gd")
const Damage=preload("res://scripts/damage.gd")
const Records=preload("res://scripts/equipment_records.gd")
const Workshop=preload("res://scripts/fleet_workshop.gd")
const Economy=preload("res://scripts/economy.gd")
const Goods=preload("res://scripts/goods.gd")
const Money=preload("res://scripts/money.gd")
const TICKS: int=120
const DT: float=1.0/60.0
var checks: int=0
var failures: int=0

class CoreView extends RefCounted:
	var data: Dictionary
	var state: Dictionary
	func _init(w: Dictionary,s: Dictionary):data=w;state=s
	func hull(id: String) -> Dictionary:return Lab.hull(data,id)
	func find_boat(uid: String) -> Dictionary:
		for ship in state.fleet:
			if str(ship.uid)==uid:return ship
		return {}
	func current_port() -> Dictionary:return state.ports[0]

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("WORKSHOP BUILDS048: "+message)

func quote_context(world: Dictionary,base: Dictionary) -> CoreView:
	var ship: Dictionary=Damage.create_ship(base)
	ship.uid="builds048-quote"
	ship.loadout=Refits.defaults(base)
	var seeded: Dictionary=Records.initialize(ship,{"base":base.duplicate(true),"loadout":ship.loadout.duplicate(true),"catalog":Refits.catalog(),"identity":ship.uid})
	check(bool(seeded.get("ok",false)),"quote hull has real canonical equipment")
	Refits.ensure(ship,base)
	# Real world-created port stocks/workers/prices. An empty captain's purse
	# deliberately quotes unaffordable fits: no grants, rebalanced stock or pay.
	var port: Dictionary=Economy.create_port(world.PORTS[0])
	var state: Dictionary={"coins":0,"crewPurse":0,"wageArrears":0,"debt":0,"day":1.0,"econDay":1,"morale":85.0,"ports":[port],"fleet":[ship],"cargo":{},"path":[],"position":{"x":port.x,"y":port.y},"moneyLog":[]}
	state.coinSupply=Money.total(state)
	return CoreView.new(world,state)

func quoted(core: CoreView,example: Dictionary) -> Dictionary:
	var before: PackedByteArray=var_to_bytes(core.state)
	var draft_before: PackedByteArray=var_to_bytes(example)
	var q: Dictionary=Workshop.preview(core,str(core.state.fleet[0].uid),example.loadout)
	var label: String=str(example.id)
	check(bool(q.validDraft) and not bool(q.affordable) and not bool(q.applicable) and int(q.cost)>0 and not str(q.quoteId).is_empty(),"legal fit has a real payable bill, never free equipment: "+label)
	check(var_to_bytes(core.state)==before and var_to_bytes(example)==draft_before and Money.total(core.state)==int(core.state.coinSupply),"preview preserves every state/condition/stock/purse/draft byte: "+label)
	check(q.newLoadout==example.loadout and q.afterSpec.weaponMounts==Refits.effective_spec(core.hull(Builds.HULL_ID),example.loadout).weaponMounts,"quote uses actual normalized fitted mounts: "+label)
	check(int(q.cost)==int(q.materialCost)+int(q.workerWages)+int(q.expertWages)+int(q.tax)+int(q.margin) and int(q.cost)==int(q.businessIncome)+int(q.workerWages)+int(q.expertWages)+int(q.tax),"bill equals actual business, worker, expert and tax recipients: "+label)
	var paid: int=0
	var labor: float=0.0
	var experts: float=0.0
	var materials: Dictionary={}
	for change in q.changes:
		var bill: Dictionary=change.bill
		paid+=int(bill.cost);labor+=float(bill.workerDays);experts+=float(bill.expertDays)
		check(int(bill.workerWages)==int(ceil(float(bill.workerDays)*Goods.WAGES.shipwright)) and int(bill.expertWages)==int(ceil(float(bill.expertDays)*Goods.WAGES.engineer)),"real wage-day rates: "+label+"/"+str(change.slot))
		for good in bill.materials:materials[good]=float(materials.get(good,0.0))+float(bill.materials[good])
	check(paid==int(q.cost) and is_equal_approx(labor,float(q.workerDays)) and is_equal_approx(experts,float(q.expertDays)) and materials==q.materials,"all changed sockets share one aggregate bill and finite labor: "+label)
	for good in q.materials:
		check(float(q.materialAvailability[good])==float(core.current_port().stocks.get(good,0.0)) and float(q.materials[good])>0.0 and int(q.materialPrices[good])>0,"real scarce input availability/price: "+label+"/"+str(good))
	check(int(q.reserve.dailyWages)==int(core.state.fleet[0].crew)*Goods.SAILOR_WAGE and float(q.workforce.free)>=0.0 and float(q.workforce.freeExperts)>=0.0,"actual crew payroll and finite yard availability: "+label)
	print("WORKSHOP BUILDS048 bill ",label,": ",q.cost," coins; parts ",q.materialCost,", workers ",q.workerWages,", experts ",q.expertWages,", materials ",q.materials,", worker/expert days ",q.workerDays,"/",q.expertDays,"; empty purse remains unchanged")
	return q

func prefix(world: Dictionary,example: Dictionary) -> Dictionary:
	var player: Dictionary=Lab.entry(world,Builds.HULL_ID)
	player.loadout=example.loadout.duplicate(true)
	# Same hulls, seed, closing formation, enemy fit, terrain, stores and default
	# auto tactics every time. The descriptor's recommended role is NOT applied.
	var config: Dictionary={"player":[player],"enemy":[Lab.entry(world,"furnace_turret")],"formation":"closing"}
	var before: PackedByteArray=var_to_bytes(config)
	var made: Dictionary=Lab.create(world,config,48048)
	check(bool(made.get("ok",false)),"real public Lab start: "+str(example.id))
	if not bool(made.get("ok",false)):return {}
	var battle: Dictionary=made.battle
	var own: Dictionary=Battle.get_flagship(battle)
	var opening: Array=[]
	var starts: Dictionary={}
	var costs: Dictionary={}
	var spent: Dictionary={}
	check(battle.ships.size()==2 and battle.autopilot and battle.projectiles.is_empty() and battle.events.is_empty(),"two normally deployed boats, no opening manufactured fire")
	check(own.loadout==example.loadout and own.spec==Refits.effective_spec(Lab.hull(world,Builds.HULL_ID),example.loadout),"Lab uses the actual recommended normalized effective fit")
	for ship in battle.ships:
		var sid: String=str(ship.id)
		opening.append([sid,ship.x,ship.y,ship.angle,ship.vx,ship.vy])
		starts[sid]={"position":Vector2(ship.x,ship.y),"ammo":float(ship.ammo),"fuel":float(ship.fuel),"supplies":float(ship.supplies),"crew":float(ship.crew)}
		costs[sid]={};spent[sid]=0.0
		for mount in ship.spec.weaponMounts:costs[sid][str(mount.id)]=float(mount.ammoCost)
		check(bool(Records.snapshot(ship).get("ok",false)) and float(ship.ammo)==float(ship.spec.ammoCapacity) and float(ship.fuel)==120.0 and float(ship.supplies)==20.0 and float(ship.crew)==float(ship.spec.crewOptimal),"canonical crew/equipment and finite actual Lab birth stores: "+sid)
	var chronological: bool=true
	var finite: bool=true
	var previous_seq: int=0
	var shots: int=0
	for tick in range(TICKS):
		Battle.update(battle,DT,{})
		chronological=chronological and is_equal_approx(float(battle.time),float(tick+1)*DT)
		for event in Battle.pop_events(battle):
			chronological=chronological and int(event.seq)>previous_seq and float(event.time)>0.0 and float(event.time)<=float(battle.time)
			previous_seq=int(event.seq)
			if str(event.kind)!="fire":continue
			var source: String=str(event.sourceId)
			var mount_id: String=str(event.mountId)
			var actual: bool=costs.has(source) and costs.get(source,{}).has(mount_id)
			chronological=chronological and actual
			if actual:spent[source]+=float(costs[source][mount_id])
			if source==str(own.id):shots+=1
		for ship in battle.ships:
			for key in ["x","y","vx","vy","angle","hp","water","engine","crew","wounded","ammo","fuel","supplies"]:finite=finite and is_finite(float(ship[key]))
	check(chronological and finite and str(battle.tactical.manualId).is_empty(),"120 real 60Hz updates with ordinary AI, finite state and chronological events")
	for ship in battle.ships:
		var start: Dictionary=starts[str(ship.id)]
		check(is_equal_approx(float(start.ammo)-float(ship.ammo),float(spent[str(ship.id)])) and float(ship.ammo)>=0.0 and float(ship.fuel)>=0.0 and float(ship.fuel)<=float(start.fuel) and float(ship.supplies)>=0.0 and float(ship.supplies)<=float(start.supplies),"actual mount emissions explain all ammo debits; no stores refilled")
		check(bool(Damage.get_status(ship).get("equipmentOk",false)) and float(ship.crew)>=0.0 and float(ship.crew)<=float(start.crew) and float(ship.wounded)>=0.0 and float(ship.wounded)<=float(ship.crew),"actual condition remains valid and people finite")
	var origin: Dictionary=starts[str(own.id)]
	var result: Dictionary={"opening":opening,"position":Vector2(own.x,own.y),"distance":Vector2(own.x,own.y).distance_to(origin.position),"fuelSpent":float(origin.fuel)-float(own.fuel),"ammoSpent":float(spent[str(own.id)]),"shots":shots}
	check(shots>0 or float(result.distance)>0.01,"fitted boat genuinely fires or moves in bounded prefix")
	check(var_to_bytes(config)==before,"Lab and real prefix leave the draft/config bytes unchanged")
	print("WORKSHOP BUILDS048 prefix ",example.id,": ",TICKS," real ticks; shots ",shots,", ammo ",result.ammoSpent,", fuel ",result.fuelSpent,", displacement ",result.distance,"; no battle-outcome/motion/FPS verdict")
	return result

func run() -> void:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var original: PackedByteArray=var_to_bytes(world)
	var catalog: PackedByteArray=var_to_bytes(Refits.catalog())
	var base: Dictionary=Lab.hull(world,Builds.HULL_ID)
	var examples: Array=Builds.examples(base)
	check(examples.size()==3 and Builds.examples(Lab.hull(world,"tin_skiff")).is_empty(),"three supported-hull recommendations, no cross-hull template injection")
	if examples.size()!=3:quit(1);return
	var core: CoreView=quote_context(world,base)
	var models: Array=[]
	var quotes: Array=[]
	var prefixes: Array=[]
	var ids: Dictionary={}
	for example in examples:
		check(not ids.has(str(example.id)),"distinct recommendation IDs")
		ids[str(example.id)]=true
		var model: Dictionary=Builds.describe_fit(base,example.loadout)
		check(bool(model.get("ok",false)) and model.spec==Refits.effective_spec(base,example.loadout) and model.loadout==Refits.normalize(base,example.loadout).loadout and int(model.usedPoints)<=int(model.maxPoints),"real normalize/effective specs/socket budget agree")
		models.append(model);quotes.append(quoted(core,example));prefixes.append(prefix(world,example))
	check(models[0].handling.speed>models[2].handling.speed and models[2].handling.speed>models[1].handling.speed and models[0].handling.fuelUse>models[1].handling.fuelUse and models[1].handling.fuelUse>models[2].handling.fuelUse,"speed and fuel rankings conflict: no best engine for every goal")
	check(models[1].survival.armor>models[2].survival.armor and models[2].survival.armor>models[0].survival.armor and models[0].survival.hp==models[1].survival.hp and models[1].survival.pumps==models[2].survival.pumps,"protection trades speed; armor never invents hull health or pumps")
	check(models[0].range<models[1].range and models[2].range==models[1].range and models[2].mounts[0].arc<models[1].mounts[0].arc and models[1].mounts[0].arc<models[0].mounts[0].arc and models[2].mounts[0].ammoCost>models[1].mounts[0].ammoCost,"actual reach, traverse and shared ammo distinguish guns/cannon/tube")
	check(quotes[1].materials.iron>quotes[0].materials.iron and quotes[1].workerDays>quotes[0].workerDays and quotes[2].cost!=quotes[1].cost and quotes[0].cost!=quotes[1].cost and quotes[0].cost!=quotes[2].cost,"stronger protection/fire has real material/labor and distinct coin bills")
	if not prefixes.any(func(p):return p.is_empty()):
		check(prefixes[0].opening==prefixes[1].opening and prefixes[1].opening==prefixes[2].opening,"identical real seeded encounter openings")
		for pair in [[0,1],[0,2],[1,2]]:
			var a: Dictionary=prefixes[pair[0]]
			var b: Dictionary=prefixes[pair[1]]
			check(a.position.distance_to(b.position)>0.01 or not is_equal_approx(float(a.ammoSpent),float(b.ammoSpent)) or not is_equal_approx(float(a.fuelSpent),float(b.fuelSpent)),"each fit changes actual movement or finite store use in the same encounter")
	var untouched: PackedByteArray=var_to_bytes(examples)
	models[0].mounts[0].range=-1.0;models[0].spec.speed=-1.0
	check(var_to_bytes(examples)==untouched and var_to_bytes(world)==original and var_to_bytes(Refits.catalog())==catalog,"returned model edits and every preview/trial preserve source knowledge bytes")
	print("WORKSHOP BUILDS048: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
