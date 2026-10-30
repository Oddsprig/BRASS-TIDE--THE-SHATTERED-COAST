extends RefCounted
## Detached voyage estimate only. Campaign remains the movement/payment authority.
const OceanWorld = preload("res://scripts/ocean_world064.gd")
const OceanTravel066 = preload("res://scripts/ocean_travel066.gd")
const Expedition = preload("res://scripts/expedition.gd")
const Economy = preload("res://scripts/economy.gd")
const FleetSupport = preload("res://scripts/fleet_support.gd")
const HoldManifest = preload("res://scripts/hold_manifest.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const Factions = preload("res://scripts/factions.gd")
const INTENT_KEYS: Array = ["targetRegionId", "targetApproachId", "outExit", "backExit", "homeEntry", "returnPortId", "idleDays"]
const STORE_EPSILON: float = 0.001


static func quote(state: Dictionary, world: Dictionary, context064: Dictionary, intent: Dictionary, runtime: Dictionary) -> Dictionary:
	var result: Dictionary = _empty()
	var error: String = _state_error(state)
	if not error.is_empty():return _refuse(result, "state", error)
	if not _number(runtime.get("speed")) or float(runtime.speed) <= 0.0:
		return _refuse(result, "speed", "A voyage needs a traveling fleet with a finite positive current speed.")
	if not _number(runtime.get("clearance")) or float(runtime.clearance) < 0.0 or not runtime.get("blocker") is String:
		return _refuse(result, "runtime", "Supply the actual fleet clearance and current transition blocker.")
	var prepared: Dictionary = OceanWorld.prepare(state, context064, float(runtime.clearance))
	if not prepared.ok:return _refuse(result, str(prepared.code), str(prepared.message))
	var location: Dictionary = prepared.location
	result.origin = {"world064": location.world064.duplicate(true), "position": location.position.duplicate(true),
		"day": float(state.day), "econDay": float(state.econDay)}
	error = _intent_error(intent, location, context064)
	if not error.is_empty():return _refuse(result, "intent", error)
	var port: Dictionary = {}
	for candidate in state.ports:
		if candidate is Dictionary and candidate.get("id") == intent.returnPortId:
			if not port.is_empty():return _refuse(result, "harbor", "The return harbor ID is repeated.")
			port = candidate
	if port.is_empty() or not context064.ports.has(intent.returnPortId):
		return _refuse(result, "harbor", "Choose an existing home harbor for the return.")
	if not _number(port.get("x")) or not _number(port.get("y")) or _point(port) != context064.ports[intent.returnPortId]:
		return _refuse(result, "harbor", "The return harbor must retain its actual home coordinates.")
	# Gate views need no boats. Runtime fitted dictionaries are not strict 064 DTOs.
	var viewed: Dictionary = OceanWorld.view(context064, location, [])
	if not viewed.ok:return _refuse(result, str(viewed.code), str(viewed.message))
	result.intent = _named_intent(intent, viewed.view, location, port)
	if Expedition.traveling(state).is_empty():return _refuse(result, "fleet", "No seaworthy crewed boat is traveling.")
	var itinerary: Dictionary = _itinerary(context064, location, intent, port, runtime)
	if not itinerary.ok:return _refuse(result, str(itinerary.code), str(itinerary.message))
	var distances: Dictionary = {"outward": 0.0, "return": 0.0, "total": 0.0, "byLayer": {"home": 0.0, "local": 0.0, "ocean": 0.0}}
	for leg in itinerary.legs:
		distances[leg.phase] += float(leg.physicalDistance)
		distances.byLayer[leg.layer] += float(leg.physicalDistance)
		distances.total += float(leg.physicalDistance)
	var speed: float = float(runtime.speed)
	var outward: float = float(distances.outward) / speed / Expedition.DAY_SECONDS
	var returning: float = float(distances["return"]) / speed / Expedition.DAY_SECONDS
	var conservative_outward: float = outward
	var conservative_returning: float = returning
	var weather: Dictionary = {}
	if runtime.has("ocean066"):
		if not runtime.ocean066 is Dictionary:return _refuse(result, "forecast", "Supply the prepared shared ocean weather context.")
		weather = OceanTravel066.forecast(runtime.ocean066, itinerary.legs, speed, float(state.day) * Expedition.DAY_SECONDS)
		if not weather.ok:return _refuse(result, str(weather.code), str(weather.message))
		var durations: Dictionary = {"outward": 0.0, "return": 0.0, "safeOutward": 0.0, "safeReturn": 0.0}
		for index in range(itinerary.legs.size()):
			var leg: Dictionary = itinerary.legs[index]
			var time: Dictionary = weather.legTimes[index]
			leg["seconds"] = time.expectedSeconds
			leg["conservativeSeconds"] = time.conservativeSeconds
			durations[leg.phase] += float(time.expectedSeconds)
			durations["safeOutward" if leg.phase == "outward" else "safeReturn"] += float(time.conservativeSeconds)
		outward = float(durations.outward) / Expedition.DAY_SECONDS
		returning = float(durations["return"]) / Expedition.DAY_SECONDS
		conservative_outward = float(durations.safeOutward) / Expedition.DAY_SECONDS
		conservative_returning = float(durations.safeReturn) / Expedition.DAY_SECONDS
	var end_day: float = float(state.day) + outward + float(intent.idleDays) + returning
	var conservative_end_day: float = float(state.day) + conservative_outward + float(intent.idleDays) + conservative_returning
	if not is_finite(end_day) or not is_finite(conservative_end_day):return _refuse(result, "time", "The chosen route does not have a finite travel time.")
	var access: Dictionary = Factions.access(state, port)
	var safe_until = state.get("relationships", {}).get("safeConduct", {}).get(str(port.id), 0.0)
	if not _number(safe_until):return _refuse(result, "harbor", "The return harbor's safe-conduct expiry is invalid.")
	if not bool(access.get("legal", false)) and float(safe_until) <= conservative_end_day:
		return _refuse(result, "access", "The selected home harbor needs legal access or safe conduct lasting past the estimated arrival.")
	# No normalization, daily settlement, inventory loading or publication reaches live state.
	var snapshot: Dictionary = state.duplicate(true)
	HoldManifest.allocate(snapshot)
	var pending: float = maxf(0.0, floorf(float(state.day)) - float(state.econDay))
	var plan: Dictionary = {"outwardDays": conservative_outward, "returnDays": conservative_returning,
		"shoreDays": float(intent.idleDays) + pending, "foodCredit": float(state.get("surveyFoodCredit", 0.0))}
	var allowance: Dictionary = Expedition.report(snapshot, world, float(distances.outward), speed, plan)
	if not _finite_data(allowance):return _refuse(result, "stores", "Current stores or carrying space cannot produce a finite allowance.")
	var expected: Dictionary = _expected(snapshot, outward, returning, float(intent.idleDays), pending)
	var stores: Dictionary = _stores(snapshot, allowance, outward, returning) if weather.is_empty() else _stores(snapshot, allowance, outward, returning, conservative_outward, conservative_returning)
	var maintenance: Dictionary = _maintenance(snapshot)
	var premium_arrears: int = FleetSupport.premium(snapshot, true)
	var required: float = float(allowance.returnWages) + float(allowance.wageArrears) + premium_arrears
	var funding: Dictionary = {"premiumArrears": premium_arrears, "requiredCoins": required,
		"shortfall": maxf(0.0, required - float(state.coins))}
	if not _finite_data([expected, stores, funding, maintenance]):return _refuse(result, "cost", "The chosen voyage does not have finite resource costs.")
	result.legs = itinerary.legs
	result.nextAction = itinerary.nextAction
	result.distances = distances
	result.timing = {"speed": speed, "movingSeconds": float(distances.total) / speed,
		"outwardDays": outward, "returnDays": returning, "idleDays": float(intent.idleDays), "endDay": end_day}
	if not weather.is_empty():
		result.timing["movingSeconds"] = float(weather.expectedSeconds)
		result.timing["conservativeMovingSeconds"] = float(weather.conservativeSeconds)
		result.timing["conservativeOutwardDays"] = conservative_outward
		result.timing["conservativeReturnDays"] = conservative_returning
		result.timing["conservativeEndDay"] = conservative_end_day
		result["weatherForecast"] = {"conditions": weather.conditions, "validUntilSecond": weather.validUntilSecond, "assumptions": weather.assumptions}
		result.assumptions[0] = "Fitted specifications and crew stay fixed; ocean speed follows the disclosed current and weather assumptions."
		result.assumptions[4] = "Moving fuel uses forecast travel time. Whole movement steps can burn extra fuel at each arrival."
		result.assumptions.append("Readiness uses slowest-weather travel time plus the separate two-day contingency; expected consumption uses current-held weather.")
		result.assumptions.append_array(weather.assumptions)
	result.expected = expected
	result.allowance = allowance # Preserve the existing report, including its original boat rows.
	result.funding = funding
	result.stores = stores
	result.maintenance = maintenance
	result.warnings = allowance.warnings.duplicate(true)
	if float(stores.loadedShortfall) > STORE_EPSILON:
		result.blockers.append("Loaded fuel is short by %.2f drums across the actual moving hulls." % float(stores.loadedShortfall))
	if float(stores.tankShortfall) > STORE_EPSILON:
		result.warnings.append("Some full-trip allowances exceed fitted tanks; plan explicit manual transfers or fuel stops. Transfers are not automatic.")
	if float(allowance.foodShortfall) > STORE_EPSILON:result.blockers.append("Food does not cover the return and contingency allowance.")
	if float(allowance.allowanceOverload) > STORE_EPSILON:result.blockers.append("The provisioned allowance exceeds traveling hold capacity.")
	if float(funding.shortfall) > 0.0:result.blockers.append("The return payroll, base arrears and professional arrears need %d more coins." % ceili(float(funding.shortfall)))
	if not maintenance.usageKnown:result.warnings.append("Existing damage or uninitialized equipment makes repairs and speed conditional; repair-supply use is unknown.")
	if maintenance.conditionalFuel:result.warnings.append("Flooding or residual boat motion can consume an additional 0.006 fuel per second, including while waiting; that conditional use is not forecast.")
	if not str(runtime.blocker).is_empty():result.blockers.append(str(runtime.blocker))
	if result.nextAction.kind == "transition" and not location.path.is_empty():
		result.blockers.append("Finish or stop the current course before changing charts.")
	result.warnings.append_array(result.blockers)
	result.readyForAllowance = bool(allowance.readyForAllowance) and result.blockers.is_empty()
	result.routeOk = true
	result.ok = true
	result.code = "ok"
	result.message = "Route estimated; the current allowance is covered." if result.readyForAllowance else "Route estimated; review the preparation shortfalls and conditions."
	return _string_data(result)


static func _empty() -> Dictionary:
	return {"ok": false, "code": "unquoted", "message": "", "routeOk": false, "readyForAllowance": false,
		"origin": {}, "intent": {}, "legs": [], "distances": {}, "timing": {}, "expected": {},
		"allowance": {}, "funding": {}, "stores": {}, "maintenance": {}, "nextAction": _no_action(),
		"assumptions": ["Current speed, fitted specifications and crew stay fixed throughout the estimate.",
			"Expected costs assume funded payroll, no encounters, trade, new damage or transfers, and only the chosen idle time.",
			"The two-day contingency is an allowance, separate from expected consumption.",
			"Other business, project and emergency debits are excluded.",
			"Moving fuel is estimated from distance and current speed. Whole movement steps can burn extra fuel at each arrival.",
			"Cargo fuel is part of loose reserves; each boat's loaded fuel remains separate. Loading and transfers require explicit actions.",
			"Refresh from actual state before acting. Chart crossings and sailing safety are checked again at the action."],
		"warnings": [], "blockers": []}


static func _no_action() -> Dictionary:
	return {"kind": "none", "regionId": "", "approachId": "", "target": {}, "destination": "", "title": "Destination reached"}


static func _refuse(result: Dictionary, code: String, message: String) -> Dictionary:
	result.code = code
	result.message = message
	result.blockers.append(message)
	return _string_data(result)


static func _number(value) -> bool:
	return (value is int or value is float) and not value is bool and is_finite(float(value))


static func _finite_data(value, depth: int = 0) -> bool:
	if depth > 32:return false
	if value == null or value is bool or value is String or value is StringName:return true
	if value is int or value is float:return _number(value)
	if value is Array:
		for child in value:
			if not _finite_data(child, depth + 1):return false
		return true
	if value is Dictionary:
		for key in value:
			if not (key is String or key is StringName) or not _finite_data(value[key], depth + 1):return false
		return true
	return false


static func _string_data(value):
	# Member assignment in live code may introduce StringName keys; the quote is a DTO.
	if value is Dictionary:
		var copy: Dictionary = {}
		for key in value:copy[str(key)] = _string_data(value[key])
		return copy
	if value is Array:
		var copy: Array = []
		for child in value:copy.append(_string_data(child))
		return copy
	return str(value) if value is StringName else value


static func _state_error(state: Dictionary) -> String:
	for key in ["day", "econDay", "coins", "wageArrears"]:
		if not _number(state.get(key)) or float(state[key]) < 0.0:return "Current %s must be finite and nonnegative." % key
	if floorf(float(state.econDay)) != float(state.econDay):return "The settled economy day must be a whole day."
	if not state.get("fleet") is Array or not state.get("ports") is Array or not state.get("cargo") is Dictionary:
		return "Supply the actual fleet, home harbors and loose cargo."
	for key in ["freight", "tooling", "regionalCrises", "passengerTransport", "captiveBerths", "relationships"]:
		if state.has(key) and not state[key] is Dictionary:return "Current %s must be a dictionary." % key
	for key in ["voyageJobs", "specialists"]:
		if state.has(key) and not state[key] is Array:return "Current %s must be an array." % key
	if not state.get("relationships", {}).get("safeConduct", {}) is Dictionary:return "Safe-conduct dates must be a dictionary."
	if not state.get("tooling", {}).get("items", []) is Array:return "Carried tooling must be an array."
	for item in state.get("tooling", {}).get("items", []):
		if not item is Dictionary:return "Carried tooling entries must be records."
		if item.get("location", "") == "cargo" and (not item.has("id") or not HoldManifest.Tooling.KINDS.has(item.get("kind"))):return "Carried tooling needs its existing ID and kind."
	var freight: Dictionary = state.get("freight", {})
	if not _lot_valid(freight):return "Sealed freight needs its actual good and finite nonnegative quantity."
	for job in state.get("voyageJobs", []):
		if not job is Dictionary or not job.get("freight", {}) is Dictionary:return "Voyage jobs must retain their freight records."
		if not _lot_valid(job.get("freight", {})) or (not job.get("freight", {}).is_empty() and not job.get("id") is String):return "Voyage freight needs its existing job ID and finite quantity."
		if not job.get("charterFood", {}) is Dictionary:return "Prepaid charter food must retain its physical record."
	if not state.get("regionalCrises", {}).get("jobs", []) is Array:return "Traveling civilian jobs must be an array."
	for job in state.get("regionalCrises", {}).get("jobs", []):
		if not job is Dictionary or not job.get("stage") is String or not job.get("food", {}) is Dictionary:return "Traveling civilian jobs must retain their stage and physical food."
	for key in ["fleet", "cargo", "freight", "voyageJobs", "tooling", "specialists", "regionalCrises", "passengerTransport", "captiveBerths"]:
		if not _finite_data(state.get(key)):return "Current %s must contain finite detached data." % key
	for key in state.cargo:
		if not _number(state.cargo[key]) or float(state.cargo[key]) < 0.0:return "Loose cargo quantities must be finite and nonnegative."
	if not _number(state.get("surveyFoodCredit", 0.0)) or float(state.get("surveyFoodCredit", 0.0)) < 0.0:return "Prepaid food credit must be finite and nonnegative."
	var uids: Dictionary = {}
	for boat in state.fleet:
		if not boat is Dictionary or not boat.get("uid") is String or str(boat.uid).is_empty() or uids.has(boat.uid):return "Owned boats need distinct existing UIDs."
		uids[boat.uid] = true
		if not boat.get("spec") is Dictionary:return "Each boat needs its actual fitted specification."
		for key in ["sunk", "mothballed", "needsHarborRepair", "towed"]:
			if not boat.get(key, false) is bool:return "Boat eligibility flags must be booleans."
		if not boat.get("storedPort", "") is String:return "Stored harbor IDs must be strings."
		for key in ["crew", "crewMin", "fuel", "ammo", "supplies", "hp", "maxHp", "water", "fire"]:
			if not _number(boat.get(key)) or float(boat[key]) < 0.0:return "Boat %s must be finite and nonnegative." % key
		for key in ["wounded", "vx", "vy"]:
			if not _number(boat.get(key, 0.0)):return "Boat %s must be finite." % key
		if not boat.get("breaches", []) is Array:return "Boat breaches must retain their physical records."
		for breach in boat.get("breaches", []):
			if not breach is Dictionary or not _number(breach.get("area")) or float(breach.area) < 0.0:return "Breach areas must be finite and nonnegative."
		if boat.get("policy", "balanced") not in ["balanced", "bail", "repair", "fight"]:return "Boat repair policy is unknown."
		for key in ["size", "speed", "cargo", "fuelCapacity", "kitCapacity", "ammoCapacity", "fuelUse", "upkeepFactor"]:
			if boat.spec.has(key) and (not _number(boat.spec[key]) or float(boat.spec[key]) < 0.0):return "Fitted %s must be finite and nonnegative." % key
		var equipment: Dictionary = EquipmentDamage.inspect_owner(boat)
		if not equipment.ok:return str(equipment.get("error", "Boat equipment is invalid."))
	for rec in state.get("specialists", []):
		if not rec is Dictionary or not rec.get("boatUid") is String:return "Specialists need their actual boat UID."
		for key in ["premiumPerDay", "arrears"]:
			if not _number(rec.get(key)) or float(rec[key]) < 0.0:return "Specialist payroll must be finite and nonnegative."
	return ""


static func _lot_valid(lot: Dictionary) -> bool:
	return lot.is_empty() or (lot.get("good") is String and _number(lot.get("qty")) and float(lot.qty) >= 0.0)


static func _intent_error(intent: Dictionary, location: Dictionary, context: Dictionary) -> String:
	if intent.size() != INTENT_KEYS.size():return "Use the seven explicit voyage-intent fields."
	for key in INTENT_KEYS:
		if not intent.has(key):return "Missing voyage choice: " + str(key)
		if key != "idleDays" and not intent[key] is String:return "Voyage choices must be strings."
	if not _number(intent.idleDays) or float(intent.idleDays) < 0.0:return "Idle days must be finite and nonnegative."
	if not context.regions.has(intent.targetRegionId):return "Choose an existing coastal target region."
	if str(intent.returnPortId).is_empty():return "Choose the actual home harbor for the return."
	var leaving: bool = location.world064.layer != "ocean" and location.world064.regionId != intent.targetRegionId
	var remote: bool = intent.targetRegionId != OceanWorld.HOME
	var crossing_in: bool = location.world064.regionId != intent.targetRegionId
	var needed: Dictionary = {"outExit": leaving, "targetApproachId": remote or crossing_in, "backExit": remote, "homeEntry": remote}
	for key in needed:
		if needed[key] and intent[key] not in ["north", "south"]:return "Choose north or south explicitly for " + str(key) + "."
		if not needed[key] and not str(intent[key]).is_empty():return "Unused crossing choice %s must be empty on this layer." % key
	return ""


static func _named_intent(intent: Dictionary, view: Dictionary, location: Dictionary, port: Dictionary) -> Dictionary:
	var named: Dictionary = intent.duplicate(true)
	for key in ["targetRegionName", "targetApproachName", "outExitName", "backExitName", "homeEntryName"]:named[key] = ""
	for region in view.regions:
		if region.regionId == intent.targetRegionId:
			named["targetRegionName"] = str(region.name)
			for gate in region.approaches:
				if gate.id == intent.targetApproachId:named["targetApproachName"] = str(gate.name)
		for field in ["outExit", "backExit", "homeEntry"]:
			var region_id: String = str(location.world064.regionId) if field == "outExit" else (str(intent.targetRegionId) if field == "backExit" else OceanWorld.HOME)
			if region.regionId != region_id:continue
			for gate in region.approaches:
				if gate.id == intent[field]:named[str(field) + "Name"] = str(gate.name)
	named["returnPortName"] = str(port.get("name", port.id))
	return named


static func _point(value: Dictionary) -> Dictionary:
	return {"x": float(value.x), "y": float(value.y)}


static func _distance(a: Dictionary, b: Dictionary) -> float:
	var dx: float = float(b.x) - float(a.x)
	var dy: float = float(b.y) - float(a.y)
	return sqrt(dx * dx + dy * dy)


static func _itinerary(context: Dictionary, location: Dictionary, intent: Dictionary, port: Dictionary, runtime: Dictionary) -> Dictionary:
	var journey: Dictionary = {"ok": true, "location": location.duplicate(true), "legs": [], "nextAction": _no_action(),
		"speed": float(runtime.speed), "clearance": float(runtime.clearance)}
	if location.world064.regionId != intent.targetRegionId:
		if location.world064.layer != "ocean":
			if not _cross(context, journey, "outward", str(location.world064.regionId), str(intent.outExit)):return journey
		if not _cross(context, journey, "outward", str(intent.targetRegionId), str(intent.targetApproachId)):return journey
	elif intent.targetRegionId != OceanWorld.HOME:
		if not _sail_gate(context, journey, "outward", str(intent.targetRegionId), str(intent.targetApproachId), true):return journey
	if intent.targetRegionId == OceanWorld.HOME:
		if not _sail_home(context, journey, "outward", port):return journey
	else:
		if not _cross(context, journey, "return", str(intent.targetRegionId), str(intent.backExit)):return journey
		if not _cross(context, journey, "return", OceanWorld.HOME, str(intent.homeEntry)):return journey
	if not _sail_home(context, journey, "return", port):return journey
	return journey


static func _route_failure(journey: Dictionary, code: String, message: String) -> bool:
	journey.ok = false
	journey["code"] = code
	journey["message"] = message
	return false


static func _gate(context: Dictionary, journey: Dictionary, region_id: String, approach_id: String) -> Dictionary:
	var viewed: Dictionary = OceanWorld.view(context, journey.location, [])
	if not viewed.ok:
		_route_failure(journey, str(viewed.code), str(viewed.message))
		return {}
	for approach in viewed.view.approaches:
		if approach.regionId == region_id and approach.id == approach_id:return approach
	_route_failure(journey, "approach", "The chosen approach is not on the projected current chart.")
	return {}


static func _sail_gate(context: Dictionary, journey: Dictionary, phase: String, region_id: String, approach_id: String, target_only: bool = false) -> bool:
	var gate: Dictionary = _gate(context, journey, region_id, approach_id)
	if gate.is_empty():return false
	# A target already inside its real arrival disk is reached. Keep that exact point.
	if target_only and _distance(journey.location.position, gate.position) <= float(gate.radius):return true
	var destination: String = "" if journey.location.world064.layer == "home" else "approach:%s:%s" % [region_id, approach_id]
	return _sail(context, journey, phase, gate.position, destination, region_id, approach_id, "Sail to " + str(gate.name))


static func _sail_home(context: Dictionary, journey: Dictionary, phase: String, port: Dictionary) -> bool:
	# Same current-port semantics as Campaign. Do not snap a docked origin away.
	if journey.location.world064.layer == "home" and _distance(journey.location.position, port) < 65.0:return true
	return _sail(context, journey, phase, _point(port), str(port.id), OceanWorld.HOME, "", "Sail to " + str(port.get("name", port.id)))


static func _sail(context: Dictionary, journey: Dictionary, phase: String, target: Dictionary, destination: String, region_id: String, approach_id: String, title: String) -> bool:
	var start: Dictionary = journey.location
	var plotted: Dictionary = OceanWorld.plot(context, start, target, destination, float(journey.clearance))
	if not plotted.ok:return _route_failure(journey, str(plotted.code), str(plotted.message))
	var length: float = 0.0
	var previous: Dictionary = start.position
	for waypoint in plotted.location.path:
		length += _distance(previous, waypoint)
		previous = waypoint
	var scale: float = float(context.ocean.localUnitsPerUnit) if start.world064.layer == "ocean" else 1.0
	var physical: float = length * scale
	var seconds: float = physical / float(journey.speed)
	if not is_finite(seconds) or not is_finite(physical):return _route_failure(journey, "route", "The route length or travel time is not finite.")
	var reached: Dictionary = plotted.location
	if length > 0.0:
		# One spatial projection, not a campaign tick; tiny slack finishes sum roundoff.
		var advanced: Dictionary = OceanWorld.advance(context, reached, seconds + maxf(0.00000001, seconds * 0.000000000001), float(journey.speed), float(journey.clearance))
		if not advanced.ok:return _route_failure(journey, str(advanced.code), str(advanced.message))
		if not advanced.location.path.is_empty():return _route_failure(journey, "route", "The spatial projection did not finish its full route.")
		reached = advanced.location
		journey.legs.append({"phase": phase, "kind": "sail", "layer": str(start.world064.layer), "regionId": str(start.world064.regionId),
			"from": _point(start.position), "to": _point(reached.position), "path": plotted.location.path.duplicate(true),
			"chartDistance": length, "physicalDistance": physical, "seconds": seconds, "destination": destination, "approachId": approach_id})
		if phase == "outward" and journey.nextAction.kind == "none":
			journey.nextAction = {"kind": "course", "regionId": region_id, "approachId": approach_id,
				"target": _point(target), "destination": destination, "title": title}
	journey.location = reached
	return true


static func _cross(context: Dictionary, journey: Dictionary, phase: String, region_id: String, approach_id: String) -> bool:
	# Future geometry is independent of today's pursuit/shore blocker. Readiness
	# records that blocker separately; Main/Core recheck it for the explicit action.
	var transferred: Dictionary = OceanWorld.transition(context, journey.location, region_id, approach_id, float(journey.clearance), "")
	if not transferred.ok:
		if not _sail_gate(context, journey, phase, region_id, approach_id):return false
		transferred = OceanWorld.transition(context, journey.location, region_id, approach_id, float(journey.clearance), "")
	if not transferred.ok:return _route_failure(journey, str(transferred.code), str(transferred.message))
	var start: Dictionary = journey.location
	var finish: Dictionary = transferred.location
	journey.legs.append({"phase": phase, "kind": "transition", "layer": str(start.world064.layer), "regionId": str(start.world064.regionId),
		"from": _point(start.position), "to": _point(finish.position), "path": [], "chartDistance": 0.0, "physicalDistance": 0.0, "seconds": 0.0,
		"approachId": approach_id, "transferRegionId": region_id, "toLayer": str(finish.world064.layer), "toRegionId": str(finish.world064.regionId)})
	if phase == "outward" and journey.nextAction.kind == "none":
		var entering: bool = finish.world064.layer != "ocean"
		journey.nextAction = {"kind": "transition", "regionId": region_id, "approachId": approach_id,
			"target": {}, "destination": "", "title": "Enter coastal chart" if entering else "Cross to the open ocean"}
	journey.location = finish
	return true


static func _expected(state: Dictionary, outward: float, returning: float, idle: float, pending: float) -> Dictionary:
	var upkeep: Dictionary = Economy.daily_upkeep(state.fleet)
	var premium: int = FleetSupport.premium(state)
	var arrears: int = FleetSupport.premium(state, true)
	var day: float = float(state.day)
	var outward_end: float = day + outward
	var idle_end: float = outward_end + idle
	var days: Dictionary = {"pending": pending, "outward": floorf(outward_end) - floorf(day),
		"idle": floorf(idle_end) - floorf(outward_end), "return": floorf(idle_end + returning) - floorf(idle_end)}
	var result: Dictionary = {"pendingDays": pending, "futurePayrollDays": days.outward + days.idle + days["return"],
		"totalPayrollDays": pending + days.outward + days.idle + days["return"], "food": 0.0, "baseWages": 0.0,
		"premiums": 0.0, "premiumArrearsPaid": 0.0, "coinsRequired": 0.0, "byPhase": {}}
	var credit: float = float(state.get("surveyFoodCredit", 0.0))
	for phase in ["pending", "outward", "idle", "return"]:
		var count: float = float(days[phase])
		var food: float = float(upkeep.food) * count
		var prepaid: float = minf(food, credit)
		credit -= prepaid
		var old_premium: int = arrears if count > 0.0 else 0
		if count > 0.0:arrears = 0
		var row: Dictionary = {"payrollDays": count, "food": food - prepaid, "baseWages": float(upkeep.wages) * count,
			"premiums": premium * count, "premiumArrearsPaid": old_premium, "coinsRequired": float(upkeep.wages) * count + premium * count + old_premium}
		result.byPhase[phase] = row
		for key in ["food", "baseWages", "premiums", "premiumArrearsPaid", "coinsRequired"]:result[key] += row[key]
	return result


static func _stores(state: Dictionary, allowance: Dictionary, outward: float, returning: float, safe_outward: float = -1.0, safe_returning: float = -1.0) -> Dictionary:
	var traveling: Dictionary = {}
	for row in allowance.boats:traveling[str(row.uid)] = true
	var result: Dictionary = {"looseFuel": float(state.cargo.get("fuel", 0.0)), "looseSupplies": float(state.cargo.get("supplies", 0.0)),
		"cargoManifest": state.cargoManifest.duplicate(true), "unassigned": state.cargoManifest.get("unassigned", {}).duplicate(true),
		"boats": [], "fuelRequired": 0.0, "loadedShortfall": 0.0, "tankShortfall": 0.0}
	for boat in state.fleet:
		if boat.get("sunk", false) or not str(boat.get("storedPort", "")).is_empty():continue
		var burns: bool = not boat.get("mothballed", false)
		var forecasted: bool = safe_outward >= 0.0 and safe_returning >= 0.0
		var moving_days: float = safe_outward + safe_returning if forecasted else outward + returning
		var row: Dictionary = Expedition._fuel_allowance(boat, moving_days + float(allowance.reserveDays) if burns else 0.0)
		row.merge({"traveling": traveling.has(str(boat.uid)), "burnsWhileMoving": burns,
			"mothballed": bool(boat.get("mothballed", false)), "towed": bool(boat.get("towed", false)),
			"needsHarborRepair": bool(boat.get("needsHarborRepair", false)),
			"cargoFuel": float(state.cargoManifest.get(str(boat.uid), {}).get("fuel", 0.0)), "loadedSupplies": float(boat.supplies),
			"outwardFuel": float(row.fuelPerDay) * outward if burns else 0.0,
			"returnFuel": float(row.fuelPerDay) * returning if burns else 0.0,
			"contingencyFuel": float(row.fuelPerDay) * float(allowance.reserveDays) if burns else 0.0,
			"loadedShortfall": float(row.fuelShortfall), "manualTransferRequired": float(row.fuelShortfall) > STORE_EPSILON})
		if forecasted:
			row["conservativeOutwardFuel"] = float(row.fuelPerDay) * safe_outward if burns else 0.0
			row["conservativeReturnFuel"] = float(row.fuelPerDay) * safe_returning if burns else 0.0
		result.boats.append(row)
		result.fuelRequired += float(row.fuelRequired)
		result.loadedShortfall += float(row.loadedShortfall)
		result.tankShortfall += float(row.tankShortfall)
	return result


static func _maintenance(state: Dictionary) -> Dictionary:
	var result: Dictionary = {"usageKnown": true, "expectedSupplies": 0.0, "looseSupplies": float(state.cargo.get("supplies", 0.0)), "conditionalFuel": false, "boats": []}
	for boat in state.fleet:
		if boat.get("sunk", false) or not str(boat.get("storedPort", "")).is_empty():continue
		var info: Dictionary = EquipmentDamage.inspect_owner(boat)
		var snap: Dictionary = info.get("snapshot", {})
		var damaged: bool = float(boat.hp) < float(boat.maxHp) or float(boat.water) > 0.0 or float(boat.fire) > 0.0 or float(boat.get("wounded", 0.0)) > 0.0 or float(boat.get("engine", 1.0)) < float(snap.get("engineHp", 1.0))
		for breach in boat.get("breaches", []):
			if float(breach.get("area", 0.0)) > 0.0:damaged = true
		for module in snap.get("installed", {}).values():
			if float(module.get("hp", 0.0)) < 1.0:damaged = true
		var known: bool = str(info.get("mode", "")) == "canonical" and not damaged
		var conditional_fuel: bool = float(boat.water) > 0.0 or absf(float(boat.get("vx", 0.0))) + absf(float(boat.get("vy", 0.0))) > 1.0
		result.conditionalFuel = bool(result.conditionalFuel) or conditional_fuel
		if not known:
			result.usageKnown = false
			result.expectedSupplies = null
		result.boats.append({"uid": str(boat.uid), "name": str(boat.get("name", "Boat")), "loadedSupplies": float(boat.supplies),
			"hp": float(boat.hp), "maxHp": float(boat.maxHp), "water": float(boat.water), "fire": float(boat.fire),
			"engine": float(boat.get("engine", 1.0)), "damaged": damaged,
			"wounded": float(boat.get("wounded", 0.0)), "breaches": boat.get("breaches", []).duplicate(true),
			"modules": snap.get("installed", {}).duplicate(true), "equipmentMode": str(info.get("mode", "invalid")),
			"policy": str(boat.get("policy", "balanced")), "repairPriority": str(snap.get("repairPriority", "auto")),
			"usageKnown": known, "expectedSupplies": 0.0 if known else null, "conditionalFuel": conditional_fuel})
	return result
