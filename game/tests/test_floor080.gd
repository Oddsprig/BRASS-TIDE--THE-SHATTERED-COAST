extends "res://tests/test_tactical_ai.gd"
func _initialize() -> void:
	if DisplayServer.get_name()!="headless":quit(2);return
	goals_live051()
	for st: Dictionary in worker_states051:T.retire_planning051(st)
	T.drain_planning051()
	print("Floor080: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
