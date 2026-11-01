extends "res://tests/test_weapon_presentation045.gd"
## Root-only three-reference selection; public no-lod caller stays unchanged.
func run() -> void:
	if DisplayServer.get_name() != "headless":
		quit(2)
		return
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	manifest = JSON.parse_string(FileAccess.get_file_as_string(Sprite.WEAPON_MANIFEST))
	for id in ["bilge_punt", "brasswind_motor_galleon", "fourport_packet"]:
		var found: Array = world.HULLS.filter(func(h): return str(h.id) == id)
		check(found.size() == 1, "081 reference hull exists: " + id)
		if found.size() != 1:
			continue
		var spec: Dictionary = Refit.effective_spec(found[0], Refit.defaults(found[0]))
		var boat: Dictionary = Art.preview_boat(spec, 0.061)
		var before: Dictionary = boat.duplicate(true)
		check_layers(record(boat), boat, id + " 081 battle")
		var workshop = preview(spec)
		check_layers(workshop, Art.preview_boat(spec, 0.0), id + " 081 workshop")
		check_visible(workshop, id + " 081 workshop")
		check(boat == before, id + " 081 draws preserve complete boat state")
		if id == "brasswind_motor_galleon":
			inspect_draw_preparation(found[0])
			inspect_batch_camera051(found[0])
			inspect_recoil(found[0], "rapid_gun")
		Sprite.clear_cache()
	print("Weapon081: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
