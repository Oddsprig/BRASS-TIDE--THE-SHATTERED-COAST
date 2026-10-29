extends RefCounted
## Main-thread remote anchorage market, provisions, ownership, and interregional shipping presenter for v0.068.
## Consumes detached Core.shipping_view068() and Core.remote_port068() read-only on open (sync=false).
## Dispatches finite remote trades through Main.remote_trade068(good, qty, side) and sailing via Core.chart_course.
## Never exposes home-only boatyard, refit, storage, or contract services at the remote branch anchorage.

const REMOTE_PORT_ID: String = "westglass_anchorage"
const REMOTE_REGION_ID: String = "glasswind_keys"
const HOME_REGION_ID: String = "shatter_coast"
const REMOTE_BERTH: Dictionary = {"x": 756.0, "y": 732.0}
const PROVISION_GOODS: Array = ["food", "fuel", "supplies", "ammo"]
const BRANCH_GOODS_ORDER: Array = ["food", "fuel", "supplies", "ammo", "timber", "logs", "iron", "tools", "ore"]

static var _open_generation: int = 0


static func _is_finite_num(value) -> bool:
	if value is bool:
		return false
	return (value is int or value is float) and is_finite(float(value))


static func _shipping_view068(c) -> Dictionary:
	if c != null and c is Object and c.has_method("shipping_view068"):
		var v = c.shipping_view068()
		if v is Dictionary:
			return v
	return {}


static func _remote_port068(c) -> Dictionary:
	if c != null and c is Object and c.has_method("remote_port068"):
		var p = c.remote_port068()
		if p is Dictionary:
			return p
	return {}


static func _find_known_port068(shipping_view: Dictionary, port_id: String = "") -> Dictionary:
	var ports = shipping_view.get("ports", [])
	if not (ports is Array) or ports.is_empty():
		return {}
	var target: String = port_id.strip_edges()
	for raw_p in ports:
		if not (raw_p is Dictionary):
			continue
		var pid: String = str(raw_p.get("id", "")).strip_edges()
		if pid.is_empty():
			continue
		if target.is_empty() or pid == target:
			return raw_p
	for raw_p in ports:
		if raw_p is Dictionary and not str(raw_p.get("id", "")).strip_edges().is_empty():
			return raw_p
	return {}


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


static func _faction_display_name(c, faction_id: String) -> String:
	var fid: String = faction_id.strip_edges()
	if fid.is_empty():
		return "Unassigned"
	if c != null and c is Object and c.has_method("faction"):
		var f: Dictionary = c.faction(fid)
		if not f.is_empty() and not str(f.get("name", "")).is_empty():
			return str(f["name"])
	if fid == "reed":
		return "Reedwater Clannish Flotillas"
	if fid == "compact":
		return "Lantern Compact"
	if fid == "forge":
		return "Cinder Forge Syndicate"
	if fid == "raiders":
		return "Shatter Tide Raiders"
	return fid.capitalize()


static func _good_meta(c, good_key: String) -> Dictionary:
	if c != null and c.get("Economy") != null and c.Economy.get("GOODS") is Dictionary and c.Economy.GOODS.has(good_key):
		var g: Dictionary = c.Economy.GOODS[good_key]
		return {
			"name": str(g.get("name", good_key.capitalize())),
			"weight": float(g.get("weight", 1.0)),
			"color": Color(str(g.get("color", "#dfbd7d"))).lightened(0.35)
		}
	return {
		"name": good_key.replace("_", " ").capitalize(),
		"weight": 1.0,
		"color": Color("dfbd7d")
	}


static func _unit_price(c, remote_port: Dictionary, good_key: String, side: String) -> int:
	var prices = remote_port.get("prices", {})
	if prices is Dictionary:
		if prices.get(good_key) is Dictionary:
			var gd: Dictionary = prices[good_key]
			var raw_p = gd.get(side, gd.get("buy" if side == "buy" else "sell", null))
			if _is_finite_num(raw_p):
				return maxi(1, roundi(float(raw_p)))
		if prices.get(side) is Dictionary and _is_finite_num(prices[side].get(good_key, null)):
			return maxi(1, roundi(float(prices[side][good_key])))
		if _is_finite_num(prices.get(good_key, null)):
			var base_p: int = maxi(1, roundi(float(prices[good_key])))
			if side == "buy":
				return base_p
			if c != null and c.get("Economy") != null and remote_port.get("stocks") is Dictionary:
				return maxi(1, int(c.Economy.price(remote_port, good_key, "sell")))
			return maxi(1, roundi(float(base_p) * 0.82))
	if c != null and c.get("Economy") != null and remote_port.get("stocks") is Dictionary:
		return maxi(1, int(c.Economy.price(remote_port, good_key, side)))
	return 0


static func _phase_label(phase: String) -> String:
	match phase.strip_edges():
		"home_service":
			return "HOME HARBOR SERVICE (KELP REACH)"
		"outbound":
			return "OUTBOUND VOYAGE (KELP REACH → WESTGLASS ANCHORAGE)"
		"remote_service":
			return "REMOTE ANCHORAGE SERVICE (WESTGLASS ANCHORAGE)"
		"return":
			return "RETURN VOYAGE (WESTGLASS ANCHORAGE → KELP REACH)"
		"lost":
			return "CONVOY LOST AT SEA"
	return phase.strip_edges().to_upper() if not phase.strip_edges().is_empty() else "UNOBSERVED"


static func open(ui, port_id: String = "") -> void:
	if ui == null or ui.host == null or ui.host.mode != "campaign":
		return
	var c = ui.host.core
	if c == null:
		return
	_open_generation += 1
	ui.modal_kind = "shipping068"
	var view064: Dictionary = c.world_view064() if c.has_method("world_view064") else {}
	var view066: Dictionary = c.ocean_view066() if c.has_method("ocean_view066") else {}
	var view068: Dictionary = _shipping_view068(c)
	var remote_port: Dictionary = _remote_port068(c)
	var known_port: Dictionary = _find_known_port068(view068, port_id)
	if known_port.is_empty() and not remote_port.is_empty():
		known_port = remote_port

	var title_name: String = str(known_port.get("name", "Interregional Shipping & Remote Anchorage")) if not known_port.is_empty() else "Interregional Shipping & Remote Anchorage"
	var subtitle: String = "WESTGLASS ANCHORAGE · REEDWATER TIMBER BRANCH & SHIPPING" if not known_port.is_empty() else "INTERREGIONAL SHIPPING · KNOWN ARCHIPELAGO HOLDINGS"
	var body: VBoxContainer = ui.modal(title_name, subtitle, 1080, 720)
	body.add_theme_constant_override("separation", 8)

	_render_ownership_and_shipping_card(ui, body, c, view064, view066, view068, known_port, remote_port)
	_render_remote_market_card(ui, body, c, view064, view068, known_port, remote_port)
	_render_receipts_card(ui, body, c, view068)
	_render_footer(ui, body, c, view064, view066, view068, known_port, remote_port)


static func _render_ownership_and_shipping_card(ui, body: VBoxContainer, c, view064: Dictionary, view066: Dictionary, view068: Dictionary, known_port: Dictionary, remote_port: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", ui.box(Color("15313a"), ui.LINE, 10))
	body.add_child(card)
	var col: VBoxContainer = ui.column(card)
	col.add_theme_constant_override("separation", 5)

	_wrapped_eyebrow(ui, col, "ARCHIPELAGO OWNERSHIP, REEDWATER BRANCH & MERCHANT ROUTE")

	var is_docked: bool = not remote_port.is_empty() or bool(known_port.get("atBerth", false))
	if not known_port.is_empty():
		var p_name: String = str(known_port.get("name", "Westglass Anchorage"))
		var p_faction: String = _faction_display_name(c, str(known_port.get("faction", "reed")))
		var p_x: float = float(known_port.get("x", REMOTE_BERTH.x))
		var p_y: float = float(known_port.get("y", REMOTE_BERTH.y))
		var status_tag: String = "DOCKED AT WATER BERTH" if is_docked else "SIGHTED / KNOWN BRANCH ANCHORAGE"
		var status_col: Color = ui.TEAL if is_docked else ui.GOLD
		_wrapped_label(ui, col, "%s  ·  %s  ·  %s" % [p_name, p_faction, status_tag], 18, status_col, true)
		ui.paragraph(col, "Westglass Anchorage is a small Reedwater branch from Kelp Reach, settled on the northwest coast of Westglass Isle (glasswind_west) at water berth (%.0f, %.0f) for timber and logs. It is one known holding, not control of the whole Glasswind Keys archipelago—Crown Key and Southglass Reef remain unclaimed." % [p_x, p_y], 13, ui.TEXT)
	else:
		var home_summary: String = str(view068.get("summary", "")).strip_edges()
		if c.home_local064() and not home_summary.is_empty():
			ui.paragraph(col, "Branch status at Shatter Coast: " + home_summary, 13, ui.GOLD)
		ui.paragraph(col, "No remote anchorage in Glasswind Keys has been sighted or visited yet. Unspotted remote ports remain omitted from the chart until observed within local coastal range, and Glasswind islands carry no known faction claim until sighted.", 13, ui.MUTED)

	var ownership: Array = view068.get("ownership", []) if view068.get("ownership") is Array else []
	if not ownership.is_empty():
		var own_parts: Array = []
		for entry in ownership:
			if not (entry is Dictionary):
				continue
			var isl_id: String = str(entry.get("islandId", "glasswind_west"))
			var pid: String = str(entry.get("portId", REMOTE_PORT_ID))
			var fac_name: String = _faction_display_name(c, str(entry.get("faction", "reed")))
			own_parts.append("%s / %s: %s (known branch holding; other Glasswind islands unassigned)" % [isl_id, pid, fac_name])
		if not own_parts.is_empty():
			ui.paragraph(col, "Recorded holdings: " + "  ·  ".join(own_parts), 12, ui.TEAL)

	var route: Dictionary = view068.get("route", {}) if view068.get("route") is Dictionary else {}
	if not route.is_empty():
		var owner_id: String = str(route.get("ownerId", "patrol-7"))
		var phase_str: String = _phase_label(str(route.get("phase", "")))
		var reason_str: String = str(route.get("reason", "")).strip_edges()
		var seen_sec: float = float(route.get("seenSecond", 0.0)) if _is_finite_num(route.get("seenSecond", null)) else 0.0
		var seen_day: float = seen_sec / 45.0 if seen_sec > 0.0 else float(c.state.get("day", 1.0))
		var route_line: String = "Observed merchant shipping (%s): %s  ·  Observed Day %.2f (%.0fs)" % [owner_id, phase_str, seen_day, seen_sec]
		if not reason_str.is_empty():
			route_line += "\nRoute / holding note: " + reason_str
		ui.paragraph(col, route_line, 13, ui.GOLD)
	else:
		ui.paragraph(col, "One Kelp Reach merchant (patrol-7) sails this interregional run in her own hull, crew, and cargo. You see her while sighted; older reports stay marked by date, and unseen positions or manifests are never disclosed. If a voyage cannot be paid from real purses after conservative round-trip reserves, she holds in port and waits.", 12, ui.MUTED)

	var contacts: Array = view068.get("contacts", []) if view068.get("contacts") is Array else []
	if contacts.is_empty() and view066.get("contacts") is Array:
		contacts = view066["contacts"]
	if not contacts.is_empty():
		var c_flow := HFlowContainer.new()
		c_flow.add_theme_constant_override("h_separation", 8)
		c_flow.add_theme_constant_override("v_separation", 6)
		col.add_child(c_flow)
		ui.label(c_flow, "SIGHTED OFFSHORE CONTACTS:", 12, ui.GOLD)
		for item in contacts:
			if not (item is Dictionary):
				continue
			var cid: String = str(item.get("id", item.get("ownerId", "")))
			if cid.is_empty():
				continue
			var vis_tag: String = "LIVE" if str(item.get("visibility", "")) == "visible" else "LAST KNOWN"
			var role_tag: String = str(item.get("role", "contact")).to_upper()
			var b: Button = ui.button(c_flow, "%s · %s (%s)" % [str(item.get("name", cid)), role_tag, vis_tag], func():
				ui.open_ocean_contact066(cid)
			, false, false)
			b.custom_minimum_size.y = 30


static func _render_remote_market_card(ui, body: VBoxContainer, c, view064: Dictionary, _view068: Dictionary, known_port: Dictionary, remote_port: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", ui.box(Color("132c35"), ui.LINE, 10))
	body.add_child(card)
	var col: VBoxContainer = ui.column(card)
	col.add_theme_constant_override("separation", 6)

	_wrapped_eyebrow(ui, col, "WESTGLASS ANCHORAGE · FINITE MARKET, TIMBER & VOYAGE PROVISIONS")

	if remote_port.is_empty():
		var layer: String = str(view064.get("layer", ""))
		var in_glasswind: bool = (layer == "local" and str(view064.get("regionId", "")) == REMOTE_REGION_ID)
		if known_port.is_empty():
			ui.paragraph(col, "Remote market and provisions are unavailable until Westglass Anchorage is installed and sighted in local Glasswind Keys waters.", 14, ui.MUTED)
		elif not in_glasswind:
			ui.paragraph(col, "Westglass Anchorage is known on Westglass Isle (756, 732). Sail to Glasswind Keys local waters and dock at its water berth to trade timber, logs, and provisions.", 14, ui.GOLD)
		else:
			var pos: Dictionary = view064.get("position", c.state.get("position", {"x": 0.0, "y": 0.0}))
			var target_pt := Vector2(float(known_port.get("x", REMOTE_BERTH.x)), float(known_port.get("y", REMOTE_BERTH.y)))
			var dist: float = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0))).distance_to(target_pt)
			var moving: bool = not view064.get("path", []).is_empty()
			var gate_msg: String = "Current distance to Westglass water berth (%.0f, %.0f): %.0f units (must be ≤ 40 units and stopped with legal Reedwater access)." % [target_pt.x, target_pt.y, dist]
			if moving:
				gate_msg += " Your flotilla is currently underway—wait to arrive at the berth or stop within 40 units."
			ui.paragraph(col, gate_msg, 14, ui.GOLD)
			var sail_flow := HFlowContainer.new()
			sail_flow.add_theme_constant_override("h_separation", 8)
			sail_flow.add_theme_constant_override("v_separation", 6)
			col.add_child(sail_flow)
			var btn_sail: Button = ui.button(sail_flow, "Sail to Westglass Anchorage berth (756, 732)  ↗", func():
				_sail_to_remote_port(ui, known_port)
			, true, false)
			btn_sail.custom_minimum_size.y = 34
			if moving:
				var btn_stop: Button = ui.button(sail_flow, "Stop engines", func():
					c.stop_sailing()
					ui.toast("Engines idle. Course canceled.")
					open(ui, str(known_port.get("id", REMOTE_PORT_ID)))
				, false, false)
				btn_stop.custom_minimum_size.y = 34
		ui.paragraph(col, "Branch service scope: Westglass Anchorage trades only its real finite stocks and cash. Boatyard construction, hull sales, drydock refits, harbor storage, and home contracts remain exclusive to Shatter Coast harbors.", 12, ui.MUTED)
		return

	var port_id: String = str(remote_port.get("id", REMOTE_PORT_ID))
	var port_cash: int = int(remote_port.get("cash", 0))
	var player_coins: int = int(remote_port.get("playerCoins", c.state.get("coins", 0)))
	var free_cap: float = float(remote_port.get("freeCapacity", maxf(0.0, c.capacity() - c.cargo_weight())))
	var total_cap: float = float(c.capacity()) if c.has_method("capacity") else free_cap
	var used_cap: float = float(c.cargo_weight()) if c.has_method("cargo_weight") else 0.0
	var stocks: Dictionary = remote_port.get("stocks", {}) if remote_port.get("stocks") is Dictionary else {}
	var player_cargo: Dictionary = c.state.get("cargo", {}) if c.state.get("cargo") is Dictionary else {}

	ui.paragraph(col, "Docked at Westglass Anchorage water berth  ·  Anchorage cash: %s coins  ·  Your purse: %s coins  ·  Hold: %.1f / %.1f used (%.1f free)" % [
		ui.money(port_cash), ui.money(player_coins), used_cap, total_cap, free_cap
	], 14, ui.TEAL)
	ui.paragraph(col, "Trade uses actual port stocks and coins on both ends. Buy provisions into your hold, then load hold reserves into boat fuel tanks, magazines, and repair racks before sailing home.", 13, ui.TEXT)

	var qty_flow := HFlowContainer.new()
	qty_flow.add_theme_constant_override("h_separation", 8)
	qty_flow.add_theme_constant_override("v_separation", 6)
	col.add_child(qty_flow)
	ui.label(qty_flow, "TRADE LOT QUANTITY:", 12, ui.GOLD)
	var cur_qty: int = clampi(int(ui.get("trade_qty")) if _is_finite_num(ui.get("trade_qty")) else 4, 1, 64)
	ui.trade_qty = cur_qty
	var qty_spin := SpinBox.new()
	qty_spin.min_value = 1
	qty_spin.max_value = 64
	qty_spin.step = 1
	qty_spin.value = cur_qty
	qty_spin.custom_minimum_size = Vector2(96, 32)
	qty_spin.value_changed.connect(func(val: float):
		ui.trade_qty = clampi(roundi(val), 1, 64)
	)
	qty_flow.add_child(qty_spin)
	for preset in [1, 4, 8, 16]:
		var p_val: int = int(preset)
		var b_preset: Button = ui.button(qty_flow, "%d lot%s" % [p_val, "" if p_val == 1 else "s"], func():
			ui.trade_qty = p_val
			qty_spin.value = p_val
		, false, false)
		b_preset.custom_minimum_size.y = 32

	var btn_load_res: Button = ui.button(qty_flow, "Load hold reserves into boats (fuel, ammo & kits)", func():
		_invoke_load_reserves(ui, port_id)
	, false, false)
	btn_load_res.custom_minimum_size.y = 32

	var ordered_goods: Array = []
	for g_key in BRANCH_GOODS_ORDER:
		if stocks.has(g_key) or (c.get("Economy") != null and c.Economy.GOODS.has(g_key)):
			ordered_goods.append(g_key)
	for g_key in stocks.keys():
		var ks: String = str(g_key)
		if ks not in ordered_goods:
			ordered_goods.append(ks)
	if c.get("Economy") != null and c.Economy.get("GOODS") is Dictionary:
		for g_key in c.Economy.GOODS.keys():
			var ks: String = str(g_key)
			if ks not in ordered_goods and float(player_cargo.get(ks, 0.0)) > 0.0:
				ordered_goods.append(ks)

	ui.rule(col)
	_wrapped_eyebrow(ui, col, "PROVISIONS, TIMBER & CARGO LOTS")

	for g_key in ordered_goods:
		var key: String = str(g_key)
		var stock_qty: int = floori(float(stocks.get(key, 0.0)))
		var hold_qty: float = float(player_cargo.get(key, 0.0))
		if stock_qty <= 0 and hold_qty < 0.01 and key not in ["food", "fuel", "supplies", "ammo", "timber", "logs"]:
			continue
		var meta: Dictionary = _good_meta(c, key)
		var buy_price: int = _unit_price(c, remote_port, key, "buy")
		var sell_price: int = _unit_price(c, remote_port, key, "sell")
		var is_prov: bool = key in ["food", "fuel", "supplies", "ammo"]
		var tag_str: String = " [PROVISIONS]" if is_prov else (" [BRANCH SPECIALTY]" if key in ["timber", "logs"] else "")

		var line := HFlowContainer.new()
		line.add_theme_constant_override("h_separation", 10)
		line.add_theme_constant_override("v_separation", 4)
		col.add_child(line)

		var name_lbl: Label = ui.label(line, str(meta["name"]) + tag_str, 15, meta["color"])
		name_lbl.custom_minimum_size.x = 220

		var stock_lbl: Label = ui.label(line, "Port stock: %d" % stock_qty, 13, ui.TEAL if stock_qty > 0 else ui.MUTED)
		stock_lbl.custom_minimum_size.x = 120

		var hold_lbl: Label = ui.label(line, "In hold: %.1f (wt %.0f)" % [hold_qty, float(meta["weight"])], 13, ui.GOLD if hold_qty >= 1.0 else ui.MUTED)
		hold_lbl.custom_minimum_size.x = 145

		var btn_buy: Button = ui.button(line, "Buy · %s coins/u" % ui.money(buy_price), func():
			_invoke_remote_trade(ui, key, maxi(1, int(ui.trade_qty)), "buy", port_id)
		, is_prov and stock_qty > 0, false)
		btn_buy.custom_minimum_size.y = 32
		btn_buy.disabled = (stock_qty <= 0 or buy_price <= 0 or player_coins < buy_price or free_cap + 0.0001 < float(meta["weight"]))

		var btn_sell: Button = ui.button(line, "Sell · %s coins/u" % ui.money(sell_price), func():
			_invoke_remote_trade(ui, key, maxi(1, int(ui.trade_qty)), "sell", port_id)
		, false, false)
		btn_sell.custom_minimum_size.y = 32
		btn_sell.disabled = (hold_qty < 1.0 or sell_price <= 0 or port_cash < sell_price)

	ui.rule(col)
	ui.paragraph(col, "Closed at Westglass Anchorage: Boatyard hull purchases/commissions, drydock hull repairs, equipment workshops/refits, boat storage berths, and home-port contracts are unavailable at this small timber branch. Sail back to Shatter Coast for full harbor yards.", 12, ui.MUTED)


static func _render_receipts_card(ui, body: VBoxContainer, c, view068: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", ui.box(Color("142e37"), ui.LINE, 10))
	body.add_child(card)
	var col: VBoxContainer = ui.column(card)
	col.add_theme_constant_override("separation", 4)
	_wrapped_eyebrow(ui, col, "RECENT REMOTE ANCHORAGE TRADE RECEIPTS")

	var receipts: Array = view068.get("receipts", []) if view068.get("receipts") is Array else []
	if receipts.is_empty():
		ui.paragraph(col, "No player remote trades recorded at Westglass Anchorage yet.", 13, ui.MUTED)
		return
	for idx in range(receipts.size() - 1, -1, -1):
		var rec = receipts[idx]
		if not (rec is Dictionary):
			continue
		var seq: int = int(rec.get("sequence", idx + 1))
		var day_val: float = float(rec.get("day", 1.0))
		var side_str: String = str(rec.get("side", "buy")).to_upper()
		var qty_val: int = int(rec.get("qty", 0))
		var good_key: String = str(rec.get("good", ""))
		var good_name: String = str(_good_meta(c, good_key).get("name", good_key))
		var total_coins: int = int(rec.get("total", 0))
		var pid: String = str(rec.get("portId", REMOTE_PORT_ID))
		ui.paragraph(col, "Receipt #%d  ·  Day %.2f  ·  %s %d %s at %s  ·  %s coins" % [
			seq, day_val, side_str, qty_val, good_name, pid, ui.money(total_coins)
		], 12, ui.TEXT if side_str == "BUY" else ui.GOLD)


static func _render_footer(ui, body: VBoxContainer, c, view064: Dictionary, view066: Dictionary, _view068: Dictionary, known_port: Dictionary, remote_port: Dictionary) -> void:
	var scroll_node: Node = body.get_parent()
	var outer: Node = scroll_node.get_parent() if scroll_node != null else body
	ui.rule(outer)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 6)
	outer.add_child(actions)

	var is_local: bool = str(view064.get("layer", "")) == "local"
	var is_docked: bool = not remote_port.is_empty() or bool(known_port.get("atBerth", false))
	var port_id: String = str(known_port.get("id", REMOTE_PORT_ID))

	if is_local and not known_port.is_empty() and not is_docked:
		var btn_sail: Button = ui.button(actions, "Sail to Westglass berth", func():
			_sail_to_remote_port(ui, known_port)
		, true, false)
		btn_sail.custom_minimum_size.y = 34

	var btn_return: Button = ui.button(actions, "Plan return to Shatter Coast", func():
		ui.voyage_intent065["targetRegionId"] = HOME_REGION_ID
		ui.open_voyage_preparation065(HOME_REGION_ID)
	, is_docked or not is_local, false)
	btn_return.custom_minimum_size.y = 34

	var btn_prep: Button = ui.button(actions, "Voyage preparation", func():
		ui.open_voyage_preparation065()
	, false, false)
	btn_prep.custom_minimum_size.y = 34

	var contacts066: Array = view066.get("contacts", []) if view066.get("contacts") is Array else []
	if not contacts066.is_empty():
		var btn_contacts: Button = ui.button(actions, "Sightings & course orders", func():
			ui.open_ocean_contact066()
		, false, false)
		btn_contacts.custom_minimum_size.y = 34

	var btn_hold: Button = ui.button(actions, "Hold & reserves", ui.open_cargo, false, false)
	btn_hold.custom_minimum_size.y = 34

	var btn_fleet: Button = ui.button(actions, "Fleet & crew", ui.open_fleet, false, false)
	btn_fleet.custom_minimum_size.y = 34

	var btn_refresh: Button = ui.button(actions, "Refresh", func():
		open(ui, port_id)
	, false, false)
	btn_refresh.custom_minimum_size.y = 34

	var btn_close: Button = ui.button(actions, "Close", ui.close_modal, false, false)
	btn_close.custom_minimum_size.y = 34


static func _sail_to_remote_port(ui, known_port: Dictionary) -> void:
	if ui == null or ui.host == null or ui.host.mode != "campaign":
		return
	var c = ui.host.core
	if c == null:
		return
	ui.host.sync_economy()
	var pid: String = str(known_port.get("id", REMOTE_PORT_ID))
	var target: Dictionary = {
		"x": float(known_port.get("x", REMOTE_BERTH.x)),
		"y": float(known_port.get("y", REMOTE_BERTH.y))
	}
	var res: Dictionary = c.chart_course(target, pid)
	if res.get("ok", false):
		ui.host.selected_port = pid
		ui.close_modal()
		ui.host.save_game(false)
	ui.host.respond(res)


static func _invoke_load_reserves(ui, port_id: String) -> void:
	if ui == null or ui.host == null or ui.host.mode != "campaign":
		return
	var c = ui.host.core
	if c == null:
		return
	ui.host.sync_economy()
	if not c.travel_lock064.is_empty():
		ui.host.respond(c.fail(c.travel_lock064))
		return
	c.use_reserves()
	ui.host.save_game(false)
	ui.host.respond(c.ok("Loaded available hold reserves into boat ammunition, fuel and repair kits. Food stays in the hold."))
	if ui.modal_open and ui.host.mode == "campaign":
		open(ui, port_id)


static func _invoke_remote_trade(ui, good: String, qty: int, side: String, port_id: String = "") -> void:
	if ui == null or ui.host == null or ui.host.mode != "campaign":
		return
	var gen_before: int = _open_generation
	if ui.host.has_method("remote_trade068"):
		ui.host.remote_trade068(good, qty, side)
	elif ui.host.core != null and ui.host.core.has_method("remote_trade068"):
		ui.host.sync_economy()
		var res: Dictionary = ui.host.core.remote_trade068(good, qty, side)
		ui.host.respond(res)
		if res.get("ok", false):
			ui.host.save_game(false)
	if ui.modal_open and ui.host.mode == "campaign" and _open_generation == gen_before:
		open(ui, port_id)


static func render_preparation_summary068(ui, body: VBoxContainer, c, view064: Dictionary) -> void:
	var view068: Dictionary = _shipping_view068(c)
	var remote_port: Dictionary = _remote_port068(c)
	var known_port: Dictionary = _find_known_port068(view068)
	if known_port.is_empty() and not remote_port.is_empty():
		known_port = remote_port
	var route: Dictionary = view068.get("route", {}) if view068.get("route") is Dictionary else {}
	var receipts: Array = view068.get("receipts", []) if view068.get("receipts") is Array else []
	var home_summary: String = str(view068.get("summary", "")).strip_edges()
	if known_port.is_empty() and route.is_empty() and receipts.is_empty() and home_summary.is_empty():
		return

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", ui.box(Color("142f38"), ui.LINE, 10))
	body.add_child(card)
	var col: VBoxContainer = ui.column(card)
	col.add_theme_constant_override("separation", 4)
	_wrapped_eyebrow(ui, col, "INTERREGIONAL SHIPPING & KNOWN GLASSWIND BRANCH (V0.068)")

	if not known_port.is_empty():
		var p_name: String = str(known_port.get("name", "Westglass Anchorage"))
		var p_fac: String = _faction_display_name(c, str(known_port.get("faction", "reed")))
		var is_docked: bool = not remote_port.is_empty() or bool(known_port.get("atBerth", false))
		ui.paragraph(col, "Known remote holding: %s (%s · timber & logs branch on Westglass Isle at 756, 732 · %s). Other Glasswind islands remain unclaimed; Reedwater holds this one branch, not the whole archipelago." % [
			p_name, p_fac, "Docked at berth" if is_docked else "Known anchorage"
		], 12, ui.TEAL if is_docked else ui.TEXT)
	elif c.home_local064() and not home_summary.is_empty():
		ui.paragraph(col, "Branch status: " + home_summary, 12, ui.GOLD)

	if not route.is_empty():
		var r_owner: String = str(route.get("ownerId", "patrol-7"))
		var r_phase: String = _phase_label(str(route.get("phase", "")))
		var r_reason: String = str(route.get("reason", "")).strip_edges()
		ui.paragraph(col, "Observed merchant (%s): %s%s" % [
			r_owner, r_phase, ("  ·  " + r_reason) if not r_reason.is_empty() else ""
		], 12, ui.GOLD)

	var btn_row := HFlowContainer.new()
	btn_row.add_theme_constant_override("h_separation", 8)
	btn_row.add_theme_constant_override("v_separation", 6)
	col.add_child(btn_row)
	var btn_open: Button = ui.button(btn_row, "Westglass Anchorage & shipping" if not known_port.is_empty() else "Interregional shipping status", func():
		open(ui, str(known_port.get("id", REMOTE_PORT_ID)))
	, not remote_port.is_empty(), false)
	btn_open.custom_minimum_size.y = 32
	if str(view064.get("layer", "")) == "local" and not known_port.is_empty() and remote_port.is_empty():
		var btn_sail: Button = ui.button(btn_row, "Sail to Westglass berth (756, 732)", func():
			_sail_to_remote_port(ui, known_port)
		, false, false)
		btn_sail.custom_minimum_size.y = 32
