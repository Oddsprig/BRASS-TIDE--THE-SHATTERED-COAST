extends "res://tests/test_wake045.gd"
## Root-only selection of existing producer and native ribbon regressions.
func run() -> void:
	if DisplayServer.get_name() != "headless":
		quit(2)
		return
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	for id in ["bilge_punt", "brasswind_motor_galleon", "fourport_packet"]:
		var spec: Dictionary = Lab.hull(world, id)
		check(not spec.is_empty(), "081 reference hull exists: " + id)
		if not spec.is_empty():
			chart_cases(spec)
	slow_turn_cases()
	frame_batch_case051()
	print("Wake081: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
