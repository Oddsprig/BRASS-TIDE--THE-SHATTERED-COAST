extends SceneTree
## v0.071 presentation invariants. Root runs this headless through Test Bridge.
## Reuses the feedback recorder. No battle loop, golden geometry, economy or save work.
const Events = preload("res://scripts/combat_events.gd")
const FX = preload("res://scripts/combat_art.gd")
const Sound = preload("res://scripts/sound.gd")
const Wake = preload("res://scripts/wake_art045.gd")
const Art = preload("res://scripts/boat_art.gd")
const Chart = preload("res://scripts/chart.gd")
const FeedbackTest = preload("res://tests/test_feedback.gd")
const BANKS: Array = ["gun", "cannon", "rocket", "splash", "wood", "metal"]

var checks: int = 0
var failures: int = 0

class HearChart extends RefCounted:
	var camera: Vector2 = Vector2.ZERO
	func project(point: Vector2) -> Vector2:
		return point - camera

class PoseSource extends RefCounted:
	var poses: Dictionary = {}
	var fraction: float = 0.5
	func presentation_poses() -> Dictionary:
		return poses
	func presentation_fraction() -> float:
		return fraction

class HostStub extends RefCounted:
	var mode: String = "battle"
	var battle: Dictionary = {}
	var battle_driver051 = null
	var core = null

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PRESENTATION071: " + message)

func fresh_state() -> Dictionary:
	return {"time": 3.0, "effects": [], "wrecks": [], "events": [], "eventSeq": 0, "droppedEvents": 0, "_stepEvents": 0, "_engineTracker": {}, "_hitTracker": {}}

func hull(id: String, role: String = "skiff") -> Dictionary:
	var spec_id: String = "slag_gunboat" if role == "gunboat" else "tin_skiff"
	return {
		"id": id, "uid": id, "team": "player", "type": spec_id, "name": id,
		"x": 10.0, "y": 20.0, "angle": 0.2, "turretAngle": 0.2,
		"vx": 0.0, "vy": 0.0, "hp": 90.0, "maxHp": 100.0, "engine": 1.0,
		"fire": 0.0, "water": 0.0, "capacity": 100.0, "sunk": false, "breaches": [], "visualHits": [],
		"spec": {"id": spec_id, "role": role, "armor": 12.0 if role == "gunboat" else 2.0, "size": 22.0 if role == "gunboat" else 14.0, "tier": 1, "faction": "compact"}
	}

func mount_of(id: String, kind: String, module_id: String, damage: float, index: int) -> Dictionary:
	return {"id": id, "kind": kind, "moduleId": module_id, "size": 1, "damage": damage, "barrelHeight": 9.0, "x": 4.0 + float(index), "y": -1.5}

func find_event(batch: Array, mount_id: String, kind: String) -> Dictionary:
	for ev in batch:
		if str(ev.get("mountId", "")) == mount_id and str(ev.get("kind", "")) == kind:
			return ev
	return {}

func find_effect(effects: Array, kind: String, family: String) -> Dictionary:
	for effect in effects:
		if str(effect.get("kind", "")) == kind and str(effect.get("family", "")) == family:
			return effect
	return {}

func layers_ok(ev: Dictionary, primary: String, accent: String = "") -> void:
	var layers: Array = Sound.event_layers(ev)
	var label: String = "%s/%s" % [str(ev.get("kind", "")), str(ev.get("family", ""))]
	check(not layers.is_empty() and str(layers[0].get("sound", "")) == primary, label + " routes to " + primary)
	if accent.is_empty():
		check(layers.size() == 1, label + " has one reported layer")
	else:
		check(layers.size() == 2 and str(layers[1].get("sound", "")) == accent, label + " accent routes to " + accent)
	for layer in layers:
		var pitch: float = float(layer.get("pitch", NAN))
		check(BANKS.has(str(layer.get("sound", ""))) and float(layer.get("gain", 1.0)) <= 0.0 and pitch >= 0.65 and pitch <= 1.25, label + " stays on a recorded bank, unclipped, in pitch range")

func nearest(rec, point: Vector2) -> float:
	var best: float = INF
	for prim in rec.prims:
		for xy in prim.pts:
			best = minf(best, Vector2(float(xy[0]), float(xy[1])).distance_to(point))
	return best

func capture(effect: Dictionary) -> Object:
	var before: PackedByteArray = var_to_bytes(effect)
	var rec = FeedbackTest.Recorder.new()
	rec.origin = Vector2.ZERO
	rec.scale_factor = 1.0
	var drawn: int = FX.effect(rec, effect)
	check(var_to_bytes(effect) == before, "drawing leaves the reported effect unchanged")
	check(drawn == rec.prims.size() and drawn <= FX.MAX_EFFECT_PRIMS and rec.invalid == 0 and rec.transform == Transform2D.IDENTITY, "effect draw stays finite and inside the primitive cap")
	return rec

func anchored(rec, effect: Dictionary) -> void:
	var world: Vector2 = Vector2(float(effect.x), float(effect.y))
	var here: float = minf(nearest(rec, rec.project(world, float(effect.get("height", 0.0)))), nearest(rec, rec.project(world, 0.0)))
	var far: float = nearest(rec, rec.project(world + Vector2(500.0, 0.0), 0.0))
	check(here < 48.0 and here < far, str(effect.get("kind", "")) + "/" + str(effect.get("family", "")) + " is drawn at the reported point")

func paint_wake(samples: Array):
	var before: PackedByteArray = var_to_bytes(samples)
	var rec = FeedbackTest.Recorder.new()
	rec.origin = Vector2.ZERO
	rec.scale_factor = 1.0
	var count: int = Wake.draw(rec, Callable(rec, "project"), samples, {"affine_water": true})
	check(var_to_bytes(samples) == before, "wake drawing leaves samples unchanged")
	check(count <= Wake.MAX_PRIMITIVES and rec.invalid == 0 and rec.transform == Transform2D.IDENTITY, "wake drawing stays bounded, finite and restored")
	return {"count": count, "recorder": rec}

func run():
	var started: int = Time.get_ticks_usec()
	route()
	budgets()
	var audio: Sound = Sound.new()
	root.add_child(audio)
	await process_frame
	mix(audio)
	speed_and_worker()
	var elapsed_ms: int = int((Time.get_ticks_usec() - started) / 1000)
	check(elapsed_ms < 10000, "fixture body stays under 10 seconds")
	audio.queue_free()
	print("combat_presentation071: %d checks, %d failures; %d ms; routing/budget/sequence/mount/speed-stop/worker-safe only" % [checks, failures, elapsed_ms])
	quit(0 if failures == 0 else 1)

func route() -> void:
	var st: Dictionary = fresh_state()
	Events.begin_step(st)
	var shooter: Dictionary = hull("shooter")
	var wood: Dictionary = hull("wood-target")
	var armor: Dictionary = hull("armor-target", "gunboat")
	var mounts: Array = [
		mount_of("m-gun", "gun", "rapid_gun", 11.0, 0),
		mount_of("m-cannon", "cannon", "light_cannon", 26.0, 1),
		mount_of("m-rocket", "rocket", "fire_rocket", 32.0, 2),
		mount_of("m-torpedo", "torpedo", "light_torpedo", 38.0, 3)
	]
	var muzzles: Array = [Vector2(40.0, -12.0), Vector2(36.0, 14.0), Vector2(-8.0, -16.0), Vector2(-6.0, 18.0)]
	var mount_bytes: PackedByteArray = var_to_bytes(mounts)
	for index in mounts.size():
		Events.emit_fire(st, shooter, mounts[index], index, muzzles[index], 0.4, wood)
	check(var_to_bytes(mounts) == mount_bytes, "firing preserves the supplied mount dictionaries")
	for index in mounts.size():
		check(is_equal_approx(Events.mount_shot_time(shooter, str(mounts[index].id)), float(st.time)), str(mounts[index].id) + " records this battle time")
	var gun_hit: Dictionary = {"kind": "bullet", "family": "gun", "vx": 80.0, "vy": 0.0, "owner": "shooter", "sourceUid": "shooter", "team": "player", "mountId": "m-gun", "mountIndex": 0, "variant": "light"}
	var cannon_hit: Dictionary = {"kind": "shell", "family": "cannon", "vx": -80.0, "vy": 0.0, "owner": "shooter", "sourceUid": "shooter", "team": "player", "mountId": "m-cannon", "mountIndex": 1, "variant": "light"}
	var rocket_hit: Dictionary = {"kind": "rocket", "family": "rocket", "vx": 40.0, "vy": 10.0, "owner": "shooter", "sourceUid": "shooter", "team": "player", "mountId": "m-rocket", "mountIndex": 2, "variant": "light", "incendiary": true}
	var torpedo_hit: Dictionary = {"kind": "torpedo", "family": "torpedo", "vx": 20.0, "vy": 0.0, "owner": "shooter", "sourceUid": "shooter", "team": "player", "mountId": "m-torpedo", "mountIndex": 3, "variant": "light"}
	Events.emit_hit(st, gun_hit, wood, Vector2(12.0, 21.0), "bow", [], 8.0, true)
	Events.emit_hit(st, cannon_hit, armor, Vector2(14.0, 22.0), "mid", ["Breach:mid"], 20.0, true)
	Events.emit_hit(st, rocket_hit, wood, Vector2(11.0, 19.0), "stern", [], 18.0, true)
	Events.emit_hit(st, torpedo_hit, wood, Vector2(13.0, 20.0), "bow", [], 30.0, true)
	Events.emit_miss(st, gun_hit, Vector2(80.0, 20.0), false)
	Events.emit_miss(st, cannon_hit, Vector2(90.0, 30.0), true)
	var trouble: Dictionary = hull("trouble")
	Events.register_ship(st, trouble, [])
	var quiet: PackedByteArray = var_to_bytes(st.events)
	Events.check_ship_engine(st, trouble)
	check(var_to_bytes(st.events) == quiet, "a healthy engine does not invent a failure")
	trouble.engine = 0.2
	Events.check_ship_engine(st, trouble)
	Events.check_ship_engine(st, trouble)
	var wreck: Dictionary = Events.record_wreck(st, wood, 14.0)
	wreck.cause = "flooding"
	wreck.onFire = false
	Events.emit_sink(st, wood, wreck)
	var batch: Array = Events.pop_events(st)
	check(Events.pop_events(st).is_empty(), "pop_events drains the reported batch once")
	var previous_seq: int = 0
	var engine_failures: int = 0
	for ev in batch:
		var seq: int = int(ev.seq)
		check(seq > previous_seq and seq == int(ev.id) and seq == int(ev.sequence), "event id, seq and sequence advance together")
		previous_seq = seq
		if str(ev.kind) == "engine":
			engine_failures += 1
	check(engine_failures == 1, "engine trouble is reported once when the stage actually drops")
	for index in mounts.size():
		var fired: Dictionary = find_event(batch, str(mounts[index].id), "fire")
		check(not fired.is_empty() and is_equal_approx(float(fired.get("x", NAN)), muzzles[index].x) and is_equal_approx(float(fired.get("y", NAN)), muzzles[index].y) and int(fired.get("mountIndex", -2)) == index, str(mounts[index].id) + " keeps its muzzle and index")
	layers_ok(find_event(batch, "m-gun", "fire"), "gun")
	layers_ok(find_event(batch, "m-cannon", "fire"), "cannon")
	layers_ok(find_event(batch, "m-rocket", "fire"), "rocket")
	layers_ok(find_event(batch, "m-torpedo", "fire"), "splash")
	layers_ok(find_event(batch, "m-gun", "hit"), "wood")
	layers_ok(find_event(batch, "m-cannon", "hit"), "metal", "cannon")
	layers_ok(find_event(batch, "m-rocket", "hit"), "cannon", "wood")
	layers_ok(find_event(batch, "m-torpedo", "hit"), "splash", "cannon")
	var misses: Array = batch.filter(func(ev): return str(ev.kind) == "miss")
	check(misses.size() == 2, "water and land misses are both reported")
	if misses.size() == 2:
		check(str(misses[0].material) == "water" and str(misses[1].material) == "land", "misses stay misses on water and on land")
		layers_ok(misses[0], "splash")
		layers_ok(misses[1], "wood")
	layers_ok(find_event(batch, "", "engine"), "metal")
	var sinks: Array = batch.filter(func(ev): return str(ev.kind) == "sink")
	check(sinks.size() == 1 and str(sinks[0].get("reason", "")) == "flooding" and not bool(sinks[0].get("incendiary", true)), "sinking keeps the reported flooding cause")
	if sinks.size() == 1:
		layers_ok(sinks[0], "splash", "wood")
	check(Sound.event_layers({"kind": "note", "family": "gun", "seq": 1}).is_empty(), "an unknown kind does not invent a weapon layer")
	var signatures: Dictionary = {}
	var rec = null
	for family in ["gun", "cannon", "rocket", "torpedo"]:
		var muzzle_fx: Dictionary = find_effect(st.effects, "fire", family)
		var reported: Dictionary = find_event(batch, "m-" + family, "fire")
		check(not muzzle_fx.is_empty() and not reported.is_empty() and is_equal_approx(float(muzzle_fx.get("x", NAN)), float(reported.get("x", NAN))), family + " muzzle effect uses the reported muzzle")
		if muzzle_fx.is_empty():
			continue
		rec = capture(muzzle_fx)
		check(rec.prims.size() > 0, family + " muzzle draws while it is fresh")
		anchored(rec, muzzle_fx)
		var signature: String = _signature(rec)
		check(not signatures.has(signature), family + " muzzle is distinct from " + str(signatures.get(signature, "")))
		signatures[signature] = family
		var spent: Dictionary = muzzle_fx.duplicate(true)
		spent.age = float(spent.life)
		var blank = capture(spent)
		check(blank.prims.is_empty(), family + " muzzle stops when its life is over")
	var saw_kind: bool = false
	for kind in ["hit", "miss", "engine", "sink"]:
		saw_kind = false
		for drawn in st.effects:
			if str(drawn.kind) != kind:
				continue
			saw_kind = true
			rec = capture(drawn)
			check(rec.prims.size() > 0, kind + "/" + str(drawn.family) + " draws from the reported effect")
			anchored(rec, drawn)
			break
		check(saw_kind, kind + " effect was reported")
	var empty = capture({})
	check(empty.prims.is_empty(), "an empty effect draws nothing")

func _signature(rec) -> String:
	var text: String = ""
	for prim in rec.prims:
		var color: Array = prim.c
		if not text.is_empty():
			text += "|"
		text += "%s:%d,%d,%d" % [str(prim.t), roundi(float(color[0]) * 20.0), roundi(float(color[1]) * 20.0), roundi(float(color[2]) * 20.0)]
	return text

func budgets() -> void:
	var st: Dictionary = fresh_state()
	Events.begin_step(st)
	var kept: int = 0
	for _i in Events.MAX_STEP_EVENTS:
		if not Events.push_event(st, {"kind": "fire", "family": "cannon", "x": 0.0, "y": 0.0}).is_empty():
			kept += 1
	check(kept == Events.MAX_STEP_EVENTS, "events inside the step cap are kept")
	check(Events.push_event(st, {"kind": "fire", "family": "cannon"}).is_empty() and int(st.droppedEvents) >= 1 and st.events.size() == Events.MAX_STEP_EVENTS, "the step cap drops overflow")
	Events.begin_step(st)
	while st.events.size() < Events.MAX_EVENTS:
		Events.push_event(st, {"kind": "hit", "family": "gun", "material": "wood"})
	var oldest: int = int(st.events[0].seq)
	Events.begin_step(st)
	Events.push_event(st, {"kind": "hit", "family": "gun", "material": "wood"})
	check(st.events.size() == Events.MAX_EVENTS and int(st.events[0].seq) != oldest, "the event ring drops the oldest report")
	var fx: Dictionary = fresh_state()
	for index in Events.MAX_EFFECTS + 5:
		Events.add_effect(fx, Vector2(float(index), 0.0), "muzzle", {"kind": "fire", "family": "gun", "seq": index})
	check(fx.effects.size() == Events.MAX_EFFECTS and int(fx.effects[0].seq) == 5, "the effect cap drops the oldest effect")
	var wrecks: Dictionary = fresh_state()
	for index in Events.MAX_WRECKS + 5:
		var ship: Dictionary = hull("w-%d" % index)
		Events.record_wreck(wrecks, ship, 14.0)
	check(wrecks.wrecks.size() == Events.MAX_WRECKS and str(wrecks.wrecks[0].id) != "w-0", "the wreck cap drops the oldest wreck")

func mix(audio: Sound) -> void:
	check(audio.headless, "presentation audio stays headless")
	check(audio.voices.size() == Sound.VOICE_LIMIT, "voice pool stays at its cap")
	for bank_name in BANKS:
		check(audio.bank[bank_name].size() > 0, "recorded bank is present: " + bank_name)
	var near: float = Sound.attenuation_db(0.0)
	check(is_equal_approx(near, Sound.attenuation_db(0.0)) and Sound.attenuation_db(Sound.AUDIBLE_RADIUS) < near and is_equal_approx(Sound.attenuation_db(NAN), -36.0), "distance falloff is finite, monotonic and independent of zoom")
	var hear := HearChart.new()
	var crowded: Dictionary = fresh_state()
	Events.begin_step(crowded)
	for _i in Sound.EVENT_VOICE_LIMIT + 4:
		Events.push_event(crowded, {"kind": "fire", "family": "cannon", "x": 1.0, "y": 1.0, "team": "player"})
	var salvo: Array = Events.pop_events(crowded)
	var salvo_bytes: PackedByteArray = var_to_bytes(salvo)
	audio.consume(salvo, hear)
	check(var_to_bytes(salvo) == salvo_bytes, "sound admission does not rewrite events")
	check(audio.scheduled == Sound.EVENT_VOICE_LIMIT and audio.dropped >= 4 and audio.received == salvo.size(), "a crowded salvo keeps the voice admission cap")
	var again: int = audio.received
	audio.consume(salvo, hear)
	check(audio.received == again, "the same sequence is not admitted twice")
	audio.reset_battle()
	var accents: Dictionary = fresh_state()
	Events.begin_step(accents)
	for _i in 10:
		Events.push_event(accents, {"kind": "hit", "family": "rocket", "material": "wood", "x": 2.0, "y": 2.0, "team": "enemy", "breach": false})
	var blast: Array = Events.pop_events(accents)
	check(Sound.event_layers(blast[0]).size() == 2, "a rocket hit has a primary and an accent")
	audio.consume(blast, hear)
	check(audio.scheduled <= Sound.EVENT_VOICE_LIMIT and audio.scheduled < blast.size() * 2, "accents share the admission cap")
	audio.reset_battle()
	var ordered: Dictionary = fresh_state()
	Events.begin_step(ordered)
	for _i in 3:
		Events.push_event(ordered, {"kind": "fire", "family": "cannon", "x": 0.0, "y": 0.0, "team": "player"})
	var triple: Array = Events.pop_events(ordered)
	var shuffled: Array = [triple[0], triple[2], triple[1]]
	audio.consume(shuffled, hear)
	check(audio.received == 2 and audio.last_seq == int(triple[2].seq), "a later lower seq is not admitted")
	audio.reset_battle()
	var rapid: Dictionary = fresh_state()
	Events.begin_step(rapid)
	Events.push_event(rapid, {"kind": "fire", "family": "gun", "x": 0.0, "y": 0.0, "team": "player", "sourceUid": "same-hull", "sourceTeam": "player"})
	Events.push_event(rapid, {"kind": "fire", "family": "gun", "x": 0.0, "y": 0.0, "team": "player", "sourceUid": "same-hull", "sourceTeam": "player"})
	Events.push_event(rapid, {"kind": "fire", "family": "gun", "x": 0.0, "y": 0.0, "team": "player", "sourceUid": "other-hull", "sourceTeam": "player"})
	Events.push_event(rapid, {"kind": "hit", "family": "gun", "material": "wood", "x": 0.0, "y": 0.0, "team": "player", "sourceUid": "same-hull", "breach": true})
	audio.consume(Events.pop_events(rapid), hear)
	check(audio.scheduled == 3 and audio.dropped >= 1, "repeated MG reports from one hull collapse; another hull and a breach do not")
	audio.reset_battle()
	var ranked: Dictionary = fresh_state()
	Events.begin_step(ranked)
	Events.push_event(ranked, {"kind": "miss", "family": "cannon", "material": "land", "x": 0.0, "y": 0.0, "team": "player"})
	Events.push_event(ranked, {"kind": "sink", "family": "cannon", "material": "water", "x": 0.0, "y": 0.0, "team": "enemy"})
	audio.consume(Events.pop_events(ranked), hear)
	check(_bank_of(audio, audio.voices[0].player.stream) == "splash" and _bank_of(audio, audio.voices[1].player.stream) == "wood" and float(audio.voices[0].priority) > float(audio.voices[1].priority), "a sinking is scheduled before a miss")
	audio.reset_battle()
	var layered: Dictionary = fresh_state()
	Events.begin_step(layered)
	Events.push_event(layered, {"kind": "hit", "family": "rocket", "material": "wood", "x": 4.0, "y": -3.0, "team": "player"})
	audio.consume(Events.pop_events(layered), hear)
	check(_bank_of(audio, audio.voices[0].player.stream) == "cannon" and _bank_of(audio, audio.voices[1].player.stream) == "wood" and float(audio.voices[0].priority) > float(audio.voices[1].priority), "the rocket primary is scheduled before its accent")
	audio.reset_battle()
	audio.enabled = false
	var muted: Dictionary = fresh_state()
	Events.begin_step(muted)
	Events.push_event(muted, {"kind": "fire", "family": "cannon", "x": 0.0, "y": 0.0, "team": "player"})
	audio.consume(Events.pop_events(muted), hear)
	check(audio.received == 1 and audio.scheduled == 0, "disabled audio keeps sequence and schedules nothing")
	audio.enabled = true
	audio.reset_battle()
	var distant: Dictionary = fresh_state()
	Events.begin_step(distant)
	Events.push_event(distant, {"kind": "fire", "family": "cannon", "x": Sound.AUDIBLE_RADIUS + 80.0, "y": 0.0, "team": "player"})
	audio.consume(Events.pop_events(distant), hear)
	check(audio.received == 1 and audio.scheduled == 0 and audio.dropped >= 1, "events beyond audible radius are dropped")

func _bank_of(audio: Sound, stream) -> String:
	for bank_name in BANKS:
		if audio.bank[bank_name].has(stream):
			return bank_name
	return ""

func speed_and_worker() -> void:
	var moving: Array = []
	for index in 6:
		moving.append({"p": Vector2(float(index) * 8.0, 0.0), "age": float(5 - index) * 0.08, "w": 6.0})
	var painted = paint_wake(moving)
	check(int(painted.count) > 0, "a travelling stern paints a wash")
	var newest: Vector2 = moving.back().p
	var oldest: Vector2 = moving[0].p
	var covers_new: bool = false
	var covers_old: bool = false
	for prim in painted.recorder.prims:
		for xy in prim.pts:
			var point := Vector2(float(xy[0]), float(xy[1]))
			covers_new = covers_new or point.distance_to(painted.recorder.project(newest, 0.0)) <= Wake.MAX_WIDTH * 3.0
			covers_old = covers_old or point.distance_to(painted.recorder.project(oldest, 0.0)) <= Wake.MAX_WIDTH * 3.0
	check(covers_new and covers_old, "the wash spans the stern path that was actually travelled")
	var turning: Array = []
	for index in 6:
		var angle: float = float(index) * 0.12
		turning.append({"p": Vector2(cos(angle), sin(angle)) * float(index) * 8.0, "age": float(5 - index) * 0.08, "w": 6.0})
	check(int(paint_wake(turning).count) > 0, "a modest turn still paints")
	var stopped: Array = [{"p": Vector2(4.0, 4.0), "age": 0.0, "w": 6.0}, {"p": Vector2(4.02, 4.0), "age": 0.1, "w": 6.0}]
	check(int(paint_wake(stopped).count) == 0, "a stopped stern paints nothing")
	var expired: Array = [{"p": Vector2.ZERO, "age": Wake.LIFE_SEC, "w": 6.0}, {"p": Vector2(12.0, 0.0), "age": Wake.LIFE_SEC + 0.1, "w": 6.0}]
	check(int(paint_wake(expired).count) == 0, "samples older than wake life paint nothing")
	var chart: Chart = Chart.new()
	var boat: Dictionary = hull("runner")
	boat.x = 0.0
	boat.y = 0.0
	boat.vx = 0.0
	boat.vy = 0.0
	chart.clock = 1.0
	chart._update_wakes([boat])
	check(chart._wakes.is_empty(), "zero speed does not start a wake")
	boat.vx = 25.0
	chart._update_wakes([boat])
	var key: String = "runner"
	var samples: Array = chart._wakes.get(key, [])
	check(samples.size() == 1, "real speed records one stern sample")
	if samples.size() >= 1:
		var stamp: float = float(samples[0].t)
		var stern: Vector2 = samples[0].p
		check(stern.distance_to(Art.stern_of(boat)) <= 0.001, "the sample is the actual stern")
		chart.clock = 1.2
		boat.vx = 0.0
		chart._update_wakes([boat])
		samples = chart._wakes.get(key, [])
		check(samples.size() == 1 and is_equal_approx(float(samples[0].t), stamp), "stopping does not refresh the old sample")
		chart.clock = 1.3
		boat.vx = 25.0
		boat.angle = 0.7
		chart._update_wakes([boat])
		samples = chart._wakes.get(key, [])
		check(samples.size() == 1 and is_equal_approx(float(samples[0].t), stamp), "turning in place does not churn a wake")
		chart.clock = 1.45
		boat.x = 12.0
		chart._update_wakes([boat])
		samples = chart._wakes.get(key, [])
		check(samples.size() == 2 and Vector2(samples[1].p).distance_to(stern) > 1.0, "travel after the stop appends the new stern")
		chart.clock = 1.55
		boat.sunk = true
		boat.x = 40.0
		boat.vx = 30.0
		chart._update_wakes([boat])
		check(chart._wakes.get(key, []).size() == 2, "a sunk hull does not extend its wake")
		chart.clock = 2.3
		chart._update_wakes([boat])
		check(not chart._wakes.has(key), "old wake samples expire in place")
	var live: Dictionary = hull("hull-1", "gunboat")
	live.x = 160.0
	live.y = 200.0
	live.angle = 0.4
	live.turretAngle = 0.5
	live.mounts = [{"id": "bow", "x": 3.5, "kind": "cannon"}]
	var published: PackedByteArray = var_to_bytes(live)
	var host := HostStub.new()
	var poses := PoseSource.new()
	poses.fraction = 0.5
	poses.poses = {
		"previous": {"hull-1": {"x": 100.0, "y": 200.0, "angle": 0.0, "turretAngle": 0.1}},
		"current": {"hull-1": {"x": 160.0, "y": 200.0, "angle": 0.4, "turretAngle": 0.5}}
	}
	host.battle = {"ships": [live]}
	host.battle_driver051 = poses
	chart.host = host
	chart._prepare_battle_presentation051()
	var visuals: Array = chart._battle_render051.get("ships", [])
	check(var_to_bytes(live) == published and is_same(host.battle.ships[0], live), "pose preparation leaves the published ship untouched")
	check(visuals.size() == 1, "pose preparation publishes one draw copy")
	if visuals.size() == 1:
		var visual: Dictionary = visuals[0]
		check(not is_same(visual, live) and is_equal_approx(float(visual.x), 130.0) and is_equal_approx(float(visual.angle), 0.2) and is_equal_approx(float(visual.hp), float(live.hp)), "the draw copy interpolates pose and keeps published condition")
		visual.x = -500.0
		visual.hp = -1.0
		check(var_to_bytes(live) == published, "edits to the draw copy do not write the live ship")
	chart.free()
