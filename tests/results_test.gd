extends Node
## Regression test for the personalized ship-results roast: it must reflect the
## actual choices made this run (architecture, debt, backups, deaths, DNS).
##
## Run: godot --headless --path . --scene tests/results_test.tscn

var passed := 0
var failed := 0

func _ready() -> void:
	_run()
	print("RESULTS TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	ResourceManager.reset()
	ArchitectureManager.reset()
	AchievementManager.reset()
	GameManager.story_flags.clear()
	GameManager.death_count = 6

	ArchitectureManager.flags = {
		"structure": "microservices", "testing": "later", "security": "velocity",
		"hosting": "cloud", "database": "nosql",
	}
	ArchitectureManager.ridiculousness = 10
	ResourceManager.resources["technical_debt"] = 90
	AchievementManager.unlock("it_was_dns")

	var roast := " || ".join(GameManager.get_ship_roast())
	_check("roasts_debt", roast.contains("Series B"))
	_check("roasts_microservices", roast.contains("microservices"))
	_check("roasts_missing_tests", roast.to_lower().contains("tests"))
	_check("roasts_security", roast.contains("Security Engineer"))
	_check("roasts_cloud", roast.to_lower().contains("cloud"))
	_check("roasts_nosql", roast.contains("NoSQL"))
	_check("roasts_no_backups", roast.contains("No backups"))
	_check("roasts_deaths", roast.contains("6 times"))
	_check("roasts_dns", roast.contains("DNS"))
	_check("roasts_ridiculousness", roast.contains("MAXIMUM"))

	# With backups, the roast flips to grudging respect.
	GameManager.set_flag("backups", true)
	var roast2 := " || ".join(GameManager.get_ship_roast())
	_check("backups_flip_roast", roast2.contains("responsible") and not roast2.contains("No backups"))

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
