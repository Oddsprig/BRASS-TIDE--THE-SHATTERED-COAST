extends SceneTree
const WC=preload("res://scripts/worker_conditions.gd")
const WAGES={"laborer":100,"carpenter":125,"mechanic":150,"foreman":175,"engineer":200}
var nc:int=0
var f:int=0
var deny:bool=false
class Core:
	extends RefCounted
	var state:Dictionary
	var home:Dictionary
	var docked:bool=true
	var services:bool=true
	var foremen:int=1
	func port(id)->Dictionary:
		return home if id==home.id else {}
	func current_port()->Dictionary:
		return home
	func ok(text:String)->Dictionary:
		return {"ok":true,"message":text}
	func fail(text:String)->Dictionary:
		return {"ok":false,"message":text}
func _new()->Core:
	var c:=Core.new()
	c.home={"id":"p1","stocks":{"food":20},"publicStores":{},
		"cash":20,"householdPurse":30,"expertPurse":40,"governmentPurse":50,
		"workforce":4,"availableWorkers":2,"availableSpecialists":1,
		"lastFoodMet":1.0,"lastEmployed":2,"lastPaid":2}
	c.state={"day":0.0,"econDay":0,"coins":100,"moneyLog":[],
		"businesses":[{"id":"mill","kind":"workshop","homePort":"p1",
		"coins":10000,"inventory":{"food":20,"supplies":4},"capacity":2,
		"employees":[{"occupation":"laborer","wage":100,"specialist":false},
		{"occupation":"mechanic","wage":150,"specialist":true}],
		"wagesPaid":0,"arrearsHousehold":0,"arrearsExpert":0,"paused":false}]}
	WC.ensure(c.home)
	return c
func _b(c:Core)->Dictionary:
	return c.state.businesses[0]
func _access(c:Core,_biz:Dictionary,_port:Dictionary)->Dictionary:
	return {"allowed":c.docked and c.services,"workers":2,"foremen":c.foremen}
func _move(src:Dictionary,sk:String,dst:Dictionary,dk:String,n:int,reason:String,ledger:Array=[])->bool:
	if (deny and dk=="expertPurse") or n<0 or src[sk]<n:
		return false
	src[sk]-=n
	dst[dk]+=n
	ledger.append({"amount":n,"reason":reason})
	return true
func _tick(c:Core)->Dictionary:
	c.state.econDay+=1
	c.state.day=float(c.state.econDay)
	var b:=_b(c)
	b.wagesPaid=0
	for e in b.employees:
		var key:String="expertPurse" if e.specialist else "householdPurse"
		if _move(b,"coins",c.home,key,int(e.wage),"Base payroll",c.state.moneyLog):
			b.wagesPaid+=e.wage
		else:
			var debt:String="arrearsExpert" if e.specialist else "arrearsHousehold"
			b[debt]+=e.wage
	b.paused=b.wagesPaid<250
	return WC.business_step(c,b,c.home)
func _sum(c:Core)->int:
	return int(_b(c).coins+c.home.householdPurse+c.home.expertPurse+c.home.governmentPurse+c.home.cash+c.state.coins)
func _snap(c:Core)->String:
	return JSON.stringify([c.state,c.home])
func _valid(c:Core)->String:
	return WC.validate_state(c.state,{"ports":[c.home],"businessHomes":{"mill":"p1"}})
func _t(value:bool,text:String)->void:
	nc+=1
	if not value:
		f+=1
		push_error(text)
func _init()->void:
	WC.configure(_move,WAGES,["food","supplies"],"food","supplies",_access)
	_policies()
	_strike()
	_fails()
	_validation()
	print("worker_conditions: %d checks, %d failures" % [nc,f])
	quit(0 if f==0 else 1)
func _policies()->void:
	var c:=_new()
	var total:=_sum(c)
	_t(WC.set_policy(c,"mill","overtime").ok,"owned")
	var r:=_tick(c)
	_t(r.workFactor==1.25 and _b(c).labor.fatigue==10,"paid rush")
	_t(c.home.householdPurse==180 and c.home.expertPurse==265,"pay split")
	var s:=_snap(c)
	r=WC.business_step(c,_b(c),c.home)
	_t(not r.canWork and _snap(c)==s,"same-day work")
	for _i in range(3):
		_tick(c)
	var fatigue:int=_b(c).labor.fatigue
	WC.set_policy(c,"mill","rest")
	_t(not _tick(c).canWork and _b(c).labor.fatigue<fatigue,"paid rest")
	_t(_b(c).wagesPaid==250 and _sum(c)==total,"rest coins")
	WC.set_policy(c,"mill","relief")
	var food:int=_b(c).inventory.food
	r=_tick(c)
	_t(r.workFactor==0.9 and _b(c).inventory.food==food-2,"food relief")
	_t(_sum(c)==total and _valid(c)=="","valid")
	_b(c).inventory.food=0
	_t(_tick(c).workFactor==1.0,"no food")
	s=_snap(c)
	_t(not WC.set_policy(c,"unowned","rest").ok and _snap(c)==s,"owned only")
	var saved:Dictionary=JSON.parse_string(JSON.stringify(c.home))
	var saved_before: String=JSON.stringify(saved)
	WC.ensure(saved)
	_t(JSON.stringify(saved)==saved_before,"Existing JSON scores remain untouched")
	saved.lastFoodMet=0.0
	saved.lastPaid=0
	var health:int=saved.conditions.health
	WC.daily_port(saved)
	_t(saved.conditions.health<health and saved.conditions.foodSecurity==0,"food facts")
	_t(saved.conditions.unrest>c.home.conditions.unrest and WC.report(saved).pay.begins_with("0/"),"pay facts")
	_t(_snap(c)==s,"copy")
func _struck()->Core:
	var c:=_new()
	_b(c).coins=0
	for i in range(3):
		var r:=_tick(c)
		_t(not r.canWork and _b(c).labor.striking==(i==2),"strike day 3")
	return c
func _strike()->void:
	var c:=_struck()
	var b:=_b(c)
	b.coins=2500
	var total:=_sum(c)
	var s:=_snap(c)
	for key in ["docked","services"]:
		c.set(key,false)
		_t(not WC.negotiate(c,"mill").ok and _snap(c)==s,key)
		c.set(key,true)
	c.foremen=0
	_t(not WC.negotiate(c,"mill").ok and _snap(c)==s,"foreman")
	c.foremen=1
	_t(WC.negotiate(c,"mill").ok,"settlement")
	_t(b.arrearsHousehold==0 and b.arrearsExpert==0 and b.coins==1681,"debt/fees")
	_t(b.inventory.food==18 and b.inventory.supplies==3 and c.home.conditions.foremanQ==1,"supplies/time")
	s=_snap(c)
	_t(not WC.negotiate(c,"mill").ok and _snap(c)==s,"no reset")
	c.state=JSON.parse_string(JSON.stringify(c.state))
	c.home=JSON.parse_string(JSON.stringify(c.home))
	b=_b(c)
	WC.ensure(c.home)
	_t(b.labor.striking and b.labor.restDays==2 and _valid(c)=="","loaded strike")
	_t(not _tick(c).canWork and b.labor.restDays==1,"rest day 1")
	_t(not _tick(c).canWork and b.labor.restDays==0,"rest day 2")
	_t(_tick(c).canWork and not b.labor.striking,"restart")
	_t(_sum(c)==total and _valid(c)=="","coins")
func _fails()->void:
	var c:=_new()
	_b(c).coins=250
	WC.set_policy(c,"mill","overtime")
	_t(_tick(c).workFactor==1.0 and _b(c).coins==0,"no cash")
	c=_new()
	WC.set_policy(c,"mill",{"policy":"overtime","cap":124})
	_t(_tick(c).workFactor==1.0 and _b(c).coins==9750,"cap")
	c=_new()
	_tick(c)
	WC.set_policy(c,"mill","overtime")
	c.state.econDay+=1
	_b(c).wagesPaid=250
	deny=true
	_t(WC.business_step(c,_b(c),c.home).workFactor==1.0,"expert failure")
	deny=false
	_t(_b(c).coins==9750 and c.home.householdPurse==130 and c.state.moneyLog.size()==2,"atomic pay")
	c=_struck()
	_b(c).coins=1000
	_b(c).inventory.supplies=0
	var s:=_snap(c)
	_t(not WC.negotiate(c,"mill").ok and _snap(c)==s,"inputs")
	_b(c).inventory.supplies=1
	_b(c).coins=818
	s=_snap(c)
	_t(not WC.negotiate(c,"mill").ok and _snap(c)==s,"debt")
func _validation()->void:
	var c:=_new()
	_tick(c)
	_t(_valid(c)=="","valid s")
	_b(c).coins=9750.0
	c.state.econDay=1.0
	_t(_valid(c)=="","whole floats")
	_b(c).inventory.food=0.1
	c.home.stocks.food=0.25
	_t(_valid(c)=="","Physical stock may contain finite fractional lots")
	for bad in [NAN,INF,-1,0.5,true,"10"]:
		var old:Variant=_b(c).coins
		_b(c).coins=bad
		_t(_valid(c)!="","bad money")
		_b(c).coins=old
	for row in [[c.home.conditions,"schema",2],[c.home.conditions,"health",100.5],
		[c.home,"availableWorkers",NAN],[_b(c).inventory,"food",-0.1],
		[_b(c).labor,"policy","free_money"],[_b(c),"id","forged"]]:
		var before:Variant=row[0][row[1]]
		row[0][row[1]]=row[2]
		_t(_valid(c)!="",str(row[1]))
		row[0][row[1]]=before
	_b(c).employees.resize(257)
	_t(_valid(c)!="","array limit")
