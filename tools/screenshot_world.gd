extends Node

func _ready() -> void:
	GameManager.show_opening_sequence = false
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")
