extends SceneTree
## v0.031 native fixture for canonical NPC/company paid equipment upkeep and offscreen weapon power.

const Campaign = preload("res://scripts/campaign.gd")
const Fleets = preload("res://scripts/fleet_economy.gd")
const NavalCombat = preload("res://scripts/naval_combat.gd")
const NavalOrders = preload("res://scripts/naval_orders.gd")
const EquipmentOwnerService = preload("res://scripts/equipment_owner_service.gd")
const EquipmentService = preload("res://scripts/equipment_service.gd")
const Core = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Damage = preload("res://scripts/damage.gd")
const Refit = preload("res://scripts/refit.gd")
const Money = preload("res://scripts/money.gd")
const Factions = preload("res://scripts/factions.gd")
const Politics = preload("res://scripts/politics.gd")
const TradeRules = preload("res://scripts/trade_rules.gd")
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


func _first_diff(a: Variant, b: Variant, path: String = "$") -> String:
	if typeof(a) != typeof(b):
		return "%s: %s -> %s" % [path, type_string(typeof(a)), type_string(typeof(b))]
	if a is Dictionary:
		if a.size() != b.size():
			return "%s: key count %d -> %d" % [path, a.size(), b.size()]
		for key in a:
			if not b.has(key):
				return "%s: missing key %s" % [path, str(key)]
			var difference: String = _first_diff(a[key], b[key], "%s[%s]" % [path, str(key)])
			if not difference.is_empty():
				return difference
	elif a is Array:
		if a.size() != b.size():
			return "%s: length %d -> %d" % [path, a.size(), b.size()]
		for i in range(a.size()):
			var difference: String = _first_diff(a[i], b[i], "%s[%d]" % [path, i])
			if not difference.is_empty():
				return difference
	elif a != b:
		return "%s: %s -> %s" % [path, var_to_str(a), var_to_str(b)]
	return ""

func same(a, b) -> bool:
	var difference: String = _first_diff(a, b)
	if not difference.is_empty():
		print("SNAPSHOT DIFFERENCE: " + difference)
	return difference.is_empty()


func _new_campaign(seed_val: int = 501):
	var c = Campaign.new(world.duplicate(true))
	c.new_game(seed_val)
	return c


func _fund_from_treasuries(c, target: Dictionary, target_key: String, amount: int, reason: String) -> bool:
	var remaining: int = amount
	for p in c.state.ports:
		if remaining <= 0:
			break
		var step: int = mini(remaining, int(p.get("governmentPurse", 0)))
		if step > 0:
			if not Money.move(p, "governmentPurse", target, target_key, step, reason, c.state.moneyLog):
				return false
			remaining -= step
	return remaining == 0


func _fund_owner_from_treasury(c, _p: Dictionary, owner: Dictionary, amount: int) -> void:
	_fund_from_treasuries(c, owner, "coins", amount, "Fixture treasury NPC advance")


func _fund_captain_from_treasury(c, _p: Dictionary, amount: int) -> void:
	_fund_from_treasuries(c, c.state, "coins", amount, "Fixture treasury captain advance")


func _make_loadout_for_mounts(base: Dictionary, mount_weapons: Dictionary, engine_id: String = "stock_engine", armor_id: String = "stock_armor") -> Dictionary:
	var fit: Dictionary = Refit.defaults(base)
	var hps: Array = Refit.hardpoints(base)
	for i in range(hps.size()):
		var mid: String = str(hps[i].get("id", "mount%d" % i))
		fit.weapons[i] = str(mount_weapons.get(mid, ""))
	fit["engine"] = engine_id
	fit["armor"] = armor_id
	return fit


func _seed_canonical_boat(c, boat: Dictionary, identity_override: String = "", custom_loadout: Dictionary = {}) -> Dictionary:
	var ident: String = str(boat.get("uid", "")) if identity_override.is_empty() else identity_override
	# Fresh careers now already own their immutable physical birth. Reinitializing
	# the same fixture must preserve it rather than request a new test identity.
	if boat.get("moduleCondition") is Dictionary:
		ident = str(boat.moduleCondition.get("birthNamespace", ""))
	var base: Dictionary = c.hull(str(boat.get("type", "tin_skiff")))
	var load_src: Dictionary = custom_loadout if not custom_loadout.is_empty() else (boat.get("loadout") if boat.get("loadout") is Dictionary else Refit.defaults(base))
	var norm: Dictionary = Refit.normalize(base, load_src)
	if not bool(norm.get("ok", false)):
		return {"ok": false, "error": str(norm.get("message", "Invalid fitting loadout."))}
	boat["loadout"] = norm.loadout
	var eff_spec: Dictionary = Refit.effective_spec(base, boat.loadout)
	boat["baseSpec"] = base.duplicate(true)
	boat["spec"] = eff_spec
	boat["maxHp"] = maxf(1.0, float(eff_spec.get("hp", base.get("hp", 150.0))))
	boat["hp"] = clampf(float(boat.get("hp", boat.maxHp)), 0.0, float(boat.maxHp))
	boat["armor"] = maxf(0.0, float(eff_spec.get("armor", base.get("armor", 0.0))))
	boat["economyBaseSpeed"] = float(boat.spec.get("speed", 90.0))
	boat["economyBaseFireRate"] = float(boat.spec.get("fireRate", 1.0))
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
	test_paid_canonical_npc_harbor_repair_and_diplomacy()
	test_atomic_refusals_and_deferrals_preserve_career_state()
	test_company_repair_expense_engine_persistence_and_legacy_npc()
	test_offscreen_canonical_weapon_availability_and_power()
	print("equipment_owner_service: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func test_paid_canonical_npc_harbor_repair_and_diplomacy() -> void:
	var c = _new_campaign(501)
	var owner: Dictionary = c.fleet_owner("patrol-1")
	var port: Dictionary = c.port("brass_haven")
	owner["atPort"] = str(port.get("id", ""))
	var pat: Dictionary = c.NavalAI._find_patrol(c.state, str(owner.get("id", "")))
	if not pat.is_empty():
		pat["x"] = float(port.get("x", 0.0))
		pat["y"] = float(port.get("y", 0.0))
		pat["holding"] = true

	_fund_owner_from_treasury(c, port, owner, 8000)
	_fund_captain_from_treasury(c, port, 5000)
	var boat: Dictionary = owner.boats[0]
	var base: Dictionary = c.hull(str(boat.get("type", "tin_skiff")))

	var init_res: Dictionary = _seed_canonical_boat(c, boat, "npc:patrol-1:0")
	check(bool(init_res.get("ok", false)) and boat.has("moduleCondition"), "Canonical equipment records initialize on active NPC fleet boat")
	check(boat.loadout.get("weapons") is Array and not boat.loadout.has("utility"), "Normalized loadout uses Array[String] weapons and has no utility field")

	# Explicit fixture setup: accept a damaged spare weapon in the NPC boat's locker.
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
	check(bool(stored_spare.get("ok", false)), "Damaged spare weapon accepted in NPC boat locker")
	var spare_uid: String = str(stored_spare.get("itemUid", ""))
	check(not spare_uid.is_empty() and boat.moduleCondition.items.has(spare_uid), "NPC locker spare has a valid canonical itemUid")
	check(bool(Records.publish(boat).get("ok", false)), "Publish canonical locker spare on NPC boat")

	# Damage all four installed canonical parts across weapons, engines (disabled at Core.DISABLE_HP = 0.20), pumps, and armor.
	var m0_before: Dictionary = _item_at(boat.moduleCondition, "mount0")
	var eng_before: Dictionary = _item_at(boat.moduleCondition, "engine")
	var pump_before: Dictionary = _item_at(boat.moduleCondition, "pumps")
	var arm_before: Dictionary = _item_at(boat.moduleCondition, "armor")

	check(bool(_damage_at(boat, "mount0", 0.50, "shell").get("ok", false)), "Damage NPC installed mount0 to 0.50")
	check(bool(_damage_at(boat, "engine", 0.80, "boiler_hit").get("ok", false)), "Disable NPC installed engine at 0.20 (Core.DISABLE_HP)")
	check(bool(_damage_at(boat, "pumps", 0.40, "flooding_shock").get("ok", false)), "Damage NPC installed integral pumps to 0.60")
	check(bool(_damage_at(boat, "armor", 0.30, "armor_spall").get("ok", false)), "Damage NPC installed armor to 0.70")
	check(bool(Records.publish(boat).get("ok", false)), "Publish damaged canonical equipment state on NPC boat")

	boat.hp = float(boat.maxHp) - 24.0
	boat.breaches = [{"area": 20.0, "section": "bow"}]
	boat.water = 10.0
	boat.fire = 6.0
	boat.wounded = 1.0
	boat.supplies = 1.0
	boat.fuel = 3.5
	boat.ammo = 60.0
	boat.crew = float(boat.get("crewMin", 3))

	# Prove NPC harbor service uses NPC faction diplomacy, not player personal standing in Factions relationship book.
	var port_faction: String = str(port.get("faction", "compact"))
	check(bool(Factions.adjust(c.state, port_faction, -25, "Fixture player offense 1", "fixture:hostile:1").get("ok", false)), "First player standing adjustment (-25) in Factions book succeeds")
	check(bool(Factions.adjust(c.state, port_faction, -25, "Fixture player offense 2", "fixture:hostile:2").get("ok", false)), "Second player standing adjustment (-25) reaches hostile threshold (-50)")
	check(bool(Factions.adjust(c.state, port_faction, -25, "Fixture player offense 3", "fixture:hostile:3").get("ok", false)), "Third player standing adjustment (-25) reaches -75")
	check(bool(Factions.standing(c.state, port_faction).get("hostile", false)), "Player standing in Factions book is hostile")
	check(not bool(Politics.permit(c, "service").get("ok", false)) and not bool(Politics.permit(c, "repair").get("ok", false)), "Real Politics.permit denies service and repair when player standing is hostile")
	var npc_access: Dictionary = EquipmentOwnerService.allowed_port_service(owner, port, c)
	check(bool(npc_access.get("ok", false)), "Friendly NPC fleet owner is still permitted harbor drydock service regardless of player standing")

	# Control the former snapshot comparison BEFORE the operation. This is
	# diagnostic only; the actual immutability assertions below remain strict.
	var json_roundtrip: Dictionary = JSON.parse_string(JSON.stringify(c.state))
	print("SNAPSHOT CONTROL legacy JSON comparison before quote: " + str(JSON.stringify(json_roundtrip) == JSON.stringify(c.state)))
	print("SNAPSHOT CONTROL first native roundtrip difference: " + _first_diff(c.state, json_roundtrip))
	var pre_quote_snap: Dictionary = c.state.duplicate(true)
	var q: Dictionary = EquipmentOwnerService.owner_service_quote(owner, port, boat, c)
	check(same(pre_quote_snap, c.state), "Detached owner_service_quote is read-only and never mutates campaign state")
	check(bool(q.get("ok", false)), "NPC canonical repair quote succeeds")
	check(int(q.get("equipmentCount", 0)) == 4 and (int(q.get("equipmentCount", 0)) - int(q.get("disabledCount", 0))) == 3 and int(q.get("disabledCount", 0)) == 1, "NPC quote counts 3 damaged and 1 disabled installed parts and ignores locker spare")
	check(int(q.get("cost", 0)) == int(q.get("materials", 0)) + int(q.get("ordinary", 0)) + int(q.get("expert", 0)) + int(q.get("fee", 0)), "NPC quote total cost equals materials + ordinary + expert + fee")

	var state_ref: Dictionary = c.state
	var owner_ref: Dictionary = owner
	var port_ref: Dictionary = port
	var stocks_ref: Dictionary = port.stocks
	var boat_ref: Dictionary = boat
	var seq_before: int = int(boat.moduleCondition.nextItemSeq)
	var birth_ns_before: String = str(boat.moduleCondition.birthNamespace)
	var uids_before: Dictionary = {
		"mount0": str(m0_before.get("itemUid", "")),
		"engine": str(eng_before.get("itemUid", "")),
		"pumps": str(pump_before.get("itemUid", "")),
		"armor": str(arm_before.get("itemUid", ""))
	}

	var supply_before: int = Money.total(c.state)
	var owner_coins_before: int = int(owner.coins)
	var owner_crew_before: int = int(owner.crewPurse)
	var captain_coins_before: int = int(c.state.coins)
	var captain_crew_before: int = int(c.state.crewPurse)
	var other_owner: Dictionary = c.fleet_owner("patrol-2")
	var other_owner_snap: Dictionary = other_owner.duplicate(true)
	var port_cash_before: int = int(port.cash)
	var port_house_before: int = int(port.householdPurse)
	var port_expert_before: int = int(port.expertPurse)
	var port_gov_before: int = int(port.governmentPurse)
	var port_supplies_before: float = float(port.stocks.supplies)
	var port_iron_before: float = float(port.stocks.iron)
	var port_copper_before: float = float(port.stocks.copper)
	var port_timber_before: float = float(port.stocks.timber)
	var workers_used_before: float = float(port.get("_yardWorkersUsed", 0.0))
	var specs_used_before: float = float(port.get("_yardSpecialistsUsed", 0.0))
	var log_len_before: int = c.state.moneyLog.size()
	var crew_before: float = float(boat.crew)
	var fuel_before: float = float(boat.fuel)
	var ammo_before: float = float(boat.ammo)

	# Execute actual NPC repair path through Fleets._repair.
	Fleets._repair(owner, port, boat, c)

	check(is_same(c.state, state_ref) and is_same(owner, owner_ref) and is_same(port, port_ref) and is_same(port.stocks, stocks_ref) and is_same(boat, boat_ref), "Fleets._repair preserves live state, owner, port, stocks, and boat Dictionary references")
	check(int(owner.coins) == owner_coins_before - int(q.cost), "NPC owner.coins decreases by exact quoted cost")
	check(int(owner.crewPurse) == owner_crew_before, "NPC owner.crewPurse is untouched")
	check(int(c.state.coins) == captain_coins_before and int(c.state.crewPurse) == captain_crew_before, "Captain coins and captain crew savings remain completely unchanged")
	check(same(other_owner_snap, other_owner), "Other fleet owners remain completely unchanged")
	check(int(port.cash) == port_cash_before + int(q.materials) + int(q.fee), "Harbor business cash receives exact materials + yard fee from NPC owner")
	check(int(port.householdPurse) == port_house_before + int(q.ordinary), "Harbor householdPurse receives exact ordinary shipwright wages from NPC owner")
	check(int(port.expertPurse) == port_expert_before + int(q.expert), "Harbor expertPurse receives exact specialist wages from NPC owner")
	check(int(port.governmentPurse) == port_gov_before, "Harbor governmentPurse is untouched during NPC service")
	check(Money.total(c.state) == supply_before and Money.total(c.state) == int(c.state.coinSupply), "World coin supply is conserved after paid NPC repair")
	check(c.state.moneyLog.size() == mini(60, log_len_before + 3), "Three ledger entries recorded for materials+fee, ordinary wages, and specialist wages")

	var eq_mats: Dictionary = q.get("equipmentMaterials", {})
	check(_approx(float(port.stocks.supplies), port_supplies_before - float(q.purchase)), "Harbor supplies stock decreases by exact purchased kits")
	check(_approx(float(port.stocks.iron), port_iron_before - float(eq_mats.get("iron", 0.0))), "Harbor iron stock decreases by exact equipment iron requirement")
	check(_approx(float(port.stocks.copper), port_copper_before - float(eq_mats.get("copper", 0.0))), "Harbor copper stock decreases by exact equipment copper requirement")
	check(_approx(float(port.stocks.timber), port_timber_before - float(eq_mats.get("timber", 0.0))), "Harbor timber stock decreases by exact equipment timber requirement")
	check(_approx(float(boat.supplies), 1.0 - float(q.own)), "NPC boat onboard repair kits consumed by exact q.own")
	check(_approx(float(port.get("_yardWorkersUsed", 0.0)), workers_used_before + float(q.workerDays)), "Harbor _yardWorkersUsed reserves exact total workerDays")
	check(_approx(float(port.get("_yardSpecialistsUsed", 0.0)), specs_used_before + float(q.expertDays)), "Harbor _yardSpecialistsUsed reserves exact expertDays")

	check(_approx(float(boat.hp), float(boat.maxHp)) and boat.breaches.is_empty() and _approx(float(boat.water), 0.0) and _approx(float(boat.fire), 0.0) and _approx(float(boat.wounded), 0.0), "NPC hull hp, breaches, water, fire, and wounded are restored")
	check(_approx(float(boat.crew), crew_before) and _approx(float(boat.fuel), fuel_before) and _approx(float(boat.ammo), ammo_before), "NPC equipment repair does not replenish crew, fuel, or ammunition")
	check(int(boat.moduleCondition.nextItemSeq) == seq_before and str(boat.moduleCondition.birthNamespace) == birth_ns_before, "Canonical nextItemSeq and birthNamespace are preserved")

	for loc in ["mount0", "engine", "pumps", "armor"]:
		var restored_item: Dictionary = _item_at(boat.moduleCondition, loc)
		check(str(restored_item.get("itemUid", "")) == str(uids_before[loc]), "Installed %s preserves exact itemUid" % loc)
		check(_approx(float(restored_item.get("hp", 0.0)), 1.0) and str(restored_item.get("status", "")) == "ok" and str(restored_item.get("cause", "")) == "", "Installed %s restored to hp=1.0, status=ok, cause=''" % loc)

	var spare_after: Dictionary = boat.moduleCondition.items.get(spare_uid, {})
	check(str(spare_after.get("location", "")) == "locker" and _approx(float(spare_after.get("hp", 0.0)), 0.42) and str(spare_after.get("status", "")) == "damaged", "Damaged locker spare on NPC boat remains untouched in locker at hp=0.42")


func test_atomic_refusals_and_deferrals_preserve_career_state() -> void:
	var c = _new_campaign(502)
	var owner: Dictionary = c.fleet_owner("patrol-1")
	var port: Dictionary = c.port("brass_haven")
	owner["atPort"] = str(port.get("id", ""))
	_fund_owner_from_treasury(c, port, owner, 6000)
	_fund_captain_from_treasury(c, port, 40000)

	var boat: Dictionary = owner.boats[0]
	check(bool(_seed_canonical_boat(c, boat, "npc:patrol-1:0").get("ok", false)), "Seed canonical records on NPC refusal fixture boat")
	check(bool(_damage_at(boat, "engine", 0.80, "boiler_hit").get("ok", false)), "Disable engine on NPC refusal fixture boat")
	check(bool(_damage_at(boat, "mount0", 0.50, "shell").get("ok", false)), "Damage mount0 on NPC refusal fixture boat")
	check(bool(Records.publish(boat).get("ok", false)), "Publish damaged state on NPC refusal fixture boat")
	boat.hp = float(boat.maxHp) - 18.0
	boat.supplies = 2.0

	var q: Dictionary = EquipmentOwnerService.owner_service_quote(owner, port, boat, c)
	check(bool(q.get("ok", false)) and int(q.get("cost", 0)) > 0, "Baseline NPC repair quote is valid before refusal checks")

	# 1. Unavailable core context defers safely and never falls through to legacy scalar engine += amount healing.
	var snap_no_core: Dictionary = c.state.duplicate(true)
	var res_no_core: Dictionary = EquipmentOwnerService.repair_owner_boat(owner, port, boat, null)
	Fleets._repair(owner, port, boat, null)
	check(not bool(res_no_core.get("ok", false)) and bool(res_no_core.get("deferred", false)) and same(snap_no_core, c.state), "Unavailable core context defers safely without falling through to legacy scalar healing")

	# 2. Insufficient owner.coins refuses even when captain has 40,000+ coins; captain is never charged.
	var saved_owner_coins: int = int(owner.coins)
	var short_target: int = maxi(0, int(q.cost) - 1)
	if saved_owner_coins > short_target:
		Money.move(owner, "coins", port, "governmentPurse", saved_owner_coins - short_target, "Fixture drain NPC coins", c.state.moneyLog)
	var snap_coins: Dictionary = c.state.duplicate(true)
	var res_coins: Dictionary = EquipmentOwnerService.repair_owner_boat(owner, port, boat, c)
	Fleets._repair(owner, port, boat, c)
	check(not bool(res_coins.get("ok", false)) and bool(res_coins.get("deferred", false)) and same(snap_coins, c.state), "Insufficient owner.coins defers atomically and never charges captain purse")
	if saved_owner_coins > short_target:
		Money.move(port, "governmentPurse", owner, "coins", saved_owner_coins - short_target, "Fixture restore NPC coins", c.state.moneyLog)

	# 3. Exhausted shipwright workforce refuses atomically.
	var saved_workers_used = port.get("_yardWorkersUsed", 0.0)
	port["_yardWorkersUsed"] = float(port.get("availableWorkers", 20.0))
	var snap_workers: Dictionary = c.state.duplicate(true)
	var res_workers: Dictionary = EquipmentOwnerService.repair_owner_boat(owner, port, boat, c)
	check(not bool(res_workers.get("ok", false)) and same(snap_workers, c.state), "Exhausted harbor shipwrights refuse NPC service with zero mutation")
	port["_yardWorkersUsed"] = saved_workers_used

	# 4. Exhausted engineering specialists refuse atomically.
	var saved_avail_spec = port.get("availableSpecialists", 0.0)
	var saved_spec_workers = port.get("specialistWorkers", 0.0)
	port["availableSpecialists"] = 0.0
	port["specialistWorkers"] = 0.0
	var snap_spec: Dictionary = c.state.duplicate(true)
	var res_spec: Dictionary = EquipmentOwnerService.repair_owner_boat(owner, port, boat, c)
	check(not bool(res_spec.get("ok", false)) and same(snap_spec, c.state), "Zero available specialists refuse NPC service with zero mutation")
	port["availableSpecialists"] = saved_avail_spec
	port["specialistWorkers"] = saved_spec_workers

	# 5. Insufficient harbor iron stock refuses atomically.
	var saved_iron: float = float(port.stocks.iron)
	port.stocks["iron"] = 0.1
	var snap_iron: Dictionary = c.state.duplicate(true)
	var res_iron: Dictionary = EquipmentOwnerService.repair_owner_boat(owner, port, boat, c)
	check(not bool(res_iron.get("ok", false)) and same(snap_iron, c.state), "Insufficient harbor iron stock refuses NPC service with zero mutation")
	port.stocks["iron"] = saved_iron

	# 6. Hostile NPC faction relation via Factions.set_relation and relationships.pairs[Factions._pair_key] refuses atomically.
	var port_fac: String = str(port.get("faction", "compact"))
	var saved_owner_faction: String = str(owner.get("faction", ""))
	var saved_rel: int = Factions.relation(c.state, "reed", port_fac)
	var pair_key: String = Factions._pair_key("reed", port_fac)
	var set_rel_res: Dictionary = Factions.set_relation(c.state, "reed", port_fac, -25, "Fixture hostile relation refusal")
	check(bool(set_rel_res.get("ok", false)) and Factions.relation(c.state, "reed", port_fac) == -25 and int(c.state.relationships.pairs.get(pair_key, 0)) == -25, "Factions.set_relation updates relationships.pairs[Factions._pair_key] to -25")
	owner["faction"] = "reed"
	var snap_hostile: Dictionary = c.state.duplicate(true)
	var res_hostile: Dictionary = EquipmentOwnerService.repair_owner_boat(owner, port, boat, c)
	check(not bool(res_hostile.get("ok", false)) and same(snap_hostile, c.state), "Hostile NPC faction relationship refuses harbor service with zero mutation")
	owner["faction"] = saved_owner_faction
	Factions.set_relation(c.state, "reed", port_fac, saved_rel, "Restore relation")

	# 7. Valid TradeRules embargo row (issuer/target/good/expires) on repair material refuses atomically.
	var embargo_bans: Array = [{"issuer": str(port.get("faction", "compact")), "target": str(owner.get("faction", "compact")), "good": "iron", "expires": 999.0}]
	c.state["tradeLaw"] = {"bans": embargo_bans}
	check(TradeRules.allowed(embargo_bans, str(owner.get("faction", "compact")), str(port.get("faction", "compact")), "copper", float(c.state.day)), "Valid TradeRules embargo row allows non-embargoed copper (not a malformed row reject)")
	check(not TradeRules.allowed(embargo_bans, str(owner.get("faction", "compact")), str(port.get("faction", "compact")), "iron", float(c.state.day)), "Valid TradeRules embargo row blocks embargoed iron")
	var snap_embargo: Dictionary = c.state.duplicate(true)
	var res_embargo: Dictionary = EquipmentOwnerService.repair_owner_boat(owner, port, boat, c)
	check(not bool(res_embargo.get("ok", false)) and bool(res_embargo.get("deferred", false)) and same(snap_embargo, c.state), "Trade embargo on required equipment material refuses NPC service with zero mutation")
	c.state.erase("tradeLaw")

	# 8. Malformed moneyLog (non-array or non-dictionary entry) refuses before any mutation.
	var saved_mlog: Array = c.state.moneyLog.duplicate(true)
	c.state["moneyLog"] = "corrupt_log"
	var snap_bad_mlog: Dictionary = c.state.duplicate(true)
	var res_bad_mlog: Dictionary = EquipmentOwnerService.repair_owner_boat(owner, port, boat, c)
	Fleets._repair(owner, port, boat, c)
	check(not bool(res_bad_mlog.get("ok", false)) and same(snap_bad_mlog, c.state), "Non-array moneyLog refuses before any mutation")
	c.state["moneyLog"] = ["bad_entry"]
	var snap_bad_mlog_entry: Dictionary = c.state.duplicate(true)
	var res_bad_mlog_entry: Dictionary = EquipmentOwnerService.repair_owner_boat(owner, port, boat, c)
	check(not bool(res_bad_mlog_entry.get("ok", false)) and same(snap_bad_mlog_entry, c.state), "Malformed moneyLog entry refuses before any mutation")
	c.state["moneyLog"] = saved_mlog

	# 9. Detached/unregistered owner dictionary or wrong owner not owning boat refuses atomically.
	var detached_owner: Dictionary = owner.duplicate(true)
	var other_owner: Dictionary = c.fleet_owner("patrol-2")
	other_owner["atPort"] = str(port.get("id", ""))
	var snap_own: Dictionary = c.state.duplicate(true)
	check(not bool(EquipmentOwnerService.repair_owner_boat(detached_owner, port, boat, c).get("ok", false)) and same(snap_own, c.state), "Detached unregistered owner dictionary is refused with zero mutation")
	check(not bool(EquipmentOwnerService.repair_owner_boat(other_owner, port, boat, c).get("ok", false)) and same(snap_own, c.state), "Owner that does not own the physical hull is refused with zero mutation")

	# 10. Undocked owner (atPort != port.id) or boat stored at another port refuses atomically.
	owner["atPort"] = ""
	var snap_undocked: Dictionary = c.state.duplicate(true)
	check(not bool(EquipmentOwnerService.repair_owner_boat(owner, port, boat, c).get("ok", false)) and same(snap_undocked, c.state), "Undocked NPC owner at sea is refused with zero mutation")
	owner["atPort"] = str(port.get("id", ""))

	boat["storedPort"] = "kelp_reach"
	var snap_stored: Dictionary = c.state.duplicate(true)
	check(not bool(EquipmentOwnerService.repair_owner_boat(owner, port, boat, c).get("ok", false)) and same(snap_stored, c.state), "Hull stored at another harbor is refused with zero mutation")
	boat["storedPort"] = ""

	# 11. Foreign condition key on owner or boat, or corrupt moduleCondition refuses atomically.
	owner["equipmentCondition"] = {}
	var snap_foreign_owner: Dictionary = c.state.duplicate(true)
	Fleets._repair(owner, port, boat, c)
	check(not bool(EquipmentOwnerService.repair_owner_boat(owner, port, boat, c).get("ok", false)) and same(snap_foreign_owner, c.state), "Owner with foreign condition key is refused with zero mutation")
	owner.erase("equipmentCondition")

	boat["equipmentCondition"] = 99
	var snap_foreign_boat: Dictionary = c.state.duplicate(true)
	Fleets._repair(owner, port, boat, c)
	check(not bool(EquipmentOwnerService.repair_owner_boat(owner, port, boat, c).get("ok", false)) and same(snap_foreign_boat, c.state), "Boat with foreign condition key is refused and never falls through to legacy repair")
	boat.erase("equipmentCondition")

	var saved_mc: Dictionary = boat.moduleCondition.duplicate(true)
	boat["moduleCondition"] = "corrupt_payload"
	var snap_corrupt: Dictionary = c.state.duplicate(true)
	Fleets._repair(owner, port, boat, c)
	check(not bool(EquipmentOwnerService.repair_owner_boat(owner, port, boat, c).get("ok", false)) and same(snap_corrupt, c.state), "Corrupt moduleCondition is refused with zero mutation")
	boat["moduleCondition"] = saved_mc

	# 12. Duplicate itemUid across fleet owners refuses atomically.
	var other_boat: Dictionary = other_owner.boats[0]
	other_boat["moduleCondition"] = saved_mc.duplicate(true)
	var snap_dup: Dictionary = c.state.duplicate(true)
	check(not bool(EquipmentOwnerService.repair_owner_boat(owner, port, boat, c).get("ok", false)) and same(snap_dup, c.state), "Duplicate canonical itemUid across fleet owners is refused with zero mutation")
	other_boat.erase("moduleCondition")
	check(Money.total(c.state) == int(c.state.coinSupply), "All refusal paths conserve total world coin supply")


func test_company_repair_expense_engine_persistence_and_legacy_npc() -> void:
	var c = _new_campaign(503)
	var home: Dictionary = c.current_port()
	_fund_captain_from_treasury(c, home, 120000)
	check(bool(c.buy_boat("tin_skiff").get("ok", false)), "Purchase second real hull for company charter")
	var company_hull_uid: String = str(c.state.fleet[-1].uid)
	var limits: Dictionary = {"buyMax": 10000, "sellMin": 0, "maxCargo": 10.0, "reserve": 4000, "risk": 0.4}
	var charter: Dictionary = c.CompanyOps.create(c, [company_hull_uid], "kelp_reach", "timber", 30000, limits)
	check(bool(charter.get("ok", false)), "Charter actual player shipping company with second hull")

	var company_id: String = str(charter.get("id", ""))
	var company_owner: Dictionary = c.fleet_owner(company_id)
	var pat: Dictionary = c.CompanyOps.api(c)._patrol(c.state, company_id)
	pat["x"] = float(home.get("x", 0.0))
	pat["y"] = float(home.get("y", 0.0))
	pat["holding"] = true
	company_owner["atPort"] = str(home.get("id", ""))

	var company_boat: Dictionary = company_owner.boats[0]
	var base: Dictionary = c.hull(str(company_boat.get("type", "tin_skiff")))
	check(bool(_seed_canonical_boat(c, company_boat, company_hull_uid).get("ok", false)), "Seed canonical equipment records on company boat")
	var company_eng_uid_before: String = str(_item_at(company_boat.moduleCondition, "engine").get("itemUid", ""))
	check(not company_eng_uid_before.is_empty(), "Company boat has a valid canonical installed engine itemUid")

	# Add a damaged locker spare on the company boat.
	var spare_res: Dictionary = Core.accept_acquired_item(company_boat.moduleCondition, {
		"acquired": true,
		"family": "weapons",
		"typeId": "rapid_gun",
		"originHullType": str(company_boat.get("type", "tin_skiff")),
		"location": "locker",
		"hp": 0.44,
		"cause": "salvaged_spare",
		"mountCount": Refit.hardpoints(base).size(),
		"hullType": str(base.get("id", "tin_skiff")),
		"knownUids": []
	})
	var spare_uid: String = str(spare_res.get("itemUid", ""))
	check(bool(spare_res.get("ok", false)) and not spare_uid.is_empty(), "Accept damaged spare in company boat locker")

	# Damage mount0, armor, pumps, and apply downward scalar engine damage (0.15) to verify absorption before repair,
	# plus upward scalar tamper protection.
	check(bool(_damage_at(company_boat, "mount0", 0.45, "shell").get("ok", false)), "Damage company mount0 to 0.55")
	check(bool(_damage_at(company_boat, "pumps", 0.35, "flood").get("ok", false)), "Damage company pumps to 0.65")
	check(bool(_damage_at(company_boat, "armor", 0.25, "spall").get("ok", false)), "Damage company armor to 0.75")
	check(bool(Records.publish(company_boat).get("ok", false)), "Publish initial damaged company equipment state")

	# Downward legacy scalar boat.engine damage is absorbed before quoting/work; upward tamper cannot mask canonical damage.
	company_boat["engine"] = 0.15
	var q_down: Dictionary = EquipmentOwnerService.owner_service_quote(company_owner, home, company_boat, c)
	check(bool(q_down.get("ok", false)) and int(q_down.get("disabledCount", 0)) == 1 and int(q_down.get("equipmentCount", 0)) == 4, "Downward scalar boat.engine=0.15 is absorbed into canonical engine condition for quote")

	check(bool(_damage_at(company_boat, "engine", 0.85, "boiler_burst").get("ok", false)), "Disable canonical company engine at 0.15")
	company_boat["engine"] = 1.0
	company_boat["hp"] = float(company_boat.maxHp) - 16.0
	company_boat["supplies"] = 2.0

	var q: Dictionary = EquipmentOwnerService.owner_service_quote(company_owner, home, company_boat, c)
	check(bool(q.get("ok", false)) and int(q.get("disabledCount", 0)) == 1 and int(q.get("cost", 0)) > 0, "Upward scalar boat.engine=1.0 tamper does not bypass canonical disabled engine quote")

	var book: Dictionary = c.state.shippingCompanies[company_id]
	var book_ref: Dictionary = book
	var book_log_ref: Array = book.log

	# Prove unsupported/limited Dictionary context or invalid company book refuses BEFORE any coins or boat fields change.
	var snap_lim_ctx: Dictionary = c.state.duplicate(true)
	var res_lim_ctx: Dictionary = EquipmentOwnerService.repair_owner_boat(company_owner, home, company_boat, {"state": c.state})
	check(not bool(res_lim_ctx.get("ok", false)) and bool(res_lim_ctx.get("deferred", false)) and same(snap_lim_ctx, c.state), "Limited Dictionary context without hull catalog defers safely before any company coin/boat mutation")

	var saved_status: String = str(book.get("status", "active"))
	book["status"] = "collected"
	var snap_collected_book: Dictionary = c.state.duplicate(true)
	var res_collected_book: Dictionary = EquipmentOwnerService.repair_owner_boat(company_owner, home, company_boat, c)
	check(not bool(res_collected_book.get("ok", false)) and same(snap_collected_book, c.state), "Collected company book refuses before any coin or hull mutation")
	book["status"] = saved_status

	var invested_before: int = int(book.get("invested", 0))
	var op_before: int = int(book.get("operating", 0))
	var rev_before: int = int(book.get("revenue", 0))
	var cogs_before: int = int(book.get("cogs", 0))
	var book_log_before: int = book.get("log", []).size()
	var company_coins_before: int = int(company_owner.coins)
	var captain_coins_before: int = int(c.state.coins)
	var supply_before: int = Money.total(c.state)

	Fleets._repair(company_owner, home, company_boat, c)

	check(is_same(c.state.shippingCompanies[company_id], book_ref) and is_same(book.log, book_log_ref), "Company repair preserves live shippingCompanies book and log references")
	check(int(company_owner.coins) == company_coins_before - int(q.cost), "Company repair is paid exclusively from company_owner.coins")
	check(int(c.state.coins) == captain_coins_before, "Captain personal coins are untouched by company repair")
	check(int(book.get("invested", 0)) == invested_before, "Company invested capital is unchanged and never treated as profit")
	check(int(book.get("operating", 0)) == op_before + int(q.cost), "Company operating expense increases by exact repair cost once")
	check(int(book.get("netProfit", 0)) == rev_before - cogs_before - int(book.get("operating", 0)), "Company netProfit balances revenue - cogs - operating")
	check(book.get("log", []).size() == book_log_before + 1 and str(book.log[-1].get("event", "")) == "repairs" and int(book.log[-1].get("coins", 0)) == int(q.cost), "CompanyOps.record logs a single 'repairs' event for the exact cost")
	check(Money.total(c.state) == supply_before and Money.total(c.state) == int(c.state.coinSupply), "World coin supply is conserved after paid company repair")

	# Verify engine repair persists through Damage.get_status (engineHp/engineFactor/speedFactor) and Records.initialize, and locker spare stays damaged.
	var st_after: Dictionary = Damage.get_status(company_boat)
	var eng_after: Dictionary = _item_at(company_boat.moduleCondition, "engine")
	check(bool(st_after.get("equipmentOk", false)) and _approx(float(st_after.get("engineHp", 0.0)), 1.0) and _approx(float(st_after.get("engineFactor", 0.0)), 1.0) and _approx(float(st_after.get("speedFactor", 0.0)), 1.0), "Restored company engine reports engineHp=1.0, engineFactor=1.0, speedFactor=1.0 in read-only Damage.get_status")
	check(str(eng_after.get("itemUid", "")) == company_eng_uid_before and _approx(float(eng_after.get("hp", 0.0)), 1.0) and str(eng_after.get("status", "")) == "ok" and _approx(float(company_boat.get("engine", 0.0)), 1.0), "Restored company engine preserves exact itemUid, raw hp=1.0, status=ok, and boat.engine=1.0 projection")
	var reinit: Dictionary = Records.initialize(company_boat, {
		"identity": company_hull_uid,
		"base": base,
		"catalog": Refit.catalog(),
		"loadout": company_boat.loadout
	})
	var eng_reinit: Dictionary = _item_at(company_boat.moduleCondition, "engine")
	check(bool(reinit.get("ok", false)) and str(eng_reinit.get("itemUid", "")) == company_eng_uid_before and _approx(float(eng_reinit.get("hp", 0.0)), 1.0) and _approx(float(company_boat.get("engine", 0.0)), 1.0), "Restored company engine itemUid, raw hp=1.0, and projection persist through Records.initialize")
	var company_spare_after: Dictionary = company_boat.moduleCondition.items.get(spare_uid, {})
	check(str(company_spare_after.get("location", "")) == "locker" and _approx(float(company_spare_after.get("hp", 0.0)), 0.44) and str(company_spare_after.get("status", "")) == "damaged", "Company boat locker spare remains damaged at hp=0.44")

	# Prove supported Dictionary core context {"state": c.state, "data": c.data} also stages and commits company repair expense atomically.
	check(bool(_damage_at(company_boat, "mount0", 0.40, "shell").get("ok", false)) and bool(Records.publish(company_boat).get("ok", false)), "Damage company mount0 to 0.60 for Dictionary context company repair check")
	var dict_ctx: Dictionary = {"state": c.state, "data": c.data}
	var q_dict: Dictionary = EquipmentOwnerService.owner_service_quote(company_owner, home, company_boat, dict_ctx)
	var op_before_dict: int = int(book.get("operating", 0))
	var log_len_before_dict: int = book.log.size()
	var coins_before_dict: int = int(company_owner.coins)
	var res_dict: Dictionary = EquipmentOwnerService.repair_owner_boat(company_owner, home, company_boat, dict_ctx)
	check(bool(q_dict.get("ok", false)) and bool(res_dict.get("ok", false)) and int(company_owner.coins) == coins_before_dict - int(q_dict.cost) and int(book.get("operating", 0)) == op_before_dict + int(q_dict.cost) and book.log.size() == log_len_before_dict + 1 and is_same(c.state.shippingCompanies[company_id], book_ref), "Supported Dictionary core context atomically stages and commits company repair expense without late failure")

	# Verify legacy NPC boat without moduleCondition retains legacy 1-worker-day repair without auto-seeding moduleCondition.
	var legacy_owner: Dictionary = c.fleet_owner("patrol-4")
	var legacy_port: Dictionary = c.port("brass_haven")
	legacy_owner["atPort"] = str(legacy_port.get("id", ""))
	_fund_owner_from_treasury(c, legacy_port, legacy_owner, 1000)
	var legacy_boat: Dictionary = legacy_owner.boats[0]
	legacy_boat.erase("moduleCondition")
	legacy_boat["hp"] = float(legacy_boat.maxHp) - 15.0
	legacy_boat["supplies"] = 3.0
	legacy_port["availableWorkers"] = 10.0
	legacy_port["_yardWorkersUsed"] = 0.0
	var leg_coins_before: int = int(legacy_owner.coins)
	var leg_hp_before: float = float(legacy_boat.hp)
	Fleets._repair(legacy_owner, legacy_port, legacy_boat, c)
	check(not legacy_boat.has("moduleCondition") and float(legacy_boat.hp) > leg_hp_before and int(legacy_owner.coins) == leg_coins_before - 100, "Legacy NPC hull without moduleCondition uses legacy repair without auto-seeding canonical records")


func test_offscreen_canonical_weapon_availability_and_power() -> void:
	var c = _new_campaign(504)
	check(_approx(Core.DISABLE_HP, 0.20) and _approx(Core.REENABLE_HP, 0.30), "Core.DISABLE_HP is 0.20 and Core.REENABLE_HP is 0.30")

	var owner_a: Dictionary = c.fleet_owner("patrol-0")
	var owner_b: Dictionary = c.fleet_owner("patrol-1")
	while owner_a.boats.size() > 1:
		owner_a.boats.pop_back()
	while owner_b.boats.size() > 1:
		owner_b.boats.pop_back()

	var skiff_base: Dictionary = c.hull("tin_skiff")
	# These are isolated power fixtures, not conversions of already registered
	# boats. A real refit must not change an existing hull's immutable origin.
	var boat_a: Dictionary = Damage.create_ship(skiff_base, {"crew": 5, "ammo": 60.0, "fuel": 5.0, "supplies": 2.0})
	var boat_b: Dictionary = Damage.create_ship(skiff_base, {"crew": 5, "ammo": 60.0, "fuel": 5.0, "supplies": 2.0})
	boat_a.uid = "combat:single:a"
	boat_b.uid = "combat:single:b"
	owner_a.boats = [boat_a]
	owner_b.boats = [boat_b]
	boat_a["ammo"] = 60.0
	boat_b["ammo"] = 60.0
	owner_a["morale"] = 85.0
	owner_a["performanceFactor"] = 1.0

	# 1. Single mounted weapon (mount0: stock_primary, mount1: "") from Refit.defaults(base): healthy vs damaged vs disabled.
	var single_loadout: Dictionary = _make_loadout_for_mounts(skiff_base, {"mount0": "stock_primary"})
	check(bool(_seed_canonical_boat(c, boat_a, "combat:single:a", single_loadout).get("ok", false)), "Seed canonical single-mount fit on boat_a")
	check(bool(_seed_canonical_boat(c, boat_b, "combat:single:b", single_loadout).get("ok", false)), "Seed canonical single-mount fit on boat_b")

	var wp_healthy: Dictionary = NavalCombat.boat_weapon_power(boat_a, 1.0)
	var fp_healthy: float = NavalCombat.fleet_firepower(owner_a)
	check(bool(wp_healthy.get("ok", false)) and str(wp_healthy.get("mode", "")) == "canonical" and int(wp_healthy.get("mountCount", 0)) == 1, "Healthy single-mount canonical boat reports 1 active mount")
	check(_approx(float(wp_healthy.get("availabilityFactor", 0.0)), 1.0) and float(wp_healthy.get("firepower", 0.0)) > 0.0 and fp_healthy > 0.0, "Healthy single-mount canonical boat has availabilityFactor=1.0 and positive firepower")

	var rng_ok := RandomNumberGenerator.new()
	rng_ok.seed = 9001
	var target_probe: Dictionary = boat_b.duplicate(true)
	var salvo_healthy: Dictionary = NavalCombat._fire_salvo_side(rng_ok, [boat_a.duplicate(true)], [target_probe], 1.0, 2.0)
	check(int(salvo_healthy.get("shots", 0)) > 0, "Healthy canonical single-mount boat fires positive salvo shots")

	# Damage sole gun to 0.50 -> firepower scales to 50% of healthy output.
	check(bool(_damage_at(boat_a, "mount0", 0.50, "shell").get("ok", false)), "Damage sole gun mount0 to 0.50")
	check(bool(Records.publish(boat_a).get("ok", false)), "Publish 0.50 damaged mount0")
	var wp_half: Dictionary = NavalCombat.boat_weapon_power(boat_a, 1.0)
	check(_approx(float(wp_half.get("availabilityFactor", 0.0)), 0.50) and _approx(float(wp_half.get("firepower", 0.0)), float(wp_healthy.get("firepower", 0.0)) * 0.50), "Damaged sole gun at 0.50 HP produces_exact 50% offensive power")

	# Disable sole gun at 0.20 (Core.DISABLE_HP) -> firepower is 0.0 and salvo fires 0 shots.
	check(bool(_damage_at(boat_a, "mount0", 0.30, "direct_hit").get("ok", false)), "Disable sole gun mount0 at 0.20")
	check(bool(Records.publish(boat_a).get("ok", false)), "Publish disabled mount0")
	var wp_disabled: Dictionary = NavalCombat.boat_weapon_power(boat_a, 1.0)
	var fp_disabled: float = NavalCombat.fleet_firepower(owner_a)
	check(_approx(float(wp_disabled.get("availabilityFactor", 0.0)), 0.0) and _approx(float(wp_disabled.get("firepower", 0.0)), 0.0) and _approx(fp_disabled, 0.0), "Disabled sole mounted gun produces 0.0 availabilityFactor and 0.0 fleet firepower")

	var ammo_before_dis: float = float(boat_a.ammo)
	var salvo_disabled: Dictionary = NavalCombat._fire_salvo_side(rng_ok, [boat_a], [target_probe], 1.0, 2.0)
	check(int(salvo_disabled.get("shots", 0)) == 0 and _approx(float(boat_a.ammo), ammo_before_dis), "Disabled sole mounted gun fires 0 salvo shots and consumes 0 ammo")

	var enc_disabled: Dictionary = NavalCombat.resolve_encounter(c.state, owner_a, owner_b, {}, {}, 77)
	var enc_ev: Dictionary = enc_disabled.get("event", {}) if enc_disabled.get("event") is Dictionary else {}
	check(bool(enc_disabled.get("ok", false)) and int(enc_ev.get("shotsA", -1)) == 0 and int(enc_ev.get("shotsB", 0)) > 0, "Disabled sole gun fires 0 shots in resolve_encounter while healthy opponent fires normally")

	# 2. Mixed mounted guns (mount0: stock_primary [26.4], mount1: rapid_gun [44.0]): weighted availability.
	var mixed_loadout: Dictionary = _make_loadout_for_mounts(skiff_base, {"mount0": "stock_primary", "mount1": "rapid_gun"})
	var mixed_boat: Dictionary = Damage.create_ship(skiff_base, {"crew": 5, "ammo": 80, "fuel": 5, "supplies": 2})
	mixed_boat["uid"] = "combat:mixed:a"
	owner_a.boats = [mixed_boat]
	check(bool(_seed_canonical_boat(c, mixed_boat, "combat:mixed:a", mixed_loadout).get("ok", false)), "Seed canonical two-mount mixed weapon fit")

	var wp_mix_full: Dictionary = NavalCombat.boat_weapon_power(mixed_boat, 1.0)
	var full_power: float = float(wp_mix_full.get("firepower", 0.0))
	check(int(wp_mix_full.get("mountCount", 0)) == 2 and _approx(float(wp_mix_full.get("availabilityFactor", 0.0)), 1.0) and _approx(float(wp_mix_full.get("healthyOutput", 0.0)), 70.4), "Healthy mixed fit has 2 active mounts and combined output 70.4 (26.4 + 44.0)")

	# Disable mount0 (26.4) while mount1 (44.0) remains healthy -> availabilityFactor = 44.0 / 70.4 = 0.625.
	check(bool(_damage_at(mixed_boat, "mount0", 0.80, "mount0_knocked_out").get("ok", false)), "Disable mount0 on mixed weapon fit")
	check(bool(Records.publish(mixed_boat).get("ok", false)), "Publish disabled mount0 on mixed fit")
	var wp_mix_partial: Dictionary = NavalCombat.boat_weapon_power(mixed_boat, 1.0)
	var partial_power: float = float(wp_mix_partial.get("firepower", 0.0))
	check(_approx(float(wp_mix_partial.get("availabilityFactor", 0.0)), 44.0 / 70.4) and partial_power > 0.0 and partial_power < full_power and _approx(partial_power, full_power * (44.0 / 70.4)), "Disabling one mount in a mixed fit weights remaining power by actual mounted weapon output")

	var salvo_mix_partial: Dictionary = NavalCombat._fire_salvo_side(rng_ok, [mixed_boat.duplicate(true)], [target_probe], 1.0, 2.0)
	check(int(salvo_mix_partial.get("shots", 0)) > 0, "Remaining active mount1 still fires in salvo when mount0 is disabled")

	# Canonical installed torpedo weapon applies 1.8 torpedo multiplier (light_torpedo: 38 * 0.65 * 1.8 = 44.46).
	var torp_loadout: Dictionary = _make_loadout_for_mounts(skiff_base, {"mount0": "light_torpedo"})
	var can_torp_boat: Dictionary = Damage.create_ship(skiff_base, {"crew": 5, "ammo": 80, "fuel": 5, "supplies": 2})
	can_torp_boat["uid"] = "combat:torp:a"
	check(bool(_seed_canonical_boat(c, can_torp_boat, "combat:torp:a", torp_loadout).get("ok", false)), "Seed canonical torpedo fit on skiff")
	var wp_can_torp: Dictionary = NavalCombat.boat_weapon_power(can_torp_boat, 1.0)
	check(bool(wp_can_torp.get("ok", false)) and _approx(float(wp_can_torp.get("healthyOutput", 0.0)), 38.0 * 0.65 * 1.8), "Canonical mounted torpedo weapon applies 1.8 torpedo multiplier")

	# 3. Locker-only weapons (all hardpoints empty, weapons in locker) contribute 0.0 power and fire 0 shots.
	var empty_loadout: Dictionary = _make_loadout_for_mounts(skiff_base, {})
	var locker_boat: Dictionary = Damage.create_ship(skiff_base, {"crew": 5, "ammo": 80, "fuel": 5, "supplies": 2})
	locker_boat["uid"] = "combat:locker:a"
	owner_a.boats = [locker_boat]
	check(bool(_seed_canonical_boat(c, locker_boat, "combat:locker:a", empty_loadout).get("ok", false)), "Seed canonical boat with empty weapon hardpoints")
	var locker_gun: Dictionary = Core.accept_acquired_item(locker_boat.moduleCondition, {
		"acquired": true,
		"family": "weapons",
		"typeId": "rapid_gun",
		"originHullType": "tin_skiff",
		"location": "locker",
		"hp": 1.0,
		"cause": "",
		"mountCount": Refit.hardpoints(skiff_base).size(),
		"hullType": "tin_skiff",
		"knownUids": []
	})
	check(bool(locker_gun.get("ok", false)) and bool(Records.publish(locker_boat).get("ok", false)), "Accept healthy rapid_gun in locker while all hardpoints are empty")

	var wp_locker: Dictionary = NavalCombat.boat_weapon_power(locker_boat, 1.0)
	var salvo_locker: Dictionary = NavalCombat._fire_salvo_side(rng_ok, [locker_boat], [target_probe], 1.0, 2.0)
	check(bool(wp_locker.get("ok", false)) and int(wp_locker.get("mountCount", -1)) == 0 and _approx(float(wp_locker.get("firepower", -1.0)), 0.0) and _approx(NavalCombat.fleet_firepower(owner_a), 0.0) and int(salvo_locker.get("shots", -1)) == 0, "Locker-only weapons contribute 0.0 firepower and fire 0 shots without falling back to spec.damage")

	# 4. Paired all-legacy fleetpower and retreat baseline checks against NavalOrders.fleet_performance.
	var leg_owner: Dictionary = c.fleet_owner("patrol-2")
	leg_owner["kind"] = "trader"
	leg_owner["morale"] = 85.0
	leg_owner["performanceFactor"] = 1.0

	var leg_gun_no_mount: Dictionary = Damage.create_ship(skiff_base, {"crew": 5, "ammo": 60, "fuel": 5, "supplies": 2})
	leg_gun_no_mount.spec.erase("weaponMounts")
	leg_owner.boats = [leg_gun_no_mount]
	check(_approx(NavalCombat.fleet_firepower(leg_owner), float(NavalOrders.fleet_performance(leg_owner).get("firepower", -1.0))), "All-legacy no-mount gun fleet_firepower matches NavalOrders.fleet_performance.firepower")

	var torp_spec: Dictionary = c.hull("reed_stinger") if not c.hull("reed_stinger").is_empty() else {"id": "reed_stinger", "name": "Reed Stinger", "hp": 180.0, "armor": 3.0, "speed": 136.0, "turn": 2.7, "crewMin": 4, "crewOptimal": 6, "crewMax": 9, "cargo": 55.0, "weapon": "torpedo", "damage": 38.0, "fireRate": 0.65, "range": 460.0, "size": 16.0, "pumps": 2.6}
	var leg_torp_no_mount: Dictionary = Damage.create_ship(torp_spec, {"crew": 6, "ammo": 60, "fuel": 5, "supplies": 2})
	leg_torp_no_mount.spec.erase("weaponMounts")
	leg_owner.boats = [leg_torp_no_mount]
	var old_torp_fp: float = float(NavalOrders.fleet_performance(leg_owner).get("firepower", -1.0))
	check(_approx(NavalCombat.boat_weapon_power(leg_torp_no_mount, 1.0).get("healthyOutput", -1.0), float(torp_spec.get("damage", 38.0)) * float(torp_spec.get("fireRate", 0.65))) and _approx(NavalCombat.fleet_firepower(leg_owner), old_torp_fp), "All-legacy no-mount torpedo boat preserves dmg*fr*wf without 1.8 multiplier and matches NavalOrders.fleet_performance")

	# Legacy trader retreat threshold check around old_torp_fp * 1.1 when hpRatio < 0.82.
	leg_torp_no_mount["hp"] = float(leg_torp_no_mount.maxHp) * 0.75
	check(not NavalCombat._should_withdraw_side(leg_owner, 1, old_torp_fp * 1.05) and NavalCombat._should_withdraw_side(leg_owner, 1, old_torp_fp * 1.15), "All-legacy trader retreat decision matches legacy NavalOrders.fleet_performance firepower * 1.1 threshold")
	leg_torp_no_mount["hp"] = float(leg_torp_no_mount.maxHp)

	var leg_mounted: Dictionary = Damage.create_ship(skiff_base, {"crew": 5, "ammo": 60, "fuel": 5, "supplies": 2})
	leg_mounted.spec = Refit.effective_spec(skiff_base, _make_loadout_for_mounts(skiff_base, {"mount0": "stock_primary", "mount1": "light_torpedo"}))
	leg_owner.boats = [leg_gun_no_mount, leg_torp_no_mount, leg_mounted]
	check(_approx(NavalCombat.fleet_firepower(leg_owner), float(NavalOrders.fleet_performance(leg_owner).get("firepower", -1.0))), "Mixed all-legacy fleet (no-mount gun, no-mount torpedo, mounted gun+torpedo) matches NavalOrders.fleet_performance")

	leg_owner["morale"] = 51.0
	Fleets._performance(leg_owner)
	check(_approx(NavalCombat.fleet_firepower(leg_owner), float(NavalOrders.fleet_performance(leg_owner).get("firepower", -1.0))), "Mixed all-legacy fleet with reduced morale/performanceFactor matches NavalOrders.fleet_performance")

	leg_gun_no_mount["ammo"] = 0.0
	check(_approx(NavalCombat.fleet_firepower(leg_owner), float(NavalOrders.fleet_performance(leg_owner).get("firepower", -1.0))), "Mixed all-legacy fleet with zero-ammo hull matches NavalOrders.fleet_performance")

	# 5. Corrupt/foreign boat and negative/nonfinite inputs never produce negative or nonfinite power.
	var bad_boat: Dictionary = boat_b.duplicate(true)
	bad_boat["ammo"] = -10.0
	var wp_neg_ammo: Dictionary = NavalCombat.boat_weapon_power(bad_boat, 1.0)
	var wp_nan_perf: Dictionary = NavalCombat.boat_weapon_power(boat_b, NAN)
	var wp_neg_perf: Dictionary = NavalCombat.boat_weapon_power(boat_b, -2.0)
	bad_boat["moduleCondition"] = "corrupt"
	var wp_corrupt: Dictionary = NavalCombat.boat_weapon_power(bad_boat, 1.0)
	var foreign_boat: Dictionary = boat_b.duplicate(true)
	foreign_boat.erase("moduleCondition")
	foreign_boat["equipmentCondition"] = 99
	var wp_foreign: Dictionary = NavalCombat.boat_weapon_power(foreign_boat, 1.0)
	check(is_finite(float(wp_neg_ammo.get("firepower", NAN))) and float(wp_neg_ammo.get("firepower", -1.0)) == 0.0, "Negative ammo clamps to 0.0 firepower")
	check(is_finite(float(wp_nan_perf.get("firepower", NAN))) and float(wp_nan_perf.get("firepower", -1.0)) == 0.0 and is_finite(float(wp_neg_perf.get("firepower", NAN))) and float(wp_neg_perf.get("firepower", -1.0)) == 0.0, "Nonfinite or negative perf_factor clamps to 0.0 firepower")
	check(not bool(wp_corrupt.get("ok", true)) and is_finite(float(wp_corrupt.get("firepower", NAN))) and float(wp_corrupt.get("firepower", -1.0)) == 0.0, "Corrupt moduleCondition returns ok=false and 0.0 firepower")
	check(not bool(wp_foreign.get("ok", true)) and is_finite(float(wp_foreign.get("firepower", NAN))) and float(wp_foreign.get("firepower", -1.0)) == 0.0, "Foreign condition key returns ok=false and 0.0 firepower")
