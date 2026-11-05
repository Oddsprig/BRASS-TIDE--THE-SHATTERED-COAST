extends RefCounted
const AI = preload("res://scripts/naval_ai.gd")
const Orders = preload("res://scripts/naval_orders.gd")
const Factions = preload("res://scripts/factions.gd")
const WATCH_RADIUS: float = 1800.0


static func can_hail(state: Dictionary, sighting: Dictionary) -> bool:
	# A dated sample never grants remote access to the live encounter window.
	if not bool(sighting.get("current", false)) or bool(sighting.get("expired", true)):
		return false
	if float(state.get("day", 1.0)) >= float(sighting.get("expiresDay", 0.0)):
		return false
	var id: String = str(sighting.get("ownerId", ""))
	var patrol: Dictionary = Orders.find_patrol(state, id)
	var owner: Dictionary = Orders.find_owner(state, id)
	if bool(patrol.get("hidden", false)) or not bool(patrol.get("active", false)) or not bool(owner.get("active", false)) or Orders.living_boats(owner).is_empty():
		return false
	var position: Dictionary = state.get("position", {})
	if not position.has("x") or not position.has("y") or not patrol.has("x") or not patrol.has("y"):
		return false
	return Vector2(float(position.x), float(position.y)).distance_to(Vector2(float(patrol.x), float(patrol.y))) <= WATCH_RADIUS


static func purpose_text(sighting: Dictionary) -> String:
	# Use only the observation contract, never an owner's live reason/ledger.
	match str(sighting.get("purpose", "")):
		"escort": return "Guarding a convoy along its last observed route."
		"intercept": return "Responding to a locally sighted hostile fleet."
		"raid": return "Seeking a prize along locally observed shipping lanes."
		"withdraw": return "Withdrawing for paid repairs and stores after damage or depletion."
		"repair": return "Seeking paid harbor repairs before returning to sea."
		"replace": return "Recovering from hull losses; replacements require a funded home yard."
		"resupply": return "Returning for stores before the next voyage."
		"deliver", "trade": return "Carrying a loaded shipment." if bool(sighting.get("loaded", false)) else "Sailing a trading route."
		"blockade": return "Maintaining a coastal blockade station."
	return "Watching a coastal sea lane."


static func report(state: Dictionary) -> Dictionary:
	var contacts: Array = []
	for sighting in AI.observe(state):
		var current: bool = can_hail(state, sighting)
		var expired: bool = bool(sighting.get("expired", true))
		var status: String = "Current contact" if current else ("Expired sighting" if expired else "Old intelligence")
		# This presentation projection deliberately excludes even last-known x/y.
		contacts.append({
			"ownerId": str(sighting.get("ownerId", "")), "name": str(sighting.get("name", "Unknown fleet")),
			"faction": str(sighting.get("faction", "")), "purpose": str(sighting.get("purpose", "patrol")),
			"day": float(sighting.get("day", 1.0)), "ageDays": float(sighting.get("ageDays", 0.0)),
			"expiresDay": float(sighting.get("expiresDay", 0.0)), "expired": expired, "current": current,
			"status": status, "destination": str(sighting.get("destination", "")),
			"reason": purpose_text(sighting)
		})
	var outcomes: Array = []
	var nav: Dictionary = state.get("navalAi", {})
	for event in nav.get("encounters", []):
		if not bool(event.get("witnessed", false)):
			continue
		var detail: String = str(event.get("summary", "Coastal engagement."))
		if event.has("survivorsA") and event.has("survivorsB"):
			detail += " %d / %d hulls survived." % [int(event.survivorsA), int(event.survivorsB)]
		if int(event.get("capturedQty", 0)) > 0:
			detail += " %d %s changed hands." % [int(event.capturedQty), str(event.get("capturedGood", "goods"))]
		outcomes.append({"day": float(event.get("day", 1.0)), "detail": detail})
		if outcomes.size() >= 6:
			break
	return {"contacts": contacts, "outcomes": outcomes}


static func hail(ui, sighting: Dictionary) -> void:
	ui.host.sync_economy()
	if not can_hail(ui.host.core.state, sighting):
		ui.toast("Contact lost. Check the dated traffic report for the last sighting.")
		open(ui)
		return
	var c=ui.host.core
	var owner: Dictionary=c.fleet_owner(str(sighting.ownerId))
	if not c.EscortOps.contracted(c,str(sighting.ownerId)).is_empty() or (owner.get("kind","")=="trader" and float(owner.get("tradeCargo",0))>0 and not c.Politics.hostile(c,owner)):
		c.EscortOps.review(ui,str(sighting.ownerId));return
	ui.host.show_patrol_encounter(str(sighting.ownerId))


static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	var observed: Dictionary = report(c.state)
	ui.modal_kind="sea_traffic"
	var body=ui.modal("Coastal traffic","LOCAL WATCH AND DATED INTELLIGENCE",1040,800)
	ui.paragraph(body,"Day %.2f · Reports show what your lookout last saw. Old intelligence keeps its observed purpose and route; it does not follow a distant fleet. Only a current local contact can be hailed." % float(c.state.day),16)
	var escort: Dictionary=c.EscortOps.contracted(c)
	if not escort.is_empty():ui.button(body,"Review active paid escort",func():c.EscortOps.review(ui,str(escort.ownerId)))
	if observed.contacts.is_empty():
		ui.paragraph(body,"No fleets have been sighted by your current watch. Sail closer to a coastal route to gather intelligence.",17)
	for sighting in observed.contacts:
		ui.rule(body)
		ui.label(body,"%s · %s" % [sighting.name, str(sighting.purpose).capitalize()],23,ui.GOLD,true)
		ui.paragraph(body,"%s · seen day %.2f · %.2f days ago" % [sighting.status, float(sighting.day), float(sighting.ageDays)],14)
		ui.paragraph(body,str(sighting.reason),16)
		var destination: String = str(sighting.destination)
		var route: String = "Last signaled toward %s." % str(c.port(destination).get("name", destination)) if not destination.is_empty() else "No destination observed."
		ui.paragraph(body,"%s · %s" % [str(Factions.CANON_NAMES.get(str(sighting.faction), "Unidentified colors")), route],14)
		if bool(sighting.current):
			ui.button(body,"Hail this fleet",func():hail(ui,sighting))
		else:
			ui.paragraph(body,"Position and purpose may have changed. Reacquire the fleet locally before hailing.",14)
	ui.rule(body)
	ui.label(body,"Witnessed outcomes",23,ui.GOLD,true)
	if observed.outcomes.is_empty():
		ui.paragraph(body,"No engagements witnessed by your lookout. Distant reports are not confirmed outcomes.",15)
	for event in observed.outcomes:
		ui.paragraph(body,"Day %.2f · %s" % [float(event.day), str(event.detail)],15)
	ui.button(body,"Refresh local watch",func():open(ui))
