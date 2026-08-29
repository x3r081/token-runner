extends CanvasLayer
## Dialogue box. The advance button rotates through phrasings that all still
## unambiguously mean "advance", and always carries the key that does it, so the
## joke never costs the player a moment of "wait, how do I continue".

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")

@onready var panel: PanelContainer = $Panel
@onready var speaker_label: Label = $Panel/Margin/VBox/Speaker
@onready var text_label: RichTextLabel = $Panel/Margin/VBox/Text
@onready var choices_box: VBoxContainer = $Panel/Margin/VBox/Choices
@onready var continue_btn: Button = $Panel/Margin/VBox/ContinueBtn

var _reveal_tween: Tween
var _choice_hint: Label

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
	_build_choice_hint()
	DialogueManager.dialogue_line.connect(_on_line)
	DialogueManager.choice_presented.connect(_on_choices)
	DialogueManager.dialogue_ended.connect(_on_ended)
	continue_btn.pressed.connect(_on_continue)
	continue_btn.text = "Continue  [E]"
	panel.visible = false

## A one-line nudge that appears only when a choice is on screen. It never names
## a "correct" option — it just says out loud that this is a decision.
func _build_choice_hint() -> void:
	_choice_hint = Label.new()
	_choice_hint.name = "ChoiceHint"
	_choice_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choice_hint.add_theme_font_size_override("font_size", 12)
	_choice_hint.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	_choice_hint.visible = false
	var vbox: VBoxContainer = $Panel/Margin/VBox
	vbox.add_child(_choice_hint)
	vbox.move_child(_choice_hint, choices_box.get_index())

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
	if is_instance_valid(_choice_hint):
		_choice_hint.visible = false
	continue_btn.visible = true
	# Rotate the phrasing, keep the key. Every variant reads as "go on".
	continue_btn.text = "%s  [E]" % _Comedy.pick("dlg_continue", _Comedy.DIALOGUE_CONTINUE)
	for c in choices_box.get_children():
		c.queue_free()

func _on_choices(choices: Array) -> void:
	choices_box.visible = true
	continue_btn.visible = false
	if is_instance_valid(_choice_hint):
		_choice_hint.text = _Comedy.pick("dlg_choice_hint", _Comedy.DIALOGUE_CHOICE_HINT)
		_choice_hint.visible = true
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
	if is_instance_valid(_choice_hint):
		_choice_hint.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return
	if not (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")):
		return
	if choices_box.visible:
		return
	_on_continue()
	get_viewport().set_input_as_handled()
