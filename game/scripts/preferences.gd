extends RefCounted
## Portable presentation options. Separate from every voyage and fleet purse.
static func defaults() -> Dictionary:
	return {"audio_enabled":true,"weapon_volume":0.85,"ambience_volume":0.35,"music_enabled":true,"music_volume":0.55,"fullscreen":false,"frame_cap":120,"dev_enabled":false}

static func sanitize(raw) -> Dictionary:
	var result: Dictionary=defaults()
	if not raw is Dictionary:return result
	for key in ["audio_enabled","music_enabled","fullscreen","dev_enabled"]:
		if raw.get(key) is bool:result[key]=raw[key]
	for key in ["weapon_volume","ambience_volume","music_volume"]:
		var value=raw.get(key)
		if (value is float or value is int) and is_finite(float(value)):result[key]=clampf(float(value),0.0,1.0)
	if raw.get("frame_cap") in [60,120]:result.frame_cap=int(raw.frame_cap)
	return result

static func load_options(path: String) -> Dictionary:
	var file=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>65536:return defaults()
	return sanitize(JSON.parse_string(file.get_as_text()))

static func save_options(path: String,options: Dictionary) -> bool:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir())!=OK:return false
	var file=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(sanitize(options),"\t"));file.close()
	return true
