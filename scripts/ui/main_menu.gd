extends Control

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

func _ready() -> void:
	var theme := _GameTheme.create()
	$CenterPanel.theme = theme
	$CenterPanel/VBox/Title.text = "TOKEN RUNNER"
	$CenterPanel/VBox/Subtitle.text = "Ship Before Reset"
	$CenterPanel/VBox/Version.text = "v1.1-dev — Localhost rebuild"
	$CenterPanel/VBox/NewGame.text = "New Game"
	$CenterPanel/VBox/ContinueBtn.text = "Continue Pretending This Is Fine"
	$CenterPanel/VBox/SettingsBtn.text = "Settings Nobody Changes"
	$CenterPanel/VBox/QuitBtn.text = "Quit And Touch Grass"
	$CenterPanel/VBox/ContinueBtn.visible = SaveManager.has_save()
	$CenterPanel/VBox/NewGame.pressed.connect(_on_new_game)
	$CenterPanel/VBox/ContinueBtn.pressed.connect(_on_continue)
	$CenterPanel/VBox/SettingsBtn.pressed.connect(_on_settings)
	$CenterPanel/VBox/QuitBtn.pressed.connect(_on_quit)
	$TipLabel.text = GameManager.get_loading_tip()

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
