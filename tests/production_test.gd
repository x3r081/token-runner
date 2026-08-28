extends Node
## Regression test for the Production incident + the "IT WAS DNS" running gag:
## the proper-investigation path restores stability, and blaming DNS is almost
## always a joke -- except occasionally it really is DNS (unlocks IT WAS DNS).
##
## Run: godot --headless --path . --scene tests/production_test.tscn

const StoryDefs := preload("res://scripts/world/story_events.gd")

var passed := 0
var failed := 0

func _ready() -> void:
	_run()
	print("PRODUCTION TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	# Investigate-properly restores stability and resolves.
	ResourceManager.reset()
	EventManager.reset()
	ResourceManager.resources["stability"] = 50
	EventManager.start_scripted("production_incident", StoryDefs.production_incident())
	_check("incident_starts", EventManager.has_active_event())
	EventManager.resolve(0)  # investigate
	EventManager.resolve(0)  # continue through aftermath
	_check("investigate_restores_stability", ResourceManager.get_value("stability") > 50.0)
	_check("incident_resolves", not EventManager.has_active_event())

	# Blaming DNS: almost always a joke, but occasionally IT WAS DNS.
	AchievementManager.reset()
	var dns_wins := 0
	for i in 150:
		ResourceManager.reset()
		EventManager.reset()
		EventManager.start_scripted("production_incident", StoryDefs.production_incident())
		EventManager.resolve(2)  # Blame DNS (gamble)
		# Either "IT WAS DNS" (win) or "never DNS" (loss); one more resolve ends it.
		EventManager.resolve(0)
		if AchievementManager.is_unlocked("it_was_dns"):
			dns_wins += 1
	_check("blame_dns_sometimes_wins (%d/150)" % dns_wins, dns_wins > 0)
	_check("it_was_dns_unlocked", AchievementManager.is_unlocked("it_was_dns"))

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
