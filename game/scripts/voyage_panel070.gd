extends RefCounted
## Display adapter for the funded-work board. Reads existing quotes and the
## live work berth. It does not price, accept, buy, or install anything.
const Choices = preload("res://scripts/civilian_choices059.gd")
const Identity = preload("res://scripts/fleet_identity.gd")
const Refit = preload("res://scripts/refit.gd")

const FITTINGS := ["cargo_rig", "survey_rig", "workshop_rig", "auxiliary_tanks"]


static func region_name(c) -> String:
	if c != null and c.has_method("world_view064"):
		var view: Dictionary = c.world_view064()
		return str(view.get("name", "")).strip_edges()
	return ""


static func work_berth(c) -> Dictionary:
	if c != null and c.has_method("work_port070"):
		var berth = c.work_port070()
		if berth is Dictionary:
			return berth
	return {}


static func service_berth(c) -> Dictionary:
	if c != null and c.has_method("current_port"):
		var port = c.current_port()
		if port is Dictionary:
			return port
	return {}


static func board_header(c) -> Dictionary:
	var work := work_berth(c)
	var service := service_berth(c)
	var kind := ""
	var port := {}
	if not work.is_empty() and not str(work.get("id", "")).is_empty():
		port = work
		kind = "work"
	elif not service.is_empty():
		port = service
		kind = "home"
	return {
		"name": str(port.get("name", "")),
		"id": str(port.get("id", "")),
		"kind": kind,
		"region": region_name(c),
		"docked": not str(port.get("name", "")).is_empty(),
	}


static func listed_offers(c) -> Array:
	if c == null or c.VoyageJobs == null:
		return []
	var listed: Array = c.VoyageJobs.available(c)
	var work := work_berth(c)
	if work.is_empty():
		return listed
	var work_id := str(work.get("id", ""))
	if work_id.is_empty():
		return listed
	var service_id := str(service_berth(c).get("id", ""))
	if service_id == work_id:
		return listed
	var matched: Array = []
	for item in listed:
		if item is Dictionary and str(item.get("port", "")) == work_id:
			matched.append(item)
	return matched


static func route_target(c, job: Dictionary) -> Dictionary:
	var empty := {"ok": false, "label": "", "point": {}, "destination": ""}
	if c == null or not c.has_method("port"):
		return empty
	var kind := str(job.get("kind", ""))
	var site_id := str(job.get("siteId", ""))
	if kind == "survey" and not site_id.is_empty() and _survey_level(c, site_id) < 3:
		if c.Exploration == null or not c.Exploration.has_method("catalog_site"):
			return empty
		var site: Dictionary = c.Exploration.catalog_site(c.state, site_id)
		if site.is_empty():
			return empty
		var earned := true if not job.has("earned") else bool(job.earned)
		var label := str(site.get("name", str(job.get("title", "landing")))) if earned else "the offered landing"
		return {"ok": true, "label": label, "point": site, "destination": ""}
	var port_id := str(job.get("targetPort", ""))
	if port_id.is_empty():
		return empty
	var harbor: Dictionary = c.port(port_id)
	if harbor.is_empty():
		return empty
	return {"ok": true, "label": str(harbor.get("name", port_id)), "point": harbor, "destination": port_id}


static func quote_view(c, offer: Dictionary) -> Dictionary:
	var gross := int(offer.get("grossFee", offer.get("reward", 0))) if offer.has("grossFee") else int(offer.get("reward", 0))
	var running_set := offer.has("operatingCost")
	var running := int(offer.get("operatingCost", 0))
	var reserves_set := offer.has("returnReserves")
	var reserves := int(offer.get("returnReserves", 0))
	var surplus_set := offer.has("likelySurplus")
	var surplus := int(offer.get("likelySurplus", 0))
	var afford_note := str(offer.get("affordNote", ""))
	var afford_short := -1
	var hold := ""
	var berths := ""
	if str(offer.get("kind", "")) in Choices.CIVILIAN_KINDS and c != null:
		var model: Dictionary = Choices.job_review(c, offer, "")
		if model.get("ok", false):
			var budget: Dictionary = model.get("budget", {})
			if not running_set:
				running = int(budget.get("operatingCost", 0))
				running_set = true
			if not reserves_set:
				reserves = int(budget.get("reserveFunding", 0))
				reserves_set = true
			if not surplus_set:
				surplus = int(model.get("estimatedNet", 0))
				surplus_set = true
			if afford_note.is_empty():
				afford_short = int(budget.get("fundingShortfall", 0))
			var carrier := str(model.get("carrierName", "the carrier"))
			if str(offer.get("kind", "")) == "passenger_charter":
				berths = "%d passengers on the offer · %d spare berths on %s" % [int(model.get("passengers", 0)), int(model.get("spareBerths", 0)), carrier]
				hold = "Dedicated rations %.2f · %.2f hold free on that hull · %.2f fleet hold free" % [float(model.get("passengerFood", 0)), float(model.get("holdFree", 0)), float(model.get("fleetHoldFree", 0))]
			else:
				hold = "%.1f hold for the sealed load · %.2f free on %s · %.2f fleet hold free" % [float(model.get("loadWeight", 0)), float(model.get("holdFree", 0)), carrier, float(model.get("fleetHoldFree", 0))]
				berths = "%d spare berths on %s" % [int(model.get("spareBerths", 0)), carrier]
	if offer.has("holdNeed"):
		hold = "Hold need %.1f" % float(offer.holdNeed)
	if offer.has("passengerNeed") or offer.has("spareBerths"):
		var people := str(int(offer.passengerNeed)) + " passengers" if offer.has("passengerNeed") else "Passenger count is on the offer terms"
		var spare := str(int(offer.spareBerths)) + " spare berths" if offer.has("spareBerths") else "spare berths are on the carrier line"
		berths = "%s · %s" % [people, spare]
	if hold.is_empty():
		var kind := str(offer.get("kind", ""))
		if kind == "survey":
			hold = "No cargo lot is reserved. The survey terms name spare sailors and kits."
		elif kind == "bounty":
			hold = "No hold space or passenger berth is reserved for this bounty."
		elif not kind.is_empty():
			hold = "Hold and passenger berths are not stated on this offer."
	return {
		"place": place_line(c, offer),
		"gross": gross,
		"runningSet": running_set,
		"running": running,
		"reservesSet": reserves_set,
		"reserves": reserves,
		"surplusSet": surplus_set,
		"surplus": surplus,
		"affordNote": afford_note,
		"affordShort": afford_short,
		"hold": hold,
		"berths": berths,
	}


static func place_line(c, offer: Dictionary) -> String:
	var earned := true if not offer.has("earned") else bool(offer.earned)
	var origin_name := "the sponsoring harbor"
	if c != null and c.has_method("port"):
		origin_name = str(c.port(str(offer.get("port", ""))).get("name", origin_name))
	var route := route_target(c, offer)
	var dest := "no recorded destination"
	if route.ok:
		dest = str(route.label) if earned else "the offered destination"
	var region := ""
	if earned and offer.has("targetRegionName"):
		region = str(offer.targetRegionName).strip_edges()
	elif earned:
		region = _same_chart_name(c, route)
	return "%s → %s%s" % [origin_name, dest, " · %s" % region if not region.is_empty() else ""]


static func fleet_notes(c) -> Array:
	var notes: Array = []
	if c == null or not c.has_method("active_fleet"):
		return ["Fleet role notes need a loaded campaign."]
	var conversions: Dictionary = Identity.conversions()
	var roles: Dictionary = Identity.roles()
	var scout_seen := false
	var catalog: Dictionary = {}
	var boats: Array = c.active_fleet()
	for boat in boats:
		if not boat is Dictionary:
			continue
		var spec: Dictionary = boat.get("spec", {}) if boat.get("spec") is Dictionary else {}
		var name := str(boat.get("name", "Boat"))
		var role := str(spec.get("civilianRole", ""))
		var role_text := _role_line(role)
		if role_text.is_empty():
			var hull_role := str(spec.get("role", ""))
			role_text = "Hull role %s." % hull_role if not hull_role.is_empty() else "Working boat."
		notes.append("%s · %s" % [name, role_text])
		var fitted := str(boat.get("conversion", ""))
		if conversions.has(fitted):
			var info: Dictionary = conversions[fitted]
			notes.append("%s: %s" % [str(info.get("name", fitted)), str(info.get("trade", ""))])
		var active: Dictionary = boat.get("specialistActive", {}) if boat.get("specialistActive") is Dictionary else {}
		if bool(active.get("surveyor", false)):
			var surveyor: Dictionary = roles.get("surveyor", {})
			notes.append("Surveyor aboard %s. Daily premium %d coins, %s." % [name, int(surveyor.get("premium", 0)), str(surveyor.get("basis", "published specialist rate"))])
		if bool(active.get("chief_engineer", false)):
			notes.append("Chief engineer aboard %s. Underway repair still consumes kits." % name)
		var armor := ""
		if boat.get("loadout") is Dictionary:
			armor = str(boat.loadout.get("armor", ""))
		if armor == "scout_plating":
			scout_seen = true
			if catalog.is_empty():
				catalog = Refit.catalog()
			var described: Dictionary = catalog.get("armor", {}).get("scout_plating", {})
			notes.append("%s carries %s. %s" % [name, str(described.get("name", "Scout plating")), str(described.get("description", ""))])
	if not scout_seen:
		notes.append("Scout plating is an armor fitting. No traveling hull has it fitted, so this estimate includes no scout-plating change.")
	notes.append_array(_fitting_quotes(c, boats, conversions))
	notes.append("Role lines and cost estimates follow the traveling fleet, stores and fittings you have now.")
	return notes


static func _role_line(role: String) -> String:
	match role:
		"transport":
			return "Transport hull. Existing fuel jobs take a transport or a tanker. Existing passenger jobs take a transport or a yacht."
		"tanker":
			return "Tanker hull. Existing fuel jobs take a tanker or a transport. Fuel loaded through Cargo stays in that boat's tank."
		"yacht":
			return "Yacht hull. Existing passenger jobs take a yacht or a transport. Spare berths are the bunks left after the crew."
		"fishing":
			return "Fishing hull. It works from the fishing board, then sells whole lots at a market you are docked in."
		_:
			return ""


static func _fitting_quotes(c, boats: Array, conversions: Dictionary) -> Array:
	var service := service_berth(c)
	var work := work_berth(c)
	if service.is_empty():
		return ["Cargo, survey, workshop and auxiliary-tank prices are quoted at a home service harbor."]
	if not work.is_empty() and str(work.get("id", "")) != str(service.get("id", "")):
		return ["Fitting prices are from %s. The work berth is %s." % [str(service.get("name", "the home harbor")), str(work.get("name", "this berth"))]]
	var lines: Array = []
	for id in FITTINGS:
		var uid := ""
		var boat_name := ""
		for boat in boats:
			if not boat is Dictionary:
				continue
			if str(boat.get("conversion", "")) == id:
				continue
			uid = str(boat.get("uid", ""))
			boat_name = str(boat.get("name", "Boat"))
			break
		if uid.is_empty():
			continue
		var quote: Dictionary = Identity.quote_conversion(c, uid, id)
		var title := str(conversions.get(id, {}).get("name", id))
		lines.append("%s on %s · quoted at %s. %s" % [title, boat_name, str(service.get("name", "this harbor")), str(quote.get("message", ""))])
	return lines


static func _survey_level(c, site_id: String) -> int:
	var exploration = c.state.get("exploration", {}) if c.state is Dictionary else {}
	if not exploration is Dictionary:
		return 0
	var sites = exploration.get("sites", {})
	if sites is Dictionary and sites.get(site_id) is Dictionary:
		return int(sites[site_id].get("level", 0))
	return 0


static func _same_chart_name(c, route: Dictionary) -> String:
	if c == null or not c.has_method("world_view064") or not bool(route.get("ok", false)):
		return ""
	var view: Dictionary = c.world_view064()
	var name := str(view.get("name", "")).strip_edges()
	if name.is_empty():
		return ""
	var point: Dictionary = route.point if route.get("point") is Dictionary else {}
	var region_id := str(point.get("regionId", ""))
	var view_id := str(view.get("regionId", ""))
	if region_id.is_empty() or view_id.is_empty() or region_id == view_id:
		return name
	return ""
