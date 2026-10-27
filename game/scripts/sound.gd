extends Node2D
## Recorded combat banks and an original procedural engine loop; bounded camera-aware voices.
const VOICE_LIMIT=32
const EVENT_VOICE_LIMIT=12
const AUDIBLE_RADIUS=2200.0
const RAPID_INTERVAL=0.16
const RAPID_SOURCE_LIMIT=128
var enabled=true
var weapon_volume=0.85
var ambience_volume=0.35
var voices: Array=[]
var bank: Dictionary={}
var last_variant: Dictionary={}
var rapid_until: Dictionary={}
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
	teams.clear();families.clear();rapid_until.clear()
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
	if event.kind=="hit":value+=12.0
	if event.kind=="hit" and (event.get("breach",false) or event.get("engineDamaged",false)):
		value=minf(98.0,value+8.0)
	if event.kind=="engine":value=90.0
	if event.kind=="miss":value-=24.0
	return value-Vector2(event.x,event.y).distance_to(camera)/80.0

static func event_layers(event: Dictionary) -> Array:
	# Pure routing used by consume and silent fixtures. Never synthesize an attack
	# or infer damage: a contact, breach, engine failure or sinking must be reported.
	var family: String=str(event.get("family",""))
	var contact: String="metal" if str(event.get("material","")) in ["armor","metal","engine"] else "wood"
	var primary: Dictionary={"sound":"","gain":-23.0,"pitch":1.0}
	var accent: Dictionary={}
	match str(event.get("kind","")):
		"fire":
			match family:
				"gun":primary={"sound":"gun","gain":-18.0,"pitch":1.04}
				"cannon":primary={"sound":"cannon","gain":-12.0,"pitch":0.94}
				"rocket":primary={"sound":"rocket","gain":-18.0,"pitch":1.02}
				"torpedo":primary={"sound":"splash","gain":-22.0,"pitch":0.84}
		"miss":
			primary={"sound":"splash" if event.get("material","")=="water" else "wood","gain":-25.0 if family=="gun" else -22.0,"pitch":0.82 if family=="torpedo" else 1.0}
		"hit":
			match family:
				"gun":primary={"sound":contact,"gain":-23.0,"pitch":1.08}
				"cannon":
					primary={"sound":contact,"gain":-20.0,"pitch":0.88}
					if event.get("breach",false):accent={"sound":"cannon","gain":-25.0,"pitch":0.82}
				"rocket":
					primary={"sound":"cannon","gain":-14.0,"pitch":1.10}
					accent={"sound":contact,"gain":-24.0,"pitch":1.02}
				"torpedo":
					# Water is the admitted attack; the subdued recording under it is
					# a low impact layer, distinct from a rocket's sharp dry report.
					primary={"sound":"splash","gain":-16.0,"pitch":0.76}
					accent={"sound":"cannon","gain":-23.0,"pitch":0.70}
		"engine":primary={"sound":"metal","gain":-22.0,"pitch":0.80}
		"sink":
			primary={"sound":"splash","gain":-19.0,"pitch":0.78}
			accent={"sound":"wood","gain":-25.0,"pitch":0.76}
	if str(primary.sound).is_empty():return []
	var layers: Array=[primary]
	if not accent.is_empty():layers.append(accent)
	var weight: float=0.88 if event.get("variant","light")=="heavy" else 1.0
	var variation: float=0.97+float(int(event.get("seq",0))%7)*0.01
	for layer in layers:layer.pitch=clampf(float(layer.pitch)*weight*variation,0.65,1.25)
	return layers

static func attenuation_db(distance: float) -> float:
	if not is_finite(distance):return -36.0
	var d: float=clampf(distance,0.0,AUDIBLE_RADIUS)
	# Continuous distance falloff and a soft far edge; zoom cannot alter loudness.
	return -20.0*log(1.0+d/320.0)/log(10.0)-18.0*smoothstep(1600.0,AUDIBLE_RADIUS,d)

func _rapid_key(event: Dictionary) -> String:
	# Each recorded burst already contains several shots. Keep its source audible
	# without stacking every mount's gun burst or routine contact on the same boat.
	# Significant damage and every other weapon family retain normal admission.
	if event.family!="gun" or event.kind not in ["fire","hit","miss"]:return ""
	if event.kind=="hit" and (event.get("breach",false) or event.get("engineDamaged",false) or event.get("sunk",false)):return ""
	var source=str(event.get("sourceUid",event.get("sourceId","")))
	if source.is_empty():return ""
	return "%s/%s/%s/%s"%[event.get("sourceTeam",event.team),source,event.family,event.kind]

func consume(events: Array,chart):
	var admitted: Array=[]
	for event in events:
		if int(event.seq)<=last_seq:continue
		last_seq=int(event.seq);received+=1
		teams[str(event.team)]=int(teams.get(str(event.team),0))+1
		families[str(event.family)]=int(families.get(str(event.family),0))+1
		admitted.append(event)
	if not enabled:return
	for key in rapid_until.keys():
		if float(rapid_until[key])<=clock:rapid_until.erase(key)
	admitted.sort_custom(func(a,b):return priority(a,chart.camera)>priority(b,chart.camera))
	var count=0
	var accents: Array=[]
	for event in admitted:
		if count>=EVENT_VOICE_LIMIT:dropped+=1;continue
		var position=Vector2(event.x,event.y)
		var distance=position.distance_to(chart.camera)
		if not is_finite(distance) or distance>AUDIBLE_RADIUS:dropped+=1;continue
		var rapid_key=_rapid_key(event)
		if not rapid_key.is_empty() and (rapid_until.has(rapid_key) or rapid_until.size()>=RAPID_SOURCE_LIMIT):dropped+=1;continue
		var layers: Array=event_layers(event)
		if layers.is_empty():continue
		var primary: Dictionary=layers[0]
		var loss: float=attenuation_db(distance)
		var projected: Vector2=chart.project(position)
		var rank: float=priority(event,chart.camera)
		if _schedule(str(primary.sound),projected,float(primary.gain)+loss,float(primary.pitch),rank):
			count+=1
			if not rapid_key.is_empty():rapid_until[rapid_key]=clock+RAPID_INTERVAL
			if layers.size()>1:
				var accent: Dictionary=layers[1]
				accents.append({"sound":accent.sound,"position":projected,"gain":float(accent.gain)+loss,"pitch":accent.pitch,"rank":rank-1.0})
	# Primary reports/impacts come before secondary layers. Layers share the same
	# admission budget, rather than doubling it during a crowded sinking salvo.
	for accent in accents:
		if count>=EVENT_VOICE_LIMIT:break
		if _schedule(accent.sound,accent.position,accent.gain,accent.pitch,accent.rank):count+=1

func _schedule(kind: String,position: Vector2,db: float,pitch: float,rank: float) -> bool:
	if not position.is_finite() or not is_finite(db) or not is_finite(pitch) or not is_finite(rank) or pitch<0.65 or pitch>1.25:return false
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
	var duration: float=stream.get_length()/pitch
	if not is_finite(duration) or duration<=0.0:return false
	slot.player.stream=stream
	slot.player.position=position
	slot.player.volume_db=db
	slot.player.pitch_scale=pitch
	slot.priority=rank
	slot.until=clock+duration
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
