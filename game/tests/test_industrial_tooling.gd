extends SceneTree

const Tooling = preload("res://scripts/industrial_tooling.gd")
const GoodsData = preload("res://scripts/goods.gd")

var failures: Array[String] = []


class Fixture:
	extends RefCounted

	const T = preload("res://scripts/industrial_tooling.gd")
	const G = preload("res://scripts/goods.gd")
	const M = preload("res://scripts/money.gd")

	var state: Dictionary
	var data: Dictionary
	var position: Dictionary = {"x": 5800.0, "y": 2700.0}
	var p: Dictionary
	var business: Dictionary
	var moored: bool = false
	var capacity_limit: float = 1000000.0
	var receipt: Dictionary = {}
	var receipt_used: bool = false
	var settle_calls: int = 0
	var offer_override: Dictionary = {}

	func _init() -> void:
		var stocks: Dictionary = {}
		var prices: Dictionary = {}
		var inventory: Dictionary = {}
		var basis: Dictionary = {}
		for key: Variant in G.ITEMS:
			var good: String = str(key)
			stocks[good] = 1000.0
			prices[good] = 100
			inventory[good] = 0.0
			basis[good] = 0.0
		var recipe: Dictionary = G.ITEMS["supplies"]
		var inputs: Dictionary = recipe["inputs"]
		for key: Variant in inputs:
			inventory[key] = float(inputs[key]) * 100.0

		p = {
			"id": "test_port",
			"name": "Tooling Test Harbor",
			"x": 100.0, "y": 200.0,
			"population": 1000,
			"stocks": stocks,
			"publicStores": {},
			"prices": prices,
			"cash": 100000000,
			"householdPurse": 100000,
			"expertPurse": 100000,
			"governmentPurse": 100000,
			"workforce":20,"workers":8,"publicWorkers":0,
			"availableWorkers":12,"availableSpecialists":6,"specialists":6,"specialistWorkers":6,
			"recruits": 10
		}
		business = {
			"id": "test_workshop",
			"kind": "workshop",
			"homePort": "test_port",
			"coins": 100000000,
			"inventory": inventory,
			"inventoryBasis": basis,
			"capacity": 100000000.0,
			"paused": false,
			"employees": [{"occupation": "carpenter"}],
			"dailyWages": 100
		}
		var ledger: Array[Dictionary] = []
		state = {
			"day": 0.0,
			"econDay": 0,
			"moneyLog": ledger,
			"coins": 10000000,
			"cargo": {"supplies": 30.0},
			"businesses": [business],
			"exploration": {
				"sites": {
					"cinder_workshop_ruin": {"level": 3},
					"lantern_fresh_cove": {"level": 3}
				}
			}
		}
		data = {"ports": [p]}
		T.ensure(self)

	func current_port() -> Dictionary:
		return p if moored else {}

	func port(port_id: String) -> Dictionary:
		return p if port_id == "test_port" else {}

	func capacity() -> float:
		return capacity_limit

	func cargo_weight() -> float:
		var total: float = T.cargo_weight(self)
		var cargo: Dictionary = state["cargo"]
		for key: Variant in cargo:
			total += float(cargo[key]) * float(G.ITEMS[str(key)]["weight"])
		return total

	func distance(a: Dictionary, b: Dictionary) -> float:
		var dx: float = float(a["x"]) - float(b["x"])
		var dy: float = float(a["y"]) - float(b["y"])
		return sqrt(dx * dx + dy * dy)

	func ok(message: String) -> Dictionary:
		return {"ok": true, "message": message}

	func fail(message: String) -> Dictionary:
		return {"ok": false, "message": message}

	func log_entry(_message: String) -> void:
		pass

	func tooling_recovery_offer(site_id: String, kind: String) -> Dictionary:
		if not offer_override.is_empty():
			return offer_override.duplicate(true)
		if site_id != "cinder_workshop_ruin":
			return fail("No evidenced machinery at this site.")
		return {
			"ok": true,
			"sourceId": "site:cinder_workshop_ruin",
			"siteId": site_id,
			"kind": kind,
			"provenance": "site",
			"near": distance(position, {"x": 5800.0, "y": 2700.0}) <= 100.0,
			"condition": 0.6
		}

	# Fixture-only completed recovery job, using actual Money.move and supplies.
	func complete_recovery(days: int) -> bool:
		var wages: int = 2 * days * G.SAILOR_WAGE
		var supplies: float = float(days) * 0.5
		var cargo: Dictionary = state["cargo"]
		if float(cargo["supplies"]) < supplies or int(state["coins"]) < wages:
			return false
		var ledger: Array = state["moneyLog"]
		var moved: bool = M.move(
			state, "coins", p, "householdPurse", wages,
			"Completed recovery labor", ledger
		)
		if not moved:
			return false
		cargo["supplies"] = float(cargo["supplies"]) - supplies
		var start: float = float(state["day"])
		advance(float(days))
		receipt = {
			"sourceId": "site:cinder_workshop_ruin",
			"startAt": start,
			"endAt": float(state["day"]),
			"workerDays": days * 2,
			"supplies": supplies,
			"wages": wages
		}
		receipt_used = false
		return true

	func tooling_settle_recovery(work: Dictionary) -> Dictionary:
		settle_calls += 1
		if receipt.is_empty() or receipt_used:
			return fail("Complete the paid recovery job first.")
		if str(receipt["sourceId"]) != str(work["sourceId"]):
			return fail("Wrong recovery receipt.")
		if float(receipt["endAt"]) > float(state["day"]):
			return fail("Recovery time has not elapsed.")
		if float(receipt["endAt"]) - float(receipt["startAt"]) < float(work["days"]):
			return fail("Insufficient elapsed recovery work.")
		for key: String in ["workerDays", "supplies", "wages"]:
			if float(receipt[key]) < float(work[key]):
				return fail("Insufficient paid recovery resources.")
		receipt_used = true
		return ok("Recovery receipt consumed.")

	func advance(days: float) -> void:
		state["day"] = float(state["day"]) + days
		state["econDay"] = int(floor(float(state["day"])))

	func dock() -> void:
		position = {"x": float(p["x"]), "y": float(p["y"])}
		moored = true

	func pay_business() -> bool:
		var ledger: Array = state["moneyLog"]
		var moved: bool = M.move(
			business, "coins", p, "householdPurse", int(business["dailyWages"]),
			"Actual shore-business wages", ledger
		)
		if moved:
			business["toolingPaidDay"] = int(state["econDay"])
		return moved

	func total_money() -> float:
		return (
			float(state["coins"]) + float(business["coins"])
			+ float(p["cash"]) + float(p["householdPurse"])
			+ float(p["expertPurse"]) + float(p["governmentPurse"])
		)

	# The supplied producer's labor/input ceilings, used to check the named hook.
	func kit_capacity(carpenter_days: float, factor: float) -> int:
		var recipe: Dictionary = G.ITEMS["supplies"]
		var labor: Dictionary = recipe["labor"]
		var inputs: Dictionary = recipe["inputs"]
		var inventory: Dictionary = business["inventory"]
		var kits: int = int(floor(
			carpenter_days * factor / float(labor["carpenter"]) + 0.000001
		))
		for key: Variant in inputs:
			kits = mini(kits, int(floor(
				float(inventory.get(key, 0.0)) / float(inputs[key]) + 0.000001
			)))
		return kits


func _initialize() -> void:
	_test_recovery()
	_test_transport_install_commission()
	_test_cancel_and_capacity()
	_test_paid_maintenance()
	_test_malformed_saves()
	if failures.is_empty():
		print("PASS industrial_tooling")
		quit(0)
		return
	for message: String in failures:
		push_error(message)
	quit(1)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
	return condition


func _succeeded(result: Dictionary, message: String) -> bool:
	return _check(
		result.get("ok", false) == true,
		"%s: %s" % [message, str(result.get("message", ""))]
	)


func _recovered() -> Fixture:
	var f: Fixture = Fixture.new()
	var money: float = f.total_money()
	if not _check(f.complete_recovery(2), "Fixture must pay actual recovery labor"):
		return null
	if not _succeeded(
		Tooling.recover(f, "cinder_workshop_ruin", "machine_tools"), "Recovery"
	):
		return null
	_check(absf(f.total_money() - money) < 0.000001, "Recovery must conserve coins")
	return f


func _first(f: Fixture) -> Dictionary:
	var items: Array = f.state["tooling"]["items"]
	return items[0]


func _test_recovery() -> void:
	var f: Fixture = Fixture.new()
	var before: Dictionary = f.state.duplicate(true)
	var premature: Dictionary = Tooling.recover(
		f, "cinder_workshop_ruin", "machine_tools"
	)
	_check(premature.get("ok", true) == false, "Recovery needs completed work")
	_check(f.state == before, "Incomplete recovery must not mutate campaign state")

	f.state["exploration"]["sites"]["cinder_workshop_ruin"]["level"] = 2
	var calls: int = f.settle_calls
	var unsurveyed: Dictionary = Tooling.recover(
		f, "cinder_workshop_ruin", "machine_tools"
	)
	_check(unsurveyed.get("ok", true) == false, "Partial survey must not unlock machinery")
	_check(f.settle_calls == calls, "Survey rejection must precede work settlement")
	f.state["exploration"]["sites"]["cinder_workshop_ruin"]["level"] = 3

	f.offer_override = {
		"ok": true, "sourceId": "site:lantern_fresh_cove",
		"siteId": "lantern_fresh_cove", "kind": "machine_tools",
		"provenance": "site", "near": true, "condition": 1.0
	}
	var unrelated: Dictionary = Tooling.recover(
		f, "lantern_fresh_cove", "machine_tools"
	)
	_check(unrelated.get("ok", true) == false, "Unrelated surveyed sites must remain locked")
	f.offer_override = {
		"ok": true, "sourceId": "wreck:invented", "siteId": "shatter_wreck_field",
		"kind": "machine_tools", "provenance": "wreck",
		"near": true, "condition": 1.0
	}
	var invented: Dictionary = Tooling.recover(
		f, "shatter_wreck_field", "machine_tools"
	)
	_check(invented.get("ok", true) == false, "An unindexed wreck must not mint machinery")
	f.offer_override = {}

	if not _check(f.complete_recovery(2), "Recovery work fixture"):
		return
	f.capacity_limit = 0.0
	var full: Dictionary = Tooling.recover(
		f, "cinder_workshop_ruin", "machine_tools"
	)
	_check(full.get("ok", true) == false, "Recovery must respect physical capacity")
	_check(not f.receipt_used, "Capacity rejection must not consume completed work")
	f.capacity_limit = 1000000.0
	if not _succeeded(
		Tooling.recover(f, "cinder_workshop_ruin", "machine_tools"), "Claim recovery"
	):
		return
	_check(f.receipt_used, "A successful recovery must consume its paid work receipt")
	calls = f.settle_calls
	var duplicate: Dictionary = Tooling.recover(
		f, "cinder_workshop_ruin", "machine_tools"
	)
	_check(duplicate.get("ok", true) == false, "Source extraction is once only")
	_check(f.settle_calls == calls, "Duplicate extraction must not consume more work")
	_check(Tooling.list_items(f).size() == 1, "Recovery must create exactly one item")

	var detached: Array = Tooling.list_items(f)
	detached[0]["condition"] = 0.0
	_check(float(_first(f)["condition"]) == 0.6, "Item listing must return detached data")
	_check(Tooling.validate(f.state, f.data).is_empty(), "Recovered state must validate")


func _test_transport_install_commission() -> void:
	var f: Fixture = _recovered()
	if f == null:
		return
	var item_id: String = str(_first(f)["id"])
	var aboard_weight: float = f.cargo_weight()
	var weight: float = Tooling.cargo_weight(f)
	_check(absf(weight - 4.0) < 0.000001, "Machinery must occupy cargo space")
	var remote: Dictionary = Tooling.quote_install(f, item_id, "test_workshop")
	_check(remote.get("ok", true) == false, "Installation requires transport to home port")
	f.dock()
	_check(absf(f.cargo_weight() - aboard_weight) < 0.000001, "Transport must preserve cargo mass")

	f.state["day"] = 2.75
	f.state["econDay"] = 2
	var workers_before: Dictionary = _pool(f.p)
	var recruits_before: int = int(f.p["recruits"])
	var employees_before: Array = f.business["employees"].duplicate(true)
	var money: float = f.total_money()
	var business_coins: int = int(f.business["coins"])
	var stocks_before: Dictionary = f.p["stocks"].duplicate(true)
	var household_before: int = int(f.p["householdPurse"])
	var expert_before: int = int(f.p["expertPurse"])
	var quote: Dictionary = Tooling.quote_install(f, item_id, "test_workshop")
	if not _succeeded(quote, "Installation quote"):
		return
	_check(f.total_money() == money, "Quoting must not move coins")
	_check(f.p["stocks"] == stocks_before, "Quoting must not consume materials")

	var installed: Dictionary = Tooling.install(f, item_id, "test_workshop")
	if not _succeeded(installed, "Installation"):
		return
	_check(_first(f)["location"] == "commissioning", "Setup must await commissioning")
	_check(Tooling.cargo_weight(f) == 0.0, "Fitted machinery cannot remain in cargo")
	_check(absf(f.cargo_weight() - (aboard_weight - weight)) < 0.000001, "Remove fitted mass once")
	_check(int(f.business["coins"]) == business_coins - int(quote["totalCoins"]), "Business pays full setup")
	_check(int(f.p["householdPurse"]) == household_before + int(quote["householdCoins"]), "Workers receive wages")
	_check(int(f.p["expertPurse"]) == expert_before + int(quote["expertCoins"]), "Experts receive wages")
	var bill: Dictionary = quote["materials"]
	for key: Variant in bill:
		_check(
			absf(float(stocks_before[key]) - float(f.p["stocks"][key]) - float(bill[key])) < 0.000001,
			"Setup must consume the purchased material: %s" % str(key)
		)
	_check(absf(f.total_money() - money) < 0.000001, "Installation conserves coins")
	_check(f.business["employees"] == employees_before, "Machinery must not create employees")
	_check(
		int(f.p["availableWorkers"]) + int(_first(f)["workers"])
		== int(workers_before["availableWorkers"]),
		"Setup must reserve existing workers"
	)
	_check(
		int(f.p["availableSpecialists"]) + int(_first(f)["specialists"])
		== int(workers_before["availableSpecialists"]),
		"Experts are a reserved subset"
	)
	_check(
		int(f.p["recruits"]) + int(_first(f)["recruits"]) == recruits_before,
		"Recruit eligibility must be conserved"
	)
	_check(Tooling.production_factor(f, "test_workshop") == 1.0, "Uncommissioned machinery gives no benefit")

	var second_install: Dictionary = Tooling.install(f, item_id, "test_workshop")
	_check(second_install.get("ok", true) == false, "Installation cannot be duplicated")

	f.advance(1.3)  # Published day 4, but only 1.3 actual days after installation.
	_check(f.pay_business(), "Pay actual operating wages")
	Tooling.daily(f)
	_check(_first(f)["location"] == "commissioning", "Published day changes cannot shorten setup")
	f.advance(0.75)
	Tooling.service(f, "test_workshop")
	_check(_first(f)["location"] == "active", "Elapsed commissioning must activate machinery")
	_check(_pool(f.p) == workers_before, "Commissioning returns setup workers exactly")
	_check(int(f.p["recruits"]) == recruits_before, "Commissioning returns eligibility exactly")

	var factor: float = Tooling.production_factor(f, "test_workshop")
	_check(factor > 1.0 and factor <= 1.2 + 0.000001, "Benefit must be bounded")
	var recipe: Dictionary = GoodsData.ITEMS["supplies"]
	var labor: Dictionary = recipe["labor"]
	var carpenter_days: float = float(labor["carpenter"]) * 10.0
	_check(
		f.kit_capacity(carpenter_days, factor) > f.kit_capacity(carpenter_days, 1.0),
		"Machinery must improve the named carpenter bottleneck"
	)
	var inputs: Dictionary = recipe["inputs"]
	var input_good: String = str(inputs.keys()[0])
	var original_input: float = float(f.business["inventory"][input_good])
	f.business["inventory"][input_good] = 0.0
	_check(Tooling.production_factor(f, "test_workshop") == 1.0, "Machinery cannot bypass real inputs")
	_check(f.kit_capacity(carpenter_days, factor) == 0, "Original input ceiling remains binding")
	f.business["inventory"][input_good] = original_input
	_check(Tooling.production_factor(f, "another_business") == 1.0, "Benefit must not be global")
	_check(Tooling.validate(f.state, f.data).is_empty(), "Commissioned state must validate")


func _test_cancel_and_capacity() -> void:
	var f: Fixture = _recovered()
	if f == null:
		return
	f.dock()
	var item_id: String = str(_first(f)["id"])
	var workforce: Dictionary = _pool(f.p)
	var recruits: int = int(f.p["recruits"])
	var condition: float = float(_first(f)["condition"])
	if not _succeeded(Tooling.install(f, item_id, "test_workshop"), "Cancellation setup"):
		return
	var money_after_setup: float = f.total_money()
	var coins_after_setup: int = int(f.business["coins"])
	var stocks_after_setup: Dictionary = f.p["stocks"].duplicate(true)
	var reserved: Dictionary = _pool(f.p)

	f.capacity_limit = 0.0
	var blocked: Dictionary = Tooling.remove(f, item_id)
	_check(blocked.get("ok", true) == false, "Cancellation must require transport capacity")
	_check(_pool(f.p) == reserved, "Failed cancellation cannot return workers")
	_check(_first(f)["location"] == "commissioning", "Failed cancellation must retain machinery")

	f.capacity_limit = 1000000.0
	if not _succeeded(Tooling.remove(f, item_id), "Cancel installation"):
		return
	_check(_first(f)["location"] == "cargo", "Cancellation returns the same physical item")
	_check(str(_first(f)["id"]) == item_id, "Cancellation preserves stable item ID")
	_check(float(_first(f)["condition"]) == condition, "Cancelled commissioning cannot restore condition")
	_check(_pool(f.p) == workforce, "Cancellation returns staff exactly once")
	_check(int(f.p["recruits"]) == recruits, "Cancellation returns eligibility")
	_check(int(f.business["coins"]) == coins_after_setup, "Cancellation cannot refund setup wages")
	_check(f.p["stocks"] == stocks_after_setup, "Cancellation cannot refund consumed materials")
	_check(absf(f.total_money() - money_after_setup) < 0.000001, "Cancellation conserves coins")

	var snapshot: Dictionary = f.state.duplicate(true)
	var repeated: Dictionary = Tooling.remove(f, item_id)
	_check(repeated.get("ok", true) == false, "Cargo machinery cannot be cancelled twice")
	_check(f.state == snapshot, "Repeated cancellation cannot create staff or refunds")
	_check(Tooling.validate(f.state, f.data).is_empty(), "Cancelled state must validate")


func _test_paid_maintenance() -> void:
	var f: Fixture = _recovered()
	if f == null:
		return
	f.dock()
	var item_id: String = str(_first(f)["id"])
	if not _succeeded(Tooling.install(f, item_id, "test_workshop"), "Maintenance setup"):
		return
	f.advance(3.0)
	Tooling.daily(f)
	_check(_first(f)["location"] == "active", "Setup must finish after elapsed time")
	_check(Tooling.production_factor(f, "test_workshop") == 1.0, "Unpaid business gets no bonus")
	var before_unpaid: int = int(f.business["coins"])
	Tooling.service(f, "test_workshop")
	_check(int(f.business["coins"]) == before_unpaid, "Unpaid staff cannot perform charged service")

	_check(f.pay_business(), "Pay maintenance-day business wages")
	var supplies_before: float = float(f.p["stocks"]["supplies"])
	var money: float = f.total_money()
	Tooling.service(f, "test_workshop")
	_check(Tooling.production_factor(f, "test_workshop") > 1.0, "Paid maintained business gets benefit")
	_check(
		absf(supplies_before - float(f.p["stocks"]["supplies"]) - 0.1) < 0.000001,
		"Maintenance consumes actual supplies"
	)
	_check(absf(f.total_money() - money) < 0.000001, "Maintenance conserves coins")
	var snapshot: Dictionary = f.state.duplicate(true)
	var port_snapshot: Dictionary = f.p.duplicate(true)
	Tooling.service(f, "test_workshop")
	Tooling.daily(f)
	_check(f.state == snapshot and f.p == port_snapshot, "Repeated daily calls cannot double-charge")

	f.business["paused"] = true
	_check(Tooling.production_factor(f, "test_workshop") == 1.0, "Paused production gets no benefit")
	f.business["paused"] = false
	f.advance(1.0)
	_check(Tooling.production_factor(f, "test_workshop") == 1.0, "Yesterday's wage stamp is insufficient")
	_check(f.pay_business(), "Pay next-day wages")
	f.p["stocks"]["supplies"] = 0.0
	var coins_before: int = int(f.business["coins"])
	var condition_before: float = float(_first(f)["condition"])
	Tooling.service(f, "test_workshop")
	_check(int(f.business["coins"]) == coins_before, "Unavailable upkeep cannot charge coins")
	_check(float(_first(f)["condition"]) < condition_before, "Unmaintained machinery loses condition")
	_check(Tooling.production_factor(f, "test_workshop") == 1.0, "Missing upkeep disables the bonus")

	var coins_before_remove: int = int(f.business["coins"])
	if not _succeeded(Tooling.remove(f, item_id), "Remove active machinery"):
		return
	_check(int(f.business["coins"]) == coins_before_remove, "Active removal cannot refund setup")
	_check(Tooling.cargo_weight(f) == 4.0, "Active removal restores cargo mass")
	_check(Tooling.production_factor(f, "test_workshop") == 1.0, "Removed machinery gives no benefit")
	_check(Tooling.validate(f.state, f.data).is_empty(), "Removed state must validate")


func _test_malformed_saves() -> void:
	var f: Fixture = _recovered()
	if f == null:
		return
	var malformed: Dictionary = f.state.duplicate(true)
	malformed["tooling"] = []
	_check(not Tooling.validate(malformed, f.data).is_empty(), "Reject non-dictionary book")

	malformed = f.state.duplicate(true)
	malformed["tooling"]["items"][0]["condition"] = -0.1
	_check(not Tooling.validate(malformed, f.data).is_empty(), "Reject negative condition")
	malformed = f.state.duplicate(true)
	malformed["tooling"]["items"][0]["condition"] = NAN
	_check(not Tooling.validate(malformed, f.data).is_empty(), "Reject non-finite condition")
	malformed = f.state.duplicate(true)
	malformed["tooling"]["nextId"] = 1
	_check(not Tooling.validate(malformed, f.data).is_empty(), "Reject duplicate future IDs")
	malformed = f.state.duplicate(true)
	var duplicate: Dictionary = malformed["tooling"]["items"][0].duplicate(true)
	malformed["tooling"]["items"].append(duplicate)
	_check(not Tooling.validate(malformed, f.data).is_empty(), "Reject duplicate physical items")
	malformed = f.state.duplicate(true)
	malformed["tooling"]["items"][0]["businessId"] = "test_workshop"
	_check(not Tooling.validate(malformed, f.data).is_empty(), "Reject cargo also attached to business")
	malformed = f.state.duplicate(true)
	malformed["tooling"]["items"][0]["workers"] = 0.5
	_check(not Tooling.validate(malformed, f.data).is_empty(), "Reject fractional worker reservations")
	malformed = f.state.duplicate(true)
	malformed["tooling"]["extracted"].clear()
	_check(not Tooling.validate(malformed, f.data).is_empty(), "Reject lost extraction provenance")

	var legacy: Dictionary = f.state.duplicate(true)
	legacy.erase("tooling")
	_check(Tooling.validate(legacy, f.data).is_empty(), "Legacy saves remain migratable")

	f.state["tooling"] = {"schema": 999, "extracted": {"spent": "retained"}}
	var old_book: Dictionary = f.state["tooling"].duplicate(true)
	Tooling.ensure(f)
	_check(f.state["tooling"] == old_book, "ensure must not reset malformed source history")

func _pool(p: Dictionary) -> Dictionary:
	return {"workforce":p.workforce,"availableWorkers":p.availableWorkers,"availableSpecialists":p.availableSpecialists,"specialists":p.specialists}
