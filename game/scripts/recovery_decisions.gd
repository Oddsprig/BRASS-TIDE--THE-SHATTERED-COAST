extends RefCounted
## Panel-time read model. Transactions remain in Campaign/Salvage; no live writes.
const Expedition=preload("res://scripts/expedition.gd")
const Navigation=preload("res://scripts/navigation.gd")
const Factions=preload("res://scripts/factions.gd")
const Refits=preload("res://scripts/refit.gd")
const Tow=preload("res://scripts/equipment_tow.gd")
const Lifecycle=preload("res://scripts/equipment_lifecycle.gd")
const Service=preload("res://scripts/equipment_service.gd")
const Goods=preload("res://scripts/goods.gd")
const Preflight=preload("res://scripts/equipment_campaign.gd")
const FleetSupport=preload("res://scripts/fleet_support.gd")

class DetachedView extends RefCounted:
	var state: Dictionary
	var data: Dictionary
	var nav: Dictionary
	var paths: Dictionary
	func _init(c,copy: Dictionary,cache: Dictionary) -> void:
		Preflight._clone_boats(c.state,copy) # Preserve real roster alias identity.
		state=copy
		data=c.data # Shared read-only catalogue and warmed immutable navigation.
		nav=c.nav
		paths=cache
	func hull(id: String) -> Dictionary:
		for h in data.get("HULLS",[]):
			if str(h.get("id",""))==id:return h
		return {}
	func port(id: String) -> Dictionary:
		for p in state.get("ports",[]):
			if str(p.get("id",""))==id:return p
		return {}
	func distance(a: Dictionary,b: Dictionary) -> float:
		return Vector2(float(a.x),float(a.y)).distance_to(Vector2(float(b.x),float(b.y)))
	func cached_path(a: Dictionary,b: Dictionary,clearance: float=10.0) -> Array:
		var actual: float=Navigation.hull_clearance(clearance)
		var key: Array=[float(a.x),float(a.y),float(b.x),float(b.y),actual]
		if not paths.has(key):paths[key]=Navigation.find_path(nav,a,b,actual)
		return paths[key].duplicate(true)

## Cheap roster filter: cargo is not evidence of ownership, captureSecured is.
static func captured_prizes(state: Dictionary) -> Array:
	var out: Array=[]
	var seen: Dictionary={}
	for boat in state.get("fleet",[])+state.get("boardingPrizes",[]):
		if not boat is Dictionary or boat.get("sunk",false) or not boat.get("captureSecured",false):continue
		var uid: String=str(boat.get("uid",""))
		if uid.is_empty() or seen.has(uid):continue
		seen[uid]=true
		out.append(boat)
	return out

static func equipment(owner: Dictionary) -> Array:
	var condition: Dictionary=owner.get("sourceModuleCondition",owner.get("moduleCondition",{}))
	var out: Array=[]
	for item in condition.get("items",{}).values():
		if item is Dictionary:out.append(item.duplicate(true))
	out.sort_custom(func(a,b):return str(a.get("location",""))+str(a.get("itemUid",""))<str(b.get("location",""))+str(b.get("itemUid","")))
	return out

static func part_name(item: Dictionary) -> String:
	if str(item.get("family",""))=="pumps":return "Integral pumps"
	return str(Refits.catalog().get(str(item.get("family","")),{}).get(str(item.get("typeId","")),{}).get("name",str(item.get("typeId","Part")).replace("_"," ").capitalize()))

## Carrier selection remains explicit; this is only a cheap candidate roster.
static func carriers(state: Dictionary) -> Array:
	return Expedition.traveling(state).filter(func(b):return not b.get("supportOnly",false) and float(b.get("hp",0))>0 and b.get("moduleCondition") is Dictionary)

static func _wreck(state: Dictionary,id: String) -> Dictionary:
	for w in state.get("wrecks",[]):
		if str(w.get("id",""))==id:return w
	return {}

static func _legal_at(view,port: Dictionary,day: float) -> bool:
	if port.is_empty():return false
	return bool(Factions.access(view.state,port).get("legal",false)) or float(view.state.get("relationships",{}).get("safeConduct",{}).get(str(port.get("id","")),0))>day

## One real clearance-aware route; work happens before departure. All allowances
## include rounded payroll and a two-day contingency, not a promise of safety.
static func _return(view,work: float,port_id: String="",extra_weight: float=0.0,pending_payroll: int=0) -> Dictionary:
	var speed: float=Expedition._route_speed(view.state,view.data,Expedition.traveling(view.state))
	var ports: Array=view.state.get("ports",[]).duplicate()
	var origin: Dictionary=view.state.get("position",{})
	ports.sort_custom(func(a,b):return view.distance(origin,a)<view.distance(origin,b))
	var harbor: Dictionary={}
	var leg: Dictionary={"ok":false,"distance":0.0,"path":[]}
	var returning: float=0.0
	for p in ports:
		if not port_id.is_empty() and str(p.get("id",""))!=port_id:continue
		if not _legal_at(view,p,float(view.state.get("day",0))+work):continue
		var candidate: Dictionary=Expedition._leg(view,origin,p)
		if not candidate.ok:continue
		var days: float=float(candidate.distance)/maxf(0.01,speed)/Expedition.DAY_SECONDS
		if not _legal_at(view,p,float(view.state.get("day",0))+work+days+2.0):continue
		harbor=p;leg=candidate;returning=days
		break
	# Unsettled earlier days are a payroll/provision liability, not more travel.
	var pending: int=maxi(0,pending_payroll)
	var plan: Dictionary={"outwardDays":0.0,"returnDays":returning,"shoreDays":work+pending,"foodCredit":maxf(0,float(view.state.get("surveyFoodCredit",0)))}
	var accounting: Dictionary=view.state.duplicate()
	accounting.wageArrears=int(view.state.get("wageArrears",0))+FleetSupport.premium(view.state,true)
	var r: Dictionary=Expedition.report(accounting,view.data,float(leg.distance),speed,plan)
	r["accountingDays"]=r.tripDays
	r.tripDays-=pending
	r["pendingPayrollDays"]=pending
	# Selected gear is quoted by A, never copied into an invented live locker here.
	if extra_weight>0:
		r.cargoWeight+=extra_weight
		r.freeCapacity=maxf(0,float(r.usableCapacity)-float(r.cargoWeight))
		r.overload=maxf(0,float(r.cargoWeight)-float(r.usableCapacity))
		r.allowanceOverload=maxf(0,float(r.cargoWeight)+float(r.foodShortfall)*float(Goods.ITEMS.food.weight)-float(r.usableCapacity))
		r.payloadAfterFood=maxf(0,float(r.payloadAfterFood)-extra_weight)
		if r.allowanceOverload>0.001:r.readyForAllowance=false;r.bottleneck="Hold capacity"
	r.merge({"routeOk":not harbor.is_empty() and speed>0,"returnPortId":str(harbor.get("id","")),"returnPortName":str(harbor.get("name","No legal return quoted")),"path":leg.get("path",[]),"workDays":work,"projectionOnly":true,"additionalHoldWeight":extra_weight},true)
	if not r.routeOk:
		r.readyForAllowance=false
		r.bottleneck="No legal return route"
		r.warnings.append("No navigable return to a harbor whose access lasts through work, travel and the two-day contingency.")
	return r

## Prices installed repair through the actual paid-service quote. Its stock and
## labor checks are separate in EquipmentService.repair, so retain them here.
static func _service(view,boat: Dictionary,returning: Dictionary) -> Dictionary:
	var port: Dictionary=view.port(str(returning.get("returnPortId","")))
	var q: Dictionary=Service.service_quote(view,boat,port)
	var blockers: Array=[]
	if not q.get("ok",false):blockers.append(str(q.get("message",q.get("error","Service quote unavailable."))))
	else:
		if not returning.get("routeOk",false):blockers.append("No working return route to this service harbor is quoted.")
		var access: Dictionary=Factions.access(view.state,port)
		if not _legal_at(view,port,float(view.state.get("day",0))+float(returning.get("workDays",0))+float(returning.get("returnDays",0))):blockers.append("Harbor entry is unavailable after this work and return.")
		if int(access.get("claim",0))>0:blockers.append("Settle the outstanding harbor claim before drydock.")
		if not str(boat.get("storedPort","")).is_empty() and str(boat.storedPort)!=str(port.get("id","")):blockers.append("Collect the boat from its actual storage harbor before using this yard.")
		var workforce: Dictionary=Service.workforce_status(port)
		if not workforce.get("ok",false):blockers.append(str(workforce.get("error","Harbor workforce unavailable.")))
		else:
			if (float(q.workerDays)>Service.EPS and floori(float(workforce.get("total",0))+Service.EPS)<1) or float(workforce.get("free",0))+Service.EPS<float(q.workerDays):blockers.append("Not enough available shipwrights today.")
			if (float(q.expertDays)>Service.EPS and floori(float(workforce.get("specialists",0))+Service.EPS)<1) or float(workforce.get("freeExperts",0))+Service.EPS<float(q.expertDays):blockers.append("Not enough mechanics/engineering specialists today.")
		if float(port.get("stocks",{}).get("supplies",-1))+Service.EPS<float(q.purchase):blockers.append("Not enough repair kits in stock today.")
		for good in q.get("equipmentMaterials",{}):
			if float(port.get("stocks",{}).get(good,-1))+Service.EPS<float(q.equipmentMaterials[good]):blockers.append("Not enough %s in stock today."%str(Goods.ITEMS.get(good,{"name":good}).name))
		var reserved: float=float(returning.get("returnWages",0))+float(returning.get("wageArrears",0))
		if float(view.state.get("coins",0))-reserved<float(q.cost):blockers.append("Purse after the work/return payroll allowance cannot cover this service quote.")
	return {"quote":q,"availableNow":q.get("ok",false) and blockers.is_empty(),"blockers":blockers,"portId":str(port.get("id","")),"portName":str(port.get("name","Unselected")),"projectionOnly":true}

## Call only for one focused/explicit selection, never from the overview loop.
## A's recovery_quote owns all transaction eligibility and work accounting.
static func compare(c,wreck_id: String,mode: String="tow",good: String="",qty: float=0.0,request: Dictionary={},return_port_id: String="") -> Dictionary:
	var cache: Dictionary={}
	var view=DetachedView.new(c,c.state.duplicate(true),cache)
	var wreck: Dictionary=_wreck(view.state,wreck_id)
	if wreck.is_empty():return {"ok":false,"message":"No such marked wreck.","quote":{},"before":{},"after":{},"service":{}}
	var q: Dictionary=c.recovery_quote(wreck_id,mode,good,qty,request)
	var before: Dictionary=_return(view,0.0,return_port_id,0.0,int(c.pending_days))
	var result: Dictionary={"ok":bool(q.get("ok",false)),"message":str(q.get("message","")),"wreck":wreck.duplicate(true),"quote":q,"before":before,"after":{},"service":{},"equipment":equipment(wreck)}
	if not q.get("ok",false):return result
	var work: float=float(q.get("workDays",0))
	var extra_weight: float=0.0
	var boat: Dictionary={}
	if mode=="tow":
		if work<=0:work=maxf(1,float(q.get("ordinary",100))/200.0)
		var spec: Dictionary=view.hull(str(wreck.get("hull","")))
		var prepared: Dictionary=Tow.stage(view,view.state,wreck,spec)
		if not prepared.get("ok",false):result.ok=false;result.message=str(prepared.get("message","Tow preview unavailable."));return result
		boat=Lifecycle.materialize(spec,0,prepared,false)
		boat.spec=Refits.effective_spec(spec,boat.get("loadout",{}))
		boat.maxHp=float(q.get("fittedMaxHp",boat.get("maxHp",1)))
		boat.hp=float(q.get("recoveredHp",boat.get("hp",0)))
		boat.mothballed=true;boat.towed=true;boat.towSpeedFactor=float(q.get("towSpeedFactor",0.55));boat.needsHarborRepair=true;boat.supportOnly=true
		view.state.fleet.append(boat)
		view.state.coins=int(view.state.get("coins",0))-int(q.get("total",0))
		# Real tug work reserves these harbor workers before a later service quote.
		var tug_port: Dictionary=view.port(str(q.get("harbor","")))
		if not tug_port.is_empty():
			tug_port.availableWorkers=maxi(0,int(tug_port.get("availableWorkers",0))-3)
			tug_port.availableSpecialists=maxi(0,int(tug_port.get("availableSpecialists",tug_port.get("specialistWorkers",0)))-1)
			tug_port.workers=int(tug_port.get("workers",0))+3
	elif mode=="strip":
		var lots: Dictionary=q.get("items",{})
		# Campaign's quote supplies the clamped finite quantity; do not project
		# more cargo than that quote can actually recover.
		var weight: float=0.0
		for key in lots:
			view.state.cargo[key]=float(view.state.get("cargo",{}).get(key,0))+float(lots[key])
			weight+=float(lots[key])*float(Goods.ITEMS.get(key,{"weight":1}).weight)
		if work<=0:work=c.recovery_days(weight)
	elif mode=="gear":extra_weight=float(q.get("weight",0))
	var after: Dictionary=_return(view,work,return_port_id,extra_weight,int(c.pending_days))
	result.after=after
	if not boat.is_empty():result.service=_service(view,boat,after)
	return result

## An already-owned prize is never quoted as an unclaimed hull or disposed here.
static func prize(c,uid: String,return_port_id: String="") -> Dictionary:
	var view=DetachedView.new(c,c.state.duplicate(true),{})
	for boat in captured_prizes(view.state):
		if str(boat.get("uid",""))!=uid:continue
		var back: Dictionary=_return(view,0.0,return_port_id,0.0,int(c.pending_days))
		return {"ok":true,"boat":boat,"equipment":equipment(boat),"return":back,"service":_service(view,boat,back)}
	return {"ok":false,"message":"That secured prize is no longer in your roster."}
