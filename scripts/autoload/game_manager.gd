extends Node
## Central game state and scene flow controller.

## Preloaded rather than referenced by class_name: GameManager is an autoload and
## resolves before the global class cache is guaranteed to be populated.
const _ComedyLines = preload("res://scripts/ui/comedy_lines.gd")
## Same reason as _ComedyLines: FxLib is static-state-only, and an autoload must
## not depend on the global class cache being warm.
const _FxLib = preload("res://scripts/combat/fx_lib.gd")

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

## The playable world. 3D when the conversion is on disk (3D_BIBLE.md), the
## 2D scene otherwise — tests instantiate world.tscn directly, so both stay.
const WORLD_SCENE_3D := "res://scenes/world3d/world3d.tscn"
const WORLD_SCENE_2D := "res://scenes/world/world.tscn"

static func world_scene() -> String:
	return WORLD_SCENE_3D if ResourceLoader.exists(WORLD_SCENE_3D) else WORLD_SCENE_2D

var state: GameState = GameState.MENU
var current_region: String = "localhost"
var current_act: int = 1
var play_time_seconds: float = 0.0
var is_post_game: bool = false
var death_count: int = 0
## dependency_district is unlocked from the start so the first hop out of
## Localhost always exists (otherwise the player is stranded — no quest unlocks
## it). Later regions unlock progressively via quest rewards.
var regions_unlocked: Array[String] = ["localhost", "dependency_district"]
var player_position: Vector2 = Vector2.ZERO
## The current region's safe spawn point (set by the world on region load). Used
## for respawns so the player never re-materializes inside the enemy pile that
## just killed them.
var region_spawn: Vector2 = Vector2.ZERO
## The counters the end-of-run screen reads. ONE definition, because there used
## to be three (this initialiser, the copy in start_new_game(), and whatever a
## save file happened to contain) and they were free to drift apart.
const SESSION_STAT_DEFAULTS := {
	"quests_completed": 0,
	"tokens_collected": 0,
	"enemies_defeated": 0,
	"debt_accepted": 0,
	"api_calls": 0,
	"reloads_detected": 0,
}

var session_stats: Dictionary = SESSION_STAT_DEFAULTS.duplicate()

var show_opening_sequence: bool = true

## Generic persistent story flags (e.g. "backups") for callbacks/running gags.
var story_flags: Dictionary = {}

func set_flag(key: String, value: bool = true) -> void:
	story_flags[key] = value

func get_flag(key: String) -> bool:
	return bool(story_flags.get(key, false))

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
	regions_unlocked = ["localhost", "dependency_district"]
	player_position = Vector2.ZERO
	session_stats = SESSION_STAT_DEFAULTS.duplicate()
	show_opening_sequence = true
	story_flags.clear()
	ResourceManager.reset()
	QuestManager.reset()
	DreamAppManager.reset()
	EventManager.reset()
	AchievementManager.reset()
	DialogueManager.reset()
	CycleManager.reset()
	ModelManager.reset()
	AgentManager.reset()
	ArchitectureManager.reset()
	# ComedyLines keeps its no-repeat bags and prop-visit counters in STATIC state,
	# so they outlive every UI node being freed — which is the point, but it means a
	# run started outside the main menu (debug, tests, restart-after-victory) would
	# otherwise inherit the previous run's exhausted pools and repeat itself.
	# main_menu._on_new_game() covers the normal path; this covers all of them.
	_ComedyLines.reset_session()
	# FxLib's hit-stop and FX-budget counters are static too, and fx_lib.gd's own
	# header says outright that "anything that tears the world down (new game,
	# death, scene swap) can call this" — but nothing ever did. A run that began
	# while a hit-stop freeze owned Engine.time_scale, or after the emitter /
	# flare counters had drifted upward, inherited slow motion or a combat layer
	# that had silently stopped spawning bursts for the rest of the session.
	_FxLib.release_hit_stop()
	state = GameState.PLAYING
	game_started.emit()
	_change_scene(world_scene())

func continue_game() -> void:
	if SaveManager.load_game():
		show_opening_sequence = false
		state = GameState.PLAYING
		_change_scene(world_scene())
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
	_FxLib.release_hit_stop()
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
	if state == GameState.GAME_OVER:
		return
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
	# You died mid-hit-stop more often than not — the killing blow IS a freeze —
	# and the world you die in is torn down before the restore timer's 40ms are
	# up on a slow load. Hand the clock and the FX budget back explicitly.
	_FxLib.release_hit_stop()

func trigger_victory() -> void:
	state = GameState.VICTORY
	var results := _calculate_ship_results()
	game_won.emit(results)
	is_post_game = true
	AchievementManager.unlock("ship_it")
	SaveManager.autosave()

func get_ship_results() -> Dictionary:
	return _calculate_ship_results()

## A personalized roast assembled from the choices you actually made this run.
func get_ship_roast() -> Array:
	var out: Array = []
	var debt := ResourceManager.get_value("technical_debt")
	var flags: Dictionary = ArchitectureManager.flags if ArchitectureManager else {}
	if debt >= 80.0:
		out.append("Your technical debt qualifies for its own Series B.")
	elif debt >= 40.0:
		out.append("Technical debt: the 'restructure the whole team' kind.")
	if flags.get("structure") == "microservices":
		out.append("47 microservices. For this. Chef's kiss.")
	if flags.get("testing") == "later":
		out.append("Tests? You said 'later.' It is now later. There are none.")
	if flags.get("security") == "velocity":
		out.append("You chose velocity over security. The Security Engineer has your address.")
	if flags.get("hosting") == "cloud":
		out.append("Your cloud bill has achieved sentience and unionized.")
	if flags.get("database") == "nosql":
		out.append("NoSQL: because who needs the data to still be there.")
	if get_flag("backups"):
		out.append("You made backups. Weirdly, disturbingly responsible.")
	else:
		out.append("No backups. Living blindfolded on a cliff edge.")
	if death_count >= 5:
		out.append("You died %d times and kept going. Grit, or a concussion." % death_count)
	if AchievementManager and AchievementManager.is_unlocked("it_was_dns"):
		out.append("And yes \u2014 that one time \u2014 it really was DNS.")
	if ArchitectureManager and ArchitectureManager.ridiculousness >= 8:
		out.append("Architecture Ridiculousness: MAXIMUM. Frame it.")
	if out.is_empty():
		out.append("Somehow you made reasonable choices. Suspicious.")
	return out

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
		# .get(), not `.quests_completed`: the property form RAISES on a
		# dictionary that lacks the key, and the one caller that can arrive here
		# with a short dictionary is the victory screen after a Continue.
		"quests_completed": session_stats.get("quests_completed", 0),
		"play_time": play_time_seconds,
		"deaths": death_count,
		"architecture_ridiculousness": ArchitectureManager.ridiculousness,
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

## Bump one end-of-run counter.
##
## The old guard was `if session_stats.has(key)`, which meant a stat SILENTLY
## VANISHED for the rest of the run whenever the dictionary was incomplete — and
## SaveManager handed it `data.get("session_stats", {})` verbatim, so continuing
## from any save written before a key existed dropped every increment of that
## key without a word. adopt_session_stats() now guarantees the dictionary is
## complete; this seeds a genuinely new key rather than throwing the count away.
## Take session counters off a save file WITHOUT losing the keys it predates.
## SaveManager calls this instead of assigning the loaded dictionary straight
## through, so a run continued from an older save still has every counter the
## current build reads.
func adopt_session_stats(loaded: Dictionary) -> void:
	var merged: Dictionary = SESSION_STAT_DEFAULTS.duplicate()
	for k in loaded:
		merged[k] = int(loaded[k])
	session_stats = merged

func record_stat(key: String, amount: int = 1) -> void:
	session_stats[key] = int(session_stats.get(key, 0)) + amount

func is_region_unlocked(region_id: String) -> bool:
	return region_id in regions_unlocked
