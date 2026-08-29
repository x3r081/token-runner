extends CanvasLayer

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

@onready var panel: PanelContainer = $Panel
@onready var speaker_label: Label = $Panel/Margin/VBox/Speaker
@onready var text_label: RichTextLabel = $Panel/Margin/VBox/Text
@onready var choices_box: VBoxContainer = $Panel/Margin/VBox/Choices
@onready var continue_btn: Button = $Panel/Margin/VBox/ContinueBtn

var _reveal_tween: Tween

func _ready() -> void:
	layer = 20
	panel.theme = _GameTheme.create()
	panel.add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.CYAN, 18.0))
	# Speaker name as an accent chip, hugging its text.
	speaker_label.add_theme_stylebox_override("normal", _GameTheme.chip_box(_GameTheme.CYAN))
	speaker_label.add_theme_color_override("font_color", _GameTheme.hot_of(_GameTheme.CYAN))
	speaker_label.add_theme_font_override("font", _GameTheme.spaced_font(2))
	speaker_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	text_label.add_theme_color_override("default_color", _GameTheme.TEXT)
	_GameTheme.style_button(continue_btn, _GameTheme.CYAN, 15)
	DialogueManager.dialogue_line.connect(_on_line)
	DialogueManager.choice_presented.connect(_on_choices)
	DialogueManager.dialogue_ended.connect(_on_ended)
	continue_btn.pressed.connect(_on_continue)
	continue_btn.text = "Continue"
	panel.visible = false

func _on_line(_npc_id: String, speaker: String, text: String) -> void:
	if not panel.visible:
		panel.visible = true
		_GameTheme.open_panel(panel)
	speaker_label.text = speaker
	text_label.text = text
	# Typewriter reveal — pressing continue mid-reveal skips to the full line.
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()
	text_label.visible_ratio = 0.0
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(text_label, "visible_ratio", 1.0,
		clampf(text.length() * 0.012, 0.15, 0.9))
	choices_box.visible = false
	continue_btn.visible = true
	for c in choices_box.get_children():
		c.queue_free()

func _on_choices(choices: Array) -> void:
	choices_box.visible = true
	continue_btn.visible = false
	for c in choices_box.get_children():
		c.queue_free()
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var btn := Button.new()
		btn.text = choice.get("text", "...")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_GameTheme.style_button(btn, _GameTheme.CYAN, 15)
		var idx := i
		btn.pressed.connect(func(): DialogueManager.select_choice(idx))
		choices_box.add_child(btn)
	_GameTheme.stagger_rows(choices_box, 0.05, 0.0)

func _on_continue() -> void:
	# First press completes the reveal; second one advances. Standard courtesy.
	if _reveal_tween and _reveal_tween.is_valid() and text_label.visible_ratio < 1.0:
		_reveal_tween.kill()
		text_label.visible_ratio = 1.0
		return
	DialogueManager.advance()

func _on_ended(_npc_id: String) -> void:
	panel.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return
	if not (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")):
		return
	if choices_box.visible:
		return
	_on_continue()
	get_viewport().set_input_as_handled()
