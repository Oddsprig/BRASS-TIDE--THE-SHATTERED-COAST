extends RefCounted
## Display adapter for the funded-work board. One selected row may call
## VoyageJobs.offer_view070. This file does not price, accept, buy, or install.
const Identity = preload("res://scripts/fleet_identity.gd")
const Refit = preload("res://scripts/refit.gd")
const Exploration = preload("res://scripts/exploration.gd")

const FITTINGS := ["cargo_rig", "survey_rig", "workshop_rig", "auxiliary_tanks"]
const HOME_REGION := "shatter_coast"


class DetachedCore extends RefCounted:
	var state: Dictionary
	var data: Dictionary
	var dock_id: String
	var source
	func _init(c, harbor_id: String):
		source = c
		state = c.state.duplicate(true) if c != null and c.get("state") is Dictionary else {}
		data = c.data if c != null and c.get("data") is Dictionary else {}
		dock_id = harbor_id
	func current_port() -> Dictionary:
		for p in state.get("ports", []) if state.get("ports") is Array else []:
			if p is Dictionary and str(p.get("id", "")) == dock_id:
				return p
		return {}
	func find_boat(uid: String) -> Dictionary:
		for b in state.get("fleet", []) if state.get("fleet") is Array else []:
			if b is Dictionary and str(b.get("uid", "")) == uid:
				return b
		return {}
	func fitted_spec(boat: Dictionary) -> Dictionary:
		return source.fitted_spec(boat) if source != null and source.has_method("fitted_spec") else boat.get("spec", {})
	func fail(message: String) -> Dictionary:
		return {"ok": false, "message": message}


static func _actions(parent: Node) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	parent.add_child(flow)
	return flow


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
			"message": "Voyage quote unavailable; published gross fee is %d coins." % gross,
			"grossFee": gross,
			"kind": str(offer.get("kind", "")),
			"offerId": str(offer.get("id", "")),
		}
	var view = c.VoyageJobs.offer_view070(c, offer)
	if view is Dictionary:
		return view
	return {"ok": false, "routeOk": false, "quoted": false, "message": "Selected voyage quote unavailable.", "grossFee": gross, "kind": str(offer.get("kind", ""))}


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
			var destination := str(leg.get("destination", ""))
			var where := "open water on this chart"
			if destination.begins_with("approach:"):
				where = "the selected approach"
			elif not destination.is_empty():
				where = "the selected berth"
			lines.append("%s: sail toward %s." % [phase, where])
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
		return ["No active campaign fleet."]
	var conversions: Dictionary = Identity.conversions()
	var roles: Dictionary = Identity.roles()
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
			role_text = "Hull role: %s." % hull_role if not hull_role.is_empty() else "Working boat."
		notes.append("%s · %s" % [name, role_text])
		var fitted := str(boat.get("conversion", ""))
		if conversions.has(fitted):
			var info: Dictionary = conversions[fitted]
			notes.append("%s: %s" % [str(info.get("name", fitted)), str(info.get("trade", ""))])
		var active: Dictionary = boat.get("specialistActive", {}) if boat.get("specialistActive") is Dictionary else {}
		if bool(active.get("surveyor", false)):
			var surveyor: Dictionary = roles.get("surveyor", {})
			notes.append("Surveyor aboard %s (+%d coins/day)." % [name, int(surveyor.get("premium", 0))])
		if bool(active.get("chief_engineer", false)):
			notes.append("Chief engineer aboard %s (repairs consume onboard kits)." % name)
		var armor := ""
		if boat.get("loadout") is Dictionary:
			armor = str(boat.loadout.get("armor", ""))
		if armor == "scout_plating":
			if catalog.is_empty():
				catalog = Refit.catalog()
			var described: Dictionary = catalog.get("armor", {}).get("scout_plating", {})
			notes.append("%s carries %s. %s" % [name, str(described.get("name", "Scout plating")), str(described.get("description", ""))])
	notes.append_array(_fitting_quotes(c, boats))
	return notes


static func _role_line(role: String) -> String:
	match role:
		"transport":
			return "Transport hull (eligible for fuel and passenger charters)."
		"tanker":
			return "Tanker hull (eligible for bulk fuel jobs; tank fuel stays on this boat)."
		"yacht":
			return "Yacht hull (eligible for passenger charters using spare berths)."
		"fishing":
			return "Fishing hull (works offshore grounds; sell whole lots at a harbor market)."
		"scout":
			return "Scout hull (faster shore surveys when fitted; still requires spare crew and kits)."
		"repair":
			return "Repair hull (faster underway repairs using onboard kits)."
		_:
			return ""


static func _fitting_quotes(c, boats: Array) -> Array:
	var service := service_berth(c)
	var work := work_berth(c)
	if service.is_empty():
		return ["Interior conversions (Cargo, Survey, Workshop, Auxiliary Tanks) are quoted at Shatter Coast harbors."]
	if not work.is_empty() and str(work.get("id", "")) != str(service.get("id", "")):
		return ["Conversion quotes at %s (current berth: %s)." % [str(service.get("name", "the service harbor")), str(work.get("name", "this berth"))]]
	var detached := DetachedCore.new(c, str(service.get("id", "")))
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
		var quote: Dictionary = Identity.quote_conversion(detached, uid, id)
		lines.append("%s (%s) · %s" % [boat_name, str(service.get("name", "this harbor")), str(quote.get("message", ""))])
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


static func course_line(c) -> String:
	if c == null or not c.get("state") is Dictionary:
		return "Current course: none."
	var state: Dictionary = c.state
	var path: Array = state.get("path", []) if state.get("path") is Array else []
	var destination := str(state.get("destination", ""))
	if path.is_empty() and destination.is_empty():
		return "Current course: none."
	if destination.begins_with("approach:"):
		var approach := _approach_name(c, destination)
		if approach.is_empty():
			return "Current course: coastal approach."
		return "Current course: %s." % approach
	if not destination.is_empty() and c.has_method("port"):
		var name := str(c.port(destination).get("name", "")).strip_edges()
		if not name.is_empty():
			return "Current course: %s." % name
		return "Current course: active."
	return "Current course: open water."


static func selection_note(c, selected_id: String) -> String:
	var picked := str(selected_id).strip_edges()
	if picked.is_empty() or c == null or not c.has_method("port"):
		return ""
	var name := str(c.port(picked).get("name", "")).strip_edges()
	if name.is_empty():
		return ""
	var destination := ""
	if c.get("state") is Dictionary:
		destination = str(c.state.get("destination", ""))
	if destination == picked:
		return ""
	if destination.is_empty():
		return "Selected on chart: %s (current course: none)." % name
	var course := str(c.port(destination).get("name", "")).strip_edges()
	if course.is_empty():
		return "Selected on chart: %s (different course active)." % name
	return "Selected on chart: %s (current course: %s)." % [name, course]


static func services_line(c) -> String:
	var service := service_berth(c)
	var work := work_berth(c)
	if not service.is_empty():
		var named := str(service.get("name", "this harbor"))
		if not work.is_empty() and str(work.get("id", "")) != str(service.get("id", "")):
			return "Harbor services (%s): Market, Crew & repairs, Refit, Boatyard · Work berth: %s." % [named, str(work.get("name", "the work berth"))]
		return "Harbor services (%s): Market, Crew & repairs, Refit, Boatyard." % named
	if not work.is_empty():
		return "Work berth (%s): funded jobs available here; drydock, refit and boatyard require Shatter Coast." % str(work.get("name", "this berth"))
	return "At sea: dock at a Shatter Coast harbor for market, repairs, refit and boatyard, or at any harbor for funded work."


static func reserve_line(report: Dictionary) -> String:
	if not report.has("foodDays") or not report.has("fuelDays") or not report.has("repairKits"):
		return ""
	return "Reserves now: %.1f food days · %.1f tank-fuel days · %.1f repair kits." % [float(report.foodDays), float(report.fuelDays), float(report.repairKits)]


static func connect_views(ui, body, work_button: bool = true, service_buttons: bool = true) -> void:
	if ui == null or ui.host == null:
		return
	var c = ui.host.core
	ui.paragraph(body, course_line(c), 15, ui.TEAL)
	var note := selection_note(c, str(ui.host.selected_port))
	if not note.is_empty():
		ui.paragraph(body, note, 14, ui.GOLD)
	var lock := ""
	if c != null and c.get("travel_lock064") is String:
		lock = str(c.travel_lock064).strip_edges()
	var pending := _pending_contact(c)
	if not lock.is_empty():
		ui.paragraph(body, lock, 15, ui.GOLD)
	elif not pending.is_empty():
		ui.paragraph(body, _contact_sentence(pending), 15, ui.GOLD)
		if str(pending.get("kind", "")) != "defeat":
			var held := pending.duplicate(true)
			ui.button(body, "Open the waiting contact", func(): _open_contact(ui, held), true, false)
	ui.paragraph(body, services_line(c), 14)
	var actions := _actions(body)
	ui.button(actions, "Long-voyage preparation", func(): ui.open_voyage_preparation065(), false, false)
	if work_button and c != null:
		var header := board_header(c)
		if bool(header.get("docked", false)):
			ui.button(actions, "Open funded work at this berth", func(): ui.VoyageUI.open(ui), false, false)
		elif c.has_method("home_local064") and c.home_local064():
			ui.button(actions, "Open funded work board", func(): ui.VoyageUI.open(ui), false, false)
	if c != null and c.has_method("home_local064") and not c.home_local064():
		ui.button(actions, "Plan return voyage to Shatter Coast", func(): ui.open_voyage_preparation065("shatter_coast"), true, false)
	if service_buttons and not service_berth(c).is_empty():
		ui.button(actions, "Paid repairs & crew", func(): ui.open_port("Crew & repairs"), false, false)
		ui.button(actions, "Paid fitting", func(): ui.open_port("Refit"), false, false)


static func _approach_name(c, destination: String) -> String:
	if c == null or not c.has_method("world_view064"):
		return ""
	var parts := destination.split(":")
	if parts.size() != 3:
		return ""
	var view: Dictionary = c.world_view064()
	var approaches: Array = view.get("approaches", []).duplicate() if view.get("approaches") is Array else []
	if view.get("regions") is Array:
		for region in view.regions:
			if region is Dictionary and region.get("approaches") is Array:
				approaches.append_array(region.approaches)
	for approach in approaches:
		if not approach is Dictionary:
			continue
		if str(approach.get("regionId", "")) == parts[1] and str(approach.get("id", "")) == parts[2]:
			return str(approach.get("name", "")).strip_edges()
	return ""


static func _pending_contact(c) -> Dictionary:
	if c == null or not c.get("events") is Array:
		return {}
	for event in c.events:
		if not event is Dictionary:
			continue
		var kind := str(event.get("kind", ""))
		if kind == "encounter":
			return {"kind": kind, "id": str(event.get("patrol", ""))}
		if kind == "ocean_encounter066":
			return {"kind": kind, "id": str(event.get("ownerId", ""))}
		if kind == "defeat":
			return {"kind": kind, "id": ""}
	return {}


static func _contact_sentence(pending: Dictionary) -> String:
	if str(pending.get("kind", "")) == "defeat":
		return "A loss is waiting. Resolve it before changing course."
	return "A contact is waiting. Resolve it before changing course or loading reserves."


static func _open_contact(ui, pending: Dictionary) -> void:
	var kind := str(pending.get("kind", ""))
	var id := str(pending.get("id", ""))
	var c = ui.host.core
	if kind == "encounter" and c != null and c.has_method("home_local064") and c.home_local064() and not id.is_empty():
		ui.host.show_patrol_encounter(id)
		return
	if ui.has_method("open_ocean_contact066"):
		ui.open_ocean_contact066(id)


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
