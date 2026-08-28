extends Control

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
