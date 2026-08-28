extends Node
## NPC dialogue presentation.

signal dialogue_started(npc_id: String)
signal dialogue_line(npc_id: String, speaker: String, text: String)
signal dialogue_ended(npc_id: String)
signal choice_presented(choices: Array)
signal choice_made(index: int)

var dialogue_data: Dictionary = {}
var is_active: bool = false
var current_npc: String = ""
var current_lines: Array = []
var line_index: int = 0
var pending_choices: Array = []

func _ready() -> void:
	_load_dialogue()

func _load_dialogue() -> void:
	var file := FileAccess.open("res://data/dialogue/npcs.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		if data is Dictionary:
			dialogue_data = data.get("npcs", {})
		file.close()

func start_dialogue(npc_id: String, topic: String = "greeting") -> void:
	if is_active:
		return
	if npc_id not in dialogue_data:
		return
	var npc: Dictionary = dialogue_data[npc_id]
	var lines: Array = npc.get(topic, npc.get("greeting", []))
	if lines.is_empty():
		return
	is_active = true
	current_npc = npc_id
	current_lines = lines
	line_index = 0
	GameManager.state = GameManager.GameState.DIALOGUE
	dialogue_started.emit(npc_id)
	_show_line()
	QuestManager.on_talk(npc_id)

func _show_line() -> void:
	if line_index >= current_lines.size():
		end_dialogue()
		return
	var line: Variant = current_lines[line_index]
	if line is Dictionary:
		if line.has("choices"):
			pending_choices = line.choices
			choice_presented.emit(pending_choices)
			return
		var speaker: String = line.get("speaker", current_npc)
		var text: String = line.get("text", "")
		dialogue_line.emit(current_npc, speaker, text)
	elif line is String:
		dialogue_line.emit(current_npc, current_npc, line)
	line_index += 1

func advance() -> void:
	if not is_active:
		return
	if not pending_choices.is_empty():
		return
	_show_line()

func select_choice(index: int) -> void:
	if pending_choices.is_empty():
		return
	if index < 0 or index >= pending_choices.size():
		return
	var choice: Dictionary = pending_choices[index]
	pending_choices.clear()
	choice_made.emit(index)
	if choice.has("effects"):
		for res in choice.effects:
			ResourceManager.modify(res, float(choice.effects[res]))
	if choice.has("quest"):
		QuestManager.start_quest(choice.quest)
	if choice.has("goto"):
		var topic: String = choice.goto
		var npc: Dictionary = dialogue_data[current_npc]
		current_lines = npc.get(topic, [])
		line_index = 0
		_show_line()
	else:
		end_dialogue()

func end_dialogue() -> void:
	is_active = false
	current_npc = ""
	current_lines.clear()
	pending_choices.clear()
	line_index = 0
	if GameManager.state == GameManager.GameState.DIALOGUE:
		GameManager.state = GameManager.GameState.PLAYING
	dialogue_ended.emit(current_npc)

func get_npc_name(npc_id: String) -> String:
	if npc_id in dialogue_data:
		return dialogue_data[npc_id].get("display_name", npc_id)
	return npc_id
