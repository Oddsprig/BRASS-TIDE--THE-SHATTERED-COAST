extends SceneTree
## Pure-contract fixtures plus one actual Kelp terrain-routing regression.
## Synthetic certificates below make NO physical claim.
## Helper A has no engine lease; C/root must run this suite and independent motion.
const P = preload("res://scripts/tactical_planner.gd")
const R = preload("res://scripts/tactical_role_plans.gd")
const Routes = preload("res://scripts/tactical_routes.gd")
const Coast = preload("res://scripts/coastal_terrain.gd")
const Refit = preload("res://scripts/refit.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL tactical_planner: " + message)

func ship(id: String, team: String = "player", point: Vector2 = Vector2(400, 850)) -> Dictionary:
	return {"id": id, "uid": id, "team": team, "x": point.x, "y": point.y, "vx": 0.0, "vy": 0.0, "angle": 0.0, "hp": 180.0, "maxHp": 180.0, "water": 0.0, "capacity": 720.0, "fire": 0.0, "engine": 1.0, "crew": 5.0, "wounded": 0.0, "crewMin": 2.0, "crewOptimal": 5.0, "supplies": 20.0, "ammo": 80.0, "fuel": 60.0, "policy": "balanced", "formationIndex": 0, "sunk": false, "captureSecured": false, "order": "engage", "orderTarget": {}, "orderRevision": 1, "orderSince": 0.0, "spec": {"id": "fixture", "size": 16.0, "speed": 140.0, "turn": 2.0, "fuelUse": 1.0}, "status": {"speedFactor": 1.0, "weaponFactor": 1.0, "inflow": 0.0, "bailing": 0.0}, "mounts": [{"id": "mount0", "kind": "gun", "damage": 12.0, "fireRate": 2.0, "range": 650.0, "speed": 850.0, "ammoCost": 1, "arc": TAU, "angle": 0.0, "x": 0.0, "y": 0.0}], "weaponCooldowns": [0.0], "mountShotTimes": {"mount0": -1.0}}

func view(boats: Array = []) -> Dictionary:
	return {"snapshotRevision": 1, "terrainRevision": 1, "time": 0.0, "dt": 1.0 / 30.0, "side": "player", "dueIds": ["a"], "ships": boats if not boats.is_empty() else [ship("a"), ship("enemy", "enemy", Vector2(850, 850))], "groups": {}, "options": {"byId": {}, "clearanceRemaining": 4096}, "mission": {}}

func get_ship(v: Dictionary, id: String) -> Dictionary:
	for boat: Dictionary in v.ships:
		if boat.id == id:
			return boat
	return {}

func certify(candidate: Dictionary, v: Dictionary) -> Dictionary:
	var boat: Dictionary = get_ship(v, str(candidate.shipId))
	var pose: Dictionary = {}
	for key: String in ["x", "y", "vx", "vy", "angle"]:
		pose[key] = boat[key]
	var firing: bool = not candidate.fireMountIds.is_empty()
	var anchor: Vector2 = candidate["pass"][0] if not candidate["pass"].is_empty() else candidate.approach[-1]
	var eta: float = Vector2(boat.x, boat.y).distance_to(anchor) / maxf(1.0, float(boat.spec.speed))
	var certificate: Dictionary = {"status": "valid", "reachable": true, "exitReachable": true, "eta": eta, "fireWindow": {"from": float(v.time), "until": float(v.time) + (0.1 if firing else 0.0), "mountIds": candidate.fireMountIds.duplicate()}, "risk": 0.1, "checkedAt": float(v.time), "validUntil": float(v.time) + 0.2, "snapshotRevision": v.snapshotRevision, "orderRevision": boat.orderRevision, "pathFingerprint": P.fingerprint(candidate), "terrainRevision": v.terrainRevision, "geometryKey": "geometry fixture".sha256_text(), "checkedPose": pose, "dynamicsKey": "dynamics fixture".sha256_text(), "physicalHorizonEnd": float(v.time) + 2.0, "rolloutSamples": 60, "scope": "complete-geometry+prefix-physical", "reason": "Synthetic pure-contract fixture."}
	return {"candidate": candidate.duplicate(true), "certificate": certificate}

func offers(v: Dictionary, memory: Dictionary = {}) -> Array:
	var result: Array = []
	for candidate: Dictionary in P.propose(v, memory):
		result.append(certify(candidate, v))
	return result

func tick(v: Dictionary, delta: float = 0.1) -> void:
	v.time += delta
	v.snapshotRevision += 1

func test_detachment_and_authorship() -> void:
	var v: Dictionary = view()
	var b: Dictionary = ship("b", "player", Vector2(400, 1200))
	v.ships.append(b)
	var memory: Dictionary = {"byId": {"b": {"phase": "hold", "observations": [{"at": 0.0, "hp": 180.0}]}}, "reservations": {"b": {"shipId": "b", "targetId": "", "sector": -1, "anchor": Vector2(400, 1200), "radius": 24.0, "from": 0.0, "until": 5.0, "approach": [Vector2(400, 1200)], "pass": [Vector2(400, 1200)], "exit": [Vector2(400, 1200)]}}}
	var original_view: Dictionary = v.duplicate(true)
	var original_memory: Dictionary = memory.duplicate(true)
	var proposed: Array = P.propose(v, memory)
	var os: Array = offers(v, memory)
	var original_offers: Array = os.duplicate(true)
	var result: Dictionary = P.resolve(v, memory, os)
	check(v == original_view and memory == original_memory and os == original_offers, "both pure calls preserve every input")
	check(result.byId.keys() == ["a"] and not result.memory.byId.has("enemy"), "only due friendly hull gets authored intent/memory")
	check(result.memory.byId.b == memory.byId.b and result.memory.reservations.b == memory.reservations.b, "other hull memory and station reservation survive unchanged")
	result.memory.byId.b.observations[0].hp = 0.0
	check(memory == original_memory, "returned memory has no nested live aliases")
	if not result.byId.a.waypoints.is_empty():
		result.byId.a.waypoints[0] = Vector2(-999, -999)
	check(os == original_offers and v == original_view, "returned paths have no proposal/snapshot aliases")
	check(not proposed.is_empty() and proposed.size() <= 8, "due hull produces bounded useful candidates")
	v.dueIds = ["b", "enemy", "b", "unknown"]
	var other_offers: Array = offers(v, memory)
	v.dueIds = ["a"]
	var rejected: Dictionary = P.resolve(v, memory, other_offers)
	check(rejected.counters.accepted == 0 and not rejected.byId.has("b"), "foreign and non-due certificates cannot author an intent")
	v.dueIds = []
	check(P.propose(v, memory).is_empty() and P.resolve(v, memory, os).memory == memory, "manual suspension by B's empty due set preserves orders and memory")

func test_certificate_rejection() -> void:
	var v: Dictionary = view()
	var baseline: Dictionary = offers(v)[0]
	check(P.resolve(v, {}, [baseline]).counters.accepted == 1, "matching valid certificate permits one assignment")
	var bad_values: Array = [{"status": "pending"}, {"status": "blocked"}, {"reachable": false}, {"exitReachable": false}, {"validUntil": 0.0}, {"validUntil": 0.3}, {"checkedAt": 1.0}, {"eta": NAN}, {"risk": INF}, {"risk": -0.1}, {"snapshotRevision": 2}, {"orderRevision": 2}, {"terrainRevision": 2}, {"pathFingerprint": "changed".sha256_text()}, {"geometryKey": ""}, {"dynamicsKey": ""}, {"physicalHorizonEnd": 1.0}, {"rolloutSamples": 59}, {"scope": "unbounded global claim"}, {"checkedPose": {"x": -1.0}}, {"fireWindow": {"from": 0.0, "until": 0.1, "mountIds": ["imaginary"]}}, {"fireWindow": {"from": NAN, "until": 0.1, "mountIds": ["mount0"]}}, {"fireWindow": {"from": 0.0, "until": 0.0, "mountIds": []}}]
	for bad: Dictionary in bad_values:
		var changed: Dictionary = baseline.duplicate(true)
		changed.certificate.merge(bad, true)
		var result: Dictionary = P.resolve(v, {}, [changed])
		check(result.counters.accepted == 0 and result.byId.a.waypoints.is_empty() and not result.byId.a.fireGate.mount0.permit, "malformed/expired/mismatched certificate fails closed: " + str(bad.keys()[0]))
	var incomplete: Dictionary = baseline.duplicate(true)
	incomplete.certificate.erase("checkedPose")
	check(P.resolve(v, {}, [incomplete]).counters.accepted == 0, "incomplete certificate is denied")
	var tampered: Dictionary = baseline.duplicate(true)
	tampered.candidate.approach[1] += Vector2(20, 0)
	check(P.resolve(v, {}, [tampered]).counters.accepted == 0, "changed interior path point cannot reuse old complete-path fingerprint")
	tampered.certificate.pathFingerprint = P.fingerprint(tampered.candidate)
	check(P.resolve(v, {}, [tampered]).counters.accepted == 1, "B-refined geometry can carry its own matching valid certificate")
	tampered.candidate.targetId = "another target"
	tampered.certificate.pathFingerprint = P.fingerprint(tampered.candidate)
	check(P.resolve(v, {}, [tampered]).counters.accepted == 0, "refinement cannot substitute the source target even with a fresh hash")
	var overflow: Dictionary = baseline.duplicate(true)
	for i: int in range(9):
		overflow.candidate.approach.append(Vector2(i, 2))
	check(P.fingerprint(overflow.candidate).is_empty() and P.resolve(v, {}, [overflow]).counters.accepted == 0, "oversized candidate path is never fingerprinted or assigned")

func test_coordination_and_budget() -> void:
	var boats: Array = []
	var center: Vector2 = Vector2(1100, 850)
	for i: int in range(3):
		var a: Dictionary = ship("a%d" % i, "player", center + Vector2.from_angle(float(i) * TAU / 3.0) * 400.0)
		a.formationIndex = i
		boats.append(a)
	var heavy: Dictionary = ship("heavy", "enemy", center)
	heavy.spec.size = 50.0
	heavy.spec.speed = 60.0
	boats.append(heavy)
	var v: Dictionary = view(boats)
	v.dueIds = ["a0", "a1", "a2"]
	var result: Dictionary = P.resolve(v, {}, offers(v))
	check(result.counters.accepted >= 2, "separated certified approaches can assign more than one flanker")
	var reservations: Array = result.memory.reservations.values()
	for i: int in range(reservations.size()):
		for j: int in range(i + 1, reservations.size()):
			check(reservations[i].anchor.distance_to(reservations[j].anchor) >= reservations[i].radius + reservations[j].radius and reservations[i].sector != reservations[j].sector, "accepted flankers reserve distinct spaced stations")
	var memory: Dictionary = result.memory
	var keep_id: String = str(reservations[0].shipId)
	var original: Dictionary = memory.reservations[keep_id].duplicate(true)
	v.dueIds.erase(keep_id)
	v.options.clearanceRemaining = 0
	tick(v)
	var waiting: Dictionary = P.resolve(v, memory, offers(v, memory))
	check(waiting.counters.clearanceTests == 0 and waiting.counters.clearanceExhausted > 0, "shared exhausted occupancy budget performs zero extra primitives")
	check(waiting.memory.reservations[keep_id] == original, "budget exhaustion never evicts another hull's live reservation")
	for intent: Dictionary in waiting.byId.values():
		check(intent.waypoints.is_empty() and intent.validUntil <= v.time, "pending reservation conflict does not execute an unchecked path")

func test_actual_shot_phases_and_leases() -> void:
	var v: Dictionary = view()
	var a: Dictionary = get_ship(v, "a")
	a.mounts[0].kind = "torpedo"
	a.mounts[0].arc = 0.3
	a.mounts[0].range = 800.0
	a.mounts[0].ammoCost = 3
	var first: Dictionary = P.resolve(v, {}, offers(v))
	check(first.byId.a.phase == "launch-window" and first.byId.a.fireGate.mount0.permit and first.byId.a.fireGate.mount0.leaseKind == "salvo", "aligned loaded fixed tube has a finite salvo lease")
	var pass_id: String = str(first.byId.a.fireGate.mount0.firingPassId)
	var memory: Dictionary = first.memory
	for i: int in range(3):
		tick(v)
		var refreshed: Dictionary = P.resolve(v, memory, offers(v, memory))
		check(refreshed.byId.a.phase != "turn-away" and refreshed.byId.a.fireGate.mount0.firingPassId == pass_id, "routine refresh and unconsumed intent never invent a shot or pass")
		memory = refreshed.memory
	tick(v)
	a.mountShotTimes.mount0 = v.time
	a.ammo -= 3.0
	var after_shot: Dictionary = P.resolve(v, memory, offers(v, memory))
	check(after_shot.memory.byId.a.phase == "turn-away" and not after_shot.byId.a.fireGate.mount0.permit, "observed real shot timestamp turns striker away and closes tube")
	check(after_shot.byId.a.fireGate.mount0.firingPassId == pass_id and a.ammo == 77.0, "turn-away preserves spent pass identity and real stores")
	memory = after_shot.memory
	tick(v, 2.1)
	var regroup: Dictionary = P.resolve(v, memory, offers(v, memory))
	check(regroup.memory.byId.a.phase == "regroup", "turn-away is followed by regroup")
	tick(v, 4.1)
	var stationary: Dictionary = P.resolve(v, regroup.memory, offers(v, regroup.memory))
	check(stationary.memory.byId.a.firingPassId == pass_id, "elapsed time without observed breakaway travel cannot refill a salvo")
	a.x -= 120.0
	tick(v)
	var new_pass: Dictionary = P.resolve(v, stationary.memory, offers(v, stationary.memory))
	check(new_pass.memory.byId.a.firingPassId != pass_id, "genuine completed regroup starts another firing pass")
	var second_id: String = str(new_pass.memory.byId.a.firingPassId)
	tick(v)
	var stable: Dictionary = P.resolve(v, new_pass.memory, offers(v, new_pass.memory))
	check(stable.memory.byId.a.firingPassId == second_id, "new pass identity stays stable on its next refresh")
	a.order = "hold"
	a.orderTarget = {"x": a.x, "y": a.y}
	a.orderRevision += 1
	tick(v)
	var held: Dictionary = P.resolve(v, stable.memory, offers(v, stable.memory))
	check(held.memory.byId.a.firingPassId == second_id, "hold revision alone cannot mint a firing pass")
	a.order = "attack"
	a.orderTarget = {"shipId": "enemy"}
	a.orderRevision += 1
	tick(v)
	var new_order: Dictionary = P.resolve(v, held.memory, offers(v, held.memory))
	check(new_order.memory.byId.a.firingPassId != second_id, "new explicit attack revision can authorize a new pass")
	var gun_view: Dictionary = view()
	var gun_first: Dictionary = P.resolve(gun_view, {}, offers(gun_view))
	tick(gun_view)
	var gun_next: Dictionary = P.resolve(gun_view, gun_first.memory, offers(gun_view, gun_first.memory))
	check(gun_first.byId.a.fireGate.mount0.leaseKind == "continuous" and gun_next.byId.a.fireGate.mount0.permit, "ordinary gun lease renews instead of becoming a one-shot gun")

func test_counterexamples_and_orders() -> void:
	var slow: Dictionary = view()
	slow.options.byId.a = {"role": "skirmisher"}
	get_ship(slow, "a").spec.speed = 50.0
	get_ship(slow, "enemy").x = 1500.0
	get_ship(slow, "enemy").vx = 200.0
	var too_slow: Dictionary = P.resolve(slow, {}, offers(slow))
	check(too_slow.memory.byId.a.phase == "regroup" and not too_slow.byId.a.fireGate.mount0.permit, "slower light declines an unsustainable pursuit")
	var endangered: Dictionary = view()
	get_ship(endangered, "a").fire = 50.0
	get_ship(endangered, "a").water = 500.0
	get_ship(endangered, "a").status.inflow = 40.0
	var escape: Dictionary = P.resolve(endangered, {}, offers(endangered))
	check(escape.memory.byId.a.phase == "breakaway" and not escape.byId.a.fireGate.mount0.permit, "observed fire/flood danger changes phase without a combat buff")
	var trapped_memory: Dictionary = {}
	for i: int in range(5):
		var blocked: Array = offers(endangered, trapped_memory)
		for offer: Dictionary in blocked:
			offer.certificate.status = "blocked"
			offer.certificate.reachable = false
		var trapped: Dictionary = P.resolve(endangered, trapped_memory, blocked)
		check(trapped.counters.accepted == 0 and trapped.byId.a.waypoints.is_empty(), "trapped/blocked boats receive no invented escape")
		trapped_memory = trapped.memory
		tick(endangered, 1.0)
	var commanded: Dictionary = view()
	var a: Dictionary = get_ship(commanded, "a")
	a.order = "move"
	a.orderTarget = {"x": 600.0, "y": 400.0}
	a.hp = 10.0
	var directed: Dictionary = P.resolve(commanded, {}, offers(commanded))
	check(directed.memory.byId.a.phase == "move" and directed.byId.a.waypoints.has(Vector2(600, 400)), "explicit movement remains authoritative over automatic survival")
	commanded.options.byId.a = {"conditionalWithdrawal": true, "rally": {"x": 120.0, "y": 850.0}}
	var conditional: Dictionary = P.resolve(commanded, {}, offers(commanded))
	check(conditional.memory.byId.a.phase == "breakaway" and conditional.byId.a.waypoints.has(Vector2(120, 850)), "enabled conditional withdrawal uses the named local rally")
	a.hp = a.maxHp
	a.x = 600.0
	a.y = 400.0
	var complete: Dictionary = P.resolve(commanded, {}, offers(commanded))
	check(complete.memory.byId.a.phase == "hold" and "complete" in str(complete.byId.a.reason).to_lower(), "move completion explains its hold without editing the order")
	a.order = "escort"
	a.orderTarget = {"shipId": "lost"}
	var lost: Dictionary = P.resolve(commanded, {}, offers(commanded))
	check(lost.memory.byId.a.phase == "hold" and "lost" in str(lost.byId.a.reason).to_lower(), "lost explicit escort leader is explained rather than silently replaced")

func test_screen_doctrine_and_memory_bounds() -> void:
	var a: Dictionary = ship("a", "player", Vector2(550, 700))
	var ally: Dictionary = ship("carrier", "player", Vector2(750, 850))
	ally.spec.size = 44.0
	var threat: Dictionary = ship("incoming", "enemy", Vector2(950, 850))
	var decoy: Dictionary = ship("nearby", "enemy", Vector2(500, 450))
	decoy.mounts = []
	var v: Dictionary = view([a, ally, threat, decoy])
	v.options.byId.a = {"role": "screen", "protectedAllyId": "carrier", "leash": 260.0}
	var candidates: Array = P.propose(v, {})
	check(candidates[0].targetId == "incoming" and candidates[0].leaderId == "carrier", "screen prioritizes a real incoming threat to its named vulnerable ally")
	for candidate: Dictionary in candidates:
		check(candidate["pass"][0].distance_to(Vector2(ally.x, ally.y)) <= 260.0001, "screen stations stay within the real ally leash")
	var base: Dictionary = view()
	base.options.byId.a = {"doctrine": "cautious"}
	var risk: Array = offers(base)
	for offer: Dictionary in risk:
		offer.certificate.risk = 0.5
	var original: Dictionary = base.duplicate(true)
	check(P.resolve(base, {}, risk).counters.accepted == 0, "cautious doctrine rejects an exposed automatic station")
	base.options.byId.a.doctrine = "aggressive"
	check(P.resolve(base, {}, risk).counters.accepted == 1, "aggressive doctrine changes risk choice using unchanged physical data")
	check(base.ships == original.ships, "doctrine creates no statistics, ammunition or fuel")
	var memory: Dictionary = {}
	for i: int in range(160):
		tick(base, 0.05)
		var result: Dictionary = P.resolve(base, memory, offers(base, memory))
		memory = result.memory
		check(memory.byId.size() == 1 and memory.reservations.size() <= 1 and memory.byId.a.observations.size() <= 8 and memory.byId.a.shotTimes.size() <= 16, "repeated refresh keeps only bounded live per-hull memory")
	var crowded: Dictionary = view()
	for i: int in range(40):
		crowded.ships.append(ship("extra%d" % i, "enemy", Vector2(600 + i * 10, 500)))
	var bounded: Dictionary = P.resolve(crowded, {}, offers(crowded))
	check(bounded.counters.scoredTargets <= 16 and bounded.counters.proposed <= 8, "large tactical context keeps scoring and offers bounded without truncating hull admission")

func test_commitments_holds_and_formations() -> void:
	var v: Dictionary = view()
	var first: Dictionary = P.resolve(v, {}, offers(v))
	var retained_target: String = str(first.memory.byId.a.targetId)
	var retained_anchor: Vector2 = first.memory.byId.a.anchor
	v.ships.append(ship("rival", "enemy", Vector2(820, 880)))
	tick(v)
	var committed: Dictionary = P.resolve(v, first.memory, offers(v, first.memory))
	check(committed.memory.byId.a.targetId == retained_target and committed.memory.byId.a.anchor == retained_anchor, "minor new target advantage does not jitter an active target/station commitment")
	var a: Dictionary = get_ship(v, "a")
	a.order = "attack"
	a.orderTarget = {"shipId": "rival"}
	a.orderRevision += 1
	tick(v)
	var commanded: Dictionary = P.resolve(v, committed.memory, offers(v, committed.memory))
	check(commanded.byId.a.targetId == "rival", "explicit attack interrupts an otherwise stable commitment")
	var second_mount: Dictionary = a.mounts[0].duplicate(true)
	second_mount.id = "mount1"
	a.mounts.append(second_mount)
	a.mountShotTimes.mount1 = -1.0
	v.options.byId.a = {"mounts": {"mount0": {"hold": true}, "mount1": {"reserve": 80}}}
	var held: Dictionary = P.resolve(v, commanded.memory, offers(v, commanded.memory))
	check(held.byId.a.fireGate.size() == 2 and not held.byId.a.fireGate.mount0.permit and not held.byId.a.fireGate.mount1.permit, "holds and real ammunition reserves close every installed automatic mount without fallback")
	check(a.ammo == 80.0 and a.order == "attack", "fire holds do not spend rounds or erase explicit helm authority")
	var escorted: Dictionary = view([ship("a"), ship("ally", "player", Vector2(650, 850)), ship("enemy", "enemy", Vector2(1050, 850))])
	get_ship(escorted, "a").order = "escort"
	get_ship(escorted, "a").orderTarget = {"shipId": "ally"}
	# Preserve distinct formation stations in clear transit, outside the
	# hostile's real weapon/protection zone. The original nearby case remains.
	var transit: Dictionary = escorted.duplicate(true)
	get_ship(transit, "enemy").x = 2200.0
	transit.options.byId.a = {"formation": "line"}
	var line: Array = P.propose(transit, {})
	transit.options.byId.a.formation = "column"
	var column: Array = P.propose(transit, {})
	transit.options.byId.a.formation = "screen"
	var screen: Array = P.propose(transit, {})
	check(line[0]["pass"][0] != column[0]["pass"][0] and column[0]["pass"][0] != screen[0]["pass"][0], "line, column and screen request distinct physical stations")
	for formation: String in ["line", "column", "screen"]:
		escorted.options.byId.a = {"formation": formation}
		var requests: Array = P.propose(escorted, {})
		var offset: Vector2 = requests[0]["pass"][0] - Vector2(650, 850)
		check(requests.size() <= 8 and str(requests[0].targetId) == "enemy" and offset.x > 0.0 and offset.length() <= 600.0, "original nearby real hostile requests threat-facing interception inside the leash for " + formation)
	var screened: Dictionary = view()
	var denied: Array = offers(screened)
	for offer: Dictionary in denied:
		offer.certificate.risk = 0.95
	var counter: Dictionary = P.resolve(screened, {}, denied)
	check(counter.counters.accepted == 0 and not counter.byId.a.fireGate.mount0.permit, "a dangerous screened approach can defeat every light attack offer")
	var dry: Dictionary = view([ship("a"), ship("escort", "player", Vector2(650, 850)), ship("enemy", "enemy", Vector2(1000, 850))])
	get_ship(dry, "a").ammo = 0.0
	var support: Dictionary = P.resolve(dry, {}, offers(dry))
	check(support.memory.byId.a.role == "support" and support.memory.byId.a.leaderId == "escort" and not support.byId.a.fireGate.mount0.permit, "dry support stays with a real protector rather than charging")

func test_time_window_and_detailed_shortlist() -> void:
	# The same HP loss over 1.8s must survive both fleet and rapid duel decisions.
	# Every stored HP/time is one supplied observation, never a fabricated anchor.
	for cadence: float in [0.2, 1.0 / 15.0, 1.0 / 30.0]:
		var v: Dictionary = view([ship("a"), ship("incoming0", "enemy", Vector2(800, 850)), ship("incoming1", "enemy", Vector2(800, 900))])
		get_ship(v, "incoming0").mountShotTimes.mount0 = 0.0
		get_ship(v, "incoming1").mountShotTimes.mount0 = 0.0
		var previous: Dictionary = {}
		var history: Array = []
		var last_loss: float = 0.0
		for step: int in range(roundi(1.8 / cadence) + 1):
			v.time = float(step) * cadence
			get_ship(v, "a").hp = 180.0 - float(v.time) * (15.0 / 1.8)
			var hp: Dictionary = R.hp_history(float(v.time), float(get_ship(v, "a").hp), history)
			history = hp.observations
			last_loss = float(hp.loss)
			var decision: Dictionary = R.decide(v, get_ship(v, "a"), previous, R.ships_by_id(v))
			previous = decision.state
			check(history.size() <= 8 and previous.observations.size() <= 8, "time coalescing is bounded at every decision cadence")
		check(absf(last_loss - 15.0) < 0.001 and previous.phase == "breakaway", "same two-second observed loss and focus reaction at fleet/duel cadence")
		var expired: Dictionary = R.hp_history(4.0, 165.0, history)
		check(float(expired.loss) == 0.0, "expired HP peak cannot masquerade as damage within the last two seconds")
	var crowded: Dictionary = view()
	var protected: Dictionary = ship("carrier", "player", Vector2(1850, 850))
	crowded.ships.append(protected)
	crowded.ships.append(ship("ally-threat", "enemy", Vector2(1750, 850)))
	for i: int in range(40):
		crowded.ships.append(ship("local%d" % i, "enemy", Vector2(430 + i, 500 + i)))
	var own: Dictionary = get_ship(crowded, "a")
	crowded.options.byId.a = {"role": "screen", "protectedAllyId": "carrier"}
	var context: Dictionary = R.ships_by_id(crowded)
	var selected: Array = R.shortlist(crowded, own, context, protected)
	var ids: Array = []
	for entry: Dictionary in selected:
		ids.append(str(entry.id))
	var decision: Dictionary = R.decide(crowded, own, {}, context)
	check(ids.size() <= 16 and "ally-threat" in ids and decision.detailedIds.size() <= 16 and decision.scored == decision.detailedIds.size(), "geometric shortlist retains an important ally threat and bounds all detailed opponent IDs")
	own.order = "attack"
	own.orderTarget = {"shipId": "ally-threat"}
	var ordered: Array = R.shortlist(crowded, own, context, protected)
	var forced: Dictionary = R.decide(crowded, own, {}, context)
	var ordered_ids: Dictionary = {}
	for entry: Dictionary in ordered:
		ordered_ids[str(entry.id)] = true
	check(ordered.size() == 16 and ordered_ids.size() == 16 and ordered[0].id == "ally-threat" and forced.detailedIds.size() == 16 and forced.state.targetId == "ally-threat" and forced.targets == ["ally-threat"], "explicit target stays mandatory and strict without erasing the bounded nearby danger shortlist")

func route_budget051(limit: int = 2900) -> Dictionary:
	return {"fullRoutes":0, "cacheHits":0, "clearanceTests":0, "clearanceLimit":limit, "exhaustions":0}

func kelp_route051(st: Dictionary, geometry: Dictionary, a: Vector2, b: Vector2, radius: float, moving_goal: bool = false) -> Dictionary:
	var result: Dictionary = {"status":"pending", "path":[]}
	var pending_calls: int = 0
	var goal: Vector2 = b
	# First model a partly spent shared allowance, then normal planning calls.
	# This must still exercise a yield if a later sweep broadphase gets faster.
	for attempt: int in range(32):
		goal = b + Vector2(0, float(attempt) * 0.03125) if moving_goal else b
		var work: Dictionary = route_budget051(128 if attempt == 0 else 2900)
		result = Routes.route(st, geometry, a, goal, radius, work)
		check(int(work.clearanceTests) <= int(work.clearanceLimit) and int(work.fullRoutes) <= 1, "Kelp route respects each call's work/query limits")
		check(st.tactical.routeCache.size() <= 128, "Kelp route cache stays bounded")
		if result.status != "pending":
			break
		pending_calls += 1
		check(result.path.is_empty(), "pending Kelp work never publishes an unchecked path")
	print("Kelp route: pending_calls=%d status=%s points=%d" % [pending_calls, result.status, result.path.size()])
	return {"route":result, "pendingCalls":pending_calls, "goal":goal}

func test_kelp_route_progress051() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	check(data is Dictionary, "actual Kelp route world loads")
	if not data is Dictionary:
		return
	var port: Dictionary = data.PORTS.filter(func(p):return p.id == "kelp_reach")[0]
	var arena: Dictionary = Coast.arena(data, port)
	var st: Dictionary = {"islands":arena.islands, "tactical":{"routeCache":{}}}
	var geometry: Dictionary = Routes.terrain(st)
	check(st.islands.size() == 1 and st.islands[0].id == "isl_kelp" and st.islands[0].points.size() == 76, "first-voyage Kelp Reach uses the real 76-vertex coast")
	var hull: Dictionary = data.HULLS.filter(func(h):return h.id == "tin_skiff")[0]
	var spec: Dictionary = Refit.effective_spec(hull, Refit.defaults(hull))
	var radius: float = Routes.planning_radius({"spec":spec})
	# Actual stalled Tin pose from job1110785; a water goal beyond Kelp's east
	# promontory deliberately needs a land detour, not a synthetic certificate.
	var a: Vector2 = Vector2(756.238525390625, 689.843505859375)
	var b: Vector2 = Vector2(1200, 1200)
	var unchanged: PackedByteArray = var_to_bytes([st.islands, spec, a, b])
	check(Routes.sweep(geometry, a, a, radius, route_budget051()) == "valid" and Routes.sweep(geometry, b, b, radius, route_budget051()) == "valid", "Kelp route endpoints admit the actual fitted Tin planning radius")
	check(Routes.sweep(geometry, a, b, radius, route_budget051()) == "blocked", "Kelp regression actually crosses land")
	var empty_work: Dictionary = route_budget051(0)
	check(Routes.route(st, geometry, a, b, radius, empty_work).status == "pending" and int(empty_work.clearanceTests) == 0 and st.tactical.routeCache.is_empty(), "zero budget cannot publish or seed a partial clearance proof")
	var progress: Dictionary = kelp_route051(st, geometry, a, b, radius)
	var found: Dictionary = progress.route
	check(progress.pendingCalls > 0 and found.status == "valid", "real Kelp route yields then completes instead of restarting indefinitely")
	if found.status != "valid":
		return
	check(not found.path.is_empty() and found.path.size() <= 8 and found.path[-1] == b, "completed Kelp route preserves the real goal and existing eight-point cap")
	var cursor: Vector2 = a
	for waypoint: Vector2 in found.path:
		check(Routes.sweep(geometry, cursor, waypoint, radius, route_budget051()) == "valid", "each returned Kelp edge independently passes the authoritative full land sweep")
		cursor = waypoint
	var warm: Dictionary = route_budget051(0)
	check(Routes.route(st, geometry, a, b, radius, warm) == found and int(warm.cacheHits) == 1, "completed exact Kelp route remains a bounded cache hit")
	var graph: Dictionary = st.tactical.routeCache.values()[0].graph
	# Start cold again and change the goal on EVERY retry. Only exact static
	# and unchanged-origin visibility may carry over, never the old goal path.
	var moving: Dictionary = {"islands":st.islands, "tactical":{"routeCache":{}}}
	var moving_geometry: Dictionary = Routes.terrain(moving)
	var moved: Dictionary = kelp_route051(moving, moving_geometry, a, b, radius, true)
	check(moved.pendingCalls > 0 and moved.route.status == "valid" and moving.tactical.routeCache.size() > 1, "changing goals retain terrain progress without borrowing an old endpoint path")
	check(is_same(moving.tactical.routeCache.values()[0].graph, moving.tactical.routeCache.values()[-1].graph), "separate exact-endpoint searches share their exact terrain/radius graph")
	var moved_cursor: Vector2 = a
	for waypoint: Vector2 in moved.route.path:
		check(Routes.sweep(moving_geometry, moved_cursor, waypoint, radius, route_budget051()) == "valid", "moving-goal route independently passes full land sweeps")
		moved_cursor = waypoint
	check(moved.route.status == "valid" and moved_cursor == moved.goal, "moving-goal route ends at the current exact goal")
	Routes.route(st, geometry, a, b, radius + 1.0, route_budget051())
	check(st.tactical.routeCache.size() == 2 and not is_same(st.tactical.routeCache.values()[1].graph, graph), "a changed fitted radius cannot borrow the old static visibility graph")
	check(var_to_bytes([st.islands, spec, a, b]) == unchanged, "routing preserves the real coast, hull statistics and endpoints")
	st.islands[0].points[0][0] += 0.125
	var changed: Dictionary = Routes.terrain(st)
	check(changed.key != geometry.key and int(changed.revision) > int(geometry.revision) and st.tactical.routeCache.is_empty(), "actual coast edits invalidate completed routes, frontiers and shared visibility together")

func traffic_reference051(cells: Dictionary, own: Dictionary, a: Vector2, b: Vector2, radius: float, from: float, until: float, work: Dictionary, avoid: bool, contact: String) -> String:
	# Independent pre-optimization closest-approach walk, including discovery
	# order, debit/refusal and the inherited-close-pass/contact exceptions.
	var extra: float = maxf(0.0, until - 2.0) * float(cells.get("_maxSpeed", 0.0))
	var query: float = radius + 80.0 + extra
	var navigation: float = maxf(radius, Routes.navigation_radius(own)) if avoid else radius
	if avoid:
		query = navigation + (float(cells._maxNavigationRadius) + 7.0 if cells.has("_maxNavigationRadius") else 220.0) + extra
	for other: Dictionary in Routes.neighbours(cells, a, b, query):
		if str(other.id) == str(own.id):continue
		var hostile: bool = other.team != own.team
		if hostile and (not avoid or str(other.id) == contact):continue
		if hostile and a == b and until <= from:continue
		if not Routes.spend(work):return "pending"
		var velocity: Vector2 = Vector2(other.vx, other.vy)
		var c: Vector2 = Routes.point(other) + velocity * from
		var d: Vector2 = Routes.point(other) + velocity * until
		var relative: Vector2 = a - c
		var delta: Vector2 = (b - a) - (d - c)
		var fraction: float = clampf(-relative.dot(delta) / maxf(0.000001, delta.length_squared()), 0.0, 1.0)
		var clearance: float = radius + maxf(10.0, float(other.spec.get("size", 16))) + 3.0
		if hostile:clearance = navigation + Routes.navigation_radius(other) + 7.0
		if (relative + delta * fraction).length() < clearance:
			if hostile and relative.length() < clearance and relative.dot(delta) >= 0.0 and (relative + delta).length_squared() > relative.length_squared() + 0.0001:continue
			return "blocked"
	return "valid"

func test_traffic_clearance051() -> void:
	var own: Dictionary = ship("traffic-own051")
	var a: Vector2 = Routes.point(own)
	var b: Vector2 = a + Vector2(160, 0)
	# Allied clearance is exactly 20+16+3=39. Boundary offsets straddle one
	# float32 step; moving crossings must not be culled by endpoint distances.
	var cases: Array = [
		{"label":"disjoint y", "position":a + Vector2(80, 80), "expected":"valid"},
		{"label":"just outside", "position":a + Vector2(80, 39.00006103515625), "expected":"valid"},
		{"label":"tangent", "position":a + Vector2(80, 39), "expected":"valid"},
		{"label":"just inside", "position":a + Vector2(80, 38.99993896484375), "expected":"blocked"},
		{"label":"moving crossing", "position":a + Vector2(80, 120), "vy":-120.0, "expected":"blocked"},
		{"label":"oversized hostile", "position":a + Vector2(500, 0), "team":"enemy", "size":120.0, "expected":"blocked"},
		{"label":"separating hostile", "position":a - Vector2(10, 0), "team":"enemy", "expected":"valid"},
		{"label":"approaching hostile", "position":a + Vector2(10, 0), "team":"enemy", "expected":"blocked"},
		{"label":"contact exception", "position":a + Vector2(80, 0), "team":"enemy", "contact":"traffic-other051", "expected":"valid"},
		{"label":"public allied-only default", "position":a + Vector2(80, 0), "team":"enemy", "avoid":false, "expected":"valid"},
		{"label":"allied hold", "position":a, "hold":true, "expected":"blocked"},
		{"label":"hostile zero-time hold", "position":a, "team":"enemy", "hold":true, "expected":"valid"},
		{"label":"full ETA crossing", "position":a + Vector2(80, 1200), "vy":-120.0, "from":9.0, "until":11.0, "expected":"blocked"}
	]
	for trial: Dictionary in cases:
		var other: Dictionary = ship("traffic-other051", str(trial.get("team", "player")), trial.position)
		other.spec.size = float(trial.get("size", 16.0));other.vy = float(trial.get("vy", 0.0))
		var cells: Dictionary = Routes.grid([own, other], true)
		var goal: Vector2 = a if trial.get("hold", false) else b
		var from: float = float(trial.get("from", 0.0))
		var until: float = float(trial.get("until", 0.0 if trial.get("hold", false) else 2.0))
		var avoid: bool = bool(trial.get("avoid", true))
		var contact: String = str(trial.get("contact", ""))
		var held: PackedByteArray = var_to_bytes([own, other])
		for limit: int in [0, 1, 4096]:
			var reference_work: Dictionary = route_budget051(limit)
			var expected: String = traffic_reference051(cells, own, a, goal, 20.0, from, until, reference_work, avoid, contact)
			var public_work: Dictionary = route_budget051(limit)
			var actual: String = Routes.occupied(cells, own, a, goal, 20.0, from, until, public_work, avoid, contact)
			var private_work: Dictionary = route_budget051(limit)
			var debits: Array[int] = []
			var recorded: String = Routes._occupied_record051(cells, own, a, goal, 20.0, from, until, private_work, avoid, contact, debits)
			check(actual == expected and recorded == expected and public_work == reference_work and private_work == reference_work, str(trial.label) + ": public/recorded results and exact budget refusals match the old narrow phase")
			if limit == 4096:check(actual == trial.expected, str(trial.label) + ": independently specified physical result")
		check(var_to_bytes([own, other]) == held, str(trial.label) + ": traffic checks preserve actual hull inputs")

func _initialize() -> void:
	if "--case=coastal-route051" in OS.get_cmdline_user_args():
		test_kelp_route_progress051()
		test_traffic_clearance051()
		print("tactical_planner coastal-route051: %d checks, %d failures" % [checks, failures])
		quit(1 if failures > 0 else 0)
		return
	test_detachment_and_authorship()
	test_certificate_rejection()
	test_coordination_and_budget()
	test_actual_shot_phases_and_leases()
	test_counterexamples_and_orders()
	test_screen_doctrine_and_memory_bounds()
	test_commitments_holds_and_formations()
	test_time_window_and_detailed_shortlist()
	test_kelp_route_progress051()
	test_traffic_clearance051()
	print("tactical_planner: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
