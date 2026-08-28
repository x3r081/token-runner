extends CanvasLayer
## Boot terminal intro — first 5 minutes hook.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

signal sequence_finished

const LINES := [
	"> TOKEN RUNNER v0.0.1-alpha-ship-before-reset",
	"> Initializing vibe-coding environment...",
	"> WARNING: Token balance critically low",
	"> WARNING: Dream App completion: 0.003%",
	"> WARNING: Client email unread (3 days)",
	"> Loading Localhost apartment... OK",
	"> Claude.exe already running in background",
	">",
	"> Press any key to pretend you're in control",
]

var _line_index := 0
var _char_index := 0
var _typing := true
var _done := false
var _wait_timer := 0.0

@onready var panel: PanelContainer = $Panel
@onready var label: RichTextLabel = $Panel/Margin/VBox/TerminalText
@onready var prompt: Label = $Panel/Margin/VBox/Prompt

func _ready() -> void:
	layer = 100
	panel.theme = _GameTheme.create()
	label.text = ""
	label.scroll_active = true
	prompt.visible = false
	AudioManager.stop_music()
	_char_index = 1
	label.text = _build_display()

func _process(delta: float) -> void:
	if _done:
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
		shown += "[color=#4de8c8]_"
	return "[color=#c8f0e8]" + shown + "[/color]"

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
