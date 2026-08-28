extends SceneTree

func _initialize() -> void:
	var runner := Node.new()
	runner.set_script(load("res://tools/capture_runner.gd"))
	root.add_child(runner)
