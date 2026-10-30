extends Node2D
## Recorded combat mix for the existing CC0 banks and the original engine loop.
## World distance sets loudness. Zoom only changes pan. Mute and headless stay silent.
const VOICE_LIMIT=32
const EVENT_VOICE_LIMIT=12
const AUDIBLE_RADIUS=2200.0
const RAPID_INTERVAL=0.16
const RAPID_SOURCE_LIMIT=128
const MISS_HOLD=0.40
const CLOSE_RADIUS=900.0
const STACK_TRIM_DB=0.45
const STACK_TRIM_CAP=5.0
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
	# Arm a limiter only on a bus this node creates. Never replace a host effect.
	_arm_limiter("BrassWeapons",-1.5,-6.0)
	_arm_limiter("BrassAmbience",-1.5,-12.0)
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

func _arm_limiter(bus_name: String,ceiling: float,threshold: float) -> void:
	var index=AudioServer.get_bus_index(bus_name)
	if index<0:
		AudioServer.add_bus()
		index=AudioServer.bus_count-1
		AudioServer.set_bus_name(index,bus_name)
	if AudioServer.get_bus_effect_count(index)>0:return
	var limiter=AudioEffectLimiter.new()
	limiter.ceiling_db=ceiling
	limiter.threshold_db=threshold
	limiter.soft_clip_db=3.0
	limiter.soft_clip_ratio=6.0
	AudioServer.add_bus_effect(index,limiter)

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
	# Equal distance: sink, heavy breach, heavy hit, engine trouble, heavy report,
	# MG breach, MG hit, MG burst, heavy miss, MG miss. Close damage gains a little.
	# Routine bursts and misses fall off faster than damage.
	var kind=str(event.kind)
	var family=str(event.family)
	var distance=Vector2(event.x,event.y).distance_to(camera)
	if not is_finite(distance):return -100000.0
	var heavy=family in ["torpedo","cannon","rocket"]
	var close=clampf(1.0-distance/CLOSE_RADIUS,0.0,1.0)
	var value=80.0 if heavy else 54.0
	var fall=distance/75.0
	match kind:
		"fire":
			if not heavy:
				value=50.0
				fall=distance/50.0
		"hit":
			value+=12.0
			if event.get("breach",false) or event.get("engineDamaged",false) or event.get("sunk",false):
				value=minf(96.0,value+8.0)
			value+=4.0*close
			fall=distance/90.0
		"miss":
			value-=36.0
			fall=distance/48.0
		"engine":
			value=88.0+4.0*close
			fall=distance/120.0
		"sink":
			value=104.0+2.0*close
			fall=distance/120.0
	return value-fall

static func event_layers(event: Dictionary) -> Array:
	# Pure routing. A contact, breach, engine failure or sinking must already be
	# reported. Pitch and gain only; the six recorded banks are not extended.
	var family=str(event.get("family",""))
	var kind=str(event.get("kind",""))
	var material=str(event.get("material",""))
	var contact="metal" if material in ["armor","metal","engine"] else "wood"
	var primary={"sound":"","gain":-24.0,"pitch":1.0}
	var accent={}
	match kind:
		"fire":
			match family:
				"gun":primary={"sound":"gun","gain":-22.0,"pitch":1.0}
				"cannon":primary={"sound":"cannon","gain":-15.0,"pitch":0.88}
				"rocket":primary={"sound":"rocket","gain":-18.0,"pitch":1.06}
				"torpedo":primary={"sound":"splash","gain":-21.0,"pitch":0.90}
		"miss":
			var thin=family=="gun"
			var miss_pitch=0.92
			if family=="torpedo":miss_pitch=0.82
			elif family=="rocket":miss_pitch=0.98
			elif thin:
				miss_pitch=1.08 if material=="water" else 1.02
			primary={"sound":"splash" if material=="water" else "wood","gain":-28.0 if thin else -26.0,"pitch":miss_pitch}
		"hit":
			match family:
				"gun":primary={"sound":contact,"gain":-23.0,"pitch":1.06}
				"cannon":
					primary={"sound":contact,"gain":-18.0,"pitch":0.84}
					accent={"sound":"cannon","gain":-19.0 if event.get("breach",false) else -22.5,"pitch":0.78}
				"rocket":
					primary={"sound":"cannon","gain":-15.5,"pitch":1.16}
					accent={"sound":contact,"gain":-23.0,"pitch":1.0}
				"torpedo":
					primary={"sound":"splash","gain":-15.5,"pitch":0.80}
					accent={"sound":"cannon","gain":-23.5,"pitch":0.68}
		"engine":
			primary={"sound":"metal","gain":-18.0,"pitch":0.84 if str(event.get("reason",""))=="fire" else 0.76}
		"sink":
			var cause=str(event.get("reason",""))
			var burning=bool(event.get("incendiary",false)) or cause=="fire"
			var flooded=cause=="flooding"
			var splash_pitch=0.70
			var hull_gain=-20.5
			var hull_pitch=0.74
			if burning:
				splash_pitch=0.76
				hull_gain=-19.0
				hull_pitch=0.90
			elif flooded:
				splash_pitch=0.66
				hull_gain=-22.0
				hull_pitch=0.72
			primary={"sound":"splash","gain":-14.0,"pitch":splash_pitch}
			accent={"sound":"wood","gain":hull_gain,"pitch":hull_pitch}
	if str(primary.sound).is_empty():return []
	var layers: Array=[primary]
	if not accent.is_empty():layers.append(accent)
	var weight: float=0.88 if str(event.get("variant","light"))=="heavy" else 1.0
	var variation: float=0.97+float(int(event.get("seq",0))%7)*0.01
	for layer in layers:layer.pitch=clampf(float(layer.pitch)*weight*variation,0.65,1.25)
	return layers

static func attenuation_db(distance: float) -> float:
	if not is_finite(distance):return -36.0
	var d: float=clampf(distance,0.0,AUDIBLE_RADIUS)
	# Continuous world-unit falloff. Display zoom cannot change this gain.
	# Close fighting stays intelligible; the existing 2200-unit edge still fades out.
	var body: float=-14.0*log(1.0+d/360.0)/log(10.0)
	var edge: float=-22.0*smoothstep(1500.0,AUDIBLE_RADIUS,d)
	return body+edge

func _rapid_key(event: Dictionary) -> String:
	# Each gun cut is already a burst. One routine gun cue per source per interval.
	# Cannon, rocket and torpedo reports and hits always play. Their misses do not
	# stack. A reported breach, engine hit or killing blow is never coalesced.
	var kind=str(event.kind)
	var family=str(event.family)
	var routine_gun=family=="gun" and kind in ["fire","hit","miss"]
	var heavy_miss=kind=="miss" and family in ["cannon","rocket","torpedo"]
	if not routine_gun and not heavy_miss:return ""
	if kind=="hit" and (event.get("breach",false) or event.get("engineDamaged",false) or event.get("sunk",false)):return ""
	var source=str(event.get("sourceUid",event.get("sourceId","")))
	if source.is_empty():return ""
	return "%s/%s/%s/%s"%[event.get("sourceTeam",event.team),source,family,kind]

func _rapid_hold(event: Dictionary) -> float:
	if str(event.kind)=="miss" and str(event.family)!="gun":return MISS_HOLD
	return RAPID_INTERVAL

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
			if not rapid_key.is_empty():rapid_until[rapid_key]=clock+_rapid_hold(event)
			if layers.size()>1:
				var accent: Dictionary=layers[1]
				accents.append({"sound":accent.sound,"position":projected,"gain":float(accent.gain)+loss,"pitch":accent.pitch,"rank":rank-1.0})
	# Primary reports and impacts come before secondary layers. Layers share the
	# same admission budget, rather than doubling it during a crowded sinking salvo.
	for accent in accents:
		if count>=EVENT_VOICE_LIMIT:break
		if _schedule(accent.sound,accent.position,accent.gain,accent.pitch,accent.rank):count+=1

func _pick_variant(kind: String,variants: Array) -> int:
	# Rotate, and skip a cut that is still playing when another cut is free.
	var last=int(last_variant.get(kind,-1))
	var best=(last+1)%variants.size()
	var best_uses=999999
	for step in range(variants.size()):
		var index=(last+1+step)%variants.size()
		var uses=0
		for slot in voices:
			if float(slot.until)>clock and slot.player.stream==variants[index]:uses+=1
		if uses<best_uses:
			best_uses=uses
			best=index
			if uses==0:break
	return best

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
	var index=_pick_variant(kind,variants)
	last_variant[kind]=index
	var stream: AudioStream=variants[index]
	var duration: float=stream.get_length()/pitch
	if not is_finite(duration) or duration<=0.0:return false
	var others=0
	for i in range(voices.size()):
		if i==chosen:continue
		if float(voices[i].until)>clock:others+=1
	# The first admitted voices are the meaningful ones. Later overlaps yield a few dB.
	var trim=minf(STACK_TRIM_CAP,float(others)*STACK_TRIM_DB)
	slot.player.stream=stream
	slot.player.position=position
	slot.player.volume_db=db-trim
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
