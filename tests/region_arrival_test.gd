extends Node
## Regression test: arriving in (or respawning into) a region must be safe — no
## enemy should spawn within the enemy aggro radius (340) of the region spawn, so
## fast-travel/respawn never drops the player into an instant swarm.
## Run: godot --headless --path . tests/region_arrival_test.tscn

const RB := preload("res://scripts/world/region_builder.gd")
const AGGRO := 340.0

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("REGION ARRIVAL TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	for rid in ["dependency_district", "api_bazaar", "gpu_mines", "stackoverflow_ruins",
			"cloud_district", "open_source_wildlands", "corporate_enterprise", "production"]:
		var root := Node2D.new()
		add_child(root)
		var data: Dictionary = RB.build(root, rid)
		var spawn: Vector2 = data.spawn
		var mind := INF
		for e in get_tree().get_nodes_in_group("enemy"):
			mind = minf(mind, spawn.distance_to(e.global_position))
		_check("%s_arrival_safe (min=%.0f)" % [rid, mind], mind > AGGRO)
		root.queue_free()
		await get_tree().process_frame

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
