extends Node
## Regression tests for Dream App architecture decisions: immediate effects,
## ridiculousness accumulation, delayed consequences (including at cycle reset),
## and the pending-decision menu.
##
## Run: godot --headless --path . --scene tests/architecture_test.tscn

var passed := 0
var failed := 0

func _ready() -> void:
	_run()
	print("ARCHITECTURE TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	ResourceManager.reset()
	ArchitectureManager.reset()

	# Immediate effects + flag + ridiculousness.
	var debt0 := ResourceManager.get_value("technical_debt")
	ArchitectureManager.choose("structure", "microservices")
	_check("decision_recorded", ArchitectureManager.flags.get("structure") == "microservices")
	_check("immediate_debt_applied", ResourceManager.get_value("technical_debt") == debt0 + 8.0)
	_check("reputation_applied", ResourceManager.get_value("reputation") == 5.0)
	_check("ridiculousness_grows", ArchitectureManager.ridiculousness == 3)

	# "We'll add tests later" — fast tokens now, stability + debt cost.
	var tok0 := ResourceManager.get_value("tokens")
	var stab0 := ResourceManager.get_value("stability")
	ArchitectureManager.choose("testing", "later")
	_check("tests_later_gives_tokens", ResourceManager.get_value("tokens") == tok0 + 25.0)
	_check("tests_later_hurts_stability", ResourceManager.get_value("stability") == stab0 - 4.0)

	# Delayed consequences: cloud invoice + microservice flakiness.
	ArchitectureManager.choose("hosting", "cloud")
	var tok1 := ResourceManager.get_value("tokens")
	var stab1 := ResourceManager.get_value("stability")
	ArchitectureManager.apply_delayed()
	_check("cloud_bill_delayed", ResourceManager.get_value("tokens") == tok1 - 12.0)
	_check("microservices_delayed_stability", ResourceManager.get_value("stability") <= stab1 - 2.0)

	# Delayed consequences also fire automatically at the cycle RESET.
	ResourceManager.reset()
	ResourceManager.resources["tokens"] = 100
	ArchitectureManager.reset()
	ArchitectureManager.choose("hosting", "cloud")
	CycleManager.reset()
	var tok_pre := ResourceManager.get_value("tokens")
	CycleManager.end_cycle()
	_check("delayed_fires_on_reset", ResourceManager.get_value("tokens") == tok_pre - 12.0)

	# Menu lists pending decisions, then collapses when all are decided.
	ArchitectureManager.reset()
	_check("menu_lists_all_pending", ArchitectureManager.menu_stages().size() == ArchitectureManager.DECISIONS.size())
	for d in ArchitectureManager.DECISIONS:
		ArchitectureManager.choose(d.id, d.a.id)
	var final_menu := ArchitectureManager.menu_stages()
	_check("menu_collapses_when_done", final_menu.size() == 1 and final_menu[0].title == "ARCHITECTURE")

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
