extends SceneTree

func _initialize() -> void:
	var gen := preload("res://scripts/tools/asset_generator_runtime.gd").new()
	gen.generate_all()
	# Audio generators (AUDIO_BIBLE.md). exists()-guarded so this script runs
	# at every intermediate state of the round.
	for path: String in [
		"res://scripts/tools/music_generator.gd",
		"res://scripts/tools/sfx_generator.gd",
	]:
		if ResourceLoader.exists(path):
			var g = load(path).new()
			if g.has_method("generate_all"):
				g.generate_all()
	quit()
