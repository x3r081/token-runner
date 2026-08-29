extends Node
## End-to-end completability test: the game must be winnable. Buying a sensible
## upgrade loadout must satisfy the ship requirements, and triggering the deploy
## must reach the VICTORY state with results. Guards against an unwinnable game.
##
## Run: godot --headless --path . --scene tests/win_test.tscn

var passed := 0
var failed := 0

func _ready() -> void:
	_run()
	print("WIN TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	ResourceManager.reset()
	DreamAppManager.reset()
	CycleManager.reset()
	ArchitectureManager.reset()

	# A realistic full-run resource pool (quest rewards alone exceed this).
	ResourceManager.resources["tokens"] = 6000
	ResourceManager.resources["compute"] = 600
	ResourceManager.resources["api_credits"] = 600
	ResourceManager.resources["reputation"] = 600

	# Buy a shipping loadout: two tiers across the core branches.
	var plan := {
		"infrastructure": 2, "ai": 2, "database": 2,
		"backend": 2, "frontend": 2, "observability": 2, "architecture": 2,
	}
	var bought := 0
	for branch in plan:
		for i in plan[branch]:
			if DreamAppManager.purchase(branch):
				bought += 1
	_check("upgrades_were_purchasable", bought >= 12)

	var totals := DreamAppManager.get_totals()
	_check("meets_feature_requirement (%d)" % totals.features, totals.features >= 15)
	_check("meets_stability_requirement (%d)" % totals.stability, totals.stability >= 8)
	_check("meets_ai_tier", DreamAppManager.get_branch_tier("ai") >= 2)
	_check("meets_infra_tier", DreamAppManager.get_branch_tier("infrastructure") >= 2)
	_check("can_ship", DreamAppManager.can_ship())

	# Deploying reaches VICTORY with results (the roast included).
	GameManager.trigger_victory()
	_check("victory_state", GameManager.state == GameManager.GameState.VICTORY)
	var results := GameManager.get_ship_results()
	_check("results_have_ranking", results.has("ranking") and results.ranking != "")
	_check("ship_it_achievement", AchievementManager.is_unlocked("ship_it"))

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
