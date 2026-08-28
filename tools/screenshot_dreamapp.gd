extends Node

func _ready() -> void:
	GameManager.show_opening_sequence = false
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")
	await get_tree().create_timer(1.5).timeout
	var world := get_tree().current_scene
	if world and world.has_method("_toggle_dream_app"):
		world._toggle_dream_app()
