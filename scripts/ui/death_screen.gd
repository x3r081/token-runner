extends Control

func _ready() -> void:
	$Panel/VBox/Message.text = GameManager.get_loading_tip()
	$Panel/VBox/Title.text = "You Died"
	$Panel/VBox/Respawn.text = "Ctrl+Z (Respawn)"
	$Panel/VBox/Menu.text = "Give Up (Main Menu)"
	GameManager.player_died.connect(_set_message)
	$Panel/VBox/Respawn.pressed.connect(_on_respawn)
	$Panel/VBox/Menu.pressed.connect(_on_menu)

func _set_message(msg: String) -> void:
	$Panel/VBox/Message.text = msg

func _on_respawn() -> void:
	GameManager.respawn_player()
	var player := get_tree().get_first_node_in_group("player")
	if player:
		# Respawn on the spot but with i-frames, so the player never re-dies into
		# the same enemies that killed them.
		player.respawn(player.global_position)
		if player.has_method("grant_spawn_grace"):
			player.grant_spawn_grace(2.5)
	queue_free()

func _on_menu() -> void:
	GameManager.return_to_menu()
