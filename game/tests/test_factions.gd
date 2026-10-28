extends SceneTree
## Unrun by the helper. Root runs this headless after integration.
const F = preload("res://scripts/factions.gd")

var checks: int = 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("FAIL factions: " + msg)
		assert(cond, msg)
		quit(1)
		return
	checks += 1


func _world() -> Dictionary:
	return {
		"FACTIONS": [
			{"id": "compact", "name": "Mercantile Compact"},
			{"id": "forge", "name": "Cinder Forge Directorate"},
			{"id": "reed", "name": "Reedwater Commune"},
			{"id": "raiders", "name": "Shatter Reef Raiders"},
		],
		"PORTS": [
			{"id": "brass_haven", "name": "Brass Haven", "faction": "compact"},
			{"id": "kelp_reach", "name": "Kelp Reach", "faction": "reed"},
			{"id": "sawtooth_mill", "name": "Sawtooth Mill", "faction": "compact"},
			{"id": "silt_hollow", "name": "Silt Hollow", "faction": "reed"},
			{"id": "cinder_quay", "name": "Cinder Quay", "faction": "forge"},
			{"id": "anvil_dock", "name": "Anvil Dock", "faction": "forge"},
			{"id": "reed_floats", "name": "Reedwater Floats", "faction": "reed"},
			{"id": "naphtha_bay", "name": "Naphtha Bay", "faction": "forge"},
			{"id": "rust_anchorage", "name": "Rust Anchorage", "faction": "raiders"},
			{"id": "shatter_spire", "name": "Shatter Spire", "faction": "raiders"},
		],
	}


func _fresh() -> Dictionary:
	var world := _world()
	var before := JSON.stringify(world)
	var state := {"day": 12, "coins": 15000}
	var book: Dictionary = F.ensure(state, world)
	_check(JSON.stringify(world) == before, "ensure does not mutate world")
	_check(book.has("factions") and book.factions.has("raiders"), "ensure installs the four factions")
	_check(state.coins == 15000, "ensure does not mint coins")
	_check(not state.has("activeContract"), "ensure does not open a campaign contract")
	return state


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	_test_initial_independence()
	_test_permissions()
	_test_hysteresis_bounds_and_events()
	_test_witness_claim_time_restitution()
	_test_commission()
	_test_commission_review_and_consent()
	_test_save_roundtrip()
	var elapsed := Time.get_ticks_msec() - started
	_check(elapsed < 60000, "faction checks finished under 60s (%d ms)" % elapsed)
	print("ALL FACTION TESTS PASSED (%d checks in %d ms)" % [checks, elapsed])
	quit(0)


func _test_initial_independence() -> void:
	var state := _fresh()
	_check(F.is_hostile(state, "raiders"), "raiders start hostile")
	_check(not F.is_hostile(state, "compact") and not F.is_hostile(state, "forge") and not F.is_hostile(state, "reed"), "legal factions start neutral")
	var raiders: Dictionary = F.standing(state, "raiders")
	_check(raiders.score == F.INITIAL_RAIDER and raiders.public == raiders.score and raiders.band == "hostile", "raider public standing is hostile and separate from witness")
	_check(raiders.witnessed == 0 and raiders.claimTotal == 0, "witness and claims start empty")
	var compact: Dictionary = F.standing(state, "compact")
	_check(compact.score == 0 and compact.band == "neutral" and compact.label == "Neutral", "compact starts neutral")
	_check(F.relation(state, "compact", "raiders") == -40 and F.relation(state, "raiders", "compact") == -40, "pair relation is one symmetric value")
	_check(F.relation(state, "compact", "forge") == 15 and F.relation(state, "compact", "reed") == 5, "authored baselines")
	_check(F.relation(state, "compact", "compact") == 0, "a faction has no self relation")
	_check(not F.standing(state, "ghost").known, "unknown faction")
	_check(not F.is_hostile(state, "ghost"), "unknown faction is not treated as hostile")
	_check(not F.adjust(state, "ghost", 5, "nope").ok, "unknown adjust is rejected")
	_check(F.standing(state, "compact").score == 0, "rejected adjust does not move a real faction")
	F.ensure(state, _world())
	_check(F.standing(state, "raiders").score == F.INITIAL_RAIDER, "second ensure does not reset raiders")
	_check(state.relationships.contacts.size() == 4, "four authored contacts")
	var changed: Dictionary = F.set_relation(state, "compact", "forge", -80, "tariff dispute")
	_check(changed.ok and changed.changed and changed.relation == -80 and changed.symmetric, "pair write")
	_check(F.relation(state, "forge", "compact") == -80, "reverse lookup uses the same pair")
	_check(F.relation(state, "compact", "reed") == 5, "other pairs stay put")
	_check(F.standing(state, "compact").score == 0 and F.standing(state, "forge").score == 0, "pair changes do not move player reputation")
	var repeat: Dictionary = F.set_relation(state, "forge", "compact", -80, "again")
	_check(not repeat.changed and state.relationships.log.size() == 1, "setting the same relation does not grow the log")
	_check(not F.set_relation(state, "reed", "reed", 10, "no").ok, "self relation is rejected")
	_check(not F.set_relation(state, "compact", "ghost", -5, "no").ok, "unknown pair is rejected")
	var capped: Dictionary = F.set_relation(state, "compact", "reed", 500, "pact")
	_check(capped.relation == F.REP_MAX and F.relation(state, "reed", "compact") == 100, "pair caps at 100")
	_check(F.standing(state, "reed").score == 0, "capped pair still leaves player reputation alone")
	var trust: Dictionary = F.adjust(state, "compact", 25, "contact:holt:spoke for the convoy", "trust-1")
	_check(trust.ok and trust.trust == 25 and trust.factionScore == 0, "contact trust is not faction score")
	_check(int(state.relationships.contacts.holt.trust) == 25, "Holt trust stored")
	_check(F.relation(state, "compact", "forge") == -80, "contact trust does not move pairs")
	_check(not F.adjust(state, "raiders", 5, "contact:holt:no").ok, "a contact cannot be adjusted through the wrong faction")
	_check(int(state.relationships.contacts.holt.trust) == 25, "mismatched contact adjust changes nothing")
	var help: Dictionary = F.adjust(state, "forge", 20, "plate shipment")
	_check(help.score == 20 and help.band == "friendly", "forge help")
	_check(F.standing(state, "compact").score == 0 and F.standing(state, "reed").score == 0, "helping forge does not befriend its rivals' rivals")
	_check(F.standing(state, "raiders").score == F.INITIAL_RAIDER - 6, "forge's explicit rival loses floor(20/3)")
	_check(F.relation(state, "compact", "forge") == -80, "public help does not rewrite faction pairs")
	_check(int(state.relationships.contacts.holt.trust) == 25, "public help does not move contact trust")
	_check(state.coins == 15000, "adjust does not move coins")


func _test_permissions() -> void:
	var state := _fresh()
	var legal: Dictionary = F.access(state, "brass_haven")
	_check(legal.ok and legal.legal and legal.entry == "open" and not legal.inspection, "neutral port is open")
	_check(legal.reason == "Neutral legal access at Brass Haven. Ordinary trade and contracts are open; guns and engines stay restricted.", "neutral access reason")
	_check(legal.contracts and legal.repairPriority == "ordinary" and not legal.militaryFittings and not legal.escorts and not legal.intelligence, "neutral permissions")
	_check(legal.restrictedGoods.has("guns") and legal.restrictedGoods.has("engines"), "guns and engines restricted while neutral")
	var refused: Dictionary = F.access(state, "shatter_spire")
	_check(refused.entry == "refused" and not refused.legal and not refused.contracts and refused.repairPriority == "none", "hostile port refuses entry")
	_check(refused.reason.begins_with("Hostile standing with Shatter Reef Raiders"), "refusal names the faction")
	_check(not F.access(state, "missing_port").ok, "unknown port")
	F.adjust(state, "compact", -25, "seized a packet")
	var wary: Dictionary = F.access(state, "brass_haven")
	_check(wary.band == "wary" and wary.legal and wary.entry == "inspected" and wary.contracts and not wary.militaryFittings, "wary trade stays legal under inspection")
	_check(F.standing(state, "raiders").score == F.INITIAL_RAIDER, "a penalty does not spill to rivals")
	var raised := _fresh()
	F.adjust(raised, "compact", 20, "known captain")
	var friend: Dictionary = F.access(raised, "brass_haven")
	_check(friend.band == "friendly" and friend.militaryFittings and friend.escorts and not friend.intelligence and friend.restrictedGoods.is_empty(), "friendly fittings and escorts")
	_check(friend.repairPriority == "ordinary", "friendly repair is ordinary")
	F.adjust(raised, "compact", 25, "long service")
	_check(F.standing(raised, "compact").score == 45 and F.standing(raised, "compact").band == "friendly", "45 stays friendly below the trusted enter")
	F.adjust(raised, "compact", 25, "longer service")
	var trusted: Dictionary = F.access(raised, "brass_haven")
	_check(F.standing(raised, "compact").score == 70 and trusted.band == "trusted", "a later step reaches trusted")
	_check(trusted.intelligence and trusted.repairPriority == "priority" and trusted.militaryFittings, "trusted intelligence and priority repair")
	raised.ports = [{"id": "brass_haven", "name": "Brass Haven", "faction": "forge"}]
	var live: Dictionary = F.access(raised, "brass_haven")
	_check(live.factionId == "forge" and live.band == "neutral", "live port faction overrides the catalog copy")


func _test_hysteresis_bounds_and_events() -> void:
	var state := _fresh()
	var near: Dictionary = F.adjust(state, "compact", 19, "nearly friendly")
	_check(near.score == 19 and near.band == "neutral", "19 has not entered friendly")
	_check(int(state.relationships.log[0].day) == 12, "log uses the campaign day")
	_check(F.standing(state, "raiders").score == F.INITIAL_RAIDER - 6, "19 spills floor(19/3) = 6")
	var entered: Dictionary = F.adjust(state, "compact", 1, "one more")
	_check(entered.score == 20 and entered.band == "friendly", "20 enters friendly")
	var back: Dictionary = F.adjust(state, "compact", -1, "one less")
	_check(back.score == 19 and back.band == "friendly", "dropping back to 19 does not flicker out of friendly")
	_check(F.standing(state, "raiders").score == F.INITIAL_RAIDER - 6, "a one-point change does not spill")
	var windfall := _fresh()
	F.adjust(windfall, "compact", 10000, "windfall")
	_check(F.standing(windfall, "compact").score == F.DELTA_CAP, "one public change caps at 25")
	_check(F.standing(windfall, "raiders").score == F.INITIAL_RAIDER - F.SPILL_CAP, "spill caps at 8")
	for _i in range(6):
		F.adjust(windfall, "compact", 25, "more")
	_check(F.standing(windfall, "compact").score == F.REP_MAX, "public standing caps at 100")
	_check(F.standing(windfall, "raiders").score == F.REP_MIN, "rival standing caps at -100")
	_check(not F.adjust(windfall, "compact", NAN, "bad", "nan-1").ok, "non-finite amount is rejected")
	_check(not F.adjust(windfall, "compact", INF, "bad").ok, "infinite amount is rejected")
	_check(F.standing(windfall, "compact").score == F.REP_MAX, "rejected amounts do not move standing")
	var small := _fresh()
	for _j in range(50):
		F.adjust(small, "compact", 1, "small")
	_check(F.standing(small, "compact").score == 50 and F.standing(small, "compact").band == "trusted", "fifty small steps reach trusted")
	_check(small.relationships.log.size() == F.LOG_LIMIT, "causal log stays bounded")
	_check(F.standing(small, "raiders").score == F.INITIAL_RAIDER, "steps of 1 do not spill")
	var jobs := _fresh()
	var first: Dictionary = F.adjust(jobs, "compact", 10, "convoy", "job-7")
	var second: Dictionary = F.adjust(jobs, "compact", 10, "convoy", "job-7")
	_check(first.changed and first.score == 10 and not first.repeated, "event applies once")
	_check(second.repeated and not second.changed and second.score == 10, "the same event id does not apply again")
	_check(F.standing(jobs, "raiders").score == F.INITIAL_RAIDER - 3, "spill of floor(10/3) happens once")
	_check(jobs.relationships.log.size() == 2, "public change and rival spill are both logged")
	F.adjust(jobs, "compact", 10, "again", "")
	F.adjust(jobs, "compact", 10, "again", "")
	_check(F.standing(jobs, "compact").score == 30 and F.standing(jobs, "compact").band == "friendly", "an empty event id is not idempotent")
	_check(F.standing(jobs, "raiders").score == F.INITIAL_RAIDER - 9, "each untagged help spills again")
	var window := _fresh()
	for n in range(F.EVENT_LIMIT + 5):
		F.adjust(window, "compact", 0, "mark", "id-%d" % n)
	_check(window.relationships.seenOrder.size() == F.EVENT_LIMIT, "remembered event ids stay bounded")
	var replay: Dictionary = F.adjust(window, "compact", 5, "mark", "id-0")
	_check(replay.changed and F.standing(window, "compact").score == 5, "an evicted event id can apply again")


func _test_witness_claim_time_restitution() -> void:
	var claimed := _fresh()
	var toll: Dictionary = F.adjust(claimed, "compact", -10, "claim:brass_haven:unpaid wharf toll")
	_check(toll.score == 0 and toll.band == "neutral" and toll.claimTotal == 10 and toll.witnessed == 0, "a port claim is not public reputation")
	var gate: Dictionary = F.access(claimed, "brass_haven")
	_check(gate.legal and gate.entry == "inspected" and gate.repairPriority == "held" and not gate.militaryFittings and gate.contracts, "a claim inspects and holds fittings without banning work")
	_check(not F.adjust(claimed, "reed", -5, "claim:brass_haven:not theirs").ok, "a claim must belong to that faction's port")
	_check(F.standing(claimed, "compact").claimTotal == 10, "rejected claim is unchanged")
	var paid: Dictionary = F.adjust(claimed, "compact", 10, "claim:brass_haven:toll paid from the purse")
	_check(paid.claimTotal == 0 and paid.score == 0, "paying a claim clears the record and not public standing")
	_check(claimed.coins == 15000, "claim payment does not move coins")
	var cleared: Dictionary = F.access(claimed, "brass_haven")
	_check(cleared.entry == "open" and cleared.repairPriority == "ordinary", "cleared claim restores ordinary access")
	var witnessed := _fresh()
	F.adjust(witnessed, "compact", -25, "witness:fired on a cutter")
	var mid: Dictionary = F.standing(witnessed, "compact")
	_check(mid.score == 0 and mid.witnessed == -25 and mid.band == "neutral" and not mid.hostile, "a witnessed offense stays off the public score")
	var inspected: Dictionary = F.access(witnessed, "brass_haven")
	_check(inspected.entry == "inspected" and inspected.legal and inspected.band == "neutral", "witness at -25 inspects a neutral port")
	F.adjust(witnessed, "compact", -25, "witness:second cutter")
	var grave: Dictionary = F.standing(witnessed, "compact")
	_check(grave.score == 0 and grave.witnessed == -50 and grave.band == "neutral" and grave.hostile, "a capital witness is hostile without changing the public band")
	var shut: Dictionary = F.access(witnessed, "brass_haven")
	_check(shut.entry == "refused" and not shut.legal and shut.reason.find("witnessed") >= 0, "capital witness refuses entry and says why")
	var quiet := _fresh()
	var stopped: Dictionary = F.adjust(quiet, "compact", 25, "time:quiet season")
	_check(not stopped.changed and str(stopped.message).find("neutral") >= 0, "time does not raise a neutral standing")
	var step_a: Dictionary = F.adjust(quiet, "raiders", 25, "time:week")
	_check(step_a.score == -45 and step_a.band == "hostile", "time from -70 stays hostile inside the exit margin")
	var step_b: Dictionary = F.adjust(quiet, "raiders", 25, "time:next")
	_check(step_b.score == -20 and step_b.band == "wary", "the next time step leaves hostility for wary")
	var step_c: Dictionary = F.adjust(quiet, "raiders", 25, "time:after")
	_check(step_c.score == 0 and step_c.band == "neutral", "time stops at neutral")
	var step_d: Dictionary = F.adjust(quiet, "raiders", 25, "time:more")
	_check(not step_d.changed and F.standing(quiet, "raiders").score == 0, "time does not buy friendship")
	_check(F.standing(quiet, "compact").score == 0, "time does not spill onto another faction")
	var blocked := _fresh()
	F.adjust(blocked, "raiders", -8, "claim:shatter_spire:blood price")
	var waiting: Dictionary = F.adjust(blocked, "raiders", 25, "time:waiting")
	_check(not waiting.changed and F.standing(blocked, "raiders").score == F.INITIAL_RAIDER, "an open claim blocks time recovery")
	_check(blocked.coins == 15000, "time and claims do not move coins")
	var debt := _fresh()
	F.adjust(debt, "compact", -25, "witness:collision")
	F.adjust(debt, "compact", -15, "claim:brass_haven:damaged pier")
	var before_raiders: int = int(F.standing(debt, "raiders").score)
	var restored: Dictionary = F.adjust(debt, "compact", 25, "restitution:brass_haven:paid the pier and apologized")
	_check(restored.score == 25 and restored.band == "friendly", "restitution moves public standing")
	_check(restored.witnessed == 0 and restored.claimTotal == 0, "restitution clears the witness and the named claim")
	_check(F.standing(debt, "raiders").score == before_raiders, "restitution does not spill to rivals")
	_check(debt.coins == 15000, "restitution does not mint or spend coins")


func _test_commission() -> void:
	var state := _fresh()
	var warn: Dictionary = F.commission(state, "compact")
	_check(warn.ok and not warn.committed and warn.stipend == 0, "the first commission call only warns")
	_check(warn.enemies.size() == 1 and warn.enemies[0] == "raiders", "the warning names raiders")
	_check(str(warn.warning).find("stipend") >= 0, "the warning says no stipend is minted")
	_check(F.standing(state, "compact").score == 0 and F.standing(state, "raiders").score == F.INITIAL_RAIDER, "a warning changes no standing")
	var refused: Dictionary = F.commission(state, "compact")
	_check(not refused.ok and not refused.committed and refused.stipend == 0, "confirming while neutral does not commit")
	_check(F.standing(state, "raiders").score == F.INITIAL_RAIDER, "a refused commission has no legal shift")
	F.adjust(state, "compact", 20, "escorted a packet")
	_check(F.standing(state, "compact").band == "friendly", "escort work makes compact friendly")
	_check(F.standing(state, "raiders").score == F.INITIAL_RAIDER - 6, "that help spills floor(20/3) before any commission")
	var warn_again: Dictionary = F.commission(state, "compact")
	_check(not warn_again.committed and F.standing(state, "raiders").score == F.INITIAL_RAIDER - 6, "the new warning still does not apply the legal shift")
	var commit: Dictionary = F.commission(state, "compact")
	_check(commit.ok and commit.committed and commit.explicit and commit.stipend == 0, "the second call commits")
	_check(commit.contract.reward == 0 and commit.contract.escrow == 0 and commit.contract.stipend == 0, "the committed contract carries no coins")
	_check(F.standing(state, "raiders").score == F.INITIAL_RAIDER - 18, "legal shift is -12 once, after the earlier spill of 6")
	_check(F.standing(state, "compact").score == 20, "the patron's player reputation is not a stipend or a bonus")
	_check(F.standing(state, "forge").score == 0 and F.standing(state, "reed").score == 0, "commission does not befriend bystanders")
	_check(F.relation(state, "compact", "raiders") == -40, "commission does not change the faction pair")
	_check(not state.has("activeContract") and state.coins == 15000, "commission does not write the campaign contract or coins")
	var again: Dictionary = F.commission(state, "compact")
	_check(again.repeated and F.standing(state, "raiders").score == F.INITIAL_RAIDER - 18, "recording the same commission does not stack the shift")
	var raider_state := _fresh()
	F.commission(raider_state, "raiders")
	var denied: Dictionary = F.commission(raider_state, "raiders")
	_check(not denied.ok and not denied.committed, "a hostile faction refuses the commission")
	_check(F.standing(raider_state, "raiders").score == F.INITIAL_RAIDER and F.standing(raider_state, "compact").score == 0, "refusal moves nobody")
	_check(raider_state.coins == 15000, "a refused commission mints nothing")


func _test_commission_review_and_consent() -> void:
	var state := _fresh()
	F.adjust(state, "compact", 20, "Fulfilled convoy work", "consent-work")
	# Old saves may contain a review left pending by the former modal.
	state.relationships.commission.pending = true
	state.relationships.commission.pendingFactionId = "compact"
	var restored: Dictionary = JSON.parse_string(JSON.stringify(state))
	F.ensure(restored, _world())
	var before: String = JSON.stringify(restored)
	var terms: Dictionary = F.commission_terms(restored, "compact")
	_check(terms.ok and terms.eligible and not terms.committed and not terms.changed and not terms.explicit, "eligible terms remain a review even with saved legacy pending")
	_check(terms.factionName == "Mercantile Compact" and terms.enemyNames == ["Shatter Reef Raiders"] and terms.legalShift == -12, "terms name the real patron, enemy and legal cost")
	_check(str(terms.warning).contains("public standing") and str(terms.warning).contains("stipend"), "terms explain actual standing costs and no income")
	F.commission_terms(restored, "compact")
	F.commission_terms(restored, "forge")
	F.commission_terms(restored, "compact")
	_check(JSON.stringify(restored) == before, "repeated and alternate reviews leave every saved field unchanged")
	terms.enemies.clear()
	terms.enemyNames.append("invented")
	terms.contract.reward = 999
	_check(JSON.stringify(restored) == before and F.commission_terms(restored, "compact").enemies == ["raiders"], "review arrays and contract are detached")
	_check(not F.commission_terms(restored, "missing").ok and JSON.stringify(restored) == before, "unknown terms cannot mutate a campaign")
	var missing := {}
	_check(not F.commission_terms(missing, "compact").ok and missing.is_empty(), "terms never initialize relationship data")
	# Current standing, not an earlier eligible snapshot, governs explicit consent.
	F.adjust(restored, "compact", -25, "Lost public confidence")
	var denied: Dictionary = F.accept_commission(restored, "compact")
	_check(not denied.ok and not denied.committed and F.standing(restored, "raiders").score == F.INITIAL_RAIDER - 6, "lost eligibility refuses stale consent without legal cost")
	F.adjust(restored, "compact", 25, "Earned confidence back")
	F.adjust(restored, "compact", -25, "witness:First documented attack")
	F.adjust(restored, "compact", -25, "witness:Second documented attack")
	_check(not F.accept_commission(restored, "compact").ok and not restored.relationships.commission.committed, "friendly public standing cannot hide a capital witnessed offense")
	# Explicit acceptance needs no pending flag and resolves live faction pairs.
	before = JSON.stringify(state)
	F.commission_terms(state, "compact")
	_check(JSON.stringify(state) == before, "the original review also remains harmless")
	state.relationships.commission.pending = false
	state.relationships.commission.pendingFactionId = ""
	F.set_relation(state, "compact", "forge", -25, "New declared enemy after review")
	var accepted: Dictionary = F.accept_commission(state, "compact")
	_check(accepted.ok and accepted.committed and accepted.changed and accepted.explicit and accepted.enemies == ["forge", "raiders"], "explicit acceptance uses current enemies without legacy pending")
	_check(F.standing(state, "forge").score == -12 and F.standing(state, "raiders").score == F.INITIAL_RAIDER - 18, "each actual enemy receives the original legal shift once")
	_check(state.coins == 15000 and not state.has("activeContract") and accepted.contract.reward == 0 and accepted.contract.escrow == 0 and accepted.stipend == 0, "explicit commission creates no coins or paid campaign contract")
	before = JSON.stringify(state)
	accepted.contract.enemies.clear()
	accepted.contract.reward = 500
	var recorded: Dictionary = F.commission_terms(state, "compact")
	recorded.contract.enemies.clear()
	recorded.contract.reward = 700
	_check(JSON.stringify(state) == before, "acceptance result and recorded review cannot edit stored contract")
	var repeat: Dictionary = F.accept_commission(state, "compact")
	_check(repeat.ok and repeat.repeated and not repeat.changed and JSON.stringify(state) == before, "repeated explicit acceptance changes no saved field")
	var loaded: Dictionary = JSON.parse_string(before)
	F.ensure(loaded, _world())
	_check(F.accept_commission(loaded, "compact").repeated and F.standing(loaded, "forge").score == -12, "save and reload preserve explicit consent and legal deduplication")
	_check(not str(F.access(state, "brass_haven").reason).contains("escorts"), "friendly access does not advertise an unimplemented escort service")
	F.adjust(state, "compact", 25, "More service")
	F.adjust(state, "compact", 25, "Long service")
	var access: Dictionary = F.access(state, "brass_haven")
	_check(access.band == "trusted" and not str(access.reason).contains("intelligence") and not str(access.reason).contains("priority repair"), "trusted access advertises only implemented permissions")


func _test_save_roundtrip() -> void:
	var state := _fresh()
	state.day = 18
	F.adjust(state, "compact", 19, "nearly")
	F.adjust(state, "compact", 1, "edge")
	F.adjust(state, "compact", -1, "flicker")
	F.set_relation(state, "reed", "forge", -33, "channel dues")
	F.adjust(state, "compact", 12, "contact:holt:kept the watch", "holt-1")
	F.adjust(state, "forge", -9, "claim:cinder_quay:broken crane")
	F.adjust(state, "reed", 8, "food run", "food-1")
	var raw: String = JSON.stringify(state)
	var restored = JSON.parse_string(raw)
	_check(restored is Dictionary, "relationships survive JSON")
	var world := _world()
	var before := JSON.stringify(world)
	F.ensure(restored, world)
	_check(JSON.stringify(world) == before, "reload does not mutate world")
	_check(int(F.standing(restored, "compact").score) == 19 and F.standing(restored, "compact").band == "friendly", "hysteresis survives the round trip")
	_check(int(F.standing(restored, "raiders").score) == F.INITIAL_RAIDER - 8, "rival spill survives the round trip")
	_check(F.relation(restored, "forge", "reed") == -33, "pair survives the round trip")
	_check(int(restored.relationships.contacts.holt.trust) == 12, "contact trust survives the round trip")
	_check(int(F.standing(restored, "forge").claimTotal) == 9, "port claim survives the round trip")
	_check(int(F.standing(restored, "reed").score) == 8, "reed help survives the round trip")
	_check(int(restored.coins) == 15000, "coins survive untouched")
	var replay: Dictionary = F.adjust(restored, "reed", 8, "food run", "food-1")
	_check(replay.repeated and int(F.standing(restored, "reed").score) == 8, "a saved event id stays idempotent")
	F.ensure(restored, world)
	_check(restored.relationships.contacts.size() == 4, "ensure does not duplicate contacts")
	_check(int(F.standing(restored, "raiders").score) == F.INITIAL_RAIDER - 8, "another ensure does not reset saved standing")
