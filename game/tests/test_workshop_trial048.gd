extends SceneTree
## Existing production Lab transition with only its rendering entry suppressed.
const Campaign = preload("res://scripts/campaign.gd")
const Refits = preload("res://scripts/refit.gd")
const Battle = preload("res://scripts/battle.gd")
var checks: int = 0
var failures: int = 0

class QuietUI extends RefCounted:
	var message: String = ""
	func toast(value: String, _error: bool = false):message = value

class TrialHost extends "res://scripts/main.gd":
	func _enter_battle():mode = "battle"

func check(ok: bool, message: String):
	checks += 1
	if not ok:failures += 1;print("FAIL workshop_trial048: " + message)

func _initialize():call_deferred("run")

func run():
	var host = TrialHost.new()
	host.data = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	host.core = Campaign.new(host.data)
	host.ui = QuietUI.new()
	host.core.new_game(48048)
	host.mode = "campaign"
	var career = host.core
	var before: Dictionary = career.state.duplicate(true)
	var owned: Dictionary = career.state.fleet[0]
	var draft: Dictionary = Refits.defaults(career.hull(str(owned.type)))
	draft.engine = "economy_drive"
	var original_draft: Dictionary = draft.duplicate(true)
	check(not host.workshop_try_draft("missing-owned-boat", draft), "unowned boat refuses trial")
	var invalid: Dictionary = draft.duplicate(true)
	invalid.engine = "unknown-engine"
	check(not host.workshop_try_draft(str(owned.uid), invalid), "invalid draft refuses trial")
	check(career.state == before and host.career_core == null and host.lab_config.is_empty(), "rejected trials preserve career and Lab state")
	check(host.workshop_try_draft(str(owned.uid), draft), "valid owned draft enters existing isolated Lab")
	if host.lab_active:
		check(host.career_core == career and host.core != career and career.state == before, "actual Lab retains original career without buying equipment")
		var friendly: Array = host.battle.ships.filter(func(s):return s.team == "player")
		var hostile: Array = host.battle.ships.filter(func(s):return s.team == "enemy")
		check(friendly.size() == 1 and hostile.size() == 1 and hostile[0].spec.id == "ash_corvette", "repeatable trial uses one chosen hull and the same real opponent")
		check(friendly[0].loadout == draft and host.lab_seed == 48048 and draft == original_draft, "trial uses detached current draft and fixed comparison seed")
		var stores: Array = [friendly[0].ammo, friendly[0].fuel, friendly[0].supplies]
		for i in range(8):Battle.update(host.battle, 1.0 / 60.0)
		check(friendly[0].ammo <= stores[0] and friendly[0].fuel <= stores[1] and friendly[0].supplies <= stores[2], "real trial ticks grant no replacement stores")
		check(career.state == before, "trial simulation cannot change career purses, equipment or people")
		check(not host.workshop_try_draft(str(owned.uid), draft), "nested trial refuses while Lab is active")
		host._leave_lab()
		check(host.core == career and host.career_core == null and not host.lab_active and career.state == before, "normal Lab exit restores the exact career")
	host.free()
	print("workshop_trial048: %d checks, %d failures; actual transition, rendering covered separately" % [checks, failures])
	quit(0 if failures == 0 else 1)
