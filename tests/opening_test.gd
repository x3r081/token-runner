extends Node
## Regression test for the intro soft-lock: the boot sequence must ALWAYS hand
## control back to the player, even if the "press any key" input is never given.
## (A stuck intro left can_move=false — movement/dash/interact all gate on it.)
##
## Run: godot --headless --path . --scene tests/opening_test.tscn

const OpeningScene := preload("res://scenes/ui/opening_sequence.tscn")

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("OPENING TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	var intro: Node = OpeningScene.instantiate()
	var finished := [false]
	add_child(intro)
	intro.sequence_finished.connect(func(): finished[0] = true)
	await get_tree().process_frame

	# Simulate ~20s of the intro running with ZERO input; it must auto-finish.
	for i in 24:
		if is_instance_valid(intro) and not finished[0]:
			intro._process(1.0)
		await get_tree().process_frame

	_check("intro_auto_finishes_without_input", finished[0])
	_check("intro_frees_itself", not is_instance_valid(intro))

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
