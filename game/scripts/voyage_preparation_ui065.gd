extends RefCounted
## Main-thread long-voyage preparation presenter for v0.065.
## Consumes Core.voyage_quote065(intent) read-only and never settles economy on view.

const HOME_REGION: String = "shatter_coast"
const REMOTE_REGION: String = "glasswind_keys"
const INTENT_KEYS: Array = ["targetRegionId", "targetApproachId", "outExit", "backExit", "homeEntry", "returnPortId", "idleDays"]


static func open(ui, region_id: String = "", approach_id: String = "") -> void:
	if ui == null or ui.host == null or ui.host.mode != "campaign":
		return
	var c = ui.host.core
	ui.modal_kind = "ocean064"
	var view: Dictionary = c.world_view064()
	var chart_name: String = str(view.get("name", "Ocean charts"))
	var body = ui.modal(chart_name + " · Voyage Preparation", "COASTAL APPROACHES · LONG-VOYAGE FORECAST & RESERVES", 1120, 720)
	body.add_theme_constant_override("separation", 8)
	if view.is_empty():
		ui.paragraph(body, "Ocean chart definitions are unavailable.", 18, ui.RED)
		ui.button(body, "Close", ui.close_modal, false, false)
		return
	var raw_intent: Dictionary = ui.voyage_intent065 if (ui.get("voyage_intent065") is Dictionary) else {}
	var intent: Dictionary = normalize_intent(c, view, raw_intent, region_id, approach_id)
	ui.voyage_intent065 = intent.duplicate(true)
	var quote: Dictionary = c.voyage_quote065(intent.duplicate(true))
	render_quote(ui, body, view, intent, quote)


static func normalize_intent(c, view: Dictionary, raw: Dictionary, region_id: String = "", approach_id: String = "") -> Dictionary:
	var target_region: String = region_id if region_id in [HOME_REGION, REMOTE_REGION] else str(raw.get("targetRegionId", ""))
	if target_region not in [HOME_REGION, REMOTE_REGION]:
		target_region = REMOTE_REGION
	var layer: String = str(view.get("layer", "home"))
	var current_region: String = str(view.get("regionId", HOME_REGION))
	var leaving: bool = layer != "ocean" and current_region != target_region
	var remote: bool = target_region == REMOTE_REGION
	var crossing_in: bool = current_region != target_region
	var out_exit: String = ""
	if leaving:
		out_exit = str(raw.get("outExit", ""))
		if out_exit not in ["north", "south"] and current_region == REMOTE_REGION:
			out_exit = str(raw.get("backExit", ""))
		if out_exit not in ["north", "south"]:
			out_exit = "south" if current_region == REMOTE_REGION else "north"
	var target_approach: String = ""
	if remote or crossing_in:
		var raw_home_entry: String = str(raw.get("homeEntry", ""))
		if approach_id in ["north", "south"]:
			target_approach = approach_id
		elif not remote and raw_home_entry in ["north", "south"]:
			target_approach = raw_home_entry
		else:
			target_approach = str(raw.get("targetApproachId", ""))
		if target_approach not in ["north", "south"]:
			target_approach = "south" if remote else "north"
	var back_exit: String = ""
	if remote:
		back_exit = str(raw.get("backExit", ""))
		if back_exit not in ["north", "south"]:
			back_exit = target_approach if target_approach in ["north", "south"] else "south"
	var home_entry: String = ""
	if remote:
		home_entry = str(raw.get("homeEntry", ""))
		if home_entry not in ["north", "south"]:
			home_entry = out_exit if out_exit in ["north", "south"] else "north"
	var return_port: String = str(raw.get("returnPortId", ""))
	if return_port.is_empty() or not _has_port(c, return_port):
		return_port = _default_return_port(c)
	var idle_raw = raw.get("idleDays", 0.0)
	var idle_days: float = float(idle_raw) if (idle_raw is int or idle_raw is float) and not (idle_raw is bool) and is_finite(float(idle_raw)) and float(idle_raw) >= 0.0 else 0.0
	return {
		"targetRegionId": target_region,
		"targetApproachId": target_approach,
		"outExit": out_exit,
		"backExit": back_exit,
		"homeEntry": home_entry,
		"returnPortId": return_port,
		"idleDays": idle_days
	}


static func _has_port(c, port_id: String) -> bool:
	for p in c.state.get("ports", []):
		if p is Dictionary and str(p.get("id", "")) == port_id:
			return true
	return false


static func _default_return_port(c) -> String:
	var candidates: Array = [
		str(c.current_port().get("id", "")),
		str(c.state.get("lastPort", "")),
		"brass_haven"
	]
	for p in c.state.get("ports", []):
		if p is Dictionary:
			candidates.append(str(p.get("id", "")))
	for port_id in candidates:
		if port_id.is_empty() or not _has_port(c, port_id):
			continue
		var port: Dictionary = c.port(port_id)
		var access: Dictionary = c.Factions.access(c.state, port)
		var safe_until: float = float(c.state.get("relationships", {}).get("safeConduct", {}).get(port_id, 0.0))
		if bool(access.get("legal", false)) or safe_until > float(c.state.get("day", 0.0)):
			return port_id
	for p in c.state.get("ports", []):
		if p is Dictionary and not str(p.get("id", "")).is_empty():
			return str(p.get("id", ""))
	return "brass_haven"


static func _apply_draft(ui, patch: Dictionary) -> void:
	var draft: Dictionary = ui.voyage_intent065.duplicate(true) if (ui.get("voyage_intent065") is Dictionary) else {}
	for key in patch:
		draft[str(key)] = patch[key]
	ui.voyage_intent065 = draft
	open(ui)


static func render_quote(ui, body: VBoxContainer, view: Dictionary, intent: Dictionary, quote: Dictionary) -> void:
	var c = ui.host.core
	var named: Dictionary = quote.get("intent", {})
	var target_region: String = str(intent.get("targetRegionId", REMOTE_REGION))
	var target_region_name: String = str(named.get("targetRegionName", "Glasswind Keys" if target_region == REMOTE_REGION else "Shatter Coast"))
	var return_port_id: String = str(intent.get("returnPortId", "brass_haven"))
	var return_port_name: String = str(named.get("returnPortName", c.port(return_port_id).get("name", return_port_id)))
	var distances: Dictionary = quote.get("distances", {})
	var by_layer: Dictionary = distances.get("byLayer", {})
	var timing: Dictionary = quote.get("timing", {})
	var expected: Dictionary = quote.get("expected", {})
	var by_phase: Dictionary = expected.get("byPhase", {})
	var allowance: Dictionary = quote.get("allowance", {})
	var funding: Dictionary = quote.get("funding", {})
	var stores: Dictionary = quote.get("stores", {})
	var maintenance: Dictionary = quote.get("maintenance", {})
	var next_action: Dictionary = quote.get("nextAction", {})

	_render_route_controls(ui, body, c, view, intent, quote, named, target_region, target_region_name, return_port_id, return_port_name, distances, by_layer, timing, expected)
	_render_phase_columns(ui, body, quote, distances, timing, expected, by_phase, allowance, funding, stores, return_port_name)
	_render_funding_and_holds(ui, body, c, expected, allowance, funding, stores)
	ui.rule(body)
	_render_boats_and_transfer(ui, body, c, view, stores, allowance)
	ui.rule(body)
	_render_maintenance_and_conditions(ui, body, quote, maintenance, stores)
	_render_footer_bar(ui, body, c, view, intent, quote, next_action)


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


static func _render_route_controls(ui, body: VBoxContainer, c, view: Dictionary, intent: Dictionary, quote: Dictionary, named: Dictionary, target_region: String, target_region_name: String, return_port_id: String, return_port_name: String, distances: Dictionary, by_layer: Dictionary, timing: Dictionary, expected: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", ui.box(Color("15313a"), ui.LINE, 10))
	body.add_child(card)
	var col = ui.column(card)
	col.add_theme_constant_override("separation", 5)

	var status_row = ui.row(col)
	var route_ok: bool = bool(quote.get("routeOk", false))
	var ready_ok: bool = bool(quote.get("readyForAllowance", false))
	var status_color: Color = ui.TEAL if ready_ok else (ui.GOLD if route_ok else ui.RED)
	var origin: Dictionary = quote.get("origin", {})
	var day_now: float = float(origin.get("day", c.state.get("day", 1.0)))
	var econ_day: int = int(origin.get("econDay", c.state.get("econDay", 1)))
	var pending_days: int = int(expected.get("pendingDays", maxi(0, floori(day_now) - econ_day)))
	ui.paragraph(status_row, "Origin: %s · Day %.2f (settled day %d · %d pending day%s)  →  Target: %s  →  Return harbor: %s" % [
		str(view.get("name", "Chart")), day_now, econ_day, pending_days, "" if pending_days == 1 else "s",
		target_region_name, return_port_name
	], 15, ui.TEXT)
	ui.label(status_row, "READY FOR ALLOWANCE" if ready_ok else ("ROUTE VALID · CHECK RESERVES" if route_ok else "ROUTE REFUSED"), 13, status_color)

	var metrics_text: String = "Route distance: %.0f water units (%.0f outward + %.0f return · Home %.0f · Ocean %.0f at 1:10 chart scale · Remote local %.0f)  ·  Current speed: %.1f units/s  ·  Moving: %.1f s  ·  Est. arrival: Day %.2f" % [
		float(distances.get("total", 0.0)), float(distances.get("outward", 0.0)), float(distances.get("return", 0.0)),
		float(by_layer.get("home", 0.0)), float(by_layer.get("ocean", 0.0)), float(by_layer.get("local", 0.0)),
		float(timing.get("speed", c.travel_speed())), float(timing.get("movingSeconds", 0.0)), float(timing.get("endDay", day_now))
	]
	ui.paragraph(col, metrics_text, 13, ui.MUTED)
	ui.paragraph(col, str(quote.get("message", "Select route and crossing choices to inspect the voyage forecast.")) + "  (Viewing, selecting or refreshing spends 0 coins and settles no pending payroll.)", 14, status_color)

	var dest_row := HFlowContainer.new()
	dest_row.add_theme_constant_override("h_separation", 8)
	dest_row.add_theme_constant_override("v_separation", 6)
	col.add_child(dest_row)
	ui.label(dest_row, "DESTINATION & RETURN:", 12, ui.GOLD)
	var btn_remote = ui.button(dest_row, "Target: Glasswind Keys", func(): _apply_draft(ui, {"targetRegionId": REMOTE_REGION}), false, false)
	btn_remote.custom_minimum_size.y = 32
	btn_remote.add_theme_color_override("font_color", ui.GOLD if target_region == REMOTE_REGION else ui.TEXT)
	var btn_home = ui.button(dest_row, "Target: Shatter Coast (Home)", func(): _apply_draft(ui, {"targetRegionId": HOME_REGION}), false, false)
	btn_home.custom_minimum_size.y = 32
	btn_home.add_theme_color_override("font_color", ui.GOLD if target_region == HOME_REGION else ui.TEXT)
	if str(view.get("regionId", "")) == REMOTE_REGION or str(quote.get("nextAction", {}).get("kind", "")) == "none":
		var btn_return_plan = ui.button(dest_row, "Plan return to Shatter Coast", func(): _apply_draft(ui, {"targetRegionId": HOME_REGION}), target_region != HOME_REGION, false)
		btn_return_plan.custom_minimum_size.y = 32

	var harbor_idle_row := HFlowContainer.new()
	harbor_idle_row.add_theme_constant_override("h_separation", 8)
	harbor_idle_row.add_theme_constant_override("v_separation", 6)
	col.add_child(harbor_idle_row)
	ui.label(harbor_idle_row, "Return harbor:", 12, ui.MUTED)
	var port_picker := OptionButton.new()
	port_picker.custom_minimum_size = Vector2(210, 32)
	port_picker.fit_to_longest_item = false
	port_picker.clip_text = true
	var port_ids: Array = []
	var selected_port_idx: int = 0
	for p in c.state.get("ports", []):
		if not (p is Dictionary):
			continue
		var pid: String = str(p.get("id", ""))
		var pname: String = str(p.get("name", pid))
		var access: Dictionary = c.Factions.access(c.state, p)
		var tag: String = "" if bool(access.get("legal", false)) else " (pass required)"
		port_ids.append(pid)
		port_picker.add_item(pname + tag)
		if pid == return_port_id:
			selected_port_idx = port_ids.size() - 1
	if not port_ids.is_empty():
		port_picker.select(selected_port_idx)
		port_picker.item_selected.connect(func(idx: int):
			if idx >= 0 and idx < port_ids.size():
				_apply_draft(ui, {"returnPortId": str(port_ids[idx])})
		)
	harbor_idle_row.add_child(port_picker)

	var idle_days: float = float(intent.get("idleDays", 0.0))
	ui.label(harbor_idle_row, "Idle wait: %.2fd" % idle_days, 12, ui.MUTED)
	for preset in [0.0, 0.25, 1.0, 2.0]:
		var val: float = float(preset)
		var b_idle = ui.button(harbor_idle_row, "%sd" % ("0" if val == 0.0 else ("0.25" if val == 0.25 else str(int(val)))), func(): _apply_draft(ui, {"idleDays": val}), false, false)
		b_idle.custom_minimum_size.y = 32
		b_idle.add_theme_color_override("font_color", ui.GOLD if is_equal_approx(idle_days, val) else ui.TEXT)

	var gates_row = ui.row(col)
	gates_row.add_theme_constant_override("separation", 8)
	_render_gate_selector(ui, gates_row, "Outward exit", "outExit", str(intent.get("outExit", "")), str(named.get("outExitName", "")))
	_render_gate_selector(ui, gates_row, "Target approach", "targetApproachId", str(intent.get("targetApproachId", "")), str(named.get("targetApproachName", "")))
	_render_gate_selector(ui, gates_row, "Return exit", "backExit", str(intent.get("backExit", "")), str(named.get("backExitName", "")))
	_render_gate_selector(ui, gates_row, "Home entry", "homeEntry", str(intent.get("homeEntry", "")), str(named.get("homeEntryName", "")))


static func _render_gate_selector(ui, parent: Node, title: String, field: String, current_val: String, readable_name: String) -> void:
	var box_panel := PanelContainer.new()
	box_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_panel.add_theme_stylebox_override("panel", ui.box(Color("102731"), ui.LINE, 8))
	parent.add_child(box_panel)
	var col = ui.column(box_panel)
	col.add_theme_constant_override("separation", 4)
	if current_val.is_empty():
		ui.paragraph(col, "%s: Unused on this layer" % title, 12, ui.MUTED)
		ui.paragraph(col, "Stripped to empty for current chart/target", 11, ui.MUTED)
		return
	var detail: String = readable_name if not readable_name.is_empty() else current_val.capitalize()
	ui.paragraph(col, "%s: %s" % [title, detail], 12, ui.GOLD)
	var btns = ui.row(col)
	btns.add_theme_constant_override("separation", 6)
	for side in ["north", "south"]:
		var chosen: String = str(side)
		var btn = ui.button(btns, chosen.capitalize(), func(): _apply_draft(ui, {field: chosen}), false, false)
		btn.custom_minimum_size.y = 30
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_color_override("font_color", ui.GOLD if current_val == chosen else ui.TEXT)


static func _render_phase_columns(ui, body: VBoxContainer, quote: Dictionary, distances: Dictionary, timing: Dictionary, expected: Dictionary, by_phase: Dictionary, allowance: Dictionary, funding: Dictionary, stores: Dictionary, return_port_name: String) -> void:
	var cols = ui.row(body)
	cols.add_theme_constant_override("separation", 10)
	var out_fuel: float = 0.0
	var ret_fuel: float = 0.0
	var cont_fuel: float = 0.0
	for b in stores.get("boats", []):
		out_fuel += float(b.get("outwardFuel", 0.0))
		ret_fuel += float(b.get("returnFuel", 0.0))
		cont_fuel += float(b.get("contingencyFuel", 0.0))

	# Column 1: Outward Leg
	var out_card := PanelContainer.new()
	out_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_card.add_theme_stylebox_override("panel", ui.box(Color("16333c"), ui.LINE, 10))
	cols.add_child(out_card)
	var out_col = ui.column(out_card)
	out_col.add_theme_constant_override("separation", 4)
	_wrapped_eyebrow(ui, out_col, "1 · OUTWARD LEG (EXPECTED)")
	var out_phase: Dictionary = by_phase.get("outward", {})
	_wrapped_label(ui, out_col, "%.0f water units  ·  %.2f sailing days" % [float(distances.get("outward", 0.0)), float(timing.get("outwardDays", 0.0))], 16, ui.TEXT, true)
	ui.paragraph(out_col, "Moving fuel: %.2f drums across active/towed burners\nCrossed calendar days: %.0f  ·  Rations: %.2f bales\nExpected outward payroll: %s coins (%s base + %s specialist + %s arrears)" % [
		out_fuel, float(out_phase.get("payrollDays", 0.0)), float(out_phase.get("food", 0.0)),
		ui.money(out_phase.get("coinsRequired", 0)), ui.money(out_phase.get("baseWages", 0)),
		ui.money(out_phase.get("premiums", 0)), ui.money(out_phase.get("premiumArrearsPaid", 0))
	], 13, ui.TEXT)
	ui.paragraph(out_col, _legs_summary(quote.get("legs", []), "outward"), 12, ui.MUTED)

	# Column 2: Return Leg & Planned Idle
	var ret_card := PanelContainer.new()
	ret_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ret_card.add_theme_stylebox_override("panel", ui.box(Color("16333c"), ui.LINE, 10))
	cols.add_child(ret_card)
	var ret_col = ui.column(ret_card)
	ret_col.add_theme_constant_override("separation", 4)
	_wrapped_eyebrow(ui, ret_col, "2 · RETURN LEG & IDLE WAIT")
	var ret_phase: Dictionary = by_phase.get("return", {})
	var idle_phase: Dictionary = by_phase.get("idle", {})
	_wrapped_label(ui, ret_col, "To %s: %.0f units  ·  %.2fd + %.2fd idle" % [return_port_name, float(distances.get("return", 0.0)), float(timing.get("returnDays", 0.0)), float(timing.get("idleDays", 0.0))], 16, ui.TEXT, true)
	ui.paragraph(ret_col, "Return moving fuel: %.2f drums (idle wait burns 0 moving fuel)\nIdle crossed days: %.0f (%s coins · %.2f food bales)\nReturn crossed days: %.0f (%s coins · %.2f food bales)" % [
		ret_fuel,
		float(idle_phase.get("payrollDays", 0.0)), ui.money(idle_phase.get("coinsRequired", 0)), float(idle_phase.get("food", 0.0)),
		float(ret_phase.get("payrollDays", 0.0)), ui.money(ret_phase.get("coinsRequired", 0)), float(ret_phase.get("food", 0.0))
	], 13, ui.TEXT)
	ui.paragraph(ret_col, _legs_summary(quote.get("legs", []), "return"), 12, ui.MUTED)

	# Column 3: Contingency Reserve & Pending vs Expected Horizon
	var res_card := PanelContainer.new()
	res_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_card.add_theme_stylebox_override("panel", ui.box(Color("16333c"), ui.LINE, 10))
	cols.add_child(res_card)
	var res_col = ui.column(res_card)
	res_col.add_theme_constant_override("separation", 4)
	_wrapped_eyebrow(ui, res_col, "3 · 2-DAY CONTINGENCY & RESERVES")
	var pend_phase: Dictionary = by_phase.get("pending", {})
	var reserve_days: float = float(allowance.get("reserveDays", 2.0))
	_wrapped_label(ui, res_col, "%.1f contingency days  ·  %.2f reserve fuel drums" % [reserve_days, cont_fuel], 16, ui.GOLD, true)
	ui.paragraph(res_col, "Unsettled pending earned: %.0f day(s) (%s coins · %.2f food bales)\nExpected total crossed: %.0f days (%s coins · %.2f food bales)\nConservative allowance ceiling: %.0f whole days (%s return wages · %.2f food bales)" % [
		float(pend_phase.get("payrollDays", expected.get("pendingDays", 0.0))),
		ui.money(pend_phase.get("coinsRequired", 0)), float(pend_phase.get("food", 0.0)),
		float(expected.get("totalPayrollDays", 0.0)), ui.money(expected.get("coinsRequired", 0)), float(expected.get("food", 0.0)),
		float(allowance.get("payrollDays", 0.0)), ui.money(allowance.get("returnWages", 0)), float(allowance.get("foodRequired", 0.0))
	], 13, ui.TEXT)
	ui.paragraph(res_col, "Expected crossed days are chronological integer day boundaries; the 2-day contingency ceiling is held back as safety margin.", 12, ui.MUTED)


static func _legs_summary(legs: Array, phase: String) -> String:
	var parts: Array[String] = []
	for leg in legs:
		if not (leg is Dictionary) or str(leg.get("phase", "")) != phase:
			continue
		var kind: String = str(leg.get("kind", ""))
		var layer: String = str(leg.get("layer", ""))
		if kind == "transition":
			parts.append("Cross %s (%s → %s, 0d)" % [str(leg.get("approachId", "")).capitalize(), layer, str(leg.get("toLayer", ""))])
		else:
			parts.append("Sail %s (%.0f u / %.1fs)" % [layer, float(leg.get("physicalDistance", 0.0)), float(leg.get("seconds", 0.0))])
	return "Steps: " + (" → ".join(parts) if not parts.is_empty() else "At destination (0 distance)")


static func _render_funding_and_holds(ui, body: VBoxContainer, c, expected: Dictionary, allowance: Dictionary, funding: Dictionary, stores: Dictionary) -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", ui.box(Color("132c35"), ui.LINE, 10))
	body.add_child(bar)
	var col = ui.column(bar)
	col.add_theme_constant_override("separation", 4)
	var coins_now: int = int(c.state.get("coins", 0))
	var base_arrears: int = int(allowance.get("wageArrears", c.state.get("wageArrears", 0)))
	var prem_arrears: int = int(funding.get("premiumArrears", 0))
	var req_coins: int = ceili(float(funding.get("requiredCoins", 0.0)))
	var wage_shortfall: int = ceili(float(funding.get("shortfall", allowance.get("wageShortfall", 0.0))))
	var food_avail: float = float(allowance.get("foodAvailable", c.state.get("cargo", {}).get("food", 0.0)))
	var food_req: float = float(allowance.get("foodRequired", 0.0))
	var food_short: float = float(allowance.get("foodShortfall", 0.0))
	var fuel_short: float = float(stores.get("loadedShortfall", allowance.get("fuelShortfall", 0.0)))
	var tank_short: float = float(stores.get("tankShortfall", 0.0))
	var hold_used: float = float(allowance.get("cargoWeight", 0.0))
	var hold_cap: float = float(allowance.get("usableCapacity", 0.0))
	var hold_free: float = float(allowance.get("freeCapacity", 0.0))
	var hold_over: float = float(allowance.get("allowanceOverload", 0.0))

	ui.paragraph(col, "Purse: %s coins  ·  Daily wages: %s coins/day (%d crew across %d owned hulls, %d traveling, %d stored)  ·  Expected debit: %s coins  ·  Full allowance + arrears: %s coins (base arrears %s + specialist arrears %s)  ·  Wage shortfall: %s coins" % [
		ui.money(coins_now), ui.money(allowance.get("dailyWages", 0)), int(allowance.get("crew", 0)),
		int(allowance.get("ownedCount", 0)), int(allowance.get("travelingCount", 0)), int(allowance.get("storedCount", 0)),
		ui.money(expected.get("coinsRequired", 0)), ui.money(req_coins), ui.money(base_arrears), ui.money(prem_arrears),
		ui.money(wage_shortfall)
	], 13, ui.RED if wage_shortfall > 0 else ui.TEAL)

	ui.paragraph(col, "Rations: %.2f / %.2f food bales (shortfall %.2f bales · %.1f food days)  ·  Loaded fuel shortfall: %.2f drums (%.2f beyond fitted tanks)  ·  Hold space: %.1f / %.1f used (%.1f free · %.1f after food top-up · overload %.1f)" % [
		food_avail, food_req, food_short, float(allowance.get("foodDays", 0.0)),
		fuel_short, tank_short, hold_used, hold_cap, hold_free, float(allowance.get("payloadAfterFood", 0.0)), hold_over
	], 13, ui.RED if (food_short > 0.001 or fuel_short > 0.001 or hold_over > 0.001) else ui.TEXT)


static func _render_boats_and_transfer(ui, body: VBoxContainer, c, view: Dictionary, stores: Dictionary, allowance: Dictionary) -> void:
	_wrapped_eyebrow(ui, body, "PER-BOAT WORKING FUEL TANKS, HOLD RESERVES & EXPLICIT MANUAL TRANSFER")
	var boats: Array = stores.get("boats", [])
	ui.paragraph(body, "Total working fuel required: %.2f drums  ·  Loaded shortfall: %.2f drums  ·  Beyond fitted tanks: %.2f drums  ·  Loose hold fuel: %.1f drums  ·  Loose hold repair kits: %.1f\nEach boat burns only its own loaded tank fuel while moving (including fueled tows). Loose hold fuel is cargo until loaded. Support and tanker tanks are never shared automatically; transfer exact working fuel between boats below while stopped, or load hold reserves (loads loose ammunition, fuel and repair kits; food stays in the hold)." % [
		float(stores.get("fuelRequired", allowance.get("fuelRequired", 0.0))),
		float(stores.get("loadedShortfall", allowance.get("fuelShortfall", 0.0))),
		float(stores.get("tankShortfall", 0.0)),
		float(stores.get("looseFuel", allowance.get("looseFuel", 0.0))),
		float(stores.get("looseSupplies", 0.0))
	], 13, ui.TEXT)

	for entry in boats:
		if not (entry is Dictionary):
			continue
		var b_card := PanelContainer.new()
		b_card.add_theme_stylebox_override("panel", ui.box(Color("153039"), ui.LINE, 10))
		body.add_child(b_card)
		var b_col = ui.column(b_card)
		b_col.add_theme_constant_override("separation", 3)
		var b_head = ui.row(b_col)
		var b_name: String = str(entry.get("name", "Boat"))
		var b_uid: String = str(entry.get("uid", ""))
		var traveling: bool = bool(entry.get("traveling", false))
		var burns: bool = bool(entry.get("burnsWhileMoving", true))
		var role_tag: String = "TRAVELING" if traveling else ("FUELED TOW · BURNS WHILE MOVING" if burns else "MOTHBALLED · NO MOVING BURN")
		var loaded_fuel: float = float(entry.get("loadedFuel", 0.0))
		var tank_cap: float = maxf(0.01, float(entry.get("tankCapacity", 60.0)))
		var short_fuel: float = float(entry.get("loadedShortfall", entry.get("fuelShortfall", 0.0)))
		var tank_short: float = float(entry.get("tankShortfall", 0.0))
		_wrapped_label(ui, b_head, "%s (%s)  ·  %s" % [b_name, b_uid, role_tag], 15, ui.GOLD if traveling else ui.TEXT, true)
		ui.label(b_head, "Tank %.2f / %.1f drums  ·  Shortfall %.2f" % [loaded_fuel, tank_cap, short_fuel], 13, ui.RED if short_fuel > 0.001 else ui.TEAL)
		var bar = ui.progress(b_col, ui.RED if short_fuel > 0.001 else ui.TEAL)
		bar.value = clampf(loaded_fuel / tank_cap * 100.0, 0.0, 100.0)
		ui.paragraph(b_col, "Burn %.2f drums/day (%.1f loaded days / %.1f tank days)  ·  Outward %.2f + Return %.2f + 2-day contingency %.2f = %.2f required  ·  Beyond fitted tank: %.2f  ·  Carrier hold fuel: %.1f  ·  Kits aboard: %.1f" % [
			float(entry.get("fuelPerDay", 0.0)), float(entry.get("loadedDays", 0.0)), float(entry.get("tankDays", 0.0)),
			float(entry.get("outwardFuel", 0.0)), float(entry.get("returnFuel", 0.0)), float(entry.get("contingencyFuel", 0.0)),
			float(entry.get("fuelRequired", 0.0)), tank_short, float(entry.get("cargoFuel", 0.0)), float(entry.get("loadedSupplies", 0.0))
		], 12, ui.MUTED)

	var xfer_panel := PanelContainer.new()
	xfer_panel.add_theme_stylebox_override("panel", ui.box(Color("173640"), ui.GOLD, 10))
	body.add_child(xfer_panel)
	var xfer_col = ui.column(xfer_panel)
	xfer_col.add_theme_constant_override("separation", 6)
	_wrapped_eyebrow(ui, xfer_col, "EXPLICIT WORKING FUEL TRANSFER & HOLD RESERVE LOADING")
	var pickers_row = ui.row(xfer_col)
	var source_picker := OptionButton.new()
	var target_picker := OptionButton.new()
	source_picker.custom_minimum_size = Vector2(200, 34)
	target_picker.custom_minimum_size = Vector2(200, 34)
	source_picker.fit_to_longest_item = false
	target_picker.fit_to_longest_item = false
	source_picker.clip_text = true
	target_picker.clip_text = true
	source_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var uids: Array = []
	var default_src: int = 0
	var default_tgt: int = 0
	for i in range(boats.size()):
		var b: Dictionary = boats[i]
		var uid: String = str(b.get("uid", ""))
		var label_text: String = "%s (%s · %.2f/%.0f)" % [str(b.get("name", uid)), uid, float(b.get("loadedFuel", 0.0)), float(b.get("tankCapacity", 60.0))]
		uids.append(uid)
		source_picker.add_item("From: " + label_text)
		target_picker.add_item("To: " + label_text)
		if float(b.get("loadedFuel", 0.0)) > float(boats[default_src].get("loadedFuel", 0.0)):
			default_src = i
		if float(b.get("loadedShortfall", 0.0)) > 0.001 or i > 0:
			default_tgt = i
	if uids.size() >= 2 and default_src == default_tgt:
		default_tgt = (default_src + 1) % uids.size()
	if not uids.is_empty():
		source_picker.select(default_src)
		target_picker.select(default_tgt)
	pickers_row.add_child(source_picker)
	pickers_row.add_child(target_picker)

	var xfer_row := HFlowContainer.new()
	xfer_row.add_theme_constant_override("h_separation", 8)
	xfer_row.add_theme_constant_override("v_separation", 6)
	xfer_col.add_child(xfer_row)
	ui.label(xfer_row, "Transfer quantity:", 12, ui.MUTED)

	var qty_box := SpinBox.new()
	qty_box.min_value = 0.125
	qty_box.max_value = 240.0
	qty_box.step = 0.125
	var initial_qty: float = 4.0
	if uids.size() >= 2:
		var tgt_short: float = float(boats[default_tgt].get("loadedShortfall", 0.0))
		var src_avail: float = float(boats[default_src].get("loadedFuel", 0.0))
		var tgt_room: float = maxf(0.0, float(boats[default_tgt].get("tankCapacity", 60.0)) - float(boats[default_tgt].get("loadedFuel", 0.0)))
		if tgt_short > 0.001:
			initial_qty = clampf(snappedf(minf(tgt_short, minf(src_avail, tgt_room)), 0.125), 0.125, 240.0)
	qty_box.value = initial_qty
	qty_box.custom_minimum_size = Vector2(110, 34)
	xfer_row.add_child(qty_box)

	for preset_qty in [0.125, 1.0, 4.0]:
		var q_val: float = float(preset_qty)
		var q_btn = ui.button(xfer_row, "%s drum%s" % [str(q_val), "" if q_val == 1.0 else "s"], func(): qty_box.value = q_val, false, false)
		q_btn.custom_minimum_size.y = 34

	var can_transfer: bool = uids.size() >= 2 and view.get("path", []).is_empty() and c.travel_lock064.is_empty()
	var btn_xfer = ui.button(xfer_row, "Transfer working fuel", func():
		if uids.size() < 2:
			return
		var s_uid: String = str(uids[clampi(source_picker.selected, 0, uids.size() - 1)])
		var t_uid: String = str(uids[clampi(target_picker.selected, 0, uids.size() - 1)])
		ui.host.transfer_fuel065(s_uid, t_uid, float(qty_box.value))
	, true, false)
	btn_xfer.custom_minimum_size.y = 34
	btn_xfer.disabled = not can_transfer

	var reserve_row = ui.row(xfer_col)
	var btn_load = ui.button(reserve_row, "Load hold reserves (ammo, fuel & kits)", func():
		ui.host.load_reserves065()
	, false, false)
	btn_load.custom_minimum_size.y = 34
	ui.paragraph(reserve_row, "Loads loose hold ammunition, fuel and repair kits into boat working stores in fleet order; food stays in the hold. Sealed job freight is never touched.", 12, ui.MUTED)


static func _render_maintenance_and_conditions(ui, body: VBoxContainer, quote: Dictionary, maintenance: Dictionary, stores: Dictionary) -> void:
	_wrapped_eyebrow(ui, body, "MAINTENANCE, CONDITIONAL REPAIR KITS & DECLARED QUOTE CONDITIONS")
	var known: bool = bool(maintenance.get("usageKnown", false))
	var expected_kits = maintenance.get("expectedSupplies", null)
	var loose_kits: float = float(maintenance.get("looseSupplies", stores.get("looseSupplies", 0.0)))
	var cond_fuel: bool = bool(maintenance.get("conditionalFuel", false))
	var maint_summary: String = "Healthy & dry fleet: %.1f repair kits expected for this voyage  ·  %.1f loose kits in hold." % [float(expected_kits if expected_kits != null else 0.0), loose_kits] if known else "Damaged or active-repair hull present: repair kit use and speed recovery are conditional (expected kits unknown)  ·  %.1f loose kits in hold." % loose_kits
	if cond_fuel:
		maint_summary += "  ·  WARNING: Flooding or residual velocity burns +0.006 fuel/s even while waiting."
	ui.paragraph(body, maint_summary, 13, ui.TEAL if (known and not cond_fuel) else ui.GOLD)

	for m_boat in maintenance.get("boats", []):
		if not (m_boat is Dictionary):
			continue
		var damaged_mods: int = 0
		var modules: Dictionary = m_boat.get("modules", {})
		for mod in modules.values():
			if mod is Dictionary and float(mod.get("hp", 1.0)) < 1.0:
				damaged_mods += 1
		var breaches: Array = m_boat.get("breaches", [])
		var b_known: bool = bool(m_boat.get("usageKnown", false))
		ui.paragraph(body, "%s (%s): Hull %.0f / %.0f  ·  Water %.1f  ·  Fire %.1f  ·  Wounded %.0f  ·  Breaches %d  ·  Damaged fittings %d  ·  Kits aboard %.1f  ·  Policy %s / Priority %s  ·  Expected kits: %s" % [
			str(m_boat.get("name", "Boat")), str(m_boat.get("uid", "")),
			float(m_boat.get("hp", 0.0)), float(m_boat.get("maxHp", 0.0)),
			float(m_boat.get("water", 0.0)), float(m_boat.get("fire", 0.0)), float(m_boat.get("wounded", 0.0)),
			breaches.size(), damaged_mods, float(m_boat.get("loadedSupplies", 0.0)),
			str(m_boat.get("policy", "balanced")), str(m_boat.get("repairPriority", "auto")),
			"0.0 (healthy)" if b_known else "conditional / unknown"
		], 12, ui.TEXT if b_known else ui.GOLD)

	var seen_messages: Dictionary = {}
	for blocker in quote.get("blockers", []):
		var msg: String = str(blocker)
		if msg.is_empty() or seen_messages.has(msg):
			continue
		seen_messages[msg] = true
		ui.paragraph(body, "Blocker / Shortfall: " + msg, 13, ui.RED)
	for warning in quote.get("warnings", []):
		var msg: String = str(warning)
		if msg.is_empty() or seen_messages.has(msg):
			continue
		seen_messages[msg] = true
		ui.paragraph(body, "Caution: " + msg, 13, ui.GOLD)

	var assumptions: Array = quote.get("assumptions", [])
	if not assumptions.is_empty():
		var joined: PackedStringArray = PackedStringArray()
		for item in assumptions:
			joined.append(str(item))
		ui.paragraph(body, "Declared conditions: " + " ".join(joined), 12, ui.MUTED)


static func _render_footer_bar(ui, body: VBoxContainer, c, view: Dictionary, intent: Dictionary, quote: Dictionary, next_action: Dictionary) -> void:
	var scroll_node: Node = body.get_parent()
	var outer: Node = scroll_node.get_parent() if scroll_node != null else body
	ui.rule(outer)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 10)
	actions.add_theme_constant_override("v_separation", 6)
	outer.add_child(actions)
	var next_kind: String = str(next_action.get("kind", "none"))
	var next_title: String = str(next_action.get("title", "Destination reached"))
	var primary_btn = ui.button(actions, next_title, func():
		ui.host.voyage_action065(intent.duplicate(true))
	, true, false)
	primary_btn.custom_minimum_size.y = 36
	if next_kind == "course":
		primary_btn.disabled = not bool(quote.get("routeOk", false)) or not c._sailing_blocker064().is_empty()
	elif next_kind == "transition":
		primary_btn.disabled = not bool(quote.get("routeOk", false)) or not view.get("path", []).is_empty() or not c.transition_blocker064().is_empty()
	else:
		primary_btn.disabled = true

	if next_kind == "none" or str(view.get("regionId", "")) == REMOTE_REGION:
		var home_btn = ui.button(actions, "Destination: Shatter Coast", func(): _apply_draft(ui, {"targetRegionId": HOME_REGION}), false, false)
		home_btn.custom_minimum_size.y = 36

	var refresh_btn = ui.button(actions, "Refresh", func(): open(ui), false, false)
	refresh_btn.custom_minimum_size.y = 36
	var fleet_btn = ui.button(actions, "Fleet & crew", ui.open_fleet, false, false)
	fleet_btn.custom_minimum_size.y = 36
	var hold_btn = ui.button(actions, "Hold & reserves", ui.open_cargo, false, false)
	hold_btn.custom_minimum_size.y = 36
	var chart_btn = ui.button(actions, "Show entire chart", func():
		ui.close_modal()
		ui.host.chart.territory_view()
	, false, false)
	chart_btn.custom_minimum_size.y = 36
	var close_btn = ui.button(actions, "Close", ui.close_modal, false, false)
	close_btn.custom_minimum_size.y = 36
