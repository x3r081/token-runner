extends Control
## Pause is the one screen a lost player always finds, so it does double duty:
## a rotating joke about nothing running, and — right under it — exactly what
## you were doing, where, and which key does what.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")

const CONTROLS_LINE := "WASD move · E interact/talk · 1 Prompt Blast · Shift/Q dash · 2-5 abilities · B Dream App · M map · J quests · T model · Esc resume"

var _reminder: Label

func _ready() -> void:
	get_tree().paused = true
	$Panel/VBox/Title.text = "Paused"
	$Panel/VBox/Subtitle.text = _Comedy.pick("pause", _Comedy.PAUSE)
	$Panel/VBox/Resume.text = "Resume Vibe Coding  [Esc]"
	$Panel/VBox/Resume.tooltip_text = "Unfreezes the world. The world was not enjoying the break either."
	$Panel/VBox/Save.text = "Save Progress (For Real This Time)"
	$Panel/VBox/Save.tooltip_text = "Writes your run to disk. Autosave already runs on region change; this is the belt to its braces."
	$Panel/VBox/Settings.text = "Settings Nobody Changes"
	$Panel/VBox/Settings.tooltip_text = "Volume, fullscreen, camera shake. Everything in there does what it says."
	$Panel/VBox/Menu.text = "Abandon Ship (Main Menu)"
	$Panel/VBox/Menu.tooltip_text = "Back to the title screen. Your progress is saved on the way out."
	_build_reminder()
	$Panel/VBox/Resume.pressed.connect(_on_resume)
	$Panel/VBox/Save.pressed.connect(_on_save)
	$Panel/VBox/Settings.pressed.connect(_on_settings)
	$Panel/VBox/Menu.pressed.connect(_on_menu)
	_dress()

## "What was I doing?" answered before it's asked: where you are, what the game
## wants next, and the full key list. The comedy sits in the framing, never in
## the facts.
func _build_reminder() -> void:
	_reminder = Label.new()
	_reminder.name = "Reminder"
	_reminder.text = _reminder_text()
	_reminder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reminder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reminder.add_theme_font_size_override("font_size", 13)
	var vbox: VBoxContainer = $Panel/VBox
	vbox.add_child(_reminder)
	vbox.move_child(_reminder, 2)  # under the subtitle, above the buttons

func _reminder_text() -> String:
	var region_id: String = GameManager.current_region
	var region: String = region_id.replace("_", " ").capitalize()
	var lines: Array[String] = []
	lines.append("WHILE YOU ARE HERE")
	lines.append("You are in %s — %s" % [region, _Comedy.region_subtitle(region_id)])
	var obj: Dictionary = QuestManager.get_current_objective() if QuestManager else {}
	if obj.is_empty():
		lines.append("Next: nothing tracked. Talk to Claude at the desk in Localhost — that is where the work comes from.")
	else:
		var where := String(obj.get("region", region_id)).replace("_", " ").capitalize()
		lines.append("Next: %s — %s (in %s)" % [obj.get("quest_name", "Quest"), obj.get("action", "…"), where])
		lines.append("Goal: buy Dream App upgrades [B] until the ship requirements are met, then Deploy in Localhost.")
	lines.append(CONTROLS_LINE)
	return "\n".join(lines)

func _dress() -> void:
	var dim: ColorRect = $Dim
	dim.modulate.a = 0.0
	var dt := dim.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	dt.tween_property(dim, "modulate:a", 1.0, _GameTheme.T_STD)
	var panel: PanelContainer = $Panel
	# The reminder block needs room the original 400x360 rect never had.
	panel.offset_left = -340.0
	panel.offset_right = 340.0
	panel.offset_top = -260.0
	panel.offset_bottom = 260.0
	panel.add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.CYAN, 24.0))
	_GameTheme.add_sheen(panel)
	var title: Label = $Panel/VBox/Title
	_GameTheme.style_heading(title, _GameTheme.CYAN, 28)
	var glow := _GameTheme.add_glow_layer(title, 2.0)
	_GameTheme.pulse(glow, 1.3, 2.0, 2.8)
	$Panel/VBox/Subtitle.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	if is_instance_valid(_reminder):
		_reminder.add_theme_color_override("font_color", _GameTheme.with_alpha(_GameTheme.AMBER, 0.9))
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
	$Panel/VBox/Subtitle.text = _Comedy.pick("pause_saved", _Comedy.PAUSE_SAVED)

func _on_settings() -> void:
	var s := preload("res://scenes/ui/settings_menu.tscn").instantiate()
	add_child(s)

func _on_menu() -> void:
	GameManager.return_to_menu()
