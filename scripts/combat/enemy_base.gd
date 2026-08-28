extends CharacterBody2D
class_name EnemyBase

@export var enemy_type: String = "bug"
@export var max_hp: int = 30
@export var damage: int = 10
@export var speed: float = 80.0
@export var token_drop: int = 8
@export var is_boss: bool = false
@export var generation: int = 0  # for merge_conflict splitting

@onready var sprite: Sprite2D = $Sprite2D
@onready var hitbox: Area2D = $Hitbox
@onready var attack_timer: Timer = $AttackTimer

## Enemies orbit the player at ENGAGE_DISTANCE and repel each other within
## SEPARATION_RADIUS instead of physically colliding with the player. Combined
## with the player/enemy collision masks (walls only), this makes it impossible
## for a ring of enemies to permanently trap the player. See tests/soft_lock_test.
const ENGAGE_DISTANCE := 34.0
const SEPARATION_RADIUS := 46.0
const KNOCKBACK_DECAY := 900.0

var hp: int
var target: Node2D = null
var _flash_tween: Tween
var _knockback := Vector2.ZERO
var _stun_time := 0.0
var _base_speed := 0.0
var _base_scale := Vector2.ONE
var _grow := 0.0
var _special_cd := 0.0
var _telegraph := 0.0

func _ready() -> void:
	add_to_group("enemy")
	hp = max_hp
	if is_boss:
		max_hp *= 4
		hp = max_hp
		damage *= 2
		token_drop *= 5
		scale = Vector2(2, 2)
	_base_speed = speed
	_base_scale = scale
	_special_cd = randf_range(2.5, 4.5)
	var tex_path := "res://assets/textures/generated/enemy_%s.png" % enemy_type
	if ResourceLoader.exists(tex_path):
		sprite.texture = load(tex_path)
	attack_timer.timeout.connect(_attack)
	attack_timer.start(randf_range(1.0, 2.0))

func stun(duration: float) -> void:
	_stun_time = maxf(_stun_time, duration)

func _physics_process(delta: float) -> void:
	# Knockback (e.g. from the player's Force Push dash) always resolves, even
	# while combat is paused, so the player can always shove enemies away.
	if _knockback.length() > 5.0:
		velocity = _knockback
		move_and_slide()
		_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
		return
	if _combat_paused():
		velocity = Vector2.ZERO
		return
	# Stunned (e.g. by Rubber Duck): frozen but still shoveable via knockback.
	if _stun_time > 0.0:
		_stun_time -= delta
		velocity = Vector2.ZERO
		sprite.modulate = Color(0.55, 0.65, 1.0)
		if _stun_time <= 0.0:
			sprite.modulate = Color.WHITE
		return
	if not target or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player")
		return
	_update_special(delta)
	var to_player := target.global_position - global_position
	var dist := to_player.length()
	var desired := Vector2.ZERO
	if dist > ENGAGE_DISTANCE:
		desired = to_player.normalized() * speed
	else:
		# Hold at engage range and orbit slightly rather than piling onto the player.
		desired = to_player.normalized() * speed * 0.12
	desired += _separation() * speed
	velocity = desired
	move_and_slide()
	if absf(velocity.x) > 1.0:
		sprite.flip_h = velocity.x < 0

## Per-type signature behaviours + telegraphs. Never traps the player.
func _update_special(delta: float) -> void:
	match enemy_type:
		"scope_creep":
			# Requirements never stop growing. It gets bigger and faster.
			_grow = minf(_grow + delta * 0.09, 1.0)
			scale = _base_scale * (1.0 + _grow * 0.7)
			speed = _base_speed * (1.0 + _grow * 0.9)
		"memory_leak":
			# Slowly bloats as it leaks.
			_grow = minf(_grow + delta * 0.05, 0.6)
			scale = _base_scale * (1.0 + _grow)
		"rate_limiter":
			_tick_rate_limiter(delta)
		"hallucination":
			_special_cd -= delta
			if _special_cd <= 0.0:
				_blink()
				_special_cd = randf_range(2.2, 3.6)

func _tick_rate_limiter(delta: float) -> void:
	if _telegraph > 0.0:
		# Flash while winding up the 429 pulse.
		_telegraph -= delta
		sprite.modulate = Color(1.0, 0.85, 0.2) if fmod(_telegraph, 0.2) < 0.1 else Color.WHITE
		if _telegraph <= 0.0:
			sprite.modulate = Color.WHITE
			_rate_pulse()
		return
	_special_cd -= delta
	if _special_cd <= 0.0 and target and global_position.distance_to(target.global_position) < 280.0:
		_telegraph = 0.6
		_special_cd = randf_range(3.5, 5.5)

## 429: shove the player back (temporary, decaying — never a trap).
func _rate_pulse() -> void:
	if target and is_instance_valid(target) and target.has_method("apply_external_knockback"):
		var away: Vector2 = target.global_position - global_position
		if away.length() < 240.0:
			target.apply_external_knockback(away.normalized() * 430.0)
	AudioManager.play_sfx("ability")

func _blink() -> void:
	var ang := randf() * TAU
	global_position += Vector2(cos(ang), sin(ang)) * 74.0
	sprite.modulate = Color(1, 1, 1, 0.4)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.3)

## Repel from nearby enemies so they surround the player instead of stacking
## into a single blob (which previously helped wall the player in).
func _separation() -> Vector2:
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other):
			continue
		var away: Vector2 = global_position - other.global_position
		var d := away.length()
		if d > 0.01 and d < SEPARATION_RADIUS:
			push += away.normalized() * (1.0 - d / SEPARATION_RADIUS)
	return push

func apply_knockback(impulse: Vector2) -> void:
	_knockback = impulse

func _combat_paused() -> bool:
	if GameManager.state != GameManager.GameState.PLAYING:
		return true
	if DialogueManager.is_active:
		return true
	var player := get_tree().get_first_node_in_group("player")
	if player and "can_move" in player and not player.can_move:
		return true
	return false

func take_damage(amount: int) -> void:
	hp -= amount
	_flash_damage()
	if hp <= 0:
		_die()

func _flash_damage() -> void:
	if _flash_tween:
		_flash_tween.kill()
	sprite.modulate = Color(2, 2, 2)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)

func _attack() -> void:
	if _combat_paused():
		attack_timer.start(1.0)
		return
	if not target or global_position.distance_to(target.global_position) > 40:
		attack_timer.start(1.0)
		return
	if target.has_method("take_damage"):
		target.take_damage(damage, enemy_type)
	attack_timer.start(randf_range(1.2, 2.5))

func _die() -> void:
	# A merge conflict resolves into two smaller, incompatible conflicts.
	if enemy_type == "merge_conflict" and generation < 1 and not is_boss:
		_split()
	QuestManager.on_enemy_defeated(enemy_type)
	GameManager.record_stat("enemies_defeated")
	AudioManager.play_sfx("enemy_death")
	_spawn_tokens()
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)

func _split() -> void:
	var scene := preload("res://scenes/combat/enemy.tscn")
	for i in 2:
		var e = scene.instantiate()
		e.enemy_type = "merge_conflict"
		e.max_hp = maxi(6, int(max_hp / 2))
		e.damage = maxi(4, int(damage * 0.7))
		e.token_drop = maxi(1, int(token_drop / 2))
		e.generation = generation + 1
		get_parent().add_child(e)
		e.global_position = global_position + Vector2(randf_range(-26, 26), randf_range(-26, 26))
		e.scale = _base_scale * 0.68

func _spawn_tokens() -> void:
	var token_scene := preload("res://scenes/world/token_pickup.tscn")
	var count := 1 if not is_boss else 5
	for i in count:
		var t = token_scene.instantiate()
		t.amount = token_drop / count
		t.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		get_parent().add_child(t)

func _on_hitbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("player_projectile"):
		var dmg: int = area.get("damage") if area.get("damage") else 10
		take_damage(dmg)
		area.queue_free()
