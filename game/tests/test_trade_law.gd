extends SceneTree
const T=preload("res://scripts/trade_law.gd")
const M=preload("res://scripts/money.gd")
const G=preload("res://scripts/goods.gd")
var checks:int=0
var failures:int=0
class Core extends RefCounted:
	var state:Dictionary
	var data:Dictionary
	var hold:float=30
	func current_port()->Dictionary:
		for p in state.ports:
			if distance(state.position,p)<65:return p
		return {}
	func distance(a:Dictionary,b:Dictionary)->float:
		return Vector2(a.x,a.y).distance_to(Vector2(b.x,b.y))
	func capacity()->float:return hold
	func cargo_weight()->float:
		var n:float=0
		for g in state.cargo:n+=float(state.cargo[g])*float(G.ITEMS[g].weight)
		return n
func ck(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;print("FAIL trade law: ",message)
func fresh()->Core:
	var c:=Core.new()
	c.data={"PORTS":[{"id":"a","faction":"compact"}]}
	c.state={"coins":10000,"crewPurse":100,"day":2.75,"econDay":2,"position":{"x":0,"y":0},"path":[],"cargo":{},"moneyLog":[],"ports":[],"patrols":[],"fleetOwners":[],"scores":{},"blocked":false,"relationships":{},"repEvents":[],"fitted":{"guns":7},"freight":{"good":"guns","qty":9}}
	c.state.ports.append({"id":"a","faction":"compact","x":0,"y":0,"stocks":{"guns":20.5,"food":10},"publicStores":{},"cash":5000,"householdPurse":100,"expertPurse":100,"governmentPurse":100,"availableWorkers":10,"availableSpecialists":10,"_yardWorkersUsed":0,"_yardSpecialistsUsed":0})
	return c
func access(c,p)->Dictionary:
	c.state.queryInitialized=true
	return {"legal":not c.state.blocked,"restrictedGoods":["guns","engines"],"inspection":true}
func permit(c,_action,_item)->Dictionary:
	return {"ok":not c.state.blocked and c.state.path.is_empty()}
func standing(s,f)->Dictionary:return {"score":s.scores.get(f,0)}
func relation(_s,a:String,b:String)->int:
	return -20 if (a=="compact" and b=="forge") or (b=="compact" and a=="forge") else 0
func price(_p,_g,side:String)->int:return 100 if side=="buy" else 80
func exportable(_c,p,g)->float:return maxf(0,float(p.stocks.get(g,0))-2)
func near(c,p)->bool:return c.distance(c.state.position,p)<65
func eligible(_c,_p,_o)->bool:return true
func adjust(s:Dictionary,f:String,n:int,_why:String,event:String)->Dictionary:
	if not s.repEvents.has(event):s.repEvents.append(event);s.scores[f]=s.scores.get(f,0)+n
	return {"ok":true}
func fail_expert(a:Dictionary,ak:String,b:Dictionary,bk:String,n:int,why:String,ledger:Array)->bool:
	return false if bk=="expertPurse" else M.move(a,ak,b,bk,n,why,ledger)
func setup()->void:
	T.configure({"items":G.ITEMS,"wages":G.WAGES,"factions":["compact","forge","reed"],"price":price,"access":access,"permit":permit,"standing":standing,"relation":relation,"move":M.move,"adjust":adjust,"exportable":exportable,"near":near,"eligible_patrol":eligible})
func harbor(c)->Dictionary:return c.state.ports[0]
func funds(c)->int:return M.total(c.state)
func raw(c:Core,g:String)->float:
	var n:float=float(c.state.cargo.get(g,0))
	for p in c.state.ports:n+=float(p.stocks.get(g,0))+float(p.publicStores.get(g,0))
	return n
func snap(c)->String:return JSON.stringify(c.state)
func _initialize()->void:
	setup()
	var c:=fresh()
	var prior:=snap(c)
	var q:=T.illicit_quote(c,"guns",100)
	ck(q.ok and q.qty==10 and snap(c)==prior,"quote")
	c.hold=0
	ck(not T.illicit_trade(c,"guns",1).ok and snap(c)==prior,"hold")
	c.hold=30
	var total:=funds(c)
	var lots:=raw(c,"guns")
	ck(T.illicit_trade(c,"guns",2).ok,"purchase")
	ck(harbor(c).stocks.guns==18.5 and c.state.cargo.guns==2,"inventory")
	c.hold=300;harbor(c).stocks.guns-=1;c.state.cargo.guns+=1
	M.move(c.state,"coins",harbor(c),"cash",100,"Legal fresh",c.state.moneyLog)
	ck(T.illicit_quote(c,"guns",100).qty==15,"shared-stock")
	var purse:int=c.state.coins
	ck(T.illicit_trade(c,"guns",2,"sell").ok and c.state.coins<purse+160,"wages")
	ck(funds(c)==total and raw(c,"guns")==lots and c.state.coins<10000,"conservation")
	harbor(c).cash=0
	prior=snap(c)
	ck(not T.illicit_trade(c,"guns",1,"sell").ok and snap(c)==prior,"liquidity")
	setup();c=fresh();prior=snap(c)
	T.api.move=fail_expert
	ck(not T.buy_license(c,"guns",2).ok and snap(c)==prior,"rollback")
	setup();c=fresh();c.state.cargo.guns=2
	total=funds(c)
	q=T.license_quote(c,"guns",2)
	ck(q.ok and q.expires==32.75 and q.fee.total==69,"terms")
	ck(T.buy_license(c,"guns",2).ok and harbor(c)._yardWorkersUsed==0.5 and harbor(c)._yardSpecialistsUsed==0.25,"clerks")
	ck(T.consume_license(c,"a","guns",2).ok and not T.licensed(c,"a","guns",1),"allowance")
	prior=snap(c)
	ck(not T.consume_license(c,"a","guns",1).ok and snap(c)==prior,"reuse")
	q=T.inspect(c)
	ck(q.ok and q.seized.is_empty() and funds(c)==total,"consignment")
	c.state.day=32.75;c.state.econDay=32
	ck(T.daily(c).ok and c.state.tradeLaw.permits.is_empty(),"expiry")
	ck(T.inspect(c).seized.get("guns",0)==2,"expired")
	c=fresh();c.state.scores.compact=20;c.state.cargo.guns=3
	ck(T.licensed(c,"a","guns",3) and T.inspect(c).seized.is_empty(),"Friendly")
	c=fresh();c.state.coins=10;c.state.cargo.guns=3
	c.state.position.x=500
	prior=snap(c)
	ck(not T.inspect(c,harbor(c)).ok and snap(c)==prior,"unobserved")
	ck(not T.inspect(c,{"id":"fake-patrol"}).ok and snap(c)==prior,"fabrication")
	c.state.position.x=0
	total=funds(c);lots=raw(c,"guns")
	q=T.inspect(c)
	ck(q.ok and q.paid==10 and q.debt==70 and harbor(c).publicStores.guns==3,"debt")
	ck(c.state.fitted.guns==7 and c.state.freight.qty==9 and funds(c)==total and raw(c,"guns")==lots,"custody")
	prior=snap(c)
	ck(T.inspect(c).repeated and snap(c)==prior and c.state.repEvents.size()==1,"idempotence")
	var debt:int=c.state.tradeLaw.debts[0].id
	M.move(harbor(c),"cash",c.state,"coins",70,"Fund debt fresh",c.state.moneyLog)
	ck(T.pay_fine(c,debt).ok and c.state.tradeLaw.debts.is_empty() and funds(c)==total,"repayment")
	c=fresh();c.state.cargo.guns=1
	c.state.fleetOwners=[{"id":"watch","faction":"compact","homePort":"a"}]
	c.state.patrols=[{"id":"watch-1","ownerId":"watch","kind":"patrol","active":true,"x":0,"y":0}]
	ck(T.inspect(c,c.state.patrols[0]).ok and harbor(c).publicStores.guns==1,"patrol")
	var hidden:=false
	for day in range(1,33):
		c=fresh();c.state.day=day;c.state.econDay=day;c.state.cargo.guns=2
		T.set_mode(c,"concealed")
		var copy:=fresh();copy.state=JSON.parse_string(snap(c))
		q=T.inspect(c)
		var again:=T.inspect(copy)
		ck(q.ok and again.ok and q.detected==again.detected,"determinism")
		if not q.detected:
			hidden=true
			ck(c.state.cargo.guns==2 and harbor(c).publicStores.is_empty(),"unseen")
			prior=snap(c)
			ck(T.inspect(c).repeated and snap(c)==prior,"reroll")
			break
	ck(hidden,"concealment")
	c=fresh();prior=snap(c)
	ck(not T.negotiate_embargo(c,"forge","guns").ok and snap(c)==prior,"neutral")
	c.state.scores.compact=20
	total=funds(c);purse=c.state.coins
	ck(T.negotiate_embargo(c,"forge","guns").ok and purse-c.state.coins==69 and funds(c)==total,"concession")
	ck(not T.trade_allowed(c,"compact","forge","guns") and not T.trade_allowed(c,"forge","compact","guns") and T.trade_allowed(c,"compact","forge","food") and T.trade_allowed(c,"reed","forge","guns"),"scope")
	prior=snap(c)
	ck(not T.negotiate_embargo(c,"forge","guns").ok and not T.negotiate_embargo(c,"reed","guns").ok and not T.negotiate_embargo(c,"forge","ammo").ok and snap(c)==prior,"definitions")
	c.state.day+=15
	ck(T.trade_allowed(c,"compact","forge","guns") and relation(c.state,"compact","forge")==-20,"restoration")
	c=fresh();harbor(c).availableSpecialists=0
	prior=snap(c)
	ck(not T.buy_license(c,"guns",1).ok and snap(c)==prior,"capacity")
	c=fresh();ck(T.ensure(c).ok,"migration")
	var world:Dictionary=T._world(c)
	var saved:Dictionary=JSON.parse_string(snap(c))
	ck(T.validate(saved,world).is_empty(),"JSON")
	for field in ["cash","governmentPurse"]:
		var bad:Dictionary=saved.duplicate(true);bad.ports[0][field]=NAN
		ck(not T.validate(bad,world).is_empty(),"NaN")
	var bad:Dictionary=saved.duplicate(true);bad.metadata={"nested":[INF]}
	ck(not T.validate(bad,world).is_empty(),"INF")
	c.state.tradeLaw.mode="bad";prior=snap(c)
	ck(not T.ensure(c).ok and snap(c)==prior,"malformed")
	c=fresh();T.buy_license(c,"guns",2);saved=c.state.duplicate(true)
	for row in [["port","missing"],["port",7],["good","invented"],["qty",0.5],["id",0]]:
		bad=saved.duplicate(true);bad.tradeLaw.permits[0][row[0]]=row[1]
		ck(not T.validate(bad,world).is_empty(),"references")
	bad=saved.duplicate(true);bad.tradeLaw.next=3
	bad.tradeLaw.bans=[{"id":2,"issuer":"unknown","target":"forge","good":"guns","expires":10}]
	ck(not T.validate(bad,world).is_empty(),"faction")
	bad=saved.duplicate(true);bad.tradeLaw.permits.resize(81)
	ck(not T.validate(bad,world).is_empty(),"bounds")
	c.state.cargo.guns=4;T.illicit_trade(c,"guns",1)
	c.state.cargo.guns=0
	ck(T.reconcile(c).ok and c.state.tradeLaw.lots.is_empty(),"loss")
	c.state.cargo.guns=2;T.reconcile(c)
	ck(c.state.tradeLaw.lots.is_empty(),"respawn")
	print("trade law: %d checks, %d failures; native candidate" % [checks,failures])
	quit(0 if failures==0 else 1)
