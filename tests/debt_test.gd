extends Node
## Regression tests for systemic technical-debt consequences: debt raises upgrade
## costs, drains stability over the safe threshold, and can break dependencies
## (spawn bugs). Below the threshold, debt is harmless (strategically fine).
##
## Run: godot --headless --path . --scene tests/debt_test.tscn

var passed := 0
var failed := 0

func _ready() -> void:
	_run()
	print("DEBT TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	ResourceManager.reset()
	DreamAppManager.reset()

	# 1. Upgrade cost scales with debt.
	ResourceManager.resources["technical_debt"] = 0
	_check("no_debt_multiplier_is_1", abs(DreamAppManager.debt_cost_multiplier() - 1.0) < 0.001)
	var base_cost := _sum(DreamAppManager.get_effective_cost("frontend"))
	ResourceManager.resources["technical_debt"] = 100
	_check("high_debt_multiplier_grows", DreamAppManager.debt_cost_multiplier() > 1.3)
	var debt_cost := _sum(DreamAppManager.get_effective_cost("frontend"))
	_check("debt_raises_upgrade_cost (%d -> %d)" % [base_cost, debt_cost], debt_cost > base_cost)

	# 2. Stability drains above the safe threshold.
	ResourceManager.reset()
	ResourceManager.resources["stability"] = 80
	ResourceManager.resources["technical_debt"] = 100
	GameManager.apply_debt_consequences()
	_check("high_debt_drains_stability", ResourceManager.get_value("stability") < 80.0)

	# 3. Low debt is harmless.
	ResourceManager.resources["stability"] = 80
	ResourceManager.resources["technical_debt"] = 5
	GameManager.apply_debt_consequences()
	_check("low_debt_is_safe", ResourceManager.get_value("stability") == 80.0)

	# 4. Very high debt breaks dependencies (fires an incident).
	var incidents := [0]
	var cb := func(_k): incidents[0] += 1
	GameManager.debt_incident.connect(cb)
	ResourceManager.resources["technical_debt"] = 320  # over/300 -> max break chance
	for i in 60:
		GameManager.apply_debt_consequences()
	GameManager.debt_incident.disconnect(cb)
	_check("high_debt_breaks_dependencies (%d incidents)" % incidents[0], incidents[0] > 0)

func _sum(d: Dictionary) -> int:
	var t := 0
	for k in d:
		t += int(d[k])
	return t

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
