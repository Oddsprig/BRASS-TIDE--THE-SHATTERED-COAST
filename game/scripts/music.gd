extends Node
## Optional user music, loaded at runtime. No online requests or imported assets needed.
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

func set_context(value: String):
	if context==value:return
	context=value
	var exact=tracks.filter(func(t):return t.role==context)
	if not exact.is_empty():next_track()

func next_track():
	if players.is_empty() or tracks.is_empty():return
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
	active=1-active
	players[active].stream=stream
	players[active].volume_db=-60
	if enabled and not headless:players[active].play()
	current=track.path;last_by_context[context]=current;elapsed=0.0

func _process(dt: float):
	scan_clock+=dt
	if scan_clock>=10.0:
		rescan()
		if current.is_empty():next_track()
	elapsed+=dt
	current_gain=move_toward(current_gain,volume if enabled else 0.0,dt*0.6)
	for i in range(players.size()):
		var gain=current_gain*clampf(elapsed/2.0,0,1) if i==active else current_gain*(1.0-clampf(elapsed/2.0,0,1))
		players[i].volume_db=linear_to_db(maxf(0.0001,gain))*1.0-7.0
		if i!=active and elapsed>=2.0:players[i].stop()
	if enabled and not headless and not current.is_empty() and not players[active].playing:players[active].play()

func title() -> String:
	return current.get_file().get_basename() if not current.is_empty() else "Drop MP3, OGG or WAV tracks into music/"
