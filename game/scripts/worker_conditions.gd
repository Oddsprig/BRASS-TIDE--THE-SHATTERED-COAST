extends RefCounted
const Goods=preload("res://scripts/goods.gd")
const Money=preload("res://scripts/money.gd")
const MAX:=1_000_000_000_000
const MAX_DAY:=1_000_000_000
const PEOPLE:=1_000_000
const POLICIES:=["normal","overtime","rest","relief"]
static var _move:Callable=Money.move
static var _gate:Callable
static var _wages:Dictionary=Goods.WAGES
static var _goods:Array=Goods.ITEMS.keys()
static var _food:String="food"
static var _supplies:String="supplies"
static func _whole(v:Variant,hi:int=MAX,lo:int=0)->bool:
	return _num(v,float(lo),float(hi)) and float(v)==floor(float(v))
static func _num(v:Variant,lo:float,hi:float)->bool:
	return typeof(v) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(v)) and float(v)>=lo and float(v)<=hi

static func configure(move:Callable,wages:Dictionary,goods:Array,food:String,supplies:String,gate:Callable)->void:
	_move=move
	_gate=gate
	_wages=wages.duplicate(true)
	_goods=goods.duplicate()
	_food=food
	_supplies=supplies

static func ensure(port:Dictionary)->void:
	if not port.has("conditions"):
		port.conditions={"schema":1,"health":80,"fatigue":15,"unrest":5,
			"foodSecurity":roundi(float(port.lastFoodMet)*100) if _num(port.get("lastFoodMet"),0,1) else 100,"reasons":["Awaiting daily facts."],
			"serviceDay":-1,"workerQ":0,"foremanQ":0}
static func _labor(b:Dictionary)->Dictionary:
	if not b.has("labor"):
		b.labor={"schema":1,"policy":"normal","cap":MAX,"fatigue":0,
			"unrest":0,"arrearsDays":0,"striking":false,"agreed":false,
			"restDays":0,"notice":"","lastProcessedEconomicDay":-1,
			"dealDay":-1,"spentDay":-1,"spent":0}
	return b.labor
static func _add(d:Dictionary,key:String,amount:int)->void:
	d[key]=clampi(int(d[key])+amount,0,100)

static func daily_port(p:Dictionary,days:float=1.0)->void:
	ensure(p)
	if days!=1.0 or validate_port(p)!="":
		return
	var c:Dictionary=p.conditions
	if not p.has("lastFoodMet") or not p.has("lastEmployed"):
		c.reasons=["Awaiting food/pay facts."]
		return
	var food:float=float(p.lastFoodMet)
	var jobs:float=minf(1,float(p.lastEmployed)/p.workforce) if p.workforce>0 else 1.0
	var paid:float=float(p.lastPaid)/p.lastEmployed if p.lastEmployed>0 else 1.0
	c.foodSecurity=roundi(food*100)
	_add(c,"health",roundi((food-0.9)*8))
	_add(c,"fatigue",roundi(2*jobs+4*(1-food)+4*(1-paid)-2))
	_add(c,"unrest",roundi(8*(1-paid)+4*(1-food)+4*(1-jobs)-2))
	c.reasons=[]
	if food<0.95:
		c.reasons.append("Purchased food: %d%% of need." % c.foodSecurity)
	if paid<1.0:
		c.reasons.append("Fully paid jobs: %d/%d." % [p.lastPaid,p.lastEmployed])
	if jobs<0.8:
		c.reasons.append("Employed: %d/%d." % [p.lastEmployed,p.workforce])
	if c.reasons.is_empty():
		c.reasons.append("Food and payroll needs met.")

static func report(p:Dictionary)->Dictionary:
	ensure(p)
	var error:=validate_port(p)
	if error!="":
		return {"valid":false,"message":error}
	var r:Dictionary=p.conditions.duplicate(true)
	r.valid=true
	r.pay="%s/%s fully paid jobs" % [p.get("lastPaid","?"),p.get("lastEmployed","?")]
	r.summary="Food %d%% | Health %d | Fatigue %d | Unrest %d" % [r.foodSecurity,r.health,r.fatigue,r.unrest]
	return r
static func _owned(core,id:Variant)->Dictionary:
	var list:Variant=core.state.get("businesses")
	if not (id is String) or not (list is Array) or list.size()>128:
		return {}
	for b in list:
		if b is Dictionary and b.get("id")==id:
			return b
	return {}

static func set_policy(core,id,policy)->Dictionary:
	var b:=_owned(core,id)
	if b.is_empty() or _bad(b)!="":
		return core.fail("Invalid owned business.")
	var l:=_labor(b)
	var mode:Variant=policy
	var cap:Variant=l.cap
	if policy is Dictionary:
		for key in policy:
			if key not in ["policy","cap"]:
				return core.fail("Invalid policy field.")
		mode=policy.get("policy")
		cap=policy.get("cap",cap)
	if not (mode is String) or mode not in POLICIES or not _whole(cap):
		return core.fail("Invalid policy/cap.")
	l.policy=mode
	l.cap=int(cap)
	return core.ok("Policy saved for next day.")
static func _reply(l:Dictionary,work:bool,factor:float,text:String)->Dictionary:
	l.notice=text
	return {"canWork":work,"workFactor":factor,"message":text}
static func _cost(b:Dictionary,share:float)->Dictionary:
	var r:Dictionary={"h":0,"e":0}
	for employee in b.employees:
		var key:="e" if employee.specialist else "h"
		r[key]+=ceili(float(employee.wage)*share)
	return r
static func _pay(core,b:Dictionary,p:Dictionary,h:int,e:int,reason:String)->bool:
	var l:=_labor(b)
	var day:=int(core.state.econDay)
	var spent:=int(l.spent) if l.spentDay==day else 0
	var total:=h+e
	if not (core.state.get("moneyLog") is Array) or not _move.is_valid() or total<0 or total>MAX or spent+total>l.cap or b.coins<total:
		return false
	if p.householdPurse+h>MAX or p.expertPurse+e>MAX:
		return false
	var src:Dictionary=b.duplicate(true)
	var dst:Dictionary=p.duplicate(true)
	var ledger:Array[Dictionary]=[]
	if h>0 and _move.call(src,"coins",dst,"householdPurse",h,reason,ledger)!=true:
		return false
	if e>0 and _move.call(src,"coins",dst,"expertPurse",e,reason,ledger)!=true:
		return false
	if src.coins!=b.coins-total or dst.householdPurse!=p.householdPurse+h or dst.expertPurse!=p.expertPurse+e:
		return false
	if core.state.moneyLog.size()+ledger.size()>8192:
		return false
	b.coins=int(src.coins)
	b.wagesPaid=int(b.wagesPaid)+total
	p.householdPurse=int(dst.householdPurse)
	p.expertPurse=int(dst.expertPurse)
	core.state.moneyLog.append_array(ledger)
	l.spentDay=day
	l.spent=spent+total
	return true
static func _rest(l:Dictionary,text:String)->Dictionary:
	_add(l,"fatigue",-18)
	_add(l,"unrest",-12)
	return _reply(l,false,0.0,text)

static func business_step(core,b:Dictionary,p:Dictionary,days:float=1.0)->Dictionary:
	b=_owned(core,b.get("id"))
	ensure(p)
	if days!=1.0 or not _whole(core.state.get("econDay"),MAX_DAY) or _bad(b)!="" or validate_port(p)!="" or b.homePort!=p.id:
		return {"canWork":false,"workFactor":0.0,"message":"Invalid workplace."}
	var l:=_labor(b)
	var day:=int(core.state.econDay)
	if day<=l.lastProcessedEconomicDay:
		return {"canWork":false,"workFactor":0.0,"message":l.notice}
	l.lastProcessedEconomicDay=day
	if b.arrearsHousehold+b.arrearsExpert>0:
		l.arrearsDays=mini(PEOPLE,int(l.arrearsDays)+1)
		_add(l,"unrest",12)
		l.agreed=false
		l.restDays=0
		if l.arrearsDays>=3:
			l.striking=true
		return _reply(l,false,0.0,"Wage arrears: day %d. %s" % [l.arrearsDays,"Stoppage; fund negotiation at home." if l.striking else "Warning: stoppage on day 3."])
	var base:=_cost(b,1.0)
	if b.employees.is_empty() or b.wagesPaid<base.h+base.e:
		return _reply(l,false,0.0,"Incomplete payroll; no paid recovery.")
	l.arrearsDays=0
	if l.striking:
		if l.agreed and day>l.dealDay:
			if l.restDays>0:
				l.restDays=int(l.restDays)-1
				return _rest(l,"Stoppage: %d paid rest days left." % l.restDays)
			if l.fatigue<=60 and l.unrest<=50:
				l.striking=false
				l.agreed=false
				l.policy="normal"
			else:
				return _rest(l,"Stoppage: paid recovery continues.")
		else:
			return _reply(l,false,0.0,"Stoppage: fund home negotiation and paid rest.")
	if l.policy=="rest":
		return _rest(l,"Paid rest; base wages, no production.")
	if b.paused:
		return _reply(l,false,0.0,"Paused; no extra spending.")
	if l.policy=="overtime" and l.fatigue<80:
		var extra:=_cost(b,0.5)
		if _pay(core,b,p,int(extra.h),int(extra.e),"Paid overtime"):
			_add(l,"fatigue",10)
			_add(l,"unrest",3 if l.fatigue>=60 else 0)
			return _reply(l,true,1.25,"Extra wages paid; fatigue rises.")
	if l.policy=="relief":
		var food:=maxi(1,b.employees.size())
		if b.inventory.get(_food,0)>=food:
			b.inventory[_food]-=food
			_add(l,"fatigue",-8)
			_add(l,"unrest",-8)
			return _reply(l,true,0.9,"Owned food, base pay; 10% prep time.")
	_add(l,"fatigue",-2)
	_add(l,"unrest",-2)
	return _reply(l,true,1.0,"Normal paid work." if l.policy=="normal" else "Normal work: policy needs cash/cap/food or more rest.")

static func negotiate(core,id)->Dictionary:
	var b:=_owned(core,id)
	if b.is_empty() or _bad(b)!="" or not _whole(core.state.get("econDay"),MAX_DAY):
		return core.fail("Invalid owned business.")
	var p:Dictionary=core.port(b.homePort)
	ensure(p)
	if validate_port(p)!="" or p.id!=b.homePort or not _gate.is_valid():
		return core.fail("Services closed.")
	var here:Variant=core.current_port()
	if not (here is Dictionary) or here.get("id")!=b.homePort:
		return core.fail("Dock at home harbor.")
	var l:=_labor(b)
	var day:=int(core.state.econDay)
	if not l.striking or l.agreed or l.dealDay==day:
		return core.fail("No new agreement available.")
	var access:Variant=_gate.call(core,b,p)
	if not (access is Dictionary) or access.get("allowed")!=true or not _whole(access.get("workers"),PEOPLE) or not _whole(access.get("foremen"),PEOPLE):
		return core.fail("Docking/service staff unavailable.")
	var c:Dictionary=p.conditions
	var workers:=int(c.workerQ) if c.serviceDay==day else 0
	var foremen:=int(c.foremanQ) if c.serviceDay==day else 0
	if workers+1>access.workers*4 or foremen+1>access.foremen*4:
		return core.fail("Worker/foreman time missing.")
	var food:=maxi(1,b.employees.size())
	if b.inventory.get(_food,0)<food or b.inventory.get(_supplies,0)<1:
		return core.fail("Owned food/supplies required.")
	var h:=int(b.arrearsHousehold)+ceili(float(_wages.laborer)/4.0)
	var e:=int(b.arrearsExpert)+ceili(float(_wages.foreman)/4.0)
	if not _pay(core,b,p,h,e,"Arrears and negotiation time"):
		return core.fail("Operating purse/cap too small.")
	b.arrearsHousehold=0
	b.arrearsExpert=0
	b.inventory[_food]-=food
	b.inventory[_supplies]-=1
	c.serviceDay=day
	c.workerQ=workers+1
	c.foremanQ=foremen+1
	l.dealDay=day
	l.agreed=true
	l.restDays=2
	l.arrearsDays=0
	l.policy="rest"
	l.notice="Arrears paid; two later paid rest days."
	return core.ok(l.notice)
static func _items(v:Variant,keys:Array,hi:int=MAX,counts:bool=false)->bool:
	if not (v is Dictionary) or v.size()>keys.size():
		return false
	for key in v:
		if key not in keys or not (_whole(v[key],hi) if counts else _num(v[key],0,hi)):
			return false
	return true
static func _fields(d:Dictionary,keys:Array,hi:int=MAX,lo:int=0)->bool:
	for key in keys:
		if not _whole(d.get(key),hi,lo):
			return false
	return true

static func validate_port(p:Dictionary)->String:
	if not (p.get("id") is String) or p.id.is_empty() or p.id.length()>80:
		return "Port ID."
	if not _fields(p,["cash","householdPurse","expertPurse","governmentPurse"]) or not _whole(p.get("workforce"),PEOPLE):
		return "Port amounts."
	if not _whole(p.get("availableWorkers"),int(p.workforce)):
		return "Workers."
	var experts:Variant=p.get("availableSpecialists")
	if not (_items(experts,_wages.keys(),PEOPLE,true) if experts is Dictionary else _whole(experts,PEOPLE)):
		return "Experts."
	if not _items(p.get("stocks"),_goods) or not _items(p.get("publicStores"),_goods):
		return "Port goods."
	if p.has("lastFoodMet") and not _num(p.lastFoodMet,0.0,1.0):
		return "Food fraction."
	if p.has("lastEmployed") or p.has("lastPaid"):
		if not _whole(p.get("lastEmployed"),PEOPLE) or not _whole(p.get("lastPaid"),int(p.lastEmployed)):
			return "Paid-job counts."
	if not p.has("conditions"):
		return ""
	var c:Variant=p.conditions
	if not (c is Dictionary) or not _whole(c.get("schema"),1,1):
		return "Schema."
	if not _fields(c,["health","fatigue","unrest","foodSecurity"],100) or not _fields(c,["workerQ","foremanQ"],PEOPLE*4):
		return "Scores."
	if not _whole(c.get("serviceDay"),MAX_DAY,-1) or not (c.get("reasons") is Array) or c.reasons.size()>8:
		return "History."
	for reason in c.reasons:
		if not (reason is String) or reason.length()>192:
			return "Reason."
	return ""
static func _bad(b:Dictionary)->String:
	for key in ["id","kind","homePort"]:
		if not (b.get(key) is String) or b[key].is_empty() or b[key].length()>80:
			return "Identity."
	if not _fields(b,["coins","wagesPaid","arrearsHousehold","arrearsExpert"]) or not _items(b.get("inventory"),_goods) or not _whole(b.get("capacity"),PEOPLE) or not (b.get("paused") is bool):
		return "Amounts."
	if not (b.get("employees") is Array) or b.employees.size()>256:
		return "Staff."
	for e in b.employees:
		if not (e is Dictionary) or e.get("occupation") not in _wages or not _whole(e.get("wage"),MAX,1) or not (e.get("specialist") is bool):
			return "Employee."
	if not b.has("labor"):
		return ""
	var l:Variant=b.labor
	if not (l is Dictionary) or not _whole(l.get("schema"),1,1) or l.get("policy") not in POLICIES:
		return "Labor."
	if not _fields(l,["cap","spent"]) or not _fields(l,["fatigue","unrest"],100) or not _whole(l.get("arrearsDays"),PEOPLE) or not _whole(l.get("restDays"),2) or not _fields(l,["lastProcessedEconomicDay","dealDay","spentDay"],MAX_DAY,-1):
		return "Labor bounds."
	if not (l.get("striking") is bool) or not (l.get("agreed") is bool) or (l.agreed and not l.striking) or (l.restDays>0 and not l.agreed):
		return "Stoppage."
	if not (l.get("notice") is String) or l.notice.length()>192:
		return "Labor notice."
	return ""

static func validate_state(state:Dictionary,world:Dictionary)->String:
	if not _num(state.get("day"),0.0,MAX_DAY) or not _whole(state.get("econDay"),MAX_DAY) or not _whole(state.get("coins")):
		return "Day/coins."
	if not (state.get("moneyLog") is Array) or state.moneyLog.size()>8192 or not (state.get("businesses") is Array) or state.businesses.size()>128:
		return "State arrays."
	if not (world.get("ports") is Array) or world.ports.size()>128 or not (world.get("businessHomes") is Dictionary) or world.businessHomes.size()>512:
		return "Registry missing."
	var ports:Array=[]
	for p in world.ports:
		if not (p is Dictionary) or validate_port(p)!="" or p.id in ports:
			return "Invalid/duplicate port."
		if p.has("conditions") and p.conditions.serviceDay>state.econDay:
			return "Future booking."
		ports.append(p.id)
	var ids:Array=[]
	for b in state.businesses:
		if not (b is Dictionary) or _bad(b)!="":
			return "Invalid owned business."
		if b.id in ids or b.homePort not in ports or world.businessHomes.get(b.id)!=b.homePort:
			return "Unknown/duplicate/moved ID."
		ids.append(b.id)
		if b.has("labor"):
			for key in ["lastProcessedEconomicDay","dealDay","spentDay"]:
				if b.labor[key]>state.econDay:
					return "Future labor day."
	return ""
