extends RefCounted
## Pure saved-manifest reads, shared by logistics and the main-thread adapter.
static func assigned(s: Dictionary,uid: String) -> int:
	var total: int=0
	for j in s.get("regionalCrises",{}).get("jobs",[]):
		if j.stage!="holding" and s.get("passengerTransport",{}).get("carriers",{}).get(str(j.id),"")==uid:total+=int(j.n)
	for j in s.get("voyageJobs",[]):
		if j.get("kind","")=="passenger_charter" and str(j.get("carrierUid",""))==uid:total+=int(j.get("passengers",{}).get("n",0))
	return total
static func food_weight(s: Dictionary,uid: String="") -> float:
	var total: float=0.0
	for j in s.get("regionalCrises",{}).get("jobs",[]):
		if j.stage=="holding":continue
		if not uid.is_empty() and s.get("passengerTransport",{}).get("carriers",{}).get(str(j.id),"")!=uid:continue
		total+=float(j.food.get("food",0))
	for j in s.get("voyageJobs",[]):
		if j.get("kind","")!="passenger_charter" or (not uid.is_empty() and str(j.get("carrierUid",""))!=uid):continue
		total+=float(j.get("charterFood",{}).get("food",0))
	return total
