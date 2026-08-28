extends CanvasLayer

func _ready() -> void:
	EventManager.event_triggered.connect(_on_event)
	panel.visible = false
	for i in 3:
		var btn: Button = choice_buttons[i]
		btn.pressed.connect(_on_choice.bind(i))

@onready var panel: PanelContainer = $Panel
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
	get_tree().paused = true
	panel.visible = true
	title_label.text = ev.get("title", "INCIDENT")
	desc_label.text = description
	var choices: Array = ev.get("choices", [])
	for i in 3:
		if i < choices.size():
			choice_buttons[i].visible = true
			choice_buttons[i].text = choices[i].get("text", "Option")
		else:
			choice_buttons[i].visible = false

func _on_choice(index: int) -> void:
	EventManager.resolve(index)
	panel.visible = false
	get_tree().paused = false
