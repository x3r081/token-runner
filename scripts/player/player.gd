extends CharacterBody2D
class_name Player

signal health_changed(current: int, max_hp: int)
signal died

const SPEED := 220.0
const MAX_HP := 100
const FRAME_SIZE := 64

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
	if not can_move or GameManager.state != GameManager.GameState.PLAYING:
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
	else:
		velocity = Vector2.ZERO
		if not sprite.animation in ["phone_idle", "laptop_idle", "coffee_idle", "panic_idle"]:
			_play_facing_anim("idle")
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
	if event.is_action_pressed("interact"):
		_try_interact()
	if event.is_action_pressed("ability_1"):
		_use_ability("prompt_blast")
	if event.is_action_pressed("ability_2"):
		_use_ability("cache")
	if event.is_action_pressed("dash"):
		_start_dash()

func _try_interact() -> void:
	if nearby_interactables.is_empty():
		return
	var closest: Node = null
	var closest_dist := INF
	for n in nearby_interactables:
		if is_instance_valid(n):
			var d := global_position.distance_to(n.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = n
	if closest and closest.has_method("interact"):
		closest.interact(self)

func _use_ability(ability: String) -> void:
	if ability_cooldown.time_left > 0:
		return
	match ability:
		"prompt_blast":
			if ResourceManager.get_value("tokens") < 5:
				return
			ResourceManager.modify("tokens", -5)
			_fire_projectile("prompt_blast", 25)
			ability_cooldown.start(0.8)
		"cache":
			if ResourceManager.get_value("compute") < 3:
				return
			ResourceManager.modify("compute", -3)
			is_invincible = true
			invincibility.start(1.5)
			ability_cooldown.start(3.0)
	AudioManager.play_sfx("ability")

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

func _fire_projectile(type: String, damage: int) -> void:
	var proj_scene := preload("res://scenes/combat/projectile.tscn")
	var proj = proj_scene.instantiate()
	proj.setup(facing, damage, type)
	proj.global_position = global_position + facing * 20
	get_tree().current_scene.add_child(proj)

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
