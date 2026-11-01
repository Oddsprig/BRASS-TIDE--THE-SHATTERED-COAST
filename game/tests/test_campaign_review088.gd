extends SceneTree
## Root-only native review of eight hash-bound, actual completed save artifacts.
## No new_game, campaign clock, transaction, Main scene, worker or owner save write.
const Campaign = preload("res://scripts/campaign.gd")
const Guidance = preload("res://scripts/campaign_guidance.gd")
const Money = preload("res://scripts/money.gd")
const Equipment = preload("res://scripts/equipment_campaign.gd")
const Stories = preload("res://scripts/coastal_stories.gd")
const BODY_MS: int = 30000
const STOP_MS: int = 28000
const IDS: Array = ["earned078", "loss083", "world075", "fishing086", "freight086", "fuel086", "passenger086", "destinations087"]
const CAREERS: Array = ["explorer", "merchant", "escort", "privateer", "fisher", "passenger"]
const BOAT_FIELDS: Array = ["uid", "type", "crew", "wounded", "shoreCrew", "fuel", "ammo", "supplies", "hp", "maxHp", "sunk", "armor", "engine", "fire", "water", "breaches", "moduleCondition", "equipmentRetiredTo", "boarders", "loadout", "refitLocker", "conversion", "specialistActive", "storedPort", "mothballed", "towed", "needsHarborRepair", "berthArrears", "service", "serviceHistory"]
const STATE_FIELDS: Array = ["seed", "day", "econDay", "world064", "position", "coins", "crewPurse", "coinSupply", "wageArrears", "debt", "cargo", "cargoManifest", "flagship", "nextUid", "wrecks", "wreckSeededSources", "wreckSeq", "voyageJobs", "doneVoyageJobs", "activeContract", "campaignFacts", "civilianWork", "passengerTransport", "regionalCrises", "captiveBerths", "captives", "businesses", "yardProjects", "relationships", "contacts", "marketSnapshots", "storyRights", "sector069", "sectorApplied069", "sectorKnowledge069", "islandOwnership069", "territorial076", "shipping068", "toolingRecovery"]
const PORT_FIELDS: Array = ["id", "regionId", "faction", "cash", "householdPurse", "expertPurse", "governmentPurse", "stocks", "publicStores", "shipStock", "shipIds", "training", "buildQueue", "population", "workforce", "recruits", "recruitRemainder"]
const OWNER_FIELDS: Array = ["id", "coins", "crewPurse", "wageArrears", "cargo", "tradeGood", "tradeCargo"]
var started: int = 0
var checks: int = 0
var failures: Array = []
var rows: Array = []
var bindings: Dictionary = {}
var output: String = ""
var manifest_path: String = ""
var manifest_sha: String = ""
var complete: bool = false
var expired: bool = false
var output_ready: bool = false
var base = null
var c = null

func _initialize() -> void:
	started = Time.get_ticks_msec()
	_run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL campaign088: ", label)
	return value

func bounded() -> bool:
	if Time.get_ticks_msec() - started < STOP_MS:
		return true
	if not expired:
		expired = true
		check(false, "Stop starting work at 28 seconds; incomplete coverage is not a pass")
	return false

func argument(prefix: String) -> String:
	for value in OS.get_cmdline_user_args():
		if str(value).begins_with(prefix):
			return str(value).trim_prefix(prefix)
	return ""

func digest(value: String) -> bool:
	return value.length() == 64 and value.to_lower() == value and value.is_valid_hex_number(false)

func same_values(a, b) -> bool:
	# Reuse070's exact decoded-value contract, with no epsilon or price rounding.
	if (a is int or a is float) and (b is int or b is float):
		return a == b
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not same_values(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in range(a.size()):
			if not same_values(a[index], b[index]): return false
		return true
	return a == b

func fields_equal(before: Dictionary, after: Dictionary, fields: Array, label: String) -> bool:
	for key in fields:
		if before.has(key) and not check(after.has(key) and same_values(before[key], after[key]), label + "." + str(key) + " exact saved values"):
			return false
	return true

func boats_equal(before: Array, after: Array, label: String) -> bool:
	if not check(before.size() == after.size(), label + " keeps every original hull and no extra hull"):
		return false
	for index in range(before.size()):
		if not fields_equal(before[index], after[index], BOAT_FIELDS, label + "[" + str(index) + "]"):
			return false
	return true

func continuity(saved: Dictionary, actual: Dictionary, label: String) -> bool:
	if not fields_equal(saved, actual, STATE_FIELDS, label): return false
	if not check(Money.total(saved) == int(saved.coinSupply) and Money.total(actual) == int(saved.coinSupply), label + " exact finite world coin total"):
		return false
	for key in ["fleet", "boardingPrizes"]:
		if not boats_equal(saved.get(key, []), actual.get(key, []), label + "." + key): return false
	for pair in [["ports", PORT_FIELDS], ["fleetOwners", OWNER_FIELDS]]:
		var old: Array = saved.get(pair[0], [])
		var now: Array = actual.get(pair[0], [])
		if not check(old.size() == now.size(), label + "." + pair[0] + " preserves every account"):
			return false
		for index in range(old.size()):
			var scope: String = label + "." + pair[0] + "[" + str(index) + "]"
			if not fields_equal(old[index], now[index], pair[1], scope): return false
			if pair[0] == "fleetOwners" and not boats_equal(old[index].get("boats", []), now[index].get("boats", []), scope + ".boats"):
				return false
	# Existing specialists predate two false lifecycle defaults; retain every
	# recorded value, matching070's explicit legacy normalization only.
	var old_specialists: Array = saved.get("specialists", []).duplicate(true)
	var now_specialists: Array = actual.get("specialists", []).duplicate(true)
	for collection in [old_specialists, now_specialists]:
		for person in collection:
			person.discharged = bool(person.get("discharged", false))
			person.lost = bool(person.get("lost", false))
	if not check(same_values(old_specialists, now_specialists), label + " paid specialist identity and terms"):
		return false
	var old_story: Dictionary = saved.get("stories", {})
	var now_story: Dictionary = actual.get("stories", {})
	if not fields_equal(old_story, now_story, ["destinations087", "consequences", "events"], label + ".stories"):
		return false
	for id in old_story.get("chains", {}):
		if not check(same_values(old_story.chains[id], now_story.get("chains", {}).get(id)), label + " existing story record " + str(id)):
			return false
	var old_sites: Dictionary = saved.get("exploration", {}).get("sites", {})
	for id in old_sites:
		if not check(same_values(old_sites[id], actual.get("exploration", {}).get("sites", {}).get(id)), label + " existing surveyed/visited site " + str(id)):
			return false
	if not saved.has("sector069") and not check(not actual.has("sector069"), label + " legacy geography remains ungenerated"):
		return false
	var gear: Dictionary = Equipment.check_state(actual, c.data)
	return check(bool(gear.get("ok", false)) and bool(gear.get("ready", false)), label + " canonical unique equipment UIDs, condition and custody: " + str(gear.get("message", "")))

func protected_state() -> PackedByteArray:
	return var_to_bytes([c.state, c.events, c.pending_days, c.data, c.nav, c.ocean_context064, c.ocean_context066, c.route_cache, c.route_hits, c.route_misses, c.ocean_watch066, c.ocean_conditions066, c.exploration_timer, c.sailing_clearance, c.travel_lock064])

func restore_input(saved: Dictionary, label: String, metrics: Dictionary) -> bool:
	if not bounded(): return false
	c = Campaign.new(base.data, base.nav, false)
	c.ocean_anchors064 = base.ocean_anchors064
	var frozen: PackedByteArray = var_to_bytes(saved)
	var began: int = Time.get_ticks_usec()
	var result: Dictionary = c.restore(saved)
	metrics.restoreUs = Time.get_ticks_usec() - began
	return check(bool(result.get("ok", false)), label + " current restore: " + str(result.get("message", ""))) and check(var_to_bytes(saved) == frozen, label + " caller dictionary untouched") and check(c.pending_days == 0, label + " no pending worker days") and continuity(saved, c.state, label)

func guidance_reading(id: String, careers: Array, metrics: Dictionary) -> bool:
	var frozen: PackedByteArray = protected_state()
	metrics.guidance = []
	for career in careers:
		if not bounded(): return false
		var began: int = Time.get_ticks_usec()
		var report: Dictionary = Guidance.report(c, 0.0, str(career))
		var usec: int = Time.get_ticks_usec() - began
		var plan: Dictionary = report.get("careerPlan", {})
		if not check(report.get("ok", false) and str(report.get("career", "")) == career and str(plan.get("id", "")) == career, id + " current " + career + " guidance contract"):
			return false
		# The actual coastal planner deliberately returns no job/reward while
		# outside HOME. A clear return blocker is valid remote guidance.
		var explained: Array = ["firstGoal", "nextStep", "rewardSource", "limits"] if c.home_local064() else ["nextStep", "limits"]
		for field in explained:
			if not check(not str(plan.get(field, "")).is_empty(), id + " " + career + " explains " + field): return false
		if not c.home_local064() and not check(not plan.get("ready", true) and not plan.get("blockers", []).is_empty(), id + " remote coastal plan honestly requires a HOME return"):
			return false
		if not check(bool(plan.get("ready", false)) == plan.get("blockers", []).is_empty(), id + " " + career + " readiness follows actual blockers"):
			return false
		if not check(protected_state() == frozen, id + " " + career + " preview preserves typed state, purses, navigation and runtime"):
			return false
		metrics.guidance.append({"career":career, "queryUs":usec, "plan":plan, "cards":report.get("cards", []), "warnings":report.get("warnings", []), "coverage":"READ_ONLY_GUIDANCE_NOT_COMPLETED_CAREER"})
	return true

func roundtrip(id: String, metrics: Dictionary) -> bool:
	if not bounded(): return false
	var payload: String = JSON.stringify(c.state, "\t", true, true)
	var decoded = JSON.parse_string(payload)
	if not check(decoded is Dictionary and continuity(c.state, decoded, id + " current encoding"), id + " full-precision current save encodes exact protected values"):
		return false
	var path: String = output.path_join("campaign088-" + id + "-reopened.json")
	if not check(not FileAccess.file_exists(path), "Private round-trip output is fresh: " + id): return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not check(file != null, "Open only the fresh private round-trip output: " + id): return false
	file.store_string(payload)
	var written: bool = file.get_error() == OK
	file.close()
	if not check(written and FileAccess.get_sha256(path) == payload.sha256_text(), id + " current disk copy hash"):
		return false
	var disk = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not check(disk is Dictionary and same_values(decoded, disk), id + " private file contains the actual whole state"):
		return false
	var timing: Dictionary = {}
	if not restore_input(disk, id + " private current disk reopen", timing): return false
	metrics.currentRoundtrip = {"path":path, "sha256":FileAccess.get_sha256(path), "restoreUs":timing.restoreUs, "reconstructed":false}
	return true

func witness_shape(id: String, saved: Dictionary) -> bool:
	# Guard the named selection against an opening/blocked file substituted for
	# a completed artifact. Historical earnings still require Root's receipts.
	var fleet: Array = saved.get("fleet", [])
	if id == "earned078":
		return check(int(saved.get("coins", -1)) == 15146 and saved.get("doneVoyageJobs", []).size() == 4 and fleet.size() == 1 and bool(fleet[0].get("specialistActive", {}).get("surveyor", false)), "078 selection is the actual completed paid survey/freight and Surveyor state")
	if id == "loss083":
		var lost: Array = saved.get("wrecks", []).filter(func(w): return str(w.get("uid", "")) == "boat-1")
		return check(fleet.size() == 1 and str(fleet[0].get("uid", "")) == "boat-2" and not fleet[0].get("sunk", true) and lost.size() == 1 and str(lost[0].get("retiredSourceUid", "")) == "boat-1" and str(lost[0].get("equipmentCustody", "")) == "wreck" and not lost[0].get("sourceModuleCondition", {}).get("items", {}).is_empty() and not saved.get("doneVoyageJobs", []).is_empty(), "083 selection has original survivor, physical loss equipment and paid work ledger")
	if id == "world075":
		var damaged: bool = false
		for wreck in saved.get("wrecks", []):
			if str(wreck.get("sourceId", "")) != "npc:patrol-6:npc-6-0": continue
			for item in wreck.get("sourceModuleCondition", {}).get("items", {}).values():
				if float(item.get("hp", 1.0)) < 1.0: damaged = true
		return check(float(saved.get("day", 0)) >= 14.0 and damaged, "075 selection is later world traffic with the actual damaged NPC wreck")
	if id == "destinations087":
		var chains: Dictionary = saved.get("stories", {}).get("chains", {})
		var used: bool = saved.get("storyRights", {}).get("usedOffers", {}).get("chainfreight-meridian-public087", false)
		var wrecks: Array = saved.get("wrecks", []).filter(func(w): return str(w.get("sourceId", "")).begins_with("site:unfinished_keel087:"))
		return check(bool(chains.get("broken_meridian087", {}).get("done", false)) and bool(chains.get("unfinished_keel087", {}).get("done", false)) and used and wrecks.size() == 1 and float(wrecks[0].get("stores", {}).get("iron", -1)) == 5.0 and saved.get("wreckSeededSources", {}).has(str(wrecks[0].sourceId)), "087 selection is connected completion, later paid offer and depleted original slipway source")
	var hulls: Dictionary = {"fishing086":"kelpnet_dory", "freight086":"fenhopper_lighter", "fuel086":"seepoil_tanker", "passenger086":"gullwing_daysailer"}
	var fitting: String = "auxiliary_tanks" if id == "fuel086" else "cargo_rig"
	var matched: Array = fleet.filter(func(b): return str(b.get("type", "")) == hulls[id] and str(b.get("conversion", "")) == fitting and int(b.get("crew", 0)) > 0)
	var work_done: bool = not saved.get("civilianWork", {}).get("sites", {}).is_empty() if id == "fishing086" else not saved.get("doneVoyageJobs", []).is_empty()
	return check(matched.size() == 1 and work_done, id + " actual working hull, completed work/quota and paid conversion; no opening substitute")

func review_case(record: Dictionary) -> bool:
	var id: String = str(record.id)
	var path: String = str(record.path)
	var began: int = Time.get_ticks_usec()
	var saved = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not check(saved is Dictionary, id + " bound original state decodes"): return false
	if not witness_shape(id, saved): return false
	var metrics: Dictionary = {"id":id, "input":record.duplicate(true), "coverage":"ACTUAL_SAVED_STATE_RESTORE", "day":saved.get("day"), "coins":saved.get("coins"), "originalSha256":bindings[path]}
	rows.append(metrics)
	if not restore_input(saved, id, metrics): return false
	var selected: Array = CAREERS if id in ["earned078", "loss083", "world075"] else ["fisher"] if id == "fishing086" else ["passenger"] if id == "passenger086" else ["explorer"] if id == "destinations087" else ["merchant"]
	if not guidance_reading(id, selected, metrics): return false
	if id == "destinations087":
		var frozen: PackedByteArray = protected_state()
		metrics.destinationJournal = Stories.journal(c.state)
		if not check(protected_state() == frozen, "087 completed journal is a pure reading"): return false
	if id in ["loss083", "destinations087"] and not roundtrip(id, metrics): return false
	metrics.elapsedUs = Time.get_ticks_usec() - began
	metrics.complete = true
	c = null
	return bounded()

func _run() -> void:
	output = OS.get_environment("GAME_TEST_ARTIFACTS").replace("\\", "/").simplify_path()
	manifest_path = argument("--qa-review088-manifest=")
	manifest_sha = argument("--qa-review088-manifest-sha256=")
	if not check(DisplayServer.get_name() == "headless", "Root runs headless with Dummy audio and a synthetic profile") or not check(output.is_absolute_path() and DirAccess.dir_exists_absolute(output), "Root supplies an existing private absolute artifact directory"):
		finish(); return
	if not check(manifest_path.is_absolute_path() and digest(manifest_sha) and FileAccess.get_sha256(manifest_path) == manifest_sha, "Required CLI manifest is pinned by its original SHA256"):
		finish(); return
	bindings[manifest_path] = manifest_sha
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not check(manifest is Dictionary and manifest.get("schema") == 1 and manifest.get("cases") is Array and manifest.cases.size() == IDS.size(), "Exactly eight scoped actual save records; missing coverage fails"):
		finish(); return
	var indexed: Dictionary = {}
	for record in manifest.cases:
		if not check(record is Dictionary and record.get("id") in IDS and not indexed.has(record.get("id")), "Every manifest record has one unique scoped ID"):
			finish(); return
		var id: String = str(record.id)
		var path: String = str(record.get("path", ""))
		var sha: String = str(record.get("sha256", ""))
		var staged: bool = id.ends_with("086") or id == "destinations087"
		if not check(path.is_absolute_path() and digest(sha) and not bindings.has(path) and FileAccess.get_sha256(path) == sha, id + " original save exists with its exact expected hash"):
			finish(); return
		if not check(record.get("stagedOpening") is bool and bool(record.stagedOpening) == staged and record.get("earnedFromDefaultStarter") is bool and bool(record.earnedFromDefaultStarter) == (id in ["earned078", "loss083"]) and not str(record.get("source", "")).is_empty() and not str(record.get("stage", "")).is_empty() and not str(record.get("limits", "")).is_empty(), id + " explicit historical source, stage, staging and limits"):
			finish(); return
		var file := FileAccess.open(path, FileAccess.READ)
		if not check(file != null and file.get_length() < 8 * 1024 * 1024, id + " save stays within eight MiB input bound"):
			finish(); return
		file.close()
		bindings[path] = sha
		indexed[id] = record
	# All future write targets are distinct from every bound input and must be new.
	for name in ["campaign-review088-result.json", "campaign088-loss083-reopened.json", "campaign088-destinations087-reopened.json"]:
		var target: String = output.path_join(name)
		for input_path in bindings:
			if not check(target.to_lower() != str(input_path).replace("\\", "/").simplify_path().to_lower(), "No output target aliases a bound input path"):
				finish(); return
		if not check(not FileAccess.file_exists(target), "Fresh private output: " + name): finish(); return
	output_ready = true
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	if not check(data is Dictionary, "Current world authority loads"): finish(); return
	base = Campaign.new(data)
	for id in IDS:
		if not bounded() or not review_case(indexed[id]): finish(); return
	complete = true
	finish()

func finish() -> void:
	c = null
	base = null
	for path in bindings:
		check(FileAccess.get_sha256(path) == bindings[path], "Original input bytes remain unchanged: " + str(path).get_file())
	var elapsed: int = Time.get_ticks_msec() - started
	check(elapsed < BODY_MS, "Body including original hash rechecks and retirement below thirty seconds")
	var pending: Array = []
	for id in IDS:
		if not rows.any(func(row): return row.get("id") == id and row.get("complete", false)): pending.append(id)
	var result: Dictionary = {"schema":1, "fixture":"campaign_review088", "status":"COMPLETED_SAVED_STATE_REVIEW" if complete and failures.is_empty() else "INCOMPLETE_OR_FAILED", "ok":complete and failures.is_empty(), "checks":checks, "failures":failures.size(), "failureLabels":failures, "elapsedMs":elapsed, "bodyLimitMs":BODY_MS, "workStopMs":STOP_MS, "manifest":{"path":manifest_path, "sha256":manifest_sha}, "cases":rows, "unreviewedIds":pending, "originalInputs":bindings, "newEarnedPlaythroughs":0, "stagedRoleSaves":true, "workersStarted":0, "ownerInputWrites":0, "qualityTargetPass":false,
		"skips":["No new088 ordinary voyage, battle, loss, recovery, job acceptance or economic day replay; Root binds accepted historical receipts.", "Escort and Privateer guidance is reviewed; no player-completed Escort or bounty save is supplied or claimed.", "086 openings use staged paid specialist hulls;087 uses staged berths/finite treasury reserve. No earned ocean crossing or four default-starter careers.", "All six guidance plans on078/083/075; one relevant plan on each086/087 state. No all-save/all-career play matrix.", "CPU restore/query durations are current saved-campaign measurements, not campaign-frame/GPU timing, sustainable NPC profitability or long-term balance.", "Derived routes, render specs and lazy empty administrative defaults are outside exact physical continuity; original money, cargo, equipment, recorded stories/sites and depletion remain exact.", "No title/settings screenshot, motion, retail battle measurement, listening, enjoyment or whole-game/parity acceptance."]}
	var report_path: String = output.path_join("campaign-review088-result.json")
	if output_ready and not FileAccess.file_exists(report_path):
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(result, "\t", true, true))
			var written: bool = file.get_error() == OK
			file.close()
			if not written: result.ok = false
		else: result.ok = false
	else: result.ok = false
	# Serialization and report I/O are also charged. Never print a pass after30s.
	result.elapsedMs = Time.get_ticks_msec() - started
	if int(result.elapsedMs) >= BODY_MS: result.ok = false
	if not result.ok: result.status = "INCOMPLETE_OR_FAILED"
	print("CAMPAIGN088_RESULT ", JSON.stringify(result, "", true, true))
	print("Campaign088: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if result.ok else 1)
