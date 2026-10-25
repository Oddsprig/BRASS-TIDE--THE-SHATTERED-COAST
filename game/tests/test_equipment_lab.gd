extends SceneTree
## Focused v0.031 FleetLab canonical equipment initialization & Battle effect fixture.
## Verifies canonical player/enemy sandbox boats, explicit initialization error handling,
## actual gun/engine/pump damage effects over a few Battle.update ticks, and catalogue/career isolation.

const Lab = preload("res://scripts/fleet_lab.gd")
const Battle = preload("res://scripts/battle.gd")
const Damage = preload("res://scripts/damage.gd")
const Refit = preload("res://scripts/refit.gd")
const Condition = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")
const EquipmentCombat = preload("res://scripts/equipment_combat.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Money = preload("res://scripts/money.gd")

var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("EQUIPMENT LAB TEST FAIL: " + message)

func _uid_at(ship: Dictionary, location: String) -> String:
	var snap: Dictionary = Records.snapshot(ship)
	if not snap.get("ok", false):
		return ""
	var item: Dictionary = snap.get("installed", {}).get(location, {})
	return str(item.get("itemUid", ""))

func _initialize() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	check(world is Dictionary and world.get("HULLS") is Array and world.HULLS.size() == 24, "world catalogue loaded with 24 hulls")
	if world.is_empty():
		quit(1)
		return

	# 1. Career isolation baseline
	var career = Campaign.new(world)
	var begun: Dictionary = career.new_game(4242)
	check(begun.get("ok", false), "career baseline initialized")
	# Career construction prices hulls; snapshot after that setup, before any Lab call.
	var world_before: Dictionary = world.duplicate(true)
	var catalog_before: Dictionary = Refit.catalog().duplicate(true)
	var career_snapshot: Dictionary = career.state.duplicate(true)
	var career_coins: int = Money.total(career.state)

	# 2. Canonical creation on both sides, valid mount/socket mapping, and determinism
	var all_weapons_cfg: Dictionary = Lab.preset(world, "all_weapons")
	var built_all: Dictionary = Lab.create(world, all_weapons_cfg, 83)
	check(built_all.get("ok", false) and built_all.get("battle") is Dictionary, "Lab.create succeeds for all_weapons preset")
	var ships_all: Array = built_all.battle.get("ships", [])
	check(ships_all.size() == 5, "all_weapons deploys 1 player and 4 enemy boats")

	var seen_ship_uids: Dictionary = {}
	var seen_item_uids: Dictionary = {}
	var player_count: int = 0
	var enemy_count: int = 0
	for ship in ships_all:
		var uid: String = str(ship.get("uid", ""))
		check(not uid.is_empty() and not seen_ship_uids.has(uid), "unique sandbox hull uid " + uid)
		seen_ship_uids[uid] = true
		if ship.get("team", "") == "player":
			player_count += 1
		elif ship.get("team", "") == "enemy":
			enemy_count += 1
		var st: Dictionary = Damage.get_status(ship)
		check(ship.has("moduleCondition") and EquipmentCombat.is_canonical_owner(ship), "sandbox ship is canonical physical owner " + uid)
		check(str(st.get("equipmentMode", "")) == "canonical" and bool(st.get("equipmentOk", false)), "canonical status valid for " + uid)
		check(str(ship.moduleCondition.get("birthNamespace", "")) == uid, "birthNamespace matches isolated sandbox uid " + uid)
		check(is_equal_approx(float(ship.get("engine", 0.0)), 1.0) and ship.get("refitLocker", {}) == {}, "fresh engine scalar and empty locker on " + uid)
		for item_uid in ship.moduleCondition.get("items", {}).keys():
			var item: Dictionary = ship.moduleCondition.items[item_uid]
			check(not seen_item_uids.has(str(item_uid)), "globally unique sandbox itemUid " + str(item_uid))
			seen_item_uids[str(item_uid)] = true
			check(is_equal_approx(float(item.get("hp", 0.0)), 1.0) and str(item.get("status", "")) == "ok", "fresh working part " + str(item_uid))

	check(player_count == 1 and enemy_count == 4, "both player and enemy teams created canonically")

	var flagship: Dictionary = ships_all[0]
	var flag_snap: Dictionary = Records.snapshot(flagship)
	check(flag_snap.get("ok", false), "flagship Records.snapshot succeeds")
	var installed: Dictionary = flag_snap.get("installed", {})
	check(str(installed.get("mount0", {}).get("typeId", "")) == "stock_primary", "mount0 mapped to stock_primary")
	check(str(installed.get("mount1", {}).get("typeId", "")) == "rapid_gun", "mount1 mapped to rapid_gun")
	check(str(installed.get("mount2", {}).get("typeId", "")) == "fire_rocket", "mount2 mapped to fire_rocket")
	check(str(installed.get("mount3", {}).get("typeId", "")) == "light_torpedo", "mount3 mapped to light_torpedo")
	check(str(installed.get("engine", {}).get("typeId", "")) == "stock_engine", "engine socket mapped to stock_engine")
	check(str(installed.get("armor", {}).get("typeId", "")) == "stock_armor", "armor socket mapped to stock_armor")
	check(str(installed.get("pumps", {}).get("typeId", "")) == "hull_pumps", "pumps socket mapped to hull_pumps")

	var replay_all: Dictionary = Lab.create(world, Lab.preset(world, "all_weapons"), 83)
	check(replay_all.get("ok", false) and replay_all.battle.ships == built_all.battle.ships, "same seed and config reproduce identical canonical ships")

	# 3. 300 DP / 40-boat bounds and explicit Records.initialize error contract
	check(not Lab.inspect(world, Lab.preset(world, "reserve_boundary")).get("ok", true), "over-cap 300 DP roster rejected by inspect")
	var bad_world: Dictionary = world.duplicate(true)
	bad_world.HULLS[0].pumps = -1.0
	var bad_cfg: Dictionary = {"player": [Lab.entry(bad_world, str(bad_world.HULLS[0].id))], "enemy": [Lab.entry(bad_world, "bilge_punt")]}
	check(Lab.inspect(bad_world, bad_cfg).get("ok", false), "malformed pump rating reaches create after fitting inspect")
	var bad_created: Dictionary = Lab.create(bad_world, bad_cfg, 19)
	check(not bad_created.get("ok", true) and not str(bad_created.get("error", "")).is_empty() and not bad_created.has("battle"), "Lab.create returns explicit Lab error contract when Records.initialize fails")

	# 4. Gun damage effect in actual Battle.update (few ticks)
	var b_gun_ok: Dictionary = Lab.create(world, Lab.preset(world, "duel"), 19).battle
	var b_gun_off: Dictionary = Lab.create(world, Lab.preset(world, "duel"), 19).battle
	for b in [b_gun_ok, b_gun_off]:
		b.ships[0].x = 900.0; b.ships[0].y = 850.0; b.ships[0].angle = 0.0
		b.ships[0].supplies = 0.0
		b.ships[1].x = 1080.0; b.ships[1].y = 850.0; b.ships[1].angle = PI
		b.ships[1].ammo = 0.0
	var gun_uid: String = _uid_at(b_gun_off.ships[0], "mount0")
	var gun_dmg: Dictionary = Condition.apply_component_damage(b_gun_off.ships[0].moduleCondition, {"itemUid": gun_uid, "loss": 1.0, "cause": "Lab gun test"})
	var gun_pub: Dictionary = Records.publish(b_gun_off.ships[0])
	check(gun_dmg.get("ok", false) and gun_pub.get("ok", false), "disabling sandbox mount0 succeeds")
	var start_ammo: float = float(b_gun_ok.ships[0].ammo)
	var start_enemy_hp: float = float(b_gun_ok.ships[1].hp)
	for _i in range(20):
		Battle.update(b_gun_ok, 1.0 / 30.0, {})
		Battle.update(b_gun_off, 1.0 / 30.0, {})
	check(float(b_gun_ok.ships[0].ammo) < start_ammo and float(b_gun_ok.ships[1].hp) < start_enemy_hp, "intact sandbox gun fires and damages target in Battle.update")
	check(is_equal_approx(float(b_gun_off.ships[0].ammo), start_ammo) and is_equal_approx(float(b_gun_off.ships[1].hp), start_enemy_hp), "disabled sandbox mount0 fires zero shots in Battle.update")

	# 5. Engine damage effect in actual Battle.update (few ticks)
	var b_eng_ok: Dictionary = Lab.create(world, Lab.preset(world, "duel"), 19).battle
	var b_eng_off: Dictionary = Lab.create(world, Lab.preset(world, "duel"), 19).battle
	for b in [b_eng_ok, b_eng_off]:
		Battle.set_autopilot(b, false)
		b.ships[0].x = 600.0; b.ships[0].y = 850.0; b.ships[0].angle = 0.0
		b.ships[0].supplies = 0.0
		b.ships[1].x = 1800.0; b.ships[1].y = 850.0; b.ships[1].ammo = 0.0
	var eng_uid: String = _uid_at(b_eng_off.ships[0], "engine")
	var eng_dmg: Dictionary = Condition.apply_component_damage(b_eng_off.ships[0].moduleCondition, {"itemUid": eng_uid, "loss": 1.0, "cause": "Lab engine test"})
	var eng_pub: Dictionary = Records.publish(b_eng_off.ships[0])
	check(eng_dmg.get("ok", false) and eng_pub.get("ok", false) and is_equal_approx(float(b_eng_off.ships[0].engine), 0.0), "disabling sandbox engine publishes 0.0 engine scalar")
	for _i in range(12):
		Battle.update(b_eng_ok, 1.0 / 30.0, {"forward": true})
		Battle.update(b_eng_off, 1.0 / 30.0, {"forward": true})
	check(float(b_eng_ok.ships[0].x) > 605.0 and float(b_eng_ok.ships[0].fuel) < 120.0, "intact sandbox engine accelerates hull and consumes fuel")
	check(is_equal_approx(float(b_eng_off.ships[0].x), 600.0), "disabled sandbox engine prevents thrust in Battle.update")

	# 6. Pump damage effect in actual Battle.update (few ticks)
	var b_pump_ok: Dictionary = Lab.create(world, Lab.preset(world, "duel"), 19).battle
	var b_pump_off: Dictionary = Lab.create(world, Lab.preset(world, "duel"), 19).battle
	for b in [b_pump_ok, b_pump_off]:
		b.ships[0].ammo = 0.0; b.ships[1].ammo = 0.0
		b.ships[0].supplies = 0.0
		b.ships[0].water = 200.0
		b.ships[0].breaches = [{"x": 0.0, "y": 0.0, "area": 90.0}]
	var pump_uid: String = _uid_at(b_pump_off.ships[0], "pumps")
	var pump_dmg: Dictionary = Condition.apply_component_damage(b_pump_off.ships[0].moduleCondition, {"itemUid": pump_uid, "loss": 1.0, "cause": "Lab pump test"})
	var pump_pub: Dictionary = Records.publish(b_pump_off.ships[0])
	check(pump_dmg.get("ok", false) and pump_pub.get("ok", false), "disabling sandbox integral pumps succeeds")
	check(float(Damage.get_status(b_pump_ok.ships[0]).get("pump", 0.0)) > 0.0 and is_equal_approx(float(Damage.get_status(b_pump_off.ships[0]).get("pump", 1.0)), 0.0), "pump status reflects canonical pump damage")
	for _i in range(15):
		Battle.update(b_pump_ok, 1.0 / 30.0, {})
		Battle.update(b_pump_off, 1.0 / 30.0, {})
	check(float(b_pump_off.ships[0].water) > float(b_pump_ok.ships[0].water) + 1.0, "disabled sandbox pumps accumulate more flood water in Battle.update")

	# 7. Catalogue and career state isolation
	check(world == world_before and Refit.catalog() == catalog_before, "sandbox battles never mutate world hull or equipment catalogues")
	check(career.state == career_snapshot and Money.total(career.state) == career_coins, "sandbox battles never mutate career state or coins")

	print("EQUIPMENT LAB: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
