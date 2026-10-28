extends RefCounted
## Main-thread ocean contact sighting & course-order presenter for v0.066.
## Consumes separate Core.ocean_view066() and Core.world_view064() read-only (sync=false on open/close).
## Never reads live owner boats/positions; uses only sanitized contact DTOs and frozen Sighting boat snapshots.

const OceanChart064 = preload("res://scripts/ocean_chart064.gd")
const FleetArt054 = preload("res://scripts/campaign_fleet_art054.gd")


class _ContactSilhouetteStrip066 extends Control:
	var boats: Array = []
	var heading: float = 0.0
	var hostile: bool = true
	var visibility: String = "visible"
	var uncertainty_radius: float = 0.0
	var age_seconds: float = 0.0
	var mono_font: Font = null

	func _init(p_boats: Array, p_heading: float, p_hostile: bool, p_vis: String, p_unc: float, p_age: float, p_font: Font) -> void:
		boats = p_boats
		heading = p_heading
		hostile = p_hostile
		visibility = p_vis
		uncertainty_radius = p_unc
		age_seconds = p_age
		mono_font = p_font
		custom_minimum_size = Vector2(0.0, 92.0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if rect.size.x <= 8.0 or rect.size.y <= 8.0:
			return
		draw_rect(rect, Color("0d222b"), true)
		draw_rect(rect, Color("3b5a60"), false, 1.0)
		var mid_y: float = rect.size.y * 0.52
		draw_line(Vector2(12.0, mid_y), Vector2(rect.size.x - 12.0, mid_y), Color(0.58, 0.78, 0.70, 0.12), 1.0, true)
		var center := Vector2(rect.size.x * 0.5, mid_y)
		var base_color: Color = Color("e8947a") if hostile else Color("8fc6b4")
		var is_stale: bool = (visibility != "visible")
		if is_stale:
			var ring_r: float = clampf(uncertainty_radius * 0.25, 24.0, minf(rect.size.x * 0.36, rect.size.y * 0.42))
			var steps: int = 28
			for i in range(0, steps, 2):
				var a0: float = float(i) / float(steps) * TAU
				var a1: float = float(i + 1) / float(steps) * TAU
				draw_line(
					center + Vector2.from_angle(a0) * ring_r,
					center + Vector2.from_angle(a1) * ring_r,
					Color(base_color, 0.48),
					1.25,
					true
				)
		var art: Dictionary = FleetArt054.layout(
			boats,
			center,
			heading,
			0.34,
			{"viewport": rect, "overview": false, "size_multiplier": 1.05}
		)
		var accent: Color = Color(base_color, 0.44 if is_stale else 0.92)
		FleetArt054.draw(self, art, accent, not is_stale)
		var bow_dir: Vector2 = Vector2.from_angle(heading)
		var r_px: float = clampf(float(art.get("hit_radius", 18.0)), 14.0, 34.0)
		if is_stale:
			draw_dashed_line(center, center + bow_dir * (r_px + 14.0), Color(base_color, 0.55), 1.2, 4.0, true)
		else:
			draw_line(center + bow_dir * (r_px + 2.0), center + bow_dir * (r_px + 12.0), Color(base_color, 0.88), 1.4, true)
		if mono_font != null:
			var badge: String = "VISUAL CONTACT" if not is_stale else ("LAST SIGHTED · %ds AGO · ±%.0f UNITS" % [maxi(0, roundi(age_seconds)), uncertainty_radius])
			draw_string(mono_font, Vector2(10.0, 16.0), badge, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0, 10, Color(base_color, 0.86))


static func open(ui, contact_id: String = "") -> void:
	if ui == null or ui.host == null or ui.host.mode != "campaign":
		return
	var c = ui.host.core
	if c == null:
		return
	# Interface's read-only close whitelist includes this panel kind.
	ui.modal_kind = "ocean_contact066"
	var view064: Dictionary = c.world_view064() if c.has_method("world_view064") else {}
	var view066: Dictionary = c.ocean_view066() if c.has_method("ocean_view066") else {}
	var contacts: Array = OceanChart064._extract_contacts066(view064, view066)
	var selected: Dictionary = _select_contact(contacts, contact_id, view066)
	var title_name: String = str(selected.get("name", "Offshore Sighting & Course Orders")) if not selected.is_empty() else "Offshore Sighting & Course Orders"
	var body: VBoxContainer = ui.modal(title_name, "OCEAN SIGHTING & COURSE ORDERS", 860, 620)
	body.add_theme_constant_override("separation", 8)

	if view066.is_empty() and view064.is_empty():
		ui.paragraph(body, "Ocean chart and sighting records are currently unavailable.", 16, ui.RED)
		_render_footer(ui, body, selected, view064, view066)
		return

	if contacts.size() > 1:
		_render_contact_selector(ui, body, contacts, str(selected.get("id", "")))

	if selected.is_empty():
		_render_no_contact_card(ui, body, view064, view066)
	else:
		_render_contact_card(ui, body, selected, view064, view066)

	_render_travel_and_zone_card(ui, body, view064, view066)
	_render_footer(ui, body, selected, view064, view066)


static func _select_contact(contacts: Array, contact_id: String, view066: Dictionary) -> Dictionary:
	if contacts.is_empty():
		return {}
	var target: String = contact_id.strip_edges()
	if target.is_empty() and view066.get("travel066") is Dictionary:
		target = str(view066["travel066"].get("contactId", "")).strip_edges()
	if not target.is_empty():
		for item in contacts:
			if str(item.get("id", "")) == target or str(item.get("ownerId", "")) == target:
				return item
	return contacts[0]


static func _wrapped_label(ui, parent: Node, text: String, font_size: int = 16, color: Color = Color.WHITE, serif: bool = false) -> Label:
	var lbl: Label = ui.label(parent, text, font_size, color, serif)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl


static func _wrapped_eyebrow(ui, parent: Node, text: String) -> Label:
	var lbl: Label = ui.eyebrow(parent, text)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl


static func _render_contact_selector(ui, body: VBoxContainer, contacts: Array, active_id: String) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	body.add_child(flow)
	ui.label(flow, "SIGHTED CONTACTS:", 12, ui.GOLD)
	for item in contacts:
		var cid: String = str(item.get("id", ""))
		var vis_tag: String = "LIVE" if str(item.get("visibility", "")) == "visible" else "LAST KNOWN"
		var b: Button = ui.button(flow, "%s (%s)" % [str(item.get("name", cid)), vis_tag], func(): open(ui, cid), cid == active_id, false)
		b.custom_minimum_size.y = 30


static func _render_no_contact_card(ui, body: VBoxContainer, view064: Dictionary, _view066: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", ui.box(Color("142f38"), ui.LINE, 10))
	body.add_child(card)
	var col: VBoxContainer = ui.column(card)
	col.add_theme_constant_override("separation", 4)
	_wrapped_eyebrow(ui, col, "NO UNEXPIRED OFFSHORE SIGHTING SELECTED")
	ui.paragraph(col, "No active or unexpired last-known fleet sighting is currently selected on %s. Unspotted fleets never disclose hidden positions or hull rosters; sightings appear only within current visual detection range and expire 30 simulated seconds after contact is lost." % str(view064.get("name", "this chart")), 14, ui.TEXT)


static func _render_contact_card(ui, body: VBoxContainer, contact: Dictionary, view064: Dictionary, _view066: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", ui.box(Color("15313a"), ui.LINE, 10))
	body.add_child(card)
	var col: VBoxContainer = ui.column(card)
	col.add_theme_constant_override("separation", 6)

	var vis: String = str(contact.get("visibility", "last_known"))
	var is_visible: bool = (vis == "visible")
	var hostile: bool = bool(contact.get("hostile", true))
	var status_color: Color = ui.RED if hostile else ui.TEAL
	var faction_text: String = str(contact.get("faction", "Independent")).strip_edges()
	var role_text: String = str(contact.get("role", "raider")).strip_edges()
	var owner_id: String = str(contact.get("ownerId", contact.get("id", "")))

	var head_flow := HFlowContainer.new()
	head_flow.add_theme_constant_override("h_separation", 12)
	head_flow.add_theme_constant_override("v_separation", 4)
	col.add_child(head_flow)
	_wrapped_label(ui, head_flow, "%s  ·  %s %s (%s)" % [
		str(contact.get("name", "Offshore Contact")),
		faction_text.capitalize() if not faction_text.is_empty() else "Offshore",
		role_text,
		owner_id
	], 18, ui.TEXT, true)

	var pos: Dictionary = contact.get("position", {"x": 0.0, "y": 0.0})
	var heading_deg: int = posmod(roundi(rad_to_deg(float(contact.get("heading", 0.0)))), 360)
	var age_sec: float = float(contact.get("ageSeconds", 0.0))
	var unc_radius: float = float(contact.get("uncertaintyRadius", 0.0))
	var sighted_day: float = float(contact.get("sightedDay", 0.0))

	if is_visible:
		ui.paragraph(col, "STATUS: DIRECT VISUAL CONTACT (%s)  ·  Chart position (%.0f, %.0f)  ·  Heading %d°  ·  Sighted Day %.2f" % [
			"HOSTILE" if hostile else "NON-HOSTILE",
			float(pos.get("x", 0.0)), float(pos.get("y", 0.0)), heading_deg, sighted_day
		], 13, status_color)
	else:
		ui.paragraph(col, "STATUS: LAST KNOWN SIGHTING (%s · %.0fs ago on Day %.2f)  ·  Frozen position (%.0f, %.0f)  ·  Frozen heading %d°  ·  Uncertainty radius ±%.0f units" % [
			"HOSTILE" if hostile else "NON-HOSTILE",
			age_sec, sighted_day, float(pos.get("x", 0.0)), float(pos.get("y", 0.0)), heading_deg, unc_radius
		], 13, ui.GOLD if hostile else ui.MUTED)
		ui.paragraph(col, "Sighting intelligence is frozen at the moment of last observation. Unseen movement, current fuel/stores and any post-sighting course changes are hidden until re-spotted.", 12, ui.MUTED)

	var provenance: String = str(contact.get("provenance", "")).strip_edges()
	var intent_label: String = str(contact.get("intentLabel", "")).strip_edges()
	if not provenance.is_empty() or not intent_label.is_empty():
		var prov_parts: Array = []
		if not provenance.is_empty():
			prov_parts.append("Provenance: " + provenance)
		if not intent_label.is_empty():
			prov_parts.append("Observed activity: " + intent_label)
		ui.paragraph(col, "  ·  ".join(prov_parts), 13, ui.GOLD)

	var boats: Array = contact.get("boats", [])
	var mono_font: Font = ui.host.chart.get("mono") if ui.host.get("chart") != null else null
	var strip := _ContactSilhouetteStrip066.new(boats, float(contact.get("heading", 0.0)), hostile, vis, unc_radius, age_sec, mono_font)
	col.add_child(strip)

	ui.paragraph(col, _describe_sighted_boats(boats, is_visible, str(view064.get("name", "Ocean chart"))), 12, ui.TEXT)


static func _describe_sighted_boats(boats: Array, is_visible: bool, _chart_name: String) -> String:
	if boats.is_empty():
		return "Observed hull roster: No surviving hull silhouettes recorded in this sighting snapshot."
	var items: Array = []
	for b in boats:
		if not (b is Dictionary):
			continue
		var spec: Dictionary = b.get("spec", {}) if b.get("spec") is Dictionary else b
		var hull_id: String = str(spec.get("id", b.get("type", b.get("hullId", "hull"))))
		var hull_name: String = str(b.get("name", spec.get("name", hull_id.replace("_", " ").capitalize())))
		var role: String = str(spec.get("role", b.get("role", ""))).strip_edges()
		var uid: String = str(b.get("uid", "")).strip_edges()
		var label_str: String = hull_name
		if not role.is_empty():
			label_str += " [%s]" % role
		if not uid.is_empty():
			label_str += " (%s)" % uid
		items.append(label_str)
	var prefix: String = "Live observed hulls (%d)" if is_visible else "Frozen last-sighted hulls (%d)"
	return "%s: %s." % [prefix % items.size(), ", ".join(items)]


static func _render_travel_and_zone_card(ui, body: VBoxContainer, view064: Dictionary, view066: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", ui.box(Color("132c35"), ui.LINE, 10))
	body.add_child(card)
	var col: VBoxContainer = ui.column(card)
	col.add_theme_constant_override("separation", 4)
	_wrapped_eyebrow(ui, col, "COURSE ORDERS, SAVED RETURN GOAL & LOCAL OCEAN CONDITIONS")

	var travel: Dictionary = view066.get("travel066", {}) if view066.get("travel066") is Dictionary else {}
	var mode: String = str(travel.get("mode", "direct"))
	var resume_dest: String = str(travel.get("resumeDestination", "")).strip_edges()
	var resume_path: Array = travel.get("resumePath", []) if travel.get("resumePath") is Array else []
	var zone_summary: String = str(travel.get("activeZoneSummary", "")).strip_edges()

	var dest_now: String = str(view064.get("destination", "")).strip_edges()
	if dest_now.is_empty():
		dest_now = "Open water waypoint" if not view064.get("path", []).is_empty() else "Stopped"

	var resume_text: String = "None saved"
	if not resume_dest.is_empty():
		resume_text = resume_dest
	elif not resume_path.is_empty():
		var last_wp = resume_path[-1]
		if last_wp is Dictionary and last_wp.has("x") and last_wp.has("y"):
			resume_text = "Saved route to (%.0f, %.0f)" % [float(last_wp["x"]), float(last_wp["y"])]
		else:
			resume_text = "Saved route (%d waypoint%s)" % [resume_path.size(), "" if resume_path.size() == 1 else "s"]

	ui.paragraph(col, "Current course mode: %s  ·  Active destination: %s  ·  Saved resume goal: %s" % [
		mode.to_upper(), dest_now, resume_text
	], 13, ui.GOLD if mode in ["investigate", "avoid", "divert"] else ui.TEXT)

	if not zone_summary.is_empty():
		ui.paragraph(col, "Active water conditions: " + zone_summary, 13, ui.TEAL)

	var zones: Array = OceanChart064._extract_zones066(view064, view066)
	if not zones.is_empty():
		var z_parts: Array = []
		for z in zones:
			z_parts.append("%s (%s)" % [str(z["name"]), str(z["summary"])])
		ui.paragraph(col, "Chart zones (15s deterministic weather phases): " + "  |  ".join(z_parts), 12, ui.MUTED)

	ui.paragraph(col, "Investigate plots to the unexpired last sighting and stops (never homes on hidden movement). Avoid plots a physical escape course to safe separation and grants NO encounter grace or immunity. Ordinary water course clicks and stopping remain available at all times.", 12, ui.MUTED)


static func _render_footer(ui, body: VBoxContainer, contact: Dictionary, _view064: Dictionary, view066: Dictionary) -> void:
	var scroll_node: Node = body.get_parent()
	var outer: Node = scroll_node.get_parent() if scroll_node != null else body
	ui.rule(outer)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 6)
	outer.add_child(actions)

	var has_contact: bool = not contact.is_empty()
	var action_id: String = str(contact.get("id", contact.get("ownerId", "")))
	var is_visible: bool = str(contact.get("visibility", "")) == "visible"
	var can_engage: bool = is_visible and bool(contact.get("canEngage", true))
	var travel: Dictionary = view066.get("travel066", {}) if view066.get("travel066") is Dictionary else {}
	var mode: String = str(travel.get("mode", "direct"))
	var has_resume: bool = mode in ["divert", "investigate", "avoid"] or not str(travel.get("resumeDestination", "")).is_empty() or (travel.get("resumePath") is Array and not travel.get("resumePath", []).is_empty())

	var btn_investigate: Button = ui.button(actions, "Investigate sighting", func():
		_invoke_contact_action(ui, action_id, "investigate")
	, not is_visible and has_contact, false)
	btn_investigate.custom_minimum_size.y = 34
	btn_investigate.disabled = not has_contact

	var btn_avoid: Button = ui.button(actions, "Avoid contact", func():
		_invoke_contact_action(ui, action_id, "avoid")
	, false, false)
	btn_avoid.custom_minimum_size.y = 34
	btn_avoid.disabled = not has_contact

	var btn_engage: Button = ui.button(actions, "Engage contact", func():
		_invoke_contact_action(ui, action_id, "engage")
	, is_visible and has_contact, false)
	btn_engage.custom_minimum_size.y = 34
	btn_engage.disabled = not can_engage

	var btn_resume: Button = ui.button(actions, "Resume original course", func():
		_invoke_resume(ui, action_id)
	, false, false)
	btn_resume.custom_minimum_size.y = 34
	btn_resume.disabled = not has_resume

	var btn_prep: Button = ui.button(actions, "Voyage preparation", func():
		ui.open_voyage_preparation065()
	, false, false)
	btn_prep.custom_minimum_size.y = 34

	var btn_refresh: Button = ui.button(actions, "Refresh", func():
		open(ui, action_id)
	, false, false)
	btn_refresh.custom_minimum_size.y = 34

	var btn_close: Button = ui.button(actions, "Close", ui.close_modal, false, false)
	btn_close.custom_minimum_size.y = 34


static func _invoke_contact_action(ui, contact_id: String, action: String) -> void:
	if ui == null or ui.host == null or contact_id.is_empty():
		return
	if ui.host.has_method("contact_action066"):
		ui.host.contact_action066(contact_id, action)
	elif ui.host.has_method("order_ocean_contact066"):
		ui.host.order_ocean_contact066(contact_id, action)
	if action != "engage" and ui.modal_open and ui.host.mode == "campaign":
		open(ui, contact_id)


static func _invoke_resume(ui, contact_id: String) -> void:
	if ui == null or ui.host == null:
		return
	if ui.host.has_method("resume_voyage066"):
		ui.host.resume_voyage066()
	elif ui.host.has_method("contact_action066"):
		ui.host.contact_action066(contact_id, "resume")
	if ui.modal_open and ui.host.mode == "campaign":
		open(ui, contact_id)
