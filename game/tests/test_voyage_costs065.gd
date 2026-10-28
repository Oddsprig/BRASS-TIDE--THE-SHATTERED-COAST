extends SceneTree
## Source fixture, unrun by the helper. Root owns all native execution.
## One real initialized career/context; controlled detached origins, debt,
## damage and staged canonical hulls. No campaign tick or earned-voyage claim.
const Campaign = preload("res://scripts/campaign.gd")
const Costs = preload("res://scripts/voyage_costs065.gd")
const OceanWorld = preload("res://scripts/ocean_world064.gd")
const Expedition = preload("res://scripts/expedition.gd")
const Economy = preload("res://scripts/economy.gd")
const Identity = preload("res://scripts/fleet_identity.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
var c
var baseline: Dictionary = {}
var checks: int = 0
var failures: int = 0
var started: int = 0


func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL voyage costs065: ", message)
	return condition


func _initialize() -> void:
	started = Time.get_ticks_msec()
	var world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	if not check(world is Dictionary, "Actual home catalog loads"):
		finish()
		return
	c = Campaign.new(world)
	var seeded: Dictionary = c.new_game(65001)
	if not check(bool(seeded.get("ok", false)) and not c.ocean_context064.is_empty(), "Normal career publication initializes the actual fleet and shared 064 geometry"):
		finish()
		return
	baseline = c.state.duplicate(true)
	if not check(EquipmentDamage.inspect_owner(c.state.fleet[0]).get("mode") == "canonical", "Baseline hull has real canonical equipment"):
		finish()
		return
	_routes()
	_accounting()
	_stores()
	_damage()
	_refusals()
	finish()


func finish() -> void:
	print("voyage costs065: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func reset() -> void:
	c.state = baseline.duplicate(true)
	c.pending_days = 0
	c.events.clear()
	c.travel_lock064 = ""


func remote_intent() -> Dictionary:
	return {"targetRegionId": OceanWorld.REMOTE, "targetApproachId": "north", "outExit": "north", "backExit": "south", "homeEntry": "south", "returnPortId": str(c.data.START.port), "idleDays": 0.0}


func home_intent() -> Dictionary:
	return {"targetRegionId": OceanWorld.HOME, "targetApproachId": "", "outExit": "", "backExit": "", "homeEntry": "", "returnPortId": str(c.data.START.port), "idleDays": 0.0}


func quoted(intent: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	if Time.get_ticks_msec() - started >= 55000:
		check(false, "Source fixture exceeded its 55-second body budget")
		return {"ok": false, "routeOk": false, "readyForAllowance": false, "nextAction": {"kind": "none"}}
	var runtime: Dictionary = {"speed": c.travel_speed(), "clearance": c.Routes.clearance(c), "blocker": c.transition_blocker064()}
	for key in overrides:runtime[key] = overrides[key]
	# Bytes retain key/value types, physical UIDs, purses and optional records.
	var before: Array = [var_to_bytes(c.state), var_to_bytes(c.data), var_to_bytes(c.ocean_context064), var_to_bytes(intent), var_to_bytes(runtime)]
	var result: Dictionary = Costs.quote(c.state, c.data, c.ocean_context064, intent, runtime)
	check(before[0] == var_to_bytes(c.state), "Quote preserves every actual state field, including pending accounts and sealed freight")
	check(before[1] == var_to_bytes(c.data) and before[2] == var_to_bytes(c.ocean_context064), "Quote preserves the catalog and both shared navigation graphs")
	check(before[3] == var_to_bytes(intent) and before[4] == var_to_bytes(runtime), "Quote preserves player choices and actual runtime inputs")
	check(plain(result), "Every returned key is String and all returned numbers are finite")
	return result


func plain(value) -> bool:
	if value == null or value is bool or value is String:return true
	if value is int or value is float:return is_finite(float(value))
	if value is Array:
		for child in value:
			if not plain(child):return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not plain(value[key]):return false
		return true
	return false


func put_location(location: Dictionary) -> void:
	for key in ["world064", "position", "heading", "path", "destination"]:
		c.state[key] = location[key].duplicate(true) if location[key] is Dictionary or location[key] is Array else location[key]


func at_gate(region_id: String, approach_id: String, ocean: bool = false, offset: Dictionary = {"x": 0.0, "y": 0.0}) -> bool:
	# Controlled unit origins come from the real catalog and are publicly validated.
	var region: Dictionary = c.ocean_context064.regions[region_id]
	for gate in region.approaches:
		if gate.id != approach_id:continue
		var location: Dictionary = {"world064": {"schema": 1, "layer": str(region.layer), "regionId": region_id},
			"position": {"x": float(gate.position.x) + float(offset.x), "y": float(gate.position.y) + float(offset.y)}, "heading": 0.0, "path": [], "destination": ""}
		var prepared: Dictionary = OceanWorld.prepare(location, c.ocean_context064, c.Routes.clearance(c))
		if not check(prepared.ok, "Controlled actual gate origin is safe"):return false
		if ocean:
			prepared = OceanWorld.transition(c.ocean_context064, prepared.location, region_id, approach_id, c.Routes.clearance(c), "")
			if not check(prepared.ok, "Ocean origin comes from the exact public paired transfer"):return false
		put_location(prepared.location)
		return true
	return check(false, "Actual gate exists")


func verify_legs(q: Dictionary) -> void:
	var cursor: Dictionary = {"world064": q.origin.world064.duplicate(true), "position": q.origin.position.duplicate(true), "heading": 0.0, "path": [], "destination": ""}
	var scale: float = float(c.ocean_context064.ocean.localUnitsPerUnit)
	var total: float = 0.0
	for leg in q.legs:
		check(cursor.position == leg.from and cursor.world064.layer == leg.layer, "Each leg starts at the exact reached previous position on the correct layer")
		if leg.kind == "transition":
			var transfer: Dictionary = OceanWorld.transition(c.ocean_context064, cursor, str(leg.transferRegionId), str(leg.approachId), c.Routes.clearance(c), "")
			if not check(transfer.ok, "Each forecast transfer passes the real public spatial guard"):return
			check(transfer.location.position == leg.to and transfer.location.world064.regionId == leg.toRegionId, "Transfer retains the paired exact position and target identity")
			check(leg.physicalDistance == 0.0 and leg.seconds == 0.0, "A chart change adds no physical travel or time")
			cursor = transfer.location
			continue
		var target: Dictionary = leg.to
		if leg.layer == "home" and not str(leg.destination).is_empty():
			target = c.ocean_context064.ports[leg.destination]
		var plotted: Dictionary = OceanWorld.plot(c.ocean_context064, cursor, target, str(leg.destination), c.Routes.clearance(c))
		if not check(plotted.ok, "Forecast sailing leg is an actual safe public route"):return
		check(plotted.location.path == leg.path, "The full live plotted path is retained, excluding its actual origin")
		var chart: float = 0.0
		var previous: Dictionary = cursor.position
		for point in plotted.location.path:
			chart += Vector2(float(previous.x), float(previous.y)).distance_to(Vector2(float(point.x), float(point.y)))
			previous = point
		check(is_equal_approx(float(leg.physicalDistance), chart * (scale if leg.layer == "ocean" else 1.0)), "Ocean distance uses actual scale 10 and local/home distance uses scale 1")
		var advanced: Dictionary = OceanWorld.advance(c.ocean_context064, plotted.location, float(leg.seconds) + 0.000001, float(q.timing.speed), c.Routes.clearance(c))
		if not check(advanced.ok, "A bounded spatial-only projection can follow the estimated leg"):return
		check(advanced.location.path.is_empty() and advanced.location.position == leg.to, "Estimated travel time reaches the entire plotted leg")
		cursor = advanced.location
		total += float(leg.physicalDistance)
	check(is_equal_approx(total, float(q.distances.total)), "Physical leg totals match the quote")
	check(cursor.world064.layer == "home" and c.distance(cursor.position, c.port(str(q.intent.returnPortId))) < 65.0, "The independently routed itinerary ends at the real selected home harbor")


func _routes() -> void:
	reset()
	var intent: Dictionary = remote_intent()
	var north: Dictionary = quoted(intent)
	if not check(north.ok and north.routeOk, "Home north departure and explicit south return are routable"):return
	var canonical_report: Dictionary = Expedition.report(c.state, c.data, float(north.distances.outward), float(north.timing.speed),
		{"outwardDays": float(north.timing.outwardDays), "returnDays": float(north.timing.returnDays), "shoreDays": 0.0, "foodCredit": float(c.state.surveyFoodCredit)})
	check(north.allowance == canonical_report, "Every original canonical allowance field and traveling-boat row stays intact")
	check(north.nextAction.kind == "course" and north.nextAction.destination == "" and north.nextAction.target == c.ocean_context064.regions[OceanWorld.HOME].approaches[0].position, "The first home action targets only the selected north gate")
	check(north.legs[0].from == c.state.position, "A forecast starts at the actual current point")
	check(north.distances.byLayer.home > 0 and north.distances.byLayer.local > 0 and north.distances.byLayer.ocean > 0, "All three physical distance layers are represented")
	check(not is_equal_approx(float(north.distances.outward), float(north.distances["return"])), "The explicit return is independently routed, not outward multiplied by two")
	verify_legs(north)
	intent.outExit = "south"
	intent.targetApproachId = "south"
	intent.backExit = "north"
	intent.homeEntry = "north"
	var south: Dictionary = quoted(intent)
	if check(south.ok, "South outward and north return remain explicit reachable choices"):
		check(south.nextAction.target == c.ocean_context064.regions[OceanWorld.HOME].approaches[1].position, "Selecting south never swaps to a cheaper north departure")
		check(not is_equal_approx(float(north.distances.outward), float(south.distances.outward)), "Different visible choices refresh physical route distances")
		verify_legs(south)
	if not at_gate(OceanWorld.HOME, "north", false, {"x": 12.0, "y": 5.0}):return
	intent = remote_intent()
	var crossing: Dictionary = quoted(intent)
	if check(crossing.ok, "An already reached off-center departure has a forecast"):
		check(crossing.nextAction.kind == "transition" and crossing.nextAction.regionId == OceanWorld.HOME and crossing.nextAction.target == {}, "Only the unresolved real Core departure transfer is next")
		check(crossing.legs[0].kind == "transition" and crossing.legs[0].from == c.state.position, "An immediate crossing preserves the actual off-center origin")
		verify_legs(crossing)
	if not at_gate(OceanWorld.HOME, "north", true):return
	intent.outExit = ""
	var ocean: Dictionary = quoted(intent)
	if check(ocean.ok, "An actual ocean origin routes outward and home"):
		check(ocean.nextAction.kind == "course" and ocean.nextAction.destination == "approach:glasswind_keys:north", "Ocean action is the chosen projected approach course")
		verify_legs(ocean)
	if not at_gate(OceanWorld.REMOTE, "north", false, {"x": 9.0, "y": 4.0}):return
	var reached: Dictionary = quoted(intent)
	check(reached.ok and reached.nextAction.kind == "none" and reached.distances.outward == 0.0, "A reached remote target offers no automatic return action")
	intent.targetApproachId = "south"
	var local: Dictionary = quoted(intent)
	check(local.ok and local.nextAction.kind == "course" and local.nextAction.destination == "approach:glasswind_keys:south", "A same-region choice is a real local path")
	var home: Dictionary = home_intent()
	home.outExit = "south"
	home.targetApproachId = "north"
	var returning: Dictionary = quoted(home)
	if check(returning.ok, "Choosing home explicitly routes the actual return as outward actions"):
		check(returning.distances["return"] == 0.0 and returning.legs[-1].destination == c.data.START.port, "A home target includes the final safe harbor sail")
		verify_legs(returning)
	if not at_gate(OceanWorld.HOME, "north"):return
	home = home_intent()
	var harbor: Dictionary = quoted(home)
	check(harbor.ok and harbor.nextAction.kind == "course" and harbor.nextAction.destination == c.data.START.port and harbor.nextAction.target == c.ocean_context064.ports[c.data.START.port], "After home entry the next action is the real harbor course")
	reset()
	var docked: Dictionary = quoted(home_intent())
	check(docked.ok and docked.nextAction.kind == "none" and docked.distances.total == 0.0, "Already at the selected home harbor needs no repeated gate detour")
	# A caller can edit a returned nested row without modifying any live input.
	north.origin.position.x += 1.0
	north.allowance.boats[0].loadedFuel = 0.0
	north.stores.cargoManifest.clear()
	check(var_to_bytes(c.state) == var_to_bytes(baseline), "Returned origin, allowance rows and manifest are fully detached")


func _accounting() -> void:
	reset()
	# Controlled debt case: designate an existing crew berth, using the real optional
	# record initializer. This is not a paid hiring/professional progression test.
	c.state.specialists = [{"id": "specialist-1", "boatUid": str(c.state.fleet[0].uid), "role": "surveyor", "arrears": 97}]
	Identity.ensure(c.state)
	c.state.day = 12.9
	c.state.econDay = 10
	c.pending_days = 1 # Another pending day may already be in flight; never add this.
	c.state.wageArrears = 73
	var upkeep: Dictionary = Economy.daily_upkeep(c.state.fleet)
	c.state.surveyFoodCredit = float(upkeep.food) * 2.5
	var intent: Dictionary = home_intent()
	intent.idleDays = 0.2
	var q: Dictionary = quoted(intent)
	if not check(q.ok, "Pending and boundary accounting produces a read-only quote"):return
	check(q.expected.pendingDays == 2 and q.expected.futurePayrollDays == 1 and q.expected.totalPayrollDays == 3, "The actual day/econDay gap includes in-flight settlement once")
	check(q.expected.byPhase.pending.payrollDays == 2 and q.expected.byPhase.outward.payrollDays == 0 and q.expected.byPhase.idle.payrollDays == 1 and q.expected.byPhase["return"].payrollDays == 0, "Integer crossings belong to their chronological phase")
	check(q.expected.byPhase.pending.food == 0.0 and is_equal_approx(float(q.expected.byPhase.idle.food), float(upkeep.food) * 0.5), "Prepaid food is used once, pending first, then future consumption")
	check(q.expected.baseWages == float(upkeep.wages) * 3 and q.expected.premiums == 225 and q.expected.premiumArrearsPaid == 97, "Base crew wages, three real premiums and old premium arrears are distinct")
	check(q.expected.coinsRequired == float(upkeep.wages) * 3 + 225 + 97, "Existing base arrears are not silently paid by expected daily ticks")
	check(q.allowance.payrollDays == 6 and q.funding.requiredCoins == q.allowance.returnWages + 73 + 97, "Rounded six-day allowance funds existing base and premium arrears exactly once")
	check(is_equal_approx(float(q.timing.endDay), 13.1) and is_equal_approx(float(q.allowance.tripDays), 4.2), "Future calendar time excludes accrued pending days and the report retains its contingency")
	var sums: Dictionary = {"payrollDays": 0.0, "food": 0.0, "baseWages": 0.0, "premiums": 0.0, "premiumArrearsPaid": 0.0, "coinsRequired": 0.0}
	for phase in q.expected.byPhase.values():
		for key in sums:sums[key] += float(phase[key])
	check(sums.payrollDays == q.expected.totalPayrollDays, "Phase payroll days sum to total expected days")
	for key in ["food", "baseWages", "premiums", "premiumArrearsPaid", "coinsRequired"]:check(is_equal_approx(float(sums[key]), float(q.expected[key])), "Phase sum matches aggregate " + key)
	c.state.day = 12.8
	c.state.econDay = 12
	intent.idleDays = 0.1
	var fraction: Dictionary = quoted(intent)
	check(fraction.ok and fraction.expected.totalPayrollDays == 0 and fraction.expected.coinsRequired == 0 and fraction.expected.premiumArrearsPaid == 0, "A future fractional interval with no crossed day does not invent a debit or arrears payment")
	reset()
	intent = remote_intent()
	var route: Dictionary = quoted(intent)
	if not route.ok:return
	c.state.day = 20.0 + fposmod(1.0 - fposmod(float(route.timing.outwardDays), 1.0) - 0.0001, 1.0)
	c.state.econDay = 20
	intent.idleDays = 0.0002
	var boundary: Dictionary = quoted(intent)
	check(boundary.ok and boundary.expected.byPhase.idle.payrollDays == 1, "A day crossing between movement phases is counted during idle, without rounding each leg upward")
	if boundary.ok:
		check(boundary.expected.totalPayrollDays == floorf(float(boundary.timing.endDay)) - 20, "Trip payroll follows the one actual calendar, not per-leg ceilings")


func add_fixture_boat(hull_id: String, crew: int) -> Dictionary:
	var spec: Dictionary = c.hull(hull_id)
	var stage: Dictionary = c.Lifecycle.stage_birth(c.state, c.data, spec, "boat-%d" % int(c.state.nextUid))
	if not check(bool(stage.get("ok", false)), "Controlled hull uses real staged birth and unique physical equipment"):return {}
	var boat: Dictionary = c.add_boat(spec, crew, stage)
	check(not boat.is_empty() and EquipmentDamage.inspect_owner(boat).get("mode") == "canonical", "Controlled hull is canonically initialized through normal publication")
	return boat


func row_for(rows: Array, uid: String) -> Dictionary:
	for row in rows:
		if row.uid == uid:return row
	return {}


func _stores() -> void:
	reset()
	var tanker: Dictionary = add_fixture_boat("seepoil_tanker", 5)
	var tow: Dictionary = add_fixture_boat("tin_skiff", 0)
	var repair: Dictionary = add_fixture_boat("tin_skiff", 3)
	var mothball: Dictionary = add_fixture_boat("tin_skiff", 3)
	var stored: Dictionary = add_fixture_boat("tin_skiff", 3)
	if tanker.is_empty() or tow.is_empty() or repair.is_empty() or mothball.is_empty() or stored.is_empty():return
	# Controlled inventory, not earned purchases. No preview may redistribute it.
	c.state.fleet[0].fuel = 0.0
	tanker.fuel = float(tanker.spec.fuelCapacity)
	tow.mothballed = false
	tow.towed = true
	tow.fuel = 0.1
	repair.needsHarborRepair = true
	repair.fuel = 0.1
	mothball.mothballed = true
	mothball.fuel = 7.0
	stored.storedPort = str(c.data.START.port)
	c.state.cargo.fuel = 8.0
	var q: Dictionary = quoted(remote_intent())
	if not check(q.ok and q.routeOk and not q.readyForAllowance, "Real per-hull shortages retain a usable route estimate"):return
	var escort_row: Dictionary = row_for(q.stores.boats, str(c.state.fleet[0].uid))
	check(escort_row.loadedFuel == 0 and escort_row.loadedShortfall == escort_row.fuelRequired and q.stores.looseFuel == 8, "Cargo reserves and a fueled tanker cannot disguise the empty escort tank")
	check(row_for(q.stores.boats, str(tanker.uid)).loadedFuel == tanker.fuel, "The tanker's physical working stock is shown without sharing it")
	var extra_required: float = 0.0
	for boat in [tow, repair]:
		var row: Dictionary = row_for(q.stores.boats, str(boat.uid))
		check(not row.is_empty() and not row.traveling and row.burnsWhileMoving and row.fuelRequired > 0.0, "Undercrewed and repair-only fueled tows remain actual burners outside report.boats")
		check(row_for(q.allowance.boats, str(boat.uid)).is_empty(), "The existing report's traveling rows remain intact")
		extra_required += float(row.fuelRequired)
	var inactive: Dictionary = row_for(q.stores.boats, str(mothball.uid))
	check(not inactive.burnsWhileMoving and inactive.loadedFuel == 7.0 and inactive.fuelRequired == 0.0, "A present nonburning hull retains inventory without a moving-fuel charge")
	check(row_for(q.stores.boats, str(stored.uid)).is_empty(), "Stored hull fuel cannot join the present fleet")
	check(is_equal_approx(float(q.stores.fuelRequired), float(q.allowance.fuelRequired) + extra_required), "Moving-tow requirements add once to the canonical report's fuel")
	var assigned: float = float(q.stores.unassigned.get("fuel", 0.0))
	var shortfall: float = 0.0
	var tank_shortfall: float = 0.0
	for row in q.stores.boats:
		assigned += float(row.cargoFuel)
		shortfall += float(row.loadedShortfall)
		tank_shortfall += float(row.tankShortfall)
		check(is_equal_approx(float(row.fuelRequired), float(row.outwardFuel) + float(row.returnFuel) + float(row.contingencyFuel)), "Per-boat outward, return and contingency stay separate")
	check(is_equal_approx(assigned, float(q.stores.looseFuel)), "Per-hull cargo assignments and unassigned fuel partition loose cargo, not extra stock")
	check(is_equal_approx(shortfall, float(q.stores.loadedShortfall)) and is_equal_approx(tank_shortfall, float(q.stores.tankShortfall)), "Shortfall totals use actual burner and nonburner rows")
	check(q.expected.baseWages == float(Economy.daily_upkeep(c.state.fleet).wages) * float(q.expected.totalPayrollDays), "Owned stored and inactive crew are already included once in actual upkeep")
	check(q.maintenance.usageKnown and q.maintenance.expectedSupplies == 0.0, "Healthy dry initialized hulls have zero no-new-damage repair use even with few loaded kits")


func _damage() -> void:
	reset()
	var intent: Dictionary = remote_intent()
	var healthy: Dictionary = quoted(intent)
	if not healthy.ok:return
	var boat: Dictionary = c.state.fleet[0]
	var snap: Dictionary = EquipmentDamage.Records.snapshot(boat)
	var hit: Dictionary = EquipmentDamage.Core.apply_component_damage(boat.moduleCondition, {"itemUid": str(snap.installed.engine.itemUid), "loss": 0.5})
	if not check(hit.ok and EquipmentDamage.Records.publish(boat).ok, "Damage fixture uses canonical installed-engine damage and publication"):return
	var damaged: Dictionary = quoted(intent)
	check(damaged.ok and damaged.timing.speed < healthy.timing.speed and damaged.timing.movingSeconds > healthy.timing.movingSeconds, "Actual damaged fleet speed makes the voyage longer")
	check(damaged.ok and damaged.stores.fuelRequired > healthy.stores.fuelRequired, "Longer moving time increases the same authoritative per-boat fuel allowance")
	check(damaged.ok and not damaged.maintenance.usageKnown and damaged.maintenance.expectedSupplies == null and damaged.maintenance.boats[0].modules.engine.hp == 0.5, "Damaged maintenance is conditional and exposes actual installed records, never a legacy scalar repair bill")
	boat.water = 2.0
	boat.vx = 2.0
	var conditional: Dictionary = quoted(intent)
	check(conditional.ok and conditional.maintenance.conditionalFuel and conditional.warnings.any(func(w):return "0.006" in str(w)), "Flooding/residual motion exposes the separate conditional fuel use, including idle")


func refuse(q: Dictionary, message: String) -> void:
	check(not q.ok and not q.routeOk and not q.readyForAllowance and q.nextAction.kind == "none", message)
	check(not str(q.get("message", "")).is_empty() and q.get("expected", {}).is_empty(), "Refusal explains the issue without a zero-cost success")


func _refusals() -> void:
	reset()
	var intent: Dictionary = remote_intent()
	intent.outExit = ""
	refuse(quoted(intent), "Missing explicit outward crossing is refused")
	intent = remote_intent()
	intent.returnPortId = "not-a-harbor"
	refuse(quoted(intent), "Missing real return harbor is refused")
	intent = remote_intent()
	intent.targetRegionId = "future-region"
	refuse(quoted(intent), "Unimplemented target regions are refused")
	intent = remote_intent()
	intent.idleDays = NAN
	refuse(quoted(intent), "Nonfinite idle time is refused")
	refuse(quoted(remote_intent(), {"speed": 0.0}), "Zero sailing speed is refused")
	refuse(quoted(remote_intent(), {"speed": INF}), "Nonfinite sailing speed is refused")
	refuse(quoted(remote_intent(), {"clearance": 100000.0}), "Unsafe/unreachable gates cannot become zero-distance success")
	c.state.fleet = []
	refuse(quoted(remote_intent()), "A missing traveling fleet is refused")
	reset()
	c.state.world064 = {"schema": 1, "layer": "local", "regionId": "unsupported"}
	refuse(quoted(remote_intent()), "Unsupported current chart identity is refused")
	reset()
	c.state.fleet[0].fuel = NAN
	refuse(quoted(remote_intent()), "Nonfinite physical boat stores are refused")
	reset()
	var blocked: Dictionary = quoted(remote_intent(), {"blocker": "A live hostile pursuit must be resolved before changing charts."})
	check(blocked.ok and blocked.routeOk and not blocked.readyForAllowance and blocked.nextAction.kind == "course", "A transition blocker is advisory to the route and does not replace an ordinary escape course")
	var harbor: Dictionary = c.port(str(c.data.START.port))
	# Reputation deltas are capped. Use bounded real adjustments, not a guessed
	# one-call drop or direct edits to the standing book's derived band.
	for _piece in range(8):
		var adjusted: Dictionary = c.Factions.adjust(c.state, str(harbor.faction), -c.Factions.DELTA_CAP, "Controlled voyage-access fixture")
		if not check(adjusted.ok, "Controlled standing adjustment follows the actual capped faction API"):return
	if not check(not c.Factions.access(c.state, harbor).legal, "Actual faction access can refuse the return harbor"):return
	refuse(quoted(remote_intent()), "An inaccessible return harbor without safe conduct is refused")
	c.state.relationships.safeConduct[str(harbor.id)] = float(c.state.day) + 0.001
	refuse(quoted(remote_intent()), "Safe conduct that expires before the actual return cannot guarantee entry")
	c.state.relationships.safeConduct[str(harbor.id)] = float(c.state.day) + 100.0
	var permitted: Dictionary = quoted(remote_intent())
	check(permitted.ok and permitted.routeOk, "Current safe conduct lasting beyond estimated arrival admits the real return harbor")
