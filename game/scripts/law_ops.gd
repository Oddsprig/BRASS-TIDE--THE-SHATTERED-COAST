extends RefCounted
const Locality064=preload("res://scripts/expedition.gd")
## Main-thread customs publication and cheap read-only carrier policy snapshots.
const Law=preload("res://scripts/trade_law.gd")
const Rules=preload("res://scripts/trade_rules.gd")
const Goods=preload("res://scripts/goods.gd")
const Economy=preload("res://scripts/economy.gd")
const Money=preload("res://scripts/money.gd")
const Politics=preload("res://scripts/politics.gd")
const Factions=preload("res://scripts/factions.gd")
const Reserves=preload("res://scripts/harbor_reserves.gd")

static func configure(c) -> void:
	Law.configure({"items":Goods.ITEMS,"wages":Goods.WAGES,"factions":c.data.FACTIONS.map(func(f):return str(f.id)),"price":Economy.price,"access":Politics.access,"permit":Politics.permit,"standing":Factions.standing,"relation":Factions.relation,"move":Money.move,"adjust":Factions.adjust,"exportable":exportable,"near":near,"eligible_patrol":eligible,"contact":contact})

static func ensure(c) -> void:
	configure(c)
	var result: Dictionary=Law.ensure(c)
	if not result.ok:push_error("Trade-law initialization refused: "+str(result.message));return
	refresh(c)

static func exportable(_view,p: Dictionary,good: String) -> float:
	return float(Reserves.exportable(p,good)) if p.get("reserves") is Dictionary else float(p.stocks.get(good,0))

static func near(c,record: Dictionary) -> bool:
	return Locality064.home_local064(c.state) and c.distance(c.state.position,record)<(65.0 if record.has("stocks") else 120.0)

static func eligible(c,p: Dictionary,o: Dictionary) -> bool:
	if o.get("playerCompany",false) or o.get("kind","")!="patrol" or not o.get("active",false) or str(o.id)!=str(p.id) or str(p.get("ownerId",""))!=str(o.id):return false
	if Factions.is_hostile(c.state,str(o.faction)):return false
	for port in c.state.ports:
		if port.faction==o.faction and c.distance(p,port)<=1600:return true
	return false

static func contact(view,p: Dictionary,good: String) -> Dictionary:
	var active: bool=float(view.state.get("relationships",{}).get("safeConduct",{}).get(p.id,0))>float(view.state.day)
	return {"ok":active and good not in ["guns","engines"],"reason":"Paid civilian safe-conduct authorizes this local civilian broker.","goods":Goods.ITEMS.keys().filter(func(g):return g not in ["guns","engines"])}

static func refresh(c) -> void:
	var bans: Array=c.state.get("tradeLaw",{}).get("bans",[])
	for p in c.state.ports:p.tradeBans=bans.duplicate(true);p.tradeLawDay=float(c.state.day)
	for o in c.state.fleetOwners:o.tradeBans=bans.duplicate(true);o.tradeLawDay=float(c.state.day)
	for p in c.state.patrols:
		var o: Dictionary=c.fleet_owner(str(p.id))
		if o.is_empty():continue
		p.ownerId=str(o.id);p.kind=str(o.kind)

static func clock(c) -> void:
	for p in c.state.ports:p.tradeLawDay=float(c.state.day)
	for o in c.state.fleetOwners:o.tradeLawDay=float(c.state.day)

static func daily(c) -> void:
	var result: Dictionary=Law.daily(c)
	if not result.ok:push_error("Trade-law daily reconciliation refused: "+str(result.message));return
	refresh(c)

static func reconcile(c) -> void:
	if not c.state.has("tradeLaw"):return
	var result: Dictionary=Law.reconcile(c)
	if not result.ok:push_error("Raw cargo provenance could not reconcile: "+str(result.message))

static func allow_player(c,p: Dictionary,good: String) -> bool:
	var commission: String=str(c.state.get("relationships",{}).get("commission",{}).get("factionId",""))
	return true if commission.is_empty() else Law.trade_allowed(c,commission,str(p.faction),good)

static func inspect(c,observer: Dictionary) -> Dictionary:
	if not Locality064.home_local064(c.state):return c.fail("Customs contacts require Shatter Coast waters.")
	var key: String=("port:" if observer.has("stocks") else "patrol:")+str(observer.id)
	var book: Dictionary=c.state.get("tradeLaw",{})
	if int(book.get("stamp",-1))==floori(float(c.state.day)) and book.get("seenBy",{}).has(key):return {"ok":true,"message":"Today's manifest encounter is already recorded.","repeated":true}
	var result: Dictionary=Law.inspect(c,observer)
	if not result.ok:return result
	c.Manifest.allocate(c.state)
	if not result.get("seized",{}).is_empty():
		var lots: Array=[]
		for good in result.seized:lots.append("%.2f %s"%[float(result.seized[good]),str(Goods.ITEMS[good].name)])
		result.message="Customs at %s seized %s. Fine %d coins: %d paid, %d still owed."%[str(result.get("reason","the observer")),", ".join(lots),int(result.fine),int(result.paid),int(result.debt)]
		c.log_entry(result.message)
	else:result.message="Manifest encounter recorded. "+str(result.get("reason",""))
	return result

static func check_patrols(c) -> void:
	if not c.state.has("tradeLaw"):return
	var candidates: Array=[]
	for p in c.state.patrols:
		if p.get("kind","")!="patrol" or not p.get("active",false) or not near(c,p):continue
		var o: Dictionary=c.fleet_owner(str(p.id))
		if not o.is_empty() and eligible(c,p,o):candidates.append(str(p.id))
	for id in candidates:
		for p in c.state.patrols:
			if str(p.id)==id:inspect(c,p);break

static func license(c,good: String,count: int) -> Dictionary:
	var result: Dictionary=Law.buy_license(c,good,count)
	if result.ok:result.message="Registered %d %s lots for this harbor, valid thirty days. The clerk and foreman were paid; actual market stock must still be purchased."%[count,str(Goods.ITEMS[good].name)];refresh(c)
	return result

static func illicit(c,good: String,count: int,side: String) -> Dictionary:
	var result: Dictionary=Law.illicit_trade(c,good,count,side)
	if result.ok:
		refresh(c);c.Manifest.allocate(c.state);c.TradeFlow.observe(c)
		result.message="%s %d %s lots for %d coins plus %d coins paid broker labor. Stock and purse transfers are actual; raw cargo remains subject to local customs."%["Bought" if side=="buy" else "Sold",int(result.qty),str(Goods.ITEMS[good].name),int(result.value),int(result.fee.total)]
	return result

static func embargo(c,target: String,good: String) -> Dictionary:
	var result: Dictionary=Law.negotiate_embargo(c,target,good)
	if result.ok:refresh(c);result.message="Paid fifteen-day %s trade restriction agreed for %s and %s faction carriers. Food, fuel, ammunition and civilian goods remain outside this agreement."%[str(Goods.ITEMS[good].name),str(c.current_port().faction),target]
	return result

static func pay(c,id: int) -> Dictionary:
	for debt in c.state.tradeLaw.debts:
		if int(debt.id)!=id:continue
		if c.current_port().get("id","")!=debt.port:return c.fail("Visit "+str(c.port(debt.port).name)+" to settle its customs debt.")
		var result: Dictionary=Law.pay_fine(c,id)
		if result.ok:result.message="Paid %d actual coins toward this customs debt; no reputation reward was created."%int(result.paid)
		return result
	return c.fail("This customs debt is already settled.")

static func trade(c,id: String,good: String,qty: int,side: String) -> Dictionary:
	var p: Dictionary=c.current_port()
	if p.is_empty() or p.id!=id:return c.fail("Enter this actual harbor before trading.")
	if not allow_player(c,p,good):return c.fail("Your commissioned faction's carrier agreement currently restricts this military commodity here.")
	var permission: Dictionary=Politics.permit(c,"buy_good" if side=="buy" else "trade",good)
	var licensed_buy: bool=false
	if not permission.ok:
		if side!="buy" or good not in ["guns","engines"] or not Law.licensed(c,id,good,qty):return permission
		licensed_buy=true
	var previous: Dictionary=c.state
	c.state=previous.duplicate(true)
	p=c.current_port()
	var overflow: float=maxf(0,c.cargo_weight()-Economy.cargo_weight(c.state.cargo)-c.freight_weight())
	var result: Dictionary=Economy.transact(p,c.state,good,qty,side,maxf(0,c.capacity()-c.freight_weight()-overflow))
	if not result.ok:c.state=previous;return result
	if licensed_buy:
		var bound: Dictionary=Law.consume_license(c,id,good,int(result.qty))
		if not bound.ok:c.state=previous;return bound
	reconcile(c)
	c.Manifest.allocate(c.state)
	c.TradeFlow.observe(c)
	if side=="sell":c.RegionalOps.delivered(c,id,float(result.qty),str(c.state.get("regionalOrigin","")))
	var accepted: Dictionary=c.state
	c.state=previous
	Law.publish(c.state,accepted)
	return result

static func validate(state: Dictionary,world: Dictionary) -> String:
	var errors: Array=Law.validate(state,{"ports":world.PORTS,"factions":world.FACTIONS.map(func(f):return str(f.id)),"goods":Goods.ITEMS})
	return "" if errors.is_empty() else str(errors[0])
