extends SceneTree

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var runner := Node.new()
	runner.set_script(load("res://tools/capture_runner.gd"))
	root.add_child(runner)
