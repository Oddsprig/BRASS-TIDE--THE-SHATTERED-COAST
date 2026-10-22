extends RefCounted

const GoodsData = preload("res://scripts/goods.gd")
const EconomyData = preload("res://scripts/economy.gd")
const MoneyData = preload("res://scripts/money.gd")

const SCHEMA: int = 1
const EPS: float = 0.000001
const MAX_NUMBER: float = 1000000000000.0
const KINDS: Dictionary = {
	"machine_tools": {
		"name": "Machine tools", "weight": 4.0, "days": 2,
		"recoveryDays": 2, "cycles": 2, "bonus": 0.20,
		"labor": {"sailor": 2, "mechanic": 1, "foreman": 1}
	},
	"engine_fixture": {
		"name": "Engine fixture", "weight": 6.0, "days": 3,
		"recoveryDays": 3, "cycles": 3, "bonus": 0.20,
		"labor": {"sailor": 2, "mechanic": 1, "engineer": 1, "foreman": 1}
	},
	"hull_jig": {
		"name": "Hull jig", "weight": 8.0, "days": 3,
		"recoveryDays": 3, "cycles": 4, "bonus": 0.20,
		"labor": {"sailor": 2, "shipwright": 2, "foreman": 1}
	}
}


static func ensure(core: Object) -> void:
	var state: Dictionary = _state(core)
	# A malformed existing book must never be reset: that would renew sources.
	if not state.has("tooling"):
		state["tooling"] = {
			"schema": SCHEMA, "nextId": 1, "items": [], "extracted": {}
		}


static func list_items(core: Object) -> Array:
	ensure(core)
	var items: Variant = _book(core).get("items", [])
	return items.duplicate(true) if items is Array else []


# Root adds this ONCE to core.cargo_weight(), including transport capacity checks.
static func cargo_weight(core: Object) -> float:
	var total: float = 0.0
	for value: Variant in list_items(core):
		if not (value is Dictionary):
			continue
		var item: Dictionary = value
		var kind: String = str(item.get("kind", ""))
		if item.get("location", "") == "cargo" and KINDS.has(kind):
			total += float(KINDS[kind]["weight"])
	return total


static func recover(core: Object, site_id: String, kind: String) -> Dictionary:
	var problem: String = _ready(core)
	if not problem.is_empty():
		return _fail(core, problem)
	if not KINDS.has(kind):
		return _fail(core, "Unknown machinery kind.")
	if not core.has_method("tooling_recovery_offer"):
		return _fail(core, "Recovery provenance is not connected.")
	if not core.has_method("tooling_settle_recovery"):
		return _fail(core, "Paid recovery work is not connected.")

	var value: Variant = core.call("tooling_recovery_offer", site_id, kind)
	if not (value is Dictionary):
		return _fail(core, "Invalid recovery offer.")
	var offer: Dictionary = value
	if offer.get("ok", false) != true:
		return _fail(core, str(offer.get("message", "No recovery opportunity.")))
	if str(offer.get("siteId", "")) != site_id:
		return _fail(core, "Recovery site does not match.")
	if str(offer.get("kind", "")) != kind:
		return _fail(core, "The source does not contain this machinery.")
	if offer.get("near", false) != true:
		return _fail(core, "Move within recovery reach of the actual source.")

	var source_id: String = str(offer.get("sourceId", ""))
	var provenance: String = str(offer.get("provenance", ""))
	problem = _source_error(
		_state(core), _world(core), source_id, site_id, kind, provenance
	)
	if not problem.is_empty():
		return _fail(core, problem)

	var book: Dictionary = _book(core)
	var extracted: Dictionary = book["extracted"]
	if extracted.has(source_id):
		return _fail(core, "This machinery source has already been extracted.")
	var condition: Variant = offer.get("condition", null)
	if not _number(condition):
		return _fail(core, "Invalid machinery condition.")
	if float(condition) < 0.0 or float(condition) > 1.0:
		return _fail(core, "Invalid machinery condition.")

	var spec: Dictionary = KINDS[kind]
	if not _has_space(core, float(spec["weight"])):
		return _fail(core, "The fleet lacks machinery cargo or tow capacity.")
	var serial: int = int(book["nextId"])
	if float(serial) >= MAX_NUMBER:
		return _fail(core, "Machinery identifier limit reached.")

	var days: int = int(spec["recoveryDays"])
	var workers: int = 2
	var requirements: Dictionary = {
		"sourceId": source_id,
		"siteId": site_id,
		"kind": kind,
		"days": days,
		"workers": workers,
		"workerDays": workers * days,
		"supplies": float(days) * 0.5,
		"wages": workers * days * GoodsData.SAILOR_WAGE,
		"weight": float(spec["weight"])
	}
	# Root consumes one completed, actually elapsed and paid recovery receipt.
	# It must neither advance time nor replace state during this synchronous call.
	var settlement_value: Variant = core.call(
		"tooling_settle_recovery", requirements.duplicate(true)
	)
	if not (settlement_value is Dictionary):
		return _fail(core, "Invalid recovery work receipt.")
	var settlement: Dictionary = settlement_value
	if settlement.get("ok", false) != true:
		var result: Dictionary = _fail(
			core, str(settlement.get("message", "Recovery work is incomplete."))
		)
		result["work"] = requirements
		return result

	var item_id: String = "tool-%06d" % serial
	var item: Dictionary = {
		"id": item_id,
		"kind": kind,
		"sourceId": source_id,
		"sourceSite": site_id,
		"provenance": provenance,
		"condition": float(condition),
		"location": "cargo",
		"businessId": "",
		"portId": "",
		"recipeGood": "",
		"recipeLabor": "",
		"recoveredAt": _day(core),
		"readyAt": 0.0,
		"lastEconDay": _econ_day(core),
		"serviceDay": -1,
		"workers": 0,
		"specialists": 0,
		"recruits": 0,
		"setupCoins": 0
	}
	var items: Array = book["items"]
	items.append(item)
	extracted[source_id] = item_id
	book["nextId"] = serial + 1
	return _ok(core, "Recovered %s." % str(spec["name"]), {
		"item": item.duplicate(true), "work": requirements
	})


static func quote_install(
	core: Object, item_id: String, business_id: String
) -> Dictionary:
	var problem: String = _ready(core)
	if not problem.is_empty():
		return _fail(core, problem)
	var item: Dictionary = _item(core, item_id)
	if item.is_empty() or item.get("location", "") != "cargo":
		return _fail(core, "This machinery is not aboard the fleet.")
	var business: Dictionary = _business(_state(core), business_id)
	if business.is_empty():
		return _fail(core, "Choose an owned shore business.")

	var here_value: Variant = core.call("current_port")
	if not (here_value is Dictionary):
		return _fail(core, "Dock at the business home port.")
	var here: Dictionary = here_value
	var port_id: String = str(business.get("homePort", ""))
	if here.is_empty() or str(here.get("id", "")) != port_id:
		return _fail(core, "Dock at the business home port.")
	var port: Dictionary = _port(core, port_id)
	if port.is_empty():
		return _fail(core, "The business home port is unavailable.")

	if business.get("paused", true) != false:
		return _fail(core, "Resume the shore business before installation.")
	if not _number(business.get("dailyWages", null)):
		return _fail(core, "The business has no valid paid workforce.")
	if float(business["dailyWages"]) <= 0.0:
		return _fail(core, "The business needs a paid workforce.")
	for value: Variant in _book(core)["items"]:
		var other: Dictionary = value
		if other["location"] != "cargo" and other["businessId"] == business_id:
			return _fail(core, "This business already has machinery fitted.")

	var kind: String = str(item["kind"])
	var binding: Dictionary = _binding(core, business, kind)
	if binding.is_empty():
		return _fail(core, "No actual recipe bottleneck accepts this machinery.")
	if _role_count(business, str(binding["labor"])) <= 0:
		return _fail(core, "The named production job needs an assigned employee.")

	var spec: Dictionary = KINDS[kind]
	if _day(core) + float(spec["days"]) > MAX_NUMBER:
		return _fail(core, "Commissioning date is outside the supported range.")
	var staff: Dictionary = _staff(kind)
	if staff.is_empty() or not _workforce_ok(port):
		return _fail(core, "The port has no valid installation workforce.")
	var workforce: Dictionary = port
	var available: int = int(workforce["availableWorkers"])
	var specialists: int = int(workforce["availableSpecialists"])
	var needed: int = int(staff["workers"])
	var expert_need: int = int(staff["specialists"])
	if available < needed or specialists < expert_need:
		return _fail(core, "The port lacks free installation workers or experts.")
	if available - specialists < needed - expert_need:
		return _fail(core, "The port lacks free general installation workers.")

	if port.get("training") is Dictionary and int(port.workforce)-int(port.training.qualified.sailor)<needed:
		return _fail(core,"The available installation team is committed to qualified seafaring work.")
	var bill: Dictionary = _materials(str(binding["good"]), kind)
	var cost: Dictionary = _material_cost(port, bill)
	if cost.get("ok", false) != true:
		return _fail(core, str(cost.get("message", "Installation materials unavailable.")))
	var total: int = (
		int(cost["coins"]) + int(staff["householdCoins"]) + int(staff["expertCoins"])
	)
	if not _count(business.get("coins", null)):
		return _fail(core, "Invalid business purse.")
	if float(total) > MAX_NUMBER or int(business["coins"]) < total:
		return _fail(core, "The business cannot afford installation.")
	if float(item["setupCoins"]) + float(total) > MAX_NUMBER:
		return _fail(core, "Machinery setup record limit reached.")
	if not _purses_ok(port):
		return _fail(core, "Invalid home-port purses.")

	# Recruits are an eligibility subset, never an additional worker pool.
	var reserved_recruits: int = maxi(0,int(port["recruits"])-(int(port["workforce"])-needed))
	return _ok(core, "Installation quote.", {
		"itemId": item_id,
		"businessId": business_id,
		"portId": port_id,
		"kind": kind,
		"good": str(binding["good"]),
		"labor": str(binding["labor"]),
		"materials": bill,
		"materialCoins": int(cost["coins"]),
		"householdCoins": int(staff["householdCoins"]),
		"expertCoins": int(staff["expertCoins"]),
		"totalCoins": total,
		"commissioningDays": int(spec["days"]),
		"workers": needed,
		"specialists": expert_need,
		"reservedRecruits": reserved_recruits
	})


static func install(
	core: Object, item_id: String, business_id: String
) -> Dictionary:
	# Never accept a cached/client-supplied price or staff allocation.
	var quote: Dictionary = quote_install(core, item_id, business_id)
	if quote.get("ok", false) != true:
		return quote
	var item: Dictionary = _item(core, item_id)
	var business: Dictionary = _business(_state(core), business_id)
	var port: Dictionary = _port(core, str(quote["portId"]))
	if not _pay(
		core, business, port, int(quote["materialCoins"]),
		int(quote["householdCoins"]), int(quote["expertCoins"]),
		"Tooling installation"
	):
		return _fail(core, "Installation payment failed; nothing was fitted.")

	_use_materials(port, quote["materials"])
	var workforce: Dictionary = port
	workforce["availableWorkers"] = (
		int(workforce["availableWorkers"]) - int(quote["workers"])
	)
	workforce["availableSpecialists"] = (
		int(workforce["availableSpecialists"]) - int(quote["specialists"])
	)
	port["recruits"] = int(port["recruits"]) - int(quote["reservedRecruits"])
	port.workforce-=int(quote.workers)
	port.specialists=int(port.get("specialists",0))-int(quote.specialists)
	port.specialistWorkers=port.specialists
	EconomyData.sync_workforce(port)

	item["location"] = "commissioning"
	item["businessId"] = business_id
	item["portId"] = str(quote["portId"])
	item["recipeGood"] = str(quote["good"])
	item["recipeLabor"] = str(quote["labor"])
	item["readyAt"] = _day(core) + float(quote["commissioningDays"])
	item["lastEconDay"] = _econ_day(core)
	item["serviceDay"] = -1
	item["workers"] = int(quote["workers"])
	item["specialists"] = int(quote["specialists"])
	item["recruits"] = int(quote["reservedRecruits"])
	item["setupCoins"] = int(item["setupCoins"]) + int(quote["totalCoins"])
	return _ok(core, "Machinery commissioning started.", {
		"item": item.duplicate(true), "quote": quote
	})


static func remove(core: Object, item_id: String) -> Dictionary:
	var problem: String = _ready(core)
	if not problem.is_empty():
		return _fail(core, problem)
	var item: Dictionary = _item(core, item_id)
	if item.is_empty() or item["location"] == "cargo":
		return _fail(core, "This machinery is not fitted.")
	var here_value: Variant = core.call("current_port")
	if not (here_value is Dictionary):
		return _fail(core, "Dock at the machinery home port.")
	var here: Dictionary = here_value
	if str(here.get("id", "")) != str(item["portId"]):
		return _fail(core, "Dock at the machinery home port.")
	var kind: String = str(item["kind"])
	if not _has_space(core, float(KINDS[kind]["weight"])):
		return _fail(core, "The fleet lacks machinery cargo or tow capacity.")
	var port: Dictionary = _port(core, str(item["portId"]))
	if not _release(item, port):
		return _fail(core, "Reserved installation staff could not be returned.")

	item["location"] = "cargo"
	item["businessId"] = ""
	item["portId"] = ""
	item["recipeGood"] = ""
	item["recipeLabor"] = ""
	item["readyAt"] = 0.0
	item["lastEconDay"] = _econ_day(core)
	item["serviceDay"] = -1
	return _ok(core, "Machinery returned to fleet cargo; setup costs remain spent.", {
		"item": item.duplicate(true)
	})


static func daily(core: Object) -> void:
	if not _ready(core).is_empty():
		return
	for value: Variant in _book(core)["items"]:
		var item: Dictionary = value
		_tick(core, item)
		_service(core, item)


# Root may call this immediately after a business's successful wage payment,
# before that business's actual production. It is safe after daily() as well.
static func service(core: Object, business_id: String) -> void:
	if not _ready(core).is_empty():
		return
	for value: Variant in _book(core)["items"]:
		var item: Dictionary = value
		if item["businessId"] == business_id and item["location"] != "cargo":
			_tick(core, item)
			_service(core, item)


# Pure query: apply ONLY to the stored recipe's paid labor bottleneck.
static func production_factor(core: Object, business_id: String) -> float:
	if not _ready(core).is_empty():
		return 1.0
	var business: Dictionary = _business(_state(core), business_id)
	for value: Variant in _book(core)["items"]:
		var item: Dictionary = value
		if item["location"] != "active" or item["businessId"] != business_id:
			continue
		if int(item["serviceDay"]) != _econ_day(core):
			return 1.0
		if not _operating(core, business, item):
			return 1.0
		var bonus: float = float(KINDS[str(item["kind"])]["bonus"])
		return 1.0 + bonus * clampf(float(item["condition"]), 0.0, 1.0)
	return 1.0


static func validate(state: Dictionary, world: Dictionary) -> String:
	if not state.has("tooling"):
		return ""  # Legacy save; ensure() can add an empty book.
	if not (state["tooling"] is Dictionary):
		return "Machinery book must be a dictionary."
	if not _number(state.get("day", null)) or float(state["day"]) < 0.0:
		return "Machinery requires a finite campaign day."
	if not _count(state.get("econDay", null)):
		return "Machinery requires a valid economic day."
	var book: Dictionary = state["tooling"]
	if not _count(book.get("schema", null)) or int(book["schema"]) != SCHEMA:
		return "Unsupported machinery schema."
	if not _count(book.get("nextId", null)) or int(book["nextId"]) < 1:
		return "Invalid next machinery identifier."
	if not (book.get("items", null) is Array) or book.get("items",[]).size()>128:
		return "Machinery items must be an array."
	if not (book.get("extracted", null) is Dictionary):
		return "Machinery extraction book must be a dictionary."

	var ids: Dictionary = {}
	var sources: Dictionary = {}
	var fitted: Dictionary = {}
	var largest: int = 0
	var items: Array = book["items"]
	var extracted: Dictionary = book["extracted"]
	for value: Variant in items:
		if not (value is Dictionary):
			return "Machinery item must be a dictionary."
		var item: Dictionary = value
		for key: String in [
			"id", "kind", "sourceId", "sourceSite", "provenance",
			"location", "businessId", "portId", "recipeGood", "recipeLabor"
		]:
			if not (item.get(key, null) is String):
				return "Invalid machinery text field: %s." % key
		var item_id: String = item["id"]
		if not item_id.begins_with("tool-"):
			return "Invalid machinery identifier."
		var suffix: String = item_id.substr(5)
		if not suffix.is_valid_int():
			return "Invalid machinery identifier."
		var serial: int = int(suffix)
		if serial < 1 or item_id != "tool-%06d" % serial or ids.has(item_id):
			return "Duplicate or invalid machinery identifier."
		ids[item_id] = true
		largest = maxi(largest, serial)
		var kind: String = item["kind"]
		if not KINDS.has(kind):
			return "Unknown saved machinery kind."
		var source_id: String = item["sourceId"]
		if sources.has(source_id):
			return "Duplicate machinery source."
		sources[source_id] = true
		if extracted.get(source_id, "") != item_id:
			return "Machinery extraction link is missing."
		var source_problem: String = _source_error(
			state, world, source_id, item["sourceSite"], kind, item["provenance"]
		)
		if not source_problem.is_empty():
			return source_problem

		if not _number(item.get("condition", null)):
			return "Invalid saved machinery condition."
		if float(item["condition"]) < 0.0 or float(item["condition"]) > 1.0:
			return "Saved machinery condition is outside its range."
		for key: String in ["recoveredAt", "readyAt"]:
			if not _number(item.get(key, null)) or float(item[key]) < 0.0:
				return "Invalid machinery date."
		if float(item["recoveredAt"]) > float(state["day"]) + EPS:
			return "Machinery recovery is dated in the future."
		for key: String in [
			"lastEconDay", "workers", "specialists", "recruits", "setupCoins"
		]:
			if not _count(item.get(key, null)):
				return "Invalid machinery count: %s." % key
		if int(item["lastEconDay"]) > int(state["econDay"]):
			return "Machinery upkeep is dated in the future."
		if not _integer(item.get("serviceDay", null)):
			return "Invalid machinery service day."
		if int(item["serviceDay"]) < -1:
			return "Invalid machinery service day."
		if int(item["serviceDay"]) > int(state["econDay"]):
			return "Machinery service is dated in the future."

		var location: String = item["location"]
		if location in ["cargo","lost"]:
			if item["businessId"] != "" or item["portId"] != "":
				return "Cargo machinery cannot also be fitted."
			if item["recipeGood"] != "" or item["recipeLabor"] != "":
				return "Cargo machinery cannot retain a production binding."
			if float(item["readyAt"]) != 0.0 or int(item["serviceDay"]) != -1:
				return "Cargo machinery cannot be commissioning or serviced."
			if int(item["workers"]) + int(item["specialists"]) + int(item["recruits"]) != 0:
				return "Cargo machinery cannot retain installation staff."
			continue
		if location != "commissioning" and location != "active":
			return "Unknown machinery location."
		if item["businessId"] == "" or item["portId"] == "":
			return "Fitted machinery needs a business and port."
		if fitted.has(item["businessId"]):
			return "A business cannot fit duplicate machinery."
		fitted[item["businessId"]] = true
		var business: Dictionary = _business(state, item["businessId"])
		if business.is_empty() or str(business.get("homePort", "")) != item["portId"]:
			return "Fitted machinery has no matching owned business."
		if not _known_port(world, item["portId"]):
			return "Fitted machinery has an unknown home port."
		if not _recipe_valid(item["recipeGood"], item["recipeLabor"]):
			return "Fitted machinery has no actual recipe bottleneck."
		if float(item["readyAt"]) < float(item["recoveredAt"]):
			return "Invalid machinery commissioning date."
		if location == "commissioning":
			var staff: Dictionary = _staff(kind)
			if int(item["workers"]) != int(staff.get("workers", -1)):
				return "Installation worker reservation does not match."
			if int(item["specialists"]) != int(staff.get("specialists", -1)):
				return "Installation expert reservation does not match."
			if int(item["recruits"]) > int(item["workers"]):
				return "Installation recruit eligibility exceeds reserved workers."
			if int(item["serviceDay"]) != -1:
				return "Uncommissioned machinery cannot be serviced."
		else:
			if float(item["readyAt"]) > float(state["day"]) + EPS:
				return "Machinery became active before commissioning elapsed."
			if int(item["workers"]) + int(item["specialists"]) + int(item["recruits"]) != 0:
				return "Commissioned machinery cannot retain setup staff."
	if extracted.size() != items.size():
		return "Machinery extraction book is not one-to-one."
	if int(book["nextId"]) <= largest:
		return "Next machinery identifier would duplicate an existing item."
	return ""


static func _source_error(
	state: Dictionary, world: Dictionary, source_id: String,
	site_id: String, kind: String, provenance: String
) -> String:
	if provenance == "site":
		# The supplied catalog evidences exactly this abandoned machine workshop.
		if (
			site_id != "cinder_workshop_ruin"
			or source_id != "site:cinder_workshop_ruin"
			or kind != "machine_tools"
		):
			return "This surveyed site has no matching abandoned machinery."
		var exploration_value: Variant = state.get("exploration", {})
		if not (exploration_value is Dictionary):
			return "Machinery site has no survey record."
		var exploration: Dictionary = exploration_value
		var sites_value: Variant = exploration.get("sites", {})
		if not (sites_value is Dictionary):
			return "Machinery site has no survey record."
		var sites: Dictionary = sites_value
		var progress_value: Variant = sites.get(site_id, {})
		if not (progress_value is Dictionary):
			return "Machinery site has no survey record."
		var progress: Dictionary = progress_value
		if not _number(progress.get("level", null)):
			return "Fully survey the abandoned workshop first."
		if float(progress["level"]) < 3.0:
			return "Fully survey the abandoned workshop first."
		return ""
	if provenance == "wreck":
		if not source_id.begins_with("wreck:") or source_id.length() <= 6:
			return "Invalid finite wreck provenance."
		# Optional root-built index of REAL finite wreck payloads. Keep spent rows.
		var index_value: Variant = world.get("toolingWreckSources", {})
		if not (index_value is Dictionary):
			return "Finite wreck provenance is unavailable."
		var index: Dictionary = index_value
		var record_value: Variant = index.get(source_id, {})
		if not (record_value is Dictionary):
			return "Unknown finite wreck source."
		var record: Dictionary = record_value
		if (
			record.get("finite", false) != true
			or str(record.get("kind", "")) != kind
			or str(record.get("siteId", "")) != site_id
		):
			return "Unknown or mismatched finite wreck payload."
		return ""
	return "Unknown machinery provenance."


static func _binding(core: Object, business: Dictionary, kind: String) -> Dictionary:
	var binding: Dictionary = {}
	if core.has_method("tooling_recipe"):
		var value: Variant = core.call(
			"tooling_recipe", str(business.get("id", "")), kind
		)
		if value is Dictionary:
			binding = value
	if binding.is_empty():
		if kind == "machine_tools" and business.get("kind", "") == "workshop":
			binding = {
				"businessKind": "workshop", "good": "supplies", "labor": "carpenter"
			}
	if str(binding.get("businessKind", "")) != str(business.get("kind", "")):
		return {}
	var good: String = str(binding.get("good", ""))
	var labor: String = str(binding.get("labor", ""))
	if not _recipe_valid(good, labor):
		return {}
	return {"good": good, "labor": labor}


static func _recipe_valid(good: String, labor: String) -> bool:
	if not GoodsData.ITEMS.has(good):
		return false
	var recipe: Dictionary = GoodsData.ITEMS[good]
	var inputs_value: Variant = recipe.get("inputs", null)
	var labor_value: Variant = recipe.get("labor", null)
	if not (inputs_value is Dictionary) or not (labor_value is Dictionary):
		return false
	var inputs: Dictionary = inputs_value
	var jobs: Dictionary = labor_value
	if inputs.is_empty() or not _number(jobs.get(labor, null)):
		return false
	if float(jobs[labor]) <= 0.0:
		return false
	for key: Variant in inputs:
		var input_good: String = str(key)
		if not GoodsData.ITEMS.has(input_good):
			return false
		if not _number(inputs[key]) or float(inputs[key]) <= 0.0:
			return false
	return true


static func _operating(
	core: Object, business: Dictionary, item: Dictionary
) -> bool:
	if business.is_empty() or business.get("paused", true) != false:
		return false
	if not _count(business.get("coins", null)):
		return false
	if not _number(business.get("dailyWages", null)):
		return false
	if float(business["dailyWages"]) <= 0.0:
		return false
	# Root stamps this only AFTER the actual wage transfer succeeds.
	if not _count(business.get("toolingPaidDay", null)):
		return false
	if int(business["toolingPaidDay"]) != _econ_day(core):
		return false
	var binding: Dictionary = _binding(core, business, str(item["kind"]))
	if (
		binding.is_empty()
		or binding["good"] != item["recipeGood"]
		or binding["labor"] != item["recipeLabor"]
	):
		return false
	if _role_count(business, str(item["recipeLabor"])) <= 0:
		return false
	var inventory_value: Variant = business.get("inventory", null)
	if not (inventory_value is Dictionary):
		return false
	var inventory: Dictionary = inventory_value
	var recipe: Dictionary = GoodsData.ITEMS[str(item["recipeGood"])]
	var inputs: Dictionary = recipe["inputs"]
	for key: Variant in inputs:
		var quantity: Variant = inventory.get(key, 0.0)
		if not _number(quantity) or float(quantity) + EPS < float(inputs[key]):
			return false
	return true


static func _tick(core: Object, item: Dictionary) -> void:
	if item["location"] in ["cargo","lost"]:
		return
	if item["location"] == "commissioning":
		if _day(core) + EPS < float(item["readyAt"]):
			return
		var port: Dictionary = _port(core, str(item["portId"]))
		if not _release(item, port):
			return
		item["location"] = "active"
		item["condition"] = 1.0
		item["lastEconDay"] = _econ_day(core)
		item["serviceDay"] = -1
		return
	var elapsed: int = _econ_day(core) - int(item["lastEconDay"])
	if elapsed > 0:
		item["condition"] = maxf(
			0.0, float(item["condition"]) - 0.01 * float(elapsed)
		)
		item["lastEconDay"] = _econ_day(core)


static func _service(core: Object, item: Dictionary) -> void:
	if item["location"] != "active":
		return
	if int(item["serviceDay"]) == _econ_day(core):
		return
	var business: Dictionary = _business(_state(core), str(item["businessId"]))
	if not _operating(core, business, item):
		return
	var port: Dictionary = _port(core, str(item["portId"]))
	var bill: Dictionary = {"supplies": 0.1}
	var cost: Dictionary = _material_cost(port, bill)
	if cost.get("ok", false) != true:
		return
	# Routine service uses the business's already-paid production staff.
	if not _pay(
		core, business, port, int(cost["coins"]), 0, 0, "Tooling maintenance"
	):
		return
	_use_materials(port, bill)
	item["condition"] = minf(1.0, float(item["condition"]) + 0.02)
	item["serviceDay"] = _econ_day(core)


static func _materials(good: String, kind: String) -> Dictionary:
	var recipe: Dictionary = GoodsData.ITEMS[good]
	var inputs: Dictionary = recipe["inputs"]
	var spec: Dictionary = KINDS[kind]
	var bill: Dictionary = {}
	for key: Variant in inputs:
		bill[str(key)] = float(inputs[key]) * float(spec["cycles"])
	bill["supplies"] = (
		float(bill.get("supplies", 0.0)) + float(spec["days"])
	)
	return bill


static func _material_cost(port: Dictionary, bill: Dictionary) -> Dictionary:
	if port.is_empty() or not (port.get("stocks", null) is Dictionary):
		return {"ok": false, "message": "The port has no valid material stocks."}
	var stocks: Dictionary = port["stocks"]
	var coins: int = 0
	for key: Variant in bill:
		var good: String = str(key)
		if not GoodsData.ITEMS.has(good):
			return {"ok": false, "message": "Unknown installation material."}
		if not _number(bill[key]) or float(bill[key]) <= 0.0:
			return {"ok": false, "message": "Invalid installation material quantity."}
		var quantity: float = float(bill[key])
		var stock: Variant = stocks.get(good, 0.0)
		if not _number(stock) or float(stock) + EPS < quantity:
			return {"ok": false, "message": "The port lacks %s." % good}
		var unit: int = EconomyData.price(port, good)
		var raw: float = quantity * float(unit)
		if unit <= 0 or not _number(raw) or raw > MAX_NUMBER:
			return {"ok": false, "message": "Invalid material price."}
		coins += int(ceil(raw))
		if float(coins) > MAX_NUMBER:
			return {"ok": false, "message": "Material quote exceeds its supported range."}
	return {"ok": true, "coins": coins}


static func _staff(kind: String) -> Dictionary:
	var spec: Dictionary = KINDS[kind]
	var roles: Dictionary = spec["labor"]
	var workers: int = 0
	var specialists: int = 0
	var household: int = 0
	var experts: int = 0
	for key: Variant in roles:
		var role: String = str(key)
		var count: int = int(roles[key])
		var wage_rate: int=GoodsData.SAILOR_WAGE if role=="sailor" else int(GoodsData.WAGES.get(role,-1))
		if wage_rate<0:return {}
		var wages: int=count*int(spec["days"])*wage_rate
		workers+=count
		if wage_rate<150:
			household += wages
		else:
			specialists += count
			experts += wages
	if float(household) + float(experts) > MAX_NUMBER:
		return {}
	return {
		"workers": workers, "specialists": specialists,
		"householdCoins": household, "expertCoins": experts
	}


static func _workforce_ok(port: Dictionary) -> bool:
	for key in ["workforce","availableWorkers","availableSpecialists","recruits"]:
		if not _count(port.get(key)):return false
	return int(port.availableWorkers)<=int(port.workforce) and int(port.availableSpecialists)<=int(port.availableWorkers) and int(port.recruits)<=int(port.workforce)

static func _release(item: Dictionary, port: Dictionary) -> bool:
	if not _workforce_ok(port):
		return false
	var workforce: Dictionary = port
	var workers: int = int(workforce["availableWorkers"]) + int(item["workers"])
	var specialists: int = (
		int(workforce["availableSpecialists"]) + int(item["specialists"])
	)
	var recruits: int = int(port["recruits"]) + int(item["recruits"])
	if (
		float(workers) > MAX_NUMBER or specialists > workers
		or recruits > workers
	):
		return false
	port.workforce+=int(item.workers)
	port.specialists=int(port.get("specialists",0))+int(item.specialists)
	port.specialistWorkers=port.specialists
	workforce["availableWorkers"] = workers
	workforce["availableSpecialists"] = specialists
	port["recruits"] = recruits
	EconomyData.sync_workforce(port)
	item["workers"] = 0
	item["specialists"] = 0
	item["recruits"] = 0
	return true


static func _purses_ok(port: Dictionary) -> bool:
	for key: String in ["cash", "householdPurse", "expertPurse"]:
		if not _count(port.get(key, null)):
			return false
	return true


static func _pay(
	core: Object, business: Dictionary, port: Dictionary,
	materials: int, household: int, experts: int, reason: String
) -> bool:
	var total: int = materials + household + experts
	if materials < 0 or household < 0 or experts < 0:
		return false
	if not _count(business.get("coins", null)) or not _purses_ok(port):
		return false
	if float(total) > MAX_NUMBER or int(business["coins"]) < total:
		return false
	var ledger_value: Variant = _state(core).get("moneyLog", null)
	if not (ledger_value is Array):
		return false
	var ledger: Array = ledger_value
	var transfers: Array = [
		["cash", materials, "materials"],
		["householdPurse", household, "worker wages"],
		["expertPurse", experts, "expert wages"]
	]
	for value: Variant in transfers:
		var transfer: Array = value
		if float(port[str(transfer[0])]) + float(transfer[1]) > MAX_NUMBER:
			return false

	var old_coins: Variant = business["coins"]
	var old_purses: Dictionary = {
		"cash": port["cash"],
		"householdPurse": port["householdPurse"],
		"expertPurse": port["expertPurse"]
	}
	var old_log: Array = ledger.duplicate(true)
	for value: Variant in transfers:
		var transfer: Array = value
		var amount: int = int(transfer[1])
		if amount == 0:
			continue
		var moved: bool = MoneyData.move(
			business, "coins", port, str(transfer[0]), amount,
			"%s: %s" % [reason, str(transfer[2])], ledger
		)
		if moved:
			continue
		# Money.move touches the named purses and bounded log only.
		business["coins"] = old_coins
		for key: Variant in old_purses:
			port[key] = old_purses[key]
		ledger.clear()
		for entry: Variant in old_log:
			ledger.append(entry)
		return false
	business["otherExpenses"]=int(business.get("otherExpenses",0))+total
	return true


static func _use_materials(port: Dictionary, bill: Dictionary) -> void:
	var stocks: Dictionary = port["stocks"]
	for key: Variant in bill:
		stocks[key] = maxf(0.0, float(stocks[key]) - float(bill[key]))


static func _has_space(core: Object, extra: float) -> bool:
	if core.has_method("tooling_hold_room") and core.call("tooling_hold_room",extra)!=true:return false
	var capacity_value: Variant = core.call("capacity")
	var weight_value: Variant = core.call("cargo_weight")
	if not _number(capacity_value) or not _number(weight_value):
		return false
	var capacity: float = float(capacity_value)
	var weight: float = float(weight_value)
	return capacity >= 0.0 and weight >= 0.0 and weight + extra <= capacity + EPS


static func _role_count(business: Dictionary, role: String) -> int:
	var employees_value: Variant = business.get("employees", null)
	if not (employees_value is Array):
		return 0
	var count: int = 0
	var employees: Array = employees_value
	for value: Variant in employees:
		if value is Dictionary:
			var employee: Dictionary = value
			if str(employee.get("occupation", "")) == role:
				count += 1
	return count


static func _known_port(world: Dictionary, port_id: String) -> bool:
	var ports_value: Variant = world.get("PORTS",world.get("ports",null))
	if ports_value is Dictionary:
		var ports: Dictionary = ports_value
		return ports.has(port_id) and ports[port_id] is Dictionary
	if ports_value is Array:
		var ports: Array = ports_value
		for value: Variant in ports:
			if value is Dictionary:
				var port: Dictionary = value
				if str(port.get("id", "")) == port_id:
					return true
	return false


static func _business(state: Dictionary, business_id: String) -> Dictionary:
	var values: Variant = state.get("businesses", [])
	if not (values is Array):
		return {}
	var found: Dictionary = {}
	for value: Variant in values:
		if value is Dictionary:
			var business: Dictionary = value
			if str(business.get("id", "")) == business_id:
				if not found.is_empty():
					return {}
				found = business
	return found


static func _item(core: Object, item_id: String) -> Dictionary:
	var values: Variant = _book(core).get("items", [])
	if values is Array:
		for value: Variant in values:
			if value is Dictionary:
				var item: Dictionary = value
				if str(item.get("id", "")) == item_id:
					return item
	return {}


static func _port(core: Object, port_id: String) -> Dictionary:
	var value: Variant = core.call("port", port_id)
	return value if value is Dictionary else {}


static func _state(core: Object) -> Dictionary:
	var value: Variant = core.get("state")
	return value if value is Dictionary else {}


static func _book(core: Object) -> Dictionary:
	var value: Variant = _state(core).get("tooling", {})
	return value if value is Dictionary else {}


static func _world(core: Object) -> Dictionary:
	var value: Variant = core.get("data")
	return value if value is Dictionary else {}


static func _ready(core: Object) -> String:
	var value: Variant = core.get("state")
	if not (value is Dictionary):
		return "Campaign state is unavailable."
	ensure(core)
	return validate(_state(core), _world(core))


static func _number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and absf(number) <= MAX_NUMBER


static func _integer(value: Variant) -> bool:
	return _number(value) and floor(float(value)) == float(value)


static func _count(value: Variant) -> bool:
	return _integer(value) and float(value) >= 0.0


static func _day(core: Object) -> float:
	return float(_state(core)["day"])


static func _econ_day(core: Object) -> int:
	return int(_state(core)["econDay"])


static func _ok(
	core: Object, message: String, extra: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = core.call("ok", message)
	for key: Variant in extra:
		result[key] = extra[key]
	return result


static func _fail(core: Object, message: String) -> Dictionary:
	var result: Dictionary = core.call("fail", message)
	return result
