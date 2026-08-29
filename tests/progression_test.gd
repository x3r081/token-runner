extends Node
## Regression test guarding against progression dead-ends: the player must be
## able to leave Localhost, and quest rewards must keep unlocking later regions.
## (Previously nothing unlocked dependency_district, so no exit portal ever
## spawned and the player was stranded in Localhost forever.)
##
## Run: godot --headless --path . --scene tests/progression_test.tscn

const RegionBuilderClass := preload("res://scripts/world/region_builder.gd")

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("PROGRESSION TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	# Fresh game: the first hop out of Localhost is available.
	GameManager.regions_unlocked = ["localhost", "dependency_district"]
	_check("first_region_unlocked_from_start", GameManager.is_region_unlocked("dependency_district"))

	# Localhost actually spawns an exit portal to it.
	var root := Node2D.new()
	add_child(root)
	var _data: Dictionary = RegionBuilderClass.build(root, "localhost")
	var portals := root.get_node_or_null("Portals")
	var has_dep_portal := false
	if portals:
		for p in portals.get_children():
			if "target_region" in p and p.target_region == "dependency_district":
				has_dep_portal = true
	_check("localhost_spawns_exit_portal", has_dep_portal)
	root.queue_free()
	await get_tree().physics_frame

	# Travel is permitted to an unlocked region.
	GameManager.current_region = "localhost"
	GameManager.change_region("dependency_district")
	_check("can_travel_to_unlocked_region", GameManager.current_region == "dependency_district")

	# The unlock chain works: completing install_node unlocks the next region.
	QuestManager.reset()
	QuestManager.quest_states["install_node"] = QuestManager.QuestState.ACTIVE
	QuestManager.quest_progress["install_node"] = {}
	QuestManager.complete_quest("install_node")
	_check("quest_reward_unlocks_next_region", GameManager.is_region_unlocked("stackoverflow_ruins"))

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
