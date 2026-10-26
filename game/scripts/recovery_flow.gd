extends RefCounted
## Small Main/UI adapter. Campaign and Salvage keep ownership of recovery rules.
const Battle=preload("res://scripts/battle.gd")
const Objectives=preload("res://scripts/battle_objectives.gd")

static func is_convoy(battle: Dictionary) -> bool:
	return str(battle.get("mission",{}).get("kind","")) in ["escort","intercept"]

static func objective_label(battle: Dictionary) -> String:
	if is_convoy(battle):return str(Battle.objective_snapshot(battle).get("label","Reach the physical exit zone."))
	return Objectives.label(battle)

static func wreck_ids(report: Dictionary) -> Array:
	var ids: Array=[]
	for wreck in report.get("wrecks",[]):
		var id: String=str(wreck.get("id",""))
		if not id.is_empty() and not id in ids:ids.append(id)
	return ids

static func recover(host,id: String,choice: String,good: String="",qty: float=0.0) -> Dictionary:
	# Leaving a wreck for later never calls Campaign.recover_wreck or advances time.
	if host.mode!="campaign" or choice not in ["tow","strip"]:
		return {"ok":false,"message":"Return to the coast and choose tow or strip. Leaving the wreck marked needs no recovery work."}
	host.sync_economy()
	var result: Dictionary=host.core.recover_wreck(id,choice,good,qty)
	host.respond(result)
	if result.get("ok",false):
		host.start_economy()
		host.sync_economy()
		host.save_game(false)
	return result
