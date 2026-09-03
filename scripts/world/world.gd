extends Node2D

const _CameraFX := preload("res://scripts/world/camera_fx.gd")
const _PostFXLayer := preload("res://scripts/world/postfx_layer.gd")

## Generated-texture root. Same string region_builder.gd and localhost_builder.gd
## use; kept local rather than reached for across classes so a parse error in one
## builder cannot take the world scene down with it.
const GEN := "res://assets/textures/generated/"

## VISUAL_BIBLE_V2 LAW 2 — the ACCENT column, verbatim. One neon per region.
## Consumed by the starfield's nebula trace and by anything that asks the world
## what colour this room is.
##
## localhost moved from #FFB74A to #24F0DC this round: amber is localhost's WARM
## (the desk lamp, the monitors), not its accent, and having the two swapped is
## why the apartment came out of round 5 as one orange room.
const REGION_ACCENT := {
	"localhost": Color("#24F0DC"),
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
## The CanvasModulate. LAW 3 says only five things may be bright, and the way a
## frame actually enforces that is by putting everything ELSE below full value:
## round 5 ran this multiplier at 0.95-1.05, i.e. the ambient did nothing and
## every prop in the room was as bright as the player.
##
## These sit around 0.78 mean with a small lean toward the region's BASE hue, so
## unlit set dressing loses roughly a fifth of its value and the motivated lights
## (LAW 4: <= 6 PointLight2D) are what carve shape out of the room. Deliberately
## NOT darker than that: the floor still has to be readable ground (LAW 6).
##
## ROUND 12 — THE LUMINANCE REGRESSION. Round 11 deleted about twenty light pools
## (correctly: they were unmotivated fill, and critique (f) counted them), and the
## floors went with them. Measured on the bare tile in the QA captures: 35.2 in
## the API Bazaar, 46.9 in Localhost and the GPU Mines, 48.3 in Production, 35-61
## across the set — against LAW 6's 64-84. The room stopped being underlit and
## started being unreadable.
##
## The lever is THIS TABLE, not the pools. A pool is a puddle with an edge in one
## place; the ambient is the exposure of the whole room, and the whole room is
## what came out dark. Every entry is its round-11 value multiplied by a scalar,
## so the HUE of each region is exactly what it was — the lean toward BASE, the
## channel ordering and the relative chroma are all preserved by construction:
##
##   x1.25  the eight regions measuring 48-61
##   x1.32  localhost / gpu_mines / production, measuring 46.9-48.3
##   x1.45  api_bazaar, the darkest floor in the game at 35.2
##
## Channels above 1.0 are deliberate and correct: a CanvasModulate multiplies, so
## the only way to lift a floor that the tile art already draws at #4C3244 is to
## push the multiplier past unity. Nothing here is a colour the player sees; it is
## an exposure.
##
## gpu_mines carries one more move on top of its x1.32 — see critique #8 below.
const REGION_AMBIENT := {
	"localhost": Color(1.003, 0.977, 1.135),
	"dependency_district": Color(0.900, 1.025, 0.925),
	"stackoverflow_ruins": Color(1.050, 0.988, 0.875),
	# ROUND 12 VERIFICATION: this was x1.45 (1.218, 1.044, 1.218), calibrated
	# against a QA frame that measured 41.4 — the darkest floor in the game. But
	# the SAME round rebuilt that floor: the 2px-pitch herringbone became 32px
	# flagstone authored at ~69 mean luminance. The exposure lift and the material
	# rebuild were two fixes for one symptom, and shipping both double-counted it:
	# the recaptured frame measures 76.7, over LAW 6's window rather than under it.
	# Back to the x1.25 every other region gets, off the same round-11 base
	# (0.840, 0.720, 0.840). Pure scalar, so the hue is untouched.
	"api_bazaar": Color(1.050, 0.900, 1.050),
	"cloud_district": Color(0.950, 1.025, 1.125),
	"open_source_wildlands": Color(0.900, 1.050, 0.950),
	"corporate_enterprise": Color(0.925, 0.988, 1.100),
	# ROUND 12, critique #8: "orange ambient saturates 12% of the frame". The x1.32
	# exposure lift would have been (1.162, 0.950, 0.871) — a 0.29 spread between
	# the hottest and coldest channel, i.e. an orange cast on every unlit pixel in
	# the mines, in a region whose ACCENT, WARM and enemy tells are all already
	# red-orange. This is that colour lerped 30% toward its own luminance: same
	# value, 30% less chroma, so the room still reads hot and the floor stops
	# being a colour.
	"gpu_mines": Color(1.115, 0.967, 0.911),
	"production": Color(1.162, 0.924, 0.924),
	# x1.21, not x1.25: the vault's gold plate already measures 61.7 in the QA
	# capture — the brightest floor in the game — and the full lift would have put
	# it at 77, over the top of LAW 6's 64-84 window rather than inside it.
	"token_vault": Color(1.041, 0.968, 0.823),
}

## --- atmosphere ------------------------------------------------------------
##
## VISUAL_BIBLE_V2 LAW 4 gives a region ONE ambient particle layer, and LAW 9
## says nothing else moves at rest. Round 5 had, per region: a two-scale floor
## mottle, angled god-ray shafts, one or two mote fields in the region's own
## hue, a rotating emergency beacon, and an irregular gust driver rewriting all
## of their uniforms 20 times a second. Deleted this round, in that order —
##
##   mottle  LAW 4 says floor overlays: ZERO. "Wear fields", "blotches" and
##           "grit" are texture noise, not readable ground (LAW 6). The floor is
##           the tile art. (region_builder.gd and localhost_builder.gd lay down
##           their own ground_mottle passes; those are theirs to remove.)
##   rays    a lit shaft over the whole room is a light source with no fixture,
##           and ten regions of them is ten more hues. god_rays.gdshader is gone
##           from the repo — nothing else loaded it.
##   strobe  a full-frame red wash on a 3.1s cycle in the one region the player
##           is most likely to be fighting in. strobe_wash.gdshader is gone too.
##   gusts   the whole surge system: it existed to keep the air from looking
##           looped, which is a problem you only have when there is too much air.
##
## What is left is ONE dust layer, the same in every region: TEXT_DIM, slow, no
## twinkle, roughly a dozen visible motes. It is the same air in every room
## because it is the same building, and because the third saturated hue in a
## frame should never be the dust.
const Z_AIR := 380
## LAW 4: "one ambient dust layer (<= 16 particles, slow, TEXT_DIM at 25%
## alpha)". air_particles.gdshader draws three internal parallax depths off one
## density figure, so `sparsity` (the fraction of grid cells left EMPTY) is the
## knob that sets the count: at 0.965 the three depths together put about a
## dozen motes on screen. `twinkle` 0 because a twinkling mote is motion at
## rest, and `brightness` 0.14 because this is the quietest thing in the frame.
const AIR := {
	"color": Color("#7C8BB0"),   # TEXT_DIM
	"density": 6.0,
	"fall": 0.007,
	"drift": 0.018,
	"size": 0.16,
	"brightness": 0.14,
	"sparsity": 0.965,
	"twinkle": 0.0,
}

## --- ambient life ----------------------------------------------------------
##
## LAW 3 allows at most TWO motivated light sources per frame, and LAW 9 allows
## a light to flicker +/- 6%. That is the entire budget, and this table is now
## the entire feature: `fixtures` wall lamps (a dim body with one lit core and a
## soft pool under it) at `energy`, in the region's WARM or ACCENT.
##
## Deleted this round: the drifting "passes" (a moving additive glow with two
## nav lights — a light source with no source, crossing the room forever, which
## is motion at rest in the most literal way available), and the "bars" machinery
## readouts (six additive cells with a running light, i.e. an animated prop that
## nothing depends on reading). Also gone: the ballast stutter that dropped a
## fixture to 40% of its energy at random, which read as a rendering fault.
const AMBIENT_LIFE := {
	"localhost": {"hue": Color("#FFB74A"), "fixtures": 2, "energy": 0.55},
	"dependency_district": {"hue": Color("#E08A3C"), "fixtures": 2, "energy": 0.45},
	"stackoverflow_ruins": {"hue": Color("#C97B4A"), "fixtures": 2, "energy": 0.45},
	"api_bazaar": {"hue": Color("#FFD34D"), "fixtures": 2, "energy": 0.50},
	"cloud_district": {"hue": Color("#E8F4FF"), "fixtures": 1, "energy": 0.45},
	"open_source_wildlands": {"hue": Color("#C9A24A"), "fixtures": 2, "energy": 0.45},
	"corporate_enterprise": {"hue": Color("#93A7C8"), "fixtures": 2, "energy": 0.40},
	# ONE fixture in the mines (critique #8, "orange ambient saturates 12% of the
	# frame"). The room already spends its motivated light on the heat pit —
	# region_builder's one real PointLight2D, at full 0.9 energy in ember — so a
	# second and third amber lamp on the walls made three orange sources in a
	# region that is meant to have two, and the pit is the one worth keeping.
	"gpu_mines": {"hue": Color("#FF6B2D"), "fixtures": 1, "energy": 0.55},
	"production": {"hue": Color("#FFB020"), "fixtures": 2, "energy": 0.50},
	"token_vault": {"hue": Color("#FFD34D"), "fixtures": 2, "energy": 0.50},
}

## THE PIXEL STAGE (VISUAL_BIBLE_V2 LAW 1). The world renders into a fixed
## 640x360 SubViewport blitted at an integer scale K; see pixel_stage.gd for why.
## Everything WORLD-space lives under `stage_view`; everything SCREEN-space (HUD,
## dialogue, popups) stays a direct child of World so `world.get_node("HUD")` and
## every UI path in the project still resolve. The two are joined by exactly two
## things: `world_rect`, which the UI layers are fitted into, and
## `PixelStage.world_to_ui()`, which is how the objective chevron finds a target.
@onready var stage: PixelStage = $PixelStage
@onready var stage_view: SubViewport = $PixelStage/Viewport
@onready var player: CharacterBody2D = $PixelStage/Viewport/Player
@onready var camera: Camera2D = $PixelStage/Viewport/Player/Camera2D
@onready var region_container: Node2D = $PixelStage/Viewport/RegionContainer
@onready var hud: CanvasLayer = $HUD
@onready var ambient: CanvasModulate = $PixelStage/Viewport/AmbientLight

var _current_region_node: Node2D
var _postfx: CanvasLayer
var _starfield: ColorRect
var _star_mat: ShaderMaterial
var _ambient_tween: Tween
var _first_ambient := true

## Ambient life. Parallel arrays instead of dictionaries so the per-frame walk
## touches floats and nodes only. Two fixtures at most, so these are short.
var _life_lights: Array[PointLight2D] = []
var _life_bulbs: Array[ColorRect] = []
var _life_energy: PackedFloat32Array = PackedFloat32Array()
var _life_seed: PackedFloat32Array = PackedFloat32Array()
var _life_t := 0.0
var _life_tick := 0.0
var _soft_tex: Texture2D
var _life_add_mat: CanvasItemMaterial

## Screen-space CanvasLayers that were created INSIDE the stage and had to be
## moved out of it (see `_adopt_layer`), paired with the node that made them.
var _adopted: Array = []
var _adopted_hosts: Array = []

func _ready() -> void:
	GameManager.state = GameManager.GameState.PLAYING
	stage.stage_changed.connect(_on_stage_changed)
	# A CanvasLayer is screen space, but "screen" for a node inside the stage is
	# 640x360 — and boss_hud.gd (a CanvasLayer parented to the boss) lays its card
	# out in HUD units. Catch them as they appear rather than naming them.
	get_tree().node_added.connect(_on_node_added)
	_setup_glow()
	_setup_postfx()
	_setup_starfield()
	_setup_camera_fx()
	_fit_ui()
	_load_region(GameManager.current_region)
	QuestManager.on_region_entered(GameManager.current_region)
	GameManager.region_changed.connect(_on_region_changed)
	GameManager.player_died.connect(_on_player_died)
	GameManager.debt_incident.connect(_on_debt_incident)
	# Debt pressure has to hear about every change — including the silent ones
	# an upgrade purchase makes.
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

## --- the pixel stage -------------------------------------------------------

## Re-fit every screen-space layer whenever the letterbox moves (window resize,
## and once at startup). Each layer's root Controls are re-anchored onto the
## world's rect; see pixel_stage.gd for why that is a re-layout and not a
## transform.
func _on_stage_changed(_rect: Rect2) -> void:
	_fit_ui()

func _fit_ui() -> void:
	if stage == null:
		return
	for c in get_children():
		if c is CanvasLayer and c != _postfx:
			stage.fit_layer(c)
	var guide := UIManager.guide() if UIManager.has_method("guide") else null
	if guide is CanvasLayer:
		stage.fit_layer(guide)

## The guide overlay is an autoload's child: it outlives this scene, so the
## world's letterbox must not follow it into the main menu.
func _exit_tree() -> void:
	var guide := UIManager.guide() if UIManager.has_method("guide") else null
	if guide is CanvasLayer:
		PixelStage.reset_layer(guide)

## A CanvasLayer born inside the stage renders against a 640x360 "screen", which
## is not the space any of this project's HUD code is written in (boss_hud.gd
## centres a 720px band; ability_fx.gd's death red-out wants the whole frame).
## Move it out to World and fit it like every other UI layer. Deferred, because
## `node_added` fires BEFORE the node's own `_ready`, and boss_hud.gd reads its
## parent there to find the boss it belongs to.
func _on_node_added(n: Node) -> void:
	if n is CanvasLayer:
		call_deferred("_adopt_layer", n)
	elif n is Control and n.get_parent() is CanvasLayer:
		call_deferred("_fit_late_control", n)
	elif n is CanvasItem and n.get_parent() == self:
		call_deferred("_reclaim_world_child", n)

## A ROOT CONTROL THAT ARRIVES AFTER THE FIT STILL HAS TO BE IN THE WORLD.
##
## Since the fit re-anchors root Controls instead of scaling their layer
## (pixel_stage.gd), a panel mounted on the HUD later — the pause menu, the death
## screen, [J], [B], [M], a toast lane, a scrim — no longer inherits the
## letterbox from its parent: it would anchor to the WINDOW, which on the 3840
## screen is 1280px of empty desktop away from the room it belongs to. Deferred,
## so the panel's own `_ready` (which is where every one of them sets its anchors
## and calls `place_centred`) has finished first.
func _fit_late_control(c: Node) -> void:
	if not is_instance_valid(c) or stage == null or not is_inside_tree():
		return
	var ctrl := c as Control
	if ctrl == null or not ctrl.is_inside_tree():
		return
	var layer := ctrl.get_parent() as CanvasLayer
	if layer == null or not layer.has_meta(PixelStage.LAYER_META):
		return
	stage.fit_control(ctrl)

## The mirror image of _adopt_layer. A handful of nodes in the project spawn
## WORLD-space visuals into `get_tree().current_scene` — token_pickup.gd's "+5"
## float being the live one — which is this Node2D, and this Node2D now sits
## OUTSIDE the stage. Left there they draw at their world coordinates in window
## space: a "+5" at world (630,460) lands 630px from the left edge of the WINDOW,
## nowhere near the token. Anything world-space that arrives on World is put back
## where it belongs, in the viewport that has the camera.
##
## Excluded: the stage itself, and anything screen-space (CanvasLayer, handled
## above; Controls that world.gd/show_overlay parent to the HUD never land here).
func _reclaim_world_child(n: Node) -> void:
	if not is_instance_valid(n) or n == stage or not is_inside_tree():
		return
	if n.get_parent() != self or n is CanvasLayer:
		return
	remove_child(n)
	stage_view.add_child(n)

func _adopt_layer(l: CanvasLayer) -> void:
	if not is_instance_valid(l) or l == _postfx or not is_inside_tree():
		return
	if l.get_viewport() != stage_view:
		return
	var host := l.get_parent()
	if host == null:
		return
	host.remove_child(l)
	add_child(l)
	_adopted.append(l)
	_adopted_hosts.append(host)
	stage.fit_layer(l)

## An adopted layer is no longer parented to the thing that made it, so a region
## change (which frees the whole region, boss included) would otherwise leave its
## card hanging on the screen. Deferred from _load_region, i.e. after the old
## region node is actually gone.
func _purge_adopted() -> void:
	for i in range(_adopted.size() - 1, -1, -1):
		var l = _adopted[i]
		var host = _adopted_hosts[i]
		if not is_instance_valid(l):
			_adopted.remove_at(i)
			_adopted_hosts.remove_at(i)
			continue
		if not _host_is_gone(host as Node):
			continue
		_adopted.remove_at(i)
		_adopted_hosts.remove_at(i)
		(l as Node).queue_free()

## THE SWEEP COULD NOT SEE THE FREEING IT EXISTS TO CATCH.
##
## `_load_region` calls `_current_region_node.queue_free()` and then
## `call_deferred("_purge_adopted")`. MessageQueue flushes BEFORE SceneTree
## flushes its delete queue, so when the sweep ran the old region node was still
## alive AND every descendant of it — the boss that owns a boss_hud, the player
## that owns an ability_fx layer — was still `is_instance_valid()` and still
## `is_inside_tree()`. Every adopted layer passed the test, and one frame later
## its host was gone and the layer was orphaned on World forever. That is the
## mechanism behind the stale boss card that survived a region change.
##
## `queue_free()` flags only the node it is called on, not its children, so
## asking the host itself is not enough either: the walk up the parent chain is
## what turns "my region is being torn down" into an answer this sweep can read
## on the frame it is asked.
static func _host_is_gone(host: Node) -> bool:
	if not is_instance_valid(host):
		return true
	if not host.is_inside_tree():
		return true
	var n: Node = host
	while n != null:
		if n.is_queued_for_deletion():
			return true
		n = n.get_parent()
	return false

func _start_opening_sequence() -> void:
	var intro := preload("res://scenes/ui/opening_sequence.tscn").instantiate()
	add_child(intro)
	if intro is CanvasLayer and stage:
		stage.fit_layer(intro)
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
	_build_life(region_id, data.get("size", Vector2.ZERO))
	if _star_mat:
		_star_mat.set_shader_parameter("accent_color", REGION_ACCENT.get(region_id, Color("#3D9BFF")))
	if _postfx and _postfx.has_method("set_region"):
		_postfx.set_region(region_id)
	_refresh_stress(true)
	_region_flourish()
	call_deferred("_purge_adopted")
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

## The game's ONLY bloom pass. LAW 5: threshold 1.0 (so a pixel has to be
## genuinely overbright, not merely light-coloured, to glow at all), two levels
## maximum, intensity <= 0.45, bloom 0.
##
## Round 5 ran five levels up to mip 5 at intensity 0.62 with glow_bloom 0.08 —
## a wide, additive haze that found every pale surface in the room, which is how
## a frame ends up with a portal, a monitor bank, a sign, a crate and the floor
## all wearing the same halo. Levels 2 and 3 only: a tight skirt on the five
## things LAW 3 allows to be bright, and nothing on anything else. glow_bloom is
## 0 because it is an unconditional lift applied BEFORE the threshold — it is
## the setting that lets sub-threshold pixels bloom anyway.
##
## Every level is written explicitly: Godot's Environment defaults are not all
## zero (3 and 5 are on), so an unwritten level is a level you did not choose.
func _setup_glow() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.42
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	# set_glow_level() is 0-indexed (0..6 == the inspector's glow_levels/1..7);
	# range(1, 8) walked off the end and threw every time the world was built.
	for level: int in range(0, 7):
		env.set_glow_level(level, 0.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.5)
	var we := WorldEnvironment.new()
	we.name = "GlowEnvironment"
	we.environment = env
	# INSIDE the stage. The SubViewport owns its World3D, so this Environment
	# applies to the 640x360 world render and to nothing else: the bloom happens
	# before the blit, at the resolution the art was drawn for, and the main
	# viewport (which carries the HUD) has no environment at all.
	stage_view.add_child(we)

## Full-screen grade/vignette/grain layer. Sits at CanvasLayer 0 — above the
## world canvas, below every UI layer — so menus stay crisp.
func _setup_postfx() -> void:
	_postfx = _PostFXLayer.new()
	_postfx.name = "PostFXLayer"
	# Inside the stage: the grade and the region curtain belong to the WORLD, and
	# a screen-reading pass has to run at the resolution it is grading. It is
	# excluded from _adopt_layer for exactly that reason.
	stage_view.add_child(_postfx)

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
		# Near-black base, and every uniform seeded (an unset parameter reads
		# back as null). The shader itself cut its star count to ~35% of round 5
		# and dropped the accent-coloured layer, so `density` stays at 1.0 —
		# the thinning is authored, not dialled.
		_star_mat.set_shader_parameter("base_color", Color("#05060E"))
		_star_mat.set_shader_parameter("accent_color", Color("#3D9BFF"))
		_star_mat.set_shader_parameter("scroll", Vector2.ZERO)
		_star_mat.set_shader_parameter("density", 1.0)
		_starfield.material = _star_mat
	# NOTE: _process is NOT disabled when the starfield shader is missing — the
	# ambient-life flicker also lives in there, and a missing starfield used to
	# silently freeze the whole world's lighting.
	stage_view.add_child(_starfield)
	_recenter_starfield(Vector2.ZERO)

## Trauma shake + zoom punches, attached to the player's camera at runtime so
## the player scene stays untouched. Combat code finds it via group "camera_fx".
func _setup_camera_fx() -> void:
	if not camera:
		return
	var fx := _CameraFX.new()
	fx.name = "CameraFX"
	camera.add_child(fx)

func _process(delta: float) -> void:
	# Starfield parallax: one cheap uniform write; the shader does the rest.
	if _star_mat and is_instance_valid(camera):
		_star_mat.set_shader_parameter("scroll", camera.global_position * 0.05)
	_drive_life(delta)

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

## Build this region's air: ONE dust quad, parented to the region node, so
## travelling frees it with everything else and there is no state to reset.
##
## z 380 sits above the props and below the world labels (400+), so the dust
## never lands on text the player is trying to read. It is a pure-ALU quad with
## no textures and no per-frame CPU work; the viewport scissor means only
## on-screen pixels are ever shaded. Quality 0 skips it entirely — with the
## mottle, the rays and the strobe gone there is nothing else in here to keep.
func _build_atmosphere(region_id: String, size: Vector2) -> void:
	if not _current_region_node or size == Vector2.ZERO:
		return
	if int(SettingsManager.get_setting("graphics_quality")) < 1:
		return
	var node := Node2D.new()
	node.name = "Atmosphere"
	_current_region_node.add_child(node)
	var aspect := Vector2(size.x / maxf(size.y, 1.0), 1.0)
	_atmo_rect(node, "Air0", "air_particles", size, Z_AIR, {
		"mote_color": AIR["color"],
		"fog_color": AIR["color"],
		"fog_amount": 0.0,
		"density": AIR["density"],
		"fall_speed": AIR["fall"],
		"drift": AIR["drift"],
		"streak": 0.0,
		"mote_size": AIR["size"],
		"twinkle": AIR["twinkle"],
		"brightness": AIR["brightness"],
		"sparsity": AIR["sparsity"],
		"aspect": aspect,
		# Stable per-region offset so two regions do not deal the same field.
		"seed": float(absi(region_id.hash()) % 313),
	})

## One atmosphere quad. Silently does nothing when the shader is missing, so a
## half-shipped shader folder degrades to "no air" rather than to a crash.
## Returns the material for the caller; every uniform it touches is seeded here
## first (Godot will not read back a shader parameter that was never set, even
## one with a default in the .gdshader).
func _atmo_rect(parent: Node2D, rect_name: String, shader_file: String, size: Vector2, z: int, params: Dictionary) -> ShaderMaterial:
	var path := "res://assets/shaders/%s.gdshader" % shader_file
	if not ResourceLoader.exists(path):
		return null
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
	return mat

## --- ambient life ----------------------------------------------------------

## Build this region's wall fixtures. Parented to the region node, so travelling
## frees them with everything else and there is no state to reset beyond the
## parallel arrays cleared at the top.
func _build_life(region_id: String, size: Vector2) -> void:
	_life_lights.clear()
	_life_bulbs.clear()
	_life_energy.clear()
	_life_seed.clear()
	if not _current_region_node or size == Vector2.ZERO:
		return
	var cfg: Dictionary = AMBIENT_LIFE.get(region_id, {})
	if cfg.is_empty():
		return
	if int(SettingsManager.get_setting("graphics_quality")) < 1:
		return
	var root := Node2D.new()
	root.name = "AmbientLife"
	root.y_sort_enabled = false
	_current_region_node.add_child(root)
	var hue: Color = cfg.get("hue", Color("#FFB74A"))
	_build_life_fixtures(root, cfg, hue, size)

## Wall lamps: a dark body, one lit core pixel-block, and a wide soft pool on
## the floor under it. LAW 4 — "lights pool on the floor; they do not spot-halo
## props" — so the cookie is scaled WIDE and the energy is low.
##
## Capped at two, which is LAW 3's entire allowance for motivated light sources.
## The region builders add the player's carried light and a portal light on top;
## that is the whole lighting rig for a room and it is meant to be.
func _build_life_fixtures(root: Node2D, cfg: Dictionary, hue: Color, size: Vector2) -> void:
	var count := mini(int(cfg.get("fixtures", 0)), 2)
	var tex := _soft()
	if count <= 0 or tex == null:
		return
	var energy := float(cfg.get("energy", 0.45))
	for i in count:
		var left := i % 2 == 0
		# Even world coordinates: LAW 1 keeps static world objects on the grid.
		var at := Vector2(
			roundf(size.x * (0.06 if left else 0.94) * 0.5) * 2.0,
			roundf(size.y * (0.26 + 0.30 * float(i / 2)) * 0.5) * 2.0)
		var l := PointLight2D.new()
		l.name = "Fixture%d" % i
		l.texture = tex
		l.texture_scale = 3.2
		l.color = hue
		l.energy = energy
		l.position = at
		root.add_child(l)
		_life_lights.append(l)
		_life_energy.append(energy)
		_life_seed.append(0.37 + float(i) * 1.31)
		# The lamp itself. A PointLight2D on its own is a glow with no source,
		# and LAW 7 puts the emissive prop first and hangs the light off it.
		# Sorted into the prop depth at its own y so it stands on the wall.
		var zi := int(at.y) + 8
		var body := ColorRect.new()
		body.name = "FixtureBody%d" % i
		body.size = Vector2(12.0, 16.0)
		body.position = at + Vector2(-6.0, -12.0)
		body.color = Color(0.045, 0.05, 0.075, 0.96)
		body.z_index = zi
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(body)
		# LAW 7: ONE emissive core per light source on the sprite. Just over 1.0
		# so it is the lamp — and only the lamp — that the bloom pass finds.
		var core := ColorRect.new()
		core.name = "FixtureCore%d" % i
		core.size = Vector2(8.0, 4.0)
		core.position = at + Vector2(-4.0, -8.0)
		core.color = Color(hue.r * 1.06, hue.g * 1.06, hue.b * 1.06, 0.95)
		core.material = _life_add()
		core.z_index = zi + 1
		core.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(core)
		_life_bulbs.append(core)

## Fixture flicker at 20Hz. LAW 9: lights flicker +/- 6%, and that is all this
## does now — the old two-sine ballast stutter that dropped a lamp to 40% is
## gone, along with the drifting passes and the running-light bars it used to
## share this function with. Everything validity-checked: a region change frees
## these nodes one frame before the arrays are rebuilt.
func _drive_life(delta: float) -> void:
	if _life_lights.is_empty():
		return
	_life_t += delta
	_life_tick -= delta
	if _life_tick > 0.0:
		return
	_life_tick = 0.05
	for i in _life_lights.size():
		if not is_instance_valid(_life_lights[i]):
			continue
		var l: PointLight2D = _life_lights[i]
		var sd := _life_seed[i]
		var v := 1.0 + 0.06 * sin(_life_t * (1.7 + sd) + sd * 6.0)
		l.energy = _life_energy[i] * v
		# The bulb breathes with its own pool. A pool that moves over a bulb
		# that does not is the tell that the light is not coming from the lamp.
		if i < _life_bulbs.size() and is_instance_valid(_life_bulbs[i]):
			var bulb: ColorRect = _life_bulbs[i]
			bulb.color.a = 0.95 * v

## The generated soft-radial cookie, loaded once. Missing art degrades to "no
## fixtures" rather than to a crash (bible: always exists()-guard).
func _soft() -> Texture2D:
	if _soft_tex:
		return _soft_tex
	var path := GEN + "fx_radial_soft.png"
	if ResourceLoader.exists(path):
		_soft_tex = load(path)
	return _soft_tex

## Additive AND unshaded, for the one thing left that needs it: a lamp's lit
## core. An emissive that is itself lit by the room's PointLight2Ds gets a
## second additive pass laid over it wherever it crosses a pool of light — which
## for a bulb sitting inside its own pool is every frame — so it declares
## LIGHT_MODE_UNSHADED, exactly as the atmosphere shader does.
func _life_add() -> CanvasItemMaterial:
	if _life_add_mat == null:
		_life_add_mat = CanvasItemMaterial.new()
		_life_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_life_add_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _life_add_mat

## --- debt pressure ---------------------------------------------------------

func _on_resource_changed(res_name: String, _old: float, _new: float) -> void:
	if res_name == "technical_debt":
		_refresh_stress(false)

## Round 5 spent technical debt on the FRAME: saturation drained, the corners
## heated and breathed, the grain thickened, and past halfway the odd scanline
## slipped sideways. It was a good joke charged to the wrong account — the
## player reads that frame while fighting in it, and LAW 5 says the post must
## never be nameable. postfx_layer.set_stress() now records the number and
## renders nothing; the joke lives in dialogue, barks and prop text (LAW 10).
## The call is kept so the debt signal still has exactly one owner.
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
		_postfx.pulse(Color("#FF4757"), 0.10, 0.45)
	if not _current_region_node or not player:
		return
	var enemies := _current_region_node.get_node_or_null("Enemies")
	if not enemies:
		return
	var e = preload("res://scenes/combat/enemy.tscn").instantiate()
	e.enemy_type = "bug"
	e.max_hp = 16
	enemies.add_child(e)
	e.global_position = _incident_spot(player.global_position)

## Where a debt incident's bug arrives: a ring around the player, but INSIDE the
## room. The angle used to be a bare `randf() * TAU`, so an incident that fired
## while the player stood near a wall — the whole south edge, the portal alcoves,
## either end of a rig bank — put the bug 180-260 units into the masonry, where it
## depenetrates against a static collider and can neither reach the player nor be
## walked up to. A debt incident is meant to be felt; a bug stuck in a wall is
## just a kill count that never closes.
##
## The camera limits are the room, set from the builder's own `size` in
## `_apply_camera_bounds`, so nothing here has to know a region's dimensions.
func _incident_spot(from: Vector2) -> Vector2:
	const INSET := 130.0
	var lo := Vector2(float(camera.limit_left) + INSET, float(camera.limit_top) + INSET)
	var hi := Vector2(float(camera.limit_right) - INSET, float(camera.limit_bottom) - INSET)
	var dist := randf_range(180.0, 260.0)
	if hi.x <= lo.x or hi.y <= lo.y:
		# No usable bounds (a test rig with no camera limits): keep the old ring.
		var a := randf() * TAU
		return from + Vector2(cos(a), sin(a)) * dist
	# Eight bearings from a random start, so the choice is still a ring and not a
	# preferred side; the first one that lands in the room wins.
	var start := randf() * TAU
	for i in 8:
		var a: float = start + float(i) * TAU / 8.0
		var p: Vector2 = from + Vector2(cos(a), sin(a)) * dist
		if p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y:
			return p
	# Boxed in on every bearing (a room smaller than the ring): clamp inward.
	return Vector2(clampf(from.x, lo.x, hi.x), clampf(from.y, lo.y, hi.y))

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
