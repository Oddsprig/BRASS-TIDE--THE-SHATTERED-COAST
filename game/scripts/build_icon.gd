extends SceneTree

func _initialize():
	var image = Image.new()
	var svg = FileAccess.get_file_as_string("res://assets/icon.svg")
	var error = image.load_svg_from_string(svg, 8.0)
	if error != OK:
		quit(1)
		return
	error = image.save_png("res://assets/icon.png")
	print("Icon 512×512 created: ", error == OK)
	quit(0 if error == OK else 1)
