extends RefCounted
## One existing-harbor improvement and one contested negotiated surrender.
## Main-thread transactions only. Coins and people stay in existing accounts.
const Home = preload("res://scripts/home_harbor.gd")
const ToolingOps = preload("res://scripts/tooling_ops.gd")
const BoardingRules = preload("res://scripts/boarding.gd")
const Factions = preload("res://scripts/factions.gd")
const Money = preload("res://scripts/money.gd")
const Manifest = preload("res://scripts/hold_manifest.gd")
const Orders = preload("res://scripts/naval_orders.gd")
const Economy = preload("res://scripts/economy.gd")
const Goods = preload("res://scripts/goods.gd")

const WORK_DAYS: int = 2
const WORKERS: int = 2
const SUPPORT_CAPITAL: int = 800
const SUPPORT_GOODS: Dictionary = {"food": 2.0, "supplies": 1.0}
const STATUSES: Array = ["active", "interrupted", "withdrawn", "complete"]
const RANGE: float = 350.0

class QuoteView extends RefCounted:
	var state: Dictionary
	var data: Dictionary
	var selected: Dictionary
	func _init(c, p: Dictionary, materials: Dictionary):
		state = c.state.duplicate();data = c.data;selected = p.duplicate(true)
		state.relationships = c.state.get("relationships", {}).duplicate(true)
		state.ports = c.state.ports.duplicate()
		for i in range(state.ports.size()):
			if state.ports[i].id == p.id:state.ports[i] = selected
		for good in materials:selected.stocks[good] = float(selected.stocks.get(good, 0)) + float(materials[good])
	func current_port() -> Dictionary:return selected
	func port(id: String) -> Dictionary:
		for p in state.ports:
			if p.id == id:return p
		return {}
	func fail(message: String) -> Dictionary:return {"ok": false, "message": message}
	func ok(message: String) -> Dictionary:return {"ok": true, "message": message}

static func ensure(c) -> void:
	# A present malformed book is never repaired into fresh resources/progress.
	if not c.state.has("territorial076"):
		c.state.territorial076 = {"schema": 1, "improvement": {}, "control": {}}

static func _book(s: Dictionary) -> Dictionary:
	return s.get("territorial076", {}) if s.get("territorial076", {}) is Dictionary else {}

static func _port(s: Dictionary, id: String) -> Dictionary:
	for p in s.get("ports", []):
		if p is Dictionary and p.get("id") == id:return p
	return {}

static func _boat(s: Dictionary, uid: String) -> Dictionary:
	for b in s.get("fleet", []):
		if b is Dictionary and str(b.get("uid", "")) == uid:return b
	return {}

static func _result(ok: bool, message: String, extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {"ok": ok, "message": message}
	out.merge(extra, true)
	return out

static func _home(s: Dictionary, id: String) -> bool:
	var p: Dictionary = _port(s, id)
	return not p.is_empty() and str(p.get("regionId", "shatter_coast")) == "shatter_coast"

static func _near(c, id: String, reach: float = 65.0) -> bool:
	if not _home(c.state, id) or not c.state.get("path", []).is_empty():return false
	var location: Dictionary = c.state.get("world064", {})
	if location.get("layer", "home") != "home":return false
	if location.get("regionId", "shatter_coast") != "shatter_coast":return false
	return c.distance(c.state.position, _port(c.state, id)) < reach

static func _machine(c, id: String = "") -> Dictionary:
	var book: Dictionary = c.state.get("tooling", {})
	for item in book.get("items", []):
		if not item is Dictionary or (not id.is_empty() and item.get("id") != id):continue
		if item.get("kind") != "machine_tools" or item.get("location") != "cargo":continue
		if not BoardingRules._n(item.get("condition"), 1):continue
		if book.get("extracted", {}).get(item.get("sourceId", "")) != item.get("id"):continue
		var error: String = ToolingOps.Tooling._source_error(c.state, c.data,
			str(item.get("sourceId", "")), str(item.get("sourceSite", "")),
			"machine_tools", str(item.get("provenance", "")))
		if error.is_empty():return item
	return {}

static func _carried(c) -> bool:
	# Use the actual hull allocation, including machinery, passengers and lockers.
	var probe: Dictionary = c.state.duplicate(true)
	Manifest.allocate(probe)
	return probe.get("cargoManifest", {}).get("unassigned", {}).is_empty() \
		and c.cargo_weight() <= c.capacity() + 0.000001

static func _party(c) -> Dictionary:
	if not c.state.get("exploration", {}).get("assignment", {}).is_empty():return {}
	if not c.state.get("toolingRecovery", {}).is_empty():return {}
	var out: Dictionary = {}
	var left: int = WORKERS
	for b in Manifest.carriers(c.state):
		if float(b.crew) > float(b.get("crewMax", 0)):continue
		var spare: int = maxi(0, floori(float(b.crew) - float(b.get("wounded", 0)))
			- ceili(float(b.crewMin)) - int(b.get("shoreCrew", 0)))
		var n: int = mini(left, spare)
		if n > 0:out[str(b.uid)] = n;left -= n
		if left == 0:return out
	return {}

static func _reserve(c, job: Dictionary, party: Dictionary) -> void:
	job.crewByBoat = party
	for uid in party:
		var b: Dictionary = _boat(c.state, str(uid))
		b.shoreCrew = int(b.get("shoreCrew", 0)) + int(party[uid])

static func _release(c, job: Dictionary) -> void:
	for uid in job.get("crewByBoat", {}):
		var b: Dictionary = _boat(c.state, str(uid))
		if not b.is_empty():b.shoreCrew = maxi(0, int(b.get("shoreCrew", 0)) - int(job.crewByBoat[uid]))
	job.crewByBoat = {}

static func _crew_ok(s: Dictionary, job: Dictionary) -> bool:
	var count: int = 0
	for uid in job.get("crewByBoat", {}):
		var b: Dictionary = _boat(s, str(uid))
		var n: int = int(job.crewByBoat[uid])
		if b.is_empty() or b.get("sunk", false) or not str(b.get("storedPort", "")).is_empty():return false
		if b.get("mothballed", false) or b.get("needsHarborRepair", false):return false
		if float(b.crew) > float(b.get("crewMax", 0)):return false
		if float(b.crew) - float(b.get("wounded", 0)) < float(b.crewMin) + n:return false
		if int(b.get("shoreCrew", 0)) < n:return false
		count += n
	return count == WORKERS

static func _busy(s: Dictionary, except: String) -> bool:
	for key in ["improvement", "control"]:
		if key == except:continue
		var job: Dictionary = _book(s).get(key, {})
		if not job.get("crewByBoat", {}).is_empty():return true
	return false

static func view(c, port_id: String) -> Dictionary:
	var p: Dictionary = _port(c.state, port_id)
	var book: Dictionary = _book(c.state)
	var businesses: Array = []
	for b in c.state.get("businesses", []):
		if b.get("homePort") == port_id:businesses.append(Home.business_view(c.state, str(b.id)))
	return {"portId": port_id, "faction": str(p.get("faction", "")),
		"supported": _home(c.state, port_id), "improvement": book.get("improvement", {}).duplicate(true),
		"control": book.get("control", {}).duplicate(true), "businesses": businesses,
		"supportCapital": SUPPORT_CAPITAL, "workDays": WORK_DAYS,
		"workers": WORKERS, "wagePerPersonDay": Goods.SAILOR_WAGE,
		"supportGoodsPerDay": SUPPORT_GOODS.duplicate(true),
		"scope": "One existing Shatter Coast harbor at a time. Businesses retain their own assets and purses."}

static func quote_improve(c, port_id: String) -> Dictionary:
	if not _home(c.state, port_id) or not _near(c, port_id):return _result(false, "Dock at the existing Shatter Coast harbor to improve its berth.")
	if _busy(c.state, "improvement"):return _result(false, "Withdraw the other shore party first.")
	var old: Dictionary = _book(c.state).get("improvement", {})
	if not old.is_empty() and old.get("portId") != port_id:return _result(false, "076 retains one improvement at its original harbor.")
	if old.get("status") == "complete":return _result(false, "This funded warehouse and rented berth are already complete.")
	var item: Dictionary = _machine(c, str(old.get("machineryId", "")))
	if item.is_empty():return _result(false, "Bring the actual recovered machine tools in fleet cargo; at least two percent condition is required.")
	if not _carried(c):return _result(false, "All cargo and machinery must fit the actual traveling hulls.")
	var party: Dictionary = old.get("crewByBoat", {})
	if party.is_empty():party = _party(c)
	elif not _crew_ok(c.state, old):return _result(false, "Recall the interrupted party before assigning healthy replacement sailors.")
	if party.is_empty():return _result(false, "Two healthy existing sailors above minimum crews are required; recall other shore work first.")
	var materials: Dictionary = Home.KINDS.warehouse.materials.duplicate(true)
	# Forecast the actual carried contribution on a detached harbor; no live
	# quote normalization or requirement for a second set of destination goods.
	var quote: Dictionary = Home.quote(QuoteView.new(c, _port(c.state, port_id), materials if old.is_empty() else {}), "warehouse", port_id)
	if not quote.get("ok", false):return quote
	if not quote.get("affordable", false):return _result(false, "The captain must fund the actual warehouse setup and its normal working-capital reserve.", {"homeQuote": quote})
	var remaining: int = WORK_DAYS - int(old.get("paidDays", 0))
	if float(item.condition) + 0.000001 < remaining * 0.01:return _result(false, "The actual machinery needs one percent condition for each remaining work day.")
	for good in materials:
		if old.is_empty() and float(c.state.cargo.get(good, 0)) < float(materials[good]):return _result(false, "Carry the warehouse's actual timber, logs and iron to this harbor before starting.")
	if float(c.state.cargo.get("supplies", 0)) < remaining * 0.5:return _result(false, "Carry half a repair-kit lot for each remaining paid work day.")
	var payroll: Dictionary = Economy.daily_upkeep(c.state.fleet)
	if int(c.state.coins) < int(quote.cost) + int(payroll.wages) * remaining:return _result(false, "Retain warehouse capital and the fleet's actual payroll for the remaining work days.")
	return _result(true, "Two paid days using carried machinery and sailors, followed by the existing funded warehouse setup.",
		{"portId": port_id, "machineryId": str(item.id), "crewByBoat": party.duplicate(true),
		"materials": materials, "homeQuote": quote, "cost": int(quote.cost),
		"remainingDays": remaining, "payrollPerDay": int(payroll.wages), "workSupplies": remaining * 0.5})

static func improve(c, port_id: String) -> Dictionary:
	var quote: Dictionary = quote_improve(c, port_id)
	if not quote.get("ok", false):return quote
	ensure(c)
	var job: Dictionary = _book(c.state).improvement
	if job.is_empty():
		var p: Dictionary = _port(c.state, port_id)
		# Explicit contribution, not a sale/refund. The existing economy owns it now.
		for good in quote.materials:
			c.state.cargo[good] = float(c.state.cargo.get(good, 0)) - float(quote.materials[good])
			p.stocks[good] = float(p.stocks.get(good, 0)) + float(quote.materials[good])
		job.merge({"portId": port_id, "status": "active", "businessId": "",
			"machineryId": str(quote.machineryId), "crewByBoat": {},
			"startedDay": int(c.state.econDay), "lastPaidDay": int(c.state.econDay),
			"paidDays": 0, "materials": quote.materials.duplicate(true), "reason": ""})
	if job.crewByBoat.is_empty():_reserve(c, job, quote.crewByBoat)
	job.status = "active";job.reason = "Keep the moored party supplied and ordinary fleet payroll fully paid."
	Manifest.allocate(c.state)
	return _result(true, "Berth work underway. Donated materials stay at this harbor; setup capital is charged by HomeHarbor on completion.", {"improvement": job.duplicate(true)})

static func _owner_near(c, owner: Dictionary, p: Dictionary) -> bool:
	if Orders.enrolled066(c.state, str(owner.get("id", ""))):return false
	if str(owner.get("atPort", "")) == str(p.id):return true
	var patrol: Dictionary = Orders.find_patrol(c.state, str(owner.get("id", "")))
	return not patrol.is_empty() and patrol.get("active", false) \
		and c.distance(patrol, p) <= RANGE

static func _defender(c, p: Dictionary, id: String = "", skip: String = "") -> Dictionary:
	for owner in c.state.get("fleetOwners", []):
		if owner.get("id") == skip:continue
		if not id.is_empty() and owner.get("id") != id:continue
		if owner.get("faction") != p.get("faction") or not owner.get("active", false):continue
		if not _owner_near(c, owner, p):continue
		for b in owner.get("boats", []):
			if not b.get("sunk", false) and float(b.get("hp", 0)) > 0 \
				and float(b.get("crew", 0)) - float(b.get("wounded", 0)) >= float(b.get("crewMin", 1)) \
				and float(b.get("ammo", 0)) > 0 and float(b.get("fuel", 0)) >= 0.5:
				return owner
	return {}

static func _mandate(s: Dictionary, old: String, sponsor: String) -> String:
	if sponsor not in Factions.CANON or old == sponsor:return "Choose a different existing faction as the proposed sovereign."
	var standing: Dictionary = Factions.standing(s, sponsor)
	if standing.get("hostile", true) or int(standing.get("score", 0)) < Factions.FRIENDLY_ENTER:return "Earn friendly standing with the sponsoring faction first."
	if Factions.relation(s, old, sponsor) > Factions.ENEMY_AT:return "Peaceful factions cannot use this contested surrender operation."
	if not Factions.is_hostile(s, old):return "The harbor's sovereign must be an actual hostile opponent of your fleet."
	return ""

static func start(c, port_id: String, new_faction: String) -> Dictionary:
	if not _near(c, port_id):return _result(false, "Stop at this existing Shatter Coast harbor's actual berth to land the support party.")
	if _busy(c.state, "control"):return _result(false, "Withdraw the berth construction party before opening contested talks.")
	var old: Dictionary = _book(c.state).get("control", {})
	if not old.is_empty() and (old.get("portId") != port_id or old.get("newFaction") != new_faction):return _result(false, "076 retains this one harbor and sponsor; resume its existing operation.")
	if old.get("status") == "complete":return _result(true, "The negotiated sovereign transfer is already recorded.", {"changed": false})
	var p: Dictionary = _port(c.state, port_id)
	var reason: String = _mandate(c.state, str(p.faction), new_faction)
	if not reason.is_empty():return _result(false, reason)
	if not _carried(c):return _result(false, "Restore the actual fleet's cargo and transport capacity first.")
	var party: Dictionary = old.get("crewByBoat", {})
	if party.is_empty():party = _party(c)
	elif not _crew_ok(c.state, old):return _result(false, "Withdraw and recall the interrupted support party first.")
	if party.is_empty():return _result(false, "Support requires two healthy sailors from existing boats above their minimum crews.")
	var defender: Dictionary = {}
	if not old.get("battleWon", false):
		defender = _defender(c, p, str(old.get("defenderId", "")))
		if defender.is_empty():return _result(false, "An actual hostile defending fleet must be present; fleet presence alone gives no surrender claim.")
	var remaining: int = WORK_DAYS - int(old.get("supportDays", 0))
	for good in SUPPORT_GOODS:
		if float(c.state.cargo.get(good, 0)) < float(SUPPORT_GOODS[good]) * remaining:return _result(false, "Carry real civilian food and repair kits for the remaining support days.")
	var capital: int = SUPPORT_CAPITAL if old.is_empty() else 0
	var payroll: Dictionary = Economy.daily_upkeep(c.state.fleet)
	if not BoardingRules._w(c.state.get("coins"), BoardingRules.CASH) or int(c.state.coins) < capital + int(payroll.wages) * remaining:return _result(false, "Fund the existing fleet payroll and 800-coin harbor operating contribution.")
	if not BoardingRules._w(p.get("governmentPurse"), BoardingRules.CASH) or int(p.governmentPurse) + capital > BoardingRules.CASH:return _result(false, "The existing harbor treasury cannot accept the support contribution.")
	ensure(c)
	var job: Dictionary = _book(c.state).control
	if job.is_empty():
		if not Money.move(c.state, "coins", p, "governmentPurse", capital, "076 civilian harbor operating support", c.state.moneyLog):return _result(false, "The actual operating contribution could not be paid.")
		var uids: Array = []
		for b in defender.boats:uids.append(str(b.uid))
		job.merge({"portId": port_id, "fromFaction": str(p.faction), "newFaction": new_faction,
			"status": "active", "defenderId": str(defender.id), "defenderUids": uids,
			"crewByBoat": {}, "startedDay": int(c.state.econDay), "lastPaidDay": int(c.state.econDay),
			"supportDays": 0, "battleSeq": 0, "startBattleSeq": int(c.state.get("battleSeq", 0)),
			"battleWon": false, "battleSource": "", "objective": false,
			"funded": capital, "supportGoods": {"food": 0.0, "supplies": 0.0}, "reason": ""})
	if job.crewByBoat.is_empty():_reserve(c, job, party)
	job.status = "active";job.reason = "Funded talks need an actual victory against the selected defender and two supplied paid support days."
	return _result(true, str(job.reason), {"control": job.duplicate(true), "changed": true})

static func withdraw(c) -> Dictionary:
	var changed: bool = false
	for key in ["improvement", "control"]:
		var job: Dictionary = _book(c.state).get(key, {})
		if job.is_empty() or job.get("status") in ["complete", "withdrawn"]:continue
		_release(c, job)
		job.status = "withdrawn";job.reason = "Party recalled to its original hulls. Earned wages, wear, donations and operating support remain spent; progress can resume here."
		changed = true
	return _result(true, "Shore work withdrawn; existing assets and paid contributions remain with their actual recipients.", {"changed": changed})

static func paid_day(c, paid: int, due: int) -> void:
	# Called ONCE immediately after ordinary fleet payroll, before its economy day.
	var stamp: int = int(c.state.econDay) + 1
	for key in ["improvement", "control"]:
		var job: Dictionary = _book(c.state).get(key, {})
		if job.get("status") != "active" or stamp <= int(job.get("lastPaidDay", stamp)):continue
		job.lastPaidDay = stamp
		var progress: String = "paidDays" if key == "improvement" else "supportDays"
		if int(job[progress]) >= WORK_DAYS:continue
		var costs: Dictionary = Economy.daily_upkeep(c.state.fleet)
		if due <= 0 or due != int(costs.wages) or paid != due or int(c.state.get("wageArrears", 0)) > 0:
			job.status = "interrupted";job.reason = "Ordinary sailor payroll was not fully paid; unpaid work does not count."
			continue
		if not _near(c, str(job.portId)) or not _crew_ok(c.state, job):
			job.status = "interrupted";job.reason = "The original healthy party must be present at this harbor's berth."
			continue
		if float(c.state.cargo.get("food", 0)) < float(costs.food):
			job.status = "interrupted";job.reason = "The sailors lack their actual ordinary rations."
			continue
		if key == "improvement":
			var item: Dictionary = _machine(c, str(job.machineryId))
			if item.is_empty() or float(item.condition) + 0.000001 < 0.01 or float(c.state.cargo.get("supplies", 0)) < 0.5:
				job.status = "interrupted";job.reason = "Carried machinery or work repair kits are missing."
				continue
			c.state.cargo.supplies = float(c.state.cargo.supplies) - 0.5
			item.condition = maxf(0, float(item.condition) - 0.01)
		else:
			var p: Dictionary = _port(c.state, str(job.portId))
			var reason: String = _mandate(c.state, str(job.fromFaction), str(job.newFaction))
			var supplied: bool = reason.is_empty() and p.get("faction") == job.fromFaction
			for good in SUPPORT_GOODS:
				var needed: float = float(SUPPORT_GOODS[good]) + (float(costs.food) if good == "food" else 0.0)
				if float(c.state.cargo.get(good, 0)) < needed:supplied = false
			if not supplied:
				job.status = "interrupted";job.reason = "Hostile mandate or carried civilian support is missing; peace also suspends the operation."
				continue
			for good in SUPPORT_GOODS:
				c.state.cargo[good] = float(c.state.cargo.get(good, 0)) - float(SUPPORT_GOODS[good])
				p.publicStores[good] = float(p.publicStores.get(good, 0)) + float(SUPPORT_GOODS[good])
				job.supportGoods[good] = float(job.supportGoods[good]) + float(SUPPORT_GOODS[good])
		job[progress] = int(job[progress]) + 1

static func daily(c) -> void:
	for key in ["improvement", "control"]:
		var job: Dictionary = _book(c.state).get(key, {})
		if job.get("status") not in ["active", "interrupted"]:continue
		if not job.get("crewByBoat", {}).is_empty() and not _crew_ok(c.state, job):
			_release(c, job)
			job.status = "interrupted";job.reason = "The original party was wounded, lost or recalled; healthy replacement sailors must be assigned explicitly."
			continue
		if job.status != "active":continue
		if not _near(c, str(job.portId)):
			job.status = "interrupted";job.reason = "Work interrupted away from the actual harbor; return and resume or withdraw."
			continue
		if key == "control":
			var reason: String = _mandate(c.state, str(job.fromFaction), str(job.newFaction))
			if not reason.is_empty():job.status = "interrupted";job.reason = reason
			continue
		if int(job.paidDays) < WORK_DAYS:continue
		var built: Dictionary = Home.establish(c, "warehouse", str(job.portId))
		if not built.get("ok", false):
			job.status = "interrupted";job.reason = str(built.get("message", "Actual warehouse setup is currently unavailable."))
			continue
		job.businessId = str(built.business.id)
		job.status = "complete";job.reason = "Paid warehouse and rented berth completed; its business remains distinct from harbor sovereignty."
		_release(c, job)
		c.log_entry(str(job.reason))

static func after_battle(c, owner: Dictionary, result: String, objective_only: bool, physical: Dictionary = {}) -> void:
	for key in ["improvement", "control"]:
		var party: Dictionary = _book(c.state).get(key, {})
		if not party.get("crewByBoat", {}).is_empty() and not _crew_ok(c.state, party):
			_release(c, party)
			party.status = "interrupted";party.reason = "The actual contest interrupted the original shore party; lost sailors are not replaced."
	var job: Dictionary = _book(c.state).get("control", {})
	if job.get("status") not in ["active", "interrupted"] or owner.get("id") != job.get("defenderId"):return
	if not _near(c, str(job.portId), RANGE) or physical.get("result") != result or physical.has("startError"):return
	if float(physical.get("time", 0)) <= 0 or str(physical.get("engagementSource060", "")).is_empty():return
	if int(c.state.get("battleSeq", 0)) <= int(job.startBattleSeq):return
	var enemy: bool = false
	var player: bool = false
	for ship in physical.get("ships", []):
		if ship.get("team") == "enemy" and str(ship.get("uid", "")) in job.defenderUids:enemy = true
		if ship.get("team") == "player" and ship.get("_serviceStart060", {}).get("team") == "player":player = true
	if not enemy or not player:return
	if result == "won" and objective_only and physical.get("objectiveSuccess", false) != true:return
	job.battleSeq = int(c.state.battleSeq);job.battleSource = str(physical.engagementSource060)
	job.objective = objective_only;job.battleWon = result == "won"
	if not job.battleWon:
		_release(c, job)
		job.status = "interrupted";job.reason = "The actual coastal contest was lost or abandoned. Support remains spent; resume only with real surviving sailors."
	else:
		job.reason = "The selected defender lost the actual coastal contest. Finish funded local support, then negotiate explicitly."

static func negotiate(c) -> Dictionary:
	var job: Dictionary = _book(c.state).get("control", {})
	if job.get("status") == "complete":return _result(true, "The existing negotiated transfer is already recorded.", {"changed": false})
	if job.get("status") != "active":return _result(false, "Resume the funded harbor operation before negotiating surrender.")
	if not _near(c, str(job.portId)) or not _crew_ok(c.state, job):return _result(false, "The actual support party must be present at the harbor berth.")
	if not job.battleWon or int(job.supportDays) < WORK_DAYS:return _result(false, "An actual selected-defender victory and two supplied, fully paid support days are required.")
	var p: Dictionary = _port(c.state, str(job.portId))
	var reason: String = _mandate(c.state, str(job.fromFaction), str(job.newFaction))
	if not reason.is_empty():return _result(false, reason)
	if p.get("faction") != job.fromFaction:return _result(false, "The original sovereign no longer controls this harbor.")
	# Winning an actual relief objective defeats this selected fleet's blockade,
	# even if it survives. A different defending fleet still blocks surrender.
	if not _defender(c, p, "", str(job.defenderId) if job.objective else "").is_empty():return _result(false, "Another existing hostile fleet still defends these waters; resolve that pressure before surrender.")
	p.faction = str(job.newFaction)
	if p.get("defenses") is Dictionary:
		# Surrender changes orders/readiness, never guns, crew, ammunition or arrears.
		BoardingRules._disable(p.defenses, "Negotiated harbor surrender; existing crew and stores retained")
	job.status = "complete";job.reason = "Negotiated harbor sovereignty after the selected actual contest and paid support; private assets retained."
	_release(c, job)
	c.log_entry(str(job.reason))
	return _result(true, str(job.reason), {"changed": true, "portId": str(job.portId), "fromFaction": str(job.fromFaction), "newFaction": str(job.newFaction)})

static func validate(saved: Dictionary, world: Dictionary) -> String:
	if not saved.has("territorial076"):return _ownership_error(saved, world, {})
	var book: Variant = saved.territorial076
	if not book is Dictionary or book.keys().size() != 3 or not BoardingRules._w(book.get("schema"), 1) or book.get("schema") != 1:return "Invalid territorial076 book."
	if not BoardingRules._w(saved.get("econDay"), BoardingRules.CASH):return "Territorial work requires published economic days."
	var ports: Dictionary = {}
	for p in world.get("PORTS", []):ports[str(p.id)] = p
	for key in ["improvement", "control"]:
		var raw: Variant = book.get(key)
		if not raw is Dictionary:return "Invalid territorial operation."
		if raw.is_empty():continue
		var j: Dictionary = raw
		if j.get("status") not in STATUSES or not ports.has(j.get("portId")):return "Invalid territorial harbor or status."
		if not j.get("reason") is String or j.reason.length() > 1000:return "Invalid territorial explanation."
		for field in ["startedDay", "lastPaidDay"]:
			if not BoardingRules._w(j.get(field), BoardingRules.CASH) or j[field] > saved.econDay:return "Invalid territorial work date."
		if j.startedDay > j.lastPaidDay:return "Territorial paid work predates its start."
		if not j.get("crewByBoat") is Dictionary or j.crewByBoat.size() > WORKERS:return "Invalid territorial crew allocation."
		var count: int = 0
		for uid in j.crewByBoat:
			if not uid is String or not BoardingRules._w(j.crewByBoat[uid], WORKERS) or int(j.crewByBoat[uid]) < 1:return "Invalid assigned territorial sailors."
			count += int(j.crewByBoat[uid])
		if count not in [0, WORKERS] or (j.status == "active" and count != WORKERS):return "Territorial party size does not reconcile."
		if count > 0 and not _crew_ok(saved, j):return "Territorial sailors are not reserved on their actual healthy hulls."
		if j.status in ["complete", "withdrawn"] and count != 0:return "Finished territorial work retains a shore party."
		var progress: String = "paidDays" if key == "improvement" else "supportDays"
		if not BoardingRules._w(j.get(progress), WORK_DAYS) or int(j[progress]) > int(j.lastPaidDay) - int(j.startedDay):return "Invalid paid territorial work days."
		if key == "improvement":
			if not j.get("businessId") is String or not j.get("machineryId") is String:return "Invalid territorial asset identity."
			if j.get("materials") != Home.KINDS.warehouse.materials:return "Invalid territorial material contribution."
			var found: bool = false
			for item in saved.get("tooling", {}).get("items", []):
				if item.get("id") == j.machineryId and item.get("kind") == "machine_tools":found = true
			if not found:return "Missing original territorial machinery record."
			if j.status == "complete":
				var b: Dictionary = Home.business_view(saved, str(j.businessId))
				if int(j.paidDays) != WORK_DAYS or b.get("kind") != "warehouse" or b.get("homePort") != j.portId:return "Completed territorial berth lacks its actual paid warehouse."
			elif j.businessId != "":return "Unfinished territorial berth claims a business."
		else:
			if j.get("fromFaction") != ports[j.portId].faction or j.get("newFaction") not in Factions.CANON or j.fromFaction == j.newFaction:return "Invalid territorial sovereign parties."
			if not j.get("defenderId") is String or j.defenderId.is_empty() or not j.get("defenderUids") is Array or j.defenderUids.is_empty() or j.defenderUids.size() > 64:return "Invalid original territorial defender."
			var seen: Dictionary = {}
			for uid in j.defenderUids:
				if not uid is String or uid.is_empty() or seen.has(uid):return "Invalid territorial defender hull identity."
				seen[uid] = true
			for field in ["battleSeq", "startBattleSeq"]:
				if not BoardingRules._w(j.get(field), BoardingRules.CASH) or int(j[field]) > int(saved.get("battleSeq", 0)):return "Invalid territorial contest sequence."
			if not j.get("battleWon") is bool or not j.get("objective") is bool or not j.get("battleSource") is String:return "Invalid territorial contest receipt."
			if j.battleWon and (j.battleSeq <= j.startBattleSeq or j.battleSource.is_empty()):return "Territorial victory has no later actual contest."
			if j.get("funded") != SUPPORT_CAPITAL:return "Invalid funded territorial operating contribution."
			if not j.get("supportGoods") is Dictionary or j.supportGoods.size() != SUPPORT_GOODS.size():return "Invalid territorial support inventory."
			for good in SUPPORT_GOODS:
				if not BoardingRules._n(j.supportGoods.get(good)) or float(j.supportGoods[good]) != float(j.supportDays) * float(SUPPORT_GOODS[good]):return "Territorial support goods and paid days disagree."
			if j.status == "complete" and (not j.battleWon or j.supportDays != WORK_DAYS):return "Sovereignty changed without actual contest and funded support."
	return _ownership_error(saved, world, book.control)

static func _ownership_error(saved: Dictionary, world: Dictionary, control: Dictionary) -> String:
	# Removing the book cannot turn an unexplained change into a legacy save.
	for definition in world.get("PORTS", []):
		var actual: Dictionary = _port(saved, str(definition.id))
		if actual.is_empty():continue # Existing campaign validation owns missing ports.
		var expected: String = str(definition.faction)
		if control.get("portId") == definition.id and control.get("status") == "complete":expected = str(control.newFaction)
		if actual.get("faction") != expected:return "Harbor sovereign change has no completed territorial operation."
	return ""
