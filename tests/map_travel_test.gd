extends Node
## Regression test for world-map fast-travel: unlocked, non-current regions are
## clickable travel buttons and traveling changes the current region. (Traversing
## 10 regions on foot was tedious and blocked mid/late-game playtesting.)
##
## Run: godot --headless --path . --scene tests/map_travel_test.tscn

const MapScene := preload("res://scenes/ui/map_panel.tscn")

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("MAP TRAVEL TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	GameManager.regions_unlocked = ["localhost", "dependency_district", "stackoverflow_ruins"]
	GameManager.current_region = "localhost"

	var m: Node = MapScene.instantiate()
	add_child(m)
	await get_tree().process_frame

	var list := m.get_node("Margin/VBox/RegionList")
	var buttons := 0
	for c in list.get_children():
		if c is Button:
			buttons += 1
	# Two unlocked non-current regions => two travel buttons.
	_check("unlocked_regions_are_travel_buttons (%d)" % buttons, buttons == 2)

	m._travel("dependency_district")
	_check("fast_travel_changes_region", GameManager.current_region == "dependency_district")
	_check("map_closes_after_travel", not is_instance_valid(m) or m.is_queued_for_deletion())

	# Traveling to a locked region is refused.
	GameManager.current_region = "localhost"
	var m2: Node = MapScene.instantiate()
	add_child(m2)
	await get_tree().process_frame
	m2._travel("token_vault")  # locked
	_check("locked_region_travel_refused", GameManager.current_region == "localhost")

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
