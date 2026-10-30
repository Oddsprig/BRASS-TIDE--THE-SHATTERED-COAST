extends SceneTree
## Source only. Root alone executes this in Test Bridge with a private profile.
## Existing funded owners and actual069 geography; no post-opening pose writes,
## income, cargo/store/crew refills, forged sightings, encounter or service result.
const Campaign = preload("res://scripts/campaign.gd")
const Shipping = preload("res://scripts/shipping068.gd")
const Ocean = preload("res://scripts/ocean_campaign066.gd")
const Travel = preload("res://scripts/ocean_travel066.gd")
const Orders = preload("res://scripts/naval_orders.gd")
const Money = preload("res://scripts/money.gd")
const Workers = preload("res://scripts/economy_workers.gd")
const Custody = preload("res://scripts/equipment_campaign.gd")
const Service = preload("res://scripts/equipment_owner_service.gd")
const BODY_LIMIT_MS: int = 15000
const SEED: int = 75075
var c
var workers = Workers.new()
var started: int = 0
var checks: int = 0
var failures: int = 0
var expired: bool = false
var complete: bool = false
var supply: int = 0
var failure_labels: Array = []
var observations: Array = []
var artifacts: Array = []
var history: Dictionary = {"corridor":{}, "load":{}, "delivery":{}, "loss":{}, "dispatch":{}, "choice":{}, "npc_contact":{}, "recovery":{}}
var seen_events: Dictionary = {}
var crew_losses: float = 0.0

func _initialize() -> void:
	started = Time.get_ticks_msec()
	progress("initialize")
	_run.call_deferred()

func progress(stage: String) -> void:
	print("FactionStrategy075 progress ", stage, " elapsed_ms=", Time.get_ticks_msec() - started)

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		failure_labels.append(label)
		print("FAIL faction_strategy075: ", label)
	return ok

func bounded() -> bool:
	if not expired and Time.get_ticks_msec() - started < BODY_LIMIT_MS - 500:
		return true
	if not expired:
		expired = true
		check(false, "Actual chronology stops before the fifteen-second body budget")
	return false

func note(kind: String, values: Dictionary = {}) -> void:
	var row: Dictionary = {"kind":kind, "day":float(c.state.day), "elapsed_ms":Time.get_ticks_msec() - started}
	row.merge(values, true)
	observations.append(row)

func crew_total(state: Dictionary) -> float:
	var total: float = 0.0
	for port in state.get("ports", []):
		total += float(port.get("workforce", 0))
	for boat in state.get("fleet", []) + state.get("boardingPrizes", []):
		total += float(boat.get("crew", 0))
	for owner in state.get("fleetOwners", []):
		for boat in owner.get("boats", []):
			total += float(boat.get("crew", 0))
	return total

func trade_pair(owner: Dictionary, port: Dictionary, good: String) -> Dictionary:
	return {"owner_coins":int(owner.coins), "crew_purse":int(owner.crewPurse),
		"port_cash":int(port.cash), "stock":float(port.stocks.get(good, 0.0)),
		"hold":float(owner.cargo.get(good, 0.0)), "manifest":float(owner.tradeCargo)}

func exact_trade(before: Dictionary, after: Dictionary, qty: int, coins: int, buy: bool) -> bool:
	var sign: int = 1 if buy else -1
	return qty > 0 and coins > 0 and after.owner_coins == before.owner_coins - sign * coins \
		and after.port_cash == before.port_cash + sign * coins and after.stock == before.stock - sign * qty \
		and after.hold == before.hold + sign * qty and after.manifest == before.manifest + sign * qty and after.crew_purse == before.crew_purse

func living_crew(owner: Dictionary) -> float:
	var total: float = 0.0
	for boat in owner.get("boats", []): total += float(boat.get("crew", 0))
	return total

func settle() -> bool:
	while c.pending_days > 0:
		if not bounded(): return false
		c.pending_days -= 1
		workers.start(c.state.ports, 1, c.TradeFlow.blockades(c), int(c.state.seed) + int(c.state.econDay) * 104729)
		var result: Dictionary = workers.finish(true)
		var yards: Dictionary = yard_book(result.ports)
		c.apply_economy(result.ports, result.events, result.days)
		replacement_after(yards)
	if Money.total(c.state) != supply or int(c.state.coinSupply) != supply:
		return check(false, "Actual harbor work, fleet payroll and queued yards conserve all world coins")
	return true

func route() -> Dictionary:
	return c.state.get("shipping068", {}).get("model", {}).get("route", {})

func read_choice() -> void:
	if history.dispatch.is_empty() or not history.choice.is_empty(): return
	var memory: Dictionary = c.state.get("ocean066", {}).get("memory", {})
	for id in memory.get("intents", {}):
		if str(id) == "player": continue
		var intent: Dictionary = memory.intents[id]
		var target: String = str(intent.get("targetId", ""))
		if target.is_empty() or target == "player" or str(intent.get("kind", "")) != "pursue": continue
		var sight: Dictionary = memory.get("sightings", {}).get(id, {}).get(target, {})
		if sight.is_empty(): continue
		if float(sight.get("manifest075", {}).get("cargoQuantity", 0)) <= 0: continue
		var owner: Dictionary = Orders.find_owner(c.state, str(id))
		if owner.get("kind", "") not in ["raider", "patrol"]: continue
		if owner.get("kind", "") == "raider" and target != str(history.corridor.ownerId): continue
		var decided: float = float(intent.get("lastPlanSecond", -1))
		var now: float = float(c.state.day) * 45.0
		if decided < float(history.dispatch.day) * 45.0 or decided > now or float(sight.get("seenSecond", INF)) > now or now >= float(sight.get("expiresSecond", -INF)): continue
		history.choice = {"ownerId":str(id), "targetId":target, "kind":str(owner.kind), "intent":intent.duplicate(true), "sighting":sight.duplicate(true), "day":float(c.state.day)}
		note("dated_observed_choice", history.choice)
		return

func npc_proposal() -> Dictionary:
	if history.dispatch.is_empty() or not history.npc_contact.is_empty(): return {}
	var npcs: Array = Ocean.actors(c, c.state.ocean066).filter(func(a): return str(a.ownerId) != "player")
	if npcs.size() != 2 or not npcs.all(func(a): return a.location.world064.layer == "ocean"): return {}
	if not npcs.any(func(a): return str(a.ownerId) == str(history.corridor.ownerId)):
		check(false, "The actual independent NPC participant pair contains the algorithm-selected merchant")
		return {}
	# Match the production observation/decision adapter on detached real actors.
	Ocean._attach_observations(c, npcs)
	var contact: Dictionary = c.state.ocean066.contact
	var watch: bool = c.ocean_watch066 >= 1.0
	var decisions: Array = [Ocean.OWNER] if watch and not contact.is_empty() and contact.phase == "patrol" and npcs.any(func(a): return str(a.ownerId) == Ocean.OWNER) else []
	var proposed: Dictionary = Travel.step(c.ocean_context066, npcs, Ocean.relations(c, npcs), c.state.ocean066.memory,
		{"startSecond":float(c.state.day) * 45.0, "dt":4.0, "watchDue":watch, "decisionOwnerIds":decisions})
	if not proposed.get("ok", false):
		check(false, "The same actual two NPC actor DTOs step without a player in the participant list: " + str(proposed.get("message", "")))
		return {}
	if proposed.encounter.is_empty(): return {}
	return {"participants":npcs.map(func(a): return str(a.ownerId)), "encounter":proposed.encounter.duplicate(true), "atDay":float(c.state.day)}

func collect_encounters(proposal: Dictionary, before_crews: Dictionary, manifest: Dictionary = {}) -> void:
	for event in c.state.get("navalAi", {}).get("encounters", []):
		var key: String = "%s:%s:%s" % [str(event.get("day", "")), str(event.get("a", "")), str(event.get("b", ""))]
		if seen_events.has(key): continue
		seen_events[key] = true
		crew_losses += float(event.get("crewLostA", 0)) + float(event.get("crewLostB", 0))
		if proposal.is_empty() or not history.npc_contact.is_empty(): continue
		var ids: Array = proposal.participants
		if str(event.get("a", "")) not in ids or str(event.get("b", "")) not in ids: continue
		var a: String = str(event.a)
		var b: String = str(event.b)
		var loss_a: float = float(before_crews.get(a, 0)) - living_crew(Orders.find_owner(c.state, a))
		var loss_b: float = float(before_crews.get(b, 0)) - living_crew(Orders.find_owner(c.state, b))
		check(not ids.has("player") and a != b and loss_a == float(event.crewLostA) and loss_b == float(event.crewLostB), "Actual independent NPC salvo event reconciles both original crews exactly")
		history.npc_contact = {"participants":ids, "proposal":proposal.encounter, "actual_event":event.duplicate(true), "crewLostA":loss_a, "crewLostB":loss_b, "day":float(c.state.day)}
		note("actual_npc_contact", history.npc_contact)
		var merchant: Dictionary = Orders.find_owner(c.state, str(history.corridor.ownerId))
		var lost: float = float(manifest.get("manifest", 0)) - float(merchant.tradeCargo)
		var sunk: int = int(event.sunkA if a == str(merchant.id) else event.sunkB)
		if lost > 0 and (int(event.capturedQty) > 0 or sunk > 0):
			var actual_hold: float = float(merchant.cargo.get(str(manifest.good), 0))
			check(absf(float(manifest.hold) - actual_hold - lost) < 0.000001, "Actual skirmish debit removes the same purchased lots from hold and commercial availability")
			history.loss = {"day":float(c.state.day), "ownerId":str(merchant.id), "good":str(manifest.good), "lost_qty":lost,
				"before":manifest, "after_hold":actual_hold, "after_manifest":float(merchant.tradeCargo), "actual_event":event.duplicate(true)}
			note("actual_purchased_cargo_loss", history.loss)

func yard_book(ports: Array = []) -> Dictionary:
	if history.dispatch.is_empty() or not history.recovery.is_empty(): return {}
	if ports.is_empty(): ports = c.state.ports
	var ids: Array = [str(history.corridor.ownerId)]
	var contact: String = str(c.state.get("ocean066", {}).get("contact", {}).get("ownerId", ""))
	if not contact.is_empty() and not ids.has(contact): ids.append(contact)
	if not history.npc_contact.is_empty(): ids = history.npc_contact.participants
	var snapshots: Dictionary = {}
	for id in ids:
		var owner: Dictionary = Orders.find_owner(c.state, str(id))
		for port in ports:
			if str(port.id) == str(owner.get("homePort", "")):
				snapshots[id] = {"coins":int(owner.coins), "crew_purse":int(owner.crewPurse), "boat_uids":owner.boats.map(func(b): return str(b.uid)), "encounters":c.state.navalAi.encounters.map(func(e): return JSON.stringify(e)),
					"port":port.duplicate(true), "queues":port.get("buildQueue", []).map(func(q): return str(q.id))}
	return snapshots

func replacement_after(before: Dictionary) -> void:
	if before.is_empty() or history.npc_contact.is_empty() or not history.recovery.is_empty(): return
	for id in before:
		var owner: Dictionary = Orders.find_owner(c.state, str(id))
		var prior: Dictionary = before[id]
		var yard: Dictionary = c.port(str(prior.port.id))
		# This branch witnesses a real funded queue, without demanding its build
		# finish inside the fixture. Crew recruitment remains the existing paid gate.
		for order in yard.get("buildQueue", []):
			if str(order.get("npcOwnerId", "")) != str(id) or str(order.id) in prior.queues: continue
			var quote: Dictionary = c.NavalAI.NavalReplacements.quote_at_port(c.hull(str(order.hull)), prior.port)
			var price: int = int(quote.get("commissionPrice", quote.get("total", 0)))
			var wages: int = int(quote.get("laborCost", 0)) + int(quote.get("supervisionCost", 0))
			var loot: int = 0
			for event in c.state.navalAi.encounters:
				if JSON.stringify(event) in prior.encounters: continue
				if str(event.get("a", "")) != str(id) and str(event.get("b", "")) != str(id): continue
				if str(event.get("winner", "")) == str(id): loot -= int(event.get("lootCoins", 0))
				elif not str(event.get("winner", "")).is_empty(): loot += int(event.get("lootCoins", 0))
			var exact: bool = c.NavalAI.NavalReplacements.enrolled_yard075(c.state, owner, yard) \
				and price > 0 and wages > 0 and int(prior.coins) - int(owner.coins) == price + loot \
				and int(owner.crewPurse) == int(prior.crew_purse) and int(order.escrow) + int(order.laborPaid) + int(order.supervisionPaid) == wages \
				and int(yard.cash) - int(prior.port.cash) == price - wages - int(quote.tax) \
				and int(yard.governmentPurse) - int(prior.port.governmentPurse) == int(quote.tax) \
				and int(yard.workforce) == int(prior.port.workforce) and int(yard.recruits) == int(prior.port.recruits) \
				and owner.boats.map(func(b): return str(b.uid)) == prior.boat_uids and order.get("fundingSource", "") == "npc"
			for good in quote.get("materials", {}):
				exact = exact and float(yard.stocks.get(good, 0)) == maxf(0.0, float(prior.port.stocks.get(good, 0)) - float(quote.materials[good]))
			if not exact: continue # An unisolated/underfunded window is not a pass.
			check(true, "Actual existing-yard queue exactly debits owner cash, finite materials, tax and wage escrow without birthing crew or a sea hull")
			history.recovery = {"kind":"funded_yard_queue", "day":float(c.state.day), "ownerId":str(id), "portId":str(yard.id),
				"price":price, "wage_escrow":wages, "materials":quote.materials.duplicate(true), "actual_order":order.duplicate(true),
				"crew_limit":"Queue only: no new crew is counted; normal paid recruitment remains mandatory at collection."}
			note("actual_funded_yard_replacement", history.recovery)
			return

func actual_outcome() -> Dictionary:
	if history.npc_contact.is_empty(): return {}
	if not history.loss.is_empty(): return history.loss
	if not history.delivery.is_empty() and float(history.delivery.day) >= float(history.npc_contact.day): return history.delivery
	return {}

func goods_pair(owner: Dictionary, port: Dictionary) -> Dictionary:
	var total: Dictionary = {}
	for good in c.Economy.GOODS:
		total[good] = float(port.stocks.get(good, 0)) + float(owner.cargo.get(good, 0))
	for boat in owner.boats:
		if boat.get("sunk", false): continue
		for good in ["fuel", "supplies", "ammo"]:
			total[good] += float(boat.get(good, 0)) / (50.0 if good == "ammo" else 1.0)
	return total

func repair_before(owner_id: String, port_id: String) -> Dictionary:
	if history.npc_contact.is_empty() or not history.recovery.is_empty(): return {}
	var owner: Dictionary = Orders.find_owner(c.state, owner_id)
	var port: Dictionary = c.port(port_id)
	if owner.is_empty() or port.is_empty() or str(port.id) != str(owner.homePort): return {}
	var actual: Dictionary = Orders.canonical_location068(c.state, str(owner.id))
	if actual.is_empty() or not actual.path.is_empty() or c.distance(actual.position, port) >= 40.0: return {}
	var quotes: Array = []
	for boat in owner.boats:
		if boat.get("sunk", false): continue
		var quoted: Dictionary = Service.owner_service_quote(owner, port, boat, c)
		if quoted.get("ok", false) and int(quoted.get("cost", 0)) > 0:
			quotes.append({"uid":str(boat.uid), "cost":int(quoted.cost), "before":boat.duplicate(true)})
	if quotes.is_empty(): return {}
	return {"ownerId":str(owner.id), "portId":str(port.id), "location":actual,
		"purses":int(owner.coins) + int(owner.crewPurse), "household":int(port.householdPurse),
		"labor":float(port.get("_yardWorkersUsed", 0)), "goods":goods_pair(owner, port), "quotes":quotes}

func repair_after(before: Dictionary, invoice: Dictionary) -> void:
	if before.is_empty() or int(invoice.get("total", 0)) <= 0: return
	var owner: Dictionary = Orders.find_owner(c.state, str(before.ownerId))
	var port: Dictionary = c.port(str(before.portId))
	var restored: Array = []
	for entry in before.quotes:
		for boat in owner.boats:
			if str(boat.uid) != str(entry.uid): continue
			if float(boat.hp) > float(entry.before.hp) or float(boat.get("wounded", 0)) < float(entry.before.get("wounded", 0)) \
				or JSON.stringify(boat.get("moduleCondition", {})) != JSON.stringify(entry.before.get("moduleCondition", {})):
				restored.append(str(boat.uid))
	var after_goods: Dictionary = goods_pair(owner, port)
	var consumed: Dictionary = {}
	for good in before.goods:
		if float(before.goods[good]) > float(after_goods[good]): consumed[good] = float(before.goods[good]) - float(after_goods[good])
	var spent: int = int(before.purses) - int(owner.coins) - int(owner.crewPurse)
	var paid: bool = not restored.is_empty() and spent > 0 and int(port.householdPurse) > int(before.household) \
		and float(port.get("_yardWorkersUsed", 0)) > float(before.labor) and not consumed.is_empty()
	if not paid: return
	history.recovery = {"kind":"paid_survivor_repair", "day":float(c.state.day), "ownerId":str(owner.id), "portId":str(port.id),
		"actual_stopped_berth":before.location, "survivor_uids":restored, "purse_debit":spent,
		"resident_wages":int(port.householdPurse) - int(before.household),
		"worker_days":float(port.get("_yardWorkersUsed", 0)) - float(before.labor), "consumed":consumed, "invoice":invoice.duplicate(true)}
	note("paid_physical_yard_recovery", history.recovery)

func tick() -> bool:
	if not bounded(): return false
	read_choice()
	# Only Campaign.step admits, plans, moves and settles. Observe its actual
	# once-only invoices; never call the stateful admission stage a second time.
	var prior: Dictionary = route()
	var sequence: int = int(prior.get("sequence", -1))
	var selected: Dictionary = prior.get("corridor075", {})
	var physical: Dictionary = {}
	var repair: Dictionary = {}
	if not selected.is_empty():
		var owner: Dictionary = Orders.find_owner(c.state, str(selected.ownerId))
		for id in [selected.originId, selected.remoteId]:
			var port: Dictionary = c.port(str(id))
			physical[id] = {}
			for good in c.Economy.GOODS: physical[id][good] = trade_pair(owner, port, str(good))
		if prior.phase in ["yard_service", "yard_arrival"] and float(prior.nextDueSecond) <= float(c.state.day) * 45.0:
			repair = repair_before(str(selected.ownerId), str(selected.homeId))
	var before_crews: Dictionary = {}
	for owner in c.state.fleetOwners: before_crews[str(owner.id)] = living_crew(owner)
	var proposed: Dictionary = npc_proposal()
	var manifest: Dictionary = {}
	if not history.dispatch.is_empty():
		var merchant: Dictionary = Orders.find_owner(c.state, str(history.corridor.ownerId))
		manifest = {"good":str(merchant.tradeGood), "manifest":float(merchant.tradeCargo), "hold":float(merchant.cargo.get(str(merchant.tradeGood), 0))}
	var yards: Dictionary = yard_book()
	var day: float = float(c.state.day)
	c.step(4.0)
	if float(c.state.day) < day or float(c.state.day) > day + 4.0 / 45.0 + 0.000001:
		return check(false, "Only the actual accepted sailing interval advances the campaign clock")
	collect_encounters(proposed, before_crews, manifest)
	replacement_after(yards)
	read_choice()
	var current: Dictionary = route()
	var corridor: Dictionary = current.get("corridor075", {})
	if history.corridor.is_empty() and not corridor.is_empty():
		history.corridor = corridor.duplicate(true)
		note("funded_natural_home_admission", {"corridor":history.corridor, "location":current.location, "owner_purse":int(Orders.find_owner(c.state, str(current.ownerId)).coins)})
	for invoice in c.state.get("shipping068", {}).get("invoices", []):
		if int(invoice.sequence) <= sequence: continue
		if str(invoice.kind) in ["load", "deliver"] and int(invoice.qty) > 0 and physical.has(invoice.portId):
			var owner: Dictionary = Orders.find_owner(c.state, str(selected.ownerId))
			var port: Dictionary = c.port(str(invoice.portId))
			var before: Dictionary = physical[invoice.portId][invoice.good]
			var after: Dictionary = trade_pair(owner, port, str(invoice.good))
			var buy: bool = str(invoice.kind) == "load"
			var field: String = "load" if buy else "delivery"
			var expected_port: String = str(history.corridor.originId if buy else history.corridor.remoteId)
			if str(port.id) == expected_port and history[field].is_empty():
				check(exact_trade(before, after, int(invoice.qty), int(invoice.total), buy), "Actual generated cargo invoice exactly transfers finite stock, hold and both cash accounts")
				history[field] = {"ownerId":str(owner.id), "portId":str(port.id), "good":str(invoice.good), "before":before, "after":after, "invoice":invoice.duplicate(true), "day":float(c.state.day)}
				note("funded_generated_" + field, history[field])
		if str(invoice.kind) == "service": repair_after(repair, invoice)
	if not settle(): return false
	collect_encounters({}, {})
	for event in c.pop_events():
		if str(event.get("kind", "")) in ["encounter", "ocean_encounter066", "defeat"]:
			note("unexpected_player_interruption", event)
			return check(false, "Independent NPC chronology proceeds without resolving or substituting a player encounter")
	current = route()
	if history.dispatch.is_empty() and not history.load.is_empty() and not current.is_empty():
		var origin: Dictionary = c.port(str(history.corridor.originId))
		if current.location.world064.layer == "ocean" or c.distance(current.location.position, origin) > 40.0:
			history.dispatch = {"ownerId":str(current.ownerId), "location":current.location.duplicate(true), "phase":str(current.phase), "day":float(c.state.day)}
			note("physical_generated_dispatch", history.dispatch)
			if not save_actual("dispatch"): return false
	return failures == 0

func save_actual(label: String) -> bool:
	# Same whole-career serializer as Main.save_game; no alternate snapshot schema.
	if not check(c.pending_days == 0 and workers.group_id < 0, "Dispatch artifact has no unpublished economy job"):
		return false
	var directory: String = OS.get_environment("GAME_TEST_ARTIFACTS")
	if not check(directory.is_absolute_path(), "Root supplies a private artifact directory"):
		return false
	var path: String = directory.path_join("faction075-" + label + ".json")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not check(file != null, "Actual full career artifact opens in Root's private directory"):
		return false
	file.store_string(JSON.stringify(c.state, "\t"))
	file.close()
	var digest: String = FileAccess.get_sha256(path)
	if not check(digest.length() == 64, "Actual full career artifact has a SHA256"):
		return false
	artifacts.append({"kind":label, "path":path, "sha256":digest, "day":float(c.state.day), "source":"Main.save_game whole core.state JSON serializer"})
	return true

func finite_accounts(state: Dictionary) -> Array:
	var rows: Array = []
	for port in state.ports:
		var row: Dictionary = {}
		for key in ["id", "cash", "governmentPurse", "householdPurse", "expertPurse", "stocks", "publicStores", "shipStock", "buildQueue", "workforce", "recruits"]:
			row[key] = port.get(key)
		rows.append(row)
	for owner in state.fleetOwners:
		var row: Dictionary = {}
		for key in ["id", "coins", "crewPurse", "wageArrears", "cargo", "tradeGood", "tradeCargo"]:
			row[key] = owner.get(key)
		row["boats"] = []
		for boat in owner.boats:
			var hull: Dictionary = {}
			for key in ["uid", "type", "crew", "wounded", "fuel", "supplies", "ammo", "hp", "sunk", "moduleCondition", "equipmentRetiredTo"]:
				if boat.has(key): hull[key] = boat[key]
			row.boats.append(hull)
		rows.append(row)
	return rows

func legacy_boundary(opening: Dictionary) -> bool:
	# One synthetic compatibility case, derived from the untouched fresh opening.
	# Remove exactly the declared generated accounts/sites; no owner save is read.
	var old: Dictionary = JSON.parse_string(JSON.stringify(opening))
	var ids: Array = old.sector069.harbors.map(func(p): return str(p.id))
	var sites: Array = old.sector069.sites.map(func(s): return str(s.id))
	var removed: int = 0
	for port in old.ports:
		if str(port.id) in ids: removed += Money.port_total(port)
	old.ports = old.ports.filter(func(p): return str(p.id) not in ids)
	old.coinSupply = int(old.coinSupply) - removed
	old.shipping068.receipts = old.shipping068.receipts.filter(func(row): return str(row.portId) not in ids)
	old.exploration.catalog = old.exploration.catalog.filter(func(s): return str(s.id) not in sites)
	for id in sites: old.exploration.sites.erase(id)
	old.exploration.leads = old.exploration.leads.filter(func(row): return row.get("fromSite", "") not in sites and row.get("toSite", "") not in sites)
	for key in ["sector069", "sectorApplied069", "sectorKnowledge069", "islandOwnership069"]: old.erase(key)
	if not check(Money.total(old) == int(old.coinSupply), "Synthetic two-region input subtracts only removed generated purses"):
		return false
	var expected: String = JSON.stringify(finite_accounts(old), "", true, true)
	var raw: PackedByteArray = var_to_bytes(old)
	var restored: Dictionary = c.restore(old)
	if not check(restored.get("ok", false), "One ordinary parsed older two-region save restores: " + str(restored.get("message", ""))):
		return false
	var before: PackedByteArray = var_to_bytes(c.state)
	var owner: Dictionary = Orders.find_owner(c.state, Shipping.OWNER)
	var chosen: Dictionary = Shipping.select_corridor075(c.state, c.ocean_context064, owner)
	var retained: bool = not c.state.has("sector069") and c.ocean_context064.regions.size() == 2 \
		and not chosen.get("ok", false) and before == var_to_bytes(c.state) and raw == var_to_bytes(old) \
		and Money.total(c.state) == int(old.coinSupply) and expected == JSON.stringify(finite_accounts(c.state), "", true, true)
	note("legacy_two_region_roundtrip", {"generated_purses_removed":removed, "regions":c.ocean_context064.regions.size(), "coin_supply":Money.total(c.state), "fallback":chosen.get("reason", chosen.get("message", "")), "retained":retained, "controlled":"Synthetic compatibility input only; no earned legacy voyage or personal save claim."})
	return check(retained, "Older two-region fallback preserves every existing purse, stock, workforce, boat and item without migration births")

func _run() -> void:
	progress("run")
	if not check(DisplayServer.get_name() == "headless", "Root's private native fixture uses the headless backend"):
		finish(); return
	var definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	if not check(definitions is Dictionary, "Actual game definitions decode"):
		finish(); return
	progress("Campaign.new begin")
	c = Campaign.new(definitions)
	progress("Campaign.new end")
	progress("new_game begin")
	var made: Dictionary = c.new_game(SEED)
	progress("new_game end")
	if not check(made.get("ok", false), "One ordinary fresh seeded career initializes: " + str(made.get("message", ""))):
		finish(); return
	supply = int(c.state.coinSupply)
	var opening: Dictionary = c.state.duplicate(true)
	var people: float = crew_total(c.state)
	var geography: PackedByteArray = var_to_bytes([c.state.sector069, c.state.islandOwnership069])
	check(c.ocean_context064.regions.size() == 48 and definitions.HULLS.size() == 36 and c.Goods.SAILOR_WAGE == 100, "Existing48 groups,36 hull designs and100coin sailor-day remain")
	check(Money.total(c.state) == supply, "Opening accounts are exactly the ordinary finite world supply")
	note("normal_opening", {"seed":SEED, "coin_supply":supply, "people":people, "staging":"None: normal home admission and all later movement, accounts, cargo and combat are ordinary APIs."})
	for _slice in range(450):
		if _slice == 0: progress("first tick begin")
		var advanced: bool = tick()
		if _slice == 0: progress("first tick end")
		if not advanced: break
		if not actual_outcome().is_empty() and not history.recovery.is_empty(): break
	note("final_route_status", {"route":route().duplicate(true), "holding":str(c.state.get("shipping068", {}).get("holding", "")), "pending_days":c.pending_days})
	check(not history.corridor.is_empty(), "An affordable generic corridor naturally admits an existing serviced home trader")
	if not history.corridor.is_empty():
		var a: Dictionary = c.port(str(history.corridor.originId))
		var b: Dictionary = c.port(str(history.corridor.remoteId))
		check(not a.is_empty() and not b.is_empty() and str(a.regionId) != str(b.regionId) and str(a.regionId) not in ["shatter_coast", "glasswind_keys"] and str(b.regionId) not in ["shatter_coast", "glasswind_keys"], "Algorithm-selected endpoints belong to distinct actual generated groups")
	check(not history.load.is_empty() and not history.dispatch.is_empty(), "Real generated purchase and cash debit precede physical loaded dispatch")
	check(not history.choice.is_empty(), "Actual unexpired dated observation drives a pirate or patrol choice")
	check(not history.npc_contact.is_empty(), "The actual independent NPC engagement matches a two-NPC participant proposal without the player")
	var outcome: Dictionary = actual_outcome()
	check(not outcome.is_empty(), "Actual funded delivery or recorded purchased-cargo loss changes physical availability")
	check(not history.recovery.is_empty(), "Actual paid survivor repair or a fully funded material/labor yard replacement occurs")
	if not outcome.is_empty(): note("actual_outcome_branch", {"branch":"cargo_loss" if not history.loss.is_empty() else "delivery", "outcome":outcome})
	if not history.recovery.is_empty():
		check(float(history.load.day) <= float(history.dispatch.day) and float(history.dispatch.day) <= float(history.choice.get("day", -1)) \
			and float(history.choice.get("day", INF)) <= float(history.npc_contact.day) and float(history.npc_contact.day) <= float(outcome.get("day", -1)) \
			and float(outcome.get("day", INF)) <= float(history.recovery.day), "One actual dated load, dispatch, observed choice, contact, delivery/loss and funded recovery stays in order")
	check(Money.total(c.state) == supply and int(c.state.coinSupply) == supply, "Every purchase, wage, prize, service and normal yard keeps the original coin supply")
	check(absf(people - crew_total(c.state) - crew_losses) < 0.000001, "All original workers and crews reconcile with actual encounter casualties")
	check(geography == var_to_bytes([c.state.sector069, c.state.islandOwnership069]), "Actual chronology preserves seeded geography and mixed island ownership without076 transfers")
	var physical: Dictionary = Custody.check_state(c.state, c.data)
	check(physical.get("ok", false) and physical.get("ready", false), "Existing equipment preflight validates unique actual hull/item/wreck custody")
	var item_uids: Array = physical.get("itemUids", []).duplicate()
	item_uids.sort()
	note("closing_accounts", {"coin_supply":Money.total(c.state), "people":crew_total(c.state), "crew_losses":crew_losses, "holders":physical.get("holders", []), "item_uid_count":item_uids.size(), "item_uids_sha256":JSON.stringify(item_uids).sha256_text()})
	if failures == 0 and bounded():
		if save_actual("outcome") and legacy_boundary(opening): complete = true
	finish()

func finish() -> void:
	if workers.group_id >= 0: workers.finish(true)
	c = null
	check(complete and not expired, "The full finite chronology and compact legacy boundary actually complete")
	var elapsed: int = Time.get_ticks_msec() - started
	check(elapsed < BODY_LIMIT_MS, "Whole native fixture body including setup and owned worker cleanup stays below fifteen seconds")
	print(JSON.stringify({"fixture":"faction_strategy075", "checks":checks, "failures":failures, "elapsed_ms":elapsed,
		"complete":complete and not expired and failures == 0, "failure_labels":failure_labels, "observations":observations,
		"artifacts":artifacts, "limits":"Source fixture until Root executes. One ordinary finite seeded NPC corridor; no rendered, listening, whole-game quality or strict performance acceptance.074combat and073art require unchanged source proof."}))
	print("FactionStrategy075: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
