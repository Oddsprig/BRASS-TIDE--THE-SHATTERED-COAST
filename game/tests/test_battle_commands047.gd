extends SceneTree
## Prepared only. Root runs this once in the existing bounded Test Bridge batch.
const Main = preload("res://scripts/main.gd")
const Chart = preload("res://scripts/chart.gd")
const Lab = preload("res://scripts/fleet_lab.gd")
const Battle = preload("res://scripts/battle.gd")
const Commands = preload("res://scripts/battle_commands047.gd")
const Stations = preload("res://scripts/tactical_stations.gd")
var checks: int = 0
var failures: int = 0

class QuietUI extends RefCounted:
	var modal_open: bool = false
	var message: String = ""
	func toast(value: String, _error: bool = false):message = value
	func update_hud():pass

func check(ok: bool, message: String):
	checks += 1
	if not ok:failures += 1;push_error("COMMANDS047: " + message)

func custody(st: Dictionary) -> Array:
	var out: Array = st.ships.duplicate(true)
	for boat: Dictionary in out:
		for key in ["order", "orderTarget", "orderRevision", "boardingOrder"]:boat.erase(key)
	return out

func _initialize():call_deferred("run")

func run():
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var original: Dictionary = world.duplicate(true)
	var made: Dictionary = Lab.create(world, Lab.preset(world, "tactical_escort_raider"), 47047)
	check(bool(made.get("ok", false)), "existing escort practice constructs normally")
	if not made.get("ok", false):quit(1);return
	var st: Dictionary = made.battle
	var players: Array = st.ships.filter(func(s):return s.team == "player")
	var own: Dictionary = players[1]
	var ally: Dictionary = players[0]
	var foe: Dictionary = st.ships.filter(func(s):return s.team == "enemy")[0]
	var id: String = str(own.id)
	var host = Main.new()
	host.ui = QuietUI.new();host.chart = Chart.new();host.chart.host = host
	host.battle = st;host.mode = "battle";host.selected_battle_ids = [id]
	var held: Array = custody(st)
	var reserves: Dictionary = st.reserves.duplicate(true)
	var deployment: Dictionary = st.deployment.duplicate(true)
	var rng_state: int = st.rng.state
	var survival_choice_preserved: bool = Battle.set_tactical_options(st, [id], {"conditionalWithdrawal": true})
	for command: String in ["engage", "harass", "focus", "escort", "defend", "rally", "hold", "withdraw"]:
		var target: Dictionary = {}
		if command == "focus":target.shipId = str(foe.id)
		if command == "escort":target.shipId = str(ally.id)
		if command in ["defend", "rally"]:target = {"x":float(own.x), "y":float(own.y)}
		var revision: int = int(own.orderRevision)
		check(host.request_battle_command(command, target), command + " accepted immediately")
		check(int(own.orderRevision) == revision + 1 and host.battle_command_ack.count == 1 and not host.ui.message.is_empty(), command + " publishes an immediate visible acknowledgement")
		check(float(st.tactical.counters.orderAcks[-1].age) == 0.0 and st.tactical.counters.orderAcks[-1].shipId == id, command + " uses the immediate authoritative order acknowledgement")
		var opts: Dictionary = st.tactical.options.byId[id]
		if command in ["focus", "hold"]:survival_choice_preserved = survival_choice_preserved and bool(opts.conditionalWithdrawal)
		if command == "harass":check(own.order == "engage" and opts.doctrine == "cautious" and opts.role == "skirmisher", "harass is cautious pressure")
		if command == "focus":check(own.order == "attack" and own.orderTarget.shipId == foe.id and opts.doctrine == "aggressive", "focus locks the actual enemy")
		if command == "escort":check(own.order == "escort" and opts.protectedAllyId == ally.id, "escort protects the actual ally")
		if command == "defend":check(own.order == "hold" and own.orderTarget == target, "defend holds the named water")
		if command == "rally":check(own.order == "move" and opts.rally == target, "rally uses real move then hold lifecycle")
		if command == "hold":check(own.order == "hold" and own.orderTarget == {"x":float(own.x),"y":float(own.y)}, "hold brakes at its own position")
	check(survival_choice_preserved, "focus and hold preserve the explicit survival withdrawal choice")
	var before: PackedByteArray = var_to_bytes([st.ships, st.tactical])
	for bad: Dictionary in [{"shipId":str(ally.id)}, {"shipId":"gone"}]:
		check(not host.request_battle_command("focus", bad), "invalid focus rejected visibly")
		check(var_to_bytes([st.ships, st.tactical]) == before, "rejection changes no options, orders or stores")
	check(not host.request_battle_command("rally", {"x":-100.0,"y":0.0}), "out of bounds rally rejected")
	check(var_to_bytes([st.ships, st.tactical]) == before, "bad water changes no tactical state")
	var revision: int = int(own.orderRevision)
	check(Commands.needs_target("focus") and not Commands.needs_target("hold"), "only target commands wait for a world click")
	check(host.request_battle_command("focus") and host.battle_command_pending == "focus" and int(own.orderRevision) == revision, "arming a target picker issues no order")
	host.selected_battle_ids = []
	check(not host.request_battle_command("hold") and int(own.orderRevision) == revision, "new bar never silently commands the fleet")
	host.selected_battle_ids = [id, str(ally.id)]
	check(host.save_selection_group(1) and host.set_selected_formation("line"), "group and real formation options are accepted")
	var view: Dictionary = {"options":st.tactical.options,"groups":st.tactical.groups}
	var line: Vector2 = Stations.formation_offset(view, own, ally)
	check(host.set_selected_formation("column") and line != Stations.formation_offset(view, own, ally), "formation changes actual escort geometry")
	check(host.save_selection_group(2) and not host.recall_selection_group(1) and host.recall_selection_group(2), "reassignment removes stale group membership")
	host.selected_battle_ids = [id]
	check(host.save_selection_group(2) and st.tactical.options.byId[str(ally.id)].group == 0, "saving over a group releases its previous members")
	host.select_battle_boat(id);host.select_battle_boat(str(ally.id), true)
	check(host.selected_battle_ids.size() == 2, "selection and additive selection preserve live boats")
	for was_paused: bool in [false, true]:
		host.paused = was_paused;host.toggle_tactical();check(host.paused, "tactical entry pauses")
		host.toggle_tactical();check(host.paused == was_paused and st.autopilot, "tactical exit restores prior pause and default autopilot")
	check(host.chart.battle_overlays == {"arcs":false,"threat":false,"routes":false}, "overlays start opt in")
	check(host.set_battle_overlay("arcs", true) and not host.set_battle_overlay("unknown", true), "only named overlays can be enabled")
	check(custody(st) == held and st.reserves == reserves and st.deployment == deployment and st.rng.state == rng_state, "commands conserve complete physical state, reserves, DP and RNG")
	host.selected_battle_ids = [id]
	Battle.set_autopilot(st, false)
	check(host.request_battle_command("hold") and not st.autopilot, "orders preserve manual helm authority")
	Battle.set_autopilot(st, true)
	var home: Dictionary = st.tactical.home[id].duplicate()
	check(host.request_battle_command("rally", home), "safe existing local rally accepted")
	revision = int(own.orderRevision)
	var began: bool = false
	for tick: int in range(15):
		Battle.update(st, 1.0 / 60.0)
		var intent: Dictionary = st.tactical.intents.get(id, {})
		if int(intent.get("orderRevision", -1)) == revision and not intent.get("waypoints", []).is_empty():began = true;break
	check(began, "new safe intent begins within 0.25s; turning and braking remain physical")
	check(world == original, "source world remains untouched")
	host.chart.free();host.free()
	print("COMMANDS047: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
