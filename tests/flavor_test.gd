extends Node
## Regression test for environmental comedy props: every FLAVOR entry is placed in
## Localhost, interacting spawns a styled FlavorPopup, and it closes on input.
## Run: godot --headless --path . tests/flavor_test.tscn

const Generic := preload("res://scripts/world/generic_interactable.gd")

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("FLAVOR TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	GameManager.current_region = "localhost"
	GameManager.show_opening_sequence = false
	GameManager.state = GameManager.GameState.PLAYING
	var world: Node = preload("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	for i in 5:
		await get_tree().physics_frame

	# Localhost's own props (kitchen/bedroom/battlestation flavor).
	const LOCALHOST_PROPS := ["prop_fridge", "prop_coffee", "prop_plant", "prop_bed",
		"prop_server", "prop_whiteboard", "prop_terminal", "prop_router",
		"prop_monitors", "prop_sticker"]
	var placed: Array = []
	for n in _all(world):
		if n.get("interact_id") != null and String(n.interact_id).begins_with("prop_"):
			placed.append(n.interact_id)
	var missing: Array = []
	for id in LOCALHOST_PROPS:
		if id not in placed:
			missing.append(id)
	_check("localhost_props_placed (%d)" % placed.size(), missing.is_empty())
	# Every FLAVOR id must be text-complete (title + body).
	var bad: Array = []
	for id in Generic.FLAVOR:
		var f: Array = Generic.FLAVOR[id]
		if f.size() < 2 or String(f[0]).is_empty() or String(f[1]).length() < 8:
			bad.append(id)
	_check("all_flavor_text_complete (%d entries)" % Generic.FLAVOR.size(), bad.is_empty())

	# Interacting with a prop spawns a FlavorPopup with the right text.
	var fridge: Node = null
	for n in _all(world):
		if n.get("interact_id") == "prop_fridge":
			fridge = n
			break
	_check("fridge_prop_exists", fridge != null)
	if fridge:
		fridge.interact(get_tree().get_first_node_in_group("player"))
		await get_tree().process_frame
		var popup := _find_popup(get_tree().root)
		_check("interacting_spawns_flavor_popup", popup != null)
		if popup:
			_check("popup_has_fridge_title", popup.title_text == "Fridge")
			_check("popup_body_nonempty", popup.body_text.length() > 10)
			# Flavor popup pauses the game so you can't die while reading a joke.
			_check("flavor_popup_pauses_game", get_tree().paused == true)
			popup.queue_free()
			await get_tree().process_frame
			_check("flavor_popup_unpauses_on_close", get_tree().paused == false)

	# Region flavor props are placed in their regions (spot-check a few).
	const RB := preload("res://scripts/world/region_builder.gd")
	for check in [["dependency_district", "prop_node_modules"], ["production", "prop_runbook"],
			["cloud_district", "prop_invoice"], ["open_source_wildlands", "prop_sponsor"]]:
		var root := Node2D.new()
		add_child(root)
		RB.build(root, check[0])
		var found := false
		for n in _all(root):
			if n.get("interact_id") == check[1]:
				found = true
				break
		_check("%s_has_%s" % [check[0], check[1]], found)
		root.queue_free()
		await get_tree().process_frame

func _all(n: Node, out: Array = []) -> Array:
	out.append(n)
	for c in n.get_children():
		_all(c, out)
	return out

func _find_popup(root: Node) -> Node:
	for n in _all(root):
		if n.get_script() and n.get("title_text") != null and n.get("body_text") != null:
			return n
	return null

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
