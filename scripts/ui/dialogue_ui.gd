extends CanvasLayer
## Dialogue box. The advance button rotates through phrasings that all still
## unambiguously mean "advance", and always carries the key that does it, so the
## joke never costs the player a moment of "wait, how do I continue".
##
## Round 5 — readability. This is the surface the player READS most, so it is the
## one place in the UI that gives up glass for opacity:
##
## 1. The body is OPAQUE. At the shared 92% panel alpha, world captions (COUCH,
##    PIZZA ARCHAEOLOGY, node_modules) showed straight through the speaker chip
##    and the dialogue line. The neon now lives in the border and the outer glow,
##    where it costs nothing to read.
## 2. The panel reads as two halves: what THEY said (accent quote-rule, no fill)
##    and what YOU can say (a "YOU" chip that mirrors the speaker chip, an accent
##    rule across the panel, then filled, raised choice cards). A player glancing
##    for a second can tell speech from options without reading either.
## 3. Measure and rhythm: body copy is inset from the right edge so a line is
##    ~80 characters instead of the panel's full width, line spacing is opened
##    up, and every block is separated by a real gap — the choice hint used to
##    sit welded to the first button.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")

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
	# Speaker name as an accent chip, hugging its text.
	speaker_label.add_theme_stylebox_override("normal", _GameTheme.chip_box(_GameTheme.CYAN))
	speaker_label.add_theme_color_override("font_color", _GameTheme.hot_of(_GameTheme.CYAN))
	speaker_label.add_theme_font_override("font", _GameTheme.spaced_font(2))
	speaker_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Air between chip / speech / hint / choices / advance. The scene's default 4px
	# is what made the hint look welded to the first choice button.
	var vbox: VBoxContainer = $Panel/Margin/VBox
	vbox.add_theme_constant_override("separation", 12)
	_style_speech()
	choices_box.add_theme_constant_override("separation", 8)
	_GameTheme.style_button(continue_btn, _GameTheme.CYAN, 15)
	_build_choice_hint()

## Opaque body, neon edge. Everything the shared panel_box does for glow is kept;
## only the transparency — which the world was reading through — is dropped.
func _dialogue_panel_box() -> StyleBoxFlat:
	var s := _GameTheme.panel_box(_GameTheme.CYAN, 18.0)
	s.bg_color = _GameTheme.BASE
	s.border_color = _GameTheme.with_alpha(_GameTheme.CYAN, 0.45)
	s.set_corner_radius_all(8)
	s.shadow_color = _GameTheme.with_alpha(_GameTheme.CYAN, 0.20)
	s.shadow_size = 20
	return s

## "This is what they said": an accent quote-rule down the left, a comfortable
## measure, and open line spacing. No fill — the fill belongs to your options.
func _style_speech() -> void:
	var quote := StyleBoxFlat.new()
	quote.draw_center = false
	quote.border_color = _GameTheme.with_alpha(_GameTheme.CYAN, 0.38)
	quote.border_width_left = 2
	quote.content_margin_left = 14.0
	quote.content_margin_right = TEXT_RIGHT_INSET
	quote.content_margin_top = 4.0
	quote.content_margin_bottom = 10.0
	text_label.add_theme_stylebox_override("normal", quote)
	text_label.add_theme_color_override("default_color", _GameTheme.TEXT)
	text_label.add_theme_font_size_override("normal_font_size", 18)
	text_label.add_theme_constant_override("line_separation", 6)
	# Shape the WHOLE line, then clip the reveal to it. Godot's default
	# (VC_CHARS_BEFORE_SHAPING) drops the not-yet-revealed characters before
	# wrapping, so with `fit_content` the label's height grows line by line as the
	# typewriter runs. The panel is bottom-anchored and grows upward, which turns
	# that into the speaker chip and the sentence you are reading crawling up the
	# screen mid-word. Harmless at the old ~100-character measure (nothing in
	# data/dialogue/npcs.json reached four lines); at this measure the long NPC
	# briefings do. Shaping first pins the box at its final height on frame one.
	text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	# A two-line floor: the panel stops resizing under every short reply, without
	# reserving the dead band the old 80px minimum left above the button.
	text_label.custom_minimum_size = Vector2(0, 66)

## The choice header: an accent rule across the panel, a "YOU" chip mirroring the
## speaker chip, and a one-line nudge. The chip carries the information (these are
## YOUR lines now); the nudge carries the joke and never names a "correct" option.
func _build_choice_hint() -> void:
	var vbox: VBoxContainer = $Panel/Margin/VBox

	_choice_rule = Panel.new()
	_choice_rule.name = "ChoiceRule"
	_choice_rule.custom_minimum_size = Vector2(0, 2)
	_choice_rule.add_theme_stylebox_override("panel", _GameTheme.bar_fill_box(_GameTheme.CYAN))
	_choice_rule.modulate.a = 0.5
	_choice_rule.visible = false
	vbox.add_child(_choice_rule)
	vbox.move_child(_choice_rule, choices_box.get_index())

	_choice_header = HBoxContainer.new()
	_choice_header.name = "ChoiceHeader"
	_choice_header.add_theme_constant_override("separation", 12)
	_choice_header.visible = false
	vbox.add_child(_choice_header)
	vbox.move_child(_choice_header, choices_box.get_index())

	var you := Label.new()
	you.name = "YouChip"
	you.text = "YOU"
	you.add_theme_stylebox_override("normal", _GameTheme.chip_box(_GameTheme.CYAN))
	you.add_theme_color_override("font_color", _GameTheme.hot_of(_GameTheme.CYAN))
	you.add_theme_font_override("font", _GameTheme.spaced_font(2))
	you.add_theme_font_size_override("font_size", 13)
	you.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_choice_header.add_child(you)

	_choice_hint = Label.new()
	_choice_hint.name = "ChoiceHint"
	_choice_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choice_hint.add_theme_font_size_override("font_size", 13)
	_choice_hint.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	_choice_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_choice_header.add_child(_choice_hint)

## One switch for the whole "your turn" block, so the rule, the chip and the
## nudge can never disagree about whether a choice is on screen.
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
	_GameTheme.stagger_rows(choices_box, 0.05, 0.0)
	# [E] deliberately does nothing while options are up — you have to pick one —
	# so without focus here a keyboard/controller player has no way to answer at
	# all. The ring is also the cheapest possible "these are the buttons": one
	# glance, and your next physical action is arrow keys + Enter, or a click.
	# Same guarantee event_popup.gd already gives its choices.
	if choices_box.get_child_count() > 0:
		var first := choices_box.get_child(0) as Button
		if first != null:
			first.grab_focus()

## "This is what you can say": filled, raised cards with generous hit padding, so
## the options never read as more of the paragraph above them.
func _style_choice_button(btn: Button) -> void:
	_GameTheme.style_button(btn, _GameTheme.CYAN, 16)
	var boxes := _GameTheme.button_boxes(_GameTheme.CYAN)
	# The body behind these is now OPAQUE BASE, which changes the maths: a
	# translucent wash (SURFACE at 60%, or accent at 10%) composites to within ~3%
	# luminance of BASE and the "card" is not a card at all — just the 1px border,
	# which is exactly what it looked like before. RAISED is the palette's own
	# step above BASE (docs/VISUAL_BIBLE.md master palette), so the base card is
	# opaque RAISED and each state lifts from THERE toward the accent. Opaque on
	# opaque: what the eye gets is what the code says.
	var card: Color = _GameTheme.RAISED
	var normal: StyleBoxFlat = boxes["normal"]
	normal.bg_color = card
	var hover: StyleBoxFlat = boxes["hover"]
	hover.bg_color = card.lerp(_GameTheme.CYAN, 0.12)
	var pressed: StyleBoxFlat = boxes["pressed"]
	pressed.bg_color = card.lerp(_GameTheme.CYAN, 0.24)
	for state: String in ["normal", "hover", "pressed"]:
		var box: StyleBoxFlat = boxes[state]
		box.content_margin_left = 18.0
		box.content_margin_right = 18.0
		box.content_margin_top = 11.0
		box.content_margin_bottom = 11.0
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
