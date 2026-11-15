extends RefCounted

const Damage = preload("res://scripts/damage.gd")
const Economy = preload("res://scripts/economy.gd")
const Navigation = preload("res://scripts/navigation.gd")
const OceanWorld064 = preload("res://scripts/ocean_world064.gd")
const OceanCampaign066 = preload("res://scripts/ocean_campaign066.gd")
const ShippingFlow068 = preload("res://scripts/shipping_flow068.gd")
const SectorWorld069 = preload("res://scripts/sector_world069.gd")
const Routes = preload("res://scripts/route_cache.gd")
const Version = preload("res://scripts/version.gd")
const Goods = preload("res://scripts/goods.gd")
const Money = preload("res://scripts/money.gd")
const Harbor = preload("res://scripts/harbor.gd")
const Construction = preload("res://scripts/construction.gd")
const Fleets = preload("res://scripts/fleet_economy.gd")
const Contracts = preload("res://scripts/contracts.gd")
const CoastMigration=preload("res://scripts/coast_migration.gd")
const SaveValidation = preload("res://scripts/save_validation.gd")
const Expedition=preload("res://scripts/expedition.gd")
const VoyageCosts065=preload("res://scripts/voyage_costs065.gd")
const Manifest=preload("res://scripts/hold_manifest.gd")
const Exploration=preload("res://scripts/exploration.gd")
const Salvage=preload("res://scripts/salvage.gd")
const Remote067=preload("res://scripts/remote_expedition067.gd")
const VoyageJobs=preload("res://scripts/voyage_jobs.gd")
const CivilianWork=preload("res://scripts/civilian_work.gd")
const Contacts=preload("res://scripts/contacts.gd")
const CrisisOps=preload("res://scripts/crisis_ops.gd")
const BoardingOps=preload("res://scripts/boarding_ops.gd")
const LawOps=preload("res://scripts/law_ops.gd")
const CompanyOps=preload("res://scripts/company_ops.gd")
const RegionalGoodsOps=preload("res://scripts/civilian_goods_ops.gd")
const WorkerOps=preload("res://scripts/worker_ops.gd")
const YardDevelopment=preload("res://scripts/yard_development.gd")
const ToolingOps=preload("res://scripts/tooling_ops.gd")
const ReserveOps=preload("res://scripts/reserve_ops.gd")
const TrainingOps=preload("res://scripts/training_ops.gd")
const HomeOps=preload("res://scripts/home_ops.gd")
const RegionalOps=preload("res://scripts/regional_ops.gd")
const StoryOps=preload("res://scripts/story_ops.gd")
const Arc110=preload("res://scripts/campaign_arc110.gd")
const Arc111=preload("res://scripts/campaign_arc111.gd")
const Arc112=preload("res://scripts/campaign_arc112.gd")
const Arc113=preload("res://scripts/campaign_arc113.gd")
const Arc114=preload("res://scripts/campaign_arc114.gd")
const Arc115=preload("res://scripts/campaign_arc115.gd")
const Arc116=preload("res://scripts/campaign_arc116.gd")
const Arc117=preload("res://scripts/campaign_arc117.gd")
const Arc118=preload("res://scripts/campaign_arc118.gd")
const EscortOps=preload("res://scripts/escort_ops.gd")
const Objectives=preload("res://scripts/battle_objectives.gd")
const FleetIdentity=preload("res://scripts/fleet_identity.gd")
const FleetSupport=preload("res://scripts/fleet_support.gd")
const TradeIntel=preload("res://scripts/trade_intel.gd")
const TradeFlow=preload("res://scripts/trade_flow.gd")
const NavalAI=preload("res://scripts/naval_ai.gd")
const NavalLifecycle=preload("res://scripts/naval_lifecycle.gd")
const Politics=preload("res://scripts/politics.gd")
const Factions=preload("res://scripts/factions.gd")
# v0.002 modules owned by the Combat and Refit helpers (public contract only; root copies them in).
const Deployment = preload("res://scripts/deployment.gd")
const Refits = preload("res://scripts/refit.gd")
const Workshop = preload("res://scripts/fleet_workshop.gd")
const Preflight = preload("res://scripts/equipment_campaign.gd")
const Lifecycle = preload("res://scripts/equipment_lifecycle.gd")
# Ownership and traveling roster safety bounds are independent of battle deployment.
const MAX_FLEET = SaveValidation.MAX_ROSTER
const MAX_TRAVELING: int=48
const DAY_SECONDS = 45.0

var shipping
var crises
var route_cache: Dictionary={}
var route_hits: int=0
var route_misses: int=0
var data: Dictionary
var state: Dictionary = {}
var nav: Dictionary = {}
var events: Array = []
var pending_days: int = 0
var exploration_timer: float=0.0
var arc_follow_timer110: float=0.0
var sailing_clearance: float=0.0
var ocean_context064: Dictionary={}
var ocean_error064: String=""
var travel_lock064: String=""
var ocean_context066: Dictionary={}
var ocean_watch066: float=1.0
var ocean_conditions066: Array=[]
var ocean_anchors064: Dictionary={}
# Opt-in tooling timings for the last substep, in microseconds; never saved.
var trace_steps075: bool=false
var step_costs075: Dictionary={}

func _init(world_data: Dictionary,shared_navigation: Dictionary={},initialize_ocean: bool=true):
	data = world_data
	if shared_navigation.is_empty():
		for h in data.HULLS:
			h.price = Construction.quote(h).readyPrice
		nav = Navigation.create(data.ISLANDS,float(data.WORLD.width),float(data.WORLD.height),40.0*float(data.get("CAMPAIGN_SCALE",1.0)))
	else:
		# A paid recovery action can reuse this campaign's immutable navigation.
		# Quotes use a data facade and never construct another Campaign.
		nav=shared_navigation
	if not initialize_ocean:return
	var atlas=JSON.parse_string(FileAccess.get_file_as_string("res://data/ocean_regions064.json"))
	if atlas is Dictionary:
		ocean_anchors064=atlas.duplicate(true)
		var created: Dictionary=OceanWorld064.create(data,atlas,nav)
		ocean_context064=created.get("context",{})
		if not created.get("ok",false):ocean_error064=str(created.get("message","Ocean charts are unavailable."))
	else:ocean_error064="Ocean chart definitions are unavailable."
	if not ocean_context064.is_empty():
		var made066: Dictionary=OceanCampaign066.Travel.create(ocean_context064,1,null,OceanCampaign066.admitted_owner_ids(state))
		if made066.get("ok",false):ocean_context066=made066.context

func home_local064() -> bool:
	return Expedition.home_local064(state)

func world_location064() -> Dictionary:
	var location: Dictionary={"world064":{"schema":1,"layer":"home","regionId":"shatter_coast"}}
	for key in ["world064","position","heading","path","destination"]:
		if key=="world064" and not state.has(key):continue
		var value=state.get(key)
		location[key]=value.duplicate(true) if value is Dictionary or value is Array else value
	return location

func _publish_location064(location: Dictionary) -> void:
	for key in ["world064","position","heading","path","destination"]:
		state[key]=location[key].duplicate(true) if location[key] is Dictionary or location[key] is Array else location[key]

func world_view064() -> Dictionary:
	var result: Dictionary=_world_view_result064()
	return result.get("view",{}) if result.get("ok",false) else {}

func _world_view_result064() -> Dictionary:
	if state.is_empty():return fail("Start or restore a voyage before using the world chart.")
	if ocean_context064.is_empty():return fail(ocean_error064 if not ocean_error064.is_empty() else "Ocean charts are unavailable.")
	var boats: Array=[]
	for boat in active_fleet():
		# FleetArt054 reads only identity, eligibility, fitting geometry and engine.
		# Runtime refitting adds StringName member keys; publish explicit String
		# keys instead of passing a whole live boat through the strict plain view.
		var drawn: Dictionary={}
		for key in ["uid","type","sunk","hidden","visible","mothballed","storedPort","engine"]:
			if boat.has(key):drawn[key]=boat[key]
		var spec: Dictionary={}
		for key in ["id","role","size","tier","faction","weapon","fuelUse"]:
			if boat.spec.has(key):spec[key]=boat.spec[key]
		if boat.spec.has("weaponMounts"):
			if not boat.spec.weaponMounts is Array:return fail("Chart weapon mounts must be an array.")
			var mounts: Array=[]
			for mount in boat.spec.weaponMounts:
				if not mount is Dictionary:return fail("Chart weapon mounts must be records.")
				var shown: Dictionary={}
				for key in ["id","moduleId","kind","size","x","y","angle","arc"]:
					if mount.has(key):shown[key]=mount[key]
				mounts.append(shown)
			spec["weaponMounts"]=mounts
		drawn["spec"]=spec
		if boat.has("loadout"):
			if not boat.loadout is Dictionary:return fail("Chart loadout must be a fitting record.")
			if boat.loadout.has("engine"):drawn["loadout"]={"engine":boat.loadout.engine}
		boats.append(drawn)
	return OceanWorld064.view(ocean_context064,world_location064(),boats)

func _sailing_blocker064() -> String:
	if not state.get("toolingRecovery",{}).is_empty():return "Recall or finish the machinery recovery party before sailing away."
	if not state.get("exploration",{}).get("assignment",{}).is_empty():return "Recall your shore party before sailing away."
	if state.get("fleet",[]).any(func(b):return int(b.get("shoreCrew",0))>0):return "Recall every shore sailor before sailing away."
	if active_fleet().is_empty():return "Crew a boat before setting sail."
	if active_fleet().size()>MAX_TRAVELING:return "Store boats at a harbor: up to %d active boats may accompany one expedition."%MAX_TRAVELING
	if cargo_weight()>capacity()+0.001:return "The traveling holds are overloaded. Offload cargo or activate a carrier before sailing."
	return ""

func transition_blocker064() -> String:
	if not travel_lock064.is_empty():return travel_lock064
	var ocean_block: String=OceanCampaign066.blocker(self)
	if not ocean_block.is_empty():return ocean_block
	for event in events:
		if event.get("kind","") in ["encounter","defeat"]:return "Resolve the pending encounter before changing charts."
	var sailing: String=_sailing_blocker064()
	if not sailing.is_empty():return sailing
	if state.get("fleet",[]).any(func(b):return int(b.get("shoreCrew",0))>0):return "Recall every shore party before changing charts."
	if not state.get("civilianWork",{}).get("fishing",[]).is_empty():return "Recover the fishing gear before changing charts."
	for job in state.get("voyageJobs",[]):
		if job.get("kind","")=="passenger_charter" and int(job.get("passengers",{}).get("n",0))>0:return "Discharge the charter passengers before leaving coastal waters."
	for job in state.get("regionalCrises",{}).get("jobs",[]):
		if job.get("stage","")!="holding" and int(job.get("n",0))>0:return "Land the traveling civilian cohort before leaving coastal waters."
	if home_local064():
		for patrol in state.get("patrols",[]):
			var owner: Dictionary=fleet_owner(str(patrol.get("id","")))
			if owner.is_empty() or not owner.get("active",false) or not patrol.get("active",false) or not owner.get("boats",[]).any(func(b):return not b.get("sunk",false)):continue
			if not Politics.hostile(self,owner):continue
			if distance(state.position,patrol)<75.0:return "A hostile fleet is in direct contact. Clear the contact before changing charts."
			var order: Dictionary=owner.get("order",{})
			if str(owner.get("atPort","")).is_empty() and str(order.get("targetOwnerId",""))=="player" and str(order.get("purpose","")) in ["raid","intercept"] and owner.boats.any(func(b):return not b.get("sunk",false) and float(b.get("ammo",0))>0 and float(b.get("crew",0))>=float(b.get("crewMin",1))):return "A live hostile pursuit must be resolved before changing charts."
	return ""

func approach_course064(region_id: String,approach_id: String) -> Dictionary:
	var result: Dictionary=_world_view_result064()
	if not result.get("ok",false):return result
	var view: Dictionary=result.view
	var approaches: Array=view.get("approaches",[])
	if view.get("layer","")=="ocean":
		approaches=[]
		for region in view.get("regions",[]):approaches.append_array(region.get("approaches",[]))
	for approach in approaches:
		if str(approach.regionId)==region_id and str(approach.id)==approach_id:return chart_course(approach.position,"" if home_local064() else "approach:%s:%s"%[region_id,approach_id])
	return fail("Choose an approach on the current chart.")

func transition064(region_id: String,approach_id: String) -> Dictionary:
	if ocean_context064.is_empty():return fail(ocean_error064)
	var result: Dictionary=OceanWorld064.transition_player(ocean_context064,world_location064(),region_id,approach_id,Routes.clearance(self),transition_blocker064())
	if not result.get("ok",false):return result
	_publish_location064(result.location)
	sailing_clearance=Routes.clearance(self)
	ShippingFlow068.observe_sector069(self)
	return ok("Entered %s."%str(world_view064().get("name",region_id)))

func cached_path(a: Dictionary,b: Dictionary,clearance: float=10.0) -> Array:
	# Coast geometry is immutable for this Campaign instance. Cache exact numeric
	# endpoints, return detached paths, and cap entries so chart movement is bounded.
	var actual: float=Navigation.hull_clearance(clearance)
	for point in [a,b]:
		for coordinate in ["x","y"]:
			var value=point.get(coordinate)
			if not (value is int or value is float) or not is_finite(float(value)):return Navigation.find_path(nav,a,b,actual)
	var key: Array=[float(a.x),float(a.y),float(b.x),float(b.y),actual]
	if route_cache.has(key):route_hits+=1;return route_cache[key].duplicate(true)
	route_misses+=1
	var path: Array=Navigation.find_path(nav,a,b,actual)
	if route_cache.size()>=128:route_cache.erase(route_cache.keys()[0])
	route_cache[key]=path.duplicate(true)
	return path

func hull(id: String) -> Dictionary:
	for h in data.HULLS:
		if h.id == id:
			return h
	return {}

func port(id: String) -> Dictionary:
	for p in state.get("ports", []):
		if p.id == id:
			return p
	return {}

func faction(id: String) -> Dictionary:
	for f in data.FACTIONS:
		if f.id == id:
			return f
	return {}

func new_game(seed_value: int = 1) -> Dictionary:
	# Build the whole candidate and its runtime contexts off to the side. A failed
	# new career leaves the old voyage, pending economy, events and nav untouched.
	var candidate=get_script().new(data,nav,false)
	candidate.ocean_anchors064=ocean_anchors064
	var result: Dictionary=candidate._new_game069(seed_value)
	if result.get("ok",false):_publish_runtime069(candidate)
	return result

func _publish_runtime069(candidate) -> void:
	state=candidate.state;events=candidate.events;pending_days=candidate.pending_days
	route_cache=candidate.route_cache;route_hits=candidate.route_hits;route_misses=candidate.route_misses
	exploration_timer=candidate.exploration_timer;sailing_clearance=candidate.sailing_clearance
	ocean_context064=candidate.ocean_context064;ocean_error064=candidate.ocean_error064
	travel_lock064=candidate.travel_lock064;ocean_context066=candidate.ocean_context066
	ocean_watch066=candidate.ocean_watch066;ocean_conditions066=candidate.ocean_conditions066
	shipping=candidate.shipping;crises=candidate.crises

func _new_game069(seed_value: int) -> Dictionary:
	if seed_value<0 or float(seed_value)>SaveValidation.MAX_COINS:return fail("Choose a nonnegative saved campaign seed within the exact integer range.")
	var generated: Dictionary=SectorWorld069.generate(seed_value,data,ocean_anchors064)
	if not generated.get("ok",false):return fail(str(generated.get("message","The seeded sector could not be prepared.")))
	var world: Dictionary=OceanWorld064.create(data,generated.atlas,nav,generated.sector.harbors)
	if not world.get("ok",false):return fail(str(world.get("message","The seeded ocean charts could not be prepared.")))
	ocean_context064=world.context
	var prior_state: Dictionary = state
	var prior_pending: int = pending_days
	var prior_events: Array = events.duplicate(true)
	route_cache.clear();route_hits=0;route_misses=0
	sailing_clearance=0.0
	var start = data.START
	var ports: Array = []
	for definition in data.PORTS:
		var p = Economy.create_port(definition)
		p.shipStock = {}
		p.buildQueue = []
		p.industryProgress = 0.0
		for id in definition.get("shipIds", []):
			p.shipStock[id] = 1 if hull(id).tier <= 3 or definition.industry == "shipyard" else 0
		ports.append(p)
	var initial = Damage.create_ship(hull(start.hull), {"crew": start.crew, "ammo": start.ammo, "fuel": start.fuel, "supplies": start.supplies})
	initial.uid = "boat-1"
	initial.mothballed = false
	fit_boat(initial,true)
	var cargo: Dictionary = {}
	for good in Economy.GOODS:
		cargo[good] = float(start.food) if good == "food" else 0.0
	state = {"mapRevision":int(data.get("MAP_REVISION",1)),"format":2,"version":Version.text(),"seed":seed_value,"nextUid":2,"coins":int(start.coins),"crewPurse":int(start.crew)*Goods.SAILOR_WAGE*10,"wageArrears":0,"debt":0,"day":1.0,"econDay":1,"renown":0,"morale":85.0,"ports":ports,"fleet":[initial],"cargo":cargo,"position":port_position(start.port),"heading":0.0,"path":[],"destination":"","lastPort":start.port,"flagship":initial.uid,"missionIndex":0,"activeContract":{},"freight":{},"doneSide":[],"wins":0,"losses":0,"kills":0,"completed":false,"patrols":[],"fleetOwners":[],"log":[],"moneyLog":[],"recoverable":{},"encounterGrace":90.0,"coinSupply":0}
	if not ocean_context064.is_empty():state.world064={"schema":1,"layer":"home","regionId":"shatter_coast"}
	travel_lock064=""
	state["ocean066"]=OceanCampaign066.empty_book()
	ocean_watch066=1.0;ocean_conditions066=[]
	if not ocean_context064.is_empty():
		var made066: Dictionary=OceanCampaign066.Travel.create(ocean_context064,seed_value,null,OceanCampaign066.admitted_owner_ids(state))
		if not made066.get("ok",false):return fail(str(made066.get("message","The seeded ocean actor context was refused.")))
		ocean_context066=made066.context
	var home: Dictionary = port(start.port)
	home.workforce = maxi(0,int(home.workforce)-int(start.crew))
	home.recruits = maxi(0,int(home.recruits)-int(start.crew))
	Economy.sync_workforce(home)
	state.fleetOwners = Fleets.create_owners(ports,data)
	for i in range(data.MISSIONS.size()):
		var mission: Dictionary = data.MISSIONS[i]
		var boats: Array = []
		for id in mission.enemyHulls:
			boats.append(Damage.create_ship(hull(id)))
		var base: Dictionary = port("shatter_spire")
		var owner: Dictionary = {"id":"story-%d"%i,"name":"Blockade detachment %d"%(i+1),"kind":"raider","homePort":base.id,"faction":"raiders","coins":0,"crewPurse":0,"wageArrears":0,"morale":85.0,"cargo":{},"tradeCargo":0,"boats":boats,"active":true,"route":[base.id,mission.targetPort],"progress":0.0,"atPort":base.id,"log":[]}
		var capital: int = 0
		for b in boats:
			capital += int(b.crew)*Goods.SAILOR_WAGE*45
			base.workforce = maxi(0,int(base.workforce)-int(b.crew))
			base.availableWorkers = maxi(0,int(base.availableWorkers)-int(b.crew))
		Money.move(base,"governmentPurse",owner,"coins",mini(capital,int(base.governmentPurse)),"Blockade operating purse",state.moneyLog)
		state.fleetOwners.append(owner)
	pending_days = 0
	for i in range(9):
		var initial_owner: Dictionary=fleet_owner("patrol-%d"%i)
		var route: Array=initial_owner.get("route",data.ROUTES[(i * 3 + 1) % data.ROUTES.size()])
		var a = port(route[0])
		var b = port(route[1])
		var t = float(i % 5) / 5.0
		var patrol: Dictionary = {"id": "patrol-%d" % i, "name": "Reef raiders" if i % 3 == 0 else "Coastal convoy", "hostile": i % 3 == 0, "active": true, "from": a.id, "to": b.id, "x": a.x, "y": a.y, "progress": t, "strength": 1 + i % 3}
		set_patrol_course(patrol,a,b)
		place_patrol(patrol)
		state.patrols.append(patrol)
		var owner: Dictionary = fleet_owner("patrol-%d"%i)
		if not owner.is_empty():
			Fleets.dock(owner,port(owner.homePort))
			owner.atPort = ""
	# Preserve HOME reserve routes before adding unrelated local coordinate spaces.
	ReserveOps.ensure(self)
	RegionalOps.ensure(self)
	var opening069: Dictionary=ShippingFlow068.install_sector069(self,generated.sector)
	if not opening069.get("ok",false):return opening069
	state.coinSupply = Money.total(state)
	VoyageJobs.ensure(self)
	Contacts.ensure(state,data)
	Politics.ensure(self)
	NavalAI.ensure(state,data)
	TradeIntel.ensure(state)
	FleetIdentity.ensure(state)
	StoryOps.ensure(self)
	HomeOps.ensure(self)
	RegionalOps.ensure(self)
	TrainingOps.ensure(self)
	ReserveOps.ensure(self)
	ToolingOps.ensure(self)
	YardDevelopment.ensure(self)
	WorkerOps.ensure(self)
	RegionalGoodsOps.ensure(self)
	CompanyOps.ensure(self)
	if not state.get("campaignFacts") is Dictionary:state.campaignFacts={"escortsSaved":0,"goodsDelivered":0,"bountyWins":0,"licensedDesigns":0}
	if not state.get("escortEvents") is Dictionary:state.escortEvents={}
	if not state.has("battleSeq"):state.battleSeq=0
	state.cargoManifest={}
	state.surveyFoodCredit=0.0
	state.wreckHazards={}
	state.blueprints={}
	state.fitTemplates=[]
	state.defeatedOwners={}
	Salvage.ensure(state)
	if int(data.get("MAP_REVISION",1))>=2:
		Exploration.ensure(state,data)
		Exploration.discover_near(state,state.position,1000.0)
	else:state.exploration={"version":1,"catalog":[],"sites":{},"assignment":{},"leads":[],"log":[]}
	BoardingOps.ensure(self)
	CrisisOps.ensure(self)
	LawOps.ensure(self)
	var built: Dictionary = state
	var published: Dictionary = publish_career(built, prior_state, prior_pending, prior_events)
	if not published.ok:
		return published
	# Orders were initialized before final canonical fittings. Refresh only
	# their derived observations; do not repeat routes, payroll or AI setup.
	var by_owner: Dictionary = state.navalAi.ordersByOwner
	for owner in state.fleetOwners:
		if owner is Dictionary and owner.get("order") is Dictionary and not owner.order.is_empty():
			NavalAI.refresh_order_stats(owner, owner.order)
			by_owner[str(owner.get("id", ""))] = owner.order
	Manifest.allocate(state)
	ShippingFlow068.install(self)
	log_entry("You inherited a Tinwake skiff, five sailors, and a debt-free start. The coast is yours to explore.")
	log_entry(str(opening069.message)+" Public settled charts accompany the new campaign; frontier and remote findings must be earned.")
	events.clear()
	return published

func port_position(id: String) -> Dictionary:
	for p in data.PORTS:
		if p.id == id:
			return {"x": p.x, "y": p.y}
	return {"x": 495.0, "y": 1240.0}

func set_patrol_course(patrol: Dictionary, a: Dictionary, b: Dictionary):
	# Precompute once per voyage/load; never pathfind or simulate water per frame.
	var actual: float=Routes.clearance(self,patrol)
	var start: Dictionary=a
	if not str(a.get("id","")).is_empty() and not port(str(a.id)).is_empty():
		start=Navigation.harbor_approach(nav,a,actual,40.0)
	var endpoint: Dictionary=Navigation.harbor_approach(nav,b,actual,40.0)
	patrol.course=[] if start.is_empty() or endpoint.is_empty() else cached_path(start,endpoint,actual)
	patrol.courseClearance=actual
	patrol.courseLength = 0.0
	for i in range(1,patrol.course.size()):
		patrol.courseLength += distance(patrol.course[i-1],patrol.course[i])
	if patrol.course.is_empty():
		NavalLifecycle.refuse_route(self,patrol,"No safe harbor approach or water route for a hull this size (%.0f clearance)."%actual)
	else:patrol.routeFailure=""

func remaining_patrol_course(patrol: Dictionary) -> Array:
	var remaining: Array=[]
	var left: float=float(patrol.get("progress",0))*float(patrol.get("courseLength",0))
	var course: Array=patrol.get("course",[])
	for i in range(1,course.size()):
		var length: float=distance(course[i-1],course[i])
		if left<=length:
			remaining.append_array(course.slice(i))
			break
		left-=length
	return remaining

func place_patrol(patrol: Dictionary):
	var left: float = patrol.progress*patrol.courseLength
	for i in range(1,patrol.course.size()):
		var a: Dictionary = patrol.course[i-1]
		var b: Dictionary = patrol.course[i]
		var length: float = distance(a,b)
		if left <= length or i == patrol.course.size()-1:
			var fraction: float = clampf(left/maxf(0.001,length),0.0,1.0)
			patrol.x = lerpf(a.x,b.x,fraction)
			patrol.y = lerpf(a.y,b.y,fraction)
			return
		left -= length

func active_fleet() -> Array:
	var fleet: Array = []
	for s in state.get("fleet", []):
		if not s.sunk and not s.get("mothballed", false) and not s.get("needsHarborRepair",false) and str(s.get("storedPort","")).is_empty() and s.crew >= s.crewMin:
			fleet.append(s)
	fleet.sort_custom(func(a, b): return a.uid == state.flagship and b.uid != state.flagship)
	return fleet

func capacity() -> float:
	return Expedition.capacity(state)

func cargo_weight() -> float:
	return Expedition.cargo_weight(state)

func expedition_report(route_distance: float=0.0) -> Dictionary:
	return Expedition.report(state,data,route_distance,travel_speed())

## Review never joins economy, normalizes equipment or allocates live holds.
## The existing speed/status, clearance and transition predicates are reads.
func voyage_quote065(intent: Dictionary={}) -> Dictionary:
	var snapshot: Dictionary=state.duplicate(true)
	# Itinerary simulation may activate a destination's coarse grid. Keep those
	# runtime slot assignments off the live travel context; immutable geometry,
	# HOME/Glasswind nav and the current generated grid remain shared read-only.
	var quote_context: Dictionary=ocean_context064.duplicate()
	var runtime: Dictionary={"speed":travel_speed(),"clearance":Routes.clearance(self),"blocker":transition_blocker064()}
	if not ocean_context066.is_empty():
		var ocean: Dictionary=ocean_context066.duplicate()
		ocean["world064Context"]=quote_context
		runtime["ocean066"]=ocean
	return VoyageCosts065.quote(snapshot,data,quote_context,intent.duplicate(true),runtime)

func ocean_view066() -> Dictionary:
	return OceanCampaign066.view(self)

## Detached knowledge/marker DTO; no quotes, navigation or live normalization.
func exploration_view067() -> Dictionary:
	return Remote067.view(self)

func contact_action066(id: String,action: String) -> Dictionary:
	return OceanCampaign066.action(self,id,action)

func resume_voyage066() -> Dictionary:
	return OceanCampaign066.action(self,"","resume")

func encounter_context066(id: String) -> Dictionary:
	return OceanCampaign066.encounter(self,id)

func freight_weight() -> float:
	var freight = state.get("freight", {})
	if freight.is_empty():
		return 0.0
	return freight.qty * Economy.GOODS[freight.good].weight

func crew_count() -> int:
	var result = 0
	for s in state.get("fleet", []):
		if not s.sunk:
			result += int(s.crew)
	return result

func current_port() -> Dictionary:
	if state.is_empty() or not home_local064():
		return {}
	for p in state.ports:
		if str(p.get("regionId","shatter_coast"))!="shatter_coast":continue
		if distance(state.position, p) < 65.0:
			return p
	return {}

## Work alone may use a known non-HOME harbor. Return its authoritative live
## account, never the detached market DTO; current_port keeps gating HOME services.
func work_port070() -> Dictionary:
	if state.is_empty() or not state.get("path",[]).is_empty():return {}
	if home_local064():return current_port()
	var gate: Dictionary=ShippingFlow068.remote_gate(self)
	return gate.port if gate.get("ok",false) else {}

func _work_permission070() -> Dictionary:
	var dock: Dictionary=work_port070()
	if dock.is_empty():return fail("Stop at a known harbor's actual work berth first.")
	# Permission previews must not normalize the live faction book on refusal.
	var policy: Dictionary={"day":state.day,"relationships":state.get("relationships",{}).duplicate(true)}
	var access: Dictionary=Politics.access({"state":policy,"data":data},dock)
	if not access.get("legal",false):return fail(str(access.get("reason","Harbor entry is refused.")))
	if not access.get("contracts",false):return fail("This harbor has suspended your contracts.")
	return ok(str(access.get("reason","Harbor work is permitted.")))

func shipping_view068() -> Dictionary:
	return ShippingFlow068.view(self)

func sector_view069() -> Dictionary:
	return ShippingFlow068.sector_view069(self)

func remote_port068(port_id: String="") -> Dictionary:
	return ShippingFlow068.remote_view(self,port_id)

func remote_trade068(good: String,qty: int,side: String,port_id: String="") -> Dictionary:
	return ShippingFlow068.market(self,good,qty,side,port_id)

func distance(a: Dictionary, b: Dictionary) -> float:
	return Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y))

func travel_speed() -> float:
	var fleet = active_fleet()
	if fleet.is_empty():
		return 0.0
	var speed = 170.0
	for s in fleet:
		speed = minf(speed, s.spec.speed * maxf(0.25, Damage.get_status(s).speedFactor) * (1.0 if s.fuel > 0 else 0.3))
	var powered_mass: float=0.0
	var tow_mass: float=0.0
	var tow_factor: float=1.0
	for s in state.fleet:
		if s.sunk or not str(s.get("storedPort","")).is_empty():continue
		if s.get("mothballed",false) or s.crew<s.crewMin or s.get("needsHarborRepair",false):tow_mass+=float(s.spec.size)
		else:powered_mass+=float(s.spec.size)
		if s.get("towed",false):
			var best_tug: float=0.55
			for tug in fleet:best_tug=maxf(best_tug,float(tug.spec.get("towSpeedFactor",0.55)))
			tow_factor=minf(tow_factor,maxf(best_tug,float(s.get("towSpeedFactor",0.55))))
	return Arc118.follow_speed(self,Arc117.follow_speed(self,Arc116.follow_speed(self,Arc112.follow_speed(self,Arc110.follow_speed(self,speed*1.55*float(data.get("CAMPAIGN_SCALE",1.0))*powered_mass/maxf(1,powered_mass+tow_mass*0.8)*tow_factor)))))

func chart_course(target: Dictionary, destination: String = "") -> Dictionary:
	if destination==ShippingFlow068.PORT and (not ShippingFlow068.installed(state) or ShippingFlow068.PORT not in state.get("shipping068",{}).get("knownPorts",[])):
		return fail("Sight the actual Westglass harbor before selecting its berth.")
	var generated_harbor: Dictionary=ShippingFlow068.definition069(state,destination)
	if not generated_harbor.is_empty() and not ShippingFlow068.known069(state,destination):return fail("Observe this canonical harbor or obtain its public chart before selecting the berth.")
	var selected_port: Dictionary=port(destination) if not destination.is_empty() else {}
	if not selected_port.is_empty() and str(selected_port.get("regionId","shatter_coast"))!="shatter_coast":
		if state.get("world064",{}).get("layer")!="local" or state.world064.get("regionId")!=selected_port.regionId:return fail("Enter this harbor's local chart before plotting its water berth.")
	var blocked: String=_sailing_blocker064()
	if not blocked.is_empty():return fail(blocked)
	Manifest.allocate(state)
	var actual: float=Routes.clearance(self)
	if not home_local064() or destination.begins_with("approach:"):
		if ocean_context064.is_empty():return fail(ocean_error064)
		var plotted: Dictionary=OceanCampaign066.diverted(self,target,destination) if not ocean_context066.is_empty() else OceanWorld064.plot(ocean_context064,world_location064(),target,destination,actual)
		if not plotted.get("ok",false):return plotted
		_publish_location064(plotted.location)
		if plotted.has("memory"):state.ocean066["memory"]=plotted.memory
		sailing_clearance=actual
		return ok("Course set for the selected approach." if destination.begins_with("approach:") else "Course set for open water.")
	var endpoint: Dictionary=Routes.endpoint(self,port(destination) if not destination.is_empty() else target,actual)
	if endpoint.is_empty():return fail("No safe harbor approach for a hull this size (%.0f clearance)."%actual)
	var path = cached_path(state.position,endpoint,actual)
	if path.is_empty():
		return fail("No safe water route for a hull this size (%.0f clearance). Choose a harbor or open water."%actual)
	path.pop_front()
	var departure: Dictionary=current_port()
	if not departure.is_empty():state.regionalOrigin=str(departure.id)
	Arc110.cancel_follow(self)
	Arc112.cancel_follow(self)
	Arc116.cancel_follow(self)
	Arc117.cancel_follow(self)
	Arc118.cancel_follow(self)
	state.path = path
	state.destination = destination
	sailing_clearance=actual
	return ok("Course set for %s." % (port(destination).get("name", "open water")))

func validate_sailing_route() -> bool:
	var actual: float=Routes.clearance(self)
	if state.get("path",[]).is_empty() or is_equal_approx(sailing_clearance,actual):return true
	sailing_clearance=actual
	if not home_local064():
		var checked: Dictionary=OceanWorld064.prepare(world_location064(),ocean_context064,actual)
		if checked.get("ok",false):return true
	else:
		if Navigation.path_clear(nav,state.position,state.path,actual):return true
	stop_sailing()
	log_entry("Course stopped: no safe water route for a hull this size (%.0f clearance). Position unchanged."%actual)
	return false

func stop_sailing():
	Arc110.cancel_follow(self)
	Arc112.cancel_follow(self)
	Arc116.cancel_follow(self)
	Arc117.cancel_follow(self)
	Arc118.cancel_follow(self)
	state.path = []
	state.destination = ""

func step(dt: float):
	if state.is_empty() or not is_finite(dt) or dt<=0.0:return
	# Existing public callers use4. Larger waits are bounded, never pre-booked.
	if dt>DAY_SECONDS:
		log_entry("Advance refused: choose a bounded day or sailing interval.");return
	var left: float=dt
	while left>0.00000001:
		var requested: float=minf(4.0,left)
		var accepted: float=_step066(requested)
		if accepted<0.0:return
		left-=accepted
		if accepted<requested or events.any(func(e):return e.get("kind","") in ["encounter","ocean_encounter066","defeat"]):return

func _step066(dt: float) -> float:
	if state.is_empty():
		return 0.0
	var trace_mark075: int=Time.get_ticks_usec() if trace_steps075 else 0
	var staged: Dictionary=OceanCampaign066.stage(self,dt)
	if trace_steps075:
		step_costs075={"ocean_stage_us":Time.get_ticks_usec()-trace_mark075}
		trace_mark075=Time.get_ticks_usec()
	if not staged.get("ok",false):log_entry(str(staged.get("message","Ocean movement refused.")));return -1.0
	dt=float(staged.acceptedSeconds)
	# No clock, damage, fuel, home AI or survey publication precedes clipping.
	OceanCampaign066.commit(self,staged)
	state.encounterGrace = maxf(0.0, state.encounterGrace - dt)
	exploration_timer+=dt
	if exploration_timer>=0.5 and int(data.get("MAP_REVISION",1))>=2 and (home_local064() or Remote067.local(state)):
		exploration_timer=0.0
		for site in Exploration.discover_near(state,state.position,620.0):
			log_entry("Sighted %s. Open Island charts (I) to investigate."%site.name)
		ShippingFlow068.observe_sector069(self)
	advance_surveys(dt/DAY_SECONDS)
	var voyage_before: Dictionary=state.position.duplicate()
	if not Arc118.active(self).is_empty():
		Arc118.follow_step(self,dt)
	elif not Arc117.active(self).is_empty():
		Arc117.follow_step(self,dt)
	elif not Arc116.work(self).is_empty() and not Arc116.work(self).get("reported",false):
		Arc116.follow_step(self,dt)
	elif not Arc112.work(self).is_empty() and not Arc112.work(self).get("reported",false):
		Arc112.follow_step(self,dt)
	else:
		Arc110.follow_step(self,dt)
	validate_sailing_route()
	var moving: bool = not state.path.is_empty()
	var voyage_distance: float=0.0
	if not home_local064():
		moving=false
		for move in staged.locations:
			if str(move.ownerId)=="player":moving=bool(move.moving);voyage_distance=float(move.distance)
	elif moving:
		var step_left = travel_speed() * dt
		while step_left > 0 and not state.path.is_empty():
			var target = state.path[0]
			var delta = Vector2(target.x - state.position.x, target.y - state.position.y)
			var d = delta.length()
			state.heading = delta.angle()
			if d <= step_left:
				state.position = {"x": target.x, "y": target.y}
				state.path.pop_front()
				step_left -= d
			else:
				var v = delta / d * step_left
				state.position.x += v.x
				state.position.y += v.y
				step_left = 0.0
		if state.path.is_empty() and not state.destination.is_empty() and not state.destination.begins_with("approach:"):
			state.lastPort = state.destination
			events.append({"kind": "arrival", "port": state.destination})
			var arrival114: String=str(state.destination)
			state.destination = ""
			if distance(voyage_before,state.position)>0.000001:Arc114.arrived(self,port(arrival114))
	if home_local064():voyage_distance=distance(voyage_before,state.position)
	CrisisOps.step(self,voyage_distance)
	for s in state.fleet:
		if s.sunk or not str(s.get("storedPort","")).is_empty():
			continue
		s.supportRepairFactor=FleetSupport.repair_factor(self)
		Damage.tick_ship(s, dt, {"inCombat": false})
		if moving and not s.get("mothballed", false):
			s.fuel = maxf(0.0, s.fuel - dt * (0.011 + s.spec.size * 0.0002) * maxf(0.2,float(s.spec.get("fuelUse",1.0))))
		if s.sunk:
			if not home_local064():Salvage.record_battle(self,{"ships":[s],"chartPosition":state.position,"world064":world_location064().world064},"voyage-loss:"+str(s.uid))
			log_entry("%s was lost to flooding." % s.name)
	BoardingOps.step(self,dt)
	CrisisOps.losses(self)
	BoardingOps.reconcile(self)
	FleetSupport.reconcile(self)
	for lost in Manifest.losses(state):log_entry("Lost %.1f %s aboard %s."%[lost.qty,lost.good,lost.boat])
	state.fleet = state.fleet.filter(func(s): return not s.sunk)
	if not state.fleet.is_empty() and not state.fleet.any(func(b):return str(b.uid)==str(state.flagship)):state.flagship=str(state.fleet[0].uid)
	if state.fleet.is_empty():
		events.append({"kind": "defeat"})
	var old_day: int = int(state.day)
	state.day += dt / DAY_SECONDS
	if int(state.day) > old_day:
		pending_days += int(state.day) - old_day
	LawOps.clock(self)
	CivilianWork.tick(self,dt/DAY_SECONDS)
	if trace_steps075:
		step_costs075["commit_player_us"]=Time.get_ticks_usec()-trace_mark075
		trace_mark075=Time.get_ticks_usec()
	NavalLifecycle.step(self,dt)
	LawOps.check_patrols(self)
	if trace_steps075:
		step_costs075["naval_lifecycle_patrol_check_us"]=Time.get_ticks_usec()-trace_mark075
		trace_mark075=Time.get_ticks_usec()
	OceanCampaign066.after_step(self,bool(staged.watchDue))
	if trace_steps075:
		step_costs075["ocean_after_step_us"]=Time.get_ticks_usec()-trace_mark075
		trace_mark075=Time.get_ticks_usec()
	ShippingFlow068.after_step(self,bool(staged.watchDue))
	if trace_steps075:
		step_costs075["shipping_after_step_us"]=Time.get_ticks_usec()-trace_mark075
	if not staged.encounter.is_empty() and not state.fleet.is_empty():
		var attacker: String=str(staged.encounter.get("attackerId",""))
		var defender: String=str(staged.encounter.get("defenderId",""))
		if attacker=="player" or defender=="player":
			stop_sailing()
			events.append({"kind":"ocean_encounter066","ownerId":defender if attacker=="player" else attacker})
		else:ShippingFlow068.resolve_encounter(self,staged.encounter)
	return dt

func apply_economy(ports: Array, messages: Array, days: int):
	state.ports = ports
	for message in messages.slice(0,3):
		log_entry(str(message))
	for i in range(days):
		var costs: Dictionary = Economy.daily_upkeep(state.fleet)
		var due: int = int(costs.wages)
		var paid: int = mini(int(state.coins),due)
		Money.move(state,"coins",state,"crewPurse",paid,"Captain pays sailors",state.moneyLog)
		state.wageArrears += due-paid
		ToolingOps.paid_day(self,paid,due)
		RegionalOps.paid_day(self,paid,due)
		if paid < due:
			state.morale = maxf(10.0,state.morale-8.0)
			log_entry("Crew wages short by %d coins. Unpaid wages accumulate and morale falls."%(due-paid))
		elif state.wageArrears == 0:
			state.morale = minf(100.0,state.morale+1.0)
		var food_need: float = float(costs.food)
		var prepaid: float=minf(food_need,float(state.get("surveyFoodCredit",0)))
		state.surveyFoodCredit=maxf(0,float(state.get("surveyFoodCredit",0))-prepaid)
		food_need-=prepaid
		if state.cargo.food >= food_need:
			state.cargo.food -= food_need
		else:
			state.cargo.food = 0.0
			state.morale = maxf(10.0,state.morale-5.0)
			log_entry("Rations exhausted. Buy food at a harbor.")
		var dock: Dictionary = current_port()
		if not dock.is_empty():
			Money.move(state,"crewPurse",dock,"cash",mini(int(state.crewPurse),crew_count()*12),"Sailors spend ashore",state.moneyLog)
		for p in state.ports:
			Construction.begin_day(p)
		for message in Fleets.tick(state.fleetOwners,state.ports,1.0,self).slice(0,2):
			log_entry(str(message))
		OceanCampaign066.record_losses(self)
		ShippingFlow068.daily(self)
		for message in FleetIdentity.tick(self,1):log_entry(str(message))
		YardDevelopment.daily(self)
		Harbor.tick_yards(self,1)
		RegionalOps.begin_day(self)
		NavalLifecycle.daily(self)
		CompanyOps.daily(self)
		TradeFlow.daily(self)
		StoryOps.daily(self)
		ToolingOps.Tooling.daily(self)
		HomeOps.daily(self)
		RegionalOps.daily(self)
		ReserveOps.refresh(self)
		VoyageJobs.ensure(self)
		VoyageJobs._expire_overdue(self,state)
		BoardingOps.daily(self)
		CrisisOps.daily(self)
		LawOps.daily(self)
		state.econDay += 1
	apply_morale()
	Manifest.allocate(state)
	for patrol in state.patrols:
		if NavalAI.NavalOrders.enrolled066(state,str(patrol.get("id",""))):continue
		var owner: Dictionary = fleet_owner(patrol.id)
		if not owner.is_empty():
			patrol.active = owner.active and owner.boats.any(func(b):return not b.sunk)
	if Money.total(state) != int(state.coinSupply):
		push_error("Coin conservation failed: %d != %d"%[Money.total(state),state.coinSupply])

func apply_morale():
	var factor: float = clampf(state.morale/85.0,0.35,1.0)
	for boat in state.fleet:
		_apply_boat_morale(boat, factor)

func _apply_boat_morale(boat: Dictionary, factor: float) -> void:
	# Morale scales the canonical fitted design, never a stale or serialized spec.
	var base: Dictionary = FleetIdentity.effective(boat,fitted_spec(boat))
	boat.spec=base.duplicate(true)
	boat.economyFactor = factor
	boat.spec.speed = float(base.speed)*factor
	boat.spec.fireRate = float(base.fireRate)*factor
	var mounts = base.get("weaponMounts")
	var live = boat.spec.get("weaponMounts")
	if mounts is Array and live is Array and mounts.size() == live.size():
		for i in range(mounts.size()):
			if mounts[i] is Dictionary and live[i] is Dictionary and mounts[i].has("fireRate"):
				live[i].fireRate = float(mounts[i].fireRate)*factor

func pay_wage_arrears() -> Dictionary:
	var amount: int = mini(int(state.coins),int(state.wageArrears))
	if amount <= 0:
		return fail("No payable crew arrears, or your purse is empty.")
	Money.move(state,"coins",state,"crewPurse",amount,"Captain settles unpaid wages",state.moneyLog)
	state.wageArrears -= amount
	state.morale = minf(100.0,state.morale+10.0)
	apply_morale()
	return ok("Paid %d coins of owed wages into the sailors' purse."%amount)

func repay_loan(amount: int = 5000) -> Dictionary:
	var payment: int = mini(amount,mini(int(state.coins),int(state.debt)))
	if payment <= 0:
		return fail("No payable harbor loan.")
	Money.move(state,"coins",port(data.START.port),"governmentPurse",payment,"Repayment to harbor treasury",state.moneyLog)
	state.debt -= payment
	return ok("Repaid %d coins to Brass Haven."%payment)

func fleet_owner(id: String) -> Dictionary:
	for owner in state.get("fleetOwners",[]):
		if owner.id == id:
			return owner
	return {}

func wait_day():
	step(DAY_SECONDS)

func begin_survey(site_id: String, action: String) -> Dictionary:
	for work in ["improvement","control"]:
		if not state.get("territorial076",{}).get(work,{}).get("crewByBoat",{}).is_empty():
			return fail("Withdraw the harbor work party before assigning a survey.")
	if not home_local064():return Remote067.survey_begin(self,site_id,action)
	if not state.get("toolingRecovery",{}).is_empty():return fail("Recall the machinery recovery party before assigning a survey.")
	var site: Dictionary=Exploration.catalog_site(state,site_id)
	if site.is_empty() or distance(state.position,site)>180:return fail("Approach within180water units of this landing first.")
	if not state.path.is_empty():return fail("Stop the fleet before landing your survey party.")
	var result: Dictionary=Exploration.begin(state,site_id,action)
	if not result.ok:return result
	state.surveyFoodCredit=float(state.get("surveyFoodCredit",0))+float(result.food)
	var left: int=int(result.crewNeeded)
	for b in active_fleet():
		var assigned: int=mini(left,maxi(0,int(b.crew)-ceili(b.wounded)-int(b.crewMin)))
		b.shoreCrew=assigned
		left-=assigned
	Manifest.allocate(state)
	log_entry("Landed %d sailors at %s; wages continue and assigned hands cannot man the boats."%[result.crewNeeded,result.siteName])
	return result

func recall_survey() -> Dictionary:
	if state.exploration.assignment.is_empty():return fail("No shore party is assigned.")
	var regional_error: String=Remote067.party_error(state)
	if not regional_error.is_empty():return fail(regional_error)
	state.exploration.assignment={}
	for b in state.fleet:b.shoreCrew=0
	state.cargo.food+=float(state.get("surveyFoodCredit",0))
	state.surveyFoodCredit=0.0
	Manifest.allocate(state)
	return ok("Party recalled; unused prepaid rations returned. Survey tools already used are spent.")

func advance_surveys(days: float) -> void:
	if int(data.get("MAP_REVISION",1))<2:return
	var remote: bool=Remote067.local(state)
	if not home_local064() and (not remote or not Remote067.party_error(state).is_empty()):return
	for event in Exploration.advance(state,days):
		for b in state.fleet:b.shoreCrew=0
		if remote:
			state.cargo.food+=float(state.get("surveyFoodCredit",0))
			state.surveyFoodCredit=0.0
			Manifest.allocate(state)
		log_entry("%s: %s. %s"%[event.siteName,event.levelName,event.discovery])
		events.append(event)
		FleetIdentity.record_service(self,active_fleet().map(func(b):return b.uid),"survey")
		StoryOps.refresh(self)
		var lead: String=str(event.get("leadId",""))
		var next: Dictionary=Exploration.catalog_site(state,lead)
		if not remote and not next.is_empty():Exploration.discover_near(state,next,1.0)
		if int(event.level)>=3:
			var found: Dictionary=Exploration.catalog_site(state,event.siteId)
			if remote and Exploration.current_region(state)=="glasswind_keys":Salvage.seed_expedition067(self,Exploration.catalog_site(state,"glasswind_south_wreck"))
			elif str(found.get("kind","")) in ["wreck_field","salvage_anchorage"]:Salvage.seed_site_wreck(self,found,"harbor_sloop")
			if not remote and str(found.get("kind",""))=="workshop_ruin":
				state.blueprints["manta_strike"]=true
				log_entry("Recovered Manta Strike workshop drawings. License them at a shipyard to unlock paid construction.")

func license_blueprint(id: String) -> Dictionary:
	var p: Dictionary=current_port()
	if p.is_empty() or p.industry!="shipyard" or not state.blueprints.get(id,false) or hull(id).is_empty():return fail("Take a recovered hull drawing to a shipyard.")
	if not id in p.shipIds:
		p.shipIds.append(id)
		state.campaignFacts.licensedDesigns=int(state.campaignFacts.get("licensedDesigns",0))+1
	return ok("Design licensed at %s. The yard still requires physical materials, workers, expert wages and coins."%p.name)

func recovery_days(weight: float) -> float:
	return maxf(0.1,weight/maxf(1,Exploration.spare_crew(state)*20.0))

func _recovery_gate(snapshot: Dictionary,id: String,mode: String) -> String:
	if not Expedition.home_local064(snapshot):return Remote067.recovery_gate(self,snapshot,id,mode)
	var w: Dictionary={}
	for row in snapshot.get("wrecks",[]):
		if row is Dictionary and str(row.get("id",""))==id:w=row;break
	if not Expedition.home_local064(w):return "This wreck belongs to another chart; its position is retained for a later voyage."
	for point in [snapshot.get("position",{}),w]:
		if not point is Dictionary or not Salvage._is_num(point.get("x")) or not Salvage._is_num(point.get("y")):return "This recovery has no finite chart position."
	if w.is_empty() or distance(snapshot.get("position",{}),w)>180:return "Approach this wreck within180water units first."
	for owner in snapshot.get("fleetOwners",[]):
		if str(owner.get("id",""))==str(snapshot.get("wreckHazards",{}).get(w.get("sourceId",""),"")):
			if owner.get("active",false) and owner.get("boats",[]).any(func(b):return not b.get("sunk",false)):return "Hostiles still control this wreck field. Secure the waters before recovery."
	if not snapshot.get("path",[]).is_empty() or not snapshot.get("exploration",{}).get("assignment",{}).is_empty() or not snapshot.get("toolingRecovery",{}).is_empty():return "Stop the fleet and recall shore parties before recovery."
	if mode in ["strip","gear"] and Exploration.spare_crew(snapshot)<1:return "Recovery needs at least one spare able sailor above the boat minimums."
	return ""

func _gear_work_quote(q: Dictionary,snapshot: Dictionary) -> Dictionary:
	var spare: int=0
	for boat in Expedition.traveling(snapshot):
		spare+=maxi(0,int(boat.get("crew",0))-ceili(float(boat.get("wounded",0)))-int(boat.get("crewMin",1))-int(boat.get("shoreCrew",0)))
	# A selected dismantling job books whole normal payroll days. This is the
	# existing recovery_days effort, rounded up, never an unpaid fractional click.
	var effort: float=maxf(recovery_days(float(q.get("weight",0))),float(q.get("weight",0))/maxf(1,spare*20.0))
	var work: float=ceilf(effort)
	var payroll: int=maxi(0,pending_days)+int(work)
	var upkeep: Dictionary=Economy.daily_upkeep(snapshot.get("fleet",[]))
	var premiums: int=FleetSupport.premium(snapshot)
	var arrears: int=int(snapshot.get("wageArrears",0))+FleetSupport.premium(snapshot,true)
	var wages: int=(int(upkeep.wages)+premiums)*payroll
	var food: float=maxf(0,float(upkeep.food)*payroll-float(snapshot.get("surveyFoodCredit",0)))
	q.merge({"workDays":work,"effortDays":effort,"payrollDays":payroll,
		"wages":wages,"arrears":arrears,"food":food,"coinsRequired":wages+arrears},true)
	if spare<1:q.ok=false;q.message="Selected recovery needs a spare able sailor on a working boat."
	elif not Salvage._tow_ledger(snapshot):q.ok=false;q.message="The world coin ledger or payroll purse cannot be reconciled."
	elif int(snapshot.get("coins",0))<wages+arrears:q.ok=false;q.message="Recovery needs %d actual coins for normal payroll and existing arrears."%(wages+arrears)
	elif float(snapshot.get("cargo",{}).get("food",0))+0.0000001<food:q.ok=false;q.message="Recovery needs %.2f actual food for its paid work."%food
	return q

## Pure board/fixture quote. Normal strip/tow retain their action contracts;
## selected equipment adds whole paid work, actual food and arrears preflight.
func recovery_quote(id: String,mode: String,good: String="",qty: float=0.0,request: Dictionary={}) -> Dictionary:
	var raw: Dictionary=Remote067.raw_wreck(state,id)
	if not home_local064() or Remote067.cargo_only(raw):return Remote067.quote(self,id,mode,good,qty)
	var view=Salvage.QuoteView.new(self)
	var q: Dictionary=Salvage.quote(view,id,mode,request)
	if mode=="strip" and not good.is_empty():
		var wreck: Dictionary=Salvage.find_wreck(view.state,id)
		var available: float=float(Salvage._strip_items(wreck).get(good,0))
		var amount: float=minf(qty,available) if is_finite(qty) else 0.0
		var weight: float=amount*float(Goods.ITEMS.get(good,{"weight":1}).weight)
		q.merge({"items":{good:amount},"weight":weight,"quantity":amount},true)
		q.ok=not wreck.is_empty() and str(wreck.get("status",""))=="unclaimed" and Goods.ITEMS.has(good) and amount>0 and weight<=float(q.get("freeCapacity",0))+0.00001 and Salvage.Recovery.refusal(wreck).is_empty()
		if q.ok:q.message="Recover %.2f %s (%.2f hold space)."%[amount,good,weight]
		else:q.message="Choose a positive finite recoverable lot that fits the traveling holds."
	if mode=="gear":q=_gear_work_quote(q,view.state)
	else:
		var work: float=recovery_days(float(q.get("weight",1))) if mode=="strip" else maxf(1,float(q.get("ordinary",100))/200.0)
		var payroll: int=maxi(0,pending_days)+int(float(state.get("day",0))+work)-int(state.get("day",0))
		var upkeep: Dictionary=Economy.daily_upkeep(view.state.get("fleet",[]))
		var wages: int=(int(upkeep.wages)+FleetSupport.premium(view.state))*payroll
		q.merge({"workDays":work,"payrollDays":payroll,"wages":wages,
			"arrears":int(view.state.get("wageArrears",0))+FleetSupport.premium(view.state,true),
			"food":maxf(0,float(upkeep.food)*payroll-float(view.state.get("surveyFoodCredit",0)))},true)
	var blocked: String=_recovery_gate(view.state,id,mode)
	if not blocked.is_empty():q.ok=false;q.message=blocked
	return q

## Run exactly the ordinary per-harbor economy day on this detached campaign,
## with the same seeds/options as Main's worker, then the normal settlement.
## No workers or navigation/world rebuilds are started by this source seam.
func _settle_recovery_economy(days: int,require_funded: bool=true) -> Dictionary:
	var receipt: Dictionary={"ok":true,"message":"Normal recovery payroll and provisions settled.","wagesPaid":0,"foodConsumed":0.0,"foodCreditUsed":0.0}
	for _day in range(days):
		var due: Dictionary=Economy.daily_upkeep(state.fleet)
		var coins: int=int(due.wages)+FleetSupport.premium(state)+FleetSupport.premium(state,true)
		var food: float=maxf(0,float(due.food)-float(state.get("surveyFoodCredit",0)))
		if require_funded and (int(state.coins)<coins or float(state.cargo.get("food",0))+0.0000001<food):return fail("Ordinary payroll or provisions changed during staged recovery; nothing was published.")
		receipt.wagesPaid+=mini(int(state.coins),coins)
		receipt.foodConsumed+=minf(float(state.cargo.get("food",0)),food)
		receipt.foodCreditUsed+=minf(float(due.food),float(state.get("surveyFoodCredit",0)))
		var blocked: Array=TradeFlow.blockades(self)
		var ports: Array=[]
		var messages: Array=[]
		for i in range(state.ports.size()):
			var p: Dictionary=state.ports[i].duplicate(true)
			var rng=RandomNumberGenerator.new()
			rng.seed=int(state.seed)+int(state.econDay)*104729+i*7919
			messages.append_array(Economy.tick_ports([p],1,{"blockaded":blocked,"interport_trade":false,"rng":rng}))
			ports.append(p)
		apply_economy(ports,messages,1)
		if require_funded and (int(state.wageArrears)>0 or FleetSupport.premium(state,true)>0):return fail("Staged recovery could not fully settle ordinary wages; nothing was published.")
	return receipt

func _recover_selected_gear(id: String,request: Dictionary) -> Dictionary:
	var built: Dictionary=Salvage._gear_stage(self,id,request)
	var q: Dictionary=_gear_work_quote(built.quote,state)
	var blocked: String=_recovery_gate(state,id,"gear")
	if not blocked.is_empty():q.ok=false;q.message=blocked
	if not q.ok:return q
	if request.get("acceptForfeiture",false)!=true:q.ok=false;q.message="Confirm loss of this hull, every unselected fitting and all structural component lots before dismantling.";return q
	# One action context reuses warmed immutable navigation and owns all mutable
	# state. Live state, pending days and events are published only after success.
	var staged=get_script().new(data,nav)
	staged.state=built.state
	staged.events=events.duplicate(true)
	staged.route_cache=route_cache.duplicate(true)
	var ordinary_arrears: int=int(staged.state.get("wageArrears",0))
	if ordinary_arrears>0:
		if not Money.move(staged.state,"coins",staged.state,"crewPurse",ordinary_arrears,"Captain settles unpaid wages before recovery",staged.state.moneyLog):return fail("Existing arrears could not be settled; nothing was recovered.")
		staged.state.wageArrears=0
	staged.state.day=float(staged.state.day)+float(q.workDays)
	var settled: Dictionary=staged._settle_recovery_economy(int(q.payrollDays))
	if not settled.ok:q.ok=false;q.message=settled.message;return q
	var destination: Dictionary={}
	for boat in Expedition.traveling(staged.state):
		if str(boat.get("uid",""))==str(q.carrierUid):destination=boat;break
	if destination.is_empty() or Expedition.locker_weight(destination)>Expedition.hull_hold_capacity(staged.state,destination)+0.00001:q.ok=false;q.message="The original working carrier cannot carry this locker after recovery work; nothing was published.";return q
	for item in q.selected:
		var actual: Dictionary=destination.get("moduleCondition",{}).get("items",{}).get(str(item.itemUid),{})
		if str(actual.get("location",""))!="locker":q.ok=false;q.message="Final custody did not retain every exact selected part in the chosen locker.";return q
		for key in ["itemUid","family","typeId","hp","originHullType","status","cause"]:
			if actual.get(key)!=item[key]:q.ok=false;q.message="Recovery would change a selected part's identity or condition; nothing was published.";return q
	staged.Manifest.allocate(staged.state)
	if staged.cargo_weight()>staged.capacity()+0.00001 or not staged.state.cargoManifest.get("unassigned",{}).is_empty():q.ok=false;q.message="Recovery work left insufficient physical carrying space; nothing was published.";return q
	var final_custody: Dictionary=Preflight.check_state(staged.state,data)
	if not final_custody.ok:q.ok=false;q.message=final_custody.message;return q
	if Money.total(staged.state)!=int(state.get("coinSupply",-1)):q.ok=false;q.message="Recovery refused an unreconciled final coin ledger.";return q
	staged.log_entry(str(q.message)+" %.0f working days; %d normal payroll coins plus %d arrears and %.2f food committed."%[float(q.workDays),int(q.wages),int(q.arrears),float(q.food)])
	q.coinsAfter=int(staged.state.coins)
	q.foodAfter=float(staged.state.cargo.food)
	q.dayAfter=float(staged.state.day)
	q.wagesPaid=int(settled.wagesPaid)+ordinary_arrears
	q.foodConsumed=float(settled.foodConsumed)
	q.foodCreditUsed=float(settled.foodCreditUsed)
	state=staged.state
	pending_days=0
	events=staged.events
	Arc111.after_recovery(self,id,q)
	Arc114.after_recovery(self,id,q)
	return q

func recover_wreck(id: String,mode: String,good: String="",qty: float=0.0,request: Dictionary={}) -> Dictionary:
	var locality: String=_recovery_gate(state,id,mode)
	if not locality.is_empty():return fail(locality)
	if Remote067.local(state):
		var receipt: Dictionary=Remote067.recover(self,id,good,qty)
		if bool(receipt.get("ok",false)) and bool(receipt.get("completed",false)):StoryOps.after_recovery077(self,id,receipt)
		return receipt
	if mode=="gear":return _recover_selected_gear(id,request)
	var w: Dictionary=Salvage.find_wreck(state,id)
	if w.is_empty() or distance(state.position,w)>180:return fail("Approach this wreck within180water units first.")
	var hazard: Dictionary=fleet_owner(str(state.wreckHazards.get(w.sourceId,"")))
	if not hazard.is_empty() and hazard.active and hazard.boats.any(func(b):return not b.sunk):return fail("Hostiles still control this wreck field. Secure the waters before recovery.")
	if not state.path.is_empty() or not state.exploration.assignment.is_empty():return fail("Stop the fleet and recall shore parties before recovery.")
	var q: Dictionary=Salvage.quote(self,id,mode)
	if mode=="strip" and Exploration.spare_crew(state)<1:return fail("Recovery needs at least one spare able sailor above the boat minimums.")
	var result: Dictionary=Salvage.strip_good(self,id,good,qty) if mode=="strip" and not good.is_empty() else Salvage.recover(self,id,mode)
	if not result.ok:return result
	var work_days: float=recovery_days(float(result.get("weight",q.get("weight",1)))) if mode=="strip" else maxf(1,float(q.get("ordinary",100))/200.0)
	var previous_day: int=int(state.day)
	state.day+=work_days
	pending_days+=int(state.day)-previous_day
	Manifest.allocate(state)
	log_entry(str(result.message)+" %.2f working days; normal wages/provisions apply."%work_days)
	if mode=="tow":
		Arc111.after_tow(self,id,result)
		Arc114.after_tow(self,id,result)
	if mode=="strip":Arc111.after_strip(self,id,result)
	return result

func jettison(good: String,qty: int) -> Dictionary:
	if not Goods.ITEMS.has(good) or qty<=0 or float(state.cargo.get(good,0))<qty:return fail("Choose a positive owned cargo lot.")
	Salvage.ensure(state)
	state.wreckSeq+=1
	state.cargo[good]-=qty
	state.wrecks.append({"id":"wreck-%d"%state.wreckSeq,"sourceId":"jettison:%d"%state.wreckSeq,"hull":"","name":"Marked cargo float","world064":world_location064().world064,"x":state.position.x,"y":state.position.y,"stores":{good:float(qty)},"components":{},"status":"unclaimed","day":state.day})
	Salvage.ensure(state)
	Manifest.allocate(state)
	return ok("Cargo set on a marked float. It can be recovered later if space is available.")

func trade(id: String, good: String, qty: int, side: String) -> Dictionary:
	var before118: Dictionary=Arc118.before_trade(self,id,good,qty,side)
	var result: Dictionary=LawOps.trade(self,id,good,qty,side)
	Arc118.after_trade(self,before118,result)
	return result

func ship_materials(h: Dictionary) -> Dictionary:
	return Construction.blueprint(h).materials

func ship_quote(h: Dictionary, at: Dictionary = {}) -> Dictionary:
	return Harbor.quote(self,h,at)

func can_materials(p: Dictionary, materials: Dictionary) -> bool:
	for key in materials:
		if p.stocks.get(key,0.0) < materials[key]:
			return false
	return true

func consume_materials(p: Dictionary, materials: Dictionary):
	for key in materials:
		p.stocks[key] -= materials[key]

func find_boat(uid: String) -> Dictionary:
	for boat in state.fleet:
		if boat.uid == uid:
			return boat
	return {}

## Publish the same per-hull defaults and current morale that restore applies.
## Domain helpers preserve existing valid fields; this never heals or pays anyone.
func _initialize_published_boat(boat: Dictionary) -> void:
	FleetIdentity.ensure_boat(boat)
	HomeOps.ensure_boat(boat)
	BoardingOps.ensure_boat(boat)
	_apply_boat_morale(boat, clampf(state.morale/85.0,0.35,1.0))

## Empty staged is only Salvage._publish_tow, which still calls add_boat(spec, 0).
## That shell does not seed. A paid caller passes an accepted stage_birth result.
func add_boat(h: Dictionary, crew: int = 0, staged: Dictionary = {}) -> Dictionary:
	if staged.is_empty():
		return _legacy_tow_shell(h, crew)
	if not bool(staged.get("ok", false)):
		return {}
	var fresh := bool(staged.get("fresh", true))
	var boat: Dictionary = Lifecycle.materialize(h, crew, staged, fresh)
	if str(boat.uid) == "boat-%d" % int(state.nextUid):
		state.nextUid += 1
	boat.mothballed = float(boat.crew) < float(boat.crewMin)
	boat.storedPort = ""
	fit_boat(boat, fresh)
	boat.fuel = 0.0
	boat.ammo = 0.0
	boat.supplies = 0.0
	if not fresh:
		boat.hp = clampf(float(staged.get("hullHp", boat.hp)), 0.0, float(boat.maxHp))
	_initialize_published_boat(boat)
	state.fleet.append(boat)
	return boat

## Unseeded boat-N shell. Caller: Salvage._publish_tow until root passes adopt_staged.
func _legacy_tow_shell(h: Dictionary, crew: int) -> Dictionary:
	var boat: Dictionary = Damage.create_ship(h, {"crew": crew, "fuel": 0.0, "ammo": 0.0, "supplies": 0.0})
	boat.uid = "boat-%d" % state.nextUid
	state.nextUid += 1
	boat.mothballed = crew < boat.crewMin
	boat.storedPort = ""
	fit_boat(boat, true)
	_initialize_published_boat(boat)
	state.fleet.append(boat)
	return boat

## One publication. Failure puts the previous career back and does not save.
func publish_career(candidate: Dictionary, prior_state: Dictionary, prior_pending: int, prior_events: Array) -> Dictionary:
	var prepared: Dictionary = Preflight.prepare_state(candidate, data)
	if not prepared.ok:
		state = prior_state
		pending_days = prior_pending
		events = prior_events
		return fail(str(prepared.get("message", "New career was refused.")))
	state = prepared.state
	_refit_published()
	apply_morale()
	return ok("Career published.")

func _refit_published() -> void:
	for s in state.get("fleet", []):
		if s is Dictionary:
			fit_boat(s, false)
	for b in state.get("boardingPrizes", []):
		if b is Dictionary:
			fit_boat(b, false)
	for owner in state.get("fleetOwners", []):
		if owner is Dictionary:
			for b in owner.get("boats", []):
				if b is Dictionary:
					canonical_npc_boat(b, bool(owner.get("playerCompany", false)))

## v0.002 fittings. The base hull is always rebuilt from world data; the loadout is the only
## fitting input. Never heals damage, refills stores, recruits or moves coins.
func fitted_spec(boat: Dictionary) -> Dictionary:
	var base: Dictionary = hull(str(boat.get("type",""))).duplicate(true)
	if base.is_empty():
		return boat.get("spec",{})
	var loadout = boat.get("loadout")
	if not loadout is Dictionary:
		loadout = Refits.defaults(base)
	return Refits.effective_spec(base,loadout)

func fit_boat(boat: Dictionary, fresh: bool = false) -> void:
	var base: Dictionary = hull(str(boat.get("type",""))).duplicate(true)
	if base.is_empty():
		return
	boat.baseSpec = base.duplicate(true)
	Refits.ensure(boat,base)
	boat.spec = FleetIdentity.effective(boat,Refits.effective_spec(base,boat.loadout))
	var max_hp: float = maxf(1.0,float(boat.spec.get("hp",base.hp)))
	if fresh:
		boat.hp = max_hp # a newly built hull is delivered to its fitted design
	boat.maxHp = max_hp
	boat.hp = clampf(float(boat.hp),0.0,max_hp) # existing damage is never healed
	boat.armor = maxf(0.0,float(boat.spec.get("armor",base.get("armor",0.0))))

## v0.002 deployment-point ownership limit (replaces the eight-boat cap).
func hull_points(h: Dictionary) -> int:
	var base: Dictionary = hull(str(h.get("id",""))).duplicate(true)
	if base.is_empty():
		return Deployment.cost(h)
	return Deployment.cost(Refits.effective_spec(base,Refits.defaults(base)))

func fleet_points() -> int:
	return Deployment.total(state.get("fleet",[]).filter(func(s): return not s.get("sunk",false)))

func fleet_limit() -> int:
	return Deployment.LIMIT

func can_add_boat(spec: Dictionary) -> bool:
	if state.is_empty() or hull(str(spec.get("id",""))).is_empty():
		return false
	if CompanyOps.api(self).owned_count(state) >= MAX_FLEET:
		return false
	return true

func points_refusal(spec: Dictionary) -> String:
	return "The fleet register holds at most %d owned hulls. Sell a hull or collect an existing stored boat; battle deployment remains 300 points per side."%MAX_FLEET

func sealed_fuel_carrier(uid: String) -> bool:
	return state.get("voyageJobs",[]).any(func(j):return j.get("kind","")=="fuel_delivery" and str(j.get("carrierUid",""))==uid and float(j.get("freight",{}).get("qty",0))>0)

func set_boat_active(uid: String, enabled: bool) -> Dictionary:
	if not enabled and sealed_fuel_carrier(uid):return fail("Deliver or safely unload this boat's sealed fuel before standing it down.")
	var b: Dictionary=find_boat(uid)
	if b.is_empty() or not str(b.get("storedPort","")).is_empty():return fail("Collect this boat from its harbor first.")
	if int(b.get("shoreCrew",0))>0:return fail("Recall the shore party before changing this boat's status.")
	if CrisisOps.Transport.assigned(state,uid)>0:return fail("Keep the actual passenger boat active until safe discharge.")
	if enabled and b.crew<b.crewMin:return fail("Hire the minimum crew before activation.")
	if enabled and b.get("needsHarborRepair",false):return fail("This recovered hull needs paid harbor repairs before it can sail under its own power.")
	if not enabled and b.uid==state.flagship:return fail("Choose another active flagship first.")
	var before: bool=b.get("mothballed",false)
	b.mothballed=not enabled
	if cargo_weight()>capacity()+0.001:
		b.mothballed=before
		return fail("Offload cargo before standing down its carrier.")
	Manifest.allocate(state)
	return ok("Boat activated." if enabled else "Boat stood down; it contributes no expedition hold space.")

func toggle_storage(uid: String) -> Dictionary:
	var b: Dictionary=find_boat(uid)
	var p: Dictionary=current_port()
	if b.is_empty() or p.is_empty() or not state.path.is_empty():return fail("Dock at a harbor to store or collect a boat.")
	if int(b.get("shoreCrew",0))>0:return fail("Recall the shore party before storing its boat.")
	if CrisisOps.Transport.assigned(state,uid)>0:return fail("Discharge passengers safely before storing their actual carrier.")
	if int(state.get("captiveBerths",{}).get(uid,0))>0:return fail("Release this boat's captives safely before storing it.")
	var stored: String=str(b.get("storedPort",""))
	if stored.is_empty() and sealed_fuel_carrier(uid):return fail("Deliver or safely unload this boat's sealed fuel before storing it.")
	if not stored.is_empty():
		var permission: Dictionary=Politics.permit(self,"service")
		if not permission.ok:return permission
		if int(b.get("berthArrears",0))>0:return fail("Settle this hull's berth arrears in Home harbors before collecting it.")
		if stored!=p.id:return fail("This boat is stored at %s."%port(stored).name)
		b.storedPort=""
		b.mothballed=b.crew<b.crewMin
		Manifest.allocate(state)
		return ok("Boat collected. Hire sailors and provision it before activation.")
	var berth: Dictionary=HomeOps.can_store(self,b,p)
	if not berth.ok:return berth
	if not FleetSupport.aboard(self,uid).is_empty():return fail("Discharge specialists with their savings before storing this boat.")
	if uid==state.flagship:return fail("Choose another active flagship before storing this boat.")
	b.storedPort=p.id
	if cargo_weight()>capacity()+0.001:
		b.storedPort=""
		return fail("Offload cargo before storing its carrier.")
	var savings: int=floori(float(state.crewPurse)*float(b.crew)/maxi(1,crew_count()))
	Money.move(state,"crewPurse",p,"householdPurse",savings,"Stored boat sailors take savings ashore",state.moneyLog)
	p.workforce+=int(b.crew);p.recruits+=int(b.crew)
	TrainingOps.Training.return_qualified(p,int(b.crew),"sailor")
	b.crew=0.0;b.wounded=0.0;b.mothballed=true
	Economy.sync_workforce(p)
	Manifest.allocate(state)
	return ok("Hull stored at %s; sailors and their savings returned ashore. Stores and fittings stay with the hull."%p.name)

func refit_boat(uid: String, slot: String, module_id: String, request: Dictionary = {}) -> Dictionary:
	var boat: Dictionary=find_boat(uid)
	if boat.is_empty():return fail("That boat is not in your flotilla.")
	var fit: Dictionary=Refits.normalize(hull(str(boat.type)),boat.get("loadout",{}))
	if not fit.ok:return fit
	var position: Dictionary=Refits._slot(fit.loadout,slot)
	if not position.ok:return position
	var next: Dictionary=fit.loadout.duplicate(true)
	if position.index>=0:next.weapons[position.index]=module_id
	else:next[position.key]=module_id
	return workshop_apply(uid,next,{},request)

func workshop_preview(uid: String,loadout: Dictionary,request: Dictionary={}) -> Dictionary:
	return Workshop.preview(self,uid,loadout,request)

func workshop_apply(uid: String,loadout: Dictionary,expected_quote: Dictionary={},request: Dictionary={}) -> Dictionary:
	var result: Dictionary=Workshop.apply(self,uid,loadout,expected_quote,request)
	if result.ok and result.get("changed",false):log_entry(str(result.message))
	return result

func workshop_save_template(uid: String,name: String,loadout: Dictionary) -> Dictionary:
	var boat: Dictionary=find_boat(uid)
	if boat.is_empty():return fail("Choose an owned hull to record a fitting.")
	return Workshop.save_template(state,hull(str(boat.type)),name,loadout)

func workshop_delete_template(id: String) -> Dictionary:
	return Workshop.delete_template(state,id)

func buy_boat(id: String) -> Dictionary:
	return Harbor.buy(self,id)

func commission(id: String) -> Dictionary:
	return Harbor.commission(self,id)

func collect_boat(index: int) -> Dictionary:
	return Harbor.collect(self,index)

func recruit_crew(uid: String, count: int) -> Dictionary:
	return Harbor.recruit(self,uid,count)

func sell_boat(uid: String) -> Dictionary:
	if sealed_fuel_carrier(uid):return fail("Deliver or safely unload this boat's sealed fuel before selling it.")
	return Harbor.sell(self,uid)

func service_quote(boat: Dictionary, p: Dictionary) -> Dictionary:
	return Harbor.service_quote(self,boat,p)

func repair_boat(uid: String) -> Dictionary:
	return Harbor.repair(self,uid)

func resupply_boat(uid: String, profile: String = "full") -> Dictionary:
	return Harbor.resupply(self,uid,profile)

func use_reserves():
	Harbor.use_reserves(self)
	Manifest.allocate(state)

## Working tank stock only. Sealed job freight and loose hold fuel stay separate.
## Validate the whole exact transfer before publishing either tank value.
func transfer_fuel065(source_uid: String,target_uid: String,quantity: float) -> Dictionary:
	if state.is_empty():return fail("Start or restore a voyage before transferring fuel.")
	if source_uid.is_empty() or target_uid.is_empty() or source_uid==target_uid:return fail("Choose two different owned boats.")
	if not is_finite(quantity) or quantity<=0.0:return fail("Choose an exact finite positive fuel quantity.")
	if not state.get("path",[]).is_empty():return fail("Stop the fleet before transferring fuel.")
	if not travel_lock064.is_empty():return fail(travel_lock064)
	for event in events:
		if event.get("kind","") in ["encounter","defeat"]:return fail("Resolve the pending encounter before transferring fuel.")
	var source: Dictionary={}
	var target: Dictionary={}
	var matches: int=0
	for boat in state.get("fleet",[]):
		if str(boat.get("uid",""))==source_uid:source=boat;matches+=1
		elif str(boat.get("uid",""))==target_uid:target=boat;matches+=1
	if matches!=2 or source.is_empty() or target.is_empty():return fail("Choose two uniquely identified owned boats.")
	for boat in [source,target]:
		if boat.get("sunk",false) or not str(boat.get("storedPort","")).is_empty():return fail("Both boats must be afloat and present with the traveling fleet.")
		var stock=boat.get("fuel")
		if not (stock is int or stock is float) or not is_finite(float(stock)) or float(stock)<0.0:return fail("The boat's working fuel record is invalid.")
	var fitted: Dictionary=fitted_spec(target)
	if fitted.is_empty():return fail("The receiving boat's fitting is invalid.")
	fitted=FleetIdentity.effective(target,fitted)
	var capacity_value=fitted.get("fuelCapacity",60.0)
	if not (capacity_value is int or capacity_value is float) or not is_finite(float(capacity_value)) or float(capacity_value)<0.0:return fail("The receiving boat's fitted tank capacity is invalid.")
	var source_fuel: float=float(source.fuel)
	var target_fuel: float=float(target.fuel)
	var tank_capacity: float=float(capacity_value)
	if quantity>source_fuel:return fail("The source tank does not contain that much fuel.")
	if quantity>tank_capacity-target_fuel:return fail("The receiving tank has insufficient fitted room for that exact quantity.")
	source.fuel=source_fuel-quantity
	target.fuel=target_fuel+quantity
	return {"ok":true,"message":"Transferred %.3f working fuel from %s to %s."%[quantity,str(source.get("name",source_uid)),str(target.get("name",target_uid))],"quantity":quantity,"sourceUid":source_uid,"targetUid":target_uid}

func available_contracts() -> Array:
	return Contracts.available(self)

func accept_contract(id: String) -> Dictionary:
	var permission: Dictionary=Politics.permit(self,"contract")
	if not permission.ok:return permission
	return Contracts.accept(self,id)

func start_fishing(uid: String,days: float=1.0,crew: int=0) -> Dictionary:
	return CivilianWork.start_fishing(self,uid,days,crew)

func cancel_fishing(uid: String) -> Dictionary:
	return CivilianWork.cancel_fishing(self,uid)

func accept_voyage_job(id: String,carrier_uid: String="") -> Dictionary:
	var permission: Dictionary=_work_permission070()
	if not permission.ok:return permission
	var result: Dictionary=VoyageJobs.accept(self,id,carrier_uid)
	if result.ok:
		Contacts.visit(state,work_port070(),state.day)
		if id.begins_with("chainfreight-"):state.storyRights.usedOffers[id]=true
	if result.ok and id==Arc113.JOB:Arc113.bind(self)
	Manifest.allocate(state)
	return result

func settle_voyage_job(id: String,abandon: bool=false) -> Dictionary:
	var permission: Dictionary=_work_permission070()
	if not permission.ok:return permission
	var completed_berth: Dictionary=work_port070()
	var before: Dictionary=VoyageJobs._find(state,id).duplicate(true)
	var result: Dictionary=VoyageJobs.abandon(self,id) if abandon else VoyageJobs.finish(self,id)
	Arc110.after_job(self,before,result,abandon)
	if result.ok:
		if not abandon:
			Politics.job_completed(self,before)
			if before.get("kind","")=="freight":RegionalOps.delivered(self,str(before.targetPort),float(before.get("freight",{}).get("qty",0)),str(before.port))
			var used: Array=[str(before.carrierUid)] if not str(before.get("carrierUid","")).is_empty() else active_fleet().map(func(b):return b.uid)
			if before.get("kind","")!="bounty":FleetIdentity.record_service(self,used,"survey" if before.get("kind","")=="survey" else "trade")
			var captain: String=str(before.get("ownerId",""))
			if before.get("kind","")=="fuel_delivery" and not captain.is_empty():Contacts.record_captain(state,captain,"job:"+id+":paid",str(before.get("title","Voyage delivery"))+" completed at "+str(completed_berth.get("name","harbor")),5)
		Contacts.visit(state,completed_berth,state.day)
		var sponsor_id: String=str(before.get("sponsorContactId",""))
		var event_id: String="job:"+id+(":abandoned" if abandon else ":paid")
		var completed_at: String=str(completed_berth.get("id",""))
		for contact in Contacts.list_contacts(state):
			if contact.has("ownerId"):continue
			var remembers: bool=contact.port==completed_at and (not abandon or contact.port==before.get("port",""))
			if contact.id=="harbor:"+str(before.get("port","")):remembers=true
			if not sponsor_id.is_empty():remembers=contact.id==sponsor_id and contact.port==before.get("port","")
			if remembers:Contacts.record(state,contact.id,event_id,-5 if abandon else 5,str(before.get("title","Voyage job")),completed_at)
	Manifest.allocate(state)
	return result

func campaign_material_offer113() -> Dictionary:
	return Arc113.offer(self)

func campaign_delivery_before113(job: Dictionary) -> Dictionary:
	return Arc113.before_job(self,job)

func campaign_job_closed110(before: Dictionary,result: Dictionary,abandon: bool) -> void:
	Arc110.after_job(self,before,result,abandon)
	Arc111.after_job(self,before,result,abandon)
	Arc112.after_job(self,before,result,abandon)
	Arc113.after_job(self,before,result,abandon)
	Arc116.after_job(self,before,result,abandon)
	Arc117.after_job(self,before,result,abandon)
	Arc118.after_job(self,before,result,abandon)

func contract_ready() -> bool:
	return home_local064() and not state.activeContract.is_empty() and not state.freight.get("lost",false) and distance(state.position,port(state.activeContract.targetPort)) < 90

func finish_contract() -> Dictionary:
	var before: Dictionary=state.activeContract.duplicate(true)
	var result: Dictionary=Contracts.finish(self)
	if result.ok:
		Politics.job_completed(self,before)
		if before.get("kind","")=="delivery":RegionalOps.delivered(self,str(before.targetPort),float(before.get("cargo",{}).get("qty",0)),str(before.port))
		if before.get("kind","")=="delivery":FleetIdentity.record_service(self,active_fleet().map(func(b):return b.uid),"trade")
	return result

func abandon_contract() -> Dictionary:
	return Contracts.abandon(self)

## Called on Main after retirement. Arena ids are transient; only an actually
## deployed original campaign owner can earn service. Reserves are not scanned.
func _record_battle_service060(physical_battle: Dictionary,result: String) -> Array:
	var owners: Array=[]
	var rows: Array=[]
	var seen: Dictionary={}
	for key in ["ships","escapedShips","captured"]:
		for ship in physical_battle.get(key,[]):
			if not ship is Dictionary or not ship.get("_serviceStart060") is Dictionary:continue
			var start: Dictionary=ship._serviceStart060
			var uid: String=str(start.get("uid",""))
			if uid.is_empty() or seen.has(uid) or str(start.get("team",""))!="player":continue
			if uid!=str(ship.get("uid","")) or not is_same(find_boat(uid),ship):continue
			seen[uid]=true
			owners.append(ship)
			var fate: String="sunk" if ship.get("sunk",false) else ("captured" if str(ship.get("team",""))!="player" else ("escaped" if ship.get("battleEscaped",false) else "afloat"))
			var crew_start: float=Damage.number(start.get("crew"))
			var crew_end: float=Damage.number(ship.get("crew"))
			rows.append({"uid":uid,"name":str(ship.get("name",uid)),"hull":str(ship.get("type","")),"result":result,"fate":fate,
				"crewStart":crew_start,"crewEnd":crew_end,"woundedStart":Damage.number(start.get("wounded")),"woundedEnd":Damage.number(ship.get("wounded")),"crewDecrease":maxf(0.0,crew_start-crew_end),
				"hpStart":Damage.number(start.get("hp")),"hpEnd":Damage.number(ship.get("hp")),"maxHp":Damage.number(ship.get("maxHp")),
				"repair":{"missingHp":maxf(0.0,Damage.number(ship.get("maxHp"))-Damage.number(ship.get("hp"))),"water":Damage.number(ship.get("water")),"fire":Damage.number(ship.get("fire")),"engine":Damage.number(ship.get("engine")),"needsHarborRepair":bool(ship.get("needsHarborRepair",false))}})
	FleetIdentity.record_service(self,rows.map(func(row):return row.uid),result)
	for index in range(rows.size()):
		var row: Dictionary=rows[index]
		var boat: Dictionary=owners[index]
		var detail: String="%s (%s): %s; crew %.0f -> %.0f, wounded %.0f -> %.0f; hull %.0f -> %.0f / %.0f HP; missing %.0f HP, water %.0f, fire %.0f, engine %.0f%%."%[row.name,row.uid,row.fate,row.crewStart,row.crewEnd,row.woundedStart,row.woundedEnd,row.hpStart,row.hpEnd,row.maxHp,row.repair.missingHp,row.repair.water,row.repair.fire,float(row.repair.engine)*100.0]
		if row.fate=="sunk":detail+=" Last crew count on a lost hull; no living berth restored."
		elif row.repair.needsHarborRepair:detail+=" Paid harbor repair is required."
		var history: Array=boat.serviceHistory
		if not history.is_empty():history[history.size()-1].detail=detail
		row.service=boat.service.duplicate(true)
		row.serviceHistory=history.duplicate(true)
		if row.fate in ["sunk","captured"]:
			log_entry("%s %s (%s); service %d battles, %d wins. %s"%[row.fate.capitalize(),row.name,row.uid,int(row.service.get("battles",0)),int(row.service.get("wins",0)),detail])
	return rows

## Read-only plan. A raider's own operating food, fuel, supplies and ammunition stay reserved.
## Only a proven captured remainder of those goods, past that reserve, can enter the manifest.
## That remainder is capped by the cargo aboard and by crewed hold space. Nothing is created or removed.
func prize_shipment(owner: Dictionary) -> Dictionary:
	var law: Dictionary=Politics.commission_enemy(self,owner)
	var empty: Dictionary={"ok":false,"lawful":bool(law.get("lawful",false)),"message":str(law.get("reason","")),"carrierUids":[],"carrierCargo":{}}
	if not law.get("lawful",false):return empty
	if str(owner.get("kind",""))!="raider":empty.message="Letters name this faction, but this fleet is not a hostile shipment.";return empty
	var boats: Array=[]
	for boat in owner.get("boats",[]):
		if boat is Dictionary and not boat.get("sunk",false) and not boat.get("captureSecured",false) and float(boat.get("crew",0))>=float(boat.get("crewMin",1)):boats.append(boat)
	boats.sort_custom(func(a,b):return str(a.get("uid",""))<str(b.get("uid","")))
	if boats.is_empty():empty.message="The hostile fleet has no crewed boat that can carry a shipment.";return empty
	var operating: Array=["food","fuel","supplies","ammo"]
	var free: Dictionary={}
	for boat in boats:
		var uid: String=str(boat.get("uid",""))
		if uid.is_empty() or free.has(uid):empty.message="Hostile carrier identities are unavailable.";return empty
		free[uid]=maxf(0.0,float(boat.get("spec",{}).get("cargo",0))-Expedition.store_overflow(boat))
	var cargo: Dictionary=owner.get("cargo",{}) if owner.get("cargo") is Dictionary else {}
	var captured_book: Dictionary=owner.get("capturedOperating",{}) if owner.get("capturedOperating") is Dictionary else {}
	var goods: Array=cargo.keys();goods.sort()
	var operating_left: Dictionary={};var prize_left: Dictionary={}
	for good in goods:
		var name: String=str(good)
		if not Goods.ITEMS.has(name):continue
		var qty: float=float(cargo[good])
		if not is_finite(qty) or qty<0.0:empty.message="Hostile cargo is not a finite lot.";return empty
		if qty<=0.0:continue
		if name in operating:
			var proven: float=0.0
			if captured_book.has(name):
				var raw=captured_book[name]
				if (raw is int or raw is float) and is_finite(float(raw)) and float(raw)>0.0:proven=minf(float(raw),qty)
			var reserve: float=maxf(0.0,qty-proven)
			if reserve>0.0:operating_left[name]=reserve
			if proven>0.0:prize_left[name]=proven
		else:prize_left[name]=qty
	for good in operating_left:
		var left: float=float(operating_left[good]);var weight: float=float(Goods.ITEMS[good].weight)
		for boat in boats:
			var uid: String=str(boat.uid)
			var take: float=minf(left,float(free[uid])/weight) if weight>0.0 else 0.0
			if take<=0.0:continue
			free[uid]-=take*weight;left-=take
			if left<=0.000001:break
	var manifest: Dictionary={};var uids: Array=[]
	for good in prize_left:
		var left: float=float(prize_left[good]);var weight: float=float(Goods.ITEMS[good].weight)
		for boat in boats:
			var uid: String=str(boat.uid)
			var take: float=minf(left,float(free[uid])/weight) if weight>0.0 else 0.0
			if take<=0.0:continue
			if not manifest.has(uid):manifest[uid]={}
			manifest[uid][good]=take;free[uid]-=take*weight;left-=take
			if left<=0.000001:break
	for boat in boats:
		var uid: String=str(boat.uid)
		if manifest.has(uid) and not manifest[uid].is_empty():uids.append(uid)
	if uids.is_empty():empty.message="This hostile fleet has no captured shipment that fits a crewed hold.";return empty
	return {"ok":true,"lawful":true,"message":str(law.reason),"carrierUids":uids,"carrierCargo":manifest,"patronId":str(law.patronId)}

## A commissioned hostile shipment uses the existing intercept mission. No prize cargo means an ordinary battle.
## Any nonempty mission already on the context, including a convoy escort, stays assigned.
func intercept_shipment(context: Dictionary) -> Dictionary:
	var existing: Dictionary=context.get("mission",{}) if context.get("mission") is Dictionary else {}
	if not existing.is_empty():return {"handled":false,"message":"An existing mission stays assigned."}
	var owner: Dictionary=fleet_owner(str(context.get("ownerId",context.get("id",""))))
	var plan: Dictionary=prize_shipment(owner)
	if not plan.ok:return {"handled":false,"message":str(plan.message)}
	var patrol: Dictionary=NavalAI._find_patrol(state,str(owner.id))
	var dest: String=str(patrol.get("to",""))
	var mission: Dictionary={"kind":"intercept","carrierTeam":"enemy","carrierOwnerId":str(owner.id),"carrierUids":plan.carrierUids,"carrierCargo":plan.carrierCargo,"exit":{"x":120.0,"y":850.0,"radius":70.0,"portId":dest,"portName":str(port(dest).get("name",dest))}}
	var error: String=Objectives.deployment_error(FleetSupport.combat(self),owner.get("boats",[]).filter(func(b):return not b.get("sunk",false)),mission)
	if not error.is_empty():return {"handled":false,"message":error}
	var out: Dictionary=context.duplicate(true)
	out.mission=mission
	return {"handled":true,"context":out,"message":str(plan.message)}

func battle_settled(result: String, enemy_specs: Array, context: Dictionary,physical_battle: Dictionary={}) -> Dictionary:
	if not home_local064() and context.get("kind","") in ["patrol","escort","contract"]:return fail("This encounter belongs to Shatter Coast waters.")
	if physical_battle.get("settlementReport") is Dictionary:return physical_battle.settlementReport.duplicate(true)
	if physical_battle.get("_battleMirror051",false) and not physical_battle.get("simulation051",{}).get("retired",false):return fail("Retire the battle worker before settling its physical owners.")
	if str(context.get("kind",""))=="ocean066":
		if result!=physical_battle.get("result"):return fail("The offshore result must match its actual physical battle.")
		var problem066: String=OceanCampaign066.settlement_error(self,context,physical_battle)
		if not problem066.is_empty():return fail(problem066)
	if physical_battle.has("convoy"):
		if result!=physical_battle.get("result"):return fail("The convoy result must match its physical encounter.")
		var cargo_problem: String=EscortOps.cargo_error(self,physical_battle)
		if not cargo_problem.is_empty():return fail(cargo_problem)
		context=context.duplicate(true);context.objectiveOnly=true
	# The physical arena retains its actual chart origin; campaign time is paused during combat.
	if physical_battle.get("chartPosition") is Dictionary:
		context=context.duplicate(true)
		context.position114=physical_battle.chartPosition.duplicate(true)
		context.day114=float(state.day)
	var captures111: Array=Arc111.capture_snapshot(self,context,physical_battle)
	var captures114: Array=Arc114.capture_snapshot(self,context,physical_battle)
	CrisisOps.losses(self)
	var boarding_result: Dictionary=BoardingOps.settle(self,physical_battle)
	if not boarding_result.ok:return boarding_result
	var participants: Array=[]
	if physical_battle.is_empty():
		# Reference callers without a physical encounter keep their legacy API.
		FleetIdentity.record_service(self,active_fleet().map(func(b):return b.uid),result)
	else:
		if not physical_battle.get("serviceReport060") is Array:physical_battle.serviceReport060=_record_battle_service060(physical_battle,result)
		participants=physical_battle.serviceReport060.duplicate(true)
	if physical_battle.is_empty() or not physical_battle.has("engagementSource060"):
		state.battleSeq=int(state.get("battleSeq",0))+1
		if not physical_battle.is_empty():
			physical_battle.campaignSequence111=int(state.battleSeq)
			physical_battle.engagementSource060=str(physical_battle.get("convoyEngagementSource","engagement:%d:%d"%[state.seed,state.battleSeq]))
			if physical_battle.has("convoy"):physical_battle.convoyEngagementSource=physical_battle.engagementSource060
	var physical_wrecks: Array=[]
	if not physical_battle.is_empty():
		var source: String=str(physical_battle.engagementSource060)
		physical_wrecks=Salvage.record_battle(self,physical_battle,source)
		for ship in physical_battle.get("ships",[]):
			if ship.get("sunk",false):ship.wreckRecorded=true
		var hostile_arena: bool=result!="won" or context.get("objectiveOnly",false)
		if physical_battle.has("convoy"):
			hostile_arena=physical_battle.get("ships",[]).any(func(b):return str(b.get("team",""))=="enemy" and not b.get("sunk",false) and not b.get("captureSecured",false))
		if hostile_arena:
			state.wreckHazards[source]=str(context.get("ownerId",""))
			while state.wreckHazards.size()>256:state.wreckHazards.erase(state.wreckHazards.keys()[0])
		for record in physical_wrecks:
			if physical_battle.get("convoyWreckCargoApplied",false):break
			if not record.friendly:continue
			var live: Dictionary=Salvage.find_wreck(state,record.id)
			for good in state.get("cargoManifest",{}).get(record.uid,{}):
				if Goods.ITEMS.has(good):live.stores[good]=float(live.stores.get(good,0))+float(state.cargoManifest[record.uid][good])*0.5
		if not physical_wrecks.is_empty():physical_battle.convoyWreckCargoApplied=true
	var convoy_outcome: Dictionary=EscortOps.settle_cargo(self,physical_battle,physical_wrecks)
	if convoy_outcome.get("ok",true)==false:return convoy_outcome
	OceanCampaign066.settled(self,physical_battle,context,physical_wrecks)
	if not convoy_outcome.is_empty():
		for index in range(physical_wrecks.size()):
			physical_wrecks[index]=Salvage.find_wreck(state,str(physical_wrecks[index].id)).duplicate(true)
	CrisisOps.losses(self)
	BoardingOps.reconcile(self)
	FleetSupport.reconcile(self)
	for lost in Manifest.losses(state):log_entry("Lost %.1f %s aboard %s."%[lost.qty,lost.good,lost.boat])
	state.fleet = state.fleet.filter(func(s):return not s.sunk)
	if not state.fleet.is_empty() and not state.fleet.any(func(b):return str(b.uid)==str(state.flagship)):state.flagship=str(state.fleet[0].uid)
	Manifest.allocate(state)
	state.encounterGrace = 75.0
	stop_sailing()
	var loot: int = 0
	var salvage: Dictionary = {}
	var owner: Dictionary = fleet_owner(str(context.get("ownerId","")))
	RegionalOps.battle(self,owner,result,bool(context.get("objectiveOnly",false)),physical_battle)
	EscortOps.settled(self,result,context,convoy_outcome)
	if result == "won" and not context.get("objectiveOnly",false):
		state.wins += 1
		state.kills += enemy_specs.size()
		if not owner.is_empty():
			loot = floori(float(owner.coins)*0.30)
			Money.move(owner,"coins",state,"coins",loot,"Captured fleet operating coins",state.moneyLog)
			owner.active = owner.boats.any(func(b):return not b.sunk) if not physical_battle.is_empty() else false
			state.defeatedOwners[owner.id]=int(state.defeatedOwners.get(owner.id,0))+1
		state.renown += enemy_specs.size()*3
		if not enemy_specs.is_empty() and physical_battle.is_empty():
			salvage = enemy_specs[0]
			state.recoverable = {"hull":salvage.id,"claimed":false}
		if context.get("kind","") == "contract" and not state.activeContract.is_empty():
			state.activeContract.cleared = true
			var completion: Dictionary = finish_contract()
			loot += completion.get("reward",0)
		elif context.get("kind","") == "patrol":
			for patrol in state.patrols:
				if patrol.id == context.get("id",""):
					patrol.active = false
	elif result!="won":
		state.losses += 1
		state.morale = maxf(10.0,state.morale-6)
	Politics.settled(self,owner,result,context)
	if not owner.is_empty():Contacts.record_captain(state,str(owner.id),"engagement:%d:%d"%[int(state.seed),int(state.battleSeq)],"Encounter with your fleet: "+result)
	use_reserves()
	apply_morale()
	log_entry("Engagement %s. %d boats remain."%[result,state.fleet.size()])
	var report: Dictionary={"coins":loot,"salvage":salvage,"wrecks":physical_wrecks,"fleetLost":active_fleet().is_empty(),"completed":state.completed,"participants":participants,"losses":participants.filter(func(row):return str(row.fate) in ["sunk","captured"]).duplicate(true)}
	if not convoy_outcome.is_empty():
		report.convoy=convoy_outcome
	Arc111.after_battle(self,result,context,physical_battle,report,captures111)
	Arc112.after_battle(self,result,context,physical_battle,report)
	Arc116.after_battle(self,result,context,physical_battle,report)
	Arc114.after_battle(self,result,context,physical_battle,report,captures114)
	if not physical_battle.is_empty():
		report.escapedUids=physical_battle.get("escapedShips",[]).map(func(b):return str(b.get("uid","")))
		physical_battle.settlementReport=report.duplicate(true)
		for key in ["ships","escapedShips","captured"]:
			for ship in physical_battle.get(key,[]):ship.erase("_serviceStart060")
	travel_lock064=""
	return report

func salvage_quote(id: String) -> Dictionary:
	if not home_local064():return fail("Return to Shatter Coast before recovering a hull.")
	var h: Dictionary = hull(id)
	if h.is_empty():
		return {}
	var ordinary: int = ceili(h.size/14.0*3.0*Goods.SAILOR_WAGE)
	var expert: int = Goods.WAGES.engineer
	var fee: int = ceili((ordinary+expert)*0.10)
	return {"ordinary":ordinary,"expert":expert,"fee":fee,"total":ordinary+expert+fee}

func salvage_boat(id: String) -> Dictionary:
	if not home_local064():return fail("Return to Shatter Coast before recovering a hull.")
	var h: Dictionary = hull(id)
	if h.is_empty() or state.recoverable.get("hull","") != id or state.recoverable.get("claimed",true):
		return fail("No unclaimed wreck of that design.")
	if not can_add_boat(h):
		return fail(points_refusal(h))
	var q: Dictionary = salvage_quote(id)
	if state.coins < q.total:
		return fail("Recovery needs %d coins for tug labor, inspection and the company fee."%q.total)
	var birth_uid := "boat-%d" % int(state.nextUid)
	var staged: Dictionary = Lifecycle.stage_birth(state, data, h, birth_uid, {})
	if not staged.ok:
		return fail(str(staged.get("message", "Equipment birth was refused.")))
	if birth_uid != "boat-%d" % int(state.nextUid):
		return fail("The hull register changed before payment.")
	var base: Dictionary = port(state.lastPort)
	Money.move(state,"coins",base,"householdPurse",q.ordinary,"Salvage tug crew wages",state.moneyLog)
	Money.move(state,"coins",base,"expertPurse",q.expert,"Salvage engineer inspection",state.moneyLog)
	Money.move(state,"coins",base,"cash",q.fee,"Salvage company fee",state.moneyLog)
	state.recoverable.claimed = true
	var boat: Dictionary = add_boat(h, 0, staged)
	boat.hp = boat.maxHp*0.35
	return ok("%s recovered. Hire a crew, repair it and buy stores."%boat.name)

func rescue() -> Dictionary:
	if not active_fleet().is_empty():
		return fail("You already have a usable boat.")
	var home: Dictionary = port(data.START.port)
	var candidate: Dictionary = {}
	var selected_quote: Dictionary = {}
	# Re-crew an owned living hull before buying another; never strand boats to fit a cap.
	var existing: Dictionary = state.fleet[0] if not state.fleet.is_empty() else {}
	var hull_cost: int = 0
	if existing.is_empty():
		for id in home.shipIds:
			if home.shipStock.get(id,0) <= 0:
				continue
			var offer: Dictionary = hull(id)
			var q: Dictionary = ship_quote(offer,home)
			if candidate.is_empty() or q.readyPrice < selected_quote.readyPrice:
				candidate = offer
				selected_quote = q
		if candidate.is_empty():
			return fail("No replacement hull is ready at Brass Haven. Load your saved voyage or start a new campaign.")
		hull_cost = int(selected_quote.readyPrice)
	else:
		candidate = hull(existing.type)
	var wanted_crew: int = maxi(int(candidate.crewMin),mini(int(candidate.crewOptimal),int(data.START.crew)))
	var current_crew: int = int(existing.get("crew",0))
	var hires: int = maxi(0,wanted_crew-current_crew)
	if home.recruits < hires or home.workforce < hires:
		return fail("Brass Haven lacks sailors for another rescue. Load your saved voyage or start a new campaign.")
	var hiring: int = Economy.recruit_cost(home,hires) if hires > 0 else 0
	var repair: Dictionary = service_quote(existing,home) if not existing.is_empty() else {"cost":0,"purchase":0}
	if home.stocks.supplies < repair.purchase:
		return fail("The harbor lacks repair kits for this rescue.")
	var store_cost: int = 0
	for good in ["ammo","fuel","supplies"]:
		var target: float = 80.0 if good == "ammo" else 60.0 if good == "fuel" else 20.0
		var conversion: float = Goods.ROUNDS_PER_CASE if good == "ammo" else 1.0
		var have: float = float(existing.get(good,0.0))
		var amount: float = maxf(0.0,(target-have)/conversion)
		store_cost += ceili(minf(amount,float(home.stocks[good]))*Economy.price(home,good))
	var rations: int = ceili(maxf(0.0,8.0-state.cargo.food))
	var borrowed: int = hull_cost+hiring+int(repair.cost)+store_cost+rations*Economy.price(home,"food")+wanted_crew*Goods.SAILOR_WAGE*5
	if home.governmentPurse < borrowed:
		return fail("The harbor treasury cannot fund another rescue. Load a saved voyage or start a new campaign.")
	var staged: Dictionary = {}
	if existing.is_empty():
		var birth_uid := "boat-%d" % int(state.nextUid)
		staged = Lifecycle.stage_birth(state, data, candidate, birth_uid, {})
		if not staged.ok:
			return fail(str(staged.get("message", "Equipment birth was refused.")))
		if birth_uid != "boat-%d" % int(state.nextUid):
			return fail("The hull register changed before the rescue.")
	var rescue_state064: Dictionary=state.duplicate(true)
	var rescue_events064: Array=events.duplicate(true)
	state.world064={"schema":1,"layer":"home","regionId":"shatter_coast"}
	state.position = port_position(home.id)
	state.lastPort = home.id
	stop_sailing()
	Money.move(home,"governmentPurse",state,"coins",borrowed,"Harbor rescue loan",state.moneyLog)
	state.debt += borrowed
	var starter: Dictionary
	if existing.is_empty():
		var tax: int = int(selected_quote.get("tax",0))+int(selected_quote.get("readyStorageTax",0))
		Money.move(state,"coins",home,"cash",hull_cost-tax,"Real replacement hull from yard stock",state.moneyLog)
		Money.move(state,"coins",home,"governmentPurse",tax,"Replacement hull registry duty",state.moneyLog)
		home.shipStock[candidate.id] -= 1
		starter = add_boat(candidate, 0, staged)
	else:
		starter = existing
		starter.sunk = false
		var fixed: Dictionary = Harbor.repair(self,starter.uid)
		if not fixed.ok:
			# Return the unused loan rather than leave a failed rescue with invented resources.
			Money.move(state,"coins",home,"governmentPurse",borrowed,"Failed rescue loan returned",state.moneyLog)
			state.debt -= borrowed
			state=rescue_state064;events=rescue_events064
			return fixed
	if hires > 0:
		var hired: Dictionary = Harbor.recruit(self,starter.uid,hires)
		if not hired.ok:
			state=rescue_state064;events=rescue_events064
			return hired
	starter.mothballed = false
	state.flagship = starter.uid
	Harbor.resupply(self,starter.uid)
	if rations > 0:
		Economy.transact(home,state,"food",mini(rations,floori(home.stocks.food)),"buy",capacity())
	state.encounterGrace = 120.0
	apply_morale()
	log_entry("Brass Haven lent %d coins; the yard supplied a real hull, labor and stores."%borrowed)
	return ok("Rescue funded by a %d-coins harbor loan."%borrowed)

func log_entry(message: String):
	if state.is_empty():
		return
	state.log.push_front("Day %d · %s" % [int(state.day), message])
	if state.log.size() > 45:
		state.log.resize(45)

func pop_events() -> Array:
	var result = events.duplicate()
	events.clear()
	return result

func restore(saved: Dictionary) -> Dictionary:
	# Validate canonical sector/ledger first. Absence is the exact legacy atlas;
	# presence never calls generate, installs accounts or reapplies ownership.
	saved=saved.duplicate(true)
	var sector: Dictionary=SectorWorld069.prepare(saved,data,ocean_anchors064)
	if not sector.get("ok",false):return fail("Save refused: "+str(sector.get("message","Invalid saved sector.")))
	var revision=saved.get("mapRevision",1)
	if not (revision is int or revision is float) or not is_finite(float(revision)) or floorf(float(revision))!=float(revision) or int(revision) not in [1,2]:return fail("Save refused: invalid or unsupported coast revision.")
	var accounts: String=ShippingFlow068.sector_error069(saved)
	if not accounts.is_empty():return fail("Save refused: "+accounts)
	var territory: String=RegionalOps.validate(saved,data)
	if not territory.is_empty():return fail("Save refused: "+territory)
	var jobs070: String=SaveValidation.job_error070(saved,data)
	if not jobs070.is_empty():return fail("Save refused: "+jobs070)
	if saved.has("sector069"):saved.sector069=sector.sector
	var world: Dictionary=OceanWorld064.create(data,sector.atlas,nav,sector.sector.get("harbors",[]))
	if not world.get("ok",false):return fail("Save refused: "+str(world.get("message","Invalid saved ocean charts.")))
	var context: Dictionary=world.context
	if int(data.get("MAP_REVISION",1))>=2 and int(saved.get("mapRevision",1))<2:
		var prepared: Dictionary=CoastMigration.prepare(saved,data,nav,context)
		if not prepared.ok: return fail(prepared.message)
		saved=prepared.state
	var validation: Dictionary = SaveValidation.validate(saved,data,context)
	if not validation.ok:
		return fail("Save refused: "+str(validation.message)+" Use your backup.")
	var incoming: Dictionary = validation.get("state", saved)
	if incoming.has("world064") or not context.is_empty():
		var location: Dictionary=OceanWorld064.prepare_player(incoming,context,Routes.clearance({"state":incoming}))
		if not location.get("ok",false):return fail("Save refused: "+str(location.get("message","Invalid chart location.")))
		for key in ["world064","position","heading","path","destination"]:incoming[key]=location.location[key]
	if incoming.get("format", 0) != 2 or not incoming.get("fleet", null) is Array or incoming.fleet.size() > MAX_FLEET:
		return fail("This save is not a Brass Tide v0.001 campaign.")
	if not incoming.get("position", null) is Dictionary or not incoming.get("ports", null) is Array:
		return fail("The save has missing world data.")
	if incoming.ports.size() != data.PORTS.size()+(1 if ShippingFlow068.installed(incoming) else 0)+ShippingFlow068.harbors069(incoming).size():
		return fail("The save has the wrong coast layout.")
	for s in incoming.fleet:
		if not s is Dictionary or hull(str(s.get("type", ""))).is_empty():
			return fail("The save contains an unknown boat.")
	if Money.total(incoming) != int(incoming.get("coinSupply",-1)):
		return fail("The saved coin ledger is inconsistent; use your backup.")
	var memory: Dictionary=incoming.get("ocean066",OceanCampaign066.empty_book()).memory
	var made066: Dictionary=OceanCampaign066.Travel.create(context,int(incoming.seed),memory,OceanCampaign066.admitted_owner_ids(incoming),float(incoming.day)*DAY_SECONDS)
	if not made066.get("ok",false):return fail("Save refused: "+str(made066.get("message","Invalid saved ocean actors.")))
	# Even post-validation legacy ensures run on a detached Core. There is one
	# publication after equipment, accounts, parties, wrecks and runtime succeed.
	var candidate=get_script().new(data,nav,false)
	candidate.ocean_anchors064=ocean_anchors064
	candidate.ocean_context064=context
	candidate.ocean_context066=made066.context
	candidate.state=incoming
	var finished: Dictionary=candidate._finish_restore069()
	if finished.get("ok",false):_publish_runtime069(candidate)
	return finished

func _finish_restore069() -> Dictionary:
	route_cache.clear();route_hits=0;route_misses=0
	sailing_clearance=0.0
	pending_days = 0
	travel_lock064=""
	ocean_watch066=1.0;ocean_conditions066=[]
	_refit_published()
	state.coins = maxi(0, int(state.coins))
	state.day = maxf(1.0, float(state.day))
	state.missionIndex = clampi(int(state.missionIndex), 0, data.MISSIONS.size())
	for s in state.fleet:
		Damage.tick_ship(s, 0.0)
	for patrol in state.patrols:
		if NavalAI.NavalOrders.enrolled066(state,str(patrol.get("id",""))):continue
		# Saved chart position is authoritative; recompute a safe remaining route from there.
		var saved_position: Dictionary={"x":patrol.x,"y":patrol.y}
		set_patrol_course(patrol,saved_position,port(patrol.to))
		patrol.progress=0.0
		patrol.x=saved_position.x;patrol.y=saved_position.y
	validate_sailing_route()
	Manifest.allocate(state)
	pending_days = 0
	Exploration.ensure(state,data)
	var raw_wrecks: Array = []
	for wreck in state.get("wrecks", []):
		if wreck is Dictionary:
			raw_wrecks.append(wreck.duplicate(true))
	Salvage.ensure(state)
	Lifecycle.retain_wrecks(raw_wrecks, state)
	VoyageJobs.ensure(self)
	Contacts.ensure(state,data)
	Politics.ensure(self)
	NavalAI.ensure(state,data)
	TradeIntel.ensure(state)
	FleetIdentity.ensure(state)
	StoryOps.ensure(self)
	HomeOps.ensure(self)
	var territory: String=RegionalOps.validate(state,data)
	if not territory.is_empty():return fail("Save refused: "+territory)
	RegionalOps.ensure(self)
	TrainingOps.ensure(self)
	ReserveOps.ensure(self)
	ToolingOps.ensure(self)
	YardDevelopment.ensure(self)
	WorkerOps.ensure(self)
	RegionalGoodsOps.ensure(self)
	CompanyOps.ensure(self)
	if not state.get("campaignFacts") is Dictionary:state.campaignFacts={"escortsSaved":0,"goodsDelivered":0,"bountyWins":0,"licensedDesigns":0}
	if not state.get("escortEvents") is Dictionary:state.escortEvents={}
	if not state.has("battleSeq"):state.battleSeq=0
	if home_local064() and not state.recoverable.is_empty() and not state.recoverable.get("claimed",true):
		var legacy_site: Dictionary=state.position.duplicate(true)
		legacy_site.id="legacy-recovery"
		Salvage.seed_site_wreck(self,legacy_site,state.recoverable.hull,"legacy-recovery")
		state.recoverable.claimed=true
	apply_morale()
	if Money.total(state) != int(state.coinSupply):
		return fail("The saved coin ledger is inconsistent; use your backup.")
	BoardingOps.ensure(self)
	CrisisOps.ensure(self)
	LawOps.ensure(self)
	StoryOps.refresh(self)
	if Money.total(state)!=int(state.coinSupply):return fail("The restored coin ledger changed during detached preparation.")
	var sector_error: String=ShippingFlow068.sector_error069(state)
	if not sector_error.is_empty():return fail("Save refused: "+sector_error)
	# Existing/pending Westglass accounts are retained exactly here. Its original
	# funded installation may retry on a later daily tick, never as restore repair.
	return ok("Voyage restored.")

func canonical_npc_boat(boat: Dictionary, _player_owned: bool = false) -> void:
	var base: Dictionary = hull(str(boat.get("type","")))
	if base.is_empty() or boat.has("equipmentRetiredTo"):
		return
	var factor: float = clampf(float(boat.get("economyFactor", 1.0)), 0.35, 1.0)
	fit_boat(boat, false)
	if not boat.get("spec") is Dictionary:
		return
	boat.economyBaseSpeed = float(boat.spec.speed)
	boat.economyBaseFireRate = float(boat.spec.fireRate)
	boat.spec.speed *= factor
	boat.spec.fireRate *= factor

func ok(message: String) -> Dictionary:
	return {"ok": true, "message": message}

func fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}


func tooling_recovery_offer(site_id: String,kind: String) -> Dictionary:
	return ToolingOps.offer(self,site_id,kind)

func tooling_settle_recovery(requirements: Dictionary) -> Dictionary:
	return ToolingOps.settle(self,requirements)

func tooling_recipe(business_id: String,kind: String) -> Dictionary:
	return ToolingOps.binding(self,business_id,kind)

func tooling_hold_room(weight: float) -> bool:
	return ToolingOps.hold_room(self,weight)

func campaign_before_arrival112(owner: Dictionary,patrol: Dictionary) -> Dictionary:
	var prior: Dictionary=Arc112.before_arrival(self,owner,patrol)
	var observation116: Dictionary=Arc116.before_arrival(self,owner,patrol)
	if not observation116.is_empty():prior._arc116=observation116
	return prior

func campaign_after_arrival112(owner: Dictionary,patrol: Dictionary,dock: Dictionary,prior: Dictionary) -> void:
	Arc112.after_arrival(self,owner,patrol,dock,prior)
	Arc116.after_arrival(self,owner,patrol,dock,prior.get("_arc116",{}))

func campaign_witness_authorized115(origin: String,destination: String,count: int) -> bool:
	return Arc115.authorized(self,origin,destination,count)

func campaign_witness_reception115(job_id: String,destination: String,count: int) -> bool:
	return Arc115.reception(self,job_id,destination,count)

func campaign_witness_closed115(before: Dictionary,destination: String,loss: bool,earned: int) -> void:
	Arc115.after_closed(self,before,destination,loss,earned)

func campaign_naval_new116(event: Dictionary) -> void:
	Arc116.after_naval_encounter(self,event)

func campaign_refund117(job: Dictionary,amount: int) -> void:
	Arc117.observe_refund(self,job,amount)
