extends RefCounted
## Fishing is explicit wild-resource production, never the shore food recipe.
## One 500-map-unit water cell supplies at most 40 preserved lots per calendar day.
## Crew catch, clean and preserve aboard; the sum of the existing fish labor
## coefficients bounds their output. Only elapsed Campaign.step time earns work.
const Goods=preload("res://scripts/goods.gd")
const Transport=preload("res://scripts/passenger_transport.gd")
const Jobs=preload("res://scripts/voyage_jobs.gd")
const Manifest=preload("res://scripts/hold_manifest.gd")
const Navigation=preload("res://scripts/navigation.gd")
const Expedition=preload("res://scripts/expedition.gd")
const SITE_SIZE: float=500.0
const SITE_QUOTA: float=40.0
const MAX_SITES: int=128
const EPS: float=0.000001

static func ensure(c) -> Dictionary:
	if not c.state.has("civilianWork"):
		c.state.civilianWork={"schema":36,"fishing":[],"resourceDay":floori(float(c.state.day)),"sites":{},"wildFishCreated":0.0}
	return c.state.civilianWork

static func site_id(position: Dictionary) -> String:
	return "%d:%d"%[floori(float(position.x)/SITE_SIZE),floori(float(position.y)/SITE_SIZE)]

static func catch_rate() -> float:
	var days: float=0.0
	for value in Goods.ITEMS.preserved_fish.labor.values():days+=float(value)
	return 1.0/maxf(0.1,days)

static func fuel_rate(b: Dictionary) -> float:
	return 45.0*(0.011+float(b.spec.size)*0.0002)*maxf(0.2,float(b.spec.get("fuelUse",1.0)))

static func _active(c,uid: String) -> Dictionary:
	for b in c.active_fleet():
		if str(b.uid)==uid:return b
	return {}

static func _fishing_hold(c,b: Dictionary) -> float:
	# Keep preview, gear setting and elapsed production on the same 058 mass
	# contract. Transport's older display read omits lockers/captive overflow.
	var captives: float=maxf(0,float(c.state.get("captiveBerths",{}).get(str(b.uid),0))-maxf(0,float(b.crewMax)-float(b.crew)))
	return maxf(0,Transport.available_hold(c,b)-Expedition.locker_weight(b)-captives)

## Detached current-ground upper bound. Never calls ensure or earns work.
## The horizon is elapsed time; an assignment's daysTotal counts working time.
static func fishing_quote(c,boat_uid: String,days: float=1.0,crew: int=0) -> Dictionary:
	var now: float=float(c.state.day)
	var day: int=floori(now)
	var site: String=site_id(c.state.position)
	var book: Dictionary=c.state.get("civilianWork",{})
	var remaining: float=maxf(0,SITE_QUOTA-float(book.get("sites",{}).get(site,0))) if int(book.get("resourceDay",-1))==day else SITE_QUOTA
	var q: Dictionary={"ok":false,"message":"","boatUid":boat_uid,"requestedDays":days,"crew":0,"day":now,"calendarDay":day,"siteId":site,
		"quotaDaily":SITE_QUOTA,"quotaRemaining":remaining,"quotaInHorizon":0.0,"catchRate":0.0,"catchMax":0.0,"sellableLots":0,
		"workingDays":0.0,"timeToFillDays":-1.0,"holdFree":0.0,"fleetHoldFree":0.0,"fuelLoaded":0.0,"foodLoaded":maxf(0,float(c.state.cargo.food)),
		"fuelPerDay":0.0,"foodPerDay":0.0,"fuelNeeded":0.0,"foodNeeded":0.0,"limitingCause":"","limits":[]}
	if not is_finite(days) or days<=0 or days>7:return _quote_refusal(q,"duration","Choose more than zero and at most seven fishing days.")
	var b: Dictionary=_active(c,boat_uid)
	if b.is_empty() or str(c.hull(str(b.type)).get("civilianRole",""))!="fishing":return _quote_refusal(q,"ineligible","Choose a working, crewed fishing hull in the traveling fleet.")
	var workers: int=int(b.crew) if crew==0 else crew
	q.crew=workers;q.fuelLoaded=maxf(0,float(b.fuel));q.fuelPerDay=fuel_rate(b)
	if workers<=0 or workers>int(b.crew):return _quote_refusal(q,"crew","Assign existing living sailors to the fishing work.")
	q.catchRate=float(workers)*catch_rate();q.foodPerDay=float(workers)*0.08
	q.holdFree=_fishing_hold(c,b)
	q.fleetHoldFree=maxf(0,c.capacity()-c.cargo_weight())
	var room: float=minf(float(q.holdFree),float(q.fleetHoldFree))
	if not c.current_port().is_empty() or not c.state.path.is_empty() or not Navigation.is_water(c.nav,c.state.position.x,c.state.position.y,maxf(10,float(b.spec.size))):return _quote_refusal(q,"location","Stop in safe open water before setting fishing gear.")
	if not c.state.get("exploration",{}).get("assignment",{}).is_empty() or not c.state.get("toolingRecovery",{}).is_empty() or book.get("fishing",[]).any(func(j):return str(j.boatUid)==boat_uid) or book.get("fishing",[]).size()>=48:return _quote_refusal(q,"assignment","Recall the assigned work party or existing gear before fishing.")
	if float(q.fuelLoaded)<=EPS:return _quote_refusal(q,"fuel","Fishing needs real working engine fuel.")
	if float(q.foodLoaded)<=EPS:return _quote_refusal(q,"food","Fishing needs real crew rations.")
	if room<=EPS:return _quote_refusal(q,"hold","The selected fishing boat and fleet need free physical hold space.")
	if remaining<=EPS:return _quote_refusal(q,"quota","This water cell's finite fish quota is exhausted for today.")
	if int(book.get("resourceDay",-1))==day and not book.get("sites",{}).has(site) and book.get("sites",{}).size()>=MAX_SITES:return _quote_refusal(q,"sites","Today's bounded fishing-ground ledger is full.")
	var rate: float=float(q.catchRate)
	var fuel_days: float=float(q.fuelLoaded)/float(q.fuelPerDay)
	var food_days: float=float(q.foodLoaded)/float(q.foodPerDay)
	# Loaded rations disappear as they are eaten. Only fuel ABOVE this boat's
	# real tank frees hold as it burns. This bounds that actual released mass;
	# shared food may be on another hull, so it is an upper bound, not a promise.
	var net_rate: float=maxf(EPS,rate-float(q.foodPerDay))
	var overflow: float=maxf(0,float(q.fuelLoaded)-float(b.spec.get("fuelCapacity",60)))
	var overflow_days: float=overflow/float(q.fuelPerDay)
	var first_fill: float=room/maxf(EPS,net_rate-float(q.fuelPerDay))
	var hold_days: float=first_fill if first_fill<=overflow_days else (room+overflow)/net_rate
	var work_left: float=minf(days,minf(hold_days,minf(fuel_days,food_days)))
	var cursor: float=now
	var end: float=now+days
	# At most eight calendar segments for a <=7-day quote, never per-frame work.
	while cursor<end-EPS:
		var segment_end: float=minf(end,float(floori(cursor)+1))
		var quota: float=remaining if floori(cursor)==day else SITE_QUOTA
		q.quotaInHorizon=float(q.quotaInHorizon)+quota
		var work: float=minf(work_left,minf(segment_end-cursor,quota/rate))
		q.workingDays=float(q.workingDays)+work;work_left=maxf(0,work_left-work)
		q.catchMax=float(q.catchMax)+work*rate
		if float(q.timeToFillDays)<0 and float(q.workingDays)>=hold_days-EPS:q.timeToFillDays=cursor-now+work
		cursor=segment_end
	q.fuelNeeded=float(q.workingDays)*float(q.fuelPerDay)
	q.foodNeeded=float(q.workingDays)*float(q.foodPerDay)
	q.sellableLots=floori(float(q.catchMax)+EPS)
	var bound: float=float(q.workingDays)
	if hold_days<=bound+EPS:q.limits.append("hold")
	if fuel_days<=bound+EPS:q.limits.append("fuel")
	if food_days<=bound+EPS:q.limits.append("food")
	if bound+EPS<minf(days,minf(hold_days,minf(fuel_days,food_days))):q.limits.append("quota")
	if q.limits.is_empty():q.limits.append("duration")
	q.limitingCause=str(q.limits[0]);q.ok=true
	q.message="Current-ground upper bound; other boats share its quota. Sales, outward/return stores and calendar payroll are separate."
	return q

static func _quote_refusal(q: Dictionary,cause: String,message: String) -> Dictionary:
	q.limitingCause=cause;q.limits=[cause];q.message=message
	return q

static func start_fishing(c,boat_uid: String,days: float=1.0,crew: int=0) -> Dictionary:
	if not is_finite(days) or days<=0 or days>7:return c.fail("Choose more than zero and at most seven fishing days.")
	var b: Dictionary=_active(c,boat_uid)
	if b.is_empty() or str(c.hull(str(b.type)).get("civilianRole",""))!="fishing":return c.fail("Choose a working, crewed fishing hull in the traveling fleet.")
	if not c.current_port().is_empty() or not c.state.path.is_empty():return c.fail("Stop in open water before setting fishing gear; no dockside catch.")
	if not Navigation.is_water(c.nav,c.state.position.x,c.state.position.y,maxf(10,float(b.spec.size))):return c.fail("This hull needs safe open water to fish.")
	if not c.state.get("exploration",{}).get("assignment",{}).is_empty() or not c.state.get("toolingRecovery",{}).is_empty():return c.fail("Recall the assigned work party before fishing.")
	var workers: int=int(b.crew) if crew==0 else crew
	if workers<=0 or workers>int(b.crew):return c.fail("Assign existing living sailors to the fishing work.")
	if float(b.fuel)<=0 or float(c.state.cargo.food)<=0:return c.fail("Fishing needs real working fuel and crew rations.")
	if minf(_fishing_hold(c,b),c.capacity()-c.cargo_weight())<=EPS:return c.fail("The fishing boat needs free hold space.")
	var book: Dictionary=ensure(c)
	if book.fishing.any(func(j):return str(j.boatUid)==boat_uid):return c.fail("That boat already has its gear set.")
	if book.fishing.size()>=48:return c.fail("All traveling fishing assignments are occupied.")
	var site: String=site_id(c.state.position)
	var day: int=floori(float(c.state.day))
	if int(book.resourceDay)==day and float(book.sites.get(site,0))>=SITE_QUOTA-EPS:return c.fail("This water cell's finite fish quota is exhausted for today.")
	var job: Dictionary={"boatUid":boat_uid,"siteId":site,"crew":workers,"daysTotal":days,"daysDone":0.0,"catch":0.0,"lastDay":float(c.state.day)}
	book.fishing.append(job)
	c.log_entry("%s set gear: %d sailors, %.2f days; wild fish limit %.0f lots per water cell/day."%[b.name,workers,days,SITE_QUOTA])
	return {"ok":true,"message":"Gear set. Existing campaign time now advances the catch.","job":job.duplicate(true)}

static func cancel_fishing(c,boat_uid: String) -> Dictionary:
	for j in c.state.get("civilianWork",{}).get("fishing",[]):
		if str(j.boatUid)==boat_uid:
			c.state.civilianWork.fishing.erase(j)
			return c.ok("Gear recovered; the actual catch and consumed stores remain accounted for.")
	return c.fail("That boat has no active fishing assignment.")

static func fishing_status(c) -> Array:
	return c.state.get("civilianWork",{}).get("fishing",[]).duplicate(true)

static func tick(c,dt_days: float) -> void:
	Jobs.tick(c,dt_days)
	if not is_finite(dt_days) or dt_days<=0 or not c.state.has("civilianWork"):return
	var book: Dictionary=c.state.civilianWork
	for j in book.fishing.duplicate():
		var b: Dictionary=_active(c,str(j.boatUid))
		var now: float=float(c.state.day)
		var begin: float=maxf(float(j.lastDay),now-dt_days)
		j.lastDay=now # A paused/invalid interval is never banked as later work.
		if b.is_empty() or int(b.crew)<int(j.crew) or not c.current_port().is_empty() or not c.state.path.is_empty() or site_id(c.state.position)!=str(j.siteId) or not c.state.get("exploration",{}).get("assignment",{}).is_empty() or not c.state.get("toolingRecovery",{}).is_empty():
			book.fishing.erase(j);c.log_entry("Fishing stopped: the actual carrier, work party or water cell changed.");continue
		while begin<now-EPS and float(j.daysDone)<float(j.daysTotal)-EPS:
			var day: int=floori(begin)
			if day<int(book.resourceDay):break
			if day>int(book.resourceDay):book.resourceDay=day;book.sites={}
			if not book.sites.has(j.siteId) and book.sites.size()>=MAX_SITES:break
			var left: float=maxf(0,SITE_QUOTA-float(book.sites.get(j.siteId,0)))
			var rate: float=float(j.crew)*catch_rate()
			var food_rate: float=float(j.crew)*0.08
			var room: float=minf(_fishing_hold(c,b),c.capacity()-c.cargo_weight())
			var work: float=minf(now-begin,minf(float(day+1)-begin,float(j.daysTotal)-float(j.daysDone)))
			work=minf(work,minf(left/rate,maxf(0,room)/rate))
			work=minf(work,minf(float(b.fuel)/fuel_rate(b),float(c.state.cargo.food)/food_rate))
			if work<=EPS:break
			var produced: float=work*rate
			b.fuel=maxf(0,float(b.fuel)-work*fuel_rate(b))
			c.state.cargo.food=maxf(0,float(c.state.cargo.food)-work*food_rate)
			# The normal daily ration charge credits this already consumed crew food.
			c.state.surveyFoodCredit=float(c.state.get("surveyFoodCredit",0))+work*food_rate
			c.state.cargo.preserved_fish=float(c.state.cargo.get("preserved_fish",0))+produced
			book.sites[j.siteId]=float(book.sites.get(j.siteId,0))+produced
			book.wildFishCreated=float(book.wildFishCreated)+produced
			j.catch=float(j.catch)+produced;j.daysDone=float(j.daysDone)+work
			begin+=work
			Manifest.allocate(c.state)
			if work<EPS:break
		if float(j.daysDone)>=float(j.daysTotal)-EPS or float(b.fuel)<=EPS or float(c.state.cargo.food)<=EPS:
			book.fishing.erase(j);c.log_entry("%s recovered %.2f preserved fish lots from wild stock in %.2f working days."%[b.name,j.catch,j.daysDone])

static func validate(s: Dictionary,world: Dictionary) -> String:
	if not s.has("civilianWork"):return ""
	var book=s.civilianWork
	if not book is Dictionary or book.get("schema")!=36 or not book.get("fishing") is Array or book.fishing.size()>48 or not book.get("sites") is Dictionary or book.sites.size()>MAX_SITES:return "Invalid civilian fishing ledger."
	if not Jobs._is_num(book.get("resourceDay")) or floorf(float(book.resourceDay))!=float(book.resourceDay) or float(book.resourceDay)<0 or float(book.resourceDay)>floorf(float(s.day)) or not Jobs._is_num(book.get("wildFishCreated")) or float(book.wildFishCreated)<0:return "Invalid wild-resource production date/quantity."
	for id in book.sites:
		if not id is String or id.split(":").size()!=2 or not Jobs._is_num(book.sites[id]) or float(book.sites[id])<0 or float(book.sites[id])>SITE_QUOTA+EPS:return "Invalid site/day fishing quota."
	var ids: Dictionary={}
	for j in book.fishing:
		if not j is Dictionary or not j.get("boatUid") is String or ids.has(j.boatUid) or not j.get("siteId") is String:return "Invalid fishing assignment."
		ids[j.boatUid]=true
		var found: Dictionary={}
		for b in s.fleet:
			if b.uid==j.boatUid:found=b;break
		if found.is_empty() or not Manifest.carriers(s).has(found) or not world.HULLS.any(func(h):return h.id==found.type and h.get("civilianRole","")=="fishing"):return "Fishing carrier is absent or ineligible."
		for key in ["crew","daysTotal","daysDone","catch","lastDay"]:
			if not Jobs._is_num(j.get(key)) or float(j[key])<0:return "Invalid fishing work accounting."
		if int(j.crew)!=float(j.crew) or j.crew<1 or j.crew>found.crew or j.daysTotal<=0 or j.daysTotal>7 or j.daysDone>j.daysTotal+EPS or j.lastDay>s.day or j.catch>float(j.crew)*catch_rate()*float(j.daysDone)+EPS:return "Unearned fishing work or invalid crew."
	return ""
