extends CanvasLayer
## Boot terminal intro — the first five seconds, and no more of them than that.
##
## Round 6: the code-rain shader behind the boot text and the breathing "press any
## key" prompt are gone (the display already draws a blinking cursor), the panel
## is the standard modal box, and three of the nine boot lines went with them.
## The intro must ALWAYS hand control back — see the hard caps below.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Modal = preload("res://scripts/ui/modal_panel.gd")

signal sequence_finished

const LINES := [
	"> TOKEN RUNNER v0.0.1-alpha",
	"> WARNING: token balance critically low",
	"> WARNING: Dream App completion 0.003%",
	"> Loading Localhost apartment... OK",
	"> Claude.exe already running",
	">",
	"> Press any key to pretend you're in control",
]

var _line_index := 0
var _char_index := 0
var _typing := true
var _done := false
var _wait_timer := 0.0
var _elapsed := 0.0
var _prompt_time := 0.0

## Hard caps so the intro can NEVER trap the player, even if input is missed.
const MAX_TOTAL := 16.0     # absolute ceiling on the whole intro
const PROMPT_AUTO := 6.0    # auto-continue after the prompt has been shown a while

@onready var panel: PanelContainer = $Panel
@onready var label: RichTextLabel = $Panel/Margin/VBox/TerminalText
@onready var prompt: Label = $Panel/Margin/VBox/Prompt

func _ready() -> void:
	layer = 100
	panel.theme = _GameTheme.create()
	_dress()
	label.text = ""
	label.scroll_active = true
	prompt.visible = false
	AudioManager.stop_music()
	_char_index = 1
	label.text = _build_display()

## One panel, one accent on the title, and the terminal text. Nothing behind it.
func _dress() -> void:
	panel.add_theme_stylebox_override("panel", _Modal.modal_box(_GameTheme.CYAN, 24.0))
	var title: Label = $Panel/Margin/VBox/Title
	title.add_theme_color_override("font_color", _GameTheme.CYAN)
	# The boot text used to carry its own two colours as inline bbcode; it is one
	# terminal, so it is one colour, set once here.
	label.add_theme_color_override("default_color", _GameTheme.TEXT)
	label.add_theme_font_size_override("normal_font_size", _Modal.BODY)
	prompt.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	_GameTheme.open_panel(panel)

func _process(delta: float) -> void:
	if _done:
		return
	# Safety: the intro must always hand control back to the player.
	_elapsed += delta
	if _elapsed >= MAX_TOTAL:
		_finish()
		return
	if prompt.visible:
		_prompt_time += delta
		if _prompt_time >= PROMPT_AUTO:
			_finish()
			return
	if _wait_timer > 0.0:
		_wait_timer -= delta
		label.text = _build_display()
		return
	if _typing:
		_char_index += maxi(1, int(delta * 48.0))
		var line: String = LINES[_line_index]
		if _char_index >= line.length():
			_char_index = line.length()
			_typing = false
			if _line_index < LINES.size() - 1:
				_wait_timer = 0.3
			else:
				prompt.visible = true
	label.text = _build_display()
	if not _typing and _wait_timer <= 0.0 and _line_index < LINES.size() - 1:
		_next_line()

func _build_display() -> String:
	var shown := ""
	for i in _line_index:
		shown += LINES[i] + "\n"
	var line: String = LINES[_line_index]
	shown += line.substr(0, mini(_char_index, line.length()))
	if _typing and int(Time.get_ticks_msec() / 400) % 2 == 0:
		shown += "_"
	return shown

func _next_line() -> void:
	_line_index += 1
	_char_index = 1
	_typing = true
	_wait_timer = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	if not event.pressed or event.is_echo():
		return
	if _line_index < LINES.size() - 1 or _typing:
		_line_index = LINES.size() - 1
		_char_index = LINES[_line_index].length()
		_typing = false
		_wait_timer = 0.0
		prompt.visible = true
		label.text = _build_display()
		return
	_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	prompt.visible = false
	sequence_finished.emit()
	queue_free()
