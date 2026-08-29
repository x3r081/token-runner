extends Control

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Panel/VBox/Message.text = GameManager.get_loading_tip()
	$Panel/VBox/Title.text = "You Died"
	$Panel/VBox/Respawn.text = "Respawn  [Ctrl+Z / Enter]"
	$Panel/VBox/Menu.text = "Give Up (Main Menu)"
	GameManager.player_died.connect(_set_message)
	$Panel/VBox/Respawn.pressed.connect(_on_respawn)
	$Panel/VBox/Menu.pressed.connect(_on_menu)
	_dress()
	# Focus the button so Enter/Space works, and support the labelled Ctrl+Z key,
	# so respawn is never "click-only" (a lingering overlay could eat a click).
	$Panel/VBox/Respawn.grab_focus()

## Full RED treatment: vignette closing in, overbright pulsing title, staggered
## rows. Death should feel like a production incident, because it is one.
func _dress() -> void:
	var dim: ColorRect = $Dim
	dim.color = Color(0.08, 0.0, 0.01, 0.78)
	dim.modulate.a = 0.0
	var dt := dim.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	dt.tween_property(dim, "modulate:a", 1.0, _GameTheme.T_STD)
	var vig := _GameTheme.make_vignette(_GameTheme.with_alpha(Color(0.35, 0.02, 0.05), 0.9))
	add_child(vig)
	move_child(vig, $Panel.get_index())
	var panel: PanelContainer = $Panel
	panel.add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.RED, 26.0))
	var title: Label = $Panel/VBox/Title
	title.add_theme_color_override("font_color", _GameTheme.RED)
	title.add_theme_font_override("font", _GameTheme.spaced_font(6))
	title.add_theme_font_size_override("font_size", 38)
	var glow := _GameTheme.add_glow_layer(title, 2.3)
	_GameTheme.pulse(glow, 1.4, 2.3, 2.0)
	$Panel/VBox/Message.add_theme_color_override("font_color", _GameTheme.TEXT)
	_GameTheme.style_button($Panel/VBox/Respawn, _GameTheme.RED, 16)
	_GameTheme.style_button($Panel/VBox/Menu, _GameTheme.RED, 14)
	_GameTheme.open_panel(panel)
	_GameTheme.stagger_rows($Panel/VBox)

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
