extends SceneTree
## One bounded model fixture. Root alone runs this through Test Bridge.
## Render DTOs below are observations, never fabricated physical fleets/stores.
## No purchases, money creation, campaign ticks, UI or rendered-quality claim.
const Travel = preload("res://scripts/ocean_travel066.gd")
const World = preload("res://scripts/ocean_world064.gd")
const Navigation = preload("res://scripts/navigation.gd")
var checks: int = 0
var failures: int = 0
var started: int = 0
var context: Dictionary = {}
var geometry: Dictionary = {}
var geometry_before: PackedByteArray
var hull_id: String = ""
var relations: Array = [{"observerId": "player", "targetId": "patrol-0", "hostile": true},
	{"observerId": "patrol-0", "targetId": "player", "hostile": true}]


func check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		print("FAIL ocean travel066: ", message)
	return value


func close(a: float, b: float) -> bool:
	return absf(a - b) <= 0.000001


func _initialize() -> void:
	started = Time.get_ticks_msec()
	var home = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var atlas = JSON.parse_string(FileAccess.get_file_as_string("res://data/ocean_regions064.json"))
	if not check(home is Dictionary and atlas is Dictionary, "Actual world definitions load"):
		finish()
		return
	hull_id = str(home.HULLS[0].id)
	var nav: Dictionary = Navigation.create(home.ISLANDS, home.WORLD.width, home.WORLD.height, 40.0 * float(home.CAMPAIGN_SCALE))
	var made: Dictionary = World.create(home, atlas, nav)
	if not check(made.ok, "One existing064 context is constructed for the entire fixture"):
		finish()
		return
	geometry = made.context
	geometry_before = var_to_bytes(geometry)
	var prepared: Dictionary = Travel.create(geometry, 0)
	if not check(prepared.ok, "Authored condition JSON creates the runtime"):
		print(prepared.message)
		finish()
		return
	context = prepared.context
	check(is_same(context.world064Context, geometry) and is_same(geometry.homeNav, nav), "Runtime shares existing navigation by identity")
	check(context.zones.size() == 3 and prepared.memory == Travel.empty_memory(), "Only three small zones and empty model memory are authored")
	for section in [Callable(self, "movement"), Callable(self, "intelligence"), Callable(self, "pursuit"), Callable(self, "crossing"), Callable(self, "forecasts"), Callable(self, "refusals")]:
		if Time.get_ticks_msec() - started >= 54000:
			check(false, "Fixture stopped before its 55-second body limit")
			break
		section.call()
	check(geometry_before == var_to_bytes(geometry), "Every operation preserves both immutable navigation graphs and geometry")
	check(Time.get_ticks_msec() - started < 55000, "Whole model fixture body stays below 55 seconds")
	finish()


func finish() -> void:
	print("ocean travel066: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func actor(owner_id: String, x: float, y: float, goal_x: float = -1.0, speed: float = 100.0) -> Dictionary:
	var location: Dictionary = {"world064": {"schema": 1, "layer": "ocean", "regionId": "open_ocean"},
		"position": {"x": x, "y": y}, "heading": 0.37, "path": [], "destination": ""}
	if goal_x >= 0.0:location["path"] = [{"x": goal_x, "y": y}]
	return {"ownerId": owner_id, "location": location, "baseSpeed": speed, "clearance": 10.0,
		"canMove": true, "canIntercept": false, "detectionRange": 1800.0, "interceptRange": 20.0,
		"boats": [{"uid": "observed-" + owner_id, "spec": {"id": hull_id, "size": 14.0}, "engineModule": "stock_engine"}]}


func stepped(actors: Array, memory: Dictionary, now: float, dt: float, watch: bool = false, decisions: Array = [], pairs: Array = []) -> Dictionary:
	var frame: Dictionary = {"startSecond": now, "dt": dt, "watchDue": watch, "decisionOwnerIds": decisions}
	var before: PackedByteArray = var_to_bytes([actors, memory, frame, pairs, context.zones])
	var result: Dictionary = Travel.step(context, actors, pairs, memory, frame)
	check(before == var_to_bytes([actors, memory, frame, pairs, context.zones]), "Step publishes no actor, intel, schedule or zone mutation")
	check(plain(result), "Step outputs only finite explicit String-key data")
	return result


func moved(source: Dictionary, result: Dictionary, index: int = 0) -> Dictionary:
	var copy: Dictionary = source.duplicate(true)
	copy["location"] = result.locations[index].location
	return copy


func movement() -> void:
	var player: Dictionary = actor("player", 1200.0, 1400.0, 1400.0)
	var result: Dictionary = stepped([player], Travel.empty_memory(), 0.0, 1.0)
	if not check(result.ok, "Clear following current integrates"):
		return
	check(close(result.locations[0].distance, 120.0) and close(result.locations[0].location.position.x, 1212.0), "100 speed plus20 current means120 physical/12 chart units")
	var reverse: Dictionary = stepped([actor("player", 1400.0, 1400.0, 1200.0)], Travel.empty_memory(), 0.0, 1.0)
	check(reverse.ok and close(reverse.locations[0].distance, 80.0), "Reverse course pays the directed opposing current")
	var idle: Dictionary = stepped([actor("player", 1200.0, 1400.0)], Travel.empty_memory(), 0.0, 4.0)
	check(idle.ok and idle.locations[0].distance == 0.0 and idle.locations[0].location.position.x == 1200.0, "No idle drift from weather/current")
	for disabled in ["canMove", "baseSpeed"]:
		var stopped: Dictionary = player.duplicate(true)
		stopped[disabled] = false if disabled == "canMove" else 0.0
		var halted: Dictionary = stepped([stopped], Travel.empty_memory(), 0.0, 4.0)
		check(halted.ok and halted.locations[0].distance == 0.0, "No powered movement without " + disabled)
	var whole: Dictionary = stepped([player], Travel.empty_memory(), 14.0, 4.0)
	var first: Dictionary = stepped([player], Travel.empty_memory(), 14.0, 1.0)
	var second: Dictionary = stepped([moved(player, first)], first.memory, 15.0, 3.0)
	check(whole.ok and close(whole.locations[0].distance, 426.0), "Four-second frame splits at the15s weather phase")
	check(close(whole.locations[0].location.position.x, second.locations[0].location.position.x), "Partitioning at the weather boundary preserves movement")
	var edge: Dictionary = actor("player", 1178.0, 1400.0, 1300.0)
	var edge_whole: Dictionary = stepped([edge], Travel.empty_memory(), 0.0, 1.0)
	var edge_first: Dictionary = stepped([edge], Travel.empty_memory(), 0.0, 0.2)
	var edge_second: Dictionary = stepped([moved(edge, edge_first)], edge_first.memory, 0.2, 0.8)
	check(edge_whole.ok and close(edge_whole.locations[0].distance, 116.0), "Zone entry splits before applying its current")
	check(close(edge_whole.locations[0].location.position.x, edge_second.locations[0].location.position.x), "Partitioning at the spatial boundary preserves movement")
	var repeated: Dictionary = stepped([player], Travel.empty_memory(), 14.0, 4.0)
	check(var_to_bytes(whole) == var_to_bytes(repeated), "Identical inputs reproduce complete results")


func intelligence() -> void:
	var player: Dictionary = actor("player", 2200.0, 1100.0, 2600.0)
	var npc: Dictionary = actor("patrol-0", 2300.0, 1100.0)
	npc.location["heading"] = 1.1
	var hidden: Dictionary = stepped([player, npc], Travel.empty_memory(), 0.0, 0.0, true, [], relations)
	check(hidden.ok and hidden.memory.sightings.is_empty(), "Dense fog hides a1000-unit contact outside630-unit detection")
	var seen: Dictionary = stepped([player, npc], Travel.empty_memory(), 15.0, 0.0, true, [], relations)
	if not check(seen.ok and seen.memory.sightings.has("player"), "Lighter mist exposes the same contact at1350-unit detection"):
		return
	var saved_sight: Dictionary = seen.memory.sightings.player["patrol-0"].duplicate(true)
	npc.location["position"] = {"x": 2450.0, "y": 1100.0}
	npc.location["heading"] = 2.2
	npc.boats[0].spec["size"] = 28.0
	var lost: Dictionary = stepped([player, npc], seen.memory, 16.0, 0.0, true, [], relations)
	check(lost.ok and lost.memory.sightings.player["patrol-0"] == saved_sight, "Hidden movement, heading and changed artwork never leak into last sight")
	var investigate: Dictionary = Travel.command(context, player, lost.memory, {"kind": "investigate", "targetId": "patrol-0"}, 16.0)
	if not check(investigate.ok, "Investigate accepts a real unexpired observation"):
		return
	check(investigate.location.path[-1].x == 2300.0 and investigate.memory.intents.player.returnGoal.target.x == 2600.0, "Investigate plots the frozen sighting and preserves the original voyage")
	var altered: Dictionary = player.duplicate(true)
	altered["location"] = investigate.location
	var divert: Dictionary = Travel.command(context, altered, investigate.memory, {"kind": "divert", "target": {"x": 2100.0, "y": 1000.0}, "destination": ""}, 16.0)
	check(divert.ok and divert.memory.intents.player.returnGoal.target.x == 2600.0, "A second diversion retains the original goal only once")
	var avoid: Dictionary = Travel.command(context, player, seen.memory, {"kind": "avoid", "targetId": "patrol-0"}, 16.0)
	check(avoid.ok and avoid.location.path[-1].x < player.location.position.x, "Avoid plots a physical escape away from the dated contact")
	altered["location"] = divert.location
	altered.location["position"] = {"x": 2190.0, "y": 1100.0}
	var resumed: Dictionary = Travel.command(context, altered, divert.memory, {"kind": "resume"}, 17.0)
	check(resumed.ok and resumed.location.position.x == 2190.0 and resumed.location.path[-1].x == 2600.0, "Resume replots from today's position without teleportation")
	var expired: Dictionary = Travel.command(context, player, seen.memory, {"kind": "investigate", "targetId": "patrol-0"}, 45.0)
	check(not expired.ok and expired.memory.is_empty() and expired.location.is_empty(), "Expired investigation refuses atomically")
	var restored = JSON.parse_string(JSON.stringify(seen.memory))
	var rebuilt: Dictionary = Travel.prepare(geometry, context.zones, 0, restored, ["player", "patrol-0"], 16.0)
	if not check(rebuilt.ok, "Save-shaped memory passes the unchanged strict validator"):
		print("Save memory validation: ", rebuilt.code, ": ", rebuilt.message)
		return
	# The save boundary is parsed JSON, including its numeric representation.
	# Compare every restored field exactly; do not round or omit snapshot data.
	check(rebuilt.memory == restored, "Save-shaped memory restores every parsed key and value exactly")
	var frozen_save = JSON.parse_string(JSON.stringify(saved_sight))
	check(rebuilt.memory.sightings.player["patrol-0"] == frozen_save, "Restored position, heading and boat artwork retain the frozen observation")
	check(is_same(rebuilt.context.world064Context, geometry), "Save restore keeps the existing shared runtime geometry")
	if rebuilt.memory != seen.memory:
		print("Save memory representation: parsedEqual=", rebuilt.memory == restored,
			" rawSchemaType=", typeof(seen.memory.schema), " savedSchemaType=", typeof(restored.schema),
			" rawSightingSchemaType=", typeof(saved_sight.world064.schema),
			" savedSightingSchemaType=", typeof(restored.sightings.player["patrol-0"].world064.schema))
	var loaded_before: PackedByteArray = var_to_bytes(rebuilt.memory)
	var saved_world: Dictionary = rebuilt.memory.sightings.player["patrol-0"].world064
	check(typeof(player.location.world064.schema) == TYPE_INT and typeof(saved_world.schema) == TYPE_FLOAT, "Save regression crosses real integer/JSON-float identity representations")
	check(Travel.same_world(saved_world, player.location.world064) and Travel.same_world(player.location.world064, saved_world), "World identity is symmetric across the save boundary")
	var loaded_command: Dictionary = Travel.command(context, player, rebuilt.memory, {"kind": "investigate", "targetId": "patrol-0"}, 16.0)
	check(loaded_command.ok and loaded_command.location.path[-1].x == 2300.0 and loaded_command.memory.sightings == rebuilt.memory.sightings, "Post-load investigate accepts the canonical actor and retains exact frozen intel")
	var pursuer: Dictionary = npc.duplicate(true)
	pursuer["canIntercept"] = true
	var loaded_step: Dictionary = stepped([player, pursuer], rebuilt.memory, 16.0, 1.0, true, ["patrol-0"], relations)
	check(loaded_step.ok and loaded_step.memory.pursuits.has("patrol-0") and loaded_step.memory.pursuits["patrol-0"].phase == "searching" and loaded_step.locations[1].location.path[-1].x == 2200.0, "Post-load scheduled pursuit uses the saved sighting with a canonical actor")
	var saved_route = JSON.parse_string(JSON.stringify(investigate.memory))
	var loaded_resume: Dictionary = Travel.command(context, player, saved_route, {"kind": "resume"}, 17.0)
	check(loaded_resume.ok and loaded_resume.location.path[-1].x == 2600.0, "Post-load resume accepts the original JSON-float voyage goal")
	check(loaded_before == var_to_bytes(rebuilt.memory), "Post-load commands and step preserve the exact parsed memory representation")
	for mismatch in [{"schema": 1.0, "layer": "ocean", "regionId": World.HOME}, {"schema": 1.0, "layer": "home", "regionId": World.OCEAN}, {"schema": 2.0, "layer": "ocean", "regionId": World.OCEAN}]:
		check(not Travel.same_world(saved_world, mismatch) and not Travel.same_world(mismatch, saved_world), "Wrong region, layer or schema still fails strict identity matching")
	var other_chart: Dictionary = rebuilt.memory.duplicate(true)
	other_chart.sightings.player["patrol-0"]["world064"] = {"schema": 1.0, "layer": "home", "regionId": World.HOME}
	other_chart.sightings.player["patrol-0"]["position"] = {"x": 5200.0, "y": 300.0}
	var refused: Dictionary = Travel.command(context, player, other_chart, {"kind": "investigate", "targetId": "patrol-0"}, 16.0)
	check(not refused.ok and refused.code == "sighting" and refused.location.is_empty() and refused.memory.is_empty(), "A valid saved sighting on another chart still refuses atomically")


func pursuit() -> void:
	var player: Dictionary = actor("player", 2200.0, 1100.0)
	var npc: Dictionary = actor("patrol-0", 2300.0, 1100.0, 2700.0)
	npc["canIntercept"] = true
	var tracked: Dictionary = stepped([player, npc], Travel.empty_memory(), 15.0, 0.0, true, ["patrol-0"], relations)
	if not check(tracked.ok and tracked.memory.pursuits.has("patrol-0"), "One scheduled NPC decision starts actual pursuit"):
		return
	check(tracked.memory.pursuits["patrol-0"].phase == "tracking" and tracked.locations[1].location.path[-1].x == 2200.0, "Visible pursuit changes the NPC's physical course")
	npc = moved(npc, tracked, 1)
	var refreshed: Dictionary = stepped([player, npc], tracked.memory, 16.0, 0.0, true, [], relations)
	check(refreshed.ok and refreshed.memory.pursuits["patrol-0"].searchUntilSecond == 46.0 and Travel.validate_memory(context, refreshed.memory, 16.0).ok, "Detection refreshes consistent pursuit dates even when the decision is deferred")
	var another_chart: Dictionary = npc.duplicate(true)
	another_chart["location"] = {"world064": {"schema": 1, "layer": "home", "regionId": "shatter_coast"},
		"position": {"x": 5200.0, "y": 300.0}, "heading": 0.0, "path": [], "destination": ""}
	var retained: Dictionary = stepped([player, another_chart], tracked.memory, 16.0, 0.0, true, ["patrol-0"], relations)
	check(retained.ok and retained.memory.pursuits.has("patrol-0"), "Changing charts cannot clear unexpired pursuit memory")
	var avoided: Dictionary = Travel.command(context, player, tracked.memory, {"kind": "avoid", "targetId": "patrol-0"}, 15.0)
	check(avoided.ok and not Travel.transition_blocker([player, npc], relations, avoided.memory, false).is_empty(), "Avoid grants no pursuit immunity or chart escape")
	player.location["position"] = {"x": 2000.0, "y": 1100.0}
	var searching: Dictionary = stepped([player, npc], tracked.memory, 16.0, 0.0, true, ["patrol-0"], relations)
	check(searching.ok and searching.memory.pursuits["patrol-0"].phase == "searching", "Lost contact keeps a bounded dated search")
	check(searching.locations[1].location.path[-1].x == 2200.0, "Search uses the last observation and respects the3s replan cadence")
	check(not Travel.transition_blocker([player, npc], relations, searching.memory, false).is_empty(), "Live search blocks a transition between watches")
	var expired: Dictionary = stepped([player, npc], searching.memory, 46.0, 0.0, true, ["patrol-0"], relations)
	check(expired.ok and expired.memory.pursuits.is_empty() and expired.locations[1].location.path[-1].x == 2700.0, "Real sighting expiry releases pursuit and restores the NPC's original course")
	var incapable: Dictionary = npc.duplicate(true)
	incapable["canIntercept"] = false
	var released: Dictionary = stepped([player, incapable], tracked.memory, 16.0, 0.0)
	check(released.ok and released.memory.pursuits.is_empty(), "Actual incapacity releases a pursuit without a watch replay")
	check(not Travel.transition_blocker([player, npc], relations, Travel.empty_memory(), true).is_empty(), "Pending physical encounter independently blocks a chart transfer")


func crossing() -> void:
	var player: Dictionary = actor("player", 1000.0, 500.0, 1100.0, 500.0)
	var npc: Dictionary = actor("patrol-0", 1100.0, 500.0, 1000.0, 500.0)
	npc.location.world064["schema"] = 1.0
	npc["canIntercept"] = true
	var crossed: Dictionary = stepped([player, npc], Travel.empty_memory(), 2.0, 4.0, false, [], relations)
	if not check(crossed.ok and not crossed.encounter.is_empty(), "Swept crossing catches fast fleets with integer/JSON-float world identities"):
		return
	check(close(crossed.acceptedSeconds, 0.98) and close(crossed.encounter.atSecond, 2.98), "Earliest physical interception clips the accepted clock interval")
	check(close(crossed.locations[0].location.position.x, 1049.0) and close(crossed.encounter.position.x, 1049.0), "Encounter uses the exact player's offshore point")
	check(close(crossed.locations[0].distance, 490.0) and close(crossed.locations[1].distance, 490.0), "Both actors commit only the single accepted movement interval")
	check(crossed.memory.pursuits["patrol-0"].phase == "engaged" and crossed.memory.sightings.player["patrol-0"].seenSecond == crossed.encounter.atSecond, "Actual swept contact reveals dated artwork and retains engagement")
	player["canIntercept"] = true
	var forward: Dictionary = stepped([player, npc], Travel.empty_memory(), 2.0, 4.0, false, [], relations)
	var reversed_pairs: Array = relations.duplicate(true)
	reversed_pairs.reverse()
	var backward: Dictionary = stepped([player, npc], Travel.empty_memory(), 2.0, 4.0, false, [], reversed_pairs)
	check(forward.encounter == backward.encounter and forward.encounter.attackerId == "patrol-0", "Coincident interception resolves by stable owner ID")


func forecasts() -> void:
	var leg: Dictionary = {"kind": "sail", "layer": "ocean", "from": {"x": 1200.0, "y": 1400.0}, "to": {"x": 1400.0, "y": 1400.0},
		"path": [{"x": 1400.0, "y": 1400.0}], "physicalDistance": 2000.0, "seconds": 20.0}
	var coast: Dictionary = {"kind": "sail", "layer": "home", "physicalDistance": 250.0, "seconds": 2.5}
	var before: PackedByteArray = var_to_bytes([leg, coast, context.zones])
	var estimate: Dictionary = Travel.forecast(context, [leg, coast], 100.0, 0.0)
	if not check(estimate.ok, "Actual leg schema accepts a weather/current forecast"):
		return
	check(close(estimate.legTimes[0].expectedSeconds, 2000.0 / 120.0) and close(estimate.legTimes[0].conservativeSeconds, 2000.0 / 102.0), "Forecast distinguishes current-held clear and slowest rain durations")
	check(estimate.legTimes[1] == {"expectedSeconds": 2.5, "conservativeSeconds": 2.5}, "Coastal duration stays exactly unchanged")
	check(estimate.conservativeSeconds > estimate.expectedSeconds and estimate.validUntilSecond == 15.0 and not estimate.assumptions.is_empty(), "Forecast discloses its15s validity and changing-weather assumptions")
	check(before == var_to_bytes([leg, coast, context.zones]) and plain(estimate), "Forecast preserves physical distances, itinerary and source zones")
	var outside: Dictionary = leg.duplicate(true)
	outside["from"] = {"x": 1200.0, "y": 2000.0}
	outside["to"] = {"x": 1400.0, "y": 2000.0}
	outside["path"] = [outside.to]
	var detour: Dictionary = Travel.forecast(context, [outside], 100.0, 0.0)
	check(detour.ok and close(detour.expectedSeconds, 20.0) and close(detour.conservativeSeconds, 20.0), "A different physical course avoids the current/weather zone")
	var sampled: Dictionary = Travel.conditions(context, actor("player", 2200.0, 1100.0).location, 0.0)
	check(sampled.ok and close(sampled.condition.speedFactor, 0.65) and close(sampled.condition.visibilityFactor, 0.35), "Authored fog has meaningful movement and visibility effects")


func refusals() -> void:
	check(not Travel.prepare(geometry, context.zones, 0, {}, ["player", "patrol-0"], 0.0).ok, "Malformed present memory refuses instead of defaulting")
	var player: Dictionary = actor("player", 1000.0, 500.0, 1500.0)
	var too_long: Dictionary = stepped([player], Travel.empty_memory(), 0.0, 4.01)
	check(not too_long.ok and too_long.acceptedSeconds == 0.0 and too_long.locations.is_empty() and too_long.memory.is_empty(), "dt over4 refuses atomically without dropping time")
	var duplicate: Dictionary = stepped([player, player], Travel.empty_memory(), 0.0, 1.0)
	check(not duplicate.ok, "Duplicate physical actor cannot move twice")
	var excess: Dictionary = player.duplicate(true)
	excess.location["path"] = []
	for index in range(9):excess.location.path.append({"x": 1100.0 + index * 10.0, "y": 500.0})
	check(not stepped([excess], Travel.empty_memory(), 0.0, 1.0).ok, "More than eight ocean waypoints refuses")
	var live_art: Dictionary = player.duplicate(true)
	live_art.boats[0]["fuel"] = 9.0
	check(not stepped([live_art], Travel.empty_memory(), 0.0, 1.0).ok, "Live resource fields cannot enter frozen artwork DTOs")
	var nan_actor: Dictionary = player.duplicate(true)
	nan_actor["baseSpeed"] = NAN
	check(not Travel.step(context, [nan_actor], [], Travel.empty_memory(), {"startSecond": 0.0, "dt": 1.0, "watchDue": false, "decisionOwnerIds": []}).ok, "Nonfinite speed refuses before any model publication")


func plain(value) -> bool:
	if value is String or value is bool:return true
	if value is int or value is float:return is_finite(float(value))
	if value is Array:
		for item in value:
			if not plain(item):return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not plain(value[key]):return false
		return true
	return false
