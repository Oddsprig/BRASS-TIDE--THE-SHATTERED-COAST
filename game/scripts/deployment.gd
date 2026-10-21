extends RefCounted
## Shared fleet accounting. Split arrays keep the original boat references.
const LIMIT: int=300

static func _number(value, fallback: float=0.0) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return float(value)
	return fallback

static func cost(ship_or_spec: Dictionary) -> int:
	var spec: Dictionary=ship_or_spec.get("spec",ship_or_spec)
	# Effective fittings publish their canonical cost. Large explicit costs stay
	# large so an over-limit boat is reserved rather than silently discounted.
	var canonical: float=_number(spec.get("deploymentPoints"))
	if canonical>0.0:
		return maxi(8,int(ceil(minf(canonical,1000000.0))))
	var base: Dictionary=ship_or_spec.get("baseSpec",spec)
	var role: String=str(base.get("role","skiff"))
	var role_points: float=float({"skiff":0,"cutter":2,"raider":4,"corvette":6,"torpedo":7,"gunboat":10,"rocket":8,"cruiser":13}.get(role,3))
	var tier: float=clampf(_number(base.get("tier"),1.0),1.0,10.0)
	var hp: float=clampf(_number(base.get("hp"),100.0),0.0,1000000.0)
	var size: float=clampf(_number(base.get("size"),14.0)-12.0,0.0,1000000.0)
	return clampi(int(ceil(8.0+role_points+(tier-1.0)*5.0+hp/28.0+size*0.8)),8,75)

static func total(fleet: Array) -> int:
	var points: int=0
	for ship in fleet:
		points+=cost(ship)
	return points

static func fits(fleet: Array,spec: Dictionary) -> bool:
	return total(fleet)+cost(spec)<=LIMIT

static func split(fleet: Array,limit: int=LIMIT) -> Dictionary:
	var deployed: Array=[]
	var reserve: Array=[]
	var points: int=0
	var budget: int=maxi(0,limit)
	for ship in fleet:
		if ship.get("supportOnly",false):
			reserve.append(ship)
			continue
		var amount: int=cost(ship)
		if points+amount<=budget:
			deployed.append(ship)
			points+=amount
		else:
			reserve.append(ship)
	return {"deployed":deployed,"reserve":reserve,"points":points}
