extends RefCounted
const Lab = preload("res://scripts/fleet_lab.gd")
const Battle = preload("res://scripts/battle.gd")
const DT: float = 1.0 / 30.0
const MAX_TICKS: int = 60
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SURVIVAL106: " + message)

func published(st: Dictionary, id: String) -> Dictionary:
	var tactical: Dictionary = st.get("tactical", {})
	var memory: Dictionary = tactical.get("memory", {})
	var side: Dictionary = memory.get(str(st.ships[0].team), {})
	return side.get("byId", {}).get(id, {}).duplicate(true)

func advance_to(st: Dictionary, id: String, leader: String, phases: Array) -> Dictionary:
	var row: Dictionary = {}
	for tick in range(MAX_TICKS):
		if st.get("result") != null:
			break
		Battle.update(st, DT)
		row = published(st, id)
		var applied: int = int(st.tactical.get("appliedRevisions", {}).get(id, -1))
		var acknowledged: bool = applied == int(st.ships[0].orderRevision)
		if acknowledged and str(row.get("role", "")) == "screen":
			if str(row.get("leaderId", "")) == leader:
				if phases.is_empty() or str(row.get("phase", "")) in phases:
					return row
	return {}

func trial(world: Dictionary, mode: String) -> void:
	var config: Dictionary = Lab.preset(world, "duel")
	config.player = [Lab.entry(world, "maiden_dreadnought"), Lab.entry(world, "tin_skiff")]
	config.enemy = [Lab.entry(world, "cobalt_frigate", 2)]
	var made: Dictionary = Lab.create(world, config, 106106)
	check(bool(made.get("ok", false)), mode + ": ordinary Lab creation")
	if not bool(made.get("ok", false)):
		return
	var st: Dictionary = made.battle
	# Controlled setup: neutralize the default escort objective before begin.
	st["mission"] = {}
	st.islands = []
	st.autoBoard = false
	for i: int in range(st.ships.size()):
		var boat: Dictionary = st.ships[i]
		boat.x = 650.0 if boat.team == "player" else 1500.0
		boat.y = 850.0 if i != 1 else 1100.0
		boat.angle = 0.0 if boat.team == "player" else PI
	Battle.update(st, DT) # Lab.create registers; this begins the native stage.
	check(st.get("result") == null, mode + ": begin remains active")
	if st.get("result") != null:
		return
	Battle.set_autopilot(st, true)
	var own: Dictionary = st.ships[0]
	var ally: Dictionary = st.ships[1]
	var id: String = str(own.id)
	var ally_id: String = str(ally.id)
	var configured: bool = Battle.set_tactical_options(st, [id],
		{"role":"screen", "protectedAllyId":ally_id, "conditionalWithdrawal":false})
	check(configured, mode + ": public screen options accepted")
	if not configured:
		return
	check(Battle.issue_order(st, [id], "engage"), mode + ": public engage accepted")
	var before: Dictionary = advance_to(st, id, ally_id, [])
	var established: bool = str(before.get("role", "")) == "screen"
	established = established and str(before.get("leaderId", "")) == ally_id
	check(established, mode + ": published screen initially protects the living ally")
	if not established:
		return
	# Controlled loss and resource/damage conditions; no role-memory injection.
	ally.sunk = true
	if mode in ["fire", "hold-fire"]:
		own.fire = 30.0
	elif mode == "dry":
		own.ammo = 0.0
	elif mode == "fuel":
		own.fuel = 0.0
	var order: String = "hold" if mode == "hold-fire" else "engage"
	check(Battle.issue_order(st, [id], order), mode + ": public command refresh")
	var wanted: Array = ["hold"] if mode in ["healthy", "hold-fire"] else ["breakaway", "regroup"]
	var after: Dictionary = advance_to(st, id, "", wanted)
	check(st.get("result") == null, mode + ": ally loss did not finish the fixture")
	check(str(own.order) == order, mode + ": native order remains " + order)
	check(str(after.get("role", "")) == "screen", mode + ": published screen role")
	check(str(after.get("leaderId", "?")) == "", mode + ": fresh memory loses protector")
	check(str(after.get("phase", "")) in wanted, mode + ": expected phase " + str(wanted))
	print("SURVIVAL106 ", JSON.stringify({"case":mode, "time":st.time,
		"order":own.order, "fire":own.get("fire", 0), "ammo":own.ammo,
		"fuel":own.fuel, "published":after}))

func exercise(world: Dictionary) -> Dictionary:
	for mode: String in ["healthy", "fire", "dry", "fuel", "hold-fire"]:
		trial(world, mode)
	print("SURVIVAL106: %d checks, %d failures" % [checks, failures])
	return {"checks":checks,"failures":failures}
