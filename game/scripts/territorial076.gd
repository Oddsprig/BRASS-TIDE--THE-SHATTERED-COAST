extends RefCounted
## Paid harbor development and one supplied negotiated corridor-harbor surrender.
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
	func current_port() -> Dictionary:
		return selected if str(selected.get("regionId", "shatter_coast")) == "shatter_coast" else {}
	func work_port070() -> Dictionary:return selected
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

static func _generated_improve_port(s: Dictionary, id: String) -> bool:
	return Home._generated_harbor084(s, id)

static func _improve_supported(s: Dictionary, id: String) -> bool:
	return _home(s, id) or _generated_improve_port(s, id)

static func _corridor085(s: Dictionary, id: String) -> Dictionary:
	var job: Dictionary = _book(s).get("control", {})
	var route: Dictionary = s.get("shipping068", {}).get("model", {}).get("route", {})
	var corridor: Dictionary = job.get("corridor085", {}) if job.get("portId") == id else route.get("corridor075", {})
	if corridor.is_empty() and job.get("portId") == id: corridor = route.get("corridor075", {})
	if not _corridor_valid085(s, corridor, id):return {}
	return {"ownerId": str(corridor.ownerId), "originId": str(corridor.originId), "remoteId": str(corridor.remoteId)}

static func _corridor_valid085(s: Dictionary, corridor: Dictionary, id: String) -> bool:
	if not _generated_improve_port(s, id):return false
	if id not in [str(corridor.get("originId", "")), str(corridor.get("remoteId", ""))]:return false
	var origin: Dictionary = _port(s, str(corridor.get("originId", "")))
	var remote: Dictionary = _port(s, str(corridor.get("remoteId", "")))
	if origin.is_empty() or remote.is_empty() or origin.get("regionId") == remote.get("regionId"):return false
	if not _generated_improve_port(s, str(origin.id)) or not _generated_improve_port(s, str(remote.id)):return false
	for owner in s.get("fleetOwners", []):
		if owner.get("id") == corridor.get("ownerId") and owner.get("kind") == "trader" and not owner.get("playerCompany", false):return true
	return false

static func _control_supported(s: Dictionary, id: String) -> bool:
	return _home(s, id) or not _corridor085(s, id).is_empty()

## Physical hostile-berth presence is distinct from permission for civilian
## services. Only this operation's original sailors may already be ashore.
static func _control_near(c, id: String, reach: float = -1.0) -> bool:
	if _home(c.state, id):return _near(c, id, 65.0 if reach < 0 else reach)
	if not _control_supported(c.state, id):return false
	var p: Dictionary = _port(c.state, id)
	var location: Dictionary = c.state.get("world064", {})
	if location.get("layer") != "local" or location.get("regionId") != p.get("regionId"):return false
	if not c.state.get("path", []).is_empty() or not c.state.get("exploration", {}).get("assignment", {}).is_empty() or not c.state.get("toolingRecovery", {}).is_empty():return false
	# Campaign validates a battle before this range-only settlement callback;
	# its own battle lock is cleared after publishing the control receipt.
	if reach < 0 and c is Object:
		if "travel_lock064" in c and not str(c.travel_lock064).is_empty():return false
		if "events" in c and c.events.any(func(e):return str(e.get("kind", "")) in ["encounter", "ocean_encounter066", "defeat"]):return false
	var position: Dictionary = c.state.get("position", {})
	if not BoardingRules._n(position.get("x")) or not BoardingRules._n(position.get("y")):return false
	var job: Dictionary = _book(c.state).get("control", {})
	var party: Dictionary = job.get("crewByBoat", {}) if job.get("portId") == id else {}
	for b in c.state.get("fleet", []):
		if int(b.get("shoreCrew", 0)) != int(party.get(str(b.get("uid", "")), 0)):return false
	return c.distance(position, p) < (40.0 if reach < 0 else reach)

static func _can_chain_control085(s: Dictionary, old: Dictionary, id: String) -> bool:
	return old.get("status") == "complete" and not old.has("priorCompleted") and _home(s, str(old.get("portId", ""))) and not _corridor085(s, id).is_empty()

static func _defender_uid085(s: Dictionary, job: Dictionary, uid: String) -> bool:
	for owner in s.get("fleetOwners", []):
		if owner.get("id") == job.defenderId and owner.get("boats", []).any(func(b):return str(b.get("uid", "")) == uid):return true
	for wreck in s.get("wrecks", []):
		if str(wreck.get("uid", "")) == uid and not str(job.battleSource).is_empty() and wreck.get("sourceId") == job.battleSource:return true
	for boat in s.get("fleet", []) + s.get("boardingPrizes", []):
		if boat.get("captureSecured", false) and str(boat.get("uid", "")) == uid:return true
	return false

static func _remote_work_port(c, id: String) -> Dictionary:
	if c == null or not c.has_method("work_port070"):return {}
	var job: Dictionary = _book(c.state).get("improvement", {})
	var unreserve: bool = job.get("status") == "active" and str(job.get("portId", "")) == id and not job.get("crewByBoat", {}).is_empty()
	if unreserve:
		for uid in job.crewByBoat:
			var b: Dictionary = _boat(c.state, str(uid))
			if not b.is_empty():b.shoreCrew = maxi(0, int(b.get("shoreCrew", 0)) - int(job.crewByBoat[uid]))
	var wp: Dictionary = c.work_port070()
	if unreserve:
		for uid in job.crewByBoat:
			var b: Dictionary = _boat(c.state, str(uid))
			if not b.is_empty():b.shoreCrew = int(b.get("shoreCrew", 0)) + int(job.crewByBoat[uid])
	return wp

static func _improve_near(c, id: String, reach: float = 65.0) -> bool:
	if _home(c.state, id):return _near(c, id, reach)
	if not _generated_improve_port(c.state, id) or not c.state.get("path", []).is_empty():return false
	var wp: Dictionary = _remote_work_port(c, id)
	return not wp.is_empty() and str(wp.get("id", "")) == id

static func _can_chain_improvement084(s: Dictionary, raw_imp: Dictionary, port_id: String) -> bool:
	if raw_imp.is_empty() or str(raw_imp.get("status", "")) != "complete":return false
	if raw_imp.has("priorCompleted"):return false
	var old_port: String = str(raw_imp.get("portId", ""))
	if old_port.is_empty() or old_port == port_id:return false
	return _home(s, old_port) != _home(s, port_id) and _improve_supported(s, port_id)

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
	var raw_imp: Dictionary = book.get("improvement", {})
	var imp_view: Dictionary = raw_imp.duplicate(true)
	if raw_imp.get("priorCompleted") is Dictionary and str(raw_imp.priorCompleted.get("portId", "")) == port_id:
		imp_view = raw_imp.priorCompleted.duplicate(true)
	var businesses: Array = []
	for b in c.state.get("businesses", []):
		if b.get("homePort") == port_id:businesses.append(Home.business_view(c.state, str(b.id)))
	return {"portId": port_id, "faction": str(p.get("faction", "")),
		"supported": _improve_supported(c.state, port_id),
		"controlSupported": _control_supported(c.state, port_id),
		"isRemote084": _generated_improve_port(c.state, port_id),
		"improvement": imp_view,
		"control": book.get("control", {}).duplicate(true), "businesses": businesses,
		"supportCapital": SUPPORT_CAPITAL, "workDays": WORK_DAYS,
		"workers": WORKERS, "wagePerPersonDay": Goods.SAILOR_WAGE,
		"supportGoodsPerDay": SUPPORT_GOODS.duplicate(true),
		"scope": "Paid warehouse development and one supplied harbor contest on the existing two-group trade corridor; island jurisdictions and private businesses remain separate."}

static func quote_improve(c, port_id: String) -> Dictionary:
	if not _improve_supported(c.state, port_id) or not _improve_near(c, port_id):
		return _result(false, "Dock at the existing Shatter Coast harbor to improve its berth." if _home(c.state, port_id) else "Dock at the charted local harbor berth to improve its warehouse.")
	if _busy(c.state, "improvement"):return _result(false, "Withdraw the other shore party first.")
	var raw_imp: Dictionary = _book(c.state).get("improvement", {})
	var old: Dictionary = {}
	if raw_imp.get("priorCompleted") is Dictionary and str(raw_imp.priorCompleted.get("portId", "")) == port_id:
		old = raw_imp.priorCompleted
	elif not _can_chain_improvement084(c.state, raw_imp, port_id):
		old = raw_imp
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
	if not old.is_empty() and old.get("reservedMaterials") != materials:return _result(false, "This project lacks its actual reserved construction materials; old spent contributions cannot be recreated.")
	# Forecast the carried bill before start, or the actual project inventory on
	# resume. Neither read-only quote lends these goods to the market economy.
	var quote: Dictionary = Home.quote(QuoteView.new(c, _port(c.state, port_id), materials if old.is_empty() else old.reservedMaterials), "warehouse", port_id)
	if not quote.get("ok", false):return quote
	var bill: Dictionary = {"homeQuote": quote, "cost": int(quote.cost),
		"grossCost": int(quote.cost), "cashRequired": int(quote.cost),
		"materialCredit": int(quote.materialCost), "netCost": int(quote.cost) - int(quote.materialCost)}
	if not quote.get("affordable", false):return _result(false, "Retain the gross warehouse setup and working capital temporarily; supplied material value is credited from the harbor on completion.", bill)
	var remaining: int = WORK_DAYS - int(old.get("paidDays", 0))
	if float(item.condition) + 0.000001 < remaining * 0.01:return _result(false, "The actual machinery needs one percent condition for each remaining work day.")
	for good in materials:
		if old.is_empty() and float(c.state.cargo.get(good, 0)) < float(materials[good]):return _result(false, "Carry the warehouse's actual timber, logs and iron to this harbor before starting.")
	if float(c.state.cargo.get("supplies", 0)) < remaining * 0.5:return _result(false, "Carry half a repair-kit lot for each remaining paid work day.")
	var payroll: Dictionary = Economy.daily_upkeep(c.state.fleet)
	if float(c.state.cargo.get("food", 0)) < float(payroll.food) * remaining:return _result(false, "Carry the fleet's ordinary rations for every remaining paid work day.")
	if int(c.state.coins) < int(quote.cost) + int(payroll.wages) * remaining:return _result(false, "Retain warehouse capital and the fleet's actual payroll for the remaining work days.")
	bill.merge(
		{"portId": port_id, "machineryId": str(item.id), "crewByBoat": party.duplicate(true),
		"materials": materials,
		"remainingDays": remaining, "payrollPerDay": int(payroll.wages), "workSupplies": remaining * 0.5})
	return _result(true, "Two paid days using carried machinery and sailors, followed by funded warehouse setup with one supplied-material credit.", bill)

static func improve(c, port_id: String) -> Dictionary:
	var quote: Dictionary = quote_improve(c, port_id)
	if not quote.get("ok", false):return quote
	ensure(c)
	var job: Dictionary = _book(c.state).improvement
	var prior: Dictionary = job.duplicate(true) if _can_chain_improvement084(c.state, job, port_id) else {}
	if job.is_empty() or not prior.is_empty():
		# Actual carried goods become this harbor project's inventory, once. They
		# are unavailable to market production and remain here during withdrawal.
		for good in quote.materials:
			c.state.cargo[good] = float(c.state.cargo.get(good, 0)) - float(quote.materials[good])
		job.clear()
		job.merge({"portId": port_id, "status": "active", "businessId": "",
			"machineryId": str(quote.machineryId), "crewByBoat": {},
			"startedDay": int(c.state.econDay), "lastPaidDay": int(c.state.econDay),
			"paidDays": 0, "materials": quote.materials.duplicate(true),
			"reservedMaterials": quote.materials.duplicate(true), "setupBill": {}, "reason": ""})
		if not prior.is_empty():job["priorCompleted"] = prior
	if job.crewByBoat.is_empty():_reserve(c, job, quote.crewByBoat)
	job.status = "active";job.reason = "Keep the moored party supplied and ordinary fleet payroll fully paid."
	Manifest.allocate(c.state)
	return _result(true, "Berth work underway. Materials stay reserved for this project at this harbor; funded setup credits their value once on completion.", {"improvement": job.duplicate(true)})

static func _owner_near(c, owner: Dictionary, p: Dictionary) -> bool:
	if Orders.enrolled066(c.state, str(owner.get("id", ""))):
		if _home(c.state, str(p.id)):return false
		var location: Dictionary = Orders.canonical_location068(c.state, str(owner.id))
		var world: Dictionary = location.get("world064", {})
		var layer: String = "home" if _home(c.state, str(p.id)) else "local"
		return world.get("layer") == layer and world.get("regionId") == p.get("regionId", "shatter_coast") and location.get("position") is Dictionary and c.distance(location.position, p) <= RANGE
	if not _home(c.state, str(p.id)):return false
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
	if not _control_near(c, port_id):return _result(false, "Stop at this harbor's actual berth on its chart; remote contests require a known endpoint of the existing supplied trade corridor.")
	if _busy(c.state, "control"):return _result(false, "Withdraw the berth construction party before opening contested talks.")
	var old: Dictionary = _book(c.state).get("control", {})
	var prior: Dictionary = old.duplicate(true) if _can_chain_control085(c.state, old, port_id) else {}
	if not prior.is_empty():old = {}
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
		if not _home(c.state, port_id) and str(defender.id) != str(_corridor085(c.state, port_id).get("ownerId", "")):return _result(false, "The existing corridor's actual defending owner must be physically present here.")
	var remaining: int = WORK_DAYS - int(old.get("supportDays", 0))
	var payroll: Dictionary = Economy.daily_upkeep(c.state.fleet)
	for good in SUPPORT_GOODS:
		var per_day: float = float(SUPPORT_GOODS[good]) + (float(payroll.food) if good == "food" else 0.0)
		if float(c.state.cargo.get(good, 0)) < per_day * remaining:return _result(false, "Carry civilian support food, the fleet's ordinary rations and repair kits for every remaining support day.")
	var capital: int = SUPPORT_CAPITAL if old.is_empty() else 0
	if not BoardingRules._w(c.state.get("coins"), BoardingRules.CASH) or int(c.state.coins) < capital + int(payroll.wages) * remaining:return _result(false, "Fund the existing fleet payroll and 800-coin harbor operating contribution.")
	if not BoardingRules._w(p.get("governmentPurse"), BoardingRules.CASH) or int(p.governmentPurse) + capital > BoardingRules.CASH:return _result(false, "The existing harbor treasury cannot accept the support contribution.")
	ensure(c)
	var job: Dictionary = _book(c.state).control
	if job.is_empty() or not prior.is_empty():
		if not Money.move(c.state, "coins", p, "governmentPurse", capital, "076 civilian harbor operating support", c.state.moneyLog):return _result(false, "The actual operating contribution could not be paid.")
		var uids: Array = []
		for b in defender.boats:uids.append(str(b.uid))
		job.clear()
		job.merge({"portId": port_id, "fromFaction": str(p.faction), "newFaction": new_faction,
			"status": "active", "defenderId": str(defender.id), "defenderUids": uids,
			"crewByBoat": {}, "startedDay": int(c.state.econDay), "lastPaidDay": int(c.state.econDay),
			"supportDays": 0, "battleSeq": 0, "startBattleSeq": int(c.state.get("battleSeq", 0)),
			"battleWon": false, "battleSource": "", "objective": false,
			"funded": capital, "supportGoods": {"food": 0.0, "supplies": 0.0}, "reason": ""})
		if not prior.is_empty():job.priorCompleted = prior
		if not _home(c.state, port_id):job.corridor085 = _corridor085(c.state, port_id)
	if job.crewByBoat.is_empty():_reserve(c, job, party)
	job.status = "active";job.reason = "Funded talks need an actual victory against the selected defender and two supplied paid support days."
	return _result(true, str(job.reason), {"control": job.duplicate(true), "changed": true})

static func withdraw(c) -> Dictionary:
	var changed: bool = false
	for key in ["improvement", "control"]:
		var job: Dictionary = _book(c.state).get(key, {})
		if job.is_empty() or job.get("status") in ["complete", "withdrawn"]:continue
		_release(c, job)
		job.status = "withdrawn";job.reason = "Party recalled to its original hulls. Project materials stay reserved here; earned wages, wear and operating support remain spent. Progress can resume here."
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
		var at_berth: bool = _improve_near(c, str(job.portId)) if key == "improvement" else _control_near(c, str(job.portId))
		if not at_berth or not _crew_ok(c.state, job):
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
		var at_berth: bool = _improve_near(c, str(job.portId)) if key == "improvement" else _control_near(c, str(job.portId))
		if not at_berth:
			job.status = "interrupted";job.reason = "Work interrupted away from the actual harbor; return and resume or withdraw."
			continue
		if key == "control":
			var reason: String = _mandate(c.state, str(job.fromFaction), str(job.newFaction))
			if not reason.is_empty():job.status = "interrupted";job.reason = reason
			continue
		if int(job.paidDays) < WORK_DAYS:continue
		if job.get("reservedMaterials") != Home.KINDS.warehouse.materials:
			job.status = "interrupted";job.reason = "The project's actual reserved construction materials are missing; no replacement goods are granted."
			continue
		var p: Dictionary = _port(c.state, str(job.portId))
		var stocks: Dictionary = p.stocks.duplicate(true)
		var held_party: Dictionary = job.get("crewByBoat", {}).duplicate(true)
		_release(c, job)
		# A synchronous handoff to existing paid setup. On refusal, restore the
		# exact prior stocks (including absent keys), leaving our held bill intact.
		for good in job.reservedMaterials:
			p.stocks[good] = float(p.stocks.get(good, 0)) + float(job.reservedMaterials[good])
		var quote: Dictionary = Home.quote(c, "warehouse", str(job.portId))
		var built: Dictionary = Home.establish(c, "warehouse", str(job.portId)) if quote.get("ok", false) else quote
		if not built.get("ok", false):
			p.stocks = stocks
			_reserve(c, job, held_party)
			job.status = "interrupted";job.reason = str(built.get("message", "Actual warehouse setup is currently unavailable."))
			continue
		# Publish the same canonical new-business defaults used by ordinary restore.
		Home.ensure(c.state)
		# This fresh quote and establish run without a time step or price change.
		# Home just paid materialCost + margin into port.cash, so that receipt
		# funds this exact credit; labor, margin, duty and working capital remain.
		var credit: int = int(quote.materialCost)
		Money.move(p, "cash", c.state, "coins", credit, "076 supplied construction materials credit", c.state.moneyLog)
		job.reservedMaterials = {}
		job.setupBill = {"grossCost": int(built.cost), "materialCredit": credit,
			"netCost": int(built.cost) - credit, "homeQuote": quote.duplicate(true)}
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
	if not _control_near(c, str(job.portId), RANGE) or physical.get("result") != result or physical.has("startError"):return
	if not _home(c.state, str(job.portId)):
		var world: Dictionary = physical.get("world064", {})
		if world.get("layer") != "local" or world.get("regionId") != _port(c.state, str(job.portId)).get("regionId"):return
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
	if not _home(c.state, str(job.portId)):
		job.battleWorld085 = physical.world064.duplicate(true)
		job.battleSeconds085 = float(physical.time)
	if not job.battleWon:
		_release(c, job)
		job.status = "interrupted";job.reason = "The actual coastal contest was lost or abandoned. Support remains spent; resume only with real surviving sailors."
	else:
		job.reason = "The selected defender lost the actual coastal contest. Finish funded local support, then negotiate explicitly."

static func negotiate(c) -> Dictionary:
	var job: Dictionary = _book(c.state).get("control", {})
	if job.get("status") == "complete":return _result(true, "The existing negotiated transfer is already recorded.", {"changed": false})
	if job.get("status") != "active":return _result(false, "Resume the funded harbor operation before negotiating surrender.")
	if not _control_near(c, str(job.portId)) or not _crew_ok(c.state, job):return _result(false, "The actual support party must be present at the harbor berth.")
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
	if not _home(c.state, str(job.portId)):job.completedDay085 = float(c.state.day)
	_release(c, job)
	c.log_entry(str(job.reason))
	return _result(true, str(job.reason), {"changed": true, "portId": str(job.portId), "fromFaction": str(job.fromFaction), "newFaction": str(job.newFaction)})

static func _validate_improvement_record(saved: Dictionary, j: Dictionary, improve_ports: Dictionary, allow_prior: bool) -> String:
	if j.get("status") not in STATUSES or not improve_ports.has(j.get("portId")):return "Invalid territorial harbor or status."
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
	if not BoardingRules._w(j.get("paidDays"), WORK_DAYS) or int(j.paidDays) > int(j.lastPaidDay) - int(j.startedDay):return "Invalid paid territorial work days."
	if not j.get("businessId") is String or not j.get("machineryId") is String:return "Invalid territorial asset identity."
	if j.get("materials") != Home.KINDS.warehouse.materials:return "Invalid territorial material contribution."
	if not j.get("reservedMaterials") is Dictionary or not j.get("setupBill") is Dictionary:return "Missing territorial project inventory or setup receipt; spent old goods cannot be recreated."
	if j.status != "complete" and (j.reservedMaterials != j.materials or not j.setupBill.is_empty()):return "Unfinished territorial work must retain its exact reserved bill and no completion credit."
	var found: bool = false
	for item in saved.get("tooling", {}).get("items", []):
		if item.get("id") == j.machineryId and item.get("kind") == "machine_tools":found = true
	if not found:return "Missing original territorial machinery record."
	if j.status == "complete":
		var bill: Dictionary = j.setupBill
		if not j.reservedMaterials.is_empty() or bill.size() != 4 or not bill.get("homeQuote") is Dictionary:return "Completed territorial work retains materials or lacks its actual setup receipt."
		for field in ["grossCost", "materialCredit", "netCost"]:
			if not BoardingRules._w(bill.get(field), BoardingRules.CASH):return "Invalid territorial supplied-material credit."
		var quote: Dictionary = bill.homeQuote
		if quote.get("ok") != true or quote.get("kind") != "warehouse" or quote.get("portId") != j.portId or quote.get("materials") != j.materials:return "Territorial setup receipt does not match its project."
		if quote.get("cost") != bill.grossCost or quote.get("materialCost") != bill.materialCredit or bill.materialCredit > bill.grossCost or bill.netCost != bill.grossCost - bill.materialCredit:return "Territorial gross bill and supplied-material credit do not reconcile."
		var b: Dictionary = Home.business_view(saved, str(j.businessId))
		if int(j.paidDays) != WORK_DAYS or b.get("kind") != "warehouse" or b.get("homePort") != j.portId:return "Completed territorial berth lacks its actual paid warehouse."
	elif j.businessId != "":return "Unfinished territorial berth claims a business."
	if j.has("priorCompleted"):
		if not allow_prior or not j.get("priorCompleted") is Dictionary or j.priorCompleted.is_empty():return "Invalid prior territorial improvement record."
		var prior: Dictionary = j.priorCompleted
		if prior.get("status") != "complete":return "Archived prior territorial improvement must be complete."
		if _home(saved, str(prior.get("portId", ""))) == _home(saved, str(j.get("portId", ""))):return "Prior territorial improvement must be in a distinct harbor tier."
		if not str(j.get("businessId", "")).is_empty() and str(prior.get("businessId", "")) == str(j.get("businessId", "")):return "Duplicate territorial warehouse business identity."
		var prior_err: String = _validate_improvement_record(saved, prior, improve_ports, false)
		if not prior_err.is_empty():return prior_err
	return ""

static func _validate_control_record(saved: Dictionary, j: Dictionary, ports: Dictionary, allow_prior: bool) -> String:
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
	if not BoardingRules._w(j.get("supportDays"), WORK_DAYS) or int(j.supportDays) > int(j.lastPaidDay) - int(j.startedDay):return "Invalid paid territorial work days."

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
	if not _home(saved, str(j.portId)):
		if not j.get("corridor085") is Dictionary or not _corridor_valid085(saved, j.corridor085, str(j.portId)):return "Remote control lacks its original two-group merchant corridor."
		if j.get("defenderId") != j.corridor085.get("ownerId"):return "Remote control defender is not the actual corridor owner."
		for uid in j.defenderUids:
			if not _defender_uid085(saved, j, str(uid)):return "Remote defender UID has no original owner, matching physical wreck or held prize."
		if int(j.battleSeq) > 0:
			if not j.get("battleWorld085") is Dictionary or j.battleWorld085.get("schema") != 1 or j.battleWorld085.get("layer") != "local" or j.battleWorld085.get("regionId") != ports[j.portId].regionId:return "Remote contest belongs to another chart."
			if not BoardingRules._n(j.get("battleSeconds085")) or float(j.battleSeconds085) <= 0:return "Remote contest lacks actual elapsed battle time."
		if j.status == "complete":
			if not BoardingRules._n(j.get("completedDay085")) or float(j.completedDay085) < float(j.lastPaidDay) or float(j.completedDay085) > float(saved.day):return "Invalid dated remote surrender receipt."
	if j.has("priorCompleted"):
		if not allow_prior or _home(saved, str(j.portId)) or not j.priorCompleted is Dictionary:return "Invalid retained prior control receipt."
		var prior: Dictionary = j.priorCompleted
		if prior.get("status") != "complete" or not _home(saved, str(prior.get("portId", ""))):return "Only one completed HOME control receipt may precede the remote operation."
		var error: String = _validate_control_record(saved, prior, ports, false)
		if not error.is_empty():return error
	return ""

static func validate(saved: Dictionary, world: Dictionary) -> String:
	if not saved.has("territorial076"):return _ownership_error(saved, world, {})
	var book: Variant = saved.territorial076
	if not book is Dictionary or book.keys().size() != 3 or not BoardingRules._w(book.get("schema"), 1) or book.get("schema") != 1:return "Invalid territorial076 book."
	if not BoardingRules._w(saved.get("econDay"), BoardingRules.CASH):return "Territorial work requires published economic days."
	var ports: Dictionary = {}
	for p in world.get("PORTS", []):ports[str(p.id)] = p
	var improve_ports: Dictionary = ports.duplicate()
	for h in saved.get("sector069", {}).get("harbors", []) if saved.get("sector069") is Dictionary and saved.get("sector069", {}).get("harbors") is Array else []:
		if h is Dictionary and _generated_improve_port(saved, str(h.get("id", ""))):
			improve_ports[str(h.id)] = h
	for key in ["improvement", "control"]:
		var raw: Variant = book.get(key)
		if not raw is Dictionary:return "Invalid territorial operation."
		if raw.is_empty():continue
		var j: Dictionary = raw
		if key == "improvement":
			var imp_err: String = _validate_improvement_record(saved, j, improve_ports, true)
			if not imp_err.is_empty():return imp_err
		else:
			var control_err: String = _validate_control_record(saved, j, improve_ports, true)
			if not control_err.is_empty():return control_err
	return _ownership_error(saved, world, book.control)

static func _ownership_error(saved: Dictionary, world: Dictionary, control: Dictionary) -> String:
	# Removing the book cannot turn an unexplained change into a legacy save.
	for definition in world.get("PORTS", []):
		var actual: Dictionary = _port(saved, str(definition.id))
		if actual.is_empty():continue # Existing campaign validation owns missing ports.
		var expected: String = str(definition.faction)
		for receipt in [control, control.get("priorCompleted", {})]:
			if receipt.get("portId") == definition.id and receipt.get("status") == "complete":expected = str(receipt.newFaction)
		if actual.get("faction") != expected:return "Harbor sovereign change has no completed territorial operation."
	for h in saved.get("sector069", {}).get("harbors", []) if saved.get("sector069") is Dictionary and saved.get("sector069", {}).get("harbors") is Array else []:
		if not h is Dictionary:continue
		var actual_gen: Dictionary = _port(saved, str(h.get("id", "")))
		if actual_gen.is_empty():continue
		var expected: String = str(h.get("faction", ""))
		if control.get("portId") == h.get("id") and control.get("status") == "complete":expected = str(control.newFaction)
		if str(actual_gen.get("faction", "")) != expected:return "Remote harbor sovereign change has no completed supplied control operation."
	return ""
