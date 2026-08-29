extends Node2D

const _CameraFX := preload("res://scripts/world/camera_fx.gd")
const _PostFXLayer := preload("res://scripts/world/postfx_layer.gd")

## VISUAL_BIBLE per-region palette: starfield accent (primary neon) and the
## CanvasModulate ambience. Dark enough that the lights do the talking.
const REGION_ACCENT := {
	"localhost": Color("#FFB74A"),
	"dependency_district": Color("#A8FF3E"),
	"stackoverflow_ruins": Color("#E8C46B"),
	"api_bazaar": Color("#FF2D95"),
	"cloud_district": Color("#6BC7FF"),
	"open_source_wildlands": Color("#58E07C"),
	"corporate_enterprise": Color("#4D7CFF"),
	"gpu_mines": Color("#FF6B2D"),
	"production": Color("#FF4757"),
	"token_vault": Color("#FFD34D"),
}
const REGION_AMBIENT := {
	"localhost": Color(0.95, 0.9, 1.03),
	"dependency_district": Color(0.82, 0.95, 0.82),
	"stackoverflow_ruins": Color(0.92, 0.87, 0.77),
	"api_bazaar": Color(0.95, 0.79, 0.98),
	"cloud_district": Color(0.95, 1.03, 1.05),
	"open_source_wildlands": Color(0.82, 1.0, 0.87),
	"corporate_enterprise": Color(0.9, 0.95, 1.05),
	"gpu_mines": Color(1.03, 0.77, 0.69),
	"production": Color(1.05, 0.74, 0.77),
	"token_vault": Color(0.98, 0.9, 0.74),
}

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Player/Camera2D
@onready var region_container: Node2D = $RegionContainer
@onready var hud: CanvasLayer = $HUD
@onready var ambient: CanvasModulate = $AmbientLight

var _current_region_node: Node2D
var _postfx: CanvasLayer
var _starfield: ColorRect
var _star_mat: ShaderMaterial
var _ambient_tween: Tween
var _first_ambient := true

func _ready() -> void:
	GameManager.state = GameManager.GameState.PLAYING
	_setup_glow()
	_setup_postfx()
	_setup_starfield()
	_setup_camera_fx()
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
	_recenter_starfield(data.get("size", Vector2.ZERO))
	if _star_mat:
		_star_mat.set_shader_parameter("accent_color", REGION_ACCENT.get(region_id, Color("#3D9BFF")))
	if _postfx and _postfx.has_method("set_region"):
		_postfx.set_region(region_id)
	_region_flourish()
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

## Cinematic bloom so the bright, emissive things (tokens, monitors, neon signs,
## projectiles, point lights) actually GLOW. Wide multi-level spread with a
## slightly eager HDR threshold — carves light out of the dark without
## white-washing the frame (per VISUAL_BIBLE).
func _setup_glow() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_strength = 1.0
	env.glow_bloom = 0.08
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.set_glow_level(1, 0.5)
	env.set_glow_level(2, 0.9)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.4)
	env.set_glow_level(5, 0.18)
	var we := WorldEnvironment.new()
	we.name = "GlowEnvironment"
	we.environment = env
	add_child(we)

## Full-screen grade/vignette/grain layer. Sits at CanvasLayer 0 — above the
## world canvas, below every UI layer — so menus stay crisp.
func _setup_postfx() -> void:
	_postfx = _PostFXLayer.new()
	_postfx.name = "PostFXLayer"
	add_child(_postfx)

## The void outside rooms: a huge parallax starfield instead of dead black.
## Scroll is bound to the camera each frame (one uniform write, that's all).
func _setup_starfield() -> void:
	_starfield = ColorRect.new()
	_starfield.name = "Starfield"
	_starfield.size = Vector2(12000, 12000)
	_starfield.z_index = -200  # well under the floor tiles (-100)
	_starfield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_starfield.color = Color("#05060E")  # VOID — the fallback is still on-palette
	if ResourceLoader.exists("res://assets/shaders/starfield.gdshader"):
		_star_mat = ShaderMaterial.new()
		_star_mat.shader = load("res://assets/shaders/starfield.gdshader")
		_star_mat.set_shader_parameter("base_color", Color("#05060E"))
		_starfield.material = _star_mat
	else:
		set_process(false)  # nothing to scroll, nothing to do per frame
	add_child(_starfield)
	_recenter_starfield(Vector2.ZERO)

## Trauma shake + zoom punches, attached to the player's camera at runtime so
## the player scene stays untouched. Combat code finds it via group "camera_fx".
func _setup_camera_fx() -> void:
	if not camera:
		return
	var fx := _CameraFX.new()
	fx.name = "CameraFX"
	camera.add_child(fx)

func _process(_delta: float) -> void:
	# Starfield parallax: one cheap uniform write; the shader does the rest.
	if _star_mat and is_instance_valid(camera):
		_star_mat.set_shader_parameter("scroll", camera.global_position * 0.05)

func _recenter_starfield(region_size: Vector2) -> void:
	if not _starfield:
		return
	var center := region_size * 0.5 if region_size != Vector2.ZERO else Vector2(640.0, 480.0)
	_starfield.position = center - _starfield.size * 0.5

## Region-entry flourish: 0.4s curtain-up plus a slight zoom settle. Cosmetic
## only — input stays live and the opening sequence (layer 100) sits far above.
func _region_flourish() -> void:
	if _postfx and _postfx.has_method("fade_from_black"):
		_postfx.fade_from_black(0.4)
	var fx := get_tree().get_first_node_in_group("camera_fx")
	if fx and fx.has_method("region_settle"):
		fx.region_settle()

## Tween the room's mood lighting to the region's ambient tint (VISUAL_BIBLE
## table). First call snaps so the game never boots mid-crossfade.
func _set_ambient(region_id: String) -> void:
	var target: Color = REGION_AMBIENT.get(region_id, Color(0.95, 0.95, 1.0))
	if _ambient_tween and _ambient_tween.is_valid():
		_ambient_tween.kill()
	if _first_ambient:
		_first_ambient = false
		ambient.color = target
		return
	_ambient_tween = create_tween()
	_ambient_tween.tween_property(ambient, "color", target, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

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
