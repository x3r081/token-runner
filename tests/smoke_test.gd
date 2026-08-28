extends Node

const RegionBuilderClass = preload("res://scripts/world/region_builder.gd")

var passed := 0
var failed := 0

func _ready() -> void:
	_run_test("autoloads_init", func(): return GameManager != null and ResourceManager != null)
	_run_test("quest_defs_load", func(): return QuestManager.quest_defs.size() > 0)
	_run_test("upgrade_defs_load", func(): return DreamAppManager.upgrade_defs.size() > 0)
	_run_test("resource_modify", func():
		var before := ResourceManager.get_value("tokens")
		ResourceManager.modify("tokens", 10)
		return ResourceManager.get_value("tokens") == before + 10
	)
	_run_test("quest_start", func():
		QuestManager.reset()
		return QuestManager.get_active_quests().has("hello_localhost")
	)
	_run_test("save_roundtrip", func():
		ResourceManager.modify("tokens", 5)
		SaveManager.save_game(2)
		var tokens := ResourceManager.get_value("tokens")
		ResourceManager.reset()
		var ok := SaveManager.load_game(2)
		return ok and abs(ResourceManager.get_value("tokens") - tokens) < 0.01
	)
	_run_test("dream_app_purchase", func():
		DreamAppManager.reset()
		ResourceManager.reset()
		ResourceManager.modify("tokens", 500)
		return DreamAppManager.purchase("frontend")
	)
	_run_test("region_builder", func():
		var root := Node2D.new()
		var data: Dictionary = RegionBuilderClass.build(root, "localhost")
		var ok: bool = data.has("spawn") and root.get_child_count() > 0
		root.free()
		return ok
	)
	print("SMOKE TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run_test(name: String, fn: Callable) -> void:
	if fn.call():
		print("  PASS: %s" % name)
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1
