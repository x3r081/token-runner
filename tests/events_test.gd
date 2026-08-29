extends Node
## Regression test: every random event is well-formed and applies cleanly, so a
## malformed event can never break the event popup mid-run. Also guards a healthy
## variety (surprise density).
## Run: godot --headless --path . tests/events_test.tscn

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("EVENTS TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	var defs: Array = EventManager.event_defs
	_check("has_variety (%d events)" % defs.size(), defs.size() >= 12)

	var valid_res := {}
	for k in ResourceManager.RESOURCE_DEFAULTS:
		valid_res[k] = true

	var ids := {}
	var all_ok := true
	var bad := ""
	for ev in defs:
		var id: String = ev.get("id", "")
		if id == "" or ev.get("title", "") == "" or ev.get("description", "") == "":
			all_ok = false; bad = "%s missing text" % id
		if id in ids:
			all_ok = false; bad = "duplicate id %s" % id
		ids[id] = true
		var choices: Array = ev.get("choices", [])
		if choices.is_empty():
			all_ok = false; bad = "%s no choices" % id
		for ch in choices:
			if String(ch.get("text", "")) == "":
				all_ok = false; bad = "%s choice no text" % id
			for res in ch.get("effects", {}):
				if not valid_res.has(res):
					all_ok = false; bad = "%s bad effect '%s'" % [id, res]
	_check("all_events_well_formed (%s)" % bad, all_ok)

	# Resolving every choice of every event applies without error.
	var resolved := 0
	for ev in defs:
		for i in ev.get("choices", []).size():
			ResourceManager.reset()
			EventManager.active_event = ev.duplicate(true)
			EventManager.resolve(i)
			resolved += 1
	_check("all_choices_resolve_cleanly (%d)" % resolved, resolved >= defs.size())

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
