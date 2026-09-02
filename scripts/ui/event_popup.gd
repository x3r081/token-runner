extends CanvasLayer
## Incidents are dressed like a real incident channel: a ticket number, a
## severity nobody agrees on, and a footer reminding you that the bill for this
## decision arrives later. The choices themselves stay untouched and readable.
##
## Round 6: one panel style, one accent (AMBER, on the title only), no row
## cascade. The three choices are equals, so they are styled as equals — the
## amber-bordered buttons used to make all three look like the recommended one.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")
const _Modal = preload("res://scripts/ui/modal_panel.gd")

var _ticket_label: Label
var _footer_label: Label

func _ready() -> void:
	EventManager.event_triggered.connect(_on_event)
	panel.visible = false
	panel.theme = _GameTheme.create()
	panel.add_theme_stylebox_override("panel", _Modal.modal_box(_GameTheme.AMBER, 6.0))
	# Two extra rows (ticket header, consequences footer) need a little more room.
	panel.offset_left = -350.0
	panel.offset_right = 350.0
	panel.offset_top = -235.0
	panel.offset_bottom = 235.0
	title_label.add_theme_color_override("font_color", _GameTheme.AMBER)
	desc_label.add_theme_color_override("font_color", _GameTheme.TEXT)
	_build_rows()
	for i in 3:
		var btn: Button = choice_buttons[i]
		_GameTheme.style_button(btn, _GameTheme.TEXT_DIM, _Modal.BODY)
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

## Incident-channel dressing. Purely decorative — it never carries information
## the player needs, so it stays small, dim and out of the way.
func _build_rows() -> void:
	var vbox: VBoxContainer = $Panel/Margin/VBox
	_ticket_label = Label.new()
	_ticket_label.name = "Ticket"
	_ticket_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ticket_label.add_theme_font_size_override("font_size", _Modal.SMALL)
	_ticket_label.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	vbox.add_child(_ticket_label)
	vbox.move_child(_ticket_label, 1)

	_footer_label = Label.new()
	_footer_label.name = "Footer"
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer_label.add_theme_font_size_override("font_size", _Modal.SMALL)
	_footer_label.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	vbox.add_child(_footer_label)

func _on_event(event_id: String, description: String) -> void:
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
	if is_instance_valid(_ticket_label):
		# Ticket number is derived from the event id, so re-rendering a scripted
		# stage keeps the same incident open instead of filing a new one.
		var ticket := absi(event_id.hash()) % 9000 + 1000
		_ticket_label.text = "INC-%d · %s" % [
			ticket, _Comedy.pick("incident_sev", _Comedy.INCIDENT_SEVERITY)]
	if is_instance_valid(_footer_label):
		_footer_label.text = _Comedy.pick("incident_footer", _Comedy.INCIDENT_FOOTER)
	var choices: Array = ev.get("choices", [])
	# This popup renders exactly three buttons. A fourth choice used to vanish
	# without a word — that is how "Ask the AI" and "Roll back EVERYTHING" spent
	# a release being unreachable. Say so loudly instead of silently dropping it.
	if choices.size() > 3:
		push_error("event_popup: '%s' has %d choices; only the first 3 can be shown. %s"
			% [str(ev.get("id", "?")), choices.size(), str(choices.slice(3))])
	for i in 3:
		if i < choices.size():
			choice_buttons[i].visible = true
			choice_buttons[i].text = choices[i].get("text", "Option")
		else:
			choice_buttons[i].visible = false
	_GameTheme.open_panel(panel)
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
