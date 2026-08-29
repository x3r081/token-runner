extends CharacterBody2D
class_name Player

signal health_changed(current: int, max_hp: int)
signal died

const SPEED := 220.0
const MAX_HP := 100
const FRAME_SIZE := 64
const _spr_base_y := -20.0
var _idle_breath_t := 0.0

## ---------------------------------------------------------------- movement --
## Weight without lag. ACCEL reaches full speed in ~0.09s and FRICTION stops in
## ~0.07s, so the character has mass but never eats an input; TURN_BOOST doubles
## the acceleration when you reverse, so a direction change stays instant even
## though a standing start does not. Tuned against tests/soft_lock_test.gd,
## which walks for 45 physics frames and demands >80px of travel.
const ACCEL := 2450.0
const FRICTION := 3200.0
const TURN_BOOST := 2.2
## The velocity WE own. `velocity` itself is rewritten by move_and_slide() when
## you scrape a wall; keeping our own copy means sliding never eats the ramp.
var _move_vel := Vector2.ZERO
## A short, hard shove owned by the player: gun recoil and hit reactions. Kept
## separate from `_ext_impulse` (which enemies set) so neither can stomp the
## other — and so tests that assert on `_ext_impulse` stay meaningful.
var _kick := Vector2.ZERO
const KICK_DECAY := 1500.0
## Sprint settle: after a second of unbroken travel the stride opens up. Long
## traversals stop feeling flat, and the ramp is small enough that combat
## spacing is unchanged (a fight is all starts, stops and turns).
const SPRINT_DELAY := 0.95
const SPRINT_RAMP := 0.85
const SPRINT_BONUS := 0.17
var _run_t := 0.0
var _sprint := 0.0
var _sprint_fx_t := 0.0
## Footstep cadence. STRIDE_PERIOD deliberately matches AudioManager's
## FOOTSTEP_INTERVAL so the bob, the puff and the sound land on the same beat.
const STRIDE_PERIOD := 0.26
var _stride_t := 0.0
var _step_squash := 0.0
var _spr_base_scale := Vector2.ONE

## Dash / Force Push: a guaranteed escape + knockback tool. Even if enemies ever
## crowd the player, a dash bursts through them and shoves them away.
const DASH_SPEED := 660.0
const DASH_DURATION := 0.18
const DASH_COOLDOWN := 1.1
const FORCE_PUSH_RADIUS := 120.0
const FORCE_PUSH_IMPULSE := 560.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow: Sprite2D = $Shadow
@onready var hitbox: Area2D = $Hitbox
@onready var interact_area: Area2D = $InteractArea
@onready var ability_cooldown: Timer = $AbilityCooldown
@onready var invincibility: Timer = $InvincibilityTimer
@onready var particles: CPUParticles2D = $CollectParticles
@onready var idle_timer: Timer = $IdleTimer

var hp: int = MAX_HP
var facing := Vector2.DOWN
var can_move := true
var is_invincible := false
var nearby_interactables: Array[Node] = []
var _facing_dir := "down"
var _walk_frame := 0
var _walk_timer := 0.0
var _dash_timer := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector2.DOWN
var _prompt_label: Label
## A short, decaying push (e.g. a Rate Limiter's 429 pulse). It never removes
## control — the player can always walk against it — so it can't cause a trap.
var _ext_impulse := Vector2.ZERO
var _duck_cd := 0.0
var _trace_cd := 0.0
var _ctrlz_cd := 0.0
## Rolling (time, hp) history so Ctrl+Z can undo damage taken in the last few sec.
var _hp_hist: Array = []
const CTRLZ_WINDOW := 2.6
const CTRLZ_COOLDOWN := 10.0
## Juice rig: carried light, footstep dust, dash afterimages, damage flash.
var _light: PointLight2D
var _dust: CPUParticles2D
var _flash_tween: Tween
var _ghost_t := 0.0
## Spectacle rig (scripts/player/ability_fx.gd): rim halo, motion lean, rewind
## buffer and the six ability signatures. Always null-checked — a stripped test
## scene or a missing FX library must never break movement or damage.
var _fx: AbilityFx
## Cache (ability 2) runs its own clock so the hex bubble matches the window it
## actually represents, instead of riding the shared i-frame timer that dashes
## and hurt-frames also poke.
const CACHE_DURATION := 1.5
var _cache_t := 0.0
## Crits: 14% of shots land as a hard hit. Purely additive damage — it can only
## make a fight shorter, never longer.
const CRIT_CHANCE := 0.14
const CRIT_MULT := 2.0
## One-shot pose frames (spritesheet rows 4-5). `_pose_t` is a lockout so the
## walk/idle animator does not stamp over a cast or a recoil the same frame it
## started; `_cast_t` drives the two-stage wind-up -> release pair. Both are
## only ever armed when the animation actually exists, so the legacy 4-frame
## fallback sheet keeps behaving exactly as before.
const CAST_WINDUP := 0.09
const CAST_RELEASE := 0.18
var _pose_t := 0.0
var _cast_t := 0.0

## ------------------------------------------------------------ combat feel --
## Prompt Blast cadence ramp. The base rate is unchanged (0.8s), but shots fired
## inside CHAIN_WINDOW of each other tighten toward 0.52s, so a sustained
## engagement builds rhythm and a poke costs the same as it always did. The HUD
## sweep reads `ability_cooldown.wait_time` live, so it follows automatically.
const BLAST_CADENCE: Array[float] = [0.8, 0.68, 0.58, 0.52]
const CHAIN_WINDOW := 1.6
var _blast_chain := 0
var _blast_chain_t := 0.0
## Perfect dodge: dash THROUGH a telegraphed attack and you enter FLOW — a short
## speed and damage boost plus most of the dash cooldown back. The dodge is the
## skill; the reward is what makes learning enemy tells worth it.
const PERFECT_RANGE := 215.0
const FLOW_DURATION := 3.0
const FLOW_SPEED := 0.18
const FLOW_DAMAGE := 0.30
var _flow_t := 0.0
## Rubber Duck's real role: it does not just stun, it finds the bug. For
## INSIGHT_WINDOW after a duck, everything you fire hits harder — duck then
## blast is the combo the ability exists to set up.
const INSIGHT_WINDOW := 2.6
const INSIGHT_DAMAGE := 0.35
var _insight_t := 0.0
## Cache bookkeeping, so the shield can report what it actually did.
var _cache_absorbed := 0
var _cache_absorbed_dmg := 0
const CACHE_REFUND := 2
## Hurt i-frames: the shared InvincibilityTimer is poked by dashes and Cache too,
## so the flicker runs on its own clock and only ever means "you were hit".
const HURT_IFRAMES := 0.8
const FLASH_TIME := 0.28
var _iframe_t := 0.0
## Low-HP state. Crossing LOW_HP_FRAC arms a presentation you cannot miss; it
## clears the moment you climb back out of it. The fraction deliberately matches
## hud.gd's own LOW_HP_FRAC so the character-side dressing and the HUD-side
## danger vignette/bar pulse arm on the same hit — one state, not two.
const LOW_HP_FRAC := 0.34
var _low_hp := false
## Throttle for "that did not fire, and here is why" callouts.
var _deny_t := 0.0
## Reticle refresh clock (see _update_reticle).
var _retic_t := 0.0

func _ready() -> void:
	add_to_group("player")
	y_sort_enabled = true
	if GameManager.player_position != Vector2.ZERO:
		global_position = GameManager.player_position
	_setup_sprite_frames()
	# Captured AFTER the frame setup, which is what decides the sheet scale
	# (2.2 for the full sheet, 2.8 for the legacy fallback). The footstep squash
	# multiplies this, so reading it too early would shrink the player.
	_spr_base_scale = sprite.scale
	_setup_shadow()
	hp = MAX_HP
	ResourceManager.resource_changed.connect(_on_resource_changed)
	idle_timer.timeout.connect(_on_idle_timer)
	idle_timer.start(randf_range(8.0, 14.0))
	_setup_prompt()
	_setup_fx()

## The player carries a soft warm light (the world is dark on purpose) and kicks
## up dust while moving. Missing art degrades to generated textures, never errors.
func _setup_fx() -> void:
	_light = FxLib.point_light(self, Color(1.0, 0.93, 0.82), 0.55, 3.4, Vector2(0, -12))
	# A desk lamp at 3am is never perfectly steady. Engine-side loop, no cost.
	var lamp := _light.create_tween().set_loops()
	lamp.tween_property(_light, "energy", 0.62, 1.7).set_trans(Tween.TRANS_SINE)
	lamp.tween_property(_light, "energy", 0.50, 2.3).set_trans(Tween.TRANS_SINE)
	_dust = CPUParticles2D.new()
	_dust.emitting = false
	_dust.amount = 12
	_dust.lifetime = 0.42
	_dust.local_coords = false  # puffs stay where the foot fell
	_dust.spread = 180.0
	_dust.direction = Vector2.UP
	_dust.gravity = Vector2(0, -22)
	_dust.initial_velocity_min = 6.0
	_dust.initial_velocity_max = 18.0
	_dust.color = Color(0.62, 0.58, 0.72, 0.4)
	_dust.position = Vector2(0, 6)
	_dust.z_index = -1
	var dot := FxLib.glow_dot()
	if dot:
		_dust.texture = dot
		_dust.scale_amount_min = 0.35
		_dust.scale_amount_max = 0.7
	else:
		_dust.scale_amount_min = 1.4
		_dust.scale_amount_max = 2.6
	add_child(_dust)
	_fx = AbilityFx.new()
	_fx.name = "AbilityFx"
	add_child(_fx)
	_fx.setup(self, sprite)

func _set_dust(on: bool) -> void:
	if _dust and _dust.emitting != on:
		_dust.emitting = on

## Floating "[E]" prompt so players always know when (and what) they can interact with.
func _setup_prompt() -> void:
	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 15)
	_prompt_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.85))
	_prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_prompt_label.add_theme_constant_override("outline_size", 5)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Absolute, not relative. The player y-sorts (z_index = int(y)), so a
	# relative z would slide the prompt around the readout band as you walk
	# up and down the room instead of pinning it above world plates (1150)
	# and below combat damage text (1220).
	_prompt_label.z_as_relative = false
	_prompt_label.z_index = CombatFx.Z_TEXT - 10
	_prompt_label.visible = false
	_prompt_label.modulate.a = 0.0
	add_child(_prompt_label)

func _update_prompt(delta: float = 0.016) -> void:
	if not is_instance_valid(_prompt_label):
		return
	var closest := _closest_interactable()
	var wants := closest != null and can_move and GameManager.state == GameManager.GameState.PLAYING and not EventManager.has_active_event()
	if wants:
		var text := "Interact"
		if closest.has_method("get_prompt"):
			text = closest.get_prompt()
		_prompt_label.text = "[E] %s" % text
		# NPCs own the space above their heads now: npc.gd puts the nameplate at
		# y -106..-86 and stacks bark bubbles above that. -64 landed the prompt
		# across the sprite's chest and under the plate. Put it below the feet
		# for a person, keep the old offset for scenery, which has nothing there.
		var lift := 34.0 if "npc_id" in closest else -64.0
		_prompt_label.position = (closest.global_position - global_position) + Vector2(-70, lift)
		_prompt_label.custom_minimum_size = Vector2(140, 0)
	# Fade in/out instead of popping, so the prompt feels like UI, not a strobe.
	var a := move_toward(_prompt_label.modulate.a, 1.0 if wants else 0.0, delta * 7.0)
	_prompt_label.modulate.a = a
	_prompt_label.visible = a > 0.02

func _closest_interactable() -> Node:
	var closest: Node = null
	var closest_dist := INF
	for n in nearby_interactables:
		if is_instance_valid(n):
			var d := global_position.distance_to(n.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = n
	return closest

func _setup_shadow() -> void:
	var tex: Texture2D = load("res://assets/textures/generated/player_shadow.png")
	if tex:
		shadow.texture = tex
		shadow.position = Vector2(0, 8)
		shadow.z_index = -1

func _setup_sprite_frames() -> void:
	if sprite.sprite_frames and sprite.sprite_frames.get_animation_names().size() > 4:
		return
	var sheet_path := "res://assets/textures/generated/player_spritesheet.png"
	if not ResourceLoader.exists(sheet_path):
		_setup_legacy_frames()
		return
	var sheet: Texture2D = load(sheet_path)
	var frames := SpriteFrames.new()
	var anims := {
		"idle_down": [0], "walk_down": [1, 2, 3, 4],
		"idle_up": [6], "walk_up": [7, 8, 9, 10],
		"idle_side": [12], "walk_side": [13, 14, 15, 16],
		"hurt": [18], "celebrate": [19], "phone_idle": [20],
		"laptop_idle": [21], "coffee_idle": [22], "panic_idle": [23],
		# Rows 4-5: combat poses. Indices 0-23 above are frozen.
		"dash_down": [24], "dash_up": [25], "dash_side": [26],
		"cast_down": [27], "cast_up": [28], "cast_side": [29],
		"cast_release_down": [30], "cast_release_up": [31], "cast_release_side": [32],
		"hurt_up": [33], "hurt_side": [34], "celebrate_side": [35],
	}
	for anim_name in anims:
		frames.add_animation(anim_name)
		for idx in anims[anim_name]:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			var col: int = int(idx) % 6
			var row: int = int(idx) / 6
			atlas.region = Rect2(col * FRAME_SIZE, row * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
			frames.add_frame(anim_name, atlas)
		frames.set_animation_speed(anim_name, 8.0 if anim_name.begins_with("walk") else 2.0)
		if anim_name.begins_with("walk"):
			frames.set_animation_loop(anim_name, true)
	sprite.sprite_frames = frames
	sprite.play("idle_down")
	sprite.scale = Vector2(2.2, 2.2)

func _setup_legacy_frames() -> void:
	var frame_map := {
		"idle_down": ["player_idle.png"],
		"walk_down": ["player_walk1.png", "player_walk2.png"],
		"hurt": ["player_hurt.png"],
		"celebrate": ["player_celebrate.png"],
	}
	var frames := SpriteFrames.new()
	for anim in frame_map:
		frames.add_animation(anim)
		for fname in frame_map[anim]:
			var tex: Texture2D = load("res://assets/textures/generated/%s" % fname)
			if tex:
				frames.add_frame(anim, tex)
	sprite.sprite_frames = frames
	sprite.play("idle_down")
	sprite.scale = Vector2(2.8, 2.8)

func _physics_process(delta: float) -> void:
	z_index = int(global_position.y)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_duck_cd = maxf(0.0, _duck_cd - delta)
	_trace_cd = maxf(0.0, _trace_cd - delta)
	_ctrlz_cd = maxf(0.0, _ctrlz_cd - delta)
	_deny_t = maxf(0.0, _deny_t - delta)
	_insight_t = maxf(0.0, _insight_t - delta)
	_blast_chain_t = maxf(0.0, _blast_chain_t - delta)
	if _blast_chain_t <= 0.0:
		_blast_chain = 0
	_tick_flow(delta)
	_tick_iframes(delta)
	_kick = _kick.move_toward(Vector2.ZERO, KICK_DECAY * delta)
	_tick_pose(delta)
	_track_hp_history(delta)
	_tick_cache(delta)
	_ext_impulse = _ext_impulse.move_toward(Vector2.ZERO, 1300.0 * delta)
	_update_prompt(delta)
	_update_reticle(delta)
	if _fx:
		# Uses last frame's velocity for the motion lean — one frame of lag on a
		# 4-degree tilt is invisible, and it keeps this call allocation-free.
		_fx.sample(delta, velocity / SPEED)
	if not can_move or GameManager.state != GameManager.GameState.PLAYING or EventManager.has_active_event():
		velocity = Vector2.ZERO
		_move_vel = Vector2.ZERO
		_run_t = 0.0
		_sprint = 0.0
		# A pause mid-step must not leave the sprite frozen mid-squash.
		_step_squash = 0.0
		_apply_step_scale()
		_set_dust(false)
		if sprite.animation.begins_with("walk"):
			_play_facing_anim("idle")
		return
	if _dash_timer > 0.0:
		_dash_timer -= delta
		velocity = _dash_dir * DASH_SPEED
		# Chromatic afterimages trailing the dash (5-6 over its duration).
		_ghost_t -= delta
		if _ghost_t <= 0.0:
			_ghost_t += DASH_DURATION / 5.0
			_spawn_dash_ghost()
		_play_facing_anim("dash")
		_set_dust(true)
		# The dash branch returns early, so the stride squash has to be unwound
		# here too — otherwise a dash begun on a footstep contact freezes the
		# sprite mid-squash for the whole 0.18s.
		_step_squash = maxf(0.0, _step_squash - delta * 7.0)
		_apply_step_scale()
		# Hand the dash's momentum back to the walk ramp, so releasing a dash
		# while still holding the stick continues at speed instead of restarting.
		_move_vel = _dash_dir * SPEED
		move_and_slide()
		GameManager.player_position = global_position
		if _dash_timer <= 0.0 and _fx:
			_fx.dash_end()
		return
	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if input_dir != Vector2.ZERO:
		var want_dir := input_dir.normalized()
		facing = want_dir
		# Reversing gets the boosted ramp: a standing start has weight, a
		# direction change does not. This is the whole trick — mass on the
		# outside, zero input lag on the inside.
		var accel := ACCEL
		if _move_vel.dot(want_dir) < 0.0:
			accel *= TURN_BOOST
			_run_t = 0.0  # a reversal is not a traversal; the stride settles
		_move_vel = _move_vel.move_toward(want_dir * SPEED * _speed_mult(), accel * delta)
		velocity = _move_vel
		_update_facing_dir()
		_walk_timer += delta
		if _walk_timer > 0.12:
			_walk_timer = 0.0
			_walk_frame = (_walk_frame + 1) % 4
		if _pose_t <= 0.0:
			_play_facing_anim("walk")
		idle_timer.start(randf_range(10.0, 18.0))
		_tick_stride(delta)
		_set_dust(true)
	else:
		_move_vel = _move_vel.move_toward(Vector2.ZERO, FRICTION * delta)
		velocity = _move_vel
		_run_t = 0.0
		_sprint = maxf(0.0, _sprint - delta * 3.0)
		_stride_t = STRIDE_PERIOD * 0.7  # next step lands as movement resumes
		_step_squash = maxf(0.0, _step_squash - delta * 7.0)
		_set_dust(_move_vel.length_squared() > 900.0)
		if not sprite.animation in ["phone_idle", "laptop_idle", "coffee_idle", "panic_idle"]:
			if _pose_t <= 0.0:
				_play_facing_anim("idle")
			# Subtle breathing so the player doesn't look frozen while idle.
			_idle_breath_t += delta
			sprite.position.y = _spr_base_y + sin(_idle_breath_t * 2.6) * 1.6
		else:
			sprite.position.y = _spr_base_y
		_apply_step_scale()
	# Impulses ride along for the SLIDE only, then `velocity` is put back to our
	# own locomotion. Everything outside this script reads `velocity` as "is the
	# player walking": AudioManager._poll_footsteps() fires a step above 30px/s,
	# so folding a 135px/s gun recoil in there played a phantom footstep on every
	# single shot, and _on_idle_timer()'s `velocity != ZERO` check never saw a
	# standing player again. move_and_slide()'s own write-back is already
	# discarded — `_move_vel` is the authority (see its declaration).
	velocity += _ext_impulse + _kick
	move_and_slide()
	velocity = _move_vel
	GameManager.player_position = global_position
	ResourceManager.regenerate_focus(delta * 0.5)

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

## Footstep cadence: a bob that peaks between contacts, a squash on the contact
## itself, and — once the stride opens up — a wake of speed lines. Costs one
## sin() and no allocations.
func _tick_stride(delta: float) -> void:
	_run_t += delta
	var want_sprint := clampf((_run_t - SPRINT_DELAY) / SPRINT_RAMP, 0.0, 1.0)
	_sprint = move_toward(_sprint, want_sprint, delta * 1.6)
	# The stride rate tracks the ACTUAL speed bonus, not a second hand-tuned
	# number that can drift away from it — a bob running faster than the body is
	# moving is exactly the "sliding" read this was added to kill.
	_stride_t += delta * (1.0 + _sprint * SPRINT_BONUS)
	if _stride_t >= STRIDE_PERIOD:
		_stride_t -= STRIDE_PERIOD
		_step_squash = 1.0
	_step_squash = maxf(0.0, _step_squash - delta * 7.0)
	var phase := clampf(_stride_t / STRIDE_PERIOD, 0.0, 1.0)
	sprite.position.y = _spr_base_y - absf(sin(phase * PI)) * (1.5 + _sprint * 0.9)
	_apply_step_scale()
	_sprint_fx_t -= delta
	if _sprint > 0.55 and _sprint_fx_t <= 0.0 and _fx:
		_sprint_fx_t = 0.36
		_fx.stride_wake(_move_vel, _sprint)

## Landing squash, applied on top of whatever sheet scale the player ended up
## with (2.2 normally, 2.8 on the legacy fallback sheet).
func _apply_step_scale() -> void:
	if not is_instance_valid(sprite):
		return
	var s := _step_squash * _step_squash  # sharp on contact, soft on recovery
	sprite.scale = Vector2(_spr_base_scale.x * (1.0 + s * 0.05),
		_spr_base_scale.y * (1.0 - s * 0.06))

## Flow decays on its own clock so the boost ends visibly, not silently.
func _tick_flow(delta: float) -> void:
	if _flow_t <= 0.0:
		return
	_flow_t = maxf(0.0, _flow_t - delta)
	if _flow_t <= 0.0 and _fx:
		_fx.set_flow(false)

## The i-frame flicker. Runs on its own clock (not the shared
## InvincibilityTimer, which dashes and Cache also poke) so a blink always means
## "you were hit and you are briefly safe". The damage flash owns `modulate` for
## its first FLASH_TIME; the flicker only starts after it, so they never fight.
func _tick_iframes(delta: float) -> void:
	if _iframe_t <= 0.0:
		return
	_iframe_t = maxf(0.0, _iframe_t - delta)
	if not is_instance_valid(sprite):
		return
	if _iframe_t <= 0.0:
		sprite.modulate.a = 1.0
		return
	if _iframe_t < HURT_IFRAMES - FLASH_TIME:
		sprite.modulate.a = 0.30 if fmod(_iframe_t, 0.13) < 0.065 else 1.0

## "That did not fire, and here is exactly why." An ability that fails silently
## is an ability the player decides is broken. Throttled so mashing a key on
## cooldown prints one line, not twenty. (COMEDY_BIBLE: the number is the
## information — any quip rides beside it, never instead of it.)
func _deny(text: String) -> void:
	if _deny_t > 0.0:
		return
	_deny_t = 0.5
	AudioManager.play_sfx("denied")
	if _fx:
		_fx.deny(text)

## Arms/disarms the low-HP presentation. Called from every path that can move
## HP: damage, heal, Ctrl+Z and respawn.
func _update_low_hp() -> void:
	# Strictly LESS THAN, matching hud.gd's `frac < LOW_HP_FRAC` exactly. With
	# `<=` the character-side dressing armed one HP earlier than the HUD's
	# vignette, so at exactly 34 HP the player got half the state.
	var low: bool = hp > 0 and float(hp) < float(MAX_HP) * LOW_HP_FRAC
	if low == _low_hp:
		return
	_low_hp = low
	# The lamp you carry shifts to emergency lighting, so the whole room around
	# you changes colour when you are about to die — visible in the corner of the
	# eye without reading a single number. Deliberately a red SHIFT and not pure
	# red: this light is ~215px of radius and the state can hold for the rest of
	# a run (nothing heals except Ctrl+Z), so a saturated red here would wash the
	# floor material zones out from under the player permanently.
	if is_instance_valid(_light):
		var want: Color = Color(1.0, 0.50, 0.43) if low else Color(1.0, 0.93, 0.82)
		var lt := _light.create_tween()
		lt.tween_property(_light, "color", want, 0.35)
	if _fx:
		_fx.set_low_hp(low, hp)

func _update_facing_dir() -> void:
	if absf(facing.y) > absf(facing.x):
		_facing_dir = "up" if facing.y < 0 else "down"
	else:
		_facing_dir = "side"
		sprite.flip_h = facing.x < 0

func _play_facing_anim(prefix: String) -> void:
	var anim := "%s_%s" % [prefix, _facing_dir]
	if sprite.sprite_frames.has_animation(anim):
		if sprite.animation != anim:
			sprite.play(anim)

## Advances the one-shot pose clocks. The cast pose runs a wind-up frame and
## then a release frame (the one carrying the muzzle flash and follow-through);
## `_pose_t` mirrors whatever is left so walk/idle stay out of the way.
func _tick_pose(delta: float) -> void:
	if _cast_t > 0.0:
		_cast_t = maxf(0.0, _cast_t - delta)
		var want := "cast_%s" % _facing_dir
		if _cast_t <= CAST_RELEASE:
			want = "cast_release_%s" % _facing_dir
		if sprite.sprite_frames and sprite.sprite_frames.has_animation(want) \
				and sprite.animation != want:
			sprite.play(want)
		_pose_t = maxf(_pose_t, _cast_t)
		return
	_pose_t = maxf(0.0, _pose_t - delta)

## Arm the cast pose — no-op on the legacy sheet, which has no such frames.
func _play_cast_pose() -> void:
	if sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation("cast_%s" % _facing_dir):
		return
	_cast_t = CAST_WINDUP + CAST_RELEASE
	_pose_t = _cast_t

func _on_idle_timer() -> void:
	if not can_move or velocity != Vector2.ZERO:
		idle_timer.start(randf_range(8.0, 14.0))
		return
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	var specials := ["phone_idle", "laptop_idle", "coffee_idle", "panic_idle"]
	var pick: String = specials[randi() % specials.size()]
	if sprite.sprite_frames.has_animation(pick):
		sprite.play(pick)
		await get_tree().create_timer(2.5).timeout
		if velocity == Vector2.ZERO and can_move:
			_play_facing_anim("idle")
	idle_timer.start(randf_range(10.0, 20.0))

func _unhandled_input(event: InputEvent) -> void:
	# Ignore gameplay input while a modal event/storyline popup is showing.
	if EventManager.has_active_event():
		return
	# Same rule mid-conversation: ability keys pressed while reading dialogue
	# (or picking a choice) must not fire blasts and spend resources behind the
	# panel. DialogueUI handles its own advance/choice input.
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
		closest.interact(self)

## Every branch now states its own reason for refusing. The shared
## `ability_cooldown` still gates Prompt Blast and Cache against each other
## (that trade-off is the HUD's contract — hud.gd reads `ability_cooldown` for
## exactly those two ids), but it no longer silently swallows Rubber Duck,
## Stack Trace and Ctrl+Z, which own their own timers and which the HUD has
## always drawn as ready during it.
func _use_ability(ability: String) -> void:
	# No ability fires while the player has no control — the opening sequence, a
	# region transition, the death screen. Silent, because a refusal callout
	# floating over a cutscene is worse than no feedback at all. (The gap is
	# older than this pass; it only became visible once refusals started
	# speaking, and GAME_OVER in particular let [1] fire behind the death panel.)
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
			# relaxes back the moment you stop. Base rate is unchanged. Counted
			# before the shot so the muzzle can run hotter as the rhythm builds.
			_blast_chain = mini(_blast_chain + 1, BLAST_CADENCE.size())
			_blast_chain_t = CHAIN_WINDOW
			_fire_projectile("prompt_blast", dmg, false, weak)
			_play_cast_pose()
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
			if is_instance_valid(sprite):
				sprite.modulate.a = 1.0
			is_invincible = true
			invincibility.start(CACHE_DURATION)
			ability_cooldown.start(3.0)
			_cache_t = CACHE_DURATION
			if _fx:
				_fx.open_cache(Color("#24F0DC"))
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
			_play_cast_pose()
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
	if _cache_t <= 0.0:
		_cache_t = 0.0
		# A cache that served hits pays part of itself back; a cache that served
		# nothing was a cache miss, and the bubble says so on its way out. This
		# is what turns Cache from "press 2 sometimes" into a reactive read.
		# `hp > 0` because _physics_process keeps ticking through GAME_OVER (the
		# early-return sits BELOW this call), so a bubble that was still open when
		# you died would otherwise pay compute into a corpse's wallet while the
		# death screen is up.
		if _cache_absorbed > 0 and hp > 0:
			ResourceManager.modify("compute", CACHE_REFUND)
		if _fx:
			_fx.close_cache(_cache_absorbed, _cache_absorbed_dmg, CACHE_REFUND)
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

## Undo, but for your entire body: a green pulse on the sprite plus the full
## rewind sequence (ghosts running backwards down your own path, a clock
## unwinding, the restored HP counted back on).
func _ctrl_z_effect(healed: int = 0) -> void:
	sprite.modulate = Color(0.5, 1.6, 0.7)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.4)
	particles.emitting = true
	if _fx:
		_fx.cast_ctrl_z(maxi(0, healed))

const RUBBER_DUCK_RADIUS := 180.0

func _rubber_duck() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("stun"):
			if global_position.distance_to(e.global_position) < RUBBER_DUCK_RADIUS:
				e.stun(1.8)
	particles.emitting = true
	if _fx:
		_fx.cast_rubber_duck(RUBBER_DUCK_RADIUS, INSIGHT_WINDOW, INSIGHT_DAMAGE)

func _start_dash() -> void:
	# Control checks first: a cutscene or a menu should refuse in silence, only
	# a real cooldown earns a callout.
	if not can_move:
		return
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	# Also silent on cooldown — dash is mashed, and the HUD's [Q] sweep already
	# says how long is left.
	if _dash_cd > 0.0:
		return
	# Read the room BEFORE the dash moves us: a dash begun while something is
	# mid-telegraph inside PERFECT_RANGE is the dodge this game wants to reward.
	var perfect := _threat_incoming()
	_dash_dir = facing if facing != Vector2.ZERO else Vector2.DOWN
	_dash_timer = DASH_DURATION
	_dash_cd = DASH_COOLDOWN
	_ghost_t = 0.0  # first afterimage drops immediately
	is_invincible = true
	invincibility.start(DASH_DURATION + 0.12)
	_force_push()
	particles.emitting = true
	if _fx:
		_fx.dash_burst(_dash_dir)
	AudioManager.play_sfx("dash")
	if perfect:
		_grant_flow()

## Is something currently winding up an attack near enough to hit us?
##
## enemy_base.gd already answers exactly this question publicly — `is_committed()`
## ("locked into something the player must react to": melee coil, charge, Rate
## Limiter pulse, boss slam) — so ask that first. Probing the private clocks
## instead would put the whole reward on a rename nothing errors about: it would
## just quietly stop firing forever, which is precisely the bug class this
## project keeps shipping. The property probe stays as a fallback for anything in
## the `enemy` group that does not expose the method.
func _threat_incoming() -> bool:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e.get("_dying"):
			continue
		if global_position.distance_to(e.global_position) > PERFECT_RANGE:
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
## "walk away early". Deliberately short: it is a beat of mastery, not a buff
## you can sit on.
func _grant_flow() -> void:
	var refresh := _flow_t > 0.0
	_flow_t = FLOW_DURATION
	_dash_cd = maxf(0.0, _dash_cd - 0.45)
	FxLib.hit_stop(get_tree(), 0.3, 0.05)
	AudioManager.play_sfx("pickup_rare")
	if _fx:
		_fx.perfect_dodge(FLOW_DURATION, FLOW_DAMAGE, refresh)

## A fading snapshot of the current sprite frame, tinted overbright cyan so the
## dash leaves a neon smear through the dark. The FX rig upgrades this to a pair
## of chromatically-offset ghosts; the legacy single ghost is the fallback.
func _spawn_dash_ghost() -> void:
	if _fx:
		_fx.dash_ghost(_dash_dir)
		return
	var parent := get_parent()
	if parent == null or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(sprite.animation):
		return
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.flip_h = sprite.flip_h
	ghost.material = FxLib.additive_material()
	ghost.modulate = Color(0.31, 2.1, 1.9, 0.5)  # overbright CYAN echo
	ghost.z_index = z_index - 1
	parent.add_child(ghost)
	ghost.global_position = sprite.global_position
	ghost.scale = sprite.global_scale
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.34)
	tw.tween_callback(ghost.queue_free)

## Shove every nearby enemy away from the player. This is the design-level
## guarantee that the player can always break out of a crowd.
func _force_push() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var away: Vector2 = e.global_position - global_position
		var d := away.length()
		if d < FORCE_PUSH_RADIUS and d > 0.01 and e.has_method("apply_knockback"):
			var strength := 1.0 - d / FORCE_PUSH_RADIUS + 0.3
			e.apply_knockback(away.normalized() * FORCE_PUSH_IMPULSE * strength)

## Aim assist: fire toward the nearest living enemy in range so combat is about
## positioning/kiting/resources, not twitch-aiming an 8-direction facing. Falls
## back to the facing direction when no enemy is near.
const AIM_ASSIST_RANGE := 640.0

func _aim_dir() -> Vector2:
	var nearest := _nearest_enemy(AIM_ASSIST_RANGE)
	if nearest:
		return (nearest.global_position - global_position).normalized()
	return facing if facing != Vector2.ZERO else Vector2.RIGHT

## The one enemy query the whole script shares: aim assist, the hit-reaction
## direction and the reticle all mean "nearest living enemy inside `max_range`".
func _nearest_enemy(max_range: float) -> Node2D:
	var nearest: Node2D = null
	var best := max_range
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e.get("_dying"):
			var d: float = global_position.distance_to(e.global_position)
			if d < best:
				best = d
				nearest = e
	return nearest

## Aim assist has always silently picked your target; now it says which one.
## Refreshed at 15 Hz — a bracket that snaps a frame late is invisible, and a
## group scan every physics frame is not free once a boss starts summoning.
func _update_reticle(delta: float) -> void:
	if _fx == null:
		return
	_retic_t -= delta
	if _retic_t > 0.0:
		return
	_retic_t = 0.066
	var t: Node2D = null
	if GameManager.state == GameManager.GameState.PLAYING and can_move \
			and not DialogueManager.is_active and not EventManager.has_active_event():
		t = _nearest_enemy(AIM_ASSIST_RANGE)
	_fx.set_target(t)

## Spawn a bolt and play the ability's signature. `weak` is the hallucination
## misfire (the model was extremely confident and extremely wrong); `crit` is
## rolled here so every shot — including scripted ones — can land hard.
func _fire_projectile(type: String, damage: int, pierce: bool = false, weak: bool = false) -> void:
	var dir := _aim_dir()
	var crit := not weak and randf() < CRIT_CHANCE
	if crit:
		damage = int(round(float(damage) * CRIT_MULT))
	var proj_scene := preload("res://scenes/combat/projectile.tscn")
	var proj = proj_scene.instantiate()
	proj.setup(dir, damage, type)
	proj.pierce = pierce
	proj.weak = weak
	proj.crit = crit
	proj.global_position = global_position + dir * 20
	get_tree().current_scene.add_child(proj)
	AudioManager.play_sfx("projectile_shoot")
	# Kickback. Small enough that it never fights your walk (it is spent in
	# ~0.1s), big enough that the gun has a butt. Stack Trace shoves harder,
	# because Stack Trace is the shoulder-fired one.
	if not weak:
		var push: float = 245.0 if type == "stack_trace" else 135.0
		if crit:
			push *= 1.35
		_kick = -dir * push
	if _fx:
		if type == "stack_trace":
			_fx.cast_stack_trace(dir, Color("#FF2D95"), 760.0)
		else:
			_fx.cast_prompt_blast(dir, ModelManager.color(), weak, crit,
				float(_blast_chain) / float(BLAST_CADENCE.size()))

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
	if is_invincible:
		# A hit that landed on the Cache bubble instead of you. Say so — an
		# ability the player can't see working is an ability they stop using.
		if _cache_t > 0.0:
			_cache_absorbed += 1
			_cache_absorbed_dmg += amount
			if _fx:
				_fx.ping_cache(_cache_absorbed)
		return
	hp -= amount
	health_changed.emit(hp, MAX_HP)
	var from_dir := _threat_dir()
	# Physical hit reaction: you get shoved away from what hit you. Short
	# (~0.18s) and always walkable-against, so it reads as impact, never as
	# lost control.
	if from_dir.length_squared() > 0.0001:
		_kick = from_dir * (170.0 + clampf(float(amount) * 6.0, 0.0, 150.0))
	if _fx:
		_fx.hurt(amount, from_dir)
	var hurt_anim := "hurt_%s" % _facing_dir
	if not sprite.sprite_frames.has_animation(hurt_anim):
		hurt_anim = "hurt"
	if sprite.sprite_frames.has_animation(hurt_anim):
		sprite.play(hurt_anim)
		_cast_t = 0.0
		_pose_t = 0.30
	# Overbright red flash + a camera kick: pain must read instantly, mid-chaos.
	if _flash_tween:
		_flash_tween.kill()
	sprite.modulate = Color(2.3, 0.5, 0.5)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, FLASH_TIME)
	FxLib.add_trauma(get_tree(), 0.25)
	AudioManager.play_sfx("damage")
	if SettingsManager.get_setting("camera_shake"):
		var cam := get_viewport().get_camera_2d()
		if cam and cam.has_method("shake"):
			cam.shake(0.3, 3.0)
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
	var nearest := _nearest_enemy(220.0)
	if nearest:
		return (global_position - nearest.global_position).normalized()
	return Vector2.ZERO

func heal(amount: int) -> void:
	var prev := hp
	hp = mini(hp + amount, MAX_HP)
	if hp > prev:
		AudioManager.play_sfx("heal")
	health_changed.emit(hp, MAX_HP)
	_update_low_hp()

## Death flow is UNCHANGED and still fully synchronous — trauma, `died`, then
## GameManager.handle_player_death() in that exact order (see
## tests/death_respawn_test.gd). The cinematic is cosmetic and self-cleaning:
## it never awaits, never pauses, and never sits between those calls.
func _die() -> void:
	_low_hp = false
	FxLib.add_trauma(get_tree(), 0.6)
	if _fx:
		_fx.death_sequence()
	died.emit()
	GameManager.handle_player_death()

func respawn(pos: Vector2) -> void:
	global_position = pos
	hp = MAX_HP
	health_changed.emit(hp, MAX_HP)
	can_move = true
	# Undo every cosmetic the death sequence applied, so you never respawn
	# tilted, tinted, shielded or mid-recoil.
	_cache_t = 0.0
	_cache_absorbed = 0
	_cache_absorbed_dmg = 0
	_dash_timer = 0.0
	_pose_t = 0.0
	_cast_t = 0.0
	_ext_impulse = Vector2.ZERO
	_kick = Vector2.ZERO
	_move_vel = Vector2.ZERO
	_run_t = 0.0
	_sprint = 0.0
	_step_squash = 0.0
	_stride_t = 0.0
	_iframe_t = 0.0
	_flow_t = 0.0
	_insight_t = 0.0
	_blast_chain = 0
	_blast_chain_t = 0.0
	_deny_t = 0.0
	_low_hp = false
	if is_instance_valid(_light):
		_light.color = Color(1.0, 0.93, 0.82)  # lamp out of emergency red
	_hp_hist.clear()  # a fresh body has no damage to undo
	if _flash_tween:
		_flash_tween.kill()
	if is_instance_valid(sprite):
		sprite.modulate = Color.WHITE
		sprite.rotation = 0.0
		sprite.scale = _spr_base_scale
		sprite.position = Vector2(0, _spr_base_y)
	if _fx:
		_fx.reset_cosmetics()
	if is_instance_valid(sprite) and sprite.sprite_frames:
		_play_facing_anim("idle")

func _on_resource_changed(name: String, old_val: float, new_val: float) -> void:
	if name == "tokens" and new_val > old_val:
		particles.emitting = true
		var cheer := "celebrate_side" if _facing_dir == "side" else "celebrate"
		if not sprite.sprite_frames.has_animation(cheer):
			cheer = "celebrate"
		if sprite.sprite_frames.has_animation(cheer):
			sprite.play(cheer)
			_pose_t = 0.6
			await get_tree().create_timer(0.6).timeout
			_play_facing_anim("idle")

func _on_interact_area_area_entered(area: Area2D) -> void:
	var node: Node = area if area.is_in_group("interactable") else area.get_parent()
	if node and node.is_in_group("interactable") and node not in nearby_interactables:
		nearby_interactables.append(node)

func _on_interact_area_area_exited(area: Area2D) -> void:
	var node: Node = area if area.is_in_group("interactable") else area.get_parent()
	nearby_interactables.erase(node)

func _on_invincibility_timer_timeout() -> void:
	is_invincible = false
