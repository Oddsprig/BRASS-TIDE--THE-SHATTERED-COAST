extends RefCounted
## Leaf adapter. Stages one wreck before any purse, worker, or custody write.
## The shared payment journal is read before either branch. No rules are copied.
## The next hull uid is checked before either branch.
## A legacy or site wreck stages disabled installed gear before either branch returns.
## An active wreck keeps its condition, loadout, birth, and source wreck id.
## Hull hp is the fitted tow contract.

const Lifecycle = preload("res://scripts/equipment_lifecycle.gd")
const Recovery = preload("res://scripts/equipment_recovery.gd")
const EquipmentService = preload("res://scripts/equipment_service.gd")

static func contract(spec: Dictionary, loadout) -> Dictionary:
	return Lifecycle.tow_contract(spec, loadout)

static func stage(core, state: Dictionary, wreck: Dictionary, spec: Dictionary) -> Dictionary:
	var journal_problem: String = EquipmentService.journal_error(state)
	if not journal_problem.is_empty():
		return {"ok": false, "message": journal_problem, "error": journal_problem}
	var named: Dictionary = Lifecycle.next_hull_uid(state)
	if not bool(named.get("ok", false)):
		return named
	var priced: Dictionary = contract(spec, wreck.get("sourceLoadout", {}))
	if not bool(priced.get("ok", false)):
		return priced
	if core == null or not (core.get("data") is Dictionary):
		return {"ok": false, "message": "Birth inputs are missing.", "error": "Birth inputs are missing."}
	var identity := str(named.get("uid", ""))
	if not Recovery.is_active(wreck):
		var legacy: Dictionary = Lifecycle.stage_legacy_recovery(state, core.data, spec, identity, wreck.get("sourceLoadout", {}))
		if not bool(legacy.get("ok", false)):
			return legacy
		legacy.restoring = false
		legacy.contract = priced
		return legacy
	var preserved := {
		"moduleCondition": wreck.sourceModuleCondition.duplicate(true),
		"loadout": wreck.get("sourceLoadout", {}).duplicate(true) if wreck.get("sourceLoadout", {}) is Dictionary else {},
		"hullHp": float(priced.hullHp),
		"sourceWreckId": str(wreck.get("id", ""))
	}
	var staged: Dictionary = Lifecycle.stage_birth(state, core.data, spec, identity, preserved)
	if not bool(staged.get("ok", false)):
		return staged
	staged.restoring = true
	staged.contract = priced
	return staged
