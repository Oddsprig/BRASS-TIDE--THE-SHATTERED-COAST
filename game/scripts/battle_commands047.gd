extends RefCounted
## A small player-command adapter. Battle remains the order/options authority.
const Battle = preload("res://scripts/battle.gd")
const Damage = preload("res://scripts/damage.gd")
const COMMANDS: Array = ["engage", "harass", "focus", "escort", "defend", "rally", "hold", "withdraw", "move", "attack"]

static func needs_target(command: String) -> bool:
	return command in ["focus", "escort", "defend", "rally"]

static func reply(command: String, ok: bool, message: String, count: int = 0) -> Dictionary:
	return {"ok": ok, "command": command, "message": message, "count": count}

static func _live(ships: Array, id: String) -> Dictionary:
	for ship: Dictionary in ships:
		if str(ship.id) == id and not ship.sunk and not ship.get("captureSecured", false):return ship
	return {}

static func apply(st: Dictionary, ids: Array, command: String, target: Dictionary = {}) -> Dictionary:
	if st.is_empty() or st.get("result") != null or command not in COMMANDS:
		return reply(command, false, "That command is unavailable.")
	var ships: Array = st.get("ships", [])
	var recipients: Array = []
	var boats: Array = []
	for id: Variant in ids:
		if not (id is String or id is StringName):return reply(command, false, "Choose living friendly boats.")
		var boat: Dictionary = _live(ships, str(id))
		if boat.is_empty() or boat.team != "player" or not st.get("tactical", {}).get("mountCache", {}).has(str(id)):
			return reply(command, false, "Choose living friendly boats.")
		if str(id) not in recipients:recipients.append(str(id));boats.append(boat)
	var clean: Dictionary = {}
	var order: String = str({"harass": "engage", "focus": "attack", "defend": "hold", "rally": "move"}.get(command, command))
	# Movement and Hold must not discard a player's chosen role/doctrine. The
	# named combat presets below still make their explicit tactical changes.
	var patch: Dictionary = {"doctrine": "steady", "role": "auto", "protectedAllyId": ""} if command in ["engage","harass","focus","attack","escort"] else {}
	if order in ["attack", "escort"]:
		if not (target.get("shipId") is String or target.get("shipId") is StringName):
			return reply(command, false, "Choose an enemy to focus." if order == "attack" else "Choose a friendly boat to protect.")
		var other: Dictionary = _live(ships, str(target.shipId))
		if other.is_empty() or other.team != ("enemy" if order == "attack" else "player"):
			return reply(command, false, "Choose a living enemy." if order == "attack" else "Choose a living friendly boat.")
		clean.shipId = str(other.id)
		if order == "escort":
			recipients.erase(str(other.id));boats.erase(other)
			patch.role = "screen";patch.protectedAllyId = str(other.id)
		else:patch.doctrine = "aggressive"
	elif order == "move" or command == "defend" or (order in ["hold", "withdraw"] and not target.is_empty()):
		var x: float = Damage.number(target.get("x"), NAN)
		var y: float = Damage.number(target.get("y"), NAN)
		if not is_finite(x) or not is_finite(y):return reply(command, false, "Choose a water position.")
		clean = {"x": x, "y": y}
		# Read-only preflight matches Battle's point checks, with its rally margin.
		# Every recipient is checked before either public mutation is called.
		for boat: Dictionary in boats:
			if Battle._blocked(st, Vector2(x, y), maxf(10.0, float(boat.spec.get("size", 16))) + 4.0):
				return reply(command, false, "That position is on land or outside the battle. Choose open water.")
		if command == "rally" or order == "withdraw":patch.rally = clean.duplicate()
	if recipients.is_empty():return reply(command, false, "Select boats to command; an escort needs another friendly boat.")
	if command == "harass":patch.doctrine = "cautious";patch.role = "skirmisher"
	if command == "withdraw":patch.doctrine = "cautious"
	if not patch.is_empty() and not Battle.set_tactical_options(st, recipients, patch):return reply(command, false, "Those tactical choices are unavailable.")
	if not Battle.issue_order(st, recipients, order, clean):return reply(command, false, "Choose navigable water or a living target.")
	var message: String = str({
		"engage": "Engage: choose targets and maneuver by fitted role.",
		"harass": "Harass: cautious pressure, with earlier breakaway.",
		"focus": "Focus attack: concentrate on the named enemy.", "attack": "Focus attack: concentrate on the named enemy.",
		"escort": "Escort: protect the named ally in the chosen formation.",
		"defend": "Defend: hold the marked water and fire within reach.",
		"rally": "Rally: move without firing, then hold at the marker.",
		"move": "Move: follow the marked water position.",
		"hold": "Hold: brake and defend current positions.",
		"withdraw": "Fall back: selected boats disengage locally. Retreat fleet ends the battle."
	}.get(command, "Order received."))
	if str(st.get("playerId", "")) in recipients and not bool(st.get("autopilot", true)):
		message += " Flagship order waits for autopilot (U)."
	return reply(command, true, message, recipients.size())
