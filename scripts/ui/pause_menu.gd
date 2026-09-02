extends Control
## Pause is the one screen a lost player always finds, so it answers "what was I
## doing" before it is asked: where you are, what the game wants next, and the
## key list. One joke, in the subtitle.
##
## Round 6 removed the glow layer on the title, its breathing pulse, the moving
## sheen over the panel, the row cascade, the amber reminder block, and a third
## of the words.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")
const _Modal = preload("res://scripts/ui/modal_panel.gd")

const CONTROLS_LINE := "WASD move · [E] interact · [1] blast · [Shift] dash · [B] Dream App · [M] map · [J] quests · [H] help"

var _reminder: Label

func _ready() -> void:
	get_tree().paused = true
	$Panel/VBox/Title.text = "Paused"
	$Panel/VBox/Subtitle.text = _Comedy.pick("pause", _Comedy.PAUSE)
	$Panel/VBox/Resume.text = "Resume  [Esc]"
	$Panel/VBox/Resume.tooltip_text = "Unfreezes the world. The world was not enjoying the break either."
	$Panel/VBox/Save.text = "Save"
	$Panel/VBox/Save.tooltip_text = "Writes your run to disk. Autosave already runs on region change; this is the belt to its braces."
	$Panel/VBox/Settings.text = "Settings"
	$Panel/VBox/Settings.tooltip_text = "Volume, fullscreen, camera shake. Everything in there does what it says."
	$Panel/VBox/Menu.text = "Main Menu"
	$Panel/VBox/Menu.tooltip_text = "Back to the title screen. Your progress is saved on the way out."
	_build_reminder()
	$Panel/VBox/Resume.pressed.connect(_on_resume)
	$Panel/VBox/Save.pressed.connect(_on_save)
	$Panel/VBox/Settings.pressed.connect(_on_settings)
	$Panel/VBox/Menu.pressed.connect(_on_menu)
	_dress()

## Where you are, what is next, and the keys. Three lines, not six.
func _build_reminder() -> void:
	_reminder = Label.new()
	_reminder.name = "Reminder"
	_reminder.text = _reminder_text()
	_reminder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reminder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reminder.add_theme_font_size_override("font_size", _Modal.SMALL)
	var vbox: VBoxContainer = $Panel/VBox
	vbox.add_child(_reminder)
	vbox.move_child(_reminder, 2)  # under the subtitle, above the buttons

func _reminder_text() -> String:
	var region_id: String = GameManager.current_region
	var region: String = region_id.replace("_", " ").capitalize()
	var lines: Array[String] = []
	lines.append("You are in %s." % region)
	var obj: Dictionary = QuestManager.get_current_objective() if QuestManager else {}
	if obj.is_empty():
		lines.append("Next: talk to Claude at the desk in Localhost.")
	else:
		var where := String(obj.get("region", region_id)).replace("_", " ").capitalize()
		lines.append("Next: %s (in %s)" % [obj.get("action", "…"), where])
	lines.append(CONTROLS_LINE)
	return "\n".join(lines)

func _dress() -> void:
	var dim: ColorRect = $Dim
	dim.modulate.a = 1.0
	var panel: PanelContainer = $Panel
	panel.offset_left = -320.0
	panel.offset_right = 320.0
	panel.offset_top = -230.0
	panel.offset_bottom = 230.0
	panel.theme = _GameTheme.create()
	panel.add_theme_stylebox_override("panel", _Modal.modal_box(_GameTheme.CYAN, 26.0))
	var title: Label = $Panel/VBox/Title
	title.add_theme_font_size_override("font_size", _Modal.HEADING)
	title.add_theme_color_override("font_color", _GameTheme.CYAN)
	var subtitle: Label = $Panel/VBox/Subtitle
	subtitle.add_theme_font_size_override("font_size", _Modal.SMALL)
	subtitle.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	if is_instance_valid(_reminder):
		_reminder.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	# One ACCENT: the button you came here to press.
	_GameTheme.style_button($Panel/VBox/Resume, _GameTheme.CYAN, _Modal.BODY)
	for b: Button in [$Panel/VBox/Save, $Panel/VBox/Settings, $Panel/VBox/Menu]:
		_GameTheme.style_button(b, _GameTheme.TEXT_DIM, _Modal.BODY)
	for b: Button in [$Panel/VBox/Resume, $Panel/VBox/Save, $Panel/VBox/Settings,
			$Panel/VBox/Menu]:
		b.custom_minimum_size = Vector2(0, 42)
	_GameTheme.open_panel(panel)

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
	$Panel/VBox/Subtitle.text = _Comedy.pick("pause_saved", _Comedy.PAUSE_SAVED)

func _on_settings() -> void:
	var s := preload("res://scenes/ui/settings_menu.tscn").instantiate()
	add_child(s)

func _on_menu() -> void:
	GameManager.return_to_menu()
