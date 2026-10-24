extends SceneTree
## Unrun native fixture for paid physical fitting. Sol runs this unchanged.
## Pose and dictionary inputs are observer inputs. This file does not claim a pass.
const Campaign = preload("res://scripts/campaign.gd")
const Refit = preload("res://scripts/refit.gd")
const Workshop = preload("res://scripts/fleet_workshop.gd")
const Condition = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Money = preload("res://scripts/money.gd")
const Construction = preload("res://scripts/construction.gd")

var core
var ship: Dictionary
var port: Dictionary
var checks: int = 0
var failures: int = 0
var fresh_engine_uid: String = ""
var old_engine_uid: String = ""
var first_rapid_uid: String = ""
var second_rapid_uid: String = ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL fitting: " + message)

func stores_of(boat: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["hp", "maxHp", "water", "ammo", "fuel", "supplies", "crew", "wounded", "breaches", "fire", "sunk"]:
		if not boat.has(key):
			continue
		var value = boat[key]
		result[key] = value.duplicate(true) if (value is Array or value is Dictionary) else value
	return result

func item_at(boat: Dictionary, location: String) -> Dictionary:
	for key in boat.moduleCondition.items.keys():
		var item: Dictionary = boat.moduleCondition.items[key]
		if str(item.location) == location:
			return item
	return {}

func locker_count(boat: Dictionary) -> int:
	var count: int = 0
	for key in boat.moduleCondition.items.keys():
		if str(boat.moduleCondition.items[key].location) == "locker":
			count += 1
	return count

func serial_of(boat: Dictionary) -> int:
	return int(boat.moduleCondition.nextItemSeq)

func purses_match(before: Dictionary, quote: Dictionary) -> bool:
	return int(port.cash) == int(before.cash) + int(quote.businessIncome) and int(port.householdPurse) == int(before.householdPurse) + int(quote.workerWages) and int(port.expertPurse) == int(before.expertPurse) + int(quote.expertWages) and int(port.governmentPurse) == int(before.governmentPurse) + int(quote.tax)

func materials_match(before_stocks: Dictionary, quote: Dictionary) -> bool:
	for good in quote.materials:
		if not is_equal_approx(float(port.stocks[good]), float(before_stocks[good]) - float(quote.materials[good])):
			return false
	return true

func stocks_exact(before_stocks: Dictionary, quote: Dictionary, stock_ref) -> bool:
	if not is_same(port.stocks, stock_ref) or port.stocks.size() != before_stocks.size():
		return false
	for good in before_stocks.keys():
		var used: float = float(quote.materials.get(good, 0.0))
		if not is_equal_approx(float(port.stocks[good]), float(before_stocks[good]) - used):
			return false
	for good in quote.materials.keys():
		if not before_stocks.has(good):
			return false
	return true

func freeze() -> Dictionary:
	return {"state": core.state.duplicate(true), "stock": port.stocks, "ship": ship, "port": port, "ammo": ship.get("ammo")}

func still(frozen: Dictionary, label: String) -> void:
	check(core.state == frozen.state and is_same(port.stocks, frozen.stock) and is_same(ship, frozen.ship) and is_same(port, frozen.port) and ship.get("ammo") == frozen.ammo, label)

func _flag_rows() -> Array:
	return [{"paid": true}, {"confirmPaid": true}, {"new": 1}, {"new": 0}, {"new": "true"}, {"new": 1.0}, {"initialize": 1}, {"initialize": 0}, {"initialize": "yes"}, {"new": [true]}, {"initialize": [false]}, {"itemUid": 12}, {"itemUid": ""}, {"itemUid": "bad id"}, {"note": "x"}]

func _socket_rows() -> Array:
	return [{"slots": {"weapon:99": {"new": true}}}, {"slots": {"weapon:-1": {"new": true}}}, {"slots": {"weapon:01": {"new": true}}}, {"slots": {"weapon:foo": {"new": true}}}, {"slots": {"weapon:0extra": {"new": true}}}, {"slots": {"Weapon:0": {"new": true}}}, {"slots": {"mount0": {"new": true}}}, {"slots": {"weapon:": {"new": true}}}, {"slots": {"weapon:+1": {"new": true}}}]

func _container_rows() -> Array:
	return [{"slots": ["engine"]}, {"slots": {"engine": {"new": 1}}}, {"slots": {"engine": {"paid": true}}}, {"slots": {1: {"new": true}}}]

func legacy_scalar_case() -> void:
	var ghost: Dictionary = ship.duplicate(true)
	var ghost_port: Dictionary = port.duplicate(true)
	var ghost_state: Dictionary = {"coins": 1000000, "fleet": [ghost], "moneyLog": []}
	ghost.engine = 0.65
	Construction.begin_day(ghost_port)
	var legacy: Dictionary = Refit.install(ghost_state, ghost_port, ghost, "engine", "boost_drive")
	check(legacy.ok, "legacy count install of boost_drive still completes")
	check(is_equal_approx(float(ghost.engine), 0.65), "legacy install keeps the 0.65 scalar; it does not publish a new engine at hp 1")
	check(not ghost.has("moduleCondition"), "legacy install does not open a physical record")
	check(int(ghost.refitLocker.get("stock_engine", 0)) == 1, "legacy removal still stores one count, not a physical item")
	check(not ship.has("moduleCondition") and is_equal_approx(float(ship.engine), 1.0), "the detached legacy case does not touch the career boat")
	print("NOTE fitting: legacy boost_drive keeps the detached 0.65 scalar and does not open a physical record. Paid same-type replacement is a separate case and may publish engine hp 1.")

func detached_migration() -> void:
	var born: Dictionary = ship.duplicate(true)
	var born_port: Dictionary = port.duplicate(true)
	var born_state: Dictionary = {"coins": 1000000, "fleet": [born], "moneyLog": []}
	born.engine = 0.40
	Construction.begin_day(born_port)
	var request: Dictionary = {"initialize": true, "new": true}
	var request_before: Dictionary = request.duplicate(true)
	var migrated: Dictionary = Refit.install(born_state, born_port, born, "engine", "economy_drive", request)
	check(migrated.ok and born.has("moduleCondition"), "paid install can open a physical record from the caller uid")
	check(is_equal_approx(float(born.engine), 1.0), "the funded replacement engine publishes hp 1")
	check(str(born.moduleCondition.birthNamespace) == str(born.uid), "birth identity is the boat uid, not the hull type")
	var absorbed_old: bool = false
	for key in born.moduleCondition.items.keys():
		var item: Dictionary = born.moduleCondition.items[key]
		if str(item.location) == "locker" and str(item.typeId) == "stock_engine":
			absorbed_old = is_equal_approx(float(item.hp), 0.40)
	check(absorbed_old, "the removed engine keeps the absorbed 0.40 condition")
	check(request == request_before, "the initialize request dictionary is not rewritten")
	check(not ship.has("moduleCondition"), "detached migration does not write the career boat")

func open_career_record() -> void:
	ship.engine = 0.65
	var seeded: Dictionary = Records.initialize(ship, {"base": ship.baseSpec, "loadout": ship.loadout, "catalog": Refit.catalog(), "identity": str(ship.uid), "knownUids": []})
	check(seeded.ok, "caller initialize accepts the stable boat uid")
	var engine: Dictionary = item_at(ship, "engine")
	old_engine_uid = str(engine.itemUid)
	check(is_equal_approx(float(engine.hp), 0.65) and str(engine.status) == "damaged", "birth engine hp is the legacy scalar")
	check(is_equal_approx(float(ship.engine), 0.65), "publish writes that raw hp and does not heal it")
	var saved_condition: Dictionary = ship.moduleCondition.duplicate(true)
	var saved_engine: float = float(ship.engine)
	var saved_serial: int = serial_of(ship)
	Refit.ensure(ship)
	check(ship.moduleCondition == saved_condition and is_equal_approx(float(ship.engine), saved_engine) and serial_of(ship) == saved_serial, "ensure after initialize does not reseed, heal, or change serial")
	var same: Dictionary = Refit.quote(port, ship, "engine", "stock_engine")
	check(not same.ok and ship.moduleCondition == saved_condition, "omitted same-type request stays already installed")

func gun_cycle() -> void:
	var gun: Dictionary = item_at(ship, "mount0")
	var gun_uid: String = str(gun.itemUid)
	var hurt: Dictionary = Condition.apply_component_damage(ship.moduleCondition, {"itemUid": gun_uid, "loss": 0.75, "cause": "Test impact"})
	check(hurt.ok and is_equal_approx(float(ship.moduleCondition.items[gun_uid].hp), 0.25) and str(ship.moduleCondition.items[gun_uid].status) == "damaged", "installed gun accepts a real 0.25 condition")
	var kept: Dictionary = stores_of(ship)
	Construction.begin_day(port)
	var before_coins: int = int(core.state.coins)
	var before_total: int = Money.total(core.state)
	var before_port: Dictionary = port.duplicate(true)
	var before_serial: int = serial_of(ship)
	var ship_ref: Dictionary = ship
	var port_ref: Dictionary = port
	var removed: Dictionary = Refit.install(core.state, port, ship, "weapon:0", "")
	check(removed.ok and removed.materials.is_empty(), "weapon removal bills labor only")
	check(is_same(ship, ship_ref) and is_same(port, port_ref), "refit keeps the live boat and port objects")
	check(Money.total(core.state) == before_total and int(core.state.coins) == before_coins - int(removed.cost), "removal conserves the coin ledger")
	check(purses_match(before_port, removed), "removal pays the real purses")
	check(stores_of(ship) == kept, "removal does not touch hull stores or wounds")
	check(serial_of(ship) == before_serial, "removal does not mint a part")
	var stored: Dictionary = ship.moduleCondition.items[gun_uid]
	check(str(stored.location) == "locker" and str(stored.typeId) == "stock_primary" and str(stored.originHullType) == "tin_skiff" and is_equal_approx(float(stored.hp), 0.25) and str(stored.cause) == "Test impact", "removed gun keeps uid, origin, hp, and cause")
	Construction.begin_day(port)
	var quoted: Dictionary = Refit.quote(port, ship, "weapon:0", "stock_primary")
	check(quoted.ok and quoted.fromLocker and str(quoted.selection.itemUid) == gun_uid and is_equal_approx(float(quoted.selection.hp), 0.25) and quoted.materials.is_empty(), "default spare is the removed gun and the quote records it")
	var serial_at_quote: int = serial_of(ship)
	var reinstalled: Dictionary = Refit.install(core.state, port, ship, "weapon:0", "stock_primary")
	check(reinstalled.ok and str(item_at(ship, "mount0").itemUid) == gun_uid and is_equal_approx(float(item_at(ship, "mount0").hp), 0.25) and str(item_at(ship, "mount0").cause) == "Test impact", "reinstall returns the same damaged gun")
	check(serial_of(ship) == serial_at_quote, "reinstalling an owned gun does not advance the serial")

func paid_engine_replacement() -> void:
	ship.engine = 0.10
	var before_items: Dictionary = ship.moduleCondition.duplicate(true)
	Refit.ensure(ship)
	check(is_equal_approx(float(ship.moduleCondition.items[old_engine_uid].hp), 0.65) and is_equal_approx(float(ship.engine), 0.10), "ensure leaves a lower scalar pending and does not heal the part")
	check(ship.moduleCondition.items[old_engine_uid].status == before_items.items[old_engine_uid].status, "ensure does not rewrite the engine item")
	Construction.begin_day(port)
	var before_serial: int = serial_of(ship)
	var before_coins: int = int(core.state.coins)
	var before_total: int = Money.total(core.state)
	var before_port: Dictionary = port.duplicate(true)
	var before_stocks: Dictionary = port.stocks.duplicate(true)
	var kept: Dictionary = stores_of(ship)
	var request: Dictionary = {"new": true}
	var request_before: Dictionary = request.duplicate(true)
	var quoted: Dictionary = Refit.quote(port, ship, "engine", "stock_engine", request)
	check(quoted.ok and quoted.selection.newUnit == true and not quoted.fromLocker, "explicit new funds a same-type engine instead of reusing the damaged one")
	check(str(quoted.selection.previewUid) == Condition.mint_uid(str(ship.moduleCondition.birthNamespace), before_serial), "preview uid is the next serial and is not minted yet")
	check(serial_of(ship) == before_serial and ship.moduleCondition.items[old_engine_uid].hp == before_items.items[old_engine_uid].hp, "the quote does not absorb or advance the live record")
	var bought: Dictionary = Refit.install(core.state, port, ship, "engine", "stock_engine", request)
	fresh_engine_uid = str(item_at(ship, "engine").itemUid)
	check(bought.ok and fresh_engine_uid == str(quoted.selection.previewUid), "commit mints the preview uid")
	check(is_equal_approx(float(item_at(ship, "engine").hp), 1.0) and is_equal_approx(float(ship.engine), 1.0), "the paid new engine is hp 1 and the scalar follows it")
	var retired: Dictionary = ship.moduleCondition.items[old_engine_uid]
	check(str(retired.location) == "locker" and is_equal_approx(float(retired.hp), 0.10) and str(retired.cause) == "Legacy engine scalar", "the old engine keeps its uid and the absorbed scalar")
	check(serial_of(ship) == before_serial + 1, "one funded unit advances the serial once")
	check(Money.total(core.state) == before_total and int(core.state.coins) == before_coins - int(bought.cost), "new-engine coins move purse to purse")
	check(purses_match(before_port, bought) and materials_match(before_stocks, bought), "new-engine materials and wages hit the live harbor")
	check(stores_of(ship) == kept and request == request_before, "new-engine install leaves stores and the request untouched")
	Construction.begin_day(port)
	var restored: Dictionary = Refit.install(core.state, port, ship, "engine", "stock_engine", {"itemUid": old_engine_uid})
	check(restored.ok and str(item_at(ship, "engine").itemUid) == old_engine_uid and is_equal_approx(float(ship.engine), 0.10), "reinstalling the old engine returns its impairment")
	check(str(ship.moduleCondition.items[fresh_engine_uid].location) == "locker" and is_equal_approx(float(ship.moduleCondition.items[fresh_engine_uid].hp), 1.0), "the new engine waits in the locker at hp 1")
	var saved_condition: Dictionary = ship.moduleCondition.duplicate(true)
	var saved_serial: int = serial_of(ship)
	Refit.ensure(ship)
	check(ship.moduleCondition == saved_condition and serial_of(ship) == saved_serial and is_equal_approx(float(ship.engine), 0.10) and is_equal_approx(float(ship.moduleCondition.items[fresh_engine_uid].hp), 1.0), "ensure after reinstall does not downsync the old scalar onto the stored engine or heal the installed one")

func distinct_guns() -> void:
	Construction.begin_day(port)
	var first_quote: Dictionary = Refit.quote(port, ship, "weapon:1", "rapid_gun", {"new": true})
	first_rapid_uid = str(first_quote.selection.previewUid)
	check(first_quote.ok and Refit.install(core.state, port, ship, "weapon:1", "rapid_gun", {"new": true}).ok, "first funded rapid gun installs")
	check(Condition.apply_component_damage(ship.moduleCondition, {"itemUid": first_rapid_uid, "loss": 0.60, "cause": "First gun"}).ok, "first rapid gun is damaged to 0.40")
	Construction.begin_day(port)
	check(Refit.install(core.state, port, ship, "weapon:1", "").ok and str(ship.moduleCondition.items[first_rapid_uid].location) == "locker", "first rapid gun returns to the locker")
	Construction.begin_day(port)
	var second_quote: Dictionary = Refit.quote(port, ship, "weapon:1", "rapid_gun", {"new": true})
	second_rapid_uid = str(second_quote.selection.previewUid)
	check(second_quote.ok and second_rapid_uid != first_rapid_uid and Refit.install(core.state, port, ship, "weapon:1", "rapid_gun", {"new": true}).ok, "second funded rapid gun is a different item")
	check(Condition.apply_component_damage(ship.moduleCondition, {"itemUid": second_rapid_uid, "loss": 0.45, "cause": "Second gun"}).ok, "second rapid gun is damaged to 0.55")
	Construction.begin_day(port)
	check(Refit.install(core.state, port, ship, "weapon:1", "").ok, "second rapid gun returns to the locker")
	Construction.begin_day(port)
	var picked: Dictionary = Refit.install(core.state, port, ship, "weapon:1", "rapid_gun", {"itemUid": first_rapid_uid})
	check(picked.ok and str(item_at(ship, "mount1").itemUid) == first_rapid_uid, "explicit spare uid selects the first rapid gun")
	check(is_equal_approx(float(item_at(ship, "mount1").hp), 0.40) and str(item_at(ship, "mount1").cause) == "First gun", "the first rapid gun still has its own condition")
	var other: Dictionary = ship.moduleCondition.items[second_rapid_uid]
	check(str(other.location) == "locker" and is_equal_approx(float(other.hp), 0.55) and str(other.cause) == "Second gun", "the second rapid gun stays distinct in the locker")

func workshop_exact_move() -> void:
	var fit: Dictionary = ship.loadout.duplicate(true)
	var request: Dictionary = {"slots": {"weapon:1": {"itemUid": second_rapid_uid}, "engine": {"itemUid": fresh_engine_uid}}}
	var fit_before: Dictionary = fit.duplicate(true)
	var request_before: Dictionary = request.duplicate(true)
	var serial_before: int = serial_of(ship)
	var condition_before: Dictionary = ship.moduleCondition.duplicate(true)
	var kept: Dictionary = stores_of(ship)
	Construction.begin_day(port)
	var preview: Dictionary = Workshop.preview(core, str(ship.uid), fit, request)
	check(preview.ok and preview.materials.is_empty() and preview.changes.size() == 2, "one workshop bill moves the locker gun and the locker engine")
	for change in preview.changes:
		check(bool(change.fromLocker) and str(change.source) == "locker", "both moved parts are owned locker parts")
	check(fit == fit_before and request == request_before, "preview does not rewrite the caller fit or request")
	check(ship.moduleCondition == condition_before and serial_of(ship) == serial_before, "preview does not absorb, mint, or rewrite condition")
	var state_ref = core.state
	var ship_ref: Dictionary = ship
	var port_ref: Dictionary = port
	var stock_ref = port.stocks
	var before_total: int = Money.total(core.state)
	var before_coins: int = int(core.state.coins)
	var reviewed: Dictionary = {"quoteId": preview.quoteId, "fittingPlan": {"goals": {}, "acquires": []}}
	var applied: Dictionary = Workshop.apply(core, str(ship.uid), fit, reviewed, request)
	check(applied.ok and applied.changed, "apply uses a fresh plan and ignores a client fitting plan")
	check(is_same(core.state, state_ref) and is_same(ship, ship_ref) and is_same(port, port_ref) and is_same(port.stocks, stock_ref), "apply keeps state, boat, port, and stock identity")
	check(Money.total(core.state) == before_total and int(core.state.coins) == before_coins - int(applied.cost), "workshop labor conserves coins")
	check(serial_of(ship) == serial_before, "an exact move does not mint a part")
	check(str(item_at(ship, "mount1").itemUid) == second_rapid_uid and is_equal_approx(float(item_at(ship, "mount1").hp), 0.55), "the selected rapid gun is now installed")
	check(str(item_at(ship, "engine").itemUid) == fresh_engine_uid and is_equal_approx(float(ship.engine), 1.0), "the selected hp 1 engine is now installed")
	check(str(ship.moduleCondition.items[first_rapid_uid].location) == "locker" and is_equal_approx(float(ship.moduleCondition.items[first_rapid_uid].hp), 0.40), "the displaced rapid gun keeps its condition")
	check(str(ship.moduleCondition.items[old_engine_uid].location) == "locker" and is_equal_approx(float(ship.moduleCondition.items[old_engine_uid].hp), 0.10), "the displaced engine keeps its impairment")
	check(stores_of(ship) == kept, "the exact move does not touch hull stores or wounds")
	var saved_condition: Dictionary = ship.moduleCondition.duplicate(true)
	var idle: Dictionary = Workshop.apply(core, str(ship.uid), ship.loadout)
	check(idle.ok and idle.changed == false and int(core.state.coins) == before_coins - int(applied.cost) and ship.moduleCondition == saved_condition, "an unchanged fitting is not charged or minted again")

func refusal_snapshots() -> void:
	var baseline: Dictionary = core.state.duplicate(true)
	var coins_now: int = int(core.state.coins)
	var supply_now: int = int(core.state.coinSupply)
	core.state.coins = 0
	core.state.coinSupply = Money.total(core.state)
	var poor_freeze: Dictionary = freeze()
	var poor: Dictionary = Workshop.preview(core, str(ship.uid), _economy_fit(), {"slots": {"engine": {"new": true}}})
	still(poor_freeze, "an empty purse preview leaves that career snapshot")
	check(not poor.ok, "an empty purse refuses the workshop bill")
	core.state.coins = coins_now
	core.state.coinSupply = supply_now
	check(core.state == baseline, "the unaffordable preview leaves the career snapshot")
	var stock_values: Dictionary = port.stocks.duplicate(true)
	for good in port.stocks.keys():
		port.stocks[good] = 0.0
	var bare_freeze: Dictionary = freeze()
	var bare: Dictionary = Refit.quote(port, ship, "engine", "economy_drive", {"new": true})
	still(bare_freeze, "missing materials leave the emptied stock object in place")
	check(not bare.ok, "missing harbor materials refuse before a purchase")
	for good in stock_values.keys():
		port.stocks[good] = stock_values[good]
	check(core.state == baseline, "the material refusal restores the same stock values and nothing else")
	var workforce: float = float(port.get("workforce", 0.0))
	var workers: float = float(port.get("availableWorkers", 0.0))
	var experts: float = float(port.get("availableSpecialists", 0.0))
	var specialist_pool = port.get("specialists", 0)
	port.workforce = 0
	port.availableWorkers = 0
	port.availableSpecialists = 0
	port.specialists = 0
	Construction.begin_day(port)
	var quiet: Dictionary = core.state.duplicate(true)
	var quiet_freeze: Dictionary = freeze()
	var unpaid: Dictionary = Workshop.preview(core, str(ship.uid), _economy_fit(), {"slots": {"engine": {"new": true}}})
	still(quiet_freeze, "no available labor leaves the career snapshot")
	check(not unpaid.ok and core.state == quiet, "no available labor refuses without mutating the career")
	port.workforce = workforce
	port.availableWorkers = workers
	port.availableSpecialists = experts
	port.specialists = specialist_pool
	Construction.begin_day(port)
	var serial_before: int = serial_of(ship)
	var missing_freeze: Dictionary = freeze()
	var missing: Dictionary = Refit.install(core.state, port, ship, "engine", "stock_engine", {"itemUid": "it-deadbeefdeadbeef-9"})
	still(missing_freeze, "a missing spare leaves the career snapshot")
	check(not missing.ok and serial_of(ship) == serial_before and int(core.state.coins) == coins_now, "a missing spare is not replaced by a purchase")
	var gun_uid: String = str(item_at(ship, "mount0").itemUid)
	var wrong_freeze: Dictionary = freeze()
	var wrong: Dictionary = Refit.quote(port, ship, "engine", "stock_engine", {"itemUid": gun_uid})
	still(wrong_freeze, "a wrong-family spare leaves the career snapshot")
	check(not wrong.ok and serial_of(ship) == serial_before, "a weapon cannot be installed as an engine")
	var paid_flag: Dictionary = {"paid": true}
	var paid_freeze: Dictionary = freeze()
	var paid_quote: Dictionary = Refit.quote(port, ship, "engine", "economy_drive", paid_flag)
	still(paid_freeze, "a caller paid flag leaves the career snapshot")
	check(not paid_quote.ok and paid_flag.has("paid"), "a caller paid flag is not a purchase")
	var own_freeze: Dictionary = freeze()
	var own: Dictionary = Refit.quote(port, ship, "engine", "economy_drive", {"new": true, "knownUids": [fresh_engine_uid]})
	still(own_freeze, "an own-uid registry quote leaves the career snapshot")
	check(not own.ok and serial_of(ship) == serial_before, "this hull's own uid in the registry refuses the bill")
	check(int(core.state.coins) == coins_now and ship.moduleCondition == baseline.fleet[0].moduleCondition, "item, flag, and registry refusals leave the record")
	var copy: Dictionary = ship.duplicate(true)
	var copy_port: Dictionary = port.duplicate(true)
	copy.moduleCondition.nextItemSeq = NAN
	var nan_freeze: Dictionary = freeze()
	var nan_quote: Dictionary = Refit.quote(copy_port, copy, "weapon:1", "rapid_gun", {"new": true})
	still(nan_freeze, "a NaN copy quote leaves the career snapshot")
	check(not nan_quote.ok and is_nan(float(copy.moduleCondition.nextItemSeq)), "NaN serial refuses and is not rounded")
	check(serial_of(ship) == serial_before, "the NaN copy is not the career record")
	ship.moduleConditions = {}
	var foreign_freeze: Dictionary = freeze()
	var foreign_schema: Dictionary = Workshop.preview(core, str(ship.uid), ship.loadout)
	still(foreign_freeze, "an unknown schema preview leaves that snapshot")
	check(not foreign_schema.ok, "moduleConditions plural stays an unknown schema")
	ship.erase("moduleConditions")
	check(not ship.has("moduleConditions") and serial_of(ship) == serial_before, "clearing the unknown schema leaves the physical record")
	Construction.begin_day(port)
	var stale_fit: Dictionary = _economy_fit()
	var stale_request: Dictionary = {"slots": {"engine": {"new": true}}}
	var stale_preview: Dictionary = Workshop.preview(core, str(ship.uid), stale_fit, stale_request)
	check(stale_preview.ok, "a current economy quote is reviewable before it goes stale")
	var drift: Dictionary = Condition.apply_component_damage(ship.moduleCondition, {"itemUid": gun_uid, "loss": 0.10, "cause": "Quote drift"})
	check(drift.ok, "damage after review changes the physical fingerprint")
	var after_drift: Dictionary = core.state.duplicate(true)
	var stale_freeze: Dictionary = freeze()
	var stale: Dictionary = Workshop.apply(core, str(ship.uid), stale_fit, {"quoteId": stale_preview.quoteId}, stale_request)
	still(stale_freeze, "a stale reviewed bill leaves the career snapshot")
	check(not stale.ok and "stale" in str(stale.message).to_lower() and core.state == after_drift, "a stale reviewed bill does not pay or fit")
	var accepted: Dictionary = Condition.accept_acquired_item(ship.moduleCondition, {"acquired": true, "family": "engines", "typeId": "stock_engine", "originHullType": "bilge_punt", "location": "locker", "hp": 1.0, "mountCount": Refit.hardpoints(ship.baseSpec).size(), "hullType": str(ship.type), "knownUids": []})
	check(accepted.ok, "setup stores a foreign-origin factory engine in the locker")
	var foreign_uid: String = str(accepted.itemUid)
	var coins_after_setup: int = int(core.state.coins)
	var serial_after_setup: int = serial_of(ship)
	var blocked_freeze: Dictionary = freeze()
	var blocked: Dictionary = Refit.quote(port, ship, "engine", "stock_engine", {"itemUid": foreign_uid})
	still(blocked_freeze, "a foreign-origin spare leaves the career snapshot")
	check(not blocked.ok and int(core.state.coins) == coins_after_setup and serial_of(ship) == serial_after_setup, "a foreign factory engine is not installed and is not replaced by a purchase")
	check(str(ship.moduleCondition.items[foreign_uid].location) == "locker" and str(ship.moduleCondition.items[foreign_uid].originHullType) == "bilge_punt", "the foreign factory engine keeps its origin")

func legacy_request_guard() -> void:
	var economy: Dictionary = _economy_fit()
	var uid: String = str(ship.uid)
	for request in _flag_rows():
		var frozen: Dictionary = freeze()
		var quoted: Dictionary = Refit.quote(port, ship, "engine", "boost_drive", request)
		still(frozen, "legacy quote refuses a malformed request with the career unchanged")
		frozen = freeze()
		var installed: Dictionary = Refit.install(core.state, port, ship, "engine", "boost_drive", request)
		still(frozen, "legacy install refuses a malformed request with the career unchanged")
		check(not quoted.ok and not installed.ok and not ship.has("moduleCondition"), "legacy malformed request does not buy or open a record")
		if request.has("paid") or request.has("confirmPaid"):
			check("unknown" in str(quoted.message).to_lower(), "legacy paid and confirmPaid are unknown fields")
		elif request.has("new") and not (request.new is bool):
			check("malformed" in str(quoted.message).to_lower(), "legacy numeric or non-bool new is malformed")
		elif request.has("initialize") and not (request.initialize is bool):
			check("malformed" in str(quoted.message).to_lower(), "legacy numeric or non-bool initialize is malformed")
	for request in _socket_rows():
		var frozen: Dictionary = freeze()
		var preview: Dictionary = Workshop.preview(core, uid, economy, request)
		still(frozen, "legacy preview refuses an unknown socket with the career unchanged")
		frozen = freeze()
		var applied: Dictionary = Workshop.apply(core, uid, economy, {}, request)
		still(frozen, "legacy apply refuses an unknown socket with the career unchanged")
		check(not preview.ok and not applied.ok and "socket" in str(preview.message).to_lower(), "legacy typo socket does not buy the other module")
	for request in _container_rows():
		var frozen: Dictionary = freeze()
		var preview: Dictionary = Workshop.preview(core, uid, economy, request)
		still(frozen, "legacy preview refuses a malformed slot map unchanged")
		frozen = freeze()
		var applied: Dictionary = Workshop.apply(core, uid, economy, {}, request)
		still(frozen, "legacy apply refuses a malformed slot map unchanged")
		check(not preview.ok and not applied.ok, "legacy malformed slots do not buy a default module")
	for request in [null, {}, {"initialize": false}]:
		var frozen: Dictionary = freeze()
		var quoted: Dictionary = Refit.quote(port, ship, "engine", "stock_engine", request)
		still(frozen, "omitted, empty, and initialize false stay on the legacy same-type refusal")
		check(not quoted.ok and "malformed" not in str(quoted.message).to_lower() and not ship.has("moduleCondition"), "null and initialize false do not become a schema refusal or a new record")
	var frozen_plain: Dictionary = freeze()
	var plain: Dictionary = Refit.quote(port, ship, "engine", "boost_drive", "paid")
	still(frozen_plain, "a non-dictionary legacy quote refuses unchanged")
	var frozen_install: Dictionary = freeze()
	var plain_install: Dictionary = Refit.install(core.state, port, ship, "engine", "boost_drive", 1)
	still(frozen_install, "a non-dictionary legacy install refuses unchanged")
	var frozen_preview: Dictionary = freeze()
	var plain_preview: Dictionary = Workshop.preview(core, uid, economy, "paid")
	still(frozen_preview, "a non-dictionary legacy preview refuses unchanged")
	var frozen_apply: Dictionary = freeze()
	var plain_apply: Dictionary = Workshop.apply(core, uid, economy, {}, 1)
	still(frozen_apply, "a non-dictionary legacy apply refuses unchanged")
	check(not plain.ok and not plain_install.ok and not plain_preview.ok and not plain_apply.ok, "non-dictionary requests refuse on every legacy public call")
	var frozen_idle: Dictionary = freeze()
	var idle: Dictionary = Workshop.preview(core, uid, ship.loadout, null)
	still(frozen_idle, "a null workshop request does not mutate the legacy career")
	check(idle.ok, "a null workshop request still previews the current legacy fitting")

func physical_request_guard() -> void:
	var economy: Dictionary = _economy_fit()
	var uid: String = str(ship.uid)
	var engine_uid: String = str(item_at(ship, "engine").itemUid)
	for request in _flag_rows():
		var frozen: Dictionary = freeze()
		var quoted: Dictionary = Refit.quote(port, ship, "engine", "economy_drive", request)
		still(frozen, "physical quote refuses a malformed request with the career unchanged")
		frozen = freeze()
		var installed: Dictionary = Refit.install(core.state, port, ship, "engine", "economy_drive", request)
		still(frozen, "physical install refuses a malformed request with the career unchanged")
		check(not quoted.ok and not installed.ok and str(item_at(ship, "engine").itemUid) == engine_uid, "physical malformed request does not buy or move the engine")
		if request.has("paid") or request.has("confirmPaid"):
			check("unknown" in str(quoted.message).to_lower(), "physical paid and confirmPaid are unknown fields")
	for request in _socket_rows():
		var frozen: Dictionary = freeze()
		var preview: Dictionary = Workshop.preview(core, uid, economy, request)
		still(frozen, "physical preview refuses an unknown socket with the career unchanged")
		frozen = freeze()
		var applied: Dictionary = Workshop.apply(core, uid, economy, {}, request)
		still(frozen, "physical apply refuses an unknown socket with the career unchanged")
		check(not preview.ok and not applied.ok and "socket" in str(preview.message).to_lower() and str(item_at(ship, "engine").itemUid) == engine_uid, "physical typo socket does not buy the economy engine")
	for request in _container_rows():
		var frozen: Dictionary = freeze()
		var preview: Dictionary = Workshop.preview(core, uid, economy, request)
		still(frozen, "physical preview refuses a malformed slot map unchanged")
		frozen = freeze()
		var applied: Dictionary = Workshop.apply(core, uid, economy, {}, request)
		still(frozen, "physical apply refuses a malformed slot map unchanged")
		check(not preview.ok and not applied.ok, "physical malformed slots do not buy a default module")
	var serial_now: int = serial_of(ship)
	var frozen_same: Dictionary = freeze()
	var same: Dictionary = Refit.quote(port, ship, "engine", "stock_engine", {"initialize": true})
	still(frozen_same, "initialize on the installed engine does not reseed")
	check(not same.ok and "installed" in str(same.message).to_lower() and str(item_at(ship, "engine").itemUid) == engine_uid, "initialize on an existing physical owner is idempotent, not a reseed")
	var frozen_preview: Dictionary = freeze()
	var preview: Dictionary = Workshop.preview(core, uid, ship.loadout, {"initialize": true})
	still(frozen_preview, "idempotent initialize preview does not mutate")
	var frozen_apply: Dictionary = freeze()
	var applied: Dictionary = Workshop.apply(core, uid, ship.loadout, {}, {"initialize": true})
	still(frozen_apply, "idempotent initialize apply does not mutate")
	check(preview.ok and applied.ok and applied.changed == false and serial_of(ship) == serial_now, "initialize on a physical boat previews and applies as already installed")

func funded_slot_purchase() -> void:
	var denial: Dictionary = core.state.duplicate(true)
	var stock_ref = port.stocks
	var frozen: Dictionary = freeze()
	var numeric: Dictionary = Refit.install(core.state, port, ship, "weapon:1", "rapid_gun", {"new": 1})
	still(frozen, "numeric new on a funded slot refuses unchanged")
	check(not numeric.ok and "malformed" in str(numeric.message).to_lower(), "numeric new is not a funded purchase")
	var coins_now: int = int(core.state.coins)
	var supply_now: int = int(core.state.coinSupply)
	core.state.coins = 0
	core.state.coinSupply = Money.total(core.state)
	frozen = freeze()
	var broke: Dictionary = Refit.install(core.state, port, ship, "weapon:1", "rapid_gun", {"new": true})
	still(frozen, "an unaffordable funded slot leaves that career snapshot unchanged")
	check(not broke.ok, "an empty purse refuses the single-slot purchase")
	core.state.coins = coins_now
	core.state.coinSupply = supply_now
	check(core.state == denial and is_same(port.stocks, stock_ref), "restoring the purse returns the same career and the same stock object")
	Construction.begin_day(port)
	var state_ref = core.state
	var ship_ref: Dictionary = ship
	var port_ref: Dictionary = port
	var before_stocks: Dictionary = port.stocks.duplicate(true)
	var before_coins: int = int(core.state.coins)
	var before_total: int = Money.total(core.state)
	var before_port: Dictionary = port.duplicate(true)
	var before_serial: int = serial_of(ship)
	var kept: Dictionary = stores_of(ship)
	var yard_used: float = float(port.get("_yardWorkersUsed", 0.0))
	var yard_ordinary: float = float(port.get("_yardOrdinaryUsed", 0.0))
	var yard_specialists: float = float(port.get("_yardSpecialistsUsed", 0.0))
	var request: Dictionary = {"new": true}
	var quoted: Dictionary = Refit.quote(port, ship, "weapon:1", "rapid_gun", request)
	check(quoted.ok and bool(quoted.get("selection", {}).get("newUnit", false)) and quoted.get("materials", {}).size() > 0 and is_same(port.stocks, stock_ref) and int(core.state.coins) == before_coins, "the funded quote prices real materials and does not touch stocks or coins")
	var preview_uid: String = str(quoted.get("selection", {}).get("previewUid", ""))
	var bought: Dictionary = Refit.install(core.state, port, ship, "weapon:1", "rapid_gun", request)
	var mounted: Dictionary = item_at(ship, "mount1")
	check(bought.ok and preview_uid != "" and str(mounted.get("itemUid", "")) == preview_uid and is_equal_approx(float(mounted.get("hp", -1.0)), 1.0) and str(mounted.get("status", "")) == "ok", "the funded gun commits the preview uid at hp 1")
	check(is_same(core.state, state_ref) and is_same(ship, ship_ref) and is_same(port, port_ref) and is_same(port.stocks, stock_ref), "the funded install keeps state, boat, port, and stock identity")
	check(stocks_exact(before_stocks, bought, stock_ref), "paid materials decrement inside the held stock dictionary")
	check(purses_match(before_port, bought) and Money.total(core.state) == before_total and int(core.state.coins) == before_coins - int(bought.get("cost", -1)), "the funded install moves every purse and conserves coins")
	check(is_equal_approx(float(port.get("_yardWorkersUsed", -1.0)), yard_used + float(bought.get("workerDays", -1.0)) + float(bought.get("expertDays", -1.0))), "yard workers reserved match the bill")
	check(is_equal_approx(float(port.get("_yardOrdinaryUsed", -1.0)), yard_ordinary + float(bought.get("workerDays", -1.0))), "ordinary yard time matches the bill")
	check(is_equal_approx(float(port.get("_yardSpecialistsUsed", -1.0)), yard_specialists + float(bought.get("expertDays", -1.0))), "specialist yard time matches the bill")
	check(serial_of(ship) == before_serial + 1 and stores_of(ship) == kept, "one funded gun advances one serial and leaves ammo and hull stores")

func _economy_fit() -> Dictionary:
	var fit: Dictionary = ship.loadout.duplicate(true)
	fit.engine = "economy_drive"
	return fit

func capacity_exchange() -> void:
	var added_ok: bool = true
	var guard: int = 0
	while locker_count(ship) < 256 and guard < 300:
		guard += 1
		var added: Dictionary = Condition.accept_acquired_item(ship.moduleCondition, {"acquired": true, "family": "weapons", "typeId": "rapid_gun", "originHullType": str(ship.type), "location": "locker", "hp": 1.0, "mountCount": Refit.hardpoints(ship.baseSpec).size(), "hullType": str(ship.type), "knownUids": []})
		if not added.ok:
			added_ok = false
			break
	check(added_ok and locker_count(ship) == 256, "setup fills the locker to the existing 256 bound")
	check(Records.publish(ship).ok and is_equal_approx(float(ship.engine), float(item_at(ship, "engine").hp)), "publish after setup matches the installed engine and does not heal it")
	var encoded: String = JSON.stringify(ship.moduleCondition)
	var parsed = JSON.parse_string(encoded)
	var roundtrip: Dictionary = Condition.validate(parsed, {"mountCount": Refit.hardpoints(ship.baseSpec).size(), "hullType": str(ship.type), "knownUids": [], "loadout": ship.loadout})
	check(parsed is Dictionary and roundtrip.ok and int(parsed.nextItemSeq) == serial_of(ship), "JSON roundtrip keeps whole counters and the loadout")
	Construction.begin_day(port)
	var fit: Dictionary = ship.loadout.duplicate(true)
	var serial_before: int = serial_of(ship)
	var before_total: int = Money.total(core.state)
	var stock_ref = port.stocks
	var preview: Dictionary = Workshop.preview(core, str(ship.uid), fit, {"slots": {"weapon:1": {"itemUid": first_rapid_uid}}})
	check(preview.ok and preview.materials.is_empty(), "a full locker can still preview an exact one-for-one gun exchange")
	var applied: Dictionary = Workshop.apply(core, str(ship.uid), fit, {"quoteId": preview.quoteId}, {"slots": {"weapon:1": {"itemUid": first_rapid_uid}}})
	check(applied.ok and locker_count(ship) == 256 and serial_of(ship) == serial_before, "the exchange commits at 256 without an intermediate extra spare")
	check(str(item_at(ship, "mount1").itemUid) == first_rapid_uid and is_equal_approx(float(item_at(ship, "mount1").hp), 0.40), "the exchanged gun keeps the condition it had in the locker")
	check(str(ship.moduleCondition.items[second_rapid_uid].location) == "locker" and is_equal_approx(float(ship.moduleCondition.items[second_rapid_uid].hp), 0.55), "the displaced gun is the one that entered the full locker")
	check(Money.total(core.state) == before_total and is_same(port.stocks, stock_ref), "the full-locker exchange conserves coins and the stock object")
	var before_remove: Dictionary = core.state.duplicate(true)
	var emptying: Dictionary = fit.duplicate(true)
	emptying.weapons[1] = ""
	var full_freeze: Dictionary = freeze()
	var blocked: Dictionary = Workshop.preview(core, str(ship.uid), emptying)
	still(full_freeze, "a full-locker removal preview leaves the career snapshot")
	check(not blocked.ok and core.state == before_remove, "a removal into a full locker refuses with no mutation")
	var slot_freeze: Dictionary = freeze()
	var blocked_slot: Dictionary = Refit.quote(port, ship, "weapon:1", "")
	still(slot_freeze, "a full-locker slot removal leaves the career snapshot")
	check(not blocked_slot.ok and core.state == before_remove, "a single-slot removal into a full locker also refuses")

func _initialize() -> void:
	var world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	core = Campaign.new(world)
	core.new_game(11)
	core.state.coins = maxi(int(core.state.coins), 1000000)
	ship = core.find_boat("boat-1")
	port = core.current_port()
	check(not ship.is_empty() and not port.is_empty(), "the career flagship is alongside a real harbor")
	if ship.is_empty() or port.is_empty():
		print("Fitting: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	for good in port.stocks.keys():
		if float(port.stocks[good]) < 40.0:
			port.stocks[good] = 40.0
	for good in ["engines", "guns", "iron", "copper", "supplies", "timber", "fuel"]:
		if not port.stocks.has(good) or float(port.stocks[good]) < 40.0:
			port.stocks[good] = 40.0
	core.state.coinSupply = Money.total(core.state)
	Construction.begin_day(port)
	var same_type: Dictionary = core.state.duplicate(true)
	check(not Refit.quote(port, ship, "engine", "stock_engine").ok and core.state == same_type, "a legacy same-type quote is already installed and has no side effect")
	legacy_scalar_case()
	detached_migration()
	legacy_request_guard()
	open_career_record()
	physical_request_guard()
	funded_slot_purchase()
	gun_cycle()
	paid_engine_replacement()
	distinct_guns()
	workshop_exact_move()
	refusal_snapshots()
	capacity_exchange()
	print("Fitting: %d checks, %d failures" % [checks, failures])
	print("NOTE fitting: this process was not a claimed pass. Cargo spare weight is not applied.")
	quit(0 if failures == 0 else 1)
