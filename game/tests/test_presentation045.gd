extends SceneTree
## Root-only silent fixture. Capture primitives and schedules, never audition or render.
const Events=preload("res://scripts/combat_events.gd")
const FX=preload("res://scripts/combat_art.gd")
const Feedback=preload("res://scripts/hull_feedback.gd")
const Sound=preload("res://scripts/sound.gd")
const Damage=preload("res://scripts/damage.gd")
const Core=preload("res://scripts/equipment_condition.gd")
const Records=preload("res://scripts/equipment_records.gd")
const Refit=preload("res://scripts/refit.gd")
const Art=preload("res://scripts/boat_art.gd")
const Layout=preload("res://scripts/mount_layout.gd")
const Profiles=preload("res://scripts/hull_profiles.gd")
const Capture=preload("res://tests/test_feedback.gd").Recorder
const FITS: Dictionary={"gun":"rapid_gun","cannon":"light_cannon","rocket":"fire_rocket","torpedo":"light_torpedo"}
var checks: int=0
var failures: int=0
var bases: Dictionary={}
var samples: Dictionary={}
var state: Dictionary={"time":0.0,"effects":[],"wrecks":[]}

class MixChart extends RefCounted:
	var camera:=Vector2.ZERO
	func project(p: Vector2) -> Vector2:return p-camera

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("PRESENTATION045: "+message)

func canonical(base: Dictionary,uid: String,weapon: String="") -> Dictionary:
	var boat: Dictionary=Damage.create_ship(base,{"id":uid,"uid":uid})
	Refit.ensure(boat,base)
	if not weapon.is_empty():
		boat.loadout.weapons[0]=weapon
		boat.spec=Refit.effective_spec(base,boat.loadout)
	var seeded: Dictionary=Records.initialize(boat,{"base":base,"loadout":boat.loadout,"catalog":Refit.catalog(),"identity":uid,"knownUids":[]})
	check(bool(seeded.ok),"canonical fitted fixture: "+uid)
	return boat

func real_contacts() -> void:
	var rng:=RandomNumberGenerator.new()
	for family in Events.FAMILIES:
		var shooter: Dictionary=canonical(bases.tin_skiff,"feedback045-"+family,FITS[family])
		var mount: Dictionary=shooter.spec.weaponMounts[0]
		check(str(mount.kind)==family,"actual fitted family reaches producer: "+family)
		samples[family+"_fire"]=Events.emit_fire(state,shooter,mount,0,Vector2.ZERO,0.0)
		var shot: Dictionary={"kind":Events.projectile_kind(family),"family":family,"damage":mount.damage,"penetration":4.0,"owner":shooter.id,"sourceUid":shooter.uid,"team":"player","vx":200.0,"vy":0.0,"mountId":mount.id}
		var target: Dictionary=canonical(bases.cinder_monitor,"feedback045-target-"+family)
		var hp_before: float=float(target.hp)
		rng.seed=4500
		var outcome: Array=Damage.apply_hit(target,{"kind":shot.kind,"damage":shot.damage,"penetration":shot.penetration,"section":"bow"},rng)
		samples[family+"_hit"]=Events.emit_hit(state,shot,target,Vector2.ZERO,"bow",outcome,hp_before-float(target.hp))
		samples[family+"_miss"]=Events.emit_miss(state,shot,Vector2.ZERO,false)
		check(float(samples[family+"_hit"].damage)>0.0,"real numerical damage precedes contact: "+family)
	# Find both real shell outcomes in a bounded deterministic seed set. Neither
	# breach text nor effect flags are invented just to select an art branch.
	for attempt in range(16):
		if samples.has("breach") and samples.has("contact"):break
		var target: Dictionary=canonical(bases.cinder_monitor,"feedback045-shell-%d"%attempt)
		var shot: Dictionary={"kind":"shell","family":"cannon","owner":"feedback045-cannon","team":"player","vx":200.0,"vy":0.0}
		rng.seed=4550+attempt
		var hp_before: float=float(target.hp)
		var outcome: Array=Damage.apply_hit(target,{"kind":"shell","damage":28.0,"penetration":6.0,"section":"bow"},rng)
		var event: Dictionary=Events.emit_hit(state,shot,target,Vector2.ZERO,"bow",outcome,hp_before-float(target.hp))
		var label: String="breach" if bool(event.breach) else "contact"
		for effect in state.effects:
			if effect.kind=="hit" and int(effect.seq)==int(event.seq):samples[label]=effect.duplicate(true);break
	check(samples.has("breach") and samples.has("contact"),"actual Damage shell outcomes include opened and unopened armor")

func visual_checks() -> void:
	var fire_draws: Dictionary={}
	for effect in state.effects:
		var near_count: int=0
		for lod in range(3):
			var value: Dictionary=effect.duplicate(true)
			value.lod=lod
			for phase in [0.0,0.3,0.8]:
				value.age=float(value.life)*phase
				var before: PackedByteArray=var_to_bytes(value)
				var rec=Capture.new()
				var count: int=FX.effect(rec,value)
				check(count>0 and count<=35 and count==rec.prims.size() and rec.invalid==0,"finite, counted existing effect budget: %s/%s/LOD%d"%[value.family,value.kind,lod])
				check(var_to_bytes(value)==before,"effect drawing leaves complete event metadata unchanged")
				if lod==0 and phase==0.3:
					near_count=count
					if value.kind=="fire":fire_draws[str(value.family)]=rec.prims
					if value.family=="torpedo":check(flames(rec.prims)==0,"wet launch/contact has no orange rocket fireball")
				if lod==2 and phase==0.3:check(count<=near_count,"far effect adds no detail beyond near LOD")
			value.age=value.life
			check(FX.effect(Capture.new(),value)==0,"completed event stops drawing")
	for family in Events.FAMILIES:
		check(fire_draws.has(family),"real muzzle/launch captured: "+family)
	for pair in [["gun","cannon"],["cannon","rocket"],["rocket","torpedo"],["gun","torpedo"]]:
		check(fire_draws.get(pair[0])!=fire_draws.get(pair[1]),"distinct real launch geometry: "+str(pair))
	if samples.has("breach") and samples.has("contact"):
		# Equalize only cosmetic sequence/age to isolate actual breach routing.
		var opened: Dictionary=samples.breach.duplicate(true)
		var closed: Dictionary=samples.contact.duplicate(true)
		opened.seq=701;closed.seq=701
		opened.age=opened.life*0.3;closed.age=closed.life*0.3
		var a=Capture.new();var b=Capture.new()
		FX.effect(a,opened);FX.effect(b,closed)
		check(a.prims!=b.prims,"reported breach changes actual armor contact geometry")

func flames(primitives: Array) -> int:
	var count: int=0
	for primitive in primitives:
		var color: Array=primitive.c
		if float(color[0])>0.9 and float(color[1])<0.7 and float(color[2])<0.3:count+=1
	return count

func equipment_capture(boat: Dictionary,lod: int=0) -> Array:
	var rec=Capture.new()
	var ctx: Dictionary={"canvas":rec,"proj":rec.project,"pos":Vector2.ZERO,"angle":0.0,"size":float(boat.spec.size),"px":float(boat.spec.size)*2.0,"lod":lod,"n":0,"npoly":0,"nline":0,"ncirc":0}
	var before: PackedByteArray=var_to_bytes(boat)
	Feedback.draw_equipment(ctx,boat,Art.mounts_of(boat.spec))
	check(ctx.n<=18 and ctx.n==rec.prims.size() and rec.invalid==0 and var_to_bytes(boat)==before,"live module overlay is finite, bounded and read-only")
	return rec.prims

func equipment_checks() -> void:
	var boat: Dictionary=canonical(bases.maiden_dreadnought,"feedback045-equipment","rapid_gun")
	var intact: Dictionary=boat.duplicate(true)
	check(equipment_capture(boat).is_empty(),"intact installed modules have no damage overlay")
	for item in boat.moduleCondition.items.values():
		if str(item.location) in ["mount0","engine","pumps"]:
			check(bool(Core.apply_component_damage(boat.moduleCondition,{"itemUid":item.itemUid,"loss":0.85,"cause":"Fixture component damage"}).ok),"canonical damage: "+str(item.location))
	check(float(boat.engine)==1.0 and Feedback._engine_hp(boat)<0.3,"engine art reads live installed hp before scalar publication")
	check(bool(Records.publish(boat).ok),"publish actual damaged engine scalar")
	var marks: Array=Feedback.equipment_marks(boat,Art.mounts_of(boat.spec))
	check(marks.size()==3,"only the real damaged gun, engine and bilge pump are marked")
	var structure: Dictionary=Layout.structure(boat.spec)
	var mount: Dictionary=Art.mounts_of(boat.spec)[0]
	for mark in marks:
		var part: Dictionary=mount if mark.location=="mount0" else structure.engine if mark.location=="engine" else structure.cabin
		check(mark.at==Vector2(part.x,part.y) and mark.status=="disabled","disabled symbol follows real module anchor: "+str(mark.location))
	var disabled: Array=equipment_capture(boat)
	check(not disabled.is_empty() and equipment_capture(boat,2).is_empty(),"disabled modules remain near-LOD-only")
	var snapshot: Dictionary=boat.duplicate(true)
	var repair: Dictionary=Core.repair_installed(boat.moduleCondition,{"work":100.0,"supplies":float(boat.supplies),"hpPerWork":0.04,"suppliesPerHp":{"weapons":1.0,"engines":1.5,"pumps":1.2},"priority":"auto"})
	boat.supplies-=float(repair.get("usedSupplies",0.0))
	check(bool(repair.ok) and float(repair.get("usedSupplies",0))>0.0 and Feedback._engine_hp(boat)>=0.72,"finite supply-consuming repair immediately changes live engine art")
	check(bool(Records.publish(boat).ok) and equipment_capture(boat)!=disabled,"real repair replaces disabled crosses without rebuilding art")
	check(equipment_capture(snapshot)==disabled and equipment_capture(intact).is_empty(),"same-ID detached states never share cached condition")
	var ctx: Dictionary={"canvas":Capture.new(),"proj":func(p: Vector2,_h: float):return p,"pos":Vector2.ZERO,"angle":0.0,"size":float(boat.spec.size),"px":float(boat.spec.size)*2.0,"lod":0,"clock":0.4,"n":0,"npoly":0,"nline":0,"ncirc":0}
	Feedback.draw(ctx,boat,Profiles.stations(boat.spec))
	check(ctx.n==0,"repaired dry, unlit hull invents no fire or engine smoke")

func sinking_checks() -> void:
	var rng:=RandomNumberGenerator.new()
	for burning in [false,true]:
		var boat: Dictionary={}
		for attempt in range(16):
			boat=canonical(bases.tin_skiff,"feedback045-sink-%s-%d"%[burning,attempt])
			rng.seed=4590+attempt
			Damage.apply_hit(boat,{"damage":100000.0,"kind":"rocket" if burning else "bullet","section":"bow"},rng)
			if burning or float(boat.fire)==0.0:break
		check(bool(boat.sunk) and (float(boat.fire)>0.0)==burning,"terminal Damage state precedes actual fire/cold wreck")
		var wreck: Dictionary=Events.record_wreck(state,boat,float(boat.spec.size))
		var event: Dictionary=Events.emit_sink(state,boat,wreck)
		samples["burning_sink" if burning else "cold_sink"]=event
		var effect: Dictionary=state.effects[-1]
		var rec=Capture.new();FX.effect(rec,effect)
		check(bool(wreck.onFire)==burning and (flames(rec.prims)>0)==burning,"sink effect fire follows actual wreck fire flag")
		var counts: Array=[]
		for progress in [0.0,0.45,0.9,1.0]:
			wreck.sinkProgress=progress;wreck.age=progress*float(wreck.sinkDuration)
			var before: PackedByteArray=var_to_bytes(wreck)
			var capture=Capture.new()
			var count: int=FX.wreck(capture,wreck)
			check(count==capture.prims.size() and capture.invalid==0 and var_to_bytes(wreck)==before,"listing/submergence draws finite real wreck state without changing it")
			counts.append(count)
		check(counts[0]>counts[-1],"completed submergence stops drawing the hull")
		wreck.age=8.0
		var tail=Capture.new();FX.wreck(tail,wreck)
		var circles: int=0
		for primitive in tail.prims:circles+=1 if primitive.t=="circle" else 0
		check(circles==0 and tail.prims.size()<=FX.MAX_WRECK_OVERLAY_PRIMS,"completed wreck retains debris without perpetual bubbles or new deaths")
	var flooded: Dictionary=Damage.create_ship(bases.tin_skiff,{"id":"feedback045-flooded","water":1000000.0})
	var flood_wreck: Dictionary=Events.record_wreck(state,flooded,float(flooded.spec.size))
	Events.emit_sink(state,flooded,flood_wreck)
	var flood=Capture.new();FX.effect(flood,state.effects[-1])
	check(flooded.sunk and flood_wreck.cause=="flooding" and flames(flood.prims)==0,"actual terminal flooding remains a cold water surge")

func stress_events(record: Dictionary,count: int,sequence: Dictionary) -> Array:
	Events.begin_step(sequence)
	var out: Array=[]
	for i in range(count):
		var raw: Dictionary=record.duplicate(true)
		raw.sourceUid="feedback045-stress-%d"%int(sequence.get("eventSeq",0))
		out.append(Events.push_event(sequence,raw))
	return out

func sound_checks() -> void:
	var chart:=MixChart.new()
	var audio=Sound.new();root.add_child(audio);audio.set_process(false)
	check(audio.headless,"recorded-bank scheduling remains silent")
	for kind in ["gun","cannon","rocket","splash","wood","metal"]:
		var valid: bool=audio.bank.get(kind,[]).size()==3
		for stream in audio.bank.get(kind,[]):valid=valid and stream is AudioStreamWAV and stream.get_length()>0.03
		check(valid,"existing licensed recording variants decode: "+kind)
	for key in samples:
		if key in ["breach","contact"]:continue
		var before: PackedByteArray=var_to_bytes(samples[key])
		var layers: Array=Sound.event_layers(samples[key])
		check(not layers.is_empty() and layers.size()<=2 and var_to_bytes(samples[key])==before,"actual event routes at most two read-only layers: "+key)
		for layer in layers:
			check(audio.bank.has(layer.sound) and is_finite(float(layer.gain)) and float(layer.gain)<=-12.0 and float(layer.pitch)>=0.65 and float(layer.pitch)<=1.25,"finite existing-bank gain/pitch schedule")
	for pair in [["gun","gun"],["cannon","cannon"],["rocket","rocket"],["torpedo","splash"]]:
		check(Sound.event_layers(samples[pair[0]+"_fire"])[0].sound==pair[1],"real fire recording route: "+str(pair[0]))
	var wet: Array=Sound.event_layers(samples.torpedo_hit)
	var dry: Array=Sound.event_layers(samples.rocket_hit)
	check(wet[0].sound=="splash" and wet[1].sound=="cannon" and wet[0].gain>wet[1].gain and wet[1].pitch<dry[0].pitch and dry[0].sound=="cannon","wet torpedo attack stays distinct from dry rocket impact")
	var previous: float=1.0
	for distance in [0.0,320.0,1000.0,1800.0,2199.0]:
		var gain: float=Sound.attenuation_db(distance)
		check(is_finite(gain) and gain<=0.0 and gain<previous,"continuous camera attenuation: "+str(distance))
		previous=gain
	var original: PackedByteArray=var_to_bytes(state)
	audio.consume(state.events,chart)
	check(audio.received==state.events.size() and audio.scheduled<=12 and audio.peak_voices<=32 and var_to_bytes(state)==original,"real mixed events share the original voice/admission caps without changing combat")
	var scheduled: int=audio.scheduled
	audio.consume(state.events,chart)
	check(audio.scheduled==scheduled,"consumed sequences never replay")
	# Re-sequence authentic records only for admission stress; no simulated damage.
	audio.reset_battle()
	var sequence: Dictionary={"time":0.0}
	audio.consume(stress_events(samples.torpedo_hit,16,sequence),chart)
	var splash_count: int=0
	for slot in audio.voices:
		if float(slot.until)>audio.clock and slot.player.stream in audio.bank.splash:splash_count+=1
	check(audio.scheduled==12 and splash_count==12,"crowding preserves wet torpedo primaries before any dry secondary layers")
	audio.reset_battle();sequence={"time":0.0}
	for batch in range(3):audio.consume(stress_events(samples.gun_fire,12,sequence),chart)
	var crowd: Array=stress_events(samples.gun_fire,16,sequence)
	crowd.append_array(stress_events(samples.cold_sink,1,sequence))
	crowd.append_array(stress_events(samples.torpedo_hit,1,sequence))
	scheduled=audio.scheduled;audio.consume(crowd,chart)
	var important: int=0
	var longest: float=0.0
	for variants in audio.bank.values():
		for stream in variants:longest=maxf(longest,stream.get_length()/0.65)
	for slot in audio.voices:
		if float(slot.until)>audio.clock and float(slot.priority)>audio.priority(samples.gun_fire,chart.camera):important+=1
		check(is_finite(float(slot.until)) and float(slot.until)-audio.clock<=longest+0.001 and slot.player.position.is_finite(),"active voice lifetime and position stay finite and bounded by existing clips")
	check(important>=2 and audio.scheduled-scheduled<=12 and audio.peak_voices<=32 and audio.voices.size()==32,"important real contacts displace routine reports within unchanged budgets")
	audio.reset_battle();sequence={"time":0.0};chart.camera=Vector2(2300,0)
	audio.consume(stress_events(samples.cannon_fire,1,sequence),chart)
	check(audio.scheduled==0 and audio.dropped==1,"existing distant-event cull remains bounded")
	var silent: bool=not audio.engine_player.playing
	for slot in audio.voices:silent=silent and not slot.player.playing
	check(silent and audio.rapid_until.size()<=128,"fixture never plays weapon or procedural engine audio")
	audio.free()

func run() -> void:
	if DisplayServer.get_name()!="headless":
		check(false,"Root must run this fixture headless with Dummy audio")
		finish();return
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	for hull in world.HULLS:bases[str(hull.id)]=hull
	real_contacts()
	visual_checks()
	equipment_checks()
	sinking_checks()
	sound_checks()
	finish()

func finish() -> void:
	print("PRESENTATION045: %d checks, %d failures; routing/geometry/scheduling only, no listening, rendered motion or quality acceptance"%[checks,failures])
	quit(0 if failures==0 else 1)
