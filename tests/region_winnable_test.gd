extends Node
## Regression test: the FIRST combat region (Dependency District) must be a fair,
## winnable introduction. A player who simply stands near the pack and fires
## Prompt Blast on cooldown should clear every enemy and survive — no difficulty
## spike that a new player can't beat. (Two playtests flagged the old 7-enemy pack
## as unfairly punishing; ground truth: clearing 7 barely beat the ~14s swarm
## death. Reduced to 4.)
## Run: godot --headless --path . tests/region_winnable_test.tscn

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("REGION WINNABLE TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	GameManager.current_region = "dependency_district"
	GameManager.show_opening_sequence = false
	GameManager.state = GameManager.GameState.PLAYING
	EventManager.reset(); EventManager.cooldown = 1e9
	var world: Node = preload("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	for i in 5: await get_tree().physics_frame
	var player: Node = get_tree().get_first_node_in_group("player")
	var enemies := get_tree().get_nodes_in_group("enemy")
	_check("first_region_enemy_count_is_gentle (%d)" % enemies.size(), enemies.size() <= 4)

	# Realistic engagement: the player approaches the pack (staying at a short
	# shooting distance) and fires on cooldown. Crucially, the player faces the
	# WRONG way (UP) the whole time — so ONLY the new aim-assist can land hits.
	# This proves a player who can't twitch-aim an 8-direction facing can still win.
	var c := Vector2.ZERO
	for e in enemies: c += e.global_position
	c /= maxf(1.0, enemies.size())
	player.global_position = c + Vector2(-120, 0)
	player.is_invincible = false
	await get_tree().physics_frame
	var fire := 0.0
	var cleared := false
	for i in 1800:
		await get_tree().physics_frame
		fire -= 1.0 / 60.0
		var living := get_tree().get_nodes_in_group("enemy").filter(func(e): return is_instance_valid(e) and not e._dying)
		if living.is_empty():
			cleared = true
			break
		# Close toward the nearest enemy but hold a ~90px shooting gap (kiting-ish).
		var nearest: Node2D = living[0]
		for e in living:
			if player.global_position.distance_to(e.global_position) < player.global_position.distance_to(nearest.global_position):
				nearest = e
		var to_n: Vector2 = nearest.global_position - player.global_position
		if to_n.length() > 90.0:
			player.global_position += to_n.normalized() * 3.0
		player.facing = Vector2.UP  # deliberately not aimed; aim-assist must carry
		if fire <= 0.0:
			fire = 0.8
			player._fire_projectile("prompt_blast", 30)
		if GameManager.state == GameManager.GameState.GAME_OVER or player.hp <= 0:
			break
	_check("aim_assist_clears_first_region_without_aiming", cleared)
	_check("player_survives_first_fight (hp=%d)" % (player.hp if is_instance_valid(player) else -1),
		is_instance_valid(player) and player.hp > 0)

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
