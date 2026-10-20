extends SceneTree

func _initialize():
	print("CPU: ", OS.get_processor_name())
	print("Threads: ", OS.get_processor_count())
	print("Memory: ", OS.get_memory_info())
	print("Renderer thread setting: ", ProjectSettings.get_setting("rendering/driver/threads/thread_model"))
	quit(0)
