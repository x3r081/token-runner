extends Node
## Regression test for the screen-space overlay bug: full-screen overlays (pause,
## death, victory) were added as children of the world Node2D, so they rendered
## in WORLD space at (0,0) and ended up off-screen wherever the camera was — the
## pause menu appeared to do nothing, and the victory/death screens were invisible.
## Overlays must live under the HUD CanvasLayer (screen space).
##
## Run: godot --headless --path . --scene tests/ui_overlay_test.tscn

const WorldScene := preload("res://scenes/world/world.tscn")

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("UI OVERLAY TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	GameManager.show_opening_sequence = false
	GameManager.current_region = "localhost"
	GameManager.regions_unlocked = ["localhost", "dependency_district"]
	GameManager.state = GameManager.GameState.PLAYING

	var world: Node = WorldScene.instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	_check("hud_is_canvaslayer", world.hud is CanvasLayer)

	# Pause overlay must land under the HUD CanvasLayer, not the world Node2D.
	world._open_pause()
	var pm: Node = world.hud.get_node_or_null("PauseMenu")
	_check("pause_menu_exists", pm != null)
	_check("pause_menu_under_canvaslayer", pm != null and pm.get_parent() is CanvasLayer)
	GameManager.pause_game(false)

	# show_overlay (used by victory) also routes to screen space.
	var probe := Control.new()
	world.show_overlay(probe)
	_check("overlay_under_canvaslayer", probe.get_parent() is CanvasLayer)

	world.queue_free()
	await get_tree().process_frame

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
