extends SceneTree
## v0.031 native fixture for paid harbor equipment service quotes and atomic restoration.

const Campaign = preload("res://scripts/campaign.gd")
const Harbor = preload("res://scripts/harbor.gd")
const EquipmentService = preload("res://scripts/equipment_service.gd")
const Core = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Damage = preload("res://scripts/damage.gd")
const Refit = preload("res://scripts/refit.gd")
const Economy = preload("res://scripts/economy.gd")
const OwnerService = preload("res://scripts/equipment_owner_service.gd")
const Money = preload("res://scripts/money.gd")
const EPS: float = 0.0001

var world: Dictionary = {}
var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
		print("FAIL: " + label)

func _approx(a: float, b: float, tol: float = 0.0005) -> bool:
	return absf(a - b) <= tol

func same(a, b) -> bool:
	return JSON.stringify(a) == JSON.stringify(b)

func _new_campaign(seed_val: int = 401):
	var c = Campaign.new(world.duplicate(true))
	c.new_game(seed_val)
	return c

func _fund_from_treasury(c, p: Dictionary, amount: int) -> void:
	Money.move(p, "governmentPurse", c.state, "coins", amount, "Fixture treasury advance", c.state.moneyLog)

func _seed_canonical_boat(c, boat: Dictionary, identity_override: String = "") -> Dictionary:
	var ident: String = str(boat.get("uid", "")) if identity_override.is_empty() else identity_override
	var base: Dictionary = c.hull(str(boat.get("type", "")))
	var norm: Dictionary = Refit.normalize(base, boat.get("loadout", Refit.defaults(base)))
	boat["loadout"] = norm.loadout
	return Records.initialize(boat, {
		"identity": ident,
		"base": base,
		"catalog": Refit.catalog(),
		"loadout": boat.loadout
	})

func _item_at(condition: Dictionary, location: String) -> Dictionary:
	var items: Dictionary = condition.get("items", {})
	for uid in items.keys():
		var item: Dictionary = items[uid]
		if str(item.get("location", "")) == location:
			return item
	return {}

func _damage_at(boat: Dictionary, location: String, loss: float, cause: String) -> Dictionary:
	var item: Dictionary = _item_at(boat.moduleCondition, location)
	var item_uid: String = str(item.get("itemUid", ""))
	return Core.apply_component_damage(boat.moduleCondition, {
		"itemUid": item_uid,
		"loss": loss,
		"cause": cause
	})

func _initialize() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	test_detached_quote_and_paid_canonical_harbor_repair()
	test_scalar_sync_and_persistence_through_status_and_initialize()
	test_captured_hull_birth_namespace_and_aliased_roster_dedup()
	test_atomic_refusals_leave_career_unchanged()
	test_legacy_without_schema_supported()
	test_malformed_payment_records_refuse_before_payment()
	test_commission_then_repair()
	print("equipment_service: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func test_detached_quote_and_paid_canonical_harbor_repair() -> void:
	var c = _new_campaign(401)
	var p: Dictionary = c.current_port()
	var boat: Dictionary = c.state.fleet[0]
	var base: Dictionary = c.hull(str(boat.get("type", "")))
	_fund_from_treasury(c, p, 6000)

	var init_res: Dictionary = _seed_canonical_boat(c, boat)
	check(bool(init_res.get("ok", false)) and boat.has("moduleCondition"), "Canonical physical equipment records initialize on active campaign boat")

	# Accept a damaged spare weapon in the boat's locker to verify loose spares are never quoted or restored.
	var stored_spare: Dictionary = Core.accept_acquired_item(boat.moduleCondition, {
		"acquired": true,
		"family": "weapons",
		"typeId": "rapid_gun",
		"originHullType": str(boat.get("type", "tin_skiff")),
		"location": "locker",
		"hp": 0.42,
		"cause": "salvaged_spare",
		"mountCount": Refit.hardpoints(base).size(),
		"hullType": str(base.get("id", "tin_skiff")),
		"knownUids": []
	})
	check(bool(stored_spare.get("ok", false)), "Damaged spare weapon accepted in canonical locker")
	var spare_uid: String = str(stored_spare.get("itemUid", ""))
	check(not spare_uid.is_empty() and boat.moduleCondition.items.has(spare_uid), "Locker spare has a valid canonical itemUid")
	check(bool(Records.publish(boat).get("ok", false)), "Publish canonical locker spare projection")

	# Damage all four installed canonical parts across weapons, engines (disabled), pumps, and armor.
	var m0_before: Dictionary = _item_at(boat.moduleCondition, "mount0")
	var eng_before: Dictionary = _item_at(boat.moduleCondition, "engine")
	var pump_before: Dictionary = _item_at(boat.moduleCondition, "pumps")
	var arm_before: Dictionary = _item_at(boat.moduleCondition, "armor")

	check(bool(_damage_at(boat, "mount0", 0.50, "shell").get("ok", false)), "Damage installed mount0 to 0.50")
	check(bool(_damage_at(boat, "engine", 0.80, "boiler_hit").get("ok", false)), "Disable installed engine at 0.20")
	check(bool(_damage_at(boat, "pumps", 0.40, "flooding_shock").get("ok", false)), "Damage installed integral pumps to 0.60")
	check(bool(_damage_at(boat, "armor", 0.30, "armor_spall").get("ok", false)), "Damage installed armor to 0.70")
	check(bool(Records.publish(boat).get("ok", false)), "Publish damaged canonical equipment state")

	boat.hp = float(boat.maxHp) - 24.0
	boat.breaches = [{"area": 20.0, "section": "bow"}]
	boat.water = 50.0
	boat.wounded = 1.0
	boat.fire = 8.0
	boat.supplies = 1.5
	var ammo_before: float = float(boat.ammo)
	var fuel_before: float = float(boat.fuel)
	var crew_before: float = float(boat.crew)

	var seq_before: int = int(boat.moduleCondition.get("nextItemSeq", 0))
	var snap_boat_before_quote: Dictionary = boat.duplicate(true)
	var snap_state_before_quote: Dictionary = c.state.duplicate(true)

	var q: Dictionary = Harbor.service_quote(c, boat, p)
	var q_via_campaign: Dictionary = c.service_quote(boat, p)
	check(bool(q.get("ok", false)) and same(q, q_via_campaign), "Harbor.service_quote and Campaign.service_quote succeed with identical quote")
	check(same(boat, snap_boat_before_quote) and same(c.state, snap_state_before_quote), "Harbor.service_quote runs on detached copy without mutating boat or campaign state")
	check(int(boat.moduleCondition.get("nextItemSeq", 0)) == seq_before, "Harbor.service_quote does not advance nextItemSeq")

	# Verify UI-compatible keys/types and no engine double-charge in hull kits/work.
	check(q.get("cost") is int and q.get("materials") is int and q.get("ordinary") is int and q.get("expert") is int and q.get("fee") is int, "Quote preserves integer coin fields (cost, materials, ordinary, expert, fee)")
	check(_approx(float(q.get("hullKits", -1.0)), 24.0 * 0.20 + 20.0 * 0.018), "Hull kit quote does not double-charge engine kits")
	check(_approx(float(q.get("hullExpertDays", -1.0)), 1.0 + 8.0 * 0.002), "Hull specialist labor quote does not double-charge engine labor")
	check(float(q.get("equipmentKits", 0.0)) > 0.0 and _approx(float(q.get("material", 0.0)), float(q.get("hullKits", 0.0)) + float(q.get("equipmentKits", 0.0))), "Total kit requirement equals hullKits + equipmentKits")
	check(_approx(float(q.get("own", 0.0)), 1.5) and _approx(float(q.get("purchase", 0.0)), float(q.get("material", 0.0)) - 1.5), "Onboard supplies are consumed before purchasing harbor repair kits")
	check(int(q.get("equipmentCount", 0)) == 4 and int(q.get("disabledCount", 0)) == 1, "Quote counts 4 damaged installed parts including 1 disabled engine and excludes locker spare")
	var deficits: Dictionary = q.get("equipmentDeficits", {})
	check(deficits.has("mount0") and deficits.has("engine") and deficits.has("pumps") and deficits.has("armor") and not deficits.has("locker"), "equipmentDeficits reports all 4 installed locations and never includes locker")
	check(bool(deficits.engine.get("disabled", false)) and _approx(float(deficits.engine.get("effort", 0.0)), 0.80 + EquipmentService.DISABLED_SURCHARGE), "Disabled engine includes teardown/re-alignment effort surcharge")
	var eq_mats: Dictionary = q.get("equipmentMaterials", {})
	check(float(eq_mats.get("iron", 0.0)) > 0.0 and float(eq_mats.get("copper", 0.0)) > 0.0 and float(eq_mats.get("timber", 0.0)) > 0.0, "Installed weapons/engine/pumps/armor restoration requires real iron, copper, and timber")
	check(int(q.get("materials", 0)) == int(q.get("kitPurchaseCost", 0)) + int(q.get("equipmentMaterialCost", 0)), "q.materials coin cost equals kitPurchaseCost + equipmentMaterialCost")
	check(int(q.get("cost", 0)) == int(q.get("materials", 0)) + int(q.get("ordinary", 0)) + int(q.get("expert", 0)) + int(q.get("fee", 0)), "q.cost equals materials + ordinary + expert + fee")

	var state_ref: Dictionary = c.state
	var boat_ref: Dictionary = c.state.fleet[0]
	var port_ref: Dictionary = c.current_port()
	var stocks_ref: Dictionary = p.stocks
	var coins_before: int = int(c.state.coins)
	var cash_before: int = int(p.cash)
	var house_before: int = int(p.householdPurse)
	var expert_before: int = int(p.expertPurse)
	var gov_before: int = int(p.governmentPurse)
	var stocks_before: Dictionary = p.stocks.duplicate(true)
	var used_workers_before: float = float(p.get("_yardWorkersUsed", 0.0))
	var used_spec_before: float = float(p.get("_yardSpecialistsUsed", 0.0))

	var rep: Dictionary = c.repair_boat(str(boat.uid))
	check(bool(rep.get("ok", false)), "Campaign.repair_boat / Harbor.repair succeeds on canonical damaged boat: " + str(rep.get("message", "")))
	check(rep.get("restoredIds") is Array and rep.restoredIds.size() == 4, "Harbor.repair reports 4 restored installed itemUids")
	check(is_same(c.state, state_ref) and is_same(c.state.fleet[0], boat_ref) and is_same(c.current_port(), port_ref) and is_same(c.current_port().stocks, stocks_ref), "Harbor.repair preserves live state, boat, port, and stocks dictionary references")
	check(Money.total(c.state) == int(c.state.coinSupply), "Harbor.repair conserves total world coins")
	check(int(c.state.coins) == coins_before - int(q.cost), "Captain pays exact quoted coin cost")
	check(int(p.cash) == cash_before + int(q.materials) + int(q.fee), "Harbor cash receives exact materials + fee coins")
	check(int(p.householdPurse) == house_before + int(q.ordinary), "Harbor householdPurse receives exact shipwright wages")
	check(int(p.expertPurse) == expert_before + int(q.expert), "Harbor expertPurse receives exact specialist wages")
	check(int(p.governmentPurse) == gov_before, "Harbor governmentPurse is untouched by drydock repair")

	check(_approx(float(boat.supplies), 0.0) and _approx(float(p.stocks.supplies), float(stocks_before.supplies) - float(q.purchase)), "Exact onboard and harbor repair kits consumed")
	for good in ["iron", "copper", "timber"]:
		var spent_good: float = float(eq_mats.get(good, 0.0))
		check(_approx(float(p.stocks[good]), float(stocks_before[good]) - spent_good), "Harbor %s stock reduced by exact equipment restoration bill" % good)

	check(_approx(float(p.get("_yardWorkersUsed", 0.0)), used_workers_before + float(q.workerDays)), "Yard worker reservation records exact total workerDays")
	check(_approx(float(p.get("_yardSpecialistsUsed", 0.0)), used_spec_before + float(q.expertDays)), "Yard specialist reservation records exact expertDays")

	# Verify all installed canonical items restored with identical itemUids and nextItemSeq.
	check(int(boat.moduleCondition.get("nextItemSeq", 0)) == seq_before, "Harbor.repair restores in place without advancing nextItemSeq")
	var m0_after: Dictionary = _item_at(boat.moduleCondition, "mount0")
	var eng_after: Dictionary = _item_at(boat.moduleCondition, "engine")
	var pump_after: Dictionary = _item_at(boat.moduleCondition, "pumps")
	var arm_after: Dictionary = _item_at(boat.moduleCondition, "armor")
	check(str(m0_after.get("itemUid", "")) == str(m0_before.get("itemUid", "")) and _approx(float(m0_after.get("hp", 0.0)), 1.0) and str(m0_after.get("status", "")) == "ok" and str(m0_after.get("cause", "x")) == "", "Installed mount0 restored to 1.0 ok with same itemUid")
	check(str(eng_after.get("itemUid", "")) == str(eng_before.get("itemUid", "")) and _approx(float(eng_after.get("hp", 0.0)), 1.0) and str(eng_after.get("status", "")) == "ok" and str(eng_after.get("cause", "x")) == "", "Installed engine restored from disabled to 1.0 ok with same itemUid")
	check(str(pump_after.get("itemUid", "")) == str(pump_before.get("itemUid", "")) and _approx(float(pump_after.get("hp", 0.0)), 1.0) and str(pump_after.get("status", "")) == "ok" and str(pump_after.get("cause", "x")) == "", "Installed integral pumps restored to 1.0 ok with same itemUid")
	check(str(arm_after.get("itemUid", "")) == str(arm_before.get("itemUid", "")) and _approx(float(arm_after.get("hp", 0.0)), 1.0) and str(arm_after.get("status", "")) == "ok" and str(arm_after.get("cause", "x")) == "", "Installed armor restored to 1.0 ok with same itemUid")

	# Verify damaged locker spare is untouched and ammo/fuel/crew are not refilled.
	var spare_after: Dictionary = boat.moduleCondition.items.get(spare_uid, {})
	check(str(spare_after.get("location", "")) == "locker" and _approx(float(spare_after.get("hp", 0.0)), 0.42) and str(spare_after.get("status", "")) == "damaged" and str(spare_after.get("cause", "")) == "salvaged_spare", "Damaged locker spare remains unchanged in locker after paid service")
	check(int(boat.get("refitLocker", {}).get("rapid_gun", 0)) == 1, "Projected refitLocker count preserves spare rapid_gun")
	check(_approx(float(boat.ammo), ammo_before) and _approx(float(boat.fuel), fuel_before) and _approx(float(boat.crew), crew_before), "Harbor.repair never refills ammo, fuel, or crew as a side effect")
	check(_approx(float(boat.hp), float(boat.maxHp)) and boat.breaches.is_empty() and _approx(float(boat.water), 0.0) and _approx(float(boat.fire), 0.0) and _approx(float(boat.wounded), 0.0) and _approx(float(boat.engine), 1.0), "Hull HP, breaches, water, fire, wounded, and projected engine scalar are fully restored")

func test_scalar_sync_and_persistence_through_status_and_initialize() -> void:
	var c = _new_campaign(402)
	var p: Dictionary = c.current_port()
	var boat: Dictionary = c.state.fleet[0]
	_fund_from_treasury(c, p, 5000)
	_seed_canonical_boat(c, boat)

	# Disable canonical engine to 0.20, then attempt an upward scalar-only write boat.engine = 1.0.
	check(bool(_damage_at(boat, "engine", 0.80, "shaft_snap").get("ok", false)), "Disable canonical engine to 0.20")
	Records.publish(boat)
	boat.engine = 1.0

	var st_before: Dictionary = Damage.get_status(boat)
	check(_approx(float(st_before.get("engineFactor", 1.0)), 0.0) and _approx(float(st_before.get("engineHp", 1.0)), 0.20) and _approx(float(_item_at(boat.moduleCondition, "engine").hp), 0.20) and _approx(float(boat.engine), 1.0), "Read-only status preserves scalar write while the actual canonical engine stays disabled at0.20")

	boat.engine = 1.0
	var q_upward: Dictionary = Harbor.service_quote(c, boat, p)
	check(bool(q_upward.get("ok", false)) and q_upward.get("equipmentDeficits", {}).has("engine") and bool(q_upward.equipmentDeficits.engine.get("disabled", false)), "Upward scalar write boat.engine=1.0 does not bypass engine restoration charge in Harbor.service_quote")

	# Paid harbor repair genuinely restores the canonical engine and persists through get_status and Records.initialize.
	var rep: Dictionary = Harbor.repair(c, str(boat.uid))
	check(bool(rep.get("ok", false)), "Paid Harbor.repair succeeds after upward scalar tamper")
	var st_after: Dictionary = Damage.get_status(boat)
	check(bool(st_after.get("equipmentOk", false)) and _approx(float(st_after.get("engineFactor", 0.0)), 1.0) and _approx(float(boat.engine), 1.0), "Genuine paid repair persists through Damage.get_status")
	var reinit: Dictionary = _seed_canonical_boat(c, boat)
	check(bool(reinit.get("ok", false)) and _approx(float(_item_at(boat.moduleCondition, "engine").get("hp", 0.0)), 1.0), "Genuine paid repair persists through Records.initialize without old scalar re-damaging engine")

	# Now test downward legacy scalar damage (boat.engine = 0.45) on a canonical hull.
	boat.engine = 0.45
	var q_downward: Dictionary = Harbor.service_quote(c, boat, p)
	check(bool(q_downward.get("ok", false)) and q_downward.get("equipmentDeficits", {}).has("engine") and _approx(float(q_downward.equipmentDeficits.engine.get("deficit", 0.0)), 0.55), "Downward legacy scalar engine damage (0.45) is absorbed before service_quote")
	check(_approx(float(_item_at(boat.moduleCondition, "engine").get("hp", 0.0)), 1.0), "Detached service_quote does not mutate live canonical engine item while absorbing downward scalar")
	var rep_down: Dictionary = Harbor.repair(c, str(boat.uid))
	check(bool(rep_down.get("ok", false)) and _approx(float(_item_at(boat.moduleCondition, "engine").get("hp", 0.0)), 1.0) and _approx(float(boat.engine), 1.0), "Paid repair absorbs downward scalar and restores canonical engine and projection to 1.0")

func test_captured_hull_birth_namespace_and_aliased_roster_dedup() -> void:
	var c = _new_campaign(403)
	var p: Dictionary = c.current_port()
	_fund_from_treasury(c, p, 5000)

	var prize: Dictionary = c.add_boat(c.hull("tin_skiff"), 4)
	# Seed with original enemy birthNamespace before capture reassigned boat.uid to prize.uid.
	var seeded: Dictionary = _seed_canonical_boat(c, prize, "enemy_convoy_9")
	check(bool(seeded.get("ok", false)) and str(prize.moduleCondition.get("birthNamespace", "")) == "enemy_convoy_9", "Captured hull retains original enemy birthNamespace")
	prize["captureSecured"] = true
	prize["supportOnly"] = true
	prize["needsHarborRepair"] = true
	prize["hp"] = float(prize.maxHp) - 18.0
	check(bool(_damage_at(prize, "mount0", 0.45, "boarding_fire").get("ok", false)), "Damage captured hull mount0")
	check(bool(_damage_at(prize, "engine", 0.75, "boarding_cripple").get("ok", false)), "Disable captured hull engine")
	Records.publish(prize)
	var m0_uid: String = str(_item_at(prize.moduleCondition, "mount0").get("itemUid", ""))
	check(Core._uid(m0_uid) and Core._records(prize.moduleCondition).ok and str(prize.moduleCondition.birthNamespace) == "enemy_convoy_9" and prize.moduleCondition.items.has(m0_uid), "Captured valid itemUid retains the original immutable birth record")

	# Also alias the exact same hull dictionary in boardingPrizes and another hull in both fleet and boardingPrizes.
	var flagship: Dictionary = c.state.fleet[0]
	_seed_canonical_boat(c, flagship)
	c.state["boardingPrizes"] = [prize, flagship]

	var q_flagship: Dictionary = Harbor.service_quote(c, flagship, p)
	check(bool(q_flagship.get("ok", false)), "Aliased same hull across fleet and boardingPrizes is counted once without false duplicate refusal")

	var q: Dictionary = Harbor.service_quote(c, prize, p)
	check(bool(q.get("ok", false)) and int(q.get("equipmentCount", 0)) == 2, "Captured hull with reassigned uid quotes cleanly using its immutable birthNamespace")
	var rep: Dictionary = Harbor.repair(c, str(prize.uid))
	check(bool(rep.get("ok", false)) and not bool(prize.get("captureSecured", false)) and not bool(prize.get("supportOnly", false)) and not bool(prize.get("needsHarborRepair", false)), "Paid Harbor.repair restores captured hull to active service and clears capture flags")
	check(str(_item_at(prize.moduleCondition, "mount0").get("itemUid", "")) == m0_uid and _approx(float(_item_at(prize.moduleCondition, "mount0").get("hp", 0.0)), 1.0) and _approx(float(_item_at(prize.moduleCondition, "engine").get("hp", 0.0)), 1.0), "Captured hull equipment keeps birthNamespace itemUids after restoration")

func test_atomic_refusals_leave_career_unchanged() -> void:
	var c = _new_campaign(404)
	var p: Dictionary = c.current_port()
	var boat: Dictionary = c.state.fleet[0]
	_fund_from_treasury(c, p, 5000)
	_seed_canonical_boat(c, boat)
	boat.hp = float(boat.maxHp) - 15.0
	check(bool(_damage_at(boat, "mount0", 0.40, "shell").get("ok", false)), "Damage mount0 for refusal tests")
	check(bool(_damage_at(boat, "engine", 0.50, "shell").get("ok", false)), "Damage engine for refusal tests")
	Records.publish(boat)
	var base_q: Dictionary = Harbor.service_quote(c, boat, p)
	check(bool(base_q.get("ok", false)) and int(base_q.get("cost", 0)) > 0, "Baseline quote for refusal checks is valid")

	# 1. Insufficient coins
	var saved_coins: int = int(c.state.coins)
	var shortage_transfer: int = int(c.state.coins) - (int(base_q.cost) - 1)
	check(Money.move(c.state, "coins", p, "governmentPurse", shortage_transfer, "Fixture reduce captain purse without losing coins", c.state.moneyLog), "Fund the genuine insufficient-coin scenario")
	var snap: Dictionary = c.state.duplicate(true)
	check(not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Insufficient coins refuses atomically with zero state mutation")
	check(Money.move(p, "governmentPurse", c.state, "coins", shortage_transfer, "Fixture restore captain purse", c.state.moneyLog) and int(c.state.coins) == saved_coins, "Restore the funded shortage fixture")

	# 2. Non-whole fractional coin balance refuses atomically
	c.state["coins"] = 5000.5
	snap = c.state.duplicate(true)
	check(not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Fractional float coin balance refuses atomically")
	c.state["coins"] = saved_coins

	# 3. Insufficient repair kits in harbor stock
	var saved_supplies: float = float(p.stocks.supplies)
	var saved_boat_supplies: float = float(boat.supplies)
	boat.supplies = 0.0
	p.stocks.supplies = 0.1
	snap = c.state.duplicate(true)
	check(not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Insufficient harbor supplies kits refuses atomically")
	p.stocks.supplies = saved_supplies
	boat.supplies = saved_boat_supplies

	# 4. Insufficient iron stock for equipment restoration
	var saved_iron: float = float(p.stocks.iron)
	p.stocks.iron = 0.01
	snap = c.state.duplicate(true)
	check(not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Insufficient harbor iron stock refuses atomically")
	p.stocks.iron = saved_iron

	# 5. Insufficient available shipwrights
	var saved_used_w: float = float(p.get("_yardWorkersUsed", 0.0))
	p["_yardWorkersUsed"] = float(p.get("availableWorkers", 0))
	snap = c.state.duplicate(true)
	check(not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Exhausted harbor workers refuses atomically")
	p["_yardWorkersUsed"] = saved_used_w

	# 6. Insufficient available specialists
	var saved_avail_spec: int = int(p.get("availableSpecialists", 0))
	var saved_spec: int = int(p.get("specialists", 0))
	p["availableSpecialists"] = 0
	p["specialists"] = 0
	snap = c.state.duplicate(true)
	check(not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Zero available specialists refuses atomically")
	p["availableSpecialists"] = saved_avail_spec
	p["specialists"] = saved_spec

	# 7. Stored at another harbor resolves port name via c.port(id).name
	boat["storedPort"] = "iron_reach"
	snap = c.state.duplicate(true)
	var stored_res: Dictionary = Harbor.repair(c, str(boat.uid))
	var expected_harbor_label: String = str(c.port("iron_reach").get("name", "iron_reach"))
	check(not stored_res.ok and str(stored_res.get("message", "")).contains(expected_harbor_label) and same(snap, c.state), "Boat stored at another harbor refuses atomically with resolved harbor name")
	boat["storedPort"] = ""

	# 8. Harbor cash overflow against EquipmentService.MAX_COINS
	var saved_cash: int = int(p.cash)
	p["cash"] = EquipmentService.MAX_COINS
	snap = c.state.duplicate(true)
	check(not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Over-bound inconsistent harbor purse refuses atomically")
	p["cash"] = saved_cash

	# 9. Corrupt moduleCondition (bad version)
	var saved_mc: Dictionary = boat.moduleCondition.duplicate(true)
	boat.moduleCondition["version"] = 99
	snap = c.state.duplicate(true)
	check(not Harbor.service_quote(c, boat, p).ok and not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Corrupt moduleCondition version refuses quote and repair without mutation")
	boat.moduleCondition = saved_mc.duplicate(true)

	# 10. Foreign condition key on boat
	boat["weaponCondition"] = {"mount0": 0.5}
	snap = c.state.duplicate(true)
	check(not Harbor.service_quote(c, boat, p).ok and not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Foreign condition field refuses quote and repair without mutation")
	boat.erase("weaponCondition")

	# 11. Duplicate itemUid across two distinct boats in fleet (via Core.collect_item_uids)
	var second: Dictionary = c.add_boat(c.hull("tin_skiff"), 4)
	_seed_canonical_boat(c, second)
	var dup_uid: String = str(_item_at(boat.moduleCondition, "mount0").get("itemUid", ""))
	var sec_m0_uid: String = str(_item_at(second.moduleCondition, "mount0").get("itemUid", ""))
	var sec_item: Dictionary = second.moduleCondition.items[sec_m0_uid].duplicate(true)
	second.moduleCondition.items.erase(sec_m0_uid)
	sec_item["itemUid"] = dup_uid
	second.moduleCondition.items[dup_uid] = sec_item
	snap = c.state.duplicate(true)
	check(not Harbor.service_quote(c, boat, p).ok and not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Cross-hull duplicate itemUid refuses quote and repair without mutation")
	c.state.fleet.erase(second)

	# 12. Duplicate boat uid across two distinct boats in fleet
	var dup_boat: Dictionary = c.add_boat(c.hull("tin_skiff"), 4)
	_seed_canonical_boat(c, dup_boat)
	dup_boat["uid"] = str(boat.uid)
	snap = c.state.duplicate(true)
	check(not Harbor.service_quote(c, boat, p).ok and not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Duplicate boat uid across distinct hulls refuses quote and repair without mutation")
	c.state.fleet.erase(dup_boat)

	# 13. Duplicate birthNamespace across two distinct boats with distinct boat uids
	var dup_ns_boat: Dictionary = c.add_boat(c.hull("tin_skiff"), 4)
	_seed_canonical_boat(c, dup_ns_boat)
	dup_ns_boat.moduleCondition["birthNamespace"] = str(boat.moduleCondition.get("birthNamespace", ""))
	snap = c.state.duplicate(true)
	check(not Harbor.service_quote(c, boat, p).ok and not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Duplicate birthNamespace across distinct hulls refuses quote and repair without mutation")
	c.state.fleet.erase(dup_ns_boat)

	# 14. Unknown originHullType on an equipment item
	var saved_origin_mc: Dictionary = boat.moduleCondition.duplicate(true)
	var m0_uid_check: String = str(_item_at(boat.moduleCondition, "mount0").get("itemUid", ""))
	boat.moduleCondition.items[m0_uid_check]["originHullType"] = "nonexistent_hull_99"
	snap = c.state.duplicate(true)
	check(not Harbor.service_quote(c, boat, p).ok and not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Unknown originHullType refuses quote and repair without mutation")
	boat.moduleCondition = saved_origin_mc.duplicate(true)

	# 15. Denied-access politics checks on actual Campaign:
	# (a) Genuine hostile standing, then separate absent-book read-only quote
	var saved_rel: Dictionary = c.state.get("relationships", {}).duplicate(true)
	for step in range(8):
		c.Factions.adjust(c.state, str(p.get("faction", "compact")), -100, "Hostile port test", "test-hostile-%d" % step)
	check(bool(c.Factions.standing(c.state, str(p.faction)).hostile), "Hostile standing is actually established before refusal")
	snap = c.state.duplicate(true)
	check(not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Hostile harbor politics refuses drydock repair atomically without mutating c.state.relationships")
	c.state["relationships"] = saved_rel
	c.state.erase("relationships")
	snap = c.state.duplicate(true)
	Harbor.service_quote(c, boat, p)
	check(same(snap, c.state) and not c.state.has("relationships"), "Quote with absent relationships does not initialize live politics")
	c.state["relationships"] = saved_rel

	# (b) Outstanding port claim refusal
	var saved_claims: Dictionary = c.state.relationships.factions[str(p.faction)].claims.duplicate(true)
	c.state.relationships.factions[str(p.faction)].claims[str(p.id)] = 120
	snap = c.state.duplicate(true)
	check(not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Outstanding harbor claim refuses drydock repair atomically")
	c.state.relationships.factions[str(p.faction)].claims = saved_claims

	# (c) Active sailing path refusal
	c.state.path = [{"x": 120.0, "y": 140.0}]
	snap = c.state.duplicate(true)
	check(not Harbor.repair(c, str(boat.uid)).ok and same(snap, c.state), "Active sailing path refuses drydock repair atomically")
	c.state.path = []

	# 16. Generic uid on uninitialized boat
	var generic_boat: Dictionary = boat.duplicate(true)
	generic_boat.erase("moduleCondition")
	generic_boat["uid"] = "tin_skiff"
	var generic_snap: Dictionary = generic_boat.duplicate(true)
	check(not Harbor.service_quote(c, generic_boat, p).ok and same(generic_snap, generic_boat), "Generic hull type as boat.uid is refused without seeding")

func test_legacy_without_schema_supported() -> void:
	var c = _new_campaign(405)
	var p: Dictionary = c.current_port()
	var boat: Dictionary = c.state.fleet[0]
	_fund_from_treasury(c, p, 4000)

	# Explicitly model the old schema; ordinary new careers are now canonical.
	boat.erase("moduleCondition")
	check(not boat.has("moduleCondition"), "Explicit older hull fixture has no moduleCondition schema")
	boat.hp = float(boat.maxHp) - 20.0
	boat.breaches = [{"area": 15.0, "section": "mid"}]
	boat.water = 30.0
	boat.wounded = 1.0
	boat.fire = 4.0
	boat.engine = 0.65
	boat.supplies = 1.0

	var before_quote: Dictionary = boat.duplicate(true)
	var q: Dictionary = Harbor.service_quote(c, boat, p)
	check(bool(q.get("ok", false)) and int(q.get("cost", 0)) > 0, "Harbor.service_quote supports legacy boat without schema")
	check(not boat.has("moduleCondition") and same(boat, before_quote), "Harbor.service_quote on legacy boat does not attach moduleCondition or mutate live boat")
	check(q.get("equipmentDeficits", {}).has("engine") and _approx(float(q.equipmentDeficits.engine.get("deficit", 0.0)), 0.35), "Legacy downward boat.engine=0.65 is absorbed on detached quote probe")

	var rep: Dictionary = Harbor.repair(c, str(boat.uid))
	check(bool(rep.get("ok", false)), "Harbor.repair succeeds on legacy boat without schema")
	check(not boat.has("moduleCondition"), "Harbor.repair on legacy boat without schema keeps legacy boat schema-free")
	check(_approx(float(boat.hp), float(boat.maxHp)) and boat.breaches.is_empty() and _approx(float(boat.water), 0.0) and _approx(float(boat.fire), 0.0) and _approx(float(boat.wounded), 0.0) and _approx(float(boat.engine), 1.0), "Legacy boat hull and engine scalar are fully repaired")
	check(Money.total(c.state) == int(c.state.coinSupply), "Legacy boat repair conserves total world coins")

func test_malformed_payment_records_refuse_before_payment() -> void:
	var cases: Array = [
		{"name": "null log", "log": null},
		{"name": "dictionary log", "log": {}},
		{"name": "string log", "log": "unreadable"},
		{"name": "null row", "log": [null]},
		{"name": "missing row fields", "log": [{}]},
		{"name": "fractional row coins", "log": [{"reason": "old", "cash": 1.5, "from": "coins", "to": "cash"}]},
		{"name": "bad payer field", "log": [{"reason": "old", "cash": 1, "from": 7, "to": "cash"}]},
		{"name": "near historical reason", "log": [{"reason": "Commission: materials, wages in escrow, yard income and duty changed", "cash": 100}]},
		{"name": "historical extra key", "log": [{"reason": "Commission: materials, wages in escrow, yard income and duty", "cash": 100, "extra": true}]},
		{"name": "historical boolean coins", "log": [{"reason": "Commission: materials, wages in escrow, yard income and duty", "cash": true}]},
		{"name": "historical one endpoint", "log": [{"reason": "Commission: materials, wages in escrow, yard income and duty", "cash": 100, "from": "coins"}]},
		{"name": "missing log", "omitLog": true},
		{"name": "missing world supply", "omitSupply": true}
	]
	for index in range(cases.size()):
		var setup: Dictionary = cases[index]
		var c = _new_campaign(701 + index)
		var p: Dictionary = c.current_port()
		var boat: Dictionary = c.state.fleet[0]
		_fund_from_treasury(c, p, 5000)
		check(_seed_canonical_boat(c, boat).ok, "Ledger scenario has real canonical inherited equipment: " + str(setup.name))
		check(_damage_at(boat, "engine", 0.5, "ledger-fixture").ok and Records.publish(boat).ok, "Ledger scenario has genuinely damaged machinery: " + str(setup.name))
		boat.hp = float(boat.maxHp) - 10.0
		var ready: Dictionary = Harbor.service_quote(c, boat, p)
		check(ready.ok and int(ready.cost) > 0 and int(c.state.coins) >= int(ready.cost) and Money.total(c.state) == int(c.state.coinSupply), "Healthy funded repair exists before journal corruption: " + str(setup.name))
		if setup.get("omitLog", false):
			c.state.erase("moneyLog")
		elif setup.has("log"):
			c.state.moneyLog = setup.log
		if setup.get("omitSupply", false):
			c.state.erase("coinSupply")
		var before: Dictionary = c.state.duplicate(true)
		var denied: Dictionary = Harbor.repair(c, str(boat.uid))
		check(not denied.ok and same(before, c.state), "Unreadable payment record refuses before coins, parts, materials or labor change: " + str(setup.name))

func test_commission_then_repair() -> void:
	for mode in ["modern", "legacy", "npc-legacy"]:
		var c = _new_campaign(950)
		var p: Dictionary = c.current_port()
		var boat: Dictionary = c.state.fleet[0]
		var spec: Dictionary = c.hull(str(p.shipIds[0]))
		var quote: Dictionary = Harbor.quote(c, spec, p)
		# Controlled initial fixture stock is finite; the commission must consume
		# its exact bill, and repair cannot borrow material from another harbor.
		for good in quote.materials:
			p.stocks[good] = maxf(float(p.stocks.get(good, 0.0)), float(quote.materials[good]) + 50.0)
		quote = Harbor.quote(c, spec, p)
		var remaining: int = maxi(0, int(quote.commissionPrice) + 20000 - int(c.state.coins))
		for donor in c.state.ports:
			var amount: int = mini(remaining, int(donor.governmentPurse))
			if amount > 0:
				check(Money.move(donor, "governmentPurse", c.state, "coins", amount, "Fixture funded commission advance", c.state.moneyLog), "commission fixture advances actual treasury coins")
				remaining -= amount
			if remaining == 0:
				break
		check(remaining == 0 and Money.total(c.state) == int(c.state.coinSupply), "commission budget comes from existing purses")
		var stocks_before: Dictionary = p.stocks.duplicate(true)
		var coins_before: int = int(c.state.coins)
		var booked: Dictionary = Harbor.commission(c, str(spec.id))
		check(booked.get("ok", false), "real funded hull commission books before %s repair" % mode)
		if not booked.get("ok", false):
			continue
		check(int(c.state.coins) == coins_before - int(quote.commissionPrice) and Money.total(c.state) == int(c.state.coinSupply), "commission moves exact coins to yard, government and worker escrow")
		for good in quote.materials:
			check(_approx(float(p.stocks[good]), float(stocks_before[good]) - float(quote.materials[good])), "commission consumes exact %s bill" % good)
		var receipt: Dictionary = c.state.moneyLog[0]
		check(str(receipt.get("from", "")) == "coins" and str(receipt.get("to", "")) == "yard construction", "future commission receipt identifies its payer and aggregate destination")
		if mode != "modern":
			receipt.erase("from")
			receipt.erase("to")
		var historical: Dictionary = receipt.duplicate(true)
		var npc: Dictionary = {}
		if mode == "npc-legacy":
			npc = c.fleet_owner("patrol-1")
			npc.atPort = str(p.id)
			boat = npc.boats[0]
			check(Money.move(c.state, "coins", npc, "coins", 6000, "Fixture company repair advance", c.state.moneyLog), "NPC repair budget is transferred, never created")
		check(_seed_canonical_boat(c, boat).get("ok", false), "commission repair uses actual canonical machinery")
		check(_damage_at(boat, "engine", 0.50, "Commission voyage wear").get("ok", false) and Records.publish(boat).get("ok", false), "commission repair has genuinely damaged installed engine")
		boat.hp = float(boat.maxHp) - 10.0
		var repair_quote: Dictionary = Harbor.service_quote(c, boat, p)
		var payer: Dictionary = c.state if npc.is_empty() else npc
		var payer_before: int = int(payer.coins)
		var repaired: Dictionary = Harbor.repair(c, str(boat.uid)) if npc.is_empty() else OwnerService.repair_owner_boat(npc, p, boat, c)
		check(repaired.get("ok", false), "paid %s repair accepts actual commission history" % mode)
		check(int(payer.coins) == payer_before - int(repair_quote.cost) and Money.total(c.state) == int(c.state.coinSupply), "post-commission repair pays exact quote and conserves world coins")
		var kept: bool = false
		for entry in c.state.moneyLog:
			if entry is Dictionary and entry == historical:
				kept = true
		check(kept, "repair retains commission receipt unchanged as historical metadata")
