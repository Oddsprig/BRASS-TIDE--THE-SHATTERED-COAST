extends SceneTree
const Main=preload("res://scripts/main.gd")
const Lab=preload("res://scripts/fleet_lab.gd")
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;push_error("AUDIO TEST: "+message)
func _initialize():call_deferred("run")
func run():
	var game=Main.new();root.add_child(game);await process_frame
	game.save_directory=ProjectSettings.globalize_path("res://../qa/audio-saves")
	check(game.audio.headless,"audio quality test remains silent/headless")
	for family in ["gun","cannon","rocket","splash","wood","metal"]:
		check(game.audio.bank[family].size()==3,"three recording cuts: "+family)
		for stream in game.audio.bank[family]:check(stream is AudioStreamWAV and stream.get_length()>0.03,"decodable PCM: "+family)
	check(game.audio.voices.size()==32,"fixed voice pool")
	game.lab_config=Lab.preset(game.data,"all_weapons");game.start_lab();game.paused=true
	for frame in range(600):
		if game.battle.result!=null:break
		game.Battle.update(game.battle,1.0/30.0,{})
		game.audio._process(1.0/30.0)
		var events: Array=game.Battle.pop_events(game.battle)
		game.audio.consume(events,game.chart)
		var received: int=game.audio.received
		game.audio.consume(events,game.chart)
		check(game.audio.received==received,"same events are never played twice")
		check(game.audio.peak_voices<=32,"bounded spatial voices")
	check(game.audio.teams.has("player") and game.audio.teams.has("enemy"),"both fleets feed the sound system")
	for family in ["gun","cannon","rocket","torpedo"]:check(game.audio.families.has(family),"actual AI audio events: "+family)
	check(game.audio.scheduled>10,"recording playback scheduled")
	game.audio.reset_battle();check(game.audio.received==0 and game.audio.last_seq==0,"event sequence resets per engagement")
	game.ui.open_settings();await process_frame;game.ui.close_modal()
	game.return_to_title();game.queue_free();await process_frame
	print("AUDIO: ",checks," checks, ",failures," failures; decoding/scheduling only, no audition")
	quit(0 if failures==0 else 1)
