extends RefCounted

const Expedition = preload("res://scripts/expedition.gd")
const Deployment = preload("res://scripts/deployment.gd")
const Goods = preload("res://scripts/goods.gd")
const CareerCosts = preload("res://scripts/career_costs.gd")
const MAX_CARDS = 8
const DISPLAY_CAP = 1000000000.0

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
				"Hail real nearby peaceful traffic with an armed threat; every loaded carrier must reach the exit.", "traffic"],
			["Budget the service voyage",
				"Escort success grants service credit and standing. Check payroll and stores; no coin fee is promised.", "supply"]]],
		["fisher", "Fisher", [
			["Prepare a working fishing boat",
				"Use a crewed fishing hull, stop in safe open water and let actual campaign time earn a bounded catch.", "fishing"],
			["Find a paying buyer",
				"Return to Market with the actual catch; sales need a business purse and leave unsold lots aboard.", "market"]]],
		["passenger", "Passenger operator", [
			["Quote a funded charter",
				"Prepare one transport or yacht with spare berths and food space for a real civilian cohort.", "jobs"],
			["Prepare the actual carrier",
				"Buy or commission a suitable hull, pay its crew and preserve the passengers' own savings.", "yard"]]],
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
			"This harbor protects operating lots and records actual supply coverage. Review exportable stock before buying.", "supply")

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
	budget["note"] = "Trip days, wages and material stores use the expedition report. Inspect Supply for material purchases at current prices. Empty durations have no finite estimate."

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
			"The expedition report records overload. Inspect fitted capacity and cargo weight.",
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
			"The recorded wage cover is shorter than this trip. Return wage budget: %s coins. Review available pay funds." %
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
