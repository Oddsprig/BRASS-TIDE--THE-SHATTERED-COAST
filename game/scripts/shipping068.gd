extends RefCounted
## One scheduled physical trader. No clock, inventory, payroll or ocean memory.
const World = preload("res://scripts/ocean_world064.gd")
const Travel = preload("res://scripts/ocean_travel066.gd")
const Economy = preload("res://scripts/economy.gd")
const Goods = preload("res://scripts/goods.gd")
const Harbor = preload("res://scripts/harbor_reserves.gd")
const Fleets = preload("res://scripts/fleet_economy.gd")
const OWNER: String = "patrol-7"
const ORIGIN: String = "kelp_reach"
const REMOTE_PORT: String = "westglass_anchorage"
const BERTH: Dictionary = {"x":756.0,"y":732.0}
const PHASES: Array = ["home_service","outbound","remote_service","return","lost"]
const PHASES075: Array = ["yard_service","to_origin","outbound","to_yard","yard_arrival","lost"]
const DAY_SECONDS: float = 45.0
const SERVICE_SECONDS: float = 11.25
const EPS: float = 0.000001


static func empty_book() -> Dictionary:
	return {"schema":1,"route":{}}


## A quotation, never a purchase or a stock reservation. Requote at the real
## loading berth: both the buyer's demand and the merchant's purse can change.
static func cargo_offer075(owner: Dictionary, origin: Dictionary, destination: Dictionary, reserveCoins: int, exportRows: Dictionary = {}) -> Dictionary:
	if origin.is_empty() or destination.is_empty() or origin.get("id")==destination.get("id") or reserveCoins<0:return _fail("A shipment needs two actual markets and a nonnegative voyage reserve.")
	if int(owner.get("coins",0))<reserveCoins:return _fail("The actual merchant purse cannot cover voyage and home-yard recovery reserves.")
	return _cargo_offer075(owner,origin,destination,reserveCoins,_market_quote075(owner,origin,exportRows),_market_quote075(owner,destination))


## Detached, short-lived prices/demand for one admission attempt, never a stock
## reservation. The physical loading berth still obtains a fresh quotation.
static func _market_quote075(owner: Dictionary, port: Dictionary, exportRows: Dictionary = {}) -> Dictionary:
	var exports: Dictionary = Harbor.report(port).goods if exportRows.is_empty() else exportRows
	var rows: Dictionary = {}
	for key in Goods.ITEMS:
		var good: String = str(key)
		rows[good]={"allowed":Fleets.allowed_trade(owner,port,good),"buy":maxi(1,Economy.price(port,good,"buy")),"sell":maxi(1,Economy.price(port,good,"sell")),"demand":maxi(0,floori(Economy.get_equilibrium_stock(port,good)-float(port.get("stocks",{}).get(good,0.0)))),"exportable":floori(float(exports.get(good,{}).get("exportable",0.0)))}
	return rows


static func _cargo_offer075(owner: Dictionary, origin: Dictionary, destination: Dictionary, reserveCoins: int, originRows: Dictionary, destinationRows: Dictionary) -> Dictionary:
	if origin.is_empty() or destination.is_empty() or origin.get("id")==destination.get("id") or reserveCoins<0:return _fail("A shipment needs two actual markets and a nonnegative voyage reserve.")
	if int(owner.get("coins",0))<reserveCoins:return _fail("The actual merchant purse cannot cover voyage and home-yard recovery reserves.")
	var held: float = maxf(0.0,float(owner.get("tradeCargo",0.0)))
	var capacity: float = maxf(0.0,Fleets._capacity(owner)-Economy.cargo_weight(owner.get("cargo",{})))
	var best: Dictionary = {}
	var best_value: float = -INF
	for key in Goods.ITEMS:
		var good: String = str(key)
		if held>EPS and good!=str(owner.get("tradeGood","")):continue
		if not originRows[good].allowed or not destinationRows[good].allowed:continue
		var buy: int = int(originRows[good].buy)
		var sell: int = int(destinationRows[good].sell)
		var demand: int = int(destinationRows[good].demand)
		var qty: int = mini(64,mini(demand,maxi(0,int(destination.get("cash",0)))/sell))
		if held>EPS:
			qty=mini(qty,floori(minf(held,float(owner.get("cargo",{}).get(good,0.0)))))
		else:
			if sell<=buy:continue
			qty=mini(qty,mini(maxi(0,int(owner.get("coins",0))-reserveCoins)/buy,mini(int(originRows[good].exportable),floori(capacity/float(Goods.ITEMS[good].weight)))))
		if qty<1:continue
		var cost: int = 0 if held>EPS else qty*buy
		var value: float = float(qty*sell-cost)
		if value<=best_value:continue
		best_value=value
		best={"ok":true,"good":good,"qty":qty,"buyCoins":cost,"sellCoins":qty*sell,"margin":qty*sell-cost,"retained":held>EPS,"reason":"Funded %.0f %s from %s to %s: %d coins purchase, at most %d coins sale into actual demand; %d coins retained for voyage and recovery."%[float(qty),good,str(origin.get("name",origin.id)),str(destination.get("name",destination.id)),cost,qty*sell,reserveCoins]}
	return best if not best.is_empty() else _fail("No affordable exportable lot meets actual destination demand and available coins after voyage reserves.")


## One bounded candidate, using existing owners/markets only. The caller owns
## enrollment and scheduled execution; selection creates no account or cargo.
static func select_corridor075(state: Dictionary, context: Dictionary, owner: Dictionary, reserveCoins: int = 0, campaignScale: float = 4.0) -> Dictionary:
	if not state.has("sector069") or context.get("harbors",{}).is_empty():return _fail("Legacy two-region career retains its existing shipping route.")
	if owner.get("kind")!="trader" or owner.get("playerCompany",false) or str(owner.get("id","")).begins_with("story-") or not owner.get("active",false):return _fail("A corridor needs an existing active independent merchant.")
	var home: Dictionary = {}
	var ports: Array = []
	for port in state.get("ports",[]):
		if port.get("id")==owner.get("homePort"):home=port
		if not context.harbors.has(port.get("id")):continue
		if owner.get("faction")!=port.get("faction") and Fleets.Factions068.relation(state,str(owner.get("faction","")),str(port.get("faction","")))<=-20:continue
		ports.append(port)
	if home.is_empty() or str(home.get("regionId",World.HOME))!=World.HOME or not _number(campaignScale,EPS):return _fail("The merchant needs its existing paid home yard and finite campaign scale.")
	var clearance: float = 10.0
	var speed: float = INF
	var count: int = 0
	for boat in owner.get("boats",[]):
		if boat.get("sunk",false):continue
		count+=1;clearance=maxf(clearance,float(boat.get("spec",{}).get("size",10.0)))
		var condition: Dictionary = Fleets.Damage.get_status(boat)
		speed=minf(speed,float(boat.get("spec",{}).get("speed",0.0))*float(condition.get("speedFactor",0.0)))
	if count<1 or not _number(speed,EPS):return _fail("The merchant has no actual powered carrier.")
	speed*=0.38*campaignScale
	var upkeep: Dictionary = Fleets.upkeep(owner)
	var home_prices: Dictionary = {"food":Economy.price(home,"food","buy"),"fuel":Economy.price(home,"fuel","buy")}
	var views: Dictionary = {}
	var homes: Array = _port_gates075(context,home,clearance,views,true)
	var markets: Dictionary = {}
	var bounds: Dictionary = {}
	for port in ports:
		markets[port.id]=_market_quote075(owner,port)
		bounds[port.id]=_port_gates075(context,port,clearance,views,true)
	var candidates: Array = []
	for origin in ports:
		for remote in ports:
			if origin.regionId==remote.regionId:continue
			# Straight local distances and the ocean's fastest allowed speed are
			# optimistic screening only. No forecasts or navigation grids here;
			# the three real quotes must fund slowest-weather time and recovery.
			var lower: Dictionary = _route_quote_gates075(context,home,origin,remote,speed,homes,bounds[origin.id],bounds[remote.id],views,true)
			if not lower.get("ok",false):continue
			var reserve: Dictionary = _voyage_reserve075(owner,home_prices,float(lower.days),upkeep,count,reserveCoins)
			var offer: Dictionary = _cargo_offer075(owner,origin,remote,int(reserve.reserveCoins),markets[origin.id],markets[remote.id])
			if not offer.get("ok",false):continue
			candidates.append({"origin":origin,"remote":remote,"score":float(offer.margin)/(1.0+float(lower.days))})
	candidates.sort_custom(func(a,b):return float(a.score)>float(b.score))
	# Only three promising pairs receive real path quotations, once at admission.
	# Navigation views are detached; never evict the player's active local grid.
	for candidate in candidates.slice(0,3):
		var quote: Dictionary = route_quote075(context,home,candidate.origin,candidate.remote,clearance,speed,views)
		if not quote.get("ok",false):continue
		var reserve: Dictionary = _voyage_reserve075(owner,home_prices,float(quote.days),upkeep,count,reserveCoins)
		var offer: Dictionary = _cargo_offer075(owner,candidate.origin,candidate.remote,int(reserve.reserveCoins),markets[candidate.origin.id],markets[candidate.remote.id])
		if not offer.get("ok",false):continue
		quote.merge(offer,true)
		quote.merge(reserve,true)
		quote.merge({"ownerId":str(owner.id),"homeId":str(home.id),"originId":str(candidate.origin.id),"remoteId":str(candidate.remote.id)},true)
		return quote
	return _fail("No generated corridor has a navigable funded lot plus actual voyage and home-yard recovery reserves.")


static func _voyage_reserve075(owner: Dictionary, homePrices: Dictionary, days: float, upkeep: Dictionary, count: int, reserveCoins: int) -> Dictionary:
	var wages: int = ceili(float(upkeep.wages)*days)+maxi(0,int(owner.get("wageArrears",0)))
	var food: int = ceili(float(upkeep.food)*days)
	var fuel: int = ceili(float(upkeep.fuel)*days)
	var repair: int = count*Economy.ORDINARY_WAGE
	var held_food: float = maxf(0.0,float(owner.get("cargo",{}).get("food",0.0))-(float(owner.get("tradeCargo",0.0)) if owner.get("tradeGood")=="food" else 0.0))
	var held_fuel: float = maxf(0.0,float(owner.get("cargo",{}).get("fuel",0.0))-(float(owner.get("tradeCargo",0.0)) if owner.get("tradeGood")=="fuel" else 0.0))
	for boat in owner.boats:
		if not boat.get("sunk",false):held_fuel+=float(boat.get("fuel",0.0))
	var provisioning: int = maxi(0,ceili(float(food)-held_food))*int(homePrices.food)+maxi(0,ceili(float(fuel)-held_fuel))*int(homePrices.fuel)
	return {"wageCoins":wages,"repairCoins":repair,"food":food,"fuel":fuel,"reserveCoins":maxi(reserveCoins,wages+repair+provisioning)}


static func route_quote075(context: Dictionary, home: Dictionary, origin: Dictionary, remote: Dictionary, clearance: float, speed: float, views: Dictionary = {}) -> Dictionary:
	if not _number(speed,EPS) or not _number(clearance,0.0):return _fail("A corridor quote needs finite actual speed and clearance.")
	if not views.has("forecastContext075"):
		# Only conservativeSeconds is used: both authored weather phases are
		# minimized along each directed leg, independent of seed or phase time.
		var prepared: Dictionary = Travel.create(context,0,null,["player"],0.0)
		if not prepared.get("ok",false):return _fail(str(prepared.message))
		views["forecastContext075"]=prepared.context
	var homes: Array = _port_gates075(context,home,clearance,views)
	var origins: Array = _port_gates075(context,origin,clearance,views)
	var remotes: Array = _port_gates075(context,remote,clearance,views)
	return _route_quote_gates075(context,home,origin,remote,speed,homes,origins,remotes,views)


static func _route_quote_gates075(context: Dictionary, home: Dictionary, origin: Dictionary, remote: Dictionary, speed: float, homes: Array, origins: Array, remotes: Array, views: Dictionary = {}, lowerBound: bool = false) -> Dictionary:
	var best: Dictionary = {}
	var seconds: float = INF
	for h in homes:
		for a in origins:
			for b in remotes:
				var ocean: float
				if lowerBound:
					ocean=(World._distance(h.ocean,a.ocean)+World._distance(a.ocean,b.ocean)+World._distance(b.ocean,h.ocean))*float(context.ocean.localUnitsPerUnit)/(1.5*speed)
				else:
					ocean=_ocean_seconds075(h.ocean,a.ocean,speed,views)+_ocean_seconds075(a.ocean,b.ocean,speed,views)+_ocean_seconds075(b.ocean,h.ocean,speed,views)
				var actual: float = 2.0*(float(h.length)+float(a.length)+float(b.length))/speed+ocean
				if not is_finite(actual) or actual>=seconds:continue
				seconds=actual
				best={"ok":true,"days":actual/DAY_SECONDS+1.0,"homeGate":{"regionId":str(home.get("regionId",World.HOME)),"approachId":str(h.id)},"originGate":{"regionId":str(origin.regionId),"approachId":str(a.id)},"remoteGate":{"regionId":str(remote.regionId),"approachId":str(b.id)}}
	return best if not best.is_empty() else _fail("No real safe harbor-to-approach route connects this generated pair and its home yard.")


static func _ocean_seconds075(start: Dictionary, finish: Dictionary, speed: float, views: Dictionary) -> float:
	var key: String = "ocean075:"+JSON.stringify([start,finish,speed])
	if views.has(key):return float(views[key])
	if not views.has("forecastContext075"):return INF
	var distance: float = World._distance(start,finish)*Travel.SCALE
	var leg: Dictionary = {"kind":"sail","layer":"ocean","from":start,"to":finish,"path":[finish],"physicalDistance":distance,"seconds":distance/speed}
	var forecast: Dictionary = Travel.forecast(views.forecastContext075,[leg],speed,0.0)
	# A refused whole-leg bound cannot admit a route. Cache both directions
	# separately: an adverse current must not reuse the following-leg time.
	var seconds: float = float(forecast.conservativeSeconds) if forecast.get("ok",false) else INF
	views[key]=seconds
	return seconds


static func _port_gates075(context: Dictionary, port: Dictionary, clearance: float, views: Dictionary, lowerBound: bool = false) -> Array:
	var region_id: String = str(port.get("regionId",World.HOME))
	if not context.get("regions",{}).has(region_id):return []
	var region: Dictionary = context.regions[region_id]
	var cache_key: String = "gates075:%s:%.6f"%[str(port.id),clearance]
	if not lowerBound and views.has(cache_key):return views[cache_key]
	var geometry: Dictionary = context.regionGeometry[region_id]
	var start: Dictionary = _point(port)
	if region_id==World.HOME:
		start=World.Navigation.harbor_approach(context.homeNav,port,clearance)
		if start.is_empty():return []
	var location: Dictionary = _location("home" if region_id==World.HOME else "local",region_id,start)
	var choices: Array = []
	for gate in region.approaches:
		if not World._approach_safe(context,region,gate,clearance) or not World.Navigation.is_water(geometry,start.x,start.y,clearance):continue
		var length: float = World._distance(start,gate.position)
		if not lowerBound and not World.Navigation.path_clear(geometry,start,[gate.position],clearance):
			# Only an obstructed real quote needs a detached navigation grid.
			if not views.has(region_id):views[region_id]=_view075(context,region_id)
			var destination: String = "" if region_id==World.HOME else "approach:%s:%s"%[region_id,str(gate.id)]
			var plotted: Dictionary = World.plot(views[region_id],location,gate.position,destination,clearance)
			if not plotted.get("ok",false):continue
			length=_length(start,plotted.location.path)
		choices.append({"id":str(gate.id),"length":length,"ocean":World._project(context,region,gate.position)})
	if not lowerBound:views[cache_key]=choices
	return choices


static func corridor_record075(quote: Dictionary) -> Dictionary:
	var record: Dictionary = {}
	for key in ["ownerId","homeId","originId","remoteId","homeGate","originGate","remoteGate"]:
		if not quote.has(key):return {}
		record[key]=quote[key].duplicate(true) if quote[key] is Dictionary else quote[key]
	return record


static func admit075(context: Dictionary, snapshot: Dictionary, now: float, sequence: int = 0) -> Dictionary:
	var error: String = _snapshot_error(snapshot)
	if not error.is_empty():return _fail(error)
	var owner: Dictionary = snapshot.owner
	var yard: Dictionary = snapshot.yardPort
	var location: Dictionary = _location("home",World.HOME,_point(snapshot.patrol))
	if not owner.active or owner.get("atPort")!=yard.id or not snapshot.patrol.get("holding",false) or not _at_berth(location,yard):return _fail("Generated shipping must enroll at its merchant's actual stopped home berth.")
	if not _number(owner.get("harborServiceUntilDay"),1.0):return _fail("Generated shipping awaits a real paid home service visit.")
	var physical: Dictionary = World.prepare(location,context,float(snapshot.clearance))
	if not physical.get("ok",false):return _fail(str(physical.get("message","The actual home berth is unsafe at this fleet's clearance.")))
	var route: Dictionary = {"ownerId":str(owner.id),"phase":"yard_service","location":location,"nextDueSecond":maxf(now,float(owner.harborServiceUntilDay)*DAY_SECONDS),"sequence":sequence,"corridor075":corridor_record075(snapshot.corridor075)}
	error=_route_error(context,route,now)
	return _result({"schema":1,"route":route},{},"Funded generated corridor admitted at the original paid home berth.") if error.is_empty() else _fail(error)


static func _requirements075(context: Dictionary, snapshot: Dictionary) -> Dictionary:
	var speed: float = float(snapshot.performance.get("speed",0.0))*0.38*float(snapshot.campaignScale)
	var quote: Dictionary = route_quote075(context,snapshot.yardPort,snapshot.originPort,snapshot.remotePort,float(snapshot.clearance),speed)
	if not quote.get("ok",false):return quote
	var costs: Dictionary = Fleets.upkeep(snapshot.owner)
	var days: float = float(quote.days)
	return {"ok":true,"days":days,"wageCoins":ceili(float(costs.wages)*days)+int(snapshot.owner.get("wageArrears",0)),"food":ceilf(float(costs.food)*days),"fuel":ceilf(float(costs.fuel)*days),"repairCoins":ceili(float(snapshot.reserves.boats)*Economy.ORDINARY_WAGE),"message":"Actual home-to-generated-pair-to-home reserve; no remittance or guaranteed profit."}


static func _command075(route: Dictionary, kind: String, port: Dictionary, good: String, qty: int) -> Dictionary:
	route["sequence"]=int(route.sequence)+1
	return {"kind":kind,"ownerId":str(route.ownerId),"portId":str(port.id),"good":good,"qty":qty,"sequence":int(route.sequence)}


static func _delivery075(owner: Dictionary, port: Dictionary) -> int:
	var good: String = str(owner.tradeGood)
	if not Fleets.allowed_trade(owner,port,good):return 0
	var carried: int = floori(minf(float(owner.tradeCargo),float(owner.cargo.get(good,0.0))))
	var affordable: int = int(port.get("cash",0))/maxi(1,Economy.price(port,good,"sell"))
	var demand: int = floori(maxf(0.0,Economy.get_equilibrium_stock(port,good)-float(port.get("stocks",{}).get(good,0.0))))
	return maxi(0,mini(64,mini(carried,mini(affordable,demand))))


static func _plan075(context: Dictionary, book: Dictionary, snapshot: Dictionary, now: float) -> Dictionary:
	var route: Dictionary = book.route
	var owner: Dictionary = snapshot.owner
	var error: String = _route_error(context,route,now)
	if not error.is_empty():return _fail(error)
	if route.ownerId!=owner.id or route.corridor075!=snapshot.corridor075:return _fail("Generated shipping owner or saved corridor changed.")
	if route.phase=="lost":return _result(book,{},"Carrier lost; replacement is funded and born only at the existing home yard.")
	if owner.boats.all(func(b):return b.sunk):
		route.phase="lost";route.location.path=[];route.location.destination=""
		return _result(book,{},"Actual carrier lost; no cargo delivery or at-sea replacement.")
	if now+EPS<float(route.nextDueSecond):return _result(book,{},"Scheduled generated-corridor watch or paid service is not due.")
	route.nextDueSecond=now+1.0
	if route.phase in ["to_origin","outbound"] and (not snapshot.performance.get("seaworthy",false) or int(owner.wageArrears)>0):
		route.phase="to_yard";route.location.path=[];route.location.destination=""
	if route.phase=="yard_arrival":
		if not _at_berth(route.location,snapshot.yardPort):return _fail("Paid recovery requires the actual stopped home yard.")
		route.phase="yard_service";route.nextDueSecond=now+SERVICE_SECONDS
		return _result(book,_command075(route,"service",snapshot.yardPort,"",0),"Request paid home-yard repair, provisions and crew recovery from actual accounts.")
	if route.phase=="yard_service":
		if not _at_berth(route.location,snapshot.yardPort):return _fail("Service is not at the actual home yard.")
		if now+EPS<float(owner.get("harborServiceUntilDay",INF))*DAY_SECONDS:return _result(book,{},"Existing paid home service is still in progress.")
		var required: Dictionary = requirements(context,snapshot)
		if not required.get("ok",false):route.nextDueSecond=now+3.0;return _result(book,{},str(required.message))
		if not _ready(snapshot,required,1.0):
			# A later invoiced visit can repair another finite amount. There is no
			# repeat subsidy and no free readiness grant while the fleet holds.
			route.nextDueSecond=now+SERVICE_SECONDS
			return _result(book,_command075(route,"service",snapshot.yardPort,"",0),"Holding at the real home yard for paid recovery and actual voyage reserves.")
		route.phase="to_origin"
	if not route.location.path.is_empty():return _result(book,{},"The same generated-corridor carrier is physically underway.")
	var destination: Dictionary = snapshot.originPort if route.phase=="to_origin" else (snapshot.remotePort if route.phase=="outbound" else snapshot.yardPort)
	if not _at_berth(route.location,destination):return _next_leg075(context,book,snapshot,destination)
	if route.phase=="to_origin":
		var required: Dictionary = requirements(context,snapshot)
		if not required.get("ok",false):return _result(book,{},str(required.message))
		var offer: Dictionary = cargo_offer075(owner,snapshot.originPort,snapshot.remotePort,int(required.wageCoins)+int(required.repairCoins))
		if not offer.get("ok",false):
			route.phase="to_yard"
			return _result(book,{},str(offer.message)+" Returning physically to the paid home yard.")
		route.phase="outbound"
		return _result(book,_command075(route,"load",destination,str(offer.good),0 if offer.retained else int(offer.qty)),str(offer.reason))
	var qty: int = _delivery075(owner,destination)
	var kind: String = "deliver"
	route.phase="to_yard" if route.phase=="outbound" else "yard_arrival"
	return _result(book,_command075(route,kind,destination,str(owner.tradeGood),qty),"Actual berth reached; sell only the surviving affordable wanted manifest. Remaining cargo retains custody.")


static func _view075(context: Dictionary, region_id: String) -> Dictionary:
	if region_id in [World.HOME,World.REMOTE] or context.get("activeRegionId")==region_id:return context
	var view: Dictionary = context.duplicate(false)
	var region: Dictionary = context.regions[region_id]
	view["activeRegionId"]=region_id
	view["activeNav"]=World.Navigation.create(region.islands,region.width,region.height,World.Navigation.DEFAULT_CELL*World.COAST_SCALE)
	return view


static func _next_leg075(context: Dictionary, book: Dictionary, snapshot: Dictionary, destination: Dictionary) -> Dictionary:
	var route: Dictionary = book.route
	var corridor: Dictionary = route.corridor075
	var target_region: String = str(destination.get("regionId",World.HOME))
	var gate: Dictionary = corridor.homeGate if destination.id==corridor.homeId else (corridor.originGate if destination.id==corridor.originId else corridor.remoteGate)
	var location: Dictionary = route.location
	var identity: Dictionary = location.world064
	var target: Dictionary
	var label: String = ""
	if identity.layer=="ocean":
		target=World._project(context,context.regions[target_region],World._approach(context.regions[target_region],str(gate.approachId)).position)
		if World._distance(location.position,target)<=EPS:
			var entered: Dictionary = World.transition(context,location,target_region,str(gate.approachId),float(snapshot.clearance),"")
			if not entered.get("ok",false):return _fail(str(entered.message))
			location=entered.location;target=_point(destination);label=str(destination.id)
		else:label="approach:%s:%s"%[target_region,str(gate.approachId)]
	elif identity.regionId!=target_region:
		var source_gate: Dictionary = corridor.homeGate if identity.regionId==World.HOME else (corridor.originGate if identity.regionId==corridor.originGate.regionId else corridor.remoteGate)
		target=World._approach(context.regions[identity.regionId],str(source_gate.approachId)).position
		if World._distance(location.position,target)<=EPS:
			var exited: Dictionary = World.transition(context,location,str(identity.regionId),str(source_gate.approachId),float(snapshot.clearance),"")
			if not exited.get("ok",false):return _fail(str(exited.message))
			location=exited.location
			target=World._project(context,context.regions[target_region],World._approach(context.regions[target_region],str(gate.approachId)).position)
			label="approach:%s:%s"%[target_region,str(gate.approachId)]
		elif identity.layer!="home":label="approach:%s:%s"%[str(identity.regionId),str(source_gate.approachId)]
	else:target=_point(destination);label=str(destination.id)
	var view: Dictionary = _view075(context,str(location.world064.regionId)) if location.world064.layer!="ocean" else context
	var plotted: Dictionary = World.plot(view,location,target,label,float(snapshot.clearance))
	if not plotted.get("ok",false):return _fail(str(plotted.message))
	route.location=plotted.location
	return _result(book,{},"Staged one actual generated-corridor water leg; clock and stores remain with the existing campaign.")


static func prepare(saved: Dictionary, context064: Dictionary) -> Dictionary:
	if not saved.has("shipping068"):return _result(empty_book(),{},"Legacy voyage has no shipping enrollment.")
	var outer = saved.get("shipping068")
	if not outer is Dictionary or not outer.has("model"):return _fail("Present shipping068 requires its explicit model book.")
	var book = outer.get("model")
	if not _book_valid(book):return _fail("Invalid shipping068 model schema or fields.")
	if book.route.is_empty():return _result(book.duplicate(true),{},"No merchant is enrolled.")
	if book.route.has("corridor075"):return _prepare075(saved,context064,book)
	if not _number(saved.get("day"),1.0):return _fail("Shipping needs the existing finite campaign clock.")
	var error: String = _route_error(context064,book.route,float(saved.day)*DAY_SECONDS)
	if not error.is_empty():return _fail(error)
	for collection in ["fleetOwners","patrols","fleet","boardingPrizes"]:
		if not saved.get(collection,[] if collection=="boardingPrizes" else null) is Array:return _fail("Shipping physical custody collections are invalid.")
	var owners: Array = saved.fleetOwners.filter(func(o):return o is Dictionary and o.get("id")==OWNER)
	var patrols: Array = saved.patrols.filter(func(p):return p is Dictionary and p.get("id")==OWNER)
	if owners.size()!=1 or patrols.size()!=1:return _fail("Shipping needs one original trader and one dormant home projection.")
	var owner: Dictionary = owners[0]
	var patrol: Dictionary = patrols[0]
	error = _owner_error(owner)
	if not error.is_empty():return _fail(error)
	var clearance: float=10.0
	for boat in owner.boats:
		if not boat.sunk:clearance=maxf(clearance,float(boat.spec.size))
	var physical_location: Dictionary=World.prepare(book.route.location,context064,clearance)
	if not physical_location.get("ok",false):return _fail(str(physical_location.get("message","Unsafe physical shipping route.")))
	if patrol.get("active")!=false or patrol.get("hidden")!=true or patrol.get("holding")!=true or not patrol.get("course") is Array or not patrol.course.is_empty() or patrol.has("interceptPoint"):
		return _fail("Enrolled merchant's home projection must stay dormant.")
	var route: Dictionary = book.route
	var living: int = owner.boats.filter(func(b):return not b.sunk).size()
	if route.phase=="lost":
		if living!=0 or owner.active or owner.get("atPort")!="" or owner.has("harborServiceUntilDay") or not route.location.path.is_empty() or route.location.destination!="":return _fail("Lost shipping cannot retain living hulls, a berth or a moving course.")
	elif living==0 or not owner.active:return _fail("Active shipping requires its original living fleet.")
	if route.phase in ["home_service","remote_service"]:
		var port_id: String = ORIGIN if route.phase=="home_service" else REMOTE_PORT
		if not saved.get("ports") is Array:return _fail("Shipping service requires actual ports.")
		var matches: Array = saved.ports.filter(func(p):return p is Dictionary and p.get("id")==port_id)
		if matches.size()!=1 or not _at_berth(route.location,matches[0]) or owner.get("atPort")!=port_id:return _fail("Shipping service needs its actual stopped canonical berth.")
		if owner.has("harborServiceUntilDay") and (not _number(owner.harborServiceUntilDay,1.0) or float(owner.harborServiceUntilDay)>float(saved.day)+0.25+EPS):return _fail("Shipping paid service deadline is invalid.")
		if int(route.sequence)%6 in [1,4] and not owner.has("harborServiceUntilDay"):return _fail("Serviced shipping must retain its actual service deadline.")
	elif route.phase!="lost" and (owner.get("atPort")!="" or owner.has("harborServiceUntilDay")):
		return _fail("A shipping passage cannot receive remote harbor service.")
	# Check raw UID custody without invoking any boat/owner normalizer.
	var custody: Dictionary = {}
	var all_boats: Array = saved.fleet+saved.get("boardingPrizes",[])
	for other in saved.fleetOwners:
		if not other is Dictionary or not other.get("boats") is Array:return _fail("Invalid raw owner custody.")
		all_boats += other.boats
	for boat in all_boats:
		if not boat is Dictionary:return _fail("Invalid raw physical boat.")
		var uid = boat.get("uid")
		if uid is String and not uid.is_empty():custody[uid]=int(custody.get(uid,0))+1
	for boat in owner.boats:
		if int(custody.get(boat.uid,0))!=1:return _fail("Shipping must preserve unique original hull custody.")
	return _result(book.duplicate(true),{},"Shipping model validated without changing raw state.")


static func requirements(context064: Dictionary, snapshot: Dictionary) -> Dictionary:
	var error: String = _snapshot_error(snapshot)
	if not error.is_empty():return _fail(error)
	if snapshot.has("corridor075"):return _requirements075(context064,snapshot)
	var speed: float = float(snapshot.performance.get("speed",0.0))*0.38*float(snapshot.campaignScale)
	if speed<=0.0:return _fail("Merchant has no powered voyage speed.")
	var home_gate: Dictionary = _gate(context064,World.HOME,false)
	var remote_gate: Dictionary = _gate(context064,World.REMOTE,false)
	var ocean_home: Dictionary = _gate(context064,World.HOME,true)
	var ocean_remote: Dictionary = _gate(context064,World.REMOTE,true)
	if home_gate.is_empty() or remote_gate.is_empty() or ocean_home.is_empty() or ocean_remote.is_empty():return _fail("The two existing northern approaches are required.")
	var home_loc: Dictionary = _location("home",World.HOME,_point(snapshot.originPort))
	var safe_home: Dictionary = World.Navigation.harbor_approach(context064.homeNav,snapshot.originPort,float(snapshot.clearance))
	if safe_home.is_empty():return _fail("The existing home berth has no safe fleet approach.")
	home_loc.position=safe_home
	var north_home: Dictionary = _location("home",World.HOME,home_gate)
	var north_remote: Dictionary = _location("local",World.REMOTE,remote_gate)
	var outward: Dictionary = World.plot(context064,home_loc,home_gate,"",float(snapshot.clearance))
	var homeward: Dictionary = World.plot(context064,north_home,_point(snapshot.originPort),ORIGIN,float(snapshot.clearance))
	var remote: Dictionary = World.plot(context064,north_remote,BERTH,"",float(snapshot.clearance))
	if not outward.get("ok",false) or not homeward.get("ok",false) or not remote.get("ok",false):return _fail("A real northern shipping leg is not navigable at this fleet clearance.")
	var local_distance: float = maxf(_length(home_loc.position,outward.location.path),_length(north_home.position,homeward.location.path))+_length(north_remote.position,remote.location.path)
	var physical_ocean: float = World._distance(ocean_home,ocean_remote)*float(context064.ocean.localUnitsPerUnit)
	# Both physical legs at slowest ocean speed, two quarter-day calls and half
	# a day of maneuver/weather contingency. No simulated time is spent here.
	var days: float = 2.0*(local_distance+physical_ocean/0.25)/speed/DAY_SECONDS+1.0
	var costs: Dictionary = Fleets.upkeep(snapshot.owner)
	if not is_finite(days) or days<=0.0:return _fail("Shipping reserve duration is invalid.")
	return {"ok":true,"days":days,"wageCoins":ceili(float(costs.wages)*days)+int(snapshot.owner.get("wageArrears",0)),"food":ceilf(float(costs.food)*days),"fuel":ceilf(float(costs.fuel)*days),"repairCoins":ceili(float(snapshot.reserves.boats)*Economy.ORDINARY_WAGE),"message":"Conservative round-trip reserve; no guaranteed profit or refill."}


static func plan(context064: Dictionary, modelBook: Dictionary, snapshot: Dictionary, nowSecond: float) -> Dictionary:
	if not _book_valid(modelBook) or not _number(nowSecond,0.0):return _fail("Invalid shipping book or existing campaign time.")
	var error: String = _snapshot_error(snapshot)
	if not error.is_empty():return _fail(error)
	var book: Dictionary = modelBook.duplicate(true)
	var owner: Dictionary = snapshot.owner
	if not book.route.is_empty() and book.route.has("corridor075"):return _plan075(context064,book,snapshot,nowSecond)
	if book.route.is_empty():
		if not owner.active or not snapshot.patrol.get("holding",false) or owner.get("atPort")!=ORIGIN or not _point_valid(snapshot.patrol):return _result(book,{},"Waiting for the same merchant's actual Kelp return and service.")
		var location: Dictionary = _location("home",World.HOME,_point(snapshot.patrol))
		if not _at_berth(location,snapshot.originPort):return _result(book,{},"Merchant has not reached the real Kelp berth.")
		if not _number(owner.get("harborServiceUntilDay"),1.0):return _result(book,{},"Waiting for an actual paid home service visit.")
		if owner.boats.filter(func(b):return not b.sunk).is_empty():return _result(book,{},"The merchant has no surviving physical carrier.")
		book.route={"ownerId":OWNER,"phase":"home_service","location":location,"nextDueSecond":maxf(nowSecond,float(owner.harborServiceUntilDay)*DAY_SECONDS),"sequence":0}
		return _result(book,{},"Original trader admitted at its actual paid home service; no invoice executed by admission.")
	else:
		error=_route_error(context064,book.route,nowSecond)
		if not error.is_empty():return _fail(error)
	var route: Dictionary = book.route
	if route.phase=="lost":return _result(book,{},"This carrier was lost; no cargo can be delivered.")
	if owner.boats.filter(func(b):return not b.sunk).is_empty():
		route.phase="lost";route.location.path=[];route.location.destination=""
		return _result(book,{},"The same physical carrier was lost.")
	if nowSecond+EPS<float(route.nextDueSecond):return _result(book,{},"Scheduled watch or paid harbor service is not yet due.")
	route.nextDueSecond=nowSecond+1.0
	if route.phase=="outbound" and (not snapshot.performance.get("seaworthy",false) or int(owner.wageArrears)>0):
		# An interrupted voyage may reverse without inventing a remote delivery
		# invoice. Its next real home arrival advances the existing sequence.
		route.phase="return";route.location.path=[];route.location.destination=""
	if route.phase in ["home_service","remote_service"]:
		var home: bool = route.phase=="home_service"
		var port: Dictionary = snapshot.originPort if home else snapshot.remotePort
		if not _at_berth(route.location,port):return _fail("Shipping service is not at its actual stopped berth.")
		var slot: int = int(route.sequence)%6
		if slot in [0,3]:
			route.sequence=int(route.sequence)+1;route.nextDueSecond=nowSecond+SERVICE_SECONDS
			return _result(book,_command("service",port,"",0,route.sequence),"Finite paid provisioning and quay service requested once.")
		if not _number(owner.get("harborServiceUntilDay"),1.0) or nowSecond+EPS<float(owner.harborServiceUntilDay)*DAY_SECONDS:return _result(book,{},"Physical paid service has not finished.")
		var required: Dictionary = requirements(context064,snapshot)
		if not required.get("ok",false):
			route.nextDueSecond=nowSecond+3.0
			return _result(book,{},str(required.message))
		var fraction: float = 1.0 if home else 0.5
		if not _ready(snapshot,required,fraction):
			route.nextDueSecond=nowSecond+3.0
			return _result(book,{},"Holding for actual crew, food, fuel, wages and repair reserve; no repeat remittance.")
		var held: float = float(owner.tradeCargo)
		var good: String = "food" if home else "logs"
		var qty: int = 0
		if held>EPS:
			good=str(owner.tradeGood)
			if home and (good!="food" or held>64.0):return _result(book,{},"Unsold prior cargo remains aboard; a bounded food manifest is required before departure.")
		elif Fleets.allowed_trade(owner,port,good):
			var reserve: int = ceili(float(required.wageCoins)*fraction)+int(required.repairCoins)
			var affordable: int = maxi(0,int(owner.coins)-reserve)/maxi(1,Economy.price(port,good,"buy"))
			var capacity: float = maxf(0.0,float(snapshot.reserves.capacity)-Economy.cargo_weight(owner.cargo))
			qty=mini(64,mini(affordable,mini(floori(Harbor.exportable(port,good)),floori(capacity/float(Goods.ITEMS[good].weight)))))
		if home and held+float(qty)<1.0:
			route.nextDueSecond=nowSecond+3.0
			return _result(book,{},"Holding for a funded exportable food lot after all voyage reserves.")
		route.phase="outbound" if home else "return"
		route.sequence=int(route.sequence)+1
		var target: Dictionary = _gate(context064,World.HOME if home else World.REMOTE,false)
		var plotted: Dictionary = World.plot(context064,route.location,target,"" if home else "approach:glasswind_keys:north",float(snapshot.clearance))
		if not plotted.get("ok",false):return _fail(str(plotted.get("message","No safe departure route.")))
		route.location=plotted.location
		return _result(book,_command("load",port,good,qty,route.sequence),"Load only the real affordable lot and depart after paid service.")
	if not route.location.path.is_empty():return _result(book,{},"The physical carrier is underway.")
	var outbound: bool = route.phase=="outbound"
	var destination: Dictionary = snapshot.remotePort if outbound else snapshot.originPort
	if _at_berth(route.location,destination):
		var good: String = str(owner.tradeGood)
		var qty: int = mini(floori(float(owner.cargo.get(good,0.0))),floori(float(owner.tradeCargo)))
		qty=mini(qty,int(destination.get("cash",0))/maxi(1,Economy.price(destination,good,"sell")))
		qty=mini(qty,maxi(0,ceili(Economy.get_equilibrium_stock(destination,good)-float(destination.get("stocks",{}).get(good,0.0)))))
		if not Fleets.allowed_trade(owner,destination,good):qty=0
		route.phase="remote_service" if outbound else "home_service"
		route.sequence=int(route.sequence)+1
		return _result(book,_command("deliver",destination,good,maxi(0,qty),route.sequence),"Real berth reached; unpaid or unwanted cargo stays aboard.")
	return _next_leg(context064,book,snapshot,outbound)


static func actor(modelBook: Dictionary, snapshot: Dictionary) -> Dictionary:
	if not _book_valid(modelBook) or modelBook.route.is_empty() or modelBook.route.get("phase")=="lost" or not _snapshot_error(snapshot).is_empty():return {}
	var route: Dictionary = modelBook.route
	var generic: bool = route.has("corridor075")
	if not _keys(route,["ownerId","phase","location","nextDueSecond","sequence","corridor075"] if generic else ["ownerId","phase","location","nextDueSecond","sequence"]) or route.ownerId!=snapshot.owner.id or route.phase not in (PHASES075 if generic else PHASES) or not _keys(route.location,["world064","position","heading","path","destination"]):return {}
	var powered: bool = snapshot.owner.boats.any(func(b):return not b.sunk and not b.get("mothballed",false) and not b.get("towed",false) and not b.get("needsHarborRepair",false) and str(b.get("storedPort","")).is_empty() and float(b.get("fuel",0.0))>0.0 and float(b.get("crew",0.0))-float(b.get("wounded",0.0))>=float(b.get("crewMin",1.0)))
	return {"ownerId":str(route.ownerId),"location":route.location.duplicate(true),"baseSpeed":float(snapshot.performance.get("speed",0.0))*0.38*float(snapshot.campaignScale) if powered else 0.0,
		"clearance":float(snapshot.clearance),"canMove":powered and route.phase in ["outbound","return","to_origin","to_yard"],"canIntercept":false,"detectionRange":900.0,"interceptRange":75.0,"boats":_render_boats(snapshot.owner.boats)}


static func _next_leg(context: Dictionary, book: Dictionary, snapshot: Dictionary, outbound: bool) -> Dictionary:
	var route: Dictionary = book.route
	var layer: String = str(route.location.world064.layer)
	var target: Dictionary
	var destination: String = ""
	if layer=="ocean":
		var region_id: String = World.REMOTE if outbound else World.HOME
		target=_gate(context,region_id,true)
		if World._distance(route.location.position,target)<=EPS:
			var crossed: Dictionary = World.transition(context,route.location,region_id,"north",float(snapshot.clearance),"")
			if not crossed.get("ok",false):return _fail(str(crossed.get("message","The northern approach refused crossing.")))
			route.location=crossed.location
			var port: Dictionary = snapshot.remotePort if outbound else snapshot.originPort
			target=_point(port);destination="" if outbound else ORIGIN
		else:destination="approach:%s:north"%region_id
	elif (outbound and layer=="home") or (not outbound and layer=="local"):
		var region_id: String = World.HOME if outbound else World.REMOTE
		target=_gate(context,region_id,false)
		if World._distance(route.location.position,target)<=EPS:
			var crossed: Dictionary = World.transition(context,route.location,region_id,"north",float(snapshot.clearance),"")
			if not crossed.get("ok",false):return _fail(str(crossed.get("message","The northern approach refused crossing.")))
			route.location=crossed.location
			region_id=World.REMOTE if outbound else World.HOME
			target=_gate(context,region_id,true);destination="approach:%s:north"%region_id
		elif layer=="local":destination="approach:glasswind_keys:north"
	else:
		var port: Dictionary = snapshot.remotePort if outbound else snapshot.originPort
		target=_point(port);destination="" if outbound else ORIGIN
	var plotted: Dictionary = World.plot(context,route.location,target,destination,float(snapshot.clearance))
	if not plotted.get("ok",false):return _fail(str(plotted.get("message","Shipping route could not be plotted.")))
	route.location=plotted.location
	return _result(book,{},"One physical northern shipping leg staged.")


static func _ready(snapshot: Dictionary, required: Dictionary, fraction: float) -> bool:
	var reserve: Dictionary = snapshot.reserves
	return snapshot.performance.get("seaworthy",false) and Economy.cargo_weight(snapshot.owner.cargo)<=float(reserve.capacity)+EPS and float(reserve.get("food",0.0))+EPS>=float(required.food)*fraction and float(reserve.get("fuel",0.0))+EPS>=float(required.fuel)*fraction and int(snapshot.owner.coins)>=ceili(float(required.wageCoins)*fraction)+int(required.repairCoins)


static func _book_valid(book) -> bool:
	return _keys(book,["schema","route"]) and _number(book.schema) and book.schema==1 and book.route is Dictionary


static func _route_error(context: Dictionary, route: Dictionary, now: float) -> String:
	if route.has("corridor075"):return _route_error075(context,route,now)
	if not _keys(route,["ownerId","phase","location","nextDueSecond","sequence"]) or route.ownerId!=OWNER or route.phase not in PHASES:return "Invalid shipping route owner, phase or fields."
	if not _number(route.sequence,0.0) or float(route.sequence)!=floorf(float(route.sequence)) or float(route.sequence)>1000000000.0:return "Shipping sequence must be a bounded integer."
	var slot: int = int(route.sequence)%6
	if route.phase!="lost" and not ((route.phase in ["home_service","remote_service"] and slot in [0,1,3,4]) or (route.phase in ["outbound","return"] and slot in [2,5])):return "Shipping phase and once-only invoice sequence disagree."
	if not _number(route.nextDueSecond,0.0) or float(route.nextDueSecond)>now+SERVICE_SECONDS+3.0+EPS:return "Invalid scheduled shipping deadline."
	if not _keys(route.location,["world064","position","heading","path","destination"]) or not route.location.path is Array or route.location.path.size()>128:return "Shipping location needs only bounded canonical spatial fields."
	var located: Dictionary = World.prepare(route.location,context,0.0)
	return "" if located.get("ok",false) else str(located.get("message","Invalid shipping location."))


static func _route_error075(context: Dictionary, route: Dictionary, now: float) -> String:
	if not _keys(route,["ownerId","phase","location","nextDueSecond","sequence","corridor075"]) or route.phase not in PHASES075 or not route.ownerId is String or str(route.ownerId).is_empty():return "Invalid generated shipping route fields, owner or phase."
	var corridor = route.corridor075
	if not _keys(corridor,["ownerId","homeId","originId","remoteId","homeGate","originGate","remoteGate"]) or corridor.ownerId!=route.ownerId:return "Invalid generated corridor owner or fields."
	for key in ["ownerId","homeId","originId","remoteId"]:
		if not corridor[key] is String or str(corridor[key]).is_empty():return "Generated corridor identities must be explicit strings."
	if not context.get("ports",{}).has(corridor.homeId) or not context.get("harbors",{}).has(corridor.originId) or not context.harbors.has(corridor.remoteId):return "Generated corridor requires its original home yard and actual generated markets."
	var origin: Dictionary = context.harbors[corridor.originId]
	var remote: Dictionary = context.harbors[corridor.remoteId]
	if origin.regionId==remote.regionId:return "Generated corridor must connect two distinct island groups."
	for pair in [["homeGate",World.HOME],["originGate",str(origin.regionId)],["remoteGate",str(remote.regionId)]]:
		var gate = corridor[pair[0]]
		if not _keys(gate,["regionId","approachId"]) or gate.regionId!=pair[1] or not gate.approachId is String or World._approach(context.regions[gate.regionId],str(gate.approachId)).is_empty():return "Generated corridor approach does not belong to its actual port's chart."
	if not _number(route.sequence,0.0) or float(route.sequence)!=floorf(float(route.sequence)) or float(route.sequence)>1000000000.0:return "Shipping sequence must remain a bounded integer."
	if not _number(route.nextDueSecond,0.0) or float(route.nextDueSecond)>now+SERVICE_SECONDS+3.0+EPS:return "Invalid generated shipping deadline."
	if not _keys(route.location,["world064","position","heading","path","destination"]) or not route.location.path is Array or route.location.path.size()>128:return "Generated carrier needs its bounded canonical spatial fields."
	if str(route.location.get("world064",{}).get("regionId","")) not in [World.OCEAN,World.HOME,str(origin.regionId),str(remote.regionId)]:return "Generated carrier left its one bounded corridor."
	var located: Dictionary = World.prepare(route.location,context,0.0)
	return "" if located.get("ok",false) else str(located.get("message","Invalid generated carrier location."))


static func _prepare075(saved: Dictionary, context: Dictionary, book: Dictionary) -> Dictionary:
	if not _number(saved.get("day"),1.0):return _fail("Generated shipping needs the existing finite clock.")
	if not saved.has("sector069"):return _fail("A legacy two-region career cannot acquire generated shipping during restore.")
	for collection in ["fleetOwners","patrols","fleet","boardingPrizes","ports"]:
		if not saved.get(collection,[] if collection=="boardingPrizes" else null) is Array:return _fail("Generated shipping needs its actual physical custody collections.")
	var route: Dictionary = book.route
	var error: String = _route_error075(context,route,float(saved.day)*DAY_SECONDS)
	if not error.is_empty():return _fail(error)
	var owners: Array = saved.get("fleetOwners",[]).filter(func(o):return o is Dictionary and o.get("id")==route.ownerId)
	var patrols: Array = saved.get("patrols",[]).filter(func(p):return p is Dictionary and p.get("id")==route.ownerId)
	if owners.size()!=1 or patrols.size()!=1:return _fail("Generated shipping needs one existing owner and one dormant projection.")
	var owner: Dictionary = owners[0]
	var patrol: Dictionary = patrols[0]
	error=_owner_error(owner,true)
	if not error.is_empty():return _fail(error)
	if owner.homePort!=route.corridor075.homeId:return _fail("Generated shipping cannot change its existing home yard.")
	var ports: Dictionary = {}
	for port in saved.get("ports",[]):
		if port.get("id") in [route.corridor075.homeId,route.corridor075.originId,route.corridor075.remoteId]:
			if ports.has(port.id):return _fail("Ambiguous generated shipping market.")
			ports[port.id]=port
	if ports.size()!=3:return _fail("Generated shipping cannot initialize missing markets during restore.")
	for id in [route.corridor075.originId,route.corridor075.remoteId]:
		for key in ["regionId","x","y"]:
			if ports[id].get(key)!=context.harbors[id].get(key):return _fail("Generated shipping's physical berth changed.")
	var living: int = owner.boats.filter(func(b):return not b.sunk).size()
	if route.phase=="lost":
		if living!=0 or owner.active or owner.get("atPort")!="" or owner.has("harborServiceUntilDay") or not route.location.path.is_empty() or route.location.destination!="":return _fail("Lost generated shipping cannot retain living hulls or a moving berth.")
	elif living==0 or not owner.active:return _fail("Active generated shipping requires its actual living carrier.")
	if route.phase in ["yard_service","yard_arrival"]:
		var yard: Dictionary = ports[route.corridor075.homeId]
		if owner.get("atPort")!=yard.id or not _at_berth(route.location,yard):return _fail("Generated recovery needs its actual stopped home berth.")
		if owner.has("harborServiceUntilDay") and (not _number(owner.harborServiceUntilDay,1.0) or float(owner.harborServiceUntilDay)>float(saved.day)+0.25+EPS):return _fail("Invalid paid generated-shipping service deadline.")
	else:
		if owner.get("atPort")!="" or owner.has("harborServiceUntilDay"):return _fail("Generated passage cannot receive remote at-sea service.")
	if patrol.get("active")!=false or patrol.get("hidden")!=true or patrol.get("holding")!=true or not patrol.get("course") is Array or not patrol.course.is_empty() or patrol.has("interceptPoint"):return _fail("Generated merchant's old local projection must remain dormant.")
	var custody: Dictionary = {}
	var boats: Array = saved.get("fleet",[])+saved.get("boardingPrizes",[])
	for other in saved.get("fleetOwners",[]):
		if not other is Dictionary or not other.get("boats") is Array:return _fail("Invalid generated fleet custody.")
		boats+=other.boats
	for boat in boats:
		if not boat is Dictionary:return _fail("Invalid raw hull custody.")
		var uid: String = str(boat.get("uid",""))
		if not uid.is_empty():custody[uid]=int(custody.get(uid,0))+1
	var clearance: float = 10.0
	for boat in owner.boats:
		if int(custody.get(str(boat.uid),0))!=1:return _fail("Generated shipping must preserve unique original hull custody.")
		if not boat.sunk:clearance=maxf(clearance,float(boat.spec.size))
	var physical: Dictionary = World.prepare(route.location,context,clearance)
	return _result(book.duplicate(true),{},"Generated corridor validated without restoring any wealth, stock or hull.") if physical.get("ok",false) else _fail(str(physical.message))


static func _snapshot_error(snapshot: Dictionary) -> String:
	var generic: bool = snapshot.has("corridor075")
	if not _keys(snapshot,["owner","patrol","originPort","remotePort","reserves","performance","clearance","campaignScale","yardPort","corridor075"] if generic else ["owner","patrol","originPort","remotePort","reserves","performance","clearance","campaignScale"]):return "Shipping snapshot requires exactly the agreed physical queries."
	for key in ["owner","patrol","originPort","remotePort","reserves","performance"]:
		if not snapshot[key] is Dictionary:return "Shipping physical queries must be dictionaries."
	var error: String = _owner_error(snapshot.owner,generic)
	if not error.is_empty():return error
	if snapshot.patrol.get("id")!=snapshot.owner.id:return "Shipping snapshot must use the same original patrol."
	if generic:
		var corridor: Dictionary = snapshot.corridor075
		if not snapshot.yardPort is Dictionary or not _keys(corridor,["ownerId","homeId","originId","remoteId","homeGate","originGate","remoteGate"]):return "Generated shipping needs its explicit saved owner, markets and gates."
		if corridor.ownerId!=snapshot.owner.id or corridor.homeId!=snapshot.owner.homePort or snapshot.yardPort.get("id")!=corridor.homeId or snapshot.originPort.get("id")!=corridor.originId or snapshot.remotePort.get("id")!=corridor.remoteId:return "Generated shipping snapshot changed a bound owner or physical market."
		if not _point_valid(snapshot.yardPort) or not _point_valid(snapshot.originPort) or not _point_valid(snapshot.remotePort) or snapshot.originPort.get("regionId")==snapshot.remotePort.get("regionId"):return "Generated shipping needs two distinct actual island groups."
	else:
		if snapshot.originPort.get("id")!=ORIGIN or snapshot.remotePort.get("id")!=REMOTE_PORT or snapshot.remotePort.get("regionId")!=World.REMOTE or snapshot.remotePort.get("faction")!="reed" or not _point_valid(snapshot.originPort) or not _point_valid(snapshot.remotePort) or _point(snapshot.remotePort)!=BERTH:return "Shipping needs the actual funded Kelp/Westglass endpoints and final berth."
	if not _number(snapshot.clearance,0.0) or not _number(snapshot.campaignScale,EPS):return "Shipping clearance and scale must be finite."
	if not _number(snapshot.performance.get("speed"),0.0):return "Shipping performance must contain finite actual speed."
	for key in ["capacity","boats","food","fuel"]:
		if not _number(snapshot.reserves.get(key),0.0):return "Shipping reserves must contain actual finite physical quantities."
	return ""


static func _owner_error(owner: Dictionary, generic: bool = false) -> String:
	if (not generic and (owner.get("id")!=OWNER or owner.get("homePort")!=ORIGIN)) or not owner.get("id") is String or str(owner.id).is_empty() or str(owner.id).begins_with("story-") or owner.get("kind")!="trader" or owner.get("playerCompany",false) or not owner.get("active") is bool:return "Shipping requires its original independent physical trader."
	if not owner.get("boats") is Array or owner.boats.size()>36 or not owner.get("cargo") is Dictionary:return "Shipping needs the actual bounded physical boats and hold."
	for key in ["coins","crewPurse","wageArrears","tradeCargo"]:
		if not _number(owner.get(key),0.0):return "Shipping accounts and manifest must be finite and nonnegative."
	if not owner.get("tradeGood") is String or not Goods.ITEMS.has(owner.tradeGood):return "Shipping manifest good is invalid."
	for good in owner.cargo:
		if not good is String or not Goods.ITEMS.has(good) or not _number(owner.cargo[good],0.0):return "Shipping hold contains invalid raw goods."
	if float(owner.tradeCargo)>float(owner.cargo.get(owner.tradeGood,0.0))+EPS:return "Shipping manifest exceeds the surviving physical cargo."
	var ids: Dictionary = {}
	for boat in owner.boats:
		if not boat is Dictionary or not boat.get("spec") is Dictionary or not boat.get("uid") is String or str(boat.uid).is_empty() or ids.has(boat.uid) or not boat.get("sunk") is bool:return "Shipping hull identity or physical specification is invalid."
		ids[boat.uid]=true
		for key in ["size","cargo","speed"]:
			if not _number(boat.spec.get(key),0.0):return "Shipping physical hull dimensions must be finite."
		for key in ["fuel","crew","wounded"]:
			if not _number(boat.get(key),0.0):return "Shipping hull stores and crew must be finite."
	return ""


static func _at_berth(location: Dictionary, port: Dictionary) -> bool:
	if not location.get("world064") is Dictionary or not location.get("path") is Array or not location.path.is_empty() or not _point_valid(location.get("position")) or not _point_valid(port):return false
	var region: String = str(port.get("regionId",World.HOME))
	return location.world064.get("layer")==("home" if region==World.HOME else "local") and location.world064.get("regionId")==region and World._distance(location.position,port)<40.0


static func _gate(context: Dictionary, region_id: String, ocean: bool) -> Dictionary:
	var region = context.get("regions",{}).get(region_id)
	if not region is Dictionary or not region.get("approaches") is Array:return {}
	for approach in region.approaches:
		if approach.get("id")=="north":return World._project(context,region,approach.position) if ocean else _point(approach.position)
	return {}


static func _render_boats(boats: Array) -> Array:
	var result: Array = []
	for boat in boats:
		if boat.sunk:continue
		var spec: Dictionary = {"id":str(boat.get("type",boat.spec.get("id","")))}
		for key in ["role","size","tier","faction","weapon","fuelUse"]:
			if boat.spec.has(key):spec[key]=boat.spec[key]
		var mounts: Array = []
		for mount in boat.spec.get("weaponMounts",[]):
			var item: Dictionary = {}
			for key in ["id","moduleId","kind","size","x","y","angle"]:
				if mount.has(key):item[key]=mount[key]
			mounts.append(item)
		if not mounts.is_empty():spec["weaponMounts"]=mounts
		result.append({"uid":str(boat.uid),"spec":spec,"engineModule":str(boat.get("engineModule","stock_engine"))})
	return result


static func _command(kind: String, port: Dictionary, good: String, qty: int, sequence: int) -> Dictionary:
	return {"kind":kind,"ownerId":OWNER,"portId":str(port.id),"good":good,"qty":qty,"sequence":sequence}


static func _result(book: Dictionary, command: Dictionary, message: String) -> Dictionary:
	return {"ok":true,"book":book,"command":command,"message":message}


static func _fail(message: String) -> Dictionary:
	return {"ok":false,"message":message}


static func _location(layer: String, region: String, position: Dictionary) -> Dictionary:
	return {"world064":{"schema":1,"layer":layer,"regionId":region},"position":position.duplicate(),"heading":0.0,"path":[],"destination":""}


static func _length(start: Dictionary, path: Array) -> float:
	var distance: float = 0.0
	var previous: Dictionary = start
	for point in path:distance+=World._distance(previous,point);previous=point
	return distance


static func _number(value, minimum: float = -INF) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum


static func _keys(value, keys: Array) -> bool:
	if not value is Dictionary or value.size()!=keys.size():return false
	for key in keys:
		if not value.has(key):return false
	return true


static func _point_valid(value) -> bool:
	return value is Dictionary and _number(value.get("x")) and _number(value.get("y"))


static func _point(value: Dictionary) -> Dictionary:
	return {"x":float(value.x),"y":float(value.y)}
