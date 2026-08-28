extends Node
## Regression tests for the deployable-agent system: deploy cost, cycle-reset
## resolution, and that archetype traits produce their signature outcomes
## (junior agents hallucinate and overengineer; agents resolve at RESET).
##
## Run: godot --headless --path . --scene tests/agent_test.tscn

var passed := 0
var failed := 0

func _ready() -> void:
	_run()
	print("AGENT TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	ResourceManager.reset()
	AgentManager.reset()

	# Deploy costs tokens and registers an agent.
	ResourceManager.resources["tokens"] = 50
	var ok := AgentManager.deploy("senior")
	_check("deploy_succeeds", ok)
	_check("deploy_costs_tokens", ResourceManager.get_value("tokens") == 10.0)
	_check("agent_registered", AgentManager.active_count() == 1)

	# Can't deploy when broke.
	var broke := AgentManager.deploy("senior")
	_check("cannot_deploy_when_broke", not broke and AgentManager.active_count() == 1)

	# Resolving clears agents and yields tokens.
	var tokens_before := ResourceManager.get_value("tokens")
	var outcomes := AgentManager.resolve_all()
	_check("resolve_clears_agents", AgentManager.active_count() == 0)
	_check("resolve_returns_outcome", outcomes.size() == 1)
	_check("agent_yields_tokens", ResourceManager.get_value("tokens") > tokens_before)

	# Junior traits over many trials: hallucinates AND overengineers, adds debt.
	var hall := 0
	var over := 0
	var debt_total := 0
	for i in 60:
		ResourceManager.resources["tokens"] = 100
		ResourceManager.resources["technical_debt"] = 0
		AgentManager.reset()
		AgentManager.deploy("junior")
		var outs := AgentManager.resolve_all()
		if outs[0].hallucinated:
			hall += 1
		if outs[0].overengineered:
			over += 1
		debt_total += int(outs[0].debt)
	_check("junior_hallucinates_sometimes (%d/60)" % hall, hall > 0)
	_check("junior_overengineers_often (%d/60)" % over, over > 20)
	_check("agents_accrue_debt (%d)" % debt_total, debt_total > 0)

	# Agents resolve automatically at the cycle RESET.
	ResourceManager.reset()
	ResourceManager.resources["tokens"] = 100
	AgentManager.reset()
	CycleManager.reset()
	AgentManager.deploy("senior")
	_check("agent_deployed_pre_reset", AgentManager.active_count() == 1)
	CycleManager.end_cycle()
	_check("agents_resolve_on_reset", AgentManager.active_count() == 0)

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
