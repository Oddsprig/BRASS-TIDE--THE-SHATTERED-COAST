extends SceneTree
## One actual seeded career; detached cases share its already-built navigation.
const Campaign = preload("res://scripts/campaign.gd")
const AI = preload("res://scripts/naval_ai.gd")
const Orders = preload("res://scripts/naval_orders.gd")
const UI = preload("res://scripts/naval_ui.gd")
const Economy = preload("res://scripts/economy.gd")
const Money = preload("res://scripts/money.gd")
const Goods = preload("res://scripts/goods.gd")
const Factions = preload("res://scripts/factions.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Service = preload("res://scripts/equipment_service.gd")
const Replacements = preload("res://scripts/naval_replacements.gd")

var checks: int = 0
var failures: int = 0
var c
var baseline: Dictionary = {}


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL campaign ai055: ", message)


func _initialize() -> void:
	print("campaign ai055: preparing one seeded Campaign baseline")
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c = Campaign.new(world)
	check(bool(c.new_game(5501).ok), "Actual campaign initializes")
	baseline = c.state.duplicate(true)
	print("campaign ai055: local intelligence and stale actions")
	_test_intelligence()
	print("campaign ai055: paid shipment, raid, patrol and recovery")
	_test_chain()
	print("campaign ai055: loss custody before paid replacement")
	_test_loss_boundary()
	print("campaign ai055: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _reset(ids: Array) -> void:
	c.state = baseline.duplicate(true)
	c.pending_days = 0
	c.events.clear()
	for owner in c.state.fleetOwners:
		if Orders.is_story_owner(owner): continue
		owner.active = ids.has(str(owner.id))
		owner.atPort = ""
		var patrol: Dictionary = Orders.find_patrol(c.state, owner.id)
		patrol.active = owner.active
		patrol.hidden = false
		patrol.holding = false
		if owner.active:
			_fund(owner, maxi(0, 8000 - int(owner.coins)))
	c.state.position = {"x": 0.0, "y": 0.0}
	c.state.navalAi.sightingsByObserver = {}


func _place(id: String, x: float, y: float) -> Dictionary:
	var patrol: Dictionary = Orders.find_patrol(c.state, id)
	patrol.x = x; patrol.y = y
	return patrol


func _record(records: Array, id: String) -> Dictionary:
	for record in records:
		if str(record.get("ownerId", "")) == id: return record
	return {}


func _load(owner: Dictionary, qty: int = 8) -> void:
	var home: Dictionary = c.port(str(owner.homePort))
	var old_good: String = str(owner.tradeGood)
	var old_qty: float = minf(float(owner.tradeCargo), float(owner.cargo.get(old_good, 0.0)))
	owner.cargo[old_good] -= old_qty
	home.stocks[old_good] += old_qty
	owner.tradeCargo = 0.0; owner.tradeGood = "timber"
	var wallet: Dictionary = {"coins": owner.coins, "cargo": owner.cargo}
	var before: int = int(owner.coins)
	var bought: Dictionary = Economy.transact(home, wallet, "timber", qty, "buy", float(Orders.fleet_reserves(owner).capacity))
	check(bool(bought.ok) and int(bought.get("qty", 0)) == qty and int(wallet.coins) < before, "Shipment is bought from finite home stock with actual coins")
	owner.coins = wallet.coins
	owner.tradeCargo = float(bought.get("qty", 0))


func _goods(good: String) -> float:
	var total: float = float(c.state.cargo.get(good, 0.0))
	for port in c.state.ports: total += float(port.stocks.get(good, 0.0))
	for boat in c.state.fleet:
		if good in ["ammo", "fuel", "supplies"]:
			total += float(boat.get(good, 0.0)) / (float(Goods.ROUNDS_PER_CASE) if good == "ammo" else 1.0)
	for owner in c.state.fleetOwners:
		total += float(owner.cargo.get(good, 0.0))
		for boat in owner.boats:
			if good in ["ammo", "fuel", "supplies"]:
				total += float(boat.get(good, 0.0)) / (float(Goods.ROUNDS_PER_CASE) if good == "ammo" else 1.0)
	return total


func _people() -> float:
	var total: float = 0.0
	for port in c.state.ports: total += float(port.workforce)
	for boat in c.state.fleet: total += float(boat.crew)
	for owner in c.state.fleetOwners:
		for boat in owner.boats: total += float(boat.crew)
	return total


func _item_ids() -> Array:
	var ids: Array = []
	for owner in c.state.fleetOwners:
		for boat in owner.boats:
			for uid in boat.get("moduleCondition", {}).get("items", {}): ids.append(str(uid))
	ids.sort()
	return ids


func _store_rounds(owner: Dictionary) -> void:
	var home: Dictionary = c.port(str(owner.homePort))
	for boat in owner.boats:
		home.stocks.ammo += float(boat.ammo) / float(Goods.ROUNDS_PER_CASE)
		boat.ammo = 0.0
	home.stocks.ammo += float(owner.cargo.ammo)
	owner.cargo.ammo = 0.0


func _fund(owner: Dictionary, amount: int) -> void:
	var left: int = amount
	for port in c.state.ports:
		var part: int = mini(left, int(port.governmentPurse))
		check(Money.move(port, "governmentPurse", owner, "coins", part, "Finite fixture recovery advance", c.state.moneyLog), "Recovery advance comes from an existing purse")
		left -= part
		if left == 0: break
	check(left == 0, "Existing treasuries fund the bounded recovery case")


func _test_intelligence() -> void:
	_reset(["patrol-0", "patrol-1", "patrol-2"])
	var raider: Dictionary = c.fleet_owner("patrol-0")
	var trader: Dictionary = c.fleet_owner("patrol-1")
	var rp: Dictionary = _place(raider.id, 4200.0, 3100.0)
	var tp: Dictionary = _place(trader.id, 4500.0, 3100.0)
	_place("patrol-2", 9000.0, 3100.0)
	_load(trader)
	_store_rounds(trader)
	c.state.position = {"x": rp.x, "y": rp.y}
	var report: Dictionary = UI.report(c.state)
	var local: Dictionary = _record(report.contacts, trader.id)
	check(not local.is_empty() and UI.can_hail(c.state, local), "A visible living local contact can be hailed")
	tp.hidden = true
	check(not UI.can_hail(c.state, local), "A contact hidden after the button was built cannot be hailed")
	tp.hidden = false
	for contact in report.contacts:
		check(not contact.has("x") and not contact.has("y") and not contact.has("coins") and not contact.has("cargo") and not contact.has("reserves"), "Traffic projection contains no coordinates or private ledgers")
	check(_record(report.contacts, "patrol-2").is_empty(), "An unobserved distant fleet has no UI record")
	var observed_destination: String = str(local.get("destination", ""))
	AI.observe(c.state, raider.id)
	var seen: Dictionary = _record(AI.sightings(c.state, raider.id), trader.id)
	check(not seen.is_empty() and bool(seen.loaded), "NPC sighting records the actually loaded local carrier")
	tp.x = 9000.0
	tp.to = str(c.state.ports[2].id) if observed_destination != str(c.state.ports[2].id) else str(c.state.ports[3].id)
	trader.purpose = "replace"; trader.reason = "PRIVATE PURSE 123456"
	c.state.day += 0.05
	report = UI.report(c.state)
	var old: Dictionary = _record(report.contacts, trader.id)
	check(str(old.get("status", "")) == "Old intelligence" and not UI.can_hail(c.state, old), "A moved-away contact becomes dated intelligence and cannot be hailed")
	check(str(old.get("destination", "")) == observed_destination and str(old.get("purpose", "")) == str(local.get("purpose", "")), "Old UI intelligence does not follow the distant route or purpose")
	check(not JSON.stringify(report).contains("123456"), "Private current owner reason is never displayed")
	var remembered: Dictionary = Orders.select_raider_order(c.state, raider, "")
	check(str(remembered.get("targetOwnerId", "")) == str(trader.id) and str(remembered.get("destination", "")) == str(seen.get("destination", "")), "Brief lost contact uses only its last observed destination")
	c.state.day = float(seen.get("expiresDay", c.state.day)) + 0.01
	report = UI.report(c.state)
	old = _record(report.contacts, trader.id)
	check(bool(old.get("expired", false)) and not UI.can_hail(c.state, old), "Expired sighting stays explicitly old and cannot grant remote access")
	check(str(Orders.select_raider_order(c.state, raider, "").get("targetOwnerId", "")).is_empty(), "Expired NPC memory stops distant pursuit")
	tp.x = 4500.0
	var witnessed: Dictionary = AI.resolve_encounter(c.state, raider, trader, rp, tp, 5501)
	check(bool(witnessed.get("ok", false)) and bool(witnessed.get("event", {}).get("witnessed", false)) and UI.report(c.state).outcomes.size() == 1, "A real locally witnessed outcome appears in the dated traffic report")
	check(Money.total(c.state) == int(c.state.coinSupply), "Observation and expiry conserve complete purses")


func _test_chain() -> void:
	_reset(["patrol-0", "patrol-1", "patrol-2"])
	var raider: Dictionary = c.fleet_owner("patrol-0")
	var trader: Dictionary = c.fleet_owner("patrol-1")
	var guard: Dictionary = c.fleet_owner("patrol-2")
	var tp: Dictionary = Orders.find_patrol(c.state, trader.id)
	# Stage a real seeded voyage at its mid-route encounter boundary.
	tp.progress = 0.5; c.place_patrol(tp)
	var rp: Dictionary = _place(raider.id, float(tp.x) + 25.0, float(tp.y))
	var gp: Dictionary = _place(guard.id, float(tp.x) + 350.0, float(tp.y))
	var player: String = JSON.stringify({"coins": c.state.coins, "cargo": c.state.cargo, "fleet": c.state.fleet, "position": c.state.position})
	var timber: float = _goods("timber")
	_load(trader)
	check(is_equal_approx(_goods("timber"), timber), "Paid departure transfers finite timber out of home stock")
	_store_rounds(trader) # Depleted merchant yields after the first real salvo.
	AI.observe(c.state, raider.id); AI.observe(c.state, guard.id)
	var raid_plan: Dictionary = Orders.select_raider_order(c.state, raider, "")
	var guard_plan: Dictionary = Orders.select_patrol_order(c.state, guard, "")
	check(str(raid_plan.get("targetOwnerId", "")) == str(trader.id), "Pirate selects the actually loaded local shipment")
	check(str(guard_plan.get("targetOwnerId", "")) == str(raider.id) and str(guard_plan.get("purpose", "")) == "intercept", "Patrol responds to the locally observed hostile raider")
	AI.build_order(c.state, raider, str(raid_plan.purpose), str(raid_plan.destination), str(raid_plan.reason), str(raid_plan.targetOwnerId))
	AI.build_order(c.state, guard, str(guard_plan.purpose), str(guard_plan.destination), str(guard_plan.reason), str(guard_plan.targetOwnerId))
	var ammo: float = _goods("ammo")
	var people: float = _people()
	var ids: Array = _item_ids()
	var raid: Dictionary = AI.resolve_encounter(c.state, raider, trader, rp, tp, 5501)
	check(bool(raid.get("ok", false)), "Actual offscreen raid resolves while the player is elsewhere")
	if not bool(raid.get("ok", false)): return
	var event: Dictionary = raid.event
	check(int(event.salvos) >= 1 and int(event.salvos) <= 5 and int(event.shotsA) > 0, "Raid runs finite real salvos")
	check(str(event.kind) == "raid" and str(event.retreated) == str(trader.id) and int(event.survivorsB) > 0, "Depleted convoy withdraws with physical survivors")
	check(int(event.capturedQty) > 0 and str(event.capturedGood) == "timber" and float(raider.cargo.timber) >= float(event.capturedQty), "Raid prize moves actual shipment goods into the pirate hold")
	check(not bool(event.get("witnessed", true)) and UI.report(c.state).outcomes.is_empty(), "Player-away raid stays out of witnessed traffic outcomes")
	check(not bool(AI.resolve_encounter(c.state, guard, raider, gp, rp, 5501).get("ok", false)), "Patrol cannot reuse today's already engaged raider")
	_store_rounds(raider)
	c.state.day += 1.0; c.state.econDay += 1
	gp.x = float(rp.x) + 25.0; gp.y = rp.y
	var peace: int = Factions.relation(c.state, str(guard.faction), str(raider.faction))
	Factions.set_relation(c.state, str(guard.faction), str(raider.faction), 0, "Finite ceasefire case")
	check(not bool(AI.resolve_encounter(c.state, guard, raider, gp, rp, 5501).get("ok", false)), "Actual diplomacy refuses a peaceful patrol attack")
	Factions.set_relation(c.state, str(guard.faction), str(raider.faction), peace, "Restore actual hostile pair")
	var response: Dictionary = AI.resolve_encounter(c.state, guard, raider, gp, rp, 5501)
	check(bool(response.get("ok", false)), "Next-day patrol resolves a real hostile response")
	if not bool(response.get("ok", false)): return
	var action: Dictionary = response.event
	check(str(action.kind) == "patrol" and int(action.salvos) <= 5 and int(action.shotsA) > 0, "Patrol response uses the same finite combat path")
	check(int(action.capturedQty) > 0 and str(action.capturedGood) == "timber" and float(guard.cargo.timber) >= float(action.capturedQty), "Patrol recovers real prize lots from the pirate's hold")
	var rounds: int = int(event.ammoUsedA) + int(event.ammoUsedB) + int(action.ammoUsedA) + int(action.ammoUsedB)
	check(is_equal_approx((ammo - _goods("ammo")) * float(Goods.ROUNDS_PER_CASE), float(rounds)), "Global stock and working ammunition debit exactly the actual per-mount rounds")
	check(is_equal_approx(_goods("timber"), timber) and _people() <= people, "Encounters transfer goods and create no people")
	check(ids == _item_ids(), "Encounters preserve every original module UID")
	var patient: Dictionary = {}
	var damaged: Dictionary = {}
	for owner in [trader, raider, guard]:
		for boat in Orders.living_boats(owner):
			if float(boat.hp) < float(boat.maxHp) - 0.01:
				patient = owner; damaged = boat; break
		if not patient.is_empty(): break
	check(not patient.is_empty(), "Real combat leaves a damaged survivor for paid recovery")
	if not patient.is_empty():
		_fund(patient, 8000)
		var patrol: Dictionary = Orders.find_patrol(c.state, str(patient.id))
		var before: Vector2 = Vector2(float(patrol.x), float(patrol.y))
		c.NavalLifecycle.route(c, patrol, str(patient.homePort))
		check(Vector2(float(patrol.x), float(patrol.y)).is_equal_approx(before) and str(patient.atPort).is_empty(), "Recovery planning does not teleport a living survivor home")
		check(not patrol.course.is_empty(), "Survivor has an actual water route to paid recovery")
		var hp: float = float(damaged.hp)
		var home: Dictionary = c.port(str(patient.homePort))
		var labor: float = float(Service.workforce_status(home).free)
		var worker_purses: int = int(home.householdPurse) + int(home.expertPurse)
		var kits: float = _goods("supplies")
		var living_people: float = _people()
		# Exercise the real arrival boundary, without simulating a long voyage.
		patrol.progress = 1.0
		c.NavalLifecycle.step(c, 0.01)
		check(float(damaged.hp) > hp, "Actual harbor arrival buys repair of combat damage")
		check(float(Service.workforce_status(home).free) < labor and _goods("supplies") < kits, "Paid recovery consumes finite harbor labor and kits")
		check(int(home.householdPurse) + int(home.expertPurse) > worker_purses, "Repair pays the actual harbor workers' purses")
		check(is_equal_approx(_people(), living_people) and ids == _item_ids(), "Recovery moves existing recruits and preserves equipment identities")
	check(Money.total(c.state) == int(c.state.coinSupply), "Shipment, prizes and paid recovery conserve the complete global coin supply")
	check(player == JSON.stringify({"coins": c.state.coins, "cargo": c.state.cargo, "fleet": c.state.fleet, "position": c.state.position}), "Autonomous chain leaves the distant player's assets and position untouched")
	check(UI.report(c.state).outcomes.is_empty(), "Returning traffic report does not reveal earlier unobserved fights")


func _test_loss_boundary() -> void:
	_reset(["patrol-0"])
	var owner: Dictionary = c.fleet_owner("patrol-0")
	var patrol: Dictionary = Orders.find_patrol(c.state, str(owner.id))
	_load(owner)
	# Fund the real cheapest stocked hull and actual recruiting charge, rather
	# than guessing that a fixed sum covers today's labor/material quote.
	var home: Dictionary = c.port(str(owner.homePort))
	var required: int = 2147483647
	for id in home.shipStock:
		if int(home.shipStock[id]) < 1: continue
		var spec: Dictionary = c.hull(str(id))
		var quote: Dictionary = Replacements.quote_at_port(spec, home)
		var bill: int = int(quote.readyPrice) + Economy.recruit_cost(home, int(spec.crewMin))
		required = mini(required, bill)
	check(required < 2147483647, "Replacement scenario has an actual stocked hull")
	if required == 2147483647: return
	_fund(owner, maxi(0, required - int(owner.coins)))
	var lost: Dictionary = owner.boats[0]
	var uid: String = str(lost.uid)
	var old_parts: Array = lost.moduleCondition.items.keys()
	var sea: Vector2 = Vector2(float(patrol.x), float(patrol.y))
	lost.sunk = true; lost.hp = 0.0; lost.crew = 0.0
	var people: float = _people()
	c.NavalLifecycle.daily(c)
	var wreck: Dictionary = {}
	for candidate in c.state.wrecks:
		if str(candidate.get("uid", "")) == uid: wreck = candidate; break
	check(not wreck.is_empty(), "Lost original hull is recorded before replacement can remove it")
	if wreck.is_empty(): return
	check(Vector2(float(wreck.x), float(wreck.y)).is_equal_approx(sea), "Original wreck stays at the loss coordinate")
	check(str(wreck.get("equipmentCustody", "")) == "wreck" and wreck.get("sourceModuleCondition", {}).get("items", {}).keys() == old_parts, "Original module UIDs remain in exclusive wreck custody")
	check(is_zero_approx(float(owner.cargo.timber)) and is_equal_approx(float(wreck.stores.get("timber", 0.0)), 4.0), "Lost hold is removed before relaunch; existing half-recoverable cargo rule is explicit")
	var settled: String = JSON.stringify(wreck)
	var cargo: String = JSON.stringify(owner.cargo)
	c.NavalLifecycle.reconcile_losses(c)
	check(JSON.stringify(wreck) == settled and JSON.stringify(owner.cargo) == cargo, "Repeating loss settlement neither duplicates wreck custody nor debits cargo twice")
	var funded: bool = false
	for replacement in c.state.navalAi.replacements:
		if str(replacement.get("ownerId", "")) == str(owner.id) and int(replacement.get("price", 0)) > 0: funded = true
	check(funded, "Replacement is a paid actual stock purchase or material/escrow commission")
	if not funded: print("campaign ai055 replacement: ", AI.request_replacement(c, owner, home), " trained pool ", Replacements.available_recruits(home))
	check(Money.total(c.state) == int(c.state.coinSupply) and is_equal_approx(_people(), people), "Paid replacement conserves global purses and hires from existing workforce")
	for boat in Orders.living_boats(owner):
		check(str(boat.uid) != uid and bool(Records.snapshot(boat).get("ok", false)), "Replacement is a distinct valid physical hull")
		for item_uid in boat.moduleCondition.items:
			check(not old_parts.has(item_uid), "Replacement cannot duplicate retired equipment identities")
