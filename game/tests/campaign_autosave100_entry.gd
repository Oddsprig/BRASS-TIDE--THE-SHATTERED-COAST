extends SceneTree
## One-case glue only, using the author's existing callable fixture.
## Root stages BOTH scripts in its scratch game/tests. Never a second engine.
var _started_ms: int = 0
var _budget_ms: int = 25000
var _report_path: String = ""

func _initialize() -> void:
	_started_ms = Time.get_ticks_msec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture-budget-ms="):
			_budget_ms = int(arg.trim_prefix("--fixture-budget-ms="))
	if _budget_ms <= 0 or _budget_ms > 25000:
		quit(2)
		return
	create_timer(float(_budget_ms) / 1000.0, true, false, true).timeout.connect(_timeout)
	call_deferred("_run")

func _timeout() -> void:
	push_error("Campaign autosave selected batch wall deadline; incomplete, no retry.")
	quit(124)

func _run() -> void:
	var artifacts: String = OS.get_environment("GAME_TEST_ARTIFACTS").replace("\\", "/").simplify_path()
	if DisplayServer.get_name() != "headless" or not artifacts.is_absolute_path():
		quit(2)
		return
	_report_path = artifacts.path_join("campaign-autosave100-result.json")
	if FileAccess.file_exists(_report_path) or DirAccess.dir_exists_absolute(_report_path):
		quit(2)
		return
	var fixture_type = load("res://tests/campaign_autosave100_fixture.gd")
	if fixture_type == null or not fixture_type.can_instantiate():
		quit(2)
		return
	var fixture = fixture_type.new()
	if not fixture is RefCounted or not fixture.has_method("run"):
		quit(2)
		return
	var report: Dictionary = await fixture.run(self, artifacts.path_join("campaign-autosave100-profile"))
	if Time.get_ticks_msec() - _started_ms >= _budget_ms:
		_timeout()
		return
	# Persist the AUTHOR'S dictionary unchanged, not an alternative result schema.
	var file = FileAccess.open(_report_path, FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(report))
	file.flush()
	var error: int = file.get_error()
	file.close()
	if error != OK:
		quit(2)
		return
	if not report.get("complete") is bool or not report.get("checks") is int or not report.get("failures") is Array or not report.get("elapsed_ms") is int:
		quit(2)
		return
	quit(0 if report.complete and report.checks > 0 and report.failures.is_empty() else 1)
