extends RefCounted
const MAX_CO = 8
const MAX_BOATS = 96
const MAX_INT = 9007199254740991
const LOG_LIMIT = 32
const FIELDS = ["ownerId","home","destination","good","limits","status",
	"recall","invested","withdrawn","revenue","cogs","operating",
	"basisQty","basisCost","returnedBasis","netProfit","log"]
const LIMITS = ["buyMax","sellMin","maxCargo","reserve","risk"]
var _goods: Dictionary
var _money
var _politics
var _hold: Callable
func _init(goods: Dictionary,money,politics,hold: Callable):
	_goods = goods
	_money = money
	_politics = politics
	_hold = hold
func ensure(c) -> void:
	if not c.state.has("shippingCompanies"):
		c.state.shippingCompanies = {}
func _fail(message: String) -> Dictionary:
	return {"ok":false,"message":message}
func _num(x) -> bool:
	return (typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT) and is_finite(float(x))
func _whole(x) -> bool:
	return _num(x) and x >= 0 and x <= MAX_INT and float(x) == floor(float(x))
func _id(x) -> bool:
	return x is String and not x.is_empty()
func _cargo(c) -> bool:
	if not c is Dictionary or c.size() != _goods.size():
		return false
	for g in _goods:
		if not c.has(g) or not _num(c[g]) or c[g] < 0:
			return false
	return true
func _limits(l) -> bool:
	if not l is Dictionary or l.size() != LIMITS.size():
		return false
	for k in LIMITS:
		if not l.has(k) or not _num(l[k]) or l[k] < 0:
			return false
	return _whole(l.buyMax) and l.buyMax > 0 and _whole(l.sellMin) \
		and _whole(l.reserve) and l.maxCargo > 0 and l.risk <= 1
func _open(books) -> int:
	var n=0
	for b in books.values():
		if b is Dictionary and b.get("status") != "collected":
			n += 1
	return n
func _ids(values) -> Dictionary:
	var out={}
	if values is Dictionary:
		for k in values:
			if _id(k):
				out[k] = true
	elif values is Array:
		for v in values:
			var key=v.get("id","") if v is Dictionary else v
			if _id(key):
				out[key] = true
	return out
func _owners(s) -> Dictionary:
	var out={}
	for o in s.get("fleetOwners",[]):
		if o is Dictionary:
			out[o.get("id","")] = o
	return out
func _patrol(s,id: String) -> Dictionary:
	for p in s.get("patrols",[]):
		if p is Dictionary and p.get("id") == id:
			return p
	return {}
func _boats(s) -> Array:
	var out: Array=s.get("fleet",[]).duplicate()
	for o in s.get("fleetOwners",[]):
		if o is Dictionary and o.get("boats") is Array:
			out.append_array(o.boats)
	return out
func owned_count(state) -> int:
	var n: int=state.get("fleet",[]).size()
	for o in state.get("fleetOwners",[]):
		if o is Dictionary and o.get("playerCompany",false):
			n += o.get("boats",[]).size()
	return n
func _error(c) -> String:
	var world: Variant=c.get("data")
	var hulls: Variant=world.get("HULLS",[]) if world is Dictionary else c.get("boats")
	return validate(c.state,{"ports":c.state.get("ports",[]),"hulls":hulls})

func _capacity(c,b) -> float:
	var n=_hold.call(c,b)
	return float(n) if _num(n) and n >= 0 else -1.0
func _travel(b) -> bool:
	return not b.sunk and not b.get("mothballed",false) and b.get("storedPort","") == "" \
		and b.hp > 0 and b.crew >= b.crewMin
func _busy(s,uid: String) -> bool:
	var records=s.get("specialists",[])
	if not records is Array:
		return true
	for r in records:
		if not r is Dictionary:
			return true
		if r.get("boatUid") == uid:
			return true
	return false

func _docked(c,o,port_id: String) -> bool:
	var p=_patrol(c.state,o.id)
	var port=c.port(port_id)
	if p.is_empty() or not port is Dictionary or o.atPort != port_id \
			or not p.get("holding",false):
		return false
	for k in ["x","y"]:
		if not _num(port.get(k)) or not _num(p.get(k)):
			return false
	if Vector2(p.x,p.y).distance_to(Vector2(port.x,port.y)) > 1.0:
		return false
	for b in o.boats:
		if not b.sunk and b.storedPort not in ["",port_id]:
			return false
	return true
func _move(src,key: String,dst,amount: int,ledger: Array) -> bool:
	if amount == 0:
		return true
	var a=int(src[key])
	var b=int(dst[key])
	_money.move(src,key,dst,key,amount,"Company",ledger)
	return src[key] == a - amount and dst[key] == b + amount
func _pair(c,src,dst,cash: int,crew: int) -> bool:
	for row in [["coins",cash],["crewPurse",crew]]:
		if not _whole(row[1]) or src[row[0]] < row[1] \
				or not _whole(dst[row[0]] + row[1]):
			return false
	var ledger: Array=[]
	if not _move(src,"coins",dst,cash,ledger):
		return false
	if not _move(src,"crewPurse",dst,crew,ledger):
		_move(dst,"coins",src,cash,[])
		return false
	c.state.moneyLog.append_array(ledger)
	return true
func create(c,boat_uids: Array,destination: String,good: String,
		amount: int,limits: Dictionary = {}) -> Dictionary:
	var error=_error(c)
	if error != "":
		return _fail(error)
	var s: Dictionary=c.state
	var books: Dictionary=s.get("shippingCompanies",{})
	if books.size()>=128:return _fail("The company register holds 128 retained charters. Existing routes continue and all records are preserved.")
	if _open(books) >= MAX_CO or boat_uids.is_empty() or amount <= 0 \
			or amount > s.coins or not _goods.has(good) or not _limits(limits):
		return _fail("Cannot create company.")
	var home=c.current_port()
	var dest=c.port(destination)
	if not home is Dictionary or not _id(home.get("id")) \
			or not dest is Dictionary or dest.get("id") != destination or home.id == destination \
			or not _ids(s.ports).has(home.id) or not _num(home.get("x")) or not _num(home.get("y")):
		return _fail("Invalid harbor route.")
	var permit=_politics.permit(c,"service")
	if not (permit.get("ok",false) if permit is Dictionary else (permit is bool and permit)):
		return _fail("Service access denied.")
	var chosen: Array=[]
	var seen={}
	var taken=0
	var crews=0
	var flag=""
	for uid in boat_uids:
		if not _id(uid) or seen.has(uid):
			return _fail("Invalid boat UID.")
		seen[uid] = true
	for b in s.fleet:
		crews += int(b.crew)
		if seen.has(b.uid):
			var shore=b.get("shoreCrew",0)
			if not _whole(shore) or shore > 0:
				return _fail("Hull has reserved shore crew.")
			if b.sunk or b.mothballed or b.get("needsHarborRepair",false) or b.hp <= 0 or b.crew < b.crewMin \
					or b.storedPort not in ["",home.id] or _busy(s,b.uid) \
					or _capacity(c,b) <= 0:
				return _fail("Hull unavailable.")
			chosen.append(b)
			taken += int(b.crew)
		elif _travel(b) and flag == "":
			flag = b.uid
	if chosen.size() != boat_uids.size() or flag == "":
		return _fail("Keep a seaworthy flagship.")
	var serial=int(s.nextUid)
	var owner_map=_owners(s)
	var id="company_%d" % serial
	while owner_map.has(id) or not _patrol(s,id).is_empty():
		serial += 1
		id = "company_%d" % serial
	if serial >= MAX_INT:
		return _fail("UID exhausted.")
	var cargo={}
	for g in _goods:
		cargo[g] = 0.0
	var o={"id":id,"name":"Shipping company %d" % serial,
		"homePort":home.id,"faction":home.get("faction",""),
		"kind":"trader","playerCompany":true,"coins":0,"crewPurse":0,
		"wageArrears":0,"morale":85,"cargo":cargo,"boats":[],
		"route":[home.id,destination],"progress":0.0,"atPort":home.id,
		"active":true,"log":[],"tradeGood":good,"tradeCargo":0.0,
		"wageRemainder":0.0,"daysOperated":0.0,"performanceFactor":1.0,
		"lastPayroll":0,"lastFoodConsumed":0.0,"lastFuelConsumed":0.0}
	var p={"id":id,"name":o.name,"hostile":false,"active":true,
		"from":home.id,"to":destination,"x":home.x,"y":home.y,
		"progress":0.0,"holding":true,"strength":chosen.size(),
		"course":[],"courseLength":0.0,"voyageSeq":0}
	var share=int(floor(float(s.crewPurse) * float(taken) / float(maxi(1,crews))))
	if not _pair(c,s,o,amount,share):
		return _fail("Funding failed.")
	var retained: Array=[]
	for b in s.fleet:
		if seen.has(b.uid):
			b.storedPort = ""
			o.boats.append(b)
		else:
			retained.append(b)
	s.fleet = retained
	if seen.has(s.flagship):
		s.flagship = flag
	s.nextUid = serial + 1
	s.fleetOwners.append(o)
	s.patrols.append(p)
	ensure(c)
	s.shippingCompanies[id] = {"ownerId":id,"home":home.id,
		"destination":destination,"good":good,"limits":limits.duplicate(true),
		"status":"active","recall":false,"invested":amount,"withdrawn":0,
		"revenue":0,"cogs":0,"operating":0,"basisQty":0.0,
		"basisCost":0,"returnedBasis":0,"netProfit":0,"log":[]}
	return {"ok":true,"id":id}

func list(c) -> Array:
	var out: Array=[]
	for book in c.state.get("shippingCompanies",{}).values():
		out.append(book.duplicate(true))
	return out
func recall(c,id) -> Dictionary:
	var error=_error(c)
	if error != "":
		return _fail(error)
	var b=c.state.get("shippingCompanies",{}).get(id,{})
	if b.is_empty() or b.status == "collected":
		return _fail("No open company.")
	b.recall = true
	b.status = "returning"
	return {"ok":true,"id":id}
func capital(c,id,amount: int) -> Dictionary:
	var error=_error(c)
	if error != "":
		return _fail(error)
	var b=c.state.get("shippingCompanies",{}).get(id,{})
	if b.is_empty() or b.status == "collected" or amount <= 0 \
			or not _whole(b.invested + amount):
		return _fail("Invalid capital request.")
	var o=_owners(c.state)[id]
	if not _pair(c,c.state,o,amount,0):
		return _fail("Insufficient capital.")
	b.invested += amount
	return {"ok":true,"id":id}
func next_port(c,o) -> String:
	var b=c.state.get("shippingCompanies",{}).get(o.get("id",""),{})
	if b.is_empty() or b.status == "collected" or not o.get("active",false):
		return ""
	if b.recall:
		return "" if _docked(c,o,b.home) else b.home
	if o.atPort == b.home:
		return b.destination
	if o.atPort == b.destination:
		return b.home
	var p=_patrol(c.state,o.id)
	return p.get("to",b.home) if p.get("to","") in [b.home,b.destination] else b.home

func trade_limit(c,o,buying: bool,good: String,price: float) -> float:
	var b=c.state.get("shippingCompanies",{}).get(o.get("id",""),{})
	if b.is_empty() or b.status == "collected" or good != b.good \
			or not is_finite(price) or price <= 0:
		return 0.0
	var port_id=b.home if buying or b.recall else b.destination
	if not _docked(c,o,port_id):
		return 0.0
	if not buying:
		return minf(o.cargo[good],b.basisQty) if price >= b.limits.sellMin else 0.0
	if b.recall or price > b.limits.buyMax:
		return 0.0
	var space=0.0
	for boat in o.boats:
		if not boat.sunk:
			var hold_size=_capacity(c,boat)
			if hold_size < 0:
				return 0.0
			space += hold_size
	for g in _goods:
		space -= float(o.cargo[g]) * float(_goods[g].weight)
	var weight=float(_goods[good].weight)
	if weight <= 0:
		return 0.0
	return maxf(0.0,minf(b.limits.maxCargo - b.basisQty,
		minf(space / weight,maxf(0.0,o.coins - b.limits.reserve) / price)))
func collect(c,id) -> Dictionary:
	var error=_error(c)
	if error != "":
		return _fail(error)
	var s: Dictionary=c.state
	var b=s.get("shippingCompanies",{}).get(id,{})
	if b.is_empty() or b.status == "collected" or not b.recall:
		return _fail("Recall the company first.")
	var o=_owners(s)[id]
	if o.wageArrears > 0:
		return _fail("Settle wage arrears first.")
	var port=c.current_port()
	if not port is Dictionary or port.get("id") != b.home or not _docked(c,o,b.home):
		return _fail("Both fleets need home dock.")
	if s.fleet.size() + o.boats.size() > MAX_BOATS:
		return _fail("No roster space.")
	var free_hold=float(c.capacity()) - float(c.cargo_weight())
	for boat in o.boats:
		if not boat.sunk:
			var hold_size=_capacity(c,boat)
			if hold_size < 0:
				return _fail("Unknown hold capacity.")
			free_hold += hold_size
	var weight=0.0
	for g in _goods:
		weight += float(o.cargo[g]) * float(_goods[g].weight)
	if not is_finite(free_hold) or weight > free_hold:
		return _fail("Cargo hold full.")
	var cash=int(o.coins)
	if not _whole(b.withdrawn + cash) or not _pair(c,o,s,cash,int(o.crewPurse)):
		return _fail("Purse transfer failed.")
	for boat in o.boats:
		if not boat.sunk:
			boat.storedPort = ""
		s.fleet.append(boat)
	o.boats.clear()
	for g in _goods:
		s.cargo[g] += o.cargo[g]
		o.cargo[g] = 0.0
	b.withdrawn += cash
	b.returnedBasis += b.basisCost
	b.basisQty = 0.0
	b.basisCost = 0
	o.tradeCargo = 0.0
	o.active = false
	var p=_patrol(s,id)
	p.active = false
	p.strength = 0
	b.status = "collected"
	return {"ok":true,"id":id,"netProfit":b.netProfit}
func record(c,o,event: String,coins: int,good: String = "",qty: float = 0) -> void:
	var b=c.state.get("shippingCompanies",{}).get(o.get("id",""),{})
	if not is_same(_owners(c.state).get(o.get("id","")),o):
		return
	if b.is_empty() or b.status == "collected" or not _whole(coins) \
			or not is_finite(qty) or qty < 0:
		return
	if event in ["purchase","sale","loss"]:
		if good != b.good or qty <= 0:
			return
		var expected=b.basisQty + qty if event == "purchase" else b.basisQty - qty
		if not _num(expected) or float(o.cargo.get(good,0))+0.000001 < float(expected):
			return
		if event == "purchase":
			b.basisQty += qty
			b.basisCost += coins
		else:
			if qty > b.basisQty or (event == "loss" and coins != 0):
				return
			var cost=int(b.basisCost) if qty == b.basisQty \
				else int(floor(float(b.basisCost) * qty / float(b.basisQty)))
			b.basisQty -= qty
			b.basisCost -= cost
			if event == "sale":
				b.revenue += coins
				b.cogs += cost
			else:
				b.operating += cost
	elif event in ["wages","fuel","repairs","fees","stores","capital_loss"]:
		b.operating += coins
	else:
		return
	b.netProfit = int(b.revenue) - int(b.cogs) - int(b.operating)
	b.log.append({"day":c.state.day,"event":event,"coins":coins,"good":good,"qty":qty})
	while b.log.size() > LOG_LIMIT:
		b.log.pop_front()
func daily(c) -> void:
	if _error(c) != "":
		return
	ensure(c)
	var owners=_owners(c.state)
	for b in c.state.shippingCompanies.values():
		if b.status == "collected":
			continue
		var o=owners[b.ownerId]
		b.status = ("ready" if _docked(c,o,b.home) else "returning") if b.recall \
			else ("waiting" if o.coins == 0 or not o.active else "active")
func validate(state: Dictionary,world: Dictionary) -> String:
	for k in ["fleet","fleetOwners","patrols","ports","moneyLog"]:
		if not state.get(k) is Array:
			return k
	for k in ["coins","crewPurse","nextUid"]:
		if not _whole(state.get(k)):
			return "player purse/UID."
	if not _cargo(state.get("cargo")) or not _num(state.get("day")):
		return "source cargo/day."
	var books=state.get("shippingCompanies",{})
	if not books is Dictionary or _open(books) > MAX_CO:
		return "Malformed company book."
	var ports=_ids(world.get("ports",[]))
	var hulls=_ids(world.get("hulls",[]))
	var owners={}
	var patrols={}
	for pair in [["fleetOwners",owners],["patrols",patrols]]:
		for row in state[pair[0]]:
			if not row is Dictionary or not _id(row.get("id")) or pair[1].has(row.id):
				return "owner/patrol ID."
			pair[1][row.id] = row
	var seen={}
	for o in state.fleetOwners:
		if not o.get("boats") is Array:
			return "Missing boat roster."
		if o.get("playerCompany",false) and not books.has(o.id):
			return "Unbooked company."
	for boat in _boats(state):
		if not boat is Dictionary or not _id(boat.get("uid")) or seen.has(boat.uid) \
				or not hulls.has(boat.get("type")):
			return "boat UID/type."
		seen[boat.uid] = true
		for k in ["crewMin","crewMax"]:
			if not _whole(boat.get(k)):
				return "boat crew."
		for k in ["crew","hp","maxHp","fuel","ammo","supplies"]:
			if not _num(boat.get(k)) or boat[k] < 0:
				return "stores/condition."
		if boat.crew > boat.crewMax or boat.crewMin > boat.crewMax or boat.maxHp <= 0 or boat.hp > boat.maxHp \
				or not boat.get("sunk") is bool or not boat.get("mothballed",false) is bool \
				or not boat.get("storedPort","") is String \
				or (boat.get("storedPort","") != "" and not ports.has(boat.storedPort)):
			return "boat state/location."
	var player_ids={}
	for boat in state.fleet:
		player_ids[boat.uid] = true
	if not player_ids.has(state.get("flagship")) or owned_count(state) > MAX_BOATS:
		return "flagship/roster."
	for id in books:
		var b=books[id]
		if not _id(id) or not b is Dictionary or b.size() != FIELDS.size():
			return "company book."
		for k in FIELDS:
			if not b.has(k):
				return "book keys."
		for k in ["ownerId","home","destination","good"]:
			if not _id(b[k]):
				return "Company IDs."
		if b.ownerId != id or not owners.has(id) or not patrols.has(id) \
				or not ports.has(b.home) or not ports.has(b.destination) or b.home == b.destination \
				or not _goods.has(b.good) or not _limits(b.limits):
			return "references/limits."
		if b.status not in ["active","waiting","returning","ready","collected"] \
				or not b.recall is bool or not b.log is Array or b.log.size() > LOG_LIMIT:
			return "status/log."
		for k in ["invested","withdrawn","revenue","cogs","operating","basisCost","returnedBasis"]:
			if not _whole(b[k]):
				return "company account."
		if not _num(b.basisQty) or b.basisQty < 0 or not _num(b.netProfit) \
				or b.netProfit != b.revenue - b.cogs - b.operating \
				or (b.basisQty == 0 and b.basisCost != 0):
			return "accounts/basis."
		for entry in b.log:
			if not entry is Dictionary or entry.size() != 5 or not _num(entry.get("day")) \
					or not entry.get("event") is String or not _whole(entry.get("coins")) \
					or not entry.get("good") is String or not _num(entry.get("qty")) or entry.qty < 0 \
					or (entry.good != "" and not _goods.has(entry.good)):
				return "company log."
		var o=owners[id]
		var p=patrols[id]
		if o.get("playerCompany") != true or o.get("kind") != "trader" or o.get("homePort") != b.home \
				or o.get("route") != [b.home,b.destination] or o.get("tradeGood") != b.good \
				or not _whole(o.get("coins")) or not _whole(o.get("crewPurse")) \
				or not _whole(o.get("wageArrears")) \
				or not _cargo(o.get("cargo")) or float(o.cargo[b.good])+0.000001 < float(b.basisQty) \
				or not o.get("active") is bool or not o.get("atPort") is String \
				or (o.atPort != "" and not ports.has(o.atPort)):
			return "company owner."
		if not p.get("active") is bool or p.get("hostile") != false \
				or not p.get("holding") is bool or not _num(p.get("x")) or not _num(p.get("y")) \
				or not ports.has(p.get("from")) or not ports.has(p.get("to")):
			return "company patrol."
		for boat in o.boats:
			if _busy(state,boat.uid):
				return "Assigned shore people."
		if b.status == "collected":
			if not o.boats.is_empty() or o.coins != 0 or o.crewPurse != 0 or o.active or p.active:
				return "Owner not empty."
			for g in _goods:
				if o.cargo[g] != 0:
					return "Cargo not empty."
	return ""
