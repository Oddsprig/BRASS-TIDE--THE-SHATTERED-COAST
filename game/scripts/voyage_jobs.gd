extends RefCounted
const Routes=preload("res://scripts/route_cache.gd")
const Navigation=preload("res://scripts/navigation.gd")
## v0.011 side voyage jobs that run ALONGSIDE the single story contract.
## Existing contracts.gd APIs and state.activeContract/state.freight are never
## touched. Side jobs live in state["voyageJobs"] (Array, max MAX_ACTIVE) with
## closed ids in state["doneVoyageJobs"] (bounded). Freight exists ONLY inside
## job.freight {good, qty}: source stocks fall on acceptance, target stocks
## rise on delivery, and no path silently deletes sealed freight.
## Money.total counts each escrow; the physical manifest accounts for every lot.
## Civilian charters keep their real cohort's savings in this same escrow.

const Money = preload("res://scripts/money.gd")
const Goods = preload("res://scripts/goods.gd")
const Exploration = preload("res://scripts/exploration.gd")
const Economy=preload("res://scripts/economy.gd")
const Transport=preload("res://scripts/passenger_transport.gd")
const Reserves=preload("res://scripts/harbor_reserves.gd")
const Factions=preload("res://scripts/factions.gd")
const TradeRules=preload("res://scripts/trade_rules.gd")
const Contacts=preload("res://scripts/contacts.gd")
const Stories=preload("res://scripts/coastal_stories.gd")
const Expedition=preload("res://scripts/expedition.gd")
const TradeIntel=preload("res://scripts/trade_intel.gd")
const Regional=preload("res://scripts/regional_goods.gd")
const WorkRegion070=preload("res://scripts/voyage_region070.gd")

const MAX_ACTIVE := 6
const MAX_DONE := 128
const KIND_FREIGHT := "freight"
const KIND_SURVEY := "survey"
const KIND_BOUNTY := "bounty"
const KIND_FUEL := "fuel_delivery"
const KIND_CHARTER := "passenger_charter"
const KIND_ESCORT := "escort"
const STATE_OFFERED := "offered"
const STATE_ACTIVE := "active"
const STATE_EXPIRED := "expired"
const FREIGHT_GOODS := ["preserved_fish","fine_timber","lacquer","medicinal_plants","supplies", "food", "timber", "fuel"]
# Exploration work a full sighted->surveyed job may need (exploration.gd
# ACTIONS): chart 2 crew x 1.0 day + survey 4 crew x 2.5 days = 12 crew-days.
const SURVEY_CREW_DAYS := 12.0
# Two useful destinations and two real load sizes, rather than a route matrix.
const WORK_ROUTES := 2
const WORK_LOADS := ["small","larger"]


static func _is_num(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func _num(v, fallback: float = 0.0) -> float:
	return float(v) if _is_num(v) else fallback


static func _state(core) -> Dictionary:
	return core.state if core != null and core.get("state") is Dictionary else {}


static func _clean_freight(raw) -> Dictionary:
	if raw is Dictionary and Goods.ITEMS.has(str(raw.get("good", ""))) and _is_num(raw.get("qty", null)):
		var qty := clampf(float(raw["qty"]), 0.0, 100000.0)
		if qty > 0.0:
			return {"good":str(raw["good"]),"qty":qty,"lost":bool(raw.get("lost",false))}
	return {}


static func _sanitize_job(raw) -> Dictionary:
	if not (raw is Dictionary) or str(raw.get("id", "")).is_empty():
		return {}
	var job_state := str(raw.get("state", STATE_ACTIVE))
	if not job_state in [STATE_OFFERED, STATE_ACTIVE, STATE_EXPIRED]:
		job_state = STATE_ACTIVE
	var payer := str(raw.get("payerKey", "cash"))
	if not payer in (["coins"] if str(raw.get("kind",""))==KIND_ESCORT else ["cash", "governmentPurse"]):
		payer = "cash"
	return {
		"id": str(raw["id"]), "title": str(raw.get("title", "Voyage job")),
		"description": str(raw.get("description", "")), "port": str(raw.get("port", "")),
		"targetPort": str(raw.get("targetPort", "")), "kind": str(raw.get("kind", KIND_FREIGHT)),
		"regionId":str(raw.get("regionId","")).left(80),"targetRegionId":str(raw.get("targetRegionId","")).left(80),
		"reward": maxi(0, int(_num(raw.get("reward", 0)))),
		"escrow": maxi(0, int(_num(raw.get("escrow", 0)))),
		"payerKey": payer,
		"deadlineDay": _num(raw.get("deadlineDay", 0.0)),
		"acceptedDay": _num(raw.get("acceptedDay", 0.0)),
		"freight": _clean_freight(raw.get("freight", {})),
		"state": job_state,
		"siteId": str(raw.get("siteId", "")), "ownerId": str(raw.get("ownerId", "")),
		"materialInvoice":maxi(0,int(_num(raw.get("materialInvoice",0)))),"failed":bool(raw.get("failed",false)),
		"baselineDefeats":maxi(0,int(_num(raw.get("baselineDefeats",0)))),
		"carrierUid":str(raw.get("carrierUid","")),
		"escort":raw.get("escort",{}).duplicate(true) if raw.get("escort",{}) is Dictionary else {},
		"passengers":raw.get("passengers",{}).duplicate(true) if raw.get("passengers",{}) is Dictionary else {},
		"charterFood":raw.get("charterFood",{}).duplicate(true) if raw.get("charterFood",{}) is Dictionary else {},
		"savingsHousehold":maxi(0,int(_num(raw.get("savingsHousehold",0)))),"savingsExpert":maxi(0,int(_num(raw.get("savingsExpert",0)))),
		"routeDays":maxi(0,int(_num(raw.get("routeDays",0)))),"routeDistance":_num(raw.get("routeDistance",0)),
		"lastTickDay":_num(raw.get("lastTickDay",0)),"elapsedDays":_num(raw.get("elapsedDays",0)),"voyageDistance":_num(raw.get("voyageDistance",0)),"foodConsumed":_num(raw.get("foodConsumed",0)),
		"lastPosition":raw.get("lastPosition",{}).duplicate() if raw.get("lastPosition",{}) is Dictionary else {},
		"lostFuel":_num(raw.get("lostFuel",0)),
		"sponsorContactId":str(raw.get("sponsorContactId","")).left(80),
		"sponsorEventId":str(raw.get("sponsorEventId","")).left(240),
		"sponsorEventDay":maxf(0,_num(raw.get("sponsorEventDay",0))),
		"sponsorEventPort":str(raw.get("sponsorEventPort","")).left(80),
		"demandNeed":maxf(0,_num(raw.get("demandNeed",0))),
		"demandPurpose":str(raw.get("demandPurpose","")).left(480),
		"loadTier":str(raw.get("loadTier","")).left(16),
		"quotedDay":maxf(0,_num(raw.get("quotedDay",0))),
		"feeBasis":str(raw.get("feeBasis","")).left(640),
		"clientMemory":_clean_client_memory(raw.get("clientMemory",{})),
		"fuelPolicy":"operating_tanks" if str(raw.get("fuelPolicy",""))=="operating_tanks" else "three_drum",
	}


static func _clean_client_memory(raw) -> Dictionary:
	if not raw is Dictionary or str(raw.get("contactId","")).is_empty():return {}
	return {"contactId":str(raw.contactId).left(80),"name":str(raw.get("name","Client")).left(80),
		"completedCount":clampi(int(_num(raw.get("completedCount",0))),0,Contacts.MAX_LOG),
		"lastPaidDay":maxf(0,_num(raw.get("lastPaidDay",0))),
		"lastEventId":str(raw.get("lastEventId","")).left(240),
		"lastPort":str(raw.get("lastPort","")).left(80),"detail":str(raw.get("detail","")).left(240)}


# Normalizes state.voyageJobs / state.doneVoyageJobs. Returns the job array.
static func ensure(core) -> Array:
	var state := _state(core)
	if state.is_empty():
		return []
	if not (state.get("voyageJobs") is Array):
		state["voyageJobs"] = []
	var cleaned: Array = []
	var seen := {}
	for raw in state["voyageJobs"]:
		var job := _sanitize_job(raw)
		if not job.is_empty() and not seen.has(job["id"]):
			seen[job["id"]] = true
			cleaned.append(job)
	state["voyageJobs"] = cleaned.slice(0, MAX_ACTIVE)
	if not (state.get("doneVoyageJobs") is Array):
		state["doneVoyageJobs"] = []
	var done: Array = []
	for id in state["doneVoyageJobs"]:
		if id is String and not done.has(id):
			done.append(id)
	while done.size() > MAX_DONE:
		done.pop_front()
	state["doneVoyageJobs"] = done
	return state["voyageJobs"]


static func _find(state: Dictionary, id: String) -> Dictionary:
	for job in state.get("voyageJobs", []):
		if job is Dictionary and str(job.get("id", "")) == id:
			return job
	return {}


static func _is_closed(state: Dictionary, id: String) -> bool:
	return id in (state.get("doneVoyageJobs", []) if state.get("doneVoyageJobs") is Array else [])


static func _close(state: Dictionary, job: Dictionary) -> void:
	state["voyageJobs"].erase(job)
	var done: Array = state["doneVoyageJobs"]
	if not done.has(str(job["id"])):
		done.append(str(job["id"]))
	while done.size() > MAX_DONE:
		done.pop_front()


# Weight of every active/expired side-job freight lot. Until root folds this
# into campaign cargo_weight(), accept() adds it locally; story-contract
# freight is already inside core.cargo_weight() and is never counted twice.
static func pending_freight_weight(state: Dictionary) -> float:
	var weight := 0.0
	for job in state.get("voyageJobs", []) if state.get("voyageJobs") is Array else []:
		if job is Dictionary:
			var freight := _clean_freight(job.get("freight", {}))
			if not freight.is_empty():
				weight += float(freight["qty"]) * float(Goods.ITEMS[str(freight["good"])]["weight"])
	return snappedf(weight, 0.01)


static func _effective_free(core, state: Dictionary) -> float:
	if core == null or not core.has_method("capacity") or not core.has_method("cargo_weight"):
		return 0.0
	return float(core.capacity())-float(core.cargo_weight())


static func _travel_days(core, a: Dictionary, b: Dictionary) -> float:
	if core == null or not core.has_method("distance") or not core.has_method("travel_speed"):
		return 1.0
	var seconds := float(core.get("DAY_SECONDS")) if _is_num(core.get("DAY_SECONDS")) else 45.0
	var route: Array=Routes.path(core,a,b)
	var length: float=0.0
	for i in range(1,route.size()):length+=core.distance(route[i-1],route[i])
	var speed: float=float(core.hull("tin_skiff").get("speed",75))*1.55*float(core.data.get("CAMPAIGN_SCALE",1))
	return maxf(0.05,length/maxf(1,speed)/maxf(1,seconds))


# Wages-derived route reward, mirroring contracts.gd delivery pricing: the
# captain's living crew at 100 coins/sailor-day for a there-and-back margin
# (x2 the one-way time), plus one lot of cargo handling value.
static func _route_reward(core,days: float,good: String="",survey: bool=false,p: Dictionary={}) -> int:
	if p.is_empty():p=WorkRegion070.work_port(core)
	if survey:return WorkRegion070.survey_reward(core,p,days)
	var crew: int=5
	var work_days: float=maxf(1,ceilf(days*2.0+(3.5 if survey else 0.25)))
	var value: float=crew*Goods.SAILOR_WAGE*work_days
	value+=crew*0.08*work_days*Economy.price(p,"food")
	value+=maxf(0.15,days*2)*0.65*Economy.price(p,"fuel")
	value+=(3.0 if survey else 0.25)*Economy.price(p,"supplies")
	value+=Goods.WAGES.laborer # quay handling / chart registration worker-day
	return maxi(1,ceili(value*1.25))


static func _refund_escrow(core, state: Dictionary, job: Dictionary, reason: String) -> void:
	# Household/expert savings belong to the passengers until discharge or loss.
	var amount := maxi(0,int(job.get("escrow",0))-int(job.get("savingsHousehold",0))-int(job.get("savingsExpert",0)))
	if amount <= 0:
		return
	var sponsor: Dictionary = core.fleet_owner(str(job.ownerId)) if str(job.kind)==KIND_ESCORT else (core.port(str(job["port"])) if core.has_method("port") else {})
	if sponsor.is_empty():
		return  # escrow stays on the job record; never vanish it silently
	var ledger: Array = state.get("moneyLog", []) if state.get("moneyLog") is Array else []
	if Money.move(job, "escrow", sponsor, str(job["payerKey"]), amount, reason, ledger):
		state["moneyLog"] = ledger
		if core is Object and core.has_method("campaign_refund117"):core.campaign_refund117(job,amount)


# Lazy expiry on mutating calls only. Expired escrow returns to the sponsor;
# expired freight stays sealed in job.freight until abandon() unloads it at a
# harbor, so cargo can never evaporate with a missed deadline.
static func _expire_overdue(core, state: Dictionary) -> void:
	var today := _num(state.get("day", 0.0))
	for job in state["voyageJobs"]:
		if str(job.get("state", "")) == STATE_ACTIVE and (today > float(job.get("deadlineDay", 0.0)) or bool(job.get("failed",false))):
			job["state"] = STATE_EXPIRED
			_refund_escrow(core, state, job, "Expired voyage job escrow refunded")
			if core.has_method("log_entry"):
				core.log_entry("Voyage job expired: %s. Escrow refunded; any sealed freight must be unloaded at a harbor." % str(job["title"]))


static func _destination(state: Dictionary, from: Dictionary, salt: int) -> Dictionary:
	var ports: Array = state.get("ports", []) if state.get("ports") is Array else []
	ports=ports.filter(func(port):return port is Dictionary and str(port.get("regionId","shatter_coast"))=="shatter_coast")
	if str(from.get("regionId","shatter_coast"))!="shatter_coast":return {}
	if ports.size() < 2:
		return {}
	var index := ports.find(from)
	if index < 0:
		index = 0
	var day := int(_num(state.get("day", 1.0)))
	return ports[(index + 1 + salt + (day % 3)) % ports.size()]


# Read existing permissions without Politics.ensure changing a preview's state.
static func _work_access(c,p: Dictionary,good: String="",origin: Dictionary={}) -> bool:
	if p.is_empty():return false
	var access: Dictionary=Factions.access(c.state,p)
	var pass_until: float=_num(c.state.get("relationships",{}).get("safeConduct",{}).get(str(p.id),0))
	if not bool(access.get("contracts",false)) and pass_until<=float(c.state.day):return false
	if origin.is_empty():origin=WorkRegion070.work_port(c)
	return good.is_empty() or TradeRules.allowed(c.state.get("tradeLaw",{}).get("bans",[]),str(origin.get("faction","")),str(p.get("faction","")),good,float(c.state.day))


# The existing manifest allocates cargo around physical lockers. Transport's
# legacy free-room display omits their mass and captive overflow; new job checks
# must subtract them on the selected hull as well as checking fleet-wide room.
static func _carrier_free(c,b: Dictionary) -> float:
	var overflow: float=maxf(0,float(c.state.get("captiveBerths",{}).get(str(b.get("uid","")),0))-maxf(0,float(b.get("crewMax",0))-float(b.get("crew",0))))
	return maxf(0,Transport.available_hold(c,b)-Expedition.locker_weight(b)-overflow)


static func _freight_room(c) -> float:
	var free: float=0.0
	for b in c.active_fleet():free+=_carrier_free(c,b)
	return maxf(0,minf(free,_effective_free(c,c.state)))


# Cheap bounded candidate ranking, then only selected useful water routes.
static func _work_destinations(c,p: Dictionary) -> Array:
	var candidates: Array=[]
	for target in WorkRegion070.destinations(c,p):
		if _work_access(c,target):candidates.append(target)
	return candidates


static func _promised_freight(state: Dictionary,target: String,good: String) -> float:
	var promised: float=0.0
	for j in state.get("voyageJobs",[]):
		if str(j.get("state",""))==STATE_ACTIVE and str(j.get("kind",""))==KIND_FREIGHT and str(j.get("targetPort",""))==target and str(j.get("freight",{}).get("good",""))==good:
			promised+=_num(j.freight.get("qty",0))
	return promised


# A fixed catalog carrier tariff, never the player's arbitrary fleet bill.
# Existing 100/sailor-day, 0.08 rations, actual hull speed/burn, quarter kit,
# one quay worker-day and 25% margin remain the underlying route/labor model.
static func _work_fee(c,p: Dictionary,days: float,kind: String,qty: int,weight: float) -> Dictionary:
	var best: Dictionary={}
	for spec in c.data.get("HULLS",[]):
		var role: String=str(spec.get("civilianRole",""))
		if kind==KIND_FUEL and role!="tanker":continue
		if kind==KIND_FREIGHT and role!="transport":continue
		if kind==KIND_CHARTER and role not in ["transport","yacht"]:continue
		var crew: int=maxi(1,int(spec.get("crewMin",1)))
		if kind==KIND_CHARTER and int(spec.get("crewMax",0))-crew<qty:continue
		var transit: float=days*float(c.hull("tin_skiff").get("speed",118))/maxf(1,float(spec.get("speed",1)))
		var paid_days: float=maxf(1,ceilf(2.0*transit+0.25))
		var upkeep: Dictionary=Economy.daily_upkeep([{"crew":crew,"spec":spec,"sunk":false}])
		var crew_food: float=float(upkeep.food)*paid_days
		var passenger_food: float=Transport.quantity(qty,ceili(transit)+2) if kind==KIND_CHARTER else 0.0
		if float(spec.get("cargo",0))+0.000001<weight+crew_food+passenger_food:continue
		var burn: float=45.0*(0.011+float(spec.get("size",14))*0.0002)*maxf(0.2,float(spec.get("fuelUse",1)))
		var fuel: float=burn*transit*2.0
		var value: float=crew*Goods.SAILOR_WAGE*paid_days+crew_food*Economy.price(p,"food")+fuel*Economy.price(p,"fuel")+0.25*Economy.price(p,"supplies")+Goods.WAGES.laborer
		var reward: int=maxi(1,ceili(1.25*value))
		if kind==KIND_CHARTER:reward+=qty*Goods.SAILOR_WAGE*maxi(1,ceili(transit))
		if not best.is_empty() and reward>=int(best.reward):continue
		best={"reward":reward,"days":transit,"feeBasis":"Catalog %s, %d minimum sailors at %d coins/day, %.0f whole payroll days for return route + quarter-day handling; %.2f rations, %.2f sailing fuel, quarter repair kit, one quay laborer-day, 25%% margin.%s Extra owned crew, specialists, delays and damage remain your costs."%[str(spec.get("name","carrier")),crew,Goods.SAILOR_WAGE,paid_days,crew_food,fuel," Charter adds %d passenger-days at %d coins."%[qty*maxi(1,ceili(transit)),Goods.SAILOR_WAGE] if kind==KIND_CHARTER else ""]}
	return best


# Quantity is visible in the ID; every other contractual term is fingerprinted.
# Repricing or a changed route yields a different ID, never changed old promises.
static func _work_id(p: Dictionary,day: int,kind: String,target: String,subject: String,qty: int,q: Dictionary) -> String:
	var terms: Array=[q.get("reward",0),q.get("materialInvoice",0),q.get("deadlineDay",0),q.get("routeDays",0),q.get("routeDistance",0),q.get("passengers",{}),q.get("charterFood",{}),q.get("savingsHousehold",0),q.get("savingsExpert",0),q.get("fuelPolicy",""),q.get("feeBasis","")]
	return "v059-%s-%s-%d-%s-%s-%d-%s"%[kind,str(p.id),day,target,subject,qty,JSON.stringify(terms).sha256_text().left(16)]


static func _catalog_load_room(c,days: float,kind: String) -> int:
	var room: float=0.0
	for spec in c.data.get("HULLS",[]):
		if str(spec.get("civilianRole",""))!=("tanker" if kind==KIND_FUEL else "transport"):continue
		var transit: float=days*float(c.hull("tin_skiff").get("speed",118))/maxf(1,float(spec.get("speed",1)))
		var paid_days: float=maxf(1,ceilf(2.0*transit+0.25))
		var upkeep: Dictionary=Economy.daily_upkeep([{"crew":int(spec.get("crewMin",1)),"spec":spec,"sunk":false}])
		room=maxf(room,float(spec.get("cargo",0))-float(upkeep.food)*paid_days)
	return maxi(0,floori(room))


# At most three monotone funding clips; never grant money or silently reprice
# an offered ID. The resulting exact qty/invoice/fee become that ID's terms.
static func _funded_load(c,p: Dictionary,days: float,kind: String,limit: int,good: String) -> Dictionary:
	var qty: int=limit
	var price: int=Economy.price(p,good)
	for attempt in range(3):
		if qty<1:return {}
		var fee: Dictionary=_work_fee(c,p,days,kind,qty,qty*float(Goods.ITEMS[good].weight))
		if fee.is_empty():return {}
		var invoice: int=qty*price
		if int(p.get("governmentPurse",0))>=int(fee.reward)+invoice:
			fee.qty=qty;fee.invoice=invoice;return fee
		qty=mini(qty-1,floori(float(int(p.get("governmentPurse",0))-int(fee.reward))/maxi(1,price)))
	return {}


static func _freight_needs(target: Dictionary) -> Dictionary:
	var needs: Dictionary=TradeIntel._observed_needs(target)
	# Reuse023's existing consumption/three-day buffer for all four finished
	# goods; neither produce stock nor invent another population demand series.
	var buffer: float=Regional._need_per_day(target)*Regional.BUFFER_DAYS/float(Regional.IDS.size())
	for good in Regional.IDS:
		needs[good]={"observedNeed":maxf(0,buffer-_num(target.get("stocks",{}).get(good,0))),
			"needPurpose":"Existing households' %.2f-lot share of the regional three-day consumption buffer, less actual stock; the treasury funds this finite relief purchase."%buffer}
	return needs


static func _freight_offers(c,p: Dictionary,day: int,taken: Dictionary) -> Array:
	var out: Array=[]
	var routes: int=0
	var room: float=_freight_room(c)
	if room<=0:return out
	var exports: Dictionary=Reserves.report(p).goods
	for target in _work_destinations(c,p):
		if routes>=WORK_ROUTES:break
		var needs: Dictionary=_freight_needs(target)
		var selected: String="";var limit: int=0;var need: float=0.0;var score: float=-1.0
		# Preserve a useful regional finished-goods route when actually funded;
		# the other route favors bulk household/recipe inputs for larger holds.
		for good in FREIGHT_GOODS:
			if not needs.has(good) or not _work_access(c,target,good):continue
			var gap: float=maxf(0,_num(needs[good].get("observedNeed",0))-_promised_freight(c.state,str(target.id),good))
			var weight: float=float(Goods.ITEMS[good].weight)
			var amount: int=floori(minf(gap,minf(_num(exports.get(good,{}).get("exportable",0)),room/weight)))
			if amount<1:continue
			var priority: float=gap/maxf(1,float(Economy.get_equilibrium_stock(target,good)))
			if (routes==0 and good in Regional.IDS) or (routes>0 and good not in Regional.IDS):priority+=2.0
			if priority<=score:continue
			selected=good;limit=amount;need=gap;score=priority
		if selected.is_empty():continue
		var route: Dictionary=WorkRegion070.route(c,target,p)
		if not route.ok:continue
		var days: float=float(route.referenceDays)
		limit=mini(limit,floori(float(_catalog_load_room(c,days,KIND_FREIGHT))/float(Goods.ITEMS[selected].weight)))
		var small: int=mini(8,limit)
		var added: bool=false
		for tier in WORK_LOADS:
			var fee: Dictionary=_funded_load(c,p,days,KIND_FREIGHT,small if tier=="small" else limit,selected)
			if fee.is_empty():continue
			var qty: int=int(fee.qty)
			if tier=="larger" and qty<=small:continue
			var invoice: int=int(fee.invoice)
			var offer: Dictionary={"title":"%s freight: %d %s to %s"%[str(tier).capitalize(),qty,str(Goods.ITEMS[selected].name),str(target.name)],"description":"Treasury purchases existing exportable cargo for a current household/production stock gap and escrows the fee; this is finite relief, not guaranteed future demand.","port":str(p.id),"targetPort":str(target.id),"kind":KIND_FREIGHT,"reward":int(fee.reward),"escrow":0,"payerKey":"governmentPurse","materialInvoice":invoice,"failed":false,"deadlineDay":float(day)+ceilf(maxf(days,float(fee.days))*2+6),"acceptedDay":0.0,"freight":{"good":selected,"qty":float(qty)},"state":STATE_OFFERED,"siteId":"","ownerId":"","demandNeed":need,"demandPurpose":str(needs[selected].needPurpose),"loadTier":tier,"quotedDay":float(c.state.day),"feeBasis":str(fee.feeBasis)}
			offer.regionId=WorkRegion070.region(p);offer.targetRegionId=WorkRegion070.region(target)
			offer.id=_work_id(p,day,KIND_FREIGHT,str(target.id),selected,qty,offer)
			if taken.has(offer.id) or _is_closed(c.state,str(offer.id)):continue
			out.append(offer);added=true
		if added:routes+=1
	return out


# A preference for the accepted current objective, never another reward or
# progression event. The journal's detached objective comes from its real gate.
static func survey_pairing(core, port_id: String = "") -> Dictionary:
	var state := _state(core)
	if state.is_empty():return {}
	var harbor: String=port_id
	if harbor.is_empty():harbor=str(WorkRegion070.work_port(core).get("id",""))
	if harbor!="reed_floats":return {}
	for entry in Stories.journal(state.duplicate(true)):
		if str(entry.get("chainId",""))!="middle_sea_chart" or bool(entry.get("done",false)):continue
		var objective: Dictionary=entry.get("objective",{})
		var site_id: String=str(objective.get("siteId",""))
		if site_id.is_empty():return {}
		for job in state.get("voyageJobs",[]):
			if str(job.get("kind",""))==KIND_SURVEY and str(job.get("siteId",""))==site_id:return {}
		for raw in Exploration._catalog(state):
			var site: Dictionary=Exploration._merged(state,raw)
			if str(site.id)==site_id and int(site.level)<Exploration.LEVEL_SURVEYED:
				return {"chainId":"middle_sea_chart","siteId":site_id,"siteName":str(site.name),
					"storyLevel":int(objective.get("requiredLevel",Exploration.LEVEL_SURVEYED)),
					"paidLevel":Exploration.LEVEL_SURVEYED,"reportPort":harbor}
	return {}


# Deterministic same-day offers at the harbor the captain is docked at. Ids
# embed port + day (+ site/owner), so reopening the board never rerolls, and
# accepted/closed ids never reappear. Offers are only listed while the
# sponsor purse can fund the full escrow and, for freight, the source port
# physically holds the sealed lot.
static func available(core) -> Array:
	var state := _state(core)
	if state.is_empty() or not core.has_method("current_port"):
		return []
	var offers: Array = []
	var p: Dictionary = WorkRegion070.work_port(core)
	if p.is_empty():
		return offers
	if not _work_access(core,p):return offers
	var day := int(_num(state.get("day", 1.0)))
	var taken := {}
	for job in state.get("voyageJobs",[]):
		taken[str(job["id"])] = true
	offers.append_array(_freight_offers(core,p,day,taken))
	# Survey: prefer Wren's accepted current site, otherwise retain the daily
	# catalog selection. A site already on a carried survey is not new paid work.
	var unsurveyed: Array=WorkRegion070.survey_candidates(core,p)
	if not unsurveyed.is_empty():
		var pairing: Dictionary=survey_pairing(core,str(p.id))
		for site in WorkRegion070.ranked_surveys(core,p,day,unsurveyed,pairing):
			var survey_id := "vsurvey-%s-%d-%s" % [str(p["id"]), day, str(site["id"])]
			if taken.has(survey_id) or _is_closed(state,survey_id):continue
			var route: Dictionary=WorkRegion070.route(core,site,p,true)
			if not route.ok:continue
			var days: float=float(route.referenceDays)
			var reward: int=WorkRegion070.survey_reward(core,p,days,site)
			if reward<=0 or int(p.get("governmentPurse",0))<reward:continue
			offers.append(WorkRegion070.survey_offer(p,site,pairing,survey_id,day,days,reward))
			break
	# Bounty: the first actually active patrol raider owner, if one is at sea.
	var bounty_id := "vbounty-%s-%d" % [str(p["id"]), day]
	if not taken.has(bounty_id) and not _is_closed(state, bounty_id):
		for owner in state.get("fleetOwners", []) if state.get("fleetOwners") is Array else []:
			if not (owner is Dictionary) or str(owner.get("kind", "")) != "raider" or not str(owner.get("id", "")).begins_with("patrol-") or not bool(owner.get("active", false)):
				continue
			if str(owner.get("faction",""))==str(p.get("faction","")):continue
			if str(owner.get("world064",{}).get("regionId",Exploration.HOME_REGION))!=WorkRegion070.region(p):continue
			var living := 0
			var enemy_value := 0.0
			for boat in owner.get("boats", []) if owner.get("boats") is Array else []:
				if boat is Dictionary and not bool(boat.get("sunk", false)):
					living += 1
					if core.has_method("hull"):
						enemy_value += _num(core.hull(str(boat.get("type", ""))).get("price", 0.0))
			if living == 0:
				continue
			var reward := maxi(1, ceili(enemy_value * 0.45 + float(Goods.SAILOR_WAGE) * 10.0))
			if int(p.get("governmentPurse", 0)) >= reward:
				offers.append({
					"id": bounty_id, "title": "Harbor bounty: %s" % str(owner.get("name", "raiders")),
					"description": "The harbor government escrows this bounty. Destroy or disable the named raider fleet, then claim here.",
					"port": str(p["id"]), "targetPort": str(p["id"]), "kind": KIND_BOUNTY,
					"reward": reward, "escrow": 0, "payerKey": "governmentPurse",
					"deadlineDay": float(day) + 20.0, "acceptedDay": 0.0,
					"freight": {}, "state": STATE_OFFERED,
					"siteId": "", "ownerId": str(owner["id"])})
			break
	offers.append_array(_civilian_offers(core,p,day,taken))
	if state.get("storyRights") is Dictionary:offers.append_array(preload("res://scripts/story_offers.gd").available(core))
	if core is Object and core.has_method("campaign_material_offer113"):
		var material113: Dictionary=core.campaign_material_offer113()
		if not material113.is_empty() and not taken.has(str(material113.id)) and not _is_closed(state,str(material113.id)):offers.append(material113)
	if core is Object and core.has_method("campaign_passage_offer119"):
		var passage119: Dictionary=core.campaign_passage_offer119()
		if not passage119.is_empty() and not taken.has(str(passage119.id)) and not _is_closed(state,str(passage119.id)):
			offers.append(passage119)
	_attach_client_memory(core,p,offers)
	_select_contact_work(core,p,offers)
	return offers


# Explain repeat business using paid work only. This does not reissue the056
# one-use introduction, reserve an offer or create another fee/reward purse.
static func _attach_client_memory(c,p: Dictionary,offers: Array) -> void:
	for offer in offers:
		if str(offer.kind)==KIND_FUEL:
			var captain: Dictionary=Contacts.client_memory(c.state,"captain:"+str(offer.get("ownerId","")))
			if not captain.is_empty():offer.clientMemory=captain
		if offer.has("clientMemory"):continue
		if WorkRegion070.region(p)!=Exploration.HOME_REGION:
			var harbor_memory: Dictionary=Contacts.client_memory(c.state,"harbor:"+str(p.id))
			if not harbor_memory.is_empty():offer.clientMemory=harbor_memory
			continue # Core records this existing harbor desk's actual payment.
		for definition in Contacts.DEFINITIONS:
			if str(definition.port)!=str(p.id) or not _contact_role_fits(str(definition.role),offer):continue
			var memory: Dictionary=Contacts.client_memory(c.state,str(definition.id))
			if not memory.is_empty():offer.clientMemory=memory
			break


static func _remember_client(c,job: Dictionary,paid: bool) -> void:
	var memory: Dictionary=job.get("clientMemory",{})
	var contact_id: String=str(memory.get("contactId",""))
	if contact_id.is_empty() or contact_id.begins_with("captain:"):return # Campaign records actual recipient captain service.
	# An accepted client field is explanatory, not authority to mint trust for
	# an unknown person: require the same role/harbor and retained paid evidence.
	for definition in Contacts.DEFINITIONS:
		if str(definition.id)!=contact_id or str(definition.port)!=str(job.port) or not _contact_role_fits(str(definition.role),job):continue
		if Contacts.client_memory(c.state,contact_id).is_empty():return
		Contacts.record(c.state,contact_id,"job:"+str(job.id)+(":paid" if paid else ":abandoned"),5 if paid else -5,str(job.title),str(c.current_port().get("id","")))
		return


# Select from the actual board rather than issuing a second contract/reward.
# Only one original contact lives at each authored harbor. The original offer
# id remains authoritative for duplicate suppression and all transactions.
static func _select_contact_work(core, p: Dictionary, offers: Array) -> void:
	if core.state.get("voyageJobs",[]).size()>=MAX_ACTIVE or core.active_fleet().is_empty() or not core.state.path.is_empty():return
	for definition in Contacts.DEFINITIONS:
		if str(definition.port)!=str(p.id):continue
		var contact: Dictionary=Contacts._find(core.state,str(definition.id))
		if contact.get("workOpportunityUsed",false):return
		var memory: Dictionary=Contacts.completed_work(core.state,str(definition.id))
		if memory.is_empty():return
		for offer in offers:
			if not _contact_role_fits(str(definition.role),offer) or not _contact_hold_fits(core,offer):continue
			offer.sponsorContactId=str(definition.id)
			offer.sponsorEventId=str(memory.event)
			offer.sponsorEventDay=float(memory.day)
			offer.sponsorEventPort=str(memory.get("port",""))
			return


static func _contact_role_fits(role: String, offer: Dictionary) -> bool:
	var kind: String=str(offer.kind)
	if role=="broker":return kind in [KIND_FREIGHT,KIND_FUEL,KIND_CHARTER]
	if role=="survey_patron":return kind==KIND_SURVEY
	if role=="salvage_agent" and kind==KIND_BOUNTY:return true
	return role in ["shipwright","salvage_agent"] and (kind==KIND_FUEL or (kind==KIND_FREIGHT and str(offer.get("freight",{}).get("good","")) in ["timber","fine_timber","supplies","fuel"]))


static func _contact_hold_fits(core, offer: Dictionary) -> bool:
	var freight: Dictionary=offer.get("freight",{})
	if not freight.is_empty():
		var weight: float=float(freight.qty)*float(Goods.ITEMS[str(freight.good)].weight)
		if weight>_effective_free(core,core.state):return false
	if str(offer.kind)==KIND_FUEL:return not _fuel_carrier(core,float(freight.get("qty",0))).is_empty()
	# The existing civilian offer builder already quotes a real eligible hull,
	# cohort and provisions. board_charter rechecks the chosen hull at acceptance.
	return true


# Detached, noncommitting view. No offer is reserved until ordinary accept().
# Empty means no earned, funded, compatible work at this contact's harbor now.
static func contact_opportunity(core, contact_id: String) -> Dictionary:
	if contact_id.is_empty():return {}
	for offer in available(core):
		if str(offer.get("sponsorContactId",""))==contact_id:return offer.duplicate(true)
	return {}


static func offer_view070(core,offer: Dictionary) -> Dictionary:
	return WorkRegion070.offer_view(core,offer)


static func _fail(core, message: String) -> Dictionary:
	return core.fail(message) if core != null and core.has_method("fail") else {"ok": false, "message": message}


static func _ok(core, message: String, extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = core.ok(message) if core != null and core.has_method("ok") else {"ok": true, "message": message}
	out.merge(extra, true)
	return out


# Accepts one listed offer. All checks (roster room, sponsor funds, physical
# stock, combined hold space) run before any stock, coin or job write, so a
# refusal is atomic. Survey acceptance legitimately sights the rumored site
# through exploration's own discover_near; it grants no goods or progress.
static func accept(core, id: String,boat_uid: String="") -> Dictionary:
	var state := _state(core)
	if state.is_empty():
		return _fail(core, "No campaign state.")
	ensure(core)
	_expire_overdue(core, state)
	if not _find(state, id).is_empty():
		return _fail(core, "That voyage job is already accepted.")
	if _is_closed(state, id):
		return _fail(core, "That voyage job is already settled.")
	var offer := {}
	for candidate in available(core):
		if str(candidate.get("id", "")) == id:
			offer=_sanitize_job(candidate)
	if offer.is_empty():
		return _fail(core, "This voyage job is no longer available.")
	var active_count := 0
	for job in state["voyageJobs"]:
		if str(job.get("state", "")) == STATE_ACTIVE:
			active_count += 1
	if state.voyageJobs.size()>=MAX_ACTIVE:
		return _fail(core, "You already carry %d side jobs. Finish or abandon one first." % MAX_ACTIVE)
	var p: Dictionary = WorkRegion070.work_port(core)
	if p.is_empty() or str(p.get("id", "")) != str(offer["port"]):
		return _fail(core, "Accept this job at its sponsoring harbor.")
	if int(p.get(str(offer["payerKey"]),0))<int(offer.reward)+int(offer.get("materialInvoice",0)):
		return _fail(core, "The sponsor cannot fund this job's escrow today.")
	if str(offer.kind)==KIND_CHARTER:
		var selected: Dictionary=_charter_quote(core,str(offer.port),str(offer.targetPort),int(offer.passengers.n),boat_uid)
		var passenger_view=WorkRegion070.charter_view(core,p,core.port(str(offer.targetPort)))
		if selected.is_empty() or passenger_view==null or not Transport.board_charter(passenger_view,offer,str(selected.carrierUid)):return _fail(core,"Charter needs real available people, funded provisions and spare berths and hold after lockers on the selected transport or yacht.")
		offer.state=STATE_ACTIVE;offer.acceptedDay=float(state.day)
		state.voyageJobs.append(offer)
		if not str(offer.get("sponsorContactId","")).is_empty():Contacts.claim_work_opportunity(state,str(offer.sponsorContactId))
		core.log_entry("Funded charter embarked %d actual people aboard %s."%[offer.passengers.n,offer.carrierUid])
		return _ok(core,"Charter funded, provisioned and boarded.",{"job":offer.duplicate(true)})
	var freight := _clean_freight(offer.get("freight", {}))
	if str(offer.kind)==KIND_FUEL:
		var recipient: Dictionary=recipient_status(core,offer)
		if not recipient.present:return _fail(core,"The actual recipient is no longer stopped at the quoted harbor.")
		if not recipient.eligible:return _fail(core,"This treasury cannot sponsor fuel under the current fleet and harbor access rules.")
		var carrier: String=_fuel_carrier(core,float(freight.get("qty",0)),boat_uid)
		if carrier.is_empty():return _fail(core,"Choose a crewed transport or tanker with room for the entire sealed fuel lot.")
		offer.carrierUid=carrier
	if not freight.is_empty():
		var stocks: Dictionary = p.get("stocks", {}) if p.get("stocks") is Dictionary else {}
		var weight := float(freight["qty"]) * float(Goods.ITEMS[str(freight["good"])]["weight"])
		if _num(stocks.get(str(freight["good"]), 0.0)) < float(freight["qty"]):
			return _fail(core, "The sponsor no longer holds that sealed cargo.")
		if weight > _effective_free(core, state):
			return _fail(core, "Your hold, counting every other commitment, cannot fit that sealed cargo.")
		if str(offer.kind)==KIND_FREIGHT and weight>_freight_room(core)+0.000001:return _fail(core,"The actual working holds, including their own lockers and stores, cannot fit this sealed cargo.")
		stocks[str(freight["good"])] = _num(stocks.get(str(freight["good"]), 0.0)) - float(freight["qty"])
		p["stocks"] = stocks
	offer["escrow"] = 0
	var ledger: Array = state.get("moneyLog", []) if state.get("moneyLog") is Array else []
	if int(offer.get("materialInvoice",0))>0:Money.move(p,"governmentPurse",p,"cash",int(offer.materialInvoice),"Treasury buys actual relief freight from local suppliers",ledger)
	if not Money.move(p, str(offer["payerKey"]), offer, "escrow", int(offer["reward"]), "Sponsor funds voyage job escrow", ledger):
		if not freight.is_empty():
			p["stocks"][str(freight["good"])] = _num(p["stocks"].get(str(freight["good"]), 0.0)) + float(freight["qty"])
		return _fail(core, "The sponsor cannot fund this job's escrow today.")
	state["moneyLog"] = ledger
	offer["freight"] = freight
	offer["state"] = STATE_ACTIVE
	offer["acceptedDay"] = _num(state.get("day", 0.0))
	offer.baselineDefeats=int(state.get("defeatedOwners",{}).get(offer.get("ownerId",""),0))
	state["voyageJobs"].append(offer)
	if not str(offer.get("sponsorContactId","")).is_empty():Contacts.claim_work_opportunity(state,str(offer.sponsorContactId))
	if str(offer["kind"]) == KIND_SURVEY:
		var site := Exploration.catalog_site(state, str(offer["siteId"]))
		if not site.is_empty() and WorkRegion070.region(site)==Exploration.current_region(state):
			Exploration.discover_near(state, {"x": float(site["x"]), "y": float(site["y"])}, 1.0)
	if core.has_method("log_entry"):
		core.log_entry("Accepted voyage job %s; %d coins moved from the sponsor into escrow." % [str(offer["title"]), int(offer["reward"])])
	return _ok(core, "Voyage job funded and accepted.", {"job": offer.duplicate(true)})


static func _at_port(core, state: Dictionary, port_id: String) -> bool:
	var dock: Dictionary=WorkRegion070.work_port(core)
	return not dock.is_empty() and str(dock.get("id",""))==port_id


static func _bounty_cleared(state: Dictionary, owner_id: String,baseline: int=0) -> bool:
	return int(state.get("defeatedOwners",{}).get(owner_id,0))>baseline


# Hailed sea work uses the SAME finite job escrow and closed-id book. Terms
# are rebuilt from the live client; the displayed fee must still match.
static func accept_escort(core,owner_id: String,quoted_fee: int) -> Dictionary:
	ensure(core)
	_expire_overdue(core,core.state)
	if not core.travel_lock064.is_empty():return _fail(core,core.travel_lock064)
	if core.state.voyageJobs.size()>=MAX_ACTIVE:return _fail(core,"Finish or abandon a carried voyage job first.")
	for carried in core.state.voyageJobs:
		if str(carried.kind)==KIND_ESCORT:return _fail(core,"Finish or withdraw from your existing escort contract first.")
	var offer: Dictionary=core.EscortOps.offer(core,owner_id)
	if offer.is_empty() or int(offer.reward)!=quoted_fee:return _fail(core,"That loaded passage or its quoted fee changed. Hail the convoy again.")
	if _is_closed(core.state,str(offer.id)) or not _find(core.state,str(offer.id)).is_empty():return _fail(core,"This convoy passage has already been contracted.")
	var client: Dictionary=core.fleet_owner(owner_id)
	var job: Dictionary=_sanitize_job(offer)
	if not Money.move(client,"coins",job,"escrow",int(job.reward),"Convoy client funds escort escrow",core.state.moneyLog):return _fail(core,"The actual convoy client can no longer fund this fee.")
	job.state=STATE_ACTIVE;job.acceptedDay=float(core.state.day)
	core.state.voyageJobs.append(job)
	core.log_entry("Accepted %s: %d client coins held in escrow; no advance. Stay within %.0f of its loaded boats, secure any physical interception exit, then report at %s after their actual delivery."%[job.title,job.reward,core.EscortOps.CONTRACT_RADIUS,core.port(str(job.targetPort)).get("name",job.targetPort)])
	return _ok(core,"Convoy client funded your escort contract.",{"job":job.duplicate(true)})


# Pays escrow to the captain exactly once when the kind's real condition is
# met: freight delivered at targetPort (target stocks rise by the sealed
# lot), survey reported at the sponsoring harbor after exploration level 3,
# bounty claimed at the sponsor after the named owner is destroyed/inactive.
static func finish(core, id: String) -> Dictionary:
	var state := _state(core)
	if state.is_empty():
		return _fail(core, "No campaign state.")
	ensure(core)
	tick(core,0.0)
	_expire_overdue(core, state)
	var job := _find(state, id)
	if job.is_empty():
		return _fail(core, "No such voyage job.")
	if str(job["state"]) == STATE_EXPIRED:
		return _fail(core, "That job expired and its escrow was refunded. Abandon it at a harbor to unload any sealed freight.")
	var kind := str(job["kind"])
	if kind==KIND_ESCORT:
		if not job.escort.get("arrived",false) or job.escort.get("battlePending",false):return _fail(core,"Accompany the original loaded carriers to their actual delivery; every interception must end in their physical escape.")
		if not _at_port(core,state,str(job.targetPort)):return _fail(core,"Report at the convoy's delivery harbor to release its client-funded fee.")
	if job.get("failed",false) or job.get("freight",{}).get("lost",false):return _fail(core,"Part of this sealed cargo was lost. Return the remainder and abandon the failed delivery at a harbor.")
	if kind == KIND_FREIGHT and not _at_port(core, state, str(job["targetPort"])):
		return _fail(core, "Deliver the sealed freight at its destination harbor first.")
	if kind==KIND_FUEL:
		var recipient: Dictionary=recipient_status(core,job)
		if not _at_port(core,state,str(job.targetPort)) or not recipient.present:return _fail(core,"Deliver at the actual recipient fleet's harbor while that fleet is present.")
		if not recipient.eligible:return _fail(core,"Current fleet or harbor access rules block this treasury's delivery. Return the sealed lot safely to abandon.")
		if float(job.freight.get("qty",0))<=0 or float(recipient.demand)+0.000001<float(job.freight.get("qty",0)):return _fail(core,"The actual recipient no longer needs or can receive this sealed lot; return it safely or wait for demand.")
	if kind==KIND_CHARTER:
		if not _at_port(core,state,str(job.targetPort)) or job.passengers.is_empty():return _fail(core,"Bring the actual passenger cohort to its destination harbor.")
		if float(job.voyageDistance)+65.0<float(job.routeDistance) or float(job.elapsedDays)<=0:return _fail(core,"The charter needs observed sailing along its actual water route.")
	if kind in [KIND_SURVEY, KIND_BOUNTY] and not _at_port(core, state, str(job["port"])):
		return _fail(core, "Report back at the sponsoring harbor to be paid.")
	if kind == KIND_SURVEY:
		var level: int=int(state.get("exploration",{}).get("sites",{}).get(str(job.siteId),{}).get("level",-1))
		if level < Exploration.LEVEL_SURVEYED:
			return _fail(core, "The site is not fully surveyed yet.")
	if kind==KIND_BOUNTY and not _bounty_cleared(state,str(job.ownerId),int(job.get("baselineDefeats",0))):
		return _fail(core, "The named raider fleet is still at sea.")
	var chapter_before113: Dictionary=job.duplicate(true)
	if core is Object and core.has_method("campaign_delivery_before113"):chapter_before113._delivery113=core.campaign_delivery_before113(job)
	if core is Object and core.has_method("campaign_delivery_before119"):
		chapter_before113.delivery119=core.campaign_delivery_before119(job)
	if not chapter_before113.get("delivery119",{}).is_empty() and not chapter_before113.delivery119.get("ok",false):
		return _fail(core,str(chapter_before113.delivery119.get("message","The original passage is not ready to settle.")))
	var paid := int(job.get("escrow",0))-int(job.get("savingsHousehold",0))-int(job.get("savingsExpert",0))
	if paid != int(job.get("reward", 0)) or paid <= 0:
		return _fail(core, "The job escrow is incomplete.")
	if kind==KIND_CHARTER and not Transport.discharge_charter(core,job,WorkRegion070.work_port(core)):return _fail(core,"The actual destination cannot safely receive this cohort yet.")
	var ledger: Array = state.get("moneyLog", []) if state.get("moneyLog") is Array else []
	if not Money.move(job, "escrow", state, "coins", paid, "Voyage job payment from escrow", ledger):
		return _fail(core, "The job escrow could not be released.")
	state["moneyLog"] = ledger
	if kind==KIND_ESCORT:
		state.lastEscortVoyage={"job":job.duplicate(true),"paidDay":float(state.day),"payment":paid,"deliveryPort":str(job.targetPort)}
	_remember_client(core,job,true)
	var freight := _clean_freight(job.get("freight", {}))
	if kind==KIND_FUEL:
		var owner: Dictionary=_fuel_owner(core,str(job.ownerId))
		var left: float=float(freight.qty)
		var full_tanks: bool=str(job.get("fuelPolicy","three_drum"))=="operating_tanks"
		for b in owner.boats:
			if b.sunk:continue
			if full_tanks and float(b.crew)<float(b.crewMin):continue
			var target: float=maxf(0,float(b.spec.get("fuelCapacity",60)))
			if not full_tanks:target=minf(3.0,target)
			var moved: float=minf(left,maxf(0,target-float(b.fuel)))
			b.fuel=float(b.fuel)+moved;left-=moved
		if left>0:owner.cargo.fuel=float(owner.cargo.get("fuel",0))+left
		job.freight={}
	elif not freight.is_empty():
		var target: Dictionary = core.port(str(job["targetPort"])) if core.has_method("port") else {}
		if not target.is_empty():
			var stocks: Dictionary = target.get("stocks", {}) if target.get("stocks") is Dictionary else {}
			stocks[str(freight["good"])] = _num(stocks.get(str(freight["good"]), 0.0)) + float(freight["qty"])
			target["stocks"] = stocks
		job["freight"] = {}
	_close(state, job)
	if core.has_method("log_entry"):
		core.log_entry("Completed voyage job %s: %d bronze coins released by its sponsor." % [str(job["title"]), paid])
	var result110: Dictionary=_ok(core, "Voyage job paid: %d coins." % paid, {"reward": paid})
	if core is Object and core.has_method("campaign_job_closed110"):core.campaign_job_closed110(chapter_before113 if not chapter_before113.get("_delivery113",{}).is_empty() or not chapter_before113.get("delivery119",{}).is_empty() else job.duplicate(true),result110,false)
	return result110


# Refunds any remaining escrow to the sponsor purse and closes the job.
# Sealed freight is unloaded into the current harbor's stocks; abandoning at
# sea with freight aboard is refused rather than jettisoning sponsor cargo.
static func abandon(core, id: String) -> Dictionary:
	var state := _state(core)
	if state.is_empty():
		return _fail(core, "No campaign state.")
	ensure(core)
	tick(core,0.0)
	_expire_overdue(core, state)
	var job := _find(state, id)
	if job.is_empty():
		return _fail(core, "No such voyage job.")
	var freight := _clean_freight(job.get("freight", {}))
	var dock: Dictionary = WorkRegion070.work_port(core)
	if not freight.is_empty() and dock.is_empty():
		return _fail(core, "Dock at a harbor to unload the sealed freight before abandoning.")
	if str(job.kind)==KIND_CHARTER and not job.passengers.is_empty():
		if dock.is_empty() or not Transport.discharge_charter(core,job,dock):return _fail(core,"Bring passengers to an actual harbor with safe reception room before abandoning.")
	var chapter_before113: Dictionary=job.duplicate(true)
	if core is Object and core.has_method("campaign_delivery_before113"):chapter_before113._delivery113=core.campaign_delivery_before113(job)
	if core is Object and core.has_method("campaign_delivery_before119"):
		chapter_before113.delivery119=core.campaign_delivery_before119(job)
	_refund_escrow(core, state, job, "Abandoned voyage job escrow refunded")
	if not chapter_before113.get("delivery119",{}).is_empty() and int(job.get("escrow",0))>0:
		return _fail(core,"The original fee could not return to its sponsor. The undertaking remains carried.")
	if str(job.kind)==KIND_ESCORT and int(job.escrow)>0:return _fail(core,"The original client is unavailable; its escrow stays held, never discarded.")
	_remember_client(core,job,false)
	if not freight.is_empty() and not bool(freight.get("lost",false)):
		var stocks: Dictionary = dock.get("stocks", {}) if dock.get("stocks") is Dictionary else {}
		stocks[str(freight["good"])] = _num(stocks.get(str(freight["good"]), 0.0)) + float(freight["qty"])
		dock["stocks"] = stocks
		job["freight"] = {}
	_close(state, job)
	var closing_message113: String="Voyage job abandoned. Escrow refunded."
	if not freight.is_empty():closing_message113="Voyage job abandoned. Escrow refunded; lost freight cannot be returned." if bool(freight.get("lost",false)) else "Voyage job abandoned. Escrow refunded and sealed freight unloaded."
	var result110: Dictionary=_ok(core,closing_message113)
	if core is Object and core.has_method("campaign_job_closed110"):core.campaign_job_closed110(chapter_before113 if not chapter_before113.get("_delivery113",{}).is_empty() or not chapter_before113.get("delivery119",{}).is_empty() else job.duplicate(true),result110,true)
	return result110

static func _fuel_owner(c,id: String) -> Dictionary:
	for owner in c.state.get("fleetOwners",[]):
		if str(owner.id)==id and owner.get("active",false) and not owner.get("playerCompany",false) and not id.begins_with("story-"):return owner
	return {}

static func _fuel_allowed(c,sponsor: Dictionary,owner: Dictionary) -> bool:
	if sponsor.is_empty() or owner.is_empty():return false
	var a: String=str(sponsor.get("faction",""));var b: String=str(owner.get("faction",""))
	return (a==b or Factions.relation(c.state,a,b)>Factions.ENEMY_AT) and TradeRules.allowed(c.state.get("tradeLaw",{}).get("bans",[]),a,b,"fuel",float(c.state.day))

static func _fuel_port(c,owner: Dictionary) -> Dictionary:
	return WorkRegion070.fuel_port(c,owner)

static func fuel_demand(owner: Dictionary,full_tanks: bool=false) -> float:
	# Old callers/jobs keep the three-drum emergency target. New059 restocking
	# uses only actual empty tank space and deducts ALL owner cargo fuel first.
	var need: float=0.0
	for b in owner.get("boats",[]):
		if b.sunk or float(b.crew)<float(b.crewMin):continue
		var target: float=maxf(0,float(b.spec.get("fuelCapacity",60)))
		if not full_tanks:target=minf(3.0,target)
		need+=maxf(0,target-float(b.fuel))
	return maxf(0,need-float(owner.get("cargo",{}).get("fuel",0)))

static func _fuel_carrier(c,qty: float,uid: String="") -> String:
	for b in c.active_fleet():
		if not uid.is_empty() and str(b.uid)!=uid:continue
		if str(c.hull(str(b.type)).get("civilianRole","")) in ["transport","tanker"] and _carrier_free(c,b)+0.000001>=qty:return str(b.uid)
	return ""


static func _fuel_promised(c,owner_id: String,excluding: String="") -> float:
	var promised: float=0.0
	for j in c.state.get("voyageJobs",[]):
		if str(j.get("id",""))!=excluding and str(j.get("kind",""))==KIND_FUEL and str(j.get("ownerId",""))==owner_id and str(j.get("state",""))==STATE_ACTIVE:
			promised+=_num(j.get("freight",{}).get("qty",0))
	return promised


# Pure live status. Observation age describes the offered/accepted information,
# never a reservation of an independent fleet's tanks or its location.
static func recipient_status(c,job: Dictionary) -> Dictionary:
	var owner_id: String=str(job.get("ownerId",""))
	var owner: Dictionary=_fuel_owner(c,owner_id)
	var target: String=str(job.get("targetPort",""))
	var current: String=str(_fuel_port(c,owner).get("id",""))
	var observed: float=_num(job.get("quotedDay",0))
	if observed<=0:observed=_num(job.get("acceptedDay",c.state.day))
	var eligible: bool=not owner.is_empty() and _fuel_allowed(c,c.port(str(job.get("port",""))),owner) and _work_access(c,c.port(target),"fuel",c.port(str(job.get("port",""))))
	var present: bool=not owner.is_empty() and not target.is_empty() and current==target
	var demand: float=fuel_demand(owner,str(job.get("fuelPolicy","three_drum"))=="operating_tanks")
	var promised: float=_fuel_promised(c,owner_id,str(job.get("id","")))
	var message: String="Live recipient is present; it may sail or restock before you arrive."
	if not eligible:message="Recipient is inactive, unavailable or blocked by current sponsorship/access rules."
	elif not present:message="Recipient has departed or changed harbor; delivery is unpaid until it is present at the contracted harbor."
	elif demand<float(job.get("freight",{}).get("qty",0)):message="Recipient no longer has enough unfilled demand for the entire sealed lot; wait or return it safely."
	return {"ownerId":owner_id,"present":present,"eligible":eligible,"targetPort":target,"currentPort":current,"demand":demand,"promised":promised,"observedDay":observed,"ageDays":maxf(0,float(c.state.day)-observed),"message":message}


static func _charter_quote(c,origin: String,target: String,count: int,uid: String="") -> Dictionary:
	var passenger_view=WorkRegion070.charter_view(c,c.port(origin),c.port(target))
	if passenger_view==null:return {}
	for b in c.active_fleet():
		if not uid.is_empty() and str(b.uid)!=uid:continue
		if str(c.hull(str(b.type)).get("civilianRole","")) not in ["transport","yacht"] or Transport.spare(c,b)<count:continue
		var q: Dictionary=Transport.charter_quote(passenger_view,origin,target,count,str(b.uid))
		if not q.is_empty() and _carrier_free(c,b)+0.000001>=float(q.charterFood.get("food",0)):return q
	return {}


static func _civilian_offers(c,p: Dictionary,day: int,taken: Dictionary) -> Array:
	var out: Array=[]
	var fuel_routes: int=0
	var fuel_room: float=0.0
	for b in c.active_fleet():
		if str(c.hull(str(b.type)).get("civilianRole","")) in ["transport","tanker"]:fuel_room=maxf(fuel_room,_carrier_free(c,b))
	fuel_room=minf(fuel_room,_effective_free(c,c.state))
	var export_fuel: float=Reserves.exportable(p,"fuel")
	for owner in c.state.get("fleetOwners",[]):
		if fuel_routes>=WORK_ROUTES:break
		var target: Dictionary=_fuel_port(c,owner)
		if _fuel_owner(c,str(owner.id)).is_empty() or not _fuel_allowed(c,p,owner) or target.is_empty() or str(target.id)==str(p.id) or not _work_access(c,target,"fuel",p):continue
		var demand: float=maxf(0,fuel_demand(owner,true)-_fuel_promised(c,str(owner.id)))
		var limit: int=floori(minf(demand,minf(export_fuel,fuel_room)))
		if limit<1:continue
		var route: Dictionary=WorkRegion070.route(c,target,p)
		if not route.ok:continue
		var days: float=float(route.referenceDays)
		limit=mini(limit,_catalog_load_room(c,days,KIND_FUEL))
		var small: int=mini(8,limit);var added: bool=false
		for tier in WORK_LOADS:
			var load: Dictionary=_funded_load(c,p,days,KIND_FUEL,small if tier=="small" else limit,"fuel")
			if load.is_empty():continue
			var qty: int=int(load.qty)
			if tier=="larger" and qty<=small:continue
			var q: Dictionary={"title":"%s fuel restock: %d drums for %s at %s"%[str(tier).capitalize(),qty,str(owner.name),str(target.name)],"description":"Treasury buys real fuel for unfilled operating tanks, after the recipient's existing cargo fuel and promises. The independent fleet may sail or restock; payment only on actual receipt.","kind":KIND_FUEL,"port":str(p.id),"targetPort":str(target.id),"ownerId":str(owner.id),"payerKey":"governmentPurse","reward":int(load.reward),"materialInvoice":int(load.invoice),"freight":{"good":"fuel","qty":float(qty)},"deadlineDay":float(day)+ceilf(maxf(days,float(load.days))*2+6),"state":STATE_OFFERED,"fuelPolicy":"operating_tanks","loadTier":tier,"quotedDay":float(c.state.day),"demandNeed":demand,"demandPurpose":"Existing living, crewed boats' unfilled real tanks; all already-carried recipient fuel deducted. No tank reservation; recipient can depart or buy fuel.","feeBasis":str(load.feeBasis)}
			q.regionId=WorkRegion070.region(p);q.targetRegionId=WorkRegion070.region(target)
			q.id=_work_id(p,day,KIND_FUEL,str(target.id),str(owner.id),qty,q)
			if taken.has(q.id) or _is_closed(c.state,str(q.id)):continue
			out.append(q);added=true
		if added:fuel_routes+=1
	var charter_routes: int=0
	for destination in _work_destinations(c,p):
		if charter_routes>=WORK_ROUTES:break
		# Existing passenger time/distance accounting is local-coordinate based.
		# Its SAME-region boarding/food/savings rules stay authoritative.
		if WorkRegion070.region(destination)!=WorkRegion070.region(p):continue
		var largest: int=0
		for b in c.active_fleet():
			if str(c.hull(str(b.type)).get("civilianRole","")) in ["transport","yacht"]:largest=maxi(largest,Transport.spare(c,b))
		var limit: int=mini(32,mini(largest,mini(int(p.get("availableWorkers",0)),Transport.charter_room(c,destination))))
		if limit<1:continue
		var route: Dictionary=WorkRegion070.route(c,destination,p)
		if not route.ok:continue
		var days: float=float(route.referenceDays)
		var small: int=mini(4,limit);var added: bool=false
		for tier in WORK_LOADS:
			var count: int=small if tier=="small" else limit
			if tier=="larger" and count<=small:continue
			var q: Dictionary={};var fee: Dictionary={}
			# Only the small option falls back through at most four real people.
			for n in range(count,(0 if tier=="small" else count-1),-1):
				q=_charter_quote(c,str(p.id),str(destination.id),n)
				if q.is_empty():continue
				fee=_work_fee(c,p,days,KIND_CHARTER,n,0)
				if not fee.is_empty() and int(p.governmentPurse)>=int(fee.reward)+int(q.materialInvoice):break
				q={}
			if q.is_empty() or fee.is_empty():continue
			q.merge({"title":"%s charter: %d people to %s"%[str(tier).capitalize(),int(q.passengers.n),str(destination.name)],"description":"Existing civilians, their own savings and purchased provisions travel in one transport or yacht. Savings are custody, never your earnings. Actual destination housing and people limit this passage.","kind":KIND_CHARTER,"port":str(p.id),"targetPort":str(destination.id),"payerKey":"governmentPurse","reward":int(fee.reward),"deadlineDay":float(day)+int(q.routeDays)*2+6,"state":STATE_OFFERED,"freight":{},"demandNeed":float(limit),"demandPurpose":"Existing available workers seeking passage into actual uncommitted destination housing, with real berths and bought food.","loadTier":tier,"quotedDay":float(c.state.day),"feeBasis":str(fee.feeBasis)})
			q.regionId=WorkRegion070.region(p);q.targetRegionId=WorkRegion070.region(destination)
			q.id=_work_id(p,day,KIND_CHARTER,str(destination.id),"people",int(q.passengers.n),q)
			if taken.has(q.id) or _is_closed(c.state,str(q.id)):continue
			out.append(q);added=true
		if added:charter_routes+=1
	return out

static func tick(c,dt_days: float) -> void:
	if not is_finite(dt_days) or dt_days<0 or not c.state.has("voyageJobs"):return
	ensure(c)
	for j in c.state.voyageJobs:
		if j.kind==KIND_ESCORT and j.state==STATE_ACTIVE:c.EscortOps.advance_contract(c,j)
		elif j.kind==KIND_CHARTER:Transport.tick_charter(c,j,dt_days)
		elif j.kind==KIND_FUEL:
			var b: Dictionary=c.find_boat(str(j.carrierUid))
			if b.is_empty() or b.sunk:
				j.lostFuel=float(j.lostFuel)+float(j.freight.get("qty",0));j.freight={};j.failed=true
			elif not c.active_fleet().has(b):j.failed=true
	_expire_overdue(c,c.state)

# Raw preflight, reusable from the canonical save-kind admission gate. The
# nested record survives ensure()/JSON without borrowing live dictionaries.
static func escort_error(s: Dictionary,j: Dictionary,world: Dictionary) -> String:
	if j.get("payerKey")!="coins" or not j.get("freight") is Dictionary or not j.freight.is_empty():return "Escort escrow must be client coins, never sealed player freight."
	if not _is_num(j.get("reward")) or float(j.reward)<=0 or floorf(float(j.reward))!=float(j.reward) or not _is_num(j.get("escrow")) or floorf(float(j.escrow))!=float(j.escrow) or float(j.escrow)<0 or float(j.escrow)>float(j.reward):return "Invalid escort fee/escrow."
	if j.get("state")==STATE_ACTIVE and j.escrow!=j.reward:return "Unfunded active escort."
	var client: Dictionary={}
	for owner in s.get("fleetOwners",[]):
		if owner.get("id")==j.get("ownerId"):client=owner;break
	if client.is_empty() or client.get("kind")!="trader" or client.get("playerCompany",false) or client.get("homePort")!=j.get("port"):return "Escort must retain its original independent trader client."
	var route=j.get("escort")
	if not route is Dictionary:return "Missing escort passage record."
	for key in ["voyageSeq","tradeQty","baselineDelivered","routeDistance","accompaniedDistance","playerDistance","lastDay"]:
		if not _is_num(route.get(key)) or float(route[key])<0 or float(route[key])>1000000000.0:return "Invalid escort route accounting."
	if floorf(float(route.voyageSeq))!=float(route.voyageSeq) or str(j.get("id",""))!="escort:%s:%d"%[str(j.get("ownerId","")),int(route.voyageSeq)]:return "Escort id disagrees with its exact client voyage."
	if not route.get("fromPort") is String or not route.get("tradeGood") is String or not Goods.ITEMS.has(route.tradeGood) or route.tradeQty<=0 or route.routeDistance<160 or float(route.lastDay)>float(s.day):return "Invalid escort cargo/route."
	for key in ["arrived","battlePending","exitSecured"]:
		if not route.get(key) is bool:return "Invalid escort physical endstate."
	if not route.get("failure") is String:return "Invalid escort failure record."
	var count=route.get("interceptions",0)
	if not _is_num(count) or float(count)<0 or floorf(float(count))!=float(count):return "Invalid escort interception count."
	if not route.get("carrierUids") is Array or route.carrierUids.is_empty() or route.carrierUids.size()>64 or not route.get("carrierCargo") is Dictionary:return "Invalid original escort carriers."
	var seen: Dictionary={}
	for uid in route.carrierUids:
		if not uid is String or seen.has(uid) or not client.get("boats",[]).any(func(b):return b.get("uid")==uid):return "Escort carrier identity is missing or duplicated."
		seen[uid]=true
		if not route.carrierCargo.get(uid) is Dictionary or route.carrierCargo[uid].is_empty():return "Escort carrier lacks its original cargo."
	var qty: float=0.0
	for uid in route.carrierCargo:
		var lot=route.carrierCargo[uid]
		if not lot is Dictionary or (not lot.is_empty() and not seen.has(uid)):return "Invalid escort carrier cargo ledger."
		for good in lot:
			if not Goods.ITEMS.has(good) or not _is_num(lot[good]) or float(lot[good])<=0:return "Invalid original escort goods."
		qty+=float(lot.get(str(route.tradeGood),0))
	if qty+0.000001<float(route.tradeQty):return "Original carriers do not contain the promised trade load."
	for key in ["lastPosition","lastConvoyPosition"]:
		if not route.get(key) is Dictionary:return "Missing escort position."
		for axis in ["x","y"]:
			if not _is_num(route[key].get(axis)) or float(route[key][axis])<0 or float(route[key][axis])>float(world.WORLD.width if axis=="x" else world.WORLD.height):return "Invalid escort route position."
	if route.arrived:
		if route.battlePending or (int(count)>0 and not route.exitSecured) or not _is_num(route.get("arrivedDay")) or float(route.arrivedDay)>float(s.day) or float(route.arrivedDay)<float(j.acceptedDay) or not _is_num(route.get("deliveredQty")) or float(route.deliveredQty)+0.000001<float(route.tradeQty):return "Unearned escort arrival."
		if float(route.accompaniedDistance)+40.0<float(route.routeDistance)*0.8 or float(route.playerDistance)+40.0<float(route.routeDistance)*0.8:return "Escort arrival lacks actual accompanying movement."
	return ""


static func validate(s: Dictionary,world: Dictionary) -> String:
	var hulls: Dictionary={}
	for h in world.HULLS:hulls[str(h.id)]=h
	for j in s.get("voyageJobs",[]):
		if j is Dictionary and j.get("kind","")==KIND_ESCORT:
			var escort_problem: String=escort_error(s,j,world)
			if not escort_problem.is_empty():return escort_problem
		if not j is Dictionary or j.get("kind","") not in [KIND_FUEL,KIND_CHARTER]:continue
		if not j.get("carrierUid") is String or str(j.carrierUid).is_empty() or not j.get("failed") is bool:return "Invalid civilian job carrier/status."
		var boat: Dictionary={}
		for b in s.fleet:
			if b.uid==j.carrierUid:boat=b;break
		if j.state==STATE_ACTIVE and (boat.is_empty() or not preload("res://scripts/hold_manifest.gd").carriers(s).has(boat)):return "Active civilian job has no working carrier."
		if not boat.is_empty():
			var role: String=str(hulls.get(str(boat.type),{}).get("civilianRole",""))
			if role not in (["transport","tanker"] if j.kind==KIND_FUEL else ["transport","yacht"]):return "Ineligible civilian job hull."
		if not _is_num(j.get("reward")) or floorf(float(j.reward))!=float(j.reward) or float(j.reward)<=0:return "Invalid civilian job fee."
		if j.kind==KIND_FUEL:
			if not s.fleetOwners.any(func(o):return str(o.id)==str(j.ownerId)):return "Unknown fuel recipient."
			var lot_limit: float=float(hulls.get(str(boat.get("type","")),{}).get("cargo",0)) if str(j.get("fuelPolicy","three_drum"))=="operating_tanks" else 12.0
			if not j.freight.is_empty() and (j.freight.get("good","")!="fuel" or not _is_num(j.freight.get("qty")) or float(j.freight.qty)<0 or float(j.freight.qty)>lot_limit or floorf(float(j.freight.qty))!=float(j.freight.qty)):return "Invalid sealed fuel lot."
			if j.state==STATE_ACTIVE and (j.freight.is_empty() or float(j.freight.qty)<=0 or int(j.escrow)!=int(j.reward)):return "Unfunded or missing active fuel shipment."
			continue
		if not j.get("passengers") is Dictionary or not j.get("charterFood") is Dictionary:return "Invalid charter cohort/provisions."
		for key in ["savingsHousehold","savingsExpert","routeDays","routeDistance","lastTickDay","elapsedDays","voyageDistance","foodConsumed"]:
			if not _is_num(j.get(key)) or float(j[key])<0 or float(j[key])>1e12:return "Invalid charter accounting."
		for key in ["savingsHousehold","savingsExpert","routeDays"]:
			if floorf(float(j[key]))!=float(j[key]):return "Nonintegral charter money/date."
		if j.routeDays<1 or j.routeDays>30 or j.routeDistance<=0 or float(j.lastTickDay)>float(s.day) or float(j.lastTickDay)<float(j.acceptedDay) or float(j.elapsedDays)>float(s.day)-float(j.acceptedDay)+0.000001:return "Unearned charter time/route."
		var savings: int=int(j.savingsHousehold)+int(j.savingsExpert)
		if int(j.escrow)!=savings+(int(j.reward) if j.state==STATE_ACTIVE else 0):return "Charter sponsor fee and passenger savings disagree with escrow."
		var cohort: Dictionary=j.passengers
		if cohort.is_empty():
			if j.state!=STATE_EXPIRED or not j.failed or savings!=0 or not j.charterFood.is_empty():return "Missing active charter passengers."
			continue
		var module=preload("res://scripts/regional_crises.gd").new()
		if not module._whole(cohort.get("n"),1,32) or not module._subsets(cohort.n,cohort.get("specialists"),cohort.get("recruits"),cohort.get("qualified")):return "Invalid actual charter people/subsets."
		if not module._shape(cohort,"n specialists recruits qualified") or not module._shape(cohort.qualified,"sailor gunner mechanic boarder"):return "Unknown charter cohort fields."
		if boat.is_empty() or boat.sunk or not str(boat.get("storedPort","")).is_empty():return "Charter passengers lack an actual living carrier."
		if Transport.assigned(s,str(boat.uid))+int(s.get("captiveBerths",{}).get(str(boat.uid),0))>maxi(0,int(boat.crewMax)-int(boat.crew)):return "Charter and existing passengers exceed spare berths."
		if j.charterFood.size()!=1 or not _is_num(j.charterFood.get("food")) or float(j.charterFood.food)<0 or absf(float(j.charterFood.food)+float(j.foodConsumed)-Transport.quantity(int(cohort.n),int(j.routeDays)+2))>0.00001:return "Charter food was created or lost outside its actual consumption."
		if not j.get("lastPosition") is Dictionary:return "Missing observed charter position."
		for axis in ["x","y"]:
			if not _is_num(j.lastPosition.get(axis)) or float(j.lastPosition[axis])<0 or float(j.lastPosition[axis])>float(world.WORLD.width if axis=="x" else world.WORLD.height):return "Invalid charter route position."
	return ""
