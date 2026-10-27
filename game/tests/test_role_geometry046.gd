extends SceneTree
## Narrow source contracts. Root owns native execution and six-scenario motion proof.
const Lab = preload("res://scripts/fleet_lab.gd")
const Battle = preload("res://scripts/battle.gd")
const Tactical = preload("res://scripts/tactical_runtime.gd")
const Roles = preload("res://scripts/tactical_role_plans.gd")
const Stations = preload("res://scripts/tactical_stations.gd")
const Routes = preload("res://scripts/tactical_routes.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ROLE GEOMETRY046: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var original_world: Dictionary = world.duplicate(true)
	var config: Dictionary = Lab.preset(world, "duel")
	config.player = [Lab.entry(world, "maiden_dreadnought"), Lab.entry(world, "tin_skiff")]
	config.enemy = [Lab.entry(world, "cobalt_frigate", 2)]
	config.player[0].loadout.weapons = ["stock_primary", "rapid_gun", "fire_rocket", "light_torpedo"]
	var made: Dictionary = Lab.create(world, config, 46046)
	check(bool(made.get("ok", false)), "real Lab accepts the cannon-primary mixed fit")
	if not bool(made.get("ok", false)):
		quit(1)
		return
	var battle: Dictionary = made.battle
	var own_id: String = str(battle.ships[0].id)
	var friend_id: String = str(battle.ships[1].id)
	# Layout only, before the first real update. No timer, event or store injection.
	for i: int in range(battle.ships.size()):
		var boat: Dictionary = battle.ships[i]
		boat.x = 650.0 if boat.team == "player" else 1200.0
		boat.y = (850.0 if i == 0 else 1100.0) if boat.team == "player" else (800.0 if i == 2 else 900.0)
		boat.angle = 0.0 if boat.team == "player" else PI
	Battle.update(battle, 1.0 / 60.0)
	var view: Dictionary = Tactical.view(battle, "player", [own_id])
	var context: Dictionary = Roles.ships_by_id(view)
	var own: Dictionary = context[own_id]
	var before: PackedByteArray = var_to_bytes(view)
	check(Roles.infer_role(view, own) == "heavy", "real cannon-primary dreadnought keeps its heavy role despite secondary tubes")
	var first: Dictionary = Roles.decide(view, own, {}, context)
	check(not str(first.state.targetId).is_empty(), "role selects an observed opponent")
	var reservations: Dictionary = {}
	reservations[friend_id] = {"targetId": str(first.state.targetId), "sector": 2, "until": float(view.time) + 2.0}
	var held: PackedByteArray = var_to_bytes(reservations)
	var shared: Dictionary = Roles.decide(view, own, {}, context, reservations)
	check(str(shared.state.targetId) != str(first.state.targetId), "existing friendly pressure separates otherwise similar autonomous targets")
	var committed: Dictionary = first.state.duplicate(true)
	committed.commitUntil = float(view.time) + 1.0
	check(Roles.decide(view, own, committed, context, reservations).state.targetId == first.state.targetId, "pressure does not jitter a live target commitment")
	var requests: Array = Stations.candidates(view, own, first, context, reservations)
	check(not requests.is_empty() and requests.size() <= Stations.MAX_OFFERS, "real snapshot yields bounded station requests")
	for candidate: Dictionary in requests:
		check(Stations.valid_candidate(candidate), "candidate field and point caps remain unchanged")
		var pass_target: Dictionary = context[str(candidate.targetId)]
		var pass_clearance: float = Routes.navigation_radius(own) + Routes.navigation_radius(pass_target) + 7.0
		var path: Array = candidate.approach + candidate["pass"] + candidate.exit
		var pass_clear: bool = true
		for j: int in range(path.size() - 1):
			pass_clear = pass_clear and Routes.distance(Roles.pos(pass_target), path[j], path[j + 1]) >= pass_clearance - 0.0001
		check(pass_clear, "ordinary approach/pass/exit does not cut through its observed target envelope")
	var target: Dictionary = context[str(first.state.targetId)]
	var center: Vector2 = Roles.pos(target)
	var clearance: float = Routes.navigation_radius(own) + Routes.navigation_radius(target) + 12.0
	var around: Array = Stations._target_approach(center + Vector2.LEFT * 400.0, center + Vector2.RIGHT * 400.0, target, clearance, 1.0)
	check(around.size() > 2 and around.size() <= Stations.MAX_LEG, "opposite-side setup uses a bounded route around the hull")
	var clear: bool = true
	for j: int in range(around.size() - 1):
		clear = clear and Routes.distance(center, around[j], around[j + 1]) >= clearance - 0.0001
	check(clear, "all offered orbit chords preserve hull stand-off")
	check(var_to_bytes(view) == before and var_to_bytes(reservations) == held, "role and station requests cannot mutate snapshots or shared reservations")
	check(Battle.issue_order(battle, [own_id], "attack", {"shipId": str(first.state.targetId)}), "public attack command accepts the observed target")
	var ordered_view: Dictionary = Tactical.view(battle, "player", [own_id])
	var ordered_context: Dictionary = Roles.ships_by_id(ordered_view)
	check(Roles.decide(ordered_view, ordered_context[own_id], {}, ordered_context, reservations).state.targetId == first.state.targetId, "team pressure cannot divert an explicit attack")
	check(world == original_world, "Lab and planning preserve source world data")
	print("ROLE GEOMETRY046: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
