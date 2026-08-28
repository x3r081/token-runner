extends CharacterBody2D
class_name Player

signal health_changed(current: int, max_hp: int)
signal died

const SPEED := 220.0
const DASH_SPEED := 500.0
const MAX_HP := 100

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $Hitbox
@onready var interact_area: Area2D = $InteractArea
@onready var ability_cooldown: Timer = $AbilityCooldown
@onready var invincibility: Timer = $InvincibilityTimer
@onready var particles: CPUParticles2D = $CollectParticles

var hp: int = MAX_HP
var facing := Vector2.DOWN
var can_move := true
var is_invincible := false
var nearby_interactables: Array[Node] = []
var _walk_frame := 0
var _walk_timer := 0.0

func _ready() -> void:
	add_to_group("player")
	if GameManager.player_position != Vector2.ZERO:
		global_position = GameManager.player_position
	_setup_sprite_frames()
	hp = MAX_HP
	ResourceManager.resource_changed.connect(_on_resource_changed)

func _setup_sprite_frames() -> void:
	if sprite.sprite_frames:
		return
	var sheet: Texture2D = load("res://assets/external/kenney/roguelike/roguelikeChar_transparent.png")
	if not sheet:
		sheet = load("res://assets/textures/generated/player_idle.png")
		if sheet:
			var frames_fallback := SpriteFrames.new()
			frames_fallback.add_animation("idle")
			frames_fallback.add_frame("idle", sheet)
			sprite.sprite_frames = frames_fallback
			sprite.play("idle")
		return
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.add_animation("walk")
	frames.add_animation("hurt")
	frames.add_animation("celebrate")
	frames.set_animation_speed("idle", 3.0)
	frames.set_animation_speed("walk", 8.0)
	# Pre-made character column 0 — 16x16 cells, 1px gap
	var cell := 17
	var char_col := 0
	for row in 4:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2i(char_col * cell + 1, row * cell + 1, 16, 16)
		if row < 2:
			frames.add_frame("idle", atlas)
		else:
			frames.add_frame("walk", atlas)
	var hurt_atlas := AtlasTexture.new()
	hurt_atlas.atlas = sheet
	hurt_atlas.region = Rect2i(char_col * cell + 1, 4 * cell + 1, 16, 16)
	frames.add_frame("hurt", hurt_atlas)
	sprite.sprite_frames = frames
	sprite.play("idle")
	sprite.scale = Vector2(3.5, 3.5)

func _physics_process(delta: float) -> void:
	if not can_move or GameManager.state != GameManager.GameState.PLAYING:
		velocity = Vector2.ZERO
		return
	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if input_dir != Vector2.ZERO:
		facing = input_dir.normalized()
		velocity = input_dir.normalized() * SPEED
		sprite.play("walk")
		sprite.flip_h = facing.x < 0
	else:
		velocity = Vector2.ZERO
		sprite.play("idle")
	move_and_slide()
	GameManager.player_position = global_position
	ResourceManager.regenerate_focus(delta * 0.5)
	_check_ability_input()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()
	if event.is_action_pressed("ability_1"):
		_use_ability("prompt_blast")
	if event.is_action_pressed("ability_2"):
		_use_ability("cache")

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

func _fire_projectile(type: String, damage: int) -> void:
	var proj_scene := preload("res://scenes/combat/projectile.tscn")
	var proj = proj_scene.instantiate()
	proj.setup(facing, damage, type)
	proj.global_position = global_position + facing * 20
	get_tree().current_scene.add_child(proj)

func take_damage(amount: int, source: String = "") -> void:
	if is_invincible:
		return
	hp -= amount
	health_changed.emit(hp, MAX_HP)
	sprite.play("hurt")
	AudioManager.play_sfx("damage")
	if SettingsManager.get_setting("camera_shake"):
		var cam := get_viewport().get_camera_2d()
		if cam and cam.has_method("shake"):
			cam.shake(0.3, 8.0)
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

func _on_resource_changed(name: String, _old: float, new_val: float) -> void:
	if name == "tokens" and new_val > _old:
		particles.emitting = true

func _on_interact_area_area_entered(area: Area2D) -> void:
	var node: Node = area if area.is_in_group("interactable") else area.get_parent()
	if node and node.is_in_group("interactable") and node not in nearby_interactables:
		nearby_interactables.append(node)

func _on_interact_area_area_exited(area: Area2D) -> void:
	var node: Node = area if area.is_in_group("interactable") else area.get_parent()
	nearby_interactables.erase(node)

func _on_invincibility_timer_timeout() -> void:
	is_invincible = false

func _check_ability_input() -> void:
	pass
