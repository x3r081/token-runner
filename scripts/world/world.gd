extends Node2D

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Player/Camera2D
@onready var region_container: Node2D = $RegionContainer
@onready var hud: CanvasLayer = $HUD
@onready var ambient: CanvasModulate = $AmbientLight

var _current_region_node: Node2D

func _ready() -> void:
	GameManager.state = GameManager.GameState.PLAYING
	_setup_glow()
	_load_region(GameManager.current_region)
	QuestManager.on_region_entered(GameManager.current_region)
	GameManager.region_changed.connect(_on_region_changed)
	GameManager.player_died.connect(_on_player_died)
	GameManager.debt_incident.connect(_on_debt_incident)
	# NOTE: do NOT also connect player.died here. player._die() emits `died` AND
	# calls GameManager.handle_player_death() (which emits player_died), so wiring
	# both spawned two stacked death screens — the top one's Respawn button freed
	# only itself, leaving an identical screen behind and making respawn look broken.
	if player and "can_move" in player:
		player.can_move = false
	_set_ambient("localhost")
	if GameManager.show_opening_sequence:
		_start_opening_sequence()
	else:
		if player and "can_move" in player:
			player.can_move = true
			if player.has_method("grant_spawn_grace"):
				player.grant_spawn_grace()

func _start_opening_sequence() -> void:
	var intro := preload("res://scenes/ui/opening_sequence.tscn").instantiate()
	add_child(intro)
	intro.sequence_finished.connect(_on_opening_finished)
	# Safety net: no matter what, restore control shortly after the intro window.
	get_tree().create_timer(18.0).timeout.connect(_ensure_player_control)

func _ensure_player_control() -> void:
	if player and "can_move" in player and not player.can_move \
			and GameManager.state == GameManager.GameState.PLAYING:
		_on_opening_finished()

func _on_opening_finished() -> void:
	GameManager.show_opening_sequence = false
	if player and "can_move" in player:
		player.can_move = true
		if player.has_method("grant_spawn_grace"):
			player.grant_spawn_grace()
	if hud and hud.has_method("show_intro_hint") and GameManager.current_region == "localhost":
		hud.show_intro_hint()
	# Let the player explore briefly; Claude dialogue starts on first interact.
	if SettingsManager.get_setting("music_enabled"):
		AudioManager.enable_music()
		AudioManager.play_music("explore_music")

func _load_region(region_id: String) -> void:
	if _current_region_node:
		_current_region_node.queue_free()
	_current_region_node = Node2D.new()
	_current_region_node.name = region_id
	region_container.add_child(_current_region_node)
	var data := RegionBuilder.build(_current_region_node, region_id)
	GameManager.region_spawn = data.spawn
	if player:
		player.global_position = data.spawn
		camera.enabled = true
		_apply_camera_bounds(data.get("size", Vector2.ZERO))
	_set_ambient(region_id)
	# Production greets you with an incident (once).
	if region_id == "production" and not EventManager.is_script_completed("production_incident"):
		call_deferred("_trigger_production_incident")
	# Corporate Enterprise greets you with a surprise live demo (once).
	if region_id == "corporate_enterprise" and not EventManager.is_script_completed("all_hands_demo"):
		call_deferred("_trigger_all_hands_demo")

func _trigger_production_incident() -> void:
	if not EventManager.has_active_event():
		EventManager.start_scripted("production_incident", preload("res://scripts/world/story_events.gd").production_incident())

func _trigger_all_hands_demo() -> void:
	if not EventManager.has_active_event():
		EventManager.start_scripted("all_hands_demo", preload("res://scripts/world/story_events.gd").all_hands_demo())

func _apply_camera_bounds(size: Vector2) -> void:
	if size == Vector2.ZERO:
		return
	# Clamp the camera to the room so empty off-map space is never shown.
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(size.x)
	camera.limit_bottom = int(size.y)

## Subtle bloom so the bright, emissive things (tokens, monitors, neon signs,
## projectiles, point lights) glow and the scene reads less flat/blocky. Tuned
## conservatively (high threshold, low intensity) so it never washes out.
func _setup_glow() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_strength = 1.0
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_scale = 2.0
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.7)
	env.set_glow_level(4, 0.4)
	var we := WorldEnvironment.new()
	we.name = "GlowEnvironment"
	we.environment = env
	add_child(we)

func _set_ambient(region_id: String) -> void:
	match region_id:
		"localhost":
			ambient.color = Color(0.72, 0.64, 0.66, 1.0)
		"production":
			ambient.color = Color(0.9, 0.5, 0.5, 1.0)
		"token_vault":
			ambient.color = Color(1.0, 0.95, 0.7, 1.0)
		"cloud_district":
			ambient.color = Color(0.7, 0.8, 1.0, 1.0)
		"gpu_mines":
			ambient.color = Color(1.0, 0.7, 0.5, 1.0)
		_:
			ambient.color = Color(0.85, 0.85, 0.95, 1.0)

func _on_region_changed(region_id: String) -> void:
	_load_region(region_id)
	QuestManager.on_region_entered(region_id)
	if player and player.has_method("grant_spawn_grace"):
		player.grant_spawn_grace(1.8)

func on_region_changed(region_id: String) -> void:
	_on_region_changed(region_id)

## Technical debt "breaks a dependency": a fresh bug crawls out near the player.
func _on_debt_incident(_kind: String) -> void:
	if not _current_region_node or not player:
		return
	var enemies := _current_region_node.get_node_or_null("Enemies")
	if not enemies:
		return
	var e = preload("res://scenes/combat/enemy.tscn").instantiate()
	e.enemy_type = "bug"
	e.max_hp = 16
	enemies.add_child(e)
	var ang := randf() * TAU
	e.global_position = player.global_position + Vector2(cos(ang), sin(ang)) * randf_range(180.0, 260.0)

func _on_player_died(_msg: String = "") -> void:
	get_tree().paused = false
	# Clear any transient overlay that could sit over the death screen and eat the
	# respawn click (e.g. a flavor popup that was open when you died).
	for n in hud.get_children():
		if n.name in ["FlavorPopup", "IntroHint"]:
			n.queue_free()
	# Idempotent: never stack death screens (see the player.died wiring note above).
	if hud.get_node_or_null("DeathScreen"):
		return
	var death_scene := preload("res://scenes/ui/death_screen.tscn")
	var death = death_scene.instantiate()
	death.name = "DeathScreen"
	hud.add_child(death)  # screen-space overlay (see _open_pause)

## Shows a full-screen overlay (victory/etc.) in the HUD's screen space.
func show_overlay(node: Node) -> void:
	hud.add_child(node)

## Pause is handled in _input (not _unhandled_input) because Escape also maps to
## ui_cancel, which a focused Control can swallow before it reaches
## _unhandled_input — that's why the menu-toggle keys worked but Esc didn't.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or event.is_echo():
		return
	# Don't hijack Escape while a modal popup, dialogue, or panel is up.
	if EventManager.has_active_event() or DialogueManager.is_active or UIManager.has_blocking_ui():
		return
	if GameManager.state == GameManager.GameState.PLAYING:
		_open_pause()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quest_log"):
		_toggle_quest_log()
	if event.is_action_pressed("dream_app"):
		_toggle_dream_app()
	if event.is_action_pressed("map"):
		_toggle_map()

func _open_pause() -> void:
	GameManager.pause_game(true)
	var pause := preload("res://scenes/ui/pause_menu.tscn").instantiate()
	# Overlays MUST live under the HUD CanvasLayer (screen space). Adding a
	# Control under the world Node2D renders it in world space at (0,0), so it
	# ends up off-screen wherever the camera is.
	hud.add_child(pause)

func _close_pause() -> void:
	GameManager.pause_game(false)
	for c in hud.get_children():
		if c.name == "PauseMenu":
			c.queue_free()

func _toggle_quest_log() -> void:
	_toggle_modal_panel("QuestLogPanel", preload("res://scenes/ui/quest_log.tscn"))

func _toggle_dream_app() -> void:
	_toggle_modal_panel("DreamAppPanel", preload("res://scenes/ui/dream_app_panel.tscn"))

func _toggle_map() -> void:
	_toggle_modal_panel("MapPanel", preload("res://scenes/ui/map_panel.tscn"))

func _toggle_modal_panel(panel_name: String, scene: PackedScene) -> void:
	var existing := hud.get_node_or_null(panel_name)
	if existing:
		existing.queue_free()
		return
	var panel := scene.instantiate()
	panel.name = panel_name
	if panel.has_method("register_modal"):
		panel.register_modal()
	elif panel is Control:
		panel.tree_exiting.connect(func(): UIManager.pop_modal())
		UIManager.push_modal()
	hud.add_child(panel)
