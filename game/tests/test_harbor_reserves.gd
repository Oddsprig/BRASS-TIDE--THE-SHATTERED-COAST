extends SceneTree

const ReservesScript = preload("res://scripts/harbor_reserves.gd")
const GoodsData = preload("res://scripts/goods.gd")

const ESSENTIALS: Array[String] = ["food", "supplies", "fuel", "ammo"]
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_coverage()
	_test_inventory_separation()
	_test_contracts_and_read_only_quotes()
	_test_policy_and_bounds()
	_test_production()
	_test_scarce_inputs()
	_test_malformed_fields()
	if _failures == 0:
		print("PASS: harbor reserve invariants")
	else:
		push_error("Harbor reserves: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _port(workforce: float = 100.0) -> Dictionary:
	return {
		"workforce": workforce,
		"stocks": {},
		"publicStores": {},
		"cash": 1234,
		"governmentPurse": 5678,
		"reserves": {
			"schema": 1,
			"policy": "security",
			"resupplyDays": 4.0,
			"observedDemand": {},
			"incoming": {},
			"contractedLots": {},
			"availableRecipes": [],
		},
	}


func _test_coverage() -> void:
	var small: Dictionary = _port(10.0)
	var large: Dictionary = _port(1000.0)
	var small_stocks: Dictionary = small["stocks"]
	var large_stocks: Dictionary = large["stocks"]
	small_stocks["food"] = 2.0
	large_stocks["food"] = 2.0
	var small_report: Dictionary = ReservesScript.report(small)
	var large_report: Dictionary = ReservesScript.report(large)
	_near(float(small_report["householdFoodPerDay"]), 0.8, "Small resident demand")
	_near(float(large_report["householdFoodPerDay"]), 80.0, "Large resident demand")
	var small_food: Dictionary = _row(small, "food")
	var large_food: Dictionary = _row(large, "food")
	_near(float(small_food["commercialCoverageDays"]), 2.5, "Small coverage")
	_near(float(large_food["commercialCoverageDays"]), 0.025, "Large coverage")

	small_stocks["supplies"] = 7.0
	var supplies: Dictionary = _row(small, "supplies")
	_check(bool(supplies["noDemand"]), "Unobserved supplies have no invented demand")
	_near(float(supplies["commercialCoverageDays"]), 0.0, "No-demand coverage is finite")
	_near(ReservesScript.exportable(small, "supplies"), 7.0, "No-demand stock remains tradable")
	var empty: Dictionary = _port()
	for good: String in ESSENTIALS:
		_near(ReservesScript.exportable(empty, good), 0.0, "Zero stock exports " + good)

	small["projectedProduction"] = {"ammo": 1000000.0}
	var ammo: Dictionary = _row(small, "ammo")
	_near(float(ammo["dailyDemand"]), 0.0, "Production projection is not consumption")


func _test_inventory_separation() -> void:
	var port: Dictionary = _port()
	var stocks: Dictionary = port["stocks"]
	stocks["food"] = 12.0
	var before: Dictionary = _row(port, "food")
	_near(float(before["exportable"]), 4.0, "Scarce cargo above operating minimum can export")

	var public_stores: Dictionary = port["publicStores"]
	public_stores["food"] = 1000.0
	var settings: Dictionary = port["reserves"]
	settings["incoming"] = {"food": 1000.0}
	var after: Dictionary = _row(port, "food")
	_near(float(after["exportable"]), float(before["exportable"]), "Public stock does not replace commercial buffer")
	_near(float(after["commercialCoverageDays"]), 1.5, "Incoming excluded from coverage")
	_near(float(after["publicCoverageDays"]), 125.0, "Public coverage reported separately")
	_near(float(after["incoming"]), 1000.0, "Incoming remains a distinct quantity")


func _test_contracts_and_read_only_quotes() -> void:
	var port: Dictionary = _production_port()
	var stocks: Dictionary = port["stocks"]
	stocks["supplies"] = 7.0
	var settings: Dictionary = port["reserves"]
	settings["observedDemand"] = {}
	settings["contractedLots"] = {"supplies": 2.0}
	_near(ReservesScript.exportable(port, "supplies"), 5.0, "Only actual contracted subset withheld")
	_check(ReservesScript.validate(port) == "", "Valid contracted snapshot")

	var before: Dictionary = port.duplicate(true)
	ReservesScript.ensure(port)
	var unused_report: Dictionary = ReservesScript.report(port)
	var unused_quote: float = ReservesScript.exportable(port, "food")
	var unused_floors: Dictionary = ReservesScript.allocation_floors(port, 100.0)
	var policy_result: Dictionary = ReservesScript.set_policy(port, "commercial")
	_check(not unused_report.is_empty(), "Report produced")
	_check(unused_quote >= 0.0 and _all_finite(unused_floors), "Quote/floors finite")
	_check(bool(policy_result["ok"]), "Local policy accepted")
	_check(port["stocks"] == before["stocks"], "APIs do not clone, consume or transfer stocks")
	_check(port["publicStores"] == before["publicStores"], "APIs do not release public stock")
	_check(port["cash"] == before["cash"], "Commercial purse unchanged")
	_check(port["governmentPurse"] == before["governmentPurse"], "Public purse unchanged")

	var current: Dictionary = port["reserves"]
	current["contractedLots"] = {"supplies": 99.0}
	_check(ReservesScript.validate(port) != "", "Overcommitted stock diagnosed")
	_near(ReservesScript.exportable(port, "supplies"), 0.0, "Overcommit cannot make exports negative")


func _test_policy_and_bounds() -> void:
	var port: Dictionary = _port()
	var stocks: Dictionary = port["stocks"]
	stocks["food"] = 12.0
	var security_quote: float = ReservesScript.exportable(port, "food")
	var result: Dictionary = ReservesScript.set_policy(port, "commercial")
	_check(bool(result["ok"]), "Commercial policy accepted")
	_check(ReservesScript.exportable(port, "food") > security_quote, "Commercial policy uses smaller buffer")
	var before: Dictionary = port.duplicate(true)
	result = ReservesScript.set_policy(port, "withhold everything")
	_check(not bool(result["ok"]), "Unknown policy rejected")
	_check(port == before, "Rejected policy leaves port unchanged")

	var settings: Dictionary = port["reserves"]
	settings["resupplyDays"] = -9.0
	ReservesScript.ensure(port)
	var snapshot: Dictionary = ReservesScript.report(port)
	_near(float(snapshot["resupplyDays"]), 1.0, "Route horizon lower bound")
	settings = port["reserves"]
	settings["resupplyDays"] = 99999.0
	ReservesScript.ensure(port)
	snapshot = ReservesScript.report(port)
	_near(float(snapshot["resupplyDays"]), 14.0, "Route horizon upper bound")
	_check(ReservesScript.validate(port) == "", "Normalized settings validate")


func _production_port() -> Dictionary:
	var port: Dictionary = _port(1000.0)
	var stocks: Dictionary = port["stocks"]
	for key: Variant in GoodsData.ITEMS.keys():
		stocks[str(key)] = 1000000.0
	var settings: Dictionary = port["reserves"]
	var recipes: Array[Dictionary] = []
	var observed: Dictionary = {}
	for good: String in ESSENTIALS:
		recipes.append({"good": good, "share": 1.0})
		observed[good] = 1000000.0
	settings["availableRecipes"] = recipes
	settings["observedDemand"] = observed
	return port


func _test_production() -> void:
	var port: Dictionary = _production_port()
	var before: Dictionary = port.duplicate(true)
	var floors: Dictionary = ReservesScript.allocation_floors(port, 100.0)
	_check(not floors.is_empty(), "Demand and feasible real recipes produce priority floors")
	_assert_feasible(port, floors, 100.0)
	_check(port == before, "Floor planning is read-only")

	var settings: Dictionary = port["reserves"]
	settings["availableRecipes"] = []
	_check(ReservesScript.allocation_floors(port, 100.0).is_empty(), "No recipe snapshot means no invented production")
	settings["availableRecipes"] = [{"good": "food", "share": 0.0}]
	_check(ReservesScript.allocation_floors(port, 100.0).is_empty(), "Zero-share recipe unavailable")
	_check(ReservesScript.allocation_floors(port, 0.0).is_empty(), "Zero paid pool")
	_check(ReservesScript.allocation_floors(port, -1.0).is_empty(), "Negative paid pool")
	_check(ReservesScript.allocation_floors(port, NAN).is_empty(), "Nonfinite paid pool")


func _test_scarce_inputs() -> void:
	var empty: Dictionary = _production_port()
	var stocks: Dictionary = empty["stocks"]
	var public_stores: Dictionary = empty["publicStores"]
	var settings: Dictionary = empty["reserves"]
	var incoming: Dictionary = {}
	for key: Variant in GoodsData.ITEMS.keys():
		var good: String = str(key)
		stocks[good] = 0.0
		public_stores[good] = 1000000000.0
		incoming[good] = 1000000000.0
	settings["incoming"] = incoming
	var floors: Dictionary = ReservesScript.allocation_floors(empty, 100.0)
	_assert_feasible(empty, floors, 100.0)

	var found_input_recipe: bool = false
	for good: String in ESSENTIALS:
		var definition: Dictionary = GoodsData.ITEMS[good]
		var inputs: Dictionary = definition.get("inputs", {})
		var labor: Dictionary = definition.get("labor", {})
		if inputs.is_empty() or float(GoodsData.labor_days(labor)) <= 0.0:
			continue
		found_input_recipe = true
		var scarce: Dictionary = _port(1000.0)
		var scarce_stocks: Dictionary = scarce["stocks"]
		for ingredient: Variant in inputs.keys():
			scarce_stocks[str(ingredient)] = 1.0
		var scarce_settings: Dictionary = scarce["reserves"]
		var observed: Dictionary = {}
		observed[good] = 1000000.0
		scarce_settings["observedDemand"] = observed
		scarce_settings["availableRecipes"] = [{"good": good, "share": 1.0}]
		var limited: Dictionary = ReservesScript.allocation_floors(scarce, 100.0)
		_check(not limited.is_empty(), "Finite opening ingredients permit bounded work")
		_assert_feasible(scarce, limited, 100.0)
		scarce_settings["contractedLots"] = scarce_stocks.duplicate(true)
		_check(ReservesScript.allocation_floors(scarce, 100.0).is_empty(), "Contracted ingredients cannot fund new production")
		break
	_check(found_input_recipe, "Real essential recipe with inputs available for scarcity check")


func _test_malformed_fields() -> void:
	var port: Dictionary = _port()
	port["workforce"] = NAN
	port["stocks"] = {"food": INF, "fuel": -3.0, "supplies": "bad"}
	port["publicStores"] = {"food": NAN}
	port["reserves"] = {
		"schema": "bad",
		"policy": "bad",
		"resupplyDays": NAN,
		"observedDemand": {"food": NAN, "fuel": INF, "supplies": -1.0},
		"incoming": {"food": INF},
		"contractedLots": {"food": INF},
		"availableRecipes": ["bad", {"good": "food", "share": NAN}],
	}
	_check(ReservesScript.validate(port) != "", "Malformed source diagnosed")
	ReservesScript.ensure(port)
	var snapshot: Dictionary = ReservesScript.report(port)
	_check(_all_finite(snapshot), "Malformed fields cannot leak nonfinite or negative report numbers")
	_check(_all_finite(ReservesScript.allocation_floors(port, 100.0)), "Malformed floor inputs remain finite")
	_near(ReservesScript.exportable(port, "food"), 0.0, "Nonfinite stock is not exportable")
	_near(float(snapshot["resupplyDays"]), 4.0, "Nonfinite horizon uses bounded default")
	_check(port["stocks"] == {"food": INF, "fuel": -3.0, "supplies": "bad"}, "Normalization does not repair inventory by creating goods")


# Independent invariants: recipe membership, total labor and aggregate input use.
func _assert_feasible(port: Dictionary, floors: Dictionary, paid_workers: float) -> void:
	var total: float = 0.0
	var used: Dictionary = {}
	var settings: Dictionary = port["reserves"]
	var records: Array = settings.get("availableRecipes", [])
	for key: Variant in floors.keys():
		var good: String = str(key)
		var workers: float = float(floors[key])
		var listed: bool = false
		for record_value: Variant in records:
			var record: Dictionary = record_value
			if str(record.get("good", "")) == good and float(record.get("share", 0.0)) > 0.0:
				listed = true
		_check(listed, "Floor uses an available positive-share recipe")
		_check(ESSENTIALS.has(good), "Floor is essential")
		_check(is_finite(workers) and workers >= 0.0, "Floor labor finite/nonnegative")
		total += workers
		var definition: Dictionary = GoodsData.ITEMS[good]
		var labor: Dictionary = definition.get("labor", {})
		var labor_days: float = float(GoodsData.labor_days(labor))
		_check(labor_days > 0.0, "Floor has real labor")
		if labor_days <= 0.0:
			continue
		var inputs: Dictionary = definition.get("inputs", {})
		for ingredient_key: Variant in inputs.keys():
			var ingredient: String = str(ingredient_key)
			used[ingredient] = float(used.get(ingredient, 0.0)) + (
				workers / labor_days * float(inputs[ingredient_key])
			)
	_check(total <= paid_workers * 0.25 + 0.00001, "Combined priority cap")
	var stocks: Dictionary = port["stocks"]
	var committed: Dictionary = settings.get("contractedLots", {})
	for ingredient: Variant in used.keys():
		var opening: float = maxf(
			0.0,
			float(stocks.get(ingredient, 0.0)) - float(committed.get(ingredient, 0.0))
		)
		_check(float(used[ingredient]) <= opening + 0.00001, "Aggregate opening-input budget")


func _row(port: Dictionary, good: String) -> Dictionary:
	var snapshot: Dictionary = ReservesScript.report(port)
	var rows: Dictionary = snapshot["goods"]
	var entry: Dictionary = rows.get(good, {})
	return entry


func _all_finite(value: Variant) -> bool:
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return is_finite(float(value)) and float(value) >= 0.0
	if value is Dictionary:
		var dictionary: Dictionary = value
		for key: Variant in dictionary.keys():
			if not _all_finite(dictionary[key]):
				return false
	if value is Array:
		var values: Array = value
		for item: Variant in values:
			if not _all_finite(item):
				return false
	return true


func _near(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) <= 0.00001 * maxf(1.0, absf(expected)), message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
