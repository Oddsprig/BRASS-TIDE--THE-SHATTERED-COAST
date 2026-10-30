extends RefCounted
## Regional reads and private route projections. No account, job store or cache.
const World=preload("res://scripts/ocean_world064.gd")
const Travel=preload("res://scripts/ocean_travel066.gd")
const Costs=preload("res://scripts/voyage_costs065.gd")
const Navigation=preload("res://scripts/navigation.gd")
const Routes=preload("res://scripts/route_cache.gd")
const Shipping=preload("res://scripts/shipping_flow068.gd")
const Exploration=preload("res://scripts/exploration.gd")
const Expedition=preload("res://scripts/expedition.gd")
const Economy=preload("res://scripts/economy.gd")
const Goods=preload("res://scripts/goods.gd")
const Support=preload("res://scripts/fleet_support.gd")
const Manifest=preload("res://scripts/hold_manifest.gd")
const MAX_CANDIDATES: int=8
const MAX_GATE_ATTEMPTS: int=2

static func region(row: Dictionary) -> String:
	return str(row.get("regionId",World.HOME))

static func work_port(c) -> Dictionary:
	if c==null:return {}
	if c.has_method("work_port070"):return c.work_port070()
	return c.current_port() if c.has_method("current_port") and c.state.get("path",[]).is_empty() else {}

static func known_port(c,p: Dictionary) -> bool:
	if p.is_empty():return false
	if region(p)==World.HOME:return true
	return Shipping.known069(c.state,str(p.id)) or (str(p.id)==Shipping.PORT and Shipping.installed(c.state) and str(p.id) in c.state.shipping068.knownPorts)

static func fuel_port(c,owner: Dictionary) -> Dictionary:
	if owner.is_empty():return {}
	var dock: Dictionary=c.port(str(owner.get("atPort","")))
	if dock.is_empty() or not known_port(c,dock):return {}
	# The shipping carrier has a real independent spatial record; its stale
	# HOME patrol projection is never evidence of a remote fuel recipient.
	if str(owner.get("id",""))==Shipping.OWNER and Shipping.installed(c.state):
		var actor: Dictionary=Shipping.actor(c)
		if actor.is_empty():return {}
		var location: Dictionary=actor.location
		if str(location.world064.regionId)!=region(dock) or location.world064.layer=="ocean" or not location.path.is_empty() or c.distance(location.position,dock)>=40.0:return {}
		return dock
	for p in c.state.get("patrols",[]):
		if str(p.get("id",""))!=str(owner.get("id","")):continue
		if not p.get("active",false) or not p.get("holding",false) or p.has("interceptPoint"):return {}
		if str(p.get("world064",{}).get("regionId",Exploration.HOME_REGION))!=region(dock):return {}
		var geometry: Dictionary=c.nav if region(dock)==Exploration.HOME_REGION else c.ocean_context064.get("regionGeometry",{}).get(region(dock),{})
		if c.distance(p,dock)>=40.0 or not Navigation.is_water(geometry,p.x,p.y,Routes.clearance(c,p)):return {}
		return dock
	return {}

static func _point(row: Dictionary) -> Dictionary:
	return {"x":float(row.x),"y":float(row.y)}

static func _project(c,row: Dictionary) -> Dictionary:
	var context: Dictionary=c.get("ocean_context064") if c.get("ocean_context064") is Dictionary else {}
	for view in context.get("regionViews",[]):
		if str(view.regionId)==region(row):
			var scale: float=float(context.ocean.localUnitsPerUnit)
			return {"x":float(view.bounds.x)+float(row.x)/scale,"y":float(view.bounds.y)+float(row.y)/scale}
	return {}

static func rank(c,a: Dictionary,b: Dictionary) -> float:
	if region(a)==region(b):return World._distance(a,b)
	var pa: Dictionary=_project(c,a);var pb: Dictionary=_project(c,b)
	return World._distance(pa,pb)*float(c.ocean_context064.ocean.localUnitsPerUnit) if not pa.is_empty() and not pb.is_empty() else INF

static func destinations(c,p: Dictionary) -> Array:
	var rows: Array=[]
	for target in c.state.get("ports",[]):
		if target is Dictionary and str(target.get("id",""))!=str(p.id) and known_port(c,target):rows.append(target)
	rows.sort_custom(func(a,b):
		var da: float=rank(c,p,a);var db: float=rank(c,p,b)
		return str(a.id)<str(b.id) if is_equal_approx(da,db) else da<db)
	return rows.slice(0,MAX_CANDIDATES)

static func survey_sites(state: Dictionary,origin: Dictionary) -> Array:
	var out: Array=[]
	# _merged is a read; sites() would normalize the live exploration book.
	for raw in Exploration._catalog(state):
		if not raw is Dictionary:continue
		var site: Dictionary=Exploration._merged(state,raw)
		if int(site.level)>=Exploration.LEVEL_SURVEYED:continue
		if region(site)==World.HOME and region(origin)==World.HOME:out.append(site)
		elif int(site.level)>=Exploration.LEVEL_SIGHTED:
			# Level-one observations disclose no hidden name/resource/hazard.
			if int(site.level)<Exploration.LEVEL_CHARTED:site.name="Uncharted shore landmark"
			out.append(site)
	return out

# Detached survey candidates/DTO and the catalog tariff share the regional reads.
# Jobs retains closed-job checks, final selection and all funding/custody writes.
static func survey_candidates(core,p: Dictionary) -> Array:
	var state: Dictionary=core.state
	var unsurveyed: Array = []
	for site in survey_sites(state,p):
		var carried: bool=false
		for job in state.get("voyageJobs",[]):
			if str(job.get("kind",""))=="survey" and str(job.get("siteId",""))==str(site.id):carried=true;break
		if not carried and int(site.get("level", 0)) < Exploration.LEVEL_SURVEYED:
			unsurveyed.append(site)
	return unsurveyed

static func ranked_surveys(core,p: Dictionary,day: int,unsurveyed: Array,pairing: Dictionary) -> Array:
	var state: Dictionary=core.state
	# Preserve the authored daily first choice and accepted story pairing.
	# Remote work is earned and ranked on its own actual region geometry.
	if region(p)==Exploration.HOME_REGION:
		var authored: Array=unsurveyed.filter(func(s):return region(s)==Exploration.HOME_REGION)
		if not authored.is_empty():
			var first: Dictionary=authored[(day+maxi(0,int(state.ports.find(p))))%authored.size()]
			unsurveyed.erase(first);unsurveyed.push_front(first)
	else:
		unsurveyed.sort_custom(func(a,b):
			var da: float=rank(core,p,a);var db: float=rank(core,p,b)
			return str(a.id)<str(b.id) if is_equal_approx(da,db) else da<db)
	for candidate in unsurveyed:
		if str(candidate.id)==str(pairing.get("siteId","")):unsurveyed.erase(candidate);unsurveyed.push_front(candidate);break
	return unsurveyed.slice(0,MAX_CANDIDATES)

static func survey_reward(core,p: Dictionary,days: float,site: Dictionary={}) -> int:
	var level: int=int(site.get("level",Exploration.LEVEL_SIGHTED))
	if level>=Exploration.LEVEL_SURVEYED:return 0
	var shore_days: float=0.0
	var kits: float=0.0
	var spare: int=0
	for key in [Exploration.ACTION_CHART,Exploration.ACTION_SURVEY]:
		var spec: Dictionary=Exploration.ACTIONS[key]
		if level>=int(spec.to):continue
		shore_days+=float(spec.days);kits+=float(spec.supplies)
		spare=maxi(spare,int(spec.crew))
	# Keep the maximum remaining shore party aboard for the entire voyage,
	# including charting: three sailing plus four survey crew on the Tinwake.
	# Extra owned boats/crew never enlarge a client's tariff.
	var reference: Dictionary=core.hull("tin_skiff")
	var crew: int=maxi(1,int(reference.get("crewMin",3)))+spare
	var work_days: float=maxf(1,ceilf(days*2.0+shore_days))
	var upkeep: Dictionary=Economy.daily_upkeep([{"crew":crew,"spec":reference,"sunk":false}])
	var burn: float=45.0*(0.011+float(reference.get("size",14))*0.0002)*maxf(0.2,float(reference.get("fuelUse",1)))
	var survey_value: float=crew*Goods.SAILOR_WAGE*work_days+float(upkeep.food)*work_days*Economy.price(p,"food")
	survey_value+=burn*days*2.0*Economy.price(p,"fuel")
	survey_value+=kits*Economy.price(p,"supplies")+Goods.WAGES.laborer
	return maxi(1,ceili(survey_value*1.25))

static func survey_offer(p: Dictionary,site: Dictionary,pairing: Dictionary,survey_id: String,day: int,days: float,reward: int) -> Dictionary:
	return {
		"id": survey_id, "title": "Survey %s" % str(site["name"]),
		"description": ("Pairs with your accepted Middle Sea lead. " if str(pairing.get("siteId",""))==str(site.id) else "")+"The harbor government escrows a survey fee. Full level 3 survey and a report here are required. Clue: %s" % str(site.get("clue", "")),
		"port": str(p["id"]), "targetPort": str(p["id"]), "kind": "survey",
		"regionId":region(p),"targetRegionId":region(site),
		"reward": reward, "escrow": 0, "payerKey": "governmentPurse",
		"deadlineDay": float(day) + ceilf(days * 2.0 + 14.0), "acceptedDay": 0.0,
		"freight": {}, "state": "offered",
		"siteId": str(site["id"]), "ownerId": "",
		"feeBasis":"Fixed catalog Tinwake with minimum sailing crew plus four spare surveyors throughout; whole payroll days for return travel and remaining base chart/survey phases, real rations/moving fuel, remaining phase kits, one registration laborer-day and 25% margin. Extra fleet costs remain yours."}

static func _gate_pairs(context: Dictionary,location: Dictionary,target: Dictionary,home: Dictionary) -> Array:
	var read: Dictionary=World.view(context,location,[])
	if not read.ok:return []
	var from: Array=[];var to: Array=[];var back: Array=[]
	for view in read.view.regions:
		if str(view.regionId)==str(location.world064.regionId):from=view.approaches
		if str(view.regionId)==region(target):to=view.approaches
		if str(view.regionId)==region(home):back=view.approaches
	var scale: float=float(context.ocean.localUnitsPerUnit)
	var pairs: Array=[]
	if location.world064.layer=="ocean":from=[{"id":"","position":location.position}]
	for depart in from:
		for arrive in to:
			var return_gate: String=str(depart.id)
			if str(location.world064.regionId)!=region(home):
				var best: float=INF
				for gate in back:
					var length: float=World._distance(arrive.position,gate.position)
					if length<best:best=length;return_gate=str(gate.id)
			var score: float=World._distance(depart.position,arrive.position)*scale
			pairs.append({"depart":str(depart.id),"arrive":str(arrive.id),"home":return_gate,"score":score})
	pairs.sort_custom(func(a,b):return str(a.depart)+str(a.arrive)<str(b.depart)+str(b.arrive) if is_equal_approx(float(a.score),float(b.score)) else float(a.score)<float(b.score))
	return pairs.slice(0,MAX_GATE_ATTEMPTS)

static func _sail_to(context: Dictionary,j: Dictionary,phase: String,target: Dictionary,site: bool=false) -> bool:
	var destination: String="" if site else str(target.id)
	var endpoint: Dictionary=_point(target)
	var reach: float=Exploration.WORK_RADIUS if site else (65.0 if region(target)==World.HOME else 40.0)
	if region(target)==str(j.location.world064.regionId) and World._distance(j.location.position,target)<reach:return true
	if site:
		var navigation: Dictionary=World._nav(context,j.location.world064)
		endpoint=Navigation.harbor_approach(navigation,target,float(j.clearance),Exploration.WORK_RADIUS)
		if endpoint.is_empty():return Costs._route_failure(j,"landing","No safe water landing within the existing shore-work radius.")
	return Costs._sail(context,j,phase,endpoint,destination,region(target),"","Sail to "+str(target.get("name","work destination")))

static func route(c,target: Dictionary,home: Dictionary,site: bool=false) -> Dictionary:
	if target.is_empty() or home.is_empty():return {"ok":false,"message":"The actual job endpoint is unavailable."}
	if not c.has_method("world_location064") or not c.get("ocean_context064") is Dictionary or c.ocean_context064.is_empty():
		return {"ok":false,"message":"The existing world geometry is unavailable."}
	var speed: float=float(c.travel_speed())
	if not is_finite(speed) or speed<=0:return {"ok":false,"message":"A crewed traveling fleet with sailing speed is required."}
	# Explicit quote owner: only these two private slot assignments may change.
	# Pinned HOME/Glasswind/current grids and all polygons stay shared read-only.
	var context: Dictionary=c.ocean_context064.duplicate()
	var prepared: Dictionary=World.prepare_player(c.world_location064(),context,Routes.clearance(c))
	if not prepared.ok:return prepared
	var location: Dictionary=prepared.location
	location.path=[];location.destination="" # projection from the actual point, no live course changes
	var same: bool=str(location.world064.regionId)==region(target) and region(target)==region(home)
	var pairs: Array=[{"depart":"","arrive":"","home":""}] if same else _gate_pairs(context,location,target,home)
	var last: Dictionary={"ok":false,"message":"No compatible regional approach was found."}
	for pair in pairs:
		var trial: Dictionary=context.duplicate()
		var j: Dictionary={"ok":true,"location":location.duplicate(true),"legs":[],"nextAction":Costs._no_action(),"speed":speed,"clearance":Routes.clearance(c)}
		if str(j.location.world064.regionId)!=region(target):
			if j.location.world064.layer!="ocean" and not Costs._cross(trial,j,"outward",str(j.location.world064.regionId),str(pair.depart)):last=j;continue
			if not Costs._cross(trial,j,"outward",region(target),str(pair.arrive)):last=j;continue
		if not _sail_to(trial,j,"outward",target,site):last=j;continue
		if region(target)!=region(home):
			if not Costs._cross(trial,j,"return",region(target),str(pair.arrive)):last=j;continue
			if not Costs._cross(trial,j,"return",region(home),str(pair.home)):last=j;continue
		if not _sail_to(trial,j,"return",home):last=j;continue
		var outward: float=0.0;var returning: float=0.0
		for leg in j.legs:
			if str(leg.phase)=="outward":outward+=float(leg.physicalDistance)
			else:returning+=float(leg.physicalDistance)
		return {"ok":true,"message":"Actual water route and return projected.","legs":j.legs,"nextAction":j.nextAction,"outwardDistance":outward,"returnDistance":returning,
			"referenceDays":outward/maxf(1,float(c.hull("tin_skiff").get("speed",118))*1.55*float(c.data.get("CAMPAIGN_SCALE",1)))/Expedition.DAY_SECONDS}
	return {"ok":false,"message":str(last.get("message","No safe job water route."))}

static func shore_work(c,offer: Dictionary) -> Dictionary:
	if str(offer.get("kind",""))!="survey":return {"days":0.0,"food":0.0,"supplies":0.0,"crew":0}
	var site: Dictionary=Exploration.catalog_site(c.state,str(offer.get("siteId","")))
	var level: int=int(c.state.get("exploration",{}).get("sites",{}).get(str(site.get("id","")),{}).get("level",0))
	var factor: float=1.0
	for b in c.active_fleet():
		if float(b.get("crew",0))-float(b.get("wounded",0))-float(b.get("shoreCrew",0))>float(b.get("crewMin",1)):factor=maxf(factor,float(b.spec.get("surveyFactor",1)))
	var work: Dictionary={"days":0.0,"food":0.0,"supplies":0.0,"crew":0}
	for key in [Exploration.ACTION_CHART,Exploration.ACTION_SURVEY]:
		var spec: Dictionary=Exploration.ACTIONS[key]
		if level>=int(spec.to):continue
		var days: float=float(spec.days)/factor
		work.days+=days;work.food+=snappedf(Exploration.FOOD_PER_CREW_DAY*float(spec.crew)*days,0.01)
		work.supplies+=float(spec.supplies);work.crew=maxi(int(work.crew),int(spec.crew))
	return work

static func _value(row: Dictionary,p: Dictionary) -> float:
	return float(row.coins)+float(row.food)*Economy.price(p,"food")+float(row.fuel)*Economy.price(p,"fuel")+float(row.supplies)*Economy.price(p,"supplies")

static func _support_roles(c) -> Array:
	var benefits: Dictionary={"scout":"Fitted surveyFactor shortens real shore work; spare crew and kits are still required.","transport":"Adds actual hold space and spare berths; sealed fuel needs one eligible carrier.",
		"tanker":"Carries sealed fuel in its own hold; operating tanks and loose fuel still need explicit transfers.","repair":"Fitted repairFactor improves work using actual kits; it does not supply free repairs.","yacht":"Provides real passenger berths with its actual crew and provisions; wages still apply."}
	var rows: Array=[]
	for role in benefits:
		var owned: Array=[]
		for b in c.active_fleet():
			if str(b.spec.get("civilianRole",""))==str(role):owned.append(str(b.uid))
		rows.append({"role":str(role),"boatUids":owned,"available":not owned.is_empty(),"benefit":str(benefits[role])})
	return rows

static func offer_view(c,offer: Dictionary) -> Dictionary:
	var p: Dictionary=c.port(str(offer.get("port","")))
	var survey: bool=str(offer.get("kind",""))=="survey"
	var target: Dictionary=Exploration.catalog_site(c.state,str(offer.get("siteId",""))) if survey else c.port(str(offer.get("targetPort","")))
	var freight: Dictionary=offer.get("freight",{})
	var held: bool=c.state.get("voyageJobs",[]).any(func(j):return str(j.get("id",""))==str(offer.get("id","")))
	var out: Dictionary={"ok":false,"routeOk":false,"message":"","offerId":str(offer.get("id","")),"kind":str(offer.get("kind","")),"port":str(offer.get("port","")),"targetPort":str(offer.get("targetPort","")),
		"regionId":region(p),"targetRegionId":region(target),"grossFee":int(offer.get("reward",0)),"materialInvoice":int(offer.get("materialInvoice",0)),
		"holdRequired":float(freight.get("qty",0))*float(Goods.ITEMS.get(str(freight.get("good","")),{"weight":0}).weight)+float(offer.get("charterFood",{}).get("food",0)),
		"berthsRequired":int(offer.get("passengers",{}).get("n",0)),"crewNeeded":0,"outwardDays":0.0,"workDays":0.0,"returnDays":0.0,"routeDistance":0.0,
		"expectedCosts":{},"returnReserve":{},"likelySurplus":0.0,"readyForAllowance":false,"blockers":[],"warnings":[],"feeBasis":str(offer.get("feeBasis","")),"supportRoles":_support_roles(c),"nextAction":Costs._no_action(),"legs":[]}
	out.targetRegionName=str(c.ocean_context064.get("regions",{}).get(region(target),{}).get("name",region(target)))
	out.holdNeed=out.holdRequired;out.passengerNeed=out.berthsRequired
	out.spareBerths=0
	for b in c.active_fleet():out.spareBerths=maxi(int(out.spareBerths),maxi(0,int(b.get("crewMax",0))-ceili(float(b.get("crew",0)))-int(c.state.get("captiveBerths",{}).get(str(b.uid),0))-Manifest.Passengers.assigned(c.state,str(b.uid))))
	if str(offer.get("kind",""))=="bounty":
		out.message="Bounty requires the actual named fleet; its combat, damage and pursuit costs cannot be estimated as a fixed delivery."
		out.warnings.append(out.message);return out
	var work: Dictionary=shore_work(c,offer)
	var report_only: bool=survey and float(work.days)<=0.0
	var expired: bool=str(offer.get("state",""))=="expired"
	if expired:work={"days":0.0,"food":0.0,"supplies":0.0,"crew":0};out.grossFee=0
	var journey: Dictionary=route(c,p if report_only or expired else target,p,survey and not report_only and not expired)
	if not journey.ok:out.message=str(journey.message);out.blockers.append(out.message);return out
	var speed: float=float(c.travel_speed())
	var outward: float=float(journey.outwardDistance)/speed/Expedition.DAY_SECONDS
	var returning: float=float(journey.returnDistance)/speed/Expedition.DAY_SECONDS
	var safe_out: float=outward;var safe_back: float=returning
	var ocean: Dictionary=c.get("ocean_context066") if c.get("ocean_context066") is Dictionary else {}
	if not ocean.is_empty():
		var forecast: Dictionary=Travel.forecast(ocean,journey.legs,speed,float(c.state.day)*Expedition.DAY_SECONDS)
		if not forecast.ok:out.message=str(forecast.message);out.blockers.append(out.message);return out
		outward=0.0;returning=0.0;safe_out=0.0;safe_back=0.0
		for i in range(journey.legs.size()):
			var time: Dictionary=forecast.legTimes[i]
			if str(journey.legs[i].phase)=="outward":outward+=float(time.expectedSeconds)/Expedition.DAY_SECONDS;safe_out+=float(time.conservativeSeconds)/Expedition.DAY_SECONDS
			else:returning+=float(time.expectedSeconds)/Expedition.DAY_SECONDS;safe_back+=float(time.conservativeSeconds)/Expedition.DAY_SECONDS
		out.warnings.append_array(forecast.assumptions)
	var snapshot: Dictionary=c.state.duplicate(true)
	if not held:
		if not snapshot.get("voyageJobs") is Array:snapshot.voyageJobs=[]
		snapshot.voyageJobs.append(offer.duplicate(true)) # physical proposed payload, no escrow reservation
	Manifest.allocate(snapshot)
	var pending: float=maxf(0,floorf(float(snapshot.day))-float(snapshot.econDay))
	var plan: Dictionary={"outwardDays":safe_out,"returnDays":safe_back,"shoreDays":float(work.days)+pending,"shoreFood":float(work.food),"foodCredit":float(snapshot.get("surveyFoodCredit",0))}
	var kits: float=float(snapshot.get("cargo",{}).get("supplies",0))
	for b in snapshot.fleet:
		if not b.get("sunk",false) and not b.get("mothballed",false) and str(b.get("storedPort","")).is_empty():kits+=float(b.get("supplies",0))
	plan.kitShortfall=maxf(0,float(work.supplies)-kits)
	var allowance: Dictionary=Expedition.report(snapshot,c.data,float(journey.outwardDistance),speed,plan)
	var expected: Dictionary=Costs._expected(snapshot,outward,returning,float(work.days),pending)
	var stores: Dictionary=Costs._stores(snapshot,allowance,outward,returning,safe_out,safe_back)
	var upkeep: Dictionary=Economy.daily_upkeep(snapshot.fleet)
	var burn: float=0.0
	for boat in stores.boats:
		if boat.burnsWhileMoving:burn+=float(boat.fuelPerDay)
	# A whole-trip replacement value. Shore food prepays the SAME daily ration
	# consumption, so it is a maximum rather than a second food bill.
	var costs: Dictionary={"coins":float(expected.coinsRequired)+float(snapshot.get("wageArrears",0)),"food":maxf(float(expected.food),float(work.food)),
		"fuel":burn*(outward+returning),"supplies":float(work.supplies),"payrollDays":float(expected.totalPayrollDays),
		"baseWages":float(expected.baseWages),"premiums":float(expected.premiums),"includesReturn":true,"basis":"All living owned crew, fitted upkeep and moving hull fuel; whole calendar settlements, work and return; replacement stores priced at the sponsor's existing buy prices."}
	costs.totalValue=_value(costs,p)
	var reserve_days: float=ceilf(safe_back+2.0)
	var reserve: Dictionary={"coins":float(allowance.dailyWages)*reserve_days,"food":float(upkeep.food)*reserve_days,"fuel":burn*(safe_back+2.0),"supplies":0.0,
		"days":safe_back+2.0,"contingencyDays":2.0,"overlapsExpected":true,"basis":"Conservative return and two-day contingency. Informational overlap; do not subtract this again from whole-trip expected costs."}
	reserve.totalValue=_value(reserve,p)
	out.merge({"ok":true,"routeOk":true,"outwardDays":outward,"workDays":float(work.days),"returnDays":returning,"routeDistance":float(journey.outwardDistance)+float(journey.returnDistance),"crewNeeded":int(work.crew),
		"expectedCosts":costs,"returnReserve":reserve,"likelySurplus":float(out.grossFee)-float(costs.totalValue),"nextAction":journey.nextAction,"legs":journey.legs,"allowance":allowance,"remainingOnly":held},true)
	out.warnings.append_array(allowance.warnings)
	if not allowance.readyForAllowance:out.blockers.append(str(allowance.bottleneck))
	if int(work.crew)>Exploration.spare_crew(snapshot):out.blockers.append("Needs %d spare crew above working hull minimums."%int(work.crew))
	if float(work.supplies)>float(allowance.repairKits)+0.000001:out.blockers.append("Carry %.0f actual shore supply kits."%float(work.supplies))
	if str(offer.get("kind",""))=="fuel_delivery" and not str(offer.get("carrierUid","")).is_empty() and snapshot.get("cargoManifest",{}).get("unassigned",{}).has("@job:"+str(offer.get("id",""))):out.blockers.append("The entire sealed fuel lot must fit its selected physical carrier.")
	if float(allowance.returnWages)+float(allowance.wageArrears)+Support.premium(snapshot,true)>float(snapshot.coins):out.blockers.append("Full return allowance and existing professional arrears are not funded; offered escrow is not spendable.")
	if c.has_method("transition_blocker064"):
		var blocked: String=str(c.transition_blocker064())
		if not blocked.is_empty():out.blockers.append(blocked)
	var maintenance: Dictionary=Costs._maintenance(snapshot)
	if not maintenance.usageKnown:out.warnings.append("Existing damage makes repair-kit use and sailing performance conditional; repair costs are not included.")
	out.warnings.append("Expected whole-trip costs include return once. Return reserve overlaps them and adds contingency; it is not a second expense. Delays, encounters, purchases and future damage are excluded.")
	out.readyForAllowance=out.blockers.is_empty()
	out.message="Route estimated from the actual fleet; review stores, whole-trip costs and return allowance."
	out.operatingCost=costs.totalValue;out.returnReserves=reserve.totalValue;out.affordNote=out.message
	return Costs._string_data(out)

# Only passenger_transport's existing same-region physical transactions use
# this narrow view. Core.current_port and every other HOME service stay intact.
class CharterView extends RefCounted:
	var source
	var core=null # passenger_transport.actual must keep this narrow view
	var state: Dictionary
	var data: Dictionary
	var nav: Dictionary
	var berth: Dictionary
	const DAY_SECONDS: float=45.0
	const LocalWorld=preload("res://scripts/ocean_world064.gd")
	const ToolingOps=preload("res://scripts/tooling_ops.gd")
	func _init(c,p: Dictionary):
		source=c;state=c.state.duplicate();data=c.data;berth=p
		# Existing Routes identifies ports by coordinates; only the current region
		# may participate in this local read. Port records themselves remain LIVE.
		state.ports=c.state.ports.filter(func(row):return str(row.get("regionId","shatter_coast"))==str(p.regionId))
		nav=LocalWorld._nav(c.ocean_context064,c.world_location064().world064)
	func current_port() -> Dictionary:return berth
	func port(id: String) -> Dictionary:return source.port(id)
	func port_position(id: String) -> Dictionary:
		var p: Dictionary=source.port(id)
		return {"x":float(p.x),"y":float(p.y)} if not p.is_empty() else {}
	func active_fleet() -> Array:return source.active_fleet()
	func travel_speed() -> float:return source.travel_speed()
	func capacity() -> float:return source.capacity()
	func cargo_weight() -> float:return source.cargo_weight()
	func hull(id: String) -> Dictionary:return source.hull(id)
	func find_boat(id: String) -> Dictionary:return source.find_boat(id)
	func distance(a: Dictionary,b: Dictionary) -> float:return source.distance(a,b)
	func fail(message: String) -> Dictionary:return source.fail(message)

static func charter_view(c,p: Dictionary,target: Dictionary):
	if region(p)!=region(target):return null
	if region(p)==World.HOME:return c
	if region(p)!=Exploration.current_region(c.state) or not known_port(c,p) or not known_port(c,target):return null
	return CharterView.new(c,p)
