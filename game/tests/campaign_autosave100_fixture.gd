extends RefCounted
## Callable fixture for Root's ONE existing headless batch. Never launches an engine.
## Semaphore gating is FUNCTIONAL fault scheduling, never a performance workload.
const Money100 = preload("res://scripts/money.gd")

class HeldWorkers100 extends "res://scripts/economy_workers.gd":
	var gate = Semaphore.new()
	var timing_mutex = Mutex.new()
	var released: bool = false
	var finish_calls: int = 0
	var force_calls: int = 0
	var start_us: int = 0
	var finish_us: int = 0
	var native_work_us: Dictionary = {}
	func start(ports: Array, count: int, blocked: Array, seed_value: int) -> void:
		var begun: int = Time.get_ticks_usec()
		super.start(ports, count, blocked, seed_value)
		start_us = Time.get_ticks_usec() - begun
	func _work(index: int) -> void:
		gate.wait() # Original copied job, RNG and economy calculation follow unchanged.
		var begun: int = Time.get_ticks_usec()
		super._work(index)
		var elapsed: int = Time.get_ticks_usec() - begun
		timing_mutex.lock()
		native_work_us[index] = elapsed
		timing_mutex.unlock()
	func release_all() -> void:
		if released:return
		released = true
		for _index in range(jobs.size()):gate.post()
	func finish(force: bool = false) -> Dictionary:
		finish_calls += 1
		if force:
			force_calls += 1
			# A baseline regression fails its assertions rather than deadlocking the lane.
			release_all()
		var begun: int = Time.get_ticks_usec()
		var result: Dictionary = super.finish(force)
		finish_us = Time.get_ticks_usec() - begun
		return result

class ObservedMain100 extends "res://scripts/main.gd":
	var save_calls: int = 0
	var primary_commits: int = 0
	var retire_calls: int = 0
	var refuse_primary_commit: bool = false
	var save_us: Array = []
	func save_game(show_notice: bool = true, allow_settled_battle: bool = false) -> bool:
		save_calls += 1
		var begun: int = Time.get_ticks_usec()
		var result: bool = super.save_game(show_notice, allow_settled_battle)
		save_us.append(Time.get_ticks_usec() - begun)
		return result
	func _commit_save_file(staged: String, path: String) -> int:
		if refuse_primary_commit and path.get_file() == "voyage.json":return ERR_CANT_CREATE
		var error: int = super._commit_save_file(staged, path)
		if error == OK and path.get_file() == "voyage.json":primary_commits += 1
		return error
	func _retire_battle_driver051() -> void:
		retire_calls += 1
		super._retire_battle_driver051()

var checks: int = 0
var failures: Array[String] = []
var completed: bool = false
var started_ms: int = 0
var game
var workers
var observation: Dictionary = {}

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL campaign autosave100: " + label)
	return ok

func file_snapshot(folder: String) -> Dictionary:
	var result: Dictionary = {}
	for name: String in DirAccess.get_files_at(folder):
		result[name] = FileAccess.get_sha256(folder.path_join(name))
	return result

func exercise(tree: SceneTree) -> void:
	game.new_game(89089) # Actual full fresh career and verified opening save.
	if not check(game.mode == "campaign" and game.has_save(), "Actual Main creates and saves the seeded opening"):return
	if not check(game.core.state.get("sector069", {}).get("bands", {}).size() == 48 and game.data.HULLS.size() == 36, "Populated48-group world and36-hull catalogue retained"):return
	var primary: String = game.save_directory.path_join("voyage.json")
	var opening_supply: int = int(game.core.state.coinSupply)
	if not check(Money100.total(game.core.state) == opening_supply, "Opening conserved world purses"):return
	var old_econ_day: int = int(game.core.state.econDay)
	var began: int = Time.get_ticks_usec()
	game.core.wait_day() # Existing bounded real45-second simulation path; no clock/cash staging.
	game.core.step(1.0 / 60.0) # One ordinary interval crosses a possible float calendar boundary.
	observation["waitDaySimulationUs"] = Time.get_ticks_usec() - began
	if not check(game.core.pending_days == 1, "Actual wait_day advances to one pending native harbor day"):return
	workers = HeldWorkers100.new()
	game.economy_workers = workers
	game.save_timer = 21.0
	var prior_files: Dictionary = file_snapshot(game.save_directory)
	var prior_state: String = JSON.stringify(game.core.state)
	var saves_before: int = game.save_calls
	var commits_before: int = game.primary_commits
	began = Time.get_ticks_usec()
	game._process(0.001) # Starts the REAL copied WorkerThreadPool group from pending_days.
	observation["heldDueProcessUs"] = Time.get_ticks_usec() - began
	if not check(game.economy_task >= 0 and game.core.pending_days == 0 and workers.group_id >= 0 and not workers.ready(), "Due autosave frame has a real unfinished native economy group"):return
	check(workers.finish_calls == 0 and workers.force_calls == 0, "Due autosave never force-joins the held native jobs")
	check(game.save_calls == saves_before and game.primary_commits == commits_before and file_snapshot(game.save_directory) == prior_files, "Pending-day start does not invoke save or write any save file")
	check(game.save_timer > 21.0 and JSON.stringify(game.core.state) == prior_state, "Due timer retained and no partial daily state published")
	game._process(0.001)
	check(game.economy_task >= 0 and workers.finish_calls == 0 and game.save_timer > 21.0 and file_snapshot(game.save_directory) == prior_files, "Repeated inflight frame stays nonblocking, due and unwritten")
	workers.release_all()
	var released_us: int = Time.get_ticks_usec()
	while not workers.ready():
		if Time.get_ticks_usec() - released_us > 8000000:
			check(false, "Real native economy finishes within8-second fixture reserve")
			return
		await tree.process_frame
	observation["releasedToObservedReadyUs"] = Time.get_ticks_usec() - released_us
	# Main automatic processing stays disabled; publish once before observing its save.
	began = Time.get_ticks_usec()
	game._finish_economy(false)
	observation["joinAndDailyPublicationUs"] = Time.get_ticks_usec() - began
	observation["workerJoinAndCollectionUs"] = workers.finish_us
	observation["mainSnapshotAndEnqueueUs"] = workers.start_us
	observation["nativePortWorkUs"] = workers.native_work_us.duplicate()
	if not check(game.economy_task < 0 and game.core.pending_days == 0 and int(game.core.state.econDay) == old_econ_day + 1 and workers.finish_calls == 1 and workers.force_calls == 0, "One real completion publishes one daily settlement without forced join"):return
	check(Money100.total(game.core.state) == opening_supply, "Native daily publication conserves all world coins")
	var settled: String = JSON.stringify(game.core.state, "\t")
	var due_before_save: float = game.save_timer
	game._process(0.001)
	var committed: String = FileAccess.get_file_as_string(primary)
	var saved = JSON.parse_string(committed)
	check(due_before_save > 20.0 and game.save_timer == 0.0 and game.save_calls == saves_before + 1 and game.primary_commits == commits_before + 1, "First settled process frame commits the one due autosave")
	check(committed == settled, "Verified primary contains the exact complete settled serialization")
	if not check(saved is Dictionary, "Committed native save parses as a dictionary"):return
	check(int(saved.coins) == int(game.core.state.coins) and int(saved.crewPurse) == int(game.core.state.crewPurse) and saved.day == JSON.parse_string(settled).day and int(saved.econDay) == old_econ_day + 1, "Committed actual captain/crew purses and serialized day match settlement")
	check(saved.cargo == JSON.parse_string(settled).cargo, "Committed cargo is the actual settled cargo")
	game._process(0.001)
	check(game.save_calls == saves_before + 1 and game.primary_commits == commits_before + 1 and FileAccess.get_file_as_string(primary) == committed and JSON.stringify(game.core.state, "\t") == settled, "Next frame neither saves nor applies the day a second time")
	check(game.save_game(false), "Explicit Save still uses the complete verified writer")
	game.refuse_primary_commit = true
	var before_retire: int = game.retire_calls
	check(not game.quit_game() and game.mode == "campaign" and game.retire_calls == before_retire and FileAccess.get_file_as_string(primary) == committed, "Actual Quit refuses failed primary commit before retirement")
	check(not game.return_to_title() and game.mode == "campaign" and game.retire_calls == before_retire and FileAccess.get_file_as_string(primary) == committed, "Actual title return refuses failed primary commit before retirement")
	game.refuse_primary_commit = false
	check(game.return_to_title() and game.mode == "menu" and game.primary_commits == commits_before + 3, "Successful title return keeps its explicit verified save behavior")
	observation["saveCallUs"] = game.save_us.duplicate()
	observation["saveCallOrder"] = ["opening", "settled-autosave", "manual", "refused-quit", "refused-title", "successful-title"]
	observation["settled"] = {"coins":int(saved.coins), "crewPurse":int(saved.crewPurse), "day":saved.day, "econDay":saved.econDay, "cargo":saved.cargo, "coinSupply":opening_supply}
	completed = true

func run(tree: SceneTree, profile_root: String) -> Dictionary:
	started_ms = Time.get_ticks_msec()
	var artifacts: String = OS.get_environment("GAME_TEST_ARTIFACTS").replace("\\", "/").simplify_path().trim_suffix("/")
	profile_root = profile_root.replace("\\", "/").simplify_path().trim_suffix("/")
	if not check(DisplayServer.get_name() == "headless", "Root's single batch is headless"):return result()
	if not check(artifacts.is_absolute_path() and profile_root.is_absolute_path() and profile_root.to_lower().begins_with(artifacts.to_lower() + "/"), "Fresh fixture profile is strictly inside GAME_TEST_ARTIFACTS"):return result()
	if not check(not DirAccess.dir_exists_absolute(profile_root) and not FileAccess.file_exists(profile_root), "Fresh profile only; no existing files overwritten"):return result()
	if not check(DirAccess.make_dir_recursive_absolute(profile_root) == OK, "Private profile opens"):return result()
	game = ObservedMain100.new()
	game.name = "BrassTide"
	game.qa_ocean066 = true # Existing seam: synthetic preferences/saves, no Desktop music scan.
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	tree.root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	# _ready may enable callbacks; keep the fixture manually scheduled after entry.
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.save_directory = profile_root.path_join("saves")
	game.preferences_path = profile_root.path_join("settings.json")
	game.audio.enabled = false
	game.music.enabled = false
	observation["sourceSha256"] = {"main":FileAccess.get_sha256("res://scripts/main.gd"), "economyWorkers":FileAccess.get_sha256("res://scripts/economy_workers.gd"), "world":FileAccess.get_sha256("res://data/world.json")}
	await exercise(tree)
	# Always release our own semaphore before Main's existing worker retirement.
	if workers != null:workers.release_all()
	game.queue_free()
	await tree.process_frame
	return result()

func result() -> Dictionary:
	print("campaign autosave100: %d checks, %d failures" % [checks, failures.size()])
	return {"complete":completed, "checks":checks, "failures":failures.duplicate(), "elapsed_ms":Time.get_ticks_msec() - started_ms, "observation":observation, "limits":"Functional native-worker scheduling regression with a semaphore-held job. Timings describe this one headless fixture, excluding its intentional semaphore hold where named; not campaign FPS, representative performance, matched before/after improvement, rendering or release acceptance."}
