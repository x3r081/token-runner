extends Node
## Regression tests for bosses: real boss scaling (only applied when is_boss is
## set), the telegraphed slam (knocks the player back, never traps), and the
## Enterprise Architect summoning adds.
##
## Run: godot --headless --path . --scene tests/boss_test.tscn

const PlayerScene := preload("res://scenes/player/player.tscn")
const EnemyScene := preload("res://scenes/combat/enemy.tscn")

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("BOSS TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	GameManager.state = GameManager.GameState.PLAYING
	GameManager.player_position = Vector2.ZERO
	if DialogueManager:
		DialogueManager.is_active = false

	# Boss scaling only applies when is_boss is set.
	var boss := _spawn_boss("enterprise_architect", Vector2(400, 400), 120)
	await get_tree().physics_frame
	_check("boss_scaled_up", boss.scale == Vector2(2, 2))
	_check("boss_hp_multiplied", boss.max_hp == 480)
	_check("boss_damage_doubled", boss.damage == 20)

	# Slam knocks the player back (temporary — never a trap).
	var player := _spawn_player(Vector2(430, 400))
	await get_tree().physics_frame
	boss.target = player
	boss._boss_slam()
	_check("boss_slam_knocks_player", player._ext_impulse.length() > 0.0)

	# Enterprise Architect summons adds; other bosses do not.
	var before := _enemy_count()
	boss._boss_slam()
	_check("architect_summons_adds", _enemy_count() == before + 1)

	var monolith := _spawn_boss("legacy_monolith", Vector2(800, 400), 200)
	await get_tree().physics_frame
	monolith.target = player
	var before2 := _enemy_count()
	monolith._boss_slam()
	_check("non_architect_does_not_summon", _enemy_count() == before2)

func _spawn_boss(type: String, pos: Vector2, hp: int) -> Node:
	var e: Node = EnemyScene.instantiate()
	e.enemy_type = type
	e.max_hp = hp
	e.is_boss = true
	add_child(e)
	e.global_position = pos
	return e

func _spawn_player(pos: Vector2) -> Node:
	var p: Node = PlayerScene.instantiate()
	add_child(p)
	p.global_position = pos
	p.can_move = true
	return p

func _enemy_count() -> int:
	return get_tree().get_nodes_in_group("enemy").size()

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
