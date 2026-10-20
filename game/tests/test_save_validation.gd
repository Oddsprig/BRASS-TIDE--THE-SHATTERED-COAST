extends SceneTree
## Read-only schema tests. Run only after root grants the single-instance test slot.
const V=preload("res://scripts/save_validation.gd")
const C=preload("res://scripts/campaign.gd")
const Construction=preload("res://scripts/construction.gd")
var world: Dictionary
var checks: int=0
var failures: Array=[]
func unchanged(a,b) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		if is_nan(float(a)) and is_nan(float(b)): return true
		return a==b
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not unchanged(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in range(a.size()):
			if not unchanged(a[i],b[i]): return false
		return true
	return a==b
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures.append(message)
		print("FAIL save validation: "+message)
func accept(saved: Dictionary,label: String) -> void:
	var before: Dictionary=saved.duplicate(true)
	var result: Dictionary=V.validate(saved,world)
	check(result.ok,label+": "+str(result.message))
	check(unchanged(saved,before),label+" does not mutate source")
func reject(saved: Dictionary,label: String) -> void:
	var before: Dictionary=saved.duplicate(true)
	var result: Dictionary=V.validate(saved,world)
	check(not result.ok and result.message is String and not result.message.is_empty(),label+" rejects with useful message")
	check(unchanged(saved,before),label+" leaves data untouched")
func copy_json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))
func _initialize() -> void:
	var started: int=Time.get_ticks_msec()
	world=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var core=C.new(world)
	core.new_game(123)
	var valid: Dictionary=copy_json(core.state)
	accept(valid,"Actual new-game JSON with whole-valued float coins and sparse story cargo")
	core.state.fleet[0].hp-=11
	core.state.fleet[0].water=7.25
	core.state.fleet[0].wounded=1
	core.state.fleet[0].breaches=[{"area":3.5,"section":"engine"}]
	core.state.fleet[0].engine=0.7
	core.state.fleet[0].supplies=2.75
	accept(copy_json(core.state),"Actual damaged boat JSON")
	var extra: Dictionary=valid.duplicate(true)
	extra.futureExtension={"note":"accepted unknown metadata","optional":null}
	extra.fleet[0].ammo=100.0
	extra.fleet[0].fuel=81.0
	extra.fleet[0].supplies=30.0
	accept(extra,"Extra fields and finite stores above refilling targets remain valid")
	var order: Dictionary=Construction.make_order(core.hull(world.START.hull),Construction.quote(core.hull(world.START.hull)),"player")
	core.state.ports[0].cash-=order.escrow
	core.state.ports[0].buildQueue.append(order)
	accept(copy_json(core.state),"Real construction-order schema with retained wage escrow")
	core.new_game(123)
	var mission: Dictionary=core.available_contracts()[0]
	var accepted: Dictionary=core.accept_contract(mission.id)
	check(accepted.ok,"Real funded story contract fixture accepted")
	var active: Dictionary=copy_json(core.state)
	accept(active,"Actual funded contract and sponsor fields")
	var bad: Dictionary=valid.duplicate(true)
	bad.ports[0]=null
	reject(bad,"Null port element")
	bad=valid.duplicate(true)
	bad.ports[0]="harbor"
	reject(bad,"String port element")
	bad=valid.duplicate(true)
	bad.ports[0].cash=null
	reject(bad,"Null business purse")
	bad=valid.duplicate(true)
	bad.ports[0].householdPurse="1000"
	reject(bad,"String household purse")
	bad=valid.duplicate(true)
	bad.ports[0].expertPurse=-1
	reject(bad,"Negative expert purse")
	bad=valid.duplicate(true)
	bad.ports[0].governmentPurse=10.5
	reject(bad,"Fractional coin amount")
	bad=valid.duplicate(true)
	bad.ports[0].stocks.erase("iron")
	reject(bad,"Missing one of sixteen stocks")
	bad=valid.duplicate(true)
	bad.ports[0].stocks.food="three"
	reject(bad,"String physical stock")
	bad=valid.duplicate(true)
	bad.position.x=NAN
	reject(bad,"NaN campaign geometry")
	bad=valid.duplicate(true)
	bad.fleet[0].angle=INF
	reject(bad,"Infinite boat angle")
	bad=valid.duplicate(true)
	bad.ports[1].id=bad.ports[0].id
	reject(bad,"Duplicate harbor IDs")
	bad=valid.duplicate(true)
	bad.ports[0].id="unknown-port"
	reject(bad,"Unknown original harbor ID")
	bad=valid.duplicate(true)
	bad.fleet[0].type="unknown-hull"
	reject(bad,"Unknown player hull")
	bad=valid.duplicate(true)
	bad.fleet[0].crew=bad.fleet[0].crewMax+1
	reject(bad,"Over-capacity crew")
	bad=valid.duplicate(true)
	bad.fleet[0].hp=bad.fleet[0].maxHp+1
	reject(bad,"Over-capacity hull HP")
	bad=valid.duplicate(true)
	bad.fleet[0].water=bad.fleet[0].capacity+1
	reject(bad,"Over-capacity water")
	bad=valid.duplicate(true)
	bad.fleet[0].ammo=-1
	reject(bad,"Negative ready ammunition")
	bad=valid.duplicate(true)
	bad.fleet[0].wounded=bad.fleet[0].crew+1
	reject(bad,"Wounded exceed surviving crew")
	bad=valid.duplicate(true)
	bad.fleet.append(bad.fleet[0].duplicate(true))
	reject(bad,"Duplicate player boat uid")
	bad=valid.duplicate(true)
	bad.fleet[0].breaches=[null]
	reject(bad,"Null breach")
	bad=valid.duplicate(true)
	bad.ports[0].buildQueue=[null]
	reject(bad,"Null construction order")
	bad=valid.duplicate(true)
	var invalid_order: Dictionary=order.duplicate(true)
	invalid_order.escrow="100"
	bad.ports[0].buildQueue=[invalid_order]
	reject(bad,"String construction escrow")
	bad=valid.duplicate(true)
	bad.coins="15000"
	reject(bad,"String captain purse")
	bad=valid.duplicate(true)
	bad.crewPurse=null
	reject(bad,"Null shared crew purse")
	bad=valid.duplicate(true)
	bad.coinSupply=1e30
	reject(bad,"Unsafe integer overflow range")
	bad=valid.duplicate(true)
	bad.cargo.erase("ammo")
	reject(bad,"Missing player cargo good")
	bad=valid.duplicate(true)
	bad.fleetOwners[0]=null
	reject(bad,"Null NPC owner")
	bad=valid.duplicate(true)
	bad.fleetOwners[0].crewPurse="50"
	reject(bad,"String NPC crew purse")
	bad=valid.duplicate(true)
	bad.fleetOwners[0].boats=[null]
	reject(bad,"Null NPC boat")
	bad=valid.duplicate(true)
	bad.fleetOwners[0].cargo.food=-1
	reject(bad,"Negative NPC cargo")
	bad=active.duplicate(true)
	bad.activeContract.port="missing-sponsor"
	reject(bad,"Unknown funded contract sponsor")
	bad=active.duplicate(true)
	bad.activeContract.escrow=null
	reject(bad,"Null funded contract escrow")
	bad=valid.duplicate(true)
	bad.activeContract=[]
	reject(bad,"Wrong active-contract container")
	bad=valid.duplicate(true)
	bad.patrols[0].x=NAN
	reject(bad,"NaN chart patrol geometry")
	bad=valid.duplicate(true)
	bad.ports[0].stocks.fuel=NAN
	reject(bad,"NaN physical stock")
	bad=valid.duplicate(true)
	bad.fleetOwners.append(bad.fleetOwners[0].duplicate(true))
	reject(bad,"Duplicate NPC owner ID")
	print("save validation: %d checks, %d failures, %dms"%[checks,failures.size(),Time.get_ticks_msec()-started])
	if failures.is_empty(): quit(0)
	else:
		quit(1)
		assert(failures.is_empty(),"Save preflight failures above")
