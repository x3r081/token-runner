extends Node
## Quest tracking, progression, and completion.

signal quest_started(quest_id: String)
signal quest_updated(quest_id: String)
signal quest_completed(quest_id: String, rewards: Dictionary)
signal quest_failed(quest_id: String)

enum QuestState { INACTIVE, ACTIVE, COMPLETED, FAILED }

var quest_defs: Dictionary = {}
var quest_states: Dictionary = {}
var quest_progress: Dictionary = {}
var completed_quests: Array[String] = []

func _ready() -> void:
	_load_quest_definitions()

func reset() -> void:
	quest_states.clear()
	quest_progress.clear()
	completed_quests.clear()
	_activate_starter_quests()

func _load_quest_definitions() -> void:
	var file := FileAccess.open("res://data/quests/quests.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		if data is Dictionary:
			quest_defs = data.get("quests", {})
		file.close()

func _activate_starter_quests() -> void:
	for qid in quest_defs:
		var q: Dictionary = quest_defs[qid]
		if q.get("auto_start", false):
			start_quest(qid)

func start_quest(quest_id: String) -> bool:
	if quest_id not in quest_defs:
		return false
	if quest_states.get(quest_id, QuestState.INACTIVE) == QuestState.ACTIVE:
		return false
	if quest_id in completed_quests:
		return false
	var prereqs: Array = quest_defs[quest_id].get("prerequisites", [])
	for p in prereqs:
		if p not in completed_quests:
			return false
	quest_states[quest_id] = QuestState.ACTIVE
	quest_progress[quest_id] = {}
	for obj in quest_defs[quest_id].get("objectives", []):
		quest_progress[quest_id][obj.id] = 0
	quest_started.emit(quest_id)
	return true

func update_objective(quest_id: String, objective_id: String, amount: int = 1) -> void:
	if quest_states.get(quest_id) != QuestState.ACTIVE:
		return
	if not quest_progress.has(quest_id):
		return
	if not quest_progress[quest_id].has(objective_id):
		return
	var obj_def := _get_objective_def(quest_id, objective_id)
	var target: int = obj_def.get("count", 1)
	quest_progress[quest_id][objective_id] = mini(
		quest_progress[quest_id][objective_id] + amount, target
	)
	quest_updated.emit(quest_id)
	if _is_quest_complete(quest_id):
		complete_quest(quest_id)

func set_objective(quest_id: String, objective_id: String, value: int) -> void:
	if quest_states.get(quest_id) != QuestState.ACTIVE:
		return
	if quest_progress.has(quest_id) and quest_progress[quest_id].has(objective_id):
		quest_progress[quest_id][objective_id] = value
		quest_updated.emit(quest_id)
		if _is_quest_complete(quest_id):
			complete_quest(quest_id)

func complete_quest(quest_id: String) -> void:
	if quest_states.get(quest_id) != QuestState.ACTIVE:
		return
	quest_states[quest_id] = QuestState.COMPLETED
	completed_quests.append(quest_id)
	var q: Dictionary = quest_defs[quest_id]
	var rewards: Dictionary = q.get("rewards", {})
	for res in rewards:
		if res == "technical_debt":
			ResourceManager.accept_debt(int(rewards[res]))
		else:
			ResourceManager.modify(res, float(rewards[res]))
	if rewards.has("unlock_region"):
		GameManager.unlock_region(rewards.unlock_region)
	if rewards.has("achievement"):
		AchievementManager.unlock(rewards.achievement)
	GameManager.record_stat("quests_completed")
	quest_completed.emit(quest_id, rewards)
	AudioManager.play_sfx("quest_complete")
	# Chain next quests
	for next_id in quest_defs:
		var nq: Dictionary = quest_defs[next_id]
		var prereqs: Array = nq.get("prerequisites", [])
		if quest_id in prereqs and _prereqs_met(prereqs):
			start_quest(next_id)

func fail_quest(quest_id: String) -> void:
	quest_states[quest_id] = QuestState.FAILED
	quest_failed.emit(quest_id)

func get_active_quests() -> Array[String]:
	var result: Array[String] = []
	for qid in quest_states:
		if quest_states[qid] == QuestState.ACTIVE:
			result.append(qid)
	return result

func get_quest_info(quest_id: String) -> Dictionary:
	if quest_id not in quest_defs:
		return {}
	var q: Dictionary = quest_defs[quest_id].duplicate(true)
	q["id"] = quest_id
	q["state"] = quest_states.get(quest_id, QuestState.INACTIVE)
	q["progress"] = quest_progress.get(quest_id, {})
	return q

func get_all_quest_infos() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for qid in quest_defs:
		result.append(get_quest_info(qid))
	return result

func is_completed(quest_id: String) -> bool:
	return quest_id in completed_quests

func _get_objective_def(quest_id: String, objective_id: String) -> Dictionary:
	for obj in quest_defs[quest_id].get("objectives", []):
		if obj.id == objective_id:
			return obj
	return {}

func _is_quest_complete(quest_id: String) -> bool:
	for obj in quest_defs[quest_id].get("objectives", []):
		var prog: int = quest_progress[quest_id].get(obj.id, 0)
		if prog < obj.get("count", 1):
			return false
	return true

func _prereqs_met(prereqs: Array) -> bool:
	for p in prereqs:
		if p not in completed_quests:
			return false
	return true

func on_enemy_defeated(enemy_type: String) -> void:
	for qid in get_active_quests():
		for obj in quest_defs[qid].get("objectives", []):
			if obj.get("type") == "defeat" and obj.get("target") == enemy_type:
				update_objective(qid, obj.id)

func on_token_collected(count: int = 1) -> void:
	for qid in get_active_quests():
		for obj in quest_defs[qid].get("objectives", []):
			if obj.get("type") == "collect_tokens":
				update_objective(qid, obj.id, count)

func on_region_entered(region_id: String) -> void:
	for qid in get_active_quests():
		for obj in quest_defs[qid].get("objectives", []):
			if obj.get("type") == "visit" and obj.get("target") == region_id:
				set_objective(qid, obj.id, 1)

func on_interact(target_id: String) -> void:
	for qid in get_active_quests():
		for obj in quest_defs[qid].get("objectives", []):
			if obj.get("type") == "interact" and obj.get("target") == target_id:
				set_objective(qid, obj.id, 1)

func on_talk(npc_id: String) -> void:
	for qid in get_active_quests():
		for obj in quest_defs[qid].get("objectives", []):
			if obj.get("type") == "talk" and obj.get("target") == npc_id:
				set_objective(qid, obj.id, 1)
