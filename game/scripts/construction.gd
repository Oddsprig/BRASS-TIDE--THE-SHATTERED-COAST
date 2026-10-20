extends RefCounted
## Pure physical boat construction blueprint, bronze-cash quote, order escrow, and slipway advance.
## Grounded in a 100-cash ordinary daily wage anchor and physical V-bottom workboat/combat hull scaling
## (reference basis: FAO Fishing Boat Designs 2: V-bottom boats, 5.2-8.5 m planked craft, scaled to 12-25 m combat hulls).
## Never reads or uses legacy spec.price or arbitrary price targets.

const Goods = preload("res://scripts/goods.gd")

const ORDINARY_WAGE: int = 100
const MARGIN_RATE: float = 0.08
const TAX_RATE: float = 0.05

const ORDINARY_OCCUPATIONS: Array[String] = [
	"laborer",
	"shipwright",
	"mechanic",
	"gunsmith"
]

const EXPERT_OCCUPATIONS: Array[String] = [
	"foreman",
	"master shipwright",
	"engineer"
]

const MATERIAL_ORDER: Array[String] = [
	"timber",
	"logs",
	"iron",
	"copper",
	"supplies",
	"engines",
	"guns",
	"fuel"
]

const OCCUPATION_LABELS: Dictionary = {
	"laborer": "Yard Laborers (ordinary rate)",
	"shipwright": "Shipwright Hull Framing & Planking",
	"mechanic": "Fitting Mechanics & Armor Hanging",
	"gunsmith": "Ordnance & Mount Fitters",
	"foreman": "Slipway Foreman Supervision",
	"master shipwright": "Master Shipwright Lofting & Survey",
	"engineer": "Chief Marine & Trials Engineer"
}

const ROLE_GEOMETRY: Dictionary = {
	"skiff": {"refSize": 14.0, "baseLengthM": 6.20, "lengthSlopeM": 0.65, "beamRatio": 0.34, "depthRatio": 0.14},
	"cutter": {"refSize": 14.0, "baseLengthM": 8.50, "lengthSlopeM": 0.90, "beamRatio": 0.27, "depthRatio": 0.15},
	"torpedo": {"refSize": 17.0, "baseLengthM": 12.20, "lengthSlopeM": 0.68, "beamRatio": 0.25, "depthRatio": 0.15},
	"raider": {"refSize": 17.0, "baseLengthM": 12.00, "lengthSlopeM": 0.72, "beamRatio": 0.33, "depthRatio": 0.17},
	"corvette": {"refSize": 17.0, "baseLengthM": 12.40, "lengthSlopeM": 0.72, "beamRatio": 0.30, "depthRatio": 0.17},
	"rocket": {"refSize": 20.0, "baseLengthM": 13.60, "lengthSlopeM": 0.66, "beamRatio": 0.32, "depthRatio": 0.17},
	"gunboat": {"refSize": 22.0, "baseLengthM": 14.80, "lengthSlopeM": 0.72, "beamRatio": 0.35, "depthRatio": 0.18},
	"cruiser": {"refSize": 24.0, "baseLengthM": 16.80, "lengthSlopeM": 0.68, "beamRatio": 0.31, "depthRatio": 0.19}
}

const WEAPON_COMPLEXITY: Dictionary = {
	"none": 0.0,
	"": 0.0,
	"gun": 1.00,
	"cannon": 1.35,
	"rocket": 1.50,
	"torpedo": 1.65
}

const ASSUMPTIONS: Dictionary = {
	"ordinaryWageAnchor": 100,
	"starterLengthM": 6.20,
	"combatLengthRangeM": [12.0, 25.0],
	"referenceBasis": "FAO Fisheries Technical Paper 134 Rev. 2 (2004) V-bottom planked boats (5.2-8.5 m) extrapolated to armored coastal craft",
	"marginRate": MARGIN_RATE,
	"taxRate": TAX_RATE,
	"foremanPerOrdinaryDay": 0.14,
	"slipwayOverheadPerOrdinaryDay": 0.08,
	"slipwayOverheadPerCalendarDay": 0.25,
	"readyWatchDaysPerOrdinaryDay": 0.16,
	"readyWatchDaysPerMeter": 0.35,
	"readyCareenShipwrightPerAreaM2": 0.04
}


static func _finite_float(value: Variant, fallback: float = 0.0) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var f: float = float(value)
		if is_finite(f):
			return f
	return fallback


static func _round2(value: float) -> float:
	return roundf(value * 100.0) / 100.0


static func _derive_weapon_count(spec: Dictionary, size_val: float, _weapon_kind: String, _damage_val: float) -> int:
	if spec.has("weaponCount"):
		return maxi(1, ceili(_finite_float(spec.get("weaponCount"), 1.0) - 1e-6))
	if spec.has("weapons"):
		var w_var: Variant = spec.get("weapons")
		if typeof(w_var) == TYPE_ARRAY:
			return maxi(1, w_var.size())
		return maxi(1, ceili(_finite_float(w_var, 1.0) - 1e-6))
	if size_val <= 15.5:
		return 1
	if size_val <= 22.5:
		return 2
	if size_val <= 29.5:
		return 3
	return 4


static func blueprint(spec: Dictionary) -> Dictionary:
	var hull_id: String = str(spec.get("id", "custom_hull"))
	var hull_name: String = str(spec.get("name", hull_id))
	var role: String = str(spec.get("role", "skiff")).to_lower()
	var tier: int = maxi(1, int(_finite_float(spec.get("tier"), 1.0)))
	var size_val: float = clampf(_finite_float(spec.get("size"), 14.0), 8.0, 48.0)
	var hp_val: float = maxf(40.0, _finite_float(spec.get("hp"), 150.0))
	var armor_val: float = maxf(0.0, _finite_float(spec.get("armor"), 2.0))
	var speed_val: float = clampf(_finite_float(spec.get("speed"), 110.0), 30.0, 220.0)
	var cargo_val: float = maxf(10.0, _finite_float(spec.get("cargo"), 60.0))
	var pumps_val: float = maxf(0.5, _finite_float(spec.get("pumps"), 2.4))
	var weapon_kind: String = str(spec.get("weapon", "gun")).to_lower()
	var fire_rate: float = maxf(0.25, _finite_float(spec.get("fireRate"), 2.0))
	var damage_val: float = maxf(1.0, _finite_float(spec.get("damage"), 12.0))
	var range_val: float = maxf(100.0, _finite_float(spec.get("range"), 340.0))

	var geom: Dictionary = ROLE_GEOMETRY.get(role, ROLE_GEOMETRY["skiff"])
	var ref_size: float = float(geom["refSize"])
	var base_length: float = float(geom["baseLengthM"])
	var length_slope: float = float(geom["lengthSlopeM"])
	var beam_ratio: float = float(geom["beamRatio"])
	var depth_ratio: float = float(geom["depthRatio"])

	var length_m: float = _round2(clampf(base_length + (size_val - ref_size) * length_slope, 4.8, 28.0))
	var cargo_beam_factor: float = 1.0 + clampf(cargo_val - 60.0, -30.0, 220.0) * 0.00045
	var beam_m: float = _round2(clampf(length_m * beam_ratio * cargo_beam_factor, 1.5, 10.5))
	var depth_m: float = _round2(length_m * depth_ratio)
	# V-bottom shell & deck area (bottom + topsides + deck/bulkheads): ~27.45 m2 for starter 6.2m x 2.11m skiff.
	var hull_area_m2: float = _round2(length_m * (beam_m + 2.0 * depth_m) * 1.15)

	# Whole installed propulsion assemblies (>= 1), rounded upward from hull displacement, armor mass, speed, and pumps.
	var disp_factor: float = hull_area_m2 / 27.45
	var armor_mass_factor: float = 1.0 + armor_val * 0.055
	var speed_factor: float = pow(speed_val / 118.0, 1.30)
	var raw_engines: float = 0.42 * pow(disp_factor * armor_mass_factor, 0.72) * speed_factor + 0.08 * (pumps_val / 2.4)
	var engine_units: int = maxi(1, ceili(raw_engines - 1e-6))

	# Whole installed weapon/launcher assemblies (>= 1), rounded upward from weapon mounts, ordnance class, and firepower.
	var weapon_count: int = _derive_weapon_count(spec, size_val, weapon_kind, damage_val)
	var weapon_weight: float = maxf(1.0, float(WEAPON_COMPLEXITY.get(weapon_kind, 1.10)))
	var firepower_factor: float = maxf(0.5, (damage_val / 12.0) * pow(fire_rate / 2.2, 0.35) * (range_val / 340.0))
	var raw_guns: float = float(weapon_count) * weapon_weight * pow(firepower_factor, 0.55) * 0.65
	var weapon_units: int = maxi(maxi(1, weapon_count), ceili(raw_guns - 1e-6))

	var timber_lots: float = _round2(0.13 * hull_area_m2 + 0.008 * cargo_val + 0.003 * hp_val + 0.08 * armor_val + 0.15 * float(weapon_units))
	var log_lots: float = _round2(0.18 * length_m + 0.02 * hull_area_m2 + 0.0015 * hp_val)
	var iron_lots: float = _round2(0.025 * hull_area_m2 + 0.014 * armor_val * pow(hull_area_m2, 0.72) + 0.35 * float(engine_units) + 0.25 * float(weapon_units))
	var copper_lots: float = _round2(0.012 * hull_area_m2 + 0.20 * float(engine_units) + 0.12 * float(weapon_units) + 0.06 * pumps_val)
	var supplies_lots: float = _round2(0.04 * hull_area_m2 + 0.08 * armor_val + 0.18 * pumps_val)
	var fuel_lots: float = _round2(0.75 * float(engine_units) + 0.01 * hull_area_m2)

	var materials: Dictionary = {
		"timber": timber_lots,
		"logs": log_lots,
		"iron": iron_lots,
		"copper": copper_lots,
		"supplies": supplies_lots,
		"engines": engine_units,
		"guns": weapon_units,
		"fuel": fuel_lots
	}
	if spec.has("materials") and typeof(spec.get("materials")) == TYPE_DICTIONARY:
		var mat_overrides: Dictionary = spec.get("materials")
		for k in mat_overrides:
			if materials.has(k):
				var ov_val: float = _finite_float(mat_overrides[k], float(materials[k]))
				if k == "engines" or k == "guns":
					materials[k] = maxi(1, ceili(ov_val - 1e-6))
				else:
					materials[k] = _round2(maxf(0.0, ov_val))

	engine_units = maxi(1, int(materials["engines"]))
	weapon_units = maxi(1, int(materials["guns"]))
	materials["engines"] = engine_units
	materials["guns"] = weapon_units

	var laborer_days: float = _round2(0.22 * hull_area_m2 + 0.35 * float(materials["logs"]) + 0.15 * armor_val)
	var shipwright_days: float = _round2(0.30 * hull_area_m2 + 0.45 * float(materials["timber"]) + 0.35 * armor_val + 0.008 * hp_val)
	var mechanic_days: float = _round2(2.50 * float(engine_units) + 0.45 * pumps_val + 0.35 * float(materials["iron"]) + 0.25 * armor_val)
	var gunsmith_days: float = _round2(1.80 * float(weapon_units) + 0.40 * float(weapon_count))

	var ordinary_labor: Dictionary = {
		"laborer": laborer_days,
		"shipwright": shipwright_days,
		"mechanic": mechanic_days,
		"gunsmith": gunsmith_days
	}
	var ordinary_days: float = _round2(laborer_days + shipwright_days + mechanic_days + gunsmith_days)

	var foreman_days: float = _round2(maxf(0.6, float(ASSUMPTIONS["foremanPerOrdinaryDay"]) * ordinary_days))
	var master_shipwright_days: float = _round2(maxf(0.4, 0.045 * hull_area_m2 + 0.18 * armor_val))
	var engineer_days: float = _round2(maxf(0.6, 1.10 * float(engine_units) + 0.70 * float(weapon_units) + 0.08 * armor_val))

	var expert_labor: Dictionary = {
		"foreman": foreman_days,
		"master shipwright": master_shipwright_days,
		"engineer": engineer_days
	}
	var expert_days: float = _round2(foreman_days + master_shipwright_days + engineer_days)
	var worker_days: float = _round2(ordinary_days + expert_days)

	var labor: Dictionary = {}
	for occ in ORDINARY_OCCUPATIONS:
		labor[occ] = ordinary_labor[occ]
	for occ in EXPERT_OCCUPATIONS:
		labor[occ] = expert_labor[occ]

	var ordinary_slot_cap: float = clampf(roundf(length_m * 0.70), 4.0, 18.0)
	var estimated_days: float = _round2(maxf(2.0, ordinary_days / ordinary_slot_cap))
	var ordinary_team_cap: float = ordinary_days / estimated_days
	var expert_team_cap: float = expert_days / estimated_days
	var team_size: int = maxi(2, ceili(ordinary_team_cap + expert_team_cap - 1e-6))

	var overhead_days: float = _round2(
		float(ASSUMPTIONS["slipwayOverheadPerOrdinaryDay"]) * ordinary_days
		+ float(ASSUMPTIONS["slipwayOverheadPerCalendarDay"]) * estimated_days
	)
	var ready_watch_days: float = _round2(
		float(ASSUMPTIONS["readyWatchDaysPerOrdinaryDay"]) * ordinary_days
		+ float(ASSUMPTIONS["readyWatchDaysPerMeter"]) * length_m
	)
	var ready_careen_days: float = _round2(
		float(ASSUMPTIONS["readyCareenShipwrightPerAreaM2"]) * hull_area_m2
	)

	return {
		"id": hull_id,
		"name": hull_name,
		"role": role,
		"tier": tier,
		"lengthM": length_m,
		"beamM": beam_m,
		"depthM": depth_m,
		"hullAreaM2": hull_area_m2,
		"engineUnits": engine_units,
		"weaponCount": weapon_count,
		"weaponUnits": weapon_units,
		"materials": materials,
		"labor": labor,
		"ordinaryLabor": ordinary_labor,
		"expertLabor": expert_labor,
		"ordinaryDays": ordinary_days,
		"expertDays": expert_days,
		"workerDays": worker_days,
		"ordinaryTeamCap": ordinary_team_cap,
		"expertTeamCap": expert_team_cap,
		"teamSize": team_size,
		"estimatedDays": estimated_days,
		"overheadDays": overhead_days,
		"readyWatchDays": ready_watch_days,
		"readyCareenDays": ready_careen_days,
		"readyStorageDays": _round2(ready_watch_days + ready_careen_days),
		"assumptions": ASSUMPTIONS.duplicate(true)
	}


static func _resolve_wages(spec: Dictionary, prices: Dictionary, wages_override: Dictionary) -> Dictionary:
	var wages: Dictionary = Goods.WAGES.duplicate(true)
	var wage_scale: float = 1.0
	if spec.has("wageScale"):
		wage_scale *= maxf(0.1, _finite_float(spec.get("wageScale"), 1.0))
	if prices.has("wageScale"):
		wage_scale *= maxf(0.1, _finite_float(prices.get("wageScale"), 1.0))
	if prices.has("wageMultiplier"):
		wage_scale *= maxf(0.1, _finite_float(prices.get("wageMultiplier"), 1.0))
	if wage_scale != 1.0:
		for occ in wages:
			wages[occ] = maxi(1, roundi(float(wages[occ]) * wage_scale))

	var sources: Array[Dictionary] = []
	if spec.has("wages") and typeof(spec.get("wages")) == TYPE_DICTIONARY:
		sources.append(spec.get("wages"))
	if prices.has("wages") and typeof(prices.get("wages")) == TYPE_DICTIONARY:
		sources.append(prices.get("wages"))
	sources.append(prices)
	sources.append(wages_override)

	for src in sources:
		for k in src:
			if k == "laborer" or k == "ordinary":
				var w_val: float = _finite_float(src[k], -1.0)
				if w_val > 0.0:
					wages["laborer"] = maxi(1, roundi(w_val))
			elif wages.has(k) and (typeof(src[k]) == TYPE_INT or typeof(src[k]) == TYPE_FLOAT):
				var w_occ: float = _finite_float(src[k], -1.0)
				if w_occ > 0.0:
					wages[k] = maxi(1, roundi(w_occ))
	return wages


static func _good_cost_with_wages(good: String, wages: Dictionary) -> float:
	if not Goods.ITEMS.has(good):
		return 0.0
	var recipe: Dictionary = Goods.ITEMS[good]
	var total_val: float = 0.0
	for occ in recipe["labor"]:
		total_val += float(recipe["labor"][occ]) * float(wages.get(occ, Goods.WAGES.get(occ, ORDINARY_WAGE)))
	for ing in recipe["inputs"]:
		total_val += float(recipe["inputs"][ing]) * _good_cost_with_wages(ing, wages)
	return total_val


static func _resolve_prices(prices_override: Dictionary, wages: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var nested_prices: Dictionary = {}
	if prices_override.has("prices") and typeof(prices_override.get("prices")) == TYPE_DICTIONARY:
		nested_prices = prices_override.get("prices")

	for good in Goods.ITEMS:
		var unit_price: float = _good_cost_with_wages(good, wages)
		if nested_prices.has(good):
			var np: float = _finite_float(nested_prices[good], -1.0)
			if np > 0.0:
				unit_price = np
		elif prices_override.has(good) and (typeof(prices_override[good]) == TYPE_INT or typeof(prices_override[good]) == TYPE_FLOAT):
			var p: float = _finite_float(prices_override[good], -1.0)
			if p > 0.0:
				unit_price = p
		result[good] = unit_price
	return result


static func quote(spec: Dictionary, prices: Dictionary = {}, wages_override: Dictionary = {}) -> Dictionary:
	var bp: Dictionary = blueprint(spec)
	var effective_wages: Dictionary = _resolve_wages(spec, prices, wages_override)
	var effective_prices: Dictionary = _resolve_prices(prices, effective_wages)

	var line_items: Array[Dictionary] = []
	var material_costs: Dictionary = {}
	var material_cost_total: int = 0
	var materials: Dictionary = bp["materials"]

	for good in MATERIAL_ORDER:
		if not materials.has(good):
			continue
		var qty: float = float(materials[good])
		if qty <= 0.0:
			material_costs[good] = 0
			continue
		var unit_cost: float = float(effective_prices.get(good, Goods.cost(good)))
		var item_cost: int = maxi(1, roundi(qty * unit_cost))
		material_costs[good] = item_cost
		material_cost_total += item_cost
		var item_def: Dictionary = Goods.ITEMS.get(good, {})
		line_items.append({
			"key": good,
			"label": str(item_def.get("name", good)),
			"category": "material",
			"qty": qty,
			"unit": str(item_def.get("unit", "lots")),
			"unitCost": _round2(unit_cost),
			"cost": item_cost,
			"amount": item_cost
		})

	var labor_costs: Dictionary = {}
	var labor_cost_total: int = 0
	var ordinary_labor: Dictionary = bp["ordinaryLabor"]
	for occ in ORDINARY_OCCUPATIONS:
		var days_val: float = float(ordinary_labor.get(occ, 0.0))
		if days_val <= 0.0:
			labor_costs[occ] = 0
			continue
		var wage_rate: int = int(effective_wages.get(occ, ORDINARY_WAGE))
		var occ_cost: int = maxi(1, roundi(days_val * float(wage_rate)))
		labor_costs[occ] = occ_cost
		labor_cost_total += occ_cost
		line_items.append({
			"key": occ,
			"label": str(OCCUPATION_LABELS.get(occ, occ)),
			"category": "labor",
			"qty": days_val,
			"unit": "worker-days",
			"unitCost": float(wage_rate),
			"cost": occ_cost,
			"amount": occ_cost
		})

	var supervision_cost_total: int = 0
	var expert_labor: Dictionary = bp["expertLabor"]
	for occ in EXPERT_OCCUPATIONS:
		var days_val: float = float(expert_labor.get(occ, 0.0))
		if days_val <= 0.0:
			labor_costs[occ] = 0
			continue
		var wage_rate: int = int(effective_wages.get(occ, 200))
		var occ_cost: int = maxi(1, roundi(days_val * float(wage_rate)))
		labor_costs[occ] = occ_cost
		supervision_cost_total += occ_cost
		line_items.append({
			"key": occ,
			"label": str(OCCUPATION_LABELS.get(occ, occ)),
			"category": "supervision",
			"qty": days_val,
			"unit": "worker-days",
			"unitCost": float(wage_rate),
			"cost": occ_cost,
			"amount": occ_cost
		})

	var ordinary_wage_rate: int = int(effective_wages.get("laborer", ORDINARY_WAGE))
	var shipwright_wage_rate: int = int(effective_wages.get("shipwright", 125))
	var overhead_days: float = float(bp["overheadDays"])
	var overhead_cost: int = maxi(1, roundi(overhead_days * float(ordinary_wage_rate)))
	line_items.append({
		"key": "overhead",
		"label": "Slipway, Lofting Floor & Tool-Crib Upkeep",
		"category": "overhead",
		"qty": overhead_days,
		"unit": "worker-days",
		"unitCost": float(ordinary_wage_rate),
		"cost": overhead_cost,
		"amount": overhead_cost
	})

	var direct_subtotal: int = material_cost_total + labor_cost_total + supervision_cost_total + overhead_cost
	var margin_cost: int = maxi(1, roundi(float(direct_subtotal) * MARGIN_RATE))
	line_items.append({
		"key": "margin",
		"label": "Shipyard Operating Margin (8%)",
		"category": "margin",
		"qty": 1.0,
		"unit": "lot",
		"unitCost": float(margin_cost),
		"cost": margin_cost,
		"amount": margin_cost
	})

	var pre_tax_total: int = direct_subtotal + margin_cost
	var tax_cost: int = maxi(1, roundi(float(pre_tax_total) * TAX_RATE))
	line_items.append({
		"key": "tax",
		"label": "Harbor Hull Registry & Stamp Tax (5%)",
		"category": "tax",
		"qty": 1.0,
		"unit": "lot",
		"unitCost": float(tax_cost),
		"cost": tax_cost,
		"amount": tax_cost
	})

	var total_cost: int = material_cost_total + labor_cost_total + supervision_cost_total + overhead_cost + margin_cost + tax_cost
	var commission_price: int = total_cost

	# Ready-built stock hulls carry additional basin watchman, hull careening, and working-capital risk.
	var ready_watch_days: float = float(bp["readyWatchDays"])
	var ready_careen_days: float = float(bp["readyCareenDays"])
	var ready_storage_labor_cost: int = maxi(
		1,
		roundi(ready_watch_days * float(ordinary_wage_rate) + ready_careen_days * float(shipwright_wage_rate))
	)
	var ready_storage_margin: int = roundi(float(ready_storage_labor_cost) * MARGIN_RATE)
	var ready_storage_tax: int = roundi(float(ready_storage_labor_cost + ready_storage_margin) * TAX_RATE)
	var ready_storage_total: int = ready_storage_labor_cost + ready_storage_margin + ready_storage_tax
	var ready_price: int = commission_price + ready_storage_total

	var out: Dictionary = bp.duplicate(true)
	out["prices"] = effective_prices
	out["wages"] = effective_wages
	out["materialCosts"] = material_costs
	out["laborCosts"] = labor_costs
	out["materialCost"] = material_cost_total
	out["laborCost"] = labor_cost_total
	out["supervisionCost"] = supervision_cost_total
	out["ordinaryWageCost"] = labor_cost_total
	out["expertWageCost"] = supervision_cost_total
	out["escrow"] = labor_cost_total + supervision_cost_total
	out["overhead"] = overhead_cost
	out["margin"] = margin_cost
	out["tax"] = tax_cost
	out["total"] = total_cost
	out["commissionPrice"] = commission_price
	out["readyStorageLaborCost"] = ready_storage_labor_cost
	out["readyStorageMargin"] = ready_storage_margin
	out["readyStorageTax"] = ready_storage_tax
	out["readyStorageCost"] = ready_storage_total
	out["readyPrice"] = ready_price
	out["commissionDiscount"] = ready_price - commission_price
	out["lineItems"] = line_items
	return out


static func make_order(spec: Dictionary, quote_data: Dictionary = {}, owner: String = "player") -> Dictionary:
	var q: Dictionary = quote_data if (not quote_data.is_empty() and quote_data.has("total") and quote_data.has("laborCost")) else quote(spec, quote_data)
	var hull_id: String = str(spec.get("id", q.get("id", "custom_hull")))
	var hull_name: String = str(spec.get("name", q.get("name", hull_id)))
	var clean_owner: String = owner if owner != "" else "player"

	var ordinary_days: float = maxf(0.01, _finite_float(q.get("ordinaryDays"), 1.0))
	var expert_days: float = maxf(0.01, _finite_float(q.get("expertDays"), 0.5))
	var worker_days: float = _round2(ordinary_days + expert_days)
	var estimated_days: float = maxf(0.1, _finite_float(q.get("estimatedDays"), 1.0))

	var labor_target: int = maxi(0, int(_finite_float(q.get("laborCost"), 0.0)))
	var supervision_target: int = maxi(0, int(_finite_float(q.get("supervisionCost"), 0.0)))
	var initial_escrow: int = labor_target + supervision_target

	var mat_cost: int = maxi(0, int(_finite_float(q.get("materialCost"), 0.0)))
	var overhead_cost: int = maxi(0, int(_finite_float(q.get("overhead"), 0.0)))
	var margin_cost: int = maxi(0, int(_finite_float(q.get("margin"), 0.0)))
	var tax_cost: int = maxi(0, int(_finite_float(q.get("tax"), 0.0)))
	var total_cost: int = maxi(0, int(_finite_float(q.get("total"), float(mat_cost + initial_escrow + overhead_cost + margin_cost + tax_cost))))

	return {
		"id": "order_%s_%s" % [hull_id, clean_owner],
		"hull": hull_id,
		"hullId": hull_id,
		"name": hull_name,
		"owner": clean_owner,
		"fundingSource": "businessPurse" if clean_owner == "yard" else "buyer",
		"ready": false,
		"finished": false,
		"progress": 0.0,
		"ordinaryDays": ordinary_days,
		"expertDays": expert_days,
		"workerDays": worker_days,
		"remainingOrdinaryDays": ordinary_days,
		"remainingExpertDays": expert_days,
		"remainingWorkerDays": worker_days,
		"workedOrdinaryDays": 0.0,
		"workedExpertDays": 0.0,
		"workedDays": 0.0,
		"elapsedDays": 0.0,
		"estimatedDays": estimated_days,
		"initialEstimatedDays": estimated_days,
		"ordinaryTeamCap": maxf(1.0, _finite_float(q.get("ordinaryTeamCap"), 6.0)),
		"expertTeamCap": maxf(0.5, _finite_float(q.get("expertTeamCap"), 1.5)),
		"teamSize": maxi(1, int(_finite_float(q.get("teamSize"), 8.0))),
		"escrow": initial_escrow,
		"initialEscrow": initial_escrow,
		"laborTarget": labor_target,
		"supervisionTarget": supervision_target,
		"laborPaid": 0,
		"supervisionPaid": 0,
		"materialCost": mat_cost,
		"laborCost": labor_target,
		"supervisionCost": supervision_target,
		"overhead": overhead_cost,
		"margin": margin_cost,
		"tax": tax_cost,
		"total": total_cost,
		"materials": q.get("materials", {}).duplicate(true),
		"labor": q.get("labor", {}).duplicate(true),
		"paymentSplit": {
			"businessCash": mat_cost + overhead_cost + margin_cost,
			"governmentTax": tax_cost,
			"wageEscrow": initial_escrow,
			"total": total_cost
		}
	}


static func _extract_specialist_count(raw: Variant) -> float:
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
		return maxf(0.0, _finite_float(raw, 0.0))
	if typeof(raw) == TYPE_DICTIONARY:
		var d: Dictionary = raw
		var total_count: float = 0.0
		for k in d:
			total_count += maxf(0.0, _finite_float(d[k], 0.0))
		return total_count
	return 0.0


static func _available_total_workers(port: Dictionary) -> float:
	var busy: float = maxf(0.0, _finite_float(port.get("workers"), 0.0)) + maxf(0.0, _finite_float(port.get("publicWorkers"), 0.0))
	if port.has("workforce"):
		var wf: float = maxf(0.0, _finite_float(port.get("workforce"), 0.0))
		var free_wf: float = maxf(0.0, wf - busy)
		if port.has("availableWorkers"):
			return maxf(0.0, minf(free_wf, _finite_float(port.get("availableWorkers"), free_wf)))
		return free_wf
	if port.has("availableWorkers"):
		return maxf(0.0, _finite_float(port.get("availableWorkers"), 0.0))
	if port.has("population"):
		var pop_wf: float = maxf(0.0, _finite_float(port.get("population"), 0.0) * 0.12 - busy)
		return pop_wf
	return 0.0


static func _available_specialists(port: Dictionary, base_total_workers: float) -> float:
	var busy_spec: float = maxf(0.0, _finite_float(port.get("busySpecialists"), 0.0))
	if port.has("availableSpecialists"):
		var avail_spec: float = maxf(0.0, _extract_specialist_count(port.get("availableSpecialists")) - busy_spec)
		if port.has("specialists"):
			var total_spec: float = maxf(0.0, _extract_specialist_count(port.get("specialists")) - busy_spec)
			avail_spec = minf(avail_spec, total_spec)
		return avail_spec

	var spec_keys: Array[String] = ["specialists", "supervisors", "expertWorkers", "experts"]
	for key in spec_keys:
		if port.has(key):
			var count: float = _extract_specialist_count(port.get(key))
			return maxf(0.0, count - busy_spec)
	if base_total_workers <= 0.0:
		return 0.0
	return maxf(1.0, floorf(base_total_workers * 0.15))


static func begin_day(port: Dictionary) -> Dictionary:
	if port.has("_yardStepOrders"):
		port.erase("_yardStepOrders")
	if port.has("_yardStepSig"):
		port.erase("_yardStepSig")
	var base_total: float = _available_total_workers(port)
	var base_specialists: float = _available_specialists(port, base_total)
	port["_yardWorkersUsed"] = 0.0
	port["_yardOrdinaryUsed"] = 0.0
	port["_yardSpecialistsUsed"] = 0.0
	port["yardWorkersReserved"] = 0.0
	port["yardOrdinaryReserved"] = 0.0
	port["yardSpecialistsReserved"] = 0.0
	port["yardAvailableWorkers"] = _round2(base_total)
	port["yardAvailableSpecialists"] = _round2(base_specialists)
	return port


static func _record_yard_reservation(port: Dictionary, base_total: float, base_specialists: float, add_total: float, add_ordinary: float, add_specialists: float) -> void:
	var used_total: float = clampf(_finite_float(port.get("_yardWorkersUsed"), 0.0) + maxf(0.0, add_total), 0.0, base_total)
	var used_ord: float = clampf(_finite_float(port.get("_yardOrdinaryUsed"), 0.0) + maxf(0.0, add_ordinary), 0.0, base_total)
	var used_spec: float = clampf(_finite_float(port.get("_yardSpecialistsUsed"), 0.0) + maxf(0.0, add_specialists), 0.0, base_specialists)
	port["_yardWorkersUsed"] = used_total
	port["_yardOrdinaryUsed"] = used_ord
	port["_yardSpecialistsUsed"] = used_spec
	port["yardWorkersReserved"] = _round2(used_total)
	port["yardOrdinaryReserved"] = _round2(used_ord)
	port["yardSpecialistsReserved"] = _round2(used_spec)
	port["yardAvailableWorkers"] = _round2(maxf(0.0, base_total - used_total))
	port["yardAvailableSpecialists"] = _round2(maxf(0.0, base_specialists - used_spec))


static func advance(port: Dictionary, order: Dictionary, days: float) -> Dictionary:
	var hull_id: String = str(order.get("hull", order.get("hullId", "")))
	var owner: String = str(order.get("owner", "player"))
	var total_ordinary: float = maxf(0.01, _finite_float(order.get("ordinaryDays"), 1.0))
	var total_expert: float = maxf(0.01, _finite_float(order.get("expertDays"), 0.5))
	var total_worker_days: float = total_ordinary + total_expert

	var rem_worker_days: float = maxf(0.0, _finite_float(order.get("remainingWorkerDays"), total_worker_days))
	var is_already_done: bool = bool(order.get("ready", false)) or bool(order.get("finished", false)) or rem_worker_days <= 1e-6
	var dt: float = _finite_float(days, 0.0)

	if is_already_done:
		order["ready"] = true
		order["finished"] = true
		order["remainingOrdinaryDays"] = 0.0
		order["remainingExpertDays"] = 0.0
		order["remainingWorkerDays"] = 0.0
		order["estimatedDays"] = 0.0
		order["progress"] = 1.0
		return {
			"ok": true,
			"finished": true,
			"ready": true,
			"progress": 1.0,
			"progressDelta": 0.0,
			"spent": 0,
			"laborSpent": 0,
			"supervisionSpent": 0,
			"workedDays": 0.0,
			"ordinaryWorked": 0.0,
			"expertWorked": 0.0,
			"reservedWorkers": 0.0,
			"reservedOrdinaryWorkers": 0.0,
			"reservedSpecialists": 0.0,
			"remainingWorkerDays": 0.0,
			"estimatedDays": 0.0,
			"escrow": maxi(0, int(_finite_float(order.get("escrow"), 0.0))),
			"owner": owner,
			"hull": hull_id
		}

	var current_escrow: int = maxi(0, int(_finite_float(order.get("escrow"), 0.0)))
	if dt <= 0.0:
		var cur_prog_idle: float = clampf(_finite_float(order.get("progress"), 0.0), 0.0, 1.0)
		return {
			"ok": true,
			"finished": false,
			"ready": false,
			"progress": cur_prog_idle,
			"progressDelta": 0.0,
			"spent": 0,
			"laborSpent": 0,
			"supervisionSpent": 0,
			"workedDays": 0.0,
			"ordinaryWorked": 0.0,
			"expertWorked": 0.0,
			"reservedWorkers": 0.0,
			"reservedOrdinaryWorkers": 0.0,
			"reservedSpecialists": 0.0,
			"remainingWorkerDays": rem_worker_days,
			"estimatedDays": maxf(0.0, _finite_float(order.get("estimatedDays"), 1.0)),
			"escrow": current_escrow,
			"owner": owner,
			"hull": hull_id
		}

	var base_total: float = _available_total_workers(port)
	var base_specialists: float = _available_specialists(port, base_total)
	var used_total: float = clampf(_finite_float(port.get("_yardWorkersUsed"), 0.0), 0.0, base_total)
	var used_specialists: float = clampf(_finite_float(port.get("_yardSpecialistsUsed"), 0.0), 0.0, base_specialists)
	var free_total: float = maxf(0.0, base_total - used_total)
	var free_specialists: float = maxf(0.0, base_specialists - used_specialists)

	var ordinary_cap: float = maxf(1.0, _finite_float(order.get("ordinaryTeamCap"), 6.0))
	var expert_cap: float = maxf(0.5, _finite_float(order.get("expertTeamCap"), 1.5))

	var eff_ordinary_workers: float = minf(free_total, ordinary_cap)
	var eff_expert_workers: float = minf(free_specialists, minf(free_total, expert_cap))

	if current_escrow <= 0 or free_total <= 1e-6 or eff_ordinary_workers <= 1e-6 or eff_expert_workers <= 1e-6:
		_record_yard_reservation(port, base_total, base_specialists, 0.0, 0.0, 0.0)
		var cur_progress: float = clampf(_finite_float(order.get("progress"), 0.0), 0.0, 1.0)
		return {
			"ok": true,
			"finished": false,
			"ready": false,
			"progress": cur_progress,
			"progressDelta": 0.0,
			"spent": 0,
			"laborSpent": 0,
			"supervisionSpent": 0,
			"workedDays": 0.0,
			"ordinaryWorked": 0.0,
			"expertWorked": 0.0,
			"reservedWorkers": 0.0,
			"reservedOrdinaryWorkers": 0.0,
			"reservedSpecialists": 0.0,
			"remainingWorkerDays": rem_worker_days,
			"estimatedDays": maxf(0.0, _finite_float(order.get("estimatedDays"), 1.0)),
			"escrow": current_escrow,
			"owner": owner,
			"hull": hull_id
		}

	var worked_ordinary_prev: float = clampf(_finite_float(order.get("workedOrdinaryDays"), 0.0), 0.0, total_ordinary)
	var worked_expert_prev: float = clampf(_finite_float(order.get("workedExpertDays"), 0.0), 0.0, total_expert)
	var worked_prev: float = worked_ordinary_prev + worked_expert_prev
	var rem_fraction: float = clampf((total_worker_days - worked_prev) / total_worker_days, 0.0, 1.0)

	var total_fraction_cap: float = (free_total * dt) / total_worker_days
	var ordinary_fraction_cap: float = (eff_ordinary_workers * dt) / total_ordinary
	var expert_fraction_cap: float = (eff_expert_workers * dt) / total_expert
	var max_step_fraction: float = minf(rem_fraction, minf(total_fraction_cap, minf(ordinary_fraction_cap, expert_fraction_cap)))

	var labor_paid_prev: int = maxi(0, int(_finite_float(order.get("laborPaid"), 0.0)))
	var supervision_paid_prev: int = maxi(0, int(_finite_float(order.get("supervisionPaid"), 0.0)))
	var labor_target: int = maxi(labor_paid_prev, int(_finite_float(order.get("laborTarget"), _finite_float(order.get("laborCost"), 0.0))))
	var supervision_target: int = maxi(supervision_paid_prev, int(_finite_float(order.get("supervisionTarget"), _finite_float(order.get("supervisionCost"), 0.0))))
	var remaining_target_wages: int = (labor_target - labor_paid_prev) + (supervision_target - supervision_paid_prev)

	if remaining_target_wages > 0 and current_escrow < remaining_target_wages:
		var affordable_rem_ratio: float = float(current_escrow) / float(remaining_target_wages)
		max_step_fraction = minf(max_step_fraction, rem_fraction * affordable_rem_ratio)

	if max_step_fraction <= 1e-9:
		_record_yard_reservation(port, base_total, base_specialists, 0.0, 0.0, 0.0)
		return {
			"ok": true,
			"finished": false,
			"ready": false,
			"progress": clampf(worked_prev / total_worker_days, 0.0, 1.0),
			"progressDelta": 0.0,
			"spent": 0,
			"laborSpent": 0,
			"supervisionSpent": 0,
			"workedDays": 0.0,
			"ordinaryWorked": 0.0,
			"expertWorked": 0.0,
			"reservedWorkers": 0.0,
			"reservedOrdinaryWorkers": 0.0,
			"reservedSpecialists": 0.0,
			"remainingWorkerDays": rem_worker_days,
			"estimatedDays": maxf(0.0, _finite_float(order.get("estimatedDays"), 1.0)),
			"escrow": current_escrow,
			"owner": owner,
			"hull": hull_id
		}

	var ordinary_worked: float = max_step_fraction * total_ordinary
	var expert_worked: float = max_step_fraction * total_expert
	var worked_now: float = ordinary_worked + expert_worked
	var reserved_ordinary_now: float = ordinary_worked / dt
	var reserved_specialist_now: float = expert_worked / dt
	var reserved_total_now: float = worked_now / dt
	_record_yard_reservation(port, base_total, base_specialists, reserved_total_now, reserved_ordinary_now, reserved_specialist_now)

	var new_worked_ordinary: float = minf(total_ordinary, worked_ordinary_prev + ordinary_worked)
	var new_worked_expert: float = minf(total_expert, worked_expert_prev + expert_worked)
	var new_worked_total: float = minf(total_worker_days, new_worked_ordinary + new_worked_expert)
	var new_rem_total: float = maxf(0.0, total_worker_days - new_worked_total)

	var can_complete_escrow: bool = current_escrow >= remaining_target_wages
	var is_complete: bool = (new_rem_total <= 1e-4) and can_complete_escrow

	if is_complete:
		new_worked_ordinary = total_ordinary
		new_worked_expert = total_expert
		new_worked_total = total_worker_days
		new_rem_total = 0.0

	var completion_ratio: float = 1.0 if is_complete else clampf(new_worked_total / total_worker_days, 0.0, 1.0)

	var desired_labor_cum: int = labor_target if is_complete else clampi(int(floor(float(labor_target) * completion_ratio + 1e-7)), labor_paid_prev, labor_target)
	var desired_supervision_cum: int = supervision_target if is_complete else clampi(int(floor(float(supervision_target) * completion_ratio + 1e-7)), supervision_paid_prev, supervision_target)

	var labor_spent: int = clampi(desired_labor_cum - labor_paid_prev, 0, current_escrow)
	var supervision_spent: int = clampi(desired_supervision_cum - supervision_paid_prev, 0, current_escrow - labor_spent)

	# If escrow hits its exact limit on a partial escrow cap, pay out the remaining affordable coins cleanly.
	if not is_complete and remaining_target_wages > 0 and current_escrow < remaining_target_wages:
		if absf(max_step_fraction - rem_fraction * (float(current_escrow) / float(remaining_target_wages))) <= 1e-6:
			var leftover: int = current_escrow - (labor_spent + supervision_spent)
			if leftover > 0:
				var add_lab: int = mini(leftover, (labor_target - labor_paid_prev) - labor_spent)
				labor_spent += add_lab
				leftover -= add_lab
				var add_sup: int = mini(leftover, (supervision_target - supervision_paid_prev) - supervision_spent)
				supervision_spent += add_sup

	var total_spent: int = labor_spent + supervision_spent
	var new_escrow: int = current_escrow - total_spent

	port["householdPurse"] = int(_finite_float(port.get("householdPurse"), 0.0)) + labor_spent
	port["expertPurse"] = int(_finite_float(port.get("expertPurse"), 0.0)) + supervision_spent

	order["escrow"] = new_escrow
	order["laborPaid"] = labor_paid_prev + labor_spent
	order["supervisionPaid"] = supervision_paid_prev + supervision_spent
	order["workedOrdinaryDays"] = new_worked_ordinary if not is_complete else total_ordinary
	order["workedExpertDays"] = new_worked_expert if not is_complete else total_expert
	order["workedDays"] = new_worked_total if not is_complete else total_worker_days
	order["remainingOrdinaryDays"] = maxf(0.0, total_ordinary - new_worked_ordinary) if not is_complete else 0.0
	order["remainingExpertDays"] = maxf(0.0, total_expert - new_worked_expert) if not is_complete else 0.0
	order["remainingWorkerDays"] = new_rem_total if not is_complete else 0.0
	order["elapsedDays"] = _round2(_finite_float(order.get("elapsedDays"), 0.0) + dt)

	var daily_rate_fraction: float = minf(free_total / total_worker_days, minf(eff_ordinary_workers / total_ordinary, eff_expert_workers / total_expert))
	var rem_fraction_after: float = maxf(0.0, 1.0 - completion_ratio)
	order["estimatedDays"] = 0.0 if is_complete else _round2(rem_fraction_after / maxf(1e-4, daily_rate_fraction))
	order["progress"] = 1.0 if is_complete else _round2(completion_ratio)
	order["ready"] = is_complete
	order["finished"] = is_complete

	return {
		"ok": true,
		"finished": is_complete,
		"ready": is_complete,
		"progress": float(order["progress"]),
		"progressDelta": _round2(max_step_fraction),
		"spent": total_spent,
		"laborSpent": labor_spent,
		"supervisionSpent": supervision_spent,
		"workedDays": _round2(worked_now),
		"ordinaryWorked": _round2(ordinary_worked),
		"expertWorked": _round2(expert_worked),
		"reservedWorkers": _round2(reserved_total_now),
		"reservedOrdinaryWorkers": _round2(reserved_ordinary_now),
		"reservedSpecialists": _round2(reserved_specialist_now),
		"remainingWorkerDays": float(order["remainingWorkerDays"]),
		"estimatedDays": float(order["estimatedDays"]),
		"escrow": new_escrow,
		"owner": owner,
		"hull": hull_id
	}
