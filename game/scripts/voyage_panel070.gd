extends RefCounted
## Display adapter for the funded-work board. One selected row may call
## VoyageJobs.offer_view070. This file does not price, accept, buy, or install.
const Identity = preload("res://scripts/fleet_identity.gd")
const Refit = preload("res://scripts/refit.gd")
const Exploration = preload("res://scripts/exploration.gd")

const FITTINGS := ["cargo_rig", "survey_rig", "workshop_rig", "auxiliary_tanks"]
const HOME_REGION := "shatter_coast"


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
	var named := not str(work.get("id", "")).is_empty() and not str(work.get("name", "")).is_empty()
	var home: bool = named and c != null and c.has_method("home_local064") and c.home_local064()
	return {
		"name": str(work.get("name", "")),
		"id": str(work.get("id", "")),
		"kind": "home" if home else ("work" if named else ""),
		"region": region_name(c),
		"docked": named,
		"berthKnown": c != null and c.has_method("work_port070"),
	}


static func listed_offers(c) -> Array:
	if c == null or c.VoyageJobs == null:
		return []
	var listed: Array = c.VoyageJobs.available(c)
	if not c.has_method("work_port070"):
		return listed
	var work := work_berth(c)
	var work_id := str(work.get("id", ""))
	if work_id.is_empty():
		return []
	var matched: Array = []
	for item in listed:
		if item is Dictionary and str(item.get("port", "")) == work_id:
			matched.append(item)
	return matched


static func selected_quote(c, offer: Dictionary) -> Dictionary:
	var gross := int(offer.get("reward", 0))
	if c == null or c.VoyageJobs == null or not c.VoyageJobs.has_method("offer_view070"):
		return {
			"ok": false,
			"routeOk": false,
			"quoted": false,
			"message": "This campaign has no selected voyage quote yet. The published gross fee still stands. No home-waters route was substituted.",
			"grossFee": gross,
			"kind": str(offer.get("kind", "")),
			"offerId": str(offer.get("id", "")),
		}
	var view = c.VoyageJobs.offer_view070(c, offer)
	if view is Dictionary:
		return view
	return {"ok": false, "routeOk": false, "quoted": false, "message": "The selected voyage quote did not return a reading.", "grossFee": gross, "kind": str(offer.get("kind", ""))}


static func origin_name(c, offer: Dictionary) -> String:
	if c != null and c.has_method("port"):
		var harbor: Dictionary = c.port(str(offer.get("port", "")))
		var name := str(harbor.get("name", "")).strip_edges()
		if not name.is_empty():
			return name
	return "the sponsoring harbor"


static func destination_name(c, offer: Dictionary) -> String:
	if str(offer.get("kind", "")) == "survey":
		return _landing_name(c, str(offer.get("siteId", "")))
	var port_id := str(offer.get("targetPort", ""))
	if c != null and c.has_method("port") and not port_id.is_empty():
		var harbor: Dictionary = c.port(port_id)
		var name := str(harbor.get("name", "")).strip_edges()
		if not name.is_empty():
			return name
	return "the destination harbor"


static func prepare_ready(c, view: Dictionary) -> bool:
	var action := _action(view)
	var kind := str(action.get("kind", "none"))
	if not bool(view.get("routeOk", false)):
		return false
	if kind == "transition":
		return not str(action.get("approachId", "")).is_empty()
	if kind != "course":
		return false
	if not str(action.get("approachId", "")).is_empty():
		return true
	if not _same_chart_target(action):
		return false
	var region := str(action.get("regionId", ""))
	var here := _view_region(c)
	return not here.is_empty() and region == here


static func prepare_label(view: Dictionary) -> String:
	var title := str(_action(view).get("title", "")).strip_edges()
	if title.is_empty():
		return "Prepare route"
	return "Prepare route · %s" % title


static func prepare_from_quote(ui, view: Dictionary) -> void:
	var c = ui.host.core
	if not prepare_ready(c, view):
		_respond(ui, str(view.get("message", "No further course is available from this chart.")))
		return
	# The host joins pending work and re-quotes the actual job before mutation.
	ui.host.prepare_voyage_job070(str(view.get("offerId","")))


static func prepare_known_point(ui, point: Dictionary, destination: String = "") -> void:
	ui.host.sync_economy()
	var c = ui.host.core
	if c == null or not point is Dictionary:
		return
	var point_region := str(point.get("regionId", ""))
	var here := _view_region(c)
	var home_here: bool = c.has_method("home_local064") and c.home_local064()
	var home_point := point_region.is_empty() or point_region == HOME_REGION
	var same: bool = point_region.is_empty() or point_region == here or (home_here and home_point and (here.is_empty() or here == HOME_REGION))
	if not same:
		if not point_region.is_empty():
			ui.open_voyage_preparation065(point_region)
		else:
			_respond(ui, "That place is not on the current chart.")
		return
	if not destination.is_empty() and home_here:
		ui.host.sail_to(destination)
		ui.close_modal()
		return
	var result: Dictionary=c.chart_course(point,destination)
	ui.host.respond(result)
	if result.get("ok",false):ui.host.save_game(false);ui.close_modal()


static func leg_lines(view: Dictionary) -> Array:
	var lines: Array = []
	var legs = view.get("legs", [])
	if not legs is Array:
		return lines
	for leg in legs:
		if not leg is Dictionary:
			continue
		var phase := str(leg.get("phase", "step")).capitalize()
		if str(leg.get("kind", "")) == "transition":
			var gate := str(leg.get("approachId", "")).strip_edges()
			lines.append("%s: cross by the %s approach." % [phase, gate if not gate.is_empty() else "marked"])
		else:
			lines.append("%s: sail the current chart." % phase)
	return lines


static func support_lines(view: Dictionary) -> Array:
	var lines: Array = []
	var roles = view.get("supportRoles", [])
	if not roles is Array:
		return lines
	for row in roles:
		if not row is Dictionary or not bool(row.get("available", false)):
			continue
		var benefit := str(row.get("benefit", "")).strip_edges()
		if benefit.is_empty():
			continue
		lines.append("%s · %s" % [str(row.get("role", "role")).capitalize(), benefit])
	return lines


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
	notes.append("Role lines follow the traveling fleet and fittings you have now. Voyage costs are on the job you review.")
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
		"scout":
			return "Scout hull. A fitted survey factor can shorten shore work. Spare sailors and kits are still required."
		"repair":
			return "Repair hull. A fitted repair factor uses real kits. It does not supply free repairs."
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


static func _landing_name(c, site_id: String) -> String:
	var level := _saved_site_level(c, site_id)
	if level >= Exploration.LEVEL_CHARTED and c != null and c.Exploration != null:
		var site: Dictionary = c.Exploration.catalog_site(c.state, site_id)
		var name := str(site.get("name", "")).strip_edges()
		if not name.is_empty():
			return name
	if level >= Exploration.LEVEL_SIGHTED:
		return "Uncharted shore landmark"
	return "the offered landing"


static func _saved_site_level(c, site_id: String) -> int:
	if c == null or site_id.is_empty() or not c.state is Dictionary:
		return 0
	var exploration = c.state.get("exploration", {})
	if not exploration is Dictionary:
		return 0
	var sites = exploration.get("sites", {})
	if sites is Dictionary and sites.get(site_id) is Dictionary:
		return int(sites[site_id].get("level", 0))
	return 0


static func _action(view: Dictionary) -> Dictionary:
	var action = view.get("nextAction", {})
	return action if action is Dictionary else {}


static func _view_region(c) -> String:
	if c != null and c.has_method("world_view064"):
		return str(c.world_view064().get("regionId", ""))
	return ""


static func _same_chart_target(action: Dictionary) -> bool:
	var target = action.get("target", {})
	return target is Dictionary and target.has("x") and target.has("y")


static func _respond(ui, message: String) -> void:
	var c = ui.host.core
	if c != null and c.has_method("fail"):
		ui.host.respond(c.fail(message))
	else:
		ui.host.respond({"ok": false, "message": message})
