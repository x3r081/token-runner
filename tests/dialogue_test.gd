extends Node
## Regression tests for Claude's reactive, memory-driven dialogue and the backups
## running-gag callback (make backups -> a later disaster becomes trivial and
## unlocks Boring Responsible Adult).
##
## Run: godot --headless --path . --scene tests/dialogue_test.tscn

var passed := 0
var failed := 0

func _ready() -> void:
	_run()
	print("DIALOGUE TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	_reset_world()

	# First conversation introduces Claude and counts as a memory.
	var first := DialogueManager.build_claude_lines()
	_check("first_talk_introduces", _joined(first).to_lower().contains("claude"))
	_check("memory_increments", int(DialogueManager.claude_state.talks) == 1)

	# Reactive: microservices architecture provokes a specific barb.
	_reset_world()
	DialogueManager.claude_state.talks = 5
	ArchitectureManager.flags = {"structure": "microservices"}
	var micro := _joined(DialogueManager.build_claude_lines()).to_lower()
	_check("reacts_to_microservices", micro.contains("microservices"))

	# Reactive: high technical debt provokes a debt barb.
	_reset_world()
	DialogueManager.claude_state.talks = 5
	ResourceManager.resources["technical_debt"] = 80
	var debty := _joined(DialogueManager.build_claude_lines()).to_lower()
	_check("reacts_to_high_debt", debty.contains("debt"))

	# Backups gag: without backups he offers to set them up.
	_reset_world()
	DialogueManager.claude_state.talks = 5
	var no_backup := DialogueManager.build_claude_lines()
	_check("offers_backups_choice", _has_action(no_backup, "setup_backups"))

	# Setting up backups costs tokens and sets the flag.
	_reset_world()
	ResourceManager.resources["tokens"] = 50
	DialogueManager._handle_action("setup_backups")
	_check("backups_flag_set", GameManager.get_flag("backups"))
	_check("backups_cost_tokens", ResourceManager.get_value("tokens") == 20.0)

	# With backups he stops nagging and is grudgingly proud.
	DialogueManager.claude_state.talks = 5
	var backed := _joined(DialogueManager.build_claude_lines()).to_lower()
	_check("proud_when_backed_up", backed.contains("proud"))

	# Payoff: a security breach with backups is survivable and earns the achievement.
	_reset_world()
	AchievementManager.reset()
	ArchitectureManager.flags = {"security": "velocity"}
	GameManager.set_flag("backups", true)
	for i in 80:
		ArchitectureManager.apply_delayed()
	_check("backups_unlock_responsible_adult", AchievementManager.is_unlocked("boring_responsible_adult"))

func _reset_world() -> void:
	ResourceManager.reset()
	DialogueManager.reset()
	ArchitectureManager.reset()
	AgentManager.reset()
	CycleManager.reset()
	GameManager.story_flags.clear()
	GameManager.death_count = 0

func _joined(lines: Array) -> String:
	var out := ""
	for l in lines:
		if l is Dictionary and l.has("text"):
			out += " " + str(l.text)
	return out

func _has_action(lines: Array, action: String) -> bool:
	for l in lines:
		if l is Dictionary and l.has("choices"):
			for c in l.choices:
				if c.get("action", "") == action:
					return true
	return false

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
