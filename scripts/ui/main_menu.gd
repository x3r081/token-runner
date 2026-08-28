extends Control

func _ready() -> void:
	AudioManager.play_music("menu_music")
	_apply_theme()
	$VBox/Title.text = "TOKEN RUNNER"
	$VBox/Subtitle.text = "Ship Before Reset"
	$VBox/Version.text = "v1.0 — A strategic adventure about vibe-coding your dream app"
	$VBox/NewGame.text = "New Game"
	$VBox/ContinueBtn.text = "Continue Pretending This Is Fine"
	$VBox/SettingsBtn.text = "Settings Nobody Changes"
	$VBox/QuitBtn.text = "Quit And Touch Grass"
	$VBox/ContinueBtn.visible = SaveManager.has_save()
	$VBox/NewGame.pressed.connect(_on_new_game)
	$VBox/ContinueBtn.pressed.connect(_on_continue)
	$VBox/SettingsBtn.pressed.connect(_on_settings)
	$VBox/QuitBtn.pressed.connect(_on_quit)
	$TipLabel.text = GameManager.get_loading_tip()

func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.04, 0.12, 0.95)
	style.border_color = Color(0.3, 0.9, 0.8, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)

func _on_new_game() -> void:
	AudioManager.play_sfx("ui_click")
	GameManager.start_new_game()

func _on_continue() -> void:
	AudioManager.play_sfx("ui_click")
	GameManager.continue_game()

func _on_settings() -> void:
	AudioManager.play_sfx("ui_click")
	var s := preload("res://scenes/ui/settings_menu.tscn").instantiate()
	add_child(s)

func _on_quit() -> void:
	get_tree().quit()
