extends Node
## Regression test for the enemy soft-lock defect.
##
## Historically the player (CharacterBody2D) collided with enemy bodies, and
## enemies could stack on top of each other, so a ring of enemies could pin the
## player in place permanently. This test surrounds the player with a tight ring
## of enemies and verifies that:
##   1. Collision layers are configured so enemies never block the player.
##   2. Holding a movement direction still moves the player out of the ring.
##   3. The dash / Force Push ability shoves surrounding enemies away.
##
## Run: godot --headless --path . --scene tests/soft_lock_test.tscn

const PlayerScene := preload("res://scenes/player/player.tscn")
const EnemyScene := preload("res://scenes/combat/enemy.tscn")

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("SOFT-LOCK TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	GameManager.state = GameManager.GameState.PLAYING
	GameManager.player_position = Vector2.ZERO
	if DialogueManager:
		DialogueManager.is_active = false

	var player: Node = PlayerScene.instantiate()
	add_child(player)
	player.global_position = Vector2(600, 400)
	player.can_move = true
	await get_tree().physics_frame

	var enemies := _surround(player.global_position, 8, 14.0)
	await get_tree().physics_frame

	# 1. Collision configuration: enemies must not be in the player's mask, and
	#    the player must not be in the enemy's mask.
	_check("player_mask_excludes_enemies", (player.collision_mask & 2) == 0)
	_check("enemy_mask_excludes_player", (enemies[0].collision_mask & 1) == 0)

	# 2. Movement escape: hold "move_right" and confirm the player travels a
	#    meaningful distance despite being fully surrounded.
	var start_x: float = player.global_position.x
	Input.action_press("move_right")
	for i in 45:
		await get_tree().physics_frame
	Input.action_release("move_right")
	var moved: float = player.global_position.x - start_x
	_check("player_escapes_ring_by_walking (moved %.1fpx)" % moved, moved > 80.0)

	# 3. Dash / Force Push escape from a fresh surround.
	player.global_position = Vector2(600, 400)
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().physics_frame
	enemies = _surround(player.global_position, 8, 14.0)
	await get_tree().physics_frame
	var before := _avg_enemy_dist(player.global_position, enemies)
	player.facing = Vector2.RIGHT
	player._dash_cd = 0.0
	player._start_dash()
	for i in 20:
		await get_tree().physics_frame
	var after := _avg_enemy_dist(player.global_position, enemies)
	_check("force_push_pushes_enemies_away (%.1f -> %.1f)" % [before, after], after > before + 20.0)

func _surround(center: Vector2, count: int, radius: float) -> Array:
	var out: Array = []
	for i in count:
		var ang := TAU * float(i) / float(count)
		var e: Node = EnemyScene.instantiate()
		e.enemy_type = "bug"
		e.max_hp = 20
		add_child(e)
		e.global_position = center + Vector2(cos(ang), sin(ang)) * radius
		out.append(e)
	return out

func _avg_enemy_dist(center: Vector2, enemies: Array) -> float:
	var total := 0.0
	var n := 0
	for e in enemies:
		if is_instance_valid(e):
			total += center.distance_to(e.global_position)
			n += 1
	return total / maxf(1.0, float(n))

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
