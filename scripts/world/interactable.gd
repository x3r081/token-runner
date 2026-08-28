extends Area2D
class_name Interactable

@export var interact_id: String = ""
@export var interact_text: String = "Interact"
@export var one_shot: bool = true

var used := false

func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 8
	collision_mask = 0

func interact(player: Node) -> void:
	if one_shot and used:
		return
	used = true
	QuestManager.on_interact(interact_id)
	_on_interact(player)

func _on_interact(_player: Node) -> void:
	pass

func get_prompt() -> String:
	return interact_text
