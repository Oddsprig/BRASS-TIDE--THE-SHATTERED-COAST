extends RefCounted
const Goods=preload("res://scripts/goods.gd")
const Workshop=preload("res://scripts/fleet_workshop.gd")
const Home=preload("res://scripts/home_harbor.gd")
const Exploration067=preload("res://scripts/exploration.gd")
const Remote067=preload("res://scripts/remote_expedition067.gd")
const Shipping068=preload("res://scripts/shipping_flow068.gd")
## Optional campaign-extension schema; legacy voyages omit these fields.
static func number(value,low: float=0.0,high: float=1000000000.0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

## Raw job preflight, also called before restore runs any legacy normalizers.
## Membership comes from this career's canonical geography; each referenced
## account must already exist once, in the correct region. Never create a book.
static func validate_jobs070(s: Dictionary,world: Dictionary) -> String:
	if not s.has("voyageJobs"):return ""
	if not s.voyageJobs is Array or s.voyageJobs.size()>6:return "Invalid voyage commitment collection."
	var ports: Dictionary={}
	for p in world.get("PORTS",[]):ports[str(p.id)]="shatter_coast"
	if Shipping068.installed(s):ports[Shipping068.PORT]=Shipping068.World.REMOTE
	for p in Shipping068.harbors069(s):
		if not p is Dictionary or not p.get("id") is String or not p.get("regionId") is String:return "Invalid canonical voyage harbor."
		ports[p.id]=p.regionId
	if not s.get("ports") is Array:return "Missing voyage harbor accounts."
	var accounts: Dictionary={}
	for p in s.ports:
		if not p is Dictionary or not p.get("id") is String:continue
		if accounts.has(p.id):return "Duplicate voyage harbor account."
		accounts[p.id]=p
	var jobs: Dictionary={}
	for job in s.voyageJobs:
		if not job is Dictionary or not job.get("id") is String or jobs.has(job.id):return "Invalid or duplicate voyage job."
		jobs[job.id]=true
		if job.get("kind","") not in ["freight","survey","bounty","fuel_delivery","passenger_charter"] or job.get("state","") not in ["active","expired"]:return "Invalid voyage job kind/state."
		for key in ["port","targetPort"]:
			var id=job.get(key)
			if not id is String or not ports.has(id) or not accounts.has(id):return "Unknown voyage sponsor/destination account."
			if str(accounts[id].get("regionId","shatter_coast"))!=str(ports[id]):return "Voyage harbor account belongs to the wrong region."
		if job.get("payerKey","") not in ["cash","governmentPurse"]:return "Unknown voyage sponsor purse."
		for key in ["reward","escrow","deadlineDay","acceptedDay"]:
			if not number(job.get(key)):return "Invalid voyage job accounting."
		var savings: float=0.0
		if job.kind=="passenger_charter":
			for key in ["savingsHousehold","savingsExpert"]:
				if not number(job.get(key,0)):return "Invalid charter savings."
				savings+=float(job.get(key,0))
		if floorf(float(job.escrow))!=float(job.escrow) or float(job.escrow)>float(job.reward)+savings:return "Invalid voyage escrow."
		if not job.get("freight") is Dictionary:return "Invalid sealed voyage freight."
		var freight: Dictionary=job.freight
		if not freight.is_empty():
			if not freight.get("good") is String or not number(freight.get("qty")) or not Goods.ITEMS.has(freight.good):return "Invalid sealed voyage goods."
		for key in ["title","description","siteId","ownerId"]:
			if not job.get(key) is String:return "Invalid voyage text."
		var target_region: String=str(ports[job.targetPort])
		if job.kind=="survey":
			var exploration=s.get("exploration")
			if not exploration is Dictionary or not exploration.get("catalog") is Array or not exploration.get("sites") is Dictionary:return "Survey job has no existing exploration book."
			var site: Dictionary={}
			for row in exploration.catalog:
				if row is Dictionary and row.get("id")==job.siteId:
					if not site.is_empty():return "Survey job has duplicate site ownership."
					site=row
			if site.is_empty() or not exploration.sites.has(job.siteId):return "Survey job has no existing canonical site/progress."
			target_region=str(site.get("regionId","shatter_coast"))
			if Exploration067.region_record069(s,target_region).is_empty():return "Survey job region is absent from this career."
		for key in ["regionId","targetRegionId"]:
			if not job.has(key):continue
			var value=job[key]
			if not value is String or value.length()>80:return "Invalid voyage endpoint region."
			if not value.is_empty() and value!=(str(ports[job.port]) if key=="regionId" else target_region):return "Voyage endpoint disagrees with its canonical harbor/site."
	return ""

static func validate(s: Dictionary,world: Dictionary) -> String:
	var sector_error: String=Shipping068.sector_error069(s)
	if not sector_error.is_empty():return sector_error
	var shipping_error: String=Shipping068.raw_error(s)
	if not shipping_error.is_empty():return shipping_error
	var regional_error: String=Exploration067.validate_remote067(s)
	if regional_error.is_empty():regional_error=Remote067.validate_saved(s)
	if not regional_error.is_empty():return regional_error
	# B's raw optional paid-work-day gate must precede any legacy normalization.
	var home_error: String=Home.validate(s)
	if not home_error.is_empty():return home_error
	var library_error: String=Workshop.validate_templates(s,world)
	if not library_error.is_empty():return library_error
	if s.has("surveyFoodCredit") and not number(s.surveyFoodCredit,0,1000):return "Invalid prepaid survey rations."
	if s.has("exploration"):
		if not s.exploration is Dictionary:return "Invalid exploration record."
		var ex: Dictionary=s.exploration
		if not ex.get("catalog") is Array or ex.catalog.size()>128 or not ex.get("sites") is Dictionary or ex.sites.size()>128:return "Invalid island catalog/progress."
		var ids: Dictionary={}
		for site in ex.catalog:
			if not site is Dictionary or not site.get("id") is String or ids.has(site.id):return "Invalid or duplicate island site."
			var region: String=str(site.get("regionId","shatter_coast"))
			var bounds: Dictionary=Exploration067.region_record069(s,region)
			if bounds.is_empty():return "Island site belongs to a region absent from this career."
			var width: float=float(world.WORLD.width) if region=="shatter_coast" else float(bounds.width)
			var height: float=float(world.WORLD.height) if region=="shatter_coast" else float(bounds.height)
			if not number(site.get("x"),0,width) or not number(site.get("y"),0,height):return "Invalid island location."
			for key in ["name","kind","region","clue","discovery","hazard","resource","leadId"]:
				if not site.get(key) is String:return "Invalid island text."
			ids[site.id]=true
		for id in ex.sites:
			var rec=ex.sites[id]
			if not ids.has(id) or not rec is Dictionary or not number(rec.get("level"),0,3) or floorf(float(rec.level))!=float(rec.level) or not rec.get("rewarded") is bool:return "Invalid island progress."
		if not ex.get("assignment") is Dictionary:return "Invalid survey assignment."
		var a: Dictionary=ex.assignment
		if not a.is_empty():
			if not ids.has(a.get("siteId","")) or a.get("action","") not in ["chart","survey"]:return "Unknown survey site/action."
			for key in ["crewReserved","daysTotal","daysDone","foodSpent","suppliesSpent","targetLevel"]:
				if not number(a.get(key),0,1000):return "Invalid survey accounting."
			for key in ["crewReserved","targetLevel"]:
				if floorf(float(a[key]))!=float(a[key]):return "Survey crew and target level must be whole numbers."
			if float(a.daysTotal)<=0 or float(a.daysDone)>float(a.daysTotal):return "Invalid survey duration."
		for key in ["leads","log"]:
			if not ex.get(key) is Array or ex[key].size()>128:return "Invalid exploration "+key+"."
	if s.has("wrecks"):
		if not s.wrecks is Array or s.wrecks.size()>128:return "Invalid persistent wreck collection."
		var wreck_ids: Dictionary={}
		for w in s.wrecks:
			if not w is Dictionary or not w.get("id") is String or wreck_ids.has(w.id):return "Invalid or duplicate wreck identity."
			wreck_ids[w.id]=true
			var provenance: Dictionary=Remote067.identity(w)
			if provenance.is_empty():return "Invalid wreck world identity."
			var bounds: Dictionary=Exploration067.region_record069(s,str(provenance.regionId))
			if provenance.layer=="ocean":bounds=s.get("sector069",{}).get("atlas",{}).get("ocean",{"width":4800.0,"height":2800.0})
			if bounds.is_empty():return "Wreck provenance is absent from this career's sector."
			var width: float=float(world.WORLD.width) if provenance.layer=="home" else float(bounds.width)
			var height: float=float(world.WORLD.height) if provenance.layer=="home" else float(bounds.height)
			if not number(w.get("x"),0,width) or not number(w.get("y"),0,height):return "Invalid wreck location."
			if w.get("status","") not in ["unclaimed","stripped","towed"]:return "Invalid wreck status."
			if w.has("sourceLoadout") and not w.sourceLoadout is Dictionary:return "Invalid wreck equipment."
			for key in ["stores","components"]:
				if not w.get(key) is Dictionary:return "Invalid wreck inventory."
				for good in w[key]:
					if not Goods.ITEMS.has(good) or not number(w[key][good]):return "Invalid wreck material quantity."
	if s.has("blueprints"):
		if not s.blueprints is Dictionary or s.blueprints.size()>128:return "Invalid blueprint library."
		for key in s.blueprints:
			if not s.blueprints[key] is bool or not world.HULLS.any(func(h):return h.id==key):return "Unknown recovered hull design."
	for key in ["wreckSeededSources","wreckHazards"]:
		if s.has(key) and (not s[key] is Dictionary or s[key].size()>512):return "Invalid wreck provenance ledger."
	var jobs_error: String=validate_jobs070(s,world)
	if not jobs_error.is_empty():return jobs_error
	if s.has("doneVoyageJobs") and (not s.doneVoyageJobs is Array or s.doneVoyageJobs.size()>128):return "Invalid completed voyage records."
	if s.has("contacts"):
		if not s.contacts is Array or s.contacts.size()>32+Shipping068.harbors069(s).size():return "Invalid contact list."
		for person in s.contacts:
			if not person is Dictionary or not person.get("id") is String or not number(person.get("trust"),-100,100) or not person.get("met") is bool:return "Invalid contact identity/trust."
	if s.has("marketSnapshots"):
		if not s.marketSnapshots is Dictionary or s.marketSnapshots.size()>32+Shipping068.harbors069(s).size():return "Invalid market reports."
		for id in s.marketSnapshots:
			var snap=s.marketSnapshots[id]
			if not snap is Dictionary or not number(snap.get("day")) or not number(snap.get("cash")) or not snap.get("stocks") is Dictionary:return "Invalid dated market observation."
	if s.has("relationships"):
		if not s.relationships is Dictionary:return "Invalid faction record."
		var b: Dictionary=s.relationships
		for key in ["factions","pairs","contacts","commission","seen","portIndex"]:
			if not b.get(key) is Dictionary or b[key].size()>128:return "Invalid faction book "+key+"."
		for id in b.factions:
			var f=b.factions[id]
			if not f is Dictionary or not number(f.get("score"),-100,100) or not number(f.get("witnessed"),-100,100) or f.get("band","") not in ["hostile","wary","neutral","friendly","trusted"] or not f.get("claims") is Dictionary:return "Invalid faction standing."
			for port_id in f.claims:
				if not number(f.claims[port_id],0,100):return "Invalid harbor claim."
		for value in b.pairs.values():
			if not number(value,-100,100):return "Invalid faction diplomacy."
		for key in ["log","seenOrder"]:
			if not b.get(key) is Array or b[key].size()>128:return "Invalid faction history."
		for key in ["safeConduct","inspections"]:
			if b.has(key) and (not b[key] is Dictionary or b[key].size()>128):return "Invalid faction permits."
		for value in b.get("safeConduct",{}).values():
			if not number(value):return "Invalid safe conduct duration."
	if s.has("navalAi"):
		if not s.navalAi is Dictionary:return "Invalid naval activity book."
		for key in ["encounters","replacements"]:
			if not s.navalAi.get(key) is Array or s.navalAi[key].size()>24:return "Invalid bounded naval history."
		for key in ["spatialGrid","ordersByOwner"]:
			if not s.navalAi.get(key) is Dictionary or s.navalAi[key].size()>128:return "Invalid naval index."
		if not number(s.navalAi.get("tickCount")) or not number(s.navalAi.get("lastDay")):return "Invalid naval day counter."
	if s.has("tradeIntel"):
		if not s.tradeIntel is Dictionary:return "Invalid trade intelligence."
		var ti: Dictionary=s.tradeIntel
		if not ti.get("observations") is Dictionary or ti.observations.size()>16 or not ti.get("blockades") is Dictionary or ti.blockades.size()>32 or not ti.get("events") is Array or ti.events.size()>40:return "Invalid bounded trade intelligence."
		for record in ti.observations.values():
			if not record is Dictionary or not number(record.get("day")) or not number(record.get("businessFunds")):return "Invalid dated buyer observation."
			for key in ["stocks","buy","sell"]:
				if not record.get(key) is Dictionary or record[key].size()>preload("res://scripts/goods.gd").ITEMS.size():return "Invalid observed market."
				for value in record[key].values():
					if not number(value):return "Invalid observed market value."
	if s.has("specialists"):
		if not s.specialists is Array or s.specialists.size()>1024:return "Invalid specialist ledger."
		var specialist_ids: Dictionary={}
		for r in s.specialists:
			if not r is Dictionary or not r.get("id") is String or specialist_ids.has(r.id) or r.get("role","") not in ["pilot","gunner","chief_engineer","surveyor","quartermaster"]:return "Invalid specialist identity."
			specialist_ids[r.id]=true
			for key in ["coins","arrears","premiumPerDay","hiredDay"]:
				if not number(r.get(key)):return "Invalid specialist accounting."
			if not r.get("boatUid") is String or not r.get("portId") is String or not r.get("active") is bool:return "Invalid specialist assignment."
	for b in s.get("fleet",[]):
		if b.has("conversion") and b.conversion not in ["","cargo_rig","survey_rig","workshop_rig","tug_rig","auxiliary_tanks"]:return "Unknown support conversion."
		if b.has("supportOnly") and not b.supportOnly is bool:return "Invalid support deployment policy."
		if b.has("serviceHistory") and (not b.serviceHistory is Array or b.serviceHistory.size()>12):return "Invalid boat service history."
		if b.has("commandPreference"):
			if not b.commandPreference is Dictionary or b.commandPreference.size()!=2:return "Invalid saved boat command preference."
			if not b.commandPreference.get("doctrine") is String or b.commandPreference.doctrine not in ["cautious","steady","aggressive"]:return "Invalid saved boat doctrine."
			if not b.commandPreference.get("role") is String or b.commandPreference.role not in ["auto","skirmisher","striker","heavy","screen","support"]:return "Invalid saved boat tactical role."
	if s.has("campaignFacts"):
		if not s.campaignFacts is Dictionary or s.campaignFacts.size()>32:return "Invalid campaign achievements."
		for value in s.campaignFacts.values():
			if not number(value):return "Invalid campaign achievement count."
	if s.has("escortEvents") and (not s.escortEvents is Dictionary or s.escortEvents.size()>256):return "Invalid escorted passage ledger."
	if s.has("battleSeq") and not number(s.battleSeq):return "Invalid engagement sequence."
	if s.has("stories"):
		if not s.stories is Dictionary:return "Invalid coastal story book."
		var stories: Dictionary=s.stories
		if not stories.get("catalog") is Array or stories.catalog.size()>16 or not stories.get("chains") is Dictionary or stories.chains.size()>16:return "Invalid bounded story catalog/progress."
		for key in ["events","consequences","notified"]:
			if not stories.get(key) is Array or stories[key].size()>128:return "Invalid story event history."
		for rec in stories.chains.values():
			if not rec is Dictionary or not rec.get("stage") is String or not rec.get("done") is bool or not rec.get("flags") is Array or not rec.get("leads") is Array:return "Invalid story progress."
		for e in stories.consequences:
			if not e is Dictionary or not e.get("id") is String or e.get("kind","") not in ["faction","contact"] or not number(e.get("amount"),-25,25) or not e.get("applied") is bool:return "Invalid story consequence."
	if s.has("storyRights"):
		if not s.storyRights is Dictionary:return "Invalid story rights."
		var r: Dictionary=s.storyRights
		for key in ["openField","privateField","workshopCharter","privateOre","publicCharts","privateCharts"]:
			if not r.get(key) is bool:return "Invalid story permission."
		if r.get("buyer","") not in ["","compact","forge"] or not r.get("usedOffers") is Dictionary or r.usedOffers.size()>8 or not r.get("salvageWork") is Dictionary or r.salvageWork.size()>32:return "Invalid story opportunity ledger."
	if s.has("businesses"):
		if not s.businesses is Array or s.businesses.size()>12:return "Invalid shore business collection."
		var business_ids: Dictionary={}
		var ports: Array=[]
		for p in world.PORTS:ports.append(p.id)
		var caps: Dictionary={"warehouse":400,"salvage_yard":600,"workshop":300}
		var staff: Dictionary={"warehouse":{"laborer":2},"salvage_yard":{"laborer":3,"mechanic":1},"workshop":{"carpenter":3,"mechanic":1}}
		for b in s.businesses:
			if not b is Dictionary or not b.get("id") is String or business_ids.has(b.id) or not caps.has(b.get("kind","")) or not b.get("homePort","") in ports:return "Invalid business identity/home."
			business_ids[b.id]=true
			for key in ["coins","workingCapital","capitalIn","revenue","wagesPaid","dividendsPaid","arrearsHousehold","arrearsExpert","establishedDay","costOfSales","inKindCapital","inKindReturned"]:
				if not number(b.get(key)):return "Invalid business accounting."
			if not b.get("inventory") is Dictionary or b.inventory.size()>preload("res://scripts/goods.gd").ITEMS.size() or not b.get("inventoryBasis") is Dictionary or b.inventoryBasis.size()>preload("res://scripts/goods.gd").ITEMS.size() or not b.get("paused") is bool or not b.get("autoSell") is bool:return "Invalid business inventory/state."
			var weight: float=0
			for good in b.inventory:
				if not preload("res://scripts/goods.gd").ITEMS.has(good) or not number(b.inventory[good]):return "Invalid stored business good."
				weight+=float(b.inventory[good])*float(preload("res://scripts/goods.gd").ITEMS[good].weight)
			for value in b.inventoryBasis.values():
				if not number(value):return "Invalid stored material basis."
			if weight>float(caps[b.kind])+0.01:return "Business store exceeds its physical capacity."
			if not b.get("employees") is Array or b.employees.size()>(12 if b.kind=="workshop" else 8):return "Invalid business staff."
			var actual: Dictionary={}
			for e in b.employees:
				if not e is Dictionary or not preload("res://scripts/goods.gd").WAGES.has(e.get("occupation","")) or e.get("wage",0)!=preload("res://scripts/goods.gd").WAGES[e.occupation] or not e.get("name") is String:return "Invalid business employee/wage."
				actual[e.occupation]=int(actual.get(e.occupation,0))+1
			if b.kind=="workshop":
				if b.employees.is_empty():return "Workshop has no actual workforce."
				for occupation in actual:
					if occupation not in ["carpenter","mechanic","engineer","gunsmith"]:return "Unknown workshop trade."
			else:
				if actual!=staff[b.kind]:return "Business has an invalid permanent workforce."
	for b in s.get("fleet",[]):
		if b.has("berthArrears") and not number(b.berthArrears):return "Invalid stored berth account."
	var port_ids: Array=world.PORTS.map(func(p):return p.id)
	if s.has("regionalOrigin") and (not s.regionalOrigin is String or (s.regionalOrigin!="" and not s.regionalOrigin in port_ids)):return "Invalid regional departure."
	if s.has("campaignFocus"):
		if not s.campaignFocus is Dictionary:return "Invalid regional focus."
		for key in ["fromPort","toPort","portId"]:
			if not s.campaignFocus.get(key,"") in port_ids:return "Unknown regional harbor."
		for key in ["peaceA","peaceB"]:
			if not s.campaignFocus.get(key,"") in ["compact","forge","reed","raiders"]:return "Unknown treaty party."
	if s.has("regionalFacts"):
		if not s.regionalFacts is Dictionary:return "Invalid physical regional facts."
		for key in ["deliveries","passages"]:
			if not s.regionalFacts.get(key) is Dictionary or s.regionalFacts[key].size()>64:return "Invalid bounded regional facts."
			for id in s.regionalFacts[key]:
				if not number(s.regionalFacts[key][id]):return "Invalid regional activity amount."
				if key=="deliveries" and not id in port_ids:return "Unknown regional delivery harbor."
				if key=="passages":
					var ends: PackedStringArray=str(id).split("|")
					if ends.size()!=2 or not ends[0] in port_ids or not ends[1] in port_ids or ends[0]==ends[1]:return "Invalid physical corridor."
	if s.has("regionalCampaigns"):
		if not s.regionalCampaigns is Dictionary:return "Invalid regional campaign book."
		var book: Dictionary=s.regionalCampaigns
		for key in ["operations","completed","peace","fundedRoutes"]:
			if not book.get(key) is Dictionary or book[key].size()>128:return "Invalid bounded regional book."
		if not book.get("journal") is Array or book.journal.size()>40 or not number(book.get("seq")):return "Invalid regional history."
		if book.operations.size()>4 or book.peace.size()>6:return "Too many regional operations."
		for id in book.operations:
			var op=book.operations[id]
			if not id in ["corridor","harbor","survey","ceasefire"] or not op is Dictionary or op.get("id","")!=id or op.get("status","") not in ["active","complete","cancelled"]:return "Invalid regional operation identity."
			if not op.get("completionId") is String or not op.get("ownerId") is String or not op.get("portId") is String:return "Invalid regional assignment."
			if op.portId!="" and not op.portId in port_ids:return "Unknown regional operation harbor."
			if op.has("watchState") and (id!="corridor" or not op.watchState is String or not op.watchState in ["active","awaiting","withdrawn"]):return "Invalid optional corridor watch choice."
			if op.has("businessDays"):
				if id!="harbor" or not op.businessDays is Dictionary or op.businessDays.size()>12 or not number(s.get("econDay")):return "Invalid optional harbor work-day baseline."
				for business_id in op.businessDays:
					var value=op.businessDays[business_id]
					if not business_id is String or business_id.is_empty() or value is bool or not number(value,0,float(s.econDay)) or floorf(float(value))!=float(value):return "Invalid harbor business work-day baseline."
			for key in ["funded","startedDay","clearDays","lastAssessedDay","patrolVisits","talksStartedDay","passageBaseline","deliveryBaseline"]:
				if not number(op.get(key)):return "Invalid regional progress/accounting."
			if not op.get("playerAction") is bool or not op.get("ends") is Array or op.ends.size()>2:return "Invalid regional corridor proof."
			for value in op.ends:
				if not value in port_ids:return "Unknown corridor endpoint."
			for key in ["contributed","baseline","businessWages","relief"]:
				if not op.get(key) is Dictionary or op[key].size()>32:return "Invalid regional supply/progress ledger."
				for value in op[key].values():
					if not number(value):return "Invalid regional supply/progress amount."
			if op.has("currentPlan"):
				if id!="corridor" or not op.currentPlan is Dictionary:return "Invalid observed corridor plan."
				var plan: Dictionary=op.currentPlan
				if not plan.get("ready") is bool or not plan.get("hold") is bool:return "Invalid observed corridor readiness."
				for key in ["ownerId","completionId","purpose","destination","targetOwnerId","convoyOwnerId","reason"]:
					if not plan.get(key) is String:return "Invalid observed corridor order."
				if plan.ownerId!=op.ownerId or plan.completionId!=op.completionId or not plan.destination in port_ids:return "Unknown observed corridor assignment."
				if not plan.purpose in ["patrol","escort","intercept","withdraw","repair","resupply","replace"]:return "Invalid corridor order purpose."
				for key in ["ownerId","targetOwnerId","convoyOwnerId"]:
					if plan[key]!="" and not s.get("fleetOwners",[]).any(func(o):return str(o.get("id",""))==str(plan[key])):return "Unknown corridor fleet."
				var point=plan.get("interceptPoint",{})
				if not point is Dictionary:return "Invalid corridor interception point."
				if not point.is_empty() and (not number(point.get("x"),0,float(world.WORLD.width)) or not number(point.get("y"),0,float(world.WORLD.height))):return "Invalid corridor interception position."
				for quote in [plan.get("readiness"),op.get("readiness",{})]:
					if not quote is Dictionary:return "Invalid corridor reserve quote."
					if quote.is_empty():continue
					for key in ["ready","moduleOk","canReturn"]:
						if not quote.get(key) is bool:return "Invalid corridor reserve flags."
					for key in ["reason","shortage"]:
						if not quote.get(key) is String:return "Invalid corridor shortage reason."
					for key in ["routeDistance","returnDistance","days","returnDays","speed","clearance","fuelNeed","fuel","foodNeed","food","payrollNeed","coins","ammoNeed","ammo","engineMin"]:
						if not number(quote.get(key)):return "Invalid corridor reserve amount."
					if quote.has("reserveDays") and not number(quote.reserveDays):return "Invalid corridor provisioning days."
				for key in ["stallReason","planIdentity"]:
					if not op.get(key,"") is String:return "Invalid observed corridor status."
			if id=="ceasefire":
				for key in ["peaceA","peaceB"]:
					if not op.get(key,"") in ["compact","forge","reed","raiders"]:return "Unknown operation treaty party."
		for rec in book.peace.values():
			if not rec is Dictionary or not rec.get("active") is bool:return "Invalid regional treaty."
			for key in ["a","b"]:
				if not rec.get(key,"") in ["compact","forge","reed","raiders"]:return "Unknown treaty faction."
			for key in ["day","untilDay","cooldownUntil"]:
				if not number(rec.get(key)):return "Invalid treaty date."
			if not number(rec.get("before"),-100,100) or rec.a==rec.b or int(rec.untilDay)<int(rec.day) or int(rec.cooldownUntil)<int(rec.untilDay):return "Invalid treaty terms."
		for rec in book.fundedRoutes.values():
			if not rec is Dictionary or not number(rec.get("amount")) or not rec.get("ownerId") is String or not rec.get("portId","") in port_ids:return "Invalid once-only regional grant record."
	return ""
