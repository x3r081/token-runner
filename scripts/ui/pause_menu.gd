extends Control

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

func _ready() -> void:
	get_tree().paused = true
	$Panel/VBox/Title.text = "Paused"
	$Panel/VBox/Subtitle.text = "Production is fine. Probably."
	$Panel/VBox/Resume.text = "Resume Vibe Coding"
	$Panel/VBox/Save.text = "Save Progress (For Real This Time)"
	$Panel/VBox/Settings.text = "Settings Nobody Changes"
	$Panel/VBox/Menu.text = "Abandon Ship (Main Menu)"
	$Panel/VBox/Resume.pressed.connect(_on_resume)
	$Panel/VBox/Save.pressed.connect(_on_save)
	$Panel/VBox/Settings.pressed.connect(_on_settings)
	$Panel/VBox/Menu.pressed.connect(_on_menu)
	_dress()

func _dress() -> void:
	var dim: ColorRect = $Dim
	dim.modulate.a = 0.0
	var dt := dim.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	dt.tween_property(dim, "modulate:a", 1.0, _GameTheme.T_STD)
	var panel: PanelContainer = $Panel
	panel.add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.CYAN, 24.0))
	_GameTheme.add_sheen(panel)
	var title: Label = $Panel/VBox/Title
	_GameTheme.style_heading(title, _GameTheme.CYAN, 28)
	var glow := _GameTheme.add_glow_layer(title, 2.0)
	_GameTheme.pulse(glow, 1.3, 2.0, 2.8)
	$Panel/VBox/Subtitle.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	for b: Button in [$Panel/VBox/Resume, $Panel/VBox/Save, $Panel/VBox/Settings, $Panel/VBox/Menu]:
		b.custom_minimum_size = Vector2(0, 42)
		_GameTheme.style_button(b, _GameTheme.CYAN, 16)
	_GameTheme.open_panel(panel)
	_GameTheme.stagger_rows($Panel/VBox)

func _input(event: InputEvent) -> void:
	# The menu processes while paused (process_mode = ALWAYS), so it owns the
	# Escape-to-resume toggle.
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_on_resume()
		get_viewport().set_input_as_handled()

func _on_resume() -> void:
	GameManager.pause_game(false)
	queue_free()

func _on_save() -> void:
	SaveManager.save_game()
	$Panel/VBox/Subtitle.text = "Saved. Unlike your last backup."

func _on_settings() -> void:
	var s := preload("res://scenes/ui/settings_menu.tscn").instantiate()
	add_child(s)

func _on_menu() -> void:
	GameManager.return_to_menu()
