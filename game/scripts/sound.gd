extends Node

var enabled = true
var voices: Array = []
var bank: Dictionary = {}
var next_voice = 0
var shot_delay = 0.0

func _ready():
	bank["shot"] = make_sound(0.12, 92, 0.48, 0.40, 19)
	bank["boom"] = make_sound(0.72, 44, 0.60, 0.65, 27)
	bank["bell"] = make_sound(0.36, 610, 0.02, 0.13, 42)
	for i in range(7):
		var voice = AudioStreamPlayer.new()
		voice.volume_db = -15
		add_child(voice)
		voices.append(voice)

func _process(dt):
	shot_delay = maxf(0.0, shot_delay - dt)

func make_sound(seconds: float, tone: float, noise_amount: float, volume: float, seed_value: int) -> AudioStreamWAV:
	var rate = 22050
	var samples = int(seconds * rate)
	var bytes = PackedByteArray()
	bytes.resize(samples * 2)
	var random = RandomNumberGenerator.new()
	random.seed = seed_value
	var previous = 0.0
	for i in range(samples):
		var t = float(i) / rate
		var envelope = pow(1.0 - float(i) / samples, 2.4) * minf(1.0, t * 180)
		previous = lerpf(previous, random.randf_range(-1, 1), 0.45)
		var sample = (sin(t * tone * TAU * (1.0 - t * 0.7)) * (1.0 - noise_amount) + previous * noise_amount) * envelope * volume
		bytes.encode_s16(i * 2, int(clampf(sample, -1, 1) * 32767))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream

func play(kind: String):
	if not enabled or voices.is_empty() or not bank.has(kind):
		return
	if kind == "shot":
		if shot_delay > 0:
			return
		shot_delay = 0.10
	var voice: AudioStreamPlayer = voices[next_voice]
	next_voice = (next_voice + 1) % voices.size()
	voice.stream = bank[kind]
	voice.volume_db = -19 if kind == "shot" else -13 if kind == "boom" else -18
	voice.play()
