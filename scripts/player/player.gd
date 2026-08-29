extends CharacterBody2D
class_name Player

signal health_changed(current: int, max_hp: int)
signal died

const SPEED := 220.0
const MAX_HP := 100
const FRAME_SIZE := 64
const _spr_base_y := -20.0
var _idle_breath_t := 0.0

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

func _ready() -> void:
	add_to_group("player")
	y_sort_enabled = true
	if GameManager.player_position != Vector2.ZERO:
		global_position = GameManager.player_position
	_setup_sprite_frames()
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
	_tick_pose(delta)
	_track_hp_history(delta)
	_tick_cache(delta)
	_ext_impulse = _ext_impulse.move_toward(Vector2.ZERO, 1300.0 * delta)
	_update_prompt(delta)
	if _fx:
		# Uses last frame's velocity for the motion lean — one frame of lag on a
		# 4-degree tilt is invisible, and it keeps this call allocation-free.
		_fx.sample(delta, velocity / SPEED)
	if not can_move or GameManager.state != GameManager.GameState.PLAYING or EventManager.has_active_event():
		velocity = Vector2.ZERO
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
		facing = input_dir.normalized()
		velocity = facing * SPEED
		_update_facing_dir()
		_walk_timer += delta
		if _walk_timer > 0.12:
			_walk_timer = 0.0
			_walk_frame = (_walk_frame + 1) % 4
		if _pose_t <= 0.0:
			_play_facing_anim("walk")
		idle_timer.start(randf_range(10.0, 18.0))
		sprite.position.y = _spr_base_y  # walk frames carry the motion
		_set_dust(true)
	else:
		velocity = Vector2.ZERO
		_set_dust(false)
		if not sprite.animation in ["phone_idle", "laptop_idle", "coffee_idle", "panic_idle"]:
			if _pose_t <= 0.0:
				_play_facing_anim("idle")
			# Subtle breathing so the player doesn't look frozen while idle.
			_idle_breath_t += delta
			sprite.position.y = _spr_base_y + sin(_idle_breath_t * 2.6) * 1.6
		else:
			sprite.position.y = _spr_base_y
	velocity += _ext_impulse
	move_and_slide()
	GameManager.player_position = global_position
	ResourceManager.regenerate_focus(delta * 0.5)

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

func _use_ability(ability: String) -> void:
	if ability_cooldown.time_left > 0:
		return
	match ability:
		"prompt_blast":
			var cost := prompt_cost()
			if ResourceManager.get_value("tokens") < cost:
				return
			ResourceManager.modify("tokens", -cost)
			var dmg := int(round(25.0 * ModelManager.dmg_mult()))
			# Low-reliability models can hallucinate: the blast fizzles.
			var weak := false
			if randf() > ModelManager.reliability():
				dmg = maxi(1, int(dmg * 0.2))
				weak = true
				GameManager.record_stat("reloads_detected")
			_fire_projectile("prompt_blast", dmg, false, weak)
			_play_cast_pose()
			ability_cooldown.start(0.8)
		"cache":
			if ResourceManager.get_value("compute") < 3:
				return
			ResourceManager.modify("compute", -3)
			is_invincible = true
			invincibility.start(CACHE_DURATION)
			ability_cooldown.start(3.0)
			_cache_t = CACHE_DURATION
			if _fx:
				_fx.open_cache(Color("#24F0DC"))
		"rubber_duck":
			# Explain the bug to the duck: nearby enemies freeze (you found it).
			if _duck_cd > 0.0 or ResourceManager.get_value("context") < 5:
				return
			ResourceManager.modify("context", -5)
			_duck_cd = 4.5
			_rubber_duck()
		"stack_trace":
			# A piercing trace that chains through a whole line of enemies.
			if _trace_cd > 0.0 or ResourceManager.get_value("tokens") < 10:
				return
			ResourceManager.modify("tokens", -10)
			_trace_cd = 1.6
			_fire_projectile("stack_trace", 22, true)
			_play_cast_pose()
		"ctrl_z":
			# Undo: restore the HP you had a couple seconds ago (panic recovery).
			if _ctrlz_cd > 0.0 or ResourceManager.get_value("context") < 4:
				return
			var prev := _hp_from_ago(CTRLZ_WINDOW)
			if prev <= hp:
				return  # nothing to undo
			ResourceManager.modify("context", -4)
			_ctrlz_cd = CTRLZ_COOLDOWN
			var before := hp
			hp = mini(prev, MAX_HP)
			health_changed.emit(hp, MAX_HP)
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
		if _fx:
			_fx.close_cache()

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
		_fx.cast_rubber_duck(RUBBER_DUCK_RADIUS)

func _start_dash() -> void:
	if _dash_cd > 0.0 or not can_move:
		return
	if GameManager.state != GameManager.GameState.PLAYING:
		return
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
	var nearest: Node2D = null
	var best := AIM_ASSIST_RANGE
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e.get("_dying"):
			var d: float = global_position.distance_to(e.global_position)
			if d < best:
				best = d
				nearest = e
	if nearest:
		return (nearest.global_position - global_position).normalized()
	return facing if facing != Vector2.ZERO else Vector2.RIGHT

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
	if _fx:
		if type == "stack_trace":
			_fx.cast_stack_trace(dir, Color("#FF2D95"), 760.0)
		else:
			_fx.cast_prompt_blast(dir, ModelManager.color(), weak)

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
		if _cache_t > 0.0 and _fx:
			_fx.ping_cache()
		return
	hp -= amount
	health_changed.emit(hp, MAX_HP)
	if _fx:
		_fx.hurt(amount, _threat_dir())
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
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.28)
	FxLib.add_trauma(get_tree(), 0.25)
	AudioManager.play_sfx("damage")
	if SettingsManager.get_setting("camera_shake"):
		var cam := get_viewport().get_camera_2d()
		if cam and cam.has_method("shake"):
			cam.shake(0.3, 3.0)
	is_invincible = true
	invincibility.start(0.8)
	if hp <= 0:
		_die()

## Which way the pain came from, for the recoil. Cheapest correct answer: the
## nearest living enemy. Falls back to "straight at you" when nothing is close.
func _threat_dir() -> Vector2:
	var nearest: Node2D = null
	var best := 220.0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e.get("_dying"):
			var d: float = global_position.distance_to(e.global_position)
			if d < best:
				best = d
				nearest = e
	if nearest:
		return (global_position - nearest.global_position).normalized()
	return Vector2.ZERO

func heal(amount: int) -> void:
	var prev := hp
	hp = mini(hp + amount, MAX_HP)
	if hp > prev:
		AudioManager.play_sfx("heal")
	health_changed.emit(hp, MAX_HP)

## Death flow is UNCHANGED and still fully synchronous — trauma, `died`, then
## GameManager.handle_player_death() in that exact order (see
## tests/death_respawn_test.gd). The cinematic is cosmetic and self-cleaning:
## it never awaits, never pauses, and never sits between those calls.
func _die() -> void:
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
	_dash_timer = 0.0
	_pose_t = 0.0
	_cast_t = 0.0
	_ext_impulse = Vector2.ZERO
	if _flash_tween:
		_flash_tween.kill()
	if is_instance_valid(sprite):
		sprite.modulate = Color.WHITE
		sprite.rotation = 0.0
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
