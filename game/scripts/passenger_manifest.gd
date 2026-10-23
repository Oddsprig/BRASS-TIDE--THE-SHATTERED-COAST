extends RefCounted
## Pure saved-manifest reads, shared by logistics and the main-thread adapter.
static func assigned(s: Dictionary,uid: String) -> int:
	var total: int=0
	for j in s.get("regionalCrises",{}).get("jobs",[]):
		if j.stage!="holding" and s.get("passengerTransport",{}).get("carriers",{}).get(str(j.id),"")==uid:total+=int(j.n)
	return total
static func food_weight(s: Dictionary,uid: String="") -> float:
	var total: float=0.0
	for j in s.get("regionalCrises",{}).get("jobs",[]):
		if j.stage=="holding":continue
		if not uid.is_empty() and s.get("passengerTransport",{}).get("carriers",{}).get(str(j.id),"")!=uid:continue
		total+=float(j.food.get("food",0))
	return total
