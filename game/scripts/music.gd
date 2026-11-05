extends Node
## Optional user music, loaded at runtime. No online requests or imported assets needed.
const CROSSFADE_SECONDS=2.0
const RETIRE_SECONDS=0.04
var folder=""
var tracks: Array=[]
var players: Array=[]
var active=0
var current=""
var context="title"
var enabled=true
var volume=0.55
var elapsed=0.0
var current_gain=0.0
var last_by_context: Dictionary={}
var scan_clock=0.0
var headless=false
var include_desktop=true
var pending_next=false
var release_gain=1.0
var releasing=false
var retiring=-1
var retire_elapsed=0.0
var retire_gain=0.0
var held_gain=0.0
var queued_track: Dictionary={}
var queued_stream: AudioStream

func _ready():
	headless=DisplayServer.get_name()=="headless"
	folder=ProjectSettings.globalize_path("res://../music") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("music")
	for n in range(2):
		var player=AudioStreamPlayer.new()
		player.volume_db=-60
		add_child(player);players.append(player)
		player.finished.connect(func():if n==active:next_track())
	rescan()
	next_track()

func _scan(path: String,role: String="all",depth: int=0):
	var dir=DirAccess.open(path)
	if dir==null or depth>2:return
	dir.list_dir_begin()
	var name=dir.get_next()
	while not name.is_empty() and tracks.size()<256:
		if not name.begins_with("."):
			var file=path.path_join(name)
			if dir.current_is_dir():
				if name.to_lower() in ["title","travel","harbor","combat","contact","finale","victory","loss","all"]:_scan(file,name.to_lower(),depth+1)
			elif name.get_extension().to_lower() in ["mp3","ogg","wav"]:
				var inferred=role
				var lower=name.to_lower()
				if role=="all":
					for pair in [["brass and salt","title"],["first light","travel"],["shipwright","harbor"],["haze","contact"],["iron across","combat"],["shatter line","finale"],["survivors","victory"],["empty berth","loss"]]:
						if pair[0] in lower:inferred=pair[1];break
				var f=FileAccess.open(file,FileAccess.READ)
				if f!=null and f.get_length()>0 and f.get_length()<=67108864:
					tracks.append({"path":file,"title":name.get_basename(),"role":inferred})
		name=dir.get_next()
	dir.list_dir_end()

func rescan():
	tracks=[]
	_scan(folder)
	if include_desktop:
		var desktop=OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP).path_join("Brass Tide Music")
		if desktop!=folder:_scan(desktop)
	# Identical titles in the portable copy and desktop staging are one playlist entry.
	var unique: Dictionary={}
	for track in tracks:
		var key=str(track.title).to_lower()+":"+str(track.role)
		if not unique.has(key):unique[key]=track
	tracks=unique.values()
	tracks.sort_custom(func(a,b):return a.path<b.path)
	scan_clock=0.0

func load_track(path: String) -> AudioStream:
	match path.get_extension().to_lower():
		"mp3":return AudioStreamMP3.load_from_file(path)
		"ogg":return AudioStreamOggVorbis.load_from_file(path)
		"wav":return AudioStreamWAV.load_from_file(path)
	return null

func _role(path: String) -> String:
	for track in tracks:
		if track.path==path:return str(track.role)
	return ""

func _audible(index: int) -> float:
	if index<0 or index>=players.size() or not players[index].playing:return 0.0
	if retiring>=0:
		return retire_gain*(1.0-clampf(retire_elapsed/RETIRE_SECONDS,0.0,1.0)) if index==retiring else held_gain
	var fade=clampf(elapsed/CROSSFADE_SECONDS,0.0,1.0)
	if index==active:return fade
	return (release_gain if releasing else 1.0)*(1.0-fade)

func _ending() -> bool:
	if players.is_empty() or active<0 or active>=players.size():return false
	var player: AudioStreamPlayer=players[active]
	if not player.playing or player.stream==null:return false
	var length=player.stream.get_length()
	return length>CROSSFADE_SECONDS and length-player.get_playback_position()<=CROSSFADE_SECONDS

func _mount(index: int,stream: AudioStream) -> void:
	var player: AudioStreamPlayer=players[index]
	player.volume_db=-87
	player.stream=stream
	if enabled and not headless:player.play()

func _reuse(stream: AudioStream,index: int,held: float) -> void:
	release_gain=held
	active=index
	_mount(active,stream)
	releasing=true
	elapsed=0.0

func _handoff(stream: AudioStream,keep_current: bool=false) -> bool:
	# Keep both live streams mounted until the quieter voice reaches the floor.
	# Hold the other voice at its present factor, including an ending cue.
	var incoming=_audible(active)
	var outgoing=_audible(1-active)
	var reuse=active if incoming<outgoing and not keep_current else 1-active
	var held=outgoing if reuse==active else incoming
	var quiet=incoming if reuse==active else outgoing
	if quiet>0.0001:
		retiring=reuse;retire_elapsed=0.0;retire_gain=quiet;held_gain=held
		return false
	_reuse(stream,reuse,held)
	return true

func set_context(value: String):
	if context==value:return
	context=value
	var exact=tracks.filter(func(t):return t.role==context)
	if not exact.is_empty():next_track()

func next_track():
	if players.is_empty() or tracks.is_empty():return
	# Same-role Next waits out this fade, so repeated presses become one cue.
	# New roles can first need a brief live-voice retirement, never a queued fade.
	var ending=_ending()
	if retiring<0 and not current.is_empty() and elapsed<CROSSFADE_SECONDS and _role(current)==context and not ending:
		pending_next=true
		return
	var pool=tracks.filter(func(t):return t.role==context)
	if pool.is_empty():pool=tracks.filter(func(t):return t.role not in ["victory","loss"])
	if pool.is_empty():return
	var previous: String=str(last_by_context.get(context,current))
	var next_index: int=0
	for i in range(pool.size()):
		if pool[i].path==previous:next_index=(i+1)%pool.size();break
	# Cycle the entire role pool, including every new variation, without adjacent repeats.
	var track: Dictionary=pool[next_index]
	var stream: AudioStream=load_track(track.path)
	if stream==null or stream.get_length()<=0:return
	if retiring>=0:
		# Latest context/Next replaces only the pending cue, not the release clock.
		queued_track=track;queued_stream=stream;pending_next=false
		return
	if not current.is_empty() and elapsed<CROSSFADE_SECONDS:
		if not _handoff(stream,ending):
			queued_track=track;queued_stream=stream;pending_next=false
			return
	else:
		releasing=false
		active=1-active
		_mount(active,stream)
		elapsed=0.0
	current=track.path;last_by_context[context]=current;pending_next=false

func _process(dt: float):
	scan_clock+=dt
	if scan_clock>=10.0:
		rescan()
		if current.is_empty():next_track()
	current_gain=move_toward(current_gain,volume if enabled else 0.0,dt*0.6)
	if retiring>=0:
		retire_elapsed+=dt
		for i in range(players.size()):
			players[i].volume_db=linear_to_db(maxf(0.0001,current_gain*_audible(i)))-7.0
		if retire_elapsed>=RETIRE_SECONDS:
			var reuse=retiring
			retiring=-1
			_reuse(queued_stream,reuse,held_gain)
			current=queued_track.path;last_by_context[context]=current;pending_next=false
			queued_track={};queued_stream=null
		return
	elapsed+=dt
	var fade=clampf(elapsed/CROSSFADE_SECONDS,0.0,1.0)
	var outgoing=(release_gain if releasing else 1.0)*(1.0-fade)
	for i in range(players.size()):
		var factor=fade if i==active else outgoing
		var gain=current_gain*factor
		players[i].volume_db=linear_to_db(maxf(0.0001,gain))*1.0-7.0
		if i!=active and elapsed>=CROSSFADE_SECONDS:players[i].stop()
	if elapsed>=CROSSFADE_SECONDS:releasing=false
	if pending_next and elapsed>=CROSSFADE_SECONDS:
		pending_next=false
		next_track()
	elif enabled and not headless and not current.is_empty():
		var player: AudioStreamPlayer=players[active]
		# Roll before the end, while the outgoing recording can still fade out.
		if player.playing and player.stream!=null and player.stream.get_length()>CROSSFADE_SECONDS and player.stream.get_length()-player.get_playback_position()<=CROSSFADE_SECONDS:
			next_track()
		elif not player.playing:player.play()

func title() -> String:
	return current.get_file().get_basename() if not current.is_empty() else "Drop MP3, OGG or WAV tracks into music/"
