extends SceneTree
## Development-only: extract notices from the exact installed engine used to export.
func _initialize():
	var folder: String = ProjectSettings.globalize_path("res://../docs/legal")
	DirAccess.make_dir_recursive_absolute(folder)
	var file = FileAccess.open(folder.path_join("GODOT LICENSE.txt"),FileAccess.WRITE)
	file.store_string(Engine.get_license_text())
	file.close()
	var copyrights = FileAccess.open(folder.path_join("GODOT COMPONENTS.json"),FileAccess.WRITE)
	copyrights.store_string(JSON.stringify(Engine.get_copyright_info(),"\t"))
	copyrights.close()
	var names: PackedStringArray = []
	for name in Engine.get_license_info():
		var safe_name: String = str(name).validate_filename()
		var notice = FileAccess.open(folder.path_join(safe_name+".txt"),FileAccess.WRITE)
		notice.store_string(str(Engine.get_license_info()[name]))
		notice.close()
		names.append(str(name))
	var index = FileAccess.open(folder.path_join("READ ME.txt"),FileAccess.WRITE)
	index.store_string("Notices extracted from Godot "+Engine.get_version_info().string+".\nGODOT LICENSE.txt: engine MIT license.\nGODOT COMPONENTS.json: each third-party component, its copyright and applicable license.\nOther .txt files: complete corresponding license texts.\nGodot source: https://github.com/godotengine/godot\nCompliance guidance: https://docs.godotengine.org/en/stable/about/complying_with_licenses.html\n\nLicenses: "+", ".join(names)+"\n")
	index.close()
	print("Notices extracted: ",names.size()," license texts")
	quit()
