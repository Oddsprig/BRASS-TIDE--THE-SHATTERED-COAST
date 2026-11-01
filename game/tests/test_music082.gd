extends SceneTree
## Standalone portable replay: only the production music script is preloaded.
const Music=preload("res://scripts/music.gd")
var checks=0
var failures: Array[String]=[]
var rows: Array=[]
var channel_paths=["", ""]
var phase="guards"
var clock=0.0
var started=0

func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message);push_error("Music082: "+message)

func _initialize():call_deferred("run")

func sample(m,label: String):
	channel_paths[m.active]=m.current
	var channels: Array=[]
	for i in range(m.players.size()):
		var p: AudioStreamPlayer=m.players[i]
		channels.append({"channel":i,"path":channel_paths[i],"playing":p.playing,"position_s":p.get_playback_position(),"length_s":p.stream.get_length() if p.stream!=null else 0.0,"gain_linear":db_to_linear(p.volume_db),"gain_db":p.volume_db})
	rows.append({"phase":phase,"time_s":clock,"wall_s":(Time.get_ticks_usec()-started)/1000000.0,"event":label,"context":m.context,"current":m.current,"active":m.active,"elapsed_s":m.elapsed,"pending_next":m.pending_next,"enabled":m.enabled,"headless_guard":m.headless,"channels":channels})

func step(m,dt: float):
	m._process(dt);clock+=dt;sample(m,"step")

func queued_request(m,value: String,next_count: int=0):
	var before=[m.active,m.current,m.elapsed,m.players[0].stream,m.players[1].stream,m.players[0].volume_db,m.players[1].volume_db]
	m.set_context(value)
	for i in range(next_count):m.next_track()
	check(m.pending_next and before==[m.active,m.current,m.elapsed,m.players[0].stream,m.players[1].stream,m.players[0].volume_db,m.players[1].volume_db],"mid-fade request preserves both streams, gains and envelope: "+value)
	sample(m,"request:"+value+":next="+str(next_count))

func run():
	Engine.max_fps=60
	started=Time.get_ticks_usec()
	var out: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	# Refuse before creating any player unless this child uses the silent driver.
	if not out.is_absolute_path() or AudioServer.get_driver_name()!="Dummy":
		push_error("Music082 requires GAME_TEST_ARTIFACTS and --audio-driver Dummy");quit(2);return
	var m=Music.new();m.enabled=false;m.include_desktop=false
	root.add_child(m);m.set_process(false)
	check(m.players.size()==2,"exactly two music players")
	check(m.tracks.size()==18,"all 18 supplied cues scanned without desktop music")
	for role in ["title","travel","harbor","combat"]:
		check(m.tracks.filter(func(t):return t.role==role).size()>=2,"finite supplied variations available: "+role)
	if failures.is_empty():
		m.headless=true;m.enabled=true;step(m,2.0);m.next_track();step(m,0.1)
		check(not m.players[0].playing and not m.players[1].playing,"headless guard prevents playback")
		m.headless=false;m.enabled=false;step(m,2.0);m.next_track();step(m,2.0)
		check(not m.players[0].playing and not m.players[1].playing,"disabled music never starts a player")
		# Eight real seconds, including rapid latest-context requests and queued Next.
		# Only this fixture overrides the headless flag; the driver remains Dummy.
		phase="realtime";clock=0.0;m.enabled=true;m.next_track();sample(m,"title_start")
		check(m.players[m.active].playing and is_equal_approx(m.players[m.active].volume_db,-87.0),"real title player begins at the envelope floor")
		var selected: Array=[m.current]
		var offsets=[0.25,0.40,0.55,2.50,4.50]
		var contexts=["travel","combat","travel","combat","combat"]
		var event_index=0
		var previous=Time.get_ticks_usec()
		while clock<8.20:
			await process_frame
			var now=Time.get_ticks_usec()
			step(m,(now-previous)/1000000.0);previous=now
			if m.current!=selected[-1]:selected.append(m.current)
			while event_index<offsets.size() and clock>=offsets[event_index]:
				queued_request(m,contexts[event_index],2 if event_index==4 else 0)
				event_index+=1
		var roles: Array=[]
		for path in selected:
			var found: Array=m.tracks.filter(func(t):return t.path==path)
			roles.append(found[0].role if not found.is_empty() else "missing")
		check(roles==["title","travel","combat","combat"] and selected[2]!=selected[3],"latest context wins and repeated Next coalesces into one distinct cue")
		check(not m.pending_next and not m.players[1-m.active].playing,"completed fade retires only the outgoing player")
		var overlap=false
		var bounded=true
		for row in rows:
			if row.phase!="realtime":continue
			var a: Dictionary=row.channels[0]
			var b: Dictionary=row.channels[1]
			overlap=overlap or (a.playing and b.playing and minf(a.gain_linear,b.gain_linear)>0.02)
			bounded=bounded and a.gain_linear+b.gain_linear<=m.volume*db_to_linear(-7.0)+0.0001
		check(overlap and bounded,"two live streams overlap within the configured linear gain budget")
		# Seek the actual incoming MP3, then allow real audio mixes to advance it.
		phase="pre_end";clock=0.0
		var old_active: int=m.active
		var outgoing: AudioStreamPlayer=m.players[old_active]
		var length: float=outgoing.stream.get_length()
		check(length>4.0 and outgoing.playing,"finite real cue is playing before the pre-end seek")
		var seek_to: float=length-1.5
		outgoing.seek(seek_to);sample(m,"seek_requested")
		var seek_start=Time.get_ticks_usec()
		while clock<0.12:
			await process_frame
			clock=(Time.get_ticks_usec()-seek_start)/1000000.0;sample(m,"seek_mix")
		var position: float=outgoing.get_playback_position()
		check(position>seek_to+0.01 and position<length and outgoing.playing,"real playback advances inside the final two seconds before finishing")
		sample(m,"before_pre_end");step(m,1.0/60.0)
		check(m.active!=old_active and m.players[m.active].playing and outgoing.playing and outgoing.get_playback_position()<length,"pre-end rollover starts a second real player while the outgoing cue is still live")
		m.enabled=false;step(m,2.0)
		check(m.players[0].volume_db<-80.0 and m.players[1].volume_db<-80.0,"mute drains both live channel gains to the silent floor")
		# Accelerated envelope checks are labelled separately from real playback.
		phase="harbor_cycle";clock=0.0;m.headless=true;m.enabled=true
		for p in m.players:p.stop()
		m.set_context("harbor");step(m,2.0)
		var pool: Array=m.tracks.filter(func(t):return t.role=="harbor")
		var variations: Dictionary={}
		for i in range(pool.size()):
			step(m,2.0);variations[m.current]=true;m.next_track();sample(m,"harbor_next")
		check(variations.size()==pool.size(),"every supplied harbor variation is selected before repeating")
		check(not m.players[0].playing and not m.players[1].playing,"headless cycling still never starts audio")
	var report=FileAccess.open(out.path_join("music082.json"),FileAccess.WRITE)
	check(report!=null,"JSON witness is writable")
	if report!=null:
		report.store_string(JSON.stringify({"schema":"music082/1","checks":checks,"failures":failures,"driver":AudioServer.get_driver_name(),"display":DisplayServer.get_name(),"tracks":m.tracks,"samples":rows,"elapsed_wall_s":(Time.get_ticks_usec()-started)/1000000.0,"listening":"UNREVIEWED; observed player state and envelope, no recorded audio"},"\t"));report.close()
	m.free()
	print("Music082: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
