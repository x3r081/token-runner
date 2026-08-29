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

## Floating "[E]" prompt so players always know when (and what) they can interact with.
func _setup_prompt() -> void:
	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 15)
	_prompt_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.85))
	_prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_prompt_label.add_theme_constant_override("outline_size", 5)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.z_index = 500
	_prompt_label.visible = false
	add_child(_prompt_label)

func _update_prompt() -> void:
	if not is_instance_valid(_prompt_label):
		return
	var closest := _closest_interactable()
	if closest and can_move and GameManager.state == GameManager.GameState.PLAYING and not EventManager.has_active_event():
		var text := "Interact"
		if closest.has_method("get_prompt"):
			text = closest.get_prompt()
		_prompt_label.text = "[E] %s" % text
		_prompt_label.position = (closest.global_position - global_position) + Vector2(-70, -64)
		_prompt_label.custom_minimum_size = Vector2(140, 0)
		_prompt_label.visible = true
	else:
		_prompt_label.visible = false

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
	_track_hp_history(delta)
	_ext_impulse = _ext_impulse.move_toward(Vector2.ZERO, 1300.0 * delta)
	_update_prompt()
	if not can_move or GameManager.state != GameManager.GameState.PLAYING or EventManager.has_active_event():
		velocity = Vector2.ZERO
		if sprite.animation.begins_with("walk"):
			_play_facing_anim("idle")
		return
	if _dash_timer > 0.0:
		_dash_timer -= delta
		velocity = _dash_dir * DASH_SPEED
		move_and_slide()
		GameManager.player_position = global_position
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
		_play_facing_anim("walk")
		idle_timer.start(randf_range(10.0, 18.0))
		sprite.position.y = _spr_base_y  # walk frames carry the motion
	else:
		velocity = Vector2.ZERO
		if not sprite.animation in ["phone_idle", "laptop_idle", "coffee_idle", "panic_idle"]:
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
			if randf() > ModelManager.reliability():
				dmg = maxi(1, int(dmg * 0.2))
				GameManager.record_stat("reloads_detected")
			_fire_projectile("prompt_blast", dmg)
			ability_cooldown.start(0.8)
		"cache":
			if ResourceManager.get_value("compute") < 3:
				return
			ResourceManager.modify("compute", -3)
			is_invincible = true
			invincibility.start(1.5)
			ability_cooldown.start(3.0)
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
		"ctrl_z":
			# Undo: restore the HP you had a couple seconds ago (panic recovery).
			if _ctrlz_cd > 0.0 or ResourceManager.get_value("context") < 4:
				return
			var prev := _hp_from_ago(CTRLZ_WINDOW)
			if prev <= hp:
				return  # nothing to undo
			ResourceManager.modify("context", -4)
			_ctrlz_cd = CTRLZ_COOLDOWN
			hp = mini(prev, MAX_HP)
			health_changed.emit(hp, MAX_HP)
			_ctrl_z_effect()
	AudioManager.play_sfx("ability")

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

func _ctrl_z_effect() -> void:
	# A green "undo" pulse.
	sprite.modulate = Color(0.5, 1.6, 0.7)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.4)
	particles.emitting = true

const RUBBER_DUCK_RADIUS := 180.0

func _rubber_duck() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("stun"):
			if global_position.distance_to(e.global_position) < RUBBER_DUCK_RADIUS:
				e.stun(1.8)
	particles.emitting = true

func _start_dash() -> void:
	if _dash_cd > 0.0 or not can_move:
		return
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	_dash_dir = facing if facing != Vector2.ZERO else Vector2.DOWN
	_dash_timer = DASH_DURATION
	_dash_cd = DASH_COOLDOWN
	is_invincible = true
	invincibility.start(DASH_DURATION + 0.12)
	_force_push()
	particles.emitting = true
	AudioManager.play_sfx("ability")

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

func _fire_projectile(type: String, damage: int, pierce: bool = false) -> void:
	var proj_scene := preload("res://scenes/combat/projectile.tscn")
	var proj = proj_scene.instantiate()
	proj.setup(facing, damage, type)
	proj.pierce = pierce
	proj.global_position = global_position + facing * 20
	get_tree().current_scene.add_child(proj)

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
		return
	hp -= amount
	health_changed.emit(hp, MAX_HP)
	if sprite.sprite_frames.has_animation("hurt"):
		sprite.play("hurt")
	AudioManager.play_sfx("damage")
	if SettingsManager.get_setting("camera_shake"):
		var cam := get_viewport().get_camera_2d()
		if cam and cam.has_method("shake"):
			cam.shake(0.3, 3.0)
	is_invincible = true
	invincibility.start(0.8)
	if hp <= 0:
		_die()

func heal(amount: int) -> void:
	hp = mini(hp + amount, MAX_HP)
	health_changed.emit(hp, MAX_HP)

func _die() -> void:
	died.emit()
	GameManager.handle_player_death()

func respawn(pos: Vector2) -> void:
	global_position = pos
	hp = MAX_HP
	health_changed.emit(hp, MAX_HP)
	can_move = true

func _on_resource_changed(name: String, old_val: float, new_val: float) -> void:
	if name == "tokens" and new_val > old_val:
		particles.emitting = true
		if sprite.sprite_frames.has_animation("celebrate"):
			sprite.play("celebrate")
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
