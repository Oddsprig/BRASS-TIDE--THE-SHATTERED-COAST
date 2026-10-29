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

static func recover(host,id: String,choice: String,good: String="",qty: float=0.0,request: Dictionary={}) -> Dictionary:
	# Leaving a wreck for later never calls Campaign.recover_wreck or advances time.
	if host.mode!="campaign" or choice not in ["tow","strip","gear"]:
		return {"ok":false,"message":"Return to the coast and choose tow, strip or selected equipment. Leaving the wreck marked needs no recovery work."}
	# Selected recovery settles pending ordinary economy on a private campaign.
	# A declined/refused selection must not charge even an unrelated pending day.
	# Main already debited an in-flight worker's pending day. Its old port result
	# must finish normally before a new private transaction can own that day.
	var remote: bool=not host.core.home_local064()
	if (choice=="gear" or remote) and int(host.economy_task)>=0:
		var busy: Dictionary={"ok":false,"message":"A normal economy day is still settling. Let it finish, then retry selected recovery; no recovery work was charged."}
		host.respond(busy)
		return busy
	if choice!="gear" and not remote:host.sync_economy()
	var result: Dictionary=host.core.recover_wreck(id,choice,good,qty,request)
	host.respond(result)
	if remote and not result.get("completed",false) and host.core.events.any(func(event):return str(event.get("kind","")) in ["encounter","ocean_encounter066","defeat"]):
		host.ui.close_modal()
		host.handle_campaign_events067()
		return result
	if result.get("ok",false) or (remote and float(result.get("elapsedDays",0))>0):
		host.start_economy()
		host.sync_economy()
		host.save_game(false)
	return result
