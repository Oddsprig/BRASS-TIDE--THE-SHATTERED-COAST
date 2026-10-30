extends RefCounted
## Chart actions for one generated coastal group. Geometry comes from world_view064.
## Politics and the optional harbor id come from sector_view069. No second atlas and no voyage quote.

const Chart = preload("res://scripts/ocean_chart064.gd")


static func open(ui, region_id: String, approach_id: String = "") -> bool:
	if ui == null or ui.host == null or ui.host.mode != "campaign" or ui.host.core == null:
		return false
	var core = ui.host.core
	if not core.has_method("world_view064") or not core.has_method("approach_course064") or not core.has_method("transition064"):
		return false
	var view: Dictionary = core.world_view064()
	if not Chart.generated_member(view, region_id):
		return false
	var region_name: String = region_id
	for region in view.get("regions", []):
		if region is Dictionary and str(region.get("regionId", "")) == region_id:
			region_name = str(region.get("name", region_id))
			break
	var group: Dictionary = {}
	var port_id: String = ""
	if core.has_method("sector_view069"):
		var sector = core.sector_view069()
		if sector is Dictionary and _schema1(sector):
			for candidate in sector.get("groups", []):
				if candidate is Dictionary and str(candidate.get("regionId", "")) == region_id:
					group = candidate
					break
			port_id = _known_port_id(sector, region_id)
	ui.modal_kind = "sector069"
	var body = ui.modal(region_name, "COASTAL GROUP", 760, 560)
	ui.paragraph(body, "Route sets a course to a marked approach. Enter uses that approach when the flotilla is already inside it.", 15)
	var knowledge: String = str(group.get("knowledge", "")).strip_edges().to_lower()
	var band: String = str(group.get("band", "")).strip_edges().to_lower()
	if not knowledge.begins_with("unknown") and band in ["settled", "frontier", "remote"]:
		ui.eyebrow(body, band + " coast")
	var ownership: String = Chart.known_ownership_line(group)
	if not ownership.is_empty():
		ui.paragraph(body, ownership, 16, ui.GOLD)
	var north_selected: bool = approach_id == "north"
	var south_selected: bool = approach_id == "south"
	ui.button(body, "Route north approach", func(): _route(ui, region_id, "north"), north_selected, false)
	ui.button(body, "Enter north approach", func(): _enter(ui, region_id, "north"), false, false)
	ui.button(body, "Route south approach", func(): _route(ui, region_id, "south"), south_selected, false)
	ui.button(body, "Enter south approach", func(): _enter(ui, region_id, "south"), false, false)
	if not port_id.is_empty():
		var harbor_id: String = port_id
		ui.button(body, "Known harbor", func(): ui.open_shipping068(harbor_id), false, false)
	ui.button(body, "Close", ui.close_modal, false, false)
	return true


static func _schema1(sector: Dictionary) -> bool:
	var schema = sector.get("schema", null)
	if schema is bool or not (schema is int or schema is float):
		return false
	return int(schema) == 1


static func _known_port_id(sector: Dictionary, region_id: String) -> String:
	var ports = sector.get("ports", [])
	if not (ports is Array):
		return ""
	for port in ports:
		if not (port is Dictionary):
			continue
		if str(port.get("regionId", "")) != region_id:
			continue
		if port.has("known") and not bool(port.get("known", false)):
			continue
		if port.has("installed") and not bool(port.get("installed", false)):
			continue
		var port_id: String = str(port.get("id", "")).strip_edges()
		if not port_id.is_empty():
			return port_id
	return ""


static func _route(ui, region_id: String, approach_id: String) -> void:
	var core = ui.host.core
	ui.host.respond(core.approach_course064(region_id, approach_id))


static func _enter(ui, region_id: String, approach_id: String) -> void:
	var core = ui.host.core
	ui.host.respond(core.transition064(region_id, approach_id))
