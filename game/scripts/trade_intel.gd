extends RefCounted

const Expedition=preload("res://scripts/expedition.gd")
const Economy = preload("res://scripts/economy.gd")
const Goods = preload("res://scripts/goods.gd")
const Damage = preload("res://scripts/damage.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Factions = preload("res://scripts/factions.gd")

const WAGE := 100
const DAY_SECONDS := 45.0
const SPEED_SCALE := 1.55
const DOCK_RADIUS := 65.0
const NEAR_PORT := 160.0
const FUEL_MIN := 0.5
const AMMO_MIN := 10.0
const FORCE_MIN := 2.0
const MAX_OBSERVATIONS := 16
const MAX_EVENTS := 40
const UNCERTAINTY_PER_DAY := 0.06
const UNCERTAINTY_CAP := 0.48
const STORY_PREFIX := "story-"

static func ensure(state) -> Dictionary:
	if not state is Dictionary:
		return {}
	if not state.get("tradeIntel") is Dictionary:
		state.tradeIntel = {}
	var book = state.tradeIntel
	book.version = 1
	if not book.get("observations") is Dictionary:
		book.observations = {}
	if not book.get("blockades") is Dictionary:
		book.blockades = {}
	if not book.get("events") is Array:
		book.events = []
	book.seq = int(book.get("seq", 0))
	var drop = []
	for key in book.observations.keys():
		if book.observations[key] is Dictionary:
			_repair_obs(book.observations[key])
		else:
			drop.append(key)
	for key in drop:
		book.observations.erase(key)
	_trim(book)
	return book

static func observe(state, port, day) -> Dictionary:
	if not state is Dictionary:
		return {"ok": false, "seen": false, "message": "No campaign state."}
	var source := _port_dict(state, port)
	if source.is_empty():
		return {"ok": false, "seen": false, "portId": str(port), "message": "Unknown port."}
	var book := ensure(state)
	var stocks := {}
	var buy := {}
	var sell := {}
	var live = source.stocks if source.get("stocks") is Dictionary else {}
	for good in Goods.ITEMS:
		stocks[good] = maxi(0, int(floor(float(live.get(good, 0)))))
		buy[good] = int(Economy.price(source, good, "buy"))
		sell[good] = int(Economy.price(source, good, "sell"))
	book.seq = int(book.seq) + 1
	var row := {
		"portId": str(source.get("id", "")),
		"name": str(source.get("name", source.get("id", ""))),
		"day": int(floor(float(day))),
		"seq": int(book.seq),
		"stocks": stocks,
		"buy": buy,
		"sell": sell,
		"businessFunds": maxi(0, int(round(float(source.get("cash", 0))))),
		"industry": str(source.get("industry", "trade")),
		"specialty": str(source.get("specialty", "")),
		"population": float(source.get("population", 1200)), "wealth": float(source.get("wealth", 1)),
		"faction": str(source.get("faction", "")),
		"needs": _observed_needs(source),
	}
	book.observations[row.portId] = row
	_trim(book)
	return {"ok": true, "seen": true, "portId": row.portId, "day": row.day, "businessFunds": row.businessFunds, "message": "Visit recorded."}

static func report(core, port_id) -> Dictionary:
	var state = _bundle(core).state
	var book := ensure(state)
	var id := str(port_id)
	var obs = book.observations.get(id, {})
	if obs.is_empty() or not obs.has("day"):
		return {
			"ok": true, "seen": false, "portId": id, "age": null, "uncertainty": "unseen",
			"scarcity": {}, "scarcitySummary": "unseen", "businessFunds": null, "needs": {},
			"estimate": false, "guaranteed": false, "source": "none",
			"message": "No visit on record. Live remote stock and prices are omitted.",
		}
	var age := maxi(0, _today(state) - int(obs.day))
	var uncertainty := _uncertainty(age)
	var scarce := _scarcity(obs)
	var quote := "observed" if age == 0 else "stale"
	return {
		"ok": true, "seen": true, "portId": id, "name": str(obs.get("name", id)),
		"observedDay": int(obs.day), "age": age, "uncertainty": uncertainty, "quote": quote,
		"stocks": _int_map(obs.get("stocks", {})), "buy": _int_map(obs.get("buy", {})), "sell": _int_map(obs.get("sell", {})),
		"businessFunds": int(obs.get("businessFunds", 0)), "scarcity": scarce.goods, "scarcitySummary": scarce.summary,
		"needs": _as_dict(obs.get("needs")).duplicate(true),
		"estimate": true, "guaranteed": false, "source": "visit",
		"message": "%s visit quote, age %d, uncertainty %.0f%%. Not a live price or a guaranteed sale." % [quote, age, uncertainty * 100.0],
	}

static func opportunities(core) -> Array:
	var bundle := _bundle(core)
	var state = bundle.state
	var book := ensure(state)
	var speed: float=float(core.travel_speed()) if not core is Dictionary and core!=null and core.has_method("travel_speed") else _travel_speed(state,bundle.world)
	if speed <= 0.01:
		return []
	var here := _current_port(state)
	var upkeep = Economy.daily_upkeep(state.get("fleet", []))
	var daily_wages := int(upkeep.get("wages", 0))
	for specialist in state.get("specialists",[]):
		if not specialist.get("discharged",false) and not specialist.get("lost",false):daily_wages+=int(specialist.get("premiumPerDay",0))
	var food_per_day := float(upkeep.get("food", 0))
	var carried := _sellable(state)
	var free: float=maxf(0,float(core.capacity())-float(core.cargo_weight())) if not core is Dictionary and core!=null and core.has_method("capacity") else maxf(0,Expedition.capacity(state)-Expedition.cargo_weight(state))
	var aboard := _fuel_aboard(state)
	var rows = []
	var here_id := str(here.get("id", ""))
	for port in state.get("ports", []):
		if not port is Dictionary:
			continue
		var pid := str(port.get("id", ""))
		if pid == "" or pid == here_id:
			continue
		var obs = book.observations.get(pid, {})
		if obs.is_empty():
			continue
		var origin = here if not here.is_empty() else {}
		if origin.is_empty() and state.get("position") is Dictionary:
			origin = state.position
		if origin.is_empty() or not origin.has("x") or not port.has("x"):
			continue
		var route := _route(bundle.nav, origin, port)
		if bool(route.noPath):continue
		var distance := float(route.distance)
		var seconds := distance / speed * 2.0
		var days := seconds / DAY_SECONDS
		var wage_cost := ceili(float(daily_wages) * days) if daily_wages > 0 else 0
		var drums := _fuel_burn(state, seconds)
		var fuel_price := 0
		var food_price := 0
		if not here.is_empty():
			fuel_price = int(Economy.price(here, "fuel", "buy"))
			food_price = int(Economy.price(here, "food", "buy"))
		var fuel_cost := ceili(drums * float(fuel_price))
		var food_cost := ceili(food_per_day * days * float(food_price))
		var trip := wage_cost + fuel_cost + food_cost
		var preparation := Expedition.report(state, bundle.world, distance, speed)
		var ctx := {
			"trip": trip, "wage": wage_cost, "wages": daily_wages, "drums": drums, "fuel": fuel_cost,
			"food": food_per_day, "foodCost": food_cost, "days": days, "distance": distance, "speed": speed,
			"route": route, "funds": int(obs.get("businessFunds", 0)), "free": free,
			"age": maxi(0, _today(state) - int(obs.get("day", _today(state)))), "aboard": aboard,
			"preparation": preparation, "fuelPrice": fuel_price, "foodPrice": food_price,
			"stockLimit": 0, "affordLimit": 0, "holdLimit": 0,
		}
		var sell_map = obs.get("sell", {})
		var best = {}
		for good in Goods.ITEMS:
			var sell := int(sell_map.get(good, 0))
			if sell <= 0:
				continue
			var weight := float(Goods.ITEMS[good].weight)
			var liquidity := int(floor(float(ctx.funds) / float(sell)))
			ctx.liquidity = liquidity
			var have := maxi(0, int(floor(float(carried.get(good, 0)))))
			if mini(have, liquidity) > 0:
				ctx.stockLimit = have
				ctx.affordLimit = have
				ctx.holdLimit = have
				best = _better(best, _offer(state, here, obs, port, "carried", good, mini(have, liquidity), 0, sell, ctx))
			if here.is_empty() or free <= 0.0:
				continue
			var buy := int(Economy.price(here, good, "buy"))
			if buy <= 0:
				continue
			var stock := 0
			if here.get("stocks") is Dictionary:
				stock = maxi(0, int(floor(float(here.stocks.get(good, 0)))))
			var afford := int(floor(float(maxi(0,int(state.get("coins",0))-trip-daily_wages*2-int(state.get("wageArrears",0))))/float(buy)))
			var room := int(floor(free / maxf(0.001, weight)))
			var qty := mini(stock, mini(afford, mini(room, liquidity)))
			if qty > 0:
				ctx.stockLimit = stock
				ctx.affordLimit = afford
				ctx.holdLimit = room
				best = _better(best, _offer(state, here, obs, port, "local_buy", good, qty, buy, sell, ctx))
		if not best.is_empty():
			rows.append(best)
	rows.sort_custom(func(a, b): return int(a.netProfit) > int(b.netProfit))
	if rows.size() > 8:
		rows.resize(8)
	return rows

static func blockades(core) -> Array:
	var state = _bundle(core).state
	var ids = []
	for port in state.get("ports", []):
		if port is Dictionary and bool(_assess_port(state, port).active):
			ids.append(str(port.get("id", "")))
	ids.sort()
	return ids

static func update(core) -> Array:
	var state = _bundle(core).state
	var book := ensure(state)
	var day := _today(state)
	var events = []
	var live := {}
	for port in state.get("ports", []):
		if not port is Dictionary:
			continue
		var pid := str(port.get("id", ""))
		if pid == "":
			continue
		live[pid] = true
		var now := _assess_port(state, port)
		var prev = book.blockades.get(pid, {})
		var was := bool(prev.get("active", false))
		if was and not bool(now.active):
			now.cause = _lift_cause(state, prev, now)
			now.active = false
			if str(now.get("ownerId", "")) == "":
				now.ownerId = str(prev.get("ownerId", ""))
		now.day = day
		now.portId = pid
		now.kind = "blockade"
		now.ownerId = str(now.get("ownerId", ""))
		now.hostileForce = float(now.hostileForce)
		now.oppositionForce = float(now.oppositionForce)
		book.blockades[pid] = now.duplicate(true)
		var active := bool(now.active)
		var cause := str(now.cause)
		if was == active and not (active and str(prev.get("cause", "")) != cause):
			continue
		if not was and not active:
			continue
		var event := now.duplicate(true)
		events.append(event)
		book.events.push_front(event.duplicate(true))
	var stale = []
	for key in book.blockades.keys():
		if not live.has(str(key)):
			stale.append(key)
	for key in stale:
		book.blockades.erase(key)
	book.lastUpdateDay = day
	_trim(book)
	return events

static func _offer(state, here, obs, port, mode, good, qty: int, buy: int, sell: int, ctx) -> Dictionary:
	var purchase := buy * qty
	var revenue := sell * qty
	var age := int(ctx.age)
	var route = ctx.route
	var preparation := _preparation(state, here, mode, good, qty, purchase, ctx)
	var need := _as_dict(_as_dict(obs.get("needs")).get(good))
	var margin := ceili(float(revenue) * _uncertainty(age))
	var flags := {
		"blockade": bool(_assess_port(state, port).active) or (not here.is_empty() and bool(_assess_port(state, here).active)),
		"stale": age > 0, "shortFuel": float(preparation.fuelShortfall) > 0.0001,
		"noPath": bool(route.get("noPath", false)), "fuelUnpriced": here.is_empty(),
		"hostileWaters": _player_hostile(state, str(obs.get("faction", port.get("faction", "")))),
		"shortFood": float(preparation.foodShortfall) > 0.0001,
		"shortFunding": int(preparation.fundingShortfall) > 0,
		"preparationHold": float(preparation.allowanceOverload) > 0.001,
	}
	preparation.preparationReady = bool(preparation.preparationReady) and not bool(flags.blockade) and not bool(flags.hostileWaters) and not bool(flags.noPath)
	var row := {
		"ok": true, "estimate": true, "guaranteed": false, "coinsMoved": false, "goodsMoved": false,
		"mode": mode, "good": good, "qty": qty, "fromPort": str(here.get("id", "")), "toPort": str(port.get("id", "")),
		"buyQuote": buy, "sellQuote": sell, "spread": sell - buy, "revenue": revenue, "purchaseCost": purchase,
		"wageCost": int(ctx.wage), "dailyWages": int(ctx.wages), "fuelDrums": float(ctx.drums), "fuelCost": int(ctx.fuel),
		"foodCost": int(ctx.foodCost), "tripCost": int(ctx.trip), "netProfit": revenue - purchase - int(ctx.trip),
		"businessFunds": int(ctx.funds), "buyerLiquidity": int(ctx.liquidity), "freeCapacity": float(ctx.free),
		"days": float(ctx.days), "distance": float(ctx.distance), "speed": float(ctx.speed),
		"path": str(route.get("path", "straight")), "quoteAge": age, "uncertainty": _uncertainty(age),
		"observedDay": int(obs.get("day", 0)), "observedNeed": float(need.get("observedNeed", 0)),
		"needPurpose": str(need.get("needPurpose", "No production need recorded; revisit to refresh.")),
		"needOutput": str(need.get("needOutput", "")), "shortageReported": bool(need.get("shortageReported", false)),
		"uncertaintyMargin": margin, "conservativeNetProfit": revenue - purchase - int(ctx.trip) - margin,
		"uncertaintyBasis": "Sale revenue less ceil(revenue x visit age uncertainty: 6%/day, capped at 48%). Price sensitivity only; excludes future aging, quantity changes and access risk.",
		"localStockLimit": int(ctx.stockLimit), "affordabilityLimit": int(ctx.affordLimit), "holdLimit": int(ctx.holdLimit),
		"quantityLimitReason": "Minimum of %s, nominal funding, current hold and observed buyer purse; provisions, protected stock and legal checks may reduce actual cargo." % ("owned unsealed cargo" if mode == "carried" else "local stock"),
		"risk": "ESTIMATE", "riskFlags": flags, "message": "ESTIMATE. Nothing is transferred.",
	}
	row.merge(preparation)
	return row

static func _preparation(state, here, mode, good, qty: int, purchase: int, ctx) -> Dictionary:
	# 052 allowance is separate from the legacy out-and-back profit calculation.
	var prep: Dictionary = ctx.preparation
	var food_available := float(prep.foodAvailable)
	var loose_fuel := float(prep.looseFuel)
	if mode == "carried" and good == "food":
		food_available = maxf(0.0, food_available - qty)
	if mode == "carried" and good == "fuel":
		loose_fuel = maxf(0.0, loose_fuel - qty)
	var food_shortfall := maxf(0.0, float(prep.foodRequired) - food_available)
	var food_lots := ceili(food_shortfall)
	var fuel_lots := ceili(maxf(0.0, float(prep.fuelShortfall) - loose_fuel))
	var preparation_cost := food_lots * int(ctx.foodPrice) + fuel_lots * int(ctx.fuelPrice)
	var funding := purchase + int(prep.returnWages) + ceili(float(prep.wageArrears)) + preparation_cost
	var funding_shortfall := maxi(0, funding - int(state.get("coins", 0)))
	var payload := float(qty) * float(Goods.ITEMS[good].weight) if mode == "local_buy" else 0.0
	var fuel_overflow := 0.0
	for boat in prep.boats:
		fuel_overflow += maxf(0.0, float(boat.fuelRequired) - maxf(float(boat.loadedFuel), float(boat.tankCapacity)))
	var allowance_overload := maxf(0.0, float(prep.cargoWeight) + payload + food_lots + fuel_overflow - float(prep.usableCapacity))
	var warnings: Array = prep.warnings.duplicate()
	warnings.append("Actual market access, protected local stock and buyer funds are checked again when trading. Quotes reserve nothing.")
	var stocks := _as_dict(here.get("stocks"))
	var food_stock := int(floor(float(stocks.get("food", 0)))) - (qty if mode == "local_buy" and good == "food" else 0)
	var fuel_stock := int(floor(float(stocks.get("fuel", 0)))) - (qty if mode == "local_buy" and good == "fuel" else 0)
	var supply_short := food_lots > maxi(0, food_stock) or fuel_lots > maxi(0, fuel_stock)
	if supply_short:
		warnings.append("Local stock cannot cover this cargo plus missing food/fuel allowance; seek supplies before departure.")
	if funding_shortfall > 0:
		warnings.append("Cargo, missing provisions, allowance payroll and arrears need %d more coins before a sale." % funding_shortfall)
	if allowance_overload > 0.001:
		warnings.append("Cargo plus whole-lot food and individual tank overflow exceed active holds by %.1f." % allowance_overload)
	if mode == "carried" and good == "food":
		warnings.append("Food earmarked for sale is excluded from the return and contingency ration allowance.")
	if not here.is_empty() and float(prep.fuelShortfall) > 0.001:
		warnings.append("Loose fuel is cargo, not loaded tank fuel. Use Cargo reserves to load each boat; tank capacity may require fuel stops.")
	var reserve_cost := ceili(float(prep.reserveDays) * (float(ctx.wages) + float(ctx.food) * float(ctx.foodPrice) + _fuel_burn(state, DAY_SECONDS) * float(ctx.fuelPrice)))
	return {
		"reserveDays": float(prep.reserveDays), "contingencyCost": reserve_cost,
		"wageArrears": ceili(float(prep.wageArrears)), "preparationCost": preparation_cost,
		"fundingRequired": funding, "fundingShortfall": funding_shortfall,
		"preparationReady": bool(prep.readyForAllowance) and food_shortfall <= 0.001 and funding_shortfall == 0 and allowance_overload <= 0.001 and not supply_short and not here.is_empty(),
		"foodRequired": float(prep.foodRequired), "foodShortfall": food_shortfall,
		"fuelShortfall": float(prep.fuelShortfall), "looseFuel": loose_fuel,
		"allowanceOverload": allowance_overload, "payloadAfterFood": maxf(0.0, float(prep.usableCapacity) - float(prep.cargoWeight) - food_lots - fuel_overflow),
		"boatFuel": prep.boats.duplicate(true), "preparationWarnings": warnings,
	}

static func _better(current, offer) -> Dictionary:
	if current.is_empty() or int(offer.netProfit) > int(current.netProfit):
		return offer
	return current

static func _assess_port(state, port) -> Dictionary:
	var faction := str(port.get("faction", ""))
	var best_id := ""
	var best_force := 0.0
	var opposition := 0.0
	for owner in state.get("fleetOwners", []):
		if not owner is Dictionary or _story(owner):
			continue
		var sup := _supplied(owner)
		var near := _near_owner(state, owner, port)
		if not near or int(sup.boats) < 1:
			continue
		if _relation(state, str(owner.get("faction", "")), faction) <= Factions.ENEMY_AT:
			if float(sup.force) > best_force:
				best_force = float(sup.force)
				best_id = str(owner.get("id", ""))
		else:
			opposition += float(sup.force)
	opposition += _player_force(state, port)
	var enough := best_id != "" and best_force >= FORCE_MIN
	var active := enough and opposition < best_force
	var cause := "clear"
	if active:
		cause = "established"
	elif enough and opposition >= best_force:
		cause = "contested"
	return {"active": active, "cause": cause, "ownerId": best_id, "hostileForce": best_force, "oppositionForce": opposition}

static func _lift_cause(state, prev, now) -> String:
	if str(now.cause) == "contested":
		return "contested"
	var owner := _owner(state, str(prev.get("ownerId", "")))
	if owner.is_empty():
		return "lost"
	var sup := _supplied(owner)
	if int(sup.boats) < 1 or float(sup.force) < FORCE_MIN:
		return "lost"
	return "withdrawn"

static func _supplied(owner) -> Dictionary:
	var force := 0.0
	var boats := 0
	if not bool(owner.get("active", true)):
		return {"boats": 0, "force": 0.0}
	for boat in owner.get("boats", []):
		if not boat is Dictionary or bool(boat.get("sunk", false)):
			continue
		if float(boat.get("crew", 0)) < maxf(1.0, float(boat.get("crewMin", 1))):
			continue
		if float(boat.get("fuel", 0)) < FUEL_MIN or float(boat.get("ammo", 0)) < AMMO_MIN:
			continue
		boats += 1
		force += maxf(1.0, float(boat.get("hp", 40.0)) / 40.0)
	return {"boats": boats, "force": force}

static func _near_owner(state, owner, port) -> bool:
	var pid := str(port.get("id", ""))
	var patrol = {}
	for row in state.get("patrols", []):
		if row is Dictionary and str(row.get("id", "")) == str(owner.get("id", "")):
			patrol = row
			break
	if not patrol.is_empty() and patrol.has("active") and not bool(patrol.active):
		return false
	if patrol.has("x") and port.has("x"):
		return _dist(patrol,port)<=NEAR_PORT
	return str(owner.get("atPort", "")) == pid

static func _player_force(state, port) -> float:
	var pos = state.get("position", {})
	if not pos is Dictionary or not pos.has("x") or not port.has("x") or _dist(pos, port) > NEAR_PORT:
		return 0.0
	if _player_hostile(state, str(port.get("faction", ""))):
		return 0.0
	var boats = []
	for boat in state.get("fleet", []):
		if boat is Dictionary and not bool(boat.get("sunk", false)) and not bool(boat.get("mothballed", false)) and str(boat.get("storedPort", "")) == "":
			boats.append(boat)
	return float(_supplied({"active": true, "boats": boats}).force)

static func _player_hostile(state, faction) -> bool:
	if faction == "" or not state.get("relationships") is Dictionary:
		return false
	return Factions.is_hostile(state, faction)

static func _relation(state, a, b) -> int:
	if a == "" or b == "" or a == b:
		return 0
	if state.get("relationships") is Dictionary and state.relationships.get("pairs") is Dictionary:
		return int(Factions.relation(state, a, b))
	return int(Factions.PAIR_BASE.get(Factions._pair_key(a, b), 0))

static func _travel_speed(state, world) -> float:
	var powered := 0.0
	var tow := 0.0
	var speed := 170.0
	var any := false
	for boat in state.get("fleet", []):
		if not _afloat(boat):
			continue
		var spec = boat.get("spec", {})
		var size := float(spec.get("size", 14))
		if bool(boat.get("mothballed", false)) or bool(boat.get("needsHarborRepair", false)) or float(boat.get("crew", 0)) < float(boat.get("crewMin", 1)):
			tow += size
			continue
		powered += size
		any = true
		var fuel_scale := 1.0 if float(boat.get("fuel", 0)) > 0.0 else 0.3
		speed = minf(speed, float(spec.get("speed", 0)) * _speed_factor(boat) * fuel_scale)
	if not any:
		return 0.0
	return speed * SPEED_SCALE * float(world.get("CAMPAIGN_SCALE", 1.0)) * powered / maxf(1.0, powered + tow * 0.8)

static func _speed_factor(boat) -> float:
	if not boat.has("maxHp") or not boat.has("water") or not boat.has("capacity") or not boat.get("breaches") is Array:
		return 1.0
	if not boat.has("policy") or not boat.has("engine") or not boat.has("crewMin"):
		return 1.0
	return maxf(0.25, float(Damage.get_status(boat).get("speedFactor", 1.0)))

static func _fuel_burn(state, seconds: float) -> float:
	var burned := 0.0
	for boat in state.get("fleet", []):
		if not _traveling(boat):
			continue
		var spec = boat.get("spec", {})
		var rate := (0.011 + float(spec.get("size", 14.0)) * 0.0002) * maxf(0.2, float(spec.get("fuelUse", 1.0)))
		burned += rate * maxf(0.0, seconds)
	return burned

static func _fuel_aboard(state) -> float:
	var total := 0.0
	for boat in state.get("fleet", []):
		if _traveling(boat):
			total += maxf(0.0, float(boat.get("fuel", 0)))
	return total

static func _capacity(state) -> float:
	var total := 0.0
	for boat in state.get("fleet", []):
		if _traveling(boat):
			total += maxf(0.0, float(boat.get("spec", {}).get("cargo", 0)))
	return total

static func _cargo_weight(state) -> float:
	var total := 0.0
	var cargo = state.cargo if state.get("cargo") is Dictionary else {}
	for key in Goods.ITEMS:
		total += maxf(0.0, float(cargo.get(key, 0))) * float(Goods.ITEMS[key].weight)
	var freight = state.get("freight", {})
	if freight is Dictionary and not freight.is_empty():
		var good := str(freight.get("good", ""))
		var weight := float(Goods.ITEMS[good].weight) if Goods.ITEMS.has(good) else 1.0
		total += maxf(0.0, float(freight.get("qty", 0))) * weight
	for boat in state.get("fleet", []):
		if not _afloat(boat):
			continue
		var spec = boat.get("spec", {})
		total += maxf(0.0, float(boat.get("fuel", 0)) - float(spec.get("fuelCapacity", 60)))
		total += maxf(0.0, float(boat.get("supplies", 0)) - float(spec.get("kitCapacity", 20)))
		total += maxf(0.0, float(boat.get("ammo", 0)) - float(spec.get("ammoCapacity", 80))) / float(Goods.ROUNDS_PER_CASE)
	return total

static func _sellable(state) -> Dictionary:
	# Sealed job freight has its own ledger and never enters player-owned cargo.
	return state.cargo.duplicate() if state.get("cargo") is Dictionary else {}

static func _route(nav, a, b) -> Dictionary:
	var straight := _dist(a, b)
	if not nav.get("nodes") is Array or nav.nodes.is_empty():
		return {"distance": straight, "path": "straight", "noPath": false}
	var path = Navigation.find_path(nav, {"x": a.x, "y": a.y}, {"x": b.x, "y": b.y})
	if path.size() < 2:
		return {"distance": straight, "path": "straight", "noPath": true}
	var length := 0.0
	for i in range(1, path.size()):
		length += _dist(path[i - 1], path[i])
	return {"distance": length, "path": "water", "noPath": false}

static func _scarcity(obs) -> Dictionary:
	var ghost := {
		"industry": str(obs.get("industry", "trade")),
		"specialty": str(obs.get("specialty", "")),
		"population": float(obs.get("population", 1200)),
		"wealth": float(obs.get("wealth", 1)),
	}
	var stocks = obs.get("stocks", {})
	var goods := {}
	var worst_ratio := 99.0
	var summary := "stocked"
	for good in Goods.ITEMS:
		var stock := int(stocks.get(good, 0))
		var eq := int(Economy.get_equilibrium_stock(ghost, good))
		var ratio := float(stock) / maxf(1.0, float(eq))
		var band := "stocked"
		if ratio < 0.55:
			band = "scarce"
		elif ratio > 1.45:
			band = "surplus"
		goods[good] = {"stock": stock, "equilibrium": eq, "band": band}
		if ratio < worst_ratio:
			worst_ratio = ratio
			summary = band
	return {"goods": goods, "summary": summary}

static func _observed_needs(port: Dictionary) -> Dictionary:
	# Snapshot only on a visit. A restock gap is not an order or future demand.
	var industry := str(port.get("industry", "trade"))
	var ind: Dictionary = Economy.INDUSTRIES.get(industry, Economy.INDUSTRIES.trade)
	var recipes := Economy._build_recipes(ind, str(port.get("specialty", "")))
	var outputs := {}
	for recipe in recipes:
		var output := str(recipe.get("good", ""))
		if not Goods.ITEMS.has(output):
			continue
		for input in Goods.ITEMS[output].inputs:
			if not outputs.has(input) or output == str(port.get("specialty", "")):
				outputs[input] = output
	var shortages: Array = port.get("shortages", []) if port.get("shortages") is Array else []
	var needs := {}
	var stocks := _as_dict(port.get("stocks"))
	for good in Goods.ITEMS:
		var output := str(outputs.get(good, ""))
		var reported := shortages.has(good)
		if output == "" and not reported and good != "food":
			continue
		var gap := maxf(0.0, float(Economy.get_equilibrium_stock(port, good)) - maxf(0.0, float(stocks.get(good, 0))))
		var purpose := "Reported local shortage; specific use not recorded."
		if output != "":
			purpose = "%.2f input lots per %s lot in the local paid recipe; other inputs, workers and wages still required." % [float(Goods.ITEMS[output].inputs[good]), str(Goods.ITEMS[output].name)]
		elif good == "food":
			purpose = "Rations for local households and workforce."
		purpose += " Need is the observed stock gap to the existing equilibrium, not a purchase order."
		needs[good] = {"observedNeed": gap, "needPurpose": purpose, "needOutput": output, "shortageReported": reported}
	return needs

static func _repair_obs(row) -> void:
	row.day = int(floor(float(row.get("day", 0))))
	row.seq = int(row.get("seq", 0))
	row.businessFunds = maxi(0, int(round(float(row.get("businessFunds", 0)))))
	# Old saves have no need snapshot; never reconstruct it from a live port.
	if not row.get("needs") is Dictionary:
		row.needs = {}
	var needs := {}
	for good in Goods.ITEMS:
		var need := _as_dict(row.needs.get(good))
		if not need.is_empty():
			var amount := float(need.get("observedNeed", 0))
			needs[good] = {"observedNeed": maxf(0.0, amount) if is_finite(amount) else 0.0,
				"needPurpose": str(need.get("needPurpose", "")), "needOutput": str(need.get("needOutput", "")),
				"shortageReported": bool(need.get("shortageReported", false))}
	row.needs = needs
	for key in ["stocks", "buy", "sell"]:
		if not row.get(key) is Dictionary:
			row[key] = {}
			continue
		for good in row[key].keys():
			row[key][good] = maxi(0, int(floor(float(row[key][good]))))

static func _trim(book) -> void:
	var obs = book.observations
	while obs.size() > MAX_OBSERVATIONS:
		var oldest := ""
		var seq := 0x7fffffff
		for key in obs.keys():
			var n := int(obs[key].get("seq", 0))
			if oldest == "" or n < seq:
				seq = n
				oldest = str(key)
		if oldest == "":
			break
		obs.erase(oldest)
	while book.events.size() > MAX_EVENTS:
		book.events.pop_back()

static func _as_dict(value) -> Dictionary:
	return value if value is Dictionary else {}

static func _bundle(core) -> Dictionary:
	if core is Dictionary and not (core.get("state") is Dictionary and not core.has("ports")):
		return {"state": core, "world": _as_dict(core.get("world")), "nav": _as_dict(core.get("nav"))}
	var bag = core
	if not core is Dictionary and core != null:
		bag = {"state": core.get("state"), "world": core.get("data") if core.get("data") is Dictionary else core.get("world"), "nav": core.get("nav")}
	return {"state": _as_dict(bag.get("state") if bag is Dictionary else {}), "world": _as_dict(bag.get("world") if bag is Dictionary else {}), "nav": _as_dict(bag.get("nav") if bag is Dictionary else {})}

static func _port_dict(state, port) -> Dictionary:
	if port is Dictionary and str(port.get("id", "")) != "":
		return port
	var id := str(port)
	for row in state.get("ports", []):
		if row is Dictionary and str(row.get("id", "")) == id:
			return row
	return {}

static func _current_port(state) -> Dictionary:
	var pos = state.get("position", {})
	if not pos is Dictionary or not pos.has("x"):
		return {}
	var best = {}
	for port in state.get("ports", []):
		if port is Dictionary and port.has("x") and _dist(pos, port) < DOCK_RADIUS:
			best = port
			break
	return best

static func _owner(state, id) -> Dictionary:
	if id == "":
		return {}
	for owner in state.get("fleetOwners", []):
		if owner is Dictionary and str(owner.get("id", "")) == id:
			return owner
	return {}

static func _story(owner) -> bool:
	return str(owner.get("id", "")).begins_with(STORY_PREFIX)

static func _afloat(boat) -> bool:
	return boat is Dictionary and not bool(boat.get("sunk", false)) and str(boat.get("storedPort", "")) == ""

static func _traveling(boat) -> bool:
	return _afloat(boat) and not bool(boat.get("mothballed", false)) and not bool(boat.get("needsHarborRepair", false)) and float(boat.get("crew", 0)) >= float(boat.get("crewMin", 1))

static func _today(state) -> int:
	return int(floor(float(state.get("day", 1))))

static func _uncertainty(age: int) -> float:
	return clampf(float(age) * UNCERTAINTY_PER_DAY, 0.0, UNCERTAINTY_CAP)

static func _dist(a, b) -> float:
	var dx := float(a.get("x", 0)) - float(b.get("x", 0))
	var dy := float(a.get("y", 0)) - float(b.get("y", 0))
	return sqrt(dx * dx + dy * dy)

static func _int_map(raw) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for key in raw.keys():
			out[key] = int(raw[key])
	return out
