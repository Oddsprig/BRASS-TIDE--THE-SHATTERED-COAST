extends RefCounted
## Glasswind glue over the one campaign, exploration book, wrecks and manifest.
## Views/guards read raw data. Work uses the live Core clock and daily settlement.
const Exploration=preload("res://scripts/exploration.gd")
const Expedition=preload("res://scripts/expedition.gd")
const Salvage=preload("res://scripts/salvage.gd")
const Goods=preload("res://scripts/goods.gd")
const REGION: String="glasswind_keys"
const SITE_IDS: Array=Salvage.EXPEDITION067_SITES
const SOURCE: String=Salvage.EXPEDITION067_SOURCE

static func number(value,low: float=0.0,high: float=INF) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func identity(record: Dictionary) -> Dictionary:
	if not record.has("world064"):return {"schema":1,"layer":"home","regionId":"shatter_coast"}
	var world=record.get("world064")
	if not world is Dictionary or world.size()!=3 or not number(world.get("schema"),1,1):return {}
	if not world.get("layer") is String or not world.get("regionId") is String:return {}
	var pair: String=str(world.layer)+"/"+str(world.regionId)
	return world.duplicate(true) if pair in ["home/shatter_coast","local/glasswind_keys","ocean/open_ocean"] else {}

static func same_world(a: Dictionary,b: Dictionary) -> bool:
	var left: Dictionary=identity(a)
	var right: Dictionary=identity(b)
	return not left.is_empty() and not right.is_empty() and left.layer==right.layer and left.regionId==right.regionId

static func local(state: Dictionary) -> bool:
	var world: Dictionary=identity(state)
	return not world.is_empty() and world.layer=="local" and world.regionId==REGION

static func all_surveyed(state: Dictionary) -> bool:
	var ex=state.get("exploration",{})
	if not ex is Dictionary or not ex.get("sites",{}) is Dictionary:return false
	for id in SITE_IDS:
		var progress=ex.sites.get(id,{})
		if not progress is Dictionary or not number(progress.get("level"),3,3) or progress.get("rewarded")!=true:return false
	return true

static func raw_wreck(state: Dictionary,id: String) -> Dictionary:
	var found: Dictionary={}
	if not state.get("wrecks",[]) is Array:return {}
	for row in state.get("wrecks",[]):
		if row is Dictionary and row.get("id")==id:
			if not found.is_empty():return {}
			found=row
	return found

static func cargo_only(wreck: Dictionary) -> bool:
	return wreck.get("sourceId")==SOURCE

static func spare_crew(state: Dictionary) -> int:
	var spare: int=0
	for boat in Expedition.traveling(state):
		spare+=maxi(0,floori(float(boat.get("crew",0)))-ceili(float(boat.get("wounded",0)))-int(boat.get("crewMin",1))-int(boat.get("shoreCrew",0)))
	return spare

## Saved remote hands must still be able members of their original working boat.
## This never ensures/migrates and therefore cannot repair a refused save.
static func party_error(state: Dictionary) -> String:
	var ex=state.get("exploration",{})
	if not ex is Dictionary or not ex.get("assignment",{}) is Dictionary:return "Invalid regional shore assignment."
	var assignment: Dictionary=ex.get("assignment",{})
	var remote: bool=local(state) or identity(assignment).get("regionId")==REGION or str(assignment.get("siteId","")) in SITE_IDS
	if not remote:return ""
	var reserved: int=0
	if not state.get("fleet",[]) is Array:return "Invalid regional party fleet."
	for boat in state.get("fleet",[]):
		if not boat is Dictionary or not number(boat.get("shoreCrew",0)) or floorf(float(boat.get("shoreCrew",0)))!=float(boat.get("shoreCrew",0)):return "Invalid regional shore sailors."
		var ashore: int=int(boat.get("shoreCrew",0))
		if ashore>0:
			if boat.get("sunk",false) or boat.get("mothballed",false) or boat.get("needsHarborRepair",false) or not str(boat.get("storedPort","")).is_empty():return "Regional shore sailors need their working physical boat."
			if not number(boat.get("crew")) or not number(boat.get("wounded",0)) or not number(boat.get("crewMin")):return "Invalid regional boat crew."
			if ashore>floori(float(boat.crew))-ceili(float(boat.get("wounded",0)))-int(boat.crewMin):return "Regional shore sailors exceed the boat's able spare hands."
		reserved+=ashore
	var credit=state.get("surveyFoodCredit",0)
	if not number(credit,0,1000):return "Invalid regional prepaid rations."
	if assignment.is_empty():
		# Legacy066 may carry unused HOME ration credit after a completed party.
		# It remains the same finite food account, even on a later remote voyage.
		return "Regional shore sailors have no assignment." if reserved>0 else ""
	if not local(state) or not assignment.has("world064") or not same_world(state,assignment):return "Regional shore party does not match the current local chart."
	if not str(assignment.get("siteId","")) in SITE_IDS:return "Regional shore party needs an authored landing."
	if not state.get("path",[]) is Array or not state.get("path",[]).is_empty():return "A deployed regional shore party must remain stopped."
	var site: Dictionary={}
	for row in ex.get("catalog",[]):
		if row is Dictionary and row.get("id")==assignment.siteId:site=row;break
	var position=state.get("position",{})
	if site.is_empty() or site.get("regionId")!=REGION or not position is Dictionary:return "Regional shore party has no matching landing."
	for point in [position,site]:
		if not number(point.get("x")) or not number(point.get("y")):return "Regional shore party has no finite landing."
	if Vector2(float(position.x)-float(site.x),float(position.y)-float(site.y)).length()>180.000001:return "Regional shore party is beyond its landing."
	var needed: int=2 if assignment.get("action")=="chart" else 4
	if assignment.get("action") not in ["chart","survey"] or not number(assignment.get("crewReserved"),needed,needed) or reserved!=needed:return "Regional party reservation does not match actual sailors."
	for key in ["daysTotal","daysDone","foodSpent","suppliesSpent","targetLevel"]:
		if not number(assignment.get(key),0,1000):return "Invalid regional survey accounting."
	var target: int=2 if needed==2 else 3
	if float(assignment.daysTotal)<=0 or float(assignment.daysDone)>=float(assignment.daysTotal) or float(assignment.targetLevel)!=target:return "Invalid regional survey progress."
	if float(assignment.suppliesSpent)!=(1.0 if needed==2 else 2.0) or float(credit)>float(assignment.foodSpent)+0.0000001:return "Regional survey stores do not reconcile."
	var prepaid: float=snappedf(Exploration.FOOD_PER_CREW_DAY*needed*float(assignment.daysTotal),0.01)
	if absf(float(assignment.foodSpent)-prepaid)>0.0000001:return "Regional survey ration commitment does not reconcile."
	return ""

static func validate_saved(state: Dictionary) -> String:
	var party: String=party_error(state)
	if not party.is_empty():return party
	return Salvage.validate_expedition067(state)

static func view(core) -> Dictionary:
	var state: Dictionary=core.state
	var world: Dictionary=identity(state)
	var sites: Array=Exploration.visible_sites(state)
	var summary: Dictionary={"regionId":str(world.get("regionId","")),"totalSites":3 if local(state) else sites.size(),"sighted":0,"charted":0,"surveyed":0,"cargoOnlyAvailable":false,"message":"Observe landings, chart them and assign paid shore surveys."}
	for site in sites:
		if int(site.get("level",0))>=1:summary.sighted+=1
		if int(site.get("level",0))>=2:summary.charted+=1
		if int(site.get("level",0))>=3:summary.surveyed+=1
	var wrecks: Array=[]
	for wreck in state.get("wrecks",[]):
		if not same_world(state,wreck) or wreck.get("status","")!="unclaimed":continue
		if cargo_only(wreck) and (not all_surveyed(state) or not Salvage.validate_expedition067(state).is_empty()):continue
		wrecks.append({"id":str(wreck.id),"name":str(wreck.get("name","Marked wreck")),"x":float(wreck.x),"y":float(wreck.y),"world064":identity(wreck),"status":str(wreck.status),"cargoOnly":cargo_only(wreck)})
		if cargo_only(wreck):summary.cargoOnlyAvailable=true
	var assignment: Dictionary=state.get("exploration",{}).get("assignment",{})
	if not assignment.is_empty() and not same_world(state,assignment):assignment={}
	if world.is_empty() or world.get("layer")=="ocean":sites=[];wrecks=[];assignment={}
	return {"world064":world,"sites":sites,"wrecks":wrecks,"assignment":assignment.duplicate(true),"summary":summary}

static func work_blocker(core) -> String:
	if not core.travel_lock064.is_empty():return core.travel_lock064
	if core.events.any(func(event):return str(event.get("kind","")) in ["encounter","ocean_encounter066","defeat"]):return "Resolve the pending encounter before landing a work party."
	return core.OceanCampaign066.blocker(core)

static func survey_begin(core,site_id: String,action: String) -> Dictionary:
	if not local(core.state):return core.fail("Choose a landing on the current local chart.")
	var prior_error: String=party_error(core.state)
	if not prior_error.is_empty():return core.fail(prior_error)
	var visible: Dictionary={}
	for row in Exploration.visible_sites(core.state):
		if row.id==site_id:visible=row;break
	if visible.is_empty():return core.fail("Observe a landing on this chart before assigning a shore party.")
	var blocked: String=work_blocker(core)
	if not blocked.is_empty():return core.fail(blocked)
	if not core.state.get("path",[]).is_empty() or core.distance(core.state.position,visible)>180:return core.fail("Stop within180water units of this landing first.")
	if not core.state.get("toolingRecovery",{}).is_empty() or core.state.fleet.any(func(b):return int(b.get("shoreCrew",0))>0):return core.fail("Recall the existing work party before assigning more hands.")
	var staged: Dictionary=core.state.duplicate(true)
	core.Preflight._clone_boats(core.state,staged)
	if staged.get("exploration",{}).get("assignment",{}).is_empty():
		staged.cargo.food=float(staged.cargo.get("food",0))+float(staged.get("surveyFoodCredit",0))
		staged["surveyFoodCredit"]=0.0
	var result: Dictionary=Exploration.begin(staged,site_id,action)
	if not result.get("ok",false):return result
	staged.exploration.assignment["world064"]={"schema":1,"layer":"local","regionId":REGION}
	staged["surveyFoodCredit"]=float(staged.get("surveyFoodCredit",0))+float(result.food)
	var left: int=int(result.crewNeeded)
	for boat in Expedition.traveling(staged):
		var assigned: int=mini(left,maxi(0,floori(float(boat.crew))-ceili(float(boat.wounded))-int(boat.crewMin)-int(boat.get("shoreCrew",0))))
		boat["shoreCrew"]=int(boat.get("shoreCrew",0))+assigned
		left-=assigned
	var error: String=party_error(staged)
	if left!=0 or not error.is_empty():return core.fail(error if not error.is_empty() else "The actual working boats cannot reserve those sailors.")
	core.Manifest.allocate(staged)
	if core.Expedition.cargo_weight(staged)>core.Expedition.capacity(staged)+0.0000001 or not staged.cargoManifest.get("unassigned",{}).is_empty():return core.fail("The returned rations and remaining cargo need actual room on the working boats.")
	core.state=staged
	result["assignment"]=staged.exploration.assignment.duplicate(true)
	core.log_entry("Landed %d sailors at %s; normal wages continue."%[int(result.crewNeeded),str(result.siteName)])
	return result

static func recovery_gate(core,snapshot: Dictionary,id: String,mode: String) -> String:
	var wreck: Dictionary=raw_wreck(snapshot,id)
	if not local(snapshot) or not cargo_only(wreck) or not same_world(snapshot,wreck) or not all_surveyed(snapshot):return "Choose a surveyed cargo cache on the current local chart."
	var raw_error: String=validate_saved(snapshot)
	if not raw_error.is_empty():return raw_error
	if mode!="strip":return "This collapsed cargo cache offers finite stores only."
	var blocked: String=work_blocker(core)
	if not blocked.is_empty():return blocked
	var hazard_id: String=str(snapshot.get("wreckHazards",{}).get(wreck.get("sourceId",""),""))
	for owner in snapshot.get("fleetOwners",[]):
		if str(owner.get("id",""))==hazard_id and owner.get("active",false) and owner.get("boats",[]).any(func(boat):return not boat.get("sunk",false)):return "Hostiles still control this cache. Secure the waters before recovery."
	if not snapshot.get("path",[]).is_empty() or not snapshot.get("exploration",{}).get("assignment",{}).is_empty() or not snapshot.get("toolingRecovery",{}).is_empty() or snapshot.fleet.any(func(b):return int(b.get("shoreCrew",0))>0):return "Stop the fleet and recall every work party before recovery."
	if core.distance(snapshot.position,wreck)>180:return "Approach the surveyed cache within180water units first."
	if spare_crew(snapshot)<1:return "Cargo recovery needs an able spare sailor above the working boat minimums."
	return ""

static func kits(state: Dictionary) -> float:
	var count: float=maxf(0,float(state.get("cargo",{}).get("supplies",0)))
	for boat in Expedition.traveling(state):count+=maxf(0,float(boat.get("supplies",0)))
	return count

static func quote(core,id: String,mode: String,good: String,qty: float) -> Dictionary:
	var q: Dictionary={"ok":false,"message":"Choose an explicit finite cargo lot.","wreckId":id,"mode":mode,"cargoOnly":true,"availableItems":{},"items":{},"weight":0.0,"quantity":0.0,"freeCapacity":0.0}
	var blocked: String=recovery_gate(core,core.state,id,mode)
	# Knowledge/world refusal returns no source name, quantities or stores.
	if not blocked.is_empty():q.message=blocked;return q
	var wreck: Dictionary=raw_wreck(core.state,id)
	q.availableItems=Salvage._strip_items(wreck)
	q.freeCapacity=maxf(0,core.capacity()-core.cargo_weight())
	q.spareCrew=spare_crew(core.state)
	q.kitsAvailable=kits(core.state)
	if wreck.get("status")!="unclaimed":q.message="This cargo cache is depleted.";return q
	if not Goods.ITEMS.has(good) or not is_finite(qty) or qty<=0 or qty>float(q.availableItems.get(good,0)):return q
	q.items={good:qty};q.quantity=qty;q.weight=qty*float(Goods.ITEMS[good].weight)
	var effort: float=maxf(core.recovery_days(float(q.weight)),float(q.weight)/maxf(1,int(q.spareCrew)*20.0))
	q.effortDays=effort;q.workDays=maxf(1,ceilf(effort));q.kitsRequired=q.workDays
	q.payrollDays=maxi(0,int(core.pending_days))+int(q.workDays)
	var upkeep: Dictionary=core.Economy.daily_upkeep(core.state.fleet)
	q.wages=(int(upkeep.wages)+core.FleetSupport.premium(core.state))*int(q.payrollDays)
	q.arrears=int(core.state.get("wageArrears",0))+core.FleetSupport.premium(core.state,true)
	q.food=maxf(0,float(upkeep.food)*int(q.payrollDays)-float(core.state.get("surveyFoodCredit",0)))
	q.coinsRequired=int(q.wages)+int(q.arrears)
	if not Salvage._tow_ledger(core.state):q.message="The world payroll accounts do not reconcile."
	elif q.weight>q.freeCapacity+0.0000001:q.message="Choose a smaller lot that fits the actual traveling holds."
	elif int(core.state.coins)<int(q.coinsRequired):q.message="Cargo work needs %d actual coins for wages and arrears."%int(q.coinsRequired)
	elif float(core.state.cargo.get("food",0))+0.0000001<float(q.food):q.message="Cargo work needs %.2f actual food."%float(q.food)
	elif float(q.kitsAvailable)<float(q.kitsRequired):q.message="Cargo work needs %.0f actual supply kits, one per working day."%float(q.kitsRequired)
	else:q.ok=true;q.message="Recover %.2f %s: %.0f working days, %.0f kits; normal wages and food continue."%[qty,good,float(q.workDays),float(q.kitsRequired)]
	return q

static func spend_kit(core) -> bool:
	if kits(core.state)<1.0:return false
	var left: float=1.0
	var cargo_use: float=minf(left,maxf(0,float(core.state.cargo.get("supplies",0))))
	core.state.cargo.supplies=float(core.state.cargo.get("supplies",0))-cargo_use
	left-=cargo_use
	for boat in Expedition.traveling(core.state):
		var used: float=minf(left,maxf(0,float(boat.get("supplies",0))))
		boat.supplies=float(boat.get("supplies",0))-used;left-=used
		if left<=0.0000001:break
	core.Manifest.allocate(core.state)
	return true

static func settle_pending(core,receipt: Dictionary) -> void:
	while int(core.pending_days)>0:
		core.pending_days-=1
		var paid: Dictionary=core._settle_recovery_economy(1,false)
		for key in ["wagesPaid","foodConsumed","foodCreditUsed"]:receipt[key]+=paid.get(key,0)

static func recover(core,id: String,good: String,qty: float) -> Dictionary:
	var q: Dictionary=quote(core,id,"strip",good,qty)
	if not q.ok:return q
	q["completed"]=false;q["elapsedDays"]=0.0;q["kitsConsumed"]=0.0
	q["wagesPaid"]=0;q["foodConsumed"]=0.0;q["foodCreditUsed"]=0.0
	var start: float=float(core.state.day)
	# From here costs/time are actual. Interrupted work never rewinds a voyage.
	var arrears: int=int(core.state.get("wageArrears",0))
	if arrears>0:
		core.Money.move(core.state,"coins",core.state,"crewPurse",arrears,"Captain settles unpaid wages before cargo work",core.state.moneyLog)
		core.state.wageArrears=0;q.wagesPaid+=arrears
	settle_pending(core,q)
	var completed: bool=true
	for _workday in range(int(q.workDays)):
		if not recovery_gate(core,core.state,id,"strip").is_empty() or not spend_kit(core):completed=false;break
		q.kitsConsumed+=1.0
		var remaining: float=core.DAY_SECONDS
		var day_goal: float=start+float(_workday)+1.0
		while remaining>0.0000001:
			var before: float=float(core.state.day)
			core.step(minf(4.0,remaining))
			var accepted: float=(float(core.state.day)-before)*core.DAY_SECONDS
			remaining=maxf(0,remaining-accepted)
			settle_pending(core,q)
			if accepted<=0.00000001 or not recovery_gate(core,core.state,id,"strip").is_empty():completed=false;break
		if not completed:break
		# Floating accumulation can stop a few ulps below an exact payroll day.
		# Finish that real interval through Core.step as well, never a clock edit.
		if float(core.state.day)<day_goal:
			core.step(maxf(0.000001,(day_goal-float(core.state.day))*core.DAY_SECONDS))
			settle_pending(core,q)
			if not recovery_gate(core,core.state,id,"strip").is_empty():completed=false;break
	q.elapsedDays=float(core.state.day)-start
	q.dayAfter=float(core.state.day);q.coinsAfter=int(core.state.coins);q.foodAfter=float(core.state.cargo.food)
	if not completed:
		q.ok=false;q.message="Cargo work interrupted. Actual elapsed time, kits and payroll remain spent; no cache goods were loaded."
		return q
	# Stage only the final source debit, goods and existing physical manifest.
	# The completed clock/economy is never replaced by an older snapshot.
	# Work has already paid its allowance: only final locality/source/hold matter.
	var source: Dictionary=raw_wreck(core.state,id)
	if not recovery_gate(core,core.state,id,"strip").is_empty() or qty>float(source.get("stores",{}).get(good,0)) or float(q.weight)>maxf(0,core.capacity()-core.cargo_weight())+0.0000001:
		q.ok=false;q.message="Cargo work finished but the source or physical hold changed; no cache goods were loaded.";return q
	var staged: Dictionary=core.state.duplicate(true)
	var wreck: Dictionary=raw_wreck(staged,id)
	wreck.stores[good]=float(wreck.stores.get(good,0))-qty
	staged.cargo[good]=float(staged.cargo.get(good,0))+qty
	if Salvage._strip_items(wreck).is_empty():wreck.status="stripped";wreck.claimedMode="strip"
	core.Manifest.allocate(staged)
	if not staged.cargoManifest.get("unassigned",{}).is_empty():q.ok=false;q.message="Cargo work finished but no physical carrier can hold the selected lot.";return q
	core.state.cargo=staged.cargo
	core.state.wrecks=staged.wrecks
	core.state.cargoManifest=staged.cargoManifest
	q.completed=true;q.ok=true
	q.message="Recovered %.2f %s after %.0f paid working days; remaining stores stay on the marked cache."%[qty,good,float(q.workDays)]
	core.log_entry(q.message)
	return q
