extends RefCounted

const Expedition = preload("res://scripts/expedition.gd")
const Deployment = preload("res://scripts/deployment.gd")
const Goods = preload("res://scripts/goods.gd")
const CareerCosts = preload("res://scripts/career_costs.gd")
const Refits = preload("res://scripts/refit.gd")
const Workshop = preload("res://scripts/fleet_workshop.gd")
const Identity = preload("res://scripts/fleet_identity.gd")
const FleetSupport = preload("res://scripts/fleet_support.gd")
const MAX_CARDS = 8
const DISPLAY_CAP = 1000000000.0

class PreviewCore extends RefCounted:
	var state: Dictionary
	var data: Dictionary
	var dock_id: String
	var source
	func _init(c, harbor_id: String):
		source = c
		state = c.state.duplicate(true)
		data = c.data
		dock_id = harbor_id
	func current_port() -> Dictionary:
		for p in state.get("ports", []) if state.get("ports") is Array else []:
			if p is Dictionary and str(p.get("id", "")) == dock_id:
				return p
		return {}
	func find_boat(uid: String) -> Dictionary:
		for b in state.get("fleet", []) if state.get("fleet") is Array else []:
			if b is Dictionary and str(b.get("uid", "")) == uid:
				return b
		return {}
	func hull(id: String) -> Dictionary:
		return source.hull(id) if source != null and source.has_method("hull") else {}
	func fitted_spec(boat: Dictionary) -> Dictionary:
		return source.fitted_spec(boat) if source != null and source.has_method("fitted_spec") else boat.get("spec", {})
	func fail(message: String) -> Dictionary:
		return {"ok": false, "message": message}

static func _finite(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))

static func _n(v, fallback: float = 0.0) -> float:
	return float(v) if _finite(v) else fallback

static func _positive(v) -> bool:
	return v if v is bool else _n(v) > 0.0

static func _shown(v, coins: bool = false):
	if not _finite(v):
		return null
	var n = clampf(float(v), -DISPLAY_CAP, DISPLAY_CAP)
	if coins:
		return int(ceil(n)) if n >= 0.0 else null
	return n

static func _amount(v) -> String:
	if not _finite(v):
		return "unavailable"
	if float(v) > DISPLAY_CAP:
		return "over 1000000000"
	if float(v) < -DISPLAY_CAP:
		return "below -1000000000"
	return str(int(ceil(float(v))))

static func _rows(v) -> Array:
	if v is Array:
		return v
	if v is Dictionary:
		return v.values()
	return []

static func _dict(v) -> Dictionary:
	return v if v is Dictionary else {}

static func _add(cards: Array, id: String, title: String, reason: String,
		action: String, urgent: bool = false) -> void:
	if cards.size() < MAX_CARDS:
		cards.append({"id":id, "title":title.left(72),
			"reason":reason.left(500), "actionId":action, "urgent":urgent})

static func _yard_ready(q: Dictionary) -> bool:
	if q.get("ok", false):
		return true
	if not q.get("validDraft", false) or int(_n(q.get("cost"), 0.0)) <= 0:
		return false
	var reasons: Array = _rows(q.get("reasons"))
	return not q.get("affordable", false) and reasons.size() == 1 and str(reasons[0]).begins_with("The whole fitting needs ")

static func _upgrade_entry(boat_name: String, name: String, slot_label: String,
		effect: String, cost: int, purse: int, reserve_wages: int,
		post_voyage_coins: int, action: String) -> Dictionary:
	var affordable_now: bool = purse >= cost
	var safe_now: bool = purse >= cost + reserve_wages
	var after_contract: bool = post_voyage_coins >= cost if post_voyage_coins >= 0 else false
	return {
		"boatName": boat_name,
		"name": name,
		"slotLabel": slot_label,
		"effect": effect,
		"cost": cost,
		"affordableNow": affordable_now,
		"safeReserveNow": safe_now,
		"affordableAfterContract": after_contract,
		"shortCoins": maxi(0, cost - purse),
		"action": action
	}

static func upgrade_quotes(c, post_voyage_coins: int = -1) -> Array:
	if c == null or not c.get("state") is Dictionary or not c.get("data") is Dictionary or not c.has_method("current_port"):
		return []
	var live_dock: Dictionary = c.current_port()
	if live_dock.is_empty() or not _rows(c.state.get("path")).is_empty():
		return []
	var view := PreviewCore.new(c, str(live_dock.get("id", "")))
	var dock: Dictionary = view.current_port()
	if dock.is_empty():
		return []
	var ship: Dictionary = view.find_boat(str(view.state.get("flagship", "")))
	if ship.is_empty() or ship.get("sunk", false) or (str(ship.get("storedPort", "")) != "" and str(ship.get("storedPort", "")) != str(dock.get("id", ""))):
		ship = {}
		for candidate in _rows(view.state.get("fleet")):
			if candidate is Dictionary and not candidate.get("sunk", false) and (str(candidate.get("storedPort", "")) == "" or str(candidate.get("storedPort", "")) == str(dock.get("id", ""))):
				ship = candidate
				break
	if ship.is_empty():
		return []
	var uid: String = str(ship.get("uid", ""))
	var boat_name: String = str(ship.get("name", "Flagship"))
	var base: Dictionary = view.hull(str(ship.get("type", "")))
	if uid.is_empty() or base.is_empty():
		return []
	var norm: Dictionary = Refits.normalize(base, _dict(ship.get("loadout")))
	if not norm.get("ok", false):
		return []
	var current_fit: Dictionary = norm.loadout
	var cat: Dictionary = Refits.catalog()
	var mounts: Array = Refits.hardpoints(base)
	var purse: int = maxi(0, int(_n(view.state.get("coins"))) - int(_n(view.state.get("wageArrears"))))
	var e_now: Dictionary = Expedition.report(view.state, view.data, 0.0)
	var reserve_wages: int = maxi(0, int(ceil(_n(e_now.get("returnWages")))))
	var results: Array = []

	var best_armor: Dictionary = {}
	for armor_id in ["scout_plating", "naval_plating"]:
		if str(current_fit.get("armor", "")) == armor_id:
			continue
		var trial_a: Dictionary = current_fit.duplicate(true)
		trial_a.armor = armor_id
		if not Refits.normalize(base, trial_a).get("ok", false):
			continue
		var qa: Dictionary = Workshop.preview(view, uid, trial_a)
		if _yard_ready(qa) and (best_armor.is_empty() or int(qa.cost) < int(best_armor.cost)):
			var info_a: Dictionary = _dict(_dict(cat.get("armor")).get(armor_id))
			var add_a: float = _n(info_a.get("armorAdd"))
			best_armor = _upgrade_entry(boat_name, str(info_a.get("name", armor_id)),
				"Hull protection", "+%.0f armor" % add_a, int(qa.cost), purse,
				reserve_wages, post_voyage_coins, "refit")
	if not best_armor.is_empty():
		results.append(best_armor)

	if not mounts.is_empty():
		var best_weapon: Dictionary = {}
		var slot_idx: int = 0
		for i in range(mounts.size()):
			if str(current_fit.weapons[i]).is_empty():
				slot_idx = i
				break
		var mount_label: String = "%d · %s" % [slot_idx + 1, str(_dict(mounts[slot_idx]).get("label", "Weapon mount"))]
		for weapon_id in ["rapid_gun", "light_cannon", "fire_rocket", "light_torpedo", "heavy_gun"]:
			if str(current_fit.weapons[slot_idx]) == weapon_id:
				continue
			var trial_w: Dictionary = current_fit.duplicate(true)
			trial_w.weapons = current_fit.weapons.duplicate()
			trial_w.weapons[slot_idx] = weapon_id
			if not Refits.normalize(base, trial_w).get("ok", false):
				continue
			var qw: Dictionary = Workshop.preview(view, uid, trial_w)
			if _yard_ready(qw) and (best_weapon.is_empty() or int(qw.cost) < int(best_weapon.cost)):
				var info_w: Dictionary = _dict(_dict(cat.get("weapons")).get(weapon_id))
				var eff_w: String = "%.0f dmg, %.0f range" % [_n(info_w.get("damage")), _n(info_w.get("range"))]
				best_weapon = _upgrade_entry(boat_name, str(info_w.get("name", weapon_id)),
					mount_label, eff_w, int(qw.cost), purse, reserve_wages,
					post_voyage_coins, "refit")
		if not best_weapon.is_empty():
			results.append(best_weapon)

	var best_engine: Dictionary = {}
	for engine_id in ["economy_drive", "boost_drive"]:
		if str(current_fit.get("engine", "")) == engine_id:
			continue
		var trial_e: Dictionary = current_fit.duplicate(true)
		trial_e.engine = engine_id
		if not Refits.normalize(base, trial_e).get("ok", false):
			continue
		var qe: Dictionary = Workshop.preview(view, uid, trial_e)
		if _yard_ready(qe) and (best_engine.is_empty() or int(qe.cost) < int(best_engine.cost)):
			var info_e: Dictionary = _dict(_dict(cat.get("engines")).get(engine_id))
			var eff_e: String = "-32% fuel burn" if engine_id == "economy_drive" else "+18% speed, +8% turn"
			best_engine = _upgrade_entry(boat_name, str(info_e.get("name", engine_id)),
				"Propulsion", eff_e, int(qe.cost), purse, reserve_wages,
				post_voyage_coins, "refit")
	if not best_engine.is_empty() and (bool(best_engine.affordableNow) or bool(best_engine.affordableAfterContract) or results.size() < 2):
		results.append(best_engine)

	if str(ship.get("conversion", "")).is_empty():
		var convs: Dictionary = Identity.conversions()
		var best_conv: Dictionary = {}
		for conv_id in ["cargo_rig", "survey_rig", "auxiliary_tanks"]:
			var qc: Dictionary = Identity.quote_conversion(view, uid, conv_id)
			if qc.get("ok", false) and int(_n(qc.get("cost"), 0.0)) > 0:
				if best_conv.is_empty() or int(qc.cost) < int(best_conv.cost):
					var info_c: Dictionary = _dict(convs.get(conv_id))
					var eff_c: String = "+35% hold" if conv_id == "cargo_rig" else ("+35% survey rate" if conv_id == "survey_rig" else "+50% fuel tank, -10% burn")
					best_conv = _upgrade_entry(boat_name, str(info_c.get("name", conv_id)),
						"Interior conversion", eff_c, int(qc.cost), purse,
						reserve_wages, post_voyage_coins, "fleet")
		if not best_conv.is_empty():
			results.append(best_conv)
	return results.slice(0, 4)

## One useful whole-fitting draft, quoted with the existing yard authority.
## The recommendation cannot spend cash. Main re-quotes it again on payment.
static func first_fit120(c, focus: String = "economy") -> Dictionary:
	var result: Dictionary = {"ok":false, "safe":false, "message":"Dock at a Shatter Coast harbor for paid fitting.", "focus":focus}
	var dock: Dictionary = c.current_port()
	if dock.is_empty() or not c.state.get("path", []).is_empty(): return result
	var view := PreviewCore.new(c, str(dock.get("id", "")))
	var boat: Dictionary = view.find_boat(str(view.state.get("flagship", "")))
	if boat.is_empty() or boat.get("sunk", false):
		result.message = "Choose a living flagship in Fleet before requesting a fitting."
		return result
	var base: Dictionary = view.hull(str(boat.get("type", "")))
	var current: Dictionary = Refits.normalize(base, boat.get("loadout", {}))
	if not current.get("ok", false):
		result.message = "Open Refit to inspect this boat's current equipment."
		return result
	var fit: Dictionary = current.loadout.duplicate(true)
	if focus == "armor": fit.armor = "scout_plating"
	else: fit.engine = "economy_drive"
	var q: Dictionary = Workshop.preview(view, str(boat.uid), fit)
	result.merge({"quote":q, "uid":str(boat.uid), "loadout":fit, "boatName":str(boat.get("name", "Flagship")), "cost":int(q.get("cost", 0)), "message":str(q.get("message", "Fitting unavailable."))}, true)
	if q.get("changes", []).is_empty():
		result.message = "This fitting is already installed. Choose the other comparison or open Refit."
		return result
	if not q.get("validDraft", false): return result
	var before: Dictionary = q.get("beforeSpec", {})
	var after: Dictionary = q.get("afterSpec", {})
	var fuel_change: float = (float(after.get("fuelUse", 1.0)) / maxf(0.001, float(before.get("fuelUse", 1.0))) - 1.0) * 100.0
	var speed_change: float = (float(after.get("speed", 1.0)) / maxf(0.001, float(before.get("speed", 1.0))) - 1.0) * 100.0
	var armor_change: float = float(after.get("armor", 0.0)) - float(before.get("armor", 0.0))
	result.title = "Long-voyage engine" if focus != "armor" else "Riveted light plates"
	result.effect = "Fuel use %+.0f%%; speed %+.0f%%." % [fuel_change, speed_change] if focus != "armor" else "Armor %+.0f; speed %+.0f%%." % [armor_change, speed_change]
	result.purpose = "Less fuel for paid freight and the trip home." if focus != "armor" else "More protection for convoy defense; slower travel still costs wages."
	if (focus == "armor" and armor_change <= 0.0) or (focus != "armor" and fuel_change >= 0.0):
		result.message = "Keep your current fitting; this draft would not improve the proposed job. Open Refit for a different comparison."
		return result
	# Reserve the actual current dock repair and store purchases as well as
	# two days' pay. Use the fitted boat on a detached copy, never a live edit.
	var costs_view := CareerCosts.QuoteView.new(c)
	var preview_boat: Dictionary = costs_view.find_boat(str(boat.uid))
	preview_boat.loadout = fit.duplicate(true)
	preview_boat.spec = after.duplicate(true)
	costs_view.state.coins = maxi(0, int(c.state.get("coins", 0)) - int(q.get("cost", 0)))
	var budget: Dictionary = CareerCosts._budget(costs_view, 0.0)
	var needed: int = int(budget.additionalCashCoins) + int(c.state.get("wageArrears", 0)) + FleetSupport.premium(costs_view.state, true)
	var ammo_cases: float = 0.0
	var kits: float = 0.0
	for working in costs_view.active_fleet():
		var magazine: float = maxf(80.0, float(working.get("spec", {}).get("ammoCapacity", 80.0)))
		ammo_cases += maxf(0.0, magazine - float(working.get("ammo", 0.0))) / Goods.ROUNDS_PER_CASE
		kits += maxf(0.0, 6.0 - float(working.get("supplies", 0.0)))
	ammo_cases = maxf(0.0, ammo_cases - float(c.state.get("cargo", {}).get("ammo", 0.0)))
	kits = maxf(0.0, kits - float(c.state.get("cargo", {}).get("supplies", 0.0)))
	var working_stores: int = ceili(ammo_cases * float(budget.ammoCaseCoins)) + ceili(kits * float(budget.repairKitUnitCoins))
	needed += working_stores
	budget["workingStoreCoins"] = working_stores
	budget.summary += " Keep another %d coins for current ammunition and six working repair kits per boat, after loose stores already owned." % working_stores
	var remaining: int = int(c.state.get("coins", 0)) - int(q.get("cost", 0))
	result.merge({"ok":bool(q.get("ok", false)), "reserveCoins":needed, "remainingCoins":remaining, "budget":budget,
		"safe":bool(q.get("ok", false)) and int(q.get("cost", 0)) > 0 and remaining >= needed and bool(budget.get("repairQuoteAvailable", false))}, true)
	if not q.get("ok", false): result.message = str(q.get("message", "The yard cannot complete this fitting."))
	elif remaining < needed: result.message = "Keep %d coins for crew, stores and current repairs; this fitting would leave %d." % [needed, remaining]
	else: result.message = "The yard bill leaves the harbor reserve. Price the chosen onward voyage before sailing."
	return result

static func recovery_notes(c, offers: Array, q: Dictionary) -> Array:
	if c == null or not c.get("state") is Dictionary or q.is_empty() or bool(q.get("ready", false)):
		return []
	var notes: Array = []
	var budget: Dictionary = _dict(q.get("operatingCosts"))
	var e: Dictionary = _dict(q.get("endurance"))
	var coins: int = maxi(0, int(_n(c.state.get("coins"))))
	var arrears: int = maxi(0, int(_n(c.state.get("wageArrears"))))
	var cash_needed: int = maxi(0, int(_n(budget.get("additionalCashCoins"))) + arrears)
	var low_cash: bool = coins < cash_needed or (_finite(e.get("affordableDays")) and _n(e.get("affordableDays")) < _n(budget.get("days"))) or arrears > 0
	if low_cash:
		var arrears_clause: String = ", %d wage arrears" % arrears if arrears > 0 else ""
		notes.append("Available coins: %d. Required for this trip: %d (%d payroll reserve, %d store purchases, %d dock repairs%s)." % [
			coins, cash_needed, int(_n(budget.get("wageCoins"))),
			int(_n(budget.get("foodPurchaseCoins"))) + int(_n(budget.get("fuelPurchaseCoins"))),
			int(_n(budget.get("repairQuoteCoins"))), arrears_clause])
	var current_offer: Dictionary = _dict(q.get("offer"))
	var current_id: String = str(current_offer.get("id", ""))
	var best_alt: Dictionary = {}
	var best_quote: Dictionary = {}
	for cand in offers:
		if not cand is Dictionary or str(cand.get("id", "")) == current_id:
			continue
		var cq: Dictionary = CareerCosts.contract_quote(c, cand)
		if not cq.get("canAccept", false) or not cq.get("funded", false) or not cq.get("routeAvailable", false) or not cq.get("ready", false):
			continue
		var cand_cash: int = int(_n(_dict(cq.get("operatingCosts")).get("additionalCashCoins")))
		if coins < cand_cash + arrears:continue
		var cand_hostiles: int = _rows(cand.get("enemyHulls")).size()
		var best_cash: int = int(_n(_dict(best_quote.get("operatingCosts")).get("additionalCashCoins")))
		var best_hostiles: int = _rows(best_alt.get("enemyHulls")).size()
		if best_alt.is_empty() or cand_hostiles < best_hostiles or (cand_hostiles == best_hostiles and cand_cash < best_cash):
			best_alt = cand
			best_quote = cq
	if not best_alt.is_empty():
		var alt_cash: int = int(_n(_dict(best_quote.get("operatingCosts")).get("additionalCashCoins")))
		var alt_hostiles: int = _rows(best_alt.get("enemyHulls")).size()
		notes.append("Next affordable departure: %s (%d hostile %s, %d coins gross, %d coins voyage outlay) is funded and open for review above." % [
			str(best_alt.get("title", "Local contract")), alt_hostiles,
			"boat" if alt_hostiles == 1 else "boats",
			int(_n(best_quote.get("grossRewardCoins"))), alt_cash])
	var saleable_lots: int = 0
	var cargo: Dictionary = _dict(c.state.get("cargo"))
	for good in cargo:
		if str(good) not in ["food", "fuel", "supplies", "ammo"]:
			saleable_lots += maxi(0, floori(_n(cargo.get(good))))
	if low_cash and saleable_lots > 0 and not c.current_port().is_empty():
		notes.append("Review possible sales: %d cargo %s in Hold, subject to buyer funds and market access." % [saleable_lots, "lot" if saleable_lots == 1 else "lots"])
	return notes

static func careers() -> Array:
	var rows = [
		["captain", "Captain", [
			["Review the battle line",
				"Compare fitted hulls with the 300-point deployment and inspect damage.", "fleet"],
			["Protect the return",
				"Check voyage payroll, food, fuel and repair stores before sailing.", "supply"]]],
		["explorer", "Explorer", [
			["Choose a measured survey",
				"Review exploration routes alongside crew reserves and return supplies.", "exploration"],
			["Prepare people ashore",
				"Check training progress and qualifications before assigning expedition work.", "training"]]],
		["merchant", "Merchant", [
			["Compare a trading route",
				"Review current prices, cargo weight and return costs before buying.", "trade"],
			["Read the company ledger",
				"Compare operating coins, invested capital and recorded net profit.", "companies"]]],
		["privateer", "Privateer", [
			["Check the legal stakes",
				"Read recorded fines and restrictions before choosing an encounter.", "law"],
			["Inspect boarding readiness",
				"Review actual crew and hull readiness before planning a boarding attempt.", "boarding"]]],
		["escort", "Escort", [
			["Protect a loaded convoy",
				"Hail nearby loaded friendly traffic for paid passage, or defend a threatened convoy to its exit.", "traffic"],
			["Budget the service voyage",
				"Paid passage escrows a client fee; voluntary rescue grants service credit and standing. Check payroll and stores.", "supply"]]],
		["fisher", "Fisher", [
			["Prepare a working fishing boat",
				"Sail a crewed fishing hull to safe open water, stop and work for a daily catch.", "fishing"],
			["Find a paying buyer",
				"Return to Market with your catch; sales depend on local buyer cash and leave unsold lots aboard.", "market"]]],
		["passenger", "Passenger operator", [
			["Quote a funded charter",
				"Prepare a transport or yacht with spare berths and food space for a funded charter.", "jobs"],
			["Prepare the actual carrier",
				"Buy or commission a suitable hull, pay its crew and carry passengers safely to their destination.", "yard"]]],
		["harbormaster", "Harbormaster", [
			["Check workplace commitments",
				"Review employees, cash, fatigue and arrears before funding more work.", "workers"],
			["Review production equipment",
				"Inspect commissioning, active and lost tooling before ordering equipment.", "tooling"]]]
	]
	var result: Array = []
	for row in rows:
		var suggestions: Array = []
		for i in range(row[2].size()):
			var item = row[2][i]
			_add(suggestions, "career_%s_%d" % [row[0], i],
				item[0], item[1], item[2])
		result.append({"id":row[0], "name":row[1], "suggestions":suggestions})
	return result

static func _unique(v) -> Array:
	var result: Array = []
	var seen = {}
	for b in _rows(v):
		if not b is Dictionary:
			continue
		var uid = b.get("uid")
		if uid is String and uid != "" and not seen.has(uid):
			seen[uid] = true
			result.append(b)
	return result

static func _companies(s: Dictionary) -> Array:
	var result: Array = []
	var seen = {}
	for book in _rows(s.get("shippingCompanies")):
		if not book is Dictionary or not book.get("ownerId") is String or book.get("status","")=="collected":
			continue
		for owner in _rows(s.get("fleetOwners")):
			if not owner is Dictionary:
				continue
			var id = book.ownerId
			if owner.get("id") == id and owner.get("playerCompany", false) == true \
					and not seen.has(id):
				seen[id] = true
				result.append({"owner":owner, "book":book})
	return result

static func _opportunities(cards: Array, s: Dictionary, p: Dictionary,
		links: Array) -> void:
	if not links.is_empty():
		var chosen = links[0]
		for link in links:
			if link.book.get("recall", false) == true \
					or _n(link.book.get("netProfit")) < 0.0 \
					or _n(link.owner.get("wageArrears")) > 0.0:
				chosen = link
				break
		var owner: Dictionary = chosen.owner
		var book: Dictionary = chosen.book
		var parts: Array[String] = []
		if book.get("status") is String:
			parts.append("Status: " + book.status.left(40))
		if owner.get("route") is Array:
			parts.append("%d recorded route stops" % owner.route.size())
		if book.get("recall", false) == true:
			parts.append("recall requested")
		if _finite(book.get("netProfit")):
			parts.append("net profit %s coins" % _amount(book.netProfit))
		if _finite(owner.get("coins")):
			parts.append("operating coins %s coins" % _amount(owner.coins))
		if _finite(owner.get("crewPurse")):
			parts.append("crew purse %s coins" % _amount(owner.crewPurse))
		parts.append("Invested capital is tracked separately from operating profit")
		_add(cards, "companies", "Review a shipping company",
			"; ".join(parts) + ".", "companies")

	var strained = 0
	for business in _rows(s.get("businesses")):
		if not business is Dictionary:
			continue
		var labor = _dict(business.get("labor"))
		var dry = _finite(business.get("coins")) \
			and _n(business.coins) <= 0.0 and _rows(business.get("employees")).size() > 0
		if _positive(labor.get("striking")) or _n(labor.get("fatigue")) > 0.0 \
				or _n(business.get("arrearsHousehold")) + _n(business.get("arrearsExpert")) > 0.0 or dry:
			strained += 1
	if strained > 0:
		_add(cards, "workers", "Review workplace strain",
			"%d businesses record labor strain or employees without operating coins. Inspect their accounts." % strained,
			"workers")

	var jobs = _rows(_dict(p.get("training")).get("jobs"))
	if not jobs.is_empty():
		_add(cards, "training", "Check training progress",
			"%d training jobs are recorded here. Review progress and qualifications before assigning crews." % jobs.size(),
			"training")
	var reserves = p.get("reserves")
	if reserves is Dictionary and not reserves.is_empty():
		_add(cards, "reserves", "Inspect harbor reserves",
			"This harbor holds protected operating stock alongside exportable goods. Check Supply before buying bulk stores.", "supply")

	var counts = {"commissioning":0, "active":0, "lost":0}
	for item in _rows(_dict(s.get("tooling")).get("items")):
		if item is Dictionary and counts.has(item.get("location")):
			counts[item.location] += 1
	if counts.commissioning + counts.active + counts.lost > 0:
		_add(cards, "tooling", "Review production tooling",
			"%d commissioning, %d active, %d lost. Inspect equipment before committing more coins." %
				[counts.commissioning, counts.active, counts.lost], "tooling")

	var law = _dict(s.get("tradeLaw"))
	var embargoes = _rows(law.get("bans")).size()
	var fines: float=0.0
	for debt in _rows(law.get("debts")):
		if debt is Dictionary:fines+=_n(debt.get("amount"))
	if fines > 0.0 or embargoes > 0:
		var reason = "%d embargo records. " % embargoes
		if fines > 0.0:
			reason += "Recorded fine: %s coins. " % _amount(fines)
		_add(cards, "law", "Review trade restrictions",
			reason + "Inspect Law before planning the next transaction.", "law")

	var defenses = p.get("defenses")
	var entries = [defenses] if defenses is Dictionary \
		and defenses.has("active") else _rows(defenses)
	var inactive = 0
	for defense in entries:
		if defense is Dictionary and defense.get("active") is bool \
				and not defense.active:
			inactive += 1
	if inactive > 0:
		_add(cards, "defenses", "Inspect harbor defenses",
			"%d defense records are inactive. Review their requirements at the harbor." % inactive,
			"regional")

static func report(c, route_distance: float = 0.0,
		career: String = "captain") -> Dictionary:
	if c == null or not c.state is Dictionary or not c.data is Dictionary:
		return {"ok":false, "day":0.0, "cards":[],
			"warnings":["Campaign data is unavailable."], "warningCount":1}
	var s: Dictionary = c.state
	var notes: Array = []
	var route_valid = is_finite(route_distance) \
		and route_distance >= 0.0 and route_distance <= DISPLAY_CAP
	var route = route_distance if route_valid else 0.0
	if not route_valid:
		notes.append("Invalid route distance: preview uses zero travel distance plus the recorded reserve. Choose a route before sailing.")
	var choice: Dictionary = {}
	var options = careers()
	for option in options:
		if option.id == career:
			choice = option
			break
	if choice.is_empty():
		choice = options[0]
		notes.append("Unknown career: showing Captain suggestions.")

	# Expedition.report is the existing read-only source of voyage estimates.
	var e: Dictionary = Expedition.report(s, c.data, route)
	var budget = {}
	for key in ["usableCapacity", "cargoWeight", "freeCapacity", "overload",
			"crew", "fuelDays", "foodDays", "repairKits", "reserveDays",
			"affordableDays", "tripDays"]:
		budget[key] = _shown(e.get(key))
	if e.get("overload") is bool:
		budget.overload = e.overload
	for key in ["dailyWages", "returnWages"]:
		budget[key] = _shown(e.get(key), true)
	budget["sailorDayCoins"] = Goods.SAILOR_WAGE
	budget["displayCapped"] = false
	for value in e.values():
		if _finite(value) and absf(float(value)) > DISPLAY_CAP:
			budget.displayCapped = true
	if budget.displayCapped:
		notes.append("Large numerical estimates are capped at 1000000000 for display.")
	budget["note"] = "Trip days, payroll and onboard stores come from your current fleet. Open Expedition preparation for harbor store prices."

	var links = _companies(s)
	var owned = _unique(_rows(s.get("fleet"))+_rows(s.get("boardingPrizes")))
	var player_count = owned.size()
	var ids = {}
	for b in owned:
		ids[b.uid] = true
	for link in links:
		for b in _unique(link.owner.get("boats")):
			if not ids.has(b.uid):
				ids[b.uid] = true
				owned.append(b)
	var stored = 0
	var support = 0
	var sunk = 0
	for b in owned:
		if b.get("storedPort", "") is String and b.get("storedPort", "") != "":
			stored += 1
		if b.get("supportOnly", false) == true:
			support += 1
		if b.get("sunk", false) == true:
			sunk += 1
	# Deployment receives detached hulls; reserves never add cargo capacity here.
	var active = _unique(c.active_fleet()).duplicate(true)
	var split: Dictionary = Deployment.split(active)
	var fleet = {"owned":owned.size(), "player":player_count,
		"company":owned.size() - player_count, "companies":links.size(),
		"stored":stored, "support":support, "sunk":sunk, "active":active.size(),
		"deployed":_rows(split.get("deployed")).size(),
		"reserve":_rows(split.get("reserve")).size(),
		"points":_shown(split.get("points"), true),
		"totalPoints":_shown(Deployment.total(active), true),
		"limit":Deployment.LIMIT}

	var cards: Array = []
	var under = 0
	var wet = 0
	var fire = 0
	var damaged = 0
	for b in _unique(s.get("fleet")):
		if b.get("sunk",false) or str(b.get("storedPort",""))!="":continue
		if _n(b.get("crew")) < _n(b.get("crewMin")):
			under += 1
		if _n(b.get("water")) > 0.0:
			wet += 1
		if _positive(b.get("fire")):
			fire += 1
		if b.get("needsHarborRepair", false) == true \
				or (_n(b.get("maxHp")) > 0.0 \
				and _n(b.get("hp")) < _n(b.maxHp) * 0.25):
			damaged += 1
	if wet + fire + damaged > 0:
		_add(cards, "hulls", "Stabilize the active hulls",
			"%d taking water, %d with recorded fire, %d badly damaged or needing harbor repair. Inspect them before sailing." %
				[wet, fire, damaged], "fleet", true)
	if under > 0:
		_add(cards, "crew", "Fill essential crew positions",
			"%d active hulls have fewer sailors than their minimum crew." % under,
			"fleet", true)

	var owed = _n(s.get("wageArrears"))
	var company_owed = 0.0
	for link in links:
		company_owed += maxf(0.0, _n(link.owner.get("wageArrears")))
	if owed > 0.0 or company_owed > 0.0:
		_add(cards, "pay", "Review overdue crew pay",
			"Player crew arrears: %s coins; company crew arrears: %s coins." %
				[_amount(maxf(0.0, owed)), _amount(company_owed)],
			"supply" if owed > 0.0 else "companies", true)
	if _positive(e.get("overload")):
		_add(cards, "overload", "Reduce the loaded hold",
			"Cargo weight exceeds fitted hold capacity. Offload cargo or shift stores in Hold before sailing.",
			"hold", true)

	var trip = _n(e.get("tripDays"))
	var shortages: Array[String] = []
	for key in ["foodDays", "fuelDays"]:
		if _finite(e.get(key)) and _n(e[key]) < trip:
			var label = "Food" if key == "foodDays" else "Fuel"
			shortages.append("%s covers %.1f days against %.1f trip days" %
				[label, _shown(e[key]), _shown(trip)])
	if damaged > 0 and _finite(e.get("repairKits")) and _n(e.repairKits) <= 0.0:
		shortages.append("No repair kits are recorded")
	if not shortages.is_empty():
		_add(cards, "stores", "Check voyage supplies",
			"; ".join(shortages) + ".", "supply", true)
	if _finite(e.get("affordableDays")) and _n(e.get("dailyWages")) > 0.0 \
			and _n(e.affordableDays) < trip:
		_add(cards, "return_pay", "Protect the return payroll",
			"Purse covers fewer wage days than this trip. Return payroll needed: %s coins." %
				_amount(e.get("returnWages")), "supply", true)

	var expedition_warnings: Array[String] = []
	for warning in _rows(e.get("warnings")):
		if warning is String:
			var text = warning.strip_edges().left(200)
			if text != "" and not expedition_warnings.has(text):
				expedition_warnings.append(text)
	if not expedition_warnings.is_empty():
		_add(cards, "expedition", "Review the expedition check",
			"; ".join(expedition_warnings.slice(0, 2)), "hold", true)
	var crisis: Dictionary=_dict(s.get("regionalCrises"))
	var active_crises: int=0
	for record in _rows(crisis.get("crises")):
		if record is Dictionary and record.get("active",false):active_crises+=1
	if active_crises>0:_add(cards,"crises","Review dated regional crises","%d sustained crisis records have actual food, pay or unrest evidence. Review relief or a funded civilian passage."%active_crises,"crises")
	var cohorts: Array=_rows(crisis.get("jobs"))
	if not cohorts.is_empty():_add(cards,"passengers","Check your passenger manifests","%d funded cohorts have real people, savings, provisions and reception obligations. Check their named boats and destinations."%cohorts.size(),"crises",true)
	_opportunities(cards, s, _dict(c.current_port()), links)
	for suggestion in choice.suggestions:
		if cards.size() < MAX_CARDS:
			cards.append(suggestion.duplicate(true))
	var career_plan: Dictionary = CareerCosts.plan(c, str(choice.id))
	var convoy_ops: Array = _rows(career_plan.get("convoyOpportunities"))
	if not convoy_ops.is_empty() and cards.size() < MAX_CARDS:
		var conv: Dictionary = _dict(convoy_ops[0])
		_add(cards, "convoy_opportunity", "Inspect witnessed civilian convoy",
			"%s carries %.0f %s (~%s coins) toward %s: hail for escort (+5 standing, 1 service credit) when threatened, or intercept as piracy." % [
				str(conv.get("name", "Trader convoy")), _n(conv.get("tradeCargo")),
				str(conv.get("tradeGood", "cargo")), _amount(conv.get("cargoValueCoins")),
				str(conv.get("destinationName", "harbor"))], "traffic")

	var warnings: Array = []
	for card in cards:
		if card.urgent:
			warnings.append(card.reason)
	for warning in expedition_warnings:
		if not warnings.has(warning):
			warnings.append(warning)
	return {"ok":true, "day":_shown(maxf(0.0, _n(s.get("day")))),
		"career":choice.id, "routeDistance":route, "routeValid":route_valid,
		"careerPlan":career_plan, "convoyOpportunities":convoy_ops,
		"notes":notes, "fleet":fleet, "route_trip_returnbudget":budget,
		"cards":cards, "warnings":warnings.slice(0, MAX_CARDS),
		"warningCount":warnings.size()}
