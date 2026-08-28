extends SceneTree

func _initialize() -> void:
	var gen := preload("res://scripts/tools/asset_generator_runtime.gd").new()
	gen.generate_all()
	quit()
