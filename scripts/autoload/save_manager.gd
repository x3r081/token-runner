extends Node
## Versioned save/load system.

signal save_completed(slot: int)
signal load_completed(slot: int, success: bool)

const SAVE_VERSION := 1
const SAVE_DIR := "user://saves/"
const AUTOSAVE_SLOT := 0
const MAX_SLOTS := 3

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func autosave() -> void:
	save_game(AUTOSAVE_SLOT)

func save_game(slot: int = AUTOSAVE_SLOT) -> bool:
	var data := _gather_save_data()
	var path := SAVE_DIR + "save_%d.json" % slot
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	save_completed.emit(slot)
	return true

func load_game(slot: int = AUTOSAVE_SLOT) -> bool:
	var path := SAVE_DIR + "save_%d.json" % slot
	if not FileAccess.file_exists(path):
		load_completed.emit(slot, false)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		load_completed.emit(slot, false)
		return false
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		load_completed.emit(slot, false)
		return false
	_apply_save_data(data)
	load_completed.emit(slot, true)
	return true

func has_save(slot: int = AUTOSAVE_SLOT) -> bool:
	return FileAccess.file_exists(SAVE_DIR + "save_%d.json" % slot)

func get_save_info(slot: int) -> Dictionary:
	var path := SAVE_DIR + "save_%d.json" % slot
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		return {}
	return {
		"region": data.get("current_region", "localhost"),
		"play_time": data.get("play_time_seconds", 0),
		"tokens": data.get("resources", {}).get("tokens", 0),
		"quests_done": data.get("completed_quests", []).size(),
	}

func _gather_save_data() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"current_region": GameManager.current_region,
		"current_act": GameManager.current_act,
		"play_time_seconds": GameManager.play_time_seconds,
		"is_post_game": GameManager.is_post_game,
		"death_count": GameManager.death_count,
		"regions_unlocked": GameManager.regions_unlocked,
		"player_position": {"x": GameManager.player_position.x, "y": GameManager.player_position.y},
		"session_stats": GameManager.session_stats,
		"resources": ResourceManager.get_all(),
		"quest_states": QuestManager.quest_states,
		"quest_progress": QuestManager.quest_progress,
		"completed_quests": QuestManager.completed_quests,
		"dream_app": DreamAppManager.purchased,
		"achievements": AchievementManager.unlocked,
		"settings": SettingsManager.settings,
		# Run state that is neither a resource nor a quest. Without these,
		# Continue re-ran finished storylines, forgot every decision the world
		# was supposed to remember, reset the cycle clock to 1 and wiped the
		# subscription, the deployed agents and the architecture you chose.
		"story_flags": GameManager.story_flags,
		"events": EventManager.save_state(),
		"cycle": {
			"cycle": CycleManager.cycle,
			"time_left": CycleManager.time_left,
			"price_index": CycleManager.price_index,
		},
		"model_index": ModelManager.index,
		"agents": AgentManager.agents,
		"architecture": {
			"flags": ArchitectureManager.flags,
			"ridiculousness": ArchitectureManager.ridiculousness,
		},
	}

func _apply_save_data(data: Dictionary) -> void:
	var version: int = data.get("save_version", 0)
	if version > SAVE_VERSION:
		push_warning("Save from newer version")
	GameManager.current_region = data.get("current_region", "localhost")
	GameManager.current_act = data.get("current_act", 1)
	GameManager.play_time_seconds = data.get("play_time_seconds", 0.0)
	GameManager.is_post_game = data.get("is_post_game", false)
	GameManager.death_count = data.get("death_count", 0)
	GameManager.regions_unlocked.assign(data.get("regions_unlocked", ["localhost"]))
	var pos: Dictionary = data.get("player_position", {"x": 0, "y": 0})
	GameManager.player_position = Vector2(pos.x, pos.y)
	GameManager.session_stats = data.get("session_stats", {})
	ResourceManager.resources = data.get("resources", ResourceManager.RESOURCE_DEFAULTS.duplicate())
	QuestManager.quest_states = data.get("quest_states", {})
	QuestManager.quest_progress = data.get("quest_progress", {})
	QuestManager.completed_quests.assign(data.get("completed_quests", []))
	DreamAppManager.purchased = data.get("dream_app", {})
	AchievementManager.unlocked.assign(data.get("achievements", []))
	# All additive and all defaulted: an older save simply keeps the fresh-run
	# values these managers already reset themselves to.
	GameManager.story_flags = data.get("story_flags", {})
	EventManager.load_state(data.get("events", {}))
	var cyc: Dictionary = data.get("cycle", {})
	CycleManager.cycle = int(cyc.get("cycle", CycleManager.cycle))
	CycleManager.time_left = float(cyc.get("time_left", CycleManager.time_left))
	CycleManager.price_index = float(cyc.get("price_index", CycleManager.price_index))
	ModelManager.index = int(data.get("model_index", ModelManager.index))
	AgentManager.agents = (data.get("agents", []) as Array).duplicate(true)
	var arch: Dictionary = data.get("architecture", {})
	ArchitectureManager.flags = arch.get("flags", ArchitectureManager.flags)
	ArchitectureManager.ridiculousness = int(arch.get("ridiculousness", ArchitectureManager.ridiculousness))
