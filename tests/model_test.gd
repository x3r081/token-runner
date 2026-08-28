extends Node
## Regression tests for the model-selection system: distinct trade-offs, cycling,
## and that the active model scales the player's Prompt Blast token cost.
##
## Run: godot --headless --path . --scene tests/model_test.tscn

const PlayerScene := preload("res://scenes/player/player.tscn")

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("MODEL TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	ModelManager.reset()
	_check("defaults_to_fast", ModelManager.current().id == "fast")

	# Cycling wraps back to the start after a full loop.
	var start := ModelManager.index
	for i in ModelManager.MODELS.size():
		ModelManager.cycle()
	_check("cycle_wraps", ModelManager.index == start)

	# Distinct trade-offs.
	ModelManager.set_model("local")
	var local_dmg := ModelManager.dmg_mult()
	var local_cost := ModelManager.cost_mult()
	ModelManager.set_model("frontier")
	_check("frontier_hits_harder", ModelManager.dmg_mult() > local_dmg)
	_check("frontier_costs_more", ModelManager.cost_mult() > local_cost)
	ModelManager.set_model("experimental")
	ModelManager.set_model("fast")
	_check("experimental_less_reliable_than_fast",
		_reliability_of("experimental") < ModelManager.reliability())

	# Model scales the player's Prompt Blast cost.
	GameManager.state = GameManager.GameState.PLAYING
	GameManager.player_position = Vector2.ZERO
	var player: Node = PlayerScene.instantiate()
	add_child(player)
	await get_tree().physics_frame
	ModelManager.set_model("local")
	var cost_local: int = player.prompt_cost()
	ModelManager.set_model("frontier")
	var cost_frontier: int = player.prompt_cost()
	_check("prompt_cost_scales_with_model (%d -> %d)" % [cost_local, cost_frontier], cost_frontier > cost_local)
	_check("local_cost_is_cheap", cost_local <= 3)
	player.queue_free()

func _reliability_of(id: String) -> float:
	for m in ModelManager.MODELS:
		if m.id == id:
			return float(m.reliability)
	return 1.0

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
