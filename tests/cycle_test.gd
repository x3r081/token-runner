extends Node
## Regression tests for the "Ship Before Reset" cycle system: cycle advancement,
## quota refill, debt reckoning, vendor price shifts (which flow into upgrade
## costs), the reset warning, and that the timer only ticks while PLAYING.
##
## Run: godot --headless --path . --scene tests/cycle_test.tscn

var passed := 0
var failed := 0

func _ready() -> void:
	_run()
	print("CYCLE TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	ResourceManager.reset()
	DreamAppManager.reset()
	CycleManager.reset()

	_check("starts_at_cycle_1", CycleManager.cycle == 1)
	_check("starts_full_timer", abs(CycleManager.time_left - CycleManager.CYCLE_LENGTH) < 0.01)
	_check("starts_price_index_1", abs(CycleManager.price_index - 1.0) < 0.001)

	# end_cycle effects
	ResourceManager.resources["compute"] = 0
	ResourceManager.resources["stability"] = 80
	ResourceManager.resources["technical_debt"] = 60
	var reset_fired := [0]
	var cb := func(_c): reset_fired[0] += 1
	CycleManager.reset_triggered.connect(cb)
	CycleManager.end_cycle()
	CycleManager.reset_triggered.disconnect(cb)
	_check("cycle_advances", CycleManager.cycle == 2)
	_check("timer_refills", abs(CycleManager.time_left - CycleManager.CYCLE_LENGTH) < 0.01)
	_check("reset_signal_fired", reset_fired[0] == 1)
	_check("compute_quota_refills", ResourceManager.get_value("compute") >= 20.0)
	_check("debt_reckoning_hits_stability", ResourceManager.get_value("stability") < 80.0)
	_check("price_index_shifts", abs(CycleManager.price_index - 1.0) > 0.001)

	# Vendor price index flows into upgrade costs.
	ResourceManager.reset()  # debt 0 so only price matters
	CycleManager.price_index = 1.0
	var c1 := _sum(DreamAppManager.get_effective_cost("frontend"))
	CycleManager.price_index = 2.0
	var c2 := _sum(DreamAppManager.get_effective_cost("frontend"))
	_check("price_index_raises_costs (%d -> %d)" % [c1, c2], c2 > c1)

	# Reset warning fires as the deadline approaches.
	CycleManager.reset()
	GameManager.state = GameManager.GameState.PLAYING
	CycleManager.time_left = CycleManager.WARN_AT + 0.05
	var warned := [0]
	var wcb := func(_s): warned[0] += 1
	CycleManager.cycle_warning.connect(wcb)
	CycleManager._process(0.2)
	CycleManager.cycle_warning.disconnect(wcb)
	_check("reset_warning_fires", warned[0] == 1)

	# Timer does not tick outside PLAYING.
	GameManager.state = GameManager.GameState.MENU
	CycleManager.time_left = 42.0
	CycleManager._process(1.0)
	_check("timer_frozen_outside_playing", abs(CycleManager.time_left - 42.0) < 0.001)

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
