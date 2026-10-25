extends SceneTree
## Unrun native fixture. Baseline is the frozen recovery fixture. No pass is claimed here.
## Holder counts include the published career's own births. A wreck source that
## asks for a different hull hp is refused. A new legacy or site tow installs
## fresh parts at 0 hp, disabled, cause "Legacy wreck recovery", with no locker.
## A dictionary journal row without endpoints refuses before either tow branch.
## The exact two-key historical commission receipt is still accepted.
## Raw corrupt status or loadout, and a stale hull cursor, refuse before payment.
## An unrepaired tow is supportOnly and is not marked captureSecured.
## SaveValidation and Campaign.restore keep that flag with the exact parts.
## After the paid bill, FleetSupport.reserve may return the hull to combat.
## Headless campaign only. accept_acquired_item stages the loose spare on the
## detached hull. It is not a recovery payment and there is no confirmPaid path.
const Campaign = preload("res://scripts/campaign.gd")
const Salvage = preload("res://scripts/salvage.gd")
const Recovery = preload("res://scripts/equipment_recovery.gd")
const Damage = preload("res://scripts/damage.gd")
const Condition = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Refit = preload("res://scripts/refit.gd")
const Money = preload("res://scripts/money.gd")
const Construction = preload("res://scripts/construction.gd")
const Lifecycle = preload("res://scripts/equipment_lifecycle.gd")
const SaveValidation = preload("res://scripts/save_validation.gd")
const EquipmentService = preload("res://scripts/equipment_service.gd")
const FleetSupport = preload("res://scripts/fleet_support.gd")
const HISTORICAL_COMMISSION := "Commission: materials, wages in escrow, yard income and duty"

var world: Dictionary
var c
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL recovery: " + message)

func reset() -> void:
	c.new_game(31)
	c.state.coins = maxi(int(c.state.coins), 1000000)
	# Root-authorized synthetic capital injection must reconcile total supply.
	c.state.coinSupply = Money.total(c.state)

func item_at(condition: Dictionary, location: String) -> Dictionary:
	for key in condition.items.keys():
		var item: Dictionary = condition.items[key]
		if str(item.location) == location:
			return item
	return {}

func mounts_clean(spec) -> bool:
	if not spec is Dictionary or not spec.get("weaponMounts", []) is Array:
		return true
	for mount in spec.get("weaponMounts", []):
		if mount is Dictionary and (mount.has("hp") or mount.has("itemUid") or mount.has("status") or mount.has("cause")):
			return false
	return true

func make_physical(uid: String) -> Dictionary:
	var spec: Dictionary = c.hull("tin_skiff")
	var ship: Dictionary = Damage.create_ship(spec, {"fuel": 10.0, "ammo": 50.0, "supplies": 2.0, "crew": 0.0})
	ship.uid = uid
	ship.id = uid
	ship.team = "enemy"
	ship.engine = 1.0
	ship.x = 40.0
	ship.y = 50.0
	c.fit_boat(ship, true)
	var seeded: Dictionary = Records.initialize(ship, {"base": ship.baseSpec, "loadout": ship.loadout, "catalog": Refit.catalog(), "identity": uid, "knownUids": []})
	check(seeded.ok, "physical seed " + uid)
	if not seeded.ok:
		return ship
	var gun: Dictionary = item_at(ship.moduleCondition, "mount0")
	var engine: Dictionary = item_at(ship.moduleCondition, "engine")
	check(Condition.apply_component_damage(ship.moduleCondition, {"itemUid": str(gun.itemUid), "loss": 0.75, "cause": "Shell splinter"}).ok, "gun damaged to 0.25")
	check(Condition.apply_component_damage(ship.moduleCondition, {"itemUid": str(engine.itemUid), "loss": 0.75, "cause": "Flooded engine"}).ok, "engine damaged to 0.25")
	var spare: Dictionary = Condition.accept_acquired_item(ship.moduleCondition, {"acquired": true, "family": "weapons", "typeId": "rapid_gun", "originHullType": "tin_skiff", "location": "locker", "hp": 0.40, "cause": "Cracked breech", "mountCount": Refit.hardpoints(ship.baseSpec).size(), "hullType": "tin_skiff", "knownUids": []})
	check(spare.ok, "loose spare is a real catalog item")
	ship.engine = 0.10
	return ship

func same_parts(saved: Dictionary, live: Dictionary) -> bool:
	if str(live.birthNamespace) != str(saved.birthNamespace) or int(live.nextItemSeq) != int(saved.nextItemSeq):
		return false
	if live.items.size() != saved.items.size():
		return false
	for key in saved.items.keys():
		if not live.items.has(key):
			return false
		var a: Dictionary = saved.items[key]
		var b: Dictionary = live.items[key]
		if str(a.itemUid) != str(b.itemUid) or str(a.typeId) != str(b.typeId) or str(a.originHullType) != str(b.originHullType):
			return false
		if str(a.location) != str(b.location) or str(a.status) != str(b.status) or str(a.cause) != str(b.cause):
			return false
		if not is_equal_approx(float(a.hp), float(b.hp)):
			return false
	return true

func holders() -> Array:
	var found: Dictionary = Recovery.active_holders(c.state)
	check(bool(found.get("ok", false)), "custody scan can be read")
	if not bool(found.get("ok", false)):
		return []
	return found.get("holders", [])

func record_source(ship: Dictionary, source_id: String) -> Dictionary:
	ship.sunk = true
	var made: Array = Salvage.record_battle(c, {"ships": [ship], "wrecks": [{"id": ship.id, "uid": ship.uid, "cause": "flooding"}]}, source_id)
	if made.is_empty():
		return {}
	return Salvage.find_wreck(c.state, str(made[0].id))

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		print("FAIL recovery: fixture is headless only")
		quit(1)
		return
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c = Campaign.new(world)
	paid_tow()
	scalar_cases()
	strip_cases()
	denials()
	custody_cases()
	legacy_wreck()
	root_findings()
	journal_rows()
	r3_edges()
	print("Recovery: %d checks, %d failures" % [checks, failures])
	print("NOTE recovery: this process was not a claimed pass. Cargo weight of locker parts is not applied.")
	quit(0 if failures == 0 else 1)

func paid_tow() -> void:
	reset()
	var source: Dictionary = make_physical("src-hull-1")
	var survivor: Dictionary = make_physical("src-hull-live")
	if not source.has("moduleCondition") or not survivor.has("moduleCondition"):
		return
	var saved: Dictionary = source.moduleCondition.duplicate(true)
	var survivor_before: Dictionary = survivor.duplicate(true)
	var flagship: Dictionary = c.find_boat("boat-1")
	var flag_before: Dictionary = flagship.duplicate(true)
	var flag_ref: Dictionary = flagship
	var custodians_before: int = holders().size()
	source.sunk = true
	var battle: Dictionary = {"ships": [source, survivor], "wrecks": [{"id": source.id, "uid": source.uid, "cause": "flooding"}]}
	var made: Array = Salvage.record_battle(c, battle, "battle:equipment")
	check(made.size() == 1 and not source.has("moduleCondition"), "the sunk hull is no longer an active owner")
	check(survivor == survivor_before and not survivor.sunk, "the live survivor hull is unchanged")
	check(is_same(flagship, flag_ref) and flagship == flag_before, "the player's other boat is unchanged")
	Salvage.ensure(c.state)
	var wreck: Dictionary = Salvage.find_wreck(c.state, str(made[0].id))
	var carried: Dictionary = wreck.sourceModuleCondition
	var saved_engine: Dictionary = item_at(saved, "engine")
	var synced_engine: Dictionary = item_at(carried, "engine")
	check(wreck.has("sourceModuleCondition"), "the wreck keeps a physical snapshot")
	check(str(synced_engine.itemUid) == str(saved_engine.itemUid) and str(synced_engine.cause) == "Flooded engine", "the engine keeps its id and cause")
	check(is_equal_approx(float(synced_engine.hp), 0.10) and str(synced_engine.status) == "disabled", "the 0.10 scalar is absorbed before custody, not healed back to 0.25")
	check(is_equal_approx(float(carried.legacyEngineSynced), 0.10), "the engine watermark matches the synchronized part")
	check(str(item_at(carried, "mount0").itemUid) == str(item_at(saved, "mount0").itemUid) and is_equal_approx(float(item_at(carried, "mount0").hp), 0.25), "the gun keeps its id and its own damage")
	check(str(item_at(carried, "locker").itemUid) == str(item_at(saved, "locker").itemUid) and is_equal_approx(float(item_at(carried, "locker").hp), 0.40), "the spare keeps its id and its own damage")
	check(str(carried.birthNamespace) == str(saved.birthNamespace) and int(carried.nextItemSeq) == int(saved.nextItemSeq), "birth id and serial stay")
	check(str(source.equipmentRetiredTo) == str(wreck.id) and not source.has("moduleCondition"), "the sunk hull is marked retired to this wreck and is not an owner")
	check(str(wreck.equipmentCustody) == "wreck" and str(wreck.retiredSourceUid) == "src-hull-1", "the wreck is the recorded custodian")
	check(mounts_clean(wreck.get("spec", {})), "the wreck spec has no mount condition")
	check(holders().size() == custodians_before + 1, "the wreck is the one added custodian")
	var again: Array = Salvage.record_battle(c, battle, "battle:equipment")
	check(again.size() == 1 and c.state.wrecks.size() == 1 and same_parts(carried, Salvage.find_wreck(c.state, str(wreck.id)).sourceModuleCondition), "recording the same battle does not mint another wreck or part")
	var encoded: String = JSON.stringify(c.state)
	var parsed = JSON.parse_string(encoded)
	check(parsed is Dictionary, "the campaign survives JSON")
	if not parsed is Dictionary:
		return
	c.state = parsed
	Salvage.ensure(c.state)
	wreck = Salvage.find_wreck(c.state, str(made[0].id))
	check(same_parts(carried, wreck.sourceModuleCondition), "JSON keeps the synchronized parts, serial, and birth id")
	var quiet: Dictionary = c.state.duplicate(true)
	var quoted: Dictionary = Salvage.quote(c, str(wreck.id), "tow")
	check(bool(quoted.ok) and c.state == quiet, "the tow quote does not pay or move equipment")
	check(is_equal_approx(float(quoted.recoveredHp), float(quoted.fittedMaxHp) * 0.35), "the quote hp is the fitted 0.35 contract")
	var forged_state: Dictionary = c.state.duplicate(true)
	var forged: Dictionary = Lifecycle.stage_birth(c.state, c.data, c.hull(str(wreck.hull)), "boat-%d" % int(c.state.nextUid), {
		"moduleCondition": wreck.sourceModuleCondition.duplicate(true),
		"loadout": wreck.get("sourceLoadout", {}).duplicate(true),
		"hullHp": float(c.hull(str(wreck.hull)).get("hp", 1.0)),
		"sourceWreckId": str(wreck.id)
	})
	check(not forged.ok and str(forged.get("message", "")).contains("tow recovery contract") and c.state == forged_state, "a wreck birth refuses an arbitrary requested hull hp")
	var harbor: Dictionary = c.port(str(c.state.lastPort))
	var total_before: int = Money.total(c.state)
	var coins_before: int = int(c.state.coins)
	var household: int = int(harbor.householdPurse)
	var expert_purse: int = int(harbor.expertPurse)
	var business: int = int(harbor.cash)
	var workers: int = int(harbor.availableWorkers)
	var specialists: int = int(harbor.get("availableSpecialists", harbor.get("specialistWorkers", 0)))
	var yard_workers: int = int(harbor.get("workers", 0))
	var fleet_before: int = c.state.fleet.size()
	var towed: Dictionary = Salvage.recover(c, str(wreck.id), "tow")
	check(bool(towed.ok), "paid tow returns the hull")
	check(Money.total(c.state) == total_before, "tow coins stay inside the existing purses")
	check(int(c.state.coins) == coins_before - int(quoted.total), "the company purse pays the quoted tug bill")
	check(int(harbor.householdPurse) == household + int(quoted.ordinary), "tug wages reach the household purse")
	check(int(harbor.expertPurse) == expert_purse + int(quoted.expert), "inspection reaches the specialist purse")
	check(int(harbor.cash) == business + int(quoted.fee), "the company fee reaches the harbor cash purse")
	check(int(harbor.availableWorkers) == workers - 3 and int(harbor.workers) == yard_workers + 3, "the tug uses three harbor workers")
	check(int(harbor.get("availableSpecialists", harbor.get("specialistWorkers", 0))) == specialists - 1, "the inspection uses one specialist")
	check(c.state.fleet.size() == fleet_before + 1, "tow adds one hull")
	var boat: Dictionary = c.find_boat(str(towed.boatUid))
	check(not boat.is_empty() and str(boat.uid) != "src-hull-1", "the recovered hull has a new uid")
	if boat.is_empty() or not boat.has("moduleCondition"):
		return
	check(same_parts(carried, boat.moduleCondition), "the recovered hull has the synchronized parts and the same ids")
	check(str(boat.moduleCondition.birthNamespace) == "src-hull-1", "birth id stays the original hull id")
	check(is_equal_approx(float(boat.engine), 0.10), "the installed engine publishes the synchronized 0.10, not the old 0.25 and not 1.0")
	check(str(source.equipmentRetiredTo) == str(made[0].id), "tow leaves the source retirement marker in place")
	check(is_equal_approx(float(item_at(boat.moduleCondition, "mount0").hp), 0.25) and str(item_at(boat.moduleCondition, "mount0").cause) == "Shell splinter", "the gun is still the damaged gun")
	check(is_equal_approx(float(item_at(boat.moduleCondition, "locker").hp), 0.40) and str(item_at(boat.moduleCondition, "locker").cause) == "Cracked breech", "the loose spare keeps its own condition")
	check(int(boat.refitLocker.get("rapid_gun", 0)) == 1, "the spare projects as one locker part")
	check(is_equal_approx(float(boat.hp), float(boat.maxHp) * 0.35) and is_equal_approx(float(boat.hp), float(quoted.recoveredHp)), "tow hull damage stays the quoted 35 percent contract")
	check(float(boat.crew) == 0.0 and float(boat.fuel) == 0.0 and float(boat.ammo) == 0.0 and float(boat.supplies) == 0.0, "tow stores and crew stay empty")
	check(bool(boat.mothballed) and bool(boat.needsHarborRepair) and bool(boat.towed) and bool(boat.get("supportOnly", false)) and not bool(boat.get("captureSecured", false)), "tow still requires a crew and paid harbor repair, and stays support-only without a capture flag")
	check(mounts_clean(boat.spec), "recovered mounts are not a second condition record")
	wreck = Salvage.find_wreck(c.state, str(wreck.id))
	check(not wreck.has("sourceModuleCondition") and str(wreck.equipmentCustody) == "transferred" and wreck.get("transferredItemUids", []).size() == carried.items.size(), "the wreck releases custody once and keeps the transferred uid list")
	var live_holders: Array = holders()
	var recovered_holder := false
	var wreck_still := false
	for holder in live_holders:
		if str(holder.get("id", "")) == str(boat.uid):
			recovered_holder = true
		if str(holder.get("id", "")) == str(wreck.id):
			wreck_still = true
	check(live_holders.size() == custodians_before + 1 and recovered_holder and not wreck_still, "the recovered boat replaces the wreck as custodian")
	check(Recovery.registry(c.state, "", "").ok, "no part id is owned twice")
	var fleet_after: int = c.state.fleet.size()
	var coins_after: int = int(c.state.coins)
	var serial_after: int = int(boat.moduleCondition.nextItemSeq)
	check(not bool(Salvage.recover(c, str(wreck.id), "tow").ok), "the wreck cannot be towed twice")
	check(not bool(Salvage.recover(c, str(wreck.id), "strip").ok), "a towed wreck cannot also be stripped")
	check(c.state.fleet.size() == fleet_after and int(c.state.coins) == coins_after and int(boat.moduleCondition.nextItemSeq) == serial_after, "a repeat tow or strip adds no hull, coins, or parts")
	var canon_uid := str(boat.get("uid", ""))
	var canon_hp := float(boat.get("hp", -1.0))
	var canon_text := JSON.stringify(c.state)
	var canon_checked: Dictionary = SaveValidation.validate(JSON.parse_string(canon_text), c.data)
	var canon_saved: Dictionary = {}
	if bool(canon_checked.get("ok", false)):
		for entry in canon_checked.state.get("fleet", []):
			if entry is Dictionary and str(entry.get("uid", "")) == canon_uid:
				canon_saved = entry
	check(bool(canon_checked.get("ok", false)) and canon_saved.has("moduleCondition") and same_parts(carried, canon_saved.moduleCondition) and is_equal_approx(float(canon_saved.get("hp", -1.0)), canon_hp) and bool(canon_saved.get("supportOnly", false)) and not bool(canon_saved.get("captureSecured", false)), "SaveValidation keeps the canonical parts, hull hp, and support-only flag: " + str(canon_checked.get("message", "")))
	var canon_reloaded: Dictionary = c.restore(JSON.parse_string(canon_text))
	boat = c.find_boat(canon_uid)
	check(bool(canon_reloaded.get("ok", false)) and boat.has("moduleCondition") and same_parts(carried, boat.moduleCondition) and is_equal_approx(float(boat.get("hp", -2.0)), canon_hp) and bool(boat.get("supportOnly", false)) and not bool(boat.get("captureSecured", false)), "Campaign.restore does not heal the canonical tow: " + str(canon_reloaded.get("message", "")))

func strip_cases() -> void:
	reset()
	var full: Dictionary = record_source(make_physical("src-strip"), "battle:strip-all")
	var saved_coins: int = int(c.state.coins)
	var fleet_before: int = c.state.fleet.size()
	var quoted: Dictionary = Salvage.quote(c, str(full.id), "strip")
	check(bool(quoted.ok), "full strip has a commodity bill")
	var stripped: Dictionary = Salvage.recover(c, str(full.id), "strip")
	check(bool(stripped.ok) and int(c.state.coins) == saved_coins and c.state.fleet.size() == fleet_before, "full strip moves lots and no coins or hull")
	for good in quoted.items:
		check(is_equal_approx(float(c.state.cargo.get(good, 0.0)), float(quoted.items[good])) or good == "food", "cargo received " + str(good))
	full = Salvage.find_wreck(c.state, str(full.id))
	check(str(full.status) == "stripped" and not full.has("sourceModuleCondition") and str(full.equipmentCustody) == "retired", "full strip retires the physical parts")
	var after_strip: Dictionary = c.state.duplicate(true)
	check(not bool(Salvage.recover(c, str(full.id), "tow").ok) and c.state == after_strip, "a fully stripped wreck cannot be towed")
	check(not bool(Salvage.recover(c, str(full.id), "strip").ok) and c.state == after_strip, "full strip cannot be repeated")
	var partial_ship: Dictionary = make_physical("src-partial")
	var partial: Dictionary = record_source(partial_ship, "battle:strip-part")
	var component := ""
	for good in partial.components.keys():
		if not Recovery.is_store_good(str(good)) and float(partial.components[good]) > 0.0:
			component = str(good)
			break
	check(not component.is_empty(), "the wreck has a hull commodity to strip")
	var before_partial: int = c.state.fleet.size()
	var custodians_partial: int = holders().size()
	var took: Dictionary = Salvage.strip_good(c, str(partial.id), component, float(partial.components[component]))
	partial = Salvage.find_wreck(c.state, str(partial.id))
	check(bool(took.ok) and bool(partial.hullStripped) and not partial.has("sourceModuleCondition"), "a hull lot retires the intact parts")
	check(c.state.fleet.size() == before_partial and holders().size() == custodians_partial - 1, "partial strip does not create a second hull or custodian")
	var held: Dictionary = c.state.duplicate(true)
	check(not bool(Salvage.recover(c, str(partial.id), "tow").ok) and c.state == held, "a partly stripped hull cannot be towed intact")
	var stored_ship: Dictionary = make_physical("src-fuel")
	var stored: Dictionary = record_source(stored_ship, "battle:fuel")
	var fuel_saved: Dictionary = stored.sourceModuleCondition.duplicate(true)
	var sip: Dictionary = Salvage.strip_good(c, str(stored.id), "fuel", 0.1)
	stored = Salvage.find_wreck(c.state, str(stored.id))
	check(bool(sip.ok) and same_parts(fuel_saved, stored.sourceModuleCondition) and str(stored.equipmentCustody) == "wreck", "store-only recovery leaves the parts on the wreck")
	check(bool(Salvage.recover(c, str(stored.id), "tow").ok), "a wreck stripped only of stores can still be towed")
	var recovered: Dictionary = c.find_boat(str(Salvage.find_wreck(c.state, str(stored.id)).towedBoatUid))
	check(not recovered.is_empty() and recovered.has("moduleCondition") and same_parts(fuel_saved, recovered.moduleCondition), "the towed hull still has the parts that stayed aboard")

func denials() -> void:
	reset()
	var wreck: Dictionary = record_source(make_physical("src-corrupt"), "battle:corrupt")
	if not wreck.has("sourceModuleCondition"):
		check(false, "corrupt case had no physical snapshot")
		return
	wreck.sourceModuleCondition.nextItemSeq = "bad"
	Salvage.ensure(c.state)
	wreck = Salvage.find_wreck(c.state, str(wreck.id))
	check(str(wreck.sourceModuleCondition.nextItemSeq) == "bad", "a bad serial is kept and not truncated")
	var snap: Dictionary = c.state.duplicate(true)
	check(not bool(Salvage.quote(c, str(wreck.id), "tow").ok), "a corrupt snapshot has no tow quote")
	check(not bool(Salvage.recover(c, str(wreck.id), "tow").ok), "a corrupt snapshot cannot be towed")
	check(not bool(Salvage.recover(c, str(wreck.id), "strip").ok), "a corrupt snapshot cannot be stripped")
	check(not bool(Salvage.strip_good(c, str(wreck.id), "fuel", 0.1).ok), "a corrupt snapshot cannot lose a store")
	check(c.state == snap and str(Salvage.find_wreck(c.state, str(wreck.id)).sourceModuleCondition.nextItemSeq) == "bad", "corrupt refusals leave the career and the raw record")
	reset()
	var broke: Dictionary = record_source(make_physical("src-broke"), "battle:broke")
	c.state.coins = 0
	var broke_snap: Dictionary = c.state.duplicate(true)
	check(not bool(Salvage.recover(c, str(broke.id), "tow").ok) and c.state == broke_snap, "a tow without the fee leaves the career")
	reset()
	var quiet: Dictionary = record_source(make_physical("src-yard"), "battle:yard")
	var harbor: Dictionary = c.port(str(c.state.lastPort))
	harbor.availableWorkers = 0
	harbor.availableSpecialists = 0
	harbor.specialistWorkers = 0
	var yard_snap: Dictionary = c.state.duplicate(true)
	check(not bool(Salvage.recover(c, str(quiet.id), "tow").ok) and c.state == yard_snap, "a tow without a tug crew leaves the career")
	reset()
	var crowded: Dictionary = record_source(make_physical("src-full"), "battle:full")
	var guard: int = 0
	while c.can_add_boat(c.hull("tin_skiff")) and guard < 120:
		c.add_boat(c.hull("tin_skiff"), 0)
		guard += 1
	check(not c.can_add_boat(c.hull("tin_skiff")), "the roster is actually full")
	var full_snap: Dictionary = c.state.duplicate(true)
	check(not bool(Salvage.recover(c, str(crowded.id), "tow").ok) and c.state == full_snap, "a full roster leaves the wreck and the career")

func scalar_cases() -> void:
	reset()
	var ship: Dictionary = make_physical("src-up")
	if not ship.has("moduleCondition"):
		return
	ship.engine = 0.90
	var saved: Dictionary = ship.moduleCondition.duplicate(true)
	var engine_uid := str(item_at(saved, "engine").itemUid)
	var wreck: Dictionary = record_source(ship, "battle:up")
	if not wreck.has("sourceModuleCondition"):
		check(false, "upward scalar produced no snapshot")
		return
	var live: Dictionary = item_at(wreck.sourceModuleCondition, "engine")
	check(str(live.itemUid) == engine_uid and is_equal_approx(float(live.hp), 0.25) and str(live.status) == "damaged" and str(live.cause) == "Flooded engine", "an upward scalar does not heal or rewrite the engine")
	var quoted: Dictionary = Salvage.quote(c, str(wreck.id), "tow")
	var coins_before := int(c.state.coins)
	var towed: Dictionary = Salvage.recover(c, str(wreck.id), "tow")
	var boat: Dictionary = c.find_boat(str(towed.get("boatUid", "")))
	check(bool(quoted.ok) and bool(towed.ok) and not boat.is_empty() and is_equal_approx(float(boat.engine), 0.25), "tow publishes 0.25 after an upward scalar")
	check(not boat.is_empty() and boat.has("moduleCondition") and str(item_at(boat.moduleCondition, "engine").itemUid) == engine_uid and is_equal_approx(float(item_at(boat.moduleCondition, "engine").hp), 0.25), "the upward-scalar tow keeps the engine uid and damage")
	check(int(c.state.coins) == coins_before - int(quoted.total), "the upward-scalar tow pays the quoted bill once")

func custody_cases() -> void:
	reset()
	check(c.state.get("fleetOwners") is Array and not c.state.fleetOwners.is_empty(), "the campaign has an NPC fleet")
	if not c.state.get("fleetOwners") is Array or c.state.fleetOwners.is_empty():
		return
	Salvage.ensure(c.state)
	var alias: Dictionary = make_physical("src-alias")
	alias.sunk = true
	c.state.fleetOwners[0].boats.append(alias)
	if not c.state.get("boardingPrizes") is Array:
		c.state.boardingPrizes = []
	c.state.boardingPrizes.append(alias)
	var alias_before: int = holders().size()
	var aliased: Array = Salvage.record_battle(c, {"ships": [alias], "wrecks": [{"id": alias.id, "uid": alias.uid, "cause": "flooding"}]}, "battle:alias")
	check(aliased.size() == 1 and holders().size() == alias_before, "one hull listed twice is still one custodian")
	check(str(alias.get("equipmentRetiredTo", "")) == str(aliased[0].id) and not alias.has("moduleCondition"), "the aliased hull keeps one retirement marker")
	reset()
	Salvage.ensure(c.state)
	var same_uid: Dictionary = make_physical("src-same-uid")
	var twin: Dictionary = same_uid.duplicate(true)
	twin.uid = same_uid.uid
	c.state.fleetOwners[0].boats.append(twin)
	c.state.boardingPrizes = [same_uid]
	same_uid.sunk = true
	var uid_snap: Dictionary = c.state.duplicate(true)
	var uid_made: Array = Salvage.record_battle(c, {"ships": [same_uid], "wrecks": [{"uid": same_uid.uid, "cause": "flooding"}]}, "battle:same-uid")
	check(uid_made.is_empty() and c.state == uid_snap and same_uid.has("moduleCondition"), "two hulls with one uid record nothing")
	reset()
	Salvage.ensure(c.state)
	var first: Dictionary = make_physical("src-clone-item")
	var second: Dictionary = {"uid": "src-other-hull", "moduleCondition": first.moduleCondition.duplicate(true)}
	c.state.fleetOwners[0].boats.append(second)
	first.sunk = true
	var clone_snap: Dictionary = c.state.duplicate(true)
	var clone_made: Array = Salvage.record_battle(c, {"ships": [first], "wrecks": [{"uid": first.uid, "cause": "flooding"}]}, "battle:clone-item")
	check(clone_made.is_empty() and c.state == clone_snap and first.has("moduleCondition"), "a second owner of the same part records nothing")
	reset()
	Salvage.ensure(c.state)
	var clean: Dictionary = make_physical("src-clean")
	c.state.boardingPrizes = [{"uid": "bad-prize", "moduleCondition": {"broken": true}}]
	clean.sunk = true
	var corrupt_snap: Dictionary = c.state.duplicate(true)
	var corrupt_made: Array = Salvage.record_battle(c, {"ships": [clean], "wrecks": [{"uid": clean.uid, "cause": "flooding"}]}, "battle:bad-prize")
	check(corrupt_made.is_empty() and c.state == corrupt_snap and clean.has("moduleCondition"), "a corrupt prize blocks capture and changes nothing")
	reset()
	var blocked: Dictionary = record_source(make_physical("src-then-bad"), "battle:then-bad")
	c.state.boardingPrizes = [{"uid": "bad-prize-2", "moduleCondition": {"broken": true}}]
	Salvage.ensure(c.state)
	var tow_snap: Dictionary = c.state.duplicate(true)
	check(not bool(Salvage.quote(c, str(blocked.id), "tow").ok) and not bool(Salvage.recover(c, str(blocked.id), "tow").ok) and c.state == tow_snap, "a corrupt other owner blocks tow and changes nothing")
	reset()
	var marked: Dictionary = make_physical("src-marker")
	c.state.fleetOwners[0].boats.append(marked)
	var marked_wreck: Dictionary = record_source(marked, "battle:marker")
	var marker := str(marked.get("equipmentRetiredTo", ""))
	check(marker == str(marked_wreck.id) and not marked.has("moduleCondition"), "the sunk NPC is marked retired to the wreck")
	var marked_tow: Dictionary = Salvage.recover(c, str(marked_wreck.id), "tow")
	check(bool(marked_tow.ok) and str(marked.equipmentRetiredTo) == marker and not marked.has("moduleCondition"), "tow keeps the retirement marker and does not reseed the NPC")
	var again: Array = Salvage.record_battle(c, {"ships": [marked], "wrecks": [{"uid": marked.uid, "cause": "flooding"}]}, "battle:marker-again")
	check(again.is_empty() and str(marked.equipmentRetiredTo) == marker and not marked.has("moduleCondition"), "the retired hull is not given a second wreck or a new part")
	marked.moduleCondition = {"broken": true}
	Salvage.ensure(c.state)
	var reseed_snap: Dictionary = c.state.duplicate(true)
	var reseed: Array = Salvage.record_battle(c, {"ships": [marked], "wrecks": [{"uid": marked.uid, "cause": "flooding"}]}, "battle:reseed")
	check(reseed.is_empty() and c.state == reseed_snap and marked.has("moduleCondition"), "a retired hull seeded again records nothing and is not wiped")
	marked.erase("moduleCondition")
	var filler := 0
	while c.state.wrecks.size() < 130 and filler < 140:
		c.state.wrecks.append({"id": "wreck-fill-%d" % filler, "status": "stripped", "hull": "tin_skiff", "name": "Old", "stores": {}, "components": {}})
		filler += 1
	Salvage.ensure(c.state)
	var still := false
	for boat in c.state.fleetOwners[0].boats:
		if is_same(boat, marked):
			still = true
	check(still and str(marked.equipmentRetiredTo) == marker and not marked.has("moduleCondition"), "pruning wrecks leaves the retirement marker on the source hull")
	reset()
	var inconsistent: Dictionary = record_source(make_physical("src-custody"), "battle:custody")
	var custody_id := str(inconsistent.id)
	inconsistent = Salvage.find_wreck(c.state, custody_id)
	inconsistent.equipmentCustody = "transferred"
	Salvage.ensure(c.state)
	var moved_snap: Dictionary = c.state.duplicate(true)
	check(not bool(Salvage.quote(c, custody_id, "tow").ok), "transferred custody with a payload has no tow quote")
	check(not bool(Salvage.recover(c, custody_id, "tow").ok), "transferred custody with a payload cannot be towed")
	check(not bool(Salvage.recover(c, custody_id, "strip").ok), "transferred custody with a payload cannot be stripped")
	check(not bool(Salvage.strip_good(c, custody_id, "fuel", 0.1).ok), "transferred custody with a payload cannot lose a store")
	check(c.state == moved_snap and Salvage.find_wreck(c.state, custody_id).has("sourceModuleCondition"), "the inconsistent payload stays raw and the career stays put")
	reset()
	var missing: Dictionary = record_source(make_physical("src-missing"), "battle:missing")
	var missing_id := str(missing.id)
	missing = Salvage.find_wreck(c.state, missing_id)
	missing.erase("sourceModuleCondition")
	missing.equipmentCustody = "wreck"
	Salvage.ensure(c.state)
	var missing_snap: Dictionary = c.state.duplicate(true)
	check(not bool(Salvage.recover(c, missing_id, "tow").ok) and c.state == missing_snap, "wreck custody without a payload refuses and changes nothing")
	reset()
	var invented: Dictionary = record_source(make_physical("src-invented"), "battle:invented")
	var invented_id := str(invented.id)
	invented = Salvage.find_wreck(c.state, invented_id)
	invented.equipmentCustody = "vault"
	Salvage.ensure(c.state)
	var invented_snap: Dictionary = c.state.duplicate(true)
	check(not bool(Salvage.recover(c, invented_id, "tow").ok) and not bool(Salvage.strip_good(c, invented_id, "fuel", 0.1).ok) and c.state == invented_snap, "an invented custody refuses and keeps the raw record")
	reset()
	var overflow: Dictionary = record_source(make_physical("src-overflow"), "battle:overflow")
	var harbor: Dictionary = c.port(str(c.state.lastPort))
	harbor.householdPurse = 9223372036854775807
	Salvage.ensure(c.state)
	var purse_snap: Dictionary = c.state.duplicate(true)
	check(not bool(Salvage.recover(c, str(overflow.id), "tow").ok) and c.state == purse_snap, "a purse that cannot hold the tug wage leaves the career")
	reset()
	var crowded_yard: Dictionary = record_source(make_physical("src-yard-max"), "battle:yard-max")
	harbor = c.port(str(c.state.lastPort))
	harbor.workers = 9223372036854775807
	harbor.availableWorkers = 10
	harbor.availableSpecialists = 10
	Salvage.ensure(c.state)
	var yard_snap: Dictionary = c.state.duplicate(true)
	check(not bool(Salvage.recover(c, str(crowded_yard.id), "tow").ok) and c.state == yard_snap, "a workforce counter that would overflow leaves the career")

func gear_disabled(boat: Dictionary) -> bool:
	if boat.is_empty() or not boat.get("moduleCondition") is Dictionary:
		return false
	var items: Dictionary = boat.moduleCondition.get("items", {})
	var locker = boat.get("refitLocker", {})
	if items.is_empty() or not locker is Dictionary or not locker.is_empty() or not is_equal_approx(float(boat.get("engine", 1.0)), 0.0):
		return false
	for key in items:
		var item: Dictionary = items[key]
		if str(item.get("location", "")) == "locker" or not is_equal_approx(float(item.get("hp", 1.0)), 0.0) or str(item.get("status", "")) != "disabled" or str(item.get("cause", "")) != "Legacy wreck recovery":
			return false
	return true

func gear_stamp(boat: Dictionary) -> String:
	var rows: Array = []
	for key in boat.moduleCondition.items:
		var item: Dictionary = boat.moduleCondition.items[key]
		rows.append("%s|%s|%s|%s" % [str(item.itemUid), str(item.hp), str(item.status), str(item.cause)])
	rows.sort()
	return "%s#%d#%s" % [str(boat.moduleCondition.birthNamespace), int(boat.moduleCondition.nextItemSeq), "|".join(rows)]

func legacy_wreck() -> void:
	reset()
	var spec: Dictionary = c.hull("harbor_sloop")
	var ship: Dictionary = Damage.create_ship(spec, {"fuel": 4.0, "ammo": 0.0, "supplies": 1.0})
	ship.team = "player"
	ship.sunk = true
	ship.uid = "legacy-hull"
	ship.id = "legacy-hull"
	var made: Array = Salvage.record_battle(c, {"ships": [ship]}, "battle:legacy")
	check(made.size() == 1 and not made[0].has("sourceModuleCondition"), "an old hull without a physical record stays on the legacy wreck")
	var wreck: Dictionary = Salvage.find_wreck(c.state, str(made[0].id))
	var wanted: Dictionary = wreck.get("sourceLoadout", {}) if wreck.get("sourceLoadout") is Dictionary else {}
	var towed: Dictionary = Salvage.recover(c, str(wreck.id), "tow")
	var boat: Dictionary = c.find_boat(str(towed.get("boatUid", "")))
	var gun: Dictionary = item_at(boat.moduleCondition, "mount0") if boat.has("moduleCondition") else {}
	var engine: Dictionary = item_at(boat.moduleCondition, "engine") if boat.has("moduleCondition") else {}
	check(bool(towed.ok) and gear_disabled(boat) and bool(boat.get("needsHarborRepair", false)) and bool(boat.get("supportOnly", false)) and not bool(boat.get("captureSecured", false)), "a legacy tow returns disabled installed gear at 0 hp and no locker, and stays support-only")
	check(not boat.is_empty() and is_equal_approx(float(boat.hp), float(boat.maxHp) * 0.35) and float(boat.crew) == 0.0 and float(boat.fuel) == 0.0 and float(boat.ammo) == 0.0 and float(boat.supplies) == 0.0, "a legacy tow is still damaged, uncrewed and empty")
	var weapon_id := ""
	if wanted.get("weapons") is Array and not wanted.weapons.is_empty():
		weapon_id = str(wanted.weapons[0])
	check(weapon_id != "" and str(gun.get("typeId", "")) == weapon_id and str(engine.get("typeId", "")) == str(wanted.get("engine", "")), "a legacy tow keeps the wreck loadout types")
	var stamp := gear_stamp(boat) if boat.has("moduleCondition") else ""
	var hull_hp := float(boat.get("hp", -1.0))
	var uid := str(boat.get("uid", ""))
	var text := JSON.stringify(c.state)
	var checked: Dictionary = SaveValidation.validate(JSON.parse_string(text), c.data)
	var saved: Dictionary = {}
	if bool(checked.get("ok", false)):
		for entry in checked.state.get("fleet", []):
			if entry is Dictionary and str(entry.get("uid", "")) == uid:
				saved = entry
	check(bool(checked.get("ok", false)) and gear_disabled(saved) and gear_stamp(saved) == stamp and is_equal_approx(float(saved.get("hp", -1.0)), hull_hp) and bool(saved.get("supportOnly", false)) and not bool(saved.get("captureSecured", false)), "SaveValidation keeps the new uids, hp, cause, counter, and 35% hull: " + str(checked.get("message", "")))
	var reloaded: Dictionary = c.restore(JSON.parse_string(text))
	boat = c.find_boat(uid)
	check(bool(reloaded.get("ok", false)) and gear_disabled(boat) and gear_stamp(boat) == stamp and is_equal_approx(float(boat.get("hp", -2.0)), hull_hp) and bool(boat.get("supportOnly", false)) and not bool(boat.get("captureSecured", false)), "Campaign.restore does not heal the legacy recovery: " + str(reloaded.get("message", "")))
	var harbor: Dictionary = c.current_port()
	if harbor.is_empty():
		harbor = c.port(str(c.state.lastPort))
	if not harbor.get("stocks") is Dictionary:
		harbor["stocks"] = {}
	harbor.workforce = int(harbor.get("workforce", 0)) + 800
	harbor.availableWorkers = int(harbor.get("availableWorkers", 0)) + 400
	harbor.specialists = int(harbor.get("specialists", 0)) + 200
	harbor.availableSpecialists = int(harbor.get("availableSpecialists", harbor.get("specialistWorkers", 0))) + 120
	for good in ["iron", "copper", "timber", "supplies"]:
		harbor.stocks[good] = maxf(float(harbor.stocks.get(good, 0.0)), 8000.0)
	var quote: Dictionary = EquipmentService.service_quote(c, boat, harbor)
	var coins: int = int(c.state.coins)
	var bill: int = int(quote.get("cost", 0))
	check(bool(quote.get("ok", false)) and float(quote.get("material", 0.0)) > 0.0 and int(quote.get("ordinary", 0)) + int(quote.get("expert", 0)) > 0 and int(quote.get("materials", 0)) > 0 and bill == int(quote.get("materials", 0)) + int(quote.get("ordinary", 0)) + int(quote.get("expert", 0)) + int(quote.get("fee", 0)) and int(quote.get("disabledCount", 0)) > 0, "harbor service quotes materials, labor, and coins for the disabled deficit: " + str(quote.get("error", quote.get("message", ""))))
	var paid: Dictionary = EquipmentService.repair(c, uid)
	var restored_ok := boat.has("moduleCondition")
	if restored_ok:
		for key in boat.moduleCondition.items:
			var item: Dictionary = boat.moduleCondition.items[key]
			if str(item.get("location", "")) == "locker":
				restored_ok = false
			elif stamp.find(str(item.get("itemUid", ""))) < 0 or not is_equal_approx(float(item.get("hp", 0.0)), 1.0) or str(item.get("status", "")) != "ok":
				restored_ok = false
	check(bool(paid.get("ok", false)) and int(paid.get("cost", -1)) == bill and int(c.state.coins) == coins - bill and Money.total(c.state) == int(c.state.coinSupply) and restored_ok and is_equal_approx(float(boat.get("engine", 0.0)), 1.0) and not bool(boat.get("needsHarborRepair", true)) and bool(boat.get("supportOnly", false)) and not bool(boat.get("captureSecured", false)), "paid harbor restore rehabilitates the same parts for the quoted bill and leaves the support role for the player: " + str(paid.get("message", "")))
	var toggled: Dictionary = FleetSupport.reserve(c, uid)
	boat = c.find_boat(uid)
	check(bool(toggled.get("ok", false)) and not bool(boat.get("supportOnly", true)) and str(toggled.get("message", "")) == "Boat available for the next 300-point battle deployment.", "after paid repair FleetSupport.reserve permits the combat role: " + str(toggled.get("message", "")))
	reset()
	var site: Dictionary = Salvage.seed_site_wreck(c, {"id": "old_wreck", "x": 1200.0, "y": 900.0}, "tin_skiff")
	check(not site.is_empty() and not site.has("sourceModuleCondition"), "a seeded site wreck does not gain a physical record")
	var site_tow: Dictionary = Salvage.recover(c, str(site.get("id", "")), "tow")
	var site_boat: Dictionary = c.find_boat(str(site_tow.get("boatUid", "")))
	check(bool(site_tow.get("ok", false)) and gear_disabled(site_boat) and is_equal_approx(float(site_boat.get("hp", -1.0)), float(site_boat.get("maxHp", 1.0)) * 0.35) and bool(site_boat.get("supportOnly", false)) and not bool(site_boat.get("captureSecured", false)), "a site wreck tow installs the same disabled gear and stays support-only")

## Appended to the unchanged corrected fixture after its original cases.
func root_atomic_refusal(wreck: Dictionary, label: String) -> void:
	check(not wreck.is_empty(), label + " has a real physical wreck")
	if wreck.is_empty():
		return
	var before: Dictionary = c.state.duplicate(true)
	var quote: Dictionary = Salvage.quote(c, str(wreck.id), "tow")
	check(not bool(quote.get("ok", false)), label + " quote refuses")
	check(c.state == before, label + " quote preserves the entire career")
	var result: Dictionary = Salvage.recover(c, str(wreck.id), "tow")
	check(not bool(result.get("ok", false)), label + " tow refuses")
	check(c.state == before, label + " tow preserves the entire career and raw evidence")
	print("ROOT RECOVERY " + label + " quote=" + str(quote.get("message", "")) + " result=" + str(result.get("message", "")))

func root_funded_wreck(label: String) -> Dictionary:
	reset()
	check(int(c.state.coinSupply) == Money.total(c.state), label + " starts with a reconciled funded ledger")
	return record_source(make_physical("root-" + label), "root-encounter-" + label)

func root_findings() -> void:
	# Reserve real funded construction work through the actual public day API.
	# Three total tug workers INCLUDE the one inspector; do not reserve four.
	for expert_only: bool in [false, true]:
		var label: String = "reserved-expert" if expert_only else "reserved-workers"
		var wreck: Dictionary = root_funded_wreck(label)
		var harbor: Dictionary = c.port(str(c.state.lastPort))
		harbor.availableWorkers = 20 if expert_only else 3
		harbor.availableSpecialists = 1
		Construction.begin_day(harbor)
		var spec: Dictionary = c.hull("tin_skiff")
		var order: Dictionary = Construction.make_order(spec, Construction.quote(spec), "player")
		var escrow: int = int(order.escrow)
		order.escrow = 0
		check(Money.move(c.state, "coins", order, "escrow", escrow, "Root QA real construction escrow", c.state.moneyLog), label + " really funds the construction order")
		harbor.buildQueue.append(order)
		var funded_total: int = Money.total(c.state)
		var advanced: Dictionary = Construction.advance(harbor, order, 1.0)
		check(bool(advanced.get("ok", false)) and float(advanced.get("workedDays", 0)) > 0.0, label + " actual construction did paid work")
		check(Money.total(c.state) == funded_total and funded_total == int(c.state.coinSupply), label + " construction wages preserve the ledger")
		var workforce: Dictionary = Refit._workforce(harbor)
		check(float(workforce.freeExperts) < 1.0 if expert_only else float(workforce.free) < 3.0, label + " remaining capacity is genuinely insufficient")
		check(int(harbor.availableWorkers) >= 3 and int(harbor.availableSpecialists) >= 1, label + " raw counts alone still look sufficient")
		root_atomic_refusal(wreck, label)
	# Every other field remains a funded, readable career. Preserve each malformed
	# field verbatim; a denial must not discard a bad log or repair a global ledger.
	for label: String in ["log-dictionary", "log-row", "unbalanced-supply", "fractional-coins", "boolean-coins", "overbound-int", "overbound-float"]:
		var wreck: Dictionary = root_funded_wreck(label)
		match label:
			"log-dictionary": c.state.moneyLog = {"unparsed": "must remain raw"}
			"log-row": c.state.moneyLog = [17]
			"unbalanced-supply": c.state.coinSupply = int(c.state.coinSupply) + 1
			"fractional-coins": c.state.coins = float(c.state.coins) + 0.5
			"boolean-coins": c.state.coins = true
			"overbound-int":
				c.state.coins = 9007199254740992
				c.state.coinSupply = Money.total(c.state)
			"overbound-float":
				c.state.coins = 9007199254740992.0
				c.state.coinSupply = Money.total(c.state)
		root_atomic_refusal(wreck, label)
	# An OTHER legacy boat with foreign owner metadata cannot be skipped as though
	# it proved global physical-item uniqueness. Retired markers stay legal in the
	# original fixture and are not removed here.
	for key: String in ["moduleConditions", "equipmentState"]:
		var wreck: Dictionary = root_funded_wreck("foreign-" + key)
		var other: Dictionary = {"uid": "legacy-foreign-" + key, "type": "tin_skiff", "engine": 1.0, "sunk": false}
		c.state.fleet.append(other)
		check(not other.has("moduleCondition"), "foreign other owner starts as an actual legacy boat")
		other[key] = {"opaque": "must remain raw"}
		check(Condition._foreign(other), key + " is genuinely foreign owner metadata")
		var before: Dictionary = c.state.duplicate(true)
		check(not bool(Recovery.registry(c.state, "", "").get("ok", false)), key + " global registry refuses unreadable other owner")
		check(c.state == before, key + " registry is entirely read-only")
		root_atomic_refusal(wreck, "foreign-" + key)

func journal_rows() -> void:
	reset()
	journal_branch("canonical", record_source(make_physical("journal-canonical"), "battle:journal-canonical"), true)
	reset()
	var spec: Dictionary = c.hull("harbor_sloop")
	var ship: Dictionary = Damage.create_ship(spec, {"fuel": 4.0, "ammo": 0.0, "supplies": 1.0})
	ship.team = "player"
	ship.sunk = true
	ship.uid = "legacy-journal"
	ship.id = "legacy-journal"
	var made: Array = Salvage.record_battle(c, {"ships": [ship]}, "battle:journal-legacy")
	var legacy: Dictionary = {} if made.is_empty() else Salvage.find_wreck(c.state, str(made[0].id))
	journal_branch("legacy", legacy, false)

func journal_branch(label: String, wreck: Dictionary, physical: bool) -> void:
	check(not wreck.is_empty() and wreck.has("sourceModuleCondition") == physical, label + " wreck is on the expected tow branch")
	if wreck.is_empty() or wreck.has("sourceModuleCondition") != physical:
		return
	var gun_uid := ""
	if physical:
		gun_uid = str(item_at(wreck.sourceModuleCondition, "mount0").get("itemUid", ""))
	c.state.moneyLog.append({"cash": 1, "reason": "fake"})
	var before: Dictionary = c.state.duplicate(true)
	var harbor: Dictionary = c.port(str(c.state.lastPort))
	var coins: int = int(c.state.coins)
	var workers: int = int(harbor.availableWorkers)
	var specialists: int = int(harbor.get("availableSpecialists", harbor.get("specialistWorkers", 0)))
	var fleet: int = c.state.fleet.size()
	var refused: Dictionary = Salvage.recover(c, str(wreck.id), "tow")
	check(not bool(refused.get("ok", false)) and str(refused.get("message", "")) == "Payment journal endpoints are unreadable; no payment was made.", label + " malformed journal row refuses before payment")
	check(c.state == before and int(c.state.coins) == coins and int(c.state.coinSupply) == int(before.coinSupply) and int(harbor.availableWorkers) == workers and int(harbor.get("availableSpecialists", harbor.get("specialistWorkers", 0))) == specialists and c.state.fleet.size() == fleet, label + " refusal leaves coins, workers, uids, and part hp unchanged")
	c.state.moneyLog.remove_at(c.state.moneyLog.size() - 1)
	c.state.moneyLog.append({"cash": 1, "reason": HISTORICAL_COMMISSION})
	var accepted: Dictionary = Salvage.recover(c, str(wreck.id), "tow")
	var boat: Dictionary = c.find_boat(str(accepted.get("boatUid", "")))
	var historical := false
	for entry in c.state.moneyLog:
		if entry is Dictionary and entry.size() == 2 and str(entry.get("reason", "")) == HISTORICAL_COMMISSION and int(entry.get("cash", 0)) == 1:
			historical = true
	check(bool(accepted.get("ok", false)) and historical and not boat.is_empty() and int(c.state.coins) < coins and int(harbor.availableWorkers) == workers - 3, label + " exact historical commission receipt is still accepted and paid")
	if boat.is_empty():
		return
	if physical:
		var gun: Dictionary = item_at(boat.moduleCondition, "mount0") if boat.has("moduleCondition") else {}
		check(boat.has("moduleCondition") and str(gun.get("itemUid", "")) == gun_uid and is_equal_approx(float(gun.get("hp", -1.0)), 0.25) and is_equal_approx(float(boat.hp), float(boat.maxHp) * 0.35) and bool(boat.get("supportOnly", false)) and not bool(boat.get("captureSecured", false)), label + " accepted tow keeps the wreck part uid, part hp, 0.35 hull, and support-only role")
	else:
		check(gear_disabled(boat) and is_equal_approx(float(boat.hp), float(boat.maxHp) * 0.35) and float(boat.crew) == 0.0 and float(boat.fuel) == 0.0 and float(boat.ammo) == 0.0 and float(boat.supplies) == 0.0 and bool(boat.get("supportOnly", false)) and not bool(boat.get("captureSecured", false)), label + " accepted legacy tow installs disabled gear at 0 hp, with no crew, fuel, ammo, or kits, and stays support-only")

func r3_edges() -> void:
	reset()
	var sample: Dictionary = record_source(make_physical("r3-empty"), "battle:r3-empty")
	if sample.is_empty():
		return
	sample.sourceLoadout = {}
	var quiet: Dictionary = c.state.duplicate(true)
	var quoted: Dictionary = Salvage.quote(c, str(sample.id), "tow")
	check(bool(quoted.get("ok", false)) and is_equal_approx(float(quoted.recoveredHp), float(quoted.fittedMaxHp) * 0.35) and c.state == quiet, "an empty wreck loadout keeps the fitted 0.35 contract")
	r3_refuse("dict", true, "dict")
	r3_refuse("typed", true, "typed")
	r3_refuse("status", true, "status")
	r3_refuse("cursor", true, "cursor")
	r3_refuse("birth", true, "birth")
	r3_refuse("legacy-cursor", false, "cursor")
	r3_refuse("legacy-birth", false, "birth")

func r3_refuse(label: String, physical: bool, kind: String) -> void:
	reset()
	var wreck: Dictionary = {}
	if physical:
		wreck = record_source(make_physical("r3-" + label), "battle:r3-" + label)
	else:
		var spec: Dictionary = c.hull("harbor_sloop")
		var ship: Dictionary = Damage.create_ship(spec, {"fuel": 4.0, "ammo": 0.0, "supplies": 1.0})
		ship.team = "player"
		ship.sunk = true
		ship.uid = "legacy-r3-" + label
		ship.id = ship.uid
		var made: Array = Salvage.record_battle(c, {"ships": [ship]}, "battle:r3-" + label)
		wreck = {} if made.is_empty() else Salvage.find_wreck(c.state, str(made[0].id))
	check(not wreck.is_empty() and wreck.has("sourceModuleCondition") == physical, label + " wreck is on the expected branch")
	if wreck.is_empty() or wreck.has("sourceModuleCondition") != physical:
		return
	var expect := "Preserved loadout is unreadable."
	if kind == "dict":
		wreck.sourceLoadout = {"weapons": "nope"}
	elif kind == "typed":
		wreck.sourceLoadout = "nope"
		expect = "Wreck loadout is unreadable."
	elif kind == "status":
		wreck.status = "floating"
		expect = "Wreck status is not a salvage settlement."
	elif kind == "cursor":
		c.state.nextUid = 1
		expect = "Two hulls share one uid."
	elif kind == "birth":
		c.state.nextUid = 80
		c.state.fleet.append({"uid": "held-birth-" + label, "type": "tin_skiff", "sunk": false, "moduleCondition": {"birthNamespace": "boat-80"}})
		expect = "Two owners share one birth namespace."
	var before: Dictionary = c.state.duplicate(true)
	var harbor: Dictionary = c.port(str(c.state.lastPort))
	var coins: int = int(c.state.coins)
	var supply: int = int(c.state.coinSupply)
	var workers: int = int(harbor.availableWorkers)
	var specialists: int = int(harbor.get("availableSpecialists", harbor.get("specialistWorkers", 0)))
	var refused: Dictionary = Salvage.recover(c, str(wreck.id), "tow")
	var raw_kept := true
	if kind == "dict":
		raw_kept = wreck.get("sourceLoadout") is Dictionary and str(wreck.sourceLoadout.get("weapons", "")) == "nope"
	elif kind == "typed":
		raw_kept = wreck.get("sourceLoadout") is String and str(wreck.sourceLoadout) == "nope"
	elif kind == "status":
		raw_kept = str(wreck.get("status", "")) == "floating"
	check(not bool(refused.get("ok", false)) and str(refused.get("message", "")) == expect and c.state == before and raw_kept and int(c.state.coins) == coins and int(c.state.coinSupply) == supply and int(harbor.availableWorkers) == workers and int(harbor.get("availableSpecialists", harbor.get("specialistWorkers", 0))) == specialists, label + " recover refuses and leaves coins, workers, parts, and raw fields unchanged")
