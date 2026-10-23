extends RefCounted
const PassengerManifest=preload("res://scripts/passenger_manifest.gd")
## v0.015 fleet identity: interior support conversions, paid specialists and
## bounded boat service history. Conversions are interior fittings only: they
## never touch weapon mounts, loadout, hardpoints or deck decoration, and
## effective() always rebuilds from the canonical fitted spec root supplies,
## so repeated calls cannot stack. Specialists are real recruited sailors in
## real crew berths; root must add each specialist.coins purse to Money.total
## and validate state.specialists (noted for integration, like voyage jobs).

const Goods = preload("res://scripts/goods.gd")
const Money = preload("res://scripts/money.gd")
const Economy = preload("res://scripts/economy.gd")

const MAX_HISTORY := 12
const NAMES := ["Ana Breg", "Piet Lorn", "Salla Miro", "Jonas Teek", "Ruth Calder", "Emre Vail", "Nils Ostro", "Faye Marlin"]

# Effects multiply/add on the canonical fitted spec. Every conversion buys
# its advantage with hold space, speed or handling, stated in "trade".
const CONVERSIONS := {
	"cargo_rig": {"name": "Cargo Rig", "materials": {"timber": 3.0, "logs": 2.0, "iron": 1.0},
		"shipwrightDays": 2.0, "mechanicDays": 0.0, "engineerDays": 0.0,
		"cargoMult": 1.35, "speedMult": 0.94, "turnMult": 0.95,
		"trade": "+35% hold; -6% speed, -5% turn from deckhouses and hoists."},
	"survey_rig": {"name": "Survey Rig", "materials": {"timber": 2.0, "copper": 1.0, "supplies": 2.0},
		"shipwrightDays": 1.5, "mechanicDays": 0.5, "engineerDays": 0.5,
		"cargoMult": 0.85, "speedMult": 1.0, "turnMult": 1.0, "surveyFactor": 1.35,
		"trade": "Survey parties work 35% faster (root divides survey days); -15% hold for chart room and boats."},
	"workshop_rig": {"name": "Workshop Rig", "materials": {"timber": 2.0, "iron": 2.0, "supplies": 2.0, "copper": 0.5},
		"shipwrightDays": 2.0, "mechanicDays": 1.0, "engineerDays": 0.5,
		"cargoMult": 0.80, "speedMult": 0.96, "turnMult": 1.0, "repairFactor": 1.5,
		"trade": "Crew repairs 50% faster underway (still consumes kits); -20% hold, -4% speed."},
	"tug_rig": {"name": "Tug Rig", "materials": {"iron": 2.0, "timber": 1.0, "engines": 1.0},
		"shipwrightDays": 1.5, "mechanicDays": 1.5, "engineerDays": 0.5,
		"cargoMult": 0.90, "speedMult": 0.97, "turnMult": 0.97, "towSpeedFactor": 0.75, "pumpsMult": 1.15,
		"trade": "Tows at 75% fleet speed instead of 55% and pumps 15% harder; -10% hold, -3% speed/turn."},
	"auxiliary_tanks": {"name": "Auxiliary Tanks", "materials": {"iron": 1.5, "copper": 1.0, "supplies": 1.0},
		"shipwrightDays": 1.0, "mechanicDays": 1.0, "engineerDays": 0.5,
		"cargoMult": 0.88, "speedMult": 0.97, "turnMult": 1.0, "enduranceFactor": 1.5, "fuelUseMult": 0.9,
		"trade": "50% more fuel endurance and 10% lower fuel burn (root applies both); -12% hold, -3% speed."},
}

# Premium = the matching trade wage in goods.gd minus the 100-coin sailor
# base the existing daily_upkeep already pays every living crew member into
# the aggregate crewPurse. tick() therefore moves ONLY this differential.
const ROLES := {
	"pilot": {"name": "Pilot", "premium": 25, "basis": "carpenter-tier 125 - sailor 100"},
	"gunner": {"name": "Gunner", "premium": 50, "basis": "gunsmith 150 - sailor 100"},
	"chief_engineer": {"name": "Chief Engineer", "premium": 100, "basis": "engineer 200 - sailor 100"},
	"surveyor": {"name": "Surveyor", "premium": 75, "basis": "foreman 175 - sailor 100"},
	"quartermaster": {"name": "Quartermaster", "premium": 25, "basis": "carpenter-tier 125 - sailor 100"},
}


static func _is_num(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func _num(v, fallback: float = 0.0) -> float:
	return float(v) if _is_num(v) else fallback


static func _round2(v: float) -> float:
	return snappedf(v, 0.01)


static func _fail(core, message: String) -> Dictionary:
	return core.fail(message) if core != null and core.has_method("fail") else {"ok": false, "message": message}


static func _ok(core, message: String, extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = core.ok(message) if core != null and core.has_method("ok") else {"ok": true, "message": message}
	out.merge(extra, true)
	return out


static func _boat(core, uid: String) -> Dictionary:
	return core.find_boat(uid) if core != null and core.has_method("find_boat") else {}


static func _history(state: Dictionary, boat: Dictionary, event: String, detail: String = "") -> void:
	var log: Array = boat.get("serviceHistory", []) if boat.get("serviceHistory") is Array else []
	log.append({"day": _num(state.get("day", 0.0)), "event": event, "detail": detail})
	while log.size() > MAX_HISTORY:
		log.pop_front()
	boat["serviceHistory"] = log


# Normalizes state["specialists"], state["specialistSeq"] and, per boat, the
# conversion id, specialistActive map and bounded serviceHistory. Returns the
# specialists array. Unknown conversion ids are cleared, never guessed.
static func ensure(state: Dictionary) -> Array:
	if not (state.get("specialists") is Array):
		state["specialists"] = []
	var cleaned: Array = []
	var max_suffix := 0
	for raw in state["specialists"]:
		if not (raw is Dictionary) or str(raw.get("id", "")).is_empty() or not ROLES.has(str(raw.get("role", ""))):
			continue
		var rec := {
			"id": str(raw["id"]), "boatUid": str(raw.get("boatUid", "")),
			"role": str(raw["role"]), "name": str(raw.get("name", "Sailor")),
			"coins": maxi(0, int(_num(raw.get("coins", 0)))),
			"arrears": maxi(0, int(_num(raw.get("arrears", 0)))),
			"premiumPerDay": int(ROLES[str(raw["role"])]["premium"]),
			"active": bool(raw.get("active", true)), "hiredDay": _num(raw.get("hiredDay", 0.0)),
			"portId": str(raw.get("portId", "")),"discharged":bool(raw.get("discharged",false)),"lost":bool(raw.get("lost",false))}
		raw.merge(rec,true)
		cleaned.append(raw)
		var tail := str(rec["id"]).trim_prefix("specialist-")
		if tail.is_valid_int():
			max_suffix = maxi(max_suffix, int(tail))
	while cleaned.size()>512:
		var retired: int=-1
		for i in range(cleaned.size()):
			if (cleaned[i].get("discharged",false) or cleaned[i].get("lost",false)) and int(cleaned[i].coins)==0 and int(cleaned[i].arrears)==0:
				retired=i;break
		if retired<0:break
		cleaned.remove_at(retired)
	state["specialists"] = cleaned
	state["specialistSeq"] = maxi(int(_num(state.get("specialistSeq", 0))), max_suffix)
	for boat in state.get("fleet", []) if state.get("fleet") is Array else []:
		if boat is Dictionary:
			if not CONVERSIONS.has(str(boat.get("conversion", ""))):
				boat["conversion"] = ""
			if not (boat.get("specialistActive") is Dictionary):
				boat["specialistActive"] = {}
			if not (boat.get("serviceHistory") is Array):
				boat["serviceHistory"] = []
			if not (boat.get("service") is Dictionary):
				boat["service"] = {}
	return cleaned


static func conversions() -> Dictionary:
	return CONVERSIONS.duplicate(true)


static func roles() -> Dictionary:
	return ROLES.duplicate(true)


# Canonical effective spec: fitted_spec (base + weapon/engine/armor loadout,
# rebuilt by root) with this boat's interior conversion and currently-paid
# specialist benefits applied once. Passing an already-effective spec back
# is a no-op (guarded), so stats can never stack. Damage, stores and mounts
# are not spec fields and are never read or changed here.
static func effective(boat: Dictionary, fitted_spec: Dictionary) -> Dictionary:
	var spec := fitted_spec.duplicate(true)
	var id := str(boat.get("conversion", ""))
	if str(spec.get("_conversionApplied", "")) == id and spec.get("_identityApplied", false):
		return spec
	spec["surveyFactor"] = 1.0
	spec["repairFactor"] = 1.0
	spec["enduranceFactor"] = 1.0
	spec["fuelCapacity"]=float(spec.get("fuelCapacity",60))
	spec["upkeepFactor"] = 1.0
	if CONVERSIONS.has(id):
		var c: Dictionary = CONVERSIONS[id]
		spec["cargo"] = maxi(1, int(round(_num(spec.get("cargo", 0.0)) * float(c.get("cargoMult", 1.0)))))
		spec["speed"] = _round2(_num(spec.get("speed", 0.0)) * float(c.get("speedMult", 1.0)))
		spec["turn"] = _round2(_num(spec.get("turn", 0.0)) * float(c.get("turnMult", 1.0)))
		if c.has("pumpsMult"):
			spec["pumps"] = _round2(_num(spec.get("pumps", 0.0)) * float(c["pumpsMult"]))
		if c.has("fuelUseMult"):
			spec["fuelUse"] = _round2(_num(spec.get("fuelUse", 1.0), 1.0) * float(c["fuelUseMult"]))
		for key in ["surveyFactor", "repairFactor", "enduranceFactor", "towSpeedFactor"]:
			if c.has(key):
				spec[key] = float(c[key])
		if c.has("enduranceFactor"):spec["fuelCapacity"]=float(spec.fuelCapacity)*float(c.enduranceFactor)
		spec["conversion"] = id
		spec["conversionName"] = str(c["name"])
	var active: Dictionary = boat.get("specialistActive", {}) if boat.get("specialistActive") is Dictionary else {}
	if bool(active.get("pilot", false)):
		spec["speed"] = _round2(_num(spec.get("speed", 0.0)) * 1.03)
		spec["turn"] = _round2(_num(spec.get("turn", 0.0)) * 1.04)
	if bool(active.get("gunner", false)):
		spec["fireRate"] = _round2(_num(spec.get("fireRate", 0.0)) * 1.06)
		for mount in spec.get("weaponMounts",[]):mount.fireRate=float(mount.fireRate)*1.06
	if bool(active.get("chief_engineer", false)):
		spec["repairFactor"] = _round2(_num(spec.get("repairFactor", 1.0), 1.0) + 0.25)
		spec["pumps"] = _round2(_num(spec.get("pumps", 0.0)) * 1.10)
	if bool(active.get("surveyor", false)):
		spec["surveyFactor"] = _round2(_num(spec.get("surveyFactor", 1.0), 1.0) + 0.30)
	if bool(active.get("quartermaster", false)):
		spec["upkeepFactor"] = 0.95
	spec["_conversionApplied"] = id
	spec["_identityApplied"] = true
	return spec


static func _free_labor(port: Dictionary) -> Dictionary:
	var workers := maxf(0.0, _num(port.get("availableWorkers", port.get("workforce", 0))) - _num(port.get("_yardWorkersUsed", 0)))
	var experts := maxf(0.0, _num(port.get("availableSpecialists", port.get("specialistWorkers", 0))) - _num(port.get("_yardSpecialistsUsed", 0)))
	return {"workers": workers, "experts": experts}


# Read-only conversion quote at local Economy prices, in the refit pattern:
# physical materials + shipwright (125/day) and mechanic (150) / engineer
# (200) trade wages from goods.gd, plus 8% yard margin and 5% duty.
static func quote_conversion(core, uid: String, id: String) -> Dictionary:
	var permission: Dictionary=preload("res://scripts/politics.gd").permit(core,"service")
	if not permission.ok:return permission
	var boat := _boat(core, uid)
	if not str(boat.get("storedPort","")).is_empty() and boat.storedPort!=core.current_port().get("id",""):return _fail(core,"Visit the harbor storing this hull first.")
	if boat.is_empty() or bool(boat.get("sunk", false)):
		return _fail(core, "That boat is not in your flotilla.")
	if not CONVERSIONS.has(id):
		return _fail(core, "Unknown interior conversion.")
	if str(boat.get("conversion", "")) == id:
		return _fail(core, "That conversion is already installed.")
	var port: Dictionary = core.current_port() if core.has_method("current_port") else {}
	if port.is_empty() or not (port.get("stocks") is Dictionary):
		return _fail(core, "Conversions need a harbor yard with physical stocks.")
	var probe: Dictionary=core.state.duplicate(true)
	for trial in probe.fleet:
		if trial.uid==uid:
			trial.conversion=id
			trial.spec=effective(trial,core.fitted_spec(boat))
	if preload("res://scripts/expedition.gd").cargo_weight(probe)>preload("res://scripts/expedition.gd").capacity(probe)+0.001:return _fail(core,"Offload cargo or activate another carrier before reducing hold space.")
	var c: Dictionary = CONVERSIONS[id]
	var materials: Dictionary = (c["materials"] as Dictionary).duplicate(true)
	var prices := {}
	var material_cost := 0
	for good in materials:
		prices[good] = Economy.price(port, str(good))
		material_cost += ceili(float(materials[good]) * float(prices[good]))
	var shipwright := ceili(float(c["shipwrightDays"]) * float(Goods.WAGES["shipwright"]))
	var mechanic := ceili(float(c["mechanicDays"]) * float(Goods.WAGES["mechanic"]))
	var engineer := ceili(float(c["engineerDays"]) * float(Goods.WAGES["engineer"]))
	var subtotal := material_cost + shipwright + mechanic + engineer
	var margin := ceili(subtotal * 0.08)
	var tax := ceili(subtotal * 0.05)
	var worker_days := float(c["shipwrightDays"])
	var expert_days := float(c["mechanicDays"]) + float(c["engineerDays"])
	var q := {"ok": true, "boatUid": uid, "conversion": id, "conversionName": str(c["name"]),
		"materials": materials, "materialPrices": prices, "materialCost": material_cost,
		"shipwrightWages": shipwright, "mechanicWages": mechanic, "engineerWages": engineer,
		"margin": margin, "tax": tax, "cost": subtotal + margin + tax,
		"workerDays": worker_days, "expertDays": expert_days, "harbor": str(port.get("id", "")),
		"trade": str(c["trade"]), "message": "%s: %d coins. %s" % [str(c["name"]), subtotal + margin + tax, str(c["trade"])]}
	for good in materials:
		if _num(port["stocks"].get(good, 0.0)) + 0.000001 < float(materials[good]):
			q["ok"] = false
			q["message"] = "The yard lacks physical %s for this conversion." % str(Goods.ITEMS[str(good)]["name"])
			return q
	var free := _free_labor(port)
	if float(free["workers"]) + 0.000001 < worker_days + expert_days or float(free["experts"]) + 0.000001 < expert_days:
		q["ok"] = false
		q["message"] = "The shared yard has insufficient available workers or specialists today."
	return q


# Installs after re-quoting; coin, stock and workforce refusals happen before
# any write. Payments split to existing harbor purses exactly as refits do.
# The boat keeps its damage, stores, breaches, crew and original loadout.
static func install_conversion(core, uid: String, id: String) -> Dictionary:
	var q := quote_conversion(core, uid, id)
	if not bool(q.get("ok", false)):
		return q
	var state: Dictionary = core.state
	ensure(state)
	if int(state.get("coins", 0)) < int(q["cost"]):
		return _fail(core, "The conversion needs %d coins." % int(q["cost"]))
	var boat := _boat(core, uid)
	var port: Dictionary = core.current_port()
	var ledger: Array = state.get("moneyLog", []) if state.get("moneyLog") is Array else []
	Money.move(state, "coins", port, "cash", int(q["materialCost"]) + int(q["margin"]), "Conversion parts and yard margin", ledger)
	Money.move(state, "coins", port, "householdPurse", int(q["shipwrightWages"]), "Conversion shipwright wages", ledger)
	Money.move(state, "coins", port, "expertPurse", int(q["mechanicWages"]) + int(q["engineerWages"]), "Conversion mechanic and engineer wages", ledger)
	Money.move(state, "coins", port, "governmentPurse", int(q["tax"]), "Conversion duty", ledger)
	state["moneyLog"] = ledger
	for good in q["materials"]:
		port["stocks"][good] = maxf(0.0, _num(port["stocks"].get(good, 0.0)) - float(q["materials"][good]))
	port["_yardWorkersUsed"] = _num(port.get("_yardWorkersUsed", 0)) + ceili(float(q["workerDays"]) + float(q["expertDays"]))
	port["_yardSpecialistsUsed"] = _num(port.get("_yardSpecialistsUsed", 0)) + ceili(float(q["expertDays"]))
	boat["conversion"] = id
	if core.has_method("fitted_spec"):
		boat["spec"] = effective(boat, core.fitted_spec(boat))
	_history(state, boat, "conversion", id)
	return _ok(core, "Installed %s on %s for %d coins." % [str(q["conversionName"]), str(boat.get("name", "boat")), int(q["cost"])], {"cost": int(q["cost"])})


static func _specialist_on(state: Dictionary, uid: String, role: String) -> Dictionary:
	for rec in state.get("specialists", []):
		if rec is Dictionary and str(rec.get("boatUid", "")) == uid and str(rec.get("role", "")) == role and not rec.get("discharged",false) and not rec.get("lost",false):
			return rec
	return {}


# Hires ONE real sailor into ONE free crew berth as a specialist. Requires a
# docked harbor with a recruit, workforce and a free specialist to spare, and
# coins for the finite Economy recruit advance (10 sailor-days, 1000-1200),
# which moves captain -> aggregate crewPurse exactly like ordinary hiring.
# The specialist also consumes one availableSpecialists slot at that harbor;
# nobody is invented and no expert is double-employed by this record.
static func hire_specialist(core, uid: String, role: String) -> Dictionary:
	var permission: Dictionary=preload("res://scripts/politics.gd").permit(core,"service")
	if not permission.ok:return permission
	var state: Dictionary = core.state if core != null and core.get("state") is Dictionary else {}
	if state.is_empty():
		return _fail(core, "No campaign state.")
	ensure(state)
	var boat := _boat(core, uid)
	if boat.is_empty() or bool(boat.get("sunk", false)):
		return _fail(core, "That boat is not in your flotilla.")
	if not str(boat.get("storedPort","")).is_empty() and boat.storedPort!=core.current_port().get("id",""):return _fail(core,"Visit the harbor storing this hull before hiring.")
	if not ROLES.has(role):
		return _fail(core, "Unknown specialist role.")
	if not _specialist_on(state, uid, role).is_empty():
		return _fail(core, "That boat already has a %s." % str(ROLES[role]["name"]))
	var port: Dictionary = core.current_port() if core.has_method("current_port") else {}
	if port.is_empty():
		return _fail(core, "Hire specialists at a harbor.")
	if _num(boat.get("crew", 0))+PassengerManifest.assigned(core.state,uid)+float(core.state.get("captiveBerths",{}).get(uid,0)) >= _num(boat.get("crewMax", 0)):
		return _fail(core, "No free crew berth for another sailor.")
	if int(_num(port.get("recruits", 0))) < 1 or int(_num(port.get("workforce", 0))) < 1:
		return _fail(core, "This harbor has no sailor to spare.")
	if int(_num(port.get("availableSpecialists", port.get("specialistWorkers", 0)))) < 1:
		return _fail(core, "This harbor has no free specialist to spare today.")
	if port.get("training") is Dictionary and int(port.training.get("qualified",{}).get("sailor",0))<1:
		return _fail(core,"No qualified sailor is available. Fund a harbor training course first.")
	var advance := Economy.recruit_cost(port, 1)
	if int(state.get("coins", 0)) < advance:
		return _fail(core, "Hiring needs a %d-coin advance." % advance)
	var ledger: Array = state.get("moneyLog", []) if state.get("moneyLog") is Array else []
	if not Money.move(state, "coins", state, "crewPurse", advance, "Specialist hiring advance", ledger):
		return _fail(core, "Hiring needs a %d-coin advance." % advance)
	state["moneyLog"] = ledger
	port["recruits"] = maxi(0, int(_num(port.get("recruits", 0))) - 1)
	port["workforce"] = maxi(0, int(_num(port.get("workforce", 0))) - 1)
	if port.get("training") is Dictionary:
		var training_role: String="gunner" if role=="gunner" else ("mechanic" if role=="chief_engineer" else "sailor")
		if int(port.training.qualified.get(training_role,0))<1:training_role="sailor"
		core.TrainingOps.Training.consume_qualified(port,1,training_role)
	if port.has("availableWorkers"):
		port["availableWorkers"] = maxi(0, int(_num(port.get("availableWorkers", 0))) - 1)
	if port.has("availableSpecialists"):
		port["availableSpecialists"] = maxi(0, int(_num(port.get("availableSpecialists", 0))) - 1)
	port["specialists"]=maxi(0,int(port.get("specialists",port.get("specialistWorkers",0)))-1)
	port["specialistWorkers"]=port.specialists
	Economy.sync_workforce(port)
	boat["crew"] = _num(boat.get("crew", 0)) + 1.0
	if _num(boat["crew"]) >= _num(boat.get("crewMin", 0)):
		boat["mothballed"] = false
	state["specialistSeq"] = int(state.get("specialistSeq", 0)) + 1
	var seq := int(state["specialistSeq"])
	var rec := {"id": "specialist-%d" % seq, "boatUid": uid, "role": role,
		"name": NAMES[(seq - 1) % NAMES.size()], "coins": 0, "arrears": 0,
		"premiumPerDay": int(ROLES[role]["premium"]), "active": true,
		"hiredDay": _num(state.get("day", 0.0)), "portId": str(port.get("id", ""))}
	state["specialists"].append(rec)
	var act: Dictionary = boat.get("specialistActive", {}) if boat.get("specialistActive") is Dictionary else {}
	act[role] = true
	boat["specialistActive"] = act
	if core.has_method("fitted_spec"):
		boat["spec"] = effective(boat, core.fitted_spec(boat))
	_history(state, boat, "specialist", role)
	return _ok(core, "%s signed on as %s aboard %s." % [str(rec["name"]), str(ROLES[role]["name"]), str(boat.get("name", "boat"))],
		{"specialist": rec.duplicate(true), "advance": advance})


# Pays specialist premiums for whole days, arrears first, captain purse ->
# each specialist's own coins purse. The 100/day base stays with the existing
# daily_upkeep over boat.crew (specialists occupy berths), so nobody is paid
# twice. Unpaid premium accrues as arrears and disables that role's benefit
# (boat.specialistActive) until settled; boat.spec is rebuilt canonically.
static func tick(core, days: float = 1.0) -> Array:
	var messages: Array = []
	var state: Dictionary = core.state if core != null and core.get("state") is Dictionary else {}
	if state.is_empty():
		return messages
	ensure(state)
	var whole := maxi(0, int(floor(days)))
	if whole == 0:
		return messages
	var ledger: Array = state.get("moneyLog", []) if state.get("moneyLog") is Array else []
	var touched := {}
	for rec in state["specialists"]:
		if rec.get("discharged",false) or rec.get("lost",false):continue
		var boat := _boat(core, str(rec["boatUid"]))
		if boat.is_empty() or bool(boat.get("sunk", false)):
			if bool(rec["active"]):
				rec["active"] = false
				messages.append("%s has no living boat; premium paused, purse preserved." % str(rec["name"]))
			continue
		var owed: int = int(rec["arrears"]) + int(rec["premiumPerDay"]) * whole
		var paid: int = mini(int(state.get("coins", 0)), owed)
		if paid > 0:
			Money.move(state, "coins", rec, "coins", paid, "Specialist professional premium", ledger)
		rec["arrears"] = owed - paid
		rec["active"] = int(rec["arrears"]) == 0 and int(state.get("wageArrears",0))==0
		var act: Dictionary = boat.get("specialistActive", {}) if boat.get("specialistActive") is Dictionary else {}
		if bool(act.get(str(rec["role"]), false)) != bool(rec["active"]):
			act[str(rec["role"])] = bool(rec["active"])
			boat["specialistActive"] = act
			touched[str(rec["boatUid"])] = boat
		if int(rec["arrears"]) > 0:
			messages.append("%s premium short by %d coins; benefit suspended." % [str(ROLES[str(rec["role"])]["name"]), int(rec["arrears"])])
	state["moneyLog"] = ledger
	if core.has_method("fitted_spec"):
		for uid in touched:
			touched[uid]["spec"] = effective(touched[uid], core.fitted_spec(touched[uid]))
	return messages


# Attachment only: bounded per-boat history + plain counters. Repeat service
# never changes any stat, price or wage. Known results: won/lost/retreated
# count as battles (won also wins); rescue/trade/survey count themselves;
# anything else is logged verbatim without a counter.
static func record_service(core, boat_uids: Array, result: String) -> void:
	var state: Dictionary = core.state if core != null and core.get("state") is Dictionary else {}
	if state.is_empty() or result.is_empty():
		return
	ensure(state)
	for uid in boat_uids:
		var boat := _boat(core, str(uid))
		if boat.is_empty():
			continue
		var service: Dictionary = boat.get("service", {}) if boat.get("service") is Dictionary else {}
		if result in ["won", "lost", "retreated"]:
			service["battles"] = int(_num(service.get("battles", 0))) + 1
			if result == "won":
				service["wins"] = int(_num(service.get("wins", 0))) + 1
		elif result in ["rescue", "trade", "survey"]:
			service[result + "s" if result != "trade" else "trades"] = int(_num(service.get(result + "s" if result != "trade" else "trades", 0))) + 1
		boat["service"] = service
		_history(state, boat, result)
