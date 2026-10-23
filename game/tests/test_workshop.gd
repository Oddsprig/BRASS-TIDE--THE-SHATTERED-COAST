extends SceneTree
## Workshop contract fixtures. Engine execution belongs to the serialized root lease.
const W=preload("res://scripts/fleet_workshop.gd")
const R=preload("res://scripts/refit.gd")
const D=preload("res://scripts/damage.gd")
const E=preload("res://scripts/economy.gd")
const C=preload("res://scripts/construction.gd")
const G=preload("res://scripts/goods.gd")
const M=preload("res://scripts/money.gd")
const DP=preload("res://scripts/deployment.gd")
const X=preload("res://scripts/expedition.gd")
var world: Dictionary
var checks: int=0
var failures: int=0

class CoreView extends RefCounted:
	var data: Dictionary
	var state: Dictionary
	var at_sea: bool=false
	func _init(w: Dictionary,s: Dictionary):data=w;state=s
	func find_boat(uid: String) -> Dictionary:
		for b in state.fleet:
			if b.uid==uid:return b
		return {}
	func hull(id: String) -> Dictionary:
		for h in data.HULLS:
			if h.id==id:return h
		return {}
	func current_port() -> Dictionary:
		return {} if at_sea else state.ports[0]

func check(condition: bool,message: String):
	checks+=1
	if not condition:failures+=1;print("FAIL workshop: "+message)

func fixture(index: int=0) -> CoreView:
	var ship: Dictionary=D.create_ship(world.HULLS[index],{"hp":71.0,"crew":3.0,"wounded":1.0,"water":30.0,"engine":0.65,"ammo":17.0,"fuel":9.0,"supplies":6.0,"breaches":[{"area":10.0,"section":"bow"}]})
	ship.uid="workshop-owned";ship.mothballed=false
	R.ensure(ship,world.HULLS[index])
	ship.retainedMetadata={"paint":{"ownerMark":"test"},"opaqueHistory":["original","worn"]}
	var port: Dictionary=E.create_port(world.PORTS[0])
	port.workforce=100;port.workers=0;port.publicWorkers=0;port.availableWorkers=100
	port.specialists=20;port.availableSpecialists=20
	for good in G.ITEMS:port.stocks[good]=100.0
	C.begin_day(port)
	var cargo: Dictionary={}
	for good in G.ITEMS:cargo[good]=0.0
	var state: Dictionary={"coins":1000000,"crewPurse":0,"wageArrears":0,"debt":0,"day":1.0,"econDay":1,"morale":85.0,"ports":[port],"fleet":[ship],"cargo":cargo,"path":[],"position":{"x":port.x,"y":port.y},"moneyLog":[],"fitTemplates":[]}
	state.coinSupply=M.total(state)
	return CoreView.new(world,state)

func health(ship: Dictionary) -> Dictionary:
	var value: Dictionary={}
	for key in ["hp","maxHp","crew","wounded","water","capacity","engine","fire","ammo","fuel","supplies","breaches","sunk","retainedMetadata"]:
		value[key]=ship[key].duplicate(true) if ship[key] is Array or ship[key] is Dictionary else ship[key]
	return value

func proposed(c: CoreView) -> Dictionary:
	var fit: Dictionary=c.state.fleet[0].loadout.duplicate(true)
	fit.engine="boost_drive";fit.armor="scout_plating"
	return fit

func refusal(c: CoreView,fit: Dictionary,message: String,expected: Dictionary={}):
	var before: Dictionary=c.state.duplicate(true)
	var result: Dictionary=W.apply(c,c.state.fleet[0].uid,fit,expected)
	check(not result.ok and c.state==before,message)

func preview_and_bill():
	var c: CoreView=fixture()
	var before: Dictionary=c.state.duplicate(true)
	var draft: Dictionary=proposed(c)
	var q: Dictionary=W.preview(c,c.state.fleet[0].uid,draft)
	check(q.ok and q.validDraft and q.affordable and q.applicable,"valid affordable whole fitting is applicable")
	check(c.state==before and draft==proposed(c),"preview is entirely read-only, including political initialization")
	check(q.changes.size()==2 and q.beforeSpec.speed<q.afterSpec.speed,"before/after full design and complete change list")
	check(q.cost==q.materialCost+q.workerWages+q.expertWages+q.tax+q.margin,"aggregate bill reconciles every coin line")
	var cost: int=0
	var days: float=0.0
	for change in q.changes:cost+=int(change.bill.cost);days+=float(change.bill.workerDays)+float(change.bill.expertDays)
	check(cost==q.cost and is_equal_approx(days,q.workerDays+q.expertDays),"whole-fit cost and time equal real shared per-slot Refits calculations")
	check(q.reserve.dailyWages==300 and q.reserve.returnWages==600 and q.reserve.afterCoins==c.state.coins-q.cost,"current crew payroll and explicit two-day reserve")
	check(q.usedPoints==8 and q.maxPoints==8 and q.deploymentLimit==300,"fitting capacity and battle deployment are distinct")
	q.afterSpec.speed=99999;q.newLoadout.engine="stock_engine";q.reserve.after.warnings.append("detached")
	check(c.state==before and draft.engine=="boost_drive","mutating returned preview cannot mutate canonical hull or draft")

func paid_apply():
	var c: CoreView=fixture()
	var state_ref: Dictionary=c.state
	var ship: Dictionary=c.state.fleet[0]
	var dock: Dictionary=c.state.ports[0]
	var stock_ref: Dictionary=dock.stocks
	var condition: Dictionary=health(ship)
	var before: Dictionary=c.state.duplicate(true)
	var coins: int=M.total(c.state)
	var q: Dictionary=W.preview(c,ship.uid,proposed(c))
	var result: Dictionary=W.apply(c,ship.uid,proposed(c),q)
	check(result.ok and result.changed and M.total(c.state)==coins,"whole fit pays once and conserves Money.total")
	check(is_same(c.state,state_ref) and is_same(c.state.fleet[0],ship) and is_same(c.state.ports[0],dock) and is_same(dock.stocks,stock_ref),"publication preserves live state, hull, port and stock Dictionary identity")
	check(health(ship)==condition,"whole fit preserves damage, engine damage, crew, stores and opaque metadata")
	check(c.state.coins==before.coins-q.cost and dock.cash==before.ports[0].cash+q.businessIncome,"captain pays exact material/margin income to real business purse")
	check(dock.householdPurse==before.ports[0].householdPurse+q.workerWages and dock.expertPurse==before.ports[0].expertPurse+q.expertWages and dock.governmentPurse==before.ports[0].governmentPurse+q.tax,"ordinary workers, experts and government receive actual counted coins")
	for good in q.materials:check(is_equal_approx(float(dock.stocks[good]),float(before.ports[0].stocks[good])-float(q.materials[good])),"aggregate physical input consumption: "+good)
	check(ship.refitLocker.get("stock_engine",0)==1 and ship.refitLocker.get("stock_armor",0)==1,"every removed original module becomes exactly one physical locker item")
	check(is_equal_approx(float(dock._yardWorkersUsed),q.workerDays+q.expertDays) and is_equal_approx(float(dock._yardSpecialistsUsed),q.expertDays),"combined yard reservation shares real workers and experts")
	var installed: Dictionary=c.state.duplicate(true)
	var again: Dictionary=W.apply(c,ship.uid,ship.loadout)
	check(again.ok and not again.changed and c.state==installed,"already-installed whole fit cannot charge, clone modules or repair again")
	refusal(c,ship.loadout,"an accepted old quote cannot be applied a second time",q)

func shared_refusals():
	var c: CoreView=fixture()
	var dock: Dictionary=c.state.ports[0]
	dock.stocks.iron=4.0
	check(R.quote(dock,c.state.fleet[0],"engine","boost_drive").ok and R.quote(dock,c.state.fleet[0],"armor","scout_plating").ok,"each change alone fits stock in the aggregate-shortage fixture")
	var q: Dictionary=W.preview(c,c.state.fleet[0].uid,proposed(c))
	check(q.validDraft and q.affordable and not q.applicable and q.materials.iron==5.0,"valid affordable draft distinguishes missing aggregate physical stock")
	refusal(c,proposed(c),"combined material shortage rejects before all mutation")
	c=fixture();dock=c.state.ports[0];dock.availableWorkers=8;dock.availableSpecialists=3
	check(R.quote(dock,c.state.fleet[0],"engine","boost_drive").ok and R.quote(dock,c.state.fleet[0],"armor","scout_plating").ok,"each change alone fits workers in the aggregate-shortage fixture")
	refusal(c,proposed(c),"aggregate shared workforce cannot be double-booked")
	c=fixture();c.state.ports[0].availableSpecialists=0
	refusal(c,proposed(c),"zero experts reject the full transaction")
	c=fixture();q=W.preview(c,c.state.fleet[0].uid,proposed(c));c.state.coins=q.cost-1;c.state.coinSupply=M.total(c.state)
	q=W.preview(c,c.state.fleet[0].uid,proposed(c))
	check(q.validDraft and not q.affordable and not q.applicable,"valid fit is distinct from affordable fit")
	refusal(c,proposed(c),"coin shortage is atomic")
	c=fixture();c.at_sea=true
	refusal(c,proposed(c),"at-sea draft does not grant a yard or paid workforce")
	c=fixture();c.state.fleet[0].storedPort="another-harbor"
	refusal(c,proposed(c),"remote stored hull cannot use the current yard")
	c=fixture();c.state.fleet[0].moduleConditions={"engine":{"condition":0.4,"serial":"retained"}}
	refusal(c,proposed(c),"unsupported individual condition metadata is retained without repair-by-swap")
	c=fixture();var bad: Dictionary=proposed(c);bad.weapons[0]="heavy_cannon"
	refusal(c,bad,"incompatible physical module rejects before mutation")
	c=fixture();bad=proposed(c);bad.weapons[1]="rapid_gun"
	q=W.preview(c,c.state.fleet[0].uid,bad)
	check(not q.validDraft and q.usedPoints>q.maxPoints,"over-budget drafts retain useful fitting diagnostics")
	refusal(c,bad,"over-budget fitting cannot publish")

func locker_swaps():
	var c: CoreView=fixture(23)
	var ship: Dictionary=c.state.fleet[0]
	ship.loadout={"weapons":["heavy_gun","light_cannon","",""],"engine":"stock_engine","armor":"stock_armor"}
	R.ensure(ship,world.HULLS[23])
	var draft: Dictionary=ship.loadout.duplicate(true)
	draft.weapons=["light_cannon","heavy_gun","",""]
	var stock: Dictionary=c.state.ports[0].stocks.duplicate(true)
	var q: Dictionary=W.preview(c,ship.uid,draft)
	check(q.ok and q.materials.is_empty() and q.lockerAfter.is_empty() and q.changes.all(func(change):return change.source=="moved"),"all returns precede consumption when swapping two physical modules")
	check(q.workerWages>0 and q.expertWages>0,"moving owned modules pays ordinary and expert installation")
	check(W.apply(c,ship.uid,draft,q).ok and ship.loadout==draft and ship.refitLocker.is_empty() and c.state.ports[0].stocks==stock,"position swap neither clones parts nor buys unnecessary materials")
	c=fixture();ship=c.state.fleet[0]
	check(R.install(c.state,c.state.ports[0],ship,"engine","boost_drive").ok,"prepare paid engine with actual current Refits.install")
	C.begin_day(c.state.ports[0])
	draft=ship.loadout.duplicate(true);draft.engine="stock_engine";draft.weapons[0]="light_cannon"
	check(not R.quote(c.state.ports[0],ship,"weapon:0","light_cannon").ok,"intermediate fit is too expensive in fitting points")
	q=W.preview(c,ship.uid,draft)
	check(q.ok and q.usedPoints==5 and q.changes.any(func(change):return change.slot=="engine" and change.fromLocker),"whole fitting frees points and consumes the actual original locker engine")
	check(W.apply(c,ship.uid,draft,q).ok and ship.refitLocker.get("boost_drive",0)==1 and not ship.refitLocker.has("stock_engine"),"point-freeing whole fit retains one removed racing engine")

func stale_and_hold():
	var c: CoreView=fixture()
	var draft: Dictionary=proposed(c)
	var q: Dictionary=W.preview(c,c.state.fleet[0].uid,draft)
	c.state.ports[0].stocks.iron-=0.25
	refusal(c,draft,"a changed material quote must be reviewed again",q)
	c=fixture();q=W.preview(c,c.state.fleet[0].uid,proposed(c))
	c.state.fleet[0].fuel+=1
	refusal(c,proposed(c),"changed paid stores invalidate the reviewed reserve",q)
	c=fixture();refusal(c,proposed(c),"an incomplete nonempty expected quote cannot authorize a bill",{"cost":1})
	c=fixture();var ship: Dictionary=c.state.fleet[0]
	ship.loadout.weapons[1]="rapid_gun";R.ensure(ship,world.HULLS[0]);ship.ammo=160.0
	c.state.cargo.iron=(float(ship.spec.cargo)-1.0)/float(G.ITEMS.iron.weight)
	draft=ship.loadout.duplicate(true);draft.weapons[1]=""
	check(X.report(c.state,c.data).overload==0,"magazine/hold fixture starts within capacity")
	refusal(c,draft,"a smaller fitted magazine cannot discard excess paid rounds or overfill the holds")
	c=fixture()
	for i in range(23):
		var extra: Dictionary=D.create_ship(world.HULLS[0]);extra.uid="extra-%d"%i;extra.mothballed=false
		R.ensure(extra,world.HULLS[0]);c.state.fleet.append(extra)
	check(DP.total(c.state.fleet)>300 and W.apply(c,c.state.fleet[0].uid,proposed(c)).ok,"owned fleet points do not become an invented 300-point ownership/refit limit")

func knowledge_library():
	var c: CoreView=fixture()
	var original: Dictionary=c.state.duplicate(true)
	var base: Dictionary=world.HULLS[0]
	var saved: Dictionary=W.save_template(c.state,base,"Coastal scout",proposed(c))
	check(saved.ok and W.template_list(c.state,base.id).size()==1,"save a named fitting as hull-specific knowledge")
	var knowledge: Array=c.state.fitTemplates.duplicate(true)
	c.state.fitTemplates=[]
	check(c.state==original,"saving fitting knowledge never mints money, stock, crews or installed modules")
	c.state.fitTemplates=knowledge
	var listed: Array=W.template_list(c.state);listed[0].loadout.engine="stock_engine"
	check(c.state.fitTemplates[0].loadout.engine=="boost_drive","template_list returns detached knowledge")
	var duplicate: Dictionary=W.save_template(c.state,base,"COASTAL SCOUT",R.defaults(base))
	check(duplicate.ok and duplicate.id==saved.id and c.state.fitTemplates.size()==1,"same hull and case-insensitive name updates one stable template ID")
	var before: Dictionary=c.state.duplicate(true)
	check(not W.save_template(c.state,base,"x".repeat(49),proposed(c)).ok and c.state==before,"overlong template names reject atomically")
	check(not W.save_template(c.state,base,"bad\nname",proposed(c)).ok and c.state==before,"control characters reject atomically")
	for i in range(23):check(W.save_template(c.state,base,"Fit %d"%i,R.defaults(base)).ok,"fill bounded library slot %d"%i)
	before=c.state.duplicate(true)
	check(not W.save_template(c.state,base,"Twenty fifth",R.defaults(base)).ok and c.state==before,"25th template is rejected without mutation")
	var restored: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	check(W.validate_templates(restored,world).is_empty(),"knowledge-only library survives JSON roundtrip")
	restored.fitTemplates[0].coins=1
	check(not W.validate_templates(restored,world).is_empty(),"preflight rejects economic or unknown fields in knowledge")
	restored=JSON.parse_string(JSON.stringify(c.state));restored.fitTemplates[0].loadout.engine="invented"
	check(not W.validate_templates(restored,world).is_empty(),"preflight rejects invalid saved fitting modules")
	check(W.validate_templates({},world).is_empty(),"legacy saves may omit the library")
	check(W.delete_template(c.state,saved.id).ok and c.state.fitTemplates.size()==23,"forgetting knowledge changes only the bounded library")
	before=c.state.duplicate(true)
	check(not W.delete_template(c.state,"missing").ok and c.state==before,"unknown template deletion cannot mutate other entries")

func _initialize():
	world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	preview_and_bill();paid_apply();shared_refusals();locker_swaps();stale_and_hold();knowledge_library()
	print("Workshop: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
