extends SceneTree
const Shipping=preload("res://scripts/shipping_companies.gd")
const GOODS={"grain":{"weight":1.0},"iron":{"weight":2.0}}
const LIMIT={"buyMax":20,"sellMin":15,"maxCargo":10.0,"reserve":50,"risk":0.4}
var errors=0

class Cash:
	static func move(src,sk,dst,dk,amount,reason,ledger=[]) -> bool:
		if amount<0 or src[sk]<amount:
			return false
		src[sk]=int(src[sk]) - amount
		dst[dk]=int(dst[dk])+amount
		ledger.append({"amount":amount,"reason":reason})
		return true

class Access:
	static func permit(core,_kind):
		return {"ok":core.access}

class Core:
	extends RefCounted
	var state: Dictionary
	var dock="a"
	var access=true
	var boats=[{"id":"cargo"}]
	func _init():
		state={"fleet":[boat("flag",2,10),boat("cargo",4,20)],
			"coins":1000,"crewPurse":600,"cargo":{"grain":2.0,"iron":0.0},
			"ports":[{"id":"a","x":0.0,"y":0.0,"faction":"f"},
				{"id":"b","x":100.0,"y":0.0,"faction":"f"}],
			"fleetOwners":[],"patrols":[],"day":0.0,"econDay":0,
			"moneyLog":[],"flagship":"flag","nextUid":1,
			"specialists":[]}
	static func boat(uid,crew,hold_size):
		return {"uid":uid,"type":"cargo","spec":{"cargoCapacity":hold_size},
			"crew":crew,"shoreCrew":0,"crewMin":1,"crewMax":8,"hp":75.0,"maxHp":100.0,
			"fuel":9.0,"ammo":7.0,"supplies":6.0,"engine":"diesel",
			"loadout":{"mount_1":"gun"},"storedPort":"","mothballed":false,"sunk":false}
	func current_port():
		return port(dock)
	func port(id):
		for p in state.ports:
			if p.id==id:
				return p
		return {}
	func fitted_spec(b):
		return b.spec
	func capacity():
		var total=0.0
		for b in state.fleet:
			if not b.sunk and b.storedPort=="" and not b.mothballed:
				total+=b.spec.cargoCapacity
		return total
	func cargo_weight():
		return state.cargo.grain+state.cargo.iron * 2.0
func module():
	return Shipping.new(GOODS,Cash,Access,func(c,b): return c.fitted_spec(b).cargoCapacity)
func ck(value,label: String=""):
	if not value:
		errors+=1
		push_error("%s %s" % [label,get_stack()])
func total(c,buyer={"coins":0}):
	var n=c.state.coins+c.state.crewPurse+buyer.coins
	for o in c.state.fleetOwners:
		n+=o.coins+o.crewPurse
	return n
func company(c):
	return c.state.fleetOwners[0]
func pat(c):
	return c.state.patrols[0]
func open(m,c):
	var r=m.create(c,["cargo"],"b","grain",400,LIMIT)
	ck(r.ok)
	return r.get("id","")
func arrived(c,port_id):
	var p=c.port(port_id)
	company(c).atPort=port_id
	pat(c).holding=true
	pat(c).x=p.x
	pat(c).y=p.y
	pat(c)["from"]=port_id
func reject(c,action: Callable,label: String):
	var before=JSON.stringify(c.state)
	ck(not action.call().ok,label+" rejected")
	ck(JSON.stringify(c.state)==before,label+" atomic")
func test_creation():
	var m=module()
	var c=Core.new()
	var boat=c.state.fleet[1]
	var sp={"id":"s","role":"test","boatUid":"flag","wage":100}
	c.state.specialists=[sp]
	var cargo=c.state.cargo.duplicate(true)
	m.ensure(c)
	ck(c.state.shippingCompanies=={} and c.state.fleetOwners.is_empty())
	var id=open(m,c)
	var o=company(c)
	ck(c.state.specialists.size()==1 and is_same(c.state.specialists[0],sp)
		and sp.wage==100 and not o.has("specialists"))
	ck(total(c)==1600 and c.state.coins==600 and o.coins==400)
	ck(o.crewPurse==400 and c.state.crewPurse==200)
	ck(is_same(o.boats[0],boat) and m.owned_count(c.state)==2)
	ck(boat.hp==75 and boat.fuel==9 and boat.ammo==7
		and boat.supplies==6 and boat.loadout.mount_1=="gun")
	ck(o.boats[0].crew==4 and c.state.fleet[0].crew==2)
	ck(o.cargo.grain==0 and c.state.cargo==cargo)
	ck(not c.state.shippingCompanies[id].has("coins"))
	var copy=m.list(c)
	copy[0].invested=0
	ck(c.state.shippingCompanies[id].invested==400)
	ck(m.next_port(c,o)=="b")
	o.atPort=""
	pat(c).holding=false
	pat(c).x=30
	for i in 5:
		m.daily(c)
	ck(total(c)==1600 and boat.fuel==9 and o.cargo.grain==0)
	ck(m.recall(c,id).ok and m.next_port(c,o)=="a")
	ck(pat(c).x==30 and o.atPort=="")
	reject(c,func(): return m.collect(c,id),"at sea")
	arrived(c,"b")
	reject(c,func(): return m.collect(c,id),"wrong dock")
	arrived(c,"a")
	o.wageArrears=1
	reject(c,func(): return m.collect(c,id),"unpaid crew")
	o.wageArrears=0
	boat.storedPort="b"
	reject(c,func(): return m.collect(c,id),"remote living hull")
	boat.storedPort=""
	m.daily(c)
	ck(c.state.shippingCompanies[id].status=="ready")
	ck(m.collect(c,id).ok and is_same(c.state.fleet[1],boat))
	ck(total(c)==1600 and o.boats.is_empty() and not o.active
		and not pat(c).active)
	reject(c,func(): return m.collect(c,id),"collect twice")
func test_limits():
	var m=module()
	for reason in ["access","dock","specialists","stale","shore","remote","mothball","crew","last","cargo"]:
		var c=Core.new()
		match reason:
			"access":
				c.access=false
			"dock":
				c.dock=""
			"specialists","stale":
				c.state.specialists=[{"id":"s","role":"test","boatUid":"cargo","wage":120}]
				if reason=="stale":
					c.state.specialists[0].active=false
			"shore":
				c.state.fleet[1].shoreCrew=1
			"remote":
				c.state.fleet[1].storedPort="b"
			"mothball":
				c.state.fleet[1].mothballed=true
			"crew":
				c.state.fleet[1].crew=0
			"last":
				c.state.fleet[0].sunk=true
			"cargo":
				c.state.erase("cargo")
		reject(c,func(): return m.create(c,["cargo"],"b","grain",400,LIMIT),reason)
	var c=Core.new()
	for uids in [["missing"],["cargo","cargo"],[]]:
		reject(c,func(): return m.create(c,uids,"b","grain",400,LIMIT),"UIDs")
	reject(c,func(): return m.create(c,["cargo"],"b","grain",1001,LIMIT),"underfunded")
	reject(c,func(): return m.create(c,["cargo"],"b","grain",400),"missing limits")
	reject(c,func(): return m.create(c,["cargo"],"b","unknown",400,LIMIT),"bad good")
	for i in 8:
		if i>0:
			c.state.fleet.append(Core.boat("cargo_%d" % i,1,20))
			c.state.coins+=1
		var uid="cargo" if i==0 else "cargo_%d" % i
		ck(m.create(c,[uid],"b","grain",1,LIMIT).ok)
	c.state.fleet.append(Core.boat("extra",1,20))
	reject(c,func(): return m.create(c,["extra"],"b","grain",1,LIMIT),"company cap")
func test_book():
	var m=module()
	var c=Core.new()
	var id=open(m,c)
	var o=company(c)
	var book=c.state.shippingCompanies[id]
	var buyer={"coins":0}
	ck(m.trade_limit(c,o,true,"grain",21)==0)
	ck(m.trade_limit(c,o,true,"grain",10)==10)
	ck(m.trade_limit(c,o,true,"iron",10)==0)
	o.coins=55
	ck(m.trade_limit(c,o,true,"grain",10)==0.5)
	o.coins=400
	Cash.move(o,"coins",buyer,"coins",100,"trade")
	o.cargo.grain=10.0
	m.record(c,o,"purchase",100,"grain",10)
	ck(book.netProfit==0 and book.basisCost==100)
	arrived(c,"b")
	ck(m.trade_limit(c,o,false,"grain",14)==0
		and m.trade_limit(c,o,false,"grain",20)==10)
	buyer.coins+=80
	Cash.move(buyer,"coins",o,"coins",80,"sale")
	o.cargo.grain=6.0
	m.record(c,o,"sale",80,"grain",4)
	ck(book.cogs==40 and book.netProfit==40 and book.basisCost==60)
	Cash.move(o,"coins",o,"crewPurse",20,"payroll")
	m.record(c,o,"wages",20)
	Cash.move(o,"crewPurse",buyer,"coins",5,"food")
	m.record(c,o,"crew_food",5)
	ck(book.netProfit==20)
	for pair in [["fuel",10],["repairs",3],["fees",2]]:
		Cash.move(o,"coins",buyer,"coins",pair[1],pair[0])
		m.record(c,o,pair[0],pair[1])
	ck(book.netProfit==5)
	var conserved=total(c,buyer)
	ck(m.capital(c,id,100).ok and total(c,buyer)==conserved
		and book.netProfit==5 and book.invested==500)
	o.cargo.grain=5.0
	m.record(c,o,"loss",0,"grain",1)
	ck(book.netProfit==-5 and book.basisCost==50)
	ck(m.recall(c,id).ok and m.trade_limit(c,o,true,"grain",10)==0)
	arrived(c,"a")
	o.boats[0].spec.cargoCapacity=1.0
	c.state.cargo.grain=10.0
	reject(c,func(): return m.collect(c,id),"cargo full")
	c.state.cargo.grain=2.0
	o.boats[0].spec.cargoCapacity=20.0
	ck(m.collect(c,id).ok and c.state.cargo.grain==7)
	ck(book.returnedBasis==50 and book.netProfit==-5
		and total(c,buyer)==conserved)
func test_save():
	var m=module()
	var c=Core.new()
	var id=open(m,c)
	var o=company(c)
	var hull=o.boats[0]
	o.coins=0
	hull.hp=1
	ck(m.capital(c,id,10).ok and hull.hp==1)
	reject(c,func(): return m.capital(c,id,10000),"bad topup")
	hull.sunk=true
	hull.hp=0
	m.daily(c)
	ck(is_same(o.boats[0],hull) and m.owned_count(c.state)==2)
	var world={"ports":c.state.ports,"hulls":{"cargo":{}}}
	var saved=JSON.parse_string(JSON.stringify(c.state))
	ck(m.validate(saved,world)=="")
	for defect in ["mirror","owner","patrol","boat","port","good","limit","nan","cash","fleet"]:
		var bad=saved.duplicate(true)
		var b=bad.shippingCompanies[id]
		match defect:
			"mirror":
				b.coins=1
			"owner":
				bad.fleetOwners.clear()
			"patrol":
				bad.patrols.clear()
			"boat":
				bad.fleet.append(bad.fleetOwners[0].boats[0])
			"port":
				b.home="missing"
			"good":
				b.good="missing"
			"limit":
				b.limits.buyMax=1.5
			"nan":
				b.limits.risk=NAN
			"cash":
				bad.fleetOwners[0].crewPurse=-1
			"fleet":
				bad.fleet={}
		ck(m.validate(bad,world) != "","bad save "+defect)
	ck(m.recall(c,id).ok and m.collect(c,id).ok
		and is_same(c.state.fleet[1],hull) and hull.sunk)
func _initialize():
	test_creation()
	test_limits()
	test_book()
	test_save()
	print("shipping: %d failures" % errors)
	quit(0 if errors==0 else 1)
