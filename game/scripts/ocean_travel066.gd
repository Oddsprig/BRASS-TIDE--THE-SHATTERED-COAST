extends RefCounted
## Pure bounded ocean movement/intel. Core alone owns clock, stores and fleets.
## Only default_data() reads a bundled definition; every operation is detached.
const World = preload("res://scripts/ocean_world064.gd")
const Navigation = preload("res://scripts/navigation.gd")
const DATA_PATH: String = "res://data/ocean_conditions066.json"
const DAY_SECONDS: float = 45.0
const SCALE: float = 10.0
const WEATHER_SECONDS: float = 15.0
const SIGHT_SECONDS: float = 30.0
const REPLAN_SECONDS: float = 3.0
const REPLAN_DISTANCE: float = 160.0
const MAX_SPLITS: int = 128
const EPS: float = 0.00000001


static func default_data() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return data if data is Dictionary else {}


static func empty_memory() -> Dictionary:
	return {"schema": 1, "intents": {}, "sightings": {}, "pursuits": {}}


static func same_world(a, b) -> bool:
	# Strict schema-one identities allow both JSON floats and runtime integers.
	return _identity_valid(a) and _identity_valid(b) and a.layer == b.layer and a.regionId == b.regionId


static func create(context064: Dictionary, seed: int, saved_memory = null, owner_ids: Array = ["player", "patrol-0"], now: float = 0.0) -> Dictionary:
	var data: Dictionary = default_data()
	if not _keys(data, ["schema", "zones"]) or not _number(data.schema) or data.schema != 1 or not data.zones is Array:
		return _failure("definitions", "Ocean condition definitions are unavailable.")
	return prepare(context064, data.zones, seed, saved_memory, owner_ids, now)


static func prepare(context064: Dictionary, zones: Array, seed: int, saved_memory, owner_ids: Array, now: float) -> Dictionary:
	# Do not duplicate context064: its two navigation graphs stay shared read-only.
	var context: Dictionary = {"world064Context": context064, "seed": seed, "zones": zones, "ownerIds": owner_ids}
	var error: String = _context_error(context)
	if not error.is_empty():return _failure("definitions", error)
	context["zones"] = _copy(zones)
	context["ownerIds"] = owner_ids.duplicate()
	var validated: Dictionary = validate_memory(context, empty_memory() if saved_memory == null else saved_memory, now)
	if not validated.ok:return validated
	var result: Dictionary = _success("Ocean runtime prepared; geometry remains shared.")
	result["context"] = context
	result["memory"] = validated.memory
	return result


static func validate_memory(context: Dictionary, memory, now: float) -> Dictionary:
	var error: String = _context_error(context)
	if error.is_empty():error = _memory_error(context, memory, now)
	if not error.is_empty():return _failure("memory", error)
	var result: Dictionary = _success("Ocean memory validated on a copy.")
	result["memory"] = _copy(memory)
	return result


static func conditions(context: Dictionary, location: Dictionary, now: float) -> Dictionary:
	var error: String = _context_error(context)
	if not error.is_empty():return _failure("definitions", error)
	if not _time(now):return _failure("time", "Conditions need finite nonnegative simulated seconds.")
	var prepared: Dictionary = World.prepare(location, context.world064Context, 0.0)
	if not prepared.ok:return _failure(str(prepared.code), str(prepared.message))
	var result: Dictionary = _success("Conditions sampled without advancing time.")
	result["condition"] = _condition(context, prepared.location, now)
	return result


static func zone_view(context: Dictionary, now: float) -> Array:
	if not _context_error(context).is_empty() or not _time(now):return []
	var result: Array = []
	for zone in context.zones:
		var copy: Dictionary = _copy(zone)
		copy["condition"] = _zone_condition(context, zone, now)
		result.append(copy)
	return result


static func command(context: Dictionary, actor: Dictionary, memory: Dictionary, action: Dictionary, now: float) -> Dictionary:
	var error: String = _context_error(context)
	if error.is_empty():error = _actor_error(context, actor)
	if error.is_empty():error = _memory_error(context, memory, now)
	if not error.is_empty():return _failure("command", error)
	var kind = action.get("kind")
	if not kind is String or kind not in ["divert", "investigate", "avoid", "resume"]:return _failure("command", "Choose divert, investigate, avoid or resume.")
	var goal: Dictionary = {}
	var target_id: String = ""
	if kind == "divert":
		if not _keys(action, ["kind", "target", "destination"]) or not _point_valid(action.target) or not action.destination is String:
			return _failure("command", "A diversion needs its explicit point and destination.")
		goal = {"world064": _copy(actor.location.world064), "target": _point(action.target), "destination": action.destination}
	elif kind == "resume":
		if not _keys(action, ["kind"]):return _failure("command", "Resume needs only its kind.")
		var previous: Dictionary = memory.intents.get(actor.ownerId, {})
		if previous.is_empty() or previous.kind == "route":return _failure("resume", "There is no interrupted voyage to resume.")
		goal = _copy(previous.returnGoal)
	else:
		if not _keys(action, ["kind", "targetId"]) or not action.targetId is String or action.targetId == actor.ownerId:
			return _failure("command", "Choose a dated contact belonging to another owner.")
		target_id = action.targetId
		var sight: Dictionary = memory.sightings.get(actor.ownerId, {}).get(target_id, {})
		if sight.is_empty() or now >= float(sight.expiresSecond):return _failure("sighting", "This contact has no unexpired last sighting.")
		if not same_world(sight.world064, actor.location.world064):return _failure("sighting", "The last sighting is on another chart.")
		var target: Dictionary = _escape(context, actor, sight.position) if kind == "avoid" else _point(sight.position)
		if target.is_empty():return _failure("route", "There is no safe escape course away from that sighting.")
		goal = {"world064": _copy(sight.world064), "target": target, "destination": ""}
	var plotted: Dictionary = _plot_goal(context, actor, goal)
	if not plotted.ok:return _failure(str(plotted.code), str(plotted.message))
	var copy: Dictionary = _copy(memory)
	copy.intents[actor.ownerId] = {"kind": "route" if kind == "resume" else kind, "targetId": target_id,
		"goal": goal, "returnGoal": {} if kind == "resume" else _original_goal(actor, memory), "lastPlanSecond": now}
	var result: Dictionary = _success("Voyage course updated from the current position.")
	result["location"] = _copy(plotted.location)
	result["memory"] = copy
	return result


static func step(context: Dictionary, actors: Array, relations: Array, memory: Dictionary, frame: Dictionary) -> Dictionary:
	var error: String = _context_error(context)
	if error.is_empty():error = _frame_error(context, actors, relations, frame)
	if error.is_empty():error = _memory_error(context, memory, float(frame.startSecond))
	if not error.is_empty():return _failure("step", error)
	# Three actors is the budget for this step, not a world population cap.
	# Callers schedule the watch; this does not simulate every fleet at 60Hz.
	var work: Array = _copy(actors) # At most three actors this step; never copy the context/nav.
	var intel: Dictionary = _copy(memory)
	var now: float = float(frame.startSecond)
	_expire(work, intel, now)
	if frame.watchDue:
		_observe(context, work, relations, intel, now)
		for owner_id in frame.decisionOwnerIds:
			_decide(context, _actor(work, owner_id), relations, intel, now)
	var traces: Array = []
	for actor in work:
		var traced: Dictionary = _trace(context, actor, float(frame.dt), now)
		if not traced.ok:return traced # No input was published or changed.
		traces.append(traced)
	var encounter: Dictionary = _encounter(work, relations, traces, now, float(frame.dt))
	var accepted: float = float(frame.dt) if encounter.is_empty() else float(encounter.atSecond) - now
	var moves: Array = []
	var sampled: Array = []
	for index in range(work.size()):
		var move: Dictionary = _clip(traces[index], accepted)
		moves.append(move)
		work[index]["location"] = move.location
		sampled.append(_condition(context, move.location, now + accepted))
	_expire(work, intel, now + accepted)
	if not encounter.is_empty():
		# Actual contact is a detection even between scheduled watches.
		var attacker: Dictionary = _actor(work, str(encounter.attackerId))
		var defender: Dictionary = _actor(work, str(encounter.defenderId))
		_capture(attacker, defender, intel, now + accepted)
		_capture(defender, attacker, intel, now + accepted)
		intel.pursuits[attacker.ownerId] = {"targetId": defender.ownerId, "phase": "engaged", "searchUntilSecond": now + accepted + SIGHT_SECONDS}
	var result: Dictionary = _success("Ocean movement and dated intelligence staged.")
	result["locations"] = moves
	result["memory"] = intel
	result["acceptedSeconds"] = accepted
	result["encounter"] = encounter
	result["conditions"] = sampled
	return result


static func transition_blocker(actors: Array, relations: Array, memory: Dictionary, pending_encounter: bool) -> String:
	if pending_encounter:return "Resolve the pending physical encounter before changing charts."
	if actors.size() > 3 or relations.size() > 6 or not memory.get("pursuits") is Dictionary:return "Ocean pursuit memory is invalid."
	for relation in relations:
		if not _keys(relation, ["observerId", "targetId", "hostile"]) or not relation.hostile is bool:return "Ocean pursuit relations are invalid."
		if not relation.hostile:continue
		var observer: Dictionary = _actor(actors, str(relation.get("observerId", "")))
		var target: Dictionary = _actor(actors, str(relation.get("targetId", "")))
		if observer.is_empty() or target.is_empty() or not _can_pursue(observer):continue
		var pursuit = memory.pursuits.get(observer.ownerId, {})
		if not pursuit is Dictionary:return "Ocean pursuit memory is invalid."
		if pursuit.get("targetId") == target.ownerId and pursuit.get("phase") in ["tracking", "searching", "engaged"]:
			return "A capable hostile fleet is still pursuing its dated contact. Sail clear or resolve the encounter."
	return ""


static func forecast(context: Dictionary, legs: Array, base_speed: float, now: float) -> Dictionary:
	var error: String = _context_error(context)
	if not error.is_empty():return _failure("forecast", error)
	if not _time(now) or not is_finite(base_speed) or base_speed <= 0.0 or legs.size() > 16:
		return _failure("forecast", "Forecast needs finite positive speed, time and at most sixteen itinerary legs.")
	var times: Array = []
	var sampled: Array = []
	var expected: float = 0.0
	var conservative: float = 0.0
	for leg in legs:
		if not leg is Dictionary or not leg.get("kind") is String or not leg.get("layer") is String or leg.kind not in ["sail", "transition"] or leg.layer not in ["home", "local", "ocean"]:
			return _failure("forecast", "Use existing validated voyage legs.")
		if not _number(leg.get("seconds")) or float(leg.seconds) < 0.0 or not _number(leg.get("physicalDistance")) or float(leg.physicalDistance) < 0.0:
			return _failure("forecast", "Voyage leg durations and distances must be finite and nonnegative.")
		var row: Dictionary = {"expectedSeconds": float(leg.seconds), "conservativeSeconds": float(leg.seconds)}
		if leg.kind == "sail" and leg.layer == "ocean":
			var projected: Dictionary = _forecast_leg(context, leg, base_speed, now)
			if not projected.ok:return projected
			row = projected.time
			for condition in projected.conditions:
				if not sampled.any(func(item):return item.zoneId == condition.zoneId):sampled.append(condition)
		times.append(row)
		expected += float(row.expectedSeconds)
		conservative += float(row.conservativeSeconds)
	if not is_finite(expected) or not is_finite(conservative):return _failure("forecast", "Forecast duration overflowed; no estimate was published.")
	var result: Dictionary = _success("Current-held and slowest-weather route estimates ready.")
	result["legTimes"] = times
	result["expectedSeconds"] = expected
	result["conservativeSeconds"] = conservative
	result["validUntilSecond"] = _valid_until(now)
	result["conditions"] = sampled
	result["assumptions"] = ["Expected ocean time holds today's weather phase and directed currents for each route segment.",
		"Conservative ocean time uses each zone's slowest authored weather with the same directed current; it excludes the separate two-day reserve.",
		"Weather changes every 15 simulated seconds. Forecast validity is a refresh deadline, not a guaranteed arrival or immunity from contacts.",
		"Coastal speed and every physical route distance remain unchanged; no stops, encounters or future damage are forecast."]
	return result


static func _context_error(context: Dictionary) -> String:
	if not _keys(context, ["world064Context", "seed", "zones", "ownerIds"]) or not context.world064Context is Dictionary:
		return "Supply the prepared shared ocean runtime context."
	var probe: Dictionary = World.prepare(_location({"x": 2400.0, "y": 1400.0}), context.world064Context, 0.0)
	if not probe.ok:return str(probe.message)
	var ocean: Dictionary = context.world064Context.ocean
	var generated: bool = context.world064Context.get("atlasSchema", 1) == 2
	if ocean.width != (12800.0 if generated else 4800.0) or ocean.height != (8400.0 if generated else 2800.0) or ocean.localUnitsPerUnit != SCALE:return "The ocean model requires canonical legacy/sector bounds and ten-to-one physical scale."
	if not _number(context.seed) or float(context.seed) != floorf(float(context.seed)):
		return "Ocean weather needs an integer campaign seed."
	# Per prepared context, not the campaign roster: one player and two owners.
	if not context.ownerIds is Array or context.ownerIds.is_empty() or context.ownerIds.size() > 3:
		return "Admit one player and at most two existing owners."
	var ids: Dictionary = {}
	for owner_id in context.ownerIds:
		if not _text(owner_id) or ids.has(owner_id):return "Admitted ocean owner IDs must be distinct strings."
		ids[owner_id] = true
	if not ids.has("player"):return "The admitted ocean actors must include the player."
	if not context.zones is Array or context.zones.size() > 6:return "At most six authored ocean zones are supported."
	var zones: Array = context.zones
	var zone_ids: Dictionary = {}
	for index in range(zones.size()):
		var zone = zones[index]
		if not _keys(zone, ["id", "name", "kind", "rect", "current", "weather", "phaseOffset"]):return "A zone needs its explicit chart and weather fields."
		if not _text(zone.id) or zone_ids.has(zone.id) or not _text(zone.name) or not zone.kind is String or zone.kind not in ["current", "weather"]:
			return "Zone IDs, names and kinds must be distinct supported strings."
		zone_ids[zone.id] = true
		if not _keys(zone.rect, ["x", "y", "width", "height"]):return "A zone needs one bounded ocean rectangle."
		for key in ["x", "y", "width", "height"]:
			if not _number(zone.rect[key]):return "Zone rectangles must be finite."
		if zone.rect.x < 0.0 or zone.rect.y < 0.0 or zone.rect.width <= 0.0 or zone.rect.height <= 0.0 or zone.rect.x + zone.rect.width > ocean.width or zone.rect.y + zone.rect.height > ocean.height:
			return "Zone rectangles must stay inside the existing ocean."
		if not _point_valid(zone.current) or _length(zone.current) > 20.0 + EPS:return "Directed currents must be finite and at most twenty local units per second."
		if not _number(zone.phaseOffset) or float(zone.phaseOffset) != floorf(float(zone.phaseOffset)) or absf(float(zone.phaseOffset)) > 1000.0:
			return "Weather phase offsets must be small integers."
		if not zone.weather is Array or zone.weather.size() != 2:return "Each zone needs exactly two deterministic weather phases."
		for weather in zone.weather:
			if not _keys(weather, ["id", "label", "speedFactor", "visibilityFactor"]) or not _text(weather.id) or not _text(weather.label):return "Weather needs its ID, label and two factors."
			if not _number(weather.speedFactor) or weather.speedFactor < 0.65 or weather.speedFactor > 1.0 or not _number(weather.visibilityFactor) or weather.visibilityFactor < 0.35 or weather.visibilityFactor > 1.0:
				return "Weather speed/visibility factors exceed the bounded chart model."
		for other_index in range(index):
			var other: Dictionary = zones[other_index].rect
			if maxf(zone.rect.x, other.x) < minf(zone.rect.x + zone.rect.width, other.x + other.width) and maxf(zone.rect.y, other.y) < minf(zone.rect.y + zone.rect.height, other.y + other.height):
				return "Ocean condition rectangles must not overlap."
	return ""


static func _actor_error(context: Dictionary, actor) -> String:
	if not _keys(actor, ["ownerId", "location", "baseSpeed", "clearance", "canMove", "canIntercept", "detectionRange", "interceptRange", "boats"]):
		return "An actor needs exactly its spatial, capability and render snapshot fields."
	if not actor.ownerId is String or actor.ownerId not in context.ownerIds or not actor.location is Dictionary:return "An actor must reference an admitted physical owner and location."
	if not _keys(actor.location, ["world064", "position", "heading", "path", "destination"]) or not _identity_valid(actor.location.world064) or not _point_valid(actor.location.position) or not _number(actor.location.heading) or not actor.location.destination is String:
		return "Actor locations must contain only the five plain 064 spatial fields."
	for key in ["baseSpeed", "clearance", "detectionRange", "interceptRange"]:
		if not _number(actor[key]) or float(actor[key]) < 0.0:return "Actor speeds, clearance and ranges must be finite and nonnegative."
	if not actor.canMove is bool or not actor.canIntercept is bool:return "Actor capabilities must be booleans."
	if not _boats_valid(actor.boats):return "Actor artwork must contain bounded detached render DTOs only."
	if not actor.location.get("path") is Array or actor.location.path.size() > 128:return "Actor routes exceed the bounded waypoint budget."
	if actor.location.get("world064", {}).get("layer") == "ocean" and actor.location.path.size() > 8:return "Ocean courses support at most eight waypoints."
	for point in actor.location.path:
		if not _point_valid(point):return "Actor waypoints must be finite plain points."
	var prepared: Dictionary = World.prepare(actor.location, context.world064Context, float(actor.clearance))
	return "" if prepared.ok else str(prepared.message)


static func _frame_error(context: Dictionary, actors: Array, relations: Array, frame: Dictionary) -> String:
	if actors.size() > 3 or relations.size() > 6:return "Only the player and two actual enrolled owners may move or sense."
	if not _keys(frame, ["startSecond", "dt", "watchDue", "decisionOwnerIds"]) or not _time(frame.startSecond) or not _number(frame.dt) or frame.dt < 0.0 or frame.dt > 4.0 or not is_finite(float(frame.startSecond) + float(frame.dt)):
		return "A frame needs finite simulated time and dt between zero and four seconds."
	if not frame.watchDue is bool or not frame.decisionOwnerIds is Array or frame.decisionOwnerIds.size() > 2:return "Supply one scheduled watch flag and at most two decision IDs."
	var ids: Dictionary = {}
	for actor in actors:
		var error: String = _actor_error(context, actor)
		if not error.is_empty():return error
		if ids.has(actor.ownerId):return "An actor owner cannot move twice in a frame."
		ids[actor.ownerId] = true
	var decisions: Dictionary = {}
	for owner_id in frame.decisionOwnerIds:
		if not owner_id is String or owner_id == "player" or not ids.has(owner_id) or decisions.has(owner_id):return "Decision IDs must be distinct admitted active NPC actors."
		decisions[owner_id] = true
	var pairs: Dictionary = {}
	for relation in relations:
		if not _keys(relation, ["observerId", "targetId", "hostile"]) or not relation.hostile is bool:return "A relation needs two actor IDs and explicit hostility."
		if not relation.observerId is String or not relation.targetId is String or not ids.has(relation.observerId) or not ids.has(relation.targetId) or relation.observerId == relation.targetId:
			return "Directed sensing must reference distinct active actors."
		var key: String = relation.observerId + ":" + relation.targetId
		if pairs.has(key):return "Directed relations must not repeat."
		pairs[key] = true
	return ""


static func _memory_error(context: Dictionary, memory, now: float) -> String:
	if not _time(now) or not _keys(memory, ["schema", "intents", "sightings", "pursuits"]) or not _number(memory.schema) or memory.schema != 1:
		return "Present ocean memory needs schema one and all three dictionaries."
	for group in ["intents", "sightings", "pursuits"]:
		if not memory[group] is Dictionary or memory[group].size() > 3:return "Ocean memory groups must contain at most three admitted owners."
		for owner_id in memory[group]:
			if not owner_id is String or owner_id not in context.ownerIds:return "Ocean memory references an unknown owner."
	for owner_id in memory.intents:
		var intent = memory.intents[owner_id]
		if not _keys(intent, ["kind", "targetId", "goal", "returnGoal", "lastPlanSecond"]) or not intent.kind is String or intent.kind not in ["route", "divert", "investigate", "avoid", "pursue"]:
			return "A saved intent needs its explicit bounded course fields."
		if not intent.targetId is String or (not intent.targetId.is_empty() and (intent.targetId == owner_id or intent.targetId not in context.ownerIds)):
			return "Saved intent targets must reference another admitted owner."
		if intent.kind in ["investigate", "avoid", "pursue"] and intent.targetId.is_empty():return "A contact intent needs its target owner."
		if not _time(intent.lastPlanSecond) or float(intent.lastPlanSecond) > now + EPS:return "Saved plans cannot be dated in the future."
		if not _goal_valid(context, intent.goal) or not _goal_valid(context, intent.returnGoal):return "Saved intent goals must retain supported safe chart targets."
	for observer_id in memory.sightings:
		var sightings = memory.sightings[observer_id]
		if not sightings is Dictionary or sightings.size() > 2:return "One observer can retain at most two admitted contacts."
		for target_id in sightings:
			if not target_id is String or target_id == observer_id or target_id not in context.ownerIds:return "Saved sightings must reference another admitted owner."
			var sight = sightings[target_id]
			if not _keys(sight, ["world064", "position", "velocity", "seenSecond", "expiresSecond", "heading", "boats"]):return "Saved sightings need position, dates and frozen heading/artwork."
			if not _identity_valid(sight.world064) or not _point_valid(sight.position) or not _point_valid(sight.velocity) or not _number(sight.heading) or not _boats_valid(sight.boats):return "Saved sighting spatial/artwork data is invalid."
			if not _time(sight.seenSecond) or float(sight.seenSecond) > now + EPS or not _time(sight.expiresSecond) or absf(float(sight.expiresSecond) - float(sight.seenSecond) - SIGHT_SECONDS) > EPS:
				return "Sighting dates must be actual past observations with a thirty-second expiry."
			var prepared: Dictionary = World.prepare({"world064": sight.world064, "position": sight.position, "heading": sight.heading, "path": [], "destination": ""}, context.world064Context, 0.0)
			if not prepared.ok:return "A saved sighting lies outside its actual navigable chart."
	for owner_id in memory.pursuits:
		var pursuit = memory.pursuits[owner_id]
		if not _keys(pursuit, ["targetId", "phase", "searchUntilSecond"]) or not pursuit.targetId is String or pursuit.targetId == owner_id or pursuit.targetId not in context.ownerIds or not pursuit.phase is String or pursuit.phase not in ["tracking", "searching", "engaged"]:
			return "Saved pursuits need an admitted target and actual pursuit phase."
		if not _time(pursuit.searchUntilSecond) or float(pursuit.searchUntilSecond) > now + SIGHT_SECONDS + EPS:return "A saved pursuit has an invalid search deadline."
		var sight: Dictionary = memory.sightings.get(owner_id, {}).get(pursuit.targetId, {})
		if sight.is_empty() or absf(float(pursuit.searchUntilSecond) - float(sight.expiresSecond)) > EPS:return "A pursuit must retain its matching dated sighting."
	return ""


static func _boats_valid(boats) -> bool:
	if not boats is Array or boats.size() > 36:return false
	var ids: Dictionary = {}
	for boat in boats:
		if not _allowed(boat, ["uid", "spec", "engineModule"], ["uid", "spec"]) or not _text(boat.uid) or ids.has(boat.uid):return false
		ids[boat.uid] = true
		if boat.has("engineModule") and not boat.engineModule is String:return false
		var spec = boat.spec
		if not _allowed(spec, ["id", "role", "size", "tier", "faction", "weapon", "fuelUse", "weaponMounts"], ["id"]) or not _text(spec.id):return false
		for key in ["role", "faction", "weapon"]:
			if spec.has(key) and not spec[key] is String:return false
		for key in ["size", "tier", "fuelUse"]:
			if spec.has(key) and (not _number(spec[key]) or float(spec[key]) < 0.0):return false
		if not spec.get("weaponMounts", []) is Array or spec.get("weaponMounts", []).size() > 16:return false
		for mount in spec.get("weaponMounts", []):
			if not _allowed(mount, ["id", "moduleId", "kind", "size", "x", "y", "angle"], ["id"]) or not _text(mount.id):return false
			for key in ["moduleId", "kind"]:
				if mount.has(key) and not mount[key] is String:return false
			for key in ["x", "y", "angle"]:
				if mount.has(key) and not _number(mount[key]):return false
			# Brackets select the DTO field instead of Dictionary's size method.
			if mount.has("size") and not (_number(mount["size"]) or mount["size"] is String):return false
	return true


static func _goal_valid(context: Dictionary, goal) -> bool:
	if not goal is Dictionary:return false
	if goal.is_empty():return true
	if not _keys(goal, ["world064", "target", "destination"]) or not _identity_valid(goal.world064) or not _point_valid(goal.target) or not goal.destination is String:return false
	var prepared: Dictionary = World.prepare({"world064": goal.world064, "position": goal.target, "heading": 0.0, "path": [], "destination": goal.destination}, context.world064Context, 0.0)
	return prepared.ok


static func _identity_valid(identity) -> bool:
	# This is syntax only. Actual actors, goals and sightings still pass World.prepare
	# against the admitted context, which rejects fabricated region membership.
	return _keys(identity, ["schema", "layer", "regionId"]) and _number(identity.schema) and identity.schema == 1 and identity.layer is String and identity.regionId is String and ((identity.layer == "ocean" and identity.regionId == World.OCEAN) or (identity.layer == "home" and identity.regionId == World.HOME) or (identity.layer == "local" and World.local_id_valid(identity.regionId)))


static func _condition(context: Dictionary, location: Dictionary, now: float, direction: Dictionary = {}) -> Dictionary:
	if location.world064.layer != "ocean":return _clear_condition(now, "coastal", "Unchanged coastal conditions")
	var point: Dictionary = location.position
	if not direction.is_empty():point = {"x": float(point.x) + float(direction.x) * EPS, "y": float(point.y) + float(direction.y) * EPS}
	for zone in context.zones:
		var rect: Dictionary = zone.rect
		if point.x >= rect.x and point.x < rect.x + rect.width and point.y >= rect.y and point.y < rect.y + rect.height:return _zone_condition(context, zone, now)
	return _clear_condition(now, "open", "Open water")


static func _clear_condition(now: float, zone_id: String, label: String) -> Dictionary:
	return {"zoneId": zone_id, "label": label, "current": {"x": 0.0, "y": 0.0}, "speedFactor": 1.0, "visibilityFactor": 1.0, "validUntilSecond": _valid_until(now)}


static func _zone_condition(context: Dictionary, zone: Dictionary, now: float) -> Dictionary:
	var phase: int = posmod(posmod(int(context.seed), 2) + int(floorf((now + EPS) / WEATHER_SECONDS)) + int(zone.phaseOffset), 2)
	var weather: Dictionary = zone.weather[phase]
	return {"zoneId": zone.id, "label": zone.name + ": " + weather.label, "current": _point(zone.current),
		"speedFactor": float(weather.speedFactor), "visibilityFactor": float(weather.visibilityFactor), "validUntilSecond": _valid_until(now)}


static func _valid_until(now: float) -> float:
	return (floorf((now + EPS) / WEATHER_SECONDS) + 1.0) * WEATHER_SECONDS


static func _speed(base: float, condition: Dictionary, direction: Dictionary) -> float:
	if base <= 0.0:return 0.0
	var current: float = float(condition.current.x) * float(direction.x) + float(condition.current.y) * float(direction.y)
	return clampf(base * float(condition.speedFactor) + current, 0.25 * base, 1.5 * base)


static func _spatial_cut(context: Dictionary, point: Dictionary, direction: Dictionary, length: float) -> float:
	var result: float = length
	for zone in context.zones:
		var rect: Dictionary = zone.rect
		if absf(float(direction.x)) > EPS:
			for edge in [float(rect.x), float(rect.x) + float(rect.width)]:
				var along: float = (edge - float(point.x)) / float(direction.x)
				var cross: float = float(point.y) + float(direction.y) * along
				if along > EPS and along < result and cross >= float(rect.y) - EPS and cross <= float(rect.y) + float(rect.height) + EPS:result = along
		if absf(float(direction.y)) > EPS:
			for edge in [float(rect.y), float(rect.y) + float(rect.height)]:
				var along: float = (edge - float(point.y)) / float(direction.y)
				var cross: float = float(point.x) + float(direction.x) * along
				if along > EPS and along < result and cross >= float(rect.x) - EPS and cross <= float(rect.x) + float(rect.width) + EPS:result = along
	return result


static func _trace(context: Dictionary, actor: Dictionary, dt: float, now: float) -> Dictionary:
	var loc: Dictionary = _copy(actor.location)
	var initial: Dictionary = _copy(loc)
	var segments: Array = []
	var elapsed: float = 0.0
	var distance: float = 0.0
	var index: int = 0
	var scale: float = SCALE if loc.world064.layer == "ocean" else 1.0
	while elapsed < dt and index < loc.path.size() and actor.canMove and float(actor.baseSpeed) > 0.0:
		if segments.size() >= MAX_SPLITS:return _failure("budget", "Movement exceeded 128 spatial/weather splits; the entire frame was refused.")
		var target: Dictionary = loc.path[index]
		var length: float = _distance(loc.position, target)
		if length == 0.0:
			index += 1
			continue
		var direction: Dictionary = {"x": (float(target.x) - float(loc.position.x)) / length, "y": (float(target.y) - float(loc.position.y)) / length}
		var condition: Dictionary = _condition(context, loc, now + elapsed, direction)
		var speed: float = _speed(float(actor.baseSpeed), condition, direction)
		if not is_finite(speed) or not is_finite(speed * dt):return _failure("step", "Movement overflowed its finite speed budget.")
		var cut: float = _spatial_cut(context, loc.position, direction, length) if scale == SCALE else length
		var seconds: float = minf(dt - elapsed, cut * scale / speed)
		if scale == SCALE:seconds = minf(seconds, _valid_until(now + elapsed) - now - elapsed)
		if seconds <= 0.0 or not is_finite(seconds):return _failure("step", "Movement could not consume a positive bounded interval.")
		var moved: float = minf(length, seconds * speed / scale)
		var complete: bool = moved >= length - EPS
		var endpoint: Dictionary = _point(target) if complete else {"x": float(loc.position.x) + float(direction.x) * moved, "y": float(loc.position.y) + float(direction.y) * moved}
		var heading: float = atan2(float(direction.y), float(direction.x))
		segments.append({"from": _point(loc.position), "to": endpoint, "t0": elapsed, "t1": elapsed + seconds, "heading": heading, "completed": complete, "index": index})
		loc["position"] = endpoint
		loc["heading"] = heading
		distance += _distance(segments[-1].from, endpoint) * scale
		elapsed += seconds
		if complete:index += 1
	if elapsed < dt or segments.is_empty():
		if segments.size() >= MAX_SPLITS:return _failure("budget", "Movement exceeded its bounded trace budget; the entire frame was refused.")
		segments.append({"from": _point(loc.position), "to": _point(loc.position), "t0": elapsed, "t1": dt, "heading": float(loc.heading), "completed": false, "index": index})
	loc["path"] = _copy(loc.path.slice(index))
	var move: Dictionary = {"ownerId": actor.ownerId, "location": loc, "distance": distance, "moving": distance > 0.0,
		"arrived": not initial.path.is_empty() and loc.path.is_empty(), "reason": "" if actor.canMove and actor.baseSpeed > 0.0 else "No powered movement capability."}
	return {"ok": true, "move": move, "segments": segments, "initial": initial, "scale": scale, "dt": dt}


static func _clip(trace: Dictionary, accepted: float) -> Dictionary:
	if accepted >= float(trace.dt):return _copy(trace.move)
	var result: Dictionary = _copy(trace.move)
	var loc: Dictionary = _copy(trace.initial)
	var consumed: int = 0
	var distance: float = 0.0
	for segment in trace.segments:
		if accepted < float(segment.t0):break
		var end: float = minf(accepted, float(segment.t1))
		var point: Dictionary = _segment_point(segment, end)
		distance += _distance(segment.from, point) * float(trace.scale)
		loc["position"] = point
		if end > float(segment.t0):loc["heading"] = segment.heading
		consumed = maxi(consumed, int(segment.index) + (1 if segment.completed and end >= float(segment.t1) else 0))
		if end >= accepted:break
	loc["path"] = _copy(loc.path.slice(consumed))
	result["location"] = loc
	result["distance"] = distance
	result["moving"] = distance > 0.0
	result["arrived"] = not trace.initial.path.is_empty() and loc.path.is_empty()
	return result


static func _encounter(actors: Array, relations: Array, traces: Array, now: float, dt: float) -> Dictionary:
	# The player may watch. Two hostile owners on the same ocean chart still meet.
	var result: Dictionary = {}
	var earliest: float = dt + 1.0
	for relation in relations:
		if not relation.hostile:continue
		var a: int = _actor_index(actors, str(relation.observerId))
		var b: int = _actor_index(actors, str(relation.targetId))
		if not actors[a].canIntercept or not same_world(actors[a].location.world064, actors[b].location.world064) or actors[a].location.world064.layer != "ocean":continue
		var hit: float = _sweep(traces[a].segments, traces[b].segments, float(actors[a].interceptRange) / SCALE)
		if hit < 0.0 or hit > dt:continue
		if hit > earliest + EPS or (absf(hit - earliest) <= EPS and not result.is_empty() and str(actors[a].ownerId) >= str(result.attackerId)):continue
		earliest = hit
		var watched: Dictionary = traces[a]
		if actors[b].ownerId == "player":watched = traces[b]
		result = {"attackerId": actors[a].ownerId, "defenderId": actors[b].ownerId, "world064": _copy(actors[a].location.world064),
			"position": _clip(watched, hit).location.position, "atSecond": now + hit}
	return result


static func _sweep(a: Array, b: Array, radius: float) -> float:
	var ai: int = 0
	var bi: int = 0
	while ai < a.size() and bi < b.size():
		var first: Dictionary = a[ai]
		var second: Dictionary = b[bi]
		var low: float = maxf(float(first.t0), float(second.t0))
		var high: float = minf(float(first.t1), float(second.t1))
		if high >= low:
			var p: Dictionary = _segment_point(first, low)
			var q: Dictionary = _segment_point(second, low)
			var pv: Dictionary = _segment_velocity(first)
			var qv: Dictionary = _segment_velocity(second)
			var rx: float = float(p.x) - float(q.x)
			var ry: float = float(p.y) - float(q.y)
			var vx: float = float(pv.x) - float(qv.x)
			var vy: float = float(pv.y) - float(qv.y)
			var constant: float = rx * rx + ry * ry - radius * radius
			if constant <= 0.0:return low
			var quadratic: float = vx * vx + vy * vy
			var linear: float = 2.0 * (rx * vx + ry * vy)
			var discriminant: float = linear * linear - 4.0 * quadratic * constant
			if quadratic > 0.0 and discriminant >= 0.0:
				var root: float = (-linear - sqrt(discriminant)) / (2.0 * quadratic)
				if root >= -EPS and root <= high - low + EPS:return clampf(low + root, low, high)
		if first.t1 <= second.t1:ai += 1
		if second.t1 <= first.t1:bi += 1
	return -1.0


static func _segment_point(segment: Dictionary, at: float) -> Dictionary:
	var width: float = float(segment.t1) - float(segment.t0)
	var fraction: float = clampf((at - float(segment.t0)) / width, 0.0, 1.0) if width > 0.0 else 0.0
	return {"x": lerpf(float(segment.from.x), float(segment.to.x), fraction), "y": lerpf(float(segment.from.y), float(segment.to.y), fraction)}


static func _segment_velocity(segment: Dictionary) -> Dictionary:
	var width: float = float(segment.t1) - float(segment.t0)
	return {"x": (float(segment.to.x) - float(segment.from.x)) / width, "y": (float(segment.to.y) - float(segment.from.y)) / width} if width > 0.0 else {"x": 0.0, "y": 0.0}


static func _observe(context: Dictionary, actors: Array, relations: Array, memory: Dictionary, now: float) -> void:
	for relation in relations:
		var observer: Dictionary = _actor(actors, str(relation.observerId))
		var target: Dictionary = _actor(actors, str(relation.targetId))
		if not same_world(observer.location.world064, target.location.world064):continue
		var scale: float = SCALE if observer.location.world064.layer == "ocean" else 1.0
		var first: Dictionary = _condition(context, observer.location, now)
		var second: Dictionary = _condition(context, target.location, now)
		var visible_range: float = float(observer.detectionRange) * minf(float(first.visibilityFactor), float(second.visibilityFactor))
		if _distance(observer.location.position, target.location.position) * scale <= visible_range:_capture(observer, target, memory, now)


static func _capture(observer: Dictionary, target: Dictionary, memory: Dictionary, now: float) -> void:
	var by_observer: Dictionary = memory.sightings.get(observer.ownerId, {})
	var previous: Dictionary = by_observer.get(target.ownerId, {})
	var velocity: Dictionary = {"x": 0.0, "y": 0.0}
	if not previous.is_empty() and same_world(previous.world064, target.location.world064) and now - float(previous.seenSecond) >= EPS:
		var scale: float = SCALE if target.location.world064.layer == "ocean" else 1.0
		var elapsed: float = now - float(previous.seenSecond)
		velocity = {"x": (float(target.location.position.x) - float(previous.position.x)) * scale / elapsed,
			"y": (float(target.location.position.y) - float(previous.position.y)) * scale / elapsed}
	by_observer[target.ownerId] = {"world064": _copy(target.location.world064), "position": _point(target.location.position),
		"velocity": velocity, "seenSecond": now, "expiresSecond": now + SIGHT_SECONDS,
		"heading": float(target.location.heading), "boats": _copy(target.boats)}
	memory.sightings[observer.ownerId] = by_observer
	var pursuit: Dictionary = memory.pursuits.get(observer.ownerId, {})
	if pursuit.get("targetId") == target.ownerId:
		# A selected decision may be deferred; sensing still refreshes its one
		# dated search deadline, without a second cache or an unscheduled replan.
		pursuit["searchUntilSecond"] = now + SIGHT_SECONDS
		if pursuit.phase != "engaged":pursuit["phase"] = "tracking"


static func _expire(actors: Array, memory: Dictionary, now: float) -> void:
	for observer_id in memory.sightings.keys():
		var sights: Dictionary = memory.sightings[observer_id]
		for target_id in sights.keys():
			if now >= float(sights[target_id].expiresSecond):sights.erase(target_id)
		if sights.is_empty():memory.sightings.erase(observer_id)
	for owner_id in memory.pursuits.keys():
		var pursuit: Dictionary = memory.pursuits[owner_id]
		var actor: Dictionary = _actor(actors, owner_id)
		if now >= float(pursuit.searchUntilSecond) or (not actor.is_empty() and not _can_pursue(actor)):
			memory.pursuits.erase(owner_id)


static func _decide(context: Dictionary, actor: Dictionary, relations: Array, memory: Dictionary, now: float) -> void:
	var sight: Dictionary = {}
	var target_id: String = ""
	var previous: Dictionary = memory.intents.get(actor.ownerId, {})
	for relation in relations:
		if relation.observerId != actor.ownerId or not relation.hostile:continue
		var candidate: Dictionary = memory.sightings.get(actor.ownerId, {}).get(relation.targetId, {})
		if not candidate.is_empty() and same_world(candidate.world064, actor.location.world064) and now < float(candidate.expiresSecond):
			sight = candidate
			target_id = relation.targetId
			break
	if sight.is_empty():
		# A chart change or an omitted relation cannot erase an unexpired
		# pursuit. Only _expire (time/incapacity) or Core settlement releases it.
		if memory.pursuits.has(actor.ownerId):return
		if not previous.is_empty() and previous.kind in ["pursue", "avoid"]:
			var resumed: Dictionary = _plot_goal(context, actor, previous.returnGoal)
			if resumed.ok:
				actor["location"] = resumed.location
				memory.intents[actor.ownerId] = {"kind": "route", "targetId": "", "goal": _copy(previous.returnGoal), "returnGoal": {}, "lastPlanSecond": now}
		memory.pursuits.erase(actor.ownerId)
		return
	var capable: bool = _can_pursue(actor)
	var visible: bool = absf(float(sight.seenSecond) - now) <= EPS
	var kind: String = "pursue" if capable else "avoid"
	var point: Dictionary = _point(sight.position)
	if capable:
		memory.pursuits[actor.ownerId] = {"targetId": target_id, "phase": "tracking" if visible else "searching", "searchUntilSecond": float(sight.expiresSecond)}
		if visible:
			var scale: float = SCALE if actor.location.world064.layer == "ocean" else 1.0
			point = _clamp_ocean(context, actor, {"x": float(point.x) + float(sight.velocity.x) * REPLAN_SECONDS / scale,
				"y": float(point.y) + float(sight.velocity.y) * REPLAN_SECONDS / scale})
	else:
		memory.pursuits.erase(actor.ownerId)
		point = _escape(context, actor, sight.position)
		if point.is_empty():return
	if not previous.is_empty():
		if now - float(previous.lastPlanSecond) < REPLAN_SECONDS:return
		var old_goal: Dictionary = previous.goal
		var scale: float = SCALE if actor.location.world064.layer == "ocean" else 1.0
		if previous.kind == kind and previous.targetId == target_id and not old_goal.is_empty() and same_world(old_goal.world064, actor.location.world064) and _distance(old_goal.target, point) * scale < REPLAN_DISTANCE and not actor.location.path.is_empty():return
	var goal: Dictionary = {"world064": _copy(actor.location.world064), "target": point, "destination": ""}
	var plotted: Dictionary = _plot_goal(context, actor, goal)
	if not plotted.ok:return
	memory.intents[actor.ownerId] = {"kind": kind, "targetId": target_id, "goal": goal,
		"returnGoal": _original_goal(actor, memory), "lastPlanSecond": now}
	actor["location"] = plotted.location


static func _original_goal(actor: Dictionary, memory: Dictionary) -> Dictionary:
	var previous: Dictionary = memory.intents.get(actor.ownerId, {})
	if not previous.is_empty() and previous.kind != "route":return _copy(previous.returnGoal)
	var loc: Dictionary = actor.location
	if loc.path.is_empty() and str(loc.destination).is_empty():return {}
	return {"world064": _copy(loc.world064), "target": _point(loc.position if loc.path.is_empty() else loc.path[-1]), "destination": loc.destination}


static func _plot_goal(context: Dictionary, actor: Dictionary, goal: Dictionary) -> Dictionary:
	if goal.is_empty():
		var stopped: Dictionary = _copy(actor.location)
		stopped["path"] = []
		stopped["destination"] = ""
		return {"ok": true, "location": stopped}
	if not same_world(goal.world064, actor.location.world064):return _failure("resume", "The saved voyage goal is on another chart; plot the matching approach explicitly.")
	return World.plot(context.world064Context, actor.location, goal.target, str(goal.destination), float(actor.clearance))


static func _escape(context: Dictionary, actor: Dictionary, sight: Dictionary) -> Dictionary:
	var position: Dictionary = actor.location.position
	var dx: float = float(position.x) - float(sight.x)
	var dy: float = float(position.y) - float(sight.y)
	var length: float = sqrt(dx * dx + dy * dy)
	if length <= EPS:
		dx = -cos(float(actor.location.heading))
		dy = -sin(float(actor.location.heading))
		length = 1.0
	var scale: float = SCALE if actor.location.world064.layer == "ocean" else 1.0
	var travel: float = maxf(600.0, float(actor.detectionRange) * 1.25) / scale
	var target: Dictionary = _clamp_ocean(context, actor, {"x": float(position.x) + dx * travel / length, "y": float(position.y) + dy * travel / length})
	if _distance(target, sight) <= _distance(position, sight) + EPS:return {}
	return target


static func _clamp_ocean(context: Dictionary, actor: Dictionary, point: Dictionary) -> Dictionary:
	if actor.location.world064.layer != "ocean":return point
	var margin: float = Navigation.hull_clearance(float(actor.clearance)) / SCALE
	return {"x": clampf(float(point.x), margin, float(context.world064Context.ocean.width) - margin),
		"y": clampf(float(point.y), margin, float(context.world064Context.ocean.height) - margin)}


static func _forecast_leg(context: Dictionary, leg: Dictionary, speed: float, now: float) -> Dictionary:
	if not _point_valid(leg.get("from")) or not _point_valid(leg.get("to")) or not leg.get("path") is Array or leg.path.size() > 8:
		return _failure("forecast", "An ocean forecast needs at most eight finite path points.")
	var position: Dictionary = _point(leg.from)
	var expected: float = 0.0
	var conservative: float = 0.0
	var distance: float = 0.0
	var splits: int = 0
	var sampled: Array = []
	for target in leg.path:
		if not _point_valid(target):return _failure("forecast", "An ocean forecast path contains an invalid point.")
		while _distance(position, target) > EPS:
			if splits >= MAX_SPLITS:return _failure("budget", "The entire forecast exceeded its bounded spatial-split budget.")
			var length: float = _distance(position, target)
			var direction: Dictionary = {"x": (float(target.x) - float(position.x)) / length, "y": (float(target.y) - float(position.y)) / length}
			var cut: float = _spatial_cut(context, position, direction, length)
			var condition: Dictionary = _condition(context, _location(position), now, direction)
			var slow: Dictionary = _copy(condition)
			for zone in context.zones:
				if zone.id == condition.zoneId:
					for weather in zone.weather:slow["speedFactor"] = minf(float(slow.speedFactor), float(weather.speedFactor))
			expected += cut * SCALE / _speed(speed, condition, direction)
			conservative += cut * SCALE / _speed(speed, slow, direction)
			distance += cut * SCALE
			if not sampled.any(func(item):return item.zoneId == condition.zoneId):sampled.append(condition)
			position = _point(target) if cut >= length - EPS else {"x": float(position.x) + float(direction.x) * cut, "y": float(position.y) + float(direction.y) * cut}
			splits += 1
	if _distance(position, leg.to) > EPS or absf(distance - float(leg.physicalDistance)) > maxf(EPS, distance * 0.000000001):return _failure("forecast", "The forecast must preserve the actual leg path, endpoint and physical distance.")
	if not is_finite(expected) or not is_finite(conservative):return _failure("forecast", "Ocean route time is not finite.")
	return {"ok": true, "time": {"expectedSeconds": expected, "conservativeSeconds": conservative}, "conditions": sampled}


static func _can_pursue(actor: Dictionary) -> bool:
	return bool(actor.get("canIntercept", false)) and bool(actor.get("canMove", false)) and float(actor.get("baseSpeed", 0.0)) > 0.0


static func _actor_index(actors: Array, owner_id: String) -> int:
	for index in range(actors.size()):
		if actors[index] is Dictionary and actors[index].get("ownerId") == owner_id:return index
	return -1


static func _actor(actors: Array, owner_id: String) -> Dictionary:
	var index: int = _actor_index(actors, owner_id)
	return actors[index] if index >= 0 else {}


static func _location(point: Dictionary) -> Dictionary:
	return {"world064": {"schema": 1, "layer": "ocean", "regionId": "open_ocean"}, "position": _point(point), "heading": 0.0, "path": [], "destination": ""}


static func _number(value) -> bool:
	return (value is int or value is float) and not value is bool and is_finite(float(value))


static func _time(value) -> bool:
	return _number(value) and float(value) >= 0.0


static func _text(value) -> bool:
	return value is String and not value.is_empty() and value.length() <= 128


static func _keys(value, expected: Array) -> bool:
	return _allowed(value, expected, expected)


static func _allowed(value, allowed: Array, required: Array) -> bool:
	if not value is Dictionary:return false
	for key in value:
		if not key is String or key not in allowed:return false
	for key in required:
		if not value.has(key):return false
	return true


static func _point_valid(value) -> bool:
	return _keys(value, ["x", "y"]) and _number(value.x) and _number(value.y)


static func _point(value: Dictionary) -> Dictionary:
	return {"x": float(value.x), "y": float(value.y)}


static func _distance(a: Dictionary, b: Dictionary) -> float:
	var dx: float = float(a.x) - float(b.x)
	var dy: float = float(a.y) - float(b.y)
	return sqrt(dx * dx + dy * dy)


static func _length(point: Dictionary) -> float:
	return sqrt(float(point.x) * float(point.x) + float(point.y) * float(point.y))


static func _copy(value):
	if value is Dictionary:
		var copy: Dictionary = {}
		for key in value:copy[str(key)] = _copy(value[key])
		return copy
	if value is Array:
		var copy: Array = []
		for child in value:copy.append(_copy(child))
		return copy
	return value


static func _success(message: String) -> Dictionary:
	return {"ok": true, "code": "ok", "message": message}


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "context": {}, "memory": {}, "location": {}, "locations": [],
		"acceptedSeconds": 0.0, "encounter": {}, "conditions": [], "condition": {}, "legTimes": [], "expectedSeconds": 0.0,
		"conservativeSeconds": 0.0, "validUntilSecond": 0.0, "assumptions": []}
