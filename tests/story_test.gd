extends Node
## Regression test for the staged "comedy-as-mechanics" storyline system and the
## flagship "Just One Tiny Change" quest.
##
## Drives EventManager's scripted storyline through every stage and asserts the
## escalation payoff: big token reward, a pile of technical debt, lost will to
## live, the AGILE achievement, script completion, and quest-chain completion.
##
## Run: godot --headless --path . --scene tests/story_test.tscn

const StoryDefs := preload("res://scripts/world/story_events.gd")

var passed := 0
var failed := 0

func _ready() -> void:
	_run()
	print("STORY TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	ResourceManager.reset()
	QuestManager.reset()
	EventManager.reset()
	AchievementManager.reset()

	# hello_localhost auto-starts; completing it activates tiny_change via chain.
	QuestManager.complete_quest("hello_localhost")
	_check("tiny_change_active_via_chain",
		QuestManager.quest_states.get("tiny_change") == QuestManager.QuestState.ACTIVE)

	var stages := StoryDefs.tiny_change()
	_check("storyline_has_multiple_stages", stages.size() >= 5)

	var tokens0 := ResourceManager.get_value("tokens")
	var debt0 := ResourceManager.get_value("technical_debt")
	var wtl0 := ResourceManager.get_value("will_to_live")

	EventManager.start_scripted("tiny_change", stages)
	_check("storyline_started", EventManager.has_active_event())

	# Walk every stage by always taking the first choice. Guard against loops.
	var steps := 0
	while EventManager.has_active_event() and steps < 50:
		EventManager.resolve(0)
		steps += 1
	_check("storyline_resolves_to_end", not EventManager.has_active_event())

	var dtokens := ResourceManager.get_value("tokens") - tokens0
	var ddebt := ResourceManager.get_value("technical_debt") - debt0
	var dwtl := ResourceManager.get_value("will_to_live") - wtl0

	# Token gain can be nibbled by the rare "funny price hike"; assert a large
	# gain rather than an exact one to stay deterministic.
	_check("gained_big_token_reward (+%.0f)" % dtokens, dtokens >= 100.0)
	_check("gained_technical_debt (+%.0f)" % ddebt, ddebt == 43.0)
	_check("lost_will_to_live (%.0f)" % dwtl, dwtl == -12.0)
	_check("unlocked_agile_achievement", AchievementManager.is_unlocked("agile"))
	_check("script_marked_completed", EventManager.is_script_completed("tiny_change"))
	_check("quest_completed", QuestManager.is_completed("tiny_change"))
	_check("chained_next_quest_started",
		QuestManager.quest_states.get("install_node") == QuestManager.QuestState.ACTIVE)

	_run_free_tier()
	_run_autonomous_agent()

func _run_free_tier() -> void:
	EventManager.reset()
	AchievementManager.reset()
	var tokens0 := ResourceManager.get_value("tokens")
	EventManager.start_scripted("free_tier", StoryDefs.free_tier())
	_check("free_tier_started", EventManager.has_active_event())
	var steps := 0
	while EventManager.has_active_event() and steps < 50:
		EventManager.resolve(0)
		steps += 1
	# Net token change should be small (10000 gifted, 9970 reclaimed).
	var dtokens := ResourceManager.get_value("tokens") - tokens0
	_check("free_tier_net_tokens_small (%.0f)" % dtokens, dtokens <= 100.0)
	_check("free_tier_achievement", AchievementManager.is_unlocked("free_tier_victim"))
	_check("free_tier_completed", EventManager.is_script_completed("free_tier"))

func _run_autonomous_agent() -> void:
	EventManager.reset()
	var debt0 := ResourceManager.get_value("technical_debt")
	var wtl0 := ResourceManager.get_value("will_to_live")
	EventManager.start_scripted("autonomous_agent", StoryDefs.autonomous_agent())
	_check("agent_started", EventManager.has_active_event())
	# Take the careful-review path (choice 0) at every branch.
	var steps := 0
	while EventManager.has_active_event() and steps < 50:
		EventManager.resolve(0)
		steps += 1
	_check("agent_added_debt (+%.0f)" % (ResourceManager.get_value("technical_debt") - debt0),
		ResourceManager.get_value("technical_debt") - debt0 == 18.0)
	_check("agent_cost_will_to_live (%.0f)" % (ResourceManager.get_value("will_to_live") - wtl0),
		ResourceManager.get_value("will_to_live") - wtl0 == -8.0)
	_check("agent_completed", EventManager.is_script_completed("autonomous_agent"))

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
