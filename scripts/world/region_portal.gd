extends Area2D

@export var target_region: String = "localhost"
@export var portal_label: String = "Portal"

@onready var label: Label = $Label

func _ready() -> void:
	add_to_group("interactable")
	label.text = "→ %s" % portal_label
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if not GameManager.is_region_unlocked(target_region):
		return
	GameManager.change_region(target_region)

func interact(_player: Node) -> void:
	if GameManager.is_region_unlocked(target_region):
		GameManager.change_region(target_region)
