extends Node
## Regression test for the death/respawn P0:
##  - player._die() emits `died` AND calls handle_player_death() (emits
##    player_died). Both were wired to the world, stacking TWO death screens; the
##    Respawn button freed only the top one, so respawn appeared broken.
##  - respawn must restore control AND grant i-frames so the player can't re-die
##    instantly into the same enemies.
##
## Run: godot --headless --path . tests/death_respawn_test.tscn

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("DEATH/RESPAWN TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	if ResourceManager.has_method("reset"):
		ResourceManager.reset()
	GameManager.death_count = 0
	GameManager.current_region = "localhost"
	GameManager.show_opening_sequence = false
	GameManager.state = GameManager.GameState.PLAYING

	var world: Node = preload("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	for i in 5:
		await get_tree().physics_frame

	var player: Node = get_tree().get_first_node_in_group("player")
	var hud: Node = world.get_node("HUD")
	_check("player_exists", player != null)
	_check("hud_exists", hud != null)
	if player == null or hud == null:
		return

	# Simulate a transient overlay (e.g. a flavor popup) open at the moment of
	# death — it must be cleared so it can't eat the respawn click.
	var blocker := Control.new()
	blocker.name = "FlavorPopup"
	hud.add_child(blocker)

	# Kill the player (bypassing spawn-grace i-frames).
	player.is_invincible = false
	player.hp = 1
	player.take_damage(999)
	for i in 4:
		await get_tree().physics_frame

	_check("blocking_overlay_cleared_on_death", hud.get_node_or_null("FlavorPopup") == null)
	# EXACTLY ONE death screen, despite the double death-signal path.
	var screens := 0
	for c in hud.get_children():
		if c.name == "DeathScreen":
			screens += 1
	_check("exactly_one_death_screen (got %d)" % screens, screens == 1)
	_check("state_is_game_over", GameManager.state == GameManager.GameState.GAME_OVER)

	# Respawn via the death screen button handler.
	var death := hud.get_node_or_null("DeathScreen")
	if death and death.has_method("_on_respawn"):
		death._on_respawn()
	for i in 4:
		await get_tree().physics_frame

	_check("death_screen_cleared_after_respawn", hud.get_node_or_null("DeathScreen") == null)
	_check("state_playing_after_respawn", GameManager.state == GameManager.GameState.PLAYING)
	_check("player_can_move_after_respawn", is_instance_valid(player) and player.can_move)
	_check("player_hp_restored", is_instance_valid(player) and player.hp == player.MAX_HP)
	_check("player_has_iframes_after_respawn", is_instance_valid(player) and player.is_invincible)
	# Respawn must return the player to the region's safe spawn, not the death
	# location (which may be inside the enemy pile).
	_check("respawn_at_region_spawn (%s)" % str(GameManager.region_spawn),
		is_instance_valid(player) and player.global_position == GameManager.region_spawn
		and GameManager.region_spawn != Vector2.ZERO)

	# No re-swarm: after respawn, enemies must be sent home (far from the player),
	# so the player can't die again instantly to the pile that killed them.
	var min_dist := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			min_dist = minf(min_dist, player.global_position.distance_to(e.global_position))
	_check("enemies_sent_home_after_respawn (min_dist=%.0f)" % min_dist, min_dist > 300.0)

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
