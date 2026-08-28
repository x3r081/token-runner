extends Node
## Achievement tracking.

signal achievement_unlocked(id: String, name: String, description: String)

var defs: Dictionary = {}
var unlocked: Array[String] = []

func _ready() -> void:
	_load_definitions()

func reset() -> void:
	unlocked.clear()

func _load_definitions() -> void:
	var file := FileAccess.open("res://data/achievements.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		if data is Dictionary:
			defs = data.get("achievements", {})
		file.close()

func unlock(id: String) -> void:
	if id in unlocked:
		return
	if id not in defs:
		return
	unlocked.append(id)
	var a: Dictionary = defs[id]
	achievement_unlocked.emit(id, a.get("name", id), a.get("description", ""))
	AudioManager.play_sfx("quest_complete")

func is_unlocked(id: String) -> bool:
	return id in unlocked

func check_progress() -> void:
	if ResourceManager.get_value("technical_debt") >= 100:
		unlock("enterprise_ready")
	if GameManager.death_count >= 3:
		unlock("works_on_my_machine")
	if GameManager.session_stats.get("tokens_collected", 0) >= 5000:
		unlock("one_more_account")
	if DreamAppManager.get_totals().features >= 20 and ResourceManager.get_value("stability") < 30:
		unlock("zero_tests_zero_fear")
