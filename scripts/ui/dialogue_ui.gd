extends CanvasLayer
## Dialogue box. The advance button rotates through phrasings that all still
## unambiguously mean "advance", and always carries the key that does it, so the
## joke never costs the player a moment of "wait, how do I continue".
##
## Round 6 stripped the costume off the most-read surface in the game. Gone: the
## cyan accent chip around the speaker's name, the "YOU" chip mirroring it, the
## accent bar-gradient rule across the panel, the accent quote-rule down the left
## of the speech, the filled RAISED "cards" behind the choices, the panel's cyan
## border and its outer glow, and the choice cascade. What is left: a name, a
## line, and up to three bordered rows.
##
## The panel is still anchored to the BOTTOM edge and grows UPWARD (a prior fix).
## Do not re-anchor it: with `fit_content` on the text, a top-anchored panel puts
## long NPC briefings under the ability bar.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")
const _Modal = preload("res://scripts/ui/modal_panel.gd")

## Body copy is inset from the panel's right edge, in panel units — NOT a
## character count, despite the coincidence of the number. The panel is 900 units
## wide because three choice buttons need the room; prose does not. Full width at
## the body font ran ~100 characters a line, which is past where a reader starts
## losing which line they were on; this brings the measure to ~80.
##
## It is load-bearing for height, not just taste: every 10 units taken off the
## measure can push a long NPC briefing onto another line, and the panel grows
## UPWARD from its anchored bottom edge. Re-check the tallest frame if you move
## it — the longest line in data/dialogue/npcs.json is 278 characters.
const TEXT_RIGHT_INSET := 110.0

@onready var panel: PanelContainer = $Panel
@onready var speaker_label: Label = $Panel/Margin/VBox/Speaker
@onready var text_label: RichTextLabel = $Panel/Margin/VBox/Text
@onready var choices_box: VBoxContainer = $Panel/Margin/VBox/Choices
@onready var continue_btn: Button = $Panel/Margin/VBox/ContinueBtn

var _reveal_tween: Tween
var _choice_hint: Label
var _choice_header: HBoxContainer
var _choice_rule: Panel

func _ready() -> void:
	layer = 20
	# Wiring first, cosmetics second — deliberately, and please keep it that way.
	# The styling below is the only part of this function that can plausibly fail
	# on an engine change (a renamed theme item, a property that moved), and a
	# _ready() that dies halfway is a build with NO dialogue at all rather than an
	# ugly one. See HANDOVER.md section 4, gotcha 6b.
	DialogueManager.dialogue_line.connect(_on_line)
	DialogueManager.choice_presented.connect(_on_choices)
	DialogueManager.dialogue_ended.connect(_on_ended)
	continue_btn.pressed.connect(_on_continue)
	continue_btn.text = "Continue  [E]"
	panel.visible = false

	panel.theme = _GameTheme.create()
	panel.add_theme_stylebox_override("panel", _dialogue_panel_box())
	# The speaker is a name, not a badge: ACCENT, small, on the panel itself.
	speaker_label.add_theme_color_override("font_color", _GameTheme.CYAN)
	speaker_label.add_theme_font_size_override("font_size", _Modal.SMALL)
	speaker_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var vbox: VBoxContainer = $Panel/Margin/VBox
	vbox.add_theme_constant_override("separation", 12)
	_style_speech()
	choices_box.add_theme_constant_override("separation", 6)
	_GameTheme.style_button(continue_btn, _GameTheme.TEXT_DIM, _Modal.SMALL)
	_build_choice_hint()

## Opaque body, one hairline border, nothing else. Fully opaque rather than the
## modal kit's 96%: this panel sits over the LIVE world with no scrim, and at 92%
## world captions (COUCH, PIZZA ARCHAEOLOGY, node_modules) used to read straight
## through the dialogue line.
func _dialogue_panel_box() -> StyleBoxFlat:
	var s := _Modal.modal_box(_GameTheme.CYAN, 18.0)
	s.bg_color = _GameTheme.BASE
	return s

## What they said: body copy at a comfortable measure with open line spacing. No
## fill, no accent rule — the accent is the name above it.
func _style_speech() -> void:
	var inset := StyleBoxFlat.new()
	inset.draw_center = false
	inset.content_margin_left = 2.0
	inset.content_margin_right = TEXT_RIGHT_INSET
	inset.content_margin_top = 2.0
	inset.content_margin_bottom = 8.0
	text_label.add_theme_stylebox_override("normal", inset)
	text_label.add_theme_color_override("default_color", _GameTheme.TEXT)
	text_label.add_theme_font_size_override("normal_font_size", _Modal.BODY)
	text_label.add_theme_constant_override("line_separation", 6)
	# Shape the WHOLE line, then clip the reveal to it. Godot's default
	# (VC_CHARS_BEFORE_SHAPING) drops the not-yet-revealed characters before
	# wrapping, so with `fit_content` the label's height grows line by line as the
	# typewriter runs. The panel is bottom-anchored and grows upward, which turns
	# that into the speaker name and the sentence you are reading crawling up the
	# screen mid-word. Shaping first pins the box at its final height on frame one.
	text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	# A two-line floor: the panel stops resizing under every short reply, without
	# reserving the dead band the old 80px minimum left above the button.
	text_label.custom_minimum_size = Vector2(0, 66)

## The choice header: a 1px LINE rule and a one-line nudge in TEXT_DIM. The rule
## used to be a 2px accent bar-gradient and the nudge used to sit next to a "YOU"
## chip; between them they made the options look like a second panel.
func _build_choice_hint() -> void:
	var vbox: VBoxContainer = $Panel/Margin/VBox

	_choice_rule = Panel.new()
	_choice_rule.name = "ChoiceRule"
	_choice_rule.custom_minimum_size = Vector2(0, 1)
	_choice_rule.add_theme_stylebox_override("panel", _Modal.rule())
	_choice_rule.visible = false
	vbox.add_child(_choice_rule)
	vbox.move_child(_choice_rule, choices_box.get_index())

	_choice_header = HBoxContainer.new()
	_choice_header.name = "ChoiceHeader"
	_choice_header.visible = false
	vbox.add_child(_choice_header)
	vbox.move_child(_choice_header, choices_box.get_index())

	_choice_hint = Label.new()
	_choice_hint.name = "ChoiceHint"
	_choice_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choice_hint.add_theme_font_size_override("font_size", _Modal.SMALL)
	_choice_hint.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	_choice_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_header.add_child(_choice_hint)

## One switch for the whole "your turn" block, so the rule and the nudge can
## never disagree about whether a choice is on screen.
func _set_choice_header_visible(v: bool) -> void:
	if is_instance_valid(_choice_rule):
		_choice_rule.visible = v
	if is_instance_valid(_choice_header):
		_choice_header.visible = v

func _on_line(_npc_id: String, speaker: String, text: String) -> void:
	if not panel.visible:
		panel.visible = true
		_GameTheme.open_panel(panel)
	speaker_label.text = speaker
	text_label.text = text
	AudioManager.play_sfx("dialogue_blip")
	# Typewriter reveal — pressing continue mid-reveal skips to the full line.
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()
	text_label.visible_ratio = 0.0
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(text_label, "visible_ratio", 1.0,
		clampf(text.length() * 0.012, 0.15, 0.9))
	choices_box.visible = false
	_set_choice_header_visible(false)
	continue_btn.visible = true
	# Rotate the phrasing, keep the key. Every variant reads as "go on".
	continue_btn.text = "%s  [E]" % _Comedy.pick("dlg_continue", _Comedy.DIALOGUE_CONTINUE)
	_clear_choices()

## Empty the option stack. `remove_child` BEFORE `queue_free`: a queued-free node
## is still a child — and still laid out — for the rest of the frame, so a block
## that replaces three options with three options would size the panel around six
## of them for one frame. That was survivable when the panel was short; with the
## taller choice block it is a visible height pop, and it also means
## `get_child(0)` can hand back a corpse.
func _clear_choices() -> void:
	for c in choices_box.get_children():
		choices_box.remove_child(c)
		c.queue_free()

func _on_choices(choices: Array) -> void:
	choices_box.visible = true
	continue_btn.visible = false
	if is_instance_valid(_choice_hint):
		_choice_hint.text = _Comedy.pick("dlg_choice_hint", _Comedy.DIALOGUE_CHOICE_HINT)
	_set_choice_header_visible(true)
	_clear_choices()
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var btn := Button.new()
		btn.text = choice.get("text", "...")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_style_choice_button(btn)
		var idx := i
		btn.pressed.connect(func():
			AudioManager.play_sfx("choice_select")
			DialogueManager.select_choice(idx))
		choices_box.add_child(btn)
	# [E] deliberately does nothing while options are up — you have to pick one —
	# so without focus here a keyboard/controller player has no way to answer at
	# all. The ring is also the cheapest possible "these are the buttons".
	if choices_box.get_child_count() > 0:
		var first := choices_box.get_child(0) as Button
		if first != null:
			first.grab_focus()

## What you can say: plain bordered rows with generous hit padding. They read as
## options because they have edges and the speech does not — not because they are
## filled, raised and lit.
func _style_choice_button(btn: Button) -> void:
	_GameTheme.style_button(btn, _GameTheme.CYAN, _Modal.BODY)
	var boxes := _GameTheme.button_boxes(_GameTheme.CYAN)
	for state: String in ["normal", "hover", "pressed"]:
		var box: StyleBoxFlat = boxes[state]
		box.set_corner_radius_all(2)
		box.content_margin_left = 16.0
		box.content_margin_right = 16.0
		box.content_margin_top = 9.0
		box.content_margin_bottom = 9.0
		btn.add_theme_stylebox_override(state, box)

func _on_continue() -> void:
	# First press completes the reveal; second one advances. Standard courtesy.
	if _reveal_tween and _reveal_tween.is_valid() and text_label.visible_ratio < 1.0:
		_reveal_tween.kill()
		text_label.visible_ratio = 1.0
		return
	DialogueManager.advance()

func _on_ended(_npc_id: String) -> void:
	panel.visible = false
	_set_choice_header_visible(false)

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return
	if not (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")):
		return
	if choices_box.visible:
		return
	_on_continue()
	get_viewport().set_input_as_handled()
