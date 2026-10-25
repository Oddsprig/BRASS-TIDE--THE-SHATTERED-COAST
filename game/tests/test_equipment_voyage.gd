extends SceneTree
## Unrun SceneTree gate for the frozen integrated equipment runtime.
## One legal public encounter on main.tscn: Main.begin_battle, one Battle.update
## with injected shells, Main.settle_battle, Main.return_to_campaign, then
## SaveValidation.validate, Campaign.restore, and paid EquipmentService.repair.
## There is no commit_fleet. Process, physics, audio and music stay stopped.
## The save directory is a fresh user-data folder, never the portable voyage.
const Battle = preload("res://scripts/battle.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Economy = preload("res://scripts/economy.gd")
const EquipmentService = preload("res://scripts/equipment_service.gd")
const FleetSupport = preload("res://scripts/fleet_support.gd")
const Money = preload("res://scripts/money.gd")
const SaveValidation = preload("res://scripts/save_validation.gd")

var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL equipment_voyage: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.audio.enabled = false
	game.music.enabled = false
	game.set_process(false)
	game.set_physics_process(false)
	game.paused = true
	game.save_directory = OS.get_user_data_dir().path_join("equipment-voyage-%d" % Time.get_ticks_usec())
	await process_frame
	game.audio.enabled = false
	game.music.enabled = false
	game.set_process(false)
	game.set_physics_process(false)
	game.new_game()
	game.paused = true
	game.set_process(false)
	game.set_physics_process(false)
	var fleet: Array = game.core.state.get("fleet", [])
	check(game.mode == "campaign" and fleet.size() == 1, "synthetic career publishes one starter hull")
	if fleet.is_empty():
		await finish(game)
		return
	var flag_uid: String = str(fleet[0].get("uid", ""))
	check(fleet[0].get("moduleCondition") is Dictionary and not part_map(fleet[0]).is_empty(), "starter hull is a canonical owner before battle")
	fund(game)
	var bought: Dictionary = buy_three(game)
	check(bool(bought.get("ok", false)), str(bought.get("message", "three synthetic hulls joined")))
	if not bought.get("ok", false):
		await finish(game)
		return
	var support: Dictionary = game.core.find_boat(str(bought.support))
	var stored: Dictionary = game.core.find_boat(str(bought.stored))
	var sacrifice: Dictionary = game.core.find_boat(str(bought.sacrifice))
	var reserved: Dictionary = FleetSupport.reserve(game.core, str(support.uid))
	check(bool(reserved.get("ok", false)) and bool(support.get("supportOnly", false)), "support reserve is marked supportOnly through FleetSupport.reserve")
	var laid_up: Dictionary = game.core.toggle_storage(str(stored.uid))
	var port_id: String = str(game.core.current_port().get("id", ""))
	check(bool(laid_up.get("ok", false)) and str(stored.get("storedPort", "")) == port_id, "stored reserve is laid up through toggle_storage: " + str(laid_up.get("message", "")))
	var support_before: Dictionary = fingerprint(support)
	var stored_before: Dictionary = fingerprint(stored)
	var sacrifice_parts: Dictionary = part_map(sacrifice)
	check(not sacrifice_parts.is_empty() and not support_before.parts.is_empty() and not stored_before.parts.is_empty(), "support, stored and sacrifice hulls each have their own parts")
	var combat_uids: Array = []
	for boat in FleetSupport.combat(game.core):
		combat_uids.append(str(boat.get("uid", "")))
	check(combat_uids == [flag_uid, str(sacrifice.uid)], "only the flagship and the sacrifice hull are combat deployments")
	check(Money.total(game.core.state) == int(game.core.state.coinSupply), "synthetic hull funding stays inside the coin ledger")
	game.begin_battle([game.core.hull("bilge_punt")], {"kind": "patrol", "id": "equipment-voyage", "ownerId": "", "aggression": false, "name": "Open water"})
	game.paused = true
	game.set_process(false)
	game.set_physics_process(false)
	check(game.mode == "battle" and not game.battle.is_empty(), "Main.begin_battle opened a real battle")
	if game.battle.is_empty():
		await finish(game)
		return
	var flagship: Dictionary = ship_by_uid(game.battle, flag_uid)
	var doomed: Dictionary = ship_by_uid(game.battle, str(sacrifice.uid))
	check(is_same(flagship, game.core.find_boat(flag_uid)) and is_same(doomed, sacrifice), "deployed hulls are the campaign dictionaries")
	check(ship_by_uid(game.battle, str(support.uid)).is_empty() and ship_by_uid(game.battle, str(stored.uid)).is_empty(), "support and stored reserves are not deployed")
	check(Battle.set_order(game.battle, "hold") == "hold", "player hulls hold so this encounter is one update")
	var enemies: Array = []
	for ship in game.battle.ships:
		if str(ship.get("team", "")) == "enemy" and not bool(ship.get("sunk", false)):
			enemies.append(ship)
	check(enemies.size() == 1, "the patrol is one spec hull, not an owner fleet")
	var flag_parts_before: Dictionary = part_map(flagship)
	var before_hit: Dictionary = fingerprint(flagship)
	push_shell(game.battle, flagship, "enemy", 54.0, "bow")
	push_shell(game.battle, flagship, "enemy", 54.0, "bow")
	push_shell(game.battle, doomed, "enemy", 2000.0, "waterline")
	for enemy in enemies:
		push_shell(game.battle, enemy, "player", 2000.0, "waterline")
	Battle.update(game.battle, 1.0 / 30.0, {})
	flagship = ship_by_uid(game.battle, flag_uid)
	doomed = ship_by_uid(game.battle, str(sacrifice.uid))
	var struck: Dictionary = part_map(flagship)
	var sunk_parts: Dictionary = part_map(doomed)
	var hit_print: Dictionary = fingerprint(flagship)
	check(str(game.battle.get("result", "")) == "won", "one Battle.update ends the encounter as won")
	check(is_same(flagship, game.core.find_boat(flag_uid)) and not bool(flagship.get("sunk", false)), "the surviving hull is still the same unsunk campaign dictionary")
	check(bool(doomed.get("sunk", false)), "the sacrifice hull sinks from the live shell")
	check(parts_damaged(flag_parts_before, struck), "bow shells lower installed part hp on the live owner")
	check(not parts_rose(flag_parts_before, struck), "the live hit does not raise any part")
	check(not stores_rose(before_hit, hit_print), "the live update does not refill crew, fuel, ammo, kits or the locker")
	game.settle_battle()
	game.paused = true
	check(is_same(game.core.find_boat(flag_uid), flagship), "settlement keeps the surviving dictionary")
	check(game.core.find_boat(str(sacrifice.uid)).is_empty(), "the sunk hull leaves the fleet")
	var wreck: Dictionary = friendly_wreck(game.core.state, str(sacrifice.uid))
	check(not wreck.is_empty() and str(wreck.get("equipmentCustody", "")) == "wreck", "the sunk hull's parts are on one wreck record")
	check(str(doomed.get("equipmentRetiredTo", "")) == str(wreck.get("id", "")) and not doomed.has("moduleCondition"), "the sunk dictionary retires its condition onto that wreck")
	for uid in sacrifice_parts.keys():
		check(uid_holders(game.core.state, str(uid)) == 1, "part %s has one custody owner after settlement" % str(uid))
	check(same_parts(sunk_parts, part_map_of(wreck.get("sourceModuleCondition", {})), true), "the wreck keeps the sunk hull's ids, hp, cause and status")
	game.return_to_campaign()
	game.paused = true
	var saved_flag: Dictionary = game.core.find_boat(flag_uid)
	check(is_same(saved_flag, flagship), "return_to_campaign saves the same hull dictionary")
	check(not stores_rose(hit_print, fingerprint(saved_flag)), "campaign return does not refill crew, fuel, ammo, kits or the locker")
	check(same_parts(struck, part_map(saved_flag), true), "campaign return keeps the struck part ids, hp, cause and status")
	var save_path: String = game.save_directory.path_join("voyage.json")
	var save_text: String = FileAccess.get_file_as_string(save_path)
	check(not save_text.is_empty() and game.save_directory != ProjectSettings.globalize_path("res://saves"), "the round trip is an isolated non-empty save")
	var parsed = JSON.parse_string(save_text)
	check(parsed is Dictionary, "the campaign save parses")
	if not parsed is Dictionary:
		await finish(game)
		return
	var gate: Dictionary = SaveValidation.validate(parsed.duplicate(true), game.data)
	check(bool(gate.get("ok", false)), "SaveValidation.validate accepts the battle career: " + str(gate.get("message", "")))
	var restored_campaign = Campaign.new(game.data)
	var restored: Dictionary = restored_campaign.restore(JSON.parse_string(save_text))
	check(bool(restored.get("ok", false)), "Campaign.restore accepts the same save: " + str(restored.get("message", "")))
	if not restored.get("ok", false):
		await finish(game)
		return
	var back_flag: Dictionary = restored_campaign.find_boat(flag_uid)
	var back_support: Dictionary = restored_campaign.find_boat(str(support.uid))
	var back_stored: Dictionary = restored_campaign.find_boat(str(stored.uid))
	var back_wreck: Dictionary = friendly_wreck(restored_campaign.state, str(sacrifice.uid))
	check(same_print(hit_print, fingerprint(back_flag)), "restore keeps the struck ids, hp, cause, counter, hull hp and stores")
	check(same_print(support_before, fingerprint(back_support)), "restore leaves the support reserve unchanged")
	check(same_print(stored_before, fingerprint(back_stored)), "restore leaves the stored reserve unchanged")
	check(str(back_wreck.get("equipmentCustody", "")) == "wreck" and same_parts(sunk_parts, part_map_of(back_wreck.get("sourceModuleCondition", {})), true), "restore keeps the wreck ids, hp, cause and status")
	for uid in sacrifice_parts.keys():
		check(uid_holders(restored_campaign.state, str(uid)) == 1, "restored part %s still has one custody owner" % str(uid))
	check(restored_campaign.find_boat(str(sacrifice.uid)).is_empty(), "restore does not put the sunk hull back on the fleet")
	prove_repair(restored_campaign, back_flag, int(restored_campaign.state.coins))
	await finish(game)

func prove_repair(core, boat: Dictionary, coins_before: int) -> void:
	var port: Dictionary = core.current_port()
	var before: Dictionary = fingerprint(boat)
	var stocks_before: Dictionary = stock_snapshot(port)
	var quote: Dictionary = EquipmentService.service_quote(core, boat, port)
	check(bool(quote.get("ok", false)), "service_quote reads the restored hull: " + str(quote.get("error", quote.get("message", ""))))
	check(int(quote.get("equipmentCount", 0)) > 0 and int(quote.get("cost", 0)) > 0, "the quote charges coins for the combat deficit")
	check(float(quote.get("workerDays", 0.0)) > 0.0 and (int(quote.get("ordinary", 0)) > 0 or int(quote.get("expert", 0)) > 0), "the quote charges shipwright or specialist labor")
	check(int(quote.get("materials", 0)) > 0 or float(quote.get("purchase", 0.0)) > 0.0 or not (quote.get("equipmentMaterials", {}) as Dictionary).is_empty(), "the quote charges repair materials or kits")
	check(same_print(before, fingerprint(boat)), "quoting does not write the live hull")
	var workers: int = int(port.get("availableWorkers", 0))
	var experts: int = int(port.get("availableSpecialists", 0))
	port.availableWorkers = 0
	port.availableSpecialists = 0
	var blocked_workers: Dictionary = EquipmentService.repair(core, str(boat.uid))
	check(not bool(blocked_workers.get("ok", false)), "repair refuses when the harbor has no free workers: " + str(blocked_workers.get("message", "")))
	check(same_print(before, fingerprint(boat)) and int(core.state.coins) == coins_before and same_stocks(stocks_before, port), "a worker refusal leaves the hull, coins, stocks and parts unchanged")
	port.availableWorkers = workers
	port.availableSpecialists = experts
	var parked: int = int(core.state.coins)
	check(Money.move(core.state, "coins", port, "cash", parked, "Fixture parks the purse", core.state.moneyLog), "the purse can be parked without minting coins")
	var blocked_coins: Dictionary = EquipmentService.repair(core, str(boat.uid))
	check(not bool(blocked_coins.get("ok", false)) and int(core.state.coins) == 0, "repair refuses an empty purse before it spends")
	check(same_print(before, fingerprint(boat)) and same_stocks(stocks_before, port), "a coin refusal leaves the hull, stocks and parts unchanged")
	check(Money.move(port, "cash", core.state, "coins", parked, "Fixture returns the purse", core.state.moneyLog), "the parked purse returns to the captain")
	var stock_before: Dictionary = {}
	for good in ["iron", "copper", "timber", "supplies"]:
		stock_before[good] = float(port.stocks.get(good, 0.0))
	var reserved_before: float = float(port.get("yardWorkersReserved", 0.0))
	var paid: Dictionary = EquipmentService.repair(core, str(boat.uid))
	check(bool(paid.get("ok", false)), "paid repair rehabilitates the restored hull: " + str(paid.get("message", "")))
	if not paid.get("ok", false):
		return
	var bill: Dictionary = paid.get("quote", quote)
	check(int(core.state.coins) == parked - int(bill.get("cost", 0)), "repair spends the quoted coins")
	check(int(bill.get("cost", 0)) == int(quote.get("cost", 0)), "the spent bill is the quote taken before payment")
	for good in (quote.get("equipmentMaterials", {}) as Dictionary).keys():
		check(float(port.stocks.get(good, 0.0)) <= float(stock_before.get(good, 0.0)) - float(quote.equipmentMaterials[good]) + 0.001, "repair consumes %s from harbor stock" % str(good))
	check(float(port.stocks.get("supplies", 0.0)) <= float(stock_before.get("supplies", 0.0)) - float(quote.get("purchase", 0.0)) + 0.001, "repair consumes purchased kits from harbor stock")
	check(float(port.get("yardWorkersReserved", 0.0)) >= reserved_before + float(quote.get("workerDays", 0.0)) - 0.05, "repair reserves the quoted worker-days")
	var after: Dictionary = fingerprint(boat)
	check(same_keyset(before.parts, after.parts) and int(after.seq) == int(before.seq), "repair keeps the same part ids and serial")
	check(absf(float(after.hp) - float(boat.maxHp)) <= 0.05 and float(after.hp) + 0.001 >= float(before.hp), "paid hull repair restores fitted hull hp and does not go past it")
	var healed: bool = true
	for uid in after.parts.keys():
		var item: Dictionary = after.parts[uid]
		if str(item.location) == "locker":
			continue
		if float(item.hp) < 0.999 or str(item.status) != "ok":
			healed = false
	check(healed, "paid repair restores every installed part on the same ids")
	check(int(after.locker) == int(before.locker) and float(after.crew) <= float(before.crew) + 0.001 and float(after.fuel) <= float(before.fuel) + 0.001 and float(after.ammo) <= float(before.ammo) + 0.001, "paid repair does not refill crew, fuel, ammo or the locker")

func fund(game) -> void:
	var state: Dictionary = game.core.state
	var grant: int = 250000
	state.coins = int(state.coins) + grant
	state.coinSupply = int(state.coinSupply) + grant
	var port: Dictionary = game.core.current_port()
	port.shipStock["tin_skiff"] = int(port.shipStock.get("tin_skiff", 0)) + 3
	port.workforce = int(port.get("workforce", 0)) + 160
	port.publicWorkers = 8
	port.workers = 0
	port.recruits = 48
	port.specialists = 32
	port.availableSpecialists = 32
	for good in ["iron", "copper", "timber", "supplies", "fuel", "ammo"]:
		port.stocks[good] = float(port.stocks.get(good, 0.0)) + 800.0
	Economy.sync_workforce(port)
	if port.get("training") is Dictionary and port.training.get("qualified") is Dictionary:
		var qualified: Dictionary = port.training.qualified
		var spare: int = maxi(0, int(port.workforce) - int(qualified.get("sailor", 0)))
		qualified.sailor = int(qualified.get("sailor", 0)) + mini(24, spare)

func buy_three(game) -> Dictionary:
	var uids: Array = []
	for _i in range(3):
		var bought: Dictionary = game.core.buy_boat("tin_skiff")
		if not bought.get("ok", false):
			return {"ok": false, "message": str(bought.get("message", "buy failed"))}
		uids.append(str(game.core.state.fleet.back().uid))
	return {"ok": true, "message": "three hulls joined", "support": uids[0], "stored": uids[1], "sacrifice": uids[2]}

func push_shell(battle: Dictionary, ship: Dictionary, from_team: String, damage: float, section: String) -> void:
	var from_bow: bool = from_team == "enemy"
	var x: float = float(ship.x) + (18.0 if from_bow else -18.0)
	battle.projectiles.append({
		"x": x, "y": float(ship.y), "px": x, "py": float(ship.y),
		"vx": -1500.0 if from_bow else 1500.0, "vy": 0.0, "team": from_team,
		"damage": damage, "penetration": 30.0, "kind": "shell", "section": section,
		"life": 1.0, "owner": "voyage-gate", "radius": 3.0
	})

func ship_by_uid(battle: Dictionary, uid: String) -> Dictionary:
	for ship in battle.get("ships", []):
		if ship is Dictionary and str(ship.get("uid", "")) == uid:
			return ship
	return {}

func friendly_wreck(state: Dictionary, uid: String) -> Dictionary:
	for wreck in state.get("wrecks", []):
		if wreck is Dictionary and str(wreck.get("retiredSourceUid", "")) == uid and bool(wreck.get("friendly", false)):
			return wreck
	return {}

func part_map(boat: Dictionary) -> Dictionary:
	if not boat.get("moduleCondition") is Dictionary:
		return {}
	return part_map_of(boat.moduleCondition)

func part_map_of(condition) -> Dictionary:
	var out: Dictionary = {}
	if not condition is Dictionary or not condition.get("items") is Dictionary:
		return out
	for uid in condition.items.keys():
		var item = condition.items[uid]
		if not item is Dictionary:
			continue
		out[str(uid)] = {
			"hp": float(item.get("hp", 1.0)),
			"status": str(item.get("status", "")),
			"cause": str(item.get("cause", "")),
			"location": str(item.get("location", ""))
		}
	return out

func fingerprint(boat: Dictionary) -> Dictionary:
	var condition = boat.get("moduleCondition", {})
	var seq: int = int(condition.get("nextItemSeq", -1)) if condition is Dictionary else -1
	var mark: float = float(condition.get("legacyEngineSynced", -1.0)) if condition is Dictionary else -1.0
	var locker: int = 0
	var parts: Dictionary = part_map(boat)
	for uid in parts.keys():
		if str(parts[uid].location) == "locker":
			locker += 1
	return {
		"uid": str(boat.get("uid", "")),
		"hp": float(boat.get("hp", 0.0)),
		"crew": float(boat.get("crew", 0.0)),
		"fuel": float(boat.get("fuel", 0.0)),
		"ammo": float(boat.get("ammo", 0.0)),
		"supplies": float(boat.get("supplies", 0.0)),
		"locker": locker,
		"supportOnly": bool(boat.get("supportOnly", false)),
		"storedPort": str(boat.get("storedPort", "")),
		"seq": seq,
		"mark": mark,
		"parts": parts
	}

func parts_damaged(before: Dictionary, after: Dictionary) -> bool:
	if before.is_empty() or not same_keyset(before, after):
		return false
	for uid in before.keys():
		if str(before[uid].location) == "locker":
			continue
		if float(after[uid].hp) < float(before[uid].hp) - 0.001:
			return true
	return false

func parts_rose(before: Dictionary, after: Dictionary) -> bool:
	for uid in before.keys():
		if not after.has(uid):
			return true
		if float(after[uid].hp) > float(before[uid].hp) + 0.001:
			return true
	return false

func same_keyset(before: Dictionary, after: Dictionary) -> bool:
	if before.size() != after.size():
		return false
	for key in before.keys():
		if not after.has(key):
			return false
	return true

func same_stocks(before: Dictionary, port: Dictionary) -> bool:
	for good in before.keys():
		if absf(float(before[good]) - float(port.stocks.get(good, -1.0))) > 0.001:
			return false
	return true

func stock_snapshot(port: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for good in ["iron", "copper", "timber", "supplies"]:
		out[good] = float(port.stocks.get(good, 0.0))
	return out

func same_parts(before: Dictionary, after: Dictionary, exact_hp: bool) -> bool:
	if not same_keyset(before, after):
		return false
	for uid in before.keys():
		if str(before[uid].location) != str(after[uid].location) or str(before[uid].status) != str(after[uid].status) or str(before[uid].cause) != str(after[uid].cause):
			return false
		if exact_hp and absf(float(before[uid].hp) - float(after[uid].hp)) > 0.001:
			return false
		if not exact_hp and float(after[uid].hp) > float(before[uid].hp) + 0.001:
			return false
	return true

func stores_rose(before: Dictionary, after: Dictionary) -> bool:
	if int(after.locker) != int(before.locker):
		return true
	for key in ["crew", "fuel", "ammo", "supplies", "hp"]:
		if float(after[key]) > float(before[key]) + 0.001:
			return true
	return false

func same_print(before: Dictionary, after: Dictionary) -> bool:
	if str(before.uid) != str(after.uid) or int(before.seq) != int(after.seq):
		return false
	if absf(float(before.mark) - float(after.mark)) > 0.001:
		return false
	if bool(before.supportOnly) != bool(after.supportOnly) or str(before.storedPort) != str(after.storedPort):
		return false
	if stores_rose(before, after) or stores_rose(after, before):
		return false
	return same_parts(before.parts, after.parts, true)

func uid_holders(state: Dictionary, uid: String) -> int:
	var count: int = 0
	var groups: Array = [state.get("fleet", []), state.get("boardingPrizes", [])]
	for owner in state.get("fleetOwners", []):
		if owner is Dictionary:
			groups.append(owner.get("boats", []))
	for group in groups:
		for boat in group:
			if boat is Dictionary and boat.get("moduleCondition") is Dictionary:
				var items = boat.moduleCondition.get("items", {})
				if items is Dictionary and items.has(uid):
					count += 1
	for wreck in state.get("wrecks", []):
		if wreck is Dictionary and wreck.get("sourceModuleCondition") is Dictionary:
			var held = wreck.sourceModuleCondition.get("items", {})
			if held is Dictionary and held.has(uid):
				count += 1
	return count

func finish(game):
	if game != null:
		game.queue_free()
	await process_frame
	print("equipment_voyage: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
