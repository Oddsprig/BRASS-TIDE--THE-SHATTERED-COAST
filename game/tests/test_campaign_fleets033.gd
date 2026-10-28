extends SceneTree
## Short v0.033 scenarios using the existing owners, selectors and skirmish.
const Campaign = preload("res://scripts/campaign.gd")
const AI = preload("res://scripts/naval_ai.gd")
const Orders = preload("res://scripts/naval_orders.gd")
const Economy = preload("res://scripts/economy.gd")
const Money = preload("res://scripts/money.gd")
const Factions = preload("res://scripts/factions.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Goods = preload("res://scripts/goods.gd")

var checks: int = 0
var failures: int = 0
var c
var baseline: Dictionary = {}


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL campaign fleets033: ", message)


func _initialize() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c = Campaign.new(world)
	check(bool(c.new_game(3301).ok), "Actual campaign initializes")
	baseline = c.state.duplicate(true)
	_test_at_sea_orders()
	c.state = baseline.duplicate(true)
	_test_shared_encounters()
	c.state = baseline.duplicate(true)
	_test_batch_days()
	print("campaign fleets033: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _isolate(ids: Array) -> void:
	for owner in c.state.fleetOwners:
		if Orders.is_story_owner(owner):
			continue
		owner.active = ids.has(str(owner.id))
		owner.atPort = ""
		var p: Dictionary = Orders.find_patrol(c.state, owner.id)
		p.active = owner.active
		p.holding = false
		if owner.active:
			var remaining: int = maxi(0, 8000 - int(owner.coins))
			for port in c.state.ports:
				var advance: int = mini(remaining, int(port.governmentPurse))
				check(Money.move(port, "governmentPurse", owner, "coins", advance, "Finite scenario voyage advance", c.state.moneyLog), "Operating advance transfers existing treasury coins")
				remaining -= advance
				if remaining == 0: break
			check(remaining == 0, "Existing treasuries fund the staged voyage")


func _load_timber(owner: Dictionary, qty: int) -> void:
	# Return the old manifest to its actual port, then buy the test cargo.
	var home: Dictionary = c.port(owner.homePort)
	var old_good: String = str(owner.tradeGood)
	var old_qty: float = minf(float(owner.tradeCargo), float(owner.cargo.get(old_good, 0)))
	owner.cargo[old_good] -= old_qty
	home.stocks[old_good] += old_qty
	owner.tradeCargo = 0.0
	owner.tradeGood = "timber"
	var wallet: Dictionary = {"coins": owner.coins, "cargo": owner.cargo}
	var bought: Dictionary = Economy.transact(home, wallet, "timber", qty, "buy", float(Orders.fleet_reserves(owner).capacity))
	check(bool(bought.ok), "Fixture loads finite paid timber: " + str(bought.get("message", "")))
	owner.coins = wallet.coins
	owner.tradeCargo = float(bought.get("qty", 0))


func _test_at_sea_orders() -> void:
	_isolate(["patrol-0", "patrol-1", "patrol-2"])
	var raider: Dictionary = c.fleet_owner("patrol-0")
	var trader: Dictionary = c.fleet_owner("patrol-1")
	var guard: Dictionary = c.fleet_owner("patrol-2")
	var rp: Dictionary = Orders.find_patrol(c.state, raider.id)
	var tp: Dictionary = Orders.find_patrol(c.state, trader.id)
	var gp: Dictionary = Orders.find_patrol(c.state, guard.id)
	rp.x = 4200.0; rp.y = 3100.0
	# All three actors are in the actual 055 local observation radius.
	tp.x = 4700.0; tp.y = 3100.0
	gp.x = 4500.0; gp.y = 3100.0
	tp.active = false
	AI.build_order(c.state, raider, "raid", raider.homePort, "Generic raid already at sea.")
	AI.build_order(c.state, guard, "patrol", guard.homePort, "Generic patrol already at sea.")
	check(str(Orders.select_raider_order(c.state, raider, "").targetOwnerId).is_empty(), "A lost chart convoy is not a selectable target")
	_load_timber(trader, 8)
	# Under-defended shipment: rounds stay conserved in its hold, not in guns.
	# This preserves real reserves while exercising the new risk-aware selector.
	for boat in trader.boats:
		trader.cargo.ammo += float(boat.ammo) / float(Goods.ROUNDS_PER_CASE)
		boat.ammo = 0.0
	tp.active = true
	var stale: String = str(c.state.ports[0].id)
	var current: String = str(c.state.ports[1].id)
	var changed: String = str(c.state.ports[2].id)
	AI.build_order(c.state, trader, "deliver", stale, "Old merchant route snapshot.")
	tp.to = current
	var picked: Dictionary = Orders.select_raider_order(c.state, raider, "")
	check(picked.targetOwnerId == trader.id and picked.destination == current, "Actual raider selector uses live convoy and current route over stale order")
	check(str(Orders.select_patrol_order(c.state, guard, "").targetOwnerId) == str(raider.id), "Actual patrol selector responds to the live raider at sea")
	var company: Dictionary = c.fleet_owner("patrol-3")
	company.playerCompany = true
	AI.build_order(c.state, company, "trade", changed, "Player company charter.")
	var company_order_id: String = str(company.order.id)
	var story: Dictionary = c.fleet_owner("story-0")
	var story_order_id: String = str(story.order.id)
	var recovering: Dictionary = c.fleet_owner("patrol-5")
	AI.build_order(c.state, recovering, "repair", changed, "Existing paid repair diversion.")
	var coins: int = Money.total(c.state)
	AI.tick(c, 1)
	print("campaign fleets033 orders: ", raider.reason, " | ", guard.reason)
	check(raider.order.targetOwnerId == trader.id and raider.destination == current and raider.atPort == "", "Daily tick retasks an already sailing raider without docking")
	check(guard.order.purpose == "intercept" and guard.order.targetOwnerId == raider.id and guard.atPort == "", "Daily tick turns an already sailing patrol toward the raider")
	check(str(raider.reason).contains(str(trader.name)) and str(guard.reason).contains(str(raider.name)), "Existing order reasons expose each actual target")
	check(company.order.id == company_order_id and company.destination == changed and company.reason == "Player company charter.", "Daily AI preserves player-company intent")
	check(story.order.id == story_order_id, "Daily AI preserves the authored story order")
	check(recovering.order.purpose == "repair" and recovering.destination == changed, "Daily retargeting preserves a recovery diversion")
	c.state.econDay += 1; c.state.day += 1.0
	tp.to = changed
	AI.tick(c, 1)
	check(raider.order.targetOwnerId == trader.id and raider.destination == changed and trader.destination == stale, "Next daily response follows the changed live route without rewriting the target")
	check(int(raider.get("lastNavalRetargetDay", -1)) == int(c.state.econDay), "Retarget cadence uses the actual campaign day")
	tp.active = false
	AI.tick(c, 1)
	check(str(raider.order.targetOwnerId).is_empty(), "A lost current sighting is cleared, even after today's earlier response")
	tp.active = true
	trader.active = false
	check(Orders.target_destination(c.state, trader).is_empty(), "An inactive target cannot retain a live destination")
	trader.active = true
	for boat in trader.boats:
		boat.sunk = true
	check(Orders.target_destination(c.state, trader).is_empty() and str(Orders.select_raider_order(c.state, raider, "").targetOwnerId).is_empty(), "Actual selector rejects sunk carriers")
	AI.observe(c.state, guard.id) # The guard locally witnesses the ended contact too.
	AI.build_order(c.state, guard, "intercept", stale, "Intercepting the now-sunk target.", trader.id)
	check(guard.order.purpose == "patrol" and str(guard.order.targetOwnerId).is_empty() and not str(guard.reason).contains("now-sunk"), "Lost target rebuild has a coherent generic purpose and reason")
	check(Money.total(c.state) == coins and coins == int(c.state.coinSupply), "Selectors and daily response conserve all actual purses")


func _goods(good: String) -> float:
	var total: float = float(c.state.cargo.get(good, 0))
	for owner in c.state.fleetOwners:
		total += float(owner.cargo.get(good, 0))
	for port in c.state.ports:
		total += float(port.stocks.get(good, 0))
	return total


func _boat_total(key: String) -> float:
	var total: float = 0.0
	for owner in c.state.fleetOwners:
		for boat in owner.boats:
			total += float(boat.get(key, 0))
	return total


func _test_shared_encounters() -> void:
	var ids: Array = []
	for i in range(9):
		ids.append("patrol-%d" % i)
	_isolate(ids)
	Factions.set_relation(c.state, "compact", "forge", -50, "Fixture actual hostile faction pair")
	var origin: Dictionary = c.port_position(str(c.data.START.port))
	for i in range(9):
		var owner: Dictionary = c.fleet_owner(ids[i])
		owner.faction = "compact" if i % 2 == 0 else "forge"
		var p: Dictionary = Orders.find_patrol(c.state, owner.id)
		p.x = float(origin.x) + floor(float(i) / 2.0) * 500.0 + float(i % 2) * 25.0
		p.y = float(origin.y)
	# A loaded, ammunition-depleted merchant yields a real finite prize.
	var merchant: Dictionary = c.fleet_owner("patrol-1")
	_load_timber(merchant, 8)
	var home: Dictionary = c.port(merchant.homePort)
	for boat in merchant.boats:
		home.stocks.ammo += float(boat.ammo) / float(Goods.ROUNDS_PER_CASE)
		boat.ammo = 0.0
	home.stocks.ammo += float(merchant.cargo.ammo)
	merchant.cargo.ammo = 0.0
	AI.ensure(c.state)
	var refused: Dictionary = AI.resolve_encounter(c.state, c.fleet_owner(ids[0]), c.fleet_owner(ids[2]))
	check(not refused.ok and int(c.state.navalAi.encounterCount) == 0 and c.state.navalAi.encounterOwners.is_empty(), "A refused friendly pair spends no encounter or owner allowance")
	refused = AI.resolve_encounter(c.state, c.fleet_owner(ids[0]), c.fleet_owner("story-0"))
	check(not refused.ok and int(c.state.navalAi.encounterCount) == 0, "A refused story pair also spends nothing")
	var coins: int = Money.total(c.state)
	var timber: float = _goods("timber")
	var ammo: float = _boat_total("ammo")
	var crew: float = _boat_total("crew")
	var supplies: float = _boat_total("supplies")
	var player: String = JSON.stringify({"coins": c.state.coins, "cargo": c.state.cargo, "fleet": c.state.fleet})
	var witness: Dictionary = Orders.find_patrol(c.state, ids[0])
	c.state.position = {"x": witness.x, "y": witness.y}
	var messages: Array = AI.tick(c, 1)
	var nav: Dictionary = c.state.navalAi
	check(int(nav.encounterCount) == 4 and nav.encounterOwners.size() == 8 and nav.encounters.size() == 4, "Existing nine owners permit at most four disjoint successful fights")
	var used: Dictionary = {}
	var shots: int = 0
	var rounds: int = 0
	var captured: int = 0
	var kinds: Dictionary = {}
	for event in nav.encounters:
		check(not used.has(event.a) and not used.has(event.b), "Each owner fought once across the actual shared daily scan")
		used[event.a] = true; used[event.b] = true
		shots += int(event.shotsA) + int(event.shotsB)
		rounds += int(event.ammoUsedA) + int(event.ammoUsedB)
		captured += int(event.capturedQty)
		kinds[event.kind] = true
	check(shots > 0 and rounds >= shots and is_equal_approx(ammo - _boat_total("ammo"), float(rounds)), "Actual hostile salvos debit precisely their per-mount finite boat rounds")
	check(captured > 0 and is_equal_approx(_goods("timber"), timber), "Actual prize cargo moves between physical holds without creation or loss")
	check(Money.total(c.state) == coins and coins == int(c.state.coinSupply), "Actual hostile prizes conserve the complete coin supply")
	check(_boat_total("crew") <= crew and _boat_total("supplies") <= supplies, "Combat and damage control create no people or repair supplies")
	check(player == JSON.stringify({"coins": c.state.coins, "cargo": c.state.cargo, "fleet": c.state.fleet}), "Autonomous fights preserve player boats, equipment, cargo and purse")
	check(kinds.has("raid") and kinds.has("patrol") and kinds.has("faction_clash"), "Existing bounded encounter records distinguish raids, patrol actions and faction clashes")
	check(not messages.is_empty() and str(messages[0]).contains("engaged"), "A nearby player receives an actual witnessed outcome")
	for owner in c.state.fleetOwners:
		for boat in owner.boats:
			check(is_finite(float(boat.crew)) and float(boat.crew) >= 0.0 and float(boat.ammo) >= 0.0 and float(boat.supplies) >= 0.0, "Actual boat retains finite nonnegative people and stores")
		check(owner.orders.size() <= 8 and owner.log.size() <= 16, "Owner orders and outcome logs stay bounded")
	check(AI.scan_encounters(c).is_empty() and int(nav.encounterCount) == 4 and nav.encounters.size() == 4, "Repeated mid-day scan shares the daily tick's exhausted budget")
	var saved = JSON.parse_string(JSON.stringify(c.state))
	var restored: Dictionary = c.restore(saved)
	check(bool(restored.ok), "Actual campaign restores the same-day encounter ledger: " + str(restored.get("message", "")))
	check(int(c.state.navalAi.encounterCount) == 4 and c.state.navalAi.encounterOwners.size() == 8 and AI.scan_encounters(c).is_empty(), "Saving and restoring does not grant extra fights")
	c.state.erase("navalAi")
	AI.ensure(c.state)
	check(int(c.state.navalAi.encounterCount) == 4 and AI.scan_encounters(c).is_empty(), "Existing owner-cache recovery also preserves the daily allowance")
	var survivor: Dictionary = {}
	for id in ids.slice(0, 8):
		var owner: Dictionary = c.fleet_owner(id)
		if not Orders.living_boats(owner).is_empty():
			survivor = owner
			break
	check(not survivor.is_empty(), "A physical survivor remains for the next-day response")
	if survivor.is_empty():
		return
	for p in c.state.patrols:
		p.active = false
	var sp: Dictionary = Orders.find_patrol(c.state, survivor.id)
	var peer: Dictionary = c.fleet_owner(ids[8])
	var pp: Dictionary = Orders.find_patrol(c.state, peer.id)
	peer.faction = "forge" if survivor.faction == "compact" else "compact"
	sp.active = true; pp.active = true
	pp.x = sp.x + 20.0; pp.y = sp.y
	c.state.econDay += 1; c.state.day += 1.0
	c.state.position = {"x": 0.0, "y": 0.0}
	# Both actors are deliberately outside the existing 1800-unit player watch.
	sp.x = 4200.0; sp.y = 3100.0; pp.x = 4220.0; pp.y = 3100.0
	check(AI.scan_encounters(c).is_empty() and int(c.state.navalAi.encounterCount) == 1 and c.state.navalAi.encounterOwners.size() == 2, "New campaign day permits a new physical fight, without broadcasting a distant result")
	check(not bool(c.state.navalAi.encounters[0].witnessed) and c.state.navalAi.encounters.size() <= 24, "Offscreen result stays in the existing bounded owner/event records")
	check(AI.scan_encounters(c).is_empty() and int(c.state.navalAi.encounterCount) == 1, "Same owners cannot fight again after the day reset's first scan")
	check(bool(Records.snapshot(Orders.living_boats(peer)[0] if not Orders.living_boats(peer).is_empty() else peer.boats[0]).ok), "Actual canonical equipment remains readable after the skirmish")
	check(Money.total(c.state) == coins, "Day reset and repeated scans conserve all coins")


func _test_batch_days() -> void:
	_isolate(["patrol-0", "patrol-1"])
	var raider: Dictionary = c.fleet_owner("patrol-0")
	var trader: Dictionary = c.fleet_owner("patrol-1")
	var rp: Dictionary = Orders.find_patrol(c.state, raider.id)
	var tp: Dictionary = Orders.find_patrol(c.state, trader.id)
	rp.x = 4200.0; rp.y = 3100.0; tp.x = 4225.0; tp.y = 3100.0
	for boat in trader.boats:
		boat.ammo = 0.0
	trader.cargo.ammo = 0.0
	var day: int = int(c.state.econDay)
	AI.tick(c, 2)
	var events: Array = c.state.navalAi.encounters
	check(events.size() == 2 and int(events[0].day) == day + 1 and int(events[1].day) == day, "Two-step tick resolves one actual pair on each simulated day")
	check(int(c.state.econDay) == day and int(c.state.navalAi.encounterDay) == day + 1 and int(c.state.navalAi.encounterCount) == 1, "Batch steps share actual actors and date the ledger without changing the campaign calendar")
