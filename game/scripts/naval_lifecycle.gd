extends RefCounted
const Routes=preload("res://scripts/route_cache.gd")
## Main-thread campaign publication around bounded autonomous daily decisions.
const AI=preload("res://scripts/naval_ai.gd")
const Fleets=preload("res://scripts/fleet_economy.gd")
const Economy=preload("res://scripts/economy.gd")
const Navigation=preload("res://scripts/navigation.gd")
const Factions=preload("res://scripts/factions.gd")
const Salvage=preload("res://scripts/salvage.gd")
const Contacts=preload("res://scripts/contacts.gd")

static func hire(c,owner: Dictionary,p: Dictionary) -> void:
	for boat in owner.boats:
		if boat.sunk:continue
		var survivors: int=maxi(0,floori(float(boat.crew)))
		var need: int=maxi(0,ceili(float(boat.crewMin))-survivors)
		if need<=0:continue
		var result: Dictionary=Economy.recruit(p,owner,need,floori(float(boat.crewMax))-survivors)
		if result.ok:
			boat.crew=survivors+int(result.count)
			boat.wounded=minf(float(boat.wounded),float(boat.crew))

static func refuse_route(c,p: Dictionary,reason: String) -> void:
	var changed: bool=str(p.get("routeFailure",""))!=reason
	p.routeFailure=reason;p.holding=true;p.course=[];p.courseLength=0.0;p.progress=0.0
	var owner: Dictionary=c.fleet_owner(str(p.id))
	if owner.is_empty():return
	owner.progress=0.0;owner.navigationReason=reason
	var dock: Dictionary=c.port(str(owner.get("atPort","")))
	if dock.is_empty() or c.distance(p,dock)>=40.0 or not Navigation.is_water(c.nav,p.x,p.y,Routes.clearance(c,p)):owner.atPort=""
	if owner.get("order") is Dictionary:owner.order.reason=reason
	if changed:
		Fleets._log(owner,reason)
		if c.distance(c.state.position,p)<=1800.0:c.log_entry("%s: %s"%[owner.get("name",p.id),reason])

static func route(c,p: Dictionary,dest: String,intercept_point: Dictionary={}) -> void:
	var target: Dictionary=c.port(dest)
	if target.is_empty():return
	var owner: Dictionary=c.fleet_owner(p.id)
	if owner.is_empty():return
	var actual: float=Routes.clearance(c,p)
	p.to=dest;p.courseClearance=actual
	if intercept_point.is_empty():p.erase("interceptPoint")
	else:p.interceptPoint=intercept_point.duplicate()
	var goal: Dictionary=target if intercept_point.is_empty() else intercept_point
	p.course=Routes.path(c,p,goal,actual)
	p.courseLength=0.0
	if p.course.is_empty():
		refuse_route(c,p,"No safe harbor approach or water route for a hull this size (%.0f clearance)."%actual)
		return
	p.routeFailure="";owner.navigationReason="";p.progress=0.0
	for i in range(1,p.course.size()):p.courseLength+=c.distance(p.course[i-1],p.course[i])
	if c.distance(p,goal)<40.0:
		# Already in service range at a certified water position: keep that
		# position, including an offset approach for a large hull.
		p.holding=true;owner.atPort=dest if intercept_point.is_empty() else ""
		return
	p.voyageSeq=int(p.get("voyageSeq",0))+1
	p.holding=false;owner.atPort=""

static func holding(c,owner: Dictionary) -> bool:
	if str(owner.get("atPort","")).is_empty():return false
	if owner.get("playerCompany",false):
		var reason: String=preload("res://scripts/naval_orders.gd").needs_home_recovery(owner,AI.fleet_reserves(owner),AI.fleet_performance(owner))
		if not reason.is_empty():return str(owner.atPort)==str(owner.homePort) or owner.get("purpose","")=="repair"
		return c.CompanyOps.hold(c,owner)
	if str(owner.atPort)!=str(owner.homePort) and str(owner.get("purpose",""))!="repair":return false
	var res: Dictionary=AI.fleet_reserves(owner)
	var perf: Dictionary=AI.fleet_performance(owner)
	return not preload("res://scripts/naval_orders.gd").needs_home_recovery(owner,res,perf).is_empty()

static func step(c,dt: float) -> void:
	if not is_finite(dt) or dt<=0:return
	c.state.navalEncounterElapsed=float(c.state.get("navalEncounterElapsed",0.0))+dt
	if c.state.navalEncounterElapsed>=1.0:
		# One scan only, even after a long step; never replay missed intervals.
		c.state.navalEncounterElapsed=0.0
		for message in AI.scan_encounters(c):c.log_entry(str(message))
		Contacts.witnessed_encounters(c.state)
		c.RegionalOps.refresh(c)
	for p in c.state.patrols:
		var owner: Dictionary=c.fleet_owner(p.id)
		if owner.is_empty():continue
		p.hostile=false if owner.get("playerCompany",false) else Factions.is_hostile(c.state,str(owner.faction))
		if not p.active:continue
		if str(owner.get("purpose","")) in ["withdraw","repair","replace","resupply"] and (str(owner.get("destination",p.to))!=str(p.to) or p.has("interceptPoint")):
			route(c,p,str(owner.destination))
		if not p.get("holding",false):
			var actual: float=Routes.clearance(c,p)
			if p.get("course",[]).is_empty():
				refuse_route(c,p,"Course stopped: no safe water route for a hull this size (%.0f clearance)."%actual)
			elif not is_equal_approx(float(p.get("courseClearance",0)),actual):
				var remaining: Array=c.remaining_patrol_course(p)
				if remaining.is_empty() or not Navigation.path_clear(c.nav,{"x":p.x,"y":p.y},remaining,actual):
					refuse_route(c,p,"Course stopped: no safe water route for a hull this size (%.0f clearance). Position unchanged."%actual)
				else:p.courseClearance=actual
		if not p.get("holding",false):
			var performance: Dictionary=AI.fleet_performance(owner)
			p.progress+=dt*float(performance.speed)*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0))/maxf(1,float(p.courseLength))
			if p.progress>=1:
				var dock: Dictionary=c.port(p.to)
				var endpoint: Dictionary=p.course[-1]
				if p.has("interceptPoint"):
					# A sea interception is not an endpoint visit or a serviced dock.
					p.x=endpoint.x;p.y=endpoint.y;p.progress=0.0;p.holding=true
					owner.atPort="";owner.progress=0.0
					c.RegionalOps.refresh(c)
					continue
				if dock.is_empty() or c.distance(endpoint,dock)>=40.0:
					refuse_route(c,p,"Course stopped: no safe harbor approach within docking range.")
					continue
				var origin: String=str(p.from)
				var delivered_before: float=float(owner.get("tradeDelivered",0))
				p.x=endpoint.x;p.y=endpoint.y;p.from=p.to;p.progress=0.0;p.holding=true
				Fleets.dock(owner,dock,c);hire(c,owner,dock)
				c.RegionalOps.delivered(c,str(dock.id),maxf(0,float(owner.get("tradeDelivered",0))-delivered_before),origin,false)
				var next: String=AI.arrived(c,owner,dock)
				if holding(c,owner):route(c,p,dock.id)
				else:route(c,p,next)
				c.RegionalOps.refresh(c)
			else:c.place_patrol(p)
		owner.progress=p.progress
		if not p.get("holding",false):owner.atPort=""
		if p.hostile and c.state.encounterGrace<=0 and c.distance(c.state.position,p)<75 and c.state.day>2:
			c.state.encounterGrace=60.0;c.stop_sailing()
			c.events.append({"kind":"encounter","patrol":p.id})

static func daily(c) -> void:
	c.state.yardsAdvancedThisDay=true
	for message in AI.tick(c,1):c.log_entry(str(message))
	Contacts.witnessed_encounters(c.state)
	c.state.erase("yardsAdvancedThisDay")
	for p in c.state.patrols:
		var owner: Dictionary=c.fleet_owner(p.id)
		if owner.is_empty():continue
		var sunk: Array=[]
		for boat in owner.boats:
			if boat.sunk and not boat.get("wreckRecorded",false):
				boat.wreckRecorded=true;sunk.append(boat)
		if not sunk.is_empty():
			var source: String="npc:%s:%d:%s"%[owner.id,int(c.state.econDay),str(sunk[0].get("uid","lost"))]
			var records: Array=Salvage.record_battle(c,{"ships":sunk,"chartPosition":{"x":p.x,"y":p.y}},source)
			var fraction: float=float(sunk.size())/maxi(1,sunk.size()+owner.boats.filter(func(b):return not b.sunk).size())
			for good in owner.cargo:
				var lost: float=float(owner.cargo[good])*fraction
				owner.cargo[good]-=lost
				if good==owner.get("tradeGood",""):owner.tradeCargo=maxf(0,float(owner.tradeCargo)-lost)
				if not records.is_empty():
					var wreck: Dictionary=Salvage.find_wreck(c.state,records[0].id)
					wreck.stores[good]=float(wreck.stores.get(good,0))+lost*0.5
		if owner.get("playerCompany",false):c.CompanyOps.reconcile(c,owner)
		p.active=bool(owner.active) and owner.boats.any(func(b):return not b.sunk)
		if not p.active:continue
		if not str(p.get("routeFailure","")).is_empty():
			if str(owner.get("destination",p.to))!=str(p.to) or not is_equal_approx(float(p.get("courseClearance",0)),Routes.clearance(c,p)):
				route(c,p,str(owner.get("destination",p.to)))
			if not str(p.get("routeFailure","")).is_empty():continue
		if p.get("holding",false) and str(owner.get("atPort",""))==str(owner.homePort):
			var home: Dictionary=c.port(owner.homePort)
			if int(home.get("availableSpecialists",0))<1 and owner.boats.any(func(b):return not b.sunk and b.engine<0.68) and int(owner.coins)>=150:
				for yard in c.state.ports:
					if yard.id==home.id or int(yard.get("availableSpecialists",0))<1 or float(yard.stocks.supplies)<1 or Factions.relation(c.state,owner.faction,yard.faction)<=-20:continue
					AI.build_order(c.state,owner,"repair",yard.id,"Diverting to %s for an available paid engine specialist."%yard.name)
					route(c,p,yard.id)
					break
		if p.get("holding",false):
			var dock: Dictionary=c.port(str(owner.atPort))
			if not dock.is_empty():hire(c,owner,dock)
			if not holding(c,owner):route(c,p,AI.arrived(c,owner,dock))
		elif str(owner.get("destination",p.to))!=str(p.to):route(c,p,str(owner.destination))
	c.RegionalOps.refresh(c)
