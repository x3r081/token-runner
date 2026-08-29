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
	# Keep random events from firing mid-test (an active event freezes idle anim).
	GameManager.state = GameManager.GameState.PLAYING
	EventManager.reset()
	EventManager.cooldown = 1e9

	# Enemy: idle breathing moves the sprite; moving dips into a deeper hop.
	var e: Node = EnemyScene.instantiate()
	e.enemy_type = "bug"
	add_child(e)
	await get_tree().process_frame
	var spr: Node = e.get_node("Sprite2D")
	e.velocity = Vector2.ZERO
	var idle := _y_span(e, spr, 40, 0.05)
	_check("enemy_idle_breathes (range=%.2f)" % (idle.y - idle.x), (idle.y - idle.x) > 1.0)
	e.velocity = Vector2(80, 0)
	var move := _y_span(e, spr, 60, 0.03)
	# Scuttle hop dips clearly lower (more negative min y) than the idle breathe.
	_check("enemy_scuttle_hops_lower (min %.2f < %.2f)" % [move.x, idle.x], move.x < idle.x - 1.5)
	e.queue_free()

	# NPC: breathing moves the sprite.
	var n: Node = NpcScene.instantiate()
	n.npc_id = "maintainer"
	add_child(n)
	await get_tree().process_frame
	var nspr: Node = n.get_node("Sprite2D")
	var nspan := _y_span(n, nspr, 40, 0.05)
	_check("npc_breathes (range=%.2f)" % (nspan.y - nspan.x), (nspan.y - nspan.x) > 1.0)
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

## Returns Vector2(min_y, max_y) of the sprite over N procedural-animation steps.
func _y_span(node: Node, spr: Node, steps: int, dt: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in steps:
		node._process(dt)
		lo = minf(lo, spr.position.y)
		hi = maxf(hi, spr.position.y)
	return Vector2(lo, hi)

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
