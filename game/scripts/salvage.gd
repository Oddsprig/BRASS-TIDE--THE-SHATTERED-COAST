extends RefCounted
## v0.010 persistent individual wrecks and salvage recovery.
## Pure data over campaign state; root owns UI, chart markers, travel-speed
## integration and harbor repair/crew flows. Wrecks live in state["wrecks"]
## (Array, bounded) with a monotonic state["wreckSeq"] id counter. Every
## record is plain JSON: no object references, no engine types.
## A wreck settles exactly once: stripped XOR towed, never both, never twice.

const Goods = preload("res://scripts/goods.gd")
const Money = preload("res://scripts/money.gd")
const Construction = preload("res://scripts/construction.gd")
const Damage = preload("res://scripts/damage.gd")
const Refits=preload("res://scripts/refit.gd")

const MAX_WRECKS := 128
const MODE_STRIP := "strip"
const MODE_TOW := "tow"
const STATUS_UNCLAIMED := "unclaimed"
const STATUS_STRIPPED := "stripped"
const STATUS_TOWED := "towed"
const TOW_HP_FRACTION := 0.35
# Root multiplies traveling fleet speed by the smallest towSpeedFactor among
# towed boats it is moving; the field is stamped on the recovered boat.
const TOW_SPEED_FACTOR := 0.55
# Site-seeded wrecks use one fixed recoverable fraction: no rolls, no rerolls.
const SITE_FRACTION := 0.30


static func _is_num(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func _num(v, fallback: float = 0.0) -> float:
	return float(v) if _is_num(v) else fallback


static func _round2(v: float) -> float:
	return snappedf(v, 0.01)


static func _position_xy(position) -> Array:
	if position is Dictionary and _is_num(position.get("x", null)) and _is_num(position.get("y", null)):
		return [float(position["x"]), float(position["y"])]
	if position is Vector2 and is_finite(position.x) and is_finite(position.y):
		return [float(position.x), float(position.y)]
	if position is Array and position.size() >= 2 and _is_num(position[0]) and _is_num(position[1]):
		return [float(position[0]), float(position[1])]
	return []


static func _goods_weight(items: Dictionary) -> float:
	var weight := 0.0
	for good in items:
		if Goods.ITEMS.has(good):
			weight += maxf(0.0, _num(items[good])) * float(Goods.ITEMS[good]["weight"])
	return weight


static func _clean_amounts(raw) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for good in raw:
			if Goods.ITEMS.has(str(good)):
				var amount := maxf(0.0, _num(raw[good]))
				if amount > 0.0:
					out[str(good)] = amount
	return out


static func _sanitize_wreck(raw) -> Dictionary:
	if not (raw is Dictionary) or str(raw.get("id", "")).is_empty():
		return {}
	var status := str(raw.get("status", STATUS_UNCLAIMED))
	if not status in [STATUS_UNCLAIMED, STATUS_STRIPPED, STATUS_TOWED]:
		status = STATUS_UNCLAIMED
	return {
		"id": str(raw["id"]), "sourceId": str(raw.get("sourceId", "")),
		"shipId": str(raw.get("shipId", "")), "uid": str(raw.get("uid", "")),
		"hull": str(raw.get("hull", "")), "name": str(raw.get("name", "Wreck")),
		"team": str(raw.get("team", "")), "friendly": bool(raw.get("friendly", false)),
		"x": _num(raw.get("x", 0.0)), "y": _num(raw.get("y", 0.0)),
		"battleX": _num(raw.get("battleX", 0.0)), "battleY": _num(raw.get("battleY", 0.0)),
		"cause": str(raw.get("cause", "")), "day": _num(raw.get("day", 0.0)),
		"stores": _clean_amounts(raw.get("stores", {})),
		"components": _clean_amounts(raw.get("components", {})),
		"status": status, "claimedMode": str(raw.get("claimedMode", "")),
		"towedBoatUid": str(raw.get("towedBoatUid", "")),
		"hullStripped":bool(raw.get("hullStripped",false)),
		"sourceLoadout":raw.get("sourceLoadout",{}).duplicate(true) if raw.get("sourceLoadout",{}) is Dictionary else {},
	}


static func _prune(state: Dictionary) -> void:
	var wrecks: Array = state["wrecks"]
	while wrecks.size() > MAX_WRECKS:
		var drop := -1
		for i in range(wrecks.size()):
			if str(wrecks[i].get("status", "")) != STATUS_UNCLAIMED:
				drop = i
				break
		wrecks.remove_at(drop if drop >= 0 else 0)


# Creates/normalizes state["wrecks"] + state["wreckSeq"]. Idempotent and safe
# on legacy saves: wreckSeq never decreases and always exceeds every existing
# numeric wreck suffix, so ids stay monotonic across save/load and pruning.
static func ensure(state: Dictionary) -> Dictionary:
	if not state.get("wreckSeededSources") is Dictionary:state.wreckSeededSources={}
	if not (state.get("wrecks") is Array):
		state["wrecks"] = []
	var cleaned: Array = []
	var seen := {}
	var max_suffix := 0
	for raw in state["wrecks"]:
		var wreck := _sanitize_wreck(raw)
		if wreck.is_empty() or seen.has(wreck["id"]):
			continue
		seen[wreck["id"]] = true
		cleaned.append(wreck)
		var tail := str(wreck["id"]).trim_prefix("wreck-")
		if tail.is_valid_int():
			max_suffix = maxi(max_suffix, int(tail))
	state["wrecks"] = cleaned
	var seq := int(_num(state.get("wreckSeq", 0)))
	state["wreckSeq"] = maxi(seq, max_suffix)
	_prune(state)
	return state


static func _next_id(state: Dictionary) -> String:
	state["wreckSeq"] = int(state.get("wreckSeq", 0)) + 1
	return "wreck-%d" % int(state["wreckSeq"])


static func find_wreck(state: Dictionary, wreck_id: String) -> Dictionary:
	ensure(state)
	for wreck in state["wrecks"]:
		if str(wreck.get("id", "")) == wreck_id:
			return wreck
	return {}


static func _by_source(state: Dictionary, source_id: String) -> Array:
	var out: Array = []
	if source_id.is_empty():
		return out
	for wreck in state["wrecks"]:
		if str(wreck.get("sourceId", "")) == source_id:
			out.append(wreck)
	return out


# Deterministic recoverable fraction of one physical hull: better-preserved
# engines leave more to recover, fire leaves less. No randomness anywhere.
static func _recoverable_fraction(ship: Dictionary) -> float:
	var engine := clampf(_num(ship.get("engine", 0.0)), 0.0, 1.0)
	var fraction := 0.25 + 0.25 * engine
	if _num(ship.get("fire", 0.0)) > 0.0:
		fraction -= 0.10
	return clampf(fraction, 0.10, 0.50)


# Finite component inventory derived from that hull's real build bill
# (construction.gd blueprint materials), scaled once at record time and then
# frozen in the save. Whole engine/gun assemblies floor to whole units.
static func _components_for(spec: Dictionary, fraction: float) -> Dictionary:
	var out := {}
	if spec.is_empty():
		return out
	var materials: Dictionary = Construction.blueprint(spec).get("materials", {})
	for good in materials:
		if not Goods.ITEMS.has(str(good)):
			continue
		var amount := _num(materials[good]) * fraction
		if str(good) in ["engines", "guns"]:
			amount = floorf(amount)
		amount = _round2(maxf(0.0, amount))
		if amount > 0.0:
			out[str(good)] = amount
	return out


# Surviving onboard stores in cargo units. Fuel drums and supply kits are the
# same units harbor.gd loads 1:1; ammunition rounds convert at the existing
# 50 rounds per cargo case (goods.gd ROUNDS_PER_CASE), kept fractional so no
# rounds silently vanish or appear.
static func _stores_for(ship: Dictionary) -> Dictionary:
	var out := {}
	var fuel := maxf(0.0, _num(ship.get("fuel", 0.0)))
	var supplies := maxf(0.0, _num(ship.get("supplies", 0.0)))
	var ammo_cases := maxf(0.0, _num(ship.get("ammo", 0.0))) / float(Goods.ROUNDS_PER_CASE)
	if fuel > 0.0:
		out["fuel"] = fuel
	if supplies > 0.0:
		out["supplies"] = supplies
	if ammo_cases > 0.0:
		out["ammo"] = ammo_cases
	return out


# Records every actually destroyed boat in a finished battle, friendly and
# enemy alike, from the battle's own ships (sunk == true) enriched with its
# combat_events wreck records (cause). Live, retreated and reserve boats are
# never recorded. Chart position is the campaign position where the battle
# happened (state.position); battle-local coordinates are kept separately.
# Idempotent per source_id: re-recording the same battle returns the existing
# records and adds nothing. Returns copies of the records for that source.
static func record_battle(core, battle: Dictionary, source_id: String) -> Array:
	if core == null or not (core.get("state") is Dictionary):
		return []
	var state: Dictionary = core.state
	ensure(state)
	var existing := _by_source(state, source_id)
	if not existing.is_empty():
		return existing.duplicate(true)
	var causes := {}
	for record in battle.get("wrecks", []) if battle.get("wrecks") is Array else []:
		if record is Dictionary:
			causes[str(record.get("id", ""))] = str(record.get("cause", ""))
			causes[str(record.get("uid", ""))] = str(record.get("cause", ""))
	var xy := _position_xy(battle.get("chartPosition",state.get("position", {})))
	var chart_x: float=float(xy[0]) if xy.size()==2 else 0.0
	var chart_y: float=float(xy[1]) if xy.size()==2 else 0.0
	var created: Array = []
	var seen_ships := {}
	for ship in battle.get("ships", []) if battle.get("ships") is Array else []:
		if not (ship is Dictionary) or not bool(ship.get("sunk", false)):
			continue
		var ship_key := str(ship.get("uid", ship.get("id", "")))
		if ship_key.is_empty() or seen_ships.has(ship_key):
			continue
		seen_ships[ship_key] = true
		var spec: Dictionary = ship.get("spec", {}) if ship.get("spec") is Dictionary else {}
		var hull_id := str(ship.get("type", spec.get("id", "")))
		var wreck := {
			"id": _next_id(state), "sourceId": source_id,
			"shipId": str(ship.get("id", "")), "uid": str(ship.get("uid", ship.get("id", ""))),
			"hull": hull_id, "name": str(ship.get("name", spec.get("name", "Wreck"))),
			"team": str(ship.get("team", "")), "friendly": str(ship.get("team", "")) == "player",
			"x": chart_x, "y": chart_y,
			"battleX": _num(ship.get("x", 0.0)), "battleY": _num(ship.get("y", 0.0)),
			"cause": str(causes.get(str(ship.get("id", "")), causes.get(ship_key, ""))),
			"day": _num(state.get("day", 0.0)),
			"stores": _stores_for(ship),
			"components": _components_for(spec, _recoverable_fraction(ship)),
			"sourceLoadout":ship.get("loadout",Refits.defaults(spec)).duplicate(true),
			"status": STATUS_UNCLAIMED, "claimedMode": "", "towedBoatUid": "", "hullStripped":false,
		}
		state["wrecks"].append(wreck)
		created.append(wreck.duplicate(true))
	_prune(state)
	return created


# Seeds one finite authored wreck at a survey site (or any {id,x,y} anchor).
# Deterministic: fixed SITE_FRACTION of that hull's blueprint materials and
# no onboard stores unless root passes explicit finite stores. Idempotent by
# source_id, defaulting to "site:<site id>", so re-seeding never duplicates
# or rerolls. Returns a copy of the record, or {} for an unknown hull/anchor.
static func seed_site_wreck(core, site: Dictionary, hull_id: String, source_id: String = "", stores: Dictionary = {}) -> Dictionary:
	if core == null or not (core.get("state") is Dictionary):
		return {}
	var state: Dictionary = core.state
	ensure(state)
	var source := source_id if not source_id.is_empty() else "site:%s" % str(site.get("id", ""))
	var existing := _by_source(state, source)
	if not existing.is_empty():
		return existing[0].duplicate(true)
	if state.wreckSeededSources.has(source):return {}
	var xy := _position_xy(site)
	var spec: Dictionary = core.hull(hull_id) if core.has_method("hull") else {}
	if xy.size() != 2 or spec.is_empty() or source == "site:":
		return {}
	var wreck := {
		"id": _next_id(state), "sourceId": source, "shipId": "", "uid": "",
		"hull": hull_id, "name": "%s wreck" % str(spec.get("name", hull_id)),
		"team": "", "friendly": false, "x": xy[0], "y": xy[1],
		"battleX": 0.0, "battleY": 0.0, "cause": "stranded",
		"day": _num(state.get("day", 0.0)),
		"stores": _clean_amounts(stores),
		"components": _components_for(spec, SITE_FRACTION),
		"sourceLoadout":Refits.defaults(spec),
		"status": STATUS_UNCLAIMED, "claimedMode": "", "towedBoatUid": "", "hullStripped":false,
	}
	state["wrecks"].append(wreck)
	state.wreckSeededSources[source]=true
	_prune(state)
	return wreck.duplicate(true)




# Unclaimed wrecks within radius of a chart position, nearest first. Copies
# carry an extra "distance" field for UI sorting; stored records do not.
static func nearby(state: Dictionary, position, radius: float = 180.0) -> Array:
	ensure(state)
	var xy := _position_xy(position)
	if xy.size() != 2 or not _is_num(radius) or float(radius) < 0.0:
		return []
	var out: Array = []
	for wreck in state["wrecks"]:
		if str(wreck.get("status", "")) != STATUS_UNCLAIMED:
			continue
		var dx: float=float(wreck["x"])-float(xy[0])
		var dy: float=float(wreck["y"])-float(xy[1])
		var dist: float=sqrt(dx*dx+dy*dy)
		if dist <= float(radius):
			var copy: Dictionary = wreck.duplicate(true)
			copy["distance"] = _round2(dist)
			out.append(copy)
	out.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]))
	return out


static func _strip_items(wreck: Dictionary) -> Dictionary:
	var items := {}
	for source in [wreck.get("stores", {}), wreck.get("components", {})]:
		if source is Dictionary:
			for good in source:
				items[str(good)]=_num(items.get(str(good),0.0))+maxf(0.0,_num(source[good]))
	for good in items.keys():
		if float(items[good]) <= 0.0:
			items.erase(good)
	return items


static func _free_capacity(core) -> float:
	if core != null and core.has_method("capacity") and core.has_method("cargo_weight"):
		return maxf(0.0, float(core.capacity()) - float(core.cargo_weight()))
	return 0.0


# The existing campaign salvage labor formula (campaign.gd salvage_quote),
# kept identical so v0.010 prices match the proven v0.007 recovery:
# ordinary tug labor at the 100 coins/sailor-day wage scaled by hull size,
# one engineer day at the goods.gd engineer wage, plus a 10% company fee.
static func _tow_fees(spec: Dictionary) -> Dictionary:
	var size := clampf(_num(spec.get("size", 14.0), 14.0), 8.0, 48.0)
	var ordinary := ceili(size / 14.0 * 3.0 * float(Goods.SAILOR_WAGE))
	var expert := int(Goods.WAGES.get("engineer", 200))
	var fee := ceili(float(ordinary + expert) * 0.10)
	return {"ordinary": ordinary, "expert": expert, "fee": fee, "total": ordinary + expert + fee}


# Repair still owed after a tow, in existing damage.gd terms: restoring the
# missing 65% of hull points at hullSupplyPerHp supply kits per hp. This is a
# finite liability estimate for harbor repair, never charged here.
static func _repair_liability(spec: Dictionary) -> Dictionary:
	var max_hp := maxf(1.0, _num(spec.get("hp", 100.0), 100.0))
	var missing := max_hp * (1.0 - TOW_HP_FRACTION)
	var supplies := missing * float(Damage.CONSTANTS.get("hullSupplyPerHp", 0.35))
	return {"missingHp": _round2(missing), "supplies": _round2(supplies)}


# Read-only quote for both modes. Never mutates cargo, coins, fleet or the
# wreck beyond ensure() normalization.
static func quote(core, wreck_id: String, mode) -> Dictionary:
	var key := str(mode)
	var base := {"ok": false, "wreckId": wreck_id, "mode": key, "message": ""}
	if core == null or not (core.get("state") is Dictionary):
		base["message"] = "No campaign state."
		return base
	var state: Dictionary = core.state
	var wreck := find_wreck(state, wreck_id)
	if wreck.is_empty():
		base["message"] = "No such wreck."
		return base
	base["hull"] = str(wreck["hull"])
	base["wreckName"] = str(wreck["name"])
	base["status"] = str(wreck["status"])
	if str(wreck["status"]) != STATUS_UNCLAIMED:
		base["message"] = "Already %s; a wreck settles once." % str(wreck["status"])
		return base
	if key == MODE_STRIP:
		var items := _strip_items(wreck)
		var weight := _goods_weight(items)
		var free := _free_capacity(core)
		base.merge({"items": items, "weight": weight, "freeCapacity": _round2(free), "coins": 0}, true)
		if items.is_empty():
			base["message"] = "Nothing recoverable remains aboard."
		elif weight > free:
			base["message"] = "Stripping needs %.1f hold space; %.1f free." % [weight, free]
		else:
			base["ok"] = true
			base["message"] = "Strip %d lots (%.1f hold space)." % [items.size(), weight]
		return base
	if key == MODE_TOW:
		if wreck.get("hullStripped",false):
			base.message="Structural parts have already been removed; only further stripping is possible."
			return base
		var spec: Dictionary = core.hull(str(wreck["hull"])) if core.has_method("hull") else {}
		if spec.is_empty():
			base["message"] = "Unknown hull design; cannot tow."
			return base
		var fees := _tow_fees(spec)
		var harbor: Dictionary = core.port(str(state.get("lastPort", ""))) if core.has_method("port") else {}
		base.merge({"ordinary": int(fees["ordinary"]), "expert": int(fees["expert"]),
			"fee": int(fees["fee"]), "total": int(fees["total"]), "coins": int(fees["total"]),
			"repairLiability": _repair_liability(spec), "towSpeedFactor": TOW_SPEED_FACTOR,
			"hpFraction": TOW_HP_FRACTION, "harbor": str(harbor.get("id", ""))}, true)
		if harbor.is_empty():
			base["message"] = "No home harbor to pay the tug and inspector."
		elif float(harbor.get("availableWorkers",0))<3 or float(harbor.get("availableSpecialists",harbor.get("specialistWorkers",0)))<1:
			base.message="The last harbor lacks an available tug crew or inspection specialist today."
		elif core.has_method("can_add_boat") and not bool(core.can_add_boat(spec)):
			base["message"] = str(core.points_refusal(spec)) if core.has_method("points_refusal") else "No roster room for another hull."
		elif int(state.get("coins", 0)) < int(fees["total"]):
			base["message"] = "Recovery needs %d coins for tug labor, inspection and the company fee." % int(fees["total"])
		else:
			base["ok"] = true
			base["message"] = "Tow to harbor for %d coins; hull returns damaged, uncrewed and empty." % int(fees["total"])
		return base
	base["message"] = "Unknown recovery mode."
	return base


# Settles one wreck. Returns the refused quote (with ok=false) and changes
# nothing when ineligible: capacity, roster, harbor and coin checks all run
# inside quote() before any cargo, purse or fleet write below.
static func recover(core, wreck_id: String, mode) -> Dictionary:
	var q := quote(core, wreck_id, mode)
	if not bool(q["ok"]):
		return q
	var state: Dictionary = core.state
	var wreck := find_wreck(state, wreck_id)
	if str(q["mode"]) == MODE_STRIP:
		var items: Dictionary = q["items"]
		var cargo: Dictionary = state.get("cargo", {}) if state.get("cargo") is Dictionary else {}
		for good in items:
			cargo[str(good)]=maxf(0.0,_num(cargo.get(str(good),0.0)))+float(items[good])
		state["cargo"] = cargo
		wreck["stores"] = {}
		wreck["components"] = {}
		wreck["status"] = STATUS_STRIPPED
		wreck["claimedMode"] = MODE_STRIP
		var out := q.duplicate(true)
		out["message"] = "Stripped %s into the hold." % str(wreck["name"])
		return out
	# Tow: pay the last harbor's existing purses exactly as the proven
	# campaign salvage_boat does, then add the physical hull back damaged.
	var harbor: Dictionary = core.port(str(state.get("lastPort", "")))
	var ledger: Array = state.get("moneyLog", []) if state.get("moneyLog") is Array else []
	Money.move(state, "coins", harbor, "householdPurse", int(q["ordinary"]), "Salvage tug crew wages", ledger)
	Money.move(state, "coins", harbor, "expertPurse", int(q["expert"]), "Salvage engineer inspection", ledger)
	Money.move(state, "coins", harbor, "cash", int(q["fee"]), "Salvage company fee", ledger)
	harbor.availableWorkers=maxi(0,int(harbor.get("availableWorkers",0))-3)
	harbor.availableSpecialists=maxi(0,int(harbor.get("availableSpecialists",harbor.get("specialistWorkers",0)))-1)
	harbor.workers=int(harbor.get("workers",0))+3
	state["moneyLog"] = ledger
	var spec: Dictionary = core.hull(str(wreck["hull"]))
	var boat: Dictionary = core.add_boat(spec, 0)
	var old_loadout: Dictionary=wreck.get("sourceLoadout",{})
	if not old_loadout.is_empty():
		boat.loadout=old_loadout.duplicate(true)
		core.fit_boat(boat,true)
	boat["hp"] = float(boat.get("maxHp", 1.0)) * TOW_HP_FRACTION
	boat["crew"] = 0.0
	boat["fuel"] = 0.0
	boat["ammo"] = 0.0
	boat["supplies"] = 0.0
	boat["mothballed"] = true
	boat["towed"] = true
	boat["towSpeedFactor"] = TOW_SPEED_FACTOR
	boat["salvageWreckId"] = wreck_id
	boat["needsHarborRepair"] = true
	boat["repairLiability"] = (q["repairLiability"] as Dictionary).duplicate(true)
	wreck["stores"] = {}
	wreck["components"] = {}
	wreck["status"] = STATUS_TOWED
	wreck["claimedMode"] = MODE_TOW
	wreck["towedBoatUid"] = str(boat.get("uid", ""))
	var out := q.duplicate(true)
	out["boatUid"] = str(boat.get("uid", ""))
	out["message"] = "%s towed in. Hire a crew, repair it at a harbor and buy stores." % str(boat.get("name", wreck["name"]))
	return out

static func strip_good(core,wreck_id: String,good: String,qty: float) -> Dictionary:
	var wreck: Dictionary=find_wreck(core.state,wreck_id)
	if wreck.is_empty() or wreck.status!=STATUS_UNCLAIMED or not Goods.ITEMS.has(good) or not is_finite(qty) or qty<=0:return {"ok":false,"message":"No recoverable lot of that kind."}
	var amount: float=minf(qty,float(_strip_items(wreck).get(good,0)))
	if amount<=0 or amount*float(Goods.ITEMS[good].weight)>_free_capacity(core)+0.00001:return {"ok":false,"message":"Choose a smaller lot; the traveling hold has insufficient space."}
	var left: float=amount
	for key in ["stores","components"]:
		var take: float=minf(left,float(wreck[key].get(good,0)))
		wreck[key][good]=maxf(0,float(wreck[key].get(good,0))-take)
		left-=take
	core.state.cargo[good]=float(core.state.cargo.get(good,0))+amount
	if good not in ["fuel","ammo","supplies","food"]:wreck.hullStripped=true
	if _strip_items(wreck).is_empty():wreck.status=STATUS_STRIPPED;wreck.claimedMode=MODE_STRIP
	return {"ok":true,"message":"Recovered %.2f %s from %s."%[amount,good,wreck.name],"weight":amount*float(Goods.ITEMS[good].weight)}
