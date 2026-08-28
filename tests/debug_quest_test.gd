extends Node
## Regression tests for the branching Debugging Investigation: distinct endings
## (proper fix vs hotfix), and the AI-diagnosis branch whose reliability depends
## on the selected model (a cheap model can hallucinate and send you down the
## failure path).
##
## Run: godot --headless --path . --scene tests/debug_quest_test.tscn

const StoryDefs := preload("res://scripts/world/story_events.gd")

var passed := 0
var failed := 0

func _ready() -> void:
	_run()
	print("DEBUG QUEST TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	# Proper-fix ending: stability up, big reward, IT-CAN-EXPLAIN achievement.
	_fresh()
	AchievementManager.reset()
	var stab0 := ResourceManager.get_value("stability")
	var tok0 := ResourceManager.get_value("tokens")
	_start()
	EventManager.resolve(0)  # read logs
	EventManager.resolve(0)  # trace it yourself
	EventManager.resolve(0)  # proper fix
	EventManager.resolve(0)  # claim reward
	_check("proper_fix_raises_stability", ResourceManager.get_value("stability") > stab0)
	_check("proper_fix_nets_tokens", ResourceManager.get_value("tokens") > tok0)
	_check("proper_fix_achievement", AchievementManager.is_unlocked("i_can_explain"))
	_check("proper_fix_resolves", not EventManager.has_active_event())

	# Hotfix ending: technical debt up, no achievement.
	_fresh()
	AchievementManager.reset()
	var debt0 := ResourceManager.get_value("technical_debt")
	_start()
	EventManager.resolve(0)  # read logs
	EventManager.resolve(0)  # trace
	EventManager.resolve(1)  # quick hotfix
	EventManager.resolve(0)  # ship it
	_check("hotfix_adds_debt", ResourceManager.get_value("technical_debt") > debt0)
	_check("hotfix_no_achievement", not AchievementManager.is_unlocked("i_can_explain"))
	_check("hotfix_resolves", not EventManager.has_active_event())

	# AI diagnosis with a reliable model reaches the real root cause.
	ModelManager.set_model("frontier")
	var reached_root := false
	for i in 6:
		_fresh()
		_start()
		EventManager.resolve(0)  # read logs
		EventManager.resolve(1)  # ask the AI
		EventManager.resolve(0)  # trust diagnosis (ai_gamble)
		if int(EventManager.active_event.get("stage", -1)) == 4:
			reached_root = true
	_check("frontier_model_diagnoses_reliably", reached_root)

	# A cheap model eventually hallucinates and lands on the failure path.
	ModelManager.set_model("local")
	var hallucinated := false
	for i in 50:
		_fresh()
		_start()
		EventManager.resolve(0)
		EventManager.resolve(1)
		EventManager.resolve(0)
		if int(EventManager.active_event.get("stage", -1)) == 8:
			hallucinated = true
			break
	_check("cheap_model_can_hallucinate", hallucinated)

func _fresh() -> void:
	ResourceManager.reset()
	EventManager.reset()

func _start() -> void:
	EventManager.start_scripted("debugging_investigation", StoryDefs.debugging_investigation())

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
