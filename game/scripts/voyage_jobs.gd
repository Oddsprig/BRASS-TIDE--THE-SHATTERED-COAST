extends RefCounted
const Routes=preload("res://scripts/route_cache.gd")
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

const MAX_ACTIVE := 6
const MAX_DONE := 128
const KIND_FREIGHT := "freight"
const KIND_SURVEY := "survey"
const KIND_BOUNTY := "bounty"
const KIND_FUEL := "fuel_delivery"
const KIND_CHARTER := "passenger_charter"
const STATE_OFFERED := "offered"
const STATE_ACTIVE := "active"
const STATE_EXPIRED := "expired"
const FREIGHT_GOODS := ["preserved_fish","fine_timber","lacquer","medicinal_plants","supplies", "food", "timber", "fuel"]
# Exploration work a full sighted->surveyed job may need (exploration.gd
# ACTIONS): chart 2 crew x 1.0 day + survey 4 crew x 2.5 days = 12 crew-days.
const SURVEY_CREW_DAYS := 12.0


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
	if not payer in ["cash", "governmentPurse"]:
		payer = "cash"
	return {
		"id": str(raw["id"]), "title": str(raw.get("title", "Voyage job")),
		"description": str(raw.get("description", "")), "port": str(raw.get("port", "")),
		"targetPort": str(raw.get("targetPort", "")), "kind": str(raw.get("kind", KIND_FREIGHT)),
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
	}


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
static func _route_reward(core,days: float,good: String="",survey: bool=false) -> int:
	var p: Dictionary=core.current_port()
	var crew: int=6 if survey else 5
	var work_days: float=maxf(1,days*2.0+(3.5 if survey else 0.25))
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
	var sponsor: Dictionary = core.port(str(job["port"])) if core.has_method("port") else {}
	if sponsor.is_empty():
		return  # escrow stays on the job record; never vanish it silently
	var ledger: Array = state.get("moneyLog", []) if state.get("moneyLog") is Array else []
	if Money.move(job, "escrow", sponsor, str(job["payerKey"]), amount, reason, ledger):
		state["moneyLog"] = ledger


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
	if ports.size() < 2:
		return {}
	var index := ports.find(from)
	if index < 0:
		index = 0
	var day := int(_num(state.get("day", 1.0)))
	return ports[(index + 1 + salt + (day % 3)) % ports.size()]


# Deterministic same-day offers at the harbor the captain is docked at. Ids
# embed port + day (+ site/owner), so reopening the board never rerolls, and
# accepted/closed ids never reappear. Offers are only listed while the
# sponsor purse can fund the full escrow and, for freight, the source port
# physically holds the sealed lot.
static func available(core) -> Array:
	var state := _state(core)
	if state.is_empty() or not core.has_method("current_port"):
		return []
	ensure(core)
	var offers: Array = []
	var p: Dictionary = core.current_port()
	if p.is_empty():
		return offers
	if core.has_method("faction") and not preload("res://scripts/politics.gd").access(core,p).contracts:return offers
	var day := int(_num(state.get("day", 1.0)))
	var taken := {}
	for job in state["voyageJobs"]:
		taken[str(job["id"])] = true
	# Freight: one sealed lot to a deterministic neighboring harbor.
	var freight_dest := _destination(state, p, 1)
	var freight_id := "vfreight-%s-%d" % [str(p["id"]), day]
	if not freight_dest.is_empty() and not taken.has(freight_id) and not _is_closed(state, freight_id):
		for good in FREIGHT_GOODS:
			var qty: int=1 if good in ["preserved_fish","fine_timber","lacquer","medicinal_plants"] else 6+(day%5)
			var stocks: Dictionary = p.get("stocks", {}) if p.get("stocks") is Dictionary else {}
			if _num(stocks.get(good, 0.0)) < float(qty):
				continue
			var days := _travel_days(core, p, freight_dest)
			var reward := _route_reward(core, days, good)
			var invoice: int=qty*Economy.price(p,good)
			if int(p.get("governmentPurse",0))<reward+invoice:
				continue
			offers.append({
				"id": freight_id, "title": "Sealed %s to %s" % [str(Goods.ITEMS[good]["name"]), str(freight_dest["name"])],
				"description":"The harbor treasury buys real relief cargo from its local business and escrows your passage fee. The quote funds a small five-sailor voyage; larger fleets cost more to run.",
				"port": str(p["id"]), "targetPort": str(freight_dest["id"]), "kind": KIND_FREIGHT,
				"reward":reward,"escrow":0,"payerKey":"governmentPurse","materialInvoice":invoice,"failed":false,
				"deadlineDay": float(day) + ceilf(days * 2.0 + 6.0), "acceptedDay": 0.0,
				"freight": {"good": good, "qty": float(qty)}, "state": STATE_OFFERED,
				"siteId": "", "ownerId": ""})
			break
	# Survey: one deterministic not-yet-surveyed catalog site, if any remains.
	var unsurveyed: Array = []
	for site in Exploration.sites(state):
		if int(site.get("level", 0)) < Exploration.LEVEL_SURVEYED:
			unsurveyed.append(site)
	if not unsurveyed.is_empty():
		var site: Dictionary = unsurveyed[(day + int(state["ports"].find(p))) % unsurveyed.size()]
		var survey_id := "vsurvey-%s-%d-%s" % [str(p["id"]), day, str(site["id"])]
		if not taken.has(survey_id) and not _is_closed(state, survey_id):
			var days := _travel_days(core, p, {"x": float(site["x"]), "y": float(site["y"])})
			var reward: int=_route_reward(core,days,"",true)
			if int(p.get("governmentPurse", 0)) >= reward:
				offers.append({
					"id": survey_id, "title": "Survey %s" % str(site["name"]),
					"description": "The harbor government escrows a survey fee. Chart and fully survey the site, then report back here. Clue: %s" % str(site.get("clue", "")),
					"port": str(p["id"]), "targetPort": str(p["id"]), "kind": KIND_SURVEY,
					"reward": reward, "escrow": 0, "payerKey": "governmentPurse",
					"deadlineDay": float(day) + ceilf(days * 2.0 + 14.0), "acceptedDay": 0.0,
					"freight": {}, "state": STATE_OFFERED,
					"siteId": str(site["id"]), "ownerId": ""})
	# Bounty: the first actually active patrol raider owner, if one is at sea.
	var bounty_id := "vbounty-%s-%d" % [str(p["id"]), day]
	if not taken.has(bounty_id) and not _is_closed(state, bounty_id):
		for owner in state.get("fleetOwners", []) if state.get("fleetOwners") is Array else []:
			if not (owner is Dictionary) or str(owner.get("kind", "")) != "raider" or not str(owner.get("id", "")).begins_with("patrol-") or not bool(owner.get("active", false)):
				continue
			if str(owner.get("faction",""))==str(p.get("faction","")):continue
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
	_select_contact_work(core,p,offers)
	return offers


# Select from the actual board rather than issuing a second contract/reward.
# Only one original contact lives at each authored harbor. The original offer
# id remains authoritative for duplicate suppression and all transactions.
static func _select_contact_work(core, p: Dictionary, offers: Array) -> void:
	if core.state.voyageJobs.size()>=MAX_ACTIVE or core.active_fleet().is_empty() or not core.state.path.is_empty():return
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
	var p: Dictionary = core.current_port() if core.has_method("current_port") else {}
	if p.is_empty() or str(p.get("id", "")) != str(offer["port"]):
		return _fail(core, "Accept this job at its sponsoring harbor.")
	if int(p.get(str(offer["payerKey"]),0))<int(offer.reward)+int(offer.get("materialInvoice",0)):
		return _fail(core, "The sponsor cannot fund this job's escrow today.")
	if str(offer.kind)==KIND_CHARTER:
		if not Transport.board_charter(core,offer,boat_uid):return _fail(core,"Charter needs real available people, funded provisions and spare berths on one transport or yacht.")
		offer.state=STATE_ACTIVE;offer.acceptedDay=float(state.day)
		state.voyageJobs.append(offer)
		if not str(offer.get("sponsorContactId","")).is_empty():Contacts.claim_work_opportunity(state,str(offer.sponsorContactId))
		core.log_entry("Funded charter embarked %d actual people aboard %s."%[offer.passengers.n,offer.carrierUid])
		return _ok(core,"Charter funded, provisioned and boarded.",{"job":offer.duplicate(true)})
	var freight := _clean_freight(offer.get("freight", {}))
	if str(offer.kind)==KIND_FUEL:
		if not _fuel_allowed(core,p,_fuel_owner(core,str(offer.ownerId))):return _fail(core,"This treasury cannot sponsor fuel for an enemy or embargoed fleet.")
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
		if not site.is_empty():
			Exploration.discover_near(state, {"x": float(site["x"]), "y": float(site["y"])}, 1.0)
	if core.has_method("log_entry"):
		core.log_entry("Accepted voyage job %s; %d coins moved from the sponsor into escrow." % [str(offer["title"]), int(offer["reward"])])
	return _ok(core, "Voyage job funded and accepted.", {"job": offer.duplicate(true)})


static func _at_port(core, state: Dictionary, port_id: String) -> bool:
	if core.has_method("current_port"):
		var dock: Dictionary = core.current_port()
		return not dock.is_empty() and str(dock.get("id", "")) == port_id
	return false


static func _bounty_cleared(state: Dictionary, owner_id: String,baseline: int=0) -> bool:
	return int(state.get("defeatedOwners",{}).get(owner_id,0))>baseline


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
	if job.get("failed",false) or job.get("freight",{}).get("lost",false):return _fail(core,"Part of this sealed cargo was lost. Return the remainder and abandon the failed delivery at a harbor.")
	if kind == KIND_FREIGHT and not _at_port(core, state, str(job["targetPort"])):
		return _fail(core, "Deliver the sealed freight at its destination harbor first.")
	if kind==KIND_FUEL:
		var owner: Dictionary=_fuel_owner(core,str(job.ownerId))
		if not _at_port(core,state,str(job.targetPort)) or owner.is_empty() or str(owner.get("atPort",""))!=str(job.targetPort):return _fail(core,"Deliver at the actual recipient fleet's harbor while that fleet is present.")
		if not _fuel_allowed(core,core.port(str(job.port)),owner):return _fail(core,"War or an existing fuel embargo blocks this treasury's delivery. Return the sealed lot safely to abandon.")
		if float(job.freight.get("qty",0))<=0 or fuel_demand(owner)+0.000001<float(job.freight.get("qty",0)):return _fail(core,"The actual recipient no longer needs or can receive this sealed lot; return it safely or wait for demand.")
	if kind==KIND_CHARTER:
		if not _at_port(core,state,str(job.targetPort)) or job.passengers.is_empty():return _fail(core,"Bring the actual passenger cohort to its destination harbor.")
		if float(job.voyageDistance)+65.0<float(job.routeDistance) or float(job.elapsedDays)<=0:return _fail(core,"The charter needs observed sailing along its actual water route.")
	if kind in [KIND_SURVEY, KIND_BOUNTY] and not _at_port(core, state, str(job["port"])):
		return _fail(core, "Report back at the sponsoring harbor to be paid.")
	if kind == KIND_SURVEY:
		var level := -1
		for site in Exploration.sites(state):
			if str(site.get("id", "")) == str(job["siteId"]):
				level = int(site.get("level", -1))
		if level < Exploration.LEVEL_SURVEYED:
			return _fail(core, "The site is not fully surveyed yet.")
	if kind==KIND_BOUNTY and not _bounty_cleared(state,str(job.ownerId),int(job.get("baselineDefeats",0))):
		return _fail(core, "The named raider fleet is still at sea.")
	var paid := int(job.get("escrow",0))-int(job.get("savingsHousehold",0))-int(job.get("savingsExpert",0))
	if paid != int(job.get("reward", 0)) or paid <= 0:
		return _fail(core, "The job escrow is incomplete.")
	if kind==KIND_CHARTER and not Transport.discharge_charter(core,job,core.current_port()):return _fail(core,"The actual destination cannot safely receive this cohort yet.")
	var ledger: Array = state.get("moneyLog", []) if state.get("moneyLog") is Array else []
	if not Money.move(job, "escrow", state, "coins", paid, "Voyage job payment from escrow", ledger):
		return _fail(core, "The job escrow could not be released.")
	state["moneyLog"] = ledger
	var freight := _clean_freight(job.get("freight", {}))
	if kind==KIND_FUEL:
		var owner: Dictionary=_fuel_owner(core,str(job.ownerId))
		var left: float=float(freight.qty)
		for b in owner.boats:
			if b.sunk:continue
			var moved: float=minf(left,maxf(0,minf(3.0,float(b.spec.get("fuelCapacity",60)))-float(b.fuel)))
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
	return _ok(core, "Voyage job paid: %d coins." % paid, {"reward": paid})


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
	var dock: Dictionary = core.current_port() if core.has_method("current_port") else {}
	if not freight.is_empty() and dock.is_empty():
		return _fail(core, "Dock at a harbor to unload the sealed freight before abandoning.")
	if str(job.kind)==KIND_CHARTER and not job.passengers.is_empty():
		if dock.is_empty() or not Transport.discharge_charter(core,job,dock):return _fail(core,"Bring passengers to an actual harbor with safe reception room before abandoning.")
	_refund_escrow(core, state, job, "Abandoned voyage job escrow refunded")
	if not freight.is_empty():
		var stocks: Dictionary = dock.get("stocks", {}) if dock.get("stocks") is Dictionary else {}
		stocks[str(freight["good"])] = _num(stocks.get(str(freight["good"]), 0.0)) + float(freight["qty"])
		dock["stocks"] = stocks
		job["freight"] = {}
	_close(state, job)
	return _ok(core, "Voyage job abandoned. Escrow refunded and sealed freight unloaded." if not freight.is_empty() else "Voyage job abandoned. Escrow refunded.")

static func _fuel_owner(c,id: String) -> Dictionary:
	for owner in c.state.get("fleetOwners",[]):
		if str(owner.id)==id and owner.get("active",false) and not owner.get("playerCompany",false) and not id.begins_with("story-"):return owner
	return {}

static func _fuel_allowed(c,sponsor: Dictionary,owner: Dictionary) -> bool:
	if sponsor.is_empty() or owner.is_empty():return false
	var a: String=str(sponsor.get("faction",""));var b: String=str(owner.get("faction",""))
	return (a==b or Factions.relation(c.state,a,b)>Factions.ENEMY_AT) and TradeRules.allowed(c.state.get("tradeLaw",{}).get("bans",[]),a,b,"fuel",float(c.state.day))

static func fuel_demand(owner: Dictionary) -> float:
	# Same three-drum operating target used by Fleets.dock, bounded by real tanks.
	var need: float=0.0
	for b in owner.get("boats",[]):
		if not b.sunk and float(b.crew)>=float(b.crewMin):need+=maxf(0,minf(3.0,float(b.spec.get("fuelCapacity",60)))-float(b.fuel))
	return maxf(0,need-float(owner.get("cargo",{}).get("fuel",0)))

static func _fuel_carrier(c,qty: float,uid: String="") -> String:
	for b in c.active_fleet():
		if not uid.is_empty() and str(b.uid)!=uid:continue
		if str(c.hull(str(b.type)).get("civilianRole","")) in ["transport","tanker"] and Transport.available_hold(c,b)+0.000001>=qty:return str(b.uid)
	return ""

static func _civilian_offers(c,p: Dictionary,day: int,taken: Dictionary) -> Array:
	var out: Array=[]
	for owner in c.state.get("fleetOwners",[]):
		var target: Dictionary=c.port(str(owner.get("atPort","")))
		if _fuel_owner(c,str(owner.id)).is_empty() or not _fuel_allowed(c,p,owner) or target.is_empty() or str(target.id)==str(p.id):continue
		var promised: float=0.0
		for j in c.state.voyageJobs:
			if j.kind==KIND_FUEL and j.ownerId==owner.id and j.state==STATE_ACTIVE:promised+=float(j.freight.get("qty",0))
		var qty: int=floori(minf(12,minf(fuel_demand(owner)-promised,Reserves.exportable(p,"fuel"))))
		var id: String="vfuel-%s-%d-%s"%[p.id,day,owner.id]
		if qty<=0 or taken.has(id) or _is_closed(c.state,id) or _fuel_carrier(c,qty).is_empty() or qty>c.capacity()-c.cargo_weight():continue
		var path: Array=Routes.path(c,c.state.position,target)
		if path.size()<2:continue
		var days: float=_travel_days(c,p,target)
		var reward: int=_route_reward(c,days,"fuel")
		var invoice: int=qty*Economy.price(p,"fuel")
		if int(p.governmentPurse)<reward+invoice:continue
		out.append({"id":id,"title":"Fuel for %s at %s"%[owner.name,target.name],"description":"Treasury buys real fuel; sealed drums must reach this actual needy fleet. Payment only on receipt.","kind":KIND_FUEL,"port":p.id,"targetPort":target.id,"ownerId":owner.id,"payerKey":"governmentPurse","reward":reward,"materialInvoice":invoice,"freight":{"good":"fuel","qty":float(qty)},"deadlineDay":float(day)+ceilf(days*2+6),"state":STATE_OFFERED})
	var destination: Dictionary=_destination(c.state,p,0)
	var id: String="vcharter-%s-%d"%[p.id,day]
	if not destination.is_empty() and destination.id!=p.id and not taken.has(id) and not _is_closed(c.state,id):
		for n in range(4,0,-1):
			var q: Dictionary=Transport.charter_quote(c,str(p.id),str(destination.id),n)
			if q.is_empty():continue
			var reward: int=_route_reward(c,float(q.routeDays))+n*Goods.SAILOR_WAGE*int(q.routeDays)
			if int(p.governmentPurse)<reward+int(q.materialInvoice):continue
			q.merge({"id":id,"title":"Passenger charter to %s"%destination.name,"description":"Existing civilians, savings and bought provisions travel in one transport or yacht. Fee remains escrowed until physical arrival.","kind":KIND_CHARTER,"port":p.id,"targetPort":destination.id,"payerKey":"governmentPurse","reward":reward,"deadlineDay":float(day)+int(q.routeDays)*2+6,"state":STATE_OFFERED,"freight":{}})
			out.append(q);break
	return out

static func tick(c,dt_days: float) -> void:
	if not is_finite(dt_days) or dt_days<0 or not c.state.has("voyageJobs"):return
	ensure(c)
	for j in c.state.voyageJobs:
		if j.kind==KIND_CHARTER:Transport.tick_charter(c,j,dt_days)
		elif j.kind==KIND_FUEL:
			var b: Dictionary=c.find_boat(str(j.carrierUid))
			if b.is_empty() or b.sunk:
				j.lostFuel=float(j.lostFuel)+float(j.freight.get("qty",0));j.freight={};j.failed=true
			elif not c.active_fleet().has(b):j.failed=true
	_expire_overdue(c,c.state)

static func validate(s: Dictionary,world: Dictionary) -> String:
	var hulls: Dictionary={}
	for h in world.HULLS:hulls[str(h.id)]=h
	for j in s.get("voyageJobs",[]):
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
			if not j.freight.is_empty() and (j.freight.get("good","")!="fuel" or not _is_num(j.freight.get("qty")) or float(j.freight.qty)<0 or float(j.freight.qty)>12 or floorf(float(j.freight.qty))!=float(j.freight.qty)):return "Invalid sealed fuel lot."
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
