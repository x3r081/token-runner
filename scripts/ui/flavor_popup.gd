extends Control
## Lightweight popup for environmental comedy props (fridge, plant, bed, router,
## terminal...). Screen-space (added under the HUD CanvasLayer), pauses the game
## while you read, and closes on any confirm/cancel/interact key or a click.
##
## Public fields (kept stable — regression tests and every prop set these):
##   title_text     the object's name, shown in the header
##   body_text      the joke, revealed with a typewriter pass
##   subtitle_text  optional "you have now stared at this four times" note
##   sigil_text     optional 1-2 char type sigil (accepted, no longer drawn)
##   accent_color   the prop's category colour — this screen's ONE accent
##
## Input is two-stage on purpose: while the text is still typing, the first press
## completes it instantly; only a press on finished text closes the popup. You
## can never accidentally skip a joke you have not read.
##
## Round 6 removed the sigil plate (a chip at a different pixel size from
## everything around it), the accent bar-gradient rule, the vignette, the moving
## sheen, the accent-glow panel and the row cascade. A prop joke is one card with
## a name and a sentence on it.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Modal = preload("res://scripts/ui/modal_panel.gd")

## Typewriter pacing: seconds per character, clamped so a one-liner still has a
## beat and a long entry never outlasts the player's patience.
const TYPE_PER_CHAR := 0.009
const TYPE_MIN := 0.30
const TYPE_MAX := 1.30

var title_text := "Prop"
var body_text := "..."
var subtitle_text := ""
var sigil_text := ""
var accent_color: Color = _GameTheme.CYAN

var _armed := false
var _typing := false
var _body: Label
var _hint: Label
var _type_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Pause while reading: a modal joke shouldn't let a nearby enemy kill you, and
	# it avoids input races with other overlays (e.g. the death screen).
	get_tree().paused = true
	tree_exiting.connect(func():
		if is_inside_tree() and get_tree():
			get_tree().paused = false)
	# Briefly ignore input so the same [E] press that opened this doesn't close it.
	get_tree().create_timer(0.18).timeout.connect(func(): _armed = true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.color = _GameTheme.with_alpha(_Modal.SCRIM_TINT, 0.78)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var panel := PanelContainer.new()
	panel.name = "FlavorPanel"
	panel.theme = _GameTheme.create()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.add_theme_stylebox_override("panel", _Modal.modal_box(accent_color, 22.0))
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(500, 0)
	panel.add_child(vb)

	# The prop's name — the one accent on this screen.
	var title := Label.new()
	title.name = "FlavorTitle"
	title.text = title_text
	title.add_theme_font_size_override("font_size", _Modal.HEADING)
	title.add_theme_color_override("font_color", accent_color)
	vb.add_child(title)

	# Repeat-visit note ("you have looked at this four times now"), when supplied.
	if not subtitle_text.is_empty():
		var sub := Label.new()
		sub.name = "FlavorSubtitle"
		sub.text = subtitle_text
		sub.add_theme_font_size_override("font_size", _Modal.SMALL)
		sub.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
		vb.add_child(sub)

	_body = Label.new()
	_body.name = "FlavorBody"
	_body.text = body_text
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", _Modal.BODY)
	_body.add_theme_color_override("font_color", _GameTheme.TEXT)
	_body.custom_minimum_size = Vector2(500, 0)
	vb.add_child(_body)

	_hint = Label.new()
	_hint.name = "FlavorHint"
	_hint.text = "[E] reveal the rest"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", _Modal.SMALL)
	_hint.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	vb.add_child(_hint)

	_GameTheme.open_panel(panel)
	_start_typing()

# --------------------------------------------------------------- typewriter ----

func _start_typing() -> void:
	if _body == null:
		return
	if body_text.length() < 2:
		_finish_typing()
		return
	_typing = true
	_body.visible_ratio = 0.0
	var dur := clampf(float(body_text.length()) * TYPE_PER_CHAR, TYPE_MIN, TYPE_MAX)
	# The popup pauses the tree, so the reveal must run on the pause-proof path.
	_type_tween = _body.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_type_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_type_tween.tween_interval(_GameTheme.T_MICRO)
	_type_tween.tween_property(_body, "visible_ratio", 1.0, dur)
	_type_tween.tween_callback(_finish_typing)

func _finish_typing() -> void:
	if _type_tween and _type_tween.is_valid():
		_type_tween.kill()
	_type_tween = null
	_typing = false
	if is_instance_valid(_body):
		_body.visible_ratio = 1.0
	if is_instance_valid(_hint):
		_hint.text = "[E] / click to close"

func _input(event: InputEvent) -> void:
	if not _armed:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
			or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") \
			or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		# First press finishes the reveal; only a press on finished text closes.
		if _typing:
			_finish_typing()
			return
		queue_free()
