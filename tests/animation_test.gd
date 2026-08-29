extends Node
## Regression test: enemies, NPCs, and the idle player have procedural liveliness
## (their sprites actually move), so nothing renders as a frozen sticker.
## Run: godot --headless --path . tests/animation_test.tscn

const EnemyScene := preload("res://scenes/combat/enemy.tscn")
const NpcScene := preload("res://scenes/world/npc.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("ANIMATION TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	# Enemy: idle breathing moves the sprite; moving produces a bigger hop.
	var e: Node = EnemyScene.instantiate()
	e.enemy_type = "bug"
	add_child(e)
	await get_tree().process_frame
	var spr: Node = e.get_node("Sprite2D")
	var base_y: float = spr.position.y
	e.velocity = Vector2.ZERO
	var idle_range := _y_range(e, spr, 30, 0.05)
	_check("enemy_idle_breathes (range=%.2f)" % idle_range, idle_range > 1.0)
	e.velocity = Vector2(80, 0)
	var move_range := _y_range(e, spr, 40, 0.03)
	_check("enemy_scuttle_hops_more (%.2f > %.2f)" % [move_range, idle_range], move_range > idle_range + 2.0)
	e.queue_free()

	# NPC: breathing moves the sprite.
	var n: Node = NpcScene.instantiate()
	n.npc_id = "maintainer"
	add_child(n)
	await get_tree().process_frame
	var nspr: Node = n.get_node("Sprite2D")
	var nrange := _y_range(n, nspr, 40, 0.05)
	_check("npc_breathes (range=%.2f)" % nrange, nrange > 1.0)
	n.queue_free()

	# Player: idle breathing moves the sprite while standing still.
	GameManager.state = GameManager.GameState.PLAYING
	var p: Node = PlayerScene.instantiate()
	add_child(p)
	p.can_move = true
	await get_tree().physics_frame
	var pspr: Node = p.get_node("AnimatedSprite2D")
	var pmin := INF
	var pmax := -INF
	for i in 40:
		p._physics_process(0.05)
		pmin = minf(pmin, pspr.position.y)
		pmax = maxf(pmax, pspr.position.y)
	_check("player_idle_breathes (range=%.2f)" % (pmax - pmin), (pmax - pmin) > 1.0)
	p.queue_free()

func _y_range(node: Node, spr: Node, steps: int, dt: float) -> float:
	var lo := INF
	var hi := -INF
	for i in steps:
		node._process(dt)
		lo = minf(lo, spr.position.y)
		hi = maxf(hi, spr.position.y)
	return hi - lo

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
