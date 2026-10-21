extends RefCounted
## Main-thread campaign publication around bounded autonomous daily decisions.
const AI=preload("res://scripts/naval_ai.gd")
const Fleets=preload("res://scripts/fleet_economy.gd")
const Economy=preload("res://scripts/economy.gd")
const Navigation=preload("res://scripts/navigation.gd")
const Factions=preload("res://scripts/factions.gd")
const Salvage=preload("res://scripts/salvage.gd")

static func hire(c,owner: Dictionary,p: Dictionary) -> void:
	for boat in owner.boats:
		if boat.sunk:continue
		var need: int=maxi(0,int(boat.crewMin)-int(boat.crew))
		if need<=0:continue
		var result: Dictionary=Economy.recruit(p,owner,need,int(boat.crewMax)-int(boat.crew))
		if result.ok:boat.crew+=int(result.count)

static func route(c,p: Dictionary,dest: String) -> void:
	var target: Dictionary=c.port(dest)
	if target.is_empty():return
	var owner: Dictionary=c.fleet_owner(p.id)
	if c.distance(p,target)<40:
		p.holding=true;owner.atPort=dest;p.progress=0.0;p.to=dest
		return
	p.holding=false;owner.atPort="";p.to=dest;p.progress=0.0
	p.course=Navigation.find_path(c.nav,p,target)
	p.courseLength=0.0
	for i in range(1,p.course.size()):p.courseLength+=c.distance(p.course[i-1],p.course[i])

static func holding(c,owner: Dictionary) -> bool:
	if str(owner.get("atPort",""))!=str(owner.homePort):return false
	var res: Dictionary=AI.fleet_reserves(owner)
	var perf: Dictionary=AI.fleet_performance(owner)
	return not preload("res://scripts/naval_orders.gd").needs_home_recovery(owner,res,perf).is_empty()

static func step(c,dt: float) -> void:
	for p in c.state.patrols:
		var owner: Dictionary=c.fleet_owner(p.id)
		if owner.is_empty():continue
		p.hostile=Factions.is_hostile(c.state,str(owner.faction))
		if not p.active:continue
		if not p.get("holding",false):
			var performance: Dictionary=AI.fleet_performance(owner)
			p.progress+=dt*float(performance.speed)*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0))/maxf(1,float(p.courseLength))
			if p.progress>=1:
				var dock: Dictionary=c.port(p.to)
				p.x=dock.x;p.y=dock.y;p.from=p.to;p.progress=0.0
				Fleets.dock(owner,dock);hire(c,owner,dock)
				var next: String=AI.arrived(c,owner,dock)
				if holding(c,owner):route(c,p,owner.homePort)
				else:route(c,p,next)
			else:c.place_patrol(p)
		owner.progress=p.progress
		if not p.get("holding",false):owner.atPort=""
		if p.hostile and c.state.encounterGrace<=0 and c.distance(c.state.position,p)<75 and c.state.day>2:
			c.state.encounterGrace=60.0;c.stop_sailing()
			c.events.append({"kind":"encounter","patrol":p.id})

static func daily(c) -> void:
	c.state.yardsAdvancedThisDay=true
	for message in AI.tick(c,1):c.log_entry(str(message))
	c.state.erase("yardsAdvancedThisDay")
	for p in c.state.patrols:
		var owner: Dictionary=c.fleet_owner(p.id)
		if owner.is_empty():continue
		var sunk: Array=[]
		for boat in owner.boats:
			if boat.sunk and not boat.get("wreckRecorded",false):
				boat.wreckRecorded=true;sunk.append(boat)
		if not sunk.is_empty():
			var source: String="npc:%s:%d:%d"%[owner.id,int(c.state.day),int(owner.get("nextBoatSeq",0))]
			var records: Array=Salvage.record_battle(c,{"ships":sunk,"chartPosition":{"x":p.x,"y":p.y}},source)
			var fraction: float=float(sunk.size())/maxi(1,owner.boats.size())
			for good in owner.cargo:
				var lost: float=float(owner.cargo[good])*fraction
				owner.cargo[good]-=lost
				if good==owner.get("tradeGood",""):owner.tradeCargo=maxf(0,float(owner.tradeCargo)-lost)
				if not records.is_empty():
					var wreck: Dictionary=Salvage.find_wreck(c.state,records[0].id)
					wreck.stores[good]=float(wreck.stores.get(good,0))+lost*0.5
		p.active=bool(owner.active) and owner.boats.any(func(b):return not b.sunk)
		if not p.active:continue
		if p.get("holding",false):
			var dock: Dictionary=c.port(str(owner.atPort))
			if not dock.is_empty():hire(c,owner,dock)
			if not holding(c,owner):route(c,p,AI.arrived(c,owner,dock))
		elif str(owner.get("destination",p.to))!=str(p.to):route(c,p,str(owner.destination))
