extends Control
## Lightweight, styled popup for environmental comedy props (fridge, plant, bed,
## router, terminal...). Screen-space (added under the HUD CanvasLayer), pauses
## nothing, and closes on any confirm/cancel/interact key or a click.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

var title_text := "Prop"
var body_text := "..."
var _armed := false

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
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	backdrop.modulate.a = 0.0
	var bt := backdrop.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	bt.tween_property(backdrop, "modulate:a", 1.0, _GameTheme.T_STD)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.CYAN, 18.0))
	add_child(panel)
	_GameTheme.add_sheen(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.custom_minimum_size = Vector2(460, 0)
	panel.add_child(vb)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 22)
	_GameTheme.style_heading(title, _GameTheme.CYAN, 22)
	vb.add_child(title)

	var body := Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", _GameTheme.TEXT)
	body.custom_minimum_size = Vector2(460, 0)
	vb.add_child(body)

	var hint := Label.new()
	hint.text = "[E] / click to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	vb.add_child(hint)

	_GameTheme.open_panel(panel)
	_GameTheme.stagger_rows(vb)

func _input(event: InputEvent) -> void:
	if not _armed:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
			or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") \
			or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		queue_free()
