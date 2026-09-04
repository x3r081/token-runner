extends CharacterBody3D
class_name Player3D
## The vibe coder, in three dimensions (3D_BIBLE.md §4).
##
## A straight port of scripts/player/player.gd — same feel, same abilities, same
## costs, same cooldown fields the HUD reads, same death order the tests assert.
## Only two things change:
##
##   1. Locomotion happens on the XZ plane. The 2D game's `+y` (screen down) is
##      world `+z`, so every direction that leaves this script is still a
##      MAP-SPACE Vector2 (`facing`, `apply_external_knockback`, the direction
##      handed to Projectile3D and to Enemy3D.apply_knockback).
##   2. Speeds authored in map pixels are divided by 64 exactly once, here, via
##      `U`. Nothing else in the file carries a unit conversion, so the tuning
##      numbers below can still be diffed line-for-line against player.gd.
##
## Everything the outside world touches (signals, MAX_HP, hp, facing, can_move,
## is_invincible, `ability_cooldown`, `_dash_cd/_duck_cd/_trace_cd/_ctrlz_cd`,
## take_damage/heal/respawn/grant_spawn_grace/prompt_cost/ability_ready) keeps
## the 2D names and shapes: hud.gd and death_screen.gd read them by name.

signal health_changed(current: int, max_hp: int)
signal died

## ------------------------------------------------------------------ units --
## One world unit is one 64px tile (Map3D.PX). Written out rather than pulled
## from Map3D so this stays a compile-time constant expression.
const U := 1.0 / 64.0

const MAX_HP := 100
## 220 px/s — a 20-unit room still takes the same ~5.8s to cross as it did in 2D.
const SPEED_PX := 220.0
const SPEED := SPEED_PX * U

## ---------------------------------------------------------------- movement --
## Weight without lag, exactly as in 2D: ACCEL reaches full speed in ~0.09s,
## FRICTION stops in ~0.07s, and TURN_BOOST doubles the ramp on a reversal so a
## direction change is instant even though a standing start is not.
const ACCEL := 2450.0 * U
const FRICTION := 3200.0 * U
const TURN_BOOST := 2.2
## The velocity WE own. `velocity` is rewritten by move_and_slide() when you
## scrape a wall; keeping our own copy means sliding never eats the ramp.
var _move_vel := Vector3.ZERO
## A short, hard shove owned by the player: gun recoil and hit reactions. Kept
## in MAP PX/S (like `_ext_impulse`) so the recoil numbers match player.gd's.
var _kick := Vector2.ZERO
const KICK_DECAY_PX := 1500.0
const EXT_DECAY_PX := 1300.0
## Sprint settle: after a second of unbroken travel the stride opens up.
const SPRINT_DELAY := 0.95
const SPRINT_RAMP := 0.85
const SPRINT_BONUS := 0.17
var _run_t := 0.0
var _sprint := 0.0
## Footstep cadence. Matches AudioManager.FOOTSTEP_INTERVAL so the bob, the puff
## and the sound land on the same beat. AudioManager's own poll only understands
## CharacterBody2D, so in 3D WE call play_footstep() (3D_BIBLE §4).
const STRIDE_PERIOD := 0.26
var _stride_t := 0.0
var _step_squash := 0.0

## Dash / Force Push: a guaranteed escape + knockback tool. Even if enemies ever
## crowd the player, a dash bursts through them and shoves them away.
const DASH_SPEED := 660.0 * U
const DASH_DURATION := 0.18
const DASH_COOLDOWN := 1.1
const FORCE_PUSH_RADIUS := 120.0 * U
## Stays in map px/s: it is handed to Enemy3D.apply_knockback(), whose contract
## (3D_BIBLE §4) is map-space like every other cross-actor vector.
const FORCE_PUSH_IMPULSE_PX := 560.0

## ------------------------------------------------------------------ model --
const MODEL_KEY := "mini-characters/character-male-b"
const MODEL_HEIGHT := 0.9
## Kenney's characters are authored facing +Z (verified: `arm-left` sits at +X,
## and in a Y-up right-handed frame left == +X only when forward == +Z). Godot's
## own forward is -Z, so the yaw below is atan2(x, z) — NOT look_at(), which
## would show us the character's back all game.
var _model: Node3D
var _anim := KenneyAnim.new()
var _meshes: Array[MeshInstance3D] = []
var _overlay: StandardMaterial3D
var _overlay_on := false
## The model's authored materials, snapshotted once after it is fitted:
## `material_override` and every surface override, per mesh. Fx3D.dissolve()
## burns a corpse away by REPLACING those overrides with a dissolve shader that
## ends at progress 1.0 (fully transparent) and, by contract, frees nothing —
## so without this snapshot the respawned hero would be a fully invisible body
## with a working lamp and shadow. Keyed by instance id, restored in respawn().
var _mat_snapshot: Dictionary = {}

@onready var model_root: Node3D = $Model
@onready var shadow: MeshInstance3D = $ShadowBlob
@onready var bubble: MeshInstance3D = $CacheBubble
@onready var reticle: MeshInstance3D = $Reticle
@onready var hitbox: Area3D = $Hitbox
@onready var interact_area: Area3D = $InteractArea
@onready var ability_cooldown: Timer = $AbilityCooldown
@onready var invincibility: Timer = $InvincibilityTimer
@onready var idle_timer: Timer = $IdleTimer
@onready var glow: OmniLight3D = $Glow
@onready var prompt: Label3D = $PromptLabel

var hp: int = MAX_HP
## MAP-SPACE unit direction (the 2D contract). Vector2.DOWN == world +Z.
## Only movement input writes it, exactly as in 2D — the dash reads it, so a
## shot that aim-assisted onto a target must not quietly redirect the next dash.
var facing := Vector2.DOWN
## A temporary LOOK direction that overrides `facing` for the model's yaw only
## (firing turns the body toward the target for the length of the shoot pose).
var _look := Vector2.ZERO
var _look_t := 0.0
var can_move := true
var is_invincible := false
var nearby_interactables: Array[Node] = []
## The one live [E] prompt, the node it is attached to, and its fade.
var _prompt_label: Label = null
var _prompt_owner: Node3D = null
var _prompt_a := 0.0
var _dash_timer := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector2.DOWN
## A short, decaying push (e.g. a Rate Limiter's 429 pulse), in map px/s. It
## never removes control — the player can always walk against it.
var _ext_impulse := Vector2.ZERO
var _duck_cd := 0.0
var _trace_cd := 0.0
var _ctrlz_cd := 0.0
## Rolling (time, hp) history so Ctrl+Z can undo damage taken in the last few sec.
var _hp_hist: Array = []
const CTRLZ_WINDOW := 2.6
const CTRLZ_COOLDOWN := 10.0
## Cache (ability 2) runs its own clock so the bubble matches the window it
## actually represents, instead of riding the shared i-frame timer that dashes
## and hurt-frames also poke.
const CACHE_DURATION := 1.5
var _cache_t := 0.0
## Crits: 14% of shots land as a hard hit. Purely additive damage.
const CRIT_CHANCE := 0.14
const CRIT_MULT := 2.0
## One-shot animation poses (shoot, interact, emote, death). While `_pose_t` is
## up the locomotion driver stays out of the AnimationPlayer's way.
const CAST_POSE := 0.27
var _pose_t := 0.0

## ------------------------------------------------------------ combat feel --
## Prompt Blast cadence ramp: shots fired inside CHAIN_WINDOW of each other
## tighten toward 0.52s. The HUD sweep reads `ability_cooldown.wait_time` live,
## so it follows automatically.
const BLAST_CADENCE: Array[float] = [0.8, 0.68, 0.58, 0.52]
const CHAIN_WINDOW := 1.6
var _blast_chain := 0
var _blast_chain_t := 0.0
## Perfect dodge: dash THROUGH a telegraphed attack and you enter FLOW.
const PERFECT_RANGE := 215.0 * U
const FLOW_DURATION := 3.0
const FLOW_SPEED := 0.18
const FLOW_DAMAGE := 0.30
var _flow_t := 0.0
## Rubber Duck does not just stun, it finds the bug: for INSIGHT_WINDOW after a
## duck everything you fire hits harder. Duck then blast is the combo.
const INSIGHT_WINDOW := 2.6
const INSIGHT_DAMAGE := 0.35
var _insight_t := 0.0
## Cache bookkeeping, so the shield can report what it actually did.
var _cache_absorbed := 0
var _cache_absorbed_dmg := 0
const CACHE_REFUND := 2
## Hurt i-frames: the shared InvincibilityTimer is poked by dashes and Cache too,
## so the blink runs on its own clock and only ever means "you were hit".
const HURT_IFRAMES := 0.8
const FLASH_TIME := 0.28
var _iframe_t := 0.0
var _flash_t := 0.0
var _flash_len := FLASH_TIME
var _flash_color := Color(1.0, 0.18, 0.22)
## Low-HP state. Matches hud.gd's LOW_HP_FRAC so the carried lamp and the HUD's
## danger vignette arm on the same hit — one state, not two.
const LOW_HP_FRAC := 0.34
var _low_hp := false
## Throttle for "that did not fire, and here is why" callouts.
var _deny_t := 0.0
## Reticle refresh clock (see _update_reticle) — a group scan every physics
## frame is not free once a boss starts summoning.
var _retic_t := 0.0
var _retic_spin := 0.0
var _retic_target: Node3D = null
const AIM_ASSIST_RANGE := 640.0 * U
const RUBBER_DUCK_RADIUS := 180.0 * U
## Celebration throttle. In 2D a token pickup played a one-frame cheer; in 3D
## the equivalent is a whole-body emote, so it only fires when you are standing
## still and not more than once every few seconds.
var _cheer_cd := 0.0

## Colours (VISUAL_BIBLE master palette).
##
## COL_TRACE used to be MAGENTA #FF2D95 and it painted two things: the stack
## trace's bolt and the aim-assist ring on the floor under the locked target. At
## an albedo gain of 2.4 that ring bloomed to a near-white pink hoop — the "pink
## ring" the critic found in region after region, in rooms whose accent is blue,
## acid or red. LAW 2 allows magenta in api_bazaar and nowhere else, so the bolt
## is now the player's own cyan (the same hue as his cache shell — one colour
## means "this is yours") and the ring is TEXT_DIM — see `_setup_dressing` for
## why it is not HOSTILE.
const COL_CACHE := Color("#24F0DC")
const COL_DAMAGE := Color("#FF4757")
const COL_HEAL := Color("#58E07C")
const COL_TRACE := COL_CACHE
const COL_DIM := Color("#7C8BB0")
const COL_GOLD := Color("#FFD34D")
const LAMP_WARM := Color(1.0, 0.93, 0.82)
const LAMP_PANIC := Color(1.0, 0.50, 0.43)

## VISUAL_BIBLE v2 LAW 3: the player is one of the five things that may be
## bright — but he is meant to be READ, not to light the room. The carried lamp
## was energy 1.5 at range 4.5, which is a floor lamp: in every captured frame
## it bleached four tiles of floor around him and left him a pale shape inside
## his own pool, exactly backwards. At 0.4/3.0 it is a rim: the moon and the
## room's two motivated lights do the lighting, and this only separates his
## silhouette from the ground it stands on. 0.4 is the FLOOR of LAW 4's light
## band (0.4-0.9): a light under the band is not a light the bible recognises,
## so the lamp sits on the band's bottom edge and counts as one of the six.
## The model itself carries NO tint — the hero is his own colormap and nothing
## paints him but light.
const LAMP_ENERGY := 0.4
const LAMP_RANGE := 3.0
## The perfect-dodge beat is combat, and v2 lets combat be loud — but the lamp
## is still a lamp. A quarter of a second at 0.8 reads as a flare against 0.4;
## the old 2.6 read as a flashbang.
const LAMP_FLOW := 0.8

## LAW 1/LAW 4 typography for the [E] prompt: the anchor height, and nothing
## else, because the type is ScreenLabels' now.
##
## The prompt is a SCREEN-SPACE label (scripts/world3d/screen_labels.gd) now,
## attached to the interactable it names. A Label3D's glyphs scale with distance
## and cannot be clamped, so the one text that is always closest to the camera
## was always the biggest thing on screen — in the combat frame "[E]
## node_modules" ran across the portal's own caption at roughly twice HUD size.
## The scene file's PromptLabel node stays (scenes are not this track's to edit)
## and is switched off in `_style_prompt`.
const PROMPT_HEIGHT := 1.0

## The prompt's ScreenLabels priority — the LOWEST thing in the world, below an
## ambient nameplate (0) and a portal's caption (1). Round 2 gave it 4, "above
## every nameplate, marker and portal caption", and the frame that came back had
## "[E] node_modules" as one of five texts stacked on the player's own head with
## the waypoint chevron drawn through them. The prompt is the most REPLACEABLE
## line on screen: the HUD's hint strip already says "[E] interact" permanently,
## so when it competes with the player's silhouette it loses, and ScreenLabels'
## keep-clear disc is what makes it lose.
const PROMPT_PRIORITY := 2

## Where a glyph about the player is anchored (see `_head`).
const GLYPH_LIFT := 1.2

## Projectile3D lands from a sibling track, so it is load()ed on first use and
## exists()-guarded — never preload()ed (3D_BIBLE, iron rules).
const PROJECTILE_PATH := "res://scenes/world3d/projectile3d.tscn"
var _proj_scene: PackedScene
var _proj_warned := false

## Shadow proxy (3D_BIBLE §5): a hidden Node2D in map px so Node2D-typed UI can
## still find the player. Group "player_proxy", NOT "player".
var _proxy: ActorProxy

func _ready() -> void:
	add_to_group("player")
	if GameManager.player_position != Vector2.ZERO:
		global_position = Map3D.to3d(GameManager.player_position, 0.0)
	hp = MAX_HP
	_setup_model()
	_setup_dressing()
	ResourceManager.resource_changed.connect(_on_resource_changed)
	idle_timer.timeout.connect(_on_idle_timer)
	idle_timer.start(randf_range(8.0, 14.0))
	_proxy = ActorProxy.attach(self, ["player_proxy"], {"hp": hp, "max_hp": MAX_HP})
	_face_model(true)

## The hero, fitted to 0.9u so he reads at the same scale as every NPC.
func _setup_model() -> void:
	var m := Map3D.model(MODEL_KEY)
	if m == null:
		# The GLB is missing (a stripped test rig, a failed import). A capsule in
		# the localhost accent keeps the player visible and playable rather than
		# turning the whole run into an invisible-protagonist bug.
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.22
		cm.height = MODEL_HEIGHT
		mi.mesh = cm
		mi.position = Vector3(0.0, MODEL_HEIGHT * 0.5, 0.0)
		mi.material_override = Map3D.matte(COL_CACHE, 1.4)
		model_root.add_child(mi)
		_collect_meshes(model_root)
		return
	Map3D.fit_height(m, MODEL_KEY, MODEL_HEIGHT)
	model_root.add_child(m)
	_model = m
	_anim = KenneyAnim.attach(m)
	_anim.play("idle", 0.0, 1.0, ["static"])
	_collect_meshes(m)

## Every MeshInstance3D under the model, cached once so the damage flash can
## swap one shared overlay material instead of walking the tree per frame. The
## same walk snapshots each mesh's authored materials for `_restore_materials`.
func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		_meshes.append(mi)
		var surfaces: Array[Material] = []
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				surfaces.append(mi.get_surface_override_material(i))
		_mat_snapshot[mi.get_instance_id()] = {"override": mi.material_override, "surfaces": surfaces}
	for c in n.get_children():
		_collect_meshes(c)

## Put the model's authored materials back after a death dissolve (see
## `_mat_snapshot`). Idempotent; a mesh that was never dissolved is untouched
## in effect, since it gets back exactly what it already had.
func _restore_materials() -> void:
	for mi in _meshes:
		if not is_instance_valid(mi):
			continue
		var snap: Dictionary = _mat_snapshot.get(mi.get_instance_id(), {})
		if snap.is_empty():
			continue
		mi.material_override = snap["override"]
		var surfaces: Array[Material] = snap["surfaces"]
		if mi.mesh:
			for i in mini(surfaces.size(), mi.mesh.get_surface_count()):
				mi.set_surface_override_material(i, surfaces[i])

## Blob shadow, cache bubble, target reticle and the carried lamp. All of it is
## degradable: a missing texture or a missing mesh must never break movement.
func _setup_dressing() -> void:
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.albedo_color = Color(_flash_color.r, _flash_color.g, _flash_color.b, 0.0)
	# A contact shadow under the feet. The moon casts a real one, but regions are
	# dark on purpose and a character with no grounding cue floats.
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.albedo_color = Color(0.0, 0.0, 0.02, 0.42)
	var blob := "res://assets/textures/generated/player_shadow.png"
	if ResourceLoader.exists(blob):
		sm.albedo_texture = load(blob)
	shadow.material_override = sm
	# Cache bubble: a thin, unmistakable cyan shell. Deliberately NOT unshaded —
	# an unshaded material ignores `emission` entirely, and the whole point of
	# this shell is that it blooms through the Environment's glow.
	var bm := StandardMaterial3D.new()
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.albedo_color = Color(COL_CACHE.r, COL_CACHE.g, COL_CACHE.b, 0.22)
	bm.emission_enabled = true
	bm.emission = COL_CACHE
	bm.emission_energy_multiplier = 3.0
	bubble.material_override = bm
	bubble.visible = false
	# Aim-assist lock: aim assist has always silently picked your target; the
	# ring on the floor is it saying which one. Unshaded (it must read the same
	# in a pitch-black cave as under localhost's desk lamp), NEUTRAL, and UNDER
	# the glow threshold: a mark on the floor, not a light on it. The 2.4 gain
	# that used to be here is why it photographed as a white hoop.
	#
	# TEXT_DIM and not HOSTILE, and the reason is geometry: this torus (r 0.32-
	# 0.40 at y 0.05) sits exactly on top of Enemy3D's alert ring (r 0.34-0.40
	# at y 0.035), the flat red hoop an enemy shows ONLY while committed to a
	# swing or a charge. Drawn in the same red, the permanent aim mark would hide
	# the one tell the bible reserves that colour for — the player could never
	# see the nearest enemy commit. A dim grey ring says "yours"; a red one says
	# "move", and only the enemy gets to say that (LAW 2, LAW 7).
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	rm.albedo_color = Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.7)
	reticle.material_override = rm
	reticle.visible = false
	glow.light_color = LAMP_WARM
	# The scene file still carries the round-1 floor lamp (1.5 / 4.5). Owned
	# here, in code, so the one number a reviewer greps for is the one the game
	# actually runs (LAW 3).
	glow.light_energy = LAMP_ENERGY
	glow.omni_range = LAMP_RANGE
	_style_prompt()

## The scene's world-space PromptLabel, switched off for good. The node itself
## cannot be deleted from here (scenes belong to another track) so it is emptied
## and hidden: an empty Label3D draws nothing, and `_update_prompt` never touches
## it again.
func _style_prompt() -> void:
	if not is_instance_valid(prompt):
		return
	prompt.text = ""
	prompt.visible = false

# ---------------------------------------------------------------- geometry --

## Chest height — where hits, bursts and the cache bubble belong.
func _center() -> Vector3:
	return global_position + Vector3(0.0, 0.45, 0.0)

## Just above the head — damage numbers and refusal callouts.
##
## GLYPH_LIFT, not the model's actual crown: the point of this anchor is that a
## number about the PLAYER never lands ON the player. 1.05 put "-10" and "+5"
## inside his silhouette in `combat_dependency_district.png`; 1.2 clears the head
## outright, and ScreenLabels' keep-clear disc lifts whatever is left of the
## overlap the rest of the way. Every Fx3D.glyph call this file makes is about
## the player, so they all come through here.
func _head() -> Vector3:
	return global_position + Vector3(0.0, GLYPH_LIFT, 0.0)

## World-space XZ direction for a map-space Vector2.
func _world_dir(d: Vector2) -> Vector3:
	return Map3D.dir3d(d)

# --------------------------------------------------------------- main loop --

func _physics_process(delta: float) -> void:
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_duck_cd = maxf(0.0, _duck_cd - delta)
	_trace_cd = maxf(0.0, _trace_cd - delta)
	_ctrlz_cd = maxf(0.0, _ctrlz_cd - delta)
	_deny_t = maxf(0.0, _deny_t - delta)
	_insight_t = maxf(0.0, _insight_t - delta)
	_cheer_cd = maxf(0.0, _cheer_cd - delta)
	_pose_t = maxf(0.0, _pose_t - delta)
	_look_t = maxf(0.0, _look_t - delta)
	_blast_chain_t = maxf(0.0, _blast_chain_t - delta)
	if _blast_chain_t <= 0.0:
		_blast_chain = 0
	_tick_flow(delta)
	_tick_flash(delta)
	_tick_iframes(delta)
	_kick = _kick.move_toward(Vector2.ZERO, KICK_DECAY_PX * delta)
	_track_hp_history(delta)
	_tick_cache(delta)
	_ext_impulse = _ext_impulse.move_toward(Vector2.ZERO, EXT_DECAY_PX * delta)
	_update_prompt(delta)
	_update_reticle(delta)
	# One yaw update per frame, here rather than in the movement branch, so a
	# player who fires or interacts while standing still still turns to face it.
	_face_model()
	if not can_move or GameManager.state != GameManager.GameState.PLAYING \
			or EventManager.has_active_event():
		velocity = Vector3.ZERO
		_move_vel = Vector3.ZERO
		_run_t = 0.0
		_sprint = 0.0
		# A pause mid-step must not leave the model frozen mid-squash.
		_step_squash = 0.0
		_apply_step_scale()
		_drive_anim(false)
		_sync_proxy()
		return
	if _dash_timer > 0.0:
		_dash_timer -= delta
		velocity = _world_dir(_dash_dir) * DASH_SPEED
		velocity.y = 0.0
		# Hand the dash's momentum back to the walk ramp, so releasing a dash
		# while still holding the stick continues at speed instead of restarting.
		_move_vel = _world_dir(_dash_dir) * SPEED
		_step_squash = maxf(0.0, _step_squash - delta * 7.0)
		_apply_step_scale()
		_drive_anim(true)
		move_and_slide()
		_settle()
		return
	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if input_dir != Vector2.ZERO:
		var want_dir := input_dir.normalized()
		facing = want_dir
		var want := _world_dir(want_dir) * SPEED * _speed_mult()
		# Reversing gets the boosted ramp: a standing start has weight, a
		# direction change does not. Mass on the outside, zero input lag inside.
		var accel := ACCEL
		if _move_vel.dot(want) < 0.0:
			accel *= TURN_BOOST
			_run_t = 0.0  # a reversal is not a traversal; the stride settles
		_move_vel = _move_vel.move_toward(want, accel * delta)
		velocity = _move_vel
		idle_timer.start(randf_range(10.0, 18.0))
		_tick_stride(delta)
		_drive_anim(true)
	else:
		_move_vel = _move_vel.move_toward(Vector3.ZERO, FRICTION * delta)
		velocity = _move_vel
		_run_t = 0.0
		_sprint = maxf(0.0, _sprint - delta * 3.0)
		_stride_t = STRIDE_PERIOD * 0.7  # next step lands as movement resumes
		_step_squash = maxf(0.0, _step_squash - delta * 7.0)
		model_root.position.y = 0.0
		_apply_step_scale()
		_drive_anim(false)
	# Impulses ride along for the SLIDE only, then `velocity` is put back to our
	# own locomotion, exactly as in 2D: everything outside this script reads
	# `velocity` as "is the player walking", and folding a gun recoil into that
	# faked a footstep on every shot.
	velocity = _move_vel + _world_dir(_ext_impulse + _kick) * U
	velocity.y = 0.0
	move_and_slide()
	velocity = _move_vel
	_settle()
	ResourceManager.regenerate_focus(delta * 0.5)

## After every move: the floor is flat (y == 0), the managers get the position in
## MAP PIXELS, and the shadow proxy follows.
func _settle() -> void:
	if absf(global_position.y) > 0.0001:
		global_position.y = 0.0
	GameManager.player_position = Map3D.to_map(global_position)
	_sync_proxy()

func _sync_proxy() -> void:
	if _proxy != null and is_instance_valid(_proxy):
		_proxy.sync()

## Current top speed. Sprint settle and Flow both live here so every consumer
## (walk ramp, dash exit) reads one number.
func _speed_mult() -> float:
	var m := 1.0 + _sprint * SPRINT_BONUS
	if _flow_t > 0.0:
		m += FLOW_SPEED
	return m

## Damage multiplier from the two earned states: Flow (a perfect dodge) and
## Insight (you just explained the bug to a duck). Additive so the combo reads
## as "both are on" rather than a hidden exponent.
func _damage_mult() -> float:
	var m := 1.0
	if _flow_t > 0.0:
		m += FLOW_DAMAGE
	if _insight_t > 0.0:
		m += INSIGHT_DAMAGE
	return m

# --------------------------------------------------------------- animation --

## Yaw the model to the current look direction. Kenney characters are authored
## facing +Z (verified from the rig: `arm-left` sits at +X, and in a Y-up
## right-handed frame left == +X only when forward == +Z), so the yaw that maps
## (0,0,1) onto (d.x, d.y) is atan2(d.x, d.y) — NOT look_at(), whose -Z forward
## would show us the character's back all game.
func _face_model(snap: bool = false) -> void:
	if not is_instance_valid(model_root):
		return
	var d := _look if _look_t > 0.0 and _look != Vector2.ZERO else facing
	if d == Vector2.ZERO:
		return
	var want := atan2(d.x, d.y)
	if snap:
		model_root.rotation.y = want
		return
	# Shortest-arc turn at ~14 rad/s: instant enough for combat, smooth enough
	# that a diagonal tap does not snap the character like a turret.
	model_root.rotation.y = lerp_angle(model_root.rotation.y, want,
		clampf(get_physics_process_delta_time() * 14.0, 0.0, 1.0))

## The locomotion animator. Never runs while a one-shot pose (shoot, interact,
## emote, death) owns the AnimationPlayer.
func _drive_anim(moving: bool) -> void:
	if _pose_t > 0.0:
		return
	if _dash_timer > 0.0:
		_anim.play("sprint", 0.06, 1.9, ["walk", "idle"])
		return
	if moving:
		# Hysteresis on the walk/sprint swap: the sprint ramp crawls (1.6/s), so a
		# bare threshold would sit on the boundary and re-blend the two clips over
		# and over on a long straight.
		var thresh := 0.42 if _anim.current == "sprint" else 0.5
		if _sprint > thresh:
			_anim.play("sprint", 0.16, 1.0, ["walk"])
		else:
			_anim.play("walk", 0.14, 1.0 + _sprint * 0.25, ["idle"])
	else:
		_anim.play("idle", 0.22, 1.0, ["static"])

## Arm a one-shot clip and lock the locomotion animator out for `hold` seconds.
func _pose(anim: String, hold: float, alts: Array = []) -> void:
	_anim.play(anim, 0.06, 1.0, alts)
	_pose_t = maxf(_pose_t, hold)

## Footstep cadence: a bob that peaks between contacts, a squash on the contact
## itself, and the sound on the same beat. Costs one sin() and no allocations.
func _tick_stride(delta: float) -> void:
	_run_t += delta
	var want_sprint := clampf((_run_t - SPRINT_DELAY) / SPRINT_RAMP, 0.0, 1.0)
	_sprint = move_toward(_sprint, want_sprint, delta * 1.6)
	# The stride rate tracks the ACTUAL speed bonus, not a second hand-tuned
	# number that can drift away from it.
	_stride_t += delta * (1.0 + _sprint * SPRINT_BONUS)
	if _stride_t >= STRIDE_PERIOD:
		_stride_t -= STRIDE_PERIOD
		_step_squash = 1.0
		# AudioManager._poll_footsteps() only understands CharacterBody2D, so the
		# 3D player is its own metronome (3D_BIBLE §4).
		AudioManager.play_footstep()
		if _sprint > 0.4:
			Fx3D.burst(self, global_position + Vector3(0.0, 0.05, 0.0),
				Color(0.49, 0.55, 0.69, 0.5), 4, 1.1, 0.3)
	_step_squash = maxf(0.0, _step_squash - delta * 7.0)
	var phase := clampf(_stride_t / STRIDE_PERIOD, 0.0, 1.0)
	model_root.position.y = absf(sin(phase * PI)) * (0.018 + _sprint * 0.014)
	_apply_step_scale()

## Landing squash. Transient — it returns to exactly Vector3.ONE the moment the
## contact is over, so the fitted model scale underneath is never disturbed.
func _apply_step_scale() -> void:
	if not is_instance_valid(model_root):
		return
	var s := _step_squash * _step_squash  # sharp on contact, soft on recovery
	model_root.scale = Vector3(1.0 + s * 0.05, 1.0 - s * 0.06, 1.0 + s * 0.05)

# ------------------------------------------------------------ damage feel --

## Flow decays on its own clock so the boost ends visibly, not silently.
func _tick_flow(delta: float) -> void:
	if _flow_t <= 0.0:
		return
	_flow_t = maxf(0.0, _flow_t - delta)
	if _flow_t <= 0.0:
		glow.light_color = LAMP_PANIC if _low_hp else LAMP_WARM
		glow.light_energy = LAMP_ENERGY

## The overbright hit tint, driven by a clock instead of a tween: a tween on a
## material would fight the next hit and freeze through get_tree().paused.
func _tick_flash(delta: float) -> void:
	if _flash_t <= 0.0:
		if _overlay_on:
			_set_overlay(false)
		return
	_flash_t = maxf(0.0, _flash_t - delta)
	var a := (_flash_t / maxf(_flash_len, 0.01)) * 0.85
	_overlay.albedo_color = Color(_flash_color.r, _flash_color.g, _flash_color.b, a)
	if not _overlay_on:
		_set_overlay(true)

func _flash(color: Color, duration: float) -> void:
	_flash_color = color
	_flash_len = duration
	_flash_t = duration
	_overlay.albedo_color = Color(color.r, color.g, color.b, 0.85)
	_set_overlay(true)

func _set_overlay(on: bool) -> void:
	_overlay_on = on
	for mi in _meshes:
		if not is_instance_valid(mi):
			continue
		if on:
			mi.material_overlay = _overlay
		else:
			mi.material_overlay = null

## The i-frame blink. Runs on its own clock (not the shared InvincibilityTimer,
## which dashes and Cache also poke) so a blink always means "you were hit and
## you are briefly safe". The damage flash owns the model for its first
## FLASH_TIME; the blink only starts after it, so they never fight.
func _tick_iframes(delta: float) -> void:
	if _iframe_t <= 0.0:
		return
	_iframe_t = maxf(0.0, _iframe_t - delta)
	if not is_instance_valid(model_root):
		return
	if _iframe_t <= 0.0:
		model_root.visible = true
		return
	if _iframe_t < HURT_IFRAMES - FLASH_TIME:
		model_root.visible = fmod(_iframe_t, 0.13) >= 0.065

## "That did not fire, and here is exactly why." An ability that fails silently
## is an ability the player decides is broken. Throttled so mashing a key on
## cooldown prints one line, not twenty. (COMEDY_BIBLE: the number is the
## information — any quip rides beside it, never instead of it.)
func _deny(text: String) -> void:
	if _deny_t > 0.0:
		return
	_deny_t = 0.5
	AudioManager.play_sfx("denied")
	Fx3D.glyph(self, _head(), text, COL_DIM, 18, 0.8, 0.7)

## Arms/disarms the low-HP presentation. Called from every path that can move
## HP: damage, heal, Ctrl+Z and respawn. The fraction matches hud.gd's
## `frac < LOW_HP_FRAC` exactly, so the lamp and the vignette arm on one hit.
func _update_low_hp() -> void:
	var low: bool = hp > 0 and float(hp) < float(MAX_HP) * LOW_HP_FRAC
	if low == _low_hp:
		return
	_low_hp = low
	# The lamp you carry shifts to emergency lighting, so the whole room around
	# you changes colour when you are about to die. A red SHIFT, not pure red:
	# this state can hold for the rest of a run.
	if is_instance_valid(glow):
		glow.light_color = LAMP_PANIC if low else LAMP_WARM

# ------------------------------------------------------------------- input --

func _unhandled_input(event: InputEvent) -> void:
	# Ignore gameplay input while a modal event/storyline popup is showing, and
	# mid-conversation: ability keys pressed while reading dialogue must not fire
	# blasts and spend resources behind the panel.
	if EventManager.has_active_event():
		return
	if DialogueManager.is_active:
		return
	if event.is_action_pressed("interact"):
		_try_interact()
	if event.is_action_pressed("ability_1"):
		_use_ability("prompt_blast")
	if event.is_action_pressed("ability_2"):
		_use_ability("cache")
	if event.is_action_pressed("dash"):
		_start_dash()
	if event.is_action_pressed("ability_3"):
		_use_ability("rubber_duck")
	if event.is_action_pressed("ability_4"):
		_use_ability("stack_trace")
	if event.is_action_pressed("ability_5"):
		_use_ability("ctrl_z")
	if event.is_action_pressed("cycle_model"):
		ModelManager.cycle()

func _try_interact() -> void:
	var closest := _closest_interactable()
	if closest and closest.has_method("interact"):
		_pose("interact-right", 0.55, ["pick-up", "emote-yes"])
		closest.interact(self)

# --------------------------------------------------------------- abilities --

## Every branch states its own reason for refusing. The shared
## `ability_cooldown` still gates Prompt Blast and Cache against each other
## (that trade-off is the HUD's contract — hud.gd reads `ability_cooldown` for
## exactly those two ids), but it never swallows Rubber Duck, Stack Trace or
## Ctrl+Z, which own their own timers.
func _use_ability(ability: String) -> void:
	# No ability fires while the player has no control — the opening sequence, a
	# region transition, the death screen. Silent, because a refusal callout
	# floating over a cutscene is worse than no feedback at all.
	if not can_move or GameManager.state != GameManager.GameState.PLAYING:
		return
	match ability:
		"prompt_blast":
			# Silent on its own cooldown: [1] is a held/mashed key and its rate
			# IS the rhythm. Callouts are for the things you would otherwise
			# think are broken — an empty wallet, or a locked-out ability.
			if ability_cooldown.time_left > 0:
				return
			var cost := prompt_cost()
			var tokens := int(ResourceManager.get_value("tokens"))
			if tokens < cost:
				_deny("need %d tokens · you have %d" % [cost, tokens])
				return
			ResourceManager.modify("tokens", -cost)
			var dmg := int(round(25.0 * ModelManager.dmg_mult() * _damage_mult()))
			# Low-reliability models can hallucinate: the blast fizzles.
			var weak := false
			if randf() > ModelManager.reliability():
				dmg = maxi(1, int(dmg * 0.2))
				weak = true
				GameManager.record_stat("reloads_detected")
			# Cadence: sustained fire tightens toward BLAST_CADENCE's floor and
			# relaxes back the moment you stop. Counted before the shot so the
			# muzzle can run hotter as the rhythm builds.
			_blast_chain = mini(_blast_chain + 1, BLAST_CADENCE.size())
			_blast_chain_t = CHAIN_WINDOW
			_fire_projectile("prompt_blast", dmg, false, weak)
			ability_cooldown.start(BLAST_CADENCE[_blast_chain - 1])
		"cache":
			if ability_cooldown.time_left > 0:
				_deny("cache · %.1fs" % ability_cooldown.time_left)
				return
			var compute := int(ResourceManager.get_value("compute"))
			if compute < 3:
				_deny("need 3 compute · you have %d" % compute)
				return
			ResourceManager.modify("compute", -3)
			_cache_absorbed = 0
			_cache_absorbed_dmg = 0
			# A shielded player must not also be blinking hurt-frames — the
			# bubble is the state that matters now.
			_iframe_t = 0.0
			_flash_t = 0.0
			if is_instance_valid(model_root):
				model_root.visible = true
			is_invincible = true
			invincibility.start(CACHE_DURATION)
			ability_cooldown.start(3.0)
			_cache_t = CACHE_DURATION
			if is_instance_valid(bubble):
				bubble.visible = true
			Fx3D.ring(self, _center(), COL_CACHE, 0.2, 0.9, 0.3)
			Fx3D.glyph(self, _head(), "CACHED", COL_CACHE, 20, 0.7, 0.9)
		"rubber_duck":
			# Explain the bug to the duck: nearby enemies freeze (you found it),
			# and for the next few seconds you know exactly where to hit.
			if _duck_cd > 0.0:
				_deny("rubber duck · %.1fs" % _duck_cd)
				return
			var ctx := int(ResourceManager.get_value("context"))
			if ctx < 5:
				_deny("need 5 context · you have %d" % ctx)
				return
			ResourceManager.modify("context", -5)
			_duck_cd = 4.5
			_insight_t = INSIGHT_WINDOW
			_rubber_duck()
		"stack_trace":
			# A piercing trace that chains through a whole line of enemies.
			if _trace_cd > 0.0:
				_deny("stack trace · %.1fs" % _trace_cd)
				return
			var trace_tokens := int(ResourceManager.get_value("tokens"))
			if trace_tokens < 10:
				_deny("need 10 tokens · you have %d" % trace_tokens)
				return
			ResourceManager.modify("tokens", -10)
			_trace_cd = 1.6
			_fire_projectile("stack_trace", int(round(22.0 * _damage_mult())), true)
		"ctrl_z":
			# Undo: restore the HP you had a couple seconds ago (panic recovery).
			if _ctrlz_cd > 0.0:
				_deny("ctrl+z · %.1fs" % _ctrlz_cd)
				return
			var undo_ctx := int(ResourceManager.get_value("context"))
			if undo_ctx < 4:
				_deny("need 4 context · you have %d" % undo_ctx)
				return
			var prev := _hp_from_ago(CTRLZ_WINDOW)
			if prev <= hp:
				_deny("nothing to undo · no damage in %.1fs" % CTRLZ_WINDOW)
				return
			ResourceManager.modify("context", -4)
			_ctrlz_cd = CTRLZ_COOLDOWN
			var before := hp
			hp = mini(prev, MAX_HP)
			health_changed.emit(hp, MAX_HP)
			_update_low_hp()
			_ctrl_z_effect(hp - before)
	AudioManager.play_sfx("ability")

## The Cache bubble owns its own clock, so it pops exactly when the window it
## represents ends — even if a dash or a hurt-frame restarted the shared timer.
func _tick_cache(delta: float) -> void:
	if _cache_t <= 0.0:
		return
	_cache_t -= delta
	if is_instance_valid(bubble):
		# A shell that breathes, so an open cache is never mistaken for a decal.
		var k := 1.0 + 0.06 * sin(_cache_t * 14.0)
		bubble.scale = Vector3(k, k, k)
	if _cache_t <= 0.0:
		_cache_t = 0.0
		if is_instance_valid(bubble):
			bubble.visible = false
			bubble.scale = Vector3.ONE
		# A cache that served hits pays part of itself back; a cache that served
		# nothing was a cache miss, and it says so on the way out. `hp > 0`
		# because _physics_process keeps ticking through GAME_OVER, and a bubble
		# still open when you died must not pay compute into a corpse's wallet.
		if _cache_absorbed > 0 and hp > 0:
			ResourceManager.modify("compute", CACHE_REFUND)
			Fx3D.glyph(self, _head(), "cache hit x%d · -%d dmg · +%d cp"
				% [_cache_absorbed, _cache_absorbed_dmg, CACHE_REFUND],
				COL_CACHE, 18, 1.0, 1.0)
		elif hp > 0:
			Fx3D.glyph(self, _head(), "cache miss", COL_DIM, 18, 0.8, 0.7)
		_cache_absorbed = 0
		_cache_absorbed_dmg = 0

## Sample HP each frame on a monotonic clock; keep only the last few seconds.
func _track_hp_history(delta: float) -> void:
	var t: float = (_hp_hist[-1][0] + delta) if not _hp_hist.is_empty() else 0.0
	_hp_hist.append([t, hp])
	while _hp_hist.size() > 1 and t - _hp_hist[0][0] > 4.0:
		_hp_hist.pop_front()

func _hp_from_ago(seconds: float) -> int:
	if _hp_hist.is_empty():
		return hp
	var now: float = _hp_hist[-1][0]
	var best: int = hp
	for entry in _hp_hist:
		if now - entry[0] >= seconds:
			best = int(entry[1])
	return best

## Undo, but for your entire body: a green pulse plus the restored HP counted
## back on over your head.
func _ctrl_z_effect(healed: int = 0) -> void:
	_flash(COL_HEAL, 0.4)
	Fx3D.ring(self, _center(), COL_HEAL, 0.15, 1.4, 0.45)
	Fx3D.burst(self, _center(), COL_HEAL, 16, 3.0, 0.5)
	if healed > 0:
		Fx3D.glyph(self, _head(), "ctrl+z · +%d" % healed, COL_HEAL, 26, 1.0, 1.4)
	_pose("emote-yes", 0.6, ["interact-right"])

func _rubber_duck() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if not e.has_method("stun"):
			continue
		if global_position.distance_to((e as Node3D).global_position) < RUBBER_DUCK_RADIUS:
			e.stun(1.8)
	# LAW 2: gold is money. A duck is not money — the pulse and the line are the
	# neutral TEXT every other piece of the player's own copy is drawn in.
	Fx3D.shockwave(self, _center(), GameTheme.TEXT, RUBBER_DUCK_RADIUS, 0.5)
	Fx3D.glyph(self, _head(), "so anyway the bug is…", GameTheme.TEXT, 20, 1.1, 1.0)
	_pose("interact-left", 0.5, ["emote-yes", "pick-up"])

# -------------------------------------------------------------------- dash --

func _start_dash() -> void:
	# Control checks first: a cutscene or a menu should refuse in silence, only
	# a real cooldown earns a callout — and dash is mashed, so even that stays
	# quiet (the HUD's [Q] sweep already says how long is left).
	if not can_move:
		return
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	if _dash_cd > 0.0:
		return
	# Read the room BEFORE the dash moves us: a dash begun while something is
	# mid-telegraph inside PERFECT_RANGE is the dodge this game wants to reward.
	var perfect := _threat_incoming()
	_dash_dir = facing if facing != Vector2.ZERO else Vector2.DOWN
	_dash_timer = DASH_DURATION
	_dash_cd = DASH_COOLDOWN
	is_invincible = true
	invincibility.start(DASH_DURATION + 0.12)
	_force_push()
	if _model:
		Fx3D.afterimage(self, _model, Color(0.62, 0.72, 0.84), 0.32)
	Fx3D.ring(self, _center(), COL_CACHE, 0.1, FORCE_PUSH_RADIUS, 0.3)
	AudioManager.play_sfx("dash")
	if perfect:
		_grant_flow()

## Is something currently winding up an attack near enough to hit us?
##
## enemy_base.gd answers exactly this question publicly — `is_committed()` — so
## ask that first; probing private clocks instead would put the whole reward on
## a rename nothing errors about. The property probe stays as a fallback for
## anything in the `enemy` group that does not expose the method.
func _threat_incoming() -> bool:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node3D) or e.get("_dying"):
			continue
		if global_position.distance_to((e as Node3D).global_position) > PERFECT_RANGE:
			continue
		if e.has_method("is_committed"):
			if e.is_committed():
				return true
			continue
		for key: String in ["_windup", "_telegraph", "_boss_tele"]:
			if key in e and float(e.get(key)) > 0.0:
				return true
	return false

## FLOW: the perfect-dodge reward. Faster, harder-hitting, and most of the dash
## back — so the correct answer to a telegraph is always "dash into it", not
## "walk away early". Deliberately short: a beat of mastery, not a buff to sit on.
func _grant_flow() -> void:
	_flow_t = FLOW_DURATION
	_dash_cd = maxf(0.0, _dash_cd - 0.45)
	Fx3D.hit_stop(get_tree(), 0.3, 0.05)
	Fx3D.punch_zoom(get_tree(), 0.05)
	Fx3D.glyph(self, _head(), "PERFECT", GameTheme.WHITE_HOT, 30, 1.0, 1.5)
	Fx3D.ring(self, _center(), GameTheme.WHITE_HOT, 0.2, 1.6, 0.4)
	if is_instance_valid(glow):
		# The flow flare is the carried lamp turned up, not a gold light: LAW 2
		# keeps GOLD for currency, and the lamp is already a warm white.
		glow.light_color = LAMP_WARM
		glow.light_energy = LAMP_FLOW
	AudioManager.play_sfx("pickup_rare")

## Shove every nearby enemy away from the player. This is the design-level
## guarantee that the player can always break out of a crowd. The impulse leaves
## in MAP PX/S — Enemy3D.apply_knockback's contract.
func _force_push() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if not e.has_method("apply_knockback"):
			continue
		var away: Vector3 = (e as Node3D).global_position - global_position
		away.y = 0.0
		var d := away.length()
		if d < FORCE_PUSH_RADIUS and d > 0.001:
			var strength := 1.0 - d / FORCE_PUSH_RADIUS + 0.3
			e.apply_knockback(Map3D.dir_map(away).normalized()
				* FORCE_PUSH_IMPULSE_PX * strength)

# ------------------------------------------------------------- projectiles --

## Aim assist: fire toward the nearest living enemy in range so combat is about
## positioning/kiting/resources, not twitch-aiming a facing. Falls back to the
## facing direction when no enemy is near. Map space, like every direction that
## leaves this script.
func _aim_dir() -> Vector2:
	var nearest := _nearest_enemy(AIM_ASSIST_RANGE)
	if nearest:
		var d := Map3D.dir_map(nearest.global_position - global_position)
		if d.length_squared() > 0.000001:
			return d.normalized()
	return facing if facing != Vector2.ZERO else Vector2.RIGHT

## The one enemy query the whole script shares: aim assist, the hit-reaction
## direction and the reticle all mean "nearest living enemy inside `max_range`"
## (world units).
func _nearest_enemy(max_range: float) -> Node3D:
	var nearest: Node3D = null
	var best := max_range
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e is Node3D and not e.get("_dying"):
			var d: float = global_position.distance_to((e as Node3D).global_position)
			if d < best:
				best = d
				nearest = e as Node3D
	return nearest

## Aim assist has always silently picked your target; the floor ring says which
## one. The SCAN is throttled to 15 Hz — a group walk every physics frame is not
## free once a boss starts summoning — but the ring is placed every frame, since
## it is parented to the player and would otherwise drag along behind him.
func _update_reticle(delta: float) -> void:
	if not is_instance_valid(reticle):
		return
	_retic_spin += delta * 1.8
	_retic_t -= delta
	if _retic_t <= 0.0:
		_retic_t = 0.066
		_retic_target = null
		if GameManager.state == GameManager.GameState.PLAYING and can_move \
				and not DialogueManager.is_active and not EventManager.has_active_event():
			_retic_target = _nearest_enemy(AIM_ASSIST_RANGE)
	if _retic_target == null or not is_instance_valid(_retic_target):
		reticle.visible = false
		return
	reticle.visible = true
	reticle.global_position = _retic_target.global_position + Vector3(0.0, 0.05, 0.0)
	reticle.rotation.y = _retic_spin

func _projectile_scene() -> PackedScene:
	if _proj_scene == null and ResourceLoader.exists(PROJECTILE_PATH):
		_proj_scene = load(PROJECTILE_PATH)
	return _proj_scene

## Spawn a bolt and play the ability's signature. `weak` is the hallucination
## misfire (the model was extremely confident and extremely wrong); `crit` is
## rolled here so every shot — including scripted ones — can land hard.
func _fire_projectile(type: String, damage: int, pierce: bool = false, weak: bool = false) -> void:
	var dir := _aim_dir()
	# Shoot where you aim: the body turns to follow the shot for the length of
	# the pose. `facing` itself is left alone — it belongs to movement input, and
	# the dash reads it.
	_look = dir
	_look_t = CAST_POSE + 0.12
	var crit := not weak and randf() < CRIT_CHANCE
	if crit:
		damage = int(round(float(damage) * CRIT_MULT))
	var muzzle := global_position + Vector3(0.0, 0.62, 0.0) + _world_dir(dir) * 0.35
	_pose("holding-right-shoot", CAST_POSE, ["attack-melee-right", "holding-right"])
	AudioManager.play_sfx("projectile_shoot")
	var accent: Color = COL_TRACE if type == "stack_trace" else ModelManager.color()
	Fx3D.flash(self, muzzle, accent, 3.0, 0.12)
	if type == "stack_trace":
		Fx3D.beam(self, muzzle, muzzle + _world_dir(dir) * 11.9, accent, 0.09, 0.16)
	# Kickback. Small enough that it never fights your walk (spent in ~0.1s),
	# big enough that the gun has a butt. Stack Trace shoves harder, because
	# Stack Trace is the shoulder-fired one.
	if not weak:
		var push: float = 245.0 if type == "stack_trace" else 135.0
		if crit:
			push *= 1.35
		_kick = -dir * push
	var ps := _projectile_scene()
	if ps == null:
		# The bolt scene has not landed yet. The shot still costs, still poses
		# and still sounds — silently doing nothing is the failure mode that
		# makes players think an ability is broken.
		if not _proj_warned:
			_proj_warned = true
			push_warning("Player3D: missing " + PROJECTILE_PATH)
		return
	var proj := ps.instantiate()
	if proj.has_method("setup"):
		proj.setup(dir, damage, type)
	if "pierce" in proj:
		proj.pierce = pierce
	if "weak" in proj:
		proj.weak = weak
	if "crit" in proj:
		proj.crit = crit
	# OUR OWN PARENT, not current_scene: the player's parent is the 3D world by
	# definition, in the game and in every rig that mounts a bare player.
	var host: Node = get_parent()
	if host == null:
		host = get_tree().current_scene
	host.add_child(proj)
	if proj is Node3D:
		(proj as Node3D).global_position = muzzle

# ------------------------------------------------------------------ damage --

func apply_external_knockback(impulse: Vector2) -> void:
	_ext_impulse = impulse

## Brief invulnerability when the player gains control, so the opening isn't an
## immediate pile-on while they learn the controls.
func grant_spawn_grace(seconds: float = 2.5) -> void:
	is_invincible = true
	invincibility.start(seconds)

## Effective Prompt Blast token cost under the current model (for HUD/tests).
func prompt_cost() -> int:
	return int(ceil(5.0 * ModelManager.cost_mult()))

## Cooldown readiness for the HUD ability bar.
func ability_ready(id: String) -> bool:
	match id:
		"prompt_blast", "cache":
			return ability_cooldown.time_left <= 0.0
		"rubber_duck":
			return _duck_cd <= 0.0
		"stack_trace":
			return _trace_cd <= 0.0
		"ctrl_z":
			return _ctrlz_cd <= 0.0
		"dash":
			return _dash_cd <= 0.0
	return true

func take_damage(amount: int, _source: String = "") -> void:
	# A corpse absorbs nothing. The hurt i-frames outlast neither the death
	# screen nor a charger's follow-up, and a second `_die()` would re-dissolve
	# an already-dissolved model (white silhouette popping back in behind the
	# death panel) and emit `died` twice. GameManager guards its own half; this
	# guards ours. `hp <= 0` is exactly "dead": respawn() is the only way back.
	if hp <= 0:
		return
	if is_invincible:
		# A hit that landed on the Cache bubble instead of you. Say so — an
		# ability the player can't see working is an ability they stop using.
		if _cache_t > 0.0:
			_cache_absorbed += 1
			_cache_absorbed_dmg += amount
			Fx3D.ring(self, _center(), COL_CACHE, 0.45, 0.85, 0.22)
		return
	hp -= amount
	health_changed.emit(hp, MAX_HP)
	if _proxy != null and is_instance_valid(_proxy):
		_proxy.set_field("hp", hp)
	var from_dir := _threat_dir()
	# Physical hit reaction: you get shoved away from what hit you. Short
	# (~0.18s) and always walkable-against, so it reads as impact, never as
	# lost control.
	if from_dir.length_squared() > 0.0001:
		_kick = from_dir * (170.0 + clampf(float(amount) * 6.0, 0.0, 150.0))
	# Overbright red + a camera kick: pain must read instantly, mid-chaos.
	_flash(Color(1.6, 0.22, 0.26), FLASH_TIME)
	Fx3D.glyph(self, _head(), "-%d" % amount, COL_DAMAGE, 26, 0.9, 1.3)
	Fx3D.burst(self, _center(), COL_DAMAGE, 10, 3.2, 0.35)
	Fx3D.add_trauma(get_tree(), 0.25)
	AudioManager.play_sfx("damage")
	is_invincible = true
	invincibility.start(HURT_IFRAMES)
	_iframe_t = HURT_IFRAMES
	if hp <= 0:
		_die()
		return
	# You are not dead, but you might be about to be. Arm the low-HP state
	# BEFORE the player has to work that out from a 60px bar in the corner.
	_update_low_hp()

## Which way the pain came from, for the recoil. Cheapest correct answer: the
## nearest living enemy. Falls back to "straight at you" when nothing is close.
func _threat_dir() -> Vector2:
	var nearest := _nearest_enemy(220.0 * U)
	if nearest:
		var d := Map3D.dir_map(global_position - nearest.global_position)
		if d.length_squared() > 0.000001:
			return d.normalized()
	return Vector2.ZERO

func heal(amount: int) -> void:
	var prev := hp
	hp = mini(hp + amount, MAX_HP)
	if hp > prev:
		AudioManager.play_sfx("heal")
		Fx3D.glyph(self, _head(), "+%d" % (hp - prev), COL_HEAL, 24, 0.8, 1.1)
	health_changed.emit(hp, MAX_HP)
	if _proxy != null and is_instance_valid(_proxy):
		_proxy.set_field("hp", hp)
	_update_low_hp()

## Death flow is UNCHANGED from 2D and still fully synchronous — trauma, `died`,
## then GameManager.handle_player_death() in that exact order (3D_BIBLE §4, and
## tests/death_respawn_test.gd for the 2D twin). Everything cosmetic here is
## fire-and-forget: it never awaits and never sits between those calls.
func _die() -> void:
	_low_hp = false
	_cache_t = 0.0
	_dash_timer = 0.0
	_iframe_t = 0.0
	_flash_t = 0.0
	_set_overlay(false)
	if is_instance_valid(model_root):
		model_root.visible = true
		model_root.position.y = 0.0
		model_root.scale = Vector3.ONE
	if is_instance_valid(bubble):
		bubble.visible = false
	if is_instance_valid(reticle):
		reticle.visible = false
	# A full-body collapse, then the model dissolves under it. The hold is long
	# on purpose: the corpse must not stand back up into idle behind the death
	# screen. respawn() zeroes `_pose_t`, so nothing is stuck.
	_pose("die", 30.0, ["fall"])
	if _model:
		Fx3D.dissolve(_model, COL_DAMAGE, 0.6)
	Fx3D.add_trauma(get_tree(), 0.6)
	Fx3D.burst(self, _center(), COL_DAMAGE, 24, 4.5, 0.7)
	Fx3D.glyph(self, _head(), "session expired", COL_DAMAGE, 26, 1.4, 1.4)
	died.emit()
	GameManager.handle_player_death()

func respawn(pos: Vector2) -> void:
	global_position = Map3D.to3d(pos, 0.0)
	hp = MAX_HP
	health_changed.emit(hp, MAX_HP)
	if _proxy != null and is_instance_valid(_proxy):
		_proxy.set_field("hp", hp)
	can_move = true
	# Undo every cosmetic the death sequence applied, so you never respawn
	# tilted, tinted, shielded or mid-recoil.
	_cache_t = 0.0
	_cache_absorbed = 0
	_cache_absorbed_dmg = 0
	_dash_timer = 0.0
	_pose_t = 0.0
	_ext_impulse = Vector2.ZERO
	_kick = Vector2.ZERO
	_move_vel = Vector3.ZERO
	velocity = Vector3.ZERO
	_run_t = 0.0
	_sprint = 0.0
	_step_squash = 0.0
	_stride_t = 0.0
	_iframe_t = 0.0
	_flash_t = 0.0
	_flow_t = 0.0
	_insight_t = 0.0
	_blast_chain = 0
	_blast_chain_t = 0.0
	_deny_t = 0.0
	_low_hp = false
	_look_t = 0.0
	_retic_target = null
	_hp_hist.clear()  # a fresh body has no damage to undo
	_set_overlay(false)
	# The death dissolve left every surface on a shader that ended fully
	# transparent; without this the respawned hero is an invisible body.
	_restore_materials()
	if is_instance_valid(glow):
		glow.light_color = LAMP_WARM  # lamp out of emergency red
		glow.light_energy = LAMP_ENERGY
		glow.omni_range = LAMP_RANGE
	if is_instance_valid(bubble):
		bubble.visible = false
		bubble.scale = Vector3.ONE
	if is_instance_valid(reticle):
		reticle.visible = false
	if is_instance_valid(model_root):
		model_root.visible = true
		model_root.position = Vector3.ZERO
		model_root.scale = Vector3.ONE
	_anim.play("idle", 0.05, 1.0, ["static"])
	_face_model(true)
	_sync_proxy()

# ------------------------------------------------------------------ prompt --

## The "[E]" prompt so players always know when — and what — they can interact
## with. ONE at a time, and it belongs to the TARGET: the label is attached to
## the closest interactable itself (ScreenLabels follows it, clamps it inside the
## safe area and stacks it off that thing's other captions), and it is detached
## the moment the target changes or the player walks away. It fades instead of
## popping so it reads as UI rather than a strobe.
func _update_prompt(delta: float) -> void:
	var closest := _closest_interactable()
	# A prompt is an offer to press a key, so it is worthless the moment the key
	# does nothing: mid-dialogue, or with any modal open (the quest log, the map,
	# the Dream App, the pause menu). Those all take the screen, and a world
	# caption burning through underneath them is the "boxes around boxes" of
	# LAW 8 with an extra layer. Same three tests `_should_hide()` in
	# objective_waypoint.gd runs, in the same order.
	var wants: bool = closest is Node3D and can_move \
		and GameManager.state == GameManager.GameState.PLAYING \
		and not EventManager.has_active_event() \
		and not DialogueManager.is_active \
		and not UIManager.has_blocking_ui()
	var target: Node3D = null
	if wants:
		target = closest as Node3D
	if target != null and target != _prompt_owner:
		# One prompt in the world: the old target's label goes before the new one
		# is made, so walking a line of crates never leaves a trail of them. The
		# FADE is not reset — between two props a step apart the prompt moves and
		# changes its words; it does not blink out and back in.
		ScreenLabels.detach(_prompt_label)
		_prompt_owner = target
		var text := "Interact"
		if target.has_method("get_prompt"):
			text = str(target.get_prompt())
		# PROMPT_PRIORITY, and see its comment: lowest in the world, so this is
		# the first caption to yield when the frame gets crowded.
		_prompt_label = ScreenLabels.attach(target, "[E] %s" % text,
			ScreenLabels.SMALL, GameTheme.TEXT, PROMPT_HEIGHT, PROMPT_PRIORITY)
		_prompt_label.modulate = Color(1.0, 1.0, 1.0, _prompt_a)
	# The owner can be freed under us (a prop that despawns, a region rebuild);
	# ScreenLabels frees the label with it, so both are checked before either is
	# written to.
	if not is_instance_valid(_prompt_label) or not is_instance_valid(_prompt_owner):
		_clear_prompt()
		return
	_prompt_a = move_toward(_prompt_a, 1.0 if _prompt_owner == target else 0.0, delta * 7.0)
	if _prompt_a <= 0.001 and _prompt_owner != target:
		_clear_prompt()
		return
	_prompt_label.modulate = Color(1.0, 1.0, 1.0, _prompt_a)

## Retire the current prompt, whatever state it is in.
func _clear_prompt() -> void:
	ScreenLabels.detach(_prompt_label)
	_prompt_label = null
	_prompt_owner = null
	_prompt_a = 0.0

func _closest_interactable() -> Node:
	var closest: Node = null
	var closest_dist := INF
	for n in nearby_interactables:
		if is_instance_valid(n) and n is Node3D:
			var d := global_position.distance_to((n as Node3D).global_position)
			if d < closest_dist:
				closest_dist = d
				closest = n
	return closest

# ------------------------------------------------------------------ signals --

## Idle personality. In 2D this swapped to a phone/laptop/coffee/panic frame;
## in 3D the character actually does something. All four clips are one-shot, so
## `_pose_t` is what returns him to idle.
func _on_idle_timer() -> void:
	if not can_move or _move_vel.length_squared() > 0.0001:
		idle_timer.start(randf_range(8.0, 14.0))
		return
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	var specials: Array[String] = ["emote-yes", "emote-no", "pick-up", "interact-left"]
	var pick: String = specials[randi() % specials.size()]
	if _anim.has(pick):
		# Hold for the clip's own length: a fixed 2.2s froze a 1s emote on its
		# last frame for over a second, which reads as a hang, not a bit.
		var clip := _anim.player.get_animation(pick)
		var hold: float = clip.length if clip else 2.2
		_pose(pick, clampf(hold, 0.4, 3.0))
	idle_timer.start(randf_range(10.0, 20.0))

## Arity matches ResourceManager.resource_changed(name, old_value, new_value)
## exactly — a mismatched handler is silently skipped (HANDOVER §4.3).
func _on_resource_changed(name: String, old_val: float, new_val: float) -> void:
	if name != "tokens" or new_val <= old_val:
		return
	Fx3D.burst(self, _center(), COL_GOLD, 10, 2.4, 0.4)
	# The cheer is a whole-body emote in 3D, so unlike the 2D one-frame version
	# it only fires when you are standing still, and not more than once every
	# few seconds — a token stream must not lock the character in applause.
	if _cheer_cd > 0.0 or _pose_t > 0.0:
		return
	if _move_vel.length_squared() > 0.04:
		return
	_cheer_cd = 4.0
	_pose("emote-yes", 0.9, ["interact-right"])

func _on_interact_area_area_entered(area: Area3D) -> void:
	var node: Node = area if area.is_in_group("interactable") else area.get_parent()
	if node and node.is_in_group("interactable") and node not in nearby_interactables:
		nearby_interactables.append(node)

func _on_interact_area_area_exited(area: Area3D) -> void:
	var node: Node = area if area.is_in_group("interactable") else area.get_parent()
	nearby_interactables.erase(node)

func _on_invincibility_timer_timeout() -> void:
	is_invincible = false
