extends RefCounted
## v0.018 goals and limited operations. Book: state.regionalCampaigns. No capture, new fleets, or reward coins.

const Rules=preload("res://scripts/regional_rules.gd")
const Money = preload("res://scripts/money.gd")
const Goods = preload("res://scripts/goods.gd")
const Factions = preload("res://scripts/factions.gd")
const Trade = preload("res://scripts/trade_intel.gd")
const Fleets = preload("res://scripts/fleet_economy.gd")

const GOALS := ["corridor", "survey", "harbor", "ceasefire"]
const TITLES := {"corridor": "Secure a trade corridor", "survey": "Complete a survey chain", "harbor": "Support a harbor industry", "ceasefire": "Negotiate a ceasefire"}
const ACCEPT := {
	"harbor": ["food", "logs", "timber", "ore", "iron", "charcoal", "crude", "fuel", "supplies"],
	"corridor": ["fuel", "ammo", "food", "supplies"],
	"ceasefire": ["food", "supplies"],
	"survey": ["supplies"],
}
const PATHS := {"corridor": ["patrol", "player"], "harbor": ["delivery", "recorded-deliveries"], "survey": ["existing-surveys", "later-surveys"], "ceasefire": ["offering"]}
const SURVEY_NEED := 3
const HARBOR_NEED := 12
const FUND_DAYS := 7
const FUND_CAP := 14000
const PEACE_DAYS := 30
const COOLDOWN_DAYS := 30
const FORCE_MIN := 2.0
const MAX_JOURNAL := 40

static func ensure(state) -> Dictionary:
	var host := _state_of(state)
	if host.is_empty() and not (state is Dictionary):
		return {}
	if not host.get("regionalCampaigns") is Dictionary:
		host.regionalCampaigns = {}
	var book: Dictionary = host.regionalCampaigns
	book.version = 2
	book.cadence = "daily"
	book.seq = maxi(0, int(book.get("seq", 0)))
	for pair in [["operations", {}], ["completed", {}], ["peace", {}], ["fundedRoutes",{}], ["journal", []]]:
		if typeof(book.get(pair[0], null)) != typeof(pair[1]):
			book[pair[0]] = pair[1].duplicate()
	var drop := []
	for key in book.operations.keys():
		if book.operations[key] is Dictionary:
			_repair_op(book.operations[key])
		else:
			drop.append(key)
	for key in drop:
		book.operations.erase(key)
	_trim(book)
	return book

static func available(core) -> Array:
	var state := _state_of(core)
	var book := ensure(state)
	var rows := []
	for id in GOALS:
		var op = book.operations.get(id, {})
		var status := "open"
		if op is Dictionary and str(op.get("status", "")) != "":
			status = str(op.status)
		var cid := _completion_id(state, id)
		if status=="cancelled":status="open"
		if status=="complete" and str(op.get("completionId",""))!=cid:status="open"
		var ready: bool = status == "open" and not book.completed.has(cid)
		var reason := "Player can choose this goal."
		if book.completed.has(cid) or status == "complete":
			ready = false
			status = "complete"
			reason = "Already completed."
		elif status == "active":
			ready = false
			reason = "Already underway."
		elif id=="ceasefire":
			var focus: Dictionary=state.get("campaignFocus",{})
			var key: String=_pair_key(str(focus.get("peaceA","compact")),str(focus.get("peaceB","raiders")))
			var until: int=int(book.peace.get(key,{}).get("cooldownUntil",0))
			if _today(state)<until:ready=false;reason="New talks can start after day %d."%until
		elif id == "corridor" and _ports(state).size() < 2:
			ready = false
			reason = "A corridor needs two ports."
		elif id == "harbor" and _ports(state).is_empty():
			ready = false
			reason = "A harbor goal needs a port."
		rows.append({"id": id, "title": str(TITLES[id]), "ready": ready, "status": status, "reason": reason, "completionId": cid, "paths": PATHS[id]})
	return rows

static func start(core, id) -> Dictionary:
	var state := _state_of(core)
	var book := ensure(state)
	Factions.ensure(state,_bundle(core).world)
	var goal := _goal(id)
	if goal == "":
		return _no("Unknown goal.")
	if goal=="ceasefire":
		var focus: Dictionary=state.get("campaignFocus",{})
		var a: String=str(focus.get("peaceA","compact"));var b: String=str(focus.get("peaceB","raiders"))
		if a==b or not a in Factions.CANON or not b in Factions.CANON:return _no("Choose two different known factions.")
		if _today(state)<int(book.peace.get(_pair_key(a,b),{}).get("cooldownUntil",0)):return _no("The previous treaty's cooldown has not ended.")
	if goal=="corridor" and str(state.get("campaignFocus",{}).get("fromPort",""))==str(state.get("campaignFocus",{}).get("toPort","")) and not state.get("campaignFocus",{}).is_empty():return _no("A corridor needs different endpoints.")
	var cid := _completion_id(state, goal)
	if book.completed.has(cid):
		return _no("That goal is already complete.")
	var live = book.operations.get(goal, {})
	if live is Dictionary and str(live.get("status", "")) == "active":
		return _no("That goal is already underway.")
	if goal == "corridor" and _ports(state).size() < 2:
		return _no("A corridor needs two ports.")
	if goal == "harbor" and _ports(state).is_empty():
		return _no("A harbor goal needs a port.")
	var op := _blank(state, goal, cid)
	Rules.initialize(state,op)
	book.operations[goal] = op
	if goal == "corridor":
		_mobilize(state, book, op)
	var recognized := goal == "survey" and _chain(state) >= SURVEY_NEED
	if recognized:
		_complete(book, op, "existing-surveys")
	_touch(state, op)
	return {"ok": true, "id": goal, "status": str(op.status), "completionId": cid, "funded": int(op.funded), "ownerId": str(op.ownerId), "portId": str(op.portId), "recognized": recognized, "completed": str(op.status) == "complete", "spawned": false, "minted": false, "escrow": "", "message": "Started. No fleet created and no reward minted."}

static func contribute(core, id, good, qty) -> Dictionary:
	var state := _state_of(core)
	var book := ensure(state)
	var goal := _goal(id)
	var name := str(good)
	var op = book.operations.get(goal, {})
	if goal == "" or not op is Dictionary or str(op.get("status", "")) != "active":
		return _refused("That goal is not accepting supplies.")
	var accepted: Array = ACCEPT.get(goal, [])
	if not Goods.ITEMS.has(name) or not accepted.has(name) or not _whole(qty):
		return _refused("The good or quantity was refused. Nothing was moved.")
	var count := int(qty)
	var port := Rules.local_port(state) if goal=="ceasefire" else _port(state,str(op.portId))
	if not Rules.may_deliver(state,port):return _refused("Stop at the actual receiving harbor with legal access. No cargo moved.")
	if goal=="ceasefire" and not str(port.get("faction","")) in [str(op.peaceA),str(op.peaceB)]:return _refused("Relief must reach one of the two treaty parties.")
	if port.is_empty() or not (port.get("stocks") is Dictionary) or not (state.get("cargo") is Dictionary):
		return _refused("No real cargo ledger or port stock.")
	if int(floor(float(state.cargo.get(name, 0)))) < count:
		return _refused("Not enough cargo. Nothing was moved.")
	state.cargo[name] = float(state.cargo.get(name, 0)) - float(count)
	port.stocks[name] = float(port.stocks.get(name, 0)) + float(count)
	op.contributed[name] = int(op.contributed.get(name, 0)) + count
	if goal=="ceasefire":
		op.relief[str(port.faction)]=int(op.relief.get(str(port.faction),0))+count
		Rules.progress(state,op)
	_note(book, {"day": _today(state), "kind": "contribute", "goal": goal, "good": name, "qty": count, "portId": str(port.id), "purpose": "supply", "target": str(port.id), "cause": "player-delivery", "funder": "player-cargo"})
	return {"ok": true, "refused": false, "id": goal, "good": name, "qty": count, "cargo": int(floor(float(state.cargo[name]))), "stock": int(floor(float(port.stocks[name]))), "message": "Cargo moved into port stock. No coins paid."}

static func tick(core, days = 1) -> Array:
	var state := _state_of(core)
	var book := ensure(state)
	if not _whole(days):
		return []
	var events := Rules.expire(state,book)
	for event in events:_note(book,event)
	for goal in GOALS:
		var op = book.operations.get(goal, {})
		if not op is Dictionary or str(op.get("status", "")) != "active":
			continue
		_touch(state, op)
		var cause := _ready_cause(state, op)
		if cause == "":
			continue
		var event := _complete(book, op, cause)
		if not event.is_empty():
			events.append(event)
	book.lastTickDay = _today(state)
	book.lastTickSpan = int(days)
	return events

static func propose_peace(core, a, b) -> Dictionary:
	var bundle := _bundle(core)
	var state: Dictionary = bundle.state
	var book := ensure(state)
	Factions.ensure(state, bundle.world)
	var left := str(a)
	var right := str(b)
	var op: Dictionary=book.operations.get("ceasefire",{})
	var conditions: Dictionary=Rules.peace_conditions(state,op,left,right)
	for value in conditions.values():
		if value is bool and not value:return _peace_no(str(conditions.reason),conditions)
	var before: int=Factions.relation(state,left,right)
	var key: String=_pair_key(left,right)
	var written: Dictionary = Factions.set_relation(state, left, right, 0, "Ceasefire. No player commission.")
	if not bool(written.get("ok", false)) or int(written.get("relation", before)) != 0:
		return _peace_no("Faction relation was not changed.", conditions)
	var day := _today(state)
	var record := {"key": key, "a": left, "b": right, "relation": 0, "before": before, "day": day, "untilDay": day + PEACE_DAYS, "cooldownUntil": day + PEACE_DAYS + COOLDOWN_DAYS, "duration": PEACE_DAYS, "kind": "peace", "goal": "ceasefire", "purpose": "ceasefire", "target": key, "cause": "existing-hostility", "funder": "none", "commissioned": false, "active":true}
	book.peace[key] = record
	if op is Dictionary:
		op.peaceKey = key
		_complete(book, op, "peace")
	_note(book, record)
	return {"ok": true, "changed": true, "relation": 0, "before": before, "after": 0, "key": key, "duration": PEACE_DAYS, "untilDay": int(record.untilDay), "cooldownUntil": int(record.cooldownUntil), "conditions": conditions, "commissioned": false, "escrow": "", "message": "Relation set to neutral. No commission and no reward."}

static func journal(state) -> Array:
	return ensure(state).journal.duplicate(true)

static func observe_plan(state: Dictionary,owner: Dictionary,plan: Dictionary) -> void:
	var book: Dictionary=ensure(state)
	var op: Dictionary=book.operations.get("corridor",{})
	if op.get("status","")!="active" or str(op.get("ownerId",""))!=str(owner.get("id","")) or plan.is_empty():return
	if str(plan.get("ownerId",owner.get("id","")))!=str(owner.get("id","")):return
	var previous: Dictionary=op.get("currentPlan",{})
	var was_ready: bool=bool(previous.get("ready",false))
	var ready: bool=bool(plan.get("ready",false))
	op.currentPlan=plan.duplicate(true)
	op.readiness=plan.get("readiness",{}).duplicate(true)
	op.stallReason="" if ready else str(plan.get("reason","Awaiting supplies."))
	var identity: String="%s|%s|%s|%s"%[str(plan.get("purpose","")),str(plan.get("destination","")),str(plan.get("targetOwnerId","")),str(plan.get("readiness",{}).get("shortage",""))]
	# Numeric reserves change continuously. Journal material order/shortage changes
	# only; one stalled watch cannot evict all physical history every second.
	if str(op.get("planIdentity",""))==identity and not previous.is_empty() and was_ready==ready:return
	op.planIdentity=identity
	var kind: String="operation-order" if ready else "operation-stalled"
	if ready and not was_ready and not previous.is_empty():kind="operation-resumed"
	_note(book,{"day":_today(state),"kind":kind,"goal":"corridor","target":str(owner.id),"purpose":str(plan.get("purpose","")),"destination":str(plan.get("destination","")),"targetOwnerId":str(plan.get("targetOwnerId","")),"convoyOwnerId":str(plan.get("convoyOwnerId","")),"cause":str(plan.get("reason","")),"completionId":str(op.completionId)})

static func cancel(core,id: String) -> Dictionary:
	var state: Dictionary=_state_of(core)
	var book: Dictionary=ensure(state)
	var op: Dictionary=book.operations.get(id,{})
	if op.get("status","")!="active":return _no("No active goal to withdraw.")
	op.status="cancelled"
	_note(book,{"day":_today(state),"kind":"withdrawn","goal":id,"cause":"player-choice","target":str(op.completionId)})
	return {"ok":true,"message":"Goal withdrawn. Supplies and grants remain with their recipients. Restarting cannot duplicate treasury support."}

static func _mobilize(state: Dictionary, book: Dictionary, op: Dictionary) -> void:
	# Reopening the same corridor reuses the original paid recipient, even if
	# threat, port stock or patrol strength has since changed. Never grant again.
	if book.fundedRoutes.has(str(op.completionId)):
		var prior: Dictionary=book.fundedRoutes[str(op.completionId)]
		op.ownerId=str(prior.get("ownerId",""));op.portId=str(prior.get("portId",op.portId))
		op.funded=int(prior.amount);op.funding=prior.duplicate(true)
		var assigned: Dictionary=_owner(state,str(op.ownerId))
		op.patrolLastPort=str(assigned.get("atPort",""))
		op.fundingReason="Existing once-only treasury support remains with its paid recipient."
		return
	var ends: Array = op.ends.map(func(id):return _port(state,str(id)))
	var threat := _threat(state, ends)
	var base := _base(state, ends)
	op.threat = bool(threat.ok)
	op.cause = str(threat.cause)
	if base.owner.is_empty() or base.port.is_empty():
		op.fundingReason="No existing patrol based at either corridor endpoint. No fleet was created."
		return
	var owner: Dictionary = base.owner
	var port: Dictionary = base.port
	op.portId = str(port.id)
	if not Rules.may_deliver(state,port):
		op.fundingReason="Organize the watch at its actual sponsoring harbor with legal access."
		return
	var standing: Dictionary=Factions.standing(state,str(port.get("faction","")))
	if standing.get("hostile",true) or int(standing.get("public",0))<Factions.FRIENDLY_ENTER:
		op.fundingReason="Friendly standing is required for the sponsoring harbor's public watch."
		return
	op.ownerId=str(owner.id);op.patrolLastPort=str(owner.get("atPort",""))
	if not threat.ok:
		op.fundingReason="No actual corridor threat justifies a treasury grant; the existing patrol uses its own paid stores."
		return
	var public_reserve: int=int(port.get("publicWorkers",0))*int(Goods.WAGES.laborer)*2
	var amount := mini(maxi(0,int(port.get("governmentPurse",0))-public_reserve),_grant(owner))
	var note := {"day": _today(state), "goal": "corridor", "purpose": "upkeep", "target": str(owner.id), "cause": str(threat.cause), "funder": str(port.id), "purse": "governmentPurse", "amount": amount}
	if amount <= 0:
		op.fundingReason="Treasury cannot fund the patrol while preserving two public-payroll days."
		note.kind = "mobilize-skipped"
		_note(book, note)
		return
	if not state.get("moneyLog") is Array:
		state.moneyLog = []
	var reason := "purpose=upkeep target=%s cause=%s funder=%s purse=governmentPurse" % [str(owner.id), str(threat.cause), str(port.id)]
	if not Money.move(port, "governmentPurse", owner, "coins", amount, reason, state.moneyLog):
		return
	op.ownerId=str(owner.id)
	op.patrolLastPort=str(owner.get("atPort",""))
	op.funded = amount
	op.fundingReason="Once-only public support paid into the actual patrol's coins; all stores, wages and service still require payment."
	op.funding = {"amount": amount, "ownerId": str(owner.id), "portId": str(port.id), "purpose": "upkeep", "target": str(owner.id), "cause": str(threat.cause), "funder": str(port.id), "purse": "governmentPurse"}
	book.fundedRoutes[str(op.completionId)]=op.funding.duplicate(true)
	note.kind = "mobilize"
	_note(book, note)

static func _ready_cause(state: Dictionary, op: Dictionary) -> String:
	if str(op.id)=="survey":return "survey-chain" if _chain(state)>=SURVEY_NEED else ""
	return Rules.progress(state,op)

static func _complete(book: Dictionary, op: Dictionary, cause: String) -> Dictionary:
	var cid := str(op.completionId)
	if cid == "" or book.completed.has(cid) or str(op.status) == "complete":
		op.status = "complete"
		return {}
	op.status = "complete"
	var day := int(op.get("progressDay", 0))
	if day <= 0:
		day = int(op.startedDay)
	var event := {"day": day, "kind": "complete", "id": str(op.id), "goal": str(op.id), "completionId": cid, "cause": cause, "funded": int(op.funded)}
	book.completed[cid] = {"id": cid, "goal": str(op.id), "day": day, "cause": cause}
	_note(book, event)
	return event

static func _touch(state: Dictionary, op: Dictionary) -> void:
	op.progressDay = _today(state)

static func _blank(state: Dictionary, goal: String, cid: String) -> Dictionary:
	var ends := _ends(state) if goal == "corridor" else []
	var ids := []
	for port in ends:
		ids.append(str(port.id))
	var port_id := ""
	if goal == "harbor":
		port_id = _harbor_id(state)
	elif not _ports(state).is_empty():
		port_id = str(_ports(state)[0].id) if goal != "corridor" else (str(ends[0].id) if ends.size() == 2 else "")
	return {"id": goal, "status": "active", "startedDay": _today(state), "completionId": cid, "portId": port_id, "ends": ids, "ownerId": "", "funded": 0, "funding": {}, "baseline": _facts(state), "contributed": {}, "threat": false, "cause": ""}

static func _completion_id(state: Dictionary, goal: String) -> String:
	if goal == "survey":
		return "survey:chain"
	if goal == "harbor":
		return "harbor:" + _harbor_id(state)
	if goal == "ceasefire":
		var focus: Dictionary=state.get("campaignFocus",{})
		var key: String=_pair_key(str(focus.get("peaceA","compact")),str(focus.get("peaceB","raiders")))
		return "peace:%s:%d"%[key,int(state.get("regionalCampaigns",{}).get("peace",{}).get(key,{}).get("day",0))]
	var ends := _ends(state)
	if ends.size() < 2:
		return "corridor:"
	return "corridor:%s|%s" % [str(ends[0].id), str(ends[1].id)]

static func _grant(owner: Dictionary) -> int:
	var boats = owner.get("boats", [])
	if not boats is Array or boats.is_empty():
		return 0
	for boat in boats:
		if not boat is Dictionary or not boat.get("spec") is Dictionary or not boat.has("sunk"):
			return 0
	return mini(FUND_CAP, maxi(0, int(floor(float(Fleets.upkeep(owner).get("wages", 0))))) * FUND_DAYS)

static func _threat(state: Dictionary, ports: Array) -> Dictionary:
	var blocked := Trade.blockades(state)
	for port in ports:
		if blocked.has(str(port.id)):return {"ok": true, "cause": "blockade:" + str(port.id)}
	for owner in state.get("fleetOwners", []):
		if not owner is Dictionary or _story(owner) or not bool(owner.get("active", true)) or _force(owner) < FORCE_MIN:
			continue
		var actor: Dictionary={}
		for patrol in state.get("patrols",[]):
			if str(patrol.get("id",""))==str(owner.get("id","")) and patrol.get("active",false):actor=patrol;break
		if actor.is_empty() or ports.size()!=2:continue
		if not Rules.near_corridor(state,{"ends":[str(ports[0].id),str(ports[1].id)]},Vector2(float(actor.x),float(actor.y))):continue
		for port in ports:
			if _relation(state, str(owner.get("faction", "")), str(port.get("faction", ""))) <= int(Factions.ENEMY_AT):
				return {"ok": true, "cause": "hostile:" + str(owner.id)}
	return {"ok": false, "cause": ""}

static func _base(state: Dictionary, ports: Array) -> Dictionary:
	var local: Dictionary=Rules.local_port(state)
	# Empty stores are a visible supply stall, not a reason to erase the patrol
	# assignment. Paid dock/loading paths remain the only consumers of stock.
	for port in ports:
		if str(port.get("id",""))!=str(local.get("id","")):continue
		var owner: Dictionary=_fund_target(state,port)
		if not owner.is_empty():return {"port":port,"owner":owner}
	for port in ports:
		var owner := _fund_target(state, port)
		if not owner.is_empty():
			return {"port": port, "owner": owner}
	return {"port": {}, "owner": {}}

static func _fund_target(state: Dictionary, port: Dictionary) -> Dictionary:
	var best := {}
	for owner in state.get("fleetOwners", []):
		if not owner is Dictionary or _story(owner) or not bool(owner.get("active", true)):
			continue
		if str(owner.get("homePort", "")) != str(port.id) or str(owner.get("faction", "")) != str(port.get("faction", "")):
			continue
		var kind := str(owner.get("kind", ""))
		if kind != "patrol" or _living(owner) < 1:
			continue
		var better := best.is_empty() or (kind == "patrol" and str(best.kind) != "patrol")
		if not better and kind == str(best.kind):
			better = str(owner.id) < str(best.id)
		if better:
			best = owner
	return best

static func _supplied_port(port: Dictionary) -> bool:
	if int(port.get("governmentPurse", 0)) <= 0 or not (port.get("stocks") is Dictionary):
		return false
	for good in ["food", "fuel", "supplies", "ammo"]:
		if float(port.stocks.get(good, 0)) >= 1.0:
			return true
	return false

static func _force(owner) -> float:
	if not owner is Dictionary or not bool(owner.get("active", true)):
		return 0.0
	var force := 0.0
	for boat in owner.get("boats", []):
		if not boat is Dictionary or bool(boat.get("sunk", false)):
			continue
		if float(boat.get("crew", 0)) < maxf(1.0, float(boat.get("crewMin", 1))):
			continue
		if float(boat.get("fuel", 0)) < 0.5 or float(boat.get("ammo", 0)) < 10.0:
			continue
		force += maxf(1.0, float(boat.get("hp", 40.0)) / 40.0)
	return force

static func _living(owner: Dictionary) -> int:
	var count := 0
	for boat in owner.get("boats", []):
		if boat is Dictionary and not bool(boat.get("sunk", false)) and float(boat.get("crew", 0)) >= 1.0:
			count += 1
	return count

static func _blocked(state: Dictionary, op: Dictionary) -> bool:
	var blocked := Trade.blockades(state)
	for id in op.ends:
		if blocked.has(str(id)):return true
	return false

static func _chain(state: Dictionary) -> int:
	var ex = state.get("exploration", {})
	if not ex is Dictionary:
		return 0
	var progress = ex.get("sites", {})
	var nodes := {}
	var catalog = ex.get("catalog", [])
	if catalog is Array:
		for site in catalog:
			if site is Dictionary and str(site.get("id", "")) != "":
				var level := 0
				if progress is Dictionary and progress.get(site.id) is Dictionary:
					level = int(progress[site.id].get("level", 0))
				nodes[str(site.id)] = [str(site.get("leadId", "")), level]
	var best := 0
	for start_id in nodes.keys():
		var seen := {}
		var cursor := str(start_id)
		var count := 0
		while nodes.has(cursor) and not seen.has(cursor) and int(nodes[cursor][1]) >= 3:
			seen[cursor] = true
			count += 1
			cursor = str(nodes[cursor][0])
			if cursor == "":
				break
		best = maxi(best, count)
	return best

static func _business(state: Dictionary, port_id: String) -> String:
	var rows = state.get("businesses", [])
	if not rows is Array:
		return ""
	for row in rows:
		if row is Dictionary and str(row.get("homePort", "")) == port_id and bool(row.get("active", true)):
			return str(row.get("id", port_id))
	return ""

static func _party_port(state: Dictionary, a: String, b: String) -> bool:
	for port in _ports(state):
		if str(port.get("faction", "")) == a or str(port.get("faction", "")) == b:
			return true
	return false

static func _facts(state: Dictionary) -> Dictionary:
	var raw = state.get("campaignFacts", {})
	if not raw is Dictionary:
		raw = {}
	return {"escortsSaved": maxi(0, int(raw.get("escortsSaved", 0))), "goodsDelivered": maxi(0, int(raw.get("goodsDelivered", 0))), "bountyWins": maxi(0, int(raw.get("bountyWins", 0))), "licensedDesigns": maxi(0, int(raw.get("licensedDesigns", 0)))}

static func _delta(state: Dictionary, op: Dictionary, key: String) -> int:
	return int(_facts(state)[key]) - int(op.baseline.get(key, 0))

static func _sum(raw) -> int:
	var total := 0
	if raw is Dictionary:
		for key in raw.keys():
			total += int(raw[key])
	return total

static func _relation(state: Dictionary, a: String, b: String) -> int:
	if a == "" or b == "" or a == b:
		return 0
	var book = state.get("relationships", {})
	if book is Dictionary and book.get("pairs") is Dictionary:
		return int(Factions.relation(state, a, b))
	return int(Factions.PAIR_BASE.get(_pair_key(a, b), 0))

static func _pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

static func _harbor_id(state: Dictionary) -> String:
	var chosen: String=str(state.get("campaignFocus",{}).get("portId",""))
	if not _port(state,chosen).is_empty():return chosen
	if not _port(state, str(state.get("lastPort", ""))).is_empty():
		return str(state.lastPort)
	var ports := _ports(state)
	return "" if ports.is_empty() else str(ports[0].id)

static func _ends(state: Dictionary) -> Array:
	var rows := _ports(state)
	var focus: Dictionary=state.get("campaignFocus",{})
	var a: Dictionary=_port(state,str(focus.get("fromPort","")))
	var b: Dictionary=_port(state,str(focus.get("toPort","")))
	if not a.is_empty() and not b.is_empty() and a.id!=b.id:
		var selected: Array=[a,b]
		selected.sort_custom(func(x,y):return str(x.id)<str(y.id))
		return selected
	if rows.size() < 2:
		return rows
	rows.sort_custom(func(a, b): return str(a.id) < str(b.id))
	return [rows[0], rows[1]]

static func _ports(state: Dictionary) -> Array:
	var rows := []
	for port in state.get("ports", []):
		if port is Dictionary and str(port.get("id", "")) != "":
			rows.append(port)
	return rows

static func _port(state: Dictionary, id: String) -> Dictionary:
	for port in state.get("ports", []):
		if port is Dictionary and str(port.get("id", "")) == id and id != "":
			return port
	return {}

static func _owner(state: Dictionary, id: String) -> Dictionary:
	for owner in state.get("fleetOwners", []):
		if owner is Dictionary and str(owner.get("id", "")) == id and id != "":
			return owner
	return {}

static func _story(owner) -> bool:
	return str(owner.get("id", "")).begins_with("story-")

static func _repair_op(op: Dictionary) -> void:
	op.id = str(op.get("id", ""))
	op.status = str(op.status) if str(op.get("status","")) in ["active","complete","cancelled"] else "active"
	op.completionId = str(op.get("completionId", ""))
	op.portId = str(op.get("portId", ""))
	op.ownerId = str(op.get("ownerId", ""))
	op.funded = maxi(0, int(op.get("funded", 0)))
	op.startedDay = int(op.get("startedDay", 0))
	if not op.get("contributed") is Dictionary:
		op.contributed = {}
	if not op.get("baseline") is Dictionary:
		op.baseline = {}
	if not op.get("ends") is Array:
		op.ends = []

static func _note(book: Dictionary, event: Dictionary) -> void:
	book.seq = int(book.seq) + 1
	event.seq = int(book.seq)
	book.journal.push_front(event.duplicate(true))
	while book.journal.size() > MAX_JOURNAL:
		book.journal.pop_back()

static func _trim(book: Dictionary) -> void:
	while book.journal.size() > MAX_JOURNAL:
		book.journal.pop_back()
	while book.completed.size()>120:
		var oldest: String=""
		var day: int=2147483647
		for key in book.completed:
			if str(key).begins_with("peace:") and int(book.completed[key].get("day",0))<day:oldest=str(key);day=int(book.completed[key].get("day",0))
		if oldest=="":break
		book.completed.erase(oldest)

static func _goal(id) -> String:
	var goal := str(id).strip_edges()
	return goal if GOALS.has(goal) else ""

static func _whole(value) -> bool:
	if value is bool:
		return false
	if value is int:
		return value >= 1
	return value is float and is_finite(value) and value >= 1.0 and floor(value) == value

static func _today(state: Dictionary) -> int:
	return Rules.today(state)

static func _no(message: String) -> Dictionary:
	return {"ok": false, "funded": 0, "escrow": "", "message": message}

static func _refused(message: String) -> Dictionary:
	return {"ok": false, "refused": true, "message": message}

static func _peace_no(message: String, conditions: Dictionary) -> Dictionary:
	return {"ok": false, "changed": false, "commissioned": false, "escrow": "", "conditions": conditions, "message": message}

static func _bundle(core) -> Dictionary:
	if core is Dictionary and not (core.get("state") is Dictionary and not core.has("ports")):
		return {"state": core, "world": core.get("world", {}) if core.get("world") is Dictionary else {}}
	var world := {}
	var inner := {}
	if not core is Dictionary and core != null:
		inner = core.get("state") if core.get("state") is Dictionary else {}
		if core.get("data") is Dictionary:
			world = core.get("data")
		elif core.get("world") is Dictionary:
			world = core.get("world")
	elif core is Dictionary and core.get("state") is Dictionary:
		inner = core.state
		world = core.world if core.get("world") is Dictionary else {}
	return {"state": inner, "world": world}

static func _state_of(core) -> Dictionary:
	return _bundle(core).state
