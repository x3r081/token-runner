extends CanvasLayer

@onready var panel: PanelContainer = $Panel
@onready var speaker_label: Label = $Panel/Margin/VBox/Speaker
@onready var text_label: RichTextLabel = $Panel/Margin/VBox/Text
@onready var choices_box: VBoxContainer = $Panel/Margin/VBox/Choices
@onready var continue_btn: Button = $Panel/Margin/VBox/ContinueBtn

func _ready() -> void:
	DialogueManager.dialogue_line.connect(_on_line)
	DialogueManager.choice_presented.connect(_on_choices)
	DialogueManager.dialogue_ended.connect(_on_ended)
	continue_btn.pressed.connect(_on_continue)
	continue_btn.text = "Continue"
	panel.visible = false

func _on_line(_npc_id: String, speaker: String, text: String) -> void:
	panel.visible = true
	speaker_label.text = speaker
	text_label.text = text
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
		var idx := i
		btn.pressed.connect(func(): DialogueManager.select_choice(idx))
		choices_box.add_child(btn)

func _on_continue() -> void:
	DialogueManager.advance()

func _on_ended(_npc_id: String) -> void:
	panel.visible = false
