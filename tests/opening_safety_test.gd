extends Node
## Regression test for opening pacing: a brand-new player who spawns in Localhost
## and stands still (learning the controls) must NOT be swarmed to death almost
## immediately. Bugs live on the far side and the player gets spawn grace, so a
## stationary player should survive comfortably for the first several seconds.
## Run: godot --headless --path . tests/opening_safety_test.tscn

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("OPENING SAFETY TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	if ResourceManager.has_method("reset"):
		ResourceManager.reset()
	GameManager.current_region = "localhost"
	GameManager.show_opening_sequence = false
	GameManager.state = GameManager.GameState.PLAYING

	var world: Node = preload("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	for i in 5:
		await get_tree().physics_frame

	var player: Node = get_tree().get_first_node_in_group("player")
	_check("player_exists", player != null)
	if player == null:
		return
	# Mirror the post-opening state: control + spawn grace.
	if player.has_method("grant_spawn_grace"):
		player.grant_spawn_grace()

	# Stand perfectly still for ~6 seconds of physics.
	var frames := 360
	var died_frame := -1
	for i in frames:
		await get_tree().physics_frame
		if GameManager.state == GameManager.GameState.GAME_OVER:
			died_frame = i
			break
	_check("stationary_new_player_survives_opening (died_frame=%d)" % died_frame, died_frame == -1)
	_check("player_alive_and_full_or_high_hp (hp=%d)" % (player.hp if is_instance_valid(player) else -1),
		is_instance_valid(player) and player.hp >= 70)

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
