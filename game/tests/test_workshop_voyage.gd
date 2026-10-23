extends SceneTree
## Actual fresh-start Campaign transactions. Root owns the serialized engine lease.
const Campaign=preload("res://scripts/campaign.gd")
const Refit=preload("res://scripts/refit.gd")
const Money=preload("res://scripts/money.gd")
const Goods=preload("res://scripts/goods.gd")
var workshop: Script
var world: Dictionary
var checks: int=0
var failures: int=0

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL workshop voyage: "+message)

func fresh():
	var core=Campaign.new(world.duplicate(true))
	core.new_game(29029)
	return core

func condition(ship: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key in ["hp","maxHp","water","engine","ammo","fuel","supplies","crew","wounded","breaches","fire","sunk","needsHarborRepair","storedPort","shoreCrew"]:
		if ship.has(key):
			var value=ship[key]
			result[key]=value.duplicate(true) if value is Dictionary or value is Array else value
	return result

func property_without_templates(state: Dictionary) -> Dictionary:
	var result: Dictionary=state.duplicate(true)
	result.erase("fitTemplates")
	return result

func assets(ship: Dictionary) -> Dictionary:
	var counts: Dictionary=Refit._locker(ship.get("refitLocker",{})).locker.duplicate(true)
	for id in ship.loadout.weapons+[ship.loadout.engine,ship.loadout.armor]:
		if not str(id).is_empty():counts[id]=int(counts.get(id,0))+1
	return counts

func refuse(core,fit: Dictionary,label: String,quote: Dictionary={}) -> void:
	var before: Dictionary=core.state.duplicate(true)
	var state_ref: Dictionary=core.state
	var ship_ref: Dictionary=core.state.fleet[0]
	var port_refs: Array=core.state.ports.duplicate()
	var result: Dictionary=workshop.apply(core,str(ship_ref.uid),fit,quote)
	check(not result.get("ok",false) and not str(result.get("message","")).is_empty(),label+" has a useful refusal")
	check(core.state==before and is_same(core.state,state_ref),label+" leaves canonical state EXACT")
	check(is_same(core.find_boat(ship_ref.uid),ship_ref),label+" preserves held hull reference")
	for port_ref in port_refs:
		check(is_same(core.port(port_ref.id),port_ref),label+" preserves held port "+str(port_ref.id))

func test_starter_bill_locker_and_refs() -> void:
	var core=fresh()
	var ship: Dictionary=core.state.fleet[0]
	var port: Dictionary=core.current_port()
	check(core.state.fleet.size()==1 and int(core.state.coins)==int(world.START.coins),"uses the ordinary starter hull and purse without capital injection")
	check(Goods.SAILOR_WAGE==100 and Money.total(core.state)==int(core.state.coinSupply),"actual 100-coin sailor-day and finite world purses")
	ship.hp-=11.0
	ship.water=2.0
	ship.engine=0.74
	ship.wounded=1.0
	ship.breaches=[{"area":0.1,"section":"bow"}]
	var health: Dictionary=condition(ship)
	var fit: Dictionary=ship.loadout.duplicate(true)
	fit.weapons[1]="rapid_gun"
	var ordinary_bill: Dictionary=Refit.quote(port,ship,"weapon:1","rapid_gun")
	check(ordinary_bill.ok and int(ordinary_bill.cost)<=int(core.state.coins),"real starter stock, workers, experts and purse afford a useful second gun")
	if not ordinary_bill.ok or int(ordinary_bill.cost)>int(core.state.coins):return
	var before: Dictionary=core.state.duplicate(true)
	var before_port: Dictionary=port.duplicate(true)
	var state_ref: Dictionary=core.state
	var stock_ref: Dictionary=port.stocks
	var quote: Dictionary=workshop.preview(core,ship.uid,fit)
	check(quote.validDraft and quote.affordable and quote.applicable and core.state==before,"whole-fit preview reports actual feasibility and is entirely read only")
	check(quote.cost==quote.materialCost+quote.workerWages+quote.expertWages+quote.tax+quote.margin and quote.cost==ordinary_bill.cost,"full bill reconciles actual parts, wages, duty and margin")
	check(quote.beforeSpec==ship.spec and quote.newLoadout==fit and quote.afterSpec.weaponMounts.size()==2,"before/after preview includes both physical fitted guns")
	check(quote.changes.size()==1 and quote.changes[0].socketId==Refit.hardpoints(ship.baseSpec)[1].id,"change list uses the actual second physical socket ID")
	check(int(quote.reserve.afterCoins)==int(core.state.coins)-int(quote.cost) and float(quote.reserve.after.dailyWages)==float(quote.reserve.before.dailyWages),"reserve exposes the actual purse after bill without creating or hiring sailors")
	var result: Dictionary=workshop.apply(core,ship.uid,fit,quote)
	check(result.get("ok",false),"apply affordable actual starter fit: "+str(result.get("message","")))
	if not result.get("ok",false):return
	check(is_same(core.state,state_ref) and is_same(core.find_boat(ship.uid),ship) and is_same(core.current_port(),port) and is_same(port.stocks,stock_ref),"successful publication retains live state, hull, harbor and stock objects")
	check(ship.loadout==fit and condition(ship)==health,"installed fit preserves exact damage, crew and working stores")
	check(int(core.state.coins)==int(before.coins)-int(ordinary_bill.cost),"whole-fit debit equals the existing real single-module bill")
	check(int(port.cash)==int(before_port.cash)+int(ordinary_bill.businessIncome),"parts and yard margin reach the real business purse")
	check(int(port.householdPurse)==int(before_port.householdPurse)+int(ordinary_bill.workerWages),"ordinary wages reach real households")
	check(int(port.expertPurse)==int(before_port.expertPurse)+int(ordinary_bill.expertWages) and int(port.governmentPurse)==int(before_port.governmentPurse)+int(ordinary_bill.tax),"expert pay and duty reach their existing counted purses")
	for good in port.stocks:
		check(is_equal_approx(float(port.stocks[good]),float(before_port.stocks[good])-float(ordinary_bill.materials.get(good,0.0))),"only the actual quoted physical material is consumed: "+str(good))
	check(Money.total(core.state)==int(before.coinSupply),"fit conserves every counted world coin")
	check(float(port.get("_yardWorkersUsed",0.0))>float(before_port.get("_yardWorkersUsed",0.0)) and float(port.get("_yardSpecialistsUsed",0.0))>float(before_port.get("_yardSpecialistsUsed",0.0)),"real shared work reservations increase")
	var owned: Dictionary=assets(ship)
	var stocks: Dictionary=port.stocks.duplicate(true)
	fit=ship.loadout.duplicate(true)
	fit.weapons[0]="rapid_gun"
	fit.weapons[1]=""
	quote=workshop.preview(core,ship.uid,fit)
	var coins: int=int(core.state.coins)
	result=workshop.apply(core,ship.uid,fit,quote)
	check(result.get("ok",false),"atomic multi-slot move returns the purchased gun before consuming it: "+str(result.get("message","")))
	if not result.get("ok",false):return
	check(assets(ship)==owned and port.stocks==stocks,"socket move creates no gun and buys no replacement materials")
	check(int(ship.refitLocker.get("stock_primary",0))==1 and int(ship.refitLocker.get("rapid_gun",0))==0,"one original primary enters the physical locker while one rapid gun remains installed")
	check(int(core.state.coins)<coins and condition(ship)==health,"reusing owned equipment still pays labor and preserves condition")
	fit.weapons[0]="stock_primary"
	fit.weapons[1]="rapid_gun"
	quote=workshop.preview(core,ship.uid,fit)
	result=workshop.apply(core,ship.uid,fit,quote)
	check(result.get("ok",false) and assets(ship)==owned and port.stocks==stocks,"reverse multi-slot swap consumes the actual locker item exactly once")
	check(ship.refitLocker.is_empty() and Money.total(core.state)==int(core.state.coinSupply),"locker cycle closes without spare clones or new coins")
	check(condition(ship)==health and is_same(core.current_port(),port) and is_same(core.find_boat(ship.uid),ship),"repeated successful swaps preserve physical hull condition and live callers")

func test_exact_refusals() -> void:
	var core=fresh()
	var ship: Dictionary=core.state.fleet[0]
	var fit: Dictionary=ship.loadout.duplicate(true)
	fit.weapons[1]="rapid_gun"
	var port: Dictionary=core.current_port()
	var bill: Dictionary=Refit.quote(port,ship,"weapon:1","rapid_gun")
	var shortfall: int=int(core.state.coins)-int(bill.cost)+1
	check(Money.move(core.state,"coins",port,"governmentPurse",shortfall,"Fixture captain deposits funds",core.state.moneyLog),"lack-of-funds setup moves existing coins instead of destroying them")
	refuse(core,fit,"insufficient captain coins")
	core=fresh();port=core.current_port();ship=core.state.fleet[0]
	var good: String=str(bill.materials.keys()[0])
	var other: Dictionary=core.state.ports[1]
	other.stocks[good]+=port.stocks[good]
	port.stocks[good]=0.0
	refuse(core,fit,"missing physical harbor stock")
	core=fresh();port=core.current_port()
	port.availableWorkers=0
	refuse(core,fit,"no available fitting workers")
	core=fresh();port=core.current_port()
	port.availableSpecialists=0
	refuse(core,fit,"no available fitting experts")
	core=fresh()
	core.state.position=core.port_position("shatter_spire")
	check(not core.Politics.permit(core,"service").ok,"actual hostile harbor denies service permission")
	refuse(core,fit,"hostile harbor permission")
	core=fresh()
	var quote: Dictionary=workshop.preview(core,core.state.fleet[0].uid,fit)
	core.current_port().stocks[good]=0.0
	refuse(core,fit,"stock changed after review",quote)

func test_knowledge_save_and_actual_voyage() -> void:
	var core=fresh()
	var ship: Dictionary=core.state.fleet[0]
	var base: Dictionary=ship.baseSpec
	var fit: Dictionary=ship.loadout.duplicate(true)
	fit.weapons[1]="rapid_gun"
	var before: Dictionary=core.state.duplicate(true)
	var known: Array=workshop.template_list(core.state,str(base.id))
	var quote: Dictionary=workshop.preview(core,ship.uid,fit)
	check(core.state==before and not quote.is_empty(),"listing and comparing a second fit grant no money, people, parts or migration mutation")
	check(quote.applicable and quote.affordable and int(quote.cost)>0 and int(quote.cost)<=int(core.state.coins),"ordinary starter stock, workers and purse cover the actual paid voyage fit")
	if not quote.applicable or not quote.affordable:return
	var saved: Dictionary=workshop.save_template(core.state,base,"Long voyage starter",fit)
	check(saved.get("ok",false) and saved.get("id") is String,"named template records fitting knowledge")
	if not saved.get("ok",false):return
	check(property_without_templates(core.state)==property_without_templates(before),"template save changes only optional fitTemplates knowledge")
	known=workshop.template_list(core.state,str(base.id))
	check(known.size()==1,"saved template is visible for its canonical hull")
	if known.is_empty():return
	known[0].name="Detached result edited by fixture"
	check(workshop.template_list(core.state,str(base.id))[0].name=="Long voyage starter","template list results cannot mutate saved knowledge")
	var templates: Array=workshop.template_list(core.state,str(base.id))
	var restored=Campaign.new(world.duplicate(true))
	var incoming: Dictionary=JSON.parse_string(JSON.stringify(core.state))
	var incoming_before: Dictionary=incoming.duplicate(true)
	check(restored.restore(incoming).ok and incoming==incoming_before,"actual Campaign restore accepts templates without mutating input")
	check(workshop.template_list(restored.state,str(base.id))==templates and Money.total(restored.state)==int(core.state.coinSupply),"JSON save/restore preserves templates and real purses")
	var result: Dictionary=workshop.apply(core,ship.uid,fit,quote)
	check(result.get("ok",false),"ordinary starter can apply its previewed voyage fit: "+str(result.get("message","")))
	if not result.get("ok",false):return
	var fuel: float=float(ship.fuel)
	var departure: Dictionary=core.state.position.duplicate(true)
	check(core.chart_course(core.port("kelp_reach"),"kelp_reach").ok,"real Campaign charts a navigable voyage after fitting")
	for i in range(8):core.step(0.25)
	check(core.distance(departure,core.state.position)>0.0 and float(ship.fuel)<fuel,"actual Campaign movement consumes working fuel under the paid fitting")
	refuse(core,Refit.defaults(base),"fitting after actual departure")
	incoming=JSON.parse_string(JSON.stringify(core.state))
	check(restored.restore(incoming).ok,"actual in-flight voyage restores with fitting and template knowledge")
	check(restored.find_boat(ship.uid).loadout==fit and restored.state.path==incoming.path and workshop.template_list(restored.state,str(base.id))==templates,"saved paid fit, remaining voyage and template survive together")
	before=core.state.duplicate(true)
	check(workshop.delete_template(core.state,str(saved.id)).get("ok",false),"delete knowledge template through the actual API")
	check(property_without_templates(core.state)==property_without_templates(before),"template deletion cannot remove equipment or mint compensation")
	var legacy: Dictionary=JSON.parse_string(JSON.stringify(fresh().state))
	legacy.erase("fitTemplates")
	var legacy_money: int=Money.total(legacy)
	var legacy_fleet: Array=legacy.fleet.duplicate(true)
	check(restored.restore(legacy).ok and workshop.template_list(restored.state).is_empty(),"old save with no optional templates migrates safely")
	check(Money.total(restored.state)==legacy_money and restored.state.fleet.size()==legacy_fleet.size() and condition(restored.state.fleet[0])==condition(legacy_fleet[0]),"old-save migration mints no hull, crew, damage repair or working stores")

func _initialize() -> void:
	# Runtime load gives a clear integration failure instead of a missing preload.
	if DisplayServer.get_name()!="headless":
		check(false,"this suite requires the root's hidden headless/silent engine lease")
	elif not ResourceLoader.exists("res://scripts/fleet_workshop.gd"):
		check(false,"root must integrate helper B's fleet_workshop.gd before this suite runs")
	else:
		workshop=load("res://scripts/fleet_workshop.gd")
		world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
		test_starter_bill_locker_and_refs()
		test_exact_refusals()
		test_knowledge_save_and_actual_voyage()
	print("workshop voyage: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
