extends RefCounted
## Presentation memory only. It never changes campaign records or settles work.
const Refits = preload("res://scripts/refit.gd")

var enabled: bool = true
var battle_introduced: bool = false
var command_seen: bool = false
var earned: bool = false
var paid_fit: bool = false
var last_payment: int = 0
var last_fit_cost: int = 0
var objective: String = ""
var offer_reinvestment: bool = false

func begin(c, fresh: bool = false) -> void:
	enabled = true
	battle_introduced = false
	command_seen = false
	last_payment = 0
	last_fit_cost = 0
	objective = ""
	earned = false
	paid_fit = false
	offer_reinvestment = false
	if fresh: return
	# These records are written by the existing settlement authorities. A closed
	# voyage-job id alone is insufficient: abandonment also closes those ids.
	for row in c.state.get("moneyLog", []):
		if not row is Dictionary: continue
		if str(row.get("to", "")) == "coins" and str(row.get("reason", "")) in ["Contract payment from escrow", "Voyage job payment from escrow"] and int(row.get("cash", 0)) > 0:
			earned = true
			if last_payment == 0: last_payment = int(row.cash)
		if str(row.get("reason", "")) == "Workshop shipwright wages" and str(row.get("from", "")) == "coins" and int(row.get("cash", 0)) > 0:
			paid_fit = true
	if int(c.state.get("missionIndex", 0)) > 0 or not c.state.get("doneSide", []).is_empty(): earned = true
	# A spent workshop bill is not proof its fitting is still installed.
	paid_fit = paid_fit and has_changed_fit(c)
	battle_introduced = earned

func observe_payment(result: Dictionary, before: int, after: int) -> void:
	var amount: int = int(result.get("reward", 0))
	if result.get("ok", false) and amount > 0 and after - before == amount:
		if not earned: offer_reinvestment = true
		earned = true
		last_payment = amount

func observe_battle_payment(c, original: Dictionary, before: int) -> void:
	# Native battle settlement completes combat contracts and may also pay
	# captured coins. Do not mistake the combined loot report for the job fee.
	if original.is_empty() or not c.state.get("activeContract", {}).is_empty(): return
	var amount: int = int(original.get("escrow", 0))
	if amount <= 0 or amount != int(original.get("reward", 0)) or int(c.state.get("coins", 0)) - before < amount: return
	var closed: bool = c.state.get("doneSide", []).has(str(original.get("id", "")))
	if original.get("story", false):
		var index: int = int(c.state.get("missionIndex", 0)) - 1
		closed = index >= 0 and index < c.data.MISSIONS.size() and str(c.data.MISSIONS[index].get("id", "")) == str(original.get("id", ""))
	if not closed: return
	for row in c.state.get("moneyLog", []):
		if row is Dictionary and str(row.get("reason", "")) == "Contract payment from escrow" and str(row.get("to", "")) == "coins" and int(row.get("cash", 0)) == amount:
			if not earned: offer_reinvestment = true
			earned = true
			last_payment = amount
			return

func observe_fit(result: Dictionary, before: int, after: int) -> void:
	var cost: int = int(result.get("cost", 0))
	if result.get("ok", false) and result.get("changed", false) and cost > 0 and before - after == cost:
		paid_fit = true
		last_fit_cost = cost

static func has_changed_fit(c) -> bool:
	for boat in c.state.get("fleet", []):
		if not boat is Dictionary or boat.get("sunk", false): continue
		var base: Dictionary = c.hull(str(boat.get("type", "")))
		var fit: Dictionary = Refits.normalize(base, boat.get("loadout", {}))
		if fit.get("ok", false) and fit.loadout != Refits.defaults(base): return true
	return false

static func _card(title: String, reason: String, action: String, caption: String, extra: Dictionary = {}) -> Dictionary:
	return {"title":title, "reason":reason, "action":action, "caption":caption}.merged(extra)

static func _port_name(c, id: String) -> String:
	return str(c.port(id).get("name", "the sponsoring harbor"))

func status(host) -> Dictionary:
	var c = host.core
	if c == null or c.state.is_empty(): return {}
	if host.mode == "battle":
		var reason: String = "Select your boat, choose Focus attack, then right-click an enemy. Space resumes. Autopilot handles the helm."
		if command_seen: reason = "Your order was accepted. Watch the target and firing arcs; pull back or order fleet escape if the fight turns."
		return _card("Give the first order" if not command_seen else "Watch your order take effect", reason, "battle", "Battle guidance")
	# Existing commitments always take priority over suggestions for new work.
	var contract: Dictionary = c.state.get("activeContract", {})
	if not contract.is_empty():
		var arrived: bool = c.contract_ready()
		var caption: String = "Review local contract"
		var reason: String = "Sail to %s. Keep food, working fuel and return wages aboard." % _port_name(c, str(contract.get("targetPort", "")))
		if arrived:
			reason = "Collect the sponsor's escrow at this harbor." if contract.get("cleared", false) else "The contract's hostile boats are here. Pause, select your boat and choose a target."
		return _card(str(contract.get("title", "Local contract")), reason, "contract", caption, {"id":str(contract.get("id", ""))})
	for raw in c.state.get("voyageJobs", []):
		if not raw is Dictionary: continue
		var job: Dictionary = raw
		var reason: String = "Deliver to %s, then claim the held fee." % _port_name(c, str(job.get("targetPort", "")))
		match str(job.get("kind", "")):
			"escort": reason = "Stay with the original loaded convoy. Protect its exit during an attack; report after its delivery."
			"survey": reason = "Chart and fully survey the named island, then report to %s." % _port_name(c, str(job.get("port", "")))
			"bounty": reason = "Defeat the named raider fleet, then report to %s." % _port_name(c, str(job.get("port", "")))
		var dock: Dictionary = c.work_port070()
		var destination: bool = str(dock.get("id", "")) == str(job.get("targetPort", "")) and not dock.is_empty()
		var survey_done: bool = int(c.state.get("exploration", {}).get("sites", {}).get(str(job.get("siteId", "")), {}).get("level", 0)) >= 3
		var claim: bool = str(job.get("kind", "")) == "freight" and destination
		if str(job.get("kind", "")) == "survey": claim = survey_done and not dock.is_empty() and str(dock.get("id", "")) == str(job.get("port", ""))
		if str(job.get("kind", "")) == "escort": claim = destination and job.get("escort", {}).get("arrived", false) and not job.get("escort", {}).get("battlePending", false)
		if claim and not job.get("failed", false) and str(job.get("state", "")) == "active":
			return _card(str(job.get("title", "Paid voyage")), "Report this actual delivery or completed work to release its held fee.", "collect_job", "Report and collect fee", {"id":str(job.get("id", ""))})
		if job.get("failed", false) or str(job.get("state", "")) == "expired": reason = "This job cannot be paid. Review its terms and unload or close it at a harbor."
		return _card(str(job.get("title", "Paid voyage")), reason, "job", "Review this job", {"id":str(job.get("id", ""))})
	for boat in c.active_fleet():
		if float(boat.get("water", 0.0)) > 1.0 or float(boat.get("fire", 0.0)) > 0.0 or float(boat.get("hp", 0.0)) < float(boat.get("maxHp", 1.0)) * 0.5:
			return _card("Repair before the next job", "%s needs attention. Inspect paid repairs and keep money for crew and stores." % str(boat.get("name", "Your boat")), "repairs", "Review damage and repairs")
	if not c.home_local064():
		if not c.work_port070().is_empty():
			return _card("Find paid work on this coast","Compare funded freight and survey jobs here. Discoveries and delivered cargo affect this coast; keep the trip home supplied.","remote_work","Review island work")
		return _card("Explore this coast and plan the return","Survey islands, investigate wrecks and reach a harbor for funded work. Keep the return route and supplies in your plan.","ocean","Plan route and return")
	if not objective.is_empty():
		match objective:
			"escort": return _card("Protect a loaded convoy", "Hail a nearby friendly loaded convoy. Its client must fund the fee; staying with its actual carriers earns payment.", "escort", "Find escort work")
			"freight": return _card("Carry a paid freight lot", "Compare a small sealed load, destination and return costs before accepting. Delivery changes the destination's stock.", "freight", "Compare freight work")
			"survey": return _card("Fund a survey and return", "Compare the fee with spare crew, kits, time and return supplies. Pick a site you can afford to finish.", "survey", "Review survey work")
			"campaign": return _card("Follow Common Passage", "Open the campaign journal for the next conversation or earned voyage. Local contracts remain separate paid work.", "campaign", "Open Common Passage")
	if not earned:
		return _card("Earn the first contract payment", "Clear the Lantern Narrows pays only after its real fight and delivery. Review the destination, fee and return reserve first.", "contract", "Review first local contract")
	if not paid_fit:
		return _card("Put paid work into a useful fitting", "Compare light armor, keep your current equipment or inspect a different fitting. Leave money and stores for the next departure.", "fit", "Review a paid fitting")
	return _card("Choose a different next voyage", "Protect loaded carriers, deliver freight, survey an island or follow Common Passage. Choose the work before buying more equipment.", "choose", "Choose next work")
