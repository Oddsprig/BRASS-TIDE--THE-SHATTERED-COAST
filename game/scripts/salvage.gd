extends RefCounted
## v0.010 persistent individual wrecks and salvage recovery.
## Pure data over campaign state; root owns UI, chart markers, travel-speed
## integration and harbor repair/crew flows. Wrecks live in state["wrecks"]
## (Array, bounded) with a monotonic state["wreckSeq"] id counter. Every
## record is plain JSON: no object references, no engine types.
## A wreck settles exactly once: stripped XOR towed, never both, never twice.
## sourceModuleCondition, when present, is the only active copy of that hull's parts.
## An active tow stages that birth before payment.
## A legacy or site tow stages disabled gear and its uid before payment. add_boat only publishes.
## A tow reads the requested wreck's raw status and loadout before ensure.
## An accepted sunk hull keeps equipmentRetiredTo set to that wreck id. The marker
## stays after transfer and after wreck pruning. It is not a second owner. Save must
## retain it with the hull and must not reseed a hull that still has it.

const Goods = preload("res://scripts/goods.gd")
const Money = preload("res://scripts/money.gd")
const Construction = preload("res://scripts/construction.gd")
const Damage = preload("res://scripts/damage.gd")
const Refits=preload("res://scripts/refit.gd")
const Recovery=preload("res://scripts/equipment_recovery.gd")
const Tow=preload("res://scripts/equipment_tow.gd")
const Condition=preload("res://scripts/equipment_condition.gd")
const Records=preload("res://scripts/equipment_records.gd")
const Preflight=preload("res://scripts/equipment_campaign.gd")
const Expedition=preload("res://scripts/expedition.gd")
const Manifest=preload("res://scripts/hold_manifest.gd")
const WorldIdentity069=preload("res://scripts/ocean_travel066.gd")

const MAX_WRECKS := 128
const MODE_STRIP := "strip"
const MODE_TOW := "tow"
const MODE_GEAR := "gear"
const STATUS_UNCLAIMED := "unclaimed"
const STATUS_STRIPPED := "stripped"
const STATUS_TOWED := "towed"
const TOW_HP_FRACTION := 0.35
# Root multiplies traveling fleet speed by the smallest towSpeedFactor among
# towed boats it is moving; the field is stamped on the recovered boat.
const TOW_SPEED_FACTOR := 0.55
const _COIN_LIMIT := 9223372036854775807
# Site-seeded wrecks use one fixed recoverable fraction: no rolls, no rerolls.
const SITE_FRACTION := 0.30
const EXPEDITION067_SOURCE := "site:glasswind_keys:abandoned_cache067"
const EXPEDITION067_STORES := {"engines":1,"copper":8,"supplies":12,"timber":16}
const EXPEDITION067_SITES := ["glasswind_west_marker","glasswind_crown_log","glasswind_south_wreck"]

## Read-only campaign facade for quotes. No Campaign/world constructor, state
## swap, economy tick or migration is needed to inspect an ordinary strip/tow.
class QuoteView extends RefCounted:
	var state: Dictionary
	var data: Dictionary
	var source
	func _init(core):
		source=core;data=core.data;state=core.state.duplicate(true)
		core.Preflight._clone_boats(core.state,state)
	func hull(id: String) -> Dictionary:
		return source.hull(id)
	func port(id: String) -> Dictionary:
		for p in state.get("ports",[]):
			if str(p.get("id",""))==id:return p
		return {}
	func capacity() -> float:
		return source.Expedition.capacity(state)
	func cargo_weight() -> float:
		return source.Expedition.cargo_weight(state)
	func can_add_boat(spec: Dictionary) -> bool:
		return source.can_add_boat(spec)
	func points_refusal(spec: Dictionary) -> String:
		return source.points_refusal(spec)


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


## Attachment metadata only. Copies never become crew, staff, money or parts.
static func _retain_service(source: Dictionary,target: Dictionary) -> void:
	var service: Dictionary={}
	var raw_service: Dictionary=source.get("service",{}) if source.get("service") is Dictionary else {}
	for key in ["battles","wins","rescues","trades","surveys"]:
		if raw_service.has(key):service[key]=maxi(0,int(_num(raw_service[key])))
	var history: Array=[]
	for row in source.get("serviceHistory",[]) if source.get("serviceHistory") is Array else []:
		if not row is Dictionary:continue
		history.append({"day":_num(row.get("day")),"event":str(row.get("event","")),"detail":str(row.get("detail",""))})
		while history.size()>12:history.pop_front()
	target.service=service
	target.serviceHistory=history


## Missing legacy metadata belongs to home. Invalid present metadata stays
## explicitly invalid, so a lookup cannot turn it into recoverable home cargo.
static func _world_metadata064(record: Dictionary) -> Dictionary:
	if not record.has("world064"):return {"schema":1,"layer":"home","regionId":"shatter_coast"}
	var identity=record.get("world064")
	# Syntax is accepted here; SaveValidation checks actual context membership and
	# water coordinates before publication. No generated wreck becomes HOME.
	if WorldIdentity069.same_world(identity,identity):return identity.duplicate(true)
	return {"schema":0,"layer":"invalid","regionId":"invalid"}

static func _sanitize_wreck(raw) -> Dictionary:
	if not (raw is Dictionary) or str(raw.get("id", "")).is_empty():
		return {}
	var status := str(raw.get("status", STATUS_UNCLAIMED))
	if not status in [STATUS_UNCLAIMED, STATUS_STRIPPED, STATUS_TOWED]:
		status = STATUS_UNCLAIMED
	var wreck := {
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
	if raw.has("world064"):wreck.world064=_world_metadata064(raw)
	Recovery.retain(raw, wreck)
	_retain_service(raw,wreck)
	return wreck


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
	for wreck in state.get("wrecks",[]):
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


# Plans one sunk hull without writing it. prepare() absorbs a lower engine scalar
# on its own detached copy. The caller's hull is unchanged until _apply_equipment.
# A hull already marked equipmentRetiredTo is not snapshotted again.
static func _plan_equipment(state: Dictionary, ship: Dictionary, base: Dictionary, reserved: Dictionary) -> Dictionary:
	if not ship is Dictionary:
		return {"ok": false, "message": "The hull record is missing."}
	if ship.has("equipmentRetiredTo"):
		if ship.has("moduleCondition"):
			return {"ok": false, "message": "A retired hull still carries equipment."}
		return {"ok": true, "mode": "skip"}
	if not ship.has("moduleCondition"):
		return {"ok": true, "mode": "legacy"}
	var known: Dictionary = Recovery.registry(state, "", ship)
	if not known.ok:
		return {"ok": false, "message": str(known.get("message", "This equipment is already recorded on another hull."))}
	if ship.moduleCondition is Dictionary and ship.moduleCondition.get("items") is Dictionary:
		var owned: Dictionary = {}
		for uid in known.get("uids", []):
			owned[str(uid)] = true
		for part_id in ship.moduleCondition.items.keys():
			if owned.has(str(part_id)):
				return {"ok": false, "message": "Two hulls share one physical part."}
	var captured: Dictionary = Recovery.prepare(ship, base, known.get("uids", []))
	if bool(captured.get("accepted", false)):
		for uid in captured.get("itemUids", []):
			if reserved.has(str(uid)):
				return {"ok": false, "message": "Two hulls share one physical part."}
		return {"ok": true, "mode": "accepted", "captured": captured}
	var raw = captured.get("raw", ship.get("moduleCondition", null))
	return {"ok": true, "mode": "refused", "raw": raw}


static func _apply_equipment(ship: Dictionary, wreck: Dictionary, plan: Dictionary) -> void:
	if str(plan.get("mode", "")) == "accepted":
		var captured: Dictionary = plan.captured
		wreck.sourceModuleCondition = captured.condition
		wreck.equipmentCustody = "wreck"
		wreck.retiredSourceUid = str(ship.get("uid", ""))
		ship.equipmentRetiredTo = str(wreck.get("id", ""))
		ship.erase("moduleCondition")
		return
	if str(plan.get("mode", "")) != "refused":
		return
	wreck.equipmentCustody = "refused"
	var raw = plan.get("raw", null)
	if raw is Dictionary or raw is Array:
		wreck.sourceModuleCondition = raw.duplicate(true)
	else:
		wreck.sourceModuleCondition = raw


static func _repair_from_max(max_hp: float) -> Dictionary:
	var missing := max_hp * (1.0 - TOW_HP_FRACTION)
	var supplies := missing * float(Damage.CONSTANTS.get("hullSupplyPerHp", 0.35))
	return {"missingHp": _round2(missing), "supplies": _round2(supplies)}


# Records every actually destroyed boat in a finished battle, friendly and
# enemy alike, from the battle's own ships (sunk == true) enriched with its
# combat_events wreck records (cause). Live, retreated and reserve boats are
# never recorded. Chart position is the campaign position where the battle
# happened (state.position); battle-local coordinates are kept separately.
# Idempotent per source_id: re-recording the same battle returns the existing
# records and adds nothing. Returns copies of the records for that source.
static func record_battle(core, battle: Dictionary, source_id: String) -> Array:
	if source_id==EXPEDITION067_SOURCE:return []
	if core == null or not (core.get("state") is Dictionary):
		return []
	var state: Dictionary = core.state
	ensure(state)
	var existing := _by_source(state, source_id)
	if not existing.is_empty():
		return existing.duplicate(true)
	# Selected dismantling permanently retired this encounter's snapshot. Keep
	# its source tombstone effective even after bounded wreck history is pruned.
	if state.wreckSeededSources.has(source_id):return []
	var causes := {}
	for record in battle.get("wrecks", []) if battle.get("wrecks") is Array else []:
		if record is Dictionary:
			causes[str(record.get("id", ""))] = str(record.get("cause", ""))
			causes[str(record.get("uid", ""))] = str(record.get("cause", ""))
	var xy := _position_xy(battle.get("chartPosition",state.get("position", {})))
	var chart_x: float=float(xy[0]) if xy.size()==2 else 0.0
	var chart_y: float=float(xy[1]) if xy.size()==2 else 0.0
	# Autonomous home losses carry chartPosition; player/prize losses supply
	# their explicit active identity. Never borrow the offshore captain's layer
	# for an unrelated home NPC sinking.
	var provenance: Dictionary=_world_metadata064(battle)
	var created: Array = []
	var seen_ships := {}
	var pending: Array = []
	var reserved: Dictionary = {}
	for ship in battle.get("ships", []) if battle.get("ships") is Array else []:
		if not (ship is Dictionary) or not bool(ship.get("sunk", false)):
			continue
		var ship_key := str(ship.get("uid", ship.get("id", "")))
		if ship_key.is_empty() or seen_ships.has(ship_key):
			continue
		seen_ships[ship_key] = true
		var spec: Dictionary = ship.get("spec", {}) if ship.get("spec") is Dictionary else {}
		var hull_id := str(ship.get("type", spec.get("id", "")))
		var base_hull: Dictionary = spec
		if core.has_method("hull"):
			var looked: Dictionary = core.hull(hull_id)
			if not looked.is_empty():
				base_hull = looked
		var plan: Dictionary = _plan_equipment(state, ship, base_hull, reserved)
		if not bool(plan.get("ok", false)):
			return []
		if str(plan.get("mode", "")) == "accepted":
			for uid in plan.captured.get("itemUids", []):
				reserved[str(uid)] = true
		pending.append({"ship": ship, "spec": spec, "hull": hull_id, "key": ship_key, "plan": plan})
	for item in pending:
		if str(item.plan.get("mode", "")) == "skip":
			continue
		var sunk: Dictionary = item.ship
		var sunk_spec: Dictionary = item.spec
		var wreck := {
			"id": _next_id(state), "sourceId": source_id,
			"shipId": str(sunk.get("id", "")), "uid": str(sunk.get("uid", sunk.get("id", ""))),
			"hull": str(item.hull), "name": str(sunk.get("name", sunk_spec.get("name", "Wreck"))),
			"team": str(sunk.get("team", "")), "friendly": str(sunk.get("team", "")) == "player",
			"x": chart_x, "y": chart_y,
			"battleX": _num(sunk.get("x", 0.0)), "battleY": _num(sunk.get("y", 0.0)),
			"cause": str(causes.get(str(sunk.get("id", "")), causes.get(str(item.key), ""))),
			"day": _num(state.get("day", 0.0)),
			"stores": _stores_for(sunk),
			"components": _components_for(sunk_spec, _recoverable_fraction(sunk)),
			"sourceLoadout":sunk.get("loadout",Refits.defaults(sunk_spec)).duplicate(true),
			"status": STATUS_UNCLAIMED, "claimedMode": "", "towedBoatUid": "", "hullStripped":false,
		}
		if battle.has("world064"):wreck.world064=provenance.duplicate(true)
		_apply_equipment(sunk, wreck, item.plan)
		_retain_service(sunk,wreck)
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
	# This named historical source has one fixed cargo-only birth below. Neither
	# a raw generic seeder nor a changed caller manifest may manufacture it.
	if source_id==EXPEDITION067_SOURCE or site.get("regionId")=="glasswind_keys" or str(site.get("id","")) in EXPEDITION067_SITES:return {}
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


## Raw, read-only finite source/tombstone gate, used before save normalization.
static func validate_expedition067(state: Dictionary) -> String:
	var tombstones=state.get("wreckSeededSources",{})
	if not tombstones is Dictionary:return "Invalid wreck provenance ledger."
	if tombstones.has(EXPEDITION067_SOURCE) and (not tombstones[EXPEDITION067_SOURCE] is bool or tombstones[EXPEDITION067_SOURCE]!=true):return "Invalid expedition cache tombstone."
	if not state.get("wrecks",[]) is Array:return "Invalid wreck collection."
	var count: int=0
	for wreck in state.get("wrecks",[]):
		if not wreck is Dictionary or wreck.get("sourceId")!=EXPEDITION067_SOURCE:continue
		count+=1
		if count>1 or not tombstones.has(EXPEDITION067_SOURCE):return "Expedition cache provenance is duplicated or missing."
		var identity= wreck.get("world064")
		if not identity is Dictionary or identity.size()!=3 or not _is_num(identity.get("schema")) or identity.schema!=1 or identity.get("layer")!="local" or identity.get("regionId")!="glasswind_keys":return "Invalid expedition cache chart provenance."
		if not _is_num(wreck.get("x")) or not _is_num(wreck.get("y")) or float(wreck.x)!=1820.0 or float(wreck.y)!=1640.0:return "Invalid expedition cache anchor."
		if wreck.get("hull")!="tideledger_coaster" or wreck.get("name")!="Collapsed Supply Coaster" or wreck.get("hullStripped")!=true:return "Invalid cargo-only cache identity."
		if not wreck.get("hullStripped") is bool or str(wreck.get("uid",""))!="" or str(wreck.get("shipId",""))!="" or str(wreck.get("towedBoatUid",""))!="":return "An abandoned cargo cache cannot own a living hull."
		if wreck.has("sourceModuleCondition") or not wreck.get("components") is Dictionary or not wreck.components.is_empty():return "The expedition cache cannot create physical fittings or derived material."
		if not wreck.get("sourceLoadout",{}) is Dictionary or not wreck.get("sourceLoadout",{}).is_empty():return "The expedition cache has no recoverable equipment."
		if not wreck.get("stores") is Dictionary:return "Invalid finite cache stores."
		for good in wreck.stores:
			if not EXPEDITION067_STORES.has(good) or not _is_num(wreck.stores[good]) or float(wreck.stores[good])<0 or float(wreck.stores[good])>float(EXPEDITION067_STORES[good]):return "Expedition cache stores exceed their one authored source."
		var remaining: bool=not _strip_items(wreck).is_empty()
		if wreck.get("status")!=(STATUS_UNCLAIMED if remaining else STATUS_STRIPPED):return "Expedition cache depletion does not match its finite stores."
		var ex=state.get("exploration",{})
		if not ex is Dictionary or not ex.get("sites") is Dictionary:return "Expedition cache needs its earned survey records."
		for id in EXPEDITION067_SITES:
			var progress=ex.sites.get(id,{})
			if not progress is Dictionary or not _is_num(progress.get("level")) or progress.level!=3 or not progress.get("rewarded") is bool or progress.rewarded!=true:return "Expedition cache needs three completed surveys."
	return ""

## Historical abandoned stores, never a new canonical hull/crew/equipment owner.
## Stage and validate the fixed64-weight pile before publishing one source birth.
static func seed_expedition067(core,site: Dictionary) -> Dictionary:
	if core==null or not core.get("state") is Dictionary:return {}
	var state: Dictionary=core.state
	if not validate_expedition067(state).is_empty():return {}
	# Refuse raw identity/inventory collisions before legacy ensure can drop or
	# normalize them. A failed reveal publishes neither cleanup nor a new pile.
	var ids: Dictionary={}
	for row in state.get("wrecks",[]):
		if not row is Dictionary or not row.get("id") is String or row.id.is_empty() or ids.has(row.id):return {}
		ids[row.id]=true
		if row.has("status") and row.status not in [STATUS_UNCLAIMED,STATUS_STRIPPED,STATUS_TOWED]:return {}
		for key in ["stores","components"]:
			if not row.get(key,{}) is Dictionary:return {}
			for good in row.get(key,{}):
				if not Goods.ITEMS.has(good) or not _is_num(row[key][good]) or float(row[key][good])<0:return {}
	if state.has("wreckSeq") and (not _is_num(state.wreckSeq) or float(state.wreckSeq)<0 or floorf(float(state.wreckSeq))!=float(state.wreckSeq)):return {}
	var current=state.get("world064")
	if not current is Dictionary or current.size()!=3 or not _is_num(current.get("schema")) or current.schema!=1 or current.get("layer")!="local" or current.get("regionId")!="glasswind_keys":return {}
	if site.get("id")!="glasswind_south_wreck" or site.get("regionId")!="glasswind_keys" or not _is_num(site.get("x")) or not _is_num(site.get("y")) or float(site.x)!=1820.0 or float(site.y)!=1640.0:return {}
	var ex=state.get("exploration",{})
	if not ex is Dictionary or not ex.get("sites") is Dictionary:return {}
	for id in EXPEDITION067_SITES:
		var record=ex.sites.get(id,{})
		if not record is Dictionary or not _is_num(record.get("level")) or record.level!=3 or record.get("rewarded")!=true:return {}
	var existing: Array=_by_source(state,EXPEDITION067_SOURCE)
	if not existing.is_empty():return existing[0].duplicate(true)
	if state.get("wreckSeededSources",{}).has(EXPEDITION067_SOURCE):return {}
	if core.hull("tideledger_coaster").is_empty():return {}
	var staged: Dictionary=state.duplicate(true)
	ensure(staged)
	var wreck: Dictionary={"id":_next_id(staged),"sourceId":EXPEDITION067_SOURCE,"shipId":"","uid":"",
		"hull":"tideledger_coaster","name":"Collapsed Supply Coaster","team":"","friendly":false,
		"world064":{"schema":1,"layer":"local","regionId":"glasswind_keys"},"x":1820.0,"y":1640.0,
		"battleX":0.0,"battleY":0.0,"cause":"abandoned cargo cache","day":_num(state.get("day",0)),
		"stores":EXPEDITION067_STORES.duplicate(true),"components":{},"sourceLoadout":{},
		"status":STATUS_UNCLAIMED,"claimedMode":"","towedBoatUid":"","hullStripped":true}
	if staged.wrecks.any(func(row):return row.get("id")==wreck.id):return {}
	staged.wrecks.append(wreck)
	staged.wreckSeededSources[EXPEDITION067_SOURCE]=true
	_prune(staged)
	if not validate_expedition067(staged).is_empty() or not is_equal_approx(_goods_weight(wreck.stores),64.0):return {}
	state.wrecks=staged.wrecks;state.wreckSeq=staged.wreckSeq;state.wreckSeededSources=staged.wreckSeededSources
	return wreck.duplicate(true)


static func _is_expedition067(state: Dictionary,id: String) -> bool:
	for row in state.get("wrecks",[]):
		if row is Dictionary and row.get("id")==id and row.get("sourceId")==EXPEDITION067_SOURCE:return true
	return false



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
	return _repair_from_max(maxf(1.0, _num(spec.get("hp", 100.0), 100.0)))


# Read-only. Explicit corrupt status or a non-dictionary loadout is refused
# before ensure can rewrite the requested wreck. Missing and empty stay put.
static func _raw_tow_preflight(state: Dictionary, wreck_id: String) -> String:
	var rows = state.get("wrecks", [])
	if not rows is Array or wreck_id.is_empty():
		return ""
	var allowed: Array = [STATUS_UNCLAIMED, STATUS_STRIPPED, STATUS_TOWED]
	for raw in rows:
		if not raw is Dictionary or str(raw.get("id", "")) != wreck_id:
			continue
		if raw.has("status") and not allowed.has(str(raw.get("status", ""))):
			return "Wreck status is not a salvage settlement."
		if raw.has("sourceLoadout") and not raw.get("sourceLoadout") is Dictionary:
			return "Wreck loadout is unreadable."
	return ""


# Read-only quote for both modes. Never mutates cargo, coins, fleet or the
# wreck beyond ensure() normalization. Tow preflight runs before that.
static func quote(core, wreck_id: String, mode, request: Dictionary={}) -> Dictionary:
	var key := str(mode)
	if core!=null and core.get("state") is Dictionary and _is_expedition067(core.state,wreck_id):
		return {"ok":false,"message":"This cargo cache requires an explicit paid campaign lot quote.","wreckId":wreck_id,"mode":key,"cargoOnly":true}
	if key==MODE_GEAR:return _gear_stage(core,wreck_id,request).quote
	var base := {"ok": false, "wreckId": wreck_id, "mode": key, "message": ""}
	if core == null or not (core.get("state") is Dictionary):
		base["message"] = "No campaign state."
		return base
	var state: Dictionary = core.state
	if key == MODE_TOW:
		var raw_problem := _raw_tow_preflight(state, str(wreck_id))
		if not raw_problem.is_empty():
			base["message"] = raw_problem
			return base
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
	var blocked := Recovery.refusal(wreck)
	if not blocked.is_empty():
		base["message"] = blocked
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
		var staged := _tow_stage(core, state, wreck)
		if staged.has("fees"):
			var fees: Dictionary = staged.fees
			var harbor: Dictionary = staged.harbor if staged.get("harbor", {}) is Dictionary else {}
			var priced: Dictionary = staged.contract if staged.get("contract") is Dictionary else {}
			var fitted_max := float(priced.get("maxHp", 0.0))
			var recovered := float(priced.get("hullHp", 0.0))
			base.merge({"ordinary": int(fees["ordinary"]), "expert": int(fees["expert"]),
				"fee": int(fees["fee"]), "total": int(fees["total"]), "coins": int(fees["total"]),
				"repairLiability": _repair_from_max(fitted_max), "towSpeedFactor": TOW_SPEED_FACTOR,
				"hpFraction": TOW_HP_FRACTION, "recoveredHp": recovered,
				"fittedMaxHp": fitted_max, "harbor": str(harbor.get("id", ""))}, true)
		base["message"] = str(staged.get("message", ""))
		base["ok"] = bool(staged.get("ok", false))
		return base
	base["message"] = "Unknown recovery mode."
	return base


# Settles one wreck. Returns the refused quote (with ok=false) and changes
# nothing when ineligible. Tow stages every fallible check again and only then
# pays, books workers, and adds the hull. It does not return failure after that.
static func recover(core, wreck_id: String, mode, request: Dictionary={}) -> Dictionary:
	if core!=null and core.get("state") is Dictionary and _is_expedition067(core.state,wreck_id):return {"ok":false,"message":"Use the paid campaign action with an explicit finite cargo lot."}
	# Selected equipment is inseparable from Campaign's paid work transaction.
	# Do not expose a lower-level path that publishes exact parts for free.
	if str(mode)==MODE_GEAR:
		if core==null or not core.has_method("recover_wreck"):return {"ok":false,"message":"Selected recovery requires the paid campaign action."}
		return core.recover_wreck(wreck_id,MODE_GEAR,"",0.0,request)
	var q := quote(core, wreck_id, mode,request)
	if not bool(q["ok"]):
		return q
	var state: Dictionary = core.state
	var wreck := find_wreck(state, wreck_id)
	if str(q["mode"]) == MODE_TOW:
		var staged := _tow_stage(core, state, wreck)
		if not bool(staged.get("ok", false)):
			q["ok"] = false
			q["message"] = str(staged.get("message", "This wreck's equipment record cannot be read, so nothing was taken."))
			return q
		return _publish_tow(core, state, wreck, staged, q)
	if str(q["mode"]) == MODE_STRIP:
		var items: Dictionary = q["items"]
		var cargo: Dictionary = state.get("cargo", {}) if state.get("cargo") is Dictionary else {}
		for good in items:
			cargo[str(good)]=maxf(0.0,_num(cargo.get(str(good),0.0)))+float(items[good])
		state["cargo"] = cargo
		wreck["stores"] = {}
		wreck["components"] = {}
		if Recovery.is_active(wreck):
			Recovery.release(wreck, "retired")
		wreck["status"] = STATUS_STRIPPED
		wreck["claimedMode"] = MODE_STRIP
		var out := q.duplicate(true)
		out["message"] = "Stripped %s into the hold." % str(wreck["name"])
		return out
	q["ok"] = false
	q["message"] = "Unknown recovery mode."
	return q


static func _whole_nonneg(value) -> bool:
	if value is bool:
		return false
	if value is int:
		return value >= 0
	if value is float and is_finite(value) and value >= 0.0 and value <= float(_COIN_LIMIT) and floor(value) == value:
		return true
	return false


## Read-only validation of the purses actually included by Money.total.
## Missing moneyLog/coinSupply refuses; supported saved careers contain both.
static func _coin_whole(value) -> bool:
	return _whole_nonneg(value) and value <= 9007199254740991

static func _tow_ledger(state: Dictionary) -> bool:
	if not _coin_whole(state.get("coinSupply")) or not state.get("moneyLog") is Array:
		return false
	for entry in state.moneyLog:
		if not entry is Dictionary:
			return false
	var holders: Array = [{"record": state, "keys": ["coins", "crewPurse"]}]
	if not state.get("ports", []) is Array:
		return false
	for port in state.get("ports", []):
		if not port is Dictionary or not port.get("training", {}) is Dictionary:
			return false
		holders.append({"record": port, "keys": ["cash", "householdPurse", "expertPurse", "governmentPurse"]})
		var training: Dictionary = port.get("training", {})
		for raw in [training.get("jobs", []), port.get("buildQueue", [])]:
			if not raw is Array:
				return false
			for row in raw:
				if not row is Dictionary:
					return false
				holders.append({"record": row, "keys": ["escrow"]})
	for entry in [["fleetOwners", ["coins", "crewPurse"]], ["voyageJobs", ["escrow"]], ["specialists", ["coins"]], ["yardProjects", ["escrow"]], ["businesses", ["coins"]]]:
		var rows = state.get(entry[0], [])
		if not rows is Array:
			return false
		for row in rows:
			if not row is Dictionary:
				return false
			holders.append({"record": row, "keys": entry[1]})
	var contract = state.get("activeContract", {})
	var crises = state.get("regionalCrises", {})
	if not contract is Dictionary or not crises is Dictionary or not crises.get("jobs", []) is Array:
		return false
	holders.append({"record": contract, "keys": ["escrow"]})
	holders.append({"record": crises, "keys": ["lostPurse"]})
	for cohort in crises.get("jobs", []):
		if not cohort is Dictionary:
			return false
		holders.append({"record": cohort, "keys": ["escrow", "householdPurse", "expertPurse"]})
	var total: int = 0
	for holder in holders:
		for key in holder["keys"]:
			var value = holder.record.get(key, 0)
			if not _coin_whole(value) or int(value) > 9007199254740991 - total:
				return false
			total += int(value)
	# Also bind to the actual accounting API, not only this shape preflight.
	return total == int(state.coinSupply) and Money.total(state) == total


static func _fits(left: int, right: int) -> bool:
	if left < 0 or right < 0:
		return false
	return left <= _COIN_LIMIT - right


static func _purse_room(holder: Dictionary, key: String, amount: int) -> bool:
	if not holder.has(key):
		return _fits(0, amount)
	if not _coin_whole(holder[key]) or amount < 0:
		return false
	return int(holder[key]) <= 9007199254740991 - amount


static func _worker_count(harbor: Dictionary, key: String, fallback: String = "") -> int:
	if harbor.has(key):
		if not _whole_nonneg(harbor[key]):
			return -1
		return int(harbor[key])
	if not fallback.is_empty() and harbor.has(fallback):
		if not _whole_nonneg(harbor[fallback]):
			return -1
		return int(harbor[fallback])
	if key == "workers":
		return 0
	return -1


# Read-only. Proves hull, custody, harbor, workforce, roster, coins, purse room,
# and the detached equipment publish before any live write.
static func _tow_stage(core, state: Dictionary, wreck: Dictionary) -> Dictionary:
	if wreck.get("hullStripped", false):
		return {"ok": false, "message": "Structural parts have already been removed; only further stripping is possible."}
	var spec: Dictionary = core.hull(str(wreck.get("hull", ""))) if core != null and core.has_method("hull") else {}
	if spec.is_empty():
		return {"ok": false, "message": "Unknown hull design; cannot tow."}
	var priced: Dictionary = Tow.contract(spec, wreck.get("sourceLoadout", {}))
	if not bool(priced.get("ok", false)):
		return {"ok": false, "message": str(priced.get("message", "Preserved loadout is unreadable."))}
	var fees := _tow_fees(spec)
	var ordinary := int(fees.ordinary)
	var expert := int(fees.expert)
	var fee := int(fees.fee)
	if not _fits(ordinary, expert) or not _fits(ordinary + expert, fee):
		return {"ok": false, "message": "The harbor ledger cannot take this tow payment."}
	var total := ordinary + expert + fee
	var harbor: Dictionary = core.port(str(state.get("lastPort", ""))) if core != null and core.has_method("port") else {}
	var staged := {"ok": false, "message": "", "fees": fees, "spec": spec, "harbor": harbor, "restoring": false, "contract": priced}
	if harbor.is_empty():
		staged.message = "No home harbor to pay the tug and inspector."
		return staged
	var live_port := false
	for port in state.get("ports", []) if state.get("ports", []) is Array else []:
		if is_same(port, harbor):
			live_port = true
	if not live_port:
		staged.message = "No home harbor to pay the tug and inspector."
		return staged
	if not _tow_ledger(state):
		staged.message = "The world coin ledger or money log cannot be reconciled for this tow."
		return staged
	var workers := _worker_count(harbor, "availableWorkers")
	var specialists := _worker_count(harbor, "availableSpecialists", "specialistWorkers")
	var yard := _worker_count(harbor, "workers")
	var workforce: Dictionary = Refits._workforce(harbor)
	if workers < 3 or specialists < 1 or float(workforce.free) < 3.0 or float(workforce.freeExperts) < 1.0:
		staged.message = "The last harbor lacks an available tug crew or inspection specialist today."
		return staged
	if not _fits(yard, 3):
		staged.message = "The harbor ledger cannot take this tow payment."
		return staged
	if core.has_method("can_add_boat") and not bool(core.can_add_boat(spec)):
		staged.message = str(core.points_refusal(spec)) if core.has_method("points_refusal") else "No roster room for another hull."
		return staged
	if not _coin_whole(state.get("coins", null)) or int(state.get("coins", 0)) < total:
		staged.message = "Recovery needs %d coins for tug labor, inspection and the company fee." % total
		return staged
	if not _purse_room(harbor, "householdPurse", ordinary) or not _purse_room(harbor, "expertPurse", expert) or not _purse_room(harbor, "cash", fee):
		staged.message = "The harbor ledger cannot take this tow payment."
		return staged
	var ready: Dictionary = Tow.stage(core, state, wreck, spec)
	if not bool(ready.get("ok", false)):
		staged.message = str(ready.get("message", "This wreck's equipment record cannot be read, so nothing was taken."))
		return staged
	if not ready.get("contract") is Dictionary or not bool(ready.contract.get("ok", false)) or not ready.contract.has("hullHp") or not ready.contract.has("maxHp"):
		staged.message = str(ready.get("message", "Preserved loadout is unreadable."))
		return staged
	staged.contract = ready.contract
	staged.ok = true
	staged.restoring = bool(ready.get("restoring", false))
	staged.prepared = ready
	staged.message = "Tow to harbor for %d coins; hull returns damaged, uncrewed and empty." % total
	return staged


# Live publish. Every check in _tow_stage has already passed. No failure return.
static func _publish_tow(core, state: Dictionary, wreck: Dictionary, staged: Dictionary, q: Dictionary) -> Dictionary:
	var harbor: Dictionary = staged.harbor
	var fees: Dictionary = staged.fees
	var ledger: Array = state.get("moneyLog", []) if state.get("moneyLog", []) is Array else []
	Money.move(state, "coins", harbor, "householdPurse", int(fees.ordinary), "Salvage tug crew wages", ledger)
	Money.move(state, "coins", harbor, "expertPurse", int(fees.expert), "Salvage engineer inspection", ledger)
	Money.move(state, "coins", harbor, "cash", int(fees.fee), "Salvage company fee", ledger)
	harbor.availableWorkers = int(harbor.availableWorkers) - 3
	var specialists := int(harbor.availableSpecialists) if harbor.has("availableSpecialists") else int(harbor.get("specialistWorkers", 0))
	harbor.availableSpecialists = specialists - 1
	harbor.workers = int(harbor.get("workers", 0)) + 3
	state.moneyLog = ledger
	var restoring: bool = bool(staged.restoring)
	var prepared: Dictionary = staged.prepared if staged.get("prepared") is Dictionary else {}
	var boat: Dictionary = core.add_boat(staged.spec, 0, prepared)
	var recovered := float(staged.contract.hullHp) if staged.get("contract") is Dictionary and staged.contract.has("hullHp") else float(q.get("recoveredHp", 0.0))
	boat["hp"] = clampf(recovered, 0.0, float(boat.get("maxHp", 1.0)))
	boat["crew"] = 0.0
	boat["fuel"] = 0.0
	boat["ammo"] = 0.0
	boat["supplies"] = 0.0
	boat["mothballed"] = true
	boat["towed"] = true
	boat["towSpeedFactor"] = TOW_SPEED_FACTOR
	boat["salvageWreckId"] = str(wreck.get("id", ""))
	boat["needsHarborRepair"] = true
	# Boarding.validate refuses a saved unrepaired hull that is not support-only.
	boat["supportOnly"] = true
	boat["repairLiability"] = (q["repairLiability"] as Dictionary).duplicate(true)
	_retain_service(wreck,boat)
	boat["name"] = str(wreck.get("name",boat.get("name","Boat")))
	boat.serviceHistory.append({"day":_num(state.get("day")),"event":"recovered","detail":"%s (%s) towed from %s for %d coins; uncrewed, empty and damaged. Paid recruitment, harbor repair and stores still required."%[str(boat.name),str(wreck.get("uid","")),str(wreck.get("id","")),int(fees.ordinary)+int(fees.expert)+int(fees.fee)]})
	while boat.serviceHistory.size()>12:boat.serviceHistory.pop_front()
	wreck["stores"] = {}
	wreck["components"] = {}
	if restoring:
		Recovery.release(wreck, "transferred")
	wreck["status"] = STATUS_TOWED
	wreck["claimedMode"] = MODE_TOW
	wreck["towedBoatUid"] = str(boat.get("uid", ""))
	var out := q.duplicate(true)
	out["boatUid"] = str(boat.get("uid", ""))
	out["message"] = "%s towed in. Hire a crew, repair it at a harbor and buy stores." % str(boat.get("name", wreck["name"]))
	return out


static func strip_good(core,wreck_id: String,good: String,qty: float) -> Dictionary:
	if core!=null and core.get("state") is Dictionary and _is_expedition067(core.state,wreck_id):return {"ok":false,"message":"Use the paid campaign action with an explicit finite cargo lot."}
	var wreck: Dictionary=find_wreck(core.state,wreck_id)
	if wreck.is_empty() or wreck.status!=STATUS_UNCLAIMED or not Goods.ITEMS.has(good) or not is_finite(qty) or qty<=0:return {"ok":false,"message":"No recoverable lot of that kind."}
	var blocked := Recovery.refusal(wreck)
	if not blocked.is_empty():
		return {"ok":false,"message":blocked}
	var amount: float=minf(qty,float(_strip_items(wreck).get(good,0)))
	if amount<=0 or amount*float(Goods.ITEMS[good].weight)>_free_capacity(core)+0.00001:return {"ok":false,"message":"Choose a smaller lot; the traveling hold has insufficient space."}
	var left: float=amount
	var removed_structure: bool=false
	for key in ["stores","components"]:
		var take: float=minf(left,float(wreck[key].get(good,0)))
		if key=="components" and take>0 and not Recovery.is_store_good(good):removed_structure=true
		wreck[key][good]=maxf(0,float(wreck[key].get(good,0))-take)
		left-=take
	core.state.cargo[good]=float(core.state.cargo.get(good,0))+amount
	if removed_structure:
		wreck.hullStripped=true
		if Recovery.is_active(wreck):
			Recovery.release(wreck, "retired")
	if _strip_items(wreck).is_empty() and not Recovery.is_active(wreck):wreck.status=STATUS_STRIPPED;wreck.claimedMode=MODE_STRIP
	return {"ok":true,"message":"Recovered %.2f %s from %s."%[amount,good,wreck.name],"weight":amount*float(Goods.ITEMS[good].weight)}


static func _gear_refused(q: Dictionary,message: String) -> Dictionary:
	q.ok=false
	q.message=message
	return {"quote":q}


## One private all-or-nothing transaction. The complete source snapshot stays
## untouched until it is retired; only a separate extraction copy is dismantled.
## Neither a refused quote nor a successful quote publishes the returned state.
static func _gear_stage(core,wreck_id: String,request: Dictionary) -> Dictionary:
	var q: Dictionary={"ok":false,"message":"","wreckId":wreck_id,"mode":MODE_GEAR,
		"carrierUid":str(request.get("carrierUid","")),"selected":[],"forfeitedItems":[],
		"forfeitedComponents":{},"forfeitedHull":true,"retainedStores":{},"weight":0.0,
		"lockerWeight":0.0,"carrierCapacity":0.0,"carrierLockerCapacity":0.0,"freeCapacity":0.0}
	if core==null or not core.get("state") is Dictionary or not core.get("data") is Dictionary:
		return _gear_refused(q,"No campaign state for exact equipment recovery.")
	if _is_expedition067(core.state,wreck_id):return _gear_refused(q,"This collapsed cache contains cargo only; no physical fittings can be recovered.")
	for key in request:
		if key not in ["itemUids","carrierUid","acceptForfeiture"]:return _gear_refused(q,"Unknown selected equipment request field.")
	if not request.get("carrierUid",null) is String or not request.get("itemUids",null) is Array:
		return _gear_refused(q,"Choose an existing carrier and explicit physical item UIDs.")
	if request.has("acceptForfeiture") and not request.acceptForfeiture is bool:
		return _gear_refused(q,"Forfeiture consent must be an explicit boolean.")
	var live: Dictionary=core.state
	if not live.get("wrecks") is Array:return _gear_refused(q,"The wreck list is unreadable.")
	# Use raw records: find_wreck/ensure intentionally normalizes ordinary legacy
	# wrecks, which must never turn corrupt exact-custody input into an accepted one.
	var source: Dictionary={}
	for row in live.wrecks:
		if row is Dictionary and str(row.get("id",""))==wreck_id:
			if not source.is_empty():return _gear_refused(q,"Two wrecks share this recovery ID.")
			source=row
	if source.is_empty() or str(source.get("status",""))!=STATUS_UNCLAIMED or bool(source.get("hullStripped",false)):
		return _gear_refused(q,"Only an intact, unclaimed equipment snapshot can be dismantled once.")
	var blocked: String=Recovery.refusal(source)
	if not blocked.is_empty() or not Recovery.is_active(source):return _gear_refused(q,blocked if not blocked.is_empty() else "This wreck has no canonical physical equipment to select.")
	q.hull=str(source.get("hull",""));q.wreckName=str(source.get("name","Wreck"));q.status=str(source.status)
	for key in ["components","stores"]:
		if not source.get(key,{}) is Dictionary:return _gear_refused(q,"The wreck's finite material lots are unreadable.")
		for good in source.get(key,{}):
			var amount=source[key][good]
			if not Goods.ITEMS.has(good) or not _is_num(amount) or float(amount)<0:return _gear_refused(q,"The wreck's finite material lots are unreadable.")
	q.forfeitedComponents=source.get("components",{}).duplicate(true)
	q.retainedStores=source.get("stores",{}).duplicate(true)
	var selected_ids: Array=request.itemUids
	var seen: Dictionary={}
	for uid in selected_ids:
		if not uid is String or str(uid).is_empty() or seen.has(uid):return _gear_refused(q,"Select unique exact physical item UIDs.")
		seen[uid]=true
	for uid in source.sourceModuleCondition.items:
		var item: Dictionary=source.sourceModuleCondition.items[uid].duplicate(true)
		item.weight=Expedition.locker_item_weight(item)
		if seen.has(uid):q.selected.append(item);q.weight+=float(item.weight)
		else:q.forfeitedItems.append(item)
	if selected_ids.is_empty() or selected_ids.size()>Condition.MAX_LOCKER:
		return _gear_refused(q,"Select at least one real weapon, engine or armor part; pumps remain integral.")
	if q.selected.size()!=selected_ids.size():return _gear_refused(q,"A selected physical item is not aboard this wreck.")
	for item in q.selected:
		if str(item.family)=="pumps":return _gear_refused(q,"Integral pumps stay with the forfeited hull and cannot enter a locker.")
	var initial: Dictionary=Preflight.check_state(live,core.data)
	if not initial.ok:return _gear_refused(q,str(initial.get("message","Campaign equipment custody is unreadable.")))
	var staged: Dictionary=live.duplicate(true)
	# Preserve any legitimate shared hull references across custody lists.
	Preflight._clone_boats(live,staged)
	var wreck: Dictionary={}
	for row in staged.wrecks:
		if str(row.get("id",""))==wreck_id:wreck=row;break
	var carrier: Dictionary={}
	for boat in Expedition.traveling(staged):
		if str(boat.get("uid",""))==str(request.carrierUid):carrier=boat;break
	# An otherwise working traveling support boat is a real carrier too. The
	# existing traveling predicate already excludes disabled/unrepaired prizes.
	if carrier.is_empty() or float(carrier.get("hp",0))<=0:
		return _gear_refused(q,"Choose an existing seaworthy, crewed working hull with its own locker.")
	var known: Dictionary=Recovery.registry(staged,wreck_id,carrier)
	if not known.ok:return _gear_refused(q,str(known.get("message","Equipment custody is unreadable.")))
	var source_base: Dictionary=core.hull(str(wreck.hull))
	var dest_base: Dictionary=core.hull(str(carrier.get("type","")))
	var whole: Dictionary=Recovery.rehearse(source_base,wreck.get("sourceLoadout"),wreck.sourceModuleCondition,str(wreck.id),known.uids)
	if not whole.ok:return _gear_refused(q,str(whole.get("message","The complete source loadout is unreadable.")))
	var prepared: Dictionary=Recovery.prepare(carrier,dest_base,known.uids)
	if not prepared.get("accepted",false):return _gear_refused(q,str(prepared.get("message","The carrier needs valid existing physical equipment.")))
	carrier.moduleCondition=prepared.condition
	var extraction: Dictionary=wreck.sourceModuleCondition.duplicate(true)
	for uid in selected_ids:
		var moved: Dictionary=Condition.transfer_exact(extraction,carrier.moduleCondition,{
			"itemUid":uid,"location":"locker","mountCount":Refits.hardpoints(dest_base).size(),
			"hullType":str(dest_base.id),"sourceMountCount":Refits.hardpoints(source_base).size(),
			"sourceHullType":str(source_base.id),"knownUids":known.uids})
		if not moved.ok:return _gear_refused(q,str(moved.get("error","No selected equipment was transferred.")))
	var projected: Dictionary=Records.publish(carrier)
	if not projected.ok:return _gear_refused(q,str(projected.get("error","The locker projection could not be published.")))
	q.lockerWeight=Expedition.locker_weight(carrier)
	q.carrierCapacity=maxf(0,float(carrier.spec.get("cargo",0)))
	q.carrierLockerCapacity=Expedition.hull_hold_capacity(staged,carrier)
	q.freeCapacity=maxf(0,Expedition.capacity(live)-Expedition.cargo_weight(live))
	if not is_finite(float(q.lockerWeight)) or float(q.lockerWeight)>float(q.carrierLockerCapacity)+0.00001:
		return _gear_refused(q,"The selected parts and existing locker do not fit on this physical hull.")
	if float(q.weight)>float(q.freeCapacity)+0.00001:
		return _gear_refused(q,"The traveling holds have insufficient real space for the selected parts.")
	# Retire the ORIGINAL complete snapshot, not the reduced extraction copy.
	# Its UID list is history; the destination is the sole live selected owner.
	Recovery.release(wreck,"retired")
	wreck.hullStripped=true
	wreck.components={}
	wreck.claimedMode=MODE_GEAR
	if _strip_items(wreck).is_empty():wreck.status=STATUS_STRIPPED
	if not staged.get("wreckSeededSources") is Dictionary:staged.wreckSeededSources={}
	if not str(wreck.get("sourceId","")).is_empty():staged.wreckSeededSources[str(wreck.sourceId)]=true
	Manifest.allocate(staged)
	if not staged.cargoManifest.get("unassigned",{}).is_empty():return _gear_refused(q,"The selected carrier would leave existing cargo without a real hold.")
	var final_custody: Dictionary=Preflight.check_state(staged,core.data)
	if not final_custody.ok:return _gear_refused(q,str(final_custody.get("message","Final equipment custody refused the entire selection.")))
	q.ok=true
	q.message="Dismantle %s: keep %d exact parts in %s; forfeit the hull, every other fitting and all component lots. Loose stores remain marked."%[q.wreckName,q.selected.size(),str(carrier.get("name","carrier"))]
	return {"quote":q,"state":staged}
