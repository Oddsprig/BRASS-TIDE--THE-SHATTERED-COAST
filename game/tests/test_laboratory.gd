extends SceneTree
const Main=preload("res://scripts/main.gd")
const Lab=preload("res://scripts/fleet_lab.gd")
const Money=preload("res://scripts/money.gd")
var checks=0
var failures=0

func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;push_error("LAB TEST: "+message)

func _initialize():call_deferred("run")

func run():
	var game=Main.new();root.add_child(game)
	await process_frame
	game.audio.enabled=false
	game.save_directory=ProjectSettings.globalize_path("res://../qa/lab-saves")
	check(game.mode=="menu","starts on title")
	check(game.music.headless and game.music.tracks.size()>=2,"silent music-library detection")
	for track in game.music.tracks:
		var stream: AudioStream=game.music.load_track(track.path)
		check(stream!=null and stream.get_length()>1.0,"decodes supplied music "+track.title)
	for spec in game.data.HULLS:
		var config: Dictionary={"player":[Lab.entry(game.data,spec.id)],"enemy":[Lab.entry(game.data,"tin_skiff")]}
		var result: Dictionary=Lab.create(game.data,config,19)
		check(result.ok and result.battle.ships.size()==2,"actual hull fixture "+spec.id)
		check(result.battle.ships[0].crew==spec.crewOptimal,"fixture fully crewed "+spec.id)
	check(not Lab.inspect(game.data,Lab.preset(game.data,"reserve_boundary")).ok,"over-cap roster rejected instead of dropped")
	var full: Dictionary=Lab.create(game.data,Lab.preset(game.data,"full_300"),83)
	check(full.ok and full.battle.ships.size()==40 and full.battle.deployment.player==300 and full.battle.deployment.enemy==300,"forty-boat 300 per-side lab")
	var bad: Dictionary=Lab.preset(game.data,"duel");bad.player[0].loadout.engine="heavy_drive"
	check(not Lab.inspect(game.data,bad).ok,"incompatible fitting rejected")
	game.new_game();game.paused=true
	var original=game.core
	var saved: String=FileAccess.get_file_as_string(game.save_directory.path_join("voyage.json"))
	var snapshot: Dictionary=original.state.duplicate(true)
	var coins: int=Money.total(snapshot)
	game.open_lab()
	check(game.ui.modal_kind=="lab" and game.ui.modal_open,"title-accessible fleet builder")
	game.lab_config=Lab.preset(game.data,"all_weapons");game.lab_seed=83
	game.start_lab();game.paused=true
	check(game.lab_active and game.quick_mode and game.battle.autopilot,"isolated AI lab starts")
	check(game.core!=original and game.career_core==original,"career object isolated")
	var initial: Dictionary=game.battle.ships[0].duplicate(true)
	for i in range(90):game.Battle.update(game.battle,1.0/30.0,{})
	check(FileAccess.get_file_as_string(game.save_directory.path_join("voyage.json"))==saved,"lab never changes voyage file")
	game.ui.open_menu()
	var time_before: float=game.battle.time
	game._physics_process(1.0/30.0)
	check(game.battle.time==time_before,"escape menu suspends battle")
	game.ui.close_modal()
	check(game.paused,"closing menu preserves prior paused state")
	game.start_lab();game.paused=true
	check(game.battle.ships[0]==initial,"same-seed replay recreates fixture")
	game.dev_enabled=true;game.dev_tools.shown=true
	game.dev_tools.refill()
	game.battle.result="won";game.result_handled=true;game.settle_battle()
	check(game.ui.modal_kind=="outcome","laboratory after-action flow")
	game.ui.close_modal()
	check(game.mode=="menu" and not game.lab_active and game.core==original,"close results restores career object")
	check(original.state==snapshot and Money.total(original.state)==coins,"career state and every coin preserved")
	game.ui.open_settings();await process_frame;game.ui.close_modal()
	game.queue_free();await process_frame
	print("LABORATORY: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
