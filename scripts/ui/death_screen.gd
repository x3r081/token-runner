extends Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Panel/VBox/Message.text = GameManager.get_loading_tip()
	$Panel/VBox/Title.text = "You Died"
	$Panel/VBox/Respawn.text = "Respawn  [Ctrl+Z / Enter]"
	$Panel/VBox/Menu.text = "Give Up (Main Menu)"
	GameManager.player_died.connect(_set_message)
	$Panel/VBox/Respawn.pressed.connect(_on_respawn)
	$Panel/VBox/Menu.pressed.connect(_on_menu)
	# Focus the button so Enter/Space works, and support the labelled Ctrl+Z key,
	# so respawn is never "click-only" (a lingering overlay could eat a click).
	$Panel/VBox/Respawn.grab_focus()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_respawn()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_Z and event.ctrl_pressed:
		get_viewport().set_input_as_handled()
		_on_respawn()

func _set_message(msg: String) -> void:
	$Panel/VBox/Message.text = msg

func _on_respawn() -> void:
	GameManager.respawn_player()
	var player := get_tree().get_first_node_in_group("player")
	if player:
		# Respawn at the region's safe spawn point (never back in the enemy pile
		# that killed us) with i-frames so the player can regroup.
		var safe: Vector2 = GameManager.region_spawn if GameManager.region_spawn != Vector2.ZERO else player.global_position
		player.respawn(safe)
		if player.has_method("grant_spawn_grace"):
			player.grant_spawn_grace(3.0)
	# Send any chasing enemies back to their posts so the respawn isn't a re-swarm.
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("reset_to_home"):
			e.reset_to_home()
	queue_free()

func _on_menu() -> void:
	GameManager.return_to_menu()
