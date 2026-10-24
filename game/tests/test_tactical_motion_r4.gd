extends SceneTree
## One prospective r4 scenario per bounded process. Never pads a terminal encounter.
const F=preload("res://tests/tactical_fixture_r4.gd")
var checks: int=0
var failures: int=0

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL tactical_motion: "+message)

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":quit(2);return
	var case_name: String="A1.stationary_heavy.authored"
	var path: String=""
	var seed: int=30011
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):case_name=arg.substr(7)
		if arg.begins_with("--seed="):seed=int(arg.substr(7))
		if arg.begins_with("--out="):path=arg.substr(6)
	var parts: PackedStringArray=case_name.split(".")
	if parts.size()!=3 or not parts[2] in ["authored","teams_swapped"]:quit(2);return
	var definitions: Dictionary=F.config()
	var result: Dictionary=F.run_case(definitions,parts[0],parts[1],seed,parts[2],int(definitions.behavior_protocol.ticks))
	check(not result.has("error") and result.has("metrics"),"frozen scenario and current native API are valid")
	check(result.get("status","") in ["COMPLETE_OBSERVATION_WINDOW","TERMINAL_OUTCOME"],"actual bounded observation completes or reaches a real outcome")
	for message in result.get("failures",[]):check(false,str(message))
	check(result.get("failures",[]).is_empty(),"physical behavior, memory, shot, separation and finite-store requirements hold")
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"result":result}));file.close()
	print("OBS motion "+JSON.stringify(result.get("metrics",{})))
	print("Tactical motion r4 %s: %d checks, %d failures"%[case_name,checks,failures])
	quit(0 if failures==0 else 1)
