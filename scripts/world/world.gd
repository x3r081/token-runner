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

## --- Weather ---------------------------------------------------------------
##
## Every region gets AIR. Four overlay quads at most (one of them nearly always
## just the floor mottle), all self-lit and additive except the mottle, which
## only ever multiplies light AWAY in slow patches. Nothing here darkens or
## hazes the frame as a whole — light carves the dark, per VISUAL_BIBLE.
##
##   mottle  floor wear at two scales. The tile art tiles perfectly, which is
##           the problem: a 20x15 grid of identical 64px cells reads as graph
##           paper in the wide regions. Broad blotches give the ground history,
##           and an off-axis octave near the tile pitch lays down a texture the
##           eye cannot line up with the lattice. Honest about its limits: it
##           makes the grid stop being the dominant structure, it does not erase
##           a seam baked into the tile art — that fix lives in the floor
##           generator.
##   rays    god-ray shafts, angled and drifting, fading along their length.
##   air     motes: dust, ash, spores, data, gold — or rain, when streak = 1.
##   strobe  a rotating emergency beacon (Production only, and yes it has been
##           doing that for four hours).
##
## Comedy in the atmosphere, stated once so nobody softens it later:
## Corporate Enterprise is the ONLY region with no airborne anything. Facilities
## is the one budget that never got cut. The Cloud literally rains on you.
## Production's sprinklers went off during the incident and nobody has filed the
## ticket to turn them off, because the ticket would need an owner.
const Z_MOTTLE := -93
const Z_RAYS := 350
const Z_AIR := 380
const Z_STROBE := 392
const WEATHER := {
	"localhost": {
		"mottle": {"amount": 0.24, "tint": Vector3(1.0, 0.94, 0.88), "streak": 0.30},
		"rays": {"color": Color("#FFC46A"), "angle": 0.50, "density": 5.0,
			"intensity": 0.11, "reach": 0.55, "sharpness": 9.0, "bottom_fade": 0.55},
		"air": [{"color": Color("#FFDDB0"), "density": 12.0, "fall": 0.010,
			"drift": 0.03, "size": 0.20, "brightness": 0.34, "sparsity": 0.80,
			"twinkle": 0.55}],
	},
	"dependency_district": {
		"mottle": {"amount": 0.30, "tint": Vector3(0.94, 1.0, 0.94), "streak": 0.42},
		"rays": {"color": Color("#A8FF3E"), "angle": -0.35, "density": 6.0,
			"intensity": 0.09, "reach": 0.70, "sharpness": 8.0},
		"air": [{"color": Color("#B6FF6A"), "density": 11.0, "fall": 0.008,
			"drift": 0.05, "size": 0.22, "brightness": 0.26, "sparsity": 0.82}],
	},
	"stackoverflow_ruins": {
		"mottle": {"amount": 0.34, "tint": Vector3(1.0, 0.96, 0.88), "streak": 0.50},
		"rays": {"color": Color("#E8C46B"), "angle": 0.30, "density": 4.0,
			"intensity": 0.18, "reach": 1.10, "sharpness": 6.0, "bottom_fade": 0.85},
		"air": [{"color": Color("#E8D2A0"), "density": 14.0, "fall": 0.014,
			"drift": 0.04, "size": 0.22, "brightness": 0.38, "sparsity": 0.76,
			"fog": 0.05, "fog_color": Color("#6A5A44")}],
	},
	"api_bazaar": {
		"mottle": {"amount": 0.28, "tint": Vector3(1.0, 0.94, 1.0), "streak": 0.30},
		"rays": {"color": Color("#FF2D95"), "angle": 0.55, "density": 7.0,
			"intensity": 0.10, "reach": 0.60, "sharpness": 8.0},
		"air": [{"color": Color("#FFD34D"), "density": 10.0, "fall": 0.006,
			"drift": 0.06, "size": 0.24, "brightness": 0.30, "sparsity": 0.82,
			"fog": 0.06, "fog_color": Color("#52294A")}],
	},
	"cloud_district": {
		"mottle": {"amount": 0.20, "tint": Vector3(0.94, 0.97, 1.0), "streak": 0.25},
		"rays": {"color": Color("#CFE9FF"), "angle": 0.22, "density": 5.0,
			"intensity": 0.14, "reach": 1.00, "sharpness": 6.0},
		"air": [
			{"color": Color("#E8F4FF"), "density": 9.0, "fall": 0.006, "drift": 0.02,
				"size": 0.20, "brightness": 0.20, "sparsity": 0.86,
				"fog": 0.07, "fog_color": Color("#6BC7FF")},
			{"color": Color("#BFE4FF"), "density": 26.0, "fall": 0.55, "drift": 0.004,
				"size": 0.10, "brightness": 0.30, "sparsity": 0.90, "twinkle": 0.0,
				"streak": 1.0, "z": 700},
		],
	},
	"open_source_wildlands": {
		"mottle": {"amount": 0.32, "tint": Vector3(0.94, 1.0, 0.94), "streak": 0.45},
		"rays": {"color": Color("#8CFF9E"), "angle": -0.42, "density": 5.0,
			"intensity": 0.17, "reach": 1.00, "sharpness": 6.0},
		"air": [{"color": Color("#7CFFA4"), "density": 12.0, "fall": -0.006,
			"drift": 0.05, "size": 0.24, "brightness": 0.28, "sparsity": 0.80}],
	},
	"corporate_enterprise": {
		"mottle": {"amount": 0.16, "tint": Vector3(0.96, 0.97, 1.0), "streak": 0.18},
		"rays": {"color": Color("#BBD2FF"), "angle": 0.0, "density": 10.0,
			"intensity": 0.08, "reach": 1.40, "sharpness": 12.0, "bottom_fade": 0.90},
	},
	"gpu_mines": {
		"mottle": {"amount": 0.34, "tint": Vector3(1.0, 0.90, 0.86), "streak": 0.50},
		"air": [{"color": Color("#FF8A3C"), "density": 10.0, "fall": -0.030,
			"drift": 0.04, "size": 0.24, "brightness": 0.42, "sparsity": 0.80,
			"fog": 0.07, "fog_color": Color("#FF5A22")}],
	},
	"production": {
		"mottle": {"amount": 0.30, "tint": Vector3(1.0, 0.90, 0.90), "streak": 0.40},
		"strobe": {"color": Color("#FF3A44"), "period": 3.1, "intensity": 0.17,
			"sweep": 0.30, "beam": 18.0},
		"air": [{"color": Color("#FFD2CE"), "density": 22.0, "fall": 0.42,
			"drift": 0.004, "size": 0.10, "brightness": 0.22, "sparsity": 0.93,
			"twinkle": 0.0, "streak": 1.0, "z": 700}],
	},
	"token_vault": {
		"mottle": {"amount": 0.26, "tint": Vector3(1.0, 0.96, 0.86), "streak": 0.30},
		"rays": {"color": Color("#FFD34D"), "angle": 0.18, "density": 5.0,
			"intensity": 0.16, "reach": 1.10, "sharpness": 6.0},
		"air": [{"color": Color("#FFE79A"), "density": 12.0, "fall": -0.008,
			"drift": 0.03, "size": 0.22, "brightness": 0.40, "sparsity": 0.78,
			"fog": 0.05, "fog_color": Color("#6A4FA8")}],
	},
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
	# The stress grade tracks technical debt, so it has to hear about every
	# change — including the silent ones an upgrade purchase makes.
	ResourceManager.resource_changed.connect(_on_resource_changed)
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
	_build_atmosphere(region_id, data.get("size", Vector2.ZERO))
	if _star_mat:
		_star_mat.set_shader_parameter("accent_color", REGION_ACCENT.get(region_id, Color("#3D9BFF")))
	if _postfx and _postfx.has_method("set_region"):
		_postfx.set_region(region_id)
	_refresh_stress(true)
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

## --- atmosphere ------------------------------------------------------------

## Build this region's air. Parented to the region node, so travelling frees it
## with everything else and there is no state to reset.
##
## Layer order matters and is fixed by z_index, not by tree order:
##   -93 mottle  above the floor tiles (-100), the seams (-98) and the blotches
##               (-97), but BELOW the wayfinding chevrons (-92) and every prop:
##               the wear lands on the tiling and never on the guidance paint.
##               blend_mul — the one thing here that subtracts.
##   350 rays    above props, BELOW world labels (400+): shafts never wash out
##               text the player is trying to read.
##   380 air     motes and haze, also under the labels.
##   392 strobe  the beacon wash, still under the labels.
##   700 rain    in front of everything, because rain is.
##
## All four are pure-ALU fullscreen-ish quads with no textures, no allocations
## after build, and no per-frame CPU work; the viewport scissor means only
## on-screen pixels are ever shaded.
func _build_atmosphere(region_id: String, size: Vector2) -> void:
	if not _current_region_node or size == Vector2.ZERO:
		return
	var profile: Dictionary = WEATHER.get(region_id, {})
	if profile.is_empty():
		return
	var node := Node2D.new()
	node.name = "Atmosphere"
	_current_region_node.add_child(node)
	var aspect := Vector2(size.x / maxf(size.y, 1.0), 1.0)
	var wear_seed := float(absi(region_id.hash()) % 313)
	# Quality 0 keeps the floor breakup (it is one cheap multiply and it is what
	# stops the tiling from reading) and drops every lit layer.
	var quality := int(SettingsManager.get_setting("graphics_quality"))

	var mottle: Dictionary = profile.get("mottle", {})
	if not mottle.is_empty():
		_atmo_rect(node, "GroundMottle", "ground_mottle", size, Z_MOTTLE, {
			"amount": mottle.get("amount", 0.26),
			"floor_scale": mottle.get("floor_scale", 2.2),
			"detail_scale": mottle.get("detail_scale", 6.5),
			"streak": mottle.get("streak", 0.35),
			"darkest": mottle.get("darkest", 0.60),
			"tint": mottle.get("tint", Vector3(1.0, 1.0, 1.0)),
			"grit": mottle.get("grit", 0.60),
			"grit_scale": mottle.get("grit_scale", 26.0),
			# Off-axis by a different amount in every region, so the texture that
			# fights the tile lattice is never the same texture twice.
			"grit_rot": 0.30 + fmod(wear_seed * 0.017, 0.95),
			"aspect": aspect,
			"seed": wear_seed,
		})
	if quality < 1:
		return

	var rays: Dictionary = profile.get("rays", {})
	if not rays.is_empty():
		_atmo_rect(node, "GodRays", "god_rays", size, Z_RAYS, {
			"ray_color": rays.get("color", Color("#CFE9FF")),
			"angle": rays.get("angle", 0.3),
			"density": rays.get("density", 6.0),
			"speed": rays.get("speed", 0.14),
			"intensity": rays.get("intensity", 0.2),
			"reach": rays.get("reach", 0.9),
			"sharpness": rays.get("sharpness", 7.0),
			"bottom_fade": rays.get("bottom_fade", 0.72),
			"aspect": aspect,
		})

	var strobe: Dictionary = profile.get("strobe", {})
	if not strobe.is_empty():
		_atmo_rect(node, "AlarmWash", "strobe_wash", size, Z_STROBE, {
			"wash_color": strobe.get("color", Color("#FF3A44")),
			"period": strobe.get("period", 3.1),
			"intensity": strobe.get("intensity", 0.18),
			"sweep_speed": strobe.get("sweep", 0.32),
			"beam_width": strobe.get("beam", 16.0),
			"edge_bias": strobe.get("edge_bias", 0.55),
			"beacon": strobe.get("beacon", Vector2(0.5, 0.16)),
			"aspect": aspect,
		})

	var layers: Array = profile.get("air", [])
	var idx := 0
	for layer: Dictionary in layers:
		_atmo_rect(node, "Air%d" % idx, "air_particles", size, int(layer.get("z", Z_AIR)), {
			"mote_color": layer.get("color", Color("#E8F4FF")),
			"fog_color": layer.get("fog_color", Color("#3D9BFF")),
			"fog_amount": layer.get("fog", 0.0),
			"density": layer.get("density", 12.0),
			"fall_speed": layer.get("fall", 0.01),
			"drift": layer.get("drift", 0.03),
			"streak": layer.get("streak", 0.0),
			"mote_size": layer.get("size", 0.22),
			"twinkle": layer.get("twinkle", 0.7),
			"brightness": layer.get("brightness", 0.32),
			"sparsity": layer.get("sparsity", 0.80),
			"aspect": aspect,
			"seed": wear_seed + float(idx) * 17.0,
		})
		idx += 1

## One atmosphere quad. Silently does nothing when the shader is missing, so a
## half-shipped shader folder degrades to "no weather" rather than to a crash.
func _atmo_rect(parent: Node2D, rect_name: String, shader_file: String, size: Vector2, z: int, params: Dictionary) -> void:
	var path := "res://assets/shaders/%s.gdshader" % shader_file
	if not ResourceLoader.exists(path):
		return
	var r := ColorRect.new()
	r.name = rect_name
	r.position = Vector2.ZERO
	r.size = size
	r.z_index = z
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	for key: String in params:
		mat.set_shader_parameter(key, params[key])
	r.material = mat
	parent.add_child(r)

## --- stress grade ----------------------------------------------------------

func _on_resource_changed(res_name: String, _old: float, _new: float) -> void:
	if res_name == "technical_debt":
		_refresh_stress(false)

## Comedy through cinematography: below the safe debt threshold the frame is
## clean, and from there to catastrophic it slowly loses its composure —
## saturation drains except in the reds, the corners heat up and breathe, the
## grain thickens, and eventually the odd scanline slips sideways. The joke only
## works because the number driving it is real (GameManager.DEBT_SAFE_THRESHOLD).
func _refresh_stress(snap: bool) -> void:
	if not _postfx or not _postfx.has_method("set_stress"):
		return
	var debt := ResourceManager.get_value("technical_debt")
	var stress := clampf((debt - 20.0) / 70.0, 0.0, 1.0)
	_postfx.set_stress(stress, 0.0 if snap else 1.4)

func _on_region_changed(region_id: String) -> void:
	_load_region(region_id)
	QuestManager.on_region_entered(region_id)
	if player and player.has_method("grant_spawn_grace"):
		player.grant_spawn_grace(1.8)

func on_region_changed(region_id: String) -> void:
	_on_region_changed(region_id)

## Technical debt "breaks a dependency": a fresh bug crawls out near the player.
func _on_debt_incident(_kind: String) -> void:
	# One short red wash so the incident is felt before it is seen. The bug is
	# already crawling toward you; this is just the moment the room notices.
	if _postfx and _postfx.has_method("pulse"):
		_postfx.pulse(Color("#FF4757"), 0.20, 0.5)
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

func _on_player_died(msg: String = "") -> void:
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
	# Prefer the actual cause of death over the death screen's random pool line —
	# "the agent deleted the database" beats a generic quip. Must come after
	# add_child so the screen's _ready has resolved its labels. Idempotent, and a
	# no-op for an empty msg, so the pool line still shows when we have no cause.
	death._set_message(msg)

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
