extends SceneTree
## Unrun native fixture: final store-only strip_good keeps active wreck custody
## and unclaimed status so the hull and physical equipment can still be paid-towed.

const Campaign = preload("res://scripts/campaign.gd")
const Salvage = preload("res://scripts/salvage.gd")
const Recovery = preload("res://scripts/equipment_recovery.gd")
const Preflight = preload("res://scripts/equipment_campaign.gd")
const Condition = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Refit = preload("res://scripts/refit.gd")
const Damage = preload("res://scripts/damage.gd")
const Money = preload("res://scripts/money.gd")

var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL strip_custody: " + message)

func item_at(condition: Dictionary, location: String) -> Dictionary:
	for key in condition.get("items", {}).keys():
		var item: Dictionary = condition.items[key]
		if str(item.get("location", "")) == location:
			return item
	return {}

func same_parts(saved: Dictionary, live: Dictionary) -> bool:
	if str(live.get("birthNamespace", "")) != str(saved.get("birthNamespace", "")) or int(live.get("nextItemSeq", -1)) != int(saved.get("nextItemSeq", -2)):
		return false
	var saved_items: Dictionary = saved.get("items", {})
	var live_items: Dictionary = live.get("items", {})
	if live_items.size() != saved_items.size():
		return false
	for key in saved_items.keys():
		if not live_items.has(key):
			return false
		var a: Dictionary = saved_items[key]
		var b: Dictionary = live_items[key]
		if str(a.get("itemUid", "")) != str(b.get("itemUid", "")) or str(a.get("typeId", "")) != str(b.get("typeId", "")) or str(a.get("originHullType", "")) != str(b.get("originHullType", "")):
			return false
		if str(a.get("location", "")) != str(b.get("location", "")) or str(a.get("status", "")) != str(b.get("status", "")) or str(a.get("cause", "")) != str(b.get("cause", "")):
			return false
		if not is_equal_approx(float(a.get("hp", -1.0)), float(b.get("hp", -2.0))):
			return false
	return true

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		print("FAIL strip_custody: fixture is headless only")
		quit(1)
		return
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var c = Campaign.new(world)
	c.new_game(31)

	var spec: Dictionary = c.hull("tin_skiff")
	var source: Dictionary = Damage.create_ship(spec, {"fuel": 3.0, "ammo": 0.0, "supplies": 0.0, "crew": 0.0})
	source.uid = "src-store-only"
	source.id = "src-store-only"
	source.team = "enemy"
	source.engine = 1.0
	source.x = float(c.state.position.x)
	source.y = float(c.state.position.y)
	c.fit_boat(source, true)
	var seeded: Dictionary = Records.initialize(source, {
		"base": source.baseSpec,
		"loadout": source.loadout,
		"catalog": Refit.catalog(),
		"identity": "src-store-only",
		"knownUids": []
	})
	check(bool(seeded.get("ok", false)), "source hull equipment seeded")
	var gun: Dictionary = item_at(source.moduleCondition, "mount0")
	var eng: Dictionary = item_at(source.moduleCondition, "engine")
	check(bool(Condition.apply_component_damage(source.moduleCondition, {"itemUid": str(gun.get("itemUid", "")), "loss": 0.75, "cause": "Shell splinter"}).get("ok", false)), "mount0 damaged to 0.25")
	check(bool(Condition.apply_component_damage(source.moduleCondition, {"itemUid": str(eng.get("itemUid", "")), "loss": 0.75, "cause": "Flooded engine"}).get("ok", false)), "engine damaged to 0.25")
	var spare: Dictionary = Condition.accept_acquired_item(source.moduleCondition, {
		"acquired": true,
		"family": "weapons",
		"typeId": "rapid_gun",
		"originHullType": "tin_skiff",
		"location": "locker",
		"hp": 0.40,
		"cause": "Cracked breech",
		"mountCount": Refit.hardpoints(source.baseSpec).size(),
		"hullType": "tin_skiff",
		"knownUids": []
	})
	check(bool(spare.get("ok", false)), "locker spare recorded")
	source.engine = 0.10
	source.sunk = true

	var made: Array = Salvage.record_battle(c, {"ships": [source], "wrecks": [{"id": source.id, "uid": source.uid, "cause": "flooding"}]}, "battle:store-only-custody")
	check(made.size() == 1 and not source.has("moduleCondition") and str(source.get("equipmentRetiredTo", "")) == str(made[0].id), "battle wreck recorded and source hull retired to wreck")
	var wreck_id: String = str(made[0].id)
	var wreck: Dictionary = Salvage.find_wreck(c.state, wreck_id)
	wreck.components = {}
	var parsed = JSON.parse_string(JSON.stringify(c.state))
	check(parsed is Dictionary, "canonical snapshot roundtrips JSON")
	c.state = parsed
	Salvage.ensure(c.state)
	wreck = Salvage.find_wreck(c.state, wreck_id)

	var preflight_before: Dictionary = Preflight.check_state(c.state, c.data)
	check(bool(preflight_before.get("ok", false)) and bool(preflight_before.get("ready", false)), "Preflight.check_state is valid and ready before strip_good")
	check(is_equal_approx(float(wreck.stores.get("fuel", 0.0)), 3.0) and wreck.components.is_empty(), "wreck has only finite 3.0 fuel store lot remaining")
	check(Recovery.refusal(wreck).is_empty() and Recovery.is_active(wreck), "wreck custody is active and refusal is empty before strip_good")

	var saved_mc: Dictionary = wreck.sourceModuleCondition.duplicate(true)
	var saved_uids: Array = Condition._uid_list(saved_mc)
	var saved_birth: String = str(saved_mc.birthNamespace)
	var saved_seq: int = int(saved_mc.nextItemSeq)
	var holders_before: Array = Recovery.active_holders(c.state).get("holders", [])
	var free_before: float = c.capacity() - c.cargo_weight()
	var fuel_before: float = float(c.state.cargo.get("fuel", 0.0))
	check(free_before >= 3.0, "real traveling hold has free capacity for 3.0 fuel drums")

	var stripped: Dictionary = Salvage.strip_good(c, wreck_id, "fuel", 3.0)
	check(bool(stripped.get("ok", false)) and is_equal_approx(float(stripped.get("weight", 0.0)), 3.0), "strip_good removes the final 3.0 fuel lot")
	check(is_equal_approx(float(c.state.cargo.get("fuel", 0.0)), fuel_before + 3.0) and is_equal_approx(c.capacity() - c.cargo_weight(), free_before - 3.0), "hold cargo and free capacity reflect the 3.0 fuel drums")

	wreck = Salvage.find_wreck(c.state, wreck_id)
	check(wreck.stores.is_empty() or is_equal_approx(float(wreck.stores.get("fuel", 0.0)), 0.0), "wreck stores are now empty")
	check(wreck.components.is_empty() and Salvage.quote(c, wreck_id, Salvage.MODE_STRIP).get("items", {}).is_empty(), "no commodity lots remain on the wreck")
	check(str(wreck.status) == Salvage.STATUS_UNCLAIMED and str(wreck.claimedMode) == "" and not bool(wreck.get("hullStripped", false)), "wreck status stays unclaimed and hullStripped stays false")
	check(str(wreck.equipmentCustody) == "wreck" and Recovery.refusal(wreck).is_empty() and Recovery.is_active(wreck), "wreck custody stays active and Recovery.refusal stays empty")
	check(wreck.has("sourceModuleCondition") and same_parts(saved_mc, wreck.sourceModuleCondition), "sourceModuleCondition parts, damage, and causes are unchanged")
	check(Condition._uid_list(wreck.sourceModuleCondition) == saved_uids and str(wreck.sourceModuleCondition.birthNamespace) == saved_birth and int(wreck.sourceModuleCondition.nextItemSeq) == saved_seq, "itemUids, birthNamespace, and nextItemSeq are unchanged")
	check(Recovery.active_holders(c.state).get("holders", []).size() == holders_before.size(), "active holder count is unchanged after store-only depletion")
	var preflight_mid: Dictionary = Preflight.check_state(c.state, c.data)
	check(bool(preflight_mid.get("ok", false)) and bool(preflight_mid.get("ready", false)), "Preflight.check_state remains valid after final store lot strip_good")

	var harbor: Dictionary = c.port(str(c.state.lastPort))
	var total_before: int = Money.total(c.state)
	var coins_before: int = int(c.state.coins)
	var household_before: int = int(harbor.householdPurse)
	var expert_before: int = int(harbor.expertPurse)
	var cash_before: int = int(harbor.cash)
	var workers_before: int = int(harbor.availableWorkers)
	var specialists_before: int = int(harbor.get("availableSpecialists", harbor.get("specialistWorkers", 0)))
	var yard_before: int = int(harbor.get("workers", 0))
	var fleet_before: int = c.state.fleet.size()

	var tow_quote: Dictionary = Salvage.quote(c, wreck_id, Salvage.MODE_TOW)
	check(bool(tow_quote.get("ok", false)) and is_equal_approx(float(tow_quote.get("recoveredHp", 0.0)), float(tow_quote.get("fittedMaxHp", 0.0)) * Salvage.TOW_HP_FRACTION), "tow quote succeeds with fitted 35% HP contract")
	var towed: Dictionary = Salvage.recover(c, wreck_id, Salvage.MODE_TOW)
	check(bool(towed.get("ok", false)), "paid tow succeeds after final store lot was stripped")
	check(Money.total(c.state) == total_before and int(c.state.coinSupply) == total_before, "world coin supply is conserved across paid tow")
	check(int(c.state.coins) == coins_before - int(tow_quote.total), "company purse pays exact quoted tow total")
	check(int(harbor.householdPurse) == household_before + int(tow_quote.ordinary) and int(harbor.expertPurse) == expert_before + int(tow_quote.expert) and int(harbor.cash) == cash_before + int(tow_quote.fee), "harbor purses receive exact tug wages, inspection, and company fee")
	check(int(harbor.availableWorkers) == workers_before - 3 and int(harbor.get("workers", 0)) == yard_before + 3 and int(harbor.get("availableSpecialists", harbor.get("specialistWorkers", 0))) == specialists_before - 1, "finite harbor workers and specialist are booked once")
	check(c.state.fleet.size() == fleet_before + 1, "paid tow adds one hull to player fleet")

	var boat: Dictionary = c.find_boat(str(towed.get("boatUid", "")))
	check(not boat.is_empty() and boat.has("moduleCondition") and same_parts(saved_mc, boat.moduleCondition), "towed boat receives exact preserved moduleCondition without healing")
	check(Condition._uid_list(boat.moduleCondition) == saved_uids and str(boat.moduleCondition.birthNamespace) == saved_birth and int(boat.moduleCondition.nextItemSeq) == saved_seq, "towed boat preserves itemUids, birthNamespace, and nextItemSeq")
	check(is_equal_approx(float(boat.engine), 0.10) and is_equal_approx(float(item_at(boat.moduleCondition, "mount0").get("hp", 0.0)), 0.25) and is_equal_approx(float(item_at(boat.moduleCondition, "locker").get("hp", 0.0)), 0.40), "installed engine, damaged mount0, and locker spare keep exact condition")
	check(is_equal_approx(float(boat.hp), float(boat.maxHp) * Salvage.TOW_HP_FRACTION) and is_equal_approx(float(boat.hp), float(tow_quote.recoveredHp)), "towed boat hull HP matches fitted 35% contract")
	check(float(boat.crew) == 0.0 and float(boat.fuel) == 0.0 and float(boat.ammo) == 0.0 and float(boat.supplies) == 0.0, "towed boat has zero crew, fuel, ammo, and supplies")

	wreck = Salvage.find_wreck(c.state, wreck_id)
	check(str(wreck.status) == Salvage.STATUS_TOWED and str(wreck.claimedMode) == Salvage.MODE_TOW and not wreck.has("sourceModuleCondition") and str(wreck.equipmentCustody) == "transferred" and wreck.get("transferredItemUids", []) == saved_uids, "wreck releases custody once to transferred and records transferredItemUids")
	var holders_after: Array = Recovery.active_holders(c.state).get("holders", [])
	var boat_held := false
	var wreck_held := false
	for h in holders_after:
		if str(h.get("id", "")) == str(boat.uid):
			boat_held = true
		if str(h.get("id", "")) == wreck_id:
			wreck_held = true
	check(holders_after.size() == holders_before.size() and boat_held and not wreck_held and bool(Recovery.registry(c.state, "", null).get("ok", false)), "single custody transfer from wreck to recovered boat")
	var preflight_after: Dictionary = Preflight.check_state(c.state, c.data)
	check(bool(preflight_after.get("ok", false)) and bool(preflight_after.get("ready", false)), "Preflight.check_state remains valid after paid tow")
	var post_tow_snap: Dictionary = c.state.duplicate(true)
	check(not bool(Salvage.recover(c, wreck_id, Salvage.MODE_TOW).get("ok", false)) and not bool(Salvage.strip_good(c, wreck_id, "fuel", 1.0).get("ok", false)) and c.state == post_tow_snap, "settled wreck refuses repeat tow or strip without mutating state")

	print("StripCustody: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
