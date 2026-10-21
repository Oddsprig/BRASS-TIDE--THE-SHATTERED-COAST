extends Node2D
## Real recording bank; bounded, camera-aware voices for every deployed boat.
const VOICE_LIMIT=32
var enabled=true
var weapon_volume=0.85
var ambience_volume=0.35
var voices: Array=[]
var bank: Dictionary={}
var last_variant: Dictionary={}
var last_seq=0
var clock=0.0
var headless=false
var received=0
var scheduled=0
var dropped=0
var peak_voices=0
var teams: Dictionary={}
var families: Dictionary={}
var engine_player: AudioStreamPlayer

func _ready():
	headless=DisplayServer.get_name()=="headless"
	for bus_name in ["BrassWeapons","BrassAmbience"]:
		if AudioServer.get_bus_index(bus_name)<0:
			AudioServer.add_bus()
			var index=AudioServer.bus_count-1
			AudioServer.set_bus_name(index,bus_name)
			var limiter=AudioEffectLimiter.new()
			AudioServer.add_bus_effect(index,limiter)
	for kind in ["gun","cannon","rocket","splash","wood","metal"]:
		bank[kind]=[]
		for n in range(1,4):
			var path="res://assets/sfx/%s-%d.wav"%[kind,n]
			if ResourceLoader.exists(path):bank[kind].append(load(path))
	for n in range(VOICE_LIMIT):
		var player=AudioStreamPlayer2D.new()
		player.bus="BrassWeapons"
		player.max_distance=100000.0
		player.attenuation=0.0
		player.panning_strength=0.8
		add_child(player)
		voices.append({"player":player,"until":0.0,"priority":0.0})
	engine_player=AudioStreamPlayer.new()
	engine_player.bus="BrassAmbience"
	add_child(engine_player)
	if ResourceLoader.exists("res://assets/sfx/engine.wav"):
		engine_player.stream=load("res://assets/sfx/engine.wav")
		if engine_player.stream is AudioStreamWAV:
			engine_player.stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
			engine_player.stream.loop_end=88200

func reset_battle():
	last_seq=0;received=0;scheduled=0;dropped=0;peak_voices=0
	teams.clear();families.clear()
	for slot in voices:slot.player.stop();slot.until=clock

func _process(dt: float):
	clock+=dt
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("BrassWeapons"),linear_to_db(maxf(0.0001,weapon_volume)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("BrassAmbience"),linear_to_db(maxf(0.0001,ambience_volume)))
	if not enabled:
		for slot in voices:slot.player.stop()
		engine_player.stop()

func priority(event: Dictionary,camera: Vector2) -> float:
	var value=100.0 if event.kind=="sink" else (82.0 if event.family in ["torpedo","cannon","rocket"] else 58.0)
	if event.kind=="miss":value-=24.0
	return value-Vector2(event.x,event.y).distance_to(camera)/80.0

func consume(events: Array,chart):
	var admitted: Array=[]
	for event in events:
		if int(event.seq)<=last_seq:continue
		last_seq=int(event.seq);received+=1
		teams[str(event.team)]=int(teams.get(str(event.team),0))+1
		families[str(event.family)]=int(families.get(str(event.family),0))+1
		admitted.append(event)
	if not enabled:return
	admitted.sort_custom(func(a,b):return priority(a,chart.camera)>priority(b,chart.camera))
	var count=0
	for event in admitted:
		if count>=12:dropped+=1;continue
		var position=Vector2(event.x,event.y)
		var distance=position.distance_to(chart.camera)
		if distance>2200.0:dropped+=1;continue
		var sound=""
		match event.kind:
			"fire":sound="splash" if event.family=="torpedo" else str(event.family)
			"miss":sound="splash" if event.material=="water" else "wood"
			"hit":sound="cannon" if event.family in ["rocket","torpedo"] else ("metal" if event.material=="armor" else "wood")
			"engine":sound="metal"
			"sink":sound="splash"
		if sound.is_empty():continue
		var gain=-12.0 if sound=="cannon" else (-18.0 if sound in ["gun","rocket"] else -23.0)
		gain-=clampf(distance/170.0,0,15)
		var pitch=0.86 if event.get("variant","light")=="heavy" else 1.0
		pitch*=0.97+float(int(event.seq)%7)*0.01
		if _schedule(sound,chart.project(position),gain,pitch,priority(event,chart.camera)):
			count+=1
		if event.kind=="hit" and event.family=="torpedo":_schedule("splash",chart.project(position),gain-3.0,0.83,85.0-distance/80.0)
		if event.kind=="sink":_schedule("wood",chart.project(position),gain-1.0,0.72,95.0-distance/80.0)

func _schedule(kind: String,position: Vector2,db: float,pitch: float,rank: float) -> bool:
	var variants: Array=bank.get(kind,[])
	if variants.is_empty():return false
	var chosen=-1
	var minimum=INF
	for i in range(voices.size()):
		if voices[i].until<=clock:chosen=i;break
		if voices[i].priority<minimum:minimum=voices[i].priority;chosen=i
	if chosen<0:return false
	var slot: Dictionary=voices[chosen]
	if slot.until>clock and slot.priority>rank:dropped+=1;return false
	var index=(int(last_variant.get(kind,-1))+1)%variants.size()
	last_variant[kind]=index
	var stream: AudioStream=variants[index]
	slot.player.stream=stream
	slot.player.position=position
	slot.player.volume_db=db
	slot.player.pitch_scale=pitch
	slot.priority=rank
	slot.until=clock+stream.get_length()/pitch
	if not headless and enabled:slot.player.play()
	scheduled+=1
	var active=0
	for voice in voices:active+=1 if voice.until>clock else 0
	peak_voices=maxi(peak_voices,active)
	return true

func set_engine(running: bool,load_value: float=0.0):
	if engine_player==null or engine_player.stream==null:return
	if not enabled or not running or headless:engine_player.stop();return
	engine_player.volume_db=-28.0+clampf(load_value,0,1)*5.0
	engine_player.pitch_scale=0.82+clampf(load_value,0,1)*0.27
	if not engine_player.playing:engine_player.play()

func play(kind: String):
	# Dock confirmation is a subdued recorded contact, never a synthetic chime.
	if enabled and kind=="bell":_schedule("wood",get_viewport_rect().size*0.5,-27.0,1.0,20.0)
