extends Node
## Regression tests for combat depth: enemy signature behaviours and the new
## player abilities. Also re-verifies that new mechanics (rate-limiter pulse)
## never trap the player.
##
## Run: godot --headless --path . --scene tests/combat_test.tscn

const PlayerScene := preload("res://scenes/player/player.tscn")
const EnemyScene := preload("res://scenes/combat/enemy.tscn")
const ProjectileScene := preload("res://scenes/combat/projectile.tscn")

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("COMBAT TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	GameManager.state = GameManager.GameState.PLAYING
	GameManager.player_position = Vector2.ZERO
	if DialogueManager:
		DialogueManager.is_active = false
	EventManager.reset()
	EventManager.cooldown = 100000.0
	ResourceManager.reset()

	await _test_merge_split()
	await _test_scope_grows()
	await _test_rubber_duck_stun()
	_test_stack_trace_pierce()
	await _test_rate_limiter_no_trap()
	await _test_ctrl_z_undo()

func _spawn_enemy(type: String, pos: Vector2, hp: int = 20) -> Node:
	var e: Node = EnemyScene.instantiate()
	e.enemy_type = type
	e.max_hp = hp
	add_child(e)
	e.global_position = pos
	return e

func _spawn_player(pos: Vector2) -> Node:
	var p: Node = PlayerScene.instantiate()
	add_child(p)
	p.global_position = pos
	p.can_move = true
	return p

func _test_merge_split() -> void:
	var e := _spawn_enemy("merge_conflict", Vector2(200, 200), 20)
	await get_tree().physics_frame
	e.take_damage(999)
	# Wait out the death fade so the parent is freed and only splits remain.
	await get_tree().create_timer(0.5).timeout
	var splits := 0
	for n in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(n) and n.enemy_type == "merge_conflict" and n.generation == 1:
			splits += 1
	_check("merge_conflict_splits_into_two (%d)" % splits, splits == 2)
	for n in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(n):
			n.queue_free()
	await get_tree().physics_frame

func _test_scope_grows() -> void:
	var player := _spawn_player(Vector2(600, 600))
	var e := _spawn_enemy("scope_creep", Vector2(700, 600), 40)
	var s0: float = e.scale.x
	for i in 70:
		await get_tree().physics_frame
	_check("scope_creep_grows_over_time (%.3f->%.3f)" % [s0, e.scale.x], e.scale.x > s0 + 0.03)
	_check("scope_creep_speeds_up", e.speed > e._base_speed)
	e.queue_free()
	player.queue_free()
	await get_tree().physics_frame

func _test_rubber_duck_stun() -> void:
	var player := _spawn_player(Vector2(500, 500))
	var enemies: Array = []
	for off in [Vector2(40, 0), Vector2(-40, 20), Vector2(0, 50)]:
		enemies.append(_spawn_enemy("bug", Vector2(500, 500) + off, 20))
	await get_tree().physics_frame
	ResourceManager.reset()  # ensure enough context
	player._use_ability("rubber_duck")
	var stunned := 0
	for e in enemies:
		if is_instance_valid(e) and e._stun_time > 0.0:
			stunned += 1
	_check("rubber_duck_stuns_nearby (%d/3)" % stunned, stunned == 3)
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	player.queue_free()
	await get_tree().physics_frame

func _test_stack_trace_pierce() -> void:
	# Piercing projectile damages multiple enemies and survives.
	var proj: Node = ProjectileScene.instantiate()
	add_child(proj)
	proj.setup(Vector2.RIGHT, 15, "stack_trace")
	proj.pierce = true
	var a := _spawn_enemy("bug", Vector2(100, 100), 40)
	var b := _spawn_enemy("bug", Vector2(140, 100), 40)
	proj._on_area_entered(a.get_node("Hitbox"))
	proj._on_area_entered(b.get_node("Hitbox"))
	_check("pierce_hits_first", a.hp < a.max_hp)
	_check("pierce_hits_second", b.hp < b.max_hp)
	# Impact: hits shove the enemy along the shot direction (rightward here).
	_check("hit_applies_knockback", a._knockback.x > 50.0)
	# Clarity: a damaged enemy shows a health bar scaled to its remaining HP.
	_check("damaged_enemy_shows_hp_bar", is_instance_valid(a._hp_bar) and a._hp_bar.visible)
	_check("hp_bar_reflects_damage", a._hp_fill.size.x < a.HP_BAR_W)
	_check("pierce_projectile_survives", is_instance_valid(proj) and not proj.is_queued_for_deletion())
	# Non-piercing projectile is consumed on first hit.
	var proj2: Node = ProjectileScene.instantiate()
	add_child(proj2)
	proj2.setup(Vector2.RIGHT, 15, "prompt_blast")
	var c := _spawn_enemy("bug", Vector2(300, 100), 40)
	proj2._on_area_entered(c.get_node("Hitbox"))
	_check("non_pierce_consumed", proj2.is_queued_for_deletion())
	for n in [proj, a, b, c]:
		if is_instance_valid(n):
			n.queue_free()

func _test_rate_limiter_no_trap() -> void:
	var player := _spawn_player(Vector2(500, 500))
	# Enemy to the RIGHT so its pulse pushes the player LEFT (against walk dir).
	var e := _spawn_enemy("rate_limiter", Vector2(560, 500), 30)
	await get_tree().physics_frame
	e._rate_pulse()
	_check("rate_pulse_applies_knockback", player._ext_impulse.length() > 0.0)
	var x0: float = player.global_position.x
	Input.action_press("move_right")
	for i in 45:
		await get_tree().physics_frame
	Input.action_release("move_right")
	var moved: float = player.global_position.x - x0
	_check("player_still_moves_after_pulse (%.1f)" % moved, moved > 20.0)
	e.queue_free()
	player.queue_free()
	await get_tree().physics_frame

func _test_ctrl_z_undo() -> void:
	# Ctrl+Z restores HP lost in the last couple seconds (panic recovery), costs
	# context, and goes on cooldown.
	ResourceManager.reset()
	ResourceManager.resources["context"] = 50
	var player := _spawn_player(Vector2(200, 200))
	player.can_move = true
	await get_tree().physics_frame
	# ~3s of full HP history, then take a big hit.
	for i in 60:
		player._physics_process(0.05)
	player.hp = 40
	for i in 12:
		player._physics_process(0.05)
	var ctx0 := ResourceManager.get_value("context")
	player._use_ability("ctrl_z")
	_check("ctrl_z_restores_recent_hp (40 -> %d)" % player.hp, player.hp >= 90)
	_check("ctrl_z_costs_context", ResourceManager.get_value("context") == ctx0 - 4.0)
	_check("ctrl_z_on_cooldown", not player.ability_ready("ctrl_z"))
	# Second immediate use is blocked (cooldown) and doesn't over-heal / refund.
	player.hp = 30
	var ctx1 := ResourceManager.get_value("context")
	player._use_ability("ctrl_z")
	_check("ctrl_z_blocked_on_cooldown", player.hp == 30 and ResourceManager.get_value("context") == ctx1)
	player.queue_free()
	await get_tree().physics_frame

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
