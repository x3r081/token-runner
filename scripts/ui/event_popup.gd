extends CanvasLayer

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

func _ready() -> void:
	EventManager.event_triggered.connect(_on_event)
	panel.visible = false
	# Incidents wear amber — the color of warnings and vending-machine coffee.
	panel.add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.AMBER, 4.0))
	_GameTheme.style_heading(title_label, _GameTheme.AMBER, 26)
	desc_label.add_theme_color_override("font_color", _GameTheme.TEXT)
	for i in 3:
		var btn: Button = choice_buttons[i]
		_GameTheme.style_button(btn, _GameTheme.AMBER, 16)
		btn.pressed.connect(_on_choice.bind(i))

@onready var panel: PanelContainer = $Panel
@onready var backdrop: ColorRect = $Backdrop
@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var desc_label: Label = $Panel/Margin/VBox/Description
@onready var choice_buttons: Array[Button] = [
	$Panel/Margin/VBox/Choice1,
	$Panel/Margin/VBox/Choice2,
	$Panel/Margin/VBox/Choice3,
]

func _on_event(_event_id: String, description: String) -> void:
	var ev := EventManager.get_active()
	if ev.is_empty():
		return
	# Scripted storylines always render (they drive their own modal flow).
	if not ev.get("scripted", false) and UIManager.has_blocking_ui():
		return
	get_tree().paused = true
	panel.visible = true
	backdrop.visible = true
	title_label.text = ev.get("title", "INCIDENT")
	desc_label.text = description
	var choices: Array = ev.get("choices", [])
	for i in 3:
		if i < choices.size():
			choice_buttons[i].visible = true
			choice_buttons[i].text = choices[i].get("text", "Option")
		else:
			choice_buttons[i].visible = false
	# Entrance: backdrop fade + panel pop (pause-proof tweens).
	backdrop.modulate.a = 0.0
	var bt := backdrop.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	bt.tween_property(backdrop, "modulate:a", 1.0, _GameTheme.T_STD)
	_GameTheme.open_panel(panel)
	_GameTheme.stagger_rows($Panel/Margin/VBox)
	# Focus the first choice so keyboard/controller players can confirm with Enter.
	if not choices.is_empty():
		choice_buttons[0].grab_focus()

func _on_choice(index: int) -> void:
	EventManager.resolve(index)
	# A scripted storyline may have advanced to the next stage, which re-renders
	# the panel via _on_event. Only tear down when nothing is active anymore.
	if EventManager.has_active_event():
		return
	panel.visible = false
	backdrop.visible = false
	get_tree().paused = false
