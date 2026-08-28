extends Node
## Random incidents and world events.

signal event_triggered(event_id: String, description: String)
signal event_resolved(event_id: String, choice: int)

var event_defs: Array = []
var active_event: Dictionary = {}
var cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_load_events()

func reset() -> void:
	active_event.clear()
	cooldown = 60.0

func _load_events() -> void:
	var file := FileAccess.open("res://data/events/random_events.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		if data is Array:
			event_defs = data
		elif data is Dictionary:
			event_defs = data.get("events", [])
		file.close()

func _process(delta: float) -> void:
	if not GameManager or GameManager.state != GameManager.GameState.PLAYING:
		return
	if not active_event.is_empty():
		return
	cooldown -= delta
	if cooldown <= 0:
		cooldown = _rng.randf_range(90.0, 180.0)
		_try_trigger()

func _try_trigger() -> void:
	if UIManager.has_blocking_ui():
		return
	var eligible: Array = []
	for ev in event_defs:
		var min_act: int = ev.get("min_act", 1)
		if GameManager.current_act >= min_act:
			eligible.append(ev)
	if eligible.is_empty():
		return
	if _rng.randf() > 0.35:
		return
	var ev: Dictionary = eligible[_rng.randi() % eligible.size()]
	active_event = ev.duplicate(true)
	event_triggered.emit(ev.id, ev.get("description", ""))

func resolve(choice_index: int) -> void:
	if active_event.is_empty():
		return
	var choices: Array = active_event.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return
	var choice: Dictionary = choices[choice_index]
	for res in choice.get("effects", {}):
		if res == "technical_debt":
			ResourceManager.accept_debt(int(choice.effects[res]))
		else:
			ResourceManager.modify(res, float(choice.effects[res]))
	if choice.has("achievement"):
		AchievementManager.unlock(choice.achievement)
	event_resolved.emit(active_event.id, choice_index)
	active_event.clear()

func has_active_event() -> bool:
	return not active_event.is_empty()

func get_active() -> Dictionary:
	return active_event
