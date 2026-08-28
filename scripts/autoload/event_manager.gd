extends Node
## Random incidents and world events.

signal event_triggered(event_id: String, description: String)
signal event_resolved(event_id: String, choice: int)

var event_defs: Array = []
var active_event: Dictionary = {}
var cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()

## Scripted multi-stage storylines (comedy-as-mechanics). Reuses the same popup
## UI as random events by having active_event hold the current stage.
var completed_scripts: Array[String] = []
var _script_id: String = ""
var _script_stages: Array = []
var _script_repeatable: bool = false

func _ready() -> void:
	_rng.randomize()
	_load_events()

func reset() -> void:
	active_event.clear()
	cooldown = 60.0
	completed_scripts.clear()
	_script_id = ""
	_script_stages = []

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

## Begin a scripted storyline. Stages are provided by StoryEvents.*.
## Repeatable scripts (e.g. menus) can be reopened and never mark as completed.
func start_scripted(script_id: String, stages: Array, repeatable: bool = false) -> void:
	if not repeatable and script_id in completed_scripts:
		return
	if stages.is_empty() or not active_event.is_empty():
		return
	_script_id = script_id
	_script_stages = stages
	_script_repeatable = repeatable
	active_event = _stage_to_event(0)
	event_triggered.emit(_script_id, active_event.get("description", ""))

func is_script_completed(script_id: String) -> bool:
	return script_id in completed_scripts

func _stage_to_event(i: int) -> Dictionary:
	var s: Dictionary = _script_stages[i]
	return {
		"id": "%s_%d" % [_script_id, i],
		"scripted": true,
		"stage": i,
		"title": s.get("title", "INCIDENT"),
		"description": s.get("description", ""),
		"choices": s.get("choices", [{"text": "Continue", "next": -1}]),
	}

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
	if choice.has("deploy_agent"):
		AgentManager.deploy(choice.deploy_agent)
	if choice.has("architecture"):
		ArchitectureManager.choose(choice.architecture.decision, choice.architecture.option)

	if active_event.get("scripted", false):
		_resolve_scripted(choice)
		return

	event_resolved.emit(active_event.id, choice_index)
	active_event.clear()

func _resolve_scripted(choice: Dictionary) -> void:
	var next_stage: int = int(choice.get("next", -1))
	# "Blame DNS": almost always a joke... except, once in a while, it IS DNS.
	if choice.get("dns_gamble", false):
		if randf() < 0.12:
			AchievementManager.unlock("it_was_dns")
			ResourceManager.modify("stability", 20.0)
			next_stage = int(choice.get("next_success", -1))
		else:
			next_stage = int(choice.get("next_fail", -1))
	if next_stage >= 0 and next_stage < _script_stages.size():
		active_event = _stage_to_event(next_stage)
		event_triggered.emit(_script_id, active_event.get("description", ""))
		return
	# End of storyline: finalize completion + quest chaining.
	if choice.has("complete_quest"):
		var qid: String = choice["complete_quest"]
		if not QuestManager.is_completed(qid):
			if QuestManager.quest_states.get(qid) != QuestManager.QuestState.ACTIVE:
				QuestManager.start_quest(qid)
			QuestManager.complete_quest(qid)
	var finished_id := _script_id
	if not _script_repeatable and finished_id != "" and finished_id not in completed_scripts:
		completed_scripts.append(finished_id)
	_script_id = ""
	_script_stages = []
	_script_repeatable = false
	active_event.clear()
	event_resolved.emit(finished_id, 0)

func has_active_event() -> bool:
	return not active_event.is_empty()

func get_active() -> Dictionary:
	return active_event
