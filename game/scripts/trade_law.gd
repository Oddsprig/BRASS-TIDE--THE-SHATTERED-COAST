class_name TradeLaw
extends RefCounted
const Rules=preload("res://scripts/trade_rules.gd")
const World068=preload("res://scripts/ocean_world064.gd")
static var api:Dictionary={}
const CAP:=80
const MAX_Q:=1000000
const MILITARY:=["guns","engines"]
class View extends RefCounted:
	var state:Dictionary
	var data:Dictionary
	var harbor:Dictionary
	func _init(s:Dictionary,w:Dictionary,p:Dictionary):
		state=s;data=w;harbor=p
	func current_port()->Dictionary:
		return harbor
	func fail(message:String)->Dictionary:
		return {"ok":false,"message":message}
static func _acc(c,s,p)->Dictionary:return api.access.call(View.new(s,c.data,p),p)
static func configure(bindings:Dictionary):
	api=bindings.duplicate()
static func _ok(extra={})->Dictionary:return {"ok":true,"message":""}.merged(extra)
static func _no(message)->Dictionary:return {"ok":false,"message":message}
static func _uint(v)->bool:return _num(v) and int(v)==v
static func _num(v)->bool:return (v is int or v is float) and is_finite(v) and v>=0 and v<=1e12
static func _json(v,budget,depth:int=0)->bool:
	budget[0]-=1
	if budget[0]<0 or depth>32:return false
	match typeof(v):
		TYPE_NIL,TYPE_BOOL,TYPE_STRING,TYPE_STRING_NAME,TYPE_INT:return true
		TYPE_FLOAT:return is_finite(v)
		TYPE_ARRAY:
			for x in v:
				if not _json(x,budget,depth+1):return false
			return true
		TYPE_DICTIONARY:
			for k in v:
				if not (k is String or k is StringName) or not _json(v[k],budget,depth+1):return false
			return true
	return false
static func _world(c)->Dictionary:
	var ports: Array=c.data.PORTS.duplicate(true)
	if _installed068(c.state):ports.append(World068.remote_port068())
	return {"ports":ports,"factions":api.get("factions",[]),"goods":api.get("items",{})}
static func _installed068(s: Dictionary)->bool:
	var book=s.get("shipping068",{})
	return book is Dictionary and book.get("schema")==1 and book.get("installation") is Dictionary and book.installation.get("status")=="installed"
static func _port(s,id)->Dictionary:
	for p in s.ports:
		if p.id==id:return p
	return {}
static func _here(c,s)->Dictionary:return _port(s,str(c.current_port().get("id","")))
static func _point(p)->bool:
	return p is Dictionary and (p.get("x") is int or p.get("x") is float) and (p.get("y") is int or p.get("y") is float)
static func _stock(v,goods)->bool:
	if not v is Dictionary:return false
	for g in v:
		if not goods.has(g) or not _num(v[g]):return false
	return true
static func validate(s:Dictionary,w:Dictionary,pending:bool=false)->Array:
	var bad:=["Invalid state/book."]
	if not _json(s,[100000]):return ["Unsupported, nonfinite or overly nested campaign data."]
	if not w.get("ports") is Array or not w.get("factions") is Array or not w.get("goods") is Dictionary:
		return ["Unknown coast, factions or commodity definitions."]
	var defs:={}
	for p in w.ports:defs[p.id]=p.faction
	if _installed068(s):defs[World068.REMOTE_PORT068]="reed"
	for key in ["coins","crewPurse","econDay"]:
		if not _uint(s.get(key)):return ["Invalid captain purse or economic day."]
	if not _num(s.get("day")):return ["Invalid calendar day."]
	if not s.get("ports") is Array or s.ports.size()!=defs.size():return ["Wrong saved harbor collection."]
	if not _stock(s.get("cargo"),w.goods) or not _point(s.get("position")):return ["Invalid raw cargo or fleet position."]
	for k in ["patrols","fleetOwners"]:
		if not s.get(k,[]) is Array:return ["Invalid fleet observer collection."]
	var ids:={}
	for p in s.ports:
		if not p is Dictionary:return ["Malformed saved harbor."]
		var id=p.get("id")
		if not id is String or not defs.has(id) or ids.has(id):return ["Unknown or duplicate harbor identity."]
		ids[id]=true
		if not _point(p):return ["Invalid harbor position."]
		if id==World068.REMOTE_PORT068:
			for key in World068.remote_port068():
				if p.get(key)!=World068.remote_port068()[key]:return ["Invalid canonical Westglass harbor definition."]
		if p.get("faction")!=defs[id] or not w.factions.has(p.faction):return ["Harbor faction does not match the coast."]
		if not _stock(p.get("stocks"),w.goods) or not _stock(p.get("publicStores",{}),w.goods):return ["Invalid physical harbor inventory."]
		for k in ["cash","householdPurse","expertPurse","governmentPurse"]:
			if not _uint(p.get(k)):return ["Invalid harbor coin purse."]
		for k in ["availableWorkers","availableSpecialists","_yardWorkersUsed","_yardSpecialistsUsed"]:
			if not _num(p.get(k,0 if k.begins_with("_") else null)):return ["Invalid service workforce capacity."]
	if not s.get("moneyLog") is Array:return ["Missing coin transfer ledger."]
	if not s.has("tradeLaw"):return []
	var b=s.tradeLaw
	if not b is Dictionary:return ["Malformed trade-law book."]
	var keys:=["schema","next","mode","permits","lots","debts","bans","seen","stamp","seenBy"]
	if b.size()!=keys.size():return ["Unexpected trade-law account fields."]
	for k in keys:
		if not b.has(k):return ["Missing trade-law account fields."]
	if b.schema!=25 or not _uint(b.next) or b.next<1 or b.next>1e9 or not ["declared","concealed"].has(b.mode):
		return ["Invalid trade-law revision, identity or declaration."]
	if not _stock(b.seen,w.goods) or not _uint(b.stamp) or b.stamp>floor(s.day):return ["Invalid cargo observation or inspection date."]
	if not b.seenBy is Dictionary or b.seenBy.size()>256:return ["Inspection observer book exceeds its limit."]
	var seenBy:={}
	for p in s.ports:seenBy["port:"+p.id]=true
	for p in s.get("patrols",[]):
		if p is Dictionary and p.get("id") is String:seenBy["patrol:"+p.id]=true
	for k in b.seenBy:
		if k.length()>128 or (b.stamp==floor(s.day) and not seenBy.has(k)) or b.seenBy[k]!=true:return ["Unknown or malformed inspection observer."]
	var used:={}
	var tagged:={}
	for group in ["permits","lots","debts","bans"]:
		if not b[group] is Array or b[group].size()>CAP:return ["Trade-law record collection exceeds its limit."]
		for r in b[group]:
			if not r is Dictionary or not _uint(r.get("id")):return ["Malformed trade-law record identity."]
			if r.id<1 or r.id>=b.next or used.has(int(r.id)):return ["Duplicate or out-of-sequence trade-law identity."]
			used[int(r.id)]=true
			if group=="bans":
				if r.size()!=5 or not w.factions.has(r.get("issuer")) or not w.factions.has(r.get("target")) or r.issuer==r.target or not MILITARY.has(r.get("good")) or not w.goods.has(r.get("good")) or not _num(r.get("expires")) or r.expires>s.day+15:return ["Invalid military embargo agreement."]
				continue
			if not defs.has(r.get("port")):return ["Trade-law record names an unknown harbor."]
			if group=="debts":
				if r.size()!=3 or not _uint(r.get("amount")) or r.amount<1:return ["Invalid customs debt."]
				continue
			if not w.goods.has(r.get("good")):return ["Trade-law record names an unknown commodity."]
			var n=r.get("qty")
			if not _uint(n) or n>MAX_Q:return ["Invalid whole consignment quantity."]
			if group=="permits":
				if r.size()!=6 or not MILITARY.has(r.good) or not _uint(r.get("bound")) or r.bound>MAX_Q or not _num(r.get("expires")) or r.expires>s.day+30:return ["Invalid consignment coverage or expiry."]
				n=r.bound
			elif r.size()!=4 or n<1:return ["Invalid illicit cargo lot."]
			var key:String=(r.port+":" if group=="permits" else "")+r.good
			tagged[key]=tagged.get(key,0)+n
			if tagged[key]>(b.seen.get(r.good,0) if pending else s.cargo.get(r.good,0)):return ["Consignment coverage exceeds actual raw cargo."]
	return []
static func _id(b)->int:
	var id:=int(b.next)
	b.next+=1
	return id
static func _drop(s,g,qty:int):
	for r in s.tradeLaw.lots:
		if r.good==g:
			var n:=mini(qty,int(r.qty))
			r.qty-=n
			qty-=n
static func _clean(s):
	var b:Dictionary=s.tradeLaw
	for g in b.seen:_drop(s,g,maxi(0,int(b.seen[g])-int(s.cargo.get(g,0))))
	b.lots=b.lots.filter(func(r):return r.qty>0)
	b.permits=b.permits.filter(func(r):return r.expires>s.day)
	var room:={}
	for r in b.permits:
		var key:String=r.port+":"+r.good
		var n:=int(room.get(key,int(s.cargo.get(r.good,0))))
		r.bound=mini(int(r.bound),n)
		room[key]=n-r.bound
	b.bans=b.bans.filter(func(r):return r.expires>s.day)
	b.seen=s.cargo.duplicate()
	if b.stamp!=floori(s.day):b.stamp=floori(s.day);b.seenBy={}
static func _draft(c)->Dictionary:
	for key in ["price","access","permit","standing","relation","move","adjust"]:
		if not api.get(key) is Callable or not api[key].is_valid():return _no("Adapter missing")
	if not api.get("wages") is Dictionary or not _uint(api.wages.get("laborer")) or not _uint(api.wages.get("foreman")) or api.wages.laborer<1 or api.wages.foreman<1:return _no("Invalid wages")
	var s:Dictionary=c.state.duplicate(true)
	var e:=validate(s,_world(c),true)
	if not e.is_empty():return _no(str(e))
	if not s.has("tradeLaw"):
		s.tradeLaw={"schema":25,"next":1,"mode":"declared","permits":[],"lots":[],"debts":[],"bans":[],"seen":s.cargo.duplicate(),"stamp":floori(s.day),"seenBy":{}}
	_clean(s)
	e=validate(s,_world(c))
	return _ok({"state":s}) if e.is_empty() else _no(str(e))
static func publish(target: Dictionary,source: Dictionary) -> void:
	# Commit staged values while retaining live boat, business, port and purse references.
	for key in target.keys():
		if not source.has(key):target.erase(key)
	for key in source:
		var incoming=source[key]
		if incoming is Dictionary and target.get(key) is Dictionary:
			publish(target[key],incoming)
		elif incoming is Array and target.get(key) is Array:
			var live: Array=target[key]
			while live.size()>incoming.size():live.pop_back()
			for i in range(incoming.size()):
				if i>=live.size():live.append(incoming[i].duplicate(true) if incoming[i] is Dictionary or incoming[i] is Array else incoming[i])
				elif incoming[i] is Dictionary and live[i] is Dictionary:publish(live[i],incoming[i])
				else:live[i]=incoming[i].duplicate(true) if incoming[i] is Dictionary or incoming[i] is Array else incoming[i]
		else:target[key]=incoming.duplicate(true) if incoming is Dictionary or incoming is Array else incoming

static func _put(c,s,extra={})->Dictionary:
	_clean(s)
	var e:=validate(s,_world(c))
	if not e.is_empty():return _no(str(e))
	publish(c.state,s)
	return _ok(extra)
static func ensure(c)->Dictionary:
	var d:=_draft(c)
	return _put(c,d.state) if d.ok else d
static func reconcile(c)->Dictionary:return ensure(c)
static func daily(c)->Dictionary:return ensure(c)
static func set_mode(c,mode:String)->Dictionary:
	if not ["declared","concealed"].has(mode):return _no("Invalid mode")
	var d:=_draft(c)
	if not d.ok:return d
	d.state.tradeLaw.mode=mode
	return _put(c,d.state)
static func _friend(s,faction)->bool:return api.standing.call(s,faction).get("score",-100)>=20
static func _fee(p,days:float)->Dictionary:
	var a:=ceili(float(api.wages.laborer)*days)
	var b:=ceili(float(api.wages.foreman)*days)
	return {"labor":a,"expert":b,"total":a+b,"days":days,"room":float(p.get("_yardWorkersUsed",0))+days*2<=p.availableWorkers and float(p.get("_yardSpecialistsUsed",0))+days<=p.availableSpecialists}
static func _move(s,a,ak,b,bk,n:int,reason)->bool:return n==0 or api.move.call(a,ak,b,bk,n,reason,s.moneyLog)
static func _pay(s,p,fee)->bool:
	if not _move(s,s,"coins",p,"householdPurse",fee.labor,"Registry labor"):return false
	if not _move(s,s,"coins",p,"expertPurse",fee.expert,"Registry foreman"):return false
	p._yardWorkersUsed=p.get("_yardWorkersUsed",0)+fee.days*2
	p._yardSpecialistsUsed=p.get("_yardSpecialistsUsed",0)+fee.days
	return true
static func _svc(c,s,p)->bool:
	var a:=_acc(c,s,p)
	return a.get("legal",false) and not a.get("hostile",false) and api.permit.call(View.new(s,c.data,p),"service","").get("ok",false)
static func license_quote(c,g:String,qty:int)->Dictionary:
	var d:=_draft(c)
	if not d.ok:return d
	var p:=_here(c,d.state)
	if p.is_empty() or not MILITARY.has(g) or qty<1 or qty>MAX_Q:return _no("Invalid license")
	if not _svc(c,d.state,p):return _no("Registry denied")
	var f:=_fee(p,0.25)
	if not f.room or d.state.coins<f.total or d.state.tradeLaw.permits.size()>=CAP:return _no("Registry full/unfunded")
	return _ok({"port":p.id,"good":g,"qty":qty,"expires":float(d.state.day)+30.0,"fee":f})
static func buy_license(c,g:String,qty:int)->Dictionary:
	var q:=license_quote(c,g,qty)
	if not q.ok:return q
	var d:=_draft(c)
	if not d.ok:return d
	var s:Dictionary=d.state
	if not _pay(s,_port(s,q.port),q.fee):return _no("Unpaid registry")
	s.tradeLaw.permits.append({"id":_id(s.tradeLaw),"port":q.port,"good":g,"qty":qty,"bound":0,"expires":q.expires})
	return _put(c,s,q)
static func _sum(s,pid,g,field)->int:
	var n:=0
	for r in s.tradeLaw.permits:
		if r.port==pid and r.good==g and r.expires>s.day:n+=int(r[field])
	return n
static func licensed(c,pid:String,g:String,qty:int=1)->bool:
	var d:=_draft(c)
	if not d.ok or qty<1 or not api.items.has(g):return false
	var p:=_port(d.state,pid)
	if p.is_empty() or not _svc(c,d.state,p):return false
	return _friend(d.state,p.faction) or _sum(d.state,pid,g,"qty")>=qty
static func _bind(s,pid,g,qty:int):
	_drop(s,g,qty)
	var left:=qty
	for r in s.tradeLaw.permits:
		if r.port==pid and r.good==g:
			var n:=mini(left,int(r.qty))
			r.qty-=n
			r.bound+=n
			left-=n
static func consume_license(c,pid:String,g:String,qty:int)->Dictionary:
	var d:=_draft(c)
	if not d.ok:return d
	var s:Dictionary=d.state
	var p:=_port(s,pid)
	if p.is_empty() or c.current_port().get("id")!=pid or qty<1 or not api.items.has(g) or not _svc(c,s,p):return _no("Bad consignment")
	if _friend(s,p.faction):return _put(c,s)
	var bound:=_sum(s,pid,g,"bound")
	if qty>int(s.cargo.get(g,0))-bound or _sum(s,pid,g,"qty")<qty:return _no("Permit/cargo exhausted")
	_bind(s,pid,g,qty)
	return _put(c,s)
static func illicit_quote(c,g:String,qty:int,side:String="buy")->Dictionary:
	var d:=_draft(c)
	if not d.ok:return d
	if not api.items.has(g) or qty<1 or qty>MAX_Q or not ["buy","sell"].has(side):return _no("Invalid counter")
	var s:Dictionary=d.state
	var p:=_here(c,s)
	if p.is_empty():return _no("No nearby counter")
	var reason:String="Civilian broker: "+p.id
	if not _svc(c,s,p):
		if MILITARY.has(g) or not api.has("contact"):return _no("No hostile service bypass")
		var contact:Dictionary=api.contact.call(View.new(s,c.data,p),p,g)
		if not contact.get("ok",false) or str(contact.get("reason","")).is_empty() or not contact.get("goods",[]).has(g):return _no("Contact denied")
		reason=contact.reason
	var fee:=_fee(p,0.1)
	if not fee.room:return _no("Broker capacity")
	var price=api.price.call(p,g,side)
	if not _uint(price) or price<=0:return _no("Invalid price")
	var unit:=int(price)
	unit=ceili(unit*1.15) if side=="buy" else maxi(1,floori(unit*0.85))
	var n:=qty
	if side=="buy":
		if not api.has("exportable"):return _no("Bind exportable")
		var loose=api.exportable.call(View.new(s,c.data,p),p,g)
		if not _num(loose):return _no("Bad export stock")
		var weight=api.items[g].weight
		if not _num(weight) or weight<=0:return _no("Bad weight")
		n=mini(n,mini(int(p.stocks.get(g,0)),int(loose)))
		n=mini(n,maxi(0,floori((c.capacity()-c.cargo_weight())/weight)))
		n=mini(n,maxi(0,floori((float(s.coins)-fee.total)/unit)))
		if s.tradeLaw.lots.size()>=CAP:return _no("Lot book full")
	else:
		n=mini(n,mini(int(s.cargo.get(g,0)),floori(float(p.cash)/unit)))
		if s.coins+n*unit<fee.total:n=0
	if n<1:return _no("Stock/hold/funds empty")
	return _ok({"port":p.id,"good":g,"side":side,"qty":n,"unit":unit,"value":n*unit,"fee":fee,"reason":reason})
static func illicit_trade(c,g:String,qty:int,side:String="buy")->Dictionary:
	var q:=illicit_quote(c,g,qty,side)
	if not q.ok:return q
	var d:=_draft(c)
	if not d.ok:return d
	var s:Dictionary=d.state
	var p:=_port(s,q.port)
	var n:=int(q.qty)
	if side=="buy":
		if not _move(s,s,"coins",p,"cash",q.value,"Illicit purchase"):return _no("Purchase unpaid")
		p.stocks[g]=p.stocks.get(g,0)-n
		s.cargo[g]=s.cargo.get(g,0)+n
		s.tradeLaw.lots.append({"id":_id(s.tradeLaw),"port":p.id,"good":g,"qty":n})
	else:
		if not _move(s,p,"cash",s,"coins",q.value,"Illicit sale"):return _no("Counter unpaid")
		s.cargo[g]-=n
		p.stocks[g]=p.stocks.get(g,0)+n
	if not _pay(s,p,q.fee):return _no("Broker unpaid")
	return _put(c,s,q)
static func _witness(c,s,arg)->Dictionary:
	if not api.has("near"):return {}
	if arg==null:arg=c.current_port()
	if not arg is Dictionary:return {}
	var id:=str(arg.get("id",""))
	var p:=_port(s,id)
	if not p.is_empty():
		if not api.near.call(c,p) or not _acc(c,s,p).get("inspection",false):return {}
		return {"key":"port:"+id,"port":id,"reason":"Port witness: "+id}
	for patrol in c.state.get("patrols",[]):
		if not _point(patrol):continue
		if patrol.get("id")!=id or patrol.get("kind")!="patrol" or patrol.get("active")!=true:continue
		for owner in c.state.get("fleetOwners",[]):
			if not owner is Dictionary:continue
			if owner.get("id")!=patrol.get("ownerId") or not api.factions.has(owner.get("faction")):continue
			if not api.has("eligible_patrol") or not api.eligible_patrol.call(c,patrol,owner) or not api.near.call(c,patrol):return {}
			var home:=_port(s,str(owner.get("homePort","")))
			if home.is_empty() or home.faction!=owner.faction:return {}
			return {"key":"patrol:"+id,"port":home.id,"reason":"Patrol witness: "+id+"; custodian "+home.id}
	return {}
static func inspect(c,observer:Variant=null)->Dictionary:
	var d:=_draft(c)
	if not d.ok:return d
	var w:=_witness(c,d.state,observer)
	if w.is_empty():return _no("No nearby witness")
	var s:Dictionary=d.state
	var b:Dictionary=s.tradeLaw
	if b.seenBy.has(w.key):return _ok({"repeated":true,"reason":w.reason})
	if b.seenBy.size()>=256:return _no("Witness book full")
	var p:=_port(s,w.port)
	var access:=_acc(c,s,p)
	var legal:bool=access.get("legal",false) and not access.get("hostile",false)
	var goods:Array=s.cargo.keys()
	goods.sort()
	var seed:String=str(floori(s.day))+":"+str(int(s.econDay))+":"+w.key+":"+b.mode
	for g in goods:seed+=":"+str(g)+"="+str(float(s.cargo[g]))
	var found:bool=b.mode=="declared" or seed.hash()%100<45
	b.seenBy[w.key]=true
	if not found:return _put(c,s,{"detected":false,"reason":w.reason})
	var seized:={}
	var total:float=0
	for g in goods:
		if not access.get("restrictedGoods",[]).has(g):continue
		if legal and _friend(s,p.faction):continue
		var cover:=0
		if legal:
			cover=_sum(s,p.id,g,"bound")
			var use:=mini(maxi(0,int(s.cargo[g])-cover),_sum(s,p.id,g,"qty"))
			_bind(s,p.id,g,use)
			cover+=use
		var n:=maxf(0,float(s.cargo[g])-cover)
		if n==0:continue
		s.cargo[g]-=n
		if not p.has("publicStores"):p.publicStores={}
		p.publicStores[g]=p.publicStores.get(g,0)+n
		seized[g]=n
		total+=n
	var fine:=mini(ceili(api.wages.laborer*(0.5+0.1*total)),ceili(api.wages.laborer*20)) if total>0 else 0
	var paid:=mini(int(s.coins),fine)
	if fine>paid and b.debts.size()>=CAP:return _no("Debt book full")
	if not _move(s,s,"coins",p,"governmentPurse",paid,"Customs fine"):return _no("Fine unpaid")
	if fine>paid:b.debts.append({"id":_id(b),"port":p.id,"amount":fine-paid})
	if total>0:
		var event:="trade-law:"+str(_id(b))
		if not api.adjust.call(s,p.faction,-2,w.reason,event).get("ok",false):return _no("Reputation failed")
	return _put(c,s,{"detected":true,"seized":seized,"fine":fine,"paid":paid,"debt":fine-paid,"reason":w.reason})
static func pay_fine(c,id:int,amount:int=-1)->Dictionary:
	var d:=_draft(c)
	if not d.ok:return d
	var s:Dictionary=d.state
	for debt in s.tradeLaw.debts:
		if debt.id!=id:continue
		var n:=mini(int(s.coins),int(debt.amount))
		if amount!=-1:n=mini(n,amount)
		if n<1:return _no("No affordable payment")
		if not _move(s,s,"coins",_port(s,debt.port),"governmentPurse",n,"Fine debt"):return _no("Debt unpaid")
		debt.amount-=n
		s.tradeLaw.debts=s.tradeLaw.debts.filter(func(r):return r.amount>0)
		return _put(c,s,{"paid":n})
	return _no("Unknown debt")
static func negotiate_embargo(c,target:String,g:String)->Dictionary:
	var d:=_draft(c)
	if not d.ok:return d
	var s:Dictionary=d.state
	var p:=_here(c,s)
	if p.is_empty() or not MILITARY.has(g) or not api.factions.has(target):return _no("Invalid embargo")
	if not _svc(c,s,p) or not _friend(s,p.faction) or api.relation.call(s,p.faction,target)>-20 or p.faction==target:return _no("Ineligible trade pair")
	for r in s.tradeLaw.bans:
		if r.issuer==p.faction and r.target==target and r.good==g:return _no("Concession active")
	var fee:=_fee(p,0.25)
	if not fee.room or s.coins<fee.total or s.tradeLaw.bans.size()>=CAP:return _no("Government full/unfunded")
	if not _pay(s,p,fee):return _no("Concession unpaid")
	s.tradeLaw.bans.append({"id":_id(s.tradeLaw),"issuer":p.faction,"target":target,"good":g,"expires":float(s.day)+15.0})
	return _put(c,s,{"expires":float(s.day)+15.0,"fee":fee.total})
static func trade_allowed(c,a:String,b:String,g:String)->bool:
	if not api.get("items",{}).has(g) or a not in api.get("factions",[]) or b not in api.get("factions",[]):return false
	if not c.state.has("tradeLaw"):return true
	var book=c.state.tradeLaw
	if not book is Dictionary or not book.get("bans") is Array:return false
	return Rules.allowed(book.bans,a,b,g,float(c.state.day))
