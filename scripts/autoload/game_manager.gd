extends Node
## Central game state and scene flow controller.

signal game_started
signal game_paused(paused: bool)
signal region_changed(region_id: String)
signal act_changed(act: int)
signal game_won(results: Dictionary)
signal player_died(message: String)
signal debt_incident(kind: String)

enum GameState { MENU, PLAYING, PAUSED, DIALOGUE, CUTSCENE, GAME_OVER, VICTORY, LOADING }

const REGION_ORDER: Array[String] = [
	"localhost",
	"dependency_district",
	"stackoverflow_ruins",
	"api_bazaar",
	"cloud_district",
	"open_source_wildlands",
	"corporate_enterprise",
	"gpu_mines",
	"production",
	"token_vault",
]

var state: GameState = GameState.MENU
var current_region: String = "localhost"
var current_act: int = 1
var play_time_seconds: float = 0.0
var is_post_game: bool = false
var death_count: int = 0
var regions_unlocked: Array[String] = ["localhost"]
var player_position: Vector2 = Vector2.ZERO
var session_stats: Dictionary = {
	"quests_completed": 0,
	"tokens_collected": 0,
	"enemies_defeated": 0,
	"debt_accepted": 0,
	"api_calls": 0,
	"reloads_detected": 0,
}

var show_opening_sequence: bool = true

## Technical debt consequences: above the safe threshold, debt periodically
## drains stability and can "break a dependency" (spawns a bug in the world).
## Below it, nothing happens — some debt is strategically fine.
const DEBT_SAFE_THRESHOLD := 20.0
const DEBT_TICK_INTERVAL := 5.0

var _rng := RandomNumberGenerator.new()
var _debt_accum := 0.0

func _ready() -> void:
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if state == GameState.PLAYING and not get_tree().paused:
		play_time_seconds += delta
		_debt_accum += delta
		if _debt_accum >= DEBT_TICK_INTERVAL:
			_debt_accum = 0.0
			apply_debt_consequences()

## Public so it can be exercised deterministically by tests.
func apply_debt_consequences() -> void:
	var debt := ResourceManager.get_value("technical_debt")
	if debt <= DEBT_SAFE_THRESHOLD:
		return
	var over := debt - DEBT_SAFE_THRESHOLD
	ResourceManager.modify("stability", -clampf(over * 0.05, 0.2, 4.0))
	var break_chance := clampf(over / 300.0, 0.0, 0.5)
	if _rng.randf() < break_chance:
		debt_incident.emit("dependency_break")

func start_new_game() -> void:
	current_region = "localhost"
	current_act = 1
	play_time_seconds = 0.0
	is_post_game = false
	death_count = 0
	regions_unlocked = ["localhost"]
	player_position = Vector2.ZERO
	session_stats = {
		"quests_completed": 0,
		"tokens_collected": 0,
		"enemies_defeated": 0,
		"debt_accepted": 0,
		"api_calls": 0,
		"reloads_detected": 0,
	}
	show_opening_sequence = true
	ResourceManager.reset()
	QuestManager.reset()
	DreamAppManager.reset()
	EventManager.reset()
	AchievementManager.reset()
	DialogueManager.reset()
	CycleManager.reset()
	ModelManager.reset()
	state = GameState.PLAYING
	game_started.emit()
	_change_scene("res://scenes/world/world.tscn")

func continue_game() -> void:
	if SaveManager.load_game():
		show_opening_sequence = false
		state = GameState.PLAYING
		_change_scene("res://scenes/world/world.tscn")
	else:
		start_new_game()

func pause_game(paused: bool) -> void:
	if state != GameState.PLAYING and state != GameState.PAUSED:
		return
	state = GameState.PAUSED if paused else GameState.PLAYING
	get_tree().paused = paused
	game_paused.emit(paused)

func return_to_menu() -> void:
	state = GameState.MENU
	get_tree().paused = false
	_change_scene("res://scenes/main/main_menu.tscn")

func change_region(region_id: String, spawn_pos: Vector2 = Vector2.ZERO) -> void:
	if region_id not in regions_unlocked:
		return
	current_region = region_id
	player_position = spawn_pos
	_update_act()
	region_changed.emit(region_id)
	SaveManager.autosave()

func unlock_region(region_id: String) -> void:
	if region_id not in regions_unlocked:
		regions_unlocked.append(region_id)
		_update_act()

func _update_act() -> void:
	var idx := REGION_ORDER.find(current_region)
	var new_act := clampi(idx / 2 + 1, 1, 5)
	if new_act != current_act:
		current_act = new_act
		act_changed.emit(new_act)

func handle_player_death(cause: String = "") -> void:
	death_count += 1
	var messages := [
		"You have been rate limited by reality.",
		"Production would like a word.",
		"The agent said it was 100% confident.",
		"Your architecture achieved sentience and rejected you.",
		"You ran out of tokens halfway through fixing the token system.",
		"Works on my machine. Unfortunately, this isn't your machine.",
		"Context window exceeded. You forgot to breathe.",
		"The merge conflict won.",
	]
	var msg: String = cause if cause != "" else messages[_rng.randi() % messages.size()]
	state = GameState.GAME_OVER
	player_died.emit(msg)
	ResourceManager.modify("will_to_live", -15)
	ResourceManager.modify("stability", -10)

func respawn_player() -> void:
	state = GameState.PLAYING
	get_tree().paused = false

func trigger_victory() -> void:
	state = GameState.VICTORY
	var results := _calculate_ship_results()
	game_won.emit(results)
	is_post_game = true
	AchievementManager.unlock("ship_it")
	SaveManager.autosave()

func get_ship_results() -> Dictionary:
	return _calculate_ship_results()

func _calculate_ship_results() -> Dictionary:
	var app := DreamAppManager.get_totals()
	var res := ResourceManager.get_all()
	var score := 0
	score += app.features * 10
	score += app.stability * 8
	score -= res.technical_debt * 3
	score += app.security * 5
	score += mini(res.reputation, 100)
	score -= mini(res.technical_debt, 200)
	var ranking := "Beautiful Disaster"
	if score > 400:
		ranking = "Actually Production Ready"
	elif score > 350:
		ranking = "Series A Ready"
	elif score > 300:
		ranking = "Technically A SaaS"
	elif score > 250:
		ranking = "VC Demo"
	elif score > 200:
		ranking = "Works On My Machine"
	elif score > 150:
		ranking = "One Customer, 47 Microservices"
	elif score > 100:
		ranking = "Enterprise Architecture Astronaut"
	elif score > 50:
		ranking = "$84,000 Inference Bill"
	return {
		"ranking": ranking,
		"score": score,
		"features": app.features,
		"stability": app.stability,
		"security": app.security,
		"technical_debt": res.technical_debt,
		"tokens_spent": session_stats.get("tokens_collected", 0),
		"quests_completed": session_stats.quests_completed,
		"play_time": play_time_seconds,
		"deaths": death_count,
	}

func can_ship() -> bool:
	return DreamAppManager.can_ship()

func get_loading_tip() -> String:
	var tips := [
		"Remember: deleting the test is technically one way to make the test suite green.",
		"If production is down, congratulations: you have observability now.",
		"Your free-tier limit is always 14 seconds away.",
		"Backups are unnecessary until approximately three seconds after you need one.",
		"This loading screen exists because someone refused to optimize scene transitions.",
		"Never trust a migration you didn't write at 3 AM.",
		"Technical debt is just features you haven't apologized for yet.",
		"The client said 'one tiny change.' Run.",
		"Your context window is a social construct until it isn't.",
		"Blame DNS first. Apologize never.",
		"Shipping without tests is a lifestyle choice.",
		"The agent is confident. That's the problem.",
		"Kubernetes: because YAML is a personality.",
		"Your .env file should not be in version control. Again.",
		"Observability: knowing your app is on fire in real time.",
	]
	return tips[_rng.randi() % tips.size()]

func _change_scene(path: String) -> void:
	state = GameState.LOADING
	get_tree().change_scene_to_file(path)

func record_stat(key: String, amount: int = 1) -> void:
	if session_stats.has(key):
		session_stats[key] = int(session_stats[key]) + amount

func is_region_unlocked(region_id: String) -> bool:
	return region_id in regions_unlocked
