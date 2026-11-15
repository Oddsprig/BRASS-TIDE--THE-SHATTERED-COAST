extends RefCounted
const Crises=preload("res://scripts/regional_crises.gd")
const Transport=preload("res://scripts/passenger_transport.gd")
const Economy=preload("res://scripts/economy.gd")
const Politics=preload("res://scripts/politics.gd")
static func api(c):
	if c.crises==null:
		c.crises=Crises.new()
		c.crises.configure({"wage":100,"berths":Transport.berths,"site_room":Transport.room,"route_days":Transport.route_days,"service":Transport.service,"food_quote":Transport.quote,"atomic":Transport.atomic,"travel_day":Transport.travel,"fleet_account":Transport.account,"witness_authorized115":_witness_authorized115,"witness_reception115":_witness_reception115,"witness_closed115":_witness_closed115})
	return c.crises
static func _witness_authorized115(view,origin: String,destination: String,count: int) -> bool:
	var c=Transport.actual(view)
	if origin!="rust_anchorage" or count!=2 or str(c.current_port().get("id",""))!=origin:return false
	if not c.has_method("campaign_witness_authorized115"):return false
	var p=c.port(destination)
	if not (p is Dictionary) or p.is_empty() or Transport.charter_room(c,p)<count:return false
	return c.call("campaign_witness_authorized115",origin,destination,count)==true
static func _witness_reception115(view,id: String,destination: String,count: int) -> bool:
	var c=Transport.actual(view)
	if not c.has_method("campaign_witness_reception115"):return true
	return c.call("campaign_witness_reception115",id,destination,count)==true
static func _witness_closed115(view,before: Dictionary,destination: String,loss: bool,earned: int) -> void:
	var c=Transport.actual(view)
	if c.has_method("campaign_witness_closed115"):c.call("campaign_witness_closed115",before,destination,loss,earned)
static func housing(definition: Dictionary) -> int:
	# Existing civilian reception places: canonical worker settlement plus
	# one vacant worker place per 200 authored residents. Never adds people.
	return int(Economy.create_port(definition).workforce)+floori(float(definition.population)/200.0)
static func ensure(c) -> void:
	if not c.state.has("passengerTransport"):
		var homes: Dictionary={}
		for definition in c.data.PORTS:homes[str(definition.id)]=housing(definition)
		c.state.passengerTransport={"schema":27,"housing":homes,"carriers":{},"work":{},"foodLost":0.0}
	if not api(c).ensure(c):push_error("Regional crisis records refused; malformed state was preserved.")
static func clean(c) -> void:
	var ids: Array=c.state.regionalCrises.jobs.map(func(j):return str(j.id))
	for key in ["carriers","work"]:
		for id in c.state.passengerTransport[key].keys():
			if id not in ids:c.state.passengerTransport[key].erase(id)
static func result(c,r: Dictionary) -> Dictionary:
	if r.ok:c.Manifest.allocate(c.state);c.ReserveOps.refresh(c)
	clean(c)
	return r
static func begin(c,destination: String,count: int) -> Dictionary:
	ensure(c)
	var p: Dictionary=c.current_port()
	if p.is_empty():return c.fail("Visit the actual sponsoring harbor.")
	return result(c,api(c).begin_resettlement(c,str(p.id),destination,count))
static func witness_quote115(c,destination: String) -> Dictionary:
	ensure(c)
	var origin: String=str(c.current_port().get("id",""))
	if origin!="rust_anchorage":return {}
	var module=api(c)
	if not module.ensure(c) or not module._ready() or not module._dock(c,origin):return {}
	var q: Dictionary=module._quote(c,origin,destination,2,true)
	return q if int(q.get("count",0))==2 else {}
static func begin_witness115(c,destination: String) -> Dictionary:
	ensure(c)
	var origin: String=str(c.current_port().get("id",""))
	if origin!="rust_anchorage":return c.fail("Board the witnesses at Rust Anchorage.")
	return result(c,api(c).begin_resettlement(c,origin,destination,2,true))
static func arrive(c,id: String) -> Dictionary:return result(c,api(c).arrive(c,id))
static func recall(c,id: String) -> Dictionary:return result(c,api(c).recall(c,id))
static func home(c,id: String) -> Dictionary:return result(c,api(c).return_to_origin(c,id))
static func step(c,distance: float) -> void:
	if not is_finite(distance) or distance<=0:return
	for j in c.state.regionalCrises.jobs:
		if j.stage=="holding":continue
		var work: Dictionary=c.state.passengerTransport.work.get(str(j.id),{})
		if work.is_empty():continue
		work.distance=minf(1000000000.0,float(work.distance)+distance)
static func losses(c) -> void:
	var lost: Array=[]
	for j in c.state.regionalCrises.jobs:
		if j.stage=="holding":continue
		var uid: String=str(c.state.passengerTransport.carriers.get(str(j.id),""))
		var boat: Dictionary=c.find_boat(uid)
		if boat.is_empty() or boat.sunk:lost.append(str(j.id))
	for id in lost:
		var r: Dictionary=api(c).lose(c,id)
		if not r.ok:push_error("Passenger loss could not reconcile: "+str(r.message))
	clean(c)
class DayView extends RefCounted:
	var core
	var state: Dictionary
	var data: Dictionary
	func _init(c):core=c;state=c.state.duplicate();state.econDay=int(c.state.econDay)+1;data=c.data
	func current_port() -> Dictionary:return core.current_port()
	func port(id: String) -> Dictionary:return core.port(id)
	func log_entry(message: String):core.log_entry(message)
	func ok(message: String) -> Dictionary:return core.ok(message)
	func fail(message: String) -> Dictionary:return core.fail(message)
static func daily(c) -> void:
	for p in c.state.ports:
		var paid: int=int(p.get("lastPayroll",{}).get("total",0))
		var unpaid: int=int(p.get("defenses",{}).get("arrears",0))
		for business in c.state.get("businesses",[]):
			if business.homePort==p.id:unpaid+=int(business.get("arrearsHousehold",0))+int(business.get("arrearsExpert",0))
		p.lastWagesPaid=paid;p.lastWagesDue=paid+unpaid
	var prior: Dictionary={}
	for j in c.state.regionalCrises.jobs:prior[str(j.id)]=int(j.progress)
	var r: Dictionary=api(c).daily(DayView.new(c))
	if not r.ok:push_error("Regional day refused: "+str(r.message));return
	for j in c.state.regionalCrises.jobs:
		var difference: int=int(j.progress)-int(prior.get(str(j.id),j.progress))
		if difference>0:
			var work: Dictionary=c.state.passengerTransport.work.get(str(j.id),{})
			if not work.is_empty():work.distance=maxf(0,float(work.distance)-float(work.unit)*difference)
	clean(c)
	for p in c.state.ports:Economy.sync_workforce(p)
static func provision(c,id: String,days: int=2) -> Dictionary:
	var permission: Dictionary=Politics.permit(c,"service")
	if not permission.ok:return permission
	var p: Dictionary=c.current_port()
	for j in c.state.regionalCrises.jobs:
		if j.id!=id:continue
		if j.stage=="holding" and j.destination!=p.id:return c.fail("Visit the actual reception harbor.")
		var qty: float=Transport.quantity(int(j.n),days)
		if float(j.food.get("food",0))+qty>float(j.n)*5.0:return c.fail("The cohort already has ample provisions.")
		if j.stage!="holding":
			var b: Dictionary=c.find_boat(str(c.state.passengerTransport.carriers.get(id,"")))
			if b.is_empty() or Transport.available_hold(c,b)<qty:return c.fail("The actual passenger boat lacks hold space.")
		var cost: int=ceili(qty*Economy.price(p,"food","buy"))
		if c.state.coins<cost or c.ReserveOps.Reserves.exportable(p,"food")<qty:return c.fail("Existing food surplus and captain coins are required.")
		c.Money.move(c.state,"coins",p,"cash",cost,"Passenger provisions paid by captain",c.state.moneyLog)
		p.stocks.food-=qty;j.food.food=float(j.food.get("food",0))+qty;c.Manifest.allocate(c.state)
		return c.ok("Bought %.2f actual ration bales for %d coins; the sponsor reward was not increased."%[qty,cost])
	return c.fail("Unknown or completed passenger cohort.")
static func validate(s: Dictionary,world: Dictionary) -> String:
	var module=Crises.new();var errors: Array=module.validate(s,world.PORTS)
	if not errors.is_empty():return str(errors[0])
	if not s.has("passengerTransport"):return "" if not s.has("regionalCrises") else "Missing physical passenger transport record."
	var t=s.passengerTransport
	if not t is Dictionary or t.get("schema")!=27 or t.size()!=5 or not t.get("housing") is Dictionary or not t.get("carriers") is Dictionary or not t.get("work") is Dictionary:return "Invalid passenger transport schema."
	if not (t.get("foodLost") is int or t.get("foodLost") is float) or not is_finite(float(t.foodLost)) or float(t.foodLost)<0:return "Invalid lost provision inventory."
	if t.housing.size()!=world.PORTS.size() or t.carriers.size()>8 or t.work.size()>8:return "Invalid passenger transport limits."
	for definition in world.PORTS:
		if t.housing.get(str(definition.id))!=housing(definition):return "Noncanonical reception capacity."
	var ids: Dictionary={}
	for j in s.get("regionalCrises",{}).get("jobs",[]):
		ids[str(j.id)]=true
		for good in j.food:
			if good!="food":return "Unknown passenger provision."
		if not t.carriers.get(str(j.id)) is String or not t.work.get(str(j.id)) is Dictionary:return "Missing passenger boat or observed work."
		var work: Dictionary=t.work[str(j.id)]
		for key in ["distance","unit"]:
			if not (work.get(key) is int or work.get(key) is float) or not is_finite(float(work[key])) or float(work[key])<0 or float(work[key])>1e9:return "Invalid passenger route evidence."
		if work.unit<=0:return "Passenger route has no actual distance."
		if j.stage!="holding":
			var found: Dictionary={}
			for b in s.fleet:
				if b.uid==t.carriers[str(j.id)]:found=b;break
			if found.is_empty() or found.sunk or not str(found.get("storedPort","")).is_empty():return "Passenger carrier is absent, lost or stored."
	for id in t.carriers:
		if not ids.has(id):return "Stale passenger carrier."
	for id in t.work:
		if not ids.has(id):return "Stale passenger route."
	for b in s.fleet:
		if float(b.crew)+float(s.get("captiveBerths",{}).get(str(b.uid),0))+Transport.assigned(s,str(b.uid))>float(b.crewMax)+floorf(float(b.spec.cargo)) or Transport.assigned(s,str(b.uid))>maxi(0,floori(float(b.crewMax)-float(b.crew))-int(s.get("captiveBerths",{}).get(str(b.uid),0))):return "Passenger and crew berths exceed the actual boat."
	return ""
