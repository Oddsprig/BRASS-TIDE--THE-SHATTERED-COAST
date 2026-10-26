extends SceneTree
## Short actual-battle recording/scheduling checks, silent under Root's Dummy lane.
## Mix stress re-sequences authentic records; it does not claim additional shots.
const Sound=preload("res://scripts/sound.gd")
const Battle=preload("res://scripts/battle.gd")
const Lab=preload("res://scripts/fleet_lab.gd")
const Damage=preload("res://scripts/damage.gd")
const Events=preload("res://scripts/combat_events.gd")
const DT: float=1.0/30.0
const WEAPONS: Array=["rapid_gun","light_cannon","fire_rocket","light_torpedo"]
class MixChart extends RefCounted:
	var camera: Vector2=Vector2(1100,850)
	func project(p: Vector2) -> Vector2:return p-camera
var checks: int=0
var failures: int=0
var sequence: Dictionary={"time":0.0}
var audio
var chart=MixChart.new()

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL combat_feedback040: "+message)

func _initialize() -> void:call_deferred("run")

func batch(record: Dictionary,count: int,unique_sources: bool=false) -> Array:
	Events.begin_step(sequence)
	var result: Array=[]
	for index in range(count):
		var raw: Dictionary=record.duplicate(true)
		if unique_sources:
			raw.sourceId="mix-source-%d-%d"%[int(sequence.get("eventSeq",0)),index]
			raw.sourceUid=raw.sourceId
		result.append(Events.push_event(sequence,raw))
	return result

func voice_family(slot: Dictionary) -> String:
	for family in audio.bank:
		if slot.player.stream in audio.bank[family]:return str(family)
	return ""

func active_family(family: String) -> bool:
	for slot in audio.voices:
		if float(slot.until)>audio.clock and voice_family(slot)==family:return true
	return false

func native_records() -> Dictionary:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var config: Dictionary={"player":[],"enemy":[]}
	for team in ["player","enemy"]:
		for index in range(WEAPONS.size()):
			var entry: Dictionary=Lab.entry(world,"cinder_monitor" if team=="enemy" and index==0 else "tin_skiff")
			entry.loadout.weapons[0]=WEAPONS[index]
			config[team].append(entry)
	var created: Dictionary=Lab.create(world,config,4001)
	check(created.ok,"eight canonical fitted boats use the existing laboratory birth/deployment path")
	if not created.ok:return {}
	var st: Dictionary=created.battle
	for index in range(st.ships.size()):
		var ship: Dictionary=st.ships[index]
		ship.x=1000.0 if ship.team=="player" else 1200.0
		ship.y=560.0+180.0*(index%4)
		ship.retreatHome={"x":ship.x,"y":ship.y}
	var records: Array=[]
	var projectiles: Dictionary={}
	var ammo_before: float=0.0
	for ship in st.ships:ammo_before+=float(ship.ammo)
	# Exercise public manual firing for each fitted family. Discretionary AI
	# launch passes are not a prerequisite for this bounded sound-path fixture.
	for tick in range(24):
		var input: Dictionary={}
		if tick<WEAPONS.size():
			var shooter: Dictionary=st.ships[tick]
			var target: Dictionary=st.ships[tick+WEAPONS.size()]
			check(Battle.select_flagship(st,shooter.id),"public manual firing authority: "+WEAPONS[tick])
			Battle.set_autopilot(st,false)
			input={"fire":true,"aimX":target.x,"aimY":target.y}
		elif tick==WEAPONS.size():Battle.set_autopilot(st,true)
		Battle.update(st,DT,input)
		for projectile in st.projectiles:
			if not projectiles.has(str(projectile.family)):projectiles[str(projectile.family)]=projectile.duplicate(true)
		records.append_array(Battle.pop_events(st))
	var samples: Dictionary={}
	for event in records:
		if event.kind=="fire" and not samples.has(str(event.family)):samples[str(event.family)]=event
	var ammo_after: float=0.0
	for ship in st.ships:ammo_after+=float(ship.ammo)
	check(ammo_after<ammo_before,"actual battle reports debit finite ammunition")
	check(Battle.pop_events(st).is_empty(),"public event drain consumes actual battle records once")
	for family in Events.FAMILIES:
		check(samples.has(family) and projectiles.has(family),"actual public Battle firing/projectile: "+str(family))
	if samples.size()!=4 or projectiles.size()!=4:return {}
	# Exercise the same public hit/miss producers as Battle with its real shots,
	# real canonical target copies and actual Damage.apply_hit outcomes. These
	# detached contacts make material/priority checks independent of aim RNG.
	var producer: Dictionary={"time":float(st.time),"effects":[]}
	for family in Events.FAMILIES:
		var target: Dictionary=st.ships[4 if family=="gun" else 1].duplicate(true)
		var shot: Dictionary=projectiles[family]
		var hp_before: float=float(target.hp)
		var damage_events: Array=Damage.apply_hit(target,{"damage":shot.damage,"kind":shot.kind,"penetration":shot.penetration,"section":"bow"},st.rng)
		samples[str(family)+"_hit"]=Events.emit_hit(producer,shot,target,Vector2(target.x,target.y),"bow",damage_events,maxf(0.0,hp_before-float(target.hp)))
	var wood: Dictionary=st.ships[1].duplicate(true)
	var old_hp: float=float(wood.hp)
	var wood_damage: Array=Damage.apply_hit(wood,{"damage":projectiles.gun.damage,"kind":"bullet","section":"bow"},st.rng)
	samples.wood=Events.emit_hit(producer,projectiles.gun,wood,Vector2(wood.x,wood.y),"bow",wood_damage,maxf(0.0,old_hp-float(wood.hp)))
	samples.water=Events.emit_miss(producer,projectiles.gun,chart.camera,false)
	# Sinking is emitted by the real battle lifecycle after actual terminal damage.
	Damage.apply_hit(st.ships[4],{"damage":100000.0,"kind":"shell","section":"bow"},st.rng)
	Battle.update(st,DT)
	for event in Battle.pop_events(st):
		if event.kind=="sink":samples.sink=event
	check(samples.has("sink"),"actual terminal damage produces a Battle sinking record")
	var before: Array=records.duplicate(true)
	var ships_before: Array=st.ships.duplicate(true)
	audio.consume(records,chart)
	check(audio.received==records.size() and audio.scheduled>0,"Sound.consume receives and schedules authentic Battle records")
	check(records==before and st.ships==ships_before,"sound leaves combat records and numerical ships unchanged")
	check(audio.teams.has("player") and audio.teams.has("enemy"),"both real fleets reach the sound path")
	return samples

func mix_checks(samples: Dictionary) -> void:
	audio.reset_battle()
	var burst: Array=batch(samples.gun,8)
	audio.consume(burst,chart)
	check(audio.received==8 and audio.scheduled==1 and audio.dropped==7,"one recorded gun burst per source replaces stacked rapid-fire clips")
	var scheduled: int=audio.scheduled
	var dropped: int=audio.dropped
	audio.consume(burst,chart)
	check(audio.received==8 and audio.scheduled==scheduled and audio.dropped==dropped,"duplicate sequences never replay, even dropped clips")
	audio.consume(batch(samples.water,8),chart)
	check(audio.scheduled==scheduled+1 and active_family("splash"),"same-source water contacts have their own bounded cue")
	var other: Dictionary=samples.gun.duplicate(true)
	other.sourceId="another-real-source";other.sourceUid=other.sourceId
	audio.consume(batch(other,1),chart)
	check(audio.scheduled==scheduled+2,"a second boat keeps its own rapid-fire admission")
	var variant: int=int(audio.last_variant.gun)
	audio._process(0.17)
	audio.consume(batch(samples.gun,1),chart)
	check(audio.scheduled==scheduled+3 and int(audio.last_variant.gun)!=variant,"source resumes after elapsed playback time and rotates recording cuts")
	for family in ["cannon","rocket","torpedo"]:
		scheduled=audio.scheduled
		audio.consume(batch(samples[family],3),chart)
		check(audio.scheduled==scheduled+3,"repeated "+family+" reports remain exempt from gun coalescing")
	# Each isolated actual producer record must route to its recorded bank(s).
	for pair in [["gun_hit","metal"],["wood","wood"],["cannon_hit","wood"],["rocket_hit","cannon"],["torpedo_hit","cannon"],["sink","splash"]]:
		audio.reset_battle()
		audio.consume(batch(samples[pair[0]],1),chart)
		check(active_family(pair[1]),str(pair[0])+" selects existing "+str(pair[1])+" recordings")
		if pair[0]=="torpedo_hit":check(active_family("splash"),"torpedo impact retains its water layer")
		if pair[0]=="sink":check(active_family("wood"),"sinking retains its hull layer")
	# Fill the real pool through consume, then admit important records under load.
	audio.reset_battle()
	for burst_index in range(3):audio.consume(batch(samples.gun,12,true),chart)
	check(audio.peak_voices==32 and audio.voices.size()==32,"crowding reaches but cannot grow the 32-voice pool")
	var crowded: Array=batch(samples.gun,16,true)
	for key in ["cannon_hit","rocket_hit","torpedo_hit","sink"]:crowded.append_array(batch(samples[key],1))
	scheduled=audio.scheduled
	audio.consume(crowded,chart)
	var significant: int=0
	var threshold: float=audio.priority(samples.gun,chart.camera)
	for slot in audio.voices:
		if float(slot.until)>audio.clock and float(slot.priority)>threshold:significant+=1
	check(significant>=4 and audio.scheduled-scheduled<=12,"major impacts and sinking displace routine fire within the event voice budget")
	audio.reset_battle();scheduled=audio.scheduled
	audio.consume(batch(samples.sink,16,true),chart)
	check(audio.scheduled-scheduled==12 and audio.peak_voices<=32,"layered sinking cannot double the 12-voice admission cap")
	check(audio.rapid_until.size()<=128,"recent rapid-fire source bookkeeping stays bounded")
	# Same report near/far: real consume gain and spatial projection, then culling.
	audio.reset_battle();chart.camera=Vector2(samples.cannon.x,samples.cannon.y)
	audio.consume(batch(samples.cannon,1),chart)
	var near_db: float=float(audio.voices[0].player.volume_db)
	audio.reset_battle();chart.camera+=Vector2(1000,0)
	audio.consume(batch(samples.cannon,1),chart)
	check(float(audio.voices[0].player.volume_db)<near_db and audio.voices[0].player.position.is_equal_approx(Vector2(-1000,0)),"camera distance attenuates and projects actual weapon reports")
	audio.reset_battle();chart.camera+=Vector2(1300,0)
	audio.consume(batch(samples.cannon,1),chart)
	check(audio.received==1 and audio.scheduled==0 and audio.dropped==1,"reports beyond the existing 2200-unit radius are culled")
	audio.reset_battle();chart.camera=Vector2(samples.gun.x,samples.gun.y)
	audio.enabled=false
	var muted: Array=batch(samples.gun,1)
	audio.consume(muted,chart);audio._process(0.0)
	check(audio.received==1 and audio.scheduled==0 and audio.rapid_until.is_empty(),"mute consumes sequences without scheduling or reserving gun admission")
	audio.enabled=true;audio.consume(muted,chart)
	check(audio.scheduled==0,"unmuting cannot replay an already consumed sequence")
	audio.weapon_volume=0.25;audio.ambience_volume=0.4;audio._process(0.0)
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("BrassWeapons")),linear_to_db(0.25)) and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("BrassAmbience")),linear_to_db(0.4)),"independent weapon and ambience volume settings reach their buses")
	audio.weapon_volume=0.0;audio._process(0.0)
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("BrassWeapons"))<=-79.9,"zero weapon volume retains its existing silent bus floor")
	audio.reset_battle()
	check(audio.last_seq==0 and audio.received==0 and audio.rapid_until.is_empty(),"new engagement clears sequence and source admission state")

func run() -> void:
	audio=Sound.new();root.add_child(audio);audio.set_process(false)
	check(audio.headless and DisplayServer.get_name()=="headless","fixture requires silent headless execution")
	if not audio.headless:audio.free();finish();return
	var bank_ok: bool=true
	for family in ["gun","cannon","rocket","wood","metal","splash"]:
		var valid: bool=audio.bank.get(family,[]).size()==3
		for stream in audio.bank.get(family,[]):valid=valid and stream is AudioStreamWAV and stream.get_length()>0.03
		check(valid,"three decodable existing recording variants: "+family)
		bank_ok=bank_ok and valid
	if bank_ok:
		var samples: Dictionary=native_records()
		if samples.has("sink"):mix_checks(samples)
	var silent: bool=not audio.engine_player.playing
	for slot in audio.voices:silent=silent and not slot.player.playing
	check(silent and audio.peak_voices<=32,"headless scheduling never starts weapon or engine playback")
	audio.free()
	finish()

func finish() -> void:
	print("COMBAT FEEDBACK 040: ",checks," checks, ",failures," failures; decoding/scheduling only, no listening acceptance")
	quit(0 if failures==0 else 1)
