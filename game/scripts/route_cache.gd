extends RefCounted
## Compatibility adapter: fixed-coast campaign caches remain outside save data.
const Navigation=preload("res://scripts/navigation.gd")
static func _owner(c,actor: Dictionary) -> Dictionary:
	var id: String=str(actor.get("id",""))
	if not id.is_empty():
		for owner in c.state.get("fleetOwners",[]):
			if str(owner.get("id",""))==id:return owner
	return {}

static func clearance(c,actor: Dictionary={}) -> float:
	var owner: Dictionary=_owner(c,actor)
	var boats: Array=c.state.get("fleet",[]) if owner.is_empty() else owner.get("boats",[])
	var result: float=Navigation.DEFAULT_CLEARANCE
	for boat in boats:
		if boat.get("sunk",false) or not str(boat.get("storedPort","")).is_empty():continue
		if owner.is_empty() and not boat.get("towed",false):
			if boat.get("mothballed",false) or boat.get("needsHarborRepair",false) or float(boat.get("crew",0))<float(boat.get("crewMin",1)):continue
		result=maxf(result,Navigation.hull_clearance(boat.get("spec",{}).get("size",10)))
	return result

static func _port(c,point: Dictionary) -> Dictionary:
	for p in c.state.get("ports",[]):
		if point.get("x")==p.x and point.get("y")==p.y:return p
	return {}

static func endpoint(c,point: Dictionary,hull_size: float,service_range: float=65.0) -> Dictionary:
	var port: Dictionary=_port(c,point)
	return point if port.is_empty() else Navigation.harbor_approach(c.nav,port,hull_size,service_range)

static func path(c,a: Dictionary,b: Dictionary,hull_size: float=-1.0) -> Array:
	var actual: float=clearance(c,a) if hull_size<0 else Navigation.hull_clearance(hull_size)
	var service_range: float=40.0 if not _owner(c,a).is_empty() else 65.0
	var end: Dictionary=endpoint(c,b,actual,service_range)
	if end.is_empty():return []
	var start: Dictionary=a
	# Port-to-port quotations may start at a safe approach. Actual player/NPC
	# coordinates are authoritative and are never snapped away from unsafe water.
	var origin: Dictionary=_port(c,a)
	if not origin.is_empty() and str(a.get("id",""))==str(origin.id):
		start=Navigation.harbor_approach(c.nav,origin,actual,service_range)
	if start.is_empty():return []
	# The adapter shares Campaign's exact-endpoint + clearance cache; it keeps
	# no second cache or saved path state that could bypass the hull-size key.
	if c is Object and c.has_method("cached_path"):return c.cached_path(start,end,actual)
	return Navigation.find_path(c.nav,start,end,actual)
