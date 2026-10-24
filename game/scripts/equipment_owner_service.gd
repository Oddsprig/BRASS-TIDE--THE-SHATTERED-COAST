extends RefCounted
## v0.031 paid harbor equipment restoration for canonical NPC and player-company fleets,
## plus canonical installed-weapon availability for offscreen naval combat power.

const Core = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")
const EquipmentService = preload("res://scripts/equipment_service.gd")
const Refit = preload("res://scripts/refit.gd")
const MountLayout = preload("res://scripts/mount_layout.gd")
const Construction = preload("res://scripts/construction.gd")
const Damage = preload("res://scripts/damage.gd")
const Money = preload("res://scripts/money.gd")
const Factions = preload("res://scripts/factions.gd")
const TradeRules = preload("res://scripts/trade_rules.gd")
const CompanyOps = preload("res://scripts/company_ops.gd")

const EPS: float = EquipmentService.EPS
const MAX_COINS: int = EquipmentService.MAX_COINS
const MOUNT_LOCATIONS: Array = ["mount0", "mount1", "mount2", "mount3"]


class DetachedCoreContext extends RefCounted:
	var state: Dictionary = {}
	var data: Dictionary = {}
	var shipping = null
	var CompanyOps = null
	var _hull_provider = null

	func _init(state_ref: Dictionary, data_ref: Dictionary, hull_provider = null) -> void:
		state = state_ref
		data = data_ref
		_hull_provider = hull_provider

	func hull(hull_id: String) -> Dictionary:
		var clean_id: String = hull_id.strip_edges()
		if clean_id.is_empty():
			return {}
		if data.get("HULLS") is Array:
			for h in data.HULLS:
				if h is Dictionary and str(h.get("id", "")) == clean_id:
					return h
		if _hull_provider != null and not (_hull_provider is Dictionary) and _hull_provider.has_method("hull"):
			var provided = _hull_provider.hull(clean_id)
			if provided is Dictionary:
				return provided
		return {}

	func port(port_id: String) -> Dictionary:
		var clean_id: String = port_id.strip_edges()
		if clean_id.is_empty() or not (state.get("ports") is Array):
			return {}
		for p in state.ports:
			if p is Dictionary and str(p.get("id", "")) == clean_id:
				return p
		return {}

	func fitted_spec(boat: Dictionary) -> Dictionary:
		var base: Dictionary = hull(str(boat.get("type", ""))).duplicate(true)
		if base.is_empty():
			return boat.get("spec", {}) if boat.get("spec") is Dictionary else {}
		var loadout = boat.get("loadout")
		if not (loadout is Dictionary):
			loadout = Refit.defaults(base)
		return Refit.effective_spec(base, loadout)


static func _fail(message: String, deferred: bool = false) -> Dictionary:
	return {
		"ok": false,
		"deferred": deferred,
		"error": message,
		"message": message,
		"cost": 0,
		"restoredIds": [],
		"changes": []
	}


static func _finite_number(value, fallback: float = 0.0) -> float:
	if (value is float or value is int) and not (value is bool) and is_finite(float(value)):
		return float(value)
	return fallback


static func is_canonical_or_foreign_boat(boat) -> bool:
	if not (boat is Dictionary):
		return false
	return boat.has("moduleCondition") or Core._foreign(boat)


static func is_foreign_owner(owner) -> bool:
	if not (owner is Dictionary):
		return false
	return Core._foreign(owner)


static func has_canonical_or_foreign_boat(owner) -> bool:
	if not (owner is Dictionary) or not (owner.get("boats") is Array):
		return false
	for b_var in owner.boats:
		if is_canonical_or_foreign_boat(b_var):
			return true
	return false


static func _resolve_core_context(core) -> Dictionary:
	if core == null:
		return _fail("Campaign core context is unavailable; canonical repair deferred safely.", true)
	if core is Dictionary:
		var d: Dictionary = core
		var st_dict = d.get("state")
		var dt_dict = d.get("data", d.get("world"))
		if not (st_dict is Dictionary) or st_dict.is_empty():
			return _fail("Campaign state dictionary is unavailable; canonical repair deferred safely.", true)
		if not (dt_dict is Dictionary) or not (dt_dict.get("HULLS") is Array):
			return _fail("World hull catalog is unavailable; canonical repair deferred safely.", true)
		var view := DetachedCoreContext.new(st_dict, dt_dict)
		return {"ok": true, "coreView": view, "state": st_dict, "data": dt_dict}
	if not ("state" in core) or not (core.state is Dictionary) or core.state.is_empty():
		return _fail("Campaign state is unavailable; canonical repair deferred safely.", true)
	var has_hull_method: bool = core.has_method("hull")
	var has_data_hulls: bool = ("data" in core) and (core.data is Dictionary) and (core.data.get("HULLS") is Array)
	if not has_hull_method and not has_data_hulls:
		return _fail("Campaign hull catalog is unavailable; canonical repair deferred safely.", true)
	var data_ref: Dictionary = core.data if (("data" in core) and (core.data is Dictionary)) else {}
	var core_view = core if has_hull_method else DetachedCoreContext.new(core.state, data_ref, core)
	return {"ok": true, "coreView": core_view, "state": core.state, "data": data_ref}


static func _allowed_trade(owner: Dictionary, port: Dictionary, good: String, state: Dictionary) -> bool:
	var bans: Array = owner.get("tradeBans", port.get("tradeBans", [])) if state.is_empty() else state.get("tradeLaw", {}).get("bans", [])
	var day_raw = owner.get("tradeLawDay", port.get("tradeLawDay", 0.0)) if state.is_empty() else state.get("day", 1.0)
	if not EquipmentService._is_finite_number(day_raw):
		return false
	return TradeRules.allowed(bans if bans is Array else [], str(owner.get("faction", "")), str(port.get("faction", "")), good, float(day_raw))


static func allowed_port_service(owner: Dictionary, port: Dictionary, core = null) -> Dictionary:
	if not (owner is Dictionary) or owner.is_empty():
		return _fail("Fleet owner must be a non-empty dictionary.")
	if not (port is Dictionary) or port.is_empty():
		return _fail("Harbor port must be a non-empty dictionary.")
	if not (owner.get("faction") is String) or not (port.get("faction") is String):
		return _fail("Fleet owner and harbor require string faction identifiers.")
	var owner_faction: String = str(owner.get("faction", "")).strip_edges()
	var port_faction: String = str(port.get("faction", "")).strip_edges()
	if owner_faction.is_empty() or port_faction.is_empty():
		return _fail("Fleet owner and harbor require non-empty faction identifiers.")
	var state: Dictionary = {}
	if core is Dictionary:
		if core.get("state") is Dictionary:
			state = core.state
		else:
			state = core
	elif core != null and ("state" in core) and (core.state is Dictionary):
		state = core.state
	if owner_faction != port_faction:
		if state.get("relationships") is Dictionary:
			if Factions.relation(state, owner_faction, port_faction) <= Factions.ENEMY_AT:
				return _fail("Harbor authorities refuse drydock service to hostile faction %s." % owner_faction)
		else:
			if (owner_faction == "raiders") != (port_faction == "raiders"):
				return _fail("Harbor authorities refuse drydock service to hostile faction %s." % owner_faction)
	return {
		"ok": true,
		"ownerFaction": owner_faction,
		"portFaction": port_faction
	}


static func _validate_money_log(state: Dictionary) -> String:
	return EquipmentService.journal_error(state)


static func _validate_owner_dock_and_hull(state: Dictionary, owner: Dictionary, port: Dictionary, boat: Dictionary) -> Dictionary:
	if not (owner is Dictionary) or owner.is_empty():
		return _fail("Fleet owner must be a non-empty dictionary.")
	if not (port is Dictionary) or port.is_empty() or not (port.get("stocks") is Dictionary):
		return _fail("Harbor service requires a valid port with commercial stocks.")
	if not (boat is Dictionary) or boat.is_empty():
		return _fail("Boat must be a non-empty dictionary.")
	if Core._foreign(owner):
		return _fail("Fleet owner carries unrecognized foreign condition metadata.")
	if Core._foreign(boat):
		return _fail("Unrecognized condition metadata was left untouched.")
	if not boat.has("moduleCondition"):
		return _fail("Legacy boat has no canonical moduleCondition; NPC hulls are not auto-seeded.")
	if not (boat.get("moduleCondition") is Dictionary):
		return _fail("Existing equipment condition is corrupt and was left untouched.")
	if bool(boat.get("sunk", false)):
		return _fail("A sunk boat cannot be serviced.")
	if boat.has("mothballed") and (not (boat.get("mothballed") is bool) or bool(boat.get("mothballed", false))):
		return _fail("A mothballed boat cannot be serviced.")
	if not (owner.get("id") is String) or str(owner.get("id", "")).strip_edges().is_empty():
		return _fail("Fleet owner requires a valid string id.")
	var owner_id: String = str(owner.get("id", "")).strip_edges()
	if not (owner.get("active") is bool) or not bool(owner.get("active", false)):
		return _fail("Inactive fleet owner cannot perform harbor service.")
	if not EquipmentService._is_whole_coin(owner.get("coins")):
		return _fail("Fleet owner coin balance is not a valid finite integer.")
	if not EquipmentService._is_whole_coin(owner.get("crewPurse")):
		return _fail("Fleet owner crewPurse balance is not a valid finite integer.")
	if owner.has("wageArrears") and not EquipmentService._is_whole_coin(owner.get("wageArrears")):
		return _fail("Fleet owner wageArrears is not a valid finite integer.")

	if not (state.get("fleetOwners") is Array):
		return _fail("Campaign fleetOwners must be an array.")
	var found_same_owner: bool = false
	for candidate in state.fleetOwners:
		if not (candidate is Dictionary):
			return _fail("Campaign fleetOwners contains a non-dictionary entry.")
		if is_same(candidate, owner):
			found_same_owner = true
		elif str(candidate.get("id", "")).strip_edges() == owner_id:
			return _fail("Fleet owner dictionary does not match the registered campaign fleetOwner.")
	if not found_same_owner:
		return _fail("Fleet owner is not registered in campaign fleetOwners.")

	if not (owner.get("boats") is Array):
		return _fail("Fleet owner boats must be an array.")
	if not EquipmentService._has_same_dict(owner.boats, boat):
		return _fail("Fleet owner does not own that physical hull.")

	if not (port.get("id") is String) or str(port.get("id", "")).strip_edges().is_empty():
		return _fail("Harbor port requires a valid string id.")
	var port_id: String = str(port.get("id", "")).strip_edges()
	if not (state.get("ports") is Array):
		return _fail("Campaign ports must be an array.")
	if not EquipmentService._has_same_dict(state.ports, port):
		return _fail("Harbor port is not a live port in campaign state.")

	if not (owner.get("atPort") is String) or str(owner.get("atPort", "")).strip_edges() != port_id:
		return _fail("Fleet owner is not docked at %s." % str(port.get("name", port_id)))

	if state.get("patrols") is Array:
		for p_var in state.patrols:
			if not (p_var is Dictionary):
				continue
			var pat: Dictionary = p_var
			if str(pat.get("id", "")).strip_edges() == owner_id:
				if pat.has("holding") and not (pat.get("holding") is bool):
					return _fail("Fleet patrol holding state is invalid.")

	if boat.has("storedPort") and not (boat.get("storedPort") is String):
		return _fail("Boat storedPort field is invalid.")
	var stored_port: String = str(boat.get("storedPort", "")).strip_edges()
	if not stored_port.is_empty() and stored_port != port_id:
		return _fail("%s is laid up at %s." % [str(boat.get("name", "Boat")), stored_port])

	return {"ok": true, "ownerId": owner_id, "portId": port_id}


static func _validate_company_book(state: Dictionary, owner: Dictionary, owner_id: String, cost: int) -> String:
	if not owner.has("playerCompany"):
		return ""
	if not (owner.get("playerCompany") is bool):
		return "Fleet owner playerCompany field must be a boolean."
	if not bool(owner.get("playerCompany", false)):
		return ""
	if not (state.get("shippingCompanies") is Dictionary) or not state.shippingCompanies.has(owner_id):
		return "Company fleet owner has no registered shipping company book."
	var book = state.shippingCompanies.get(owner_id)
	if not (book is Dictionary) or book.is_empty():
		return "Company accounting book is invalid."
	if not (book.get("ownerId") is String) or str(book.get("ownerId", "")) != owner_id:
		return "Company book ownerId does not match fleet owner."
	if not (book.get("status") is String) or not (str(book.get("status", "")) in ["active", "waiting", "returning", "ready"]):
		return "Collected or invalid shipping company cannot incur repair expenses."
	if not (book.get("log") is Array):
		return "Company accounting log must be an array."
	for entry in book.log:
		if not (entry is Dictionary):
			return "Company accounting log contains a non-dictionary entry."
	if not EquipmentService._is_finite_number(state.get("day")) or float(state.get("day", -1.0)) < 0.0:
		return "Campaign day must be a finite nonnegative number for company accounting."
	if not EquipmentService._is_finite_number(book.get("basisQty")) or float(book.get("basisQty", -1.0)) < 0.0:
		return "Company book basisQty is not a valid finite nonnegative number."
	for acct_key in ["invested", "withdrawn", "revenue", "cogs", "operating", "basisCost", "returnedBasis"]:
		if not EquipmentService._is_whole_coin(book.get(acct_key)):
			return "Company book %s is not a valid finite integer." % acct_key
	if int(book.get("operating", 0)) > MAX_COINS - cost:
		return "Company operating expense would overflow maximum coin supply."
	var expected_net: int = int(book.get("revenue", 0)) - int(book.get("cogs", 0)) - int(book.get("operating", 0))
	if not EquipmentService._is_finite_number(book.get("netProfit")) or int(book.get("netProfit", 0)) != expected_net:
		return "Company netProfit is out of balance before repair."
	return ""


static func _needs_restoration(boat: Dictionary, q: Dictionary) -> bool:
	if int(q.get("equipmentCount", 0)) > 0:
		return true
	if float(q.get("hullKits", 0.0)) > EPS or float(q.get("hullOrdinaryDays", 0.0)) > EPS or float(q.get("hullExpertDays", 0.0)) > EPS:
		return true
	if _finite_number(boat.get("hp"), 0.0) < _finite_number(boat.get("maxHp"), 0.0) - EPS:
		return true
	if Damage.sum_areas(boat) > EPS:
		return true
	if _finite_number(boat.get("water"), 0.0) > EPS or _finite_number(boat.get("fire"), 0.0) > EPS or _finite_number(boat.get("wounded"), 0.0) > EPS:
		return true
	if bool(boat.get("needsHarborRepair", false)) or bool(boat.get("captureSecured", false)):
		return true
	return false


static func owner_service_quote(owner: Dictionary, port: Dictionary, boat: Dictionary, core = null) -> Dictionary:
	var ctx: Dictionary = _resolve_core_context(core)
	if not ctx.get("ok", false):
		var fail_q: Dictionary = EquipmentService._fail_quote(str(ctx.get("error", "Campaign context is unavailable.")))
		fail_q["deferred"] = bool(ctx.get("deferred", false))
		return fail_q
	var state: Dictionary = ctx.state
	var core_view = ctx.coreView

	var valid: Dictionary = _validate_owner_dock_and_hull(state, owner, port, boat)
	if not valid.get("ok", false):
		return EquipmentService._fail_quote(str(valid.get("error", "Owner or hull validation failed.")))

	var access: Dictionary = allowed_port_service(owner, port, core_view)
	if not access.get("ok", false):
		return EquipmentService._fail_quote(str(access.get("error", "Harbor authorities refused service.")))

	var inspected: Dictionary = EquipmentService.inspect_service_owner(core_view, boat)
	if not inspected.get("ok", false) or not bool(inspected.get("hadCanonical", false)):
		return EquipmentService._fail_quote(str(inspected.get("error", "Canonical equipment condition is invalid.")))

	return EquipmentService.service_quote(core_view, boat, port)


static func repair_owner_boat(owner: Dictionary, port: Dictionary, boat: Dictionary, core = null) -> Dictionary:
	if not (owner is Dictionary) or owner.is_empty():
		return _fail("Fleet owner must be a non-empty dictionary.")
	if Core._foreign(owner):
		return _fail("Fleet owner carries unrecognized foreign condition metadata.")
	if not (boat is Dictionary) or boat.is_empty():
		return _fail("Boat must be a non-empty dictionary.")
	if Core._foreign(boat):
		return _fail("Unrecognized condition metadata was left untouched.")
	if not boat.has("moduleCondition"):
		return _fail("Legacy boat has no canonical moduleCondition; NPC hulls are not auto-seeded.")
	if not (boat.get("moduleCondition") is Dictionary):
		return _fail("Existing equipment condition is corrupt and was left untouched.")

	var ctx: Dictionary = _resolve_core_context(core)
	if not ctx.get("ok", false):
		return ctx
	var state: Dictionary = ctx.state
	var core_view = ctx.coreView

	var valid: Dictionary = _validate_owner_dock_and_hull(state, owner, port, boat)
	if not valid.get("ok", false):
		return valid
	var owner_id: String = str(valid.get("ownerId", ""))

	var mlog_err: String = _validate_money_log(state)
	if not mlog_err.is_empty():
		return _fail(mlog_err)

	var access: Dictionary = allowed_port_service(owner, port, core_view)
	if not access.get("ok", false):
		return access

	var inspected: Dictionary = EquipmentService.inspect_service_owner(core_view, boat)
	if not inspected.get("ok", false) or not bool(inspected.get("hadCanonical", false)):
		return _fail(str(inspected.get("error", "Equipment condition is invalid and cannot be serviced.")))

	var q: Dictionary = EquipmentService.service_quote(core_view, boat, port)
	if not q.get("ok", false):
		return _fail(str(q.get("error", "Harbor could not prepare a valid service quote.")))

	if not _needs_restoration(inspected.probe, q):
		return {
			"ok": true,
			"changed": false,
			"deferred": false,
			"cost": 0,
			"restoredIds": [],
			"changes": [],
			"quote": q,
			"message": "No hull or installed equipment restoration needed."
		}

	if float(q.get("purchase", 0.0)) > EPS and not _allowed_trade(owner, port, "supplies", state):
		return _fail("Harbor trade embargo forbids purchasing repair supplies.", true)
	var eq_mats: Dictionary = q.get("equipmentMaterials", {})
	for good in EquipmentService.SERVICE_GOODS:
		if eq_mats.has(good) and float(eq_mats[good]) > EPS:
			if not _allowed_trade(owner, port, good, state):
				return _fail("Harbor trade embargo forbids purchasing %s." % good, true)

	var wf: Dictionary = EquipmentService.workforce_status(port)
	if not wf.get("ok", false):
		return _fail(str(wf.get("error", "Harbor workforce records are invalid.")))
	var total_work: float = float(q.get("workerDays", 0.0))
	var ordinary_work: float = float(q.get("ordinaryDays", 0.0))
	var expert_work: float = float(q.get("expertDays", 0.0))
	var workers_total: float = float(wf.get("total", 0.0))
	var experts_total: float = float(wf.get("specialists", 0.0))
	if (total_work > EPS and int(floor(workers_total + EPS)) < 1) or float(wf.get("free", 0.0)) + EPS < total_work:
		return _fail("This harbor doesn't have enough available shipwrights for drydock today.", true)
	if (expert_work > EPS and int(floor(experts_total + EPS)) < 1) or float(wf.get("freeExperts", 0.0)) + EPS < expert_work:
		return _fail("This harbor lacks available mechanics and engineering specialists today.", true)

	var raw_supplies = port.stocks.get("supplies", -1.0)
	if not EquipmentService._is_finite_number(raw_supplies) or float(raw_supplies) < 0.0:
		return _fail("Harbor repair kit stock is invalid.")
	if float(raw_supplies) + EPS < float(q.get("purchase", 0.0)):
		return _fail("This harbor doesn't have enough repair kits in stock.", true)

	for good in EquipmentService.SERVICE_GOODS:
		if not eq_mats.has(good):
			continue
		var need: float = float(eq_mats[good])
		var have_raw = port.stocks.get(good, -1.0)
		if not EquipmentService._is_finite_number(have_raw) or float(have_raw) < 0.0:
			return _fail("Harbor %s stock is invalid." % good)
		if float(have_raw) + EPS < need:
			return _fail("This harbor lacks enough %s in stock to restore damaged equipment." % good, true)

	var ledger_err: String = EquipmentService._validate_ledger_and_overflow(state, port, q)
	if not ledger_err.is_empty():
		return _fail(ledger_err)

	var cost: int = int(q.get("cost", 0))
	if int(owner.get("coins", 0)) < cost:
		return _fail("Fleet owner does not have enough coins for drydock restoration.", true)

	var company_err: String = _validate_company_book(state, owner, owner_id, cost)
	if not company_err.is_empty():
		return _fail(company_err)

	# Stage all hull, equipment, purse, stock, workforce, ledger, and company accounting changes on detached copies.
	var staged_boat: Dictionary = inspected.probe
	var restore_res: Dictionary = Core.restore_installed_paid(staged_boat.moduleCondition, {"confirmPaid": true})
	if not restore_res.get("ok", false):
		return _fail(str(restore_res.get("error", "Failed to restore installed equipment records.")))

	staged_boat["supplies"] = maxf(0.0, float(staged_boat.get("supplies", 0.0)) - float(q.get("own", 0.0)))
	staged_boat["hp"] = float(staged_boat.get("maxHp", staged_boat.get("hp", 0.0)))
	staged_boat["breaches"] = []
	staged_boat["water"] = 0.0
	staged_boat["fire"] = 0.0
	staged_boat["wounded"] = 0.0
	if bool(staged_boat.get("captureSecured", false)):
		staged_boat["supportOnly"] = false
		staged_boat["captureSecured"] = false
	if staged_boat.has("needsHarborRepair"):
		staged_boat["needsHarborRepair"] = false
	if staged_boat.has("towed"):
		staged_boat["towed"] = false
	if staged_boat.has("towSpeedFactor"):
		staged_boat["towSpeedFactor"] = 1.0

	# Project canonical condition after paid restoration without re-running absorb_legacy_damage.
	var pub_res: Dictionary = Records.publish(staged_boat)
	if not pub_res.get("ok", false):
		return _fail(str(pub_res.get("error", "Failed to publish restored equipment state.")))
	var post_snap: Dictionary = Records.snapshot(staged_boat)
	if not post_snap.get("ok", false):
		return _fail(str(post_snap.get("error", "Restored equipment state failed post-service validation.")))

	var dock: Dictionary = port.duplicate(true)
	var staged_owner: Dictionary = owner.duplicate(true)
	var staged_log: Array = state.moneyLog.duplicate(true)

	var before_pair_coins: int = int(staged_owner.coins) + int(staged_owner.crewPurse) + Money.port_total(dock)
	if not Money.move(staged_owner, "coins", dock, "cash", int(q.get("materials", 0)) + int(q.get("fee", 0)), "Repair materials and yard fee", staged_log):
		return _fail("Drydock material and fee transfer failed.")
	if not Money.move(staged_owner, "coins", dock, "householdPurse", int(q.get("ordinary", 0)), "Drydock shipwright wages", staged_log):
		return _fail("Shipwright wage transfer failed.")
	if not Money.move(staged_owner, "coins", dock, "expertPurse", int(q.get("expert", 0)), "Mechanics and treatment specialists", staged_log):
		return _fail("Specialist wage transfer failed.")
	if int(staged_owner.coins) + int(staged_owner.crewPurse) + Money.port_total(dock) != before_pair_coins:
		return _fail("Drydock coin conservation check failed.")

	dock.stocks["supplies"] = maxf(0.0, float(dock.stocks.get("supplies", 0.0)) - float(q.get("purchase", 0.0)))
	for good in EquipmentService.SERVICE_GOODS:
		if not eq_mats.has(good):
			continue
		dock.stocks[good] = maxf(0.0, float(dock.stocks.get(good, 0.0)) - float(eq_mats[good]))

	dock["_yardWorkersUsed"] = float(wf.get("used", 0.0))
	dock["_yardSpecialistsUsed"] = float(wf.get("expertsUsed", 0.0))
	var ord_used_a: float = float(port.get("_yardOrdinaryUsed", 0.0)) if EquipmentService._is_finite_number(port.get("_yardOrdinaryUsed")) else 0.0
	var ord_used_b: float = float(port.get("yardOrdinaryReserved", 0.0)) if EquipmentService._is_finite_number(port.get("yardOrdinaryReserved")) else 0.0
	dock["_yardOrdinaryUsed"] = maxf(ord_used_a, ord_used_b)
	Construction._record_yard_reservation(dock, workers_total, experts_total, total_work, ordinary_work, expert_work)

	var staged_ports: Array = []
	for p_entry in state.ports:
		staged_ports.append(dock if is_same(p_entry, port) else p_entry)
	var staged_owners: Array = []
	for o_entry in state.fleetOwners:
		staged_owners.append(staged_owner if is_same(o_entry, owner) else o_entry)
	var staged_state: Dictionary = state.duplicate(false)
	staged_state["ports"] = staged_ports
	staged_state["fleetOwners"] = staged_owners
	staged_state["moneyLog"] = staged_log
	if state.has("coinSupply"):
		if Money.total(staged_state) != int(state.get("coinSupply", 0)):
			return _fail("World coin supply conservation check failed.")

	var is_company: bool = bool(owner.get("playerCompany", false))
	var live_book: Dictionary = {}
	var staged_book: Dictionary = {}
	if is_company:
		live_book = state.shippingCompanies[owner_id]
		staged_book = live_book.duplicate(true)
		if cost > 0:
			var op_before: int = int(staged_book.get("operating", 0))
			var inv_before: int = int(staged_book.get("invested", 0))
			var rev_before: int = int(staged_book.get("revenue", 0))
			var cogs_before: int = int(staged_book.get("cogs", 0))
			var log_before_len: int = staged_book.log.size()
			var staged_companies: Dictionary = state.shippingCompanies.duplicate(false)
			staged_companies[owner_id] = staged_book
			staged_state["shippingCompanies"] = staged_companies
			var staged_company_ctx := DetachedCoreContext.new(staged_state, ctx.data, core)
			if not (core is Dictionary) and core != null and ("CompanyOps" in core) and core.CompanyOps != null:
				core.CompanyOps.record(staged_company_ctx, staged_owner, "repairs", cost)
			else:
				CompanyOps.record(staged_company_ctx, staged_owner, "repairs", cost)
			var expected_op: int = op_before + cost
			var expected_net: int = rev_before - cogs_before - expected_op
			var expected_log_len: int = mini(32, log_before_len + 1)
			if int(staged_book.get("invested", -1)) != inv_before:
				return _fail("Company repair staging altered invested capital.")
			if int(staged_book.get("operating", -1)) != expected_op:
				return _fail("Company repair expense was not recorded in operating account.")
			if int(staged_book.get("netProfit", 0)) != expected_net:
				return _fail("Company netProfit did not reconcile after staged repair expense.")
			if not (staged_book.get("log") is Array) or staged_book.log.size() != expected_log_len or staged_book.log.is_empty():
				return _fail("Company repair expense log receipt was not recorded.")
			var receipt = staged_book.log[-1]
			if not (receipt is Dictionary) or str(receipt.get("event", "")) != "repairs" or int(receipt.get("coins", -1)) != cost:
				return _fail("Company repair expense log receipt is invalid.")

	# Publish staged changes in place while preserving live Dictionary and Array references.
	var live_stocks: Dictionary = port.stocks
	for stock_key in dock.stocks.keys():
		live_stocks[stock_key] = dock.stocks[stock_key]
	for dock_key in dock.keys():
		if dock_key == "stocks":
			continue
		port[dock_key] = dock[dock_key]

	var boat_commit_keys: Array = [
		"supplies", "hp", "breaches", "water", "fire", "wounded", "engine",
		"captureSecured", "supportOnly", "needsHarborRepair", "towed", "towSpeedFactor",
		"loadout", "moduleCondition", "refitLocker"
	]
	for boat_key in boat_commit_keys:
		if staged_boat.has(boat_key):
			boat[boat_key] = staged_boat[boat_key]

	owner["coins"] = int(staged_owner.coins)
	state.moneyLog.clear()
	state.moneyLog.append_array(staged_log)

	if is_company and cost > 0:
		live_book["operating"] = int(staged_book.operating)
		live_book["netProfit"] = int(staged_book.netProfit)
		live_book.log.clear()
		live_book.log.append_array(staged_book.log)
		if not (core is Dictionary) and core != null and ("shipping" in core) and core.shipping == null:
			CompanyOps.api(core)

	var restored_ids: Array = []
	var change_list: Array = restore_res.get("changes", [])
	for ch in change_list:
		if ch is Dictionary and ch.has("itemUid"):
			restored_ids.append(str(ch.itemUid))

	var boat_label: String = str(boat.get("name", boat.get("uid", "Hull")))
	return {
		"ok": true,
		"changed": true,
		"deferred": false,
		"cost": cost,
		"changes": change_list,
		"restoredIds": restored_ids,
		"quote": q,
		"message": "%s repaired for %d coins paid from %s purse." % [boat_label, cost, str(owner.get("name", owner_id))]
	}


static func boat_weapon_power(boat: Dictionary, perf_factor: float = 1.0) -> Dictionary:
	var clean_perf: float = clampf(_finite_number(perf_factor, 0.0), 0.0, 1.0)
	if not (boat is Dictionary) or boat.is_empty() or bool(boat.get("sunk", false)):
		return {
			"ok": true,
			"mode": "sunk",
			"firepower": 0.0,
			"rawOutput": 0.0,
			"healthyOutput": 0.0,
			"availabilityFactor": 0.0,
			"crewWeaponFactor": 0.0,
			"performanceFactor": clean_perf,
			"activeMounts": [],
			"mountCount": 0
		}

	var st: Dictionary = Damage.get_status(boat)
	var eq_ok: bool = bool(st.get("equipmentOk", false))
	var eq_mode: String = str(st.get("equipmentMode", "invalid"))
	if not eq_ok or eq_mode == "invalid":
		return {
			"ok": false,
			"mode": "invalid",
			"firepower": 0.0,
			"rawOutput": 0.0,
			"healthyOutput": 0.0,
			"availabilityFactor": 0.0,
			"crewWeaponFactor": 0.0,
			"performanceFactor": clean_perf,
			"activeMounts": [],
			"mountCount": 0
		}

	var crew_wf: float = clampf(_finite_number(st.get("weaponFactor"), 0.0), 0.0, 1.0)
	var wf: float = crew_wf * clean_perf
	var ammo_now: float = maxf(0.0, _finite_number(boat.get("ammo"), 0.0))
	var has_ammo: bool = ammo_now > 0.0
	var spec_d: Dictionary = boat.get("spec", {}) if boat.get("spec") is Dictionary else {}
	var active_mounts: Array = []
	var healthy_output: float = 0.0
	var raw_output: float = 0.0
	var firepower: float = 0.0

	if eq_mode == "legacy":
		var mounts_leg: Array = spec_d.get("weaponMounts", []) if spec_d.get("weaponMounts") is Array else []
		if not mounts_leg.is_empty():
			for m_var in mounts_leg:
				if not (m_var is Dictionary):
					continue
				var m: Dictionary = m_var
				var kind_leg: String = str(m.get("kind", "gun"))
				var dmg_leg: float = maxf(1.0, _finite_number(m.get("damage"), 10.0))
				var fr_leg: float = maxf(0.1, _finite_number(m.get("fireRate"), 1.0))
				var ammo_cost_leg: int = maxi(1, int(ceil(_finite_number(m.get("ammoCost"), 1.0))))
				var mult_leg: float = 1.8 if kind_leg == "torpedo" else 1.0
				var out_leg: float = dmg_leg * fr_leg * mult_leg
				healthy_output += out_leg
				raw_output += out_leg
				var mount_power_leg: float = (out_leg * wf) if (has_ammo and wf > 0.0) else 0.0
				firepower += mount_power_leg
				active_mounts.append({
					"id": str(m.get("id", "mount%d" % active_mounts.size())),
					"kind": kind_leg,
					"damage": dmg_leg,
					"fireRate": fr_leg,
					"ammoCost": ammo_cost_leg,
					"hp": 1.0,
					"status": "ok",
					"mountFactor": 1.0,
					"effectiveWf": wf if has_ammo else 0.0,
					"healthyOutput": out_leg,
					"availableOutput": out_leg,
					"power": mount_power_leg
				})
		else:
			var kind_fb: String = str(spec_d.get("weapon", "gun"))
			var dmg_fb: float = maxf(1.0, _finite_number(spec_d.get("damage"), 10.0))
			var fr_power_fb: float = maxf(0.1, _finite_number(boat.get("economyBaseFireRate", spec_d.get("fireRate", 1.0)), 1.0))
			var fr_salvo_fb: float = maxf(0.1, _finite_number(boat.get("economyBaseFireRate", spec_d.get("fireRate", 1.5)), 1.5))
			# Preserve NavalOrders.fleet_performance legacy fallback (no weaponMounts): dmg * fr * wf without 1.8 torpedo multiplier.
			var out_fb: float = dmg_fb * fr_power_fb
			healthy_output = out_fb
			raw_output = out_fb
			firepower = (out_fb * wf) if (has_ammo and wf > 0.0) else 0.0
			active_mounts.append({
				"id": "mount0",
				"kind": kind_fb,
				"damage": dmg_fb,
				"fireRate": fr_salvo_fb,
				"ammoCost": 1,
				"hp": 1.0,
				"status": "ok",
				"mountFactor": 1.0,
				"effectiveWf": wf if has_ammo else 0.0,
				"healthyOutput": out_fb,
				"availableOutput": out_fb,
				"power": firepower
			})
		return {
			"ok": true,
			"mode": "legacy",
			"firepower": maxf(0.0, firepower),
			"rawOutput": maxf(0.0, raw_output),
			"healthyOutput": maxf(0.0, healthy_output),
			"availabilityFactor": 1.0 if healthy_output > 0.0 else 0.0,
			"crewWeaponFactor": crew_wf,
			"performanceFactor": clean_perf,
			"activeMounts": active_mounts,
			"mountCount": active_mounts.size()
		}

	# Canonical equipment mode: use only physical installed weapon mounts weighted by Damage.get_status weaponFactors.
	var snap: Dictionary = Records.snapshot(boat)
	if not snap.get("ok", false) or bool(snap.get("needsInitialize", true)):
		return {
			"ok": false,
			"mode": "invalid",
			"firepower": 0.0,
			"rawOutput": 0.0,
			"healthyOutput": 0.0,
			"availabilityFactor": 0.0,
			"crewWeaponFactor": 0.0,
			"performanceFactor": clean_perf,
			"activeMounts": [],
			"mountCount": 0
		}

	var base_spec: Dictionary = boat.get("baseSpec", {}) if (boat.get("baseSpec") is Dictionary and not boat.baseSpec.is_empty()) else spec_d
	var hardpoints: Array = MountLayout.hardpoints(base_spec)
	var valid_sockets: Dictionary = {}
	for pt in hardpoints:
		if pt is Dictionary and pt.has("id"):
			valid_sockets[str(pt.id)] = pt

	var spec_mounts_by_id: Dictionary = {}
	if spec_d.get("weaponMounts") is Array:
		for sm_var in spec_d["weaponMounts"]:
			if sm_var is Dictionary and sm_var.has("id"):
				var sm: Dictionary = sm_var
				spec_mounts_by_id[str(sm.id)] = sm

	var cat_weapons: Dictionary = Refit.catalog().get("weapons", {})
	var installed: Dictionary = snap.get("installed", {}) if snap.get("installed") is Dictionary else {}
	var weapon_factors: Dictionary = st.get("weaponFactors", {}) if st.get("weaponFactors") is Dictionary else {}

	for loc in MOUNT_LOCATIONS:
		if not installed.has(loc) or not valid_sockets.has(loc):
			continue
		var item: Dictionary = installed[loc]
		if str(item.get("family", "")) != "weapons":
			continue
		var type_id: String = str(item.get("typeId", ""))
		if type_id.is_empty() or not cat_weapons.has(type_id):
			continue

		var kind_can: String = "gun"
		var dmg_can: float = 10.0
		var fr_can: float = 1.0
		var ammo_cost_can: int = 1

		if type_id == "stock_primary":
			kind_can = str(base_spec.get("weapon", spec_d.get("weapon", "gun")))
			dmg_can = maxf(1.0, _finite_number(base_spec.get("damage", spec_d.get("damage", 12.0)), 12.0))
			if boat.get("baseSpec") is Dictionary and boat.baseSpec.has("fireRate"):
				fr_can = maxf(0.1, _finite_number(boat.baseSpec.get("fireRate"), 2.0))
			else:
				fr_can = maxf(0.1, _finite_number(boat.get("economyBaseFireRate", spec_d.get("fireRate", 2.0)), 2.0))
			ammo_cost_can = 1
			if spec_mounts_by_id.has(loc):
				var sm_stock: Dictionary = spec_mounts_by_id[loc]
				if not sm_stock.has("moduleId") or str(sm_stock.get("moduleId", "")) == "stock_primary":
					kind_can = str(sm_stock.get("kind", kind_can))
					dmg_can = maxf(1.0, _finite_number(sm_stock.get("damage"), dmg_can))
					fr_can = maxf(0.1, _finite_number(sm_stock.get("fireRate"), fr_can))
					ammo_cost_can = maxi(1, int(ceil(_finite_number(sm_stock.get("ammoCost"), 1.0))))
		else:
			var mod: Dictionary = cat_weapons[type_id]
			kind_can = str(mod.get("kind", "gun"))
			dmg_can = maxf(1.0, _finite_number(mod.get("damage"), 10.0))
			fr_can = maxf(0.1, _finite_number(mod.get("fireRate"), 1.0))
			ammo_cost_can = maxi(1, int(ceil(_finite_number(mod.get("ammoCost"), 1.0))))

		var status_str: String = str(item.get("status", "disabled"))
		var hp_val: float = clampf(_finite_number(item.get("hp"), 0.0), 0.0, 1.0)
		var mount_factor: float = clampf(_finite_number(weapon_factors.get(loc, 0.0), 0.0), 0.0, 1.0)
		if status_str == "disabled" or hp_val <= Core.DISABLE_HP + Core.EPS:
			mount_factor = 0.0

		var mult_can: float = 1.8 if kind_can == "torpedo" else 1.0
		var mount_healthy_out: float = dmg_can * fr_can * mult_can
		var mount_avail_out: float = mount_healthy_out * mount_factor
		var mount_eff_wf: float = wf * mount_factor
		var mount_power: float = (mount_healthy_out * mount_eff_wf) if (has_ammo and mount_eff_wf > 0.0) else 0.0

		healthy_output += mount_healthy_out
		raw_output += mount_avail_out
		firepower += mount_power
		active_mounts.append({
			"id": loc,
			"itemUid": str(item.get("itemUid", "")),
			"moduleId": type_id,
			"kind": kind_can,
			"damage": dmg_can,
			"fireRate": fr_can,
			"ammoCost": ammo_cost_can,
			"hp": hp_val,
			"status": status_str,
			"mountFactor": mount_factor,
			"effectiveWf": mount_eff_wf if has_ammo else 0.0,
			"healthyOutput": mount_healthy_out,
			"availableOutput": mount_avail_out,
			"power": mount_power
		})

	var avail_factor: float = clampf(raw_output / healthy_output, 0.0, 1.0) if healthy_output > 0.0 else 0.0
	return {
		"ok": true,
		"mode": "canonical",
		"firepower": maxf(0.0, firepower),
		"rawOutput": maxf(0.0, raw_output),
		"healthyOutput": maxf(0.0, healthy_output),
		"availabilityFactor": avail_factor,
		"crewWeaponFactor": crew_wf,
		"performanceFactor": clean_perf,
		"activeMounts": active_mounts,
		"mountCount": active_mounts.size()
	}


static func fleet_firepower(owner: Dictionary) -> float:
	if not (owner is Dictionary) or owner.is_empty():
		return 0.0
	var morale: float = clampf(_finite_number(owner.get("morale"), 85.0), 10.0, 100.0)
	var default_perf: float = 1.0 if not owner.has("performanceFactor") else (morale / 85.0)
	var perf_factor: float = clampf(_finite_number(owner.get("performanceFactor"), default_perf), 0.35, 1.0)
	var total_power: float = 0.0
	var boats: Array = owner.get("boats", []) if owner.get("boats") is Array else []
	for b_var in boats:
		if not (b_var is Dictionary):
			continue
		var b: Dictionary = b_var
		if bool(b.get("sunk", false)):
			continue
		var wp: Dictionary = boat_weapon_power(b, perf_factor)
		if bool(wp.get("ok", false)):
			total_power += maxf(0.0, _finite_number(wp.get("firepower"), 0.0))
	return snappedf(maxf(0.0, total_power), 0.1)
