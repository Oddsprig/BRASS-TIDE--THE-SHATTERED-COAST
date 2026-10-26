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
	if minf(Transport.available_hold(c,b),c.capacity()-c.cargo_weight())<=EPS:return c.fail("The fishing boat needs free hold space.")
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
			var room: float=minf(Transport.available_hold(c,b),c.capacity()-c.cargo_weight())
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
